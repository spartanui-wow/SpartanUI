local _, ns = ...
local P = ns.Plates

-- Highlights (kind 'highlight') and theme art (kind 'art') (5.5, 3.5). Owner: Phase 2; the art set
-- (Phase 4a) paints the pictures.
--
-- highlight: art around the plate for a state (spec.state: target, focus or mouseover; a highlight
--   with no state always shows and draws like a target highlight). Arts: arrows, doubleArrows,
--   brackets, glow, underline, sideBars (Highlight.ARTS).
--   * Pictures: an art key is looked up in LibSharedMedia (type ArtAliases.MEDIA.highlight), then
--     in the art slot's own file (Data/ArtAliases.lua SLOTS.highlight). How a picture draws (a
--     mirrored pair, nine-sliced around the plate, a strip below) comes from its slot.
--   * Stand-ins: until the art set fills a slot, each art is drawn from plain textures and lines
--     (chevrons, brackets, bars, a faded strip; the soft glow comes from P.GlowLib), so every key
--     always draws.
--   * One rule for mouseover and focus (5.5): they reuse the same pictures, with their own alpha
--     and tint (Highlight.STATE_LOOK). A mouseover highlight steps aside while the plate is your
--     target, and so does a focus highlight that draws the target highlight's art around the
--     same region, so the target art is never doubled.
--   * Motion: the plate shows and hides state-tied parts (Plate:SetState); this part fades in over
--     the same 0.15 s as the plate's target emphasis (P.Scheduler, never an OnUpdate) and follows
--     the plate's eased growth because everything hangs from the plate. spec.animate: 'pulse'
--     (alpha) or 'bounce' (the pair of pictures moves in and out), both AnimationGroups.
--   * S4: when the target is only known as a secret, the plate fades widget.frame from it; this
--     part keeps its own alpha at the state's look.
--   Highlight colors are always plain (style colors and state tints), so gradients are safe here.
-- art: a static theme decoration (nine-slice plate, emblem). spec.art is a file path, or a
--   LibSharedMedia key of type ArtAliases.MEDIA.art ('nameplateart') or 'background'. Nothing draws when it does not
--   resolve: decorations have no stand-in.

---@class Plates.Highlight
local Highlight = {}
P.Highlight = Highlight

Highlight.ARTS = { 'arrows', 'doubleArrows', 'brackets', 'glow', 'underline', 'sideBars' }
Highlight.WHITE = 'Interface\\Buttons\\WHITE8X8'
Highlight.FADE = 0.15
---How far the pair of pictures moves for 'bounce', in pixels.
Highlight.BOUNCE = 3

---Alpha and tint per state. mix lightens the tint toward white (0 keeps the style color).
Highlight.STATE_LOOK = {
	target = { alpha = 1, mix = 0 },
	focus = { alpha = 0.85, mix = 0 },
	mouseover = { alpha = 0.5, mix = 0.35 },
}

local made = 0

----------------------------------------------------------------------------------------------------
-- Piece pools: textures and lines, reused across layouts
----------------------------------------------------------------------------------------------------

local function Pool(frame)
	return { frame = frame, textures = {}, lines = {}, modes = {}, nt = 0, nl = 0 }
end

local function Begin(pool)
	pool.nt, pool.nl = 0, 0
end

---@param mode? string 'solid' (default), 'fadeIn', 'fadeOut' (gradients along the strip), 'picture'
local function Tex(pool, mode, alpha)
	pool.nt = pool.nt + 1
	local texture = pool.textures[pool.nt]
	if not texture then
		texture = pool.frame:CreateTexture(nil, 'ARTWORK')
		pool.textures[pool.nt] = texture
	end
	texture:SetTexture(Highlight.WHITE)
	texture:SetTexCoord(0, 1, 0, 1)
	texture:ClearAllPoints()
	texture:SetAlpha(alpha or 1)
	texture:Show()
	pool.modes[pool.nt] = mode or 'solid'
	return texture
end

local function Line(pool, thickness, alpha)
	pool.nl = pool.nl + 1
	local line = pool.lines[pool.nl]
	if not line then
		line = pool.frame:CreateLine(nil, 'ARTWORK')
		line:SetTexture(Highlight.WHITE)
		pool.lines[pool.nl] = line
	end
	line:SetThickness(thickness)
	line:SetAlpha(alpha or 1)
	line:Show()
	return line
