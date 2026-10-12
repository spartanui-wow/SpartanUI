local _, ns = ...
local P = ns.Plates
local util = P.util

-- Sparse reads and writes by path, plus change messages with refresh reasons (5.2).
-- Rules:
--   * Options get/set call Store:Get/Store:Set on every call and never keep sub-tables
--     (pitfalls 2026-10-01: profile switches replace tables).
--   * Writing nil removes the key and prunes empty parent tables, so the profile only ever holds
--     what the player changed. A top-level key with an AceDB default (style, size, role, scheme,
--     colorBlind, enabled, followHostProfile) goes back to that default instead: AceDB has no
--     fallback for plain defaults until the next profile load, so nil would read as nil. Use
--     Store:Reset for "back to default"; AceDB strips the default again when it saves.
--   * Lists (color orders, "When" entries, spell lists) are written whole; never merged by index.
--   * Every successful write fires P:Fire('STORE_CHANGED', reasons, keys, scope), where reasons is
--     a set such as { look = true, size = true }. A profile switch fires the union of the reasons
--     of every top-level key whose value differs between the two profiles.

---@class Plates.Store
local Store = {}
P.Store = Store

local R = P.REASON

local function Set(...)
	local out = {}
	for i = 1, select('#', ...) do
		out[select(i, ...)] = true
	end
	return out
end

---Refresh reasons by top-level profile key. Unknown keys default to { look }.
Store.REASONS = {
	profile = {
		enabled = P.ALL_REASONS,
		style = Set(R.LOOK, R.SIZE, R.AURAS, R.ASSIGNMENT),
		size = Set(R.SIZE, R.LOOK),
		assign = Set(R.ASSIGNMENT, R.SIZE, R.AURAS),
		modes = Set(R.ASSIGNMENT),
		when = Set(R.ASSIGNMENT, R.SIZE, R.AURAS),
		tweaks = Set(R.LOOK, R.SIZE, R.AURAS),
		scheme = Set(R.COLORS),
		colors = Set(R.COLORS),
		colorBlind = Set(R.COLORS),
		threat = Set(R.COLORS, R.LOOK),
		role = Set(R.COLORS, R.LOOK),
		casts = Set(R.LOOK, R.COLORS),
		behavior = Set(R.ASSIGNMENT, R.CVARS),
		auras = Set(R.AURAS),
		cvars = Set(R.CVARS),
		followHostProfile = {},
		schema = {},
		migratedFromOld = {},
		actions = Set(R.ASSIGNMENT, R.COLORS),
	},
	global = {
		styles = Set(R.LOOK, R.SIZE, R.AURAS),
		capOverrides = Set(R.LOOK, R.AURAS),
		cvarBackup = {},
		seen = {},
		schema = {},
		migratedFromOld = {},
	},
	char = {
		engine = {},
		cvarBackup = {},
	},
}
local DEFAULT_REASONS = Set(R.LOOK)

---@param a table|nil
---@param b table|nil
---@return table union (new table)
function Store.Union(a, b)
	local out = {}
	for k in pairs(a or {}) do
		out[k] = true
	end
	for k in pairs(b or {}) do
		out[k] = true
	end
	return out
end

---@param scope? 'profile'|'global'|'char'
---@return table|nil
local function Root(scope)
	local db = P.db
	if not db then
		return nil
	end
	return db[scope or 'profile']
end

---Refresh reasons for a write to `path` in `scope`.
---@param path string|table
---@param scope? 'profile'|'global'|'char'
---@return table reasons
function Store:ReasonsFor(path, scope)
	local keys = util.SplitPath(path)
	local byKey = self.REASONS[scope or 'profile'] or {}
	return byKey[keys[1]] or DEFAULT_REASONS
end

---Read a value. Never cache the returned table; read again on every call.
---@param path string|table 'tweaks.clean.changes' or { 'tweaks', 'clean', 'changes' }
---@param scope? 'profile'|'global'|'char'
---@return any
function Store:Get(path, scope)
	local node = Root(scope)
	local keys = util.SplitPath(path)
	for i = 1, #keys do
		if type(node) ~= 'table' then
			return nil
		end
		node = node[keys[i]]
	end
	return node
end

