---@class SUI
local SUI = SUI
local Style = SUI.UI.Style

-- Drawing helpers shared by the options window widgets (SUI-Switch, SUI-Slider, ...).
-- Everything here draws with flat textures so it follows the accent color and needs no art files.

---@class SUI.UI.OptionWidgets
local W = {}
SUI.UI.OptionWidgets = W

W.CIRCLE_MASK = 'Interface\\CHARACTERFRAME\\TempPortraitAlphaMask'
W.CHECK_GLYPH = 130751 -- Interface\Buttons\UI-CheckBox-Check
W.CHECKERS = 188523 -- Tileset\Generic\Checkers

W.LABEL_SIZE = 12
W.SMALL_SIZE = 11
W.INPUT_HEIGHT = 22
-- Labeled controls are 44 tall with the input box at the bottom. The flow layout lines up
-- controls on the same row by alignoffset, so every labeled control uses the box's middle.
W.LABELED_HEIGHT = 44
W.LABELED_ALIGN = 33
W.UNLABELED_HEIGHT = 26
W.UNLABELED_ALIGN = 15

-- Opaque colors for shapes built from several overlapping pieces (pill tracks, rings)
W.color = {
	trackOff = { 0.19, 0.20, 0.22 },
	ringOff = { 0.34, 0.35, 0.38 },
	hole = { 0.055, 0.059, 0.068 },
}

---@param id number
function W.Sound(id)
	if PlaySound then
		PlaySound(id)
	end
end

---@param region Texture|FontString
---@param color number[]
---@param alpha? number
function W.Paint(region, color, alpha)
	if region.SetVertexColor and region:GetObjectType() == 'Texture' then
		region:SetVertexColor(color[1], color[2], color[3], alpha or color[4] or 1)
	else
		region:SetTextColor(color[1], color[2], color[3], alpha or color[4] or 1)
	end
end

---@param a number
---@param b number
---@param t number
---@return number
function W.Lerp(a, b, t)
	return a + (b - a) * t
end

---Blend two colors
---@param a number[]
---@param b number[]
---@param t number 0 gives a, 1 gives b
---@return number[]
function W.Mix(a, b, t)
	return { W.Lerp(a[1], b[1], t), W.Lerp(a[2], b[2], t), W.Lerp(a[3], b[3], t), W.Lerp(a[4] or 1, b[4] or 1, t) }
end

---@return number[]
function W.Accent()
	local r, g, b = Style:GetAccent()
	return { r, g, b, 1 }
end

---Lighten a color toward white
---@param color number[]
---@param amount number
---@return number[]
function W.Lift(color, amount)
	return { math.min(1, color[1] + amount), math.min(1, color[2] + amount), math.min(1, color[3] + amount), color[4] or 1 }
end

---Text without color codes, textures or atlas markup, for searching
---@param text any
---@return string
function W.PlainText(text)
	if type(text) ~= 'string' then
		return tostring(text or '')
	end
	local plain = text:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', ''):gsub('|T.-|t', ''):gsub('|A.-|a', '')
	return plain
end

---@param parent Frame
---@param layer? DrawLayer
---@param sublevel? number
---@return Texture
function W:CreateRect(parent, layer, sublevel)
	local tex = parent:CreateTexture(nil, layer or 'ARTWORK', nil, sublevel)
	tex:SetTexture(Style.WHITE)
	return tex
end

