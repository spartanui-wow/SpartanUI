---@type SUI
local SUI = SUI
---@class SUI.Module.LastTick
local module = SUI:GetModule('LastTick')
local Spells = module.Spells
local canaccess = SUI.BlizzAPI.canaccessvalue

-- Follows the player's DoTs on every enemy by GUID and works out the damage still to come.
--
-- A DoT starts from the player's cast (spell description: damage, school, duration). Each tick
-- then corrects it: the observed tick size replaces the description's guess, and the time between
-- ticks gives the real interval. Both are saved per spell so the next cast starts accurate.
--
-- Where ticks come from:
--   * clients with a combat log: SPELL_PERIODIC_DAMAGE, exact, and the target's own auras give
--     the exact expiry
--   * restricted clients (Retail, Forever): UNIT_COMBAT, which only gives amount and school,
--     so each hit is matched to a DoT by school, timing and size

---@class SUI.Module.LastTick.Dot
---@field spellID number
---@field info SUI.Module.LastTick.SpellInfo
---@field school number
---@field start number When it was applied (or refreshed)
---@field duration number
---@field total number Damage over the whole duration, from the description
---@field points? number Combo points a finisher was cast with
---@field expires number
---@field interval number
---@field intervalTrusted boolean Measured from two ticks
---@field tick number Average damage per tick
---@field tickKnown boolean Measured from a real tick
---@field ticks number Ticks dealt since `start`
---@field count number Ticks in total
---@field lastTick? number
---@field waitForTick? boolean Finisher whose combo points are unknown: shown from its first tick
---@field previous? SUI.Module.LastTick.Dot The DoT this cast replaced, restored if the cast missed
---@field watchFrom? number
---@field lastCheck? number

---@class SUI.Module.LastTick.Tracker
local Tracker = {}
module.Tracker = Tracker

---@type table<string, table<number, SUI.Module.LastTick.Dot>>
local byGUID = {}
---@type table<string, {guid: string|nil, points: number|nil}>
local sentCasts = {}
local playerGUID
local enabled = false

-- A tick may arrive this early or late (seconds) once the interval has been measured
local TICK_EARLY = 0.4
local TICK_LATE = 0.6
-- A miss or dodge this soon after a cast belongs to the cast
local AVOID_WINDOW = 0.5
-- Ticks seen at these sizes compared to the expected tick still count (crits on Retail)
local SIZE_RANGE = { 0.55, 1.6 }
local CRIT_RANGE = { 1.3, 2.4 }
local LOOSE_RANGE = { 0.2, 5 }

local AVOIDED = {
	MISS = true,
	DODGE = true,
	PARRY = true,
	RESIST = true,
	IMMUNE = true,
	EVADE = true,
	REFLECT = true,
	DEFLECT = true,
}

local events = CreateFrame('Frame')

---@param key string|number
---@return table|nil
local function Learned(key)
	return module.DBG and module.DBG.learned and module.DBG.learned[key]
end

---@param dot SUI.Module.LastTick.Dot
---@return string|number
local function LearnKey(dot)
	if dot.points then
		return dot.spellID .. ':' .. dot.points
	end
	return dot.spellID
end

---@param dot SUI.Module.LastTick.Dot
local function Remember(dot)
	if not (module.DBG and dot.tickKnown) then
		return
	end
	module.DBG.learned = module.DBG.learned or {}
	module.DBG.learned[LearnKey(dot)] = {
		tick = math.floor(dot.tick * 10 + 0.5) / 10,
		interval = dot.intervalTrusted and math.floor(dot.interval * 100 + 0.5) / 100 or nil,
	}
end

---Fill in tick size and interval from what was learned before, or from the description
---@param dot SUI.Module.LastTick.Dot
local function Prime(dot)
	local learned = Learned(LearnKey(dot))
	if learned and learned.interval then
		dot.interval = learned.interval
		dot.intervalTrusted = true
	end
	dot.count = Spells:TickCount(dot.duration or dot.info.duration, dot.interval)
	if learned and learned.tick then
		dot.tick = learned.tick
		dot.tickKnown = true
	else
		dot.tick = (dot.total or dot.info.total) / dot.count
		dot.tickKnown = false
	end
end

---@return number|nil
local function ReadComboPoints()
	local points
	if GetComboPoints then
		points = GetComboPoints('player', 'target')
	elseif UnitPower and Enum and Enum.PowerType then
		points = UnitPower('player', Enum.PowerType.ComboPoints)
	end
	if points and canaccess(points) and points > 0 then
		return points
	end
	return nil
