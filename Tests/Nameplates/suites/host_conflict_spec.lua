-- @runtime lua51
-- Another nameplate addon is loaded (Phase 4a): the host never starts the engine, so two plate
-- engines never run together.
local M, H = ...

if not (H.ModuleExists() and H.Exists(H.hostFile)) then
	describe('host with a conflicting addon', function()
		pending('all', 'the nameplate module or its host does not exist yet')
	end)
	return
end

local SUI, ns = H.LoadNameplatesLikeTheGame()
local P = ns.Plates
-- SpartanUI's setup registration with its Done page links (Core/Handlers/SetupWizard.lua)
local finish = { links = {} }
rawset(SUI.Setup.registration, 'config', { finish = finish })

describe('host with a conflicting addon', function()
	it('leaves the engine off and says why in the log', function()
		M.loadedAddons = { Plater = true }
		M.Login('SpartanUI')
		M.Advance(1)
		M.loadedAddons = nil
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
end)

----------------------------------------------------------------------------------------------------
-- Setup and the Done page while another nameplate addon draws the plates
----------------------------------------------------------------------------------------------------

describe('host with a conflicting addon: setup', function()
	local function LookStep()
		for _, step in ipairs(H.sui.setupSteps) do
			if step.id == 'nameplates-look' then
				return step
			end
		end
	end

	local function Values(cards)
		local out = {}
		for i, card in ipairs(cards) do
			out[i] = card.value
		end
		return out
	end

	it('still offers Match my look and the War style, preselected', function()
		local step = LookStep()
		assert.not_nil(step, 'the look step is added')
		assert.is_false(step.hidden(), 'the conflicts step can turn the other addon off, so the pick still counts')
		local values = Values(step.cards())
		assert.contains(values, 'host')
		assert.equal(step.get(), 'host', 'Next accepts Match my look')
		assert.equal(P.Styles.Registry:ResolveId('host'), 'spartanui')
		assert.not_nil(P.Styles.Registry:Get('war'))
		for _, card in ipairs(step.cards()) do
			if card.value == 'host' then
				assert.is_true(card.recommended)
			end
		end
	end)

	it('does that without starting anything', function()
		assert.is_false(P.enabled)
		assert.equal(P:RegisteredEventCount(), 0)
		assert.empty(H.sui.options, 'no settings pages')
		assert.empty(M.rec.cvarWrites, 'no game settings')
	end)

	it('tells the player what the pick needs, and what ElvUI needs', function()
		local step = LookStep()
		M.enabledAddons = { Plater = true }
		local banner = step.banner()
		M.enabledAddons = nil
		assert.matches(banner.title, 'Plater draws your nameplates now')
		assert.matches(banner.text, 'Conflicts step')
		assert.matches(banner.text, 'reloads your screen')
		assert.equal(banner.step, 'conflicts')

		M.loadedAddons = { ElvUI = true }
		rawset(_G, 'ElvUI', { { private = { nameplates = { enable = true } } } })
		banner = step.banner()
		M.loadedAddons = nil
		rawset(_G, 'ElvUI', nil)
		assert.matches(banner.title, 'ElvUI draws your nameplates now')
		assert.matches(banner.text, 'own settings')
		assert.is_nil(banner.step, 'the Conflicts step cannot turn its nameplates off')
	end)

	it('gives the game back its settings from the Done page, and leaves out the link to a page that is not there', function()
		assert.equal(#finish.links, 1)
		local link = finish.links[1]
		assert.equal(link.title, 'Give the game back its settings')
		local name = 'nameplateMaxDistance'
		M.SetCVarState(name, { value = '40', account = true })
		P.CVars.info[name] = nil
		P.CVars:Set(name, 60)
		P.Store:Set({ 'behavior', 'pinScale' }, true)
		link.onClick()
		assert.equal(C_CVar.GetCVar(name), '40')
		assert.is_nil(P.Store:Get({ 'behavior', 'pinScale' }))
		assert.is_false(P.enabled, 'still nothing running')
	end)
end)
