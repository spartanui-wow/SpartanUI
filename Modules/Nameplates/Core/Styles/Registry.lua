local _, ns = ...
local P = ns.Plates
local Schema = P.Styles.Schema

-- The style library (5.2 layer 1). Three sources, in gallery order:
--   builtin  styles in code (Builtin_*.lua), trusted at runtime and validated by the headless test
--   host     styles the host registers through P.API:RegisterStyle ("Match my look", War art)
--   saved    styles the player made or imported, account-wide in global.styles[id]:
--            { name, schema, base = style, source = { kind = 'import'|'copy', author?, version? } }
-- 'host' is a pseudo id: it resolves to the host style marked matchesHost, else Clean.
-- Registry never returns the stored table itself for saved styles: it returns an upgraded copy,
-- cached until the library changes.

---@class Plates.Registry
local Registry = { builtin = {}, host = {}, order = {}, savedCache = {} }
P.Styles.Registry = Registry

Registry.FALLBACK_ID = 'clean'

---Register a built-in style (from Builtin_*.lua at file load).
---@param style table
function Registry:RegisterBuiltin(style)
	assert(type(style) == 'table' and type(style.id) == 'string', 'RegisterBuiltin needs a style with an id')
	style.schema = style.schema or Schema.CURRENT
	if not self.builtin[style.id] and not self.host[style.id] then
		self.order[#self.order + 1] = style.id
	end
	self.builtin[style.id] = style
end

---Register (or replace) a host style after validation.
---@param style table
---@return boolean ok
---@return string|nil reason
function Registry:RegisterHostStyle(style)
	local upgraded, why = Schema:Upgrade(style)
	if not upgraded then
		return false, why
	end
	local cleaned, report, reason = Schema:ValidateStyle(upgraded)
	if not cleaned then
		P.log.warning('Host style rejected: ' .. tostring(reason))
		return false, reason
	end
	if not cleaned.id or self.builtin[cleaned.id] then
		return false, 'badId'
	end
	if report.dropped > 0 then
		P.log.debug(string.format('Host style %s: %d settings were not recognized', cleaned.id, report.dropped))
	end
	if not self.host[cleaned.id] then
		self.order[#self.order + 1] = cleaned.id
	end
	self.host[cleaned.id] = cleaned
	P:Fire('STYLES_CHANGED', cleaned.id)
	P:Fire('STORE_CHANGED', { look = true, size = true, auras = true }, nil, 'global')
	return true
end

local function Saved()
	local db = P.db
	return db and db.global.styles or nil
end

---Turn the 'host' pseudo id (and unknown ids) into a real style id.
---@param id string|nil
---@return string
function Registry:ResolveId(id)
	if id == 'host' or id == nil then
		for _, styleId in ipairs(self.order) do
			local style = self.host[styleId]
			if style and style.matchesHost then
				return styleId
			end
		end
		return self.FALLBACK_ID
	end
	if self.builtin[id] or self.host[id] then
		return id
	end
	local saved = Saved()
	if saved and saved[id] then
		return id
	end
	return self.FALLBACK_ID
end

---Base style table for an id (after ResolveId). Read-only for callers.
---@param id string
---@return table|nil style
---@return 'builtin'|'host'|'saved'|nil source
function Registry:Get(id)
	if self.builtin[id] then
		return self.builtin[id], 'builtin'
	end
	if self.host[id] then
		return self.host[id], 'host'
	end
	local saved = Saved()
	local entry = saved and saved[id]
	if not entry or type(entry.base) ~= 'table' then
		return nil
	end
	local cached = self.savedCache[id]
	if cached and cached.entry == entry then
		return cached.style, 'saved'
	end
	local upgraded = Schema:Upgrade(entry.base)
	if not upgraded then
		return nil
	end
	upgraded.id = id
	upgraded.name = entry.name or upgraded.name
	self.savedCache[id] = { entry = entry, style = upgraded }
	return upgraded, 'saved'
end

---@class Plates.StyleListItem
---@field id string
---@field name string
---@field description? string
---@field source 'builtin'|'host'|'saved'
---@field matchesHost? boolean

---Every style for the gallery: built-ins and host styles in registration order (internal ones
---skipped unless asked), then saved and imported styles by name.
---@param includeInternal? boolean
---@return Plates.StyleListItem[]
function Registry:List(includeInternal)
	local out = {}
	for _, id in ipairs(self.order) do
		local style, source = self:Get(id)
		if style and (includeInternal or not style.internal) then
			out[#out + 1] = { id = id, name = style.name, description = style.description, source = source, matchesHost = style.matchesHost, order = style.order or 0 }
		end
	end
	local saved = {}
	for id, entry in pairs(Saved() or {}) do
		saved[#saved + 1] = { id = id, name = entry.name or id, source = 'saved', order = 0 }
	end
	table.sort(saved, function(a, b)
		return a.name < b.name
	end)
	for _, item in ipairs(saved) do
		out[#out + 1] = item
	end
	return out
end

---A short random id for a new saved style.
---@return string
function Registry:NewId()
	local saved = Saved() or {}
	local id
	repeat
		id = string.format('u%04x', math.random(0, 65535))
	until not saved[id] and not self.builtin[id] and not self.host[id]
	return id
end

---Save a style into the library (Make a copy, imports). Returns the new id.
---@param style table Already validated
---@param name string
---@param source? table { kind = 'import'|'copy', author?, version? }
---@return string id
function Registry:Save(style, name, source)
	local id = self:NewId()
	local base = P.util.Copy(style)
	base.id = id
	base.name = name
	P.Store:Set({ 'styles', id }, { name = name, schema = Schema.CURRENT, base = base, source = source or { kind = 'copy' } }, 'global')
	self.savedCache[id] = nil
	P:Fire('STYLES_CHANGED', id)
	return id
end

---Replace the base of a saved style (an import update). The player's overlay is untouched.
---@param id string
---@param style table Already validated
---@param source? table
function Registry:UpdateSaved(id, style, source)
	local saved = Saved()
	local entry = saved and saved[id]
	if not entry then
		return
	end
	local base = P.util.Copy(style)
	base.id = id
	base.name = entry.name
	P.Store:Set({ 'styles', id, 'base' }, base, 'global')
	if source then
		P.Store:Set({ 'styles', id, 'source' }, source, 'global')
	end
	self.savedCache[id] = nil
	P:Fire('STYLES_CHANGED', id)
end

---@param id string
---@param name string
function Registry:Rename(id, name)
	if Saved() and Saved()[id] then
		P.Store:Set({ 'styles', id, 'name' }, name, 'global')
		self.savedCache[id] = nil
		P:Fire('STYLES_CHANGED', id)
	end
end

---Delete a saved style (built-ins and host styles cannot be deleted).
---@param id string
function Registry:Delete(id)
	if Saved() and Saved()[id] then
		P.Store:Set({ 'styles', id }, nil, 'global')
		self.savedCache[id] = nil
		P:Fire('STYLES_CHANGED', id)
	end
end

---@param id string
---@return boolean
function Registry:IsSaved(id)
	local saved = Saved()
	return saved ~= nil and saved[id] ~= nil
end

P:On('STORE_CHANGED', function(_, _, scope)
	if scope == 'global' then
		P.util.Wipe(Registry.savedCache)
	end
end, Registry)
