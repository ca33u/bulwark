--[[
  Bulwark: aggro list.

  A compact panel that lists the enemies in combat around you, read from
  enemy nameplates (enemy nameplates must be on, V key):
    gold   - the mob is attacking you
    orange - attacking you, but someone is about to pull it off
    red    - "loose": in combat with your group but hitting someone else

  Loose mobs are listed first, because those are the ones a tank must grab.
  The header counts "N on me" and "N loose".

  /bulwark aggro        show or hide the panel
  /bulwark aggrocombat  show the panel only in combat (default on)
  Move it with /bulwark unlock like the rest of Bulwark.

  If the client hides threat data for a mob (secret values), the row stays
  grey instead of guessing.
]]

local ADDON_NAME, ns = ...
ns = ns or {}
local T = ns.T or function(text)
	return text
end

local A = {}
ns.Aggro = A

local PREFIX = "|cfff4c430Bulwark|r "
local MAX_ROWS = 8
local ROW_H = 18
local WIDTH = 210
local MAX_PLATES = 40

A.STATE_LOOSE, A.STATE_LOSING, A.STATE_TANKING, A.STATE_UNKNOWN = 1, 2, 3, 4

local COLORS = {
	[1] = { 1.00, 0.27, 0.22 }, -- loose
	[2] = { 1.00, 0.62, 0.15 }, -- losing
	[3] = { 0.96, 0.77, 0.19 }, -- tanking (Bulwark gold)
	[4] = { 0.55, 0.55, 0.55 }, -- unknown
}

------------------------------------------------------------------------
-- Guards
------------------------------------------------------------------------

local function IsSecret(value)
	return issecretvalue and issecretvalue(value) and true or false
end

