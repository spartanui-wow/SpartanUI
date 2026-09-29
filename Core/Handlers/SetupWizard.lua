---@class SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Handler.SetupWizard
local module = SUI:NewModule('Handler.SetupWizard') ---@type SUI.Module

local ADDON_ID = 'spartanui'

----------------------------------------------------------------------------------------------------
-- Backward compat stub: old modules calling SUI.Setup:AddPage() will silently no-op
----------------------------------------------------------------------------------------------------

---@param PageData table
function module:AddPage(PageData)
	-- No-op: old-style pages are no longer supported.
	-- Modules should use LibAT.SetupWizard:AddPage('spartanui', page) instead.
end

----------------------------------------------------------------------------------------------------
-- Registration
----------------------------------------------------------------------------------------------------

function module:OnInitialize()
	if not LibAT or not LibAT.SetupWizard then
		return
	end

	LibAT.SetupWizard:RegisterAddon(ADDON_ID, {
		name = 'SpartanUI',
		icon = 'Interface\\AddOns\\SpartanUI\\images\\setup\\SUISetup',
		pages = {},
	})

	-- Register Welcome and Other Addons pages (core concerns)
	self:RegisterWelcomePage()
	self:RegisterOtherAddonsPage()
end

function module:OnEnable()
	if not LibAT or not LibAT.SetupWizard then
		return
	end

	-- Migration: if old wizard was completed, grandfather all SUI pages as complete
	if not SUI.DB.SetupWizard.FirstLaunch and LibAT.Database and LibAT.Database.global then
		if not LibAT.Database.global.setupWizardCompleted then
			LibAT.Database.global.setupWizardCompleted = {}
		end
		local completed = LibAT.Database.global.setupWizardCompleted
		if not completed[ADDON_ID .. '.welcome'] then
			local allPages = {
				'welcome',
				'theme',
				'artwork-options',
				'font',
				'modules',
				'unitframes',
				'uf-personal',
				'uf-group',
				'autosell',
				'questtools',
				'minimap',
				'tooltips',
				'convenience',
				'uienhancements',
				'other-addons',
			}
			for _, pageId in ipairs(allPages) do
				completed[ADDON_ID .. '.' .. pageId] = true
			end
		end
	end

	-- Auto-open wizard on first launch. Completion is account-wide, so a fresh profile opens the
	-- wizard without clearing progress that other characters' profiles rely on.
	if SUI.DB.SetupWizard.FirstLaunch then
		local function OpenOnFirstLaunch()
			if InCombatLockdown() then
				return
			end
			if not LibAT.SetupWizard.window or not LibAT.SetupWizard.window:IsShown() then
				LibAT.SetupWizard:OpenWindow()
			end
		end
		-- AceAddon enables modules while PLAYER_LOGIN is being dispatched, so that event has already fired here
		if IsLoggedIn() then
			C_Timer.After(1, OpenOnFirstLaunch)
		else
			local LoadWatcher = CreateFrame('Frame')
			LoadWatcher:SetScript('OnEvent', function()
				LoadWatcher:UnregisterAllEvents()
				LoadWatcher:SetScript('OnEvent', nil)
				C_Timer.After(1, OpenOnFirstLaunch)
			end)
			LoadWatcher:RegisterEvent('PLAYER_LOGIN')
		end
	end

	SUI:AddChatCommand('setup', function()
		LibAT.SetupWizard:OpenWindow()
	end, 'Open the setup wizard')
end

----------------------------------------------------------------------------------------------------
-- Welcome Page
----------------------------------------------------------------------------------------------------

function module:RegisterWelcomePage()
	if LibAT.SetupWizard:GetPage(ADDON_ID, 'welcome') then
		return
	end
	LibAT.SetupWizard:AddPage(ADDON_ID, {
		id = 'welcome',
		name = L['Welcome'],
		order = 10,
		builder = function(contentFrame)
			self:BuildWelcomePage(contentFrame)
		end,
		onLeave = function()
			self:OnLeaveWelcome()
		end,
		isComplete = function()
			return not SUI.DB.SetupWizard.FirstLaunch
		end,
	})
end

