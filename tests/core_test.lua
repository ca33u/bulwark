-- Run: lua tests/core_test.lua  (from the repo root)
-- Pure logic of the core: guards, swing math, cooldowns with talents,
-- mitigation formulas, reminder decisions, line trackers, migration.
dofile("tests/wow_stubs.lua")

local ns = LoadAddon()
local G = ns.G

local function Near(a, b, eps)
	return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (eps or 1e-6)
end

------------------------------------------------------------------------
-- Guards
------------------------------------------------------------------------

Check(G.IsSecret(SECRET) and not G.IsSecret(5), "IsSecret")
Check(G.Num(SECRET) == nil and G.Num("5") == nil and G.Num(5) == 5, "Num rejects secrets and strings")
Check(G.Num(0 / 0) == nil, "Num rejects NaN")
Check(G.Str(SECRET) == nil and G.Str("a") == "a", "Str")
Check(G.Flag(SECRET) == nil and G.Flag(nil) == false and G.Flag(1) == true, "Flag: secret is nil, not false")
Check(G.Read(function()
	error("blocked")
end) == nil, "Read survives errors")
Check(G.Read(function()
	return SECRET
end) == nil, "Read drops a secret result")
Check(G.Read(nil) == nil, "Read of a missing function")
local all = G.ReadAll(function()
	return 1, SECRET, 3
end)
Check(all and all[1] == 1 and all[2] == nil and all[3] == 3 and all.hidden, "ReadAll replaces secrets and flags hidden")
Check(G.Field({ a = SECRET }, "a") == nil and G.Field(SECRET, "a") == nil and G.Field({ a = 2 }, "a") == 2, "Field")
local erroring = setmetatable({}, { __index = function()
	error("forbidden read")
end })
Check(G.Field(erroring, "x") == nil, "Field survives an erroring table")
Check(G.Norm("  Templar\226\128\153s  Bulwark ") == "templar's bulwark", "Norm: trim, lower, curly apostrophe")
Check(G.Norm(SECRET) == nil and G.Norm("") == nil, "Norm of secret or empty")
Check(G.Clamp(5, 0, 3) == 3 and G.Clamp(-1, 0, 3) == 0 and G.Clamp("x", 0, 3) == 0, "Clamp")

-- Forbidden frames: only IsForbidden is called, nothing else is read.
local touched = false
local forbidden = setmetatable({ IsForbidden = function()
	return true
end }, { __index = function()
	touched = true
	error("read")
end })
Check(G.IsForbidden(forbidden) and not touched, "IsForbidden detects without reading fields")
Check(not G.IsForbidden({ IsForbidden = function()
	return false
end }), "normal frame")
Check(G.IsForbidden({ IsForbidden = function()
	error("x")
end }), "IsForbidden that errors counts as forbidden")
Check(G.IsForbidden(nil), "nil counts as forbidden")

-- C_Secrets: a failed or secret answer counts as hidden.
C_Secrets = { ShouldAurasBeSecret = function()
	return SECRET
end, ShouldCooldownsBeSecret = function()
	error("x")
end }
Check(G.AurasSecret() == true, "secret answer from C_Secrets = secret")
Check(G.CooldownsSecret() == true, "failed C_Secrets call = secret")
C_Secrets = { GetSpellAuraSecrecy = function(id)
	return id == 1 and Enum.SecrecyLevel.AlwaysSecret or Enum.SecrecyLevel.NeverSecret
end }
Check(G.SpellAuraSecret(1) == true and G.SpellAuraSecret(2) == false, "GetSpellAuraSecrecy levels")
C_Secrets = nil
Check(G.AurasSecret() == false, "no C_Secrets = readable")

-- Visibility options
local db = { barOnlyInCombat = true, barHideMounted = true }
Check(not G.ShouldShow(db, "bar", "barOnlyInCombat", { combat = false }), "only in combat hides out of combat")
Check(G.ShouldShow(db, "bar", "barOnlyInCombat", { combat = true }), "shown in combat")
Check(not G.ShouldShow(db, "bar", "barOnlyInCombat", { combat = true, mounted = true }), "hidden when mounted")

