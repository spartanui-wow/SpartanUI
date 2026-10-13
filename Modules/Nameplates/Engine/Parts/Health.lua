local _, ns = ...
local P = ns.Plates
local L = P.L
local Secret = P.Secret
local BarLib = P.BarLib

-- Health bar (kind 'bar', source 'health') with absorbs, heal absorbs, the low-health overlay, the
-- execute band and mark, and the lost-health chunk (4, 5.1, 5.5, 6.3).
--
-- Contract: widget.bar (= widget.frame) is the health StatusBar (P.API:GetHealthBar, LastTick).
--
-- What it draws, bottom to top (frame levels relative to the bar, L; P.LayoutContext.PART_LEVELS leaves room):
--   L    the bar: background, fill, the low-health overlay and the execute band (both over the fill)
--   L+1  border holder (edges outside the bar), the lost-health clip (from the fill edge to the
--        bar's end) and the overlay clip (over the whole bar: execute mark, shield glow)
--   L+2  the lost-health chunk, the absorb bar (starts at the fill edge) and the heal-absorb bar
--        (ends at the fill edge), each inside its clip
--
-- Values (never read in Lua where the game can hide them):
--   * Health and absorbs come from the heal prediction calculator where it works
--     (CreateUnitHealPredictionCalculator + src:FillHealPrediction). absorbMode 'overlay' (the
--     default) clamps shields to the missing health and lights the shield glow from the clamp
--     flag; 'extend' makes room for the whole shield (the bar's maximum includes it). Every fill
--     runs in pcall, and the first good fill is the S0 runtime check (the Classic family has the
--     calculator documented but unproven): on clients without secrets the calculator's health and
--     maximum must also match the unit's own, so a calculator that answers zeros never empties a
--     bar. Three failed checks before any good one turn it off for the session:
--     Caps:Record('healPrediction', false), and every bar reads src:HealthSecret(),
--     src:HealthMaxSecret(), src:AbsorbSecret() and src:HealAbsorbSecret() instead. That path
--     clips shields at the bar's end and only does glow and 'extend' math where values are
--     readable (always on the Classic family).
--   * Sinks: SetMinMaxValues, SetValue(value, Enum.StatusBarInterpolation.ExponentialEaseOut)
--     where Caps barInterpolation says so (never on the first fill), P.Colors:Apply with
--     'SetStatusBarColor' (spec.colors, default 'health') and with BarLib.BorderTarget for
--     spec.borderColors, P.Secret.SetAlphaFromBoolean for the shield glow.
--   * Low health is the color list's curve row (program.overlay, shown where its "When" clause
--     applies), drawn here as an overlay over the fill. Execute (spec.execute, a health fraction)
--     is a band over the fill plus a mark at the threshold. Both use a step ColorCurve
--     (P.Colors:BuildStepCurve) through src:HealthPercentSecret(curve) on clients with secrets
--     (S5), whose color (alpha 0 above the threshold) reaches the texture through
--     SetVertexColorFromBoolean; clients without secrets use plain math from src:HealthPlain(),
--     as the plan asks. S5 fallback: if the game refuses the curve's color, capability
--     healthCurves is recorded false for the session (also `/sui np cap healthCurves off`) and
--     the overlays use the plain math, which shows them whenever health is readable and leaves
--     them clear while it is hidden. The mark never needs health and always shows.
--   * Borders are whole physical pixels from the layout, placed again on every bind when the
--     plate's scale changed (BarLib.Resnap): the game reuses a base plate for units it draws at
--     other scales.
--   * The lost-health chunk (spec.lostHealth) keeps the previous health value, possibly secret,
--     in widget.lastHealthSecret, sets it on a second bar clipped to the part right of the live
--     fill edge, then fades that bar on the shared scheduler. Nothing compares the two values: a
--     heal leaves the chunk entirely behind the fill, where the clip hides it. Hits that land
--     while it fades keep the oldest value, so a burst shows as one chunk.
--   * The mark's place and the shield bars' width come from the bar's width, measured on the
--     overlay clip (it never holds a value, so the game does not hide its size) and otherwise
--     from the layout (BarLib.LayoutWidth). The clip's OnSizeChanged keeps them right while the
--     target grows.

local HEALTH_EVENTS = { UNIT_HEALTH = true, UNIT_MAXHEALTH = true, UNIT_ABSORB_AMOUNT_CHANGED = true, UNIT_HEAL_ABSORB_AMOUNT_CHANGED = true }
local LOSS_EVENTS = { UNIT_HEALTH = true, UNIT_MAXHEALTH = true }

local DEFAULT_ABSORB = { 1, 1, 1, 0.45 }
local DEFAULT_HEAL_ABSORB = { 0.55, 0.05, 0.05, 0.75 }
local DEFAULT_EXECUTE = { 1, 1, 1, 0.9 }
local BAND_ALPHA = 0.35 -- the execute band is the execute color at this share of its alpha
local CHUNK_HOLD = 0.6 -- the chunk eases from 1 + hold to 0 and shows min(value, 1): a short hold
local CHUNK_TIME = 0.7
local GLOW_PIXELS = 3
local MARK_PIXELS = 2

----------------------------------------------------------------------------------------------------
-- Heal prediction calculator (S0)
----------------------------------------------------------------------------------------------------

---@class Plates.HealthPrediction
local Prediction = { calculators = {}, verified = false, failed = false, reason = nil }

---Stop using the calculator for this session and say why.
---@param reason string
function Prediction:Fail(reason)
	if self.failed then
		return
	end
	self.failed = true
	self.reason = reason
	P.Caps:Record('healPrediction', false)
	P.log.warning('Heal prediction is off, health bars read the unit directly: ' .. tostring(reason))
end

---Forget calculators and the check (a capability override was cleared, or tests).
function Prediction:Reset()
	P.util.Wipe(self.calculators)
	self.verified, self.failed, self.reason, self.errors, self.warned = false, false, nil, 0, nil
end

local function MakeCalculator(mode)
	local calc = CreateUnitHealPredictionCalculator()
	if not calc then
		return nil
	end
	if mode == 'extend' then
		calc:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.WithAbsorbs)
		calc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth)
	else
		calc:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
		calc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealthWithoutIncomingHeals)
	end
	calc:SetHealAbsorbClampMode(Enum.UnitHealAbsorbClampMode.CurrentHealth)
	calc:SetHealAbsorbMode(Enum.UnitHealAbsorbMode.Total)
	return calc
