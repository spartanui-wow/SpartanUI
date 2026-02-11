---@class SUI
local SUI = SUI
---@class MoveIt
local MoveIt = SUI.MoveIt

---@class SUI.MoveIt.BlizzardEditMode
local BlizzardEditMode = {}
MoveIt.BlizzardEditMode = BlizzardEditMode

-- Frames that have native EditMode support (from https://warcraft.wiki.gg/wiki/Edit_Mode)
-- We'll use LibEditModeOverride to add our settings to them
local NATIVE_EDITMODE_FRAMES = {
	-- Action Bars
	ActionBar = { systemID = 1 }, -- Enum.EditModeSystem.ActionBar
	-- Unit Frames (we replace these with oUF, but need to hook checkboxes)
	CastBar = { systemID = 2 },
	PlayerFrame = { systemID = 3 },
	TargetFrame = { systemID = 4 },
	FocusFrame = { systemID = 5 },
	PartyFrame = { systemID = 6 },
	RaidFrame = { systemID = 7 },
	BossFrame = { systemID = 8 },
	ArenaFrame = { systemID = 9 },
	-- UI Elements
	EncounterBar = { systemID = 10 },
	ExtraAbilities = { systemID = 11 }, -- ExtraActionButton, ZoneAbility
	AuraFrame = { systemID = 12 },
	TalkingHeadFrame = { systemID = 13 },
	VehicleLeaveButton = { systemID = 14 },
	HudTooltip = { systemID = 15 },
	ObjectiveTracker = { systemID = 16 },
	MicroMenu = { systemID = 17 },
	Bags = { systemID = 18 },
	StatusTrackingBar = { systemID = 19 }, -- XP/Rep/Honor bars
	Minimap = { systemID = 20 },
	-- Containers
	ArchaeologyBar = { systemID = 21 },
	QuestTimerFrame = { systemID = 22 },
	-- Note: Some frames were added in different patches
}

-- Frames that DON'T have EditMode support
-- These need custom movers
local NON_EDITMODE_FRAMES = {
	FramerateFrame = true,
	AlertFrame = true, -- GroupLootContainer and AlertFrame holder
	TopCenterContainer = true, -- UIWidgetTopCenterContainerFrame
	WidgetPowerBarContainer = true, -- UIWidgetPowerBarContainerFrame
	VehicleSeatIndicator = true, -- Has EditMode but not well supported
}

---Initialize Blizzard EditMode integration
function BlizzardEditMode:Initialize()
	-- Check if we're on Retail (EditMode only exists in Retail)
	if not EditModeManagerFrame then
		if MoveIt.logger then
			MoveIt.logger.info('EditMode not available (Classic/TBC/Wrath) - using custom movers for all Blizzard frames')
		end
		return
	end

	-- Check if LibEditModeOverride is available
	local LibEMO = LibStub and LibStub('LibEditModeOverride-1.0', true)
	if not LibEMO then
		if MoveIt.logger then
			MoveIt.logger.warning('LibEditModeOverride not found - falling back to custom movers for Blizzard frames')
		end
		return
	end

	if MoveIt.logger then
		MoveIt.logger.info('Initializing Blizzard EditMode integration with LibEditModeOverride')
	end

	-- Wait for EditMode to be ready
	if LibEMO:IsReady() then
		self:SetupBlizzardFrames(LibEMO)
		self:StartLayoutMonitoring()
		self:RegisterEditModeExitHandler()
	else
		-- Hook into ready event
		local frame = CreateFrame('Frame')
		frame:RegisterEvent('EDIT_MODE_LAYOUTS_UPDATED')
		frame:SetScript('OnEvent', function(self, event)
			if LibEMO:IsReady() then
				BlizzardEditMode:SetupBlizzardFrames(LibEMO)
				BlizzardEditMode:StartLayoutMonitoring()
				BlizzardEditMode:RegisterEditModeExitHandler()
				self:UnregisterAllEvents()
			end
		end)
	end

	-- Register combat-end handler to process deferred EditMode changes
	if not self.combatFrame then
		self.combatFrame = CreateFrame('Frame')
		self.combatFrame:RegisterEvent('PLAYER_REGEN_ENABLED')
		self.combatFrame:SetScript('OnEvent', function()
			BlizzardEditMode:PLAYER_REGEN_ENABLED()
		end)
	end
end

---Create or ensure the SpartanUI EditMode profile exists
---@param LibEMO table LibEditModeOverride instance
---@return boolean success True if profile is ready
function BlizzardEditMode:CreateSpartanUIProfile(LibEMO)
	local profileName = 'SpartanUI'

	-- Check if profile already exists
	if LibEMO:DoesLayoutExist(profileName) then
		if MoveIt.logger then
			MoveIt.logger.debug(('EditMode profile "%s" already exists'):format(profileName))
		end
		return true
	end

	-- Create character-level profile
	if MoveIt.logger then
		MoveIt.logger.info(('Creating EditMode profile "%s"'):format(profileName))
	end

	local success = pcall(function()
		LibEMO:AddLayout(Enum.EditModeLayoutType.Character, profileName)
		LibEMO:SetActiveLayout(profileName)
	end)

	if success then
		self:SafeApplyChanges()
	end

	if success then
		if MoveIt.logger then
			MoveIt.logger.info(('Successfully created EditMode profile "%s"'):format(profileName))
		end
		return true
	else
		if MoveIt.logger then
			MoveIt.logger.error(('Failed to create EditMode profile "%s"'):format(profileName))
		end
		return false
	end
end

---Ensure the SpartanUI profile is ready for use
---@param LibEMO table LibEditModeOverride instance
---@return boolean ready True if profile is ready
function BlizzardEditMode:EnsureProfileReady(LibEMO)
	if not LibEMO then
		return false
	end

	-- Check if EditMode is ready
	if not LibEMO:IsReady() then
		if MoveIt.logger then
			MoveIt.logger.warning('EnsureProfileReady: EditMode not ready yet')
		end
		return false
	end

	-- Load layouts first (required before any other LibEMO calls)
	if not LibEMO:AreLayoutsLoaded() then
		LibEMO:LoadLayouts()
	end

	-- Check current active layout
	local currentLayout = LibEMO:GetActiveLayout()
	local expectedProfile = self:GetMatchingProfileName()

	-- If user is already on the expected profile, we're good
	if currentLayout and currentLayout == expectedProfile then
		if MoveIt.logger then
			MoveIt.logger.debug(('EnsureProfileReady: Already on expected profile "%s"'):format(expectedProfile))
		end
		return true
	end

	-- If user is on an unrelated profile and we have no record of managing them, don't switch
	if
		currentLayout
		and currentLayout ~= expectedProfile
		and not self:IsSpartanUILayout(currentLayout)
		and not (MoveIt.DB and MoveIt.DB.EditModeControl and MoveIt.DB.EditModeControl.CurrentProfile)
	then
		if MoveIt.logger then
			MoveIt.logger.warning(('EnsureProfileReady: User is on "%s" profile with no managed profile record - not switching'):format(currentLayout))
		end
		return false
	end

	-- Create profile if it doesn't exist
	if not LibEMO:DoesLayoutExist(expectedProfile) then
		if MoveIt.logger then
			MoveIt.logger.info(('Creating EditMode profile "%s"'):format(expectedProfile))
		end
		local success = pcall(function()
			LibEMO:AddLayout(Enum.EditModeLayoutType.Character, expectedProfile)
		end)
		if not success then
			if MoveIt.logger then
				MoveIt.logger.error(('Failed to create EditMode profile "%s"'):format(expectedProfile))
			end
			return false
		end
	end

	-- Set as active if not already
	if not currentLayout or currentLayout ~= expectedProfile then
		if MoveIt.logger then
			MoveIt.logger.info(('Activating EditMode profile "%s" (was: %s)'):format(expectedProfile, tostring(currentLayout)))
		end
		local success = pcall(function()
			LibEMO:SetActiveLayout(expectedProfile)
		end)
		if success then
			self:SafeApplyChanges(true) -- Suppress movers during activation
		end
		if not success then
			if MoveIt.logger then
				MoveIt.logger.error(('Failed to activate EditMode profile "%s"'):format(expectedProfile))
			end
			return false
		end
	end

	return true
end

---Setup Blizzard frames with EditMode integration
---@param LibEMO table LibEditModeOverride instance
function BlizzardEditMode:SetupBlizzardFrames(LibEMO)
	LibEMO:LoadLayouts()

	-- Store LibEMO reference for later use
	self.LibEMO = LibEMO

	-- Hook default positions
	self:HookDefaultPositions()

	-- Hook the reset button to ensure it works with our custom positions
	self:HookResetButton()
end

function BlizzardEditMode:StartLayoutMonitoring()
	if not EditModeManagerFrame then
		return
	end

	-- Create monitoring frame if it doesn't exist
	if not self.layoutMonitorFrame then
		self.layoutMonitorFrame = CreateFrame('Frame')
	end

	-- Register for layout updates
	self.layoutMonitorFrame:RegisterEvent('EDIT_MODE_LAYOUTS_UPDATED')
	self.layoutMonitorFrame:SetScript('OnEvent', function(frame, event)
		BlizzardEditMode:OnLayoutChanged()
	end)

	-- Hook EditModePresetLayoutManager to override what Blizzard considers "default" positions
	self:HookDefaultPositions()
end

---Hook EditModePresetLayoutManager to override default positions
function BlizzardEditMode:HookDefaultPositions()
	if self.defaultPositionsHooked then
		return
	end

	-- Hook EditModePresetLayoutManager:GetDefaultSystemAnchorInfo to return SpartanUI positions
	if not (EditModePresetLayoutManager and EditModePresetLayoutManager.GetDefaultSystemAnchorInfo) then
		if MoveIt.logger then
			MoveIt.logger.warning('EditModePresetLayoutManager not found - cannot override default positions')
		end
		return
	end

	-- Store original function
	local originalGetDefaultSystemAnchorInfo = EditModePresetLayoutManager.GetDefaultSystemAnchorInfo

	-- Override GetDefaultSystemAnchorInfo to return SpartanUI positions when appropriate
	EditModePresetLayoutManager.GetDefaultSystemAnchorInfo = function(self, systemIndex)
		-- During combat, always use original to avoid tainting protected calls
		if InCombatLockdown() then
			return originalGetDefaultSystemAnchorInfo(self, systemIndex)
		end

		-- Get the original default first
		local originalInfo = originalGetDefaultSystemAnchorInfo(self, systemIndex)

		-- Check if we have a SpartanUI position for this system
		for frameName, frameInfo in pairs(NATIVE_EDITMODE_FRAMES) do
			if frameInfo.systemID == systemIndex then
				-- Check if we have a saved position in SpartanUI DB
				local styleDB = SUI.DB and SUI.DB.Styles and SUI.DB.Styles[SUI.DB.Artwork.Style]
				if styleDB and styleDB.BlizzMovers and styleDB.BlizzMovers[frameName] then
					local posString = styleDB.BlizzMovers[frameName]
					local point, anchor, relativePoint, x, y = BlizzardEditMode:ParseSUIPosition(posString)

					if point and x and y then
						-- Return our custom position instead of Blizzard's default
						local customInfo = {
							point = point,
							relativeTo = anchor or 'UIParent',
							relativePoint = relativePoint or point,
							offsetX = tonumber(x) or 0,
							offsetY = tonumber(y) or 0,
						}

						if MoveIt.logger then
							MoveIt.logger.debug(('Overriding default position for %s (system %d): %s'):format(frameName, systemIndex, posString))
						end

						return customInfo
					end
				end
			end
		end

		-- No override found, return original
		return originalInfo
	end

	self.defaultPositionsHooked = true

	if MoveIt.logger then
		MoveIt.logger.info('Hooked EditModePresetLayoutManager:GetDefaultSystemAnchorInfo to return SpartanUI positions')
	end
end

---Hook the Reset button to ensure it works with our custom positions
function BlizzardEditMode:HookResetButton()
	if self.resetButtonHooked then
		return
	end

	-- Find the reset button in EditMode UI
	if not (EditModeManagerFrame and EditModeManagerFrame.ResetButton) then
		if MoveIt.logger then
			MoveIt.logger.warning('EditMode ResetButton not found - cannot hook reset functionality')
		end
		return
	end

	-- Store original OnClick handler
	local resetButton = EditModeManagerFrame.ResetButton
	if not resetButton then
		return
	end

	-- Hook the OnClick script
	resetButton:HookScript('OnClick', function(self)
		-- Notify SpartanUI that positions were reset
		if MoveIt.logger then
			MoveIt.logger.info('EditMode reset button clicked - reapplying SpartanUI positions')
		end

		-- Delayed reapplication to let EditMode finish its reset first
		C_Timer.After(0.1, function()
			BlizzardEditMode:ApplyAllBlizzMoverPositions()
		end)
	end)

	self.resetButtonHooked = true

	if MoveIt.logger then
		MoveIt.logger.info('Hooked EditMode ResetButton to reapply SpartanUI positions after reset')
	end
end

---Get the frame name for a given EditMode system ID
---@param systemID number The EditMode system ID
---@return string|nil frameName The frame name if found
function BlizzardEditMode:GetFrameNameBySystemID(systemID)
	for frameName, frameInfo in pairs(NATIVE_EDITMODE_FRAMES) do
		if frameInfo.systemID == systemID then
			return frameName
		end
	end
	return nil
end

---Reapply a single frame's position from the database
---@param frameName string The name of the frame
---@param frame table The frame object
---@param skipApply boolean If true, don't actually apply the position (just prep)
function BlizzardEditMode:ReapplyFramePosition(frameName, frame, skipApply)
	if not frame or not frameName then
		return
	end

	-- Get position from DB
	local styleDB = SUI.DB and SUI.DB.Styles and SUI.DB.Styles[SUI.DB.Artwork.Style]
	if not (styleDB and styleDB.BlizzMovers and styleDB.BlizzMovers[frameName]) then
		return
	end

	local posString = styleDB.BlizzMovers[frameName]
	if not posString or posString == '' then
		return
	end

	-- Parse position
	local point, anchor, relativePoint, x, y = self:ParseSUIPosition(posString)
	if not (point and x and y) then
		if MoveIt.logger then
			MoveIt.logger.warning(('Failed to parse position for %s: %s'):format(frameName, posString))
		end
		return
	end

	if skipApply then
		return
	end

	-- Apply position using EditMode API if this frame has native support
	local frameInfo = NATIVE_EDITMODE_FRAMES[frameName]
	if frameInfo and EditModeManagerFrame and self.LibEMO then
		local LibEMO = self.LibEMO

		-- Check if we're in Edit Mode
		if EditModeManagerFrame:IsEditModeActive() then
			-- Use LibEditModeOverride to apply position
			local success = pcall(function()
				LibEMO:SetSystemPosition(frameInfo.systemID, {
					point = point,
					relativeTo = anchor or 'UIParent',
					relativePoint = relativePoint or point,
					offsetX = tonumber(x) or 0,
					offsetY = tonumber(y) or 0,
				})
			end)

			if success and MoveIt.logger then
				MoveIt.logger.debug(('Applied EditMode position for %s: %s'):format(frameName, posString))
			elseif not success and MoveIt.logger then
				MoveIt.logger.warning(('Failed to apply EditMode position for %s'):format(frameName))
			end
		end
	end
end

---Called when EditMode layout changes
function BlizzardEditMode:OnLayoutChanged()
	-- Get the new layout name
	if not self.LibEMO then
		return
	end

	local currentLayout = self.LibEMO:GetActiveLayout()

	if MoveIt.logger then
		MoveIt.logger.debug(('EditMode layout changed to: %s'):format(tostring(currentLayout)))
	end

	-- If switching to a different layout, show a warning popup
	if currentLayout and currentLayout ~= 'SpartanUI' and currentLayout ~= '' then
		-- Check if this is a preset layout (Modern, Classic)
		if self:IsPresetLayout(currentLayout) then
			-- Preset layout - show warning about switching back to SpartanUI
			self:ShowDisableManagementPopup(currentLayout)
		else
			-- Custom user layout - offer to switch manually
			self:ShowManualSwitchPopup()
		end
	end
end

---Show popup warning about switching to a different layout
---@param profileName string The name of the layout the user switched to
function BlizzardEditMode:ShowDisableManagementPopup(profileName)
	StaticPopup_Show('SPARTANUI_EDITMODE_DISABLE', profileName)
end

-- Define the static popup
StaticPopupDialogs['SPARTANUI_EDITMODE_DISABLE'] = {
	text = "You've switched to the '%s' Edit Mode layout.\n\nSpartanUI manages its own layout through the 'SpartanUI' profile. Would you like to switch back?",
	button1 = 'Switch Back',
	button2 = 'Keep New Layout',
	OnAccept = function()
		if BlizzardEditMode.LibEMO then
			BlizzardEditMode.LibEMO:SetActiveLayout('SpartanUI')
			BlizzardEditMode:SafeApplyChanges()
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

---Show popup about manual switch needed
function BlizzardEditMode:ShowManualSwitchPopup()
	-- Store flag to show popup after exiting Edit Mode
	self.pendingManualSwitchPrompt = true
end

-- Define the manual switch popup
StaticPopupDialogs['SPARTANUI_EDITMODE_MANUAL_SWITCH'] = {
	text = "You're using a custom Edit Mode layout.\n\nSpartanUI manages frame positions through its own 'SpartanUI' profile. Switch back to use SpartanUI's positioning?",
	button1 = 'Switch to SpartanUI',
	button2 = 'Keep Custom Layout',
	OnAccept = function()
		if BlizzardEditMode.LibEMO then
			BlizzardEditMode.LibEMO:SetActiveLayout('SpartanUI')
			BlizzardEditMode:SafeApplyChanges()
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function BlizzardEditMode:RegisterEditModeExitHandler()
	if self.editModeExitRegistered then
		return
	end

	if EditModeManagerFrame then
		EventRegistry:RegisterCallback('EditMode.Exit', function()
			-- Check if we need to show the manual switch popup
			if self.pendingManualSwitchPrompt then
				-- Delay slightly to let EditMode fully exit
				C_Timer.After(0.5, function()
					StaticPopup_Show('SPARTANUI_EDITMODE_MANUAL_SWITCH')
					self.pendingManualSwitchPrompt = nil
				end)
			end
		end)
		self.editModeExitRegistered = true
	end
end

---Check if a frame should use native EditMode
---@param frameName string The frame name
---@return boolean useNative True if frame has native EditMode support
function BlizzardEditMode:ShouldUseNativeEditMode(frameName)
	if not EditModeManagerFrame then
		return false -- EditMode not available
	end

	return NATIVE_EDITMODE_FRAMES[frameName] ~= nil
end

---Parse SpartanUI position CSV string into components
---@param csvString string Position in format 'POINT,AnchorFrame,RelativePoint,X,Y'
---@return string|nil point
---@return string|nil anchor
---@return string|nil relativePoint
---@return number|nil x
---@return number|nil y
function BlizzardEditMode:ParseSUIPosition(csvString)
	if not csvString or csvString == '' then
		return nil, nil, nil, nil, nil
	end

	local parts = { strsplit(',', csvString) }
	if #parts < 5 then
		return nil, nil, nil, nil, nil
	end

	local point = parts[1]
	local anchor = parts[2]
	local relativePoint = parts[3]
	local x = tonumber(parts[4])
	local y = tonumber(parts[5])

	return point, anchor, relativePoint, x, y
end

---Check if a frame's position has been customized by the user
---@param frame table The frame to check
---@return boolean customized True if the frame has been moved from default
function BlizzardEditMode:IsFramePositionCustomized(frame)
	if not frame then
		return false
	end

	local frameName = frame:GetName()
	if not frameName then
		return false
	end

	-- Check if we have a saved position
	local styleDB = SUI.DB and SUI.DB.Styles and SUI.DB.Styles[SUI.DB.Artwork.Style]
	if styleDB and styleDB.BlizzMovers and styleDB.BlizzMovers[frameName] then
		return true
	end

	return false
end

---Set a frame's position from the database
---@param frameName string The name of the frame
---@param frame table The frame object
function BlizzardEditMode:SetFramePositionFromDB(frameName, frame)
	if not frame or not frameName then
		return
	end

	-- Get position from DB
	local styleDB = SUI.DB and SUI.DB.Styles and SUI.DB.Styles[SUI.DB.Artwork.Style]
	if not (styleDB and styleDB.BlizzMovers and styleDB.BlizzMovers[frameName]) then
		return
	end

	local posString = styleDB.BlizzMovers[frameName]
	if not posString or posString == '' then
		return
	end

	-- Parse position
	local point, anchor, relativePoint, x, y = self:ParseSUIPosition(posString)
	if not (point and x and y) then
		return
	end

	-- Get anchor frame
	local anchorFrame = _G[anchor] or UIParent

	-- Apply position
	frame:ClearAllPoints()
	frame:SetPoint(point, anchorFrame, relativePoint or point, x, y)

	if MoveIt.logger then
		MoveIt.logger.debug(('Applied position to %s from DB: %s'):format(frameName, posString))
	end
end

---Apply all BlizzMover positions from the database
function BlizzardEditMode:ApplyAllBlizzMoverPositions()
	local styleDB = SUI.DB and SUI.DB.Styles and SUI.DB.Styles[SUI.DB.Artwork.Style]
	if not (styleDB and styleDB.BlizzMovers) then
		return
	end

	for frameName, posString in pairs(styleDB.BlizzMovers) do
		local frame = _G[frameName]
		if frame then
			self:SetFramePositionFromDB(frameName, frame)
		end
	end

	if MoveIt.logger then
		MoveIt.logger.info('Applied all BlizzMover positions from database')
	end
end

---Apply a frame position (used by Artwork/BlizzMovers.lua)
---@param frameName string The name of the frame
---@param frameGlobal string|nil The global name override
---@param loadAddon string|nil Addon to load before applying
---@param onLoadEvent string|nil Event to wait for before applying
function BlizzardEditMode:ApplyFramePosition(frameName, frameGlobal, loadAddon, onLoadEvent)
	-- This function is called by Artwork/BlizzMovers.lua
	-- It handles both EditMode-supported frames and custom movers

	-- Get the frame
	local frame = _G[frameGlobal or frameName]

	-- If addon needs to be loaded, handle that first
	if loadAddon and not C_AddOns.IsAddOnLoaded(loadAddon) then
		self:QueuePendingApplication(frameName, frameGlobal, loadAddon, onLoadEvent)
		return
	end

	-- If we need to wait for an event, register that
	if onLoadEvent and not frame then
		self:QueuePendingApplication(frameName, frameGlobal, loadAddon, onLoadEvent)
		return
	end

	if not frame then
		return
	end

	-- Check if this frame uses native EditMode
	if self:ShouldUseNativeEditMode(frameName) then
		-- Use EditMode positioning
		self:ReapplyFramePosition(frameName, frame, false)
	else
		-- Use traditional positioning
		self:SetFramePositionFromDB(frameName, frame)
	end
end

---Queue a pending frame position application
---@param frameName string The name of the frame
---@param frameGlobal string|nil The global name override
---@param loadAddon string|nil Addon to load before applying
---@param onLoadEvent string|nil Event to wait for before applying
function BlizzardEditMode:QueuePendingApplication(frameName, frameGlobal, loadAddon, onLoadEvent)
	if not self.pendingApplications then
		self.pendingApplications = {}
	end

	table.insert(self.pendingApplications, {
		frameName = frameName,
		frameGlobal = frameGlobal,
		loadAddon = loadAddon,
		onLoadEvent = onLoadEvent,
	})

	-- Register for the event or addon load
	if onLoadEvent then
		if not self.applicationWatcher then
			self.applicationWatcher = CreateFrame('Frame')
			self.applicationWatcher:SetScript('OnEvent', function(self, event, ...)
				BlizzardEditMode:ProcessPendingApplications(event, ...)
			end)
		end

		self.applicationWatcher:RegisterEvent(onLoadEvent)
	end
end

---Process pending frame position applications
---@param event string|nil The event that triggered this
---@param ... any Event arguments
function BlizzardEditMode:ProcessPendingApplications(event, ...)
	if not self.pendingApplications then
		return
	end

	local processed = {}

	for i, pending in ipairs(self.pendingApplications) do
		local shouldProcess = false

		-- Check if event matches
		if event and pending.onLoadEvent == event then
			shouldProcess = true
		end

		-- Check if addon is now loaded
		if pending.loadAddon and C_AddOns.IsAddOnLoaded(pending.loadAddon) then
			shouldProcess = true
		end

		if shouldProcess then
			self:ApplyFramePosition(pending.frameName, pending.frameGlobal, nil, nil)
			table.insert(processed, i)
		end
	end

	-- Remove processed items
	for i = #processed, 1, -1 do
		table.remove(self.pendingApplications, processed[i])
	end

	-- Unregister events if no more pending
	if #self.pendingApplications == 0 and self.applicationWatcher then
		self.applicationWatcher:UnregisterAllEvents()
	end
end

---Apply TalkingHeadFrame position
function BlizzardEditMode:ApplyTalkingHeadPosition()
	self:ApplyFramePosition('TalkingHeadFrame', 'TalkingHeadFrame')
end

---Apply ExtraAbilities position
function BlizzardEditMode:ApplyExtraAbilitiesPosition()
	self:ApplyFramePosition('ExtraAbilities', 'ExtraActionBarFrame', 'Blizzard_ExtraActionButton', 'UPDATE_EXTRA_ACTIONBAR')
end

---Apply EncounterBar position
function BlizzardEditMode:ApplyEncounterBarPosition()
	self:ApplyFramePosition('EncounterBar', 'EncounterBar')
end

---Apply VehicleLeaveButton position
function BlizzardEditMode:ApplyVehicleLeaveButtonPosition()
	self:ApplyFramePosition('VehicleLeaveButton', 'MainMenuBarVehicleLeaveButton')
end

---Apply ArchaeologyBar position
function BlizzardEditMode:ApplyArchaeologyBarPosition()
	self:ApplyFramePosition('ArchaeologyBar', 'ArcheologyDigsiteProgressBar', 'Blizzard_ArchaeologyUI', 'ARCHAEOLOGY_SURVEY_CAST')
end

---Restore a frame to its Blizzard default position
---@param frameName string The name of the frame to restore
function BlizzardEditMode:RestoreBlizzardDefault(frameName)
	local frameInfo = NATIVE_EDITMODE_FRAMES[frameName]
	if not frameInfo then
		return
	end

	-- Clear from database
	local styleDB = SUI.DB and SUI.DB.Styles and SUI.DB.Styles[SUI.DB.Artwork.Style]
	if styleDB and styleDB.BlizzMovers then
		styleDB.BlizzMovers[frameName] = nil
	end

	-- Use EditMode API to reset if available
	if EditModeManagerFrame and self.LibEMO then
		local LibEMO = self.LibEMO
		pcall(function()
			LibEMO:ResetSystemPosition(frameInfo.systemID)
		end)
	end

	if MoveIt.logger then
		MoveIt.logger.info(('Restored %s to Blizzard default position'):format(frameName))
	end
end

---Safely apply EditMode changes with error handling
---@param suppressMovers boolean If true, don't update movers (used during profile switching)
function BlizzardEditMode:SafeApplyChanges(suppressMovers)
	if not self.LibEMO then
		return
	end

	-- Defer if in combat to avoid tainting protected frames (party frames, player frame, etc.)
	if InCombatLockdown() then
		if MoveIt.logger then
			MoveIt.logger.warning('SafeApplyChanges: In combat, deferring until combat ends')
		end
		self.pendingApplyChanges = self.pendingApplyChanges or {}
		table.insert(self.pendingApplyChanges, { suppressMovers = suppressMovers })
		return
	end

	local success, err = pcall(function()
		self.LibEMO:ApplyChanges()
	end)

	if not success then
		if MoveIt.logger then
			MoveIt.logger.error(('Error applying EditMode changes: %s'):format(tostring(err)))
		end
		return
	end

	-- Hide movers when suppressed (e.g., during profile changes)
	-- Movers should not automatically appear after profile changes
	if suppressMovers and MoveIt and MoveIt.LockAll then
		C_Timer.After(0.1, function()
			MoveIt:LockAll()
		end)
	end
end

---Handle PLAYER_REGEN_ENABLED (leaving combat)
function BlizzardEditMode:PLAYER_REGEN_ENABLED()
	-- Process deferred SafeApplyChanges calls that were blocked by combat
	if self.pendingApplyChanges and #self.pendingApplyChanges > 0 then
		if MoveIt.logger then
			MoveIt.logger.info(('PLAYER_REGEN_ENABLED: Processing %d deferred ApplyChanges calls'):format(#self.pendingApplyChanges))
		end
		local lastEntry = self.pendingApplyChanges[#self.pendingApplyChanges]
		self.pendingApplyChanges = {}
		-- Only need to apply once with the most recent settings
		self:SafeApplyChanges(lastEntry.suppressMovers)
	end

	-- If we have pending frame applications that were blocked by combat, process them now
	if self.pendingApplications and #self.pendingApplications > 0 then
		self:ProcessPendingApplications()
	end
end

---Check if a frame needs a custom mover (not native EditMode)
---@param frameName string The frame name
---@return boolean needsCustom True if frame needs custom mover
function BlizzardEditMode:NeedsCustomMover(frameName)
	-- Check if frame is in the native EditMode list
	if NATIVE_EDITMODE_FRAMES[frameName] then
		return false -- EditMode handles this
	end

	-- Check if frame is explicitly marked as needing custom mover
	if NON_EDITMODE_FRAMES[frameName] then
		return true
	end

	-- Default: if EditMode exists, assume it might handle it
	-- Otherwise, needs custom mover
	return not EditModeManagerFrame
end

---Check if a layout name is a preset (Modern, Classic)
---@param layoutName string The layout name to check
---@return boolean isPreset True if this is a Blizzard preset layout
function BlizzardEditMode:IsPresetLayout(layoutName)
	local presets = { 'Modern', 'Classic' }
	for _, preset in ipairs(presets) do
		if layoutName == preset then
			return true
		end
	end
	return false
end

---Check if a layout name is a SpartanUI-managed layout
---@param layoutName string The layout name to check
---@return boolean isSUI True if this is a SpartanUI-managed layout
function BlizzardEditMode:IsSpartanUILayout(layoutName)
	if layoutName == 'SpartanUI' then
		return true
	end
	-- Check if this is the currently managed profile (e.g., a custom-named profile set during wizard)
	if MoveIt.DB and MoveIt.DB.EditModeControl and MoveIt.DB.EditModeControl.CurrentProfile then
		return layoutName == MoveIt.DB.EditModeControl.CurrentProfile
	end
	return false
end

---Get current EditMode state information
---@return table state EditMode state info
function BlizzardEditMode:GetEditModeState()
	local state = {
		available = EditModeManagerFrame ~= nil,
		active = false,
		currentLayout = nil,
		currentLayoutName = nil,
		isOnPresetLayout = false,
		isOnSpartanUILayout = false,
		libEMOAvailable = self.LibEMO ~= nil,
	}

	if EditModeManagerFrame then
		state.active = EditModeManagerFrame:IsEditModeActive()
	end

	if self.LibEMO then
		state.currentLayout = self.LibEMO:GetActiveLayout()
		state.currentLayoutName = state.currentLayout
		if state.currentLayout then
			state.isOnPresetLayout = self:IsPresetLayout(state.currentLayout)
			state.isOnSpartanUILayout = self:IsSpartanUILayout(state.currentLayout)
		end
	end

	return state
end

---Get list of frame names that have customized positions
---@return table frameNames List of frame names with custom positions
function BlizzardEditMode:GetCustomizedFrameNames()
	local frameNames = {}

	local styleDB = SUI.DB and SUI.DB.Styles and SUI.DB.Styles[SUI.DB.Artwork.Style]
	if not (styleDB and styleDB.BlizzMovers) then
		return frameNames
	end

	for frameName, _ in pairs(styleDB.BlizzMovers) do
		table.insert(frameNames, frameName)
	end

	return frameNames
end

---Get a matching profile name based on current SUI profile
---@return string profileName The EditMode profile name to use
function BlizzardEditMode:GetMatchingProfileName()
	-- Use the stored CurrentProfile if available (set during wizard/migration)
	if MoveIt.DB and MoveIt.DB.EditModeControl and MoveIt.DB.EditModeControl.CurrentProfile then
		return MoveIt.DB.EditModeControl.CurrentProfile
	end
	-- Default fallback for fresh installs
	return 'SpartanUI'
end

---Determine the layout type (Account vs Character)
---@return number layoutType Enum.EditModeLayoutType value
function BlizzardEditMode:DetermineLayoutType()
	-- SpartanUI profiles are character-specific by default
	-- (matching how SUI DB works with per-character profiles)

	-- However, if user has account-wide SUI profiles enabled,
	-- we should create account-wide EditMode layouts
	local useAccountWide = false

	-- Check if SUI DB is set to account-wide mode
	if SUI.DB and SUI.DB.profileKeys then
		-- If using Default profile across all characters, treat as account-wide
		local currentProfile = SUI.DB:GetCurrentProfile()
		if currentProfile == 'Default' then
			useAccountWide = true
		end
	end

	if useAccountWide then
		return Enum.EditModeLayoutType.Account
	else
		return Enum.EditModeLayoutType.Character
	end
end

---Create a new layout from current positions
---@param layoutType number Enum.EditModeLayoutType
---@param newLayoutName string Name for the new layout
---@param sourceLayoutName string|nil Source layout to copy from
---@return boolean success True if layout was created
function BlizzardEditMode:CreateLayoutFromCurrent(layoutType, newLayoutName, sourceLayoutName)
	if not self.LibEMO then
		return false
	end

	local LibEMO = self.LibEMO

	-- Create the layout
	local success = pcall(function()
		if sourceLayoutName then
			-- Copy from existing layout
			LibEMO:CopyLayout(sourceLayoutName, layoutType, newLayoutName)
		else
			-- Create fresh layout
			LibEMO:AddLayout(layoutType, newLayoutName)
		end
	end)

	if not success then
		if MoveIt.logger then
			MoveIt.logger.error(('Failed to create EditMode layout "%s"'):format(newLayoutName))
		end
		return false
	end

	-- Apply all current SpartanUI positions to the new layout
	local styleDB = SUI.DB and SUI.DB.Styles and SUI.DB.Styles[SUI.DB.Artwork.Style]
	if styleDB and styleDB.BlizzMovers then
		-- Switch to the new layout
		LibEMO:SetActiveLayout(newLayoutName)

		-- Apply each frame position
		for frameName, posString in pairs(styleDB.BlizzMovers) do
			local frameInfo = NATIVE_EDITMODE_FRAMES[frameName]
			if frameInfo then
				local point, anchor, relativePoint, x, y = self:ParseSUIPosition(posString)
				if point and x and y then
					pcall(function()
						LibEMO:SetSystemPosition(frameInfo.systemID, {
							point = point,
							relativeTo = anchor or 'UIParent',
							relativePoint = relativePoint or point,
							offsetX = tonumber(x) or 0,
							offsetY = tonumber(y) or 0,
						})
					end)
				end
			end
		end

		-- Save the layout
		self:SafeApplyChanges()
	end

	if MoveIt.logger then
		MoveIt.logger.info(('Created EditMode layout "%s" with SpartanUI positions'):format(newLayoutName))
	end

	return true
end

---Apply default positions to all EditMode frames
function BlizzardEditMode:ApplyDefaultPositions()
	if not self.LibEMO then
		return
	end

	-- Get default positions from current style
	local styleDB = SUI.DB and SUI.DB.Styles and SUI.DB.Styles[SUI.DB.Artwork.Style]
	if not styleDB then
		return
	end

	-- Apply each registered frame
	for frameName, frameInfo in pairs(NATIVE_EDITMODE_FRAMES) do
		local frame = _G[frameName]
		if frame then
			self:SetFramePositionFromDB(frameName, frame)
		end
	end

	if MoveIt.logger then
		MoveIt.logger.info('Applied default positions to all EditMode frames')
	end
end

---Handle SUI profile changes
---@param event string The event name
---@param database table The AceDB database
---@param newProfile string The new profile name
function BlizzardEditMode:OnSUIProfileChanged(event, database, newProfile)
	if not self.LibEMO then
		return
	end

	if MoveIt.logger then
		MoveIt.logger.info(('SUI profile changed to "%s" - updating EditMode layout'):format(newProfile))
	end

	-- Ensure SpartanUI EditMode profile exists and is active
	if self:EnsureProfileReady(self.LibEMO) then
		-- Apply all positions from the new SUI profile
		self:ApplyAllBlizzMoverPositions()
	end
end

---Switch to a specific EditMode profile by name
---@param profileName string The EditMode profile name to switch to
function BlizzardEditMode:SwitchToProfile(profileName)
	if not self.LibEMO then
		if MoveIt.logger then
			MoveIt.logger.error('SwitchToProfile: LibEMO not available')
		end
		return false
	end

	if not profileName or profileName == '' then
		if MoveIt.logger then
			MoveIt.logger.error('SwitchToProfile: Invalid profile name')
		end
		return false
	end

	-- Load layouts if needed
	if not self.LibEMO:AreLayoutsLoaded() then
		self.LibEMO:LoadLayouts()
	end

	-- Check if the profile exists
	if not self.LibEMO:DoesLayoutExist(profileName) then
		if MoveIt.logger then
			MoveIt.logger.warning(('SwitchToProfile: Profile "%s" does not exist'):format(profileName))
		end
		return false
	end

	-- Switch to the profile
	if MoveIt.logger then
		MoveIt.logger.info(('Switching to EditMode profile "%s"'):format(profileName))
	end

	local success = pcall(function()
		self.LibEMO:SetActiveLayout(profileName)
	end)

	if not success then
		if MoveIt.logger then
			MoveIt.logger.error(('Failed to switch to EditMode profile "%s"'):format(profileName))
		end
		return false
	end

	-- Apply changes and suppress movers
	self:SafeApplyChanges(true)

	return true
end

-- Initialize when module loads
EventRegistry:RegisterCallback('EditMode.Enter', function()
	-- When entering Edit Mode, ensure our profile is active
	if BlizzardEditMode.LibEMO then
		BlizzardEditMode:EnsureProfileReady(BlizzardEditMode.LibEMO)
	end
end)