------------------------------------------------------------------------
-- Swing math
------------------------------------------------------------------------

local SW = ns.Swing
local st = SW.New()
Check(SW.Begin(st, 10, 2.5), "swing starts")
Check(Near(SW.Remaining(st, 11), 1.5), "remaining after 1 s")
Check(Near(SW.Fraction(st, 11), 0.4), "fill 40 %")
Check(not SW.Begin(st, 10.2, 2.5), "duplicate report of the same swing ignored")
-- Parry haste: 2.0 s left of 2.5 -> minus 1.0 (40 %) = 1.0 s
SW.Begin(st, 20, 2.5)
Check(SW.Parry(st, 20.5) and Near(SW.Remaining(st, 20.5), 1.0), "parry: minus 40 % of weapon speed")
-- 0.8 s left -> floor is 0.5 (20 % of 2.5)
SW.Begin(st, 30, 2.5)
SW.Parry(st, 31.7)
Check(Near(SW.Remaining(st, 31.7), 0.5), "parry: never below 20 % of the weapon speed")
-- 0.4 s left: already under the floor, unchanged
SW.Begin(st, 40, 2.5)
SW.Parry(st, 42.1)
Check(Near(SW.Remaining(st, 42.1), 0.4), "parry: no change under the floor")
Check(Near(SW.ParryHaste(2.0, 2.5), 1.0) and Near(SW.ParryHaste(0.6, 2.5), 0.5), "ParryHaste pure")
SW.Stop(st)
Check(not SW.Parry(st, 50), "no parry haste without a running swing")
Check(SW.Idle(st, 50), "stopped = idle")
SW.Begin(st, 60, 2)
SW.Restart(st, 61, 3)
Check(Near(SW.Remaining(st, 61), 3), "weapon change restarts the swing with the new speed")
Check(SW.Idle(st, 61 + 3 + 4.6) and not SW.Idle(st, 62), "idle after 1.5 swings without a hit")

-- Combat log rows
local me = "Player-1"
Check(SW.FromCombatLog({ 0, "SWING_DAMAGE", false, me, "", 0, 0, "Mob" }, me) == "swing", "own SWING_DAMAGE = swing")
local offhand = { 0, "SWING_DAMAGE", false, me, "", 0, 0, "Mob" }
offhand[21] = true
Check(SW.FromCombatLog(offhand, me) == nil, "off-hand swing ignored")
Check(SW.FromCombatLog({ 0, "SWING_MISSED", false, me, "", 0, 0, "Mob", "", 0, 0, "DODGE", false }, me) == "swing", "own miss = swing")
Check(SW.FromCombatLog({ 0, "SWING_MISSED", false, "Mob", "", 0, 0, me, "", 0, 0, "PARRY" }, me) == "parry", "parried melee = parry")
Check(SW.FromCombatLog({ 0, "SPELL_MISSED", false, "Mob", "", 0, 0, me, "", 0, 0, 1, "Strike", 1, "PARRY" }, me) == "parry", "parried special = parry")
Check(SW.FromCombatLog({ 0, SECRET, false, me }, me) == nil, "secret sub-event ignored")
Check(SW.FromCombatLog({ 0, "SWING_DAMAGE", false, SECRET }, me) == nil, "secret source ignored")

------------------------------------------------------------------------
-- Cooldowns with talents
------------------------------------------------------------------------

