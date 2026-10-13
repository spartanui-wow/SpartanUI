-- @runtime lua51
-- The cast part (Engine/Parts/Cast.lua) and its data (Data/Kicks.lua, Data/ClassicChannels.lua):
-- every cast state on every client, under the strict secret mock on Retail and Forever and with
-- plain values on the Classic family. Covers the fill (timer, plain fallback, still bar), time
-- text (binding, plain math, Mists quirk), name, icon, shield, important glow, aimed frame, cast
-- target in class color, the interrupt-ready color row, the kick mark (chained bars and plain
-- math), "Interrupted by NAME", failed, fades, late stop events, Era channels from data, lifting
-- casts above other plates, previews, and the interrupt lists for every client.
local M, H = ...
local S = M.S

if not H.ModuleExists() then
	describe('cast', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

M.Login('NameplatesTestHost')
local P = H.FreshCore()
local Merge = P.Styles.Merge
local Cast = P.CastBar
local Kicks = P.Data.Kicks
local Channels = P.Data.ClassicChannels

local TOKEN = 'nameplate7'
local readyColor = P.Colors:GetKind('interruptReady').default
local castColor = P.Colors.FALLBACK.cast
local CLIENTS = { 'retail', 'forever', 'mists', 'titan', 'tbc', 'era' }
local serial = 0

---Register a one-off style: a health bar filling the plate and a cast bar below it.
local function Style(fields)
	serial = serial + 1
	local id = 'castTest' .. serial
	local cast = { order = 20, kind = 'cast', anchor = { 'TOP', 'health', 'BOTTOM', 0, -2 }, height = 8, icon = 'left', target = true, shield = true, important = true, aimedAtMe = true }
	for k, v in pairs(fields or {}) do
		cast[k] = v
	end
	P.Styles.Registry:RegisterBuiltin({
		id = id,
		name = id,
		version = 1,
		schema = 1,
		order = 6000 + serial,
		internal = true,
		plate = { sizes = { small = { 100, 8 }, medium = { 120, 10 }, large = { 140, 12 } } },
		tokens = { accent = '$host', font = '$host', bar = 'Nameplates Flat', ink = { 0, 0, 0, 1 }, shade = { 0, 0, 0, 0.6 } },
		parts = {
			health = { order = 10, kind = 'bar', source = 'health', anchor = { 'CENTER', 'plate', 'CENTER', 0, 0 }, fill = 'plate', colors = 'health' },
			cast = cast,
		},
	})
	return Merge:Resolve(id, 'enemyNPC', 'medium')
end

---A bound live plate on a fresh unit. Returns plate, cast widget, unit.
local function Live(fields, unitSpec)
	local unit = M.AddUnit(unitSpec or { name = 'Caster', canAttack = true, reaction = 2 })
	M.SetToken(TOKEN, unit)
	local plate = P.Plate.New(UIParent, false)
	local src = P.Source.NewLive(TOKEN)
	src:ReadFacts(plate.facts)
	plate:ApplyStyle(Style(fields))
	plate:Bind(TOKEN, src)
	return plate, plate:GetWidget('cast'), unit
end

local function Done(plate)
	plate:Unbind()
	M.SetToken(TOKEN, nil)
	M.SetRestricted(false)
	P.Context.kickSpell = nil
end

local function Text(fontString)
	return S.Reveal(M.Get(fontString, 'text'))
end

local function Alpha(region)
	return M.Get(region, 'alpha')
end

local function Shown(region)
	return M.Get(region, 'shown') == true
end

local function BarColor(bar)
	local c = M.Get(bar, 'barColor')
	return c and { c[1], c[2], c[3] }
end

local function Near(a, b)
	return math.abs(a - b) < 0.001
end

local function SameColor(got, want)
	return got ~= nil and Near(got[1], want[1]) and Near(got[2], want[2]) and Near(got[3], want[3])
end

---Swap globals for one test; returns a function that puts them back.
local function Swap(values)
	local old = {}
	for name, value in pairs(values) do
		old[name] = { rawget(_G, name) }
		rawset(_G, name, value)
	end
	return function()
		for name, saved in pairs(old) do
			rawset(_G, name, saved[1])
		end
	end
end

---Swap fields of a namespace table for one test.
local function SwapIn(tbl, values)
	local old = {}
	for name, value in pairs(values) do
		old[name] = { rawget(tbl, name) }
		rawset(tbl, name, value)
	end
	return function()
		for name, saved in pairs(old) do
			rawset(tbl, name, saved[1])
		end
	end
end

---A cooldown duration for the player's interrupt: `left` seconds from now (0 = ready). With
---secret = true its readings come back secret, the way a restricted client hands them out.
local function Cooldown(left, secret)
	local d = C_DurationUtil.CreateDuration()
	local finish = M.now + left
	d:SetTimeFromStart(M.now, left)
	local function Wrap(v)
		return secret and S.Wrap(v) or v
	end
	d.GetRemainingDuration = function()
		return Wrap(math.max(0, finish - M.now))
	end
	d.IsZero = function()
		return Wrap(M.now >= finish)
	end
	return d
end

local function InstallCooldown(get)
	return SwapIn(C_Spell, {
		GetSpellCooldownDuration = function(spell)
			return get(spell)
		end,
	})
end

-- The mock's class colors are stand-ins; these give each test known values (secret in, secret out)
local CLASS_RGB = { ROGUE = { 1, 0.96, 0.41 }, PRIEST = { 0.9, 0.9, 0.95 } }

local function InstallClassColors()
	return SwapIn(C_ClassColor, {
		GetClassColor = function(token)
			local rgb = CLASS_RGB[S.Reveal(token)]
			if not rgb then
				return nil
			end
			local function V(v)
				return S.IsSecret(token) and S.Wrap(v) or v
			end
			return {
				r = V(rgb[1]),
				g = V(rgb[2]),
				b = V(rgb[3]),
				GetRGB = function(self)
					return self.r, self.g, self.b
				end,
			}
		end,
	})
end

local function Restricted()
	return M.SetRestricted(true)
end

---The mock's Duration objects have no GetElapsedDuration; give them one for chained kick bars.
local function WithElapsed()
	local methods = M.Class('Duration').methods
	local real = methods.GetElapsedDuration
	methods.GetElapsedDuration = function(self)
		local v = self:GetTotalDuration() - self:GetRemainingDuration()
		return M.secrets and S.Wrap(v) or v
	end
	return function()
		methods.GetElapsedDuration = real
	end
end

----------------------------------------------------------------------------------------------------
-- Data
----------------------------------------------------------------------------------------------------

describe('cast data: interrupt lists', function()
	it('has a checked table for every client', function()
		for _, client in ipairs(CLIENTS) do
			local data = Kicks.CLIENTS[client]
			assert.not_nil(data, client)
			assert.equal(type(data.source), 'string', client)
			assert.equal(type(data.exact), 'boolean', client)
			local listed = {}
			for class, ids in pairs(data.byClass) do
				assert.matches(class, '^[A-Z]+$')
				local seen = {}
				for _, id in ipairs(ids) do
					assert.equal(type(id), 'number', client .. ' ' .. class)
					assert.equal(id, math.floor(id))
					assert.is_true(id > 0)
					assert.is_nil(seen[id], client .. ' ' .. class .. ' lists ' .. id .. ' twice')
					seen[id] = true
					listed[id] = true
				end
			end
			for _, id in ipairs(data.pet) do
				listed[id] = true
			end
			for id, why in pairs(data.unverified or {}) do
				assert.is_true(listed[id] == true, client .. ': unverified id ' .. id .. ' is not listed')
				assert.equal(type(why), 'string')
			end
		end
	end)

	it('gives every class that can interrupt an interrupt on each client', function()
		local everywhere = { 'MAGE', 'PRIEST', 'ROGUE', 'SHAMAN', 'WARRIOR', 'DRUID' }
		for _, client in ipairs(CLIENTS) do
			for _, class in ipairs(everywhere) do
				local ids = Kicks.CLIENTS[client].byClass[class]
				assert.is_true(ids ~= nil and #ids > 0, client .. ' ' .. class)
			end
			assert.is_true(#Kicks.CLIENTS[client].pet > 0, client .. ' pet interrupts (Spell Lock)')
		end
		assert.not_nil(Kicks.CLIENTS.retail.byClass.EVOKER)
		assert.not_nil(Kicks.CLIENTS.retail.byClass.DEMONHUNTER)
		assert.not_nil(Kicks.CLIENTS.mists.byClass.MONK)
		assert.not_nil(Kicks.CLIENTS.titan.byClass.DEATHKNIGHT)
		assert.is_nil(Kicks.CLIENTS.era.byClass.PALADIN, 'no paladin interrupt before Cataclysm')
		assert.equal(Kicks.CLIENTS.era.byClass.ROGUE[1], 1769, 'highest rank first')
		assert.equal(Kicks.CLIENTS.tbc.byClass.ROGUE[1], 38768)
	end)

	it('uses the running client', function()
		assert.equal(Kicks.client, P.Caps:Client())
		assert.equal(Kicks.byClass, Kicks.CLIENTS[P.Caps:Client()].byClass)
	end)

	it('picks a pet interrupt first, then the class list in order', function()
		Kicks:Use('era')
		local spell, isPet = Kicks:Pick('WARLOCK', function(id, pet)
			return pet and id == 19244
		end)
		assert.equal(spell, 19244)
		assert.is_true(isPet)
		spell, isPet = Kicks:Pick('ROGUE', function(id)
			return id == 1766 or id == 1767
		end)
		assert.equal(spell, 1767)
		assert.is_false(isPet)
		Kicks:Use('nowhere')
		assert.is_nil((Kicks:Pick('ROGUE', function()
			return true
		end)))
		Kicks:Use(P.Caps:Client())
	end)

	it('asks the spell book for player and pet spells', function()
		local asked = {}
		local restore = SwapIn(C_SpellBook, {
			IsSpellKnownOrInSpellBook = function(id, bank)
				asked[#asked + 1] = { id, bank }
				return id == 1766 and bank == Enum.SpellBookSpellBank.Player
			end,
			IsSpellKnown = function()
				return false
			end,
		})
		assert.is_true(Kicks.Known(1766, false))
		assert.is_false(Kicks.Known(19647, true))
		assert.equal(asked[2][2], Enum.SpellBookSpellBank.Pet)
		Kicks:Use('era')
		assert.equal(Kicks:Choose('ROGUE'), 1766)
		Kicks:Use(P.Caps:Client())
		restore()
	end)
end)

describe('cast data: Era channel lengths', function()
	it('finds every rank by id only on the Era content tier', function()
		if P.Data.CLIENT_TIERS[P.Caps:Client()] ~= P.Data.CLIENT_TIERS.era then
			assert.is_nil(Channels:Duration(5143))
			return
		end
		assert.equal(Channels:Duration(5143), 3)
		assert.equal(Channels:Duration(5144), 4)
		assert.equal(Channels:Duration(25345), 5)
		assert.equal(Channels:Duration(10187), 8)
		assert.equal(Channels:Duration(11675), 15)
		assert.is_nil(Channels:Duration(1))
		assert.is_nil(Channels:Duration('5143'))
		for id, seconds in pairs(Channels.byId) do
			assert.equal(type(id), 'number')
			assert.is_true(seconds > 0 and seconds <= 60)
		end
	end)

	it('falls back to the spell name with the longest listed length', function()
		if P.Data.CLIENT_TIERS[P.Caps:Client()] ~= P.Data.CLIENT_TIERS.era then
			assert.is_nil(Channels:Duration(99999))
			return
		end
		Channels.names = nil
		local restore = SwapIn(C_Spell, {
			GetSpellName = function(id)
				if id == 99999 or id == 5143 or id == 5144 or id == 5145 then
					return 'Arcane Missiles'
				end
				return 'Spell ' .. tostring(id)
			end,
		})
		assert.equal(Channels:Duration(99999), 5)
		restore()
		Channels.names = nil
	end)
end)

----------------------------------------------------------------------------------------------------
-- Drawing a cast
----------------------------------------------------------------------------------------------------

describe('cast part: a cast from start to end', function()
	it('shows the name, icon and fill, and sets the casting state', function()
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Shadow Bolt', spellID = 686, duration = 2, castBarID = 7, texture = 136197 })
		assert.equal(widget.state, 'casting')
		assert.is_true(Shown(widget.content))
		assert.equal(Text(widget.name), 'Shadow Bolt')
		assert.equal(M.Get(widget.icon, 'texture'), 136197)
		assert.is_true(plate.states.casting)
		if P.Caps:Get('timerBars') then
			assert.not_nil(M.Get(widget.bar, 'timer'), 'the game timer fills the bar')
		else
			assert.is_true(Near(S.Reveal(M.Get(widget.bar, 'max')) - S.Reveal(M.Get(widget.bar, 'min')), 2))
		end
		Done(plate)
	end)

	it('picks up a cast that started before the plate was bound', function()
		local unit = M.AddUnit({ name = 'Early', canAttack = true, reaction = 2 })
		M.SetToken(TOKEN, unit)
		unit.cast = { name = 'Fireball', spellID = 133, startMS = M.now * 1000, endMS = (M.now + 3) * 1000, castID = 'x', castBarID = 2 }
		local plate = P.Plate.New(UIParent, false)
		local src = P.Source.NewLive(TOKEN)
		src:ReadFacts(plate.facts)
		plate:ApplyStyle(Style())
		plate:Bind(TOKEN, src)
		local widget = plate:GetWidget('cast')
		assert.equal(widget.state, 'casting')
		assert.equal(Text(widget.name), 'Fireball')
		unit.cast = nil
		Done(plate)
	end)

	it('fades out after the cast ends and clears the casting state', function()
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Heal', spellID = 2050, duration = 1, castBarID = 3 })
		M.StopCast(unit, 'stop')
		assert.equal(widget.state, 'done')
		assert.is_true(Shown(widget.content))
		M.Advance(0.5)
		assert.is_false(Shown(widget.content))
		assert.is_nil(widget.state)
		assert.is_nil(plate.states.casting)
		Done(plate)
	end)

	it('ignores a stop event from an older cast', function()
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Frostbolt', spellID = 116, duration = 2, castBarID = 9 })
		M.Fire('UNIT_SPELLCAST_STOP', TOKEN, 'Cast-old', 116, 4)
		assert.equal(widget.state, 'casting')
		M.Fire('UNIT_SPELLCAST_FAILED', TOKEN, 'Cast-old', 116, 4)
		assert.equal(widget.state, 'casting')
		Done(plate)
	end)

	it('hides casts on friendly plates unless the style asks for them', function()
		local friendSpec = { name = 'Friend', canAttack = false, reaction = 5 }
		local plate, widget, unit = Live(nil, friendSpec)
		M.StartCast(unit, { name = 'Renew', spellID = 139, duration = 2 })
		assert.is_nil(widget.state)
		assert.is_false(Shown(widget.content))
		Done(plate)
		plate, widget, unit = Live({ friends = true }, friendSpec)
		M.StartCast(unit, { name = 'Renew', spellID = 139, duration = 2 })
		assert.equal(widget.state, 'casting')
		Done(plate)
	end)

	it('drains channels and fills casts', function()
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Drain Life', spellID = 689, duration = 5, channel = true })
		assert.equal(widget.kind, 'channel')
		local timer = M.Get(widget.bar, 'timer')
		if timer and Enum.StatusBarTimerDirection then
			assert.equal(timer.direction, Enum.StatusBarTimerDirection.RemainingTime)
		end
		M.StopCast(unit, 'stop')
		assert.equal(widget.state, 'done')
		assert.equal(S.Reveal(M.Get(widget.bar, 'value')), 0, 'a finished channel ends empty')
		Done(plate)
	end)
end)

describe('cast part: interrupted and failed', function()
	local restore, restoreColors
	before_each(function()
		restoreColors = InstallClassColors()
		restore = Swap({
			UnitNameFromGUID = rawget(_G, 'UnitNameFromGUID') and function(guid)
				return S.Reveal(guid) == 'Player-1-KICK' and 'Kicker' or nil
			end or nil,
			UnitClassFromGUID = function(guid)
				if S.Reveal(guid) == 'Player-1-KICK' then
					return 'Rogue', 'ROGUE', 4
				end
			end,
			GetPlayerInfoByGUID = function(guid)
				if S.Reveal(guid) == 'Player-1-KICK' then
					return 'Rogue', 'ROGUE', 'Human', 'Human', 2, 'Kicker', ''
				end
			end,
		})
	end)
	after_each(function()
		restore()
		restoreColors()
	end)

	it('flashes "Interrupted by NAME" in class color, holds, then fades', function()
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Shadow Bolt', spellID = 686, duration = 3, castBarID = 7 })
		unit.cast = nil
		M.Fire('UNIT_SPELLCAST_INTERRUPTED', TOKEN, 'Cast-1', 686, 'Player-1-KICK', 7)
		assert.equal(widget.state, 'interrupted')
		assert.equal(Text(widget.name), 'Interrupted by Kicker')
		local c = M.Get(widget.name, 'textColor')
		assert.is_true(Near(c[1], CLASS_RGB.ROGUE[1]) and Near(c[2], CLASS_RGB.ROGUE[2]) and Near(c[3], CLASS_RGB.ROGUE[3]))
		assert.is_true(SameColor(BarColor(widget.bar), { 0.85, 0.2, 0.2 }))
		assert.equal(S.Reveal(M.Get(widget.bar, 'value')), 1)
		-- The stop that follows an interrupt keeps the flash
		M.Fire('UNIT_SPELLCAST_STOP', TOKEN, 'Cast-1', 686, 7)
		assert.equal(widget.state, 'interrupted')
		M.Advance(0.3)
		assert.is_true(Shown(widget.content), 'the flash holds')
		M.Advance(1)
		assert.is_false(Shown(widget.content))
		assert.is_nil(plate.states.casting)
		Done(plate)
	end)

	it('says "Interrupted" when nobody is named', function()
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Fireball', spellID = 133, duration = 3 })
		M.StopCast(unit, 'interrupted')
		assert.equal(widget.state, 'interrupted')
		assert.equal(Text(widget.name), 'Interrupted')
		Done(plate)
	end)

	it('names who interrupted a channel', function()
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Mind Flay', spellID = 15407, duration = 3, channel = true })
		unit.cast = nil
		M.Fire('UNIT_SPELLCAST_CHANNEL_STOP', TOKEN, 'Cast-2', 15407, 'Player-1-KICK', nil)
		assert.equal(widget.state, 'interrupted')
		assert.equal(Text(widget.name), 'Interrupted by Kicker')
		Done(plate)
	end)

	it('leaves the name out when the style turns it off', function()
		local plate, widget, unit = Live({ interrupter = false })
		M.StartCast(unit, { name = 'Fireball', spellID = 133, duration = 3 })
		unit.cast = nil
		M.Fire('UNIT_SPELLCAST_INTERRUPTED', TOKEN, 'Cast-3', 133, 'Player-1-KICK', nil)
		assert.equal(Text(widget.name), 'Interrupted')
		Done(plate)
	end)

	it('says "Failed" and an interrupt that follows still names the kicker', function()
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Fireball', spellID = 133, duration = 3 })
		M.StopCast(unit, 'failed')
		assert.equal(widget.state, 'failed')
		assert.equal(Text(widget.name), 'Failed')
		assert.is_true(SameColor(BarColor(widget.bar), { 0.5, 0.5, 0.5 }))
		M.Fire('UNIT_SPELLCAST_INTERRUPTED', TOKEN, 'Cast-4', 133, 'Player-1-KICK', nil)
		assert.equal(widget.state, 'interrupted')
		assert.equal(Text(widget.name), 'Interrupted by Kicker')
		Done(plate)
	end)

	it('a new cast during the flash takes over at once', function()
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Fireball', spellID = 133, duration = 3 })
		M.StopCast(unit, 'interrupted')
		M.StartCast(unit, { name = 'Frostbolt', spellID = 116, duration = 2 })
		assert.equal(widget.state, 'casting')
		assert.equal(Text(widget.name), 'Frostbolt')
		assert.equal(Alpha(widget.content), 1)
		M.Advance(1.5)
		assert.equal(widget.state, 'casting', 'the old flash does not fade the new cast')
		Done(plate)
	end)

	it('ends a channel normally when the interrupter GUID is empty', function()
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Mind Flay', spellID = 15407, duration = 3, channel = true })
		unit.cast = nil
		M.Fire('UNIT_SPELLCAST_CHANNEL_STOP', TOKEN, 'Cast-7', 15407, '', nil)
		assert.equal(widget.state, 'done')
		Done(plate)
	end)

	it('shows an empower that stopped early as broken off, and a finished one as done', function()
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Fire Breath', spellID = 357208, duration = 3, channel = true, empowered = true, numStages = 3 })
		assert.equal(widget.kind, 'empower')
		assert.is_true(M.Get(widget.bar, 'reverseFill') ~= true, 'empowers fill like casts')
		unit.cast = nil
		M.Fire('UNIT_SPELLCAST_EMPOWER_STOP', TOKEN, 'Cast-8', 357208, false, nil, nil)
		assert.equal(widget.state, 'interrupted')
		assert.equal(Text(widget.name), 'Interrupted')
		Done(plate)
		plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Fire Breath', spellID = 357208, duration = 3, channel = true, empowered = true, numStages = 3 })
		unit.cast = nil
		M.Fire('UNIT_SPELLCAST_EMPOWER_STOP', TOKEN, 'Cast-8', 357208, true, nil, nil)
		assert.equal(widget.state, 'done')
		Done(plate)
		plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Fire Breath', spellID = 357208, duration = 3, channel = true, empowered = true, numStages = 3 })
		unit.cast = nil
		M.Fire('UNIT_SPELLCAST_EMPOWER_STOP', TOKEN, 'Cast-8', 357208, false, 'Player-1-KICK', nil)
		assert.equal(Text(widget.name), 'Interrupted by Kicker')
		Done(plate)
	end)

	it("uses the game's own words when it has them", function()
		local restoreText = Swap({ FAILED = 'Fehlgeschlagen', INTERRUPTED = 'Unterbrochen', SPELL_INTERRUPTED_BY = 'Unterbrochen von %s' })
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Fireball', spellID = 133, duration = 3 })
		M.StopCast(unit, 'failed')
		assert.equal(Text(widget.name), 'Fehlgeschlagen')
		M.Fire('UNIT_SPELLCAST_INTERRUPTED', TOKEN, 'Cast-4', 133, 'Player-1-KICK', nil)
		assert.equal(Text(widget.name), 'Unterbrochen von Kicker')
		Done(plate)
		plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Fireball', spellID = 133, duration = 3 })
		M.StopCast(unit, 'interrupted')
		assert.equal(Text(widget.name), 'Unterbrochen')
		Done(plate)
		restoreText()
	end)
end)

describe('cast part: shield, glow, aimed, target', function()
	it('shows the shield and hides the kick frame for casts that cannot be interrupted', function()
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Ground Slam', spellID = 500, duration = 2, notInterruptible = true })
		assert.equal(Alpha(widget.shield), 1)
		assert.equal(Alpha(widget.kick), 0)
		unit.cast.notInterruptible = false
		M.UpdateUnit(unit, nil, { 'UNIT_SPELLCAST_INTERRUPTIBLE' })
		assert.equal(Alpha(widget.shield), 0)
		assert.equal(Alpha(widget.kick), 1)
		Done(plate)
	end)

	it('glows for important casts and frames casts aimed at the player', function()
		M.importantSpells = { [777] = true }
		local restore = Swap({
			PlayerIsSpellTarget = function()
				return true
			end,
		})
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Doom', spellID = 777, duration = 2 })
		local glow = widget.important
		assert.is_true(P.GlowLib.IsShown(glow), 'the shared glow draws it')
		assert.equal(Alpha(glow.gate), 1)
		assert.is_true(Shown(glow.gate))
		local orange = P.GlowLib.SOURCE_COLORS.importantCast
		assert.is_true(Near(glow.r, orange[1]) and Near(glow.g, orange[2]) and Near(glow.b, orange[3]), 'orange')
		assert.equal(Alpha(widget.aimed), 1)
		M.StopCast(unit, 'stop')
		assert.is_false(P.GlowLib.IsShown(glow), 'gone when the cast ends')
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 2 })
		assert.is_false(P.GlowLib.IsShown(glow), 'a plain no keeps it off, pulse and all')
		restore()
		M.importantSpells = nil
		Done(plate)
		assert.is_false(Shown(glow.gate), 'hidden at once on unbind')
	end)

	it('leaves the glow off when the style turns it off', function()
		M.importantSpells = { [777] = true }
		local plate, widget, unit = Live({ important = false })
		M.StartCast(unit, { name = 'Doom', spellID = 777, duration = 2 })
		assert.is_false(P.GlowLib.IsShown(widget.important))
		M.importantSpells = nil
		Done(plate)
	end)

	it('leaves the aimed frame off where the client cannot tell', function()
		local saved = rawget(_G, 'PlayerIsSpellTarget')
		rawset(_G, 'PlayerIsSpellTarget', nil)
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 2 })
		assert.equal(Alpha(widget.aimed), 0)
		Done(plate)
		rawset(_G, 'PlayerIsSpellTarget', saved)
	end)

	it('writes the cast target in class color', function()
		local restoreColors = InstallClassColors()
		local restore = Swap({
			UnitSpellTargetName = function()
				return 'Healbot'
			end,
			UnitSpellTargetClass = function()
				return 'PRIEST'
			end,
		})
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 2 })
		assert.equal(Text(widget.target), 'Healbot')
		local c = M.Get(widget.target, 'textColor')
		assert.is_true(Near(c[1], CLASS_RGB.PRIEST[1]) and Near(c[3], CLASS_RGB.PRIEST[3]))
		Done(plate)
		restore()
		restoreColors()
	end)
