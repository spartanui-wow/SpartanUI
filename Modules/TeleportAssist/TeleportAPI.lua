local SUI, L = SUI, SUI.L
---@class SUI.Module.TeleportAssist : SUI.Module
local module = SUI:NewModule('TeleportAssist')
module.DisplayName = L['Teleport Assist']
module.description = 'Quick access panel for all available teleports, portals, and travel items'
----------------------------------------------------------------------------------------------------

-- Determine max expansion available on this game client
local currentExpansion = GetServerExpansionLevel()
module.currentExpansion = currentExpansion

---@class SUI.Module.TeleportAssist.DB.Defaults
local DBDefaults = {
	enabled = true,
	frameScale = 1.0,
	buttonsPerRow = 8,
	buttonSize = 34,
	showTooltips = true,
	hideUnavailable = true,
	showFavoritesFirst = true,
	displayMode = 'list', -- 'grid', 'list', 'compact'
	labelMode = 'full', -- 'full', 'abbreviated', 'none'
	hideHearthstoneLabels = false,
	showAllHearthstones = true,
	showMapPins = true,
	mapPinSize = 20,
	showChallengesButtons = true,
	collapsedCategories = {},
	minimapDefaultApplied = 0, -- Tracks version of minimap defaults (for migration)
	position = {
		point = 'CENTER',
		relativeTo = 'UIParent',
		relativePoint = 'CENTER',
		x = 0,
		y = 0,
	},
	minimap = {
		hide = true,
		minimapPos = 220,
		lock = false,
	},
}

---@class SUI.Module.TeleportAssist.DBGlobal.Defaults
local DBGlobalDefaults = {
	favorites = {},
}

-- State
local availableTeleports = {}
local playerHouses = {} -- Store house list from C_Housing API

-- Expose teleportsByCategory on module for DataBroker access
module.teleportsByCategory = {}

-- Expose defaults for access
module.DBDefaults = DBDefaults
module.DBGlobalDefaults = DBGlobalDefaults

-- Current settings (merged defaults + user settings)
module.CurrentSettings = {}

---Reload settings after options change
function module:UpdateSettings()
	SUI.DBM:RefreshSettings(module)
	if module.RefreshTeleportAssist then
		module:RefreshTeleportAssist()
	end
end

-- ==================== MODULE LIFECYCLE ====================

function module:OnInitialize()
	-- Setup database with Configuration Override Pattern
	SUI.DBM:SetupModule(module, DBDefaults, DBGlobalDefaults, {
		autoCalculateDepth = true, -- Auto-detect nesting depth
	})

	-- Register logger
	if SUI.logger then
		module.logger = SUI.logger:RegisterCategory('TeleportAssist')
	end
end

function module:OnEnable()
	if SUI:IsModuleDisabled('TeleportAssist') then
		return
	end

	-- Check if required data files are loaded
	if not module.EXPANSION_ORDER or not module.HEARTHSTONE_VARIANTS or not module.TELEPORT_DATA then
		if module.logger then
			module.logger.error('TeleportAssist: Required data files not loaded (TeleportData.lua missing)')
		end
		module.Disabled = true
		return
	end

	-- Initialize housing support (Retail only - C_Housing API)
	if SUI.IsRetail then
		module:InitializeHousingSupport()
	end

	-- Build available teleports list
	module:BuildAvailableTeleports()

	-- Build options (from Options.lua - loaded later)
	if module.BuildOptions then
		module:BuildOptions()
	end

	-- Initialize DataBroker (from DataBroker.lua - loaded later)
	if module.InitDataBroker then
		module:InitDataBroker()
	end

	-- Initialize World Map integration (Retail only - from WorldMapIntegration.lua)
	if SUI.IsRetail and WorldMapFrame and module.InitializeWorldMapIntegration then
		module:InitializeWorldMapIntegration()
	end

	-- Initialize Challenges UI integration (Retail only - from ChallengesIntegration.lua)
	if SUI.IsRetail and module.InitializeChallengesIntegration then
		module:InitializeChallengesIntegration()
	end

	-- Initialize SpellBook tab (Classic clients only - from SpellBookTab.lua)
	if not SUI.IsRetail and module.InitSpellBookTab then
		module:InitSpellBookTab()
	end

	-- Register chat command
	SUI:AddChatCommand('tp', function()
		module:ToggleTeleportAssist()
	end, 'Toggle the teleport frame')
