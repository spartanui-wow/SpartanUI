---@class SUI.UF
local UF = SUI.UF
local Auras = {}
UF.MonitoredBuffs = {}

-- WoW 12.0.1 Aura Filter Constants
-- Complete list of all 14 WoW aura filter keywords for IsAuraFilteredOutByInstanceID
Auras.FILTER_TYPES = {
	-- Basic filters
	HELPFUL = 'HELPFUL',
	HARMFUL = 'HARMFUL',

	-- Targeting filters
	PLAYER = 'PLAYER',
	RAID = 'RAID',
	RAID_IN_COMBAT = 'RAID_IN_COMBAT', -- Combat-relevant auras (HoTs, major CDs)
	RAID_PLAYER_DISPELLABLE = 'RAID_PLAYER_DISPELLABLE',

	-- Defensive/offensive filters
	EXTERNAL_DEFENSIVE = 'EXTERNAL_DEFENSIVE', -- External saves (Guardian Spirit, Pain Suppression, etc.)
	BIG_DEFENSIVE = 'BIG_DEFENSIVE', -- Major personal defensives
	CROWD_CONTROL = 'CROWD_CONTROL', -- Stuns, roots, silences, etc.

	-- Action filters
	CANCELABLE = 'CANCELABLE',
	NOT_CANCELABLE = 'NOT_CANCELABLE',

	-- Special filters
	INCLUDE_NAME_PLATE_ONLY = 'INCLUDE_NAME_PLATE_ONLY',
	MAW = 'MAW', -- Shadowlands Maw powers
	IMPORTANT = 'IMPORTANT', -- Blizzard-flagged important auras
}

-- Preset filter combinations (common patterns)
Auras.FILTER_PRESETS = {
	-- Buff presets
	all_buffs = 'HELPFUL',
	player_buffs = 'HELPFUL|PLAYER',
	raid_buffs = 'HELPFUL|RAID',
	healing_mode = 'HELPFUL|PLAYER|RAID_IN_COMBAT',
	external_defensives = 'HELPFUL|EXTERNAL_DEFENSIVE',
	big_defensives = 'HELPFUL|BIG_DEFENSIVE',
	important_buffs = 'HELPFUL|IMPORTANT',

	-- Debuff presets
	all_debuffs = 'HARMFUL',
	player_debuffs = 'HARMFUL|PLAYER',
	raid_debuffs = 'HARMFUL|RAID',
	dispellable = 'RAID_PLAYER_DISPELLABLE',
	crowd_control = 'HARMFUL|CROWD_CONTROL',
	important_debuffs = 'HARMFUL|IMPORTANT',

	-- Nameplate-specific
	nameplate_only = 'INCLUDE_NAME_PLATE_ONLY',
}

-- Track which auras we've already logged to avoid spam
local loggedAuras = {}
local loggedAurasCount = 0
local MAX_LOGGED_AURAS = 100 -- Clear cache after this many entries to prevent memory leak

