local _, ns = ...
local P = ns.Plates
local L = P.L
local util = P.util

-- The designer (3.2 drag-to-move, 3.4 full designer): selecting, moving, resizing, adding and
-- hiding parts in the preview panel, with undo and redo. Never a control inside an options page
-- (pages are torn down on every change): the preview provider calls Designer:Attach while it draws
-- the Customize scene, and the Customize page reads and changes the same session state.
--
-- Session state (never saved): the selection (a list, the first id is the primary part), the
-- "Preview as" kind, the scope ('all' or 'kind': "Only for these plates") and the history.
--
-- Every edit writes the player's overlay through P.Store, never built-in data:
--   whole style       profile.tweaks[styleId].changes.parts[id]
--   only these plates profile.tweaks[styleId].situations[kind].parts[id]
--   added parts       profile.tweaks[styleId].add[id]
-- so "Undo my changes" and "Reset this part" always work. Undo and redo keep 20 steps per session;
-- each step is a copy of tweaks[styleId] taken before the edit (a drag copies it when it starts).
--
-- Moving: click a part to select it, then drag it. The Stage turns the cursor movement into plate
-- units with the dragged part's effective scale. While it moves, the part's frame is offset in
-- place (nothing is written) and snaps to the plate's edges and centers, with guide lines. On drop
-- the anchor is chosen for the player (DropAnchor): the nearest part or the plate, the side of it
-- the part sits on, centers snapped within 2 px, offsets rounded to half pixels. Arrow keys nudge
-- by 0.5 px (Shift 2 px), Delete hides the selection, Ctrl-Z undoes, Ctrl-Y or Ctrl-Shift-Z redoes.
-- Shift-click selects several parts; dragging moves them together, keeping their relative places
-- (a selected part anchored to another selected part simply follows it).

---@class Plates.Designer
local Designer = {
	state = { selection = {}, kind = 'enemyNPC', scope = 'all' },
	cache = {},
	cacheGeneration = -1,
}
P.Designer = Designer

Designer.HISTORY_LIMIT = 20
Designer.COALESCE = 1.5 -- seconds: repeats of one edit (nudges, slider drags) are one undo step
Designer.CENTER_SNAP = 2 -- plate pixels: a center this close to another center snaps onto it
Designer.SNAP_SCREEN = 5 -- screen pixels: how close an edge must come to a guide to snap
Designer.EDGE = 0.5 -- plate pixels: touching counts as beside
Designer.HANDLE_SCREEN = 8 -- resize handle size on screen at zoom 1

Designer.KIND_LABELS = {
	enemyNPC = L['Enemy NPC'],
	enemyPlayer = L['Enemy player'],
	friendlyNPC = L['Friendly NPC'],
	friendlyPlayer = L['Friendly player'],
	minor = L['Minor enemy'],
}
Designer.KIND_PLURALS = {
	enemyNPC = L['enemy NPCs'],
	enemyPlayer = L['enemy players'],
	friendlyNPC = L['friendly NPCs'],
	friendlyPlayer = L['friendly players'],
	minor = L['minor enemies'],
}

Designer.GROUPS = { 'bar', 'text', 'cast', 'auras', 'icons', 'emphasis', 'other' }
Designer.GROUP_LABELS = {
	bar = L['Bar'],
	text = L['Text'],
	cast = L['Cast'],
	auras = L['Auras'],
	icons = L['Icons'],
	emphasis = L['Emphasis'],
	other = L['Other'],
}

Designer.TEXT_LABELS = {
	name = L['Name'],
	level = L['Level'],
	healthPercent = L['Health text'],
	healthValue = L['Health number'],
	forces = L['Mythic+ forces'],
	title = L['Title or guild'],
	threatPercent = L['Threat percent'],
	threatLead = L['Threat lead'],
	castName = L['Spell name'],
	castTime = L['Cast time'],
	castTarget = L['Cast target'],
	arena = L['Arena number'],
	nameFill = L['Name with health'],
}
Designer.ICON_LABELS = {
	raidMarker = L['Raid marker'],
	classification = L['Classification icon'],
	quest = L['Quest icon'],
	faction = L['Faction icon'],
	focus = L['Focus mark'],
	shield = L['Shield icon'],
}
Designer.AURA_LABELS = {
	myDebuffs = L['My debuffs'],
	removable = L['Enemy buffs'],
	crowdControl = L['Crowd control'],
	custom = L['Always show'],
}
Designer.GLOW_LABELS = {
	threat = L['Threat glow'],
	importantCast = L['Important cast glow'],
	purge = L['Can remove glow'],
	pandemic = L['Pandemic glow'],
	target = L['Target glow'],
}
Designer.HIGHLIGHT_LABELS = {
	target = L['Target highlight'],
	focus = L['Focus highlight'],
	mouseover = L['Mouseover highlight'],
	casting = L['Casting highlight'],
	notTarget = L['Highlight'],
}

---The part palette (Phase 7): what "Add a part" offers.
Designer.PALETTE = {
	{ value = 'bar', text = L['Bar'] },
	{ value = 'text', text = L['Text'] },
	{ value = 'icon', text = L['Icon'] },
	{ value = 'auras', text = L['Aura row'] },
	{ value = 'glow', text = L['Glow'] },
	{ value = 'highlight', text = L['Highlight'] },
	{ value = 'region', text = L['Click area'] },
}

---Rows under a part in the part list that switch one feature of it (the eye only; picking the row
---selects the part). on(spec) reads; set(on, spec, base) returns the field changes.
Designer.SUB_ROWS = {
	bar = {
		{
			key = 'absorb',
			label = L['Absorbs'],
			when = function(spec)
				return spec.source == 'health'
			end,
			on = function(spec)
				return spec.absorb ~= false
			end,
			set = function(on)
				return { absorb = on and true or false, healAbsorb = on and true or false }
			end,
		},
	},
	cast = {
		{
			key = 'icon',
			label = L['Spell icon'],
			on = function(spec)
				return spec.icon ~= 'none'
			end,
			set = function(on, _, base)
				local side = (base and base.icon and base.icon ~= 'none') and base.icon or 'left'
				return { icon = on and side or 'none' }
			end,
		},
		{
			key = 'nameText',
			label = L['Spell name'],
			on = function(spec)
				return spec.nameText ~= false
			end,
			set = function(on)
				return { nameText = on and true or false }
			end,
		},
		{
			key = 'target',
			label = L['Cast target'],
			on = function(spec)
				return spec.target and true or false
			end,
			set = function(on)
				return { target = on and true or false }
			end,
		},
	},
}

----------------------------------------------------------------------------------------------------
-- Pure helpers
----------------------------------------------------------------------------------------------------

local function Half(v)
	return math.floor(v * 2 + 0.5) / 2
end
Designer.Half = Half

local function Now()
	return (GetTime and GetTime()) or 0
end

---Group and label of a part for the list, the panel title and tooltips.
---@param id string
---@param spec table|nil
---@return string group
---@return string label
function Designer.PartInfo(id, spec)
	spec = spec or {}
	local kind = spec.kind
	local group, label = 'other', nil
	if kind == 'bar' then
		group = 'bar'
		label = spec.source == 'power' and L['Power bar'] or L['Health bar']
	elseif kind == 'cast' then
		group, label = 'cast', L['Cast bar']
	elseif kind == 'text' then
		local source = spec.source
		group = (source == 'castName' or source == 'castTime' or source == 'castTarget') and 'cast' or 'text'
		label = Designer.TEXT_LABELS[source] or L['Text']
	elseif kind == 'icon' then
		group, label = 'icons', Designer.ICON_LABELS[spec.source] or L['Icon']
	elseif kind == 'auras' then
		group, label = 'auras', Designer.AURA_LABELS[spec.row] or L['Aura row']
	elseif kind == 'highlight' then
		group, label = 'emphasis', Designer.HIGHLIGHT_LABELS[spec.state] or L['Highlight']
	elseif kind == 'glow' then
		group, label = 'emphasis', Designer.GLOW_LABELS[spec.source] or L['Glow']
	elseif kind == 'classPower' then
		group, label = 'bar', L['Class power']
	elseif kind == 'region' then
		label = spec.region == 'stack' and L['Stacking area'] or L['Click area']
	elseif kind == 'art' then
		label = L['Picture']
	end
	if type(spec.label) == 'string' and spec.label ~= '' then
		label = spec.label
	end
	return group, label or id
