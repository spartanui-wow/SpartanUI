---@class SUI
local SUI = SUI

-- Shared visual language for SpartanUI's own tool windows (frame mover, options window, setup).
-- Flat dark panels, 1 physical pixel borders, one accent color taken from the active theme,
-- one condensed UI font and short eased motion. Anything drawn with these helpers repaints
-- itself when the accent changes.

---@class SUI.UI.Style
local Style = {}
SUI.UI = SUI.UI or {}
SUI.UI.Style = Style

Style.WHITE = 'Interface\\Buttons\\WHITE8X8'
Style.FONT_NAME = 'Roboto Condensed Bold'

Style.color = {
	pane = { 0.047, 0.051, 0.059, 0.94 },
	raised = { 0.066, 0.070, 0.082, 0.96 },
	header = { 0.058, 0.062, 0.072, 0.97 },
	mover = { 0.075, 0.113, 0.141, 0.92 },
	hover = { 1, 1, 1, 0.05 },
	pressed = { 1, 1, 1, 0.09 },
	line = { 1, 1, 1, 0.09 },
	lineStrong = { 1, 1, 1, 0.16 },
	input = { 0, 0, 0, 0.4 },
	dim = { 0.02, 0.03, 0.04 },
	text = { 0.93, 0.92, 0.90 },
	muted = { 0.62, 0.63, 0.66 },
	faint = { 0.42, 0.43, 0.46 },
	onAccent = { 0.04, 0.05, 0.06 },
	anchored = { 1, 0.7, 0.3 },
	warn = { 1, 0.72, 0.28 },
	good = { 0.30, 0.82, 0.40 },
	bad = { 0.92, 0.30, 0.30 },
}

local DEFAULT_ACCENT = { 0.886, 0.122, 0.122 }

-- Accent per theme. A theme can also set `accent = { r, g, b }` in its registry metadata.
local THEME_ACCENTS = {
	Classic = { 1, 0.78, 0.22 },
	Fel = { 0.42, 0.86, 0.22 },
	Arcane = { 0.33, 0.66, 1 },
	ArcaneRed = { 0.95, 0.30, 0.25 },
	Digital = { 0.20, 0.82, 0.95 },
	Midnight = { 0.58, 0.40, 0.95 },
	Midnight_Void = { 0.58, 0.40, 0.95 },
	Midnight_Shadow = { 0.70, 0.55, 1 },
	Tribal = { 0.92, 0.60, 0.26 },
	Transparent = { 0.35, 0.72, 1 },
	Grid = { 0.05, 0.82, 0.62 },
}

----------------------------------------------------------------------------------------------------
-- Accent
----------------------------------------------------------------------------------------------------

local accentListeners = setmetatable({}, { __mode = 'k' })

---@return table|nil
local function GetStyleDB()
	return SUI.DB and SUI.DB.UIStyle
end

---Accent color for the active theme, or the player's choice
---@return number r, number g, number b
function Style:GetAccent()
	local db = GetStyleDB()
	if db then
		if db.accentMode == 'class' then
			local _, class = UnitClass('player')
			local color = class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
			if color then
				return color.r, color.g, color.b
			end
		elseif db.accentMode == 'custom' and db.customAccent then
			return db.customAccent.r or 1, db.customAccent.g or 1, db.customAccent.b or 1
		end
	end

	local themeName = SUI.GetActiveStyle and SUI:GetActiveStyle()
	if themeName then
		local entry = SUI.ThemeRegistry and SUI.ThemeRegistry:Get(themeName)
		local accent = (entry and entry.accent) or THEME_ACCENTS[themeName]
		if not accent and themeName == 'War' then
			accent = UnitFactionGroup('player') == 'Alliance' and { 0.25, 0.55, 1 } or { 0.9, 0.22, 0.16 }
		end
		if accent then
			return accent[1], accent[2], accent[3]
		end
	end
	return DEFAULT_ACCENT[1], DEFAULT_ACCENT[2], DEFAULT_ACCENT[3]
end

---Accent as a hex color code for inline text (|cffRRGGBB)
---@return string
function Style:GetAccentHex()
	local r, g, b = self:GetAccent()
	return string.format('ff%02x%02x%02x', r * 255, g * 255, b * 255)
end

