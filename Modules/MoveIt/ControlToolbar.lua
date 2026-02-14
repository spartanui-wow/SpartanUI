---@class SUI
local SUI = SUI
---@class MoveIt
local MoveIt = SUI.MoveIt

---@class SUI.MoveIt.ControlToolbar
local ControlToolbar = {}
MoveIt.ControlToolbar = ControlToolbar

-- Constants
local TOOLBAR_WIDTH = 460
local TOOLBAR_HEIGHT = 80
local PADDING = 10
local CONTROL_HEIGHT = 24

-- Backdrop texture paths
local BACKDROP = {
	bgFile = 'Interface\\DialogFrame\\UI-DialogBox-Background-Dark',
	edgeFile = 'Interface\\AddOns\\SpartanUI\\images\\blank.tga',
	edgeSize = 2,
}

---Create the control toolbar frame
function ControlToolbar:Create()
	if self.toolbar then
		return self.toolbar
	end

	local toolbar = CreateFrame('Frame', 'SUI_MoveIt_ControlToolbar', UIParent, BackdropTemplateMixin and 'BackdropTemplate')
	toolbar:SetSize(TOOLBAR_WIDTH, TOOLBAR_HEIGHT)
	toolbar:SetPoint('BOTTOM', UIParent, 'BOTTOM', 0, 100)
	toolbar:SetFrameStrata('DIALOG')
	toolbar:SetFrameLevel(200)
	toolbar:SetMovable(true)
	toolbar:EnableMouse(true)
	toolbar:SetClampedToScreen(true)
	toolbar:Hide()

	-- Backdrop
	toolbar:SetBackdrop(BACKDROP)
	toolbar:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
	toolbar:SetBackdropBorderColor(0.2, 0.6, 1.0, 1.0)

	-- Draggable
	toolbar:RegisterForDrag('LeftButton')
	toolbar:SetScript('OnDragStart', function(self)
		self:StartMoving()
	end)
	toolbar:SetScript('OnDragStop', function(self)
		self:StopMovingOrSizing()
	end)

	-- Title (left side, top)
	local title = toolbar:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
	title:SetPoint('TOPLEFT', toolbar, 'TOPLEFT', PADDING, -PADDING)
	title:SetText('SpartanUI Frame Mover')
	title:SetTextColor(1, 0.82, 0, 1)

	-- Hint text (bottom center)
	local hint = toolbar:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
	hint:SetPoint('BOTTOM', toolbar, 'BOTTOM', 0, 6)
	hint:SetText('Press ESC or click Done to exit')
	hint:SetTextColor(0.6, 0.6, 0.6, 1)

	-- Controls row
	local controlsY = -32

	-- Done button (right side, prominent)
	local doneBtn = CreateFrame('Button', nil, toolbar, 'UIPanelButtonTemplate')
	doneBtn:SetSize(70, CONTROL_HEIGHT)
	doneBtn:SetPoint('TOPRIGHT', toolbar, 'TOPRIGHT', -PADDING, controlsY)
	doneBtn:SetText('Done')
	doneBtn:SetScript('OnClick', function()
		if MoveIt.MoverMode then
			MoveIt.MoverMode:Exit()
		end
	end)
	toolbar.doneBtn = doneBtn

	-- Reset All button (next to Done)
	local resetBtn = CreateFrame('Button', nil, toolbar, 'UIPanelButtonTemplate')
	resetBtn:SetSize(80, CONTROL_HEIGHT)
	resetBtn:SetPoint('RIGHT', doneBtn, 'LEFT', -8, 0)
	resetBtn:SetText('Reset All')
	resetBtn:SetScript('OnClick', function()
		StaticPopupDialogs['SUI_MOVEIT_RESET_ALL'] = {
			text = 'Reset all frames to default positions? This cannot be undone.',
			button1 = 'Reset',
			button2 = 'Cancel',
			OnAccept = function()
				MoveIt:Reset()
			end,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
		}
		StaticPopup_Show('SUI_MOVEIT_RESET_ALL')
	end)
	toolbar.resetBtn = resetBtn

	-- Show Grid checkbox (controls both grid visibility and grid snapping)
	local gridCheck = CreateFrame('CheckButton', 'SUI_MoveIt_GridCheck', toolbar, 'UICheckButtonTemplate')
	gridCheck:SetSize(CONTROL_HEIGHT, CONTROL_HEIGHT)
	gridCheck:SetPoint('TOPLEFT', toolbar, 'TOPLEFT', PADDING, controlsY)
	gridCheck:SetScript('OnClick', function(self)
		local checked = self:GetChecked()
		MoveIt.DB.GridSnapEnabled = checked
		if MoveIt.GridOverlay then
			if checked then
				MoveIt.GridOverlay:Show()
			else
				MoveIt.GridOverlay:Hide()
			end
		end
		if MoveIt.MagnetismManager then
			MoveIt.MagnetismManager:UpdateGridLines()
		end
	end)
	local gridLabel = toolbar:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
	gridLabel:SetPoint('LEFT', gridCheck, 'RIGHT', 2, 0)
	gridLabel:SetText('Grid Snap')
	toolbar.gridCheck = gridCheck

	-- Frame Snap checkbox (controls frame-to-frame snapping)
	local elemSnapCheck = CreateFrame('CheckButton', 'SUI_MoveIt_ElemSnapCheck', toolbar, 'UICheckButtonTemplate')
	elemSnapCheck:SetSize(CONTROL_HEIGHT, CONTROL_HEIGHT)
	elemSnapCheck:SetPoint('LEFT', gridLabel, 'RIGHT', 12, 0)
	elemSnapCheck:SetScript('OnClick', function(self)
		MoveIt.DB.ElementSnapEnabled = self:GetChecked()
	end)
	local elemSnapLabel = toolbar:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
	elemSnapLabel:SetPoint('LEFT', elemSnapCheck, 'RIGHT', 2, 0)
	elemSnapLabel:SetText('Frame Snap')
	toolbar.elemSnapCheck = elemSnapCheck

	-- Grid Size slider
	local gridSizeLabel = toolbar:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
	gridSizeLabel:SetPoint('LEFT', elemSnapLabel, 'RIGHT', 14, 0)
	gridSizeLabel:SetText('Grid: ' .. (MoveIt.DB.GridSpacing or 32))
	toolbar.gridSizeLabel = gridSizeLabel

	local gridSlider = CreateFrame('Slider', 'SUI_MoveIt_GridSlider', toolbar, 'OptionsSliderTemplate')
	gridSlider:SetSize(80, 16)
	gridSlider:SetPoint('LEFT', gridSizeLabel, 'RIGHT', 6, 0)
	gridSlider:SetMinMaxValues(16, 64)
	gridSlider:SetValueStep(4)
	gridSlider:SetObeyStepOnDrag(true)
	gridSlider:SetValue(MoveIt.DB.GridSpacing or 32)
	-- Hide the built-in min/max/value text
	local sliderLow = gridSlider.Low or _G[gridSlider:GetName() .. 'Low']
	local sliderHigh = gridSlider.High or _G[gridSlider:GetName() .. 'High']
	local sliderText = gridSlider.Text or _G[gridSlider:GetName() .. 'Text']
	if sliderLow then
		sliderLow:SetText('')
	end
	if sliderHigh then
		sliderHigh:SetText('')
	end
	if sliderText then
		sliderText:SetText('')
	end
	gridSlider:SetScript('OnValueChanged', function(self, value)
		value = math.floor(value + 0.5)
		MoveIt.DB.GridSpacing = value
		gridSizeLabel:SetText('Grid: ' .. value)
		if MoveIt.GridOverlay and MoveIt.GridOverlay.Refresh then
			MoveIt.GridOverlay:Refresh()
		end
		if MoveIt.MagnetismManager then
			MoveIt.MagnetismManager:UpdateGridLines()
		end
	end)
	toolbar.gridSlider = gridSlider

	self.toolbar = toolbar
	return toolbar
end

---Show the toolbar and sync toggle states from DB
function ControlToolbar:Show()
	if not self.toolbar then
		self:Create()
	end

	-- Sync toggle states with current DB values
	if self.toolbar.gridCheck then
		self.toolbar.gridCheck:SetChecked(MoveIt.DB.GridSnapEnabled ~= false)
	end
	if self.toolbar.elemSnapCheck then
		self.toolbar.elemSnapCheck:SetChecked(MoveIt.DB.ElementSnapEnabled ~= false)
	end
	if self.toolbar.gridSlider then
		self.toolbar.gridSlider:SetValue(MoveIt.DB.GridSpacing or 32)
	end
	if self.toolbar.gridSizeLabel then
		self.toolbar.gridSizeLabel:SetText('Grid: ' .. (MoveIt.DB.GridSpacing or 32))
	end

	self.toolbar:Show()
end

---Hide the toolbar
function ControlToolbar:Hide()
	if self.toolbar then
		self.toolbar:Hide()
	end
end

---Check if toolbar is shown
---@return boolean
function ControlToolbar:IsShown()
	return self.toolbar and self.toolbar:IsShown() or false
end
