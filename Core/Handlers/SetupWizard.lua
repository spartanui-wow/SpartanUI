---@class SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Handler.SetupWizard
local module = SUI:NewModule('Handler.SetupWizard') ---@type SUI.Module

local ADDON_ID = 'spartanui'
local BACKDROP_LOOKS = {
	War = true,
	Classic = true,
	Midnight = true,
	Fel = true,
	Arcane = true,
	Digital = true,
	Tribal = true,
	Minimal = true,
	Transparent = true,
	ModernFlat = true,
	HealerGrid = true,
	ClassicDark = true,
}

----------------------------------------------------------------------------------------------------
-- Backward compat stub: old modules calling SUI.Setup:AddPage() will silently no-op
----------------------------------------------------------------------------------------------------

---@param PageData table
function module:AddPage(PageData)
	-- No-op: old-style pages are no longer supported.
	-- Modules should add steps to SUI.Setup.registration instead.
end

----------------------------------------------------------------------------------------------------
-- Registration
----------------------------------------------------------------------------------------------------

function module:OnInitialize()
	if not LibAT or not LibAT.Setup then
		return
	end

	-- Asked once: a profile that has been through setup before (or predates it) is an existing user
	module.registration = LibAT.Setup:Register(ADDON_ID, {
		name = 'SpartanUI',
		icon = 'Interface\\AddOns\\SpartanUI\\images\\setup\\SUISetup',
		summary = L['Pick a look for your whole screen, your frames and your action bars.'],
		priority = 10,
		scope = 'account',
		-- The step list shows chapters; each module's steps join one here
		chapters = {
			welcome = L['Welcome'],
			profile = L['Welcome'],
			theme = L['Look'],
			['artwork-options'] = L['Look'],
			font = L['Look'],
			unitframes = L['Frames'],
			['uf-personal'] = L['Frames'],
			['uf-group'] = L['Frames'],
			actionbars = L['Action bars'],
			['actionbars-import'] = L['Action bars'],
			modules = L['Features'],
			autosell = L['Features'],
			questtools = L['Features'],
			minimap = L['Features'],
			tooltips = L['Features'],
			convenience = L['Features'],
			uienhancements = L['Features'],
			['other-addons'] = L['Other addons'],
		},
		isExistingUser = function()
			return not SUI.DB.SetupWizard.FirstLaunch
		end,
		profileKey = function()
			return SUI.SpartanUIDB:GetCurrentProfile()
		end,
		isNewProfile = function()
			return SUI.DB.SetupWizard.FirstLaunch
		end,
		optionsCommand = function()
			SUI.Options:OpenTo({})
		end,
	})
	if not module.registration then
		return
	end
	SUI.WindowKits:Register()

	-- Setup windows take the accent of the active SpartanUI theme, and repaint when it changes
	if LibAT.UI.SetAccentProvider then
		LibAT.UI.SetAccentProvider(function()
			return SUI.UI.Style:GetAccent()
		end)
	end
	if LibAT.UI.SetBackdropProvider then
		LibAT.UI.SetBackdropProvider(function()
			local style = SUI:GetActiveStyle()
			local entry = style and SUI.ThemeRegistry and SUI.ThemeRegistry:Get(style)
			local look = (entry and entry.variantGroup) or style
			if not look or not BACKDROP_LOOKS[look] then
				return nil
			end
			return 'Interface\\AddOns\\SpartanUI\\images\\setup\\backdrops\\' .. look .. '.png'
		end)
	end
	if LibAT.UI.SetKitProvider then
		LibAT.UI.SetKitProvider(function()
			return SUI.WindowKits:GetActiveId()
		end)
	end

	self:RegisterWelcomeSteps()
	self:RegisterOtherAddonsStep()
end

function module:OnEnable()
	if SUI.UI.Style and LibAT and LibAT.UI and LibAT.UI.NotifyAccentChanged then
		SUI.UI.Style:OnAccentChanged(module, function()
			LibAT.UI.NotifyAccentChanged()
		end)
	end
	if SUI.Event and LibAT and LibAT.UI and LibAT.UI.NotifyBackdropChanged then
		SUI.Event:RegisterEvent('ARTWORK_STYLE_CHANGED', function()
			LibAT.UI.NotifyBackdropChanged()
			if LibAT.UI.NotifyKitChanged then
				LibAT.UI.NotifyKitChanged()
			end
		end)
	end

	SUI:AddChatCommand('setup', function()
		module:Open()
	end, 'Open the setup wizard')
end

---Open SpartanUI's setup, at a step when given
---@param stepId? string
function module:Open(stepId)
	if LibAT and LibAT.Setup then
		LibAT.Setup:Open(ADDON_ID, stepId)
	end
end

