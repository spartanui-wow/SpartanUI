---@class SUI
local SUI = SUI
local L, Lib = SUI.L, SUI.Lib
---@class SUI.Handler.Options : SUI.Module
local module = SUI:NewModule('Handler.Options')
module.ShowOptionsUI = false
local unpack = unpack
local Options = {}
---------------------------------------------------------------------------
function module:GetConfigWindow()
	local ConfigOpen = Lib.AceCD and Lib.AceCD.OpenFrames and Lib.AceCD.OpenFrames['SpartanUI']
	return ConfigOpen and ConfigOpen.frame
end

function module:OnInitialize()
	SUI.opt.args.General.args = {
		ver1 = {
			name = 'SUI Version: ' .. SUI.Version,
			type = 'description',
			order = 50,
			fontSize = 'large',
		},
		ver2 = {
			name = 'SUI Build: ' .. SUI.BuildNum,
			type = 'description',
			order = 51,
			fontSize = 'large',
		},
		ver3 = {
			name = 'Bartender4 Version: ' .. SUI.Bartender4Version,
			type = 'description',
			order = 53,
			fontSize = 'large',
		},
		line2 = { name = '', type = 'header', order = 99 },
		navigationissues = {
			name = L['Have a Question?'],
			type = 'description',
			order = 100,
			fontSize = 'medium',
		},
		navigationissues2 = {
			name = '',
			type = 'input',
			order = 101,
			width = 'full',
			get = function(info)
				return 'https://discord.gg/Qc9TRBv'
			end,
			set = function(info, value) end,
		},
		bugsandfeatures = {
			name = L['Bugs & Feature Requests'] .. ':',
			type = 'description',
			order = 200,
			fontSize = 'medium',
		},
		bugsandfeatures2 = {
			name = '',
			type = 'input',
			order = 201,
			width = 'full',
			get = function(info)
				return 'http://bugs.spartanui.net/'
			end,
			set = function(info, value) end,
		},
		style = {
			name = L['Art Style'],
			type = 'group',
			order = 100,
			args = {
				description = { type = 'header', name = L['Overall Style'], order = 1 },
				OverallStyle = {
					name = '',
					type = 'group',
					inline = true,
					order = 10,
					args = {},
				},
				description2 = { type = 'header', name = L['Artwork Style'], order = 19 },
				Artwork = {
					type = 'group',
					name = L['Artwork'],
					inline = true,
					order = 20,
					args = {},
				},
				description3 = { type = 'header', name = L['Unitframe Presets'], order = 29 },
			},
		},
	}

	local Skins = {
		'Classic',
		'War',
		'Midnight',
		'Tribal',
		'Fel',
		'Digital',
		'Arcane',
		'Transparent',
		'Minimal',
	}

	-- Setup Buttons
	for _, skin in pairs(Skins) do
		-- Create overall skin button
		SUI.opt.args.General.args.style.args.OverallStyle.args[skin] = {
			name = skin,
			type = 'execute',
			image = function()
				return 'interface\\addons\\SpartanUI\\images\\setup\\Style_' .. skin, 120, 60
			end,
			func = function()
				SUI:SetActiveStyle(skin)
				if SUI.UF then
					SUI.UF:SetActiveStyle(skin)
				end
			end,
		}
		-- Setup artwork card
		SUI.opt.args.General.args.style.args.Artwork.args[skin] = {
			name = skin,
			type = 'select',
			dialogControl = 'ThemeVariantCard',
			values = { [skin] = skin },
			sorting = { skin },
			get = function()
				return skin
			end,
			set = function()
				---@type SUI.Module.Artwork
				local artworkModule = SUI:GetModule('Artwork')
				artworkModule:SetActiveStyle(skin)
			end,
		}
	end

	SUI.opt.args.Help = {
		name = L['Help'],
		type = 'group',
		order = 900,
		args = {
			SUIActions = {
				name = L['SUI Core Reset'],
				type = 'group',
				inline = true,
				order = 40,
				args = {
					ReRunSetupWizard = {
						name = L['Rerun setup wizard'],
						type = 'execute',
						order = 0.1,
						func = function()
							if LibAT and LibAT.SetupWizard then
								LibAT.SetupWizard:OpenWindow()
							end
						end,
					},
					ResetProfileDB = {
						name = L['Reset profile'],
						type = 'execute',
						width = 'double',
						desc = L['Start fresh with a new SUI profile'],
						order = 0.5,
						func = function()
							SUI.SpartanUIDB:ResetProfile()
							SUI:SafeReloadUI()
						end,
					},
					ResetDB = {
						name = L['Reset Database'],
						type = 'execute',
						desc = L['New SUI profile did not work? This is your nucular option. Reset everything SpartanUI related.'],
						order = 1,
						func = function()
							SUI.SpartanUIDB:ResetDB()
							SUI:SafeReloadUI()
						end,
					},
				},
			},
			line1 = { name = '', type = 'header', order = 40 },
			SUIModuleHelp = {
				name = L['SUI module resets'],
				type = 'group',
				order = 45,
				inline = true,
				args = {
					ResetMovedFrames = {
						name = L['Reset movable frames'],
						type = 'execute',
						order = 3,
						func = function()
							SUI.MoveIt:Reset()
						end,
					},
				},
			},
			line2 = { name = '', type = 'header', order = 49 },
			ver1 = {
				name = 'SUI ' .. L['Version'] .. ': ' .. SUI.Version,
				type = 'description',
				order = 50,
				fontSize = 'large',
			},
			ver2 = {
				name = 'SUI ' .. L['Build'] .. ': ' .. SUI.BuildNum,
				type = 'description',
				order = 51,
				fontSize = 'large',
			},
			ver3 = {
				name = L['Bartender4 version'] .. ': ' .. SUI.Bartender4Version,
				type = 'description',
				order = 53,
				fontSize = 'large',
			},
			line3 = { name = '', type = 'header', order = 99 },
			navigationissues = { name = L['Have a Question?'], type = 'description', order = 100, fontSize = 'large' },
			navigationissues2 = {
				name = '',
				type = 'input',
				order = 101,
				width = 'full',
				get = function(info)
					return 'https://discord.gg/Qc9TRBv'
				end,
				set = function(info, value) end,
			},
			bugsandfeatures = {
				name = L['Bugs & Feature Requests'] .. ':',
				type = 'description',
				order = 200,
				fontSize = 'large',
			},
			bugsandfeatures2 = {
				name = '',
				type = 'input',
				order = 201,
				width = 'full',
				get = function(info)
					return 'http://bugs.spartanui.net/'
				end,
				set = function(info, value) end,
			},
			line4 = { name = '', type = 'header', order = 500 },
		},
	}

	SUI.opt.args.Modules = {
		name = L['Modules'],
		type = 'group',
		order = 4,
		args = {
			ModuleListing = {
				name = L['Enabled modules'],
				type = 'group',
				inline = true,
				args = {},
			},
		},
	}

	-- List Modules
	for name, submodule in SUI:IterateModules() do
		if not string.match(name, 'Handler.') and not string.match(name, 'Style.') and not submodule.HideModule then
			local Displayname = name
			if submodule.DisplayName then
				Displayname = submodule.DisplayName
			end

			SUI.opt.args.Modules.args.ModuleListing.args[name] = {
				name = Displayname,
				type = 'toggle',
				disabled = submodule.Override or false,
				get = function(info)
					if submodule.Override then
						return false
					end
					return SUI:IsModuleEnabled(name)
				end,
				set = function(info, val)
					if val then
						SUI:EnableModule(submodule)
					else
						SUI:DisableModule(submodule)
					end
				end,
			}
		end
	end

	SUI.opt.args.Modules.args.enabledModules = {
		name = L['Enabled modules'],
		type = 'group',
		order = 0.1,
		args = {
			Modules = SUI.opt.args.Modules.args.ModuleListing,
		},
	}
