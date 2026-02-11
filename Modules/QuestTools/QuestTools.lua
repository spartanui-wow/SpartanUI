local SUI, L = SUI, SUI.L
---@class SUI.Module.QuestTools : SUI.Module
local module = SUI:GetModule('QuestTools', true) or SUI:NewModule('QuestTools')
module.DisplayName = L['Quest Tools']
module.description = 'Auto accept and turn in quests with advanced management'
----------------------------------------------------------------------------------------------------

---@type SUI.Module.QuestTools.DB
local DB
---@type SUI.Module.QuestTools.GlobalDB
local GlobalDB

-- Frame for event handling
local EventFrame = CreateFrame('Frame')

-- Temporary blacklist for session-based blocking
local TempBlackList = {}

-- Reputation quests that require items
local Lquests = {
	-- Steamwheedle Cartel
	['Making Amends'] = { item = 'Runecloth', amount = 40, currency = false },
	['War at Sea'] = { item = 'Mageweave Cloth', amount = 40, currency = false },
	['Traitor to the Bloodsail'] = { item = 'Silk Cloth', amount = 40, currency = false },
	['Mending Old Wounds'] = { item = 'Linen Cloth', amount = 40, currency = false },
	-- Timbermaw Quests
	['Feathers for Grazle'] = { item = 'Deadwood Headdress Feather', amount = 5, currency = false },
	['Feathers for Nafien'] = { item = 'Deadwood Headdress Feather', amount = 5, currency = false },
	['More Beads for Salfa'] = { item = 'Winterfall Spirit Beads', amount = 5, currency = false },
	-- Cenarion
	['Encrypted Twilight Texts'] = { item = 'Encrypted Twilight Text', amount = 10, currency = false },
	['Still Believing'] = { item = 'Encrypted Twilight Text', amount = 10, currency = false },
	-- Thorium Brotherhood
	['Favor Amongst the Brotherhood, Blood of the Mountain'] = { item = 'Blood of the Mountain', amount = 1, currency = false },
	['Favor Amongst the Brotherhood, Core Leather'] = { item = 'Core Leather', amount = 2, currency = false },
	['Favor Amongst the Brotherhood, Dark Iron Ore'] = { item = 'Dark Iron Ore', amount = 10, currency = false },
	['Favor Amongst the Brotherhood, Fiery Core'] = { item = 'Fiery Core', amount = 1, currency = false },
	['Favor Amongst the Brotherhood, Lava Core'] = { item = 'Lava Core', amount = 1, currency = false },
	['Gaining Acceptance'] = { item = 'Dark Iron Residue', amount = 4, currency = false },
	['Gaining Even More Acceptance'] = { item = 'Dark Iron Residue', amount = 100, currency = false },
	-- Burning Crusade, Lower City
	['More Feathers'] = { item = 'Arakkoa Feather', amount = 30, currency = false },
	-- Aldor
	["More Marks of Kil'jaeden"] = { item = "Mark of Kil'jaeden", amount = 10, currency = false },
	['More Marks of Sargeras'] = { item = 'Mark of Sargeras', amount = 10, currency = false },
	['Fel Armaments'] = { item = 'Fel Armaments', amount = 10, currency = false },
	["Single Mark of Kil'jaeden"] = { item = "Mark of Kil'jaeden", amount = 1, currency = false },
	['Single Mark of Sargeras'] = { item = 'Mark of Sargeras', amount = 1, currency = false },
	['More Venom Sacs'] = { item = 'Dreadfang Venom Sac', amount = 8, currency = false },
	-- Scryer
	['More Firewing Signets'] = { item = 'Firewing Signet', amount = 10, currency = false },
	['More Sunfury Signets'] = { item = 'Sunfury Signet', amount = 10, currency = false },
	['Arcane Tomes'] = { item = 'Arcane Tome', amount = 1, currency = false },
	['Single Firewing Signet'] = { item = 'Firewing Signet', amount = 1, currency = false },
	['Single Sunfury Signet'] = { item = 'Sunfury Signet', amount = 1, currency = false },
	['More Basilisk Eyes'] = { item = 'Dampscale Basilisk Eye', amount = 8, currency = false },
	-- Skettis
	['More Shadow Dust'] = { item = 'Shadow Dust', amount = 6, currency = false },
	-- SporeGar
	['Bring Me Another Shrubbery!'] = { item = 'Sanguine Hibiscus', amount = 5, currency = false },
	['More Fertile Spores'] = { item = 'Fertile Spores', amount = 6, currency = false },
	['More Glowcaps'] = { item = 'Glowcap', amount = 10, currency = false },
	['More Spore Sacs'] = { item = 'Mature Spore Sac', amount = 10, currency = false },
	['More Tendrils!'] = { item = 'Bog Lord Tendril', amount = 6, currency = false },
	-- Halaa
	["Oshu'gun Crystal Powder"] = { item = "Oshu'gun Crystal Powder Sample", amount = 10, currency = false },
	["Hodir's Tribute"] = { item = 'Relic of Ulduar', amount = 10, currency = false },
	['Remember Everfrost!'] = { item = 'Everfrost Chip', amount = 1, currency = false },
	['Additional Armaments'] = { item = 416, amount = 125, currency = true },
	['Calling the Ancients'] = { item = 416, amount = 125, currency = true },
	['Filling the Moonwell'] = { item = 416, amount = 125, currency = true },
	['Into the Fire'] = { donotaccept = true },
	['The Forlorn Spire'] = { donotaccept = true },
	['Fun for the Little Ones'] = { item = 393, amount = 15, currency = true },
	-- MoP
	['Seeds of Fear'] = { item = 'Dread Amber Shards', amount = 5, currency = false },
	['A Dish for Jogu'] = { item = 'Sauteed Carrots', amount = 5, currency = false },
	['A Dish for Ella'] = { item = 'Shrimp Dumplings', amount = 5, currency = false },
	['Valley Stir Fry'] = { item = 'Valley Stir Fry', amount = 5, currency = false },
	['A Dish for Farmer Fung'] = { item = 'Wildfowl Roast', amount = 5, currency = false },
	['A Dish for Fish'] = { item = 'Twin Fish Platter', amount = 5, currency = false },
	['Swirling Mist Soup'] = { item = 'Swirling Mist Soup', amount = 5, currency = false },
	['A Dish for Haohan'] = { item = 'Charbroiled Tiger Steak', amount = 5, currency = false },
	['A Dish for Old Hillpaw'] = { item = 'Braised Turtle', amount = 5, currency = false },
	['A Dish for Sho'] = { item = 'Eternal Blossom Fish', amount = 5, currency = false },
	['A Dish for Tina'] = { item = 'Fire Spirit Salmon', amount = 5, currency = false },
	['Replenishing the Pantry'] = { item = 'Bundle of Groceries', amount = 1, currency = false },
	-- MoP Timeless Island
	['Great Turtle Meat'] = { item = 'Great Turtle Meat', amount = 1, currency = false },
	['Heavy Yak Flank'] = { item = 'Heavy Yak Flank', amount = 1, currency = false },
	['Meaty Crane Leg'] = { item = 'Meaty Crane Leg', amount = 1, currency = false },
	['Pristine Firestorm Egg'] = { item = 'Pristine Firestorm Egg', amount = 1, currency = false },
	['Thick Tiger Haunch'] = { item = 'Thick Tiger Haunch', amount = 1, currency = false },
}