function module:BuildWelcomePage(contentFrame)
	local UI = LibAT.UI

	-- SUI Logo
	local logo = contentFrame:CreateTexture(nil, 'ARTWORK')
	logo:SetTexture('Interface\\AddOns\\SpartanUI\\images\\setup\\SUISetup')
	logo:SetSize(205, 51)
	logo:SetPoint('TOP', contentFrame, 'TOP', 0, -10)
	logo:SetAlpha(0.8)

	-- Welcome text
	local welcomeText = UI.CreateLabel(contentFrame, '', 'GameFontNormal')
	welcomeText:SetPoint('TOP', logo, 'BOTTOM', 0, -10)
	welcomeText:SetPoint('LEFT', contentFrame, 'LEFT', 20, 0)
	welcomeText:SetPoint('RIGHT', contentFrame, 'RIGHT', -20, 0)
	welcomeText:SetJustifyH('CENTER')
	welcomeText:SetWordWrap(true)
	welcomeText:SetText('Welcome to SpartanUI! This wizard will help you set up the UI and its modules.\nYou can re-run this wizard any time via /setup or the SUI settings screen.')

	local currentProfile = SUI.SpartanUIDB:GetCurrentProfile()

	-- Build profile lists
	local function GetProfileListWithCommon(excludeCurrent, excludeCharProfiles)
		local profileList = {}
		local tmpProfiles = {}
		SUI.SpartanUIDB:GetProfiles(tmpProfiles)

		local function isCharacterProfile(profileName)
			if not profileName:find(' %- ') then
				return false
			end
			if SUI.SpartanUIDB.sv and SUI.SpartanUIDB.sv.profileKeys then
				for charKey, _ in pairs(SUI.SpartanUIDB.sv.profileKeys) do
					if profileName == charKey then
						return true
					end
				end
			end
			return false
		end

		for _, v in pairs(tmpProfiles) do
			local shouldExclude = (excludeCurrent and v == currentProfile) or (excludeCharProfiles and isCharacterProfile(v))
			if not shouldExclude then
				profileList[#profileList + 1] = { text = v, value = v, isCommon = false }
			end
		end

		local commonProfiles = {
			{ key = 'Default', text = 'Default' },
			{ key = SUI.SpartanUIDB.keys.realm, text = SUI.SpartanUIDB.keys.realm },
			{ key = SUI.SpartanUIDB.keys.class, text = UnitClass('player') },
		}

		for _, common in ipairs(commonProfiles) do
			if not (excludeCurrent and common.key == currentProfile) then
				local found = false
				for _, profile in ipairs(profileList) do
					if profile.value == common.key then
						found = true
						break
					end
				end
				if not found then
					profileList[#profileList + 1] = { text = common.text, value = common.key, isCommon = true }
				end
			end
		end

		return profileList
	end

	local copyProfiles = GetProfileListWithCommon(true, false)
	local sharedProfiles = GetProfileListWithCommon(true, true)

	table.sort(sharedProfiles, function(a, b)
		local aIsDefault = a.value == 'Default'
		local bIsDefault = b.value == 'Default'
		if aIsDefault then
			return true
		end
		if bIsDefault then
			return false
		end
		local aIsRealm = a.value == SUI.SpartanUIDB.keys.realm
		local bIsRealm = b.value == SUI.SpartanUIDB.keys.realm
		if aIsRealm and not bIsRealm then
			return true
		end
		if bIsRealm and not aIsRealm then
			return false
		end
		local aIsClass = a.value == SUI.SpartanUIDB.keys.class
		local bIsClass = b.value == SUI.SpartanUIDB.keys.class
		if aIsClass and not bIsClass then
			return true
		end
		if bIsClass and not aIsClass then
			return false
		end
		return a.text < b.text
	end)

	-- Profile copy section
	local copyLabel = UI.CreateLabel(contentFrame, 'Copy settings from another profile:', 'GameFontNormal')
	copyLabel:SetWidth(400)
	copyLabel:SetJustifyH('CENTER')
	copyLabel:SetWordWrap(true)
	copyLabel:SetPoint('TOP', welcomeText, 'BOTTOM', 0, -25)

	local copyDropdown = UI.CreateDropdown(contentFrame, 'Select Profile...', 200, 20)
	copyDropdown.selectedValue = nil
	copyDropdown:SetupMenu(function(dropdown, rootDescription)
		for _, profile in ipairs(copyProfiles) do
			rootDescription:CreateButton(profile.text, function()
				dropdown.selectedValue = profile.value
				dropdown:SetText(profile.text)
			end)
		end
	end)
	copyDropdown:SetPoint('TOP', copyLabel, 'BOTTOM', 0, -5)
	copyDropdown:SetPoint('LEFT', contentFrame, 'CENTER', -130, 0)

	local copyBtn = UI.CreateButton(contentFrame, 60, 20, 'COPY')
	copyBtn:SetScript('OnClick', function()
		local selection = copyDropdown.selectedValue
		if not selection or selection == '' then
			return
		end
		self:HandleEditModeBeforeProfileChange(selection, false)
		SUI.SpartanUIDB:CopyProfile(selection)
		self:HandleEditModeAfterProfileChange(selection, false)
		SUI:SafeReloadUI()
	end)
	copyBtn:SetPoint('LEFT', copyDropdown, 'RIGHT', 4, 0)

	-- Shared profile section
	local sharedLabel = UI.CreateLabel(contentFrame, 'Share a profile between characters:', 'GameFontNormal')
	sharedLabel:SetWidth(400)
	sharedLabel:SetJustifyH('CENTER')
	sharedLabel:SetWordWrap(true)
	sharedLabel:SetPoint('TOP', copyLabel, 'BOTTOM', 0, -60)

	local sharedInfoBtn = UI.CreateInfoButton(
		contentFrame,
		"Why can't I share my character profile?",
		'Character profiles (e.g., "Mythra - Area 52") are for one character only.\n\nTo share settings, use Default, Realm, Class, or a custom named profile.'
	)
	sharedInfoBtn:SetPoint('LEFT', sharedLabel, 'RIGHT', 5, 0)

	local sharedDropdown = UI.CreateDropdown(contentFrame, 'Select Profile...', 200, 20)
	sharedDropdown.selectedValue = nil
	sharedDropdown:SetupMenu(function(dropdown, rootDescription)
		for _, profile in ipairs(sharedProfiles) do
			rootDescription:CreateButton(profile.text, function()
				dropdown.selectedValue = profile.value
				dropdown:SetText(profile.text)
			end)
		end
	end)
	sharedDropdown:SetPoint('TOP', sharedLabel, 'BOTTOM', 0, -5)
	sharedDropdown:SetPoint('LEFT', contentFrame, 'CENTER', -130, 0)

	local applyBtn = UI.CreateButton(contentFrame, 60, 20, 'APPLY')
	applyBtn:SetScript('OnClick', function()
		local selection = sharedDropdown.selectedValue
		if not selection or selection == '' then
			return
		end
		self:HandleEditModeBeforeProfileChange(selection, true)
		SUI.SpartanUIDB:SetProfile(selection)
		self:HandleEditModeAfterProfileChange(selection, true)
		SUI:SafeReloadUI()
	end)
	applyBtn:SetPoint('LEFT', sharedDropdown, 'RIGHT', 4, 0)

	-- Current profile status
	local statusLabel = UI.CreateLabel(contentFrame, '')
	statusLabel:SetJustifyH('CENTER')
	statusLabel:SetWordWrap(true)
	statusLabel:SetPoint('TOP', sharedDropdown, 'BOTTOM', 0, -30)
	statusLabel:SetPoint('LEFT', contentFrame, 'LEFT', 20, 0)
	statusLabel:SetPoint('RIGHT', contentFrame, 'RIGHT', -20, 0)

	local isCharProfile = false
	if currentProfile:find(' %- ') then
		if SUI.SpartanUIDB.sv and SUI.SpartanUIDB.sv.profileKeys then
			for charKey, _ in pairs(SUI.SpartanUIDB.sv.profileKeys) do
				if currentProfile == charKey then
					isCharProfile = true
					break
				end
			end
		end
	end

	if isCharProfile then
		statusLabel:SetText('Current Profile: ' .. currentProfile)
		statusLabel:SetTextColor(1, 0.82, 0)
	else
		statusLabel:SetText('Current: ' .. currentProfile)
		statusLabel:SetTextColor(0.5, 1, 0.5)
	end

	-- Hide profile sections if no profiles available
	if #copyProfiles == 0 and #sharedProfiles == 0 then
		copyLabel:Hide()
		copyDropdown:Hide()
		copyBtn:Hide()
		sharedLabel:Hide()
		sharedInfoBtn:Hide()
		sharedDropdown:Hide()
		applyBtn:Hide()
	end

	-- Set scroll child height
	contentFrame:SetHeight(400)
end

---Handle EditMode profile creation BEFORE profile copy/switch
---@param profileSelection string
---@param isSharedProfile boolean
function module:HandleEditModeBeforeProfileChange(profileSelection, isSharedProfile)
	if not SUI.IsRetail or not EditModeManagerFrame then
		return
	end

	local MoveIt = SUI.MoveIt
	if not MoveIt or not MoveIt.BlizzardEditMode then
		return
	end

	local state = MoveIt.BlizzardEditMode:GetEditModeState()
	local newEditModeProfileName

	if isSharedProfile then
		if profileSelection == 'Default' then
			newEditModeProfileName = 'SpartanUI'
		else
			newEditModeProfileName = 'SpartanUI - ' .. profileSelection
		end
	else
		newEditModeProfileName = MoveIt.BlizzardEditMode:GetMatchingProfileName()
	end

	local layoutType = isSharedProfile and Enum.EditModeLayoutType.Account or MoveIt.BlizzardEditMode:DetermineLayoutType()

	if MoveIt.logger then
		MoveIt.logger.info(('WelcomePage: Creating EditMode profile "%s"'):format(newEditModeProfileName))
	end

	local LibEMO = LibStub('LibEditModeOverride-1.0', true)
	if LibEMO and LibEMO:IsReady() then
		if not LibEMO:AreLayoutsLoaded() then
			LibEMO:LoadLayouts()
		end

		if LibEMO:DoesLayoutExist(newEditModeProfileName) then
			pcall(function()
				LibEMO:SetActiveLayout(newEditModeProfileName)
				MoveIt.BlizzardEditMode:SafeApplyChanges(true)
			end)
		else
			if state.isOnPresetLayout then
				pcall(function()
					LibEMO:AddLayout(layoutType, newEditModeProfileName)
					LibEMO:SetActiveLayout(newEditModeProfileName)
				end)
			else
				MoveIt.BlizzardEditMode:CreateLayoutFromCurrent(layoutType, newEditModeProfileName)
			end
			MoveIt.BlizzardEditMode:ApplyDefaultPositions()
			MoveIt.BlizzardEditMode:SafeApplyChanges(true)
		end
	end
end

---Mark EditMode setup as done AFTER profile copy/switch
---@param profileSelection string
---@param isSharedProfile boolean
function module:HandleEditModeAfterProfileChange(profileSelection, isSharedProfile)
	if not SUI.IsRetail or not EditModeManagerFrame then
		return
	end

	local MoveIt = SUI.MoveIt
	if not MoveIt then
		return
	end

	MoveIt.DB = MoveIt.Database.profile
	if MoveIt.DB and MoveIt.DB.EditModeWizard then
		local newEditModeProfileName
		if isSharedProfile then
			if profileSelection == 'Default' then
				newEditModeProfileName = 'SpartanUI'
			else
				newEditModeProfileName = 'SpartanUI - ' .. profileSelection
			end
		else
			newEditModeProfileName = MoveIt.BlizzardEditMode:GetMatchingProfileName()
		end
		MoveIt.DB.EditModeWizard.SetupDone = true
		MoveIt.DB.EditModeControl.CurrentProfile = newEditModeProfileName
		MoveIt.BlizzardEditMode.initialSetupComplete = true
	end
end

---Called when leaving the Welcome page
function module:OnLeaveWelcome()
	SUI.DB.SetupWizard.FirstLaunch = false

	-- Create matching EditMode profile for new users
	if SUI.IsRetail and EditModeManagerFrame then
		local MoveIt = SUI.MoveIt
		if MoveIt and MoveIt.BlizzardEditMode then
			MoveIt.BlizzardEditMode.suppressLayoutChangePopup = true

			local state = MoveIt.BlizzardEditMode:GetEditModeState()
			if state.isOnPresetLayout or not state.currentLayoutName then
				local profileName = MoveIt.BlizzardEditMode:GetMatchingProfileName()
				local layoutType = MoveIt.BlizzardEditMode:DetermineLayoutType()

				if MoveIt.logger then
					MoveIt.logger.info(('WelcomePage: Creating EditMode profile "%s" for new user'):format(profileName))
				end

				local LibEMO = LibStub('LibEditModeOverride-1.0', true)
				if LibEMO and LibEMO:IsReady() then
					if not LibEMO:AreLayoutsLoaded() then
						LibEMO:LoadLayouts()
					end

					if not LibEMO:DoesLayoutExist(profileName) then
						pcall(function()
							LibEMO:AddLayout(layoutType, profileName)
							LibEMO:SetActiveLayout(profileName)
						end)

						MoveIt.BlizzardEditMode:ApplyDefaultPositions()
						MoveIt.BlizzardEditMode:SafeApplyChanges(true)
					end

					if MoveIt.DB and MoveIt.DB.EditModeWizard then
						MoveIt.DB.EditModeWizard.SetupDone = true
						MoveIt.DB.EditModeControl.CurrentProfile = profileName
					end
				end
			end

			C_Timer.After(2.0, function()
				MoveIt.BlizzardEditMode.suppressLayoutChangePopup = false
			end)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Other Addons Page
----------------------------------------------------------------------------------------------------

function module:RegisterOtherAddonsPage()
	if LibAT.SetupWizard:GetPage(ADDON_ID, 'other-addons') then
		return
	end
	LibAT.SetupWizard:AddPage(ADDON_ID, {
		id = 'other-addons',
		name = 'Other Addons',
		order = 90,
		builder = function(contentFrame)
			self:BuildOtherAddonsPage(contentFrame)
		end,
	})
end

function module:BuildOtherAddonsPage(contentFrame)
	local UI = LibAT.UI

	local header = UI.CreateLabel(contentFrame, 'Companion Addons', 'GameFontNormalLarge')
	header:SetPoint('TOP', contentFrame, 'TOP', 0, 0)
	header:SetJustifyH('CENTER')

	local desc = UI.CreateLabel(contentFrame, 'These addons complement SpartanUI. Install them for additional features.', 'GameFontNormal')
	desc:SetPoint('TOP', header, 'BOTTOM', 0, -5)
	desc:SetPoint('LEFT', contentFrame, 'LEFT', 20, 0)
	desc:SetPoint('RIGHT', contentFrame, 'RIGHT', -20, 0)
	desc:SetJustifyH('CENTER')
	desc:SetWordWrap(true)

	local addons = {
		{
			name = 'SpartanUI Animated',
			desc = 'Adds animated artwork textures to SpartanUI themes.',
			addonName = 'SpartanUI-Animated',
			url = 'https://www.curseforge.com/wow/addons/spartanui-animated',
		},
		{
			name = 'FunFact',
			desc = 'Spam your group with random fun facts. Type /fact to share one, or they show on death.',
			global = 'FunFactDB',
			url = 'https://www.curseforge.com/wow/addons/funfact',
		},
		{
			name = "Lib's - Time Played",
			desc = 'Tracks /played time across all your characters with a data broker display. Cool graphs!',
			global = 'LibsTimePlayedDB',
			url = 'https://www.curseforge.com/wow/addons/libs-timeplayed',
		},
		{
			name = "Lib's - Farm Assistant",
			desc = 'Session-based farming tracker with loot, gold, currency, reputation, and honor tracking.',
			global = 'LibsFarmAssistantDB',
			url = 'https://github.com/spartanui-wow/Libs-FarmAssistant',
		},
		{
			name = "Lib's - DataBar",
			desc = 'Customizable data broker bar with plugins for clock, bags, currency, XP, location, and more.',
			global = 'LibsDataBarDB',
			url = 'https://github.com/spartanui-wow/Libs-DataBar',
		},
		{
			name = "Lib's - Item Highlighter",
			desc = 'Highlights openable, cosmetic, and usable items in your bags.',
			global = 'LibsIHDB',
			url = 'https://www.curseforge.com/wow/addons/libs-itemhighlighter',
		},
		{
			name = "Lib's - Disenchant Assist",
			desc = 'Smart disenchanting assistant with advanced filtering and safety features.',
			global = 'LibsDisenchantAssistDB',
			url = 'https://www.curseforge.com/wow/addons/libs-disenchantassist',
		},
	}

	local function isAddonInstalled(addon)
		if addon.addonName then
			return C_AddOns.IsAddOnLoaded(addon.addonName)
		end
		return _G[addon.global] ~= nil
	end

	-- Sort: non-installed first, installed last
	local notInstalled = {}
	local installed = {}
	for _, addon in ipairs(addons) do
		if isAddonInstalled(addon) then
			table.insert(installed, addon)
		else
			table.insert(notInstalled, addon)
		end
	end
	local sortedAddons = {}
	for _, addon in ipairs(notInstalled) do
		table.insert(sortedAddons, addon)
	end
	for _, addon in ipairs(installed) do
		table.insert(sortedAddons, addon)
	end

	local yOffset = -50
	local cardHeight = 64
	for _, addon in ipairs(sortedAddons) do
		local isInstalled = isAddonInstalled(addon)
		local card = CreateFrame('Frame', nil, contentFrame, BackdropTemplateMixin and 'BackdropTemplate')
		card:SetSize(contentFrame:GetWidth() - 40, cardHeight)
		card:SetPoint('TOP', contentFrame, 'TOP', 0, yOffset)
		card:SetPoint('LEFT', contentFrame, 'LEFT', 20, 0)
		card:SetPoint('RIGHT', contentFrame, 'RIGHT', -20, 0)
		card:SetBackdrop({
			bgFile = 'Interface\\Buttons\\WHITE8x8',
			edgeFile = 'Interface\\Buttons\\WHITE8x8',
			edgeSize = 1.5,
		})
		card:SetBackdropColor(0.1, 0.1, 0.1, 0.6)
		if isInstalled then
			card:SetBackdropBorderColor(0.2, 0.8, 0.2, 1)
		else
			card:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
		end

		local nameLabel = UI.CreateLabel(card, addon.name, 'GameFontNormal')
		nameLabel:SetPoint('TOPLEFT', card, 'TOPLEFT', 10, -8)

		if isInstalled then
			local statusLabel = UI.CreateLabel(card, 'Installed', 'GameFontNormalSmall')
			statusLabel:SetPoint('LEFT', nameLabel, 'RIGHT', 8, 0)
			statusLabel:SetTextColor(0.2, 0.8, 0.2)
		end

		local descLabel = UI.CreateLabel(card, addon.desc, 'GameFontHighlightSmall')
		descLabel:SetPoint('TOPLEFT', nameLabel, 'BOTTOMLEFT', 0, -2)
		descLabel:SetPoint('RIGHT', card, 'RIGHT', -10, 0)
		descLabel:SetWordWrap(true)

		if addon.url then
			local linkBox = CreateFrame('EditBox', nil, card, 'InputBoxTemplate')
			linkBox:SetSize(card:GetWidth() - 20, 16)
			linkBox:SetPoint('BOTTOMLEFT', card, 'BOTTOMLEFT', 10, 4)
			linkBox:SetAutoFocus(false)
			linkBox:SetFontObject('GameFontHighlightSmall')
			linkBox:SetText(addon.url)
			linkBox:SetCursorPosition(0)
			linkBox:SetScript('OnEditFocusGained', function(self)
				self:HighlightText()
			end)
			linkBox:SetScript('OnEscapePressed', function(self)
				self:ClearFocus()
			end)
			cardHeight = 80
			card:SetHeight(cardHeight)
		end

		yOffset = yOffset - (cardHeight + 6)
	end

	-- All projects link
	yOffset = yOffset - 10
	local cfHeader = UI.CreateLabel(contentFrame, 'All my projects', 'GameFontNormal')
	cfHeader:SetPoint('TOP', contentFrame, 'TOP', 0, yOffset)
	cfHeader:SetJustifyH('CENTER')

	yOffset = yOffset - 20
	local cfBox = CreateFrame('EditBox', nil, contentFrame, 'InputBoxTemplate')
	cfBox:SetSize(contentFrame:GetWidth() - 80, 20)
	cfBox:SetPoint('TOP', contentFrame, 'TOP', 0, yOffset)
	cfBox:SetAutoFocus(false)
	cfBox:SetText('https://www.curseforge.com/members/wutname1/projects')
	cfBox:SetCursorPosition(0)
	cfBox:SetScript('OnEditFocusGained', function(self)
		self:HighlightText()
	end)
	cfBox:SetScript('OnEscapePressed', function(self)
		self:ClearFocus()
	end)

	contentFrame:SetHeight(math.abs(yOffset) + 40)
end

SUI.Setup = module
