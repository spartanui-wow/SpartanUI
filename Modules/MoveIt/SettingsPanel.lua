---@class SUI
local SUI = SUI
local MoveIt = SUI.MoveIt
local MoverMode = MoveIt.MoverMode
local PositionCalculator = MoveIt.PositionCalculator

---@class SUI.MoveIt.SettingsPanel
local SettingsPanel = {}
MoveIt.SettingsPanel = SettingsPanel

-- Panel state
SettingsPanel.panel = nil
SettingsPanel.currentMover = nil
SettingsPanel.widgetContainer = nil
SettingsPanel.activeWidgets = {}
SettingsPanel.lastPosition = nil -- Session persistence

-- Constants
local PANEL_WIDTH = 260
local PANEL_MIN_HEIGHT = 180
local PANEL_PADDING = 15
local WIDGET_WIDTH = PANEL_WIDTH - (PANEL_PADDING * 2)
local NUDGE_STEP = 1
local NUDGE_BIG_STEP = 10

-- Built-in widget definitions (order 1-50)
local BUILTIN_WIDGETS = {
	resetPosition = {
		type = 'button',
		order = 10,
		name = 'Reset Position',
		desc = 'Reset this frame to its default position',
		func = function()
			local mover = SettingsPanel.currentMover
			if mover then
				MoveIt:Reset(mover.name, true)
				-- Get display name from FontString or use mover name
				local displayText = mover.name
				if mover.DisplayName and mover.DisplayName.GetText then
					displayText = mover.DisplayName:GetText() or displayText
				end
				SUI:Print('Reset ' .. displayText .. ' to default position')
			end
		end,
	},
	scale = {
		type = 'slider',
		order = 20,
		name = 'Scale',
		desc = 'Adjust the scale of this frame',
		min = 0.5,
		max = 2.0,
		step = 0.05,
		get = function()
			local mover = SettingsPanel.currentMover
			if mover then
				return (mover.parent and mover.parent:GetScale()) or mover:GetScale() or 1.0
			end
			return 1.0
		end,
		set = function(_, value)
			local mover = SettingsPanel.currentMover
			if mover then
				local parent = mover.parent
				local name = mover.name

				-- Simply apply scale - don't try to adjust position
				-- The frame scales from its anchor point (CENTER), so position stays stable
				if parent then
					parent:SetScale(value)
				end
				mover:SetScale(value)

				-- Save scale
				if MoveIt.DB and MoveIt.DB.movers and MoveIt.DB.movers[name] then
					MoveIt.DB.movers[name].AdjustedScale = value
				end

				-- Show scaled indicator
				if mover.ScaledText then
					mover.ScaledText:Show()
				end

				-- Update position display
				if SettingsPanel.nudgeWidget and SettingsPanel.nudgeWidget.UpdatePositionDisplay then
					SettingsPanel.nudgeWidget:UpdatePositionDisplay()
				end
			end
		end,
	},
	divider1 = {
		type = 'divider',
		order = 35,
	},
	suiSettings = {
		type = 'button',
		order = 45,
		name = 'SpartanUI Settings',
		desc = 'Open SpartanUI options',
		func = function()
			local panel = SettingsPanel.panel
			if panel then
				panel:Hide()
			end
			MoverMode:Exit()
			SUI.Options:ToggleOptions({ 'Movers' })
		end,
	},
}

