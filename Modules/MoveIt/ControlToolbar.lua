---@class SUI
local SUI = SUI
local L = SUI.L
---@class MoveIt
local MoveIt = SUI.MoveIt
local Style = SUI.UI.Style

-- The bar pinned to the top of the screen while moving frames: view toggles on the left,
-- Exit and Save on the right, and a line of help underneath. Holding Shift fades it so frames
-- underneath can be reached.

---@class SUI.MoveIt.ControlToolbar
local ControlToolbar = {}
MoveIt.ControlToolbar = ControlToolbar

local BAR_HEIGHT = 54
local GRID_LABELS = { off = 'Grid: Off', dim = 'Grid: Faint', bright = 'Grid: Bright' }

local function DefaultHint()
	return L['Drag to move. Right-click a frame for more. Arrow keys nudge the selected frame. Hold Shift to keep a straight line, Ctrl to stop snapping. Drag this bar or shrink it to reach frames under it.']
end

function ControlToolbar:Create()
	if self.toolbar then
		return self.toolbar
	end
	local Widgets = MoveIt.Widgets
	local bar = CreateFrame('Frame', 'SUI_MoveIt_ControlToolbar', UIParent)
	bar:SetHeight(BAR_HEIGHT)
	bar:SetPoint('TOP', UIParent, 'TOP', 0, -6)
	bar:SetFrameStrata('FULLSCREEN')
	bar:SetFrameLevel(50)
	bar:EnableMouse(true)
	bar:SetClampedToScreen(true)
	-- The bar can be dragged out of the way for this visit only
	bar:SetMovable(true)
	bar:RegisterForDrag('LeftButton')
	if bar.SetDontSavePosition then
		bar:SetDontSavePosition(true)
	end
	bar:SetScript('OnDragStart', function(self)
		self:StartMoving()
	end)
	bar:SetScript('OnDragStop', function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
	end)
	bar:Hide()
	Style:SkinPanel(bar, Style.color.header, Style.color.lineStrong)

	local accentLine = bar:CreateTexture(nil, 'OVERLAY')
	accentLine:SetTexture(Style.WHITE)
	accentLine:SetPoint('TOPLEFT', 0, 0)
	accentLine:SetPoint('TOPRIGHT', 0, 0)
	accentLine:SetHeight(Style:PixelSize(bar) * 2)
	Style:OnAccentChanged(bar, function(r, g, b)
		accentLine:SetVertexColor(r, g, b, 1)
		if bar.title then
			bar.title:SetTextColor(r, g, b)
		end
	end)

	local title = Style:CreateText(bar, 14)
	title:SetPoint('TOPLEFT', 12, -11)
	title:SetText(L['Move frames'])
	bar.title = title
	Style:FireAccentChanged()

	bar.leftButtons = {}
	bar.rightButtons = {}
	local function Place(widget)
		bar.leftButtons[#bar.leftButtons + 1] = widget
	end

	bar.gridButton = Widgets:Button(bar, L[GRID_LABELS.bright], 96, function(self)
		MoveIt.GridOverlay:CycleMode()
		ControlToolbar:Refresh()
	end)
	bar.gridButton:SetTooltip(L['Show a grid behind your frames to help line them up.'])
	Place(bar.gridButton)

	bar.gridSnapButton = Widgets:Button(bar, L['Snap to grid'], nil, function()
		MoveIt.DB.GridSnapEnabled = not MoveIt.DB.GridSnapEnabled
		ControlToolbar:Refresh()
	end)
	Place(bar.gridSnapButton)

	bar.frameSnapButton = Widgets:Button(bar, L['Snap to frames'], nil, function()
		MoveIt.DB.ElementSnapEnabled = MoveIt.DB.ElementSnapEnabled == false
		ControlToolbar:Refresh()
	end)
	bar.frameSnapButton:SetTooltip(L['Line frames up with other frames and the middle and edges of your screen.'])
	Place(bar.frameSnapButton)

	bar.coordsButton = Widgets:Button(bar, L['Show position'], nil, function()
		MoveIt.DB.ShowCoordinates = not MoveIt.DB.ShowCoordinates
		ControlToolbar:Refresh()
		MoveIt.MoverMode:RepaintAll()
	end)
	Place(bar.coordsButton)

	bar.seeThroughButton = Widgets:Button(bar, L['See-through'], nil, function()
		MoveIt.DB.SeeThrough = not MoveIt.DB.SeeThrough
		ControlToolbar:Refresh()
		MoveIt.MoverMode:RepaintAll()
	end)
	bar.seeThroughButton:SetTooltip(L['Make the frame boxes see-through so you can see the frames under them.'])
	Place(bar.seeThroughButton)

	bar.filterButton = Widgets:Button(bar, L['Show: All'], 110, function(self)
		ControlToolbar:ToggleFilterMenu(self)
	end)
	Place(bar.filterButton)

	bar.saveButton = Widgets:Button(bar, L['Save and exit'], nil, function()
		MoveIt.MoverMode:Exit(false)
	end, true)

	bar.exitButton = Widgets:Button(bar, L['Exit without saving'], nil, function()
		MoveIt.MoverMode:Exit(true)
	end)

	bar.resetButton = Widgets:Button(bar, L['Reset all'], nil, function()
		StaticPopupDialogs['SUI_MOVEIT_RESET_ALL'] = {
			text = L['Put every frame back where SpartanUI places it? This also resets their size.'],
			button1 = L['Reset all'],
			button2 = CANCEL,
			OnAccept = function()
				MoveIt:Reset()
				MoveIt.MoverMode:RepaintAll()
			end,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
		}
		StaticPopup_Show('SUI_MOVEIT_RESET_ALL')
	end)
	bar.rightButtons = { bar.resetButton, bar.exitButton, bar.saveButton }

	bar.minimizeButton = Widgets:Button(bar, '-', 24, function()
		ControlToolbar:SetMinimized(not ControlToolbar.minimized)
	end)
	bar.minimizeButton:SetTooltip(L['Shrink this bar so you can reach the frames under it.'], L['Shrink'])

	local hint = Style:CreateText(bar, 10, Style.color.muted)
	hint:SetPoint('BOTTOMLEFT', 12, 8)
	hint:SetPoint('BOTTOMRIGHT', -12, 8)
	hint:SetJustifyH('LEFT')
	hint:SetWordWrap(false)
	bar.hint = hint

	-- Fade out while Shift is held so frames under the bar can be reached
	bar:SetScript('OnUpdate', function(self)
		local faded = IsShiftKeyDown() and not self:IsMouseOver()
		if faded ~= self.faded then
			self.faded = faded
			Style:FadeTo(self, faded and 0.12 or 1, 0.15)
		end
	end)

	self.toolbar = bar
	return bar
end

local PAD, GAP, ROW_H = 12, 6, 30

---Place everything from measured text widths. One row when it fits, otherwise the view
---toggles move to a second row.
function ControlToolbar:Layout()
	local bar = self.toolbar
	if not bar then
		return
	end
	local Widgets = MoveIt.Widgets
	for _, button in ipairs(bar.leftButtons) do
		button:FitText()
	end
	for _, button in ipairs(bar.rightButtons) do
		button:FitText()
	end

	local titleWidth = Widgets:MeasureText(bar.title)
	local minimize = bar.minimizeButton
	minimize:SetText(self.minimized and '+' or '-')
	minimize:ClearAllPoints()

	bar.title:ClearAllPoints()
	bar.title:SetPoint('TOPLEFT', bar, 'TOPLEFT', PAD, -11)

	if self.minimized then
		for _, button in ipairs(bar.leftButtons) do
			button:Hide()
		end
		for _, button in ipairs(bar.rightButtons) do
			button:Hide()
		end
		bar.hint:Hide()
		minimize:SetPoint('TOPLEFT', bar, 'TOPLEFT', PAD + titleWidth + 12, -6)
		bar:SetWidth(PAD + titleWidth + 12 + minimize:GetWidth() + PAD)
		bar:SetHeight(34)
		return
	end
	for _, button in ipairs(bar.leftButtons) do
		button:Show()
	end
	for _, button in ipairs(bar.rightButtons) do
		button:Show()
	end
	bar.hint:Show()
	minimize:SetPoint('TOPRIGHT', bar, 'TOPRIGHT', -PAD, -8)

	local leftWidth = 0
	for _, button in ipairs(bar.leftButtons) do
		leftWidth = leftWidth + button:GetWidth() + GAP
	end
	local rightWidth = minimize:GetWidth() + GAP
	for _, button in ipairs(bar.rightButtons) do
		rightWidth = rightWidth + button:GetWidth() + GAP
	end

	local maxWidth = UIParent:GetWidth() - 20
	local oneRowWidth = PAD + titleWidth + 20 + leftWidth + 24 + rightWidth + PAD
	local twoRows = oneRowWidth > maxWidth

	local x = twoRows and PAD or (PAD + titleWidth + 20)
	local y = twoRows and -(8 + ROW_H) or -8
	for _, button in ipairs(bar.leftButtons) do
		button:ClearAllPoints()
		button:SetPoint('TOPLEFT', bar, 'TOPLEFT', x, y)
		x = x + button:GetWidth() + GAP
	end

	local right = -PAD - minimize:GetWidth()
	for i = #bar.rightButtons, 1, -1 do
		local button = bar.rightButtons[i]
		button:ClearAllPoints()
		button:SetPoint('TOPRIGHT', bar, 'TOPRIGHT', right - GAP, -8)
		right = right - button:GetWidth() - GAP
	end

	local width
	if twoRows then
		width = math.max(PAD + titleWidth + 24 + rightWidth + PAD, PAD + leftWidth + PAD)
	else
		width = oneRowWidth
	end
	bar:SetWidth(math.min(maxWidth, math.max(width, 640)))
	bar:SetHeight(twoRows and (BAR_HEIGHT + ROW_H) or BAR_HEIGHT)
end

---Sync button states with the saved settings
function ControlToolbar:Refresh()
	local bar = self.toolbar
	if not bar then
		return
	end
	local db = MoveIt.DB
	local mode = MoveIt.GridOverlay:GetMode()
	bar.gridButton:SetText(L[GRID_LABELS[mode]])
	bar.gridButton:SetActive(mode ~= 'off')
	bar.gridSnapButton:SetActive(db.GridSnapEnabled)
	bar.frameSnapButton:SetActive(db.ElementSnapEnabled ~= false)
	bar.coordsButton:SetActive(db.ShowCoordinates)
	bar.seeThroughButton:SetActive(db.SeeThrough)
	local hidden = MoveIt.MoverMode:GetHiddenGroupCount()
	bar.filterButton:SetText(hidden > 0 and L['Show: Some'] or L['Show: All'])
	bar.filterButton:SetActive(hidden > 0)
	bar.hint:SetText(self.hintText or (db.tips ~= false and DefaultHint()) or '')
	self:Layout()
end

---Replace the help line (nil restores the default)
---@param text string|nil
function ControlToolbar:SetHint(text)
	self.hintText = text
	self:Refresh()
end

---Shrink the bar to just its title, or bring it back
---@param minimized boolean
function ControlToolbar:SetMinimized(minimized)
	self.minimized = minimized and true or false
	if minimized then
		self:HideFilterMenu()
	end
	self:Layout()
end

function ControlToolbar:Show()
	local bar = self:Create()
	-- Each visit starts with the bar back at the top and full size
	self.minimized = false
	bar:ClearAllPoints()
	bar:SetPoint('TOP', UIParent, 'TOP', 0, -6)
	self:Refresh()
	bar:SetAlpha(0)
	bar:Show()
	Style:FadeTo(bar, 1, 0.2)
	-- Text can measure 0 until its font has been drawn once; measure again next frame
	C_Timer.After(0, function()
		ControlToolbar:Layout()
	end)
end

function ControlToolbar:Hide()
	if self.toolbar then
		self.toolbar:Hide()
	end
	self:HideFilterMenu()
	self.hintText = nil
end

---@return boolean
function ControlToolbar:IsShown()
	return self.toolbar and self.toolbar:IsShown() or false
end

----------------------------------------------------------------------------------------------------
-- Group filter
----------------------------------------------------------------------------------------------------

---@param anchor Frame
function ControlToolbar:ToggleFilterMenu(anchor)
	if self.filterMenu and self.filterMenu:IsShown() then
		self:HideFilterMenu()
		return
	end
	local menu = self.filterMenu
	if not menu then
		menu = CreateFrame('Frame', nil, self.toolbar)
		menu:SetFrameStrata('FULLSCREEN_DIALOG')
		menu:EnableMouse(true)
		Style:SkinPanel(menu, Style.color.raised, Style.color.lineStrong)
		menu.buttons = {}
		self.filterMenu = menu
	end
	for _, button in ipairs(menu.buttons) do
		button:Hide()
	end

	local groups = MoveIt.MoverMode:GetGroups()
	local width = 170
	for i, group in ipairs(groups) do
		local button = menu.buttons[i]
		if not button then
			button = MoveIt.Widgets:Button(menu, '', width - 12)
			menu.buttons[i] = button
		end
		button:SetText(group)
		button:SetActive(not MoveIt.MoverMode:IsGroupHidden(group))
		button:SetScript('OnClick', function(self)
			local hide = not MoveIt.MoverMode:IsGroupHidden(group)
			MoveIt.MoverMode:SetGroupHidden(group, hide)
			self:SetActive(not hide)
			ControlToolbar:Refresh()
		end)
		button:ClearAllPoints()
		button:SetPoint('TOPLEFT', menu, 'TOPLEFT', 6, -6 - (i - 1) * 25)
		button:Show()
	end
	menu:SetSize(width, 12 + #groups * 25 - 3)
	menu:ClearAllPoints()
	menu:SetPoint('TOPLEFT', anchor, 'BOTTOMLEFT', 0, -4)
	menu:Show()
end

function ControlToolbar:HideFilterMenu()
	if self.filterMenu then
		self.filterMenu:Hide()
	end
end

---@return boolean
function ControlToolbar:IsFilterMenuShown()
	return self.filterMenu ~= nil and self.filterMenu:IsShown()
end