end

local function Finish(pool, textures, blend)
	for i = pool.nt + 1, #pool.textures do
		pool.textures[i]:Hide()
	end
	for i = pool.nl + 1, #pool.lines do
		pool.lines[i]:Hide()
	end
	for i = 1, pool.nt do
		pool.textures[i]:SetBlendMode(blend)
		textures[#textures + 1] = pool.textures[i]
	end
	for i = 1, pool.nl do
		pool.lines[i]:SetBlendMode(blend)
	end
end

local function Paint(pool, r, g, b, a)
	for i = 1, pool.nt do
		local texture = pool.textures[i]
		local mode = pool.modes[i]
		if (mode == 'fadeIn' or mode == 'fadeOut') and texture.SetGradient and CreateColor then
			local clear, full = CreateColor(r, g, b, 0), CreateColor(r, g, b, a)
			if mode == 'fadeIn' then
				texture:SetGradient('HORIZONTAL', clear, full)
			else
				texture:SetGradient('HORIZONTAL', full, clear)
			end
		else
			texture:SetVertexColor(r, g, b, a)
		end
	end
	for i = 1, pool.nl do
		pool.lines[i]:SetVertexColor(r, g, b, a)
	end
end

----------------------------------------------------------------------------------------------------
-- Geometry
----------------------------------------------------------------------------------------------------

---Size of the region a highlight surrounds, from the style (never read back from a frame).
---@param ctx Plates.LayoutContext
---@param id string 'plate' or a part id
---@return number w
---@return number h
local function RegionSize(ctx, id)
	local spec = id ~= 'plate' and ctx.style and ctx.style.parts and ctx.style.parts[id]
	if spec then
		return P.Styles.Merge.PartSize(spec, ctx.width, ctx.height)
	end
	return ctx.width, ctx.height
end

---Height of an arrow picture for a region height (whole pixels).
---@param spec table
---@param h number
---@return integer
function Highlight.ArrowSize(spec, h)
	if spec.size and spec.size > 0 then
		return math.floor(spec.size + 0.5)
	end
	return math.max(10, math.min(22, math.floor(h + 6.5)))
end

local function PlaceSides(widget, w, h, gap)
	local left, right = widget.left, widget.right
	left:ClearAllPoints()
	left:SetSize(w, h)
	left:SetPoint('RIGHT', widget.frame, 'LEFT', -gap, 0)
	right:ClearAllPoints()
	right:SetSize(w, h)
	right:SetPoint('LEFT', widget.frame, 'RIGHT', gap, 0)
end

---A chevron in a side frame. pointRight: '>' on the left side, else '<' on the right side.
---inset moves the chevron's open end in; back moves its tip back (double arrows).
local function Chevron(pool, frame, pointRight, thickness, inset, back, alpha)
	local a = Line(pool, thickness, alpha)
	local b = Line(pool, thickness, alpha)
	if pointRight then
		a:SetStartPoint('TOPLEFT', frame, inset, 0)
		a:SetEndPoint('RIGHT', frame, -back, 0)
		b:SetStartPoint('BOTTOMLEFT', frame, inset, 0)
		b:SetEndPoint('RIGHT', frame, -back, 0)
	else
		a:SetStartPoint('TOPRIGHT', frame, -inset, 0)
		a:SetEndPoint('LEFT', frame, back, 0)
		b:SetStartPoint('BOTTOMRIGHT', frame, -inset, 0)
		b:SetEndPoint('LEFT', frame, back, 0)
	end
end

---Stand-in shapes, drawn from plain textures and lines. Each returns the kind of drawing it made
---('pair' when the side frames are used, so 'bounce' can move them).
local SHAPES = {}

SHAPES.arrows = function(widget, spec, w, h)
	local s = Highlight.ArrowSize(spec, h)
	local aw = math.max(4, math.floor(s * 0.5 + 0.5))
	local t = math.max(2, math.floor(s / 7 + 0.5))
	PlaceSides(widget, aw, s, spec.pad or 2)
	Chevron(widget.pools.left, widget.left, true, t, 0, 0, 1)
	Chevron(widget.pools.right, widget.right, false, t, 0, 0, 1)
	return 'pair'
end

SHAPES.doubleArrows = function(widget, spec, w, h)
	local s = Highlight.ArrowSize(spec, h)
	local aw = math.max(4, math.floor(s * 0.5 + 0.5))
	local d = math.max(3, math.floor(aw * 0.75 + 0.5))
	local t = math.max(2, math.floor(s / 7 + 0.5))
	PlaceSides(widget, aw + d, s, spec.pad or 2)
	Chevron(widget.pools.left, widget.left, true, t, d, 0, 1)
	Chevron(widget.pools.left, widget.left, true, t, 0, d, 0.55)
	Chevron(widget.pools.right, widget.right, false, t, d, 0, 1)
	Chevron(widget.pools.right, widget.right, false, t, 0, d, 0.55)
	return 'pair'
end

SHAPES.sideBars = function(widget, spec, w, h)
	local pad = spec.pad or 2
	local barH = math.floor(h + pad * 2 + 0.5)
	local barW = (spec.size and spec.size > 0) and math.floor(spec.size + 0.5) or math.max(2, math.floor(barH * 0.2 + 0.5))
	PlaceSides(widget, barW, barH, pad)
	Tex(widget.pools.left):SetAllPoints(widget.left)
	Tex(widget.pools.right):SetAllPoints(widget.right)
	return 'pair'
end

SHAPES.brackets = function(widget, spec, w, h)
	local pool, frame = widget.pools.main, widget.frame
	local pad = spec.pad or 2
	local t = (spec.size and spec.size > 0) and math.floor(spec.size + 0.5) or 2
	local k = math.max(3, math.min(8, math.floor(h * 0.6 + 0.5)))
	-- Left: upright bar, then the two ticks pointing in
	local bar = Tex(pool)
	bar:SetPoint('TOPLEFT', frame, 'TOPLEFT', -pad - t, pad)
	bar:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMLEFT', -pad, -pad)
	local top = Tex(pool)
	top:SetPoint('TOPLEFT', frame, 'TOPLEFT', -pad, pad)
	top:SetPoint('BOTTOMRIGHT', frame, 'TOPLEFT', -pad + k, pad - t)
	local bottom = Tex(pool)
	bottom:SetPoint('TOPLEFT', frame, 'BOTTOMLEFT', -pad, -pad + t)
	bottom:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMLEFT', -pad + k, -pad)
	-- Right, mirrored
	bar = Tex(pool)
	bar:SetPoint('TOPLEFT', frame, 'TOPRIGHT', pad, pad)
	bar:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', pad + t, -pad)
	top = Tex(pool)
	top:SetPoint('TOPLEFT', frame, 'TOPRIGHT', pad - k, pad)
	top:SetPoint('BOTTOMRIGHT', frame, 'TOPRIGHT', pad, pad - t)
	bottom = Tex(pool)
	bottom:SetPoint('TOPLEFT', frame, 'BOTTOMRIGHT', pad - k, -pad + t)
	bottom:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', pad, -pad)
	return 'frame'
end

SHAPES.underline = function(widget, spec, w, h)
	local pool, frame = widget.pools.main, widget.frame
	local gap = spec.pad or 2
	local th = (spec.size and spec.size > 0) and math.floor(spec.size + 0.5) or 2
	local tip = math.max(4, math.floor(w * 0.2 + 0.5))
	local left = Tex(pool, 'fadeIn')
	left:SetPoint('TOPLEFT', frame, 'BOTTOMLEFT', 0, -gap)
	left:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMLEFT', tip, -gap - th)
	local middle = Tex(pool)
	middle:SetPoint('TOPLEFT', frame, 'BOTTOMLEFT', tip, -gap)
	middle:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -tip, -gap - th)
	local right = Tex(pool, 'fadeOut')
	right:SetPoint('TOPLEFT', frame, 'BOTTOMRIGHT', -tip, -gap)
	right:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 0, -gap - th)
	return 'strip'