end

---@param mode 'overlay'|'extend'
---@return table|nil calculator
function Prediction:Get(mode)
	if self.failed or not P.Caps:Get('healPrediction') then
		return nil
	end
	local calc = self.calculators[mode]
	if not calc then
		local ok, made = pcall(MakeCalculator, mode)
		if not ok or not made then
			self:Fail(ok and 'the game gave no calculator' or tostring(made))
			return nil
		end
		calc = made
		self.calculators[mode] = calc
	end
	return calc
end

---Every value one update needs, straight from a filled calculator.
local function ReadCalculatorSecret(calc)
	local maxSecret = calc:GetMaximumHealth()
	local healthSecret = calc:GetCurrentHealth()
	local absorbSecret, clampedSecret = calc:GetDamageAbsorbs()
	local healAbsorbSecret = calc:GetHealAbsorbs()
	return maxSecret, healthSecret, absorbSecret, clampedSecret, healAbsorbSecret
end

-- Errors in a row, before the first good fill, that turn the calculator off for the session. One
-- bad unit token (a restricted PvP unit) must not decide it alone.
Prediction.MAX_ERRORS = 3

---The S0 check on a filled calculator: every getter answers, and where values are plain the
---calculator agrees with the unit. Returns true (trust it), false (it gave wrong values) or nil
---(the values are hidden right now, so use them and check again next time).
---@param calc table
---@param src Plates.Source
---@param mode 'overlay'|'extend'
---@return boolean|nil
function Prediction.Check(calc, src, mode)
	local maxSecret, healthSecret = ReadCalculatorSecret(calc)
	if P.Caps:Get('secrets') then
		return true
	end
	local maxValue, maxReadable = Secret.Plain(maxSecret)
	local health, healthReadable = Secret.Plain(healthSecret)
	local unitMax, unitMaxReadable = Secret.Plain(src:HealthMaxSecret())
	local unitHealth, unitHealthReadable = src:HealthPlain()
	if not (maxReadable and healthReadable and unitMaxReadable and unitHealthReadable) then
		return nil
	end
	if type(maxValue) ~= 'number' or type(health) ~= 'number' or type(unitMax) ~= 'number' or type(unitHealth) ~= 'number' then
		return false
	end
	if math.abs(health - unitHealth) > 0.5 then
		return false
	end
	if mode == 'extend' then
		return maxValue + 0.5 >= unitMax
	end
	return math.abs(maxValue - unitMax) <= 0.5
