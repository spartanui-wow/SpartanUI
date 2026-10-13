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
	return setmetatable({ unit = unit, isSample = false, Call = Direct, readStamp = 0, castInfo = { n = 0 }, tankInfo = {}, auraLists = {}, scoreInfo = { n = 0 } }, Live)
end

---@param unit string|nil
function Live:SetUnit(unit)
	self.unit = unit
	self.readStamp = self.readStamp + 1
end

---One dispatch (an event, a message or a full update handed to every part of a plate) reads the
---unit's cast once: UnitCastingInfo and UnitChannelInfo answer the same for its whole length, so
---every cast helper picks its field from one read. The Plate calls BeginRead before handing the
---event to its parts and EndRead after. Reads outside a dispatch (shared timers) are never cached,
---and the cache also ends with the frame's time, so a dispatch an error cut short cannot leave a
---stale answer behind.
function Live:BeginRead()
	self.readStamp = self.readStamp + 1
	self.reading = true
end

function Live:EndRead()
	self.reading = false
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
	if P.Data.Totems:ForNPC(self:CreatureIDPlain(), P.Caps:Client()) then
		facts.isMinion = true
	end
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
	facts.isQuest = facts.questBoss or (not facts.isPlayer and self:QuestCachedPlain()) or nil
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

---Whether the unit is in range for a range checker (a LibRangeCheck harm checker or a spell
---check the Driver builds), for range fade (S9). Errors and hidden answers read as unknown.
---@param checker fun(unit: string): any
---@return boolean|nil inRange
---@return boolean readable
function Live:InRangePlain(checker)
	if not (checker and self.unit) then
		return nil, false
	end
	local ok, inRange = pcall(checker, self.unit)
	if not ok then
		return nil, false
	end
	return Plain(inRange)
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

function Live:FullNamePlain()
	local name, realm = self.Call(Fn(UnitFullName), self.unit)
	name, realm = Plain(name), Plain(realm)
	if type(name) ~= 'string' then
		return nil, false
	end
	if type(realm) == 'string' and realm ~= '' then
		return name .. '-' .. realm, true
	end
	return name, true
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

local function ReadThreatStatus(self)
	if self.reading and self.threatStamp == self.readStamp then
		return self.threatRaw
	end
	self.threatRaw = self.Call(Fn(UnitThreatSituation), 'player', self.unit)
	self.threatStamp = self.readStamp
	return self.threatRaw
end

function Live:ThreatStatusSecret()
	return ReadThreatStatus(self)
end

---@return integer|nil status
---@return boolean readable
function Live:ThreatStatusPlain()
	if Secret.ShouldUnitThreatStateBeSecret('player', self.unit) then
		return nil, false
	end
	return Plain(ReadThreatStatus(self))
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

---The player's threat as a percent of the highest threat on this unit not counting the player's
---(over 100 while the player leads; only for text sinks).
function Live:ThreatLeadSecret()
	return (self.Call(Fn(UnitThreatPercentageOfLead), 'player', self.unit))
end

---@return number|nil percentOfLead
---@return boolean readable
function Live:ThreatLeadPlain()
	if Secret.ShouldUnitThreatValuesBeSecret('player', self.unit) then
		return nil, false
	end
	return Plain((self.Call(Fn(UnitThreatPercentageOfLead), 'player', self.unit)))
end

local function ReadTanking(self, tank)
	local cached = self.tankInfo[tank]
	if not cached then
		cached = {}
		self.tankInfo[tank] = cached
	end
	if self.reading and cached.stamp == self.readStamp then
		return cached.raw
	end
	cached.raw = (self.Call(Fn(UnitDetailedThreatSituation), tank, self.unit))
	cached.stamp = self.readStamp
	return cached.raw
end

---Whether another unit is tanking this one, for secret-safe sinks.
function Live:IsTankingSecret(tank)
	return ReadTanking(self, tank)
end

---@param tank string
---@return boolean|nil
---@return boolean readable
function Live:IsTankingPlain(tank)
	return Plain(ReadTanking(self, tank))
end

---Copy a call's returns into a reused list (values stay as the game gave them; only kept, never
---looked at here).
---@param list table
---@return table list
local function FillList(list, ...)
	local n = select('#', ...)
	for i = 1, n do
		list[i] = (select(i, ...))
	end
	for i = n + 1, list.n do
		list[i] = nil
	end
	list.n = n
	return list
end

---The unit's cast info, read once per dispatch: kind ('cast' | 'channel' | 'empower' | nil) and
---the returns of UnitCastingInfo (cast) or UnitChannelInfo (channel, empower) in castInfo.
---@param self Plates.LiveSource
---@return string|nil kind
---@return table info
local function ReadCast(self)
	local info = self.castInfo
	local now = P.services.GetTime()
	if self.reading and info.stamp == self.readStamp and info.time == now then
		return info.kind, info
	end
	local kind
	FillList(info, self.Call(Fn(UnitCastingInfo), self.unit))
	if type(info[1]) ~= 'nil' then
		kind = 'cast'
	else
		FillList(info, self.Call(Fn(UnitChannelInfo), self.unit))
		if type(info[1]) ~= 'nil' then
			-- isEmpowered (the ninth return) is NeverSecret
			kind = info[9] and 'empower' or 'channel'
		end
	end
	info.kind, info.stamp, info.time = kind, self.reading and self.readStamp or nil, now
	return kind, info
