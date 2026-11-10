--[[
  Bulwark core: small UI building blocks in the flat Bulwark style.

  Everything is built from plain textures (Interface\Buttons\WHITE8x8) on
  Bulwark's own frames, all children of UIParent. No Blizzard templates
  are required and no Blizzard frame is touched (Bulwark even has its own
  tooltip instead of driving GameTooltip).
]]

local ADDON_NAME, ns = ...
ns = ns or {}
local G = ns.G
local T = ns.T

local W = {}
ns.W = W

W.WHITE = "Interface\\Buttons\\WHITE8x8"
W.FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

-- Dark flat panel with a 1 px black border (textures, no backdrop needed).
function W.Panel(frame, alpha, r, g, b)
	if frame.bulwarkPanel then
		frame.bulwarkPanel.bg:SetColorTexture(r or 0.05, g or 0.05, b or 0.07, alpha or 0.85)
		return frame
	end
	local p = {}
	p.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	p.bg:SetAllPoints()
	p.bg:SetColorTexture(r or 0.05, g or 0.05, b or 0.07, alpha or 0.85)
	p.edges = {}
	for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local e = frame:CreateTexture(nil, "BORDER", nil, -8)
		e:SetColorTexture(0, 0, 0, 0.9)
		if side == "TOP" or side == "BOTTOM" then
			e:SetPoint(side .. "LEFT")
			e:SetPoint(side .. "RIGHT")
			e:SetHeight(1)
		else
			e:SetPoint("TOP" .. side)
			e:SetPoint("BOTTOM" .. side)
			e:SetWidth(1)
		end
		p.edges[i] = e
	end
	frame.bulwarkPanel = p
	return frame
end

function W.Text(parent, template, size, flags)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
	if size then
		W.SetFontSize(fs, size, flags)
	end
	return fs
end

function W.SetFontSize(fs, size, flags)
	if not G.Call(fs.SetFont, fs, W.FONT, size, flags or "OUTLINE") then
		G.Call(fs.SetFont, fs, "Fonts\\FRIZQT__.TTF", size, flags or "OUTLINE")
	end
end

-- Horizontal or vertical gradient, guarded for old and new clients.
function W.Gradient(tex, orientation, c1, c2)
	tex:SetTexture(W.WHITE)
	tex:SetVertexColor(1, 1, 1, 1)
	local ok = false
	if type(tex.SetGradient) == "function" and type(_G.CreateColor) == "function" then
		ok = pcall(tex.SetGradient, tex, orientation,
			_G.CreateColor(c1[1], c1[2], c1[3], c1[4] or 1),
			_G.CreateColor(c2[1], c2[2], c2[3], c2[4] or 1))
	end
	if not ok and type(tex.SetGradientAlpha) == "function" then
		ok = pcall(tex.SetGradientAlpha, tex, orientation,
			c1[1], c1[2], c1[3], c1[4] or 1, c2[1], c2[2], c2[3], c2[4] or 1)
	end
	if not ok then
		tex:SetColorTexture((c1[1] + c2[1]) / 2, (c1[2] + c2[2]) / 2, (c1[3] + c2[3]) / 2,
			((c1[4] or 1) + (c2[4] or 1)) / 2)
	end
	return ok
end

