local SUI, L = SUI, SUI.L
---@class SUI.Module.AutoTurnIn : SUI.Module
local module = SUI:NewModule('AutoTurnIn')
module.DisplayName = L['Auto turn in']
module.description = 'Auto accept and turn in quests'
----------------------------------------------------------------------------------------------------
local DB ---@type AutoTurnInDB
local GlobalDB ---@type AutoTurnInGlobalDB
local Blacklist = {
	QuestIDs = {},
	Gossip = {
		-- General Blacklist
		'Send me into the Black Temple.',
		'what do you have for me?',
		'show me your offerings.',
		'What is the Superbloom?',
		'i wish to buy from you.',
		'i would like to buy from you.',
		'make this inn your home.',
		"i'd like to heal and revive my battle pets.",
		'let me browse your goods.',
		"i'm looking for a lost companion.",
		'i need a ride to the top of the statue.',
		'show me what you have available.',
		'flight master',
		'guild master & vendor',
		'void storage',
		'auction house',
		'stable master',
		'zeppelin master',
		'other continents',
		"officer's lounge",
		'transmogrification',
		'i want to transmogrify my gear.',
		'The Enclave',
		'Bank',
		'Appearance Agitator',
		'Portal to Orgrimmar',
		'Inn',
		'Master of Conflict',
		'Mailbox',
		'Item Upgrade',
		'Item Upgrades',
		'Points of Interest',
		'Barber',
		'Rostrum of Transformation',
		'Crafting Orders',
		'Transmogrifier',
		-- wotlk blacklist
		'i am prepared to face saragosa!',
		'what is the cause of this conflict?',
		'can you spare a drake to take me to lord afrasastrasz in the middle of the temple?',
		'i must return to the world of shadows, koltira. send me back.',
		'i am ready to be teleported to dalaran.',
		'can i get a ride back to ground level, lord afrasastrasz?',
		'i would like to go to lord afrasastrasz in the middle of the temple.',
		'my lord, i need to get to the top of the temple.',
		'yes, please, i would like to return to the ground level of the temple.',
		"steward, please allow me to ride one of the drakes to the queen's chamber at the top of the temple.",
		'i want to exchange my ruby essence for amber essence.',
		'what abilities do ruby drakes have?',
		'i want to fly on the wings of the bronze flight.',
		'i want to fly on the wings of the red flight.',
		'i want to exchange my ruby essence for emerald essence.',
		'what abilities do emerald drakes have?',
		'i want to fly on the wings of the green flight.',
		'i want to exchange my amber essence for ruby essence.',
		'what abilities do amber drakes have?',
		'i am ready.', -- this one is used alot but blacklisted due to trial of the champion
		"i am ready.  however, i'd like to skip the pageantry.",
		-- mop
		"i'm ready to be introduced to the instructors, high elder.",
		"fine. let's proceed with the introductions.",
		'what is this place?',
		-- legion
		'your people treat you with contempt. why? what did you do?',
		-- bfa
		"yes, i'm ready to go to drustvar.",
		'warchief, may i ask why we want to capture teldrassil?',
		'i am ready to go to the undercity.',
		"i've heard this tale before... <skip the scenario and begin your next mission.>",
		'release me.',
		--- Shadowlands
		"Witness the Jailer's defeat.",
		'What is the Purpose?',
		'I am ready to choose my fate in the Shadowlands.',
		'What adventures await me if i join your covenant?',
		'Show me how I can help the Shadowlands.',
		'What are you offering here?',
		--DF
	},
	Wildcard = {
		'wartime donation',
		'where do i stand',
		'how do i',
		'work order',
		'supplies needed',
		'like to build',
		'taxi',
		'trade',
		'train',
		'trainer',
		'repeat',
		'buy',
		'browse your',
		'my home',
		'reinforcements',
		'Set sail',
		'drustvar',
		'stormsong valley',
		'tiragarde sound',
		'tell me about the',
		'like to change',
		'goods',
		'take us back',
		'take me back',
		'and listen',
		'where I can fly',
		'seal of wartorn',
		'Threads of Fate',
		'What are the strengths of the',
		'covenant abilities again',
		'could you please reset the cooldown on my ability',
		'your home',
		'this inn',
		'what you have on offer',
		"i'd like to try the",
	},
}
local Whitelist = {
	Gossip = {
		-- TWW
		'Your general asked me to spar with you.',
		-- MISC
		'Evacuate, now!',
		"I've cleared a path for you. You should leave.",
		'If you insist. The show must go on!',
		'Will you spar with me?',
		'I would like to challenge both of you to a spar.',
		'<Request tithe>',
		--DF
		'We need explorers for an expedition to the Dragon Isles. Will you join us?',
		'We need artisans for an expedition to the Dragon Isles. Will you join us?',
		'We need scholars for an expedition to the Dragon Isles. Will you join us?',
		'<Ask Khadgar what happened.>',
		'Scalecommander Cindrethresh would like you to meet her at the zeppelin tower.',
		"Tell me of the Neltharion's downfall.",
		'Tell me of the Dawn of the Aspects.',
		"I'm here to test your combat skills.",
		--Event
		'Begin the battle.',
	},
}
---@class AutoTurnInGlobalDB
local GlobalDBDefaults = {
	Blacklist = Blacklist,
	Whitelist = Whitelist,
}
---@class AutoTurnInDB
local DBDefaults = {
	ChatText = true,
	FirstLaunch = true,
	debug = false,
	TurnInEnabled = true,
	AutoGossip = true,
	AutoGossipSafeMode = true,
	AcceptGeneralQuests = true,
	DoCampainQuests = false,
	AcceptRepeatable = false,
	trivial = false,
	lootreward = false,
	autoequip = false,
	armor = {},
	weapon = {},
	stat = {},
	secondary = {},
	useGlobalDB = true,
	Blacklist = Blacklist,
	Whitelist = Whitelist,
}