---Call `fn(r, g, b)` now and whenever the accent changes. Held weakly by `owner`.
---@param owner table
---@param fn fun(r: number, g: number, b: number)
function Style:OnAccentChanged(owner, fn)
	accentListeners[owner] = fn
	fn(self:GetAccent())
end

function Style:FireAccentChanged()
	local r, g, b = self:GetAccent()
	for _, fn in pairs(accentListeners) do
		fn(r, g, b)
	end
end

----------------------------------------------------------------------------------------------------
-- Pixels
----------------------------------------------------------------------------------------------------

---Size of one physical screen pixel in the region's own units
---@param region ScriptRegion
---@return number
function Style:PixelSize(region)
	local _, physicalHeight = GetPhysicalScreenSize()
	local scale = (region and region:GetEffectiveScale()) or UIParent:GetEffectiveScale()
	if not physicalHeight or physicalHeight == 0 or not scale or scale == 0 then
		return 1
	end
	return 768 / physicalHeight / scale
end

---Round a value in the region's units to whole physical pixels
---@param region ScriptRegion
---@param value number
---@return number
function Style:SnapToPixel(region, value)
	local px = self:PixelSize(region)
	return math.floor(value / px + 0.5) * px
end

local borders = setmetatable({}, { __mode = 'k' })

---@class SUI.UI.Style.Border
---@field frame Frame
---@field edges Texture[]
---@field thickness number Thickness in physical pixels
local BorderMixin = {}

function BorderMixin:SetColor(r, g, b, a)
	for _, edge in ipairs(self.edges) do
		edge:SetVertexColor(r, g, b, a or 1)
	end
end

function BorderMixin:SetShown(shown)
	for _, edge in ipairs(self.edges) do
		edge:SetShown(shown)
	end
end

function BorderMixin:Layout()
	local size = Style:PixelSize(self.frame) * self.thickness
	local top, bottom, left, right = self.edges[1], self.edges[2], self.edges[3], self.edges[4]
	top:ClearAllPoints()
	top:SetPoint('TOPLEFT')
	top:SetPoint('TOPRIGHT')
	top:SetHeight(size)
	bottom:ClearAllPoints()
	bottom:SetPoint('BOTTOMLEFT')
	bottom:SetPoint('BOTTOMRIGHT')
	bottom:SetHeight(size)
	left:ClearAllPoints()
	left:SetPoint('TOPLEFT', 0, -size)
	left:SetPoint('BOTTOMLEFT', 0, size)
	left:SetWidth(size)
	right:ClearAllPoints()
	right:SetPoint('TOPRIGHT', 0, -size)
	right:SetPoint('BOTTOMRIGHT', 0, size)
	right:SetWidth(size)
end

---Draw a border of whole physical pixels on the inside edge of a frame
---@param frame Frame
---@param thickness? number Physical pixels (default 1)
---@param layer? DrawLayer
---@param sublevel? number
---@return SUI.UI.Style.Border
function Style:CreateBorder(frame, thickness, layer, sublevel)
	local border = { frame = frame, edges = {}, thickness = thickness or 1 }
	for i = 1, 4 do
		local edge = frame:CreateTexture(nil, layer or 'OVERLAY', nil, sublevel or 7)
		edge:SetTexture(self.WHITE)
		border.edges[i] = edge
	end
	Mixin(border, BorderMixin)
	border:Layout()
	borders[border] = true
	return border
end

---Fill a frame with a flat color
---@param frame Frame
---@param color number[]
---@param layer? DrawLayer
---@return Texture
function Style:CreateFill(frame, color, layer)
	local fill = frame:CreateTexture(nil, layer or 'BACKGROUND')
	fill:SetTexture(self.WHITE)
	fill:SetAllPoints()
	fill:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
	return fill
end

---Flat panel: fill plus a 1px hairline border
---@param frame Frame
---@param fillColor? number[]
---@param borderColor? number[]
function Style:SkinPanel(frame, fillColor, borderColor)
	frame.styleFill = frame.styleFill or self:CreateFill(frame, fillColor or self.color.pane)
	local fc = fillColor or self.color.pane
	frame.styleFill:SetVertexColor(fc[1], fc[2], fc[3], fc[4] or 1)
	frame.styleBorder = frame.styleBorder or self:CreateBorder(frame)
	local bc = borderColor or self.color.line
	frame.styleBorder:SetColor(bc[1], bc[2], bc[3], bc[4] or 1)
