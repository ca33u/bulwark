--[[
  Bulwark: party blessings.

  Shows the long paladin blessings on each party member and how many minutes
  are left, as small icons right next to the game's party frames. A separate
  panel with one row per member is also available (/bulwark blessingspanel).
    gold icon border  - your blessing
    grey icon border  - another paladin's blessing
    red cross         - no blessing at all (red row in the panel)
    yellow time       - under 1 minute left
    class icon        - the member's class, before the blessings
    grey icon + cross - no blessing; the grey icon is the one the class wants
                        (Might for warriors and rogues, Wisdom for the rest)
  Members who are dead, offline, or out of range are dimmed.

  WoW Forever can hide other units' auras in combat (secret values). Then the
  row keeps the last readable state and the timer keeps counting down from it.

  /bulwark blessings        turn the whole feature on or off
  /bulwark blessingsframes  icons next to the party frames (default on)
  /bulwark blessingspanel   the separate panel (default off)
  /bulwark blessingssolo    also show when you are not in a group
  /bulwark classicons       class icons before the blessings (default on)
  /bulwark blessingsdebug   list the party frames Bulwark found
  The panel moves with /bulwark unlock like the rest of Bulwark.
]]

local ADDON_NAME, ns = ...
ns = ns or {}
local T = ns.T or function(text)
	return text
end

local B = {}
ns.Blessings = B

local PREFIX = "|cfff4c430Bulwark|r "
local MAX_ROWS = 5
local ROW_H = 20
local ICON = 16
local WIDTH = 210

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
-- Pure logic (tests/blessings_test.lua)
------------------------------------------------------------------------

-- Short emergency blessings are not "the" blessing a member should keep.
local SHORT = {
	["blessing of protection"] = true,
	["blessing of freedom"] = true,
	["blessing of sacrifice"] = true,
}

function B.IsLongBlessing(name)
	if type(name) ~= "string" then
		return false
	end
	local n = name:lower()
	if SHORT[n] then
		return false
	end
	return n:find("^blessing of ") ~= nil or n:find("^greater blessing of ") ~= nil
end

-- auras: list of { name, icon, expires, mine }. Returns the blessings sorted
-- with yours first, and the row state: "mine", "other" or "none".
function B.Summarize(auras)
	local list = {}
	for _, a in ipairs(auras or {}) do
		if B.IsLongBlessing(a.name) then
			list[#list + 1] = a
		end
	end
	table.sort(list, function(x, y)
		if x.mine ~= y.mine then
			return x.mine and true or false
		end
		return (x.name or "") < (y.name or "")
	end)
	local state = "none"
	for _, a in ipairs(list) do
		if a.mine then
			state = "mine"
			break
		end
		state = "other"
	end
	return list, state
end

-- Which blessing a class wants. Classic rules: Might only helps melee attack
-- power (not ranged), so hunters and casters take Wisdom.
local MIGHT = { key = "might", spell = 19740, icon = 135906, name = "Blessing of Might" }
local WISDOM = { key = "wisdom", spell = 19742, icon = 135970, name = "Blessing of Wisdom" }
local WANTS = {
	WARRIOR = MIGHT,
	ROGUE = MIGHT,
	MAGE = WISDOM,
	WARLOCK = WISDOM,
	PRIEST = WISDOM,
	HUNTER = WISDOM,
	DRUID = WISDOM,
	SHAMAN = WISDOM,
	PALADIN = WISDOM,
}

-- Returns { key, spell, icon, name } or nil for an unknown class.
function B.Suggest(class)
	return WANTS[class]
end

-- Class icon coordinates on the character-create class sheet.
local CLASS_SHEET = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local CLASS_COORDS = {
	WARRIOR = { 0, 0.25, 0, 0.25 },
	MAGE = { 0.25, 0.49609375, 0, 0.25 },
	ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
	DRUID = { 0.7421875, 0.98828125, 0, 0.25 },
	HUNTER = { 0, 0.25, 0.25, 0.5 },
	SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
	PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 },
	WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
	PALADIN = { 0, 0.25, 0.5, 0.75 },
}