local ATI_Container = CreateFrame('Frame')
local IsMerchantOpen = false
local SLOTS = {
	['INVTYPE_AMMO'] = { 'AmmoSlot' },
	['INVTYPE_HEAD'] = { 'HeadSlot' },
	['INVTYPE_NECK'] = { 'NeckSlot' },
	['INVTYPE_SHOULDER'] = { 'ShoulderSlot' },
	['INVTYPE_CHEST'] = { 'ChestSlot' },
	['INVTYPE_WAIST'] = { 'WaistSlot' },
	['INVTYPE_LEGS'] = { 'LegsSlot' },
	['INVTYPE_FEET'] = { 'FeetSlot' },
	['INVTYPE_WRIST'] = { 'WristSlot' },
	['INVTYPE_HAND'] = { 'HandsSlot' },
	['INVTYPE_FINGER'] = { 'Finger0Slot', 'Finger1Slot' },
	['INVTYPE_TRINKET'] = { 'Trinket0Slot', 'Trinket1Slot' },
	['INVTYPE_CLOAK'] = { 'BackSlot' },
	['INVTYPE_WEAPON'] = { 'MainHandSlot', 'SecondaryHandSlot' },
	['INVTYPE_2HWEAPON'] = { 'MainHandSlot' },
	['INVTYPE_RANGED'] = { 'MainHandSlot' },
	['INVTYPE_RANGEDRIGHT'] = { 'MainHandSlot' },
	['INVTYPE_WEAPONMAINHAND'] = { 'MainHandSlot' },
	['INVTYPE_SHIELD'] = { 'SecondaryHandSlot' },
	['INVTYPE_WEAPONOFFHAND'] = { 'SecondaryHandSlot' },
	['INVTYPE_HOLDABLE'] = { 'SecondaryHandSlot' },
}
local TempBlackList = {}
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
	['Favor Amongst the Brotherhood, Blood of the Mountain'] = {
		item = 'Blood of the Mountain',
		amount = 1,
		currency = false,
	},
	['Favor Amongst the Brotherhood, Core Leather'] = { item = 'Core Leather', amount = 2, currency = false },
	['Favor Amongst the Brotherhood, Dark Iron Ore'] = { item = 'Dark Iron Ore', amount = 10, currency = false },
	['Favor Amongst the Brotherhood, Fiery Core'] = { item = 'Fiery Core', amount = 1, currency = false },
	['Favor Amongst the Brotherhood, Lava Core'] = { item = 'Lava Core', amount = 1, currency = false },
	['Gaining Acceptance'] = { item = 'Dark Iron Residue', amount = 4, currency = false },
	['Gaining Even More Acceptance'] = { item = 'Dark Iron Residue', amount = 100, currency = false },
	--Burning Crusade, Lower City
	['More Feathers'] = { item = 'Arakkoa Feather', amount = 30, currency = false },
	--Aldor
	["More Marks of Kil'jaeden"] = { item = "Mark of Kil'jaeden", amount = 10, currency = false },
	['More Marks of Sargeras'] = { item = 'Mark of Sargeras', amount = 10, currency = false },
	['Fel Armaments'] = { item = 'Fel Armaments', amount = 10, currency = false },
	["Single Mark of Kil'jaeden"] = { item = "Mark of Kil'jaeden", amount = 1, currency = false },
	['Single Mark of Sargeras'] = { item = 'Mark of Sargeras', amount = 1, currency = false },
	['More Venom Sacs'] = { item = 'Dreadfang Venom Sac', amount = 8, currency = false },
	--Scryer
	['More Firewing Signets'] = { item = 'Firewing Signet', amount = 10, currency = false },
	['More Sunfury Signets'] = { item = 'Sunfury Signet', amount = 10, currency = false },
	['Arcane Tomes'] = { item = 'Arcane Tome', amount = 1, currency = false },
	['Single Firewing Signet'] = { item = 'Firewing Signet', amount = 1, currency = false },
	['Single Sunfury Signet'] = { item = 'Sunfury Signet', amount = 1, currency = false },
	['More Basilisk Eyes'] = { item = 'Dampscale Basilisk Eye', amount = 8, currency = false },
	--Skettis
	['More Shadow Dust'] = { item = 'Shadow Dust', amount = 6, currency = false },
	--SporeGar
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
	--MoP
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
	--MOP timeless Island
	['Great Turtle Meat'] = { item = 'Great Turtle Meat', amount = 1, currency = false },
	['Heavy Yak Flank'] = { item = 'Heavy Yak Flank', amount = 1, currency = false },
	['Meaty Crane Leg'] = { item = 'Meaty Crane Leg', amount = 1, currency = false },
	['Pristine Firestorm Egg'] = { item = 'Pristine Firestorm Egg', amount = 1, currency = false },
	['Thick Tiger Haunch'] = { item = 'Thick Tiger Haunch', amount = 1, currency = false },
}

