local _, ns = ...
local P = ns.Plates
local Secret = P.Secret

-- Data sources for parts (6.3, 5.6). THE ONLY FILE THAT MAY CALL Unit* FUNCTIONS (the lint checks).
--
-- Two kinds with one method list:
--   LiveSource    bound to a nameplate unit token; values may be secret on Retail and Forever
--   SampleSource  bound to a sample from Data/Samples.lua; always plain; used by previews, cards
--                 and the setup look step, so they run the same parts as real plates
--
-- Method naming is the contract:
--   ...Secret()  may return a secret value. Pass it straight to an approved sink (Secret.SINKS), or
--                keep it in a local named ...Secret used only as a sink argument. Never compare
--                it, test it, do arithmetic, concatenate it or use it as a table key. The only
--                allowed check is type(x) == 'nil'.
--   ...Plain()   returns value, readable. readable == false means the game hid it (value is nil).
--   anything else is always plain (facts, CastKind, CastBarID).
-- Inside this file Unit* results are only returned, passed to canaccessvalue (Secret.Plain) or
-- checked with type(); nothing else is done to them.
--
-- PvP-restricted unit tokens (9.2): some reads may refuse the token in restricted PvP. A source in
-- guarded mode wraps every read in pcall and answers nothing on failure; the Driver turns it on in
-- arenas and battlegrounds on clients with secrets.

---@class Plates.Source
---@field unit string|nil Unit token ('nameplate3'); nil for samples
---@field isSample boolean
---@field sample? Plates.Sample
local Source = {}
P.Source = Source

local Plain = Secret.Plain
local CurveConstants = CurveConstants

local function Direct(fn, ...)
	return fn(...)
end

local function Pass(ok, ...)
	if ok then
		return ...
	end
end

local function Guarded(fn, ...)
	return Pass(pcall(fn, ...))
end

local function Noop() end

---@param fn function|nil
local function Fn(fn)
	return fn or Noop
end

----------------------------------------------------------------------------------------------------
-- LiveSource
----------------------------------------------------------------------------------------------------

---@class Plates.LiveSource : Plates.Source
local Live = {}
Live.__index = Live
Source.Live = Live

---@param unit? string
---@return Plates.LiveSource
function Source.NewLive(unit)
	return setmetatable({ unit = unit, isSample = false, Call = Direct }, Live)
end

---@param unit string|nil
function Live:SetUnit(unit)
	self.unit = unit
end

---Wrap every read in pcall (restricted PvP tokens). Cheap enough to leave on for a whole match.
---@param on boolean
function Live:SetGuarded(on)
	self.Call = on and Guarded or Direct
end

local UnitEffectiveLevel = UnitEffectiveLevel or UnitLevel
local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0

