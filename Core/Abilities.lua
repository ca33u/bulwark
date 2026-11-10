--[[
  Bulwark core: ability icons ("ready group") with cooldowns.

  An icon is shown only when the ability is known (confirmed) and enabled
  in the options. Cooldowns come from C_Spell.GetSpellCooldown when it is
  readable. When it is hidden (secret), a local timer runs from the
  player's own cast with the base cooldown adjusted by talents, and the
  last confirmed value is kept.
]]

local ADDON_NAME, ns = ...
ns = ns or {}
local G, S, W, T = ns.G, ns.Spells, ns.W, ns.T

local AB = {}
ns.Abilities = AB

------------------------------------------------------------------------
-- Cooldown math (pure, unit-tested)
------------------------------------------------------------------------

local PURIFYING = { [0] = 0, [1] = 0.17, [2] = 0.33 }

-- Base cooldown of an ability after talents. ranks: talent key -> rank.
function AB.BaseCooldown(key, ranks)
	local spell = S.Get(key)
	if not spell or not spell.cd then
		return nil
	end
	ranks = ranks or {}
	local cd = spell.cd
	if key == "judgement" then
		cd = cd - 1 * (ranks.improved_judgement or 0)
	elseif key == "holy_strike" then
		cd = cd - 4 * (ranks.shieldsworn or 0)
	elseif key == "divine_shield" or key == "divine_protection" or key == "templar_bulwark" then
		cd = cd - 30 * (ranks.sacred_duty or 0)
	elseif key == "bop" then
		cd = cd - 60 * (ranks.guardians_favor or 0)
	elseif key == "hammer_of_justice" then
		cd = cd - 5 * (ranks.improved_hoj or 0)
	elseif key == "exorcism" or key == "holy_wrath" then
		local r = math.min(2, math.max(0, ranks.purifying_power or 0))
		cd = cd * (1 - PURIFYING[r])
	end
	return math.max(0, cd)
end

-- entry: { confStart, confDur, castStart, castDur }
-- read: { status = "ok", start, duration } or { status = "hidden" }
-- Returns remaining seconds (0 = ready) and the start/duration in use.
function AB.Resolve(entry, read, now)
	if read and read.status == "ok" then
		local start, dur = read.start or 0, read.duration or 0
		if dur > 1.5 and start > 0 then
			entry.confStart, entry.confDur = start, dur
			local rem = start + dur - now
			if rem > 0 then
				return rem, start, dur
			end
			return 0
		end
		-- Ready (or only the global cooldown): the API is the truth.
		entry.confStart, entry.confDur = nil, nil
		entry.castStart, entry.castDur = nil, nil
		return 0
	end
	-- Hidden: the most recent of the cast timer and the last confirmed value.
	local start, dur
	if entry.confStart and entry.confDur then
		start, dur = entry.confStart, entry.confDur
	end
	if entry.castStart and entry.castDur and (not start or entry.castStart > start) then
		start, dur = entry.castStart, entry.castDur
	end
	if not start then
		return 0
	end
	local rem = start + dur - now
	if rem > 0 then
		return rem, start, dur
	end
	return 0
end

-- Guarded cooldown read for a spell ID.
function AB.ReadCooldown(id)
	if not id or G.CooldownsSecret() then
		return { status = "hidden" }
	end
	local api = _G.C_Spell
	if type(api) == "table" and type(api.GetSpellCooldown) == "function" then
		local ok, info = pcall(api.GetSpellCooldown, id)
		if not ok or info == nil or G.IsSecret(info) then
			return { status = "hidden" }
		end
		local start = G.Num(G.Field(info, "startTime"))
		local dur = G.Num(G.Field(info, "duration"))
		if start == nil or dur == nil then
			return { status = "hidden" }
		end
		return { status = "ok", start = start, duration = dur }
	end
	local r = G.ReadAll(_G.GetSpellCooldown, id)
	if not r or r.hidden or G.Num(r[1]) == nil or G.Num(r[2]) == nil then
		return { status = "hidden" }
	end
	return { status = "ok", start = r[1], duration = r[2] }
end

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------

AB.entries = {}

local function Entry(key)
	local e = AB.entries[key]
	if not e then
		e = {}
		AB.entries[key] = e
	end
	return e
end

function AB.OnCast(key, now)
	local cd = AB.BaseCooldown(key, S.ranks)
	if cd and cd > 0 then
		local e = Entry(key)
		e.castStart, e.castDur = now, cd
	end
end

-- Judgement needs an active seal: without one the icon is dimmed.
-- Only a confirmed "no seal" dims it; a hidden read leaves it bright.
AB.NEEDS_SEAL = { judgement = true, swift_judgement = true }
function AB.NeedsSeal(key)
	return AB.NEEDS_SEAL[key] and ns.Auras.SealStatus() == "absent" or false
end

-- Abilities locked by Forbearance.
function AB.LockedByForbearance(key)
	local spell = S.Get(key)
	return spell and spell.forbearance and ns.Auras.Status("forbearance") == "present" or false
end

------------------------------------------------------------------------
-- Icons
------------------------------------------------------------------------

local group = CreateFrame("Frame", "BulwarkAbilities", UIParent)
group:SetFrameStrata("MEDIUM")
group:SetSize(32, 32)
group:SetClampedToScreen(true)
AB.frame = group

local buttons = {}