end

function module:OnDisable()
	-- Handled in TeleportAssist.lua (UI cleanup)
	if module.HideMainFrame then
		module:HideMainFrame()
	end
end

-- ==================== AVAILABILITY CHECKING ====================

---Check if a toy is available
---@param toyId number
---@return boolean
local function IsToyAvailable(toyId)
	if not PlayerHasToy then
		return false
	end
	if not PlayerHasToy(toyId) then
		return false
	end
	if C_ToyBox and C_ToyBox.IsToyUsable then
		return C_ToyBox.IsToyUsable(toyId)
	end
	return true
end

---Check if an item is in inventory
---@param itemId number
---@return boolean
local function IsItemAvailable(itemId)
	if C_Item and C_Item.GetItemCount then
		return C_Item.GetItemCount(itemId) > 0
	end
	return false
end

---Check if player has engineering profession
---@return boolean
local function HasEngineering()
	local prof1, prof2 = GetProfessions()
	for _, profIndex in ipairs({ prof1, prof2 }) do
		if profIndex then
			local _, _, _, _, _, _, skillLine = GetProfessionInfo(profIndex)
			if skillLine == 202 then -- Engineering skill line ID
				return true
			end
		end
	end
	return false
end

---Check if a teleport entry is available to the player
---@param entry SUI.TeleportAssist.TeleportEntry
---@return boolean
function module:IsTeleportAvailable(entry)
	-- Check expansion requirement
	if entry.minExpansion and entry.minExpansion > module.currentExpansion then
		return false
	end

	-- Check class restriction
	if entry.class then
		local _, playerClass = UnitClass('player')
		if entry.class ~= playerClass then
			return false
		end
	end

	-- Check race restriction
	if entry.race then
		local _, playerRace = UnitRace('player')
		-- Normalize race name (remove spaces)
		playerRace = playerRace:gsub(' ', '')
		if entry.race ~= playerRace then
			return false
		end
	end

	-- Check faction restriction
	if entry.faction then
		local playerFaction = UnitFactionGroup('player')
		if entry.faction ~= playerFaction then
			return false
		end
	end

	-- Check engineering requirement
	if entry.isEngineering and not HasEngineering() then
		return false
	end

	-- Custom availability check (for macro types, etc.)
	if entry.availableCheck then
		return entry.availableCheck()
	end

	-- Check by type
	if entry.type == 'spell' then
		return C_SpellBook.IsSpellInSpellBook(entry.id)
	elseif entry.type == 'toy' then
		return IsToyAvailable(entry.id)
	elseif entry.type == 'item' then
		return IsItemAvailable(entry.id)
	elseif entry.type == 'macro' or entry.type == 'housing' then
		return true -- Macros/housing are always "available" if they pass restriction checks above
	end

	return false
end

---Get abbreviated name for a teleport
---@param name string Full name
---@return string Abbreviated name
function module:GetAbbreviatedName(name)
	-- Common abbreviations
	local abbrev = name
	abbrev = abbrev:gsub('Hearthstone', 'HS')
	abbrev = abbrev:gsub('Teleport:', 'TP:')
	abbrev = abbrev:gsub('Portal:', 'P:')
	abbrev = abbrev:gsub('Dalaran', 'Dal')
	abbrev = abbrev:gsub('Stormwind', 'SW')
	abbrev = abbrev:gsub('Orgrimmar', 'Org')
	abbrev = abbrev:gsub('Darnassus', 'Darn')
	abbrev = abbrev:gsub('Ironforge', 'IF')
	abbrev = abbrev:gsub('Thunder Bluff', 'TB')
	abbrev = abbrev:gsub('Undercity', 'UC')
	abbrev = abbrev:gsub('Shattrath', 'Shat')
	abbrev = abbrev:gsub('Stonard', 'Ston')
	abbrev = abbrev:gsub('Theramore', 'Thera')
	abbrev = abbrev:gsub('the ', '')
	abbrev = abbrev:gsub('The ', '')
	return abbrev