local function Prune(root, keys)
	-- Walk down remembering parents, then remove empty tables from the deepest up
	local parents = { root }
	local node = root
	for i = 1, #keys - 1 do
		node = node[keys[i]]
		if type(node) ~= 'table' then
			return
		end
		parents[#parents + 1] = node
	end
	for i = #keys - 1, 1, -1 do
		local child = parents[i + 1]
		if next(child) == nil then
			parents[i][keys[i]] = nil
		else
			return
		end
	end
end

local pendingReasons, pendingKeys

---Write a value (nil removes it). Tables are copied in, so callers may keep editing theirs.
---Returns true when something changed.
---@param path string|table
---@param value any
---@param scope? 'profile'|'global'|'char'
---@param reasons? table Override the reasons looked up from Store.REASONS
---@return boolean changed
function Store:Set(path, value, scope, reasons)
	local root = Root(scope)
	if not root then
		return false
	end
	local keys = util.SplitPath(path)
	assert(#keys > 0, 'Store:Set needs a path')
	if value == nil and #keys == 1 then
		local defaults = P.Config:Defaults()[scope or 'profile']
		if defaults and defaults[keys[1]] ~= nil then
			value = defaults[keys[1]]
		end
	end
	local current = self:Get(keys, scope)
	if util.Equal(current, value) then
		return false
	end
	local node = root
	for i = 1, #keys - 1 do
		local key = keys[i]
		if type(node[key]) ~= 'table' then
			if value == nil then
				return false
			end
			node[key] = {}
		end
		node = node[key]
	end
	node[keys[#keys]] = util.Copy(value)
	if value == nil then
		Prune(root, keys)
	end

	reasons = reasons or self:ReasonsFor(keys, scope)
	if pendingReasons then
		for k in pairs(reasons) do
			pendingReasons[k] = true
		end
		pendingKeys[#pendingKeys + 1] = keys
	else
		P:Fire('STORE_CHANGED', reasons, keys, scope or 'profile')
	end
	return true
end

---Put a setting back to its default: the AceDB default for top-level keys that have one,
---otherwise remove it.
---@param path string|table
---@param scope? 'profile'|'global'|'char'
---@return boolean changed
function Store:Reset(path, scope)
	return self:Set(path, nil, scope)
end

---Run several writes and fire one STORE_CHANGED with the union of their reasons.
---@param fn fun()
function Store:Batch(fn)
	if pendingReasons then
		fn()
		return
	end
	pendingReasons, pendingKeys = {}, {}
	local ok, err = pcall(fn)
	local reasons, keys = pendingReasons, pendingKeys
	pendingReasons, pendingKeys = nil, nil
	if next(reasons) then
		P:Fire('STORE_CHANGED', reasons, keys, 'profile')
	end
	if not ok then
		error(err, 0)
	end
end

---@return string|nil
function Store:ProfileKey()
	return P.db and P.db:GetCurrentProfile() or nil
end

---Remember the current profile so a switch can compare old and new values.
function Store:Track()
	self.trackedKey = self:ProfileKey()
end

---Called by Config after AceDB switches, copies or resets the profile.
---@param forced? table Reasons to fire regardless of what changed
function Store:ProfileSwapped(forced)
	local db = P.db
	local reasons = forced and Store.Union(forced) or {}
	if not forced then
		local old = self.trackedKey and db.profiles and db.profiles[self.trackedKey] or {}
		local new = db.profile
		local byKey = self.REASONS.profile
		-- AceDB strips defaults from the profile it leaves and copies them into the one it opens,
		-- so a key missing from either side reads as its default
		local defaults = db.defaults and db.defaults.profile or {}
		local function Effective(profile, key)
			local value = profile[key]
			if value == nil then
				return defaults[key]
			end
			return value
		end
		local seen = {}
		for key in pairs(old) do
			seen[key] = true
		end
		for key in pairs(new) do
			seen[key] = true
		end
		for key in pairs(seen) do
			if not util.Equal(Effective(old, key), Effective(new, key)) then
				for reason in pairs(byKey[key] or DEFAULT_REASONS) do
					reasons[reason] = true
				end
			end
		end
	end
	self:Track()
	P:Fire('PROFILE_CHANGED', reasons)
	P:Fire('STORE_CHANGED', reasons, nil, 'profile')
end

---Switch to a profile by name (created when missing).
---@param name string
function Store:SetProfile(name)
	local db = P.db
	if db and name and name ~= '' and db:GetCurrentProfile() ~= name then
		db:SetProfile(name)
	end
end

---When the profile follows the host's profile name, switch to it. Called at initialize and by the
---host whenever its own profile changes.
function Store:FollowHostProfile()
	local db, host = P.db, P.host
	if not (db and host and host.GetHostProfileName) then
		return
	end
	if not db.profile.followHostProfile then
		return
	end
	local name = host.GetHostProfileName()
	if type(name) == 'string' then
		self:SetProfile(name)
	end
end
