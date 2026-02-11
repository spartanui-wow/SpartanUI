local SUI, L, Lib = SUI, SUI.L, SUI.Lib
local module = SUI:NewModule('Handler.HealHelper') ---@type SUI.Module
module.name = 'Heal helper'
module.description = 'SUI click to heal implementation'
----------------------------------------------------------------------------------------------------
local ActiveStateOverride, OverrideIsEnabled = false, false

function module:OnInitialize()
	---@alias HHActiveType
	---|"Enabled"
	---|"InCombat"
	---|"Disabled"

	---@class HHSettings
	local defaults = {
		Activate = {
			InRaid = 'Enabled', ---@type HHActiveType
			InParty = 'Enabled', ---@type HHActiveType
			InBG = 'Enabled', ---@type HHActiveType
			InArena = 'Enabled', ---@type HHActiveType
			WhenSolo = 'InCombat', ---@type HHActiveType
		},
		ChatOutput = true, ---When Enabled will output to chat on enable/disable change
		KeySets = {},
	}
	module.Database = SUI.SpartanUIDB:RegisterNamespace('HealHelper', { profile = defaults })
	module.DB = module.Database.profile ---@type HHSettings

	-- Register profile change callbacks
	SUI.DBM:RegisterSequentialProfileRefresh(module)
end

function module:OnEnable()
	if SUI:IsModuleDisabled('HealHelper') or SUI:IsModuleDisabled('UnitFrames') then
		return
	end
end
