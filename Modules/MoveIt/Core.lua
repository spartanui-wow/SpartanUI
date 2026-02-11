local SUI, L, print = SUI, SUI.L, SUI.print
---@class MoveIt : AceAddon, AceHook-3.0, AceEvent-3.0, AceTimer-3.0
local MoveIt = SUI:NewModule('MoveIt', 'AceHook-3.0') ---@type SUI.Module
MoveIt.description = 'CORE: Is the movement system for SpartanUI'
MoveIt.Core = true
SUI.MoveIt = MoveIt

-- Shared state (accessed by other MoveIt files via MoveIt.MoverList, etc.)
MoveIt.MoverList = {}

--- Check if EditModeManagerFrame is actually functional (not just defined)
--- TBC 2.5.5+ has it, but it's not fully functional (missing fonts, etc.)
--- Only Retail has a complete EditMode implementation
---@return boolean
local function IsEditModeAvailable()
	-- EditMode is only fully functional on Retail
	-- TBC 2.5.5+ has EditModeManagerFrame but it's incomplete and causes errors
	if not SUI.IsRetail then
		return false
	end

	-- Check if the frame exists
	if not EditModeManagerFrame then
		return false
	end

	-- Log what we find for diagnostics
	local log = function(msg)
		if MoveIt.logger then
			MoveIt.logger.debug(msg)
		end
	end

	log('EditModeManagerFrame exists, checking capabilities...')

	-- Check for EnterEditMode (indicates functional EditMode)
	if type(EditModeManagerFrame.EnterEditMode) ~= 'function' then
		log('  FAIL: Missing EnterEditMode method')
		return false
	end

	-- Check for ExitEditMode
	if type(EditModeManagerFrame.ExitEditMode) ~= 'function' then
		log('  FAIL: Missing ExitEditMode method')
		return false
	end

	log('  SUCCESS: EditMode is functional')
	return true
end

-- Cache the result after first check (evaluated after PLAYER_LOGIN)
local editModeAvailable = nil

--- Get cached EditMode availability (with lazy initialization)
---@return boolean
local function HasEditMode()
	if editModeAvailable == nil then
		editModeAvailable = IsEditModeAvailable()
		if MoveIt.logger then
			MoveIt.logger.info('EditMode availability check: ' .. tostring(editModeAvailable))
		end
	end
	return editModeAvailable
end

