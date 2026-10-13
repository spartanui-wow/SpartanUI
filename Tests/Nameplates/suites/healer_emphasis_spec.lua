-- @runtime lua51
-- Healer emphasis (plan 3.1, Roles): for the healer role, enemy NPC and minor plates are small and
-- soft until they matter (target, focus, under the mouse, casting), sizes stay whole pixels and are
-- never scaled, enemy players keep their size, the setting turns it off, and healers get a
-- stronger removable buffs row (a new row when the style has none, a bigger one when it has).
local M, H = ...

if not H.ModuleExists() then
	describe('healer emphasis', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

M.Login('NameplatesTestHost')
local P = H.FreshCore()
M.Login('NameplatesTestHost')
local Roles, Store, Merge = P.Roles, P.Store, P.Styles.Merge

local function Ctx(role)
	return { place = 'world', inCombat = false, resting = false, role = role or 'healer', inGroup = true, groupSize = 5, playerLevel = 60, difficultyID = 0, tanks = {}, hasTarget = false }
end

local tokenCount = 120

local function LivePlate(kind, ctx, unitSpec, resolved)
	tokenCount = tokenCount + 1
	local token = 'nameplate' .. tokenCount
	local unit = M.AddUnit(unitSpec or { name = 'Gnoll', canAttack = true, reaction = 2, health = 80, healthMax = 100 })
	M.SetToken(token, unit)
	local plate = P.Plate.New(UIParent, false, ctx or Ctx())
	plate.situation = kind or 'enemyNPC'
	plate:ApplyStyle(resolved or Merge:Resolve('clean', plate.situation, 'medium'))
	local src = P.Source.NewLive(token)
	src:ReadFacts(plate.facts)
	plate:Bind(token, src)
	return plate, unit
end

local function Size(plate)
	return M.Get(plate.art, 'w'), M.Get(plate.art, 'h')
end

local function Reset()
	Store:Set({ 'behavior', 'healerEmphasis' }, nil)
	Store:Set('actions', nil)
end

describe('healer emphasis: quiet enemy plates', function()
	before_each(Reset)

	it('makes enemy NPC plates small and soft for healers, in whole pixels', function()
		local plate = LivePlate('enemyNPC')
		local base = plate.baseStyle
		local w, h = Roles.QuietSize(base.width, base.height)
		assert.equal(w % 1, 0)
		assert.equal(h % 1, 0)
		assert.truthy(w < base.width and h < base.height, 'smaller')
		local gotW, gotH = Size(plate)
		assert.equal(gotW, w)
		assert.equal(gotH, h)
		assert.near(M.Get(plate.art, 'alpha'), Roles.QUIET.alpha, 1e-6)
		assert.equal(#M.Calls(plate.art, 'SetScale'), 0, 'never scaled')
	end)

	it('brings a plate back when it matters: target, focus, mouse and casting', function()
		for _, state in ipairs({ 'target', 'focus', 'mouseover', 'casting' }) do
			local plate = LivePlate('enemyNPC')
			local base = plate.baseStyle
			plate:SetState(state, true)
			M.Advance(0.5)
			local w = Size(plate)
			assert.truthy(w >= base.width, state .. ' is full size: ' .. tostring(w))
			assert.truthy(M.Get(plate.art, 'alpha') > Roles.QUIET.alpha, state .. ' is bright')
			plate:SetState(state, false)
			M.Advance(0.5)
			assert.equal(Size(plate), (Roles.QuietSize(base.width, base.height)), state .. ' quiet again')
		end
	end)

	it('quiets minor enemies but never enemy players or friends', function()
		assert.is_true(Roles.Quiet(LivePlate('minor')))
		assert.is_false(Roles.Quiet(LivePlate('enemyPlayer', nil, { name = 'Rogue', isPlayer = true, canAttack = true, reaction = 2, health = 100, healthMax = 100 })))
		assert.is_false(Roles.Quiet(LivePlate('friendlyNPC', nil, { name = 'Guard', reaction = 6, health = 100, healthMax = 100 })))
	end)

	it('leaves tanks and damage dealers alone', function()
		assert.is_false(Roles.Quiet(LivePlate('enemyNPC', Ctx('tank'))))
		assert.is_false(Roles.Quiet(LivePlate('enemyNPC', Ctx('damage'))))
	end)

	it('turns off with the setting, and back on', function()
		local plate = LivePlate('enemyNPC')
		Store:Set({ 'behavior', 'healerEmphasis' }, false)
		plate:RefreshRole()
		M.Advance(0.5)
		assert.is_false(Roles.Quiet(plate))
		assert.equal(Size(plate), plate.baseStyle.width)
		Store:Set({ 'behavior', 'healerEmphasis' }, nil)
		plate:RefreshRole()
		M.Advance(0.5)
		assert.is_true(Roles.Quiet(plate))
	end)

	it('follows a role change', function()
		local ctx = Ctx('healer')
		local plate = LivePlate('enemyNPC', ctx)
		assert.is_true(Roles.Quiet(plate))
		ctx.role = 'damage'
		plate:RefreshRole()
		M.Advance(0.5)
		assert.is_false(Roles.Quiet(plate))
		assert.equal(Size(plate), plate.baseStyle.width)
		assert.is_nil(plate.style.roleBase, 'back to the plain style')
	end)

	it('keeps previews as they are unless they show fades', function()
		local plate = P.Plate.New(UIParent, true, Ctx('healer'))
		plate.situation = 'enemyNPC'
		plate:ApplyStyle(Merge:Resolve('clean', 'enemyNPC', 'medium'))
		assert.is_false(Roles.Quiet(plate))
		assert.is_nil(plate.style.roleBase, 'previews and the designer show the style itself')
		plate.previewFade = true
		assert.is_true(Roles.Quiet(plate))
	end)
end)

describe('healer emphasis: a stronger removable buffs row', function()
	before_each(Reset)

	it('adds a removable buffs row to enemy plates when the style has none', function()
		local plate = LivePlate('enemyNPC')
		local spec = plate.style.parts.healerRemovable
		assert.not_nil(spec, 'Clean has no removable row, so healers get one')
		assert.equal(spec.kind, 'auras')
		assert.equal(spec.row, 'removable')
		assert.truthy(plate.style.key:find('|healer', 1, true))
		assert.not_nil(plate:GetWidget('healerRemovable'), 'the row is drawn')
		assert.equal(plate.baseStyle.parts.healerRemovable, nil, 'the style itself is untouched')
		local report = { dropped = 0, clamped = 0, fixed = 0, droppedKeys = {} }
		local raw = P.util.Copy(Roles.REMOVABLE_PART)
		raw.anchor = { 'RIGHT', 'health', 'LEFT', -4, 0 }
		assert.not_nil(P.Styles.Schema:CheckPart(raw, 'healerRemovable', report))
		assert.equal(report.dropped + report.clamped + report.fixed, 0, 'the added row is a valid part')
	end)

	it('gives enemy players the row too, but not friends', function()
		local enemy = LivePlate('enemyPlayer', nil, { name = 'Mage', isPlayer = true, canAttack = true, reaction = 2, health = 100, healthMax = 100 })
		assert.not_nil(enemy.style.parts.healerRemovable)
		local friend = LivePlate('friendlyNPC', nil, { name = 'Guard', reaction = 6, health = 100, healthMax = 100 })
		assert.is_nil(friend.style.parts.healerRemovable)
	end)

	it('makes an existing removable row bigger instead of adding one', function()
		local resolved = Merge.ResolveRaw({
			id = 'healerTest',
			name = 'Healer test',
			version = 1,
			schema = 1,
			parts = {
				health = { order = 10, kind = 'bar', source = 'health', fill = 'plate' },
				buffs = { order = 20, kind = 'auras', row = 'removable', anchor = { 'RIGHT', 'health', 'LEFT', -4, 0 }, size = 18, max = 2 },
			},
		}, nil, 'enemyNPC', 'medium')
		resolved.key = 'healerTest'
		local plate = LivePlate('enemyNPC', nil, nil, resolved)
		assert.is_nil(plate.style.parts.healerRemovable)
		assert.equal(plate.style.parts.buffs.size, 18 + Roles.REMOVABLE_BOOST.size)
		assert.equal(plate.style.parts.buffs.max, 2 + Roles.REMOVABLE_BOOST.max)
		assert.equal(resolved.parts.buffs.size, 18, 'the resolved style stays read-only')
	end)

	it('makes one healer style per resolved style, and none for other roles', function()
		local a = LivePlate('enemyNPC')
		local b = LivePlate('enemyNPC')
		assert.equal(a.style, b.style, 'shared, not rebuilt per plate')
		local damage = LivePlate('enemyNPC', Ctx('damage'))
		assert.is_nil(damage.style.parts.healerRemovable)
	end)

	it('lays out again with the base style, never a healer style of a healer style', function()
		local plate = LivePlate('enemyNPC')
		local key = plate.style.key
		plate:Layout()
		assert.equal(plate.style.key, key)
		plate:ApplyStyle(plate.style)
		assert.equal(plate.style.key, key)
	end)
end)
