local _, ns = ...
local P = ns.Plates
local L = P.L

-- The nameplate game settings we own (6.7): a registry, a probe per setting, a backup of the
-- player's value the first time we change it, a combat queue for secure settings, and a record of
-- who last changed each one.
--
-- Rules:
--   * Never write nameplateMotion (removed from every client; Decision 12). Define and Set refuse it.
--   * Probe with C_CVar.GetCVarInfo. A missing setting hides its control. Scope (account or
--     character) and the secure flag come from the probe, never from code: sources disagree.
--   * Write only when the value differs. Secure settings are queued until combat ends.
--   * The first write backs up the player's value (first write wins): account settings in
--     global.cvarBackup, character settings in char.cvarBackup. RestoreAll gives them back.
--   * Attribution hooks C_CVar.SetCVar and C_CVar.SetCVarBitfield only (the globals wrap them).
--     hooksecurefunc cannot be undone, so the hooks are installed on the first Enable and do
--     nothing while the engine is off.
--   * The combat queue flushes itself: PLAYER_REGEN_ENABLED is registered while the queue holds
--     something, whether or not the engine runs, so a restore queued in combat (turning the
--     engine off, "Give the game back its settings") is never lost.

---@class Plates.CVarDef
---@field name string
---@field kind 'bool'|'number'|'string'|'bitfield'
---@field label string
---@field page? string Options page that shows it ('whoAndWhere', 'style'); nil = internal only
---@field bits? table<string, integer> Bitfield indexes by key
---@field alt? string[] Older names to try when this one is missing
---@field min? number
---@field max? number

---@class Plates.CVarInfo
---@field exists boolean
---@field actual string Name that exists on this client
---@field default string|nil
---@field account boolean Stored per account on the server
---@field character boolean Stored per character on the server
---@field locked boolean
---@field secure boolean Combat-locked
---@field readOnly boolean

---@class Plates.CVars
local CVars = { defs = {}, order = {}, info = {}, queue = {}, attribution = {}, active = false, hooked = false, writing = false }
P.CVars = CVars

local FORBIDDEN = { nameplateMotion = true }