end

---Fill the calculator for a source. Returns it when it holds this unit's values, nil when the
---caller must read the unit directly (samples, a failed fill, or the check failed). Every fill runs
---in pcall; until the first good fill (the S0 check) the reads do too.
---@param src Plates.Source
---@param mode 'overlay'|'extend'
---@return table|nil calculator
function Prediction:Fill(src, mode)
	local calc = self:Get(mode)
	if not calc then
		return nil
	end
	local ok, filled = pcall(src.FillHealPrediction, src, calc)
	if ok and filled and not self.verified then
		local okRead, agrees = pcall(self.Check, calc, src, mode)
		if not okRead then
			ok, filled = false, agrees
		elseif agrees == false then
			ok, filled = false, 'its health did not match the unit'
		elseif agrees == true then
			self.verified = true
			self.errors = 0
		end
	end
	if not ok then
		if not self.verified then
			self.errors = (self.errors or 0) + 1
			if self.errors >= self.MAX_ERRORS then
				self:Fail(filled)
			end
		elseif not self.warned then
			self.warned = true
			P.log.warning('Heal prediction failed for one plate; it read the unit directly: ' .. tostring(filled))
		end
		return nil
	end
	if not filled then
		return nil
	end
	return calc
end

----------------------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------------------

P.Caps:AddProbe('clipChildren', function()
	return CreateFrame ~= nil and CreateFrame('Frame').SetClipsChildren ~= nil
end, 'Frames that clip their children (shield bars, lost health)')

P.Caps:AddProbe('healthCurves', function()
	return P.Caps:Get('colorCurves')
end, 'Low health and execute overlays from hidden health (S5)')

---Curves only where health can be hidden: clients without secrets always read it plainly.
local function UseCurves()
	return P.Caps:Get('secrets') and P.Caps:Get('healthCurves')
end

---Health as a 0-1 fraction when the game lets us read it, else nil.
---@param src Plates.Source
---@return number|nil
local function PlainFraction(src)
	local health, healthReadable = src:HealthPlain()
	local maxValue, maxReadable = Secret.Plain(src:HealthMaxSecret())
	if not (healthReadable and maxReadable) or type(health) ~= 'number' or type(maxValue) ~= 'number' or maxValue <= 0 then
		return nil
	end
	return health / maxValue
end

local lowCurves = setmetatable({}, { __mode = 'k' })

local function LowCurve(row, threshold)
	local curve = lowCurves[row]
	if curve == nil then
		curve = P.Colors:BuildStepCurve(row.color, threshold) or false
		lowCurves[row] = curve
	end
	return curve or nil
end

---Tint an overlay with a color that may be hidden: the boolean form is the documented sink that
---takes a whole color object, so its channels are never read here.
local function TintFromColorSecret(texture, colorSecret)
	Secret.SetVertexColorFromBoolean(texture, true, colorSecret, colorSecret)
end

