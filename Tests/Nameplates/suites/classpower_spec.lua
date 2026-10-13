-- @runtime lua51
-- Class resource pips on the target plate (Engine/Parts/ClassPower.lua): the right resource for
-- each class on this client, combo points read from the target where they belong to it, every pip
-- filled from one (possibly secret) amount without reading it, pips only on an attackable target,
-- the player's power events reaching only the target plate, fragments, runes that fill as they
-- come back, charged combo points, previews from the sample, plain reasons when nothing shows,
-- and quiet events once the engine stops.
local M, H = ...
local S = M.S

if not H.ModuleExists() then
	describe('class power', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

M.Login('NameplatesTestHost')
local P = H.FreshCore()
local Merge = P.Styles.Merge
local ClassPower = P.ClassPower
local POWER = ClassPower.POWER
local retail = P.Caps.Rules.retail and true or false
local client = P.Caps:Client()

-- What each client's game gives the player (a maximum above zero), so the stubs below answer the
-- way that client would
local HAS = {
	[POWER.combo] = true,
	[POWER.holy] = retail or client == 'mists',
	[POWER.chi] = retail or client == 'mists',
	[POWER.arcane] = retail,
	[POWER.shards] = retail or client == 'mists',
	[POWER.embers] = client == 'mists',
	[POWER.orbs] = client == 'mists',
	[POWER.essence] = retail,
}
local RUNES = retail or client == 'mists' or client == 'titan'
local TYPED_RUNES = client == 'mists' or client == 'titan'
local MAX = { [POWER.combo] = 5, [POWER.holy] = 5, [POWER.chi] = 5, [POWER.arcane] = 4, [POWER.shards] = retail and 5 or 4, [POWER.embers] = 4, [POWER.orbs] = 3, [POWER.essence] = 6 }
local FRAGMENTS = { [POWER.shards] = 10, [POWER.embers] = 10 }

-- The player's power world. The mock models one power per unit, so the suite answers the
-- player's power reads itself (and wraps them as secrets when world.secret is set).
local world
local saved = {}

local function Stub(name, fn)
	if saved[name] == nil then
		saved[name] = { value = rawget(_G, name) }
	end
	rawset(_G, name, fn)
end

local function Restore()
	for name, entry in pairs(saved) do
		rawset(_G, name, entry.value)
	end
	saved = {}
	M.spec = nil
	M.player.class = 'MAGE'
	if P.db then
		P.Caps:SetOverride('quirk:comboPointsFromPlayer', nil)
	end
end

local function Wrap(value)
	if world.secret then
		return S.Wrap(value)
	end
	return value
end

local function IsPlayer(unit)
	return S.Reveal(unit) == 'player'
end

---Set up the player. spec fields: class, spec, powerType, power (by power type), raw (fragments),
---combo (points on the target), runes, charged, vehicle, secret.
local function Player(spec)
	world = {
		power = spec.power or {},
		raw = spec.raw or {},
		combo = spec.combo or 0,
		runes = spec.runes,
		charged = spec.charged,
		vehicle = spec.vehicle,
		secret = spec.secret,
		powerType = spec.powerType or 0,
	}
	M.player.class = spec.class
	M.spec = spec.spec
	Stub('UnitPower', function(unit, powerType, unmodified)
		if not IsPlayer(unit) then
			return 0
		end
		if unmodified and FRAGMENTS[powerType] then
			return Wrap(world.raw[powerType] or (world.power[powerType] or 0) * FRAGMENTS[powerType])
		end
		return Wrap(world.power[powerType] or 0)
	end)
	Stub('UnitPowerMax', function(unit, powerType, unmodified)
		if not IsPlayer(unit) or not HAS[powerType] then
			return 0
		end
		local max = MAX[powerType] or 5
		if unmodified and FRAGMENTS[powerType] then
			return max * FRAGMENTS[powerType]
		end
		return max
	end)
	Stub('UnitPowerType', function()
		return world.powerType
	end)
	Stub('UnitPowerDisplayMod', function(powerType)
		return powerType == POWER.shards and 10 or 1
	end)
	Stub('GetComboPoints', function(unit)
		if not IsPlayer(unit) then
			return 0
		end
		return Wrap(world.combo)
	end)
	Stub('UnitHasVehicleUI', function()
		return world.vehicle and true or false
	end)
	Stub('GetUnitChargedPowerPoints', function()
		return world.charged
	end)
	Stub('GetRuneCooldown', RUNES and function(index)
		local rune = world.runes and world.runes[index]
		if not rune then
			return nil
		end
		return rune.start, rune.duration, rune.ready
	end or nil)
	Stub('GetRuneType', TYPED_RUNES and function(index)
		return ({ 1, 1, 2, 2, 3, 3 })[index]
	end or nil)
	ClassPower:Invalidate()
end

local count = 0
local function NewLive(unitSpec)
	count = count + 1
	local unit = M.AddUnit(unitSpec or { name = 'Target Dummy', canAttack = true, reaction = 2 })
	local token = 'nameplate' .. (20 + count)
	M.SetToken(token, unit)
	local plate = P.Plate.New(UIParent, false)
	local src = P.Source.NewLive(token)
	src:ReadFacts(plate.facts)
	plate:ApplyStyle(Merge:Resolve('clean', 'enemyNPC', 'medium'))
	plate:Bind(token, src)
	return plate, plate:GetWidget('power'), token
end

local function Value(pip)
	return S.Reveal(M.Get(pip, 'value'))
end

local function Shown(region)
	return M.Get(region, 'shown') == true
end

local function FirePower(token)
	M.Fire('UNIT_POWER_FREQUENT', 'player', token or 'COMBO_POINTS')
end

describe('class power: the built-in look', function()
	it('Clean draws the pips under the cast bar, on the target only', function()
		local resolved = Merge:Resolve('clean', 'enemyNPC', 'medium')
		local spec = resolved.parts.power
		assert.not_nil(spec, 'Clean has a class power part')
		assert.equal(spec.kind, 'classPower')
		assert.equal(spec.state, 'target')
		local _, report = P.Styles.Schema:ValidateStyle(P.Styles.Registry:Get('clean'))
		assert.equal(report.dropped + report.clamped + report.fixed, 0, 'Clean passes the import checks')
	end)
end)

describe('class power: which resource', function()
	after_each(Restore)

	local cases = {
		{ class = 'ROGUE', want = 'comboPoints' },
		{ class = 'DRUID', powerType = POWER.energy, want = 'comboPoints' },
		{ class = 'DRUID', powerType = 0, want = nil, reason = 'form' },
		{ class = 'PALADIN', want = HAS[POWER.holy] and 'holyPower' or nil },
		{ class = 'MONK', spec = 3, want = HAS[POWER.chi] and 'chi' or nil },
		{ class = 'MONK', spec = 1, want = client == 'mists' and 'chi' or nil },
		{ class = 'MAGE', spec = 1, want = HAS[POWER.arcane] and 'arcaneCharges' or nil },
		{ class = 'MAGE', spec = 2, want = nil },
		{ class = 'WARLOCK', spec = 3, want = retail and 'soulShards' or (HAS[POWER.embers] and 'burningEmbers') or nil },
		{ class = 'WARLOCK', spec = 1, want = HAS[POWER.shards] and 'soulShards' or nil },
		{ class = 'PRIEST', spec = 3, want = HAS[POWER.orbs] and 'shadowOrbs' or nil },
		{ class = 'EVOKER', want = HAS[POWER.essence] and 'essence' or nil },
		{ class = 'DEATHKNIGHT', want = RUNES and 'runes' or nil },
		{ class = 'WARRIOR', want = nil, reason = 'class' },
	}
	for _, case in ipairs(cases) do
		local label = case.class .. (case.spec and (' spec ' .. case.spec) or '') .. (case.powerType and (' power ' .. case.powerType) or '')
		it(label .. ' on ' .. client .. ' -> ' .. tostring(case.want), function()
			Player({ class = case.class, spec = case.spec, powerType = case.powerType })
			local res, reason = ClassPower:Compute()
			assert.equal(res and res.id or nil, case.want)
			if case.reason then
				assert.equal(reason, case.reason)
				local shown, words = ClassPower:Status()
				assert.is_false(shown)
				assert.equal(words, ClassPower.REASONS[case.reason])
			end
		end)
	end

	it('reads combo points from the target everywhere but Retail', function()
		Player({ class = 'ROGUE' })
		local res = ClassPower:Compute()
		assert.equal(res.onTarget, not retail)
		P.Caps:SetOverride('quirk:comboPointsFromPlayer', true)
		res = ClassPower:Compute()
		assert.is_false(res.onTarget, 'the quirk reads the player power instead')
		P.Caps:SetOverride('quirk:comboPointsFromPlayer', nil)
		P.Caps:SetOverride('comboTarget', false)
		res = ClassPower:Compute()
		P.Caps:SetOverride('comboTarget', nil)
		assert.is_false(res.onTarget, 'a client without GetComboPoints reads the player power')
		assert.equal(P.Caps:Get('comboTarget'), GetComboPoints ~= nil)
	end)

	it('counts fragments for Destruction shards (Retail) and embers (Mists)', function()
		Player({ class = 'WARLOCK', spec = 3 })
		local res = ClassPower:Compute()
		if not res then
			skip('no fragments on ' .. client)
		end
		assert.equal(res.mod, 10)
		assert.equal(res.count, retail and 5 or 4)
	end)

	it('uses the game maximum for the number of pips', function()
		Player({ class = 'ROGUE' })
		MAX[POWER.combo] = 7
		local res = ClassPower:Compute()
		MAX[POWER.combo] = 5
		assert.equal(res.count, 7)
	end)

	it('says the class has no points on clients without the resource', function()
		Player({ class = 'PALADIN' })
		local res, reason = ClassPower:Compute()
		if HAS[POWER.holy] then
			assert.equal(res and res.id, 'holyPower')
		else
			assert.is_nil(res)
			assert.equal(reason, 'class', 'not "you do not have these points yet"')
		end
		Player({ class = 'MAGE', spec = 1 })
		res, reason = ClassPower:Compute()
		if not HAS[POWER.arcane] then
			assert.equal(reason, 'class')
		end
	end)

	it('says "not yet" when the game gives no points of a resource the client has', function()
		if not HAS[POWER.holy] then
			skip('no holy power on ' .. client)
		end
		Player({ class = 'PALADIN' })
		Stub('UnitPowerMax', function()
			return 0
		end)
		local res, reason = ClassPower:Compute()
		assert.is_nil(res)
		assert.equal(reason, 'none')
	end)

	it('reads the maximum in whole points or in fragments, whichever the client hands back', function()
		local row = { id = 'scaleTest', max = 4, mod = 100 }
		local info = {}
		local function Answers(whole, raw, display)
			Stub('UnitPowerMax', function(_, _, unmodified)
				return unmodified and raw or whole
			end)
			Stub('UnitPowerDisplayMod', function()
				return display
			end)
		end
		Player({ class = 'WARLOCK' })
		-- Whole points: pips fill from whole points
		Answers(4, 400, 100)
		local count, mod = ClassPower.Scale(row, info, POWER.shards)
		assert.equal(count, 4)
		assert.equal(mod, 1)
		-- Fragments in both forms (raw maximum from the plain call): pips fill from fragments
		Answers(400, 400, 100)
		count, mod = ClassPower.Scale(row, info, POWER.shards)
		assert.equal(count, 4)
		assert.equal(mod, 100)
		-- No display size: the row's own size decides
		Answers(400, 400, 1)
		count, mod = ClassPower.Scale(row, info, POWER.shards)
		assert.equal(count, 4)
		assert.equal(mod, 100)
		-- A fragment row always fills part way
		row.fragments = true
		Answers(4, 40, 10)
		count, mod = ClassPower.Scale(row, info, POWER.embers)
		assert.equal(count, 4)
		assert.equal(mod, 10)
		-- A maximum of zero means none yet
		Answers(0, 0, 10)
		assert.is_nil((ClassPower.Scale(row, info, POWER.embers)))
		ClassPower.lastCount.scaleTest = nil
	end)

	it('keeps the last pip count while the game hides the maximum', function()
		if not M.secrets then
			skip('the maximum is never hidden on ' .. client)
		end
		local row = { id = 'hiddenTest', max = 5 }
		Player({ class = 'ROGUE' })
		Stub('UnitPowerMax', function()
			return 6
		end)
		assert.equal((ClassPower.Scale(row, {}, POWER.combo)), 6)
		Stub('UnitPowerMax', function()
			return S.Wrap(6)
		end)
		local count, mod = ClassPower.Scale(row, {}, POWER.combo)
		assert.equal(count, 6, 'the count shown last')
		assert.equal(mod, 1)
		ClassPower.lastCount.hiddenTest = nil
		assert.equal((ClassPower.Scale(row, {}, POWER.combo)), 5, 'the row maximum when nothing was shown yet')
	end)
end)

describe('class power: drawing', function()
	after_each(Restore)

	it('fills every pip from one secret amount without reading it', function()
		Player({ class = 'ROGUE', power = { [POWER.combo] = 3 }, combo = 3, secret = true })
		local plate, widget = NewLive()
		plate:SetState('target', true)
		assert.is_true(Shown(widget.row), 'pips show on the target')
		for i = 1, 5 do
			local pip = widget.pips[i]
			assert.equal(M.Get(pip, 'min'), i - 1)
			assert.equal(M.Get(pip, 'max'), i)
			assert.secret(M.Get(pip, 'value'))
			assert.equal(Value(pip), 3)
		end
		plate:Unbind()
	end)

	it('reads the points the game keeps for this client', function()
		Player({ class = 'ROGUE', power = { [POWER.combo] = 1 }, combo = 4 })
		local plate, widget = NewLive()
		plate:SetState('target', true)
		assert.equal(Value(widget.pips[1]), retail and 1 or 4)
		plate:Unbind()
	end)

	it('lays pips out in whole pixels, centered', function()
		Player({ class = 'ROGUE', combo = 2, power = { [POWER.combo] = 2 } })
		local plate, widget = NewLive()
		plate:SetState('target', true)
		local width = plate.style.width
		local pipW = math.floor((width - 4 * 2) / 5)
		for i = 1, 5 do
			assert.equal(M.Get(widget.pips[i], 'w'), pipW)
			assert.equal(M.Get(widget.pips[i], 'h'), 5)
		end
		plate:Unbind()
	end)

	it('shows pips only on an attackable target and never in a vehicle', function()
		Player({ class = 'ROGUE', combo = 2, power = { [POWER.combo] = 2 } })
		local plate, widget = NewLive()
		assert.is_false(Shown(widget.row), 'not the target')
		plate:SetState('target', true)
		assert.is_true(Shown(widget.row))
		plate:SetState('target', false)
		assert.is_false(Shown(widget.row))
		plate:Unbind()

		local friend, friendWidget = NewLive({ name = 'Friend', canAttack = false, reaction = 5 })
		friend:SetState('target', true)
		assert.is_false(Shown(friendWidget.row), 'a friendly target gets no pips')
		friend:Unbind()

		Player({ class = 'ROGUE', combo = 2, power = { [POWER.combo] = 2 }, vehicle = true })
		local driven, drivenWidget = NewLive()
		driven:SetState('target', true)
		assert.is_false(Shown(drivenWidget.row), 'no pips in a vehicle')
		local shown, words = ClassPower:Status()
		assert.is_false(shown)
		assert.equal(words, ClassPower.REASONS.vehicle)
		driven:Unbind()
	end)

	it('fades the row from a secret target answer', function()
		Player({ class = 'ROGUE', combo = 2, power = { [POWER.combo] = 2 } })
		local plate, widget = NewLive()
		plate:SetStateSecret('target', S.Wrap(true))
		assert.is_true(Shown(widget.row))
		assert.equal(M.Get(widget.row, 'alpha'), 1)
		plate:SetStateSecret('target', S.Wrap(false))
		assert.equal(M.Get(widget.row, 'alpha'), 0)
		plate:SetState('target', true)
		assert.equal(M.Get(widget.row, 'alpha'), 1, 'a plain answer takes over again')
		plate:Unbind()
	end)

	it('follows the player power events on the target plate only', function()
		Player({ class = 'ROGUE', combo = 1, power = { [POWER.combo] = 1 } })
		local target, targetWidget = NewLive()
		local other, otherWidget = NewLive()
		target:SetState('target', true)
		assert.is_true(ClassPower.running, 'a live plate starts the player events')
		world.combo, world.power[POWER.combo] = 4, 4
		FirePower('COMBO_POINTS')
		assert.equal(Value(targetWidget.pips[1]), 4)
		assert.is_false(Shown(otherWidget.row))
		world.combo, world.power[POWER.combo] = 5, 5
		FirePower('ENERGY')
		assert.equal(Value(targetWidget.pips[1]), 4, 'other powers do not redraw the pips')
		M.Fire('UNIT_POWER_FREQUENT', target.unit, 'COMBO_POINTS')
		assert.equal(Value(targetWidget.pips[1]), 4, 'other units never reach the player frame')
		if M.secrets then
			M.Fire('UNIT_POWER_FREQUENT', 'player', S.Wrap('COMBO_POINTS'))
			assert.equal(Value(targetWidget.pips[1]), 5, 'a hidden power token still redraws')
		end
		target:Unbind()
		other:Unbind()
	end)

	it('redraws when the game moves the combo points to another target', function()
		Player({ class = 'ROGUE', combo = 2, power = { [POWER.combo] = 2 } })
		local plate, widget = NewLive()
		plate:SetState('target', true)
		assert.equal(Value(widget.pips[1]), 2)
		world.combo, world.power[POWER.combo] = 0, 0
		M.FireIfKnown('COMBO_TARGET_CHANGED')
		assert.equal(Value(widget.pips[1]), 0)
		plate:Unbind()
	end)

	it('hides pips when a druid leaves cat form', function()
		Player({ class = 'DRUID', powerType = POWER.energy, combo = 3, power = { [POWER.combo] = 3 } })
		local plate, widget = NewLive()
		plate:SetState('target', true)
		assert.is_true(Shown(widget.row))
		world.powerType = 0
		M.FireIfKnown('UNIT_DISPLAYPOWER', 'player')
		assert.is_false(Shown(widget.row))
		local shown, words = ClassPower:Status()
		assert.is_false(shown)
		assert.equal(words, ClassPower.REASONS.form)
		plate:Unbind()
	end)

	it('fills fragment pips part way', function()
		Player({ class = 'WARLOCK', spec = 3, raw = { [POWER.shards] = 35, [POWER.embers] = 25 }, secret = true })
		local res = ClassPower:Compute()
		if not res then
			skip('no fragments on ' .. client)
		end
		local plate, widget = NewLive()
		plate:SetState('target', true)
		assert.equal(M.Get(widget.pips[2], 'min'), 10)
		assert.equal(M.Get(widget.pips[2], 'max'), 20)
		assert.equal(Value(widget.pips[1]), retail and 35 or 25)
		plate:Unbind()
	end)

	it('tints charged combo points where the game has them', function()
		if not retail then
			skip('charged combo points are a Retail feature')
		end
		Player({ class = 'ROGUE', combo = 3, power = { [POWER.combo] = 3 }, charged = { 2 } })
		local plate, widget = NewLive()
		plate:SetState('target', true)
		local charged = ClassPower.CHARGED_COLOR
		assert.near(M.Get(widget.pips[2], 'barColor')[3], charged[3], 0.001)
		assert.near(M.Get(widget.pips[1], 'barColor')[1], ClassPower:Resource().color[1], 0.001)
		plate:Unbind()
	end)
end)

describe('class power: runes', function()
	after_each(function()
		P.Scheduler:Cancel('ClassPower.runes')
		Restore()
	end)

	it('fills runes as they come back and stops ticking when all are ready', function()
		if not RUNES then
			skip('no death knights on ' .. client)
		end
		local now = GetTime()
		local runes = {}
		for i = 1, 6 do
			runes[i] = i <= 2 and { start = 0, duration = 0, ready = true } or { start = now - i, duration = 10, ready = false }
		end
		Player({ class = 'DEATHKNIGHT', spec = 2, runes = runes })
		local plate, widget = NewLive()
		plate:SetState('target', true)
		assert.equal(Value(widget.pips[1]), 1)
		assert.equal(Value(widget.pips[2]), 1)
		local before = {}
		for i = 3, 6 do
			before[i] = Value(widget.pips[i])
			assert.is_true(before[i] > 0 and before[i] < 1, 'rune ' .. i .. ' is part way back')
		end
		if not TYPED_RUNES then
			assert.is_true(Value(widget.pips[3]) >= Value(widget.pips[6]), 'runes closest to ready come first')
		end
		assert.is_true(P.Scheduler:IsRunning('ClassPower.runes'))
		M.Advance(1)
		for i = 3, 6 do
			assert.is_true(Value(widget.pips[i]) > before[i], 'rune ' .. i .. ' keeps filling')
		end
		for i = 1, 6 do
			runes[i] = { start = 0, duration = 0, ready = true }
		end
		M.FireIfKnown('RUNE_POWER_UPDATE', 1, true)
		M.Advance(0.3)
		assert.is_false(P.Scheduler:IsRunning('ClassPower.runes'), 'the tick stops when every rune is ready')
		if TYPED_RUNES then
			assert.near(M.Get(widget.pips[3], 'barColor')[2], ClassPower.RUNE_TYPE_COLORS[2][2], 0.001)
			-- The game's rune frame: type 2 is frost (blue), type 3 unholy (green)
			local frost, unholy = ClassPower.RUNE_TYPE_COLORS[2], ClassPower.RUNE_TYPE_COLORS[3]
			assert.is_true(frost[3] > frost[1] and frost[3] > frost[2], 'type 2 is blue')
			assert.is_true(unholy[2] > unholy[1] and unholy[2] > unholy[3], 'type 3 is green')
		else
			assert.near(M.Get(widget.pips[1], 'barColor')[3], ClassPower.RUNE_SPEC_COLORS[2][3], 0.001)
		end
		plate:Unbind()
	end)
end)

describe('class power: previews and stopping', function()
	after_each(Restore)

	it('previews draw the sample points on the sample target', function()
		Player({ class = 'ROGUE' })
		local plate = P.Plate.New(UIParent, true)
		plate:ApplyStyle(Merge:Resolve('clean', 'enemyNPC', 'medium'))
		plate:BindSample(P.Source.NewSample('casterTarget'))
		local widget = plate:GetWidget('power')
		assert.is_true(Shown(widget.row))
		assert.equal(Value(widget.pips[1]), 3)
		plate:Unbind()
	end)

	it('previews show sample combo points for a player without points', function()
		Player({ class = 'WARRIOR' })
		local plate = P.Plate.New(UIParent, true)
		plate:ApplyStyle(Merge:Resolve('clean', 'enemyNPC', 'medium'))
		plate:BindSample(P.Source.NewSample('casterTarget'))
		local widget = plate:GetWidget('power')
		assert.is_true(Shown(widget.row))
		assert.equal(widget.count, 5)
		plate:Unbind()
	end)

	it('stops listening when the engine turns off', function()
		Player({ class = 'ROGUE', combo = 1, power = { [POWER.combo] = 1 } })
		local plate = NewLive()
		plate:SetState('target', true)
		assert.is_true(ClassPower.running)
		assert.is_true(#M.RegisteredEvents(ClassPower.events) > 0)
		P:Fire('ENGINE_DISABLED')
		assert.is_false(ClassPower.running)
		assert.equal(#M.RegisteredEvents(ClassPower.events), 0)
		plate:Unbind()
	end)
end)

describe('class power: with the engine running', function()
	after_each(function()
		if P.enabled then
			P:Disable()
		end
		Restore()
	end)

	it('shows pips on the plate the player targets, and only there', function()
		Player({ class = 'ROGUE', combo = 2, power = { [POWER.combo] = 2 } })
		P:Enable()
		local token, base = M.ShowPlate({ name = 'Ogre', canAttack = true, reaction = 2 })
		local other, otherBase = M.ShowPlate({ name = 'Ogre Brute', canAttack = true, reaction = 2 })
		local plate = P.API:GetPlate(base)
		local widget = plate and plate:GetWidget('power')
		if not widget then
			M.HidePlate(token)
			M.HidePlate(other)
			skip('the Driver does not draw a style with points on this plate in this build')
		end
		local otherWidget = P.API:GetPlate(otherBase):GetWidget('power')
		assert.is_false(Shown(widget.row), 'no pips before targeting')
		M.SetTarget(token)
		assert.is_true(Shown(widget.row), 'pips on the target')
		assert.equal(Value(widget.pips[1]), 2)
		assert.is_false(Shown(otherWidget.row), 'none on other plates')
		world.combo, world.power[POWER.combo] = 3, 3
		FirePower('COMBO_POINTS')
		assert.equal(Value(widget.pips[1]), 3)
		M.SetTarget(other)
		assert.is_false(Shown(widget.row))
		assert.is_true(Shown(otherWidget.row), 'pips follow the target')
		M.SetTarget(nil)
		assert.is_false(Shown(otherWidget.row))
		M.HidePlate(token)
		M.HidePlate(other)
	end)
end)