function B.ClassCoords(class)
	local t = type(CLASS_ICON_TCOORDS) == "table" and CLASS_ICON_TCOORDS[class]
	if type(t) == "table" and #t == 4 then
		return t
	end
	return CLASS_COORDS[class]
end

local function SuggestName(s)
	if C_Spell and C_Spell.GetSpellName then
		local ok, name = pcall(C_Spell.GetSpellName, s.spell)
		if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
			return name
		end
	end
	return T(s.name)
end

-- "12m", "45s"; nil when the buff has no end time.
function B.FormatLeft(expires, now)
	if type(expires) ~= "number" or expires <= 0 then
		return nil
	end
	local left = expires - now
	if left <= 0 then
		return "0s"
	end
	if left >= 60 then
		return string.format("%dm", math.floor(left / 60 + 0.5))
	end
	return string.format("%ds", math.floor(left))
end

------------------------------------------------------------------------
-- Reading auras
------------------------------------------------------------------------

local cache = {} -- [guid] = { auras = {...}, at = time }

local function ReadAuras(unit)
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
		return nil
	end
	local out = {}
	for i = 1, 40 do
		local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
		if not ok then
			return nil
		end
		if data == nil then
			break
		end
		if IsSecret(data) then
			return nil
		end
		local name = Field(data, "name")
		if name == nil then
			return nil -- hidden: keep the last readable state
		end
		local source = Field(data, "sourceUnit")
		out[#out + 1] = {
			name = name,
			icon = Field(data, "icon"),
			expires = Field(data, "expirationTime"),
			mine = type(source) == "string" and Read(UnitIsUnit, source, "player") and true or false,
		}
	end
	return out
end

