local SUI, L = SUI, SUI.L
---@type SUI.Module.TeleportAssist
local module = SUI:GetModule('TeleportAssist')
----------------------------------------------------------------------------------------------------

-- State (UI only)
local mainFrame = nil

-- ==================== FRAME MANAGEMENT ====================

local UI = LibAT.UI

---Toggle the teleport frame visibility
function module:ToggleTeleportAssist()
	if not mainFrame then
		module:CreateTeleportAssist()
	end

	if mainFrame:IsShown() then
		mainFrame:Hide()
	else
		module:RefreshTeleportAssist()
		mainFrame:Show()
	end
end

---Refresh the teleport frame content
function module:RefreshTeleportAssist()
	if not mainFrame then
		return
	end
	if InCombatLockdown() then
		module.refreshPending = true
		return
	end
	module.refreshPending = false
	module:BuildAvailableTeleports()
	module:PopulateFrame()
end

---Hide the main frame (called from OnDisable)
function module:HideMainFrame()
	if mainFrame then
		mainFrame:Hide()
	end
end

---Create the main teleport frame using LibAT.UI
function module:CreateTeleportAssist()
	if mainFrame then
		return
	end

	-- Create window using LibAT.UI with modern styling
	mainFrame = UI.CreateWindow({
		name = 'SUI_TeleportAssist',
		title = '|cffffffffSpartan|cffe21f1fUI|r ' .. L['Teleport Assist'],
		width = 520,
		height = 480,
		hidePortrait = true,
	})

	-- Improve frame strata for better visibility
	mainFrame:SetFrameStrata('DIALOG')
	mainFrame:SetFrameLevel(100)

	-- Save position on drag stop
	mainFrame:HookScript('OnDragStop', function(self)
		local point, _, relativePoint, x, y = self:GetPoint()
		if not module.DB.position then
			module.DB.position = {}
		end
		module.DB.position.point = point
		module.DB.position.relativePoint = relativePoint
		module.DB.position.x = x
		module.DB.position.y = y
	end)

	-- Restore saved position
	if module.DB.position and module.DB.position.point then
		mainFrame:ClearAllPoints()
		mainFrame:SetPoint(module.DB.position.point, UIParent, module.DB.position.relativePoint, module.DB.position.x, module.DB.position.y)
	else
		-- Use default position from CurrentSettings
		local pos = module.CurrentSettings.position
		mainFrame:ClearAllPoints()
		mainFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
	end

	-- Create control frame for settings button
	mainFrame.ControlFrame = UI.CreateControlFrame(mainFrame)

	-- Add settings button
	mainFrame.SettingsButton = UI.CreateIconButton(mainFrame.ControlFrame, 'Warfronts-BaseMapIcons-Empty-Workshop', 'Warfronts-BaseMapIcons-Alliance-Workshop', 'Warfronts-BaseMapIcons-Horde-Workshop')
	mainFrame.SettingsButton:SetPoint('RIGHT', mainFrame.ControlFrame, 'RIGHT', -5, 0)
	mainFrame.SettingsButton:SetScript('OnClick', function()
		SUI.Options:OpenModuleSettings('TeleportAssist')
	end)

	-- Create main content area
	mainFrame.MainContent = UI.CreateContentFrame(mainFrame, mainFrame.ControlFrame)

	-- Add improved background with better visual integration
	mainFrame.MainContent.Background = mainFrame.MainContent:CreateTexture(nil, 'BACKGROUND')
	-- Use a more subtle, modern background texture
	mainFrame.MainContent.Background:SetAtlas('ChallengeMode-guild-background', true)
	mainFrame.MainContent.Background:SetAllPoints(mainFrame.MainContent)
	mainFrame.MainContent.Background:SetAlpha(0.8)

	-- Add border overlay for polish
	mainFrame.MainContent.BorderOverlay = mainFrame.MainContent:CreateTexture(nil, 'BORDER')
	mainFrame.MainContent.BorderOverlay:SetAtlas('ui-frame-genericmetal-cornertopl', true)
	mainFrame.MainContent.BorderOverlay:SetPoint('TOPLEFT', mainFrame.MainContent, 'TOPLEFT', 0, 0)
	mainFrame.MainContent.BorderOverlay:SetSize(64, 64)

	-- Create scroll frame for teleport buttons
	if ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
		-- Retail: use MinimalScrollBar
		mainFrame.ScrollFrame = CreateFrame('ScrollFrame', nil, mainFrame.MainContent)
		mainFrame.ScrollFrame:SetPoint('TOPLEFT', mainFrame.MainContent, 'TOPLEFT', 8, -8)
		mainFrame.ScrollFrame:SetPoint('BOTTOMRIGHT', mainFrame.MainContent, 'BOTTOMRIGHT', -8, 8)

		mainFrame.ScrollFrame.ScrollBar = CreateFrame('EventFrame', nil, mainFrame.ScrollFrame, 'MinimalScrollBar')
		mainFrame.ScrollFrame.ScrollBar:SetPoint('TOPLEFT', mainFrame.ScrollFrame, 'TOPRIGHT', 2, 0)
		mainFrame.ScrollFrame.ScrollBar:SetPoint('BOTTOMLEFT', mainFrame.ScrollFrame, 'BOTTOMRIGHT', 2, 0)
		ScrollUtil.InitScrollFrameWithScrollBar(mainFrame.ScrollFrame, mainFrame.ScrollFrame.ScrollBar)
	else
		-- Classic: use basic ScrollFrame with UIPanelScrollFrameTemplate
		mainFrame.ScrollFrame = CreateFrame('ScrollFrame', 'SUI_TeleportAssistScrollFrame', mainFrame.MainContent, 'UIPanelScrollFrameTemplate')
		mainFrame.ScrollFrame:SetPoint('TOPLEFT', mainFrame.MainContent, 'TOPLEFT', 8, -8)
		mainFrame.ScrollFrame:SetPoint('BOTTOMRIGHT', mainFrame.MainContent, 'BOTTOMRIGHT', -26, 8)
	end

	-- Content frame inside scroll
	mainFrame.Content = CreateFrame('Frame', nil, mainFrame.ScrollFrame)
	mainFrame.Content:SetSize(mainFrame.ScrollFrame:GetWidth() - 20, 1) -- Height set dynamically
	mainFrame.ScrollFrame:SetScrollChild(mainFrame.Content)

	-- Button pool for teleport buttons
	mainFrame.buttonPool = {}

	-- Header pool for category headers
	mainFrame.headerPool = {}

	mainFrame:Hide()

	-- Populate content
	module:PopulateFrame()
