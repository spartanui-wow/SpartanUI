---@type SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.ActionBars
local module = SUI:GetModule('ActionBars')

local _, playerClass = UnitClass('player')
local playerClassName = UnitClass('player')

local GROWTH_POINTS = {
	TOPLEFT = L['Right and down'],
	TOPRIGHT = L['Left and down'],
	BOTTOMLEFT = L['Right and up'],
	BOTTOMRIGHT = L['Left and up'],
}

local FLYOUT_DIRECTIONS = {
	AUTOMATIC = L['Automatic'],
	UP = L['Up'],
	DOWN = L['Down'],
	LEFT = L['Left'],
	RIGHT = L['Right'],
}

local TEXT_ANCHORS = {
	TOPLEFT = L['Top left'],
	TOP = L['Top'],
	TOPRIGHT = L['Top right'],
	LEFT = L['Left'],
	CENTER = L['Center'],
	RIGHT = L['Right'],
	BOTTOMLEFT = L['Bottom left'],
	BOTTOM = L['Bottom'],
	BOTTOMRIGHT = L['Bottom right'],
}

local FONT_FLAGS = {
	[''] = L['None'],
	OUTLINE = L['Outline'],
	THICKOUTLINE = L['Thick outline'],
	MONOCHROME = L['Monochrome'],
	['MONOCHROME,OUTLINE'] = L['Monochrome outline'],
}

----------------------------------------------------------------------------------------------------
-- Storage helpers
----------------------------------------------------------------------------------------------------

---@param root table
---@param path any[]
---@param create? boolean
---@return table|nil
local function Walk(root, path, create)
	local t = root
	for _, key in ipairs(path) do
		if t[key] == nil then
			if not create then
				return nil
			end
			t[key] = {}
		end
		t = t[key]
	end
	return t
end

---Read a merged setting.
---@param path any[]
---@param key string
---@return any
function module:GetSetting(path, key)
	local t = Walk(self.CurrentSettings, path)
	return t and t[key]
end

---Write a setting, storing nothing when the value matches the default.
---@param path any[]
---@param key string
---@param value any
function module:SetSetting(path, key, value)
	local target = Walk(self.DB, path, true)
	local defaults = Walk(self.DBDefaults, path)
	local default = defaults and defaults[key]
	if type(value) ~= 'table' and value == default then
		target[key] = nil
	else
		target[key] = value
	end
	SUI.DBM:RefreshSettings(self)
end

----------------------------------------------------------------------------------------------------
-- Shared bar option builders
----------------------------------------------------------------------------------------------------

