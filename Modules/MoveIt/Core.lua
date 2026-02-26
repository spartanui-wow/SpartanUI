local SUI, L, print = SUI, SUI.L, SUI.print
---@class MoveIt : AceAddon, AceHook-3.0, AceEvent-3.0, AceTimer-3.0
local MoveIt = SUI:NewModule('MoveIt', 'AceHook-3.0') ---@type SUI.Module
MoveIt.description = 'CORE: Is the movement system for SpartanUI'
MoveIt.Core = true
SUI.MoveIt = MoveIt

-- Shared state (accessed by other MoveIt files via MoveIt.MoverList, etc.)
MoveIt.MoverList = {}

-- MoverWatcher frame for keyboard input handling
local MoverWatcher = CreateFrame('Frame', nil, UIParent)
local MoveEnabled = false

function MoveIt:CalculateMoverPoints(mover)
	local screenWidth, screenHeight, screenCenter = UIParent:GetRight(), UIParent:GetTop(), UIParent:GetCenter()
	local x, y = mover:GetCenter()

	local LEFT = screenWidth / 3
	local RIGHT = screenWidth * 2 / 3
	local TOP = screenHeight / 2
	local point, InversePoint

	if y >= TOP then
		point = 'TOP'
		InversePoint = 'BOTTOM'
		y = -(screenHeight - mover:GetTop())
	else
		point = 'BOTTOM'
		InversePoint = 'TOP'
		y = mover:GetBottom()
	end

	if x >= RIGHT then
		point = point .. 'RIGHT'
		InversePoint = 'LEFT'
		x = mover:GetRight() - screenWidth
	elseif x <= LEFT then
		point = point .. 'LEFT'
		InversePoint = 'RIGHT'
		x = mover:GetLeft()
	else
		x = x - screenCenter
	end

	--Update coordinates if nudged
	x = x
	y = y

	return x, y, point, InversePoint
end

function MoveIt:IsMoved(name)
	if not MoveIt.DB.movers[name] then
		return false
	end
	if MoveIt.DB.movers[name].MovedPoints then
		return true
	end
	if MoveIt.DB.movers[name].AdjustedScale then
		return true
	end
	return false
end

function MoveIt:Reset(name, onlyPosition)
	local MoverList = self.MoverList
	if name == nil then
		for moverName, frame in pairs(MoverList) do
			MoveIt:Reset(moverName)
		end
		print('Moved frames reset!')
	else
		local frame = _G['SUI_Mover_' .. name]
		if frame and MoveIt:IsMoved(name) and MoveIt.DB.movers[name] then
			-- Reset Position
			local point, anchor, secondaryPoint, x, y = strsplit(',', MoverList[name].defaultPoint)
			frame:ClearAllPoints()
			frame:SetPoint(point, anchor, secondaryPoint, x, y)

			if onlyPosition or not MoveIt.DB.movers[name].AdjustedScale then
				MoveIt.DB.movers[name].MovedPoints = nil
			else
				-- Reset the scale
				if MoveIt.DB.movers[name].AdjustedScale and not onlyPosition then
					frame:SetScale(frame.defaultScale or 1)
					frame.parent:SetScale(frame.defaultScale or 1)
					frame.ScaledText:Hide()
				end
				-- Clear element
				MoveIt.DB.movers[name] = nil
			end

			-- Hide Moved Text
			frame.MovedText:Hide()
		end
	end
end

function MoveIt:GetMover(name)
	return self.MoverList[name]
end

function MoveIt:UpdateMover(name, obj, doNotScale)
	local mover = self.MoverList[name]

	if not mover then
		return
	end
	-- This allows us to assign a new object to be used to assign the mover's size
	-- Removing this breaks the positioning of objects when the wow window is resized as it triggers the SizeChanged event.
	if mover.parent ~= obj then
		mover.updateObj = obj
	end

	local f = (obj or mover.updateObj or mover.parent)
	mover:SetSize(f:GetWidth(), f:GetHeight())
	if not doNotScale then
		mover:SetScale(f:GetScale())
	end
end