-- Diagnostic function to log whether aura properties are secret values
-- Logs once per unique aura (by auraInstanceID) to avoid spam
-- ALWAYS ON for debugging - logs to /logs via UF:debug
---@param data UnitAuraInfo
---@param unit UnitId
local function LogAuraSecretStatus(data, unit)
	if not SUI.IsRetail then
		return -- Only relevant for Retail
	end

	if not data then
		return
	end

	-- Get a unique key for this aura - auraInstanceID is always safe
	local auraKey = data.auraInstanceID
	if not auraKey then
		return -- No way to track uniqueness
	end

	-- Check if we already logged this aura
	if loggedAuras[auraKey] then
		return
	end

	-- Mark as logged
	loggedAuras[auraKey] = true
	loggedAurasCount = loggedAurasCount + 1

	-- Clear cache if it gets too large
	if loggedAurasCount > MAX_LOGGED_AURAS then
		loggedAuras = {}
		loggedAurasCount = 0
	end

	-- List of properties to check
	local propertiesToCheck = {
		'auraInstanceID',
		'name',
		'icon',
		'applications',
		'dispelName',
		'duration',
		'expirationTime',
		'sourceUnit',
		'isStealable',
		'nameplateShowPersonal',
		'spellId',
		'canApplyAura',
		'isBossAura',
		'isFromPlayerOrPlayerPet',
		'nameplateShowAll',
		'timeMod',
		'points',
		'isHarmful',
		'isHelpful',
		'isRaid',
		'isNameplateOnly',
		-- oUF-created properties (should always be safe)
		'isPlayerAura',
		'isHarmfulAura',
	}

	UF:debug('=== Secret Value Check for aura ID: ' .. tostring(auraKey) .. ' on ' .. tostring(unit) .. ' ===')

	for _, prop in ipairs(propertiesToCheck) do
		local value = data[prop]
		local isSecret = false
		local safeForDisplay = 'nil'

		if value ~= nil then
			-- Check if it's a secret value
			if issecretvalue and issecretvalue(value) then
				isSecret = true
				safeForDisplay = '<SECRET>'
			else
				-- Safe to display - convert to string
				if type(value) == 'table' then
					safeForDisplay = 'table[' .. #value .. ']'
				elseif type(value) == 'boolean' then
					safeForDisplay = value and 'true' or 'false'
				else
					safeForDisplay = tostring(value)
				end
			end
		end

		local status = isSecret and 'SECRET' or 'safe'
		UF:debug('  ' .. prop .. ': ' .. status .. ' = ' .. safeForDisplay)
	end

	UF:debug('=== End Secret Value Check ===')
end

-- Export for use in other modules
Auras.LogAuraSecretStatus = LogAuraSecretStatus

-- RETAIL FILTER: Uses only Blizzard-safe APIs and oUF-safe properties.
-- No access to secret values (name, spellId, duration, dispelName, sourceUnit, etc.)
---@param element any
---@param unit UnitId
---@param data UnitAuraInfo
---@param config SUI.UF.Auras.RetailConfig
---@return boolean
function Auras:FilterRetail(element, unit, data, config)
	local filterMode = config and config.filterMode or 'blizzard_default'
	local customFilter = config and config.customFilter
	local auraInstanceID = data.auraInstanceID

	if not auraInstanceID then
		return false
	end

	-- Custom filter string takes priority over preset
	if customFilter and customFilter ~= '' then
		return not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, customFilter)
	end

	-- blizzard_default is context-dependent: player sees all, others get RAID filter
	if filterMode == 'blizzard_default' then
		if UnitIsUnit(unit, 'player') then
			return true
		end
		local baseFilter = element.__owner.Buffs and 'HELPFUL' or 'HARMFUL'
		return not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, baseFilter .. '|RAID')
	end

	-- Look up filter string from FILTER_PRESETS
	local filterString = self.FILTER_PRESETS[filterMode]
	if filterString then
		return not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, filterString)
	end

	-- Unknown filterMode - show all
	return true
end

