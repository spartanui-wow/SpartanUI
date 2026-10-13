local _, ns = ...
local P = ns.Plates

-- The part schema (5.1, 3.6): every field a style, part, overlay or situation patch may hold,
-- with types and ranges. Used by the import validator, by Registry for host and saved styles, by
-- the designer and options (slider ranges), and by the headless built-ins test (every built-in
-- must pass the validator, so a built-in can never hold something an import would reject).
--
-- Validation never trusts input: unknown keys are dropped and counted, numbers are clamped and
-- counted, wrong types are dropped, anchors to missing parts point at the plate, and anchor
-- cycles reject the whole style. Upgrades (one numbered chain for built-ins, saved bases,
-- overlays and imports) live at the end of this file.

---@class Plates.Styles
P.Styles = P.Styles or {}

---@class Plates.Schema
local Schema = {}
P.Styles.Schema = Schema

---Current style data format: the one number for saved styles, overlays and share strings. Raise
---it together with Schema:AddUpgrade.
Schema.CURRENT = 1
P.VERSION.schema = Schema.CURRENT

---@class Plates.ValidationReport
---@field dropped integer Unknown or invalid keys removed
---@field droppedKeys string[] Paths of removed keys (first 50)
---@field clamped integer Numbers pulled into range
---@field fixed integer Anchors re-pointed at the plate
---@field errors string[] Problems that reject the input

local function Report()
	return { dropped = 0, droppedKeys = {}, clamped = 0, fixed = 0, errors = {} }
end
Schema.NewReport = Report