---A fact from a function only some clients have. nil means the client has no such function (or
---the game hid the answer); a readable false stays false (Situation.MobType tells "not a
---lieutenant" apart from "this client cannot say" by it).
---@param call function
---@param fn function|nil
---@param unit string
---@return any
local function Optional(call, fn, unit)
	if not fn then
		return nil
	end
	return (Plain(call(fn, unit)))
end

---Fill plain facts. Every read goes through Secret.Plain, so a hidden fact reads as nil.
---@param facts Plates.Facts
---@return Plates.Facts
function Live:ReadFacts(facts)
	local u, call = self.unit, self.Call
	facts.reaction = Plain(call(Fn(UnitReaction), u, 'player'))
	facts.canAttack = Plain(call(Fn(UnitCanAttack), 'player', u))
	facts.isPlayer = Plain(call(Fn(UnitIsPlayer), u))
	facts.playerControlled = Plain(call(Fn(UnitPlayerControlled), u))
	facts.isMinion = Optional(call, UnitIsMinion, u)
	facts.classification = Plain(call(Fn(UnitClassification), u))
	facts.effectiveLevel = Plain(call(Fn(UnitEffectiveLevel), u))
	facts.isBoss = Optional(call, UnitIsBossMob, u)
	facts.isLieutenant = Optional(call, UnitIsLieutenant, u)
	if UnitHasPowerType then
		facts.isCaster = Plain(call(UnitHasPowerType, u, MANA))
	else
		local powerType = Plain(call(Fn(UnitPowerType), u))
		facts.isCaster = powerType ~= nil and powerType == MANA
	end
	facts.tapDenied = Plain(call(Fn(UnitIsTapDenied), u))
	facts.questBoss = Optional(call, UnitIsQuestBoss, u)
	facts.widgetsOnly = Optional(call, UnitNameplateShowsWidgetsOnly, u)
	facts.isGameObject = Optional(call, UnitIsGameObject, u)
	facts.inCombat = Plain(call(Fn(UnitAffectingCombat), u))
	facts.classToken = nil
	if facts.isPlayer then
		local _, token = call(Fn(UnitClass), u)
		facts.classToken = Plain(token)
	end
	facts.isQuest = facts.questBoss or self:QuestPlain() or nil
	facts.mobType = P.Situation.MobType(facts, P.Context)
	return facts
end

---Re-read facts that have no event (can attack, in combat), for the round-robin poller.
---@param facts Plates.Facts
---@return boolean changed
function Live:PollFacts(facts)
	local u, call = self.unit, self.Call
	local canAttack = Plain(call(Fn(UnitCanAttack), 'player', u))
	local inCombat = Plain(call(Fn(UnitAffectingCombat), u))
	local changed = canAttack ~= facts.canAttack or inCombat ~= facts.inCombat
	facts.canAttack, facts.inCombat = canAttack, inCombat
	return changed
end

function Live:HealthSecret()
	return self.Call(Fn(UnitHealth), self.unit)
end

function Live:HealthMaxSecret()
	return self.Call(Fn(UnitHealthMax), self.unit)
end

---@return number|nil value
---@return boolean readable
function Live:HealthPlain()
	return Plain(self.Call(Fn(UnitHealth), self.unit))
end

---Health percent through a curve (default 0-100). The result may be secret; a ColorCurve gives a
---color. Only for sinks.
---@param curve? table
function Live:HealthPercentSecret(curve)
	if not UnitHealthPercent then
		return nil
	end
	return self.Call(UnitHealthPercent, self.unit, true, curve or (CurveConstants and CurveConstants.ScaleTo100))
end

---Fill a heal prediction calculator (CreateUnitHealPredictionCalculator). Returns false when the
---client has none; then use AbsorbSecret and HealAbsorbSecret.
---@param calculator table
---@return boolean
function Live:FillHealPrediction(calculator)
	if not (calculator and UnitGetDetailedHealPrediction) then
		return false
	end
	self.Call(UnitGetDetailedHealPrediction, self.unit, nil, calculator)
	return true
end

function Live:AbsorbSecret()
	return self.Call(Fn(UnitGetTotalAbsorbs), self.unit)
end

function Live:HealAbsorbSecret()
	return self.Call(Fn(UnitGetTotalHealAbsorbs), self.unit)
end

function Live:NameSecret()
	return self.Call(Fn(UnitName), self.unit)
end

---@return string|nil
---@return boolean readable
function Live:NamePlain()
	return Plain((self.Call(Fn(UnitName), self.unit)))
end

function Live:ClassTokenSecret()
	local _, token = self.Call(Fn(UnitClass), self.unit)
	return token
end

---@return string|nil
---@return boolean readable
function Live:ClassTokenPlain()
	local _, token = self.Call(Fn(UnitClass), self.unit)
	return Plain(token)
end

function Live:RaidMarkerSecret()
	return self.Call(Fn(GetRaidTargetIndex), self.unit)
end

function Live:ThreatStatusSecret()
	return self.Call(Fn(UnitThreatSituation), 'player', self.unit)
end

---@return integer|nil status 0-3, nil when not on the threat list or hidden
---@return boolean readable
function Live:ThreatStatusPlain()
	if Secret.ShouldUnitThreatStateBeSecret('player', self.unit) then
		return nil, false
	end
	return Plain(self.Call(Fn(UnitThreatSituation), 'player', self.unit))
end

---Scaled threat percent (only for text sinks).
function Live:ThreatPercentSecret()
	local _, _, scaled = self.Call(Fn(UnitDetailedThreatSituation), 'player', self.unit)
	return scaled
end

---@return number|nil scaledPercent
---@return boolean readable
function Live:ThreatPercentPlain()
	if Secret.ShouldUnitThreatValuesBeSecret('player', self.unit) then
		return nil, false
	end
	local _, _, scaled = self.Call(Fn(UnitDetailedThreatSituation), 'player', self.unit)
	return Plain(scaled)
end

---Whether another unit (a group tank, 'pet') is tanking this one.
---@param tank string
function Live:IsTankingSecret(tank)
	return (self.Call(Fn(UnitDetailedThreatSituation), tank, self.unit))
end

---@param tank string
---@return boolean|nil
---@return boolean readable
function Live:IsTankingPlain(tank)
	return Plain((self.Call(Fn(UnitDetailedThreatSituation), tank, self.unit)))
end

---'cast' | 'channel' | 'empower' | nil. Plain: decided by presence (type) and NeverSecret flags.
---@return string|nil
function Live:CastKind()
	local name = self.Call(Fn(UnitCastingInfo), self.unit)
	if type(name) ~= 'nil' then
		return 'cast'
	end
	local channelName, _, _, _, _, _, _, _, isEmpowered = self.Call(Fn(UnitChannelInfo), self.unit)
	if type(channelName) ~= 'nil' then
		-- isEmpowered is NeverSecret
		return isEmpowered and 'empower' or 'channel'
	end
	return nil
end

---castBarID is NeverSecret on both info calls.
---@return integer|nil
function Live:CastBarID()
	local kind = self:CastKind()
	if kind == 'cast' then
		return (select(10, self.Call(Fn(UnitCastingInfo), self.unit)))
	elseif kind then
		return (select(11, self.Call(Fn(UnitChannelInfo), self.unit)))
	end
	return nil
end

local function CastField(self, castIndex, channelIndex)
	local kind = self:CastKind()
	if kind == 'cast' then
		return (select(castIndex, self.Call(Fn(UnitCastingInfo), self.unit)))
	elseif kind then
		return (select(channelIndex, self.Call(Fn(UnitChannelInfo), self.unit)))
	end
	return nil
end

function Live:CastNameSecret()
	return CastField(self, 2, 2)
end

function Live:CastIconSecret()
	return CastField(self, 3, 3)
end

function Live:NotInterruptibleSecret()
	return CastField(self, 8, 7)
end

---@return boolean|nil
---@return boolean readable
function Live:NotInterruptiblePlain()
	local kind = self:CastKind()
	if not kind then
		return false, true
	end
	return Plain(CastField(self, 8, 7))
end

function Live:SpellIDSecret()
	return CastField(self, 9, 8)
end

---@return integer|nil
---@return boolean readable
function Live:SpellIDPlain()
	return Plain(CastField(self, 9, 8))
end

---Duration object for StatusBar:SetTimerDuration and duration text bindings, or nil.
function Live:CastDurationSecret()
	local kind = self:CastKind()
	local u, call = self.unit, self.Call
	if kind == 'cast' and UnitCastingDuration then
		return call(UnitCastingDuration, u)
	elseif kind == 'channel' and UnitChannelDuration then
		return call(UnitChannelDuration, u)
	elseif kind == 'empower' and UnitEmpoweredChannelDuration then
		return call(UnitEmpoweredChannelDuration, u, true)
	end
	return nil
end

---Cast start and end in seconds, for the plain-math path (Classic family, Quirks plainCastText).
---@return number|nil startTime
---@return number|nil endTime
---@return boolean readable
function Live:CastTimesPlain()
	local kind = self:CastKind()
	if not kind then
		return nil, nil, true
	end
	local startMS, startReadable = Plain(CastField(self, 4, 4))
	local endMS, endReadable = Plain(CastField(self, 5, 5))
	if not (startReadable and endReadable) or not startMS or not endMS then
		return nil, nil, false
	end
	return startMS / 1000, endMS / 1000, true
end

function Live:IsImportantSecret()
	local spellIDSecret = self:SpellIDSecret()
	if type(spellIDSecret) == 'nil' or not (C_Spell and C_Spell.IsSpellImportant) then
		return false
	end
	return C_Spell.IsSpellImportant(spellIDSecret)
end

---@return boolean|nil
---@return boolean readable
function Live:IsImportantPlain()
	return Plain(self:IsImportantSecret())
end

function Live:AimedAtMeSecret()
	if not PlayerIsSpellTarget then
		return false
	end
	return self.Call(PlayerIsSpellTarget, self.unit)
end

---@return boolean|nil
---@return boolean readable
function Live:AimedAtMePlain()
	if not self:CastKind() then
		return false, true
	end
	return Plain(self:AimedAtMeSecret())
end

function Live:SpellTargetNameSecret()
	if not UnitSpellTargetName then
		return nil
	end
	return self.Call(UnitSpellTargetName, self.unit)
end

function Live:SpellTargetClassSecret()
	if not UnitSpellTargetClass then
		return nil
	end
	return self.Call(UnitSpellTargetClass, self.unit)
end

---Whether the game wants the cast target name shown for this unit.
---@return boolean|nil
---@return boolean readable
function Live:ShowSpellTargetPlain()
	if not UnitShouldDisplaySpellTargetName then
		return true, true
	end
	return Plain(self.Call(UnitShouldDisplaySpellTargetName, self.unit))
end

---Mythic+ forces as a percent string ("1.25%"), only during an active run.
function Live:ForcesSecret()
	if not (C_ScenarioInfo and C_ScenarioInfo.GetUnitCriteriaProgressValues) or not P.Context.challengeActive then
		return nil
	end
	local _, _, text = self.Call(C_ScenarioInfo.GetUnitCriteriaProgressValues, self.unit)
	return text
end

function Live:InCombatSecret()
	return self.Call(Fn(UnitAffectingCombat), self.unit)
end

---@return boolean|nil
---@return boolean readable
function Live:InCombatPlain()
	return Plain(self.Call(Fn(UnitAffectingCombat), self.unit))
end

---Readable creature id, nil when identity is hidden (UnitCreatureID returns nothing then).
---@return integer|nil
function Live:CreatureIDPlain()
	if Secret.ShouldUnitIdentityBeSecret(self.unit) then
		return nil
	end
	if UnitCreatureID then
		return (Plain(self.Call(UnitCreatureID, self.unit)))
	end
	local guid = Plain(self.Call(Fn(UnitGUID), self.unit))
	if type(guid) ~= 'string' then
		return nil
	end
	local kind, _, _, _, _, id = strsplit('-', guid)
	if kind == 'Creature' or kind == 'Vehicle' then
		return tonumber(id)
	end
	return nil
end

local function QuestLines(data)
	local lines = data.lines
	if not Secret.CanIndex(lines) then
		return nil
	end
	local objective = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective or 8
	for _, line in ipairs(lines) do
		if Secret.CanIndex(line) then
			local lineType = Plain(line.type)
			local completed, readable = Plain(line.completed)
			if lineType == objective and readable and completed == false then
				return true
			end
		end
	end
	return false
end

---Quest objective: questBoss, or an unfinished objective line in the unit tooltip (Retail and
---Forever). Tooltip reads are skipped inside instances and whenever identity is secret (S13).
---@return boolean|nil
function Live:QuestPlain()
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then
		return nil
	end
	if P.Context.place ~= 'world' or Secret.ShouldUnitIdentityBeSecret(self.unit) then
		return nil
	end
	local data = Plain(self.Call(C_TooltipInfo.GetUnit, self.unit))
	if not Secret.CanIndex(data) then
		return nil
	end
	-- Runs inside the plate add handler: a tooltip table the game forbids must not break it
	local ok, found = pcall(QuestLines, data)
	if not ok then
		return nil
	end
	return found
end

---Is this unit the same as another token (S4 fallback). Possibly secret: alpha sinks only.
---@param token string
function Live:IsUnitSecret(token)
	return self.Call(Fn(UnitIsUnit), self.unit, token)
end

function Live:PowerSecret(powerType)
	return self.Call(Fn(UnitPower), self.unit, powerType)
end

function Live:PowerMaxSecret(powerType)
	return self.Call(Fn(UnitPowerMax), self.unit, powerType)
end

---One aura by index for the Lua scan path (Classic family). nil when none or hidden.
---@param index integer
---@param filter string
---@return table|nil aura
function Live:AuraByIndexPlain(index, filter)
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
		return nil
	end
	local aura = Plain(self.Call(C_UnitAuras.GetAuraDataByIndex, self.unit, index, filter))
	if type(aura) ~= 'table' or not Secret.CanAccess(aura.spellId) then
		return nil
	end
	return aura
end

---Blizzard-sorted aura instance ids for the Lua scan path, where the client has them.
---@param filter string
---@param sortRule? integer
---@param sortDirection? integer
---@return table|nil ids
function Live:AuraInstanceIDsPlain(filter, sortRule, sortDirection)
	if not (C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs) then
		return nil
	end
	return (Plain(self.Call(C_UnitAuras.GetUnitAuraInstanceIDs, self.unit, filter, nil, sortRule, sortDirection)))
end

---@param auraInstanceID integer
---@return table|nil aura
function Live:AuraByInstancePlain(auraInstanceID)
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID) then
		return nil
	end
	local aura = Plain(self.Call(C_UnitAuras.GetAuraDataByAuraInstanceID, self.unit, auraInstanceID))
	if type(aura) ~= 'table' then
		return nil
	end
	return aura