end

function module:OnEnable()
	if not SUI:GetModule('Artwork', true) then
		SUI.opt.args.General.args['style'].args['OverallStyle'].disabled = true
	end

	SUI:AddChatCommand('help', function()
		module:ToggleOptions({ 'Help' })
	end, 'Displays SUI Help screen')
end

function module:ConfigOpened(name)
	if name ~= 'SpartanUI' then
		return
	end
	module:BuildFooter()
end

---Buttons along the bottom of the options window
function module:BuildFooter()
	local window = Lib.AceCD and Lib.AceCD.OpenFrames and Lib.AceCD.OpenFrames['SpartanUI']
	if not window or not window.footer or window.footerBuilt then
		return
	end
	window.footerBuilt = true
	local Style = SUI.UI.Style
	local footer = window.footer
	local previous
	local buttons = {}

	local function Add(text, onClick, primary)
		local button = Style:CreateButton(footer, text, nil, onClick, primary)
		if previous then
			button:SetPoint('LEFT', previous, 'RIGHT', 6, 0)
		else
			button:SetPoint('LEFT', footer, 'LEFT', 12, 0)
		end
		previous = button
		buttons[#buttons + 1] = button
		return button
	end

	if SUI:IsModuleEnabled('MoveIt') then
		Add(L['Move frames'], function()
			if SUI.MoveIt and SUI.MoveIt.MoverMode then
				Lib.AceCD:Close('SpartanUI')
				SUI.MoveIt.MoverMode:Toggle()
			end
		end)
	end
	if LibAT and LibAT.Logger and LibAT.Logger.ToggleWindow then
		Add(L['Logs'], function()
			LibAT.Logger.ToggleWindow()
		end)
	end
	local ProfileHandler = SUI:GetModule('Handler.Profiles', true) ---@type SUI.Handler.Profiles
	if ProfileHandler then
		Add(L['Import settings'], function()
			ProfileHandler:ImportUI()
			Lib.AceCD:Close('SpartanUI')
		end)
		Add(L['Export settings'], function()
			ProfileHandler:ExportUI()
			Lib.AceCD:Close('SpartanUI')
		end)
	end

	local close = Style:CreateButton(footer, CLOSE or L['Close'], 90, function()
		Lib.AceCD:Close('SpartanUI')
	end, true)
	close:SetPoint('RIGHT', footer, 'RIGHT', -22, 0)

	-- Text can measure 0 before the font is drawn once; size the buttons again when shown
	footer:HookScript('OnShow', function()
		for _, button in ipairs(buttons) do
			button:FitText()
		end
	end)
	C_Timer.After(0, function()
		for _, button in ipairs(buttons) do
			button:FitText()
		end
	end)
end
function module:PLAYER_REGEN_ENABLED()
	module:ToggleOptions()
end

---@param pages? table
function module:ToggleOptions(pages)
	if InCombatLockdown() then
		SUI:Print(ERR_NOT_IN_COMBAT)
		module.ShowOptionsUI = true
		module:RegisterEvent('PLAYER_REGEN_ENABLED')
		return
	end
	module:UnregisterEvent('PLAYER_REGEN_ENABLED')
	module.ShowOptionsUI = false

	local frame = module:GetConfigWindow()
	local mode = 'Open'
	if frame then
		mode = 'Close'
	end

	local ACD = Lib.AceCD
	if ACD then
		if not ACD.OpenHookedSUI then
			hooksecurefunc(Lib.AceCD, 'Open', module.ConfigOpened)
			ACD.OpenHookedSUI = true
		end

		ACD[mode](ACD, 'SpartanUI')
	end

	if not frame then
		frame = module:GetConfigWindow()
	end

	if mode == 'Open' and frame then
		module:BuildFooter()

		if ACD and pages and #pages > 0 then
			-- Check if the navigation path exists and provide feedback if it doesn't
			local pathExists = true
			local currentTable = SUI.opt.args
			local validPath = {}

			-- First validate if the navigation path exists in the options structure
			for i, step in ipairs(pages) do
				-- Direct match by key
				if currentTable[step] then
					table.insert(validPath, step)
					if currentTable[step].args then
						currentTable = currentTable[step].args
					else
						-- We've reached a leaf node that doesn't have any sub-options
						if i < #pages then
							pathExists = false
							break
						end
					end
				else
					-- Try to match by displayed name (case insensitive)
					local found = false
					local exactMatchKey = nil
					local lowercaseStep = step:lower()

					for optKey, optData in pairs(currentTable) do
						if type(optData) == 'table' and optData.name then
							local optName = tostring(optData.name)
							if optName == step then
								-- Exact match
								exactMatchKey = optKey
								found = true
								break
							elseif optName:lower() == lowercaseStep then
								-- Case insensitive match
								exactMatchKey = optKey
								found = true
								break
							end
						end
					end

					if found and exactMatchKey then
						table.insert(validPath, exactMatchKey)
						if currentTable[exactMatchKey].args then
							currentTable = currentTable[exactMatchKey].args
						else
							-- We've reached a leaf node that doesn't have any sub-options
							if i < #pages then
								pathExists = false
								break
							end
						end
					else
						pathExists = false
						break
					end
				end
			end

			if pathExists then
				-- Valid path, navigate to it
				if ACD.Navigate then
					ACD:Navigate('SpartanUI', validPath)
				else
					ACD:SelectGroup('SpartanUI', unpack(validPath))
				end
			else
				-- Path doesn't exist, provide feedback with available options
				SUI:Print('Navigation path not found: ' .. table.concat(pages, ' > '))

				-- List available options at the level where navigation failed
				if #validPath > 0 then
					-- We got partway through the path
					SUI:Print('Successfully navigated to: ' .. table.concat(validPath, ' > '))

					-- Get the table at the deepest valid level
					currentTable = SUI.opt.args
					for _, step in ipairs(validPath) do
						currentTable = currentTable[step].args or {}
					end

					-- Navigate to the valid portion of the path
					ACD:SelectGroup('SpartanUI', unpack(validPath))
				end

				-- Display available options at current level
				local availableOptions = {}
				for option, optData in pairs(currentTable) do
					if type(optData) == 'table' and optData.name and type(option) == 'string' and not string.match(option, '^line%d+$') then
						local displayName = tostring(optData.name)
						if displayName ~= option then
							table.insert(availableOptions, displayName .. ' (' .. option .. ')')
						else
							table.insert(availableOptions, displayName)
						end
					end
				end

				if #availableOptions > 0 then
					table.sort(availableOptions)
					SUI:Print('Available options at this level:')
					-- Display options in a more readable format
					for _, option in ipairs(availableOptions) do
						SUI:Print('- ' .. option)
					end
				end
			end
		end
	end
end

---@alias OptionsType
---| "Module"
---| "Help"
---| "Root"
---| "General"

---@param OptionsTable AceConfig.OptionsTable
---@param name? string
---@param OptType? OptionsType Default is "Module"
function Options:AddOptions(OptionsTable, name, OptType)
	if OptType == nil or OptType == 'Module' then
		SUI.opt.args.Modules.args[name or tostring(#SUI.opt.args.Modules.args)] = OptionsTable
	elseif OptType == 'Root' then
		SUI.opt.args[name or tostring(#SUI.opt.args)] = OptionsTable
	elseif OptType ~= nil then
		SUI.opt.args[OptType].args[name or tostring(#SUI.opt.args[OptType].args)] = OptionsTable
	end
end

function Options:DisableOptions(name)
	SUI.opt.args.Modules.args[name or tostring(#SUI.opt.args.Modules.args)].disabled = not (SUI.opt.args.Modules.args[name or tostring(#SUI.opt.args.Modules.args)].disabled or false)
end

---@param UserSetting table
---@param DefaultSetting table
---@return boolean
function Options:hasChanges(UserSetting, DefaultSetting)
	if not UserSetting or not DefaultSetting then
		return false
	end
	for k, v in pairs(UserSetting) do
		if type(v) == 'table' then
			if Options:hasChanges(v, DefaultSetting[k]) then
				return true
			end
		elseif v ~= DefaultSetting[k] then
			return true
		end
	end
	return false
end

---Open the options window (never closes it) and show a page, optionally scrolling to one setting
---@param path string[] Keys to the group, for example { 'UnitFrames', 'player' }
---@param optionKey? string Key of a setting inside that group
function Options:OpenTo(path, optionKey)
	if InCombatLockdown() then
		SUI:Print(ERR_NOT_IN_COMBAT)
		return
	end
	local ACD = Lib.AceCD
	if not ACD then
		return
	end
	if not module:GetConfigWindow() then
		ACD:Open('SpartanUI')
	end
	module:BuildFooter()
	if path and #path > 0 then
		if ACD.Navigate then
			ACD:Navigate('SpartanUI', path, optionKey)
		else
			ACD:SelectGroup('SpartanUI', unpack(path))
		end
	end
end

---@param moduleName string The name of the module to open settings for
function Options:OpenModuleSettings(moduleName)
	self:ToggleOptions({ 'Modules', moduleName })
end

Options.ToggleOptions = module.ToggleOptions

SUI.Options = Options
