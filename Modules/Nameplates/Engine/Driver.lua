local _, ns = ...
local P = ns.Plates
local Secret = P.Secret

-- The nameplate driver (6.5, 6.7, 6.8). Owner: Phase 2. The only owner of client-wide plate state
-- (plate size, hit-test insets, the UpdateNamePlateOptions hook, the place settings it writes
-- through P.CVars), and only while the engine is on, the profile wants plates (profile.enabled)
-- and the tester switch was not turned off this session (OwnsSettings).
--
-- NAME_PLATE_CREATED(base)
--   plate = P.Pool:Acquire(base) (a warm plate when one is ready); attach the click-area frame
--   (with a PingableUnitFrameTemplate child carrying the unit attribute where the template exists)
--   and the stacking-bounds frame (a frame holding a transparent full-size texture,
--   base:SetStackingBoundsFrame); byBase[base] = plate in a weak table. Never write fields on
--   Blizzard frames, never parse NamePlateN names, never cap the plate count.
-- NAME_PLATE_UNIT_ADDED(unit)   (synchronous: kept cheap; no tables or closures made per add)
--   1. base = Source.PlateForUnit(unit) (pcall, S14); plate = byBase[base] (made now if missing)
--   2. src:ReadFacts. The player's own plate (the personal plate on the Classic family, found by
--      frame compare with GetNamePlateForUnit('player')) is left to Blizzard: Suppress:Release
--      gives back a pooled unit frame we silenced before, nothing draws, return (mode 'self').
--      Otherwise P.Suppress:Apply(base, plate, facts) (again on every add: Blizzard pools its
--      UnitFrame).
--      Game objects (interact objects) are left to Blizzard the same way (mode 'blizzard'): its
--      own plate for them is a name, which ours would hide.
--   3. widget-only plates: draw nothing (the rescued widget container and soft-target icon stay
--      on the base), return (mode 'widgets'). Otherwise the plate's own fact
--      frame follows UNIT_FACTION / UNIT_CLASSIFICATION_CHANGED and, where Caps 'simplified',
--      C_NamePlateManager.SetNamePlateSimplified(unit, false) explicitly (our Mini style replaces
--      the engine's shrink; S8). Quirk 'engineSimplified' (S8 fallback) passes true for minor
--      enemies so the engine shrinks them instead.
--   4. Classify -> Assign (Driver:Reassign); Show mode 'hidden': the plate root hides, nothing
--      binds, no hit-test rebinding (the base keeps Blizzard's click area), Blizzard's plate stays
--      suppressed, and the kind is left out of ComputePlateSize. Hidden plates draw nothing, so
--      their stacking frame (inside the hidden root) takes no room either.
--   5. ApplyStyle only when the resolved key changed; then the click and stacking frames follow
--      the style's regions (LayoutRegions: root CENTER on the base BOTTOM, offset so the click
--      rect's bottom sits on the base's bottom edge; hostile plates hang from the base TOP when
--      nameplateOtherAtBase puts them under units, friendly and neutral ones never move; CVAR_UPDATE
--      for that setting and UNIT_FACTION move plates again).
--   6. plate:Bind(unit, src): RegisterUnitEvent for the union of its parts' events, full update;
--      base:SetStackingBoundsFrame(plate.stack) again (pcall)
--   7. click frame: ClearAllHitTestPoints + SetAllHitTestPoints(plate.click) only when
--      base:CanChangeHitTestPoints() is true (in combat tainted code may do this only on the add
--      tick; out of combat also when catching up or showing a hidden kind again). Blizzard's own
--      add handler sets its click area first on every add, so this runs on every add. The first
--      plate records Caps 'hitTest' from GetHitTestPoints. Fallback (S1, or /sui np cap hitTest
--      off): leave Blizzard's click area; the base plate is still sized to our plate.
--   8. target / focus / mouseover states by frame compare (S4 fallback below), arena index
--   9. Configure when the style changed or settings waited for a restriction to lift
--   Fires PLATE_ADDED(plate, unit) once the plate draws. No tables or closures are made per add
--   once a plate was laid out (Plate:Bind only registers events when its maps are current;
--   Tests/Nameplates/suites/bench_spec.lua measures it).
-- NAME_PLATE_UNIT_REMOVED(unit): plate:Unbind() (parts Reset: aura containers SetUnit('none')),
--   fact frame unregistered. Fires PLATE_REMOVED(plate, unit) for plates that drew.
-- Global events (P:RegisterEvent, owner 'Driver'):
--   PLAYER_TARGET_CHANGED, PLAYER_FOCUS_CHANGED, UPDATE_MOUSEOVER_UNIT: frame compare through
--     Source.PlateForUnit(token) (pcall). When the unit exists but no plate is found (no plate in
--     view, or the game will not say: S4), each drawn plate is asked src:IsUnitSecret(token):
--     readable answers set the state, hidden ones go to plate:SetStateSecret (state-tied parts
--     fade by SetAlphaFromBoolean; target growth and the fade of other plates are off then, so
--     P.Context.hasTarget stays false). A plate that got a hidden answer gets its state-tied parts
--     back at their own alpha before the next plain answer (SetPlateState). Mouseover leave: a
--     0.1 s Scheduler task only while something is moused over; while a mouse button is held
--     mouseover reads as gone, so it waits for GLOBAL_MOUSE_UP before clearing. Fires
--     TARGET_CHANGED / FOCUS_CHANGED / MOUSEOVER_CHANGED on the bus; plates hear it only when
--     their state changed (the plate that lost it and the one that got it), or every plate when
--     hidden answers were involved.
--   RAID_TARGET_UPDATE -> RAID_TARGET_UPDATE to bound plates.
--   GROUP_ROSTER_UPDATE, PLAYER_ROLES_ASSIGNED, UNIT_PET (the player's pet only), PLAYER_SPECIALIZATION_CHANGED,
--     ACTIVE_TALENT_GROUP_CHANGED, PLAYER_LEVEL_UP, PLAYER_UPDATE_RESTING: context re-read on the
--     next frame (coalesced); TANKS_CHANGED when the other tanks changed, CONTEXT_CHANGED when
--     anything else in P.Context changed.
--   PLAYER_ENTERING_WORLD, ZONE_CHANGED_NEW_AREA, CHALLENGE_MODE_START/COMPLETED/RESET, combat
--     edges: P.Context now (place incl. delves and housing, combat, challenge mode), place
--     settings, guarded sources on (arenas and battlegrounds on clients with secrets) or off.
--   SPELLS_CHANGED (and Kicks.EVENTS): the kick spell (P.Context.kickSpell) is picked again.
--   SPELL_UPDATE_COOLDOWN -> KICK_READY_CHANGED when Conditions.KickReadyPlain changes; while the
--     interrupt is cooling down or hidden a 0.2 s task keeps checking (hidden answers are sent on
--     the task only, so cooldown event storms cost nothing).
--   ADDON_RESTRICTION_STATE_CHANGED (and combat edges): RESTRICTION_CHANGED(P.Secret.IsRestricted())
--     When it lifts (and on PLAYER_REGEN_ENABLED) Driver:FlushPendingConfigure() runs Configure on
--     every plate marked pendingConfigure, and the Pool resumes its pre-warm.
--   QUEST_LOG_UPDATE -> isQuest re-read on every plate at most twice a second, QUEST_BUDGET plates
--     per 0.1 s tick (each read is a tooltip); each plate gets QUESTS_CHANGED after its read, the
--     bus once all are done.
--   ARENA_OPPONENT_UPDATE -> plate.arenaIndex (1-5 from GetNamePlateForUnit('arenaN') frame
--     compare, pcall, arenas only; S18) and ARENA_CHANGED (bus and bound plates) when any index
--     moved. Text draws the labels (its arena source reads src:ArenaIndexPlain).
-- hooksecurefunc(NamePlateDriverFrame, 'UpdateNamePlateOptions'): Blizzard just set its own base
--   size; remember it for giving back and re-apply ours out of combat, else
--   P.Scheduler:AfterCombat('Driver.size'). Installed once; does nothing while the Driver does not
--   own settings. Insets are written only after our own changes. Never edits the driver frame's
--   event registrations.
-- Round-robin fact poller (6.4): a 0.1 s Scheduler task, only while plates show units, re-reads
--   can-attack and in-combat (src:PollFacts) for about 4 checks per plate per second, plus range
--   when range fade is on; re-runs Assign only when plate.assignment.deps has the fact; sends
--   FACTS_POLLED to the plate (also when the combat flag stays hidden, so engine color rows keep up).
-- STORE_CHANGED(reasons): profile.enabled, place settings, plate size, RefreshAll(reasons).
-- CONTEXT_CHANGED(keys) and TANKS_CHANGED (listeners below; keys is the set of P.Context keys
--   that changed): Colors drops its programs first when the role changed (its listener loads
--   earlier); plates get Reassign only while a "When" entry is on, and Refresh({ colors = true })
--   only when Colors:ReadsContext(keys); the message (with keys) is delivered to bound plates
--   through Plate:OnMessage (parts list it in impl.messages). TANKS_CHANGED is only delivered.
--   Combat edges therefore cost one message per listening part and no event map rebuilds.
-- profile.enabled = false: the Driver stands down for that profile: every plate unbinds, Blizzard
--   plates are no longer suppressed, the click and stacking frames cover the whole base again,
--   place settings, plate size and insets go back, and no plate binds until a STORE_CHANGED
--   (profile switch or the setting) makes it true again.
--
-- Plate behavior settings (profile.behavior, sparse; nil leaves the game setting alone; Options
-- Who and where writes them in Phase 4a, setup turns on stacking, friendlyNames and pinScale):
--   enemies = 'always' | 'combat'         nameplateShowEnemies, on combat edges for 'combat'
--   friendlyPlayers, friendlyNPCs = bool  nameplateShowFriendlyPlayers / nameplateShowFriendlyNpcs
--   stacking = { enemy = bool, friendly = bool }  nameplateStackingTypes bits
--   friendlyNames = true                  inside instances (place ~= 'world'), where the game draws
--                                         friendly plates itself: names only, class colors
--   pinScale = true                       nameplateMinScale/MaxScale/SelectedScale = 1 (S17)
--   fadeBehindWalls = 0..1                nameplateOccludedAlphaMult, where probed (S12)
--   fadeBehindWallsCombat = 0..1          the same while the player is in combat (combat edges)
--   clickThroughFriendly = bool           friendly hit-test insets (10000 = click through)
--   onlyFighting = true                   enemy NPC and minor plates whose unit is not fighting
--                                         get root alpha 0 (target and focus excepted). Hidden
--                                         combat flags (S16) show the plate and record Caps
--                                         'unitCombat' = false
--   rangeFade = 0..1, rangeYards = 40     root alpha out of range: LibRangeCheck-3.0's harm
--                                         checker through LibStub when present, else the
--                                         interrupt's own range (C_Spell.IsSpellInRange), else off
--                                         (FeatureState says why). Hidden answers never fade (S9)
--   places = { [place] = { same keys } }  per-place overrides (World, Dungeon, Raid, ...)
-- A kind hidden in every place (an explicit profile.modes entry and no "When" entry showing it)
-- also turns off its show CVar, so the game makes no plate for it. profile.cvars[name] holds values
-- the player set on our pages; they are written too. On the Classic family Blizzard's enemy aura
-- display bits are turned off while we draw (they cause taint errors next to addon plates).
-- A setting someone else changes after us (attribution 'other') is left alone for the session,
-- until the player changes our settings again.

---@class Plates.Driver
local Driver = {
	byBase = setmetatable({}, { __mode = 'k' }), -- base plate -> our plate (every base we attached)
	bound = {}, -- plate -> true while it draws a unit
	units = {}, -- plate -> unit token while its base shows a unit (drawn, hidden or widgets only)
	list = {}, -- the plates in `units`, for the round-robin poller
	active = false, -- engine on
	standing = false, -- drawing for the current profile
	statePlates = {}, -- state -> plate found by frame compare
	secretStates = {}, -- state -> true while known only through secrets (S4)
	exists = {}, -- state -> the unit exists
	appliedSize = { 0, 0 },
	placeApplied = {}, -- CVar name -> true while place settings changed it
	yielded = {}, -- CVar name -> true after someone else changed it (left alone this session)
	cursor = 0,
	kickReady = nil,
	restricted = false,
	guarded = false,
	atBase = false,
}
P.Driver = Driver

local weak = { __mode = 'k' }
local sources = setmetatable({}, weak) -- plate -> LiveSource (kept across adds)
local modes = setmetatable({}, weak) -- plate -> 'drawn' | 'hidden' | 'widgets' | 'self' | 'blizzard'
local factFrames = setmetatable({}, weak) -- plate -> frame for UNIT_FACTION / UNIT_CLASSIFICATION_CHANGED
local framePlate = setmetatable({}, weak) -- fact frame -> plate
local listIndex = setmetatable({}, weak) -- plate -> index in Driver.list
local regionKey = setmetatable({}, weak) -- plate -> style key its click and stacking frames follow
local regionLow = setmetatable({}, weak) -- plate -> true while it hangs from the base top (OtherAtBase)
local inRange = setmetatable({}, weak) -- plate -> true | false | nil (unknown)
local fadeAlpha = setmetatable({}, weak) -- plate -> root alpha last applied

---True for plates the Driver assigns a style to: drawn, or hidden by their Show mode (widget-only
---plates, game objects and the player's own plate are left alone).
---@param plate Plates.Plate
---@return boolean
local function Assignable(plate)
	local mode = modes[plate]
	return mode == 'drawn' or mode == 'hidden'
end

local STATES = { 'target', 'focus', 'mouseover' }
local STATE_MESSAGES = { target = 'TARGET_CHANGED', focus = 'FOCUS_CHANGED', mouseover = 'MOUSEOVER_CHANGED' }
local ARENA_TOKENS = { 'arena1', 'arena2', 'arena3', 'arena4', 'arena5' }
local FIGHT_KINDS = { enemyNPC = true, minor = true }
local COLORS = { colors = true }
local EMPTY = {}

Driver.POLL_PER_SECOND = 4 -- fact checks per plate per second
Driver.POLL_MAX_PER_TICK = 24 -- budget per 0.1 s tick, however many plates show
Driver.MOUSEOVER_TICK = 0.1
Driver.KICK_TICK = 0.2
Driver.QUEST_DELAY = 0.5
Driver.RANGE_YARDS = 40
Driver.CLICK_THROUGH = 10000

local FRIENDLY_PLATE = (Enum and Enum.NamePlateType and Enum.NamePlateType.Friendly) or 0

-- Settings the place automation may write; bitfields are listed by name and bit key
local STACK_BITS = { 'enemy', 'friendly' }
local AURA_BIT_CVARS = { 'nameplateEnemyNpcAuraDisplay', 'nameplateEnemyPlayerAuraDisplay' }
local AURA_BITS = { 'buffs', 'debuffs', 'crowdControl' }
local PIN_CVARS = { 'nameplateMinScale', 'nameplateMaxScale', 'nameplateSelectedScale' }

local CONTEXT_KEYS = { 'place', 'instanceType', 'difficultyID', 'inInstance', 'inCombat', 'resting', 'role', 'inGroup', 'groupSize', 'petTank', 'playerLevel', 'challengeActive' }
local lastContext = {}
local lastTanks = {}
local changedKeys = {} -- keys of the last ReadContext that changed (reused)

----------------------------------------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------------------------------------

local function InCombat()
	return InCombatLockdown and InCombatLockdown() and true or false
end

---Scale that maps our UI units onto the base plate's coordinate space. 1 everywhere but Mists,
---where base plates do not follow UIParent's scale (Quirk 'uiParentScale', S1). This corrects a
---coordinate space; plate sizes and target emphasis never use SetScale.
---@return number
local function CoordScale()
	if P.Caps:Quirk('uiParentScale') and UIParent and UIParent.GetScale then
		local scale = Secret.Plain(UIParent:GetScale())
		if type(scale) == 'number' and scale > 0 then
			return scale
		end
	end
	return 1
end
Driver.CoordScale = CoordScale

---True when the game places plates under units (nameplateOtherAtBase), so ours hang from the
---base plate's top edge instead of standing on its bottom edge.
---@return boolean
local function ReadAtBase()
	local value = P.CVars:Get('nameplateOtherAtBase')
	return value ~= nil and value ~= '0' and value ~= ''
end

local function ListAdd(plate)
	if listIndex[plate] then
		return
	end
	local list = Driver.list
	list[#list + 1] = plate
	listIndex[plate] = #list
end

local function ListRemove(plate)
	local index = listIndex[plate]
	if not index then
		return
	end
	local list = Driver.list
	local last = list[#list]
	list[index] = last
	listIndex[last] = index
	list[#list] = nil
	listIndex[plate] = nil
end

---A behavior setting for the current place: profile.behavior.places[place][key] wins.
---@param key string
---@return any
function Driver:Behavior(key)
	local profile = P.db and P.db.profile
	local behavior = profile and profile.behavior
	if type(behavior) ~= 'table' then
		return nil
	end
	local places = behavior.places
	local here = type(places) == 'table' and places[P.Context.place]
	if type(here) == 'table' and here[key] ~= nil then
		return here[key]
	end
	return behavior[key]
end

---True while the Driver may change client-wide state: the engine is on, the profile wants
---plates, and the tester switch was not turned off this session (its settings are already back).
---@return boolean
function Driver:OwnsSettings()
	if not (self.active and self.standing) then
		return false
	end
	local Config = P.Config
	if Config and Config.GetSessionEngine and Config:GetSessionEngine() ~= 'old' and Config:GetEngineChoice() == 'old' then
		return false
	end
	return true
end

----------------------------------------------------------------------------------------------------
-- Lookup
----------------------------------------------------------------------------------------------------

---Our plate drawn on a base nameplate (nil while nothing is drawn there).
---@param base table
---@return Plates.Plate|nil
function Driver:GetPlate(base)
	local plate = base and self.byBase[base]
	if plate and self.bound[plate] then
		return plate
	end
	return nil
end

---Our drawn plate for a unit token ('target', 'nameplate3'); pcall-guarded (S14).
---@param unit string
---@return Plates.Plate|nil
function Driver:GetPlateForUnit(unit)
	return self:GetPlate(P.Source.PlateForUnit(unit))
end

---Call fn(plate) for every bound plate.
---@param fn fun(plate: Plates.Plate)
function Driver:ForEachPlate(fn)
	for plate in pairs(self.bound) do
		fn(plate)
	end
end

---Number of plates drawing right now.
---@return integer
function Driver:CountBound()
	local count = 0
	for _ in pairs(self.bound) do
		count = count + 1
	end
	return count
end

---How a plate is shown: 'drawn', 'hidden' (Show mode), 'widgets' (widget-only), 'self' (the
---player's own plate, left to Blizzard), 'blizzard' (a game object, left to Blizzard), nil.
---@param plate Plates.Plate
---@return string|nil
function Driver:ModeOf(plate)
	return modes[plate]
end

----------------------------------------------------------------------------------------------------
-- Styles and sizes
----------------------------------------------------------------------------------------------------

---Classify and assign a plate, resolve its style and lay it out when the key changed. Plates in
---Show mode 'hidden' are not laid out.
---@param plate Plates.Plate
---@return boolean relaidOut
function Driver:Reassign(plate)
	local profile = P.db and P.db.profile or EMPTY
	local situation = P.Situation.Classify(plate.facts)
	plate.situation = situation
	P.Situation.Assign(situation, plate.env, profile, plate.assignment)
	if plate.assignment.mode == 'hidden' then
		return false
	end
	local resolved = P.Styles.Merge:Resolve(plate.assignment.style, situation, plate.assignment.size)
	return plate:ApplyStyle(resolved)
end

local sizeEnv = { facts = {}, states = {} }
local sizeOut = { deps = {} }

---Base plate size covering the largest click area of any style a kind of plate can use (the base
---assignment of every kind plus every style or size a "When" entry can pick). Applied with
---C_NamePlate.SetNamePlateSize out of combat (times UIParent:GetScale() under Quirk
---'uiParentScale'). Kinds hidden by their Show mode are left out.
---@return integer width
---@return integer height
function Driver:ComputePlateSize()
	local Merge, Situation = P.Styles.Merge, P.Situation
	local profile = P.db and P.db.profile or EMPTY
	local width, height = 1, 1
	local function Consider(styleId, situation, size)
		local resolved = Merge:Resolve(styleId, situation, size)
		local w, h = Merge.SizeForRect(resolved.regions.click)
		width, height = math.max(width, w), math.max(height, h)
	end
	-- The base assignment of each kind, without "When" entries (they are counted below, whichever
	-- place the player is in now)
	local view = { style = profile.style, size = profile.size, assign = profile.assign, modes = profile.modes }
	sizeEnv.ctx = P.Context
	for _, situation in ipairs(Situation.KINDS) do
		Situation.Assign(situation, sizeEnv, view, sizeOut)
		if sizeOut.mode ~= 'hidden' then
			Consider(sizeOut.style, situation, sizeOut.size)
		end
	end
	for _, entry in ipairs(type(profile.when) == 'table' and profile.when or EMPTY) do
		if not entry.off and entry.mode ~= 'hidden' and (entry.style or entry.size or entry.mode) then
			for _, situation in ipairs(entry.kinds or Situation.KINDS) do
				local style = entry.style or (profile.assign and profile.assign[situation]) or Situation.DEFAULT_ASSIGN[situation] or profile.style or 'host'
				if entry.mode == 'name' then
					style = Situation.NAME_STYLE
				end
				Consider(style, situation, entry.size or profile.size or 'medium')
			end
		end
	end
	return width, height
end

local function ApplySizeAfterCombat()
	Driver:ApplyPlateSize(true)
end

---Read the game's own base size (to give it back later).
local function RememberBlizzardSize()
	if not (C_NamePlate and C_NamePlate.GetNamePlateSize) then
		return
	end
	local ok, w, h = pcall(C_NamePlate.GetNamePlateSize)
	w, h = Secret.Plain(w), Secret.Plain(h)
	if ok and type(w) == 'number' and type(h) == 'number' then
		Driver.blizzSize = Driver.blizzSize or {}
		Driver.blizzSize[1], Driver.blizzSize[2] = w, h
	end
end

---Size the base plates to our largest click area (out of combat; queued after combat otherwise).
---@param force boolean Write even when the size did not change (Blizzard just set its own)
---@return boolean written
function Driver:ApplyPlateSize(force)
	if not (self:OwnsSettings() and C_NamePlate and C_NamePlate.SetNamePlateSize) then
		return false
	end
	if InCombat() then
		P.Scheduler:AfterCombat('Driver.size', ApplySizeAfterCombat)
		return false
	end
	local width, height = self:ComputePlateSize()
	local scale = CoordScale()
	width, height = math.ceil(width * scale), math.ceil(height * scale)
	local applied = self.appliedSize
	if not force and applied[1] == width and applied[2] == height then
		return false
	end
	if not self.blizzSize or self.blizzDirty then
		-- Blizzard set its own size since our last write (in combat, its write went through and
		-- ours waited): that is the size to give back
		RememberBlizzardSize()
		self.blizzDirty = nil
	end
	local ok = pcall(C_NamePlate.SetNamePlateSize, width, height)
	if ok then
		applied[1], applied[2] = width, height
	end
	return ok
end

local function ApplyInsetsAfterCombat()
	Driver:ApplyInsets()
end

---Friendly plates click through (hit-test insets), when the player asks for it. Written only
---after our own changes, out of combat.
function Driver:ApplyInsets()
	if not (self:OwnsSettings() and P.Caps:Get('hitTestInsets')) then
		return
	end
	local want = self:Behavior('clickThroughFriendly')
	if want == nil then
		self:RestoreInsets()
		return
	end
	local value = want and self.CLICK_THROUGH or 0
	if self.appliedInset == value then
		return
	end
	if InCombat() then
		P.Scheduler:AfterCombat('Driver.insets', ApplyInsetsAfterCombat)
		return
	end
	local manager = C_NamePlateManager
	if not self.blizzInsets and manager.GetNamePlateHitTestInsets then
		local ok, l, r, t, b = pcall(manager.GetNamePlateHitTestInsets, FRIENDLY_PLATE)
		l, r, t, b = Secret.Plain(l), Secret.Plain(r), Secret.Plain(t), Secret.Plain(b)
		if ok and type(l) == 'number' and type(r) == 'number' and type(t) == 'number' and type(b) == 'number' then
			self.blizzInsets = { l, r, t, b }
		else
			self.blizzInsets = { 0, 0, 0, 0 }
		end
	end
	if pcall(manager.SetNamePlateHitTestInsets, FRIENDLY_PLATE, value, value, value, value) then
		self.appliedInset = value
	end
end

local restoreQueued = false

local function RestoreAfterCombat()
	restoreQueued = false
	P:UnregisterEvent('PLAYER_REGEN_ENABLED', 'Driver.restore')
	if not Driver.standing then
		Driver:RestoreClientState()
		-- Unit frames the game kept locked in combat get their parent and rolesets back now
		P.Suppress:RestoreAll()
	end
end

---Give the game back its plate size and insets (stand down, engine off). In combat it waits for
---combat to end on its own event, so it works even while the engine is off.
function Driver:RestoreClientState()
	if InCombat() then
		if not restoreQueued then
			restoreQueued = true
			P:RegisterEvent('PLAYER_REGEN_ENABLED', 'Driver.restore', RestoreAfterCombat)
		end
		return
	end
	local size = self.blizzSize
	-- After Blizzard set its own size (blizzDirty) and ours waited for combat, the plates already
	-- have Blizzard's size
	if size and not self.blizzDirty and C_NamePlate and C_NamePlate.SetNamePlateSize then
		pcall(C_NamePlate.SetNamePlateSize, size[1], size[2])
	end
	self.blizzSize, self.blizzDirty = nil, nil
	self.appliedSize[1], self.appliedSize[2] = 0, 0
	self:RestoreInsets()
end

---Put the friendly insets back to what the game had.
function Driver:RestoreInsets()
	local insets = self.blizzInsets
	if not insets or InCombat() then
		return
	end
	local manager = C_NamePlateManager
	if manager and manager.SetNamePlateHitTestInsets then
		pcall(manager.SetNamePlateHitTestInsets, FRIENDLY_PLATE, insets[1], insets[2], insets[3], insets[4])
	end
	self.blizzInsets = nil
	self.appliedInset = nil
end

----------------------------------------------------------------------------------------------------
-- Click and stacking frames
----------------------------------------------------------------------------------------------------

---Give a plate its click-area and stacking-bounds frames and hand the stacking frame to the base.
---@param plate Plates.Plate
---@param base table
function Driver:Attach(plate, base)
	local root = plate.root
	if not plate.click then
		local click = CreateFrame('Frame', nil, root)
		click:SetSize(1, 1)
		if P.Caps:Get('pingable') then
			local ok, ping = pcall(CreateFrame, 'Frame', nil, click, 'PingableUnitFrameTemplate')
			if ok and ping then
				ping:SetAllPoints(click)
				plate.ping = ping
			end
		end
		plate.click = click
	end
	if not plate.stack then
		local stack = CreateFrame('Frame', nil, root)
		-- The engine measures what a frame draws: a transparent full-size texture gives it a size
		local fill = stack:CreateTexture(nil, 'BACKGROUND')
		fill:SetColorTexture(1, 1, 1, 0)
		fill:SetAllPoints(stack)
		stack:SetSize(1, 1)
		plate.stack = stack
	end
	if P.Caps:Quirk('uiParentScale') then
		root:SetScale(CoordScale())
	end
	if base.SetStackingBoundsFrame then
		pcall(base.SetStackingBoundsFrame, base, plate.stack)
	end
	regionKey[plate] = nil
	self.byBase[base] = plate
end

local function PlaceRect(frame, root, rect)
	if frame:GetParent() ~= root then
		frame:SetParent(root)
	end
	frame:ClearAllPoints()
	frame:SetPoint('TOPLEFT', root, 'CENTER', rect.left, rect.top)
	frame:SetSize(math.max(rect.right - rect.left, 1), math.max(rect.top - rect.bottom, 1))
end

---Point the plate root at its base and size the click and stacking frames from the style.
---@param plate Plates.Plate
function Driver:LayoutRegions(plate)
	local style, base = plate.style, plate.base
	if not (style and base and plate.click) then
		return
	end
	local click = style.regions.click
	local root = plate.root
	local low = self:HangsLow(plate)
	root:ClearAllPoints()
	if low then
		root:SetPoint('CENTER', base, 'TOP', 0, -click.top)
	else
		root:SetPoint('CENTER', base, 'BOTTOM', 0, -click.bottom)
	end
	PlaceRect(plate.click, root, click)
	PlaceRect(plate.stack, root, style.regions.stack)
	regionKey[plate], regionLow[plate] = style.key, low
end

---True when the game places this plate under its unit: nameplateOtherAtBase moves hostile plates
---only (friendly and neutral ones stay above heads), so ours hang from the base plate's top edge.
---@param plate Plates.Plate
---@return boolean
function Driver:HangsLow(plate)
	if not self.atBase then
		return false
	end
	local reaction = plate.facts.reaction
	if type(reaction) == 'number' then
		return reaction <= 3
	end
	return plate.facts.canAttack == true
end

---True when a plate's click and stacking frames no longer match its style or position.
---@param plate Plates.Plate
---@return boolean
function Driver:RegionsStale(plate)
	return regionKey[plate] ~= plate.styleKey or regionLow[plate] ~= self:HangsLow(plate)
end

---nameplateOtherAtBase changed: read it again and move every drawn plate.
function Driver:AtBaseChanged()
	local atBase = ReadAtBase()
	if atBase == self.atBase then
		return
	end
	self.atBase = atBase
	for plate in pairs(self.bound) do
		self:LayoutRegions(plate)
	end
end

---Hand the click area to our click frame whenever the base allows it (the add tick, and out of
---combat; base:CanChangeHitTestPoints() decides). The S1 fallback (Caps 'hitTest' false) leaves
---Blizzard's click area.
---@param plate Plates.Plate
---@return boolean rebound
function Driver:BindClick(plate)
	local base = plate.base
	if not (base and plate.click and base.CanChangeHitTestPoints and base.SetAllHitTestPoints) then
		return false
	end
	if not P.Caps:Get('hitTest') then
		return false
	end
	local ok, can = pcall(base.CanChangeHitTestPoints, base)
	if not ok or can ~= true then
		return false
	end
	local cleared = not base.ClearAllHitTestPoints or pcall(base.ClearAllHitTestPoints, base)
	local set = cleared and pcall(base.SetAllHitTestPoints, base, plate.click)
	if not self.hitTestChecked then
		self.hitTestChecked = true
		local works = false
		if set and base.GetHitTestPoints then
			local okGet, points = pcall(base.GetHitTestPoints, base)
			works = okGet and Secret.CanIndex(points) and #points > 0 or false
		end
		P.Caps:Record('hitTest', works)
		if not works then
			P.log.warning('Plates cannot change where they take clicks on this client; the game keeps its own click area')
		end
	end
	return set and true or false
end

local function RebindAll()
	for plate in pairs(Driver.bound) do
		Driver:BindClick(plate)
	end
end

---Give every drawn plate its click area again after Blizzard set its own (UpdateNamePlateOptions:
---options, display size, nameplate settings; UpdateShowOnlyName). Now when combat allows it,
---else once combat ends; a plate added meanwhile binds on its own add tick.
function Driver:RebindClicks()
	if not P.Caps:Get('hitTest') then
		return
	end
	P.Scheduler:AfterCombat('Driver.click', RebindAll)
end

local function RebindSoon()
	if Driver.active then
		Driver:RebindClicks()
	end
end

---Click and stacking frames cover the whole base again (standing down): Blizzard's plates keep
---taking clicks and stacking until their next add sets them up.
---@param plate Plates.Plate
local function CoverBase(plate)
	local base = plate.base
	if not base then
		return
	end
	for _, frame in ipairs({ plate.click, plate.stack }) do
		if frame then
			frame:SetParent(base)
			frame:ClearAllPoints()
			frame:SetAllPoints(base)
		end
	end
	regionKey[plate] = nil
end

----------------------------------------------------------------------------------------------------
-- States (target, focus, mouseover)
----------------------------------------------------------------------------------------------------

local secretAnswered = setmetatable({}, weak) -- plate -> { [state] = true } set from hidden answers (S4)

---Set a plain state on a plate. A state the plate last got as a hidden answer first gets its
---state-tied parts back at their own alpha (SetStateSecret faded them through the engine), so a
---later plain answer never shows a part that is still faded out.
---@param plate Plates.Plate
---@param state string
---@param on boolean
local function SetPlateState(plate, state, on)
	local answered = secretAnswered[plate]
	if not (answered and answered[state]) then
		plate:SetState(state, on)
		return
	end
	answered[state] = nil
	plate:SetStateSecret(state, true)
	plate:SetState(state, true)
	if not on then
		plate:SetState(state, false)
	end
end
Driver.SetPlateState = SetPlateState

---Whether a plate stands for a state's unit, asked of the plate's own source: true or false when
---readable; otherwise the state is set from the hidden answer (S4) and nil comes back. No answer
---at all (the game would not compare the two tokens) counts as hidden too: the state-tied parts
---fade out through the engine, and nothing fades the other plates.
---@param plate Plates.Plate
---@param state string
---@return boolean|nil
local function AskPlate(plate, state)
	local src = sources[plate]
	if not src then
		return false
	end
	local answerSecret = src:IsUnitSecret(state)
	if type(answerSecret) ~= 'nil' then
		local same, readable = Secret.Plain(answerSecret)
		if readable then
			SetPlateState(plate, state, same == true)
			return same == true
		end
	end
	local answered = secretAnswered[plate]
	if not answered then
		answered = {}
		secretAnswered[plate] = answered
	end
	answered[state] = true
	plate:SetStateSecret(state, answerSecret)
	return nil
end

local function MouseUp()
	P:UnregisterEvent('GLOBAL_MOUSE_UP', 'Driver.mouse')
	Driver:UpdateState('mouseover')
end

local function MouseoverTick()
	if P.Source.UnitExists('mouseover') then
		return
	end
	P.Scheduler:Cancel('Driver.mouseover')
	-- Mouseover reads as gone while a mouse button is held (camera turning): wait for the button
	if IsMouseButtonDown and IsMouseButtonDown() then
		P:RegisterEvent('GLOBAL_MOUSE_UP', 'Driver.mouse', MouseUp)
		return
	end
	Driver:UpdateState('mouseover')
end
Driver.MouseoverTick = MouseoverTick

---Find which plate shows a state's unit and move the state there.
---@param state 'target'|'focus'|'mouseover'
function Driver:UpdateState(state)
	local Source = P.Source
	local exists = self.standing and Source.UnitExists(state) or false
	local base = exists and Source.PlateForUnit(state) or nil
	local plate = base and self.byBase[base] or nil
	if plate and not self.bound[plate] then
		plate = nil
	end
	local prev = self.statePlates[state]
	local wasHidden = self.secretStates[state]
	local secret = false
	if exists and not base then
		-- No plate found: the unit has none in view, or the game will not say which (S4)
		plate = nil
		for each in pairs(self.bound) do
			local answer = AskPlate(each, state)
			if answer == nil then
				secret = true
			elseif answer then
				plate = each
			end
		end
	elseif wasHidden then
		for each in pairs(self.bound) do
			SetPlateState(each, state, each == plate)
		end
	else
		if prev and prev ~= plate then
			SetPlateState(prev, state, false)
		end
		if plate then
			SetPlateState(plate, state, true)
		end
	end
	self.statePlates[state] = plate
	self.secretStates[state] = secret or nil
	self.exists[state] = exists
	if state == 'target' then
		self:SetHasTarget(exists and not secret)
	end
	if prev and prev ~= plate then
		self:UpdateFade(prev)
	end
	if plate then
		self:UpdateFade(plate)
	end
	if state == 'mouseover' then
		if exists and (plate or secret) then
			if not P.Scheduler:IsRunning('Driver.mouseover') then
				P.Scheduler:Every('Driver.mouseover', self.MOUSEOVER_TICK, MouseoverTick)
			end
		else
			P.Scheduler:Cancel('Driver.mouseover')
		end
	end
	local message = STATE_MESSAGES[state]
	if secret or wasHidden then
		-- Every plate may have a new answer (hidden answers, or plain ones after hidden ones)
		self:Relay(message)
		return
	end
	-- Plain answers: only the plate that lost the state and the one that got it changed (the
	-- conditions and parts that listen read the plate's own state), so only they hear about it
	P:Fire(message)
	if prev and prev ~= plate and self.bound[prev] then
		prev:OnMessage(message)
	end
	if plate then
		plate:OnMessage(message)
	end
end

---P.Context.hasTarget drives the fade of other plates; every plate re-applies its emphasis.
---@param hasTarget boolean
function Driver:SetHasTarget(hasTarget)
	if P.Context.hasTarget == hasTarget then
		return
	end
	P.Context.hasTarget = hasTarget
	for plate in pairs(self.bound) do
		plate:ApplyEmphasis(false)
	end
end

---States for a plate that just started drawing.
---@param plate Plates.Plate
function Driver:ApplyStates(plate)
	local Source = P.Source
	for i = 1, #STATES do
		local state = STATES[i]
		if self.exists[state] then
			local base = Source.PlateForUnit(state)
			if base then
				if base == plate.base then
					local prev = self.statePlates[state]
					if prev and prev ~= plate then
						SetPlateState(prev, state, false)
					end
					SetPlateState(plate, state, true)
					self.statePlates[state] = plate
				end
			else
				local answer = AskPlate(plate, state)
				if answer then
					self.statePlates[state] = plate
				elseif answer == nil and not self.secretStates[state] then
					self.secretStates[state] = true
					if state == 'target' then
						self:SetHasTarget(false)
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Fades (only enemies that are fighting, range)
----------------------------------------------------------------------------------------------------

---Root alpha from the fighting filter and range fade.
---@param plate Plates.Plate
function Driver:UpdateFade(plate)
	if not self.bound[plate] then
		return
	end
	local alpha = 1
	local states = plate.states
	if self.onlyFighting and FIGHT_KINDS[plate.situation] and plate.facts.inCombat == false and not states.target and not states.focus then
		alpha = 0
	end
	local rangeAlpha = self.rangeAlpha
	if rangeAlpha and inRange[plate] == false and alpha > rangeAlpha then
		alpha = rangeAlpha
	end
	if fadeAlpha[plate] ~= alpha then
		fadeAlpha[plate] = alpha
		plate.root:SetAlpha(alpha)
	end
end

---Pick the requested distance from the range library; fade is off without a checker.
function Driver:UpdateRangeChecker()
	self.rangeChecker, self.rangeHow = nil, nil
	local alpha = self:Behavior('rangeFade')
	self.rangeAlpha = type(alpha) == 'number' and math.max(0, math.min(1, alpha)) or nil
	if not self.rangeAlpha then
		return
	end
	local yards = self:Behavior('rangeYards')
	yards = type(yards) == 'number' and yards or self.RANGE_YARDS
	local lib = LibStub and LibStub('LibRangeCheck-3.0', true)
	if lib and lib.GetHarmMaxChecker then
		local ok, checker = pcall(lib.GetHarmMaxChecker, lib, yards, true)
		if ok and type(checker) == 'function' then
			self.rangeChecker, self.rangeHow = checker, 'library'
			return
		end
	end
	self.rangeAlpha = nil
end

---Read the behavior settings the plates follow (fighting filter, range fade).
function Driver:ReadBehavior()
	self.onlyFighting = self:Behavior('onlyFighting') == true
	self:UpdateRangeChecker()
	P.util.Wipe(inRange)
end

local L = P.L

---Whether a plate behavior works on this client, and why not (6th grade wording, for options).
---@param id 'rangeFade'|'onlyFighting'|'clickThroughFriendly'|'fadeBehindWalls'|'stacking'|'friendlyNames'|'pinScale'
---@return boolean available
---@return string|nil reason
function Driver:FeatureState(id)
	local CVars = P.CVars
	if id == 'rangeFade' then
		local lib = LibStub and LibStub('LibRangeCheck-3.0', true)
		if lib and lib.GetHarmMaxChecker then
			if not P.Caps:Get('rangeReadable') then
				return false, L['The game hides how far away enemies are here, so plates do not fade.']
			end
			return true
		end
		return false, L['This needs a way to tell how far away enemies are, and none was found.']
	elseif id == 'onlyFighting' then
		if not P.Caps:Get('unitCombat') then
			return false, L['The game hides whether enemies are fighting, so every enemy shows.']
		end
		return true
	elseif id == 'clickThroughFriendly' then
		if not P.Caps:Get('hitTestInsets') then
			return false, L['This version of the game cannot let clicks pass through plates.']
		end
		return true
	elseif id == 'fadeBehindWalls' then
		if not CVars:Exists('nameplateOccludedAlphaMult') then
			return false, L['This version of the game cannot fade plates behind walls.']
		end
		return true
	elseif id == 'stacking' then
		if not (CVars:Exists('nameplateStackingTypes') and P.Caps:Get('cvarBitfield')) then
			return false, L['This version of the game cannot keep plates from overlapping.']
		end
		return true
	elseif id == 'friendlyNames' then
		if not CVars:Exists('nameplateShowOnlyNameForFriendlyPlayerUnits') then
			return false, L['This version of the game cannot show names only on friendly plates.']
		end
		return true
	elseif id == 'pinScale' then
		if not CVars:Exists('nameplateMinScale') then
			return false, L['This version of the game does not shrink far away plates.']
		end
		return true
	end
	return true
end

----------------------------------------------------------------------------------------------------
-- Adding and removing plates
----------------------------------------------------------------------------------------------------

local function OnFactEvent(frame)
	local plate = framePlate[frame]
	if plate then
		Driver:FactsChanged(plate)
	end
end

---Follow UNIT_FACTION and UNIT_CLASSIFICATION_CHANGED for the plate's unit on its own frame
---(unit tokens in payloads can be secret, so no shared frame indexes plates by unit).
---@param plate Plates.Plate
---@param unit string|nil nil stops
local function WatchFacts(plate, unit)
	local frame = factFrames[plate]
	if not frame then
		if not unit then
			return
		end
		frame = CreateFrame('Frame')
		frame:SetScript('OnEvent', OnFactEvent)
		factFrames[plate] = frame
		framePlate[frame] = plate
	end
	frame:UnregisterAllEvents()
	if unit then
		pcall(frame.RegisterUnitEvent, frame, 'UNIT_FACTION', unit)
		pcall(frame.RegisterUnitEvent, frame, 'UNIT_CLASSIFICATION_CHANGED', unit)
	end
end

---NAME_PLATE_CREATED: a plate for a new base nameplate.
---@param base table
---@return Plates.Plate|nil
function Driver:OnCreated(base)
	if not base then
		return nil
	end
	local plate = self.byBase[base]
	if not plate then
		plate = P.Pool:Acquire(base)
		self:Attach(plate, base)
	end
	return plate
end

---NAME_PLATE_UNIT_ADDED.
---@param unit string
function Driver:OnAdded(unit)
	if not self.standing then
		return
	end
	local base = P.Source.PlateForUnit(unit)
	if not base then
		return
	end
	local plate = self.byBase[base] or self:OnCreated(base)
	self:Show(plate, base, unit)
end

---Start showing a unit on a plate.
---@param plate Plates.Plate
---@param base table
---@param unit string
function Driver:Show(plate, base, unit)
	if self.units[plate] then
		self:Release(plate)
	end
	local src = sources[plate]
	if src then
		src:SetUnit(unit)
	else
		src = P.Source.NewLive(unit)
		sources[plate] = src
	end
	src:SetGuarded(self.guarded)
	self.units[plate] = unit
	local facts = src:ReadFacts(plate.facts)
	if facts.isPlayer and facts.canAttack == false and P.Source.PlateForUnit('player') == base then
		-- The player's own plate (the personal plate on the Classic family) stays Blizzard's
		modes[plate] = 'self'
		plate.root:Hide()
		P.Suppress:Release(base)
		return
	end
	if facts.isGameObject or facts.widgetsOnly then
		-- Blizzard's plate for an interact object is its name: leave it to Blizzard
		modes[plate] = facts.widgetsOnly and 'widgets' or 'blizzard'
		plate.root:Hide()
		P.Suppress:Release(base)
		return
	end
	P.Suppress:Apply(base, plate, facts)
	if facts.widgetsOnly then
		modes[plate] = 'widgets'
		plate.root:Hide()
		return
	end
	ListAdd(plate)
	WatchFacts(plate, unit)
	if P.Caps:Get('simplified') then
		local simplified = P.Caps:Quirk('engineSimplified') and P.Situation.Classify(facts) == 'minor'
		pcall(C_NamePlateManager.SetNamePlateSimplified, unit, simplified)
	end
	self:Present(plate)
	self:EnsurePoller()
end

---Assign the plate and draw it, or keep it hidden for Show mode 'hidden'.
---@param plate Plates.Plate
function Driver:Present(plate)
	local relaid = self:Reassign(plate)
	if plate.assignment.mode == 'hidden' then
		modes[plate] = 'hidden'
		plate.root:Hide()
		return
	end
	modes[plate] = 'drawn'
	if relaid or self:RegionsStale(plate) then
		self:LayoutRegions(plate)
	end
	local unit = self.units[plate]
	self.bound[plate] = true
	if plate.ping then
		plate.ping:SetAttribute('unit', unit)
	end
	plate:Bind(unit, sources[plate])
	-- Hand the stacking frame over again on every add (cheap; Blizzard sets its plates up on each
	-- add and must keep stacking by our frame)
	local base = plate.base
	if base and base.SetStackingBoundsFrame and plate.stack then
		pcall(base.SetStackingBoundsFrame, base, plate.stack)
	end
	-- Legal on the add tick, and out of combat (catching up, a hidden kind shown again); BindClick
	-- asks CanChangeHitTestPoints itself
	self:BindClick(plate)
	self:ApplyStates(plate)
	if P.Context.place == 'arena' then
		self:ArenaFor(plate)
	end
	inRange[plate] = nil
	self:UpdateFade(plate)
	if relaid or plate.pendingConfigure then
		plate:Configure()
	end
	P:Fire('PLATE_ADDED', plate, unit)
	if P.Context.kickSpell and not P.Scheduler:IsRunning('Driver.kick') then
		self:CheckKick(false)
	end
end

---Stop drawing a plate (Show mode turned hidden, the unit left, standing down).
---@param plate Plates.Plate
function Driver:Unbind(plate)
	if not self.bound[plate] then
		return
	end
	local unit = self.units[plate]
	self.bound[plate] = nil
	local answered = secretAnswered[plate]
	for i = 1, #STATES do
		local state = STATES[i]
		if self.statePlates[state] == plate then
			self.statePlates[state] = nil
		end
		if answered and answered[state] then
			SetPlateState(plate, state, false)
		end
	end
	plate:Unbind()
	plate.arenaIndex = nil
	P:Fire('PLATE_REMOVED', plate, unit)
end

---The plate's unit went away.
---@param plate Plates.Plate
function Driver:Release(plate)
	if self.bound[plate] then
		self:Unbind(plate)
	else
		plate.root:Hide()
	end
	self.units[plate] = nil
	modes[plate] = nil
	inRange[plate] = nil
	ListRemove(plate)
	WatchFacts(plate, nil)
	local src = sources[plate]
	if src then
		src:SetUnit(nil)
	end
	if #self.list == 0 then
		P.Scheduler:Cancel('Driver.poll')
	end
end

---NAME_PLATE_UNIT_REMOVED (the token still works while it is delivered).
---@param unit string
function Driver:OnRemoved(unit)
	local base = P.Source.PlateForUnit(unit)
	local plate = base and self.byBase[base]
	if not plate and Secret.CanAccess(unit) then
		for each, shown in pairs(self.units) do
			if shown == unit then
				plate = each
				break
			end
		end
	end
	if plate and self.units[plate] then
		self:Release(plate)
	end
end

---A plate's facts changed (UNIT_FACTION, UNIT_CLASSIFICATION_CHANGED): read them again.
---@param plate Plates.Plate
function Driver:FactsChanged(plate)
	local src = sources[plate]
	if not (src and self.units[plate]) or not Assignable(plate) then
		return
	end
	src:ReadFacts(plate.facts)
	if not self:Reevaluate(plate) and self.bound[plate] then
		plate:UpdateAll('FULL')
	end
	-- A unit turning hostile or friendly moves between above heads and under units (OtherAtBase)
	if self.bound[plate] and self:RegionsStale(plate) then
		self:LayoutRegions(plate)
	end
	self:UpdateFade(plate)
end

---Assign a showing plate again: draw it, hide it or lay it out anew. Not the add tick, so the
---hit-test points stay where they are.
---@param plate Plates.Plate
---@return boolean refreshed The plate drew everything again
function Driver:Reevaluate(plate)
	if not Assignable(plate) or not self.units[plate] then
		return false
	end
	if not self.bound[plate] then
		self:Present(plate)
		return self.bound[plate] == true
	end
	local relaid = self:Reassign(plate)
	if plate.assignment.mode == 'hidden' then
		self:Unbind(plate)
		modes[plate] = 'hidden'
		return true
	end
	if relaid then
		self:LayoutRegions(plate)
		plate:UpdateAll('FULL')
		plate:Configure()
		return true
	end
	return false
end

---Draw every plate that shows a unit right now (engine or profile turned on mid-session).
---Not the add tick: hit-test points stay Blizzard's until each plate's next add.
function Driver:CatchUp()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then
		return
	end
	local ok, bases = pcall(C_NamePlate.GetNamePlates)
	if not ok or type(bases) ~= 'table' then
		return
	end
	local missing = 0
	for _, base in ipairs(bases) do
		local token = rawget(base, 'unitToken')
		if type(token) == 'string' then
			self:Show(self:OnCreated(base), base, token)
		else
			missing = missing + 1
		end
	end
	-- Clients whose base plates do not say their unit: ask each nameplate token in turn
	local index, found = 0, 0
	while found < missing and index < #bases + 100 do
		index = index + 1
		local token = 'nameplate' .. index
		local base = P.Source.PlateForUnit(token)
		if base and not self.units[self.byBase[base] or EMPTY] then
			self:Show(self:OnCreated(base), base, token)
			found = found + 1
		end
	end
end

----------------------------------------------------------------------------------------------------
-- The fact poller
----------------------------------------------------------------------------------------------------

---Poll one plate: can-attack, in-combat, range.
---@param plate Plates.Plate
function Driver:PollPlate(plate)
	local src = sources[plate]
	if not src or not Assignable(plate) or not self.units[plate] then
		return
	end
	local facts = plate.facts
	local changed = src:PollFacts(facts)
	if changed then
		local deps = plate.assignment.deps
		if deps.canAttack or deps.inCombat then
			self:Reevaluate(plate)
		end
	end
	if not self.bound[plate] then
		return
	end
	local combatColors = P.Colors:Program('health').readsCombat or P.Colors:Program('border').readsCombat
	if changed or (facts.inCombat == nil and combatColors) then
		plate:OnMessage('FACTS_POLLED')
	end
	if self.onlyFighting and facts.inCombat == nil and FIGHT_KINDS[plate.situation] then
		-- S16: the game hides whether this enemy is fighting; it stays shown
		P.Caps:Record('unitCombat', false)
	end
	if self.rangeChecker then
		local value, readable = src:InRangePlain(self.rangeChecker)
		if readable then
			inRange[plate] = value
		else
			inRange[plate] = nil
			if P.Caps:Get('secrets') then
				P.Caps:Record('rangeReadable', false)
			end
		end
	end
	self:UpdateFade(plate)
end

local function PollTick()
	local self = Driver
	local list = self.list
	local count = #list
	if count == 0 then
		P.Scheduler:Cancel('Driver.poll')
		return
	end
	local per = math.ceil(count * self.POLL_PER_SECOND * P.Scheduler.TICK)
	if per > self.POLL_MAX_PER_TICK then
		per = self.POLL_MAX_PER_TICK
	end
	if per > count then
		per = count
	end
	for _ = 1, per do
		local cursor = self.cursor + 1
		if cursor > #list then
			cursor = 1
		end
		self.cursor = cursor
		local plate = list[cursor]
		if plate then
			self:PollPlate(plate)
		end
	end
end
Driver.PollTick = PollTick

---Start the poller when plates show units (it stops by itself when none do).
function Driver:EnsurePoller()
	if #self.list > 0 and not P.Scheduler:IsRunning('Driver.poll') then
		P.Scheduler:Every('Driver.poll', P.Scheduler.TICK, PollTick)
	end
end

----------------------------------------------------------------------------------------------------
-- Context
----------------------------------------------------------------------------------------------------

---Read P.Context from the game. Returns whether anything changed since the last read, whether
---the other tanks changed, and the set of context keys that changed (a reused table: read it
---during the CONTEXT_CHANGED it rides on, never keep it).
---@param inCombat? boolean Combat state from a combat edge event
---@return boolean changed
---@return boolean tanksChanged
---@return table<string, boolean> keys
function Driver:ReadContext(inCombat)
	local ctx = P.Context
	P.Situation.ReadPlace(ctx)
	P.Source.ReadPlayerContext(ctx, P.db and P.db.profile.role)
	if inCombat ~= nil then
		ctx.inCombat = inCombat
	end
	local changed = false
	P.util.Wipe(changedKeys)
	for i = 1, #CONTEXT_KEYS do
		local key = CONTEXT_KEYS[i]
		if lastContext[key] ~= ctx[key] then
			lastContext[key] = ctx[key]
			changed = true
			changedKeys[key] = true
		end
	end
	local tanks = ctx.tanks or EMPTY
	local tanksChanged = #tanks ~= #lastTanks
	for i = 1, #tanks do
		if lastTanks[i] ~= tanks[i] then
			tanksChanged = true
		end
		lastTanks[i] = tanks[i]
	end
	for i = #tanks + 1, #lastTanks do
		lastTanks[i] = nil
	end
	return changed, tanksChanged, changedKeys
end

---Sources use pcall in arenas and battlegrounds on clients with secrets (restricted PvP tokens).
function Driver:UpdateGuard()
	local place = P.Context.place
	local guarded = P.Caps:Get('secrets') and (place == 'arena' or place == 'battleground') or false
	if guarded == self.guarded then
		return
	end
	self.guarded = guarded
	for plate in pairs(self.units) do
		local src = sources[plate]
		if src then
			src:SetGuarded(guarded)
		end
	end
end

---Context may have changed (an event): read it, then tell everything that depends on it.
---@param inCombat? boolean
function Driver:ContextEvent(inCombat)
	local placeBefore = P.Context.place
	local changed, tanksChanged, keys = self:ReadContext(inCombat)
	self:UpdateGuard()
	if not self.standing then
		return
	end
	if placeBefore ~= P.Context.place then
		self:AtBaseChanged()
		self:ReadBehavior()
		self:UpdateArena()
	end
	if changed then
		self:ApplyPlaceSettings()
		self:ApplyInsets()
		P:Fire('CONTEXT_CHANGED', keys)
	end
	if tanksChanged then
		P:Fire('TANKS_CHANGED')
	end
end

local function ContextNow()
	Driver:ContextEvent()
end

---Re-read the context on the next frame (group and role events come in bursts).
function Driver:QueueContext()
	P.Scheduler:NextFrame('Driver.context', ContextNow)
end

---Only assignments and color programs that read a changed context key are revisited.
function Driver:ContextChanged(message, keys)
	if message ~= 'TANKS_CHANGED' then
		for plate in pairs(self.units) do
			local reassign = keys == nil
			if keys then
				for key in pairs(keys) do
					if plate.assignment.deps[key] then
						reassign = true
						break
					end
				end
			end
			if reassign then
				self:Reevaluate(plate)
			end
			if self.bound[plate] and not plate:EventMapsCurrent() then
				plate:RebuildEvents()
			end
		end
	end
	self:Broadcast(message, keys)
end

---Fire a message on the bus and deliver it to every bound plate.
---@param message string
function Driver:Relay(message, ...)
	P:Fire(message, ...)
	self:Broadcast(message, ...)
end

---Deliver a bus message to every bound plate.
---@param message string
function Driver:Broadcast(message, ...)
	for plate in pairs(self.bound) do
		plate:OnMessage(message, ...)
	end
end

---Fire RESTRICTION_CHANGED when the restriction state changed (always for the game's own event).
---@param always? boolean
function Driver:CheckRestriction(always)
	local restricted = Secret.IsRestricted()
	if always or restricted ~= self.restricted then
		self.restricted = restricted
		P:Fire('RESTRICTION_CHANGED', restricted)
	end
end

local function RestrictionNextFrame()
	Driver:CheckRestriction(false)
end

---Aura settings changed while the game restricted changes: configure those plates now.
function Driver:FlushPendingConfigure()
	if Secret.IsRestricted() then
		return
	end
	for plate in pairs(self.bound) do
		if plate.pendingConfigure then
			plate:Configure()
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Interrupt readiness and quests
----------------------------------------------------------------------------------------------------

local function KickTick()
	Driver:CheckKick(true)
end

---Pick the interrupt the player uses now.
function Driver:UpdateKick()
	local Kicks = P.Data and P.Data.Kicks
	local spell
	if Kicks and Kicks.Choose then
		spell = Kicks:Choose(P.Source.PlayerClass())
	end
	if spell ~= P.Context.kickSpell then
		P.Context.kickSpell = spell
		self.kickReady = 'unknown'
		if self.rangeHow ~= 'library' then
			self:UpdateRangeChecker()
		end
		self:CheckKick(true)
	end
end

local function KickNow()
	Driver:UpdateKick()
end

---KICK_READY_CHANGED when interrupt readiness changes. A hidden answer is sent from the 0.2 s
---task only, never from cooldown events.
---@param fromTick boolean
function Driver:CheckKick(fromTick)
	P.Conditions.RefreshKick()
	local spell = P.Context.kickSpell
	local ready = false
	if spell then
		ready = P.Conditions.KickReadyPlain()
	end
	local hidden = spell ~= nil and ready == nil
	if (hidden and fromTick) or (not hidden and ready ~= self.kickReady) then
		self.kickReady = ready
		self:Relay('KICK_READY_CHANGED')
	end
	if spell and ready ~= true and next(self.bound) ~= nil then
		if not P.Scheduler:IsRunning('Driver.kick') then
			P.Scheduler:Every('Driver.kick', self.KICK_TICK, KickTick)
		end
	else
		P.Scheduler:Cancel('Driver.kick')
	end
end

Driver.QUEST_BUDGET = 8 -- plates whose quest state is read again per tick (each read is a tooltip)

local questQueue = {} -- plates waiting for their quest read (reused list)
local questQueued = setmetatable({}, weak)
local QuestStepTick

---isQuest again on every plate (quest log changed). The reads are spread over ticks
---(QUEST_BUDGET plates each), each plate hears QUESTS_CHANGED right after its own read, and the
---bus hears it once every plate is done.
function Driver:QuestsChanged()
	P.Source.ClearQuestCache()
	P.Scheduler:Cancel('Driver.quests')
	for plate in pairs(self.units) do
		if not questQueued[plate] then
			questQueued[plate] = true
			questQueue[#questQueue + 1] = plate
		end
	end
	self:QuestStep()
end

---Read the next few plates' quest state (Driver:QuestsChanged).
function Driver:QuestStep()
	local done = 0
	while questQueue[1] and done < self.QUEST_BUDGET do
		local plate = table.remove(questQueue)
		questQueued[plate] = nil
		local src = sources[plate]
		if src and self.units[plate] and Assignable(plate) then
			done = done + 1
			local facts = plate.facts
			local before = facts.isQuest
			facts.isQuest = facts.questBoss or (not facts.isPlayer and src:QuestCachedPlain()) or nil
			if before ~= facts.isQuest and plate.assignment.deps.isQuest then
				self:Reevaluate(plate)
			end
			if before ~= facts.isQuest and self.bound[plate] then
				plate:OnMessage('QUESTS_CHANGED')
			end
		end
	end
	if questQueue[1] then
		if not P.Scheduler:IsRunning('Driver.questStep') then
			P.Scheduler:Every('Driver.questStep', 0, QuestStepTick)
		end
		return
	end
	P.Scheduler:Cancel('Driver.questStep')
	P:Fire('QUESTS_CHANGED')
end

QuestStepTick = function()
	Driver:QuestStep()
end

local function QuestsNow()
	Driver:QuestsChanged()
end

----------------------------------------------------------------------------------------------------
-- Arena labels (S18; Text draws them)
----------------------------------------------------------------------------------------------------

---Arena index for one plate (1-5), by frame compare with the arena tokens' plates.
---@param plate Plates.Plate
---@return boolean changed
function Driver:ArenaFor(plate)
	local index = nil
	if P.Context.place == 'arena' and plate.base then
		for i = 1, #ARENA_TOKENS do
			if P.Source.PlateForUnit(ARENA_TOKENS[i]) == plate.base then
				index = i
				break
			end
		end
	end
	if plate.arenaIndex ~= index then
		plate.arenaIndex = index
		return true
	end
	return false
end

local arenaIndexOf = setmetatable({}, weak)

---Arena indexes for every drawn plate; ARENA_CHANGED when any moved.
function Driver:UpdateArena()
	P.util.Wipe(arenaIndexOf)
	if P.Context.place == 'arena' then
		for i = 1, #ARENA_TOKENS do
			local base = P.Source.PlateForUnit(ARENA_TOKENS[i])
			local plate = base and self.byBase[base]
			if plate then
				arenaIndexOf[plate] = i
			end
		end
	end
	local changed = false
	for plate in pairs(self.bound) do
		local index = arenaIndexOf[plate]
		if plate.arenaIndex ~= index then
			plate.arenaIndex = index
			changed = true
		end
	end
	if changed then
		self:Relay('ARENA_CHANGED')
	end
end

----------------------------------------------------------------------------------------------------
-- Place settings (6.7)
----------------------------------------------------------------------------------------------------

---True when the player hid a kind of plate in every place: an explicit Show mode and no "When"
---entry that shows it.
---@param kind string
---@return boolean
local function HiddenEverywhere(kind)
	local profile = P.db and P.db.profile
	local modesSetting = profile and profile.modes
	if not (type(modesSetting) == 'table' and modesSetting[kind] == 'hidden') then
		return false
	end
	for _, entry in ipairs(type(profile.when) == 'table' and profile.when or EMPTY) do
		if not entry.off and entry.mode and entry.mode ~= 'hidden' then
			if not entry.kinds then
				return false
			end
			for _, other in ipairs(entry.kinds) do
				if other == kind then
					return false
				end
			end
		end
	end
	return true
end
Driver.HiddenEverywhere = HiddenEverywhere

local wantValues = {}
local wantBits = {} -- [cvar] = { [bitKey] = on }
local bitTables = {}
local wantRequired = {} -- [cvar] = true for settings the plates need to work (kept after a hand back)

local function WantBit(name, key, on)
	local bits = wantBits[name]
	if not bits then
		bits = bitTables[name] or {}
		bitTables[name] = bits
		P.util.Wipe(bits)
		wantBits[name] = bits
	end
	bits[key] = on
end

---Work out every game setting the place and the profile ask for right now.
local function Collect()
	local self = Driver
	P.util.Wipe(wantValues)
	P.util.Wipe(wantBits)
	P.util.Wipe(wantRequired)
	local ctx = P.Context
	local profile = P.db and P.db.profile or EMPTY
	local CVars = P.CVars
	if type(profile.cvars) == 'table' then
		for name, value in pairs(profile.cvars) do
			if CVars.defs[name] and type(value) ~= 'table' then
				wantValues[name] = value
			end
		end
	end
	local enemies = self:Behavior('enemies')
	if enemies == 'combat' then
		wantValues.nameplateShowEnemies = ctx.inCombat and true or false
	elseif enemies == 'always' then
		wantValues.nameplateShowEnemies = true
	end
	local friendlyPlayers = self:Behavior('friendlyPlayers')
	if friendlyPlayers ~= nil then
		wantValues.nameplateShowFriendlyPlayers = friendlyPlayers and true or false
	end
	local friendlyNPCs = self:Behavior('friendlyNPCs')
	if friendlyNPCs ~= nil then
		wantValues.nameplateShowFriendlyNpcs = friendlyNPCs and true or false
	end
	-- A kind hidden everywhere needs no plate from the game at all
	if HiddenEverywhere('friendlyPlayer') then
		wantValues.nameplateShowFriendlyPlayers = false
	end
	if HiddenEverywhere('friendlyNPC') then
		wantValues.nameplateShowFriendlyNpcs = false
	end
	-- The enemy setting also makes the game's plates for minor enemies (totems, pets, minus mobs):
	-- only turn it off when those are hidden everywhere too. There is no setting for "every enemy
	-- but the minor ones", so with minor enemies shown the game keeps making enemy plates and the
	-- Driver leaves the hidden kinds undrawn.
	if HiddenEverywhere('enemyNPC') and HiddenEverywhere('enemyPlayer') and HiddenEverywhere('minor') then
		wantValues.nameplateShowEnemies = false
	end
	if HiddenEverywhere('minor') then
		wantValues.nameplateShowEnemyMinus = false
		wantValues.nameplateShowEnemyMinions = false
	end
	-- Inside instances the game draws friendly plates itself: names only, in class colors
	if self:Behavior('friendlyNames') == true and ctx.place ~= 'world' then
		wantValues.nameplateShowOnlyNameForFriendlyPlayerUnits = true
		wantValues.nameplateUseClassColorForFriendlyPlayerUnitNames = true
	end
	if self:Behavior('pinScale') == true then
		for i = 1, #PIN_CVARS do
			wantValues[PIN_CVARS[i]] = 1
		end
	end
	local occluded = self:Behavior('fadeBehindWalls')
	local occludedInCombat = ctx.inCombat and self:Behavior('fadeBehindWallsCombat')
	if type(occludedInCombat) == 'number' then
		occluded = occludedInCombat
	end
	if type(occluded) == 'number' then
		wantValues.nameplateOccludedAlphaMult = math.max(0, math.min(1, occluded))
	end
	local stacking = self:Behavior('stacking')
	if type(stacking) == 'table' then
		for i = 1, #STACK_BITS do
			local key = STACK_BITS[i]
			if stacking[key] ~= nil then
				WantBit('nameplateStackingTypes', key, stacking[key] and true or false)
			end
		end
	end
	-- Classic family: Blizzard's enemy aura icons cause taint errors next to addon plates
	if not P.Caps:Get('secrets') then
		for i = 1, #AURA_BIT_CVARS do
			for j = 1, #AURA_BITS do
				WantBit(AURA_BIT_CVARS[i], AURA_BITS[j], false)
			end
			wantRequired[AURA_BIT_CVARS[i]] = true
		end
	end
end

---Write the game settings the place and the profile ask for; give back the ones no longer asked
---for. Runs on place changes, combat edges and setting changes, only while the Driver owns
---settings. Settings someone else changed after us are left alone this session.
function Driver:ApplyPlaceSettings()
	if not self:OwnsSettings() then
		return
	end
	local CVars = P.CVars
	Collect()
	local applied, yielded = self.placeApplied, self.yielded
	local handedBack = self:HandedBack()
	for name, value in pairs(wantValues) do
		if not yielded[name] and not (handedBack and not wantRequired[name]) then
			local result = CVars:Set(name, value, 'place')
			if result ~= 'missing' and result ~= 'locked' then
				applied[name] = true
			end
		end
	end
	for name, bits in pairs(wantBits) do
		if not yielded[name] and not (handedBack and not wantRequired[name]) then
			for key, on in pairs(bits) do
				local result = CVars:SetBit(name, key, on, 'place')
				if result ~= 'missing' and result ~= 'locked' then
					applied[name] = true
				end
			end
		end
	end
	for name in pairs(applied) do
		if wantValues[name] == nil and wantBits[name] == nil then
			applied[name] = nil
			if not yielded[name] then
				CVars:Restore(name)
			end
		end
	end
end

---True after the player gave the game back its settings: the place and the profile stop
---writing them (only the settings the plates need to work stay) until the player changes a
---related setting. Kept per character across reloads.
---@return boolean
function Driver:HandedBack()
	local char = P.db and P.db.char
	return char ~= nil and char.handedBack == true
end

---"Give the game back its settings": cancel queued writes, put back every backed-up setting and
---stop writing them until the player changes a related setting (ClearHandBack).
---@return boolean done false when some settings wait for combat to end
function Driver:HandBack()
	local char = P.db and P.db.char
	if char then
		char.handedBack = true
	end
	P.util.Wipe(self.placeApplied)
	local done = P.CVars:RestoreAll()
	-- The settings the plates need to work come straight back
	if self.standing then
		self:ApplyPlaceSettings()
	end
	return done
end

---The player changed a setting the place settings follow: write them again.
function Driver:ClearHandBack()
	local char = P.db and P.db.char
	if char and char.handedBack ~= nil then
		char.handedBack = nil
	end
end

----------------------------------------------------------------------------------------------------
-- Settings and profile
----------------------------------------------------------------------------------------------------

---Whether the current profile wants our plates (profile.enabled).
---@return boolean
function Driver:ProfileWantsPlates()
	local profile = P.db and P.db.profile
	return not profile or profile.enabled ~= false
end

---Start drawing for the current profile.
function Driver:StandUp()
	if self.standing or not self.active then
		return
	end
	self.standing = true
	P.util.Wipe(self.yielded)
	self.atBase = ReadAtBase()
	self:UpdateKick()
	self:ReadBehavior()
	self:ApplyPlaceSettings()
	self:ApplyPlateSize(false)
	self:ApplyInsets()
	self:CatchUp()
	for i = 1, #STATES do
		self:UpdateState(STATES[i])
	end
	self:UpdateArena()
	P.Pool:Prewarm()
end

---Stop drawing: plates unbind, Blizzard plates come back, settings go back.
function Driver:StandDown()
	if not self.standing then
		return
	end
	local plates = {}
	for plate in pairs(self.units) do
		plates[#plates + 1] = plate
	end
	for i = 1, #plates do
		self:Release(plates[i])
	end
	self.standing = false
	for _, plate in pairs(self.byBase) do
		CoverBase(plate)
	end
	for _, id in ipairs({ 'Driver.poll', 'Driver.mouseover', 'Driver.kick', 'Driver.quests', 'Driver.questStep' }) do
		P.Scheduler:Cancel(id)
	end
	for i = #questQueue, 1, -1 do
		questQueued[questQueue[i]] = nil
		questQueue[i] = nil
	end
	P:UnregisterEvent('GLOBAL_MOUSE_UP', 'Driver.mouse')
	P.util.Wipe(self.statePlates)
	P.util.Wipe(self.secretStates)
	P.util.Wipe(self.exists)
	P.Context.hasTarget = false
	P.Pool:Pause()
	P.Suppress:RestoreAll()
	self:RestoreClientState()
	P.util.Wipe(self.placeApplied)
	P.CVars:RestoreAll()
end

---Settings changed: re-resolve and refresh every plate (look and size re-lay out through a new
---style key; colors and auras refresh in place).
---@param reasons table<string, boolean>
function Driver:RefreshAll(reasons)
	local relayout = reasons.look or reasons.size or reasons.assignment or reasons.auras
	for plate in pairs(self.units) do
		if relayout then
			self:Reevaluate(plate)
		end
		if self.bound[plate] then
			plate:Refresh(reasons)
		end
	end
end

---STORE_CHANGED: profile.enabled, behavior, game settings, plate size, then RefreshAll.
---@param reasons table<string, boolean>
function Driver:SettingsChanged(reasons)
	local wants = self:ProfileWantsPlates()
	if wants ~= self.standing then
		if wants then
			self:StandUp()
		else
			self:StandDown()
		end
		return
	end
	if not self.standing then
		return
	end
	if reasons.cvars or reasons.assignment then
		P.util.Wipe(self.yielded)
		self:ClearHandBack()
		self:ReadBehavior()
		self:ApplyPlaceSettings()
		self:ApplyInsets()
	end
	if reasons.colors then
		-- The role setting lives in the profile
		local changed, tanksChanged, keys = self:ReadContext()
		if changed then
			P:Fire('CONTEXT_CHANGED', keys)
		end
		if tanksChanged then
			P:Fire('TANKS_CHANGED')
		end
	end
	self:RefreshAll(reasons)
	if reasons.size or reasons.look or reasons.assignment then
		self:ApplyPlateSize(false)
	end
end

local function OnBlizzardOptions()
	local self = Driver
	if not self:OwnsSettings() then
		return
	end
	-- Blizzard just set its own base size: keep it for giving back, then put ours back. In combat
	-- the size waits for combat to end (one coalesced write however many times this fires), and the
	-- size Blizzard has then is the one remembered.
	self.blizzDirty = true
	self:ApplyPlateSize(true)
	-- Blizzard also set its own click area on every plate (ApplyFrameOptions ->
	-- UpdateHitTestArea): hand it back to our click frames
	self:RebindClicks()
end
Driver.OnBlizzardOptions = OnBlizzardOptions

---UI scale changed: Mists base plates need the new scale (Quirk 'uiParentScale').
function Driver:ScaleChanged()
	if not P.Caps:Quirk('uiParentScale') then
		return
	end
	local scale = CoordScale()
	for _, plate in pairs(self.byBase) do
		plate.root:SetScale(scale)
		regionKey[plate] = nil
	end
	for plate in pairs(self.bound) do
		self:LayoutRegions(plate)
	end
	self:ApplyPlateSize(true)
end

----------------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------------

local EVENTS = {}

function EVENTS.NAME_PLATE_CREATED(_, base)
	if Driver.standing then
		Driver:OnCreated(base)
	end
end
function EVENTS.NAME_PLATE_UNIT_ADDED(_, unit)
	Driver:OnAdded(unit)
end
function EVENTS.NAME_PLATE_UNIT_REMOVED(_, unit)
	Driver:OnRemoved(unit)
end
function EVENTS.PLAYER_TARGET_CHANGED()
	Driver:UpdateState('target')
end
function EVENTS.PLAYER_FOCUS_CHANGED()
	Driver:UpdateState('focus')
end
function EVENTS.UPDATE_MOUSEOVER_UNIT()
	Driver:UpdateState('mouseover')
end
function EVENTS.RAID_TARGET_UPDATE()
	Driver:Relay('RAID_TARGET_UPDATE')
end
local function QueueContextEvent()
	Driver:QueueContext()
end
EVENTS.GROUP_ROSTER_UPDATE = QueueContextEvent
EVENTS.PLAYER_ROLES_ASSIGNED = QueueContextEvent
EVENTS.PLAYER_SPECIALIZATION_CHANGED = QueueContextEvent
EVENTS.ACTIVE_TALENT_GROUP_CHANGED = QueueContextEvent
EVENTS.PLAYER_LEVEL_UP = QueueContextEvent
EVENTS.PLAYER_UPDATE_RESTING = QueueContextEvent
function EVENTS.UNIT_PET(_, unit)
	-- Fires for every group member's pet; only the player's pet changes the context (pet tank)
	-- or the interrupt (pet spells)
	if Secret.Plain(unit) ~= 'player' then
		return
	end
	Driver:QueueContext()
	P.Scheduler:NextFrame('Driver.kick', KickNow)
end
local function RangeNow()
	Driver:UpdateRangeChecker()
end
function EVENTS.SPELLS_CHANGED()
	P.Scheduler:NextFrame('Driver.kick', KickNow)
	if Driver.rangeHow == 'library' then
		P.Scheduler:NextFrame('Driver.range', RangeNow)
	end
end
local function PlaceEvent()
	Driver:ContextEvent()
	P.Scheduler:NextFrame('Driver.kick', KickNow)
end
EVENTS.PLAYER_ENTERING_WORLD = PlaceEvent
EVENTS.ZONE_CHANGED_NEW_AREA = PlaceEvent
EVENTS.CHALLENGE_MODE_START = PlaceEvent
EVENTS.CHALLENGE_MODE_COMPLETED = PlaceEvent
EVENTS.CHALLENGE_MODE_RESET = PlaceEvent
function EVENTS.PLAYER_REGEN_DISABLED()
	-- Combat lockdown starts after this event: settings written here still go through
	Driver:ContextEvent(true)
	P.Scheduler:NextFrame('Driver.restriction', RestrictionNextFrame)
end
function EVENTS.PLAYER_REGEN_ENABLED()
	Driver:ContextEvent(false)
	Driver:CheckRestriction(false)
	Driver:FlushPendingConfigure()
end
function EVENTS.SPELL_UPDATE_COOLDOWN()
	if Driver.standing then
		Driver:CheckKick(false)
	end
end
function EVENTS.ADDON_RESTRICTION_STATE_CHANGED()
	Driver:CheckRestriction(true)
end
function EVENTS.QUEST_LOG_UPDATE()
	if Driver.standing and not P.Scheduler:IsRunning('Driver.quests') then
		P.Scheduler:Every('Driver.quests', Driver.QUEST_DELAY, QuestsNow)
	end
end
function EVENTS.ARENA_OPPONENT_UPDATE()
	if Driver.standing then
		Driver:UpdateArena()
	end
end
function EVENTS.UI_SCALE_CHANGED()
	Driver:ScaleChanged()
end
function EVENTS.CVAR_UPDATE(_, name)
	-- Fires for every setting; only the one that moves hostile plates under units matters here
	if Driver.standing and type(name) == 'string' and name:lower() == 'nameplateotheratbase' then
		Driver:AtBaseChanged()
	end
end

function Driver:Enable()
	self.active = true
	self.standing = false
	local ctx = P.Context
	ctx.inCombat = InCombat()
	self:ReadContext()
	self.guarded = false
	self:UpdateGuard()
	self.restricted = Secret.IsRestricted()
	for event, fn in pairs(EVENTS) do
		P:RegisterEvent(event, 'Driver', fn)
	end
	local Kicks = P.Data and P.Data.Kicks
	for _, event in ipairs(Kicks and Kicks.EVENTS or EMPTY) do
		if not EVENTS[event] then
			P:RegisterEvent(event, 'Driver', function()
				P.Scheduler:NextFrame('Driver.kick', KickNow)
			end)
		end
	end
	if not self.hooked and hooksecurefunc and NamePlateDriverFrame and NamePlateDriverFrame.UpdateNamePlateOptions then
		self.hooked = true
		hooksecurefunc(NamePlateDriverFrame, 'UpdateNamePlateOptions', OnBlizzardOptions)
	end
	if self:ProfileWantsPlates() then
		self:StandUp()
	else
		P.log.info('Nameplates are off for this profile; the game draws its own')
	end
end

function Driver:Disable()
	self:StandDown()
	self.active = false
	P:UnregisterAllEvents('Driver')
	P:UnregisterAllEvents('Driver.mouse')
end

P:On('STORE_CHANGED', function(reasons)
	if reasons and (reasons.cvars or reasons.assignment) then
		Driver:ClearHandBack()
	end
	if Driver.active and reasons then
		Driver:SettingsChanged(reasons)
	end
end, Driver)
P:On('CONTEXT_CHANGED', function(keys)
	if Driver.active then
		Driver:ContextChanged('CONTEXT_CHANGED', keys)
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
P:On('CVAR_CHANGED', function(name, _, by)
	-- Someone else changed a setting we placed: leave it alone this session
	if Driver.active and by == 'other' and Driver.placeApplied[name] and not Driver.yielded[name] then
		Driver.yielded[name] = true
		P.log.info('Left ' .. tostring(name) .. ' alone: it was changed outside the nameplate settings')
	end
	-- Blizzard's plates set their own click area again when this one changes (UpdateShowOnlyName):
	-- take it back once its callbacks have run
	if Driver.active and name == 'nameplateShowOnlyNameForFriendlyPlayerUnits' then
		P.Scheduler:NextFrame('Driver.rebind', RebindSoon)
	end
end, Driver)

local Caps = P.Caps
Caps:AddProbe('hitTest', function()
	return C_NamePlate ~= nil and C_NamePlate.GetNamePlateForUnit ~= nil
end, 'Click areas follow the drawn plate (the first real plate records the answer, S1)')
Caps:AddProbe('unitCombat', function()
	return true
end, 'Whether enemies are fighting can be read (a hidden answer on a real plate records false, S16)')
Caps:AddProbe('rangeReadable', function()
	return true
end, 'Range to enemies can be read (a hidden answer on a real plate records false, S9)')
Caps:AddProbe('rangeLibrary', function()
	return LibStub ~= nil and LibStub('LibRangeCheck-3.0', true) ~= nil
end, 'LibRangeCheck-3.0 is loaded for range fade')
Caps:AddProbe('spellRange', function()
	return C_Spell ~= nil and C_Spell.IsSpellInRange ~= nil
end, 'C_Spell.IsSpellInRange for range fade without the library')
