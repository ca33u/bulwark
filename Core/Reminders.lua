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
--   bless = { enabled, known, status },     status: any blessing present/absent/hidden
--   spec = "PROTECTION" / other / nil (unknown)
-- }
-- Returns a list of { id, text } and the badges { rf = bool, forbearance = bool }.
-- Which of your cures removes a debuff on you. Pure: cure = {
--   enabled, purify, cleanse (known: true/false/nil),
--   kinds = { Poison = "debuff name", ... }, curable = bool }
-- Cleanse takes Magic, Poison and Disease; Purify only Poison and Disease.
-- Curses: a paladin has no cure, so nothing is shown.
-- Returns spell key, debuff type (or nil when only "curable" is known), debuff name.
function R.Cure(cure)
	if not (cure and cure.enabled) then
		return nil
	end
	local kinds = cure.kinds or {}
	if cure.cleanse == true then
		for _, k in ipairs({ "Magic", "Poison", "Disease" }) do
			if kinds[k] then
				return "cleanse", k, kinds[k]
			end
		end
	end
	if cure.purify == true then
		for _, k in ipairs({ "Poison", "Disease" }) do
			if kinds[k] then
				return "purify", k, kinds[k]
			end
		end
	end
	-- the debuff's fields were hidden, but the game says you can cure it
	if cure.curable then
		if cure.cleanse == true then
			return "cleanse"
		elseif cure.purify == true then
			return "purify"
		end
	end
	return nil
end

R.KIND_TEXT = { Magic = "Magic", Poison = "Poison", Disease = "Disease" }

