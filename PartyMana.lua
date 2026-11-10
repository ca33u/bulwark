--[[
  Bulwark: low mana in the party.

  When a party member who uses mana drops under the threshold (30 % by
  default), a red, softly pulsing overlay lies over their mana bar on the
  game's party frames. The overlay is Bulwark's own frame, only anchored to
  the Blizzard bar, so the protected party frames are never touched.

  Dead and offline members are skipped. If WoW Forever hides a member's mana
  (secret values, e.g. in combat), there is no overlay rather than a guess.

  /bulwark lowmana        turn it on or off
  /bulwark lowmana 25     set the threshold in percent (5-90)
  /bulwark manadebug      what Bulwark sees for each party member
]]

local ADDON_NAME, ns = ...
ns = ns or {}
local T = ns.T or function(text)
	return text
end

local M = {}
ns.PartyMana = M

local PREFIX = "|cfff4c430Bulwark|r "
local MANA = 0 -- Enum.PowerType.Mana

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

local function Field(tbl, key)
	if type(tbl) ~= "table" or IsSecret(tbl) then
		return nil
	end
	local ok, value = pcall(function()
		return tbl[key]
	end)
	if not ok or IsSecret(value) then
		return nil
	end
	return value
end

------------------------------------------------------------------------
-- Pure logic (tests/partymana_test.lua)
------------------------------------------------------------------------

-- Mana fraction 0..1 for a mana user, nil when not a mana user, dead,
-- offline, or the numbers are hidden.
function M.ManaFraction(unit)
	if not Read(UnitExists, unit) then
		return nil
	end
	if Read(UnitIsDeadOrGhost, unit) or Read(UnitIsConnected, unit) == false then
		return nil
	end
	local ptype = Read(UnitPowerType, unit)
	if ptype ~= MANA then
		return nil
	end
	local cur = Read(UnitPower, unit, MANA)
	local max = Read(UnitPowerMax, unit, MANA)
	if type(cur) ~= "number" or type(max) ~= "number" or max <= 0 then
		return nil
	end
	return cur / max
end

function M.IsLow(fraction, threshold)
	return type(fraction) == "number" and fraction < (threshold or 30) / 100
end

-- Why a unit is or is not highlighted (for /bulwark manadebug).
function M.Explain(unit)
	if not Read(UnitExists, unit) then
		return "no unit"
	end
	if Read(UnitIsDeadOrGhost, unit) then
		return "dead"
	end
	if Read(UnitIsConnected, unit) == false then
		return "offline"
	end
	local okT, ptype = pcall(UnitPowerType, unit)
	if not okT then
		return "power type: error"
	end
	if IsSecret(ptype) then
		return "power type hidden by the game"
	end
	if ptype ~= MANA then
		return "not a mana user (power type " .. tostring(ptype) .. ")"
	end
	local okC, cur = pcall(UnitPower, unit, MANA)
	local okM, max = pcall(UnitPowerMax, unit, MANA)
	if not okC or not okM then
		return "mana: error"
	end
	if IsSecret(cur) or IsSecret(max) then
		return "mana hidden by the game (secret value)"
	end
	if type(max) ~= "number" or max <= 0 then
		return "mana max " .. tostring(max)
	end
	return string.format("mana %d/%d = %d%%", cur, max, math.floor(cur / max * 100 + 0.5))
end

-- The mana bar inside a party frame, whatever this client calls it.
function M.ManaBarOf(frame)
	for _, key in ipairs({ "manabar", "ManaBar", "powerBar", "PowerBar" }) do
		local bar = Field(frame, key)
		if type(bar) == "table" then
			return bar
		end
	end
	local ok, name = pcall(function()
		return frame:GetName()
	end)
	if ok and type(name) == "string" and not IsSecret(name) then
		local bar = _G[name .. "ManaBar"]
		if type(bar) == "table" then
			return bar
		end
	end
	return nil
end

------------------------------------------------------------------------
-- Overlays
------------------------------------------------------------------------

local function DB()
	if type(BulwarkDB) ~= "table" then
		return nil
	end
	local d = BulwarkDB.lowMana
	if type(d) ~= "table" then
		d = {}
		BulwarkDB.lowMana = d
	end
	if d.enabled == nil then d.enabled = true end
	if d.threshold == nil then d.threshold = 30 end
	return d