---Create the nudge controls widget (not using WidgetBuilder for this custom widget)
---@param container Frame Parent container
---@return Frame nudgeFrame
---@return number height
local function CreateNudgeWidget(container)
	local frame = CreateFrame('Frame', nil, container)
	frame:SetSize(WIDGET_WIDTH, 70)

	-- Header
	local header = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	header:SetPoint('TOP', frame, 'TOP', 0, 0)
	header:SetText('Position')
	header:SetTextColor(1, 0.82, 0)

	-- Anchor display (shows anchor point info)
	local anchorText = frame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
	anchorText:SetPoint('TOP', header, 'BOTTOM', 0, -2)
	anchorText:SetText('Anchor: CENTER')
	anchorText:SetTextColor(0.7, 0.7, 0.7)
	frame.anchorText = anchorText

	-- Position display (offset from anchor)
	local posText = frame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
	posText:SetPoint('TOP', anchorText, 'BOTTOM', 0, -1)
	posText:SetText('X: 0  Y: 0')
	frame.posText = posText

	-- Create arrow buttons layout:
	--       [Up]
	-- [Left]    [Right]
	--      [Down]
	local buttonSize = 22
	local centerX = WIDGET_WIDTH / 2
	local centerY = -45 -- Adjusted for anchor text line

	-- Up button
	local upBtn = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
	upBtn:SetSize(buttonSize, buttonSize)
	upBtn:SetPoint('CENTER', frame, 'TOP', 0, centerY)
	upBtn:SetText('^')
	upBtn:SetScript('OnClick', function()
		local step = IsShiftKeyDown() and NUDGE_BIG_STEP or NUDGE_STEP
		SettingsPanel:NudgeMover(0, step)
	end)
	upBtn:SetScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		GameTooltip:SetText('Move Up')
		GameTooltip:AddLine('Click: 1 pixel | Shift+Click: 10 pixels', 1, 1, 1)
		GameTooltip:Show()
	end)
	upBtn:SetScript('OnLeave', GameTooltip_Hide)

	-- Down button
	local downBtn = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
	downBtn:SetSize(buttonSize, buttonSize)
	downBtn:SetPoint('CENTER', frame, 'TOP', 0, centerY - 24)
	downBtn:SetText('v')
	downBtn:SetScript('OnClick', function()
		local step = IsShiftKeyDown() and NUDGE_BIG_STEP or NUDGE_STEP
		SettingsPanel:NudgeMover(0, -step)
	end)
	downBtn:SetScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		GameTooltip:SetText('Move Down')
		GameTooltip:AddLine('Click: 1 pixel | Shift+Click: 10 pixels', 1, 1, 1)
		GameTooltip:Show()
	end)
	downBtn:SetScript('OnLeave', GameTooltip_Hide)

	-- Left button
	local leftBtn = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
	leftBtn:SetSize(buttonSize, buttonSize)
	leftBtn:SetPoint('CENTER', frame, 'TOP', -26, centerY - 12)
	leftBtn:SetText('<')
	leftBtn:SetScript('OnClick', function()
		local step = IsShiftKeyDown() and NUDGE_BIG_STEP or NUDGE_STEP
		SettingsPanel:NudgeMover(-step, 0)
	end)
	leftBtn:SetScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		GameTooltip:SetText('Move Left')
		GameTooltip:AddLine('Click: 1 pixel | Shift+Click: 10 pixels', 1, 1, 1)
		GameTooltip:Show()
	end)
	leftBtn:SetScript('OnLeave', GameTooltip_Hide)

	-- Right button
	local rightBtn = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
	rightBtn:SetSize(buttonSize, buttonSize)
	rightBtn:SetPoint('CENTER', frame, 'TOP', 26, centerY - 12)
	rightBtn:SetText('>')
	rightBtn:SetScript('OnClick', function()
		local step = IsShiftKeyDown() and NUDGE_BIG_STEP or NUDGE_STEP
		SettingsPanel:NudgeMover(step, 0)
	end)
	rightBtn:SetScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		GameTooltip:SetText('Move Right')
		GameTooltip:AddLine('Click: 1 pixel | Shift+Click: 10 pixels', 1, 1, 1)
		GameTooltip:Show()
	end)
	rightBtn:SetScript('OnLeave', GameTooltip_Hide)

	frame.upBtn = upBtn
	frame.downBtn = downBtn
	frame.leftBtn = leftBtn
	frame.rightBtn = rightBtn

	---Update position display (shows live CENTER-based coordinates)
	function frame:UpdatePositionDisplay()
		local mover = SettingsPanel.currentMover
		if mover then
			-- Check if anchored to another frame (not UIParent)
			local pos = PositionCalculator:GetRelativePosition(mover)
			local anchorName = pos and pos.anchorFrameName or 'UIParent'

			if anchorName ~= 'UIParent' then
				-- Show attachment info for frame-to-frame anchors
				self.anchorText:SetText(string.format('%s -> %s.%s', pos.point or '?', anchorName, pos.anchorPoint or '?'))
				self.posText:SetText(string.format('X: %d  Y: %d', math.floor(pos.x or 0), math.floor(pos.y or 0)))
			else
				-- Use shared function to get CENTER offset
				local offsetX, offsetY = PositionCalculator:GetCenterOffset(mover)
				if offsetX and offsetY then
					self.anchorText:SetText('Anchor: CENTER')
					self.posText:SetText(string.format('X: %d  Y: %d', offsetX, offsetY))
				end
			end
		end
	end

	return frame, 70
end