local function Units()
	local units = { "player" }
	local n = Read(GetNumSubgroupMembers) or 0
	for i = 1, math.min(n, 4) do
		units[#units + 1] = "party" .. i
	end
	return units
end

function B.ReadClass(unit)
	if type(UnitClass) ~= "function" then
		return nil
	end
	local ok, _, class = pcall(UnitClass, unit)
	if not ok or IsSecret(class) or type(class) ~= "string" then
		return nil
	end
	return class
end

function B.Collect()
	local rows = {}
	for _, unit in ipairs(Units()) do
		if Read(UnitExists, unit) then
			local guid = Read(UnitGUID, unit) or unit
			local auras = ReadAuras(unit)
			local stale = false
			if auras then
				cache[guid] = { auras = auras }
			elseif cache[guid] then
				auras = cache[guid].auras
				stale = true
			else
				auras = {}
				stale = true
			end
			local list, state = B.Summarize(auras)
			local dim = Read(UnitIsDeadOrGhost, unit) or Read(UnitIsConnected, unit) == false
			if unit ~= "player" then
				local inRange = Read(UnitInRange, unit)
				if inRange == false then
					dim = true
				end
			end
			rows[#rows + 1] = {
				unit = unit,
				list = list,
				state = state,
				stale = stale,
				dim = dim and true or false,
				class = B.ReadClass(unit),
			}
		end
	end
	return rows
end

------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------

local function DB()
	if type(BulwarkDB) ~= "table" then
		return nil
	end
	local d = BulwarkDB.blessings
	if type(d) ~= "table" then
		d = {}
		BulwarkDB.blessings = d
	end
	if d.enabled == nil then d.enabled = true end
	if d.solo == nil then d.solo = false end
	if d.frames == nil then d.frames = true end -- icons next to the party frames
	if d.panel == nil then d.panel = false end  -- the separate panel
	if d.classIcons == nil then d.classIcons = true end -- class icon before the blessings
	if d.x == nil then d.x = -330 end
	if d.y == nil then d.y = -60 end
	return d
end

local panel = CreateFrame("Frame", "BulwarkBlessingsPanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
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
header:SetText(T("BLESSINGS"))
header:SetTextColor(0.96, 0.77, 0.19)

local summary = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
summary:SetPoint("TOPRIGHT", -8, -6)

local rowFrames = {}
for i = 1, MAX_ROWS do
	local r = CreateFrame("Frame", nil, panel)
	r:SetSize(WIDTH - 12, ROW_H)
	r:SetPoint("TOPLEFT", 6, -20 - (i - 1) * (ROW_H + 2))

	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()

	r.strip = r:CreateTexture(nil, "ARTWORK")
	r.strip:SetPoint("TOPLEFT")
	r.strip:SetPoint("BOTTOMLEFT")
	r.strip:SetWidth(3)

	r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.name:SetPoint("LEFT", 8, 0)
	r.name:SetWidth(84)
	r.name:SetJustifyH("LEFT")
	r.name:SetWordWrap(false)

	r.icons = {}
	for k = 1, 4 do
		local f = CreateFrame("Frame", nil, r)
		f:SetSize(ICON + 2, ICON + 2)
		f:SetPoint("LEFT", 94 + (k - 1) * (ICON + 8), 0)
		f.border = f:CreateTexture(nil, "BACKGROUND")
		f.border:SetAllPoints()
		f.tex = f:CreateTexture(nil, "ARTWORK")
		f.tex:SetPoint("TOPLEFT", 1, -1)
		f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
		f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		f.time = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		f.time:SetPoint("LEFT", f, "RIGHT", 1, 0)
		f.time:SetScale(0.8)
		f:Hide()
		r.icons[k] = f
	end

	r.none = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.none:SetPoint("LEFT", 94, 0)
	r.none:SetTextColor(1, 0.35, 0.3)

	r:Hide()
	rowFrames[i] = r
end

local function SetName(fs, unit, class)
	local ok, name = pcall(UnitName, unit)
	if not ok or name == nil or not pcall(fs.SetText, fs, name) then
		fs:SetText(unit)
	end
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then
		fs:SetTextColor(c.r, c.g, c.b)
	else
		fs:SetTextColor(0.9, 0.9, 0.9)
	end
end

local function Render(rows, now)
	local covered, mineCount = 0, 0
	local shown = math.min(#rows, MAX_ROWS)
	for i = 1, MAX_ROWS do
		local r, row = rowFrames[i], rows[i]
		if i <= shown then
			if row.state ~= "none" then
				covered = covered + 1
			end
			if row.state == "mine" then
				mineCount = mineCount + 1
			end
			if row.state == "none" then
				r.strip:SetColorTexture(1, 0.27, 0.22, 1)
				r.bg:SetColorTexture(1, 0.2, 0.15, 0.12)
			else
				r.strip:SetColorTexture(0.96, 0.77, 0.19, row.state == "mine" and 1 or 0.4)
				r.bg:SetColorTexture(1, 1, 1, 0.05)
			end
			if row.unit then
				SetName(r.name, row.unit, row.class)
			else
				r.name:SetText(row.label or "")
				r.name:SetTextColor(0.9, 0.9, 0.9)
			end
			for k = 1, 4 do
				local f, a = r.icons[k], row.list[k]
				if a then
					f.tex:SetTexture(a.icon or 134400)
					if a.mine then
						f.border:SetColorTexture(0.96, 0.77, 0.19, 1)
					else
						f.border:SetColorTexture(0.45, 0.45, 0.45, 1)
					end
					local left = B.FormatLeft(a.expires, now)
					f.time:SetText(left or "")
					if type(a.expires) == "number" and a.expires > 0 and a.expires - now < 60 then
						f.time:SetTextColor(1, 0.85, 0.2)
					else
						f.time:SetTextColor(0.85, 0.85, 0.85)
					end
					f:Show()
				else
					f:Hide()
				end
			end
			local text = ""
			if row.state == "none" then
				local want = B.Suggest(row.class)
				text = want and (T("no blessing") .. " > " .. SuggestName(want)) or T("no blessing")
			end
			r.none:SetText(text)
			r:SetAlpha((row.dim and 0.4 or 1) * (row.stale and 0.75 or 1))
			r:Show()
		else
			r:Hide()
		end
	end
	summary:SetText(string.format("%d/%d", covered, shown))
	panel:SetHeight(24 + shown * (ROW_H + 2))
end

local PREVIEW = {
	{ label = "Saz Zy", state = "mine", list = { { name = "Blessing of Might", icon = 135906, expires = 0, mine = true } } },
	{ label = "Healer", state = "other", list = { { name = "Blessing of Wisdom", icon = 135970, expires = 0, mine = false } } },
	{ label = "Rogue", state = "none", list = {} },
}

local unlocked = false

------------------------------------------------------------------------
-- Icons next to the game's party frames
------------------------------------------------------------------------

-- The frames are Blizzard's and protected. Bulwark never touches them: its
-- icon holders are children of UIParent that are only anchored to them.

local function FrameUnit(frame, fallback)
	local u = Field(frame, "unit")
	if type(u) == "string" then
		return u
	end
	if type(frame.GetAttribute) == "function" then
		local ok, a = pcall(frame.GetAttribute, frame, "unit")
		if ok and type(a) == "string" and not IsSecret(a) then
			return a
		end
	end
	return fallback
end

local function Visible(frame)
	if type(frame) ~= "table" then
		return false
	end
	-- Forbidden frames must not be touched at all (it raises the
	-- "blocked from an action" popup even inside pcall).
	if type(frame.IsForbidden) == "function" then
		local okF, forbidden = pcall(frame.IsForbidden, frame)
		if not okF or forbidden == true then
			return false
		end
	end
	if type(frame.IsVisible) ~= "function" then
		return false
	end
	local ok, v = pcall(frame.IsVisible, frame)
	return ok and v == true
end

-- Returns { {frame=, unit=}, ... } for the party frames that are on screen.
-- Raid-style party frames win when they are shown.
function B.PartyFrames()
	local out = {}
	for i = 1, 5 do
		local f = _G["CompactPartyFrameMember" .. i]
		if Visible(f) then
			local unit = FrameUnit(f, nil)
			if unit then
				out[#out + 1] = { frame = f, unit = unit, compact = true }
			end
		end
	end
	if #out > 0 then
		return out
	end
	for i = 1, 4 do
		local f = _G["PartyMemberFrame" .. i]
		if not f and type(_G.PartyFrame) == "table" then
			f = Field(_G.PartyFrame, "MemberFrame" .. i)
		end
		if Visible(f) then
			out[#out + 1] = { frame = f, unit = FrameUnit(f, "party" .. i) }
		end
	end
	return out
end

local holders = {} -- [blizzard frame] = holder

local CLASS_W = ICON + 6 -- class icon column before the blessings

local function MakeHolder()
	local h = CreateFrame("Frame", nil, UIParent)
	h:SetSize(CLASS_W + 4 * (ICON + 6), ICON + 14)
	h:SetFrameStrata("MEDIUM")

	-- Class icon with a class-coloured border.
	h.class = CreateFrame("Frame", nil, h)
	h.class:SetSize(ICON + 2, ICON + 2)
	h.class:SetPoint("TOPLEFT", 0, 0)
	h.class.border = h.class:CreateTexture(nil, "BACKGROUND")
	h.class.border:SetAllPoints()
	h.class.tex = h.class:CreateTexture(nil, "ARTWORK")
	h.class.tex:SetPoint("TOPLEFT", 1, -1)
	h.class.tex:SetPoint("BOTTOMRIGHT", -1, 1)
	h.class.tex:SetTexture(CLASS_SHEET)
	h.class:Hide()

	h.icons = {}
	for k = 1, 4 do
		local f = CreateFrame("Frame", nil, h)
		f:SetSize(ICON + 2, ICON + 2)
		f:SetPoint("TOPLEFT", CLASS_W + (k - 1) * (ICON + 6), 0)
		f.border = f:CreateTexture(nil, "BACKGROUND")
		f.border:SetAllPoints()
		f.tex = f:CreateTexture(nil, "ARTWORK")
		f.tex:SetPoint("TOPLEFT", 1, -1)
		f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
		f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		f.time = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		f.time:SetPoint("TOP", f, "BOTTOM", 0, -1)
		f.time:SetScale(0.75)
		f:Hide()
		h.icons[k] = f
	end
	-- Red cross (the game's ready-check "not ready" icon) when there is no blessing.
	h.missing = h:CreateTexture(nil, "OVERLAY")
	h.missing:SetSize(ICON, ICON)
	h.missing:SetPoint("TOPLEFT", CLASS_W + 1, -1)
	h.missing:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
	h.missing:Hide()
	-- The blessing this class wants, greyed, under a small red cross.
	h.want = h:CreateTexture(nil, "ARTWORK")
	h.want:SetSize(ICON, ICON)
	h.want:SetPoint("TOPLEFT", CLASS_W + 1, -1)
	h.want:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	h.want:Hide()
	h:Hide()
	return h
end

local function HolderFor(entry)
	local h = holders[entry.frame]
	if not h then
		h = MakeHolder()
		holders[entry.frame] = h
	end
	if h.anchoredTo ~= entry.frame then
		h:ClearAllPoints()
		if entry.compact then
			h:SetPoint("BOTTOMLEFT", entry.frame, "BOTTOMRIGHT", 4, 2)
		else
			h:SetPoint("LEFT", entry.frame, "RIGHT", 2, 2)
		end
		h.anchoredTo = entry.frame
	end
	return h
end

local function PaintClass(h, class)
	local coords = B.ClassCoords(class)
	if not coords or not (BulwarkDB and BulwarkDB.blessings and BulwarkDB.blessings.classIcons ~= false) then
		h.class:Hide()
		return
	end
	h.class.tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then
		h.class.border:SetColorTexture(c.r, c.g, c.b, 1)
	else
		h.class.border:SetColorTexture(0, 0, 0, 1)
	end
	h.class:Show()
end

local function PaintHolder(h, row, now)
	for k = 1, 4 do
		local f, a = h.icons[k], row.list[k]
		if a then
			f.tex:SetTexture(a.icon or 134400)
			if a.mine then
				f.border:SetColorTexture(0.96, 0.77, 0.19, 1)
			else
				f.border:SetColorTexture(0.45, 0.45, 0.45, 1)
			end
			f.time:SetText(B.FormatLeft(a.expires, now) or "")
			if type(a.expires) == "number" and a.expires > 0 and a.expires - now < 60 then
				f.time:SetTextColor(1, 0.85, 0.2)
			else
				f.time:SetTextColor(0.9, 0.9, 0.9)
			end
			f:Show()
		else
			f:Hide()
		end
	end
	PaintClass(h, row.class)
	local want = row.state == "none" and B.Suggest(row.class)
	if want then
		h.want:SetTexture(want.icon)
		if h.want.SetDesaturated then
			h.want:SetDesaturated(true)
		end
		h.want:SetVertexColor(0.8, 0.8, 0.8)
		h.want:Show()
		h.missing:ClearAllPoints()
		h.missing:SetSize(ICON * 0.7, ICON * 0.7)
		h.missing:SetPoint("BOTTOMRIGHT", h.want, "BOTTOMRIGHT", 4, -4)
	else
		h.want:Hide()
		h.missing:ClearAllPoints()
		h.missing:SetSize(ICON, ICON)
		h.missing:SetPoint("TOPLEFT", CLASS_W + 1, -1)
	end
	h.missing:SetShown(row.state == "none")
	h:SetAlpha((row.dim and 0.4 or 1) * (row.stale and 0.75 or 1))
	h:Show()
end

local function HideHolders()
	for _, h in pairs(holders) do
		h:Hide()
	end
end

-- Returns how many party frames got icons.
local function RenderFrames(rows, now)
	local byUnit = {}
	for _, row in ipairs(rows) do
		byUnit[row.unit] = row
	end
	local used = {}
	local count = 0
	for _, entry in ipairs(B.PartyFrames()) do
		local row = byUnit[entry.unit]
		if not row then
			-- party frames can name the unit differently (e.g. "raid3")
			for _, r in ipairs(rows) do
				if Read(UnitIsUnit, r.unit, entry.unit) then
					row = r
					break
				end
			end
		end
		if row then
			local h = HolderFor(entry)
			PaintHolder(h, row, now)
			used[h] = true
			count = count + 1
		end
	end
	for _, h in pairs(holders) do
		if not used[h] then
			h:Hide()
		end
	end
	return count
end

function B.Refresh()
	local d = DB()
	if not d then
		return
	end
	local now = Read(GetTime) or 0
	if unlocked and d.panel then
		Render(PREVIEW, now)
		panel:Show()
		return
	end
	if not d.enabled then
		panel:Hide()
		HideHolders()
		return
	end
	local inGroup = (Read(GetNumSubgroupMembers) or 0) > 0
	if not inGroup and not d.solo then
		panel:Hide()
		HideHolders()
		return
	end
	local rows = B.Collect()
	if d.frames then
		RenderFrames(rows, now)
	else
		HideHolders()
	end
	if d.panel then
		Render(rows, now)
		panel:Show()
	else
		panel:Hide()
	end
end

local function ApplyPosition()
	local d = DB()
	if not d then
		return
	end
	panel:ClearAllPoints()
	panel:SetPoint("CENTER", UIParent, "CENTER", d.x, d.y)
end

function B.SetLocked(locked)
	unlocked = not locked
	panel:SetMovable(unlocked)
	panel:EnableMouse(unlocked)
	if unlocked then
		panel:RegisterForDrag("LeftButton")
	end
	B.Refresh()
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
	if acc < 0.5 then
		return
	end
	acc = 0
	B.Refresh()
end)
ticker:Hide()

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		ApplyPosition()
		B.SetLocked(not (type(BulwarkDB) == "table" and BulwarkDB.locked == false))
		ticker:Show()
		return
	end
	B.Refresh()
end)
events:RegisterEvent("PLAYER_LOGIN")
pcall(events.RegisterEvent, events, "GROUP_ROSTER_UPDATE")

if _G.Bulwark and _G.Bulwark.SetLocked and hooksecurefunc then
	hooksecurefunc(_G.Bulwark, "SetLocked", function(locked)
		B.SetLocked(locked and true or false)
	end)
end

------------------------------------------------------------------------
-- Slash
------------------------------------------------------------------------

local previous = SlashCmdList and SlashCmdList.BULWARK
if previous then
	SlashCmdList.BULWARK = function(msg)
		local cmd = string.lower(msg or ""):match("^(%S+)") or ""
		local d = DB()
		if cmd == "blessings" and d then
			d.enabled = not d.enabled
			print(PREFIX .. T("party blessings:"), d.enabled and T("on") or T("off"))
			B.Refresh()
			return
		elseif cmd == "blessingspanel" and d then
			d.panel = not d.panel
			print(PREFIX .. T("party blessings panel:"), d.panel and T("on") or T("off"))
			B.Refresh()
			return
		elseif cmd == "blessingsframes" and d then
			d.frames = not d.frames
			print(PREFIX .. T("blessing icons on party frames:"), d.frames and T("on") or T("off"))
			B.Refresh()
			return
		elseif cmd == "blessingsdebug" then
			local list = B.PartyFrames()
			print(PREFIX .. string.format(T("party frames found: %d"), #list))
			for _, e in ipairs(list) do
				local ok, name = pcall(e.frame.GetName, e.frame)
				print("  " .. tostring(ok and name or "?") .. " -> " .. tostring(e.unit))
			end
			return
		elseif cmd == "classicons" and d then
			d.classIcons = not d.classIcons
			print(PREFIX .. T("class icons on party frames:"), d.classIcons and T("on") or T("off"))
			B.Refresh()
			return
		elseif cmd == "blessingssolo" and d then
			d.solo = not d.solo
			print(PREFIX .. T("party blessings when solo:"), d.solo and T("on") or T("off"))
			B.Refresh()
			return
		end
		previous(msg)
		if cmd == "" or cmd == "help" then
			print(T("  |cffaaaaaa/bulwark|r blessings | blessingsframes | blessingspanel | blessingssolo | classicons | blessingsdebug"))
		end
	end
end