end)

describe('cast part: colors and the kick', function()
	it('turns green while the interrupt is ready and back when it is used', function()
		P.Context.kickSpell = 1766
		local left = 0
		local restore = InstallCooldown(function()
			return Cooldown(left)
		end)
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 3 })
		assert.is_true(SameColor(BarColor(widget.bar), readyColor), 'ready')
		left = 10
		plate:OnMessage('KICK_READY_CHANGED')
		assert.is_true(SameColor(BarColor(widget.bar), castColor), 'cooling down')
		restore()
		Done(plate)
	end)

	it('stays gray for casts that cannot be interrupted', function()
		P.Context.kickSpell = 1766
		local restore = InstallCooldown(function()
			return Cooldown(0)
		end)
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Slam', spellID = 500, duration = 3, notInterruptible = true })
		assert.is_true(SameColor(BarColor(widget.bar), P.Colors:GetKind('notInterruptible').default))
		restore()
		Done(plate)
	end)

	it('marks where the interrupt comes back, by math on plain clients', function()
		P.Context.kickSpell = 1766
		local restore = InstallCooldown(function()
			return Cooldown(1)
		end)
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 2 })
		assert.equal(widget.kickMode, 'plain')
		assert.is_true(Shown(widget.kick))
		local point = M.Get(widget.kickParts.mark, 'points')[1]
		assert.equal(point[1], 'CENTER')
		assert.equal(point[4], math.floor(0.5 * widget.barWidth + 0.5))
		M.Advance(1.5)
		assert.is_false(Shown(widget.kick), 'gone once the interrupt is back')
		assert.is_false(P.Scheduler:IsRunning('cast.kick'), 'the shared task stops with no marks')
		restore()
		Done(plate)
	end)

	it('hides the mark when the interrupt is back only after the cast', function()
		P.Context.kickSpell = 1766
		local restore = InstallCooldown(function()
			return Cooldown(5)
		end)
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 2 })
		assert.is_false(Shown(widget.kick))
		restore()
		Done(plate)
	end)

	it('places the mark with two chained bars without reading anything', function()
		P.Context.kickSpell = 1766
		local methods = M.Class('Duration').methods
		local real = methods.GetElapsedDuration
		local secret = M.secrets
		methods.GetElapsedDuration = function(self)
			local v = self:GetTotalDuration() - self:GetRemainingDuration()
			return secret and S.Wrap(v) or v
		end
		local cooldown = Cooldown(1, secret)
		local restore = InstallCooldown(function()
			return cooldown
		end)
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 2 })
		assert.equal(widget.kickMode, 'bars')
		local kick = widget.kickParts
		assert.is_true(Near(S.Reveal(M.Get(kick.marker, 'value')), 1), 'remaining cooldown')
		assert.is_true(Near(S.Reveal(M.Get(kick.positioner, 'max')), 2), 'over the whole cast')
		assert.equal(M.Get(kick.marker, 'points')[1][2], kick.positioner:GetStatusBarTexture())
		assert.equal(Alpha(kick.mark), 1)
		M.Advance(1.1)
		if secret then
			assert.equal(Alpha(kick.mark), 0, 'the mark fades once the interrupt is ready')
			assert.is_true(P.Scheduler:IsRunning('cast.kick'), 'a hidden answer keeps the check running')
		else
			assert.is_false(Shown(widget.kick), 'a readable ready answer hides the mark')
			assert.is_nil(Cast.kickActive[widget], 'and leaves the shared check')
			M.Advance(0.25)
			assert.is_false(P.Scheduler:IsRunning('cast.kick'), 'which stops with no marks')
		end
		methods.GetElapsedDuration = real
		restore()
		Done(plate)
	end)

	it('turns pixel snapping off on the kick bars so the mark holds still', function()
		P.Context.kickSpell = 1766
		local methods = M.Class('Duration').methods
		local real = methods.GetElapsedDuration
		methods.GetElapsedDuration = function(self)
			return self:GetTotalDuration() - self:GetRemainingDuration()
		end
		local restore = InstallCooldown(function()
			return Cooldown(1)
		end)
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 2 })
		methods.GetElapsedDuration = real
		assert.equal(widget.kickMode, 'bars')
		local fill = widget.kickParts.marker:GetStatusBarTexture()
		if not fill.SetSnapToPixelGrid then
			restore()
			Done(plate)
			skip('no pixel snapping on this client')
		end
		local calls = M.Calls(fill, 'SetSnapToPixelGrid')
		assert.is_true(#calls > 0)
		assert.equal(calls[#calls][1], false)
		restore()
		Done(plate)
	end)

	it('keeps the mark when a later cooldown read comes back empty', function()
		P.Context.kickSpell = 1766
		local restoreElapsed = WithElapsed()
		local give = true
		local cooldown = Cooldown(1)
		local restore = InstallCooldown(function()
			return give and cooldown or nil
		end)
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 2 })
		assert.equal(widget.kickMode, 'bars')
		give = false
		plate:OnMessage('KICK_READY_CHANGED')
		assert.equal(widget.kickMode, 'bars', 'no blink on a passing read miss')
		assert.is_true(Shown(widget.kick))
		M.Advance(0.25)
		assert.is_true(Shown(widget.kick), 'the shared check also waits')
		restoreElapsed()
		restore()
		Done(plate)
	end)

	it('skips the mark and the check when the interrupt is already ready', function()
		P.Context.kickSpell = 1766
		local restore = InstallCooldown(function()
			return Cooldown(0)
		end)
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 2 })
		assert.is_false(Shown(widget.kick))
		assert.is_nil(Cast.kickActive[widget])
		restore()
		Done(plate)
	end)

	it('tints the part of the bar after the mark when the style asks', function()
		P.Context.kickSpell = 1766
		local restore = InstallCooldown(function()
			return Cooldown(1)
		end)
		local plate, widget, unit = Live({ kickFill = true })
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 2 })
		assert.equal(widget.kickMode, 'plain')
		local x = math.floor(0.5 * widget.barWidth + 0.5)
		local fillLeft = M.Get(widget.kickParts.fill, 'points')
		local found = false
		for _, p in ipairs(fillLeft) do
			if p[1] == 'LEFT' and p[2] == widget.bar and p[4] == x then
				found = true
			end
		end
		assert.is_true(found, 'by math: starts at the mark')
		Done(plate)
		P.Context.kickSpell = 1766
		local restoreElapsed = WithElapsed()
		plate, widget, unit = Live({ kickFill = true })
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 2 })
		local kick = widget.kickParts
		assert.equal(widget.kickMode, 'bars')
		assert.is_true(Shown(kick.fill), 'fill shown; kick shown: ' .. tostring(Shown(widget.kick)))
		local points = M.Get(kick.fill, 'points')
		local left, right
		for _, p in ipairs(points) do
			if p[1] == 'LEFT' then
				left = p
			elseif p[1] == 'RIGHT' then
				right = p
			end
		end
		assert.equal(right[2], widget.bar, 'runs to the end of the bar')
		assert.equal(widget.kickMode, 'bars')
		assert.equal(left[2], kick.marker:GetStatusBarTexture(), 'chained bars: starts at the mark')
		restoreElapsed()
		Done(plate)
		P.Context.kickSpell = 1766
		plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 2 })
		assert.is_true(Shown(widget.kick))
		assert.is_false(Shown(widget.kickParts.fill), 'off by default')
		restore()
		Done(plate)
	end)

	it('mirrors the kick bars for channels', function()
		P.Context.kickSpell = 1766
		local methods = M.Class('Duration').methods
		local real = methods.GetElapsedDuration
		methods.GetElapsedDuration = function(self)
			return self:GetTotalDuration() - self:GetRemainingDuration()
		end
		local restore = InstallCooldown(function()
			return Cooldown(1)
		end)
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Drain', spellID = 689, duration = 4, channel = true })
		local kick = widget.kickParts
		assert.equal(M.Get(kick.marker, 'points')[1][1], 'RIGHT')
		assert.is_true(M.Get(kick.marker, 'reverseFill') == true)
		methods.GetElapsedDuration = real
		restore()
		Done(plate)
	end)

	it('draws no mark without an interrupt, or when the style turns it off', function()
		local restore = InstallCooldown(function()
			return Cooldown(1)
		end)
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 2 })
		assert.is_false(Shown(widget.kick))
		Done(plate)
		P.Context.kickSpell = 1766
		plate, widget, unit = Live({ kickMark = false })
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 2 })
		assert.is_false(Shown(widget.kick))
		restore()
		Done(plate)
	end)