---Create the settings panel frame
local function CreatePanel()
	if SettingsPanel.panel then
		return SettingsPanel.panel
	end

	-- Create main panel frame
	local panel = CreateFrame('Frame', 'SUI_EditMode_SettingsPanel', UIParent, BackdropTemplateMixin and 'BackdropTemplate')
	panel:SetSize(PANEL_WIDTH, PANEL_MIN_HEIGHT)
	panel:SetFrameStrata('DIALOG')
	panel:SetFrameLevel(100)
	panel:SetClampedToScreen(true)

	-- Make draggable
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag('LeftButton')
	panel:SetScript('OnDragStart', function(self)
		self:StartMoving()
	end)
	panel:SetScript('OnDragStop', function(self)
		self:StopMovingOrSizing()
		-- Position resets on next Show, so no need to save
	end)

	-- Backdrop - darker, more modern look
	panel:SetBackdrop({
		bgFile = 'Interface\\DialogFrame\\UI-DialogBox-Background-Dark',
		edgeFile = 'Interface\\DialogFrame\\UI-DialogBox-Border',
		tile = true,
		tileSize = 32,
		edgeSize = 24,
		insets = { left = 6, right = 6, top = 6, bottom = 6 },
	})
	panel:SetBackdropColor(0.1, 0.1, 0.1, 0.95)

	-- Title bar
	local titleBar = CreateFrame('Frame', nil, panel)
	titleBar:SetHeight(30)
	titleBar:SetPoint('TOPLEFT', panel, 'TOPLEFT', 6, -6)
	titleBar:SetPoint('TOPRIGHT', panel, 'TOPRIGHT', -6, -6)

	-- Title text
	local title = titleBar:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
	title:SetPoint('LEFT', titleBar, 'LEFT', 10, 0)
	title:SetText('Frame Settings')
	panel.title = title

	-- Frame name (below title)
	local frameName = panel:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	frameName:SetPoint('TOP', titleBar, 'BOTTOM', 0, -2)
	frameName:SetText('')
	panel.frameName = frameName

	-- Close button
	local closeBtn = CreateFrame('Button', nil, panel, 'UIPanelCloseButton')
	closeBtn:SetPoint('TOPRIGHT', panel, 'TOPRIGHT', -3, -3)
	closeBtn:SetScript('OnClick', function()
		panel:Hide()
		SettingsPanel.currentMover = nil
	end)
	panel.closeBtn = closeBtn

	-- Widget container
	local widgetContainer = CreateFrame('Frame', nil, panel)
	widgetContainer:SetPoint('TOPLEFT', panel, 'TOPLEFT', PANEL_PADDING, -55)
	widgetContainer:SetPoint('TOPRIGHT', panel, 'TOPRIGHT', -PANEL_PADDING, -55)
	widgetContainer:SetHeight(200) -- Will be adjusted dynamically
	panel.widgetContainer = widgetContainer

	-- Keyboard support for arrow nudging
	panel:EnableKeyboard(true)
	panel:SetPropagateKeyboardInput(true)
	panel:SetScript('OnKeyDown', function(self, key)
		if InCombatLockdown() then
			return
		end

		local step = IsShiftKeyDown() and NUDGE_BIG_STEP or NUDGE_STEP
		local handled = false

		if key == 'LEFT' then
			SettingsPanel:NudgeMover(-step, 0)
			handled = true
		elseif key == 'RIGHT' then
			SettingsPanel:NudgeMover(step, 0)
			handled = true
		elseif key == 'UP' then
			SettingsPanel:NudgeMover(0, step)
			handled = true
		elseif key == 'DOWN' then
			SettingsPanel:NudgeMover(0, -step)
			handled = true
		elseif key == 'ESCAPE' then
			self:Hide()
			SettingsPanel.currentMover = nil
			handled = true
		end

		if handled then
			self:SetPropagateKeyboardInput(false)
		else
			self:SetPropagateKeyboardInput(true)
		end
	end)

	panel:Hide()
	SettingsPanel.panel = panel
	SettingsPanel.widgetContainer = widgetContainer

	return panel
end

---Calculate the best position for the panel relative to a mover
---@param mover Frame The mover frame
---@return string point, string relativePoint, number xOffset, number yOffset
function SettingsPanel:CalculateBestPosition(mover)
	local screenWidth = GetScreenWidth()
	local screenHeight = GetScreenHeight()
	local panelWidth = PANEL_WIDTH
	local panelHeight = self.panel and self.panel:GetHeight() or PANEL_MIN_HEIGHT

	local moverLeft = mover:GetLeft() or 0
	local moverRight = mover:GetRight() or 0
	local moverTop = mover:GetTop() or 0
	local moverBottom = mover:GetBottom() or 0

	-- Priority: Right > Left > Above > Below
	if moverRight + panelWidth + 20 < screenWidth then
		return 'LEFT', 'RIGHT', 10, 0
	elseif moverLeft - panelWidth - 20 > 0 then
		return 'RIGHT', 'LEFT', -10, 0
	elseif moverTop + panelHeight + 20 < screenHeight then
		return 'BOTTOM', 'TOP', 0, 10
	else
		return 'TOP', 'BOTTOM', 0, -10
	end
