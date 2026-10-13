-- @runtime lua51
-- End to end (stage B): the core and the SpartanUI host load in LoadAll.xml order, and one play
-- session runs on each client: 40 plates of mixed kinds, target, focus and mouseover moves, casts
-- with the interrupt ready and not ready, combat,
-- restricted mode on clients with secrets, style, size and color changes through the Store, a
-- profile switch, leaving combat, every plate removed, and the engine turned off.
--
-- What it guards:
--   * no Lua errors and no secret misuse (the strict mock raises on both, and the test fails on
--     anything sent to the error handler);
--   * nothing protected in combat: no function the docs mark HasRestrictions, no secure setting,
--     and no method the docs mark IsProtectedFunction on Blizzard's own (protected) plate frames
--     while combat lockdown is on;
--   * game settings, plate size and click insets are given back when the engine stops;
--   * every plate is reset when its unit goes away, and no per-frame work is left behind;
--   * a second identical session creates no new frames, textures or font strings.
local M, H = ...
local S = M.S

if not (H.ModuleExists() and H.Exists(H.hostFile)) then
	describe('engine end to end', function()
		pending('all', 'the nameplate module or its host does not exist yet')
	end)
	return
end

----------------------------------------------------------------------------------------------------
-- The protected world: Blizzard's base plates and their unit frames are protected, and calls the
-- docs mark IsProtectedFunction on them during combat lockdown are recorded as violations.
----------------------------------------------------------------------------------------------------

local protectedFrames = setmetatable({}, { __mode = 'k' })
local knownBases = 0

local function RefreshProtected()
	local bases = M.Bases()
	if #bases == knownBases then
		return
	end
	knownBases = #bases
	for _, base in ipairs(bases) do
		protectedFrames[base] = true
		if base.UnitFrame then
			protectedFrames[base.UnitFrame] = true
		end
	end
end

local violations = {}

