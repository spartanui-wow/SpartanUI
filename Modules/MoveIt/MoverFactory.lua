---@type SUI
local SUI = SUI
local L = SUI.L
local print = SUI.print
---@class MoveIt
local MoveIt = SUI.MoveIt

-- Colors for mover frames
local colors = {
	bg = { 0.0588, 0.0588, 0, 0.85 },
	active = { 0.1, 0.1, 0.1, 0.7 },
	border = { 0.00, 0.00, 0.00, 1 },
	text = { 1, 1, 1, 1 },
	disabled = { 0.55, 0.55, 0.55, 1 },
}

local function GetPoints(obj)
	local point, anchor, secondaryPoint, x, y = obj:GetPoint()
	if not anchor then
		anchor = UIParent
	end

	return format('%s,%s,%s,%d,%d', point, anchor:GetName(), secondaryPoint, Round(x), Round(y))
end

local isDragging = false

---@class SUI.MoveIt.MoverParent : Frame, SUI.MoveIt.parentMixin
local parentFrameTemp = {}

---@param parent SUI.MoveIt.MoverParent
---@param name string
---@param DisplayName? string
---@param postdrag? function
---@param groupName? string
---@param widgets? table Ace3-style widget definitions for the settings panel
---@return nil
function MoveIt:CreateMover(parent, name, DisplayName, postdrag, groupName, widgets)
	if SUI:IsModuleDisabled('MoveIt') then
		return
	end
	-- If for some reason the parent does not exist or we have already done this exit out
	if not parent or self.MoverList[name] then
		return
	end
	if DisplayName == nil then
		DisplayName = name
	end

	local point, anchor, secondaryPoint, x, y = strsplit(',', GetPoints(parent))

	--Use dirtyWidth / dirtyHeight to set initial size if possible
	local width = parent.dirtyWidth or parent:GetWidth()
	local height = parent.dirtyHeight or parent:GetHeight()

	---@class SUI.MoveIt.Mover : Frame, BackdropTemplate
	local f = CreateFrame('Button', 'SUI_Mover_' .. name, UIParent, BackdropTemplateMixin and 'BackdropTemplate')
	f:SetClampedToScreen(true)
	f:RegisterForDrag('LeftButton', 'RightButton')
	f:EnableMouseWheel(true)
	f:SetMovable(true)
	f:SetSize(width, height)

	f:SetBackdrop({
		bgFile = 'Interface\\AddOns\\SpartanUI\\images\\blank.tga',
		edgeFile = 'Interface\\AddOns\\SpartanUI\\images\\blank.tga',
		edgeSize = 1,
	})
	f:SetBackdropColor(unpack(colors.bg))
	f:SetBackdropBorderColor(unpack(colors.border))

	f:Hide()
	f.parent = parent
	f.name = name
	f.DisplayName = DisplayName
	f.postdrag = postdrag
	f.defaultScale = (parent:GetScale() or 1)
	f.defaultPoint = GetPoints(parent)
	f.widgets = widgets -- Ace3-style widget definitions for settings panel

	f:SetFrameLevel(parent:GetFrameLevel() + 1)
	f:SetFrameStrata('DIALOG')

	self.MoverList[name] = f

	-- Register frame with magnetism manager if available
	if MoveIt.MagnetismManager then
		MoveIt.MagnetismManager:RegisterFrame(f)
	end

	local nameText = f:CreateFontString(nil, 'OVERLAY')
	SUI.Font:Format(nameText, 12, 'Mover')
	nameText:SetJustifyH('CENTER')
	nameText:SetPoint('CENTER')
	nameText:SetText(DisplayName or name)
	nameText:SetTextColor(unpack(colors.text))
	f:SetFontString(nameText)
	f.DisplayName = nameText

	local MovedText = f:CreateFontString(nil, 'OVERLAY')
	SUI.Font:Format(MovedText, 8, 'Mover')
	MovedText:SetJustifyH('CENTER')
	MovedText:SetPoint('TOPRIGHT', nameText, 'BOTTOM', -2, -2)
	MovedText:SetText('(MOVED)')
	MovedText:SetTextColor(unpack(colors.text))
	MovedText:Hide()
	f.MovedText = MovedText

	local ScaledText = f:CreateFontString(nil, 'OVERLAY')
	SUI.Font:Format(ScaledText, 8, 'Mover')
	ScaledText:SetJustifyH('CENTER')
	ScaledText:SetPoint('TOPLEFT', nameText, 'BOTTOM', 2, -2)
	ScaledText:SetText('(SCALED)')
	ScaledText:SetTextColor(unpack(colors.text))
	ScaledText:Hide()
	f.ScaledText = ScaledText

	f:SetScale(MoveIt.DB.movers[name].AdjustedScale or parent:GetScale() or 1)
	if MoveIt.DB.movers[name].AdjustedScale then
		ScaledText:Show()
		parent:SetScale(MoveIt.DB.movers[name].AdjustedScale)
	end

	if MoveIt.DB.movers[name].MovedPoints then
		MovedText:Show()
		point, anchor, secondaryPoint, x, y = strsplit(',', MoveIt.DB.movers[name].MovedPoints)
	end

	-- Validate anchor frame exists (it may reference a disabled unit frame's mover)
	-- If the anchor is a string and doesn't exist as a global frame, fall back to UIParent
	if type(anchor) == 'string' and anchor ~= 'UIParent' and not _G[anchor] then
		if MoveIt.logger then
			MoveIt.logger.debug(('CreateMover %s: anchor %s does not exist, falling back to UIParent'):format(name, anchor))
		end
		anchor = 'UIParent'
		-- Clear the invalid saved position so it doesn't persist
		MoveIt.DB.movers[name].MovedPoints = nil
		MovedText:Hide()
	end

	f:ClearAllPoints()
	f:SetPoint(point, anchor, secondaryPoint, x, y)

	local function SaveMoverPosition()
		local savedPoints = GetPoints(f)
		MoveIt.DB.movers[name].MovedPoints = savedPoints
		f.MovedText:Show()

		if MoveIt.logger then
			MoveIt.logger.debug(('SaveMoverPosition %s: saved as %s'):format(name, savedPoints))
		end

		-- Debug: Hook SetPoint temporarily to catch unexpected repositioning
		if name == 'pet' and MoveIt.logger then
			local originalSetPoint = f.SetPoint
			f.SetPoint = function(self, ...)
				MoveIt.logger.debug(
					('HOOK: SetPoint called on %s after save: %s,%s,%s,%s,%s'):format(
						name,
						tostring(select(1, ...)),
						tostring(select(2, ...)),
						tostring(select(3, ...)),
						tostring(select(4, ...)),
						tostring(select(5, ...))
					)
				)
				MoveIt.logger.debug(('HOOK: Stack trace: %s'):format(debugstack(2, 3, 3)))
				return originalSetPoint(self, ...)
			end
			-- Remove hook after 5 seconds
			C_Timer.After(5, function()
				f.SetPoint = originalSetPoint
				if MoveIt.logger then
					MoveIt.logger.debug(('HOOK: Removed SetPoint hook from %s'):format(name))
				end
			end)
		end
	end

	local Scale = function(self, ammount)
		local Current = self:GetScale()
		local NewScale = Current + (ammount or 0)

		-- Simply apply scale - don't try to adjust position
		-- The frame scales from its anchor point (CENTER), so position stays stable
		self:SetScale(NewScale)
		self.parent:SetScale(NewScale)

		-- Save the user's scale adjustment to DB
		MoveIt.DB.movers[name].AdjustedScale = NewScale

		-- Only hide the indicator if user resets to default scale
		if NewScale == f.defaultScale then
			MoveIt.DB.movers[name].AdjustedScale = nil
			ScaledText:Hide()
		else
			ScaledText:Show()
		end
	end

	local NudgeMover = function(self, nudgeX, nudgeY)
		local point, anchor, secondaryPoint, x, y = self:GetPoint()
		if not anchor then
			anchor = UIParent
		end
		x = Round(x)
		y = Round(y)

		-- Shift it.
		x = x + (nudgeX or 0)
		y = y + (nudgeY or 0)

		-- Save it.
		self:ClearAllPoints()
		self:SetPoint(point, anchor, secondaryPoint, x, y)
		SaveMoverPosition()
	end

	local function OnDragStart(self)
		if InCombatLockdown() then
			print(ERR_NOT_IN_COMBAT)
			return
		end

		-- DUAL SNAPPING SYSTEM:
		-- - LibSimpleSticky handles frame-to-frame snapping (via its own OnUpdate)
		-- - MagnetismManager handles grid snapping (via our OnUpdate)

		self:StartMoving()

		isDragging = true

		-- Initialize magnetism for grid snapping only
		local MagnetismManager = MoveIt.MagnetismManager
		if MagnetismManager and MagnetismManager:IsGridSnapActive() then
			MagnetismManager:BeginDragSession(self)
		end

		-- Create OnUpdate frame for grid snap preview lines
		if not self.dragUpdateFrame then
			self.dragUpdateFrame = CreateFrame('Frame')
		end
		self.dragUpdateFrame:SetScript('OnUpdate', function()
			-- Check IsGridSnapActive() each frame to handle toggle
			if MagnetismManager and MagnetismManager:IsGridSnapActive() then
				local snapInfo = MagnetismManager:CheckForSnaps(self)
				if snapInfo then
					MagnetismManager:ShowPreviewLines(snapInfo)
				else
					MagnetismManager:HidePreviewLines()
				end
			elseif MagnetismManager then
				-- Hide preview lines when grid snap is disabled
				MagnetismManager:HidePreviewLines()
			end

			-- Update settings panel position display during drag
			local SettingsPanel = MoveIt.SettingsPanel
			if SettingsPanel and SettingsPanel.nudgeWidget and SettingsPanel.nudgeWidget.UpdatePositionDisplay then
				SettingsPanel.nudgeWidget:UpdatePositionDisplay()
			end
		end)
	end

	local function OnDragStop(self)
		if InCombatLockdown() then
			print(ERR_NOT_IN_COMBAT)
			return
		end
		isDragging = false

		self:StopMovingOrSizing()

		SaveMoverPosition()

		self:SetUserPlaced(false)

		-- Update settings panel position display after drag
		local SettingsPanel = MoveIt.SettingsPanel
		if SettingsPanel and SettingsPanel.nudgeWidget and SettingsPanel.nudgeWidget.UpdatePositionDisplay then
			SettingsPanel.nudgeWidget:UpdatePositionDisplay()
		end
	end

	local function OnEnter(self)
		if isDragging then
			return
		end
		self:SetBackdropColor(unpack(colors.active))
		self.DisplayName:SetTextColor(1, 1, 1)
	end

	local function OnMouseDown(self, button)
		if button == 'LeftButton' and not isDragging then
			-- if NudgeWindow:IsShown() then
			-- 	NudgeWindow:Hide()
			-- else
			-- 	NudgeWindow:Show()
			-- end
		end

		if IsAltKeyDown() then -- Reset anchor
			MoveIt:Reset(name)
			if MoveIt.DB.tips then
				print("Tip use the chat command '/sui move reset' to reset everything quickly.")
			end
		elseif IsControlKeyDown() then -- Reset Scale to default
			self:SetScale(self.defaultScale)
			self.parent:SetScale(self.defaultScale)
			ScaledText:Hide()

			MoveIt.DB.movers[name].AdjustedScale = nil
		elseif IsShiftKeyDown() then -- Allow hiding a mover temporarily
			self:Hide()
			print(self.name .. ' hidden temporarily.')
		end
	end

	local function OnLeave(self)
		if isDragging then
			return
		end
		self:SetBackdropColor(unpack(colors.bg))
	end

	local function OnShow(self)
		self:SetBackdropBorderColor(unpack(colors.bg))
	end

	local function OnMouseWheel(_, delta)
		if IsAltKeyDown() then
			f:Scale((delta / 100))
		elseif IsShiftKeyDown() then
			f:NudgeMover(nil, delta)
		else
			f:NudgeMover(delta)
		end
	end

	f.Scale = Scale
	f.NudgeMover = NudgeMover
	f:SetScript('OnDragStart', OnDragStart)
	f:SetScript('OnDragStop', OnDragStop)
	f:SetScript('OnEnter', OnEnter)
	f:SetScript('OnMouseDown', OnMouseDown)
	f:SetScript('OnLeave', OnLeave)
	f:SetScript('OnShow', OnShow)
	f:SetScript('OnMouseWheel', OnMouseWheel)

	local DragMoving = false
	local function ParentMouseDown(self)
		if IsAltKeyDown() and MoveIt.DB.AltKey then
			OnDragStart(self.mover)
			DragMoving = true
		end
	end
	local function ParentMouseUp(self)
		if DragMoving then
			OnDragStop(self.mover)
		end
	end
	local function scale(self, scale, setDefault, forced)
		if setDefault then
			f.defaultScale = scale
		end

		-- If user has adjusted scale and we're not forcing, don't change anything
		if MoveIt.DB.movers[name].AdjustedScale and not forced then
			if MoveIt.logger then
				MoveIt.logger.debug(('scale() for %s: skipped due to AdjustedScale'):format(name))
			end
			return
		end

		-- IMPORTANT: If the frame has been MOVED, we should not change its scale
		-- because the saved coordinates were calculated at the current scale.
		-- Changing scale would make those coordinates represent a different position.
		if MoveIt.DB.movers[name].MovedPoints and not forced then
			if MoveIt.logger then
				MoveIt.logger.debug(('scale() for %s: skipped due to MovedPoints'):format(name))
			end
			return
		end

		f:SetScale(max((scale or f.defaultScale), 0.01))
		if f.OnScale then
			f.OnScale:SetScale(max((scale or f.defaultScale), 0.01))
		end
		parent:SetScale(max((scale or f.defaultScale), 0.01))

		-- Only show scaled indicator if user has actually adjusted the scale
		-- Not when themes or other internal systems change it programmatically
		if MoveIt.DB.movers[name].AdjustedScale then
			ScaledText:Show()
		else
			ScaledText:Hide()
		end

		local point, anchor, secondaryPoint, x, y = strsplit(',', f.defaultPoint)

		if MoveIt.DB.movers[name].MovedPoints then
			point, anchor, secondaryPoint, x, y = strsplit(',', MoveIt.DB.movers[name].MovedPoints)
		end

		-- Ensure x and y are numbers (strsplit returns strings)
		x = tonumber(x) or 0
		y = tonumber(y) or 0

		-- Validate anchor frame exists (it may reference a disabled unit frame's mover)
		if type(anchor) == 'string' and anchor ~= 'UIParent' and not _G[anchor] then
			if MoveIt.logger then
				MoveIt.logger.debug(('scale() for %s: anchor %s does not exist, falling back to UIParent'):format(name, anchor))
			end
			anchor = 'UIParent'
		end

		if MoveIt.logger then
			MoveIt.logger.debug(('scale() for %s: repositioning to %s,%s,%s,%.1f,%.1f'):format(name, point or 'nil', anchor or 'nil', secondaryPoint or 'nil', x, y))
		end

		f:ClearAllPoints()
		f:SetPoint(point, anchor, secondaryPoint, x, y)
	end
	local function position(self, point, anchor, secondaryPoint, x, y, forced, defaultPos)
		-- If Frame:position() was called just make sure we are anchored properly
		if not point then
			self:ClearAllPoints()
			self:SetPoint('TOPLEFT', self.mover, 0, 0)
			return
		end

		-- If the frame has been moved and we are not forcing the movement, exit
		if MoveIt.DB.movers[name].MovedPoints and not forced then
			return
		end

		-- Position frame
		f:ClearAllPoints()
		f:SetPoint(point, (anchor or UIParent), (secondaryPoint or point), (x or 0), (y or 0))

		-- Register frame relationships for magnetism (for non-unit-frame movers)
		-- Unit frames register their relationships separately after all movers are created
		if anchor and anchor ~= UIParent and self.mover and MoveIt.MagnetismManager then
			local anchorFrame = anchor
			if type(anchor) == 'string' then
				anchorFrame = _G[anchor]
			end

			if anchorFrame and anchorFrame.mover then
				MoveIt.MagnetismManager:RegisterFrameRelationship(self.mover, anchorFrame.mover)
			end
		end

		if defaultPos then
			f.defaultPoint = GetPoints(f)
		end
	end
	local function SizeChanged(frame)
		if InCombatLockdown() then
			return
		end
		if frame.mover.updateObj then
			frame.mover:SetSize(frame.mover.updateObj:GetSize())
		else
			frame.mover:SetSize(frame:GetSize())
		end
	end

	hooksecurefunc(parent, 'SetSize', SizeChanged)
	hooksecurefunc(parent, 'SetHeight', SizeChanged)
	hooksecurefunc(parent, 'SetWidth', SizeChanged)

	parent:HookScript('OnMouseDown', ParentMouseDown)
	parent:HookScript('OnMouseUp', ParentMouseUp)
	---@class SUI.MoveIt.parentMixin
	local parentMixin = {
		scale = scale,
		position = position,
		mover = f,
		dirtyWidth = 0,
		dirtyHeight = 0,
	}
	for k, v in pairs(parentMixin) do
		parent[k] = v
	end
	parent.isMoved = function()
		if MoveIt.DB.movers[name].MovedPoints then
			return true
		end
		return false
	end

	parent:ClearAllPoints()
	parent:SetPoint('TOPLEFT', f, 0, 0)

	-- Blizz mover holders intercept mouse events when visible (HookScript enables mouse).
	-- Hide them immediately; MoverMode:Enter/Exit manages their visibility.
	if parent.isBlizzMoverHolder then
		parent:Hide()
	end

	self:AddToOptions(name, DisplayName, (groupName or 'General'), f)
end

function MoveIt:RegisterExternalMover(mover, name)
	if not mover or not name then
		return
	end

	if not self.MoverList[name] then
		self.MoverList[name] = mover
		mover.name = name

		return true
	end
	return false
end

function MoveIt:CreateCustomMover(displayName, defaultPosition, config)
	-- Generate a unique name based on the display name
	local name = 'SUI_CustomMover_' .. displayName:gsub('%s+', '')

	-- Default configuration options
	local cfg = {
		width = 180,
		height = 180,
		colors = {
			bg = { 0.2, 0.0, 0.0, 0.85 }, -- Reddish background to distinguish from regular movers
			active = { 0.3, 0.1, 0.1, 0.7 },
			border = { 0.5, 0.0, 0.0, 1 },
			text = { 1, 1, 1, 1 },
		},
		onPositionChanged = nil, -- Callback function
		savePosition = nil, -- Function to handle position saving
		onHide = nil, -- Function called when mover is hidden
	}

	-- Override defaults with any provided config
	if config then
		for k, v in pairs(config) do
			cfg[k] = v
		end
	end

	-- Create the mover frame
	local mover = CreateFrame('Button', name, UIParent, BackdropTemplateMixin and 'BackdropTemplate')
	mover:SetClampedToScreen(true)
	mover:RegisterForDrag('LeftButton', 'RightButton')
	mover:EnableMouseWheel(true)
	mover:SetMovable(true)
	mover:SetSize(cfg.width, cfg.height)

	mover:SetBackdrop({
		bgFile = 'Interface\\AddOns\\SpartanUI\\images\\blank.tga',
		edgeFile = 'Interface\\AddOns\\SpartanUI\\images\\blank.tga',
		edgeSize = 1,
	})
	mover:SetBackdropColor(unpack(cfg.colors.bg))
	mover:SetBackdropBorderColor(unpack(cfg.colors.border))

	mover:Hide()
	mover.defaultPoint = defaultPosition
	mover.displayName = displayName
	mover.savedPosition = nil

	mover:SetFrameLevel(100)
	mover:SetFrameStrata('DIALOG')

	-- Create text elements
	local nameText = mover:CreateFontString(nil, 'OVERLAY')
	SUI.Font:Format(nameText, 12, 'Mover')
	nameText:SetJustifyH('CENTER')
	nameText:SetPoint('CENTER')
	nameText:SetText(displayName)
	nameText:SetTextColor(unpack(cfg.colors.text))
	mover:SetFontString(nameText)
	mover.DisplayName = nameText

	local helpText = mover:CreateFontString(nil, 'OVERLAY')
	SUI.Font:Format(helpText, 8, 'Mover')
	helpText:SetJustifyH('CENTER')
	helpText:SetPoint('BOTTOM', nameText, 'TOP', 0, 2)
	helpText:SetText(L['Drag to set position'])
	helpText:SetTextColor(unpack(cfg.colors.text))
	mover.HelpText = helpText

	-- Set initial position from saved settings
	local point, anchor, secondaryPoint, x, y = strsplit(',', defaultPosition)
	-- Validate anchor frame exists, fall back to UIParent if not
	local anchorFrame = _G[anchor]
	if not anchorFrame then
		if MoveIt.logger then
			MoveIt.logger.debug(('CreateCustomMover %s: anchor %s does not exist, falling back to UIParent'):format(name, anchor or 'nil'))
		end
		anchorFrame = UIParent
	end
	mover:ClearAllPoints()
	mover:SetPoint(point, anchorFrame, secondaryPoint, x, y)

	-- Script handlers for dragging
	local isDraggingCustom = false

	mover:SetScript('OnDragStart', function(self)
		if InCombatLockdown() then
			SUI:Print(ERR_NOT_IN_COMBAT)
			return
		end

		self:StartMoving()
		isDraggingCustom = true
	end)

	mover:SetScript('OnDragStop', function(self)
		if InCombatLockdown() then
			SUI:Print(ERR_NOT_IN_COMBAT)
			return
		end

		isDraggingCustom = false
		self:StopMovingOrSizing()

		-- Save the position
		local point, anchor, secondaryPoint, x, y = self:GetPoint()
		if not anchor then
			anchor = UIParent
		end

		local anchorName = anchor:GetName() or 'UIParent'
		self.savedPosition = format('%s,%s,%s,%d,%d', point, anchorName, secondaryPoint, Round(x), Round(y))

		-- Call custom save function if provided
		if cfg.savePosition then
			cfg.savePosition(self.savedPosition)
		end

		-- Callback for position change
		if cfg.onPositionChanged then
			cfg.onPositionChanged(self)
		end

		self:SetUserPlaced(false)
	end)

	mover:SetScript('OnEnter', function(self)
		if isDraggingCustom then
			return
		end
		self:SetBackdropColor(unpack(cfg.colors.active))
	end)

	mover:SetScript('OnLeave', function(self)
		if isDraggingCustom then
			return
		end
		self:SetBackdropColor(unpack(cfg.colors.bg))
	end)

	mover:SetScript('OnMouseDown', function(self, button)
		if InCombatLockdown() then
			SUI:Print(ERR_NOT_IN_COMBAT)
			return
		elseif IsAltKeyDown() then
			self:Hide()
			if cfg.onHide then
				cfg.onHide()
			end
			return
		end

		if button == 'RightButton' then
			-- Reset to default position
			local point, anchor, secondaryPoint, x, y = strsplit(',', self.defaultPoint)
			-- Validate anchor frame exists, fall back to UIParent if not
			local anchorFrame = _G[anchor]
			if not anchorFrame then
				anchorFrame = UIParent
			end
			self:ClearAllPoints()
			self:SetPoint(point, anchorFrame, secondaryPoint, x, y)

			self.savedPosition = nil

			if cfg.savePosition then
				cfg.savePosition(self.defaultPoint)
			end

			SUI:Print(L['Position reset to default'])
		end
	end)

	mover:SetScript('OnMouseWheel', function(self, delta)
		if IsShiftKeyDown() then
			-- Vertical nudge
			local point, anchor, secondaryPoint, x, y = self:GetPoint()
			if not anchor then
				anchor = UIParent
			end

			y = y + delta

			self:ClearAllPoints()
			self:SetPoint(point, anchor, secondaryPoint, x, y)
		else
			-- Horizontal nudge
			local point, anchor, secondaryPoint, x, y = self:GetPoint()
			if not anchor then
				anchor = UIParent
			end

			x = x + delta

			self:ClearAllPoints()
			self:SetPoint(point, anchor, secondaryPoint, x, y)
		end
	end)

	-- Add Escape key handling
	mover:SetScript('OnKeyDown', function(self, key)
		if key == 'ESCAPE' then
			self:Hide()
			if cfg.onHide then
				cfg.onHide()
			end
			return
		end
	end)
	mover:EnableKeyboard(true)

	-- Register with UISpecialFrames for Escape handling
	tinsert(UISpecialFrames, name)

	-- Register with MoveIt system
	self.MoverList[name] = mover

	return mover
end

---Create two debug test movers for snapping troubleshooting
---Call with: /run SUI.MoveIt:CreateDebugTestMovers()
function MoveIt:CreateDebugTestMovers()
	-- Remove existing test movers if they exist
	if self.MoverList['DebugTestMover1'] then
		self.MoverList['DebugTestMover1']:Hide()
		self.MoverList['DebugTestMover1'] = nil
	end
	if self.MoverList['DebugTestMover2'] then
		self.MoverList['DebugTestMover2']:Hide()
		self.MoverList['DebugTestMover2'] = nil
	end

	-- Create test mover parent frames (required for CreateMover)
	local parent1 = CreateFrame('Frame', 'SUI_DebugTestParent1', UIParent)
	parent1:SetSize(50, 50)
	parent1:SetPoint('CENTER', UIParent, 'CENTER', -100, 100)

	local parent2 = CreateFrame('Frame', 'SUI_DebugTestParent2', UIParent)
	parent2:SetSize(50, 50)
	parent2:SetPoint('CENTER', UIParent, 'CENTER', 100, 100)

	-- Initialize DB entries for the test movers
	if not MoveIt.DB.movers['DebugTestMover1'] then
		MoveIt.DB.movers['DebugTestMover1'] = { defaultPoint = false, MovedPoints = false }
	end
	if not MoveIt.DB.movers['DebugTestMover2'] then
		MoveIt.DB.movers['DebugTestMover2'] = { defaultPoint = false, MovedPoints = false }
	end

	-- Create the movers using standard CreateMover
	MoveIt:CreateMover(parent1, 'DebugTestMover1', 'Test Box 1', nil, 'Debug')
	MoveIt:CreateMover(parent2, 'DebugTestMover2', 'Test Box 2', nil, 'Debug')

	-- Show the test movers
	if self.MoverList['DebugTestMover1'] then
		self.MoverList['DebugTestMover1']:Show()
	end
	if self.MoverList['DebugTestMover2'] then
		self.MoverList['DebugTestMover2']:Show()
	end

	if MoveIt.logger then
		MoveIt.logger.info('Created 2 debug test movers (50x50)')
	end

	print('Debug test movers created. Use /sui move to see them.')
end

---Remove debug test movers
---Call with: /run SUI.MoveIt:RemoveDebugTestMovers()
function MoveIt:RemoveDebugTestMovers()
	if self.MoverList['DebugTestMover1'] then
		self.MoverList['DebugTestMover1']:Hide()
		self.MoverList['DebugTestMover1'] = nil
	end
	if self.MoverList['DebugTestMover2'] then
		self.MoverList['DebugTestMover2']:Hide()
		self.MoverList['DebugTestMover2'] = nil
	end
	if _G['SUI_DebugTestParent1'] then
		_G['SUI_DebugTestParent1']:Hide()
	end
	if _G['SUI_DebugTestParent2'] then
		_G['SUI_DebugTestParent2']:Hide()
	end
	print('Debug test movers removed.')
end