-- Expose for sub-modules
module.Lquests = Lquests
module.TempBlackList = TempBlackList
module.EventFrame = EventFrame

local function debug(content)
	SUI.Log(content, 'QuestTools')
end
module.debug = debug

function module:GetDB()
	return DB
end

function module:GetGlobalDB()
	return GlobalDB
end

function module:GetItemAmount(isCurrency, item)
	local currency = C_CurrencyInfo.GetCurrencyInfo(item)
	local amount = isCurrency and (currency.quantity or C_Item.GetItemCount(item, nil, true))
	return amount and amount or 0
end

function module:OnInitialize()
	-- Register namespace first
	module.Database = SUI.SpartanUIDB:RegisterNamespace('QuestTools', { global = module.GlobalDBDefaults, profile = module.DBDefaults })
	DB = module.Database.profile
	GlobalDB = module.Database.global

	-- Register profile change callbacks
	module.Database.RegisterCallback(module, 'OnProfileChanged', function()
		DB = module.Database.profile
		GlobalDB = module.Database.global
		module.DB = DB
		module.GlobalDB = GlobalDB
	end)
	module.Database.RegisterCallback(module, 'OnProfileCopied', function()
		DB = module.Database.profile
		GlobalDB = module.Database.global
		module.DB = DB
		module.GlobalDB = GlobalDB
	end)
	module.Database.RegisterCallback(module, 'OnProfileReset', function()
		DB = module.Database.profile
		GlobalDB = module.Database.global
		module.DB = DB
		module.GlobalDB = GlobalDB
	end)

	-- Expose DB references
	module.DB = DB
	module.GlobalDB = GlobalDB

	-- Check for migration from AutoTurnIn (must happen after namespace registration)
	module:MigrateFromAutoTurnIn()
