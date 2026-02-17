local SUI, L, print = SUI, SUI.L, SUI.print
---@class SUI.Module.AutoSell : SUI.Module
local module = SUI:GetModule('AutoSell')

-- Configuration constants
local MAX_BAG_SLOTS = 12 -- Maximum number of bag slots to scan (0-12 covers all normal bags plus extras)

local buildItemList, buildCharacterList, OptionTable

local function SetupPage()
	-- Access LibAT from global namespace (not LibStub)
	local LibAT = _G.LibAT

	---@type SUI.SetupWizard.PageData
	local PageData = {
		ID = 'Autosell',
		Name = L['Auto sell'],
		SubTitle = L['Auto sell'],
		Desc1 = L['Automatically vendor items when you visit a merchant.'],
		Desc2 = L['Crafting, consumables, and gearset items will not be sold by default.'],
		RequireDisplay = module.CurrentSettings.FirstLaunch,
		Display = function()
			local SUI_Win = SUI.Setup.window.content

			--Container
			local AutoSell = CreateFrame('Frame', nil)
			AutoSell:SetParent(SUI_Win)
			AutoSell:SetAllPoints(SUI_Win)

			if SUI:IsModuleDisabled('AutoSell') then
				AutoSell.lblDisabled = LibAT.UI.CreateLabel(AutoSell, 'Disabled', 'GameFontNormalLarge')
				AutoSell.lblDisabled:SetPoint('CENTER', AutoSell)
				-- Attaching
				SUI_Win.AutoSell = AutoSell
			else
				-- Quality Selling Options
				AutoSell.SellGray = LibAT.UI.CreateCheckbox(AutoSell, L['Sell gray'])
				AutoSell.SellWhite = LibAT.UI.CreateCheckbox(AutoSell, L['Sell white'])
				AutoSell.SellGreen = LibAT.UI.CreateCheckbox(AutoSell, L['Sell green'])
				AutoSell.SellBlue = LibAT.UI.CreateCheckbox(AutoSell, L['Sell blue'])
				AutoSell.SellPurple = LibAT.UI.CreateCheckbox(AutoSell, L['Sell purple'])

				-- Max iLVL
				AutoSell.iLVLDesc = LibAT.UI.CreateLabel(AutoSell, L['Maximum iLVL to sell'])
				AutoSell.iLVLLabel = LibAT.UI.CreateNumericBox(AutoSell, 80, 20, 1, module.CurrentSettings.MaximumiLVL)
				AutoSell.iLVLLabel:SetValue(module.CurrentSettings.MaxILVL)
				AutoSell.iLVLLabel:SetScript('OnTextChanged', function(self)
					local value = self:GetValue()
					if value and AutoSell.iLVLSlider then
						if math.floor(value) ~= math.floor(AutoSell.iLVLSlider:GetValue()) then
							AutoSell.iLVLSlider:SetValue(math.floor(value))
						end
					end
				end)

				AutoSell.iLVLSlider = LibAT.UI.CreateSlider(AutoSell, module.CurrentSettings.MaximumiLVL, 20, 1, module.CurrentSettings.MaximumiLVL, 1)
				AutoSell.iLVLSlider:SetValue(module.CurrentSettings.MaxILVL)
				AutoSell.iLVLSlider:SetScript('OnValueChanged', function(self, value)
					if AutoSell.iLVLLabel then
						if math.floor(AutoSell.iLVLLabel:GetValue()) ~= math.floor(value) then
							AutoSell.iLVLLabel:SetValue(math.floor(value))
						end
					end
				end)

				-- AutoRepair
				AutoSell.AutoRepair = LibAT.UI.CreateCheckbox(AutoSell, L['Auto repair'])

				-- Positioning using SUI.UI helpers
				SUI.UI.GlueTop(AutoSell.SellGray, SUI_Win, 0, -30)
				SUI.UI.GlueBelow(AutoSell.SellWhite, AutoSell.SellGray, 0, -5)
				SUI.UI.GlueBelow(AutoSell.SellGreen, AutoSell.SellWhite, 0, -5)
				SUI.UI.GlueBelow(AutoSell.SellBlue, AutoSell.SellGreen, 0, -5)
				SUI.UI.GlueBelow(AutoSell.SellPurple, AutoSell.SellBlue, 0, -5)
				SUI.UI.GlueBelow(AutoSell.iLVLDesc, AutoSell.SellPurple, 0, -5)
				SUI.UI.GlueBelow(AutoSell.iLVLSlider, AutoSell.iLVLDesc, -40, -5)
				SUI.UI.GlueRight(AutoSell.iLVLLabel, AutoSell.iLVLSlider, 2, 0)
				SUI.UI.GlueBelow(AutoSell.AutoRepair, AutoSell.iLVLSlider, 40, -5)

				-- Attaching
				SUI_Win.AutoSell = AutoSell

				-- Defaults
				AutoSell.SellGray:SetChecked(module.CurrentSettings.Gray)
				AutoSell.SellWhite:SetChecked(module.CurrentSettings.White)
				AutoSell.SellGreen:SetChecked(module.CurrentSettings.Green)
				AutoSell.SellBlue:SetChecked(module.CurrentSettings.Blue)
				AutoSell.SellPurple:SetChecked(module.CurrentSettings.Purple)
				AutoSell.AutoRepair:SetChecked(module.CurrentSettings.AutoRepair)
				AutoSell.iLVLLabel:SetValue(module.CurrentSettings.MaxILVL)
			end
		end,
		Next = function()
			if SUI:IsModuleEnabled('AutoSell') then
				local SUI_Win = SUI.Setup.window.content.AutoSell

				module.DB.Gray = (SUI_Win.SellGray:GetChecked() == true or false)
				module.DB.White = (SUI_Win.SellWhite:GetChecked() == true or false)
				module.DB.Green = (SUI_Win.SellGreen:GetChecked() == true or false)
				module.DB.Blue = (SUI_Win.SellBlue:GetChecked() == true or false)
				module.DB.Purple = (SUI_Win.SellPurple:GetChecked() == true or false)
				module.DB.AutoRepair = (SUI_Win.AutoRepair:GetChecked() == true or false)
				module.DB.MaxILVL = SUI_Win.iLVLLabel:GetValue()
			end
			module.DB.FirstLaunch = false
			SUI.DBM:RefreshSettings(module)
		end,
		Skip = function()
			module.DB.FirstLaunch = false
			SUI.DBM:RefreshSettings(module)
		end,
	}
	SUI.Setup:AddPage(PageData)
