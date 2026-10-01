---@class SUI
local SUI = SUI
local Style = SUI.UI.Style
local W = SUI.UI.OptionWidgets

-- Keybinding replacement: a flat input box that shows the key. Click it, then press a key; while
-- it waits the border turns accent and the box asks for a key. Escape clears the binding and a
-- second click cancels. Same methods, callbacks and events as the stock AceGUI Keybinding.

local Type, Version = 'SUI-Keybinding', 1
local AceGUI = LibStub and LibStub('AceGUI-3.0', true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then
	return
end

local L = SUI.L or setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})

local IGNORE_KEYS = {
	BUTTON1 = true,
	BUTTON2 = true,
	UNKNOWN = true,
	LSHIFT = true,
	LCTRL = true,
	LALT = true,
	RSHIFT = true,
	RCTRL = true,
	RALT = true,
}

local MOUSE_BUTTONS = {
	MiddleButton = 'BUTTON3',
	Button4 = 'BUTTON4',
	Button5 = 'BUTTON5',
}

----------------------------------------------------------------------------------------------------
-- Support functions
----------------------------------------------------------------------------------------------------

local function Paint(self)
	local c = Style.color
	local state = 'normal'
	if self.disabled then
		state = 'disabled'
	elseif self.waitingForKey then
		state = 'focus'
	elseif self.hovered then
		state = 'hover'
	end
	W.PaintBox(self.button, state)
	W.Paint(self.label, self.disabled and c.faint or c.text)
	if self.waitingForKey then
		self.text:SetText(L['Press a key. Esc clears it.'])
		W.Paint(self.text, W.Accent())
	else
		local bound = (self.key or '') ~= ''
		self.text:SetText(bound and self.key or NOT_BOUND)
		W.Paint(self.text, self.disabled and c.faint or (bound and c.text or c.muted))
	end
end

local function SetListening(self, listening)
	local button = self.button
	self.waitingForKey = listening or nil
	button:EnableKeyboard(listening)
	button:EnableMouseWheel(listening)
	if button.EnableGamePadButton then
		button:EnableGamePadButton(listening)
	end
	Paint(self)
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

local function Keybinding_OnClick(frame, mouseButton)
	if mouseButton == 'LeftButton' or mouseButton == 'RightButton' then
		local self = frame.obj
		W.Sound(856) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
		SetListening(self, not self.waitingForKey)
	end
	AceGUI:ClearFocus()
end

local function Keybinding_OnKeyDown(frame, key)
	local self = frame.obj
	if not self.waitingForKey then
		return
	end
	local keyPressed = key
	if keyPressed == 'ESCAPE' then
		keyPressed = ''
	else
		if IGNORE_KEYS[keyPressed] then
			return
		end
		if IsShiftKeyDown() then
			keyPressed = 'SHIFT-' .. keyPressed
		end
		if IsControlKeyDown() then
			keyPressed = 'CTRL-' .. keyPressed
		end
		if IsAltKeyDown() then
			keyPressed = 'ALT-' .. keyPressed
		end
	end
	SetListening(self, false)
	if not self.disabled then
		self:SetKey(keyPressed)
		self:Fire('OnKeyChanged', keyPressed)
	end
end

local function Keybinding_OnMouseDown(frame, mouseButton)
	local key = MOUSE_BUTTONS[mouseButton]
	if key then
		Keybinding_OnKeyDown(frame, key)
	end
end

local function Keybinding_OnMouseWheel(frame, direction)
	Keybinding_OnKeyDown(frame, direction >= 0 and 'MOUSEWHEELUP' or 'MOUSEWHEELDOWN')
end

local function Keybinding_OnHide(frame)
	if frame.obj.waitingForKey then
		SetListening(frame.obj, false)
	end
end

----------------------------------------------------------------------------------------------------
-- Methods
----------------------------------------------------------------------------------------------------

local methods = {
	OnAcquire = function(self)
		self.hovered = false
		self:SetWidth(200)
		self:SetLabel('')
		self:SetKey('')
		self:SetDisabled(false)
		SetListening(self, false)
	end,

	OnRelease = function(self)
		SetListening(self, false)
	end,

	SetDisabled = function(self, disabled)
		self.disabled = disabled
		if disabled then
			self.button:Disable()
			SetListening(self, false)
		else
			self.button:Enable()
		end
		Paint(self)
	end,

	SetKey = function(self, key)
		self.key = key or ''
		Paint(self)
	end,

	GetKey = function(self)
		if (self.key or '') == '' then
			return nil
		end
		return self.key
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
}

----------------------------------------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------------------------------------

local function Constructor()
	local name = 'SUI_OptionsKeybinding' .. AceGUI:GetNextWidgetNum(Type)
	local frame = CreateFrame('Frame', nil, UIParent)
	frame:Hide()

	local label = Style:CreateText(frame, W.LABEL_SIZE)
	label:SetPoint('TOPLEFT', 0, 0)
	label:SetPoint('TOPRIGHT', 0, 0)
	label:SetJustifyH('LEFT')
	label:SetWordWrap(false)
	label:SetHeight(20)
	label:Hide()

	local button = CreateFrame('Button', name, frame)
	button:SetPoint('BOTTOMLEFT', 0, 0)
	button:SetPoint('BOTTOMRIGHT', 0, 0)
	button:SetHeight(W.INPUT_HEIGHT)
	W:SkinBox(button)
	button:EnableMouse(true)
	button:RegisterForClicks('AnyDown')
	button:SetScript('OnEnter', Control_OnEnter)
	button:SetScript('OnLeave', Control_OnLeave)
	button:SetScript('OnClick', Keybinding_OnClick)
	button:SetScript('OnKeyDown', Keybinding_OnKeyDown)
	button:SetScript('OnMouseDown', Keybinding_OnMouseDown)
	button:SetScript('OnMouseWheel', Keybinding_OnMouseWheel)
	button:SetScript('OnHide', Keybinding_OnHide)
	if button.EnableGamePadButton then
		button:SetScript('OnGamePadButtonDown', Keybinding_OnKeyDown)
	end

	local text = Style:CreateText(button, W.LABEL_SIZE)
	text:SetPoint('LEFT', 8, 0)
	text:SetPoint('RIGHT', -8, 0)
	text:SetJustifyH('LEFT')
	text:SetWordWrap(false)

	local widget = {
		alignoffset = W.LABELED_ALIGN,
		button = button,
		frame = frame,
		label = label,
		text = text,
		type = Type,
	}
	for method, func in pairs(methods) do
		widget[method] = func
	end
	button.obj = widget
	Style:OnAccentChanged(frame, function()
		Paint(widget)
	end)

	return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