end

---Previews only: live sources have no sample icons.
---@return nil
function Live:SampleAuras()
	return nil
end

----------------------------------------------------------------------------------------------------
-- SampleSource
----------------------------------------------------------------------------------------------------

---@class Plates.SampleSource : Plates.Source
local Sample = {}
Sample.__index = Sample
Source.Sample = Sample

---@param sample Plates.Sample|string Sample table or id from P.Data.Samples
---@return Plates.SampleSource
function Source.NewSample(sample)
	if type(sample) == 'string' then
		sample = P.Data.Samples[sample]
	end
	return setmetatable({ unit = nil, isSample = true, sample = sample or {} }, Sample)
end

---@param sample Plates.Sample|string
function Sample:SetSample(sample)
	if type(sample) == 'string' then
		sample = P.Data.Samples[sample]
	end
	self.sample = sample or {}
end

function Sample:SetGuarded() end

function Sample:ReadFacts(facts)
	P.util.Wipe(facts)
	for k, v in pairs(self.sample.facts or {}) do
		facts[k] = v
	end
	facts.isQuest = self.sample.quest or facts.isQuest
	facts.mobType = P.Situation.MobType(facts, P.Context)
	return facts
end

function Sample:PollFacts()
	return false
end

function Sample:HealthSecret()
	return self.sample.health or 100
