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
	mapPinSize = 15,
	showChallengesButtons = true,
	randomFromFavoritesOnly = false,
	collapsedCategories = {},
	position = {
		point = 'CENTER',
		relativeTo = 'UIParent',
		relativePoint = 'CENTER',
		x = 0,
		y = 0,
	},
	minimap = {
		hide = SUI.IsRetail, -- Retail: hidden (world map button), Classic: shown
		minimapPos = 220,
		lock = false,
	},
}

---@class SUI.Module.TeleportAssist.DBGlobal.Defaults
local DBGlobalDefaults = {
	favorites = {},
	rotationState = {
		remaining = {},
		lastUsed = nil,
	},
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

	-- Create hidden random hearthstone secure button
	module:CreateRandomHearthButton()

	-- Rebuild when new spells or toys are learned
	self:RegisterEvent('SPELLS_CHANGED', 'OnTeleportSourceChanged')
	self:RegisterEvent('NEW_TOY_ADDED', 'OnTeleportSourceChanged')

	-- Advance random hearthstone rotation when a hearthstone spell is cast
	self:RegisterEvent('UNIT_SPELLCAST_SUCCEEDED', function(_, unit, _, spellID)
		if unit ~= 'player' then
			return
		end
		if not SUI.BlizzAPI.canaccessvalue(spellID) then
			return
		end
		local current = module:GetCurrentRandomHearthstone()
		if current and current.spellId and spellID == current.spellId then
			C_Timer.After(1, function()
				module:AdvanceRandomHearthstone()
			end)
		end
	end)

	-- Handle deferred refresh after combat ends
	self:RegisterEvent('PLAYER_REGEN_ENABLED', function()
		if module.refreshPending and module.RefreshTeleportAssist then
			module:RefreshTeleportAssist()
		end
		if module.randomButtonUpdatePending then
			module.randomButtonUpdatePending = false
			module:UpdateRandomHearthButton()
		end
	end)

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

	-- Register chat commands
	SUI:AddChatCommand('tp', function()
		module:ToggleTeleportAssist()
	end, 'Toggle the teleport frame')

	-- Also register /tp as a standalone global command
	SUI:RegisterChatCommand('tp', function()
		module:ToggleTeleportAssist()
	end)
end

function module:OnTeleportSourceChanged()
	-- Debounce since SPELLS_CHANGED fires frequently
	if self.rebuildTimer then
		self:CancelTimer(self.rebuildTimer)
	end
	self.rebuildTimer = self:ScheduleTimer(function()
		self.rebuildTimer = nil
		module:BuildAvailableTeleports()
		if module.RefreshTeleportAssist then
			module:RefreshTeleportAssist()
		end
	end, 1)
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
	return PlayerHasToy(toyId) == true
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

-- ==================== RANDOM HEARTHSTONE ====================

local randomHearthButton = nil

---Get list of owned hearthstone IDs eligible for rotation
---@return table[] List of hearthstone entries {id, type, icon, name}
function module:GetOwnedHearthstones()
	local owned = {}
	local allOwned = {}
	local favoritesOnly = module.CurrentSettings.randomFromFavoritesOnly

	for _, hsVariant in ipairs(module.HEARTHSTONE_VARIANTS) do
		if not hsVariant.minExpansion or hsVariant.minExpansion <= module.currentExpansion then
			local available = false
			if hsVariant.isToy then
				available = IsToyAvailable(hsVariant.id)
			elseif hsVariant.isItem then
				available = IsItemAvailable(hsVariant.id)
			end
			if available then
				local hsType = hsVariant.isToy and 'toy' or 'item'
				local entry = {
					id = hsVariant.id,
					type = hsType,
					icon = hsVariant.icon,
					spellId = hsVariant.spellId,
					name = C_Item.GetItemNameByID(hsVariant.id) or ('Hearthstone (' .. hsVariant.id .. ')'),
				}
				table.insert(allOwned, entry)

				if favoritesOnly then
					local favKey = hsType .. '_' .. hsVariant.id
					if module.DBG.favorites[favKey] == true then
						table.insert(owned, entry)
					end
				else
					table.insert(owned, entry)
				end
			end
		end
	end

	-- Fallback: if favorites-only returned nothing, use all owned
	if #owned == 0 and #allOwned > 0 then
		return allOwned
	end

	return owned
end

---Pick the next random hearthstone using no-repeat shuffle
---@return table|nil The selected hearthstone entry, or nil if none available
function module:PickRandomHearthstone()
	local owned = module:GetOwnedHearthstones()
	if #owned == 0 then
		return nil
	end

	-- Single hearthstone, no rotation needed
	if #owned == 1 then
		module.DBG.rotationState.lastUsed = owned[1].id
		module.DBG.rotationState.remaining = {}
		return owned[1]
	end

	local state = module.DBG.rotationState

	-- Rebuild remaining list if empty or stale
	if not state.remaining or #state.remaining == 0 then
		state.remaining = {}
		for _, hs in ipairs(owned) do
			table.insert(state.remaining, hs.id)
		end
	end

	-- Clean out any IDs no longer in the owned set
	local ownedSet = {}
	for _, hs in ipairs(owned) do
		ownedSet[hs.id] = true
	end
	local cleaned = {}
	for _, id in ipairs(state.remaining) do
		if ownedSet[id] then
			table.insert(cleaned, id)
		end
	end
	state.remaining = cleaned

	-- If cleaning emptied it, refill
	if #state.remaining == 0 then
		for _, hs in ipairs(owned) do
			table.insert(state.remaining, hs.id)
		end
	end

	-- Anti-repeat: if lastUsed is in remaining and there are alternatives, exclude it from pick range
	local pickMax = #state.remaining
	if state.lastUsed and pickMax > 1 then
		for i, id in ipairs(state.remaining) do
			if id == state.lastUsed then
				-- Swap lastUsed to end so it's outside pickMax
				state.remaining[i] = state.remaining[pickMax]
				state.remaining[pickMax] = id
				pickMax = pickMax - 1
				break
			end
		end
	end

	-- Swap-and-pop random pick
	local pickIndex = math.random(1, pickMax)
	local pickedId = state.remaining[pickIndex]

	-- Swap picked to end and remove
	state.remaining[pickIndex] = state.remaining[#state.remaining]
	table.remove(state.remaining)

	state.lastUsed = pickedId

	-- Find the full entry for the picked ID
	for _, hs in ipairs(owned) do
		if hs.id == pickedId then
			return hs
		end
	end

	return nil
end

---Get the currently queued random hearthstone (without advancing)
---@return table|nil
function module:GetCurrentRandomHearthstone()
	local state = module.DBG.rotationState
	if state.lastUsed then
		-- Verify it's still owned
		local owned = module:GetOwnedHearthstones()
		for _, hs in ipairs(owned) do
			if hs.id == state.lastUsed then
				return hs
			end
		end
	end
	-- No valid current selection, pick one
	return module:PickRandomHearthstone()
end

---Update the hidden secure button attributes to match the current selection
function module:UpdateRandomHearthButton()
	if not randomHearthButton then
		return
	end
	if InCombatLockdown() then
		module.randomButtonUpdatePending = true
		return
	end

	local current = module:GetCurrentRandomHearthstone()
	if not current then
		randomHearthButton:SetAttribute('type', nil)
		return
	end

	randomHearthButton:SetAttribute('type', 'macro')
	randomHearthButton:SetAttribute('macrotext', '/use item:' .. current.id)

	if module.logger then
		module.logger.debug('Random HS button updated: type=' .. tostring(current.type) .. ' id=' .. tostring(current.id) .. ' name=' .. tostring(current.name))
		module.logger.debug('Button macrotext: ' .. tostring(randomHearthButton:GetAttribute('macrotext')))
	end

	-- Update companion macro if it already exists (safe outside hardware events)
	local macroIndex = GetMacroIndexByName('SUI Random HS')
	if macroIndex and macroIndex > 0 then
		module:UpdateRandomHearthMacro(current)
	end
end

---Advance rotation and update the button for the next use
function module:AdvanceRandomHearthstone()
	local next = module:PickRandomHearthstone()
	if next then
		module:UpdateRandomHearthButton()
	end
end

---Create or update the companion macro for dragging to action bars
---Must be called from a hardware event context (click/drag) for initial creation.
---@param current? table Current hearthstone entry
---@return boolean success Whether the macro exists after this call
function module:UpdateRandomHearthMacro(current)
	current = current or module:GetCurrentRandomHearthstone()
	if not current then
		return false
	end

	if InCombatLockdown() then
		return false
	end

	local macroName = 'SUI Random HS'
	local macroBody = '#showtooltip item:' .. current.id .. '\n/stopcasting\n/use item:' .. current.id

	-- Check if macro exists
	local existingIndex = GetMacroIndexByName(macroName)
	if existingIndex and existingIndex > 0 then
		-- Only update the body, keep the same name and use question mark icon
		-- so #showtooltip drives the display dynamically
		EditMacro(existingIndex, nil, nil, macroBody)
		return true
	end

	-- Try to create (requires hardware event context)
	-- Use question mark icon so #showtooltip dynamically shows the current item
	local numGlobal, _ = GetNumMacros()
	if numGlobal < MAX_ACCOUNT_MACROS then
		local newId = CreateMacro(macroName, 134400, macroBody, false)
		if module.logger then
			if newId then
				module.logger.info('Created "SUI Random HS" macro (id: ' .. newId .. ')')
			else
				module.logger.warning('Failed to create "SUI Random HS" macro')
			end
		end
		return newId ~= nil
	end

	if module.logger then
		module.logger.warning('Cannot create "SUI Random HS" macro - at account macro limit (' .. numGlobal .. '/' .. MAX_ACCOUNT_MACROS .. ')')
	end
	return false
end

---Create the hidden secure action button used by all panels
function module:CreateRandomHearthButton()
	if randomHearthButton then
		return
	end

	randomHearthButton = CreateFrame('Button', 'SUI_RandomHearthstone', UIParent, 'SecureActionButtonTemplate')
	randomHearthButton:SetSize(32, 32)
	randomHearthButton:SetPoint('TOP', UIParent, 'BOTTOM', 0, -100)
	randomHearthButton:SetAlpha(0)
	randomHearthButton:Show()
	randomHearthButton:RegisterForClicks('AnyUp')
	randomHearthButton:SetAttribute('type', 'macro')

	randomHearthButton:SetScript('PostClick', function()
		if not InCombatLockdown() then
			module:AdvanceRandomHearthstone()
		end
	end)

	-- Set initial selection
	module:UpdateRandomHearthButton()

	if module.logger then
		local current = module:GetCurrentRandomHearthstone()
		module.logger.debug('Random Hearthstone button created, current: ' .. (current and current.name or 'none'))
	end
end

---Build a synthetic entry for the Random Hearthstone button (used by all panels)
---@return table
function module:GetRandomHearthstoneEntry()
	local current = module:GetCurrentRandomHearthstone()
	return {
		id = current and current.id or 0,
		type = 'random_hearthstone',
		name = L['Random Hearthstone'],
		expansion = 'Home',
		icon = current and current.icon or 134414,
		available = current ~= nil,
		currentHearthstone = current,
	}
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