-- Which step of DrawCurveSecret ran last, so a failure in the read (one bad unit token) is told
-- apart from the game refusing the color (the S5 answer)
local curveStage

---@return boolean drew
local function DrawCurveSecret(texture, src, curve)
	curveStage = 'read'
	local colorSecret = src:HealthPercentSecret(curve)
	if type(colorSecret) == 'nil' then
		return false
	end
	curveStage = 'tint'
	TintFromColorSecret(texture, colorSecret)
	return true
end

---Show a step overlay: `color` at or below `threshold` (a 0-1 health fraction), clear above it.
local function DrawStep(texture, src, color, threshold, curve)
	if curve and UseCurves() then
		local ok, drew = pcall(DrawCurveSecret, texture, src, curve)
		if ok and drew then
			return
		end
		if not ok and curveStage == 'tint' then
			P.Caps:Record('healthCurves', false)
			P.log.warning('Low health and execute overlays use plain health from now on: ' .. tostring(drew))
		end
	end
	local fraction = PlainFraction(src)
	local alpha = 0
	if fraction and fraction < threshold then
		alpha = color[4] or 1
	end
	texture:SetVertexColor(color[1], color[2], color[3], alpha)
end

---Frame levels of the overlays, relative to the bar (see the header). Set on every layout and
---full update, so they follow the level the plate gives the bar.
local function ApplyLevels(widget)
	local level = Secret.Plain(widget.bar:GetFrameLevel())
	if type(level) ~= 'number' then
		return
	end
	widget.bar.border:SetFrameLevel(level + 1)
	widget.chunkClip:SetFrameLevel(level + 1)
	widget.over:SetFrameLevel(level + 1)
	widget.chunk:SetFrameLevel(level + 2)
	widget.absorbBar:SetFrameLevel(level + 2)
	widget.healAbsorbBar:SetFrameLevel(level + 2)
end

---Width-dependent pieces: shield bars as wide as the health bar, the execute mark's place.
---@param widget table
---@param measured any The overlay clip's width (from GetWidth or OnSizeChanged), maybe hidden
local function Resize(widget, measured)
	local spec = widget.spec
	if not spec then
		return
	end
	local width = Secret.Plain(measured)
	if type(width) ~= 'number' or width <= 0 then
		width = BarLib.LayoutWidth(spec, widget.plate, widget.layoutWidth or 1)
	end
	widget.width = width
	widget.absorbBar:SetWidth(width)
	widget.healAbsorbBar:SetWidth(width)
	local mark, over = widget.mark, widget.over
	if widget.execute then
		local markWidth = MARK_PIXELS * (widget.pixel or 1)
		local x = widget.execute * width - markWidth / 2
		mark:ClearAllPoints()
		if spec.reverse then
			mark:SetPoint('TOPRIGHT', over, 'TOPRIGHT', -x, 0)
			mark:SetPoint('BOTTOMRIGHT', over, 'BOTTOMRIGHT', -x, 0)
		else
			mark:SetPoint('TOPLEFT', over, 'TOPLEFT', x, 0)
			mark:SetPoint('BOTTOMLEFT', over, 'BOTTOMLEFT', x, 0)
		end
		mark:SetWidth(markWidth)
	end
end

local function Program(spec, env)
	local piece = spec.colors or (not spec.color and 'health') or nil
	if not piece then
		return nil
	end
	return P.Colors:Program(piece, env.ctx)
end

---Keep the old health on the chunk and fade it (see the header). Never compares values.
local function ChunkSecret(widget, event, maxSecret, healthSecret, full)
	local chunk = widget.chunk
	chunk:SetMinMaxValues(0, maxSecret)
	if full or not widget.chunkReady then
		P.Scheduler:StopEase(widget.chunkEase)
		widget.chunkFading = false
		chunk:SetAlpha(0)
		chunk:SetValue(healthSecret)
		widget.lastHealthSecret = healthSecret
		widget.chunkReady = true
		return
	end
	if not LOSS_EVENTS[event] then
		return
	end
	if not widget.chunkFading then
		chunk:SetValue(widget.lastHealthSecret)
	end
	widget.lastHealthSecret = healthSecret
	widget.chunkFading = true
	chunk:SetAlpha(1)
	P.Scheduler:Ease(widget.chunkEase, 1 + CHUNK_HOLD, 0, CHUNK_TIME, widget.chunkApply, widget.chunkDone)
