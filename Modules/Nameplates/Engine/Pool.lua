local _, ns = ...
local P = ns.Plates

-- The plate pool and pre-warm (6.5, 6.6). Owner: Phase 2.
--
-- Plates:
--   * Pre-warm out of combat after login: PREWARM plates, one every PREWARM_STEP seconds (one plate
--     per step is the whole budget), each laid out for a style the profile uses (enemy NPCs most
--     often), so NAME_PLATE_CREATED during the first pull takes a ready plate instead of building
--     frames mid-pull. Only while the profile wants plates (Driver:ProfileWantsPlates); the Driver
--     starts it again when it stands up.
--   * NAME_PLATE_CREATED takes a warm plate or builds one (Plate.New(base, false)); the pool grows
--     on demand with no cap (never 40, never parse NamePlateN names). A plate then stays with its
--     base plate for the session: Blizzard reuses base plates, and the Driver re-binds on each add.
--     A warm plate whose art frame lands on another frame level than the one it was laid out at
--     is laid out again on its first add (part levels are absolute).
--   * Pre-warm pauses while P.Secret.IsRestricted() is true (combat, or auras secret in a
--     restricted instance) and resumes when RESTRICTION_CHANGED(false) or PLAYER_REGEN_ENABLED says
--     it lifted. It never runs while the engine is off.
-- Aura containers (Retail and Forever): the aura part pools them per plate (P.AuraContainers).
--   Pre-warm asks it to build the containers a warm plate's style turns on
--   (P.AuraContainers:Prewarm(plate), out of combat only), for at most PREWARM_CONTAINER_PLATES
--   plates; Quirk 'fewerContainers' lowers that to FEWER_CONTAINER_PLATES (S6's fallback when about
--   1,200 pre-built aura buttons prove too heavy). Whether containers can be created in combat is
--   UNVERIFIED (S6), so they are only ever built out of combat.

---@class Plates.Pool
local Pool = { free = {}, built = 0, warmed = 0, containerPlates = 0, running = false, done = false, active = false }
P.Pool = Pool

Pool.PREWARM = 20
Pool.PREWARM_STEP = 0.1
Pool.PREWARM_CONTAINER_PLATES = 20
Pool.FEWER_CONTAINER_PLATES = 6

-- Pre-warmed plates are laid out for these kinds in turn, so most match the first pull
local PREWARM_KINDS = { 'enemyNPC', 'enemyNPC', 'enemyNPC', 'minor', 'enemyNPC', 'friendlyPlayer', 'enemyNPC', 'enemyPlayer' }
local TICK_ID = 'Pool.prewarm'
local EMPTY = {}

---Frame that holds plates nobody uses right now.
---@return table
function Pool:Holder()
	if not self.holder then
		self.holder = CreateFrame('Frame')
		self.holder:Hide()
	end
	return self.holder
end

---A plate for a base nameplate: a warm one when available, else a new one.
---@param base table
---@return Plates.Plate
function Pool:Acquire(base)
	local plate = table.remove(self.free)
	if not plate then
		plate = P.Plate.New(base, false)
		self.built = self.built + 1
	else
		plate.root:SetParent(base)
		if plate.styleKey then
			local level = P.Secret.Plain(plate.art:GetFrameLevel())
			if level ~= plate.artLevel then
				-- Part levels were set for the holder: lay out again at the base plate's levels
				plate.styleKey = nil
			end
		end
	end
	plate.base = base
	return plate
end

