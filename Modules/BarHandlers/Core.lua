local SUI = SUI
local L = SUI.L
---@class SUI.Module.BarHandler : SUI.Module
local module = SUI:NewModule('Handler.BarSystem')
local DB = nil
module.DisplayName = 'Bar Handler'
module.description = 'CORE: Chooses what draws the action bars: SpartanUI, Bartender4 or Blizzard'
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

local SYSTEM_NAMES = {
	SpartanUI = 'SpartanUI',
	Bartender4 = 'Bartender4',
	WoW = 'Blizzard',
}

---Another addon that already draws action bars, if one is running.
---@return string|nil
function module:GetExternalBarAddon()
	if C_AddOns.IsAddOnLoaded('Dominos') then
		return 'Dominos'
	end
	local E = C_AddOns.IsAddOnLoaded('ElvUI') and _G.ElvUI and _G.ElvUI[1]
	if E and E.private and E.private.actionbar and E.private.actionbar.enable then
		return 'ElvUI'
	end
	return nil
end

---The bar system the player asked for. Nil means "pick automatically".
---@return string|nil
function module:GetChosenSystem()
	return DB and DB.ActiveSystem
end

---The bar system that actually runs this session. Bartender4 wins while it is loaded,
---SpartanUI's own bars take over when it is not, and nothing is touched when another
---action bar addon is in charge.
---@return string system
---@return string|nil reason Why the choice differs from what the player picked
function module:GetEffectiveSystem()
	local chosen = self:GetChosenSystem()
	local bt4Loaded = Bartender4 ~= nil
	local external = self:GetExternalBarAddon()

	if chosen == 'WoW' then
		return 'WoW'
	end
	if chosen == nil then
		chosen = bt4Loaded and 'Bartender4' or 'SpartanUI'
	end
	if chosen == 'Bartender4' then
		if bt4Loaded then
			return 'Bartender4'
		end
		chosen = 'SpartanUI'
	end
	if chosen == 'SpartanUI' then
		if bt4Loaded then
			return 'Bartender4', 'bt4loaded'
		end
		if external then
			return 'None', external
		end
	end
	if not module.Registry[chosen] then
		return 'None', 'missing'
	end
	return chosen
end

local function Options()
	---@type AceConfig.OptionsTable
	local OptTable = {
		name = L['Bar System'],
		type = 'group',
		childGroups = 'tab',
		args = {
			ActiveSystem = {
				name = L['Active Bar System'],
				desc = L['Choose what draws your action bars. Changing this reloads your UI.'],
				type = 'select',
				order = 1,
				width = 'double',
				values = function()
					local t = { auto = L['Automatic'] }
					for k in pairs(module.Registry) do
						t[k] = SYSTEM_NAMES[k] or k
					end
					return t
				end,
				get = function()
					return DB.ActiveSystem or 'auto'
				end,
				set = function(_, val)
					module:SetChosenSystem(val ~= 'auto' and val or nil)
				end,
			},
			status = {
				name = function()
					local effective, reason = module:GetEffectiveSystem()
					if reason == 'bt4loaded' then
						return L['SpartanUI bars are selected, but Bartender4 is still enabled. Disable Bartender4 to switch.']
					elseif effective == 'None' and reason then
						return (L['%s is drawing your action bars, so SpartanUI leaves them alone.']):format(reason)
					end
					return (L['Currently using: %s']):format(SYSTEM_NAMES[effective] or effective)
				end,
				type = 'description',
				order = 2,
				fontSize = 'medium',
			},
		},
	}

	SUI.Options:AddOptions(OptTable, 'Bar System', 'General')
end

---Store the player's bar system choice, disable Bartender4 when switching away from it,
---and reload.
---@param system string|nil
function module:SetChosenSystem(system)
	DB.ActiveSystem = system
	DB.systemChosen = true
	if system == 'SpartanUI' and Bartender4 then
		C_AddOns.DisableAddOn('Bartender4', UnitName('player'))
	elseif system == 'Bartender4' and not Bartender4 then
		C_AddOns.EnableAddOn('Bartender4', UnitName('player'))
	end
	SUI:reloadui()