end

local function UpdateValues(widget, src, event, full)
	local spec, bar = widget.spec, widget.bar
	local mode = spec.absorbMode == 'extend' and 'extend' or 'overlay'
	local calc = (spec.absorb or spec.healAbsorb) and Prediction:Fill(src, mode) or nil
	local maxSecret, healthSecret, absorbSecret, clampedSecret, healAbsorbSecret
	if calc then
		maxSecret, healthSecret, absorbSecret, clampedSecret, healAbsorbSecret = ReadCalculatorSecret(calc)
	else
		maxSecret = src:HealthMaxSecret()
		healthSecret = src:HealthSecret()
		if spec.absorb then
			absorbSecret = src:AbsorbSecret()
		end
		if spec.healAbsorb then
			healAbsorbSecret = src:HealAbsorbSecret()
		end
	end
	if type(maxSecret) == 'nil' then
		maxSecret = 1
	end
	if type(healthSecret) == 'nil' then
		healthSecret = 0
	end
	if type(absorbSecret) == 'nil' then
		absorbSecret = 0
	end
	if type(healAbsorbSecret) == 'nil' then
		healAbsorbSecret = 0
	end

	-- Without the calculator, the shield glow and room for the whole shield need plain values
	local glow
	if not calc and spec.absorb then
		local maxValue, maxReadable = Secret.Plain(maxSecret)
		local absorb, absorbReadable = Secret.Plain(absorbSecret)
		local health, healthReadable = Secret.Plain(healthSecret)
		local readable = maxReadable and absorbReadable and type(maxValue) == 'number' and type(absorb) == 'number'
		glow = false
		if readable and mode == 'extend' then
			maxSecret = maxValue + absorb
		elseif readable and healthReadable and type(health) == 'number' then
			glow = absorb > maxValue - health
			if not widget.clips then
				-- Nothing clips the shield at the bar's end, so clamp it here
				absorbSecret = math.max(0, math.min(absorb, maxValue - health))
			end
		end
	end

	local interpolation = BarLib.Interpolation(spec, full)
	bar:SetMinMaxValues(0, maxSecret)
	BarLib.SetValueSecret(bar, healthSecret, interpolation)
	if spec.absorb then
		local absorbBar = widget.absorbBar
		absorbBar:SetMinMaxValues(0, maxSecret)
		BarLib.SetValueSecret(absorbBar, absorbSecret, interpolation)
		if glow ~= nil then
			widget.glow:SetAlpha(glow and 1 or 0)
		else
			Secret.SetAlphaFromBoolean(widget.glow, clampedSecret, 1, 0)
		end
	end
	if spec.healAbsorb then
		local healAbsorbBar = widget.healAbsorbBar
		healAbsorbBar:SetMinMaxValues(0, maxSecret)
		BarLib.SetValueSecret(healAbsorbBar, healAbsorbSecret, interpolation)
	end
	if widget.lostHealth then
		ChunkSecret(widget, event, maxSecret, healthSecret, full)
	end
end

local function UpdateOverlays(widget, src, program, ctx)
	local row = program and program.overlay
	if row and not P.Conditions:WhenApplies(row.when, ctx or P.Context) then
		row = nil
	end
	local low = widget.low
	if row and row.color then
		local threshold = row.threshold or (row.kind and row.kind.threshold) or 0.35
		low:Show()
		DrawStep(low, src, row.color, threshold, LowCurve(row, threshold))
	else
		low:Hide()
	end
	if widget.execute then
		DrawStep(widget.band, src, widget.bandColor, widget.execute, widget.executeCurve)
	end
end

