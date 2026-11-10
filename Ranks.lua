--[[
  Bulwark: spell rank updater.

  When you learn a new rank, every action slot with a lower rank of that
  spell gets the highest rank. Also at login and whenever the bars change.
  With /bulwark keepdownranks on, only the previous top rank is replaced and
  lower ranks you placed on purpose (downranked heals) stay.

  Rank text ("Rank 3") is empty until the game has the spell's data, so
  ranks are read after C_Spell.RequestLoadSpellData + SPELL_DATA_LOAD_RESULT.

  /bulwark ranks          upgrade every lower rank on the bars now
  /bulwark autoranks      automatic upgrade on/off
  /bulwark rankscheck     list ranked spells on the bars and their state
  /bulwark keepdownranks  keep lower ranks placed on purpose on/off

  Placing actions is blocked in combat, so the work waits for combat to end.
]]

local ADDON_NAME, ns = ...
ns = ns or {}
local T = ns.T or function(text)
	return text
end

local R = {}
ns.Ranks = R

local MAX_ACTION_SLOT = 180
local PREFIX = "|cfff4c430Bulwark|r "

------------------------------------------------------------------------
-- Guards
------------------------------------------------------------------------

local function IsSecret(value)
	return issecretvalue and issecretvalue(value) and true or false
end

local function Num(value)
	if type(value) == "number" and not IsSecret(value) then
		return value
	end
	return nil
end

local function Str(value)
	if type(value) == "string" and not IsSecret(value) then
		return value
	end
	return nil
end

local function Call(fn, ...)
	if type(fn) ~= "function" then
		return false
	end
	return pcall(fn, ...)
end

------------------------------------------------------------------------
-- Spell info
------------------------------------------------------------------------

function R.SpellName(spellID)
	if not spellID then
		return nil
	end
	if C_Spell and C_Spell.GetSpellName then
		local ok, name = Call(C_Spell.GetSpellName, spellID)
		if ok and Str(name) then
			return name
		end
	end
	if GetSpellInfo then
		local ok, name = Call(GetSpellInfo, spellID)
		if ok and Str(name) then
			return name
		end
	end
	return nil
end

-- "Rank 3", "Ранг 3", "Rang 3" -> 3. No rank text -> nil.
function R.ParseRank(text)
	text = Str(text)
	if not text then
		return nil
	end
	local n = text:match("(%d+)")
	return n and tonumber(n) or nil
end

