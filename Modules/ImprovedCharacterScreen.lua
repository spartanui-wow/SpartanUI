---@class SUI
local SUI = SUI
local L = SUI.L
local module = SUI:NewModule('ImprovedCharacterScreen')
module.DisplayName = 'Improved Character Screen'
------------------------------------------
-- Upgrade quality tier data for character screen icons (Retail only)
local UPGRADE_CATEGORY_DATA = {
	[970] = { name = 'Explorer', tier = 1 },
	[971] = { name = 'Adventurer', tier = 2 },
	[972] = { name = 'Veteran', tier = 3 },
	[973] = { name = 'Champion', tier = 4 },
	[974] = { name = 'Hero', tier = 5 },
	[978] = { name = 'Myth', tier = 5 },
	[998] = { name = 'Awakened', tier = 5 },
}

---@class ImprovedCharacterScreenDB
---@field upgradeQualityIcons boolean
local DBDefaults = {
	position = 'BOTTOMRIGHT',
	fontSize = 14,
	color = {
		byQuality = false,
		fontColor = { 1, 1, 1, 1 },
	},
	upgradeQualityIcons = true,
}

local function ButtonOverlay(button)
	if not button.SUIOverlay then
		local overlayFrame = CreateFrame('FRAME', nil, button)
		overlayFrame:SetAllPoints()
		overlayFrame:SetFrameLevel(button:GetFrameLevel() + 1)
		button.SUIOverlay = overlayFrame
	end
end

---@param button any
---@param itemLevel number
---@param itemQuality Enum.ItemQuality
local function addiLvlDisplay(button, itemLevel, itemQuality)
	if not itemLevel or SUI:IsModuleDisabled(module) then
		if button.ilvlText then
			button.ilvlText:Hide()
		end
		return
	end

	if not button.ilvlText then
		ButtonOverlay(button)
		button.ilvlText = button.SUIOverlay:CreateFontString('$parentItemLevel', 'OVERLAY')
		button.ilvlText:Hide()
	end

	button.ilvlText:ClearAllPoints()
	button.ilvlText:SetPoint(module.DB.position)
	SUI.Font:Format(button.ilvlText, module.DB.fontSize, 'CharacterScreen')

	local hex = select(4, C_Item.GetItemQualityColor(itemQuality))

	button.ilvlText:SetFormattedText(string.format('|c%s%s|r', hex or '', itemLevel or ''))
	if not module.DB.color.byQuality then
		button.ilvlText:SetFormattedText(itemLevel or '')
		button.ilvlText:SetTextColor(unpack(module.DB.color.fontColor))
	end
	button.ilvlText:Show()
end

---@param button SUI.ICS.ItemButtonFrame
---@param item ItemMixin
local function addTimerunnerThreadCount(button, item)
	if string.match(item:GetItemName(), 'Cloak of Infinite Potential') and SUI:IsModuleEnabled(module) then
		local c, ThreadCount = { 0, 1, 2, 3, 4, 5, 6, 7, 148 }, 0
		for i = 1, 9 do
			ThreadCount = ThreadCount + C_CurrencyInfo.GetCurrencyInfo(2853 + c[i]).quantity
		end

		if not button.threadCount then
			ButtonOverlay(button)
			button.threadCount = button.SUIOverlay:CreateFontString('$parentItemLevel', 'OVERLAY')
			SUI.Font:Format(button.threadCount, module.DB.fontSize - 2, 'CharacterScreen')
			button.threadCount:ClearAllPoints()
			button.threadCount:SetPoint('LEFT', button.SUIOverlay, 'RIGHT', 2, 0)
		end
		button.threadCount:SetFormattedText('|cff00FF98Threads:|cffFFFFFF\n' .. SUI.Font:comma_value(ThreadCount))
	end
end