end

---Draw the art set's picture for a slot.
local function Picture(widget, spec, slot, path, w, h)
	local draw = slot and slot.draw or 'sliced'
	local pad = spec.pad or 2
	if draw == 'pair' then
		local ph = slot.fit == 'plate' and math.floor(h + pad * 2 + 0.5) or Highlight.ArrowSize(spec, h)
		local pw = math.max(1, math.floor(ph * (slot.aspect or 0.5) + 0.5))
		PlaceSides(widget, pw, ph, pad)
		local left = Tex(widget.pools.left, 'picture')
		left:SetTexture(path)
		left:SetAllPoints(widget.left)
		local right = Tex(widget.pools.right, 'picture')
		right:SetTexture(path)
		right:SetTexCoord(1, 0, 0, 1)
		right:SetAllPoints(widget.right)
		return 'pair'
	end
	local texture = Tex(widget.pools.main, 'picture')
	texture:SetTexture(path)
	if draw == 'below' then
		local th = (spec.size and spec.size > 0) and math.floor(spec.size + 0.5) or slot.height or 3
		texture:SetPoint('TOPLEFT', widget.frame, 'BOTTOMLEFT', 0, -pad)
		texture:SetPoint('BOTTOMRIGHT', widget.frame, 'BOTTOMRIGHT', 0, -pad - th)
		return 'strip'
	end
	texture:SetPoint('TOPLEFT', widget.frame, 'TOPLEFT', -pad, pad)
	texture:SetPoint('BOTTOMRIGHT', widget.frame, 'BOTTOMRIGHT', pad, -pad)
	local margins = slot and slot.margins
	if margins and texture.SetTextureSliceMargins then
		texture:SetTextureSliceMargins(margins[1], margins[2], margins[3], margins[4])
		if texture.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
			texture:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
		end
	end
	return 'frame'