end

local function BuildOptions()
	local itemCache = {}
	local eventFrame = CreateFrame('Frame')
	eventFrame:RegisterEvent('GET_ITEM_INFO_RECEIVED')
	eventFrame:SetScript('OnEvent', function(_, event, itemID, success)
		if event == 'GET_ITEM_INFO_RECEIVED' and success then
			eventFrame:UnregisterEvent('GET_ITEM_INFO_RECEIVED')
			local itemLink = C_Item.GetItemInfo(itemID)
			if itemLink then
				itemCache[itemID] = itemLink
				-- Call buildItemList to refresh the list
				buildItemList('Items')
			end
		end
	end)

	buildItemList = function(mode)
		local listOpt = OptionTable.args[mode].args.list.args
		table.wipe(listOpt)

		for itemId, entry in pairs(module.CurrentSettings.Blacklist[mode]) do
			-- Skip entries explicitly removed by user (false = user deleted a default)
			if entry ~= false then
				local label

				if type(entry) == 'number' then
					-- Check the cache first
					local itemLink = itemCache[entry]
					if itemLink then
						-- If the item link is in the cache, use it
						label = itemLink .. ' (' .. entry .. ')'
					else
						-- Request item info which may return nil initially
						local _, itemLink2 = C_Item.GetItemInfo(entry)
						if itemLink2 then
							-- If the item link is available, use it
							label = itemLink2 .. ' (' .. entry .. ')'
							itemCache[entry] = itemLink2 -- Cache it
						else
							-- If the item link is not available, display an error and the item ID in Red
							label = '|cffff0000' .. entry .. ' NOT FOUND|r'
							-- Request the server to send the item info
							eventFrame:RegisterEvent('GET_ITEM_INFO_RECEIVED')
						end
					end
				else
					-- If the entry is not a number, use it directly
					label = entry
				end

				listOpt[itemId .. 'label'] = {
					type = 'description',
					width = 'double',
					fontSize = 'medium',
					order = itemId,
					name = label,
				}
				listOpt[tostring(itemId)] = {
					type = 'execute',
					name = L['Delete'],
					width = 'half',
					order = itemId + 0.05,
					func = function(info)
						module.DB.Blacklist[mode][itemId] = false
						SUI.DBM:RefreshSettings(module)
						module:InvalidateBlacklistCache()
						buildItemList(mode)
					end,
				}
			end
		end
	end

	buildCharacterList = function(mode)
		local listType = mode == 'Whitelist' and 'CharacterWhitelist' or 'CharacterBlacklist'
		local listOpt = OptionTable.args[listType].args.list.args
		table.wipe(listOpt)

		local charList = module.CharDB[mode]
		local orderCounter = 1
		for itemId, enabled in pairs(charList) do
			if enabled then
				local itemName, _, itemQuality = C_Item.GetItemInfo(itemId)
				local label
				if itemName then
					local qualityColor = ITEM_QUALITY_COLORS[itemQuality] and ITEM_QUALITY_COLORS[itemQuality].hex or 'ffffffff'
					label = string.format('|c%s%s|r (%d)', qualityColor, itemName, itemId)
				else
					label = string.format('Item ID: %d (not cached)', itemId)
				end

				listOpt[itemId .. 'label'] = {
					type = 'description',
					width = 'double',
					fontSize = 'medium',
					order = orderCounter,
					name = label,
				}
				listOpt[tostring(itemId)] = {
					type = 'execute',
					name = L['Delete'],
					width = 'half',
					order = orderCounter + 0.1,
					func = function(info)
						module.CharDB[mode][itemId] = nil
						module:InvalidateBlacklistCache()
						buildCharacterList(mode)
					end,
				}
				orderCounter = orderCounter + 1
			end
		end
	end

	--@type AceConfig.OptionsTable
	OptionTable = {
		type = 'group',
		name = L['Auto sell'],
		get = function(info)
			return module.CurrentSettings[info[#info]]
		end,
		set = function(info, val)
			module.DB[info[#info]] = val
			SUI.DBM:RefreshSettings(module)
		end,
		disabled = function()
			return SUI:IsModuleDisabled(module)
		end,
		childGroups = 'tab',
	}

	OptionTable.args = {
		NotCrafting = {
			name = L["Don't sell crafting items"],
			type = 'toggle',
			order = 1,
			width = 'full',
		},
		NotConsumables = {
			name = L["Don't sell consumables"],
			type = 'toggle',
			order = 2,
			width = 'full',
		},
		NotInGearset = {
			name = L["Don't sell items in a equipment set"],
			type = 'toggle',
			order = 3,
			width = 'full',
		},
		GearTokens = {
			name = L['Sell tier tokens'],
			type = 'toggle',
			order = 4,
			width = 'full',
		},
		MaxILVL = {
			name = L['Maximum iLVL to sell'],
			type = 'range',
			order = 10,
			width = 'full',
			min = 1,
			max = module.CurrentSettings.MaximumiLVL,
			step = 1,
		},
		Gray = {
			name = L['Sell gray'],
			type = 'toggle',
			order = 20,
			width = 'double',
		},
		White = {
			name = L['Sell white'],
			type = 'toggle',
			order = 21,
			width = 'double',
		},
		Green = {
			name = L['Sell green'],
			type = 'toggle',
			order = 22,
			width = 'double',
		},
		Blue = {
			name = L['Sell blue'],
			type = 'toggle',
			order = 23,
			width = 'double',
		},
		Purple = {
			name = L['Sell purple'],
			type = 'toggle',
			order = 24,
			width = 'double',
		},
		line1 = { name = '', type = 'header', order = 200 },
		AutoRepair = {
			name = L['Auto repair'],
			type = 'toggle',
			order = 201,
		},
		UseGuildBankRepair = {
			name = L['Use guild bank repair if possible'],
			type = 'toggle',
			order = 202,
		},
		ShowBagMarking = {
			name = 'Show bag item marking',
			desc = 'Show icons on items in your bags that will be auto-sold',
			type = 'toggle',
			order = 203,
			set = function(info, val)
				module.DB[info[#info]] = val
				SUI.DBM:RefreshSettings(module)
				if val then
					module:InitializeBagMarking()
				else
					module:CleanupBagMarking()
				end
			end,
		},
		Items = {
			type = 'group',
			name = 'Blacklisted Items',
			order = 40,
			args = {
				desc = {
					name = 'Blacklisted items will not be sold',
					type = 'description',
					order = 1,
				},
				create = {
					name = 'Add Item ID',
					type = 'input',
					order = 2,
					width = 'full',
					set = function(info, input)
						--Check that the input is a valid number
						local itemID = tonumber(input)
						if not itemID then
							SUI:Print('Invalid item ID: ' .. input)
							return
						end
						--Check that the inputted nmumber is a valid item
						local itemLink = C_Item.GetItemInfo(itemID)
						if not itemLink then
							SUI:Print('Could not load item ID: ' .. input .. ' this can happen if the item is not in your cache, please try again in a few seconds.')
							return
						end
						-- Add the item ID to the blacklist
						module.DB.Blacklist.Items[#info - 1] = input
						SUI.DBM:RefreshSettings(module)
						module:InvalidateBlacklistCache()
						buildItemList(info[#info - 1])
					end,
				},
				list = {
					order = 3,
					type = 'group',
					inline = true,
					name = 'Item list',
					args = {},
				},
			},
		},
		Types = {
			type = 'group',
			name = 'Blacklisted Types',
			order = 50,
			args = {
				desc = {
					name = 'Blacklisted types will not be sold',
					type = 'description',
					order = 1,
				},
				create = {
					name = 'Add Type',
					type = 'input',
					order = 2,
					width = 'full',
					set = function(info, input)
						--Check that the input is a valid Enum.ItemClass
						local itemClass = Enum.ItemClass[input]
						if not itemClass then
							SUI:Print('Invalid item class: ' .. input)
							return
						end
						-- Add the item class to the blacklist
						module.DB.Blacklist.Types[#info - 1] = input
						SUI.DBM:RefreshSettings(module)
						module:InvalidateBlacklistCache()
						buildItemList(info[#info - 1])
					end,
				},
				list = {
					order = 3,
					type = 'group',
					inline = true,
					name = 'Type list',
					args = {},
				},
			},
		},
		CharacterWhitelist = {
			type = 'group',
			name = 'Character Whitelist',
			order = 60,
			get = function(info)
				return module.CharDB[info[#info]]
			end,
			set = function(info, val)
				module.CharDB[info[#info]] = val
			end,
			args = {
				desc = {
					name = 'Character-specific whitelist items will always be sold (overrides all other settings for this character only)',
					type = 'description',
					order = 1,
				},
				create = {
					name = 'Add Item ID',
					type = 'input',
					order = 2,
					width = 'full',
					set = function(info, input)
						local itemID = tonumber(input)
						if not itemID then
							SUI:Print('Invalid item ID: ' .. input)
							return
						end
						local itemLink = C_Item.GetItemInfo(itemID)
						if not itemLink then
							SUI:Print('Could not load item ID: ' .. input .. ' this can happen if the item is not in your cache, please try again in a few seconds.')
							return
						end
						module.CharDB.Whitelist[itemID] = true
						module:InvalidateBlacklistCache()
						buildCharacterList('Whitelist')
					end,
				},
				list = {
					order = 3,
					type = 'group',
					inline = true,
					name = 'Whitelisted items',
					args = {},
				},
			},
		},
		CharacterBlacklist = {
			type = 'group',
			name = 'Character Blacklist',
			order = 70,
			get = function(info)
				return module.CharDB[info[#info]]
			end,
			set = function(info, val)
				module.CharDB[info[#info]] = val
			end,
			args = {
				desc = {
					name = 'Character-specific blacklist items will never be sold (overrides all other settings for this character only)',
					type = 'description',
					order = 1,
				},
				create = {
					name = 'Add Item ID',
					type = 'input',
					order = 2,
					width = 'full',
					set = function(info, input)
						local itemID = tonumber(input)
						if not itemID then
							SUI:Print('Invalid item ID: ' .. input)
							return
						end
						local itemLink = C_Item.GetItemInfo(itemID)
						if not itemLink then
							SUI:Print('Could not load item ID: ' .. input .. ' this can happen if the item is not in your cache, please try again in a few seconds.')
							return
						end
						module.CharDB.Blacklist[itemID] = true
						module:InvalidateBlacklistCache()
						buildCharacterList('Blacklist')
					end,
				},
				list = {
					order = 3,
					type = 'group',
					inline = true,
					name = 'Blacklisted items',
					args = {},
				},
			},
		},
	}
	buildItemList('Items')
	buildItemList('Types')
	buildCharacterList('Whitelist')
	buildCharacterList('Blacklist')
	SUI.Options:AddOptions(OptionTable, 'AutoSell')
end

function module:CreateMiniVendorPanels()
	-- Create quick access panel for vendor windows
	local IsCollapsed = true
	-- Access LibAT from global namespace (not LibStub)
	local LibAT = _G.LibAT

	-- LibAT is required for vendor panels
	if not LibAT or not LibAT.UI then
		SUI:Print('AutoSell vendor panels require Libs-AddonTools')
		return
	end

	-- Store panel references so we can hide them on disable
	if not module.VendorPanels then
		module.VendorPanels = {}
	end

	for _, v in ipairs({ 'MerchantFrame' }) do
		local panelWidth = _G[v]:GetWidth() / 3

		-- Create panel using native frame (StdUi:Panel replacement)
		local OptionsPopdown = CreateFrame('Frame', nil, _G[v], 'BackdropTemplate')
		OptionsPopdown:SetSize(panelWidth, 20)
		OptionsPopdown:SetBackdrop({
			bgFile = 'Interface\\Tooltips\\UI-Tooltip-Background',
			edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border',
			tile = true,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		OptionsPopdown:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
		OptionsPopdown:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
		OptionsPopdown:SetScale(0.95)
		-- Position on bottom right, avoiding the tabs on the bottom left
		OptionsPopdown:SetPoint('TOPRIGHT', _G[v], 'BOTTOMRIGHT', -5, -2)
		OptionsPopdown.title = LibAT.UI.CreateLabel(OptionsPopdown, '|cffffffffSpartan|cffe21f1fUI|r AutoSell', 'GameFontNormalSmall')
		OptionsPopdown.title:SetPoint('CENTER')

		-- Function to count sellable items and update sell button
		local function UpdateSellButton()
			if not OptionsPopdown.Panel or not OptionsPopdown.Panel.options then
				return
			end

			local sellableCount = 0
			local blizzardCount = 0

			-- Count items that would be sold with current settings
			for bag = 0, MAX_BAG_SLOTS do
				for slot = 1, C_Container.GetContainerNumSlots(bag) do
					local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
					if itemInfo then
						-- Check if Blizzard will sell this item
						local _, _, quality = C_Item.GetItemInfo(itemInfo.itemID)
						if module:WouldBlizzardSell(itemInfo.itemID, quality) and module.CurrentSettings.Gray then
							blizzardCount = blizzardCount + 1
						else
							-- Use pcall to safely handle any tooltip-related errors
							local success, result = pcall(module.IsSellable, module, itemInfo.itemID, itemInfo.hyperlink, bag, slot)
							if success and result then
								sellableCount = sellableCount + 1
							end
						end
					end
				end
			end

			local sellButton = OptionsPopdown.Panel.options.sellItemsButton
			if sellButton then
				local totalItems = sellableCount + blizzardCount
				if totalItems > 0 then
					if blizzardCount > 0 and sellableCount > 0 then
						sellButton:SetText('Sell ' .. totalItems .. ' Items (' .. blizzardCount .. ' + ' .. sellableCount .. ')')
					elseif blizzardCount > 0 then
						sellButton:SetText('Sell ' .. blizzardCount .. ' Junk Items')
					else
						sellButton:SetText('Sell ' .. sellableCount .. ' Items')
					end
					sellButton:Show()
				else
					sellButton:Hide()
				end
			end
		end

		-- Function to refresh panel values from database
		local function RefreshPanelValues()
			if OptionsPopdown.Panel and OptionsPopdown.Panel.options then
				local opts = OptionsPopdown.Panel.options

				-- Update checkboxes
				if opts.AutoRepair then
					opts.AutoRepair:SetChecked(module.CurrentSettings.AutoRepair)
				end
				if opts.Green then
					opts.Green:SetChecked(module.CurrentSettings.Green)
				end
				if opts.Blue then
					opts.Blue:SetChecked(module.CurrentSettings.Blue)
				end
				if opts.Purple then
					opts.Purple:SetChecked(module.CurrentSettings.Purple)
				end

				-- Update slider and input values
				if opts.MaxILVLSlider then
					opts.MaxILVLSlider:SetValue(module.CurrentSettings.MaxILVL)
				end
				if opts.MaxILVLInput and opts.MaxILVLInput.SetValue then
					opts.MaxILVLInput:SetValue(module.CurrentSettings.MaxILVL)
				end

				-- Update slider maximum if it has changed
				if opts.MaxILVLSlider and opts.MaxILVLSlider.SetMaxValue then
					opts.MaxILVLSlider:SetMaxValue(module.CurrentSettings.MaximumiLVL)
				end
				if opts.MaxILVLInput and opts.MaxILVLInput.SetMaxValue then
					opts.MaxILVLInput:SetMaxValue(module.CurrentSettings.MaximumiLVL)
				end
			end
		end

		-- Make the title clickable to toggle the panel
		OptionsPopdown.title:EnableMouse(true)
		OptionsPopdown.title:SetScript('OnMouseUp', function()
			-- Refresh values from database before showing/hiding
			RefreshPanelValues()

			if OptionsPopdown.Panel:IsVisible() then
				OptionsPopdown.Panel:Hide()
				IsCollapsed = true
			else
				OptionsPopdown.Panel:Show()
				IsCollapsed = false
			end
		end)

		OptionsPopdown:HookScript('OnShow', function()
			-- Refresh all values from the database when the panel is shown
			RefreshPanelValues()

			if IsCollapsed then
				OptionsPopdown.Panel:Hide()
			else
				OptionsPopdown.Panel:Show()
			end
		end)

		-- Create the expanded panel with increased height to accommodate the settings button
		local Panel = CreateFrame('Frame', nil, OptionsPopdown, 'BackdropTemplate')
		Panel:SetSize(_G[v]:GetWidth(), 120)
		Panel:SetBackdrop({
			bgFile = 'Interface\\Tooltips\\UI-Tooltip-Background',
			edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border',
			tile = true,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		Panel:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
		Panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
		Panel:SetPoint('TOPRIGHT', OptionsPopdown, 'BOTTOMRIGHT', 0, -10)
		Panel:Hide()

		local options = {}

		-- Settings button (moved into the expanded area)
		options.openSettingsButton = LibAT.UI.CreateButton(Panel, 120, 20, L['All Settings'])
		options.openSettingsButton:SetScript('OnClick', function()
			SUI.Options:OpenModuleSettings('AutoSell')
		end)

		-- Sell Items button (appears in top right when items are detected)
		options.sellItemsButton = LibAT.UI.CreateButton(Panel, 120, 20, 'Sell 0 Items')
		options.sellItemsButton:SetScript('OnClick', function()
			module:SellTrash()
			options.sellItemsButton:Hide()
		end)
		options.sellItemsButton:Hide()

		-- Auto repair checkbox
		options.AutoRepair = LibAT.UI.CreateCheckbox(Panel, L['Auto repair'])

		-- Max iLVL slider and input (adjusted for smaller panel width)
		options.MaxILVLLabel = LibAT.UI.CreateLabel(Panel, L['Maximum iLVL to sell'])
		options.MaxILVLSlider = LibAT.UI.CreateSlider(Panel, Panel:GetWidth() - 70, 20, 1, module.CurrentSettings.MaximumiLVL, 1)
		options.MaxILVLSlider:SetValue(module.CurrentSettings.MaxILVL)
		options.MaxILVLInput = LibAT.UI.CreateNumericBox(Panel, 50, 20, 1, module.CurrentSettings.MaximumiLVL)
		options.MaxILVLInput:SetValue(module.CurrentSettings.MaxILVL)

		-- Quality checkboxes
		options.Green = LibAT.UI.CreateCheckbox(Panel, L['Sell green'])
		options.Blue = LibAT.UI.CreateCheckbox(Panel, L['Sell blue'])
		options.Purple = LibAT.UI.CreateCheckbox(Panel, L['Sell purple'])

		-- Set up event handlers for slider
		options.MaxILVLSlider:SetScript('OnValueChanged', function(self, value)
			value = math.floor(value)
			module.DB.MaxILVL = value
			SUI.DBM:RefreshSettings(module)
			if options.MaxILVLInput then
				options.MaxILVLInput:SetValue(value)
			end
			module:InvalidateBlacklistCache()
			UpdateSellButton()
		end)

		-- Set up event handlers for numeric input
		options.MaxILVLInput:HookScript('OnTextChanged', function(self, userInput)
			if not userInput then
				return
			end
			local value = self:GetValue()
			if value then
				value = math.floor(value)
				module.DB.MaxILVL = value
				SUI.DBM:RefreshSettings(module)
				options.MaxILVLSlider:SetValue(value)
				module:InvalidateBlacklistCache()
				UpdateSellButton()
			end
		end)

		-- Set up event handlers for checkboxes
		for setting, control in pairs(options) do
			if setting ~= 'MaxILVLSlider' and setting ~= 'MaxILVLInput' and setting ~= 'MaxILVLLabel' and setting ~= 'openSettingsButton' and setting ~= 'sellItemsButton' then
				control:SetChecked(module.CurrentSettings[setting])
				control:HookScript('OnClick', function()
					module.DB[setting] = control:GetChecked()
					SUI.DBM:RefreshSettings(module)
					module:InvalidateBlacklistCache()
					UpdateSellButton()
				end)
			end
		end

		-- Position the controls (settings button at top, then other controls below)
		SUI.UI.GlueTop(options.openSettingsButton, Panel, 5, -5, 'LEFT')
		SUI.UI.GlueTop(options.sellItemsButton, Panel, -5, -5, 'RIGHT')

		SUI.UI.GlueBelow(options.AutoRepair, options.openSettingsButton, 0, -5, 'LEFT')

		SUI.UI.GlueBelow(options.MaxILVLLabel, options.AutoRepair, 0, -5, 'LEFT')
		SUI.UI.GlueBelow(options.MaxILVLSlider, options.MaxILVLLabel, 0, -2, 'LEFT')
		SUI.UI.GlueRight(options.MaxILVLInput, options.MaxILVLSlider, 5, 0)

		SUI.UI.GlueBelow(options.Green, options.MaxILVLSlider, 0, -5, 'LEFT')
		SUI.UI.GlueRight(options.Blue, options.Green, 0, 0)
		SUI.UI.GlueRight(options.Purple, options.Blue, 0, 0)

		OptionsPopdown.Panel = Panel
		OptionsPopdown.Panel.options = options

		-- Store panel reference for cleanup on disable
		module.VendorPanels[v] = OptionsPopdown
	end
end

function module:InitializeOptions()
	BuildOptions()
	SetupPage()
end