end

---@param info SUI.Module.LastTick.SpellInfo
---@param points number
---@return {total: number, duration: number}|nil, number|nil
local function PointsEntry(info, points)
	if info.points[points] then
		return info.points[points], points
	end
	local best
	for count in pairs(info.points) do
		if count <= points and (not best or count > best) then
			best = count
		end
	end
	return best and info.points[best], best
end

---Expected damage of tick number `index`
---@param dot SUI.Module.LastTick.Dot
---@param index number
---@return number
local function TickAmount(dot, index)
	return dot.tick * Spells:RampFactor(dot.info.ramp, index, dot.count)
end

-- ============================================================================
-- Applying and removing
-- ============================================================================

---@param guid string
---@param spellID number
---@param info SUI.Module.LastTick.SpellInfo
---@param points number|nil
---@param now number
function Tracker:Apply(guid, spellID, info, points, now)
	local dots = byGUID[guid]
	if not dots then
		dots = {}
		byGUID[guid] = dots
	end
	local old = dots[spellID]
	if old and old.expires < now then
		old = nil
	end

	---@type SUI.Module.LastTick.Dot
	local dot = {
		spellID = spellID,
		info = info,
		school = info.school,
		start = now,
		duration = info.duration,
		total = info.total,
		interval = info.interval,
		intervalTrusted = info.intervalKnown,
		ticks = 0,
		previous = old,
	}

	if info.points then
		local entry, used = nil, nil
		if points then
			entry, used = PointsEntry(info, points)
		end
		if entry then
			dot.points = used
			dot.duration = entry.duration
			dot.total = entry.total
		else
			dot.waitForTick = true
			dot.duration = info.duration
			dot.total = 0
		end
	end

	Prime(dot)
	dot.expires = now + dot.duration

	if old then
		-- What this DoT has measured is better than anything saved
		if old.intervalTrusted and old.points == dot.points then
			dot.interval = old.interval
			dot.intervalTrusted = true
		end
		if old.tickKnown and old.points == dot.points then
			dot.tick = old.tick
			dot.tickKnown = true
		end
		dot.count = Spells:TickCount(dot.duration, dot.interval)
		if SUI.IsRetail then
			-- Refreshing keeps the tick rhythm and carries up to 30% of the duration over
			local carried = math.min(old.expires - now, dot.duration * 0.3)
			dot.expires = now + dot.duration + carried
			dot.start = old.start
			dot.lastTick = old.lastTick
			dot.ticks = old.ticks
			dot.count = old.ticks + Spells:TickCount(dot.expires - (old.lastTick or old.start), dot.interval)
		end
	end

	dots[spellID] = dot
	module:Log(
		('Applied %s to %s: %.0f over %ss, tick %.0f every %ss%s'):format(
			info.name,
			guid,
			dot.tick * dot.count,
			tostring(dot.duration),
			dot.tick,
			tostring(dot.interval),
			dot.waitForTick and ' (waiting for first tick)' or ''
		)
	)
	module:Wake()
end

---Undo a cast that missed: restore the DoT it replaced, if that one is still running
---@param guid string
---@param dot SUI.Module.LastTick.Dot
---@param why string
local function Cancel(guid, dot, why)
	local dots = byGUID[guid]
	if not dots then
		return
	end
	local previous = dot.previous
	if previous and previous.expires > GetTime() then
		dots[dot.spellID] = previous
	else
		dots[dot.spellID] = nil
	end
	module:Log(('Dropped %s on %s: %s'):format(dot.info.name, guid, why))
end

---@param guid string
function Tracker:Clear(guid)
	byGUID[guid] = nil
end

---@param guid string
---@return boolean
function Tracker:Has(guid)
	return byGUID[guid] ~= nil
end

---@return boolean
function Tracker:HasAny()
	return next(byGUID) ~= nil
end

---Forget every saved tick size and interval
function Tracker:Forget()
	if module.DBG then
		module.DBG.learned = {}
	end
end

---@param now number
function Tracker:Prune(now)
	for guid, dots in pairs(byGUID) do
		for spellID, dot in pairs(dots) do
			if dot.expires + 0.5 < now then
				dots[spellID] = nil
			end
		end
		if not next(dots) then
			byGUID[guid] = nil
		end
	end
	for castGUID, sent in pairs(sentCasts) do
		if sent.time + 10 < now then
			sentCasts[castGUID] = nil
		end
	end
end

-- ============================================================================
-- Ticks
-- ============================================================================

