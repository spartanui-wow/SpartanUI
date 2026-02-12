---@class SUI
local SUI = SUI
local MoveIt = SUI.MoveIt
local L = SUI.L

-- ============================================================================
-- MoveIt EditMode Setup Wizard Page
-- Shown when user needs EditMode profile setup (preset or custom profiles)
-- ============================================================================

local WizardPage = {}
MoveIt.WizardPage = WizardPage

-- Local state for wizard
local selectedOption = 'copy_new' -- Default option
local applyToAllCharacters = false
local pageWasAutoSkipped = false -- Flag to prevent double-application when auto-skipping
local migrationInProgress = false -- Flag to suppress popups during migration
local sharedProfileWarningShown = false -- Flag to prevent showing warning multiple times per session

---Check if migration is currently in progress
---@return boolean inProgress True if migration is happening
function WizardPage:IsMigrationInProgress()
	return migrationInProgress
end

---Get the character key for per-character EditMode tracking (e.g., "Libbi - Thrall")
---@return string charKey The character-realm key
function WizardPage:GetCharacterKey()
	return SUI.SpartanUIDB.keys.char
end

---Get the per-character EditMode setup record from global DB
---@return table|nil record The setup record for this character, or nil if not set up
function WizardPage:GetCharacterSetupRecord()
	if not MoveIt.DBG or not MoveIt.DBG.EditModeSetupCharacters then
		return nil
	end
	return MoveIt.DBG.EditModeSetupCharacters[self:GetCharacterKey()]
end

---Mark this character's EditMode setup as complete in global DB
---@param editModeProfile string The EditMode profile name assigned to this character
---@param migrationOption? string The migration option used ('apply_current', 'copy_new', 'do_nothing')
function WizardPage:SetCharacterSetupDone(editModeProfile, migrationOption)
	if not MoveIt.DBG then
		return
	end
	if not MoveIt.DBG.EditModeSetupCharacters then
		MoveIt.DBG.EditModeSetupCharacters = {}
	end
	MoveIt.DBG.EditModeSetupCharacters[self:GetCharacterKey()] = {
		setupDone = true,
		editModeProfile = editModeProfile,
		migrationOption = migrationOption,
		timestamp = time(),
	}
end

---Check if this character has completed EditMode setup (checks global per-character record)
---@return boolean done True if setup is complete for this character
function WizardPage:IsCharacterSetupDone()
	local record = self:GetCharacterSetupRecord()
	return record and record.setupDone == true
end

---Get this character's current EditMode profile from global DB
---@return string|nil profileName The current EditMode profile name, or nil if not set
function WizardPage:GetCurrentProfile()
	if not MoveIt.DBG or not MoveIt.DBG.CurrentProfiles then
		return nil
	end
	return MoveIt.DBG.CurrentProfiles[self:GetCharacterKey()]
end

---Set this character's current EditMode profile in global DB
---@param profileName string|nil The EditMode profile name to set (nil to clear)
function WizardPage:SetCurrentProfile(profileName)
	if not MoveIt.DBG then
		return
	end
	if not MoveIt.DBG.CurrentProfiles then
		MoveIt.DBG.CurrentProfiles = {}
	end
	MoveIt.DBG.CurrentProfiles[self:GetCharacterKey()] = profileName
end

---Check if user is using another character's SUI profile (not a proper shared profile)
---@return boolean isUsingOtherCharProfile True if using another character's profile
---@return string|nil otherCharName The name of the other character if applicable
function WizardPage:IsUsingOtherCharacterProfile()
	local currentSUIProfile = SUI.SpartanUIDB:GetCurrentProfile()
	local charKey = SUI.SpartanUIDB.keys.char -- e.g., "Libbi - Thrall"

	-- If using own character profile, that's fine
	if currentSUIProfile == charKey then
		return false, nil
	end

	-- If using a proper shared profile (Default, Realm, Class), that's fine
	if currentSUIProfile == 'Default' then
		return false, nil
	end
	if currentSUIProfile == SUI.SpartanUIDB.keys.realm then
		return false, nil
	end
	if currentSUIProfile == SUI.SpartanUIDB.keys.class then
		return false, nil
	end

	-- Check if the profile name looks like another character's profile (CharName - RealmName)
	local otherCharName, otherRealm = currentSUIProfile:match('^(.+)%s+%-%s+(.+)$')
	if otherCharName and otherRealm then
		-- This looks like another character's profile
		return true, otherCharName
	end

	-- Custom named profile - not another character's profile
	return false, nil
