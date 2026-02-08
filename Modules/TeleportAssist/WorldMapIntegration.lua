local SUI, L = SUI, SUI.L
---@type SUI.Module.TeleportAssist
local module = SUI:GetModule('TeleportAssist')
----------------------------------------------------------------------------------------------------

local WorldMapIntegration = {}
WorldMapIntegration.tabSpacing = 4
local DISPLAY_MODE = 'SUI_TELEPORTS'

local tabButton = nil
local contentPanel = nil
local buttonPool = {}
local headerPool = {}
local isShowing = false
local initialized = false

---Initialize the world map integration
function module:InitializeWorldMapIntegration()
	if not WorldMapFrame then
		if module.logger then
			module.logger.warning('WorldMapFrame not available for integration')
		end
		return
	end

	-- Delay initialization to ensure WorldMapFrame is fully loaded
	C_Timer.After(1, function()
		WorldMapIntegration:Initialize()
	end)
end

---Get the panel parent (where content lives)
function WorldMapIntegration:GetPanelParent()
	if QuestMapFrame then
		return QuestMapFrame
	end
	if WorldMapFrame and WorldMapFrame.QuestLog then
		return WorldMapFrame.QuestLog
	end
	return WorldMapFrame
end

---Get the content anchor point (official Blizzard content area)
function WorldMapIntegration:GetContentAnchor()
	if QuestMapFrame then
		if QuestMapFrame.ContentsAnchor then
			return QuestMapFrame.ContentsAnchor
		end
		if QuestMapFrame.MapLegendFrame then
			return QuestMapFrame.MapLegendFrame
		end
		if QuestMapFrame.EventsFrame then
			return QuestMapFrame.EventsFrame
		end
		if QuestMapFrame.QuestsFrame then
			return QuestMapFrame.QuestsFrame
		end
	end
	return WorldMapIntegration:GetPanelParent()
end

---Find existing Blizzard side tabs to anchor below them
function WorldMapIntegration:FindSideTabs()
	local tabs = {}
	local function AddIfTab(frame)
		if frame and frame.Background and frame.Icon and frame.SetChecked then
			if frame.Background.GetAtlas and frame.Background:GetAtlas() == 'questlog-tab-side' then
				table.insert(tabs, frame)
			end
		end
	end

	if QuestMapFrame then
		AddIfTab(QuestMapFrame.QuestsTab)
		AddIfTab(QuestMapFrame.EventsTab)
		AddIfTab(QuestMapFrame.MapLegendTab)
	end

	-- Scan for other tabs
	local function Scan(frame)
		if not frame or not frame.GetChildren then
			return
		end
		for _, child in ipairs({ frame:GetChildren() }) do
			if child ~= tabButton then
				AddIfTab(child)
			end
			Scan(child)
		end
	end

	Scan(WorldMapFrame)
	return tabs
end

---Create the tab button on the world map
function WorldMapIntegration:Initialize()
	if initialized then
		return -- Already initialized
	end

	if not WorldMapFrame or not WorldMapFrame.BorderFrame then
		C_Timer.After(0.5, function()
			WorldMapIntegration:Initialize()
		end)
		return
	end

	-- Create tab button using LargeSideTabButtonTemplate
	local tabParent = QuestMapFrame or WorldMapFrame.BorderFrame
	tabButton = CreateFrame('Button', 'SUI_TeleportMapTab', tabParent, 'LargeSideTabButtonTemplate')
	tabButton:SetFrameStrata('HIGH')
	tabButton:SetFrameLevel(WorldMapFrame.BorderFrame:GetFrameLevel() + 5)

	-- Set tab properties
	tabButton.tooltipText = L['Teleports']
	tabButton.displayMode = DISPLAY_MODE

	-- Setup icon visuals
	WorldMapIntegration:SetupButtonVisuals()

	-- Hook to reapply visuals on show
	if not tabButton.suiIconHooked then
		tabButton:HookScript('OnShow', function()
			WorldMapIntegration:SetupButtonVisuals()
		end)
		tabButton.suiIconHooked = true
	end

	tabButton:SetChecked(false)

	-- Use custom click handler to integrate with QuestMapFrame display mode
	tabButton:SetCustomOnMouseUpHandler(function(btn, mouseButton, upInside)
		if mouseButton == 'LeftButton' and upInside then
			WorldMapIntegration:SelectTab()
		end
	end)

	-- Anchor below existing Blizzard tabs (MapLegend, Events, Quests)
	WorldMapIntegration:AnchorTabButton()

	-- Hook other tabs to hide our panel when clicked
	WorldMapIntegration:HookOtherTabs()

	-- Hook other content frames to hide our panel when shown
	WorldMapIntegration:HookOtherContentFrames()

	-- Hook display mode system
	WorldMapIntegration:HookDisplayMode()

	-- Create the content panel
	WorldMapIntegration:CreatePanel()

	-- Make button visible
	tabButton:Show()

	initialized = true

	-- Initialize canvas pins
	WorldMapIntegration:InitializePins()

	-- If display mode is already set to ours, show the panel
	if QuestMapFrame and QuestMapFrame.displayMode == DISPLAY_MODE then
		WorldMapIntegration:ShowPanel()
	end

	if module.logger then
		module.logger.info('World Map integration initialized')
	end
end

---Setup button icon visuals to match Blizzard tabs
function WorldMapIntegration:SetupButtonVisuals()
	if tabButton and tabButton.Icon then
		-- Set the atlas names used by SidePanelTabButtonMixin:SetChecked()
		tabButton.inactiveAtlas = 'TaxiNode_Continent_Neutral'
		tabButton.activeAtlas = 'TaxiNode_Continent_Neutral'

		-- Apply initial icon
		tabButton.Icon:SetAtlas('TaxiNode_Continent_Neutral')
		tabButton.Icon:SetAlpha(0.8)

		-- Size the icon
		tabButton.Icon:SetSize(20, 20)
	end
