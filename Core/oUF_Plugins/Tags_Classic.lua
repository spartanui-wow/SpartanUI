---@diagnostic disable: missing-parameter
local SUI = SUI
local unpack = unpack

-- ============================================================================
-- Classic-Specific oUF Tags for SpartanUI
-- ============================================================================
-- This file contains Classic versions of tags that use different APIs
-- Retail version is in Tags.lua
-- ============================================================================

-- Classic health/power formatting (uses different calculation methods)
local function dynamicCalc(num)
	if num >= 1000000000 then
		return SUI:round(num / 1000000000, 1) .. 'B'
	elseif num >= 1000000 then
		return SUI:round(num / 1000000, 1) .. 'M'
	else
		return SUI.Font:comma_value(num)
	end
end

local function shortCalc(num)
	if num >= 1000000 then
		return SUI:round(num / 1000000, 0) .. 'M'
	elseif num >= 1000 then
		return SUI:round(num / 1000, 0) .. 'K'
	else
		return SUI.Font:comma_value(num)
	end
end

local function calculateResult(currentVal, maxVal, isDead, ...)
	local returnVal = ''
	local num = currentVal

	for i = 1, select('#', ...) do
		local var = tostring(select(i, ...))
		if var == 'missing' then
			num = maxVal - currentVal
		elseif var == 'max' then
			num = maxVal
		end
	end

	for i = 1, select('#', ...) do
		local var = tostring(select(i, ...))

		if var == 'percentage' then
			returnVal = math.floor(currentVal / maxVal * 100 + 0.5) .. '%'
		elseif var == 'dynamic' then
			returnVal = dynamicCalc(num)
		elseif var == 'short' then
			returnVal = shortCalc(num)
		elseif var == 'hideDead' and isDead then
			return ''
		elseif var == 'displayDead' and isDead then
			return 'Dead'
		elseif var == 'hideZero' and (currentVal == 0 or num == 0) then
			return ''
		elseif var == 'hideMax' and currentVal == maxVal then
			return ''
		end
	end
	if returnVal == '' then
		returnVal = SUI.Font:comma_value(num)
	end

	return returnVal
end

local function SUIHealth(unit, _, ...)
	local currentVal = UnitHealth(unit) or 0
	local maxVal = UnitHealthMax(unit) or currentVal
	local isDead = UnitIsDeadOrGhost(unit)

	return calculateResult(currentVal, maxVal, isDead, ...)
end

local function SUIPower(unit, _, ...)
	local returnVal = ''
	if not ... then
		return returnVal
	end

	local currentVal = UnitPower(unit) or 0
	local maxVal = UnitPowerMax(unit) or currentVal
	local isDead = UnitIsDeadOrGhost(unit)

	return calculateResult(currentVal, maxVal, isDead, ...)
end

SUIUF.Tags.Events['SUIHealth'] = 'UNIT_HEALTH UNIT_MAXHEALTH'
SUIUF.Tags.Methods['SUIHealth'] = SUIHealth

SUIUF.Tags.Events['SUIPower'] = 'UNIT_MAXPOWER UNIT_POWER_UPDATE'
SUIUF.Tags.Methods['SUIPower'] = SUIPower

SUIUF.Tags.Events['SUIHealthDeficit'] = 'UNIT_HEALTH UNIT_MAXHEALTH'
SUIUF.Tags.Methods['SUIHealthDeficit'] = function(unit)
	if not unit or UnitIsDeadOrGhost(unit) then
		return ''
	end
	local missing = (UnitHealthMax(unit) or 0) - (UnitHealth(unit) or 0)
	if missing <= 0 then
		return ''
	end
	return '|cffff4444-' .. AbbreviateNumbers(missing) .. '|r'
end

