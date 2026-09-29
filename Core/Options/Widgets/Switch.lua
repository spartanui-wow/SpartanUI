---@class SUI
local SUI = SUI
local Style = SUI.UI.Style
local W = SUI.UI.OptionWidgets

-- CheckBox replacement. The checkbox type is an on/off switch, the radio type a ring with a dot.
-- Same methods, callbacks and events as the stock AceGUI CheckBox.

local Type, Version = 'SUI-Switch', 1
local AceGUI = LibStub and LibStub('AceGUI-3.0', true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then
	return
end

local TRACK_W, TRACK_H = 28, 14
local RADIO = 14
local ROW = 24
local ANIM = 0.12

-- AceConfigDialog redraws the whole page when a toggle changes, so the widget that was clicked
-- is released before its knob can move. The redrawn switch for the same option picks up the
-- slide from here when it is shown in the same frame.
local lastClick = { key = nil, time = nil, from = 0 }

---@param widget table
---@return string|nil
local function OptionKey(widget)
	local path = widget.userdata and widget.userdata.path
	if type(path) ~= 'table' then
		return nil
	end
	local parts = {}
	for i = 1, #path do
		parts[i] = tostring(path[i])
	end
	-- items of a multiselect group share the option path and differ by value
	return tostring(widget.userdata.appName) .. '\001' .. table.concat(parts, '\001') .. '\002' .. tostring(widget.userdata.value)
end

---Knob position for the widget's value: 0 off, 1 on, 0.5 for the tristate "mixed" value
---@param self table
---@return number
local function Progress(self)
	if self.checked then
		return 1
	elseif self.checked == nil and self.tristate then
		return 0.5
	end
	return 0
end

----------------------------------------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------------------------------------

local function PaintSwitch(self, p)
	local c = Style.color
	local accent = W.Accent()
	local off = W.color.trackOff
	local track
	if self.disabled then
		track = W.Mix(off, accent, p * 0.35)
	elseif self.hovered then
		track = W.Mix(W.Lift(off, 0.05), W.Lift(accent, 0.08), p)
	else
		track = W.Mix(off, accent, p)
	end
	for _, piece in ipairs(self.trackParts) do
		W.Paint(piece, track)
	end
	local knob = W.Mix(c.muted, c.text, p)
	W.Paint(self.knob, knob, self.disabled and 0.5 or 1)
	local x = 2 + (TRACK_W - TRACK_H) * p
	self.knob:ClearAllPoints()
	self.knob:SetPoint('LEFT', self.track, 'LEFT', x, 0)
	self.mid:SetShown(self.tristate and self.checked == nil)
end

local function PaintRadio(self)
	local c = Style.color
	local accent = W.Accent()
	local ring
	if self.disabled then
		ring = W.color.trackOff
	elseif self.checked then
		ring = accent
	elseif self.hovered then
		ring = W.Lift(W.color.ringOff, 0.1)
	else
		ring = W.color.ringOff
	end
	W.Paint(self.ring, ring)
	W.Paint(self.hole, W.color.hole)
	W.Paint(self.dot, accent, self.disabled and 0.4 or 1)
	self.dot:SetShown(self.checked and true or false)
	if self.tristate and self.checked == nil then
		self.dot:Show()
		W.Paint(self.dot, c.muted, 0.6)
	end
end

local function PaintText(self)
	local c = Style.color
	if self.disabled then
		W.Paint(self.text, c.faint)
		if self.desc then
			W.Paint(self.desc, c.faint)
		end
	else
		W.Paint(self.text, self.hovered and c.text or W.Mix(c.text, c.muted, 0.15))
		if self.desc then
			W.Paint(self.desc, c.muted)
		end
	end
end

local function Paint(self)
	local isRadio = self.checkType == 'radio'
	for _, piece in ipairs(self.trackParts) do
		piece:SetShown(not isRadio)
	end
	self.knob:SetShown(not isRadio)
	self.ring:SetShown(isRadio)
	self.hole:SetShown(isRadio)
	if isRadio then
		self.mid:Hide()
		PaintRadio(self)
	else
		self.dot:Hide()
		PaintSwitch(self, self.progress or Progress(self))
	end
	PaintText(self)
end

---Slide the knob to the current value
local function Animate(self, from)
	local to = Progress(self)
	if self.checkType == 'radio' or from == to then
		Style:Stop(self.anim)
		self.progress = to
		Paint(self)
		return
	end
	self.progress = from
	PaintSwitch(self, from)
	Style:Tween(self.anim, ANIM, from, to, function(p)
		self.progress = p
		PaintSwitch(self, p)
	end)
end

local function AlignImage(self)
	local img = self.image:GetTexture()
	local box = self.checkType == 'radio' and self.ring or self.track
	self.text:ClearAllPoints()
	if not img then
		self.text:SetPoint('LEFT', box, 'RIGHT', 8, 0)
	else
		self.text:SetPoint('LEFT', self.image, 'RIGHT', 4, 0)
	end
	self.text:SetPoint('RIGHT')
	self.image:ClearAllPoints()
	self.image:SetPoint('LEFT', box, 'RIGHT', 8, 0)
end

----------------------------------------------------------------------------------------------------
-- Scripts
----------------------------------------------------------------------------------------------------

local function Control_OnEnter(frame)
	local self = frame.obj
	self.hovered = not self.disabled
	Paint(self)
	self:Fire('OnEnter')
end

local function Control_OnLeave(frame)
	local self = frame.obj
	self.hovered = false
	Paint(self)
	self:Fire('OnLeave')
end

local function CheckBox_OnMouseDown(frame)
	AceGUI:ClearFocus()
end

local function CheckBox_OnMouseUp(frame)
	local self = frame.obj
	if not self.disabled then
		local from = self.progress or Progress(self)
		self:ToggleChecked()
		Animate(self, from)

		if self.checked then
			W.Sound(856) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
		else
			W.Sound(857) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
		end

		lastClick.key = OptionKey(self)
		lastClick.time = GetTime()
		lastClick.from = from
		self:Fire('OnValueChanged', self.checked)
	end
end

local function Frame_OnShow(frame)
	local self = frame.obj
	if self.checkType == 'radio' or not lastClick.key or lastClick.time ~= GetTime() then
		return
	end
	if OptionKey(self) == lastClick.key then
		lastClick.key = nil
		Animate(self, lastClick.from)
	end
end

----------------------------------------------------------------------------------------------------
-- Methods
----------------------------------------------------------------------------------------------------

local methods = {
	OnAcquire = function(self)
		self.hovered = false
		self:SetType()
		self:SetValue(false)
		self:SetTriState(nil)
		-- height is calculated from the width and required space for the description
		self:SetWidth(200)
		self:SetImage()
		self:SetDisabled(nil)
		self:SetDescription(nil)
	end,

	OnRelease = function(self)
		Style:Stop(self.anim)
		self.progress = nil
		self.hovered = false
	end,

	OnWidthSet = function(self, width)
		if self.desc then
			self.desc:SetWidth(math.max(1, width - self.descIndent))
			if self.desc:GetText() and self.desc:GetText() ~= '' then
				self:SetHeight(ROW + 4 + self.desc:GetStringHeight())
			end
		end
	end,

	SetDisabled = function(self, disabled)
		self.disabled = disabled
		if disabled then
			self.frame:Disable()
			self.hovered = false
		else
			self.frame:Enable()
		end
		Paint(self)
	end,

	SetValue = function(self, value)
		self.checked = value
		Style:Stop(self.anim)
		self.progress = Progress(self)
		Paint(self)
	end,

	GetValue = function(self)
		return self.checked
	end,

	SetTriState = function(self, enabled)
		self.tristate = enabled
		self:SetValue(self:GetValue())
	end,

	SetType = function(self, checkType)
		self.checkType = checkType == 'radio' and 'radio' or 'checkbox'
		self.descIndent = (self.checkType == 'radio' and RADIO or TRACK_W) + 8
		if self.desc then
			self.desc:ClearAllPoints()
			self.desc:SetPoint('TOPLEFT', self.frame, 'TOPLEFT', self.descIndent, -(ROW - 2))
			self.desc:SetPoint('RIGHT', self.frame, 'RIGHT', 0, 0)
		end
		AlignImage(self)
		Paint(self)
	end,

	ToggleChecked = function(self)
		local value = self:GetValue()
		if self.tristate then
			--cycle in true, nil, false order
			if value then
				self:SetValue(nil)
			elseif value == nil then
				self:SetValue(false)
			else
				self:SetValue(true)
			end
		else
			self:SetValue(not self:GetValue())
		end
	end,

	SetLabel = function(self, label)
		self.text:SetText(label)
	end,

	SetDescription = function(self, desc)
		if desc then
			if not self.desc then
				local f = Style:CreateText(self.frame, W.SMALL_SIZE, Style.color.muted)
				f:SetJustifyH('LEFT')
				f:SetJustifyV('TOP')
				f:SetWordWrap(true)
				self.desc = f
				self:SetType(self.checkType)
			end
			self.desc:SetWidth(math.max(1, (self.frame.width or self.frame:GetWidth() or 200) - self.descIndent))
			self.desc:Show()
			self.desc:SetText(desc)
			self:SetHeight(ROW + 4 + self.desc:GetStringHeight())
		else
			if self.desc then
				self.desc:SetText('')
				self.desc:Hide()
			end
			self:SetHeight(ROW)
		end
		PaintText(self)
	end,

	SetImage = function(self, path, ...)
		local image = self.image
		image:SetTexture(path)

		if image:GetTexture() then
			local n = select('#', ...)
			if n == 4 or n == 8 then
				image:SetTexCoord(...)
			else
				image:SetTexCoord(0, 1, 0, 1)
			end
		end
		AlignImage(self)
	end,
}

----------------------------------------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------------------------------------

local function Constructor()
	local frame = CreateFrame('Button', nil, UIParent)
	frame:Hide()

	frame:EnableMouse(true)
	frame:SetScript('OnEnter', Control_OnEnter)
	frame:SetScript('OnLeave', Control_OnLeave)
	frame:SetScript('OnMouseDown', CheckBox_OnMouseDown)
	frame:SetScript('OnMouseUp', CheckBox_OnMouseUp)
	frame:SetScript('OnShow', Frame_OnShow)

	-- Pill track: two round caps and a bar between their centers
	local track = frame:CreateTexture(nil, 'BACKGROUND')
	track:SetSize(TRACK_W, TRACK_H)
	track:SetPoint('TOPLEFT', 0, -(ROW - TRACK_H) / 2)
	local capLeft = W:CreateDisc(frame, 'ARTWORK', 1)
	capLeft:SetSize(TRACK_H, TRACK_H)
	capLeft:SetPoint('LEFT', track, 'LEFT')
	local capRight = W:CreateDisc(frame, 'ARTWORK', 1)
	capRight:SetSize(TRACK_H, TRACK_H)
	capRight:SetPoint('RIGHT', track, 'RIGHT')
	local bar = W:CreateRect(frame, 'ARTWORK', 1)
	bar:SetPoint('TOPLEFT', track, 'TOPLEFT', TRACK_H / 2, 0)
	bar:SetPoint('BOTTOMRIGHT', track, 'BOTTOMRIGHT', -TRACK_H / 2, 0)

	-- Short dash marking the "mixed" tristate value
	local mid = W:CreateRect(frame, 'ARTWORK', 2)
	mid:SetSize(6, 2)
	mid:SetPoint('CENTER', track, 'CENTER')
	W.Paint(mid, Style.color.onAccent, 0.8)

	local knob = W:CreateDisc(frame, 'ARTWORK', 3)
	knob:SetSize(TRACK_H - 4, TRACK_H - 4)
	knob:SetPoint('LEFT', track, 'LEFT', 2, 0)

	local ring = W:CreateDisc(frame, 'ARTWORK', 1)
	ring:SetSize(RADIO, RADIO)
	ring:SetPoint('TOPLEFT', 0, -(ROW - RADIO) / 2)
	local hole = W:CreateDisc(frame, 'ARTWORK', 2)
	hole:SetSize(RADIO - 3, RADIO - 3)
	hole:SetPoint('CENTER', ring, 'CENTER')
	local dot = W:CreateDisc(frame, 'ARTWORK', 3)
	dot:SetSize(6, 6)
	dot:SetPoint('CENTER', ring, 'CENTER')

	local text = Style:CreateText(frame, W.LABEL_SIZE)
	text:SetJustifyH('LEFT')
	text:SetWordWrap(false)
	text:SetHeight(18)
	text:SetPoint('LEFT', track, 'RIGHT', 8, 0)
	text:SetPoint('RIGHT')

	local image = frame:CreateTexture(nil, 'OVERLAY')
	image:SetHeight(16)
	image:SetWidth(16)
	image:SetPoint('LEFT', track, 'RIGHT', 8, 0)

	local widget = {
		track = track,
		trackParts = { capLeft, capRight, bar },
		knob = knob,
		mid = mid,
		ring = ring,
		hole = hole,
		dot = dot,
		text = text,
		image = image,
		anim = {},
		checkType = 'checkbox',
		descIndent = TRACK_W + 8,
		frame = frame,
		type = Type,
	}
	for method, func in pairs(methods) do
		widget[method] = func
	end
	Style:OnAccentChanged(frame, function()
		Paint(widget)
	end)

	return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