end

---Anchor the tab button below existing Blizzard tabs
function WorldMapIntegration:AnchorTabButton()
	if not tabButton then
		return
	end

	if InCombatLockdown() then
		return
	end

	-- Find the last Blizzard tab to anchor below it
	local anchorTab = (QuestMapFrame and QuestMapFrame.MapLegendTab) or (QuestMapFrame and QuestMapFrame.EventsTab) or (QuestMapFrame and QuestMapFrame.QuestsTab)

	tabButton:ClearAllPoints()
	if anchorTab then
		-- Anchor below the last Blizzard tab with spacing
		tabButton:SetPoint('TOP', anchorTab, 'BOTTOM', 0, -(WorldMapIntegration.tabSpacing or 4))
	else
		-- Fallback if no Blizzard tabs found
		tabButton:SetPoint('TOPRIGHT', WorldMapFrame.BorderFrame, 'TOPRIGHT', -8, -100)
	end
end

---Hook other side tabs to hide our panel when they're clicked
function WorldMapIntegration:HookOtherTabs()
	local tabs = WorldMapIntegration:FindSideTabs()
	for _, tab in ipairs(tabs) do
		if not tab.suiHooked then
			if tab.SetCustomOnMouseUpHandler then
				-- Hook the custom handler if available
				local originalHandler = tab.GetCustomOnMouseUpHandler and tab:GetCustomOnMouseUpHandler()
				tab:SetCustomOnMouseUpHandler(function(btn, mouseButton, upInside)
					if originalHandler then
						originalHandler(btn, mouseButton, upInside)
					end
					WorldMapIntegration:HidePanel()
				end)
			else
				-- Fallback to OnClick
				tab:HookScript('OnClick', function()
					WorldMapIntegration:HidePanel()
				end)
			end
			tab.suiHooked = true
		end
	end
end

---Hook other content frames (Quests, Events, MapLegend) to hide our panel when shown
function WorldMapIntegration:HookOtherContentFrames()
	if not QuestMapFrame then
		return
	end

	local function HookFrame(frame)
		if frame and not frame.suiHooked then
			hooksecurefunc(frame, 'Show', function()
				WorldMapIntegration:HidePanel()
			end)
			frame.suiHooked = true
		end
	end

	HookFrame(QuestMapFrame.QuestsFrame)
	HookFrame(QuestMapFrame.EventsFrame)
	HookFrame(QuestMapFrame.MapLegendFrame)
end

---Hook into QuestMapFrame display mode system
function WorldMapIntegration:HookDisplayMode()
	if not QuestMapFrame or not QuestMapFrame.SetDisplayMode then
		return
	end

	-- Hook SetDisplayMode to show/hide our panel based on display mode
	hooksecurefunc(QuestMapFrame, 'SetDisplayMode', function(self, mode)
		if mode == DISPLAY_MODE then
			WorldMapIntegration:ShowPanel()
		else
			WorldMapIntegration:HidePanel()
		end
	end)
end

---Select this tab (show our panel using display mode system)
function WorldMapIntegration:SelectTab()
	if InCombatLockdown() then
		-- In combat, just show the panel directly
		WorldMapIntegration:ShowPanel()
		return
	end

	-- Use QuestMapFrame display mode system if available
	if QuestMapFrame and QuestMapFrame.SetDisplayMode then
		QuestMapFrame:SetDisplayMode(DISPLAY_MODE)
		return
	end

	-- Fallback: just show the panel
	WorldMapIntegration:ShowPanel()
end

