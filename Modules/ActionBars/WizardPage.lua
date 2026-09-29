---@type SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.ActionBars
local module = SUI:GetModule('ActionBars')

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
	local reg = SUI.Setup and SUI.Setup.registration
	if not reg or reg:GetStep('actionbars') then
		return
	end
	local BarSystem = SUI.Handlers.BarSystem
	local pendingSystem
	local function Bartender4Installed()
		return _G.Bartender4 ~= nil or (C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist('Bartender4')) or false
	end

	-- Only asked when there is a real choice: Bartender4 is installed
	reg:AddStep({
		id = 'actionbars',
		kind = 'choice',
		name = L['Action Bars'],
		title = L['Which action bars?'],
		text = L['SpartanUI has its own action bars. They work on every game version.'],
		order = 25,
		hidden = function()
			return not Bartender4Installed()
		end,
		choices = {
			{ value = 'SpartanUI', title = L['SpartanUI bars'], caption = L['Bartender4 is turned off.'], recommended = true },
			{ value = 'Bartender4', title = L['Keep Bartender4'], caption = L['SpartanUI places and sizes the Bartender4 bars.'] },
		},
		-- The change waits for the reload at the end, so the card shows the pick, not what runs now
		get = function()
			return pendingSystem or (BarSystem:GetActiveSystem() == 'Bartender4' and 'Bartender4' or 'SpartanUI')
		end,
		set = function(value, ctx)
			local current = BarSystem:GetActiveSystem() == 'Bartender4' and 'Bartender4' or 'SpartanUI'
			pendingSystem = value
			if value == current then
				pendingSystem = nil
				ctx:CancelReload('bars')
				return
			end
			ctx:NeedsReload('bars', (L['Action bars: %s']):format(value == 'SpartanUI' and L['SpartanUI bars'] or 'Bartender4'), function()
				BarSystem:SetChosenSystem(value, true)
			end)
		end,
	})

	-- Copy a setup from another bar addon that is running now; hidden when there is none
	local sources = {}
	for _, id in ipairs(self.ImporterOrder) do
		local importer = self.Importers[id]
		sources[#sources + 1] = {
			id = importer.id or id,
			title = importer.name,
			caption = L['Your bars, their buttons and key bindings. Bar positions stay with your look.'],
			detect = function()
				return (importer:IsAvailable())
			end,
			apply = function()
				local ok, message = module:RunImport(id, importer:GetCurrentProfile(), {
					positions = false,
					keybinds = true,
					disableSource = true,
					skipReload = true,
				})
				if not ok and message then
					SUI:Print(message)
				end
			end,
		}
	end
	reg:AddStep({
		id = 'actionbars-import',
		kind = 'import',
		name = L['Copy your bars'],
		title = L['Copy your bars from another addon'],
		text = L['This happens when you finish setup. The other addon is turned off.'],
		order = 26,
		sources = sources,
	})
end

function module:OnEnable()
	self:BuildImportOptions()
	self:RegisterSetupWizardPage()
end
