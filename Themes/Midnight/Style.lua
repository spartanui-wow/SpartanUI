local SUI = SUI
---@class SUI.Theme.Midnight : SUI.Theme.StyleBase
local module = SUI:NewModule('Style.Midnight')

function module:OnInitialize()
	if SUI.UF then
		SUI.UF.Style:Register('Midnight', {
			displayName = 'Midnight',
			description = 'Modern, clean interface inspired by ElvUI. Features minimalist design with focus on readability and larger, well-spaced aura icons.',
			setup = {
				image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Frames_Classic', -- Reuse Classic setup image for now
			},
		})
	end
end

function module:OnEnable()
	-- Midnight theme has no artwork to manage
	-- All frame overrides are in SUI.DB.Styles.Midnight.Frames (defined in Core/Framework.lua)
end

function module:OnDisable()
	-- Nothing to clean up
end