---Create the content panel that integrates into QuestMapFrame
function WorldMapIntegration:CreatePanel()
	if contentPanel then
		return
	end

	local panelParent = WorldMapIntegration:GetPanelParent()
	local contentAnchor = WorldMapIntegration:GetContentAnchor()

	-- Create panel that fills the official content area
	contentPanel = CreateFrame('Frame', 'SUI_TeleportMapPanel', panelParent)
	contentPanel:SetAllPoints(contentAnchor)
	contentPanel:SetFrameStrata(contentAnchor:GetFrameStrata())
	contentPanel:SetFrameLevel(contentAnchor:GetFrameLevel() + 10)
	contentPanel:EnableMouse(true)
	contentPanel:Hide()

	-- Special positioning for QuestMapFrame.ContentsAnchor
	if QuestMapFrame and contentAnchor == QuestMapFrame.ContentsAnchor then
		contentPanel:ClearAllPoints()
		contentPanel:SetPoint('TOPLEFT', contentAnchor, 'TOPLEFT', 0, -29)
		contentPanel:SetPoint('BOTTOMRIGHT', contentAnchor, 'BOTTOMRIGHT', -22, 0)
	end

	-- Create scroll frame using Blizzard template (matches MapLegend style)
	contentPanel.ScrollFrame = CreateFrame('ScrollFrame', 'SUI_TeleportMapPanelScrollFrame', contentPanel, 'ScrollFrameTemplate')
	contentPanel.ScrollFrame:ClearAllPoints()
	contentPanel.ScrollFrame:SetPoint('TOPLEFT', 10, 0) -- Add 10px left padding
	contentPanel.ScrollFrame:SetPoint('BOTTOMRIGHT', -10, 0) -- Add 10px right padding

	-- Background using official Blizzard atlas (matches QuestLog)
	contentPanel.ScrollFrame.Background = contentPanel.ScrollFrame:CreateTexture(nil, 'BACKGROUND')
	contentPanel.ScrollFrame.Background:SetAtlas('QuestLog-main-background', true)
	contentPanel.ScrollFrame.Background:ClearAllPoints()
	contentPanel.ScrollFrame.Background:SetPoint('TOPLEFT', contentPanel.ScrollFrame, 'TOPLEFT', 3, -1)
	contentPanel.ScrollFrame.Background:SetPoint('BOTTOMRIGHT', contentPanel.ScrollFrame, 'BOTTOMRIGHT', -3, 0)

	-- Scrollbar alignment (matches MapLegend)
	if contentPanel.ScrollFrame.ScrollBar then
		contentPanel.ScrollFrame.ScrollBar:ClearAllPoints()
		contentPanel.ScrollFrame.ScrollBar:SetPoint('TOPLEFT', contentPanel.ScrollFrame, 'TOPRIGHT', 8, 2)
		contentPanel.ScrollFrame.ScrollBar:SetPoint('BOTTOMLEFT', contentPanel.ScrollFrame, 'BOTTOMRIGHT', 8, -4)
	end

	-- Scroll child
	contentPanel.Content = CreateFrame('Frame', nil, contentPanel.ScrollFrame)
	contentPanel.Content:SetWidth(contentPanel.ScrollFrame:GetWidth())
	contentPanel.Content:SetHeight(1)
	contentPanel.ScrollFrame:SetScrollChild(contentPanel.Content)

	-- Settings button will be positioned at bottom of scroll content in PopulatePanel

	-- Adjust scroll frame to make room for button (removed - button now inside scroll area)

	-- Border frame using official Blizzard template
	contentPanel.BorderFrame = CreateFrame('Frame', nil, contentPanel, 'QuestLogBorderFrameTemplate')
	contentPanel.BorderFrame:ClearAllPoints()
	contentPanel.BorderFrame:SetPoint('TOPLEFT', contentPanel.ScrollFrame, 'TOPLEFT', -3, 7)
	contentPanel.BorderFrame:SetPoint('BOTTOMRIGHT', contentPanel.ScrollFrame, 'BOTTOMRIGHT', 3, -6)

	-- Title above border
	contentPanel.Title = contentPanel:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
	contentPanel.Title:SetPoint('BOTTOM', contentPanel.BorderFrame, 'TOP', -1, 3)
	local fontPath, fontSize, fontFlags = GameFontNormal:GetFont()
	if fontPath and fontSize then
		contentPanel.Title:SetFont(fontPath, fontSize + 3, fontFlags)
	end
	contentPanel.Title:SetText('|cffffffffSpartan|cffe21f1fUI|r ' .. L['Teleport Assist'])
	contentPanel.Title:SetTextColor(1, 0.82, 0)

	-- Integrate into QuestMapFrame.ContentFrames if available
	if QuestMapFrame and QuestMapFrame.ContentFrames then
		local exists = false
		for _, frame in ipairs(QuestMapFrame.ContentFrames) do
			if frame == contentPanel then
				exists = true
				break
			end
		end
		if not exists then
			table.insert(QuestMapFrame.ContentFrames, contentPanel)
		end
	end

	-- Integrate into QuestMapFrame.TabButtons if available
	if QuestMapFrame and QuestMapFrame.TabButtons then
		local exists = false
		for _, tab in ipairs(QuestMapFrame.TabButtons) do
			if tab == tabButton then
				exists = true
				break
			end
		end
		if not exists then
			table.insert(QuestMapFrame.TabButtons, tabButton)
		end
	end

	-- Validate tabs (Blizzard function)
	if QuestMapFrame and QuestMapFrame.ValidateTabs then
		QuestMapFrame:ValidateTabs()
	end
end

---Toggle the panel visibility
function WorldMapIntegration:TogglePanel()
	if isShowing then
		WorldMapIntegration:HidePanel()
	else
		WorldMapIntegration:SelectTab()
	end
end

---Show the panel
function WorldMapIntegration:ShowPanel()
	if not contentPanel then
		return
	end

	-- Populate with current teleports
	WorldMapIntegration:PopulatePanel()

	contentPanel:Show()
	isShowing = true
	if tabButton then
		tabButton:SetChecked(true)
		if tabButton.Icon then
			tabButton.Icon:SetAlpha(1.0)
		end
	end
end

---Hide the panel
function WorldMapIntegration:HidePanel()
	if not contentPanel then
		return
	end

	contentPanel:Hide()
	isShowing = false
	if tabButton then
		tabButton:SetChecked(false)
		if tabButton.Icon then
			tabButton.Icon:SetAlpha(0.8)
		end
	end
end

