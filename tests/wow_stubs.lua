-- Richer WoW API stubs for loading the whole addon (every TOC file, in
-- order) outside the game. Builds on tests/module_stubs.lua (Check, LoadModule).
-- Run tests from the repo root.
dofile("tests/module_stubs.lua")

WOW = {
	time = 1000,
	combat = false,
	frames = {},
	printed = {},
	sounds = {},
	spells = {},     -- id -> { name, texture }
	known = {},      -- id -> true
	book = {},       -- list of spell IDs in the spellbook
	auras = { HELPFUL = {}, HARMFUL = {} }, -- lists of aura data tables
	aurasHidden = false,                    -- every aura read returns a secret
	oneSecretAura = false,                  -- the first buff is unreadable, the rest are fine
	cooldowns = {},  -- id -> { startTime, duration } or "SECRET"
	talents = nil,   -- { { {name, rank}, ... }, tab2, tab3 }
	inventory = {},  -- slot -> { id, link, equipLoc }
	stats = { defense = { 300, 0 }, dodge = 5, parry = 5, block = 5, blockValue = 50, armor = 3000, hp = 4000 },
}

SECRET = setmetatable({}, { __tostring = function()
	return "SECRET"
end })
function issecretvalue(v)
	return v == SECRET
end

------------------------------------------------------------------------
-- Widgets
------------------------------------------------------------------------

local Widget = {}
local widgetMeta = {
	__index = function(self, key)
		local m = Widget[key]
		if m ~= nil then
			return m
		end
		-- Methods (Capitalized) are no-ops; plain fields are nil like in the game.
		if type(key) == "string" and key:match("^%u") then
			return function() end
		end
		return nil
	end,
}

