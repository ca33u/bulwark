--[[
  Bulwark: threat colors on the default nameplates.

  Replaces Threat Plates for a tank: the game's own nameplates stay, only the
  health bar of an enemy that is in combat with you changes color:
    green  - it is attacking you and you hold it (secure)
    orange - it is on you but someone is about to pull it, or you are
             climbing its list without holding it
    red    - loose: in combat with your group, hitting someone else
  Out of combat, players, and units whose threat the client hides keep the
  default colors. Enemy nameplates must be on (V key).

  /bulwark plates   turn the coloring on or off

  Every unit read goes through pcall and the secret-value check: a hidden
  value means "leave the default color", never a guess.
]]

local ADDON_NAME, ns = ...
ns = ns or {}
local T = ns.T or function(text)
	return text
end

local P = {}
ns.Plates = P

local PREFIX = "|cfff4c430Bulwark|r "

P.STATE_SECURE, P.STATE_INSECURE, P.STATE_LOOSE = 3, 2, 1

-- Threat Plates tank palette: high threat green, medium orange, low red.
local COLORS = {
	[3] = { 0.25, 0.85, 0.35 },
	[2] = { 1.00, 0.62, 0.15 },
	[1] = { 1.00, 0.27, 0.22 },
}

------------------------------------------------------------------------
-- Guards
------------------------------------------------------------------------

local function IsSecret(value)
	return issecretvalue and issecretvalue(value) and true or false
end

local function Read(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a = pcall(fn, ...)
	if not ok or IsSecret(a) then
		return nil
	end
	return a
end

local function IndexField(tbl, key)
	return tbl[key]
end

local function SafeGet(tbl, key)
	if type(tbl) ~= "table" or IsSecret(tbl) then
		return nil
	end
	local ok, value = pcall(IndexField, tbl, key)
	if not ok or IsSecret(value) then
		return nil
	end
	return value
end

local function DB()
	if type(BulwarkDB) ~= "table" then
		return nil
	end
	local d = BulwarkDB.plates
	if type(d) ~= "table" then
		d = { enabled = true }
		BulwarkDB.plates = d
	end
	if d.enabled == nil then
		d.enabled = true
	end
	return d
end

------------------------------------------------------------------------
-- Classification (pure, unit-tested in tests/plates_test.lua)
------------------------------------------------------------------------

-- threat: UnitThreatSituation("player", mob) -> nil, 0, 1, 2, 3
-- targetIsMe: the mob's target is the player (nil = unknown)
-- targetIsGroup: the mob's target is in the player's group (nil = unknown)
-- Returns a state, or nil to keep the default color.
function P.Classify(threat, targetIsMe, targetIsGroup)
	if threat == 3 then
		return P.STATE_SECURE
	end
	if threat == 2 then
		return P.STATE_INSECURE
	end
	if targetIsMe then
		-- Threat hidden, but the mob is hitting me: close enough to secure.
		return P.STATE_SECURE
	end
	if threat == 1 then
		return P.STATE_INSECURE
	end
	if threat == 0 then
		if targetIsGroup == false then
			return nil -- fighting a guard or another player, not my mob
		end
		return P.STATE_LOOSE
	end
	if targetIsGroup then
		return P.STATE_LOOSE
	end
	return nil
end

------------------------------------------------------------------------
-- Unit reads
------------------------------------------------------------------------

local function IsGroupUnit(unit)
	if Read(UnitIsUnit, unit, "player") or Read(UnitIsUnit, unit, "pet") then
		return true
	end
	if Read(UnitInParty, unit) or Read(UnitInRaid, unit) then
		return true
	end
	return false
end

-- Returns the state for a nameplate unit, or nil to keep the default color.
function P.StateFor(unit)
	if type(unit) ~= "string" or not Read(UnitExists, unit) then
		return nil
	end
	if not Read(UnitCanAttack, "player", unit) or Read(UnitIsPlayer, unit) then
		return nil
	end
	if Read(UnitIsDeadOrGhost, unit) or not Read(UnitAffectingCombat, unit) then
		return nil
	end
	local threat = Read(UnitThreatSituation, "player", unit)
	local target = unit .. "target"
	local targetIsMe, targetIsGroup
	if Read(UnitExists, target) then
		targetIsMe = Read(UnitIsUnit, target, "player")
		targetIsGroup = IsGroupUnit(target)
	end
	return P.Classify(threat, targetIsMe, targetIsGroup)
end

------------------------------------------------------------------------
-- Painting
------------------------------------------------------------------------

local painted = {}

-- Forbidden frames (friendly nameplates in instances, some Blizzard unit
-- frames) may not be touched by addons at all: even reading a field raises
-- the "blocked from an action only available to the Blizzard UI" popup,
-- and pcall does not stop it. IsForbidden itself is always allowed.
function P.IsForbidden(frame)
	if type(frame) ~= "table" then
		return true
	end
	local fn = frame.IsForbidden
	if type(fn) ~= "function" then
		return false
	end
	local ok, forbidden = pcall(fn, frame)
	return not ok or forbidden == true
end

local function PlateUnitFrame(plate)
	if type(plate) ~= "table" or P.IsForbidden(plate) then
		return nil
	end
	local frame = plate.UnitFrame
	if type(frame) ~= "table" or P.IsForbidden(frame) then
		return nil
	end
	return frame
end

local function UnitOf(frame)
	if P.IsForbidden(frame) then
		return nil
	end
	local unit = frame and frame.unit
	if type(unit) ~= "string" or IsSecret(unit) then
		return nil
	end
	if not unit:match("^nameplate%d+$") then
		return nil
	end
	return unit
end

-- Bulwark never changes the game's nameplates (setting their colors in
-- combat taints them, and the game then blocks its own nameplate code and
-- blames Bulwark). Instead each plate gets our own small frame with one
-- texture laid over the filled part of the health bar. Our frame is a
-- child of the plate so it moves, scales and hides with it.
local overlays = {} -- plate -> our frame
P.overlays = overlays

