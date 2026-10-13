local _, ns = ...
local P = ns.Plates
local util = P.util

-- Builds the style a plate actually uses (5.2), from these layers, each overriding the last:
--   1. base       Registry style (built-in, host or saved)
--   2. host look  every '$host' token resolves to the host's value (P.hostLook), else a fallback
--   3. overlay    profile.tweaks[styleId] = { schema, baseVersion, changes, add, remove, situations }
--   4. situation  style.situations[kind], then tweaks.situations[kind] ("Only for these plates")
-- Runtime states (target, focus, mouseover, casting, notTarget) are not merged here: the Plate
-- applies style.states on top at runtime.
--
-- Rules: tables merge by key, lists (anchors, sizes, colors, hide lists) are replaced whole; a part
-- that is removed or hidden hands its anchor to anything anchored to it, so nothing is orphaned;
-- tokens are resolved to plain values; the result is cached until a change message says the look
-- may differ. Resolved styles are read-only for every caller.

---@class Plates.ResolvedStyle
---@field key string Changes whenever the layout may differ; a Plate re-lays out only then
---@field id string
---@field name string
---@field situation string
---@field sizeKey string
---@field width integer Plate width in whole pixels
---@field height integer Plate height in whole pixels
---@field tokens table<string, any> Resolved token values
---@field parts table<string, table> Resolved part specs (defaults filled, tokens resolved)
---@field order string[] Part ids to lay out, anchor targets first, then by `order`
---@field hidden table<string, boolean> Parts that exist in the style but are hidden here
---@field states table Runtime state adjustments (grow, alpha)
---@field regions { click: Plates.Rect, stack: Plates.Rect }

---@class Plates.Rect Offsets from the plate center in pixels (left and bottom are negative)
---@field left number
---@field right number
---@field top number
---@field bottom number

---@class Plates.Merge
local Merge = { cache = {}, generation = 0 }
P.Styles.Merge = Merge

---Defaults filled into every part of a kind before the part's own fields.
Merge.PART_DEFAULTS = {
	bar = { texture = '$bar', bg = '$shade', border = { kind = 'pixel', size = 1, color = '$ink' }, interpolate = true, alpha = 1 },
	cast = {
		height = 8,
		icon = 'left',
		texture = '$bar',
		bg = '$shade',
		border = { kind = 'pixel', size = 1, color = '$ink' },
		colors = 'cast',
		font = { face = '$font', size = 9, flags = 'OUTLINE' },
		nameText = true,
		timeText = true,
		timeFormat = 'remaining',
		enemies = true,
		friends = false,
		kickMark = true,
		kickFill = false,
		interrupter = true,
		alpha = 1,
	},
	text = { font = { face = '$font', size = 10, flags = 'OUTLINE' }, justify = 'CENTER', alpha = 1 },
	icon = { size = 16, alpha = 1 },
	auras = {
		size = 20,
		max = 6,
		grow = 'RIGHT',
		spacing = 2,
		timer = true,
		stacks = true,
		borderStyle = 'pixel',
		sort = 'default',
		font = { face = '$font', size = 9, flags = 'OUTLINE' },
		alpha = 1,
		timerAnchor = { point = 'CENTER', relPoint = 'CENTER', x = 0, y = 0 },
		stackAnchor = { point = 'BOTTOMRIGHT', relPoint = 'BOTTOMRIGHT', x = 1, y = 0 },
	},
	highlight = { art = 'arrows', color = '$accent', pad = 2, blend = 'BLEND', alpha = 1 },
	glow = { size = 4, color = '$accent', alpha = 1 },
	art = { color = { 1, 1, 1, 1 }, alpha = 1 },
	region = {},
	classPower = { size = 6, spacing = 2, alpha = 1 },
}

---Token fallbacks when neither the style nor the host supplies a value.
Merge.TOKEN_FALLBACK = {
	accent = function()
		local r, g, b = P.services.GetAccent()
		return { r, g, b, 1 }
	end,
	font = function()
		return P.services.FontPath()
	end,
	bar = function()
		return 'Nameplates Flat'
	end,
	ink = function()
		return { 0, 0, 0, 1 }
	end,
	shade = function()
		return { 0, 0, 0, 0.6 }
	end,
}