---Record a tick for a DoT
---@param dot SUI.Module.LastTick.Dot
---@param amount number
---@param crit boolean
---@param now number
local function OnTick(dot, amount, crit, now)
	local steps = 1
	if dot.lastTick then
		local gap = now - dot.lastTick
		steps = math.max(1, math.floor(gap / dot.interval + 0.5))
		local measured = gap / steps
		if measured >= 0.5 and measured <= 6 then
			dot.interval = dot.intervalTrusted and (dot.interval * 0.6 + measured * 0.4) or measured
			dot.intervalTrusted = true
		end
	elseif not dot.intervalTrusted then
		-- The first tick lands one interval after the DoT goes on
		local measured = now - dot.start
		if measured >= 0.8 and measured <= 6 then
			dot.interval = measured
		end
	end
	dot.ticks = dot.ticks + steps
	dot.lastTick = now

	if dot.waitForTick and dot.info.points then
		-- Combo points were unknown: the first tick's size tells how many were spent. Attack
		-- power only adds to a tick, so take the most points whose plain tick fits under it.
		local chosen
		for count, entry in pairs(dot.info.points) do
			local plain = entry.total / Spells:TickCount(entry.duration, dot.interval)
			if plain <= amount * 1.05 and (not chosen or count > chosen) then
				chosen = count
			end
		end
		chosen = chosen or 1
		local entry = dot.info.points[chosen] or dot.info.points[next(dot.info.points)]
		dot.points = chosen
		dot.duration = entry.duration
		dot.expires = dot.start + entry.duration
		dot.waitForTick = nil
	end

	dot.count = math.max(dot.ticks, Spells:TickCount(dot.expires - dot.start, dot.interval))
	local factor = Spells:RampFactor(dot.info.ramp, dot.ticks, dot.count)
	local plain = crit and amount / 1.5 or amount
	if not crit or not dot.tickKnown then
		dot.tick = plain / factor
		dot.tickKnown = true
	end
	dot.previous = nil
	Remember(dot)
end

---Is `now` a plausible time for this DoT's next tick? Returns how far off it is.
---@param dot SUI.Module.LastTick.Dot
---@param now number
---@return number|nil
local function TimingError(dot, now)
	local base = dot.lastTick or dot.start
	local since = now - base
	if dot.intervalTrusted then
		local steps = math.max(1, math.floor(since / dot.interval + 0.5))
		local expected = base + steps * dot.interval
		local off = now - expected
		if off >= -TICK_EARLY and off <= TICK_LATE then
			return math.abs(off)
		end
		return nil
	end
	-- Interval still a guess: anything from shortly after the cast to a bit past the guess
	if since >= 0.8 and since <= dot.interval + 1.2 then
		return math.abs(since - dot.interval)
	end
	return nil
end

---Does the hit's size fit the DoT's expected tick?
---@param dot SUI.Module.LastTick.Dot
---@param amount number
---@param crit boolean
---@return boolean
local function SizeFits(dot, amount, crit)
	if dot.waitForTick then
		return true
	end
	local expected = TickAmount(dot, dot.ticks + 1)
	if expected <= 0 then
		return true
	end
	local range = (not dot.tickKnown) and LOOSE_RANGE or (crit and CRIT_RANGE or SIZE_RANGE)
	local ratio = amount / expected
	return ratio >= range[1] and ratio <= range[2]
end

---Match a hit on an enemy to one of the player's DoTs (restricted clients)
---@param guid string
---@param amount number
---@param school number
---@param crit boolean
---@param now number
local function MatchHit(guid, amount, school, crit, now)
	local dots = byGUID[guid]
	if not dots then
		return
	end
	local best, bestError
	for _, dot in pairs(dots) do
		if dot.school == school and dot.expires + TICK_LATE >= now then
			local off = TimingError(dot, now)
			if off and SizeFits(dot, amount, crit) and (not bestError or off < bestError) then
				best, bestError = dot, off
			end
		end
	end
	if best then
		OnTick(best, amount, crit, now)
		module:Log(('Tick %s on %s: %d%s (tick %.0f, every %.2fs)'):format(best.info.name, guid, amount, crit and ' crit' or '', best.tick, best.interval))
	end
end

---A miss, dodge or resist right after a cast means the DoT never landed
---@param guid string
---@param school number
---@param now number
local function MatchAvoid(guid, school, now)
	local dots = byGUID[guid]
	if not dots then
		return
	end
	for _, dot in pairs(dots) do
		if dot.ticks == 0 and dot.school == school and now - dot.start <= AVOID_WINDOW then
			Cancel(guid, dot, 'avoided')
			return
		end
	end