end

function Sample:HealthMaxSecret()
	return self.sample.healthMax or 100
end

function Sample:HealthPlain()
	return self.sample.health or 100, true
end

function Sample:HealthPercentSecret(curve)
	local fraction = (self.sample.health or 100) / math.max(self.sample.healthMax or 100, 1)
	if curve and curve.Evaluate then
		return curve:Evaluate(fraction)
	end
	return fraction * 100
end

function Sample:FillHealPrediction()
	return false
end

function Sample:AbsorbSecret()
	return self.sample.absorb or 0
end

function Sample:HealAbsorbSecret()
	return self.sample.healAbsorb or 0
end

function Sample:NameSecret()
	return self.sample.name or ''
end

function Sample:NamePlain()
	return self.sample.name or '', true
end

function Sample:ClassTokenSecret()
	return self.sample.facts and self.sample.facts.classToken
end

function Sample:ClassTokenPlain()
	return self.sample.facts and self.sample.facts.classToken, true
end

function Sample:RaidMarkerSecret()
	return self.sample.raidMarker
end

function Sample:ThreatStatusSecret()
	return self.sample.threat
end

function Sample:ThreatStatusPlain()
	return self.sample.threat, true
end

function Sample:ThreatPercentSecret()
	return self.sample.threat and (self.sample.threat >= 2 and 100 or 60) or nil
