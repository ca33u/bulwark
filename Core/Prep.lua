--[[
  Bulwark core: tank readiness window (/bulwark prep).

  A movable list of checks. Each row is green (good), yellow (could not
  read, or advice) or red (missing). Refreshed when opened, on relevant
  events and once a second while open.
]]

local ADDON_NAME, ns = ...
ns = ns or {}
local G, S, W, T = ns.G, ns.Spells, ns.W, ns.T

local P = {}
ns.Prep = P

P.GOOD, P.WARN, P.BAD = "good", "warn", "bad"

-- Buffs other classes give. ids: one classic ID per name, used to get the
-- client's localized name (every rank shares it).
P.GROUP_BUFFS = {
	{ class = "PALADIN", label = "Blessing of Kings", names = { "Blessing of Kings", "Greater Blessing of Kings" }, ids = { 20217, 25898 } },
	{ class = "PALADIN", label = "Blessing of Might", names = { "Blessing of Might", "Greater Blessing of Might" }, ids = { 19740, 25782 } },
	{ class = "PALADIN", label = "Blessing of Wisdom", names = { "Blessing of Wisdom", "Greater Blessing of Wisdom" }, ids = { 19742, 25894 } },
	{ class = "PRIEST", label = "Power Word: Fortitude", names = { "Power Word: Fortitude", "Prayer of Fortitude" }, ids = { 1243, 21562 } },
	{ class = "PRIEST", label = "Divine Spirit", names = { "Divine Spirit", "Prayer of Spirit" }, ids = { 14752, 27681 } },
	{ class = "PRIEST", label = "Shadow Protection", names = { "Shadow Protection", "Prayer of Shadow Protection" }, ids = { 976, 27683 } },
	{ class = "MAGE", label = "Arcane Intellect", names = { "Arcane Intellect", "Arcane Brilliance" }, ids = { 1459, 23028 } },
	{ class = "DRUID", label = "Mark of the Wild", names = { "Mark of the Wild", "Gift of the Wild" }, ids = { 1126, 21849 } },
	{ class = "DRUID", label = "Thorns", names = { "Thorns" }, ids = { 467 } },
	{ class = "DRUID", label = "Leader of the Pack", names = { "Leader of the Pack" }, ids = { 24932 } },
	{ class = "DRUID", label = "Moonkin Aura", names = { "Moonkin Aura" }, ids = { 24907 } },
	{ class = "WARRIOR", label = "Battle Shout", names = { "Battle Shout" }, ids = { 6673 } },
	{ class = "WARLOCK", label = "Blood Pact", names = { "Blood Pact" }, ids = { 6307 } },
	{ class = "SHAMAN", label = "Strength of Earth", names = { "Strength of Earth" }, ids = { 8076 } },
	{ class = "SHAMAN", label = "Grace of Air", names = { "Grace of Air" }, ids = { 8836 } },
	{ class = "SHAMAN", label = "Stoneskin", names = { "Stoneskin" }, ids = { 8072 } },
	{ class = "SHAMAN", label = "Windfury", names = { "Windfury Totem", "Windfury" }, ids = { 8516 } },
	{ class = "SHAMAN", label = "Mana Spring", names = { "Mana Spring" }, ids = { 5677 } },
	{ class = "SHAMAN", label = "Fire Resistance", names = { "Fire Resistance" }, ids = { 8185 } },
	{ class = "SHAMAN", label = "Frost Resistance", names = { "Frost Resistance" }, ids = { 8182 } },
	{ class = "SHAMAN", label = "Nature Resistance", names = { "Nature Resistance" }, ids = { 10596 } },
	{ class = "HUNTER", label = "Trueshot Aura", names = { "Trueshot Aura" }, ids = { 19506 } },
	{ class = "HUNTER", label = "Aspect of the Wild", names = { "Aspect of the Wild" }, ids = { 20043 } },
	-- Tranquil Air lowers threat: correct to be missing on a tank.
	{ class = "SHAMAN", label = "Tranquil Air", names = { "Tranquil Air" }, ids = { 25909 }, threatReducer = true },
}

P.BLESSINGS = {
	names = {
		"Blessing of Kings", "Greater Blessing of Kings", "Blessing of Might", "Greater Blessing of Might",
		"Blessing of Wisdom", "Greater Blessing of Wisdom", "Blessing of Light", "Greater Blessing of Light",
		"Blessing of Sanctuary", "Greater Blessing of Sanctuary",
	},
	ids = { 20217, 25898, 19740, 25782, 19742, 25894, 19977, 25890, 20911, 25899 },
}