---@param bar SUI.ActionBars.Bar
---@param path any[]
---@return table getset
local function BarGetSet(bar, path)
	return {
		get = function(info)
			return module:GetSetting(path, info[#info])
		end,
		set = function(info, value)
			module:SetSetting(path, info[#info], value)
			bar:Apply()
			if bar.id then
				module:UpdateKeybinds()
			end
		end,
	}
end

---Validate a visibility or paging macro condition string.
---@param _ table
---@param value string
---@return true|string
local function ValidateConditions(_, value)
	if value == nil or value:gsub('%s', '') == '' then
		return true
	end
	local ok = pcall(SecureCmdOptionParse, value)
	if not ok then
		return L['That condition is not valid. Check the brackets and semicolons.']
	end
	return true
end

---Options every bar type shares: layout, size, fading and visibility.
---@param bar SUI.ActionBars.Bar
---@param path any[]
---@param features table Which optional controls to show
---@return table args
local function BuildCommonBarArgs(bar, path, features)
	local args = {
		enabled = {
			name = L['Enabled'],
			type = 'toggle',
			order = 1,
		},
		resetBar = {
			name = L['Reset this bar'],
			desc = L['Put this bar back to SpartanUI defaults, including its position.'],
			type = 'execute',
			order = 2,
			func = function()
				local target = Walk(module.DB, path)
				if target then
					wipe(target)
				end
				SUI.DBM:RefreshSettings(module)
				local MoveIt = SUI:GetModule('MoveIt', true) ---@type MoveIt
				if MoveIt and bar.mover then
					MoveIt:Reset(bar.key)
				end
				bar:Apply()
				module:ApplyThemeLayout()
			end,
		},
		layoutHeader = { name = L['Layout'], type = 'header', order = 10 },
		buttonsPerRow = {
			name = L['Buttons per row'],
			type = 'range',
			order = 12,
			min = 1,
			max = features.maxButtons or 12,
			step = 1,
		},
		point = {
			name = L['Growth direction'],
			desc = L['Which way new buttons and rows are added.'],
			type = 'select',
			order = 13,
			values = GROWTH_POINTS,
		},
		buttonSize = {
			name = L['Button size'],
			type = 'range',
			order = 14,
			min = 12,
			max = 128,
			step = 1,
		},
		keepSizeRatio = {
			name = L['Square buttons'],
			desc = L['Keep buttons as wide as they are tall.'],
			type = 'toggle',
			order = 15,
		},
		buttonHeight = {
			name = L['Button height'],
			type = 'range',
			order = 16,
			min = 12,
			max = 128,
			step = 1,
			hidden = function()
				return module:GetSetting(path, 'keepSizeRatio') ~= false
			end,
		},
		buttonSpacing = {
			name = L['Button spacing'],
			type = 'range',
			order = 17,
			min = -10,
			max = 30,
			step = 1,
		},
		backdrop = {
			name = L['Show backdrop'],
			type = 'toggle',
			order = 18,
		},
		backdropSpacing = {
			name = L['Backdrop padding'],
			desc = L['Space between the edge of the bar and its buttons.'],
			type = 'range',
			order = 19,
			min = 0,
			max = 20,
			step = 1,
		},
		zoom = {
			name = L['Crop icon borders'],
			type = 'toggle',
			order = 20,
			hidden = function()
				return not bar.cropIcons
			end,
		},
		clickThrough = {
			name = L['Click through'],
			desc = L['Mouse clicks pass through this bar to whatever is behind it.'],
			type = 'toggle',
			order = 21,
		},
		frameStrata = {
			name = L['Layer'],
			desc = L['Which layer the bar is drawn on. Higher layers cover lower ones.'],
			type = 'select',
			order = 28,
			values = {
				[''] = L['Default'],
				BACKGROUND = L['Background'],
				LOW = L['Low'],
				MEDIUM = L['Medium'],
				HIGH = L['High'],
			},
		},
		frameLevel = {
			name = L['Layer order'],
			desc = L['Order within the layer. 0 keeps the default.'],
			type = 'range',
			order = 29,
			min = 0,
			max = 100,
			step = 1,
		},
		fadeHeader = { name = L['Fading'], type = 'header', order = 30 },
		alpha = {
			name = L['Opacity'],
			type = 'range',
			order = 31,
			min = 0,
			max = 1,
			step = 0.05,
			isPercent = true,
		},
		mouseover = {
			name = L['Show on mouseover'],
			desc = L['Fade the bar out until you point at it.'],
			type = 'toggle',
			order = 32,
		},
		mouseoverAlpha = {
			name = L['Faded opacity'],
			type = 'range',
			order = 33,
			min = 0,
			max = 1,
			step = 0.05,
			isPercent = true,
			disabled = function()
				return not module:GetSetting(path, 'mouseover')
			end,
		},
		inheritGlobalFade = {
			name = L['Use global fade'],
			desc = L['Fade this bar along with the others while you are idle. Turn global fade on in the General tab.'],
			type = 'toggle',
			order = 34,
		},
		visibilityHeader = { name = L['Visibility'], type = 'header', order = 40 },
		visibility = {
			name = L['Show / hide rules'],
			desc = L['Macro conditions deciding when the bar shows, for example: [combat] show; hide'],
			type = 'input',
			multiline = 3,
			width = 'full',
			order = 41,
			validate = ValidateConditions,
		},
	}
	if features.hotkeyText then
		args.hotkeyText = { name = L['Show key bindings'], type = 'toggle', order = 22 }
	end
	return args
end

---Font controls for one button text element.
---@param element string hotkey, count or macro
---@param name string
---@param order number
---@param path any[] Where the values are stored
---@param fallbackPath? any[] Values shown until this element is customized
---@param apply fun()
---@param disabled? fun(): boolean
---@return table
local function BuildTextOptions(element, name, order, path, fallbackPath, apply, disabled)
	local function read(key)
		local value = module:GetSetting(path, key)
		if value == nil and fallbackPath then
			value = module:GetSetting(fallbackPath, key)
		end
		return value
	end
	return {
		name = name,
		type = 'group',
		inline = true,
		order = order,
		disabled = disabled,
		get = function(info)
			return read(info[#info])
		end,
		set = function(info, value)
			module:SetSetting(path, info[#info], value)
			apply()
		end,
		args = {
			face = {
				name = L['Font'],
				type = 'select',
				order = 1,
				values = function()
					local fonts = { [''] = L['Default'] }
					for fontName in pairs(SUI.Lib.LSM:HashTable('font')) do
						fonts[fontName] = fontName
					end
					return fonts
				end,
			},
			size = { name = L['Size'], type = 'range', order = 2, min = 4, max = 40, step = 1 },
			flags = { name = L['Outline'], type = 'select', order = 3, values = FONT_FLAGS },
			anchor = { name = L['Position'], type = 'select', order = 4, values = TEXT_ANCHORS },
			x = { name = L['X offset'], type = 'range', order = 5, min = -30, max = 30, step = 1 },
			y = { name = L['Y offset'], type = 'range', order = 6, min = -30, max = 30, step = 1 },
			color = {
				name = L['Color'],
				type = 'color',
				order = 7,
				get = function()
					local c = read('color') or { 1, 1, 1 }
					return c[1], c[2], c[3]
				end,
				set = function(_, r, g, b)
					module:SetSetting(path, 'color', { r, g, b })
					apply()
				end,
			},
		},
	}
end

---@param id number
---@param bar SUI.ActionBars.ActionBar
---@return table
local function BuildActionBarOptions(id, bar)
	local path = { 'bars', id }
	local getset = BarGetSet(bar, path)
	local args = BuildCommonBarArgs(bar, path, { hotkeyText = true, maxButtons = 12 })

	args.buttons = {
		name = L['Number of buttons'],
		type = 'range',
		order = 11,
		min = 1,
		max = 12,
		step = 1,
	}
	args.showGrid = {
		name = L['Show empty buttons'],
		type = 'toggle',
		order = 23,
	}
	args.macroText = { name = L['Show macro names'], type = 'toggle', order = 24 }
	args.countText = { name = L['Show item counts'], type = 'toggle', order = 25 }
	args.showEquipped = { name = L['Highlight equipped items'], type = 'toggle', order = 26 }
	args.flyoutDirection = {
		name = L['Fly-out direction'],
		desc = L['Which way spell fly-outs such as portals and pets open.'],
		type = 'select',
		order = 27,
		values = FLYOUT_DIRECTIONS,
	}

	args.textHeader = { name = L['Button text'], type = 'header', order = 60 }
	args.customText = {
		name = L['Style text for this bar'],
		desc = L['Use different fonts on this bar than the ones set in the General tab.'],
		type = 'toggle',
		order = 61,
	}
	local function applyBar()
		module:UpdateActionBarConfig(bar)
	end
	local function notCustom()
		return not module:GetSetting(path, 'customText')
	end
	args.hotkeyTextStyle = BuildTextOptions('hotkey', L['Key binding'], 62, { 'bars', id, 'text', 'hotkey' }, { 'text', 'hotkey' }, applyBar, notCustom)
	args.countTextStyle = BuildTextOptions('count', L['Item count'], 63, { 'bars', id, 'text', 'count' }, { 'text', 'count' }, applyBar, notCustom)
	args.macroTextStyle = BuildTextOptions('macro', L['Macro name'], 64, { 'bars', id, 'text', 'macro' }, { 'text', 'macro' }, applyBar, notCustom)

	args.pagingHeader = { name = L['Page swapping'], type = 'header', order = 50 }
	args.pagingEnabled = {
		name = id == 1 and L['Swap pages for stances and forms'] or L['Use custom page swapping'],
		desc = L['Change which actions this bar shows when you change stance, form or press a modifier.'],
		type = 'toggle',
		order = 51,
	}
	args.paging = {
		name = (L['Page rules for %s']):format(playerClassName),
		desc = L['Macro conditions picking the page to show, for example: [mod:shift] 2; [bonusbar:1] 7;  Leave empty to use the default for your class.'],
		type = 'input',
		multiline = 3,
		width = 'full',
		order = 52,
		validate = ValidateConditions,
		disabled = function()
			return not module:GetSetting(path, 'pagingEnabled')
		end,
		get = function()
			local paging = module:GetSetting(path, 'paging')
			return paging and paging[playerClass] or ''
		end,
		set = function(_, value)
			local paging = Walk(module.DB, { 'bars', id, 'paging' }, true)
			paging[playerClass] = (value and value:gsub('%s', '') ~= '') and value or nil
			SUI.DBM:RefreshSettings(module)
			bar:Apply()
		end,
	}
	args.pagingDefault = {
		name = function()
			local default = id == 1 and module.DefaultClassPaging[playerClass]
			if default then
				return (L['Default for your class: %s']):format(default)
			end
			return L['Your class has no default page swaps for this bar.']
		end,
		type = 'description',
		order = 53,
	}

	return {
		name = bar.displayName,
		type = 'group',
		order = 10 + id,
		get = getset.get,
		set = getset.set,
		args = args,
	}
end

---@param key string
---@param settingsKey string
---@param order number
---@param extra? table
---@return table|nil
local function BuildSpecialBarOptions(key, settingsKey, order, extra)
	local bar = module.bars[key]
	if not bar then
		return nil
	end
	local path = { settingsKey }
	local getset = BarGetSet(bar, path)
	local args = BuildCommonBarArgs(bar, path, { hotkeyText = settingsKey == 'pet' or settingsKey == 'stance', maxButtons = 13 })
	for k, v in pairs(extra or {}) do
		args[k] = v
	end
	-- These bars take Blizzard's own buttons; handing them back needs a reload
	if settingsKey == 'micro' or settingsKey == 'bags' then
		args.enabled.desc = L['Turning this off gives the buttons back to the standard game layout. Needs a reload.']
		args.enabled.set = function(_, value)
			module:SetSetting(path, 'enabled', value)
			SUI:reloadui()
		end
	end
	return {
		name = bar.displayName,
		type = 'group',
		order = order,
		get = getset.get,
		set = getset.set,
		args = args,
	}
end

----------------------------------------------------------------------------------------------------
-- General tab
----------------------------------------------------------------------------------------------------

---@return table
local function BuildGeneralOptions()
	local function applyAll()
		module:ApplyAll()
	end
	local function updateButtons()
		module:UpdateButtonConfig()
	end
	local function colorOption(key, name, order)
		return {
			name = name,
			type = 'color',
			order = order,
			get = function()
				local c = module.CurrentSettings.colors[key]
				return c[1], c[2], c[3]
			end,
			set = function(_, r, g, b)
				module:SetSetting({ 'colors' }, key, { r, g, b })
				module:UpdateButtonConfig()
			end,
		}
	end

	return {
		name = L['General'],
		type = 'group',
		order = 1,
		get = function(info)
			return module.CurrentSettings[info[#info]]
		end,
		set = function(info, value)
			module:SetSetting({}, info[#info], value)
			applyAll()
		end,
		args = {
			moveBars = {
				name = L['Move bars'],
				type = 'execute',
				order = 1,
				func = function()
					SUI.Handlers.BarSystem:MoveIt()
				end,
			},
			keybindMode = {
				name = L['Key bindings'],
				desc = L['Hover a button and press a key to bind it. Press Escape to clear.'],
				type = 'execute',
				order = 2,
				func = function()
					module:ToggleKeybindMode()
				end,
			},
			resetAll = {
				name = L['Reset action bars'],
				desc = L['Put every bar back to SpartanUI defaults, including positions.'],
				type = 'execute',
				order = 3,
				confirm = true,
				func = function()
					module:ResetAll()
				end,
			},
			behaviorHeader = { name = L['Behavior'], type = 'header', order = 10 },
			lockButtons = {
				name = L['Lock buttons'],
				desc = L['Stop spells being dragged off the bars by accident. Hold Shift to drag them anyway.'],
				type = 'toggle',
				order = 11,
			},
			keyDown = {
				name = L['Cast on key press'],
				desc = L['Cast when a key is pressed instead of when it is released.'],
				type = 'toggle',
				order = 12,
				get = function()
					return GetCVarBool('ActionButtonUseKeyDown')
				end,
				set = function(_, value)
					SetCVar('ActionButtonUseKeyDown', value and '1' or '0')
				end,
			},
			rightClickSelfCast = {
				name = L['Right-click self cast'],
				desc = L['Right-clicking a button casts the spell on yourself.'],
				type = 'toggle',
				order = 13,
			},
			tooltip = {
				name = L['Button tooltips'],
				type = 'select',
				order = 14,
				values = {
					enabled = L['Always'],
					nocombat = L['Out of combat only'],
					disabled = L['Never'],
				},
			},
			showCooldownText = {
				name = L['Show cooldown numbers'],
				type = 'toggle',
				order = 15,
			},
			masque = {
				name = L['Use Masque skins'],
				desc = L['Let the Masque addon skin SpartanUI buttons. Needs a reload.'],
				type = 'toggle',
				order = 16,
				hidden = function()
					return LibStub('Masque', true) == nil
				end,
				set = function(_, value)
					module:SetSetting({}, 'masque', value)
					SUI:reloadui()
				end,
			},
			colorHeader = { name = L['Colors'], type = 'header', order = 20 },
			outOfRangeColoring = {
				name = L['Out of range warning'],
				type = 'select',
				order = 21,
				values = {
					button = L['Tint the button'],
					hotkey = L['Tint the key binding'],
					none = L['Off'],
				},
			},
			rangeColor = colorOption('range', L['Out of range'], 22),
			manaColor = colorOption('mana', L['Not enough power'], 23),
			backdropBackground = {
				name = L['Backdrop'],
				type = 'color',
				hasAlpha = true,
				order = 24,
				get = function()
					local c = module.CurrentSettings.backdropColors.background
					return c[1], c[2], c[3], c[4]
				end,
				set = function(_, r, g, b, a)
					module:SetSetting({ 'backdropColors' }, 'background', { r, g, b, a })
					applyAll()
				end,
			},
			backdropBorder = {
				name = L['Backdrop border'],
				type = 'color',
				hasAlpha = true,
				order = 25,
				get = function()
					local c = module.CurrentSettings.backdropColors.border
					return c[1], c[2], c[3], c[4]
				end,
				set = function(_, r, g, b, a)
					module:SetSetting({ 'backdropColors' }, 'border', { r, g, b, a })
					applyAll()
				end,
			},
			fadeHeader = { name = L['Global fade'], type = 'header', order = 30 },
			globalFade = {
				name = '',
				type = 'group',
				inline = true,
				order = 31,
				get = function(info)
					return module.CurrentSettings.globalFade[info[#info]]
				end,
				set = function(info, value)
					module:SetSetting({ 'globalFade' }, info[#info], value)
					module:UpdateGlobalFade()
				end,
				args = {
					description = {
						name = L['Bars with "Use global fade" turned on fade out together while you are idle, and come back when any of the checked things happen.'],
						type = 'description',
						order = 0,
					},
					enabled = { name = L['Enable global fade'], type = 'toggle', order = 1 },
					alpha = { name = L['Faded opacity'], type = 'range', order = 2, min = 0, max = 1, step = 0.05, isPercent = true },
					showInCombat = { name = L['In combat'], type = 'toggle', order = 3 },
					showWithTarget = { name = L['With a target or focus'], type = 'toggle', order = 4 },
					showWhileCasting = { name = L['While casting'], type = 'toggle', order = 5 },
					showInVehicle = { name = L['In a vehicle'], type = 'toggle', order = 6 },
					showWhenHurt = {
						name = L['When hurt'],
						type = 'toggle',
						order = 7,
						hidden = function()
							return SUI.IsRetail
						end,
					},
				},
			},
			textHeader = { name = L['Button text'], type = 'header', order = 40 },
			hotkeyText = BuildTextOptions('hotkey', L['Key binding'], 41, { 'text', 'hotkey' }, nil, updateButtons),
			countText = BuildTextOptions('count', L['Item count'], 42, { 'text', 'count' }, nil, updateButtons),
			macroText = BuildTextOptions('macro', L['Macro name'], 43, { 'text', 'macro' }, nil, updateButtons),
		},
	}
end

----------------------------------------------------------------------------------------------------
-- Registration
----------------------------------------------------------------------------------------------------

function module:BuildOptions()
	if self.optionsBuilt then
		return
	end
	self.optionsBuilt = true

	local options = {
		name = L['Action Bars'],
		type = 'group',
		order = 3,
		childGroups = 'tree',
		args = {
			General = BuildGeneralOptions(),
		},
	}

	for id, bar in self:IterateActionBars() do
		if bar then
			options.args['bar' .. id] = BuildActionBarOptions(id, bar)
		end
	end

	options.args.pet = BuildSpecialBarOptions('BT4BarPetBar', 'pet', 30)
	options.args.stance = BuildSpecialBarOptions('BT4BarStanceBar', 'stance', 31)
	options.args.micro = BuildSpecialBarOptions('BT4BarMicroMenu', 'micro', 32)
	options.args.bags = BuildSpecialBarOptions('BT4BarBagBar', 'bags', 33, {
		bagsHeader = { name = L['Bags'], type = 'header', order = 60 },
		onlyBackpack = { name = L['Only show the backpack'], type = 'toggle', order = 61 },
		showReagentBag = {
			name = L['Show reagent bag'],
			type = 'toggle',
			order = 62,
			hidden = function()
				return _G.CharacterReagentBag0Slot == nil
			end,
		},
		showKeyring = {
			name = L['Show keyring'],
			type = 'toggle',
			order = 63,
			hidden = function()
				return _G.KeyRingButton == nil
			end,
		},
		reverse = { name = L['Reverse order'], type = 'toggle', order = 64 },
	})
	options.args.queue = BuildSpecialBarOptions('BT4BarQueueStatus', 'queue', 34)
	options.args.totem = BuildSpecialBarOptions('MultiCastActionBarFrame', 'totem', 35)
	-- These hold a single Blizzard frame with a fixed shape; only placement options apply
	for _, groupKey in ipairs({ 'queue', 'totem' }) do
		local group = options.args[groupKey]
		for _, key in ipairs({ 'buttonsPerRow', 'point', 'buttonSize', 'keepSizeRatio', 'buttonHeight', 'buttonSpacing', 'backdrop', 'backdropSpacing', 'zoom', 'clickThrough' }) do
			if group then
				group.args[key] = nil
			end
		end
	end

	SUI.opt.args.ActionBars = options

	if SUI.opt.args.Help and SUI.opt.args.Help.args.SUIModuleHelp then
		SUI.opt.args.Help.args.SUIModuleHelp.args.ResetActionBars = options.args.General.args.resetAll
	end
end

---Wipe every action bar setting and position back to defaults.
function module:ResetAll()
	if InCombatLockdown() then
		SUI:Print(ERR_NOT_IN_COMBAT)
		return
	end
	wipe(self.DB)
	SUI.DBM:RefreshSettings(self)
	local MoveIt = SUI:GetModule('MoveIt', true) ---@type MoveIt
	if MoveIt then
		for key in pairs(self.bars) do
			if MoveIt.MoverList[key] then
				MoveIt:Reset(key)
			end
		end
	end
	SUI.Handlers.BarSystem.DB.custom.scale.BT4 = {}
	self:ApplyAll()
end
