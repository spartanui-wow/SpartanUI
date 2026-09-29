---@class SUI
local SUI = SUI
local Style = SUI.UI.Style
local W = SUI.UI.OptionWidgets

-- A row of equal-width buttons for a select with 2 to 4 short choices; the chosen one is filled
-- with the accent color. Implements the part of the Dropdown API AceConfigDialog uses for a select.

local Type, Version = 'SUI-Segmented', 1
local AceGUI = LibStub and LibStub('AceGUI-3.0', true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then
	return
end

local pairs, ipairs, type, tostring, tonumber = pairs, ipairs, type, tostring, tonumber

local function sortTbl(x, y)
	local num1, num2 = tonumber(x), tonumber(y)
	if num1 and num2 then
		return num1 < num2
	else
		return tostring(x) < tostring(y)
	end
end

----------------------------------------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------------------------------------

local function PaintSegment(self, segment)
	local c = Style.color
	local accent = W.Accent()
	local key = segment.key
	local selected = key ~= nil and self.value == key
	local disabled = self.disabled or self.itemDisabled[key]
	if selected then
		local lift = (segment.hovered and not disabled) and 0.1 or 0
		W.Paint(segment.fill, W.Lift(accent, lift), disabled and 0.45 or 1)
		W.Paint(segment.text, c.onAccent, disabled and 0.7 or 1)
	else
		W.Paint(segment.fill, segment.hovered and not disabled and { 1, 1, 1, 0.06 } or { 1, 1, 1, 0 })
		if disabled then
			W.Paint(segment.text, c.faint)
		else
			W.Paint(segment.text, segment.hovered and c.text or W.Mix(c.text, c.muted, 0.35))
		end
	end
end

local function Paint(self)
	local c = Style.color
	W.PaintBox(self.box, self.disabled and 'disabled' or (self.hovered and 'hover' or 'normal'))
	W.Paint(self.label, self.disabled and c.faint or c.text)
	for i = 1, #self.order do
		PaintSegment(self, self.segments[i])
	end
	for i, divider in ipairs(self.dividers) do
		W.Paint(divider, c.lineStrong)
		divider:SetShown(i < #self.order)
	end
end

local function Layout(self)
	local count = #self.order
	local width = (self.frame.width or self.frame:GetWidth() or 200)
	local px = Style:PixelSize(self.box)
	local each = count > 0 and width / count or width
	for i, segment in ipairs(self.segments) do
		if i <= count then
			segment:ClearAllPoints()
			segment:SetPoint('TOPLEFT', self.box, 'TOPLEFT', (i - 1) * each, 0)
			segment:SetPoint('BOTTOMLEFT', self.box, 'BOTTOMLEFT', (i - 1) * each, 0)
			segment:SetWidth(each)
			segment:Show()
		else
			segment:Hide()
		end
	end
	for i, divider in ipairs(self.dividers) do
		divider:ClearAllPoints()
		divider:SetPoint('TOP', self.box, 'TOPLEFT', i * each, -px)
		divider:SetPoint('BOTTOM', self.box, 'BOTTOMLEFT', i * each, px)
		divider:SetWidth(px)
	end
end

----------------------------------------------------------------------------------------------------
-- Scripts
----------------------------------------------------------------------------------------------------

local function Segment_OnEnter(segment)
	local self = segment.obj
	segment.hovered = true
	self.hovered = true
	Paint(self)
	self:Fire('OnEnter')
end

local function Segment_OnLeave(segment)
	local self = segment.obj
	segment.hovered = false
	self.hovered = false
	Paint(self)
	self:Fire('OnLeave')
end

local function Segment_OnClick(segment)
	local self = segment.obj
	local key = segment.key
	AceGUI:ClearFocus()
	if self.disabled or key == nil or self.itemDisabled[key] or self.value == key then
		return
	end
	W.Sound(856) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
	self:SetValue(key)
	self:Fire('OnValueChanged', key)
end

local function CreateSegment(self, index)
	local segment = CreateFrame('Button', nil, self.box)
	segment.obj = self
	segment.fill = W:CreateRect(segment, 'BACKGROUND', 1)
	segment.fill:SetPoint('TOPLEFT', 1, -1)
	segment.fill:SetPoint('BOTTOMRIGHT', -1, 1)
	segment.text = Style:CreateText(segment, W.SMALL_SIZE)
	segment.text:SetPoint('LEFT', 4, 0)
	segment.text:SetPoint('RIGHT', -4, 0)
	segment.text:SetJustifyH('CENTER')
	segment.text:SetWordWrap(false)
	segment:SetScript('OnEnter', Segment_OnEnter)
	segment:SetScript('OnLeave', Segment_OnLeave)
	segment:SetScript('OnClick', Segment_OnClick)
	self.segments[index] = segment
	if index > 1 then
		local divider = W:CreateRect(self.box, 'ARTWORK', 2)
		self.dividers[index - 1] = divider
	end
	return segment
end

----------------------------------------------------------------------------------------------------
-- Methods
----------------------------------------------------------------------------------------------------

local methods = {
	OnAcquire = function(self)
		self.hovered = false
		self:SetHeight(W.LABELED_HEIGHT)
		self:SetWidth(200)
		self:SetLabel()
		self:SetDisabled(false)
		self:SetList(nil)
	end,

	OnRelease = function(self)
		self.value = nil
		self.list = nil
		self.hovered = false
		wipe(self.order)
		wipe(self.itemDisabled)
		for _, segment in ipairs(self.segments) do
			segment.hovered = false
			segment.key = nil
		end
	end,

	OnWidthSet = function(self, width)
		Layout(self)
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

	SetDisabled = function(self, disabled)
		self.disabled = disabled
		for _, segment in ipairs(self.segments) do
			if disabled then
				segment:Disable()
			else
				segment:Enable()
			end
		end
		Paint(self)
	end,

	---@param list table|nil key -> text
	---@param order table|nil keys in display order
	---@param itemType string|nil ignored, items are always text
	SetList = function(self, list, order, itemType)
		self.list = list or {}
		wipe(self.order)
		wipe(self.itemDisabled)
		if list then
			if type(order) ~= 'table' then
				for key in pairs(list) do
					self.order[#self.order + 1] = key
				end
				table.sort(self.order, sortTbl)
			else
				for _, key in ipairs(order) do
					self.order[#self.order + 1] = key
				end
			end
		end
		for i, key in ipairs(self.order) do
			local segment = self.segments[i] or CreateSegment(self, i)
			segment.key = key
			segment.text:SetText(self.list[key])
			if self.disabled then
				segment:Disable()
			else
				segment:Enable()
			end
		end
		for i = #self.order + 1, #self.segments do
			self.segments[i].key = nil
		end
		Layout(self)
		Paint(self)
	end,

	AddItem = function(self, value, text)
		local order = {}
		for i, key in ipairs(self.order) do
			order[i] = key
		end
		order[#order + 1] = value
		local list = self.list or {}
		list[value] = text
		self:SetList(list, order)
	end,

	SetValue = function(self, value)
		self.value = value
		Paint(self)
	end,

	GetValue = function(self)
		return self.value
	end,

	SetText = function(self, text) end,

	-- A row of buttons holds one choice
	SetMultiselect = function(self, multi) end,

	GetMultiselect = function(self)
		return false
	end,

	SetItemValue = function(self, item, value) end,

	SetItemDisabled = function(self, item, disabled)
		self.itemDisabled[item] = disabled and true or nil
		Paint(self)
	end,

	SetPulloutWidth = function(self, width) end,

	ClearFocus = function(self) end,
}

----------------------------------------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------------------------------------

local function Constructor()
	local frame = CreateFrame('Frame', nil, UIParent)
	frame:Hide()

	local label = Style:CreateText(frame, W.LABEL_SIZE)
	label:SetPoint('TOPLEFT', 0, 0)
	label:SetPoint('TOPRIGHT', 0, 0)
	label:SetJustifyH('LEFT')
	label:SetWordWrap(false)
	label:SetHeight(20)
	label:Hide()

	local box = CreateFrame('Frame', nil, frame)
	box:SetPoint('BOTTOMLEFT', 0, 0)
	box:SetPoint('BOTTOMRIGHT', 0, 0)
	box:SetHeight(W.INPUT_HEIGHT)
	W:SkinBox(box)

	local widget = {
		type = Type,
		frame = frame,
		label = label,
		box = box,
		segments = {},
		dividers = {},
		order = {},
		itemDisabled = {},
		list = {},
		alignoffset = W.LABELED_ALIGN,
	}
	for method, func in pairs(methods) do
		widget[method] = func
	end
	frame.obj = widget
	frame:SetScript('OnShow', function()
		Layout(widget)
	end)
	Style:OnAccentChanged(frame, function()
		Paint(widget)
	end)

	return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
