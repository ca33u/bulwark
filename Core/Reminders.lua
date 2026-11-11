--[[
  Bulwark core: reminders above the line (Bulwark's own icons with a
  pulsing red frame, or red text if you prefer) and badges.

    Righteous Fury missing   known, and the buff is confirmed absent
    Seal missing             a seal is known, none confirmed on you (any spec)
    Seal timer expired       same, right after a seal ran out by itself
    No aura active           an aura is known and no paladin aura at all is on you
                             (any aura counts: Devotion, Retribution, Concentration,
                             resistance auras, Sanctity)
  Badges: Righteous Fury (with its reminder) and Forbearance (while on you).
  A hidden read never creates a reminder.
]]

local ADDON_NAME, ns = ...
ns = ns or {}
local G, S, W, T = ns.G, ns.Spells, ns.W, ns.T

local R = {}
ns.Reminders = R

------------------------------------------------------------------------
-- Decision (pure, unit-tested)
------------------------------------------------------------------------

-- ctx = {
--   rf   = { enabled, known, status },
--   seal = { enabled, known, status, expired },
--   dev  = { enabled, known, aura },      known: any paladin aura known;
--                                          aura: devotion/resist/other/none/hidden
--   forb = { enabled, status },
--   spec = "PROTECTION" / other / nil (unknown)
-- }
-- Returns a list of { id, text } and the badges { rf = bool, forbearance = bool }.
function R.Decide(ctx)
	local list, badges = {}, { rf = false, forbearance = false }
	local rf = ctx.rf or {}
	if rf.enabled and rf.known == true and rf.status == "absent" then
		list[#list + 1] = { id = "rf", text = T("Righteous Fury missing"), icon = "fury" }
		badges.rf = true
	end
	local seal = ctx.seal or {}
	-- Any spec: Forever's talents often cannot be read, and every paladin
	-- fights with a seal.
	if seal.enabled and seal.known == true and seal.status == "absent" then
		if seal.expired then
			list[#list + 1] = { id = "seal", text = T("Seal timer expired"), icon = "seal", expired = true }
		else
			list[#list + 1] = { id = "seal", text = T("Seal missing"), icon = "seal" }
		end
	end
	local dev = ctx.dev or {}
	-- Any aura is fine; only "no aura at all" is worth a reminder, in any spec.
	if dev.enabled and dev.known == true and dev.aura == "none" then
		list[#list + 1] = { id = "aura", text = T("No aura active"), icon = "aura" }
	end
	local forb = ctx.forb or {}
	if forb.enabled and forb.status == "present" then
		badges.forbearance = true
	end
	return list, badges
end

------------------------------------------------------------------------
-- Live context
------------------------------------------------------------------------

-- true when at least one paladin aura is confirmed known.
local function AnyAuraKnown()
	for _, key in ipairs(S.AURAS) do
		if S.IsKnown(key) == true then
			return true
		end
	end
	return false
end

local function AnySealKnown()
	local answered = false
	for _, key in ipairs(S.SEALS) do
		local known = S.IsKnown(key)
		if known then
			return true
		end
		if known == false then
			answered = true
		end
	end
	return answered and false or nil
end

-- A seal ran out by its timer in the last minute and nothing replaced it.
local function SealExpired(now)
	local last
	for _, key in ipairs(S.SEALS) do
		local e = ns.Auras.ended[key]
		if e and (not last or e.at > last.at) then
			last = e
		end
	end
	return last ~= nil and last.reason == "expired" and now - last.at < 60
end

function R.Context(now)
	local db = ns.DB()
	local A = ns.Auras
	local sealStatus = A.SealStatus()
	-- hidden in combat: fall back to what was readable before, if nothing was cast since
	if sealStatus == "hidden" and A.RememberedNone(S.SEALS) then
		sealStatus = "absent"
	end
	local aura = A.PaladinAura()
	if aura == "hidden" and A.RememberedNone(S.AURAS) then
		aura = "none"
	end
	return {
		spec = S.spec,
		rf = { enabled = db.warnRighteousFury, known = (S.IsKnown("righteous_fury")), status = A.Remembered("righteous_fury") },
		seal = { enabled = db.warnSeal, known = AnySealKnown(), status = sealStatus, expired = SealExpired(now) },
		dev = { enabled = db.warnDevotion, known = AnyAuraKnown(), aura = aura },
		forb = { enabled = db.warnForbearance, status = A.Status("forbearance") },
	}
end

------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------

local warn = CreateFrame("Frame", "BulwarkWarnings", UIParent)
warn:SetFrameStrata("MEDIUM")
warn:SetSize(300, 20)
warn:SetClampedToScreen(true)
warn.text = W.Text(warn, nil, 16)
warn.text:SetPoint("BOTTOM")
warn.text:SetJustifyH("CENTER")
warn:Hide()
R.frame = warn

local ALIGN = { left = "LEFT", center = "CENTER", right = "RIGHT" }

-- Icons: one tile per reminder, centred above the line (Bulwark's own art).
R.ICON_PATH = "Interface\\AddOns\\" .. (ADDON_NAME or "Bulwark") .. "\\Media\\Reminders\\"
local tiles = {}

local function Tile(i)
	if tiles[i] then
		return tiles[i]
	end
	local t = CreateFrame("Frame", nil, warn)
	t.glow = t:CreateTexture(nil, "BACKGROUND")
	t.glow:SetPoint("TOPLEFT", -2, 2)
	t.glow:SetPoint("BOTTOMRIGHT", 2, -2)
	t.glow:SetColorTexture(0.95, 0.15, 0.08, 1)
	t.edge = t:CreateTexture(nil, "BORDER")
	t.edge:SetAllPoints()
	t.edge:SetColorTexture(0, 0, 0, 1)
	t.icon = t:CreateTexture(nil, "ARTWORK")
	t.icon:SetPoint("TOPLEFT", 1, -1)
	t.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	t.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
	t.mark = W.Text(t, nil, 11)
	t.mark:SetPoint("BOTTOMRIGHT", -1, 1)
	t:Hide()
	tiles[i] = t
	return t
end

-- Lays out the icon tiles for the active reminders; returns how many.
function R.ShowIcons(list, now)
	local db = ns.DB()
	local size = math.floor(db.warnSize * 2 + 0.5)
	local gap = math.max(4, math.floor(size / 6))
	local total = #list * size + math.max(0, #list - 1) * gap
	local point = ALIGN[db.warnAlign] or "CENTER"
	-- a slow pulse on the red frame: it catches the eye without words
	local pulse = 0.55 + 0.45 * math.abs(math.sin((now or 0) * 3))
	for i, item in ipairs(list) do
		local t = Tile(i)
		t:SetSize(size, size)
		t:ClearAllPoints()
		if point == "LEFT" then
			t:SetPoint("BOTTOMLEFT", warn, "BOTTOMLEFT", (i - 1) * (size + gap), 0)
		elseif point == "RIGHT" then
			t:SetPoint("BOTTOMRIGHT", warn, "BOTTOMRIGHT", -(#list - i) * (size + gap), 0)
		else
			t:SetPoint("BOTTOMLEFT", warn, "BOTTOM", -total / 2 + (i - 1) * (size + gap), 0)
		end
		t.icon:SetTexture(R.ICON_PATH .. (item.icon or "seal"))
		t.glow:SetAlpha(pulse)
		-- a seal that just ran out gets a small "!"
		W.SetFontSize(t.mark, math.max(10, math.floor(size / 2.6)))
		t.mark:SetText(item.expired and "|cffffd100!|r" or "")
		t:Show()
	end
	for i = #list + 1, #tiles do
		tiles[i]:Hide()
	end
	return #list
end

local function Badge(name, icon, label)
	local b = CreateFrame("Frame", name, UIParent)
	b:SetFrameStrata("MEDIUM")
	b:SetClampedToScreen(true)
	b.border = b:CreateTexture(nil, "BACKGROUND")
	b.border:SetAllPoints()
	b.border:SetColorTexture(0.9, 0.12, 0.08, 1)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 2, -2)
	b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.icon:SetTexture(icon)
	b.label = W.Text(b, nil, 10)
	b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)
	b.label:SetText(label)
	b.label:SetTextColor(1, 0.35, 0.3)
	b.label:Hide() -- the icon says it; the name only while moving badges (/bulwark unlock)
	b.time = W.Text(b, nil, 12)
	b.time:SetPoint("CENTER")
	b:Hide()
	return b
end

local rfBadge = Badge("BulwarkBadgeRF", S.Get("righteous_fury").icon, T("Righteous Fury"))
local forbBadge = Badge("BulwarkBadgeForbearance", S.Get("forbearance").icon, T("Forbearance"))
R.rfBadge, R.forbBadge = rfBadge, forbBadge


function R.Apply()
	local db = ns.DB()
	local c = db.warnColor
	W.SetFontSize(warn.text, db.warnSize)
	warn.text:SetTextColor(c[1], c[2], c[3], c[4])
	local point = ALIGN[db.warnAlign] or "CENTER"
	warn.text:ClearAllPoints()
	warn.text:SetPoint("BOTTOM" .. (point == "CENTER" and "" or point), warn, "BOTTOM" .. (point == "CENTER" and "" or point))
	warn.text:SetJustifyH(point)
	local tall = db.warnIcons and math.floor(db.warnSize * 2 + 0.5) or (db.warnSize + 4)
	warn:SetSize(math.max(200, db.width * db.scale), tall)
	warn:ClearAllPoints()
	warn:SetPoint("BOTTOM", ns.Line.frame, "TOP", db.warnOffX, db.warnOffY)

	for _, pair in ipairs({ { rfBadge, "badgeRFX", "badgeRFY" }, { forbBadge, "badgeForbX", "badgeForbY" } }) do
		local b = pair[1]
		-- same size as the ability icons under the line
		b:SetSize(db.readyIconSize, db.readyIconSize)
		b:ClearAllPoints()
		b:SetPoint("CENTER", UIParent, "CENTER", db[pair[2]], db[pair[3]])
	end
end

R.active = {}

function R.Render()
	local db = ns.DB()
	local now = G.Now()
	local movers = ns.Movers
	local preview = movers and (movers.unlocked or movers.testing)
	local list, badges
	if preview then
		list = { { id = "rf", text = T("Righteous Fury missing"), icon = "fury" }, { id = "seal", text = T("Seal missing"), icon = "seal" }, { id = "aura", text = T("No aura active"), icon = "aura" } }
		badges = { rf = true, forbearance = true }
	elseif G.IsPaladin() and G.ShouldShow(db, "warn", "warningsOnlyInCombat", G.PlayerState()) then
		list, badges = R.Decide(R.Context(now))
	else
		list, badges = {}, { rf = false, forbearance = false }
	end
	R.active = list

	if db.warnIcons then
		warn.text:SetText("")
		R.ShowIcons(list, now)
		warn:SetShown(#list > 0)
	else
		R.ShowIcons({}, now)
		local lines = {}
		for i, item in ipairs(list) do
			lines[i] = item.text
		end
		warn.text:SetText(table.concat(lines, "\n"))
		warn:SetShown(#lines > 0)
	end

	-- The RF icon repeats the red text, so it is off unless asked for.
	rfBadge.label:SetShown(preview and true or false)
	forbBadge.label:SetShown(preview and true or false)
	rfBadge:SetShown(badges.rf and ns.DB().rfBadge and true or false)
	forbBadge:SetShown(badges.forbearance and true or false)
	local fd = ns.Auras.data.forbearance
	local left = fd and fd.expires and fd.expires - now
	forbBadge.time:SetText(left and left > 0 and ns.Line.FormatTime(left) or "")
end

ns.Every(0.25, R.Render)

------------------------------------------------------------------------
-- /bulwark spellcheck
------------------------------------------------------------------------

local function Check(key, reminderOn)
	local name = S.DisplayName(key)
	local byID
	for _, id in ipairs(S.AllIDs(key)) do
		for _, fn in ipairs({ _G.C_SpellBook and _G.C_SpellBook.IsSpellKnown, _G.IsPlayerSpell, _G.IsSpellKnown }) do
			if G.Flag(G.Read(fn, id)) then
				byID = id
				break
			end
		end
		if byID then
			break
		end
	end
	local inBook
	if S.book.ok then
		for _, n in ipairs(S.NamesOf(key)) do
			if S.book.byName[n] then
				inBook = S.book.byName[n]
				break
			end
		end
	end
	print(string.format("  %s: %s %s, %s %s, %s %s", name,
		T("by ID"), byID and ("|cff40ff40" .. byID .. "|r") or "|cffff5040" .. T("no") .. "|r",
		T("in spellbook"), inBook and ("|cff40ff40" .. T("yes") .. "|r") or (S.book.ok and "|cffff5040" .. T("no") .. "|r" or T("unreadable")),
		T("reminder"), ns.OnOff(reminderOn)))
end

function R.SpellCheck()
	local db = ns.DB()
	S.ScanBook()
	ns.Print(T("spell check (spec: %s)"), tostring(S.spec or T("unknown")))
	for _, key in ipairs(S.AURAS) do
		Check(key, db.warnDevotion)
	end
	Check("righteous_fury", db.warnRighteousFury)
	for _, key in ipairs(S.SEALS) do
		Check(key, db.warnSeal)
	end
end
