local _, ns = ...
local P = ns.Plates

-- Class resource on the target plate (kind 'classPower', Phase 5).
--
-- One StatusBar per pip with SetMinMaxValues(i - 1, i); every pip is given the same value from
-- src:PowerSecret(powerType), so a secret value fills the right pips without being read
-- (UnitPower and GetComboPoints are SecretWhenUnitPowerRestricted on Retail and Forever).
-- Only shown on the plate in the 'target' state. Pip shapes come from the art set.

P.Parts:Register({
	id = 'classPower',
	kinds = { 'classPower' },
	events = { 'UNIT_POWER_UPDATE', 'UNIT_MAXPOWER' },
	Create = function(plate)
		local holder = CreateFrame('Frame', nil, plate.art)
		holder:Hide()
		return { frame = holder, pips = {} }
	end,
	Layout = function(widget, spec, ctx)
		widget.frame:SetSize(ctx.width, spec.size or 6)
		ctx:Anchor(widget.frame, spec.anchor)
	end,
	Update = function() end,
	Reset = function() end,
})
