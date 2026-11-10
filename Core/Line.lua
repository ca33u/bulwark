--[[
  Bulwark core: the duration line.

  A horizontal bar drawn with plain textures: background, glow, body
  (gradient from the line color to the end color), caps and an optional
  bevel or inset border depending on the style. Tracked short buffs ride
  on it: an icon starts at the "start" end and travels to the red end as
  the buff runs out.
]]

local ADDON_NAME, ns = ...
ns = ns or {}
local G, S, W, T = ns.G, ns.Spells, ns.W, ns.T

local L = {}
ns.Line = L

-- Styles: default thickness and extras. "Classic rounded" uses round caps.
L.STYLES = {
	classic = { label = "Classic rounded", round = true },
	minimal = { label = "Minimal flat", flat = true },
	inset = { label = "Inset rail", inset = true },
	luminous = { label = "Luminous beveled", bevel = true, round = true, glowBoost = 1.6 },
}

-- Container: always shown, holds the bar, the icons and the swing rail.
local frame = CreateFrame("Frame", "BulwarkLine", UIParent)
frame:SetFrameStrata("MEDIUM")
frame:SetSize(420, 10)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, -140)
frame:SetClampedToScreen(true)
L.frame = frame

-- The bar itself (hidden by "only in combat" and the hide options).
local bar = CreateFrame("Frame", nil, frame)
bar:SetAllPoints()
L.bar = bar

local tex = {}
tex.bg = bar:CreateTexture(nil, "BACKGROUND", nil, 0)
tex.glowOuter = bar:CreateTexture(nil, "BACKGROUND", nil, 2)
tex.glowInner = bar:CreateTexture(nil, "BACKGROUND", nil, 3)
tex.body = bar:CreateTexture(nil, "ARTWORK", nil, 0)
tex.bevelTop = bar:CreateTexture(nil, "ARTWORK", nil, 2)
tex.bevelBottom = bar:CreateTexture(nil, "ARTWORK", nil, 2)
tex.capStart = bar:CreateTexture(nil, "ARTWORK", nil, 3)
tex.capEnd = bar:CreateTexture(nil, "ARTWORK", nil, 3)
tex.inset = {}
for i = 1, 4 do
	tex.inset[i] = bar:CreateTexture(nil, "ARTWORK", nil, 4)
end
for _, t in pairs(tex) do
	if type(t) == "table" and t.SetTexture then
		t:SetTexture(W.WHITE)
	end
end
L.tex = tex
local capMaskStart = W.RoundMask(bar, tex.capStart)
local capMaskEnd = W.RoundMask(bar, tex.capEnd)