-- CLASSIC FILTER: Full access to all aura properties.
-- Supports duration rules, whitelist/blacklist, spell-specific matching, displayReasons tracking.
---@param element any
---@param unit UnitId
---@param data UnitAuraInfo
---@param config SUI.UF.Auras.ClassicConfig
---@return boolean
function Auras:FilterClassic(element, unit, data, config)
	local rules = config and config.rules or {}
	local spellIdNum = data.spellId and tonumber(data.spellId)

	---@param msg any
	local function debug(msg)
		if not UF.MonitoredBuffs[unit] then
			UF.MonitoredBuffs[unit] = {}
		end

		if spellIdNum and SUI:IsInTable(UF.MonitoredBuffs[unit], spellIdNum) and UF.Log then
			UF.Log.debug('[UF.Auras] ' .. tostring(msg))
		end
	end
	local ShouldDisplay = false
	-- Use string key for consistent lookup (ALT+click uses tostring)
	local spellKey = tostring(data.spellId)
	element.displayReasons[spellKey] = {}

	local function AddDisplayReason(reason)
		debug('Adding display reason ' .. reason)
		element.displayReasons[spellKey][reason] = true
		ShouldDisplay = true
	end

	debug('----')
	debug(data.spellId)

	-- EXCLUSIVE: If showPlayers is enabled, ONLY show player-cast buffs
	-- This check must happen BEFORE other rules that might set ShouldDisplay = true
	if rules.showPlayers and data.sourceUnit ~= 'player' then
		debug('showPlayers enabled but sourceUnit is not player, rejecting')
		return false
	end

	-- Check whitelist/blacklist from config (not from rules)
	local whitelist = config.whitelist or {}
	local blacklist = config.blacklist or {}
	if whitelist[data.spellId] then
		AddDisplayReason('whitelist')
		return true
	end
	if blacklist[data.spellId] then
		debug('Blacklisted')
		return false
	end

	for k, v in pairs(rules) do
		if data[k] then
			if type(v) == 'table' then
				if SUI:IsInTable(v, data[k]) then
					if v[data[k]] then
						debug('Force show per rules')
						AddDisplayReason(k)
					else
						debug('Force hide per rules')
						return false
					end
				end
			elseif type(v) == 'boolean' then
				if v and v == data[k] then
					debug(k .. ' Not equal')
					AddDisplayReason(k)
				end
			end
		else
			if k == 'isMount' and v then
				if UF.MountIds[data.spellId] then
					AddDisplayReason(k)
					return true
				end
			elseif k == 'showPlayers' then
				if v == true and data.sourceUnit == 'player' then
					debug('Is casted by the player')
					AddDisplayReason(k)
					ShouldDisplay = true
				end
			end
		end
	end

	if rules.duration and rules.duration.enabled then
		local moreThanMax = data.duration > rules.duration.maxTime
		local lessThanMin = data.duration < rules.duration.minTime
		debug('Durration is ' .. data.duration)
		debug('Is More than ' .. rules.duration.maxTime .. ' = ' .. (moreThanMax and 'true' or 'false'))
		debug('Is Less than ' .. rules.duration.minTime .. ' = ' .. (lessThanMin and 'true' or 'false'))
		if ShouldDisplay and (not lessThanMin and not moreThanMax) and rules.duration.mode == 'include' then
			AddDisplayReason('duration')
		elseif ShouldDisplay and (lessThanMin or moreThanMax) and rules.duration.mode == 'exclude' then
			AddDisplayReason('duration')
		else
			debug('Durration check Failed, ShouldDisplay is now false')
			ShouldDisplay = false
		end
	else
		debug('Durration is not enabled')
	end
	debug('ShouldDisplay result ' .. (ShouldDisplay and 'true' or 'false'))
	debug('----')
	-- WoW 12.0.0: Use numeric value for table operations
	if spellIdNum and SUI:IsInTable(UF.MonitoredBuffs[unit], spellIdNum) then
		for i, v in ipairs(UF.MonitoredBuffs[unit]) do
			if v == spellIdNum then
				debug('Removed ' .. data.spellId .. ' from the list of monitored buffs for ' .. unit)
				table.remove(UF.MonitoredBuffs[unit], i)
				if UF.Log then
					UF.Log.debug('[UF.Auras] ----')
				end
			end
		end
	end

	return ShouldDisplay
end

-- Thin dispatcher: reads version-specific config from element.DB and calls the right filter
---@param element any
---@param unit UnitId
---@param data UnitAuraInfo
function Auras:Filter(element, unit, data)
	if not SUI.BlizzAPI.canaccesstable(data) then
		return true
	end

	if SUI.IsRetail then
		local config = element.DB and element.DB.retail or { filterMode = 'blizzard_default' }
		return self:FilterRetail(element, unit, data, config)
	else
		local config = element.DB and element.DB.classic or { rules = element.DB and element.DB.rules or {} }
		return self:FilterClassic(element, unit, data, config)
	end
end