---Populate the panel with teleport buttons
function WorldMapIntegration:PopulatePanel()
	if not contentPanel then
		return
	end

	-- Ensure content width matches scroll frame width
	contentPanel.Content:SetWidth(contentPanel.ScrollFrame:GetWidth())

	-- Hide all existing buttons and headers
	for _, button in pairs(buttonPool) do
		button:Hide()
	end
	for _, header in pairs(headerPool) do
		header:Hide()
	end

	local buttonIndex = 1
	local yOffset = 10 -- Top padding to prevent header cutoff
	local settings = module.CurrentSettings
	local displayMode = settings.displayMode or 'list'

	-- Get user-configured button size and scale
	local baseButtonSize = settings.buttonSize or 36
	local scale = settings.frameScale or 1.0

	-- Apply scale to contentPanel
	contentPanel:SetScale(scale)

	-- Display mode specific settings (scaled by buttonSize)
	local buttonHeight, buttonWidth, iconSize, columnCount, spacing, columnSpacing
	if displayMode == 'grid' then
		-- Grid: Square buttons, icon-focused, labels below
		local ratio = baseButtonSize / 36 -- Scale relative to default 36
		buttonWidth = math.floor(50 * ratio)
		buttonHeight = math.floor(65 * ratio) -- Taller to fit label below icon
		iconSize = math.floor(40 * ratio)
		columnCount = 4
		spacing = 4
		columnSpacing = 4
	elseif displayMode == 'compact' then
		-- Compact: Smaller everything, icon above label
		local ratio = baseButtonSize / 36
		buttonWidth = math.floor(60 * ratio)
		buttonHeight = math.floor(50 * ratio)
		iconSize = math.floor(28 * ratio)
		columnCount = 3
		spacing = 2
		columnSpacing = 6
	else
		-- List (default): Current 2-column layout
		local ratio = baseButtonSize / 36
		buttonWidth = math.floor(130 * ratio)
		buttonHeight = math.floor(28 * ratio)
		iconSize = math.floor(20 * ratio)
		columnCount = 2
		spacing = 2
		columnSpacing = 8
	end

	-- Helper to create a button
	local function GetButton(index)
		if buttonPool[index] then
			local button = buttonPool[index]
			-- Update size and icon/label positioning for display mode changes
			button:SetSize(buttonWidth, buttonHeight)
			button.Icon:SetSize(iconSize, iconSize)
			button.Icon:ClearAllPoints()
			button.Label:ClearAllPoints()

			-- Position icon based on display mode
			if displayMode == 'list' then
				-- List mode: icon on LEFT
				button.Icon:SetPoint('LEFT', button, 'LEFT', 4, 0)
				-- List mode: label to RIGHT of icon
				button.Label:SetPoint('LEFT', button.Icon, 'RIGHT', 6, 0)
				button.Label:SetPoint('RIGHT', button, 'RIGHT', -4, 0)
				button.Label:SetJustifyH('LEFT')
			else
				-- Grid/Compact mode: icon on TOP (centered)
				button.Icon:SetPoint('TOP', button, 'TOP', 0, -4)
				-- Grid/Compact mode: label BELOW icon (centered)
				button.Label:SetPoint('TOP', button.Icon, 'BOTTOM', 0, -2)
				button.Label:SetPoint('LEFT', button, 'LEFT', 2, 0)
				button.Label:SetPoint('RIGHT', button, 'RIGHT', -2, 0)
				button.Label:SetJustifyH('CENTER')
			end

			return button
		end

		local button = CreateFrame('Button', 'SUI_TeleportMapButton_' .. index, contentPanel.Content, 'SecureActionButtonTemplate')
		button:SetSize(buttonWidth, buttonHeight)

		-- Background
		button.Background = button:CreateTexture(nil, 'BACKGROUND')
		button.Background:SetAllPoints()
		button.Background:SetColorTexture(0, 0, 0, 0.3)

		-- Hover highlight
		button.Hover = button:CreateTexture(nil, 'HIGHLIGHT')
		button.Hover:SetAllPoints()
		button.Hover:SetColorTexture(1, 1, 1, 0.2)
		button.Hover:SetBlendMode('ADD')

		-- Icon (size will be set dynamically based on display mode)
		button.Icon = button:CreateTexture(nil, 'ARTWORK')
		button.Icon:SetSize(iconSize, iconSize)

		-- Position icon based on display mode
		if displayMode == 'list' then
			-- List mode: icon on LEFT, label on RIGHT
			button.Icon:SetPoint('LEFT', button, 'LEFT', 4, 0)
		else
			-- Grid/Compact mode: icon on TOP (centered)
			button.Icon:SetPoint('TOP', button, 'TOP', 0, -4)
		end

		-- Label (smaller font)
		button.Label = button:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
		button.Label:SetWordWrap(false)

		-- Position label based on display mode
		if displayMode == 'list' then
			-- List mode: label to RIGHT of icon
			button.Label:SetPoint('LEFT', button.Icon, 'RIGHT', 6, 0)
			button.Label:SetPoint('RIGHT', button, 'RIGHT', -4, 0)
			button.Label:SetJustifyH('LEFT')
		else
			-- Grid/Compact mode: label BELOW icon (centered)
			button.Label:SetPoint('TOP', button.Icon, 'BOTTOM', 0, -2)
			button.Label:SetPoint('LEFT', button, 'LEFT', 2, 0)
			button.Label:SetPoint('RIGHT', button, 'RIGHT', -2, 0)
			button.Label:SetJustifyH('CENTER')
		end

		-- Cooldown overlay
		button.Cooldown = CreateFrame('Cooldown', nil, button, 'CooldownFrameTemplate')
		button.Cooldown:SetAllPoints(button.Icon)
		button.Cooldown:SetDrawEdge(false)

		-- Clicks (match MDungeonTeleports pattern)
		button:RegisterForClicks('AnyUp', 'AnyDown')
		button:RegisterForDrag('LeftButton')

		-- Script handlers for housing and favorites
		button:SetScript('PreClick', function(self, mouseButton)
			if mouseButton == 'RightButton' then
				-- Temporarily disable secure action for right-click
				self:SetAttribute('type', nil)
			end
		end)

		button:SetScript('PostClick', function(self, mouseButton)
			local entry = self.entry
			if not entry then
				return
			end

			if mouseButton == 'RightButton' then
				-- Toggle favorite and refresh
				module:ToggleFavorite(entry)
				-- Restore secure attribute after right-click
				if entry.available then
					if entry.type == 'spell' then
						self:SetAttribute('type', 'spell')
					elseif entry.type == 'toy' then
						self:SetAttribute('type', 'toy')
					elseif entry.type == 'item' then
						self:SetAttribute('type', 'item')
					elseif entry.type == 'macro' then
						self:SetAttribute('type', 'macro')
					end
				end
				WorldMapIntegration:PopulatePanel()
			elseif mouseButton == 'LeftButton' and entry.type == 'housing' and entry.available then
				-- Open Housing UI and select specific house
				if module.logger then
					module.logger.debug('Housing button clicked, houseIndex: ' .. tostring(entry.houseIndex))
					module.logger.debug('HousingDashboardFrame exists: ' .. tostring(HousingDashboardFrame ~= nil))
					if HousingDashboardFrame then
						module.logger.debug('HouseInfoContent exists: ' .. tostring(HousingDashboardFrame.HouseInfoContent ~= nil))
					end
				end

				-- Open the Housing Dashboard using ShowUIPanel
				if HousingDashboardFrame then
					ShowUIPanel(HousingDashboardFrame)

					-- After the frame is shown, trigger the house selection
					if HousingDashboardFrame.HouseInfoContent and entry.houseIndex then
						local houseInfoContent = HousingDashboardFrame.HouseInfoContent
						local houseInfoID = entry.houseIndex

						-- Set the selected house ID
						houseInfoContent.selectedHouseID = houseInfoID
						houseInfoContent.selectedHouseInfo = houseInfoContent.playerHouseList and houseInfoContent.playerHouseList[houseInfoID]

						-- Trigger the callbacks that update the UI (mimics OnHouseSelected)
						if houseInfoContent.ContentFrame then
							if houseInfoContent.ContentFrame.InitiativesFrame and houseInfoContent.ContentFrame.InitiativesFrame.OnHouseSelected then
								houseInfoContent.ContentFrame.InitiativesFrame:OnHouseSelected(houseInfoID)
							end
							if houseInfoContent.ContentFrame.HouseUpgradeFrame and houseInfoContent.ContentFrame.HouseUpgradeFrame.OnHouseSelected then
								houseInfoContent.ContentFrame.HouseUpgradeFrame:OnHouseSelected(houseInfoID)
							end
						end

						if module.logger then
							module.logger.info('Opened Housing Dashboard for: ' .. (entry.name or 'unknown') .. ' (index: ' .. houseInfoID .. ')')
						end
					end
				else
					if module.logger then
						module.logger.error('HousingDashboardFrame not available')
					end
				end
			end

			-- Debug: Log clicks
			if module.logger then
				module.logger.debug('Button clicked: ' .. (entry.name or 'unknown') .. ' (type: ' .. (entry.type or 'unknown') .. ', available: ' .. tostring(entry.available) .. ')')
			end
		end)

		-- Tooltip
		button:SetScript('OnEnter', function(self)
			if not module.CurrentSettings.showTooltips then
				return
			end

			local entry = self.entry
			if not entry then
				return
			end

			GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
			GameTooltip:SetText(entry.name, 1, 1, 1)

			if entry.type == 'spell' then
				GameTooltip:SetSpellByID(entry.spellId or entry.id)
			elseif entry.type == 'toy' then
				GameTooltip:SetToyByItemID(entry.id)
			elseif entry.type == 'item' then
				GameTooltip:SetItemByID(entry.id)
			end

			if entry.class then
				GameTooltip:AddLine('Class: ' .. entry.class, 0.5, 0.5, 0.5)
			end
			if entry.faction then
				GameTooltip:AddLine('Faction: ' .. entry.faction, 0.5, 0.5, 0.5)
			end

			GameTooltip:AddLine(' ')
			GameTooltip:AddLine('|cff888888Right-click to favorite|r', 0.5, 0.5, 0.5)

			GameTooltip:Show()
		end)

		button:SetScript('OnLeave', function()
			GameTooltip:Hide()
		end)

		buttonPool[index] = button
		return button
	end

	-- Helper to get/create a header
	local headerIndex = 1
	local function GetHeader()
		if headerPool[headerIndex] then
			local header = headerPool[headerIndex]
			header:Show()
			headerIndex = headerIndex + 1
			return header
		end

		local header = contentPanel.Content:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
		header:SetTextColor(1, 0.82, 0)
		headerPool[headerIndex] = header
		headerIndex = headerIndex + 1
		return header
	end

	-- Track current row/column for 2-column layout
	local currentRow = 0
	local currentColumn = 0

	-- Add all available teleports from each category
	for _, expansion in ipairs(module.EXPANSION_ORDER) do
		local entries = module.teleportsByCategory[expansion]
		if entries and #entries > 0 then
			-- Category header (spans both columns)
			if currentColumn > 0 then
				-- Move to next row if we were in the middle of a row
				currentRow = currentRow + 1
				currentColumn = 0
				yOffset = yOffset + buttonHeight + spacing
			end

			local header = GetHeader()
			header:ClearAllPoints()
			header:SetPoint('TOPLEFT', contentPanel.Content, 'TOPLEFT', 4, -yOffset)
			header:SetText(module.EXPANSION_NAMES[expansion] or expansion)
			yOffset = yOffset + 20
			currentRow = currentRow + 1
			currentColumn = 0

			-- Add buttons for this category in 2-column layout
			for _, entry in ipairs(entries) do
				if entry.available or not module.CurrentSettings.hideUnavailable then
					local button = GetButton(buttonIndex)
					button:SetSize(buttonWidth, buttonHeight)
					button:ClearAllPoints()

					-- Calculate position based on column
					local xOffset = 4 + (currentColumn * (buttonWidth + columnSpacing))
					button:SetPoint('TOPLEFT', contentPanel.Content, 'TOPLEFT', xOffset, -yOffset)

					-- Set icon with proper fallback logic
					local iconTexture = entry.icon
					if not iconTexture then
						-- Try to get icon from spell/item/toy
						if entry.type == 'spell' then
							iconTexture = C_Spell.GetSpellTexture(entry.spellId or entry.id)
						elseif entry.type == 'toy' then
							-- C_ToyBox.GetToyInfo returns: itemID, toyName, icon, isFavorite, hasFanfare, itemQuality
							local _, _, toyIcon = C_ToyBox.GetToyInfo(entry.id)
							iconTexture = toyIcon
						elseif entry.type == 'item' then
							iconTexture = C_Item.GetItemIconByID(entry.id)
						end
					end

					-- Set texture or atlas
					if type(iconTexture) == 'string' then
						-- Atlas name (string)
						button.Icon:SetAtlas(iconTexture)
					else
						-- Texture ID (number) or fallback to question mark
						button.Icon:SetTexture(iconTexture or 134400)
					end
					button.Icon:SetDesaturated(not entry.available)

					-- Set label text based on display settings
					local labelText = module:GetDisplayLabel(entry)
					if labelText then
						button.Label:SetText(labelText)
						button.Label:Show()
						if entry.available then
							button.Label:SetTextColor(1.0, 1.0, 1.0) -- White
						else
							button.Label:SetTextColor(0.5, 0.5, 0.5) -- Gray
						end
					else
						-- Hide label if GetDisplayLabel returns nil
						button.Label:SetText('')
						button.Label:Hide()
					end

					-- Store entry reference
					button.entry = entry

					-- Set secure attributes for left-click teleports (CRITICAL: only outside combat)
					if not InCombatLockdown() then
						if entry.available then
							if entry.type == 'spell' then
								button:SetAttribute('type', 'spell')
								local spellID = entry.spellId or entry.id
								button:SetAttribute('spell', spellID)
								if module.logger then
									module.logger.debug('Set spell button: ' .. (entry.name or 'unknown') .. ' (ID: ' .. spellID .. ')')
								end
							elseif entry.type == 'toy' then
								button:SetAttribute('type', 'toy')
								button:SetAttribute('toy', entry.id)
								if module.logger then
									module.logger.debug('Set toy button: ' .. (entry.name or 'unknown') .. ' (ID: ' .. entry.id .. ')')
								end
							elseif entry.type == 'item' then
								button:SetAttribute('type', 'item')
								button:SetAttribute('item', 'item:' .. entry.id)
								if module.logger then
									module.logger.debug('Set item button: ' .. (entry.name or 'unknown') .. ' (ID: ' .. entry.id .. ')')
								end
							elseif entry.type == 'macro' then
								button:SetAttribute('type', 'macro')
								button:SetAttribute('macrotext', entry.macro)
								if module.logger then
									module.logger.debug('Set macro button: ' .. (entry.name or 'unknown'))
								end
							elseif entry.type == 'housing' then
								-- Housing uses PostClick handler (not secure)
								button:SetAttribute('type', nil)
								if module.logger then
									module.logger.debug('Set housing button: ' .. (entry.name or 'unknown'))
								end
							end
						else
							button:SetAttribute('type', nil)
						end
					end

					button:Show()
					buttonIndex = buttonIndex + 1

					-- Move to next column
					currentColumn = currentColumn + 1
					if currentColumn >= columnCount then
						currentColumn = 0
						currentRow = currentRow + 1
						yOffset = yOffset + buttonHeight + spacing
					end
				end
			end

			-- Add extra spacing between categories
			if currentColumn > 0 then
				-- Move to next row
				currentColumn = 0
				currentRow = currentRow + 1
				yOffset = yOffset + buttonHeight + spacing
			end
			yOffset = yOffset + 8
		end
	end

	-- Add Settings button at bottom of content (inside scroll area)
	yOffset = yOffset + 20 -- Top padding for button
	if not contentPanel.SettingsButton then
		contentPanel.SettingsButton = LibAT.UI.CreateButton(contentPanel.Content, 120, 22, 'Open Settings', true)
		contentPanel.SettingsButton:SetScript('OnClick', function()
			SUI.Options:OpenModuleSettings('TeleportAssist')
		end)
	end
	contentPanel.SettingsButton:ClearAllPoints()
	contentPanel.SettingsButton:SetPoint('TOP', contentPanel.Content, 'TOP', 0, -yOffset)
	contentPanel.SettingsButton:Show()

	yOffset = yOffset + 22 + 20 -- Button height + bottom padding

	-- Update content height
	contentPanel.Content:SetHeight(math.max(yOffset, contentPanel.ScrollFrame:GetHeight()))
