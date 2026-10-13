-- @runtime lua51
-- Threat display (plan 3.1, 4, 6.4): the six states per role as a truth table, threat only where
-- the setting allows and only on enemy NPCs, the per-role channel defaults (tanks on the bar with
-- the flipped palette, damage on the border, healers a glow), the glow and size channels on live
-- plates, another tank and the pet holding a mob, the S2 fallback (hidden threat gives no threat
-- display, logged once), hidden "is tanking" answers folded through sinks, and previews showing a
-- tank's view whatever the player is doing.
local M, H = ...

if not H.ModuleExists() then
	describe('threat', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

M.Login('NameplatesTestHost')
local P = H.FreshCore()
local Threat, Roles, Colors, GlowLib = P.Threat, P.Roles, P.Colors, P.GlowLib
local Store = P.Store

local function Ctx(fields)
	local ctx = { place = 'dungeon', inCombat = true, role = 'damage', inGroup = true, playerLevel = 60, tanks = {}, petTank = false }
	for k, v in pairs(fields or {}) do
		ctx[k] = v
	end
	return ctx
end

local function Has(list, id)
	for _, row in ipairs(list) do
		if row.id == id then
			return true
		end
	end
	return false
end

describe('threat: states', function()
	it('works out the six states for tanks', function()
		local cases = {
			{ 3, true, nil, nil, 'safe' },
			{ 2, true, nil, nil, 'losing' },
			{ 1, true, nil, nil, 'lost' },
			{ 0, true, nil, nil, 'lost' },
			{ nil, true, nil, nil, nil },
			{ 0, true, true, nil, 'offTank' },
			{ nil, true, true, nil, 'offTank' },
			{ 0, true, nil, true, 'pet' },
			{ 3, true, true, nil, 'safe' },
			{ 3, false, nil, nil, 'solo' },
			{ 0, false, nil, true, 'pet' },
		}
		for _, c in ipairs(cases) do
			assert.equal(Threat.State('tank', c[1], c[2], c[3], c[4]), c[5], string.format('tank status %s group %s other %s pet %s', tostring(c[1]), tostring(c[2]), tostring(c[3]), tostring(c[4])))
		end
	end)

	it('never hides "about to pull" behind "the tank has it" for damage and healers', function()
		for _, role in ipairs({ 'damage', 'healer' }) do
			local cases = {
				{ 0, true, nil, nil, 'safe' },
				{ 1, true, nil, nil, 'losing' },
				{ 2, true, nil, nil, 'lost' },
				{ 3, true, nil, nil, 'lost' },
				{ nil, true, nil, nil, nil },
				{ 0, true, true, nil, 'offTank' },
				{ 1, true, true, nil, 'losing' },
				{ 0, true, nil, true, 'pet' },
				{ 3, true, nil, true, 'lost' },
				{ 3, false, nil, nil, 'solo' },
				{ 0, false, nil, true, 'pet' },
			}
			for _, c in ipairs(cases) do
				assert.equal(Threat.State(role, c[1], c[2], c[3], c[4]), c[5], string.format('%s status %s other %s pet %s', role, tostring(c[1]), tostring(c[3]), tostring(c[4])))
			end
		end
	end)

	it('glows and grows only for states that need attention', function()
		assert.is_true(Threat.GlowStates('tank').offTank)
		assert.is_true(Threat.GlowStates('tank').lost)
		assert.is_nil(Threat.GlowStates('tank').safe)
		assert.is_nil(Threat.GlowStates('damage').offTank)
		assert.is_true(Threat.GlowStates('healer').losing)
		local style = { states = { target = { grow = { 14, 2 } } } }
		assert.same({ Threat.GrowFor('lost', style) }, { 14, 2 })
		assert.same({ Threat.GrowFor('losing', style) }, { 7, 1 })
		assert.is_nil(Threat.GrowFor('safe', style))
		assert.is_nil(Threat.GrowFor('offTank', style))
		assert.same({ Threat.GrowFor('lost', {}) }, Threat.DEFAULT_GROW)
	end)

	it('shows threat only on enemy NPCs, where the setting allows', function()
		local mob = { canAttack = true, isPlayer = false }
		assert.equal(Threat.When(nil), 'instances')
		assert.equal(Threat.When({ when = 'always' }), 'everywhere')
		assert.is_true(Threat.Applies(mob, Ctx({ place = 'dungeon' }), nil))
		assert.is_false(Threat.Applies(mob, Ctx({ place = 'world' }), nil), 'in instances by default')
		assert.is_true(Threat.Applies(mob, Ctx({ place = 'world' }), { when = 'always' }))
		assert.is_false(Threat.Applies(mob, Ctx({ place = 'raid' }), { when = 'never' }))
		assert.is_false(Threat.Applies({ canAttack = true, isPlayer = true }, Ctx(), nil), 'not on enemy players')
		assert.is_false(Threat.Applies({ canAttack = false }, Ctx(), nil), 'not on friends')
	end)
end)

describe('threat: role defaults (3.1)', function()
	local function Rows(piece, role)
		return Colors:Compile(piece, { scheme = 'auto' }, Ctx({ role = role })).rows
	end

	it('puts the flipped palette on the bar for tanks', function()
		local health = Rows('health', 'tank')
		assert.is_true(Has(health, 'threat'))
		assert.is_true(Has(health, 'offTank'))
		assert.is_true(Has(health, 'petTank'))
		assert.is_false(Has(Rows('border', 'tank'), 'threat'))
		assert.equal(Roles.ThreatState('tank', 3, true), 'safe', 'holding the mob is safe for a tank')
		assert.equal(Roles.ThreatState('damage', 3, true), 'lost', 'and lost for everyone else')
	end)

	it('puts threat on the border for damage, so mob type keeps the bar', function()
		assert.is_true(Has(Rows('border', 'damage'), 'threat'))
		assert.is_false(Has(Rows('health', 'damage'), 'threat'))
		assert.is_true(Has(Rows('health', 'damage'), 'mobType'))
	end)

	it('gives healers a glow and leaves every color list alone', function()
		for _, piece in ipairs({ 'health', 'border', 'name' }) do
			assert.is_false(Has(Rows(piece, 'healer'), 'threat'), piece)
		end
		assert.is_true(Roles.ThreatOn('healer').glow)
	end)
end)

----------------------------------------------------------------------------------------------------
-- Live plates
----------------------------------------------------------------------------------------------------

local count = 0
local live = {}

local function Setup(opts)
	Store:Set('threat', opts.threat)
	local ctx = P.Context
	ctx.role = opts.role or 'damage'
	ctx.inGroup = opts.inGroup ~= false
	ctx.place = opts.place or 'dungeon'
	ctx.tanks = opts.tanks or {}
	ctx.petTank = opts.petTank or false
	-- The Driver fires CONTEXT_CHANGED in game; color programs are cached until then
	Colors:Invalidate()
	count = count + 1
	local token = 'nameplate' .. (60 + count)
	local mob = M.AddUnit({ name = 'Ghoul', canAttack = true, reaction = 2 })
	M.SetToken(token, mob)
	local plate = P.Plate.New(UIParent, false)
	plate:ApplyStyle(P.Styles.Merge:Resolve('clean', 'enemyNPC', 'medium'))
	local src = P.Source.NewLive(token)
	src:ReadFacts(plate.facts)
	plate:Bind(token, src)
	live[#live + 1] = { plate = plate, token = token }
	return plate, mob, plate:GetWidget('threat')
end

local function Teardown()
	for _, entry in ipairs(live) do
		entry.plate:Unbind()
		M.SetToken(entry.token, nil)
	end
	live = {}
	Store:Set('threat', nil)
	local ctx = P.Context
	ctx.role, ctx.inGroup, ctx.place, ctx.tanks, ctx.petTank = 'damage', false, 'world', {}, false
	M.SetToken('party1', nil)
	M.SetToken('pet', nil)
	M.SetRestricted(false)
end

local function Color(widget)
	local vertex = M.Get(widget.glow.pieces[1], 'vertex')
	return { vertex[1], vertex[2], vertex[3] }, vertex
end

local function Palette(state)
	local c = Roles.PALETTE[state]
	return { c[1], c[2], c[3] }
end

local function GroupTank()
	local tank = M.AddUnit({ name = 'Other Tank', isPlayer = true, canAttack = false, reaction = 5, role = 'TANK' })
	M.SetToken('party1', tank)
	return tank
end

describe('threat: glow on live plates', function()
	after_each(Teardown)

	it('shows healers a glow only for states that need attention', function()
		local _, mob, widget = Setup({ role = 'healer' })
		assert.not_nil(widget, 'Clean has a threat part')
		assert.is_false(GlowLib.IsShown(widget.glow), 'not on the threat list')
		M.SetThreat(mob, M.player, { status = 1 })
		assert.is_true(GlowLib.IsShown(widget.glow))
		assert.same(Color(widget), Palette('losing'))
		M.SetThreat(mob, M.player, { status = 3 })
		assert.same(Color(widget), Palette('lost'))
		M.SetThreat(mob, M.player, { status = 0 })
		assert.is_false(GlowLib.IsShown(widget.glow), 'safe draws nothing')
	end)

	it('follows where threat may show', function()
		local _, mob, widget = Setup({ role = 'healer', place = 'world' })
		M.SetThreat(mob, M.player, { status = 3 })
		assert.is_false(GlowLib.IsShown(widget.glow), 'in instances only by default')
		Store:Set('threat', { when = 'always' })
		M.SetThreat(mob, M.player, { status = 3 })
		assert.is_true(GlowLib.IsShown(widget.glow))
		Store:Set('threat', { when = 'never' })
		M.SetThreat(mob, M.player, { status = 3 })
		assert.is_false(GlowLib.IsShown(widget.glow))
	end)

	it('leaves the glow off for roles whose threat shows elsewhere', function()
		local _, mob, widget = Setup({ role = 'damage' })
		M.SetThreat(mob, M.player, { status = 3 })
		assert.is_false(GlowLib.IsShown(widget.glow), 'damage shows threat on the border')
	end)

	it('shows a tank when another tank or the pet holds the mob', function()
		local tank = GroupTank()
		local pet = M.AddUnit({ name = 'Wolf', canAttack = false, reaction = 5, playerControlled = true })
		M.SetToken('pet', pet)
		local _, mob, widget = Setup({ role = 'tank', tanks = { 'party1' }, petTank = true, threat = { show = { glow = true } } })
		M.SetThreat(mob, M.player, { status = 0 })
		M.SetThreat(mob, tank, { status = 3 })
		assert.is_true(GlowLib.IsShown(widget.glow))
		assert.same(Color(widget), Palette('offTank'))
		M.SetThreat(mob, tank, { status = 0 })
		M.SetThreat(mob, pet, { status = 3 })
		assert.same(Color(widget), Palette('pet'))
		M.SetThreat(mob, pet, { status = 0 })
		M.SetThreat(mob, M.player, { status = 3 })
		assert.is_false(GlowLib.IsShown(widget.glow), 'holding it yourself is calm')
	end)

	it('tells damage dealers they are about to pull even while the tank holds the mob', function()
		local tank = GroupTank()
		local _, mob, widget = Setup({ role = 'damage', tanks = { 'party1' }, threat = { show = { glow = true } } })
		M.SetThreat(mob, tank, { status = 3 })
		M.SetThreat(mob, M.player, { status = 0 })
		assert.is_false(GlowLib.IsShown(widget.glow))
		M.SetThreat(mob, M.player, { status = 1 })
		assert.is_true(GlowLib.IsShown(widget.glow))
		assert.same(Color(widget), Palette('losing'))
	end)

	it('uses the color-blind palette and the player own colors', function()
		Store:Set('colorBlind', true)
		local _, mob, widget = Setup({ role = 'healer' })
		M.SetThreat(mob, M.player, { status = 3 })
		local c = Roles.PALETTE_COLORBLIND.lost
		assert.same(Color(widget), { c[1], c[2], c[3] })
		Store:Set('threat', { colors = { lost = { 1, 0, 1, 1 } } })
		M.SetThreat(mob, M.player, { status = 3 })
		assert.same(Color(widget), { 1, 0, 1 })
		Store:Reset('colorBlind')
	end)
end)

describe('threat: size channel', function()
	after_each(Teardown)

	it('grows plates that need attention in whole pixels, eased with the target emphasis', function()
		local plate, mob = Setup({ role = 'tank', threat = { show = { size = true } } })
		local width, height = plate.style.width, plate.style.height
		local grow = plate.style.states.target.grow
		M.SetThreat(mob, M.player, { status = 0 })
		M.Advance(0.5)
		assert.equal(M.Get(plate.art, 'w'), width + grow[1])
		assert.equal(M.Get(plate.art, 'h'), height + grow[2])
		M.SetThreat(mob, M.player, { status = 2 })
		M.Advance(0.5)
		assert.equal(M.Get(plate.art, 'w'), width + math.floor(grow[1] / 2 + 0.5))
		M.SetThreat(mob, M.player, { status = 3 })
		M.Advance(0.5)
		assert.equal(M.Get(plate.art, 'w'), width)
		assert.is_nil(plate.grows.threat)
	end)

	it('adds to the target growth instead of replacing it', function()
		local plate, mob = Setup({ role = 'tank', threat = { show = { size = true } } })
		local width = plate.style.width
		local grow = plate.style.states.target.grow
		plate:SetState('target', true)
		M.SetThreat(mob, M.player, { status = 0 })
		M.Advance(0.5)
		assert.equal(M.Get(plate.art, 'w'), width + grow[1] * 2)
		plate:Unbind()
		assert.is_nil(plate.grows.threat, 'unbinding drops the growth')
	end)

	it('gives the growth back when the plate changes to a style without threat, and takes it again after', function()
		local plate, mob = Setup({ role = 'tank', threat = { show = { size = true } } })
		local grow = plate.style.states.target.grow
		M.SetThreat(mob, M.player, { status = 0 })
		M.Advance(0.5)
		assert.not_nil(plate.grows.threat)
		local mini = P.Styles.Merge:Resolve('mini', 'enemyNPC', 'medium')
		plate:ApplyStyle(mini)
		assert.is_nil(plate.grows.threat, 'Mini has no threat part')
		assert.equal(M.Get(plate.art, 'w'), mini.width)
		local clean = P.Styles.Merge:Resolve('clean', 'enemyNPC', 'medium')
		plate:ApplyStyle(clean)
		M.Advance(0.5)
		assert.equal(M.Get(plate.art, 'w'), clean.width + grow[1])
	end)
end)

describe('threat: color channels', function()
	after_each(Teardown)

	local function Border(plate)
		local vertex = M.Get(plate:GetWidget('health').bar.border.edges.top, 'vertex')
		return { vertex[1], vertex[2], vertex[3] }, vertex
	end

	local function Bar(plate)
		local c = M.Get(plate:GetHealthBar(), 'barColor')
		return { c[1], c[2], c[3] }, c
	end

	it('warns damage dealers on the border before saying the tank has it', function()
		local tank = GroupTank()
		local plate, mob = Setup({ role = 'damage', tanks = { 'party1' } })
		M.SetThreat(mob, tank, { status = 3 })
		M.SetThreat(mob, M.player, { status = 0 })
		assert.same(Border(plate), Palette('offTank'))
		M.SetThreat(mob, M.player, { status = 1 })
		assert.same(Border(plate), Palette('losing'), 'about to pull wins over the tank holding it')
		M.SetThreat(mob, tank, { status = 1 })
		M.SetThreat(mob, M.player, { status = 3 })
		assert.same(Border(plate), Palette('lost'))
	end)

	it('puts threat on a tank bar with the flipped palette, another tank and the pet', function()
		local tank = GroupTank()
		local pet = M.AddUnit({ name = 'Wolf', canAttack = false, reaction = 5, playerControlled = true })
		M.SetToken('pet', pet)
		local plate, mob = Setup({ role = 'tank', tanks = { 'party1' }, petTank = true })
		M.SetThreat(mob, M.player, { status = 3 })
		assert.same(Bar(plate), Palette('safe'), 'holding it is safe for a tank')
		M.SetThreat(mob, M.player, { status = 0 })
		assert.same(Bar(plate), Palette('lost'))
		M.SetThreat(mob, tank, { status = 3 })
		assert.same(Bar(plate), Palette('offTank'))
		M.SetThreat(mob, tank, { status = 0 })
		M.SetThreat(mob, pet, { status = 3 })
		assert.same(Bar(plate), Palette('pet'))
	end)

	it('colors the name when the player picks the name channel', function()
		local plate, mob = Setup({ role = 'damage', threat = { show = { name = true } } })
		M.SetThreat(mob, M.player, { status = 3 })
		local c = M.Get(plate:GetWidget('name').text, 'textColor')
		assert.same({ c[1], c[2], c[3] }, Palette('lost'))
		local border = Border(plate)
		local lost = Palette('lost')
		assert.is_false(border[1] == lost[1] and border[2] == lost[2], 'the border no longer shows threat')
	end)

	it('folds a hidden "another tank holds it" answer into the bar color', function()
		local tank = GroupTank()
		local plate, mob = Setup({ role = 'tank', tanks = { 'party1' } })
		if not M.SetRestricted(true, { 'threat' }) then
			skip('this client never hides threat')
		end
		M.SetThreat(mob, M.player, { status = 0 })
		M.SetThreat(mob, tank, { status = 3 })
		local color, raw = Bar(plate)
		assert.is_true(raw.secret, 'the color came from the engine')
		assert.same(color, Palette('offTank'))
		M.SetThreat(mob, tank, { status = 0 })
		assert.same(Bar(plate), Palette('lost'))
	end)

	it('shows no threat color where threat is not allowed', function()
		local plate, mob = Setup({ role = 'tank', place = 'world' })
		M.SetThreat(mob, M.player, { status = 0 })
		local color, lost = Bar(plate), Palette('lost')
		assert.is_false(color[1] == lost[1] and color[2] == lost[2] and color[3] == lost[3], 'in instances only by default')
		Store:Set('threat', { when = 'always' })
		Colors:Invalidate()
		M.SetThreat(mob, M.player, { status = 0 })
		assert.same(Bar(plate), Palette('lost'))
	end)
end)

describe('threat: hidden by the game', function()
	after_each(function()
		Teardown()
	end)

	it('shows no threat glow or size when your own threat is hidden (S2), logged once', function()
		if not C_Secrets then
			skip('this client has no secret checks')
		end
		local real = C_Secrets.ShouldUnitThreatStateBeSecret
		C_Secrets.ShouldUnitThreatStateBeSecret = function()
			return true
		end
		local plate, mob, widget = Setup({ role = 'healer', threat = { show = { glow = true, size = true } } })
		M.SetThreat(mob, M.player, { status = 3 })
		M.SetThreat(mob, M.player, { status = 2 })
		C_Secrets.ShouldUnitThreatStateBeSecret = real
		assert.is_false(GlowLib.IsShown(widget.glow))
		assert.is_nil(plate.grows and plate.grows.threat)
		local lines = 0
		for _, line in ipairs(H.logs.host or {}) do
			if line:find('threat glow and size are off', 1, true) then
				lines = lines + 1
			end
		end
		assert.equal(lines, 1, 'logged once')
	end)

	it('folds a hidden "another tank holds it" answer into the glow without reading it', function()
		local tank = GroupTank()
		local plate, mob, widget = Setup({ role = 'tank', tanks = { 'party1' }, threat = { show = { glow = true, size = true } } })
		if not M.SetRestricted(true, { 'threat' }) then
			skip('this client never hides threat')
		end
		M.SetThreat(mob, tank, { status = 3 })
		M.SetThreat(mob, M.player, { status = 0 })
		local color, vertex = Color(widget)
		assert.is_true(vertex.secret, 'the color came from the engine')
		assert.same(color, Palette('offTank'))
		assert.equal(vertex[4], 1)
		assert.is_nil(plate.grows and plate.grows.threat, 'size waits for a plain answer')
		M.SetThreat(mob, tank, { status = 0 })
		color, vertex = Color(widget)
		assert.same(color, Palette('lost'))
		M.SetThreat(mob, M.player, nil)
		color, vertex = Color(widget)
		assert.equal(vertex[4], 0, 'nothing to show: no one we know holds it')
		M.SetThreat(mob, tank, { status = 3 })
		color, vertex = Color(widget)
		assert.equal(vertex[4], 1)
		assert.same(color, Palette('offTank'))
	end)
end)

describe('threat: previews', function()
	after_each(Teardown)

	it('shows a tank view of another tank holding the mob, whatever the player is doing', function()
		Store:Set('threat', { show = { glow = true } })
		local ctx = P.Scenes.PreviewContext({ role = 'tank', tanks = { 'party1' }, place = 'dungeon' })
		local plate = P.Plate.New(UIParent, true, ctx)
		plate:ApplyStyle(P.Styles.Merge:Resolve('clean', 'enemyNPC', 'medium'))
		plate:BindSample(P.Source.NewSample('offTanked'))
		local widget = plate:GetWidget('threat')
		assert.is_true(GlowLib.IsShown(widget.glow))
		assert.same(Color(widget), Palette('offTank'))
		local state, reason = Threat.Describe(plate)
		assert.equal(state, 'offTank')
		assert.equal(reason, 'shown')
	end)
end)
