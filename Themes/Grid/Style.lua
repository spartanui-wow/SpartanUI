local SUI = SUI
---@class SUI.Theme.Grid : SUI.Theme.StyleBase
local module = SUI:NewModule('Style.Grid')

function module:OnInitialize()
	if SUI.UF then
		SUI.UF.Style:Register('Grid', {
			displayName = 'Grid',
			setup = {
				image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Frames_Grid',
			},
		})
	end
end

function module:OnEnable()
	-- Grid theme has no artwork to manage
	-- All frame overrides are in DBdefault.Styles.Grid.Frames
end

function module:OnDisable()
	-- Nothing to clean up
end