---A flat texture clipped to a circle by a mask
---@param parent Frame
---@param layer? DrawLayer
---@param sublevel? number
---@return Texture
function W:CreateDisc(parent, layer, sublevel)
	local tex = self:CreateRect(parent, layer, sublevel)
	local mask = parent:CreateMaskTexture()
	mask:SetTexture(self.CIRCLE_MASK, 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE')
	mask:SetAllPoints(tex)
	tex:AddMaskTexture(mask)
	return tex
end

----------------------------------------------------------------------------------------------------
-- Glyphs drawn from whole-pixel rectangles
----------------------------------------------------------------------------------------------------

---@class SUI.UI.OptionWidgets.Arrow
---@field anchor Texture Position this to place the arrow
---@field parts Texture[]
---@field rows number
---@field direction string
local ArrowMixin = {}

---@param direction 'DOWN'|'UP'|'RIGHT'|'LEFT'
function ArrowMixin:SetDirection(direction)
	self.direction = direction
	self:Layout()
end

function ArrowMixin:SetColor(r, g, b, a)
	for _, part in ipairs(self.parts) do
		part:SetVertexColor(r, g, b, a or 1)
	end
end

function ArrowMixin:SetShown(shown)
	for _, part in ipairs(self.parts) do
		part:SetShown(shown)
	end
end

function ArrowMixin:Layout()
	local px = Style:PixelSize(self.parent)
	local n = self.rows
	local long = (2 * n - 1) * px
	local horizontal = self.direction == 'RIGHT' or self.direction == 'LEFT'
	if horizontal then
		self.anchor:SetSize(n * px, long)
	else
		self.anchor:SetSize(long, n * px)
	end
	for i, part in ipairs(self.parts) do
		local size = (2 * (n - i) + 1) * px
		part:ClearAllPoints()
		if self.direction == 'DOWN' then
			part:SetSize(size, px)
			part:SetPoint('TOP', self.anchor, 'TOP', 0, -(i - 1) * px)
		elseif self.direction == 'UP' then
			part:SetSize(size, px)
			part:SetPoint('BOTTOM', self.anchor, 'BOTTOM', 0, (i - 1) * px)
		elseif self.direction == 'RIGHT' then
			part:SetSize(px, size)
			part:SetPoint('LEFT', self.anchor, 'LEFT', (i - 1) * px, 0)
		else
			part:SetSize(px, size)
			part:SetPoint('RIGHT', self.anchor, 'RIGHT', -(i - 1) * px, 0)
		end
	end
end

---A small solid triangle, e.g. for dropdowns and fold-outs
---@param parent Frame
---@param rows? number Height in physical pixels (default 4)
---@param layer? DrawLayer
---@return SUI.UI.OptionWidgets.Arrow
function W:CreateArrow(parent, rows, layer)
	local arrow = { parent = parent, rows = rows or 4, parts = {}, direction = 'DOWN' }
	arrow.anchor = parent:CreateTexture(nil, layer or 'ARTWORK')
	for i = 1, arrow.rows do
		arrow.parts[i] = self:CreateRect(parent, layer or 'ARTWORK')
	end
	Mixin(arrow, ArrowMixin)
	arrow:Layout()
	return arrow
end

---@class SUI.UI.OptionWidgets.PlusMinus
---@field anchor Texture
---@field across Texture
---@field down Texture
local PlusMinusMixin = {}

---@param expanded boolean Shows a minus when true, a plus otherwise
function PlusMinusMixin:SetExpanded(expanded)
	self.down:SetShown(not expanded)
end

function PlusMinusMixin:SetColor(r, g, b, a)
	self.across:SetVertexColor(r, g, b, a or 1)
	self.down:SetVertexColor(r, g, b, a or 1)
end

function PlusMinusMixin:Layout()
	local px = Style:PixelSize(self.parent)
	local arm = 7 * px
	self.anchor:SetSize(arm, arm)
	self.across:ClearAllPoints()
	self.across:SetPoint('CENTER', self.anchor)
	self.across:SetSize(arm, px)
	self.down:ClearAllPoints()
	self.down:SetPoint('CENTER', self.anchor)
	self.down:SetSize(px, arm)
end

---@param parent Frame
---@param layer? DrawLayer
---@return SUI.UI.OptionWidgets.PlusMinus
function W:CreatePlusMinus(parent, layer)
	local glyph = { parent = parent }
	glyph.anchor = parent:CreateTexture(nil, layer or 'ARTWORK')
	glyph.across = self:CreateRect(parent, layer or 'ARTWORK')
	glyph.down = self:CreateRect(parent, layer or 'ARTWORK')
	Mixin(glyph, PlusMinusMixin)
	glyph:Layout()
	return glyph
end

----------------------------------------------------------------------------------------------------
-- Flat scrollbar
----------------------------------------------------------------------------------------------------

---@class SUI.UI.OptionWidgets.ScrollBar : Slider
---@field track Texture
---@field thumb Texture
---@field thumbFill Texture
---@field hovered boolean
---@field dragging boolean
---@field thumbRatio number

local function PaintScrollBar(bar)
	if bar.hovered or bar.dragging then
		W.Paint(bar.thumbFill, W.Accent(), 0.9)
	else
		W.Paint(bar.thumbFill, Style.color.muted, 0.45)
	end
end

local ScrollBarMixin = {}

---Size the thumb to the visible share of the content
---@param ratio number Visible height divided by content height
function ScrollBarMixin:SetThumbRatio(ratio)
	self.thumbRatio = ratio
	local height = self:GetHeight() or 0
	local thumb = 24
	if height > 0 and ratio and ratio > 0 then
		thumb = math.max(24, math.min(height, height * ratio))
	end
	self.thumb:SetHeight(thumb)
end

---Thin vertical scrollbar: faint track, muted thumb that turns accent on hover
---@param parent Frame
---@param name? string
---@return SUI.UI.OptionWidgets.ScrollBar
function W:CreateScrollBar(parent, name)
	local bar = CreateFrame('Slider', name, parent) ---@type SUI.UI.OptionWidgets.ScrollBar
	Mixin(bar, ScrollBarMixin)
	bar:SetOrientation('VERTICAL')
	bar:SetWidth(10)
	bar:SetMinMaxValues(0, 1000)
	bar:SetValueStep(1)
	bar:SetValue(0)

	bar.track = self:CreateRect(bar, 'BACKGROUND')
	bar.track:SetPoint('TOP')
	bar.track:SetPoint('BOTTOM')
	bar.track:SetWidth(2)
	W.Paint(bar.track, Style.color.line)

	-- The real thumb is an invisible hit area; the visible bar inside it is thinner
	bar.thumb = self:CreateRect(bar, 'ARTWORK')
	bar.thumb:SetSize(10, 24)
	bar.thumb:SetAlpha(0)
	bar:SetThumbTexture(bar.thumb)
	bar.thumbFill = self:CreateRect(bar, 'OVERLAY')
	bar.thumbFill:SetPoint('TOP', bar.thumb, 'TOP')
	bar.thumbFill:SetPoint('BOTTOM', bar.thumb, 'BOTTOM')
	bar.thumbFill:SetWidth(4)

	bar:SetScript('OnEnter', function(self)
		self.hovered = true
		PaintScrollBar(self)
	end)
	bar:SetScript('OnLeave', function(self)
		self.hovered = false
		PaintScrollBar(self)
	end)
	bar:SetScript('OnMouseDown', function(self)
		self.dragging = true
		PaintScrollBar(self)
	end)
	bar:SetScript('OnMouseUp', function(self)
		self.dragging = false
		PaintScrollBar(self)
	end)
	bar:HookScript('OnSizeChanged', function(self)
		if self.thumbRatio then
			self:SetThumbRatio(self.thumbRatio)
		end
	end)
	Style:OnAccentChanged(bar, function()
		PaintScrollBar(bar)
	end)
	return bar
end

----------------------------------------------------------------------------------------------------
-- Input box skin
----------------------------------------------------------------------------------------------------

---@class SUI.UI.OptionWidgets.Box
---@field fill Texture
---@field border SUI.UI.Style.Border

---Paint a flat input box: input fill, hairline border that shows hover and focus
---@param box table Frame with .fill and .border from SkinBox
---@param state 'normal'|'hover'|'focus'|'disabled'
function W.PaintBox(box, state)
	local c = Style.color
	if state == 'focus' then
		local r, g, b = Style:GetAccent()
		box.border:SetColor(r, g, b, 1)
		W.Paint(box.fill, c.input)
	elseif state == 'hover' then
		box.border:SetColor(1, 1, 1, 0.28)
		W.Paint(box.fill, c.input)
	elseif state == 'disabled' then
		box.border:SetColor(c.line[1], c.line[2], c.line[3], c.line[4])
		W.Paint(box.fill, c.input, 0.2)
	else
		box.border:SetColor(c.lineStrong[1], c.lineStrong[2], c.lineStrong[3], c.lineStrong[4])
		W.Paint(box.fill, c.input)
	end
end

---Give a frame an input fill and a 1px border
---@param frame Frame
function W:SkinBox(frame)
	frame.fill = Style:CreateFill(frame, Style.color.input)
	frame.border = Style:CreateBorder(frame)
	W.PaintBox(frame, 'normal')
end

---Is the mouse over any of the given frames
---@param ... Frame|nil
---@return boolean
function W.MouseOverAny(...)
	for i = 1, select('#', ...) do
		local frame = select(i, ...)
		if frame and frame:IsVisible() and frame:IsMouseOver() then
			return true
		end
	end
	return false
end

---Call `fn` on the next mouse click anywhere, while `frame` is shown. Returns false when the
---client has no global mouse event, so the caller can fall back.
---@param frame Frame
---@param fn fun(button: string)
---@return boolean
function W.WatchGlobalClicks(frame, fn)
	local ok = pcall(frame.RegisterEvent, frame, 'GLOBAL_MOUSE_DOWN')
	if not ok then
		return false
	end
	frame:SetScript('OnEvent', function(_, event, button)
		if event == 'GLOBAL_MOUSE_DOWN' then
			fn(button)
		end
	end)
	return true
end
