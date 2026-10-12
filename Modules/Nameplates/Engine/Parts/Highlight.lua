local _, ns = ...
local P = ns.Plates

-- Highlights (kind 'highlight') and theme art (kind 'art'). Owner: Phase 2 (art set in Phase 4a).
--
-- highlight: art drawn around the plate for a state (spec.state: target, focus, mouseover).
--   Arts: arrows, doubleArrows, brackets, glow, underline, sideBars (5.5). Mouseover and focus reuse
--   the target art with their own tint and alpha. Art keys go through P.Data.ArtAliases and the
--   LSM media types the art set registers; textures draw with SetTextureSliceMargins where sliced.
-- art: static theme decoration (nine-slice plate, emblem); host looks supply paths in tokens/art.
-- The plate shows and hides state-tied parts itself (Plate:SetState); OnState is for animation.

local function Create(plate)
	local holder = CreateFrame('Frame', nil, plate.art)
	local texture = holder:CreateTexture(nil, 'BACKGROUND')
	texture:SetAllPoints(holder)
	return { frame = holder, texture = texture }
end

local function Layout(widget, spec, ctx)
	local pad = spec.pad or 0
	widget.frame:ClearAllPoints()
	widget.frame:SetPoint('TOPLEFT', ctx.plate.art, 'TOPLEFT', -pad, pad)
	widget.frame:SetPoint('BOTTOMRIGHT', ctx.plate.art, 'BOTTOMRIGHT', pad, -pad)
end

P.Parts:Register({
	id = 'highlight',
	kinds = { 'highlight' },
	Create = Create,
	Layout = Layout,
	Update = function() end,
	Reset = function() end,
})

P.Parts:Register({
	id = 'art',
	kinds = { 'art' },
	Create = Create,
	Layout = Layout,
	Update = function() end,
	Reset = function() end,
})