-- Expose for other modules (ChatCommands, Options, etc.)
MoveIt.HasEditMode = HasEditMode

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

	-- Skip if automatic position update is in progress (new unified flag)
	if MoveIt.BlizzardEditMode and MoveIt.BlizzardEditMode.isApplyingAutomaticUpdate then
		if MoveIt.logger then
			MoveIt.logger.debug('UnlockAll: Suppressed during automatic position update')
		end
		return
	end

	-- Legacy flag check (can be removed after testing)
	if MoveIt.BlizzardEditMode and MoveIt.BlizzardEditMode.applyingProfileChange then
		if MoveIt.logger then
			MoveIt.logger.debug('UnlockAll: Suppressed during profile change (legacy flag)')
		end
		return
	end

	-- Check if EditMode is still active (prevents race condition with quick exit)
	if EditModeManagerFrame and not EditModeManagerFrame:IsEditModeActive() then
		if MoveIt.logger then
			MoveIt.logger.debug('UnlockAll: Cancelled - EditMode already exited, ensuring movers are locked')
		end
		-- Defensive cleanup: ensure movers are hidden since EditMode exited
		C_Timer.After(0.1, function()
			if not (EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive()) then
				if MoveIt.logger then
					MoveIt.logger.debug('UnlockAll: Race condition cleanup - locking movers')
				end
				self:LockAll()
			end
		end)
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

		-- Check if EditMode exited while we're showing movers (race condition protection)
		if EditModeManagerFrame and not EditModeManagerFrame:IsEditModeActive() then
			if MoveIt.logger then
				MoveIt.logger.debug(('UnlockAll: EditMode exited during unlock after showing %d movers - aborting and locking'):format(shownCount))
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

	-- If Retail has EditMode, use it
	if HasEditMode() then
		ShowUIPanel(EditModeManagerFrame)
		-- EditMode.Enter event will fire and unlock movers (user mode)
		if MoveIt.logger then
			MoveIt.logger.debug('EnterMoveMode: Opening EditMode UI for user')
		end
	else
		-- Classic: use legacy mover system
		if MoveIt.logger then
			MoveIt.logger.debug('EnterMoveMode: Using legacy mover system (Classic)')
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
			movers = {
				['**'] = {
					defaultPoint = false,
					MovedPoints = false,
				},
			},
			-- EditMode wizard tracking
			EditModeWizard = {
				SetupDone = false, -- Wizard/setup completed for this character?
				MigratedFromProfile = nil, -- Profile name we migrated from (if upgrade)
				MigrationOption = nil, -- 'apply_current' | 'copy_new'
			},
			-- EditMode management control
			EditModeControl = {
				Enabled = true, -- Allow MoveIt to manage EditMode profiles
				AutoSwitch = true, -- Auto-switch EditMode when SUI profile changes
				CurrentProfile = nil, -- Currently managed EditMode profile name
			},
		},
		global = {
			-- Account-wide EditMode preferences for multi-character sync
			EditModePreferences = {
				ApplyToAllCharacters = false, -- Auto-apply choices on other characters
				DefaultMigrationOption = nil, -- 'apply_current' | 'copy_new'
			},
			-- Per-character EditMode setup tracking (keyed by "CharName - Realm")
			-- Stored globally because EditMode profiles are per-character in WoW,
			-- independent of shared SUI profiles
			EditModeSetupCharacters = {},
		},
	}
	---@type MoveItDB
	MoveIt.Database = SUI.SpartanUIDB:RegisterNamespace('MoveIt', defaults)
	MoveIt.DB = MoveIt.Database.profile
	MoveIt.DBG = MoveIt.Database.global -- Global scope for account-wide settings

	-- Migrate old settings
	if SUI.DB.MoveIt then
		print('MoveIt DB Migration')
		MoveIt.DB = SUI:MergeData(MoveIt.DB, SUI.DB.MoveIt, true)
		SUI.DB.MoveIt = nil
	end

	--Build Options
	MoveIt:Options()

	-- Only register EditMode callbacks if EditMode is actually functional
	-- Note: HasEditMode() may not be accurate yet (logger not ready), so check basics here
	if EditModeManagerFrame and type(EditModeManagerFrame.EnterEditMode) == 'function' and EventRegistry then
		EventRegistry:RegisterCallback('EditMode.Enter', function()
			-- Check if we're in an automatic update context (system applying positions silently)
			if MoveIt.BlizzardEditMode and MoveIt.BlizzardEditMode.isApplyingAutomaticUpdate then
				if MoveIt.logger then
					MoveIt.logger.debug('EditMode.Enter: Suppressed during automatic position update')
				end
				return -- Don't unlock movers during automatic updates
			end

			-- Check if wizard is running
			local isMigrating = MoveIt.WizardPage and MoveIt.WizardPage:IsMigrationInProgress()
			if isMigrating then
				if MoveIt.logger then
					MoveIt.logger.debug('EditMode.Enter: Suppressed during wizard migration')
				end
				return
			end

			-- User explicitly entered EditMode - unlock movers for manual adjustment
			local isActive = EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive()
			if isActive then
				if MoveIt.logger then
					MoveIt.logger.debug('EditMode.Enter: User mode detected, unlocking movers')
				end
				self:UnlockAll()
			end
		end)
		EventRegistry:RegisterCallback('EditMode.Exit', function()
			if MoveIt.logger then
				MoveIt.logger.debug('EditMode.Exit callback fired - locking movers IMMEDIATELY')
			end
			-- Lock movers IMMEDIATELY when EditMode exits, no delay
			-- This catches the race condition where UnlockAll() is still running
			self:LockAll()

			-- Additional safety check after a short delay
			C_Timer.After(0.1, function()
				if not EditModeManagerFrame:IsEditModeActive() and MoveEnabled then
					if MoveIt.logger then
						MoveIt.logger.debug('EditMode.Exit: Double-checking movers are locked')
					end
					self:LockAll()
				end
			end)
		end)
	end
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

		-- Log EditModeManagerFrame diagnostics
		MoveIt.logger.info('=== EditMode Diagnostics ===')
		MoveIt.logger.info('Game Version: ' .. (SUI.wowVersion or 'Unknown'))
		MoveIt.logger.info('IsRetail: ' .. tostring(SUI.IsRetail))
		MoveIt.logger.info('IsTBC: ' .. tostring(SUI.IsTBC))
		MoveIt.logger.info('EditModeManagerFrame exists: ' .. tostring(EditModeManagerFrame ~= nil))
		if EditModeManagerFrame then
			MoveIt.logger.info('  Type: ' .. type(EditModeManagerFrame))
			MoveIt.logger.info('  IsShown: ' .. tostring(type(EditModeManagerFrame.IsShown)))
			MoveIt.logger.info('  EnterEditMode: ' .. tostring(type(EditModeManagerFrame.EnterEditMode)))
			MoveIt.logger.info('  ExitEditMode: ' .. tostring(type(EditModeManagerFrame.ExitEditMode)))
			MoveIt.logger.info('  Show: ' .. tostring(type(EditModeManagerFrame.Show)))
			MoveIt.logger.info('  Hide: ' .. tostring(type(EditModeManagerFrame.Hide)))
			MoveIt.logger.info('  GetAttribute: ' .. tostring(type(EditModeManagerFrame.GetAttribute)))
		end
		MoveIt.logger.info('HasEditMode() result: ' .. tostring(HasEditMode()))

		-- Log font availability for debugging Classic font issues
		local testFonts = { 'GameFontDisableMed2', 'GameFontHighlightMed2', 'GameFontNormalMed2', 'GameFontDisable', 'GameFontNormal' }
		MoveIt.logger.info('=== Font Availability ===')
		for _, fontName in ipairs(testFonts) do
			local fontObj = _G[fontName]
			MoveIt.logger.info(('  %s: %s'):format(fontName, fontObj and 'EXISTS' or 'MISSING'))
		end
		MoveIt.logger.info('=== End EditMode Diagnostics ===')
	end

	-- Initialize Blizzard EditMode integration
	if MoveIt.BlizzardEditMode then
		MoveIt.BlizzardEditMode:Initialize()
	end

	-- Register for SUI profile change callbacks to sync EditMode profiles
	SUI.SpartanUIDB.RegisterCallback(MoveIt, 'OnProfileChanged', 'HandleProfileChange')
	SUI.SpartanUIDB.RegisterCallback(MoveIt, 'OnProfileCopied', 'HandleProfileChange')
	SUI.SpartanUIDB.RegisterCallback(MoveIt, 'OnProfileReset', 'HandleProfileChange')

	-- Register the EditMode wizard page now that DB is available
	if MoveIt.WizardPage and SUI.Setup then
		MoveIt.WizardPage:RegisterPage()
	end

	local ChatCommand = function(arg)
		if InCombatLockdown() then
			print(ERR_NOT_IN_COMBAT)
			return
		end

		if not arg then
			-- Enter user move mode (explicit user action to reposition frames)
			MoveIt:EnterMoveMode()
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
			else
				print('Invalid move command!')
				return
			end
		end
	end
	SUI:AddChatCommand('move', ChatCommand, "|cffffffffSpartan|cffe21f1fUI|r's movement system", {
		reset = 'Reset all moved objects',
		tips = 'Disable tips from being displayed in chat when movement system is activated',
	}, true)

	-- Register custom EditMode slash command
	SUI:AddChatCommand('edit', function()
		if MoveIt.CustomEditMode then
			MoveIt.CustomEditMode:Toggle()
		end
	end, 'Toggle custom EditMode', nil, true)

	local function OnKeyDown(self, key)
		if MoveEnabled and key == 'ESCAPE' then
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

	-- Delegate to BlizzardEditMode for EditMode profile sync
	if MoveIt.BlizzardEditMode and EditModeManagerFrame then
		-- Get the actual new profile name if not provided
		local profileName = newProfile or SUI.SpartanUIDB:GetCurrentProfile()
		MoveIt.BlizzardEditMode:OnSUIProfileChanged(event, database, profileName)
	end
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