Merge.DEFAULT_SIZES = { small = { 112, 8 }, medium = { 132, 10 }, large = { 156, 12 } }

---Part kinds that make up the click and stacking areas when they are worked out automatically.
Merge.REGION_KINDS = { bar = true, cast = true }
Merge.REGION_TEXT_SOURCES = { name = true, nameFill = true }

----------------------------------------------------------------------------------------------------
-- Pure helpers
----------------------------------------------------------------------------------------------------

---Deep merge `over` into a copy of `base`: tables merge by key, lists and scalars replace.
---@param base table|nil
---@param over table|nil
---@return table
function Merge.Deep(base, over)
	local out = util.Copy(base) or {}
	if type(over) ~= 'table' then
		return out
	end
	for key, value in pairs(over) do
		if type(value) == 'table' and not util.IsList(value) and type(out[key]) == 'table' and not util.IsList(out[key]) then
			out[key] = Merge.Deep(out[key], value)
		else
			out[key] = util.Copy(value)
		end
	end
	return out
end

---Apply an overlay to a style copy (no situation, tokens kept). Used by Resolve and "Make a copy".
---@param style table
---@param overlay table|nil
---@return table style The same table, changed
function Merge.ApplyOverlay(style, overlay)
	if type(overlay) ~= 'table' then
		return style
	end
	style.parts = style.parts or {}
	for id in pairs(overlay.remove or {}) do
		style.parts[id] = nil
	end
	for id, part in pairs(overlay.add or {}) do
		style.parts[id] = util.Copy(part)
	end
	local changes = overlay.changes or {}
	for id, partial in pairs(changes.parts or {}) do
		if style.parts[id] then
			style.parts[id] = Merge.Deep(style.parts[id], partial)
		end
	end
	if changes.plate then
		style.plate = Merge.Deep(style.plate, changes.plate)
	end
	if changes.states then
		style.states = Merge.Deep(style.states, changes.states)
	end
	if changes.tokens then
		style.tokens = Merge.Deep(style.tokens, changes.tokens)
	end
	if changes.regions then
		style.regions = Merge.Deep(style.regions, changes.regions)
	end
	if overlay.situations then
		style.situations = style.situations or {}
		for situation, patch in pairs(overlay.situations) do
			local mine = style.situations[situation] or {}
			local merged = Merge.Deep(mine, patch)
			-- hide lists add up instead of replacing each other
			if mine.hide or patch.hide then
				local hide, seen = {}, {}
				for _, list in ipairs({ mine.hide or {}, patch.hide or {} }) do
					for _, id in ipairs(list) do
						if not seen[id] then
							seen[id] = true
							hide[#hide + 1] = id
						end
					end
				end
				merged.hide = hide
			end
			style.situations[situation] = merged
		end
	end
	return style
end

local function TokenValue(name, tokens, hostLook, depth)
	if depth > 4 then
		return nil
	end
	local value = tokens and tokens[name]
	if value == nil or value == '$host' then
		local fromHost
		if hostLook then
			fromHost = hostLook.tokens and hostLook.tokens[name]
			if fromHost == nil and name == 'font' then
				fromHost = hostLook.font
			elseif fromHost == nil and name == 'accent' then
				fromHost = hostLook.accent
			end
		end
		if fromHost ~= nil then
			return util.Copy(fromHost)
		end
		local fallback = Merge.TOKEN_FALLBACK[name]
		return fallback and fallback() or nil
	end
	if type(value) == 'string' and string.sub(value, 1, 1) == '$' then
		return TokenValue(string.sub(value, 2), tokens, hostLook, depth + 1)
	end
	return util.Copy(value)
end

local function ResolveTokens(value, tokens, hostLook)
	if type(value) == 'string' and string.sub(value, 1, 1) == '$' then
		return TokenValue(string.sub(value, 2), tokens, hostLook, 0)
	end
	if type(value) == 'table' then
		local out = {}
		for k, v in pairs(value) do
			out[k] = ResolveTokens(v, tokens, hostLook)
		end
		return out
	end
	return value
end
Merge.ResolveTokens = ResolveTokens

---Icon-relative text positions. An omitted size follows the row font, including old styles.
function Merge.AuraText(spec, field)
	local defaults = Merge.PART_DEFAULTS.auras[field]
	local anchor = spec[field] or {}
	return {
		point = anchor.point or defaults.point,
		relPoint = anchor.relPoint or defaults.relPoint,
		x = anchor.x or defaults.x,
		y = anchor.y or defaults.y,
		size = anchor.size or (spec.font and spec.font.size) or Merge.PART_DEFAULTS.auras.font.size,
	}
end

function Merge.AuraTextFont(spec, field)
	local font = Merge.Deep(Merge.PART_DEFAULTS.auras.font, spec.font)
	font.size = Merge.AuraText(spec, field).size
	return font
end

local PX = { TOPLEFT = -1, TOP = 0, TOPRIGHT = 1, LEFT = -1, CENTER = 0, RIGHT = 1, BOTTOMLEFT = -1, BOTTOM = 0, BOTTOMRIGHT = 1 }
local PY = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 0, CENTER = 0, RIGHT = 0, BOTTOMLEFT = -1, BOTTOM = -1, BOTTOMRIGHT = -1 }

