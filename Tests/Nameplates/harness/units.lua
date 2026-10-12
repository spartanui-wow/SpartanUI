-- The mock world: units, nameplates, auras, casts, threat, restriction and the C_ APIs around them.
-- Loaded by wowmock.lua as a chunk: loadfile(...)(M, FN, NS, W, WT, S, state).
-- Lines that define a global function start with "FN.Name =" so api_matrix.py can find them.

local M, FN, NS, W, WT, S, state = ...
local rawtype = S.rawtype
local rawtostring = S.rawtostring

----------------------------------------------------------------------------------------------------
-- Restriction ("restricted mode"): which unit functions hand back secrets
----------------------------------------------------------------------------------------------------

-- Documentation marker -> restriction category. "secret" wraps every return value, "nothing"
-- returns no values, "error" raises (the documented failure mode of each predicate).
local MARKERS = {
	SecretReturns = { 'values', 'secret' },
	SecretWhenCurveSecret = { 'values', 'secret' },
	SecretWhenUnitIdentityRestricted = { 'identity', 'secret' },
	SecretWhenUnitNameIdentityRestricted = { 'identity', 'secret' },
	RequiresUnitIdentityAccess = { 'identity', 'nothing' },
	RequiresDeclassifiedUnitIdentity = { 'identity', 'nothing' },
	SecretWhenUnitComparisonRestricted = { 'comparison', 'secret' },
	RequiresComparableUnitTokens = { 'comparison', 'nothing' },
	SecretWhenUnitSpellCastRestricted = { 'casting', 'secret' },
	SecretWhenUnitAuraRestricted = { 'auras', 'secret' },
	SecretWhenAurasRestricted = { 'auras', 'secret' },
	RequiresNonSecretAura = { 'auras', 'nothing' },
	RequiresUnitAuraAccess = { 'auras', 'error' },
	SecretWhenUnitThreatStateRestricted = { 'threat', 'secret' },
	SecretWhenUnitThreatValuesRestricted = { 'threat', 'secret' },
	SecretWhenUnitStatsRestricted = { 'stats', 'secret' },
	SecretWhenUnitPowerRestricted = { 'stats', 'secret' },
	SecretWhenUnitPowerMaxRestricted = { 'stats', 'secret' },
	SecretWhenUnitHealthMaxRestricted = { 'stats', 'secret' },
	SecretWhenUnitPossessionRestricted = { 'possession', 'secret' },
	SecretWhenInCombat = { 'combat', 'secret' },
	SecretInActivePvPMatch = { 'pvp', 'secret' },
}
M.RESTRICTION_CATEGORIES = { 'values', 'identity', 'comparison', 'casting', 'auras', 'threat', 'stats', 'possession', 'combat' }

M.restrict = { on = false, categories = {} }

