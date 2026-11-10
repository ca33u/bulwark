-- Run: lua tests/partymana_test.lua  (from the repo root)
dofile("tests/module_stubs.lua")

local ns = { Blessings = {} }
local chunk = assert(loadfile("PartyMana.lua"))
chunk("Bulwark", ns)
local M = ns.PartyMana

local units = {
	party1 = { power = 0, cur = 400, max = 2000 },          -- priest at 20 %
	party2 = { power = 0, cur = 1800, max = 2000 },         -- mage at 90 %
	party3 = { power = 1, cur = 10, max = 100 },            -- warrior (rage)
	party4 = { power = 0, cur = 0, max = 1500, dead = true }, -- dead healer
	party5 = { power = 0, cur = "SECRET", max = 1500 },     -- hidden in combat
}
function issecretvalue(v)
	return v == "SECRET"
end
function UnitExists(u)
	return units[u] ~= nil
end
function UnitIsDeadOrGhost(u)
	return units[u].dead or false
end
function UnitIsConnected()
	return true
end
function UnitPowerType(u)
	return units[u].power
end
function UnitPower(u)
	return units[u].cur
end
function UnitPowerMax(u)
	return units[u].max
end

Check(M.ManaFraction("party1") == 0.2, "priest at 20 %")
Check(M.ManaFraction("party3") == nil, "rage users are skipped")
Check(M.ManaFraction("party4") == nil, "dead members are skipped")
Check(M.ManaFraction("party5") == nil, "hidden mana gives no guess")
Check(M.ManaFraction("party9") == nil, "missing unit")

Check(M.IsLow(0.2, 30), "20 % is low under 30")
Check(not M.IsLow(0.9, 30), "90 % is fine")
Check(not M.IsLow(nil, 30), "unknown is not low")
Check(M.IsLow(0.29, nil), "default threshold 30")

-- Mana bar lookup: field names, then global name + "ManaBar"
Check(M.ManaBarOf({ manabar = { id = 1 } }).id == 1, "classic manabar field")
Check(M.ManaBarOf({ powerBar = { id = 2 } }).id == 2, "raid-style powerBar field")
PartyMemberFrame1ManaBar = { id = 3 }
Check(M.ManaBarOf({ GetName = function()
	return "PartyMemberFrame1"
end }).id == 3, "global PartyMemberFrame1ManaBar")
Check(M.ManaBarOf({}) == nil, "no bar found")

-- Refresh over two frames: only the low one gets an overlay.
local shown = {}
local real = CreateFrame
CreateFrame = function()
	local f = real()
	rawset(f, "Show", function(self)
		shown[self] = true
	end)
	rawset(f, "Hide", function(self)
		shown[self] = nil
	end)
	return f
end
ns.Blessings.PartyFrames = function()
	return { { frame = { manabar = {} }, unit = "party1" }, { frame = { manabar = {} }, unit = "party2" } }
end
BulwarkDB = {}
local ok, err = pcall(M.Refresh, 0.1)
local count = 0
for _ in pairs(shown) do
	count = count + 1
end
Check(ok, "refresh runs " .. tostring(err or ""))
Check(count == 1, "one overlay for the low-mana member, got " .. count)
Check(BulwarkDB.lowMana.threshold == 30, "default threshold stored")

local src = io.open("PartyMana.lua"):read("a")
Check(src:find('SetFrameStrata("HIGH")', 1, true) ~= nil, "overlay sits above the party frames")
Check(M.Explain("party1"):find("mana", 1, true) ~= nil, "manadebug explains a mana user: " .. M.Explain("party1"))
Check(M.Explain("nobody") == "no unit", "manadebug: missing unit")

io.write(string.format("%d tests, %d failed\n", TESTS or 0, FAILED or 0))
os.exit((FAILED or 0) == 0 and 0 or 1)