---@param name string
---@param def table Plates.CVarDef without the name
function CVars:Define(name, def)
	if FORBIDDEN[name] then
		error('Plates: ' .. name .. ' must never be written', 2)
	end
	def.name = name
	def.kind = def.kind or 'bool'
	if not self.defs[name] then
		self.order[#self.order + 1] = name
	end
	self.defs[name] = def
	self.info[name] = nil
	self.lowerNames = nil
end

local function RawInfo(name)
	if not (C_CVar and C_CVar.GetCVarInfo) then
		return nil
	end
	local ok, value, default, account, character, locked, secure, readOnly = pcall(C_CVar.GetCVarInfo, name)
	if not ok or value == nil then
		return nil
	end
	return {
		exists = true,
		actual = name,
		default = default,
		account = account and true or false,
		character = character and true or false,
		locked = locked and true or false,
		secure = secure and true or false,
		readOnly = readOnly and true or false,
	}
end

---Probe a defined setting (cached). Tries older names from def.alt when the name is missing.
---@param name string
---@return Plates.CVarInfo
function CVars:Probe(name)
	local cached = self.info[name]
	if cached then
		return cached
	end
	local info = RawInfo(name)
	local def = self.defs[name]
	if not info and def and def.alt then
		for _, altName in ipairs(def.alt) do
			info = RawInfo(altName)
			if info then
				break
			end
		end
	end
	info = info or { exists = false, actual = name }
	self.info[name] = info
	return info
end

---@param name string
---@return boolean
function CVars:Exists(name)
	return self:Probe(name).exists
end

---Current value as the client stores it (a string), or nil.
---@param name string
---@return string|nil
function CVars:Get(name)
	local info = self:Probe(name)
	if not info.exists or not (C_CVar and C_CVar.GetCVar) then
		return nil
	end
	return C_CVar.GetCVar(info.actual)
end

---@param name string
---@param bitKey string
---@return boolean|nil
function CVars:GetBit(name, bitKey)
	local info, def = self:Probe(name), self.defs[name]
	local index = def and def.bits and def.bits[bitKey]
	if not info.exists or not index or not (C_CVar and C_CVar.GetCVarBitfield) then
		return nil
	end
	return C_CVar.GetCVarBitfield(info.actual, index) and true or false
end

---Turn a Lua value into the string the client stores.
---@param value any
---@return string
function CVars.Normalize(value)
	if value == true then
		return '1'
	elseif value == false then
		return '0'
	elseif type(value) == 'number' then
		if value == math.floor(value) then
			return string.format('%d', value)
		end
		return string.format('%.4g', value)
	end
	return tostring(value)
end

---True when two stored values mean the same thing ("1" and "1.0" are the same number).
---@param a string|nil
---@param b string|nil
---@return boolean
function CVars.Same(a, b)
	if a == b then
		return true
	end
	local na, nb = tonumber(a), tonumber(b)
	return na ~= nil and nb ~= nil and math.abs(na - nb) < 1e-6
end

local function BackupBucket(info)
	local db = P.db
	if not db then
		return nil
	end
	local scope = info.character and db.char or db.global
	scope.cvarBackup = scope.cvarBackup or {}
	return scope.cvarBackup
end

---Keep the player's value the first time we change a setting.
---@param name string
function CVars:Backup(name)
	local info = self:Probe(name)
	local bucket = BackupBucket(info)
	if bucket and bucket[name] == nil then
		bucket[name] = self:Get(name)
	end
end

local function Write(self, info, value)
	self.writing = true
	local ok, result = pcall(C_CVar.SetCVar, info.actual, value)
	self.writing = false
	return ok and result ~= false
end

---Change a setting we own. Returns what happened:
---'set' | 'same' | 'queued' | 'missing' | 'locked' | 'failed'
---@param name string
---@param value any
---@param why? string Short reason kept with the attribution ('place', 'setup', 'player')
---@return string result
function CVars:Set(name, value, why)
	if FORBIDDEN[name] then
		P.log.error('Refused to write ' .. name)
		return 'locked'
	end
	local info = self:Probe(name)
	if not info.exists then
		return 'missing'
	end
	if info.locked or info.readOnly then
		return 'locked'
	end
	local text = CVars.Normalize(value)
	if CVars.Same(self:Get(name), text) then
		self.queue[name] = nil
		return 'same'
	end
	if info.secure and InCombatLockdown and InCombatLockdown() then
		self:Queue(name, { value = text, why = why })
		return 'queued'
	end
	self:Backup(name)
	if not Write(self, info, text) then
		return 'failed'
	end
	self.attribution[name] = { by = 'us', why = why, time = P.services.GetTime() }
	P:Fire('CVAR_CHANGED', name, text, 'us')
	return 'set'
end

---Change one bit of a bitfield setting (stacking types, aura displays).
---@param name string
---@param bitKey string
---@param on boolean
---@param why? string
---@return string result
function CVars:SetBit(name, bitKey, on, why)
	local info, def = self:Probe(name), self.defs[name]
	local index = def and def.bits and def.bits[bitKey]
	if not info.exists or not index or not (C_CVar and C_CVar.SetCVarBitfield) then
		return 'missing'
	end
	if info.locked or info.readOnly then
		return 'locked'
	end
	if self:GetBit(name, bitKey) == (on and true or false) then
		return 'same'
	end
	if info.secure and InCombatLockdown and InCombatLockdown() then
		self:Queue(name .. ':' .. bitKey, { bit = bitKey, base = name, value = on, why = why })
		return 'queued'
	end
	self:Backup(name)
	self.writing = true
	local ok = pcall(C_CVar.SetCVarBitfield, info.actual, index, on and true or false)
	self.writing = false
	if not ok then
		return 'failed'
	end
	self.attribution[name] = { by = 'us', why = why, time = P.services.GetTime() }
	P:Fire('CVAR_CHANGED', name, self:Get(name), 'us')
	return 'set'
end

local FLUSH_OWNER = 'CVars.queue'

---Hold a write for after combat and make sure something flushes it.
---@param key string
---@param entry table
function CVars:Queue(key, entry)
	self.queue[key] = entry
	if not self.flushing then
		self.flushing = P:RegisterEvent('PLAYER_REGEN_ENABLED', FLUSH_OWNER, function()
			CVars:FlushQueue()
		end)
	end
end

---Write queued secure settings (PLAYER_REGEN_ENABLED).
function CVars:FlushQueue()
	local queue = self.queue
	self.queue = {}
	for key, entry in pairs(queue) do
		if entry.bit then
			self:SetBit(entry.base, entry.bit, entry.value, entry.why)
		elseif entry.restore then
			self:Restore(key)
		else
			self:Set(key, entry.value, entry.why)
		end
	end
	if next(self.queue) == nil and self.flushing then
		self.flushing = false
		P:UnregisterEvent('PLAYER_REGEN_ENABLED', FLUSH_OWNER)
	end
end

---True while settings wait for combat to end.
---@return boolean
function CVars:HasQueued()
	return next(self.queue) ~= nil
end

---Give one setting back its backed-up value.
---@param name string
---@return boolean restored
function CVars:Restore(name)
	local info = self:Probe(name)
	local bucket = BackupBucket(info)
	local original = bucket and bucket[name]
	if original == nil or not info.exists then
		return false
	end
	if info.secure and InCombatLockdown and InCombatLockdown() then
		self:Queue(name, { restore = true })
		return false
	end
	if not CVars.Same(self:Get(name), original) then
		Write(self, info, original)
	end
	bucket[name] = nil
	self.attribution[name] = { by = 'us', why = 'restore', time = P.services.GetTime() }
	P:Fire('CVAR_CHANGED', name, original, 'restore')
	return true
end

---Give the game back every setting we changed ("Give the game back its settings", turning the
---module off, turning the tester switch off). Settings the game locks in combat are queued and
---written when combat ends.
---@return boolean done false when some settings wait for combat to end
function CVars:RestoreAll()
	local db = P.db
	if not db then
		return true
	end
	local names = {}
	for _, scope in ipairs({ db.global, db.char }) do
		for name in pairs(scope.cvarBackup or {}) do
			names[#names + 1] = name
		end
	end
	local done = true
	for _, name in ipairs(names) do
		if not self:Restore(name) and self.queue[name] then
			done = false
		end
	end
	for _, scope in ipairs({ db.global, db.char }) do
		if scope.cvarBackup and next(scope.cvarBackup) == nil then
			scope.cvarBackup = nil
		end
	end
	return done
end

---The backed-up player value, or nil when we never changed it.
---@param name string
---@return string|nil
function CVars:GetBackup(name)
	local db = P.db
	if not db then
		return nil
	end
	local char = db.char.cvarBackup
	local global = db.global.cvarBackup
	return (char and char[name]) or (global and global[name]) or nil
end

---@param name string
---@return table|nil { by = 'us'|'other'|'restore', why?, time, stack? }
function CVars:GetAttribution(name)
	return self.attribution[name]
end

---The defined setting a written name stands for: CVar names ignore case in the game, and a setting
---may exist on this client only under an older name (def.alt).
---@param name string
---@return string|nil
function CVars:DefinedName(name)
	if self.defs[name] then
		return name
	end
	local map = self.lowerNames
	if not map then
		map = {}
		for defined, def in pairs(self.defs) do
			map[defined:lower()] = defined
			for _, alt in ipairs(def.alt or {}) do
				map[alt:lower()] = defined
			end
		end
		self.lowerNames = map
	end
	return map[name:lower()]
end

local function OnExternalWrite(name)
	local self = CVars
	if not self.active or self.writing or type(name) ~= 'string' then
		return
	end
	name = self:DefinedName(name)
	if name then
		self.attribution[name] = { by = 'other', time = P.services.GetTime(), stack = debugstack and debugstack(3, 3, 0) or nil }
		P:Fire('CVAR_CHANGED', name, self:Get(name), 'other')
	end
end

---Defined settings for one options page, in definition order, with their probe.
---@param page string
---@return table[] list of { def, info }
function CVars:List(page)
	local out = {}
	for _, name in ipairs(self.order) do
		local def = self.defs[name]
		if def.page == page then
			out[#out + 1] = { def = def, info = self:Probe(name) }
		end
	end
	return out
end

function CVars:Enable()
	self.active = true
	P.util.Wipe(self.info)
	if not self.hooked and hooksecurefunc and C_CVar then
		self.hooked = true
		hooksecurefunc(C_CVar, 'SetCVar', function(name)
			OnExternalWrite(name)
		end)
		if C_CVar.SetCVarBitfield then
			hooksecurefunc(C_CVar, 'SetCVarBitfield', function(name)
				OnExternalWrite(name)
			end)
		end
	end
end

---Stop owning settings. Writes still waiting for combat to end are dropped (the engine is giving
---the settings back); queued restores stay and flush after combat.
function CVars:Disable()
	self.active = false
	for key, entry in pairs(self.queue) do
		if not entry.restore then
			self.queue[key] = nil
		end
	end
	if next(self.queue) == nil and self.flushing then
		self.flushing = false
		P:UnregisterEvent('PLAYER_REGEN_ENABLED', FLUSH_OWNER)
	end
end

----------------------------------------------------------------------------------------------------
-- Settings we own. Defining is inert; nothing is written until the engine asks.
----------------------------------------------------------------------------------------------------

local stack = Enum and Enum.NamePlateStackType
local npcAura = Enum and Enum.NamePlateEnemyNpcAuraDisplay
local playerAura = Enum and Enum.NamePlateEnemyPlayerAuraDisplay

CVars:Define('nameplateShowEnemies', { kind = 'bool', label = L['Show enemy nameplates'], page = 'whoAndWhere' })
CVars:Define('nameplateShowFriendlyPlayers', { kind = 'bool', label = L['Show friendly player nameplates'], page = 'whoAndWhere', alt = { 'nameplateShowFriends' } })
CVars:Define('nameplateShowFriendlyNpcs', { kind = 'bool', label = L['Show friendly NPC nameplates'], page = 'whoAndWhere' })
CVars:Define('nameplateShowEnemyMinions', { kind = 'bool', label = L['Enemy pets and minions'], page = 'whoAndWhere' })
CVars:Define('nameplateShowEnemyPets', { kind = 'bool', label = L['Enemy pets'], page = 'whoAndWhere' })
CVars:Define('nameplateShowEnemyGuardians', { kind = 'bool', label = L['Enemy guardians'], page = 'whoAndWhere' })
CVars:Define('nameplateShowEnemyTotems', { kind = 'bool', label = L['Enemy totems'], page = 'whoAndWhere' })
CVars:Define('nameplateShowEnemyMinus', { kind = 'bool', label = L['Minor enemies'], page = 'whoAndWhere' })
CVars:Define('nameplateShowFriendlyPlayerPets', { kind = 'bool', label = L['Friendly pets'], page = 'whoAndWhere' })
CVars:Define('nameplateShowFriendlyPlayerGuardians', { kind = 'bool', label = L['Friendly guardians'], page = 'whoAndWhere' })
CVars:Define('nameplateShowFriendlyPlayerTotems', { kind = 'bool', label = L['Friendly totems'], page = 'whoAndWhere' })
CVars:Define('nameplateShowFriendlyPlayerMinions', { kind = 'bool', label = L['Friendly minions'], page = 'whoAndWhere' })
CVars:Define('nameplateShowOnlyNameForFriendlyPlayerUnits', { kind = 'bool', label = L['Friendly players show names only'], page = 'whoAndWhere' })
CVars:Define('nameplateUseClassColorForFriendlyPlayerUnitNames', { kind = 'bool', label = L['Color friendly names by class'], page = 'whoAndWhere' })
CVars:Define('nameplateStackingTypes', {
	kind = 'bitfield',
	label = L['Keep plates from overlapping'],
	page = 'whoAndWhere',
	bits = { enemy = stack and stack.Enemy or 1, friendly = stack and stack.Friendly or 2 },
})
CVars:Define('nameplateOccludedAlphaMult', { kind = 'number', label = L['Fade plates behind walls'], page = 'whoAndWhere', min = 0, max = 1 })
CVars:Define('nameplateMaxDistance', { kind = 'number', label = L['How far away plates show'], page = 'whoAndWhere', min = 10, max = 100 })
CVars:Define('nameplateMinScale', { kind = 'number', label = L['Smallest size far away'], page = 'style', min = 0.5, max = 1 })
CVars:Define('nameplateMaxScale', { kind = 'number', label = L['Largest size up close'], page = 'style', min = 0.5, max = 2 })
CVars:Define('nameplateSelectedScale', { kind = 'number', label = L['Game target size'], min = 0.5, max = 2 })
CVars:Define('nameplateTopInset', { kind = 'number', label = L['Space at the top of the screen'], page = 'whoAndWhere', min = 0, max = 0.5 })
CVars:Define('nameplateBottomInset', { kind = 'number', label = L['Space at the bottom of the screen'], page = 'whoAndWhere', min = 0, max = 0.5 })
CVars:Define('nameplateMotionSpeed', { kind = 'number', label = L['How fast plates move apart'], page = 'whoAndWhere', min = 0, max = 0.1 })
-- Classic family: Blizzard's enemy aura display bits cause taint errors next to addon plates
CVars:Define('nameplateEnemyNpcAuraDisplay', {
	kind = 'bitfield',
	label = L['Game aura icons on enemy NPCs'],
	bits = { buffs = npcAura and npcAura.Buffs or 1, debuffs = npcAura and npcAura.Debuffs or 2, crowdControl = npcAura and npcAura.CrowdControl or 3 },
})
CVars:Define('nameplateEnemyPlayerAuraDisplay', {
	kind = 'bitfield',
	label = L['Game aura icons on enemy players'],
	bits = { buffs = playerAura and playerAura.Buffs or 1, debuffs = playerAura and playerAura.Debuffs or 2, crowdControl = playerAura and playerAura.CrowdControl or 3 },
})
