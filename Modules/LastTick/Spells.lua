---@type SUI
local SUI = SUI
---@class SUI.Module.LastTick
local module = SUI:GetModule('LastTick')

-- Reads a damage over time spell from its description, once per spell ID. Descriptions leave out
-- spell and attack power, so these numbers are only a first guess; observed ticks replace them.
-- The patterns read English descriptions. On other languages nothing is recognised until the
-- spell has been seen ticking (clients with a combat log) or not at all (restricted clients).

---@class SUI.Module.LastTick.SpellInfo
---@field name string
---@field total number Damage over the whole duration
---@field duration number Seconds
---@field interval number Seconds between ticks
---@field intervalKnown boolean The description states the interval
---@field school number School bit mask
---@field ramp boolean Ticks start low and build up
---@field points? table<number, {total: number, duration: number}> Finisher damage by combo points

---@class SUI.Module.LastTick.Spells
local Spells = {}
module.Spells = Spells

local SCHOOL_MASKS = {
	physical = 1,
	holy = 2,
	fire = 4,
	nature = 8,
	frost = 16,
	shadow = 32,
	arcane = 64,
}
local SCHOOL_GLOBALS = {
	STRING_SCHOOL_PHYSICAL = 1,
	STRING_SCHOOL_HOLY = 2,
	STRING_SCHOOL_FIRE = 4,
	STRING_SCHOOL_NATURE = 8,
	STRING_SCHOOL_FROST = 16,
	STRING_SCHOOL_SHADOW = 32,
	STRING_SCHOOL_ARCANE = 64,
}
for global, mask in pairs(SCHOOL_GLOBALS) do
	local name = _G[global]
	if type(name) == 'string' and name ~= '' then
		SCHOOL_MASKS[name:lower()] = mask
	end
end

-- Damage that is not a single-target DoT on the spell's target
local SKIP_PHRASES = {
	'nearby',
	'all enemies',
	'enemies within',
	'enemies in',
	'each enemy',
	'enemies who',
	'area',
	'targets within',
	'up to %d+ targets',
	'coats',
	'weapon',
	'your pet',
}

---@type table<number, SUI.Module.LastTick.SpellInfo|false>
local cache = {}

---@param spellID number
---@return string|nil
local function Description(spellID)
	if C_Spell and C_Spell.GetSpellDescription then
		return C_Spell.GetSpellDescription(spellID)
	end
	return GetSpellDescription and GetSpellDescription(spellID)
end

---@param spellID number
---@return string
local function Name(spellID)
	if C_Spell and C_Spell.GetSpellName then
		return C_Spell.GetSpellName(spellID) or ''
	end
	return (GetSpellInfo and GetSpellInfo(spellID)) or ''
end

---@param word string|nil
---@return number
local function School(word)
	return (word and SCHOOL_MASKS[word]) or 1
end

---Seconds between ticks when the description does not say. Most early DoTs tick every 3
---seconds; durations that are not a multiple of 3 almost always tick every 2.
---@param duration number
---@return number
local function GuessInterval(duration)
	if duration % 3 == 0 then
		return 3
	end
	if duration % 2 == 0 then
		return 2
	end
	return 3
end

---@param text string Lower-cased description with thousands separators removed
---@return table<number, {total: number, duration: number}>|nil
local function ReadComboPoints(text)
	if not text:find('combo point') then
		return nil
	end
	local fallbackDuration = tonumber(text:match('over ([%d%.]+) sec'))
	local points
	for count, entry in text:gmatch('(%d) points?:([^\n]*)') do
		local damage = tonumber(entry:match('(%d+)%s*%a*%s*damage'))
		local duration = tonumber(entry:match('over ([%d%.]+) sec')) or fallbackDuration
		if damage and duration then
			points = points or {}
			points[tonumber(count)] = { total = damage, duration = duration }
		end
	end
	return points
end

