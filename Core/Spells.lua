--[[
  Bulwark core: spell catalog, spellbook, "is known", talents and spec.

  Spells are matched by spell ID first and by normalized name second
  (English catalog names plus the names the client returns for the
  catalog IDs, so localized clients match too). Never by icon.
  Forever-only spells have no known IDs: their IDs are learned at runtime
  (spellbook, own casts, auras) and kept in BulwarkDB.learnedIDs[key].
]]

local ADDON_NAME, ns = ...
ns = ns or {}
local G = ns.G

local S = {}
ns.Spells = S

local function Range(a, b)
	local out = {}
	for i = a, b do
		out[#out + 1] = i
	end
	return out
end

local function Ids(...)
	local out = {}
	for _, v in ipairs({ ... }) do
		if type(v) == "table" then
			for _, x in ipairs(v) do
				out[#out + 1] = x
			end
		else
			out[#out + 1] = v
		end
	end
	return out
end

local ICON = "Interface\\Icons\\"

------------------------------------------------------------------------
-- Catalog. dur = buff duration on the line, cd = base cooldown.
------------------------------------------------------------------------

S.CATALOG = {
	seal_fury = { name = "Seal of Fury", forever = true, seal = true, dur = 30,
		ids = Ids(1311656, 20422, 20414, 20453, 20187, Range(20300, 20303), 20163), icon = "Spell_Holy_SealOfFury" },
	seal_righteousness = { name = "Seal of Righteousness", seal = true, dur = 30,
		ids = Ids(21084, 20154, Range(20287, 20293)), icon = "Ability_ThunderBolt" },
	seal_command = { name = "Seal of Command", seal = true, dur = 30,
		ids = Ids(20375, 20915, Range(20918, 20920)), icon = "Ability_Warrior_InnerRage" },
	seal_justice = { name = "Seal of Justice", seal = true, dur = 30, ids = { 20164 }, icon = "Spell_Holy_SealOfWrath" },
	seal_light = { name = "Seal of Light", seal = true, dur = 30, ids = Ids(20165, Range(20347, 20349)), icon = "Spell_Holy_HealingAura" },
	seal_wisdom = { name = "Seal of Wisdom", seal = true, dur = 30, ids = { 20166, 20356, 20357 }, icon = "Spell_Holy_RighteousnessAura" },
	seal_crusader = { name = "Seal of the Crusader", seal = true, dur = 30,
		ids = Ids(21082, 20162, Range(20305, 20308)), icon = "Spell_Holy_HolySmite" },
	righteous_fury = { name = "Righteous Fury", dur = 1800, ids = { 25780 }, icon = "Spell_Holy_SealOfFury" },
	holy_shield = { name = "Holy Shield", dur = 10, cd = 10, readyDefault = false,
		ids = { 20925, 20927, 20928 }, icon = "Spell_Holy_BlessingOfProtection" },
	templar_bulwark = { name = "Templar's Bulwark", forever = true, dur = 8, cd = 300, readyDefault = false,
		ids = {}, icon = "Spell_Holy_DivineProtection", forbearance = true },
	divine_protection = { name = "Divine Protection", dur = 8, cd = 300, readyDefault = false,
		ids = { 498, 5573 }, icon = "Spell_Holy_Restoration", forbearance = true },
	divine_shield = { name = "Divine Shield", dur = 12, cd = 300, readyDefault = false,
		ids = { 642, 1020 }, icon = "Spell_Holy_DivineIntervention", forbearance = true },
	bop = { name = "Blessing of Protection", dur = 10, cd = 300, readyDefault = false,
		ids = { 1022, 5599, 10278 }, icon = "Spell_Holy_SealOfProtection", forbearance = true },
	freedom = { name = "Blessing of Freedom", dur = 10, ids = { 1044 }, icon = "Spell_Holy_SealOfValor" },
	consecration = { name = "Consecration", dur = 8, cd = 8, readyDefault = false, castOnly = true,
		ids = Ids(26573, 20116, Range(20922, 20924)), icon = "Spell_Holy_InnerFire" },
	iron_creed = { name = "Iron Creed", forever = true, dur = 6, ids = {}, icon = "INV_Shield_05" },
	shieldsworn = { name = "Shieldsworn", forever = true, dur = 6, ids = {}, icon = "INV_Shield_06" },

	judgement = { name = "Judgement", alt = { "Judgment" }, cd = 10, readyDefault = true,
		ids = { 20271 }, icon = "Spell_Holy_RighteousFury" },
	holy_strike = { name = "Holy Strike", forever = true, cd = 10, readyDefault = true, ids = {}, icon = "Spell_Holy_HolyBolt" },
	hammer_of_justice = { name = "Hammer of Justice", cd = 60, readyDefault = false,
		ids = { 853, 5588, 5589, 10308 }, icon = "Spell_Holy_SealOfMight" },
	hammer_of_wrath = { name = "Hammer of Wrath", cd = 6, readyDefault = false,
		ids = { 24275, 24274, 24239 }, icon = "Ability_ThunderClap" },
	hammer_righteous = { name = "Hammer of the Righteous", forever = true, cd = 6, readyDefault = false,
		ids = {}, icon = "Ability_Paladin_HammeroftheRighteous" },
	exorcism = { name = "Exorcism", cd = 15, readyDefault = false,
		ids = Ids(879, 5614, 5615, Range(10312, 10314)), icon = "Spell_Holy_Excorcism_02" },
	holy_wrath = { name = "Holy Wrath", cd = 60, readyDefault = false, ids = { 2812, 10318 }, icon = "Spell_Holy_Excorcism" },
	swift_judgement = { name = "Swift Judgement", alt = { "Swift Judgment" }, forever = true, cd = 60,
		readyDefault = false, ids = {}, icon = "Spell_Holy_RighteousFury" },
	lay_on_hands = { name = "Lay on Hands", cd = 3600, readyDefault = false,
		ids = { 633, 2800, 10310 }, icon = "Spell_Holy_LayOnHands" },

	-- blessings you keep on yourself (the "no blessing" reminder); greater ones count too
	bless_might = { name = "Blessing of Might", alt = { "Greater Blessing of Might" }, blessing = true,
		ids = Ids(19740, Range(19834, 19838), 25291, 25782, 25916), icon = "Spell_Holy_FistOfJustice" },
	bless_wisdom = { name = "Blessing of Wisdom", alt = { "Greater Blessing of Wisdom" }, blessing = true,
		ids = Ids(19742, 19850, Range(19852, 19854), 25290, 25894, 25918), icon = "Spell_Holy_SealOfWisdom" },
	bless_kings = { name = "Blessing of Kings", alt = { "Greater Blessing of Kings" }, blessing = true,
		ids = { 20217, 25898 }, icon = "Spell_Magic_MageArmor" },
	bless_salvation = { name = "Blessing of Salvation", alt = { "Greater Blessing of Salvation" }, blessing = true,
		ids = { 1038, 25895 }, icon = "Spell_Holy_SealOfSalvation" },
	bless_light = { name = "Blessing of Light", alt = { "Greater Blessing of Light" }, blessing = true,
		ids = { 19977, 19978, 19979, 25890 }, icon = "Spell_Holy_PrayerOfHealing02" },
	bless_sanctuary = { name = "Blessing of Sanctuary", alt = { "Greater Blessing of Sanctuary" }, blessing = true,
		ids = { 20911, 20912, 20913, 20914, 25899 }, icon = "Spell_Nature_LightningShield" },

	-- not on the line or the icon row
	devotion_aura = { name = "Devotion Aura", ids = { 465, 10290, 643, 10291, 1032, 10292, 10293 }, icon = "Spell_Holy_DevotionAura" },
	forbearance = { name = "Forbearance", ids = { 25771 }, harmful = true, icon = "Spell_Holy_RemoveCurse" },
	fire_res_aura = { name = "Fire Resistance Aura", ids = { 19891, 19899, 19900 }, resistAura = true },
	frost_res_aura = { name = "Frost Resistance Aura", ids = { 19888, 19897, 19898 }, resistAura = true },
	shadow_res_aura = { name = "Shadow Resistance Aura", ids = { 19876, 19895, 19896 }, resistAura = true },
	retribution_aura = { name = "Retribution Aura", ids = { 7294, 10298, 10299, 10300, 10301 }, otherAura = true },
	concentration_aura = { name = "Concentration Aura", ids = { 19746 }, otherAura = true },
	sanctity_aura = { name = "Sanctity Aura", ids = { 20218 }, otherAura = true },
}

-- Order on the line and in the options.
S.LINE = {
	"seal_fury", "seal_righteousness", "seal_command", "seal_justice", "seal_light", "seal_wisdom",
	"seal_crusader", "righteous_fury", "holy_shield", "templar_bulwark", "divine_protection",
	"divine_shield", "bop", "freedom", "consecration", "iron_creed", "shieldsworn",
}
S.READY = {
	"judgement", "holy_strike", "consecration", "holy_shield", "hammer_of_justice", "hammer_of_wrath",
	"hammer_righteous", "exorcism", "holy_wrath", "swift_judgement", "templar_bulwark",
	"divine_protection", "divine_shield", "bop", "lay_on_hands",
}
S.SEALS = {
	"seal_fury", "seal_righteousness", "seal_command", "seal_justice", "seal_light", "seal_wisdom", "seal_crusader",
}
S.BLESSINGS = {
	"bless_might", "bless_wisdom", "bless_kings", "bless_salvation", "bless_light", "bless_sanctuary",
}
S.AURAS = {
	"devotion_aura", "fire_res_aura", "frost_res_aura", "shadow_res_aura",
	"retribution_aura", "concentration_aura", "sanctity_aura",
}

for key, spell in pairs(S.CATALOG) do
	spell.key = key
	if spell.icon and not spell.icon:find("\\") then
		spell.icon = ICON .. spell.icon
	end
	if spell.dur and spell.lineDefault == nil then
		spell.lineDefault = true
	end
end

function S.Get(key)
	return S.CATALOG[key]
end

------------------------------------------------------------------------
-- Spell info
------------------------------------------------------------------------

function S.NameOf(id)
	id = G.Num(id)
	if not id then
		return nil
	end
	if C_Spell and C_Spell.GetSpellName then
		local name = G.Str(G.Read(C_Spell.GetSpellName, id))
		if name then
			return name
		end
	end
	return G.Str(G.Read(GetSpellInfo, id))
end

function S.TextureOf(id)
	id = G.Num(id)
	if not id then
		return nil
	end
	if C_Spell and C_Spell.GetSpellTexture then
		local tex = G.Read(C_Spell.GetSpellTexture, id)
		if tex ~= nil then
			return tex
		end
	end
	local all = G.ReadAll(GetSpellInfo, id)
	return all and all[3] or nil
end

-- All IDs of a key: catalog first, then the learned ones.
function S.AllIDs(key)
	local spell = S.CATALOG[key]
	local out = {}
	if not spell then
		return out
	end
	for _, id in ipairs(spell.ids) do
		out[#out + 1] = id
	end
	local db = type(BulwarkDB) == "table" and BulwarkDB or nil
	local learned = db and type(db.learnedIDs) == "table" and db.learnedIDs[key]
	if type(learned) == "table" then
		for _, id in ipairs(learned) do
			if type(id) == "number" then
				out[#out + 1] = id
			end
		end
	end
	return out
end

------------------------------------------------------------------------
-- Lookup indexes (rebuilt on login, spell changes and learning)
------------------------------------------------------------------------

local byID, byName = {}, {}
S.byID, S.byName = byID, byName

-- English names, alternative spellings and the client's names for the IDs.
function S.NamesOf(key)
	local spell = S.CATALOG[key]
	local out, seen = {}, {}
	local function add(n)
		n = G.Norm(n)
		if n and not seen[n] then
			seen[n] = true
			out[#out + 1] = n
		end
	end
	if not spell then
		return out
	end
	add(spell.name)
	for _, n in ipairs(spell.alt or {}) do
		add(n)
	end
	if spell.localName then
		add(spell.localName)
	end
	return out
end

function S.Rebuild()
	for k in pairs(byID) do
		byID[k] = nil
	end
	for k in pairs(byName) do
		byName[k] = nil
	end
	for key, spell in pairs(S.CATALOG) do
		for _, id in ipairs(S.AllIDs(key)) do
			byID[id] = key
		end
		-- The client's (possibly localized) name for the first catalog ID.
		if not spell.localName then
			for _, id in ipairs(S.AllIDs(key)) do
				local n = S.NameOf(id)
				if n then
					spell.localName = n
					break
				end
			end
		end
		for _, n in ipairs(S.NamesOf(key)) do
			if byName[n] == nil then
				byName[n] = key
			end
		end
	end
end

function S.KeyForID(id)
	id = G.Num(id)
	return id and byID[id] or nil
end

function S.KeyForName(name)
	local n = G.Norm(name)
	return n and byName[n] or nil
end

-- Match a spell (ID first, name second). Learns the ID of a name match.
function S.Match(id, name)
	local key = S.KeyForID(id)
	if key then
		return key
	end
	if name == nil and id then
		name = S.NameOf(id)
	end
	key = S.KeyForName(name)
	if key and G.Num(id) then
		S.Learn(key, id)
	end
	return key
end

function S.Learn(key, id)
	id = G.Num(id)
	if not id or not S.CATALOG[key] or byID[id] == key then
		return false
	end
	if type(BulwarkDB) ~= "table" then
		return false
	end
	BulwarkDB.learnedIDs = type(BulwarkDB.learnedIDs) == "table" and BulwarkDB.learnedIDs or {}
	local list = BulwarkDB.learnedIDs[key]
	if type(list) ~= "table" then
		list = {}
		BulwarkDB.learnedIDs[key] = list
	end
	for _, x in ipairs(list) do
		if x == id then
			return false
		end
	end
	list[#list + 1] = id
	byID[id] = key
	return true
end

------------------------------------------------------------------------
-- Spellbook (player bank, no future spells)
------------------------------------------------------------------------

local book = { ok = false, byName = {}, ids = {} }
S.book = book

local function FutureType()
	local e = _G.Enum and _G.Enum.SpellBookItemType
	return e and e.FutureSpell or 2
end

local function AddBookSpell(id)
	id = G.Num(id)
	if not id or id <= 0 then
		return
	end
	book.ids[id] = true
	local n = G.Norm(S.NameOf(id))
	if n then
		book.byName[n] = id
	end
end

function S.ScanBook()
	local fresh = { byName = {}, ids = {} }
	book.byName, book.ids = fresh.byName, fresh.ids
	local scanned = 0
	local api = _G.C_SpellBook
	if type(api) == "table" and api.GetNumSpellBookSkillLines and api.GetSpellBookSkillLineInfo and api.GetSpellBookItemType then
		local bank = _G.Enum and _G.Enum.SpellBookSpellBank and _G.Enum.SpellBookSpellBank.Player or 0
		local lines = G.Num(G.Read(api.GetNumSpellBookSkillLines)) or 0
		local future = FutureType()
		for i = 1, math.min(lines, 40) do
			local info = G.Read(api.GetSpellBookSkillLineInfo, i)
			if type(info) == "table" then
				local offset = G.Num(G.Field(info, "itemIndexOffset")) or 0
				local count = G.Num(G.Field(info, "numSpellBookItems")) or 0
				for j = offset + 1, offset + math.min(count, 400) do
					local r = G.ReadAll(api.GetSpellBookItemType, j, bank)
					if r and r[1] ~= nil and r[1] ~= future then
						AddBookSpell(r[3] or r[2])
						scanned = scanned + 1
					end
				end
			end
		end
	elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo then
		local tabs = G.Num(G.Read(GetNumSpellTabs)) or 0
		for tab = 1, tabs do
			local r = G.ReadAll(GetSpellTabInfo, tab)
			local offset, count = r and G.Num(r[3]) or 0, r and G.Num(r[4]) or 0
			for j = offset + 1, offset + count do
				local item = G.ReadAll(GetSpellBookItemInfo, j, BOOKTYPE_SPELL or "spell")
				if item and item[1] == "SPELL" then
					AddBookSpell(item[2])
					scanned = scanned + 1
				end
			end
		end
	end
	book.ok = scanned > 0
	-- Learn IDs of Forever spells found by name.
	if book.ok then
		for n, id in pairs(book.byName) do
			local key = byName[n]
			if key then
				S.Learn(key, id)
			end
		end
	end
	return book
end

------------------------------------------------------------------------
-- Known: only when confirmed. Returns true, false, or nil (unknown).
------------------------------------------------------------------------

local function KnownByAPI(id)
	local answered = false
	local checks = {
		_G.C_SpellBook and _G.C_SpellBook.IsSpellKnown,
		_G.IsPlayerSpell,
		_G.IsSpellKnown,
	}
	for i = 1, 3 do
		local fn = checks[i]
		if type(fn) == "function" then
			local ok, v = pcall(fn, id)
			if ok and not G.IsSecret(v) then
				if v then
					return true
				end
				answered = true
			end
		end
	end
	return answered and false or nil
end

-- Returns known (true/false/nil) and how: "id", "book", or nil.
function S.IsKnown(key)
	local answered = false
	for _, id in ipairs(S.AllIDs(key)) do
		local v = KnownByAPI(id)
		if v then
			return true, "id", id
		end
		if v == false then
			answered = true
		end
	end
	if book.ok then
		for _, n in ipairs(S.NamesOf(key)) do
			local id = book.byName[n]
			if id then
				return true, "book", id
			end
		end
		return false
	end
	if answered then
		return false
	end
	return nil
end

-- The ID to use for cooldowns and icons: the spellbook's, else a known one.
function S.KnownID(key)
	if book.ok then
		for _, n in ipairs(S.NamesOf(key)) do
			if book.byName[n] then
				return book.byName[n]
			end
		end
	end
	local best
	for _, id in ipairs(S.AllIDs(key)) do
		if KnownByAPI(id) then
			best = id
		end
	end
	return best
end

function S.Icon(key)
	local id = S.KnownID(key)
	local tex = id and S.TextureOf(id)
	if tex == nil then
		for _, x in ipairs(S.AllIDs(key)) do
			tex = S.TextureOf(x)
			if tex ~= nil then
				break
			end
		end
	end
	local spell = S.CATALOG[key]
	return tex or (spell and spell.icon) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Name to show: the client's name if it has one, else the catalog name.
function S.DisplayName(key)
	local spell = S.CATALOG[key]
	if not spell then
		return key
	end
	return spell.localName or spell.name
end

------------------------------------------------------------------------
-- Talents and spec (last known ranks are kept when a read fails)
------------------------------------------------------------------------

S.TALENTS = {
	improved_judgement = { "Improved Judgement", "Improved Judgment" },
	shieldsworn = { "Shieldsworn" },
	sacred_duty = { "Sacred Duty" },
	guardians_favor = { "Guardian's Favor", "Guardian's Favour" },
	improved_hoj = { "Improved Hammer of Justice" },
	purifying_power = { "Purifying Power" },
	iron_creed = { "Iron Creed" },
}

S.ranks = {}
for k in pairs(S.TALENTS) do
	S.ranks[k] = 0
end
S.spec = nil -- "HOLY", "PROTECTION", "RETRIBUTION" or nil (unknown)

local TREE = { "HOLY", "PROTECTION", "RETRIBUTION" }

local talentByName = {}
for key, names in pairs(S.TALENTS) do
	for _, n in ipairs(names) do
		talentByName[G.Norm(n)] = key
	end
end

-- Pure part: points per tree -> spec name (nil when nothing is spent).
function S.SpecFromPoints(points)
	local best, bestPoints = nil, 0
	for i = 1, 3 do
		local p = points[i] or 0
		if p > bestPoints then
			best, bestPoints = i, p
		end
	end
	return best and TREE[best] or nil
end

function S.ReadTalents()
	if type(GetNumTalentTabs) ~= "function" or type(GetNumTalents) ~= "function" or type(GetTalentInfo) ~= "function" then
		return false
	end
	local tabs = G.Num(G.Read(GetNumTalentTabs))
	if not tabs or tabs < 1 then
		return false
	end
	local ranks, points = {}, {}
	for k in pairs(S.TALENTS) do
		ranks[k] = 0
	end
	for tab = 1, math.min(tabs, 3) do
		local n = G.Num(G.Read(GetNumTalents, tab))
		if not n then
			return false
		end
		points[tab] = 0
		for i = 1, n do
			local info = G.ReadAll(GetTalentInfo, tab, i)
			if not info or info.hidden then
				return false -- keep the last known ranks
			end
			local rank = G.Num(info[5]) or 0
			points[tab] = points[tab] + rank
			local key = talentByName[G.Norm(info[1]) or ""]
			if key then
				ranks[key] = rank
			end
		end
	end
	S.ranks = ranks
	-- Spec: the game's answer when there is one, else the biggest tree.
	local spec
	local idx = G.Num(G.Read(_G.GetPrimaryTalentTree))
	if idx and TREE[idx] then
		spec = TREE[idx]
	end
	S.spec = spec or S.SpecFromPoints(points)
	S.specRead = true
	return true
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

function S.Refresh()
	S.Rebuild()
	S.ScanBook()
	S.Rebuild()
	S.ReadTalents()
end

ns.On("PLAYER_LOGIN", S.Refresh)
ns.On("SPELLS_CHANGED", function()
	S.ScanBook()
	S.ReadTalents()
end)
ns.On("CHARACTER_POINTS_CHANGED", S.ReadTalents)
ns.On("PLAYER_TALENT_UPDATE", S.ReadTalents)
ns.On("LEARNED_SPELL_IN_SKILL_LINE", S.ScanBook)
ns.On("LEARNED_SPELL_IN_TAB", S.ScanBook)