end

---'cast' | 'channel' | 'empower' | nil. Plain: decided by presence (type) and NeverSecret flags.
---@return string|nil
function Live:CastKind()
	return (ReadCast(self))
end

---castBarID is NeverSecret on both info calls.
---@return integer|nil
function Live:CastBarID()
	local kind, info = ReadCast(self)
	if kind == 'cast' then
		return info[10]
	elseif kind then
		return info[11]
	end
	return nil
end

local function CastField(self, castIndex, channelIndex)
	local kind, info = ReadCast(self)
	if kind == 'cast' then
		return info[castIndex]
	elseif kind then
		return info[channelIndex]
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

-- S11: the API exists on all six clients, but the Classic family may never flag a spell. The
-- first readable "yes" from a real cast records Caps 'importantSeen' (the probe starts true only
-- where secrets exist), so option badges stop warning once the game has shown it answers.
local importantSeen = false

function Live:IsImportantSecret()
	local spellIDSecret = self:SpellIDSecret()
	if type(spellIDSecret) == 'nil' or not (C_Spell and C_Spell.IsSpellImportant) then
		return false
	end
	local answer = C_Spell.IsSpellImportant(spellIDSecret)
	if not importantSeen then
		local plain, readable = Plain(answer)
		if readable and plain == true then
			importantSeen = true
			P.Caps:Record('importantSeen', true)
		end
	end
	return answer
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

---Mythic+ forces as the documented percentValueString ("1.25"; the text part adds the percent
---sign, confirm in game), only during an active run.
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
	if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
		local ok, hidden = pcall(C_Secrets.ShouldUnitIdentityBeSecret, self.unit)
		if not ok or Plain(hidden) ~= false then
			return nil
		end
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

local LINE_TYPE = Enum and Enum.TooltipDataLineType
local QUEST_OBJECTIVE = LINE_TYPE and LINE_TYPE.QuestObjective or 8
local QUEST_TITLE = LINE_TYPE and LINE_TYPE.QuestTitle or 17
local QUEST_PLAYER = LINE_TYPE and LINE_TYPE.QuestPlayer or 18

---A goal's own text still short of done: "3/8", or a percent under 100. Classic tooltips mark
---percent goals with a leading dash ("- 45%"); structured objective lines need no dash.
---@param text string
---@param needDash? boolean
---@return boolean
local function OpenGoalText(text, needDash)
	local have, need = string.match(text, '(%d+)%s*/%s*(%d+)')
	if have and tonumber(have) < tonumber(need) then
		return true
	end
	local percent = string.match(text, needDash and '^%s*%-.-(%d+)%%' or '(%d+)%%')
	return percent ~= nil and tonumber(percent) < 100
end

local playerGUID, playerName

---True when a QuestPlayer line names the player (grouped tooltips list every member's progress
---under their name). The GUID decides; the name is a fallback (Forever shows only its first word).
---A line that says neither counts as ours, like a solo tooltip.
---@param line table
---@return boolean
local function IsPlayerSection(line)
	if not playerGUID then
		playerGUID = Plain(UnitGUID and UnitGUID('player'))
		playerName = Plain(UnitName and UnitName('player'))
	end
	local guid = Plain(line.guid)
	if type(guid) == 'string' and type(playerGUID) == 'string' then
		return guid == playerGUID
	end
	local text = Plain(line.leftText)
	if type(text) ~= 'string' or type(playerName) ~= 'string' then
		return true
	end
	return text == playerName or string.find(playerName, text .. ' ', 1, true) == 1
end

---Is this objective line unfinished? The line's `completed` flag (not in the generated docs, but
---carried by the game's tooltip data) decides when present; otherwise its text does.
---@param line table
---@return boolean
local function ObjectiveOpen(line)
	local completed, readable = Plain(line.completed)
	if readable and type(completed) == 'boolean' then
		return completed == false
	end
	local text = Plain(line.leftText)
	return type(text) == 'string' and OpenGoalText(text)
end

---An unfinished objective of the player's own in tooltip data. Sections under another group
---member's name (QuestPlayer) are skipped until the next quest title.
---@param data table
---@return boolean|nil
local function QuestLines(data)
	local lines = data.lines
	if not Secret.CanIndex(lines) then
		return nil
	end
	local others = false
	for _, line in ipairs(lines) do
		if Secret.CanIndex(line) then
			local lineType = Plain(line.type)
			if lineType == QUEST_TITLE then
				others = false
			elseif lineType == QUEST_PLAYER then
				others = not IsPlayerSection(line)
			elseif lineType == QUEST_OBJECTIVE and not others and ObjectiveOpen(line) then
				return true
			end
		end
	end
	return false
