local _, ns = ...
local P = ns.Plates
local L = P.L

-- Import and export (3.6) behind the Sharing page, the Style page's Share and Import buttons and
-- P.API:ImportStyle. P.Share builds and reads the strings; this file decides what a string may do:
--   * Inspect(text) reads a string without changing anything and says what it is (a live preview
--     card, the numbers behind "2 settings were not recognized", "Your 4 changes stay").
--   * Apply(info, mode) saves a style (new, update, use) or replaces colors, the "When" list or a
--     whole profile. Every replace keeps one Undo.
--   * Strings are never trusted: styles go through Schema (upgrade chain, ranges, anchor cycles),
--     and colors, "When" lists and profiles go through the cleaners below, which keep only the
--     keys and types the engine reads and count what they drop.
--   * BuildExport(what) makes the strings for the Sharing page.

---@class Plates.Exchange
local Exchange = { undo = nil }
P.Exchange = Exchange

local Registry, Merge, Schema = P.Styles.Registry, P.Styles.Merge, P.Styles.Schema
local util = P.util

---Longest text Inspect looks at, before it reads anything (a whole profile with styles is far
---smaller). P.Share then caps the packed and unpacked sizes.
Exchange.MAX_LENGTH = 400000

---Profile keys a profile string carries. Role, game settings (cvars) and the host switches stay
---with the player.
Exchange.PROFILE_KEYS = { 'style', 'size', 'assign', 'modes', 'when', 'tweaks', 'scheme', 'colors', 'threat', 'colorBlind', 'behavior', 'auras' }

-- Profile keys a share string never carries on purpose: the player's own role and game settings
-- (personal, not part of a look), this profile's own switches, bookkeeping, and keys no page
-- writes yet. Every other key in Store.REASONS.profile must be in PROFILE_KEYS (a test checks
-- this, so a page that writes a new key cannot have it dropped on import without anyone deciding).
Exchange.PROFILE_KEYS_KEPT_OUT = { 'role', 'cvars', 'enabled', 'followHostProfile', 'schema', 'migratedFromOld', 'legacy', 'casts', 'actions' }

local ROLES = { auto = true, tank = true, damage = true, healer = true }

Exchange.EXPORT_KINDS = { 'style', 'colors', 'when', 'everything' }

----------------------------------------------------------------------------------------------------
-- Cleaning helpers (return a fresh value or nil, and count what they changed in a report)
----------------------------------------------------------------------------------------------------

local function NewReport()
	return { dropped = 0, clamped = 0, fixed = 0, droppedKeys = {} }
end

