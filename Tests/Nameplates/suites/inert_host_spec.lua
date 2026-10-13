-- @runtime lua51
-- "Inert when off" with the SpartanUI host loaded (Decision 21, 6.11, Phase 4a). The new plates are
-- the default, so the engine must stay completely off (no game events, hooks, game setting writes
-- or named frames from the core or the host) whenever it is not chosen:
--   * the module is turned off,
--   * another nameplate addon is loaded,
--   * the profile has plates off (an existing Retail profile before the player opts in),
--   * the old plates were picked for this character.
-- One process: each case turns the module off and on again and checks that nothing was recorded
-- since the start. The last case clears every condition and the engine starts, so the checks are
-- not passing by accident. Runs in its own process so the core-only check stays independent.
local M, H = ...

local function where(rec)
	return (rec.event or rec.name or rec.label or '?') .. ' at ' .. (rec.where or '?')
end

describe('inert when off, with the SpartanUI host', function()
	if not H.ModuleExists() then
		pending('core and host', 'Modules/Nameplates/Load.xml does not exist yet')
		return
	end
	if not H.Exists(H.hostFile) then
		pending('core and host', 'Modules/Nameplates/Host/SpartanUI.lua does not exist yet')
		return
	end

	local P, SUI, module

	local function AssertInert(label)
		assert.is_false(P and P.enabled == true, label .. ': the engine stays off')
		assert.empty(M.rec.events, label .. ': registered game events', where)
		assert.empty(M.rec.hooks, label .. ': installed hooksecurefunc', where)
		assert.empty(M.rec.cvarWrites, label .. ': wrote CVars', where)
		local frames = {}
		for _, g in ipairs(M.rec.globals) do
			frames[#frames + 1] = g
		end
		assert.empty(frames, label .. ': created named (global) frames', where)
	end

	---Show and hide a plate, then wait past the What's new card.
	local function Play()
		M.Advance(1)
		local token = M.ShowPlate({ name = 'Mob' })
		M.Advance(1)
		M.HidePlate(token)
		M.Advance(10)
	end

	---Turn the module off and on again, then play a little.
	local function Cycle()
		module:Disable()
		module:Enable()
		Play()
	end

	it('stays off while the module is turned off', function()
		H.LoadLibs()
		H.InstallLibATStub()
		SUI = H.InstallSUIMock({})
		SUI.DB.DisabledModules.Nameplates = true
		M.ResetRecords()
		local ns = H.LoadCore({ libs = false, addonName = 'SpartanUI' })
		H.LoadSpartanUIHost({ ns = ns })
		P = ns.Plates
		module = SUI:GetModule('Nameplates')
		M.Login('SpartanUI')
		Play()
		AssertInert('module off')
	end)

	it('stays off while another nameplate addon is loaded', function()
		SUI.DB.DisabledModules.Nameplates = nil
		M.loadedAddons = { Plater = true }
		Cycle()
		M.loadedAddons = nil
		AssertInert('other addon')
	end)

	it('stays off while the profile has plates off', function()
		P.db.profile.enabled = false
		Cycle()
		AssertInert('profile off')
		local root
		for _, entry in ipairs(H.sui.options) do
			if entry.name == 'Nameplates' then
				root = entry.table
			end
		end
		assert.not_nil(root, 'the settings still offer to turn plates on')
		assert.is_false(root.args.turnOn.hidden())
	end)

	it('stays off while the old plates are picked', function()
		P.db.profile.enabled = true
		P.Config:SetEngineChoice('old')
		Cycle()
		AssertInert('old plates picked')
		P.Config.sessionEngine = 'old'
		Cycle()
		AssertInert('a session that started on the old plates')
	end)

	it('starts once nothing keeps it off', function()
		P.Config.sessionEngine = nil
		P.Config:SetEngineChoice(nil)
		Cycle()
		assert.is_true(P.enabled, 'the engine runs')
		assert.is_true(#M.rec.events > 0, 'and now registers its events')
		local missing = {}
		for key in pairs(H.suiMissing or {}) do
			missing[#missing + 1] = key
		end
		table.sort(missing)
		if #missing > 0 then
			io.write('@@NOTE the host read SUI fields the mock does not have: ' .. table.concat(missing, ', ') .. '\n')
		end
	end)
end)