local function ApplyColors(widget, program, env)
	local spec, bar = widget.spec, widget.bar
	if program then
		P.Colors:Apply(program, env, widget.colorTarget, 'SetStatusBarColor')
	end
	if spec.borderColors and bar.border.kind then
		P.Colors:Apply(P.Colors:Program(spec.borderColors, env.ctx), env, BarLib.BorderTarget(bar.border), 'SetVertexColor')
	end
end

local function Anchor(region, point, relative, relPoint)
	region:SetPoint(point, relative, relPoint, 0, 0)
end

---Shield, heal-absorb and lost-health pieces hang from the live fill edge; a reversed bar fills
---from the right, so every edge flips.
local function AnchorToFill(widget, reverse)
	local bar, fill = widget.bar, widget.bar:GetStatusBarTexture()
	widget.fill = fill
	local near, far = 'RIGHT', 'LEFT'
	if reverse then
		near, far = 'LEFT', 'RIGHT'
	end

	local absorbBar = widget.absorbBar
	absorbBar:ClearAllPoints()
	Anchor(absorbBar, 'TOP' .. far, fill, 'TOP' .. near)
	Anchor(absorbBar, 'BOTTOM' .. far, fill, 'BOTTOM' .. near)
	absorbBar:SetReverseFill(reverse)

	local healAbsorbBar = widget.healAbsorbBar
	healAbsorbBar:ClearAllPoints()
	Anchor(healAbsorbBar, 'TOP' .. near, fill, 'TOP' .. near)
	Anchor(healAbsorbBar, 'BOTTOM' .. near, fill, 'BOTTOM' .. near)
	healAbsorbBar:SetReverseFill(not reverse)

	local chunkClip = widget.chunkClip
	chunkClip:ClearAllPoints()
	Anchor(chunkClip, 'TOP' .. far, fill, 'TOP' .. near)
	Anchor(chunkClip, 'BOTTOM' .. far, fill, 'BOTTOM' .. near)
	Anchor(chunkClip, 'TOP' .. near, bar, 'TOP' .. near)
	Anchor(chunkClip, 'BOTTOM' .. near, bar, 'BOTTOM' .. near)
	widget.chunk:SetReverseFill(reverse)

	local glow, over = widget.glow, widget.over
	glow:ClearAllPoints()
	Anchor(glow, 'TOP' .. near, over, 'TOP' .. near)
	Anchor(glow, 'BOTTOM' .. near, over, 'BOTTOM' .. near)
end

local eventLists = setmetatable({}, { __mode = 'k' }) -- resolved spec -> its event list