local function Button(i)
	local b = buttons[i]
	if b then
		return b
	end
	b = CreateFrame("Frame", nil, group)
	b.border = b:CreateTexture(nil, "BACKGROUND")
	b.border:SetAllPoints()
	b.border:SetColorTexture(0, 0, 0, 1)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local ok, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
	if ok and cd then
		cd:SetAllPoints(b.icon)
		G.Call(cd.SetHideCountdownNumbers, cd, true)
		G.Call(cd.SetDrawEdge, cd, false)
		b.cd = cd
	end
	b.lock = b:CreateTexture(nil, "OVERLAY")
	b.lock:SetAllPoints(b.icon)
	b.lock:SetColorTexture(0.8, 0.05, 0.05, 0.45)
	b.lock:Hide()
	b.text = W.Text(b, nil, 13)
	b.text:SetPoint("CENTER", 0, 0)
	b:EnableMouse(false)
	b:SetScript("OnEnter", function(self)
		if not self.key then
			return
		end
		local lines = {}
		if self.locked then
			lines[#lines + 1] = T("Locked out by Forbearance: immunities cannot be used while it is on you.")
		end
		if self.noSeal then
			lines[#lines + 1] = T("Needs an active seal.")
		end
		if self.remaining and self.remaining > 0 then
			lines[#lines + 1] = string.format(T("Ready in %s"), ns.Line.FormatTime(self.remaining))
		else
			lines[#lines + 1] = T("Ready")
		end
		W.ShowTip(self, S.DisplayName(self.key), (unpack or table.unpack)(lines))
	end)
	b:SetScript("OnLeave", W.HideTip)
	buttons[i] = b
	return b
end

local ALIGN_POINT = { left = "LEFT", center = "CENTER", right = "RIGHT" }

function AB.Apply()
	local db = ns.DB()
	local point = ALIGN_POINT[db.readyAlign] or "CENTER"
	group:ClearAllPoints()
	-- Offsets are in screen units; the icon size does not follow the line scale.
	group:SetPoint(point, ns.Line.frame, point, db.readyOffX, db.readyOffY)
end

-- Which abilities to show: known and enabled. Pure on the given checks.
function AB.Visible(knownFn, shownFn)
	local out = {}
	for _, key in ipairs(S.READY) do
		if shownFn(key) and knownFn(key) == true then
			out[#out + 1] = key
		end
	end
	return out
end

local SAMPLE = { "judgement", "holy_strike", "holy_shield", "divine_protection" }
local knownCache, knownAt = {}, -10

function AB.Render()
	local db = ns.DB()
	local now = G.Now()
	local movers = ns.Movers
	local preview = movers and (movers.unlocked or movers.testing)
	local state = G.PlayerState()
	local show = preview or (G.IsPaladin() and G.ShouldShow(db, "icons", "abilitiesOnlyInCombat", state))
	if not show then
		group:Hide()
		return
	end

	-- "Known" checks are cheap but not free: refresh them once a second.
	if now - knownAt > 1 then
		knownAt = now
		for _, key in ipairs(S.READY) do
			knownCache[key] = S.IsKnown(key)
		end
	end
	local keys = AB.Visible(function(key)
		return knownCache[key]
	end, ns.IsReadyShown)
	if preview and #keys == 0 then
		keys = SAMPLE
	end

	local size, gap = db.readyIconSize, db.readySpacing
	local n = #keys
	local total = math.max(size, n * size + math.max(0, n - 1) * gap)
	group:SetSize(total, size)
	for i, key in ipairs(keys) do
		local b = Button(i)
		b:SetSize(size, size)
		b:ClearAllPoints()
		local slot = db.readyGrowRight and (i - 1) or (n - i)
		b:SetPoint("LEFT", group, "LEFT", slot * (size + gap), 0)
		b.key = key
		b:EnableMouse(not preview)
		b.icon:SetTexture(S.Icon(key))

		local e = Entry(key)
		local remaining, start, dur = 0, nil, nil
		if movers and movers.testing then
			remaining = (i % 2 == 0) and (6 - (movers.TestElapsed() % 6)) or 0
			start, dur = now - (6 - remaining), 6
		else
			local id = S.KnownID(key)
			remaining, start, dur = AB.Resolve(e, AB.ReadCooldown(id), now)
		end
		b.remaining = remaining
		local locked = not (movers and movers.testing) and AB.LockedByForbearance(key)
		b.locked = locked

		if remaining > 0 then
			b.icon:SetDesaturated(true)
			b.icon:SetVertexColor(0.55, 0.55, 0.55)
			b.text:SetText(ns.Line.FormatTime(remaining))
			if b.cd and (b.cdStart ~= start or b.cdDur ~= dur) then
				b.cdStart, b.cdDur = start, dur
				G.Call(b.cd.SetCooldown, b.cd, start, dur)
			end
		else
			b.icon:SetDesaturated(false)
			b.icon:SetVertexColor(1, 1, 1)
			b.text:SetText("")
			if b.cd and b.cdStart then
				b.cdStart, b.cdDur = nil, nil
				G.Call(b.cd.Clear, b.cd)
			end
		end
		b.lock:SetShown(locked and true or false)
		if locked then
			b.icon:SetDesaturated(true)
		end
		local noSeal = not (movers and movers.testing) and AB.NeedsSeal(key)
		b.noSeal = noSeal
		if noSeal then
			b.icon:SetDesaturated(true)
			b.icon:SetVertexColor(0.4, 0.4, 0.4)
		end
		b:Show()
	end
	for i = n + 1, #buttons do
		buttons[i]:Hide()
		buttons[i].key = nil
	end
	group:SetShown(n > 0)
end

ns.Every(0.1, AB.Render)
ns.On("SPELLS_CHANGED", function()
	knownAt = -10
end)
