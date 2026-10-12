-- @runtime lua51
-- Colors and roles (plan 3.5, 6.4, contracts 8): scheme row orders, the custom order, "When"
-- clauses, row colors from the player and the palettes, the compiled program's events, and the
-- priority rule "the top row that fits wins", including rows the game hides, which are folded
-- per channel through the engine so the answer is still the top row.
local M, H = ...
local S = M.S

if not H.ModuleExists() then
	describe('colors', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

local P = H.FreshCore()
local Colors, Roles = P.Colors, P.Roles

---A secret where the client has secrets, a plain value elsewhere (Classic clients never see one).
local function Hidden(v)
	if M.secrets then
		return S.Wrap(v)
	end
	return v
end

local function Ctx(fields)
	local ctx = { place = 'world', inCombat = false, role = 'damage', inGroup = true, playerLevel = 60, tanks = {}, petTank = false }
	for k, v in pairs(fields or {}) do
		ctx[k] = v
	end
	return ctx
end

local function Ids(program)
	local out = {}
	for i, row in ipairs(program.rows) do
		out[i] = row.id
	end
	return out
end

local function Row(program, id)
	for _, row in ipairs(program.rows) do
		if row.id == id then
			return row
		end
	end
end

---A sink that records the color it is handed (values may be secret).
local function Sink()
	local sink = {}
	local function take(_, r, g, b, a)
		sink.r, sink.g, sink.b, sink.a = r, g, b, a
	end
	sink.SetStatusBarColor, sink.SetTextColor, sink.SetVertexColor = take, take, take
	function sink.Color()
		return { S.Reveal(sink.r), S.Reveal(sink.g), S.Reveal(sink.b) }
	end
	return sink
end

local function RGB(c)
	return { c[1], c[2], c[3] }
end

---A source stub: each engine answer is 'hidden' (unreadable), true or false.
local function Src(answers)
	answers = answers or {}
	local src = {}
	local function Pair(name, plain, secret)
		src[plain] = function()
			local v = answers[name]
			if v == 'hidden' or (type(v) == 'table' and v.hidden) then
				return nil, false
			end
			return v == true, true
		end
		src[secret] = function()
			local v = answers[name]
			if type(v) == 'table' then
				return Hidden(v.value)
			end
			return Hidden(v == true)
		end
	end
	Pair('notInterruptible', 'NotInterruptiblePlain', 'NotInterruptibleSecret')
	Pair('important', 'IsImportantPlain', 'IsImportantSecret')
	Pair('aimed', 'AimedAtMePlain', 'AimedAtMeSecret')
	Pair('inCombat', 'InCombatPlain', 'InCombatSecret')
	function src:ThreatStatusPlain()
		if answers.threat == 'hidden' then
			return nil, false
		end
		return answers.threat, true
	end
	function src:IsTankingPlain(tank)
		local v = answers.tanking and answers.tanking[tank]
		if v == 'hidden' or type(v) == 'table' then
			return nil, false
		end
		return v == true, true
	end
	function src:IsTankingSecret(tank)
		local v = answers.tanking and answers.tanking[tank]
		if type(v) == 'table' then
			-- A unit that is not on the threat list gives no answer at all
			if v.nothing then
				return nil
			end
			return Hidden(v.value)
		end
		return Hidden(v == true)
	end
	return src
end

describe('colors: scheme orders', function()
	it('puts threat first for tanks, on the health bar where tanks see threat', function()
		local program = Colors:Compile('health', { scheme = 'auto' }, Ctx({ role = 'tank' }))
		assert.equal(program.scheme, 'threat')
		assert.same(Ids(program), { 'tapped', 'offTank', 'petTank', 'threat', 'quest', 'mobType', 'class', 'reaction' })
	end)

	it('puts mob type first for damage, with threat on the border only', function()
		local health = Colors:Compile('health', { scheme = 'auto' }, Ctx({ role = 'damage' }))
		assert.equal(health.scheme, 'mobType')
		assert.same(Ids(health), { 'tapped', 'mobType', 'quest', 'class', 'reaction' })
		local border = Colors:Compile('border', { scheme = 'auto' }, Ctx({ role = 'damage' }))
		assert.same(Ids(border), { 'target', 'focus', 'offTank', 'petTank', 'threat' })
	end)

	it('follows the player threat display choice over the role default', function()
		local program = Colors:Compile('health', { scheme = 'mobType', threat = { show = { bar = true } } }, Ctx({ role = 'damage' }))
		assert.same(Ids(program), { 'tapped', 'mobType', 'offTank', 'petTank', 'threat', 'quest', 'class', 'reaction' })
	end)

	it('puts class first for the class scheme', function()
		local program = Colors:Compile('health', { scheme = 'class' }, Ctx({ role = 'healer' }))
		assert.same(Ids(program), { 'tapped', 'class', 'mobType', 'quest', 'reaction' })
	end)

	it('orders the cast bar rows: cannot interrupt, interrupt ready, important', function()
		local program = Colors:Compile('cast', { scheme = 'auto' }, Ctx())
		assert.same(Ids(program), { 'notInterruptible', 'interruptReady', 'importantCast' })
	end)

	it('gives rows their default When clauses', function()
		local program = Colors:Compile('health', { scheme = 'threat' }, Ctx({ role = 'tank' }))
		assert.equal(Row(program, 'quest').when, 'world')
		assert.equal(Row(program, 'mobType').when, 'dungeons')
		assert.equal(Row(program, 'threat').when, 'instances')
		assert.equal(Row(program, 'tapped').when, 'everywhere')
		local always = Colors:Compile('health', { scheme = 'threat', threat = { when = 'always' } }, Ctx({ role = 'tank' }))
		assert.equal(Row(always, 'threat').when, 'everywhere')
	end)
end)

describe('colors: the player list', function()
	it('keeps a custom order and the scheme When clauses for rows it did not change', function()
		local settings = { scheme = 'custom', colors = { health = { order = { 'class', 'quest', 'tapped' }, when = { tapped = 'combat' } } } }
		local program = Colors:Compile('health', settings, Ctx())
		assert.same(Ids(program), { 'class', 'quest', 'tapped' })
		assert.equal(Row(program, 'quest').when, 'world')
		assert.equal(Row(program, 'tapped').when, 'combat')
	end)

	it('falls back to the role scheme when custom has no order yet', function()
		local program = Colors:Compile('health', { scheme = 'custom' }, Ctx({ role = 'tank' }))
		assert.equal(program.scheme, 'threat')
		assert.equal(Ids(program)[2], 'offTank')
	end)

	it('leaves out rows that are off, unknown, or not built yet', function()
		local settings = { scheme = 'custom', colors = { health = { order = { 'tapped', 'noSuchRow', 'unitInCombat', 'reaction' }, off = { reaction = true } } } }
		assert.same(Ids(Colors:Compile('health', settings, Ctx())), { 'tapped' })
	end)

	it('takes a curve row as the overlay, never as a folded row', function()
		local settings = { scheme = 'custom', colors = { health = { order = { 'lowHealth', 'reaction' } } } }
		local program = Colors:Compile('health', settings, Ctx())
		assert.same(Ids(program), { 'reaction' })
		assert.equal(program.overlay.id, 'lowHealth')
	end)

	it('uses the player colors over the defaults, for plain and mapped rows', function()
		local settings = {
			scheme = 'mobType',
			colors = { health = { color = { tapped = { 0, 0, 1 }, mobType = { boss = { 1, 1, 0 } } }, fallback = { 0.1, 0.2, 0.3 } } },
		}
		local program = Colors:Compile('health', settings, Ctx())
		assert.same(Row(program, 'tapped').color, { 0, 0, 1, 1 })
		assert.same(Row(program, 'mobType').colors.boss, { 1, 1, 0, 1 })
		assert.same(Row(program, 'mobType').colors.normal, { 0.8, 0.2, 0.2, 1 }, 'other states keep the default')
		assert.same(program.fallback, { 0.1, 0.2, 0.3, 1 })
	end)

	it('uses the color-blind threat palette, with the player threat colors on top', function()
		local program = Colors:Compile('health', { scheme = 'threat', colorBlind = true, threat = { colors = { lost = { 1, 0, 1, 1 } } } }, Ctx({ role = 'tank' }))
		local threat = Row(program, 'threat')
		assert.same(threat.colors.safe, Roles.PALETTE_COLORBLIND.safe)
		assert.same(threat.colors.lost, { 1, 0, 1, 1 })
	end)

	it('collects the events and messages its rows need', function()
		local program = Colors:Compile('health', { scheme = 'threat' }, Ctx({ role = 'tank' }))
		assert.is_true(program.events.UNIT_THREAT_LIST_UPDATE)
		assert.is_true(program.events.UNIT_FACTION, 'tapped and reaction')
		assert.is_true(program.messages.TANKS_CHANGED)
		assert.is_true(program.messages.QUESTS_CHANGED)
		local border = Colors:Compile('border', { scheme = 'threat' }, Ctx())
		assert.is_true(border.messages.TARGET_CHANGED)
		assert.is_true(border.messages.FOCUS_CHANGED)
	end)
end)

describe('colors: the top row that fits wins', function()
	local mobType = Colors:Compile('health', { scheme = 'mobType' }, Ctx())

	local function Apply(program, facts, ctxFields, states, src)
		local sink = Sink()
		local winner, engineRows = Colors:Apply(program, { facts = facts, ctx = Ctx(ctxFields), states = states or {}, src = src }, sink, 'SetStatusBarColor')
		return sink, winner, engineRows
	end

	it('gray beats everything when someone else tagged it', function()
		local sink, winner = Apply(mobType, { tapDenied = true, canAttack = true, reaction = 2, classification = 'elite' }, { place = 'dungeon' })
		assert.same(sink.Color(), { 0.5, 0.5, 0.5 })
		assert.equal(winner, 1)
	end)

	it('mob type wins in dungeons only', function()
		local facts = { canAttack = true, reaction = 2, classification = 'elite' }
		local sink = Apply(mobType, facts, { place = 'dungeon' })
		assert.same(sink.Color(), RGB(Colors:GetKind('mobType').default.elite))
		sink = Apply(mobType, facts, { place = 'world' })
		assert.same(sink.Color(), { 0.85, 0.2, 0.2 }, 'out in the world it falls through to reaction')
	end)

	it('quest wins out in the world, under tapped', function()
		local sink = Apply(mobType, { canAttack = true, reaction = 2, isQuest = true }, { place = 'world' })
		assert.same(sink.Color(), { 0.95, 0.8, 0.2 })
		sink = Apply(mobType, { canAttack = true, reaction = 2, isQuest = true }, { place = 'raid' })
		assert.same(sink.Color(), { 0.85, 0.2, 0.2 }, 'quest is off in raids')
	end)

	it('colors players by class and friends by reaction', function()
		local sink = Apply(mobType, { isPlayer = true, reaction = 5, classToken = 'MAGE' })
		local mage = RAID_CLASS_COLORS.MAGE
		assert.near(sink.Color()[1], mage.r, 1e-6)
		assert.near(sink.Color()[3], mage.b, 1e-6)
		sink = Apply(mobType, { reaction = 5 })
		assert.same(sink.Color(), { 0.25, 0.8, 0.3 })
		sink = Apply(mobType, { reaction = 4 })
		assert.same(sink.Color(), { 0.95, 0.8, 0.2 })
	end)

	it('uses the fallback when no row fits', function()
		local sink, winner, engineRows = Apply(mobType, {})
		assert.same(sink.Color(), RGB(Colors.FALLBACK.health))
		assert.is_nil(winner)
		assert.equal(engineRows, 0)
	end)

	it('honors the player order over the scheme', function()
		local custom = Colors:Compile('health', { scheme = 'custom', colors = { health = { order = { 'reaction', 'tapped' } } } }, Ctx())
		local sink = Apply(custom, { tapDenied = true, reaction = 2 })
		assert.same(sink.Color(), { 0.85, 0.2, 0.2 }, 'reaction is on top now')
	end)

	it('skips rows whose When clause is never', function()
		local custom = Colors:Compile('health', { scheme = 'custom', colors = { health = { order = { 'tapped', 'reaction' }, when = { tapped = 'never' } } } }, Ctx())
		local sink = Apply(custom, { tapDenied = true, reaction = 2 })
		assert.same(sink.Color(), { 0.85, 0.2, 0.2 })
	end)

	it('reads threat only when the game shows it (no threat color otherwise)', function()
		local tank = Colors:Compile('health', { scheme = 'threat' }, Ctx({ role = 'tank' }))
		local facts = { canAttack = true, reaction = 2 }
		local sink = Apply(tank, facts, { place = 'dungeon', role = 'tank', inGroup = true }, nil, Src({ threat = 3 }))
		assert.same(sink.Color(), RGB(Roles.PALETTE.safe))
		sink = Apply(tank, facts, { place = 'dungeon', role = 'tank', inGroup = true }, nil, Src({ threat = 0 }))
		assert.same(sink.Color(), RGB(Roles.PALETTE.lost))
		sink = Apply(tank, facts, { place = 'dungeon', role = 'tank', inGroup = false }, nil, Src({ threat = 3 }))
		assert.same(sink.Color(), RGB(Roles.PALETTE.solo))
		local _, winner, engineRows = Apply(tank, facts, { place = 'dungeon', role = 'tank', inGroup = true }, nil, Src({ threat = 'hidden' }))
		assert.not_equal(winner, 4, 'hidden threat never wins')
		assert.equal(engineRows, 0, 'and is not folded either')
		sink = Apply(tank, facts, { place = 'world', role = 'tank', inGroup = true }, nil, Src({ threat = 3 }))
		assert.same(sink.Color(), { 0.85, 0.2, 0.2 }, 'threat rows show in instances by default')
	end)

	it('shows another tank holding the mob, above your own threat', function()
		local tank = Colors:Compile('health', { scheme = 'threat' }, Ctx({ role = 'tank' }))
		local sink = Apply(tank, { canAttack = true, reaction = 2 }, { place = 'dungeon', role = 'tank', tanks = { 'party1' } }, nil, Src({ threat = 0, tanking = { party1 = true } }))
		assert.same(sink.Color(), RGB(Roles.PALETTE.offTank))
	end)
end)

describe('colors: rows the game hides', function()
	local cast = Colors:Compile('cast', { scheme = 'auto' }, Ctx())
	local GRAY = { 0.55, 0.55, 0.55 }
	local PURPLE = { 0.85, 0.35, 1 }
	local FALLBACK = RGB(Colors.FALLBACK.cast)

	local function Apply(answers)
		local sink = Sink()
		local winner, engineRows = Colors:Apply(cast, { facts = { canAttack = true }, ctx = Ctx(), states = {}, src = Src(answers) }, sink, 'SetStatusBarColor')
		return sink, winner, engineRows
	end

	it('settles readable answers in Lua', function()
		local sink, winner, engineRows = Apply({ notInterruptible = true })
		assert.same(sink.Color(), GRAY)
		assert.equal(winner, 1)
		assert.equal(engineRows, 0)
		sink, winner = Apply({ important = true })
		assert.same(sink.Color(), PURPLE)
		assert.equal(winner, 3)
	end)

	it('folds a hidden top row over the plain winner below it', function()
		local sink, winner, engineRows = Apply({ notInterruptible = { hidden = true, value = true }, important = true })
		assert.equal(winner, 3)
		assert.equal(engineRows, 1)
		if M.secrets then
			assert.secret(sink.r, 'the color handed to the bar stays secret')
		end
		assert.same(sink.Color(), GRAY, 'the hidden top row still wins when it holds')
		sink = Apply({ notInterruptible = { hidden = true, value = false }, important = true })
		assert.same(sink.Color(), PURPLE, 'and the plain winner shows when it does not')
	end)

	it('keeps the top-first rule when several hidden rows are folded', function()
		local sink, _, engineRows = Apply({ notInterruptible = { hidden = true, value = true }, important = { hidden = true, value = true } })
		assert.equal(engineRows, 2)
		assert.same(sink.Color(), GRAY)
		sink = Apply({ notInterruptible = { hidden = true, value = false }, important = { hidden = true, value = true } })
		assert.same(sink.Color(), PURPLE)
		sink = Apply({ notInterruptible = { hidden = true, value = false }, important = { hidden = true, value = false } })
		assert.same(sink.Color(), FALLBACK)
	end)

	it('never folds rows below the plain winner', function()
		local _, winner, engineRows = Apply({ notInterruptible = true, important = { hidden = true, value = true } })
		assert.equal(winner, 1)
		assert.equal(engineRows, 0)
	end)

	it('does not count interrupt ready as hidden when no interrupt is known', function()
		P.Context.kickSpell = nil
		local _, winner, engineRows = Apply({})
		assert.is_nil(winner)
		assert.equal(engineRows, 0)
	end)

	it('folds hidden tank rows once per tank', function()
		local tank = Colors:Compile('health', { scheme = 'threat' }, Ctx({ role = 'tank' }))
		local sink = Sink()
		local env = {
			facts = { canAttack = true, reaction = 2 },
			ctx = Ctx({ place = 'dungeon', role = 'tank', tanks = { 'party1', 'party2' } }),
			states = {},
			src = Src({ threat = 0, tanking = { party1 = { value = false }, party2 = { value = true } } }),
		}
		local winner, engineRows = Colors:Apply(tank, env, sink, 'SetVertexColor')
		assert.equal(engineRows, 1)
		assert.equal(winner, 4, 'your own lost threat is the plain winner')
		assert.same(sink.Color(), RGB(Roles.PALETTE.offTank), 'the second tank holds it')
	end)

	it('folds a tank that is not on the threat list as not holding it', function()
		local tank = Colors:Compile('health', { scheme = 'threat' }, Ctx({ role = 'tank' }))
		local env = {
			facts = { canAttack = true, reaction = 2 },
			ctx = Ctx({ place = 'dungeon', role = 'tank', tanks = { 'party1', 'party2' } }),
			states = {},
			src = Src({ threat = 0, tanking = { party1 = { nothing = true }, party2 = { value = false } } }),
		}
		local sink = Sink()
		Colors:Apply(tank, env, sink, 'SetVertexColor')
		assert.same(sink.Color(), RGB(Roles.PALETTE.lost), 'nobody else holds it, so your own threat shows')
		env.src = Src({ threat = 0, tanking = { party1 = { nothing = true }, party2 = { value = true } } })
		Colors:Apply(tank, env, sink, 'SetVertexColor')
		assert.same(sink.Color(), RGB(Roles.PALETTE.offTank))
	end)

	it('uses class colors the player picked, which have no default', function()
		local program = Colors:Compile('health', { scheme = 'class', colors = { health = { color = { class = { MAGE = { 0.1, 0.2, 0.3, 1 } } } } } }, Ctx())
		local row = Row(program, 'class')
		assert.same(row.colors.MAGE, { 0.1, 0.2, 0.3, 1 })
		local sink = Sink()
		Colors:Apply(program, { facts = { isPlayer = true, classToken = 'MAGE', reaction = 5 }, ctx = Ctx(), states = {}, src = Src({}) }, sink, 'SetStatusBarColor')
		assert.same(sink.Color(), { 0.1, 0.2, 0.3 })
	end)

	it('explains the winner and the rows that might override it', function()
		local winner, maybe = Colors:Explain(cast, { facts = {}, ctx = Ctx(), states = {}, src = Src({ notInterruptible = 'hidden', important = true }) })
		assert.equal(winner.id, 'importantCast')
		assert.equal(#maybe, 1)
		assert.equal(maybe[1].id, 'notInterruptible')
	end)
end)

describe('colors: condition folds', function()
	local Conditions = P.Conditions
	local function Fold(expr, answers)
		local env = { facts = {}, ctx = Ctx(), states = {}, src = Src(answers) }
		return S.Reveal(Conditions:FoldSecret(expr, env, 1, 0))
	end
	local function H_(v)
		return { hidden = true, value = v }
	end

	it('folds AND, OR and NOT the same way Lua would answer them', function()
		local A, B = { id = 'notInterruptible' }, { id = 'importantCast' }
		for _, a in ipairs({ true, false }) do
			for _, b in ipairs({ true, false }) do
				local answers = { notInterruptible = H_(a), important = H_(b) }
				assert.equal(Fold({ all = { A, B } }, answers), (a and b) and 1 or 0, 'AND')
				assert.equal(Fold({ any = { A, B } }, answers), (a or b) and 1 or 0, 'OR')
				assert.equal(Fold({ ['not'] = A }, answers), (not a) and 1 or 0, 'NOT')
				assert.equal(Fold({ id = 'notInterruptible', negate = true }, answers), (not a) and 1 or 0, 'negate')
				assert.equal(Fold({ all = { A, { ['not'] = B } } }, answers), (a and not b) and 1 or 0, 'AND NOT')
			end
		end
	end)

	it('settles plain leaves in Lua inside a fold', function()
		local env = { facts = { tapDenied = true }, ctx = Ctx(), states = {}, src = Src({ important = H_(false) }) }
		assert.equal(S.Reveal(Conditions:FoldSecret({ any = { { id = 'tapped' }, { id = 'importantCast' } } }, env, 1, 0)), 1)
		assert.equal(S.Reveal(Conditions:FoldSecret({ all = { { id = 'tapped' }, { id = 'importantCast' } } }, env, 1, 0)), 0)
	end)

	it('answers nil only when the game hides the answer', function()
		local env = { facts = {}, ctx = Ctx(), states = {}, src = Src({ important = 'hidden', notInterruptible = false }) }
		assert.is_nil(Conditions:TestExpr({ id = 'importantCast' }, env))
		assert.is_false(Conditions:TestExpr({ all = { { id = 'importantCast' }, { id = 'notInterruptible' } } }, env), 'a false leaf settles AND')
		assert.is_nil(Conditions:TestExpr({ any = { { id = 'importantCast' }, { id = 'notInterruptible' } } }, env))
		assert.is_false(Conditions:TestExpr({ id = 'noSuchCondition' }, env))
	end)

	it('allows only color, alpha and glow for engine conditions where secrets exist', function()
		local actions = Conditions:AllowedActions('importantCast')
		if P.Caps:Get('secrets') then
			assert.is_nil(actions.style)
			assert.is_true(actions.color)
		else
			assert.is_true(actions.style)
		end
		assert.is_true(Conditions:AllowedActions('tapped').style)
	end)
end)

describe('colors: program cache and new rows', function()
	it('reuses the compiled program until colors, look or context change', function()
		local a = Colors:Program('health')
		assert.is_true(rawequal(a, Colors:Program('health')))
		P.Store:Set('modes.friendlyNPC', 'full')
		assert.is_true(rawequal(a, Colors:Program('health')), 'assignment changes keep it')
		P.Store:Set('scheme', 'class')
		local b = Colors:Program('health')
		assert.is_false(rawequal(a, b))
		assert.equal(b.scheme, 'class')
		P:Fire('CONTEXT_CHANGED')
		assert.is_false(rawequal(b, Colors:Program('health')))
		P.Store:Set('scheme', nil)
		P.Store:Set('modes', nil)
	end)

	it('suggests a spot for a new row under the rows that rank higher', function()
		assert.equal(Colors:SuggestInsertIndex('health', 'class', { 'tapped', 'reaction' }, {}, 'damage'), 2)
		assert.equal(Colors:SuggestInsertIndex('health', 'tapped', { 'class', 'reaction' }, {}, 'damage'), 1)
		assert.equal(Colors:SuggestInsertIndex('health', 'fixed', { 'tapped', 'reaction' }, {}, 'damage'), 3, 'unranked rows go last')
	end)
end)

describe('roles', function()
	it('resolves the role from the setting or the spec', function()
		assert.equal(Roles.Resolve('tank', 'HEALER'), 'tank')
		assert.equal(Roles.Resolve('auto', 'TANK'), 'tank')
		assert.equal(Roles.Resolve('auto', 'HEALER'), 'healer')
		assert.equal(Roles.Resolve('auto', 'DAMAGER'), 'damage')
		assert.equal(Roles.Resolve(nil, nil), 'damage')
		assert.equal(Roles.Resolve('auto', 'NONE'), 'damage')
	end)

	it('maps threat status to a state per role', function()
		local cases = {
			-- role, status, inGroup, state
			{ 'tank', 3, true, 'safe' },
			{ 'tank', 2, true, 'losing' },
			{ 'tank', 1, true, 'lost' },
			{ 'tank', 0, true, 'lost' },
			{ 'damage', 0, true, 'safe' },
			{ 'damage', 1, true, 'losing' },
			{ 'damage', 2, true, 'lost' },
			{ 'damage', 3, true, 'lost' },
			{ 'healer', 0, true, 'safe' },
			{ 'tank', 3, false, 'solo' },
			{ 'damage', 0, false, 'solo' },
		}
		for _, c in ipairs(cases) do
			assert.equal(Roles.ThreatState(c[1], c[2], c[3]), c[4], c[1] .. ' ' .. c[2] .. ' ' .. tostring(c[3]))
		end
		assert.is_nil(Roles.ThreatState('tank', nil, true), 'not on the threat list')
	end)

	it('picks where threat shows and which scheme auto means', function()
		assert.same(Roles.ThreatOn('tank'), { bar = true })
		assert.same(Roles.ThreatOn('damage', {}), { border = true }, 'an empty choice keeps the default')
		assert.same(Roles.ThreatOn('healer', { name = true }), { name = true })
		assert.equal(Roles.Scheme('tank'), 'threat')
		assert.equal(Roles.Scheme('healer'), 'mobType')
		assert.equal(Roles.Scheme('nonsense'), 'mobType')
		assert.is_true(Roles.HealerEmphasis('healer'))
		assert.is_false(Roles.HealerEmphasis('tank'))
	end)

	it('builds the palette with the player colors on top', function()
		local palette = Roles.Palette(false, { safe = { 0, 1, 1, 1 } })
		assert.same(palette.safe, { 0, 1, 1, 1 })
		assert.same(palette.lost, Roles.PALETTE.lost)
		for _, state in ipairs(Roles.STATES) do
			assert.not_nil(Roles.PALETTE_COLORBLIND[state], 'color-blind ' .. state)
		end
	end)
end)