end

function module:MigrateFromAutoTurnIn()
	debug('MigrateFromAutoTurnIn: Starting migration check')

	-- Check if AutoTurnIn data exists in raw saved variables
	-- AceDB stores namespaces in SpartanUIDB.namespaces table
	local rawSV = SpartanUIDB and SpartanUIDB.namespaces and SpartanUIDB.namespaces.AutoTurnIn
	if not rawSV then
		debug('MigrateFromAutoTurnIn: No AutoTurnIn namespace found in saved variables')
		return
	end
	debug('MigrateFromAutoTurnIn: AutoTurnIn namespace exists in saved variables')

	-- Check if we've already migrated (QuestTools has non-default FirstLaunch)
	-- If QuestTools.FirstLaunch is false, migration was already done or user completed setup
	debug('MigrateFromAutoTurnIn: QuestTools DB.FirstLaunch = ' .. tostring(DB.FirstLaunch))
	if DB.FirstLaunch == false then
		debug('MigrateFromAutoTurnIn: QuestTools already set up, skipping migration')
		return
	end

	-- Check if AutoTurnIn was completed (FirstLaunch = false means setup was done)
	debug('MigrateFromAutoTurnIn: Checking AutoTurnIn profile data')
	debug('MigrateFromAutoTurnIn: rawSV.profiles exists = ' .. tostring(rawSV.profiles ~= nil))

	local currentProfile = SUI.SpartanUIDB:GetCurrentProfile()
	debug('MigrateFromAutoTurnIn: Current profile name = ' .. tostring(currentProfile))

	-- AutoTurnIn data is stored in profiles table keyed by profile name
	local autoProfile = rawSV.profiles and rawSV.profiles[currentProfile]

	if not autoProfile then
		debug('MigrateFromAutoTurnIn: No AutoTurnIn profile data found for current profile')
		-- Dump what we do have
		if rawSV.profiles then
			for k, v in pairs(rawSV.profiles) do
				debug('MigrateFromAutoTurnIn: rawSV.profiles has key: ' .. tostring(k))
			end
		end
		return
	end

	debug('MigrateFromAutoTurnIn: AutoTurnIn profile found')
	debug('MigrateFromAutoTurnIn: AutoTurnIn FirstLaunch = ' .. tostring(autoProfile.FirstLaunch))

	-- Only migrate if AutoTurnIn setup was completed
	if autoProfile.FirstLaunch == false then
		SUI:Print('Migrating AutoTurnIn settings to QuestTools...')

		-- Copy all compatible settings from AutoTurnIn to QuestTools
		local settingsToMigrate = {
			'ChatText',
			'FirstLaunch',
			'debug',
			'TurnInEnabled',
			'AutoGossip',
			'AutoGossipSafeMode',
			'AcceptGeneralQuests',
			'DoCampainQuests',
			'AcceptRepeatable',
			'trivial',
			'lootreward',
			'autoequip',
			'armor',
			'weapon',
			'stat',
			'secondary',
			'useGlobalDB',
			'Blacklist',
			'Whitelist',
		}

		for _, key in ipairs(settingsToMigrate) do
			if autoProfile[key] ~= nil then
				debug('MigrateFromAutoTurnIn: Copying ' .. key .. ' = ' .. tostring(autoProfile[key]))
				DB[key] = autoProfile[key]
			end
		end

		-- Also migrate global settings if they exist
		local autoGlobal = rawSV.global
		if autoGlobal then
			debug('MigrateFromAutoTurnIn: Found global settings')
			if autoGlobal.Blacklist then
				GlobalDB.Blacklist = autoGlobal.Blacklist
				debug('MigrateFromAutoTurnIn: Migrated global Blacklist')
			end
			if autoGlobal.Whitelist then
				GlobalDB.Whitelist = autoGlobal.Whitelist
				debug('MigrateFromAutoTurnIn: Migrated global Whitelist')
			end
		end

		SUI:Print('AutoTurnIn settings migrated to QuestTools successfully')
		debug('MigrateFromAutoTurnIn: Migration complete, DB.FirstLaunch = ' .. tostring(DB.FirstLaunch))
	else
		debug('MigrateFromAutoTurnIn: AutoTurnIn FirstLaunch is not false, not migrating')
	end

	-- Migrate enabled/disabled state
	if SUI.DB and SUI.DB.DisabledModules then
		local disabled = SUI.DB.DisabledModules
		if disabled.AutoTurnIn ~= nil and disabled.QuestTools == nil then
			disabled.QuestTools = disabled.AutoTurnIn
			SUI:Print('Migrated AutoTurnIn enabled state to QuestTools')
		end
	end