---@param button SUI.ICS.ItemButtonFrame
---@param itemLink string
local function addUpgradeQualityIcon(button, itemLink)
	if not SUI.IsRetail or not module.DB.upgradeQualityIcons or SUI:IsModuleDisabled(module) then
		if button.upgradeQualityIcon then
			button.upgradeQualityIcon:Hide()
		end
		return
	end

	if not itemLink or not C_Item or not C_Item.GetItemUpgradeInfo then
		if button.upgradeQualityIcon then
			button.upgradeQualityIcon:Hide()
		end
		return
	end

	local upgradeInfo = C_Item.GetItemUpgradeInfo(itemLink)
	if not upgradeInfo or not upgradeInfo.trackStringID then
		if button.upgradeQualityIcon then
			button.upgradeQualityIcon:Hide()
		end
		return
	end

	local categoryData = UPGRADE_CATEGORY_DATA[upgradeInfo.trackStringID]
	if not categoryData or not categoryData.tier then
		if button.upgradeQualityIcon then
			button.upgradeQualityIcon:Hide()
		end
		return
	end

	if not button.upgradeQualityIcon then
		ButtonOverlay(button)
		button.upgradeQualityIcon = button.SUIOverlay:CreateFontString(nil, 'OVERLAY', 'GameTooltipText')
		button.upgradeQualityIcon:SetPoint('TOPLEFT', button.SUIOverlay, 'TOPLEFT', -2, 2)
	end

	local icon = CreateAtlasMarkup('Professions-ChatIcon-Quality-Tier' .. categoryData.tier, 18, 18)
	button.upgradeQualityIcon:SetText(icon)
	button.upgradeQualityIcon:Show()
end

---@param button SUI.ICS.ItemButtonFrame
---@param unit UnitId
local function UpdateItemSlotButton(button, unit)
	if button.ilvlText then
		button.ilvlText:Hide()
	end
	if button.upgradeQualityIcon then
		button.upgradeQualityIcon:Hide()
	end

	local slotID = button:GetID()

	if slotID >= INVSLOT_FIRST_EQUIPPED and slotID <= INVSLOT_LAST_EQUIPPED then
		local item
		local itemLink = GetInventoryItemLink(unit, slotID)
		if unit == 'player' then
			item = Item:CreateFromEquipmentSlot(slotID)
		else
			local itemID = GetInventoryItemID(unit, slotID)
			if itemLink or itemID then
				item = itemLink and Item:CreateFromItemLink(itemLink) or Item:CreateFromItemID(itemID)
			end
		end

		if not item or item:IsItemEmpty() then
			return
		end

		item:ContinueOnItemLoad(function()
			-- Add item level text to the overlay frame
			addiLvlDisplay(button, item:GetCurrentItemLevel(), item:GetItemQuality())

			-- Add upgrade quality tier icon
			addUpgradeQualityIcon(button, itemLink)

			--Add Text next to item if its Cloak of Infinite Potential
			if SUI:IsTimerunner() then
				addTimerunnerThreadCount(button, item)
			end
		end)
	end
end

---@param button SUI.ICS.ItemButtonFrame
local function UpdateSpellFlyout(button)
	if button.ilvlText then
		button.ilvlText:Hide()
	end

	if not button.location or button.location >= EQUIPMENTFLYOUT_FIRST_SPECIAL_LOCATION then
		return
	end

	local data = EquipmentManager_GetLocationData(button.location)
	local item
	if data.isBags then
		item = Item:CreateFromBagAndSlot(data.bag, data.slot)
	elseif not data.isPlayer then
		item = Item:CreateFromEquipmentSlot(data.slot)
	else
		local itemID = EquipmentManager_GetItemInfoByLocation(button.location)
		if itemID then
			item = Item:CreateFromItemID(itemID)
		end
	end

	--Make sure we found the item
	if not item or item:IsItemEmpty() then
		return
	end

	item:ContinueOnItemLoad(function()
		local _, _, _, _, _, itemClass, itemSubClass = C_Item.GetItemInfoInstant(item:GetItemID())
		if not (itemClass == Enum.ItemClass.Weapon or itemClass == Enum.ItemClass.Armor or (itemClass == Enum.ItemClass.Gem and itemSubClass == Enum.ItemGemSubclass.Artifactrelic)) then
			return
		end
		local quality = item:GetItemQuality()
		addiLvlDisplay(button, item:GetCurrentItemLevel(), quality)
	end)
