--[[
  Bulwark core: applying settings and the login sequence.
  Loaded last among the core files, before the modules.
]]

local ADDON_NAME, ns = ...
ns = ns or {}

-- Re-layout everything from BulwarkDB. Safe to call at any time.
function ns.ApplyAll()
	if type(BulwarkDB) ~= "table" then
		return
	end
	ns.Line.Apply()
	ns.Abilities.Apply()
	ns.Reminders.Apply()
	ns.Mitigation.Apply()
	ns.Prep.Apply()
	ns.Minimap.Place()
	if ns.Options.frame:IsShown() then
		ns.Options.Refresh()
	end
end

ns.On("PLAYER_LOGIN", function()
	ns.DB()
	-- Bulwark.SetLocked (hooked by the modules) applies the layout too.
	_G.Bulwark.SetLocked(BulwarkDB.locked ~= false)
end)

ns.On("PLAYER_ENTERING_WORLD", function()
	ns.ApplyAll()
end)

ns.On("UI_SCALE_CHANGED", function()
	ns.ApplyAll()
end)

-- If the game ever blocks something Bulwark did, say which function it was,
-- once per session, and keep it in BulwarkDB.lastBlocked for a bug report.
local blockedSeen = {}
local function OnBlocked(_, addon, func)
	if addon ~= ADDON_NAME then
		return
	end
	func = tostring(func or "?")
	BulwarkDB = BulwarkDB or {}
	BulwarkDB.lastBlocked = { func = func, at = date and date("%Y-%m-%d %H:%M") or "" }
	if not blockedSeen[func] then
		blockedSeen[func] = true
		print("|cfff4c430Bulwark|r the game blocked: " .. func .. " (please send this line to addicted)")
	end
end
ns.On("ADDON_ACTION_BLOCKED", OnBlocked)
ns.On("ADDON_ACTION_FORBIDDEN", OnBlocked)