end

---Get or create a teleport button
---@param index number
---@param displayMode? string Display mode ('list', 'grid', 'compact')
---@param iconSize? number Icon size in pixels
---@return Button
function module:GetButton(index, displayMode, iconSize)
	displayMode = displayMode or 'list'
	iconSize = iconSize or 24

	if mainFrame.buttonPool[index] then
		local button = mainFrame.buttonPool[index]
		-- Update icon size and positioning dynamically for display mode changes
		button.Icon:SetSize(iconSize, iconSize)
		button.Icon:ClearAllPoints()
		button.Label:ClearAllPoints()

		-- Position icon based on display mode
		if displayMode == 'list' then
			-- List mode: icon on LEFT
			button.Icon:SetPoint('LEFT', button, 'LEFT', 4, 0)
			-- List mode: label to RIGHT of icon
			button.Label:SetPoint('LEFT', button.Icon, 'RIGHT', 8, 0)
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

		button.Cooldown:SetAllPoints(button.Icon)
		return button
	end

	-- Create button with flexible layout based on display mode
	local button = CreateFrame('Button', 'SUI_TeleportButton_' .. index, mainFrame.Content, 'SecureActionButtonTemplate')

	-- Background/border using action button styling
	button.Background = button:CreateTexture(nil, 'BACKGROUND')
	button.Background:SetAllPoints()
	button.Background:SetAtlas('adventureguide-itembutton-ring-border', true)

	-- Icon (size will be set dynamically)
	button.Icon = button:CreateTexture(nil, 'ARTWORK')
	button.Icon:SetSize(iconSize, iconSize)

	-- Position icon based on display mode
	if displayMode == 'list' then
		-- List mode: icon on LEFT
		button.Icon:SetPoint('LEFT', button, 'LEFT', 4, 0)
	else
		-- Grid/Compact mode: icon on TOP (centered)
		button.Icon:SetPoint('TOP', button, 'TOP', 0, -4)
	end

	-- Text label
	button.Label = button:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
	button.Label:SetWordWrap(false)

	-- Position label based on display mode
	if displayMode == 'list' then
		-- List mode: label to RIGHT of icon
		button.Label:SetPoint('LEFT', button.Icon, 'RIGHT', 8, 0)
		button.Label:SetPoint('RIGHT', button, 'RIGHT', -4, 0)
		button.Label:SetJustifyH('LEFT')
	else
		-- Grid/Compact mode: label BELOW icon (centered)
		button.Label:SetPoint('TOP', button.Icon, 'BOTTOM', 0, -2)
		button.Label:SetPoint('LEFT', button, 'LEFT', 2, 0)
		button.Label:SetPoint('RIGHT', button, 'RIGHT', -2, 0)
		button.Label:SetJustifyH('CENTER')
	end

	-- Cooldown (sized to match icon)
	button.Cooldown = CreateFrame('Cooldown', nil, button, 'CooldownFrameTemplate')
	button.Cooldown:SetAllPoints(button.Icon)

	-- Favorite star (on top of icon)
	button.FavoriteStar = button:CreateTexture(nil, 'OVERLAY')
	button.FavoriteStar:SetAtlas('PetJournal-FavoritesIcon', true)
	button.FavoriteStar:SetSize(16, 16)
	button.FavoriteStar:SetPoint('TOPLEFT', button.Icon, 'TOPLEFT', 0, 0)
	button.FavoriteStar:Hide()

	-- Unavailable overlay (on icon only)
	button.Unavailable = button:CreateTexture(nil, 'OVERLAY')
	button.Unavailable:SetAllPoints(button.Icon)
	button.Unavailable:SetColorTexture(0, 0, 0, 0.7)
	button.Unavailable:Hide()

	-- Highlight texture
	button.Highlight = button:CreateTexture(nil, 'HIGHLIGHT')
	button.Highlight:SetAllPoints()
	button.Highlight:SetAtlas('adventureguide-itembutton-selected', true)
	button.Highlight:SetBlendMode('ADD')

	-- Register clicks
	button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
	-- Mouse-only button: act on release, or the cast-on-key-down setting swallows every click
	button:SetAttribute('useOnKeyDown', false)

	-- Register drag for action bar placement
	button:RegisterForDrag('LeftButton')

	-- Set up script handlers (ONLY ONCE when button is created)
	-- Handle clicks for both favorites (right-click) and housing (left-click if housing type)
	button:SetScript('PreClick', function(self, mouseButton)
		if mouseButton == 'RightButton' then
			-- Disable secure action on right-click
			self:SetAttribute('type', nil)
		end
	end)

	button:SetScript('PostClick', function(self, mouseButton)
		local entry = self.entry
		if not entry then
			return
		end

		if mouseButton == 'RightButton' then
			module:ToggleFavorite(entry)
			-- Restore secure attribute
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
		if entry.type == 'spell' then
			GameTooltip:SetSpellByID(entry.spellId or entry.id)
		elseif entry.type == 'toy' then
			GameTooltip:SetToyByItemID(entry.id)
		elseif entry.type == 'item' then
			GameTooltip:SetItemByID(entry.id)
		elseif entry.type == 'macro' or entry.type == 'housing' then
			GameTooltip:AddLine(entry.name, 1, 1, 1)
		end
		GameTooltip:AddLine(' ')
		GameTooltip:AddLine(L['Right-click to toggle favorite'], 0.5, 0.5, 0.5)
		if not entry.available then
			GameTooltip:AddLine(L['Not available'], 1, 0.2, 0.2)
		end
		GameTooltip:Show()
	end)

	button:SetScript('OnLeave', function()
		GameTooltip:Hide()
	end)

	-- Drag-to-actionbar handlers
	button:SetScript('OnDragStart', function(self)
		module:PickupEntry(self.entry)
	end)

	mainFrame.buttonPool[index] = button
	return button
