---@class SUI
local SUI = SUI
local Style = SUI.UI.Style
local W = SUI.UI.OptionWidgets

-- EditBox replacement: a flat input with a hairline border that turns accent while typing.
-- The "Okay" button is a small accent button inside the box while there are unsaved edits.
-- Same methods, callbacks and events as the stock AceGUI EditBox.

local Type, Version = 'SUI-EditBox', 1
local AceGUI = LibStub and LibStub('AceGUI-3.0', true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then
	return
end

local tostring = tostring
local _G = _G

local BOX_NAME = 'SUI_OptionsEditBox'
local BUTTON_W = 34

----------------------------------------------------------------------------------------------------
-- Support functions
----------------------------------------------------------------------------------------------------

-- Shift-clicked links go into whichever of our boxes has focus
local function InsertLink(text)
	for i = 1, AceGUI:GetWidgetCount(Type) do
		local editbox = _G[BOX_NAME .. i]
		if editbox and editbox:IsVisible() and editbox:HasFocus() then
			editbox:Insert(text)
			return true
		end
	end
end
if ChatFrameUtil and ChatFrameUtil.InsertLink then
	hooksecurefunc(ChatFrameUtil, 'InsertLink', InsertLink)
elseif ChatEdit_InsertLink then
	hooksecurefunc('ChatEdit_InsertLink', InsertLink)
end

local function Paint(self)
	local c = Style.color
	local state = 'normal'
	if self.disabled then
		state = 'disabled'
	elseif self.editbox:HasFocus() then
		state = 'focus'
	elseif self.hovered then
		state = 'hover'
	end
	W.PaintBox(self.box, state)
	local textColor = self.disabled and c.faint or c.text
	self.editbox:SetTextColor(textColor[1], textColor[2], textColor[3])
	W.Paint(self.label, self.disabled and c.faint or c.text)

	local button = self.button
	local r, g, b = Style:GetAccent()
	local lift = button.hovered and 0.12 or 0
	button.fill:SetVertexColor(math.min(1, r + lift), math.min(1, g + lift), math.min(1, b + lift), 1)
	W.Paint(button.label, c.onAccent)
end

local function ShowButton(self)
	if not self.disablebutton then
		self.button:Show()
		self.editbox:SetTextInsets(6, BUTTON_W + 6, 0, 0)
	end
end

local function HideButton(self)
	self.button:Hide()
	self.editbox:SetTextInsets(6, 6, 0, 0)
end

----------------------------------------------------------------------------------------------------
-- Scripts
----------------------------------------------------------------------------------------------------

local function Control_OnEnter(frame)
	local self = frame.obj
	self.hovered = true
	Paint(self)
	self:Fire('OnEnter')
end

local function Control_OnLeave(frame)
	local self = frame.obj
	self.hovered = false
	Paint(self)
	self:Fire('OnLeave')
end

local function Frame_OnShowFocus(frame)
	frame.obj.editbox:SetFocus()
	frame:SetScript('OnShow', nil)
end

local function EditBox_OnEscapePressed(frame)
	AceGUI:ClearFocus()
end

local function EditBox_OnEnterPressed(frame)
	local self = frame.obj
	local value = frame:GetText()
	local cancel = self:Fire('OnEnterPressed', value)
	if not cancel then
		W.Sound(856) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
		HideButton(self)
	end
end

local function EditBox_OnReceiveDrag(frame)
	local self = frame.obj
	local cursorType, id, info, extra = GetCursorInfo()
	local name
	if cursorType == 'item' then
		name = info
	elseif cursorType == 'spell' then
		if C_Spell and C_Spell.GetSpellName then
			name = C_Spell.GetSpellName(extra)
		else
			name = GetSpellInfo(id, info)
		end
	elseif cursorType == 'macro' then
		name = GetMacroInfo(id)
	end
	if name then
		self:SetText(name)
		self:Fire('OnEnterPressed', name)
		ClearCursor()
		HideButton(self)
		AceGUI:ClearFocus()
	end
end

local function EditBox_OnTextChanged(frame)
	local self = frame.obj
	local value = frame:GetText()
	if tostring(value) ~= tostring(self.lasttext) then
		self:Fire('OnTextChanged', value)
		self.lasttext = value
		ShowButton(self)
	end
end

local function EditBox_OnFocusGained(frame)
	AceGUI:SetFocus(frame.obj)
	Paint(frame.obj)
end

local function EditBox_OnFocusLost(frame)
	Paint(frame.obj)
end

local function Button_OnClick(frame)
	local editbox = frame.obj.editbox
	editbox:ClearFocus()
	EditBox_OnEnterPressed(editbox)
end

local function Button_OnEnter(frame)
	frame.hovered = true
	Paint(frame.obj)
end

local function Button_OnLeave(frame)
	frame.hovered = false
	Paint(frame.obj)
end

----------------------------------------------------------------------------------------------------
-- Methods
----------------------------------------------------------------------------------------------------

local methods = {
	OnAcquire = function(self)
		-- height is controlled by SetLabel
		self.hovered = false
		self:SetWidth(200)
		self:SetDisabled(false)
		self:SetLabel()
		self:SetText()
		self:DisableButton(false)
		self:SetMaxLetters(0)
	end,

	OnRelease = function(self)
		self:ClearFocus()
		self.hovered = false
		self.button.hovered = false
	end,

	SetDisabled = function(self, disabled)
		self.disabled = disabled
		if disabled then
			self.editbox:EnableMouse(false)
			self.editbox:ClearFocus()
		else
			self.editbox:EnableMouse(true)
		end
		Paint(self)
	end,

	SetText = function(self, text)
		self.lasttext = text or ''
		self.editbox:SetText(text or '')
		self.editbox:SetCursorPosition(0)
		HideButton(self)
	end,

	GetText = function(self, text)
		return self.editbox:GetText()
	end,

	SetLabel = function(self, text)
		if text and text ~= '' then
			self.label:SetText(text)
			self.label:Show()
			self:SetHeight(W.LABELED_HEIGHT)
			self.alignoffset = W.LABELED_ALIGN
		else
			self.label:SetText('')
			self.label:Hide()
			self:SetHeight(W.UNLABELED_HEIGHT)
			self.alignoffset = W.UNLABELED_ALIGN
		end
	end,

	DisableButton = function(self, disabled)
		self.disablebutton = disabled
		if disabled then
			HideButton(self)
		end
	end,

	SetMaxLetters = function(self, num)
		self.editbox:SetMaxLetters(num or 0)
	end,

	ClearFocus = function(self)
		self.editbox:ClearFocus()
		self.frame:SetScript('OnShow', nil)
	end,

	SetFocus = function(self)
		self.editbox:SetFocus()
		if not self.frame:IsShown() then
			self.frame:SetScript('OnShow', Frame_OnShowFocus)
		end
	end,

	HighlightText = function(self, from, to)
		self.editbox:HighlightText(from, to)
	end,
}

----------------------------------------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------------------------------------

local function Constructor()
	local num = AceGUI:GetNextWidgetNum(Type)
	local frame = CreateFrame('Frame', nil, UIParent)
	frame:Hide()

	local label = Style:CreateText(frame, W.LABEL_SIZE)
	label:SetPoint('TOPLEFT', 0, 0)
	label:SetPoint('TOPRIGHT', 0, 0)
	label:SetJustifyH('LEFT')
	label:SetWordWrap(false)
	label:SetHeight(20)

	local box = CreateFrame('Frame', nil, frame)
	box:SetPoint('BOTTOMLEFT', 0, 0)
	box:SetPoint('BOTTOMRIGHT', 0, 0)
	box:SetHeight(W.INPUT_HEIGHT)
	W:SkinBox(box)

	local editbox = CreateFrame('EditBox', BOX_NAME .. num, box)
	editbox:SetAllPoints()
	editbox:SetAutoFocus(false)
	Style:SetFont(editbox, W.LABEL_SIZE)
	editbox:SetScript('OnEnter', Control_OnEnter)
	editbox:SetScript('OnLeave', Control_OnLeave)
	editbox:SetScript('OnEscapePressed', EditBox_OnEscapePressed)
	editbox:SetScript('OnEnterPressed', EditBox_OnEnterPressed)
	editbox:SetScript('OnTextChanged', EditBox_OnTextChanged)
	editbox:SetScript('OnReceiveDrag', EditBox_OnReceiveDrag)
	editbox:SetScript('OnMouseDown', EditBox_OnReceiveDrag)
	editbox:SetScript('OnEditFocusGained', EditBox_OnFocusGained)
	editbox:SetScript('OnEditFocusLost', EditBox_OnFocusLost)
	editbox:SetTextInsets(6, 6, 0, 0)
	editbox:SetMaxLetters(256)

	local button = CreateFrame('Button', nil, editbox)
	button:SetSize(BUTTON_W, W.INPUT_HEIGHT - 6)
	button:SetPoint('RIGHT', -3, 0)
	button.fill = Style:CreateFill(button, Style.color.raised)
	button.label = Style:CreateText(button, W.SMALL_SIZE)
	button.label:SetPoint('CENTER', 0, 0)
	button.label:SetText(OKAY)
	button:SetScript('OnClick', Button_OnClick)
	button:SetScript('OnEnter', Button_OnEnter)
	button:SetScript('OnLeave', Button_OnLeave)
	button:Hide()

	local widget = {
		alignoffset = W.LABELED_ALIGN,
		editbox = editbox,
		box = box,
		label = label,
		button = button,
		frame = frame,
		type = Type,
	}
	for method, func in pairs(methods) do
		widget[method] = func
	end
	editbox.obj, button.obj = widget, widget
	Style:OnAccentChanged(frame, function()
		Paint(widget)
	end)

	return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