P.WELL_FED = { names = { "Well Fed" }, ids = { 19705 } }
P.TITANS = { names = { "Flask of the Titans" }, ids = { 17626 } }
P.FLASKS = { names = { "Flask of Supreme Power", "Flask of Distilled Wisdom", "Flask of Chromatic Resistance" }, ids = { 17628, 17627, 17629 } }
P.ELIXIRS = {
	names = { "Elixir of the Mongoose", "Greater Armor", "Health II", "Elixir of the Giants", "Greater Agility", "Gift of Arthas" },
	ids = { 17538, 11348, 3593, 11405, 11334, 11371 },
}

P.SUBTLETY_ENCHANT = 2621

P.ENCHANT_SLOTS = {
	{ 1, "Head" }, { 3, "Shoulder" }, { 5, "Chest" }, { 7, "Legs" }, { 8, "Feet" },
	{ 9, "Wrist" }, { 10, "Hands" }, { 15, "Back" }, { 16, "Main hand" },
}

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

-- English names plus the client's names for the IDs.
local function AllNames(def)
	local out = {}
	for _, n in ipairs(def.names or {}) do
		out[#out + 1] = n
	end
	for _, id in ipairs(def.ids or {}) do
		local n = S.NameOf(id)
		if n then
			out[#out + 1] = n
		end
	end
	return out
end

-- true / false / nil (could not read)
local function Has(def)
	local found = ns.Auras.HasNamed(AllNames(def))
	if found == nil then
		return nil
	end
	return found and true or false, found
end

-- Name prefix match on the last full scan ("Flask of ..." from any source).
local function HasPrefix(prefix)
	if not ns.Auras.complete then
		return nil
	end
	prefix = G.Norm(prefix)
	for n in pairs(ns.Auras.names) do
		if n:sub(1, #prefix) == prefix then
			return true
		end
	end
	return false
end

-- Classes in the group, without the player.
function P.GroupClasses()
	local classes = {}
	local raid = G.Num(G.Read(GetNumGroupMembers)) or 0
	local inRaid = G.Flag(G.Read(IsInRaid)) == true
	local units = {}
	if inRaid then
		for i = 1, math.min(raid, 40) do
			units[#units + 1] = "raid" .. i
		end
	else
		for i = 1, 4 do
			units[#units + 1] = "party" .. i
		end
	end
	for _, unit in ipairs(units) do
		if G.Flag(G.Read(UnitExists, unit)) and not G.Flag(G.Read(UnitIsUnit, unit, "player")) then
			local ok, _, class = pcall(UnitClass, unit)
			if ok and G.Str(class) then
				classes[class] = true
			end
		end
	end
	return classes
end

local function ClassName(class)
	local names = _G.LOCALIZED_CLASS_NAMES_MALE
	return type(names) == "table" and G.Str(names[class]) or class:sub(1, 1) .. class:sub(2):lower()
end

local function EquipLoc(itemID)
	if not itemID then
		return nil
	end
	local api = _G.C_Item
	local fn = type(api) == "table" and api.GetItemInfoInstant or _G.GetItemInfoInstant
	local r = G.ReadAll(fn, itemID)
	if r and G.Str(r[4]) then
		return r[4]
	end
	r = G.ReadAll(type(api) == "table" and api.GetItemInfo or _G.GetItemInfo, itemID)
	return r and G.Str(r[9]) or nil
end

-- Enchant ID of an item link (0 = none), nil when unreadable.
function P.EnchantOf(link)
	link = G.Str(link)
	if not link then
		return nil
	end
	local id, enchant = link:match("item:(%-?%d+):(%-?%d*)")
	if not id then
		return nil
	end
	return tonumber(enchant) or 0
end

local function Slot(slot)
	local id = G.Num(G.Read(GetInventoryItemID, "player", slot))
	local link = G.Read(GetInventoryItemLink, "player", slot)
	return id, P.EnchantOf(link)
end

------------------------------------------------------------------------
-- Checks
------------------------------------------------------------------------

function P.Collect()
	local rows = {}
	local function Row(state, text)
		rows[#rows + 1] = { state = state, text = text }
	end
	local A = ns.Auras
	A.Update()

	-- Righteous Fury
	local rfKnown = S.IsKnown("righteous_fury")
	local rf = A.Status("righteous_fury")
	if rf == "present" then
		Row(P.GOOD, T("Righteous Fury is up"))
	elseif rf == "hidden" then
		Row(P.WARN, T("Righteous Fury: could not read"))
	elseif rfKnown then
		Row(P.BAD, T("Righteous Fury missing"))
	end

	-- Seal: Seal of Fury for Forever tanks, any seal otherwise.
	local furyKnown = S.IsKnown("seal_fury")
	if furyKnown then
		local st = A.Status("seal_fury")
		if st == "present" or A.entries.seal_fury then
			Row(P.GOOD, T("Seal of Fury is up"))
		elseif st == "hidden" then
			Row(P.WARN, T("Seal: could not read"))
		else
			Row(P.BAD, T("Seal of Fury missing"))
		end
	else
		local st = A.SealStatus()
		if st == "present" then
			Row(P.GOOD, T("Seal is up"))
		elseif st == "hidden" then
			Row(P.WARN, T("Seal: could not read"))
		else
			local anyKnown = false
			for _, k in ipairs(S.SEALS) do
				anyKnown = anyKnown or S.IsKnown(k) == true
			end
			if anyKnown then
				Row(P.BAD, T("Seal missing"))
			end
		end
	end

	-- Aura
	if S.IsKnown("devotion_aura") then
		local aura = A.PaladinAura()
		if aura == "devotion" then
			Row(P.GOOD, T("Devotion Aura is up"))
		elseif aura == "resist" then
			Row(P.GOOD, T("Resistance aura is up (fine for this fight)"))
		elseif aura == "other" then
			Row(P.WARN, T("Devotion is the tank aura"))
		elseif aura == "hidden" then
			Row(P.WARN, T("Aura: could not read"))
		else
			Row(P.BAD, T("Devotion Aura missing"))
		end
	end

	-- A paladin blessing on you
	local has, aura = Has(P.BLESSINGS)
	local level = G.Num(G.Read(UnitLevel, "player")) or 60
	if has then
		Row(P.GOOD, string.format(T("Blessing: %s"), aura and aura.name or "?"))
	elseif has == nil then
		Row(P.WARN, T("Blessing: could not read"))
	elseif level >= 4 then
		Row(P.BAD, T("Blessing missing"))
	end

	-- Group class buffs
	local classes = P.GroupClasses()
	for _, def in ipairs(P.GROUP_BUFFS) do
		if classes[def.class] then
			local on = Has(def)
			if def.threatReducer then
				if on then
					Row(P.WARN, string.format(T("%s is on you: it lowers your threat"), def.label))
				elseif on == false then
					Row(P.GOOD, string.format(T("%s not on you (right for a tank)"), def.label))
				end
			elseif on then
				Row(P.GOOD, def.label)
			elseif on == nil then
				Row(P.WARN, string.format(T("%s: could not read"), def.label))
			else
				Row(P.BAD, string.format(T("%s missing - %s"), def.label, ClassName(def.class)))
			end
		end
	end

	-- Forbearance
	local forb = A.Status("forbearance")
	if forb == "present" then
		Row(P.WARN, T("Forbearance: immunities locked"))
	elseif forb == "absent" then
		Row(P.GOOD, T("Forbearance clear"))
	else
		Row(P.WARN, T("Forbearance: could not read"))
	end

	-- Weapon and shield
	local mh = Slot(16)
	local mhLoc = EquipLoc(mh)
	if not mh then
		Row(P.BAD, T("No weapon equipped"))
	elseif mhLoc == "INVTYPE_2HWEAPON" then
		Row(P.BAD, T("Two-handed weapon: a tank wants one hand and a shield"))
	else
		Row(P.GOOD, T("One-handed weapon"))
	end
	local oh, ohEnchant = Slot(17)
	if not oh or EquipLoc(oh) ~= "INVTYPE_SHIELD" then
		Row(P.BAD, T("No shield"))
	elseif ohEnchant == 0 then
		Row(P.BAD, T("Shield not enchanted (enchant or shield spike)"))
	elseif ohEnchant == nil then
		Row(P.WARN, T("Shield enchant: could not read"))
	else
		Row(P.GOOD, T("Shield enchanted"))
	end

	-- Gear enchants
	local missing = 0
	for _, s in ipairs(P.ENCHANT_SLOTS) do
		local id, enchant = Slot(s[1])
		local slotName = T(s[2])
		if not id then
			Row(P.BAD, string.format(T("%s: empty slot"), slotName))
			missing = missing + 1
		elseif enchant == 0 then
			Row(P.BAD, string.format(T("%s: no enchant"), slotName))
			missing = missing + 1
		end
		if s[1] == 15 and enchant == P.SUBTLETY_ENCHANT then
			Row(P.BAD, T("Cloak has Subtlety: it lowers your threat"))
		end
	end
	if missing == 0 then
		Row(P.GOOD, T("Gear enchanted"))
	end

	-- Consumables
	local fed = Has(P.WELL_FED)
	if fed then
		Row(P.GOOD, T("Well Fed"))
	elseif fed == nil then
		Row(P.WARN, T("Well Fed: could not read"))
	else
		Row(P.BAD, T("Not Well Fed"))
	end
	local titans = Has(P.TITANS)
	if titans then
		Row(P.GOOD, T("Flask of the Titans"))
	elseif titans == nil then
		Row(P.WARN, T("Flask: could not read"))
	elseif Has(P.FLASKS) or HasPrefix("Flask of") then
		Row(P.WARN, T("Flask: Flask of the Titans is the tank flask"))
	else
		Row(P.WARN, T("No flask"))
	end
	local elixir = Has(P.ELIXIRS)
	if elixir or (elixir == false and HasPrefix("Elixir")) then
		Row(P.GOOD, T("Elixir active"))
	elseif elixir == nil then
		Row(P.WARN, T("Elixirs: could not read"))
	else
		Row(P.WARN, T("No battle or guardian elixir"))
	end

	-- Defense skill
	local def = G.ReadAll(UnitDefense, "player")
	local base, mod = def and G.Num(def[1]), def and G.Num(def[2])
	if base then
		Row(P.GOOD, string.format(T("Defense %d"), math.floor(base + (mod or 0) + 0.5)))
	else
		Row(P.WARN, T("Defense: hidden while stats are restricted"))
	end
	return rows
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------

local COLORS = {
	good = { 0.3, 0.9, 0.35 },
	warn = { 1, 0.82, 0.2 },
	bad = { 1, 0.3, 0.25 },
}
local ROW_H, WIDTH, MAX_ROWS = 16, 300, 40

local win = CreateFrame("Frame", "BulwarkPrepWindow", UIParent)
win:SetSize(WIDTH, 60)
win:SetFrameStrata("DIALOG")
win:SetClampedToScreen(true)
win:SetMovable(true)
win:EnableMouse(true)
win:RegisterForDrag("LeftButton")
W.Panel(win, 0.92)
win:Hide()
P.frame = win
if type(UISpecialFrames) == "table" then
	table.insert(UISpecialFrames, "BulwarkPrepWindow")
end

local title = W.Text(win, "GameFontNormal")
title:SetPoint("TOPLEFT", 10, -8)
title:SetText("|cfff4c430" .. T("Tank readiness") .. "|r")

local close = W.Button(win, "x", 18, 18, function()
	win:Hide()
end)
close:SetPoint("TOPRIGHT", -6, -6)

local rowFrames = {}
local function RowFrame(i)
	local r = rowFrames[i]
	if r then
		return r
	end
	r = CreateFrame("Frame", nil, win)
	r:SetSize(WIDTH - 20, ROW_H)
	r:SetPoint("TOPLEFT", 10, -30 - (i - 1) * ROW_H)
	r.dot = r:CreateTexture(nil, "ARTWORK")
	r.dot:SetSize(8, 8)
	r.dot:SetPoint("LEFT", 0, 0)
	r.text = W.Text(r, "GameFontHighlightSmall")
	r.text:SetPoint("LEFT", 14, 0)
	r.text:SetPoint("RIGHT", 0, 0)
	r.text:SetJustifyH("LEFT")
	r.text:SetWordWrap(false)
	rowFrames[i] = r
	return r
end

function P.Refresh()
	if not win:IsShown() then
		return
	end
	local rows = P.Collect()
	local n = math.min(#rows, MAX_ROWS)
	for i = 1, n do
		local r, row = RowFrame(i), rows[i]
		local c = COLORS[row.state] or COLORS.warn
		r.dot:SetColorTexture(c[1], c[2], c[3], 1)
		r.text:SetText(row.text)
		r.text:SetTextColor(c[1], c[2], c[3])
		r:Show()
	end
	for i = n + 1, #rowFrames do
		rowFrames[i]:Hide()
	end
	win:SetHeight(40 + n * ROW_H)
end

function P.Apply()
	local db = ns.DB()
	win:ClearAllPoints()
	win:SetPoint("CENTER", UIParent, "CENTER", db.prepX, db.prepY)
end

win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local db = ns.DB()
	db.prepX, db.prepY = W.CenterOffset(self)
	P.Apply()
end)
win:SetScript("OnShow", P.Refresh)

function P.Toggle()
	if win:IsShown() then
		win:Hide()
	else
		P.Apply()
		win:Show()
		P.Refresh()
	end
end

local function Dirty()
	if win:IsShown() then
		P.Refresh()
	end
end
ns.On("PLAYER_EQUIPMENT_CHANGED", Dirty)
ns.On("GROUP_ROSTER_UPDATE", Dirty)
ns.Every(1, Dirty)