local function NewWidget(kind, name)
	local w = setmetatable({ _kind = kind, _name = name, _scripts = {}, _events = {}, _shown = true, _w = 0, _h = 0 }, widgetMeta)
	WOW.frames[#WOW.frames + 1] = w
	return w
end

function Widget:SetScript(name, fn)
	self._scripts[name] = fn
end
function Widget:GetScript(name)
	return self._scripts[name]
end
function Widget:HookScript(name, fn)
	local old = self._scripts[name]
	self._scripts[name] = function(...)
		if old then
			old(...)
		end
		fn(...)
	end
end
-- Events that do not exist on this "client" raise, like the real one.
WOW.missingEvents = { PLAYER_SWING = true }
function Widget:RegisterEvent(event)
	if WOW.missingEvents[event] then
		error("Attempt to register unknown event \"" .. event .. "\"")
	end
	self._events[event] = true
end
function Widget:UnregisterEvent(event)
	self._events[event] = nil
end
function Widget:Show()
	self._shown = true
end
function Widget:Hide()
	self._shown = false
end
function Widget:SetShown(v)
	self._shown = v and true or false
end
function Widget:IsShown()
	return self._shown
end
function Widget:IsVisible()
	return self._shown
end
function Widget:SetSize(w, h)
	self._w, self._h = w, h
end
function Widget:SetWidth(w)
	self._w = w
end
function Widget:SetHeight(h)
	self._h = h
end
function Widget:GetWidth()
	return self._w
end
function Widget:GetHeight()
	return self._h
end
function Widget:GetCenter()
	return 500, 400
end
function Widget:GetEffectiveScale()
	return 1
end
function Widget:GetScale()
	return 1
end
function Widget:GetFrameLevel()
	return 1
end
function Widget:GetName()
	return self._name
end
function Widget:IsForbidden()
	return false
end
function Widget:CreateTexture()
	return NewWidget("Texture")
end
function Widget:CreateMaskTexture()
	return NewWidget("MaskTexture")
end
function Widget:CreateFontString()
	return NewWidget("FontString")
end
function Widget:SetText(t)
	self._text = t
end
function Widget:GetText()
	return self._text
end
function Widget:GetStringWidth()
	return 60
end
function Widget:GetStringHeight()
	return 12
end
function Widget:SetValue(v)
	self._value = v
	local fn = self._scripts.OnValueChanged
	if fn then
		fn(self, v)
	end
end
function Widget:GetValue()
	return self._value or 0
end
function Widget:SetFont()
	return true
end

function CreateFrame(kind, name, parent, template)
	local w = NewWidget(kind or "Frame", name)
	w._parent = parent
	if name then
		_G[name] = w
	end
	return w
end

UIParent = CreateFrame("Frame", "UIParent")
Minimap = CreateFrame("Frame", "Minimap")
Minimap._w = 140
UISpecialFrames = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
SOUNDKIT = { RAID_WARNING = 8959 }
function CreateColor(r, g, b, a)
	return { r = r, g = g, b = b, a = a }
end
function GetCursorPosition()
	return 420, 300
end

-- Real hooksecurefunc semantics: the hook runs after the original.
function hooksecurefunc(a, b, c)
	local tbl, key, fn = a, b, c
	if type(a) == "string" then
		tbl, key, fn = _G, a, b
	end
	local orig = tbl[key]
	tbl[key] = function(...)
		local r = { orig(...) }
		fn(...)
		return (unpack or table.unpack)(r)
	end
end

------------------------------------------------------------------------
-- Events and time
------------------------------------------------------------------------

function FireEvent(event, ...)
	for _, f in ipairs(WOW.frames) do
		if f._events[event] and f._scripts.OnEvent then
			f._scripts.OnEvent(f, event, ...)
		end
	end
end

function RunUpdates(seconds, step)
	step = step or 0.05
	local t = 0
	while t < seconds do
		WOW.time = WOW.time + step
		t = t + step
		for _, f in ipairs(WOW.frames) do
			local fn = f._scripts.OnUpdate
			if fn and f._shown then
				fn(f, step)
			end
		end
	end
end

C_Timer = {
	After = function(_, fn)
		WOW.timers = WOW.timers or {}
		WOW.timers[#WOW.timers + 1] = fn
	end,
}

------------------------------------------------------------------------
-- Game API
------------------------------------------------------------------------

function GetTime()
	return WOW.time
end
function GetLocale()
	return WOW.locale or "enUS"
end
function print(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(i, ...)))
	end
	WOW.printed[#WOW.printed + 1] = table.concat(parts, " ")
end
function InCombatLockdown()
	return WOW.combat
end
function UnitAffectingCombat(unit)
	return unit == "player" and WOW.combat or false
end
function UnitClass(unit)
	if unit == "player" then
		return "Paladin", WOW.class or "PALADIN"
	end
	local m = WOW.group and WOW.group[unit]
	if m then
		return m, m
	end
	return nil
end
function UnitExists(unit)
	return unit == "player" or (WOW.group and WOW.group[unit] ~= nil) or false
end
function UnitIsUnit(a, b)
	return a == b
end
function UnitLevel()
	return 60
end
function UnitName(unit)
	return unit == "player" and "Tester" or unit
end
function GetRealmName()
	return "Realm"
end
function UnitGUID(unit)
	if WOW.combat and WOW.secretGUID then
		return SECRET
	end
	return unit == "player" and "Player-1" or "Unit-" .. unit
end
function UnitAttackSpeed()
	if WOW.combat and not WOW.speedReadableInCombat then
		return SECRET
	end
	return WOW.speed or 2.6, nil
end
function UnitIsDeadOrGhost()
	return false
end
function IsFlying()
	return WOW.flying or false
end
function IsResting()
	return false
end
function IsMounted()
	return WOW.mounted or false
end
function IsShiftKeyDown()
	return false
end
function IsAltKeyDown()
	return false
end
function GetNumGroupMembers()
	local n = 0
	for _ in pairs(WOW.group or {}) do
		n = n + 1
	end
	return n
end
function GetNumSubgroupMembers()
	return GetNumGroupMembers()
end
function IsInRaid()
	return false
end
function PlaySound(id)
	WOW.sounds[#WOW.sounds + 1] = id
end

Enum = {
	SpellBookSpellBank = { Player = 0 },
	SpellBookItemType = { Spell = 1, FutureSpell = 2 },
	SecrecyLevel = { NeverSecret = 0, AlwaysSecret = 1, ContextuallySecret = 2 },
}

C_Spell = {
	GetSpellName = function(id)
		local s = WOW.spells[id]
		return s and s[1] or nil
	end,
	GetSpellTexture = function(id)
		local s = WOW.spells[id]
		return s and (s[2] or 135000) or nil
	end,
	GetSpellCooldown = function(id)
		local cd = WOW.cooldowns[id]
		if cd == "SECRET" then
			return { startTime = SECRET, duration = SECRET }
		end
		return cd or { startTime = 0, duration = 0, isEnabled = true }
	end,
}

C_SpellBook = {
	GetNumSpellBookSkillLines = function()
		return 1
	end,
	GetSpellBookSkillLineInfo = function()
		return { itemIndexOffset = 0, numSpellBookItems = #WOW.book }
	end,
	GetSpellBookItemType = function(index)
		local entry = WOW.book[index]
		if type(entry) == "table" then
			return entry.future and 2 or 1, entry.id, entry.id
		end
		return 1, entry, entry
	end,
	IsSpellKnown = function(id)
		return WOW.known[id] or false
	end,
}
function IsPlayerSpell(id)
	return WOW.known[id] or false
end

-- Per-spell secrecy follows "everything hidden"; one unrelated secret aura
-- also sets the general flag, as Forever does in some situations.
C_Secrets = {
	ShouldAurasBeSecret = function()
		return WOW.aurasHidden or WOW.oneSecretAura
	end,
	ShouldSpellAuraBeSecret = function()
		return WOW.aurasHidden
	end,
}

C_UnitAuras = {
	GetAuraDataByIndex = function(unit, i, filter)
		if unit ~= "player" then
			return nil
		end
		if WOW.aurasHidden then
			return i == 1 and SECRET or nil
		end
		if WOW.oneSecretAura and (filter or "HELPFUL") == "HELPFUL" then
			if i == 1 then
				return SECRET
			end
			return WOW.auras.HELPFUL[i - 1]
		end
		return WOW.auras[filter or "HELPFUL"][i]
	end,
	GetPlayerAuraBySpellID = function(id)
		if WOW.aurasHidden then
			return nil
		end
		for _, list in pairs(WOW.auras) do
			for _, a in ipairs(list) do
				if a.spellId == id then
					return a
				end
			end
		end
		return nil
	end,
}

function GetNumTalentTabs()
	return WOW.talents and #WOW.talents or 0
end
function GetNumTalents(tab)
	return #WOW.talents[tab]
end
function GetTalentInfo(tab, i)
	local t = WOW.talents[tab][i]
	return t[1], 1, 1, 1, t[2], 5
end

function GetInventoryItemID(_, slot)
	local it = WOW.inventory[slot]
	return it and it.id or nil
end
function GetInventoryItemLink(_, slot)
	local it = WOW.inventory[slot]
	return it and it.link or nil
end
C_Item = {
	GetItemInfoInstant = function(id)
		for _, it in pairs(WOW.inventory) do
			if it.id == id then
				return id, "Armor", "Misc", it.equipLoc
			end
		end
	end,
}

function UnitDefense()
	return WOW.stats.defense[1], WOW.stats.defense[2]
end
function GetDodgeChance()
	return WOW.stats.dodge
end
function GetParryChance()
	return WOW.stats.parry
end
function GetBlockChance()
	return WOW.stats.block
end
function GetShieldBlock()
	return WOW.stats.blockValue
end
function UnitArmor()
	return WOW.stats.armor, WOW.stats.armor
end
function UnitHealthMax()
	return WOW.stats.hp
end
function GetSpellBonusDamage()
	return 100
end
function GetSpellBonusHealing()
	return 120
end
function GetHitModifier()
	return 2
end

------------------------------------------------------------------------
-- Loading the addon
------------------------------------------------------------------------

-- Files listed in Bulwark.toc, in order.
function TocFiles()
	local files = {}
	for raw in io.lines("Bulwark.toc") do
		local line = raw:gsub("\r", "")
		if line ~= "" and not line:match("^##") then
			files[#files + 1] = (line:gsub("\\", "/"))
		end
	end
	return files
end

-- Loads every TOC file with one shared namespace, like the game does.
-- Returns ns and the list of files loaded.
function LoadAddon(upTo)
	local ns = {}
	local loaded = {}
	for _, path in ipairs(TocFiles()) do
		local chunk = assert(loadfile(path))
		chunk("Bulwark", ns)
		loaded[#loaded + 1] = path
		if upTo and path == upTo then
			break
		end
	end
	return ns, loaded
end

-- Loads the addon and runs the usual startup events.
function BootAddon(db)
	BulwarkDB = db
	local ns, files = LoadAddon()
	FireEvent("ADDON_LOADED", "Bulwark")
	FireEvent("PLAYER_LOGIN")
	FireEvent("PLAYER_ENTERING_WORLD")
	return ns, files
end

function Report(name)
	io.write(string.format("%s: %d checks, %d failed\n", name, TESTS or 0, FAILED or 0))
	os.exit((FAILED or 0) == 0 and 0 or 1)
end
