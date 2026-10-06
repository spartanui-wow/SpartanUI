---@class SUI
local SUI = SUI
local L = SUI.L

-- Show the SpartanUI options in the shared settings window from Lib's AddonTools, with the helm
-- and the game and version after the name.

local Options = LibAT and LibAT.UI and LibAT.UI.Options
if not Options then
	return
end

local ACD = Options:Register('SpartanUI', {
	title = '|cffffffffSpartan|cffe21f1fUI|r',
	logo = 'Interface\\AddOns\\SpartanUI\\images\\Menu\\SUILogo_white.png',
	version = function()
		local parts = {}
		for _, value in ipairs({ SUI.wowVersion, SUI.Version, SUI.releaseType }) do
			if value and value ~= '' then
				parts[#parts + 1] = value
			end
		end
		return table.concat(parts, '  ')
	end,
})
ACD.AdvancedLabel = L['More settings']
