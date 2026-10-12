local _, ns = ...
local P = ns.Plates

-- Editable click and stacking areas (kind 'region', Phase 7). Until then the regions come from
-- the style's `regions` block (Merge.Regions) and the Driver sizes the click and stack frames.
-- In the preview, "Show all parts" draws both areas as outlines; real plates draw them too while
-- that toggle is on (3.2), through this part.

P.Parts:Register({
	id = 'region',
	kinds = { 'region' },
	Create = function(plate)
		local holder = CreateFrame('Frame', nil, plate.art)
		holder:Hide()
		return { frame = holder }
	end,
	Layout = function(widget, spec, ctx)
		widget.frame:SetSize(spec.width or ctx.width, spec.height or ctx.height)
		ctx:Anchor(widget.frame, spec.anchor)
	end,
	Update = function() end,
	Reset = function() end,
})