end

-- ============================================================================
-- Watching enemies on screen
-- ============================================================================

---A DoT by spell ID, or by name where the client reports none (Classic combat log)
---@param dots table<number, SUI.Module.LastTick.Dot>
---@param spellID number|nil
---@param spellName string|nil
---@return SUI.Module.LastTick.Dot|nil
local function FindDotByName(dots, spellID, spellName)
	if spellID and spellID ~= 0 and dots[spellID] then
		return dots[spellID]
	end
	for _, dot in pairs(dots) do
		if dot.info.name == spellName then
			return dot
		end
	end
	return nil
end

---Read the player's auras on a unit for exact expiry times (clients with readable auras)
---@param unit string
---@param guid string
---@param now number
local function SyncAuras(unit, guid, now)
	local dots = byGUID[guid]
	if not dots then
		return
	end
	-- Matched by name too: a spell's debuff can carry a different ID than the cast
	local found = {}
	for index = 1, 40 do
		local name, spellID, expires, duration
		if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
			local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, 'HARMFUL|PLAYER')
			if not aura then
				break
			end
			name, spellID, expires, duration = aura.name, aura.spellId, aura.expirationTime, aura.duration
		elseif UnitAura then
			local auraName, _, _, _, auraDuration, expiration, _, _, _, id = UnitAura(unit, index, 'HARMFUL|PLAYER')
			if not auraName then
				break
			end
			name, spellID, expires, duration = auraName, id, expiration, auraDuration
		else
			return
		end
		if canaccess(name) and canaccess(spellID) and canaccess(expires) and canaccess(duration) then
			local dot = (spellID and dots[spellID]) or FindDotByName(dots, nil, name)
			if dot then
				found[dot] = true
				if duration and duration > 0 and expires and expires > 0 then
					dot.expires = expires
					dot.count = math.max(dot.ticks, Spells:TickCount(expires - dot.start, dot.interval))
				end
			end
		end
	end
	for spellID, dot in pairs(dots) do
		if not found[dot] and now - dot.start > 1 then
			dots[spellID] = nil
			module:Log(('%s is no longer on %s'):format(dot.info.name, guid))
		end
	end
end

---Called for enemies that are on screen (target, focus, nameplates). On restricted clients a DoT
---that stops ticking while its enemy is watched is dropped (dispelled, immune, or never landed).
---@param unit string
---@param guid string
---@param now number
function Tracker:Observe(unit, guid, now)
	if not module.Restricted then
		SyncAuras(unit, guid, now)
		return
	end
	local dots = byGUID[guid]
	if not dots then
		return
	end
	for _, dot in pairs(dots) do
		-- Ticks are only reported for enemies on screen; start counting from when it came back
		if not dot.lastCheck or now - dot.lastCheck > 0.5 then
			dot.watchFrom = now
		end
		dot.lastCheck = now
		local due = math.max((dot.lastTick or dot.start) + dot.interval, dot.watchFrom)
		local grace = dot.intervalTrusted and dot.interval * 2 + TICK_LATE or dot.interval * 2 + 1.5
		if now > due + grace and now < dot.expires then
			Cancel(guid, dot, 'stopped ticking')
		end
	end
end

---Damage the player's DoTs on this enemy still have to deal
---@param guid string
---@param now number
---@return number
function Tracker:Remaining(guid, now)
	local dots = byGUID[guid]
	if not dots then
		return 0
	end
	local total = 0
	for _, dot in pairs(dots) do
		if not dot.waitForTick then
			local nextTick = (dot.lastTick or dot.start) + dot.interval
			local index = dot.ticks + 1
			-- Ticks whose time has clearly passed have been dealt, seen or not
			while nextTick < now - TICK_LATE do
				nextTick = nextTick + dot.interval
				index = index + 1
			end
			-- The count decides how many ticks are left; the expiry only guards against a bad count
			while index <= dot.count and nextTick <= dot.expires + dot.interval * 0.5 do
				total = total + TickAmount(dot, index)
				nextTick = nextTick + dot.interval
				index = index + 1
			end
		end
	end
	return total
end

-- ============================================================================
-- Events
-- ============================================================================

local lastHit = {}

