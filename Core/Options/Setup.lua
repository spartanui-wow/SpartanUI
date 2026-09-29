---@class SUI
local SUI = SUI
local L = SUI.L

-- Route the SpartanUI options through the SUI window and widgets. Widget types that are not
-- registered fall back to the stock AceGUI ones inside AceConfigDialog-3.0-SUI.

local ACD = LibStub('AceConfigDialog-3.0-SUI', true)
if not ACD then
	return
end

ACD:SetFrameType('SpartanUI', 'SUI-Window', true)
ACD:SetWidgetMap('SpartanUI', {
	CheckBox = 'SUI-Switch',
	Slider = 'SUI-Slider',
	EditBox = 'SUI-EditBox',
	Button = 'SUI-Button',
	Heading = 'SUI-Heading',
	ColorPicker = 'SUI-ColorPicker',
	Dropdown = 'SUI-Dropdown',
	Segmented = 'SUI-Segmented',
	Expander = 'SUI-Expander',
	InlineGroup = 'SUI-InlineGroup',
	ScrollFrame = 'SUI-ScrollFrame',
	TabGroup = 'SUI-TabGroup',
	TreeGroup = 'SUI-TreeGroup',
	PageGroup = 'SUI-PageGroup',
})
ACD.AdvancedLabel = L['More settings']