-- A "pill": a rectangle with half-circle ends, for the dark track and the
-- glow around round styles. The ends are textures masked by a full circle
-- that is twice as wide as the texture, so only the outer half shows and
-- nothing overlaps (no darker seams with see-through colors).
local function Pill(layer, sub)
	local p = {}
	for _, part in ipairs({ "mid", "left", "right" }) do
		p[part] = bar:CreateTexture(nil, layer, nil, sub)
		p[part]:SetTexture(W.WHITE)
	end
	if type(bar.CreateMaskTexture) == "function" and type(p.left.AddMaskTexture) == "function" then
		for _, side in ipairs({ "left", "right" }) do
			local ok, m = pcall(bar.CreateMaskTexture, bar)
			if ok and m then
				pcall(m.SetTexture, m, W.ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
				pcall(p[side].AddMaskTexture, p[side], m)
				p[side .. "Mask"] = m
			end
		end
	end
	p.canRound = p.leftMask ~= nil and p.rightMask ~= nil
	return p
end

-- Places a pill around the line frame with this padding and color.
-- round = false draws a plain rectangle (flat and inset styles).
function L.PlacePill(p, pad, color, round, shown)
	for _, part in ipairs({ "mid", "left", "right" }) do
		p[part]:SetShown(shown and true or false)
		p[part]:ClearAllPoints()
		p[part]:SetColorTexture(color[1], color[2], color[3], color[4])
	end
	if not shown then
		return
	end
	local h = (frame:GetHeight() or 0) + 2 * pad
	local r = (round and p.canRound) and h / 2 or 0
	p.mid:SetPoint("TOPLEFT", frame, "TOPLEFT", -pad + r, pad)
	p.mid:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", pad - r, -pad)
	if r <= 0 then
		p.left:Hide()
		p.right:Hide()
		return
	end
	p.left:SetPoint("TOPRIGHT", p.mid, "TOPLEFT")
	p.left:SetPoint("BOTTOMRIGHT", p.mid, "BOTTOMLEFT")
	p.left:SetWidth(r)
	p.right:SetPoint("TOPLEFT", p.mid, "TOPRIGHT")
	p.right:SetPoint("BOTTOMLEFT", p.mid, "BOTTOMRIGHT")
	p.right:SetWidth(r)
	p.leftMask:ClearAllPoints()
	p.leftMask:SetSize(h, h)
	p.leftMask:SetPoint("CENTER", p.mid, "LEFT")
	p.rightMask:ClearAllPoints()
	p.rightMask:SetSize(h, h)
	p.rightMask:SetPoint("CENTER", p.mid, "RIGHT")
end

-- Track and glow are pills; tex.bg / tex.glow* stay as the plain fallbacks.
local pills = {
	bg = Pill("BACKGROUND", 0),
	glowOuter = Pill("BACKGROUND", 2),
	glowInner = Pill("BACKGROUND", 3),
}
L.pills = pills
tex.bg:Hide()
tex.glowOuter:Hide()
tex.glowInner:Hide()

-- Unlocked preview label.
local hint = W.Text(frame, "GameFontNormalSmall")
hint:SetPoint("BOTTOM", frame, "TOP", 0, 26)
hint:SetText(T("Bulwark line: drag to move, wheel = scale, Shift = width, Alt = thickness, right-click = options"))
hint:Hide()
L.hint = hint

local function Mix(c1, c2, f)
	return {
		c1[1] + (c2[1] - c1[1]) * f,
		c1[2] + (c2[2] - c1[2]) * f,
		c1[3] + (c2[3] - c1[3]) * f,
		(c1[4] or 1) + ((c2[4] or 1) - (c1[4] or 1)) * f,
	}
end

------------------------------------------------------------------------
-- Layout and looks
------------------------------------------------------------------------

function L.Apply()
	local db = ns.DB()
	local style = L.STYLES[db.barStyle] or L.STYLES.classic
	local width, h = db.width, db.lineHeight
	local scale = db.scale
	local c = db.colors

	frame:SetScale(scale)
	frame:SetSize(width, h)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", db.x / scale, db.y / scale)

	-- Direction: the "start" end is where icons appear.
	local startColor, endColor = c.capStart, c.capEnd
	local leftBody, rightBody = c.line, Mix(c.line, c.capEnd, 0.85)
	if not db.growRight then
		leftBody, rightBody = rightBody, leftBody
	end

	-- Caps: round circles at both ends, or square ends.
	local capsOn = db.showCaps and not style.flat
	local capW = capsOn and h or 0
	tex.capStart:SetShown(capsOn)
	tex.capEnd:SetShown(capsOn)
	if capsOn then
		local leftCap, rightCap = tex.capStart, tex.capEnd
		if not db.growRight then
			leftCap, rightCap = tex.capEnd, tex.capStart
		end
		leftCap:ClearAllPoints()
		leftCap:SetSize(h, h)
		leftCap:SetPoint("CENTER", frame, "LEFT", h / 2, 0)
		rightCap:ClearAllPoints()
		rightCap:SetSize(h, h)
		rightCap:SetPoint("CENTER", frame, "RIGHT", -h / 2, 0)
		local useRound = style.round and capMaskStart ~= nil
		tex.capStart:SetColorTexture(startColor[1], startColor[2], startColor[3], startColor[4])
		tex.capEnd:SetColorTexture(endColor[1], endColor[2], endColor[3], endColor[4])
		if not useRound then
			-- Square caps: a slightly larger block at each end.
			leftCap:SetSize(math.max(3, h * 0.6), h + 2)
			rightCap:SetSize(math.max(3, h * 0.6), h + 2)
		end
	end

	-- Body between the caps (overlaps half a cap for a smooth join).
	tex.body:ClearAllPoints()
	tex.body:SetPoint("TOPLEFT", frame, "TOPLEFT", capW / 2, 0)
	tex.body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -capW / 2, 0)
	W.Gradient(tex.body, "HORIZONTAL", leftBody, rightBody)

	-- Bevel (luminous): light top half, dark bottom strip.
	tex.bevelTop:SetShown(style.bevel and true or false)
	tex.bevelBottom:SetShown(style.bevel and true or false)
	if style.bevel then
		tex.bevelTop:ClearAllPoints()
		tex.bevelTop:SetPoint("TOPLEFT", tex.body, "TOPLEFT")
		tex.bevelTop:SetPoint("TOPRIGHT", tex.body, "TOPRIGHT")
		tex.bevelTop:SetHeight(math.max(1, h * 0.45))
		W.Gradient(tex.bevelTop, "VERTICAL", { 1, 1, 1, 0 }, { 1, 1, 1, 0.45 })
		tex.bevelBottom:ClearAllPoints()
		tex.bevelBottom:SetPoint("BOTTOMLEFT", tex.body, "BOTTOMLEFT")
		tex.bevelBottom:SetPoint("BOTTOMRIGHT", tex.body, "BOTTOMRIGHT")
		tex.bevelBottom:SetHeight(math.max(1, h * 0.3))
		W.Gradient(tex.bevelBottom, "VERTICAL", { 0, 0, 0, 0.45 }, { 0, 0, 0, 0 })
	end

	-- Inset rail: dark top/left, light bottom/right 1 px edges.
	for i = 1, 4 do
		tex.inset[i]:SetShown(style.inset and true or false)
	end
	if style.inset then
		local e = tex.inset
		e[1]:ClearAllPoints()
		e[1]:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -1, 0)
		e[1]:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 1, 0)
		e[1]:SetHeight(1)
		e[1]:SetColorTexture(0, 0, 0, 0.9)
		e[2]:ClearAllPoints()
		e[2]:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -1, 0)
		e[2]:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 1, 0)
		e[2]:SetHeight(1)
		e[2]:SetColorTexture(1, 1, 1, 0.25)
		e[3]:ClearAllPoints()
		e[3]:SetPoint("TOPRIGHT", frame, "TOPLEFT", 0, 0)
		e[3]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 0, 0)
		e[3]:SetWidth(1)
		e[3]:SetColorTexture(0, 0, 0, 0.9)
		e[4]:ClearAllPoints()
		e[4]:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, 0)
		e[4]:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 0, 0)
		e[4]:SetWidth(1)
		e[4]:SetColorTexture(1, 1, 1, 0.25)
	end

	-- Background: a dark track around the bar, rounded like the bar's ends
	-- for the round styles.
	local round = style.round and true or false
	L.PlacePill(pills.bg, 2, c.bg, round, db.showBackground)

	-- Glow: two soft layers around the bar, same shape.
	local glowOn = db.showGlow and db.glowSize > 0
	local gs = db.glowSize or 0
	local boost = style.glowBoost or 1
	local gc = c.glow
	L.PlacePill(pills.glowOuter, gs, { gc[1], gc[2], gc[3], math.min(1, gc[4] * 0.45 * boost) }, round, glowOn)
	L.PlacePill(pills.glowInner, math.max(1, gs / 2), { gc[1], gc[2], gc[3], math.min(1, gc[4] * boost) }, round, glowOn)

	L.ApplyIcons()
	if ns.Swing and ns.Swing.Apply then
		ns.Swing.Apply()
	end
