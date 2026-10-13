-- @runtime lua51
-- A module turned off in SpartanUI's module list at login (SUI.DB.DisabledModules). SpartanUI does
-- not disable listed modules at load, so AceAddon still runs OnEnable; the host must mark the
-- module off so the module list's toggle (SUI:EnableModule: clear the list entry, then
-- module:Enable() with no Disable() first) starts the new plates in the same session.
local M, H = ...

describe('host: module off at login', function()
	if not (H.ModuleExists() and H.Exists(H.hostFile)) then
		pending('all', 'the nameplate module or its host does not exist yet')
		return
	end

	local P, SUI, module

	it('stays off at login and counts as off', function()
		H.LoadLibs()
		H.InstallLibATStub()
		SUI = H.InstallSUIMock({})
		SUI.DB.DisabledModules.Nameplates = true
		local ns = H.LoadCore({ libs = false, addonName = 'SpartanUI' })
		H.LoadSpartanUIHost({ ns = ns })
		P = ns.Plates
		module = SUI:GetModule('Nameplates')
		M.Login('SpartanUI')
		M.Advance(1)
		assert.is_false(P.enabled == true, 'the engine stays off')
		assert.is_false(module:IsEnabled(), 'AceAddon counts the module as off')
	end)

	it('starts the new plates when the module list turns it on, without a reload', function()
		-- What the module list's toggle does (SUI:EnableModule)
		SUI.DB.DisabledModules.Nameplates = nil
		module:Enable()
		M.Advance(1)
		assert.is_true(module:IsEnabled())
		assert.is_true(P.enabled, 'the engine runs')
	end)

	it('stops again when it is turned off', function()
		SUI.DB.DisabledModules.Nameplates = true
		module:Disable()
		assert.is_false(P.enabled == true)
	end)
end)
