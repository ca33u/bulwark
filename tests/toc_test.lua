-- Run: lua tests/toc_test.lua  (from the repo root)
-- Loads every file of Bulwark.toc in order on stubs, boots the addon with a
-- 1.x BulwarkDB and drives it through events, slash commands and the UI.
dofile("tests/wow_stubs.lua")

local function Printed(pattern)
	for _, line in ipairs(WOW.printed) do
		if line:find(pattern, 1, true) then
			return true
		end
	end
	return false
end

------------------------------------------------------------------------
-- TOC
------------------------------------------------------------------------

local files = TocFiles()
local okFiles = true
for _, path in ipairs(files) do
	local f = io.open(path, "r")
	if not f then
		okFiles = false
		io.write("missing: ", path, "\n")
	else
		f:close()
	end
end
Check(okFiles, "every TOC file exists (" .. #files .. ")")
local function IndexOf(name)
	for i, p in ipairs(files) do
		if p == name then
			return i
		end
	end
end
Check(IndexOf("Locales/enUS.lua") < IndexOf("Core/Init.lua"), "locales load before the core")
Check(IndexOf("Core/Boot.lua") < IndexOf("Aggro.lua"), "core loads before the modules")
local modulesInOrder = IndexOf("Aggro.lua") < IndexOf("Ranks.lua") and IndexOf("Ranks.lua") < IndexOf("Plates.lua")
	and IndexOf("Plates.lua") < IndexOf("Blessings.lua") and IndexOf("Blessings.lua") < IndexOf("PartyMana.lua")
Check(modulesInOrder and files[#files] == "PartyMana.lua", "modules in contract order")
for _, path in ipairs(files) do
	if path:match("^Core/") then
		local n = 0
		for _ in io.lines(path) do
			n = n + 1
		end
		Check(n < 1500, path .. " under 1500 lines (" .. n .. ")")
	end
end

-- Contract before the modules load.
SlashCmdList = nil
local ns = LoadAddon("Core/Boot.lua")
Check(type(ns.T) == "function" and ns.T("x") == "x", "ns.T falls back to English")
Check(type(SlashCmdList.BULWARK) == "function", "SlashCmdList.BULWARK defined by the core")
Check(SLASH_BULWARK1 == "/bulwark" and SLASH_BULWARK2 == "/bul", "slash aliases")
Check(type(Bulwark) == "table" and type(Bulwark.SetLocked) == "function", "global Bulwark.SetLocked")
Check(type(Bulwark_OnAddonCompartmentClick) == "function", "addon compartment function")

------------------------------------------------------------------------
-- Boot with a 1.x database
------------------------------------------------------------------------

WOW.frames = {}
WOW.printed = {}
WOW.spells = {
	[25780] = { "Righteous Fury" },
	[20154] = { "Seal of Righteousness" },
	[1311656] = { "Seal of Fury" },
	[465] = { "Devotion Aura" },
	[26573] = { "Consecration" },
	[20271] = { "Judgement" },
	[1400001] = { "Holy Strike" },
	[25771] = { "Forbearance" },
	[642] = { "Divine Shield" },
}
WOW.book = { 25780, 20154, 465, 26573, 20271, 1400001, 642, { id = 1311656, future = true } }
WOW.known = { [25780] = true, [20154] = true, [465] = true, [26573] = true, [20271] = true, [642] = true }
WOW.talents = {
	{ { "Purifying Power", 0 } },
	{ { "Sacred Duty", 2 }, { "Shieldsworn", 1 }, { "Improved Hammer of Justice", 3 } },
	{ { "Improved Judgement", 2 } },
}

local db = {
	x = 0, y = -160, width = 450, locked = true, barStyle = "classic",
	aggro = { enabled = true }, someFutureKey = 1,
}
SlashCmdList = { BULWARK = function() end }
ns = BootAddon(db)
Check(BulwarkDB == db and db.schema == 2, "ADDON_LOADED migrates BulwarkDB in place")
Check(db.someFutureKey == 1 and db.aggro.enabled == true, "unknown and module keys kept")
Check(type(db.blessings) == "table" and type(db.plates) == "table", "modules created their tables")
Check(ns.Spells.spec == "PROTECTION", "spec read from talent points")
Check(ns.Spells.ranks.sacred_duty == 2 and ns.Spells.ranks.improved_judgement == 2, "talent ranks read")
Check(db.learnedIDs.holy_strike and db.learnedIDs.holy_strike[1] == 1400001, "Forever spell ID learned from the spellbook")
Check(ns.Spells.IsKnown("seal_fury") ~= true, "future spells in the book do not count as known")
Check(ns.Spells.IsKnown("judgement") == true and ns.Spells.IsKnown("lay_on_hands") == false, "known by ID / not known")

-- Events that do not exist were registered through pcall.
Check(ns.registered.PLAYER_SWING == false, "missing event registered through pcall")

------------------------------------------------------------------------
-- Reminders from live reads
------------------------------------------------------------------------

RunUpdates(1)
local ids = {}
for _, r in ipairs(ns.Reminders.active) do
	ids[r.id] = true
end
Check(ids.rf and ids.seal and ids.aura, "nothing on you: RF, seal and no-aura reminders")
Check(not ns.Reminders.rfBadge:IsShown(), "RF icon off by default (the red text says it)")
Check(ns.Abilities.NeedsSeal("judgement") == true, "no seal: Judgement dimmed")
Check(ns.Abilities.NeedsSeal("consecration") == false, "no seal: other abilities stay bright")
ns.DB().rfBadge = true
RunUpdates(0.2)
Check(ns.Reminders.rfBadge:IsShown(), "RF icon when turned on")
ns.DB().rfBadge = false

WOW.aurasHidden = true
RunUpdates(1)
Check(#ns.Reminders.active == 3, "auras turn secret (combat): what was missing before stays reminded")
ns.Auras.known = {}
RunUpdates(1)
Check(#ns.Reminders.active == 0, "hidden auras and nothing seen before: no reminders")
WOW.aurasHidden = false

-- One unrelated aura is unreadable and the general flag is set, but these
-- spells are readable: the reminders must still show.
WOW.oneSecretAura = true
RunUpdates(1)
ids = {}
for _, r in ipairs(ns.Reminders.active) do
	ids[r.id] = true
end
Check(ids.rf and ids.seal and ids.aura, "one secret aura elsewhere: RF, seal and aura reminders still show")
WOW.oneSecretAura = false

WOW.auras.HELPFUL = {
	{ name = "Righteous Fury", spellId = 25780, duration = 1800, expirationTime = WOW.time + 1700 },
	{ name = "Seal of Righteousness", spellId = 20154, duration = 30, expirationTime = WOW.time + 20 },
	{ name = "Devotion Aura", spellId = 465, duration = 0, expirationTime = 0 },
	{ name = "Iron Creed", spellId = 1500001, duration = 6, expirationTime = WOW.time + 6 },
}
RunUpdates(0.5)
Check(#ns.Reminders.active == 0, "everything up: no reminders")
Check(ns.Abilities.NeedsSeal("judgement") == false, "seal on: Judgement bright again")
Check(ns.Auras.entries.seal_righteousness ~= nil, "seal rides the line")
Check(db.learnedIDs.iron_creed and db.learnedIDs.iron_creed[1] == 1500001, "Forever buff ID learned from its aura")
Check(ns.Auras.entries.righteous_fury ~= nil, "RF entry tracked")

-- Seal ran out by itself.
WOW.auras.HELPFUL[2].expirationTime = WOW.time + 0.2
RunUpdates(0.6)
table.remove(WOW.auras.HELPFUL, 2)
RunUpdates(0.6)
local text
for _, r in ipairs(ns.Reminders.active) do
	if r.id == "seal" then
		text = r.text
	end
end
Check(text == "Seal timer expired", "seal ran out: 'Seal timer expired' (" .. tostring(text) .. ")")

-- Seal of Fury drops in combat: sound.
WOW.known[1311656] = true
WOW.combat = true
WOW.auras.HELPFUL[#WOW.auras.HELPFUL + 1] = { name = "Seal of Fury", spellId = 1311656, duration = 30, expirationTime = WOW.time + 30 }
RunUpdates(0.5)
table.remove(WOW.auras.HELPFUL)
RunUpdates(0.5)
Check(#WOW.sounds == 1, "sound when Seal of Fury drops in combat")
WOW.combat = false

-- Forbearance badge and locked immunities.
WOW.auras.HARMFUL = { { name = "Forbearance", spellId = 25771, duration = 60, expirationTime = WOW.time + 60 } }
RunUpdates(0.5)
Check(ns.Reminders.forbBadge:IsShown(), "Forbearance badge")
Check(ns.Abilities.LockedByForbearance("divine_shield") and not ns.Abilities.LockedByForbearance("judgement"), "immunities locked")
WOW.auras.HARMFUL = {}

------------------------------------------------------------------------
-- Casts and cooldowns
------------------------------------------------------------------------

WOW.cooldowns[26573] = "SECRET"
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 26573)
RunUpdates(0.2)
Check(ns.Auras.entries.consecration ~= nil, "Consecration starts on cast")
local e = ns.Abilities.entries.consecration
Check(e and e.castDur == 8, "local cooldown timer from the cast")
WOW.cooldowns[642] = "SECRET"
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 642)
Check(ns.Abilities.entries.divine_shield.castDur == 240, "Sacred Duty applied to the local Divine Shield timer")
FireEvent("UNIT_SPELLCAST_SUCCEEDED", SECRET, "cast-3", 26573)
Check(true, "secret unit in a cast event is ignored")

------------------------------------------------------------------------
-- Swing timer
------------------------------------------------------------------------

local SW = ns.Swing
SW.ReadSpeed()
Check(SW.state.speed == 2.6, "weapon speed read out of combat")
WOW.combat = true
WOW.secretGUID = true
SW.ReadSpeed()
Check(SW.state.speed == 2.6, "in combat the cached speed is kept")
CombatLogGetCurrentEventInfo = function()
	return 0, "SWING_DAMAGE", false, "Player-1", "", 0, 0, "Mob"
end
FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
Check(SW.state.finish and math.abs(SW.state.finish - WOW.time - 2.6) < 1e-6, "combat log swing starts the rail")
RunUpdates(0.5)
local before = SW.state.finish - WOW.time
FireEvent("UNIT_COMBAT", "player", "PARRY")
Check(math.abs(SW.state.finish - WOW.time - (before - 1.04)) < 1e-6, "parry haste from UNIT_COMBAT")
Check(SW.rail:IsShown(), "rail shown while swinging")
FireEvent("PLAYER_LEAVE_COMBAT")
Check(SW.state.finish == nil, "auto attack off stops the rail")

-- A haste buff in combat: a readable speed is picked up on the next swing.
WOW.speedReadableInCombat, WOW.speed = true, 2.0
RunUpdates(3)
FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
Check(SW.state.speed == 2.0 and math.abs(SW.state.finish - WOW.time - 2.0) < 1e-6, "in-combat readable speed is used")
WOW.speedReadableInCombat, WOW.speed = false, nil
FireEvent("PLAYER_LEAVE_COMBAT")
WOW.combat = false
WOW.secretGUID = false

-- PLAYER_SWING is a signal: any payload (true, secret, nothing) is a swing.
SW.ReadSpeed()
for _, payload in ipairs({ true, SECRET, false }) do
	RunUpdates(3)
	local before = SW.debug.playerSwing
	ns.Fire("PLAYER_SWING", payload)
	Check(SW.debug.playerSwing == before + 1 and SW.state.finish and math.abs(SW.state.finish - WOW.time - 2.6) < 1e-6,
		"PLAYER_SWING with payload " .. tostring(payload) .. " starts a swing")
end
FireEvent("PLAYER_LEAVE_COMBAT")
WOW.printed = {}
SlashCmdList.BULWARK("swingdebug")
Check(Printed("PLAYER_SWING event") and Printed("speed 2.6"), "/bulwark swingdebug prints the sources")

------------------------------------------------------------------------
-- Slash commands through the module chain
------------------------------------------------------------------------

WOW.printed = {}
SlashCmdList.BULWARK("")
Check(Printed("lock | unlock") and Printed("aggro | aggrocombat") and Printed("lowmana"), "help: core and module lines")
SlashCmdList.BULWARK("width 500")
Check(db.width == 500, "/bulwark width")
SlashCmdList.BULWARK("width 5000")
Check(db.width == 800, "/bulwark width clamps")
SlashCmdList.BULWARK("thick 6")
SlashCmdList.BULWARK("scale 1.5")
Check(db.lineHeight == 6 and db.scale == 1.5, "/bulwark thick and scale")
SlashCmdList.BULWARK("swingheight 8")
SlashCmdList.BULWARK("swinggap 10")
Check(db.swingHeight == 8 and db.swingGap == 10, "swing sizes")
SlashCmdList.BULWARK("readysize 40")
SlashCmdList.BULWARK("readyx 12")
SlashCmdList.BULWARK("readyy 80")
SlashCmdList.BULWARK("readygap 6")
Check(db.readyIconSize == 40 and db.readyOffX == 12 and db.readyOffY == 80 and db.readySpacing == 6, "ready group commands")
SlashCmdList.BULWARK("combat")
Check(db.barOnlyInCombat and db.abilitiesOnlyInCombat and db.warningsOnlyInCombat and db.swingOnlyInCombat, "/bulwark combat")
SlashCmdList.BULWARK("combat")
SlashCmdList.BULWARK("warnings")
Check(not db.warnSeal and not db.warnRighteousFury, "/bulwark warnings off")
SlashCmdList.BULWARK("warnings")
Check(db.warnSeal and db.warnDevotion, "/bulwark warnings on")
SlashCmdList.BULWARK("swinglog")
Check(db.swingCombatLog == false, "/bulwark swinglog")
SlashCmdList.BULWARK("timers")
SlashCmdList.BULWARK("names")
SlashCmdList.BULWARK("swing")
Check(db.showTimers == false and db.showNames == true and db.showSwing == false, "toggles")
SlashCmdList.BULWARK("aggro")
Check(db.aggro.enabled == false, "module command still reaches Aggro")
WOW.printed = {}
SlashCmdList.BULWARK("nonsense")
Check(Printed("unknown command"), "unknown command message")

-- Lock / unlock: the hook the modules use fires.
local hooked
hooksecurefunc(Bulwark, "SetLocked", function(locked)
	hooked = locked
end)
SlashCmdList.BULWARK("unlock")
Check(db.locked == false and hooked == false and ns.Movers.unlocked, "/bulwark unlock")
RunUpdates(0.3)
Check(ns.Abilities.frame:IsShown() and ns.Reminders.frame:IsShown(), "unlocked: previews shown")
SlashCmdList.BULWARK("move")
SlashCmdList.BULWARK("lock")
Check(db.locked == true and hooked == true and not ns.Movers.unlocked, "/bulwark lock")

SlashCmdList.BULWARK("swing")
SlashCmdList.BULWARK("test")
RunUpdates(1)
Check(ns.Movers.testing and ns.Swing.rail:IsShown(), "test mode runs the rail")
RunUpdates(12)
Check(not ns.Movers.testing, "test mode ends after 12 s")

db.x, db.width = 99, 777
SlashCmdList.BULWARK("reset")
Check(db.x == 0 and db.y == -140 and db.width == 420, "/bulwark reset")

WOW.printed = {}
SlashCmdList.BULWARK("spellcheck")
Check(Printed("Devotion Aura") and Printed("Righteous Fury") and Printed("Seal of Fury"), "/bulwark spellcheck lists the spells")
WOW.printed = {}
SlashCmdList.BULWARK("debug")
Check(#WOW.printed > 0, "/bulwark debug prints")

------------------------------------------------------------------------
-- Windows
------------------------------------------------------------------------

WOW.group = { party1 = "PRIEST", party2 = "SHAMAN" }
WOW.inventory = {
	[16] = { id = 1, link = "|Hitem:1:0:0|h", equipLoc = "INVTYPE_2HWEAPON" },
	[15] = { id = 2, link = "|Hitem:2:2621:0|h", equipLoc = "INVTYPE_CLOAK" },
}
SlashCmdList.BULWARK("prep")
local rows = ns.Prep.Collect()
local texts = {}
for _, r in ipairs(rows) do
	texts[#texts + 1] = r.state .. ":" .. r.text
end
local all = table.concat(texts, "\n")
Check(all:find("bad:Two-handed", 1, true) ~= nil, "prep: two-handed weapon is red")
Check(all:find("bad:Cloak has Subtlety", 1, true) ~= nil, "prep: Subtlety is red")
Check(all:find("bad:Power Word: Fortitude missing - Priest", 1, true) ~= nil, "prep: priest buff missing")
Check(all:find("good:Tranquil Air not on you", 1, true) ~= nil, "prep: Tranquil Air missing is right")
Check(all:find("Arcane Intellect", 1, true) == nil, "prep: no rows for classes not in the group")
Check(all:find("bad:No shield", 1, true) ~= nil, "prep: no shield")
Check(all:find("good:Defense 300", 1, true) ~= nil, "prep: defense skill")
WOW.stats.defense = { SECRET, SECRET }
rows = ns.Prep.Collect()
local hidden = false
for _, r in ipairs(rows) do
	hidden = hidden or (r.state == "warn" and r.text:find("hidden while stats", 1, true) ~= nil)
end
Check(hidden, "prep: hidden defense is yellow")
Check(ns.Prep.EnchantOf("|Hitem:5:1888:0|h") == 1888 and ns.Prep.EnchantOf("|Hitem:5::0|h") == 0, "enchant parsing")

SlashCmdList.BULWARK("mitig")
Check(db.showMitigation and ns.Mitigation.frame:IsShown(), "/bulwark mitig shows the window")
RunUpdates(0.6)
SlashCmdList.BULWARK("mitig")
Check(not db.showMitigation, "/bulwark mitig hides it")

SlashCmdList.BULWARK("options")
Check(ns.Options.frame:IsShown(), "/bulwark options")
for _, tab in ipairs({ "general", "bar", "abilities", "warnings", "swing", "windows" }) do
	ns.Options.Show(tab)
	Check(ns.Options.current == tab, "tab opens: " .. tab)
end
ns.Options.Show("about")
Check(ns.Options.current == "general", "old tab name 'about' opens General")
ns.Options.Show("mitigation")
Check(ns.Options.current == "windows", "old tab name 'mitigation' opens Windows")
ns.Options.Toggle()
Bulwark_OnAddonCompartmentClick()
Check(ns.Options.frame:IsShown(), "compartment opens options")

-- Minimap button
Check(ns.Minimap.button ~= nil and ns.Minimap.button:IsShown(), "minimap button placed")
local x, y = ns.Minimap.Point(0, 100, 100, 140)
Check(math.abs(x - 180) < 1e-6 and math.abs(y - 100) < 1e-6, "minimap ring position")
Check(math.abs(ns.Minimap.Angle(100, 200, 100, 100) - 90) < 1e-6, "minimap angle")
db.showMinimap = false
ns.ApplyAll()
Check(not ns.Minimap.button:IsShown(), "minimap button can be hidden")

-- Blocked action report
WOW.printed = {}
FireEvent("ADDON_ACTION_BLOCKED", "Bulwark", "CastSpellByName()")
FireEvent("ADDON_ACTION_FORBIDDEN", "OtherAddon", "Foo()")
Check(#WOW.printed == 1 and Printed("blocked call: CastSpellByName() (ADDON_ACTION_BLOCKED)"), "blocked call reported once, only for Bulwark")

-- Non-paladins: the paladin parts stay hidden.
WOW.class = "WARRIOR"
RunUpdates(0.5)
Check(not ns.Line.bar:IsShown() and not ns.Reminders.frame:IsShown(), "warrior: line and reminders hidden")
WOW.class = nil

-- Everything keeps running for a while without errors.
local ok, err = pcall(RunUpdates, 3, 0.03)
Check(ok, "update loop runs " .. tostring(err or ""))

------------------------------------------------------------------------
-- Locales
------------------------------------------------------------------------

for _, code in ipairs({ "ruRU", "deDE", "frFR", "esES", "esMX", "ptBR", "koKR", "zhTW" }) do
	WOW.locale = code
	local lns = LoadAddon("Core/Init.lua")
	Check(lns.T("Seal missing") ~= "Seal missing" and lns.T("Righteous Fury missing") ~= "Righteous Fury missing",
		code .. " translates the reminders")
	Check(lns.T("no such string") == "no such string", code .. " falls back to English")
end
WOW.locale = nil

-- Rounded track and glow (pills)
do
	local pill = ns.Line.pills.bg
	Check(pill.canRound, "pill ends have round masks")
	ns.DB().barStyle = "classic"
	ns.DB().showBackground = true
	ns.ApplyAll()
	Check(pill.mid:IsShown() and pill.left:IsShown() and pill.right:IsShown(), "classic style: track has round ends")
	local h = ns.Line.frame:GetHeight() + 4
	Check(math.abs(pill.left:GetWidth() - h / 2) < 1e-6, "round end is half the track height wide")
	ns.DB().barStyle = "minimal"
	ns.ApplyAll()
	Check(pill.mid:IsShown() and not pill.left:IsShown() and not pill.right:IsShown(), "flat style: plain rectangle")
	ns.DB().showBackground = false
	ns.ApplyAll()
	Check(not pill.mid:IsShown(), "background off hides the track")
	ns.DB().barStyle, ns.DB().showBackground = "classic", true
	ns.ApplyAll()
end

Report("toc_test")