end

------------------------------------------------------------------------
-- Icons on the line
------------------------------------------------------------------------

local icons = {}

local function IconFrame(i)
	local f = icons[i]
	if f then
		return f
	end
	f = CreateFrame("Frame", nil, frame)
	f:SetFrameLevel((G.Num(frame:GetFrameLevel()) or 1) + 5)
	f.border = f:CreateTexture(nil, "BACKGROUND")
	f.border:SetAllPoints()
	f.border:SetColorTexture(0, 0, 0, 1)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetPoint("TOPLEFT", 1, -1)
	f.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.time = W.Text(f, nil, 11)
	f.time:SetPoint("TOP", f, "BOTTOM", 0, -1)
	f.name = W.Text(f, nil, 9)
	f.name:SetPoint("TOP", f.time, "BOTTOM", 0, 0)
	f.name:SetTextColor(0.85, 0.85, 0.85)
	f:Hide()
	icons[i] = f
	return f
end

function L.ApplyIcons()
	local db = ns.DB()
	for _, f in ipairs(icons) do
		f:SetSize(db.iconSize, db.iconSize)
	end
end

-- Pure: horizontal offset of an icon from the start end, 0..1.
function L.Progress(remaining, duration)
	if not duration or duration <= 0 then
		return 0
	end
	local f = 1 - remaining / duration
	if f < 0 then
		return 0
	end
	if f > 1 then
		return 1
	end
	return f
