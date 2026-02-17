local SUI, L, print = SUI, SUI.L, SUI.print
---@class SUI.Module.AutoSell : SUI.Module
local module = SUI:NewModule('AutoSell')
module.DisplayName = L['Auto sell']
module.description = 'Auto sells junk and more'
module.log = nil

----------------------------------------------------------------------------------------------------
-- Configuration constants
local MAX_BAG_SLOTS = 12 -- Maximum number of bag slots to scan (0-12 covers all normal bags plus extras)

local Tooltip = CreateFrame('GameTooltip', 'AutoSellTooltip', nil, 'GameTooltipTemplate')
local LoadedOnce = false
local totalValue = 0

-- Performance cache for blacklist lookups
local blacklistLookup = {
	items = {},
	types = {},
	valid = false,
}
local highestILVL = function()
	local CurrentHighestILVL = 0
	for bag = 0, MAX_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
			if itemInfo then
				local iLevel = SUI:GetiLVL(itemInfo.hyperlink)
				if iLevel and iLevel > CurrentHighestILVL then
					CurrentHighestILVL = iLevel
				end
			end
		end
	end
	return CurrentHighestILVL
end

---@class SUI.Module.AutoSell.DB
local DbDefaults = {
	FirstLaunch = true,
	NotCrafting = true,
	NotConsumables = true,
	NotInGearset = true,
	MaximumiLVL = 500,
	MaxILVL = 0,
	LastWowProjectID = WOW_PROJECT_ID,
	Gray = true,
	White = false,
	Green = false,
	Blue = false,
	Purple = false,
	GearTokens = false,
	AutoRepair = true,
	UseGuildBankRepair = false,
	ShowBagMarking = true,
	Blacklist = {
		Items = {
			-- Shadowlands
			180276, --Locked Toolbox Key
			175757, --Construct Supply Key
			27944, --Talisman of True Treasure Tracking
			156725, --red-crystal-monocle
			156726, --yellow-crystal-monocle
			156727, --green-crystal-monocle
			156724, --blue-crystal-monocle
			-- BFA
			168135, --Titans Blood
			166846, --spare parts
			168327, --chain ignitercoil
			166971, --empty energy cell
			170500, --energy cell
			166970, --energy cell
			169475, --Barnacled Lockbox
			137642, --Mark Of Honor
			168217, --Hardened Spring
			168136, --Azerokk's Fist
			168216, --Tempered Plating
			168215, --Machined Gear Assembly
			169334, --Strange Oceanic Sediment
			170193, --Sea Totem
			168802, --Nazjatar Battle Commendation
			171090, --Battleborn Sigil
			153647, --Tome of the quiet mind
			-- Cata
			71141, -- Eternal Ember
			-- Legion
			129276, -- Beginner's Guide to Dimensional Rifting
			-- MOP
			80914, -- Mourning Glory
			-- Misc Items
			141446, --Tome of the Tranquil Mind
			81055, -- Darkmoon ride ticket
			150372, -- Arsenal: The Warglaives of Azzinoth
			32837, -- Warglaive of Azzinoth
			--Professions
			6219, -- Arclight Spanner
			140209, --imported blacksmith hammer
			5956, -- Blacksmith Hammer
			7005, --skinning knife
			2901, --mining pick
			-- Classic WoW
			6256, -- Fishing Pole
			--Start Shredder Operating Manual pages
			16645,
			16646,
			16647,
			16648,
			16649,
			16650,
			16651,
			16652,
			16653,
			16654,
			16655,
			16656,
			2730,
			--End Shredder Operating Manual pages
			63207, -- Wrap of unity
			63206, -- Wrap of unity
		},
		Types = {
			'Container',
			'Companions',
			'Holiday',
			'Mounts',
			'Quest',
		},
	},
}

---@class SUI.Module.AutoSell.CharDB
---@field Whitelist table<number, boolean> Character-specific whitelist items
---@field Blacklist table<number, boolean> Character-specific blacklist items

