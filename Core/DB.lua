--[[
  Bulwark core: saved variables (BulwarkDB) and migration from 1.x.

  BulwarkDB is account-wide. Keys the core does not know (module tables
  such as aggro, plates, blessings, lowMana, autoRanks, ranksCaughtUp,
  cvarsReset) are never removed. Known keys are type-checked and clamped;
  a wrong type falls back to the default.
]]

local ADDON_NAME, ns = ...
ns = ns or {}
local G = ns.G

local SCHEMA = 2

local function RGBA(r, g, b, a)
	return { r, g, b, a }
end

ns.STYLES = { "classic", "minimal", "inset", "luminous" }
ns.STYLE_THICKNESS = { classic = 7, minimal = 3, inset = 6, luminous = 8 }

ns.DEFAULTS = {
	-- the line
	x = 0, y = -140, width = 420, lineHeight = 7, scale = 1,
	barStyle = "classic", iconSize = 22,
	showTimers = true, showNames = false, flashSoon = true, expireSoon = 5,
	growRight = true, rfLastOnly = true,
	showGlow = true, glowSize = 4, showCaps = true, showBackground = true,
	colors = {
		line = RGBA(0.96, 0.77, 0.19, 1),
		glow = RGBA(1.00, 0.82, 0.35, 0.35),
		bg = RGBA(0.02, 0.02, 0.03, 0.65),
		capStart = RGBA(0.96, 0.77, 0.19, 1),
		capEnd = RGBA(1.00, 0.22, 0.15, 1),
	},
	barOnlyInCombat = false,
	barHideFlying = true, barHideResting = false, barHideMounted = false, barHideDead = true,
	tracked = {},

	-- ability icons
	readyCDs = {},
	readyIconSize = 32, readySpacing = 4, readyOffX = 0, readyOffY = 50,
	readyAlign = "center", readyGrowRight = true,
	abilitiesOnlyInCombat = false,
	iconsHideFlying = true, iconsHideResting = false, iconsHideMounted = false, iconsHideDead = true,

	-- reminders and badges
	warnRighteousFury = true, warnSeal = true, warnDevotion = true, warnForbearance = true,
	warnBlessing = true,
	rfBadge = false, -- the separate RF icon; the red text already says it
	soundSealDrop = true,
	warnSize = 16, warnOffX = 0, warnOffY = 8, warnAlign = "center",
	warnIcons = true, -- Bulwark's own icons above the line instead of red text
	warnColor = RGBA(1, 0.25, 0.15, 1),
	badgeRFX = -250, badgeRFY = -140, badgeForbX = 250, badgeForbY = -140, badgeSize = 34,
	warningsOnlyInCombat = false,
	warnHideFlying = true, warnHideResting = false, warnHideMounted = false, warnHideDead = true,

	-- swing rail
	showSwing = true, swingHeight = 4, swingGap = 6, swingShowTime = true,
	swingParryHaste = true, swingOnlyInCombat = false, swingCombatLog = true,

	-- windows
	showMitigation = false, mitigX = 330, mitigY = 140, mitigScale = 1, mitigFont = 11, mitigLevelDiff = 3,
	prepX = -330, prepY = 140,

	-- misc
	showMinimap = true, minimapAngle = 220,
	learnedIDs = {},
	locked = true,
}

-- Numeric ranges, applied after migration.
ns.RANGES = {
	width = { 200, 800 }, lineHeight = { 2, 24 }, scale = { 0.6, 2 }, iconSize = { 12, 48 },
	expireSoon = { 0, 30 }, glowSize = { 0, 24 },
	readyIconSize = { 12, 64 }, readySpacing = { 0, 24 },
	readyOffX = { -2000, 2000 }, readyOffY = { -2000, 2000 },
	warnSize = { 8, 40 }, warnOffX = { -2000, 2000 }, warnOffY = { -2000, 2000 }, badgeSize = { 16, 64 },
	swingHeight = { 2, 12 }, swingGap = { 0, 60 },
	mitigScale = { 0.5, 2 }, mitigFont = { 8, 20 }, mitigLevelDiff = { 0, 3 },
	minimapAngle = { -360, 720 },
	x = { -4000, 4000 }, y = { -4000, 4000 },
}

