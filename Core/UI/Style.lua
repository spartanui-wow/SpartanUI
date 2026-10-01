---@class SUI
local SUI = SUI

-- Shared visual language for SpartanUI's own tool windows (frame mover, options window, setup).
-- Colors and buttons follow the active window kit from Lib's AddonTools, so these windows look
-- like every other kit window; the palette below is only used when no kit is loaded. Anything
-- drawn with these helpers repaints itself when the accent or the kit changes.

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

---Take colors from a window kit, then repaint everything drawn with these helpers.
---@param kit table A normalized LibAT.UI.Kit config
function Style:ApplyKit(kit)
	local c, k = self.color, kit.colors
	c.pane = k.surface[1]
	c.raised = k.surface[2]
	c.header = k.bar or k.surface[3]
	c.line = { k.trim[1], k.trim[2], k.trim[3], 0.35 }
	c.lineStrong = { k.trimHi[1], k.trimHi[2], k.trimHi[3], 0.45 }
	c.text = k.text
	c.muted = k.secondary
	c.faint = k.muted
	self.kit = kit
	self:FireAccentChanged()
end

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

---Text drawn on a filled shape (buttons, segments) is sharper without the drop shadow
---@param text FontString
function Style:ClearShadow(text)
	text:SetShadowColor(0, 0, 0, 0)
	text:SetShadowOffset(0, 0)
end

----------------------------------------------------------------------------------------------------
-- Buttons
----------------------------------------------------------------------------------------------------

---@class SUI.UI.Style.Button : Button
---@field label FontString
---@field fill Texture
---@field border SUI.UI.Style.Border
---@field primary boolean
---@field active boolean

---Kit buttons are a gradient with an edge; without a kit the flat fill below is used.
local function PaintKitButton(button, colors, fallbackText)
	local r, g, b = Style:GetAccent()
	local top = colors.top or { r, g, b }
	local bottom = colors.bottom or { r * 0.5, g * 0.5, b * 0.5 }
	LibAT.UI.Kit:SetGradient(button.fill, top, bottom, button.hovered and 0.85 or 1)
	local edge = colors.edge or { r, g, b }
	button.border:SetColor(edge[1], edge[2], edge[3], 1)
	local text = colors.text or fallbackText
	button.label:SetTextColor(text[1], text[2], text[3])
end

local function PaintButton(button)
	local c = Style.color
	local r, g, b = Style:GetAccent()
	local kit = Style.kit
	if kit and button:IsEnabled() and not button.active then
		PaintKitButton(button, button.primary and kit.button.primary or kit.button.secondary, button.primary and c.onAccent or c.text)
		return
	end
	if not button:IsEnabled() then
		button.fill:SetVertexColor(c.raised[1], c.raised[2], c.raised[3], 0.6)
		button.border:SetColor(c.line[1], c.line[2], c.line[3], c.line[4])
		button.label:SetTextColor(c.faint[1], c.faint[2], c.faint[3])
	elseif button.primary then
		local lift = button.hovered and 0.12 or 0
		button.fill:SetVertexColor(math.min(1, r + lift), math.min(1, g + lift), math.min(1, b + lift), 1)
		button.border:SetColor(r, g, b, 1)
		button.label:SetTextColor(c.onAccent[1], c.onAccent[2], c.onAccent[3])
	elseif button.active then
		button.fill:SetVertexColor(r, g, b, button.hovered and 0.3 or 0.2)
		button.border:SetColor(r, g, b, 0.9)
		button.label:SetTextColor(c.text[1], c.text[2], c.text[3])
	else
		local lift = button.hovered and 0.035 or 0
		local textColor = button.hovered and c.text or c.muted
		button.fill:SetVertexColor(c.raised[1] + lift, c.raised[2] + lift, c.raised[3] + lift, c.raised[4])
		button.border:SetColor(c.lineStrong[1], c.lineStrong[2], c.lineStrong[3], button.hovered and 0.3 or c.lineStrong[4])
		button.label:SetTextColor(textColor[1], textColor[2], textColor[3])
	end
end

---Width of a FontString's text. A font file that has not been drawn yet can measure 0,
---so fall back to an estimate from the character count.
---@param text FontString
---@return number
function Style:MeasureText(text)
	local width = text:GetStringWidth() or 0
	if width <= 0 then
		local _, size = text:GetFont()
		width = #(text:GetText() or '') * (size or 11) * 0.52
	end
	return math.ceil(width)
end

local ButtonMixin = {}

---Size the button to its text unless it was given a fixed width
function ButtonMixin:FitText()
	self:SetWidth(self.fixedWidth or math.max(48, Style:MeasureText(self.label) + 18))
end

---Create a flat button
---@param parent Frame
---@param text string
---@param width? number Fixed width; sized to the text when omitted
---@param onClick? fun(button: SUI.UI.Style.Button, mouseButton: string)
---@param primary? boolean Filled with the accent color
---@return SUI.UI.Style.Button
function Style:CreateButton(parent, text, width, onClick, primary)
	local button = CreateFrame('Button', nil, parent) ---@type SUI.UI.Style.Button
	Mixin(button, ButtonMixin)
	button:SetHeight(22)
	button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
	button.fill = Style:CreateFill(button, Style.color.raised)
	button.border = Style:CreateBorder(button)
	button.label = Style:CreateText(button, 11)
	Style:ClearShadow(button.label)
	button.label:SetPoint('CENTER', 0, 0)
	button.label:SetText(text)
	button.primary = primary or false
	button.fixedWidth = width
	button:FitText()
	button:SetScript('OnEnter', function(self)
		self.hovered = true
		PaintButton(self)
		if self.tooltip then
			GameTooltip:SetOwner(self, 'ANCHOR_BOTTOM')
			GameTooltip:SetText(self.tooltipTitle or text, 1, 1, 1)
			GameTooltip:AddLine(self.tooltip, nil, nil, nil, true)
			GameTooltip:Show()
		end
	end)
	button:SetScript('OnLeave', function(self)
		self.hovered = false
		PaintButton(self)
		GameTooltip:Hide()
	end)
	button:SetScript('OnEnable', PaintButton)
	button:SetScript('OnDisable', PaintButton)
	if onClick then
		button:SetScript('OnClick', onClick)
	end
	function button:SetText(value)
		self.label:SetText(value)
		self:FitText()
	end
	function button:SetActive(active)
		self.active = active and true or false
		PaintButton(self)
	end
	function button:SetTooltip(body, title)
		self.tooltip = body
		self.tooltipTitle = title
	end
	Style:OnAccentChanged(button, function()
		PaintButton(button)
	end)
	return button
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
		if LibAT and LibAT.UI and LibAT.UI.Kit then
			LibAT.UI.Kit:Track(watcher, function(_, kit)
				Style:ApplyKit(kit)
			end)
		end
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