end

function module:OnInitialize()
	if SUI.logger then
		module.logger = SUI.logger:RegisterCategory('BarHandler')
	end

	---@class SUI.BarHandler.DB
	local defaults = {
		ActiveSystem = nil,
		systemChosen = false,
		custom = {
			scale = {
				BT4 = {},
			},
		},
	}
	module.Database = SUI.SpartanUIDB:RegisterNamespace('BarHandler', { profile = defaults })
	module.DB = module.Database.profile ---@type SUI.BarHandler.DB

	SUI.DBM:RegisterSequentialProfileRefresh(module)
	DB = module.DB

	-- Older versions wrote 'WoW' automatically whenever Bartender4 was missing. That was
	-- never the player's choice, so let automatic selection pick SpartanUI's bars instead.
	if DB.ActiveSystem == 'WoW' and not DB.systemChosen then
		DB.ActiveSystem = nil
	end

	Options()
end

function module:OnEnable()
	local effective, reason = self:GetEffectiveSystem()
	module.activeSystem = effective
	if module.logger then
		module.logger.info(('Bar system: %s%s'):format(effective, reason and (' (' .. reason .. ')') or ''))
	end
	if reason == 'bt4loaded' and not InCombatLockdown() then
		SUI:Print(L['SpartanUI bars are selected, but Bartender4 is still enabled. Disable Bartender4 to switch.'])
	end

	local entry = module.Registry[effective]
	if entry then
		if entry.Initialize then
			entry:Initialize()
		end
		entry:enable()
	end
end

---The system running this session.
---@return string
function module:GetActiveSystem()
	return module.activeSystem or self:GetEffectiveSystem()
end

---The frame the active bar system uses for a bar. Keys are the Bartender4 bar names that
---themes use (BT4Bar1, BT4BarPetBar ...), whichever system is running.
---@param key string
---@return Frame|nil
function module:GetBarFrame(key)
	local system = module:GetActiveSystem()
	if system == 'SpartanUI' then
		return SUI.ActionBars and SUI.ActionBars:IsActive() and SUI.ActionBars:GetBar(key) or nil
	elseif system == 'Bartender4' then
		return _G[key]
	end
	return nil
end

---The frame that outlines a bar's buttons, for artwork drawn behind a bar.
---@param key string
---@return Frame|nil
function module:GetBarOverlay(key)
	local system = module:GetActiveSystem()
	if system == 'Bartender4' then
		return _G[key .. 'Overlay']
	end
	return module:GetBarFrame(key)
end

---Place a bar the way a theme asks, unless the player moved it.
---@param key string
function module:PositionBar(key, point, anchor, relativePoint, x, y)
	local frame = module:GetBarFrame(key)
	if frame and frame.position then
		frame:position(point, anchor, relativePoint, x, y)
	end
end

---Hide or show a bar for a sliding tray. SpartanUI bars are secure, so they go through
---their visibility rules instead of a plain Hide.
---@param key string
---@param hidden boolean
---@return boolean handled False when no bar system owns this bar
function module:SetBarTrayHidden(key, hidden)
	local frame = module:GetBarFrame(key)
	if not frame then
		return false
	end
	if frame.SetTrayHidden then
		frame:SetTrayHidden(hidden)
	elseif hidden then
		frame:Hide()
	else
		frame:Show()
	end
	return true
end

function module:Refresh()
	local entry = module.Registry[module:GetActiveSystem()]
	if entry and entry.refresh then
		entry:refresh()
	end
end

function module:ReloadDB()
	DB = module.DB
end

function module:MoveIt()
	local entry = module.Registry[module:GetActiveSystem()]
	if entry and entry.move then
		entry:move()
	end
end

SUI.Handlers.BarSystem = module
