--[[
  Bulwark core: guards around every read of game data.

  WoW Forever can hand back "secret" values in combat. A secret value may
  not be compared, indexed or used in arithmetic, so every read goes
  through these helpers: they return a plain Lua value or nil. Callers
  treat nil as "could not read" (hidden), never as "missing" or "zero".
]]

local ADDON_NAME, ns = ...
ns = ns or {}

local G = {}
ns.G = G

function G.IsSecret(value)
	if issecretvalue == nil then
		return false
	end
	local ok, secret = pcall(issecretvalue, value)
	return ok and secret == true
end
local IsSecret = G.IsSecret

function G.Num(value)
	if type(value) == "number" and not IsSecret(value) and value == value then
		return value
	end
	return nil
end

function G.Str(value)
	if type(value) == "string" and not IsSecret(value) then
		return value
	end
	return nil
end

-- Boolean-ish result: true / false, or nil when the value is secret.
function G.Flag(value)
	if IsSecret(value) then
		return nil
	end
	return value and true or false
end

-- pcall that returns (ok, ...); a missing function counts as a failure.
function G.Call(fn, ...)
	if type(fn) ~= "function" then
		return false
	end
	return pcall(fn, ...)
end

-- First return value, or nil on error or when it is secret.
function G.Read(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a = pcall(fn, ...)
	if not ok or IsSecret(a) then
		return nil
	end
	return a
end

-- Several return values. Returns a table { n = count, hidden = bool, ... }
-- with secret values replaced by nil, or nil when the call failed.
function G.ReadAll(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local packed = { pcall(fn, ...) }
	if not packed[1] then
		return nil
	end
	local out = { n = 0, hidden = false }
	for i = 2, #packed do
		local v = packed[i]
		if IsSecret(v) then
			v = nil
			out.hidden = true
		end
		out[i - 1] = v
		out.n = i - 1
	end
	return out
end

-- Safe table field: nil for secret tables, errors or secret values.
local function Index(tbl, key)
	return tbl[key]
end

function G.Field(tbl, key)
	if type(tbl) ~= "table" or IsSecret(tbl) then
		return nil
	end
	local ok, value = pcall(Index, tbl, key)
	if not ok or IsSecret(value) then
		return nil
	end
	return value
end

-- Forbidden Blizzard frames must not be read at all: even a field read
-- inside pcall raises the "blocked from an action" popup. IsForbidden
-- itself is always allowed.
function G.IsForbidden(frame)
	if type(frame) ~= "table" then
		return true
	end
	local fn = frame.IsForbidden -- reading IsForbidden itself is allowed
	if type(fn) ~= "function" then
		return false
	end
	local ok, forbidden = pcall(fn, frame)
	return not ok or forbidden == true
end

------------------------------------------------------------------------
-- Names
------------------------------------------------------------------------

local CURLY = { "\226\128\153", "\226\128\152", "\202\188", "`" }

-- Lowercase, trimmed, curly apostrophes made straight.
function G.Norm(name)
	if type(name) ~= "string" or IsSecret(name) then
		return nil
	end
	local s = name
	for _, c in ipairs(CURLY) do
		s = s:gsub(c, "'")
	end
	s = s:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
	if s == "" then
		return nil
	end
	return s
end

------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------

function G.Now()
	return G.Num(G.Read(GetTime)) or 0
end

function G.Clamp(v, lo, hi)
	v = tonumber(v)
	if not v then
		return lo
	end
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end

function G.Round(v, step)
	step = step or 1
	return math.floor(v / step + 0.5) * step
end

function G.InCombat()
	if type(InCombatLockdown) == "function" then
		local ok, v = pcall(InCombatLockdown)
		if ok and v == true then
			return true
		end
	end
	return G.Flag(G.Read(UnitAffectingCombat, "player")) == true
end

-- C_Secrets answers: true (secret), false (readable) or nil (unknown).
-- A failed or secret answer counts as "secret".
local function SecretsCall(name, ...)
	local api = _G.C_Secrets
	if type(api) ~= "table" or type(api[name]) ~= "function" then
		return nil
	end
	local ok, v = pcall(api[name], ...)
	if not ok or IsSecret(v) then
		return true
	end
	return v
end

function G.AurasSecret()
	local v = SecretsCall("ShouldAurasBeSecret")
	if v == nil then
		return false
	end
	return v and true or false
end

function G.CooldownsSecret()
	local v = SecretsCall("ShouldCooldownsBeSecret")
	if v == nil then
		return false
	end
	return v and true or false
end

-- Is this spell's aura readable right now? true / false.
function G.SpellAuraSecret(spellID)
	local v = SecretsCall("ShouldSpellAuraBeSecret", spellID)
	if v ~= nil then
		return v and true or false
	end
	local level = SecretsCall("GetSpellAuraSecrecy", spellID)
	if level == true then
		return true
	end
	local enum = _G.Enum and _G.Enum.SecrecyLevel
	if type(level) == "number" and type(enum) == "table" then
		if level == enum.AlwaysSecret then
			return true
		end
		if level == enum.ContextuallySecret then
			return G.InCombat()
		end
	end
	return false
end

------------------------------------------------------------------------
-- Player state used by the "hide when ..." options
------------------------------------------------------------------------

function G.PlayerState()
	return {
		flying = G.Flag(G.Read(IsFlying)) == true,
		resting = G.Flag(G.Read(IsResting)) == true,
		mounted = G.Flag(G.Read(IsMounted)) == true,
		dead = G.Flag(G.Read(UnitIsDeadOrGhost, "player")) == true,
		combat = G.InCombat(),
	}
end

-- prefix: "bar", "icons" or "warn". Pure: db and state are plain tables.
function G.ShouldShow(db, prefix, onlyInCombatKey, state)
	if not db then
		return false
	end
	if db[onlyInCombatKey] and not state.combat then
		return false
	end
	if db[prefix .. "HideFlying"] and state.flying then
		return false
	end
	if db[prefix .. "HideResting"] and state.resting and not state.combat then
		return false
	end
	if db[prefix .. "HideMounted"] and state.mounted then
		return false
	end
	if db[prefix .. "HideDead"] and state.dead then
		return false
	end
	return true
end

function G.PlayerClass()
	local ok, _, class = pcall(UnitClass, "player")
	if ok and type(class) == "string" and not IsSecret(class) then
		return class
	end
	return nil
end

function G.IsPaladin()
	return G.PlayerClass() == "PALADIN"
end