end)

describe('cast part: time and fill fallbacks', function()
	it('writes time by plain math when the engine cannot format it', function()
		P.Caps:SetOverride('durationText', false)
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 2 })
		assert.equal(Text(widget.time), '2.0')
		M.Advance(0.5)
		assert.is_true(math.abs(tonumber(Text(widget.time)) - 1.5) < 0.15)
		Done(plate)
		P.Caps:SetOverride('durationText', nil)
		M.Advance(0.3)
		local left = 0
		for _ in pairs(Cast.textActive) do
			left = left + 1
		end
		assert.equal(left, 0, 'no cast keeps time text')
		assert.is_false(P.Scheduler:IsRunning('cast.text'), 'the shared text task stops with no casts')
	end)

	it('shows elapsed and total when the style asks', function()
		P.Caps:SetOverride('durationText', false)
		local plate, widget, unit = Live({ timeFormat = 'both' })
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 12 })
		assert.equal(Text(widget.time), '12 / 12')
		M.Advance(3)
		assert.matches(Text(widget.time), '^9%.%d / 12$')
		Done(plate)
		P.Caps:SetOverride('durationText', nil)
	end)

	it('binds the time text to the cast where the engine formats it', function()
		local made = { breakpoints = nil }
		made.SetBreakpoints = function(self, list)
			self.breakpoints = list
		end
		local restore = SwapIn(C_StringUtil, {
			CreateNumericRuleFormatter = function()
				return made
			end,
		})
		Cast.ForgetFormatter()
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 2 })
		if P.Caps:Get('durationText') then
			assert.not_nil(widget.binding)
			assert.equal(M.Get(widget.binding, 'duration'), widget.durationSecret)
			assert.equal(made.breakpoints[1].format, '%.1f')
		else
			assert.equal(P.Caps:Client(), 'mists', 'only the Mists quirk turns the binding off here')
			assert.is_nil(widget.binding)
			assert.equal(Text(widget.time), '2.0')
		end
		Done(plate)
		restore()
		Cast.ForgetFormatter()
	end)

	it('falls back to the seconds format when a binding refuses the rule formatter', function()
		if not P.Caps:Get('durationText') then
			skip('this client has no time text binding')
		end
		local rule = { SetBreakpoints = function() end }
		local seconds = {}
		local restore = SwapIn(C_StringUtil, {
			CreateNumericRuleFormatter = function()
				return rule
			end,
			CreateSecondsFormatter = function()
				return seconds
			end,
		})
		local methods = M.Class('DurationTextBinding').methods
		local real = methods.SetFormatter
		local got
		methods.SetFormatter = function(self, formatter)
			if formatter == rule then
				error('this formatter is not allowed here')
			end
			got = formatter
			return real(self, formatter)
		end
		Cast.ForgetFormatter()
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 2 })
		assert.is_true(widget.bindingOn == true, 'the time text is still bound')
		assert.equal(got, seconds)
		assert.equal(Cast.Formatter(), seconds, 'later casts start with the seconds format')
		methods.SetFormatter = real
		Done(plate)
		restore()
		Cast.ForgetFormatter()
	end)

	it('keeps Mists on plain math for time text', function()
		if P.Caps:Client() ~= 'mists' then
			skip('Mists only')
		end
		assert.is_true(P.Caps:Quirk('plainCastText'))
		assert.is_false(P.Caps:Get('durationText'))
	end)

	it('fills from cast times when the game refuses the timer (S0)', function()
		local plate, widget, unit = Live()
		widget.bar.SetTimerDuration = function()
			error('refused')
		end
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 2 })
		local start = M.now
		if P.Caps:Get('castDurations') then
			assert.is_false(P.Caps:Get('timerBars'), 'the refusal is recorded')
		end
		assert.is_true(Near(S.Reveal(M.Get(widget.bar, 'min')), start))
		assert.is_true(Near(S.Reveal(M.Get(widget.bar, 'max')), start + 2))
		M.Advance(1)
		assert.is_true(math.abs(S.Reveal(M.Get(widget.bar, 'value')) - (start + 1)) < 0.06)
		widget.bar.SetTimerDuration = nil
		P.Caps.recorded.timerBars = nil
		Done(plate)
	end)

	it('holds a still full bar when neither the timer nor the times work', function()
		if not M.secrets then
			skip('cast times are always readable without secrets')
		end
		local plate, widget, unit = Live()
		widget.bar.SetTimerDuration = function()
			error('refused')
		end
		Restricted()
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 2 })
		assert.equal(S.Reveal(M.Get(widget.bar, 'value')), 1)
		assert.equal(S.Reveal(M.Get(widget.bar, 'max')), 1)
		widget.bar.SetTimerDuration = nil
		P.Caps.recorded.timerBars = nil
		Done(plate)
	end)