local function OnUnitCombat(unit, action, flag, amount, school)
	if not (canaccess(action) and canaccess(amount) and canaccess(school)) then
		return
	end
	local guid = module:SafeGUID(unit)
	if not guid or not byGUID[guid] then
		return
	end
	local now = GetTime()
	-- The same hit is reported once for every token that points at the enemy
	if lastHit.guid == guid and lastHit.time == now and lastHit.action == action and lastHit.amount == amount and lastHit.school == school then
		return
	end
	lastHit.guid, lastHit.time, lastHit.action, lastHit.amount, lastHit.school = guid, now, action, amount, school

	if action == 'WOUND' then
		if amount and amount > 0 then
			MatchHit(guid, amount, school, canaccess(flag) and flag == 'CRITICAL', now)
		end
	elseif AVOIDED[action] then
		MatchAvoid(guid, school, now)
	end
end

local function OnCombatLog()
	local _, subEvent, _, sourceGUID, _, _, _, destGUID, _, _, _, spellID, spellName, _, amount, _, _, _, _, _, critical = CombatLogGetCurrentEventInfo()
	if subEvent == 'UNIT_DIED' or subEvent == 'PARTY_KILL' then
		byGUID[destGUID] = nil
		return
	end
	if sourceGUID ~= playerGUID then
		return
	end
	local dots = byGUID[destGUID]
	if not dots then
		return
	end
	local now = GetTime()
	if subEvent == 'SPELL_PERIODIC_DAMAGE' then
		local dot = FindDotByName(dots, spellID, spellName)
		if dot and amount and amount > 0 then
			OnTick(dot, amount, critical and true or false, now)
		end
	elseif subEvent == 'SPELL_PERIODIC_MISSED' then
		local dot = FindDotByName(dots, spellID, spellName)
		if dot then
			dot.ticks = dot.ticks + 1
			dot.lastTick = now
		end
	elseif subEvent == 'SPELL_MISSED' then
		local dot = FindDotByName(dots, spellID, spellName)
		if dot and dot.ticks == 0 and now - dot.start <= 1 then
			Cancel(destGUID, dot, 'missed')
		end
	elseif subEvent == 'SPELL_AURA_REMOVED' then
		local dot = FindDotByName(dots, spellID, spellName)
		if dot and now - dot.start > 0.3 then
			dots[dot.spellID] = nil
		end
	end
end

---@param castGUID string
---@param spellID number
local function OnSpellcastSent(_, _, castGUID, spellID)
	if not (castGUID and canaccess(castGUID)) then
		return
	end
	local guid = UnitCanAttack('player', 'target') and module:SafeGUID('target') or nil
	sentCasts[castGUID] = { guid = guid, points = ReadComboPoints(), time = GetTime() }
end

---@param castGUID string
---@param spellID number
local function OnSpellcastSucceeded(_, castGUID, spellID)
	if not (spellID and canaccess(spellID) and castGUID and canaccess(castGUID)) then
		return
	end
	local sent = sentCasts[castGUID]
	sentCasts[castGUID] = nil
	local info = Spells:Get(spellID)
	if not info then
		return
	end
	local guid = sent and sent.guid
	if not guid and UnitCanAttack('player', 'target') then
		guid = module:SafeGUID('target')
	end
	if not guid then
		return
	end
	Tracker:Apply(guid, spellID, info, sent and sent.points or ReadComboPoints(), GetTime())
end

events:SetScript('OnEvent', function(_, event, ...)
	if event == 'UNIT_SPELLCAST_SUCCEEDED' then
		OnSpellcastSucceeded(...)
	elseif event == 'UNIT_SPELLCAST_SENT' then
		OnSpellcastSent(...)
	elseif event == 'UNIT_COMBAT' then
		OnUnitCombat(...)
	elseif event == 'COMBAT_LOG_EVENT_UNFILTERED' then
		OnCombatLog()
	elseif event == 'PLAYER_REGEN_ENABLED' then
		Tracker:Prune(GetTime())
	end
end)

function Tracker:Enable()
	if enabled then
		return
	end
	enabled = true
	playerGUID = UnitGUID('player')
	-- Unit events for the player only: other units' cast events can carry secret unit tokens
	events:RegisterUnitEvent('UNIT_SPELLCAST_SENT', 'player')
	events:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'player')
	events:RegisterEvent('PLAYER_REGEN_ENABLED')
	if module.Restricted then
		events:RegisterEvent('UNIT_COMBAT')
	else
		events:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
	end
end

function Tracker:Disable()
	enabled = false
	events:UnregisterAllEvents()
	wipe(byGUID)
	wipe(sentCasts)
end

-- Exposed for the options preview and tests
Tracker.OnTick = OnTick
Tracker.MatchHit = MatchHit