end

---Refresh the panel when map changes (called by WorldMapFrame)
function WorldMapIntegration:Refresh()
	if isShowing then
		WorldMapIntegration:PopulatePanel()
	end
end

-- ==================== CANVAS PIN SYSTEM ====================
-- Uses Blizzard's MapCanvasDataProvider system (same approach as TomTom/HandyNotes)
-- Each pin is a data provider pin with a SecureActionButton child for click-to-cast

local PIN_TEMPLATE = 'SUI_TeleportPinTemplate'
local dataProviderRegistered = false

-- Pin mixin - handles positioning and display within the data provider system
local TeleportPinMixin = CreateFromMixins(MapCanvasPinMixin)

function TeleportPinMixin:OnLoad()
	self:UseFrameLevelType('PIN_FRAME_LEVEL_AREA_POI')
	self:SetScalingLimits(1, 1.0, 1.2)
end

---@param pinData SUI.TeleportAssist.PinData
function TeleportPinMixin:OnAcquired(pinData)
	self:SetPosition(pinData.projectedX, pinData.projectedY)
	local entry = pinData.entry
	self.entry = entry

	-- Create or update the action button child
	if not self.ActionButton then
		self.ActionButton = CreateFrame('Button', nil, self, 'SecureActionButtonTemplate')
		self.ActionButton:SetAllPoints(self)
		self.ActionButton:RegisterForClicks('AnyUp', 'AnyDown')

		-- Icon
		self.ActionButton.Texture = self.ActionButton:CreateTexture(nil, 'BACKGROUND')
		self.ActionButton.Texture:SetAllPoints(self.ActionButton)

		-- Border
		self.ActionButton.Border = self.ActionButton:CreateTexture(nil, 'OVERLAY')
		self.ActionButton.Border:SetPoint('CENTER')
		self.ActionButton.Border:SetAtlas('communities-ring-blue')

		-- Highlight
		local highlight = self.ActionButton:CreateTexture(nil, 'HIGHLIGHT')
		highlight:SetPoint('CENTER')
		highlight:SetAtlas('communities-ring-blue')
		highlight:SetAlpha(0.5)
		highlight:SetBlendMode('ADD')
		self.ActionButton.Highlight = highlight

		-- Tooltip
		self.ActionButton:SetScript('OnEnter', function(btn)
			local e = self.entry
			if not e then
				return
			end
			GameTooltip:SetOwner(btn, 'ANCHOR_RIGHT')
			if e.type == 'spell' then
				GameTooltip:SetSpellByID(e.spellId or e.id)
			elseif e.type == 'toy' then
				GameTooltip:SetToyByItemID(e.id)
			elseif e.type == 'item' then
				GameTooltip:SetItemByID(e.id)
			else
				GameTooltip:AddLine(e.name, 1, 1, 1)
			end
			-- Show portal option hint for mages
			if e.portalEntry and e.portalEntry.available then
				GameTooltip:AddLine(' ')
				GameTooltip:AddLine('|cff00ff00' .. L['Left-Click'] .. ':|r ' .. L['Teleport'])
				GameTooltip:AddLine('|cff00ff00' .. L['Right-Click'] .. ':|r ' .. L['Portal'])
			else
				GameTooltip:AddLine(' ')
				GameTooltip:AddLine('|cff00ff00' .. L['Click to cast'] .. '|r')
			end
			GameTooltip:Show()
		end)

		self.ActionButton:SetScript('OnLeave', function()
			GameTooltip:Hide()
		end)
	end

	-- Size (read from settings)
	local pinSize = module.CurrentSettings.mapPinSize or 32
	self:SetSize(pinSize, pinSize)
	self.ActionButton:SetAllPoints(self)
	self.ActionButton.Border:SetSize(pinSize + 4, pinSize + 4)
	self.ActionButton.Highlight:SetSize(pinSize + 6, pinSize + 6)

	-- Icon texture
	local iconTexture = entry.icon
	if not iconTexture then
		if entry.type == 'spell' then
			iconTexture = C_Spell.GetSpellTexture(entry.spellId or entry.id)
		elseif entry.type == 'toy' then
			local _, _, toyIcon = C_ToyBox.GetToyInfo(entry.id)
			iconTexture = toyIcon
		elseif entry.type == 'item' then
			iconTexture = C_Item.GetItemIconByID(entry.id)
		end
	end

	if type(iconTexture) == 'string' then
		self.ActionButton.Texture:SetAtlas(iconTexture)
	else
		self.ActionButton.Texture:SetTexture(iconTexture or 134400)
	end

	-- Set secure action attributes for left-click (teleport)
	if not InCombatLockdown() then
		if entry.type == 'spell' then
			self.ActionButton:SetAttribute('type', 'spell')
			self.ActionButton:SetAttribute('spell', entry.spellId or entry.id)
		elseif entry.type == 'toy' then
			self.ActionButton:SetAttribute('type', 'macro')
			self.ActionButton:SetAttribute('macrotext', '/use item:' .. entry.id)
		elseif entry.type == 'item' then
			self.ActionButton:SetAttribute('type', 'item')
			self.ActionButton:SetAttribute('item', 'item:' .. entry.id)
		end

		-- For mages: right-click casts portal variant
		if entry.portalEntry and entry.portalEntry.available then
			self.ActionButton:SetAttribute('type2', 'spell')
			self.ActionButton:SetAttribute('spell2', entry.portalEntry.spellId or entry.portalEntry.id)
		end
	end

	self.ActionButton:Show()
