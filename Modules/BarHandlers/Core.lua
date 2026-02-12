local SUI = SUI
---@class SUI.Module.BarHandler : SUI.Module
local module = SUI:NewModule('Handler.BarSystem')
local DB = nil
module.DisplayName = 'Bar Handler'
module.description = 'CORE: Handles the SpartanUI Bartender4 intergration'
module.Core = true
module.Registry = {}
module.BarPosition = {
	BT4 = {
		default = {
			['BT4Bar1'] = SUI.IsRetail and 'BOTTOM,SUI_BottomAnchor,BOTTOM,-451,100' or 'BOTTOM,SUI_BottomAnchor,BOTTOM,-367,80',
			['BT4Bar2'] = SUI.IsRetail and 'BOTTOM,SUI_BottomAnchor,BOTTOM,-451,33' or 'BOTTOM,SUI_BottomAnchor,BOTTOM,-368,28',
			['BT4Bar3'] = SUI.IsRetail and 'BOTTOM,SUI_BottomAnchor,BOTTOM,451,100' or 'BOTTOM,UIParent,BOTTOM,366,80',
			['BT4Bar4'] = SUI.IsRetail and 'BOTTOM,SUI_BottomAnchor,BOTTOM,451,33' or 'BOTTOM,UIParent,BOTTOM,367,27',
			['BT4Bar5'] = 'BOTTOMRIGHT,SUI_BottomAnchor,BOTTOMLEFT,-15,0',
			['BT4Bar6'] = 'BOTTOMLEFT,SUI_BottomAnchor,BOTTOMRIGHT,15,0',
			['BT4Bar7'] = '',
			['BT4Bar8'] = '',
			['BT4Bar9'] = '',
			['BT4Bar10'] = '',
			--
			['BT4BarZoneAbilityBar'] = 'BOTTOM,SUI_BottomAnchor,TOP,0,87',
			['BT4BarExtraActionBar'] = 'BOTTOM,SUI_BottomAnchor,TOP,0,87',
			--
			['BT4BarStanceBar'] = SUI.IsRetail and 'BOTTOM,SUI_BottomAnchor,BOTTOM,-285,192' or 'TOP,SpartanUI,TOP,-336,0',
			['BT4BarPetBar'] = SUI.IsRetail and 'BOTTOM,SUI_BottomAnchor,BOTTOM,-661,191' or 'TOP,SpartanUI,TOP,-645,0',
			--
			['BT4BarMicroMenu'] = SUI.IsRetail and 'BOTTOM,SUI_BottomAnchor,BOTTOM,340,191' or 'TOP,SpartanUI,TOP,374,0',
			['BT4BarBagBar'] = SUI.IsRetail and 'BOTTOM,SUI_BottomAnchor,BOTTOM,707,193' or 'TOP,SpartanUI,TOP,652,0',
			['BT4BarQueueStatus'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,-107,132',
		},
	},
}
module.BarScale = {
	BT4 = {
		default = {
			['BT4Bar1'] = SUI.IsRetail and 0.62 or 0.77,
			['BT4Bar2'] = SUI.IsRetail and 0.62 or 0.77,
			['BT4Bar3'] = SUI.IsRetail and 0.62 or 0.77,
			['BT4Bar4'] = SUI.IsRetail and 0.62 or 0.77,
			['BT4Bar5'] = SUI.IsRetail and 0.62 or 0.77,
			['BT4Bar6'] = SUI.IsRetail and 0.62 or 0.77,
			['BT4Bar7'] = SUI.IsRetail and 0.62 or 0.77,
			['BT4Bar8'] = SUI.IsRetail and 0.62 or 0.77,
			['BT4Bar9'] = SUI.IsRetail and 0.62 or 0.77,
			['BT4Bar10'] = SUI.IsRetail and 0.62 or 0.77,
			['BT4BarBagBar'] = 0.6,
			['BT4BarZoneAbilityBar'] = 0.8,
			['BT4BarExtraActionBar'] = 0.8,
			['BT4BarStanceBar'] = 0.6,
			['BT4BarPetBar'] = 0.6,
			['MultiCastActionBarFrame'] = 0.6,
			['BT4BarMicroMenu'] = 0.6,
			['BT4BarQueueStatus'] = 0.58,
		},
	},
}

------------------------------------------------------------

function module:AddBarSystem(name, OnInitialize, OnEnable, OnDisable, Unlocker, RefreshConfig)
	module.Registry[name] = {
		active = false,
		Initialize = OnInitialize,
		enable = OnEnable,
		disable = OnDisable,
		move = Unlocker,
		refresh = RefreshConfig,
	}
end

local function Options()
	---@type AceConfig.OptionsTable
	local OptTable = {
		name = 'Bar System',
		type = 'group',
		childGroups = 'tab',
		get = function(info)
			return DB[info[#info]]
		end,
		set = function(info, val)
			DB[info[#info]] = val
			SUI:reloadui()
		end,
		args = {
			ActiveSystem = {
				name = 'Active Bar System',
				type = 'select',
				order = 1,
				values = function()
					local t = {}
					for k, v in pairs(module.Registry) do
						t[k] = k
					end
					return t
				end,
				get = function()
					return DB.ActiveSystem
				end,
				set = function(_, val)
					DB.ActiveSystem = val
					SUI:reloadui()
				end,
			},
		},
	}

	-- for name, settings in pairs(module.Registry) do
	-- 	OptTable.args.enabledState.args[name] = {
	-- 		name = name,
	-- 		type = 'toggle',
	-- 		order = 1
	-- 	}

	-- 	if settings.Config then
	-- 		local SettingsScreen = {
	-- 			name = name,
	-- 			type = 'group',
	-- 			args = {}
	-- 		}
	-- 		settings.Config(SettingsScreen)
	-- 		OptTable.args[name] = SettingsScreen
	-- 	end
	-- end

	SUI.Options:AddOptions(OptTable, 'Bar System', 'General')
end

-- Hard code this for now.
function module:OnInitialize()
	-- Initialize logger
	if SUI.logger then
		module.logger = SUI.logger:RegisterCategory('BarHandler')
	end

	---@class SUI.BarHandler.DB
	local defaults = {
		ActiveSystem = 'Bartender4',
		custom = {
			scale = {
				BT4 = {},
			},
		},
	}
	module.Database = SUI.SpartanUIDB:RegisterNamespace('BarHandler', { profile = defaults })
	module.DB = module.Database.profile ---@type SUI.BarHandler.DB

	-- Register for sequential profile refresh with validation
	SUI.DBM:RegisterSequentialProfileRefresh(module, 'ValidateActiveSystem')
	DB = module.DB

	-- Initial validation for first load
	if SUI:IsAddonDisabled('Bartender4') then
		DB.ActiveSystem = 'WoW'
	elseif SUI:IsAddonEnabled('Bartender4') then
		DB.ActiveSystem = 'Bartender4'
	end
	if not module.Registry[DB.ActiveSystem] then
		DB.ActiveSystem = 'Bartender4'
	end

	Options()

	-- Do Setup
	module.Registry[DB.ActiveSystem]:Initialize()
end

function module:OnEnable()
	module.Registry[DB.ActiveSystem]:enable()
end

function module:Refresh()
	-- Defensive check - ensure ActiveSystem is set and registered
	if not DB.ActiveSystem or not module.Registry[DB.ActiveSystem] then
		-- Re-detect active system
		if SUI:IsAddonDisabled('Bartender4') then
			DB.ActiveSystem = 'WoW'
		elseif SUI:IsAddonEnabled('Bartender4') then
			DB.ActiveSystem = 'Bartender4'
		end

		-- If still not found, skip refresh
		if not DB.ActiveSystem or not module.Registry[DB.ActiveSystem] then
			return
		end
	end

	-- Safe to call refresh now
	if module.Registry[DB.ActiveSystem].refresh then
		module.Registry[DB.ActiveSystem]:refresh()
	end
end

---Validate ActiveSystem on profile change (only sets defaults for new profiles)
function module:ValidateActiveSystem()
	-- Update the local DB reference
	DB = module.DB

	-- Only set ActiveSystem if it's NOT already set (new/empty profile)
	if not DB.ActiveSystem then
		if SUI:IsAddonDisabled('Bartender4') then
			DB.ActiveSystem = 'Bartender4' -- Default even if disabled
		elseif SUI:IsAddonEnabled('Bartender4') then
			DB.ActiveSystem = 'Bartender4'
		end

		-- Ensure the system is registered
		if not module.Registry[DB.ActiveSystem] then
			DB.ActiveSystem = 'Bartender4' -- Fallback
		end
	else
		-- For existing profiles, just ensure the registry entry exists
		if not module.Registry[DB.ActiveSystem] then
			-- User's chosen system isn't available, fall back
			DB.ActiveSystem = 'Bartender4'
		end
	end
end

function module:MoveIt()
	if module.Registry[DB.ActiveSystem].move then
		module.Registry[DB.ActiveSystem]:move()
	end
end

SUI.Handlers.BarSystem = module
