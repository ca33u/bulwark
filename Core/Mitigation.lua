--[[
  Bulwark core: mitigation stats window (/bulwark mitig).

  Numbers against a raid boss (player level + 3 by default):
    each attacker level above you lowers miss, dodge, parry and block by
    0.2 % (classic: defense skill vs attack skill 5 x level)
    crit:  5 % + 0.04 % per attack skill above your defense
    crush: 15 % from three levels up, pushed off when miss + dodge +
           parry + block reaches 100 % after the level penalty
           (102.4 % on the character sheet against +3)
    armor: DR = armor / (armor + 400 + 85 x attacker level), max 75 %
    EHP  = HP / (1 - DR)
  Values the client hides are shown as "-".
]]

local ADDON_NAME, ns = ...
ns = ns or {}
local G, W, T = ns.G, ns.W, ns.T

local M = {}
ns.Mitigation = M

------------------------------------------------------------------------
-- Formulas (pure, unit-tested)
------------------------------------------------------------------------

function M.ArmorDR(armor, attackerLevel)
	if not armor or not attackerLevel or armor <= 0 then
		return 0
	end
	local dr = armor / (armor + 400 + 85 * attackerLevel)
	return math.min(0.75, dr)
end

function M.EHP(hp, dr)
	if not hp then
		return nil
	end
	dr = math.min(0.75, math.max(0, dr or 0))
	return hp / (1 - dr)
end

-- in: { level, levelDiff, defense, dodge, parry, block, blockValue, armor,
--       hp, spellPower, healing, hit }  (any value may be nil = hidden)
-- out: table of numbers (nil = hidden) with the same meaning as the rows.
function M.Compute(i)
	local o = {}
	local level = i.level or 60
	local diff = i.levelDiff or 3
	local attacker = level + diff
	local attackSkill = 5 * attacker
	local penalty = 0.2 * diff
	local function Down(v)
		if v == nil then
			return nil
		end
		return math.max(0, v - penalty)
	end
	o.attackerLevel = attacker
	if i.defense then
		o.miss = math.max(0, 5 + (i.defense - 5 * level) * 0.04 - penalty)
		o.crit = math.max(0, 5 + (attackSkill - i.defense) * 0.04)
		o.critCap = attackSkill + 125 -- 5 % / 0.04 % per point
		o.critNeed = math.max(0, o.critCap - i.defense)
	end
	o.dodge = Down(i.dodge)
	o.parry = Down(i.parry)
	o.block = Down(i.block)
	if o.miss and o.dodge and o.parry then
		o.avoid = o.miss + o.dodge + o.parry
	end
	if diff >= 3 then
		if o.avoid and o.block then
			local total = o.avoid + o.block
			o.crushGap = math.max(0, 100 - total)
			o.crush = total < 100 and 15 or 0
		end
	else
		o.crush, o.crushGap = 0, 0
	end
	o.blockValue = i.blockValue
	o.armor = i.armor
	if i.armor then
		o.dr = M.ArmorDR(i.armor, attacker) * 100
	end
	o.hp = i.hp
	if i.hp and i.armor then
		o.ehp = M.EHP(i.hp, o.dr / 100)
	end
	o.spellPower = i.spellPower
	o.healing = i.healing
	o.hit = i.hit
	return o
end

------------------------------------------------------------------------
-- Reading (guarded)
------------------------------------------------------------------------

local function N(fn, ...)
	return G.Num(G.Read(fn, ...))
end

function M.Read()
	local db = ns.DB()
	local i = { level = N(UnitLevel, "player"), levelDiff = db.mitigLevelDiff }
	local def = G.ReadAll(UnitDefense, "player")
	if def and G.Num(def[1]) then
		i.defense = def[1] + (G.Num(def[2]) or 0)
	end
	i.dodge = N(GetDodgeChance)
	i.parry = N(GetParryChance)
	i.block = N(GetBlockChance)
	i.blockValue = N(GetShieldBlock)
	local armor = G.ReadAll(UnitArmor, "player")
	i.armor = armor and G.Num(armor[2]) or nil
	i.hp = N(UnitHealthMax, "player")
	i.spellPower = N(GetSpellBonusDamage, 2)
	i.healing = N(GetSpellBonusHealing)
	i.hit = N(GetHitModifier)
	return i
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------

local ROWS = {
	{ "miss", "Miss" }, { "dodge", "Dodge" }, { "parry", "Parry" }, { "avoid", "Avoid" },
	{ "block", "Block" }, { "crit", "Crit" }, { "crush", "Crush" }, { "blockValue", "Block Value" },
	{ "armor", "Armor" }, { "dr", "DR" }, { "ehp", "EHP/HP" }, { "spellPower", "Spell Power" }, { "hit", "Hit" },
}

