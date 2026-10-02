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
	local function Bartender4Installed()
		return _G.Bartender4 ~= nil or (C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist('Bartender4')) or false
	end
	local function Running()
		return BarSystem:GetActiveSystem() == 'Bartender4' and 'Bartender4' or 'SpartanUI'
	end
	local function Detected()
		local list = {}
		for _, id in ipairs(self.ImporterOrder) do
			local importer = self.Importers[id]
			if importer and importer:IsAvailable() then
				list[#list + 1] = { id = id, importer = importer }
			end
		end
		return list
	end

	-- One page for everything about bars, shown only when another bar addon is around.
	-- Nothing changes until the reload at the end, so the card shows the pick, not what runs now.
	local picked
	reg:AddStep({
		id = 'actionbars',
		kind = 'choice',
		name = L['Action bars'],
		title = L['Which action bars?'],
		text = L['Two bar addons cannot run together. Your choice applies when you finish setup.'],
		order = 25,
		hidden = function()
			return #Detected() == 0 and not Bartender4Installed()
		end,
		choices = function()
			local choices = {}
			for i, source in ipairs(Detected()) do
				local name = source.importer.name
				choices[#choices + 1] = {
					value = 'import:' .. source.id,
					title = (L['SpartanUI bars, with my %s layout']):format(name),
					caption = (L['Your buttons and key bindings come over. %s is turned off.']):format(name),
					recommended = i == 1,
				}
			end
			if Bartender4Installed() then
				choices[#choices + 1] =
					{ value = 'SpartanUI', title = L['SpartanUI bars, start clean'], caption = L['Bars where your look puts them. Bartender4 is turned off.'], recommended = #choices == 0 }
				choices[#choices + 1] = { value = 'Bartender4', title = L['Keep Bartender4'], caption = L['SpartanUI places and sizes the Bartender4 bars.'] }
			end
			for _, source in ipairs(Detected()) do
				if source.id ~= 'Bartender4' then
					choices[#choices + 1] = { value = 'keep:' .. source.id, title = (L['Keep %s']):format(source.importer.name), caption = L['SpartanUI leaves your bars alone.'] }
				end
			end
			return choices
		end,
		get = function()
			return picked or Running()
		end,
		set = function(value, ctx)
			picked = value
			ctx:CancelReload('bars')
			local importId = value:match('^import:(.+)$')
			if importId then
				local importer = self.Importers[importId]
				ctx:NeedsReload('bars', (L['Bring over your %s bars']):format(importer.name), function()
					local ok, message = module:RunImport(importId, importer:GetCurrentProfile(), {
						positions = false,
						keybinds = true,
						disableSource = true,
						skipReload = true,
					})
					if not ok and message then
						SUI:Print(message)
					end
				end)
			elseif (value == 'SpartanUI' or value == 'Bartender4') and value ~= Running() then
				ctx:NeedsReload('bars', (L['Action bars: %s']):format(value == 'SpartanUI' and L['SpartanUI bars'] or 'Bartender4'), function()
					BarSystem:SetChosenSystem(value, true)
				end)
			end
		end,
	})
end

function module:OnEnable()
	self:BuildImportOptions()
	self:RegisterSetupWizardPage()
end
