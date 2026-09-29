---@class SUI
local SUI = SUI
local Style = SUI.UI.Style
local W = SUI.UI.OptionWidgets

-- Slider replacement: label and a typeable value box on top, a thin track with an accent fill
-- and a round knob below. Same methods, callbacks and events as the stock AceGUI Slider.

local Type, Version = 'SUI-Slider', 1
local AceGUI = LibStub and LibStub('AceGUI-3.0', true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then
	return
end

local min, max, floor = math.min, math.max, math.floor
local tonumber = tonumber

local KNOB = 12
local KNOB_ACTIVE = 14
local THUMB_W = 16
local VALUE_W = 56

----------------------------------------------------------------------------------------------------
-- Support functions
----------------------------------------------------------------------------------------------------

local function UpdateText(self)
	local value = self.value or 0
	if self.ispercent then
		self.editbox:SetText(('%s%%'):format(floor(value * 1000 + 0.5) / 10))
	else
		self.editbox:SetText(floor(value * 100 + 0.5) / 100)
	end
end

local function UpdateLabels(self)
	local min_value, max_value = (self.min or 0), (self.max or 100)
	if self.ispercent then
		self.lowtext:SetFormattedText('%s%%', (min_value * 100))
		self.hightext:SetFormattedText('%s%%', (max_value * 100))
	else
		self.lowtext:SetText(min_value)
		self.hightext:SetText(max_value)
	end
end

local function Paint(self)
	local c = Style.color
	local accent = W.Accent()
	if self.disabled then
		W.Paint(self.label, c.faint)
		W.Paint(self.fill, c.faint, 0.5)
		W.Paint(self.knob, c.faint)
		W.Paint(self.track, c.input)
		self.editbox:SetTextColor(c.faint[1], c.faint[2], c.faint[3])
		W.PaintBox(self.valuebox, 'disabled')
	else
		W.Paint(self.label, c.text)
		W.Paint(self.fill, accent)
		W.Paint(self.knob, (self.hovered or self.dragging) and W.Lift(accent, 0.15) or accent)
		W.Paint(self.track, W.color.trackOff)
		self.editbox:SetTextColor(c.text[1], c.text[2], c.text[3])
		W.PaintBox(self.valuebox, self.editbox:HasFocus() and 'focus' or (self.boxHovered and 'hover' or 'normal'))
	end
	local size = (self.hovered or self.dragging) and not self.disabled and KNOB_ACTIVE or KNOB
	self.knob:SetSize(size, size)
end

---Stock step for the wheel is `step or 1`, which never moves when step is 0
local function WheelStep(self)
	if self.step and self.step > 0 then
		return self.step
	end
	local range = (self.max or 100) - (self.min or 0)
	return range > 0 and range / 100 or 1
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

local function Frame_OnMouseDown(frame)
	frame.obj.slider:EnableMouseWheel(true)
	AceGUI:ClearFocus()
end

local function Slider_OnMouseDown(frame)
	local self = frame.obj
	self.dragging = true
	frame:EnableMouseWheel(true)
	AceGUI:ClearFocus()
	Paint(self)
end

local function Slider_OnValueChanged(frame, newvalue)
	local self = frame.obj
	if not frame.setup then
		if self.step and self.step > 0 then
			local min_value = self.min or 0
			newvalue = floor((newvalue - min_value) / self.step + 0.5) * self.step + min_value
		end
		if newvalue ~= self.value and not self.disabled then
			self.value = newvalue
			self:Fire('OnValueChanged', newvalue)
		end
		if self.value then
			UpdateText(self)
		end
	end
end

local function Slider_OnMouseUp(frame)
	local self = frame.obj
	self.dragging = false
	Paint(self)
	self:Fire('OnMouseUp', self.value)
end

local function Slider_OnMouseWheel(frame, v)
	local self = frame.obj
	if not self.disabled then
		local value = self.value or 0
		if v > 0 then
			value = min(value + WheelStep(self), self.max or 100)
		else
			value = max(value - WheelStep(self), self.min or 0)
		end
		self.slider:SetValue(value)
	end
end

local function EditBox_OnEscapePressed(frame)
	UpdateText(frame.obj)
	frame:ClearFocus()
end

local function EditBox_OnEnterPressed(frame)
	local self = frame.obj
	local value = frame:GetText()
	if self.ispercent then
		value = value:gsub('%%', '')
		value = tonumber(value)
		value = value and value / 100
	else
		value = tonumber(value)
	end

	if value then
		W.Sound(856) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
		self.slider:SetValue(value)
		self:Fire('OnMouseUp', value)
	else
		UpdateText(self)
	end
	frame:ClearFocus()
end

local function EditBox_OnEnter(frame)
	local self = frame.obj
	self.boxHovered = true
	Paint(self)
	self:Fire('OnEnter')
end

local function EditBox_OnLeave(frame)
	local self = frame.obj
	self.boxHovered = false
	Paint(self)
	self:Fire('OnLeave')
end

local function EditBox_OnFocusGained(frame)
	frame:HighlightText()
	Paint(frame.obj)
end

local function EditBox_OnFocusLost(frame)
	frame:HighlightText(0, 0)
	Paint(frame.obj)
end

----------------------------------------------------------------------------------------------------
-- Methods
----------------------------------------------------------------------------------------------------

local methods = {
	OnAcquire = function(self)
		self.hovered, self.dragging, self.boxHovered = false, false, false
		self:SetWidth(200)
		self:SetHeight(W.LABELED_HEIGHT)
		self:SetDisabled(false)
		self:SetIsPercent(nil)
		self:SetSliderValues(0, 100, 1)
		self:SetValue(0)
		self.slider:EnableMouseWheel(false)
	end,

	OnRelease = function(self)
		self.editbox:ClearFocus()
		self.hovered, self.dragging, self.boxHovered = false, false, false
	end,

	SetDisabled = function(self, disabled)
		self.disabled = disabled
		if disabled then
			self.slider:EnableMouse(false)
			self.editbox:EnableMouse(false)
			self.editbox:ClearFocus()
			self.hovered, self.dragging = false, false
		else
			self.slider:EnableMouse(true)
			self.editbox:EnableMouse(true)
		end
		Paint(self)
	end,

	SetValue = function(self, value)
		self.slider.setup = true
		self.slider:SetValue(value)
		self.value = value
		UpdateText(self)
		self.slider.setup = nil
	end,

	GetValue = function(self)
		return self.value
	end,

	SetLabel = function(self, text)
		self.label:SetText(text)
	end,

	SetSliderValues = function(self, min_value, max_value, step)
		local frame = self.slider
		frame.setup = true
		self.min = min_value
		self.max = max_value
		self.step = step
		frame:SetMinMaxValues(min_value or 0, max_value or 100)
		UpdateLabels(self)
		frame:SetValueStep(step or 1)
		if self.value then
			frame:SetValue(self.value)
		end
		frame.setup = nil
	end,

	SetIsPercent = function(self, value)
		self.ispercent = value
		UpdateLabels(self)
		UpdateText(self)
	end,
}

----------------------------------------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------------------------------------

local function Constructor()
	local frame = CreateFrame('Frame', nil, UIParent)
	frame:Hide()

	frame:EnableMouse(true)
	frame:SetScript('OnMouseDown', Frame_OnMouseDown)

	local label = Style:CreateText(frame, W.LABEL_SIZE)
	label:SetPoint('TOPLEFT', 0, 0)
	label:SetPoint('TOPRIGHT', -(VALUE_W + 6), 0)
	label:SetJustifyH('LEFT')
	label:SetWordWrap(false)
	label:SetHeight(20)

	-- Value box on the label row
	local valuebox = CreateFrame('Frame', nil, frame)
	valuebox:SetSize(VALUE_W, 20)
	valuebox:SetPoint('TOPRIGHT', 0, 0)
	W:SkinBox(valuebox)

	local editbox = CreateFrame('EditBox', nil, valuebox)
	editbox:SetAllPoints()
	editbox:SetAutoFocus(false)
	editbox:SetJustifyH('CENTER')
	editbox:SetTextInsets(4, 4, 0, 0)
	editbox:SetMaxLetters(12)
	Style:SetFont(editbox, W.SMALL_SIZE)
	editbox:EnableMouse(true)
	editbox:SetScript('OnEnter', EditBox_OnEnter)
	editbox:SetScript('OnLeave', EditBox_OnLeave)
	editbox:SetScript('OnEnterPressed', EditBox_OnEnterPressed)
	editbox:SetScript('OnEscapePressed', EditBox_OnEscapePressed)
	editbox:SetScript('OnEditFocusGained', EditBox_OnFocusGained)
	editbox:SetScript('OnEditFocusLost', EditBox_OnFocusLost)

	-- The track row is centered on W.LABELED_ALIGN so it lines up with input boxes in the same row
	local slider = CreateFrame('Slider', nil, frame)
	slider:SetOrientation('HORIZONTAL')
	slider:SetHeight(18)
	slider:SetPoint('TOPLEFT', 0, -(W.LABELED_ALIGN - 9))
	slider:SetPoint('TOPRIGHT', 0, -(W.LABELED_ALIGN - 9))
	slider:SetHitRectInsets(0, 0, -4, -4)
	if slider.SetObeyStepOnDrag then
		slider:SetObeyStepOnDrag(true)
	end

	local track = W:CreateRect(slider, 'BACKGROUND')
	track:SetHeight(4)
	track:SetPoint('LEFT', THUMB_W / 2, 0)
	track:SetPoint('RIGHT', -THUMB_W / 2, 0)

	-- Invisible thumb hit area; the visible knob and fill follow it
	local thumb = W:CreateRect(slider, 'ARTWORK')
	thumb:SetSize(THUMB_W, 18)
	thumb:SetAlpha(0)
	slider:SetThumbTexture(thumb)

	local fill = W:CreateRect(slider, 'ARTWORK', 1)
	fill:SetHeight(4)
	fill:SetPoint('LEFT', track, 'LEFT')
	fill:SetPoint('RIGHT', thumb, 'CENTER')

	local knob = W:CreateDisc(slider, 'OVERLAY')
	knob:SetSize(KNOB, KNOB)
	knob:SetPoint('CENTER', thumb, 'CENTER')

	slider:SetValue(0)
	slider:SetScript('OnValueChanged', Slider_OnValueChanged)
	slider:SetScript('OnEnter', Control_OnEnter)
	slider:SetScript('OnLeave', Control_OnLeave)
	slider:SetScript('OnMouseDown', Slider_OnMouseDown)
	slider:SetScript('OnMouseUp', Slider_OnMouseUp)
	slider:SetScript('OnMouseWheel', Slider_OnMouseWheel)

	-- Kept for code that reads the stock fields; the range is not drawn
	local lowtext = Style:CreateText(slider, 9, Style.color.faint)
	lowtext:SetPoint('TOPLEFT', slider, 'BOTTOMLEFT', 0, 0)
	lowtext:Hide()
	local hightext = Style:CreateText(slider, 9, Style.color.faint)
	hightext:SetPoint('TOPRIGHT', slider, 'BOTTOMRIGHT', 0, 0)
	hightext:Hide()

	local widget = {
		label = label,
		slider = slider,
		track = track,
		fill = fill,
		knob = knob,
		lowtext = lowtext,
		hightext = hightext,
		editbox = editbox,
		valuebox = valuebox,
		alignoffset = W.LABELED_ALIGN,
		frame = frame,
		type = Type,
	}
	for method, func in pairs(methods) do
		widget[method] = func
	end
	slider.obj, editbox.obj = widget, widget
	-- An edit box shows no text until its font has been drawn once
	C_Timer.After(0.3, function()
		editbox:SetText(' ')
		UpdateText(widget)
	end)
	Style:OnAccentChanged(frame, function()
		Paint(widget)
	end)

	return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