end

function TeleportPinMixin:OnReleased()
	if self.ActionButton then
		self.ActionButton:Hide()
		if not InCombatLockdown() then
			self.ActionButton:SetAttribute('type', nil)
			self.ActionButton:SetAttribute('spell', nil)
			self.ActionButton:SetAttribute('macrotext', nil)
			self.ActionButton:SetAttribute('item', nil)
			self.ActionButton:SetAttribute('type2', nil)
			self.ActionButton:SetAttribute('spell2', nil)
		end
	end
	self.entry = nil
end

-- ==================== MULTI-LEVEL PIN PROJECTION ====================
-- Allows pins to display at any zoom level by projecting coordinates
-- between parent and child maps using Blizzard's C_Map APIs.

---@type table<number, table<number, boolean>>
local ancestorCache = {}

---Build the set of ancestor mapIDs for a given map (walks parentMapID chain)
---@param mapId number
---@return table<number, boolean>
local function BuildAncestorSet(mapId)
	if ancestorCache[mapId] then
		return ancestorCache[mapId]
	end
	local ancestors = {}
	local current = mapId
	for _ = 1, 20 do -- safety limit
		local info = C_Map.GetMapInfo(current)
		if not info or not info.parentMapID or info.parentMapID == 0 then
			break
		end
		ancestors[info.parentMapID] = true
		current = info.parentMapID
	end
	ancestorCache[mapId] = ancestors
	return ancestors
