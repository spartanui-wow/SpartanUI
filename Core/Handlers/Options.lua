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
		-- Three pages of picture cards: the look, the frames and the windows. The old groups stay (hidden)
		-- because looks still add their variant pickers to them.
		style = {
			name = L['Look'],
			type = 'group',
			order = 100,
			args = {
				cards = {
					name = '',
					type = 'select',
					dialogControl = 'SUICardGrid',
					order = 1,
					width = 'full',
					values = function()
						local values = {}
						local artwork = SUI:GetModule('Artwork', true)
						for _, card in ipairs(artwork and artwork.GetLookCards and artwork:GetLookCards() or {}) do
							values[card.value] = card.title
						end
						return values
					end,
					arg = {
						size = 'look',
						cards = function()
							local artwork = SUI:GetModule('Artwork', true)
							return artwork and artwork.GetLookCards and artwork:GetLookCards() or {}
						end,
						setVariant = function(value, variant)
							local artwork = SUI:GetModule('Artwork', true)
							if artwork and artwork.ApplyLook then
								artwork:ApplyLook(value, variant)
							end
						end,
					},
					get = function()
						local artwork = SUI:GetModule('Artwork', true)
						return artwork and artwork.GetActiveLook and artwork:GetActiveLook()
					end,
					set = function(_, value)
						local artwork = SUI:GetModule('Artwork', true)
						if artwork and artwork.ApplyLook then
							artwork:ApplyLook(value)
						end
					end,
				},
				OverallStyle = { name = '', type = 'group', inline = true, hidden = true, order = 10, args = {} },
				Artwork = { type = 'group', name = '', inline = true, hidden = true, order = 20, args = {} },
			},
		},
		frameStyle = {
			name = L['Frames'],
			type = 'group',
			order = 101,
			args = {
				intro = {
					name = L['Your health bars, portraits and party frames. Picking a look sets these too; pick here to mix a look with other frames.'],
					type = 'description',
					fontSize = 'medium',
					order = 0,
				},
				cards = {
					name = '',
					type = 'select',
					dialogControl = 'SUICardGrid',
					order = 1,
					width = 'full',
					values = function()
						local values = {}
						for _, card in ipairs(SUI.UF and SUI.UF.GetPresetCards and SUI.UF:GetPresetCards() or {}) do
							values[card.value] = card.title
						end
						return values
					end,
					arg = {
						size = 'compact',
						cards = function()
							return SUI.UF and SUI.UF.GetPresetCards and SUI.UF:GetPresetCards() or {}
						end,
					},
					get = function()
						return SUI.UF and SUI.UF.Preset and SUI.UF.Preset:GetActive('player')
					end,
					set = function(_, value)
						if SUI.UF and SUI.UF.Preset then
							SUI.UF.Preset:ApplyThemeDefaults(value)
							SUI.UF:Update()
						end
					end,
				},
			},
		},
		windowLook = {
			name = L['Windows'],
			type = 'group',
			order = 102,
			args = {
				intro = {
					name = L['How the settings, setup and other SpartanUI windows look. Your screen art stays the same.'],
					type = 'description',
					fontSize = 'medium',
					order = 0,
				},
				cards = {
					name = '',
					type = 'select',
					dialogControl = 'SUICardGrid',
					order = 1,
					width = 'full',
					values = function()
						local values = { auto = L['Match my look'] }
						for _, kit in ipairs(SUI.WindowKits:GetList()) do
							values[kit.id] = kit.name
						end
						return values
					end,
					arg = {
						size = 'swatch',
						cards = function()
							return SUI.WindowKits:GetCards()
						end,
					},
					get = function()
						return SUI.WindowKits:GetChoice()
					end,
					set = function(_, value)
						SUI.WindowKits:SetChoice(value)
					end,
				},
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
		'ModernFlat',
		'HealerGrid',
		'ClassicDark',
		'Atlas',
		'Boughs',
		'Meridian',
	}

	local function DisplayName(skin)
		local entry = SUI.ThemeRegistry and SUI.ThemeRegistry:Get(skin)
		return entry and entry.displayName or skin
	end

	-- Setup Buttons
	for _, skin in pairs(Skins) do
		-- Create overall skin button
		SUI.opt.args.General.args.style.args.OverallStyle.args[skin] = {
			name = function()
				return DisplayName(skin)
			end,
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
			name = function()
				return DisplayName(skin)
			end,
			type = 'select',
			dialogControl = 'ThemeVariantCard',
			values = { [skin] = DisplayName(skin) },
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
		childGroups = 'tab',
		args = {
			Overview = {
				name = L['Get help'],
				type = 'group',
				order = 1,
				args = {
					intro = {
						name = L['Stuck, or something looks wrong? Start here.'],
						type = 'description',
						order = 1,
						fontSize = 'medium',
					},
					GetHelp = {
						name = L['Ask for help'],
						type = 'group',
						inline = true,
						order = 10,
						args = {
							discordText = {
								name = L['Ask questions and chat with other players and the author on Discord. Click the link, then press Ctrl+C to copy it.'],
								type = 'description',
								order = 1,
								fontSize = 'medium',
							},
							discord = {
								name = L['Discord'],
								type = 'input',
								order = 2,
								width = 'full',
								get = function()
									return 'https://discord.gg/Qc9TRBv'
								end,
								set = function() end,
							},
							bugsText = {
								name = L['Found a bug, or have an idea? Tell us here.'],
								type = 'description',
								order = 3,
								fontSize = 'medium',
							},
							bugs = {
								name = L['Bugs and ideas'],
								type = 'input',
								order = 4,
								width = 'full',
								get = function()
									return 'http://bugs.spartanui.net/'
								end,
								set = function() end,
							},
						},
					},
					About = {
						name = L['About this version'],
						type = 'group',
						inline = true,
						order = 20,
						args = {
							info = {
								name = function()
									return module:GetVersionSummary()
								end,
								type = 'description',
								order = 1,
								fontSize = 'medium',
							},
						},
					},
					SUICoreReset = {
						name = L['Fix a problem'],
						type = 'group',
						inline = true,
						order = 30,
						args = {
							explain = {
								name = L['These put things back the way SpartanUI sets them up. The bigger ones ask first.'],
								type = 'description',
								order = 0,
							},
							ReRunSetupWizard = {
								name = L['Run setup again'],
								desc = L['Walk through the first-time setup again. Nothing changes until you pick something.'],
								type = 'execute',
								order = 1,
								func = function()
									SUI.Setup:Open()
								end,
							},
							ResetProfileDB = {
								name = L['Reset this profile'],
								desc = L['Start this profile fresh. Your other profiles are not touched. Your screen reloads.'],
								type = 'execute',
								order = 2,
								confirm = true,
								confirmText = L['Reset this profile to SpartanUI defaults? Your screen will reload.'],
								func = function()
									SUI.SpartanUIDB:ResetProfile()
									SUI:SafeReloadUI()
								end,
							},
							ResetDB = {
								name = L['Reset everything'],
								desc = L['Remove every SpartanUI setting for all characters and profiles. Only use this if nothing else works.'],
								type = 'execute',
								order = 3,
								confirm = true,
								confirmText = L['Remove ALL SpartanUI settings on every character? This cannot be undone. Your screen will reload.'],
								func = function()
									SUI.SpartanUIDB:ResetDB()
									SUI:SafeReloadUI()
								end,
							},
						},
					},
					SUIModuleHelp = {
						name = L['Reset one part'],
						type = 'group',
						inline = true,
						order = 40,
						args = {
							ResetMovedFrames = {
								name = L['Reset frame positions'],
								desc = L['Put every frame you moved back in its default place.'],
								type = 'execute',
								order = 3,
								confirm = true,
								func = function()
									SUI.MoveIt:Reset()
								end,
							},
						},
					},
				},
			},
		},
	}

	local ModuleListing = {
		name = L['Turn modules on or off'],
		type = 'group',
		inline = true,
		args = {},
	}
	SUI.opt.args.Modules = {
		name = L['Modules'],
		type = 'group',
		order = 4,
		args = {},
	}

	-- List Modules
	for name, submodule in SUI:IterateModules() do
		if not string.match(name, 'Handler.') and not string.match(name, 'Style.') and not submodule.HideModule then
			local Displayname = name
			if submodule.DisplayName then
				Displayname = submodule.DisplayName
			end

			ModuleListing.args[name] = {
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
			Modules = ModuleListing,
		},
	}