---Parse a description into DoT info
---@param spellID number
---@param raw string
---@return SUI.Module.LastTick.SpellInfo|nil
function Spells:Parse(spellID, raw)
	local text = raw:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', ''):lower()
	text = text:gsub('(%d),(%d)', '%1%2')

	for _, phrase in ipairs(SKIP_PHRASES) do
		if text:find(phrase) then
			return nil
		end
	end

	---@type SUI.Module.LastTick.SpellInfo
	local info = {
		name = Name(spellID),
		total = 0,
		duration = 0,
		interval = 3,
		intervalKnown = false,
		school = 1,
		ramp = text:find('slowly at first') ~= nil,
	}

	local points = ReadComboPoints(text)
	if points then
		info.points = points
		local lowest = points[1] or points[next(points)]
		info.duration = lowest.duration
		info.interval = 2
		return info
	end

	-- "X <school> damage every N sec for M sec" / "transfers X health every N sec ... lasts M sec"
	local tick, word, every = text:match('(%d+) (%a*) ?damage every ([%d%.]+) sec')
	if not tick then
		tick, every = text:match('transfers (%d+) health every ([%d%.]+) sec')
		word = 'shadow'
	end
	if tick then
		local duration = tonumber(text:match('for ([%d%.]+) sec') or text:match('lasts ([%d%.]+) sec'))
		every = tonumber(every)
		if duration and every and every > 0 then
			info.duration = duration
			info.interval = every
			info.intervalKnown = true
			info.total = tonumber(tick) * math.floor(duration / every + 0.5)
			info.school = School(word ~= '' and word or nil)
			return info
		end
	end

	-- "X to Y <school> damage over N sec", "X <school> damage over N sec", "X damage over N sec"
	local low, high, duration
	low, high, word, duration = text:match('(%d+) to (%d+) (%a*) ?damage over ([%d%.]+) sec')
	if not low then
		low, word, duration = text:match('(%d+) (%a+) damage over ([%d%.]+) sec')
	end
	if not low then
		low, duration = text:match('(%d+) damage over ([%d%.]+) sec')
		word = nil
	end
	if not low then
		return nil
	end

	low = tonumber(low)
	high = tonumber(high) or low
	info.total = (low + high) / 2
	info.duration = tonumber(duration)
	info.interval = GuessInterval(info.duration)
	info.school = School(word ~= '' and word or nil)
	if info.duration <= 0 or info.total <= 0 then
		return nil
	end
	return info
end

---DoT info for a spell, or nil when it is not a DoT this module can follow
---@param spellID number
---@return SUI.Module.LastTick.SpellInfo|nil
function Spells:Get(spellID)
	local cached = cache[spellID]
	if cached ~= nil then
		return cached or nil
	end
	local raw = Description(spellID)
	-- Spell data that has not loaded yet comes back empty; ask again next time
	if not raw or raw == '' or not SUI.BlizzAPI.canaccessvalue(raw) then
		return nil
	end
	local info = Spells:Parse(spellID, raw)
	cache[spellID] = info or false
	if info then
		module:Log(
			('Spell %d (%s): %s over %ss, school %d, every %ss%s'):format(
				spellID,
				info.name,
				info.points and 'by combo points' or tostring(info.total),
				tostring(info.duration),
				info.school,
				tostring(info.interval),
				info.ramp and ', builds up' or ''
			)
		)
	end
	return info
end

---Number of ticks a DoT of this length makes
---@param duration number
---@param interval number
---@return number
function Spells:TickCount(duration, interval)
	return math.max(1, math.floor(duration / interval + 0.5))
end

---Share of the average tick a given tick deals. Ramping curses deal a third of their ticks at
---half, a third at the average and a third at one and a half times.
---@param ramp boolean
---@param index number 1-based tick number
---@param count number Ticks in total
---@return number
function Spells:RampFactor(ramp, index, count)
	if not ramp or count < 3 then
		return 1
	end
	local third = count / 3
	if index <= third then
		return 0.5
	elseif index <= third * 2 then
		return 1
	end
	return 1.5
end