end

---@type table<number, boolean>
local descendantCache = {}

---Check if childMapId is a descendant of parentMapId
---@param childMapId number
---@param parentMapId number
---@return boolean
local function IsDescendantOf(childMapId, parentMapId)
	if childMapId == parentMapId then
		return true
	end
	local cacheKey = childMapId * 100000 + parentMapId
	if descendantCache[cacheKey] ~= nil then
		return descendantCache[cacheKey]
	end
	local ancestors = BuildAncestorSet(childMapId)
	local result = ancestors[parentMapId] or false
	descendantCache[cacheKey] = result
	return result
end

---Transform coordinates from one map to another (parent/child projection)
---Returns projected x, y or nil if the maps are not related or pin is out of bounds
---@param entryMapId number The map the entry's coordinates are defined on
---@param entryX number Normalized 0-1 X coordinate on the entry's map
---@param entryY number Normalized 0-1 Y coordinate on the entry's map
---@param targetMapId number The map we want to display the pin on
---@return number|nil projectedX
---@return number|nil projectedY
local function TransformCoordinates(entryMapId, entryX, entryY, targetMapId)
	-- Same map: no transform needed
	if entryMapId == targetMapId then
		return entryX, entryY
	end

	-- Case 1: Entry is on a child map, target is a parent (e.g., zone pin on continent)
	-- Forward projection: zone coords -> continent coords
	if IsDescendantOf(entryMapId, targetMapId) then
		local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(entryMapId, targetMapId)
		if minX and maxX and minY and maxY then
			local projX = minX + entryX * (maxX - minX)
			local projY = minY + entryY * (maxY - minY)
			return projX, projY
		end
		return nil, nil
	end

	-- Case 2: Target is a child map, entry is on a parent (e.g., continent pin on zone view)
	-- Inverse projection: continent coords -> zone coords
	if IsDescendantOf(targetMapId, entryMapId) then
		local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(targetMapId, entryMapId)
		if minX and maxX and minY and maxY then
			local width = maxX - minX
			local height = maxY - minY
			if width > 0 and height > 0 then
				local projX = (entryX - minX) / width
				local projY = (entryY - minY) / height
				-- Reject pins that fall outside the zone bounds (with small margin)
				if projX >= -0.05 and projX <= 1.05 and projY >= -0.05 and projY <= 1.05 then
					return projX, projY
				end
			end
		end
		return nil, nil
	end

	-- No parent/child relationship: maps are unrelated
	return nil, nil
