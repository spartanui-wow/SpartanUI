---@class SUI
local SUI = SUI
---@class MoveIt
local MoveIt = SUI.MoveIt
local Style = SUI.UI.Style

-- Small flat controls shared by the top bar and the frame inspector

---@class SUI.MoveIt.Widgets
local Widgets = {}
MoveIt.Widgets = Widgets

---@class SUI.MoveIt.Button : Button
---@field label FontString
---@field fill Texture
---@field border SUI.UI.Style.Border
---@field primary boolean
---@field active boolean

local function PaintButton(button)
	local c = Style.color
	local r, g, b = Style:GetAccent()
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
function Widgets:MeasureText(text)
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
	self:SetWidth(self.fixedWidth or math.max(48, Widgets:MeasureText(self.label) + 18))
end

---Create a flat button
---@param parent Frame
---@param text string
---@param width? number Fixed width; sized to the text when omitted
---@param onClick? fun(button: SUI.MoveIt.Button, mouseButton: string)
---@param primary? boolean Filled with the accent color
---@return SUI.MoveIt.Button
function Widgets:Button(parent, text, width, onClick, primary)
	local button = CreateFrame('Button', nil, parent) ---@type SUI.MoveIt.Button
	Mixin(button, ButtonMixin)
	button:SetHeight(22)
	button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
	button.fill = Style:CreateFill(button, Style.color.raised)
	button.border = Style:CreateBorder(button)
	button.label = Style:CreateText(button, 11)
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

---@class SUI.MoveIt.NumberBox : EditBox
---@field onCommit fun(value: number)

---Create a small numeric edit box. Enter or losing focus commits the value.
---@param parent Frame
---@param width number
---@param onCommit fun(value: number)
---@return SUI.MoveIt.NumberBox
function Widgets:NumberBox(parent, width, onCommit)
	local box = CreateFrame('EditBox', nil, parent) ---@type SUI.MoveIt.NumberBox
	box:SetSize(width, 20)
	box:SetAutoFocus(false)
	box:SetJustifyH('CENTER')
	box:SetTextInsets(4, 4, 0, 0)
	Style:SetFont(box, 11)
	box:SetTextColor(Style.color.text[1], Style.color.text[2], Style.color.text[3])
	box.fill = Style:CreateFill(box, Style.color.input)
	box.border = Style:CreateBorder(box)
	box.border:SetColor(unpack(Style.color.lineStrong))
	box.onCommit = onCommit

	local function Commit(self)
		local value = tonumber(self:GetText())
		if value and self.onCommit then
			self.onCommit(value)
		end
		self:ClearFocus()
	end
	box:SetScript('OnEnterPressed', Commit)
	box:SetScript('OnEscapePressed', function(self)
		self:ClearFocus()
	end)
	box:SetScript('OnEditFocusGained', function(self)
		local r, g, b = Style:GetAccent()
		self.border:SetColor(r, g, b, 1)
		self:HighlightText()
	end)
	box:SetScript('OnEditFocusLost', function(self)
		self.border:SetColor(unpack(Style.color.lineStrong))
		self:HighlightText(0, 0)
	end)
	return box
end

---Create a thin horizontal rule
---@param parent Frame
---@return Texture
function Widgets:Rule(parent)
	local rule = parent:CreateTexture(nil, 'ARTWORK')
	rule:SetTexture(Style.WHITE)
	rule:SetVertexColor(unpack(Style.color.line))
	rule:SetHeight(Style:PixelSize(parent))
	return rule
end

---Small section caption in muted uppercase
---@param parent Frame
---@param text string
---@return FontString
function Widgets:Caption(parent, text)
	local caption = Style:CreateText(parent, 9, Style.color.faint)
	caption:SetText(text:upper())
	return caption
end
