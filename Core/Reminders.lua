--[[
  Bulwark core: reminders (red text above the line) and badges.

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
		list[#list + 1] = { id = "rf", text = T("Righteous Fury missing") }
		badges.rf = true
	end
	local seal = ctx.seal or {}
	-- Any spec: Forever's talents often cannot be read, and every paladin
	-- fights with a seal.
	if seal.enabled and seal.known == true and seal.status == "absent" then
		if seal.expired then
			list[#list + 1] = { id = "seal", text = T("Seal timer expired") }
		else
			list[#list + 1] = { id = "seal", text = T("Seal missing") }
		end
	end
	local dev = ctx.dev or {}
	-- Any aura is fine; only "no aura at all" is worth a reminder, in any spec.
	if dev.enabled and dev.known == true and dev.aura == "none" then
		list[#list + 1] = { id = "aura", text = T("No aura active") }
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
	return {
		spec = S.spec,
		rf = { enabled = db.warnRighteousFury, known = (S.IsKnown("righteous_fury")), status = A.Status("righteous_fury") },
		seal = { enabled = db.warnSeal, known = AnySealKnown(), status = sealStatus, expired = SealExpired(now) },
		dev = { enabled = db.warnDevotion, known = AnyAuraKnown(), aura = A.PaladinAura() },
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
	b.time = W.Text(b, nil, 12)
	b.time:SetPoint("CENTER")
	b:Hide()
	return b
end

local rfBadge = Badge("BulwarkBadgeRF", S.Get("righteous_fury").icon, T("Righteous Fury"))
local forbBadge = Badge("BulwarkBadgeForbearance", S.Get("forbearance").icon, T("Forbearance"))
R.rfBadge, R.forbBadge = rfBadge, forbBadge

local ALIGN = { left = "LEFT", center = "CENTER", right = "RIGHT" }

function R.Apply()
	local db = ns.DB()
	local c = db.warnColor
	W.SetFontSize(warn.text, db.warnSize)
	warn.text:SetTextColor(c[1], c[2], c[3], c[4])
	local point = ALIGN[db.warnAlign] or "CENTER"
	warn.text:ClearAllPoints()
	warn.text:SetPoint("BOTTOM" .. (point == "CENTER" and "" or point), warn, "BOTTOM" .. (point == "CENTER" and "" or point))
	warn.text:SetJustifyH(point)
	warn:SetSize(math.max(200, db.width * db.scale), db.warnSize + 4)
	warn:ClearAllPoints()
	warn:SetPoint("BOTTOM", ns.Line.frame, "TOP", db.warnOffX, db.warnOffY)

	for _, pair in ipairs({ { rfBadge, "badgeRFX", "badgeRFY" }, { forbBadge, "badgeForbX", "badgeForbY" } }) do
		local b = pair[1]
		b:SetSize(db.badgeSize, db.badgeSize)
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
		list = { { id = "rf", text = T("Righteous Fury missing") }, { id = "seal", text = T("Seal missing") } }
		badges = { rf = true, forbearance = true }
	elseif G.IsPaladin() and G.ShouldShow(db, "warn", "warningsOnlyInCombat", G.PlayerState()) then
		list, badges = R.Decide(R.Context(now))
	else
		list, badges = {}, { rf = false, forbearance = false }
	end
	R.active = list

	local lines = {}
	for i, item in ipairs(list) do
		lines[i] = item.text
	end
	if #lines > 0 then
		warn.text:SetText(table.concat(lines, "\n"))
		warn:Show()
	else
		warn.text:SetText("")
		warn:Hide()
	end

	-- The RF icon repeats the red text, so it is off unless asked for.
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