end

-- Unit tooltips on clients without C_TooltipInfo: one anonymous hidden tooltip, made on first use.
-- Quirk 'noTooltipScan' turns every scan off (same-day escape hatch).
local scanTip
local scanLines = {}

---The hidden scan tooltip (Classic family), or nil.
---@return table|nil
function Source.ScanTooltip()
	if scanTip == nil then
		scanTip = false
		local ok, tip = pcall(CreateFrame, 'GameTooltip', nil, nil, 'GameTooltipTemplate')
		if ok and tip then
			scanTip = tip
		end
	end
	return scanTip or nil
end

---Point the hidden tooltip at a unit (made once, so a scan makes no closure).
---@param tip table
---@param unit string
local function PrepareTip(tip, unit)
	tip:SetOwner(WorldFrame or UIParent, 'ANCHOR_NONE')
	if tip.ClearLines then
		tip:ClearLines()
	end
	tip:SetUnit(unit)
end

---Left text of every line of a unit's tooltip, through the hidden tooltip. nil when the client
---cannot scan. Reuses one table; copy what you keep.
---@param unit string
---@return string[]|nil lines
---@return integer count
local function ScanLines(unit)
	if P.Caps:Quirk('noTooltipScan') then
		return nil, 0
	end
	local tip = Source.ScanTooltip()
	if not (tip and tip.SetOwner and tip.SetUnit and tip.NumLines) then
		return nil, 0
	end
	local ok = pcall(PrepareTip, tip, unit)
	if not ok then
		return nil, 0
	end
	local count = tonumber((Plain(tip:NumLines()))) or 0
	local name = tip.GetName and tip:GetName()
	for i = 1, count do
		local region = (tip.GetLeftLine and tip:GetLeftLine(i)) or tip['TextLeft' .. i] or (name and _G[name .. 'TextLeft' .. i])
		local text = region and region.GetText and region:GetText()
		text = Plain(text)
		scanLines[i] = type(text) == 'string' and text or nil
	end
	for i = count + 1, #scanLines do
		scanLines[i] = nil
	end
	if tip.Hide then
		tip:Hide()
	end
	return scanLines, count
end

---Classic family: an unfinished objective in a native unit tooltip ("3/8" or "- 45%"). Whether
---Classic tooltips carry objective lines at all is S13; when they do not, this finds nothing and
---no quest mark shows.
---@param self Plates.LiveSource
---@return boolean|nil
local function ScanQuest(self)
	if Plain(self.Call(Fn(UnitIsPlayer), self.unit)) then
		return false
	end
	local lines, count = ScanLines(self.unit)
	if not lines then
		return nil
	end
	for i = 2, count do
		local text = lines[i]
		if text and OpenGoalText(text, true) then
			return true
		end
	end
	return false
end

