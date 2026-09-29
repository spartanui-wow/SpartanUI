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
	return L['Drag to move. Right-click a frame for more. Arrow keys nudge the selected frame. Hold Shift to keep a straight line, Ctrl to stop snapping.']
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

	local x = 12 + math.ceil(title:GetStringWidth()) + 16
	local function Place(widget, gap)
		widget:SetPoint('TOPLEFT', bar, 'TOPLEFT', x, -8)
		x = x + widget:GetWidth() + (gap or 6)
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
	Place(bar.filterButton, 24)

	bar.saveButton = Widgets:Button(bar, L['Save and exit'], nil, function()
		MoveIt.MoverMode:Exit(false)
	end, true)
	bar.saveButton:SetPoint('TOPRIGHT', bar, 'TOPRIGHT', -10, -8)

	bar.exitButton = Widgets:Button(bar, L['Exit without saving'], nil, function()
		MoveIt.MoverMode:Exit(true)
	end)
	bar.exitButton:SetPoint('RIGHT', bar.saveButton, 'LEFT', -6, 0)

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
	bar.resetButton:SetPoint('RIGHT', bar.exitButton, 'LEFT', -6, 0)

	x = x + bar.resetButton:GetWidth() + bar.exitButton:GetWidth() + bar.saveButton:GetWidth() + 28
	bar:SetWidth(math.min(UIParent:GetWidth() - 20, math.max(x, 700)))

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
end

---Replace the help line (nil restores the default)
---@param text string|nil
function ControlToolbar:SetHint(text)
	self.hintText = text
	self:Refresh()
end

function ControlToolbar:Show()
	local bar = self:Create()
	self:Refresh()
	bar:SetAlpha(0)
	bar:Show()
	Style:FadeTo(bar, 1, 0.2)
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
