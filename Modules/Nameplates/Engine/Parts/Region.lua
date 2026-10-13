local _, ns = ...
local P = ns.Plates
local L = P.L
local Secret = P.Secret

-- Click and stacking areas you can see (kind 'region', plan 3.2 and Phase 7).
--
-- Two things live here:
--   P.Regions   draws a plate's click area and stacking area as outlined boxes. The preview
--               panel's eye toggle ("Show all parts") calls Regions:SetShowAll(on): every plate,
--               preview and real, then draws its boxes, so the player can check them in a crowd.
--               Regions:ShowBoxes(plate, on) shows one plate only (the designer's selection).
--   'region'    the part kind. A style part { kind = 'region', region = 'click' | 'stack' }
--               draws that area's box while boxes are shown. Without width and height it follows
--               the style's own area (style.regions, worked out by Merge.Regions). With width and
--               height it is a hand-placed area (the Phase 7 palette's "Click area"): Merge.Regions
--               then uses its rect for that area, so dragging the part moves the real click area.
-- Where a real plate's boxes go: the click box covers the Driver's click frame (plate.click), or
-- Blizzard's base plate when hit-test rebinding is off (capability 'hitTest' false: recorded by the
-- first real plate or forced, the S1 fallback), or else the style's rect around the center. The
-- stacking box covers plate.stack, or the style's rect. Boxes never take the mouse, live on the
-- plate root above the art, and are made only the first time a plate has to show them.

---@class Plates.Regions
local Regions = {
	showAll = false,
	perPlate = setmetatable({}, { __mode = 'k' }),
	plates = setmetatable({}, { __mode = 'k' }),
	boxes = setmetatable({}, { __mode = 'k' }),
	parts = setmetatable({}, { __mode = 'k' }),
}
P.Regions = Regions

local WHITE = 'Interface\\Buttons\\WHITE8X8'
Regions.KINDS = { 'click', 'stack' }
Regions.COLORS = { click = { 0.25, 0.75, 1 }, stack = { 1, 0.6, 0.15 } }
Regions.LABELS = { click = L['Click area'], stack = L['Stacking area'] }
Regions.FILL_ALPHA = 0.12
-- Above every part level a style can use (Plate ApplyCommon: base + 1 + rank + (layer + 8) * 32)
Regions.LEVEL = 600

----------------------------------------------------------------------------------------------------
-- Boxes
----------------------------------------------------------------------------------------------------

---An outlined box: a faint fill, four one-pixel edges and a small label. Frames only.
---@param parent table
---@return table box
local function NewBox(parent)
	local box = CreateFrame('Frame', nil, parent)
	box.fill = box:CreateTexture(nil, 'BACKGROUND')
	box.fill:SetTexture(WHITE)
	box.fill:SetAllPoints(box)
	box.edges = {}
	for i = 1, 4 do
		local edge = box:CreateTexture(nil, 'BORDER')
		edge:SetTexture(WHITE)
		box.edges[i] = edge
	end
	box.label = box:CreateFontString(nil, 'OVERLAY')
	box.label:SetFont(P.services.FontPath(), 8, 'OUTLINE')
	box:Hide()
	return box
end
Regions.NewBox = NewBox

---Color, edges and label for one kind of area.
---@param box table
---@param which 'click'|'stack'
---@param pixel number
local function PaintBox(box, which, pixel)
	local color = Regions.COLORS[which] or Regions.COLORS.click
	local r, g, b = color[1], color[2], color[3]
	box.fill:SetVertexColor(r, g, b, Regions.FILL_ALPHA)
	local top, bottom, left, right = box.edges[1], box.edges[2], box.edges[3], box.edges[4]
	for _, edge in ipairs(box.edges) do
		edge:ClearAllPoints()
		edge:SetVertexColor(r, g, b, 0.9)
	end
	top:SetPoint('TOPLEFT', box, 'TOPLEFT', 0, 0)
	top:SetPoint('TOPRIGHT', box, 'TOPRIGHT', 0, 0)
	top:SetHeight(pixel)
	bottom:SetPoint('BOTTOMLEFT', box, 'BOTTOMLEFT', 0, 0)
	bottom:SetPoint('BOTTOMRIGHT', box, 'BOTTOMRIGHT', 0, 0)
	bottom:SetHeight(pixel)
	left:SetPoint('TOPLEFT', box, 'TOPLEFT', 0, 0)
	left:SetPoint('BOTTOMLEFT', box, 'BOTTOMLEFT', 0, 0)
	left:SetWidth(pixel)
	right:SetPoint('TOPRIGHT', box, 'TOPRIGHT', 0, 0)
	right:SetPoint('BOTTOMRIGHT', box, 'BOTTOMRIGHT', 0, 0)
	right:SetWidth(pixel)
	-- Click label in the top left corner, stacking label in the bottom right, so both stay readable
	box.label:ClearAllPoints()
	if which == 'stack' then
		box.label:SetPoint('BOTTOMRIGHT', box, 'BOTTOMRIGHT', -2, 2)
	else
		box.label:SetPoint('TOPLEFT', box, 'TOPLEFT', 2, -2)
	end
	box.label:SetText(Regions.LABELS[which] or '')
	box.label:SetTextColor(r, g, b, 1)
	box.which = which
end
Regions.PaintBox = PaintBox

---Size of one physical pixel for a frame (1 when the scale cannot be read).
---@param frame table
---@return number
local function Pixel(frame)
	local scale = frame and frame.GetEffectiveScale and Secret.Plain(frame:GetEffectiveScale())
	local physical = GetPhysicalScreenSize and select(2, GetPhysicalScreenSize()) or 768
	if type(scale) ~= 'number' or scale <= 0 or not physical or physical <= 0 then
		return 1
	end
	return 768 / physical / scale
end

---True when hit-test rebinding is off (S1): the base plate keeps Blizzard's click area. The
---Driver's probe starts hopeful and the first real plate records the answer (or the cap command
---forces it).
---@return boolean
function Regions.HitTestOff()
	return not P.Caps:Get('hitTest')