local AB = ns.Abilities
Check(AB.BaseCooldown("judgement", {}) == 10, "Judgement 10 s")
Check(AB.BaseCooldown("judgement", { improved_judgement = 2 }) == 8, "Improved Judgement 2/2: 8 s")
Check(AB.BaseCooldown("holy_strike", { shieldsworn = 1 }) == 6, "Shieldsworn: Holy Strike 6 s")
Check(AB.BaseCooldown("divine_shield", { sacred_duty = 2 }) == 240, "Sacred Duty 2/2: Divine Shield 240 s")
Check(AB.BaseCooldown("divine_protection", { sacred_duty = 1 }) == 270, "Sacred Duty 1/2: Divine Protection 270 s")
Check(AB.BaseCooldown("templar_bulwark", { sacred_duty = 2 }) == 240, "Sacred Duty: Templar's Bulwark")
Check(AB.BaseCooldown("bop", { guardians_favor = 2 }) == 180, "Guardian's Favor 2/2: BoP 180 s")
Check(AB.BaseCooldown("hammer_of_justice", { improved_hoj = 3 }) == 45, "Improved HoJ 3/3: 45 s")
Check(Near(AB.BaseCooldown("exorcism", { purifying_power = 1 }), 15 * 0.83), "Purifying Power 1/2: Exorcism -17 %")
Check(Near(AB.BaseCooldown("holy_wrath", { purifying_power = 2 }), 60 * 0.67), "Purifying Power 2/2: Holy Wrath -33 %")
Check(AB.BaseCooldown("lay_on_hands", nil) == 3600, "no ranks known = base")
Check(AB.BaseCooldown("righteous_fury", {}) == nil, "no cooldown for a buff")
Check(ns.Auras.BaseDuration("freedom", { guardians_favor = 2 }) == 16, "Guardian's Favor: Freedom +3 s per rank")

-- Resolve: readable API is the truth, hidden keeps the last confirmed value.
local e = {}
local rem = AB.Resolve(e, { status = "ok", start = 100, duration = 10 }, 104)
Check(Near(rem, 6) and e.confStart == 100, "readable cooldown")
rem = AB.Resolve(e, { status = "hidden" }, 106)
Check(Near(rem, 4), "hidden: last confirmed value keeps counting")
e.castStart, e.castDur = 107, 8
rem = AB.Resolve(e, { status = "hidden" }, 108)
Check(Near(rem, 7), "hidden: a newer own cast wins")
rem = AB.Resolve(e, { status = "ok", start = 108, duration = 1.5 }, 108.5)
Check(rem == 0 and e.castStart == nil, "global cooldown only = ready, local timer cleared")
rem = AB.Resolve({}, { status = "hidden" }, 200)
Check(rem == 0, "hidden with nothing known = ready")

------------------------------------------------------------------------
-- Mitigation
------------------------------------------------------------------------

local M = ns.Mitigation
Check(Near(M.ArmorDR(10000, 63), 10000 / (10000 + 400 + 85 * 63)), "armor DR formula")
Check(M.ArmorDR(1e7, 63) == 0.75, "armor DR capped at 75 %")
Check(Near(M.EHP(5000, 0.5), 10000), "EHP = HP / (1 - DR)")
local o = M.Compute({ level = 60, levelDiff = 3, defense = 440, dodge = 15, parry = 15, block = 30, armor = 10000, hp = 8000 })
Check(o.attackerLevel == 63, "raid boss is level 63")
Check(Near(o.miss, 5 + 140 * 0.04 - 0.6), "miss: 5 % + 0.04 % per defense over 300, -0.6 % vs +3")
Check(Near(o.dodge, 14.4) and Near(o.parry, 14.4) and Near(o.block, 29.4), "dodge/parry/block -0.2 % per level")
Check(Near(o.crit, 0) and o.critCap == 440, "440 defense = crit immune vs 63")
Check(o.crush == 0 or o.crush == 15, "crush is 0 or 15")
local total = o.avoid + o.block
Check((total < 100 and o.crush == 15) or (total >= 100 and o.crush == 0), "crush pushed off at 100 % after the level penalty")
o = M.Compute({ level = 60, levelDiff = 3, defense = 400, dodge = 20, parry = 20, block = 55 })
Check(o.crush == 0 and o.crushGap == 0, "102.4 % on the sheet pushes crushing blows off")
o = M.Compute({ level = 60, levelDiff = 3, defense = 300, dodge = 5, parry = 5, block = 5 })
Check(o.crush == 15 and o.crushGap > 0, "low avoidance: 15 % crush with a gap")
Check(Near(o.crit, 5 + 15 * 0.04), "crit chance vs +3 with 300 defense")
o = M.Compute({ level = 60, levelDiff = 0, dodge = 5 })
Check(o.crush == 0 and o.miss == nil and o.avoid == nil, "hidden defense: miss/avoid unknown, no crush vs same level")
local f = M.Format(M.Compute({ level = 60, levelDiff = 3 }))
Check(f.dodge == "-" and f.armor == "-", "hidden values are shown as -")