end

---Plain text describing this copy of SpartanUI and the game client
---@return string
function module:GetVersionSummary()
	local function Known(value)
		return value and value ~= '' and value ~= 0 and not tostring(value):find('^@')
	end
	local lines = {}
	local version = Known(SUI.Version) and tostring(SUI.Version) or L['Development build']
	if SUI.releaseType and SUI.releaseType ~= '' then
		version = version .. ' (' .. SUI.releaseType .. ')'
	end
	lines[#lines + 1] = 'SpartanUI: ' .. version
	if Known(SUI.BuildNum) then
		lines[#lines + 1] = L['Build'] .. ': ' .. tostring(SUI.BuildNum)
	end
	local _, build, _, interface = GetBuildInfo()
	lines[#lines + 1] = L['Game'] .. ': ' .. tostring(SUI.wowVersion or '') .. ' ' .. tostring(build or '') .. ' (' .. tostring(interface or '') .. ')'
	local libVersion = C_AddOns.GetAddOnMetadata('LibsAddonTools', 'Version')
	if Known(libVersion) then
		lines[#lines + 1] = "Lib's AddonTools: " .. libVersion
	end
	if C_AddOns.IsAddOnLoaded('Bartender4') and Known(SUI.Bartender4Version) then
		lines[#lines + 1] = 'Bartender4: ' .. tostring(SUI.Bartender4Version)
	end
	return table.concat(lines, '\n')
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
	local padding = LibAT.UI.Kit:GetActive().layout.barPadding
	local previous
	local buttons = {}

	local function Add(text, onClick, primary)
		local button = Style:CreateButton(footer, text, nil, onClick, primary)
		if previous then
			button:SetPoint('LEFT', previous, 'RIGHT', 6, 0)
		else
			button:SetPoint('LEFT', footer, 'LEFT', padding, 0)
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
	close:SetPoint('RIGHT', footer, 'RIGHT', -padding, 0)

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
