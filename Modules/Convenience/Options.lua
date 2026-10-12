local SUI, L = SUI, SUI.L
---@class SUI.Module.Convenience
local module = SUI:GetModule('Convenience')
----------------------------------------------------------------------------------------------------

function module:BuildOptions()
	local DB = module:GetDB()

	---@type AceConfig.OptionsTable
	local OptionTable = {
		type = 'group',
		name = L['Convenience'],
		disabled = function()
			return SUI:IsModuleDisabled(module)
		end,
		args = {
			autoAcceptSummon = {
				name = L['Auto-accept summons'],
				desc = L['Automatically accept summon requests when not in combat'],
				type = 'toggle',
				order = 1,
				width = 'full',
				get = function()
					return DB.autoAcceptSummon
				end,
				set = function(_, val)
					DB.autoAcceptSummon = val
				end,
			},
			autoAcceptResurrection = {
				name = L['Auto-accept resurrections'],
				desc = L['Automatically accept resurrection requests when not in combat'],
				type = 'toggle',
				order = 2,
				width = 'full',
				get = function()
					return DB.autoAcceptResurrection
				end,
				set = function(_, val)
					DB.autoAcceptResurrection = val
				end,
			},
			autoReleaseInPvP = {
				name = L['Auto-release in PvP'],
				desc = L['Automatically release spirit in battlegrounds, arenas, and PvP zones'],
				type = 'toggle',
				order = 3,
				width = 'full',
				get = function()
					return DB.autoReleaseInPvP
				end,
				set = function(_, val)
					DB.autoReleaseInPvP = val
				end,
			},
			tweaksHeader = {
				name = 'Game Tweaks',
				type = 'header',
				order = 10,
			},
			tweaksDesc = {
				name = 'These settings adjust game CVars. They are normally applied during first-run setup but can be re-applied here.',
				type = 'description',
				order = 11,
				fontSize = 'medium',
				width = 'full',
			},
			applyTweaks = {
				name = 'Apply Recommended Tweaks',
				desc = 'Disables personal nameplate, enables all nameplates, and disables all tutorials',
				type = 'execute',
				order = 12,
				width = 'full',
				func = function()
					SetCVar('nameplateShowSelf', 0)
					SetCVar('nameplateShowAll', 1)
					SetCVar('showTutorials', 0)
					SUI:Print('Recommended game tweaks applied.')
				end,
			},
		},
	}

	SUI.Options:AddOptions(OptionTable, 'Convenience')
end
