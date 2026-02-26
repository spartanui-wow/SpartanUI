---@diagnostic disable: missing-parameter
local _, ns = ...
local oUF = ns.oUF or oUF
local unpack = unpack

-- ============================================================================
-- Custom oUF Tags for SpartanUI
-- ============================================================================

-- AFK / DND status text
oUF.Tags.Events['afkdnd'] = 'PLAYER_FLAGS_CHANGED PLAYER_TARGET_CHANGED UNIT_TARGET'
oUF.Tags.Methods['afkdnd'] = function(unit)
	if unit then
		local afk = UnitIsAFK(unit)
		if not SUI.BlizzAPI.canaccessvalue(afk) then
			return ''
		end
		if afk then
			return 'AFK'
		elseif UnitIsDND and UnitIsDND(unit) then
			return 'DND'
		end
		return ''
	end
end

-- Retail-only tags
if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
	oUF.Tags.Events['title'] = 'UNIT_NAME_UPDATE INSTANCE_ENCOUNTER_ENGAGE_UNIT'
	oUF.Tags.Methods['title'] = function(unit)
		if UnitIsPlayer(unit) then
			return GetTitleName(GetCurrentTitle())
		end
	end

	oUF.Tags.Events['specialization'] = 'PLAYER_TALENT_UPDATE'
	oUF.Tags.Methods['specialization'] = function(unit)
		if UnitIsPlayer(unit) then
			local currentSpec = GetSpecialization()
			if currentSpec then
				local _, currentSpecName = GetSpecializationInfo(currentSpec)
				if currentSpecName then
					return currentSpecName
				end
			end
		end
	end
end

-- Health deficit tag: shows missing health as negative abbreviated value (e.g., "-15K")
-- Returns empty at full health. Uses red color (no comparison of secret values possible)
oUF.Tags.Events['SUIHealthDeficit'] = 'UNIT_HEALTH UNIT_MAXHEALTH'
oUF.Tags.Methods['SUIHealthDeficit'] = function(unit)
	if not unit or UnitIsDeadOrGhost(unit) then
		return ''
	end
	local missing = UnitHealthMissing(unit)
	-- Hide when at full health (missing == 0)
	local truncated = C_StringUtil.TruncateWhenZero(missing)
	if not truncated then
		return ''
	end
	-- Secret values cannot be compared, so use a fixed color
	return '|cffff4444-' .. AbbreviateNumbers(missing) .. '|r'
end

--[[ WoW 12.0 UPDATED: Custom health/power tags rebuilt using secret-safe APIs

     OLD APPROACH (Broken in 12.0):
     - Performed arithmetic on UnitHealth/UnitPower secret values
     - Used division/multiplication for percentages and abbreviations

     NEW APPROACH (12.0 Compatible):
     - Uses AbbreviateNumbers() for K/M/B formatting (secret-safe)
     - Uses UnitHealthMissing() instead of subtraction (secret-safe)
     - Uses UnitHealthPercent() for percentage display (secret-safe)
     - Uses BreakUpLargeNumbers() for comma formatting (secret-safe)

     SUPPORTED OPTIONS:
     ✅ displayDead - Show "Dead" when unit is dead
     ✅ hideDead - Hide output when unit is dead
     ✅ hideZero - Hide when value is 0
     ✅ short/dynamic - K/M/B abbreviations (e.g., "1.2K", "45M")
     ✅ percentage - Show as percentage (e.g., "75")
     ✅ missing - Show missing health/power
     ✅ max - Show max health/power
     ✅ plain - No formatting, raw value
     ✅ comma/formatted - Comma-separated (e.g., "1,234,567") - DEFAULT if no format specified
     ❌ hideMax - REMOVED (requires comparing secrets - impossible in 12.0)

     See: https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes#Secret_values
--]]

---Formats health/power values using WoW 12.0 secret-safe APIs
---@param unit string Unit token
---@param _ any Unused realUnit parameter
---@param ... string Options: displayDead, hideDead, hideZero, short, dynamic, percentage, missing, max
---@return string|nil Formatted value or nil to hide
local function SUIHealth(unit, _, ...)
	if not UnitExists(unit) then
		return ''
	end
	local isDead = UnitIsDeadOrGhost(unit)

	-- Handle dead state first
	for i = 1, select('#', ...) do
		local var = tostring(select(i, ...))
		if var == 'hideDead' and isDead then
			return '' -- Hide when dead
		elseif var == 'displayDead' and isDead then
			return 'Dead' -- Show "Dead" text
		end
	end

	-- Check if percentage format requested
	local wantsPercentage = false
	for i = 1, select('#', ...) do
		if tostring(select(i, ...)) == 'percentage' then
			wantsPercentage = true
			break
		end
	end

	-- Handle percentage display (uses secret-safe UnitHealthPercent)
	if wantsPercentage then
		local percent = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
		-- Check hideZero
		for i = 1, select('#', ...) do
			if tostring(select(i, ...)) == 'hideZero' then
				local truncated = C_StringUtil.TruncateWhenZero(percent)
				if not truncated then
					return ''
				end
				break
			end
		end
		return string.format('%d', percent)
	end

	-- Determine which value to display (current, missing, or max)
	local value
	for i = 1, select('#', ...) do
		local var = tostring(select(i, ...))
		if var == 'missing' then
			value = UnitHealthMissing(unit) -- Secret-safe subtraction
		elseif var == 'max' then
			value = UnitHealthMax(unit)
		end
	end

	-- Default to current health if no specific value requested
	if not value then
		value = UnitHealth(unit)
	end

	-- Check hideZero option
	for i = 1, select('#', ...) do
		if tostring(select(i, ...)) == 'hideZero' then
			local truncated = C_StringUtil.TruncateWhenZero(value)
			if not truncated then
				return ''
			end
			break
		end
	end

	-- Format the value based on options
	for i = 1, select('#', ...) do
		local var = tostring(select(i, ...))
		if var == 'short' or var == 'dynamic' then
			return AbbreviateNumbers(value) -- Secret-safe abbreviation (1.2K, 45M, etc)
		elseif var == 'plain' then
			return tostring(value) -- Plain, unformatted value
		elseif var == 'comma' or var == 'formatted' then
			return BreakUpLargeNumbers(value) -- Comma-separated (1,234,567)
		end
	end

	-- Default: comma formatting
	return BreakUpLargeNumbers(value)
