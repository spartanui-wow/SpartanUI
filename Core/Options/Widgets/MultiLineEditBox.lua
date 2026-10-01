---@class SUI
local SUI = SUI
local Style = SUI.UI.Style
local W = SUI.UI.OptionWidgets

-- MultiLineEditBox replacement: the flat input box grown to several lines, with a thin scrollbar
-- and an accent "Accept" button below. Same methods, callbacks and events as the stock AceGUI
-- MultiLineEditBox.

local Type, Version = 'SUI-MultiLineEditBox', 1
local AceGUI = LibStub and LibStub('AceGUI-3.0', true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then
	return
end

local _G = _G

local BOX_NAME = 'SUI_OptionsMultiLineEditBox'
local LINE_H = 14
local PAD = 6
local LABEL_H = 20
local BUTTON_H = 22

----------------------------------------------------------------------------------------------------
-- Support functions
----------------------------------------------------------------------------------------------------

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
	elseif self.editBox:HasFocus() then
		state = 'focus'
	elseif self.hovered then
		state = 'hover'
	end
	W.PaintBox(self.box, state)
	local textColor = self.disabled and c.faint or c.text
	self.editBox:SetTextColor(textColor[1], textColor[2], textColor[3])
	W.Paint(self.label, self.disabled and c.faint or c.text)
end

local function Layout(self)
	local labelHeight = self.label:IsShown() and LABEL_H or 0
	local buttonHeight = self.disablebutton and 0 or (BUTTON_H + 4)
	self:SetHeight(labelHeight + self.numlines * LINE_H + PAD * 2 + buttonHeight)
	self.box:ClearAllPoints()
	self.box:SetPoint('TOPLEFT', 0, -labelHeight)
	self.box:SetPoint('TOPRIGHT', 0, -labelHeight)
	self.box:SetPoint('BOTTOM', 0, buttonHeight)
end

local function UpdateScrollBar(self)
	local scrollFrame, bar = self.scrollFrame, self.scrollBar
	local range = scrollFrame:GetVerticalScrollRange() or 0
	local height = scrollFrame:GetHeight() or 0
	self.updating = true
	if range > 0 then
		bar:SetMinMaxValues(0, range)
		bar:SetValue(scrollFrame:GetVerticalScroll())
		bar:SetThumbRatio(height / (height + range))
		bar:Show()
	else
		bar:Hide()
	end
	self.updating = false
end

----------------------------------------------------------------------------------------------------
-- Scripts
----------------------------------------------------------------------------------------------------

local function Button_OnClick(button)
	local self = button.obj
	self.editBox:ClearFocus()
	if not self:Fire('OnEnterPressed', self.editBox:GetText()) then
		W.Sound(856) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
		self.button:Disable()
	end
end

local function Control_OnEnter(frame)
	local self = frame.obj
	if not self.hovered then
		self.hovered = true
		Paint(self)
		self:Fire('OnEnter')
	end
end

local function Control_OnLeave(frame)
	local self = frame.obj
	if self.hovered then
		self.hovered = false
		Paint(self)
		self:Fire('OnLeave')
	end
end

local function EditBox_OnCursorChanged(editBox, _, y, _, cursorHeight)
	local scrollFrame = editBox.obj.scrollFrame
	y = -y
	local offset = scrollFrame:GetVerticalScroll()
	if y < offset then
		scrollFrame:SetVerticalScroll(y)
	else
		y = y + cursorHeight - scrollFrame:GetHeight()
		if y > offset then
			scrollFrame:SetVerticalScroll(y)
		end
	end
end

local function EditBox_OnTextChanged(editBox, userInput)
	if userInput then
		local self = editBox.obj
		self:Fire('OnTextChanged', editBox:GetText())
		self.button:Enable()
	end
end

local function EditBox_OnTextSet(editBox)
	editBox:HighlightText(0, 0)
	editBox:SetCursorPosition(editBox:GetNumLetters())
	editBox:SetCursorPosition(0)
	editBox.obj.button:Disable()
end

local function EditBox_OnFocusGained(editBox)
	AceGUI:SetFocus(editBox.obj)
	Paint(editBox.obj)
	editBox.obj:Fire('OnEditFocusGained')
end

local function EditBox_OnFocusLost(editBox)
	editBox:HighlightText(0, 0)
	Paint(editBox.obj)
	editBox.obj:Fire('OnEditFocusLost')
end

local function EditBox_OnEscapePressed(editBox)
	AceGUI:ClearFocus()
end

local function OnReceiveDrag(frame)
	local cursorType, id, info, extra = GetCursorInfo()
	if cursorType == 'spell' then
		if C_Spell and C_Spell.GetSpellName then
			info = C_Spell.GetSpellName(extra)
		else
			info = GetSpellInfo(id, info)
		end
	elseif cursorType ~= 'item' then
		return
	end
	ClearCursor()
	local self = frame.obj
	local editBox = self.editBox
	if not editBox:HasFocus() then
		editBox:SetFocus()
		editBox:SetCursorPosition(editBox:GetNumLetters())
	end
	editBox:Insert(info)
	self.button:Enable()
end

local function ScrollFrame_OnMouseUp(scrollFrame)
	local editBox = scrollFrame.obj.editBox
	if scrollFrame.obj.disabled then
		return
	end
	editBox:SetFocus()
	editBox:SetCursorPosition(editBox:GetNumLetters())
end

local function ScrollFrame_OnMouseWheel(scrollFrame, delta)
	local range = scrollFrame:GetVerticalScrollRange() or 0
	local value = math.max(0, math.min(range, scrollFrame:GetVerticalScroll() - delta * LINE_H * 3))
	scrollFrame:SetVerticalScroll(value)
end

local function ScrollFrame_OnSizeChanged(scrollFrame, width)
	scrollFrame.obj.editBox:SetWidth(width)
	UpdateScrollBar(scrollFrame.obj)
end

local function ScrollFrame_OnVerticalScroll(scrollFrame, offset)
	local self = scrollFrame.obj
	local editBox = self.editBox
	editBox:SetHitRectInsets(0, 0, offset, editBox:GetHeight() - offset - scrollFrame:GetHeight())
	UpdateScrollBar(self)
end

local function ScrollFrame_OnScrollRangeChanged(scrollFrame, _, yrange)
	if yrange == 0 then
		scrollFrame.obj.editBox:SetHitRectInsets(0, 0, 0, 0)
	else
		ScrollFrame_OnVerticalScroll(scrollFrame, scrollFrame:GetVerticalScroll())
	end
	UpdateScrollBar(scrollFrame.obj)
end

local function ScrollBar_OnValueChanged(bar, value)
	local self = bar.obj
	if not self.updating then
		self.scrollFrame:SetVerticalScroll(value)
	end
end

local function Frame_OnShowFocus(frame)
	frame.obj.editBox:SetFocus()
	frame:SetScript('OnShow', nil)
end

----------------------------------------------------------------------------------------------------
-- Methods
----------------------------------------------------------------------------------------------------

local methods = {
	OnAcquire = function(self)
		self.hovered = false
		self.editBox:SetText('')
		self:SetDisabled(false)
		self:SetWidth(200)
		self:SetLabel()
		self:DisableButton(false)
		self:SetNumLines()
		self:SetMaxLetters(0)
	end,

	OnRelease = function(self)
		self:ClearFocus()
		self.hovered = false
	end,

	SetDisabled = function(self, disabled)
		self.disabled = disabled
		local editBox = self.editBox
		if disabled then
			editBox:ClearFocus()
			editBox:EnableMouse(false)
			self.scrollFrame:EnableMouse(false)
			self.button:Disable()
		else
			editBox:EnableMouse(true)
			self.scrollFrame:EnableMouse(true)
		end
		Paint(self)
	end,

	SetLabel = function(self, text)
		if text and text ~= '' then
			self.label:SetText(text)
			self.label:Show()
		else
			self.label:SetText('')
			self.label:Hide()
		end
		Layout(self)
	end,

	SetNumLines = function(self, value)
		if not value or value < 4 then
			value = 4
		end
		self.numlines = value
		Layout(self)
	end,

	SetText = function(self, text)
		self.editBox:SetText(text or '')
	end,

	GetText = function(self)
		return self.editBox:GetText()
	end,

	SetMaxLetters = function(self, num)
		self.editBox:SetMaxLetters(num or 0)
	end,

	DisableButton = function(self, disabled)
		self.disablebutton = disabled
		self.button:SetShown(not disabled)
		Layout(self)
	end,

	ClearFocus = function(self)
		self.editBox:ClearFocus()
		self.frame:SetScript('OnShow', nil)
	end,

	SetFocus = function(self)
		self.editBox:SetFocus()
		if not self.frame:IsShown() then
			self.frame:SetScript('OnShow', Frame_OnShowFocus)
		end
	end,

	HighlightText = function(self, from, to)
		self.editBox:HighlightText(from, to)
	end,

	GetCursorPosition = function(self)
		return self.editBox:GetCursorPosition()
	end,

	SetCursorPosition = function(self, ...)
		return self.editBox:SetCursorPosition(...)
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
	label:SetHeight(LABEL_H)

	local box = CreateFrame('Frame', nil, frame)
	W:SkinBox(box)

	local scrollFrame = CreateFrame('ScrollFrame', nil, box)
	scrollFrame:SetPoint('TOPLEFT', PAD, -PAD)
	scrollFrame:SetPoint('BOTTOMRIGHT', -(PAD + 12), PAD)
	scrollFrame:EnableMouseWheel(true)
	scrollFrame:SetScript('OnEnter', Control_OnEnter)
	scrollFrame:SetScript('OnLeave', Control_OnLeave)
	scrollFrame:SetScript('OnMouseUp', ScrollFrame_OnMouseUp)
	scrollFrame:SetScript('OnMouseWheel', ScrollFrame_OnMouseWheel)
	scrollFrame:SetScript('OnReceiveDrag', OnReceiveDrag)
	scrollFrame:SetScript('OnSizeChanged', ScrollFrame_OnSizeChanged)
	scrollFrame:HookScript('OnVerticalScroll', ScrollFrame_OnVerticalScroll)
	scrollFrame:HookScript('OnScrollRangeChanged', ScrollFrame_OnScrollRangeChanged)

	local editBox = CreateFrame('EditBox', BOX_NAME .. num, scrollFrame)
	editBox:SetAllPoints()
	editBox:SetMultiLine(true)
	editBox:SetAutoFocus(false)
	editBox:EnableMouse(true)
	editBox:SetCountInvisibleLetters(false)
	Style:SetFont(editBox, W.LABEL_SIZE)
	editBox:SetScript('OnCursorChanged', EditBox_OnCursorChanged)
	editBox:SetScript('OnEditFocusGained', EditBox_OnFocusGained)
	editBox:SetScript('OnEditFocusLost', EditBox_OnFocusLost)
	editBox:SetScript('OnEnter', Control_OnEnter)
	editBox:SetScript('OnLeave', Control_OnLeave)
	editBox:SetScript('OnEscapePressed', EditBox_OnEscapePressed)
	editBox:SetScript('OnMouseDown', OnReceiveDrag)
	editBox:SetScript('OnReceiveDrag', OnReceiveDrag)
	editBox:SetScript('OnTextChanged', EditBox_OnTextChanged)
	editBox:SetScript('OnTextSet', EditBox_OnTextSet)
	scrollFrame:SetScrollChild(editBox)

	local scrollBar = W:CreateScrollBar(box)
	scrollBar:SetPoint('TOPRIGHT', -4, -PAD)
	scrollBar:SetPoint('BOTTOMRIGHT', -4, PAD)
	scrollBar:SetScript('OnValueChanged', ScrollBar_OnValueChanged)
	scrollBar:Hide()

	local button = Style:CreateButton(frame, ACCEPT, nil, Button_OnClick, true)
	button:SetPoint('BOTTOMLEFT', 0, 0)
	button:Disable()

	local widget = {
		box = box,
		button = button,
		editBox = editBox,
		frame = frame,
		label = label,
		labelHeight = LABEL_H,
		numlines = 4,
		scrollBar = scrollBar,
		scrollFrame = scrollFrame,
		type = Type,
	}
	for method, func in pairs(methods) do
		widget[method] = func
	end
	button.obj, editBox.obj, scrollFrame.obj, scrollBar.obj = widget, widget, widget, widget
	Style:OnAccentChanged(frame, function()
		Paint(widget)
	end)

	return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