---Return a plate (only when its base plate goes away for good; normally a plate stays with its
---base and is re-bound on every add).
---@param plate Plates.Plate
function Pool:Release(plate)
	plate:Unbind()
	plate.base = nil
	plate.root:SetParent(self:Holder())
	self.free[#self.free + 1] = plate
end

---Number of plates waiting in the pool.
---@return integer
function Pool:FreeCount()
	return #self.free
end

---Counts for npbench and S6.
---@return table { built, warmed, free, containerPlates, containers, buttons }
function Pool:Stats()
	local containers, buttons = 0, 0
	local Containers = P.AuraContainers
	if Containers and Containers.Stats then
		containers, buttons = Containers:Stats()
	end
	return { built = self.built, warmed = self.warmed, free = #self.free, containerPlates = self.containerPlates, containers = containers, buttons = buttons }
end

local assignment = { deps = {} }
local env = { facts = {}, states = {} }

---Resolved style a pre-warmed plate should carry, or nil when that kind is hidden.
---@param kind string
---@return Plates.ResolvedStyle|nil
local function PrewarmStyle(kind)
	local profile = P.db and P.db.profile or EMPTY
	env.ctx = P.Context
	P.Situation.Assign(kind, env, profile, assignment)
	if assignment.mode == 'hidden' then
		return nil
	end
	return P.Styles.Merge:Resolve(assignment.style, kind, assignment.size)
end

---Build the aura containers a freshly laid out plate turns on (Retail and Forever).
---@param plate Plates.Plate
local function WarmContainers(plate)
	local Containers = P.AuraContainers
	if not (Containers and Containers.Prewarm and P.Caps:Get('containers')) then
		return
	end
	local limit = P.Caps:Quirk('fewerContainers') and Pool.FEWER_CONTAINER_PLATES or Pool.PREWARM_CONTAINER_PLATES
	if Pool.containerPlates >= limit then
		return
	end
	if Containers:Prewarm(plate) then
		Pool.containerPlates = Pool.containerPlates + 1
	end
end

---Build one plate for the pool. Returns false when pre-warm should stop.
---@return boolean more
function Pool:WarmOne()
	if self.built >= self.PREWARM then
		return false
	end
	local plate = P.Plate.New(self:Holder(), false)
	self.built = self.built + 1
	self.warmed = self.warmed + 1
	local kind = PREWARM_KINDS[(self.warmed - 1) % #PREWARM_KINDS + 1]
	local resolved = PrewarmStyle(kind) or PrewarmStyle('enemyNPC')
	if resolved then
		plate:ApplyStyle(resolved)
		WarmContainers(plate)
	end
	self.free[#self.free + 1] = plate
	return self.built < self.PREWARM
end

---True when pre-warm may run now: engine on, the profile wants plates, nothing restricted.
---@return boolean
local function MayWarm()
	if not Pool.active or P.Secret.IsRestricted() then
		return false
	end
	local Driver = P.Driver
	return not (Driver and Driver.ProfileWantsPlates) or Driver:ProfileWantsPlates()
end

local function Step()
	if not MayWarm() then
		Pool:Pause()
		return
	end
	local ok, more = pcall(Pool.WarmOne, Pool)
	if not ok then
		P.log.error('Building nameplates ahead of time failed: ' .. tostring(more))
		more = false
	end
	if not more then
		Pool.done = true
		Pool:Pause()
	end
end
Pool.Step = Step

---Build plates ahead of the first pull, one per step, out of combat only.
---@param count? integer Total plates the pool should have built (default PREWARM)
function Pool:Prewarm(count)
	if count then
		self.PREWARM = count
		self.done = false
	end
	if self.done or self.built >= self.PREWARM or P.Scheduler:IsRunning(TICK_ID) then
		return
	end
	if not MayWarm() then
		self.running = false
		return
	end
	self.running = true
	P.Scheduler:Every(TICK_ID, self.PREWARM_STEP, Step)
end

---Stop building for now (combat or restriction); Prewarm resumes it.
function Pool:Pause()
	self.running = false
	P.Scheduler:Cancel(TICK_ID)
end

local function Resume()
	Pool:Prewarm()
end

local function PauseNow()
	Pool:Pause()
end

function Pool:Enable()
	self.active = true
	P:On('RESTRICTION_CHANGED', function(isRestricted)
		if isRestricted then
			Pool:Pause()
		else
			Pool:Prewarm()
		end
	end, Pool)
	P:RegisterEvent('PLAYER_REGEN_ENABLED', 'Pool', Resume)
	P:RegisterEvent('PLAYER_REGEN_DISABLED', 'Pool', PauseNow)
	self:Prewarm()
end

function Pool:Disable()
	self.active = false
	self:Pause()
	P:Off('RESTRICTION_CHANGED', Pool)
	P:UnregisterAllEvents('Pool')
end