end

---Point a box at the area it shows on a plate.
---@param box table
---@param plate Plates.Plate
---@param which 'click'|'stack'
local function PlaceBox(box, plate, which)
	box:ClearAllPoints()
	local target
	if not plate.isPreview then
		if which == 'click' then
			if Regions.HitTestOff() and plate.base then
				target = plate.base
			else
				target = plate.click
			end
		else
			target = plate.stack
		end
	end
	if target then
		box:SetAllPoints(target)
		return
	end
	local rect = plate.style and plate.style.regions and plate.style.regions[which]
	if not rect then
		box:SetAllPoints(plate.art)
		return
	end
	box:SetPoint('TOPLEFT', plate.art, 'CENTER', rect.left, rect.top)
	box:SetPoint('BOTTOMRIGHT', plate.art, 'CENTER', rect.right, rect.bottom)
end

---True when the plate's style has a region part for this area (that part draws the box).
local function HasPart(plate, which)
	for i = 1, #(plate.active or {}) do
		local widget = plate.active[i]
		if widget.impl.id == 'region' and (widget.spec.region or 'click') == which then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------------------------------------
-- Showing and hiding
----------------------------------------------------------------------------------------------------

---Whether a plate draws its boxes now: its own setting (ShowBoxes) wins, then Show all parts.
---@param plate Plates.Plate
---@return boolean
function Regions:Wanted(plate)
	local own = self.perPlate[plate]
	if own ~= nil then
		return own
	end
	return self.showAll
end