function MoveIt:UnlockAll()
	-- Skip if migration is in progress (wizard is applying changes)
	if MoveIt.WizardPage and MoveIt.WizardPage:IsMigrationInProgress() then
		if MoveIt.logger then
			MoveIt.logger.debug('UnlockAll: Suppressed during migration')
		end
		return
	end

	-- Check if MoverMode was already exited (prevents race condition with quick exit)
	if MoveIt.MoverMode and not MoveIt.MoverMode:IsActive() then
		if MoveIt.logger then
			MoveIt.logger.debug('UnlockAll: Cancelled - MoverMode already exited')
		end
		return
	end

	-- Debug logging to trace who's calling UnlockAll
	if MoveIt.logger then
		local stack = debugstack(2, 2, 0) -- Get caller stack
		MoveIt.logger.debug('UnlockAll called from: ' .. (stack or 'unknown'))
	end

	-- Set flag indicating unlock is in progress
	self.unlockInProgress = true

	-- Show movers with intermediate checks for early exit
	local shownCount = 0
	for _, v in pairs(self.MoverList) do
		-- Check if LockAll() was called (MoveEnabled became false)
		if not MoveEnabled then
			if MoveIt.logger then
				MoveIt.logger.debug(('UnlockAll: LockAll was called during unlock after showing %d movers - aborting'):format(shownCount))
			end
			self.unlockInProgress = false
			return
		end

		-- Check if MoverMode exited while we're showing movers (race condition protection)
		if MoveIt.MoverMode and not MoveIt.MoverMode:IsActive() then
			if MoveIt.logger then
				MoveIt.logger.debug(('UnlockAll: MoverMode exited during unlock after showing %d movers - aborting and locking'):format(shownCount))
			end
			self.unlockInProgress = false
			-- Lock any movers we already showed
			self:LockAll()
			return
		end
		v:Show()
		shownCount = shownCount + 1
	end

	self.unlockInProgress = false
	MoveEnabled = true
	MoverWatcher:Show()

	if MoveIt.logger then
		MoveIt.logger.debug(('UnlockAll: Completed showing %d movers, MoveEnabled=true'):format(shownCount))
	end

	if MoveIt.DB.tips then
		print('When the movement system is enabled you can:')
		print('     Shift+Click a mover to temporarily hide it', true)
		print("     Alt+Click a mover to reset it's position", true)
		print("     Control+Click a mover to reset it's scale", true)
		print(' ', true)
		print('     Use the scroll wheel to move left and right 1 coord at a time', true)
		print('     Hold Shift + use the scroll wheel to move up and down 1 coord at a time', true)
		print('     Hold Alt + use the scroll wheel to scale the frame', true)
		print(' ', true)
		-- Classic-specific tip for magnetism
		if not SUI.IsRetail then
			print('     Hold Shift while dragging to enable snap/magnetism', true)
			print(' ', true)
		end
		print('     Press ESCAPE to exit the movement system quickly.', true)
		print("Use the command '/sui move tips' to disable tips")
		print("Use the command '/sui move reset' to reset ALL moved items")
	end
end

function MoveIt:LockAll()
	if MoveIt.logger then
		MoveIt.logger.debug(('LockAll called - MoveEnabled=%s, unlockInProgress=%s'):format(tostring(MoveEnabled), tostring(self.unlockInProgress)))
	end

	-- Exit MoverMode first if active (handles hiding movers, canceling timers, hiding grid, cleaning up magnetism)
	if MoveIt.MoverMode and MoveIt.MoverMode:IsActive() then
		if MoveIt.logger then
			MoveIt.logger.debug('LockAll: Exiting MoverMode')
		end
		MoveIt.MoverMode:Exit()
		MoveEnabled = false
		MoverWatcher:Hide()
		return
	end

	-- Cancel any in-progress unlock operation
	if self.unlockInProgress then
		if MoveIt.logger then
			MoveIt.logger.debug('LockAll: Cancelling in-progress unlock')
		end
		self.unlockInProgress = false
	end

	local hiddenCount = 0
	for _, v in pairs(self.MoverList) do
		if v:IsShown() then
			hiddenCount = hiddenCount + 1
		end
		v:Hide()
	end

	if MoveIt.logger then
		MoveIt.logger.debug(('LockAll: Hid %d visible movers'):format(hiddenCount))
	end

	MoveEnabled = false
	MoverWatcher:Hide()
end

---Enter user move mode (explicit user action to reposition frames)
function MoveIt:EnterMoveMode()
	if InCombatLockdown() then
		print(ERR_NOT_IN_COMBAT)
		return
	end

	-- Use MoverMode for full custom mover experience (independent of Blizzard EditMode)
	if MoveIt.MoverMode then
		MoveIt.MoverMode:Enter()
		if MoveIt.logger then
			MoveIt.logger.debug('EnterMoveMode: Activated MoverMode')
		end
	else
		-- Fallback to legacy unlock
		if MoveIt.logger then
			MoveIt.logger.debug('EnterMoveMode: Using legacy mover system (fallback)')
		end
		self:UnlockAll()
	end
end

function MoveIt:MoveIt(name)
	if MoveEnabled and not name then
		MoveIt:LockAll()
	else
		if name then
			if type(name) == 'string' then
				local frame = self.MoverList[name]
				if not frame:IsVisible() then
					frame:Show()
				else
					frame:Hide()
				end
			else
				for _, v in pairs(name) do
					if self.MoverList[v] then
						local frame = self.MoverList[v]
						frame:Show()
					end
				end
			end
		else
			MoveIt:UnlockAll()
		end
	end
	MoverWatcher:EnableKeyboard(MoveEnabled)
