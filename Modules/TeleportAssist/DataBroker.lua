---@class SUI
local SUI = SUI
local L = SUI.L

---@class SUI.Module.TeleportAssist
local module = SUI:GetModule('TeleportAssist')

----------------------------------------------------------------------------------------------------
-- LibDataBroker Integration
----------------------------------------------------------------------------------------------------

local LDB = LibStub('LibDataBroker-1.1', true)
local LDBIcon = LibStub('LibDBIcon-1.0', true)
local dataObj = nil ---@type table|nil

---Create or update the LDB data object
local function CreateDataObject()
	if not LDB then
		if module.logger then
			module.logger.warning('LibDataBroker-1.1 not available')
		end
		return
	end

	if dataObj then
		return dataObj
	end

	dataObj = LDB:NewDataObject('SUI_TeleportAssist', {
		type = 'launcher',
		text = L['Teleports'],
		label = L['Teleports'],
		icon = 'Interface\\Icons\\Spell_Arcane_TeleportStormwind',
		OnClick = function(_, button)
			if button == 'LeftButton' then
				module:ToggleTeleportAssist()
			elseif button == 'RightButton' then
				SUI.Options:OpenModuleSettings('TeleportAssist')
			end
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddLine('|cffffffffSpartan|cffe21f1fUI|r ' .. L['Teleport Assist'])
			tooltip:AddLine(' ')

			-- Count available teleports
			local availableCount = 0
			local favoriteCount = 0
			for _, entry in ipairs(module:GetAllTeleports()) do
				if entry.available then
					availableCount = availableCount + 1
				end
				if module:IsFavorite(entry) then
					favoriteCount = favoriteCount + 1
				end
			end

			tooltip:AddDoubleLine(L['Available Teleports:'], availableCount, 1, 1, 1, 0.2, 1, 0.2)
			if favoriteCount > 0 then
				tooltip:AddDoubleLine(L['Favorites:'], favoriteCount, 1, 1, 1, 1, 0.82, 0)
			end

			tooltip:AddLine(' ')
			tooltip:AddLine('|cff888888' .. L['Left-click: Toggle teleport frame'] .. '|r')
			tooltip:AddLine('|cff888888' .. L['Right-click: Open settings'] .. '|r')
		end,
	})

	return dataObj
end

---Register minimap button with LibDBIcon
local function RegisterMinimapButton()
	if not LDBIcon then
		if module.logger then
			module.logger.warning('LibDBIcon-1.0 not available')
		end
		return
	end

	if not dataObj then
		return
	end

	-- Smart default: Retail hides (world map button provides access), Classic shows (no map integration)
	-- DBDefault is hide=true, so only need to override for Classic
	if not module.DB.minimapDefaultApplied then
		module.DB.minimapDefaultApplied = true
		if not SUI.IsRetail then
			module.DB.minimap.hide = false
		end
	end

	-- LDBIcon needs to use DB.minimap for persistence
	LDBIcon:Register('SUI_TeleportAssist', dataObj, module.DB.minimap)

	-- Apply initial visibility from CurrentSettings
	if module.CurrentSettings.minimap.hide then
		LDBIcon:Hide('SUI_TeleportAssist')
	else
		LDBIcon:Show('SUI_TeleportAssist')
	end

	-- Fix z-order: Set frame strata and level higher to appear above other minimap elements
	-- This ensures the icon appears above Mapster's quest log and other minimap frames
	C_Timer.After(0.5, function()
		local minimapButton = LDBIcon:GetMinimapButton('SUI_TeleportAssist')
		if minimapButton then
			minimapButton:SetFrameStrata('TOOLTIP')
			minimapButton:SetFrameLevel(100)
		end
	end)
end

---Update minimap button visibility
function module:UpdateMinimapButton()
	if not LDBIcon then
		return
	end

	if module.CurrentSettings.minimap.hide then
		LDBIcon:Hide('SUI_TeleportAssist')
	else
		LDBIcon:Show('SUI_TeleportAssist')
	end
end

----------------------------------------------------------------------------------------------------
-- Helper Functions
----------------------------------------------------------------------------------------------------

---Get all teleport entries (for tooltip display)
---@return table[]
function module:GetAllTeleports()
	-- Access the local availableTeleports via refresh
	local teleports = {}
	for _, expansion in ipairs(module.EXPANSION_ORDER or {}) do
		local entries = module.teleportsByCategory and module.teleportsByCategory[expansion]
		if entries then
			for _, entry in ipairs(entries) do
				table.insert(teleports, entry)
			end
		end
	end
	return teleports
end

----------------------------------------------------------------------------------------------------
-- Module Integration
----------------------------------------------------------------------------------------------------

---Initialize the DataBroker plugin
function module:InitDataBroker()
	-- Initialize minimap settings in DB if not present (for LDBIcon persistence)
	-- Must copy from DBDefaults to respect the default hide state
	if not module.DB.minimap then
		module.DB.minimap = CopyTable(module.DBDefaults.minimap)
	end

	CreateDataObject()
	RegisterMinimapButton()

	if module.logger then
		module.logger.debug('DataBroker initialized')
	end
end

-- Note: InitDataBroker is called from the main TeleportAssist.lua OnEnable
