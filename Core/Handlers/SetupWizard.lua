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

	-- A profile setup has never seen: helpers show their recommended state there
	module.freshProfile = SUI.DB.SetupWizard.FirstLaunch == true

	-- Asked once: a profile that has been through setup before (or predates it) is an existing user
	module.registration = LibAT.Setup:Register(ADDON_ID, {
		name = 'SpartanUI',
		-- The name in its own colors, where a window has room for it (What's new)
		brand = '|cffffffffSpartan|cffe21f1fUI|r',
		icon = 'Interface\\AddOns\\SpartanUI\\images\\Menu\\SUILogo_white.png',
		summary = L['Pick a look for your whole screen, your frames and your action bars.'],
		priority = 10,
		scope = 'account',
		-- The step list shows chapters; each module's steps join one here
		chapters = {
			welcome = L['Welcome'],
			conflicts = L['Conflicts'],
			theme = L['Look'],
			unitframes = L['Look'],
			['artwork-options'] = L['Look'],
			actionbars = L['Action bars'],
			helpers = L['Helpers'],
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
		finish = {
			note = L['Open settings any time: type /sui, or press Esc and click SpartanUI. /setup brings this window back.'],
			links = {
				{
					title = L['Frame sizes'],
					caption = L['Width and bar heights for every frame'],
					onClick = function()
						SUI.Options:OpenTo({ 'UnitFrames' })
					end,
				},
				{
					title = L['Minimap'],
					caption = L['Shape, size, clock and addon buttons'],
					onClick = function()
						SUI.Options:OpenTo({ 'Modules', 'Minimap' })
					end,
				},
				{
					title = L['Tooltips'],
					caption = L['Colors, spell IDs and vendor prices'],
					onClick = function()
						SUI.Options:OpenTo({ 'Modules', 'Tooltips' })
					end,
				},
				{
					title = L['Mouse and cursor'],
					caption = L['A ring or a trail around your cursor'],
					onClick = function()
						SUI.Options:OpenTo({ 'Modules', 'UIEnhancements' })
					end,
				},
				{
					title = L['All features'],
					caption = L['Turn any SpartanUI feature on or off'],
					onClick = function()
						SUI.Options:OpenTo({ 'Modules' })
					end,
				},
				{
					title = L['Move frames'],
					caption = L['Drag anything on your screen where you want it'],
					action = L['Start'],
					onClick = function()
						if SUI.MoveIt and SUI.MoveIt.MoverMode then
							SUI.MoveIt.MoverMode:Toggle()
						end
					end,
				},
			},
		},
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
	self:RegisterConflictsStep()
	self:RegisterHelpersStep()
end

function module:OnEnable()
	module:WatchFirstUse()
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

---Is the player setting up this profile from scratch (not copying or sharing another)?
---@return boolean
function module:IsStartingFresh()
	return welcomeMode == 'fresh' or chosenProfile == nil
end

---Does any profile other than the current one exist?
---@return boolean
function module:HasOtherProfiles()
	local current = SUI.SpartanUIDB:GetCurrentProfile()
	local names = {}
	SUI.SpartanUIDB:GetProfiles(names)
	for _, name in pairs(names) do
		if name ~= current then
			return true
		end
	end
	return false
end

---How many characters use a profile, and which SpartanUI version it was last used with
---@param profileName string
---@return string caption
---@return number characters
local function ProfileCaption(profileName)
	local sv = SUI.SpartanUIDB.sv
	local count = 0
	for _, used in pairs(sv and sv.profileKeys or {}) do
		if used == profileName then
			count = count + 1
		end
	end
	local parts = {}
	if count == 1 then
		parts[#parts + 1] = L['Used by 1 character']
	elseif count > 1 then
		parts[#parts + 1] = (L['Used by %d characters']):format(count)
	end
	local data = sv and sv.profiles and sv.profiles[profileName]
	if data and data.Version and data.Version ~= '' then
		parts[#parts + 1] = (L['Last used with SpartanUI %s']):format(tostring(data.Version))
	end
	if #parts == 0 then
		return L['Not used yet'], count
	end
	return table.concat(parts, '. '), count
end

---The profile cards for the copy or share choice: setups in use first (most characters first),
---then the rest by name
---@return table[]
local function ProfileCards()
	local cards = {}
	for key, label in pairs(module:GetProfileChoices(welcomeMode == 'share')) do
		local caption, count = ProfileCaption(key)
		cards[#cards + 1] = { value = key, title = label, caption = caption, characters = count }
	end
	table.sort(cards, function(a, b)
		if a.characters ~= b.characters then
			return a.characters > b.characters
		end
		return a.title < b.title
	end)
	return cards
end

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

----------------------------------------------------------------------------------------------------
-- Conflicts: parts of SpartanUI that stay off because another addon does the same job
----------------------------------------------------------------------------------------------------

local conflictChoice = {} ---@type table<string, boolean>

---An addon's name as its list shows it, without color codes or icons
---@param addon string
---@return string
local function AddonTitle(addon)
	local title = C_AddOns.GetAddOnMetadata(addon, 'Title') or addon
	title = title:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', ''):gsub('|T.-|t', ''):gsub('^%s+', ''):gsub('%s+$', '')
	return title ~= '' and title or addon
end

---@param addons string[]
---@return string
local function AddonList(addons)
	local titles = {}
	for i, addon in ipairs(addons) do
		titles[i] = AddonTitle(addon)
	end
	return table.concat(titles, ', ')
end

---SpartanUI parts that step aside for another addon the player has on, by name. A part the player
---turned off themselves is not a conflict.
---@return {name: string, module: table, addons: string[]}[]
function module:GetConflicts()
	local list = {}
	local disabled = SUI.DB.DisabledModules or {}
	for name, submodule in SUI:IterateModules() do
		if submodule.ConflictsWith and not disabled[name] then
			local addons = SUI:GetModuleConflicts(submodule)
			if #addons > 0 then
				list[#list + 1] = { name = name, module = submodule, addons = addons }
			end
		end
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

---How many addons in all overlap with a part of SpartanUI
---@return number
local function ConflictAddonCount()
	local count = 0
	for _, conflict in ipairs(module:GetConflicts()) do
		count = count + #conflict.addons
	end
	return count
end

function module:RegisterConflictsStep()
	local reg = module.registration
	local byName = {}

	reg:AddStep({
		id = 'conflicts',
		kind = 'toggles',
		name = L['Conflicts'],
		title = L['Detected conflicts'],
		text = L['These addons do the same job as part of SpartanUI. Only one can run, so that part of SpartanUI stays off. Keep your addon, or switch it off and use SpartanUI.'],
		order = 15,
		scope = 'profile',
		noBulk = true,
		hidden = function()
			return #module:GetConflicts() == 0
		end,
		groups = function()
			local items = {}
			wipe(byName)
			for _, conflict in ipairs(module:GetConflicts()) do
				local display = conflict.module.DisplayName or conflict.name
				local addons = AddonList(conflict.addons)
				byName[conflict.name] = { display = display, addons = addons, list = conflict.addons }
				items[#items + 1] = {
					key = conflict.name,
					title = (L["Use SpartanUI's %s"]):format(display),
					caption = (L['%s is on, so this part of SpartanUI is off. Turn this on to switch %s off for this character.']):format(addons, addons),
				}
			end
			return { { items = items } }
		end,
		get = function(key)
			return conflictChoice[key] == true
		end,
		set = function(key, value, ctx)
			conflictChoice[key] = value and true or nil
			local info = byName[key]
			if not ctx or not info then
				return
			end
			if value then
				ctx:NeedsReload('conflict:' .. key, (L["Turn off %s and use SpartanUI's %s"]):format(info.addons, info.display), function()
					local character = UnitName('player')
					for _, addon in ipairs(info.list) do
						C_AddOns.DisableAddOn(addon, character)
					end
					-- Saved now, so the game's addon list cannot throw the change away
					if C_AddOns.SaveAddOns then
						C_AddOns.SaveAddOns()
					end
				end)
			else
				ctx:CancelReload('conflict:' .. key)
			end
		end,
		summary = function()
			local picked = {}
			for key, on in pairs(conflictChoice) do
				if on and byName[key] then
					picked[#picked + 1] = byName[key].display
				end
			end
			if #picked == 0 then
				return nil
			end
			table.sort(picked)
			return (L['Switching to SpartanUI: %s']):format(table.concat(picked, ', '))
		end,
	})
end

function module:RegisterWelcomeSteps()
	local reg = module.registration

	reg:AddStep({
		id = 'welcome',
		kind = 'choice',
		name = L['Welcome'],
		title = L['Welcome to SpartanUI'],
		text = L['Start fresh, or use the setup from another character. A copied or shared setup is ready right away.'],
		order = 10,
		scope = 'profile',
		-- Nothing to copy or share on a first install: setup opens on the look
		hidden = function()
			return not module:HasOtherProfiles()
		end,
		-- A fresh start runs SpartanUI's own parts, so point out the ones another addon is keeping off
		banner = function()
			if welcomeMode ~= 'fresh' then
				return nil
			end
			local count = ConflictAddonCount()
			if count == 0 then
				return nil
			end
			return {
				title = count == 1 and L['1 of your addons does the same job as part of SpartanUI'] or (L['%d of your addons do the same job as parts of SpartanUI']):format(count),
				text = L['Those parts stay off while your addons run. Click to choose which to keep.'],
				step = 'conflicts',
			}
		end,
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
		end,
		-- On the final page only a copied or shared profile is worth a line
		summary = function()
			if welcomeMode ~= 'fresh' and chosenProfile then
				return (welcomeMode == 'share' and L['Shared with %s'] or L['Copy of %s']):format(chosenProfile)
			end
		end,
		-- A copied or shared setup already has everything: Next applies it and reloads
		finishNow = function()
			if welcomeMode ~= 'fresh' and chosenProfile then
				return welcomeMode == 'share' and L['Share and reload'] or L['Copy and reload']
			end
		end,
		-- Copy and share list the profiles right under the pick
		follow = {
			title = function()
				return welcomeMode == 'share' and L['Share which setup?'] or L['Copy which setup?']
			end,
			shown = function()
				return welcomeMode ~= 'fresh'
			end,
			choices = ProfileCards,
			get = function()
				return chosenProfile
			end,
			set = function(value, ctx)
				chosenProfile = value
				local profile, sharing = value, welcomeMode == 'share'
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
		},
		-- Closing the window (or the game closing it) is not passing the welcome
		onLeave = function(ctx)
			if ctx and ctx.closing then
				return
			end
			module:OnLeaveWelcome(welcomeMode == 'fresh')
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
	module.welcomeDone = true
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

---The first step that runs does the welcome work, even when the welcome page itself was hidden
function module:EnsureWelcomeDone()
	if not module.welcomeDone then
		module:OnLeaveWelcome(welcomeMode == 'fresh')
	end
end

----------------------------------------------------------------------------------------------------
-- Helpers: one page for every feature that acts on its own while the player plays
----------------------------------------------------------------------------------------------------

local HELPER_GROUPS = {
	{ id = 'selling', title = 'Selling and repairs' },
	{ id = 'quests', title = 'Quests' },
	{ id = 'messages', title = 'Messages' },
	{ id = 'groups', title = 'Groups' },
}
local helperItems = {} ---@type table<string, table[]>
local helperByKey = {} ---@type table<string, table>
local helperChoice = {} ---@type table<string, boolean>

---Add switches to the Helpers page. Each item: key, title, caption, recommended, get(), set(value),
---and module (the SpartanUI module the switch needs; it is turned on when the switch is).
---@param groupId 'selling'|'quests'|'messages'|'groups'
---@param items table[]
function module:AddHelpers(groupId, items)
	helperItems[groupId] = helperItems[groupId] or {}
	for _, item in ipairs(items) do
		if not helperByKey[item.key] then
			helperByKey[item.key] = item
			table.insert(helperItems[groupId], item)
		end
	end
end

---What a switch shows: the player's pick this run, the recommended state on a new profile, else the setting
---@param item table
---@return boolean
local function HelperValue(item)
	if helperChoice[item.key] ~= nil then
		return helperChoice[item.key]
	end
	if module.freshProfile then
		return item.recommended == true
	end
	local ok, value = pcall(item.get)
	return ok and value and true or false
end

---@param item table
---@param value boolean
local function ApplyHelper(item, value)
	if value and item.module and SUI:IsModuleDisabled(item.module) then
		SUI:EnableModule(item.module)
	end
	local ok, err = pcall(item.set, value)
	if not ok and SUI.logger and SUI.logger.error then
		SUI.logger.error('Setup helper ' .. item.key .. ' failed: ' .. tostring(err))
	end
end

----------------------------------------------------------------------------------------------------
-- Ask once, when it first matters: a helper the player left off is offered the first time it
-- would have done something (first vendor, first quest, first whisper, first summon)
----------------------------------------------------------------------------------------------------

local FIRST_USE = {
	MERCHANT_SHOW = { helper = 'autosell:Gray', ask = 'Sell gray junk for you?' },
	QUEST_DETAIL = { helper = 'questtools:accept', ask = 'Accept and turn in quests for you?' },
	CHAT_MSG_WHISPER = { helper = 'messenger:whispers', ask = 'Keep whispers as conversations in Messenger?' },
	CONFIRM_SUMMON = { helper = 'convenience:autoAcceptSummon', ask = 'Accept summons for you?' },
}

---@param event string
local function AskOnce(event)
	local trigger = FIRST_USE[event]
	local item = trigger and helperByKey[trigger.helper]
	local hub = LibAT and LibAT.Setup and LibAT.Setup.Hub
	if not item or not hub or SUI.DB.SetupWizard.FirstLaunch or InCombatLockdown() then
		return
	end
	local asked = SUI.DB.SetupWizard.Asked or {}
	SUI.DB.SetupWizard.Asked = asked
	if asked[trigger.helper] then
		return
	end
	local ok, on = pcall(item.get)
	if not ok or on then
		return
	end
	asked[trigger.helper] = true
	local text = L[trigger.ask] .. ' ' .. (item.caption or '') .. ' ' .. L['You can change this later in /sui.']
	hub:ShowToast(text, L['Turn on'], function()
		helperChoice[item.key] = true
		ApplyHelper(item, true)
	end, { duration = 30 })
end

function module:WatchFirstUse()
	if module.firstUseWatcher then
		return
	end
	local watcher = CreateFrame('Frame')
	for event in pairs(FIRST_USE) do
		watcher:RegisterEvent(event)
	end
	watcher:SetScript('OnEvent', function(_, event)
		AskOnce(event)
	end)
	module.firstUseWatcher = watcher
end

function module:RegisterHelpersStep()
	module.registration:AddStep({
		id = 'helpers',
		kind = 'toggles',
		name = L['Helpers'],
		title = L['What should SpartanUI do for you?'],
		text = L['These act on their own while you play, so each one says what it will do. Turn on only what you want; change them any time in /sui.'],
		order = 50,
		scope = 'profile',
		noBulk = true,
		hidden = function()
			return not module:IsStartingFresh() or next(helperByKey) == nil
		end,
		groups = function()
			local groups = {}
			for _, group in ipairs(HELPER_GROUPS) do
				local items = helperItems[group.id]
				if items and #items > 0 then
					groups[#groups + 1] = { title = L[group.title], items = items }
				end
			end
			return groups
		end,
		get = function(key)
			local item = helperByKey[key]
			return item ~= nil and HelperValue(item)
		end,
		set = function(key, value)
			local item = helperByKey[key]
			if item then
				helperChoice[key] = value and true or false
				ApplyHelper(item, value and true or false)
			end
		end,
		-- A new profile keeps the recommended switches the player saw, even untouched ones
		onLeave = function(ctx)
			if (ctx and ctx.closing) or not module.freshProfile then
				return
			end
			for key, item in pairs(helperByKey) do
				if helperChoice[key] == nil then
					helperChoice[key] = item.recommended == true
					ApplyHelper(item, helperChoice[key])
				end
			end
		end,
	})
end

SUI.Setup = module
