---@class SUI
local SUI = SUI
local Style = SUI.UI.Style
local W = SUI.UI.OptionWidgets

-- Button replacement: flat raised button, accent filled when primary.
-- Same methods, callbacks and events as the stock AceGUI Button, plus SetPrimary.

local Type, Version = 'SUI-Button', 1
local AceGUI = LibStub and LibStub('AceGUI-3.0', true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then
	return
end

local PADDING = 30

----------------------------------------------------------------------------------------------------
-- Support functions
----------------------------------------------------------------------------------------------------

local function Paint(self)
	local c = Style.color
	local frame = self.frame
	local r, g, b = Style:GetAccent()
	local hovered = frame.hovered and not self.disabled
	local pressed = frame.pressed and hovered
	if self.disabled then
		frame.fill:SetVertexColor(c.raised[1], c.raised[2], c.raised[3], 0.6)
		frame.border:SetColor(c.line[1], c.line[2], c.line[3], c.line[4])
		W.Paint(self.text, c.faint)
	elseif self.primary then
		local lift = pressed and -0.08 or (hovered and 0.12 or 0)
		frame.fill:SetVertexColor(math.max(0, math.min(1, r + lift)), math.max(0, math.min(1, g + lift)), math.max(0, math.min(1, b + lift)), 1)
		frame.border:SetColor(r, g, b, 1)
		W.Paint(self.text, c.onAccent)
	else
		local lift = pressed and 0.06 or (hovered and 0.035 or 0)
		frame.fill:SetVertexColor(c.raised[1] + lift, c.raised[2] + lift, c.raised[3] + lift, c.raised[4])
		frame.border:SetColor(c.lineStrong[1], c.lineStrong[2], c.lineStrong[3], hovered and 0.3 or c.lineStrong[4])
		W.Paint(self.text, hovered and c.text or W.Mix(c.text, c.muted, 0.35))
	end
end

local function FitWidth(self)
	if self.autoWidth then
		self:SetWidth(Style:MeasureText(self.text) + PADDING)
	end
end

----------------------------------------------------------------------------------------------------
-- Scripts
----------------------------------------------------------------------------------------------------

local function Button_OnClick(frame, ...)
	AceGUI:ClearFocus()
	W.Sound(852) -- SOUNDKIT.IG_MAINMENU_OPTION
	frame.obj:Fire('OnClick', ...)
end

local function Control_OnEnter(frame)
	frame.hovered = true
	Paint(frame.obj)
	frame.obj:Fire('OnEnter')
end

local function Control_OnLeave(frame)
	frame.hovered = false
	frame.pressed = false
	Paint(frame.obj)
	frame.obj:Fire('OnLeave')
end

local function Control_OnMouseDown(frame)
	frame.pressed = true
	Paint(frame.obj)
end

local function Control_OnMouseUp(frame)
	frame.pressed = false
	Paint(frame.obj)
end

-- A font that has not been drawn yet measures 0, so measure again once the button is on screen
local function Frame_OnShow(frame)
	local self = frame.obj
	if not self.autoWidth then
		return
	end
	C_Timer.After(0, function()
		if not self.autoWidth or not frame:IsShown() then
			return
		end
		local before = frame.width
		FitWidth(self)
		if before ~= frame.width and self.parent and self.parent.DoLayout then
			self.parent:DoLayout()
		end
	end)
end

----------------------------------------------------------------------------------------------------
-- Methods
----------------------------------------------------------------------------------------------------

local methods = {
	OnAcquire = function(self)
		-- restore default values
		self.frame.hovered, self.frame.pressed = false, false
		self:SetHeight(24)
		self:SetWidth(200)
		self:SetPrimary(false)
		self:SetDisabled(false)
		self:SetAutoWidth(false)
		self:SetText()
	end,

	OnRelease = function(self)
		self.frame.hovered, self.frame.pressed = false, false
	end,

	SetText = function(self, text)
		self.text:SetText(text)
		FitWidth(self)
	end,

	SetAutoWidth = function(self, autoWidth)
		self.autoWidth = autoWidth
		FitWidth(self)
	end,

	SetDisabled = function(self, disabled)
		self.disabled = disabled
		if disabled then
			self.frame:Disable()
		else
			self.frame:Enable()
		end
		Paint(self)
	end,

	---Draw the button filled with the accent color
	---@param primary boolean|nil
	SetPrimary = function(self, primary)
		self.primary = primary and true or false
		Paint(self)
	end,
}

----------------------------------------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------------------------------------

local function Constructor()
	local name = 'SUI_OptionsButton' .. AceGUI:GetNextWidgetNum(Type)
	local frame = CreateFrame('Button', name, UIParent)
	frame:Hide()

	frame:EnableMouse(true)
	frame:SetScript('OnClick', Button_OnClick)
	frame:SetScript('OnEnter', Control_OnEnter)
	frame:SetScript('OnLeave', Control_OnLeave)
	frame:SetScript('OnMouseDown', Control_OnMouseDown)
	frame:SetScript('OnMouseUp', Control_OnMouseUp)
	frame:SetScript('OnShow', Frame_OnShow)

	frame.fill = Style:CreateFill(frame, Style.color.raised)
	frame.border = Style:CreateBorder(frame)

	local text = Style:CreateText(frame, W.LABEL_SIZE)
	text:SetPoint('TOPLEFT', 8, -1)
	text:SetPoint('BOTTOMRIGHT', -8, 1)
	text:SetJustifyV('MIDDLE')
	text:SetWordWrap(false)
	frame:SetFontString(text)
	frame:SetPushedTextOffset(0, 0)

	local widget = {
		text = text,
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
