local _, ns = ...
local P = ns.Plates
local Secret = P.Secret

-- Bar: shared status bar helpers (P.BarLib, used by Health, Cast and ClassPower) and the 'bar'
-- kind for every source except health (power bars).
--
-- Spec fields (Core/Styles/Schema.lua PART_FIELDS.bar): source, fill ('plate' = SetAllPoints on
-- plate.art), width, height, texture, border { kind, size, color }, bg, colors, borderColors,
-- color, interpolate, reverse (health adds absorb, healAbsorb, absorbMode, absorbColor,
-- absorbTexture, healAbsorbColor, lostHealth, execute, executeColor: see Health.lua).
--
-- BarLib contract (stable; other parts call it):
--   BarLib.WHITE                         plain white file for fills, backgrounds and edges
--   BarLib.Create(parent) -> bar         StatusBar with bar.bg (BACKGROUND texture) and
--                                        bar.border (a holder frame laid over the bar)
--   BarLib.Style(bar, spec, ctx)         fill texture, background, border, reverse fill
--   BarLib.StyleBorder(holder, border, ctx)  crisp edges in physical pixels (see below)
--   BarLib.BorderTarget(holder) -> obj   pass to P.Colors:Apply(program, env, obj, 'SetVertexColor')
--                                        to color every edge of a border from one color list
--   BarLib.Place(frame, spec, ctx)       size and anchor (fill = 'plate' covers plate.art)
--   BarLib.LayoutWidth(spec, plate, w)   the width a bar is drawn at, from the layout
--   BarLib.Pixel(ctx) -> number          one physical pixel in the plate's units, never secret
--   BarLib.RegionPixel(region) -> number the same for any region (no layout context needed)
--   BarLib.Resnap(holder, pixel) -> bool re-place a border's edges for a new pixel size (a base
--                                        plate reused for a unit the game draws at another
--                                        scale); true when something moved
--   BarLib.Interpolation(spec, instant)  Enum.StatusBarInterpolation value or nil (Caps)
--   BarLib.SetValueSecret(bar, valueSecret, interpolation)  SetValue with or without easing
-- Rules:
--   * Borders are four edge textures drawn outside the bar, each a whole number of physical
--     pixels thick (ctx:Pixel()). The core ships no border art yet, and a sliced solid file
--     cannot leave the middle empty; four flat edges stay crisp and cost four textures, not nine.
--   * Values reach a bar only through sinks: SetMinMaxValues, SetValue(value, interpolation),
--     SetStatusBarColor (or P.Colors:Apply with method 'SetStatusBarColor').
--   * Power bars read src:PowerSecret() / src:PowerMaxSecret() for the unit's current power type;
--     events UNIT_POWER_UPDATE, UNIT_MAXPOWER, UNIT_DISPLAYPOWER.
--   * Frame levels: a bar part may use its own level and up to three above it for overlays
--     (P.LayoutContext.PART_LEVELS), so a text part laid over the bar always draws on top.

---@class Plates.BarLib
local BarLib = {}
P.BarLib = BarLib

---Plain white texture for fills and backgrounds when a style names no texture.
BarLib.WHITE = 'Interface\\Buttons\\WHITE8X8'

BarLib.BORDER_KINDS = { pixel = true, thick = true, shadow = true, beveled = true }

local EDGES = { 'top', 'bottom', 'left', 'right' }

P.Caps:AddProbe('barInterpolation', function()
	return Enum ~= nil and Enum.StatusBarInterpolation ~= nil and Enum.StatusBarInterpolation.ExponentialEaseOut ~= nil
end, 'Status bars can ease to a new value')

---A status bar with a background texture and a border holder. Frames only.
---@param parent table
---@return table bar StatusBar with .bg (Texture) and .border (Frame)
function BarLib.Create(parent)
	local bar = CreateFrame('StatusBar', nil, parent)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	bar:SetStatusBarTexture(BarLib.WHITE)
	bar.bg = bar:CreateTexture(nil, 'BACKGROUND')
	bar.bg:SetAllPoints(bar)
	bar.bg:SetTexture(BarLib.WHITE)
	bar.border = CreateFrame('Frame', nil, bar)
	bar.border:SetAllPoints(bar)
	return bar