end

---The picture for a highlight art key, when the art set (or another addon) has one.
---@param key string
---@param ctx Plates.LayoutContext
---@return string|nil path
---@return table|nil slot
function Highlight.PictureFor(key, ctx)
	local Art = P.Data.ArtAliases
	key = Art:Resolve(key)
	local slot = Art:Slot('highlight', key)
	local path = ctx:Texture(key, Art.MEDIA.highlight)
	if not path and slot and slot.file and P.host and P.host.mediaPath then
		path = P.host.mediaPath .. slot.file
	end
	return path, slot
end

----------------------------------------------------------------------------------------------------
-- Motion and state looks
----------------------------------------------------------------------------------------------------

local function Group(frame)
	local group = frame:CreateAnimationGroup()
	group:SetLooping('BOUNCE')
	return group
end

local function StopMotion(widget)
	for _, group in pairs(widget.anims) do
		group:Stop()
	end
end

local function SetupMotion(widget, animate, drawing)
	StopMotion(widget)
	widget.animate = nil
	if animate ~= 'pulse' and animate ~= 'bounce' then
		return
	end
	if not widget.motion.CreateAnimationGroup then
		return
	end
	local anims = widget.anims
	if animate == 'bounce' and drawing == 'pair' then
		if not anims.left then
			anims.left = Group(widget.left)
			anims.leftMove = anims.left:CreateAnimation('Translation')
			anims.right = Group(widget.right)
			anims.rightMove = anims.right:CreateAnimation('Translation')
		end
		anims.leftMove:SetOffset(-Highlight.BOUNCE, 0)
		anims.leftMove:SetDuration(0.45)
		anims.rightMove:SetOffset(Highlight.BOUNCE, 0)
		anims.rightMove:SetDuration(0.45)
		widget.animate = 'bounce'
	else
		if not anims.pulse then
			anims.pulse = Group(widget.motion)
			anims.pulseAlpha = anims.pulse:CreateAnimation('Alpha')
			anims.pulseAlpha:SetFromAlpha(1)
			anims.pulseAlpha:SetToAlpha(0.45)
			anims.pulseAlpha:SetDuration(0.6)
		end
		widget.animate = 'pulse'
	end
end

local function PlayMotion(widget)
	local anims = widget.anims
	if widget.animate == 'bounce' then
		if not anims.left:IsPlaying() then
			anims.left:Play()
			anims.right:Play()
		end
	elseif widget.animate == 'pulse' then
		if not anims.pulse:IsPlaying() then
			anims.pulse:Play()
		end
	end
