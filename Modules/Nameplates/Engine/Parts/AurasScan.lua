local _, ns = ...
local P = ns.Plates

-- Aura rows by Lua scan (kind 'auras'): the Classic family, and every preview (sample icons).
-- Owner: Phase 3. Never on live plates where secrets exist: the row predicates read aura fields
-- that can be secret there. A client with secrets and no aura containers (a failed probe, or the
-- containers capability forced off) shows no aura rows.
--
-- Live: UNIT_AURA with its updateInfo; reads go through src:AuraByIndexPlain(index, filter),
-- src:AuraInstanceIDsPlain(filter, sortRule, sortDirection) and src:AuraByInstancePlain(id) (all
-- plain on these clients). Where GetUnitAuraInstanceIDs exists, Blizzard sorts and we intersect
-- with our picks. Row predicates come from P.AuraRows.ROWS[row].scan; always/never lists from
-- profile.auras[row] ({ always = { [spellID] = 'mine'|'any' }, never = {...} }), read through
-- P.Store on every rescan. Icons come from our own pool; timers use the duration binding where
-- present and not P.Caps:Quirk('plainCastText'), else plain math.
-- Preview: src.isSample is true; draw src:SampleAuras(spec.row) with cooldown swipes paused, and a
-- small "sample icons" label is drawn by the scene, not here.
-- Never key a table by auraInstanceID on clients with secrets (match keeps this path off there).

P.Parts:Register({
	id = 'aurasScan',
	kinds = { 'auras' },
	match = function(_, plate)
		return plate.isPreview or not P.Caps:Get('secrets')
	end,
	events = { 'UNIT_AURA' },
	reasons = { auras = true },
	Create = function(plate)
		local holder = CreateFrame('Frame', nil, plate.art)
		return { frame = holder, icons = {} }
	end,
	Layout = function(widget, spec, ctx)
		local w, h = P.Styles.Merge.PartSize(spec, ctx.width, ctx.height)
		widget.frame:SetSize(w, h)
		ctx:Anchor(widget.frame, spec.anchor)
	end,
	Configure = function() end,
	Update = function() end,
	Reset = function() end,
})