end

---Build widgets for a mover
---@param mover Frame The mover frame
function SettingsPanel:BuildWidgets(mover)
	local container = self.widgetContainer
	if not container then
		return
	end

	-- Clear existing widgets
	for _, widget in pairs(self.activeWidgets) do
		if widget and widget.Hide then
			widget:Hide()
			widget:SetParent(nil)
		end
	end
	self.activeWidgets = {}

	-- Combine built-in widgets with mover-specific widgets
	local allWidgets = {}

	-- Add built-in widgets
	for id, def in pairs(BUILTIN_WIDGETS) do
		allWidgets[id] = def
	end

	-- Add nudge widget (custom, not from WidgetBuilder)
	local nudgeFrame, nudgeHeight = CreateNudgeWidget(container)
	nudgeFrame:SetPoint('TOPLEFT', container, 'TOPLEFT', 0, 0)
	nudgeFrame:Show()
	nudgeFrame:UpdatePositionDisplay()
	self.activeWidgets.nudge = nudgeFrame
	self.nudgeWidget = nudgeFrame

	-- Add mover-specific widgets if defined
	if mover.widgets then
		for id, def in pairs(mover.widgets) do
			-- Ensure mover widgets have higher order (after built-in)
			if not def.order then
				def.order = 50 + (id:byte() or 0)
			elseif def.order < 50 then
				def.order = def.order + 50
			end
			allWidgets[id] = def
		end
	end

	-- Build widgets using WidgetBuilder (if available)
	local yOffset = -(nudgeHeight + 10) -- Start after nudge widget

	if LibAT and LibAT.UI and LibAT.UI.BuildWidgets then
		local widgets, totalHeight = LibAT.UI.BuildWidgets(container, allWidgets, WIDGET_WIDTH)

		-- Position widgets after nudge
		for id, widget in pairs(widgets) do
			widget:ClearAllPoints()
			widget:SetPoint('TOPLEFT', container, 'TOPLEFT', 0, yOffset)
			yOffset = yOffset - (widget:GetHeight() + 5)
			self.activeWidgets[id] = widget
		end

		-- Calculate total height
		local totalContentHeight = math.abs(yOffset) + nudgeHeight + 10
		self:UpdatePanelHeight(totalContentHeight)
	else
		-- Fallback: create basic widgets without WidgetBuilder
		self:CreateFallbackWidgets(container, allWidgets, yOffset)
	end
end

---Create fallback widgets when WidgetBuilder is not available
---@param container Frame Widget container
---@param widgets table Widget definitions
---@param startOffset number Starting Y offset
function SettingsPanel:CreateFallbackWidgets(container, widgets, startOffset)
	local yOffset = startOffset

	-- Sort widgets by order
	local sorted = {}
	for id, def in pairs(widgets) do
		def._id = id
		table.insert(sorted, def)
	end
	table.sort(sorted, function(a, b)
		return (a.order or 100) < (b.order or 100)
	end)

	for _, def in ipairs(sorted) do
		if def.type == 'button' then
			local btn = CreateFrame('Button', nil, container, 'UIPanelButtonTemplate')
			btn:SetSize(WIDGET_WIDTH, 25)
			btn:SetPoint('TOPLEFT', container, 'TOPLEFT', 0, yOffset)
			btn:SetText(def.name or 'Button')
			btn:SetScript('OnClick', def.func)
			btn:Show()
			self.activeWidgets[def._id] = btn
			yOffset = yOffset - 30
		elseif def.type == 'slider' then
			local frame = CreateFrame('Frame', nil, container)
			frame:SetSize(WIDGET_WIDTH, 40)
			frame:SetPoint('TOPLEFT', container, 'TOPLEFT', 0, yOffset)

			local label = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
			label:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
			label:SetText(def.name or 'Slider')
			label:SetTextColor(1, 0.82, 0)

			local slider = CreateFrame('Slider', nil, frame, 'OptionsSliderTemplate')
			slider:SetPoint('TOPLEFT', frame, 'TOPLEFT', 5, -18)
			slider:SetWidth(WIDGET_WIDTH - 10)
			slider:SetMinMaxValues(def.min or 0, def.max or 1)
			slider:SetValueStep(def.step or 0.1)
			slider:SetObeyStepOnDrag(true)

			if def.get then
				slider:SetValue(def.get())
			end

			slider:SetScript('OnValueChanged', function(self, value)
				if def.set then
					def.set({}, value)
				end
			end)

			frame:Show()
			self.activeWidgets[def._id] = frame
			yOffset = yOffset - 45
		elseif def.type == 'divider' then
			local frame = CreateFrame('Frame', nil, container)
			frame:SetSize(WIDGET_WIDTH, 10)
			frame:SetPoint('TOPLEFT', container, 'TOPLEFT', 0, yOffset)

			local line = frame:CreateTexture(nil, 'ARTWORK')
			line:SetHeight(1)
			line:SetPoint('LEFT', frame, 'LEFT', 10, 0)
			line:SetPoint('RIGHT', frame, 'RIGHT', -10, 0)
			line:SetColorTexture(0.5, 0.5, 0.5, 0.5)

			frame:Show()
			self.activeWidgets[def._id] = frame
			yOffset = yOffset - 15
		end
	end

	-- Update panel height
	local totalHeight = math.abs(yOffset) + 60 -- 60 for nudge widget
	self:UpdatePanelHeight(totalHeight)