---Draw or hide one plate's boxes (and its region parts) for what Wanted says now.
---@param plate Plates.Plate
function Regions:Refresh(plate)
	local want = self:Wanted(plate) and plate.style ~= nil
	local boxes = self.boxes[plate]
	if want and not boxes then
		boxes = {}
		for _, which in ipairs(self.KINDS) do
			boxes[which] = NewBox(plate.root)
		end
		self.boxes[plate] = boxes
	end
	if boxes then
		local level = (plate.artLevel or 0) + self.LEVEL
		local pixel = want and Pixel(plate.art) or 1
		for _, which in ipairs(self.KINDS) do
			local box = boxes[which]
			if want and not HasPart(plate, which) then
				box:SetFrameLevel(level)
				PaintBox(box, which, pixel)
				PlaceBox(box, plate, which)
				box:Show()
			else
				box:Hide()
			end
		end
	end
	for widget in pairs(self.parts) do
		if widget.plate == plate then
			widget.box:SetShown(widget.active and self:Wanted(plate) or false)
		end
	end
end

---The eye toggle: every plate, in previews and in the world, draws its click and stacking boxes.
---Session only. Fires REGION_BOXES_CHANGED(on).
---@param on boolean
function Regions:SetShowAll(on)
	on = on and true or false
	if self.showAll == on then
		return
	end
	self.showAll = on
	for plate in pairs(self.plates) do
		self:Refresh(plate)
	end
	P:Fire('REGION_BOXES_CHANGED', on)
end

---@return boolean
function Regions:IsShowingAll()
	return self.showAll
end

---Show or hide one plate's boxes whatever the eye toggle says (nil goes back to following it).
---@param plate Plates.Plate
---@param on boolean|nil
function Regions:ShowBoxes(plate, on)
	self.perPlate[plate] = on
	self.plates[plate] = true
	self:Refresh(plate)
end

-- A plate laid out for a new style: its areas may have moved
P:On('STYLE_APPLIED', function(plate)
	Regions.plates[plate] = true
	if Regions.boxes[plate] or Regions:Wanted(plate) then
		Regions:Refresh(plate)
	end
end, Regions)

-- A real plate was bound: the Driver has placed its click and stacking frames by now
P:On('PLATE_ADDED', function(plate)
	if plate then
		Regions.plates[plate] = true
		if Regions.boxes[plate] or Regions:Wanted(plate) then
			Regions:Refresh(plate)
		end
	end
end, Regions)

P:On('ENGINE_DISABLED', function()
	for plate, boxes in pairs(Regions.boxes) do
		if not plate.isPreview then
			for _, box in pairs(boxes) do
				box:Hide()
			end
		end
	end
end, Regions)

----------------------------------------------------------------------------------------------------
-- The part
----------------------------------------------------------------------------------------------------

P.Parts:Register({
	id = 'region',
	kinds = { 'region' },
	Create = function(plate)
		local holder = CreateFrame('Frame', nil, plate.art)
		local box = NewBox(holder)
		box:SetAllPoints(holder)
		return { frame = holder, box = box, textures = { box.fill } }
	end,
	Layout = function(widget, spec, ctx)
		local which = spec.region or 'click'
		local frame = widget.frame
		frame:ClearAllPoints()
		if spec.width and spec.height then
			-- A hand-placed area: Merge.Regions uses this rect for the real area
			frame:SetSize(spec.width, spec.height)
			ctx:Anchor(frame, spec.anchor)
		else
			local rect = ctx.style and ctx.style.regions and ctx.style.regions[which]
			if rect then
				frame:SetPoint('TOPLEFT', ctx.plate.art, 'CENTER', rect.left, rect.top)
				frame:SetPoint('BOTTOMRIGHT', ctx.plate.art, 'CENTER', rect.right, rect.bottom)
			else
				frame:SetAllPoints(ctx.plate.art)
			end
		end
		PaintBox(widget.box, which, ctx:Pixel())
		widget.which = which
		Regions.parts[widget] = true
		Regions.plates[ctx.plate] = true
		widget.box:SetShown(Regions:Wanted(ctx.plate))
	end,
	Update = function() end,
	Reset = function() end,
})
