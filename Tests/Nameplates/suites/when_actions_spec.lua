-- @runtime lua51
-- "When" actions (Phase 8, plan 3.5, 6.4): the compiler turns profile.actions into rules on the
-- condition catalog, every condition and action pair the builder offers runs under the strict
-- secret mock (Retail and Forever restricted, plain on the Classic family), answers the game hides
-- reach only sinks, the plate listens to exactly the events and messages the rules declare (no
-- per-frame work), templates are ready to use, and actions survive a "When" share string while
-- entries from a newer version are refused.
local M, H = ...
local S = M.S

if not H.ModuleExists() then
	describe('when actions', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

-- The mock client has no codec: a plain stand-in for C_EncodingUtil (as in share_spec)
local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local B64INDEX = {}
for i = 1, #B64 do
	B64INDEX[B64:sub(i, i)] = i - 1
end
local function Serialize(v)
	local t = type(v)
	if t == 'string' then
		return string.format('%q', v)
	elseif t == 'number' then
		return string.format('%.17g', v)
	elseif t == 'boolean' then
		return tostring(v)
	end
	local parts = {}
	for k, item in pairs(v) do
		parts[#parts + 1] = '[' .. Serialize(k) .. ']=' .. Serialize(item)
	end
	return '{' .. table.concat(parts, ',') .. '}'
end
local function EncodeBase64(data)
	local out = {}
	for i = 1, #data, 3 do
		local a, b, c = data:byte(i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local d1, d2, d3, d4 = math.floor(n / 262144) % 64, math.floor(n / 4096) % 64, math.floor(n / 64) % 64, n % 64
		out[#out + 1] = B64:sub(d1 + 1, d1 + 1) .. B64:sub(d2 + 1, d2 + 1) .. (b and B64:sub(d3 + 1, d3 + 1) or '=') .. (c and B64:sub(d4 + 1, d4 + 1) or '=')
	end
	return table.concat(out)
end
local function DecodeBase64(text)
	local out = {}
	for i = 1, #text, 4 do
		local n, pad = 0, 0
		for j = 0, 3 do
			local ch = text:sub(i + j, i + j)
			if ch == '=' then
				pad = pad + 1
				n = n * 64
			else
				n = n * 64 + B64INDEX[ch]
			end
		end
		out[#out + 1] = string.char(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256):sub(1, 3 - pad)
	end
	return table.concat(out)
end
if not C_EncodingUtil then
	rawset(_G, 'C_EncodingUtil', {})
end
C_EncodingUtil.SerializeCBOR = Serialize
C_EncodingUtil.DeserializeCBOR = function(text)
	local chunk = assert(loadstring('return ' .. text))
	setfenv(chunk, {})
	return chunk()
end
C_EncodingUtil.CompressString = function(text)
	return text
end
C_EncodingUtil.DecompressString = function(text)
	return text
end
C_EncodingUtil.EncodeBase64 = EncodeBase64
C_EncodingUtil.DecodeBase64 = DecodeBase64

M.Login('NameplatesTestHost')
local P = H.FreshCore()
M.Login('NameplatesTestHost')
local Actions, WB, Conditions, Store = P.Actions, P.WhenBuilder, P.Conditions, P.Store
local secrets = P.Caps:Get('secrets') == true

local function Ctx(fields)
	local ctx = { place = 'world', inCombat = false, resting = false, role = 'damage', inGroup = false, groupSize = 1, playerLevel = 60, difficultyID = 0, tanks = {}, hasTarget = false }
	for k, v in pairs(fields or {}) do
		ctx[k] = v
	end
	return ctx
end

local tokenCount = 60
local plates = {}

local function LivePlate(unitSpec, kind, ctx)
	tokenCount = tokenCount + 1
	local token = 'nameplate' .. tokenCount
	local unit = M.AddUnit(unitSpec or { name = 'Gnoll', canAttack = true, reaction = 2, health = 80, healthMax = 100, inCombat = true })
	M.SetToken(token, unit)
	local plate = P.Plate.New(UIParent, false, ctx or Ctx())
	plate.situation = kind or 'enemyNPC'
	plate:ApplyStyle(P.Styles.Merge:Resolve('clean', plate.situation, 'medium'))
	local src = P.Source.NewLive(token)
	src:ReadFacts(plate.facts)
	plate:Bind(token, src)
	plates[#plates + 1] = plate
	return plate, unit, token
end

---Store a rules list and point every test plate at it.
local function Rules(list)
	Store:Set('actions', list)
	for _, plate in ipairs(plates) do
		if plate.src then
			Actions:Refresh(plate)
		end
	end
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

local function Clause(choice)
	local clause = { id = choice.id, args = choice.args, negate = choice.negate }
	if choice.picker == 'spellList' then
		clause.args = { [589] = 'any', [8921] = 'mine' }
	elseif choice.picker == 'npcList' then
		clause.args = { 1234, 5678 }
	end
	return clause
end

-- One entry per emphasis action, filled the way the builder starts it
local function EntryFor(actionId, clause)
	local entry = { conditions = { clause } }
	WB.actions[actionId].Start(entry)
	return entry
end

local EMPHASIS = { 'grow', 'paint', 'fade', 'glow', 'mark' }

local function Reset()
	Rules(nil)
	M.SetRestricted(false)
end

describe('when actions: the builder offers only what can work', function()
	before_each(Reset)
	it('registers the five emphasis actions in the emphasis context only', function()
		local emphasis = Ids(WB:ActionList('emphasis'))
		for _, id in ipairs(EMPHASIS) do
			assert.is_true(Has(emphasis, id), id .. ' is offered for rules')
			assert.is_false(Has(Ids(WB:ActionList('layout')), id), id .. ' stays out of special cases')
		end
	end)

	it('allows every action for plain conditions on every client', function()
		local ids = Ids(WB:Actions('emphasis', { { id = 'place', args = 'raid' }, { id = 'focus' } }))
		for _, id in ipairs(EMPHASIS) do
			assert.is_true(Has(ids, id), id)
		end
	end)

	it('keeps answers the game hides to color, fade, glow and marks', function()
		local ids = Ids(WB:Actions('emphasis', { { id = 'notInterruptible' } }))
		assert.equal(Has(ids, 'grow'), not secrets, 'size waits for a plain answer')
		for _, id in ipairs({ 'paint', 'fade', 'glow', 'mark' }) do
			assert.is_true(Has(ids, id), id)
		end
	end)

	it('lets low health only tint or mark where health can be hidden', function()
		local ids = Ids(WB:Actions('emphasis', { { id = 'lowHealth', args = 35 } }))
		assert.is_true(Has(ids, 'paint') and Has(ids, 'mark'))
		assert.equal(Has(ids, 'fade'), not secrets)
		assert.equal(Has(ids, 'glow'), not secrets)
	end)

	it('lets identity conditions do everything, since a hidden identity is simply no match', function()
		local ids = Ids(WB:Actions('emphasis', { { id = 'npcID', args = { 1 } } }))
		for _, id in ipairs(EMPHASIS) do
			assert.is_true(Has(ids, id), id)
		end
	end)

	it('offers the spell conditions with a picker, grayed out with a reason where auras are hidden', function()
		local _, byKey = WB:All()
		for _, key in ipairs({ 'auraPresent', 'auraMissing' }) do
			local choice = byKey[key]
			assert.not_nil(choice, key)
			assert.equal(choice.picker, 'spellList')
			assert.equal(choice.available, not secrets, key .. ' works where aura spell ids are readable')
			if secrets then
				assert.truthy(choice.reason and choice.reason:find('hides which spells', 1, true), choice.reason)
				assert.same(WB:Actions('emphasis', { { id = key, args = { [589] = 'any' } } }), {})
				local problems = WB:Problems({ conditions = { { id = key, args = { [589] = 'any' } } }, glow = { 1, 1, 1, 1 } }, 'emphasis')
				assert.truthy(#problems > 0)
			end
		end
		assert.equal(byKey.castSpell.picker, 'spellList')
		assert.equal(byKey.npcID.picker, 'npcList')
	end)

	it('asks for a spell when a picker list is empty', function()
		local problems = WB:Problems({ conditions = { { id = 'castSpell' } }, glow = { 1, 1, 1, 1 } }, 'emphasis')
		local text = table.concat(problems, ' ')
		assert.truthy(text:find('Pick at least one spell', 1, true), text)
	end)

	it('warns when a fade waits on two answers the game hides', function()
		local entry = { conditions = { { id = 'notInterruptible' }, { id = 'importantCast' } }, fade = 0.5 }
		local text = table.concat(WB:Problems(entry, 'emphasis'), ' ')
		assert.equal(text:find('only wait for one condition', 1, true) ~= nil, secrets, text)
	end)

	it('keeps the spell and state conditions out of special cases', function()
		local layout = {}
		for _, choice in ipairs(WB:Choices('layout')) do
			layout[choice.id] = true
		end
		for _, id in ipairs({ 'auraPresent', 'auraMissing', 'castSpell', 'npcID', 'lowHealth', 'target', 'casting', 'unitInCombat', 'totem' }) do
			assert.is_nil(layout[id], id)
		end
	end)

	it('ships every template the plan names, each ready to use here', function()
		local labels = {}
		for _, def in ipairs(WB:Templates('emphasis')) do
			labels[def.label] = def.id
		end
		for _, label in ipairs({ 'Make casters stand out', "Fade enemies I'm not fighting", 'Big plate for my focus', 'Warn when low on health', 'Mark totems' }) do
			assert.not_nil(labels[label], label)
		end
		local layoutLabels = {}
		for _, def in ipairs(WB:Templates('layout')) do
			layoutLabels[def.label] = true
		end
		assert.is_true(layoutLabels['Hide minor enemies in raids'], 'the layout template stays with special cases')
		for _, def in ipairs(WB:Templates('emphasis')) do
			local entry = WB:NewEntry(def.id)
			assert.same(WB:Problems(entry, 'emphasis'), {}, def.id)
			assert.not_nil(Actions:CleanEntry(entry), def.id .. ' is a valid rule')
		end
	end)
end)

describe('when actions: every condition and action pair', function()
	before_each(Reset)
	it('compiles exactly the pairs the builder offers and runs them under the strict mock', function()
		local plate = LivePlate()
		local tried, compiled = 0, 0
		for _, choice in ipairs(WB:Choices('emphasis')) do
			-- Places that never happen on this client just never match; skip them
			if choice.available or choice.reason then
				local clause = Clause(choice)
				local offered = Ids(WB:Actions('emphasis', { clause }))
				for _, actionId in ipairs(EMPHASIS) do
					local entry = EntryFor(actionId, clause)
					tried = tried + 1
					Rules({ entry })
					local program = Actions:Program()
					local works = Has(offered, actionId)
					assert.equal(#program.rules, works and 1 or 0, choice.key .. ' + ' .. actionId)
					if works then
						compiled = compiled + 1
					end
					for _, restricted in ipairs({ false, true }) do
						M.SetRestricted(restricted)
						assert.no_errors(function()
							Actions:Run(plate)
							plate:UpdateAll('FULL')
						end, choice.key .. ' + ' .. actionId)
					end
					M.SetRestricted(false)
				end
			end
		end
		assert.truthy(tried > 100, 'a real matrix: ' .. tried)
		assert.truthy(compiled > 0)
		assert.empty(Actions.warned, 'no rule failed to run')
	end)

	it('never lets a hidden answer reach a non-sink: drawing under restriction stays secret', function()
		if not secrets then
			skip('no secrets on this client')
		end
		local plate, unit = LivePlate()
		M.StartCast(unit, { name = 'Fireball', spellID = 133, notInterruptible = false, duration = 3 })
		plate:UpdateAll('FULL')
		M.SetRestricted(true)
		Rules({ { conditions = { { id = 'notInterruptible' } }, paint = 'health', color = { 1, 0, 0, 1 } } })
		local st = Actions:StateOf(plate)
		local vertex = M.Get(st.tint, 'vertex')
		assert.is_true(vertex.secret, 'the tint got the engine fold')
		M.SetRestricted(false)
	end)
end)

describe('when actions: what each action draws', function()
	before_each(Reset)
	it('grows the plate in whole pixels while it fits', function()
		local ctx = Ctx()
		local plate = LivePlate(nil, 'enemyNPC', ctx)
		local w0 = M.Get(plate.art, 'w')
		Rules({ { conditions = { { id = 'focus' } }, grow = { 24, 4 } } })
		assert.is_nil(plate.grows and plate.grows.actions)
		plate:SetState('focus', true)
		M.Advance(0.5)
		assert.equal(M.Get(plate.art, 'w'), w0 + 24)
		assert.equal(M.Get(plate.art, 'w') % 1, 0, 'whole pixels')
		plate:SetState('focus', false)
		M.Advance(0.5)
		assert.equal(M.Get(plate.art, 'w'), w0)
		assert.equal(#M.Calls(plate.art, 'SetScale'), 0, 'never scaled')
	end)

	it('fades with its own frame, plainly or through the engine', function()
		local plate, unit = LivePlate({ name = 'Calm', canAttack = true, reaction = 2, health = 80, healthMax = 100, inCombat = false })
		Rules({ { conditions = { { id = 'unitInCombat', negate = true } }, fade = 0.4 } })
		assert.near(M.Get(plate.fader, 'alpha'), 0.4, 1e-6)
		M.UpdateUnit(unit, { inCombat = true })
		plate:OnMessage('FACTS_POLLED')
		assert.near(M.Get(plate.fader, 'alpha'), 1, 1e-6)
		if secrets then
			Rules({ { conditions = { { id = 'notInterruptible' } }, fade = 0.4 } })
			M.StartCast(unit, { name = 'Shield Wall', spellID = 871, notInterruptible = true, duration = 3 })
			M.SetRestricted(true)
			Actions:Run(plate)
			assert.is_true(M.Get(plate.fader, 'alphaSecret'), 'the game decided the fade')
			assert.near(M.Get(plate.fader, 'alpha'), 0.4, 1e-6, 'and it holds')
			M.SetRestricted(false)
		end
	end)

	it('glows and marks, and takes them away', function()
		local plate = LivePlate()
		Rules({ { conditions = { { id = 'target' } }, glow = { 1, 0.6, 0.1, 1 } }, { conditions = { { id = 'target' } }, mark = 'skull' } })
		local st = Actions:StateOf(plate)
		assert.is_false(st.glow ~= nil and P.GlowLib.IsShown(st.glow))
		plate:SetState('target', true)
		assert.is_true(P.GlowLib.IsShown(st.glow))
		assert.equal(M.Get(st.marks[1], 'vertex')[4], 1)
		plate:SetState('target', false)
		assert.is_false(P.GlowLib.IsShown(st.glow))
		assert.equal(M.Get(st.marks[1], 'vertex')[4], 0)
		Rules(nil)
		assert.is_false(M.Get(st.marks[1], 'shown') == true)
	end)

	it('tints the health bar and the border, top rule first', function()
		local plate = LivePlate()
		Rules({
			{ conditions = { { id = 'target' } }, paint = 'health', color = { 0, 1, 0, 1 } },
			{ conditions = { { id = 'canAttack' } }, paint = 'health', color = { 1, 0, 0, 1 } },
			{ conditions = { { id = 'canAttack' } }, paint = 'border', color = { 0, 0, 1, 1 } },
		})
		local st = Actions:StateOf(plate)
		assert.same({ M.Get(st.tint, 'vertex')[1], M.Get(st.tint, 'vertex')[2] }, { 1, 0 }, 'the second rule fits')
		plate:SetState('target', true)
		assert.same({ M.Get(st.tint, 'vertex')[1], M.Get(st.tint, 'vertex')[2] }, { 0, 1 }, 'the higher rule wins')
		assert.equal(M.Get(st.border.edges.top, 'vertex')[3], 1)
	end)

	it('colors the name over its own color and gives it back', function()
		local plate = LivePlate()
		local name
		for _, widget in ipairs(plate.active) do
			if widget.spec.kind == 'text' and widget.spec.source == 'name' then
				name = widget.text
			end
		end
		assert.not_nil(name, 'Clean has a name')
		local before = M.Get(name, 'textColor')
		Rules({ { conditions = { { id = 'target' } }, paint = 'name', color = { 1, 0, 1, 1 } } })
		plate:SetState('target', true)
		assert.same({ M.Get(name, 'textColor')[1], M.Get(name, 'textColor')[2] }, { 1, 0 })
		plate:SetState('target', false)
		assert.same(M.Get(name, 'textColor')[1], before[1], 'the name color came back')
	end)

	it('warns at low health from plain math, and from the engine curve where health is hidden', function()
		local plate, unit = LivePlate({ name = 'Hurt', canAttack = true, reaction = 2, health = 90, healthMax = 100 })
		Rules({ { conditions = { { id = 'lowHealth', args = 35 } }, paint = 'health', color = { 1, 0.85, 0.1, 1 } } })
		local st = Actions:StateOf(plate)
		assert.equal(M.Get(st.tint, 'vertex')[4], 0)
		M.UpdateUnit(unit, { health = 20 }, { 'UNIT_HEALTH' })
		assert.equal(M.Get(st.tint, 'vertex')[4], 1, 'the health event ran the rule')
		if secrets then
			M.SetRestricted(true)
			M.UpdateUnit(unit, { health = 21 }, { 'UNIT_HEALTH' })
			local low = M.Get(st.lowTint, 'vertex')
			assert.is_true(low.secret, 'alpha came from the curve')
			M.SetRestricted(false)
		end
	end)
end)

describe('when actions: events come from the conditions', function()
	before_each(Reset)
	it('derives each rule event set from its conditions', function()
		Rules({
			{ conditions = { { id = 'lowHealth', args = 35 } }, paint = 'health', color = { 1, 1, 0, 1 } },
			{ conditions = { { id = 'place', args = 'raid' }, { id = 'casting' } }, glow = { 1, 1, 1, 1 } },
			{ conditions = { { id = 'unitInCombat' } }, mark = 'star' },
			{ conditions = { { id = 'focus' } }, grow = { 10, 2 } },
		})
		local rules = Actions:Program().rules
		assert.is_true(rules[1].events.UNIT_HEALTH and rules[1].events.UNIT_MAXHEALTH)
		assert.is_nil(next(rules[1].messages))
		assert.is_true(rules[2].messages.CONTEXT_CHANGED)
		assert.is_true(rules[2].events.UNIT_SPELLCAST_START)
		assert.is_true(rules[2].states)
		assert.is_true(rules[3].messages.FACTS_POLLED)
		assert.is_true(rules[4].messages.FOCUS_CHANGED and rules[4].states)
	end)

	it('registers exactly the rule events on the plate and drops them with the rules', function()
		local plate = LivePlate()
		Rules(nil)
		local before = M.RegisteredEvents(plate.events)
		assert.is_false(Has(before, 'UNIT_AURA') and not Has(before, 'UNIT_AURA'))
		Rules({ { conditions = { { id = 'castSpell', args = { [133] = 'any' } } }, mark = 'star' } })
		local during = M.RegisteredEvents(plate.events)
		assert.is_true(Has(during, 'UNIT_SPELLCAST_START'))
		assert.is_true(Has(during, 'UNIT_SPELLCAST_NOT_INTERRUPTIBLE'))
		Rules(nil)
		assert.same(M.RegisteredEvents(plate.events), before)
	end)

	it('runs a rule only for its own events, a state change or a part it paints over', function()
		local plate, unit = LivePlate()
		Rules({ { conditions = { { id = 'lowHealth', args = 35 } }, paint = 'health', color = { 1, 1, 0, 1 } } })
		local runs = 0
		local original = Actions.Run
		Actions.Run = function(self, p)
			runs = runs + 1
			return original(self, p)
		end
		M.UpdateUnit(unit, { name = 'Renamed' }, { 'UNIT_NAME_UPDATE' })
		local afterName = runs
		M.UpdateUnit(unit, { health = 10 }, { 'UNIT_HEALTH' })
		local afterHealth = runs
		Actions.Run = original
		assert.equal(afterName, 0, 'a name change is not one of its events')
		assert.equal(afterHealth, 1, 'its health event ran it once')
	end)

	it('tells the fact poller when a rule follows the fight', function()
		Rules({ { conditions = { { id = 'canAttack' } }, glow = { 1, 1, 1, 1 } } })
		assert.is_false(Actions:ReadsCombat())
		Rules({ { conditions = { { id = 'unitInCombat', negate = true } }, fade = 0.4 } })
		assert.is_true(Actions:ReadsCombat())
	end)

	it('explains each rule in plain words for the inspector', function()
		local plate = LivePlate()
		Rules({ { conditions = { { id = 'canAttack' } }, glow = { 1, 1, 1, 1 } }, { conditions = { { id = 'target' } }, mark = 'star' } })
		local lines = Actions:Describe(plate)
		assert.equal(#lines, 2)
		assert.truthy(lines[1]:find('yes', 1, true), lines[1])
		assert.truthy(lines[2]:find('no', 1, true), lines[2])
	end)

	it('does no per-frame work', function()
		local plate = LivePlate()
		plate:UpdateAll('FULL')
		M.Advance(1)
		local before = #M.ActiveOnUpdates()
		Rules({
			{ conditions = { { id = 'canAttack' } }, glow = { 1, 1, 1, 1 } },
			{ conditions = { { id = 'canAttack' } }, mark = 'star' },
			{ conditions = { { id = 'canAttack' } }, paint = 'border', color = { 1, 0, 0, 1 } },
		})
		plate:UpdateAll('FULL')
		M.Advance(1)
		assert.equal(#M.ActiveOnUpdates(), before)
	end)

	it('applies a rule only to the kinds it names', function()
		local enemy = LivePlate()
		local friend = LivePlate({ name = 'Guard', canAttack = false, reaction = 6, health = 100, healthMax = 100 }, 'friendlyNPC')
		Rules({ { conditions = {}, kinds = { 'enemyNPC' }, fade = 0.5 } })
		assert.near(M.Get(enemy.fader, 'alpha'), 0.5, 1e-6)
		assert.near(M.Get(friend.fader, 'alpha') or 1, 1, 1e-6)
		assert.is_nil(friend.actionEvents)
	end)

	it('takes everything off a plate when it unbinds', function()
		local plate = LivePlate()
		Rules({ { conditions = {}, fade = 0.3 }, { conditions = {}, grow = { 10, 0 } } })
		assert.near(M.Get(plate.fader, 'alpha'), 0.3, 1e-6)
		plate:Unbind()
		assert.near(M.Get(plate.fader, 'alpha'), 1, 1e-6)
		assert.is_nil(plate.grows and plate.grows.actions)
	end)
end)

describe('when actions: sharing', function()
	before_each(Reset)
	it('round-trips through a "When" share string', function()
		local list = {
			{ conditions = { { id = 'casting' } }, kinds = { 'enemyNPC', 'enemyPlayer' }, glow = { 1, 0.5, 0, 1 } },
			{ conditions = { { id = 'castSpell', args = { [133] = 'any' } }, { id = 'target', negate = true } }, paint = 'border', color = { 1, 0, 0, 1 } },
			{ conditions = { { id = 'lowHealth', args = 20 } }, mark = 'skull', markColor = { 1, 0, 0, 1 }, off = true },
			{ conditions = { { id = 'focus' } }, grow = { 24, 4 } },
			{ conditions = { { id = 'unitInCombat', negate = true } }, fade = 0.4 },
		}
		Store:Set('actions', list)
		local text = P.Share:Encode('when', Actions:SharePayload())
		if not text then
			skip('this client cannot make share strings')
		end
		local decoded = assert(P.Share:Decode(text))
		assert.equal(decoded.kind, 'when')
		local clean, report = Actions:CleanList(decoded.payload.actions, decoded.schema)
		assert.equal(report.kept, #list)
		assert.equal(report.newer + report.dropped, 0)
		assert.same(clean, list)
	end)

	it('refuses entries a newer version made', function()
		local _, report = Actions:CleanList({
			{ conditions = { { id = 'target' } }, glow = { 1, 1, 1, 1 } },
			{ conditions = { { id = 'target' } }, sound = 'bell' },
			{ conditions = { { id = 'someFutureCondition' } }, glow = { 1, 1, 1, 1 } },
		})
		assert.equal(report.kept, 1)
		assert.equal(report.newer, 2)
	end)

	it('refuses an action on a share string older than the action', function()
		local glow = Actions.EFFECTS.glow
		local since = glow.since
		glow.since = since + 1
		local clean, reason = Actions:CleanEntry({ conditions = { { id = 'target' } }, glow = { 1, 1, 1, 1 } }, since)
		glow.since = since
		assert.is_nil(clean)
		assert.equal(reason, 'newer')
	end)

	it('refuses a whole string from a newer format', function()
		local text = '!NP:' .. (P.Styles.Schema.CURRENT + 1) .. ':when!AAAA'
		local decoded, reason = P.Share:Decode(text)
		assert.is_nil(decoded)
		assert.equal(reason, 'newer')
	end)

	it('drops broken values instead of guessing', function()
		local _, report = Actions:CleanList({
			{ conditions = { { id = 'target' } }, paint = 'everything', color = { 1, 0, 0, 1 } },
			{ conditions = { { id = 'target' } }, mark = 'banana' },
			{ conditions = { { id = 'target' } }, glow = { 1, 1, 1, 1 }, fade = 0.5 },
			{ conditions = { { id = 'target' } } },
		})
		assert.equal(report.kept, 0)
		assert.equal(report.dropped, 4)
	end)
end)

describe('when actions: the Who and where page', function()
	before_each(Reset)
	it('adds a rule from a template and edits it in place', function()
		local W = P.Options.WhoAndWhere
		W.ApplyActionChange({ action = 'add', order = { 'tpl:focusBig' }, rows = { { on = true } } })
		local list = Store:Get('actions')
		assert.equal(#list, 1)
		assert.same(list[1].grow, { 24, 4 })
		assert.equal(W.editingAction, 1)
		local entry = W.EditedAction()
		entry.grow = { 30, 6 }
		W.SetEditedAction(entry)
		assert.same(Store:Get('actions')[1].grow, { 30, 6 })
		local rows = W.ActionRows()
		assert.equal(#rows, 1)
		assert.truthy(rows[1].sentence:find('focus', 1, true), rows[1].sentence)
		W.ApplyActionChange({ action = 'remove', order = {}, rows = {} })
		assert.is_nil(Store:Get('actions'))
	end)
end)
