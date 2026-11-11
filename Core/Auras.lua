--[[
  Bulwark core: player auras and the duration-line trackers.

  Every catalog spell gets a status each scan:
    "present"  the aura is confirmed on the player
    "absent"   confirmed missing (a full, readable scan did not find it)
    "hidden"   could not tell (secret values, failed read)
  A hidden status never removes a tracked icon and never creates a
  reminder: the tracker keeps its last readable state and runs the timer
  from the cast (or the last confirmed expiration).
]]

local ADDON_NAME, ns = ...
ns = ns or {}
local G, S = ns.G, ns.Spells

local A = {}
ns.Auras = A

A.status = {}   -- key -> "present" / "absent" / "hidden"
A.data = {}     -- key -> { expires, duration, icon, name, spellId } when present
A.entries = {}  -- key -> line entry { expires, duration, icon, source, start }
A.ended = {}    -- key -> { at, reason } last time an entry left the line

------------------------------------------------------------------------
-- Reading
------------------------------------------------------------------------

local function AuraFields(data)
	return {
		name = G.Str(G.Field(data, "name")),
		icon = G.Field(data, "icon"),
		spellId = G.Num(G.Field(data, "spellId")),
		duration = G.Num(G.Field(data, "duration")),
		expires = G.Num(G.Field(data, "expirationTime")),
	}
end

-- One pass over the player's auras. complete = every aura was readable.
local function ScanFilter(filter, found, names)
	local api = _G.C_UnitAuras
	if type(api) == "table" and type(api.GetAuraDataByIndex) == "function" then
		for i = 1, 80 do
			local ok, data = pcall(api.GetAuraDataByIndex, "player", i, filter)
			if not ok then
				return false
			end
			if data == nil then
				return true
			end
			if G.IsSecret(data) then
				return false
			end
			local a = AuraFields(data)
			if not a.name and not a.spellId then
				return false
			end
			local key = S.Match(a.spellId, a.name)
			if key and not found[key] then
				found[key] = a
			end
			if a.name then
				names[G.Norm(a.name) or ""] = a
			end
		end
		return true
	end
	local fn = filter == "HELPFUL" and _G.UnitBuff or _G.UnitDebuff
	if type(fn) ~= "function" then
		return false
	end
	for i = 1, 40 do
		local r = G.ReadAll(fn, "player", i)
		if not r then
			return false
		end
		if r[1] == nil then
			if r.hidden then
				return false
			end
			return true
		end
		local a = { name = G.Str(r[1]), icon = r[2], duration = G.Num(r[5]), expires = G.Num(r[6]), spellId = G.Num(r[10]) }
		local key = S.Match(a.spellId, a.name)
		if key and not found[key] then
			found[key] = a
		end
		names[G.Norm(a.name) or ""] = a
	end
	return true
end

-- Direct queries, used when the full scan was not readable.
local function QueryKey(key)
	local api = _G.C_UnitAuras
	if type(api) ~= "table" then
		return nil
	end
	local spell = S.Get(key)
	local filter = spell and spell.harmful and "HARMFUL" or "HELPFUL"
	if type(api.GetPlayerAuraBySpellID) == "function" then
		for _, id in ipairs(S.AllIDs(key)) do
			local ok, data = pcall(api.GetPlayerAuraBySpellID, id)
			if ok and data ~= nil then
				-- Something came back: the aura is there, even if its fields are secret.
				local a = G.IsSecret(data) and {} or AuraFields(data)
				a.spellId = a.spellId or id
				return a
			end
		end
	end
	if type(api.GetAuraDataBySpellName) == "function" then
		local spellNames = { spell and spell.name, spell and spell.localName }
		for _, n in ipairs(spellNames) do
			local ok, data = pcall(api.GetAuraDataBySpellName, "player", n, filter)
			if ok and data ~= nil then
				local a = G.IsSecret(data) and {} or AuraFields(data)
				if a.spellId then
					S.Learn(key, a.spellId)
				end
				return a
			end
		end
	end
	return nil
end

-- Can an empty direct query be trusted as "not on you"? Yes when the game
-- says this spell's aura is readable right now (C_Secrets per spell). Then a
-- single unreadable *other* aura, or the general "auras are secret" flag,
-- does not silence the reminder. Spells without known IDs fall back to the
-- general flag.
function A.QueryTrustworthy(key)
	local api = _G.C_UnitAuras
	if type(api) ~= "table" or (type(api.GetPlayerAuraBySpellID) ~= "function"
		and type(api.GetAuraDataBySpellName) ~= "function") then
		return false
	end
	local ids = S.AllIDs(key)
	if #ids == 0 then
		return not G.AurasSecret()
	end
	for _, id in ipairs(ids) do
		if G.SpellAuraSecret(id) then
			return false
		end
	end
	return true