---Categories the markers of one function belong to, or nil when it is never secret.
function M.SecretCategories(flags)
	if flags.ReturnsNeverSecret then
		return nil
	end
	local out
	for flag in pairs(flags) do
		local marker = MARKERS[flag]
		if marker then
			out = out or {}
			out[#out + 1] = marker
		end
	end
	return out
end

---Switch restricted mode on or off. Only clients with secrets restrict, unless force is true.
---@param on boolean
---@param categories? string[] default: every category except pvp
---@param force? boolean allow it on a Classic-family flavor
---@return boolean applied
function M.SetRestricted(on, categories, force)
	if on and not M.secrets and not force then
		return false
	end
	M.restrict.on = on and true or false
	M.restrict.forced = (on and not M.secrets) and true or false
	M.restrict.categories = {}
	if on then
		for _, cat in ipairs(categories or M.RESTRICTION_CATEGORIES) do
			M.restrict.categories[cat] = true
		end
	end
	M.FireIfKnown('ADDON_RESTRICTION_STATE_CHANGED')
	return true
end

---True when a unit token's values are hidden right now: restricted mode is on and the unit is
---not the player (a unit spawned with restricted = false stays readable).
function M.IsRestrictedUnit(token)
	if not M.restrict.on then
		return false
	end
	local unit = M.UnitFor(token)
	if not unit then
		return false
	end
	return not unit.isSelf and unit.restricted ~= false
end

function M.SecretMode(categories, flags, token)
	if not M.restrict.on or not M.IsRestrictedUnit(token) then
		return nil
	end
	local secret = false
	for _, marker in ipairs(categories) do
		if M.restrict.categories[marker[1]] then
			if marker[2] == 'error' then
				error('unit data is restricted for addons right now', 4)
			elseif marker[2] == 'nothing' then
				return 'nothing'
			end
			secret = true
		end
	end
	return secret and 'secret' or nil
end

----------------------------------------------------------------------------------------------------
-- Units and tokens
----------------------------------------------------------------------------------------------------

M.units = {} -- guid -> unit
M.tokens = {} -- token -> guid
local unitCount = 0

local UNIT_DEFAULTS = {
	name = 'Test Mob',
	level = 60,
	health = 1000,
	healthMax = 1000,
	power = 0,
	powerMax = 0,
	powerType = 0,
	powerToken = 'MANA',
	reaction = 2,
	canAttack = true,
	canAssist = false,
	isPlayer = false,
	classification = 'normal',
	creatureType = 'Humanoid',
	class = 'WARRIOR',
	className = 'Warrior',
	classID = 1,
	race = 'Human',
	raceFile = 'Human',
	faction = 'Horde',
	sex = 2,
	npcID = 1000,
}

---Add a unit to the world. spec fields override UNIT_DEFAULTS (see README for the list).
function M.AddUnit(spec)
	unitCount = unitCount + 1
	local unit = {}
	for k, v in pairs(UNIT_DEFAULTS) do
		unit[k] = v
	end
	for k, v in pairs(spec or {}) do
		unit[k] = v
	end
	if not unit.guid then
		if unit.isPlayer then
			unit.guid = ('Player-1-%08X'):format(unitCount)
		else
			unit.guid = ('Creature-0-1-1-1-%d-%010X'):format(unit.npcID, unitCount)
		end
	end
	unit.auras = unit.auras or {}
	unit.threat = unit.threat or {}
	M.units[unit.guid] = unit
	return unit
end

---Point a token ('target', 'focus', 'nameplate3', ...) at a unit, or clear it with nil.
function M.SetToken(token, unit)
	M.tokens[token] = unit and unit.guid or nil
end

---The unit behind a token (tokens that are secret are read through).
function M.UnitFor(token)
	token = S.Reveal(token)
	if rawtype(token) ~= 'string' then
		return nil
	end
	local guid = M.tokens[token]
	if not guid and token:match('target$') and #token > 6 then
		local base = M.UnitFor(token:sub(1, -7))
		return base and base.target and M.units[base.target]
	end
	return guid and M.units[guid]
end

M.player = M.AddUnit({
	name = 'Tester',
	isPlayer = true,
	isSelf = true,
	reaction = 5,
	canAttack = false,
	canAssist = true,
	class = 'MAGE',
	className = 'Mage',
	classID = 8,
	faction = 'Alliance',
	health = 5000,
	healthMax = 5000,
	powerToken = 'MANA',
	power = 10000,
	powerMax = 10000,
	restricted = false,
})
M.SetToken('player', M.player)

---Change fields on a unit and fire the matching unit events for every token that shows it.
function M.UpdateUnit(unit, fields, events)
	for k, v in pairs(fields or {}) do
		unit[k] = v
	end
	for _, event in ipairs(events or {}) do
		for token, guid in pairs(M.tokens) do
			if guid == unit.guid then
				M.FireIfKnown(event, token)
			end
		end
	end
end

local function U(token)
	return M.UnitFor(token)
end

local function other(a, b)
	local ua, ub = U(a), U(b)
	if not ua or not ub then
		return nil
	end
	if ua.isSelf then
		return ub
	end
	if ub.isSelf then
		return ua
	end
	return ub
end

FN.UnitExists = function(t)
	return U(t) ~= nil
end
FN.UnitGUID = function(t)
	local u = U(t)
	return u and u.guid
end
FN.UnitName = function(t)
	local u = U(t)
	if u then
		return u.name, u.realm
	end
end
FN.UnitNameUnmodified = FN.UnitName
FN.UnitFullName = FN.UnitName
FN.UnitClass = function(t)
	local u = U(t)
	if u then
		return u.className, u.class, u.classID
	end
end
FN.UnitClassBase = function(t)
	local u = U(t)
	if u then
		return u.class, u.classID
	end
end
FN.UnitRace = function(t)
	local u = U(t)
	if u then
		return u.race, u.raceFile
	end
end
FN.UnitSex = function(t)
	local u = U(t)
	return u and u.sex
end
FN.UnitFactionGroup = function(t)
	local u = U(t)
	if u then
		return u.faction, u.faction
	end
end
FN.UnitLevel = function(t)
	local u = U(t)
	return u and u.level
end
FN.UnitEffectiveLevel = function(t)
	local u = U(t)
	return u and (u.effectiveLevel or u.level)
end
FN.UnitHealth = function(t)
	local u = U(t)
	return u and u.health
end
FN.UnitHealthMax = function(t)
	local u = U(t)
	return u and u.healthMax
end
FN.UnitHealthMissing = function(t)
	local u = U(t)
	return u and (u.healthMax - u.health)
end
-- Fraction 0 to 1 without a curve (the documented range is not stated; UNVERIFIED)
FN.UnitHealthPercent = function(t, usePredicted, curve)
	local u = U(t)
	if not u then
		return nil
	end
	local pct = u.healthMax > 0 and u.health / u.healthMax or 0
	if curve then
		return curve:Evaluate(pct)
	end
	return pct
end
FN.UnitPower = function(t)
	local u = U(t)
	return u and u.power
end
FN.UnitPowerMax = function(t)
	local u = U(t)
	return u and u.powerMax
end
FN.UnitPowerType = function(t)
	local u = U(t)
	if u then
		return u.powerType, u.powerToken
	end
end
FN.UnitHasPowerType = function(t, powerType)
	local u = U(t)
	return u ~= nil and u.powerType == powerType
end
FN.UnitReaction = function(a, b)
	local u = other(a, b)
	return u and u.reaction
end
FN.UnitCanAttack = function(a, b)
	local u = other(a, b)
	return u ~= nil and u.canAttack and true or false
end
FN.UnitCanAssist = function(a, b)
	local u = other(a, b)
	return u ~= nil and u.canAssist and true or false
end
FN.UnitIsEnemy = function(a, b)
	local u = other(a, b)
	return u ~= nil and (u.reaction or 4) <= 3
end
FN.UnitIsFriend = function(a, b)
	local u = other(a, b)
	return u ~= nil and (u.reaction or 4) >= 5
end
FN.UnitIsPlayer = function(t)
	local u = U(t)
	return u ~= nil and u.isPlayer and true or false
end
FN.UnitPlayerControlled = function(t)
	local u = U(t)
	return u ~= nil and (u.playerControlled or u.isPlayer) and true or false
end
FN.UnitIsOtherPlayersPet = function(t)
	local u = U(t)
	return u ~= nil and u.otherPlayersPet and true or false
end
FN.UnitIsMinion = function(t)
	local u = U(t)
	return u ~= nil and u.isMinion and true or false
end
FN.UnitClassification = function(t)
	local u = U(t)
	return u and u.classification
end
FN.UnitIsLieutenant = function(t)
	local u = U(t)
	return u ~= nil and u.isLieutenant and true or false
end
FN.UnitIsBossMob = function(t)
	local u = U(t)
	return u ~= nil and u.isBoss and true or false
end
FN.UnitIsTapDenied = function(t)
	local u = U(t)
	return u ~= nil and u.tapDenied and true or false
end
FN.UnitIsQuestBoss = function(t)
	local u = U(t)
	return u ~= nil and u.questBoss and true or false
end
FN.UnitIsDead = function(t)
	local u = U(t)
	return u ~= nil and u.health <= 0
end
FN.UnitIsDeadOrGhost = FN.UnitIsDead
FN.UnitIsConnected = function(t)
	return U(t) ~= nil
end
FN.UnitIsVisible = FN.UnitIsConnected
FN.UnitInRange = function(t)
	local u = U(t)
	if u then
		return u.inRange ~= false, true
	end
end
FN.UnitIsPVP = function(t)
	local u = U(t)
	return u ~= nil and u.pvp and true or false
end
FN.UnitIsUnit = function(a, b)
	local ua, ub = U(a), U(b)
	return ua ~= nil and ua == ub
end
FN.UnitAffectingCombat = function(t)
	local u = U(t)
	if u and u.isSelf then
		return M.inCombat and true or false
	end
	return u ~= nil and u.inCombat and true or false
end
FN.UnitThreatSituation = function(t, mob)
	local u, m = U(t), U(mob)
	if not u then
		return nil
	end
	if m then
		local entry = m.threat[u.guid]
		return entry and entry.status
	end
	return u.threatStatus
end
FN.UnitDetailedThreatSituation = function(t, mob)
	local u, m = U(t), U(mob)
	if not (u and m) then
		return nil
	end
	local entry = m.threat[u.guid]
	if entry then
		return entry.status == 3 or entry.status == 2, entry.status, entry.scaledPercent or 0, entry.rawPercent or 0, entry.value or 0
	end
end
FN.UnitCastingInfo = function(t)
	local u = U(t)
	local c = u and u.cast
	if c and not c.channel then
		return c.name, c.text or c.name, c.texture or 136243, c.startMS, c.endMS, false, c.castID, c.notInterruptible or false, c.spellID, c.castBarID
	end
end
FN.UnitChannelInfo = function(t)
	local u = U(t)
	local c = u and u.cast
	if c and c.channel then
		return c.name, c.text or c.name, c.texture or 136243, c.startMS, c.endMS, false, c.notInterruptible or false, c.spellID, c.empowered or false, c.numStages or 0
	end
end
local function castDuration(t, channel)
	local u = U(t)
	local c = u and u.cast
	if c and (c.channel or false) == channel then
		local d = C_DurationUtil.CreateDuration()
		d:SetTimeFromStart(c.startMS / 1000, (c.endMS - c.startMS) / 1000)
		return d
	end
end
FN.UnitCastingDuration = function(t)
	return castDuration(t, false)
end
FN.UnitChannelDuration = function(t)
	return castDuration(t, true)
end
FN.UnitGetTotalAbsorbs = function(t)
	local u = U(t)
	return u and (u.absorbs or 0)
end
FN.UnitGetTotalHealAbsorbs = function(t)
	local u = U(t)
	return u and (u.healAbsorbs or 0)
end
FN.UnitGetIncomingHeals = function(t)
	local u = U(t)
	return u and (u.incomingHeals or 0)
end
FN.UnitCreatureType = function(t)
	local u = U(t)
	return u and u.creatureType
end
FN.UnitCreatureFamily = function(t)
	local u = U(t)
	return u and u.creatureFamily
end
FN.UnitCreatureID = function(t)
	local u = U(t)
	return u and u.npcID
end
FN.UnitIsGameObject = function(t)
	local u = U(t)
	return u ~= nil and u.isGameObject and true or false
end
FN.UnitNameplateShowsWidgetsOnly = function(t)
	local u = U(t)
	return u ~= nil and u.widgetsOnly and true or false
end
FN.UnitSelectionColor = function(t)
	local u = U(t)
	if not u then
		return nil
	end
	local r = u.reaction or 4
	if r <= 2 then
		return 1, 0, 0, 1
	elseif r == 3 or r == 4 then
		return 1, 1, 0, 1
	end
	return 0, 1, 0, 1
end
FN.UnitGroupRolesAssigned = function(t)
	local u = U(t)
	return u and u.role or 'NONE'
end
FN.UnitInParty = function(t)
	local u = U(t)
	return u ~= nil and u.inParty and true or false
end
FN.UnitInRaid = function(t)
	local u = U(t)
	return u and u.raidIndex
end
FN.UnitTokenFromGUID = function(guid)
	for token, g in pairs(M.tokens) do
		if g == guid and token:match('^nameplate') then
			return token
		end
	end
	for token, g in pairs(M.tokens) do
		if g == guid then
			return token
		end
	end
end
FN.GetRaidTargetIndex = function(t)
	local u = U(t)
	return u and u.raidMarker
end
FN.CheckInteractDistance = function(t)
	return U(t) ~= nil
end

----------------------------------------------------------------------------------------------------
-- Place, group and role
----------------------------------------------------------------------------------------------------

M.place = { inInstance = false, instanceType = 'none', name = 'Elwynn Forest', difficultyID = 0, mapID = 0 }
M.resting = false

---Move the player: { inInstance, instanceType, name, difficultyID, mapID }. Fires the zone events.
function M.SetPlace(place)
	for k, v in pairs(place) do
		M.place[k] = v
	end
	M.FireIfKnown('PLAYER_ENTERING_WORLD', false, false)
	M.FireIfKnown('ZONE_CHANGED_NEW_AREA')
end

FN.GetRealmName = function()
	return 'Test Realm'
end
FN.GetNormalizedRealmName = function()
	return 'TestRealm'
end
FN.GetCurrentRegionName = function()
	return 'US'
end
FN.RegionalUniqueNamesEnabled = function()
	return M.flavor == 'forever'
end
FN.GetSpecialization = function()
	return M.spec or 1
end
FN.GetSpecializationRole = function()
	return M.role or 'DAMAGER'
end
FN.IsInInstance = function()
	return M.place.inInstance, M.place.instanceType
end
FN.GetInstanceInfo = function()
	local p = M.place
	return p.name, p.instanceType, p.difficultyID, '', 5, 0, false, p.mapID, 5, 0
end
FN.IsResting = function()
	return M.resting
end
FN.IsInGroup = function()
	return M.group ~= nil
end
FN.IsInRaid = function()
	return M.group == 'raid'
end
FN.GetNumGroupMembers = function()
	return M.groupSize or 0
end

----------------------------------------------------------------------------------------------------
-- Nameplates
----------------------------------------------------------------------------------------------------

M.plates = {} -- token -> base plate
local freeBases = {}
M.allBases = {}

local function newBasePlate()
	local base = M.NewObject('NamePlate', nil, WorldFrame)
	state[base].w, state[base].h = 110, 45
	local uf = M.NewObject('Button', nil, base)
	state[uf].w, state[uf].h = 110, 45
	-- Blizzard's own unit frame on the plate, with the children addons commonly touch
	base.UnitFrame = uf
	uf.healthBar = M.NewObject('StatusBar', nil, uf)
	uf.castBar = M.NewObject('StatusBar', nil, uf)
	uf.name = M.NewObject('FontString', nil, uf)
	uf.HealthBarsContainer = M.NewObject('Frame', nil, uf)
	uf.WidgetContainer = M.NewObject('Frame', nil, uf)
	uf.SoftTargetFrame = M.NewObject('Frame', nil, uf)
	M.allBases[#M.allBases + 1] = base
	return base
end

local function freeToken()
	for i = 1, 400 do
		local token = 'nameplate' .. i
		if not M.plates[token] then
			return token
		end
	end
	error('no free nameplate token')
end

---Show a nameplate for a unit (a unit object or a spec for M.AddUnit).
---Fires NAME_PLATE_CREATED for a new base plate, then NAME_PLATE_UNIT_ADDED (or the FORBIDDEN_
---events for spec.forbidden). Hit-test points can change only while the add event runs.
---@return string token, table base, table unit
function M.ShowPlate(unitOrSpec)
	local unit = unitOrSpec
	if not (unit and unit.guid and M.units[unit.guid] == unit) then
		unit = M.AddUnit(unitOrSpec)
	end
	local token = freeToken()
	local base = table.remove(freeBases)
	local created = false
	if not base then
		base = newBasePlate()
		created = true
	end
	state[base].forbidden = unit.forbidden or false
	state[base].token = token
	M.plates[token] = base
	M.SetToken(token, unit)
	W.Show(base)
	local prefix = unit.forbidden and 'FORBIDDEN_' or ''
	if created then
		M.FireIfKnown(prefix .. 'NAME_PLATE_CREATED', base)
	end
	state[base].canHitTest = true
	M.FireIfKnown(prefix .. 'NAME_PLATE_UNIT_ADDED', token)
	state[base].canHitTest = false
	return token, base, unit
end

---Remove a nameplate: NAME_PLATE_UNIT_REMOVED fires while the token still works, then it is freed.
function M.HidePlate(token)
	local base = M.plates[token]
	if not base then
		error('no plate for ' .. rawtostring(token), 2)
	end
	local prefix = state[base].forbidden and 'FORBIDDEN_' or ''
	M.FireIfKnown(prefix .. 'NAME_PLATE_UNIT_REMOVED', token)
	M.plates[token] = nil
	M.SetToken(token, nil)
	state[base].token = nil
	W.Hide(base)
	freeBases[#freeBases + 1] = base
end

---Base plates the client created so far (shown or pooled).
function M.Bases()
	return M.allBases
end

local function setAlias(token, event, unitOrToken)
	local unit = unitOrToken
	if rawtype(unitOrToken) == 'string' then
		unit = M.UnitFor(unitOrToken)
	end
	M.SetToken(token, unit)
	M.FireIfKnown(event)
end
function M.SetTarget(unitOrToken)
	setAlias('target', 'PLAYER_TARGET_CHANGED', unitOrToken)
end
function M.SetFocus(unitOrToken)
	setAlias('focus', 'PLAYER_FOCUS_CHANGED', unitOrToken)
end
function M.SetMouseover(unitOrToken)
	setAlias('mouseover', 'UPDATE_MOUSEOVER_UNIT', unitOrToken)
end

M.plateSize = { 110, 45 }
NS.C_NamePlate = {
	GetNamePlateForUnit = function(token, includeForbidden)
		local plain = S.Reveal(token)
		if rawtype(plain) ~= 'string' then
			return nil
		end
		local base = M.plates[plain]
		if not base then
			if M.restrict.on and M.restrict.categories.identity and M.IsRestrictedUnit(plain) then
				error('GetNamePlateForUnit: this unit is restricted for addons', 2)
			end
			local unit = M.UnitFor(plain)
			for t, b in pairs(M.plates) do
				if unit and M.tokens[t] == unit.guid then
					base = b
					break
				end
			end
		end
		if base and state[base].forbidden then
			return nil
		end
		return base
	end,
	GetNamePlates = function()
		local out = {}
		for i = 1, 400 do
			local base = M.plates['nameplate' .. i]
			if base and not state[base].forbidden then
				out[#out + 1] = base
			end
		end
		return out
	end,
	SetNamePlateSize = function(w, h)
		M.plateSize = { w, h }
		M.Log(M, 'SetNamePlateSize', w, h)
	end,
	GetNamePlateSize = function()
		return M.plateSize[1], M.plateSize[2]
	end,
}

W.CanChangeHitTestPoints = function(self)
	return state[self].canHitTest or false
end
W.SetAllHitTestPoints = function(self, relativeTo)
	state[self].hitTest = { { 'ALL', relativeTo } }
	M.Log(self, 'SetAllHitTestPoints', relativeTo)
end
W.ClearAllHitTestPoints = function(self)
	state[self].hitTest = {}
	M.Log(self, 'ClearAllHitTestPoints')
end
W.GetHitTestPoints = function(self)
	return state[self].hitTest or {}
end
W.SetHitTestPoints = function(self, anchors)
	state[self].hitTest = anchors
end
W.SetStackingBoundsFrame = function(self, frame)
	state[self].stackingBounds = frame
	M.Log(self, 'SetStackingBoundsFrame', frame)
end

----------------------------------------------------------------------------------------------------
-- Casts and threat
----------------------------------------------------------------------------------------------------

local castCount = 0

---Start a cast on a unit: { name, spellID, duration (s), channel, notInterruptible }.
function M.StartCast(unit, cast)
	castCount = castCount + 1
	local now = M.now * 1000
	cast.startMS = now
	cast.endMS = now + (cast.duration or 1.5) * 1000
	cast.castID = cast.castID or ('Cast-' .. castCount)
	cast.name = cast.name or 'Test Spell'
	cast.spellID = cast.spellID or 100
	unit.cast = cast
	M.UpdateUnit(unit, nil, { cast.channel and 'UNIT_SPELLCAST_CHANNEL_START' or 'UNIT_SPELLCAST_START' })
end

---End the current cast: how = 'stop' | 'interrupted' | 'succeeded' | 'failed'.
function M.StopCast(unit, how)
	local cast = unit.cast
	unit.cast = nil
	if not cast then
		return
	end
	local event
	if cast.channel then
		event = 'UNIT_SPELLCAST_CHANNEL_STOP'
	elseif how == 'interrupted' then
		event = 'UNIT_SPELLCAST_INTERRUPTED'
	elseif how == 'failed' then
		event = 'UNIT_SPELLCAST_FAILED'
	elseif how == 'succeeded' then
		event = 'UNIT_SPELLCAST_SUCCEEDED'
	else
		event = 'UNIT_SPELLCAST_STOP'
	end
	M.UpdateUnit(unit, nil, { event })
end

---Set who the mob is attacking: threat[guid] = { status, scaledPercent, rawPercent, value }.
function M.SetThreat(mob, holder, entry)
	mob.threat[holder.guid] = entry
	M.UpdateUnit(mob, nil, { 'UNIT_THREAT_LIST_UPDATE', 'UNIT_THREAT_SITUATION_UPDATE' })
end

----------------------------------------------------------------------------------------------------
-- Auras
----------------------------------------------------------------------------------------------------

local auraCount = 0

local function filterTokens(filter)
	local t = {}
	for token in rawtostring(filter or 'HELPFUL'):gmatch('[^|%s]+') do
		t[token] = true
	end
	return t
end

local function auraMatches(aura, filter)
	local tokens = filterTokens(filter)
	if tokens.HARMFUL and not aura.isHarmful then
		return false
	end
	if (tokens.HELPFUL or not tokens.HARMFUL) and aura.isHarmful then
		return false
	end
	if tokens.PLAYER and aura.sourceUnit ~= 'player' then
		return false
	end
	if tokens['!PLAYER'] and aura.sourceUnit == 'player' then
		return false
	end
	for token in pairs(tokens) do
		if token ~= 'HELPFUL' and token ~= 'HARMFUL' and token ~= 'PLAYER' and token ~= '!PLAYER' then
			local negated = token:match('^!(.+)$')
			if negated then
				if aura.tags and aura.tags[negated] then
					return false
				end
			elseif not (aura.tags and aura.tags[token]) then
				return false
			end
		end
	end
	return true
end
M.AuraMatches = auraMatches

---Put an aura on a unit and fire UNIT_AURA with an update info table.
---aura: { spellId, name, icon, duration, isHarmful, sourceUnit, applications, dispelName, tags = { RAID = true } }
function M.ApplyAura(unit, aura)
	auraCount = auraCount + 1
	aura.auraInstanceID = aura.auraInstanceID or auraCount
	aura.isHelpful = not aura.isHarmful
	aura.name = aura.name or ('Aura ' .. (aura.spellId or 0))
	aura.spellId = aura.spellId or 0
	aura.icon = aura.icon or 136243
	aura.applications = aura.applications or 0
	aura.duration = aura.duration or 0
	aura.expirationTime = aura.duration > 0 and (M.now + aura.duration) or 0
	unit.auras[#unit.auras + 1] = aura
	M.UpdateUnit(unit, nil, nil)
	for token, guid in pairs(M.tokens) do
		if guid == unit.guid then
			M.FireIfKnown('UNIT_AURA', token, { isFullUpdate = false, addedAuras = { aura } })
		end
	end
	return aura
end

function M.RemoveAura(unit, auraInstanceID)
	for i = #unit.auras, 1, -1 do
		if unit.auras[i].auraInstanceID == auraInstanceID then
			table.remove(unit.auras, i)
		end
	end
	for token, guid in pairs(M.tokens) do
		if guid == unit.guid then
			M.FireIfKnown('UNIT_AURA', token, { isFullUpdate = false, removedAuraInstanceIDs = { auraInstanceID } })
		end
	end
end

local function auraCopy(aura)
	local out = {}
	for k, v in pairs(aura) do
		if k ~= 'tags' then
			out[k] = v
		end
	end
	return out
end

local function auraList(token, filter)
	local u = U(token)
	local out = {}
	if u then
		for _, aura in ipairs(u.auras) do
			if auraMatches(aura, filter) then
				out[#out + 1] = aura
			end
		end
	end
	return out
end

NS.C_UnitAuras = {
	GetAuraDataByIndex = function(token, index, filter)
		local aura = auraList(token, filter)[index]
		return aura and auraCopy(aura)
	end,
	GetBuffDataByIndex = function(token, index, filter)
		local aura = auraList(token, 'HELPFUL' .. (filter and ('|' .. filter) or ''))[index]
		return aura and auraCopy(aura)
	end,
	GetDebuffDataByIndex = function(token, index, filter)
		local aura = auraList(token, 'HARMFUL' .. (filter and ('|' .. filter) or ''))[index]
		return aura and auraCopy(aura)
	end,
	GetAuraDataByAuraInstanceID = function(token, id)
		local u = U(token)
		for _, aura in ipairs(u and u.auras or {}) do
			if aura.auraInstanceID == id then
				return auraCopy(aura)
			end
		end
	end,
	-- Returns a continuation token (always nil here) followed by slot numbers
	GetAuraSlots = function(token, filter, maxSlots)
		local list = auraList(token, filter)
		local ids = {}
		for i = 1, math.min(#list, maxSlots or #list) do
			ids[i] = list[i].auraInstanceID
		end
		return nil, unpack(ids)
	end,
	GetAuraDataBySlot = function(token, slot)
		return NS.C_UnitAuras.GetAuraDataByAuraInstanceID(token, slot)
	end,
	GetUnitAuraInstanceIDs = function(token, filter, maxCount)
		local out = {}
		for i, aura in ipairs(auraList(token, filter)) do
			if maxCount and i > maxCount then
				break
			end
			out[#out + 1] = aura.auraInstanceID
		end
		return out
	end,
	IsAuraFilteredOutByInstanceID = function(token, id, filter)
		local u = U(token)
		for _, aura in ipairs(u and u.auras or {}) do
			if aura.auraInstanceID == id then
				return not auraMatches(aura, filter)
			end
		end
		return true
	end,
}

----------------------------------------------------------------------------------------------------
-- Secrets predicates
----------------------------------------------------------------------------------------------------

local function catRestricted(cat, token)
	if not (M.restrict.on and M.restrict.categories[cat]) then
		return false
	end
	if token == nil then
		return true
	end
	return M.IsRestrictedUnit(token)
end

NS.C_Secrets = {
	HasSecretRestrictions = function()
		return M.secrets
	end,
	ShouldAurasBeSecret = function()
		return catRestricted('auras')
	end,
	ShouldCooldownsBeSecret = function()
		return catRestricted('combat')
	end,
	ShouldUnitIdentityBeSecret = function(token)
		return catRestricted('identity', token)
	end,
	ShouldUnitComparisonBeSecret = function(a, b)
		return catRestricted('comparison', a) or catRestricted('comparison', b)
	end,
	ShouldUnitHealthMaxBeSecret = function(token)
		return catRestricted('stats', token)
	end,
	ShouldUnitSpellCastingBeSecret = function(token)
		return catRestricted('casting', token)
	end,
	ShouldUnitThreatStateBeSecret = function(token)
		return catRestricted('threat', token)
	end,
	ShouldUnitThreatValuesBeSecret = function(token)
		return catRestricted('threat', token)
	end,
	ShouldUnitAuraIndexBeSecret = function(token)
		return catRestricted('auras', token)
	end,
	ShouldUnitAuraInstanceBeSecret = function(token)
		return catRestricted('auras', token)
	end,
	ShouldUnitAuraSlotBeSecret = function(token)
		return catRestricted('auras', token)
	end,
	CanCompareUnitTokens = function(a, b)
		return not (catRestricted('comparison', a) or catRestricted('comparison', b))
	end,
}

----------------------------------------------------------------------------------------------------
-- Curves, durations, colors and strings (engine sinks that accept secrets)
----------------------------------------------------------------------------------------------------

local function newScriptObject(kind)
	local obj = M.NewObject(kind)
	state[obj].points = {}
	return obj
end

NS.C_CurveUtil = {
	CreateCurve = function()
		return newScriptObject('Curve')
	end,
	CreateColorCurve = function()
		return newScriptObject('ColorCurve')
	end,
	EvaluateColorValueFromBoolean = function(value, ifTrue, ifFalse)
		-- Documented Nilable = false (unverified whether the client errors; strict here)
		if value == nil then
			error('EvaluateColorValueFromBoolean: bad argument #1, boolean expected, got nil', 2)
		end
		local chosen = S.Reveal(value) and ifTrue or ifFalse
		if S.Any(value, ifTrue, ifFalse) then
			return S.Wrap(S.Reveal(chosen))
		end
		return chosen
	end,
	EvaluateColorFromBoolean = function(value, ifTrue, ifFalse)
		if value == nil then
			error('EvaluateColorFromBoolean: bad argument #1, boolean expected, got nil', 2)
		end
		local chosen = S.Reveal(value) and ifTrue or ifFalse
		if not S.IsSecret(value) then
			return chosen
		end
		local r, g, b, a = chosen:GetRGBA()
		return CreateColor(S.Wrap(r), S.Wrap(g), S.Wrap(b), S.Wrap(a))
	end,
}

local function curveEvaluate(self, x)
	local plain = S.Reveal(x)
	local points = state[self].points
	local best
	for _, p in ipairs(points) do
		if p.x <= plain then
			best = p
		end
	end
	best = best or points[1]
	local y = best and best.y
	if S.IsSecret(x) then
		if rawtype(y) == 'table' and y.GetRGBA then
			local r, g, b, a = y:GetRGBA()
			return CreateColor(S.Wrap(r), S.Wrap(g), S.Wrap(b), S.Wrap(a))
		end
		return S.Wrap(y)
	end
	return y
end
local function curveAddPoint(self, x, y)
	local points = state[self].points
	points[#points + 1] = { x = x, y = y }
	table.sort(points, function(a, b)
		return a.x < b.x
	end)
end
WT.Curve = {
	AddPoint = curveAddPoint,
	Evaluate = curveEvaluate,
	ClearPoints = function(self)
		state[self].points = {}
	end,
	GetPointCount = function(self)
		return #state[self].points
	end,
}
WT.ColorCurve = {
	AddPoint = curveAddPoint,
	Evaluate = curveEvaluate,
	EvaluateUnpacked = function(self, x)
		local c = curveEvaluate(self, x)
		return c:GetRGBA()
	end,
	ClearPoints = WT.Curve.ClearPoints,
	GetPointCount = WT.Curve.GetPointCount,
}

local function durationRemaining(self)
	local st = state[self]
	if not st.start then
		return 0
	end
	return math.max(0, S.Reveal(st.start) + S.Reveal(st.total) - M.now)
end
WT.Duration = {
	SetTimeFromStart = function(self, start, total)
		state[self].start, state[self].total = start, total
	end,
	SetTimeFromEnd = function(self, finish, total)
		state[self].start, state[self].total = S.Reveal(finish) - S.Reveal(total), total
		state[self].secret = S.Any(finish, total)
	end,
	SetTimeSpan = function(self, start, finish)
		state[self].start, state[self].total = start, S.Reveal(finish) - S.Reveal(start)
	end,
	Reset = function(self)
		state[self].start, state[self].total = nil, nil
	end,
	GetRemainingDuration = function(self)
		return durationRemaining(self)
	end,
	GetTotalDuration = function(self)
		return S.Reveal(state[self].total) or 0
	end,
	GetStartTime = function(self)
		return S.Reveal(state[self].start) or 0
	end,
	GetEndTime = function(self)
		return (S.Reveal(state[self].start) or 0) + (S.Reveal(state[self].total) or 0)
	end,
	HasExpired = function(self)
		return durationRemaining(self) <= 0
	end,
	IsZero = function(self)
		return (S.Reveal(state[self].total) or 0) == 0
	end,
	HasSecretValues = function(self)
		return state[self].secret or false
	end,
}

NS.C_DurationUtil = {
	CreateDuration = function()
		return newScriptObject('Duration')
	end,
	CreateDurationTextBinding = function()
		return newScriptObject('DurationTextBinding')
	end,
}

NS.C_ClassColor = {
	GetClassColor = function(classFile)
		local plain = S.Reveal(classFile)
		local colors = RAID_CLASS_COLORS
		local base = colors and colors[plain]
		if not base then
			return nil
		end
		if S.IsSecret(classFile) then
			return CreateColor(S.Wrap(base.r), S.Wrap(base.g), S.Wrap(base.b), S.Wrap(1))
		end
		return CreateColor(base.r, base.g, base.b, 1)
	end,
}

NS.C_StringUtil = {
	TruncateWhenZero = function(value)
		local plain = S.Reveal(value)
		local text = (plain == 0 or plain == nil) and '' or rawtostring(plain)
		if S.IsSecret(value) then
			return S.Wrap(text)
		end
		return text
	end,
}

NS.C_ChallengeMode = {
	IsChallengeModeActive = function()
		return M.challengeActive or false
	end,
}

NS.C_Texture = {
	GetAtlasInfo = function(atlas)
		if M.missingAtlases and M.missingAtlases[atlas] then
			return nil
		end
		return { file = 'Interface\\Atlas\\' .. rawtostring(atlas), width = 64, height = 64, leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1 }
	end,
}

NS.C_Spell = {
	GetSpellInfo = function(spell)
		local id = tonumber(spell)
		if not id then
			return nil
		end
		return { name = 'Spell ' .. id, spellID = id, iconID = 136243, castTime = 0, minRange = 0, maxRange = 0, originalIconID = 136243 }
	end,
	GetSpellName = function(id)
		return 'Spell ' .. rawtostring(id)
	end,
	IsSpellImportant = function(id)
		return M.importantSpells and M.importantSpells[S.Reveal(id)] or false
	end,
}

NS.C_AddOnProfiler = {
	IsEnabled = function()
		return false
	end,
}

----------------------------------------------------------------------------------------------------
-- Aura containers (Retail and Forever): the inbound checks Blizzard's container code makes
----------------------------------------------------------------------------------------------------

-- Candidate filter keys Blizzard_CustomAuraContainer.lua reads; unknown keys are kept but recorded
local CANDIDATE_KEYS = {
	includeSpellIDs = 'table',
	excludeSpellIDs = 'table',
	includeDispelTypes = 'table',
	excludeDispelTypes = 'table',
	processedAuraType = 'number',
	maxDuration = 'number',
	isFromPlayerOrPlayerPet = 'boolean',
	isRoleAura = 'boolean',
	isPriorityAura = 'boolean',
	isStealable = 'boolean',
	nameplateShowAll = 'boolean',
	nameplateShowPersonal = 'boolean',
	canApplyAura = 'boolean',
	isBossAura = 'boolean',
	isBossOrRoleAura = 'boolean',
}
M.CANDIDATE_KEYS = CANDIDATE_KEYS

local function containerState(self)
	local st = state[self]
	st.groups = st.groups or {}
	st.slots = st.slots or {}
	st.unknownCandidateKeys = st.unknownCandidateKeys or {}
	return st
end

local function checkCandidates(self, filters)
	if filters == nil then
		return
	end
	if rawtype(filters) ~= 'table' then
		error('candidateFilters must be a table or nil.', 3)
	end
	local st = containerState(self)
	for key, value in pairs(filters) do
		local want = CANDIDATE_KEYS[key]
		if not want then
			st.unknownCandidateKeys[#st.unknownCandidateKeys + 1] = key
		elseif rawtype(value) ~= want then
			error(('%s must be a %s or nil.'):format(key, want), 3)
		end
	end
end

local function requireGroup(self, key)
	local group = containerState(self).groups[key]
	if not group then
		error(("aura group '%s' was not found with this key."):format(rawtostring(key)), 3)
	end
	return group
end

local function checkCount(count)
	if not (count == math.huge or (rawtype(count) == 'number' and count >= 0 and count == math.floor(count))) then
		error('maxFrameCount must be a non-negative integer or infinity.', 3)
	end
end

WT.AuraContainer = {
	AddAuraGroup = function(self, key, filter, options)
		M.Log(self, 'AddAuraGroup', key, filter, options)
		if rawtype(key) ~= 'string' or key == '' then
			error('groupKey must be a non-empty string.', 2)
		end
		if rawtype(filter) ~= 'string' then
			error('filterString must be a string.', 2)
		end
		local st = containerState(self)
		if st.groups[key] then
			error(("aura group '%s' already exists with this key."):format(key), 2)
		end
		options = options or {}
		checkCandidates(self, options.candidateFilters)
		if options.maxFrameCount ~= nil then
			checkCount(options.maxFrameCount)
		end
		st.groups[key] = { filter = filter, options = options, maxFrameCount = options.maxFrameCount, candidateFilters = options.candidateFilters, layout = options.layout }
	end,
	HasAuraGroup = function(self, key)
		return containerState(self).groups[key] ~= nil
	end,
	SetAuraGroupMaxFrameCount = function(self, key, count)
		M.Log(self, 'SetAuraGroupMaxFrameCount', key, count)
		local group = requireGroup(self, key)
		checkCount(count)
		group.maxFrameCount = count
	end,
	SetAuraGroupFilterString = function(self, key, filter)
		M.Log(self, 'SetAuraGroupFilterString', key, filter)
		requireGroup(self, key).filter = filter
	end,
	SetAuraGroupCandidateFilters = function(self, key, filters)
		M.Log(self, 'SetAuraGroupCandidateFilters', key, filters)
		local group = requireGroup(self, key)
		checkCandidates(self, filters)
		group.candidateFilters = filters
	end,
	SetAuraGroupSortMethod = function(self, key, method, direction)
		M.Log(self, 'SetAuraGroupSortMethod', key, method, direction)
		local group = requireGroup(self, key)
		group.sortMethod, group.sortDirection = method, direction
	end,
	SetAuraGroupLayout = function(self, key, layout)
		M.Log(self, 'SetAuraGroupLayout', key, layout)
		requireGroup(self, key).layout = layout
	end,
	AddAuraSlot = function(self, key, filter, options)
		M.Log(self, 'AddAuraSlot', key, filter, options)
		if rawtype(key) ~= 'string' or key == '' then
			error('slotKey must be a non-empty string.', 2)
		end
		local st = containerState(self)
		if st.slots[key] then
			error(("aura slot '%s' already exists with this key."):format(key), 2)
		end
		options = options or {}
		checkCandidates(self, options.candidateFilters)
		st.slots[key] = { filter = filter, options = options }
	end,
	SetUnit = function(self, unit)
		M.Log(self, 'SetUnit', unit)
		state[self].unit = unit
	end,
	GetUnit = function(self)
		return state[self].unit
	end,
	SetEnabled = function(self, enabled)
		M.Log(self, 'SetEnabled', enabled)
		state[self].enabled = enabled and true or false
	end,
	IsEnabled = function(self)
		return state[self].enabled ~= false
	end,
}

NS.C_SpecializationInfo = {
	GetSpecialization = function()
		return M.spec or 1
	end,
	GetSpecializationInfo = function(index)
		return 100 + (index or 1), 'Spec ' .. rawtostring(index or 1), '', 136243, M.role or 'DAMAGER'
	end,
}
