local _, ns = ...
local P = ns.Plates

-- The nameplate driver (6.5). Owner: Phase 2. The only owner of client-wide plate state (plate
-- size, insets, the UpdateNamePlateOptions hook) and only while the engine is on.
--
-- NAME_PLATE_CREATED(base)
--   plate = P.Pool:Acquire(base); attach the click-area frame (with a PingableUnitFrameTemplate
--   child carrying the unit attribute where the template exists) and the stacking-bounds frame
--   (a frame holding a transparent full-size texture, base:SetStackingBoundsFrame); byBase[base]
--   = plate in a weak table. Never write fields on Blizzard frames, never parse NamePlateN names.
-- NAME_PLATE_UNIT_ADDED(unit)   (synchronous: keep it cheap; budget 0.10 ms unchanged style)
--   1. base = C_NamePlate.GetNamePlateForUnit(unit) in pcall (S14); plate = byBase[base]
--   2. P.Suppress:Apply(base, plate, facts) (again on every add: Blizzard pools its UnitFrame)
--   3. widget-only plates and game objects: keep only the widget container, return. Otherwise,
--      where Caps 'simplified', C_NamePlateManager.SetNamePlateSimplified(unit, false) explicitly
--      (our Mini style replaces the engine's shrink; S8)
--   4. src:ReadFacts -> Situation.Classify -> Situation.Assign (Driver:Reassign)
--   5. ApplyStyle only when the resolved key changed. Show mode 'hidden' (plate.assignment.mode):
--      plate.root:Hide(), no Bind (no unit events), no hit-test rebinding (the base keeps
--      Blizzard's click area, so the unit stays clickable and stacking keeps working), Blizzard's
--      plate stays suppressed, and the kind is left out of ComputePlateSize. The show CVars are
--      used only when the player hides a whole kind in every place (Who and where).
--   6. plate:Bind(unit, src): RegisterUnitEvent for the union of its parts' events, full update
--   7. click frame: ClearAllHitTestPoints + SetAllHitTestPoints(plate.click) only when
--      base:CanChangeHitTestPoints() is true (tainted code may do this only on this tick); record
--      Caps 'hitTest' from GetHitTestPoints on the first plate. Fallback (S1): leave Blizzard's
--      click area and size our plate to it.
--   8. target / focus / mouseover states by frame compare (S4 fallback below)
--   9. plate.pendingConfigure from before the add is cleared by the add's own Configure
--   Fires PLATE_ADDED(plate, unit).
-- NAME_PLATE_UNIT_REMOVED(unit): plate:Unbind(), aura containers SetUnit('none') + disabled.
--   Fires PLATE_REMOVED(plate, unit).
-- Global events (P:RegisterEvent, owner 'Driver'):
--   PLAYER_TARGET_CHANGED, PLAYER_FOCUS_CHANGED, UPDATE_MOUSEOVER_UNIT: frame compare through
--     Driver:GetPlateForUnit('target') (pcall). Fallback when that fails on restricted targets
--     (S4): plate:SetStateSecret('target', src:IsUnitSecret('target')) on every bound plate when
--     P.Secret.CanCompareUnitTokens says the tokens cannot be compared; target growth and the
--     fade of other plates are off while target is only known that way. Mouseover leave: a 0.1 s
--     Scheduler task only while
--     something is moused over, waiting for GLOBAL_MOUSE_UP while a button is held.
--     Fires TARGET_CHANGED / FOCUS_CHANGED / MOUSEOVER_CHANGED; sets P.Context.hasTarget.
--   RAID_TARGET_UPDATE -> message RAID_TARGET_UPDATE to bound plates.
--   GROUP_ROSTER_UPDATE -> P.Source.ReadPlayerContext; TANKS_CHANGED.
--   SPELL_UPDATE_COOLDOWN -> KICK_READY_CHANGED when Conditions.KickReadyPlain changes or is hidden.
--   PLAYER_REGEN_DISABLED/ENABLED, PLAYER_ENTERING_WORLD, ZONE_CHANGED_NEW_AREA,
--     PLAYER_UPDATE_RESTING, PLAYER_SPECIALIZATION_CHANGED, CHALLENGE_MODE_START: update
--     P.Context (Situation.ReadPlace, Source.ReadPlayerContext), fire CONTEXT_CHANGED, re-run
--     Reassign over bound plates (only changed plates re-lay out), apply place automation
--     through P.CVars, guarded sources on (arena/battleground with secrets) or off.
--   ADDON_RESTRICTION_STATE_CHANGED: fire RESTRICTION_CHANGED(P.Secret.IsRestricted()). When it
--     lifts (and on PLAYER_REGEN_ENABLED) Driver:FlushPendingConfigure() runs Configure on every
--     plate marked pendingConfigure (aura settings changed while restricted), and the pre-warm
--     resumes.
--   QUEST_LOG_UPDATE -> QUESTS_CHANGED (re-read isQuest facts in the open world).
-- hooksecurefunc(NamePlateDriverFrame, 'UpdateNamePlateOptions'): re-apply our plate size out of
--   combat, else P.Scheduler:AfterCombat('Driver.size', ...). Installed once; does nothing while off.
-- Round-robin fact poller (6.4): a Scheduler task re-reads can-attack and in-combat (src:PollFacts)
--   for about 4 plates per plate-second while plates are shown; re-runs Assign only when
--   plate.assignment.deps has the fact; fires FACTS_POLLED to the plate.
-- STORE_CHANGED(reasons): Driver:RefreshAll(reasons).
-- CONTEXT_CHANGED and TANKS_CHANGED (listeners below): Colors drops its programs first (its
--   listener loads earlier), then every bound plate gets Reassign (place and role can change the
--   style) and Refresh({ colors = true }) (new color rows, new event maps), and the message is
--   delivered to bound plates through Plate:OnMessage (parts list it in impl.messages).
-- profile.enabled = false: the Driver stands down for that profile: every plate unbinds, Blizzard
--   plates are no longer suppressed, place settings go back through P.CVars, and no plate binds
--   until a STORE_CHANGED (profile switch or the setting) makes it true again.

---@class Plates.Driver
local Driver = { byBase = setmetatable({}, { __mode = 'k' }), bound = {}, active = false }
P.Driver = Driver

---Our plate for a base nameplate.
---@param base table
---@return Plates.Plate|nil
function Driver:GetPlate(base)
	return base and self.byBase[base] or nil
end

---Our plate for a unit token ('target', 'nameplate3'); pcall-guarded (S14).
---@param unit string
---@return Plates.Plate|nil
function Driver:GetPlateForUnit(unit)
	local base = P.Source.PlateForUnit(unit)
	return base and self.byBase[base] or nil
end

---Call fn(plate) for every bound plate.
---@param fn fun(plate: Plates.Plate)
function Driver:ForEachPlate(fn)
	for plate in pairs(self.bound) do
		fn(plate)
	end
end

---Classify and assign a plate, resolve its style and lay it out when the key changed.
---@param plate Plates.Plate
---@return boolean relaidOut
function Driver:Reassign(plate)
	local profile = P.db and P.db.profile or {}
	local situation = P.Situation.Classify(plate.facts)
	plate.situation = situation
	P.Situation.Assign(situation, plate.env, profile, plate.assignment)
	local resolved = P.Styles.Merge:Resolve(plate.assignment.style, situation, plate.assignment.size)
	return plate:ApplyStyle(resolved)
end

---Base plate size covering the largest click area of any style a kind of plate can use. Applied
---with C_NamePlate.SetNamePlateSize out of combat (multiplied by UIParent:GetScale() under
---Quirk 'uiParentScale').
---@return integer width
---@return integer height
function Driver:ComputePlateSize()
	local Merge, Situation = P.Styles.Merge, P.Situation
	local profile = P.db and P.db.profile or {}
	local width, height = 1, 1
	local function Consider(styleId, situation, size)
		local resolved = Merge:Resolve(styleId, situation, size)
		local w, h = Merge.SizeForRect(resolved.regions.click)
		width, height = math.max(width, w), math.max(height, h)
	end
	local out = { deps = {} }
	local env = { facts = {}, ctx = P.Context, states = {} }
	for _, situation in ipairs(Situation.KINDS) do
		Situation.Assign(situation, env, profile, out)
		if out.mode ~= 'hidden' then
			Consider(out.style, situation, out.size)
		end
	end
	for _, entry in ipairs(type(profile.when) == 'table' and profile.when or {}) do
		if not entry.off and (entry.style or entry.size) then
			for _, situation in ipairs(entry.kinds or Situation.KINDS) do
				Consider(entry.style or profile.style or 'host', situation, entry.size or profile.size or 'medium')
			end
		end
	end
	return width, height
end

---Settings changed: re-resolve and refresh every bound plate (look and size re-lay out through a
---new style key; colors and auras refresh in place).
---@param reasons table<string, boolean>
function Driver:RefreshAll(reasons)
	for plate in pairs(self.bound) do
		if reasons.look or reasons.size or reasons.assignment or reasons.auras then
			if self:Reassign(plate) then
				plate:UpdateAll('FULL')
			end
		end
		plate:Refresh(reasons)
	end
end

---Deliver a bus message to every bound plate.
---@param message string
function Driver:Broadcast(message, ...)
	for plate in pairs(self.bound) do
		plate:OnMessage(message, ...)
	end
end

---Whether the current profile wants our plates (profile.enabled).
---@return boolean
function Driver:ProfileWantsPlates()
	local profile = P.db and P.db.profile
	return not profile or profile.enabled ~= false
end

---Aura settings changed while the game restricted changes: configure those plates now.
function Driver:FlushPendingConfigure()
	if P.Secret.IsRestricted() then
		return
	end
	for plate in pairs(self.bound) do
		if plate.pendingConfigure then
			plate:Configure()
		end
	end
end

---Place, combat, role or the other tanks changed: re-pick styles, rebuild colors and tell parts.
---@param message string
function Driver:ContextChanged(message)
	for plate in pairs(self.bound) do
		if self:Reassign(plate) then
			plate:UpdateAll('FULL')
		end
		plate:Refresh({ colors = true })
	end
	self:Broadcast(message)
end

function Driver:Enable()
	self.active = true
	P.Situation.ReadPlace(P.Context)
	P.Source.ReadPlayerContext(P.Context, P.db and P.db.profile.role)
	P:RegisterEvent('PLAYER_REGEN_ENABLED', 'Driver', function()
		Driver:FlushPendingConfigure()
	end)
	P.log.info('Nameplate driver is not built yet; Blizzard plates stay in place')
end

function Driver:Disable()
	self.active = false
	for plate in pairs(self.bound) do
		plate:Unbind()
	end
	P.util.Wipe(self.bound)
	P:UnregisterAllEvents('Driver')
end

P:On('STORE_CHANGED', function(reasons)
	if Driver.active and reasons then
		Driver:RefreshAll(reasons)
	end
end, Driver)
P:On('CONTEXT_CHANGED', function()
	if Driver.active then
		Driver:ContextChanged('CONTEXT_CHANGED')
	end
end, Driver)
P:On('TANKS_CHANGED', function()
	if Driver.active then
		Driver:ContextChanged('TANKS_CHANGED')
	end
end, Driver)
P:On('RESTRICTION_CHANGED', function(isRestricted)
	if Driver.active and not isRestricted then
		Driver:FlushPendingConfigure()
	end
end, Driver)