end

A.names = {}      -- normalized name -> aura (last complete scan, for Prep)
A.known = {}      -- key -> { status, at }: the last status that was readable
A.cast = {}       -- key -> time of your last cast of it
A.complete = false

-- Pure: decides a status from a scan result.
function A.StatusOf(found, complete, queried)
	if found or queried then
		return "present"
	end
	if complete then
		return "absent"
	end
	return "hidden"
end

function A.Scan()
	local found, names = {}, {}
	local okHelp = ScanFilter("HELPFUL", found, names)
	local okHarm = ScanFilter("HARMFUL", found, names)
	local complete = okHelp and okHarm and not G.AurasSecret()
	A.complete = complete
	if complete then
		A.names = names
	end
	for key in pairs(S.CATALOG) do
		local data = found[key]
		local queried, trusted
		if not data and not complete then
			queried = QueryKey(key)
			trusted = not queried and A.QueryTrustworthy(key)
		end
		local status = A.StatusOf(data, complete or trusted, queried)
		A.status[key] = status
		if status ~= "hidden" then
			A.known[key] = { status = status, at = G.Now() }
		end
		A.data[key] = data or queried
	end
	return complete
end

function A.Status(key)
	return A.status[key] or "hidden"
end

-- Like A.Status, but a hidden read (auras turn secret in combat on WoW
-- Forever) keeps the last readable "absent" as long as you have not cast
-- the spell since. So "Righteous Fury missing" stays up in combat when it
-- was missing before the pull.
function A.Remembered(key)
	local st = A.Status(key)
	if st ~= "hidden" then
		return st
	end
	local k = A.known[key]
	if k and k.status == "absent" and not (A.cast[key] and A.cast[key] >= k.at) then
		return "absent"
	end
	return "hidden"
end

-- Same for a group (all seals, all auras): "absent" only when every one
-- of them was last seen absent and none was cast since.
function A.RememberedNone(keys)
	for _, key in ipairs(keys) do
		if A.Remembered(key) ~= "absent" then
			return false
		end
	end
	return true
end

------------------------------------------------------------------------
-- Line entries (pure: entries, now and the read are passed in)
------------------------------------------------------------------------

-- Base duration of a line buff, with Guardian's Favor for Freedom.
function A.BaseDuration(key, ranks)
	local spell = S.Get(key)
	local dur = spell and spell.dur or 0
	if key == "freedom" then
		dur = dur + 3 * ((ranks and ranks.guardians_favor) or 0)
	end
	return dur
end

local function Ended(ended, key, now, reason)
	if ended then
		ended[key] = { at = now, reason = reason }
	end
end

-- Seals are exclusive: a new seal removes the others from the line.
local function ClearOtherSeals(entries, keep, now, ended)
	for _, k in ipairs(S.SEALS) do
		if k ~= keep and entries[k] then
			entries[k] = nil
			Ended(ended, k, now, "replaced")
		end
	end
end

-- Apply one read to one entry. status: "present"/"absent"/"hidden".
-- data: { expires, duration, icon } for a present aura (fields may be nil).
function A.ApplyRead(entries, key, status, data, now, baseDur, ended)
	local spell = S.Get(key)
	local e = entries[key]
	if spell and spell.castOnly then
		-- No aura to read: the cast timer is the only source.
		if e and now >= e.expires then
			entries[key] = nil
			Ended(ended, key, now, "expired")
		end
		return entries[key]
	end
	if status == "present" then
		local expires = data and data.expires
		local duration = data and data.duration
		if expires and expires > 0 and duration and duration > 0 then
			local isNew = not e
			e = e or {}
			e.expires, e.duration, e.source = expires, duration, "aura"
			e.icon = data.icon or e.icon
			entries[key] = e
			if isNew and spell and spell.seal then
				ClearOtherSeals(entries, key, now, ended)
			end
		elseif not e then
			-- Present but timing hidden: start from now with the base duration.
			e = { expires = now + baseDur, duration = baseDur, source = "guess", icon = data and data.icon }
			entries[key] = e
			if spell and spell.seal then
				ClearOtherSeals(entries, key, now, ended)
			end
		elseif now >= e.expires then
			-- Still there after our timer ran out (refreshed while hidden).
			e.expires, e.duration, e.source = now + baseDur, baseDur, "guess"
		end
		e.confirmed = now
	elseif status == "absent" then
		if e then
			entries[key] = nil
			Ended(ended, key, now, now >= e.expires - 0.5 and "expired" or "removed")
		end
	else -- hidden: keep, but drop once the timer has run out
		if e and now >= e.expires then
			entries[key] = nil
			Ended(ended, key, now, "expired")
		end
	end
	return entries[key]