-- Priority tiers for aura sorting (higher = more important, shown first)
-- These are base priorities that get applied based on aura properties
local PRIORITY_BOSS = 100 -- Boss auras are highest priority
local PRIORITY_DISPELLABLE = 80 -- Dispellable debuffs (for healers)
local PRIORITY_PLAYER = 60 -- Player-cast auras
local PRIORITY_STEALABLE = 50 -- Stealable buffs (for offensive dispel)
local PRIORITY_RAID = 40 -- Raid-marked auras
local PRIORITY_OTHER = 20 -- Everything else

-- Helper to safely check if a value is a secret value (Retail WoW 12.0+)
-- Secret values cannot be used in boolean tests, comparisons, or arithmetic
local function IsSafeValue(value)
	-- issecretvalue is a global WoW API function
	if issecretvalue then
		return not issecretvalue(value)
	end
	return true -- Classic doesn't have secret values
end

-- Calculate priority for an aura based on its properties
-- RETAIL: Only uses safe values (isPlayerAura, isHarmfulAura created by oUF, auraInstanceID)
-- CLASSIC: Can use full aura properties
---@param data UnitAuraInfo
---@return number
function Auras:GetAuraPriority(data)
	if not data then
		return 0
	end

	local priority = PRIORITY_OTHER

	if SUI.IsRetail then
		-- RETAIL: Only use properties that oUF has pre-processed as safe
		-- isPlayerAura is safe - created by oUF using C_UnitAuras.IsAuraFilteredOutByInstanceID
		-- isHarmfulAura is safe - created by oUF from filter string
		if data.isPlayerAura then
			priority = PRIORITY_PLAYER
		end
		-- That's all we can safely test in Retail - other properties are secret values
	else
		-- CLASSIC: Full access to all aura properties
		-- Boss auras are highest priority
		if data.isBossAura then
			priority = PRIORITY_BOSS
		-- Player-cast auras
		elseif data.isPlayerAura or data.isFromPlayerOrPlayerPet then
			priority = PRIORITY_PLAYER
		-- Raid-flagged auras
		elseif data.isRaid then
			priority = PRIORITY_RAID
		end

		-- Boost priority for dispellable debuffs (important for healers)
		if data.isHarmfulAura and data.dispelName then
			priority = math.max(priority, PRIORITY_DISPELLABLE)
		end

		-- Boost priority for stealable buffs (important for mages/priests)
		if data.isStealable then
			priority = math.max(priority, PRIORITY_STEALABLE)
		end
	end

	return priority
end

-- Safely get a numeric value from aura data (handles secret values)
-- Returns fallback if value is nil, secret, or causes error
local function SafeGetNumber(data, field, fallback)
	if not data then
		return fallback
	end
	local value = data[field]
	if value == nil then
		return fallback
	end
	-- Check if it's a secret value
	if issecretvalue and issecretvalue(value) then
		return fallback
	end
	return value
end

-- Safely get a string value from aura data (handles secret values)
local function SafeGetString(data, field, fallback)
	if not data then
		return fallback
	end
	local value = data[field]
	if value == nil then
		return fallback
	end
	-- Check if it's a secret value
	if issecretvalue and issecretvalue(value) then
		return fallback
	end
	return value
end