local function Overlay(plate, frame)
	local o = overlays[plate]
	if not o then
		o = CreateFrame("Frame", nil, plate)
		o.tex = o:CreateTexture(nil, "OVERLAY")
		o.tex:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
		overlays[plate] = o
	end
	local bar = frame.healthBar
	local fill = type(bar) == "table" and type(bar.GetStatusBarTexture) == "function" and Read(bar.GetStatusBarTexture, bar)
	if type(fill) ~= "table" then
		return nil
	end
	o:SetFrameLevel((Read(bar.GetFrameLevel, bar) or 1) + 2)
	o:SetAllPoints(bar)
	o.tex:ClearAllPoints()
	o.tex:SetAllPoints(fill)
	return o
end

local function Clear(plate)
	local o = overlays[plate]
	if o then
		o:Hide()
		o.on = false
	end
	painted[plate] = nil
end

function P.Paint(frame, plate)
	if P.IsForbidden(frame) then
		return
	end
	local d = DB()
	plate = plate or Read(frame.GetParent, frame)
	if not plate then
		return
	end
	if not d or not d.enabled then
		Clear(plate)
		return
	end
	local unit = UnitOf(frame)
	if not unit then
		Clear(plate)
		return
	end
	local state = P.StateFor(unit)
	if not state then
		Clear(plate)
		return
	end
	local o = Overlay(plate, frame)
	if not o then
		return
	end
	local c = COLORS[state]
	o.tex:SetVertexColor(c[1], c[2], c[3], 1)
	o.color = c
	o.on = true
	o:Show()
	painted[plate] = true
end

function P.PaintAll()
	if not C_NamePlate or type(C_NamePlate.GetNamePlates) ~= "function" then
		return
	end
	local ok, plates = pcall(C_NamePlate.GetNamePlates)
	if not ok or type(plates) ~= "table" then
		return
	end
	for i = 1, #plates do
		local frame = PlateUnitFrame(plates[i])
		if frame then
			P.Paint(frame, plates[i])
		end
	end
end

function P.RestoreAll()
	for plate in pairs(overlays) do
		Clear(plate)
	end
end

------------------------------------------------------------------------
-- Updates
------------------------------------------------------------------------

local ticker = CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
	acc = acc + elapsed
	if acc < 0.25 then
		return
	end
	acc = 0
	local d = DB()
	if d and d.enabled then
		P.PaintAll()
	end
