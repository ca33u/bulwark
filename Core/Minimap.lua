--[[
  Bulwark core: round button on the minimap ring (LibDBIcon classic look).

  Parented to UIParent and only positioned around the minimap: a button
  parented to Minimap with the old border art has crashed the Forever
  client during load.
    Left click   options window
    Drag         move it around the minimap (angle saved)
]]

local ADDON_NAME, ns = ...
ns = ns or {}
local G, W, T = ns.G, ns.W, ns.T

local MM = {}
ns.Minimap = MM

MM.ICON = "Interface\\AddOns\\Bulwark\\Media\\minimap"

-- Pure: position on the ring for an angle in degrees, UIParent coordinates.
function MM.Point(angle, mx, my, width, minimapScale, uiScale)
	local a = math.rad(angle or 220)
	local r = width / 2 + 10
	local x, y = mx + math.cos(a) * r, my + math.sin(a) * r
	if minimapScale and uiScale and minimapScale > 0 and uiScale > 0 then
		x, y = x * minimapScale / uiScale, y * minimapScale / uiScale
	end
	return x, y
end

-- Pure: angle in degrees from the minimap center to a point.
function MM.Angle(px, py, mx, my)
	local deg = math.deg((math.atan2 or math.atan)(py - my, px - mx))
	return deg % 360
end

local btn

local function MinimapGeometry()
	local mm = _G.Minimap
	if type(mm) ~= "table" or G.IsForbidden(mm) then
		return nil
	end
	local ok, mx, my = pcall(mm.GetCenter, mm)
	local okW, width = pcall(mm.GetWidth, mm)
	mx, my = ok and G.Num(mx), ok and G.Num(my)
	width = okW and G.Num(width)
	if not mx or not my or not width or width < 20 then
		return nil
	end
	local okS, ms = pcall(mm.GetEffectiveScale, mm)
	local okU, us = pcall(UIParent.GetEffectiveScale, UIParent)
	return mx, my, width, okS and G.Num(ms) or nil, okU and G.Num(us) or nil
end

function MM.Place()
	if not btn then
		return
	end
	local db = ns.DB()
	if not db.showMinimap then
		btn:Hide()
		return
	end
	local mx, my, width, ms, us = MinimapGeometry()
	if not mx then
		btn:Hide()
		return
	end
	local x, y = MM.Point(db.minimapAngle, mx, my, width, ms, us)
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	btn:Show()
end

local function OnDragUpdate()
	local mx, my, _, ms, us = MinimapGeometry()
	if not mx then
		return
	end
	local cx, cy = GetCursorPosition()
	cx, cy = G.Num(cx), G.Num(cy)
	if not cx then
		return
	end
	local scale = ms or 1
	ns.DB().minimapAngle = MM.Angle(cx / scale, cy / scale, mx, my)
	MM.Place()
	return us
end

function MM.Create()
	if btn then
		return btn
	end
	btn = CreateFrame("Button", "BulwarkMinimapButton", UIParent)
	btn:SetSize(31, 31)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFrameLevel(40)
	btn:SetClampedToScreen(true)
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	btn:RegisterForDrag("LeftButton")
	btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", 7, -5)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	icon:SetTexture(MM.ICON)
	icon:SetTexCoord(0.06, 0.94, 0.06, 0.94) -- slight zoom, the round mask does the rest
	if not G.Call(icon.SetMask, icon, W.ROUND_MASK) then
		W.RoundMask(btn, icon)
	end
	btn.icon = icon

	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	btn:SetScript("OnClick", function()
		ns.Options.Toggle()
	end)
	btn:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", OnDragUpdate)
	end)
	btn:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	btn:SetScript("OnEnter", function(self)
		W.ShowTip(self, "Bulwark " .. ns.VERSION, T("Click: options"), T("Drag: move around the minimap"))
	end)
	btn:SetScript("OnLeave", W.HideTip)
	MM.button = btn
	return btn
end

ns.On("PLAYER_LOGIN", function()
	MM.Create()
	MM.Place()
end)