end

function Sample:ThreatPercentPlain()
	return self:ThreatPercentSecret(), true
end

function Sample:IsTankingSecret(tank)
	return tank ~= 'pet' and self.sample.tankedByOther == true
end

function Sample:IsTankingPlain(tank)
	return self:IsTankingSecret(tank), true
end

function Sample:CastKind()
	return self.sample.cast and self.sample.cast.kind or nil
end

function Sample:CastBarID()
	return self.sample.cast and 1 or nil
end

function Sample:CastNameSecret()
	return self.sample.cast and self.sample.cast.name
end

function Sample:CastIconSecret()
	return self.sample.cast and self.sample.cast.icon
end

function Sample:NotInterruptibleSecret()
	return self.sample.cast and self.sample.cast.notInterruptible == true or false
end

function Sample:NotInterruptiblePlain()
	return self:NotInterruptibleSecret(), true
end

function Sample:SpellIDSecret()
	return self.sample.cast and 0 or nil
end

function Sample:SpellIDPlain()
	return self:SpellIDSecret(), true
end

---Loop start for the sample cast: casts repeat every `duration` seconds, starting mid-way so the
---kick mark and fill show at once.
local function LoopStart(cast)
	local now = P.services.GetTime()
	local duration = math.max(cast.duration or 3, 0.5)
	return now - ((now + duration * 0.4) % duration), duration