W.ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- Round mask on a texture, when this client supports masks.
function W.RoundMask(parent, tex)
	if type(parent.CreateMaskTexture) ~= "function" or type(tex.AddMaskTexture) ~= "function" then
		return nil
	end
	local ok, mask = pcall(parent.CreateMaskTexture, parent)
	if not ok or not mask then
		return nil
	end
	pcall(mask.SetTexture, mask, W.ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(tex)
	pcall(tex.AddMaskTexture, tex, mask)
	return mask
end

-- Offset of a frame's center from the screen center, in UIParent units.
function W.CenterOffset(frame)
	local cx, cy = frame:GetCenter()
	local ux, uy = UIParent:GetCenter()
	if not cx or not ux then
		return 0, 0
	end
	local scale = (frame:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	return math.floor(cx * scale - ux + 0.5), math.floor(cy * scale - uy + 0.5)
end

------------------------------------------------------------------------
-- Own tooltip
------------------------------------------------------------------------

local tip = CreateFrame("Frame", "BulwarkTooltip", UIParent)
tip:SetFrameStrata("TOOLTIP")
tip:SetClampedToScreen(true)
W.Panel(tip, 0.95)
tip.lines = {}
tip:Hide()

function W.ShowTip(owner, title, ...)
	local lines = { ... }
	local width, y = 0, -6
	local count = 0
	local function Line(text, r, g, b)
		count = count + 1
		local fs = tip.lines[count]
		if not fs then
			fs = W.Text(tip, count == 1 and "GameFontNormalSmall" or "GameFontHighlightSmall")
			tip.lines[count] = fs
		end
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", 8, y)
		fs:SetWidth(0)
		fs:SetText(text)
		if r then
			fs:SetTextColor(r, g, b)
		end
		fs:Show()
		local w = G.Num(fs:GetStringWidth()) or 120
		if w > 260 then
			fs:SetWidth(260)
			w = 260
		end
		width = math.max(width, w)
		y = y - (G.Num(fs:GetStringHeight()) or 12) - 2
	end
	Line(title, ns.GOLD[1], ns.GOLD[2], ns.GOLD[3])
	for _, text in ipairs(lines) do
		Line(text, 0.9, 0.9, 0.9)
	end
	for i = count + 1, #tip.lines do
		tip.lines[i]:Hide()
	end
	tip:SetSize(width + 16, -y + 4)
	tip:ClearAllPoints()
	tip:SetPoint("BOTTOMLEFT", owner, "TOPRIGHT", 4, 4)
	tip:Show()
end

function W.HideTip()
	tip:Hide()
end

function W.AttachTip(frame, title, ...)
	local lines = { ... }
	frame:SetScript("OnEnter", function(self)
		local t = type(title) == "function" and title(self) or title
		if type(t) == "table" then
			W.ShowTip(self, t[1], select(2, (unpack or table.unpack)(t)))
		else
			W.ShowTip(self, t, (unpack or table.unpack)(lines))
		end
	end)
	frame:SetScript("OnLeave", W.HideTip)
end

------------------------------------------------------------------------
-- Controls (used by the options window)
------------------------------------------------------------------------

function W.Button(parent, text, width, height, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width or 90, height or 20)
	W.Panel(b, 1, 0.15, 0.15, 0.18)
	b.text = W.Text(b, "GameFontHighlightSmall")
	b.text:SetPoint("CENTER")
	b.text:SetText(text)
	b.hl = b:CreateTexture(nil, "HIGHLIGHT")
	b.hl:SetAllPoints()
	b.hl:SetColorTexture(1, 0.82, 0.2, 0.12)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	if onClick then
		b:SetScript("OnClick", onClick)
	end
	return b
end

-- Flat checkbox: get() -> bool, set(bool).
function W.Check(parent, label, get, set)
	local c = CreateFrame("Button", nil, parent)
	c:SetSize(220, 18)
	c.box = c:CreateTexture(nil, "ARTWORK")
	c.box:SetSize(14, 14)
	c.box:SetPoint("LEFT", 0, 0)
	c.box:SetColorTexture(0.12, 0.12, 0.15, 1)
	c.edge = c:CreateTexture(nil, "BORDER")
	c.edge:SetPoint("TOPLEFT", c.box, -1, 1)
	c.edge:SetPoint("BOTTOMRIGHT", c.box, 1, -1)
	c.edge:SetColorTexture(0, 0, 0, 1)
	c.mark = c:CreateTexture(nil, "OVERLAY")
	c.mark:SetPoint("TOPLEFT", c.box, 3, -3)
	c.mark:SetPoint("BOTTOMRIGHT", c.box, -3, 3)
	c.mark:SetColorTexture(ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], 1)
	c.label = W.Text(c, "GameFontHighlightSmall")
	c.label:SetPoint("LEFT", c.box, "RIGHT", 6, 0)
	c.label:SetJustifyH("LEFT")
	c.label:SetText(label)
	c.hl = c:CreateTexture(nil, "HIGHLIGHT")
	c.hl:SetAllPoints(c.box)
	c.hl:SetColorTexture(1, 1, 1, 0.15)
	function c.Refresh()
		c.mark:SetShown(get() and true or false)
	end
	c:SetScript("OnClick", function()
		set(not get())
		c.Refresh()
		if ns.Options and ns.Options.Changed then
			ns.Options.Changed()
		end
	end)
	c.Refresh()
	return c
end

-- Flat slider with label and value text.
function W.Slider(parent, label, min, max, step, get, set, fmt)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(230, 34)
	holder.label = W.Text(holder, "GameFontNormalSmall")
	holder.label:SetPoint("TOPLEFT", 0, 0)
	holder.label:SetText(label)
	holder.value = W.Text(holder, "GameFontHighlightSmall")
	holder.value:SetPoint("TOPRIGHT", 0, 0)

	local s = CreateFrame("Slider", nil, holder)
	s:SetPoint("TOPLEFT", 0, -16)
	s:SetPoint("TOPRIGHT", 0, -16)
	s:SetHeight(12)
	s:SetOrientation("HORIZONTAL")
	s:SetMinMaxValues(min, max)
	G.Call(s.SetValueStep, s, step)
	G.Call(s.SetObeyStepOnDrag, s, true)
	s.track = s:CreateTexture(nil, "BACKGROUND")
	s.track:SetPoint("LEFT")
	s.track:SetPoint("RIGHT")
	s.track:SetHeight(4)
	s.track:SetColorTexture(0.2, 0.2, 0.24, 1)
	s.thumb = s:CreateTexture(nil, "OVERLAY")
	s.thumb:SetSize(8, 12)
	s.thumb:SetColorTexture(ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], 1)
	s:SetThumbTexture(s.thumb)
	s:EnableMouseWheel(true)
	holder.slider = s

	local function Show(v)
		if fmt then
			holder.value:SetText(fmt(v))
		elseif step < 1 then
			holder.value:SetText(string.format("%.2f", v))
		else
			holder.value:SetText(tostring(math.floor(v + 0.5)))
		end
	end
	local updating = false
	s:SetScript("OnValueChanged", function(_, v)
		if updating then
			return
		end
		v = G.Clamp(G.Round(v, step), min, max)
		set(v)
		Show(v)
		if ns.Options and ns.Options.Changed then
			ns.Options.Changed()
		end
	end)
	s:SetScript("OnMouseWheel", function(self, delta)
		local v = G.Num(self:GetValue()) or min
		self:SetValue(G.Clamp(v + delta * step, min, max))
	end)
	function holder.Refresh()
		local v = tonumber(get()) or min
		updating = true
		s:SetValue(v)
		updating = false
		Show(v)
	end
	holder.Refresh()
	return holder