end)

describe('cast part: Era channels from data', function()
	it('leaves unreported channels alone where secrets exist', function()
		if not P.Caps:Get('secrets') then
			skip('Classic family only draws them')
		end
		local plate, widget = Live()
		M.Fire('UNIT_SPELLCAST_CHANNEL_START', TOKEN, 'Cast-9', 5143, nil)
		assert.is_nil(widget.state)
		Done(plate)
	end)

	it('draws a channel the unit does not report, from its listed length', function()
		if P.Caps:Get('secrets') then
			skip('clients with secrets report every channel')
		end
		local plate, widget = Live()
		M.Fire('UNIT_SPELLCAST_CHANNEL_START', TOKEN, 'Cast-9', 5143, nil)
		if P.Data.CLIENT_TIERS[P.Caps:Client()] ~= P.Data.CLIENT_TIERS.era then
			assert.is_nil(widget.state, 'Era lengths are not used on later content tiers')
			Done(plate)
			return
		end
		assert.equal(widget.state, 'casting')
		assert.equal(widget.kind, 'channel')
		assert.is_true(Near(widget.times.finish - widget.times.start, 3))
		assert.equal(Text(widget.name), C_Spell.GetSpellInfo(5143).name)
		M.Advance(1)
		assert.equal(widget.state, 'casting', 'other stop events do not end it')
		M.Fire('UNIT_SPELLCAST_CHANNEL_STOP', TOKEN, 'Cast-9', 5143, nil, nil)
		assert.equal(widget.state, 'done')
		Done(plate)
	end)

	it('knows Mind Control and Eyes of the Beast', function()
		if P.Data.CLIENT_TIERS[P.Caps:Client()] ~= P.Data.CLIENT_TIERS.era then
			assert.is_nil(Channels:Duration(605))
			return
		end
		assert.equal(Channels:Duration(605), 60)
		assert.equal(Channels:Duration(10912), 60)
		assert.equal(Channels:Duration(1002), 60)
		for key, why in pairs(Channels.unverified) do
			assert.equal(type(key), 'string')
			assert.equal(type(why), 'string')
		end
	end)

	it('ignores channels it has no length for', function()
		local plate, widget = Live()
		M.Fire('UNIT_SPELLCAST_CHANNEL_START', TOKEN, 'Cast-9', 424242, nil)
		assert.is_nil(widget.state)
		Done(plate)
	end)
end)