local win = CreateFrame("Frame", "BulwarkMitigation", UIParent)
win:SetSize(220, 40)
win:SetFrameStrata("MEDIUM")
win:SetClampedToScreen(true)
win:SetMovable(true)
win:EnableMouse(true)
win:RegisterForDrag("LeftButton")
W.Panel(win, 0.8)
win:Hide()
M.frame = win

local header = W.Text(win, "GameFontNormalSmall")
header:SetPoint("TOPLEFT", 8, -6)
header:SetTextColor(ns.GOLD[1], ns.GOLD[2], ns.GOLD[3])

local close = W.Button(win, "x", 14, 14, function()
	ns.DB().showMitigation = false
	win:Hide()
end)
close:SetPoint("TOPRIGHT", -4, -4)

local rowFrames = {}
for idx, def in ipairs(ROWS) do
	local r = {}
	r.label = W.Text(win, "GameFontHighlightSmall")
	r.value = W.Text(win, "GameFontHighlightSmall")
	r.label:SetJustifyH("LEFT")
	r.value:SetJustifyH("RIGHT")
	r.key = def[1]
	r.text = def[2]
	rowFrames[idx] = r
end

local DASH = "-"

local function Pct(v)
	return v and string.format("%.2f%%", v) or DASH
end

local function Int(v)
	return v and tostring(math.floor(v + 0.5)) or DASH
end

function M.Format(o)
	local out = {}
	out.miss, out.dodge, out.parry, out.avoid = Pct(o.miss), Pct(o.dodge), Pct(o.parry), Pct(o.avoid)
	out.block = Pct(o.block)
	if o.crit then
		out.crit = o.critNeed and o.critNeed > 0
			and string.format("%s (%s %d)", Pct(o.crit), T("need def"), math.floor(o.critCap + 0.5))
			or Pct(o.crit)
	else
		out.crit = DASH
	end
	if o.crush then
		out.crush = o.crushGap and o.crushGap > 0
			and string.format("%s (%s %.2f%%)", Pct(o.crush), T("gap"), o.crushGap)
			or Pct(o.crush)
	else
		out.crush = DASH
	end
	out.blockValue, out.armor = Int(o.blockValue), Int(o.armor)
	out.dr = o.dr and string.format("%.1f%%", o.dr) or DASH
	out.ehp = (o.ehp and o.hp) and string.format("%s / %s", Int(o.ehp), Int(o.hp)) or Int(o.hp)
	if o.spellPower or o.healing then
		out.spellPower = string.format("%s / %s", Int(o.spellPower), Int(o.healing))
	else
		out.spellPower = DASH
	end
	out.hit = Pct(o.hit)
	return out
end

function M.Apply()
	local db = ns.DB()
	win:SetScale(db.mitigScale)
	win:ClearAllPoints()
	win:SetPoint("CENTER", UIParent, "CENTER", db.mitigX / db.mitigScale, db.mitigY / db.mitigScale)
	local size = db.mitigFont
	local lh = size + 4
	W.SetFontSize(header, size + 1, "")
	for idx, r in ipairs(rowFrames) do
		W.SetFontSize(r.label, size, "")
		W.SetFontSize(r.value, size, "")
		r.label:ClearAllPoints()
		r.label:SetPoint("TOPLEFT", 8, -8 - lh * idx)
		r.value:ClearAllPoints()
		r.value:SetPoint("TOPRIGHT", -8, -8 - lh * idx)
		r.label:SetText(T(r.text))
	end
	win:SetSize(math.max(200, size * 20), 16 + lh * (#rowFrames + 1))
	win:SetShown(db.showMitigation and true or false)
end

function M.Refresh()
	if not win:IsShown() then
		return
	end
	local db = ns.DB()
	local o = M.Compute(M.Read())
	header:SetText(string.format(T("Mitigation vs level %d"), o.attackerLevel))
	local f = M.Format(o)
	for _, r in ipairs(rowFrames) do
		r.value:SetText(f[r.key] or DASH)
	end
	return db
end

win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local db = ns.DB()
	db.mitigX, db.mitigY = W.CenterOffset(self)
	M.Apply()
end)
win:SetScript("OnShow", M.Refresh)

function M.Toggle()
	local db = ns.DB()
	db.showMitigation = not db.showMitigation
	M.Apply()
	M.Refresh()
end

ns.Every(0.5, M.Refresh)