local function InstallProtectedWorld()
	for typeName in pairs(M.TYPES) do
		local cls = M.Class(typeName)
		local methods, specs = cls.methods, cls.specs
		if methods.IsProtected then
			local real = methods.IsProtected
			methods.IsProtected = function(self, ...)
				RefreshProtected()
				if protectedFrames[self] then
					return true, true
				end
				return real(self, ...)
			end
		end
		for name, spec in pairs(specs) do
			local flags = M.ParseSpec(spec).flags
			if flags.IsProtectedFunction and methods[name] then
				local real = methods[name]
				methods[name] = function(self, ...)
					if M.lockdown then
						RefreshProtected()
						if protectedFrames[self] then
							violations[#violations + 1] = typeName .. ':' .. name .. ' at ' .. M.Caller()
						end
					end
					return real(self, ...)
				end
			end
		end
	end
end
InstallProtectedWorld()

-- Every object the client creates, by type (frames, regions, animations, script objects)
local created = {}
local realNewObject = M.NewObject
M.NewObject = function(typeName, name, parent)
	created[typeName] = (created[typeName] or 0) + 1
	return realNewObject(typeName, name, parent)
end

local function IsWidgetType(typeName)
	local info = M.TYPES[typeName]
	return info ~= nil and (info.frame or info.region or info.animation or info.internal or typeName == 'AnimationGroup' or typeName == 'Font') and true or false
end

local function CountCreated()
	local out = {}
	for typeName, count in pairs(created) do
		out[typeName] = count
	end
	return out
end

local function NewSince(before)
	local widgets, scripts = {}, {}
	for typeName, count in pairs(created) do
		local delta = count - (before[typeName] or 0)
		if delta > 0 then
			if IsWidgetType(typeName) then
				widgets[typeName] = delta
			else
				scripts[typeName] = delta
			end
		end
	end
	return widgets, scripts
end

local function Note(text)
	io.write('@@NOTE ' .. text .. '\n')
end

----------------------------------------------------------------------------------------------------
-- The world before login: secure nameplate settings, values the engine must give back
----------------------------------------------------------------------------------------------------

for name, c in pairs(M.cvars) do
	if name:lower():find('^nameplate') then
		c.secure = true
	end
end
local PLAYER_VALUES = {
	nameplateShowEnemies = '1',
	nameplateShowFriendlyNpcs = '1',
	nameplateMinScale = '0.8',
	nameplateMaxScale = '1',
	nameplateSelectedScale = '1.2',
	nameplateOccludedAlphaMult = '0.4',
	nameplateStackingTypes = '0',
	nameplateEnemyNpcAuraDisplay = '7',
	nameplateEnemyPlayerAuraDisplay = '7',
}
for name, value in pairs(PLAYER_VALUES) do
	if M.cvars[name] then
		M.SetCVarState(name, { value = value })
	end
end
local cvarsBefore = {}
for name, c in pairs(M.cvars) do
	cvarsBefore[name] = c.value
end
local plateSizeBefore = { M.plateSize[1], M.plateSize[2] }

local SUI, ns, module = H.LoadNameplatesLikeTheGame()
local P = ns.Plates
local Driver, Store = P.Driver, P.Store

----------------------------------------------------------------------------------------------------
-- The player's interrupt: known, with a cooldown the test controls (secret while restricted)
----------------------------------------------------------------------------------------------------

local kickLeft = 0
local function SwapIn(tbl, name, value)
	if tbl and rawget(tbl, name) ~= nil then
		rawset(tbl, name, value)
	end
end
local function Known()
	return true
end
SwapIn(C_SpellBook, 'IsSpellKnownOrInSpellBook', Known)
SwapIn(C_SpellBook, 'IsSpellKnown', Known)
SwapIn(_G, 'IsSpellKnown', Known)
SwapIn(C_Spell, 'GetSpellCooldownDuration', function()
	local d = C_DurationUtil.CreateDuration()
	local finish = M.now + kickLeft
	d:SetTimeFromStart(M.now, kickLeft)
	local function Wrap(v)
		return M.restrict.on and S.Wrap(v) or v
	end
	d.GetRemainingDuration = function()
		return Wrap(math.max(0, finish - M.now))
	end
	d.IsZero = function()
		return Wrap(M.now >= finish)
	end
	return d
end)

local function SetKick(left)
	kickLeft = left
	M.FireIfKnown('SPELL_UPDATE_COOLDOWN')
	M.Advance(0.25)
end

----------------------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------------------

local function Shown(region)
	return M.Get(region, 'shown') == true
end

local function Near(a, b)
	return math.abs(a - b) < 0.001
end

local function BarColor(bar)
	local c = M.Get(bar, 'barColor')
	if not c then
		return nil
	end
	return { S.Reveal(c[1]), S.Reveal(c[2]), S.Reveal(c[3]) }
end

local function SameColor(got, want)
	return got ~= nil and Near(got[1], want[1]) and Near(got[2], want[2]) and Near(got[3], want[3])
end

local function Count(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

local function PlateOf(token)
	return P.API:GetPlate(M.plates[token])
end

-- Mixed kinds: 12 enemy NPCs (10 casters, 2 bosses), 8 minor, 6 enemy players, 6 friendly
-- players, 8 friendly NPCs = 40 plates; friendly NPCs are hidden by default (Show mode)
local KIND_COUNTS = { enemyNPC = 12, minor = 8, enemyPlayer = 6, friendlyPlayer = 6, friendlyNPC = 8 }
local DRAWN = 32

local function Specs(cycle)
	local list = {}
	local function Add(kind, spec)
		spec.name = spec.name .. ' ' .. cycle .. '.' .. (#list + 1)
		list[#list + 1] = { kind = kind, spec = spec }
	end
	for i = 1, 10 do
		Add('enemyNPC', {
			name = 'Caster',
			canAttack = true,
			reaction = 2,
			classification = (i == 7 and 'rare') or (i % 3 == 0 and 'elite') or 'normal',
			powerType = 0,
			power = 1000,
			powerMax = 1000,
			raidMarker = i <= 3 and i or nil,
			health = 800 + i,
			healthMax = 1000,
			npcID = 2000 + i,
			inCombat = false,
		})
	end
	for i = 1, 2 do
		Add('enemyNPC', { name = 'Boss', canAttack = true, reaction = 2, classification = 'worldboss', isBoss = true, level = -1, health = 90000, healthMax = 100000, npcID = 3000 + i })
	end
	for _ = 1, 8 do
		Add('minor', { name = 'Rat', canAttack = true, reaction = 2, classification = 'minus', health = 40, healthMax = 50 })
	end
	for i = 1, 6 do
		Add('enemyPlayer', { name = 'Rogue', isPlayer = true, canAttack = true, reaction = 2, class = 'ROGUE', className = 'Rogue', classID = 4, health = 3000 + i, healthMax = 4000 })
	end
	for _ = 1, 6 do
		Add('friendlyPlayer', { name = 'Priest', isPlayer = true, canAttack = false, canAssist = true, reaction = 5, class = 'PRIEST', className = 'Priest', classID = 5 })
	end
	for _ = 1, 8 do
		Add('friendlyNPC', { name = 'Guard', canAttack = false, canAssist = true, reaction = 5 })
	end
	return list
end

---One session's world: units, tokens and bases in show order.
local world

local function ShowAll(cycle)
	world = { entries = Specs(cycle), tokens = {}, units = {}, bases = {}, byKind = {} }
	for i, entry in ipairs(world.entries) do
		local token, base, unit = M.ShowPlate(entry.spec)
		world.tokens[i], world.bases[i], world.units[i] = token, base, unit
		world.byKind[entry.kind] = world.byKind[entry.kind] or {}
		local group = world.byKind[entry.kind]
		group[#group + 1] = i
	end
end

local function Unit(kind, n)
	return world.units[world.byKind[kind][n]]
end

local function Token(kind, n)
	return world.tokens[world.byKind[kind][n]]
end

local function SetSettings()
	Store:Batch(function()
		Store:Set('behavior', {
			enemies = 'combat',
			stacking = { enemy = true, friendly = true },
			pinScale = true,
			fadeBehindWalls = 0.2,
			fadeBehindWallsCombat = 0.6,
			clickThroughFriendly = true,
		})
		Store:Set('modes', { friendlyNPC = 'hidden' })
		Store:Set('threat', { when = 'everywhere' })
	end)
end

local function ChangeLook()
	Store:Batch(function()
		Store:Set('style', 'clean')
		Store:Set('size', 'large')
		Store:Set('scheme', 'class')
		Store:Set('colorBlind', true)
		Store:Set('tweaks.clean.changes.parts.name.font.size', 12)
		Store:Set('colors.health.order', { 'lowHealth', 'reaction' })
		Store:Set('auras.myDebuffs', { on = true, onlyMine = false })
	end)
end

local function ResetSettings()
	Store:Batch(function()
		for _, key in ipairs({ 'behavior', 'modes', 'threat', 'tweaks', 'colors', 'auras', 'style', 'size', 'scheme', 'colorBlind' }) do
			Store:Set(key, nil)
		end
	end)
end

local function HideAll()
	for i = #world.tokens, 1, -1 do
		M.HidePlate(world.tokens[i])
	end
	M.SetTarget(nil)
	M.SetFocus(nil)
	M.SetMouseover(nil)
end

---Assert no protected work happened, and start a new record.
local function AssertNothingProtected(where)
	local blocked = {}
	for _, entry in ipairs(M.rec.blocked) do
		blocked[#blocked + 1] = entry.label .. ' at ' .. tostring(entry.where)
	end
	assert.empty(blocked, where .. ': blocked in combat')
	assert.empty(violations, where .. ': protected frame changed in combat')
end

---Every step of one session, without the checks the first session makes along the way.
local function Session(cycle)
	SetSettings()
	ShowAll(cycle)
	for n = 1, 3 do
		M.ApplyAura(Unit('enemyNPC', n), { spellId = 116, name = 'Frostbolt', isHarmful = true, sourceUnit = 'player', duration = 8, dispelName = 'Magic' })
	end
	M.ApplyAura(Unit('enemyNPC', 4), { spellId = 118, name = 'Polymorph', isHarmful = true, sourceUnit = 'player', duration = 50, tags = { CROWD_CONTROL = true } })
	M.ApplyAura(Unit('enemyNPC', 5), { spellId = 1459, name = 'Arcane Intellect', isHarmful = false, isStealable = true, dispelName = 'Magic', duration = 3600 })
	M.SetThreat(Unit('enemyNPC', 1), M.player, { status = 3, scaledPercent = 100, rawPercent = 110, value = 5000 })
	M.SetThreat(Unit('enemyNPC', 2), M.player, { status = 1, scaledPercent = 90, rawPercent = 95, value = 4000 })
	M.Advance(0.5)

	M.SetTarget(Unit('enemyNPC', 1))
	M.SetFocus(Unit('enemyNPC', 2))
	M.SetMouseover(Unit('enemyPlayer', 1))
	M.Advance(0.3)
	M.SetTarget(Unit('enemyNPC', 3))
	M.SetMouseover(nil)
	M.Advance(0.3)

	M.FireIfKnown('SPELLS_CHANGED')
	M.Advance(0.1)
	SetKick(0)
	M.StartCast(Unit('enemyNPC', 5), { name = 'Shadow Bolt', spellID = 686, duration = 2.5 })
	M.StartCast(Unit('enemyNPC', 11), { name = 'Doom', spellID = 603, duration = 3, channel = true, notInterruptible = true })
	M.Advance(0.3)
	SetKick(10)
	M.Advance(0.3)

	M.EnterCombat()
	for i = 1, 12 do
		M.UpdateUnit(Unit('enemyNPC', i), { inCombat = true }, { 'UNIT_FLAGS' })
	end
	M.Advance(0.3)
	M.SetRestricted(true)
	M.Advance(0.3)
	M.SetTarget(Unit('enemyNPC', 6))
	M.SetFocus(Unit('minor', 1))
	M.SetMouseover(Unit('enemyPlayer', 2))
	M.UpdateUnit(Unit('enemyNPC', 6), { health = 200 }, { 'UNIT_HEALTH' })
	M.StartCast(Unit('enemyNPC', 6), { name = 'Fireball', spellID = 133, duration = 2 })
	M.ApplyAura(Unit('enemyNPC', 6), { spellId = 116, name = 'Frostbolt', isHarmful = true, sourceUnit = 'player', duration = 8 })
	SetKick(0)
	M.Advance(0.5)
	ChangeLook()
	M.Advance(0.3)
	Store:SetProfile('E2E Raid')
	M.Advance(0.3)
	Store:SetProfile('Default')
	M.Advance(0.3)
	M.StopCast(Unit('enemyNPC', 6), 'interrupted')
	M.Advance(0.5)

	M.LeaveCombat()
	M.SetRestricted(false)
	M.Advance(0.5)
	ResetSettings()
	M.Advance(0.5)
	HideAll()
	M.Advance(2)
end

----------------------------------------------------------------------------------------------------
-- Session one, checked step by step
----------------------------------------------------------------------------------------------------

describe('engine end to end', function()
	it('logs in and starts the engine', function()
		M.Login('SpartanUI')
		M.Advance(3)
		assert.is_true(P.enabled, 'the engine is on')
		assert.is_true(Driver.active)
		assert.is_true(Driver.standing, 'drawing for this profile')
		SetSettings()
		AssertNothingProtected('login')
	end)

	it('draws 40 plates of mixed kinds', function()
		ShowAll(1)
		M.Advance(0.5)
		local modes = {}
		for i, entry in ipairs(world.entries) do
			local plate = Driver.byBase[world.bases[i]]
			assert.not_nil(plate, entry.spec.name .. ' has a plate')
			assert.equal(plate.situation, entry.kind, entry.spec.name)
			local mode = Driver:ModeOf(plate)
			modes[mode] = (modes[mode] or 0) + 1
			if entry.kind == 'friendlyNPC' then
				assert.equal(mode, 'hidden', 'friendly NPCs are hidden by default')
				assert.is_false(Shown(plate.root))
			else
				assert.equal(mode, 'drawn', entry.spec.name)
				assert.is_true(Shown(plate.root), entry.spec.name .. ' shows')
			end
		end
		assert.equal(Driver:CountBound(), DRAWN)
		assert.equal(PlateOf(Token('minor', 1)).style.id, 'mini', 'minor enemies get the small style')
		assert.equal(PlateOf(Token('friendlyPlayer', 1)).style.id, 'namesOnly', 'friendly players show names only')
		assert.equal(PlateOf(Token('enemyNPC', 1)).style.id, 'spartanui', 'Match my look by default')
		local health = P.API:GetHealthBar(world.bases[1])
		assert.not_nil(health, 'the health bar is there for other addons')
		assert.equal(S.Reveal(M.Get(health, 'value')), Unit('enemyNPC', 1).health)
		for kind, count in pairs(KIND_COUNTS) do
			assert.equal(#world.byKind[kind], count, kind)
		end
	end)

	it('shows auras and threat', function()
		for n = 1, 3 do
			M.ApplyAura(Unit('enemyNPC', n), { spellId = 116, name = 'Frostbolt', isHarmful = true, sourceUnit = 'player', duration = 8, dispelName = 'Magic' })
		end
		M.ApplyAura(Unit('enemyNPC', 4), { spellId = 118, name = 'Polymorph', isHarmful = true, sourceUnit = 'player', duration = 50, tags = { CROWD_CONTROL = true } })
		M.ApplyAura(Unit('enemyNPC', 5), { spellId = 1459, name = 'Arcane Intellect', isHarmful = false, isStealable = true, dispelName = 'Magic', duration = 3600 })
		M.SetThreat(Unit('enemyNPC', 1), M.player, { status = 3, scaledPercent = 100, rawPercent = 110, value = 5000 })
		M.SetThreat(Unit('enemyNPC', 2), M.player, { status = 1, scaledPercent = 90, rawPercent = 95, value = 4000 })
		M.Advance(0.5)
		assert.not_nil(PlateOf(Token('enemyNPC', 1)):GetWidget('mine'), 'the aura row is drawn')
	end)

	it('moves target, focus and mouseover by frame compare', function()
		local first, second, rogue = PlateOf(Token('enemyNPC', 1)), PlateOf(Token('enemyNPC', 2)), PlateOf(Token('enemyPlayer', 1))
		M.SetTarget(Unit('enemyNPC', 1))
		M.SetFocus(Unit('enemyNPC', 2))
		M.SetMouseover(Unit('enemyPlayer', 1))
		M.Advance(0.3)
		assert.is_true(first.states.target == true)
		assert.is_true(second.states.focus == true)
		assert.is_true(rogue.states.mouseover == true)
		assert.is_true(P.Context.hasTarget)
		local third = PlateOf(Token('enemyNPC', 3))
		M.SetTarget(Unit('enemyNPC', 3))
		M.SetMouseover(nil)
		M.Advance(0.3)
		assert.is_nil(first.states.target, 'the old target lets go')
		assert.is_true(third.states.target == true)
		assert.is_nil(rogue.states.mouseover, 'mouseover clears after the mouse leaves')
		assert.is_false(P.Scheduler:IsRunning('Driver.mouseover'))
	end)

	it('colors a cast by whether the interrupt is ready', function()
		M.FireIfKnown('SPELLS_CHANGED')
		M.Advance(0.1)
		assert.not_nil(P.Context.kickSpell, 'the interrupt is picked')
		SetKick(0)
		local caster = Unit('enemyNPC', 5)
		local widget = PlateOf(Token('enemyNPC', 5)):GetWidget('cast')
		M.StartCast(caster, { name = 'Shadow Bolt', spellID = 686, duration = 2.5 })
		M.StartCast(Unit('enemyNPC', 11), { name = 'Doom', spellID = 603, duration = 3, channel = true, notInterruptible = true })
		M.Advance(0.3)
		assert.is_true(Shown(widget.content), 'the cast shows')
		local ready = P.Colors:GetKind('interruptReady').default
		assert.is_true(SameColor(BarColor(widget.bar), ready), 'green while the interrupt is ready')
		SetKick(10)
		assert.is_true(SameColor(BarColor(widget.bar), P.Colors.FALLBACK.cast), 'normal while it cools down')
		assert.is_true(P.Scheduler:IsRunning('Driver.kick'), 'the interrupt is watched while it cools down')
	end)

	it('enters combat, then restricted mode where the client has secrets', function()
		M.ResetRecords()
		M.EnterCombat()
		for i = 1, 12 do
			M.UpdateUnit(Unit('enemyNPC', i), { inCombat = true }, { 'UNIT_FLAGS' })
		end
		M.Advance(0.3)
		assert.is_true(P.Context.inCombat)
		local restricted = M.SetRestricted(true)
		M.Advance(0.3)
		assert.equal(P.Secret.IsRestricted(), true)
		-- Under secrets nothing can be compared, so states come from hidden answers (S4)
		M.SetTarget(Unit('enemyNPC', 6))
		M.SetFocus(Unit('minor', 1))
		M.SetMouseover(Unit('enemyPlayer', 2))
		M.UpdateUnit(Unit('enemyNPC', 6), { health = 200 }, { 'UNIT_HEALTH' })
		M.StartCast(Unit('enemyNPC', 6), { name = 'Fireball', spellID = 133, duration = 2 })
		M.ApplyAura(Unit('enemyNPC', 6), { spellId = 116, name = 'Frostbolt', isHarmful = true, sourceUnit = 'player', duration = 8 })
		SetKick(0)
		M.Advance(0.5)
		if restricted then
			assert.secret(UnitHealth(Token('enemyNPC', 6)), 'values are hidden')
			assert.is_true(Driver.secretStates.target == true, 'the target is known only as a hidden answer')
			assert.is_false(P.Context.hasTarget, 'nothing fades other plates while the target is hidden')
		else
			assert.is_true(PlateOf(Token('enemyNPC', 6)).states.target == true)
		end
		AssertNothingProtected('combat')
	end)

	it('changes style, size and colors through the Store in combat', function()
		ChangeLook()
		M.Advance(0.3)
		local plate = PlateOf(Token('enemyNPC', 1))
		assert.equal(plate.style.id, 'clean')
		assert.equal(plate.style.sizeKey, 'large')
		assert.equal(PlateOf(Token('minor', 1)).style.id, 'mini', 'minor enemies keep their own style')
		if P.Secret.IsRestricted() then
			assert.is_true(plate.pendingConfigure == true, 'aura settings wait for the lock to lift')
		end
		assert.equal(M.plateSize[1], Driver.appliedSize[1], 'the plate size waits for combat to end')
		AssertNothingProtected('style change in combat')
	end)

	it('switches profiles and back in combat', function()
		Store:SetProfile('E2E Raid')
		M.Advance(0.3)
		local plate = PlateOf(Token('enemyNPC', 1))
		assert.equal(plate.style.id, 'spartanui', 'the new profile has its own style')
		assert.equal(plate.style.sizeKey, 'medium')
		Store:SetProfile('Default')
		M.Advance(0.3)
		assert.equal(PlateOf(Token('enemyNPC', 1)).style.id, 'clean')
		M.StopCast(Unit('enemyNPC', 6), 'interrupted')
		M.Advance(0.5)
		AssertNothingProtected('profile switch in combat')
	end)

	it('catches up when combat ends', function()
		M.LeaveCombat()
		M.SetRestricted(false)
		M.Advance(0.5)
		assert.is_false(P.Context.inCombat)
		assert.is_false(P.Secret.IsRestricted())
		for plate in pairs(Driver.bound) do
			assert.is_nil(plate.pendingConfigure, 'waiting aura settings went through')
		end
		assert.is_false(P.CVars:HasQueued(), 'settings locked in combat were written')
		assert.same(M.plateSize, { Driver.appliedSize[1], Driver.appliedSize[2] }, 'the plate size was written')
		assert.is_true(Driver.appliedSize[1] > 0)
		-- A plain target again: the states come back from frame compare
		M.SetTarget(Unit('enemyNPC', 2))
		M.Advance(0.2)
		assert.is_true(PlateOf(Token('enemyNPC', 2)).states.target == true)
		assert.is_nil(Driver.secretStates.target)
		ResetSettings()
		M.Advance(0.5)
		assert.equal(PlateOf(Token('enemyNPC', 1)).style.id, 'spartanui')
	end)

	it('resets every plate when all units go away and leaves no per-frame work', function()
		local resets = {}
		local wrapped = {}
		for id, impl in pairs(P.Parts.impls) do
			local real = impl.Reset
			wrapped[id] = real
			impl.Reset = function(widget)
				resets[widget] = (resets[widget] or 0) + 1
				return real(widget)
			end
		end
		local active = {}
		for plate in pairs(Driver.bound) do
			for _, widget in ipairs(plate.active) do
				active[#active + 1] = widget
			end
		end
		HideAll()
		M.Advance(2)
		for id, real in pairs(wrapped) do
			P.Parts.impls[id].Reset = real
		end
		assert.equal(Driver:CountBound(), 0)
		for _, widget in ipairs(active) do
			assert.is_true((resets[widget] or 0) >= 1, widget.id .. ' was reset')
		end
		for _, plate in pairs(Driver.byBase) do
			assert.is_nil(plate.unit)
			assert.is_nil(plate.src)
			assert.is_nil(next(plate.states), 'no state is left on')
			assert.is_false(Shown(plate.root))
			assert.is_nil(Driver:ModeOf(plate))
		end
		assert.equal(#Driver.list, 0, 'the fact poller has no plates')
		assert.is_nil(next(P.Scheduler.tasks), 'no repeating tasks')
		assert.is_nil(next(P.Scheduler.eases), 'no eases')
		assert.equal(#M.ActiveOnUpdates(), 0, 'nothing runs every frame')
		AssertNothingProtected('session one')
	end)

	it('creates no new frames in a second identical session', function()
		local before = CountCreated()
		Session(2)
		local widgets, scripts = NewSince(before)
		local parts = {}
		for typeName, n in pairs(scripts) do
			parts[#parts + 1] = typeName .. ' ' .. n
		end
		table.sort(parts)
		Note(('%s second session: script objects made %s'):format(FLAVOR, #parts > 0 and table.concat(parts, ', ') or 'none'))
		assert.same(widgets, {}, 'frames, regions and animations are all reused')
		assert.equal(Driver:CountBound(), 0)
		AssertNothingProtected('session two')
	end)

	it('gives everything back when the engine is turned off', function()
		SetSettings()
		ShowAll(3)
		M.Advance(0.5)
		assert.equal(Driver:CountBound(), DRAWN)
		local touched = {}
		for i = 1, #world.bases do
			touched[i] = world.bases[i].UnitFrame
		end
		HideAll()
		module:Disable()
		M.Advance(1)
		assert.is_false(P.enabled)
		local changed = {}
		for name, value in pairs(cvarsBefore) do
			local now = M.cvars[name] and M.cvars[name].value
			if now ~= value then
				changed[#changed + 1] = name .. ' = ' .. tostring(now) .. ' (was ' .. tostring(value) .. ')'
			end
		end
		assert.empty(changed, 'every game setting is back')
		assert.same(M.plateSize, plateSizeBefore, 'the game plate size is back')
		local insets = M.FnCalls('C_NamePlateManager.SetNamePlateHitTestInsets')
		if #insets > 0 then
			local last = insets[#insets]
			assert.same({ last[2], last[3], last[4], last[5] }, { 0, 0, 0, 0 }, 'click insets are back')
		end
		for i, unitFrame in ipairs(touched) do
			assert.equal(M.Get(unitFrame, 'alpha'), 1, 'Blizzard plate ' .. i .. ' draws again')
			assert.is_false(P.Suppress:WasTouched(unitFrame))
		end
		assert.equal(P:RegisteredEventCount(), 0, 'no game events left')
		assert.is_nil(next(P.Scheduler.tasks))
		assert.equal(#M.ActiveOnUpdates(), 0)
		assert.equal(Count(Driver.bound), 0)
	end)

	it('starts again and stops again cleanly', function()
		module:Enable()
		M.Advance(1)
		assert.is_true(P.enabled)
		local before = CountCreated()
		ShowAll(4)
		M.Advance(0.5)
		assert.equal(Driver:CountBound(), DRAWN)
		HideAll()
		M.Advance(1)
		local widgets = NewSince(before)
		assert.same(widgets, {}, 'plates built in the first run are reused')
		module:Disable()
		M.Advance(1)
		local changed = {}
		for name, value in pairs(cvarsBefore) do
			local now = M.cvars[name] and M.cvars[name].value
			if now ~= value then
				changed[#changed + 1] = name
			end
		end
		assert.empty(changed, 'every game setting is back again')
		AssertNothingProtected('restart')
	end)
end)
