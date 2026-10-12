local _, ns = ...
local P = ns.Plates

-- Health bar (kind 'bar', source 'health'), with absorbs and heal absorbs (4). Owner: Phase 2.
--
-- Reads: src:HealthSecret(), src:HealthMaxSecret(), src:FillHealPrediction(calculator) (else
-- src:AbsorbSecret() / src:HealAbsorbSecret()), src:HealthPercentSecret(curve) for curve rows.
-- Sinks: SetMinMaxValues, SetValue(value, Enum.StatusBarInterpolation.*), P.Colors:Apply with
-- 'SetStatusBarColor' for spec.colors and 'SetVertexColor' on the border for spec.borderColors.
-- The low-health row is a curve overlay (program.overlay): a texture over the fill tinted with
-- the color UnitHealthPercent returns for a step ColorCurve (P.Colors:BuildStepCurve).
-- Contract: widget.bar is the health StatusBar (P.API:GetHealthBar, LastTick).
-- The absorb overlay anchors to the fill texture's right edge.

local BarLib = P.BarLib

P.Parts:Register({
	id = 'health',
	kinds = { 'bar' },
	priority = 10,
	match = function(spec)
		return spec.source == 'health' or spec.source == nil
	end,
	events = { 'UNIT_HEALTH', 'UNIT_MAXHEALTH', 'UNIT_ABSORB_AMOUNT_CHANGED', 'UNIT_HEAL_ABSORB_AMOUNT_CHANGED', 'UNIT_HEAL_PREDICTION' },
	Create = function(plate)
		local bar = BarLib.Create(plate.art)
		return { frame = bar, bar = bar, textures = { bar.bg } }
	end,
	Layout = function(widget, spec, ctx)
		BarLib.Place(widget.frame, spec, ctx)
		BarLib.Style(widget.frame, spec, ctx)
	end,
	Update = function(widget, src)
		local bar = widget.bar
		bar:SetMinMaxValues(0, src:HealthMaxSecret())
		bar:SetValue(src:HealthSecret())
		local env = widget.plate.env
		P.Colors:Apply(P.Colors:Program(widget.spec.colors or 'health', env.ctx), env, bar, 'SetStatusBarColor')
	end,
	Reset = function() end,
})