---Approximate size of a part in pixels (text width follows the plate, height the font).
---@param spec table
---@param W number
---@param H number
---@return number w
---@return number h
function Merge.PartSize(spec, W, H)
	local kind = spec.kind
	if kind == 'bar' then
		if spec.fill == 'plate' then
			return W, H
		end
		return spec.width or W, spec.height or H
	elseif kind == 'cast' then
		return spec.width or W, spec.height or 8
	elseif kind == 'text' then
		local width = (spec.width and spec.width > 0) and spec.width or W
		return width, ((spec.font and spec.font.size) or 10) + 2
	elseif kind == 'icon' then
		return spec.size or 16, spec.size or 16
	elseif kind == 'auras' then
		local count = math.min(spec.max or 6, spec.perRow or spec.max or 6)
		local long = count * (spec.size or 20) + math.max(count - 1, 0) * (spec.spacing or 2)
		if spec.grow == 'UP' or spec.grow == 'DOWN' then
			return spec.size or 20, long
		end
		return long, spec.size or 20
	elseif kind == 'region' or kind == 'art' then
		return spec.width or W, spec.height or H
	elseif kind == 'classPower' then
		return W, spec.size or 6
	end
	return W, H
end

---Rectangles of every laid-out part, relative to the plate center (pure geometry).
---@param resolved table Needs parts, order, width, height
---@return table<string, Plates.Rect>
function Merge.PartRects(resolved)
	local W, H = resolved.width, resolved.height
	local rects = { plate = { left = -W / 2, right = W / 2, top = H / 2, bottom = -H / 2 } }
	for _, id in ipairs(resolved.order) do
		local spec = resolved.parts[id]
		local pw, ph = Merge.PartSize(spec, W, H)
		local anchor = spec.anchor
		local cx, cy = 0, 0
		if spec.fill == 'plate' or not anchor then
			cx, cy = 0, 0
		else
			local target = rects[anchor[2]] or rects.plate
			local tw, th = target.right - target.left, target.top - target.bottom
			local tcx, tcy = (target.left + target.right) / 2, (target.top + target.bottom) / 2
			local relPoint, point = anchor[3] or anchor[1], anchor[1]
			local tx = tcx + (PX[relPoint] or 0) * tw / 2
			local ty = tcy + (PY[relPoint] or 0) * th / 2
			cx = tx + (anchor[4] or 0) - (PX[point] or 0) * pw / 2
			cy = ty + (anchor[5] or 0) - (PY[point] or 0) * ph / 2
		end
		rects[id] = { left = cx - pw / 2, right = cx + pw / 2, top = cy + ph / 2, bottom = cy - ph / 2 }
	end
	return rects