end

function Sample:CastDurationSecret()
	local cast = self.sample.cast
	if not cast or not (C_DurationUtil and C_DurationUtil.CreateDuration) then
		return nil
	end
	self.duration = self.duration or C_DurationUtil.CreateDuration()
	local start, duration = LoopStart(cast)
	self.duration:SetTimeFromStart(start, duration)
	return self.duration
end

function Sample:CastTimesPlain()
	local cast = self.sample.cast
	if not cast then
		return nil, nil, true
	end
	local start, duration = LoopStart(cast)
	return start, start + duration, true
end

function Sample:IsImportantSecret()
	return self.sample.cast and self.sample.cast.important == true or false
end

function Sample:IsImportantPlain()
	return self:IsImportantSecret(), true
end

function Sample:AimedAtMeSecret()
	return self.sample.cast and self.sample.cast.aimedAtMe == true or false
end

function Sample:AimedAtMePlain()
	return self:AimedAtMeSecret(), true
end

function Sample:SpellTargetNameSecret()
	return self.sample.cast and self.sample.cast.target
end

function Sample:SpellTargetClassSecret()
	return self.sample.cast and self.sample.cast.targetClass
end

function Sample:ShowSpellTargetPlain()
	return true, true
end

function Sample:ForcesSecret()
	return self.sample.forces
end

function Sample:InCombatSecret()
	return self.sample.threat ~= nil
end

function Sample:InCombatPlain()
	return self:InCombatSecret(), true
end

function Sample:CreatureIDPlain()
	return nil
end

function Sample:QuestPlain()
	return self.sample.quest == true
end

function Sample:IsUnitSecret(token)
	local states = self.sample.states or {}
	return states[token] == true
end

function Sample:PowerSecret()
	return 3
end

function Sample:PowerMaxSecret()
	return 5
end

function Sample:AuraByIndexPlain()
	return nil
end

function Sample:AuraInstanceIDsPlain()
	return nil
end

function Sample:AuraByInstancePlain()
	return nil
end

---Sample icons for one aura row (previews draw these instead of a container).
---@param row string
---@return Plates.SampleAura[]
function Sample:SampleAuras(row)
	return self.sample.auras and self.sample.auras[row] or {}
end

---Kick readiness in previews.
---@return boolean
function Sample:KickReady()
	return self.sample.kickReady == true
end

----------------------------------------------------------------------------------------------------
-- Player and group reads (not tied to a plate)
----------------------------------------------------------------------------------------------------

local function SpecRole()
	local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
	local getRole = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationRole) or GetSpecializationRole
	if getSpec and getRole then
		local ok, spec = pcall(getSpec)
		if ok and spec then
			local okRole, role = pcall(getRole, spec)
			if okRole and type(role) == 'string' then
				return role
			end
		end
	end
	if UnitGroupRolesAssigned then
		local role = Plain(UnitGroupRolesAssigned('player'))
		if role and role ~= 'NONE' then
			return role
		end
	end
	return nil