local function Drop(report, path)
	report.dropped = report.dropped + 1
	if #report.droppedKeys < 30 then
		report.droppedKeys[#report.droppedKeys + 1] = tostring(path)
	end
end

local function Number(value, min, max, report, path, integer)
	if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then
		Drop(report, path)
		return nil
	end
	local out = value
	if integer then
		out = math.floor(out + 0.5)
	end
	if out < min then
		out = min
	elseif out > max then
		out = max
	end
	if out ~= value and not (integer and math.abs(out - value) <= 0.5) then
		report.clamped = report.clamped + 1
	end
	return out
end

local function Boolean(value, report, path)
	if type(value) ~= 'boolean' then
		Drop(report, path)
		return nil
	end
	return value
end

local function OneOf(value, allowed, report, path)
	if type(value) == 'string' and allowed[value] then
		return value
	end
	Drop(report, path)
	return nil
end

local function SetOf(list)
	local out = {}
	for _, item in ipairs(list) do
		out[item] = true
	end
	return out
end

local function Key(value, max)
	return type(value) == 'string' and #value > 0 and #value <= (max or 48) and string.find(value, '^[%w_%-]+$') ~= nil
end

local function Color(value, report, path)
	if type(value) ~= 'table' then
		Drop(report, path)
		return nil
	end
	local out = {}
	local names = { 'r', 'g', 'b', 'a' }
	for i = 1, 4 do
		local item = value[i]
		if item == nil then
			item = value[names[i]]
		end
		if item == nil and i == 4 then
			item = 1
		end
		item = Number(item, 0, 1, report, path)
		if item == nil then
			return nil
		end
		out[i] = item
	end
	return out
end

local function Count(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

----------------------------------------------------------------------------------------------------
-- Colors
----------------------------------------------------------------------------------------------------

local SCHEMES = SetOf({ 'auto', 'threat', 'mobType', 'class', 'custom' })
local THREAT_CHANNELS = SetOf({ 'bar', 'border', 'name', 'glow', 'size' })
local SPELL_ROWS = SetOf({ 'hasAura', 'auraMissing' })

local function WhenId(value)
	return type(value) == 'string' and (value == 'always' or P.Conditions.WHEN[value] ~= nil)
end

---A spell list is either a map { [spellID] = 'mine' | 'any' } or a plain list of spell ids and names.
local function SpellList(value, report, path)
	if type(value) ~= 'table' then
		Drop(report, path)
		return nil
	end
	local out, n = {}, 0
	local isList = util.IsList(value)
	for key, item in pairs(value) do
		local accepted = false
		if n < 200 then
			if isList then
				if type(item) == 'number' and item >= 1 and item <= 1e9 and item == math.floor(item) then
					accepted = true
				elseif type(item) == 'string' and #item > 0 and #item <= 64 then
					accepted = true
				end
			elseif type(key) == 'number' and key >= 1 and key <= 1e9 and key == math.floor(key) and (item == 'mine' or item == 'any') then
				accepted = true
			end
		end
		if accepted then
			out[key] = item
			n = n + 1
		else
			Drop(report, path)
		end
	end
	return out
end

local function CleanPiece(piece, report, path)
	if type(piece) ~= 'table' then
		Drop(report, path)
		return nil
	end
	local Colors = P.Colors
	local out = {}
	for key, item in pairs(piece) do
		local here = path .. '.' .. tostring(key)
		if key == 'order' and type(item) == 'table' then
			local order, seen = {}, {}
			for _, id in ipairs(item) do
				if type(id) == 'string' and Colors.kinds[id] and not seen[id] and #order < 40 then
					seen[id] = true
					order[#order + 1] = id
				else
					Drop(report, here)
				end
			end
			out.order = order
		elseif key == 'off' and type(item) == 'table' then
			local off = {}
			for id, flag in pairs(item) do
				if type(id) == 'string' and Colors.kinds[id] and flag == true then
					off[id] = true
				else
					Drop(report, here)
				end
			end
			out.off = off
		elseif key == 'color' and type(item) == 'table' then
			local colors = {}
			for id, value in pairs(item) do
				if type(id) == 'string' and Colors.kinds[id] and type(value) == 'table' then
					if type(value[1]) == 'number' or type(value.r) == 'number' then
						colors[id] = Color(value, report, here .. '.' .. id)
					else
						local states, n = {}, 0
						for state, color in pairs(value) do
							if Key(state, 40) and n < 40 then
								states[state] = Color(color, report, here .. '.' .. id .. '.' .. state)
								n = n + 1
							else
								Drop(report, here .. '.' .. id)
							end
						end
						if next(states) then
							colors[id] = states
						end
					end
				else
					Drop(report, here)
				end
			end
			out.color = colors
		elseif key == 'when' and type(item) == 'table' then
			local whens = {}
			for id, value in pairs(item) do
				if type(id) == 'string' and Colors.kinds[id] and WhenId(value) then
					whens[id] = value
				else
					Drop(report, here)
				end
			end
			out.when = whens
		elseif key == 'fallback' then
			out.fallback = Color(item, report, here)
		elseif key == 'spells' and type(item) == 'table' then
			local spells = {}
			for id, list in pairs(item) do
				if SPELL_ROWS[id] then
					spells[id] = SpellList(list, report, here .. '.' .. id)
				else
					Drop(report, here)
				end
			end
			out.spells = spells
		else
			Drop(report, here)
		end
	end
	return out
end

---Check the colors fields of a profile (scheme, colors, threat, colorBlind).
---@param source table
---@param report Plates.ValidationReport
---@return table cleaned
local function CleanColorFields(source, report)
	local out = {}
	if source.scheme ~= nil then
		out.scheme = OneOf(source.scheme, SCHEMES, report, 'scheme')
	end
	if source.colorBlind ~= nil then
		out.colorBlind = Boolean(source.colorBlind, report, 'colorBlind')
	end
	if type(source.colors) == 'table' then
		local colors = {}
		for piece, item in pairs(source.colors) do
			local known = false
			for _, name in ipairs(P.Colors.PIECES) do
				if name == piece then
					known = true
				end
			end
			if known then
				colors[piece] = CleanPiece(item, report, 'colors.' .. piece)
			else
				Drop(report, 'colors.' .. tostring(piece))
			end
		end
		if next(colors) then
			out.colors = colors
		end
	elseif source.colors ~= nil then
		Drop(report, 'colors')
	end
	if type(source.threat) == 'table' then
		local threat = {}
		for key, item in pairs(source.threat) do
			local here = 'threat.' .. tostring(key)
			if key == 'when' then
				if WhenId(item) then
					threat.when = item
				else
					Drop(report, here)
				end
			elseif key == 'show' and type(item) == 'table' then
				local show = {}
				for channel, on in pairs(item) do
					if THREAT_CHANNELS[channel] and type(on) == 'boolean' then
						show[channel] = on
					else
						Drop(report, here)
					end
				end
				threat.show = show
			elseif key == 'colors' and type(item) == 'table' then
				local colors = {}
				for _, state in ipairs(P.Roles.STATES) do
					if item[state] ~= nil then
						colors[state] = Color(item[state], report, here .. '.' .. state)
					end
				end
				for state in pairs(item) do
					local known = false
					for _, name in ipairs(P.Roles.STATES) do
						if name == state then
							known = true
						end
					end
					if not known then
						Drop(report, here)
					end
				end
				threat.colors = colors
			else
				Drop(report, here)
			end
		end
		if next(threat) then
			out.threat = threat
		end
	elseif source.threat ~= nil then
		Drop(report, 'threat')
	end
	return out
end

---Check a colors payload { scheme, colors, threat, colorBlind }.
---@param payload table
---@return table cleaned
---@return Plates.ValidationReport report
function Exchange:CleanColors(payload)
	local report = NewReport()
	return CleanColorFields(type(payload) == 'table' and payload or {}, report), report
end

----------------------------------------------------------------------------------------------------
-- "When" list
----------------------------------------------------------------------------------------------------

local KINDS = SetOf(P.Situation.KINDS)
local SIZES = SetOf({ 'small', 'medium', 'large' })
local MODES = SetOf({ 'full', 'name', 'hidden' })

local function CleanArgs(value, report, path, depth)
	local t = type(value)
	if t == 'string' then
		return #value <= 64 and value or nil
	elseif t == 'number' then
		return Number(value, -1e9, 1e9, report, path)
	elseif t == 'boolean' then
		return value
	elseif t == 'table' and (depth or 0) < 2 then
		local out, n = {}, 0
		for key, item in pairs(value) do
			if n < 60 and (type(key) == 'number' or Key(key, 32)) then
				out[key] = CleanArgs(item, report, path, (depth or 0) + 1)
				n = n + 1
			else
				Drop(report, path)
			end
		end
		return out
	end
	Drop(report, path)
	return nil
end

---@param id any
---@param known? table<string, boolean> Extra style ids that are fine (styles in the same string)
---@return boolean
local function StyleKnown(id, known)
	if type(id) ~= 'string' or not Key(id, 48) then
		return false
	end
	return id == 'host' or Registry:Get(id) ~= nil or (known ~= nil and known[id] == true)
end

---Check a "When" list. Entries that name a style nobody has lose that style (and count as dropped).
---@param list any
---@param report Plates.ValidationReport
---@param known? table<string, boolean>
---@return table[] cleaned
local function CleanWhenList(list, report, known)
	local out = {}
	if type(list) ~= 'table' then
		Drop(report, 'when')
		return out
	end
	for index, entry in ipairs(list) do
		local here = 'when.' .. index
		if #out >= 40 then
			Drop(report, here)
		elseif type(entry) ~= 'table' then
			Drop(report, here)
		else
			local clean = {}
			if type(entry.conditions) == 'table' then
				local conditions = {}
				for _, clause in ipairs(entry.conditions) do
					if type(clause) == 'table' and type(clause.id) == 'string' and P.Conditions:Get(clause.id) and #conditions < 8 then
						local item = { id = clause.id }
						if clause.args ~= nil then
							item.args = CleanArgs(clause.args, report, here .. '.args')
						end
						if clause.negate == true then
							item.negate = true
						end
						conditions[#conditions + 1] = item
					else
						Drop(report, here .. '.conditions')
					end
				end
				clean.conditions = conditions
			end
			if type(entry.kinds) == 'table' then
				local kinds = {}
				for _, kind in ipairs(entry.kinds) do
					if KINDS[kind] then
						kinds[#kinds + 1] = kind
					else
						Drop(report, here .. '.kinds')
					end
				end
				clean.kinds = kinds
			end
			if entry.style ~= nil then
				if StyleKnown(entry.style, known) then
					clean.style = entry.style
				else
					Drop(report, here .. '.style')
				end
			end
			if entry.size ~= nil then
				clean.size = OneOf(entry.size, SIZES, report, here .. '.size')
			end
			if entry.mode ~= nil then
				clean.mode = OneOf(entry.mode, MODES, report, here .. '.mode')
			end
			if entry.off == true then
				clean.off = true
			end
			out[#out + 1] = clean
		end
	end
	return out
end

---Check a "When" payload { when = list }.
---@param payload table
---@return table[] cleaned
---@return Plates.ValidationReport report
function Exchange:CleanWhen(payload)
	local report = NewReport()
	return CleanWhenList(type(payload) == 'table' and payload.when or nil, report), report
end

----------------------------------------------------------------------------------------------------
-- Profile
----------------------------------------------------------------------------------------------------

local BEHAVIOR_BOOLS = SetOf({ 'friendlyPlayers', 'friendlyNPCs', 'friendlyNames', 'pinScale', 'clickThroughFriendly', 'onlyFighting' })
local BEHAVIOR_UNIT = SetOf({ 'fadeBehindWalls', 'fadeBehindWallsCombat', 'rangeFade' })

local function CleanBehaviorSet(source, report, path, withPlaces)
	local out = {}
	for key, item in pairs(source) do
		local here = path .. '.' .. tostring(key)
		if key == 'enemies' then
			out.enemies = OneOf(item, SetOf({ 'always', 'combat' }), report, here)
		elseif BEHAVIOR_BOOLS[key] then
			out[key] = Boolean(item, report, here)
		elseif BEHAVIOR_UNIT[key] then
			out[key] = Number(item, 0, 1, report, here)
		elseif key == 'rangeYards' then
			out.rangeYards = Number(item, 5, 100, report, here)
		elseif key == 'stacking' and type(item) == 'table' then
			local stacking = {}
			for side, on in pairs(item) do
				if (side == 'enemy' or side == 'friendly') and type(on) == 'boolean' then
					stacking[side] = on
				else
					Drop(report, here)
				end
			end
			out.stacking = stacking
		elseif key == 'places' and withPlaces and type(item) == 'table' then
			local places = {}
			for _, place in ipairs(P.Situation.PLACES) do
				if type(item[place]) == 'table' then
					places[place] = CleanBehaviorSet(item[place], report, here .. '.' .. place, false)
				end
			end
			out.places = places
		else
			Drop(report, here)
		end
	end
	return out
end

local function CleanAurasField(source, report)
	local out = {}
	local rows = SetOf(Schema.AURA_ROWS)
	rows.tankDebuffs = true
	for row, item in pairs(source) do
		local here = 'auras.' .. tostring(row)
		if rows[row] and type(item) == 'table' then
			local clean = {}
			for key, value in pairs(item) do
				if key == 'on' or key == 'onlyMine' or key == 'important' then
					clean[key] = Boolean(value, report, here .. '.' .. key)
				elseif key == 'always' or key == 'never' then
					clean[key] = SpellList(value, report, here .. '.' .. key)
				else
					Drop(report, here .. '.' .. tostring(key))
				end
			end
			out[row] = clean
		else
			Drop(report, here)
		end
	end
	return out
end

---The player's own settings a share string leaves out (role, game settings), checked, for a
---restore from the player's own backup (the host's full profile import).
---@param source table A profile
---@return table cleaned { role?, cvars? }
function Exchange:CleanOwnSettings(source)
	local report, out = NewReport(), {}
	if type(source) ~= 'table' then
		return out
	end
	if source.role ~= nil then
		out.role = OneOf(source.role, ROLES, report, 'profile.role')
	end
	if type(source.cvars) == 'table' then
		-- Only the game settings a page offers, with values of the right kind and range
		local cvars = {}
		for name, value in pairs(source.cvars) do
			local def = type(name) == 'string' and P.CVars.defs[name]
			local here = 'profile.cvars.' .. tostring(name)
			if def and def.page and def.kind == 'bool' then
				cvars[name] = Boolean(value, report, here)
			elseif def and def.page and def.kind == 'number' then
				cvars[name] = Number(tonumber(value), def.min or 0, def.max or 1000, report, here)
			end
		end
		out.cvars = next(cvars) and cvars or nil
	end
	return out
end

---Check a profile string's payload { profile, styles }. Styles come back checked and keyed by the
---ids they had in the string; the profile refers to those ids until Apply gives them new ones.
---@param payload table
---@return table|nil cleaned { profile, styles = { [oldId] = { name, base, source } } }
---@return Plates.ValidationReport report
---@return string|nil reason
function Exchange:CleanProfile(payload)
	local report = NewReport()
	if type(payload) ~= 'table' or type(payload.profile) ~= 'table' then
		return nil, report, 'decode'
	end
	local source = payload.profile
	-- Styles first: the profile may point at them
	local styles, known, count = {}, {}, 0
	if type(payload.styles) == 'table' then
		for id, entry in pairs(payload.styles) do
			local here = 'styles.' .. tostring(id)
			if Key(id, 48) and type(entry) == 'table' and count < 40 then
				local upgraded = Schema:Upgrade(type(entry.base) == 'table' and entry.base or {})
				local cleaned, styleReport = nil, nil
				if upgraded then
					cleaned, styleReport = Schema:ValidateStyle(upgraded)
				end
				if cleaned then
					report.dropped = report.dropped + styleReport.dropped
					report.clamped = report.clamped + styleReport.clamped
					report.fixed = report.fixed + styleReport.fixed
					cleaned.internal, cleaned.matchesHost = nil, nil
					local src = type(entry.source) == 'table' and entry.source or {}
					local source2 = { kind = 'import', styleId = cleaned.id }
					if src.kind == 'import' then
						local author = P.Gallery.CleanName(type(src.author) == 'string' and string.sub(src.author, 1, 48) or nil)
						source2.author = author ~= '' and author or nil
						source2.version = tonumber(src.version)
						source2.styleId = type(src.styleId) == 'string' and string.sub(src.styleId, 1, 48) or cleaned.id
					end
					local name = P.Gallery.CleanName(type(entry.name) == 'string' and string.sub(entry.name, 1, 48) or cleaned.name)
					styles[id] = { name = name ~= '' and name or L['Imported style'], base = cleaned, source = source2 }
					known[id] = true
					count = count + 1
				else
					Drop(report, here)
				end
			else
				Drop(report, here)
			end
		end
	end

	local profile = {}
	local allowed = SetOf(Exchange.PROFILE_KEYS)
	for key, item in pairs(source) do
		if not allowed[key] then
			Drop(report, 'profile.' .. tostring(key))
		elseif key == 'style' then
			if StyleKnown(item, known) then
				profile.style = item
			else
				Drop(report, 'profile.style')
			end
		elseif key == 'size' then
			profile.size = OneOf(item, SIZES, report, 'profile.size')
		elseif key == 'assign' and type(item) == 'table' then
			local assign = {}
			for kind, styleId in pairs(item) do
				if KINDS[kind] and StyleKnown(styleId, known) then
					assign[kind] = styleId
				else
					Drop(report, 'profile.assign')
				end
			end
			profile.assign = assign
		elseif key == 'modes' and type(item) == 'table' then
			local modes = {}
			for kind, mode in pairs(item) do
				if KINDS[kind] and MODES[mode] then
					modes[kind] = mode
				else
					Drop(report, 'profile.modes')
				end
			end
			profile.modes = modes
		elseif key == 'when' then
			profile.when = CleanWhenList(item, report, known)
		elseif key == 'tweaks' and type(item) == 'table' then
			local tweaks, n = {}, 0
			for styleId, overlay in pairs(item) do
				if StyleKnown(styleId, known) and styleId ~= 'host' and type(overlay) == 'table' and n < 40 then
					local upgraded = Schema:UpgradeOverlay(overlay)
					local base = known[styleId] and styles[styleId].base or Registry:Get(styleId)
					local cleaned, overlayReport = nil, nil
					if upgraded then
						cleaned, overlayReport = Schema:ValidateOverlay(upgraded, base and base.parts)
					end
					if cleaned and next(cleaned) then
						report.dropped = report.dropped + overlayReport.dropped
						report.clamped = report.clamped + overlayReport.clamped
						tweaks[styleId] = cleaned
						n = n + 1
					else
						Drop(report, 'profile.tweaks.' .. tostring(styleId))
					end
				else
					Drop(report, 'profile.tweaks')
				end
			end
			profile.tweaks = tweaks
		elseif key == 'scheme' or key == 'colors' or key == 'threat' or key == 'colorBlind' then
			-- handled together below
		elseif key == 'behavior' and type(item) == 'table' then
			profile.behavior = CleanBehaviorSet(item, report, 'profile.behavior', true)
		elseif key == 'auras' and type(item) == 'table' then
			profile.auras = CleanAurasField(item, report)
		else
			Drop(report, 'profile.' .. tostring(key))
		end
	end
	for key, value in pairs(CleanColorFields(source, report)) do
		profile[key] = value
	end
	return { profile = profile, styles = styles }, report
end

----------------------------------------------------------------------------------------------------
-- Counting what an import does to the player's changes
----------------------------------------------------------------------------------------------------

local function Leaves(t)
	local n = 0
	for _, value in pairs(t) do
		if type(value) == 'table' and not util.IsList(value) then
			n = n + Leaves(value)
		else
			n = n + 1
		end
	end
	return n
end

---How many separate settings the player changed on a style ("Your 4 changes stay").
---@param overlay table|nil profile.tweaks[styleId]
---@return integer
function Exchange.CountChanges(overlay)
	if type(overlay) ~= 'table' then
		return 0
	end
	local n = 0
	local changes = overlay.changes or {}
	for _, part in pairs(changes.parts or {}) do
		n = n + math.max(Leaves(part), 1)
	end
	for _, key in ipairs({ 'plate', 'states', 'tokens', 'regions' }) do
		if type(changes[key]) == 'table' then
			n = n + Leaves(changes[key])
		end
	end
	n = n + Count(overlay.add or {}) + Count(overlay.remove or {})
	for _, patch in pairs(overlay.situations or {}) do
		n = n + math.max(Leaves(patch), 1)
	end
	return n
end

----------------------------------------------------------------------------------------------------
-- Reading a string
----------------------------------------------------------------------------------------------------

---Player-facing text for a failure.
---@param reason string
---@return string
function Exchange:ReasonText(reason)
	if reason == 'tooLong' then
		return L['That text is too long to be a nameplate share string.']
	elseif reason == 'empty' then
		return L['Paste a share string first.']
	elseif reason == 'format' or reason == 'decode' then
		return L['This text is not a nameplate share string.']
	end
	return P.Share:ReasonText(reason)
end

---@class Plates.ExchangeInfo
---@field kind 'style'|'colors'|'when'|'profile'
---@field report table dropped, clamped, fixed, droppedKeys
---@field style? table Cleaned style (kind style)
---@field name? string
---@field author? string
---@field version? integer
---@field updateOf? string Saved style this string updates
---@field isNewer? boolean The string has a newer version than the saved copy
---@field keepCount? integer The player's changes that stay on an update
---@field payload? table Cleaned payload (colors, when, profile)
---@field count? integer Entries in a "When" list, styles in a profile

---The saved copy of a shared style that a string with this style id, author and version belongs
---to. With several copies the most advanced one counts: when it already has this version (or a
---newer one) nothing is newer, otherwise it is the copy that gets the update.
---@param styleId string
---@param author? string
---@param version integer
---@return string|nil savedId
---@return boolean|nil isNewer
function Exchange:FindImported(styleId, author, version)
	local best, bestVersion
	for id, entry in pairs(P.Store:Get('styles', 'global') or {}) do
		local source = type(entry) == 'table' and entry.source or nil
		if source and source.kind == 'import' and source.styleId == styleId and source.author == author then
			local have = tonumber(source.version) or 0
			if best == nil or have > bestVersion or (have == bestVersion and id < best) then
				best, bestVersion = id, have
			end
		end
	end
	if best == nil then
		return nil, nil
	end
	return best, bestVersion < (tonumber(version) or 1)
end

---Read a share string without changing anything. A string that breaks the reader (a table nested
---too deep to copy, say) is refused like any other text that is not a share string.
---@param text any
---@return Plates.ExchangeInfo|nil info
---@return string|nil reason 'empty' | 'tooLong' | the reasons of P.Share:Decode and Schema
function Exchange:Inspect(text)
	local ok, info, reason = pcall(self.Read, self, text)
	if not ok then
		P.log.error('A share string could not be read: ' .. tostring(info))
		return nil, 'decode'
	end
	return info, reason
end

---@param text any
---@return Plates.ExchangeInfo|nil info
---@return string|nil reason
function Exchange:Read(text)
	if type(text) ~= 'string' or string.find(text, '^%s*$') then
		return nil, 'empty'
	end
	if #text > self.MAX_LENGTH then
		return nil, 'tooLong'
	end
	local decoded, reason = P.Share:Decode(text)
	if not decoded then
		return nil, reason
	end
	local kind = decoded.kind
	if kind == 'style' then
		local preview, why = P.Share:InspectDecoded(decoded)
		if not preview then
			return nil, why
		end
		preview.style.internal, preview.style.matchesHost = nil, nil
		local author = P.Gallery.CleanName(preview.author)
		local info = {
			kind = 'style',
			style = preview.style,
			name = P.Gallery.CleanName(preview.name) ~= '' and P.Gallery.CleanName(preview.name) or L['Imported style'],
			author = author ~= '' and author or nil,
			version = preview.version,
			report = preview.report,
		}
		info.updateOf, info.isNewer = self:FindImported(preview.style.id, info.author, preview.version)
		if info.updateOf then
			info.keepCount = self.CountChanges(P.Store:Get({ 'tweaks', info.updateOf }))
		end
		return info
	elseif kind == 'colors' then
		local cleaned, report = self:CleanColors(decoded.payload)
		return { kind = 'colors', payload = cleaned, report = report, count = Count(cleaned) }
	elseif kind == 'when' then
		local cleaned, report = self:CleanWhen(decoded.payload)
		return { kind = 'when', payload = cleaned, report = report, count = #cleaned }
	elseif kind == 'profile' then
		local cleaned, report, why = self:CleanProfile(decoded.payload)
		if not cleaned then
			return nil, why
		end
		return { kind = 'profile', payload = cleaned, report = report, count = Count(cleaned.styles) }
	end
	return nil, 'kind'
end

local function Plural(n, one, many)
	if n == 1 then
		return one
	end
	return string.format(many, n)
end

---Lines that tell the player what a string holds and what using it does.
---@param info Plates.ExchangeInfo
---@return string[]
function Exchange:Describe(info)
	local lines = {}
	if info.kind == 'style' then
		local who = info.author and info.author ~= '' and string.format(L['"%s" by %s, version %s.'], info.name, info.author, tostring(info.version or 1))
			or string.format(L['"%s", version %s.'], info.name, tostring(info.version or 1))
		lines[#lines + 1] = who
		if info.updateOf then
			if info.isNewer then
				lines[#lines + 1] = string.format(L['Update to version %s.'], tostring(info.version or 1)) .. ' ' .. Plural(info.keepCount or 0, L['Your 1 change stays.'], L['Your %d changes stay.'])
			else
				lines[#lines + 1] = L['You already have this version.']
			end
		end
	elseif info.kind == 'colors' then
		lines[#lines + 1] = L['A set of colors. Using it replaces your own colors.']
	elseif info.kind == 'when' then
		lines[#lines + 1] = Plural(info.count or 0, L['A list with 1 special case. Using it replaces your special cases.'], L['A list with %d special cases. Using it replaces your special cases.'])
	elseif info.kind == 'profile' then
		lines[#lines + 1] = Plural(
			info.count or 0,
			L['All nameplate settings, with 1 style. Using it replaces the settings in this profile.'],
			L['All nameplate settings, with %d styles. Using it replaces the settings in this profile.']
		)
	end
	local report = info.report or {}
	if (report.dropped or 0) > 0 then
		lines[#lines + 1] = Plural(report.dropped, L['1 setting was not recognized and was left out.'], L['%d settings were not recognized and were left out.'])
	end
	if (report.clamped or 0) > 0 then
		lines[#lines + 1] = Plural(report.clamped, L['1 value was out of range and was adjusted.'], L['%d values were out of range and were adjusted.'])
	end
	if (report.fixed or 0) > 0 then
		lines[#lines + 1] =
			Plural(report.fixed, L['1 part pointed at a part that does not exist. It now sits on the plate.'], L['%d parts pointed at parts that do not exist. They now sit on the plate.'])
	end
	return lines
end

----------------------------------------------------------------------------------------------------
-- Pasted text on the Sharing page
----------------------------------------------------------------------------------------------------

---What the Sharing page has been given: info or reason, and the line after the last action.
Exchange.state = { info = nil, reason = nil, result = nil }

---Read pasted text and show a pasted style in the preview panel.
---@param text any
---@return Plates.ExchangeInfo|nil info
---@return string|nil reason
function Exchange:Paste(text)
	local state = self.state
	state.result = nil
	local info, reason = self:Inspect(text)
	state.info, state.reason = info, info and nil or reason
	if reason == 'empty' then
		state.reason = nil
	end
	if info and info.kind == 'style' then
		P.Gallery:SetPreview({ style = info.style, name = info.name, author = info.author, version = info.version })
	else
		P.Gallery:ClearPreview()
	end
	P:Fire('EXCHANGE_CHANGED')
	return info, state.reason
end

---Forget the pasted text and stop previewing it.
function Exchange:Clear()
	local state = self.state
	state.info, state.reason = nil, nil
	P.Gallery:ClearPreview()
	P:Fire('EXCHANGE_CHANGED')
end

-- The preview panel clears the pasted style when it hides. The string is still waiting on the
-- page, so it is shown again when the panel comes back. (Paste, Clear and Do empty state.info
-- before they clear the preview, so a clear of their own is left alone.)
P:On('GALLERY_PREVIEW', function(preview)
	local info = Exchange.state.info
	if preview == nil and info and info.kind == 'style' then
		P.Gallery:SetPreview({ style = info.style, name = info.name, author = info.author, version = info.version })
	end
end, Exchange)

----------------------------------------------------------------------------------------------------
-- Using a string
----------------------------------------------------------------------------------------------------

local function ImportSource(info)
	return { kind = 'import', author = info.author, version = info.version, styleId = info.style.id }
end

---@class Plates.ExchangeResult
---@field ok boolean
---@field id? string Style id saved, updated or picked
---@field name? string
---@field updated? boolean
---@field unchanged? boolean An update that was not newer: nothing changed
---@field keptChanges? integer
---@field staleChanges? integer
---@field message string Player sentence

---Save a style string. mode 'new' adds a style (never overwrites), 'update' replaces the base of
---the copy the string updates and keeps the player's changes, 'use' adds (or finds) the style and
---picks it. The player's own name for the style wins over the string's name.
---@param info Plates.ExchangeInfo
---@param mode 'new'|'update'|'use'
---@param name? string
---@return Plates.ExchangeResult
function Exchange:ApplyStyle(info, mode, name)
	local id
	local result = { ok = true }
	if mode == 'update' and info.updateOf then
		if not info.isNewer then
			result.id, result.unchanged = info.updateOf, true
			result.name = Registry:Get(info.updateOf) and Registry:Get(info.updateOf).name
			result.message = L['You already have this version.']
			return result
		end
		Registry:UpdateSaved(info.updateOf, info.style, ImportSource(info))
		id = info.updateOf
		result.updated = true
		result.keptChanges = info.keepCount or 0
		result.staleChanges = Merge:StaleChanges(id)
	elseif mode == 'use' and info.updateOf and not info.isNewer then
		id = info.updateOf
	else
		id = Registry:Save(info.style, P.Gallery:UniqueName(name or info.name or L['Imported style']), ImportSource(info))
	end
	local style = Registry:Get(id)
	result.id, result.name = id, style and style.name or info.name
	if mode == 'use' then
		P.Store:Set('style', id)
		result.message = string.format(L['Using "%s" now.'], result.name)
	elseif result.updated then
		result.message = string.format(L['Updated "%s" to version %s.'], result.name, tostring(info.version or 1))
			.. ' '
			.. Plural(result.keptChanges, L['Your 1 change stays.'], L['Your %d changes stay.'])
		if result.staleChanges > 0 then
			result.message = result.message
				.. ' '
				.. Plural(
					result.staleChanges,
					L['1 of your changes no longer applies. It stays until you undo your changes.'],
					L['%d of your changes no longer apply. They stay until you undo your changes.']
				)
		end
	else
		result.message = string.format(L['Added "%s" to your styles.'], result.name)
	end
	return result
end

local function SnapshotKeys(keys)
	local snapshot = {}
	for _, key in ipairs(keys) do
		snapshot[key] = util.Copy(P.Store:Get(key))
	end
	return snapshot
end

local function RestoreKeys(snapshot, keys)
	P.Store:Batch(function()
		for _, key in ipairs(keys) do
			P.Store:Set(key, util.Copy(snapshot[key]))
		end
	end)
end

local COLOR_KEYS = { 'scheme', 'colors', 'threat', 'colorBlind' }

---Replace the colors, the "When" list or the profile settings with what a string holds.
---@param info Plates.ExchangeInfo
---@return Plates.ExchangeResult
function Exchange:ApplyReplace(info)
	local Store = P.Store
	if info.kind == 'colors' then
		local snapshot = SnapshotKeys(COLOR_KEYS)
		Store:Batch(function()
			for _, key in ipairs(COLOR_KEYS) do
				Store:Set(key, util.Copy(info.payload[key]))
			end
		end)
		self.undo = {
			label = L['colors'],
			restore = function()
				RestoreKeys(snapshot, COLOR_KEYS)
			end,
		}
		return { ok = true, message = L['Using these colors now.'] }
	elseif info.kind == 'when' then
		local snapshot = SnapshotKeys({ 'when' })
		local list = util.Copy(info.payload)
		Store:Set('when', #list > 0 and list or nil)
		self.undo = {
			label = L['special cases'],
			restore = function()
				RestoreKeys(snapshot, { 'when' })
			end,
		}
		return { ok = true, message = L['Using these special cases now.'] }
	elseif info.kind == 'profile' then
		return self:ApplyProfile(info)
	end
	return { ok = false, message = self:ReasonText('kind') }
end

---Use a profile string: its styles are saved (a style that is an update of one you have updates
---it), the profile's references move to the new ids, and every setting in the string replaces
---yours.
---@param info Plates.ExchangeInfo
---@return Plates.ExchangeResult
function Exchange:ApplyProfile(info)
	local Store = P.Store
	local keys = self.PROFILE_KEYS
	local snapshot = SnapshotKeys(keys)
	local profile = util.Copy(info.payload.profile)
	local added, map = {}, {}
	for oldId, entry in pairs(info.payload.styles) do
		local existing, isNewer
		if entry.source.author ~= nil then
			existing, isNewer = self:FindImported(entry.source.styleId, entry.source.author, entry.source.version)
		end
		if existing then
			if isNewer then
				Registry:UpdateSaved(existing, entry.base, entry.source)
			end
			map[oldId] = existing
		else
			local newId = Registry:Save(entry.base, P.Gallery:UniqueName(entry.name), entry.source)
			map[oldId] = newId
			added[#added + 1] = newId
		end
	end
	local function Mapped(id)
		return map[id] or id
	end
	if profile.style then
		profile.style = Mapped(profile.style)
	end
	for kind, id in pairs(profile.assign or {}) do
		profile.assign[kind] = Mapped(id)
	end
	for _, entry in ipairs(profile.when or {}) do
		if entry.style then
			entry.style = Mapped(entry.style)
		end
	end
	if profile.tweaks then
		local tweaks = {}
		for id, overlay in pairs(profile.tweaks) do
			tweaks[Mapped(id)] = overlay
		end
		profile.tweaks = tweaks
	end
	Store:Batch(function()
		for _, key in ipairs(keys) do
			Store:Set(key, profile[key])
		end
	end)
	self.undo = {
		label = L['settings'],
		restore = function()
			RestoreKeys(snapshot, keys)
			for _, id in ipairs(added) do
				Registry:Delete(id)
			end
		end,
	}
	return { ok = true, message = L['Using these settings now.'], added = #added }
end

---@return boolean
function Exchange:HasUndo()
	return self.undo ~= nil
end

-- The undo belongs to the profile it was made on: after a switch, copy or reset it would write
-- that profile's old values into another one
P:On('PROFILE_CHANGED', function()
	if Exchange.undo then
		Exchange.undo = nil
		P:Fire('EXCHANGE_CHANGED')
	end
end, Exchange)

---Put back what the last replace changed.
---@return boolean undone
function Exchange:Undo()
	local undo = self.undo
	if not undo then
		return false
	end
	self.undo = nil
	undo.restore()
	P:Fire('EXCHANGE_CHANGED')
	return true
end

---Use the pasted string the Sharing page holds.
---@param action 'new'|'update'|'use'|'replace'
---@return Plates.ExchangeResult
function Exchange:Do(action)
	local state = self.state
	local info = state.info
	if not info then
		return { ok = false, message = L['Paste a share string first.'] }
	end
	local result
	if info.kind == 'style' then
		result = self:ApplyStyle(info, action)
	else
		result = self:ApplyReplace(info)
	end
	if result.ok then
		state.info, state.reason = nil, nil
		P.Gallery:ClearPreview()
	end
	state.result = result.message
	P:Fire('EXCHANGE_CHANGED')
	return result
end

----------------------------------------------------------------------------------------------------
-- Making a string
----------------------------------------------------------------------------------------------------

---The name written on strings the player makes (account-wide, optional).
---@return string
function Exchange:GetAuthor()
	local author = P.Store:Get('author', 'global')
	return type(author) == 'string' and author or ''
end

---@param name string
function Exchange:SetAuthor(name)
	name = string.sub(P.Gallery.CleanName(name), 1, 48)
	P.Store:Set('author', name ~= '' and name or nil, 'global', {})
end

local function SavedStyleIds(profile)
	local ids, seen = {}, {}
	local function Add(id)
		if type(id) == 'string' and not seen[id] and Registry:IsSaved(id) then
			seen[id] = true
			ids[#ids + 1] = id
		end
	end
	Add(profile.style)
	for _, id in pairs(profile.assign or {}) do
		Add(id)
	end
	for _, entry in ipairs(profile.when or {}) do
		Add(entry.style)
	end
	for id in pairs(profile.tweaks or {}) do
		Add(id)
	end
	table.sort(ids)
	return ids
end

---Make a share string.
---@param what 'style'|'colors'|'when'|'everything'
---@param opts? { styleId?: string, version?: integer, author?: string }
---@return string|nil text
---@return string|nil reason 'missing' | 'unavailable' | 'encode' | 'kind'
function Exchange:BuildExport(what, opts)
	opts = opts or {}
	local Store = P.Store
	if what == 'style' then
		local id = Registry:ResolveId(opts.styleId or Store:Get('style'))
		local baked = Merge:Bake(id)
		if not baked then
			return nil, 'missing'
		end
		baked.internal, baked.matchesHost = nil, nil
		local author = opts.author
		if author == nil then
			author = self:GetAuthor()
		end
		return P.Share:Encode('style', { style = baked, name = baked.name, author = author ~= '' and author or nil, version = opts.version or baked.version or 1 })
	elseif what == 'colors' then
		return P.Share:Encode('colors', {
			scheme = Store:Get('scheme'),
			colors = Store:Get('colors'),
			threat = Store:Get('threat'),
			colorBlind = Store:Get('colorBlind'),
		})
	elseif what == 'when' then
		return P.Share:Encode('when', { when = Store:Get('when') or {} })
	elseif what == 'everything' then
		local profile = {}
		for _, key in ipairs(self.PROFILE_KEYS) do
			profile[key] = util.Copy(Store:Get(key))
		end
		local styles = {}
		for _, id in ipairs(SavedStyleIds(profile)) do
			local entry = Store:Get({ 'styles', id }, 'global')
			if type(entry) == 'table' then
				styles[id] = { name = entry.name, schema = entry.schema, base = util.Copy(entry.base), source = util.Copy(entry.source) }
			end
		end
		return P.Share:Encode('profile', { profile = profile, styles = styles })
	end
	return nil, 'kind'
end

----------------------------------------------------------------------------------------------------
-- Public API (P.API:ImportStyle)
----------------------------------------------------------------------------------------------------

---Import a shared style string, for UI pack authors and other addons.
---  P.API:ImportStyle(text, name, opts) -> id, nil, info   or   nil, reason, info
--- name  the player-facing name; defaults to the name in the string
--- opts.update  when the string is a newer version of a style this player imported before (same
---              author and style), replace that style's base and keep the player's changes;
---              otherwise a new style is added. Without it a style is never overwritten.
--- opts.use     also pick the style
--- info         { name, author, version, updated, unchanged, dropped, droppedKeys, clamped,
---              keptChanges, staleChanges, message } (info.author and info.version come from the string)
---@param text string
---@param name? string
---@param opts? { update?: boolean, use?: boolean }
---@return string|nil styleId
---@return string|nil reason
---@return table|nil info
function P.API:ImportStyle(text, name, opts)
	opts = type(opts) == 'table' and opts or {}
	local info, reason = Exchange:Inspect(text)
	if not info then
		return nil, reason
	end
	if info.kind ~= 'style' then
		return nil, 'kind'
	end
	local mode = (opts.update and info.updateOf) and 'update' or 'new'
	local result = Exchange:ApplyStyle(info, mode, name)
	if opts.use and result.id then
		P.Store:Set('style', result.id)
	end
	return result.id,
		nil,
		{
			name = result.name,
			author = info.author,
			version = info.version,
			updated = result.updated or false,
			unchanged = result.unchanged or false,
			dropped = info.report.dropped,
			droppedKeys = util.Copy(info.report.droppedKeys),
			clamped = info.report.clamped,
			keptChanges = result.keptChanges,
			staleChanges = result.staleChanges,
			message = result.message,
		}
end