end

---Show warning popup when user is using another character's SUI profile
---@param otherCharName string The name of the character whose profile is being used
function WizardPage:ShowSharedProfileWarning(otherCharName)
	-- Don't show if already shown this session
	if sharedProfileWarningShown then
		return
	end
	sharedProfileWarningShown = true

	local currentChar = UnitName('player')

	local message = ("You are using %s's SpartanUI profile.\n\n"):format(otherCharName)
		.. 'This works for SpartanUI settings, but EditMode profiles are character-specific.\n\n'
		.. ('A personal EditMode profile "SpartanUI - %s" will be created for you.\n\n'):format(currentChar)
		.. 'To share EditMode layouts between characters, use a shared profile like "Default" in SpartanUI settings (/sui).'

	local LibAT = _G.LibAT
	if LibAT and LibAT.UI and LibAT.UI.CreateConfirmDialog then
		LibAT.UI.CreateConfirmDialog({
			title = 'SpartanUI - Profile Notice',
			message = message,
			confirmText = 'OK, got it',
			cancelText = nil, -- No cancel button
			onConfirm = function()
				-- Nothing to do, just informing
			end,
		})
	else
		-- Fallback to StaticPopup
		StaticPopupDialogs['SUI_EDITMODE_SHARED_PROFILE_WARNING'] = {
			text = message,
			button1 = 'OK',
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
		}
		StaticPopup_Show('SUI_EDITMODE_SHARED_PROFILE_WARNING')
	end

	if MoveIt.logger then
		MoveIt.logger.info(("Showed shared profile warning: using %s's profile"):format(otherCharName))
	end
end

---Ensure user is on the correct EditMode profile based on their SUI profile
---Called when SetupDone is true but user might not be on the expected profile.
---IMPORTANT: This function respects the user's current profile choice rather than
---forcing them back to a "SpartanUI" profile. If the user manually switched to
---a different profile, we update our tracking to match.
---@return boolean handled True if profile was verified or tracking was updated
local function EnsureCorrectProfile()
	if not MoveIt.BlizzardEditMode then
		return false
	end

	-- Check if EditMode management is enabled
	if MoveIt.DB and MoveIt.DB.EditModeControl and not MoveIt.DB.EditModeControl.Enabled then
		if MoveIt.logger then
			MoveIt.logger.debug('EnsureCorrectProfile: EditMode management disabled, skipping')
		end
		return true
	end

	-- Check if user is using another character's SUI profile
	local isUsingOtherProfile, otherCharName = WizardPage:IsUsingOtherCharacterProfile()
	if isUsingOtherProfile and otherCharName then
		if MoveIt.logger then
			MoveIt.logger.info(("EnsureCorrectProfile: User is using %s's SUI profile, showing warning"):format(otherCharName))
		end
		C_Timer.After(0.5, function()
			WizardPage:ShowSharedProfileWarning(otherCharName)
		end)
	end

	local LibEMO = MoveIt.BlizzardEditMode.LibEMO or LibStub('LibEditModeOverride-1.0', true)
	if not LibEMO or not LibEMO:IsReady() then
		return false
	end
	if not LibEMO:AreLayoutsLoaded() then
		LibEMO:LoadLayouts()
	end

	local currentLayout = LibEMO:GetActiveLayout()
	local expectedProfile = MoveIt.BlizzardEditMode:GetMatchingProfileName()

	-- Already on expected profile — nothing to do
	if currentLayout == expectedProfile then
		if MoveIt.logger then
			MoveIt.logger.debug(('EnsureCorrectProfile: Already on expected profile "%s"'):format(expectedProfile))
		end
		MoveIt.BlizzardEditMode.initialSetupComplete = true
		return true
	end

	-- User is on a different valid profile — respect their choice, update tracking
	if currentLayout and currentLayout ~= '' then
		if MoveIt.logger then
			MoveIt.logger.info(('EnsureCorrectProfile: User is on "%s" (expected "%s") - respecting user choice, updating tracking'):format(currentLayout, expectedProfile))
		end
		WizardPage:SetCurrentProfile(currentLayout)
		WizardPage:SetCharacterSetupDone(currentLayout, 'user_switch')
		MoveIt.BlizzardEditMode.initialSetupComplete = true
		return true
	end

	-- Current layout is somehow nil/empty — fall back to expected if it exists
	if expectedProfile and LibEMO:DoesLayoutExist(expectedProfile) then
		if MoveIt.logger then
			MoveIt.logger.info(('EnsureCorrectProfile: No active layout detected, switching to expected "%s"'):format(expectedProfile))
		end
		migrationInProgress = true
		MoveIt.BlizzardEditMode.suppressLayoutChangePopup = true
		pcall(function()
			LibEMO:SetActiveLayout(expectedProfile)
			MoveIt.BlizzardEditMode:SafeApplyChanges('automatic')
		end)
		WizardPage:SetCurrentProfile(expectedProfile)
		MoveIt.BlizzardEditMode.initialSetupComplete = true
		C_Timer.After(2.0, function()
			MoveIt.BlizzardEditMode.suppressLayoutChangePopup = false
		end)
		migrationInProgress = false
	end

	return true