end

function module:OnEnable()
	debug('QuestTools Loaded')

	if SUI:IsModuleDisabled(module) then
		return
	end

	-- Initialize sub-modules
	module:InitializeBlacklist()
	module:InitializeGossipHandler()
	module:InitializeAutoAccept()
	module:InitializeAutoTurnIn()
	module:InitializeRewardSelection()

	-- Build options and first launch
	module:BuildOptions()
	module:FirstLaunch()

	-- Register events
	local lastEvent = ''
	local function OnEvent(_, event)
		if SUI:IsModuleDisabled(module) then
			return
		end
		debug(event)
		lastEvent = event

		local QuestID = GetQuestID()
		if QuestID ~= 0 and C_CampaignInfo then
			local CampaignId = C_CampaignInfo.GetCampaignID(QuestID)
			debug(C_CampaignInfo.GetCurrentChapterID(CampaignId))
			debug(C_CampaignInfo.IsCampaignQuest(QuestID))
			if C_CampaignInfo.IsCampaignQuest(QuestID) and not DB.DoCampainQuests and C_CampaignInfo.GetCurrentChapterID(CampaignId) ~= nil then
				SUI:Print(L['Current quest is a campaign quest, pausing QuestTools'])
				return
			end
		end

		if IsAltKeyDown() then
			SUI:Print('Override key held, QuestTools disabled')
			module:CancelAllTimers()
			return
		end

		if IsControlKeyDown() then
			if event == 'GOSSIP_SHOW' or event == 'QUEST_GREETING' then
				SUI:Print('Quest Blacklist key held, select the quest to blacklist')
			elseif event == 'QUEST_DETAIL' or event == 'QUEST_PROGRESS' then
				if module.Blacklist.isBlacklisted(QuestID) then
					SUI:Print('Quest "' .. GetTitleText() .. '" is already blacklisted')
				else
					SUI:Print('Blacklisting quest "' .. GetTitleText() .. '" ID# ' .. QuestID)
					module.Blacklist.Add(QuestID, 'QuestIDs')
					module:RefreshBlacklistUI()
				end
			end
			module:CancelAllTimers()
			return
		end

		-- Dispatch to appropriate handler
		if event == 'GOSSIP_SHOW' then
			module:HandleGossipShow()
		elseif event == 'QUEST_DETAIL' then
			module:HandleQuestDetail()
		elseif event == 'QUEST_GREETING' then
			module:HandleQuestGreeting()
		elseif event == 'QUEST_PROGRESS' then
			module:HandleQuestProgress()
		elseif event == 'QUEST_COMPLETE' then
			module:HandleQuestComplete()
		elseif event == 'MERCHANT_SHOW' then
			module.IsMerchantOpen = true
		elseif event == 'MERCHANT_CLOSED' then
			module.IsMerchantOpen = false
		end
	end

	EventFrame:SetScript('OnEvent', OnEvent)
	EventFrame:RegisterEvent('GOSSIP_SHOW')
	EventFrame:RegisterEvent('QUEST_DETAIL')
	EventFrame:RegisterEvent('QUEST_GREETING')
	EventFrame:RegisterEvent('QUEST_PROGRESS')
	EventFrame:RegisterEvent('QUEST_COMPLETE')
	EventFrame:RegisterEvent('MERCHANT_SHOW')
	EventFrame:RegisterEvent('MERCHANT_CLOSED')

	-- Create quest frame panels
	module:CreateQuestFramePanels()