end

local function PixelFromScale(scale)
	local physical = GetPhysicalScreenSize and select(2, GetPhysicalScreenSize()) or 768
	if type(scale) ~= 'number' or scale <= 0 or not physical or physical <= 0 then
		return 1
	end
	return 768 / physical / scale
end

local function UIParentPixel()
	local scale = UIParent and UIParent.GetEffectiveScale and Secret.Plain(UIParent:GetEffectiveScale()) or 1
	return PixelFromScale(scale)
end

local function Usable(pixel)
	return type(pixel) == 'number' and Secret.CanAccess(pixel) and pixel > 0 and pixel < 64
end

---One physical pixel in the plate's units. A plate inside the game's nameplate tree could report
---its scale as a hidden value; then the UI parent's scale stands in.
---@param ctx Plates.LayoutContext
---@return number
function BarLib.Pixel(ctx)
	local ok, pixel = pcall(ctx.Pixel, ctx)
	if ok and Usable(pixel) then
		return pixel
	end
	return UIParentPixel()
end

---One physical pixel in a region's units, read from its effective scale (hidden scales fall back
---to the UI parent's, like BarLib.Pixel).
---@param region table
---@return number
function BarLib.RegionPixel(region)
	if not (region and region.GetEffectiveScale) then
		return UIParentPixel()
	end
	local ok, scale = pcall(region.GetEffectiveScale, region)
	if ok and Secret.CanAccess(scale) then
		local pixel = PixelFromScale(scale)
		if Usable(pixel) then
			return pixel
		end
	end
	return UIParentPixel()
end

---Interpolation for SetValue: nil (instant) unless the style wants easing and the client has it.
---@param spec table
---@param instant? boolean First fill after a bind or a layout: never ease from the last unit
---@return integer|nil
function BarLib.Interpolation(spec, instant)
	if instant or spec.interpolate == false or not P.Caps:Get('barInterpolation') then
		return nil
	end
	return Enum.StatusBarInterpolation.ExponentialEaseOut
end

---SetValue with or without easing. The game counts an explicit nil as an argument, so the
---interpolation is only passed when there is one.
---@param bar table
---@param valueSecret any number, possibly secret
---@param interpolation? integer
function BarLib.SetValueSecret(bar, valueSecret, interpolation)
	if interpolation then
		bar:SetValue(valueSecret, interpolation)
	else
		bar:SetValue(valueSecret)
	end
end

---Apply texture, background and border from a resolved spec.
---@param bar table
---@param spec table
---@param ctx Plates.LayoutContext
function BarLib.Style(bar, spec, ctx)
	local texture = ctx:Texture(spec.texture) or BarLib.WHITE
	bar:SetStatusBarTexture(texture)
	bar.bg:SetTexture(BarLib.WHITE)
	bar.bg:SetVertexColor(ctx:Color(spec.bg or { 0, 0, 0, 0 }))
	BarLib.StyleBorder(bar.border, spec.border, ctx)
	if bar.SetReverseFill then
		bar:SetReverseFill(spec.reverse and true or false)
	end
end

