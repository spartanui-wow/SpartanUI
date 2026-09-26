---@type SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.ActionBars
local module = SUI:GetModule('ActionBars')

local SYSTEM_LABELS = {
	SpartanUI = 'SpartanUI',
	Bartender4 = 'Bartender4',
	WoW = 'Blizzard',
}

---Importers that can run right now.
---@return SUI.ActionBars.Importer[]
function module:GetAvailableImporters()
	local list = {}
	for _, id in ipairs(self.ImporterOrder) do
		local importer = self.Importers[id]
		if importer:IsAvailable() then
			list[#list + 1] = importer
		end
	end
	return list
end

----------------------------------------------------------------------------------------------------
-- Import options (always available, whichever bar system is running)
----------------------------------------------------------------------------------------------------

local importState = {
	source = nil,
	profile = nil,
	positions = false,
	keybinds = true,
	-- The other addon is always turned off: two bar addons cannot draw bars at once
	disableSource = true,
}

local function SelectedImporter()
	local id = importState.source
	if not id or not module.Importers[id] then
		local available = module:GetAvailableImporters()
		id = available[1] and available[1].id or module.ImporterOrder[1]
		importState.source = id
	end
	return module.Importers[id]
end

local function SelectedProfile(importer)
	if not importState.profile or importState.profileSource ~= importer.id then
		importState.profile = importer:IsAvailable() and importer:GetCurrentProfile() or nil
		importState.profileSource = importer.id
	end
	return importState.profile
end

function module:BuildImportOptions()
	local barSystem = SUI.opt and SUI.opt.args.General and SUI.opt.args.General.args['Bar System']
	if not barSystem then
		return
	end

	barSystem.args.import = {
		name = L['Import bar settings'],
		type = 'group',
		inline = true,
		order = 10,
		args = {
			description = {
				name = L['Copy your action bar setup from another bar addon into SpartanUI, then switch to SpartanUI bars. The other addon must be turned on while you import.'],
				type = 'description',
				order = 1,
				fontSize = 'medium',
			},
			source = {
				name = L['Import from'],
				type = 'select',
				order = 2,
				values = function()
					local values = {}
					for _, id in ipairs(module.ImporterOrder) do
						local importer = module.Importers[id]
						values[id] = importer:IsAvailable() and importer.name or (importer.name .. ' (' .. L['not loaded'] .. ')')
					end
					return values
				end,
				get = function()
					return SelectedImporter().id
				end,
				set = function(_, value)
					importState.source = value
					importState.profile = nil
				end,
			},
			profile = {
				name = L['Profile'],
				type = 'select',
				order = 3,
				disabled = function()
					return not SelectedImporter():IsAvailable()
				end,
				values = function()
					local importer = SelectedImporter()
					local values = {}
					if importer:IsAvailable() then
						for _, name in ipairs(importer:GetProfiles()) do
							values[name] = name
						end
					end
					return values
				end,
				get = function()
					return SelectedProfile(SelectedImporter())
				end,
				set = function(_, value)
					importState.profile = value
				end,
			},
			unavailable = {
				name = function()
					local _, reason = SelectedImporter():IsAvailable()
					return '|cffff8080' .. (reason or '') .. '|r'
				end,
				type = 'description',
				order = 4,
				hidden = function()
					return SelectedImporter():IsAvailable()
				end,
			},
			positions = {
				name = L['Also copy bar positions'],
				desc = L['Move bars to where the other addon had them. Leave this off to keep bars in your SpartanUI theme.'],
				type = 'toggle',
				order = 5,
				get = function()
					return importState.positions
				end,
				set = function(_, value)
					importState.positions = value
				end,
			},
			keybinds = {
				name = L['Move key bindings'],
				desc = L["Keep the keys you bound to bars that don't exist in the default UI."],
				type = 'toggle',
				order = 6,
				get = function()
					return importState.keybinds
				end,
				set = function(_, value)
					importState.keybinds = value
				end,
			},
			run = {
				name = L['Import and use SpartanUI bars'],
				desc = L['Replaces your SpartanUI action bar settings and reloads your UI.'],
				type = 'execute',
				order = 8,
				width = 'double',
				confirm = true,
				disabled = function()
					local importer = SelectedImporter()
					return not importer:IsAvailable() or not SelectedProfile(importer)
				end,
				func = function()
					local importer = SelectedImporter()
					local ok, message = module:RunImport(importer.id, SelectedProfile(importer), importState)
					if not ok and message then
						SUI:Print(message)
					end
				end,
			},
		},
	}
end

----------------------------------------------------------------------------------------------------
-- Setup wizard
----------------------------------------------------------------------------------------------------

function module:RegisterSetupWizardPage()
	if not LibAT or not LibAT.SetupWizard or LibAT.SetupWizard:GetPage('spartanui', 'actionbars') then
		return
	end
	local BarSystem = SUI.Handlers.BarSystem
	local bt4Installed = _G.Bartender4 ~= nil or (C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist('Bartender4')) or false
	-- Nothing to choose for players with no other bar addon: SpartanUI bars just run
	if not bt4Installed and #self:GetAvailableImporters() == 0 then
		return
	end

	LibAT.SetupWizard:AddPage('spartanui', {
		id = 'actionbars',
		name = L['Action Bars'],
		order = 25,
		isComplete = function()
			return true
		end,
		builder = function(contentFrame)
			local width = contentFrame:GetWidth()
			local defs = {
				header = { type = 'header', name = L['Action Bars'], order = 1 },
				intro = {
					type = 'description',
					order = 2,
					name = L['SpartanUI has its own action bars. They work on every game version and can copy your setup from Bartender4, ElvUI or Dominos.'],
				},
				current = {
					type = 'description',
					order = 3,
					name = (L['Currently using: %s']):format(SYSTEM_LABELS[BarSystem:GetActiveSystem()] or BarSystem:GetActiveSystem()),
				},
				useSUI = {
					type = 'button',
					order = 10,
					name = L['Use SpartanUI bars'],
					desc = L['Switch to SpartanUI bars and reload. Bartender4 is turned off.'],
					hidden = function()
						return BarSystem:GetActiveSystem() == 'SpartanUI'
					end,
					func = function()
						BarSystem:SetChosenSystem('SpartanUI')
					end,
				},
				useBT4 = {
					type = 'button',
					order = 11,
					name = L['Keep using Bartender4'],
					hidden = function()
						return not bt4Installed or BarSystem:GetActiveSystem() == 'Bartender4'
					end,
					func = function()
						BarSystem:SetChosenSystem('Bartender4')
					end,
				},
			}
			local order = 20
			for _, importer in ipairs(module:GetAvailableImporters()) do
				order = order + 1
				defs['import' .. importer.id] = {
					type = 'button',
					order = order,
					name = (L['Import from %s']):format(importer.name),
					desc = L['Copy that setup into SpartanUI bars and reload. Bar positions stay with your theme.'],
					func = function()
						local ok, message = module:RunImport(importer.id, importer:GetCurrentProfile(), {
							positions = false,
							keybinds = true,
							disableSource = true,
						})
						if not ok and message then
							SUI:Print(message)
						end
					end,
				}
			end
			LibAT.UI.BuildWidgets(contentFrame, defs, width)
		end,
	})
end

function module:OnEnable()
	self:BuildImportOptions()
	self:RegisterSetupWizardPage()
end