end

function module:OnDisable()
	EventFrame:UnregisterEvent('GOSSIP_SHOW')
	EventFrame:UnregisterEvent('QUEST_DETAIL')
	EventFrame:UnregisterEvent('QUEST_GREETING')
	EventFrame:UnregisterEvent('QUEST_PROGRESS')
	EventFrame:UnregisterEvent('QUEST_COMPLETE')
	EventFrame:UnregisterEvent('MERCHANT_SHOW')
	EventFrame:UnregisterEvent('MERCHANT_CLOSED')

	-- Hide quest panels
	if module.QuestPanels then
		for _, panel in pairs(module.QuestPanels) do
			if panel then
				panel:Hide()
				if panel.Panel then
					panel.Panel:Hide()
				end
			end
		end
	end
end

function module:CreateQuestFramePanels()
	if not module.QuestPanels then
		module.QuestPanels = {}
	end

	local IsCollapsed = true
	local UI = LibAT.UI

	for _, v in ipairs({ 'QuestFrame', 'GossipFrame' }) do
		local OptionsPopdown = CreateFrame('Frame', nil, _G[v], BackdropTemplateMixin and 'BackdropTemplate')
		OptionsPopdown:SetSize(330, 20)
		OptionsPopdown:SetBackdrop({
			bgFile = 'Interface\\Buttons\\WHITE8X8',
			edgeFile = 'Interface\\Buttons\\WHITE8X8',
			edgeSize = 1,
		})
		OptionsPopdown:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
		OptionsPopdown:SetBackdropBorderColor(0, 0, 0, 1)
		OptionsPopdown:SetScale(0.95)
		OptionsPopdown:SetPoint('TOP', _G[v], 'BOTTOM', 0, -2)
		OptionsPopdown.title = UI.CreateLabel(OptionsPopdown, '|cffffffffSpartan|cffe21f1fUI|r Quest Tools', 'GameFontNormal')
		OptionsPopdown.title:SetPoint('CENTER')

		OptionsPopdown.minimizeButton = UI.CreateButton(OptionsPopdown, 15, 15, '-')
		OptionsPopdown.minimizeButton:SetPoint('RIGHT', OptionsPopdown, 'RIGHT', -5, 0)

		OptionsPopdown.minimizeButton:SetScript('OnClick', function()
			if OptionsPopdown.Panel:IsVisible() then
				OptionsPopdown.Panel:Hide()
				IsCollapsed = true
			else
				OptionsPopdown.Panel:Show()
				IsCollapsed = false
			end
		end)
		OptionsPopdown:HookScript('OnShow', function()
			if IsCollapsed then
				OptionsPopdown.Panel:Hide()
			else
				OptionsPopdown.Panel:Show()
			end
		end)

		local Panel = CreateFrame('Frame', nil, OptionsPopdown, BackdropTemplateMixin and 'BackdropTemplate')
		Panel:SetSize(OptionsPopdown:GetWidth(), 62)
		Panel:SetBackdrop({
			bgFile = 'Interface\\Buttons\\WHITE8X8',
			edgeFile = 'Interface\\Buttons\\WHITE8X8',
			edgeSize = 1,
		})
		Panel:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
		Panel:SetBackdropBorderColor(0, 0, 0, 1)
		Panel:SetPoint('TOP', OptionsPopdown, 'BOTTOM', 0, -1)
		Panel:Hide()

		local options = {}
		options.DoCampainQuests = UI.CreateCheckbox(Panel, L['Accept/Complete Campaign Quests'], 200, 20)
		options.AcceptGeneralQuests = UI.CreateCheckbox(Panel, L['Accept quests'], 120, 20)
		options.TurnInEnabled = UI.CreateCheckbox(Panel, L['Turn in completed quests'], 160, 20)
		options.AutoGossip = UI.CreateCheckbox(Panel, L['Auto gossip'], 120, 20)
		options.AutoGossipSafeMode = UI.CreateCheckbox(Panel, L['Auto gossip safe mode'], 160, 20)

		for setting, Checkbox in pairs(options) do
			Checkbox:SetChecked(DB[setting])
			Checkbox:HookScript('OnClick', function()
				DB[setting] = Checkbox:GetChecked()
			end)
		end

		options.DoCampainQuests:SetPoint('TOPLEFT', Panel, 'TOPLEFT', 5, -2)
		options.AcceptGeneralQuests:SetPoint('TOPLEFT', options.DoCampainQuests, 'BOTTOMLEFT', 0, 2)
		options.TurnInEnabled:SetPoint('LEFT', options.AcceptGeneralQuests, 'RIGHT', 5, 0)
		options.AutoGossip:SetPoint('TOPLEFT', options.AcceptGeneralQuests, 'BOTTOMLEFT', 0, 2)
		options.AutoGossipSafeMode:SetPoint('LEFT', options.AutoGossip, 'RIGHT', 5, 0)

		OptionsPopdown.Panel = Panel
		OptionsPopdown.Panel.options = options

		module.QuestPanels[v] = OptionsPopdown
	end