local ALIGNS = { left = true, center = true, right = true }

local function Copy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = Copy(x)
	end
	return out
end
ns.CopyTable = Copy

-- Accepts { r, g, b, a } or { r = , g = , b = , a = }. Returns a clean
-- array copy or nil.
function ns.NormalizeColor(c, fallback)
	if type(c) ~= "table" then
		return fallback and Copy(fallback) or nil
	end
	local r = tonumber(c[1] or c.r)
	local g = tonumber(c[2] or c.g)
	local b = tonumber(c[3] or c.b)
	local a = tonumber(c[4] or c.a)
	if not r or not g or not b then
		return fallback and Copy(fallback) or nil
	end
	if a == nil then
		a = fallback and fallback[4] or 1
	end
	local function C(v)
		return math.max(0, math.min(1, v))
	end
	return { C(r), C(g), C(b), C(a) }
end

-- 1.x stored the style either as a name or as a 1-based index.
local STYLE_ALIASES = {
	classic = "classic", rounded = "classic", default = "classic",
	minimal = "minimal", flat = "minimal",
	inset = "inset", rail = "inset",
	luminous = "luminous", beveled = "luminous", bevel = "luminous",
}

function ns.NormalizeStyle(v)
	if type(v) == "number" then
		return ns.STYLES[math.floor(v)] or "classic"
	end
	if type(v) == "string" then
		local s = v:lower()
		if STYLE_ALIASES[s] then
			return STYLE_ALIASES[s]
		end
		for word in s:gmatch("%a+") do
			if STYLE_ALIASES[word] then
				return STYLE_ALIASES[word]
			end
		end
	end
	return "classic"
end

------------------------------------------------------------------------
-- Migration (pure: works on any table, unit-tested)
------------------------------------------------------------------------

local function MigrateFrom1x(db)
	-- Ability group position. readyOffsetX/Y were offsets from the line;
	-- readyX/readyY were screen positions (offsets from the screen center).
	if db.readyOffX == nil and db.readyOffY == nil then
		local ox, oy = tonumber(db.readyOffsetX), tonumber(db.readyOffsetY)
		if ox or oy then
			db.readyOffX, db.readyOffY = ox or 0, oy or 50
		else
			local rx, ry = tonumber(db.readyX), tonumber(db.readyY)
			if rx or ry then
				local lx = tonumber(db.x) or ns.DEFAULTS.x
				local ly = tonumber(db.y) or ns.DEFAULTS.y
				db.readyOffX = (rx or lx) - lx
				db.readyOffY = (ry or (ly + 50)) - ly
			end
		end
	end
	-- learnedIDs: a single number per key becomes a list.
	if type(db.learnedIDs) == "table" then
		for key, v in pairs(db.learnedIDs) do
			if type(v) == "number" then
				db.learnedIDs[key] = { v }
			elseif type(v) ~= "table" then
				db.learnedIDs[key] = nil
			end
		end
	end
	-- tracked / readyCDs could be lists of keys instead of key -> bool.
	for _, name in ipairs({ "tracked", "readyCDs" }) do
		local t = db[name]
		if type(t) == "table" and #t > 0 then
			local map = {}
			for _, key in ipairs(t) do
				if type(key) == "string" then
					map[key] = true
				end
			end
			for k, v in pairs(t) do
				if type(k) == "string" then
					map[k] = v and true or false
				end
			end
			db[name] = map
			db[name .. "Exclusive"] = true -- a list meant "only these"
		end
	end
end