describe('cast part: above other plates', function()
	it('lifts the cast into a high frame at the plate scale while it shows', function()
		if not P.Caps:Get('castLift') then
			skip('this client cannot lift frames out of a plate')
		end
		local plate, widget, unit = Live({ above = true })
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 1 })
		assert.is_true(widget.lifted)
		assert.equal(widget.content:GetParent(), widget.lift)
		assert.equal(M.Get(widget.lift, 'strata'), 'HIGH')
		assert.equal(M.Get(widget.content, 'strata'), 'HIGH')
		assert.equal(M.Get(widget.lift, 'scale'), widget.frame:GetEffectiveScale())
		assert.equal(M.Get(widget.content, 'points')[1][2], widget.frame, 'anchored across parents')
		M.StopCast(unit, 'stop')
		M.Advance(0.5)
		assert.is_nil(widget.lifted)
		assert.equal(widget.content:GetParent(), widget.frame)
		assert.is_false(Shown(widget.lift))
		Done(plate)
	end)

	it('follows the plate alpha and scale, and hides with the plate', function()
		if not P.Caps:Get('castLift') then
			skip('this client cannot lift frames out of a plate')
		end
		local plate, widget, unit = Live({ above = true })
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 3 })
		assert.is_true(widget.lifted)
		plate.root:SetAlpha(0.5)
		plate.root:SetScale(0.8)
		M.Advance(0.15)
		assert.is_true(Near(M.Get(widget.lift, 'alpha'), 0.5), 'the lifted cast fades with its plate')
		assert.is_true(Near(M.Get(widget.lift, 'scale'), widget.frame:GetEffectiveScale()), 'and keeps its size')
		-- The game also hides it at once through the holder's OnHide; the mock does not pass
		-- OnHide down to children, so this checks the shared task's backstop
		plate.root:Hide()
		M.Advance(0.15)
		assert.is_false(Shown(widget.lift), 'hidden with the plate')
		plate.root:Show()
		M.Advance(0.15)
		assert.is_true(Shown(widget.lift))
		widget.frame:Hide()
		assert.is_false(Shown(widget.lift), 'the holder hiding takes it away at once')
		widget.frame:Show()
		assert.is_true(Shown(widget.lift))
		plate.root:SetAlpha(1)
		plate.root:SetScale(1)
		Done(plate)
		assert.is_false(Shown(widget.lift))
		assert.is_nil(Cast.liftActive[widget])
		M.Advance(0.25)
		assert.is_false(P.Scheduler:IsRunning('cast.lift'), 'the shared task stops with no lifted casts')
	end)

	it('stays on the plate without the setting', function()
		local plate, widget, unit = Live()
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 1 })
		assert.is_nil(widget.lifted)
		assert.equal(widget.content:GetParent(), widget.frame)
		Done(plate)
	end)