function R.Decide(ctx)
	local list, badges = {}, { rf = false, forbearance = false }
	-- a debuff you can cure comes first: it is the one to act on now
	local cureKey, kind, debuff = R.Cure(ctx.cure)
	if cureKey then
		list[#list + 1] = { id = "cure", spell = cureKey, kind = kind, debuff = debuff,
			text = string.format(T("Press %s"), S.DisplayName(cureKey)) .. (kind and (" (" .. T(R.KIND_TEXT[kind]) .. ")") or ""),
			texture = S.Get(cureKey).icon }
	end
	local rf = ctx.rf or {}
	if rf.enabled and rf.known == true and rf.status == "absent" then
		-- the game's own Righteous Fury icon: everyone knows it
		list[#list + 1] = { id = "rf", text = T("Righteous Fury missing"), texture = S.Get("righteous_fury").icon }
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
	local bless = ctx.bless or {}
	-- any of your blessings on yourself is fine
	if bless.enabled and bless.known == true and bless.status == "absent" then
		list[#list + 1] = { id = "blessing", text = T("No blessing on yourself"), icon = "blessing" }
	end
	local forb = ctx.forb or {}
	if forb.enabled and forb.status == "present" then
		badges.forbearance = true
	end
	return list, badges
end

------------------------------------------------------------------------
-- Points to spend: talents and Forever's legacy trees
------------------------------------------------------------------------

R.TALENT_ICON = "Interface\\Icons\\INV_Misc_Book_11"
R.LEGACY_ICON = "Interface\\Icons\\INV_Misc_Rune_01"
R.legacy = { searched = false, fn = nil, from = nil, currency = nil, names = {} }

-- Unspent talent points (0 when the game does not say).
function R.TalentPoints()
	local n = G.Read(UnitCharacterPoints, "player")
	if type(n) ~= "number" then
		n = G.Read(GetUnspentTalentPoints)
	end
	return type(n) == "number" and n > 0 and n or 0
end

local WORDS = { "unspent", "available", "remaining", "free", "spendable", "unused" }

-- Does a function name look like "how many legacy points can I spend"?
function R.LooksLikeUnspent(fname)
	local lf = type(fname) == "string" and fname:lower() or ""
	if not lf:find("point") then
		return false
	end
	for _, w in ipairs(WORDS) do
		if lf:find(w) then
			return true
		end
	end
	return false
end

-- Forever does not document how addons read legacy points, so Bulwark
-- looks once: functions with "legacy" in their name (global, or inside a
-- C_ table), then a currency called Legacy. /bulwark legacy shows what
-- it found.
function R.FindLegacy()
	local L = R.legacy
	L.searched, L.names, L.fn, L.from, L.currency = true, {}, nil, nil, nil
	local function Try(label, fname, fn)
		L.names[#L.names + 1] = label
		if not L.fn and R.LooksLikeUnspent(fname) then
			local v = G.Read(fn)
			if type(v) == "number" then
				L.fn, L.from = fn, label
			end
		end
	end
	for name, t in pairs(_G) do
		if type(name) == "string" and name:lower():find("legacy") then
			if type(t) == "function" then
				Try(name, name, t)
			elseif type(t) == "table" and name:find("^C_") then
				for fname, fn in pairs(t) do
					if type(fn) == "function" then
						Try(name .. "." .. fname, fname, fn)
					end
				end
			end
		end
	end
	local CI = C_CurrencyInfo
	if not L.fn and CI and CI.GetCurrencyListSize and CI.GetCurrencyListInfo then
		for i = 1, G.Read(CI.GetCurrencyListSize) or 0 do
			local info = G.Read(CI.GetCurrencyListInfo, i)
			if type(info) == "table" and not info.isHeader and type(info.name) == "string" and info.name:lower():find("legacy") then
				L.currency = i
				L.names[#L.names + 1] = "currency: " .. info.name
				break
			end
		end
	end
	table.sort(L.names)
end

-- Legacy points you can spend now, or nil when the game does not say.
function R.LegacyPoints()
	local L = R.legacy
	if not L.searched then
		R.FindLegacy()
	end
	local v
	if L.fn then
		v = G.Read(L.fn)
	elseif L.currency and C_CurrencyInfo then
		local info = G.Read(C_CurrencyInfo.GetCurrencyListInfo, L.currency)
		v = type(info) == "table" and info.quantity or nil
	end
	return type(v) == "number" and v or nil
end

function R.LegacyReport()
	local L = R.legacy
	R.FindLegacy()
	ns.Print(T("legacy points:") .. " " .. tostring(R.LegacyPoints() or "?") .. (L.from and ("  (" .. L.from .. ")") or ""))
	if #L.names == 0 then
		ns.Print(T("the game shows addons nothing named Legacy."))
	end
	for _, n in ipairs(L.names) do
		ns.Print("  " .. n)
	end
	ns.Print(T("talent points:") .. " " .. R.TalentPoints())
end

-- Tiles for points you have not spent; only out of combat.
function R.PointTiles(ctx)
	local out = {}
	if not ctx.enabled or ctx.combat then
		return out
	end
	if (ctx.talents or 0) > 0 then
		out[#out + 1] = { id = "talents", count = ctx.talents, texture = R.TALENT_ICON,
			text = string.format(T("%d talent points to spend"), ctx.talents) }
	end
	if (ctx.legacy or 0) > 0 then
		out[#out + 1] = { id = "legacy", count = ctx.legacy, texture = R.LEGACY_ICON,
			text = string.format(T("%d legacy points to spend"), ctx.legacy) }
	end
	return out
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

local function AnyKnown(keys)
	for _, key in ipairs(keys) do
		if S.IsKnown(key) == true then
			return true
		end
	end
	return false
end

-- Any of your blessings on you: "present" / "absent" / "hidden" (the last
-- readable state is kept in combat, as for the other reminders).
local function BlessingStatus()
	local hidden = false
	for _, key in ipairs(S.BLESSINGS) do
		local st = ns.Auras.Status(key)
		if st == "present" then
			return "present"
		elseif st == "hidden" then
			hidden = true
		end
	end
	if hidden and not ns.Auras.RememberedNone(S.BLESSINGS) then
		return "hidden"
	end
	return "absent"
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

local function A_Debuffs()
	local A = ns.Auras
	if A and A.Debuffs then
		return A.Debuffs()
	end
	return { kinds = {}, curable = false }
end

local function CureContext(db)
	if not db.warnCleanse then
		return { enabled = false }
	end
	local d = A_Debuffs()
	return { enabled = true, purify = S.IsKnown("purify"), cleanse = S.IsKnown("cleanse"),
		kinds = d.kinds, curable = d.curable }
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
		bless = { enabled = db.warnBlessing, known = AnyKnown(S.BLESSINGS), status = BlessingStatus() },
		cure = CureContext(db),
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

-- Each reminder has its colour from the addicted palette (ns.BRAND):
-- Righteous Fury gold, seal ember, aura tide blue, blessing arcane violet.
R.LOOK = {
	rf = { brand = "gold", title = "Righteous Fury", desc = "Not on you. Without it a tank holds far less threat." },
	seal = { brand = "ember", title = "Seal", desc = "No seal on you. Judgement and much of your damage need one." },
	aura = { brand = "tide", title = "Aura", desc = "No paladin aura active. Any aura counts." },
	blessing = { brand = "arcane", title = "Blessing", desc = "No blessing on yourself. Any of yours counts." },
	cure = { brand = "tide", title = "Cure", desc = "A debuff on you that this spell removes. Press it." },
	talents = { brand = "gold", title = "Talent points", steady = true, desc = "You have talent points to spend. Click to open your talents." },
	legacy = { brand = "arcane", title = "Legacy points", steady = true, desc = "You have legacy points to spend in the legacy trees." },
	forb = { brand = "ember", title = "Forbearance", steady = true,
		desc = "Divine Shield, Divine Protection, Blessing of Protection and Lay on Hands cannot be used on you until it fades." },
}

local function TileEnter(self)
	local item = self.item
	local look = item and R.LOOK[item.id]
	if not look then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	if item.id == "cure" then
		GameTooltip:AddLine(string.format(T("Press %s"), S.DisplayName(item.spell)), 1, 0.82, 0)
		if item.debuff then
			GameTooltip:AddLine(string.format(T("On you: %s (%s)"), item.debuff, T(R.KIND_TEXT[item.kind] or item.kind)), 1, 1, 1, true)
		else
			GameTooltip:AddLine(T("A debuff on you that this spell removes."), 1, 1, 1, true)
		end
		GameTooltip:Show()
		return
	end
	GameTooltip:AddLine(T(look.title), 1, 0.82, 0)
	GameTooltip:AddLine(T(look.desc), 1, 1, 1, true)
	if item.count then
		GameTooltip:AddLine(item.text, 1, 0.82, 0)
	elseif item.id == "forb" then
		local left = item.expires and item.expires - G.Now()
		if left and left > 0 then
			GameTooltip:AddLine(string.format(T("%s left"), ns.Line.FormatTime(left)), 1, 0.3, 0.25)
		end
	else
		GameTooltip:AddLine(T(item.expired and "Ran out" or "Missing"), 1, 0.3, 0.25)
	end
	GameTooltip:Show()
end

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
	t.glow:SetColorTexture(1, 1, 1, 1)
	t.edge = t:CreateTexture(nil, "BORDER")
	t.edge:SetAllPoints()
	t.edge:SetColorTexture(0, 0, 0, 1)
	t.icon = t:CreateTexture(nil, "ARTWORK")
	t.icon:SetPoint("TOPLEFT", 1, -1)
	t.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	t.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
	t.mark = W.Text(t, nil, 11)
	t.mark:SetPoint("BOTTOMRIGHT", -1, 1)
	t.time = W.Text(t, nil, 12)
	t.time:SetPoint("CENTER")
	t:EnableMouse(true)
	t:SetScript("OnEnter", TileEnter)
	t:SetScript("OnLeave", function() GameTooltip:Hide() end)
	t:SetScript("OnMouseUp", function(self)
		if self.item and self.item.id == "talents" and not G.InCombat() then
			G.Call(ToggleTalentFrame)
		end
	end)
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
		t.item = item
		t.icon:SetTexture(item.texture or (R.ICON_PATH .. (item.icon or "seal")))
		local look = R.LOOK[item.id]
		local brand = ns.BRAND or {}
		local g = brand[look and look.brand or "ember"] or { { 0.96, 0.77, 0.19, 1 }, { 1, 0.22, 0.15, 1 } }
		W.Gradient(t.glow, "VERTICAL", g[2], g[1]) -- light on top
		t.glow:SetAlpha(look and look.steady and 1 or pulse)
		local left = item.expires and item.expires - (now or 0)
		W.SetFontSize(t.time, math.max(10, math.floor(size / 2.6)))
		t.time:SetText(left and left > 0 and ns.Line.FormatTime(left) or "")
		-- a seal that just ran out gets a small "!"
		W.SetFontSize(t.mark, math.max(10, math.floor(size / 2.6)))
		t.mark:SetText(item.expired and "|cffffd100!|r" or item.count and ("|cffffd100" .. item.count .. "|r") or "")
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
		list = { { id = "cure", spell = "purify", kind = "Poison", debuff = "Poison", text = string.format(T("Press %s"), S.DisplayName("purify")), texture = S.Get("purify").icon }, { id = "rf", text = T("Righteous Fury missing"), texture = S.Get("righteous_fury").icon }, { id = "seal", text = T("Seal missing"), icon = "seal" }, { id = "aura", text = T("No aura active"), icon = "aura" }, { id = "blessing", text = T("No blessing on yourself"), icon = "blessing" } }
		badges = { rf = true, forbearance = true }
	elseif G.IsPaladin() and G.ShouldShow(db, "warn", "warningsOnlyInCombat", G.PlayerState()) then
		list, badges = R.Decide(R.Context(now))
	else
		list, badges = {}, { rf = false, forbearance = false }
	end
	R.active = list
	-- Forbearance sits in the same icon row, after the reminders
	local row = {}
	for i, item in ipairs(list) do
		row[i] = item
	end
	if badges.forbearance then
		local fd = ns.Auras.data and ns.Auras.data.forbearance
		row[#row + 1] = { id = "forb", text = T("Forbearance"), texture = S.Get("forbearance").icon,
			expires = fd and fd.expires or (preview and now + 42) or nil }
	end

	-- then points you have not spent yet (out of combat)
	local points
	if preview then
		points = R.PointTiles({ enabled = true, talents = 2, legacy = 1 })
	elseif G.IsPaladin() then
		points = R.PointTiles({ enabled = db.warnPoints, combat = G.InCombat(),
			talents = R.TalentPoints(), legacy = R.LegacyPoints() })
	else
		points = {}
	end
	for _, item in ipairs(points) do
		row[#row + 1] = item
	end

	R.row = row
	if db.warnIcons then
		warn.text:SetText("")
		R.ShowIcons(row, now)
		warn:SetShown(#row > 0)
	else
		R.ShowIcons({}, now)
		local lines = {}
		for i, item in ipairs(list) do
			lines[i] = item.text
		end
		for _, item in ipairs(points) do
			lines[#lines + 1] = item.text
		end
		warn.text:SetText(table.concat(lines, "\n"))
		warn:SetShown(#lines > 0)
	end

	-- The RF icon repeats the red text, so it is off unless asked for.
	rfBadge.label:SetShown(preview and true or false)
	forbBadge.label:SetShown(preview and true or false)
	rfBadge:SetShown(badges.rf and ns.DB().rfBadge and true or false)
	-- with icons Forbearance is a tile in the reminder row; with text, its badge
	forbBadge:SetShown(badges.forbearance and not db.warnIcons and true or false)
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
