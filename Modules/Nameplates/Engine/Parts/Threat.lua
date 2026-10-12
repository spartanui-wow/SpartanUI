local _, ns = ...
local P = ns.Plates

-- Threat glow (kind 'glow', source 'threat') for roles whose threat shows as a glow (healers by
-- default, 3.1). Owner: Phase 2.
--
-- Shown only where Roles.ThreatOn(role, profile.threat.show).glow is true and the threat "When"
-- clause applies (Conditions.WHEN). Color: the threat row of the 'border' piece is reused, or the
-- palette from P.Roles.Palette for the state from P.Roles.ThreatState(role, status, inGroup) with
-- src:ThreatStatusPlain(). When threat is hidden by the game (readable == false) the glow hides
-- (S2 fallback). Events: UNIT_THREAT_LIST_UPDATE, UNIT_THREAT_SITUATION_UPDATE; messages
-- CONTEXT_CHANGED and TANKS_CHANGED.

P.Parts:Register({
	id = 'threat',
	kinds = { 'glow' },
	priority = 10,
	match = function(spec)
		return spec.source == 'threat'
	end,
	events = { 'UNIT_THREAT_LIST_UPDATE', 'UNIT_THREAT_SITUATION_UPDATE' },
	messages = { 'CONTEXT_CHANGED', 'TANKS_CHANGED' },
	reasons = { colors = true },
	Create = function(plate)
		local holder = CreateFrame('Frame', nil, plate.art)
		holder:Hide()
		return { frame = holder }
	end,
	Layout = function(widget, spec, ctx)
		local size = spec.size or 4
		widget.frame:ClearAllPoints()
		widget.frame:SetPoint('TOPLEFT', ctx.plate.art, 'TOPLEFT', -size, size)
		widget.frame:SetPoint('BOTTOMRIGHT', ctx.plate.art, 'BOTTOMRIGHT', size, -size)
	end,
	Update = function() end,
	Reset = function() end,
})
