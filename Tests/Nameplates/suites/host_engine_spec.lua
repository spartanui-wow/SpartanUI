-- @runtime lua51
-- A character that picked the new plates (Decision 21; testers saved char.engine = 'new'): the real
-- old module, the core and the host load in LoadAll.xml order. At login the host starts the new
-- engine instead of the old plates, registers its options and "Match my look". Turning the module
-- off, or picking the old plates, stops the engine and gives the game every setting back at once;
-- turning either back on in the same session starts the new plates again.
local M, H = ...

if not (H.ModuleExists() and H.Exists(H.hostFile)) then
	describe('host with the switch on', function()
		pending('all', 'the nameplate module or its host does not exist yet')
	end)
	return
end

local saved = { char = { [H.CharacterKey()] = { engine = 'new' } } }
local SUI, ns, module = H.LoadNameplatesLikeTheGame({ saved = saved })
local P = ns.Plates

local function Called(path)
	for _, call in ipairs(H.oldCalls) do
		if call.path == path then
			return true
		end
	end
	return false
end

describe('host with the switch on', function()
	it('starts the new engine at login instead of the old plates', function()
		M.Login('SpartanUI')
		M.Advance(1)
		assert.equal(P.Config:GetSessionEngine(), 'new')
		assert.is_true(P.enabled, 'the engine is on')
		assert.is_false(Called('SUIUF.SpawnNamePlates'), 'the old plates are not spawned')
		assert.is_nil(SUI.opt.args.Modules.args.Nameplates, 'the old options are not built')
	end)

	it('adds the new options as their own top-level entry', function()
		local found
		for _, entry in ipairs(H.sui.options) do
			if entry.name == 'Nameplates' then
				found = entry
			end
		end
		assert.not_nil(found)
		assert.equal(found.parent, 'Root')
		assert.equal(found.table.type, 'group')
	end)

	it('registers Match my look and pushes the theme look', function()
		assert.not_nil(P.Styles.Registry:Get('spartanui'))
		assert.equal(P.Styles.Registry:ResolveId('host'), 'spartanui')
		assert.not_nil(P.hostLook)
		assert.not_nil(P.Styles.Merge:Resolve('host', 'enemyNPC', 'medium'))
	end)

	it('pushes the look once per frame however often fonts refresh', function()
		local pushes = 0
		local owner = {}
		P:On('HOST_LOOK_CHANGED', function()
			pushes = pushes + 1
		end, owner)
		SUI.Font:Refresh()
		SUI.Font:Refresh('Nameplates')
		M.Advance(0.2)
		P:Off('HOST_LOOK_CHANGED', owner)
		assert.equal(pushes, 1)
	end)

	it('takes the new theme nameplate style when the theme changes', function()
		H.sui.themes.Fel = { nameplates = { style = 'mini' } }
		H.sui.activeStyle = 'Fel'
		H.FireSUIEvent('ARTWORK_STYLE_CHANGED')
		M.Advance(0.2)
		local mini = P.Styles.Registry:Get('mini')
		local host = P.Styles.Registry:Get('spartanui')
		assert.same(host.plate.sizes.medium, mini.plate.sizes.medium)
		H.sui.activeStyle = 'War'
		H.FireSUIEvent('ARTWORK_STYLE_CHANGED')
		M.Advance(0.2)
		assert.same(P.Styles.Registry:Get('spartanui').plate.sizes.medium, P.Styles.Registry:Get('clean').plate.sizes.medium)
	end)

	it('redraws the open options after changes made outside a control', function()
		local registry = LibStub('AceConfigRegistry-3.0')
		local original = registry.NotifyChange
		local notified = {}
		registry.NotifyChange = function(self, app, ...)
			notified[#notified + 1] = app
			return original(self, app, ...)
		end
		P.Store:Set('scheme', 'class')
		P.Store:Set('colorBlind', true)
		M.Advance(0.2)
		registry.NotifyChange = original
		P.Store:Reset('scheme')
		P.Store:Reset('colorBlind')
		M.Advance(0.2)
		assert.equal(#notified, 1, 'one redraw for several changes in one frame')
		assert.equal(notified[1], 'SpartanUI')
	end)

	it('teaches the settings search its words for SpartanUI settings only', function()
		local found
		for _, call in ipairs(H.libatCalls or {}) do
			if call.path == 'LibAT.UI.Options.Search.AddSynonyms' then
				found = call
			end
		end
		assert.not_nil(found)
		assert.equal(found[2], 'SpartanUI')
		assert.equal(found[3].aggro, 'threat')
	end)

	it('keeps running while plates come and go', function()
		local token = M.ShowPlate({ name = 'Gnoll', canAttack = true, reaction = 2 })
		M.Advance(1)
		M.EnterCombat()
		M.Advance(1)
		M.LeaveCombat()
		M.HidePlate(token)
		M.Advance(1)
		assert.is_true(P.enabled)
	end)

	it('gives the game its settings back on /sui np restore', function()
		local name = 'nameplateMinScale'
		M.SetCVarState(name, { value = '1', account = true })
		P.CVars.info[name] = nil
		P.CVars:Set(name, 0.8)
		H.sui.commands.np.fn('restore')
		assert.equal(C_CVar.GetCVar(name), '1')
		assert.is_nil(P.CVars:GetBackup(name))
	end)

	it('stops the engine and restores settings when the module is turned off', function()
		assert.is_true(P.enabled)
		local name = 'nameplateMinScale'
		M.SetCVarState(name, { value = '1', account = true })
		P.CVars.info[name] = nil
		P.CVars:Set(name, 0.6)
		module:Disable()
		assert.is_false(P.enabled)
		assert.equal(C_CVar.GetCVar(name), '1')
		assert.is_nil(P.CVars:GetBackup(name))
	end)

	it('starts again when the module is turned back on', function()
		module:Enable()
		M.Advance(1)
		assert.is_true(P.enabled)
		assert.is_false(Called('SUIUF.SpawnNamePlates'), 'the old plates still do not run')
	end)

	it('restores settings at once when the old plates are picked', function()
		local name = 'nameplateMaxScale'
		M.SetCVarState(name, { value = '1', account = true })
		P.CVars.info[name] = nil
		P.CVars:Set(name, 1.3)
		H.sui.commands.np.fn('preview')
		assert.equal(P.Config:GetEngineChoice(), 'old')
		assert.is_false(P.enabled, 'the new plates stop at once')
		assert.equal(C_CVar.GetCVar(name), '1')
		assert.is_false(Called('SUIUF.SpawnNamePlates'), 'the old plates wait for a reload')
	end)

	it('does not start while the old plates are picked, even when the module is turned back on', function()
		module:Disable()
		module:Enable()
		P.Store:Set('size', 'large')
		M.Advance(1)
		P.Store:Reset('size')
		assert.is_false(P.enabled)
	end)

	it('gives back settings left behind when the module is turned off while stopped', function()
		local name = 'nameplateMinScale'
		M.SetCVarState(name, { value = '1', account = true })
		P.CVars.info[name] = nil
		P.CVars:Set(name, 0.7)
		module:Disable()
		assert.is_false(P.enabled)
		assert.equal(C_CVar.GetCVar(name), '1')
		module:Enable()
	end)

	it('starts the new plates again in the same session when they are picked again', function()
		H.sui.commands.np.fn('preview')
		assert.equal(P.Config:GetEngineChoice(), 'new')
		M.Advance(1)
		assert.is_true(P.enabled, 'the old plates never ran this session, so no reload is needed')
	end)
end)