end

---True for parts that can be dragged: anchored parts that do not fill or surround the plate.
---@param spec table|nil
---@return boolean
function Designer.Movable(spec)
	if type(spec) ~= 'table' then
		return false
	end
	if spec.fill == 'plate' or spec.kind == 'glow' or spec.kind == 'highlight' then
		return false
	end
	return true
end

---True for parts with a size the resize handle can change.
---@param spec table|nil
---@return boolean
function Designer.Resizable(spec)
	if not Designer.Movable(spec) then
		return false
	end
	local kind = spec.kind
	return kind == 'bar' or kind == 'cast' or kind == 'icon' or kind == 'auras' or kind == 'text' or kind == 'region' or kind == 'art' or kind == 'classPower'
end

---Every part anchored (directly or through others) to `id`, plus `id` itself.
---@param parts table<string, table>
---@param id string
---@return table<string, boolean>
function Designer.Descendants(parts, id)
	local out = { [id] = true }
	local grew = true
	local guard = 0
	while grew and guard < 64 do
		grew = false
		guard = guard + 1
		for partId, spec in pairs(parts) do
			local anchor = spec.anchor
			local target = anchor and anchor[2]
			if not out[partId] and target and out[target] then
				out[partId] = true
				grew = true
			end
		end
	end
	return out
end