---False when the game says the unit has nothing to do with the player's quests (Retail and
---Forever), so its tooltip is never read. nil when it cannot say. Quirk 'noQuestGate' turns the
---check off (same-day escape hatch if the game's answer misses quest mobs).
---@param self Plates.LiveSource
---@return boolean|nil
local function RelatedToQuest(self)
	local fn = C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest
	if not fn or P.Caps:Quirk('noQuestGate') then
		return nil
	end
	local ok, answer = pcall(fn, self.unit)
	if not ok then
		return nil
	end
	local related, readable = Plain(answer)
	if readable and type(related) == 'boolean' then
		return related
	end
	return nil
end

---Quest objective: questBoss, or an unfinished objective line of the player's own in the unit
---tooltip (C_TooltipInfo on Retail and Forever, the hidden tooltip on the Classic family). Tooltip
---reads are skipped inside instances, whenever identity is secret (S13), and for units the game
---says are not part of any active quest.
---@return boolean|nil
function Live:QuestPlain()
	if Plain(self.Call(Fn(UnitIsPlayer), self.unit)) then
		return false
	end
	if P.Context.place ~= 'world' or Secret.ShouldUnitIdentityBeSecret(self.unit) then
		return nil
	end
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then
		return ScanQuest(self)
	end
	if RelatedToQuest(self) == false then
		return false
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

local questCache = {}

function Source.ClearQuestCache()
	P.util.Wipe(questCache)
end

function Live:QuestCachedPlain()
	if P.Context.place ~= 'world' or Secret.ShouldUnitIdentityBeSecret(self.unit) then
		return nil
	end
	local guid = Plain(self.Call(Fn(UnitGUID), self.unit))
	if type(guid) ~= 'string' then
		return self:QuestPlain()
	end
	local found = questCache[guid]
	if found ~= nil then
		return found
	end
	found = self:QuestPlain()
	questCache[guid] = found
	return found
end

local levelPatterns

---True for the tooltip's level line ("Level 60 Beast"), which is never a title.
---@param text string
---@return boolean
local function IsLevelLine(text)
	if not levelPatterns then
		levelPatterns = {}
		for _, template in ipairs({ _G.UNIT_TYPE_LEVEL_TEMPLATE, _G.UNIT_LEVEL_TEMPLATE, _G.UNIT_TYPE_PLUS_LEVEL_TEMPLATE }) do
			if type(template) == 'string' then
				-- "%s", "%d" and "%2$s" become ".+"; every other magic character is escaped
				local pattern = string.gsub(template, '%%%d*%$?[ds]', '\001')
				pattern = string.gsub(pattern, '([%(%)%.%+%-%*%?%[%]%^%$%%])', '%%%1')
				pattern = string.gsub(pattern, '\001', '.+')
				levelPatterns[#levelPatterns + 1] = '^' .. pattern .. '$'
			end
		end
	end
	for _, pattern in ipairs(levelPatterns) do
		if string.match(text, pattern) then
			return true
		end
	end
	return false
end

-- Tooltip line types that are never a title
local NOT_TITLE = { [2] = true, [7] = true, [8] = true, [16] = true, [17] = true, [18] = true, [47] = true, [48] = true, [49] = true }

local function TitleFromData(data, index)
	local lines = data.lines
	if not Secret.CanIndex(lines) then
		return nil
	end
	local line = lines[index]
	if not Secret.CanIndex(line) then
		return nil
	end
	local lineType = Plain(line.type)
	if type(lineType) == 'number' and NOT_TITLE[lineType] then
		return nil
	end
	local text = Plain(line.leftText)
	return type(text) == 'string' and text or nil
end

---A title for the plate: an NPC's title line ("Innkeeper") from its tooltip, or a player's guild.
---Tooltip reads follow the quest rules: open world only, never while identity is secret.
---@return string|nil title
---@return boolean readable
function Live:TitlePlain()
	local u = self.unit
	if Plain(self.Call(Fn(UnitIsPlayer), u)) then
		if not GetGuildInfo then
			return nil, true
		end
		local guild, readable = Plain((self.Call(GetGuildInfo, u)))
		if not readable then
			return nil, false
		end
		return (type(guild) == 'string' and guild ~= '') and guild or nil, true
	end
	if P.Context.place ~= 'world' then
		return nil, true
	end
	if Secret.ShouldUnitIdentityBeSecret(u) then
		return nil, false
	end
	-- Color blind mode puts the reaction on the second line
	local index = (GetCVarBool and GetCVarBool('colorblindMode')) and 3 or 2
	local text
	if C_TooltipInfo and C_TooltipInfo.GetUnit then
		local data = Plain(self.Call(C_TooltipInfo.GetUnit, u))
		if not Secret.CanIndex(data) then
			return nil, false
		end
		local ok, found = pcall(TitleFromData, data, index)
		text = ok and found or nil
	else
		local lines = ScanLines(u)
		text = lines and lines[index]
	end
	if text and text ~= '' and not IsLevelLine(text) then
		return text, true
	end
	return nil, true
end

---Is this unit the same as another token (S4 fallback). Possibly secret: alpha sinks only.
---@param token string
function Live:IsUnitSecret(token)
	if not Secret.CanCompareUnitTokens(self.unit, token) then
		return nil
	end
	return Guarded(Fn(UnitIsUnit), self.unit, token)
end

function Live:PowerSecret(powerType)
	return self.Call(Fn(UnitPower), self.unit, powerType)
end

function Live:PowerMaxSecret(powerType)
	return self.Call(Fn(UnitPowerMax), self.unit, powerType)
end

-- The player's class resource (the classPower part). These read the player, never the plate's
-- unit: UnitPower and GetComboPoints are SecretWhenUnitPowerRestricted on Retail and Forever even
-- for the player, so the amount is a ...Secret value for pip bars only. Previews answer from the
-- sample instead (Sample methods below).

---The player's amount of one power type. Possibly secret: pip bars only.
---@param powerType integer
---@param unmodified? boolean Raw points (soul shard and ember fragments)
function Live:PlayerPowerSecret(powerType, unmodified)
	return self.Call(Fn(UnitPower), 'player', powerType, unmodified)
end

---Combo points the player has on the current target, on clients where points belong to the
---target. Possibly secret: pip bars only.
function Live:TargetComboPointsSecret()
	return self.Call(Fn(GetComboPoints), 'player', 'target')
end

---One rune of the player: start, duration, ready, readable. Plain or nothing.
---@param index integer
---@return number|nil start
---@return number|nil duration
---@return boolean|nil ready
---@return boolean readable
function Live:RunePlain(index)
	if not GetRuneCooldown then
		return nil, nil, nil, false
	end
	local start, duration, ready = self.Call(GetRuneCooldown, index)
	local readyPlain, okReady = Plain(ready)
	local startPlain, okStart = Plain(start)
	local durationPlain, okDuration = Plain(duration)
	if not (okReady and okStart and okDuration) or type(readyPlain) ~= 'boolean' then
		return nil, nil, nil, false
	end
	return startPlain, durationPlain, readyPlain, true
end

local chargedOut = {}

---Charged combo points of the player (a list of point indexes), or nil when there are none or
---the game hides them. The list is reused by the next call: read it at once, never keep it.
---@return integer[]|nil
function Live:ChargedPointsPlain()
	if not GetUnitChargedPowerPoints then
		return nil
	end
	local list = self.Call(GetUnitChargedPowerPoints, 'player')
	if not Secret.CanIndex(list) then
		return nil
	end
	local out = chargedOut
	P.util.Wipe(out)
	for i = 1, #list do
		local index = Plain(list[i])
		if type(index) == 'number' then
			out[#out + 1] = index
		end
	end
	return out
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

---Plain aura list shared by rows in one dispatch; sorting stays with each row.
function Live:AuraListPlain(filter)
	local cached = self.auraLists[filter]
	if not cached then
		cached = { list = {} }
		self.auraLists[filter] = cached
	end
	if self.reading and cached.stamp == self.readStamp then
		return cached.list
	end
	local list = cached.list
	P.util.Wipe(list)
	local ids
	if P.Caps:Get('auraInstanceIDs') then
		local ok, answer = pcall(self.AuraInstanceIDsPlain, self, filter)
		if ok then
			ids = answer
		else
			P.Caps:Record('auraInstanceIDs', false)
			P.log.warning('Sorted aura lists failed; reading auras by index: ' .. tostring(answer))
		end
	end
	if Secret.CanIndex(ids) then
		for i = 1, #ids do
			local aura = self:AuraByInstancePlain(ids[i])
			if aura then
				list[#list + 1] = aura
			end
		end
	else
		for i = 1, 40 do
			local aura = self:AuraByIndexPlain(i, filter)
			if not aura then
				break
			end
			list[#list + 1] = aura
		end
	end
	cached.stamp = self.readStamp
	return list
end

-- Reads for the text and icon parts (level, health text, classification, faction, arena labels).

---Effective level (-1 for skull-level bosses).
---@return integer|nil
---@return boolean readable
function Live:LevelPlain()
	return Plain(self.Call(Fn(UnitEffectiveLevel), self.unit))
end

---@return number|nil
---@return boolean readable
function Live:HealthMaxPlain()
	return Plain(self.Call(Fn(UnitHealthMax), self.unit))
end

---'normal' | 'elite' | 'rare' | 'rareelite' | 'worldboss' | 'trivial' | 'minus'
---@return string|nil
---@return boolean readable
function Live:ClassificationPlain()
	return Plain(self.Call(Fn(UnitClassification), self.unit))
end

---'Alliance' | 'Horde' | 'Neutral' | nil
---@return string|nil
---@return boolean readable
function Live:FactionPlain()
	return Plain((self.Call(Fn(UnitFactionGroup), self.unit)))
end

---Flagged for PvP. Possibly secret: alpha sinks only.
function Live:IsPvPSecret()
	return self.Call(Fn(UnitIsPVP), self.unit)
end

---@return boolean|nil
---@return boolean readable
function Live:IsPvPPlain()
	return Plain(self.Call(Fn(UnitIsPVP), self.unit))
end

---@return boolean|nil
---@return boolean readable
function Live:IsFreeForAllPlain()
	return Plain(self.Call(Fn(UnitIsPVPFreeForAll), self.unit))
end

---Arena opponent number (1-5) of this plate's unit, by comparing base plates (frames, never unit
---tokens). nil outside arenas, when the game will not hand out the arena plates (S18), or for
---anyone else.
---@return integer|nil
function Live:ArenaIndexPlain()
	local mine = self.unit and Source.PlateForUnit(self.unit)
	if not mine then
		return nil
	end
	for i = 1, 5 do
		local base = Source.PlateForUnit('arena' .. i)
		if base and base == mine then
			return i
		end
	end
	return nil
end

-- Phase 9 display reads. Role pictures are whole files so no hidden role needs Lua cropping.
local ROLE_TEXTURES = {
	TANK = 'Interface\\Icons\\Ability_Warrior_DefensiveStance',
	HEALER = 'Interface\\Icons\\Spell_Holy_Heal',
	DAMAGER = '',
}
Source.ROLE_TEXTURES = ROLE_TEXTURES
local ROLE_OPTIONS = { displayRoleIcon = true, textureMap = ROLE_TEXTURES }
local NPC_PATH = { 'colors', 'npcs' }

function Source.ArenasAvailablePlain()
	if P.Caps:Client() == 'era' then
		return false
	end
	if not GetArenaOpponentSpec then
		return false
	end
	if P.Caps:Client() == 'forever' then
		local ok, active = pcall(Fn(IsActiveBattlefieldArena))
		local arena = ok and Plain(active)
		return arena == true
	end
	return true
end

local function EnemyPlayer(self)
	return Plain(self.Call(Fn(UnitIsPlayer), self.unit)) == true and Plain(self.Call(Fn(UnitCanAttack), 'player', self.unit)) == true
end

local function SpecInfo(id, gender)
	local getInfo = GetSpecializationInfoByID or GetSpecializationInfoForSpecID
	if type(id) ~= 'number' or id <= 0 or not getInfo then
		return nil
	end
	local ok, _, name, _, icon, role = pcall(getInfo, id, gender)
	if ok then
		return Plain(name), Plain(icon), Plain(role)
	end
end

local CLASS_IDS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6, SHAMAN = 7, MAGE = 8, WARLOCK = 9, MONK = 10, DRUID = 11, DEMONHUNTER = 12, EVOKER = 13 }
local function ScoreDisplay(self, name)
	local class = self:ClassTokenPlain()
	local classID = class and CLASS_IDS[class]
	local countFn = C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID
	if classID and countFn and GetSpecializationInfoForClassID then
		local count = Plain(Guarded(countFn, classID))
		if type(count) == 'number' then
			for i = 1, count do
				local _, specName, _, icon, role = Guarded(GetSpecializationInfoForClassID, classID, i)
				specName, icon, role = Plain(specName), Plain(icon), Plain(role)
				if specName == name then
					return name, icon, role
				end
			end
		end
	end
	return name, nil, nil
end

-- Score rows can have readable names but hidden stats. Stop at the first hidden field.
local function ScoreSpec(self)
	local name, readable = self:NamePlain()
	if not readable or type(name) ~= 'string' then
		return nil
	end
	local fullName = self:FullNamePlain()
	local count = Guarded(Fn(GetNumBattlefieldScores))
	count = Plain(count)
	if type(count) ~= 'number' then
		return nil
	end
	for i = 1, count do
		local rowName, spec
		if P.Caps:Get('secrets') and C_PvP and C_PvP.GetScoreInfo then
			local info = Guarded(C_PvP.GetScoreInfo, i)
			if not Secret.CanIndex(info) then
				break
			end
			local hidden = false
			for key, value in pairs(info) do
				if not Secret.CanAccess(key) or not Secret.CanAccess(value) then
					hidden = true
					break
				end
			end
			if hidden then
				break
			end
			rowName, spec = info.name, info.talentSpec
		elseif GetBattlefieldScore then
			local info = FillList(self.scoreInfo, Guarded(GetBattlefieldScore, i))
			rowName, spec = Plain(info[1]), Plain(info[16])
		else
			break
		end
		if (rowName == name or rowName == fullName) and type(spec) == 'string' and spec ~= '' then
			return ScoreDisplay(self, spec)
		end
	end
end

local function ReadPvp(self)
	if self.reading and self.pvpStamp == self.readStamp then
		return
	end
	self.pvpStamp = self.reading and self.readStamp or nil
	self.specNameRaw, self.specIconRaw, self.hasSpecRaw = nil, nil, false
	self.roleIconRaw, self.showRoleRaw = nil, false
	if not Source.ArenasAvailablePlain() or not EnemyPlayer(self) then
		return
	end
	local index = self:ArenaIndexPlain()
	local util = UnitFrameUtil
	if index and util and util.GetArenaOpponentSpecDisplayInfo then
		local ok, info = pcall(util.GetArenaOpponentSpecDisplayInfo, index, ROLE_TEXTURES)
		if ok and Secret.CanIndex(info) then
			self.specNameRaw, self.specIconRaw, self.hasSpecRaw = info.specName, info.specIcon, info.hasSpec
			self.roleIconRaw, self.showRoleRaw = info.roleIconTexture, info.showRoleIcon
			return
		end
	end
	local name, icon, role
	if index and GetArenaOpponentSpec then
		local id, gender = Guarded(GetArenaOpponentSpec, index)
		name, icon, role = SpecInfo(Plain(id), Plain(gender))
	end
	if not name then
		name, icon, role = ScoreSpec(self)
	end
	self.specNameRaw, self.specIconRaw, self.hasSpecRaw = name, icon, name ~= nil
	if role == 'HEALER' or role == 'TANK' then
		self.roleIconRaw, self.showRoleRaw = ROLE_TEXTURES[role], true
	elseif util and util.GetUnitRoleIconDisplayInfo then
		local ok, info = pcall(util.GetUnitRoleIconDisplayInfo, self.unit, ROLE_OPTIONS)
		if ok and Secret.CanIndex(info) then
			self.roleIconRaw, self.showRoleRaw = info.roleIconTexture, info.showRoleIcon
		end
	end
end

function Live:SpecNameSecret()
	ReadPvp(self)
	return self.specNameRaw
end
function Live:SpecIconSecret()
	ReadPvp(self)
	return self.specIconRaw
end
function Live:HasSpecSecret()
	ReadPvp(self)
	return self.hasSpecRaw
end
function Live:RoleIconSecret()
	ReadPvp(self)
	return self.roleIconRaw
end
function Live:ShowRoleIconSecret()
	ReadPvp(self)
	return self.showRoleRaw
end
function Live:SpecNamePlain()
	return Plain(self:SpecNameSecret())
end
function Live:SpecIconPlain()
	return Plain(self:SpecIconSecret())
end
function Live:RoleIconPlain()
	return Plain(self:RoleIconSecret())
end

function Live:SpecialMobPlain()
	local id = self:CreatureIDPlain()
	if not id then
		return nil
	end
	NPC_PATH[3] = tostring(id)
	local row = P.Store:Get(NPC_PATH)
	return type(row) == 'table' and row or nil
end

function Live:DisplayNameSecret()
	local row = self:SpecialMobPlain()
	if row and type(row.rename) == 'string' and row.rename ~= '' then
		return row.rename
	end
	return self:NameSecret()
end

function Live:IsTotemPlain()
	local icon, readable = self:TotemIconPlain()
	if not readable then
		return nil, false
	end
	return icon ~= nil, true
end

function Live:TotemIconPlain()
	local data = P.Data.Totems
	local row = data:ForNPC(self:CreatureIDPlain(), P.Caps:Client())
	if row then
		return row.icon, true
	end
	if not P.Caps:Get('secrets') then
		return nil, true
	end
	local minion = Optional(self.Call, UnitIsMinion, self.unit)
	local controlled = Plain(self.Call(Fn(UnitPlayerControlled), self.unit))
	if minion ~= true or controlled ~= true then
		return nil, true
	end
	local owned = Plain(self.Call(Fn(UnitIsOwnerOrControllerOfUnit), 'player', self.unit))
	if owned ~= true then
		return nil, false
	end
	local name, readable = self:NamePlain()
	if not readable or type(name) ~= 'string' or not GetTotemInfo then
		return nil, false
	end
	for slot = 1, 4 do
		local have, totemName, _, _, icon = Guarded(GetTotemInfo, slot)
		have, totemName, icon = Plain(have), Plain(totemName), Plain(icon)
		if have == true and totemName == name then
			return icon, true
		end
	end
	return nil, true
end

function Source.TargetMobPlain()
	local target = Source.NewLive('target')
	if Plain(target.Call(Fn(UnitIsPlayer), 'target')) == true then
		return nil
	end
	return target:CreatureIDPlain(), target:NamePlain()
end

local function PvpChanged()
	if P.Driver and P.Driver.Relay then
		P.Driver:Relay('PVP_CHANGED')
	end
end
P:On('ENGINE_ENABLED', function()
	for _, event in ipairs({ 'UPDATE_BATTLEFIELD_SCORE', 'ARENA_PREP_OPPONENT_SPECIALIZATIONS', 'PLAYER_ROLES_ASSIGNED' }) do
		P:RegisterEvent(event, 'Source.pvp', PvpChanged)
	end
end, 'Source.pvp')
P:On('ENGINE_DISABLED', function()
	P:UnregisterAllEvents('Source.pvp')
end, 'Source.pvp')
P:On('RESTRICTION_CHANGED', function()
	if P.Driver and P.Driver.active then
		P.Driver:Relay('IDENTITY_CHANGED')
	end
end, 'Source.identity')

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

function Sample:InRangePlain()
	return self.sample.outOfRange ~= true, true
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

function Sample:FullNamePlain()
	return self.sample.fullName or self.sample.name or '', true
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

---sample.threatLead, else made up from the threat status (130% while holding it, 75% otherwise).
function Sample:ThreatLeadSecret()
	local sample = self.sample
	if sample.threatLead ~= nil then
		return sample.threatLead
	end
	return sample.threat and (sample.threat >= 2 and 130 or 75) or nil
end

function Sample:ThreatLeadPlain()
	return self:ThreatLeadSecret(), true
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
	return self.sample.npcID
end

function Sample:SpecNameSecret()
	return self.sample.specName
end
function Sample:SpecIconSecret()
	return self.sample.specIcon
end
function Sample:HasSpecSecret()
	return self.sample.specName ~= nil or self.sample.specIcon ~= nil
end
function Sample:RoleIconSecret()
	return ROLE_TEXTURES[self.sample.role]
end
function Sample:ShowRoleIconSecret()
	return self.sample.role == 'HEALER' or self.sample.role == 'TANK'
end
function Sample:SpecNamePlain()
	return self.sample.specName, true
end
function Sample:SpecIconPlain()
	return self.sample.specIcon, true
end
function Sample:RoleIconPlain()
	return self:RoleIconSecret(), true
end
function Sample:TotemIconPlain()
	return self.sample.totemIcon, true
end
function Sample:IsTotemPlain()
	return self.sample.totemIcon ~= nil, true
end
function Sample:SpecialMobPlain()
	local id = self:CreatureIDPlain()
	if not id then
		return nil
	end
	NPC_PATH[3] = tostring(id)
	local row = P.Store:Get(NPC_PATH)
	return type(row) == 'table' and row or nil
end
function Sample:DisplayNameSecret()
	local row = self:SpecialMobPlain()
	if row and type(row.rename) == 'string' and row.rename ~= '' then
		return row.rename
	end
	return self:NameSecret()
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

---The player's class resource in previews: `sample.classPower` points (default 3).
function Sample:PlayerPowerSecret()
	return self.sample.classPower or 3
end

function Sample:TargetComboPointsSecret()
	return self.sample.classPower or 3
end

---Preview runes: the first `classPower` runes are ready, the rest part way back.
---@param index integer
function Sample:RunePlain(index)
	local ready = index <= (self.sample.classPower or 3)
	local now = P.services.GetTime()
	local duration = 10
	return now - (ready and duration or (duration * (7 - index) / 6)), duration, ready, true
end

function Sample:ChargedPointsPlain()
	return nil
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

function Sample:LevelPlain()
	local facts = self.sample.facts or {}
	return self.sample.level or facts.effectiveLevel, true
end

function Sample:HealthMaxPlain()
	return self.sample.healthMax or 100, true
end

function Sample:ClassificationPlain()
	return self.sample.facts and self.sample.facts.classification, true
end

function Sample:TitlePlain()
	return self.sample.title, true
end

function Sample:FactionPlain()
	return self.sample.faction, true
end

function Sample:IsPvPSecret()
	return self.sample.pvp == true
end

function Sample:IsPvPPlain()
	return self.sample.pvp == true, true
end

function Sample:IsFreeForAllPlain()
	return false, true
end

function Sample:ArenaIndexPlain()
	return self.sample.arena
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

---Name and class token of whoever interrupted a cast, from the interruptedBy GUID of
---UNIT_SPELLCAST_INTERRUPTED, _CHANNEL_STOP and _EMPOWER_STOP (no combat log). Both may be
---secret: text and color sinks only. UnitNameFromGUID also names pets and NPCs; clients without
---it (the Classic family) name players only, through GetPlayerInfoByGUID.
---@param guidSecret any Possibly secret GUID from the event
---@return any nameSecret
---@return any classSecret Class file name ('MAGE')
function Source.InterrupterSecret(guidSecret)
	if type(guidSecret) == 'nil' then
		return nil, nil
	end
	local nameSecret, classSecret
	if UnitNameFromGUID then
		nameSecret = UnitNameFromGUID(guidSecret)
	end
	if UnitClassFromGUID then
		local _, fileSecret = UnitClassFromGUID(guidSecret)
		classSecret = fileSecret
	end
	if GetPlayerInfoByGUID and (type(nameSecret) == 'nil' or type(classSecret) == 'nil') then
		local _, playerClassSecret, _, _, _, playerNameSecret = GetPlayerInfoByGUID(guidSecret)
		if type(nameSecret) == 'nil' then
			nameSecret = playerNameSecret
		end
		if type(classSecret) == 'nil' then
			classSecret = playerClassSecret
		end
	end
	return nameSecret, classSecret
end

---Plain facts that decide which class resource the player has (the classPower part): class,
---specialization index, current power type (Energy means cat form for druids), vehicle, level.
---@param out table
---@return table out { class, spec, powerType, inVehicle, level }
function Source.ReadPlayerPower(out)
	local _, class = UnitClass('player')
	out.class = class
	local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
	local spec
	if getSpec then
		local ok, value = pcall(getSpec)
		spec = ok and Plain(value) or nil
	end
	out.spec = type(spec) == 'number' and spec or nil
	out.powerType = (Plain(Fn(UnitPowerType)('player')))
	out.inVehicle = (UnitHasVehicleUI and Plain(UnitHasVehicleUI('player'))) == true
	out.level = (Plain(Fn(UnitLevel)('player')))
	return out
end

---The player's maximum of one power type: value, readable.
---@param powerType integer
---@param unmodified? boolean Raw points (fragments)
---@return number|nil
---@return boolean readable
function Source.PlayerPowerMaxPlain(powerType, unmodified)
	if not UnitPowerMax then
		return nil, false
	end
	local value = Plain(UnitPowerMax('player', powerType, unmodified))
	if type(value) ~= 'number' then
		return nil, false
	end
	return value, true
end

---How many raw points make one shown point of a power type (soul shard fragments), or nil.
---@param powerType integer
---@return number|nil
function Source.PowerDisplayModPlain(powerType)
	if not UnitPowerDisplayMod then
		return nil
	end
	local ok, value = pcall(UnitPowerDisplayMod, powerType)
	value = ok and Plain(value) or nil
	return type(value) == 'number' and value or nil
end

---Rune type on clients with typed runes (1 blood, 2 unholy, 3 frost, 4 death), or nil.
---@param index integer
---@return integer|nil
function Source.RuneTypePlain(index)
	if not GetRuneType then
		return nil
	end
	local ok, value = pcall(GetRuneType, index)
	value = ok and Plain(value) or nil
	return type(value) == 'number' and value or nil
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