end

---Fill the unit-based context fields: role, group, other tanks, pet, player level.
---@param ctx Plates.Context
---@param roleSetting string profile.role
---@return Plates.Context
function Source.ReadPlayerContext(ctx, roleSetting)
	ctx.role = P.Roles.Resolve(roleSetting, SpecRole())
	ctx.playerLevel = Plain(Fn(UnitEffectiveLevel)('player')) or ctx.playerLevel or 1
	local inRaid = IsInRaid and IsInRaid() or false
	local inGroup = IsInGroup and IsInGroup() or false
	ctx.inGroup = inGroup and true or false
	ctx.groupSize = (GetNumGroupMembers and GetNumGroupMembers()) or 1
	local tanks = ctx.tanks or {}
	P.util.Wipe(tanks)
	if inGroup and UnitGroupRolesAssigned then
		local prefix = inRaid and 'raid' or 'party'
		local count = inRaid and ctx.groupSize or math.max(ctx.groupSize - 1, 0)
		-- party1-4 never include the player. In a raid, skip the player by raid index: UnitIsUnit
		-- can be secret on restricted maps, the player's own raid index never is
		local myIndex = inRaid and UnitInRaid and Plain(UnitInRaid('player')) or nil
		for i = 1, count do
			local unit = prefix .. i
			local isMe = false
			if inRaid then
				if myIndex then
					isMe = i == myIndex
				else
					local same, readable = Plain(Fn(UnitIsUnit)(unit, 'player'))
					-- Unknown counts as the player, so the player's own mobs never get another tank's color
					isMe = not readable or same == true
				end
			end
			if not isMe then
				local role = Plain(UnitGroupRolesAssigned(unit))
				if role == 'TANK' then
					tanks[#tanks + 1] = unit
				end
			end
		end
	end
	ctx.tanks = tanks
	ctx.petTank = (UnitExists and Plain(UnitExists('pet'))) and true or false
	return ctx
end

---Blizzard base nameplate for a unit token, or nil. pcall-guarded: it can still hard-error on
---restricted units (S14).
---@param unit string
---@return table|nil base
function Source.PlateForUnit(unit)
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
		return nil
	end
	local ok, base = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	if ok then
		return base
	end
	return nil
end

---Player class token (always plain for the player).
---@return string|nil
function Source.PlayerClass()
	local _, token = UnitClass('player')
	return token
end

---@param unit string
---@return boolean
function Source.UnitExists(unit)
	return (UnitExists and Plain(UnitExists(unit))) and true or false
end

----------------------------------------------------------------------------------------------------
-- Probes that touch unit functions (see Core/Caps.lua)
----------------------------------------------------------------------------------------------------

local Caps = P.Caps
Caps:AddProbe('lieutenant', function()
	return UnitIsLieutenant ~= nil
end, 'UnitIsLieutenant (mini-boss detection on Retail and Forever)')
Caps:AddProbe('bossMob', function()
	return UnitIsBossMob ~= nil
end, 'UnitIsBossMob')
Caps:AddProbe('questBoss', function()
	return UnitIsQuestBoss ~= nil
end, 'UnitIsQuestBoss')
Caps:AddProbe('healPrediction', function()
	return CreateUnitHealPredictionCalculator ~= nil and UnitGetDetailedHealPrediction ~= nil
end, 'Heal prediction calculator')
Caps:AddProbe('castDurations', function()
	return UnitCastingDuration ~= nil and UnitChannelDuration ~= nil
end, 'Cast and channel duration objects')
Caps:AddProbe('timerBars', function()
	if not (UnitCastingDuration and CreateFrame) then
		return false
	end
	local bar = CreateFrame('StatusBar')
	return bar.SetTimerDuration ~= nil
end, 'StatusBar:SetTimerDuration exists (in-game use confirmed by S0)')
Caps:AddProbe('spellTarget', function()
	return UnitSpellTargetName ~= nil and PlayerIsSpellTarget ~= nil
end, 'Cast target name and "aimed at you"')
Caps:AddProbe('creatureID', function()
	return UnitCreatureID ~= nil
end, 'UnitCreatureID')
