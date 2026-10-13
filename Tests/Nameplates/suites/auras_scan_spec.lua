-- @runtime lua51
-- Aura rows on the Lua scan path (Engine/Parts/AurasScan.lua) and the spell data behind them
-- (Data/CrowdControl.lua, Data/TankDebuffs.lua), on every client: live plates on the Classic family
-- (My debuffs with tank debuffs from anyone, enemy buffs you can remove, crowd control from the
-- spell list, the game's spell flag or the filter token, the custom list), always and never lists
-- by id and by name, sorting, stack and timer text, the pandemic glow, UNIT_AURA filtering, sample
-- icons in previews (strict secrets on Retail and Forever), the presence conditions behind the
-- "My debuff is missing" color row, and the per-client spell tables.
local M, H = ...
local S = M.S

if not H.ModuleExists() then
	describe('aura scan rows', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

M.Login('NameplatesTestHost')
local P = H.FreshCore()
local Scan = P.AuraScan
local CLASSIC = not P.Caps:Get('secrets')
local CLIENT = P.Caps:Client()

local function A(row, extra)
	local part = { kind = 'auras', row = row, anchor = { 'BOTTOMLEFT', 'plate', 'TOPLEFT', 0, 2 }, max = 6, size = 18 }
	for k, v in pairs(extra or {}) do
		part[k] = v
	end
	return part
end

local STYLE = {
	id = 'scanTest',
	name = 'Scan test',
	version = 1,
	schema = 1,
	order = 992,
	internal = true,
	plate = { sizes = { small = { 100, 8 }, medium = { 120, 10 }, large = { 140, 12 } } },
	parts = {
		health = { order = 1, kind = 'bar', source = 'health', fill = 'plate' },
		debuffs = A('myDebuffs', { order = 10, pandemic = true, borderStyle = 'dispel' }),
		buffs = A('removable', { order = 11, anchor = { 'BOTTOMRIGHT', 'plate', 'TOPRIGHT', 0, 2 }, grow = 'LEFT', max = 3, borderStyle = 'dispel' }),
		cc = A('crowdControl', { order = 12, anchor = { 'LEFT', 'plate', 'RIGHT', 2, 0 }, max = 2 }),
		custom = A('custom', { order = 13, anchor = { 'TOP', 'plate', 'BOTTOM', 0, -2 }, max = 4, sort = 'name' }),
	},
}

local function Register(core)
	core.Styles.Registry:RegisterBuiltin(STYLE)
	return core
end
Register(P)

local function Live(spec, core)
	core = core or P
	local token, base, unit = M.ShowPlate(spec)
	local plate = core.Plate.New(UIParent, false)
	local src = core.Source.NewLive(token)
	src:ReadFacts(plate.facts)
	plate:ApplyStyle(core.Styles.Merge:Resolve('scanTest', 'enemyNPC', 'medium'))
	plate:Bind(token, src)
	return plate, unit, token
end

local function Preview(sample, core)
	core = core or P
	local plate = core.Plate.New(UIParent, true)
	plate:ApplyStyle(core.Styles.Merge:Resolve('scanTest', 'enemyNPC', 'medium'))
	plate:BindSample(core.Source.NewSample(sample))
	return plate
end

local function Done(plate, token)
	plate:Unbind()
	if token then
		M.HidePlate(token)
	end
end

local ENEMY = { name = 'Gnoll', canAttack = true, reaction = 2, health = 100, healthMax = 100 }
local FRIEND = { name = 'Guard', canAttack = false, reaction = 5, health = 100, healthMax = 100 }

---Shown icons of a part, and the texture each one shows (icons are given ids as textures).
local function Shown(plate, id)
	local widget = plate:GetWidget(id)
	assert.not_nil(widget, 'part ' .. id)
	local icons, textures = {}, {}
	for _, icon in ipairs(widget.icons) do
		if icon:IsShown() then
			icons[#icons + 1] = icon
			textures[#textures + 1] = M.Get(icon.texture, 'texture')
		end
	end
	return textures, icons, widget
end

local function Mine(spellId, extra)
	local aura = { spellId = spellId, icon = spellId, isHarmful = true, sourceUnit = 'player', duration = 20 }
	for k, v in pairs(extra or {}) do
		aura[k] = v
	end
	return aura
end

local function Other(spellId, extra)
	local aura = Mine(spellId, extra)
	aura.sourceUnit = (extra and extra.sourceUnit) or 'party1'
	return aura
end

local function FirstKey(map)
	local best
	for key in pairs(map) do
		if not best or key < best then
			best = key
		end
	end
	return best
end

local function NeedsClassic()
	if not CLASSIC then
		skip('live plates on clients with secrets use aura containers, not the scan')
	end
end

describe('aura scan: data', function()
	it('builds tank debuffs per client tier, every rank', function()
		local era = P.Data.TankDebuffsFor('era')
		assert.equal(era[7386], 'sunder')
		assert.equal(era[11597], 'sunder')
		assert.equal(era[99], 'demoRoar')
		assert.is_nil(era[25225], 'TBC ranks stay out of Era')
		assert.same(P.Data.TankDebuffsFor('forever'), era, 'Forever runs Classic content')
		assert.equal(P.Data.TankDebuffsFor('tbc')[25225], 'sunder')
		local wrath = P.Data.TankDebuffsFor('titan')
		assert.equal(wrath[58567], 'sunder', "Wrath's Sunder Armor debuff")
		assert.equal(wrath[55095], 'frostFever')
		local mists = P.Data.TankDebuffsFor('mists')
		assert.equal(mists[113746], 'weakenedArmor')
		assert.equal(mists[115798], 'weakenedBlows')
		assert.is_nil(mists[7386], 'Mists folds Sunder Armor into Weakened Armor')
		assert.is_nil(next(P.Data.TankDebuffsFor('retail')), 'Retail has none')
	end)

	it('builds crowd control per client tier, every rank', function()
		local era = P.Data.CrowdControlFor('era')
		for _, id in ipairs({ 118, 12824, 12825, 12826, 853, 10308, 6770, 11297, 3355, 14309, 20549 }) do
			assert.not_nil(era[id], 'era ' .. id)
		end
		assert.is_nil(era[115078], 'no monks in Era')
		assert.equal(P.Data.CrowdControlFor('tbc')[33786], 'disorient', 'Cyclone')
		assert.equal(P.Data.CrowdControlFor('titan')[51514], 'incapacitate', 'Hex')
		local mists = P.Data.CrowdControlFor('mists')
		assert.equal(mists[115078], 'incapacitate', 'Paralysis')
		assert.equal(mists[99], 'incapacitate', 'Mists reuses 99 for Disorienting Roar')
		assert.is_nil(next(P.Data.CrowdControlFor('retail')), 'Retail has none')
	end)

	it('gives this client the tables the scan and the containers read', function()
		assert.same(P.Data.TankDebuffs, P.Data.TankDebuffsFor(CLIENT))
		local count = 0
		for id, value in pairs(P.Data.CrowdControl) do
			count = count + 1
			assert.equal(value, true, 'crowd control ' .. id .. ' is a plain true (the container scan compares with true)')
			assert.not_nil(P.Data.CrowdControlKinds[id])
		end
		if CLIENT == 'retail' then
			assert.equal(count, 0)
		else
			assert.truthy(count > 20, 'crowd control list for ' .. CLIENT)
		end
		local ids = P.Data.TankDebuffIDs()
		for i = 2, #ids do
			assert.truthy(ids[i - 1] < ids[i], 'sorted list for includeSpellIDs')
		end
	end)

	it('keeps every entry well formed and the two lists apart on every client', function()
		for _, sources in ipairs({ P.Data.TANK_DEBUFF_SOURCES, P.Data.CROWD_CONTROL_SOURCES }) do
			for _, entry in ipairs(sources) do
				local first, last = P.Data.TIERS[entry[2]], P.Data.TIERS[entry[3]]
				assert.not_nil(first, tostring(entry[2]))
				assert.not_nil(last, tostring(entry[3]))
				assert.truthy(first <= last, entry[1])
				assert.truthy(#entry >= 4, entry[1] .. ' names at least one spell')
				for i = 4, #entry do
					assert.truthy(type(entry[i]) == 'number' and entry[i] > 0 and entry[i] == math.floor(entry[i]), entry[1])
				end
			end
		end
		for _, client in ipairs({ 'era', 'forever', 'tbc', 'titan', 'mists' }) do
			local tank = P.Data.TankDebuffsFor(client)
			for id in pairs(P.Data.CrowdControlFor(client)) do
				assert.is_nil(tank[id], client .. ': ' .. id .. ' is both crowd control and a tank debuff')
			end
		end
	end)
end)

describe('aura scan: part choice', function()
	it('draws every preview and live plates only where nothing is secret', function()
		local preview = Preview('casterTarget')
		assert.equal(preview:GetWidget('debuffs').impl.id, 'aurasScan')
		Done(preview)
		local token = M.ShowPlate(ENEMY)
		local plate = P.Plate.New(UIParent, false)
		local impl = P.Parts:Resolve(STYLE.parts.debuffs, plate)
		if CLASSIC then
			assert.equal(impl and impl.id, 'aurasScan')
		else
			assert.not_equal(impl and impl.id, 'aurasScan', 'clients with secrets never scan live plates')
		end
		M.HidePlate(token)
	end)

	it('says why rows cannot show only where they cannot', function()
		if CLASSIC then
			assert.is_nil(Scan.Limit('myDebuffs'))
			assert.is_nil(Scan.Limit('crowdControl'))
			return
		end
		local core = Register(H.FreshCore())
		if core.Caps:Get('containers') then
			assert.is_nil(Scan.Limit('myDebuffs'))
		end
		core.Caps:SetOverride('containers', false)
		assert.matches(core.AuraScan.Limit('myDebuffs'), 'aura')
	end)
end)

describe('aura scan: my debuffs', function()
	it('shows my debuffs and tank debuffs from anyone on enemies, not other debuffs', function()
		NeedsClassic()
		local plate, unit, token = Live(ENEMY)
		local tankId = FirstKey(P.Data.TankDebuffs)
		M.ApplyAura(unit, Mine(589))
		M.ApplyAura(unit, Other(980))
		M.ApplyAura(unit, Other(tankId))
		local textures = Shown(plate, 'debuffs')
		assert.contains(textures, 589)
		assert.contains(textures, tankId)
		assert.not_contains(textures, 980)
		P.Store:Set({ 'auras', 'tankDebuffs', 'on' }, false)
		plate:Configure()
		assert.not_contains((Shown(plate, 'debuffs')), tankId, 'the tank list can be turned off')
		P.Store:Set({ 'auras', 'tankDebuffs' }, nil)
		P.Store:Set({ 'auras', 'myDebuffs', 'onlyMine' }, false)
		plate:Configure()
		assert.contains((Shown(plate, 'debuffs')), 980, '"Only mine" off shows everyone')
		P.Store:Set({ 'auras' }, nil)
		Done(plate, token)
	end)

	it('keeps tank debuffs off friendly plates', function()
		NeedsClassic()
		local plate, unit, token = Live(FRIEND)
		local tankId = FirstKey(P.Data.TankDebuffs)
		M.ApplyAura(unit, Other(tankId))
		assert.not_contains((Shown(plate, 'debuffs')), tankId)
		Done(plate, token)
	end)

	it('leaves my crowd control to its own row', function()
		NeedsClassic()
		local plate, unit, token = Live(ENEMY)
		local ccId = FirstKey(P.Data.CrowdControl)
		M.ApplyAura(unit, Mine(ccId, { duration = 8 }))
		M.ApplyAura(unit, Mine(589))
		assert.not_contains((Shown(plate, 'debuffs')), ccId)
		assert.contains((Shown(plate, 'cc')), ccId)
		Done(plate, token)
	end)

	it('follows never and always lists by id and by name, never first', function()
		NeedsClassic()
		local plate, unit, token = Live(ENEMY)
		M.ApplyAura(unit, Mine(589))
		-- Another rank of the same spell: the mock names spells "Spell <id>"
		M.ApplyAura(unit, Mine(10894, { name = C_Spell.GetSpellName(589) }))
		M.ApplyAura(unit, Other(980))
		P.Store:Set({ 'auras', 'myDebuffs', 'never' }, { [589] = 'any' })
		P.Store:Set({ 'auras', 'myDebuffs', 'always' }, { [980] = 'any', [589] = 'mine' })
		plate:Configure()
		local textures = Shown(plate, 'debuffs')
		assert.not_contains(textures, 589, 'never wins over always')
		assert.not_contains(textures, 10894, 'never covers every rank by name')
		assert.contains(textures, 980, 'always shows a debuff from anyone')
		P.Store:Set({ 'auras', 'myDebuffs', 'always' }, { 980 })
		P.Store:Set({ 'auras', 'myDebuffs', 'never' }, nil)
		plate:Configure()
		assert.contains((Shown(plate, 'debuffs')), 980, 'a plain list of ids counts as anyone')
		P.Store:Set({ 'auras', 'myDebuffs', 'always' }, { [980] = 'mine' })
		plate:Configure()
		assert.not_contains((Shown(plate, 'debuffs')), 980, '"Only mine" entries need my own cast')
		P.Store:Set({ 'auras' }, nil)
		Done(plate, token)
	end)

	it('turns a row off and caps it at its size', function()
		NeedsClassic()
		local plate, unit, token = Live(ENEMY)
		for i = 1, 8 do
			M.ApplyAura(unit, Mine(5000 + i))
		end
		local textures = Shown(plate, 'debuffs')
		assert.equal(#textures, 6)
		P.Store:Set({ 'auras', 'myDebuffs', 'on' }, false)
		plate:Configure()
		assert.equal(#(Shown(plate, 'debuffs')), 0)
		P.Store:Set({ 'auras' }, nil)
		Done(plate, token)
	end)
end)

describe('aura scan: enemy buffs and crowd control', function()
	it('shows buffs that can be stolen, purged or calmed, only on enemies', function()
		NeedsClassic()
		local plate, unit, token = Live(ENEMY)
		M.ApplyAura(unit, { spellId = 700, icon = 700, dispelName = 'Magic', duration = 30 })
		M.ApplyAura(unit, { spellId = 701, icon = 701, duration = 30 })
		M.ApplyAura(unit, { spellId = 702, icon = 702, isStealable = true, duration = 30 })
		M.ApplyAura(unit, { spellId = 703, icon = 703, dispelName = '', duration = 30 })
		local textures, icons = Shown(plate, 'buffs')
		assert.contains(textures, 700)
		assert.contains(textures, 702)
		assert.contains(textures, 703, 'Enrage (an empty dispel type)')
		assert.not_contains(textures, 701)
		local magic
		for _, icon in ipairs(icons) do
			if M.Get(icon.texture, 'texture') == 700 then
				magic = icon
			end
		end
		local border = M.Get(magic.border, 'vertex')
		assert.near(border[3], 1, 0.001, 'Magic border is blue')
		M.importantSpells = { [701] = true }
		P.Store:Set({ 'auras', 'removable', 'important' }, true)
		plate:Configure()
		assert.contains((Shown(plate, 'buffs')), 701, 'important buffs when asked')
		M.importantSpells = nil
		P.Store:Set({ 'auras' }, nil)
		Done(plate, token)
		local friend, funit, ftoken = Live(FRIEND)
		M.ApplyAura(funit, { spellId = 700, icon = 700, dispelName = 'Magic', duration = 30 })
		assert.equal(#(Shown(friend, 'buffs')), 0, 'friendly buffs are not shown')
		Done(friend, ftoken)
	end)

	it("uses the game's own crowd control flag", function()
		NeedsClassic()
		local real = C_Spell.IsSpellCrowdControl
		C_Spell.IsSpellCrowdControl = function(id)
			return id == 990001
		end
		local ok, err = pcall(function()
			local plate, unit, token = Live(ENEMY)
			M.ApplyAura(unit, Other(990001, { duration = 6 }))
			M.ApplyAura(unit, Other(990002, { duration = 6 }))
			local textures = Shown(plate, 'cc')
			assert.contains(textures, 990001)
			assert.not_contains(textures, 990002)
			Done(plate, token)
		end)
		C_Spell.IsSpellCrowdControl = real
		assert.is_true(ok, tostring(err))
	end)

	it('reads the crowd control filter where the flag is missing and drops it when it misbehaves', function()
		NeedsClassic()
		local core = Register(H.FreshCore())
		local hadUtil = rawget(_G, 'AuraUtil')
		if not hadUtil then
			rawset(_G, 'AuraUtil', { AuraFilters = { CrowdControl = 'CROWD_CONTROL' } })
		end
		core.Caps:SetOverride('spellCrowdControl', false)
		core.Caps.values.ccFilter = nil
		local ok, err = pcall(function()
			assert.is_true(core.AuraScan.UsesToken())
			local plate, unit, token = Live(ENEMY, core)
			M.ApplyAura(unit, Other(990010, { duration = 6, tags = { CROWD_CONTROL = true } }))
			assert.contains((Shown(plate, 'cc')), 990010, 'the filter found it')
			-- A tank debuff in the filter result means the client ignores the token
			M.ApplyAura(unit, Other(FirstKey(core.Data.TankDebuffs), { tags = { CROWD_CONTROL = true } }))
			assert.is_false(core.Caps:Get('ccFilter'), 'turned off for the session')
			assert.not_contains((Shown(plate, 'cc')), 990010)
			Done(plate, token)
		end)
		core.Caps:SetOverride('spellCrowdControl', nil)
		if not hadUtil then
			rawset(_G, 'AuraUtil', nil)
		end
		assert.is_true(ok, tostring(err))
	end)

	it('mixes buffs and debuffs in the custom row and sorts them by name', function()
		NeedsClassic()
		local plate, unit, token = Live(ENEMY)
		P.Store:Set({ 'auras', 'custom', 'always' }, { [810] = 'any', [811] = 'any' })
		M.ApplyAura(unit, { spellId = 811, icon = 811, name = 'Alpha', duration = 10 })
		M.ApplyAura(unit, Other(810, { name = 'Bravo' }))
		M.ApplyAura(unit, Other(812, { name = 'Charlie' }))
		local textures = Shown(plate, 'custom')
		assert.same(textures, { 811, 810 })
		P.Store:Set({ 'auras' }, nil)
		Done(plate, token)
	end)
end)

describe('aura scan: icons', function()
	it('shows stacks above one and draws the cooldown swipe', function()
		NeedsClassic()
		local plate, unit, token = Live(ENEMY)
		M.ApplyAura(unit, Mine(589, { applications = 5 }))
		M.ApplyAura(unit, Mine(172, { applications = 1 }))
		local _, icons = Shown(plate, 'debuffs')
		assert.equal(M.Get(icons[1].count, 'text'), '5')
		assert.equal(M.Get(icons[2].count, 'text'), '')
		assert.truthy(#M.Calls(icons[1].cooldown, 'SetCooldown') > 0)
		Done(plate, token)
	end)

	it('counts down in the engine where it can and on the shared tick elsewhere', function()
		NeedsClassic()
		local plate, unit, token = Live(ENEMY)
		M.ApplyAura(unit, Mine(589, { duration = 10 }))
		local _, icons = Shown(plate, 'debuffs')
		if P.Caps:Get('durationText') then
			assert.not_nil(icons[1].binding, 'a duration text binding')
			assert.is_nil(icons[1].plainTimer)
		else
			assert.equal(M.Get(icons[1].timer, 'text'), '10')
			M.Advance(5)
			local left = tonumber(M.Get(icons[1].timer, 'text'))
			assert.truthy(left and left >= 5 and left <= 6, 'counted down: ' .. tostring(left))
		end
		assert.truthy(#M.ActiveOnUpdates() <= 1, 'one shared driver frame, no per-plate OnUpdate')
		Done(plate, token)
		M.Advance(1)
		assert.equal(Scan.TickingCount(), 0, 'unbound icons leave the tick')
	end)

	it('glows my debuffs in their refresh window, not other debuffs', function()
		NeedsClassic()
		local plate, unit, token = Live(ENEMY)
		local tankId = FirstKey(P.Data.TankDebuffs)
		M.ApplyAura(unit, Mine(589, { duration = 10 }))
		M.ApplyAura(unit, Other(tankId, { duration = 10 }))
		local _, icons = Shown(plate, 'debuffs')
		assert.is_false(P.GlowLib.IsShown(icons[1].pglow))
		M.Advance(7.5)
		assert.is_true(P.GlowLib.IsShown(icons[1].pglow), 'last 30% of my debuff')
		assert.is_false(P.GlowLib.IsShown(icons[2].pglow), 'not on a debuff from someone else')
		local border = M.Get(icons[1].border, 'vertex')
		assert.near(border[1], Scan.PANDEMIC_COLOR[1], 0.001)
		Done(plate, token)
	end)

	it('rescans only for aura changes that can change the row', function()
		NeedsClassic()
		local plate, unit, token = Live(ENEMY)
		local real = P.AuraScan.Collect
		local calls = 0
		P.AuraScan.Collect = function(widget, src)
			if widget.id == 'debuffs' then
				calls = calls + 1
			end
			return real(widget, src)
		end
		local ok, err = pcall(function()
			local shown = M.ApplyAura(unit, Mine(589))
			assert.equal(calls, 1, 'an added debuff')
			M.ApplyAura(unit, { spellId = 900, icon = 900, duration = 30 })
			assert.equal(calls, 1, 'an added buff cannot change My debuffs')
			local other = M.ApplyAura(unit, Other(980))
			assert.equal(calls, 2)
			M.RemoveAura(unit, other.auraInstanceID)
			assert.equal(calls, 2, 'removing an aura we do not show')
			M.RemoveAura(unit, shown.auraInstanceID)
			assert.equal(calls, 3, 'removing one we show')
			assert.equal(#(Shown(plate, 'debuffs')), 0)
		end)
		P.AuraScan.Collect = real
		assert.is_true(ok, tostring(err))
		Done(plate, token)
	end)

	it('reads auras by index where the client cannot sort them', function()
		NeedsClassic()
		local core = Register(H.FreshCore())
		core.Caps:SetOverride('auraInstanceIDs', false)
		local plate, unit, token = Live(ENEMY, core)
		M.ApplyAura(unit, Mine(589))
		M.ApplyAura(unit, Mine(172))
		assert.same((Shown(plate, 'debuffs')), { 589, 172 })
		Done(plate, token)
	end)

	it('reads auras by index from then on when a sorted list fails', function()
		NeedsClassic()
		local core = Register(H.FreshCore())
		local plate, unit, token = Live(ENEMY, core)
		plate.src.AuraInstanceIDsPlain = function()
			error('sorted list failed')
		end
		M.ApplyAura(unit, Mine(589))
		assert.same((Shown(plate, 'debuffs')), { 589 })
		assert.is_false(core.Caps:Get('auraInstanceIDs'), 'recorded for the session')
		Done(plate, token)
	end)

	it('reuses its icons across units', function()
		NeedsClassic()
		local plate, unit, token = Live(ENEMY)
		M.ApplyAura(unit, Mine(589))
		local _, _, widget = Shown(plate, 'debuffs')
		local made = #widget.icons
		Done(plate, token)
		assert.equal(#(Shown(plate, 'debuffs')), 0, 'unbinding hides every icon')
		local token2, _, unit2 = M.ShowPlate(ENEMY)
		local src = P.Source.NewLive(token2)
		src:ReadFacts(plate.facts)
		plate:Bind(token2, src)
		M.ApplyAura(unit2, Mine(172))
		assert.same((Shown(plate, 'debuffs')), { 172 })
		assert.equal(#widget.icons, made, 'no new icons')
		Done(plate, token2)
	end)
end)

describe('aura scan: previews', function()
	it('draws sample icons with paused swipes and frozen text', function()
		local plate = Preview('casterTarget')
		local textures, icons = Shown(plate, 'debuffs')
		assert.equal(#textures, 2)
		assert.equal(textures[1], P.Data.SampleIcons.pain)
		assert.equal(M.Get(icons[1].timer, 'text'), '12')
		if icons[1].cooldown.Pause then
			assert.truthy(#M.Calls(icons[1].cooldown, 'Pause') > 0)
		end
		assert.is_true(P.GlowLib.IsShown(icons[2].pglow), 'Corruption sits in its refresh window')
		Done(plate)
	end)

	it('works under strict secrets on every client', function()
		M.SetRestricted(true, nil, true)
		local ok, err = pcall(function()
			for id in pairs(P.Data.Samples) do
				local plate = Preview(id)
				Done(plate)
			end
			local plate = Preview('tankDebuffs')
			assert.equal(#(Shown(plate, 'debuffs')), 1, 'tank debuff sample')
			Done(plate)
		end)
		M.SetRestricted(false)
		assert.is_true(ok, tostring(err))
	end)

	it('follows row switches and never lists, and fills empty rows on request', function()
		P.Store:Set({ 'auras', 'myDebuffs', 'never' }, { [589] = 'any' })
		local plate = Preview('casterTarget')
		assert.same((Shown(plate, 'debuffs')), { P.Data.SampleIcons.corruption })
		Done(plate)
		P.Store:Set({ 'auras', 'myDebuffs', 'on' }, false)
		plate = Preview('casterTarget')
		assert.equal(#(Shown(plate, 'debuffs')), 0)
		Done(plate)
		P.Store:Set({ 'auras' }, nil)
		plate = P.Plate.New(UIParent, true)
		plate.fillAuras = true
		plate:ApplyStyle(P.Styles.Merge:Resolve('scanTest', 'enemyNPC', 'medium'))
		plate:BindSample(P.Source.NewSample('casterTarget'))
		assert.equal(#(Shown(plate, 'cc')), 1, 'an empty sample row gets a stock icon')
		assert.equal(#(Shown(plate, 'custom')), 3, 'stock icons for any row')
		Done(plate)
	end)
end)

describe('aura scan: presence conditions', function()
	local function Test(id, env, args)
		return P.Conditions:TestExpr({ id = id, args = args }, env)
	end

	it('answers "my debuff is missing" and "has a spell" from plain reads', function()
		NeedsClassic()
		local plate, unit, token = Live(ENEMY)
		local env = plate.env
		assert.is_true(Test('auraMissing', env, { 589 }), 'nothing on it yet')
		local aura = M.ApplyAura(unit, Mine(589))
		assert.is_false(Test('auraMissing', env, { 589 }))
		assert.is_true(Test('auraPresent', env, { [589] = 'any' }))
		M.RemoveAura(unit, aura.auraInstanceID)
		M.ApplyAura(unit, Other(589))
		assert.is_true(Test('auraMissing', env, { 589 }), "someone else's copy is not mine")
		assert.is_true(Test('auraPresent', env, { 589 }), 'from anyone')
		Done(plate, token)
		local friend, _, ftoken = Live(FRIEND)
		assert.is_false(Test('auraMissing', friend.env, { 589 }), 'no reminder on friends')
		Done(friend, ftoken)
	end)

	it('reads the color row spell lists when a color row asks', function()
		NeedsClassic()
		local plate, unit, token = Live(ENEMY)
		assert.is_false(Test('auraMissing', plate.env), 'no spells picked: no reminder')
		P.Store:Set({ 'colors', 'health', 'spells' }, { hasAura = { [172] = 'any' }, auraMissing = { [589] = 'mine' } })
		assert.is_true(Test('auraMissing', plate.env))
		assert.is_false(Test('auraPresent', plate.env))
		M.ApplyAura(unit, Mine(589))
		M.ApplyAura(unit, Other(172))
		assert.is_false(Test('auraMissing', plate.env))
		assert.is_true(Test('auraPresent', plate.env))
		P.Store:Set({ 'colors' }, nil)
		assert.is_false(Test('auraPresent', plate.env), 'forgets the lists when colors change')
		Done(plate, token)
	end)

	it('answers previews from samples and leaves hidden auras to the engine', function()
		local plate = Preview('casterTarget')
		assert.is_true(Test('auraPresent', plate.env, { 589 }))
		assert.is_false(Test('auraMissing', plate.env, { 172 }))
		assert.is_true(Test('auraMissing', plate.env, { 8921 }))
		Done(plate)
		local cond = P.Conditions:Get('auraMissing')
		assert.contains(cond.events, 'UNIT_AURA')
		if not CLASSIC then
			local live, _, token = Live(ENEMY)
			assert.is_false(Test('auraMissing', live.env, { 589 }), 'live plates with secrets keep the engine answer')
			Done(live, token)
		end
	end)
end)