end

function L.FormatTime(sec)
	if sec >= 60 then
		return string.format("%dm", math.floor(sec / 60 + 0.5))
	end
	if sec >= 3 then
		return tostring(math.floor(sec + 0.5))
	end
	return string.format("%.1f", math.max(0, sec))
end

-- Entries to draw: { key, remaining, duration, icon }.
function L.Collect(now)
	local db = ns.DB()
	local out = {}
	for _, key in ipairs(S.LINE) do
		local e = ns.Auras.entries[key]
		if e and ns.IsTracked(key) then
			local remaining = e.expires - now
			local duration = e.duration
			local show = remaining > 0
			if key == "righteous_fury" and db.rfLastOnly then
				show = show and remaining <= 30
				duration = 30
			end
			if show then
				out[#out + 1] = { key = key, remaining = remaining, duration = duration, icon = e.icon }
			end
		end
	end
	return out
end

local SAMPLE = {
	{ key = "seal_fury", frac = 0.25, total = 30 },
	{ key = "holy_shield", frac = 0.55, total = 10 },
	{ key = "consecration", frac = 0.85, total = 8 },
}

function L.Render()
	local db = ns.DB()
	local now = G.Now()
	local preview = ns.Movers and (ns.Movers.unlocked or ns.Movers.testing)
	local paladin = G.IsPaladin()
	local state = G.PlayerState()
	local show = preview or (paladin and G.ShouldShow(db, "bar", "barOnlyInCombat", state))
	bar:SetShown(show and true or false)

	local list
	if ns.Movers and ns.Movers.testing then
		list = {}
		local t = ns.Movers.TestElapsed()
		for _, s in ipairs(SAMPLE) do
			local frac = (s.frac + t / 12) % 1
			list[#list + 1] = { key = s.key, remaining = s.total * (1 - frac), duration = s.total }
		end
	elseif show then
		list = L.Collect(now)
	else
		list = {}
	end

	local width = db.width
	local size = db.iconSize
	for i, item in ipairs(list) do
		local f = IconFrame(i)
		f:SetSize(size, size)
		local p = L.Progress(item.remaining, item.duration)
		local x = db.growRight and (-width / 2 + p * width) or (width / 2 - p * width)
		f:ClearAllPoints()
		f:SetPoint("CENTER", frame, "CENTER", x, 0)
		f.icon:SetTexture(item.icon or S.Icon(item.key))
		if db.showTimers then
			f.time:SetText(L.FormatTime(item.remaining))
			f.time:Show()
		else
			f.time:Hide()
		end
		if db.showNames then
			f.name:SetText(S.DisplayName(item.key))
			f.name:Show()
		else
			f.name:Hide()
		end
		local alpha = 1
		if db.flashSoon and item.remaining <= db.expireSoon then
			alpha = 0.45 + 0.55 * math.abs(math.sin(now * 5))
		end
		f:SetAlpha(alpha)
		f:Show()
	end
	for i = #list + 1, #icons do
		icons[i]:Hide()
	end
end

ns.Every(0.03, L.Render)
