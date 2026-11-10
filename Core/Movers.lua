--[[
  Bulwark core: moving things, test mode, reset.

  /bulwark unlock: the line, the ability group, the warning text and both
  badges become draggable and show a preview. On the line: mouse wheel =
  scale, Shift+wheel = width, Alt+wheel = thickness, right-click = options.
  On the ability group: wheel = icon size, Shift+wheel = spacing.
  /bulwark test: sample icons, reminders and a running swing rail for 12 s.
]]

local ADDON_NAME, ns = ...
ns = ns or {}
local G, W, T = ns.G, ns.W, ns.T

local MV = {}
ns.Movers = MV

MV.unlocked = false
MV.testing = false
MV.TEST_SECONDS = 12
local testStart = 0

function MV.TestElapsed()
	return G.Now() - testStart
end

function MV.StartTest()
	testStart = G.Now()
	MV.testing = true
	ns.ApplyAll()
	ns.Print(T("test mode for %d seconds."), MV.TEST_SECONDS)
end

ns.Every(0.5, function()
	if MV.testing and MV.TestElapsed() >= MV.TEST_SECONDS then
		MV.testing = false
		ns.ApplyAll()
	end
end)

------------------------------------------------------------------------
-- Geometry helpers (UIParent units)
------------------------------------------------------------------------

local function Center(frame)
	local cx, cy = frame:GetCenter()
	cx, cy = G.Num(cx), G.Num(cy)
	if not cx then
		return nil
	end
	local s = (G.Num(frame:GetEffectiveScale()) or 1) / (G.Num(UIParent:GetEffectiveScale()) or 1)
	return cx * s, cy * s, s
end

local function Size(frame, s)
	return (G.Num(frame:GetWidth()) or 0) * (s or 1), (G.Num(frame:GetHeight()) or 0) * (s or 1)
end

------------------------------------------------------------------------
-- Drag handlers
------------------------------------------------------------------------

local function SaveLine(frame)
	local db = ns.DB()
	db.x, db.y = W.CenterOffset(frame)
end

local function SaveAbilities(frame)
	local db = ns.DB()
	local line = ns.Line.frame
	local gx, gy, gs = Center(frame)
	local lx, ly, ls = Center(line)
	if not gx or not lx then
		return
	end
	local gw = Size(frame, gs)
	local lw = Size(line, ls)
	if db.readyAlign == "left" then
		db.readyOffX = math.floor((gx - gw / 2) - (lx - lw / 2) + 0.5)
	elseif db.readyAlign == "right" then
		db.readyOffX = math.floor((gx + gw / 2) - (lx + lw / 2) + 0.5)
	else
		db.readyOffX = math.floor(gx - lx + 0.5)
	end
	db.readyOffY = math.floor(gy - ly + 0.5)
end

local function SaveWarnings(frame)
	local db = ns.DB()
	local line = ns.Line.frame
	local wx, wy, ws = Center(frame)
	local lx, ly, ls = Center(line)
	if not wx or not lx then
		return
	end
	local _, wh = Size(frame, ws)
	local _, lh = Size(line, ls)
	db.warnOffX = math.floor(wx - lx + 0.5)
	db.warnOffY = math.floor((wy - wh / 2) - (ly + lh / 2) + 0.5)
end

local function SaveBadge(xKey, yKey)
	return function(frame)
		local db = ns.DB()
		db[xKey], db[yKey] = W.CenterOffset(frame)
	end
end

local targets = {}

local function Register(frame, save, wheel)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if MV.unlocked then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		save(self)
		ns.ApplyAll()
	end)
	if wheel then
		frame:SetScript("OnMouseWheel", function(_, delta)
			if MV.unlocked then
				wheel(delta)
				ns.ApplyAll()
				if ns.Options then
					ns.Options.Refresh()
				end
			end
		end)
	end
	targets[#targets + 1] = { frame = frame, wheel = wheel ~= nil }
end

local function Shift()
	return G.Flag(G.Read(IsShiftKeyDown)) == true
end

local function Alt()
	return G.Flag(G.Read(IsAltKeyDown)) == true
end

local function Bump(key, delta, step)
	local db = ns.DB()
	local range = ns.RANGES[key]
	db[key] = G.Clamp(G.Round(db[key] + delta * step, step), range[1], range[2])
end

function MV.Init()
	if MV.ready then
		return
	end
	MV.ready = true
	local line = ns.Line.frame
	Register(line, SaveLine, function(delta)
		if Shift() then
			Bump("width", delta, 10)
		elseif Alt() then
			Bump("lineHeight", delta, 1)
		else
			Bump("scale", delta, 0.05)
		end
	end)
	line:SetScript("OnMouseUp", function(_, button)
		if MV.unlocked and button == "RightButton" then
			ns.Options.Open("bar")
		end
	end)
	Register(ns.Abilities.frame, SaveAbilities, function(delta)
		if Shift() then
			Bump("readySpacing", delta, 1)
		else
			Bump("readyIconSize", delta, 1)
		end
	end)
	Register(ns.Reminders.frame, SaveWarnings)
	Register(ns.Reminders.rfBadge, SaveBadge("badgeRFX", "badgeRFY"))
	Register(ns.Reminders.forbBadge, SaveBadge("badgeForbX", "badgeForbY"))
end

-- Called by Bulwark.SetLocked (the modules hook that one).
function MV.Apply(locked)
	MV.Init()
	MV.unlocked = not locked
	for _, t in ipairs(targets) do
		t.frame:EnableMouse(MV.unlocked)
		if t.wheel then
			t.frame:EnableMouseWheel(MV.unlocked)
		end
	end
	ns.Line.hint:SetShown(MV.unlocked)
	ns.ApplyAll()
end

function MV.Reset()
	ns.ResetLayout()
	ns.ApplyAll()
	if ns.Options then
		ns.Options.Refresh()
	end
end
