local _, ns = ...
local P = ns.Plates

-- Numbered run-once patches (6.10, 7.1). Two kinds:
--
-- 1. Schema patches upgrade the data format of one scope ('profile' or 'global'). Patch N turns
--    schema N-1 into schema N. A stored schema of nil reads as 0 ("oldest"). Each patch stamps its
--    number as soon as it finishes, so a failed run resumes at the right place. New profiles are
--    stamped with the current number (Config) and never run old patches.
--
-- 2. Steps are named, idempotent jobs that run on every profile load until they report done.
--    They keep their own guards. The legacy import ("patch 1" in the plan, Phase 4a) is a step,
--    not a schema patch: the profile it serves is brand new in this database (the old module's
--    data lives in the host's database), so a schema stamp cannot guard it. Its guards are
--    profile.migratedFromOld and global.migratedFromOld[profileKey]; the second survives a profile
--    reset, so a reset profile is never re-imported.
--
-- Styles and overlays have their own upgrade chain in Core/Styles/Schema.lua.
-- Every patch and step must give the same result when run twice (SavedVariable writes were once
-- unreliable on Forever).

---@class Plates.Migrate
local Migrate = { patches = { profile = {}, global = {} }, steps = {}, stepOrder = {} }
P.Migrate = Migrate

---@param scope 'profile'|'global'
---@param number integer Upgrades schema number-1 to number
---@param fn fun(data: table, profileKey?: string)
function Migrate:AddPatch(scope, number, fn)
	assert(self.patches[scope], 'Migrate:AddPatch: unknown scope ' .. tostring(scope))
	assert(not self.patches[scope][number], 'Migrate:AddPatch: patch ' .. number .. ' already exists for ' .. scope)
	self.patches[scope][number] = fn
end

---Add a run-once step for profiles. fn(profile, profileKey, global) must be idempotent.
---@param id string
---@param fn fun(profile: table, profileKey: string, global: table)
function Migrate:AddStep(id, fn)
	if not self.steps[id] then
		self.stepOrder[#self.stepOrder + 1] = id
	end
	self.steps[id] = fn
end

local function RunChain(scope, data, target, profileKey)
	local current = tonumber(data.schema) or 0
	if current > target then
		P.log.warning(string.format('Nameplate %s data is newer (%d) than this version understands (%d); leaving it alone', scope, current, target))
		return
	end
	for number = current + 1, target do
		local patch = Migrate.patches[scope][number]
		if patch then
			local ok, err = pcall(patch, data, profileKey)
			if not ok then
				P.log.error(string.format('Nameplate %s patch %d failed: %s', scope, number, tostring(err)))
				return
			end
		end
		data.schema = number
	end
end

---Run global schema patches. Safe on a fresh install (nil schema).
function Migrate:RunGlobal()
	local db = P.db
	if not db then
		return
	end
	RunChain('global', db.global, P.Config.SCHEMA.global)
end

---Run profile schema patches and steps on the current profile.
function Migrate:RunProfile()
	local db = P.db
	if not db then
		return
	end
	local profile = db.profile
	local key = db:GetCurrentProfile()
	RunChain('profile', profile, P.Config.SCHEMA.profile, key)
	for _, id in ipairs(self.stepOrder) do
		local ok, err = pcall(self.steps[id], profile, key, db.global)
		if not ok then
			P.log.error('Nameplate step ' .. id .. ' failed: ' .. tostring(err))
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Legacy import (plan 7): the nameplates this module replaces
----------------------------------------------------------------------------------------------------
--
-- The host knows its own old data, so it answers for one profile at a time through
-- host.ImportLegacy(profileKey) (7.4, "who gets what"):
--   nil                                  nothing to bring over: a brand-new profile (setup asks),
--                                        or one whose plates were already set up some other way
--   { action = 'import', settings, defaults }
--                                        the profile used the old plates: it switches to Clean,
--                                        with the old plate width, health height and name size
--                                        (and the parts the player turned off) in Clean's overlay
--   { action = 'off' }                   an existing profile that never had the old plates: the
--                                        plates stay off until the player picks a style
--   { action = 'later' }                 not now (this character still uses the old plates): the
--                                        profile is left unmarked and asked again on a later load
-- `settings` is the old module's raw saved profile ({} when it saved nothing) and `defaults` its
-- effective defaults on this client, in the same shape (no '**' wildcards). AceDB only saves what
-- the player changed, so most sizes come from `defaults`: the old defaults differ by client.
--
-- Old keys read (everything else is dropped, 7.3): width (may be text), Scale, onlyShowPlayer,
-- showStealableBuffs, elements.Health.{height,texture}, elements.Name.textSize,
-- elements.Castbar.{enabled,height,texture,Icon.enabled,Icon.size}, elements.Power.{enabled,height},
-- elements.RaidTargetIndicator.{enabled,size}, elements.QuestMob.{enabled,size},
-- elements.TargetHighlight.enabled, elements.PvPIndicator.enabled, elements.PvPRoleIndicator.enabled.
-- Values are read with rawget only, so AceDB wildcard tables and literal '**' keys saved as data
-- are never followed.
--
-- A profile that already holds settings of its own (someone used these plates on it while
-- testing) is left alone. After a run the profile is marked (profile.migratedFromOld,
-- global.migratedFromOld[key]) and global.seen.makeover[key] holds 'import' or 'off' until the
-- host has shown its What's new card (FinishMakeover sets 'done'). Game settings are never touched
-- here: only setup changes those.

Migrate.LEGACY_TARGET = 'clean'

---Keys that never count as "the player already set these plates up".
local BOOKKEEPING = { schema = true, migratedFromOld = true, followHostProfile = true, legacy = true }

---Read a value from a nested table without metatables.
---@param tbl any
---@param path string[]
---@return any
local function Dig(tbl, path)
	local node = tbl
	for i = 1, #path do
		if type(node) ~= 'table' then
			return nil
		end
		node = rawget(node, path[i])
	end
	return node
end

---A finite number from a number or numeric text (the old width field saved text).
---@param value any
---@return number|nil
local function Number(value)
	local n = tonumber(value)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return n
end

local function Clamp(value, low, high)
	if value < low then
		return low
	end
	if value > high then
		return high
	end
	return value
end

local function Round(value)
	return math.floor(value + 0.5)
end

---Settings reader over the old saved values with the old defaults underneath.
---@param settings table|nil
---@param defaults table|nil
---@return fun(...: string): any effective
---@return fun(...: string): boolean changed
local function Reader(settings, defaults)
	local function Effective(...)
		local path = { ... }
		local value = Dig(settings, path)
		if value == nil then
			value = Dig(defaults, path)
		end
		return value
	end
	local function Changed(...)
		local path = { ... }
		local value = Dig(settings, path)
		if value == nil then
			return false
		end
		local default = Dig(defaults, path)
		if type(value) == 'number' or type(default) == 'number' then
			return Number(value) ~= Number(default)
		end
		return value ~= default
	end
	return Effective, Changed
end

---True when the profile already holds nameplate settings of its own (someone used these plates on
---it before, for example while testing). Plain defaults AceDB copied in do not count.
---@param profile table
---@return boolean
function Migrate.HasPlayerSettings(profile)
	local defaults = P.Config and P.Config:Defaults().profile or {}
	for key, value in pairs(profile) do
		if not BOOKKEEPING[key] then
			local default = defaults[key]
			if type(value) == 'table' then
				if next(value) ~= nil then
					return true
				end
			elseif default == nil or value ~= default then
				return true
			end
		end
	end
	return false
end

---Build the Clean overlay, aura settings and remembered flags from the old settings. Pure: reads
---only its arguments and the registered Clean style.
---@param settings table|nil Raw saved settings of the old module
---@param defaults table|nil Its effective defaults on this client
---@return table overlay Unvalidated overlay for tweaks.clean
---@return table|nil auras profile.auras entries, or nil
---@return table|nil legacy Flags kept for later phases (profile.legacy), or nil
function Migrate.LegacyOverlay(settings, defaults)
	local Effective, Changed = Reader(settings, defaults)
	local base = P.Styles and P.Styles.Registry and P.Styles.Registry:Get(Migrate.LEGACY_TARGET)
	local baseSize = base and base.plate and base.plate.sizes and base.plate.sizes.medium or { 132, 10 }

	-- "Scale" made the whole old plate bigger: fold it into the sizes, in whole pixels
	local scale = Number(Effective('Scale')) or 1
	if scale <= 0 then
		scale = 1
	end
	local function Px(value, low, high)
		return Clamp(Round(value * scale), low, high)
	end

	local changes, parts, add, remove = {}, {}, {}, {}
	local width = Number(Effective('width')) or baseSize[1]
	local height = Number(Effective('elements', 'Health', 'height')) or baseSize[2]
	changes.plate = { sizes = { medium = { Px(width, 1, 1024), Px(height, 1, 1024) } } }

	local nameSize = Number(Effective('elements', 'Name', 'textSize'))
	if nameSize then
		parts.name = { font = { size = Px(nameSize, 6, 40) } }
	end

	local healthTexture = Effective('elements', 'Health', 'texture')
	if Changed('elements', 'Health', 'texture') and type(healthTexture) == 'string' and healthTexture ~= '' then
		parts.health = { texture = healthTexture }
	end

	-- Parts that were on by default stay on unless the player turned them off
	local castOn = Effective('elements', 'Castbar', 'enabled') ~= false
	if not castOn then
		remove.cast = true
	else
		local cast = {}
		local castHeight = Number(Effective('elements', 'Castbar', 'height'))
		if castHeight and Changed('elements', 'Castbar', 'height') then
			cast.height = Px(castHeight, 1, 64)
		end
		local castTexture = Effective('elements', 'Castbar', 'texture')
		if Changed('elements', 'Castbar', 'texture') and type(castTexture) == 'string' and castTexture ~= '' then
			cast.texture = castTexture
		end
		if Effective('elements', 'Castbar', 'Icon', 'enabled') == true then
			cast.icon = 'left'
			local iconSize = Number(Effective('elements', 'Castbar', 'Icon', 'size'))
			if iconSize and Changed('elements', 'Castbar', 'Icon', 'size') then
				cast.iconSize = Px(iconSize, 0, 64)
			end
		end
		if next(cast) then
			parts.cast = cast
		end
	end

	local function Toggle(element, partId, sizeLow, sizeHigh)
		if Effective('elements', element, 'enabled') == false then
			remove[partId] = true
			return
		end
		local size = Number(Effective('elements', element, 'size'))
		if size and Changed('elements', element, 'size') then
			parts[partId] = { size = Px(size, sizeLow, sizeHigh) }
		end
	end
	Toggle('RaidTargetIndicator', 'marker', 4, 64)
	Toggle('QuestMob', 'quest', 4, 64)
	if Effective('elements', 'TargetHighlight', 'enabled') == false then
		remove.arrows = true
	end

	-- A power bar under the health bar; the cast bar moves under it
	if Effective('elements', 'Power', 'enabled') == true then
		local powerHeight = Number(Effective('elements', 'Power', 'height')) or 3
		add.powerBar = { order = 15, kind = 'bar', source = 'power', anchor = { 'TOP', 'health', 'BOTTOM', 0, -1 }, height = Px(powerHeight, 1, 128) }
		if castOn then
			parts.cast = parts.cast or {}
			parts.cast.anchor = { 'TOP', 'powerBar', 'BOTTOM', 0, -2 }
		end
	end

	local auras
	if Effective('onlyShowPlayer') == false then
		auras = auras or {}
		auras.myDebuffs = { onlyMine = false }
	end
	if Effective('showStealableBuffs') == true then
		auras = auras or {}
		auras.removable = { on = true }
		add.removable = { order = 55, kind = 'auras', row = 'removable', anchor = { 'RIGHT', 'health', 'LEFT', -22, 0 }, size = 18, max = 2, grow = 'LEFT' }
	end

	-- No launch equivalent yet; remembered so healer and PvP marks can switch on for these players
	local legacy
	if Effective('elements', 'PvPRoleIndicator', 'enabled') == true then
		legacy = legacy or {}
		legacy.healerMarks = true
	end
	if Effective('elements', 'PvPIndicator', 'enabled') == true then
		legacy = legacy or {}
		legacy.pvpIcon = true
	end

	if next(parts) then
		changes.parts = parts
	end
	local overlay = {
		schema = (P.Styles and P.Styles.Schema and P.Styles.Schema.CURRENT) or 1,
		baseVersion = base and base.version or 1,
		changes = changes,
	}
	if next(add) then
		overlay.add = add
	end
	if next(remove) then
		overlay.remove = remove
	end
	return overlay, auras, legacy
end

---Write an import into a profile: Clean with the old sizes, validated like any other overlay.
---@param profile table
---@param legacy table { settings, defaults }
function Migrate.ApplyLegacy(profile, legacy)
	local overlay, auras, flags = Migrate.LegacyOverlay(legacy.settings, legacy.defaults)
	local Schema = P.Styles and P.Styles.Schema
	local base = P.Styles and P.Styles.Registry and P.Styles.Registry:Get(Migrate.LEGACY_TARGET)
	if Schema and base then
		local cleaned, report = Schema:ValidateOverlay(overlay, base.parts)
		if report and ((report.dropped or 0) > 0 or (report.clamped or 0) > 0) then
			P.log.warning(string.format('Old nameplate settings: %d dropped, %d clamped', report.dropped or 0, report.clamped or 0))
		end
		overlay = cleaned or overlay
	end
	profile.style = Migrate.LEGACY_TARGET
	local tweaks = type(profile.tweaks) == 'table' and profile.tweaks or {}
	tweaks[Migrate.LEGACY_TARGET] = overlay
	profile.tweaks = tweaks
	if auras then
		local current = type(profile.auras) == 'table' and profile.auras or {}
		for row, values in pairs(auras) do
			local entry = type(current[row]) == 'table' and current[row] or {}
			for key, value in pairs(values) do
				entry[key] = value
			end
			current[row] = entry
		end
		profile.auras = current
	end
	if flags then
		profile.legacy = flags
	end
end

---Mark a profile done. The global mark survives a profile reset.
---@param profile table
---@param key string
---@param global table
local function MarkDone(profile, key, global)
	profile.migratedFromOld = true
	local done = type(global.migratedFromOld) == 'table' and global.migratedFromOld or {}
	done[key] = true
	global.migratedFromOld = done
end

---@param global table
---@param key string
---@param outcome 'import'|'off'
local function WantCard(global, key, outcome)
	local seen = type(global.seen) == 'table' and global.seen or {}
	local makeover = type(seen.makeover) == 'table' and seen.makeover or {}
	if makeover[key] == nil then
		makeover[key] = outcome
	end
	seen.makeover = makeover
	global.seen = seen
end

Migrate:AddStep('legacyImport', function(profile, key, global)
	if profile.migratedFromOld then
		return
	end
	if type(global.migratedFromOld) == 'table' and global.migratedFromOld[key] then
		-- Reset (or otherwise emptied) after an earlier run: never import it again
		profile.migratedFromOld = true
		return
	end
	local host = P.host
	local legacy
	if host and host.ImportLegacy then
		local ok, result = pcall(host.ImportLegacy, key)
		if not ok then
			-- Try again on the next load rather than mark a profile that was never looked at
			P.log.error('Reading the old nameplate settings failed: ' .. tostring(result))
			return
		end
		legacy = result
	end
	if type(legacy) == 'table' and legacy.action == 'later' then
		return
	end
	if type(legacy) == 'table' and Migrate.HasPlayerSettings(profile) then
		P.log.info('Nameplate profile ' .. tostring(key) .. ' already has its own settings; the old ones are not brought over')
		legacy = nil
	end
	if type(legacy) == 'table' then
		if legacy.action == 'import' then
			Migrate.ApplyLegacy(profile, legacy)
			WantCard(global, key, 'import')
			P.log.info('Nameplate profile ' .. tostring(key) .. ' now uses Clean with its old sizes')
		elseif legacy.action == 'off' then
			profile.enabled = false
			WantCard(global, key, 'off')
		end
	end
	MarkDone(profile, key, global)
end)

---The What's new state of a profile: 'import' or 'off' while its card is due, 'done' after it,
---nil when it never needs one.
---@param key? string Profile key (default: the current one)
---@return string|nil
function Migrate:MakeoverState(key)
	local db = P.db
	if not db then
		return nil
	end
	key = key or db:GetCurrentProfile()
	local seen = db.global.seen
	local makeover = type(seen) == 'table' and seen.makeover
	return type(makeover) == 'table' and makeover[key] or nil
end

---Record that the What's new card was answered for a profile.
---@param key? string
function Migrate:FinishMakeover(key)
	local db = P.db
	if not db then
		return
	end
	key = key or db:GetCurrentProfile()
	if self:MakeoverState(key) ~= nil then
		P.Store:Set({ 'seen', 'makeover', key }, 'done', 'global')
	end
end