end

---The alpha and tint a highlight shows with right now (plain; from plate states only).
---@param widget Plates.Widget
---@return number alpha
---@return table look
function Highlight.Look(widget)
	local state = widget.spec.state
	local look = Highlight.STATE_LOOK[state] or Highlight.STATE_LOOK.target
	if widget.plate.states.target and (state == 'mouseover' or (state == 'focus' and widget.sharesTargetArt)) then
		return 0, look
	end
	return look.alpha, look
end

---Whether a target highlight in the same style draws the same art around the same region, so a
---focus highlight on the target would only double it.
---@param style table Resolved style
---@param spec table This highlight's spec
---@param art string Resolved art key
---@return boolean
function Highlight.SharesTargetArt(style, spec, art)
	if spec.state ~= 'focus' or not style or not style.parts then
		return false
	end
	local region = spec.anchor and spec.anchor[2] or 'plate'
	for _, other in pairs(style.parts) do
		if other ~= spec and other.kind == 'highlight' and other.state == 'target' then
			local otherRegion = other.anchor and other.anchor[2] or 'plate'
			if otherRegion == region and P.Data.ArtAliases:Resolve(other.art or 'arrows') == art then
				return true
			end
		end
	end
	return false
end

local function Repaint(widget, look)
	local base = widget.color
	local mix = look.mix or 0
	local r = base[1] + (1 - base[1]) * mix
	local g = base[2] + (1 - base[2]) * mix
	local b = base[3] + (1 - base[3]) * mix
	local a = base[4]
	for _, pool in pairs(widget.pools) do
		Paint(pool, r, g, b, a)
	end
	if widget.usesGlow then
		P.GlowLib.SetColor(widget.glow, r, g, b, a)
	end
end

---Set the state alpha, fading in when asked.
local function ApplyLook(widget, fadeIn)
	local alpha, look = Highlight.Look(widget)
	Repaint(widget, look)
	local inner = widget.inner
	if fadeIn and alpha > 0 then
		P.Scheduler:Ease(widget.key, 0, alpha, Highlight.FADE, widget.fadeIn)
	else
		P.Scheduler:StopEase(widget.key)
		inner:SetAlpha(alpha)
	end
	local state = widget.spec.state
	if alpha > 0 and (not state or widget.plate.states[state]) then
		PlayMotion(widget)
	else
		StopMotion(widget)
	end
end

----------------------------------------------------------------------------------------------------
-- Part
----------------------------------------------------------------------------------------------------

local function Create(plate)
	made = made + 1
	local holder = CreateFrame('Frame', nil, plate.art)
	local inner = CreateFrame('Frame', nil, holder)
	inner:SetAllPoints(holder)
	local motion = CreateFrame('Frame', nil, inner)
	motion:SetAllPoints(inner)
	local left = CreateFrame('Frame', nil, motion)
	local right = CreateFrame('Frame', nil, motion)
	return {
		frame = holder,
		inner = inner,
		motion = motion,
		left = left,
		right = right,
		pools = { main = Pool(motion), left = Pool(left), right = Pool(right) },
		anims = {},
		textures = {},
		color = { 1, 1, 1, 1 },
		key = 'highlight' .. made,
		-- Made once: every target change fades a highlight in with it
		fadeIn = function(value)
			inner:SetAlpha(value)
		end,
	}
end