-- Spell IDs whose data we asked the game to load (rank text is empty until
-- the spell's data is cached; Forever addons like WhatsTraining do the same).
R.waiting = {}

local function EnsureLoaded(spellID)
	local api = C_Spell
	if type(api) ~= "table" or type(api.IsSpellDataCached) ~= "function" then
		return true -- old API: data is always there
	end
	local ok, cached = Call(api.IsSpellDataCached, spellID)
	if ok and cached == true then
		return true
	end
	if type(api.RequestLoadSpellData) == "function" then
		Call(api.RequestLoadSpellData, spellID)
		R.waiting[spellID] = true
	end
	return false
end

function R.SpellRank(spellID)
	if not spellID then
		return nil
	end
	if not EnsureLoaded(spellID) then
		return nil -- asked the game to load it; a rescan follows the load event
	end
	local text
	if C_Spell and C_Spell.GetSpellSubtext then
		local ok, sub = Call(C_Spell.GetSpellSubtext, spellID)
		if ok then
			text = Str(sub)
		end
	end
	if not text and GetSpellSubtext then
		local ok, sub = Call(GetSpellSubtext, spellID)
		if ok then
			text = Str(sub)
		end
	end
	return R.ParseRank(text)
end

local function IsKnown(spellID)
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		local ok, known = Call(C_SpellBook.IsSpellKnown, spellID)
		if ok and known ~= nil and not IsSecret(known) then
			return known and true or false
		end
	end
	if IsSpellKnown then
		local ok, known = Call(IsSpellKnown, spellID)
		if ok and known ~= nil and not IsSecret(known) then
			return known and true or false
		end
	end
	if IsPlayerSpell then
		local ok, known = Call(IsPlayerSpell, spellID)
		if ok and not IsSecret(known) then
			return known and true or false
		end
	end
	return true
end

------------------------------------------------------------------------
-- Spellbook scan: highest known rank per spell name
------------------------------------------------------------------------

local function Consider(best, spellID)
	spellID = Num(spellID)
	if not spellID or spellID <= 0 then
		return
	end
	local name = R.SpellName(spellID)
	if not name then
		return
	end
	local rank = R.SpellRank(spellID)
	if not rank then
		return -- spells without ranks never need an upgrade
	end
	if not IsKnown(spellID) then
		return
	end
	local cur = best[name]
	if not cur or rank > cur.rank then
		best[name] = { id = spellID, rank = rank }
	end
end

function R.ScanSpellbook()
	local best = {}
	if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo then
		local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
		local ok, numLines = Call(C_SpellBook.GetNumSpellBookSkillLines)
		numLines = ok and Num(numLines) or 0
		for i = 1, math.min(numLines, 40) do
			local okInfo, line = Call(C_SpellBook.GetSpellBookSkillLineInfo, i)
			if okInfo and type(line) == "table" and not IsSecret(line) then
				local offset = Num(line.itemIndexOffset) or 0
				local count = Num(line.numSpellBookItems) or 0
				for j = offset + 1, offset + math.min(count, 400) do
					local okType, _, actionID, spellID = Call(C_SpellBook.GetSpellBookItemType, j, bank)
					if okType then
						Consider(best, Num(spellID) or Num(actionID))
					end
				end
			end
		end
		return best
	end
	-- Older API.
	if GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo then
		local okTabs, tabs = Call(GetNumSpellTabs)
		tabs = okTabs and Num(tabs) or 0
		for tab = 1, tabs do
			local okTab, _, _, offset, count = Call(GetSpellTabInfo, tab)
			if okTab then
				offset, count = Num(offset) or 0, Num(count) or 0
				for j = offset + 1, offset + count do
					local okItem, kind, spellID = Call(GetSpellBookItemInfo, j, BOOKTYPE_SPELL or "spell")
					if okItem and kind == "SPELL" then
						Consider(best, spellID)
					end
				end
			end
		end
	end
	return best
end

------------------------------------------------------------------------
-- Planning (pure logic, unit-tested in tests/ranks_cases.lua)
------------------------------------------------------------------------

-- mode "all": any lower rank of a known spell gets the highest rank.
-- mode "learned": only slots holding prev[name].id, the old highest rank,
-- and only for spells whose highest rank went up between prev and best.
function R.PlanUpgrades(best, mode, prev)
	local plan = {}
	for slot = 1, MAX_ACTION_SLOT do
		local ok, kind, id = Call(GetActionInfo, slot)
		id = ok and Num(id) or nil
		if ok and kind == "spell" and id then
			local name = R.SpellName(id)
			local top = name and best[name]
			if top and top.id ~= id then
				local take = false
				if mode == "all" then
					local rank = R.SpellRank(id)
					take = rank ~= nil and rank < top.rank
				elseif mode == "learned" and prev then
					local old = prev[name]
					take = old ~= nil and old.id == id and old.rank < top.rank
				end
				if take then
					plan[#plan + 1] = { slot = slot, from = id, to = top.id, name = name, rank = top.rank }
				end
			end
		end
	end
	return plan
end

------------------------------------------------------------------------
-- Placing
------------------------------------------------------------------------

local function Pickup(spellID)
	if C_Spell and C_Spell.PickupSpell then
		return Call(C_Spell.PickupSpell, spellID)
	end
	return Call(PickupSpell, spellID)
end

local function CursorBusy()
	local ok, kind = Call(GetCursorInfo)
	return ok and kind ~= nil
end

-- Returns number of slots changed, or nil when it has to wait.
function R.ApplyPlan(plan)
	if #plan == 0 then
		return 0
	end
	if InCombatLockdown and InCombatLockdown() then
		return nil
	end
	if CursorBusy() then
		return nil -- the player is dragging something; try again later
	end
	local done, perSpell = 0, {}
	for _, step in ipairs(plan) do
		Pickup(step.to)
		if CursorBusy() then
			Call(PlaceAction, step.slot)
			Call(ClearCursor)
			local ok, _, now = Call(GetActionInfo, step.slot)
			if ok and Num(now) == step.to then
				done = done + 1
				local key = step.name .. "|" .. step.rank
				perSpell[key] = (perSpell[key] or 0) + 1
			end
		end
	end
	for key, count in pairs(perSpell) do
		local name, rank = key:match("^(.*)|(%d+)$")
		print(PREFIX .. string.format(T("%s -> rank %s on %d slot(s)."), name, rank, count))
	end
	return done
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local snapshot      -- highest ranks the bars were last synced to
local pendingAll    -- a full pass is waiting for combat to end
local pendingLearn  -- a learned-rank pass is waiting
local scanQueued

local function DB()
	if type(BulwarkDB) ~= "table" then
		return nil
	end
	if BulwarkDB.autoRanks == nil then
		BulwarkDB.autoRanks = true
	end
	if BulwarkDB.keepDownranks == nil then
		BulwarkDB.keepDownranks = false
	end
	return BulwarkDB
end

-- "all": every lower rank on the bars gets the highest (default).
-- "learned": only the previous top rank (keeps downranks placed on purpose).
local function Mode(db)
	return (db and db.keepDownranks) and "learned" or "all"
end

local snapshot     -- highest ranks the bars were last synced to
local pending      -- a pass is waiting for combat / the cursor
local scanQueued

-- One pass. verbose: say something even when nothing changed.
function R.Run(verbose)
	local db = DB()
	local best = R.ScanSpellbook()
	local mode = Mode(db)
	local plan
	if mode == "learned" then
		if not snapshot then
			snapshot = best
			return
		end
		plan = R.PlanUpgrades(best, "learned", snapshot)
	else
		plan = R.PlanUpgrades(best, "all")
	end
	local result = R.ApplyPlan(plan)
	if result == nil then
		pending = true
		if verbose then
			print(PREFIX .. T("ranks: waiting until you are out of combat."))
		end
		return
	end
	pending = false
	snapshot = best
	if verbose and result == 0 then
		if next(R.waiting) then
			print(PREFIX .. T("ranks: loading spell data, trying again in a moment."))
		else
			print(PREFIX .. T("ranks: every spell on your bars is already the highest rank."))
		end
	end
end

-- Kept for older callers.
function R.RunAll(verbose)
	R.Run(verbose)
end
R.RunLearned = R.Run

local frame = CreateFrame("Frame")
local function QueueScan(delay)
	if scanQueued then
		return
	end
	scanQueued = true
	C_Timer.After(delay or 0.5, function()
		scanQueued = false
		local db = DB()
		if db and db.autoRanks then
			R.Run(false)
		end
	end)
end
R.QueueScan = QueueScan

frame:SetScript("OnEvent", function(_, event, spellID)
	if event == "PLAYER_LOGIN" then
		QueueScan(2)
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pending then
			QueueScan(0.2)
		end
	elseif event == "SPELL_DATA_LOAD_RESULT" then
		if R.waiting[spellID] then
			R.waiting[spellID] = nil
			if not next(R.waiting) then
				QueueScan(0.2) -- every rank we asked for has arrived
			end
		end
	else
		QueueScan(0.5)
	end
end)
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("SPELLS_CHANGED")
pcall(frame.RegisterEvent, frame, "LEARNED_SPELL_IN_SKILL_LINE")
pcall(frame.RegisterEvent, frame, "LEARNED_SPELL_IN_TAB")
pcall(frame.RegisterEvent, frame, "SPELL_DATA_LOAD_RESULT")
pcall(frame.RegisterEvent, frame, "ACTIONBAR_SLOT_CHANGED")

-- /bulwark rankscheck: every ranked spell on the bars and what it should be.
function R.Check()
	local best = R.ScanSpellbook()
	local shown = 0
	for slot = 1, MAX_ACTION_SLOT do
		local ok, kind, id = Call(GetActionInfo, slot)
		id = ok and Num(id) or nil
		if ok and kind == "spell" and id then
			local name = R.SpellName(id)
			local rank = R.SpellRank(id)
			local top = name and best[name]
			if top or rank then
				shown = shown + 1
				print(string.format("  %d: %s %s -> %s", slot, tostring(name or id),
					rank and ("rank " .. rank) or "rank ?",
					top and ("rank " .. top.rank .. (top.id == id and " (ok)" or " (old)")) or "no ranked entry in the spellbook"))
			end
		end
	end
	local waiting = 0
	for _ in pairs(R.waiting) do
		waiting = waiting + 1
	end
	print(PREFIX .. string.format(T("ranks: %d ranked spells on your bars, %d still loading, mode: %s"), shown, waiting,
		Mode(DB()) == "all" and T("upgrade every lower rank") or T("keep downranks")))
end

------------------------------------------------------------------------
-- Slash: /bulwark ranks, /bulwark autoranks
------------------------------------------------------------------------

local previous = SlashCmdList and SlashCmdList.BULWARK
if previous then
	SlashCmdList.BULWARK = function(msg)
		local cmd = string.lower(msg or ""):match("^(%S+)") or ""
		if cmd == "ranks" then
			R.Run(true)
			return
		elseif cmd == "rankscheck" then
			R.Check()
			return
		elseif cmd == "keepdownranks" then
			local db = DB()
			if db then
				db.keepDownranks = not db.keepDownranks
				print(PREFIX .. T("keep lower ranks placed on purpose:"), db.keepDownranks and T("on") or T("off"))
			end
			return
		elseif cmd == "autoranks" then
			local db = DB()
			if db then
				db.autoRanks = not db.autoRanks
				print(PREFIX .. T("automatic rank upgrade:"), db.autoRanks and T("on") or T("off"))
			end
			return
		end
		previous(msg)
		if cmd == "" or cmd == "help" then
			print(T("  |cffaaaaaa/bulwark|r ranks | autoranks | rankscheck | keepdownranks"))
		end
	end
end
