local SUI, L = SUI, SUI.L
---@class SUI.Module.Convenience
local module = SUI:GetModule('Convenience')

function module:RegisterSetupWizardPage()
	if not LibAT or not LibAT.SetupWizard then
		return
	end

	if LibAT.SetupWizard:GetPage('spartanui', 'convenience') then
		return
	end

	local DB = module:GetDB()

	LibAT.SetupWizard:AddPage('spartanui', {
		id = 'convenience',
		name = L['Convenience'],
		order = 54,
		builder = function(contentFrame)
			local widgets, totalHeight = LibAT.UI.BuildWidgets(contentFrame, {
				cvarsHeader = {
					type = 'header',
					name = 'UI Tweaks',
					order = 1,
				},
				disablePersonalNameplate = {
					type = 'checkbox',
					name = 'Disable personal nameplate',
					desc = 'Hides the nameplate under your character',
					order = 2,
					get = function()
						return GetCVar('nameplateShowSelf') == '0'
					end,
					set = function(_, val)
						SetCVar('nameplateShowSelf', val and '0' or '1')
					end,
				},
				enableNameplates = {
					type = 'checkbox',
					name = 'Enable enemy nameplates',
					desc = 'Shows nameplates above enemies',
					order = 3,
					get = function()
						return GetCVar('nameplateShowAll') == '1'
					end,
					set = function(_, val)
						SetCVar('nameplateShowAll', val and '1' or '0')
					end,
				},
				disableTutorials = {
					type = 'checkbox',
					name = 'Disable all tutorials',
					desc = 'For experienced players - disables all in-game tutorial popups',
					order = 4,
					get = function()
						return GetCVar('showTutorials') == '0'
					end,
					set = function(_, val)
						if val then
							SetCVar('showTutorials', 0)
						else
							SetCVar('showTutorials', 1)
						end
					end,
				},
				convenienceHeader = {
					type = 'header',
					name = L['Convenience'],
					order = 10,
				},
				autoAcceptSummon = {
					type = 'checkbox',
					name = 'Auto-accept summons',
					desc = 'Automatically accept summons when out of combat',
					order = 11,
					get = function()
						return DB.autoAcceptSummon
					end,
					set = function(_, val)
						DB.autoAcceptSummon = val
					end,
				},
				autoAcceptResurrection = {
					type = 'checkbox',
					name = 'Auto-accept resurrections',
					desc = 'Automatically accept resurrection requests when out of combat',
					order = 12,
					get = function()
						return DB.autoAcceptResurrection
					end,
					set = function(_, val)
						DB.autoAcceptResurrection = val
					end,
				},
				autoReleaseInPvP = {
					type = 'checkbox',
					name = 'Auto-release in PvP',
					desc = 'Automatically release spirit when dying in battlegrounds or arenas',
					order = 13,
					get = function()
						return DB.autoReleaseInPvP
					end,
					set = function(_, val)
						DB.autoReleaseInPvP = val
					end,
				},
			}, contentFrame:GetWidth())

			contentFrame:SetHeight(totalHeight)
		end,
	})
end
