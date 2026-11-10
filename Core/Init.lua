--[[
  Bulwark core: namespace, event bus, update loop, the public Bulwark table
  and the slash entry point.

  Contract with the modules (Aggro, Ranks, Plates, Blessings, PartyMana):
    ns.T(text)                 translation (Locales/enUS.lua)
    BulwarkDB / .locked        saved variables (Core/DB.lua)
    _G.Bulwark.SetLocked(b)    hooked by the modules with hooksecurefunc
    SlashCmdList.BULWARK       defined here, wrapped by every module
]]

local ADDON_NAME, ns = ...
ns = ns or {}

ns.NAME = "Bulwark"
ns.VERSION = "2.0.0"
ns.AUTHOR = "addicted"
ns.WEBSITE = "addicted.sh"
ns.WEBSITE_URL = "https://addicted.sh"
ns.LICENSE = "MIT"
ns.PREFIX = "|cfff4c430Bulwark|r "
ns.GOLD = { 0.96, 0.77, 0.19 }
ns.T = ns.T or function(text)
	return text
end

local T = ns.T

function ns.Print(text, ...)
	if select("#", ...) > 0 then
		text = string.format(text, ...)
	end
	print(ns.PREFIX .. tostring(text))
end

function ns.OnOff(value)
	return value and T("on") or T("off")
end

------------------------------------------------------------------------
-- Event bus: one frame, any number of handlers per event.
-- Events that may not exist on this client are registered through pcall.
------------------------------------------------------------------------

local bus = CreateFrame("Frame", "BulwarkEventFrame", UIParent)
ns.handlers = {}
ns.registered = {}

local function Report(err)
	local handler = type(geterrorhandler) == "function" and geterrorhandler()
	if type(handler) == "function" then
		handler(err)
	else
		print(ns.PREFIX .. tostring(err))
	end
end

function ns.On(event, fn)
	local list = ns.handlers[event]
	if not list then
		list = {}
		ns.handlers[event] = list
		local ok = pcall(bus.RegisterEvent, bus, event)
		ns.registered[event] = ok and true or false
	end
	list[#list + 1] = fn
	return ns.registered[event]
end

function ns.Fire(event, ...)
	local list = ns.handlers[event]
	if not list then
		return
	end
	for i = 1, #list do
		local ok, err = pcall(list[i], event, ...)
		if not ok then
			Report(err)
		end
	end
end

bus:SetScript("OnEvent", function(_, event, ...)
	ns.Fire(event, ...)
end)

------------------------------------------------------------------------
-- Update loop: subscribers run at their own interval.
------------------------------------------------------------------------

local loop = CreateFrame("Frame", "BulwarkUpdateFrame", UIParent)
local tickers = {}

function ns.Every(interval, fn)
	tickers[#tickers + 1] = { interval = interval, fn = fn, acc = interval }
end

loop:SetScript("OnUpdate", function(_, elapsed)
	for i = 1, #tickers do
		local t = tickers[i]
		t.acc = t.acc + (elapsed or 0)
		if t.acc >= t.interval then
			local ok, err = pcall(t.fn, t.acc)
			t.acc = 0
			if not ok then
				Report(err)
			end
		end
	end
end)

------------------------------------------------------------------------
-- Public table. Modules hook SetLocked, so core code always calls it
-- through _G.Bulwark.SetLocked, never through a local copy.
------------------------------------------------------------------------

local Bulwark = type(_G.Bulwark) == "table" and _G.Bulwark or {}
_G.Bulwark = Bulwark
Bulwark.version = ns.VERSION

function Bulwark.SetLocked(locked)
	locked = locked and true or false
	if type(BulwarkDB) == "table" then
		BulwarkDB.locked = locked
	end
	if ns.Movers and ns.Movers.Apply then
		ns.Movers.Apply(locked)
	end
end

function Bulwark.IsLocked()
	return not (type(BulwarkDB) == "table" and BulwarkDB.locked == false)
end

function Bulwark.OpenOptions(tab)
	if ns.Options and ns.Options.Open then
		ns.Options.Open(tab)
	end
end

-- Addon compartment (the addon button next to the minimap).
function Bulwark_OnAddonCompartmentClick()
	Bulwark.OpenOptions()
end

------------------------------------------------------------------------
-- Slash entry point. Core commands are filled in by Core/Slash.lua; the
-- modules wrap this function when they load.
------------------------------------------------------------------------

ns.commands = {}

SLASH_BULWARK1 = "/bulwark"
SLASH_BULWARK2 = "/bul"
SlashCmdList = SlashCmdList or {}
SlashCmdList.BULWARK = function(msg)
	if ns.HandleSlash then
		ns.HandleSlash(msg)
	end
end

------------------------------------------------------------------------
-- Blocked actions: tell the user, so it can be reported.
------------------------------------------------------------------------

local function OnBlocked(event, addon, func)
	if addon == ADDON_NAME or addon == ns.NAME then
		print(string.format("%s%s %s (%s)", ns.PREFIX, T("blocked call:"), tostring(func), event))
	end
end
ns.On("ADDON_ACTION_BLOCKED", OnBlocked)
ns.On("ADDON_ACTION_FORBIDDEN", OnBlocked)
