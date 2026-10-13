-- @runtime lua51
-- The "When" builder (plan 3.2 page 5, 3.5): what it offers comes from the condition catalog,
-- only actions that can work for the chosen conditions are offered, sentences read in plain words,
-- templates make entries Situation.Assign honors, and the editor group reads and writes its entry
-- through get/set on every call.
local M, H = ...

if not H.ModuleExists() then
	describe('when builder', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

local P = H.FreshCore()
local WB = P.WhenBuilder
local Conditions, Situation, Store = P.Conditions, P.Situation, P.Store

local function Ctx(fields)
	local ctx = { place = 'world', inCombat = false, resting = false, role = 'damage', inGroup = false, playerLevel = 60, difficultyID = 0, tanks = {} }
	for k, v in pairs(fields or {}) do
		ctx[k] = v
	end
	return ctx
end

local function Env(facts, ctx, states)
	return { facts = facts or {}, ctx = Ctx(ctx), states = states or {} }
end

local function Keys(list)
	local out = {}
	for i, choice in ipairs(list) do
		out[i] = choice.key
	end
	return out
end

local function Has(list, value)
	for _, v in ipairs(list) do
		if v == value then
			return true
		end
	end
	return false
end

local function Ids(defs)
	local out = {}
	for i, def in ipairs(defs) do
		out[i] = def.id
	end
	return out
end

local function Sorted(set)
	local out = {}
	for k in pairs(set) do
		out[#out + 1] = k
	end
	table.sort(out)
	return out
end

describe('when builder: conditions come from the catalog', function()
	it('offers only plain catalog conditions for special cases', function()
		local choices = WB:Choices('layout')
		assert.truthy(#choices > 20, 'a real list')
		for _, choice in ipairs(choices) do
			local cond = Conditions:Get(choice.id)
			assert.not_nil(cond, choice.key .. ' is in the catalog')
			assert.equal(cond.kind, 'plain', choice.key .. ' is plain')
			assert.truthy(choice.phase <= WB.PHASE, choice.key .. ' is not from a later phase')
			assert.is_nil(({ target = 1, focus = 1, mouseover = 1, casting = 1 })[choice.id], choice.key .. ' is a state, not a layout condition')
			assert.truthy(choice.label ~= nil and choice.label ~= '', choice.key .. ' has a label')
			assert.truthy(choice.phrase ~= nil and choice.phrase ~= '', choice.key .. ' has a phrase')
		end
	end)

	it('offers the conditions the plan lists', function()
		local keys = Keys(WB:Choices('layout'))
		for _, key in ipairs({ 'place:raid', 'place:dungeon', 'place:delve', 'place:pvp', 'resting', '!myCombat', 'role:tank', 'elite', 'canAttack' }) do
			assert.truthy(Has(keys, key), key .. ' is offered')
		end
	end)

	it('gives every key a stored condition that maps back to the same key', function()
		for _, choice in ipairs(WB:Choices('layout')) do
			local clause = WB:ClauseForKey(choice.key)
			assert.not_nil(clause, choice.key)
			assert.equal(WB:KeyOf(clause), choice.key)
			assert.equal(clause.id, choice.id)
		end
		assert.is_nil(WB:ClauseForKey('nothing:here'))
	end)

	local cases = {
		-- key, ctx fields, facts, states, expected
		{ 'place:raid', { place = 'raid' }, nil, nil, true },
		{ 'place:raid', { place = 'dungeon' }, nil, nil, false },
		{ 'place:dungeon', { place = 'dungeon' }, nil, nil, true },
		{ 'place:dungeon', { place = 'delve' }, nil, nil, false },
		{ 'place:delve', { place = 'delve' }, nil, nil, true },
		{ 'place:pvp', { place = 'arena' }, nil, nil, true },
		{ 'place:pvp', { place = 'battleground' }, nil, nil, true },
		{ 'place:pvp', { place = 'raid' }, nil, nil, false },
		{ 'place:battleground', { place = 'battleground' }, nil, nil, true },
		{ 'place:arena', { place = 'arena' }, nil, nil, true },
		{ 'place:instance', { place = 'dungeon' }, nil, nil, true },
		{ 'place:instance', { place = 'world' }, nil, nil, false },
		{ 'place:world', { place = 'world' }, nil, nil, true },
		{ 'place:world', { place = 'raid' }, nil, nil, false },
		{ '!myCombat', { inCombat = false }, nil, nil, true },
		{ '!myCombat', { inCombat = true }, nil, nil, false },
		{ 'myCombat', { inCombat = true }, nil, nil, true },
		{ 'resting', { resting = true }, nil, nil, true },
		{ '!resting', { resting = true }, nil, nil, false },
		{ '!resting', { resting = false }, nil, nil, true },
		{ 'role:tank', { role = 'tank' }, nil, nil, true },
		{ 'role:tank', { role = 'damage' }, nil, nil, false },
		{ 'role:healer', { role = 'healer' }, nil, nil, true },
		{ 'role:damage', { role = 'damage' }, nil, nil, true },
		{ 'inGroup', { inGroup = true }, nil, nil, true },
		{ '!inGroup', { inGroup = true }, nil, nil, false },
		{ 'challenge', { challengeActive = true }, nil, nil, true },
		{ 'challenge', { challengeActive = false }, nil, nil, false },
		{ 'canAttack', nil, { canAttack = true }, nil, true },
		{ '!canAttack', nil, { canAttack = true }, nil, false },
		{ '!canAttack', nil, { canAttack = false }, nil, true },
		{ 'elite', nil, { classification = 'elite' }, nil, true },
		{ 'elite', nil, { classification = 'worldboss' }, nil, true },
		{ 'elite', nil, { classification = 'normal' }, nil, false },
		{ 'rare', nil, { classification = 'rare' }, nil, true },
		{ 'mobType:boss', nil, { classification = 'worldboss' }, nil, true },
		{ 'mobType:normal', nil, { classification = 'normal', effectiveLevel = 60 }, nil, true },
		{ 'mobType:caster', nil, { classification = 'normal', isCaster = true, effectiveLevel = 60 }, nil, true },
		{ 'levelAbove', nil, { effectiveLevel = 62 }, nil, true },
		{ 'levelAbove', nil, { effectiveLevel = 58 }, nil, false },
		{ 'isPlayer', nil, { isPlayer = true }, nil, true },
		{ 'isNPC', nil, { isPlayer = false }, nil, true },
		{ 'minion', nil, { isMinion = true }, nil, true },
		{ 'tapped', nil, { tapDenied = true }, nil, true },
		{ 'quest', nil, { isQuest = true }, nil, true },
		{ 'reaction:hostile', nil, { reaction = 2 }, nil, true },
		{ 'reaction:friendly', nil, { reaction = 5 }, nil, true },
		{ 'reaction:neutral', nil, { reaction = 4 }, nil, true },
		{ 'reaction:hostile', nil, { reaction = 5 }, nil, false },
	}
	for _, case in ipairs(cases) do
		it(string.format('%s is %s for %s %s', case[1], tostring(case[5]), case[2] and 'ctx' or 'facts', case[2] and next(case[2]) or next(case[3] or {})), function()
			local clause = WB:ClauseForKey(case[1])
			assert.not_nil(clause, case[1])
			local entry = { conditions = { clause }, size = 'small' }
			local result = Situation.EntryApplies(entry, 'enemyNPC', Env(case[3], case[2], case[4]))
			assert.equal(result, case[5])
		end)
	end

	it('offers a condition registered later with no change to the builder', function()
		Conditions:Register({
			id = 'testPlate',
			kind = 'plain',
			label = 'Test plate',
			facts = { 'isPlayer' },
			Test = function(env)
				return env.facts.isPlayer == true
			end,
		})
		local found
		for _, choice in ipairs(WB:Choices('layout')) do
			if choice.key == 'testPlate' then
				found = choice
			end
		end
		assert.not_nil(found, 'new condition is offered')
		assert.equal(found.label, 'Test plate')
		assert.equal(found.group, 'plate', 'a condition that reads facts is about the plate')
		local entry = { conditions = { { id = 'testPlate' } }, mode = 'hidden' }
		assert.is_true(Situation.EntryApplies(entry, 'enemyNPC', Env({ isPlayer = true })))
		assert.truthy(WB:Sentence(entry):find('test plate', 1, true), WB:Sentence(entry))
	end)

	it('leaves out conditions that need a picker, a later phase or the engine', function()
		Conditions:Register({
			id = 'testPicker',
			kind = 'plain',
			label = 'Needs a picker',
			argType = 'spellList',
			Test = function()
				return false
			end,
		})
		Conditions:Register({
			id = 'testLater',
			kind = 'plain',
			label = 'Later phase',
			phase = 99,
			Test = function()
				return false
			end,
		})
		Conditions:Register({
			id = 'testEngine',
			kind = 'engine',
			label = 'Engine thing',
			Test = function()
				return nil
			end,
			TestSecret = function()
				return false
			end,
		})
		local layout = Keys(WB:Choices('layout'))
		assert.is_false(Has(layout, 'testPicker'))
		assert.is_false(Has(layout, 'testLater'))
		assert.is_false(Has(layout, 'testEngine'), 'the layout never waits for an answer the game hides')
		local emphasis = Keys(WB:Choices('emphasis'))
		assert.is_true(Has(emphasis, 'testEngine'), 'colors and fades may use it')
		assert.is_true(Has(emphasis, 'target'), 'states only change emphasis')
		assert.is_false(Has(emphasis, 'testPicker'))
		assert.is_false(Has(emphasis, 'testLater'))
		local phase = WB.PHASE
		WB.PHASE = 99
		assert.is_true(Has(Keys(WB:Choices('layout')), 'testLater'), 'a later phase raises the line')
		WB.PHASE = phase
	end)

	it('shows a catalog limit as a badge on this client', function()
		local client = P.Caps:Client()
		Conditions:Register({
			id = 'testLimited',
			kind = 'plain',
			label = 'Limited thing',
			limits = { [client] = 'Only in the open world here' },
			Test = function()
				return false
			end,
		})
		local found
		for _, choice in ipairs(WB:Choices('layout')) do
			if choice.key == 'testLimited' then
				found = choice
			end
		end
		assert.not_nil(found)
		assert.equal(found.badge, 'Only in the open world here')
		assert.truthy(WB:Badge({ { id = 'testLimited' } }):find('Only in the open world here', 1, true))
	end)

	it('marks situations a client does not have', function()
		local saved = P.Caps.client
		P.Caps.client = 'era'
		local delve, arena
		for _, choice in ipairs(WB:Choices('layout')) do
			if choice.key == 'place:delve' then
				delve = choice
			elseif choice.key == 'place:arena' then
				arena = choice
			end
		end
		assert.is_false(delve.available)
		assert.is_false(arena.available)
		assert.not_nil(delve.badge)
		assert.truthy(WB:Problems({ conditions = { { id = 'place', args = 'delve' } }, size = 'small' }, 'layout')[1], 'a problem is named')
		P.Caps.client = 'retail'
		local retailDelve
		for _, choice in ipairs(WB:Choices('layout')) do
			if choice.key == 'place:delve' then
				retailDelve = choice
			end
		end
		assert.is_true(retailDelve.available)
		P.Caps.client = saved
	end)

	it('describes a condition the catalog no longer has', function()
		local choice = WB:ChoiceFor({ id = 'gone', args = 'x' })
		assert.is_false(choice.available)
		assert.truthy(choice.label:find('gone', 1, true))
		local problems = WB:Problems({ conditions = { { id = 'gone' } }, mode = 'hidden' }, 'layout')
		assert.truthy(#problems >= 1)
		assert.is_false(Situation.EntryApplies({ conditions = { { id = 'gone' } }, mode = 'hidden' }, 'enemyNPC', Env()), 'it never matches')
	end)
end)

describe('when builder: only actions that can work are offered', function()
	it('offers every layout action for plain conditions', function()
		local ids = Ids(WB:Actions('layout', { { id = 'place', args = 'raid' }, { id = 'role', args = 'tank' } }))
		assert.same(ids, { 'style', 'size', 'name', 'hide' })
	end)

	it('offers every layout action while no condition is picked', function()
		assert.same(Ids(WB:Actions('layout', {})), { 'style', 'size', 'name', 'hide' })
		assert.same(Ids(WB:Actions('layout', nil)), { 'style', 'size', 'name', 'hide' })
	end)

	it('offers nothing for a condition the catalog does not have', function()
		assert.same(Ids(WB:Actions('layout', { { id = 'gone' } })), {})
	end)

	it('takes the actions every chosen condition allows', function()
		WB:RegisterAction({
			id = 'testFade',
			label = 'Fade',
			order = 200,
			context = 'emphasis',
			needs = 'alpha',
			Active = function(entry)
				return entry.alpha ~= nil
			end,
			Start = function(entry)
				entry.alpha = 0.5
			end,
			Clear = function(entry)
				entry.alpha = nil
			end,
			Describe = function(entry)
				return 'fade to ' .. entry.alpha
			end,
		})
		WB:RegisterAction({
			id = 'testHideBoth',
			label = 'Hide it',
			order = 201,
			context = 'emphasis',
			needs = 'hide',
			Active = function(entry)
				return entry.testHide == true
			end,
			Start = function(entry)
				entry.testHide = true
			end,
			Clear = function(entry)
				entry.testHide = nil
			end,
			Describe = function()
				return 'hide it'
			end,
		})
		local engine = { { id = 'notInterruptible' } }
		local plain = { { id = 'place', args = 'raid' } }
		local secrets = P.Caps:Get('secrets')
		local withEngine = Ids(WB:Actions('emphasis', engine))
		assert.is_true(Has(withEngine, 'testFade'), 'fading always works')
		assert.equal(Has(withEngine, 'testHideBoth'), not secrets, 'hiding needs a plain answer')
		local withPlain = Ids(WB:Actions('emphasis', plain))
		assert.is_true(Has(withPlain, 'testFade') and Has(withPlain, 'testHideBoth'))
		local mixed = Ids(WB:Actions('emphasis', { plain[1], engine[1] }))
		assert.equal(Has(mixed, 'testHideBoth'), not secrets, 'one engine condition limits the whole entry')
		assert.is_false(Has(Ids(WB:Actions('layout', plain)), 'testFade'), 'emphasis actions stay out of the layout list')
		assert.is_false(Has(Ids(WB:Actions('layout', plain)), 'testHideBoth'))
	end)

	it('explains the limit with a client badge', function()
		local text = WB:Badge({ { id = 'notInterruptible' } })
		assert.not_nil(text)
		if P.Caps:Get('secrets') then
			assert.truthy(text:find('On this version of WoW', 1, true), text)
		else
			assert.truthy(text:find('On Retail and Forever', 1, true), text)
		end
		assert.truthy(text:find('color or fade', 1, true))
		assert.is_nil(WB:Badge({ { id = 'place', args = 'raid' } }), 'plain conditions have nothing to warn about')
	end)

	it('says when an entry holds an action its conditions cannot do', function()
		local entry = { conditions = { { id = 'notInterruptible' } }, testHide = true }
		local problems = WB:Problems(entry, 'emphasis')
		assert.equal(#problems > 0, P.Caps:Get('secrets'))
		local layoutProblems = WB:Problems({ conditions = entry.conditions, mode = 'hidden' }, 'layout')
		assert.truthy(#layoutProblems > 0, 'the layout cannot wait for a hidden answer on any client')
	end)

	it('rejects an action without the pieces it needs', function()
		assert.errors(function()
			WB:RegisterAction({ id = 'broken' })
		end, 'RegisterAction needs')
	end)
end)

describe('when builder: actions change the right fields', function()
	it('reads the action out of an entry', function()
		assert.equal(WB:ActionOf({ style = 'clean' }, 'layout').id, 'style')
		assert.equal(WB:ActionOf({ style = 'clean', size = 'small' }, 'layout').id, 'style')
		assert.equal(WB:ActionOf({ size = 'large' }, 'layout').id, 'size')
		assert.equal(WB:ActionOf({ mode = 'name' }, 'layout').id, 'name')
		assert.equal(WB:ActionOf({ mode = 'hidden' }, 'layout').id, 'hide')
		assert.equal(WB:ActionOf({ mode = 'name', style = 'clean' }, 'layout').id, 'name', 'names only wins like in Assign')
		assert.is_nil(WB:ActionOf({}, 'layout'))
	end)

	it('switches action and clears the old fields', function()
		local entry = { conditions = {}, style = 'clean', size = 'small' }
		WB:SetAction(entry, 'hide', 'layout')
		assert.same({ entry.mode, entry.style, entry.size }, { 'hidden' })
		WB:SetAction(entry, 'name', 'layout')
		assert.equal(entry.mode, 'name')
		WB:SetAction(entry, 'size', 'layout')
		assert.is_nil(entry.mode)
		assert.equal(entry.size, 'small')
		WB:SetAction(entry, 'style', 'layout')
		assert.is_nil(entry.mode)
		assert.is_nil(entry.size)
		assert.equal(entry.style, 'host', 'the style the plates use now')
		Store:Set('style', 'clean')
		WB:SetAction(entry, 'hide', 'layout')
		WB:SetAction(entry, 'style', 'layout')
		assert.equal(entry.style, 'clean')
		Store:Reset('style')
	end)

	it('keeps an entry when the same action is picked again', function()
		local entry = { style = 'mini', size = 'large' }
		WB:SetAction(entry, 'style', 'layout')
		assert.equal(entry.style, 'mini')
		assert.equal(entry.size, 'large')
	end)

	it('says what each action does in a phrase and in two words', function()
		local cases = {
			{ { style = 'clean' }, 'use Clean', 'Clean' },
			{ { style = 'clean', size = 'small' }, 'use Clean at small size', 'Clean, small' },
			{ { size = 'large' }, 'use large size', 'Large size' },
			{ { mode = 'name' }, 'show names only', 'Names only' },
			{ { mode = 'hidden' }, 'hide the plate', 'Hidden' },
		}
		for _, case in ipairs(cases) do
			assert.equal(WB:ActionText(case[1], 'layout'), case[2])
			assert.equal(WB:Short(case[1], 'layout'), case[3])
		end
		assert.equal(WB:Short({}, 'layout'), '-')
		assert.is_nil(WB:ActionText({}, 'layout'))
	end)

	it('writes entries Situation.Assign understands', function()
		local settings = { style = 'clean', size = 'medium', when = {} }
		local out = {}
		local cases = {
			{ { style = 'mini' }, 'mini', 'full', 'medium' },
			{ { style = 'mini', size = 'small' }, 'mini', 'full', 'small' },
			{ { size = 'large' }, 'clean', 'full', 'large' },
			{ { mode = 'name' }, Situation.NAME_STYLE, 'name', 'medium' },
			{ { mode = 'hidden' }, 'clean', 'hidden', 'medium' },
		}
		for _, case in ipairs(cases) do
			local entry = { conditions = { { id = 'place', args = 'raid' } } }
			for k, v in pairs(case[1]) do
				entry[k] = v
			end
			settings.when = { entry }
			Situation.Assign('enemyNPC', Env({}, { place = 'raid' }), settings, out)
			assert.same({ out.style, out.mode, out.size }, { case[2], case[3], case[4] })
		end
	end)
end)

describe('when builder: words', function()
	local function Entry(conditions, extra)
		local entry = { conditions = {} }
		for i, key in ipairs(conditions) do
			entry.conditions[i] = WB:ClauseForKey(key)
		end
		for k, v in pairs(extra or {}) do
			entry[k] = v
		end
		return entry
	end

	it('writes the conditions in plain words', function()
		assert.equal(WB:Sentence(Entry({})), 'Always')
		assert.equal(WB:Sentence(Entry({ 'place:raid' })), 'In a raid')
		assert.equal(WB:Sentence(Entry({ 'place:raid', 'role:tank' })), 'In a raid and as a tank')
		assert.equal(WB:Sentence(Entry({ '!myCombat' })), 'Out of combat')
		assert.equal(WB:Sentence(Entry({ 'elite' })), 'For elite plates')
		assert.equal(WB:Sentence(Entry({ 'place:raid', 'elite' })), 'In a raid, for elite plates')
		assert.equal(WB:Sentence(Entry({ 'elite', 'place:raid', 'canAttack' })), 'In a raid, for elite plates and plates you can attack')
	end)

	it('names the kinds an entry covers', function()
		assert.equal(WB:Sentence(Entry({ 'place:raid' }, { kinds = { 'minor' } })), 'In a raid - Minor enemies only')
		assert.equal(WB:Sentence(Entry({ 'place:raid' }, { kinds = { 'minor', 'enemyNPC' } })), 'In a raid - Enemy NPCs and Minor enemies only')
		assert.equal(WB:Sentence(Entry({ 'place:raid' }, { kinds = { 'enemyNPC', 'enemyPlayer', 'friendlyNPC', 'friendlyPlayer', 'minor' } })), 'In a raid', 'all of them is the same as none')
		assert.is_nil(WB:KindsText(nil))
	end)

	it('puts the sentence and the action together', function()
		local entry = Entry({ 'place:raid', 'role:tank' }, { style = 'clean', size = 'small' })
		assert.equal(WB:Describe(entry, 'layout'), 'In a raid and as a tank: use Clean at small size')
		assert.equal(WB:Describe(Entry({ 'place:raid' }), 'layout'), 'In a raid: nothing yet')
	end)

	it('uses the name of the style the plates use for the host look', function()
		assert.equal(WB.StyleName('host'), WB.StyleName(P.Styles.Registry:ResolveId('host')))
		assert.equal(WB.StyleName('clean'), 'Clean')
		assert.equal(WB.StyleName('unknown-style'), 'Clean', 'an unknown id falls back like the registry')
	end)

	it('lists problems in plain sentences', function()
		assert.same(WB:Problems(Entry({ 'place:raid' }, { style = 'clean' }), 'layout'), {})
		assert.equal(WB:Problems(Entry({ 'place:raid' }), 'layout')[1], 'Pick what should happen.')
		local contradiction = WB:Problems(Entry({ 'place:raid', 'place:dungeon' }, { mode = 'hidden' }), 'layout')
		assert.same(contradiction, { 'These conditions can never be true together.' })
		assert.same(WB:Problems(Entry({ 'place:raid', 'place:instance' }, { mode = 'hidden' }), 'layout'), {}, 'a broad place can go with a narrow one')
		assert.same(WB:Problems(Entry({ '!myCombat', 'myCombat' }, { mode = 'hidden' }), 'layout'), { 'These conditions can never be true together.' })
		assert.same(WB:Problems(Entry({ 'place:raid' }, { mode = 'hidden', kinds = {} }), 'layout'), { 'No kinds of plates are picked.' })
	end)
end)

describe('when builder: templates', function()
	it('has the launch templates', function()
		local ids = Ids(WB:Templates('layout'))
		for _, id in ipairs({ 'raidSmall', 'raidMinor', 'battlegroundNames', 'tankLarge', 'blank' }) do
			assert.truthy(Has(ids, id), id)
		end
	end)

	it('makes entries without problems that say something', function()
		for _, template in ipairs(WB:Templates('layout')) do
			local entry = WB:NewEntry(template.id)
			assert.not_nil(entry, template.id)
			assert.same(WB:Problems(entry, 'layout'), {}, template.id)
			assert.truthy(template.label ~= '')
		end
	end)

	it('hands out copies', function()
		local first = WB:NewEntry('raidSmall')
		first.size = 'large'
		first.conditions[1].args = 'dungeon'
		local second = WB:NewEntry('raidSmall')
		assert.equal(second.size, 'small')
		assert.equal(second.conditions[1].args, 'raid')
		assert.is_nil(WB:NewEntry('nothing'))
	end)

	it('changes plates only where it says', function()
		local settings = { style = 'clean', size = 'medium', when = {} }
		local out = {}
		local function Assign(templateId, kind, ctx)
			settings.when = { WB:NewEntry(templateId) }
			return Situation.Assign(kind, Env({}, ctx), settings, out)
		end
		assert.equal(Assign('raidSmall', 'enemyNPC', { place = 'raid' }).size, 'small')
		assert.equal(Assign('raidSmall', 'enemyNPC', { place = 'world' }).size, 'medium')
		assert.equal(Assign('raidMinor', 'minor', { place = 'raid' }).mode, 'hidden')
		assert.equal(Assign('raidMinor', 'enemyNPC', { place = 'raid' }).mode, 'full', 'only minor enemies')
		assert.equal(Assign('raidMinor', 'minor', { place = 'world' }).mode, 'full')
		local names = Assign('battlegroundNames', 'enemyPlayer', { place = 'battleground' })
		assert.same({ names.mode, names.style }, { 'name', Situation.NAME_STYLE })
		assert.equal(Assign('tankLarge', 'enemyNPC', { role = 'tank' }).size, 'large')
		assert.equal(Assign('tankLarge', 'enemyNPC', { role = 'damage' }).size, 'medium')
		local blank = Assign('blank', 'enemyNPC', { place = 'dungeon' })
		assert.same({ blank.style, blank.size, blank.mode }, { 'host', 'medium', 'full' }, 'a new blank case changes nothing yet')
	end)

	it('can be added to', function()
		WB:RegisterTemplate({
			id = 'testTemplate',
			label = 'Test template',
			order = 5,
			context = 'layout',
			entry = function()
				return { conditions = { { id = 'inGroup' } }, mode = 'name' }
			end,
		})
		local list = WB:Templates('layout')
		assert.equal(list[1].id, 'testTemplate', 'ordered by order')
		assert.equal(WB:NewEntry('testTemplate').mode, 'name')
		assert.is_false(Has(Ids(WB:Templates('emphasis')), 'raidSmall'), 'layout templates stay out of the emphasis list')
		assert.errors(function()
			WB:RegisterTemplate({ id = 'broken' })
		end, 'RegisterTemplate needs')
	end)
end)

---Walk an AceConfig group and check every control the way the dialog reads it.
local function CheckTable(group, path, seen)
	seen = seen or { controls = 0 }
	path = path or 'root'
	assert.equal(group.type, 'group', path)
	for key, option in pairs(group.args or {}) do
		local where = path .. '.' .. key
		assert.truthy(option.type ~= nil, where .. ' has a type')
		if option.type == 'group' then
			CheckTable(option, where, seen)
		else
			seen.controls = seen.controls + 1
			if type(option.name) == 'function' then
				assert.equal(type(option.name()), 'string', where .. ' name')
			end
			if type(option.hidden) == 'function' then
				option.hidden({})
			end
			if type(option.disabled) == 'function' then
				option.disabled({})
			end
			if option.type == 'select' or option.type == 'multiselect' then
				local values = type(option.values) == 'function' and option.values({}) or option.values
				assert.equal(type(values), 'table', where .. ' values')
				if option.sorting ~= nil then
					local sorting = type(option.sorting) == 'function' and option.sorting({}) or option.sorting
					assert.equal(type(sorting), 'table', where .. ' sorting')
					local inSorting = {}
					for _, key2 in ipairs(sorting) do
						inSorting[key2] = true
						assert.not_nil(values[key2], where .. ' sorting names ' .. tostring(key2) .. ' which has no value')
					end
					for key2 in pairs(values) do
						assert.truthy(inSorting[key2], where .. ' value ' .. tostring(key2) .. ' is missing from sorting')
					end
				end
			end
		end
	end
	return seen
end

describe('when builder: the editor group', function()
	local entry
	local done
	local group

	local function Build(extra)
		local opts = {
			get = function()
				return entry and P.util.Copy(entry) or nil
			end,
			set = function(value)
				entry = P.util.Copy(value)
			end,
			onDone = function()
				done = true
			end,
		}
		for k, v in pairs(extra or {}) do
			opts[k] = v
		end
		return WB:Group(opts), opts
	end

	before_each(function()
		entry = { conditions = { { id = 'place', args = 'raid' }, { id = 'role', args = 'tank' } }, style = 'clean' }
		done = false
		group = Build()
	end)

	it('is an inline group that hides with no entry', function()
		assert.equal(group.type, 'group')
		assert.is_true(group.inline)
		assert.is_false(group.hidden())
		entry = nil
		assert.is_true(group.hidden())
		for key, option in pairs(group.args) do
			if option.hidden then
				assert.is_true(option.hidden({}), key .. ' hides too')
			end
		end
	end)

	it('hides the group while the page says so', function()
		local hidden = true
		local g = Build({
			hidden = function()
				return hidden
			end,
		})
		assert.is_true(g.hidden())
		hidden = false
		assert.is_false(g.hidden())
	end)

	it('reads every control without error for a spread of entries', function()
		local entries = {
			{ conditions = {}, mode = 'hidden' },
			{ conditions = { { id = 'place', args = 'raid' } }, mode = 'name', kinds = { 'minor' } },
			{ conditions = { { id = 'place', args = 'raid' }, { id = 'role', args = 'tank' }, { id = 'elite' }, { id = '!', negate = true } }, size = 'large' },
			{ conditions = { { id = 'gone' } } },
			{ conditions = { { id = 'notInterruptible' } }, mode = 'hidden' },
			{},
		}
		for index, value in ipairs(entries) do
			entry = value
			CheckTable(group, 'entry' .. index)
		end
	end)

	it('shows a box per condition and one empty box to add the next', function()
		local function Visible()
			local out = {}
			for i = 1, WB.MAX_CONDITIONS do
				out[i] = not group.args.conditions.args['condition' .. i].hidden({})
			end
			return out
		end
		assert.same(Visible(), { true, true, true, false })
		entry.conditions = {}
		assert.same(Visible(), { true, false, false, false })
		entry.conditions = { { id = 'place', args = 'raid' }, { id = 'role', args = 'tank' }, { id = 'elite' }, { id = 'canAttack' } }
		assert.same(Visible(), { true, true, true, true })
		assert.is_nil(group.args.conditions.args['condition' .. (WB.MAX_CONDITIONS + 1)])
	end)

	it('lists what is left for a box and lets a box remove its condition', function()
		local second = group.args.conditions.args.condition2
		local values = second.values({})
		assert.equal(values['role:tank'], 'As a tank', 'its own choice stays')
		assert.is_nil(values['place:raid'], 'the other box already uses this one')
		assert.not_nil(values['role:healer'])
		assert.not_nil(values.remove)
		assert.is_nil(values.add)
		assert.equal(second.get({}), 'role:tank')
		local empty = group.args.conditions.args.condition3
		local emptyValues = empty.values({})
		assert.not_nil(emptyValues.add)
		assert.is_nil(emptyValues.remove)
		assert.is_nil(emptyValues['place:raid'])
		assert.is_nil(emptyValues['role:tank'])
		assert.equal(empty.get({}), 'add')
		assert.equal(emptyValues['place:delve'] ~= nil, P.Caps:Client() == 'retail' or P.Caps:Client() == 'forever' or P.Caps:Client() == 'unknown', 'a delve is only offered where it exists')
	end)

	it('changes, adds and removes conditions through set', function()
		group.args.conditions.args.condition1.set({}, 'place:dungeon')
		assert.equal(entry.conditions[1].args, 'dungeon')
		assert.equal(#entry.conditions, 2)
		group.args.conditions.args.condition3.set({}, '!myCombat')
		assert.equal(#entry.conditions, 3)
		assert.same(entry.conditions[3], { id = 'myCombat', negate = true })
		group.args.conditions.args.condition3.set({}, 'add')
		assert.equal(#entry.conditions, 3, 'the empty choice changes nothing')
		group.args.conditions.args.condition2.set({}, 'remove')
		assert.equal(#entry.conditions, 2)
		assert.equal(entry.conditions[2].id, 'myCombat', 'the list closes up')
		group.args.conditions.args.condition1.set({}, 'remove')
		group.args.conditions.args.condition1.set({}, 'remove')
		assert.same(entry.conditions, {})
		assert.equal(entry.style, 'clean', 'the action stays')
	end)

	it('offers only the actions that can work', function()
		local action = group.args.thenGroup.args.action
		local values = action.values({})
		assert.same(Sorted(values), { 'hide', 'name', 'size', 'style' })
		assert.is_nil(values.none)
		assert.same(action.sorting({}), { 'style', 'size', 'name', 'hide' })
		assert.equal(action.get({}), 'style')
		entry = { conditions = { { id = 'place', args = 'raid' } } }
		assert.equal(action.get({}), 'none', 'no action yet')
		assert.not_nil(action.values({}).none)
		entry = { conditions = { { id = 'notInterruptible' } }, mode = 'hidden' }
		if P.Caps:Get('secrets') then
			assert.equal(action.values({}).hide, 'Hide the plate (cannot work here)', 'the entry keeps its action, flagged')
		end
	end)

	it('switches the action and shows the controls that belong to it', function()
		local function Shown()
			local out = {}
			for key, option in pairs(group.args.thenGroup.args) do
				if key:find('^action_') and not option.hidden({}) then
					out[#out + 1] = key
				end
			end
			table.sort(out)
			return out
		end
		assert.same(Shown(), { 'action_style_size', 'action_style_style' })
		group.args.thenGroup.args.action.set({}, 'size')
		assert.equal(entry.size, 'small')
		assert.is_nil(entry.style)
		assert.same(Shown(), { 'action_size_size' })
		group.args.thenGroup.args.action.set({}, 'name')
		assert.equal(entry.mode, 'name')
		assert.same(Shown(), {})
		group.args.thenGroup.args.action.set({}, 'hide')
		assert.equal(entry.mode, 'hidden')
		group.args.thenGroup.args.action.set({}, 'none')
		assert.equal(entry.mode, 'hidden', 'the placeholder is not an action')
		group.args.thenGroup.args.action.set({}, 'style')
		assert.equal(entry.style, 'host')
		assert.is_nil(entry.mode)
	end)

	it('picks a style and a size', function()
		local style = group.args.thenGroup.args.action_style_style
		local values = style.values({})
		assert.equal(values.clean, 'Clean')
		assert.equal(values.mini, 'Mini', 'minor enemies use it')
		assert.is_nil(values.namesOnly, 'names only is a Show choice')
		assert.equal(style.get({}), 'clean')
		style.set({}, 'mini')
		assert.equal(entry.style, 'mini')
		local size = group.args.thenGroup.args.action_style_size
		assert.equal(size.get({}), 'keep')
		size.set({}, 'large')
		assert.equal(entry.size, 'large')
		assert.equal(size.get({}), 'large')
		size.set({}, 'keep')
		assert.is_nil(entry.size)
		entry = { conditions = {}, size = 'medium' }
		local plain = group.args.thenGroup.args.action_size_size
		assert.equal(plain.get({}), 'medium')
		plain.set({}, 'small')
		assert.equal(entry.size, 'small')
		entry = { conditions = {}, style = 'saved1' }
		assert.equal(style.values({}).saved1, WB.StyleName('saved1'), 'a style that is gone is still shown')
	end)

	it('covers every kind unless some are unchecked', function()
		local kinds = group.args.kinds
		for _, kind in ipairs(Situation.KINDS) do
			assert.is_true(kinds.get({}, kind), kind)
		end
		kinds.set({}, 'minor', false)
		assert.same(entry.kinds, { 'enemyNPC', 'enemyPlayer', 'friendlyNPC', 'friendlyPlayer' })
		assert.is_false(kinds.get({}, 'minor'))
		assert.is_true(kinds.get({}, 'enemyNPC'))
		kinds.set({}, 'minor', true)
		assert.is_nil(entry.kinds, 'all of them is stored as none')
		entry.kinds = { 'minor' }
		kinds.set({}, 'minor', false)
		assert.same(entry.kinds, { 'minor' }, 'at least one kind stays')
		kinds.set({}, 'enemyNPC', true)
		assert.same(entry.kinds, { 'enemyNPC', 'minor' }, 'kept in the usual order')
	end)

	it('can leave out "Applies to"', function()
		local g = Build({ kinds = false })
		assert.is_nil(g.args.kinds)
	end)

	it('writes the sentence, the badge and the problems as they change', function()
		assert.equal(group.args.sentence.name(), 'In a raid and as a tank: use Clean')
		assert.is_true(group.args.badge.hidden({}))
		assert.is_true(group.args.problems.hidden({}))
		entry = { conditions = { { id = 'place', args = 'raid' }, { id = 'place', args = 'dungeon' } } }
		assert.is_false(group.args.problems.hidden({}))
		assert.truthy(group.args.problems.name():find('Pick what should happen.', 1, true))
		assert.truthy(group.args.problems.name():find('never be true together', 1, true))
		entry = { conditions = { { id = 'notInterruptible' } }, mode = 'hidden' }
		assert.is_false(group.args.badge.hidden({}))
		assert.truthy(group.args.badge.name():find('color or fade', 1, true))
	end)

	it('has a Done button only when asked, and it calls back', function()
		group.args.done.func()
		assert.is_true(done)
		local g = Build({ onDone = false })
		assert.is_nil(g.args.done)
	end)

	it('disables every control while the page says so', function()
		local locked = true
		local g = Build({
			disabled = function()
				return locked
			end,
		})
		local count = 0
		local function Each(group, fn)
			for key, option in pairs(group.args) do
				if option.type == 'group' then
					Each(option, fn)
				else
					fn(key, option)
				end
			end
		end
		Each(g, function(key, option)
			if option.type == 'select' or option.type == 'multiselect' then
				count = count + 1
				assert.is_true(option.disabled({}), key)
			end
		end)
		assert.truthy(count >= 5)
		locked = false
		Each(g, function(_, option)
			if option.type == 'select' and not (option.hidden and option.hidden({})) then
				assert.is_false(option.disabled({}))
			end
		end)
	end)

	it('reads and writes the entry fresh on every call', function()
		local reads = 0
		local g = Build({
			get = function()
				reads = reads + 1
				return { conditions = { { id = 'place', args = 'raid' } }, style = 'clean' }
			end,
		})
		local before = reads
		g.args.conditions.args.condition1.get({})
		g.args.conditions.args.condition1.get({})
		assert.truthy(reads >= before + 2)
	end)
end)

describe('when builder: safe edits and later actions', function()
	local B, C
	before_each(function()
		local fresh = H.FreshCore()
		B, C = fresh.WhenBuilder, fresh.Conditions
	end)

	local function ExtraAction(extra)
		local def = {
			id = 'fadeLater',
			label = 'Fade plates',
			context = 'emphasis',
			needs = 'alpha',
			Active = function(entry)
				return entry.alpha ~= nil
			end,
			Start = function(entry)
				entry.alpha = 0.5
			end,
			Clear = function(entry)
				entry.alpha = nil
			end,
			Describe = function()
				return 'fade plates'
			end,
			Controls = function(ctx)
				return {
					strength = {
						type = 'range',
						name = 'Fade',
						min = 0,
						max = 1,
						disabled = false,
						get = function()
							return ctx.get().alpha
						end,
						set = function(_, value)
							ctx.update(function(entry)
								entry.alpha = value
							end)
						end,
					},
				}
			end,
		}
		for key, value in pairs(extra or {}) do
			def[key] = value
		end
		B:RegisterAction(def)
		return def
	end

	it('keeps catalog replacements fresh even when the number of conditions stays the same', function()
		C:Register({
			id = 'laterCondition',
			kind = 'plain',
			label = 'First words',
			Test = function()
				return true
			end,
		})
		local clause = { id = 'laterCondition' }
		assert.equal(B:ChoiceFor(clause).label, 'First words')
		C:Register({
			id = 'laterCondition',
			kind = 'plain',
			label = 'New words',
			Test = function()
				return true
			end,
		})
		assert.equal(B:ChoiceFor(clause).label, 'New words')
	end)

	it('offers no layout actions for engine or state conditions on any client', function()
		assert.same(B:Actions('layout', { { id = 'notInterruptible' } }), {})
		assert.same(B:Actions('layout', { { id = 'target' } }), {})
		assert.same(B:Actions('layout', { { id = 'gone' } }), {})
	end)

	it('keeps an action intact when a callback asks for one that cannot work', function()
		local entry = { conditions = { { id = 'notInterruptible' } }, mode = 'name' }
		B:SetAction(entry, 'hide', 'layout')
		assert.equal(entry.mode, 'name')
		entry.conditions = {}
		B:SetAction(entry, 'gone', 'layout')
		assert.equal(entry.mode, 'name')
		ExtraAction()
		B:SetAction(entry, 'fadeLater', 'layout')
		assert.equal(entry.mode, 'name')
		assert.is_nil(entry.alpha)
	end)

	it('lets later actions supply capability checks, controls and client badges', function()
		local ready = true
		ExtraAction({
			Available = function()
				return ready
			end,
			limits = { [P.Caps:Client()] = 'Only enemy plates here' },
		})
		local entry = { conditions = { { id = 'notInterruptible' } } }
		local g = B:Group({
			context = 'emphasis',
			kinds = false,
			get = function()
				return entry
			end,
			set = function(value)
				entry = value
			end,
		})
		assert.equal(g.args.thenGroup.args.action.values().fadeLater, 'Fade plates (Only enemy plates here)')
		g.args.thenGroup.args.action.set({}, 'fadeLater')
		assert.equal(entry.alpha, 0.5)
		assert.truthy(g.args.badge.name():find('Only enemy plates here', 1, true))
		g.args.thenGroup.args.action_fadeLater_strength.set({}, 0.2)
		assert.equal(entry.alpha, 0.2)
		ready = false
		assert.equal(g.args.thenGroup.args.action.values().fadeLater, 'Fade plates (cannot work here)')
		assert.truthy(#B:Problems(entry, 'emphasis') > 0)
		local strength = g.args.thenGroup.args.action_fadeLater_strength
		assert.is_true(strength.disabled())
		strength.set({}, 0.9)
		assert.equal(entry.alpha, 0.2, 'a stale control cannot change an action that no longer works')
	end)

	it('honors the parent lock even when an action control supplies disabled false', function()
		ExtraAction()
		local locked, writes = false, 0
		local entry = { conditions = {}, alpha = 0.5 }
		local g = B:Group({
			context = 'emphasis',
			get = function()
				return entry
			end,
			set = function(value)
				writes = writes + 1
				entry = value
			end,
			disabled = function()
				return locked
			end,
		})
		local strength = g.args.thenGroup.args.action_fadeLater_strength
		assert.is_false(strength.disabled())
		locked = true
		assert.is_true(strength.disabled())
		strength.set({}, 0.2)
		g.args.conditions.args.condition1.set({}, 'place:raid')
		g.args.thenGroup.args.action.set({}, 'fadeLater')
		g.args.kinds.set({}, 'minor', false)
		assert.equal(writes, 0)
		assert.equal(entry.alpha, 0.5)
		assert.same(entry.conditions, {})
	end)

	it('does not change the object supplied by the reader before it is stored', function()
		local original = { conditions = {}, mode = 'name' }
		local stored
		local g = B:Group({
			get = function()
				return original
			end,
			set = function(entry)
				stored = entry
			end,
		})
		g.args.conditions.args.condition1.set({}, 'place:raid')
		assert.same(original.conditions, {})
		assert.equal(stored.conditions[1].args, 'raid')
	end)

	it('lets players remove every imported condition past the normal four', function()
		local entry = {
			conditions = {
				{ id = 'place', args = 'raid' },
				{ id = 'role', args = 'tank' },
				{ id = 'elite' },
				{ id = 'canAttack' },
				{ id = 'inGroup' },
				{ id = 'myCombat' },
			},
			mode = 'name',
		}
		local g = B:Group({
			get = function()
				return entry
			end,
			set = function(value)
				entry = value
			end,
		})
		assert.not_nil(g.args.conditions.args.condition6)
		assert.is_true(g.args.conditions.args.condition6.advanced)
		g.args.conditions.args.condition6.set({}, 'remove')
		assert.equal(#entry.conditions, 5)
		g.args.conditions.args.condition5.set({}, 'remove')
		assert.equal(#entry.conditions, 4)
		assert.equal(entry.mode, 'name')
	end)

	it('rejects stale unavailable or duplicate condition choices', function()
		local entry = { conditions = { { id = 'place', args = 'raid' } }, mode = 'name' }
		local g = B:Group({
			get = function()
				return entry
			end,
			set = function(value)
				entry = value
			end,
		})
		g.args.conditions.args.condition2.set({}, 'place:raid')
		assert.equal(#entry.conditions, 1)
		g.args.conditions.args.condition2.set({}, 'notInterruptible')
		assert.equal(#entry.conditions, 1)
	end)

	it('warns when broad places and negations make a case impossible', function()
		for _, conditions in ipairs({
			{ { id = 'place', args = 'world' }, { id = 'place', args = 'instance' } },
			{ { id = 'place', args = 'raid' }, { id = 'place', args = 'pvp' } },
			{ { id = 'place', args = 'raid' }, { id = 'place', args = 'instance', negate = true } },
			{ { id = 'myCombat' }, { id = 'myCombat', negate = true } },
		}) do
			assert.contains(B:Problems({ conditions = conditions, mode = 'hidden' }, 'layout'), 'These conditions can never be true together.')
		end
		assert.same(
			B:Problems({ conditions = { { id = 'place', args = 'arena' }, { id = 'place', args = 'pvp' } }, mode = 'hidden' }, 'layout'),
			P.Caps:Client() == 'era' and { 'These conditions cannot do that on this version of WoW.', '"In an arena" does not happen on this version of WoW.' } or {}
		)
	end)
end)