---Selected parts that move by themselves: movable ones with no selected part up their anchor
---chain (the others follow along).
---@param parts table<string, table>
---@param selection string[]
---@return string[]
function Designer.Roots(parts, selection)
	local chosen = {}
	for _, id in ipairs(selection) do
		chosen[id] = true
	end
	local out = {}
	for _, id in ipairs(selection) do
		local spec = parts[id]
		if spec and Designer.Movable(spec) then
			local follows = false
			local anchor = spec.anchor
			local guard = 0
			while not follows and anchor and anchor[2] and anchor[2] ~= 'plate' and guard < 32 do
				guard = guard + 1
				if chosen[anchor[2]] then
					follows = true
				else
					local up = parts[anchor[2]]
					anchor = up and up.anchor
				end
			end
			if not follows then
				out[#out + 1] = id
			end
		end
	end
	return out
end

---@param rect Plates.Rect
---@param dx number
---@param dy number
---@return Plates.Rect
function Designer.MoveRect(rect, dx, dy)
	return { left = rect.left + dx, right = rect.right + dx, top = rect.top + dy, bottom = rect.bottom + dy }
end

local function Gap(a, b)
	local gx = math.max(0, b.left - a.right, a.left - b.right)
	local gy = math.max(0, b.bottom - a.top, a.bottom - b.top)
	return math.sqrt(gx * gx + gy * gy)
end

-- One axis of a drop: which side of the part pins to which side of the target
local function Axis(pLo, pHi, tLo, tHi, edge, centerSnap)
	local pc, tc = (pLo + pHi) / 2, (tLo + tHi) / 2
	if pLo >= tHi - edge then
		return 'lo', 'hi'
	end
	if pHi <= tLo + edge then
		return 'hi', 'lo'
	end
	if math.abs(pc - tc) <= centerSnap then
		return 'mid', 'mid'
	end
	if pc < tc then
		return 'lo', 'lo'
	end
	return 'hi', 'hi'
end

local H_NAMES = { lo = 'LEFT', mid = '', hi = 'RIGHT' }
local V_NAMES = { lo = 'BOTTOM', mid = '', hi = 'TOP' }

local function PointName(v, h)
	local name = V_NAMES[v] .. H_NAMES[h]
	return name == '' and 'CENTER' or name
end

local function Coord(side, lo, hi)
	if side == 'lo' then
		return lo
	elseif side == 'hi' then
		return hi
	end
	return (lo + hi) / 2
end

---Pick the anchor for a dropped part (pure). Rects are relative to the plate center.
---The target is the nearest part (or the plate); ties go to `prefer`, then the plate, then by id.
---The part pins on the side of the target it sits on; a center within CENTER_SNAP snaps to the
---target's center; offsets are rounded to half pixels.
---@param partRect Plates.Rect Where the part was dropped
---@param targets table<string, Plates.Rect> Possible targets: other parts and 'plate'
---@param prefer? string The part's current target, kept when it is as near as any
---@return table anchor { point, relativeTo, relPoint, x, y }
function Designer.DropAnchor(partRect, targets, prefer)
	local ids = {}
	for id in pairs(targets) do
		ids[#ids + 1] = id
	end
	table.sort(ids, function(a, b)
		local ra = (a == prefer and 0) or (a == 'plate' and 1) or 2
		local rb = (b == prefer and 0) or (b == 'plate' and 1) or 2
		if ra ~= rb then
			return ra < rb
		end
		return a < b
	end)
	local bestId, bestGap
	for _, id in ipairs(ids) do
		local gap = Gap(partRect, targets[id])
		if not bestGap or gap < bestGap - 0.01 then
			bestId, bestGap = id, gap
		end
	end
	bestId = bestId or 'plate'
	local t = targets[bestId] or { left = 0, right = 0, top = 0, bottom = 0 }
	local edge, snap = Designer.EDGE, Designer.CENTER_SNAP
	local ph, th = Axis(partRect.left, partRect.right, t.left, t.right, edge, snap)
	local pv, tv = Axis(partRect.bottom, partRect.top, t.bottom, t.top, edge, snap)
	local x = Coord(ph, partRect.left, partRect.right) - Coord(th, t.left, t.right)
	local y = Coord(pv, partRect.bottom, partRect.top) - Coord(tv, t.bottom, t.top)
	if ph == 'mid' and math.abs(x) <= snap then
		x = 0
	end
	if pv == 'mid' and math.abs(y) <= snap then
		y = 0
	end
	return { PointName(pv, ph), bestId, PointName(tv, th), Half(x), Half(y) }
end

---Snap guides for a plate: its edges and centers (rect relative to the plate center).
---@param plateRect Plates.Rect
---@return { x: number[], y: number[] }
function Designer.Guides(plateRect)
	return {
		x = { plateRect.left, (plateRect.left + plateRect.right) / 2, plateRect.right },
		y = { plateRect.bottom, (plateRect.bottom + plateRect.top) / 2, plateRect.top },
	}
end

---Snap a moving rect to guide lines (pure). Each axis tries the rect's two edges and its center
---against every line and takes the closest within `tolerance`.
---@param rect Plates.Rect
---@param guides { x: number[], y: number[] }
---@param tolerance number
---@return number dx Correction to add
---@return number dy
---@return number|nil lineX The vertical guide it snapped to
---@return number|nil lineY
function Designer.Snap(rect, guides, tolerance)
	local function Best(values, lines)
		local bestDelta, bestLine
		for _, line in ipairs(lines or {}) do
			for _, v in ipairs(values) do
				local delta = line - v
				if math.abs(delta) <= tolerance and (not bestDelta or math.abs(delta) < math.abs(bestDelta)) then
					bestDelta, bestLine = delta, line
				end
			end
		end
		return bestDelta or 0, bestLine
	end
	local dx, lineX = Best({ rect.left, (rect.left + rect.right) / 2, rect.right }, guides.x)
	local dy, lineY = Best({ rect.bottom, (rect.bottom + rect.top) / 2, rect.top }, guides.y)
	return dx, dy, lineX, lineY
end

local function Clamp(kind, field, value)
	local spec = P.Styles.Schema:FieldSpec(kind, field)
	if spec and spec.t == 'number' then
		if spec.min and value < spec.min then
			value = spec.min
		end
		if spec.max and value > spec.max then
			value = spec.max
		end
		if spec.int then
			value = math.floor(value + 0.5)
		end
	end
	return value
end

---Field changes for a part resized to w x h plate pixels (pure, clamped to the schema).
---@param spec table
---@param w number
---@param h number
---@return table changes field -> value ('font.size' for text height)
function Designer.ResizeFields(spec, w, h)
	local kind = spec.kind
	w, h = math.max(1, math.floor(w + 0.5)), math.max(1, math.floor(h + 0.5))
	if kind == 'bar' or kind == 'cast' or kind == 'region' or kind == 'art' then
		return { width = Clamp(kind, 'width', w), height = Clamp(kind, 'height', h) }
	elseif kind == 'icon' then
		return { size = Clamp(kind, 'size', math.max(w, h)) }
	elseif kind == 'auras' then
		local across = not (spec.grow == 'UP' or spec.grow == 'DOWN')
		return { size = Clamp(kind, 'size', across and h or w) }
	elseif kind == 'classPower' then
		return { size = Clamp(kind, 'size', h) }
	elseif kind == 'text' then
		local font = P.Styles.Schema.PART_FIELDS.text.font.fields.size
		local size = math.max(font.min, math.min(font.max, h - 2))
		return { width = Clamp(kind, 'width', w), ['font.size'] = size }
	end
	return {}
end

---A free id for a new part of a kind: 'text1', 'text2', ...
---@param kind string
---@param parts table<string, table>
---@return string
function Designer.NewPartId(kind, parts)
	local n = 1
	while parts[kind .. n] do
		n = n + 1
	end
	return kind .. n
end

---A new part from the palette (pure): its id and spec, placed where it is easy to see.
---@param kind string Palette value
---@param parts table<string, table> The style's parts (for a free id and the next order)
---@param width? number Plate width
---@param height? number Plate height
---@return string|nil id
---@return table|nil spec
function Designer.NewPart(kind, parts, width, height)
	width, height = width or 132, height or 10
	local order = 0
	for _, spec in pairs(parts) do
		order = math.max(order, spec.order or 0)
	end
	local spec
	if kind == 'bar' then
		spec = { kind = 'bar', source = 'power', width = math.floor(width), height = 4, anchor = { 'TOP', 'plate', 'BOTTOM', 0, -2 } }
	elseif kind == 'text' then
		spec = { kind = 'text', source = 'level', justify = 'CENTER', font = { size = 9 }, anchor = { 'CENTER', 'plate', 'CENTER', 0, 0 } }
	elseif kind == 'icon' then
		spec = { kind = 'icon', source = 'raidMarker', size = 14, anchor = { 'LEFT', 'plate', 'RIGHT', 4, 0 } }
	elseif kind == 'auras' then
		spec = { kind = 'auras', row = 'custom', size = 18, max = 4, grow = 'RIGHT', anchor = { 'BOTTOMLEFT', 'plate', 'TOPLEFT', 0, 16 } }
	elseif kind == 'glow' then
		spec = { kind = 'glow', source = 'target', size = 4 }
	elseif kind == 'highlight' then
		spec = { kind = 'highlight', state = 'target', art = 'brackets' }
	elseif kind == 'region' then
		spec = { kind = 'region', region = 'click', width = math.floor(width + 8), height = math.floor(height + 16), anchor = { 'CENTER', 'plate', 'CENTER', 0, 0 } }
	else
		return nil, nil
	end
	spec.order = order + 1
	return Designer.NewPartId(kind, parts), spec
end

local function Split(point)
	point = point or 'CENTER'
	local v = point:find('TOP') and 'hi' or (point:find('BOTTOM') and 'lo' or 'mid')
	local h = point:find('LEFT') and 'lo' or (point:find('RIGHT') and 'hi' or 'mid')
	return v, h
end
local OPPOSITE = { lo = 'hi', hi = 'lo', mid = 'mid' }

---Which grid cell an anchor shows (the point on what it hangs from).
---@param anchor table|nil
---@return string point
function Designer.GridCell(anchor)
	return (anchor and (anchor[3] or anchor[1])) or 'CENTER'
end

---Anchor for a grid cell pick (pure): the cell is the point on the target, which stays the same.
---Each axis keeps the part inside or outside the target as it was; an axis that was centered goes
---inside when the other axis is outside (a cast bar below the bar, left aligned), else outside.
---Gaps are 2 px; an aligned axis next to an outside one gets none.
---@param anchor table|nil Current anchor
---@param cell string One of the nine points
---@return table anchor
function Designer.GridAnchor(anchor, cell)
	anchor = anchor or { 'CENTER', 'plate', 'CENTER', 0, 0 }
	local oldV, oldH = Split(anchor[1])
	local oldRV, oldRH = Split(anchor[3] or anchor[1])
	local cellV, cellH = Split(cell)
	local relV = oldRV == 'mid' and 'mid' or (oldV == oldRV and 'in' or 'out')
	local relH = oldRH == 'mid' and 'mid' or (oldH == oldRH and 'in' or 'out')
	if relV == 'mid' and relH == 'mid' then
		relV = 'out'
		relH = cellV == 'mid' and 'out' or 'in'
	elseif relV == 'mid' then
		relV = (cellH ~= 'mid' and relH == 'out') and 'in' or 'out'
	elseif relH == 'mid' then
		relH = (cellV ~= 'mid' and relV == 'out') and 'in' or 'out'
	end
	local function Pick(cellSide, rel)
		if cellSide == 'mid' then
			return 'mid', 0
		end
		local sign = cellSide == 'hi' and 1 or -1
		if rel == 'in' then
			return cellSide, -2 * sign
		end
		return OPPOSITE[cellSide], 2 * sign
	end
	local pv, gy = Pick(cellV, relV)
	local ph, gx = Pick(cellH, relH)
	if cellV ~= 'mid' and cellH ~= 'mid' then
		if relV == 'out' and relH == 'in' then
			gx = 0
		elseif relH == 'out' and relV == 'in' then
			gy = 0
		end
	end
	return { PointName(pv, ph), anchor[2] or 'plate', cell, gx, gy }
end

---Anchor and grow direction for an aura row side pick (Above, Below, Left, Right; pure).
---@param anchor table|nil
---@param side 'above'|'below'|'left'|'right'
---@param grow? string Current grow direction
---@return table anchor
---@return string grow
function Designer.SideAnchor(anchor, side, grow)
	anchor = anchor or { 'CENTER', 'plate', 'CENTER', 0, 0 }
	local target = anchor[2] or 'plate'
	local _, oldH = Split(anchor[1])
	local _, oldRH = Split(anchor[3] or anchor[1])
	local h = (oldH == oldRH) and oldH or 'mid'
	local across = (grow == 'LEFT' or grow == 'RIGHT') and grow or 'RIGHT'
	local x = h == 'mid' and 0 or (anchor[4] or 0)
	if side == 'above' then
		return { PointName('lo', h), target, PointName('hi', h), x, 2 }, across
	elseif side == 'below' then
		return { PointName('hi', h), target, PointName('lo', h), x, -2 }, across
	elseif side == 'left' then
		return { 'RIGHT', target, 'LEFT', -4, 0 }, 'LEFT'
	end
	return { 'LEFT', target, 'RIGHT', 4, 0 }, 'RIGHT'
end

---Which side an anchor puts a row on (for the Side picker).
---@param anchor table|nil
---@return 'above'|'below'|'left'|'right'
function Designer.SideOf(anchor)
	if not anchor then
		return 'above'
	end
	local v, h = Split(anchor[1])
	local rv, rh = Split(anchor[3] or anchor[1])
	if v == 'lo' and rv == 'hi' then
		return 'above'
	elseif v == 'hi' and rv == 'lo' then
		return 'below'
	elseif h == 'hi' and rh == 'lo' then
		return 'left'
	elseif h == 'lo' and rh == 'hi' then
		return 'right'
	end
	return rv == 'lo' and 'below' or 'above'
end

----------------------------------------------------------------------------------------------------
-- History (pure: snapshots in, snapshots out)
----------------------------------------------------------------------------------------------------

---@class Plates.DesignerStep
---@field styleId string
---@field tweaks table|nil Copy of profile.tweaks[styleId] before the edit (nil: no changes)
---@field label? string 'move' | 'nudge' | 'resize' | 'edit' | ...
---@field key? string Coalesce key
---@field time? number

local HistoryMT = {}
HistoryMT.__index = HistoryMT

---A new undo and redo history.
---@param limit? integer Steps kept (default 20)
---@return table history
function Designer.History(limit)
	return setmetatable({ undo = {}, redo = {}, limit = limit or Designer.HISTORY_LIMIT }, HistoryMT)
end

---Record a step. A step with the same key as the last one, within COALESCE seconds, is folded
---into it (the older snapshot is kept). Any new step clears redo.
---@param step Plates.DesignerStep
---@return boolean pushed false when folded into the last step
function HistoryMT:Push(step)
	util.Wipe(self.redo)
	local top = self.undo[#self.undo]
	if top and step.key and top.key == step.key and top.styleId == step.styleId and (step.time or 0) - (top.time or 0) <= Designer.COALESCE then
		top.time = step.time
		return false
	end
	self.undo[#self.undo + 1] = step
	while #self.undo > self.limit do
		table.remove(self.undo, 1)
	end
	return true
end

---Forget the last step (an edit that changed nothing).
function HistoryMT:Drop()
	self.undo[#self.undo] = nil
end

---Take the last step back. current(styleId) returns the state to keep for redo.
---@param current fun(styleId: string): table|nil
---@return Plates.DesignerStep|nil
function HistoryMT:Undo(current)
	local step = table.remove(self.undo)
	if not step then
		return nil
	end
	self.redo[#self.redo + 1] = { styleId = step.styleId, tweaks = current(step.styleId), label = step.label }
	return step
end

---Put back the last undone step.
---@param current fun(styleId: string): table|nil
---@return Plates.DesignerStep|nil
function HistoryMT:Redo(current)
	local step = table.remove(self.redo)
	if not step then
		return nil
	end
	self.undo[#self.undo + 1] = { styleId = step.styleId, tweaks = current(step.styleId), label = step.label }
	while #self.undo > self.limit do
		table.remove(self.undo, 1)
	end
	return step
end

function HistoryMT:CanUndo()
	return #self.undo > 0
end

function HistoryMT:CanRedo()
	return #self.redo > 0
end

function HistoryMT:Clear()
	util.Wipe(self.undo)
	util.Wipe(self.redo)
end

---@return Plates.DesignerStep|nil
function HistoryMT:Last()
	return self.undo[#self.undo]
end

Designer.history = Designer.History()

----------------------------------------------------------------------------------------------------
-- Session state
----------------------------------------------------------------------------------------------------

local function Changed(what)
	P:Fire('DESIGNER_CHANGED', what)
end

local function RefreshOptions()
	if P.Options and P.Options.RequestRefresh then
		P.Options:RequestRefresh(false)
	end
end

---The style the Customize page edits (the profile's style).
---@return string
function Designer:StyleId()
	return P.Styles.Registry:ResolveId(P.Store:Get('style'))
end

---@return string kind
function Designer:PreviewKind()
	return self.state.kind
end

---@param kind string One of Situation.KINDS
function Designer:SetPreviewKind(kind)
	if not Designer.KIND_LABELS[kind] or kind == self.state.kind then
		return
	end
	self.state.kind = kind
	Changed('kind')
	RefreshOptions()
end

---'all' (the whole style) or 'kind' (only the plates shown in the preview).
---@return 'all'|'kind'
function Designer:Scope()
	return self.state.scope
end

---@param scope 'all'|'kind'
function Designer:SetScope(scope)
	scope = scope == 'kind' and 'kind' or 'all'
	if scope ~= self.state.scope then
		self.state.scope = scope
		Changed('scope')
		RefreshOptions()
	end
end

---The situation kind edits go to, or nil for the whole style.
---@return string|nil
function Designer:ScopeKind()
	return self.state.scope == 'kind' and self.state.kind or nil
end

---@param path table|nil
---@return boolean
function Designer:IsCustomizePath(path)
	if type(path) ~= 'table' then
		return false
	end
	local page = (P.Options and P.Options.Path) and P.Options.Path('customize') or { 'Nameplates', 'customize' }
	if #path < #page then
		return false
	end
	for i = 1, #page do
		if path[i] ~= page[i] then
			return false
		end
	end
	return true
end

---Selected part ids (primary first). Read only.
---@return string[]
function Designer:Selected()
	return self.state.selection
end

---@return string|nil
function Designer:Primary()
	return self.state.selection[1]
end

---@param id string
---@return boolean
function Designer:IsSelected(id)
	for _, selected in ipairs(self.state.selection) do
		if selected == id then
			return true
		end
	end
	return false
end

---Select a part. additive adds it to (or takes it out of) the selection (Shift-click).
---@param id string|nil nil clears
---@param additive? boolean
function Designer:Select(id, additive)
	local selection = self.state.selection
	if not id then
		if #selection == 0 then
			return
		end
		util.Wipe(selection)
	elseif additive then
		local found
		for i, selected in ipairs(selection) do
			if selected == id then
				found = i
			end
		end
		if found then
			table.remove(selection, found)
		else
			selection[#selection + 1] = id
		end
	else
		if #selection == 1 and selection[1] == id then
			return
		end
		util.Wipe(selection)
		selection[1] = id
	end
	Changed('select')
	RefreshOptions()
end

function Designer:ClearSelection()
	self:Select(nil)
end

---Drop selected ids the edited style no longer has.
function Designer:ValidateSelection()
	local parts = self:Parts()
	local selection = self.state.selection
	for i = #selection, 1, -1 do
		if not parts[selection[i]] then
			table.remove(selection, i)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Reading the style being edited
----------------------------------------------------------------------------------------------------

---The edited style with the player's overlay (tokens kept) and, for a kind, its situation patches
---(the style's own and the player's). Cached until the style data changes. Read only.
---@param kind? string
---@return { parts: table<string, table>, hidden: table<string, boolean|string>, style: table, base: table }
function Designer:Effective(kind)
	local Styles = P.Styles
	if self.cacheGeneration ~= Styles.Merge.generation then
		util.Wipe(self.cache)
		self.cacheGeneration = Styles.Merge.generation
	end
	local id = self:StyleId()
	local key = id .. '|' .. (kind or '')
	local cached = self.cache[key]
	if cached then
		return cached
	end
	local Registry = Styles.Registry
	local raw = Registry:Get(id) or Registry:Get(Registry.FALLBACK_ID)
	local base = Styles.Schema:Upgrade(raw) or { parts = {} }
	base.parts = base.parts or {}
	local style = Styles.Schema:Upgrade(raw) or { parts = {} }
	local tweaks = P.Store:Get({ 'tweaks', id })
	local overlay = tweaks and Styles.Schema:UpgradeOverlay(tweaks)
	Styles.Merge.ApplyOverlay(style, overlay)
	style.parts = style.parts or {}
	local hidden = {}
	if kind then
		local patch = style.situations and style.situations[kind]
		if patch then
			for _, partId in ipairs(patch.hide or {}) do
				hidden[partId] = 'style'
			end
			for partId, partial in pairs(patch.parts or {}) do
				if style.parts[partId] then
					style.parts[partId] = Styles.Merge.Deep(style.parts[partId], partial)
				end
			end
		end
	end
	for partId, spec in pairs(style.parts) do
		if spec.hidden and not hidden[partId] then
			hidden[partId] = true
		end
	end
	local out = { parts = style.parts, hidden = hidden, style = style, base = base }
	self.cache[key] = out
	return out
end

---Parts of the edited style (whole style, overlay applied). Read only.
---@return table<string, table>
function Designer:Parts()
	return self:Effective(nil).parts
end

---A part's spec as the controls show it: the whole style, or with the preview kind's patches
---while the scope is "only these plates". Read only.
---@param id string
---@return table|nil
function Designer:Spec(id)
	return self:Effective(self:ScopeKind()).parts[id]
end

---@param id string
---@return boolean
function Designer:IsAdded(id)
	return P.Store:Get({ 'tweaks', self:StyleId(), 'add', id }) ~= nil
end

local function GetField(tbl, field)
	local keys = util.SplitPath(field)
	local node = tbl
	for i = 1, #keys do
		if type(node) ~= 'table' then
			return nil
		end
		node = node[keys[i]]
	end
	return node
end
Designer.GetField = GetField

---A field of a part as shown (defaults filled from Merge.PART_DEFAULTS).
---@param id string
---@param field string 'size' or 'font.size'
---@return any
function Designer:Value(id, field)
	local spec = self:Spec(id)
	if not spec then
		return nil
	end
	local value = GetField(spec, field)
	if value == nil then
		value = GetField(P.Styles.Merge.PART_DEFAULTS[spec.kind] or {}, field)
	end
	return value
end

---Where a part field is stored.
---@param id string
---@param field? string
---@param kind? string|false nil follows the scope; false forces the whole style
---@return table path
function Designer:FieldPath(id, field, kind)
	if kind == nil then
		kind = self:ScopeKind()
	end
	local styleId = self:StyleId()
	local path
	if kind then
		path = { 'tweaks', styleId, 'situations', kind, 'parts', id }
	elseif self:IsAdded(id) then
		path = { 'tweaks', styleId, 'add', id }
	else
		path = { 'tweaks', styleId, 'changes', 'parts', id }
	end
	if field then
		for _, key in ipairs(util.SplitPath(field)) do
			path[#path + 1] = key
		end
	end
	return path
end

---Write one field of a part (no undo step; see Change). A value equal to what the layer below
---already has is removed instead, so the overlay holds only real changes.
---@param id string
---@param field string
---@param value any
---@param kind? string|false nil follows the scope; false forces the whole style
function Designer:SetField(id, field, value, kind)
	if kind == nil then
		kind = self:ScopeKind()
	end
	local below
	if kind then
		below = self:Effective(nil).parts[id]
	elseif not self:IsAdded(id) then
		below = self:Effective(nil).base.parts[id]
	end
	if below and value ~= nil then
		local was = GetField(below, field)
		if was == nil and field == 'hidden' then
			was = false
		end
		if util.Equal(was, value) then
			value = nil
		end
	end
	P.Store:Set(self:FieldPath(id, field, kind or false), value)
end

---Change one field as one undo step (repeats with the same key, such as a slider drag, fold).
---@param id string
---@param field string
---@param value any
---@param key? string
function Designer:Change(id, field, value, key)
	self:Edit('edit', function()
		self:SetField(id, field, value)
	end, key or ('field:' .. id .. ':' .. field))
end

---Kinds that have the player's own changes for this part ("Only for these plates").
---@param id string
---@return string[]
function Designer:ScopedKinds(id)
	local out = {}
	local situations = P.Store:Get({ 'tweaks', self:StyleId(), 'situations' })
	for _, kind in ipairs(P.Situation.KINDS) do
		local patch = situations and situations[kind]
		if patch and patch.parts and patch.parts[id] then
			out[#out + 1] = kind
		end
	end
	return out
end

---True when the player changed this part (whole style or any kind).
---@param id string
---@return boolean
function Designer:HasChanges(id)
	if P.Store:Get({ 'tweaks', self:StyleId(), 'changes', 'parts', id }) ~= nil then
		return true
	end
	return #self:ScopedKinds(id) > 0
end

----------------------------------------------------------------------------------------------------
-- Edits
----------------------------------------------------------------------------------------------------

---Run an edit as one undo step. fn writes through P.Store (in one Store batch).
---@param label string
---@param fn fun()
---@param key? string Folds repeated edits with the same key into one step
---@return boolean changed
function Designer:Edit(label, fn, key)
	local styleId = self:StyleId()
	local before = util.Copy(P.Store:Get({ 'tweaks', styleId }))
	local pushed = self.history:Push({ styleId = styleId, tweaks = before, label = label, key = key, time = Now() })
	local ok, err = pcall(P.Store.Batch, P.Store, fn)
	local changed = not util.Equal(before, P.Store:Get({ 'tweaks', styleId }))
	if pushed and not changed then
		self.history:Drop()
	end
	if not ok then
		P.log.error('Nameplate designer edit failed: ' .. tostring(err))
	end
	Changed('history')
	return changed
end

local function Current(styleId)
	return util.Copy(P.Store:Get({ 'tweaks', styleId }))
end

---@return boolean
function Designer:CanUndo()
	return self.history:CanUndo()
end

---@return boolean
function Designer:CanRedo()
	return self.history:CanRedo()
end

---Take back the last designer or Customize page edit.
---@return boolean done
function Designer:Undo()
	local step = self.history:Undo(Current)
	if not step then
		return false
	end
	P.Store:Set({ 'tweaks', step.styleId }, step.tweaks)
	self:ValidateSelection()
	Changed('history')
	return true
end

---Put back the last undone edit.
---@return boolean done
function Designer:Redo()
	local step = self.history:Redo(Current)
	if not step then
		return false
	end
	P.Store:Set({ 'tweaks', step.styleId }, step.tweaks)
	self:ValidateSelection()
	Changed('history')
	return true
end

---Show or hide a part (the eye; Delete).
---@param id string
---@param hidden boolean
function Designer:SetHidden(id, hidden)
	self:Edit('hide', function()
		self:SetField(id, 'hidden', hidden and true or false)
	end)
end

---Switch a sub row (Absorbs, Spell icon, Spell name, Cast target) of a part.
---@param id string
---@param key string Sub row key
---@param on boolean
function Designer:SetSubRow(id, key, on)
	local spec = self:Spec(id)
	if not spec then
		return
	end
	for _, row in ipairs(Designer.SUB_ROWS[spec.kind] or {}) do
		if row.key == key then
			local fields = row.set(on, spec, self:Effective(nil).base.parts[id])
			self:Edit('edit', function()
				for field, value in pairs(fields) do
					self:SetField(id, field, value)
				end
			end)
		end
	end
end

---Move parts' anchor offsets by dx, dy (nudges; repeats fold into one undo step).
---@param ids string[]
---@param dx number
---@param dy number
function Designer:NudgeParts(ids, dx, dy)
	local parts = self:Effective(self:ScopeKind()).parts
	local roots = Designer.Roots(parts, ids)
	if #roots == 0 then
		return
	end
	local anchors = {}
	for _, id in ipairs(roots) do
		local anchor = util.Copy(parts[id].anchor) or { 'CENTER', 'plate', 'CENTER', 0, 0 }
		anchor[4] = Half((anchor[4] or 0) + dx)
		anchor[5] = Half((anchor[5] or 0) + dy)
		anchors[id] = anchor
	end
	self:Edit('nudge', function()
		for _, id in ipairs(roots) do
			self:SetField(id, 'anchor', anchors[id])
		end
	end, 'nudge:' .. table.concat(roots, ','))
end

---@param id string
---@param dx number
---@param dy number
function Designer:NudgePart(id, dx, dy)
	self:NudgeParts({ id }, dx, dy)
end

---Pick a cell on the anchor grid for a part.
---@param id string
---@param cell string
function Designer:SetGridCell(id, cell)
	local spec = self:Spec(id)
	if not spec then
		return
	end
	local anchor = Designer.GridAnchor(spec.anchor, cell)
	self:Edit('move', function()
		self:SetField(id, 'anchor', anchor)
	end)
end

---Put a part's offset back to zero (the anchor grid's middle button).
---@param id string
function Designer:ResetOffset(id)
	local spec = self:Spec(id)
	if not (spec and spec.anchor) then
		return
	end
	local anchor = util.Copy(spec.anchor)
	anchor[4], anchor[5] = 0, 0
	self:Edit('move', function()
		self:SetField(id, 'anchor', anchor)
	end)
end

---Hang a part from another part (or the plate) without moving it on screen.
---@param id string
---@param targetId string
function Designer:SetTarget(id, targetId)
	local spec = self:Spec(id)
	if not spec then
		return
	end
	local resolved = P.Styles.Merge:Resolve(self:StyleId(), self:PreviewKind(), P.Store:Get('size'))
	local rects = P.Styles.Merge.PartRects(resolved)
	local rect = rects[id]
	if not rect then
		return
	end
	local targets = { [targetId] = rects[targetId] or rects.plate }
	local anchor = Designer.DropAnchor(rect, targets, targetId)
	self:Edit('move', function()
		self:SetField(id, 'anchor', anchor)
	end)
end

---Part ids a part may hang from (not itself, nothing hanging from it, no glows or highlights).
---@param id string
---@return string[]
function Designer:TargetChoices(id)
	local parts = self:Effective(self:ScopeKind()).parts
	local below = Designer.Descendants(parts, id)
	local out = {}
	for partId, spec in pairs(parts) do
		if not below[partId] and spec.kind ~= 'glow' and spec.kind ~= 'highlight' and spec.kind ~= 'region' then
			out[#out + 1] = partId
		end
	end
	table.sort(out)
	return out
end

---Back to the style's own settings for this part: every change, or only one kind's.
---@param id string
---@param kind? string
function Designer:ResetPart(id, kind)
	local styleId = self:StyleId()
	self:Edit('reset', function()
		if kind then
			P.Store:Set({ 'tweaks', styleId, 'situations', kind, 'parts', id }, nil)
		else
			P.Store:Set({ 'tweaks', styleId, 'changes', 'parts', id }, nil)
			for _, k in ipairs(P.Situation.KINDS) do
				P.Store:Set({ 'tweaks', styleId, 'situations', k, 'parts', id }, nil)
			end
		end
	end)
end

---Add a part from the palette and select it.
---@param kind string Palette value
---@return string|nil id
function Designer:AddPart(kind)
	local parts = self:Parts()
	local resolved = P.Styles.Merge:Resolve(self:StyleId(), self:PreviewKind(), P.Store:Get('size'))
	local id, spec = Designer.NewPart(kind, parts, resolved and resolved.width, resolved and resolved.height)
	if not id then
		return nil
	end
	local styleId = self:StyleId()
	self:Edit('add', function()
		P.Store:Set({ 'tweaks', styleId, 'add', id }, spec)
	end)
	self:Select(id)
	return id
end

---Remove a part the player added (a style's own parts are hidden instead). Parts hanging from it
---hang from what it hung from.
---@param id string
function Designer:RemovePart(id)
	if not self:IsAdded(id) then
		self:SetHidden(id, true)
		return
	end
	local styleId = self:StyleId()
	local parts = self:Parts()
	local gone = parts[id]
	local through = (gone and gone.anchor) or { 'CENTER', 'plate', 'CENTER', 0, 0 }
	self:Edit('remove', function()
		for partId, spec in pairs(parts) do
			local anchor = spec.anchor
			if partId ~= id and anchor and anchor[2] == id then
				self:SetField(partId, 'anchor', { anchor[1], through[2], through[3], Half((anchor[4] or 0) + (through[4] or 0)), Half((anchor[5] or 0) + (through[5] or 0)) }, false)
			end
		end
		P.Store:Set({ 'tweaks', styleId, 'add', id }, nil)
		P.Store:Set({ 'tweaks', styleId, 'changes', 'parts', id }, nil)
		for _, k in ipairs(P.Situation.KINDS) do
			P.Store:Set({ 'tweaks', styleId, 'situations', k, 'parts', id }, nil)
		end
	end)
	self:ValidateSelection()
	Changed('select')
	RefreshOptions()
end

---Hide every selected part (Delete).
function Designer:HideSelected()
	local ids = util.Copy(self.state.selection)
	if #ids == 0 then
		return
	end
	self:Edit('hide', function()
		for _, id in ipairs(ids) do
			self:SetField(id, 'hidden', true)
		end
	end)
end

---Keys the panel passes on while a part is selected. Returns true when used.
---@param name string 'DELETE', 'CTRL-Z', 'CTRL-SHIFT-Z', 'CTRL-Y', ...
---@return boolean
function Designer:HandleKey(name)
	if name == 'DELETE' or name == 'BACKSPACE' then
		self:HideSelected()
		return true
	elseif name == 'CTRL-Z' or name == 'META-Z' then
		self:Undo()
		return true
	elseif name == 'CTRL-Y' or name == 'CTRL-SHIFT-Z' or name == 'META-SHIFT-Z' then
		self:Redo()
		return true
	end
	return false
end

----------------------------------------------------------------------------------------------------
-- Drawing in the preview panel
----------------------------------------------------------------------------------------------------

local WHITE = 'Interface\\Buttons\\WHITE8X8'
local chrome = setmetatable({}, { __mode = 'k' }) -- plate -> { guides, handle }

local function Chrome(plate)
	local c = chrome[plate]
	if not c then
		c = { guides = {} }
		chrome[plate] = c
	end
	return c
end

local function AccentColor()
	local services = P.services
	if services and services.GetAccent then
		local ok, r, g, b = pcall(services.GetAccent)
		if ok and type(r) == 'number' then
			return r, g, b
		end
	end
	return 1, 0.82, 0
end

local function HideGuides(plate)
	local c = plate and chrome[plate]
	if not c then
		return
	end
	for _, line in ipairs(c.guides) do
		line:Hide()
	end
end

local function ShowGuide(plate, index, vertical, value, rect)
	local c = Chrome(plate)
	local line = c.guides[index]
	if not line then
		line = plate.art:CreateTexture(nil, 'OVERLAY', nil, 7)
		line:SetTexture(WHITE)
		c.guides[index] = line
	end
	local r, g, b = AccentColor()
	line:SetVertexColor(r, g, b, 0.85)
	local px = 1
	local scale = plate.art:GetEffectiveScale()
	if type(scale) == 'number' and scale > 0 and UIParent then
		px = UIParent:GetEffectiveScale() / scale
	end
	line:ClearAllPoints()
	if vertical then
		line:SetSize(px, (rect.top - rect.bottom) + 24)
		line:SetPoint('CENTER', plate.art, 'CENTER', value, (rect.top + rect.bottom) / 2)
	else
		line:SetSize((rect.right - rect.left) + 24, px)
		line:SetPoint('CENTER', plate.art, 'CENTER', (rect.left + rect.right) / 2, value)
	end
	line:Show()
end

local function WidgetFor(plate, id)
	return plate and plate.GetWidget and plate:GetWidget(id) or nil
end

local function SavePoints(frame)
	local points = {}
	for i = 1, (frame:GetNumPoints() or 0) do
		local point, relativeTo, relPoint, x, y = frame:GetPoint(i)
		points[#points + 1] = { point, relativeTo, relPoint, x or 0, y or 0 }
	end
	return points
end

local function ApplyPoints(frame, points, dx, dy)
	frame:ClearAllPoints()
	for _, p in ipairs(points) do
		frame:SetPoint(p[1], p[2], p[3], p[4] + dx, p[5] + dy)
	end
end

local function Tolerance(frame)
	local scale = frame and frame:GetEffectiveScale()
	local base = UIParent and UIParent:GetEffectiveScale() or 1
	if type(scale) ~= 'number' or scale <= 0 then
		return Designer.SNAP_SCREEN
	end
	return Designer.SNAP_SCREEN * base / scale
end

---Start moving the selection (Stage drag Start).
---@param id string The part under the cursor
function Designer:BeginDrag(id)
	local attached = self.attached
	local plate = attached and attached.plate
	if not (plate and plate.style) then
		return
	end
	if not self:IsSelected(id) then
		self:Select(id)
	end
	local resolved = plate.style
	local rects = P.Styles.Merge.PartRects(resolved)
	local roots = Designer.Roots(resolved.parts, self.state.selection)
	local drag = { plate = plate, rects = rects, roots = {}, dx = 0, dy = 0 }
	for _, rootId in ipairs(roots) do
		local widget = WidgetFor(plate, rootId)
		if widget and widget.frame and rects[rootId] then
			drag.roots[#drag.roots + 1] = { id = rootId, frame = widget.frame, points = SavePoints(widget.frame), rect = rects[rootId] }
		end
	end
	drag.lead = drag.roots[1]
	for _, root in ipairs(drag.roots) do
		if root.id == id then
			drag.lead = root
		end
	end
	drag.guides = Designer.Guides(rects.plate)
	drag.tolerance = Tolerance(drag.lead and drag.lead.frame)
	self.drag = drag
end

---Follow the cursor (Stage drag Move). dx, dy are plate pixels since the drag started.
---@param dx number
---@param dy number
function Designer:DragTo(dx, dy)
	local drag = self.drag
	if not (drag and drag.lead) then
		return
	end
	drag.rawX, drag.rawY = dx, dy
	local sx, sy, lineX, lineY = 0, 0, nil, nil
	-- No snapping until the part has really moved, so a click on a part near an edge stays put
	if math.abs(dx) >= drag.tolerance or math.abs(dy) >= drag.tolerance then
		sx, sy, lineX, lineY = Designer.Snap(Designer.MoveRect(drag.lead.rect, dx, dy), drag.guides, drag.tolerance)
	end
	dx, dy = dx + sx, dy + sy
	drag.dx, drag.dy = dx, dy
	for _, root in ipairs(drag.roots) do
		ApplyPoints(root.frame, root.points, dx, dy)
	end
	HideGuides(drag.plate)
	if lineX then
		ShowGuide(drag.plate, 1, true, lineX, drag.rects.plate)
	end
	if lineY then
		ShowGuide(drag.plate, 2, false, lineY, drag.rects.plate)
	end
end

---Drop the selection (Stage drag Stop): pick each moved part's anchor and write it.
---@return boolean changed
function Designer:EndDrag()
	local drag = self.drag
	self.drag = nil
	if not drag then
		return false
	end
	HideGuides(drag.plate)
	local dx, dy = drag.dx, drag.dy
	local rawX, rawY = drag.rawX or 0, drag.rawY or 0
	local changed = false
	if math.abs(rawX) >= 0.25 or math.abs(rawY) >= 0.25 then
		local parts = drag.plate.style.parts
		local anchors = {}
		for _, root in ipairs(drag.roots) do
			local below = Designer.Descendants(parts, root.id)
			local targets = {}
			for targetId, rect in pairs(drag.rects) do
				local spec = parts[targetId]
				local usable = targetId == 'plate' or (spec and spec.kind ~= 'glow' and spec.kind ~= 'highlight' and spec.kind ~= 'region')
				if usable and not below[targetId] then
					targets[targetId] = rect
				end
			end
			local current = parts[root.id].anchor
			anchors[root.id] = Designer.DropAnchor(Designer.MoveRect(root.rect, dx, dy), targets, current and current[2])
		end
		changed = self:Edit('move', function()
			for _, root in ipairs(drag.roots) do
				self:SetField(root.id, 'anchor', anchors[root.id])
			end
		end)
	end
	if not changed then
		for _, root in ipairs(drag.roots) do
			ApplyPoints(root.frame, root.points, 0, 0)
		end
	end
	return changed
end

---Start resizing the primary part (Stage drag Start on the handle).
function Designer:BeginResize()
	local attached = self.attached
	local plate = attached and attached.plate
	local id = self:Primary()
	local widget = id and WidgetFor(plate, id)
	if not (widget and widget.frame and plate.style and plate.style.parts[id]) then
		return
	end
	local rect = P.Styles.Merge.PartRects(plate.style)[id]
	if not rect then
		return
	end
	local fw, fh = widget.frame:GetSize()
	self.resize = { id = id, plate = plate, frame = widget.frame, w = rect.right - rect.left, h = rect.top - rect.bottom, fw = fw, fh = fh, spec = plate.style.parts[id], dx = 0, dy = 0 }
end

---@param dx number
---@param dy number
function Designer:ResizeTo(dx, dy)
	local resize = self.resize
	if not resize then
		return
	end
	resize.dx, resize.dy = dx, dy
	resize.frame:SetSize(math.max(1, (resize.fw or resize.w) + dx), math.max(1, (resize.fh or resize.h) - dy))
end

---@return boolean changed
function Designer:EndResize()
	local resize = self.resize
	self.resize = nil
	if not resize then
		return false
	end
	local dx, dy = resize.dx, resize.dy
	local changed = false
	if math.abs(dx) >= 0.5 or math.abs(dy) >= 0.5 then
		local fields = Designer.ResizeFields(resize.spec, resize.w + dx, resize.h - dy)
		changed = self:Edit('resize', function()
			for field, value in pairs(fields) do
				self:SetField(resize.id, field, value)
			end
		end)
	end
	if not changed and resize.fw then
		resize.frame:SetSize(resize.fw, resize.fh)
	end
	return changed
end

local function Area(rect)
	if not rect then
		return 0
	end
	return (rect.right - rect.left) * (rect.top - rect.bottom)
end

local RANK = { region = 0, glow = 1, highlight = 1 }

local function FrameArea(frame, rect)
	local ok, w, h = pcall(frame.GetSize, frame)
	if ok and type(w) == 'number' and type(h) == 'number' and w > 0 and h > 0 then
		return w * h
	end
	return Area(rect)
end

local JUSTIFY_POINT = { LEFT = 'LEFT', CENTER = 'CENTER', RIGHT = 'RIGHT' }

---What a click on a part hits. A text part's holder is as wide as the plate, so it gets a box the
---size of its words instead (an invisible texture), or it would cover the bar under it.
---@param plate table
---@param widget table
---@param spec table
---@return table frame
---@return number area
local function HitFrame(plate, widget, spec, rect)
	local frame = widget.frame
	if spec.kind ~= 'text' then
		return frame, FrameArea(frame, rect)
	end
	local c = Chrome(plate)
	c.textBoxes = c.textBoxes or {}
	local box = c.textBoxes[widget]
	if not box then
		box = frame:CreateTexture(nil, 'BACKGROUND')
		box:SetTexture(WHITE)
		box:SetVertexColor(0, 0, 0, 0)
		c.textBoxes[widget] = box
	end
	local okSize, holderW, holderH = pcall(frame.GetSize, frame)
	if not (okSize and type(holderW) == 'number' and holderW > 0) then
		holderW, holderH = rect and (rect.right - rect.left) or 40, rect and (rect.top - rect.bottom) or 12
	end
	local source = widget.text
	if spec.source == 'nameFill' and widget.fill and widget.fill.fg then
		source = widget.fill.fg
	end
	local textW = 0
	if source and source.GetStringWidth then
		local ok, w = pcall(source.GetStringWidth, source)
		if ok and type(w) == 'number' then
			textW = w
		end
	end
	if textW <= 0 then
		textW = holderW
	end
	local w = math.max(8, math.min(holderW, textW + 4))
	local point = JUSTIFY_POINT[spec.justify or 'CENTER'] or 'CENTER'
	box:ClearAllPoints()
	box:SetSize(w, holderH)
	box:SetPoint(point, frame, point, 0, 0)
	box:Show()
	return box, w * holderH
end

---A tooltip line for a part: why its color, or why it may stay empty on this client.
---@param id string
---@param plate table
---@return string|nil
function Designer:Detail(id, plate)
	local spec = plate and plate.style and plate.style.parts[id]
	if not spec then
		return nil
	end
	local lines = {}
	local piece = spec.colors
	if piece and P.Inspector and plate.env then
		local ok, text = pcall(P.Inspector.Explain, P.Inspector, plate, piece)
		if ok and type(text) == 'string' and text ~= '' then
			lines[#lines + 1] = text
		end
	end
	local limit
	if spec.kind == 'text' and P.TextParts and P.TextParts.Limit then
		limit = P.TextParts.Limit(spec.source)
	elseif spec.kind == 'icon' and P.IconParts and P.IconParts.Limit then
		limit = P.IconParts.Limit(spec.source)
	elseif spec.kind == 'glow' and P.GlowLib and P.GlowLib.Limit then
		limit = P.GlowLib.Limit(spec.source)
	end
	if type(limit) == 'string' and limit ~= '' then
		lines[#lines + 1] = limit
	end
	if #lines == 0 then
		return nil
	end
	return table.concat(lines, '\n')
end

---Register the parts of the Customize plate as Stage regions (see the file header).
---@param ctx table Stage context (ctx.Region, ctx.canvas)
---@param plate table The large preview plate, laid out and filled
function Designer:Attach(ctx, plate)
	if not (ctx and ctx.Region and plate and plate.style) then
		return
	end
	self.attached = { ctx = ctx, plate = plate }
	self:ValidateSelection()
	local resolved = plate.style
	local rects = P.Styles.Merge.PartRects(resolved)
	local items = {}
	for i = 1, #plate.active do
		local widget = plate.active[i]
		local spec = resolved.parts[widget.id]
		local frame = widget.frame
		if spec and frame and frame:IsShown() then
			local hit, area = HitFrame(plate, widget, spec, rects[widget.id])
			items[#items + 1] = { id = widget.id, frame = hit, spec = spec, rank = RANK[spec.kind] or 2, area = area }
		end
	end
	table.sort(items, function(a, b)
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		if a.area ~= b.area then
			return a.area > b.area
		end
		return a.id < b.id
	end)
	local designer = self
	local page = (P.Options and P.Options.Path) and P.Options.Path('customize') or nil
	local function Nudge(dx, dy)
		designer:NudgeParts(designer.state.selection, dx, dy)
	end
	local function Key(name)
		return designer:HandleKey(name)
	end
	for _, item in ipairs(items) do
		local id, spec = item.id, item.spec
		local group, label = Designer.PartInfo(id, spec)
		-- The click selects the part, then the Stage opens the Customize page at its settings
		local target = {
			label = label,
			group = group,
			partId = id,
			path = page,
			option = 'part_' .. id,
			selected = self:IsSelected(id),
			detail = function()
				return designer:Detail(id, plate)
			end,
			onClick = function()
				designer:Select(id, (IsShiftKeyDown and IsShiftKeyDown()) and true or false)
				return nil
			end,
		}
		if Designer.Movable(spec) then
			target.drag = {
				Start = function()
					designer:BeginDrag(id)
				end,
				Move = function(dx, dy)
					designer:DragTo(dx, dy)
				end,
				Stop = function()
					designer:EndDrag()
				end,
				Nudge = Nudge,
				Key = Key,
			}
		end
		ctx.Region(item.frame, target)
	end
	self:AttachHandle(ctx, plate, Nudge, Key)
end

---The resize handle on the primary part's bottom right corner (Phase 7).
---@param ctx table
---@param plate table
---@param nudge fun(dx: number, dy: number)
---@param key fun(name: string): boolean
function Designer:AttachHandle(ctx, plate, nudge, key)
	local c = Chrome(plate)
	local handle = c.handle
	local id = self:Primary()
	local spec = id and plate.style.parts[id]
	local widget = id and WidgetFor(plate, id)
	if not (spec and widget and widget.frame and widget.frame:IsShown() and Designer.Resizable(spec) and #self.state.selection == 1) then
		if handle then
			handle:Hide()
		end
		return
	end
	if not handle then
		handle = plate.art:CreateTexture(nil, 'OVERLAY', nil, 7)
		handle:SetTexture(WHITE)
		c.handle = handle
	end
	local r, g, b = AccentColor()
	handle:SetVertexColor(r, g, b, 1)
	local size = Designer.HANDLE_SCREEN
	local art = plate.art:GetEffectiveScale()
	local canvas = ctx.canvas and ctx.canvas:GetEffectiveScale()
	if type(art) == 'number' and art > 0 and type(canvas) == 'number' and canvas > 0 then
		size = Designer.HANDLE_SCREEN * canvas / art
	end
	handle:SetSize(size, size)
	handle:ClearAllPoints()
	handle:SetPoint('CENTER', widget.frame, 'BOTTOMRIGHT', 0, 0)
	handle:Show()
	local designer = self
	ctx.Region(handle, {
		label = L['Resize'],
		detail = L['Drag the corner to change its size.'],
		selected = true,
		drag = {
			Start = function()
				designer:BeginResize()
			end,
			Move = function(dx, dy)
				designer:ResizeTo(dx, dy)
			end,
			Stop = function()
				designer:EndResize()
			end,
			Nudge = nudge,
			Key = key,
		},
	})
end

---Forget the drawn plate (provider Hide and Close).
function Designer:Detach()
	local attached = self.attached
	self.attached = nil
	self.drag, self.resize = nil, nil
	local plate = attached and attached.plate
	if plate then
		HideGuides(plate)
		local c = chrome[plate]
		if c and c.handle then
			c.handle:Hide()
		end
	end
end

---Panel title on the Customize page: the selected part's group and name.
---@return string|nil
function Designer:Title()
	local id = self:Primary()
	local spec = id and self:Parts()[id]
	if not spec then
		return nil
	end
	local group, label = Designer.PartInfo(id, spec)
	local count = #self.state.selection
	if count > 1 then
		return string.format(L['%s and %d more'], label, count - 1)
	end
	return (Designer.GROUP_LABELS[group] or '') .. ': ' .. label
end

---Panel hint on the Customize page.
---@return string
function Designer:Hint()
	if not self:Primary() then
		return L['Click a part to change it. Shift-click picks more than one.']
	end
	return L['Drag to move. Arrow keys nudge, Delete hides, Ctrl-Z undoes.']
end

---"Undo move" at the bottom of the panel while there is something to undo.
---@return table|nil
function Designer:Footer()
	local last = self.history:Last()
	if not last then
		return nil
	end
	local designer = self
	local moved = last.label == 'move' or last.label == 'nudge' or last.label == 'resize'
	return {
		text = moved and L['Undo move'] or L['Undo'],
		tooltip = L['Ctrl-Z also undoes. Ctrl-Y brings it back.'],
		func = function()
			designer:Undo()
		end,
	}
end

---Toolbar items for the Customize page: the part palette and Redo.
---@return table[]
function Designer:ToolbarItems()
	local designer = self
	local items = {
		{
			kind = 'select',
			label = L['Add'],
			text = L['Add a part'],
			choices = Designer.PALETTE,
			tooltip = L['Add a new part to this style. It is picked right away so you can move it.'],
			onSelect = function(value)
				designer:AddPart(value)
			end,
			align = 'right',
		},
	}
	if self.history:CanRedo() then
		items[#items + 1] = {
			kind = 'button',
			text = L['Redo'],
			tooltip = L['Bring back what you undid.'],
			onClick = function()
				designer:Redo()
			end,
			align = 'right',
		}
	end
	return items
end

-- A profile switch means other overlays: start a fresh history and selection
P:On('PROFILE_CHANGED', function()
	Designer.history:Clear()
	util.Wipe(Designer.state.selection)
	util.Wipe(Designer.cache)
end, Designer)