end

function MoveIt:OnInitialize()
	---@class MoveItDB
	local defaults = {
		profile = {
			AltKey = false,
			tips = true,
			-- Position anchor mode: how frame positions are saved
			-- 'center' = Always use CENTER anchor (legacy behavior)
			-- 'cardinal' = Use closest edge or center (5 anchors: CENTER, TOP, BOTTOM, LEFT, RIGHT)
			-- 'corners' = Use closest edge or corner (9 anchors: all 5 cardinal + 4 corners)
			anchorMode = 'corners',
			movers = {
				['**'] = {
					defaultPoint = false,
					MovedPoints = false,
				},
			},
			-- Grid spacing for magnetism snap (pixels)
			GridSpacing = 40,
			-- Grid snap: show grid overlay and snap to grid lines
			GridSnapEnabled = false,
			-- Element snap: snap to other frame edges and corners
			ElementSnapEnabled = true,
			-- EditMode profile sync (optional feature)
			-- When enabled, changes to SUI profiles will automatically switch the EditMode profile
			SyncEditModeProfile = false,
		},
		global = {
			-- Per-character current EditMode profile tracking (keyed by "CharName - Realm")
			-- Stored globally to avoid conflicts when multiple characters share the same SUI profile
			-- Used by EditModeProfileSync feature
			CurrentProfiles = {},
			-- Migration flag to track EditMode positioning removal
			EditModePositioningRemoved = false,
			-- Version-based migration tracker for minimap container offset fix (6.19.0)
			MinimapOffsetMigrationVersion = false,
		},
	}
	---@type MoveItDB
	MoveIt.Database = SUI.SpartanUIDB:RegisterNamespace('MoveIt', defaults)
	MoveIt.DB = MoveIt.Database.profile

	-- Register for sequential profile refresh with ApplyAllMoverPositions
	SUI.DBM:RegisterSequentialProfileRefresh(MoveIt, 'ApplyAllMoverPositions')
	MoveIt.DBG = MoveIt.Database.global -- Global scope for account-wide settings

	-- Migrate old settings
	if SUI.DB.MoveIt then
		print('MoveIt DB Migration')
		MoveIt.DB = SUI:MergeData(MoveIt.DB, SUI.DB.MoveIt, true)
		SUI.DB.MoveIt = nil
	end

	--Build Options
	MoveIt:Options()

	-- EditMode Enter/Exit callbacks removed - SUI now uses fully custom mover system
	-- No longer integrating with Blizzard's EditMode for positioning
end

function MoveIt:CombatLockdown()
	if MoveEnabled then
		MoveIt:MoveIt()
		print('Disabling movement system while in combat')
	end
end