----------------------------------------------------------------------------------------------------
-- Welcome: start fresh, or copy / share a profile
----------------------------------------------------------------------------------------------------

local welcomeMode = 'fresh'
local chosenProfile

---@param profileName string
---@return boolean
local function IsCharacterProfile(profileName)
	if not profileName:find(' %- ') then
		return false
	end
	local keys = SUI.SpartanUIDB.sv and SUI.SpartanUIDB.sv.profileKeys
	return keys ~= nil and keys[profileName] ~= nil
end

---Profiles the player can copy from or share, as value -> label
---@param forSharing boolean character profiles cannot be shared
---@return table<string, string>
function module:GetProfileChoices(forSharing)
	local current = SUI.SpartanUIDB:GetCurrentProfile()
	local list = {}
	local names = {}
	SUI.SpartanUIDB:GetProfiles(names)
	for _, name in pairs(names) do
		if name ~= current and not (forSharing and IsCharacterProfile(name)) then
			list[name] = name
		end
	end
	local keys = SUI.SpartanUIDB.keys
	for _, common in ipairs({ { 'Default', 'Default' }, { keys.realm, keys.realm }, { keys.class, (UnitClass('player')) } }) do
		if common[1] ~= current and not list[common[1]] then
			list[common[1]] = common[2]
		end
	end
	return list
end

function module:RegisterWelcomeSteps()
	local reg = module.registration

	reg:AddStep({
		id = 'welcome',
		kind = 'choice',
		name = L['Welcome'],
		title = L['Welcome to SpartanUI'],
		text = L['Start with a fresh setup, or bring your settings from another character. You can open this again any time with /setup.'],
		order = 10,
		scope = 'profile',
		choices = {
			{ value = 'fresh', title = L['Start fresh'], caption = L['Pick your look in the next steps.'], recommended = true },
			{ value = 'copy', title = L['Copy a profile'], caption = L['Copy the settings of another profile into this one.'] },
			{ value = 'share', title = L['Share a profile'], caption = L['Use one profile on several characters. Changes show up on all of them.'] },
		},
		get = function()
			return welcomeMode
		end,
		set = function(value, ctx)
			welcomeMode = value
			chosenProfile = nil
			ctx:CancelReload('profile')
			local values = module.registration:GetStep('profile').widgets.profile.values
			wipe(values)
			if value ~= 'fresh' then
				for key, label in pairs(module:GetProfileChoices(value == 'share')) do
					values[key] = label
				end
			end
		end,
		onLeave = function()
			module:OnLeaveWelcome(welcomeMode == 'fresh')
		end,
	})

	reg:AddStep({
		id = 'profile',
		kind = 'form',
		name = L['Profile'],
		title = L['Which profile?'],
		text = L['The change happens when you finish setup.'],
		order = 11,
		scope = 'profile',
		hidden = function()
			return welcomeMode == 'fresh'
		end,
		widgets = {
			profile = {
				type = 'dropdown',
				name = L['Profile'],
				order = 1,
				width = 260,
				values = {},
				get = function()
					return chosenProfile
				end,
				set = function(_, value)
					chosenProfile = value
				end,
			},
		},
		onLeave = function(ctx)
			if not chosenProfile then
				return
			end
			local profile, sharing = chosenProfile, welcomeMode == 'share'
			local label = (sharing and L['Share profile: %s'] or L['Copy profile: %s']):format(profile)
			ctx:NeedsReload('profile', label, function()
				module:HandleEditModeBeforeProfileChange(profile, sharing)
				if sharing then
					SUI.SpartanUIDB:SetProfile(profile)
				else
					SUI.SpartanUIDB:CopyProfile(profile)
				end
				module:HandleEditModeAfterProfileChange(profile, sharing)
			end)
		end,
	})
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

---Called when leaving the Welcome step
---@param fresh boolean the player starts fresh rather than copying or sharing a profile
function module:OnLeaveWelcome(fresh)
	SUI.DB.SetupWizard.FirstLaunch = false

	-- Create matching EditMode profile for new users (a copied or shared profile brings its own)
	if fresh and SUI.IsRetail and EditModeManagerFrame then
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

function module:RegisterOtherAddonsStep()
	module.registration:AddStep({
		id = 'other-addons',
		kind = 'custom',
		name = L['Other Addons'],
		title = L['Companion addons'],
		order = 90,
		build = function(contentFrame)
			self:BuildOtherAddonsPage(contentFrame)
		end,
	})
end

function module:BuildOtherAddonsPage(contentFrame)
	local UI = LibAT.UI

	local desc = UI.CreateLabel(contentFrame, 'These addons complement SpartanUI. Install them for additional features.', 'GameFontNormal')
	desc:SetPoint('TOP', contentFrame, 'TOP', 0, -5)
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