end

local overlays = {} -- [blizzard frame] = overlay

local function OverlayFor(frame)
	local o = overlays[frame]
	if not o then
		o = CreateFrame("Frame", nil, UIParent)
		-- Above the party frames: at their strata the game's own bars were
		-- drawn over the overlay and hid it.
		o:SetFrameStrata("HIGH")
		o.fill = o:CreateTexture(nil, "OVERLAY")
		o.fill:SetAllPoints()
		o.fill:SetColorTexture(1, 0.1, 0.05, 0.45)
		o.edge = {}
		for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
			local e = o:CreateTexture(nil, "OVERLAY")
			e:SetColorTexture(1, 0.2, 0.15, 0.95)
			if side == "TOP" or side == "BOTTOM" then
				e:SetPoint(side .. "LEFT")
				e:SetPoint(side .. "RIGHT")
				e:SetHeight(1)
			else
				e:SetPoint("TOP" .. side)
				e:SetPoint("BOTTOM" .. side)
				e:SetWidth(1)
			end
			o.edge[i] = e
		end
		o:Hide()
		overlays[frame] = o
	end
	if o.anchoredTo ~= frame then
		o:ClearAllPoints()
		local bar = M.ManaBarOf(frame)
		if bar then
			o:SetAllPoints(bar)
		else
			-- No bar found: a strip along the bottom of the frame.
			o:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
			o:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
			o:SetHeight(8)
		end
		o.anchoredTo = frame
	end
	return o
end

local pulse = 0

function M.Refresh(elapsed)
	local d = DB()
	local find = ns.Blessings and ns.Blessings.PartyFrames
	if not d or not d.enabled or not find then
		for _, o in pairs(overlays) do
			o:Hide()
		end
		return
	end
	pulse = (pulse + (elapsed or 0) * 3) % (2 * math.pi)
	local alpha = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(pulse))
	local used = {}
	for _, entry in ipairs(find()) do
		if M.IsLow(M.ManaFraction(entry.unit), d.threshold) then
			local o = OverlayFor(entry.frame)
			o:SetAlpha(alpha)
			o:Show()
			used[o] = true
		end
	end
	for _, o in pairs(overlays) do
		if not used[o] then
			o:Hide()
		end
	end
end

local ticker = CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
	acc = acc + elapsed
	if acc < 0.05 then
		return
	end
	M.Refresh(acc)
	acc = 0
end)

------------------------------------------------------------------------
-- Slash: /bulwark lowmana [n]
------------------------------------------------------------------------

local previous = SlashCmdList and SlashCmdList.BULWARK
if previous then
	SlashCmdList.BULWARK = function(msg)
		local cmd, rest = string.lower(msg or ""):match("^(%S*)%s*(.-)$")
		local d = DB()
		if cmd == "manadebug" then
			local find = ns.Blessings and ns.Blessings.PartyFrames
			local list = find and find() or {}
			print(PREFIX .. string.format(T("party frames found: %d"), #list) .. ", " .. T("low mana highlight:") .. " " .. ((d and d.enabled) and T("on") or T("off")) .. string.format(" (<%d%%)", d and d.threshold or 30))
			for _, e in ipairs(list) do
				local okN, name = pcall(UnitName, e.unit)
				local bar = M.ManaBarOf(e.frame)
				print(string.format("  %s (%s): %s; bar: %s", tostring(okN and not IsSecret(name) and name or "?"), e.unit, M.Explain(e.unit), bar and "found" or "not found"))
			end
			return
		elseif cmd == "lowmana" and d then
			local n = tonumber(rest)
			if n then
				d.threshold = math.min(90, math.max(5, math.floor(n)))
				d.enabled = true
				print(PREFIX .. string.format(T("low mana highlight under %d%%"), d.threshold))
			else
				d.enabled = not d.enabled
				print(PREFIX .. T("low mana highlight:"), d.enabled and T("on") or T("off"))
			end
			return
		end
		previous(msg)
		if cmd == "" or cmd == "help" then
			print(T("  |cffaaaaaa/bulwark|r lowmana [percent] | manadebug"))
		end
	end
end
