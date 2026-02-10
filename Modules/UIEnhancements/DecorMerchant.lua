local SUI, L = SUI, SUI.L
---@class SUI.Module.UIEnhancements
local module = SUI:GetModule('UIEnhancements')
----------------------------------------------------------------------------------------------------

-- Housing Decoration Vendor NPC IDs
-- GUID format: [typeStr]-[typeID]-[serverID]-[instanceID]-[zoneUID]-[npcID]-[spawnUID]
local DECOR_VENDOR_NPC_ID = {
	-- Founder's Point
	['255213'] = true, -- Faarden the Builder
	['255203'] = true, -- Xiao Dan
	['255216'] = true, -- Balen Starfinder
	['255218'] = true, -- Argan Hammerfist
	['248854'] = true, -- The Last Architect
	['255221'] = true, -- Trevor Grenner
	['255222'] = true, -- High Tides Ren
	['255228'] = true, -- Len Splinthoof
	['255230'] = true, -- Yen Malone

	-- Razorwind Shores
	['255298'] = true, -- Jehzar Starfall
	['255299'] = true, -- Lefton Farrer
	['255301'] = true, -- Botanist Boh'an
	['253596'] = true, -- The Last Architect
	['255297'] = true, -- Shon'ja
	['255278'] = true, -- Gronthul
	['255325'] = true, -- High Tides Ren
	['255326'] = true, -- Len Splinthoof
	['255319'] = true, -- Yen Malone
}

local BULK_INTERVAL = 0.125 -- 125ms between purchases
local BULK_MAX = 99

local isInMerchantUI = false
local eventFrame = nil
local staticPopupHooked = false

---Parse a GUID to extract the NPC ID
---@param guid string
---@return string|nil npcId
local function ParseNPCIdFromGUID(guid)
	if not guid or SUI.BlizzAPI.issecretvalue(guid) then
		return nil
	end
	-- GUID format: Creature-0-serverID-instanceID-zoneUID-npcID-spawnUID
	local npcId = select(6, strsplit('-', guid))
	return npcId
end

---Check if we're interacting with a decoration merchant
---@return boolean
local function IsInteractingWithDecorMerchant()
	local targetGUID = UnitGUID('target')
	if not targetGUID or SUI.BlizzAPI.issecretvalue(targetGUID) then
		return false
	end

	local npcId = ParseNPCIdFromGUID(targetGUID)
	return npcId and DECOR_VENDOR_NPC_ID[npcId] or false
end

---Check if feature is active (enabled and at decor merchant)
---@return boolean
local function IsDecorMerchantActive()
	local DB = module:GetDB()
	if not DB.decorMerchantBulkBuy then
		return false
	end
	return IsInteractingWithDecorMerchant()
end

---Check if we're in merchant state and at decor vendor
---@return boolean
local function IsInMerchantState()
	return isInMerchantUI and IsDecorMerchantActive()
end

---Purchase items with throttling
---@param itemButton Frame
---@param quantity number
local function BulkPurchaseItem(itemButton, quantity)
	local index = itemButton:GetID()
	for i = 1, quantity do
		C_Timer.After(i * BULK_INTERVAL, function()
			if not IsInMerchantState() then
				return
			end
			BuyMerchantItem(index, 1)
		end)
	end
end

---Open the stack split UI for bulk purchasing
---@param itemButton Frame
---@param maxQuantity? number
local function OpenBulkPurchaseUI(itemButton, maxQuantity)
	maxQuantity = maxQuantity or BULK_MAX

	local originalSplitStack = itemButton.SplitStack
	itemButton.SplitStack = function(button, split)
		if split > 0 then
			BulkPurchaseItem(button, split)
		end
		itemButton.SplitStack = originalSplitStack
	end

	StackSplitFrame:OpenStackSplitFrame(maxQuantity, itemButton, 'BOTTOMLEFT', 'TOPLEFT', 1)
end

---Setup hooks on merchant item buttons
local function SetupMerchantButtons()
	for i = 1, MERCHANT_ITEMS_PER_PAGE do
		local itemButton = _G['MerchantItem' .. i .. 'ItemButton']
		if itemButton and not itemButton.__suiDecorMerchantInitialized then
			itemButton:HookScript('OnClick', function(self, button)
				if not IsDecorMerchantActive() then
					return
				end

				if IsShiftKeyDown() and button == 'RightButton' then
					local maxStack = GetMerchantItemMaxStack(self:GetID())
					if maxStack == 1 then
						OpenBulkPurchaseUI(self, BULK_MAX)
					end
				end
			end)
			itemButton.__suiDecorMerchantInitialized = true
		end
	end
end

---Hook StaticPopup_Show to auto-confirm high cost items at decor merchants
local function SetupStaticPopupHook()
	if staticPopupHooked then
		return
	end

	hooksecurefunc('StaticPopup_Show', function(which)
		if which ~= 'CONFIRM_HIGH_COST_ITEM' then
			return
		end
		if not IsDecorMerchantActive() then
			return
		end

		local dialog = StaticPopup_FindVisible(which)
		if dialog then
			dialog:GetButton1():Click() -- Accept button
		end
	end)

	staticPopupHooked = true
end

---Handle merchant events
---@param event string
local function OnEvent(_, event)
	if event == 'MERCHANT_SHOW' then
		isInMerchantUI = true
		if IsDecorMerchantActive() then
			SetupMerchantButtons()
		end
	else
		isInMerchantUI = false
	end
end

function module:InitializeDecorMerchant()
	local DB = module:GetDB()
	if not DB.decorMerchantBulkBuy then
		return
	end

	-- Create event frame if needed
	if not eventFrame then
		eventFrame = CreateFrame('Frame')
		eventFrame:SetScript('OnEvent', OnEvent)
	end

	eventFrame:RegisterEvent('MERCHANT_SHOW')
	eventFrame:RegisterEvent('MERCHANT_CLOSED')

	-- Setup static popup hook
	SetupStaticPopupHook()
end

function module:RestoreDecorMerchant()
	if eventFrame then
		eventFrame:UnregisterAllEvents()
	end
	isInMerchantUI = false
end

function module:ApplyDecorMerchantSettings()
	local DB = module:GetDB()
	if DB.decorMerchantBulkBuy then
		module:InitializeDecorMerchant()
	else
		module:RestoreDecorMerchant()
	end
end