local function EventsFor(spec)
	local cached = eventLists[spec]
	if cached then
		return cached
	end
	local events = { 'UNIT_HEALTH', 'UNIT_MAXHEALTH' }
	if spec.absorb then
		events[#events + 1] = 'UNIT_ABSORB_AMOUNT_CHANGED'
	end
	if spec.healAbsorb then
		events[#events + 1] = 'UNIT_HEAL_ABSORB_AMOUNT_CHANGED'
	end
	eventLists[spec] = events
	return events
end

----------------------------------------------------------------------------------------------------
-- The part
----------------------------------------------------------------------------------------------------

local Health = {
	id = 'health',
	kinds = { 'bar' },
	priority = 10,
	prediction = Prediction,
}

function Health.match(spec)
	return spec.source == 'health' or spec.source == nil
end

Health.events = EventsFor

function Health.Create(plate)
	local bar = BarLib.Create(plate.art)
	local widget = { frame = bar, bar = bar }

	widget.low = bar:CreateTexture(nil, 'ARTWORK', nil, 2)
	widget.band = bar:CreateTexture(nil, 'ARTWORK', nil, 3)

	local chunkClip = CreateFrame('Frame', nil, bar)
	local chunk = CreateFrame('StatusBar', nil, chunkClip)
	chunk:SetAllPoints(bar)
	chunk:SetMinMaxValues(0, 1)
	chunk:SetValue(0)
	chunk:SetAlpha(0)
	widget.chunkClip, widget.chunk = chunkClip, chunk
	widget.chunkEase = tostring(widget) .. 'chunk'
	-- Made once: every hit that starts the fade reuses them
	widget.chunkApply = function(value)
		chunk:SetAlpha(math.min(value, 1))
	end
	widget.chunkDone = function()
		widget.chunkFading = false
	end

	local over = CreateFrame('Frame', nil, bar)
	over:SetAllPoints(bar)
	local absorbBar = CreateFrame('StatusBar', nil, over)
	absorbBar:SetMinMaxValues(0, 1)
	absorbBar:SetValue(0)
	local healAbsorbBar = CreateFrame('StatusBar', nil, over)
	healAbsorbBar:SetMinMaxValues(0, 1)
	healAbsorbBar:SetValue(0)
	widget.over, widget.absorbBar, widget.healAbsorbBar = over, absorbBar, healAbsorbBar
	widget.glow = over:CreateTexture(nil, 'OVERLAY')
	widget.glow:SetTexture(BarLib.WHITE)
	widget.glow:SetAlpha(0)
	widget.mark = over:CreateTexture(nil, 'OVERLAY', nil, 1)
	widget.mark:SetTexture(BarLib.WHITE)

	-- Clip to the bar (shields that run past its end) and to the part right of the fill (chunk)
	if over.SetClipsChildren and P.Caps:Get('clipChildren') then
		over:SetClipsChildren(true)
		chunkClip:SetClipsChildren(true)
		widget.clips = true
	end
	over:SetScript('OnSizeChanged', function(_, width)
		Resize(widget, width)
	end)

	-- Colors from the list go to the bar and to the chunk, which shows the same fill fading out
	widget.colorTarget = {
		SetStatusBarColor = function(_, r, g, b, a)
			bar:SetStatusBarColor(r, g, b, a)
			chunk:SetStatusBarColor(r, g, b, a)
		end,
	}
	widget.textures = { bar.bg, widget.low, widget.band, widget.mark, widget.glow }
	return widget
end

function Health.Layout(widget, spec, ctx)
	local bar = widget.bar
	BarLib.Place(bar, spec, ctx)
	BarLib.Style(bar, spec, ctx)
	local texture = ctx:Texture(spec.texture) or BarLib.WHITE
	local reverse = spec.reverse and true or false
	widget.pixel = BarLib.Pixel(ctx)
	widget.layoutWidth = (spec.fill ~= 'plate' and spec.width) or ctx.width
	widget.chunkReady = false

	local textures = widget.textures
	for i = #textures, 6, -1 do
		textures[i] = nil
	end
	for _, edge in ipairs(bar.border.edges or {}) do
		textures[#textures + 1] = edge
	end

	bar:GetStatusBarTexture():SetDrawLayer('ARTWORK', 1)
	AnchorToFill(widget, reverse)

	if not spec.colors and spec.color then
		widget.colorTarget:SetStatusBarColor(ctx:Color(spec.color))
	end

	-- Low health (the color list's curve row) and the execute band recolor the fill itself
	local fill = widget.fill
	for _, overlay in ipairs({ widget.low, widget.band }) do
		overlay:SetTexture(texture)
		overlay:ClearAllPoints()
		overlay:SetAllPoints(fill)
		overlay:SetVertexColor(1, 1, 1, 0)
	end

	-- Lost-health chunk: needs the clip so it only shows right of the live fill
	widget.lostHealth = spec.lostHealth == true and widget.clips == true
	widget.chunk:SetStatusBarTexture(texture)
	widget.chunk:SetAlpha(0)
	widget.chunkClip:SetShown(widget.lostHealth)

	-- Shields
	widget.absorbBar:SetStatusBarTexture(ctx:Texture(spec.absorbTexture) or texture)
	widget.absorbBar:SetStatusBarColor(ctx:Color(spec.absorbColor or DEFAULT_ABSORB))
	widget.absorbBar:SetShown(spec.absorb == true)
	widget.healAbsorbBar:SetStatusBarTexture(ctx:Texture(spec.absorbTexture) or texture)
	widget.healAbsorbBar:SetStatusBarColor(ctx:Color(spec.healAbsorbColor or DEFAULT_HEAL_ABSORB))
	widget.healAbsorbBar:SetShown(spec.healAbsorb == true)
	local r, g, b = ctx:Color(spec.absorbColor or DEFAULT_ABSORB)
	widget.glow:SetVertexColor(r, g, b, 1)
	if widget.glow.SetBlendMode then
		widget.glow:SetBlendMode('ADD')
	end
	widget.glow:SetWidth(GLOW_PIXELS * widget.pixel)
	widget.glow:SetAlpha(0)
	widget.glow:SetShown(spec.absorb == true)

	-- Execute band and mark
	local execute = type(spec.execute) == 'number' and spec.execute > 0 and spec.execute or nil
	widget.execute = execute
	if execute then
		local er, eg, eb, ea = ctx:Color(spec.executeColor or DEFAULT_EXECUTE)
		widget.bandColor = { er, eg, eb, ea * BAND_ALPHA }
		local key = table.concat(widget.bandColor, ',') .. '@' .. execute
		if widget.executeKey ~= key then
			widget.executeKey = key
			widget.executeCurve = P.Colors:BuildStepCurve(widget.bandColor, execute)
		end
		widget.mark:SetVertexColor(er, eg, eb, ea)
	end
	widget.band:SetShown(execute ~= nil)
	widget.mark:SetShown(execute ~= nil)

	Resize(widget, widget.over:GetWidth())
	ApplyLevels(widget)
end

---Place the border, glow and mark again when the plate's pixel changed since the layout.
local function Resnap(widget)
	local pixel = BarLib.RegionPixel(widget.plate.art)
	if widget.pixel and math.abs(widget.pixel - pixel) < 1e-6 then
		return
	end
	widget.pixel = pixel
	BarLib.Resnap(widget.bar.border, pixel)
	widget.glow:SetWidth(GLOW_PIXELS * pixel)
	Resize(widget, widget.width)
end

function Health.Update(widget, src, event)
	local full = event == 'FULL'
	local health = HEALTH_EVENTS[event]
	if full then
		ApplyLevels(widget)
		Resnap(widget)
	end
	if full or health then
		UpdateValues(widget, src, event, full)
	end
	local env = widget.plate.env
	local program = Program(widget.spec, env)
	if full or health or event == 'COLORS' or event == 'CONTEXT_CHANGED' then
		UpdateOverlays(widget, src, program, env.ctx)
	end
	if full or not health or (program and program.events[event]) then
		ApplyColors(widget, program, env)
	end
end

function Health.Reset(widget)
	P.Scheduler:StopEase(widget.chunkEase)
	widget.chunkFading = false
	widget.chunkReady = false
	widget.lastHealthSecret = nil
	widget.chunk:SetAlpha(0)
	widget.glow:SetAlpha(0)
	widget.low:SetVertexColor(1, 1, 1, 0)
	widget.band:SetVertexColor(1, 1, 1, 0)
end

---Plain reasons, for the options, when part of the health bar cannot work on this client right
---now. Empty when everything works.
---@return string[]
function Health.Limits()
	local out = {}
	local secrets = P.Caps:Get('secrets')
	-- Without secrets the plain math does everything the calculator did
	if secrets and (Prediction.failed or not P.Caps:Get('healPrediction')) then
		out[#out + 1] = L['The glow for big shields and room for the whole shield only show when the game lets addons see shield amounts.']
	end
	if secrets and not P.Caps:Get('healthCurves') then
		out[#out + 1] = L['Low health and execute colors only show when the game lets addons see health.']
	end
	if not P.Caps:Get('clipChildren') then
		out[#out + 1] = L['The lost health piece needs a newer version of WoW.']
	end
	return out
end

P.Parts:Register(Health)
