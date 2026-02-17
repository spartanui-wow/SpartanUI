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
		-- Setup artwork button
		SUI.opt.args.General.args.style.args.Artwork.args[skin] = {
			name = skin,
			type = 'execute',
			image = function()
				return 'interface\\addons\\SpartanUI\\images\\setup\\Style_' .. skin, 120, 60
			end,
			func = function()
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
							SUI:GetModule('Handler.SetupWizard'):SetupWizard()
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

	local frame = module:GetConfigWindow()
	if frame and frame.bottomHolder then
		frame.bottomHolder:Show()
	end
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
		if not frame.bottomHolder then -- window was released or never opened
			local bottom = CreateFrame('Frame', nil, frame, BackdropTemplateMixin and 'BackdropTemplate')
			bottom:SetPoint('BOTTOMLEFT', 2, 2)
			bottom:SetPoint('BOTTOMRIGHT', -2, 2)
			bottom:SetHeight(35)
			bottom:SetBackdropBorderColor(0, 0, 0, 0)
			frame.bottomHolder = bottom

			-- Button layout: Toggle Movers | Logging | Import Settings | Export Settings | Close
			-- Button widths: 120px for most, 80px for Close (smaller)
			-- Spacing between buttons: 10px
			-- Total width calculation: 4*120 + 80 + 4*10 = 600px (centered in window)

			-- Toggle Movers button (leftmost, most prominent)
			if SUI:IsModuleEnabled('MoveIt') then
				local MoveIt = CreateFrame('Button', nil, bottom, 'UIPanelButtonTemplate')
				MoveIt:SetSize(150, 20)
				MoveIt:SetText(L['Toggle movers'])
				MoveIt:SetPoint('BOTTOM', -190, 10) -- Start at -190 to center the 5 buttons
				MoveIt:HookScript('OnClick', function()
					-- Toggle custom MoveIt frame mover system
					if SUI.MoveIt and SUI.MoveIt.MoverMode then
						SUI.MoveIt.MoverMode:Toggle()
					end
				end)
				SUI.Skins.SkinObj('Button', MoveIt, 'Dark', 'Ace3') -- Dark skin for prominence
				bottom.MoveIt = MoveIt
			end

			-- Logging button (second from left, darker/transparent)
			if SUI.Log then
				local Logging = CreateFrame('Button', nil, bottom, 'UIPanelButtonTemplate')
				Logging:SetSize(100, 20)
				Logging:SetText('Logging')
				if bottom.MoveIt then
					Logging:SetPoint('LEFT', bottom.MoveIt, 'RIGHT', 10, 0)
				else
					Logging:SetPoint('BOTTOM', -190, 10)
				end
				Logging:HookScript('OnClick', function()
					-- Use the LibAT.Logger API to toggle the Logger window
					if LibAT and LibAT.Logger and LibAT.Logger.ToggleWindow then
						LibAT.Logger.ToggleWindow()
					end
				end)
				SUI.Skins.SkinObj('Button', Logging, 'Light', 'Ace3')
				-- Make it more transparent/darker by adjusting the background after skinning
				Logging:HookScript('OnShow', function(self)
					if self.bg then
						self.bg:SetAlpha(0.6)
					end
					-- Also make the texture more transparent
					local normalTexture = self:GetNormalTexture()
					if normalTexture then
						normalTexture:SetAlpha(0.7)
					end
				end)
				bottom.Logging = Logging
			end

			-- Import and Export buttons (middle)
			local ProfileHandler = SUI:GetModule('Handler.Profiles', true) ---@type SUI.Handler.Profiles
			if ProfileHandler then
				-- Import Settings button
				local Import = CreateFrame('Button', nil, bottom, 'UIPanelButtonTemplate')
				Import:SetSize(120, 20)
				Import:SetText('Import Settings')
				if bottom.Logging then
					Import:SetPoint('LEFT', bottom.Logging, 'RIGHT', 10, 0)
				elseif bottom.MoveIt then
					Import:SetPoint('LEFT', bottom.MoveIt, 'RIGHT', 10, 0)
				else
					Import:SetPoint('BOTTOM', -70, 10)
				end
				Import:HookScript('OnClick', function()
					ProfileHandler:ImportUI()
					ACD:Close('SpartanUI')
				end)
				SUI.Skins.SkinObj('Button', Import, 'Light', 'Ace3')
				bottom.Import = Import

				-- Export Settings button
				local Export = CreateFrame('Button', nil, bottom, 'UIPanelButtonTemplate')
				Export:SetSize(120, 20)
				Export:SetText('Export Settings')
				Export:SetPoint('LEFT', bottom.Import, 'RIGHT', 10, 0)
				Export:HookScript('OnClick', function()
					ProfileHandler:ExportUI()
					ACD:Close('SpartanUI')
				end)
				SUI.Skins.SkinObj('Button', Export, 'Light', 'Ace3')
				bottom.Export = Export
			end

			local Logo = bottom:CreateTexture()
			Logo:SetTexture('Interface\\AddOns\\SpartanUI\\images\\setup\\SUISetup')
			Logo:SetPoint('LEFT', bottom, 'LEFT')
			Logo:SetSize(156, 45)
			Logo:SetScale(0.78)
			Logo:SetTexCoord(0, 0.611328125, 0, 0.6640625)
			bottom.Logo = Logo

			frame:HookScript('OnHide', function()
				if bottom then
					bottom:Hide()
				end
			end)
		end

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
				ACD:SelectGroup('SpartanUI', unpack(validPath))
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

---@param moduleName string The name of the module to open settings for
function Options:OpenModuleSettings(moduleName)
	self:ToggleOptions({ 'Modules', moduleName })
end

Options.ToggleOptions = module.ToggleOptions

SUI.Options = Options
