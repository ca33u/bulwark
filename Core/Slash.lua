--[[
  Bulwark core: slash commands (/bulwark, /bul).

  The modules wrap SlashCmdList.BULWARK; every command they do not know
  ends up here. "" and "help" print the core list, then each module adds
  its own help line.
]]

local ADDON_NAME, ns = ...
ns = ns or {}
local G, S, T = ns.G, ns.Spells, ns.T

local C = ns.commands
local HELP = {}

local function Add(names, help, fn)
	for _, name in ipairs(names) do
		C[name] = fn
	end
	if help then
		HELP[#HELP + 1] = help
	end
end

local function Toggle(key, label)
	return function()
		local db = ns.DB()
		db[key] = not db[key]
		ns.Print("%s %s", label, ns.OnOff(db[key]))
		ns.ApplyAll()
	end
end

-- Numeric setter: /bulwark width 500
local function Number(key, label, lo, hi)
	return function(arg)
		local n = tonumber(arg)
		if not n then
			ns.Print(T("usage: /bulwark %s <%s-%s>"), label, tostring(lo), tostring(hi))
			return
		end
		local db = ns.DB()
		db[key] = G.Clamp(n, lo, hi)
		ns.Print("%s = %s", label, tostring(db[key]))
		ns.ApplyAll()
	end
end

Add({ "help" }, nil, function()
	ns.PrintHelp()
end)
Add({ "lock" }, "lock | unlock (move)", function()
	_G.Bulwark.SetLocked(true)
	ns.Print(T("frames locked."))
end)
Add({ "unlock", "move" }, nil, function()
	_G.Bulwark.SetLocked(false)
	ns.Print(T("frames unlocked: drag to move, /bulwark lock when done."))
end)
Add({ "options", "config" }, "options", function()
	ns.Options.Toggle()
end)
Add({ "prep" }, "prep | mitig", function()
	ns.Prep.Toggle()
end)
Add({ "mitig" }, nil, function()
	ns.Mitigation.Toggle()
end)
Add({ "test" }, "test | reset", function()
	ns.Movers.StartTest()
end)
Add({ "swingdebug" }, nil, function()
	ns.Swing.DebugPrint()
end)
Add({ "reset" }, nil, function()
	ns.Movers.Reset()
	ns.Print(T("positions and sizes reset."))
end)
Add({ "combat" }, "combat | warnings | timers | names", function()
	local db = ns.DB()
	local v = not db.barOnlyInCombat
	db.barOnlyInCombat, db.abilitiesOnlyInCombat, db.warningsOnlyInCombat, db.swingOnlyInCombat = v, v, v, v
	ns.Print("%s %s", T("everything only in combat:"), ns.OnOff(v))
	ns.ApplyAll()
end)
Add({ "warnings" }, nil, function()
	local db = ns.DB()
	local v = not (db.warnRighteousFury or db.warnSeal or db.warnDevotion or db.warnForbearance)
	db.warnRighteousFury, db.warnSeal, db.warnDevotion, db.warnForbearance = v, v, v, v
	ns.Print("%s %s", T("reminders:"), ns.OnOff(v))
	ns.ApplyAll()
end)
Add({ "timers" }, nil, Toggle("showTimers", T("seconds under icons:")))
Add({ "names" }, nil, Toggle("showNames", T("spell names under icons:")))
Add({ "swing" }, "swing | swinglog", Toggle("showSwing", T("swing timer:")))
Add({ "swinglog" }, nil, function()
	local db = ns.DB()
	db.swingCombatLog = not db.swingCombatLog
	ns.Print("%s %s", T("swing timer combat log source:"), ns.OnOff(db.swingCombatLog))
	if db.swingCombatLog and ns.Swing.combatLogAvailable == false then
		ns.Print(T("the combat log is not available on this client."))
	end
end)
Add({ "width" }, "width 200-800 | thick 2-24 | scale 0.6-2", Number("width", "width", 200, 800))
Add({ "thick" }, nil, Number("lineHeight", "thick", 2, 24))
Add({ "scale" }, nil, Number("scale", "scale", 0.6, 2))
Add({ "readysize" }, "readysize 12-64", Number("readyIconSize", "readysize", 12, 64))
Add({ "spellcheck" }, "spellcheck | debug", function()
	ns.Reminders.SpellCheck()
end)
Add({ "debug" }, nil, function()
	ns.DebugDump()
end)

function ns.PrintHelp()
	ns.Print("%s %s · |cff7fd4ff%s|r - %s", ns.VERSION, T("by addicted"), ns.WEBSITE, T("commands:"))
	for _, line in ipairs(HELP) do
		print("  |cffaaaaaa/bulwark|r " .. line)
	end
end

function ns.DebugDump()
	local A = ns.Auras
	local now = G.Now()
	ns.Print(T("debug: spec %s, auras readable: %s, swing %s"),
		tostring(S.spec or "?"), tostring(A.complete), tostring(ns.Swing.state.speed or "?"))
	for _, key in ipairs(S.LINE) do
		local e = A.entries[key]
		local status = A.Status(key)
		if e or status ~= "absent" then
			print(string.format("  %s: %s%s", key, status,
				e and string.format(", %.1fs left (%s)", e.expires - now, e.source or "?") or ""))
		end
	end
	for key, st in pairs(ns.Abilities.entries) do
		if st.confStart or st.castStart then
			print(string.format("  cd %s: conf %s, cast %s", key, tostring(st.confDur), tostring(st.castDur)))
		end
	end
	for key, rank in pairs(S.ranks) do
		if rank > 0 then
			print(string.format("  talent %s: %d", key, rank))
		end
	end
end

function ns.HandleSlash(msg)
	local cmd, rest = string.lower(msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd or ""
	if cmd == "" then
		ns.PrintHelp()
		return
	end
	local fn = C[cmd]
	if fn then
		fn(rest)
	else
		ns.Print(T("unknown command \"%s\". Type /bulwark for the list."), cmd)
	end
end