end

-- The player cast a line spell: start (or restart) its timer.
function A.ApplyCast(entries, key, now, baseDur, ended)
	local spell = S.Get(key)
	if not spell or not spell.dur then
		return nil
	end
	local e = entries[key] or {}
	e.expires, e.duration, e.source, e.start = now + baseDur, baseDur, "cast", now
	entries[key] = e
	if spell.seal then
		ClearOtherSeals(entries, key, now, ended)
	end
	return e
end

------------------------------------------------------------------------
-- Summaries used by reminders and the prep window
------------------------------------------------------------------------

-- Any seal on the player: "present" / "absent" / "hidden".
function A.SealStatus()
	local hidden = false
	for _, k in ipairs(S.SEALS) do
		local st = A.Status(k)
		if st == "present" or A.entries[k] then
			return "present", k
		end
		if st ~= "absent" then
			hidden = true
		end
	end
	return hidden and "hidden" or "absent"
end

-- A paladin aura: "devotion", "resist", "other", "none" or "hidden".
function A.PaladinAura()
	if A.Status("devotion_aura") == "present" then
		return "devotion"
	end
	local hidden = A.Status("devotion_aura") == "hidden"
	for _, k in ipairs(S.AURAS) do
		local spell = S.Get(k)
		local st = A.Status(k)
		if st == "present" then
			return spell.resistAura and "resist" or "other"
		elseif st == "hidden" then
			hidden = true
		end
	end
	return hidden and "hidden" or "none"
end

-- Aura by name from the last complete scan (English or localized name).
function A.HasNamed(names)
	if not A.complete then
		return nil
	end
	for _, n in ipairs(names) do
		local a = A.names[G.Norm(n) or ""]
		if a then
			return a
		end
	end
	return false
end

------------------------------------------------------------------------
-- Updates
------------------------------------------------------------------------

local sealFuryWasUp = false

function A.Update()
	local now = G.Now()
	A.Scan()
	for _, key in ipairs(S.LINE) do
		local base = A.BaseDuration(key, S.ranks)
		A.ApplyRead(A.entries, key, A.Status(key), A.data[key], now, base, A.ended)
	end
	-- Sound when Seal of Fury drops in combat (not when replaced by a cast).
	local up = A.entries.seal_fury ~= nil
	if sealFuryWasUp and not up then
		local ended = A.ended.seal_fury
		local db = ns.DB()
		if db.soundSealDrop and G.InCombat() and ended and ended.reason ~= "replaced" then
			A.PlayDrop()
		end
	end
	sealFuryWasUp = up
end

function A.PlayDrop()
	local kit = _G.SOUNDKIT
	local id = type(kit) == "table" and G.Num(kit.RAID_WARNING) or 8959
	if not G.Call(_G.PlaySound, id, "Master") then
		G.Call(_G.PlaySoundFile, "Sound\\Interface\\RaidWarning.ogg", "Master")
	end
end

-- Own casts: start timers (cast-only spells, hidden auras) and learn IDs.
function A.OnCast(spellID)
	local key = S.Match(spellID)
	if not key then
		return nil
	end
	local now = G.Now()
	A.cast[key] = now
	local spell = S.Get(key)
	if spell.dur then
		local base = A.BaseDuration(key, S.ranks)
		if spell.castOnly or A.Status(key) ~= "present" or spell.seal then
			A.ApplyCast(A.entries, key, now, base, A.ended)
		end
	end
	if ns.Abilities and ns.Abilities.OnCast then
		ns.Abilities.OnCast(key, now)
	end
	return key
end

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
	if G.Str(unit) ~= "player" then
		return
	end
	A.OnCast(G.Num(spellID))
	A.dirty = true
end)

-- UNIT_AURA can fire many times a second in combat: only mark dirty.
ns.On("UNIT_AURA", function(_, unit)
	if G.Str(unit) == "player" then
		A.dirty = true
	end
end)
ns.On("PLAYER_ENTERING_WORLD", function()
	A.dirty = true
end)

local sinceFull = 0
ns.Every(0.1, function(elapsed)
	sinceFull = sinceFull + (elapsed or 0)
	if A.dirty or sinceFull >= 0.5 then
		A.dirty = false
		sinceFull = 0
		A.Update()
	end
end)
