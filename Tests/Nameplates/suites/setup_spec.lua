-- @runtime lua51
-- Setup look step (plan 3.1): one compact look step, preselected on the host look, with the size as
-- a variant row on every card. Picks are staged and applied when the player moves on: style, size,
-- the role the host's own setup asked about, the game settings setup turns on, and plates on for
-- the profile. The Done page line lists the game settings, and "Give the game back its settings"
-- undoes them. Core only (host stub); the SpartanUI decoration is checked in host_launch_spec.
local M, H = ...

if not H.ModuleExists() then
	describe('setup', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

local function HostStyle(P)
	local clean = P.Styles.Registry:Get('clean')
	local style = P.util.Copy(clean)
	style.id = 'testhost'
	style.name = 'Host Look'
	style.matchesHost = true
	style.order = 1
	assert.is_true((P.API:RegisterStyle(style)))
end

local function Step(P)
	local steps = P:GetSetupSteps()
	assert.equal(#steps, 1)
	return steps[1]
end

describe('setup: the look step', function()
	it('is one compact profile look step with a size row on every card', function()
		M.Login('NameplatesTestHost')
		local P = H.FreshCore()
		HostStyle(P)
		local step = Step(P)
		assert.equal(step.id, 'nameplates-look')
		assert.equal(step.kind, 'look')
		assert.equal(step.scope, 'profile')
		assert.is_true(step.compact)
		assert.equal(type(step.cards), 'function')
		local cards = step.cards()
		assert.is_true(#cards >= 3, 'the built-in styles and the host look')
		local host
		for _, card in ipairs(cards) do
			assert.equal(#card.variants, 3, 'size row on ' .. tostring(card.value))
			assert.equal(card.variants[1].value, 'small')
			assert.equal(card.variants[3].value, 'large')
			if card.value == 'host' then
				host = card
			end
		end
		assert.not_nil(host, 'Match my look is offered as the host style')
		assert.is_true(host.recommended)
	end)

	it('starts on Match my look and medium, so Next accepts it', function()
		local P = H.FreshCore()
		local step = Step(P)
		assert.equal(step.get(), 'host')
		assert.equal(step.getVariant('host'), 'medium')
	end)

	it('stages a pick and a size without writing them', function()
		local P = H.FreshCore()
		local step = Step(P)
		step.set('clean')
		assert.equal(step.get(), 'clean')
		step.setVariant('mini', 'large')
		assert.equal(step.get(), 'mini', 'picking a size on a card picks the card')
		assert.equal(step.getVariant('clean'), 'large', 'one size for every card')
		assert.equal(P.db.profile.style, 'host')
		assert.equal(P.db.profile.size, 'medium')
		P.SetupSteps.pending = {}
	end)

	it('applies nothing when the window closes', function()
		local P = H.FreshCore()
		local step = Step(P)
		step.set('mini')
		step.onLeave({ closing = true })
		assert.equal(P.db.profile.style, 'host')
		assert.is_nil(rawget(P.db.profile, 'behavior'))
		P.SetupSteps.pending = {}
	end)

	it('applies style, size, setup game settings and plates on when the player moves on', function()
		local P = H.FreshCore()
		local step = Step(P)
		local changes = 0
		local owner = {}
		P:On('STORE_CHANGED', function()
			changes = changes + 1
		end, owner)
		step.setVariant('clean', 'small')
		step.onLeave({})
		P:Off('STORE_CHANGED', owner)
		assert.equal(changes, 1, 'one refresh for the whole step')
		assert.equal(P.db.profile.style, 'clean')
		assert.equal(P.db.profile.size, 'small')
		assert.same(P.db.profile.behavior.stacking, { enemy = true })
		assert.is_true(P.db.profile.behavior.friendlyNames)
		assert.is_true(P.db.profile.behavior.pinScale)
		assert.is_true(P.db.profile.enabled)
		assert.is_nil(P.SetupSteps.pending.style, 'the pending pick is cleared')
		assert.equal(P.db.profile.role, 'auto', 'no host answer keeps the role from the spec')
	end)

	it('keeps a game setting the player already chose', function()
		local P = H.FreshCore({ saved = { profileKeys = {}, profiles = { Default = { behavior = { friendlyNames = false } } } } })
		Step(P).onLeave({})
		assert.is_false(P.db.profile.behavior.friendlyNames)
		assert.is_true(P.db.profile.behavior.pinScale)
	end)

	it('takes the role from the host setup answer', function()
		local P = H.FreshCore({
			host = {
				GetSetupRole = function()
					return 'healer'
				end,
			},
		})
		Step(P).onLeave({})
		assert.equal(P.db.profile.role, 'healer')
	end)

	it('ignores a role it does not know and a host that errors', function()
		local P = H.FreshCore({
			host = {
				GetSetupRole = function()
					return 'dps'
				end,
			},
		})
		Step(P).onLeave({})
		assert.equal(P.db.profile.role, 'auto')
		local Q = H.FreshCore({
			host = {
				GetSetupRole = function()
					error('no answer')
				end,
			},
		})
		Step(Q).onLeave({})
		assert.equal(Q.db.profile.role, 'auto')
	end)

	it("turns plates on for a profile that kept them off, and answers its What's new card", function()
		local P = H.FreshCore({
			host = {
				ImportLegacy = function()
					return { action = 'off' }
				end,
			},
		})
		assert.is_false(P.db.profile.enabled)
		assert.equal(P.Migrate:MakeoverState(), 'off')
		Step(P).onLeave({})
		assert.is_true(P.db.profile.enabled)
		assert.equal(P.Migrate:MakeoverState(), 'done')
	end)
end)

describe('setup: the Done page', function()
	it('names the style and size, and the game settings setup turns on', function()
		local P = H.FreshCore()
		local step = Step(P)
		step.setVariant('clean', 'large')
		local before = step.summary()
		assert.matches(before, 'Clean')
		assert.matches(before, 'Large')
		assert.is_nil(before:find('overlap', 1, true), 'nothing changed yet')
		step.onLeave({})
		local after = step.summary()
		assert.matches(after, 'Plates do not overlap')
		assert.matches(after, 'Friendly players show names only')
		assert.matches(after, 'Plates keep one size')
	end)

	it('lists other game settings the plates changed, once each', function()
		local P = H.FreshCore()
		M.SetCVarState('nameplateMaxDistance', { value = '40', account = true })
		M.SetCVarState('nameplateMinScale', { value = '0.8', account = true })
		P.CVars.info.nameplateMaxDistance = nil
		P.CVars.info.nameplateMinScale = nil
		P.CVars:Set('nameplateMaxDistance', 60)
		P.CVars:Set('nameplateMinScale', 1)
		Step(P).onLeave({})
		local changed = P.SetupSteps:ChangedSettings()
		local seen = {}
		for _, text in ipairs(changed) do
			assert.is_nil(seen[text], 'listed twice: ' .. text)
			seen[text] = true
		end
		assert.is_true(seen[P.CVars.defs.nameplateMaxDistance.label], 'a setting with a backup is listed')
		assert.is_nil(seen[P.CVars.defs.nameplateMinScale.label], 'plate scale is covered by "Plates keep one size"')
		P.CVars:RestoreAll()
	end)

	it('gives the game its settings back and stops setup changes from coming back', function()
		local P = H.FreshCore()
		M.SetCVarState('nameplateMaxDistance', { value = '40', account = true })
		P.CVars.info.nameplateMaxDistance = nil
		P.CVars:Set('nameplateMaxDistance', 60)
		Step(P).onLeave({})
		assert.is_true(P.SetupSteps:RestoreGame())
		assert.equal(C_CVar.GetCVar('nameplateMaxDistance'), '40')
		assert.is_nil(P.CVars:GetBackup('nameplateMaxDistance'))
		assert.is_nil(P.Store:Get({ 'behavior', 'stacking' }))
		assert.is_nil(P.Store:Get({ 'behavior', 'pinScale' }))
		assert.equal(#P.SetupSteps:ChangedSettings(), 0)
	end)
end)

describe('setup: polish', function()
	it('says the style and the size in words on the Done page', function()
		local P = H.FreshCore()
		HostStyle(P)
		local step = Step(P)
		assert.matches(step.summary(), '^Style: Host Look%. Size: Medium%.')
		step.setVariant('clean', 'large')
		assert.matches(step.summary(), '^Style: Clean%. Size: Large%.')
		step.onLeave({})
		assert.matches(step.summary(), '^Style: Clean%. Size: Large%. Game settings we change: ')
		P.SetupSteps.pending = {}
	end)

	it('says friendly plates, not friends', function()
		local P = H.FreshCore()
		assert.equal(Step(P).text, 'The bars over enemy and friendly plates. You can change any part later.')
	end)

	it('puts Bordered right after Match my look on Era, TBC and Forever', function()
		local P = H.FreshCore()
		HostStyle(P)
		local values = {}
		for _, card in ipairs(Step(P).cards()) do
			values[#values + 1] = card.value
		end
		assert.equal(values[1], 'host')
		if FLAVOR == 'era' or FLAVOR == 'tbc' or FLAVOR == 'forever' then
			assert.equal(values[2], 'bordered')
		else
			assert.equal(values[2], 'clean')
		end
	end)

	it('offers no Match my look card until the host registers one, and the profile still falls back to Clean', function()
		local P = H.FreshCore()
		local step = Step(P)
		local found = false
		for _, card in ipairs(step.cards()) do
			found = found or card.value == 'host'
		end
		assert.is_false(found, 'no host look, no Match my look card')
		step.onLeave({})
		assert.equal(P.db.profile.style, 'host', 'the profile still follows the host look, which falls back to Clean')
		assert.equal(P.Styles.Registry:ResolveId('host'), 'clean')
	end)
end)
