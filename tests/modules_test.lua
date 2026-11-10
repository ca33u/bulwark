-- Run: lua tests/modules_test.lua  (from the repo root)
dofile("tests/module_stubs.lua")

------------------------------------------------------------------------
-- Ranks
------------------------------------------------------------------------

-- Spell ids: Holy Light 1..4 = 101..104, Seal of Righteousness 1..2 = 201..202,
-- Righteous Fury (no rank) = 301.
local SPELLS = {
	[101] = { "Holy Light", "Rank 1" },
	[102] = { "Holy Light", "Rank 2" },
	[103] = { "Holy Light", "Rank 3" },
	[104] = { "Holy Light", "Rank 4" },
	[201] = { "Seal of Righteousness", "Rank 1" },
	[202] = { "Seal of Righteousness", "Rank 2" },
	[301] = { "Righteous Fury", "" },
}
local book = { 101, 102, 103, 201, 202, 301 }
local bars = {}
local cursor

C_Spell = {
	GetSpellName = function(id)
		return SPELLS[id] and SPELLS[id][1]
	end,
	GetSpellSubtext = function(id)
		return SPELLS[id] and SPELLS[id][2]
	end,
	PickupSpell = function(id)
		cursor = id
	end,
}
C_SpellBook = {
	GetNumSpellBookSkillLines = function()
		return 1
	end,
	GetSpellBookSkillLineInfo = function()
		return { itemIndexOffset = 0, numSpellBookItems = #book }
	end,
	GetSpellBookItemType = function(j)
		return 1, book[j], book[j]
	end,
	IsSpellKnown = function(id)
		for _, b in ipairs(book) do
			if b == id then
				return true
			end
		end
		return false
	end,
}
function GetActionInfo(slot)
	if bars[slot] then
		return "spell", bars[slot]
	end
end
function GetCursorInfo()
	return cursor and "spell" or nil
end
function PlaceAction(slot)
	bars[slot] = cursor
end
function ClearCursor()
	cursor = nil
end
function InCombatLockdown()
	return false
end

local R = LoadModule("Ranks.lua").Ranks

Check(R.ParseRank("Rank 12") == 12, "ParseRank reads the number")
Check(R.ParseRank("Ранг 3") == 3, "ParseRank reads a localized rank")
Check(R.ParseRank("") == nil, "ParseRank: no rank")

local best = R.ScanSpellbook()
Check(best["Holy Light"].id == 103, "scan keeps the highest Holy Light rank")
Check(best["Seal of Righteousness"].id == 202, "scan keeps the highest Seal rank")
Check(best["Righteous Fury"] == nil, "spells without ranks are not tracked")

-- Catch-up pass: stale ranks get replaced, unranked spells untouched.
bars = { [1] = 102, [2] = 201, [3] = 301, [4] = 103, [5] = 101 }
local plan = R.PlanUpgrades(best, "all")
Check(#plan == 3, "all: three stale slots planned (got " .. #plan .. ")")
Check(R.ApplyPlan(plan) == 3, "all: three slots changed")
Check(bars[1] == 103 and bars[5] == 103 and bars[2] == 202, "all: slots now hold the highest ranks")
Check(bars[3] == 301 and bars[4] == 103, "all: other slots untouched")

-- Learned pass: only the old top rank moves up, the downrank stays.
bars = { [1] = 103, [2] = 101, [7] = 202 }
local before = R.ScanSpellbook()
book[#book + 1] = 104 -- trainer teaches Holy Light rank 4
local after = R.ScanSpellbook()
plan = R.PlanUpgrades(after, "learned", before)
Check(#plan == 1 and plan[1].slot == 1 and plan[1].to == 104, "learned: only the previous top rank is replaced")
R.ApplyPlan(plan)
Check(bars[1] == 104 and bars[2] == 101 and bars[7] == 202, "learned: downranked Holy Light kept")

-- Combat: nothing moves, caller is told to wait.
function InCombatLockdown()
	return true
end
bars = { [1] = 101 }
Check(R.ApplyPlan(R.PlanUpgrades(after, "all")) == nil, "combat: plan waits")
Check(bars[1] == 101, "combat: bar untouched")
function InCombatLockdown()
	return false
end

-- Cursor busy: do not drop what the player holds.
cursor = 999
Check(R.ApplyPlan(R.PlanUpgrades(after, "all")) == nil, "busy cursor: plan waits")
Check(cursor == 999 and bars[1] == 101, "busy cursor: nothing changed")
cursor = nil

-- Spell data not cached yet: ask the game to load it, read the rank after.
local cachedSpells = { [101] = true, [102] = true, [103] = true, [104] = true, [201] = true, [202] = true, [301] = true }
local requested = {}
C_Spell.IsSpellDataCached = function(id)
	return cachedSpells[id] == true
end
C_Spell.RequestLoadSpellData = function(id)
	requested[id] = true
end
cachedSpells[103] = nil
Check(R.SpellRank(103) == nil and requested[103], "uncached spell: rank waits, data load requested")
Check(R.waiting[103], "uncached spell is remembered until it loads")
cachedSpells[103] = true
Check(R.SpellRank(103) == 3, "after loading: rank is read")
R.waiting[103] = nil

-- Default mode upgrades skipped ranks too (rank 1 on the bar, rank 4 known).
BulwarkDB = {}
bars = { [1] = 101, [2] = 102 }
R.Run(false)
Check(bars[1] == 104 and bars[2] == 104, "default: every lower rank becomes the highest")
-- keepDownranks: only the previous top rank moves.
BulwarkDB.keepDownranks = true
bars = { [1] = 104, [3] = 101 }
R.Run(false) -- first pass takes the snapshot
book[#book + 1] = 105
SPELLS[105] = { "Holy Light", "Rank 5" }
cachedSpells[105] = true
R.Run(false)
Check(bars[1] == 105 and bars[3] == 101, "keepDownranks: top rank moves, downrank stays")
BulwarkDB = nil

------------------------------------------------------------------------
-- Aggro
------------------------------------------------------------------------

local A = LoadModule("Aggro.lua").Aggro

Check(A.Classify(3, true, false) == A.STATE_TANKING, "threat 3 = tanking")
Check(A.Classify(2, false, true) == A.STATE_LOSING, "threat 2 = losing")
Check(A.Classify(1, false, true) == A.STATE_LOOSE, "on my table, hitting a party member = loose")
Check(A.Classify(0, false, false) == nil, "hitting a stranger = not listed")
Check(A.Classify(nil, true, nil) == A.STATE_TANKING, "no threat data but targets me = tanking")
Check(A.Classify(nil, false, true) == A.STATE_LOOSE, "not on my table, hitting my group = loose")
Check(A.Classify(nil, false, false) == nil, "someone else's mob = not listed")

local rows = A.Sort({
	{ state = A.STATE_TANKING, hp = 0.2 },
	{ state = A.STATE_LOOSE, hp = 0.9 },
	{ state = A.STATE_LOSING, hp = 0.5 },
	{ state = A.STATE_LOOSE, hp = 0.3 },
})
Check(rows[1].state == A.STATE_LOOSE and rows[1].hp == 0.3, "sort: loose first, lowest health first")
Check(rows[3].state == A.STATE_LOSING and rows[4].state == A.STATE_TANKING, "sort: then losing, then tanking")

-- Scan over nameplates: two mobs on me, one loose on the healer, one stranger's.
local units = {
	nameplate1 = { attack = true, combat = true, threat = 3, target = "player" },
	nameplate2 = { attack = true, combat = true, threat = 1, target = "party1" },
	nameplate3 = { attack = true, combat = true, threat = nil, target = "stranger" },
	nameplate4 = { attack = true, combat = false },
	nameplate5 = { attack = true, combat = true, threat = 2, target = "party1" },
}
local function base(u)
	return (u:gsub("target$", ""))
end
function UnitExists(u)
	if u == "player" or u == "party1" then
		return true
	end
	if units[u] then
		return true
	end
	local b = units[base(u)]
	return b ~= nil and b.target ~= nil
end
function UnitCanAttack(_, u)
	return units[u] and units[u].attack or false
end
function UnitIsDeadOrGhost()
	return false
end
function UnitAffectingCombat(u)
	if u == "player" then
		return true
	end
	return units[u] and units[u].combat or false
end
function UnitThreatSituation(_, u)
	return units[u] and units[u].threat
end
local function resolve(u)
	local b = units[base(u)]
	if u:match("target$") and b then
		return b.target
	end
	return u
end
function UnitIsUnit(a, b)
	return resolve(a) == resolve(b)
end
function UnitInParty(u)
	return resolve(u) == "party1"
end
function UnitInRaid()
	return nil
end
function UnitHealth()
	return 50
end
function UnitHealthMax()
	return 100
end
function UnitGUID(u)
	return u
end
function UnitName(u)
	return resolve(u)
end
function GetRaidTargetIndex()
	return nil
end

rows = A.Scan()
Check(#rows == 3, "scan lists three mobs (got " .. #rows .. ")")
Check(rows[1].unit == "nameplate2" and rows[1].targetName == "party1", "scan: loose mob first, with its target")
Check(rows[2].unit == "nameplate5", "scan: losing mob second")
Check(rows[3].unit == "nameplate1", "scan: tanked mob last")

-- Secret values: every read errors or is secret -> no crash, nothing listed.
function issecretvalue(v)
	return v == "SECRET"
end
function UnitThreatSituation()
	return "SECRET"
end
function UnitIsUnit()
	error("blocked")
end
local ok = pcall(A.Scan)
Check(ok, "scan survives secret threat values")

io.write(string.format("\n%d checks, %d failed\n", TESTS, FAILED or 0))
os.exit((FAILED or 0) == 0 and 0 or 1)
