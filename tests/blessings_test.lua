-- Run: lua tests/blessings_test.lua  (from the repo root)
dofile("tests/module_stubs.lua")

local B = LoadModule("Blessings.lua").Blessings

Check(B.IsLongBlessing("Blessing of Might"), "Might is a long blessing")
Check(B.IsLongBlessing("Greater Blessing of Kings"), "Greater Kings is a long blessing")
Check(not B.IsLongBlessing("Blessing of Protection"), "Protection is short")
Check(not B.IsLongBlessing("Blessing of Freedom"), "Freedom is short")
Check(not B.IsLongBlessing("Power Word: Fortitude"), "priest buff is not a blessing")
Check(not B.IsLongBlessing(nil), "nil is not a blessing")

local list, state = B.Summarize({
	{ name = "Power Word: Fortitude" },
	{ name = "Blessing of Wisdom", mine = false },
	{ name = "Blessing of Might", mine = true },
})
Check(#list == 2, "summary keeps only blessings")
Check(list[1].name == "Blessing of Might", "your blessing first")
Check(state == "mine", "state mine")
_, state = B.Summarize({ { name = "Blessing of Kings", mine = false } })
Check(state == "other", "state other")
_, state = B.Summarize({ { name = "Mark of the Wild" } })
Check(state == "none", "state none")

Check(B.FormatLeft(1000 + 300, 1000) == "5m", "5 minutes")
Check(B.FormatLeft(1000 + 45, 1000) == "45s", "45 seconds")
Check(B.FormatLeft(0, 1000) == nil, "no end time")

Check(B.Suggest("WARRIOR").key == "might", "warriors want Might")
Check(B.Suggest("ROGUE").key == "might", "rogues want Might")
Check(B.Suggest("MAGE").key == "wisdom", "mages want Wisdom")
Check(B.Suggest("HUNTER").key == "wisdom", "hunters want Wisdom (Might is melee only)")
Check(B.Suggest("PRIEST").key == "wisdom", "priests want Wisdom")
Check(B.Suggest(nil) == nil, "unknown class: no suggestion")
for _, c in ipairs({ "WARRIOR", "MAGE", "ROGUE", "DRUID", "HUNTER", "SHAMAN", "PRIEST", "WARLOCK", "PALADIN" }) do
	Check(type(B.ClassCoords(c)) == "table" and #B.ClassCoords(c) == 4, "class icon coords for " .. c)
end
Check(B.ClassCoords("NOPE") == nil, "no coords for unknown class")

-- Collect: player + 2 party members; party2's auras are hidden (secret).
function GetNumSubgroupMembers()
	return 2
end
function UnitExists(u)
	return u == "player" or u == "party1" or u == "party2"
end
function UnitGUID(u)
	return "G-" .. u
end
function UnitIsUnit(a, b)
	return a == b
end
function UnitIsDeadOrGhost()
	return false
end
function UnitIsConnected()
	return true
end
function UnitInRange()
	return true
end
function UnitClass()
	return "Paladin", "PALADIN"
end
function issecretvalue(v)
	return v == "SECRET"
end
local hidden = false
local AURAS = {
	player = { { name = "Blessing of Might", icon = 1, expirationTime = 500, sourceUnit = "player" } },
	party1 = { { name = "Arcane Intellect" } },
	party2 = { { name = "Blessing of Wisdom", icon = 2, expirationTime = 600, sourceUnit = "party1" } },
}
C_UnitAuras = {
	GetAuraDataByIndex = function(unit, i)
		if unit == "party2" and hidden then
			return { name = "SECRET" }
		end
		return AURAS[unit][i]
	end,
}

local rows = B.Collect()
Check(#rows == 3, "three rows")
Check(rows[1].class == "PALADIN", "class read")
Check(rows[1].state == "mine", "player has my blessing")
Check(rows[2].state == "none", "party1 has no blessing")
Check(rows[3].state == "other" and not rows[3].stale, "party2 has another paladin's blessing")

hidden = true
rows = B.Collect()
Check(rows[3].state == "other" and rows[3].stale, "hidden auras keep the last state, marked stale")

-- Party frames: classic names first, raid-style frames win when shown.
local function UnitFrameStub(unit, shown)
	return {
		unit = unit,
		IsVisible = function()
			return shown
		end,
	}
end
PartyMemberFrame1 = UnitFrameStub("party1", true)
PartyMemberFrame2 = UnitFrameStub("party2", true)
PartyMemberFrame3 = UnitFrameStub("party3", false)
local list = B.PartyFrames()
Check(#list == 2 and list[1].unit == "party1" and list[2].unit == "party2", "classic party frames, hidden ones skipped")

PartyMemberFrame1, PartyMemberFrame2, PartyMemberFrame3 = nil, nil, nil
PartyFrame = { MemberFrame1 = { IsVisible = function()
	return true
end } }
list = B.PartyFrames()
Check(#list == 1 and list[1].unit == "party1", "modern PartyFrame.MemberFrame1 with fallback unit")

CompactPartyFrameMember1 = UnitFrameStub("player", true)
CompactPartyFrameMember2 = UnitFrameStub("party1", true)
list = B.PartyFrames()
Check(#list == 2 and list[1].compact and list[1].unit == "player", "raid-style party frames win")

-- Refresh draws without errors on the stubs.
BulwarkDB = {}
Check(pcall(B.Refresh), "refresh runs with party frames")
Check(BulwarkDB.blessings.frames == true and BulwarkDB.blessings.panel == false, "defaults: frames on, panel off")

io.write(string.format("%d tests, %d failed\n", TESTS or 0, FAILED or 0))
os.exit((FAILED or 0) == 0 and 0 or 1)
