--[[
  Bulwark core: swing timer rail under the line.

  The rail fills left to right between main-hand swings. Sources:
    PLAYER_SWING (when the client has it)
    own SWING_DAMAGE / SWING_MISSED from the combat log (optional)
  PLAYER_SWING is used as a signal only: its payload can be secret on
  Forever, and a paladin has no off-hand weapon, so every event is a
  main-hand swing.
  Swing length comes from UnitAttackSpeed("player"): read on every swing,
  in combat too; a secret or failed read keeps the last plain number.
  Parry haste: when the player parries, the time to the next swing
  shrinks by 40 % of the weapon speed, but not below 20 % of the weapon
  speed (and never grows).
]]

local ADDON_NAME, ns = ...
ns = ns or {}
local G, W = ns.G, ns.W

local SW = {}
ns.Swing = SW

------------------------------------------------------------------------
-- Pure swing math (unit-tested)
------------------------------------------------------------------------

function SW.New()
	return { speed = nil, start = nil, finish = nil }
end

-- A main-hand swing landed (or missed) at `now`. Returns false for a
-- duplicate report of the same swing from a second source.
function SW.Begin(st, now, speed)
	speed = speed or st.speed
	if not speed or speed <= 0 then
		return false
	end
	if st.start and now - st.start < speed * 0.3 then
		return false
	end
	st.speed = speed
	st.start = now
	st.finish = now + speed
	return true
end

-- Weapon change: the swing restarts from now.
function SW.Restart(st, now, speed)
	speed = speed or st.speed
	if not st.finish or not speed then
		st.speed = speed or st.speed
		return
	end
	st.speed = speed
	st.start = now
	st.finish = now + speed
end

function SW.Stop(st)
	st.start, st.finish = nil, nil
end

-- Classic parry haste. Returns the new remaining time (or nil).
function SW.ParryHaste(remaining, speed)
	if not remaining or not speed or remaining <= 0 then
		return remaining
	end
	local floor = 0.2 * speed
	if remaining <= floor then
		return remaining
	end
	return math.max(remaining - 0.4 * speed, floor)
end

function SW.Parry(st, now)
	if not st.finish or not st.speed or now >= st.finish then
		return false
	end
	if st.lastParry and now - st.lastParry < 0.05 then
		return false -- same parry reported twice
	end
	st.lastParry = now
	local remaining = SW.ParryHaste(st.finish - now, st.speed)
	st.finish = now + remaining
	return true
end

function SW.Remaining(st, now)
	if not st.finish then
		return nil
	end
	return math.max(0, st.finish - now)
end

-- Fill 0..1: how much of a full swing has passed.
function SW.Fraction(st, now)
	if not st.finish or not st.speed or st.speed <= 0 then
		return 0
	end
	local f = 1 - (st.finish - now) / st.speed
	if f < 0 then
		return 0
	end
	if f > 1 then
		return 1
	end
	return f
end

-- Idle: no swing for a while after the last one finished.
function SW.Idle(st, now)
	if not st.finish then
		return true
	end
	return now > st.finish + (st.speed or 2) * 1.5
end

-- Combat log row -> "swing", "parry" or nil. args = { CombatLogGetCurrentEventInfo() }
function SW.FromCombatLog(args, playerGUID)
	if type(args) ~= "table" or not playerGUID then
		return nil
	end
	local sub = G.Str(args[2])
	if not sub then
		return nil
	end
	local source, dest = G.Str(args[4]), G.Str(args[8])
	if source == playerGUID then
		if sub == "SWING_DAMAGE" then
			return args[21] ~= true and "swing" or nil
		elseif sub == "SWING_MISSED" then
			return args[13] ~= true and "swing" or nil
		end
	end
	if dest == playerGUID then
		if sub == "SWING_MISSED" and G.Str(args[12]) == "PARRY" then
			return "parry"
		elseif sub == "SPELL_MISSED" and G.Str(args[15]) == "PARRY" then
			return "parry"
		end
	end
	return nil
end

------------------------------------------------------------------------
-- Live state
------------------------------------------------------------------------

SW.state = SW.New()
local st = SW.state
local playerGUID

-- What fed the timer, for /bulwark swingdebug.
SW.debug = { playerSwing = 0, combatLog = 0, parry = 0, speedReads = 0, speedHidden = 0 }

local function ReadSpeed()
	local speed = G.Num(G.Read(UnitAttackSpeed, "player"))
	SW.debug.speedReads = SW.debug.speedReads + 1
	if not speed then
		SW.debug.speedHidden = SW.debug.speedHidden + 1
	end
	if speed and speed > 0 then
		st.speed = speed
	end
	local guid = G.Str(G.Read(UnitGUID, "player"))
	if guid then
		playerGUID = guid
	end
	return st.speed
end
SW.ReadSpeed = ReadSpeed

function SW.OnSwing(source)
	if source then
		SW.debug[source] = (SW.debug[source] or 0) + 1
		SW.debug.lastSource = source
	end
	-- Fresh speed on every swing (haste buffs change it mid-fight).
	SW.Begin(st, G.Now(), ReadSpeed())
end

function SW.OnParry()
	SW.debug.parry = SW.debug.parry + 1
	if ns.DB().swingParryHaste then
		SW.Parry(st, G.Now())
	end
end