------------------------------------------------------------------------
-- Reminder decisions
------------------------------------------------------------------------

local R = ns.Reminders
local function Ids(list)
	local out = {}
	for _, item in ipairs(list) do
		out[#out + 1] = item.id
	end
	return table.concat(out, ",")
end
local function Ctx(over)
	local c = {
		spec = "PROTECTION",
		rf = { enabled = true, known = true, status = "present" },
		seal = { enabled = true, known = true, status = "present" },
		dev = { enabled = true, known = true, aura = "devotion" },
		forb = { enabled = true, status = "absent" },
	}
	for k, v in pairs(over or {}) do
		c[k] = v
	end
	return c
end
local list, badges = R.Decide(Ctx())
Check(#list == 0 and not badges.rf and not badges.forbearance, "all good: nothing")
list, badges = R.Decide(Ctx({ rf = { enabled = true, known = true, status = "absent" } }))
Check(Ids(list) == "rf" and badges.rf, "RF known and confirmed absent: reminder and badge")
Check(list[1].texture ~= nil, "RF reminder uses the game's icon")
Check(R.ShowIcons(list, 1) == 1 and R.ShowIcons({}, 1) == 0, "icon tiles laid out and cleared")
list = R.Decide(Ctx({ bless = { enabled = true, known = true, status = "absent" } }))
Check(Ids(list) == "blessing" and list[1].icon == "blessing", "no blessing on yourself: reminder")
list = R.Decide(Ctx({ bless = { enabled = true, known = true, status = "hidden" } }))
Check(#list == 0, "blessing hidden: no reminder")
Check(R.LOOK.blessing.brand == "arcane" and R.LOOK.aura.brand == "tide" and R.LOOK.seal.brand == "ember" and R.LOOK.rf.brand == "gold", "each reminder has its brand colour")
list = R.Decide(Ctx({ rf = { enabled = true, known = true, status = "hidden" } }))
Check(#list == 0, "RF hidden: no reminder")
list = R.Decide(Ctx({ rf = { enabled = true, known = nil, status = "absent" } }))
Check(#list == 0, "RF unknown (not confirmed known): no reminder")
list = R.Decide(Ctx({ rf = { enabled = true, known = false, status = "absent" } }))
Check(#list == 0, "RF not known: no reminder")
list = R.Decide(Ctx({ rf = { enabled = false, known = true, status = "absent" } }))
Check(#list == 0, "RF reminder off")
list = R.Decide(Ctx({ seal = { enabled = true, known = true, status = "absent" } }))
Check(Ids(list) == "seal" and list[1].text == "Seal missing", "seal missing")
list = R.Decide(Ctx({ seal = { enabled = true, known = true, status = "absent", expired = true } }))
Check(list[1].text == "Seal timer expired", "seal timer expired")
list = R.Decide(Ctx({ seal = { enabled = true, known = true, status = "hidden" } }))
Check(#list == 0, "seal hidden: no reminder")
list = R.Decide(Ctx({ spec = "RETRIBUTION", seal = { enabled = true, known = true, status = "absent" } }))
Check(Ids(list) == "seal", "seal reminder in any spec")
list = R.Decide(Ctx({ spec = false, seal = { enabled = true, known = true, status = "absent" } }))
Check(Ids(list) == "seal", "unknown spec (talents unreadable): seal reminder still shows")
list = R.Decide(Ctx({ seal = { enabled = true, known = false, status = "absent" } }))
Check(#list == 0, "no seal learned: no reminder")
list = R.Decide(Ctx({ dev = { enabled = true, known = true, aura = "none" } }))
Check(Ids(list) == "aura" and list[1].text == "No aura active", "no aura at all: reminder")
list = R.Decide(Ctx({ dev = { enabled = true, known = true, aura = "other" } }))
Check(#list == 0, "Retribution or another aura: no reminder")
list = R.Decide(Ctx({ spec = "RETRIBUTION", dev = { enabled = true, known = true, aura = "none" } }))
Check(Ids(list) == "aura", "no aura: reminder in any spec")
list = R.Decide(Ctx({ dev = { enabled = true, known = true, aura = "resist" } }))
Check(#list == 0, "resistance aura counts as fine")
list = R.Decide(Ctx({ dev = { enabled = true, known = true, aura = "hidden" } }))
Check(#list == 0, "aura hidden: no reminder")
list = R.Decide(Ctx({ dev = { enabled = true, known = nil, aura = "none" } }))
Check(#list == 0, "no aura confirmed known: no reminder")
_, badges = R.Decide(Ctx({ forb = { enabled = true, status = "present" } }))
Check(badges.forbearance, "forbearance badge")
_, badges = R.Decide(Ctx({ forb = { enabled = true, status = "hidden" } }))
Check(not badges.forbearance, "forbearance hidden: no badge")

------------------------------------------------------------------------
-- Line trackers
------------------------------------------------------------------------

local A = ns.Auras
local entries, ended = {}, {}
A.ApplyRead(entries, "holy_shield", "present", { expires = 110, duration = 10 }, 100, 10, ended)
Check(entries.holy_shield and entries.holy_shield.expires == 110, "aura read creates the entry")
A.ApplyRead(entries, "holy_shield", "hidden", nil, 105, 10, ended)
Check(entries.holy_shield ~= nil, "hidden read keeps the icon")
A.ApplyRead(entries, "holy_shield", "hidden", nil, 111, 10, ended)
Check(entries.holy_shield == nil and ended.holy_shield.reason == "expired", "hidden: dropped when the timer ran out")
A.ApplyCast(entries, "seal_fury", 200, 30, ended)
A.ApplyCast(entries, "seal_command", 201, 30, ended)
Check(entries.seal_fury == nil and entries.seal_command, "seals are exclusive")
Check(ended.seal_fury.reason == "replaced", "replaced seal is marked replaced")
A.ApplyRead(entries, "seal_command", "absent", nil, 205, 30, ended)
Check(entries.seal_command == nil and ended.seal_command.reason == "removed", "confirmed absent removes")
A.ApplyCast(entries, "consecration", 300, 8, ended)
A.ApplyRead(entries, "consecration", "absent", nil, 301, 8, ended)
Check(entries.consecration ~= nil, "consecration (cast only) ignores aura reads")
A.ApplyRead(entries, "consecration", "absent", nil, 308.1, 8, ended)
Check(entries.consecration == nil, "consecration ends after 8 s")
A.ApplyRead(entries, "divine_shield", "present", { icon = 1 }, 400, 12, ended)
Check(entries.divine_shield and entries.divine_shield.expires == 412, "present with hidden timing: base duration from now")
Check(A.StatusOf(nil, false, nil) == "hidden" and A.StatusOf(nil, true, nil) == "absent" and A.StatusOf({}, false) == "present", "StatusOf")
-- in combat auras turn secret: remember the last readable "absent"
A.status.righteous_fury = "hidden"
A.known.righteous_fury, A.cast.righteous_fury = { status = "absent", at = 100 }, nil
Check(A.Remembered("righteous_fury") == "absent", "RF missing before the pull stays missing in combat")
A.cast.righteous_fury = 150
Check(A.Remembered("righteous_fury") == "hidden", "cast since then: no longer sure, no reminder")
A.known.righteous_fury, A.cast.righteous_fury = { status = "present", at = 100 }, nil
Check(A.Remembered("righteous_fury") == "hidden", "it was on before the pull: no reminder")
A.status.righteous_fury = "absent"
Check(A.Remembered("righteous_fury") == "absent", "readable: the read wins")
A.status.righteous_fury, A.known.righteous_fury = nil, nil
Check(ns.Line.Progress(5, 10) == 0.5 and ns.Line.Progress(20, 10) == 0 and ns.Line.Progress(-1, 10) == 1, "line progress")

------------------------------------------------------------------------
-- Migration from 1.x
------------------------------------------------------------------------

local old = {
	x = 10, y = -200, width = 500, scale = 1.2, iconSize = 26, lineHeight = 8, barStyle = 4,
	showTimers = false, warnSeal = false, readyX = 10, readyY = -150,
	colors = { line = { r = 1, g = 0, b = 0, a = 1 }, glow = { 0, 1, 0 } },
	learnedIDs = { templar_bulwark = 1234567 },
	tracked = { seal_fury = false }, readyCDs = { exorcism = true },
	locked = false, minimapAngle = 90, swingHeight = 99,
	aggro = { enabled = false }, plates = { enabled = true }, blessings = {}, lowMana = { threshold = 25 },
	autoRanks = false, ranksCaughtUp = { ["A-B"] = true }, cvarsReset = true, someFutureKey = "keep",
}
local m = ns.MigrateDB(old)
Check(m.schema == 3, "schema marker")
Check(m.x == 10 and m.y == -200 and m.width == 500 and m.scale == 1.2 and m.iconSize == 26, "positions and sizes kept")
Check(m.barStyle == "luminous", "numeric style 4 -> luminous")
Check(m.showTimers == false and m.warnSeal == false and m.locked == false, "booleans kept")
Check(m.readyOffX == 0 and m.readyOffY == 50, "readyX/readyY screen position -> offset from the line")
Check(m.colors.line[1] == 1 and m.colors.line[2] == 0 and m.colors.glow[4] == 0.35, "colors normalized, missing alpha from default")
Check(m.colors.capEnd and #m.colors.capEnd == 4, "missing colors filled")
Check(type(m.learnedIDs.templar_bulwark) == "table" and m.learnedIDs.templar_bulwark[1] == 1234567, "learned ID kept as a list")
Check(m.tracked.seal_fury == false and m.readyCDs.exorcism == true, "tracked and readyCDs kept")
Check(m.swingHeight == 12, "out of range value clamped")
Check(m.aggro.enabled == false and m.lowMana.threshold == 25 and m.autoRanks == false and m.cvarsReset == true,
	"module keys untouched")
Check(m.ranksCaughtUp["A-B"] and m.someFutureKey == "keep", "unknown keys never wiped")
Check(m.showSwing == true and m.swingParryHaste == true and m.swingCombatLog == true, "new keys get defaults")
local m2 = ns.MigrateDB({ readyOffsetX = 5, readyOffsetY = 70, readyX = 999 })
Check(m2.readyOffX == 5 and m2.readyOffY == 70, "readyOffsetX/Y win over readyX/Y")
local m3 = ns.MigrateDB({ barStyle = "Minimal flat", width = "bad", tracked = { "seal_fury" } })
Check(m3.barStyle == "minimal" and m3.width == 420, "style by name, wrong type falls back to default")
Check(m3.tracked.seal_fury == true and m3.trackedExclusive, "a list of tracked keys means only those")
local again = ns.MigrateDB(ns.MigrateDB({}))
Check(again.schema == 3 and again.width == 420, "migration is idempotent")
local m4 = ns.MigrateDB({ schema = 2, warnOffX = -55, warnOffY = -77, readyOffX = 47, readyOffY = -57, width = 500 })
Check(m4.warnOffX == 0 and m4.warnOffY == 12 and m4.readyOffX == 0 and m4.readyOffY == -40 and m4.width == 500,
	"2.x -> 3: reminders above, abilities below, centred; other settings kept")
Check(ns.NormalizeStyle("Luminous beveled") == "luminous" and ns.NormalizeStyle(nil) == "classic", "style names")

-- Website link: the copy window opens with the address.
Check(ns.WEBSITE == "addicted.sh" and ns.WEBSITE_URL == "https://addicted.sh", "website constants")
local okCopy, errCopy = pcall(ns.W.ShowCopy, ns.WEBSITE_URL)
Check(okCopy, "copy window opens " .. tostring(errCopy or ""))
local okLink, link = pcall(ns.W.Link, UIParent, ns.WEBSITE, ns.WEBSITE_URL)
Check(okLink and link ~= nil, "link button builds")

Report("core_test")