end

-- Data provider mixin - manages pin lifecycle
local TeleportDataProvider = CreateFromMixins(MapCanvasDataProviderMixin)

function TeleportDataProvider:RemoveAllData()
	if self:GetMap() then
		self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
	end
end

function TeleportDataProvider:RefreshAllData(fromOnShow)
	if not self:GetMap() then
		return
	end
	self:RemoveAllData()

	if not module.CurrentSettings.showMapPins then
		return
	end

	local mapId = self:GetMap():GetMapID()
	if not mapId then
		return
	end

	-- Build a lookup of portal entries keyed by original mapId + coordinates for mage right-click
	local portalLookup = {}
	for _, expansion in ipairs(module.EXPANSION_ORDER) do
		local catEntries = module.teleportsByCategory[expansion]
		if catEntries then
			for _, entry in ipairs(catEntries) do
				if entry.isPortal and entry.available and entry.mapId and entry.mapX and entry.mapY then
					-- Key by original mapId + coordinates to avoid cross-map false matches
					local key = entry.mapId .. ':' .. tostring(entry.mapX) .. ':' .. tostring(entry.mapY)
					portalLookup[key] = entry
				end
			end
		end
	end

	-- Create pins for non-portal teleport entries, projecting coordinates to current map
	for _, expansion in ipairs(module.EXPANSION_ORDER) do
		local catEntries = module.teleportsByCategory[expansion]
		if catEntries then
			for _, entry in ipairs(catEntries) do
				if entry.available and entry.mapId and entry.mapX and entry.mapY and not entry.isPortal then
					local projX, projY = TransformCoordinates(entry.mapId, entry.mapX, entry.mapY, mapId)
					if projX and projY then
						-- Attach portal variant if available (for mage right-click)
						local portalKey = entry.mapId .. ':' .. tostring(entry.mapX) .. ':' .. tostring(entry.mapY)
						entry.portalEntry = portalLookup[portalKey]

						---@class SUI.TeleportAssist.PinData
						---@field entry SUI.TeleportAssist.TeleportEntry
						---@field projectedX number
						---@field projectedY number
						local pinData = {
							entry = entry,
							projectedX = projX,
							projectedY = projY,
						}
						self:GetMap():AcquirePin(PIN_TEMPLATE, pinData)
					end
				end
			end
		end
	end
end

---Initialize canvas pin system using MapCanvasDataProvider
function WorldMapIntegration:InitializePins()
	if not WorldMapFrame or dataProviderRegistered then
		return
	end

	-- Create pin pool (same technique as HereBeDragons-Pins-2.0)
	local pinPool
	if CreateUnsecuredRegionPoolInstance then
		pinPool = CreateUnsecuredRegionPoolInstance(PIN_TEMPLATE)
	else
		pinPool = CreateFramePool('FRAME')
	end

	pinPool.parent = WorldMapFrame:GetCanvas()

	local function createPin()
		local frame = CreateFrame('Frame', nil, WorldMapFrame:GetCanvas())
		frame:SetSize(1, 1)
		Mixin(frame, TeleportPinMixin)
		frame:OnLoad()
		return frame
	end

	local function resetPin(pool, pin)
		pin:Hide()
		pin:ClearAllPoints()
		pin:OnReleased()
		pin.pinTemplate = nil
		pin.owningMap = nil
	end

	-- Set both old and new field names for compatibility
	pinPool.createFunc = createPin
	pinPool.creationFunc = createPin
	pinPool.resetFunc = resetPin
	pinPool.resetterFunc = resetPin

	-- Register pin pool with the world map
	WorldMapFrame.pinPools[PIN_TEMPLATE] = pinPool

	-- Register data provider
	WorldMapFrame:AddDataProvider(TeleportDataProvider)
	dataProviderRegistered = true

	if module.logger then
		module.logger.debug('World Map canvas pins initialized (DataProvider)')
	end
end

---Refresh all map pins (called from options when settings change)
function WorldMapIntegration:RefreshPins()
	if dataProviderRegistered and TeleportDataProvider.GetMap and TeleportDataProvider:GetMap() then
		TeleportDataProvider:RefreshAllData()
	end
end

-- Expose WorldMapIntegration on module for options access
module.WorldMapIntegration = WorldMapIntegration