end

---Update panel height based on content
---@param contentHeight number The total content height
function SettingsPanel:UpdatePanelHeight(contentHeight)
	local panel = self.panel
	if not panel then
		return
	end

	local totalHeight = contentHeight + 70 -- Header + padding
	panel:SetHeight(math.max(PANEL_MIN_HEIGHT, totalHeight))
end

---Nudge the current mover by offset
---@param deltaX number X offset
---@param deltaY number Y offset
function SettingsPanel:NudgeMover(deltaX, deltaY)
	local mover = self.currentMover
	if not mover then
		return
	end

	if InCombatLockdown() then
		SUI:Print(ERR_NOT_IN_COMBAT)
		return
	end

	-- Get current position
	local currentPos = PositionCalculator:GetRelativePosition(mover)
	if not currentPos then
		return
	end

	-- Apply offset
	local newPos = {
		point = currentPos.point,
		anchorFrame = currentPos.anchorFrame,
		anchorFrameName = currentPos.anchorFrameName,
		anchorPoint = currentPos.anchorPoint,
		x = (currentPos.x or 0) + deltaX,
		y = (currentPos.y or 0) + deltaY,
	}

	-- Set new position
	PositionCalculator:SetRelativePosition(mover, newPos)

	-- Save position
	PositionCalculator:SavePosition(mover.name, newPos)

	-- Show moved indicator
	if mover.MovedText then
		mover.MovedText:Show()
	end

	-- Update position display
	if self.nudgeWidget and self.nudgeWidget.UpdatePositionDisplay then
		self.nudgeWidget:UpdatePositionDisplay()
	end
end

---Show the settings panel for a mover
---@param mover Frame The mover frame
function SettingsPanel:Show(mover)
	if not mover then
		return
	end

	local panel = CreatePanel()
	self.currentMover = mover

	-- Update frame name
	-- Note: mover.DisplayName is a FontString, get the text from it or use mover.name
	local displayText = mover.name or 'Unknown'
	if mover.DisplayName and mover.DisplayName.GetText then
		displayText = mover.DisplayName:GetText() or displayText
	elseif type(mover.DisplayName) == 'string' then
		displayText = mover.DisplayName
	end
	panel.frameName:SetText(displayText)

	-- Build widgets
	self:BuildWidgets(mover)

	-- Position panel - static position on right side (like Blizzard EditMode)
	-- Always reset to default position when showing
	panel:ClearAllPoints()
	panel:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', -50, -150)

	panel:Show()
end

---Hide the settings panel
function SettingsPanel:Hide()
	if self.panel then
		self.panel:Hide()
		self.currentMover = nil
		-- Deselect the frame (turn it back to blue)
		MoverMode:DeselectOverlay()
	end
end

-- Expose to MoverMode for compatibility
function MoverMode:ShowSettingsPanel(mover)
	SettingsPanel:Show(mover)
end

function MoverMode:HideSettingsPanel()
	SettingsPanel:Hide()
end

-- Hook into Exit to hide panel
local originalExit = MoverMode.Exit
function MoverMode:Exit()
	SettingsPanel:Hide()
	originalExit(self)
end

if MoveIt.logger then
	MoveIt.logger.info('Settings Panel loaded (modular widget system)')
end