local function Drop(report, path)
	report.dropped = report.dropped + 1
	if #report.droppedKeys < 50 then
		report.droppedKeys[#report.droppedKeys + 1] = path
	end
end

----------------------------------------------------------------------------------------------------
-- Field types
----------------------------------------------------------------------------------------------------

local function Set(list)
	local out = {}
	for _, v in ipairs(list) do
		out[v] = true
	end
	return out
end

local function Num(min, max, int)
	return { t = 'number', min = min, max = max, int = int }
end
local function Str(max, pattern)
	return { t = 'string', max = max or 64, pattern = pattern }
end
local function Enum(list)
	return { t = 'enum', values = Set(list), list = list }
end
local function Fields(map)
	return { t = 'record', fields = map }
end
local function MapOf(keyPattern, value, max)
	return { t = 'map', key = keyPattern, value = value, max = max or 64 }
end
local function ListOf(value, max)
	return { t = 'list', value = value, max = max or 64 }
end

local BOOL = { t = 'bool' }
local COLOR = { t = 'color' }
local TOKEN_OR_COLOR = { t = 'tokenOrColor' }
local TOKEN_OR_STRING = { t = 'tokenOrString', max = 256 }
local TOKEN_VALUE = { t = 'tokenValue' }
local ANCHOR = { t = 'anchor' }

Schema.PART_ID = '^[%a][%w_]*$'
Schema.POINTS = { 'TOPLEFT', 'TOP', 'TOPRIGHT', 'LEFT', 'CENTER', 'RIGHT', 'BOTTOMLEFT', 'BOTTOM', 'BOTTOMRIGHT' }
Schema.FLAGS = { '', 'OUTLINE', 'THICKOUTLINE', 'MONOCHROME', 'OUTLINE, MONOCHROME', 'THICKOUTLINE, MONOCHROME' }
Schema.PART_KINDS = { 'bar', 'cast', 'text', 'icon', 'auras', 'highlight', 'glow', 'art', 'region', 'classPower' }
Schema.PIECES = { 'health', 'border', 'name', 'cast' }
Schema.STATES = { 'target', 'notTarget', 'focus', 'mouseover', 'casting' }
Schema.SIZES = { 'small', 'medium', 'large' }
Schema.BAR_SOURCES = { 'health', 'power' }
Schema.TEXT_SOURCES = { 'name', 'level', 'healthPercent', 'healthValue', 'forces', 'title', 'threatPercent', 'threatLead', 'castName', 'castTime', 'castTarget', 'arena', 'nameFill' }
Schema.ICON_SOURCES = { 'raidMarker', 'classification', 'quest', 'faction', 'focus', 'shield' }
Schema.AURA_ROWS = { 'myDebuffs', 'removable', 'crowdControl', 'custom' }
Schema.GLOW_SOURCES = { 'threat', 'importantCast', 'purge', 'pandemic', 'target' }

---Aura container candidate filter keys known from Blizzard's source (6.6). Unknown keys are dropped
---before they reach the engine, because a wrong key fails open (matches every aura).
Schema.CANDIDATE_KEYS = Set({
	'excludeSpellIDs',
	'includeSpellIDs',
	'processedAuraType',
	'excludeDispelTypes',
	'includeDispelTypes',
	'canApplyAura',
	'isBossAura',
	'isBossOrRoleAura',
	'isFromPlayerOrPlayerPet',
	'isRoleAura',
	'isPriorityAura',
	'isStealable',
	'maxDuration',
	'nameplateShowAll',
	'nameplateShowPersonal',
})

local SIZE2 = { t = 'size2', min = 1, max = 1024 }
local GROW2 = { t = 'size2', min = 0, max = 64 }
local PAD4 = { t = 'pad4', min = 0, max = 64 }
local FONT = Fields({ face = TOKEN_OR_STRING, size = Num(6, 40, true), flags = Enum(Schema.FLAGS), shadow = BOOL })
local BORDER = Fields({ kind = Enum({ 'none', 'pixel', 'thick', 'shadow', 'beveled' }), size = Num(0, 8, true), color = TOKEN_OR_COLOR })

---Fields every part may hold.
Schema.PART_COMMON = {
	order = Num(0, 10000),
	kind = Enum(Schema.PART_KINDS),
	anchor = ANCHOR,
	alpha = Num(0, 1),
	layer = Num(-8, 8, true),
	hidden = BOOL,
	state = Enum(Schema.STATES),
	pixelSnap = BOOL,
	above = BOOL,
	label = Str(48),
}

---Fields by part kind (on top of PART_COMMON).
Schema.PART_FIELDS = {
	bar = {
		source = Enum(Schema.BAR_SOURCES),
		fill = Enum({ 'plate' }),
		width = Num(1, 512, true),
		height = Num(1, 128, true),
		texture = TOKEN_OR_STRING,
		border = BORDER,
		bg = TOKEN_OR_COLOR,
		colors = Enum(Schema.PIECES),
		borderColors = Enum(Schema.PIECES),
		color = TOKEN_OR_COLOR,
		absorb = BOOL,
		healAbsorb = BOOL,
		interpolate = BOOL,
		reverse = BOOL,
		-- Health only (Engine/Parts/Health.lua); each has a default in code
		absorbMode = Enum({ 'overlay', 'extend' }),
		absorbColor = TOKEN_OR_COLOR,
		absorbTexture = TOKEN_OR_STRING,
		healAbsorbColor = TOKEN_OR_COLOR,
		lostHealth = BOOL,
		execute = Num(0, 0.9),
		executeColor = TOKEN_OR_COLOR,
	},
	cast = {
		width = Num(1, 512, true),
		height = Num(1, 64, true),
		icon = Enum({ 'left', 'right', 'none' }),
		iconSize = Num(0, 64, true),
		target = BOOL,
		shield = BOOL,
		important = BOOL,
		aimedAtMe = BOOL,
		texture = TOKEN_OR_STRING,
		border = BORDER,
		bg = TOKEN_OR_COLOR,
		colors = Enum(Schema.PIECES),
		font = FONT,
		nameText = BOOL,
		timeText = BOOL,
		timeFormat = Enum({ 'remaining', 'elapsed', 'both' }),
		enemies = BOOL,
		friends = BOOL,
		kickMark = BOOL,
		kickFill = BOOL,
		interrupter = BOOL,
	},
	text = {
		source = Enum(Schema.TEXT_SOURCES),
		font = FONT,
		justify = Enum({ 'LEFT', 'CENTER', 'RIGHT' }),
		colors = Enum(Schema.PIECES),
		color = TOKEN_OR_COLOR,
		width = Num(0, 512, true),
		hideAtFull = BOOL,
		abbreviate = BOOL,
		bg = TOKEN_OR_COLOR, -- nameFill: the name's color where health is lost
	},
	icon = {
		source = Enum(Schema.ICON_SOURCES),
		size = Num(4, 64, true),
		color = TOKEN_OR_COLOR,
	},
	auras = {
		row = Enum(Schema.AURA_ROWS),
		size = Num(8, 64, true),
		max = Num(0, 40, true),
		perRow = Num(1, 40, true),
		grow = Enum({ 'LEFT', 'RIGHT', 'UP', 'DOWN' }),
		spacing = Num(0, 16, true),
		timer = BOOL,
		stacks = BOOL,
		borderStyle = Enum({ 'none', 'pixel', 'dispel' }),
		sort = Enum({ 'default', 'time', 'name' }),
		pandemic = BOOL,
		font = FONT,
	},
	highlight = {
		art = Str(64),
		color = TOKEN_OR_COLOR,
		pad = Num(0, 32, true),
		size = Num(0, 64, true),
		blend = Enum({ 'BLEND', 'ADD' }),
		animate = Enum({ 'none', 'pulse', 'bounce' }),
	},
	glow = {
		source = Enum(Schema.GLOW_SOURCES),
		color = TOKEN_OR_COLOR,
		size = Num(0, 32, true),
		art = Str(64),
		blend = Enum({ 'BLEND', 'ADD' }),
		animate = Enum({ 'none', 'pulse' }),
	},
	art = {
		art = Str(64),
		color = TOKEN_OR_COLOR,
		width = Num(1, 512, true),
		height = Num(1, 256, true),
		fill = Enum({ 'plate' }),
		-- A picture cut in nine: corners keep their shape, the edges and middle stretch. Texel
		-- numbers are in the picture file; scale is drawn pixels per texel.
		slice = Fields({
			file = SIZE2,
			size = SIZE2,
			left = Num(0, 1024, true),
			top = Num(0, 1024, true),
			right = Num(0, 1024, true),
			bottom = Num(0, 1024, true),
			scale = Num(0.05, 4),
		}),
		-- How far a plate-filling picture reaches past the plate on each side, in pixels
		outset = Fields({ left = Num(0, 64, true), top = Num(0, 64, true), right = Num(0, 64, true), bottom = Num(0, 64, true) }),
	},
	region = {
		region = Enum({ 'click', 'stack' }),
		width = Num(1, 1024, true),
		height = Num(1, 512, true),
	},
	classPower = {
		size = Num(2, 32, true),
		spacing = Num(0, 16, true),
		shape = Str(32),
		color = TOKEN_OR_COLOR, -- one color for every pip; unset uses each resource's own color
	},
}

local REGION = Fields({ auto = BOOL, pad = PAD4, rect = Fields({ left = Num(-1024, 0), right = Num(0, 1024), top = Num(0, 512), bottom = Num(-512, 0) }) })
local STATE = Fields({ grow = GROW2, alpha = Num(0, 1), glow = BOOL })
local STATES = Fields({ target = STATE, notTarget = STATE, focus = STATE, mouseover = STATE, casting = STATE })
local PLATE = Fields({ sizes = Fields({ small = SIZE2, medium = SIZE2, large = SIZE2 }) })
local TOKENS = MapOf('^[%a][%w_]*$', TOKEN_VALUE, 32)

----------------------------------------------------------------------------------------------------
-- Checker
----------------------------------------------------------------------------------------------------

local Check

local function CheckNumber(spec, value, path, report)
	if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then
		Drop(report, path)
		return nil
	end
	local out = value
	if spec.min and out < spec.min then
		out = spec.min
	end
	if spec.max and out > spec.max then
		out = spec.max
	end
	if spec.int then
		out = math.floor(out + 0.5)
	end
	if out ~= value then
		report.clamped = report.clamped + 1
	end
	return out
end

local function CheckColor(value, path, report)
	if type(value) ~= 'table' then
		Drop(report, path)
		return nil
	end
	local out = {}
	for i = 1, 4 do
		local c = value[i]
		if c == nil and i == 4 then
			c = 1
		end
		if type(c) ~= 'number' or c ~= c then
			Drop(report, path)
			return nil
		end
		if c < 0 then
			c = 0
			report.clamped = report.clamped + 1
		elseif c > 1 then
			c = 1
			report.clamped = report.clamped + 1
		end
		out[i] = c
	end
	return out
end

local function IsToken(value)
	return type(value) == 'string' and string.match(value, '^%$[%a][%w_]*$') ~= nil
end

local function CheckAnchor(value, path, report)
	if type(value) ~= 'table' then
		Drop(report, path)
		return nil
	end
	local points = Set(Schema.POINTS)
	local point, relativeTo, relPoint = value[1], value[2] or 'plate', value[3] or value[1]
	if not points[point] or not points[relPoint] then
		Drop(report, path)
		return nil
	end
	if type(relativeTo) ~= 'string' or (relativeTo ~= 'plate' and not string.match(relativeTo, Schema.PART_ID)) then
		Drop(report, path)
		return nil
	end
	local x = value[4] == nil and 0 or CheckNumber(Num(-512, 512), value[4], path .. '[4]', report)
	local y = value[5] == nil and 0 or CheckNumber(Num(-512, 512), value[5], path .. '[5]', report)
	if x == nil or y == nil then
		return nil
	end
	return { point, relativeTo, relPoint, x, y }
end

Check = function(spec, value, path, report, partial)
	local t = spec.t
	if t == 'number' then
		return CheckNumber(spec, value, path, report)
	elseif t == 'string' then
		if type(value) ~= 'string' then
			Drop(report, path)
			return nil
		end
		local out = value
		if #out > spec.max then
			out = string.sub(out, 1, spec.max)
			report.clamped = report.clamped + 1
		end
		if spec.pattern and not string.match(out, spec.pattern) then
			Drop(report, path)
			return nil
		end
		return out
	elseif t == 'enum' then
		if spec.values[value] then
			return value
		end
		Drop(report, path)
		return nil
	elseif t == 'bool' then
		if type(value) == 'boolean' then
			return value
		end
		Drop(report, path)
		return nil
	elseif t == 'color' then
		return CheckColor(value, path, report)
	elseif t == 'tokenOrColor' then
		if IsToken(value) then
			return value
		end
		return CheckColor(value, path, report)
	elseif t == 'tokenOrString' then
		if type(value) ~= 'string' or #value == 0 or #value > spec.max or string.find(value, '[%c|]') then
			Drop(report, path)
			return nil
		end
		return value
	elseif t == 'tokenValue' then
		if type(value) == 'table' then
			return CheckColor(value, path, report)
		end
		return Check(TOKEN_OR_STRING, value, path, report)
	elseif t == 'anchor' then
		return CheckAnchor(value, path, report)
	elseif t == 'size2' then
		if type(value) ~= 'table' then
			Drop(report, path)
			return nil
		end
		local w = CheckNumber({ min = spec.min, max = spec.max, int = true }, value[1], path .. '[1]', report)
		local h = CheckNumber({ min = spec.min, max = spec.max, int = true }, value[2], path .. '[2]', report)
		if w == nil or h == nil then
			return nil
		end
		return { w, h }
	elseif t == 'pad4' then
		if type(value) ~= 'table' then
			Drop(report, path)
			return nil
		end
		local out = {}
		for i = 1, 4 do
			out[i] = CheckNumber({ min = spec.min, max = spec.max, int = true }, value[i] or 0, path .. '[' .. i .. ']', report)
			if out[i] == nil then
				return nil
			end
		end
		return out
	elseif t == 'record' then
		if type(value) ~= 'table' then
			Drop(report, path)
			return nil
		end
		local out = {}
		for key, item in pairs(value) do
			local field = type(key) == 'string' and spec.fields[key]
			if field then
				out[key] = Check(field, item, path .. '.' .. key, report, partial)
			else
				Drop(report, path .. '.' .. tostring(key))
			end
		end
		return out
	elseif t == 'map' then
		if type(value) ~= 'table' then
			Drop(report, path)
			return nil
		end
		local out, count = {}, 0
		for key, item in pairs(value) do
			if type(key) == 'string' and string.match(key, spec.key) and count < spec.max then
				local checked = Check(spec.value, item, path .. '.' .. key, report, partial)
				if checked ~= nil then
					out[key] = checked
					count = count + 1
				end
			else
				Drop(report, path .. '.' .. tostring(key))
			end
		end
		return out
	elseif t == 'list' then
		if type(value) ~= 'table' then
			Drop(report, path)
			return nil
		end
		local out = {}
		for i = 1, math.min(#value, spec.max) do
			local checked = Check(spec.value, value[i], path .. '[' .. i .. ']', report, partial)
			if checked ~= nil then
				out[#out + 1] = checked
			end
		end
		return out
	elseif t == 'set' then
		if type(value) ~= 'table' then
			Drop(report, path)
			return nil
		end
		local out = {}
		for key, flag in pairs(value) do
			if type(key) == 'string' and string.match(key, Schema.PART_ID) and flag == true then
				out[key] = true
			else
				Drop(report, path .. '.' .. tostring(key))
			end
		end
		return out
	end
	Drop(report, path)
	return nil
end

---Range and type of one field, for sliders and pickers. nil when unknown.
---@param kind string Part kind
---@param field string
---@return table|nil spec
function Schema:FieldSpec(kind, field)
	return (self.PART_FIELDS[kind] and self.PART_FIELDS[kind][field]) or self.PART_COMMON[field]
end

---Check one part. kindHint is used for partial parts (overlay changes) that do not repeat kind.
---@param part table
---@param path string
---@param report Plates.ValidationReport
---@param partial? boolean
---@param kindHint? string
---@return table|nil
function Schema:CheckPart(part, path, report, partial, kindHint)
	if type(part) ~= 'table' then
		Drop(report, path)
		return nil
	end
	local kind = part.kind or kindHint
	if not kind or not self.PART_FIELDS[kind] then
		if partial and not kind then
			-- A partial change without a known kind keeps only the common fields
			local out = {}
			for key, item in pairs(part) do
				local field = self.PART_COMMON[key]
				if field then
					out[key] = Check(field, item, path .. '.' .. key, report, true)
				else
					Drop(report, path .. '.' .. tostring(key))
				end
			end
			return out
		end
		Drop(report, path)
		return nil
	end
	local fields = self.PART_FIELDS[kind]
	local out = {}
	for key, item in pairs(part) do
		local field = type(key) == 'string' and (fields[key] or self.PART_COMMON[key])
		if field then
			out[key] = Check(field, item, path .. '.' .. key, report, partial)
		else
			Drop(report, path .. '.' .. tostring(key))
		end
	end
	if not partial then
		out.kind = kind
	end
	return out
end

local function CheckParts(parts, path, report, partial, kindsFrom)
	if type(parts) ~= 'table' then
		Drop(report, path)
		return nil
	end
	local out, count = {}, 0
	for id, part in pairs(parts) do
		if type(id) == 'string' and string.match(id, Schema.PART_ID) and #id <= 32 and count < 64 then
			local hint = kindsFrom and kindsFrom[id] and kindsFrom[id].kind
			local checked = Schema:CheckPart(part, path .. '.' .. id, report, partial, hint)
			if checked then
				out[id] = checked
				count = count + 1
			end
		else
			Drop(report, path .. '.' .. tostring(id))
		end
	end
	return out
end

local function CheckPatch(patch, path, report, kindsFrom)
	if type(patch) ~= 'table' then
		Drop(report, path)
		return nil
	end
	local out = {}
	for key, item in pairs(patch) do
		if key == 'hide' then
			out.hide = Check(ListOf(Str(32, Schema.PART_ID), 64), item, path .. '.hide', report)
		elseif key == 'parts' then
			out.parts = CheckParts(item, path .. '.parts', report, true, kindsFrom)
		elseif key == 'plate' then
			out.plate = Check(PLATE, item, path .. '.plate', report, true)
		elseif key == 'states' then
			out.states = Check(STATES, item, path .. '.states', report, true)
		else
			Drop(report, path .. '.' .. tostring(key))
		end
	end
	return out
end

local function CheckSituations(value, path, report, kindsFrom)
	if type(value) ~= 'table' then
		Drop(report, path)
		return nil
	end
	local kinds = Set({ 'enemyNPC', 'enemyPlayer', 'friendlyNPC', 'friendlyPlayer', 'minor' })
	local out = {}
	for situation, patch in pairs(value) do
		if kinds[situation] then
			out[situation] = CheckPatch(patch, path .. '.' .. situation, report, kindsFrom)
		else
			Drop(report, path .. '.' .. tostring(situation))
		end
	end
	return out
end

---Part ids that sit in an anchor cycle (nil when there is none).
---@param parts table<string, table>
---@return string[]|nil
function Schema:FindCycle(parts)
	local state = {}
	local cycle
	local function Visit(id, trail)
		if cycle then
			return
		end
		if state[id] == 'done' then
			return
		end
		if state[id] == 'visiting' then
			cycle = { id }
			for i = #trail, 1, -1 do
				if trail[i] == id then
					break
				end
				cycle[#cycle + 1] = trail[i]
			end
			return
		end
		state[id] = 'visiting'
		trail[#trail + 1] = id
		local anchor = parts[id] and parts[id].anchor
		local target = anchor and anchor[2]
		if target and target ~= 'plate' and parts[target] then
			Visit(target, trail)
		end
		trail[#trail] = nil
		state[id] = 'done'
	end
	for id in pairs(parts) do
		Visit(id, {})
	end
	return cycle
end

local STYLE_FIELDS = {
	id = Str(48, '^[%w_%-]+$'),
	name = Str(48),
	description = Str(160),
	author = Str(48),
	version = Num(1, 1000000, true),
	schema = Num(1, 1000, true),
	order = Num(0, 10000),
	internal = BOOL,
	matchesHost = BOOL,
	plate = PLATE,
	regions = Fields({ click = REGION, stack = REGION }),
	tokens = TOKENS,
	states = STATES,
}

---Validate a full style. Returns a cleaned copy and a report; on failure nil, the report and a
---reason ('cycle', 'notTable', 'noParts', 'noName').
---@param style table
---@return table|nil cleaned
---@return Plates.ValidationReport report
---@return string|nil reason
function Schema:ValidateStyle(style)
	local report = Report()
	if type(style) ~= 'table' then
		return nil, report, 'notTable'
	end
	local out = {}
	for key, item in pairs(style) do
		if key == 'parts' then
			out.parts = CheckParts(item, 'parts', report, false)
		elseif key == 'situations' then
			-- checked after parts so partial changes know their kinds
		elseif type(key) == 'string' and STYLE_FIELDS[key] then
			out[key] = Check(STYLE_FIELDS[key], item, key, report)
		else
			Drop(report, tostring(key))
		end
	end
	if style.situations ~= nil then
		out.situations = CheckSituations(style.situations, 'situations', report, out.parts)
	end
	if not out.parts or next(out.parts) == nil then
		return nil, report, 'noParts'
	end
	if not out.name then
		return nil, report, 'noName'
	end
	for id, part in pairs(out.parts) do
		local anchor = part.anchor
		if anchor and anchor[2] ~= 'plate' and not out.parts[anchor[2]] then
			part.anchor = { anchor[1], 'plate', anchor[3], anchor[4], anchor[5] }
			report.fixed = report.fixed + 1
			P.log.debug('Part ' .. id .. ' pointed at a missing part; now anchored to the plate')
		end
	end
	local cycle = self:FindCycle(out.parts)
	if cycle then
		report.errors[#report.errors + 1] = 'cycle:' .. table.concat(cycle, ',')
		return nil, report, 'cycle'
	end
	out.schema = out.schema or self.CURRENT
	out.version = out.version or 1
	return out, report
end

---Validate an overlay (profile.tweaks[styleId]). basePartsKinds lets partial part changes keep
---their kind-specific fields.
---@param overlay table
---@param baseParts? table<string, table>
---@return table|nil cleaned
---@return Plates.ValidationReport report
function Schema:ValidateOverlay(overlay, baseParts)
	local report = Report()
	if type(overlay) ~= 'table' then
		return nil, report
	end
	local out = {}
	for key, item in pairs(overlay) do
		if key == 'schema' then
			out.schema = Check(Num(1, 1000, true), item, key, report)
		elseif key == 'baseVersion' then
			out.baseVersion = Check(Num(0, 1000000, true), item, key, report)
		elseif key == 'add' then
			out.add = CheckParts(item, 'add', report, false)
		elseif key == 'remove' then
			out.remove = Check({ t = 'set' }, item, 'remove', report)
		elseif key == 'changes' then
			local changes = {}
			if type(item) == 'table' then
				for ckey, citem in pairs(item) do
					if ckey == 'parts' then
						changes.parts = CheckParts(citem, 'changes.parts', report, true, baseParts)
					elseif ckey == 'plate' then
						changes.plate = Check(PLATE, citem, 'changes.plate', report, true)
					elseif ckey == 'states' then
						changes.states = Check(STATES, citem, 'changes.states', report, true)
					elseif ckey == 'tokens' then
						changes.tokens = Check(TOKENS, citem, 'changes.tokens', report, true)
					elseif ckey == 'regions' then
						changes.regions = Check(Fields({ click = REGION, stack = REGION }), citem, 'changes.regions', report, true)
					else
						Drop(report, 'changes.' .. tostring(ckey))
					end
				end
			end
			out.changes = changes
		elseif key == 'situations' then
			out.situations = CheckSituations(item, 'situations', report, baseParts)
		else
			Drop(report, tostring(key))
		end
	end
	return out, report
end

----------------------------------------------------------------------------------------------------
-- Upgrade chain (one chain for built-ins, saved bases, overlays and imports)
----------------------------------------------------------------------------------------------------

---[n] = fn(style) turns schema n-1 into n, in place on a copy.
Schema.upgrades = {}
---[n] = fn(overlay) for overlays.
Schema.overlayUpgrades = {}

---@param number integer
---@param styleFn fun(style: table)
---@param overlayFn? fun(overlay: table)
function Schema:AddUpgrade(number, styleFn, overlayFn)
	self.upgrades[number] = styleFn
	self.overlayUpgrades[number] = overlayFn
end

local function Upgrade(data, chain)
	local copy = P.util.Copy(data)
	local from = tonumber(copy.schema) or 1
	if from > Schema.CURRENT then
		return nil, 'newer'
	end
	for number = from + 1, Schema.CURRENT do
		local fn = chain[number]
		if fn then
			fn(copy)
		end
		copy.schema = number
	end
	copy.schema = Schema.CURRENT
	return copy
end

---Copy of a style at the current schema, or nil and 'newer' when it comes from a newer version.
---@param style table
---@return table|nil
---@return string|nil reason
function Schema:Upgrade(style)
	return Upgrade(style, self.upgrades)
end

---Copy of an overlay at the current schema, or nil and 'newer'.
---@param overlay table
---@return table|nil
---@return string|nil reason
function Schema:UpgradeOverlay(overlay)
	return Upgrade(overlay, self.overlayUpgrades)
end
