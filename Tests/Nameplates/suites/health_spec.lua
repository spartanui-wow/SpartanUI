-- @runtime lua51
-- The health part and the shared bar helpers (Engine/Parts/Health.lua, Engine/Parts/Bar.lua):
-- the bar fills through sinks only, under the strict secret mock on Retail and Forever and with
-- plain values on the Classic family; shields come from the heal prediction calculator and fall
-- back to the unit when the calculator fails (S0); low health and execute are step overlays
-- (curves where secrets exist, plain math elsewhere); the lost-health chunk never compares
-- values; borders are whole physical pixels; frame levels leave text above the bar.
local M, H = ...
local S = M.S

if not H.ModuleExists() then
	describe('health', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

-- The mock lists CreateColor among engine functions and answers with a stub that returns
-- nothing; the game's CreateColor returns a ColorMixin, which curves and gradients need
if CreateColor and CreateColor(1, 1, 1, 1) == nil then
	rawset(_G, 'CreateColor', function(r, g, b, a)
		local color = {}
		for k, v in pairs(M.ColorMixin) do
			color[k] = v
		end
		color:SetRGBA(r, g, b, a)
		return color
	end)
end

M.Login('NameplatesTestHost')
local P = H.FreshCore()
local Merge = P.Styles.Merge
local BarLib = P.BarLib
local Prediction = P.Parts:Get('health').prediction

local TOKEN = 'nameplate9'
local NONE = {} -- removes a field from the test style
local serial = 0

---Register a one-off style holding a health bar (plus a power bar after it) and resolve it.
local function Style(fields, extra)
	serial = serial + 1
	local id = 'healthTest' .. serial
	local health = {
		order = 10,
		kind = 'bar',
		source = 'health',
		anchor = { 'CENTER', 'plate', 'CENTER', 0, 0 },
		fill = 'plate',
		texture = '$bar',
		border = { kind = 'pixel', size = 1, color = '$ink' },
		bg = '$shade',
		colors = 'health',
		borderColors = 'border',
		absorb = true,
		healAbsorb = true,
	}
	for k, v in pairs(fields or {}) do
		if v == NONE then
			health[k] = nil
		else
			health[k] = v
		end
	end
	local parts = { health = health }
	for k, v in pairs(extra or {}) do
		parts[k] = v
	end
	P.Styles.Registry:RegisterBuiltin({
		id = id,
		name = id,
		version = 1,
		schema = 1,
		order = 5000 + serial,
		internal = true,
		plate = { sizes = { small = { 100, 8 }, medium = { 120, 10 }, large = { 140, 12 } } },
		tokens = { accent = '$host', font = '$host', bar = 'Nameplates Flat', ink = { 0, 0, 0, 1 }, shade = { 0, 0, 0, 0.6 } },
		parts = parts,
		states = { target = { grow = { 10, 2 } } },
	})
	return Merge:Resolve(id, 'enemyNPC', 'medium')
end

local function Unit(spec)
	local unit = M.AddUnit(spec or { health = 900, healthMax = 1000 })
	M.SetToken(TOKEN, unit)
	return unit
end

---A bound live plate on a fresh unit. Returns plate, health widget, unit.
local function Live(fields, unitSpec, extra)
	local unit = Unit(unitSpec)
	local plate = P.Plate.New(UIParent, false)
	plate:ApplyStyle(Style(fields, extra))
	plate:Bind(TOKEN, P.Source.NewLive(TOKEN))
	return plate, plate:GetWidget('health'), unit
end

local function Value(bar)
	return S.Reveal(M.Get(bar, 'value'))
end

local function Max(bar)
	return S.Reveal(M.Get(bar, 'max'))
end

local function Alpha(region)
	return M.Get(region, 'alpha')
end

local function VertexAlpha(texture)
	local c = M.Get(texture, 'vertex')
	return c and c[4]
end

local function Hit(unit, health, event)
	M.UpdateUnit(unit, { health = health }, { event or 'UNIT_HEALTH' })
end

local function Done(plate)
	plate:Unbind()
	M.SetToken(TOKEN, nil)
	M.SetRestricted(false)
end

---A stand-in heal prediction calculator driven by the mock units. Values come back secret for
---restricted units, the way the game's calculator hands them out.
local realCreate = rawget(_G, 'CreateUnitHealPredictionCalculator')
local realFill = rawget(_G, 'UnitGetDetailedHealPrediction')

local function InstallCalculator(opts)
	opts = opts or {}
	local Calc = {}
	Calc.__index = Calc
	for _, name in ipairs({ 'SetMaximumHealthMode', 'SetDamageAbsorbClampMode', 'SetHealAbsorbClampMode', 'SetHealAbsorbMode' }) do
		Calc[name] = function(self, value)
			self.modes[name] = value
		end
	end
	function Calc:GetMaximumHealth()
		return self.v.max
	end
	function Calc:GetCurrentHealth()
		return self.v.health
	end
	function Calc:GetDamageAbsorbs()
		return self.v.absorb, self.v.clamped
	end
	function Calc:GetHealAbsorbs()
		return self.v.heal, self.v.healClamped
	end
	local made = {}
	rawset(_G, 'CreateUnitHealPredictionCalculator', function()
		local calc = setmetatable({ modes = {}, v = {} }, Calc)
		made[#made + 1] = calc
		return calc
	end)
	rawset(_G, 'UnitGetDetailedHealPrediction', function(token, _, calc)
		if opts.fail then
			error('calculator broke')
		end
		local u = M.UnitFor(token)
		local withAbsorbs = calc.modes.SetMaximumHealthMode == Enum.UnitMaximumHealthMode.WithAbsorbs
		local absorbs, maxValue = u.absorbs or 0, u.healthMax
		local cap = withAbsorbs and maxValue or (maxValue - u.health)
		local amount = math.min(absorbs, cap)
		local wrap = M.IsRestrictedUnit(token) and S.Wrap or function(v)
			return v
		end
		calc.v = {
			max = wrap(opts.wrongMax and 0 or withAbsorbs and (maxValue + absorbs) or maxValue),
			health = wrap(u.health),
			absorb = wrap(amount),
			clamped = wrap(absorbs > cap),
			heal = wrap(math.min(u.healAbsorbs or 0, u.health)),
			healClamped = wrap(false),
		}
	end)
	Prediction:Reset()
	P.Caps.recorded.healPrediction = nil
	P.Caps.values.healPrediction = nil
	return made
end

local function RemoveCalculator()
	rawset(_G, 'CreateUnitHealPredictionCalculator', realCreate)
	rawset(_G, 'UnitGetDetailedHealPrediction', realFill)
	Prediction:Reset()
	P.Caps.recorded.healPrediction = nil
	P.Caps.values.healPrediction = nil
end

describe('health: the bar', function()
	it('is the health bar other modules read, with a real background file', function()
		local plate, widget = Live()
		assert.is_true(rawequal(plate:GetHealthBar(), widget.bar))
		assert.is_true(rawequal(widget.frame, widget.bar))
		assert.equal(M.Get(widget.bar.bg, 'texture'), BarLib.WHITE)
		assert.equal(Value(widget.bar), 900)
		assert.equal(Max(widget.bar), 1000)
		Done(plate)
	end)

	it('fills from hidden values without reading them', function()
		local plate, widget, unit = Live(nil, { health = 400, healthMax = 800, absorbs = 0 })
		if M.SetRestricted(true) then
			Hit(unit, 300)
			assert.secret(M.Get(widget.bar, 'value'), 'the bar holds the hidden value')
			assert.secret(M.Get(widget.bar, 'max'))
			assert.equal(Value(widget.bar), 300)
			assert.equal(Max(widget.bar), 800)
			-- Color events still color the bar from the list while values are hidden
			plate:Refresh({ colors = true })
			assert.not_nil(M.Get(widget.bar, 'barColor'))
		else
			Hit(unit, 300)
			assert.not_secret(M.Get(widget.bar, 'value'))
			assert.equal(Value(widget.bar), 300)
		end
		Done(plate)
	end)

	it('never reads its own size back', function()
		local unit = Unit()
		local plate = P.Plate.New(UIParent, false)
		plate:ApplyStyle(Style())
		local widget = plate:GetWidget('health')
		for _, method in ipairs({ 'GetWidth', 'GetHeight', 'GetSize', 'GetRect', 'GetValue', 'GetMinMaxValues', 'GetStatusBarColor' }) do
			widget.bar[method] = function()
				error('read the health bar back: ' .. method)
			end
		end
		plate:Bind(TOKEN, P.Source.NewLive(TOKEN))
		M.SetRestricted(true)
		Hit(unit, 500)
		plate:Layout()
		Done(plate)
	end)

	it('eases to new values only after the first fill, and only when the style wants it', function()
		local function Record(widget)
			local calls = {}
			local original = widget.bar.SetValue
			widget.bar.SetValue = function(self, ...)
				calls[#calls + 1] = { n = select('#', ...), interpolation = (select(2, ...)) }
				return original(self, ...)
			end
			return calls
		end
		local unit = Unit()
		local plate = P.Plate.New(UIParent, false)
		plate:ApplyStyle(Style())
		local calls = Record(plate:GetWidget('health'))
		plate:Bind(TOKEN, P.Source.NewLive(TOKEN))
		assert.equal(calls[#calls].n, 1, 'the first fill is instant and passes no easing argument')
		Hit(unit, 700)
		if P.Caps:Get('barInterpolation') then
			assert.equal(calls[#calls].n, 2)
			assert.equal(calls[#calls].interpolation, Enum.StatusBarInterpolation.ExponentialEaseOut)
		else
			assert.equal(calls[#calls].n, 1)
		end
		Done(plate)

		unit = Unit()
		plate = P.Plate.New(UIParent, false)
		plate:ApplyStyle(Style({ interpolate = false }))
		calls = Record(plate:GetWidget('health'))
		plate:Bind(TOKEN, P.Source.NewLive(TOKEN))
		Hit(unit, 600)
		assert.equal(calls[#calls].n, 1, 'interpolate = false never eases')
		Done(plate)
	end)

	it('colors the bar and the lost-health chunk from the same list', function()
		local plate, widget = Live({ lostHealth = true })
		local bar = M.Get(widget.bar, 'barColor')
		local chunk = M.Get(widget.chunk, 'barColor')
		assert.not_nil(bar)
		assert.same({ chunk[1], chunk[2], chunk[3] }, { bar[1], bar[2], bar[3] })
		Done(plate)
	end)

	it('uses a fixed color when the style names one and no list', function()
		local plate, widget = Live({ colors = NONE, color = { 0.1, 0.2, 0.3, 1 } })
		local c = M.Get(widget.bar, 'barColor')
		assert.near(c[1], 0.1, 1e-6)
		assert.near(c[3], 0.3, 1e-6)
		Done(plate)
	end)
end)

describe('health: shields without the calculator', function()
	it('falls back to the unit when the game gives no calculator, and says why once', function()
		RemoveCalculator()
		local plate, widget = Live(nil, { health = 900, healthMax = 1000, absorbs = 300, healAbsorbs = 50 })
		if P.Caps:Get('healPrediction') then
			assert.fail('the mock calculator is a stub, so the check must fail')
		end
		assert.is_true(Prediction.failed)
		assert.equal(Value(widget.absorbBar), 300)
		assert.equal(Max(widget.absorbBar), 1000)
		assert.equal(Value(widget.healAbsorbBar), 50)
		assert.equal(Alpha(widget.glow), 1, 'readable values: the shield is bigger than the missing health')
		local limits = P.Parts:Get('health').Limits()
		if P.Caps:Get('secrets') then
			assert.not_equal(#limits, 0, 'the options can say why')
		else
			assert.equal(#limits, 0, 'plain values do everything the calculator did')
		end
		Done(plate)
	end)

	it('keeps the glow off when the values are hidden, instead of guessing', function()
		local plate, widget, unit = Live(nil, { health = 900, healthMax = 1000, absorbs = 300 })
		if not M.SetRestricted(true) then
			skip('no secrets on this client')
		end
		M.UpdateUnit(unit, { absorbs = 400 }, { 'UNIT_ABSORB_AMOUNT_CHANGED' })
		assert.secret(M.Get(widget.absorbBar, 'value'))
		assert.equal(Value(widget.absorbBar), 400)
		assert.equal(Alpha(widget.glow), 0)
		Done(plate)
	end)

	it('makes room for the whole shield only where it can add the numbers', function()
		local plate, widget, unit = Live({ absorbMode = 'extend' }, { health = 900, healthMax = 1000, absorbs = 300 })
		assert.equal(Max(widget.bar), 1300)
		if M.SetRestricted(true) then
			Hit(unit, 800)
			assert.equal(Max(widget.bar), 1000, 'hidden values: the plain maximum')
		end
		Done(plate)
	end)

	it('registers shield events only for the shields the style shows', function()
		local plate = Live({ absorb = false, healAbsorb = false })
		local events = P.Parts:Get('health').events(plate:GetWidget('health').spec)
		assert.same(events, { 'UNIT_HEALTH', 'UNIT_MAXHEALTH' })
		assert.is_false(plate:GetWidget('health').absorbBar:IsShown() and true or false)
		Done(plate)
	end)
end)

describe('health: the heal prediction calculator (S0)', function()
	after_each(function()
		RemoveCalculator()
	end)

	it('clamps shields to the missing health and lights the glow from the clamp flag', function()
		local made = InstallCalculator()
		local plate, widget, unit = Live(nil, { health = 900, healthMax = 1000, absorbs = 300, healAbsorbs = 50 })
		assert.is_true(Prediction.verified)
		assert.equal(made[1].modes.SetMaximumHealthMode, Enum.UnitMaximumHealthMode.Default)
		assert.equal(made[1].modes.SetDamageAbsorbClampMode, Enum.UnitDamageAbsorbClampMode.MissingHealthWithoutIncomingHeals)
		assert.equal(Value(widget.absorbBar), 100)
		assert.equal(Alpha(widget.glow), 1)
		if M.SetRestricted(true) then
			Hit(unit, 500)
			assert.secret(M.Get(widget.bar, 'value'))
			assert.equal(Value(widget.bar), 500)
			assert.equal(Value(widget.absorbBar), 300)
			assert.equal(Alpha(widget.glow), 0, 'the hidden clamp flag drives the glow')
			assert.equal(Value(widget.healAbsorbBar), 50)
		end
		Done(plate)
	end)

	it('extends the bar with the whole shield in extend mode', function()
		local made = InstallCalculator()
		local plate, widget = Live({ absorbMode = 'extend' }, { health = 900, healthMax = 1000, absorbs = 300 })
		local calc
		for _, c in ipairs(made) do
			if c.modes.SetMaximumHealthMode == Enum.UnitMaximumHealthMode.WithAbsorbs then
				calc = c
			end
		end
		assert.not_nil(calc, 'a calculator in WithAbsorbs mode')
		assert.equal(calc.modes.SetDamageAbsorbClampMode, Enum.UnitDamageAbsorbClampMode.MaximumHealth)
		assert.equal(Max(widget.bar), 1300)
		assert.equal(Value(widget.absorbBar), 300)
		Done(plate)
	end)

	it('stops using a calculator that keeps erroring and reads the unit instead', function()
		InstallCalculator({ fail = true })
		local plate, widget, unit = Live(nil, { health = 650, healthMax = 1000, absorbs = 20 })
		assert.is_false(Prediction.failed, 'one bad fill does not decide it')
		assert.equal(Value(widget.bar), 650, 'that update reads the unit')
		Hit(unit, 640)
		Hit(unit, 630)
		assert.is_true(Prediction.failed)
		assert.is_false(P.Caps:Get('healPrediction'))
		Hit(unit, 620)
		assert.equal(Value(widget.bar), 620)
		assert.equal(Value(widget.absorbBar), 20)
		Done(plate)
	end)

	it('keeps a working calculator when one later fill fails', function()
		local failing = false
		InstallCalculator()
		local plate, widget, unit = Live(nil, { health = 700, healthMax = 1000, absorbs = 500 })
		assert.is_true(Prediction.verified)
		local fill = rawget(_G, 'UnitGetDetailedHealPrediction')
		rawset(_G, 'UnitGetDetailedHealPrediction', function(...)
			if failing then
				error('one bad token')
			end
			return fill(...)
		end)
		failing = true
		Hit(unit, 600)
		assert.equal(Value(widget.bar), 600)
		assert.equal(Value(widget.absorbBar), 500, 'read straight from the unit for that update')
		failing = false
		Hit(unit, 550)
		assert.is_false(Prediction.failed)
		assert.equal(Value(widget.absorbBar), 450, 'the calculator clamps again')
		Done(plate)
	end)

	it('does not trust a calculator whose health does not match the unit where values are plain', function()
		if P.Caps:Get('secrets') then
			skip('the check trusts the game where values can be hidden')
		end
		InstallCalculator({ wrongMax = true })
		local plate, widget, unit = Live(nil, { health = 600, healthMax = 1000, absorbs = 100 })
		assert.is_false(Prediction.verified)
		assert.equal(Value(widget.bar), 600, 'the bar reads the unit, never the bad maximum')
		assert.equal(Max(widget.bar), 1000)
		assert.equal(Value(widget.absorbBar), 100)
		Hit(unit, 590)
		Hit(unit, 580)
		assert.is_true(Prediction.failed)
		assert.equal(Max(widget.bar), 1000)
		Done(plate)
	end)

	it('reads samples directly, so previews never touch the calculator', function()
		InstallCalculator()
		local plate = P.Plate.New(UIParent, true, P.Scenes and P.Scenes.PreviewContext and P.Scenes.PreviewContext({}) or nil)
		plate:ApplyStyle(Style())
		plate:BindSample(P.Source.NewSample({ health = 30, healthMax = 100, absorb = 10, healAbsorb = 5, facts = { reaction = 2, canAttack = true } }))
		local widget = plate:GetWidget('health')
		assert.equal(Value(widget.bar), 30)
		assert.equal(Value(widget.absorbBar), 10)
		assert.equal(Value(widget.healAbsorbBar), 5)
		assert.equal(Alpha(widget.glow), 0)
		assert.is_false(Prediction.verified)
		plate:Unbind()
	end)
end)

describe('health: low health and execute', function()
	local Store = P.Store

	after_each(function()
		Store:Set('colors', nil)
		Store:Set('scheme', 'auto')
	end)

	it('draws the low health row of the color list as an overlay at or below its threshold', function()
		Store:Set('scheme', 'custom')
		Store:Set('colors.health.order', { 'lowHealth', 'reaction' })
		local plate, widget, unit = Live(nil, { health = 200, healthMax = 1000 })
		assert.not_nil(P.Colors:Program('health').overlay, 'the row compiles to an overlay')
		assert.is_true(widget.low:IsShown() and true or false)
		assert.equal(VertexAlpha(widget.low), 1, 'at 20% health the overlay shows')
		Hit(unit, 800)
		assert.equal(VertexAlpha(widget.low), 0, 'at 80% it is clear')
		if M.SetRestricted(true) then
			Hit(unit, 100)
			assert.equal(VertexAlpha(widget.low), 1, 'hidden health still drives it through the curve')
			Hit(unit, 900)
			assert.equal(VertexAlpha(widget.low), 0)
		end
		Done(plate)
	end)

	it('hides the overlay when the list has no low health row', function()
		local plate, widget = Live(nil, { health = 100, healthMax = 1000 })
		assert.is_false(widget.low:IsShown() and true or false)
		Done(plate)
	end)

	it("follows the low health row's When setting", function()
		Store:Set('scheme', 'custom')
		Store:Set('colors.health.order', { 'lowHealth', 'reaction' })
		Store:Set('colors.health.when', { lowHealth = 'never' })
		local plate, widget = Live(nil, { health = 100, healthMax = 1000 })
		assert.is_false(widget.low:IsShown() and true or false, 'never: no overlay at 10% health')
		Store:Set('colors.health.when', nil)
		plate:Refresh({ colors = true })
		assert.is_true(widget.low:IsShown() and true or false)
		assert.equal(VertexAlpha(widget.low), 1)
		Done(plate)
	end)

	it('keeps the curve after a read error, and uses plain health after the game refuses its color (S5)', function()
		Store:Set('scheme', 'custom')
		Store:Set('colors.health.order', { 'lowHealth', 'reaction' })
		local plate, widget, unit = Live(nil, { health = 200, healthMax = 1000 })
		local src = plate.src
		local read = src.HealthPercentSecret
		src.HealthPercentSecret = function()
			error('one bad token')
		end
		Hit(unit, 150)
		assert.is_nil(P.Caps.recorded.healthCurves, 'a failed read says nothing about the curve')
		assert.equal(VertexAlpha(widget.low), 1, 'plain health drew it')
		src.HealthPercentSecret = read
		if not P.Caps:Get('secrets') then
			Done(plate)
			skip('no curves on this client')
		end
		widget.low.SetVertexColorFromBoolean = function()
			error('refused')
		end
		Hit(unit, 120)
		assert.is_false(P.Caps:Get('healthCurves'))
		assert.equal(VertexAlpha(widget.low), 1, 'readable health: the plain math shows it')
		local found
		for _, line in ipairs(P.Parts:Get('health').Limits()) do
			found = found or line:find('see health', 1, true)
		end
		assert.not_nil(found, 'the options say why')
		M.SetRestricted(true)
		Hit(unit, 100)
		assert.equal(VertexAlpha(widget.low), 0, 'hidden health: clear instead of guessing')
		widget.low.SetVertexColorFromBoolean = nil
		P.Caps.recorded.healthCurves = nil
		Done(plate)
	end)

	it('shows the execute band below the threshold and puts the mark at it', function()
		local plate, widget, unit = Live({ execute = 0.3, executeColor = { 1, 0, 0, 1 } }, { health = 200, healthMax = 1000 })
		assert.is_true(widget.mark:IsShown() and true or false)
		assert.near(VertexAlpha(widget.band), 0.35, 1e-6, 'band at 20% health')
		Hit(unit, 500)
		assert.equal(VertexAlpha(widget.band), 0)
		if M.SetRestricted(true) then
			Hit(unit, 250)
			assert.near(VertexAlpha(widget.band), 0.35, 1e-6)
		end
		-- The mark sits at 30% of the bar's width, centered on its two pixels
		local width = widget.width
		local _, _, _, x = widget.mark:GetPoint(1)
		assert.near(x, 0.3 * width - widget.pixel, 1e-6)
		Done(plate)
	end)

	it('moves the mark and the shield bars when the bar changes size, even if the size is hidden', function()
		local plate, widget = Live({ execute = 0.5 })
		local onSize = widget.over:GetScript('OnSizeChanged')
		onSize(widget.over, 200, 10)
		assert.equal(M.Get(widget.absorbBar, 'w'), 200)
		local _, _, _, x = widget.mark:GetPoint(1)
		assert.near(x, 100 - widget.pixel, 1e-6)
		onSize(widget.over, S.Wrap(300), S.Wrap(10))
		assert.equal(M.Get(widget.absorbBar, 'w'), plate.emW, 'a hidden size falls back to the width the plate applied')
		Done(plate)
	end)

	it('puts the mark from the right on a bar that fills from the right', function()
		local plate, widget = Live({ execute = 0.25, reverse = true })
		local point = widget.mark:GetPoint(1)
		assert.equal(point, 'TOPRIGHT')
		assert.is_true(M.Get(widget.absorbBar, 'reverseFill') and true or false)
		assert.is_false(M.Get(widget.healAbsorbBar, 'reverseFill') and true or false)
		Done(plate)
	end)
end)

describe('health: the lost-health chunk', function()
	it('shows the health just lost, holds it, then fades it on the shared scheduler', function()
		local plate, widget, unit = Live({ lostHealth = true }, { health = 1000, healthMax = 1000 })
		assert.is_true(widget.chunkClip:IsShown() and true or false)
		assert.equal(Alpha(widget.chunk), 0)
		assert.equal(Value(widget.chunk), 1000)
		Hit(unit, 600)
		assert.equal(Value(widget.chunk), 1000, 'the chunk keeps the old value')
		assert.equal(Value(widget.bar), 600)
		assert.equal(Alpha(widget.chunk), 1)
		M.Advance(0.1)
		assert.equal(Alpha(widget.chunk), 1, 'held at full for a moment')
		M.Advance(1)
		assert.equal(Alpha(widget.chunk), 0)
		assert.is_false(widget.chunkFading)
		Done(plate)
	end)

	it('keeps the oldest value through a burst of hits', function()
		local plate, widget, unit = Live({ lostHealth = true }, { health = 1000, healthMax = 1000 })
		Hit(unit, 800)
		M.Advance(0.1)
		Hit(unit, 500)
		assert.equal(Value(widget.chunk), 1000)
		M.Advance(1)
		Hit(unit, 400)
		assert.equal(Value(widget.chunk), 500, 'after the fade the next hit starts from the last value')
		Done(plate)
	end)

	it('works on hidden values without comparing them', function()
		if not M.SetRestricted(true) then
			skip('no secrets on this client')
		end
		local plate, widget, unit = Live({ lostHealth = true }, { health = 1000, healthMax = 1000 })
		assert.secret(M.Get(widget.chunk, 'value'))
		Hit(unit, 700)
		assert.secret(M.Get(widget.chunk, 'value'))
		assert.equal(Value(widget.chunk), 1000)
		Hit(unit, 900)
		M.Advance(1)
		Hit(unit, 650)
		assert.equal(Value(widget.chunk), 900, 'a heal during the fade is kept as the next start')
		Done(plate)
	end)

	it('stops and clears on unbind', function()
		local plate, widget, unit = Live({ lostHealth = true }, { health = 1000, healthMax = 1000 })
		Hit(unit, 500)
		plate:Unbind()
		assert.equal(Alpha(widget.chunk), 0)
		assert.is_false(widget.chunkFading)
		assert.is_nil(widget.lastHealthSecret)
		M.Advance(1)
		assert.equal(Alpha(widget.chunk), 0)
		M.SetToken(TOKEN, nil)
	end)

	it('is off unless the style asks for it', function()
		local plate, widget, unit = Live(nil, { health = 1000, healthMax = 1000 })
		assert.is_false(widget.chunkClip:IsShown() and true or false)
		Hit(unit, 500)
		assert.equal(Alpha(widget.chunk), 0)
		Done(plate)
	end)
end)

describe('health: borders and levels', function()
	local function Thickness(widget)
		return M.Get(widget.bar.border.edges.top, 'h')
	end

	it('draws a 1 px border as one physical pixel on each side', function()
		local plate, widget = Live()
		local edges = widget.bar.border.edges
		assert.equal(#edges, 4)
		assert.near(Thickness(widget), widget.pixel, 1e-9)
		assert.near(M.Get(edges.left, 'w'), widget.pixel, 1e-9)
		assert.near(widget.pixel, 768 / 1080 / UIParent:GetEffectiveScale(), 1e-9)
		Done(plate)
	end)

	it('draws thick, shadow and beveled borders in whole pixels and hides none', function()
		local thick = Live({ border = { kind = 'thick', size = 1, color = { 0, 0, 0, 1 } } })
		local w = thick:GetWidget('health')
		assert.near(Thickness(w), 2 * w.pixel, 1e-9)
		Done(thick)
		local shadow = Live({ border = { kind = 'shadow', size = 1, color = { 0, 0, 0, 1 } } })
		w = shadow:GetWidget('health')
		assert.near(Thickness(w), 3 * w.pixel, 1e-9)
		Done(shadow)
		local bevel = Live({ border = { kind = 'beveled', size = 1, color = { 0.5, 0.5, 0.5, 1 } }, borderColors = NONE })
		w = bevel:GetWidget('health')
		local top, bottom = M.Get(w.bar.border.edges.top, 'vertex'), M.Get(w.bar.border.edges.bottom, 'vertex')
		assert.is_true(top[1] > bottom[1], 'light top, dark bottom')
		Done(bevel)
		local none = Live({ border = { kind = 'none' }, borderColors = NONE })
		w = none:GetWidget('health')
		assert.is_false(w.bar.border:IsShown() and true or false)
		Done(none)
	end)

	it('places a 1 px border again when the game reuses the plate at another scale', function()
		local plate, widget = Live()
		local before = widget.pixel
		plate:Unbind()
		-- Stands in for the game drawing this base plate larger for its next unit
		plate.root:SetScale(1.25)
		plate:Bind(TOKEN, P.Source.NewLive(TOKEN))
		assert.near(widget.pixel, before / 1.25, 1e-9)
		assert.near(Thickness(widget), widget.pixel, 1e-9)
		assert.near(M.Get(widget.glow, 'w'), 3 * widget.pixel, 1e-9)
		plate:Unbind()
		plate.root:SetScale(1)
		plate:Bind(TOKEN, P.Source.NewLive(TOKEN))
		assert.near(Thickness(widget), before, 1e-9)
		Done(plate)
	end)

	it('works without clipping: no lost-health piece, shields clamped in Lua where readable', function()
		RemoveCalculator()
		P.Caps:SetOverride('clipChildren', false)
		local plate, widget = Live({ lostHealth = true }, { health = 900, healthMax = 1000, absorbs = 300 })
		assert.is_false(widget.clips and true or false)
		assert.is_false(widget.chunkClip:IsShown() and true or false)
		assert.equal(Value(widget.absorbBar), 100, 'clamped to the missing health')
		assert.equal(Alpha(widget.glow), 1)
		local found
		for _, line in ipairs(P.Parts:Get('health').Limits()) do
			found = found or line:find('lost health', 1, true)
		end
		assert.not_nil(found)
		Done(plate)
		P.Caps:SetOverride('clipChildren', nil)
	end)

	it('hands one hidden color to every edge of a border', function()
		local plate, widget = Live()
		local target = BarLib.BorderTarget(widget.bar.border)
		target:SetVertexColor(S.Wrap(0.2), S.Wrap(0.4), S.Wrap(0.6), S.Wrap(1))
		for _, edge in ipairs(widget.bar.border.edges) do
			local c = M.Get(edge, 'vertex')
			assert.near(c[2], 0.4, 1e-9)
		end
		Done(plate)
	end)

	it('keeps its overlays between the bar and the next part', function()
		local plate, widget = Live(nil, nil, {
			power = { order = 20, kind = 'bar', source = 'power', anchor = { 'TOP', 'health', 'BOTTOM', 0, -2 }, height = 4, color = { 0, 0, 1, 1 } },
		})
		local level = M.Get(widget.bar, 'level')
		assert.equal(M.Get(widget.absorbBar, 'level'), level + 2)
		assert.equal(M.Get(widget.chunk, 'level'), level + 2)
		assert.equal(M.Get(widget.over, 'level'), level + 1)
		local power = plate:GetWidget('power')
		assert.is_true(M.Get(power.frame, 'level') > level + 2, 'the next part draws above the shields')
		Done(plate)
	end)
end)

describe('bar: power', function()
	it('fills from the unit power through sinks, hidden or not', function()
		local plate = Live(nil, { health = 500, healthMax = 1000, power = 40, powerMax = 100 }, {
			power = { order = 20, kind = 'bar', source = 'power', anchor = { 'TOP', 'health', 'BOTTOM', 0, -2 }, height = 4 },
		})
		local power = plate:GetWidget('power')
		assert.equal(power.impl.id, 'bar')
		assert.equal(S.Reveal(M.Get(power.frame, 'value')), 40)
		assert.equal(S.Reveal(M.Get(power.frame, 'max')), 100)
		if M.SetRestricted(true) then
			M.UpdateUnit(M.UnitFor(TOKEN), { power = 30 }, { 'UNIT_POWER_UPDATE' })
			assert.equal(S.Reveal(M.Get(power.frame, 'value')), 30)
		end
		Done(plate)
	end)
end)

describe('health: built-in styles', function()
	it('lays out and fills every built-in style that has a health bar', function()
		for _, id in ipairs(P.Styles.Registry.order) do
			local resolved = Merge:Resolve(id, 'enemyNPC', 'medium')
			if resolved.parts.health then
				local unit = Unit({ health = 300, healthMax = 600, absorbs = 50 })
				local plate = P.Plate.New(UIParent, false)
				plate:ApplyStyle(resolved)
				plate:Bind(TOKEN, P.Source.NewLive(TOKEN))
				local widget = plate:GetWidget('health')
				assert.equal(widget.impl.id, 'health', id)
				assert.equal(Value(widget.bar), 300, id)
				M.SetRestricted(true)
				Hit(unit, 200)
				assert.equal(Value(widget.bar), 200, id)
				Done(plate)
			end
		end
	end)
end)