-- Create a sort function for auras based on the specified mode
-- Mode can be: 'priority', 'time', 'name', or nil (default oUF behavior)
-- RETAIL: Limited sorting - duration/name/etc are secret values
-- CLASSIC: Full sorting capabilities available
---@param sortMode string|nil
---@return function|nil
function Auras:CreateSortFunction(sortMode)
	if sortMode == 'priority' then
		return function(a, b)
			local priorityA = Auras:GetAuraPriority(a)
			local priorityB = Auras:GetAuraPriority(b)

			-- Higher priority first
			if priorityA ~= priorityB then
				return priorityA > priorityB
			end

			-- Same priority: player auras first (safe property created by oUF)
			if a.isPlayerAura ~= b.isPlayerAura then
				return a.isPlayerAura == true
			end

			-- Fallback to instance ID for stability (always safe - it's an integer)
			local idA = SafeGetNumber(a, 'auraInstanceID', 0)
			local idB = SafeGetNumber(b, 'auraInstanceID', 0)
			return idA < idB
		end
	elseif sortMode == 'time' then
		return function(a, b)
			if not SUI.IsRetail then
				-- CLASSIC: Can sort by expiration time
				local timeA = SafeGetNumber(a, 'expirationTime', math.huge)
				local timeB = SafeGetNumber(b, 'expirationTime', math.huge)
				-- Shorter time remaining first (more urgent)
				if timeA ~= timeB then
					return timeA < timeB
				end
			end

			-- Player auras first (safe property)
			if a.isPlayerAura ~= b.isPlayerAura then
				return a.isPlayerAura == true
			end

			-- Fallback to instance ID for stability
			local idA = SafeGetNumber(a, 'auraInstanceID', 0)
			local idB = SafeGetNumber(b, 'auraInstanceID', 0)
			return idA < idB
		end
	elseif sortMode == 'name' then
		return function(a, b)
			if not SUI.IsRetail then
				-- CLASSIC: Can sort by name
				local nameA = SafeGetString(a, 'name', '')
				local nameB = SafeGetString(b, 'name', '')
				if nameA ~= nameB then
					return nameA < nameB
				end
			end

			-- Retail: name is secret, fall back to player auras first
			if a.isPlayerAura ~= b.isPlayerAura then
				return a.isPlayerAura == true
			end

			local idA = SafeGetNumber(a, 'auraInstanceID', 0)
			local idB = SafeGetNumber(b, 'auraInstanceID', 0)
			return idA < idB
		end
	end

	-- nil = use default oUF sorting
	return nil
end

-- Format duration for display (handles seconds, minutes, hours)
---@param duration number
---@return string
local function FormatDuration(duration)
	if duration >= 3600 then
		return string.format('%dh', math.floor(duration / 3600))
	elseif duration >= 60 then
		return string.format('%dm', math.floor(duration / 60))
	elseif duration >= 10 then
		return string.format('%d', math.floor(duration))
	else
		return string.format('%.1f', duration)
	end
end

-- OnUpdate handler for duration text
-- RETAIL: Duration text disabled (secret values) - cooldown spiral shows duration instead
-- CLASSIC: Full duration text support
---@param button any
---@param elapsed number
local function DurationOnUpdate(button, elapsed)
	-- Retail doesn't support duration text - oUF's cooldown spiral handles it
	if SUI.IsRetail then
		return
	end

	if not button.expiration or button.expiration == math.huge then
		if button.Duration then
			button.Duration:SetText('')
		end
		return
	end

	button.expiration = button.expiration - elapsed
	if button.expiration <= 0 then
		if button.Duration then
			button.Duration:SetText('')
		end
		return
	end

	if button.Duration and button.showDuration then
		-- Color based on remaining time
		if button.expiration < 5 then
			button.Duration:SetTextColor(1, 0.2, 0.2) -- Red for < 5s
		elseif button.expiration < 30 then
			button.Duration:SetTextColor(1, 1, 0.2) -- Yellow for < 30s
		else
			button.Duration:SetTextColor(1, 1, 1) -- White otherwise
		end
		button.Duration:SetText(FormatDuration(button.expiration))
	end
end

---@param elementName string
---@param button any
function Auras:PostCreateButton(elementName, button)
	-- Register for clicks - oUF doesn't do this by default
	button:RegisterForClicks('AnyUp')
	button:SetScript('OnClick', function()
		Auras:OnClick(button, elementName)
	end)
	--Remove game cooldown text
	button.Cooldown:SetHideCountdownNumbers(true)

	-- Create a parent for aura strings so that they appear over the cooldown widget
	local StringParent = CreateFrame('Frame', nil, button)
	StringParent:SetFrameLevel(button:GetFrameLevel() + 10)
	StringParent:SetAllPoints(button)

	-- Reposition count text
	if button.Count then
		button.Count:SetParent(StringParent)
		button.Count:ClearAllPoints()
		button.Count:SetPoint('BOTTOMRIGHT', button, 2, -2)
		button.Count:SetFont(SUI.Font:GetFont('UnitFrames'), 10, 'OUTLINE')
	end

	-- Create duration text
	local Duration = StringParent:CreateFontString(nil, 'OVERLAY')
	Duration:SetFont(SUI.Font:GetFont('UnitFrames'), 10, 'OUTLINE')
	Duration:SetPoint('CENTER', button, 'CENTER', 0, 0)
	Duration:SetJustifyH('CENTER')
	button.Duration = Duration
	button.showDuration = true -- Default to showing duration

	-- Set up OnUpdate for duration countdown
	button:HookScript('OnUpdate', DurationOnUpdate)
end

local function CreateAddToFilterWindow(button, elementName)
	local AceGUI = SUI.Lib.AceGUI
	local window = AceGUI:Create('Frame') ---@type AceGUIFrame
	window:SetTitle('|cffffffffSpartan|cffe21f1fUI|r Aura filter addition')
	window:SetWidth(500)
	window:SetHeight(400)
	window:EnableResize(false)

	local label = AceGUI:Create('Label') ---@type AceGUILabel
	label:SetText(button.data.name)
	label:SetJustifyH('CENTER')
	label:SetImage(button.data.icon)
	label:SetFont(SUI.Font:GetFont(), 12, 'OUTLINE')
	label:SetParent(window)
	label.frame:SetPoint('TOP', window.content, 'TOP', 0, 0)
	label.frame:Show()
	window.content.SpellLabel = label

	local group = AceGUI:Create('InlineGroup') ---@type AceGUIInlineGroup
	group:SetTitle('Mode')
	group:SetLayout('Flow')
	group:SetWidth(480)
	group:SetParent(window)
	group.frame:Show()
	group.frame:SetPoint('TOP', label.frame, 'BOTTOM', 0, -5)
	window.content.group = group

	--Create 2 checkboxes for the filter type
	local Whitelist = AceGUI:Create('CheckBox') ---@type AceGUICheckBox
	Whitelist:SetLabel('Whitelist')
	Whitelist:SetType('radio')
	Whitelist:SetValue(false)
	group:AddChild(Whitelist)
	local Blacklist = AceGUI:Create('CheckBox') ---@type AceGUICheckBox
	Blacklist:SetLabel('Blacklist')
	Blacklist:SetType('radio')
	Blacklist:SetValue(true)
	group:AddChild(Blacklist)

	--Set Callbacks
	Whitelist:SetCallback('OnValueChanged', function(_, _, value)
		Whitelist:SetValue(value)
		Blacklist:SetValue(not value)
	end)
	Blacklist:SetCallback('OnValueChanged', function(_, _, value)
		Blacklist:SetValue(value)
		Whitelist:SetValue(not value)
	end)

	--UnitFrameListing to add buff to
	local scrollcontainer = AceGUI:Create('SimpleGroup') ---@type AceGUISimpleGroup
	scrollcontainer:SetWidth(480)
	scrollcontainer:SetHeight(200)
	scrollcontainer:SetLayout('Fill')
	scrollcontainer:SetParent(window)
	scrollcontainer.frame:Show()
	scrollcontainer.frame:SetPoint('TOP', group.frame, 'BOTTOM', 0, -5)
	window.content.scrollcontainer = scrollcontainer

	local scroll = AceGUI:Create('ScrollFrame') ---@type AceGUIScrollFrame
	scroll:SetLayout('Flow')
	scrollcontainer:AddChild(scroll)

	window.units = {}
	for name, config in pairs(SUI.UF.Unit:GetFrameList()) do
		local check = AceGUI:Create('CheckBox') ---@type AceGUICheckBox
		check:SetLabel(config.displayName or name)

		if button.unit == name then
			check:SetValue(true)
		end

		scroll:AddChild(check)
		window.units[name] = check
	end

	--Save Button
	local Save = AceGUI:Create('Button') ---@type AceGUIButton
	Save:SetText('Save')
	Save:SetParent(window)
	Save.frame:HookScript('OnClick', function()
		for frameName, check in pairs(window.units) do
			if check:GetValue() then
				local mode = Whitelist:GetValue() and 'whitelist' or 'blacklist'
				-- WoW 12.0.0: Use string key for table index
				local spellKey = tostring(button.data.spellId)

				-- Classic config uses classic sub-table for whitelist/blacklist
				local currentClassic = UF.CurrentSettings[frameName].elements[elementName].classic
				local userClassic = UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements[elementName].classic
				if currentClassic then
					currentClassic[mode] = currentClassic[mode] or {}
					currentClassic[mode][spellKey] = true
				end
				if userClassic then
					userClassic[mode] = userClassic[mode] or {}
					userClassic[mode][spellKey] = true
				end

				UF.Unit[frameName]:ElementUpdate(elementName)
			end
		end

		window:Hide()
	end)
	Save.frame:Show()
	Save.frame:SetPoint('TOP', scrollcontainer.frame, 'BOTTOM', 0, -10)
	window.content.Save = Save

	window.frame.CloseBtn:SetText('Cancel')
end

function Auras:OnClick(button, elementName)
	local keyDown = IsShiftKeyDown() and 'SHIFT' or IsAltKeyDown() and 'ALT' or IsControlKeyDown() and 'CTRL'
	if not keyDown then
		return
	end

	local data = button.data
	-- Fallback: try to get data directly if button.data wasn't set
	if not data and button.filter and button:GetID() then
		local parent = button:GetParent()
		local unit = parent and parent.__owner and parent.__owner.unit
		if unit then
			data = C_UnitAuras.GetAuraDataByIndex(unit, button:GetID(), button.filter)
		end
	end

	if data and keyDown then
		if keyDown == 'CTRL' then
			-- Log aura properties to the logger (use /logs to view)
			if UF.Log then
				UF.Log.info('=== Aura Properties ===')
			end

			-- List of known aura data properties to check
			local propsToCheck = {
				-- oUF-created safe properties
				'auraInstanceID',
				'isPlayerAura',
				'isHarmfulAura',
				-- Standard WoW aura properties (may be secret in Retail for other units' auras)
				'name',
				'icon',
				'applications',
				'dispelName',
				'duration',
				'expirationTime',
				'sourceUnit',
				'isStealable',
				'nameplateShowPersonal',
				'spellId',
				'canApplyAura',
				'isBossAura',
				'isFromPlayerOrPlayerPet',
				'nameplateShowAll',
				'timeMod',
				'isHarmful',
				'isHelpful',
				'isRaid',
				'isNameplateOnly',
			}

			for _, k in ipairs(propsToCheck) do
				local success, result = pcall(function()
					local v = data[k]
					if v == nil then
						return nil
					end
					-- Check if it's a secret value
					if issecretvalue and issecretvalue(v) then
						return '<SECRET>'
					end
					-- Format the value
					if type(v) == 'table' then
						return 'table[' .. #v .. ']'
					elseif type(v) == 'boolean' then
						return v and 'true' or 'false'
					else
						return tostring(v)
					end
				end)

				if success and result then
					if UF.Log then
						UF.Log.info('  ' .. k .. ' = ' .. result)
					end
				elseif not success then
					if UF.Log then
						UF.Log.info('  ' .. k .. ' = <ERROR: ' .. tostring(result) .. '>')
					end
				end
			end

			if UF.Log then
				UF.Log.info('======================')
			end
			SUI:Print('Aura properties logged. Use /logs to view details.')
		elseif keyDown == 'ALT' then
			if not SUI.IsRetail then
				-- Classic: Show display reasons
				local spellKey = tostring(data.spellId)
				local parent = button:GetParent()
				if parent and parent.displayReasons and parent.displayReasons[spellKey] then
					if UF.Log then
						UF.Log.info('Reasons for display (spellId: ' .. spellKey .. '):')
						for k, _ in pairs(parent.displayReasons[spellKey]) do
							UF.Log.info('  ' .. k)
						end
					end
					SUI:Print('Display reasons logged. Use /logs to view details.')
				else
					SUI:Print('No display reasons found for this aura (spellId: ' .. spellKey .. ')')
					if UF.Log then
						UF.Log.info('No display reasons found for spellId: ' .. spellKey)
						UF.Log.info('Parent element: ' .. tostring(parent and parent:GetName() or 'nil'))
						UF.Log.info('displayReasons table exists: ' .. tostring(parent and parent.displayReasons ~= nil))
						-- List all keys in displayReasons if it exists
						if parent and parent.displayReasons then
							local keyCount = 0
							for k, _ in pairs(parent.displayReasons) do
								keyCount = keyCount + 1
								if keyCount <= 5 then
									UF.Log.info('  Known spellKey: ' .. tostring(k))
								end
							end
							UF.Log.info('Total tracked spells: ' .. keyCount)
							-- Check if our spell exists with empty reasons
							if parent.displayReasons[spellKey] then
								local reasonCount = 0
								for _ in pairs(parent.displayReasons[spellKey]) do
									reasonCount = reasonCount + 1
								end
								UF.Log.info('SpellKey exists but with ' .. reasonCount .. ' reasons')
							end
						end
					end
				end
			else
				-- Retail: Show filter mode info
				local parent = button:GetParent()
				local filterMode = parent and parent.DB and parent.DB.retail and parent.DB.retail.filterMode or 'unknown'
				SUI:Print('Retail filter mode: ' .. filterMode)
				if UF.Log then
					UF.Log.info('Retail aura filter check:')
					UF.Log.info('  filterMode = ' .. filterMode)
					UF.Log.info('  isPlayerAura = ' .. tostring(data.isPlayerAura))
					UF.Log.info('  isHarmfulAura = ' .. tostring(data.isHarmfulAura))
				end
			end
		elseif keyDown == 'SHIFT' then
			if not SUI.IsRetail then
				CreateAddToFilterWindow(button, elementName)
			else
				SUI:Print('Whitelist/Blacklist filtering is not available in Retail due to WoW 12.0+ API restrictions.')
			end
		end
	end
end

---@param element any
---@param unit UnitId
---@param button any
---@param index integer
function Auras.PostUpdateAura(element, unit, button, index)
	local auraData = C_UnitAuras.GetAuraDataByIndex(unit, index, button.filter)
	if not auraData then
		-- Clear duration when aura data unavailable
		button.expiration = nil
		if button.Duration then
			button.Duration:SetText('')
		end
		return
	end

	if SUI.IsRetail then
		-- RETAIL (12.0+): duration and expirationTime are SECRET VALUES
		-- Cannot access them for text display - attempting to read causes errors
		-- Duration countdown is shown via cooldown spiral (oUF uses SetCooldownFromDurationObject)
		-- Hide our text duration display in Retail
		button.expiration = nil
		if button.Duration then
			button.Duration:SetText('')
		end

		-- Visual effects - CANNOT safely access isStealable or sourceUnit in Retail
		-- These are secret values and will crash if tested
		-- Only use isPlayerAura (safe, created by oUF) or isHarmfulAura (safe)
		if button.SetBackdrop then
			button:SetBackdropColor(0, 0, 0)
		end
	else
		-- CLASSIC/WRATH/CATA: Full access to aura properties - duration text works!
		local duration, expiration = auraData.duration, auraData.expirationTime
		if duration and expiration and duration > 0 then
			-- Calculate remaining time
			local remaining = expiration - GetTime()
			if remaining > 0 then
				button.expiration = remaining
			else
				button.expiration = nil
			end
		else
			-- No duration (permanent aura) or invalid data
			button.expiration = math.huge
		end

		-- Visual effects for special aura types
		if button.SetBackdrop then
			if unit == 'target' and auraData.isStealable then
				button:SetBackdropColor(0, 1 / 2, 1 / 2)
			elseif auraData.sourceUnit ~= 'player' then
				button:SetBackdropColor(0, 0, 0)
			end
		end
	end
end

UF.Auras = Auras