local function Read(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b = pcall(fn, ...)
	if not ok or IsSecret(a) then
		return nil
	end
	return a, b
end

------------------------------------------------------------------------
-- Classification (pure, unit-tested in tests/aggro_cases.lua)
------------------------------------------------------------------------

-- threat: UnitThreatSituation("player", mob) -> nil, 0, 1, 2, 3
-- targetIsMe / targetIsFriend: what the mob is targeting (nil = unknown)
-- Returns a state or nil when the mob is not part of the fight.
function A.Classify(threat, targetIsMe, targetIsFriend)
	if threat == 3 then
		return A.STATE_TANKING
	end
	if threat == 2 then
		return A.STATE_LOSING
	end
	if targetIsMe then
		return A.STATE_TANKING
	end
	if threat == 0 or threat == 1 then
		-- On my threat table but hitting someone else.
		if targetIsFriend == false then
			return nil -- fighting a non-group unit (a guard, another player)
		end
		return A.STATE_LOOSE
	end
	if targetIsFriend then
		return A.STATE_LOOSE
	end
	return nil
end

function A.Sort(rows)
	table.sort(rows, function(a, b)
		if a.state ~= b.state then
			return a.state < b.state
		end
		return (a.hp or 1) < (b.hp or 1)
	end)
	return rows
end

------------------------------------------------------------------------
-- Scan
------------------------------------------------------------------------

local function IsGroupUnit(unit)
	if Read(UnitIsUnit, unit, "player") then
		return true
	end
	if Read(UnitIsUnit, unit, "pet") then
		return true
	end
	if Read(UnitInParty, unit) or Read(UnitInRaid, unit) then
		return true
	end
	return false
end

local function ScanUnit(unit)
	if not Read(UnitExists, unit) then
		return nil
	end
	if not Read(UnitCanAttack, "player", unit) or Read(UnitIsDeadOrGhost, unit) then
		return nil
	end
	if not Read(UnitAffectingCombat, unit) then
		return nil
	end
	local target = unit .. "target"
	local threat = Read(UnitThreatSituation, "player", unit)
	local hasTarget = Read(UnitExists, target)
	local targetIsMe, targetIsFriend
	if hasTarget then
		targetIsMe = Read(UnitIsUnit, target, "player")
		targetIsFriend = IsGroupUnit(target)
	end
	local state = A.Classify(threat, targetIsMe, targetIsFriend)
	if not state then
		-- Threat hidden by the client: show it grey if it is in combat with us.
		if threat == nil and hasTarget == nil and Read(UnitAffectingCombat, "player") then
			state = A.STATE_UNKNOWN
		else
			return nil
		end
	end
	local hp
	local cur, mx = Read(UnitHealth, unit), Read(UnitHealthMax, unit)
	if type(cur) == "number" and type(mx) == "number" and mx > 0 then
		hp = cur / mx
	end
	local targetName
	if state == A.STATE_LOOSE and hasTarget then
		targetName = Read(UnitName, target)
	end
	return {
		unit = unit,
		state = state,
		hp = hp,
		mark = Read(GetRaidTargetIndex, unit),
		targetName = targetName,
	}
end

function A.Scan()
	local rows = {}
	local seen = {}
	for i = 1, MAX_PLATES do
		local unit = "nameplate" .. i
		local row = ScanUnit(unit)
		if row then
			local guid = Read(UnitGUID, unit)
			if not guid or not seen[guid] then
				if guid then
					seen[guid] = true
				end
				rows[#rows + 1] = row
			end
		end
	end
	return A.Sort(rows)
end

------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------

local function DB()
	if type(BulwarkDB) ~= "table" then
		return nil
	end
	local d = BulwarkDB.aggro
	if type(d) ~= "table" then
		d = {}
		BulwarkDB.aggro = d
	end
	if d.enabled == nil then d.enabled = true end
	if d.onlyInCombat == nil then d.onlyInCombat = true end
	if d.x == nil then d.x = 330 end
	if d.y == nil then d.y = -60 end
	return d
end

local panel = CreateFrame("Frame", "BulwarkAggroPanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
panel:SetSize(WIDTH, 24)
panel:SetFrameStrata("MEDIUM")
panel:SetClampedToScreen(true)
panel:Hide()
if panel.SetBackdrop then
	panel:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	panel:SetBackdropColor(0.05, 0.05, 0.07, 0.62)
	panel:SetBackdropBorderColor(0, 0, 0, 0.9)
end

local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
header:SetPoint("TOPLEFT", 8, -6)
header:SetText(T("AGGRO"))
header:SetTextColor(0.96, 0.77, 0.19)

local counts = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
counts:SetPoint("TOPRIGHT", -8, -6)

local rowFrames = {}
for i = 1, MAX_ROWS do
	local r = CreateFrame("Frame", nil, panel)
	r:SetSize(WIDTH - 12, ROW_H)
	r:SetPoint("TOPLEFT", 6, -20 - (i - 1) * (ROW_H + 2))

	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()
	r.bg:SetColorTexture(1, 1, 1, 0.06)

	r.hpFill = r:CreateTexture(nil, "BORDER")
	r.hpFill:SetPoint("TOPLEFT")
	r.hpFill:SetPoint("BOTTOMLEFT")
	r.hpFill:SetColorTexture(1, 1, 1, 0.10)

	r.strip = r:CreateTexture(nil, "ARTWORK")
	r.strip:SetPoint("TOPLEFT")
	r.strip:SetPoint("BOTTOMLEFT")
	r.strip:SetWidth(3)

	r.mark = r:CreateTexture(nil, "ARTWORK")
	r.mark:SetSize(12, 12)
	r.mark:SetPoint("LEFT", 7, 0)
	r.mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")

	r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.name:SetPoint("LEFT", 22, 0)
	r.name:SetPoint("RIGHT", -40, 0)
	r.name:SetJustifyH("LEFT")
	r.name:SetWordWrap(false)

	r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.right:SetPoint("RIGHT", -5, 0)
	r.right:SetJustifyH("RIGHT")

	r:Hide()
	rowFrames[i] = r
end

local function SetMark(tex, index)
	if type(index) == "number" and index >= 1 and index <= 8 then
		if SetRaidTargetIconTexture then
			SetRaidTargetIconTexture(tex, index)
		else
			local col = (index - 1) % 4
			local line = math.floor((index - 1) / 4)
			tex:SetTexCoord(col * 0.25, (col + 1) * 0.25, line * 0.25, (line + 1) * 0.25)
		end
		tex:Show()
	else
		tex:Hide()
	end
end

local function SetName(fs, unit)
	local ok, name = pcall(UnitName, unit)
	if ok and name ~= nil then
		-- A hidden (secret) name can still be shown by the client itself.
		if not pcall(fs.SetText, fs, name) then
			fs:SetText(T("Enemy"))
		end
	else
		fs:SetText(T("Enemy"))
	end
end

local unlocked = false

local function Render(rows)
	local onMe, loose = 0, 0
	for _, row in ipairs(rows) do
		if row.state == A.STATE_TANKING or row.state == A.STATE_LOSING then
			onMe = onMe + 1
		elseif row.state == A.STATE_LOOSE then
			loose = loose + 1
		end
	end
	if loose > 0 then
		counts:SetText(string.format("|cfff4c430%d|r %s  |cffff4538%d|r %s", onMe, T("on me"), loose, T("loose")))
	else
		counts:SetText(string.format("|cfff4c430%d|r %s", onMe, T("on me")))
	end

	local shown = math.min(#rows, MAX_ROWS)
	for i = 1, MAX_ROWS do
		local r, row = rowFrames[i], rows[i]
		if i <= shown then
			local c = COLORS[row.state]
			r.strip:SetColorTexture(c[1], c[2], c[3], 1)
			r.hpFill:SetWidth(math.max(1, (WIDTH - 12) * (row.hp or 0)))
			r.hpFill:SetShown(row.hp ~= nil)
			SetMark(r.mark, row.mark)
			r.name:SetPoint("LEFT", row.mark and 22 or 8, 0)
			if row.unit then
				SetName(r.name, row.unit)
			else
				r.name:SetText(row.label or "")
			end
			r.name:SetTextColor(c[1], c[2], c[3])
			if row.state == A.STATE_LOOSE and row.targetName then
				r.right:SetText("> " .. row.targetName)
				r.right:SetTextColor(1, 0.45, 0.4)
			elseif row.hp then
				r.right:SetText(string.format("%d%%", math.floor(row.hp * 100 + 0.5)))
				r.right:SetTextColor(0.8, 0.8, 0.8)
			else
				r.right:SetText("")
			end
			r:Show()
		else
			r:Hide()
		end
	end
	panel:SetHeight(24 + math.max(shown, 1) * (ROW_H + 2) - (shown == 0 and ROW_H or 0))
	return shown
end

local PREVIEW = {
	{ state = A.STATE_LOOSE, label = "Kobold Geomancer", hp = 0.8, mark = 8, targetName = "Healer" },
	{ state = A.STATE_LOSING, label = "Kobold Miner", hp = 0.55 },
	{ state = A.STATE_TANKING, label = "Kobold Tunneler", hp = 0.35, mark = 1 },
}

local function InCombat()
	return Read(UnitAffectingCombat, "player") or (InCombatLockdown and InCombatLockdown())
end

function A.Refresh()
	local d = DB()
	if not d then
		return
	end
	if unlocked then
		Render(PREVIEW)
		panel:Show()
		return
	end
	if not d.enabled then
		panel:Hide()
		return
	end
	local rows = A.Scan()
	local fighting = InCombat()
	if #rows == 0 and (d.onlyInCombat or not fighting) then
		panel:Hide()
		return
	end
	Render(rows)
	panel:Show()
end

local function ApplyPosition()
	local d = DB()
	if not d then
		return
	end
	panel:ClearAllPoints()
	panel:SetPoint("CENTER", UIParent, "CENTER", d.x, d.y)
end

function A.SetLocked(locked)
	unlocked = not locked
	panel:SetMovable(unlocked)
	panel:EnableMouse(unlocked)
	if unlocked then
		panel:RegisterForDrag("LeftButton")
	end
	A.Refresh()
end

panel:SetScript("OnDragStart", function(self)
	if unlocked then
		self:StartMoving()
	end
end)
panel:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local d = DB()
	if d then
		local cx, cy = self:GetCenter()
		local ux, uy = UIParent:GetCenter()
		local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
		d.x = math.floor(cx * scale - ux + 0.5)
		d.y = math.floor(cy * scale - uy + 0.5)
		ApplyPosition()
	end
end)

------------------------------------------------------------------------
-- Updates
------------------------------------------------------------------------

local ticker = CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
	acc = acc + elapsed
	if acc < 0.2 then
		return
	end
	acc = 0
	A.Refresh()
end)
ticker:Hide()

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		ApplyPosition()
		local locked = true
		if type(BulwarkDB) == "table" and BulwarkDB.locked == false then
			locked = false
		end
		A.SetLocked(locked)
		ticker:Show()
		return
	end
	A.Refresh()
end)
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(events.RegisterEvent, events, "NAME_PLATE_UNIT_ADDED")
pcall(events.RegisterEvent, events, "NAME_PLATE_UNIT_REMOVED")
pcall(events.RegisterEvent, events, "UNIT_THREAT_LIST_UPDATE")

-- Follow /bulwark lock and unlock.
if _G.Bulwark and _G.Bulwark.SetLocked and hooksecurefunc then
	hooksecurefunc(_G.Bulwark, "SetLocked", function(locked)
		A.SetLocked(locked and true or false)
	end)
end

------------------------------------------------------------------------
-- Slash: /bulwark aggro, /bulwark aggrocombat
------------------------------------------------------------------------

local previous = SlashCmdList and SlashCmdList.BULWARK
if previous then
	SlashCmdList.BULWARK = function(msg)
		local cmd = string.lower(msg or ""):match("^(%S+)") or ""
		local d = DB()
		if cmd == "aggro" and d then
			d.enabled = not d.enabled
			print(PREFIX .. T("aggro list:"), d.enabled and T("on") or T("off"))
			A.Refresh()
			return
		elseif cmd == "aggrocombat" and d then
			d.onlyInCombat = not d.onlyInCombat
			print(PREFIX .. T("aggro list only in combat:"), d.onlyInCombat and T("on") or T("off"))
			A.Refresh()
			return
		end
		previous(msg)
		if cmd == "" or cmd == "help" then
			print(T("  |cffaaaaaa/bulwark|r aggro | aggrocombat"))
		end
	end
end