end

local function Options()
	---@type AceConfig.OptionsTable
	local OptTable = {
		name = module.DisplayName,
		type = 'group',
		disabled = function()
			return SUI:IsModuleDisabled(module)
		end,
		get = function(info)
			return module.DB[info[#info]]
		end,
		set = function(info, value)
			module.DB[info[#info]] = value
		end,
		args = {
			display = {
				type = 'group',
				name = 'Display',
				inline = true,
				order = 1,
				args = {
					fontSize = {
						type = 'range',
						name = 'iLvL Font Size',
						min = 5,
						max = 24,
						step = 1,
					},
				},
			},
			Position = {
				type = 'group',
				name = 'Position',
				inline = true,
				order = 2,
				args = {
					position = {
						type = 'select',
						name = 'iLvL Position',
						values = {
							['TOPLEFT'] = 'Top Left',
							['TOP'] = 'Top',
							['TOPRIGHT'] = 'Top Right',
							['LEFT'] = 'Left',
							['CENTER'] = 'Center',
							['RIGHT'] = 'Right',
							['BOTTOMLEFT'] = 'Bottom Left',
							['BOTTOM'] = 'Bottom',
							['BOTTOMRIGHT'] = 'Bottom Right',
						},
					},
				},
			},
			upgradeQualityIcons = {
				type = 'toggle',
				name = L['Show Upgrade Quality Icons on Character Screen'],
				desc = L['Display quality tier icons on equipped items in the character screen'],
				order = 3,
				width = 'full',
				hidden = function()
					return not SUI.IsRetail
				end,
			},
			color = {
				type = 'group',
				name = 'Color settings',
				inline = true,
				order = 4,
				get = function(info)
					return module.DB.color[info[#info]]
				end,
				set = function(info, value)
					module.DB.color[info[#info]] = value
				end,
				args = {
					byQuality = {
						type = 'toggle',
						name = 'Color by Quality',
						desc = 'Color the iLvL by the item quality',
					},
					fontColor = {
						type = 'color',
						name = 'iLvL Font Color',
						hasAlpha = true,
						disabled = function()
							return module.DB.color.byQuality
						end,
						get = function(info)
							return unpack(module.DB.color[info[#info]])
						end,
						set = function(info, r, g, b, a)
							module.DB.color[info[#info]] = { r, g, b, a }
						end,
					},
				},
			},
		},
	}

	SUI.Options:AddOptions(OptTable, 'ImprovedCharacterScreen', nil)
end

function module:OnInitialize()
	module.Database = SUI.SpartanUIDB:RegisterNamespace('ImprovedCharacterScreen', { profile = DBDefaults })
	---@type ImprovedCharacterScreenDB
	module.DB = module.Database.profile
end

function module:OnEnable()
	Options()
	if SUI:IsModuleDisabled(module) then
		return
	end

	--Hook Character frame
	hooksecurefunc('PaperDollItemSlotButton_Update', function(button)
		UpdateItemSlotButton(button, 'player')
	end)

	--Equit item flyout (retail only)
	if EquipmentFlyout_DisplayButton then
		hooksecurefunc('EquipmentFlyout_DisplayButton', function(button)
			UpdateSpellFlyout(button)
		end)
	end
	-- Hook Inspect frame
	EventUtil.ContinueOnAddOnLoaded('Blizzard_InspectUI', function()
		hooksecurefunc('InspectPaperDollItemSlotButton_Update', function(button)
			UpdateItemSlotButton(button, InspectFrame.unit or 'target')
		end)
	end)
end

function module:OnDisable() end

---@class SUI.ICS.ItemButtonFrame : Frame
---@field ilvlText fontstring
---@field upgradeQualityIcon fontstring
---@field location number
