-- Run: lua tests/plates_test.lua  (from the repo root)
dofile("tests/module_stubs.lua")

-- A fake world: nameplate1 is on me, nameplate2 is loose, nameplate3 is a
-- player, nameplate4 is out of combat, nameplate5 has hidden threat but hits me.
local SECRET = {}
issecretvalue = function(v)
	return v == SECRET
end
local world = {
	nameplate1 = { threat = 3, target = "player" },
	nameplate2 = { threat = 0, target = "party1" },
	nameplate3 = { threat = 3, player = true, target = "player" },
	nameplate4 = { threat = nil, combat = false },
	nameplate5 = { threat = SECRET, target = "player" },
	nameplate6 = { threat = 2, target = "player" },
}
local function mob(unit)
	return world[unit]
end
function UnitExists(unit)
	if unit:match("target$") then
		local m = mob(unit:gsub("target$", ""))
		return m and m.target ~= nil
	end
	return mob(unit) ~= nil
end
function UnitCanAttack(_, unit)
	return mob(unit) ~= nil
end
function UnitIsPlayer(unit)
	return mob(unit) and mob(unit).player or false
end
function UnitIsDeadOrGhost()
	return false
end
function UnitAffectingCombat(unit)
	local m = mob(unit)
	return m and m.combat ~= false
end
function UnitThreatSituation(_, unit)
	return mob(unit).threat
end
function UnitIsUnit(a, b)
	local m = mob(a:gsub("target$", ""))
	return m and m.target == b
end
function UnitInParty(a)
	local m = mob(a:gsub("target$", ""))
	return m and m.target == "party1"
end
function UnitInRaid()
	return false
end

local touched = 0 -- calls on Blizzard's own bar: must stay 0
local function Frame(unit)
	return { unit = unit, healthBar = {
		SetStatusBarColor = function() touched = touched + 1 end,
		GetStatusBarTexture = function() return {} end,
		GetFrameLevel = function() return 1 end,
	} }
end
local frames = {}
for i = 1, 6 do
	frames[i] = { UnitFrame = Frame("nameplate" .. i) }
end
C_NamePlate = { GetNamePlates = function()
	return frames
end }
local restored = 0
function CompactUnitFrame_UpdateHealthColor()
	restored = restored + 1
end
BulwarkDB = {}

local ns = LoadModule("Plates.lua")
local P = ns.Plates

-- Classify
Check(P.Classify(3) == P.STATE_SECURE, "threat 3 is secure")
Check(P.Classify(2) == P.STATE_INSECURE, "threat 2 is insecure")
Check(P.Classify(1) == P.STATE_INSECURE, "threat 1 is insecure")
Check(P.Classify(0, false, true) == P.STATE_LOOSE, "threat 0 on a group member is loose")
Check(P.Classify(0, false, false) == nil, "threat 0 on a stranger keeps default")
Check(P.Classify(nil, true) == P.STATE_SECURE, "hidden threat, hitting me: secure")
Check(P.Classify(nil, nil, nil) == nil, "nothing known keeps default")
Check(P.Classify(nil, false, true) == P.STATE_LOOSE, "hidden threat, hitting a friend: loose")

-- StateFor through the guarded reads
Check(P.StateFor("nameplate1") == P.STATE_SECURE, "plate 1 secure")
Check(P.StateFor("nameplate2") == P.STATE_LOOSE, "plate 2 loose")
Check(P.StateFor("nameplate3") == nil, "player plate untouched")
Check(P.StateFor("nameplate4") == nil, "out of combat untouched")
Check(P.StateFor("nameplate5") == P.STATE_SECURE, "secret threat but targeting me")
Check(P.StateFor("nameplate6") == P.STATE_INSECURE, "plate 6 insecure")
Check(P.StateFor("nameplate9") == nil, "missing unit untouched")

-- PaintAll: our own overlay on each plate, Blizzard's bar untouched
local function ColorOf(i)
	local o = P.overlays[frames[i]]
	return o and o.on and o.color or nil
end
P.PaintAll()
Check(ColorOf(1) and ColorOf(1)[2] > 0.8, "plate 1 painted green")
Check(ColorOf(2) and ColorOf(2)[1] == 1 and ColorOf(2)[2] < 0.3, "plate 2 painted red")
Check(ColorOf(3) == nil, "player plate not painted")
Check(ColorOf(4) == nil, "out-of-combat plate not painted")
Check(touched == 0, "the game's nameplate bar is never touched (no taint)")

-- Toggle off hides our overlays
BulwarkDB.plates.enabled = false
P.RestoreAll()
Check(restored == 0, "restore never calls Blizzard code (taint), got " .. restored)
Check(ColorOf(1) == nil and ColorOf(2) == nil, "turned off: overlays hidden")
P.PaintAll()
Check(ColorOf(1) == nil and touched == 0, "disabled paints nothing")

-- Nameplate CVar reset: Threat Plates left alpha 0 and enemies hidden.
local cvars = { nameplateMinAlpha = "0", nameplateShowEnemies = "0", nameplateGlobalScale = "0.4" }
local defaultsCV = { nameplateMinAlpha = "0.6", nameplateGlobalScale = "1" }
C_CVar = {
	GetCVarDefault = function(n)
		return defaultsCV[n]
	end,
	SetCVar = function(n, v)
		cvars[n] = v
	end,
}
function InCombatLockdown()
	return true
end
Check(P.ResetNameplateCVars() == nil, "reset waits in combat")
Check(cvars.nameplateShowEnemies == "0", "nothing written in combat")
function InCombatLockdown()
	return false
end
local n = P.ResetNameplateCVars()
Check(n == 3, "reset wrote two defaults plus enemies on, got " .. tostring(n))
Check(cvars.nameplateMinAlpha == "0.6" and cvars.nameplateGlobalScale == "1", "alpha and scale back to defaults")
Check(cvars.nameplateShowEnemies == "1", "enemy nameplates on")

-- Forbidden frames: never read, never painted
local touched = false
local forbidden = setmetatable({ IsForbidden = function()
	return true
end }, { __index = function()
	touched = true
	error("forbidden frame read")
end })
Check(P.IsForbidden(forbidden), "IsForbidden detects a forbidden frame")
Check(not P.IsForbidden({ IsForbidden = function()
	return false
end }), "normal frame is not forbidden")
BulwarkDB.plates.enabled = true
frames[#frames + 1] = { UnitFrame = forbidden }
painted = {}
Check(pcall(P.PaintAll), "PaintAll skips forbidden plates without errors")
Check(not touched, "no field of a forbidden frame was read")
Check(pcall(P.Paint, forbidden) and not touched, "Paint ignores a forbidden frame")

io.write(string.format("%d tests, %d failed\n", TESTS or 0, FAILED or 0))
os.exit((FAILED or 0) == 0 and 0 or 1)
