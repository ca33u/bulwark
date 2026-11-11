--[[
  Bulwark core: options window (/bulwark options, minimap click, addon list).

  Classic Warcraft dialog look (the game's dialog border and header plate,
  red panel buttons, standard check boxes), same as FastLoot's window.

  Tabs, by what you want to change:
    General    lock, minimap button, preview, reset, spell check,
               VISIBILITY matrix (only in combat / hide when ...) for every
               part, about
    Line       the duration line: look, icons, colors, which buffs
    Abilities  the ability icons: layout, which abilities
    Reminders  which reminders, their look and color
    Swing      the swing timer rail
    Windows    mitigation window, tank readiness window
  Every control writes BulwarkDB and applies at once.
]]

local ADDON_NAME, ns = ...
ns = ns or {}
local G, S, W, T = ns.G, ns.Spells, ns.W, ns.T

local O = {}
ns.Options = O

local WIDTH, HEIGHT = 640, 690
local PAD = 22                -- room for the dialog border
local COLX = { PAD, 334 }     -- two columns
local COLW = 286              -- column width
local TOP = -6

local win = CreateFrame("Frame", "BulwarkOptions", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
win:SetSize(WIDTH, HEIGHT)
win:SetPoint("CENTER", 0, 40)
win:SetFrameStrata("DIALOG")
win:SetClampedToScreen(true)
win:SetMovable(true)
win:EnableMouse(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", win.StopMovingOrSizing)
if win.SetBackdrop then
	win:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	win:SetBackdropColor(1, 1, 1, 0.95)
else
	W.Panel(win, 0.94)
end
win:Hide()
O.frame = win
if type(UISpecialFrames) == "table" then
	table.insert(UISpecialFrames, "BulwarkOptions") -- Esc closes it
end

-- Title on the classic dialog header plate.
local header = win:CreateTexture(nil, "ARTWORK")
header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
header:SetSize(300, 64)
header:SetPoint("TOP", 0, 12)
local title = W.Text(win, "GameFontNormal")
title:SetPoint("TOP", header, "TOP", 0, -14)
title:SetText("Bulwark")

local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -5, -5)

local footer = W.Text(win, "GameFontDisableSmall")
footer:SetPoint("BOTTOMLEFT", PAD, 16)
footer:SetText(string.format("Bulwark %s  ·  %s addicted  ·  %s MIT  · ", ns.VERSION, T("by"), T("license")))
local footerLink = W.Link(win, ns.WEBSITE, ns.WEBSITE_URL)
footerLink:SetPoint("LEFT", footer, "RIGHT", 2, 0)

------------------------------------------------------------------------
-- Controls in the game's own style
------------------------------------------------------------------------

local refreshers = {}

local function Changed()
	if O.Changed then
		O.Changed()
	end
end

-- The game's red panel button.
local function RedButton(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 140, 22)
	b:SetText(text)
	if onClick then
		b:SetScript("OnClick", onClick)
	end
	return b
end

-- The game's check box with a label; get() -> bool, set(bool).
local function CheckBox(parent, label, get, set)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(22, 22)
	cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	cb.label:SetJustifyH("LEFT")
	cb.label:SetText(label or "")
	function cb.Refresh()
		cb:SetChecked(get() and true or false)
	end
	cb:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
		Changed()
	end)
	cb.Refresh()
	refreshers[#refreshers + 1] = cb.Refresh
	return cb
end

------------------------------------------------------------------------
-- Pages and layout
------------------------------------------------------------------------

local pages, tabs, order = {}, {}, {}

local function NewPage(id, label)
	local p = CreateFrame("Frame", nil, win)
	p:SetPoint("TOPLEFT", 0, -64)
	p:SetPoint("BOTTOMRIGHT", 0, 36)
	p:Hide()
	p.y = { TOP, TOP }
	p.id = id
	pages[id] = p
	order[#order + 1] = id
	local t = RedButton(win, label, 96, function()
		O.Show(id)
	end)
	t:SetPoint("TOPLEFT", PAD + (#order - 1) * 99, -30)
	tabs[id] = t
	return p
end

local function Add(p, col, widget, height, x)
	widget:SetPoint("TOPLEFT", p, "TOPLEFT", x or COLX[col], p.y[col])
	p.y[col] = p.y[col] - height
	if widget.Refresh then
		refreshers[#refreshers + 1] = widget.Refresh
	end
	return widget
end

-- A gold header with a thin rule. col = 1 or 2 for one column, nil for the
-- full width below whatever is lowest.
local function Section(p, text, col)
	local x, y, right
	if col then
		x, y = COLX[col], p.y[col] - 4
		right = COLX[col] + COLW
	else
		x, y = COLX[1], math.min(p.y[1], p.y[2]) - 8
		right = WIDTH - PAD
	end
	local fs = W.Text(p, "GameFontNormalSmall")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetText(text)
	-- Thin gold underline from the header to the end of its column.
	local rule = p:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(1, 0.82, 0, 0.22)
	rule:SetSize(right - x, 1)
	rule:SetPoint("TOPLEFT", p, "TOPLEFT", x, y - 13)
	if col then
		p.y[col] = y - 18
	else
		p.y[1], p.y[2] = y - 18, y - 18
	end
	return fs
end

local function Note(p, col, text, height)
	local fs = W.Text(p, "GameFontDisableSmall")
	fs:SetWidth(col and COLW or (WIDTH - 2 * PAD))
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	if col then
		return Add(p, col, fs, height or 28)
	end
	local y = math.min(p.y[1], p.y[2]) - 2
	fs:SetPoint("TOPLEFT", p, "TOPLEFT", COLX[1], y)
	p.y[1], p.y[2] = y - (height or 18), y - (height or 18)
	return fs
end

local function DB()
	return ns.DB()
end

local function CheckKey(p, col, key, label, after)
	return Add(p, col, CheckBox(p, label, function()
		return DB()[key]
	end, function(v)
		DB()[key] = v
		if after then
			after(v)
		end
	end), 22, COLX[col] - 4)
end

local function SliderKey(p, col, key, label, min, max, step, fmt)
	local s = W.Slider(p, label, min, max, step, function()
		return DB()[key]
	end, function(v)
		DB()[key] = v
	end, fmt)
	s:SetWidth(COLW - 10)
	return Add(p, col, s, 38)
end

local function CycleKey(p, col, key, label, choices, after)
	local c = W.Cycle(p, label, choices, function()
		return DB()[key]
	end, function(v)
		DB()[key] = v
		if after then
			after(v)
		end
	end)
	c:SetWidth(COLW - 10)
	return Add(p, col, c, 40)
end

local function ButtonAt(p, col, text, width, onClick)
	return Add(p, col, RedButton(p, text, width or 160, onClick), 28)
end

-- A grid of check boxes over the full width (3 columns).
local function CheckGrid(p, keys, get, set, labelOf)
	local y = math.min(p.y[1], p.y[2])
	for i, key in ipairs(keys) do
		local col = (i - 1) % 3
		local row = math.floor((i - 1) / 3)
		local c = CheckBox(p, labelOf(key), function()
			return get(key)
		end, function(v)
			set(key, v)
		end)
		c:SetPoint("TOPLEFT", p, "TOPLEFT", COLX[1] - 4 + col * 200, y - row * 22)
	end
	local rows = math.ceil(#keys / 3)
	p.y[1], p.y[2] = y - rows * 22, y - rows * 22
end


------------------------------------------------------------------------
-- General
------------------------------------------------------------------------

-- Visibility matrix: one row per part, one column per condition.
O.VISIBILITY_ROWS = {
	{ T("Duration line"), "barOnlyInCombat", "bar" },
	{ T("Ability icons"), "abilitiesOnlyInCombat", "icons" },
	{ T("Reminders"), "warningsOnlyInCombat", "warn" },
	{ T("Swing timer"), "swingOnlyInCombat", nil },
}
O.VISIBILITY_COLS = {
	{ T("Only in combat"), nil },
	{ T("Hide: flying"), "HideFlying" },
	{ T("resting"), "HideResting" },
	{ T("mounted"), "HideMounted" },
	{ T("dead"), "HideDead" },
}

do
	local p = NewPage("general", T("General"))

	Section(p, T("BULWARK"), 1)
	Add(p, 1, CheckBox(p, T("Lock position"), function()
		return DB().locked ~= false
	end, function(v)
		_G.Bulwark.SetLocked(v)
	end), 22, COLX[1] - 4)
	CheckKey(p, 1, "showMinimap", T("Minimap button"))
	Note(p, 1, T("Unlocked: drag the line, icons, reminders and panels. Wheel on the line = scale, Shift = width, Alt = thickness."), 40)

	Section(p, T("TOOLS"), 2)
	ButtonAt(p, 2, T("Preview (12 s)"), 180, function()
		ns.Movers.StartTest()
	end)
	ButtonAt(p, 2, T("Reset positions"), 180, function()
		ns.Movers.Reset()
		O.Refresh()
	end)
	ButtonAt(p, 2, T("Spell check"), 180, function()
		ns.Reminders.SpellCheck()
	end)
	ButtonAt(p, 2, T("Readiness window"), 180, function()
		ns.Prep.Toggle()
	end)

	Section(p, T("VISIBILITY"))
	local y = p.y[1]
	local labelW, colW = 128, 92
	for c, colInfo in ipairs(O.VISIBILITY_COLS) do
		local h = W.Text(p, "GameFontNormalSmall")
		h:SetPoint("TOPLEFT", p, "TOPLEFT", COLX[1] + labelW + (c - 1) * colW, y)
		h:SetWidth(colW)
		h:SetJustifyH("LEFT")
		h:SetText(colInfo[1])
	end
	y = y - 16
	for r, rowInfo in ipairs(O.VISIBILITY_ROWS) do
		local name = W.Text(p, "GameFontHighlightSmall")
		name:SetPoint("TOPLEFT", p, "TOPLEFT", COLX[1], y - (r - 1) * 24 - 4)
		name:SetText(rowInfo[1])
		for c, colInfo in ipairs(O.VISIBILITY_COLS) do
			local key
			if c == 1 then
				key = rowInfo[2]
			elseif rowInfo[3] then
				key = rowInfo[3] .. colInfo[2]
			end
			if key then
				local cb = CheckBox(p, "", function()
					return DB()[key]
				end, function(v)
					DB()[key] = v
				end)
				cb:SetPoint("TOPLEFT", p, "TOPLEFT", COLX[1] + labelW + (c - 1) * colW + 8, y - (r - 1) * 24)
			end
		end
	end
	p.y[1], p.y[2] = y - #O.VISIBILITY_ROWS * 24 - 4, y - #O.VISIBILITY_ROWS * 24 - 4
	Note(p, nil, T("The swing timer has no hide options of its own: it follows auto attack."), 16)

	Section(p, T("ABOUT"))
	local about = Note(p, nil, string.format("|cfff4c430Bulwark|r %s  ·  %s |cffffffffaddicted|r  ·  %s MIT  · ", ns.VERSION, T("by"), T("license")), 18)
	about:SetWidth(0)
	local link = W.Link(p, ns.WEBSITE, ns.WEBSITE_URL)
	link:SetPoint("LEFT", about, "RIGHT", 2, 0)
	Note(p, nil, T("Type /bulwark for the list of commands. /bulwark unlock to move things, /bulwark test for a preview."), 30)
end

------------------------------------------------------------------------
-- Line: size and what the icons on it show. Colours and style are the
-- addicted look (gold to red); positions are set by dragging.
------------------------------------------------------------------------

do
	local p = NewPage("bar", T("Line"))

	Section(p, T("SIZE"), 1)
	SliderKey(p, 1, "width", T("Width"), 200, 800, 10)
	SliderKey(p, 1, "lineHeight", T("Thickness"), 2, 24, 1)
	SliderKey(p, 1, "scale", T("Scale"), 0.6, 2, 0.05)
	SliderKey(p, 1, "iconSize", T("Icon size"), 12, 48, 1)

	Section(p, T("ICONS ON THE LINE"), 2)
	CheckKey(p, 2, "showTimers", T("Seconds under icons"))
	CheckKey(p, 2, "showNames", T("Spell names under icons"))
	CheckKey(p, 2, "flashSoon", T("Flash before a buff ends"))
	CheckKey(p, 2, "rfLastOnly", T("Righteous Fury only in its last 30 s"))

	Section(p, T("BUFFS ON THE LINE"))
	CheckGrid(p, S.LINE, ns.IsTracked, function(key, v)
		DB().tracked[key] = v
	end, S.DisplayName)
end

------------------------------------------------------------------------
-- Reminders
------------------------------------------------------------------------

do
	local p = NewPage("warnings", T("Reminders"))

	Section(p, T("WHAT TO REMIND"), 1)
	CheckKey(p, 1, "warnRighteousFury", T("Righteous Fury missing"))
	CheckKey(p, 1, "warnSeal", T("Seal missing"))
	CheckKey(p, 1, "warnDevotion", T("No aura active"))
	CheckKey(p, 1, "warnBlessing", T("No blessing on yourself"))
	CheckKey(p, 1, "warnForbearance", T("Forbearance"))
	CheckKey(p, 1, "soundSealDrop", T("Sound when Seal of Fury drops in combat"))

	Section(p, T("SIZE"), 2)
	SliderKey(p, 2, "warnSize", T("Icon size"), 8, 40, 1)
	Note(p, 2, T("Reminders sit above the line, abilities under it. Drag them in /bulwark unlock."), 40)

	Note(p, nil, T("Reminders appear only when Bulwark is sure: a value the game hides never creates one."), 18)
end

------------------------------------------------------------------------
-- Abilities
------------------------------------------------------------------------

do
	local p = NewPage("abilities", T("Abilities"))

	Section(p, T("SIZE"), 1)
	SliderKey(p, 1, "readyIconSize", T("Icon size"), 12, 64, 1)

	Section(p, T("ABILITIES TO SHOW"))
	CheckGrid(p, S.READY, ns.IsReadyShown, function(key, v)
		DB().readyCDs[key] = v
	end, S.DisplayName)
	Note(p, nil, T("An icon appears only when you know the ability. Forbearance shows immunities as locked."), 18)
end

------------------------------------------------------------------------
-- More: swing timer, mitigation window, readiness
------------------------------------------------------------------------

do
	local p = NewPage("more", T("More"))

	Section(p, T("SWING TIMER"), 1)
	CheckKey(p, 1, "showSwing", T("Show the swing timer"))
	CheckKey(p, 1, "swingShowTime", T("Seconds to the next swing"))
	CheckKey(p, 1, "swingParryHaste", T("Parry haste"))
	Note(p, 1, T("Weapon speed is read out of combat and cached. Parry haste: a parry cuts the wait by 40% of the weapon speed, never below 20%."), 56)

	Section(p, T("MITIGATION STATS"), 2)
	CheckKey(p, 2, "showMitigation", T("Show the mitigation window"))
	CycleKey(p, 2, "mitigLevelDiff", T("Target level"), {
		{ 3, T("Raid boss (+3)") }, { 2, "+2" }, { 1, "+1" }, { 0, T("Same level") },
	})

	Section(p, T("TANK READINESS"), 2)
	Note(p, 2, T("A checklist before a pull: Righteous Fury, seal, aura, blessings, group buffs, weapon, shield, enchants, food and flasks."), 42)
	ButtonAt(p, 2, T("Readiness window"), 180, function()
		ns.Prep.Toggle()
	end)
end

------------------------------------------------------------------------
-- Showing
------------------------------------------------------------------------

-- Old tab names still open the right page.
local ALIAS = { about = "general", mitigation = "more", windows = "more", swing = "more" }

function O.Refresh()
	for _, fn in ipairs(refreshers) do
		pcall(fn)
	end
end

function O.Show(id)
	id = ALIAS[id] or id
	id = pages[id] and id or O.current or "general"
	O.current = id
	for pid, p in pairs(pages) do
		p:SetShown(pid == id)
		local t = tabs[pid]
		if pid == id then
			t:LockHighlight()
		else
			t:UnlockHighlight()
		end
	end
	O.Refresh()
end

function O.Open(tab)
	win:Show()
	O.Show(tab)
end

function O.Toggle()
	if win:IsShown() then
		win:Hide()
	else
		O.Open()
	end
end

-- Called by every control after it wrote BulwarkDB.
function O.Changed()
	if ns.ApplyAll then
		ns.ApplyAll()
	end
end

------------------------------------------------------------------------
-- Entry in the game's addon options list (guarded; optional)
------------------------------------------------------------------------

local function RegisterAddonList()
	local panel = CreateFrame("Frame", "BulwarkSettingsPanel", UIParent)
	panel.name = "Bulwark"
	panel:Hide()
	local label = W.Text(panel, "GameFontNormalLarge")
	label:SetPoint("TOPLEFT", 16, -16)
	label:SetText("|cfff4c430Bulwark|r " .. ns.VERSION)
	local open = RedButton(panel, T("Open Bulwark options"), 200, function()
		O.Open()
	end)
	open:SetPoint("TOPLEFT", 16, -48)
	local settings = _G.Settings
	if type(settings) == "table" and type(settings.RegisterCanvasLayoutCategory) == "function" then
		local ok, category = pcall(settings.RegisterCanvasLayoutCategory, panel, "Bulwark")
		if ok and category then
			pcall(settings.RegisterAddOnCategory, category)
			return
		end
	end
	G.Call(_G.InterfaceOptions_AddCategory, panel)
end

ns.On("PLAYER_LOGIN", function()
	pcall(RegisterAddonList)
end)