end

---Silently apply EditMode profile for users on preset layouts
---@return boolean applied True if profile was silently applied
local function TrySilentPresetSetup()
	if not MoveIt.BlizzardEditMode then
		return false
	end

	local state = MoveIt.BlizzardEditMode:GetEditModeState()

	-- Only for preset layouts (Modern/Classic)
	if not state.isOnPresetLayout or state.isOnSpartanUILayout then
		-- Mark initial setup complete even if we didn't apply
		MoveIt.BlizzardEditMode.initialSetupComplete = true
		return false
	end

	if MoveIt.logger then
		MoveIt.logger.info('TrySilentPresetSetup: User on preset layout, silently creating SpartanUI profile')
	end

	-- Set migration flag before applying
	migrationInProgress = true

	-- Apply the migration silently (this also sets initialSetupComplete)
	WizardPage:ApplyMigration('copy_new', false)

	-- Note: migrationInProgress is cleared in ApplyMigration
	return true
end

---Check if the upgrade wizard should be shown
---@return boolean shouldShow True if wizard page should be displayed
local function ShouldShowWizard()
	-- Skip on non-Retail (no EditMode)
	if not SUI.IsRetail then
		return false
	end

	-- Skip if EditMode not available
	if not EditModeManagerFrame then
		return false
	end

	-- Get current EditMode state first - we need this for all decisions
	local state = nil
	if MoveIt.BlizzardEditMode then
		state = MoveIt.BlizzardEditMode:GetEditModeState()
	end

	-- Migrate existing users: if per-profile SetupDone is true but no per-character record exists,
	-- backfill the global record — but ONLY if this character is actually on a SpartanUI EditMode layout.
	-- A shared SUI profile may have SetupDone=true from another character, but EditMode profiles
	-- are per-character in WoW, so we can't trust SetupDone from a shared profile.
	if not WizardPage:IsCharacterSetupDone() and MoveIt.DB and MoveIt.DB.EditModeWizard and MoveIt.DB.EditModeWizard.SetupDone then
		if state and state.isOnSpartanUILayout then
			-- Character is already on a SpartanUI EditMode layout — safe to backfill
			local existingProfile = state.currentLayoutName or WizardPage:GetCurrentProfile() or 'SpartanUI'
			local existingOption = MoveIt.DB.EditModeWizard.MigrationOption or 'migrated'
			WizardPage:SetCharacterSetupDone(existingProfile, existingOption)
			WizardPage:SetCurrentProfile(existingProfile)
			if MoveIt.logger then
				MoveIt.logger.info(('ShouldShowWizard: Migrated existing setup record for %s (profile: %s)'):format(WizardPage:GetCharacterKey(), existingProfile))
			end
		else
			-- Character is NOT on a SpartanUI layout despite shared profile saying SetupDone=true
			-- This means another character set it up — this character still needs setup
			if MoveIt.logger then
				MoveIt.logger.info(
					('ShouldShowWizard: Shared profile has SetupDone=true but %s is on "%s", not SpartanUI — needs setup'):format(
						WizardPage:GetCharacterKey(),
						state and state.currentLayoutName or 'unknown'
					)
				)
			end
		end
	end

	-- If user is already on a SpartanUI layout, mark setup complete and skip
	if state and state.isOnSpartanUILayout then
		if MoveIt.BlizzardEditMode then
			MoveIt.BlizzardEditMode.initialSetupComplete = true
		end
		-- Record per-character setup in global DB
		WizardPage:SetCharacterSetupDone(state.currentLayoutName, 'already_on_sui')
		WizardPage:SetCurrentProfile(state.currentLayoutName)
		if MoveIt.logger then
			MoveIt.logger.info(('ShouldShowWizard: User already on SpartanUI layout "%s", skipping wizard'):format(state.currentLayoutName))
		end
		return false
	end

	-- Skip if this character already completed EditMode setup (per-character global check)
	if WizardPage:IsCharacterSetupDone() then
		-- Ensure we're on the correct profile (handles profile mismatch after login)
		C_Timer.After(0.1, function()
			EnsureCorrectProfile()
		end)
		-- Mark initial setup as complete since wizard was already done previously
		if MoveIt.BlizzardEditMode then
			MoveIt.BlizzardEditMode.initialSetupComplete = true
		end
		if MoveIt.logger then
			local record = WizardPage:GetCharacterSetupRecord()
			MoveIt.logger.debug(('ShouldShowWizard: Character already set up (profile: %s), skipping'):format(record and record.editModeProfile or 'unknown'))
		end
		return false
	end

	-- Check global preference for auto-apply (only for characters that haven't been set up yet)
	if MoveIt.DBG and MoveIt.DBG.EditModePreferences and MoveIt.DBG.EditModePreferences.ApplyToAllCharacters then
		local defaultOption = MoveIt.DBG.EditModePreferences.DefaultMigrationOption
		if defaultOption then
			-- Auto-apply saved preference
			C_Timer.After(0.1, function()
				WizardPage:ApplyMigration(defaultOption, false)
			end)
			return false
		end
	end

	-- For preset layouts (Modern/Classic), silently apply - no wizard needed
	if state and state.isOnPresetLayout then
		if MoveIt.logger then
			MoveIt.logger.info(('ShouldShowWizard: User on preset layout "%s", scheduling silent setup'):format(state.currentLayoutName))
		end
		C_Timer.After(0.1, function()
			TrySilentPresetSetup()
		end)
		return false
	end

	-- If EditMode state couldn't be fully determined (LibEMO not ready), skip wizard
	-- The silent setup or popup will handle it later when ready
	if not state or not state.currentLayoutName then
		if MoveIt.logger then
			MoveIt.logger.info('ShouldShowWizard: Could not determine current layout (LibEMO not ready?), skipping wizard')
		end
		return false
	end

	-- Only show wizard for upgrade scenario: custom profile that's not preset and not SpartanUI
	if state.needsUpgradeWizard then
		return true
	end

	-- No wizard needed, mark setup complete
	if MoveIt.BlizzardEditMode then
		MoveIt.BlizzardEditMode.initialSetupComplete = true
	end

	return false
end

---Apply the migration based on selected option
---@param option string 'apply_current', 'copy_new', or 'do_nothing'
---@param saveGlobal boolean Whether to save preference globally
function WizardPage:ApplyMigration(option, saveGlobal)
	if not MoveIt.BlizzardEditMode then
		return
	end

	local LibEMO = MoveIt.BlizzardEditMode.LibEMO or LibStub('LibEditModeOverride-1.0', true)
	if not LibEMO then
		return
	end

	-- Set migration in progress flag to suppress popups
	migrationInProgress = true

	-- Mark initial setup as complete to enable layout change monitoring
	MoveIt.BlizzardEditMode.initialSetupComplete = true

	local state = MoveIt.BlizzardEditMode:GetEditModeState()
	local currentLayoutName = state.currentLayoutName

	-- Handle "do nothing" option - just mark setup as done without changes
	if option == 'do_nothing' then
		if MoveIt.logger then
			MoveIt.logger.info(('WizardPage: User chose to keep current profile "%s" without changes'):format(currentLayoutName or 'unknown'))
		end

		MoveIt.DB.EditModeWizard.SetupDone = true
		WizardPage:SetCurrentProfile(currentLayoutName)
		-- Disable EditMode management since user doesn't want us to manage it
		MoveIt.DB.EditModeControl.Enabled = false

		-- Record per-character setup
		WizardPage:SetCharacterSetupDone(currentLayoutName or 'none', 'do_nothing')

		-- Save global preference if requested
		if saveGlobal and MoveIt.DBG then
			MoveIt.DBG.EditModePreferences.ApplyToAllCharacters = true
			MoveIt.DBG.EditModePreferences.DefaultMigrationOption = option
		end

		migrationInProgress = false
		return
	end

	if option == 'apply_current' then
		-- Apply SUI defaults to current profile (only for custom profiles, not presets)
		if state.isOnPresetLayout then
			-- Can't modify preset, fall back to copy_new
			option = 'copy_new'
		else
			if MoveIt.logger then
				MoveIt.logger.info(('WizardPage: Applying SUI defaults to current profile "%s"'):format(currentLayoutName))
			end

			MoveIt.BlizzardEditMode:ApplyDefaultPositions()
			MoveIt.BlizzardEditMode:SafeApplyChanges(true)

			MoveIt.DB.EditModeWizard.MigratedFromProfile = currentLayoutName
			MoveIt.DB.EditModeWizard.MigrationOption = 'apply_current'
			WizardPage:SetCurrentProfile(currentLayoutName)

			-- Mark setup as done
			MoveIt.DB.EditModeWizard.SetupDone = true
			WizardPage:SetCharacterSetupDone(currentLayoutName, 'apply_current')

			-- Save global preference if requested
			if saveGlobal and MoveIt.DBG then
				MoveIt.DBG.EditModePreferences.ApplyToAllCharacters = true
				MoveIt.DBG.EditModePreferences.DefaultMigrationOption = option
			end
			migrationInProgress = false
			return
		end
	end

	if option == 'copy_new' then
		-- Create new SpartanUI profile, then apply defaults
		local newProfileName = MoveIt.BlizzardEditMode:GetMatchingProfileName()
		local layoutType = MoveIt.BlizzardEditMode:DetermineLayoutType()

		if MoveIt.logger then
			MoveIt.logger.info(('WizardPage: Creating profile "%s" (layout type: %s)'):format(newProfileName, tostring(layoutType)))
		end

		-- Ensure layouts are loaded
		if not LibEMO:AreLayoutsLoaded() then
			LibEMO:LoadLayouts()
		end

		-- Check if profile already exists
		if LibEMO:DoesLayoutExist(newProfileName) then
			if MoveIt.logger then
				MoveIt.logger.info(('WizardPage: Profile "%s" already exists, switching to it'):format(newProfileName))
			end
			pcall(function()
				LibEMO:SetActiveLayout(newProfileName)
			end)
		else
			-- For preset layouts, use standard AddLayout (copies from Modern which is fine)
			-- For custom layouts, use CreateLayoutFromCurrent to preserve user's positions
			if state.isOnPresetLayout then
				if MoveIt.logger then
					MoveIt.logger.info(('WizardPage: Creating new profile "%s" from preset'):format(newProfileName))
				end
				pcall(function()
					LibEMO:AddLayout(layoutType, newProfileName)
					LibEMO:SetActiveLayout(newProfileName)
				end)
			else
				-- Create from current to preserve user's customizations
				if MoveIt.logger then
					MoveIt.logger.info(('WizardPage: Creating profile "%s" as copy of "%s"'):format(newProfileName, currentLayoutName))
				end
				-- Pass preserveSourcePositions=true to keep the user's custom positions from the copy
				MoveIt.BlizzardEditMode:CreateLayoutFromCurrent(layoutType, newProfileName, currentLayoutName, true)
			end
		end

		-- Apply SUI defaults — use additive mode when copying from custom layout
		-- to preserve user's existing positions (e.g., chat frame they already moved)
		local isFromCustomLayout = not state.isOnPresetLayout
		MoveIt.BlizzardEditMode:ApplyDefaultPositions(isFromCustomLayout)
		MoveIt.BlizzardEditMode:SafeApplyChanges(true)

		-- If we created a shared (Account) profile, also create a character-specific fallback
		-- This gives the user a personal profile to fall back to if needed
		if layoutType == Enum.EditModeLayoutType.Account then
			local charName = UnitName('player')
			local fallbackProfileName = 'SpartanUI - ' .. charName
			if not LibEMO:DoesLayoutExist(fallbackProfileName) then
				if MoveIt.logger then
					MoveIt.logger.info(('WizardPage: Creating fallback character profile "%s"'):format(fallbackProfileName))
				end
				pcall(function()
					-- Create character profile from Modern (clean slate)
					LibEMO:AddLayout(Enum.EditModeLayoutType.Character, fallbackProfileName)
				end)
				-- Note: We don't switch to it, just create it as a fallback
			end
		end

		MoveIt.DB.EditModeWizard.MigratedFromProfile = currentLayoutName
		MoveIt.DB.EditModeWizard.MigrationOption = 'copy_new'
		WizardPage:SetCurrentProfile(newProfileName)
	end

	-- Mark setup as done
	MoveIt.DB.EditModeWizard.SetupDone = true
	WizardPage:SetCharacterSetupDone(WizardPage:GetCurrentProfile() or 'SpartanUI', option)

	-- Save global preference if requested
	if saveGlobal and MoveIt.DBG then
		MoveIt.DBG.EditModePreferences.ApplyToAllCharacters = true
		MoveIt.DBG.EditModePreferences.DefaultMigrationOption = option
	end

	-- Clear migration in progress flag
	migrationInProgress = false
end

---Register the wizard page with the setup wizard system
function WizardPage:RegisterPage()
	if not SUI.Setup then
		return
	end

	local PageData = {
		ID = 'MoveItEditModeUpgrade',
		SubTitle = 'EditMode Profile Setup',
		Desc1 = 'SpartanUI needs to configure your EditMode profile for frame positioning.',
		Desc2 = '',
		Priority = true, -- Show early in wizard, after WelcomePage
		RequireDisplay = ShouldShowWizard(), -- Evaluated when RegisterPage is called (after DB init)

		Display = function()
			local UI = LibAT.UI
			local window = SUI.Setup.window

			-- Get current state
			local state = MoveIt.BlizzardEditMode:GetEditModeState()

			-- Dynamic skip check - if user is already on SpartanUI layout or preset, skip this page
			if state.isOnSpartanUILayout then
				-- Already on SpartanUI layout, mark setup done and skip
				if MoveIt.DB and MoveIt.DB.EditModeWizard then
					MoveIt.DB.EditModeWizard.SetupDone = true
				end
				WizardPage:SetCurrentProfile(state.currentLayoutName)
				WizardPage:SetCharacterSetupDone(state.currentLayoutName, 'already_on_sui')
				if MoveIt.BlizzardEditMode then
					MoveIt.BlizzardEditMode.initialSetupComplete = true
				end
				if MoveIt.logger then
					MoveIt.logger.info(('WizardPage Display: Already on SpartanUI layout "%s", auto-skipping'):format(state.currentLayoutName))
				end
				-- Mark as auto-skipped so Next function doesn't re-apply
				pageWasAutoSkipped = true
				-- Auto-advance to next page
				C_Timer.After(0.01, function()
					if window and window.Next then
						window.Next:Click()
					end
				end)
				return
			end

			if state.isOnPresetLayout then
				-- On preset layout, silently apply and skip
				if MoveIt.logger then
					MoveIt.logger.info(('WizardPage Display: On preset layout "%s", silently applying'):format(state.currentLayoutName))
				end
				WizardPage:ApplyMigration('copy_new', false)
				-- Mark as auto-skipped so Next function doesn't re-apply
				pageWasAutoSkipped = true
				-- Auto-advance to next page
				C_Timer.After(0.01, function()
					if window and window.Next then
						window.Next:Click()
					end
				end)
				return
			end

			-- Reset flag for normal display
			pageWasAutoSkipped = false

			local currentLayoutName = state.currentLayoutName or 'Unknown'
			local customizedFrames = state.customizedFrames or {}
			local newProfileName = MoveIt.BlizzardEditMode:GetMatchingProfileName()

			-- Create container frame
			local UpgradePage = CreateFrame('Frame', nil)
			UpgradePage:SetParent(window.content)
			UpgradePage:SetAllPoints(window.content)

			-- This page only shows for custom profiles (presets are handled silently)
			local warningLabel = UI.CreateLabel(UpgradePage, ('Current EditMode Profile: |cFFFFFF00%s|r'):format(currentLayoutName), 'GameFontNormalLarge')
			warningLabel:SetPoint('TOP', UpgradePage, 'TOP', 0, -10)
			warningLabel:SetJustifyH('CENTER')
			warningLabel:SetWidth(600)

			-- Show customized frames if any
			local customFramesY = -40
			if #customizedFrames > 0 then
				local customLabel = UI.CreateLabel(UpgradePage, 'You have customized the following frames: |cFF69BD45' .. table.concat(customizedFrames, ', ') .. '|r')
				customLabel:SetPoint('TOP', warningLabel, 'BOTTOM', 0, -10)
				customLabel:SetJustifyH('CENTER')
				customLabel:SetWidth(600)
				customFramesY = -70
			end

			-- Options section header
			local optionsHeader = UI.CreateLabel(UpgradePage, 'Choose migration option:', 'GameFontNormal')
			optionsHeader:SetPoint('TOP', UpgradePage, 'TOP', 0, customFramesY)
			optionsHeader:SetJustifyH('CENTER')

			-- Option 1: Apply to current profile
			local option1Frame = CreateFrame('Frame', nil, UpgradePage)
			option1Frame:SetSize(550, 60)
			option1Frame:SetPoint('TOP', optionsHeader, 'BOTTOM', 0, -15)

			local option1Radio = CreateFrame('CheckButton', 'SUI_MoveIt_Wizard_Option1', option1Frame, 'UIRadioButtonTemplate')
			option1Radio:SetPoint('TOPLEFT', option1Frame, 'TOPLEFT', 0, 0)
			option1Radio:SetChecked(selectedOption == 'apply_current')

			local option1Label = UI.CreateLabel(option1Frame, 'Apply to Current Profile', 'GameFontHighlight')
			option1Label:SetPoint('LEFT', option1Radio, 'RIGHT', 5, 0)

			local option1Desc = UI.CreateLabel(option1Frame, ('Apply SUI frame positions to your "%s" profile.\nYour other customizations will be preserved.'):format(currentLayoutName))
			option1Desc:SetPoint('TOPLEFT', option1Radio, 'BOTTOMLEFT', 20, -2)
			option1Desc:SetTextColor(0.7, 0.7, 0.7)
			option1Desc:SetWidth(500)

			-- Option 2: Create new copy (DEFAULT)
			local option2Frame = CreateFrame('Frame', nil, UpgradePage)
			option2Frame:SetSize(550, 60)
			option2Frame:SetPoint('TOP', option1Frame, 'BOTTOM', 0, -5)

			local option2Radio = CreateFrame('CheckButton', 'SUI_MoveIt_Wizard_Option2', option2Frame, 'UIRadioButtonTemplate')
			option2Radio:SetPoint('TOPLEFT', option2Frame, 'TOPLEFT', 0, 0)
			option2Radio:SetChecked(selectedOption == 'copy_new')

			local option2Label = UI.CreateLabel(option2Frame, 'Create New SpartanUI Profile (Recommended)', 'GameFontHighlight')
			option2Label:SetPoint('LEFT', option2Radio, 'RIGHT', 5, 0)

			local option2Desc = UI.CreateLabel(
				option2Frame,
				('Create "%s" as a copy of your current profile,\nthen apply SUI frame positions. Your original "%s" profile remains unchanged.'):format(newProfileName, currentLayoutName)
			)
			option2Desc:SetPoint('TOPLEFT', option2Radio, 'BOTTOMLEFT', 20, -2)
			option2Desc:SetTextColor(0.7, 0.7, 0.7)
			option2Desc:SetWidth(500)

			-- Option 3: Do nothing
			local option3Frame = CreateFrame('Frame', nil, UpgradePage)
			option3Frame:SetSize(550, 50)
			option3Frame:SetPoint('TOP', option2Frame, 'BOTTOM', 0, -5)

			local option3Radio = CreateFrame('CheckButton', 'SUI_MoveIt_Wizard_Option3', option3Frame, 'UIRadioButtonTemplate')
			option3Radio:SetPoint('TOPLEFT', option3Frame, 'TOPLEFT', 0, 0)
			option3Radio:SetChecked(selectedOption == 'do_nothing')

			local option3Label = UI.CreateLabel(option3Frame, 'Do Nothing', 'GameFontHighlight')
			option3Label:SetPoint('LEFT', option3Radio, 'RIGHT', 5, 0)

			local option3Desc = UI.CreateLabel(option3Frame, 'Keep your current EditMode profile as-is. SpartanUI will not manage your EditMode profiles.')
			option3Desc:SetPoint('TOPLEFT', option3Radio, 'BOTTOMLEFT', 20, -2)
			option3Desc:SetTextColor(0.7, 0.7, 0.7)
			option3Desc:SetWidth(500)

			-- Radio button behavior
			option1Radio:SetScript('OnClick', function()
				selectedOption = 'apply_current'
				option1Radio:SetChecked(true)
				option2Radio:SetChecked(false)
				option3Radio:SetChecked(false)
			end)

			option2Radio:SetScript('OnClick', function()
				selectedOption = 'copy_new'
				option1Radio:SetChecked(false)
				option2Radio:SetChecked(true)
				option3Radio:SetChecked(false)
			end)

			option3Radio:SetScript('OnClick', function()
				selectedOption = 'do_nothing'
				option1Radio:SetChecked(false)
				option2Radio:SetChecked(false)
				option3Radio:SetChecked(true)
			end)

			-- "Apply to all characters" checkbox
			local applyAllCheckbox = CreateFrame('CheckButton', 'SUI_MoveIt_Wizard_ApplyAll', UpgradePage, 'UICheckButtonTemplate')
			applyAllCheckbox:SetPoint('TOP', option3Frame, 'BOTTOM', 0, -10)
			applyAllCheckbox:SetPoint('LEFT', UpgradePage, 'CENTER', -150, 0)
			applyAllCheckbox:SetChecked(applyToAllCharacters)

			local applyAllLabel = UI.CreateLabel(UpgradePage, 'Apply this choice to all my other characters')
			applyAllLabel:SetPoint('LEFT', applyAllCheckbox, 'RIGHT', 5, 0)

			applyAllCheckbox:SetScript('OnClick', function(self)
				applyToAllCharacters = self:GetChecked()
			end)

			-- Store reference for Next function
			window.content.MoveItUpgradePage = UpgradePage
		end,

		Next = function()
			-- Skip if page was auto-skipped (already handled in Display)
			if pageWasAutoSkipped then
				pageWasAutoSkipped = false -- Reset for potential future use
				return
			end
			-- Apply the selected migration option
			WizardPage:ApplyMigration(selectedOption, applyToAllCharacters)
		end,
	}

	SUI.Setup:AddPage(PageData)

	if MoveIt.logger then
		MoveIt.logger.info('MoveIt EditMode upgrade wizard page registered')
	end
end

-- Registration is now called from MoveIt:OnEnable() after DB is initialized
-- This ensures MoveIt.DB is available when ShouldShowWizard() is evaluated
