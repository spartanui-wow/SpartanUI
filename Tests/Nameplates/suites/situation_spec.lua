-- @runtime lua51
-- Situation (plan 6.4, contracts 8): Classify, MobType, PlaceFrom and Assign as truth tables over
-- plain facts and a context table, plus the "When" list (first match, plain conditions only) and
-- the facts each decision records.
local M, H = ...

if not H.ModuleExists() then
	describe('situation', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

local P = H.FreshCore()
local Situation = P.Situation

local function Ctx(fields)
	local ctx = { place = 'world', inCombat = false, resting = false, role = 'damage', inGroup = false, playerLevel = 60, difficultyID = 0 }
	for k, v in pairs(fields or {}) do
		ctx[k] = v
	end
	return ctx
end

local function Env(facts, ctxFields, states)
	return { facts = facts or {}, ctx = Ctx(ctxFields), states = states or {} }
end

describe('situation: Classify', function()
	local cases = {
		-- facts, expected
		{ { isPlayer = true, canAttack = true, reaction = 2 }, 'enemyPlayer', 'attackable hostile player' },
		{ { isPlayer = true, canAttack = false, reaction = 2 }, 'enemyPlayer', 'hostile reaction alone (cannot attack yet)' },
		{ { isPlayer = true, canAttack = true, reaction = 5 }, 'enemyPlayer', 'attackable friendly-reaction player (duel)' },
		{ { isPlayer = true, canAttack = false, reaction = 5 }, 'friendlyPlayer', 'friendly player' },
		{ { isPlayer = true, canAttack = false, reaction = 4 }, 'friendlyPlayer', 'neutral player that cannot be attacked' },
		{ { isPlayer = true }, 'friendlyPlayer', 'player with unknown reaction' },
		{ { canAttack = true, reaction = 2, classification = 'normal' }, 'enemyNPC', 'hostile mob' },
		{ { canAttack = true, reaction = 4, classification = 'normal' }, 'enemyNPC', 'neutral mob you can attack' },
		{ { canAttack = false, reaction = 4 }, 'friendlyNPC', 'neutral mob you cannot attack' },
		{ { canAttack = false, reaction = 3 }, 'enemyNPC', 'unfriendly mob you cannot attack yet' },
		{ { canAttack = false, reaction = 5 }, 'friendlyNPC', 'friendly NPC' },
		{ { canAttack = false, reaction = 8 }, 'friendlyNPC', 'exalted NPC' },
		{ {}, 'friendlyNPC', 'nothing known' },
		{ { canAttack = true, reaction = 2, classification = 'elite' }, 'enemyNPC', 'elite' },
		{ { canAttack = true, reaction = 2, classification = 'worldboss' }, 'enemyNPC', 'world boss' },
		{ { canAttack = true, reaction = 2, classification = 'rare' }, 'enemyNPC', 'rare' },
		{ { canAttack = true, reaction = 2, classification = 'minus' }, 'minor', 'minus mob' },
		{ { canAttack = true, reaction = 2, classification = 'trivial' }, 'minor', 'trivial mob' },
		{ { canAttack = true, reaction = 2, isMinion = true }, 'minor', 'enemy minion' },
		{ { canAttack = true, reaction = 2, playerControlled = true }, 'minor', 'enemy player pet' },
		{ { canAttack = false, reaction = 5, isMinion = true }, 'friendlyNPC', 'friendly minion' },
		{ { canAttack = false, reaction = 5, playerControlled = true }, 'friendlyNPC', 'friendly pet' },
		{ { canAttack = false, reaction = 5, classification = 'minus' }, 'friendlyNPC', 'friendly minus critter' },
		{ { isPlayer = true, canAttack = true, reaction = 2, classification = 'minus' }, 'enemyPlayer', 'players are never minor' },
	}
	for _, case in ipairs(cases) do
		it(case[3] .. ' -> ' .. case[2], function()
			assert.equal(Situation.Classify(case[1]), case[2])
		end)
	end

	it('treats can-attack or reaction 1 to 3 as hostile', function()
		for reaction = 1, 8 do
			assert.equal(Situation.IsHostile({ reaction = reaction }), reaction <= 3, 'reaction ' .. reaction)
			assert.is_true(Situation.IsHostile({ reaction = reaction, canAttack = true }))
		end
	end)

	it('returns only the five known kinds', function()
		local known = {}
		for _, kind in ipairs(Situation.KINDS) do
			known[kind] = true
		end
		for _, case in ipairs(cases) do
			assert.is_true(known[Situation.Classify(case[1])] == true)
		end
	end)
end)

describe('situation: MobType', function()
	local ctx = Ctx({ playerLevel = 60 })
	local cases = {
		{ { classification = 'minus' }, 'minor' },
		{ { classification = 'trivial' }, 'minor' },
		{ { classification = 'normal', isMinion = true }, 'minor' },
		{ { classification = 'normal', isBoss = true }, 'boss' },
		{ { classification = 'worldboss' }, 'boss' },
		{ { classification = 'elite', effectiveLevel = -1 }, 'boss' },
		{ { classification = 'elite', isLieutenant = true, isBoss = false }, 'miniboss' },
		{ { classification = 'normal', isLieutenant = true }, 'miniboss' },
		-- Classic family: no lieutenant API, an elite above your level is a mini-boss
		{ { classification = 'elite', effectiveLevel = 62 }, 'miniboss' },
		{ { classification = 'rareelite', effectiveLevel = 61 }, 'miniboss' },
		{ { classification = 'elite', effectiveLevel = 60 }, 'elite' },
		-- Retail and Forever answer isLieutenant = false: level never makes a mini-boss there
		{ { classification = 'elite', effectiveLevel = 62, isLieutenant = false }, 'elite' },
		{ { classification = 'elite', isCaster = true }, 'caster' },
		{ { classification = 'normal', isCaster = true }, 'caster' },
		{ { classification = 'elite' }, 'elite' },
		{ { classification = 'rareelite' }, 'elite' },
		{ { classification = 'rare' }, 'normal' },
		{ { classification = 'normal' }, 'normal' },
		{ {}, 'normal' },
	}
	for i, case in ipairs(cases) do
		it(('case %d -> %s'):format(i, case[2]), function()
			assert.equal(Situation.MobType(case[1], ctx), case[2])
		end)
	end

	it('needs the context to spot a higher-level elite', function()
		assert.equal(Situation.MobType({ classification = 'elite', effectiveLevel = 62 }, nil), 'elite')
	end)
end)

describe('situation: places', function()
	local cases = {
		{ false, 'none', 0, 'world' },
		{ false, 'party', 1, 'world' },
		{ true, 'party', 1, 'dungeon' },
		{ true, 'party', 8, 'dungeon' },
		{ true, 'raid', 16, 'raid' },
		{ true, 'scenario', 1, 'scenario' },
		{ true, 'scenario', 208, 'delve' },
		{ true, 'party', 208, 'delve' },
		{ true, 'arena', 0, 'arena' },
		{ true, 'pvp', 0, 'battleground' },
		{ true, 'neighborhood', 0, 'world' },
		{ true, 'interior', 0, 'world' },
		{ true, 'none', 0, 'world' },
		{ true, nil, nil, 'world' },
	}
	for _, case in ipairs(cases) do
		it(('%s %s %s -> %s'):format(tostring(case[1]), tostring(case[2]), tostring(case[3]), case[4]), function()
			assert.equal(Situation.PlaceFrom(case[1], case[2], case[3]), case[4])
		end)
	end

	it('reads the place from the client into the context', function()
		local ctx = Ctx()
		M.SetPlace({ inInstance = true, instanceType = 'party', difficultyID = 23 })
		Situation.ReadPlace(ctx)
		assert.equal(ctx.place, 'dungeon')
		assert.equal(ctx.difficultyID, 23)
		assert.is_true(ctx.inInstance)
		M.SetPlace({ inInstance = true, instanceType = 'scenario', difficultyID = 208 })
		Situation.ReadPlace(ctx)
		assert.equal(ctx.place, 'delve')
		M.SetPlace({ inInstance = false, instanceType = 'none', difficultyID = 0 })
		Situation.ReadPlace(ctx)
		assert.equal(ctx.place, 'world')
		assert.equal(ctx.difficultyID, 0)
		assert.is_false(ctx.challengeActive)
	end)
end)

describe('situation: Assign defaults', function()
	local function Run(kind, settings, env)
		return Situation.Assign(kind, env or Env(), settings or { style = 'host', size = 'medium' }, {})
	end

	local cases = {
		-- kind, settings, style, mode, size
		{ 'enemyNPC', nil, 'host', 'full', 'medium' },
		{ 'enemyPlayer', nil, 'host', 'full', 'medium' },
		{ 'friendlyNPC', nil, 'host', 'hidden', 'medium' },
		{ 'friendlyPlayer', nil, 'namesOnly', 'name', 'medium' },
		{ 'minor', nil, 'mini', 'full', 'medium' },
		{ 'enemyNPC', { style = 'clean', size = 'large' }, 'clean', 'full', 'large' },
		{ 'minor', { style = 'clean' }, 'mini', 'full', 'medium' },
		{ 'minor', { style = 'clean', assign = { minor = 'clean' } }, 'clean', 'full', 'medium' },
		{ 'enemyPlayer', { style = 'clean', assign = { enemyPlayer = 'mini' } }, 'mini', 'full', 'medium' },
		{ 'friendlyNPC', { style = 'clean', modes = { friendlyNPC = 'full' } }, 'clean', 'full', 'medium' },
		{ 'friendlyPlayer', { style = 'clean', modes = { friendlyPlayer = 'full' } }, 'clean', 'full', 'medium' },
		{ 'enemyNPC', { style = 'clean', modes = { enemyNPC = 'name' } }, 'namesOnly', 'name', 'medium' },
		{ 'enemyNPC', { style = 'clean', modes = { enemyNPC = 'hidden' } }, 'clean', 'hidden', 'medium' },
		{ 'enemyNPC', {}, 'host', 'full', 'medium' },
	}
	for i, case in ipairs(cases) do
		it(('case %d: %s -> %s %s %s'):format(i, case[1], case[3], case[4], case[5]), function()
			local out = Run(case[1], case[2])
			assert.equal(out.style, case[3], 'style')
			assert.equal(out.mode, case[4], 'mode')
			assert.equal(out.size, case[5], 'size')
			assert.is_nil(out.whenIndex)
		end)
	end
end)

describe('situation: the When list', function()
	local base = { style = 'clean', size = 'medium' }

	local function With(when, extra)
		local settings = { style = base.style, size = base.size, when = when }
		for k, v in pairs(extra or {}) do
			settings[k] = v
		end
		return settings
	end

	it('takes the first matching entry, top to bottom', function()
		local settings = With({
			{ conditions = { { id = 'place', args = 'raid' } }, style = 'mini' },
			{ conditions = { { id = 'place', args = 'dungeon' } }, style = 'bold', size = 'large' },
			{ conditions = { { id = 'place', args = 'instance' } }, style = 'slim' },
		})
		local out = Situation.Assign('enemyNPC', Env({}, { place = 'dungeon' }), settings, {})
		assert.equal(out.style, 'bold')
		assert.equal(out.size, 'large')
		assert.equal(out.whenIndex, 2)
		out = Situation.Assign('enemyNPC', Env({}, { place = 'arena' }), settings, out)
		assert.equal(out.style, 'slim')
		assert.equal(out.whenIndex, 3)
		out = Situation.Assign('enemyNPC', Env({}, { place = 'world' }), settings, out)
		assert.equal(out.style, 'clean')
		assert.is_nil(out.whenIndex, 'nothing matched')
	end)

	it('wins over assign and modes, and keeps what it does not set', function()
		local settings = With({ { conditions = { { id = 'myCombat' } }, size = 'small' } }, { assign = { enemyNPC = 'mini' }, modes = { enemyNPC = 'name' } })
		local out = Situation.Assign('enemyNPC', Env({}, { inCombat = true }), settings, {})
		assert.equal(out.size, 'small')
		assert.equal(out.mode, 'name', 'the mode it did not set')
		assert.equal(out.style, 'namesOnly', 'name mode still draws names only')
		local hidden = With({ { conditions = { { id = 'myCombat' } }, mode = 'full', style = 'bold' } }, { modes = { friendlyNPC = 'hidden' } })
		out = Situation.Assign('friendlyNPC', Env({}, { inCombat = true }), hidden, out)
		assert.equal(out.mode, 'full')
		assert.equal(out.style, 'bold')
	end)

	it('applies only to the kinds it lists', function()
		local settings = With({ { kinds = { 'enemyPlayer', 'friendlyPlayer' }, style = 'mini' } })
		assert.equal(Situation.Assign('enemyPlayer', Env(), settings, {}).style, 'mini')
		assert.equal(Situation.Assign('enemyNPC', Env(), settings, {}).style, 'clean')
	end)

	it('skips entries that are switched off', function()
		local settings = With({ { off = true, style = 'mini' }, { style = 'bold' } })
		local out = Situation.Assign('enemyNPC', Env(), settings, {})
		assert.equal(out.style, 'bold')
		assert.equal(out.whenIndex, 2)
	end)

	it('needs every condition of an entry to match', function()
		local settings = With({ { conditions = { { id = 'place', args = 'dungeon' }, { id = 'role', args = 'tank' } }, style = 'mini' } })
		assert.equal(Situation.Assign('enemyNPC', Env({}, { place = 'dungeon', role = 'tank' }), settings, {}).style, 'mini')
		assert.equal(Situation.Assign('enemyNPC', Env({}, { place = 'dungeon', role = 'healer' }), settings, {}).style, 'clean')
	end)

	it('turns a condition around with negate', function()
		local settings = With({ { conditions = { { id = 'place', args = 'world', negate = true } }, style = 'mini' } })
		assert.equal(Situation.Assign('enemyNPC', Env({}, { place = 'raid' }), settings, {}).style, 'mini')
		assert.equal(Situation.Assign('enemyNPC', Env({}, { place = 'world' }), settings, {}).style, 'clean')
	end)

	it('never matches on a condition the engine decides, or one it does not know', function()
		local env = Env({ canAttack = true })
		env.src = {
			NotInterruptiblePlain = function()
				return true, true
			end,
		}
		local settings = With({ { conditions = { { id = 'notInterruptible' } }, style = 'mini' }, { conditions = { { id = 'noSuchCondition' } }, style = 'bold' } })
		local out = Situation.Assign('enemyNPC', env, settings, {})
		assert.equal(out.style, 'clean')
		assert.is_nil(out.whenIndex)
	end)

	it('matches on plain facts such as tapped, elite and level', function()
		local settings = With({
			{ conditions = { { id = 'tapped' } }, style = 'mini' },
			{ conditions = { { id = 'mobType', args = 'boss' } }, size = 'large' },
		})
		assert.equal(Situation.Assign('enemyNPC', Env({ tapDenied = true }), settings, {}).style, 'mini')
		local out = Situation.Assign('enemyNPC', Env({ classification = 'worldboss' }), settings, {})
		assert.equal(out.size, 'large')
		assert.equal(out.style, 'clean')
	end)

	it('ignores a When list that is not a table', function()
		local out = Situation.Assign('enemyNPC', Env(), With('broken'), {})
		assert.equal(out.style, 'clean')
	end)
end)

describe('situation: facts each decision reads', function()
	it('always records the facts Classify uses', function()
		local out = Situation.Assign('enemyNPC', Env(), { style = 'clean' }, {})
		for _, fact in ipairs(Situation.CLASSIFY_FACTS) do
			assert.is_true(out.deps[fact], fact)
		end
	end)

	it('adds the facts of conditions it checked, and wipes the old ones on reuse', function()
		local settings = { style = 'clean', when = { { conditions = { { id = 'tapped' } }, style = 'mini' } } }
		local out = Situation.Assign('enemyNPC', Env(), settings, {})
		assert.is_true(out.deps.tapDenied)
		out = Situation.Assign('enemyNPC', Env(), { style = 'clean' }, out)
		assert.is_nil(out.deps.tapDenied, 'a reused result forgets facts it no longer reads')
	end)

	it('does not record facts of entries for other kinds', function()
		local settings = { style = 'clean', when = { { kinds = { 'enemyPlayer' }, conditions = { { id = 'tapped' } }, style = 'mini' } } }
		local out = Situation.Assign('enemyNPC', Env(), settings, {})
		assert.is_nil(out.deps.tapDenied)
	end)
end)

describe('situation: classify then assign', function()
	local profile = { style = 'clean', size = 'medium' }
	local table_ = {
		{ { isPlayer = true, canAttack = true, reaction = 2 }, 'enemyPlayer', 'clean', 'full' },
		{ { isPlayer = true, reaction = 5 }, 'friendlyPlayer', 'namesOnly', 'name' },
		{ { canAttack = true, reaction = 2, classification = 'elite' }, 'enemyNPC', 'clean', 'full' },
		{ { canAttack = false, reaction = 5 }, 'friendlyNPC', 'clean', 'hidden' },
		{ { canAttack = true, reaction = 2, classification = 'minus' }, 'minor', 'mini', 'full' },
	}
	for _, row in ipairs(table_) do
		it(row[2] .. ' -> ' .. row[3] .. ' ' .. row[4], function()
			local kind = Situation.Classify(row[1])
			assert.equal(kind, row[2])
			local out = Situation.Assign(kind, Env(row[1]), profile, {})
			assert.equal(out.style, row[3])
			assert.equal(out.mode, row[4])
		end)
	end
end)