end

---Put a teleport on the cursor so it can be dropped on an action bar
---@param entry table|nil
function module:PickupEntry(entry)
	if not entry or not entry.available then
		return
	end

	if entry.type == 'spell' then
		C_Spell.PickupSpell(entry.spellId or entry.id)
	elseif entry.type == 'item' then
		C_Item.PickupItem(entry.id)
	elseif entry.type == 'toy' then
		if C_ToyBox and C_ToyBox.PickupToyBoxItem then
			C_ToyBox.PickupToyBoxItem(entry.id)
		else
			C_Item.PickupItem(entry.id)
		end
	end
end

---Get or create a category header
---@param index number
---@return FontString
function module:GetHeader(index)
	if mainFrame.headerPool[index] then
		return mainFrame.headerPool[index]
	end

	local header = mainFrame.Content:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
	header:SetTextColor(1, 0.82, 0) -- Gold color
	header:SetJustifyH('LEFT')

	mainFrame.headerPool[index] = header
	return header
end

---Set up a button for a teleport entry
---@param button Button
---@param entry table
function module:SetupButton(button, entry, displayMode, iconSize)
	displayMode = displayMode or 'list'
	iconSize = iconSize or 24
	button.entry = entry

	-- Update icon size if changed
	button.Icon:SetSize(iconSize, iconSize)

	-- Get icon
	local icon
	if entry.icon then
		icon = entry.icon
	elseif entry.type == 'spell' then
		icon = C_Spell.GetSpellTexture(entry.spellId or entry.id)
	elseif entry.type == 'toy' then
		local _, _, toyIcon = C_ToyBox.GetToyInfo(entry.id)
		icon = toyIcon or C_Item.GetItemIconByID(entry.id)
	elseif entry.type == 'item' then
		icon = C_Item.GetItemIconByID(entry.id)
	end

	-- Set texture or atlas
	if type(icon) == 'string' then
		-- Atlas name (string)
		button.Icon:SetAtlas(icon)
	else
		-- Texture ID (number) or fallback to question mark
		button.Icon:SetTexture(icon or 134400)
	end

	-- Set text label based on display settings
	local labelText = module:GetDisplayLabel(entry)
	if labelText then
		button.Label:SetText(labelText)
		button.Label:Show()
		-- Color coding: Gold for available, Gray for unavailable
		if entry.available then
			button.Label:SetTextColor(1.0, 0.82, 0.0) -- Gold
		else
			button.Label:SetTextColor(0.5, 0.5, 0.5) -- Gray
		end
	else
		-- Hide label if GetDisplayLabel returns nil
		button.Label:SetText('')
		button.Label:Hide()
	end

	-- Set secure attributes or OnClick handler
	if entry.available then
		if entry.type == 'spell' then
			button:SetAttribute('type', 'spell')
			button:SetAttribute('spell', entry.spellId or entry.id)
		elseif entry.type == 'toy' then
			button:SetAttribute('type', 'toy')
			button:SetAttribute('toy', entry.id)
		elseif entry.type == 'item' then
			button:SetAttribute('type', 'item')
			button:SetAttribute('item', 'item:' .. entry.id)
		elseif entry.type == 'macro' then
			button:SetAttribute('type', 'macro')
			button:SetAttribute('macrotext', entry.macro)
		elseif entry.type == 'housing' then
			-- Housing requires direct API call (handled in PostClick)
			button:SetAttribute('type', nil)
		end
		button.Unavailable:Hide()
		button.Icon:SetDesaturated(false)
	else
		button:SetAttribute('type', nil)
		button.Unavailable:Show()
		button.Icon:SetDesaturated(true)
	end

	-- Favorite star
	if module:IsFavorite(entry) then
		button.FavoriteStar:Show()
	else
		button.FavoriteStar:Hide()
	end

	-- Note: All script handlers (PreClick, PostClick, OnEnter, OnLeave, OnDragStart)
	-- are set up once in GetButton() to avoid creating multiple handlers on every refresh

	button:Show()