end

---Get label for display based on settings
---@param entry table Teleport entry
---@return string|nil Label text or nil to hide
function module:GetDisplayLabel(entry)
	local settings = module.CurrentSettings

	-- Check if this is a hearthstone and labels should be hidden
	if settings.hideHearthstoneLabels and entry.isHearthstone then
		return nil
	end

	-- Check label mode
	if settings.labelMode == 'none' then
		return nil
	elseif settings.labelMode == 'abbreviated' then
		return module:GetAbbreviatedName(entry.name)
	else
		return entry.name
	end
end

---Build the list of available teleports
function module:BuildAvailableTeleports()
	availableTeleports = {}
	module.teleportsByCategory = {}

	-- Initialize categories
	for _, expansion in ipairs(module.EXPANSION_ORDER) do
		module.teleportsByCategory[expansion] = {}
	end

	-- Add player houses as separate entries
	if playerHouses and #playerHouses > 0 then
		-- Alternate between two housing atlas icons
		local housingIcons = {
			'dashboard-panel-homestone-teleport-button',
			'housing-dashboard-homestone-icon',
		}

		for houseIndex, houseInfo in ipairs(playerHouses) do
			local iconIndex = ((houseIndex - 1) % #housingIcons) + 1
			local entry = {
				id = 0,
				type = 'housing',
				name = houseInfo.houseName or ('House ' .. houseIndex),
				expansion = 'Home',
				icon = housingIcons[iconIndex], -- Atlas name (string)
				houseIndex = houseIndex, -- Store index for selection
				houseGUID = houseInfo.houseGUID,
				neighborhoodGUID = houseInfo.neighborhoodGUID,
				availableCheck = function()
					return C_Housing and C_Housing.IsHousingServiceEnabled and C_Housing.IsHousingServiceEnabled() and C_Housing.HasHousingExpansionAccess and C_Housing.HasHousingExpansionAccess()
				end,
				available = true,
			}
			table.insert(module.teleportsByCategory['Home'], entry)
			table.insert(availableTeleports, entry)
		end
	end

	-- Add all available hearthstones to Home category
	for _, hsVariant in ipairs(module.HEARTHSTONE_VARIANTS) do
		-- Skip hearthstones not available in this expansion
		if not hsVariant.minExpansion or hsVariant.minExpansion <= module.currentExpansion then
			local available = false
			if hsVariant.isToy then
				available = IsToyAvailable(hsVariant.id)
			elseif hsVariant.isItem then
				available = IsItemAvailable(hsVariant.id)
			end

			-- Check showAllHearthstones setting
			local shouldShow = false
			if module.CurrentSettings.showAllHearthstones then
				-- Show all hearthstones regardless of availability
				shouldShow = true
			else
				-- Only show if available
				shouldShow = available
			end

			-- Also respect hideUnavailable setting
			if not available and module.CurrentSettings.hideUnavailable then
				shouldShow = false
			end

			if shouldShow then
				-- Get actual item name
				local itemName = C_Item.GetItemNameByID(hsVariant.id) or ('Hearthstone (' .. hsVariant.id .. ')')

				local entry = {
					id = hsVariant.id,
					spellId = hsVariant.spellId,
					type = hsVariant.isToy and 'toy' or 'item',
					name = itemName,
					expansion = 'Home',
					icon = hsVariant.icon,
					isHearthstone = true,
					available = available,
				}
				table.insert(module.teleportsByCategory['Home'], entry)
				table.insert(availableTeleports, entry)
			end
		end
	end

	-- Process all teleport entries
	for _, entry in ipairs(module.TELEPORT_DATA) do
		local available = module:IsTeleportAvailable(entry)

		-- Skip unavailable entries if hideUnavailable is enabled
		if available or not module.CurrentSettings.hideUnavailable then
			local teleportEntry = {
				id = entry.id,
				spellId = entry.spellId or entry.id,
				type = entry.type,
				macro = entry.macro,
				name = entry.name,
				expansion = entry.expansion,
				icon = entry.icon,
				class = entry.class,
				faction = entry.faction,
				isPortal = entry.isPortal,
				isEngineering = entry.isEngineering,
				isHearthstone = entry.isHearthstone,
				availableCheck = entry.availableCheck,
				available = available,
				mapId = entry.mapId,
				mapX = entry.mapX,
				mapY = entry.mapY,
			}

			if module.teleportsByCategory[entry.expansion] then
				table.insert(module.teleportsByCategory[entry.expansion], teleportEntry)
			end
			table.insert(availableTeleports, teleportEntry)
		end
	end

	if module.logger then
		module.logger.debug('Built teleport list: ' .. #availableTeleports .. ' entries')
	end
end

-- ==================== FAVORITES ====================

---Check if a teleport is favorited
---@param entry table
---@return boolean
function module:IsFavorite(entry)
	local key = entry.type .. '_' .. entry.id
	return module.DBG.favorites[key] == true
end

---Toggle favorite status
---@param entry table
function module:ToggleFavorite(entry)
	local key = entry.type .. '_' .. entry.id
	if module.DBG.favorites[key] then
		module.DBG.favorites[key] = nil
	else
		module.DBG.favorites[key] = true
	end
	-- Refresh the frame (calls UI layer)
	if module.RefreshTeleportAssist then
		module:RefreshTeleportAssist()
	end
end

---Get all favorites
---@return table[]
function module:GetFavorites()
	local favorites = {}
	for _, entry in ipairs(availableTeleports) do
		if module:IsFavorite(entry) then
			table.insert(favorites, entry)
		end
	end
	return favorites
end

-- ==================== HOUSING API ====================

---Get player houses list
---@return table
function module:GetPlayerHouses()
	return playerHouses
end

---Set up housing event handler for direct teleport
function module:InitializeHousingSupport()
	if C_Housing and C_Housing.IsHousingServiceEnabled and C_Housing.IsHousingServiceEnabled() then
		module:RegisterEvent('PLAYER_HOUSE_LIST_UPDATED', function(event, houseInfos)
			playerHouses = houseInfos or {}
			if module.logger then
				module.logger.debug('Updated player houses, count: ' .. #playerHouses)
			end
			-- Rebuild teleport list to include individual house buttons
			module:BuildAvailableTeleports()
			-- Refresh UI if visible
			if module.RefreshTeleportFrame then
				module:RefreshTeleportFrame()
			end
		end)

		-- Force load Housing Dashboard addon and request house list
		C_Timer.After(2, function()
			-- Load the Housing Dashboard addon (LoadOnDemand)
			if not C_AddOns.IsAddOnLoaded('Blizzard_HousingDashboard') then
				C_AddOns.LoadAddOn('Blizzard_HousingDashboard')
				if module.logger then
					module.logger.debug('Loaded Blizzard_HousingDashboard addon')
				end
			end

			-- Request player house list (triggers PLAYER_HOUSE_LIST_UPDATED event)
			if C_Housing and C_Housing.GetPlayerOwnedHouses then
				C_Housing.GetPlayerOwnedHouses()
				if module.logger then
					module.logger.debug('Requested player owned houses')
				end
			end
		end)
	end
end
