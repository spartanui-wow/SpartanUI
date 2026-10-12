-- @runtime lua51
-- The tester switch on while another nameplate addon is loaded: the host never starts the new
-- engine, so two plate engines never run together, and the old module behaves as it always did.
local M, H = ...

if not (H.ModuleExists() and H.Exists(H.hostFile)) then
	describe('host with a conflicting addon', function()
		pending('all', 'the nameplate module or its host does not exist yet')
	end)
	return
end

local saved = { char = { [H.CharacterKey()] = { engine = 'new' } } }
local SUI, ns = H.LoadNameplatesLikeTheGame({ saved = saved })
local P = ns.Plates

describe('host with a conflicting addon', function()
	it('leaves the engine off and says why in the log', function()
		M.loadedAddons = { Plater = true }
		M.Login('SpartanUI')
		M.Advance(1)
		M.loadedAddons = nil
		assert.equal(P.Config:GetSessionEngine(), 'new')
		assert.is_false(P.enabled)
		assert.equal(P:RegisteredEventCount(), 0)
		assert.empty(M.rec.cvarWrites, 'CVar writes')
		local said = false
		for _, line in ipairs(H.logs.Nameplates or {}) do
			if line:find('conflict:Plater', 1, true) then
				said = true
			end
		end
		assert.is_true(said, 'the log names the other addon')
		assert.empty(H.sui.options, 'no new options')
	end)

	it('lets the old module see the other addon too', function()
		local spawned = false
		for _, call in ipairs(H.oldCalls) do
			if call.path == 'SUIUF.SpawnNamePlates' then
				spawned = true
			end
		end
		assert.is_false(spawned, 'the old plates stand down for the other addon as before')
		if not SUI.IsRetail then
			assert.not_nil(SUI.opt.args.Modules.args.Nameplates, 'the old options are still built')
		end
	end)
end)