local function Edges(holder)
	local edges = holder.edges
	if not edges then
		edges = {}
		for _, side in ipairs(EDGES) do
			local edge = holder:CreateTexture(nil, 'BORDER')
			edge:SetTexture(BarLib.WHITE)
			edges[side] = edge
			edges[#edges + 1] = edge
		end
		holder.edges = edges
	end
	return edges
end

---Lay the four edges outside the holder's rect, each `thick` units thick.
local function PlaceEdges(holder, edges, thick)
	local top, bottom, left, right = edges.top, edges.bottom, edges.left, edges.right
	top:ClearAllPoints()
	top:SetPoint('BOTTOMLEFT', holder, 'TOPLEFT', -thick, 0)
	top:SetPoint('BOTTOMRIGHT', holder, 'TOPRIGHT', thick, 0)
	top:SetHeight(thick)
	bottom:ClearAllPoints()
	bottom:SetPoint('TOPLEFT', holder, 'BOTTOMLEFT', -thick, 0)
	bottom:SetPoint('TOPRIGHT', holder, 'BOTTOMRIGHT', thick, 0)
	bottom:SetHeight(thick)
	left:ClearAllPoints()
	left:SetPoint('TOPRIGHT', holder, 'TOPLEFT', 0, 0)
	left:SetPoint('BOTTOMRIGHT', holder, 'BOTTOMLEFT', 0, 0)
	left:SetWidth(thick)
	right:ClearAllPoints()
	right:SetPoint('TOPLEFT', holder, 'TOPRIGHT', 0, 0)
	right:SetPoint('BOTTOMLEFT', holder, 'BOTTOMRIGHT', 0, 0)
	right:SetWidth(thick)
end

---Fade an edge from the border color next to the bar to clear on the outside (shadow border).
---minColor is the bottom (VERTICAL) or left (HORIZONTAL) end.
---@return boolean done
local function Gradient(edge, orientation, inner, outer, innerIsMin)
	if not (edge.SetGradient and CreateColor) then
		return false
	end
	local inside = CreateColor(inner[1], inner[2], inner[3], inner[4])
	local outside = CreateColor(outer[1], outer[2], outer[3], outer[4])
	if innerIsMin then
		return (pcall(edge.SetGradient, edge, orientation, inside, outside))
	end
	return (pcall(edge.SetGradient, edge, orientation, outside, inside))
end

local function Mix(value, toward, amount)
	return value + (toward - value) * amount
end

---Draw (or hide) the border. Kinds: pixel (size physical pixels), thick (size + 1), shadow (a
---soft edge size + 2 wide that fades outward) and beveled (light top and left, dark bottom and
---right). Size 0 or kind 'none' hides it.
---@param holder table
---@param border table|nil { kind, size, color }
---@param ctx Plates.LayoutContext
function BarLib.StyleBorder(holder, border, ctx)
	local kind = border and border.kind
	local size = border and border.size or 1
	if not BarLib.BORDER_KINDS[kind] or size <= 0 then
		holder:Hide()
		holder.kind = nil
		return
	end
	holder:Show()
	holder.kind = kind
	local edges = Edges(holder)
	local pixels = size
	if kind == 'thick' then
		pixels = size + 1
	elseif kind == 'shadow' then
		pixels = size + 2
	end
	-- Whole physical pixels: n times one pixel, so 1 px stays 1 px at any UI scale
	local pixel = BarLib.Pixel(ctx)
	holder.pixels, holder.pixel = pixels, pixel
	PlaceEdges(holder, edges, pixels * pixel)
	local r, g, b, a = ctx:Color(border.color)
	for i = 1, #edges do
		-- One color for all corners, which also clears a gradient left by an earlier shadow border
		edges[i]:SetVertexColor(r, g, b, a)
	end
	if kind == 'shadow' then
		local inner, outer = { r, g, b, a }, { r, g, b, 0 }
		local done = Gradient(edges.top, 'VERTICAL', inner, outer, true)
		done = Gradient(edges.bottom, 'VERTICAL', inner, outer, false) and done
		done = Gradient(edges.left, 'HORIZONTAL', inner, outer, false) and done
		done = Gradient(edges.right, 'HORIZONTAL', inner, outer, true) and done
		if not done then
			for i = 1, #edges do
				edges[i]:SetVertexColor(r, g, b, a * 0.5)
			end
		end
	elseif kind == 'beveled' then
		edges.top:SetVertexColor(Mix(r, 1, 0.45), Mix(g, 1, 0.45), Mix(b, 1, 0.45), a)
		edges.left:SetVertexColor(Mix(r, 1, 0.45), Mix(g, 1, 0.45), Mix(b, 1, 0.45), a)
		edges.bottom:SetVertexColor(Mix(r, 0, 0.5), Mix(g, 0, 0.5), Mix(b, 0, 0.5), a)
		edges.right:SetVertexColor(Mix(r, 0, 0.5), Mix(g, 0, 0.5), Mix(b, 0, 0.5), a)
	end
end

---Keep a border's edges whole physical pixels after the plate's scale changed. Layout measures the
---pixel once; a base plate the game reuses for a unit it draws larger (or smaller) needs the edges
---placed again, or a 1 px line falls between two screen pixels and blurs.
---@param holder table bar.border
---@param pixel number BarLib.Pixel or BarLib.RegionPixel
---@return boolean moved
function BarLib.Resnap(holder, pixel)
	if not (holder.kind and holder.pixels and holder.edges) or type(pixel) ~= 'number' then
		return false
	end
	if holder.pixel and math.abs(holder.pixel - pixel) < 1e-6 then
		return false
	end
	holder.pixel = pixel
	PlaceEdges(holder, holder.edges, holder.pixels * pixel)
	return true
end

local borderTargets = setmetatable({}, { __mode = 'k' })

---A stand-in target for P.Colors:Apply that hands one (possibly secret) color to every edge of
---a border. The color is only passed along to the edges, never read.
---@param holder table bar.border
---@return table target
function BarLib.BorderTarget(holder)
	local target = borderTargets[holder]
	if not target then
		target = {
			SetVertexColor = function(_, r, g, b, a)
				local edges = Edges(holder)
				for i = 1, #edges do
					edges[i]:SetVertexColor(r, g, b, a)
				end
			end,
		}
		borderTargets[holder] = target
	end
	return target
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

---The width a bar part is drawn at, from the layout (never read back from a frame): a bar that
---fills the plate follows the plate's eased width (target growth), others keep their own.
---@param spec table
---@param plate Plates.Plate
---@param fallback number Layout width
---@return number
function BarLib.LayoutWidth(spec, plate, fallback)
	if spec.fill == 'plate' then
		return plate.emW or fallback
	end
	return spec.width or fallback
end

----------------------------------------------------------------------------------------------------
-- The 'bar' kind for power (and any bar source that is not health)
----------------------------------------------------------------------------------------------------

local POWER_EVENTS = { UNIT_POWER_UPDATE = true, UNIT_MAXPOWER = true, UNIT_DISPLAYPOWER = true }
local POWER_COLOR = { 0.2, 0.45, 1, 1 }

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
		local bar = widget.frame
		BarLib.Place(bar, spec, ctx)
		BarLib.Style(bar, spec, ctx)
		for i, edge in ipairs(bar.border.edges or {}) do
			widget.textures[i + 1] = edge
		end
		if not spec.colors then
			bar:SetStatusBarColor(ctx:Color(spec.color or POWER_COLOR))
		end
	end,
	Update = function(widget, src, event)
		local spec, bar = widget.spec, widget.frame
		local full = event == 'FULL' or event == 'COLORS'
		if event == 'FULL' then
			BarLib.Resnap(bar.border, BarLib.RegionPixel(widget.plate.art))
		end
		if full or POWER_EVENTS[event] then
			bar:SetMinMaxValues(0, src:PowerMaxSecret())
			BarLib.SetValueSecret(bar, src:PowerSecret(), BarLib.Interpolation(spec, full))
		end
		if full or not POWER_EVENTS[event] then
			local env = widget.plate.env
			if spec.colors then
				P.Colors:Apply(P.Colors:Program(spec.colors, env.ctx), env, bar, 'SetStatusBarColor')
			end
			if spec.borderColors and bar.border.kind then
				P.Colors:Apply(P.Colors:Program(spec.borderColors, env.ctx), env, BarLib.BorderTarget(bar.border), 'SetVertexColor')
			end
		end
	end,
	Reset = function() end,
})