end)

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
	if event == "PLAYER_LOGIN" then
		-- Once per account: undo what a removed Threat Plates left behind.
		local d = DB()
		local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
		if d and not d.cvarsReset and not Read(isLoaded, "TidyPlates_ThreatPlates") then
			local n = P.ResetNameplateCVars()
			if n then
				d.cvarsReset = true
				print(PREFIX .. string.format(T("nameplate settings reset to game defaults (%d), enemy nameplates on."), n))
			end
		end
		return
	end
	if event == "NAME_PLATE_UNIT_ADDED" and type(unit) == "string" and not IsSecret(unit) then
		if C_NamePlate and type(C_NamePlate.GetNamePlateForUnit) == "function" then
			local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
			local frame = ok and PlateUnitFrame(plate)
			if frame then
				P.Paint(frame, plate)
			end
		end
		return
	end
	if event == "NAME_PLATE_UNIT_REMOVED" and type(unit) == "string" and not IsSecret(unit) then
		if C_NamePlate and type(C_NamePlate.GetNamePlateForUnit) == "function" then
			local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
			if ok and plate then
				Clear(plate)
			end
		end
		return
	end
	P.PaintAll()
end)
events:RegisterEvent("PLAYER_LOGIN")
pcall(events.RegisterEvent, events, "NAME_PLATE_UNIT_REMOVED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(events.RegisterEvent, events, "NAME_PLATE_UNIT_ADDED")
pcall(events.RegisterEvent, events, "UNIT_THREAT_SITUATION_UPDATE")
pcall(events.RegisterEvent, events, "UNIT_THREAT_LIST_UPDATE")

------------------------------------------------------------------------
-- Slash: /bulwark plates
------------------------------------------------------------------------

-- Threat Plates changes these CVars and does not put them back when it is
-- removed, which can leave the default nameplates invisible or tiny.
P.RESET_CVARS = {
	"nameplateMinAlpha", "nameplateMaxAlpha", "nameplateSelectedAlpha",
	"nameplateNotSelectedAlpha", "nameplateOccludedAlphaMult",
	"nameplateGlobalScale", "nameplateMinScale", "nameplateMaxScale",
	"nameplateSelectedScale", "nameplateLargerScale",
	"nameplateOverlapV", "nameplateOverlapH", "nameplateShowAll",
	"nameplateShowEnemyMinions", "nameplateShowEnemyMinus",
}

-- Sets every CVar above to the game default and turns enemy nameplates on.
-- Returns the number of CVars written, or nil in combat.
function P.ResetNameplateCVars()
	if InCombatLockdown and InCombatLockdown() then
		return nil
	end
	local getDefault = C_CVar and C_CVar.GetCVarDefault or GetCVarDefault
	local set = C_CVar and C_CVar.SetCVar or SetCVar
	local count = 0
	for _, name in ipairs(P.RESET_CVARS) do
		local value = Read(getDefault, name)
		if value ~= nil and pcall(set, name, value) then
			count = count + 1
		end
	end
	if pcall(set, "nameplateShowEnemies", "1") then
		count = count + 1
	end
	return count
end

local previous = SlashCmdList and SlashCmdList.BULWARK
if previous then
	SlashCmdList.BULWARK = function(msg)
		local cmd = string.lower(msg or ""):match("^(%S+)") or ""
		local d = DB()
		if cmd == "plates" and d then
			d.enabled = not d.enabled
			print(PREFIX .. T("threat colors on nameplates:"), d.enabled and T("on") or T("off"))
			if d.enabled then
				P.PaintAll()
			else
				P.RestoreAll()
			end
			return
		elseif cmd == "platesreset" then
			local n = P.ResetNameplateCVars()
			if n == nil then
				print(PREFIX .. T("nameplate reset: leave combat first."))
			else
				print(PREFIX .. string.format(T("nameplate settings reset to game defaults (%d), enemy nameplates on."), n))
			end
			return
		end
		previous(msg)
		if cmd == "" or cmd == "help" then
			print(T("  |cffaaaaaa/bulwark|r plates | platesreset"))
		end
	end
end