end

local function Union(a, b)
	if not a then
		return { left = b.left, right = b.right, top = b.top, bottom = b.bottom }
	end
	a.left = math.min(a.left, b.left)
	a.right = math.max(a.right, b.right)
	a.top = math.max(a.top, b.top)
	a.bottom = math.min(a.bottom, b.bottom)
	return a
end

---Click and stacking areas: the union of bars, the cast bar and the name, plus each region's pad,
---unless a region part with a width and height places the area (first such part wins), or the
---style sets a rect by hand (auto = false).
---@param resolved table
---@param regions table|nil style.regions
---@return { click: Plates.Rect, stack: Plates.Rect }
function Merge.Regions(resolved, regions)
	local rects = Merge.PartRects(resolved)
	local area
	for _, id in ipairs(resolved.order) do
		local spec = resolved.parts[id]
		if Merge.REGION_KINDS[spec.kind] or (spec.kind == 'text' and Merge.REGION_TEXT_SOURCES[spec.source]) then
			area = Union(area, rects[id])
		end
	end
	area = area or rects.plate
	-- A region part with a width and height is an area placed by hand (Engine/Parts/Region.lua)
	local placed = {}
	for _, id in ipairs(resolved.order) do
		local spec = resolved.parts[id]
		local which = spec.kind == 'region' and (spec.region or 'click') or nil
		if which and not placed[which] and spec.width and spec.height then
			local r = rects[id]
			placed[which] = { left = math.floor(r.left), right = math.ceil(r.right), top = math.ceil(r.top), bottom = math.floor(r.bottom) }
		end
	end
	local out = {}
	for _, which in ipairs({ 'click', 'stack' }) do
		local spec = regions and regions[which] or {}
		if placed[which] then
			out[which] = placed[which]
		elseif spec.auto == false and spec.rect then
			out[which] = { left = spec.rect.left, right = spec.rect.right, top = spec.rect.top, bottom = spec.rect.bottom }
		else
			local pad = spec.pad or { 0, 0, 0, 0 }
			out[which] = { left = math.floor(area.left - pad[1]), right = math.ceil(area.right + pad[2]), top = math.ceil(area.top + pad[3]), bottom = math.floor(area.bottom - pad[4]) }
		end
	end
	return out
end

---Base plate size that covers a click area (C_NamePlate.SetNamePlateSize is one value for every
---plate, so the Driver takes the largest over every style in use).
---@param rect Plates.Rect
---@return integer width
---@return integer height
function Merge.SizeForRect(rect)
	local width = 2 * math.max(math.abs(rect.left), math.abs(rect.right))
	local height = rect.top - rect.bottom
	return math.ceil(width), math.ceil(height)
end

