local _, ns = ...
local P = ns.Plates

-- Plate and aura container pools (6.5, 6.6). Owner: Phase 2 (containers Phase 3).
--
-- Plates:
--   * Pre-warm out of combat after login: PREWARM plates, one every 0.1 s, with the parts of the
--     profile's default styles laid out (Plate:ApplyStyle with Merge:Resolve for the usual kinds).
--   * NAME_PLATE_CREATED takes a warm plate or builds one (Plate.New(base, false)); the pool grows
--     on demand with no cap (never 40, never parse NamePlateN names).
--   * Pre-warm stops while P.Secret.IsRestricted() is true and resumes when
--     ADDON_RESTRICTION_STATE_CHANGED or PLAYER_REGEN_ENABLED says it lifted.
-- Containers (Retail and Forever):
--   * AcquireContainer(plate, rowId) returns a pooled CustomAuraContainerTemplate container with its
--     groups already added for that row (AddAuraGroup creates 10 buttons each: about 1,200
--     buttons for 20 plates x 3 rows x 2 groups; S6 measures it). Containers are reparented to the
--     plate's holder; whether they can be created in combat is UNVERIFIED (S6), so the pool only
--     grows out of combat and a row without a container stays empty until combat ends.

---@class Plates.Pool
local Pool = { free = {}, containers = {}, built = 0 }
P.Pool = Pool

Pool.PREWARM = 20
Pool.PREWARM_STEP = 0.1

---A plate for a base nameplate: a warm one when available, else a new one.
---@param base table
---@return Plates.Plate
function Pool:Acquire(base)
	local plate = table.remove(self.free)
	if not plate then
		plate = P.Plate.New(base, false)
		self.built = self.built + 1
	end
	plate.root:SetParent(base)
	plate.base = base
	return plate
end

---Return a plate (only when its base plate goes away for good; normally a plate stays with its
---base and is re-bound on every add).
---@param plate Plates.Plate
function Pool:Release(plate)
	plate:Unbind()
	plate.base = nil
	self.free[#self.free + 1] = plate
end

---Build plates ahead of the first pull. Phase 2 implements the timed, restriction-aware loop.
---@param count? integer
function Pool:Prewarm(count) end

---A container for one aura row on one plate, or nil when none can be made right now.
---@param plate Plates.Plate
---@param rowId string
---@return table|nil container
function Pool:AcquireContainer(plate, rowId)
	return nil
end

---@param container table
function Pool:ReleaseContainer(container) end

function Pool:Enable()
	self:Prewarm(self.PREWARM)
end

function Pool:Disable()
	P.Scheduler:Cancel('Pool.prewarm')
end
