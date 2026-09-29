---@class SUI
local SUI = SUI
local Style = SUI.UI.Style
local W = SUI.UI.OptionWidgets

-- ColorPicker replacement: a flat swatch (checkered behind it so alpha shows) that opens the
-- game's color picker, plus a small arrow (or right-click) for the colors used recently.
-- Same methods, callbacks and events as the stock AceGUI ColorPicker.

local Type, Version = 'SUI-ColorPicker', 1
local AceGUI = LibStub and LibStub('AceGUI-3.0', true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then
	return
end

-- No API tells whether the client's color picker uses inverted alpha. Only mainline does not.
local INVERTED_ALPHA = (WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE)

local SWATCH_W, SWATCH_H = 26, 16
local ARROW_W = 12
local RECENT_MAX = 8
local RECENT_SIZE = 16

-- Colors picked this session, newest first
local recent = {}

---@param r number
---@param g number
---@param b number
---@param a number
local function RememberColor(r, g, b, a)
	local function same(entry)
		return math.abs(entry[1] - r) < 0.004 and math.abs(entry[2] - g) < 0.004 and math.abs(entry[3] - b) < 0.004 and math.abs(entry[4] - a) < 0.004
	end
	for i = #recent, 1, -1 do
		if same(recent[i]) then
			table.remove(recent, i)
		end
	end
	table.insert(recent, 1, { r, g, b, a })
	while #recent > RECENT_MAX do
		table.remove(recent)
	end
end

local popup
-- The widget the game's color picker was last opened for
local session
local pickerHooked = false

----------------------------------------------------------------------------------------------------
-- Support functions
----------------------------------------------------------------------------------------------------

local function Paint(self)
	local c = Style.color
	local frame = self.frame
	local hovered = frame.hovered and not self.disabled
	if self.disabled then
		self.swatchBorder:SetColor(c.line[1], c.line[2], c.line[3], c.line[4])
		W.Paint(self.text, c.faint)
		self.arrow:SetColor(c.faint[1], c.faint[2], c.faint[3], 0.6)
		self.colorSwatch:SetAlpha(0.5)
	else
		if hovered then
			local r, g, b = Style:GetAccent()
			self.swatchBorder:SetColor(r, g, b, 1)
		else
			self.swatchBorder:SetColor(1, 1, 1, 0.28)
		end
		W.Paint(self.text, hovered and c.text or W.Mix(c.text, c.muted, 0.15))
		local arrowColor = self.arrowButton.hovered and c.text or c.muted
		self.arrow:SetColor(arrowColor[1], arrowColor[2], arrowColor[3], 1)
		self.colorSwatch:SetAlpha(1)
	end
end

local function ColorCallback(self, r, g, b, a, isAlpha)
	if INVERTED_ALPHA and a then
		a = 1 - a
	end
	if not self.HasAlpha then
		a = 1
	end
	-- no change, skip update
	if r == self.r and g == self.g and b == self.b and a == self.a then
		return
	end
	self:SetColor(r, g, b, a)
	if session and session.widget == self then
		session.last = { r, g, b, a or 1 }
	end
	if ColorPickerFrame:IsVisible() then
		--colorpicker is still open
		self:Fire('OnValueChanged', r, g, b, a)
	else
		--colorpicker is closed, color callback is first, ignore it,
		--alpha callback is the final call after it closes so confirm now
		if isAlpha then
			self:Fire('OnValueConfirmed', r, g, b, a)
		end
	end
end

-- The picker does not always call back when it closes, so recent colors are saved from its OnHide
local function Picker_OnHide()
	if not session then
		return
	end
	local first, last = session.first, session.last
	session = nil
	if last and not (last[1] == first[1] and last[2] == first[2] and last[3] == first[3] and last[4] == first[4]) then
		RememberColor(first[1], first[2], first[3], first[4])
		RememberColor(last[1], last[2], last[3], last[4])
	end
end

local function HidePopup()
	if popup then
		popup:Hide()
	end
end

local function OpenPicker(self, frame)
	ColorPickerFrame:Hide()
	HidePopup()
	if not self.disabled then
		if not pickerHooked then
			pickerHooked = true
			ColorPickerFrame:HookScript('OnHide', Picker_OnHide)
		end
		session = { widget = self, first = { self.r, self.g, self.b, self.a or 1 } }
		ColorPickerFrame:SetFrameStrata('FULLSCREEN_DIALOG')
		ColorPickerFrame:SetFrameLevel(frame:GetFrameLevel() + 10)
		ColorPickerFrame:SetClampedToScreen(true)

		if ColorPickerFrame.SetupColorPickerAndShow then -- 10.2.5 color picker overhaul
			local r2, g2, b2, a2 = self.r, self.g, self.b, (self.a or 1)
			if INVERTED_ALPHA then
				a2 = 1 - a2
			end

			local info = {
				swatchFunc = function()
					local r, g, b = ColorPickerFrame:GetColorRGB()
					local a = ColorPickerFrame:GetColorAlpha()
					ColorCallback(self, r, g, b, a)
				end,

				hasOpacity = self.HasAlpha,
				opacityFunc = function()
					local r, g, b = ColorPickerFrame:GetColorRGB()
					local a = ColorPickerFrame:GetColorAlpha()
					ColorCallback(self, r, g, b, a, true)
				end,
				opacity = a2,

				cancelFunc = function()
					ColorCallback(self, r2, g2, b2, a2, true)
				end,

				r = r2,
				g = g2,
				b = b2,
			}

			ColorPickerFrame:SetupColorPickerAndShow(info)
		else
			ColorPickerFrame.func = function()
				local r, g, b = ColorPickerFrame:GetColorRGB()
				local a = OpacitySliderFrame:GetValue()
				ColorCallback(self, r, g, b, a)
			end

			ColorPickerFrame.hasOpacity = self.HasAlpha
			ColorPickerFrame.opacityFunc = function()
				local r, g, b = ColorPickerFrame:GetColorRGB()
				local a = OpacitySliderFrame:GetValue()
				ColorCallback(self, r, g, b, a, true)
			end

			local r, g, b, a = self.r, self.g, self.b, 1 - (self.a or 1)
			if self.HasAlpha then
				ColorPickerFrame.opacity = a
			end
			ColorPickerFrame:SetColorRGB(r, g, b)

			ColorPickerFrame.cancelFunc = function()
				ColorCallback(self, r, g, b, a, true)
			end

			ColorPickerFrame:Show()
		end
	end
	AceGUI:ClearFocus()
end

----------------------------------------------------------------------------------------------------
-- Recent colors popup (one shared frame)
----------------------------------------------------------------------------------------------------

local function ApplyRecent(button)
	local self = popup.owner
	local color = button.color
	HidePopup()
	if not self or self.disabled or not color then
		return
	end
	local r, g, b, a = color[1], color[2], color[3], self.HasAlpha and color[4] or 1
	RememberColor(r, g, b, a)
	self:SetColor(r, g, b, a)
	W.Sound(852) -- SOUNDKIT.IG_MAINMENU_OPTION
	self:Fire('OnValueChanged', r, g, b, a)
	self:Fire('OnValueConfirmed', r, g, b, a)
end

local function RecentButton_OnEnter(button)
	local r, g, b = Style:GetAccent()
	button.border:SetColor(r, g, b, 1)
end

local function RecentButton_OnLeave(button)
	button.border:SetColor(1, 1, 1, 0.25)
end

local function GetPopup()
	if popup then
		return popup
	end
	popup = CreateFrame('Frame', nil, UIParent)
	popup:SetFrameStrata('TOOLTIP')
	popup:SetClampedToScreen(true)
	popup:EnableMouse(true)
	popup:Hide()
	Style:SkinPanel(popup, Style.color.raised, Style.color.lineStrong)

	popup.empty = Style:CreateText(popup, W.SMALL_SIZE, Style.color.muted)
	popup.empty:SetPoint('LEFT', 8, 0)
	popup.empty:SetText(SUI.L and SUI.L['No recent colors yet'] or 'No recent colors yet')

	popup.buttons = {}
	for i = 1, RECENT_MAX do
		local button = CreateFrame('Button', nil, popup)
		button:SetSize(RECENT_SIZE, RECENT_SIZE)
		button:SetPoint('LEFT', 6 + (i - 1) * (RECENT_SIZE + 4), 0)
		local checkers = button:CreateTexture(nil, 'BACKGROUND')
		checkers:SetAllPoints()
		checkers:SetTexture(W.CHECKERS)
		checkers:SetTexCoord(0.25, 0, 0.5, 0.25)
		checkers:SetDesaturated(true)
		checkers:SetVertexColor(1, 1, 1, 0.75)
		button.swatch = W:CreateRect(button, 'ARTWORK')
		button.swatch:SetAllPoints()
		button.border = Style:CreateBorder(button)
		button.border:SetColor(1, 1, 1, 0.25)
		button:SetScript('OnClick', ApplyRecent)
		button:SetScript('OnEnter', RecentButton_OnEnter)
		button:SetScript('OnLeave', RecentButton_OnLeave)
		popup.buttons[i] = button
	end

	popup:SetScript('OnHide', function(self)
		self:UnregisterEvent('GLOBAL_MOUSE_DOWN')
		self.owner = nil
	end)
	return popup
end

local function TogglePopup(self)
	local frame = GetPopup()
	if frame:IsShown() and frame.owner == self then
		HidePopup()
		return
	end
	if self.disabled then
		return
	end
	frame.owner = self
	local count = #recent
	for i, button in ipairs(frame.buttons) do
		local color = recent[i]
		button.color = color
		if color then
			button.swatch:SetVertexColor(color[1], color[2], color[3], self.HasAlpha and color[4] or 1)
			button:Show()
		else
			button:Hide()
		end
	end
	frame.empty:SetShown(count == 0)
	if count == 0 then
		frame:SetSize(Style:MeasureText(frame.empty) + 16, RECENT_SIZE + 12)
	else
		frame:SetSize(12 + count * RECENT_SIZE + (count - 1) * 4, RECENT_SIZE + 12)
	end
	frame:ClearAllPoints()
	frame:SetPoint('LEFT', self.arrowButton, 'RIGHT', 4, 0)
	frame:SetFrameLevel(self.frame:GetFrameLevel() + 20)
	frame:Show()
	W.WatchGlobalClicks(frame, function()
		if not W.MouseOverAny(frame, self.arrowButton, self.frame) then
			HidePopup()
		end
	end)
end

----------------------------------------------------------------------------------------------------
-- Scripts
----------------------------------------------------------------------------------------------------

local function Control_OnEnter(frame)
	frame.hovered = true
	Paint(frame.obj)
	frame.obj:Fire('OnEnter')
end

local function Control_OnLeave(frame)
	frame.hovered = false
	Paint(frame.obj)
	frame.obj:Fire('OnLeave')
end

local function ColorSwatch_OnClick(frame, mouseButton)
	local self = frame.obj
	if mouseButton == 'RightButton' then
		TogglePopup(self)
		return
	end
	OpenPicker(self, frame)
end

local function Arrow_OnClick(button)
	TogglePopup(button.obj)
end

local function Arrow_OnEnter(button)
	button.hovered = true
	Paint(button.obj)
	button.obj:Fire('OnEnter')
end

local function Arrow_OnLeave(button)
	button.hovered = false
	Paint(button.obj)
	button.obj:Fire('OnLeave')
end

----------------------------------------------------------------------------------------------------
-- Methods
----------------------------------------------------------------------------------------------------

local methods = {
	OnAcquire = function(self)
		self.frame.hovered = false
		self.arrowButton.hovered = false
		self:SetHeight(24)
		self:SetWidth(200)
		self:SetHasAlpha(false)
		self:SetColor(0, 0, 0, 1)
		self:SetDisabled(nil)
		self:SetLabel(nil)
	end,

	OnRelease = function(self)
		if popup and popup.owner == self then
			HidePopup()
		end
		self.frame.hovered = false
		self.arrowButton.hovered = false
	end,

	SetLabel = function(self, text)
		self.text:SetText(text)
	end,

	SetColor = function(self, r, g, b, a)
		self.r = r
		self.g = g
		self.b = b
		self.a = a or 1
		self.colorSwatch:SetVertexColor(r, g, b, a)
	end,

	SetHasAlpha = function(self, HasAlpha)
		self.HasAlpha = HasAlpha
	end,

	SetDisabled = function(self, disabled)
		self.disabled = disabled
		if self.disabled then
			self.frame:Disable()
			self.arrowButton:Disable()
			if popup and popup.owner == self then
				HidePopup()
			end
		else
			self.frame:Enable()
			self.arrowButton:Enable()
		end
		Paint(self)
	end,
}

----------------------------------------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------------------------------------

local function Constructor()
	local frame = CreateFrame('Button', nil, UIParent)
	frame:Hide()

	frame:EnableMouse(true)
	frame:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
	frame:SetScript('OnEnter', Control_OnEnter)
	frame:SetScript('OnLeave', Control_OnLeave)
	frame:SetScript('OnClick', ColorSwatch_OnClick)

	-- The swatch sits in its own frame so its border does not wrap the whole row
	local swatchFrame = CreateFrame('Frame', nil, frame)
	swatchFrame:SetSize(SWATCH_W, SWATCH_H)
	swatchFrame:SetPoint('LEFT', 0, 0)

	local checkers = swatchFrame:CreateTexture(nil, 'BACKGROUND')
	checkers:SetAllPoints()
	checkers:SetTexture(W.CHECKERS)
	checkers:SetTexCoord(0.25, 0, 0.5, 0.25)
	checkers:SetDesaturated(true)
	checkers:SetVertexColor(1, 1, 1, 0.75)

	local colorSwatch = W:CreateRect(swatchFrame, 'ARTWORK')
	colorSwatch:SetAllPoints()
	colorSwatch.checkers = checkers
	local swatchBorder = Style:CreateBorder(swatchFrame)

	local arrowButton = CreateFrame('Button', nil, frame)
	arrowButton:SetSize(ARROW_W, SWATCH_H)
	arrowButton:SetPoint('LEFT', swatchFrame, 'RIGHT', 1, 0)
	arrowButton:SetScript('OnClick', Arrow_OnClick)
	arrowButton:SetScript('OnEnter', Arrow_OnEnter)
	arrowButton:SetScript('OnLeave', Arrow_OnLeave)
	local arrow = W:CreateArrow(arrowButton, 3)
	arrow.anchor:SetPoint('CENTER', arrowButton, 'CENTER', 0, 0)
	arrowButton:SetScript('OnShow', function()
		arrow:Layout()
	end)

	local text = Style:CreateText(frame, W.LABEL_SIZE)
	text:SetHeight(24)
	text:SetJustifyH('LEFT')
	text:SetWordWrap(false)
	text:SetPoint('LEFT', arrowButton, 'RIGHT', 6, 0)
	text:SetPoint('RIGHT')

	local widget = {
		colorSwatch = colorSwatch,
		swatchBorder = swatchBorder,
		arrowButton = arrowButton,
		arrow = arrow,
		text = text,
		frame = frame,
		type = Type,
	}
	for method, func in pairs(methods) do
		widget[method] = func
	end
	arrowButton.obj = widget
	Style:OnAccentChanged(frame, function()
		Paint(widget)
	end)

	return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)

---Colors picked this session, newest first (read only)
---@return number[][]
function W.GetRecentColors()
	return recent
end
