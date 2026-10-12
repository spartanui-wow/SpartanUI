local _, ns = ...
local P = ns.Plates

-- Bar: shared status bar helpers (used by Health, Cast, ClassPower) and the 'bar' kind for every
-- source except health (power bars). Owner: Phase 2 engine agent.
--
-- Spec fields (Core/Styles/Schema.lua PART_FIELDS.bar): source, fill ('plate' = SetAllPoints on
-- plate.art), width, height, texture, border { kind, size, color }, bg, colors, borderColors,
-- color, interpolate, reverse.
-- Rules:
--   * Borders are crisp 1 px: size in physical pixels (ctx:Pixel()), one texture with
--     SetTextureSliceMargins where the client has it, never nine textures per border.
--   * Values reach the bar only through sinks: SetMinMaxValues, SetValue(value, interpolation),
--     SetStatusBarColor (or P.Colors:Apply with method 'SetStatusBarColor').
--   * Power bars read src:PowerSecret(type) / src:PowerMaxSecret(type); events UNIT_POWER_UPDATE,
--     UNIT_MAXPOWER, UNIT_DISPLAYPOWER.

---@class Plates.BarLib
local BarLib = {}
P.BarLib = BarLib

---Plain white texture for fills and backgrounds when a style names no texture.
BarLib.WHITE = 'Interface\\Buttons\\WHITE8X8'

---A status bar with a background texture and a border holder. Frames only.
---@param parent table
---@return table bar StatusBar with .bg (Texture) and .border (Frame)
function BarLib.Create(parent)
	local bar = CreateFrame('StatusBar', nil, parent)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	bar.bg = bar:CreateTexture(nil, 'BACKGROUND')
	bar.bg:SetAllPoints(bar)
	bar.border = CreateFrame('Frame', nil, bar)
	bar.border:SetAllPoints(bar)
	return bar
end

---Apply texture, background and border from a resolved spec.
---@param bar table
---@param spec table
---@param ctx Plates.LayoutContext
function BarLib.Style(bar, spec, ctx)
	local texture = ctx:Texture(spec.texture) or BarLib.WHITE
	bar:SetStatusBarTexture(texture)
	bar.bg:SetTexture(BarLib.WHITE)
	bar.bg:SetVertexColor(ctx:Color(spec.bg))
	BarLib.StyleBorder(bar.border, spec.border, ctx)
	if spec.reverse ~= nil and bar.SetReverseFill then
		bar:SetReverseFill(spec.reverse)
	end
end

---Draw (or hide) the border. Phase 2 implements pixel, thick, shadow and beveled kinds.
---@param holder table
---@param border table|nil { kind, size, color }
---@param ctx Plates.LayoutContext
function BarLib.StyleBorder(holder, border, ctx)
	if not border or border.kind == 'none' then
		holder:Hide()
		return
	end
	holder:Show()
end

---Size and anchor a bar part: fill = 'plate' covers plate.art, else width/height and anchor.
---@param frame table
---@param spec table
---@param ctx Plates.LayoutContext
function BarLib.Place(frame, spec, ctx)
	frame:ClearAllPoints()
	if spec.fill == 'plate' then
		frame:SetAllPoints(ctx.plate.art)
		return
	end
	frame:SetSize(spec.width or ctx.width, spec.height or ctx.height)
	ctx:Anchor(frame, spec.anchor)
end

P.Parts:Register({
	id = 'bar',
	kinds = { 'bar' },
	match = function(spec)
		return spec.source ~= 'health'
	end,
	events = { 'UNIT_POWER_UPDATE', 'UNIT_MAXPOWER', 'UNIT_DISPLAYPOWER' },
	Create = function(plate)
		local bar = BarLib.Create(plate.art)
		return { frame = bar, bar = nil, statusBar = bar, textures = { bar.bg } }
	end,
	Layout = function(widget, spec, ctx)
		BarLib.Place(widget.frame, spec, ctx)
		BarLib.Style(widget.frame, spec, ctx)
	end,
	Update = function() end,
	Reset = function() end,
})