ns.On("PLAYER_LOGIN", ReadSpeed)
ns.On("PLAYER_REGEN_ENABLED", ReadSpeed)
ns.On("UNIT_ATTACK_SPEED", function(_, unit)
	if G.Str(unit) == "player" then
		ReadSpeed()
	end
end)
-- Signal only: the payload is not read (it can be secret on Forever).
SW.playerSwingAvailable = ns.On("PLAYER_SWING", function()
	SW.OnSwing("playerSwing")
end)
ns.On("PLAYER_LEAVE_COMBAT", function()
	SW.Stop(st)
end)
ns.On("PLAYER_EQUIPMENT_CHANGED", function(_, slot)
	if G.Num(slot) == 16 then
		SW.Restart(st, G.Now(), ReadSpeed())
	end
end)
local lastWeapon
ns.On("UNIT_INVENTORY_CHANGED", function(_, unit)
	if G.Str(unit) ~= "player" then
		return
	end
	local id = G.Num(G.Read(GetInventoryItemID, "player", 16))
	if id ~= lastWeapon then
		if lastWeapon ~= nil then
			SW.Restart(st, G.Now(), ReadSpeed())
		end
		lastWeapon = id
	end
end)
ns.On("UNIT_COMBAT", function(_, unit, action)
	if G.Str(unit) == "player" and G.Str(action) == "PARRY" then
		SW.OnParry()
	end
end)

-- Optional source: the combat log may be missing or restricted.
local function OnCombatLog()
	if not ns.DB().swingCombatLog or type(CombatLogGetCurrentEventInfo) ~= "function" then
		return
	end
	local ok, args = pcall(function()
		return { CombatLogGetCurrentEventInfo() }
	end)
	if not ok then
		return
	end
	local what = SW.FromCombatLog(args, playerGUID)
	if what == "swing" then
		SW.OnSwing("combatLog")
	elseif what == "parry" then
		SW.OnParry()
	end
end
SW.combatLogAvailable = ns.On("COMBAT_LOG_EVENT_UNFILTERED", OnCombatLog)

-- /bulwark swingdebug: which sources work on this client.
function SW.DebugPrint()
	local d = SW.debug
	local function av(v)
		return v and "yes" or "no"
	end
	ns.Print("swing: PLAYER_SWING event %s (%d swings), combat log %s (%d swings, option %s), parries %d",
		av(SW.playerSwingAvailable), d.playerSwing, av(SW.combatLogAvailable), d.combatLog,
		ns.OnOff(ns.DB().swingCombatLog), d.parry)
	ns.Print("swing: speed %s (reads %d, hidden %d), last source %s, next swing in %s",
		tostring(st.speed or "?"), d.speedReads, d.speedHidden, tostring(d.lastSource or "none"),
		st.finish and string.format("%.2f", math.max(0, st.finish - G.Now())) or "-")
end

------------------------------------------------------------------------
-- Rail
------------------------------------------------------------------------

local line = ns.Line.frame
local rail = CreateFrame("Frame", "BulwarkSwingRail", line)
rail:SetSize(420, 4)
rail:Hide()
SW.rail = rail

rail.bg = rail:CreateTexture(nil, "BACKGROUND")
rail.bg:SetPoint("TOPLEFT", -1, 1)
rail.bg:SetPoint("BOTTOMRIGHT", 1, -1)
rail.fill = rail:CreateTexture(nil, "ARTWORK")
rail.fill:SetPoint("TOPLEFT")
rail.fill:SetPoint("BOTTOMLEFT")
rail.spark = rail:CreateTexture(nil, "OVERLAY")
rail.spark:SetTexture(W.WHITE)
rail.spark:SetWidth(2)
rail.time = W.Text(rail, nil, 10)
rail.time:SetPoint("LEFT", rail, "RIGHT", 5, 0)

function SW.Apply()
	local db = ns.DB()
	local c = db.colors
	rail:SetSize(db.width, db.swingHeight)
	rail:ClearAllPoints()
	rail:SetPoint("TOP", line, "BOTTOM", 0, -db.swingGap)
	rail.bg:SetColorTexture(c.bg[1], c.bg[2], c.bg[3], math.max(0.35, c.bg[4]))
	W.Gradient(rail.fill, "HORIZONTAL", c.line, { c.capEnd[1], c.capEnd[2], c.capEnd[3], c.capEnd[4] })
	rail.spark:ClearAllPoints()
	rail.spark:SetPoint("TOP", rail.fill, "TOPRIGHT", 0, 1)
	rail.spark:SetPoint("BOTTOM", rail.fill, "BOTTOMRIGHT", 0, -1)
	rail.spark:SetVertexColor(1, 1, 1, 0.9)
end

local testState = SW.New()

function SW.Render()
	local db = ns.DB()
	local now = G.Now()
	local movers = ns.Movers
	local testing = movers and movers.testing
	local s = st
	if testing then
		s = testState
		if not s.finish or now >= s.finish then
			SW.Begin(s, now, 2.4)
		end
	end
	local show = db.showSwing and (testing or (movers and movers.unlocked) or
		(G.IsPaladin() and not SW.Idle(s, now) and (not db.swingOnlyInCombat or G.InCombat())))
	if not show then
		rail:Hide()
		return
	end
	local frac = SW.Fraction(s, now)
	if movers and movers.unlocked and not testing and not s.finish then
		frac = 0.6
	end
	rail.fill:SetWidth(math.max(0.01, db.width * frac))
	if db.swingShowTime then
		local rem = SW.Remaining(s, now)
		rail.time:SetText(rem and string.format("%.1f", rem) or "")
		rail.time:Show()
	else
		rail.time:Hide()
	end
	rail:Show()
end

ns.Every(0.02, SW.Render)