---Layout order: anchor targets before the parts anchored to them, then by `order`, then id.
---@param parts table<string, table>
---@return string[]
function Merge.LayoutOrder(parts)
	local ids = {}
	for id in pairs(parts) do
		ids[#ids + 1] = id
	end
	table.sort(ids, function(a, b)
		local oa, ob = parts[a].order or 0, parts[b].order or 0
		if oa ~= ob then
			return oa < ob
		end
		return a < b
	end)
	local out, placed, visiting = {}, {}, {}
	local function Place(id)
		if placed[id] or visiting[id] then
			return
		end
		visiting[id] = true
		local anchor = parts[id].anchor
		local target = anchor and anchor[2]
		if target and target ~= 'plate' and parts[target] then
			Place(target)
		end
		visiting[id] = nil
		placed[id] = true
		out[#out + 1] = id
	end
	for _, id in ipairs(ids) do
		Place(id)
	end
	return out
end

---Hand the anchors of hidden or removed parts to the parts anchored to them, and point anything
---left in a cycle (or at a missing part) at the plate.
---@param parts table<string, table> Visible parts (changed in place)
---@param all table<string, table> Every part before hiding, for walking through hidden ones
function Merge.Reanchor(parts, all)
	for _, spec in pairs(parts) do
		local anchor = spec.anchor
		local guard = 0
		while anchor and anchor[2] ~= 'plate' and not parts[anchor[2]] and guard < 16 do
			guard = guard + 1
			local gone = all[anchor[2]]
			local through = gone and gone.anchor
			if through then
				anchor = { anchor[1], through[2], through[3], (anchor[4] or 0) + (through[4] or 0), (anchor[5] or 0) + (through[5] or 0) }
			else
				anchor = { anchor[1], 'plate', anchor[3], anchor[4] or 0, anchor[5] or 0 }
			end
		end
		if anchor and anchor[2] ~= 'plate' and not parts[anchor[2]] then
			anchor = { anchor[1], 'plate', anchor[3], anchor[4] or 0, anchor[5] or 0 }
		end
		spec.anchor = anchor
	end
	local cycle = P.Styles.Schema:FindCycle(parts)
	local guard = 0
	while cycle and guard < 16 do
		guard = guard + 1
		local spec = parts[cycle[1]]
		spec.anchor = { spec.anchor[1], 'plate', spec.anchor[3], 0, 0 }
		P.log.warning('Nameplate part ' .. cycle[1] .. ' was in an anchor loop; it now sits on the plate')
		cycle = P.Styles.Schema:FindCycle(parts)
	end
end

---Resolve a style without the registry, the profile or the cache (pure; previews, imports, tests).
---@param base table Style (any schema; upgraded here)
---@param overlay table|nil
---@param situation string|nil
---@param sizeKey string|nil
---@param hostLook Plates.HostLook|nil
---@return Plates.ResolvedStyle|nil
function Merge.ResolveRaw(base, overlay, situation, sizeKey, hostLook)
	local style = P.Styles.Schema:Upgrade(base)
	if not style then
		return nil
	end
	if overlay then
		overlay = P.Styles.Schema:UpgradeOverlay(overlay)
	end
	-- Parts the overlay removes still hand their anchor on, so keep them for the anchor walk
	local through = {}
	for id, spec in pairs(style.parts or {}) do
		through[id] = spec
	end
	Merge.ApplyOverlay(style, overlay)
	local all = style.parts or {}

	local hidden = {}
	local patch = situation and style.situations and style.situations[situation]
	if patch then
		for _, id in ipairs(patch.hide or {}) do
			hidden[id] = true
		end
		for id, partial in pairs(patch.parts or {}) do
			if all[id] then
				all[id] = Merge.Deep(all[id], partial)
			end
		end
		if patch.plate then
			style.plate = Merge.Deep(style.plate, patch.plate)
		end
		if patch.states then
			style.states = Merge.Deep(style.states, patch.states)
		end
	end
	for id, spec in pairs(all) do
		if spec.hidden then
			hidden[id] = true
		end
	end

	local tokens = style.tokens or {}
	local parts = {}
	for id, spec in pairs(all) do
		if not hidden[id] then
			local filled = Merge.Deep(Merge.PART_DEFAULTS[spec.kind] or {}, spec)
			parts[id] = ResolveTokens(filled, tokens, hostLook)
		end
	end
	for id, spec in pairs(all) do
		through[id] = spec
	end
	Merge.Reanchor(parts, through)

	sizeKey = sizeKey or 'medium'
	local sizes = (style.plate and style.plate.sizes) or Merge.DEFAULT_SIZES
	local size = sizes[sizeKey] or sizes.medium or Merge.DEFAULT_SIZES.medium

	local resolvedTokens = {}
	for name in pairs(tokens) do
		resolvedTokens[name] = TokenValue(name, tokens, hostLook, 0)
	end
	for name in pairs(Merge.TOKEN_FALLBACK) do
		if resolvedTokens[name] == nil then
			resolvedTokens[name] = TokenValue(name, tokens, hostLook, 0)
		end
	end

	local resolved = {
		id = style.id,
		name = style.name,
		situation = situation or 'enemyNPC',
		sizeKey = sizeKey,
		width = math.floor(size[1] + 0.5),
		height = math.floor(size[2] + 0.5),
		tokens = resolvedTokens,
		parts = parts,
		hidden = hidden,
		states = util.Copy(style.states or {}),
	}
	resolved.order = Merge.LayoutOrder(parts)
	resolved.regions = Merge.Regions(resolved, style.regions)
	return resolved
end

----------------------------------------------------------------------------------------------------
-- Cached resolution from the registry and the profile
----------------------------------------------------------------------------------------------------

---@param styleId string May be 'host'
---@param situation string
---@param sizeKey string
---@return Plates.ResolvedStyle
function Merge:Resolve(styleId, situation, sizeKey)
	local Registry = P.Styles.Registry
	local id = Registry:ResolveId(styleId)
	local cacheKey = id .. '|' .. (situation or '') .. '|' .. (sizeKey or 'medium')
	local cached = self.cache[cacheKey]
	if cached then
		return cached
	end
	local base = Registry:Get(id)
	if not base then
		id = Registry.FALLBACK_ID
		base = Registry:Get(id)
	end
	local tweaks = P.db and P.db.profile.tweaks
	local resolved = Merge.ResolveRaw(base, tweaks and tweaks[id], situation, sizeKey, P.hostLook)
	if not resolved then
		resolved = Merge.ResolveRaw(Registry:Get(Registry.FALLBACK_ID), nil, situation, sizeKey, P.hostLook)
	end
	resolved.id = id
	resolved.key = cacheKey .. '#' .. self.generation
	self.cache[cacheKey] = resolved
	return resolved
end

---Forget every resolved style. The next Resolve builds new ones with a new key.
function Merge:Invalidate()
	self.generation = self.generation + 1
	util.Wipe(self.cache)
end

---Base plus the player's overlay, tokens kept: what "Make a copy" saves.
---@param styleId string
---@return table|nil style
function Merge:Bake(styleId)
	local Registry = P.Styles.Registry
	local id = Registry:ResolveId(styleId)
	local base = Registry:Get(id)
	if not base then
		return nil
	end
	local style = P.Styles.Schema:Upgrade(base)
	local tweaks = P.db and P.db.profile.tweaks
	local overlay = tweaks and tweaks[id] and P.Styles.Schema:UpgradeOverlay(tweaks[id])
	return Merge.ApplyOverlay(style, overlay)
end

---How many of the player's changes point at parts the style no longer has ("2 of your changes
---no longer apply"). They are kept until the player clears them.
---@param styleId string
---@return integer
function Merge:StaleChanges(styleId)
	local Registry = P.Styles.Registry
	local id = Registry:ResolveId(styleId)
	local base = Registry:Get(id)
	local tweaks = P.db and P.db.profile.tweaks and P.db.profile.tweaks[id]
	if not base or not tweaks then
		return 0
	end
	local count = 0
	local changes = tweaks.changes and tweaks.changes.parts or {}
	for partId in pairs(changes) do
		if not (base.parts and base.parts[partId]) and not (tweaks.add and tweaks.add[partId]) then
			count = count + 1
		end
	end
	for partId in pairs(tweaks.remove or {}) do
		if not (base.parts and base.parts[partId]) then
			count = count + 1
		end
	end
	return count
end

---True when the player changed this style (shows "Reset my changes").
---@param styleId string
---@return boolean
function Merge:HasChanges(styleId)
	local id = P.Styles.Registry:ResolveId(styleId)
	local tweaks = P.db and P.db.profile.tweaks
	return tweaks ~= nil and tweaks[id] ~= nil and next(tweaks[id]) ~= nil
end

P:On('STORE_CHANGED', function(reasons)
	if reasons and (reasons.look or reasons.size or reasons.auras) then
		Merge:Invalidate()
	end
end, Merge)
P:On('HOST_LOOK_CHANGED', function()
	Merge:Invalidate()
end, Merge)
P:On('STYLES_CHANGED', function()
	Merge:Invalidate()
end, Merge)
