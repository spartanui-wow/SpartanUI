---@class SUI
local SUI = SUI
---@class MoveIt
local MoveIt = SUI.MoveIt
local Style = SUI.UI.Style

-- Small flat controls shared by the top bar and the frame inspector

---@class SUI.MoveIt.Widgets
local Widgets = {}
MoveIt.Widgets = Widgets

---@alias SUI.MoveIt.Button SUI.UI.Style.Button

---@param text FontString
---@return number
function Widgets:MeasureText(text)
	return Style:MeasureText(text)
end

---Create a flat button
---@param parent Frame
---@param text string
---@param width? number
---@param onClick? fun(button: SUI.UI.Style.Button, mouseButton: string)
---@param primary? boolean
---@return SUI.UI.Style.Button
function Widgets:Button(parent, text, width, onClick, primary)
	return Style:CreateButton(parent, text, width, onClick, primary)
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
