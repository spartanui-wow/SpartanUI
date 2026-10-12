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
