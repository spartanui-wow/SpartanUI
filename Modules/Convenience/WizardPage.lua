local SUI, L = SUI, SUI.L
---@class SUI.Module.Convenience
local module = SUI:GetModule('Convenience')

function module:RegisterSetupWizardPage()
	if not (SUI.Setup and SUI.Setup.AddHelpers) then
		return
	end
	local DB = module:GetDB()
	local function Item(key, title, caption)
		return {
			key = 'convenience:' .. key,
			title = title,
			caption = caption,
			module = 'Convenience',
			get = function()
				return DB[key] and true or false
			end,
			set = function(value)
				DB[key] = value
			end,
		}
	end
	SUI.Setup:AddHelpers('groups', {
		Item('autoAcceptSummon', L['Accept summons'], L['Only out of combat.']),
		Item('autoAcceptResurrection', L['Accept resurrections'], L['Only out of combat.']),
		Item('autoReleaseInPvP', L['Release your spirit in battlegrounds'], L['Saves a click after every death in PvP.']),
	})
end