end

-- A button that cycles through choices: { { value, text }, ... }.
function W.Cycle(parent, label, choices, get, set)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(230, 36)
	holder.label = W.Text(holder, "GameFontNormalSmall")
	holder.label:SetPoint("TOPLEFT", 0, 0)
	holder.label:SetText(label)
	local b = W.Button(holder, "", 230, 18)
	b:SetPoint("TOPLEFT", 0, -15)
	b:SetPoint("TOPRIGHT", 0, -15)
	holder.button = b
	local function Index()
		local v = get()
		for i, c in ipairs(choices) do
			if c[1] == v then
				return i
			end
		end
		return 1
	end
	function holder.Refresh()
		local c = choices[Index()]
		b.text:SetText("< " .. (c and c[2] or "?") .. " >")
	end
	b:SetScript("OnClick", function(_, button)
		local i = Index() + (button == "RightButton" and -1 or 1)
		if i > #choices then
			i = 1
		elseif i < 1 then
			i = #choices
		end
		set(choices[i][1])
		holder.Refresh()
		if ns.Options and ns.Options.Changed then
			ns.Options.Changed()
		end
	end)
	W.AttachTip(b, label, T("Left click: next. Right click: previous."))
	holder.Refresh()
	return holder
end

-- Color swatch: get() -> { r, g, b, a }.
function W.Swatch(parent, label, get, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(100, 18)
	b.chip = b:CreateTexture(nil, "ARTWORK")
	b.chip:SetSize(16, 16)
	b.chip:SetPoint("LEFT")
	b.edge = b:CreateTexture(nil, "BORDER")
	b.edge:SetPoint("TOPLEFT", b.chip, -1, 1)
	b.edge:SetPoint("BOTTOMRIGHT", b.chip, 1, -1)
	b.edge:SetColorTexture(0, 0, 0, 1)
	b.label = W.Text(b, "GameFontHighlightSmall")
	b.label:SetPoint("LEFT", b.chip, "RIGHT", 5, 0)
	b.label:SetText(label)
	b.sel = b:CreateTexture(nil, "BACKGROUND")
	b.sel:SetAllPoints()
	b.sel:SetColorTexture(1, 0.82, 0.2, 0.18)
	b.sel:Hide()
	function b.Refresh(selected)
		local c = get()
		b.chip:SetColorTexture(c[1], c[2], c[3], 1)
		b.sel:SetShown(selected and true or false)
	end
	b:SetScript("OnClick", onClick)
	b.Refresh(false)
	return b
end

------------------------------------------------------------------------
-- Website link. The game cannot open web pages, so a click shows the
-- address in a small window, selected and ready for Cmd+C / Ctrl+C.
------------------------------------------------------------------------

local copy

function W.ShowCopy(url)
	if not copy then
		copy = CreateFrame("Frame", "BulwarkCopyDialog", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
		copy:SetSize(330, 104)
		copy:SetPoint("CENTER", 0, 120)
		copy:SetFrameStrata("FULLSCREEN_DIALOG")
		copy:SetToplevel(true)
		copy:EnableMouse(true)
		if copy.SetBackdrop then
			copy:SetBackdrop({
				bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
				tile = true, tileSize = 32, edgeSize = 32,
				insets = { left = 11, right = 12, top = 12, bottom = 11 },
			})
		end
		local hint = copy:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		hint:SetPoint("TOP", 0, -22)
		hint:SetText(T("Press Cmd+C (Ctrl+C) to copy the address"))
		local eb = CreateFrame("EditBox", nil, copy, "InputBoxTemplate")
		eb:SetSize(250, 22)
		eb:SetPoint("TOP", 0, -44)
		eb:SetAutoFocus(true)
		eb:SetJustifyH("CENTER")
		eb:SetScript("OnEscapePressed", function() copy:Hide() end)
		eb:SetScript("OnEnterPressed", function() copy:Hide() end)
		eb:SetScript("OnTextChanged", function(self, user)
			if user then -- keep the address intact
				self:SetText(copy.url or "")
				self:HighlightText()
			end
		end)
		eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
		copy.eb = eb
		local close = CreateFrame("Button", nil, copy, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -5, -5)
		local done = CreateFrame("Button", nil, copy, "UIPanelButtonTemplate")
		done:SetSize(90, 20)
		done:SetPoint("BOTTOM", 0, 16)
		done:SetText(OKAY or "OK")
		done:SetScript("OnClick", function() copy:Hide() end)
		if UISpecialFrames then
			table.insert(UISpecialFrames, "BulwarkCopyDialog")
		end
	end
	copy.url = url
	copy.eb:SetText(url)
	copy:Show()
	copy.eb:SetFocus()
	copy.eb:HighlightText()
end

-- A clickable "addicted.sh"-style text. Returns the button.
function W.Link(parent, text, url)
	local b = CreateFrame("Button", nil, parent)
	local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetPoint("LEFT")
	fs:SetText(text)
	fs:SetTextColor(0.5, 0.83, 1)
	b.text = fs
	local w = fs:GetStringWidth()
	b:SetSize((type(w) == "number" and w > 0 and w or 60) + 2, 14)
	b:SetScript("OnEnter", function(self)
		fs:SetTextColor(0.75, 0.92, 1)
		W.ShowTip(self, url, T("Click to copy the address"))
	end)
	b:SetScript("OnLeave", function()
		fs:SetTextColor(0.5, 0.83, 1)
		W.HideTip()
	end)
	b:SetScript("OnClick", function()
		W.ShowCopy(url)
	end)
	return b
end
