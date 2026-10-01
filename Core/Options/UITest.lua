---@class SUI
local SUI = SUI

-- A developer window with two of every settings control, for checking each window kit.
-- `/sui uitest` opens it. It uses the same controls as the options window. Nothing on it is saved.

local APP = 'SpartanUI_UITest'

local values = {
	toggleA = true,
	toggleB = false,
	tristate = nil,
	rangeA = 42,
	rangeB = 0.75,
	select = 'b',
	radio = 'two',
	short = 'left',
	long = 'option3',
	multi = { a = true, c = true },
	inputA = 'Some text',
	inputB = 'Line one\nLine two',
	colorA = { 0.2, 0.6, 1, 1 },
	colorB = { 0.9, 0.3, 0.2, 0.5 },
	font = 'Roboto Condensed Bold',
	statusbar = 'Blizzard',
	background = 'Blizzard Dialog Background',
	border = 'Blizzard Tooltip',
	sound = 'None',
	key = '',
}

local function Get(info)
	local value = values[info[#info]]
	if type(value) == 'table' and info.type == 'color' then
		return value[1], value[2], value[3], value[4]
	end
	return value
end

local function Set(info, value, g, b, a)
	if info.type == 'color' then
		values[info[#info]] = { value, g, b, a or 1 }
	else
		values[info[#info]] = value
	end
end

local function GetMulti(info, key)
	return values[info[#info]][key]
end

local function SetMulti(info, key, state)
	values[info[#info]][key] = state
end

local function Disabled()
	return true
end

local LETTERS = { a = 'Alpha', b = 'Bravo', c = 'Charlie', d = 'Delta' }
local NUMBERS = { one = 'One', two = 'Two', three = 'Three' }
local LONG = {}
for i = 1, 12 do
	LONG['option' .. i] = 'Longer option name number ' .. i
end

local function Build()
	local L = SUI.L
	local order = 0
	local function O()
		order = order + 1
		return order
	end
	return {
		type = 'group',
		name = 'UI test',
		desc = 'Two of every settings control, for checking window kits',
		order = 1,
		get = Get,
		set = Set,
		args = {
			intro = {
				type = 'description',
				name = 'Every control appears twice; the second is often disabled. Nothing here is saved.',
				fontSize = 'medium',
				order = O(),
			},
			headerToggles = { type = 'header', name = 'Toggles', order = O() },
			toggleA = { type = 'toggle', name = 'Toggle', desc = 'A normal toggle', order = O() },
			toggleB = { type = 'toggle', name = 'Disabled toggle', desc = 'Cannot be changed', disabled = Disabled, order = O() },
			tristate = { type = 'toggle', name = 'Three-state toggle', tristate = true, order = O() },
			headerRanges = { type = 'header', name = 'Sliders', order = O() },
			rangeA = { type = 'range', name = 'Slider', min = 0, max = 100, step = 1, order = O() },
			rangeB = { type = 'range', name = 'Percent slider', min = 0, max = 1, isPercent = true, order = O() },
			rangeC = {
				type = 'range',
				name = 'Disabled slider',
				min = 0,
				max = 100,
				step = 1,
				disabled = Disabled,
				order = O(),
				get = function()
					return 30
				end,
			},
			headerSelects = { type = 'header', name = 'Choices', order = O() },
			select = { type = 'select', name = 'Dropdown', values = LETTERS, dialogControl = 'dropdown', order = O() },
			long = { type = 'select', name = 'Long dropdown', values = LONG, order = O() },
			short = { type = 'select', name = 'Segmented', values = { left = 'Left', center = 'Center', right = 'Right' }, order = O() },
			shortB = {
				type = 'select',
				name = 'Disabled segmented',
				values = { up = 'Up', down = 'Down' },
				disabled = Disabled,
				order = O(),
				get = function()
					return 'up'
				end,
			},
			radio = { type = 'select', name = 'Radio list', style = 'radio', values = NUMBERS, order = O() },
			multi = { type = 'multiselect', name = 'Multi-select', values = LETTERS, get = GetMulti, set = SetMulti, order = O() },
			headerMedia = { type = 'header', name = 'Shared media', order = O() },
			font = { type = 'select', name = 'Font', dialogControl = 'LSM30_Font', values = SUI.Lib.LSM:HashTable('font'), order = O() },
			statusbar = { type = 'select', name = 'Bar texture', dialogControl = 'LSM30_Statusbar', values = SUI.Lib.LSM:HashTable('statusbar'), order = O() },
			background = { type = 'select', name = 'Background', dialogControl = 'LSM30_Background', values = SUI.Lib.LSM:HashTable('background'), order = O() },
			border = { type = 'select', name = 'Border', dialogControl = 'LSM30_Border', values = SUI.Lib.LSM:HashTable('border'), order = O() },
			sound = { type = 'select', name = 'Sound', dialogControl = 'LSM30_Sound', values = SUI.Lib.LSM:HashTable('sound'), order = O() },
			headerInputs = { type = 'header', name = 'Text', order = O() },
			inputA = { type = 'input', name = 'Text box', desc = 'One line of text', order = O() },
			inputB = { type = 'input', name = 'Multi-line text box', multiline = 4, width = 'full', order = O() },
			inputC = {
				type = 'input',
				name = 'Disabled text box',
				disabled = Disabled,
				order = O(),
				get = function()
					return 'Read only'
				end,
			},
			headerColors = { type = 'header', name = 'Colors', order = O() },
			colorA = { type = 'color', name = 'Color', order = O() },
			colorB = { type = 'color', name = 'Color with alpha', hasAlpha = true, order = O() },
			headerButtons = { type = 'header', name = 'Buttons', order = O() },
			buttonA = { type = 'execute', name = 'Button', func = function() end, order = O() },
			buttonB = { type = 'execute', name = 'Primary button', primary = true, func = function() end, order = O() },
			buttonC = { type = 'execute', name = 'Asks first', confirm = true, confirmText = 'Are you sure?', func = function() end, order = O() },
			buttonD = { type = 'execute', name = 'Disabled button', disabled = Disabled, func = function() end, order = O() },
			key = { type = 'keybinding', name = 'Key binding', order = O() },
			headerGroups = { type = 'header', name = 'Groups and text', order = O() },
			inlineA = {
				type = 'group',
				name = 'Inline group',
				inline = true,
				order = O(),
				args = {
					text = { type = 'description', name = 'A description inside an inline group, long enough to wrap onto a second line so wrapping can be checked.', order = 1 },
					toggle = {
						type = 'toggle',
						name = 'Toggle in a group',
						order = 2,
						get = function()
							return values.toggleA
						end,
						set = function(_, v)
							values.toggleA = v
						end,
					},
				},
			},
			inlineB = {
				type = 'group',
				name = 'Second inline group',
				inline = true,
				order = O(),
				args = {
					big = { type = 'description', name = 'Large description text', fontSize = 'large', order = 1 },
					image = { type = 'description', name = 'Description with an image', image = 'Interface\\Icons\\INV_Misc_QuestionMark', imageWidth = 24, imageHeight = 24, order = 2 },
				},
			},
			advancedA = { type = 'toggle', name = 'Advanced toggle', advanced = true, order = O() },
			advancedB = {
				type = 'range',
				name = 'Advanced slider',
				advanced = true,
				min = 0,
				max = 10,
				step = 1,
				order = O(),
				get = function()
					return 5
				end,
				set = function() end,
			},
			tabs = {
				type = 'group',
				name = 'Tabs',
				childGroups = 'tab',
				order = O(),
				args = {
					first = { type = 'group', name = 'First tab', order = 1, args = { text = { type = 'description', name = 'Content of the first tab.', order = 1 } } },
					second = { type = 'group', name = 'Second tab', order = 2, args = { text = { type = 'description', name = 'Content of the second tab.', order = 1 } } },
				},
			},
			tree = {
				type = 'group',
				name = 'Tree',
				childGroups = 'tree',
				order = O(),
				args = {
					first = { type = 'group', name = 'First branch', order = 1, args = { text = { type = 'description', name = 'First branch content.', order = 1 } } },
					second = { type = 'group', name = 'Second branch', order = 2, args = { text = { type = 'description', name = 'Second branch content.', order = 1 } } },
				},
			},
		},
	}
end

---Tabs at the top level, so each page scrolls on its own: the controls, then the group demos.
local function BuildApp()
	local controls = Build()
	local tabs, tree = controls.args.tabs, controls.args.tree
	controls.args.tabs, controls.args.tree = nil, nil
	controls.name = 'Controls'
	tabs.order, tree.order = 2, 3
	return {
		type = 'group',
		name = 'UI test',
		childGroups = 'tab',
		get = Get,
		set = Set,
		args = { controls = controls, tabs = tabs, tree = tree },
	}
end

local window, container

local function Open()
	local ACD = LibStub('AceConfigDialog-3.0-SUI', true)
	local AceGUI = LibStub('AceGUI-3.0', true)
	if not ACD or not AceGUI then
		return
	end
	if not window then
		LibStub('AceConfigRegistry-3.0'):RegisterOptionsTable(APP, BuildApp(), true)
		ACD:SetWidgetMap(APP, ACD.WidgetMaps['SpartanUI'])
		window = LibAT.UI.Kit:CreateShell({
			name = 'SUI_UITestWindow',
			title = 'UI test',
			width = 900,
			height = 640,
			strata = 'DIALOG',
			resizable = true,
			minWidth = 600,
			minHeight = 400,
		})
		container = AceGUI:Create('SimpleGroup')
		container:SetLayout('Fill')
		container.frame:SetParent(window.Body)
		container.frame:ClearAllPoints()
		container.frame:SetAllPoints(window.Body)
		container.frame:Show()
		-- AceGUI lays out by the sizes it is given, so pass the body's size on
		window.Body:HookScript('OnSizeChanged', function(_, width, height)
			container:SetWidth(width)
			container:SetHeight(height)
			container:DoLayout()
		end)
	end
	window:Show()
	container:SetWidth(window.Body:GetWidth())
	container:SetHeight(window.Body:GetHeight())
	ACD:Open(APP, container)
end

local module = SUI:NewModule('Handler.UITest')

function module:OnInitialize()
	SUI:AddChatCommand('uitest', function()
		if window and window:IsShown() then
			window:Hide()
		else
			Open()
		end
	end, 'Open the window with every settings control (for testing window looks)')
end