-- Usage: [SUI_smartlevel] hides the level at max level; [SUI_smartlevel(show)] always shows it
SUIUF.Tags.Events['SUI_smartlevel'] = 'UNIT_LEVEL PLAYER_LEVEL_UP UNIT_CLASSIFICATION_CHANGED'
SUIUF.Tags.Methods['SUI_smartlevel'] = function(unit, _, ...)
	local level = (UnitEffectiveLevel or UnitLevel)(unit)
	if not level then
		return nil
	end

	local classification = UnitClassification(unit)
	if classification == 'worldboss' then
		return 'Boss'
	end
	if level <= 0 then
		return '??'
	end

	local show = false
	for i = 1, select('#', ...) do
		if tostring(select(i, ...)) == 'show' then
			show = true
		end
	end
	if not show and level >= GetMaxPlayerLevel() then
		return nil
	end

	if classification == 'elite' or classification == 'rareelite' then
		return level .. '+'
	end
	return tostring(level)
end

-- LEGACY Health Formatting Tags
do
	local listing = {
		['health:current-short'] = { 'short' },
		['health:current-dynamic'] = { 'dynamic' },
		['health:current-formatted'] = {},
		['health:max-short'] = { 'max', 'short' },
		['health:max-dynamic'] = { 'max', 'dynamic' },
		['health:max-formatted'] = { 'max' },
		['health:missing-short'] = { 'missing', 'short' },
		['health:missing-dynamic'] = { 'missing', 'dynamic' },
		['health:missing-formatted'] = { 'missing' },
	}
	for k, v in pairs(listing) do
		SUIUF.Tags.Events[k] = 'UNIT_HEALTH UNIT_MAXHEALTH'
		SUIUF.Tags.Methods[k] = function(unit)
			return SUIHealth(unit, nil, unpack(v or {}))
		end
	end
end

-- LEGACY Mana Formatting Tags
do
	local listing = {
		['power:current-short'] = { 'short' },
		['power:current-dynamic'] = { 'dynamic' },
		['power:current-formatted'] = {},
		['power:max-short'] = { 'max', 'short' },
		['power:max-dynamic'] = { 'max', 'dynamic' },
		['power:max-formatted'] = { 'max' },
		['power:missing-short'] = { 'missing', 'short' },
		['power:missing-dynamic'] = { 'missing', 'dynamic' },
		['power:missing-formatted'] = { 'missing' },
	}
	for k, v in pairs(listing) do
		SUIUF.Tags.Events[k] = 'UNIT_MAXPOWER UNIT_DISPLAYPOWER UNIT_POWER_FREQUENT'
		SUIUF.Tags.Methods[k] = function(unit)
			return SUIPower(unit, nil, unpack(v))
		end
	end
end

-- Class Color Tag
do
	local function hex(r, g, b)
		if r then
			if type(r) == 'table' then
				if r.r then
					r, g, b = r.r, r.g, r.b
				else
					r, g, b = unpack(r)
				end
			end
			return ('|cff%02x%02x%02x'):format(r * 255, g * 255, b * 255)
		end
	end

	SUIUF.Tags.Events['SUI_ColorClass'] = 'UNIT_HEALTH UNIT_MAXHEALTH'
	SUIUF.Tags.Methods['SUI_ColorClass'] = function(u)
		local _, class = UnitClass(u)

		if u == 'pet' then
			return hex(SUIUF.colors.class[class])
		elseif UnitIsPlayer(u) then
			return hex(SUIUF.colors.class[class])
		else
			return hex(1, 1, 1)
		end
	end
	-- AFK / DND status text
	SUIUF.Tags.Events['afkdnd'] = 'PLAYER_FLAGS_CHANGED PLAYER_TARGET_CHANGED UNIT_TARGET'
	SUIUF.Tags.Methods['afkdnd'] = function(unit)
		if unit then
			if UnitIsAFK(unit) then
				return 'AFK'
			elseif UnitIsDND and UnitIsDND(unit) then
				return 'DND'
			end
			return ''
		end
	end
end