end

---Populate the frame with teleport buttons
function module:PopulateFrame()
	if not mainFrame then
		return
	end

	-- Hide all existing buttons and headers
	for _, button in pairs(mainFrame.buttonPool) do
		button:Hide()
	end
	for _, header in pairs(mainFrame.headerPool) do
		header:Hide()
	end

	local buttonIndex = 1
	local headerIndex = 1
	local yOffset = 0
	local spacing = 2
	local contentWidth = mainFrame.Content:GetWidth()

	-- Display mode configuration
	local settings = module.CurrentSettings
	local displayMode = settings.displayMode or 'list'
	local buttonWidth, buttonHeight, iconSize, columnCount

	if displayMode == 'grid' then
		buttonWidth = 80
		buttonHeight = 95
		iconSize = 48
		columnCount = 3
	elseif displayMode == 'compact' then
		buttonWidth = 90
		buttonHeight = 70
		iconSize = 36
		columnCount = 3
	else -- 'list'
		buttonWidth = 280
		buttonHeight = 32
		iconSize = 24
		columnCount = 1
	end

	-- Helper to add a category section (supports multi-column layouts)
	local function AddCategory(categoryName, entries)
		if #entries == 0 then
			return
		end

		-- Category header (spans full width)
		local header = module:GetHeader(headerIndex)
		header:ClearAllPoints()
		header:SetPoint('TOPLEFT', mainFrame.Content, 'TOPLEFT', 4, -yOffset)
		header:SetText(module.EXPANSION_NAMES[categoryName] or categoryName)
		header:Show()
		headerIndex = headerIndex + 1
		yOffset = yOffset + 22

		-- Add buttons in grid/list layout
		local currentColumn = 0
		local rowStartY = yOffset

		for _, entry in ipairs(entries) do
			local button = module:GetButton(buttonIndex, displayMode, iconSize)
			button:SetSize(buttonWidth, buttonHeight)
			button:ClearAllPoints()

			-- Calculate position based on column
			local xOffset = 4 + (currentColumn * (buttonWidth + spacing))
			button:SetPoint('TOPLEFT', mainFrame.Content, 'TOPLEFT', xOffset, -yOffset)
			module:SetupButton(button, entry, displayMode, iconSize)

			buttonIndex = buttonIndex + 1
			currentColumn = currentColumn + 1

			-- Move to next row when columns filled
			if currentColumn >= columnCount then
				currentColumn = 0
				yOffset = yOffset + buttonHeight + spacing
			end
		end

		-- If we didn't finish a complete row, move to next row
		if currentColumn > 0 then
			yOffset = yOffset + buttonHeight + spacing
		end

		yOffset = yOffset + 12 -- Extra spacing between categories
	end

	-- Add favorites first if enabled
	if module.CurrentSettings.showFavoritesFirst then
		local favorites = module:GetFavorites()
		if #favorites > 0 then
			AddCategory('Favorites', favorites)
		end
	end

	-- Add each expansion category
	for _, expansion in ipairs(module.EXPANSION_ORDER) do
		local entries = module.teleportsByCategory[expansion]
		if entries then
			-- Filter out favorites if shown separately
			local filteredEntries = {}
			for _, entry in ipairs(entries) do
				if not module.CurrentSettings.showFavoritesFirst or not module:IsFavorite(entry) then
					table.insert(filteredEntries, entry)
				end
			end
			AddCategory(expansion, filteredEntries)
		end
	end

	-- Update content height
	mainFrame.Content:SetHeight(math.max(yOffset + 20, mainFrame.ScrollFrame:GetHeight()))
end