end

----------------------------------------------------------------------------------------------------
-- Text
----------------------------------------------------------------------------------------------------

---@return string path
function Style:GetFontFace()
	local LSM = SUI.Lib and SUI.Lib.LSM
	local face = LSM and LSM:Fetch('font', self.FONT_NAME, true)
	return face or STANDARD_TEXT_FONT
end

---Create a shadowed FontString in the UI font
---@param parent Frame
---@param size number
---@param color? number[]
---@param layer? DrawLayer
---@param flags? string
---@return FontString
function Style:CreateText(parent, size, color, layer, flags)
	local text = parent:CreateFontString(nil, layer or 'OVERLAY')
	self:SetFont(text, size, flags)
	local c = color or self.color.text
	text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
	return text
end

---@param text FontString
---@param size number
---@param flags? string
function Style:SetFont(text, size, flags)
	text:SetFont(self:GetFontFace(), size, flags or '')
	text:SetShadowColor(0, 0, 0, 0.9)
	text:SetShadowOffset(1, -1)
end

----------------------------------------------------------------------------------------------------
-- Motion
----------------------------------------------------------------------------------------------------

local tweens = {}
local driver = CreateFrame('Frame')
driver:Hide()

local function EaseOutCubic(t)
	local inv = 1 - t
	return 1 - inv * inv * inv
end

driver:SetScript('OnUpdate', function(_, elapsed)
	local any = false
	for id, tween in pairs(tweens) do
		tween.elapsed = tween.elapsed + elapsed
		if tween.loop then
			tween.apply(tween.elapsed)
			any = true
		else
			local t = math.min(1, tween.elapsed / tween.duration)
			tween.apply(tween.from + (tween.to - tween.from) * EaseOutCubic(t))
			if t >= 1 then
				tweens[id] = nil
				if tween.onDone then
					tween.onDone()
				end
			else
				any = true
			end
		end
	end
	if not any and not next(tweens) then
		driver:Hide()
	end
end)

---Animate a number from `from` to `to`. A new tween with the same id replaces the running one.
---@param id any Unique key, usually the object being animated
---@param duration number Seconds
---@param from number
---@param to number
---@param apply fun(value: number)
---@param onDone? fun()
function Style:Tween(id, duration, from, to, apply, onDone)
	if duration <= 0 then
		tweens[id] = nil
		apply(to)
		if onDone then
			onDone()
		end
		return
	end
	tweens[id] = { elapsed = 0, duration = duration, from = from, to = to, apply = apply, onDone = onDone }
	driver:Show()
end

---Run `apply(elapsedSeconds)` every frame until stopped
---@param id any
---@param apply fun(elapsed: number)
function Style:Loop(id, apply)
	tweens[id] = { elapsed = 0, loop = true, apply = apply }
	driver:Show()
end

---@param id any
function Style:Stop(id)
	tweens[id] = nil
end

---Fade a region's alpha to a target
---@param region ScriptRegion
---@param to number
---@param duration? number
---@param onDone? fun()
function Style:FadeTo(region, to, duration, onDone)
	self:Tween(region, duration or 0.15, region:GetAlpha(), to, function(value)
		region:SetAlpha(value)
	end, onDone)
end

----------------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------------

local watcher = CreateFrame('Frame')
watcher:RegisterEvent('UI_SCALE_CHANGED')
watcher:RegisterEvent('DISPLAY_SIZE_CHANGED')
watcher:RegisterEvent('PLAYER_ENTERING_WORLD')
watcher:RegisterEvent('PLAYER_LOGIN')
watcher:SetScript('OnEvent', function(_, event)
	if event == 'PLAYER_LOGIN' then
		-- SUI.Event loads after the core UI files
		if SUI.Event then
			SUI.Event:RegisterEvent('ARTWORK_STYLE_CHANGED', function()
				Style:FireAccentChanged()
			end)
		end
		return
	end
	for border in pairs(borders) do
		border:Layout()
	end
	if event == 'PLAYER_ENTERING_WORLD' then
		Style:FireAccentChanged()
	end
end)