end

---Formats power values using WoW 12.0 secret-safe APIs
---@param unit string Unit token
---@param _ any Unused realUnit parameter
---@param ... string Options: displayDead, hideDead, hideZero, short, dynamic, percentage, missing, max
---@return string|nil Formatted value or nil to hide
local function SUIPower(unit, _, ...)
	-- Return empty if no options provided or unit doesn't exist (compound tokens in PvP)
	if not ... or not UnitExists(unit) then
		return ''
	end

	local isDead = UnitIsDeadOrGhost(unit)

	-- Handle dead state first
	for i = 1, select('#', ...) do
		local var = tostring(select(i, ...))
		if var == 'hideDead' and isDead then
			return '' -- Hide when dead
		elseif var == 'displayDead' and isDead then
			return 'Dead' -- Show "Dead" text
		end
	end

	-- Check if percentage format requested
	local wantsPercentage = false
	for i = 1, select('#', ...) do
		if tostring(select(i, ...)) == 'percentage' then
			wantsPercentage = true
			break
		end
	end

	-- Handle percentage display (uses secret-safe UnitPowerPercent)
	if wantsPercentage then
		local percent = UnitPowerPercent(unit, nil, true, CurveConstants.ScaleTo100)
		-- Check hideZero
		for i = 1, select('#', ...) do
			if tostring(select(i, ...)) == 'hideZero' then
				local truncated = C_StringUtil.TruncateWhenZero(percent)
				if not truncated then
					return ''
				end
				break
			end
		end
		return string.format('%d', percent)
	end

	-- Determine which value to display (current, missing, or max)
	local value
	for i = 1, select('#', ...) do
		local var = tostring(select(i, ...))
		if var == 'missing' then
			value = UnitPowerMissing(unit) -- Secret-safe subtraction
		elseif var == 'max' then
			value = UnitPowerMax(unit)
		end
	end

	-- Default to current power if no specific value requested
	if not value then
		value = UnitPower(unit)
	end

	-- Check hideZero option
	for i = 1, select('#', ...) do
		if tostring(select(i, ...)) == 'hideZero' then
			local truncated = C_StringUtil.TruncateWhenZero(value)
			if not truncated then
				return ''
			end
			break
		end
	end

	-- Format the value based on options
	for i = 1, select('#', ...) do
		local var = tostring(select(i, ...))
		if var == 'short' or var == 'dynamic' then
			return AbbreviateNumbers(value) -- Secret-safe abbreviation (1.2K, 45M, etc)
		elseif var == 'plain' then
			return tostring(value) -- Plain, unformatted value
		elseif var == 'comma' or var == 'formatted' then
			return BreakUpLargeNumbers(value) -- Comma-separated (1,234,567)
		end
	end

	-- Default: comma formatting
	return BreakUpLargeNumbers(value)
end

-- Register the custom tags with oUF
oUF.Tags.Events['SUIHealth'] = 'UNIT_HEALTH UNIT_MAXHEALTH'
oUF.Tags.Methods['SUIHealth'] = SUIHealth

oUF.Tags.Events['SUIPower'] = 'UNIT_MAXPOWER UNIT_POWER_UPDATE'
oUF.Tags.Methods['SUIPower'] = SUIPower

-- LEGACY Health Formatting Tags (for backwards compatibility)
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
		oUF.Tags.Events[k] = 'UNIT_HEALTH UNIT_MAXHEALTH'
		oUF.Tags.Methods[k] = function(unit)
			return SUIHealth(unit, nil, unpack(v or {}))
		end
	end
end

-- LEGACY Power Formatting Tags (for backwards compatibility)
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
		oUF.Tags.Events[k] = 'UNIT_MAXPOWER UNIT_DISPLAYPOWER UNIT_POWER_FREQUENT'
		oUF.Tags.Methods[k] = function(unit)
			return SUIPower(unit, nil, unpack(v))
		end
	end
end

-- Color name by Class
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

	oUF.Tags.Events['SUI_ColorClass'] = 'UNIT_HEALTH UNIT_MAXHEALTH'
	oUF.Tags.Methods['SUI_ColorClass'] = function(u)
		local _, class = UnitClass(u)

		if u == 'pet' then
			return hex(oUF.colors.class[class])
		elseif UnitIsPlayer(u) then
			return hex(oUF.colors.class[class])
		else
			return hex(1, 1, 1)
		end
	end
end