local OptionTable = {
	type = 'group',
	name = L['Auto TurnIn'],
	childGroups = 'tab',
	get = function(info)
		return DB[info[#info]]
	end,
	set = function(info, val)
		DB[info[#info]] = val
	end,
	disabled = function()
		return SUI:IsModuleDisabled(module)
	end,
}
local buildItemList
local function debug(content)
	SUI.Log(content, 'AutoTurnIn')
end
-- turns quest in printing reward text if `ChatText` option is set.
-- prints appropriate message if item is taken by greed
-- equips received reward if such option selected
function module:TurnInQuest(rewardIndex)
	debug('TurnInQuest')
	debug(rewardIndex)
	if DB.ChatText then
		SUI:Print((UnitName('target') and UnitName('target') or '') .. '\n', GetRewardText())
	end
	if IsAltKeyDown() then
		SUI:Print('Override key held, turn in disabled')
		module:CancelAllTimers()
		return
	end
	if module.Blacklist.isBlacklisted(GetQuestID()) then
		SUI:Print('Quest is blacklisted, not turning in.')
		return
	end

	GetQuestReward(rewardIndex)
end

function module:EquipItem(ItemToEquip)
	if InCombatLockdown() then
		return
	end

	local EquipItemName = C_Item.GetItemInfo(ItemToEquip)
	local EquipILvl = C_Item.GetDetailedItemLevelInfo(ItemToEquip)
	local ItemFound = false

	-- Make sure it is in the bags
	for bag = 0, NUM_BAG_SLOTS do
		if ItemFound then
			return
		end
		for slot = 1, GetContainerNumSlots(bag), 1 do
			local link = GetContainerItemLink(bag, slot)
			if link then
				local slotItemName = C_Item.GetItemInfo(link)
				local SlotILvl = C_Item.GetDetailedItemLevelInfo(link)
				if (slotItemName == EquipItemName) and (SlotILvl == EquipILvl) then
					if IsMerchantOpen then
						SUI:Print(L['Unable to equip'] .. ' ' .. link)
						module:CancelAllTimers()
					else
						SUI:Print(L['Equipping reward'] .. ' ' .. link)
						UseContainerItem(bag, slot)
						module:CancelAllTimers()
						ItemFound = true
						return
					end
				end
			end
		end
	end
end

function module.MERCHANT_SHOW()
	IsMerchantOpen = true
end

function module.MERCHANT_CLOSED()
	IsMerchantOpen = false
end

local QUESTDETAILHistory = {}
function module.QUEST_DETAIL()
	debug('QUEST_DETAIL')
	debug(GetTitleText())
	debug(GetObjectiveText())
	debug(GetQuestID())
	if DB.AcceptGeneralQuests then
		if DB.ChatText then
			local title = GetTitleText()
			local objText = GetObjectiveText()
			if title and title ~= '' and not QUESTDETAILHistory[title] then
				QUESTDETAILHistory[title] = objText
				SUI:Print(title)
				if objText and objText ~= '' then
					SUI:Print(L['Quest Objectives'])
					print(objText)
					debug('    ' .. objText)
				end
			end
		end

		if not IsAltKeyDown() and not module.Blacklist.isBlacklisted(GetQuestID()) then
			AcceptQuest()
		end
	end
end

function module.QUEST_COMPLETE()
	if not DB.TurnInEnabled then
		return
	end

	-- Look for the item that is the best upgrade and whats worth the most.
	local GreedID, GreedValue, UpgradeID = nil, 0, nil
	local GreedLink, UpgradeLink, UpgradeAmmount = nil, nil, 0
	local QuestRewardsWeapon = false
	for i = 1, GetNumQuestChoices() do
		-- Load the items information
		local link = GetQuestItemLink('choice', i)
		debug(link)
		if link == nil then
			return
		end
		local itemName, _, _, _, _, _, _, _, itemEquipLoc, _, itemSellPrice = C_Item.GetItemInfo(link)
		local QuestItemTrueiLVL = SUI:GetiLVL(link) or 0

		-- Check the items value
		if itemSellPrice > GreedValue then
			GreedValue = itemSellPrice
			GreedID = i
			GreedLink = link
		end

		-- See if the item is an upgrade
		local slot = SLOTS[itemEquipLoc]
		if slot then
			local firstSlot = GetInventorySlotInfo(slot[1])
			local firstinvLink = GetInventoryItemLink('player', firstSlot)
			local EquipedLevel = SUI:GetiLVL(firstinvLink) or 0

			if EquipedLevel then
				-- If reward is a ring, trinket or one-handed weapons all slots must be checked in order to swap with a lesser ilevel
				if #slot > 1 then
					local secondSlot = GetInventorySlotInfo(slot[2])
					local secondinvLink = GetInventoryItemLink('player', secondSlot)
					-- if (invLink) then
					-- 	local eq2Level = SUI:GetiLVL(invLink)
					-- 	if (EquipedLevel > eq2Level) then
					-- 		debug('Slot ' .. #slot .. ' is lower (' .. EquipedLevel .. '>' .. eq2Level .. ')')
					-- 		firstSlot = secondSlot
					-- 		EquipedLevel = eq2Level
					-- 		firstinvLink = secondinvLink
					-- 	end
					-- end
				end

				-- comparing lowest equipped item level with reward's item level
				debug('iLVL Comparisson ' .. link .. ' - ' .. QuestItemTrueiLVL .. '-' .. EquipedLevel .. ' - ' .. (firstinvLink or ''))

				if (QuestItemTrueiLVL > EquipedLevel) and ((QuestItemTrueiLVL - EquipedLevel) > UpgradeAmmount) then
					UpgradeLink = link
					UpgradeID = i
					UpgradeAmmount = (QuestItemTrueiLVL - EquipedLevel)
				end
			end

			-- Check if it is a weapon, do this last incase it only rewards one item
			if slot[1] == 'MainHandSlot' or slot[1] == 'SecondaryHandSlot' then
				QuestRewardsWeapon = true
			elseif slot[1] == 'Trinket0Slot' then
				QuestRewardsWeapon = true
			end
		end
	end

	debug(GetNumQuestChoices())
	-- If there is more than one reward check that we are allowed to select it.
	if GetNumQuestChoices() > 1 then
		if QuestRewardsWeapon then
			-- SUI:Print(L['Canceling turn in, quest rewards'] .. ' ' .. QuestRewardsWeapon .. '.')
		elseif DB.lootreward then
			if GreedID and not UpgradeID then
				SUI:Print('Grabbing item to vendor ' .. GreedLink .. ' worth ' .. SUI:GoldFormattedValue(GreedValue))
				module:TurnInQuest(GreedID)
			elseif UpgradeID then
				SUI:Print('Upgrade found! Grabbing ' .. UpgradeLink)
				module:TurnInQuest(UpgradeID)
				-- if DB.autoequip then module.equipTimer = module:ScheduleRepeatingTimer('EquipItem', 0.5, UpgradeLink) end
			end
		else
			if GreedID and not UpgradeID then
				SUI:Print('Would vendor: ' .. GreedLink .. ' worth ' .. SUI:GoldFormattedValue(GreedValue))
			elseif UpgradeLink then
				SUI:Print('Would select upgrade ' .. UpgradeLink)
			end
		end
	else
		if GreedID and not UpgradeID then
			SUI:Print('Quest rewards vendor item ' .. GreedLink .. ' worth ' .. SUI:GoldFormattedValue(GreedValue))
			module:TurnInQuest(GreedID)
		elseif UpgradeID then
			-- if DB.autoequip then module.equipTimer = module:ScheduleRepeatingTimer('EquipItem', 0.5, UpgradeLink) end
			SUI:Print('Quest rewards a upgrade ' .. UpgradeLink)
			module:TurnInQuest(UpgradeID)
		else
			debug(L['No Reward, turning in.'])
			module:TurnInQuest(1)
		end
	end
end

function module:GetItemAmount(isCurrency, item)
	local currency = C_CurrencyInfo.GetCurrencyInfo(item)
	local amount = isCurrency and (currency.quantity or C_Item.GetItemCount(item, nil, true))
	return amount and amount or 0
end

---@param ... GossipQuestUIInfo[]
function module:VarArgForActiveQuests(...)
	debug('VarArgForActiveQuests')
	if ... then
		debug(#...)
	end

	for i, quest in pairs(...) do
		debug(quest.isComplete)
		debug(quest.frequency)
		debug(quest.title)
		if quest.isComplete and (not module.Blacklist.isBlacklisted(quest.title)) then
			local questInfo = Lquests[quest.title]
			debug('selecting.. ' .. quest.title)
			if questInfo then
				if module:GetItemAmount(questInfo.currency, questInfo.item) >= questInfo.amount then
					C_GossipInfo.SelectActiveQuest(quest.questID)
				end
			else
				C_GossipInfo.SelectActiveQuest(quest.questID)
			end
		end
	end
end

-- like previous function this one works around `nil` values in a list.
---@param ... GossipQuestUIInfo[]
function module:VarArgForAvailableQuests(...)
	debug('VarArgForAvailableQuests')
	debug(#...)

	for i, quest in pairs(...) do
		local trivialORAllowed = (not quest.isTrivial) or DB.trivial
		local isRepeatableORAllowed = (not quest.repeatable) or DB.AcceptRepeatable

		-- Quest is appropriate if: (it is trivial and trivial are accepted) and (any quest accepted or (it is daily quest that is not in ignore list))
		if (trivialORAllowed and isRepeatableORAllowed) and not module.Blacklist.isBlacklisted(quest.title) and not module.Blacklist.isBlacklisted(quest.questID) then
			local questInfo = Lquests[quest.title]
			if questInfo and questInfo.amount then
				if self:GetItemAmount(questInfo.currency, questInfo.item) >= questInfo.amount then
					C_GossipInfo.SelectAvailableQuest(quest.questID)
				end
			else
				C_GossipInfo.SelectAvailableQuest(quest.questID)
			end
		else
			debug('Quest is not appropriate: ' .. quest.title)
			debug('-isImportant: ' .. tostring(quest.isImportant))
			debug('-isMeta: ' .. tostring(quest.isMeta))
			debug('-Trivial: ' .. tostring(trivialORAllowed))
			debug('-Repeatable: ' .. tostring(isRepeatableORAllowed))
			debug('-Blacklisted: ' .. tostring(module.Blacklist.isBlacklisted(quest.title)) .. ', ' .. tostring(module.Blacklist.isBlacklisted(quest.questID)))
		end
	end
end

function module:FirstLaunch()
	local PageData = {
		ID = 'Autoturnin',
		Name = L['Auto TurnIn'],
		SubTitle = L['Auto TurnIn'],
		Desc1 = L['Automatically accept and turn in quests.'],
		Desc2 = L['Holding ALT while talking to a NPC will temporarily disable the auto turnin module.'],
		RequireDisplay = DB.FirstLaunch,
		Display = function()
			local SUI_Win = SUI.Setup.window.content
			local UI = LibAT.UI

			--Container
			local ATI = CreateFrame('Frame', nil)
			ATI:SetParent(SUI_Win)
			ATI:SetAllPoints(SUI_Win)

			if SUI:IsModuleDisabled('AutoTurnIn') then
				ATI.lblDisabled = UI.CreateLabel(ATI, 'Disabled', 'GameFontNormalLarge')
				ATI.lblDisabled:SetPoint('CENTER', ATI)
			else
				-- Setup checkboxes
				ATI.options = {}
				ATI.options.AcceptGeneralQuests = UI.CreateCheckbox(ATI, L['Accept quests'], 220, 20)
				ATI.options.TurnInEnabled = UI.CreateCheckbox(ATI, L['Turn in completed quests'], 220, 20)
				ATI.options.AutoGossip = UI.CreateCheckbox(ATI, L['Auto gossip'], 220, 20)
				ATI.options.AutoGossipSafeMode = UI.CreateCheckbox(ATI, L['Auto gossip safe mode'], 220, 20)
				ATI.options.autoequip = UI.CreateCheckbox(ATI, L['Auto equip upgrade quest rewards'] .. ' - ' .. L['Based on iLVL'], 400, 20)

				-- Retail only options
				if SUI.IsRetail then
					ATI.options.lootreward = UI.CreateCheckbox(ATI, L['Auto select quest reward'], 220, 20)
					ATI.options.DoCampainQuests = UI.CreateCheckbox(ATI, L['Accept/Complete Campaign Quests'], 220, 20)
				end

				-- Positioning - 2 column layout with proper spacing
				local col1X, col2X = -150, 50 -- X positions for each column
				local startY = -20 -- Starting Y position
				local rowHeight = 25 -- Height per row including spacing

				-- Column 1 (left)
				ATI.options.AcceptGeneralQuests:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X, startY)
				ATI.options.AutoGossip:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X, startY - rowHeight)
				ATI.options.AutoGossipSafeMode:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X, startY - (rowHeight * 2))

				-- Column 2 (right)
				ATI.options.TurnInEnabled:SetPoint('TOPLEFT', SUI_Win, 'TOP', col2X, startY)

				if SUI.IsRetail then
					ATI.options.lootreward:SetPoint('TOPLEFT', SUI_Win, 'TOP', col2X, startY - rowHeight)
					ATI.options.DoCampainQuests:SetPoint('TOPLEFT', SUI_Win, 'TOP', col2X, startY - (rowHeight * 2))
					-- Auto equip spans both columns at bottom
					ATI.options.autoequip:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X, startY - (rowHeight * 3))
				else
					-- Auto equip at bottom for non-retail
					ATI.options.autoequip:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X, startY - (rowHeight * 3))
				end

				-- Defaults
				for key, object in pairs(ATI.options) do
					object:SetChecked(DB[key])
				end
			end
			SUI_Win.ATI = ATI
		end,
		Next = function()
			if SUI:IsModuleEnabled('AutoTurnIn') then
				local window = SUI.Setup.window
				---@diagnostic disable-next-line: undefined-field
				local ATI = window.content.ATI

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

module.Blacklist = {}
module.Whitelist = {}
---@enum ListTypes
---| 'QuestIDs'
---| 'Gossip'
---| 'Wildcard'

---Returns true if blacklisted
---@param lookupId string|number
---@return boolean
function module.Blacklist.isBlacklisted(lookupId)
	local name = tostring(lookupId)

	-- Determine which blacklist to use
	local blacklistDB = DB.useGlobalDB and GlobalDB.Blacklist or DB.Blacklist
	local gossipBlacklist = blacklistDB.Gossip
	local questBlacklist = blacklistDB.QuestIDs
	local wildcardBlacklist = blacklistDB.Wildcard

	-- Function to perform a case-insensitive search
	local function isInPairSearch(blacklist, checkName)
		for _, key in pairs(blacklist) do
			if string.find(string.lower(checkName), string.lower(key)) then
				return true
			end
		end
		return false
	end

	-- Check for direct match in blacklists or wildcard match
	if SUI:IsInTable(gossipBlacklist, name) or SUI:IsInTable(TempBlackList, name) then
		debug(name .. '---IS BLACKLISTED')
		return true
	elseif isInPairSearch(wildcardBlacklist, name) or isInPairSearch(questBlacklist, name) then
		debug(name .. ' - IS BLACKLISTED')
		return true
	end

	-- Not blacklisted
	debug(name .. '---IS NOT BLACKLISTED')
	return false
end

local function Add(list, id, mode, temp, index)
	if temp then
		TempBlackList[id] = true
	else
		local database = DB.useGlobalDB and GlobalDB[list][mode] or DB[list][mode]
		if index then
			database[index] = id
		else
			database[#database + 1] = id
		end
	end
end
---@param id string|number
---@param mode ListTypes
---@param temp? boolean
---@param index? number
function module.Blacklist.Add(id, mode, temp, index)
	Add('Blacklist', id, mode, temp, index)
end

---@param id string|number
---@param mode ListTypes
---@param temp? boolean
---@param index? number
function module.Whitelist.Add(id, mode, temp, index)
	Add('Whitelist', id, mode, temp, index)
end

---@param mode ListTypes
---@return table<number, any>
function module.Blacklist.Get(mode)
	return DB.useGlobalDB and GlobalDB.Blacklist[mode] or DB.Blacklist[mode]
end
---@param mode ListTypes
---@return table<number, any>
function module.Whitelist.Get(mode)
	return DB.useGlobalDB and GlobalDB.Whitelist[mode] or DB.Whitelist[mode]
end

local function Remove(list, id, mode, temp, index)
	local name = tostring(id)
	if temp then
		TempBlackList[name] = nil
	else
		local database = DB.useGlobalDB and GlobalDB[list][mode] or DB[list][mode]
		if index then
			database[index] = nil
		else
			database[name] = nil
		end
	end
end

---@param id string|number
---@param mode ListTypes
---@param temp? boolean
---@param index? number
function module.Blacklist.Remove(id, mode, temp, index)
	Remove('Blacklist', id, mode, temp, index)
end

---@param id string|number
---@param mode ListTypes
---@param temp? boolean
---@param index? number
function module.Whitelist.Remove(id, mode, temp, index)
	Remove('Whitelist', id, mode, temp, index)
end

function module.QUEST_GREETING()
	local numActiveQuests = GetNumActiveQuests()
	local numAvailableQuests = GetNumAvailableQuests()

	debug(numActiveQuests)
	debug(numAvailableQuests)
	for i = 1, numActiveQuests do
		local isComplete = select(2, GetActiveTitle(i))
		debug('Option ' .. i .. ' isComplete: ' .. tostring(isComplete))
		if isComplete then
			C_GossipInfo.SelectActiveQuest(i)
			if SelectActiveQuest then
				debug('Selecting Active Quest ' .. i)
				---@diagnostic disable-next-line: redundant-parameter
				SelectActiveQuest(i)
			end
		end
	end

	for i = 1, numAvailableQuests do
		if SUI.IsRetail then
			local isTrivial, frequency, isRepeatable, _, questID = GetAvailableQuestInfo(i - numActiveQuests)

			local trivialORAllowed = (not isTrivial) or DB.trivial
			local isDaily = (frequency == LE_QUEST_FREQUENCY_DAILY or frequency == LE_QUEST_FREQUENCY_WEEKLY)
			local isRepeatableORAllowed = (not isRepeatable or not isDaily) or DB.AcceptRepeatable
			if (trivialORAllowed and isRepeatableORAllowed) and (not module.Blacklist.isBlacklisted(questID)) and questID ~= 0 then
				debug('selecting ' .. i .. ' questId ' .. questID)
				---@diagnostic disable-next-line: redundant-parameter
				C_GossipInfo.SelectAvailableQuest(i)
			end
		else
			---@diagnostic disable-next-line: redundant-parameter
			C_GossipInfo.SelectAvailableQuest(i)
		end
	end
end

function module.GOSSIP_SHOW()
	if (not DB.AutoGossip) or (IsAltKeyDown()) then
		return
	end

	module:VarArgForActiveQuests(C_GossipInfo.GetActiveQuests())
	module:VarArgForAvailableQuests(C_GossipInfo.GetAvailableQuests())

	debug('------ [Debugging Gossip] ------')
	local options = C_GossipInfo.GetOptions()
	debug('Number of Options ' .. #options)
	for _, gossip in pairs(options) do
		debug('---Start Option Info---')

		-- Debug individual gossip attributes
		debug('Gossip Name: ' .. tostring(gossip.name))
		debug('Gossip Rewards: ' .. tostring(gossip.rewards))
		debug('Gossip Status: ' .. tostring(gossip.status))
		debug('Gossip Flags: ' .. tostring(gossip.flags))

		-- Check if gossip is whitelisted
		local whitelist = DB.useGlobalDB and GlobalDB.Whitelist.Gossip or DB.Whitelist.Gossip
		local isWhitelisted = SUI:IsInTable(whitelist, gossip.name)
		debug('Is Whitelisted: ' .. tostring(isWhitelisted))

		-- Check if gossip is blacklisted
		local isBlacklisted = module.Blacklist.isBlacklisted(gossip.name)
		debug('Is Blacklisted: ' .. tostring(isBlacklisted))

		-- Check if gossip is a quest
		local isQuest = string.match(gossip.name, 'Quest') and true or false
		debug('Is a Quest: ' .. tostring(isQuest))

		-- Check the final condition
		local Allow = not isBlacklisted or (isWhitelisted or isQuest)
		debug('Final Condition: ' .. tostring(Allow))
		debug('---End Option Info---')
		if (gossip.status == 0) and Allow then
			-- If we are in safemode and gossip option flagged as 'QUEST' then exit
			if DB.AutoGossipSafeMode and (not isWhitelisted and not isQuest) then
				debug(string.format('Safe mode active - not selecting gossip option "%s"', gossip.name))
				return
			end
			TempBlackList[gossip.name] = true
			debug(gossip.name .. '---BLACKLISTED')
			C_GossipInfo.SelectOption(gossip.gossipOptionID)

			if DB.ChatText then
				SUI:Print('Selecting: ' .. gossip.name)
			end
			return
		end
	end

	module:VarArgForActiveQuests(C_GossipInfo.GetActiveQuests())
	module:VarArgForAvailableQuests(C_GossipInfo.GetAvailableQuests())
end

function module.QUEST_PROGRESS()
	if IsQuestCompletable() and DB.TurnInEnabled and (not module.Blacklist.isBlacklisted(GetTitleText())) then
		CompleteQuest()
	end
end

function module:OnInitialize()
	module.Database = SUI.SpartanUIDB:RegisterNamespace('AutoTurnIn', { global = GlobalDBDefaults, profile = DBDefaults })
	DB = module.Database.profile
	GlobalDB = module.Database.global

	-- Register profile change callbacks
	module.Database.RegisterCallback(module, 'OnProfileChanged', function()
		DB = module.Database.profile
		GlobalDB = module.Database.global
	end)
	module.Database.RegisterCallback(module, 'OnProfileCopied', function()
		DB = module.Database.profile
		GlobalDB = module.Database.global
	end)
	module.Database.RegisterCallback(module, 'OnProfileReset', function()
		DB = module.Database.profile
		GlobalDB = module.Database.global
	end)
end

function module:OnEnable()
	debug('AutoTurnIn Loaded')
	module:BuildOptions()
	module:FirstLaunch()
	local lastEvent = ''
	if SUI:IsModuleDisabled(module) then
		return
	end

	local function OnEvent(_, event)
		if SUI:IsModuleDisabled(module) then
			return
		end
		debug(event)
		lastEvent = event

		local QuestID = GetQuestID()
		if QuestID ~= 0 then
			local CampaignId = C_CampaignInfo.GetCampaignID(QuestID)
			debug(C_CampaignInfo.GetCurrentChapterID(CampaignId))
			debug(C_CampaignInfo.IsCampaignQuest(QuestID))
			if C_CampaignInfo.IsCampaignQuest(QuestID) and not DB.DoCampainQuests and C_CampaignInfo.GetCurrentChapterID(CampaignId) ~= nil then
				SUI:Print(L['Current quest is a campaign quest, pausing AutoTurnIn'])
				return
			end
		end

		if IsAltKeyDown() then
			SUI:Print('Canceling Override key held disabled')
			module:CancelAllTimers()
			return
		end
		if IsControlKeyDown() then
			if event == 'GOSSIP_SHOW' or event == 'QUEST_GREETING' then
				SUI:Print('Quest Blacklist key held, select the quest to blacklist')
			elseif event == 'QUEST_DETAIL' or event == 'QUEST_PROGRESS' then
				if module.Blacklist.isBlacklisted(QuestID) then
					SUI:Print('Quest "' .. GetTitleText() .. '" is already blacklisted ')
				else
					SUI:Print('Blacklisting quest "' .. GetTitleText() .. '" ID# ' .. QuestID)
					module.Blacklist.Add(QuestID, 'QuestIDs')
					buildItemList('QuestIDs')
				end
			end
			module:CancelAllTimers()
			return
		end

		if module[event] then
			module[event]()
		end
	end

	ATI_Container:SetScript('OnEvent', OnEvent)
	ATI_Container:RegisterEvent('GOSSIP_SHOW') -- multiple quests, and NPC chat screen
	ATI_Container:RegisterEvent('QUEST_DETAIL') -- new quest screen
	ATI_Container:RegisterEvent('QUEST_GREETING')
	ATI_Container:RegisterEvent('QUEST_PROGRESS')
	ATI_Container:RegisterEvent('QUEST_COMPLETE') -- quest turn in screen
	ATI_Container:RegisterEvent('MERCHANT_SHOW')
	ATI_Container:RegisterEvent('MERCHANT_CLOSED')

	local IsCollapsed = true

	-- Store panel references so we can hide them on disable
	if not module.QuestPanels then
		module.QuestPanels = {}
	end

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
		OptionsPopdown.title = UI.CreateLabel(OptionsPopdown, '|cffffffffSpartan|cffe21f1fUI|r AutoTurnIn', 'GameFontNormal')
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
				if Checkbox:GetChecked() then
					OnEvent(nil, lastEvent)
				end
			end)
		end

		options.DoCampainQuests:SetPoint('TOPLEFT', Panel, 'TOPLEFT', 5, -2)
		options.AcceptGeneralQuests:SetPoint('TOPLEFT', options.DoCampainQuests, 'BOTTOMLEFT', 0, 2)
		options.TurnInEnabled:SetPoint('LEFT', options.AcceptGeneralQuests, 'RIGHT', 5, 0)
		options.AutoGossip:SetPoint('TOPLEFT', options.AcceptGeneralQuests, 'BOTTOMLEFT', 0, 2)
		options.AutoGossipSafeMode:SetPoint('LEFT', options.AutoGossip, 'RIGHT', 5, 0)

		OptionsPopdown.Panel = Panel
		OptionsPopdown.Panel.options = options

		-- Store panel reference for cleanup on disable
		module.QuestPanels[v] = OptionsPopdown
	end
end

function module:OnDisable()
	ATI_Container:UnregisterEvent('GOSSIP_SHOW') -- multiple quests, and NPC chat screen
	ATI_Container:UnregisterEvent('QUEST_DETAIL') -- new quest screen
	ATI_Container:UnregisterEvent('QUEST_GREETING')
	ATI_Container:UnregisterEvent('QUEST_PROGRESS')
	ATI_Container:UnregisterEvent('QUEST_COMPLETE') -- quest turn in screen
	ATI_Container:UnregisterEvent('MERCHANT_SHOW')
	ATI_Container:UnregisterEvent('MERCHANT_CLOSED')

	-- Hide and cleanup quest panels
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

function module:BuildOptions()
	buildItemList = function(listType, mode)
		if not mode then
			mode = 'Blacklist'
		end
		local spellsOpt = OptionTable.args[mode].args[listType].args.list.args
		table.wipe(spellsOpt)

		for itemId, entry in pairs(module[mode].Get(listType)) do
			local label

			if type(entry) == 'number' then
				-- If the entry is a number, assume it's a quest ID
				local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(entry)
				if title then
					label = 'ID: ' .. entry .. ' (' .. title .. ')'
				else
					label = '|cFFFF0000ID: ' .. entry .. ' (Title not found)'
				end
			else
				-- If the entry is not a number, use it directly
				label = entry
			end

			spellsOpt[itemId .. 'label'] = {
				type = 'description',
				width = 'double',
				fontSize = 'medium',
				order = itemId,
				name = label,
			}
			spellsOpt[tostring(itemId)] = {
				type = 'execute',
				name = L['Delete'],
				width = 'half',
				order = itemId + 0.05,
				func = function(info)
					module[mode].Remove(itemId, listType)
					buildItemList(listType)
				end,
			}
		end
	end

	OptionTable.args = {
		DoCampainQuests = {
			name = L['Accept/Complete Campaign Quests'],
			type = 'toggle',
			width = 'double',
			order = 1,
		},
		ChatText = {
			name = L['Output quest text in chat'],
			type = 'toggle',
			width = 'double',
			order = 2,
		},
		QuestAccepting = {
			name = L['Quest accepting'],
			type = 'group',
			inline = true,
			order = 10,
			width = 'full',
			get = function(info)
				return DB[info[#info]]
			end,
			set = function(info, val)
				DB[info[#info]] = val
			end,
			args = {
				AcceptGeneralQuests = {
					name = L['Accept quests'],
					type = 'toggle',
					order = 10,
				},
				trivial = {
					name = L['Accept trivial quests'],
					type = 'toggle',
					order = 20,
				},
				AcceptRepeatable = {
					name = L['Accept repeatable'],
					type = 'toggle',
					order = 30,
				},
				AutoGossip = {
					name = L['Auto gossip'],
					type = 'toggle',
					order = 15,
				},
				AutoGossipSafeMode = {
					name = L['Auto gossip safe mode'],
					desc = 'If the option is not in the whitelist or does not have the (Quest) tag, it will not be automatically selected.',
					type = 'toggle',
					order = 16,
				},
			},
		},
		QuestTurnIn = {
			name = L['Quest turn in'],
			type = 'group',
			inline = true,
			order = 20,
			width = 'full',
			get = function(info)
				return DB[info[#info]]
			end,
			set = function(info, val)
				DB[info[#info]] = val
			end,
			args = {
				TurnInEnabled = {
					name = L['Turn in completed quests'],
					type = 'toggle',
					order = 10,
				},
				lootreward = {
					name = L['Auto select quest reward'],
					type = 'toggle',
					order = 30,
				},
				autoequip = {
					name = L['Auto equip upgrade quest rewards'],
					desc = L['Based on iLVL'],
					type = 'toggle',
					order = 30,
				},
			},
		},
		useGlobalDB = {
			name = L['Use a shared Blacklist & Whitelist for all characters.'],
			type = 'toggle',
			width = 'full',
			order = 30,
		},
		Blacklist = {
			type = 'group',
			name = 'Blacklist',
			order = 40,
			args = {
				QuestIDs = {
					type = 'group',
					name = 'Quest ID',
					order = 40,
					args = {
						desc = {
							name = 'Blacklisted quests will never be auto accepted',
							type = 'description',
							order = 1,
						},
						desc2 = {
							name = 'Quests can be blacklisted by holding CTRL while talking to a NPC or by adding the quest ID to the list below',
							type = 'description',
							order = 1.1,
						},
						create = {
							name = 'Add Quest ID',
							type = 'input',
							order = 2,
							width = 'full',
							set = function(info, input)
								module.Blacklist.Add(input, 'QuestIDs', false, #info - 1)
								buildItemList(info[#info - 1])
							end,
						},
						list = {
							order = 3,
							type = 'group',
							inline = true,
							name = 'Quest list',
							args = {},
						},
					},
				},
				Wildcard = {
					type = 'group',
					name = 'Wildcard',
					order = 41,
					args = {
						desc = {
							name = 'Any quest or gossip selection when talking to a NPC containing the text below will not be auto selected',
							type = 'description',
							order = 1,
						},
						create = {
							name = 'Add text to block',
							type = 'input',
							order = 2,
							width = 'full',
							set = function(info, input)
								module.Blacklist.Add(input, 'Wildcard', false, #info - 1)
								buildItemList(info[#info - 1])
							end,
						},
						list = {
							order = 3,
							type = 'group',
							inline = true,
							name = 'Quest list',
							args = {},
						},
					},
				},
				Gossip = {
					type = 'group',
					name = 'Gossip options',
					order = 42,
					args = {
						desc = {
							name = 'Blacklisted gossip options will never be auto selected',
							type = 'description',
							order = 1,
						},
						create = {
							name = 'Add gossip text',
							type = 'input',
							order = 2,
							width = 'full',
							set = function(info, input)
								module.Blacklist.Add(input, 'Gossip', false, #info - 1)
								buildItemList(info[#info - 1])
							end,
						},
						list = {
							order = 3,
							type = 'group',
							inline = true,
							name = 'Quest list',
							args = {},
						},
					},
				},
			},
		},
		Whitelist = {
			type = 'group',
			name = 'Whitelist',
			order = 50,
			args = {
				Gossip = {
					type = 'group',
					name = 'Gossip',
					order = 42,
					args = {
						desc = {
							name = 'Whitelisted gossip options will be auto selected',
							type = 'description',
							order = 1,
						},
						create = {
							name = 'Add gossip text',
							type = 'input',
							order = 2,
							width = 'full',
							set = function(info, input)
								module.Whitelist.Add(input, 'Gossip', false, #info - 1)
								buildItemList(info[#info - 1], 'Whitelist')
							end,
						},
						list = {
							order = 3,
							type = 'group',
							inline = true,
							name = 'Quest list',
							args = {},
						},
					},
				},
			},
		},
	}
	buildItemList('QuestIDs')
	buildItemList('Wildcard')
	buildItemList('Gossip')
	buildItemList('Gossip', 'Whitelist')
	SUI.Options:AddOptions(OptionTable, 'AutoTurnIn')
end