end

function module:FirstLaunch()
	local PageData = {
		ID = 'QuestTools',
		Name = L['Quest Tools'],
		SubTitle = L['Quest Tools'],
		Desc1 = L['Automatically accept and turn in quests.'],
		Desc2 = L['Holding ALT while talking to a NPC will temporarily disable the auto turnin module.'],
		RequireDisplay = DB.FirstLaunch,
		Display = function()
			local SUI_Win = SUI.Setup.window.content
			local UI = LibAT.UI

			local ATI = CreateFrame('Frame', nil)
			ATI:SetParent(SUI_Win)
			ATI:SetAllPoints(SUI_Win)

			if SUI:IsModuleDisabled('QuestTools') then
				ATI.lblDisabled = UI.CreateLabel(ATI, 'Disabled', 'GameFontNormalLarge')
				ATI.lblDisabled:SetPoint('CENTER', ATI)
			else
				ATI.options = {}
				ATI.options.AcceptGeneralQuests = UI.CreateCheckbox(ATI, L['Accept quests'], 220, 20)
				ATI.options.TurnInEnabled = UI.CreateCheckbox(ATI, L['Turn in completed quests'], 220, 20)
				ATI.options.AutoGossip = UI.CreateCheckbox(ATI, L['Auto gossip'], 220, 20)
				ATI.options.AutoGossipSafeMode = UI.CreateCheckbox(ATI, L['Auto gossip safe mode'], 220, 20)
				ATI.options.autoequip = UI.CreateCheckbox(ATI, L['Auto equip upgrade quest rewards'] .. ' - ' .. L['Based on iLVL'], 400, 20)

				if SUI.IsRetail then
					ATI.options.lootreward = UI.CreateCheckbox(ATI, L['Auto select quest reward'], 220, 20)
					ATI.options.DoCampainQuests = UI.CreateCheckbox(ATI, L['Accept/Complete Campaign Quests'], 220, 20)
				end

				local col1X, col2X = -150, 50
				local startY = -20
				local rowHeight = 25

				ATI.options.AcceptGeneralQuests:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X, startY)
				ATI.options.AutoGossip:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X, startY - rowHeight)
				ATI.options.AutoGossipSafeMode:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X, startY - (rowHeight * 2))

				ATI.options.TurnInEnabled:SetPoint('TOPLEFT', SUI_Win, 'TOP', col2X, startY)

				if SUI.IsRetail then
					ATI.options.lootreward:SetPoint('TOPLEFT', SUI_Win, 'TOP', col2X, startY - rowHeight)
					ATI.options.DoCampainQuests:SetPoint('TOPLEFT', SUI_Win, 'TOP', col2X, startY - (rowHeight * 2))
					ATI.options.autoequip:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X, startY - (rowHeight * 3))
				else
					ATI.options.autoequip:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X, startY - (rowHeight * 3))
				end

				for key, object in pairs(ATI.options) do
					object:SetChecked(DB[key])
				end
			end
			SUI_Win.QuestTools = ATI
		end,
		Next = function()
			if SUI:IsModuleEnabled('QuestTools') then
				local window = SUI.Setup.window
				local ATI = window.content.QuestTools

				for key, object in pairs(ATI.options) do
					DB[key] = object:GetChecked()
				end
			end
			DB.FirstLaunch = false
		end,
		Skip = function()
			DB.FirstLaunch = false
		end,
	}
	SUI.Setup:AddPage(PageData)
end