function ns.MigrateDB(db)
	if type(db) ~= "table" then
		db = {}
	end
	local fromSchema = tonumber(db.schema) or 1
	if fromSchema < SCHEMA then
		MigrateFrom1x(db)
	end

	db.barStyle = ns.NormalizeStyle(db.barStyle)

	-- Fill and type-check known keys.
	for key, default in pairs(ns.DEFAULTS) do
		local v = db[key]
		if key == "colors" then
			if type(v) ~= "table" then
				v = {}
				db.colors = v
			end
			for ck, cdef in pairs(default) do
				v[ck] = ns.NormalizeColor(v[ck], cdef)
			end
		elseif key == "warnColor" then
			db.warnColor = ns.NormalizeColor(v, default)
		elseif type(default) == "table" then
			if type(v) ~= "table" then
				db[key] = Copy(default)
			end
		elseif type(default) == "number" then
			v = tonumber(v)
			db[key] = v or default
		elseif type(default) == "boolean" then
			if type(v) ~= "boolean" then
				if v == nil then
					db[key] = default
				else
					db[key] = (v ~= 0 and v ~= "0") and true or false
				end
			end
		elseif type(default) == "string" then
			if type(v) ~= "string" then
				db[key] = default
			end
		end
	end

	for key, range in pairs(ns.RANGES) do
		db[key] = G.Clamp(db[key], range[1], range[2])
	end
	if not ALIGNS[db.readyAlign] then
		db.readyAlign = "center"
	end
	if not ALIGNS[db.warnAlign] then
		db.warnAlign = "center"
	end
	db.schema = SCHEMA
	return db
end

------------------------------------------------------------------------
-- Access
------------------------------------------------------------------------

-- Before ADDON_LOADED the saved table does not exist yet: UI built at load
-- time reads a throwaway table of defaults instead.
local loadTimeDB

function ns.DB()
	if type(BulwarkDB) ~= "table" then
		if ns.dbReady then
			BulwarkDB = ns.MigrateDB({})
			return BulwarkDB
		end
		loadTimeDB = loadTimeDB or ns.MigrateDB({})
		return loadTimeDB
	end
	if BulwarkDB.schema ~= SCHEMA then
		ns.MigrateDB(BulwarkDB)
	end
	return BulwarkDB
end

-- "tracked" (line buffs) and "readyCDs" (ability icons): a missing key
-- means "use the catalog default".
function ns.IsTracked(key)
	local db = ns.DB()
	local v = db.tracked[key]
	if v == nil then
		if db.trackedExclusive then
			return false
		end
		local spell = ns.Spells and ns.Spells.Get(key)
		return not (spell and spell.lineDefault == false)
	end
	return v and true or false
end

function ns.IsReadyShown(key)
	local db = ns.DB()
	local v = db.readyCDs[key]
	if v == nil then
		if db.readyCDsExclusive then
			return false
		end
		local spell = ns.Spells and ns.Spells.Get(key)
		return spell and spell.readyDefault == true or false
	end
	return v and true or false
end

-- Positions and sizes back to the defaults (/bulwark reset).
ns.LAYOUT_KEYS = {
	"x", "y", "width", "lineHeight", "scale", "iconSize",
	"readyIconSize", "readySpacing", "readyOffX", "readyOffY", "readyAlign",
	"warnSize", "warnOffX", "warnOffY", "warnAlign",
	"badgeRFX", "badgeRFY", "badgeForbX", "badgeForbY", "badgeSize",
	"swingHeight", "swingGap", "mitigX", "mitigY", "mitigScale", "prepX", "prepY",
}

function ns.ResetLayout(keys)
	local db = ns.DB()
	for _, key in ipairs(keys or ns.LAYOUT_KEYS) do
		db[key] = Copy(ns.DEFAULTS[key])
	end
	db.lineHeight = ns.STYLE_THICKNESS[db.barStyle] or ns.DEFAULTS.lineHeight
end

ns.On("ADDON_LOADED", function(_, name)
	if name ~= ADDON_NAME and name ~= ns.NAME then
		return
	end
	BulwarkDB = ns.MigrateDB(BulwarkDB)
	ns.dbReady = true
end)