-- One-time migration: strip values matching old defaults so DB becomes sparse
local function MigrateToDBM(profileDB)
	if profileDB._dbm_migrated then
		return
	end

	-- Old defaults for comparison (must match what DbDefaults had before migration)
	local oldDefaults = {
		FirstLaunch = true,
		NotCrafting = true,
		NotConsumables = true,
		NotInGearset = true,
		MaximumiLVL = 500,
		MaxILVL = 0,
		LastWowProjectID = WOW_PROJECT_ID,
		Gray = true,
		White = false,
		Green = false,
		Blue = false,
		Purple = false,
		GearTokens = false,
		AutoRepair = false,
		UseGuildBankRepair = false,
		ShowBagMarking = true,
	}

	-- Strip values that match defaults (they'll come from CurrentSettings instead)
	for key, defaultVal in pairs(oldDefaults) do
		if profileDB[key] == defaultVal then
			profileDB[key] = nil
		end
	end

	-- Strip seeded Blacklist from DB (now lives in DbDefaults/CurrentSettings)
	if profileDB.Blacklist then
		profileDB.Blacklist = nil
	end

	profileDB._dbm_migrated = true
end

local function debugMsg(msg, level)
	if module.log then
		module.log.log(msg, level or 'debug')
	end
end

-- Build fast blacklist lookup tables
local function buildBlacklistLookup()
	if blacklistLookup.valid then
		return
	end

	-- Reset tables
	blacklistLookup.items = {}
	blacklistLookup.types = {}

	-- Build item blacklist lookup from CurrentSettings (merged defaults + user changes)
	-- false entries = user explicitly removed a default item, skip them
	for _, itemID in pairs(module.CurrentSettings.Blacklist.Items) do
		if itemID and itemID ~= false then
			blacklistLookup.items[itemID] = true
		end
	end

	-- Build type blacklist lookup from CurrentSettings
	for _, itemType in pairs(module.CurrentSettings.Blacklist.Types) do
		if itemType and itemType ~= false then
			blacklistLookup.types[itemType] = true
		end
	end

	blacklistLookup.valid = true
end

-- Invalidate lookup cache when settings change
local function invalidateBlacklistLookup()
	blacklistLookup.valid = false
end

-- Module function to invalidate cache (accessible from Options.lua)
function module:InvalidateBlacklistCache()
	invalidateBlacklistLookup()

	-- Refresh bag markings when cache is invalidated
	if module.CurrentSettings.ShowBagMarking and module.markItems then
		debugMsg('Refreshing bag markings after blacklist cache invalidation', 'debug')
		module.markItems()
	end

	-- Refresh Baganator when cache is invalidated
	if C_AddOns.IsAddOnLoaded('Baganator') and Baganator and Baganator.API then
		Baganator.API.RequestItemButtonsRefresh()
	end
end

local function IsInGearset(bag, slot)
	-- Skip gearset check if called without valid bag/slot (like from Baganator)
	if not bag or not slot or bag < 0 or slot < 1 then
		return false
	end

	local success, result = pcall(function()
		local line
		Tooltip:SetOwner(UIParent, 'ANCHOR_NONE')
		Tooltip:SetBagItem(bag, slot)

		for i = 1, Tooltip:NumLines() do
			line = _G['AutoSellTooltipTextLeft' .. i]
			if line and line:GetText() and line:GetText():find(EQUIPMENT_SETS:format('.*')) then
				return true
			end
		end
		return false
	end)

	if not success then
		debugMsg('IsInGearset error: ' .. tostring(result), 'error')
		return false
	end

	return result
end

---Check if an item would be sold by Blizzard's SellAllJunkItems
---@param item number
---@param quality number
---@return boolean
function module:WouldBlizzardSell(item, quality)
	-- Blizzard only sells gray (quality 0) junk items
	-- and only if SellAllJunkItems is enabled
	if SUI.IsRetail and quality == 0 and C_MerchantFrame and C_MerchantFrame.IsSellAllJunkEnabled then
		return C_MerchantFrame.IsSellAllJunkEnabled()
	end
	return false
end

function module:IsSellable(item, ilink, bag, slot)
	if not item then
		debugMsg('IsSellable: item is nil, returning false', 'warning')
		return false
	end
	local name, _, quality, _, _, itemType, itemSubType, _, equipSlot, _, vendorPrice, _, _, _, expacID, _, isCraftingReagent = C_Item.GetItemInfo(ilink)
	-- Ensure vendorPrice exists and is greater than 0 to prevent selling items with no sale value
	-- (e.g., Legion Remix weapons, items that can't be sold)
	if not vendorPrice or vendorPrice == 0 or name == nil then
		debugMsg('IsSellable: no vendor price or name for item ' .. tostring(item) .. ' (vendorPrice: ' .. tostring(vendorPrice) .. ')', 'debug')
		return false
	end

	-- Check character-specific blacklist FIRST (highest priority)
	if module.CharDB.Blacklist[item] then
		debugMsg('--Decision: Not selling (character blacklist)--', 'debug')
		return false
	end

	-- Check character-specific whitelist (overrides ALL other rules)
	if module.CharDB.Whitelist[item] then
		debugMsg('--Decision: Selling (character whitelist overrides all rules)--', 'debug')
		debugMsg('Item: ' .. (name or 'Unknown') .. ' (Link: ' .. ilink .. ')', 'debug')
		debugMsg('Vendor Price: ' .. tostring(vendorPrice), 'debug')
		return true
	end

	-- 0. Poor (gray): Broken I.W.I.N. Button
	-- 1. Common (white): Archmage Vargoth's Staff
	-- 2. Uncommon (green): X-52 Rocket Helmet
	-- 3. Rare / Superior (blue): Onyxia Scale Cloak
	-- 4. Epic (purple): Talisman of Ephemeral Power
	-- 5. Legendary (orange): Fragment of Val'anyr
	-- 6. Artifact (golden yellow): The Twin Blades of Azzinoth
	-- 7. Heirloom (light yellow): Bloodied Arcanite Reaper
	local iLevel = SUI:GetiLVL(ilink)

	-- Quality check
	if
		(quality == 0 and not module.CurrentSettings.Gray)
		or (quality == 1 and not module.CurrentSettings.White)
		or (quality == 2 and not module.CurrentSettings.Green)
		or (quality == 3 and not module.CurrentSettings.Blue)
		or (quality == 4 and not module.CurrentSettings.Purple)
		or (iLevel and iLevel > module.CurrentSettings.MaxILVL)
	then
		return false
	end

	--Gearset detection
	if module.CurrentSettings.NotInGearset and C_EquipmentSet.CanUseEquipmentSets() and IsInGearset(bag, slot) then
		return false
	end
	-- Gear Tokens
	if quality == 4 and itemType == 'Miscellaneous' and itemSubType == 'Junk' and equipSlot == '' and not module.CurrentSettings.GearTokens then
		return false
	end

	--Crafting Items
	if
		(
			(itemType == 'Gem' or itemType == 'Reagent' or itemType == 'Recipes' or itemType == 'Trade Goods' or itemType == 'Tradeskill')
			or (itemType == 'Miscellaneous' and itemSubType == 'Reagent')
			or (itemType == 'Item Enhancement')
			or isCraftingReagent
		) and module.CurrentSettings.NotCrafting
	then
		return false
	end

	-- Dont sell pets
	if itemSubType == 'Companion Pets' then
		return false
	end
	-- Transmog tokens
	if expacID == 9 and (itemType == 'Miscellaneous' or (itemType == 'Armor' and itemSubType == 'Miscellaneous')) and iLevel == 0 and quality >= 2 then
		return false
	end

	--Consumables
	if module.CurrentSettings.NotConsumables and (itemType == 'Consumable' or itemSubType == 'Consumables') and quality ~= 0 then
		return false
	end --Some junk is labeled as consumable

	-- Check for items with "Use:" in tooltip (profession enhancement items, etc.)
	if bag and slot then
		local success, hasUseText = pcall(function()
			Tooltip:SetOwner(UIParent, 'ANCHOR_NONE')
			Tooltip:SetBagItem(bag, slot)

			for i = 1, Tooltip:NumLines() do
				local line = _G['AutoSellTooltipTextLeft' .. i]
				if line and line:GetText() then
					local text = line:GetText():lower()
					if text:find('^use:') or text:find('^%s*use:') then
						Tooltip:Hide()
						return true
					end
				end
			end
			Tooltip:Hide()
			return false
		end)

		if success and hasUseText then
			debugMsg('Item has "Use:" text in tooltip - skipping', 'debug')
			return false
		end
	end

	if string.find(name, '') and quality == 1 then
		return false
	end

	-- Check profile blacklists (optimized lookups)
	buildBlacklistLookup()
	if not blacklistLookup.items[item] and not blacklistLookup.types[itemType] and not blacklistLookup.types[itemSubType] then
		debugMsg('--Decision: Selling--', 'debug')
		debugMsg('Item: ' .. (name or 'Unknown') .. ' (Link: ' .. ilink .. ')', 'debug')
		debugMsg('Expansion ID: ' .. tostring(expacID), 'debug')
		debugMsg('Item Level: ' .. tostring(iLevel), 'debug')
		debugMsg('Item Type: ' .. itemType, 'debug')
		debugMsg('Item Sub-Type: ' .. itemSubType, 'debug')
		debugMsg('Vendor Price: ' .. tostring(vendorPrice), 'debug')
		return true
	end

	return false
end

function module:SellTrash()
	--Reset Locals
	totalValue = 0
	local ItemToSell = {}
	local highestILVL = highestILVL()
	local blizzardSoldItems = false

	-- First, try to use Blizzard's sell junk function if available
	if SUI.IsRetail and C_MerchantFrame and C_MerchantFrame.IsSellAllJunkEnabled and C_MerchantFrame.SellAllJunkItems then
		if C_MerchantFrame.IsSellAllJunkEnabled() then
			-- Count gray items that Blizzard will sell
			local grayItemCount = 0
			for bag = 0, MAX_BAG_SLOTS do
				for slot = 1, C_Container.GetContainerNumSlots(bag) do
					local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
					if itemInfo then
						local _, _, quality = C_Item.GetItemInfo(itemInfo.itemID)
						if quality == 0 then -- Gray items
							grayItemCount = grayItemCount + 1
						end
					end
				end
			end

			if grayItemCount > 0 then
				debugMsg('Using Blizzard SellAllJunkItems for ' .. grayItemCount .. ' gray items', 'info')
				C_MerchantFrame.SellAllJunkItems()
				-- blizzardSoldItems = true
				-- Schedule our additional selling after a delay to let Blizzard's sell complete
				-- module:ScheduleTimer('SellAdditionalItems', 1.0)
				-- return
			end
		end
	end

	--Find Items to sell and track highest iLVL
	debugMsg('Starting to scan bags for sellable items...', 'info')
	-- Scan through all possible bag slots (0-12 covers all normal bags plus extras)
	for bag = 0, MAX_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
			if itemInfo then
				local iLevel = SUI:GetiLVL(itemInfo.hyperlink)
				if iLevel and iLevel > highestILVL then
					highestILVL = iLevel
				end
				local sellable = module:IsSellable(itemInfo.itemID, itemInfo.hyperlink, bag, slot)
				if sellable then
					ItemToSell[#ItemToSell + 1] = { bag, slot }
					totalValue = totalValue + (select(11, C_Item.GetItemInfo(itemInfo.itemID)) * itemInfo.stackCount)
				end
			end
		end
	end
	debugMsg('Finished scanning bags. Found ' .. #ItemToSell .. ' items to sell.', 'info')

	-- Auto-increase MaximumiLVL if we detected higher iLVL items
	if highestILVL > 0 and (highestILVL + 50) > module.CurrentSettings.MaximumiLVL then
		module.DB.MaximumiLVL = highestILVL + 50
		SUI.DBM:RefreshSettings(module)
		debugMsg('Auto-increased MaximumiLVL to: ' .. module.CurrentSettings.MaximumiLVL .. ' (highest detected: ' .. highestILVL .. ')', 'info')
	end

	--Sell Items if needed
	if #ItemToSell == 0 then
		SUI:Print(L['No items are to be auto sold'])
	else
		SUI:Print('Need to sell ' .. #ItemToSell .. ' additional item(s) for ' .. SUI:GoldFormattedValue(totalValue))
		--Start Loop to sell, reset locals
		module:ScheduleRepeatingTimer('SellTrashInBag', 0.2, ItemToSell)
	end
end

function module:SellAdditionalItems()
	--Reset Locals
	local ItemToSell = {}
	local highestILVL = 0

	--Find Items to sell and track highest iLVL (excluding gray items already sold by Blizzard)
	-- Scan through all possible bag slots (0-12 covers all normal bags plus extras)
	for bag = 0, MAX_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
			if itemInfo then
				local iLevel = SUI:GetiLVL(itemInfo.hyperlink)
				if iLevel and iLevel > highestILVL then
					highestILVL = iLevel
				end
				-- Skip gray items as they were already handled by Blizzard
				local _, _, quality = C_Item.GetItemInfo(itemInfo.itemID)
				if quality ~= 0 and module:IsSellable(itemInfo.itemID, itemInfo.hyperlink, bag, slot) then
					ItemToSell[#ItemToSell + 1] = { bag, slot }
					totalValue = totalValue + (select(11, C_Item.GetItemInfo(itemInfo.itemID)) * itemInfo.stackCount)
				end
			end
		end
	end

	-- Auto-increase MaximumiLVL if we detected higher iLVL items
	if highestILVL > 0 and (highestILVL + 50) > module.CurrentSettings.MaximumiLVL then
		module.DB.MaximumiLVL = highestILVL + 50
		SUI.DBM:RefreshSettings(module)
		debugMsg('Auto-increased MaximumiLVL to: ' .. module.CurrentSettings.MaximumiLVL .. ' (highest detected: ' .. highestILVL .. ')', 'info')
	end

	--Sell Items if needed
	if #ItemToSell == 0 then
		if totalValue == 0 then
			SUI:Print(L['No items are to be auto sold'])
		end
	else
		SUI:Print('Need to sell ' .. #ItemToSell .. ' additional item(s) for ' .. SUI:GoldFormattedValue(totalValue))
		--Start Loop to sell, reset locals
		module:ScheduleRepeatingTimer('SellTrashInBag', 0.2, ItemToSell)
	end
end

---Sell Items 5 at a time, sometimes it can sell stuff too fast for the game.
---@param ItemListing number
function module:SellTrashInBag(ItemListing)
	-- Grab an item to sell
	local item = table.remove(ItemListing)

	-- If the Table is empty then exit.
	if not item then
		module:CancelAllTimers()
		return
	end

	-- SELL!
	C_Container.UseContainerItem(item[1], item[2])

	-- If it was the last item stop timers
	if #ItemListing == 0 then
		module:CancelAllTimers()
	end
end

---@param personalFunds? boolean
function module:Repair(personalFunds)
	-- First see if this vendor can repair & we need to
	if not module.CurrentSettings.AutoRepair or not CanMerchantRepair() or GetRepairAllCost() == 0 then
		return
	end

	if CanGuildBankRepair() and module.CurrentSettings.UseGuildBankRepair and not personalFunds then
		debugMsg('Repairing with guild funds for ' .. SUI:GoldFormattedValue(GetRepairAllCost()), 'info')
		SUI:Print(L['Auto repair cost'] .. ': ' .. SUI:GoldFormattedValue(GetRepairAllCost()) .. ' ' .. L['used guild funds'])
		RepairAllItems(true)
		module:ScheduleTimer('Repair', 0.7, true)
	else
		debugMsg('Repairing with personal funds for ' .. SUI:GoldFormattedValue(GetRepairAllCost()), 'info')
		SUI:Print(L['Auto repair cost'] .. ': ' .. SUI:GoldFormattedValue(GetRepairAllCost()) .. ' ' .. L['used personal funds'])
		RepairAllItems()
	end
end

function module:MERCHANT_SHOW()
	if SUI:IsModuleDisabled('AutoSell') then
		return
	end
	debugMsg('Merchant window opened, starting auto-sell process', 'info')
	module:ScheduleTimer('SellTrash', 0.2)
	module:Repair()
end

function module:MERCHANT_CLOSED()
	debugMsg('Merchant window closed, canceling timers', 'info')
	module:CancelAllTimers()
	if totalValue > 0 then
		totalValue = 0
	end
end

local function HandleItemLevelSquish()
	-- Check if the WOW_PROJECT_ID has changed (indicating potential expansion change)
	if module.CurrentSettings.LastWowProjectID ~= WOW_PROJECT_ID then
		debugMsg('Detected WOW_PROJECT_ID change from ' .. (module.CurrentSettings.LastWowProjectID or 'unknown') .. ' to ' .. WOW_PROJECT_ID, 'info')

		-- Scan all items to find the new highest item level
		local newHighestILVL = highestILVL()

		-- Add buffer to new highest level
		local newMaximumiLVL = newHighestILVL + 50

		-- Check if this represents a squish (new max is significantly lower than old max)
		if newMaximumiLVL > 0 and newMaximumiLVL < (module.CurrentSettings.MaximumiLVL * 0.8) then
			local squishRatio = newMaximumiLVL / module.CurrentSettings.MaximumiLVL
			local oldMaxILVL = module.CurrentSettings.MaxILVL
			local newMaxILVL = math.floor(oldMaxILVL * squishRatio)

			-- Ensure we don't go below 1
			if newMaxILVL < 1 then
				newMaxILVL = 1
			end

			debugMsg('Item level squish detected!', 'warning')
			debugMsg('Old MaximumiLVL: ' .. module.CurrentSettings.MaximumiLVL .. ' -> New: ' .. newMaximumiLVL, 'info')
			debugMsg('Old MaxILVL: ' .. oldMaxILVL .. ' -> New: ' .. newMaxILVL .. ' (ratio: ' .. string.format('%.2f', squishRatio) .. ')', 'info')

			-- Apply the adjustments
			module.DB.MaximumiLVL = newMaximumiLVL
			module.DB.MaxILVL = newMaxILVL

			SUI:Print('Item level squish detected! Adjusted sell threshold from ' .. oldMaxILVL .. ' to ' .. newMaxILVL)
		elseif newMaximumiLVL > module.CurrentSettings.MaximumiLVL then
			-- Normal case: just increase the maximum if we found higher level items
			module.DB.MaximumiLVL = newMaximumiLVL
			debugMsg('Increased MaximumiLVL to: ' .. newMaximumiLVL, 'info')
		end

		-- Update the stored project ID
		module.DB.LastWowProjectID = WOW_PROJECT_ID
		SUI.DBM:RefreshSettings(module)
	end
end

---Debug item sellability with detailed output
function module:DebugItemSellability(link)
	local itemID = tonumber(string.match(link, 'item:(%d+)'))
	if not itemID then
		print('|cffFFFF00AutoSell Debug:|r Could not extract item ID from link')
		return
	end

	local name, _, quality, _, _, itemType, itemSubType, _, equipSlot, _, vendorPrice, _, _, bindType, expacID, _, isCraftingReagent = C_Item.GetItemInfo(link)
	local actualItemLevel, previewLevel, sparseItemLevel = C_Item.GetDetailedItemLevelInfo(link)

	if not name then
		print('|cffFFFF00AutoSell Debug:|r Item info not available')
		return
	end

	-- Find the actual bag/slot for this exact item (matching full link, not just ID)
	local actualBag, actualSlot = nil, nil
	for bag = 0, MAX_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
			if itemInfo and itemInfo.hyperlink == link then
				actualBag, actualSlot = bag, slot
				break
			end
		end
		if actualBag then
			break
		end
	end

	local iLevel = SUI:GetiLVL(link)
	local qualityColor = ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].hex or 'ffffffff'

	print('|cffFFFF00=== AutoSell Debug ===|r')
	print(string.format('Item: |c%s%s|r (ID: %d)', qualityColor, name, itemID))
	print(string.format('Quality: %d (%s)', quality, _G['ITEM_QUALITY' .. quality .. '_DESC'] or 'Unknown'))
	print(string.format('Type: %s / %s', itemType or 'nil', itemSubType or 'nil'))
	print(string.format('iLevel: %s', iLevel and tostring(iLevel) or 'nil'))
	print(string.format('Vendor Price: %s', vendorPrice and tostring(vendorPrice) or '0'))
	print(string.format('Equip Slot: %s', equipSlot or 'none'))
	print(string.format('Expansion ID: %s', expacID and tostring(expacID) or 'nil'))
	print(string.format('Bind Type: %s', bindType and _G['BIND_' .. bindType] or 'nil'))
	print(string.format('Is Crafting Reagent: %s', isCraftingReagent and 'Yes' or 'No'))
	print(string.format('Actual Item Level: %s', actualItemLevel and tostring(actualItemLevel) or 'nil'))
	print(string.format('Preview Item Level: %s', previewLevel and tostring(previewLevel) or 'nil'))
	print(string.format('Sparse Item Level: %s', sparseItemLevel and tostring(sparseItemLevel) or 'nil'))

	-- Tooltip Analysis
	print('|cffFFFF00--- Tooltip Analysis ------|r')
	if actualBag and actualSlot then
		local success, tooltipText = pcall(function()
			Tooltip:SetOwner(UIParent, 'ANCHOR_NONE')
			Tooltip:SetBagItem(actualBag, actualSlot)

			local lines = {}
			for i = 1, Tooltip:NumLines() do
				local leftText = _G['AutoSellTooltipTextLeft' .. i]
				local rightText = _G['AutoSellTooltipTextRight' .. i]
				if leftText and leftText:GetText() then
					local lineText = leftText:GetText()
					if rightText and rightText:GetText() then
						lineText = lineText .. ' | ' .. rightText:GetText()
					end
					table.insert(lines, lineText)
				end
			end
			return table.concat(lines, '\n')
		end)

		if success and tooltipText then
			print('Tooltip Content:')
			for line in tooltipText:gmatch('[^\n]+') do
				print('  ' .. line)
			end
		else
			print('|cffFF0000ERROR:|r Could not read tooltip: ' .. tostring(tooltipText))
		end

		Tooltip:Hide()
	else
		print('|cffFFFFFF WARNING:|r Could not dump tooltip - item not found in bags')
	end

	-- Check each condition
	print('|cffFFFF00--- Sell Decision Process ------|r')

	-- Basic checks
	if not vendorPrice or vendorPrice == 0 then
		print('|cffFF0000BLOCKED:|r No vendor value (vendorPrice: ' .. tostring(vendorPrice) .. ')')
		return
	end

	-- Character blacklist
	if module.CharDB.Blacklist[itemID] then
		print('|cffFF0000BLOCKED:|r In character blacklist')
		return
	end

	-- Character whitelist
	print('Debug: Checking CharDB.Whitelist[' .. tostring(itemID) .. '] = ' .. tostring(module.CharDB.Whitelist[itemID]))
	if module.CharDB.Whitelist[itemID] then
		print('|cff00FF00ALLOWED:|r In character whitelist (overrides all rules)')
		print('|cff00FF00RESULT:|r Item should be marked with sell icon')

		-- Final decision check to verify the actual function using EXACT same parameters as marking/selling
		if actualBag and actualSlot then
			local itemInfo = C_Container.GetContainerItemInfo(actualBag, actualSlot)
			if itemInfo then
				local finalDecision = module:IsSellable(itemInfo.itemID, itemInfo.hyperlink, actualBag, actualSlot)
				print(string.format('|cffFFFFFF--- FINAL DECISION (exact call): %s ---|r', finalDecision and '|cff00FF00WILL SELL|r' or '|cffFF0000WILL NOT SELL|r'))
			end
		else
			print('|cffFFFF00WARNING:|r Could not find item in bags for exact test')
		end
		return
	end

	-- Quality checks
	local qualityBlocked = false
	if quality == 0 and not module.CurrentSettings.Gray then
		print('|cffFF0000BLOCKED:|r Gray quality disabled')
		qualityBlocked = true
	elseif quality == 1 and not module.CurrentSettings.White then
		print('|cffFF0000BLOCKED:|r White quality disabled')
		qualityBlocked = true
	elseif quality == 2 and not module.CurrentSettings.Green then
		print('|cffFF0000BLOCKED:|r Green quality disabled')
		qualityBlocked = true
	elseif quality == 3 and not module.CurrentSettings.Blue then
		print('|cffFF0000BLOCKED:|r Blue quality disabled')
		qualityBlocked = true
	elseif quality == 4 and not module.CurrentSettings.Purple then
		print('|cffFF0000BLOCKED:|r Purple quality disabled')
		qualityBlocked = true
	else
		print('|cff00FF00PASSED:|r Quality check')
	end

	-- iLevel check
	if iLevel and iLevel > module.CurrentSettings.MaxILVL then
		print(string.format('|cffFF0000BLOCKED:|r iLevel %d > max %d', iLevel, module.CurrentSettings.MaxILVL))
		qualityBlocked = true
	else
		print(string.format('|cff00FF00PASSED:|r iLevel check (max: %d)', module.CurrentSettings.MaxILVL))
	end

	if qualityBlocked then
		return
	end

	-- Gearset check (can't easily test without bag/slot)
	print('|cffFFFFFF SKIPPED:|r Gearset check (requires bag position)')

	-- Gear tokens check
	if quality == 4 and itemType == 'Miscellaneous' and itemSubType == 'Junk' and equipSlot == '' and not module.CurrentSettings.GearTokens then
		print('|cffFF0000BLOCKED:|r Gear tokens disabled')
		return
	else
		print('|cff00FF00PASSED:|r Gear token check')
	end

	-- Crafting check
	local isCraftingItem = (itemType == 'Gem' or itemType == 'Reagent' or itemType == 'Recipes' or itemType == 'Trade Goods' or itemType == 'Tradeskill')
		or (itemType == 'Miscellaneous' and itemSubType == 'Reagent')
		or (itemType == 'Item Enhancement')
		or isCraftingReagent

	if isCraftingItem and module.CurrentSettings.NotCrafting then
		print('|cffFF0000BLOCKED:|r Crafting items disabled (NotCrafting = ' .. tostring(module.CurrentSettings.NotCrafting) .. ')')
		return
	else
		print('|cff00FF00PASSED:|r Crafting check (NotCrafting = ' .. tostring(module.CurrentSettings.NotCrafting) .. ')')
	end

	-- Pet check
	if itemSubType == 'Companion Pets' then
		print('|cffFF0000BLOCKED:|r Companion pets never sold')
		return
	else
		print('|cff00FF00PASSED:|r Pet check')
	end

	-- Transmog tokens check
	if expacID == 9 and (itemType == 'Miscellaneous' or (itemType == 'Armor' and itemSubType == 'Miscellaneous')) and iLevel == 0 and quality >= 2 then
		print('|cffFF0000BLOCKED:|r Transmog token protection')
		return
	else
		print('|cff00FF00PASSED:|r Transmog token check')
	end

	-- Consumables check
	if module.CurrentSettings.NotConsumables and (itemType == 'Consumable' or itemSubType == 'Consumables') and quality ~= 0 then
		print('|cffFF0000BLOCKED:|r Consumables disabled (NotConsumables = ' .. tostring(module.CurrentSettings.NotConsumables) .. ')')
		return
	else
		print('|cff00FF00PASSED:|r Consumables check (NotConsumables = ' .. tostring(module.CurrentSettings.NotConsumables) .. ')')
	end

	-- Use text check
	if actualBag and actualSlot then
		local success, hasUseText = pcall(function()
			Tooltip:SetOwner(UIParent, 'ANCHOR_NONE')
			Tooltip:SetBagItem(actualBag, actualSlot)

			for i = 1, Tooltip:NumLines() do
				local line = _G['AutoSellTooltipTextLeft' .. i]
				if line and line:GetText() then
					local text = line:GetText():lower()
					if text:find('^use:') or text:find('^%s*use:') then
						Tooltip:Hide()
						return true
					end
				end
			end
			Tooltip:Hide()
			return false
		end)

		if success and hasUseText then
			print('|cffFF0000BLOCKED:|r Item has "Use:" text in tooltip (profession enhancement protection)')
			return
		else
			print('|cff00FF00PASSED:|r Use text check (no "Use:" found)')
		end
	else
		print('|cffFFFFFF SKIPPED:|r Use text check (item not found in bags)')
	end

	-- Profile blacklist checks
	if SUI:IsInTable(module.CurrentSettings.Blacklist.Items, itemID) then
		print('|cffFF0000BLOCKED:|r In profile item blacklist')
		return
	elseif SUI:IsInTable(module.CurrentSettings.Blacklist.Types, itemType) then
		print("|cffFF0000BLOCKED:|r Item type '" .. itemType .. "' in profile type blacklist")
		return
	elseif SUI:IsInTable(module.CurrentSettings.Blacklist.Types, itemSubType) then
		print("|cffFF0000BLOCKED:|r Item subtype '" .. itemSubType .. "' in profile type blacklist")
		return
	else
		print('|cff00FF00PASSED:|r Profile blacklist checks')
	end

	-- Final decision
	local finalDecision = module:IsSellable(itemID, link, actualBag, actualSlot)
	print(string.format('|cffFFFFFF--- FINAL DECISION: %s ---|r', finalDecision and '|cff00FF00WILL SELL|r' or '|cffFF0000WILL NOT SELL|r'))

	if finalDecision then
		print('|cff00FF00RESULT:|r Item should be marked with sell icon')
	else
		print('|cffFF0000RESULT:|r Item should NOT be marked with sell icon')
	end
end

---Handle Alt+Right Click on items to add/remove from character-specific lists
function module:HandleItemClick(link)
	if not IsAltKeyDown() then
		return
	end

	-- Control+Alt+Right Click for debugging
	if IsControlKeyDown() then
		module:DebugItemSellability(link)
		return
	end

	-- Extract item ID from hyperlink using string matching
	local itemID = tonumber(string.match(link, 'item:(%d+)'))
	if not itemID then
		return
	end

	local itemName, _, quality = C_Item.GetItemInfo(itemID)
	if not itemName then
		return
	end

	-- Find the actual bag/slot for this item to use exact same call as marking/selling
	local actualBag, actualSlot, actualItemInfo = nil, nil, nil
	for bag = 0, MAX_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
			if itemInfo and itemInfo.itemID == itemID then
				actualBag, actualSlot, actualItemInfo = bag, slot, itemInfo
				break
			end
		end
		if actualBag then
			break
		end
	end

	-- Check current state of this item
	local isInCharBlacklist = module.CharDB.Blacklist[itemID]
	local isInCharWhitelist = module.CharDB.Whitelist[itemID]
	local isSellable = false
	if actualItemInfo then
		isSellable = module:IsSellable(actualItemInfo.itemID, actualItemInfo.hyperlink, actualBag, actualSlot)
	end

	if isInCharWhitelist then
		-- State 1: In whitelist -> Move to blacklist
		module.CharDB.Whitelist[itemID] = nil
		module.CharDB.Blacklist[itemID] = true
		print(string.format('|cffFFFF00AutoSell:|r %s added to character blacklist (will not be sold)', ITEM_QUALITY_COLORS[quality].hex .. (itemName or 'Unknown') .. '|r'))
	elseif isInCharBlacklist then
		-- State 2: In blacklist -> Remove from all lists (use default behavior)
		module.CharDB.Blacklist[itemID] = nil
		print(string.format('|cffFFFF00AutoSell:|r %s removed from character lists (using default rules)', ITEM_QUALITY_COLORS[quality].hex .. (itemName or 'Unknown') .. '|r'))
	else
		-- State 3: Not in any character list -> Add to whitelist
		module.CharDB.Whitelist[itemID] = true
		print(string.format('|cffFFFF00AutoSell:|r %s added to character whitelist (will be sold)', ITEM_QUALITY_COLORS[quality].hex .. (itemName or 'Unknown') .. '|r'))
	end

	-- Refresh bag markings if enabled
	if module.CurrentSettings.ShowBagMarking and module.markItems then
		debugMsg('Refreshing bag markings after item list changes', 'debug')
		module.markItems()
	end

	-- Request refresh for Baganator if loaded
	if C_AddOns.IsAddOnLoaded('Baganator') and Baganator and Baganator.API then
		-- Request refresh so junk plugin can re-evaluate all items
		debugMsg('Requesting Baganator item button refresh', 'debug')
		Baganator.API.RequestItemButtonsRefresh()
	end
end

---Set up click handler for Alt+Right Click functionality
function module:SetupClickHandler()
	-- Hook the global modified item click handler
	hooksecurefunc('HandleModifiedItemClick', function(link)
		module:HandleItemClick(link)
	end)
end

function module:OnInitialize()
	-- Setup database with Configuration Override Pattern (sparse DB)
	SUI.DBM:SetupModule(module, DbDefaults, nil, { autoCalculateDepth = true })

	-- CharDB is not supported by SetupModule - handle manually
	module.CharDB = module.Database.char ---@type SUI.Module.AutoSell.CharDB
	if not module.CharDB.Whitelist then
		module.CharDB.Whitelist = {}
	end
	if not module.CharDB.Blacklist then
		module.CharDB.Blacklist = {}
	end

	-- One-time migration: strip old pre-populated defaults from DB
	if not module.DB._dbm_migrated then
		MigrateToDBM(module.DB)
		SUI.DBM:RefreshSettings(module)
	end

	-- One-time migration: strip seeded Blacklist from DB (now in DbDefaults/CurrentSettings)
	-- Check raw SV data to avoid AceDB wildcard/default resolution
	local profileKey = module.Database.keys.profile
	local rawProfile = module.Database.sv.profiles[profileKey]
	if rawProfile and rawProfile.Blacklist then
		rawProfile.Blacklist = nil
		SUI.DBM:RefreshSettings(module)
	end

	-- Setup logging system for AutoSell
	if SUI.logger then
		module.log = SUI.logger:RegisterCategory('AutoSell')
	end

	-- Handle potential item level squish after DB is initialized
	HandleItemLevelSquish()

	-- Set up Alt+Right Click handling
	module:SetupClickHandler()
end

function module:OnEnable()
	if not LoadedOnce then
		module:InitializeOptions()
	end
	if SUI:IsModuleDisabled(module) then
		return
	end

	-- Calculate MaxILVL from bag contents if still at default sentinel (0)
	if module.CurrentSettings.MaxILVL == 0 then
		local detectedILVL = highestILVL()
		if detectedILVL > 0 then
			module.DB.MaxILVL = math.floor(detectedILVL * 0.8)
			SUI.DBM:RefreshSettings(module)
			debugMsg('Set initial MaxILVL to ' .. module.CurrentSettings.MaxILVL .. ' (80% of highest: ' .. detectedILVL .. ')', 'info')
		end
	end

	module:RegisterEvent('MERCHANT_SHOW')
	module:RegisterEvent('MERCHANT_CLOSED')

	module:CreateMiniVendorPanels()

	-- Initialize bag marking system if enabled
	if module.CurrentSettings.ShowBagMarking then
		debugMsg('Initializing bag marking system', 'info')
		module:InitializeBagMarking()
	end

	-- Build blacklist cache on enable for better performance
	buildBlacklistLookup()

	LoadedOnce = true
end

function module:OnDisable()
	SUI:Print('Autosell disabled')
	module:UnregisterEvent('MERCHANT_SHOW')
	module:UnregisterEvent('MERCHANT_CLOSED')

	-- Cleanup bag marking system
	debugMsg('Cleaning up bag marking system', 'info')
	module:CleanupBagMarking()

	-- Hide and cleanup vendor panels
	if module.VendorPanels then
		for _, panel in pairs(module.VendorPanels) do
			if panel then
				panel:Hide()
				if panel.Panel then
					panel.Panel:Hide()
				end
			end
		end
	end
end