function MoveIt:OnEnable()
	if SUI:IsModuleDisabled('MoveIt') then
		return
	end

	-- Register logger if LibAT is available
	local LibAT = _G.LibAT
	if LibAT and LibAT.Logger then
		MoveIt.logger = SUI.logger:RegisterCategory('MoveIt')
		MoveIt.logger.info('MoveIt system initialized')

		-- Run migration handler (one-time cleanup)
		if MoveIt.Migration then
			MoveIt.Migration:Initialize()
		end

		-- Initialize EditMode profile sync (optional feature)
		if MoveIt.EditModeProfileSync then
			MoveIt.EditModeProfileSync:Initialize()
		end
	end

	-- Register for SUI profile change callbacks to sync EditMode profiles (optional feature)
	SUI.SpartanUIDB.RegisterCallback(MoveIt, 'OnProfileChanged', 'HandleProfileChange')
	SUI.SpartanUIDB.RegisterCallback(MoveIt, 'OnProfileCopied', 'HandleProfileChange')
	SUI.SpartanUIDB.RegisterCallback(MoveIt, 'OnProfileReset', 'HandleProfileChange')

	local ChatCommand = function(arg)
		if InCombatLockdown() then
			print(ERR_NOT_IN_COMBAT)
			return
		end

		if not arg then
			-- Toggle move mode (enter if inactive, exit if active)
			if MoveIt.MoverMode and MoveIt.MoverMode:IsActive() then
				MoveIt.MoverMode:Exit()
			else
				MoveIt:EnterMoveMode()
			end
		else
			if self.MoverList[arg] then
				MoveIt:MoveIt(arg)
			elseif arg == 'reset' then
				print('Restting all frames...')
				MoveIt:Reset()
				return
			elseif arg == 'tips' then
				MoveIt.DB.tips = not MoveIt.DB.tips
				local mode = '|cffed2024off'
				if MoveIt.DB.tips then
					mode = '|cff69bd45on'
				end

				print('Tips turned ' .. mode)
			elseif arg == 'test' then
				-- Test command: show closest anchor for frame under cursor
				local frame = GetMouseFocus()
				if frame and frame.anchoredFrame then
					local anchor = MoveIt.PositionCalculator:GetClosestAnchor(frame)
					local x, y = MoveIt.PositionCalculator:CalculateAnchorOffset(frame, anchor)
					print(('Closest anchor: %s (offset: %.1f, %.1f)'):format(anchor, x, y))
				else
					print('No mover frame under cursor. Hover over a mover frame and try again.')
				end
			else
				print('Invalid move command!')
				return
			end
		end
	end
	SUI:AddChatCommand('move', ChatCommand, "|cffffffffSpartan|cffe21f1fUI|r's movement system", {
		reset = 'Reset all moved objects',
		tips = 'Disable tips from being displayed in chat when movement system is activated',
		test = 'Show closest anchor for frame under cursor (debug)',
	}, true)

	-- Register custom EditMode slash command
	SUI:AddChatCommand('edit', function()
		if MoveIt.MoverMode then
			MoveIt.MoverMode:Toggle()
		end
	end, 'Toggle custom EditMode', nil, true)

	local function OnKeyDown(self, key)
		-- Check both legacy MoveEnabled flag and new MoverMode:IsActive()
		local isMoveActive = MoveEnabled or (MoveIt.MoverMode and MoveIt.MoverMode:IsActive())
		if isMoveActive and key == 'ESCAPE' then
			if InCombatLockdown() then
				self:SetPropagateKeyboardInput(true)
				return
			end
			self:SetPropagateKeyboardInput(false)
			MoveIt:LockAll()
		else
			self:SetPropagateKeyboardInput(true)
		end
	end

	MoverWatcher:Hide()
	MoverWatcher:SetFrameStrata('TOOLTIP')
	MoverWatcher:SetScript('OnKeyDown', OnKeyDown)

	self:RegisterEvent('PLAYER_REGEN_DISABLED', 'CombatLockdown')
end

---Handle SUI profile changes to sync EditMode profiles
---@param event string The callback event name
---@param database table The AceDB database object
---@param newProfile? string The new profile name (may be nil for some events)
function MoveIt:HandleProfileChange(event, database, newProfile)
	-- Update our DB reference since profile changed
	MoveIt.DB = MoveIt.Database.profile

	-- Delegate to EditModeProfileSync for optional profile sync
	if MoveIt.EditModeProfileSync and MoveIt.DB and MoveIt.DB.SyncEditModeProfile then
		-- Get the actual new profile name if not provided
		local profileName = newProfile or SUI.SpartanUIDB:GetCurrentProfile()
		MoveIt.EditModeProfileSync:OnSUIProfileChanged(event, database, profileName)
	end
end

-- Expose MoverWatcher controls for MoverMode
function MoveIt:ShowMoverWatcher()
	MoverWatcher:Show()
	MoverWatcher:EnableKeyboard(true)
end

function MoveIt:HideMoverWatcher()
	MoverWatcher:Hide()
end

-- Expose shared state for other MoveIt files
MoveIt.MoverWatcher = MoverWatcher
MoveIt.MoveEnabled = MoveEnabled

---Helper function to save a mover's position
---@param name string The mover name
function MoveIt:SaveMoverPosition(name)
	local mover = self.MoverList[name]
	if not mover or not self.PositionCalculator then
		return
	end

	local position = self.PositionCalculator:GetRelativePosition(mover)
	if position then
		self.PositionCalculator:SavePosition(name, position)
	end
end

---Re-apply all mover positions from the new profile
function MoveIt:ApplyAllMoverPositions()
	-- Skip if in combat
	if InCombatLockdown() then
		if MoveIt.logger then
			MoveIt.logger.warning('Profile swap during combat - mover positions will not update until after combat')
		end
		return
	end

	-- Re-apply each stored mover position
	local applied = 0
	for moverName, data in pairs(MoveIt.DB.movers or {}) do
		if data.MovedPoints then
			local mover = _G['SUI_Mover_' .. moverName]
			if mover then
				local point, anchor, secondaryPoint, x, y = strsplit(',', data.MovedPoints)
				mover:ClearAllPoints()
				mover:SetPoint(point, anchor, secondaryPoint, tonumber(x), tonumber(y))

				-- Apply custom scale if set
				if data.AdjustedScale then
					mover:SetScale(data.AdjustedScale)
					if mover.parent then
						mover.parent:SetScale(data.AdjustedScale)
					end
				end
				applied = applied + 1
			end
		end
	end

	if MoveIt.logger then
		MoveIt.logger.info(string.format('Applied %d mover positions from new profile', applied))
	end
end