end)

describe('cast part: layout', function()
	it('stretches to the part it hangs from when it has no width of its own', function()
		local plate, widget = Live()
		local points = M.Get(widget.frame, 'points')
		assert.equal(#points, 2)
		assert.equal(points[1][1], 'TOPLEFT')
		assert.equal(points[2][1], 'TOPRIGHT')
		Done(plate)
		plate, widget = Live({ width = 90 })
		assert.equal(M.Get(widget.frame, 'w'), 90)
		assert.equal(#M.Get(widget.frame, 'points'), 1)
		Done(plate)
	end)

	it('passes the import check with the new fields', function()
		local style = {
			id = 'castImport',
			name = 'Cast import',
			version = 1,
			schema = 1,
			parts = { cast = { kind = 'cast', kickMark = false, interrupter = true, above = true } },
		}
		local _, report = P.Styles.Schema:ValidateStyle(style)
		assert.equal(report.dropped, 0)
		assert.equal(report.clamped, 0)
	end)
end)

describe('cast part: previews', function()
	it('draws and loops the sample cast with the sample interrupt state', function()
		local plate = P.Plate.New(UIParent, true)
		plate:ApplyStyle(Merge:Resolve('clean', 'enemyNPC', 'medium'))
		local src = P.Source.NewSample('casterTarget')
		plate:BindSample(src)
		local widget = plate:GetWidget('cast')
		assert.equal(widget.state, 'casting')
		assert.equal(Text(widget.name), src.sample.cast.name)
		assert.is_true(SameColor(BarColor(widget.bar), readyColor), 'the sample interrupt is ready')
		M.Advance(src.sample.cast.duration + 0.1)
		assert.equal(widget.state, 'casting', 'samples loop')
		assert.is_nil(widget.lifted, 'previews never lift')
		plate:Unbind()
	end)

	it('draws the kick mark for samples whose interrupt is cooling down', function()
		local plate = P.Plate.New(UIParent, true)
		plate:ApplyStyle(Merge:Resolve('clean', 'enemyNPC', 'medium'))
		local sample = {}
		for k, v in pairs(P.Data.Samples.casterTarget) do
			sample[k] = v
		end
		sample.kickReady = false
		plate:BindSample(P.Source.NewSample(sample))
		local widget = plate:GetWidget('cast')
		assert.equal(widget.kickMode, 'preview')
		assert.is_true(Shown(widget.kick))
		plate:Unbind()
	end)
end)

describe('cast part: under the strict secret mock', function()
	it('draws a whole cast from secret values without reading them', function()
		if not M.secrets then
			skip('no secrets on this client')
		end
		local restore = Swap({
			UnitNameFromGUID = function()
				return S.Wrap('Kicker')
			end,
			UnitClassFromGUID = function()
				return S.Wrap('Rogue'), S.Wrap('ROGUE'), S.Wrap(4)
			end,
			UnitSpellTargetName = function()
				return S.Wrap('Healbot')
			end,
			UnitSpellTargetClass = function()
				return S.Wrap('PRIEST')
			end,
			PlayerIsSpellTarget = function()
				return S.Wrap(true)
			end,
		})
		P.Context.kickSpell = 1766
		M.importantSpells = { [686] = true }
		local restoreColors = InstallClassColors()
		local restoreCooldown = InstallCooldown(function()
			return Cooldown(1, true)
		end)
		local plate, widget, unit = Live()
		assert.is_true(Restricted())
		assert.no_errors(function()
			M.StartCast(unit, { name = 'Shadow Bolt', spellID = 686, duration = 3, notInterruptible = true, castBarID = 5 })
		end)
		assert.equal(widget.state, 'casting')
		assert.secret(M.Get(widget.name, 'text'))
		assert.equal(Text(widget.name), 'Shadow Bolt')
		assert.equal(Alpha(widget.shield), 1)
		assert.is_true(M.Get(widget.shield, 'alphaSecret'))
		assert.equal(Alpha(widget.aimed), 1)
		assert.equal(Alpha(widget.important.gate), 1, 'the important glow shows from the hidden answer')
		assert.equal(Text(widget.target), 'Healbot')
		assert.is_true(M.Get(widget.bar, 'barColor').secret, 'the color comes from secret rows')
		unit.cast.notInterruptible = false
		assert.no_errors(function()
			M.UpdateUnit(unit, nil, { 'UNIT_SPELLCAST_INTERRUPTIBLE' })
		end)
		assert.equal(Alpha(widget.shield), 0)
		unit.cast = nil
		assert.no_errors(function()
			M.Fire('UNIT_SPELLCAST_INTERRUPTED', TOKEN, S.Wrap('Cast-5'), S.Wrap(686), S.Wrap('Player-1-KICK'), 5)
		end)
		assert.equal(widget.state, 'interrupted')
		assert.secret(M.Get(widget.name, 'text'))
		assert.equal(Text(widget.name), 'Interrupted by Kicker')
		M.Advance(2)
		assert.is_false(Shown(widget.content))
		local c = M.Get(widget.name, 'textColor')
		assert.is_true(c.secret == true and Near(c[1], CLASS_RGB.ROGUE[1]), 'the kicker name takes the class color')
		restoreCooldown()
		restoreColors()
		restore()
		M.importantSpells = nil
		Done(plate)
	end)

	it('finishes a cast whose stop event carries secret values', function()
		if not M.secrets then
			skip('no secrets on this client')
		end
		local plate, widget, unit = Live()
		Restricted()
		M.StartCast(unit, { name = 'Bolt', spellID = 778, duration = 1, channel = true })
		unit.cast = nil
		assert.no_errors(function()
			M.Fire('UNIT_SPELLCAST_CHANNEL_STOP', TOKEN, S.Wrap('Cast-6'), S.Wrap(778), nil, nil)
		end)
		assert.equal(widget.state, 'done')
		Done(plate)
	end)
end)