local function Layout(widget, spec, ctx)
	local anchor = spec.anchor
	local regionId = anchor and anchor[2] or 'plate'
	local region = ctx:Region(regionId)
	local x, y = anchor and anchor[4] or 0, anchor and anchor[5] or 0
	local holder = widget.frame
	holder:ClearAllPoints()
	holder:SetPoint('TOPLEFT', region, 'TOPLEFT', x, y)
	holder:SetPoint('BOTTOMRIGHT', region, 'BOTTOMRIGHT', x, y)
	local w, h = RegionSize(ctx, regionId)

	local art = P.Data.ArtAliases:Resolve(spec.art or 'arrows')
	widget.sharesTargetArt = Highlight.SharesTargetArt(ctx.style, spec, art)
	local path, slot = Highlight.PictureFor(art, ctx)
	for _, pool in pairs(widget.pools) do
		Begin(pool)
	end
	local drawing
	widget.usesGlow = false
	if slot and slot.draw == 'glow' and not path then
		-- Made on first use: most highlights never need a glow
		widget.glow = widget.glow or P.GlowLib.Create(widget.motion)
		local size = (spec.size and spec.size > 0) and spec.size or ((spec.pad or 2) + 4)
		P.GlowLib.Layout(widget.glow, holder, P.GlowLib.Opts(slot.look, size, nil, spec.blend, 'none'), ctx)
		P.GlowLib.Show(widget.glow, true)
		widget.usesGlow = true
		drawing = 'glow'
	elseif path then
		drawing = Picture(widget, spec, slot, path, w, h)
	else
		drawing = (SHAPES[art] or SHAPES.arrows)(widget, spec, w, h)
	end
	if not widget.usesGlow and widget.glow then
		P.GlowLib.Reset(widget.glow)
	end

	local textures = widget.textures
	P.util.Wipe(textures)
	local blend = spec.blend == 'ADD' and 'ADD' or 'BLEND'
	for _, pool in pairs(widget.pools) do
		Finish(pool, textures, blend)
	end
	if widget.usesGlow then
		for _, texture in ipairs(widget.glow.textures) do
			textures[#textures + 1] = texture
		end
	end
	local r, g, b, a = ctx:Color(spec.color)
	local color = widget.color
	color[1], color[2], color[3], color[4] = r, g, b, a
	SetupMotion(widget, spec.animate, drawing)
	widget.drawing = drawing
	ApplyLook(widget, false)
end

P.Parts:Register({
	id = 'highlight',
	kinds = { 'highlight' },
	Create = Create,
	Layout = Layout,
	Update = function(widget, _, event)
		if event == 'FULL' then
			ApplyLook(widget, false)
		end
	end,
	OnState = function(widget, state, on)
		local mine = widget.spec.state
		if state == mine then
			if on then
				ApplyLook(widget, true)
			else
				P.Scheduler:StopEase(widget.key)
				StopMotion(widget)
			end
		elseif state == 'target' and (mine == 'mouseover' or (mine == 'focus' and widget.sharesTargetArt)) then
			ApplyLook(widget, false)
		end
	end,
	OnStateSecret = function(widget, state)
		if state == widget.spec.state then
			-- The plate fades widget.frame from the secret answer; keep the state's own look here
			ApplyLook(widget, false)
		end
	end,
	Reset = function(widget)
		P.Scheduler:StopEase(widget.key)
		StopMotion(widget)
		widget.inner:SetAlpha(1)
	end,
})

----------------------------------------------------------------------------------------------------
-- Theme art
----------------------------------------------------------------------------------------------------

P.Parts:Register({
	id = 'art',
	kinds = { 'art' },
	Create = function(plate)
		local holder = CreateFrame('Frame', nil, plate.art)
		local texture = holder:CreateTexture(nil, 'BACKGROUND')
		texture:SetAllPoints(holder)
		return { frame = holder, texture = texture, textures = { texture } }
	end,
	Layout = function(widget, spec, ctx)
		local holder = widget.frame
		holder:ClearAllPoints()
		local anchor = spec.anchor
		if spec.fill == 'plate' then
			local x, y = anchor and anchor[4] or 0, anchor and anchor[5] or 0
			holder:SetPoint('TOPLEFT', ctx.plate.art, 'TOPLEFT', x, y)
			holder:SetPoint('BOTTOMRIGHT', ctx.plate.art, 'BOTTOMRIGHT', x, y)
		else
			holder:SetSize(spec.width or ctx.width, spec.height or ctx.height)
			ctx:Anchor(holder, anchor)
		end
		local path = ctx:Texture(spec.art, P.Data.ArtAliases.MEDIA.art) or ctx:Texture(spec.art, 'background')
		local texture = widget.texture
		if path then
			texture:SetTexture(path)
			texture:SetVertexColor(ctx:Color(spec.color))
			texture:Show()
		else
			texture:Hide()
		end
	end,
	Update = function() end,
	Reset = function() end,
})
