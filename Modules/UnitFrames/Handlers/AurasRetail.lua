---@class SUI.UF
local UF = SUI.UF
local L = SUI.L
local Auras = UF.Auras

-- Retail 12.1+ helpers for the group/slot aura system.
--
-- Everything here describes auras to Blizzard rather than inspecting them.
-- No function in this file reads an aura property, so none of it can trip the
-- secret value restrictions that forced the old per-aura filter callbacks.
--
-- VERIFICATION STATUS (2026-08-07): group and slot option names come from
-- oUF's 12.1 rewrite, which exercises them directly.
--
-- candidateFilters keys confirmed in shipping code (ElvUI uses all four
-- against a live client, or shipped by ElvUI as a user-facing option):
-- includeSpellIDs, excludeSpellIDs, includeDispelTypes, maxDuration,
-- canApplyAura, isBossAura, isBossOrRoleAura, isFromPlayerOrPlayerPet,
-- isPriorityAura, isRoleAura, isStealable, nameplateShowAll,
-- nameplateShowPersonal. Only these are trusted when the client exposes no
-- validator, because an unsupported key fails OPEN - the group matches every
-- aura rather than erroring.
--
-- Still unconfirmed, from the PTR notes only: excludeDispelTypes.
--
-- "Only mine" still rides the PLAYER filter token rather than
-- isFromPlayerOrPlayerPet. The token is what splits a container into its
-- player and others halves, so the two have to agree on one mechanism, and
-- ElvUI moved the same way when they dropped isFromPlayerOrPlayerPet from
-- their own ownOnly handling.

-- Number of aura groups offered per frame.
Auras.MAX_GROUPS = 5

-- Number of individually tracked spells offered per frame. Slots cannot be
-- added after the container is built, so this is the hard ceiling.
Auras.MAX_TRACKER_SLOTS = 12

-- Defaults for one tracked spell.
Auras.TRACKER_DEFAULTS = {
	enabled = false,
	name = '',
	spellId = '',
	filter = 'HELPFUL',
	onlyMine = true,
	size = 26,
	showStacks = true,
	showDuration = true,
	showSwipe = true,
	fontSize = 12,
	anchor = 'CENTER',
	x = 0,
	y = 0,
	expiring = {
		enabled = false,
		threshold = 5,
		color = { 1, 0.1, 0.1, 1 },
	},
}

-- Per-group defaults, resolved in code rather than through an AceDB ['**']
-- wildcard. The UserSettings wildcard chain is only six levels deep and is
-- fully consumed by preset/unit/elements/<container>/groups/index, and
-- SUI:MergeData (which builds CurrentSettings) does not expand wildcards at all.
Auras.GROUP_DEFAULTS = {
	enabled = false,
	name = '',
	filterMode = 'all_buffs',
	customFilter = '',
	number = 10,
	perRow = 0,
	size = 24,
	spacing = 2,
	lineSpacing = 2,
	groupSpacing = 4,
	forceNewLine = false,
	sortMethod = 'expiration',
	sortDirection = 'normal',
	fontSize = 12,
	durationText = {
		size = 10,
		outline = 'OUTLINE',
		anchor = 'CENTER',
		x = 0,
		y = 0,
		colorByTime = true,
	},
	stackText = {
		size = 10,
		outline = 'OUTLINE',
		anchor = 'BOTTOMRIGHT',
		x = 2,
		y = -2,
	},
	showCount = true,
	showDuration = true,
	showCooldown = true,
	showDebuffBorder = true,
	showBuffBorder = false,
	dispelBorderStyle = 'border',
	showBuffIndicator = false,
	showDebuffIndicator = false,
	showStealableBorder = false,
	clickThrough = false,
	onlyMine = false,
	onlyStealable = false,
	maxDuration = 0,
	includeSpellIDs = '',
	excludeSpellIDs = '',
	expiring = {
		enabled = false,
		threshold = 5,
		color = { 1, 0.1, 0.1, 1 },
	},
}

---Whether the client provides the native aura container objects.
---@return boolean
function Auras:HasNativeContainers()
	return SUI.IsRetail and C_UnitAuras ~= nil and AuraContainerSortMethod ~= nil
end

---Storage key for a group or tracked spell.
---
---Deliberately a word rather than a number. Numeric-looking string keys such
---as '1' pass through SavedVariables serialisation and several table merges,
---and anything that normalises one to a real number silently breaks the
---lookup - the entry then reads as unconfigured and falls back to defaults.
---@param index number|string
---@return string
function Auras:GetSlotKey(index)
	return 'slot' .. tostring(index)
end

---Read a group's settings with defaults applied.
---Always returns a table, so callers can read any group index without a nil
---check. An unconfigured index simply reads as the defaults.
---@param DB table
---@param index number|string
---@return table
function Auras:ResolveGroup(DB, index)
	local stored = type(DB) == 'table' and DB.groups and DB.groups[self:GetSlotKey(index)]
	local resolved = {}

	for key, value in pairs(self.GROUP_DEFAULTS) do
		if type(value) == 'table' then
			local copy = {}
			for k, v in pairs(value) do
				copy[k] = v
			end
			resolved[key] = copy
		else
			resolved[key] = value
		end
	end

	if stored then
		for key, value in pairs(stored) do
			local default = resolved[key]

			if type(value) == 'table' and type(default) == 'table' then
				for k, v in pairs(value) do
					resolved[key][k] = v
				end
			elseif default == nil or type(value) == type(default) then
				resolved[key] = value
			end
			-- A stored value whose type does not match the default is dropped.
			-- The shared element defaults carry sub-tables (position, text)
			-- that a profile merge can leave inside a group, and handing one to
			-- the aura APIs errors: they expect numbers and strings.
		end
	end

	return resolved
end

----------------------------------------------------------------------------------------------------
-- Filters
----------------------------------------------------------------------------------------------------

-- Filter tokens confirmed working on 12.1. DISPELLABLE and IMPORTANT were
-- restored by Blizzard in PTR 5 after being removed earlier in the 12.0 cycle.
Auras.FILTER_PRESETS_RETAIL = {
	-- Buffs
	all_buffs = 'HELPFUL',
	player_buffs = 'HELPFUL|PLAYER',
	other_buffs = 'HELPFUL|!PLAYER',
	raid_buffs = 'HELPFUL|RAID',
	important_buffs = 'HELPFUL|IMPORTANT',
	healing_mode = 'HELPFUL|RAID_IN_COMBAT',
	external_defensives = 'HELPFUL|EXTERNAL_DEFENSIVE',
	big_defensives = 'HELPFUL|BIG_DEFENSIVE',
	stealable = 'HELPFUL|RAID_PLAYER_DISPELLABLE',
	cancelable_buffs = 'HELPFUL|CANCELABLE',

	-- Debuffs
	all_debuffs = 'HARMFUL',
	player_debuffs = 'HARMFUL|PLAYER',
	other_debuffs = 'HARMFUL|!PLAYER',
	raid_debuffs = 'HARMFUL|RAID',
	important_debuffs = 'HARMFUL|IMPORTANT',
	dispellable = 'HARMFUL|RAID_PLAYER_DISPELLABLE',
	any_dispellable = 'HARMFUL|DISPELLABLE',
	crowd_control = 'HARMFUL|CROWD_CONTROL',
}

-- Human readable names for the filter dropdown.
Auras.FILTER_PRESET_NAMES = {
	all_buffs = L['All buffs'],
	player_buffs = L['Buffs you cast'],
	other_buffs = L['Buffs others cast'],
	raid_buffs = L['Important raid buffs'],
	important_buffs = L['Important buffs'],
	healing_mode = L['Heal-over-time effects'],
	external_defensives = L['Defensives cast on you'],
	big_defensives = L['Major defensives'],
	stealable = L['Stealable buffs'],
	cancelable_buffs = L['Buffs you can cancel'],
	all_debuffs = L['All debuffs'],
	player_debuffs = L['Debuffs you cast'],
	other_debuffs = L['Debuffs others cast'],
	raid_debuffs = L['Important raid debuffs'],
	important_debuffs = L['Important debuffs'],
	dispellable = L['Debuffs you can remove'],
	any_dispellable = L['Any removable debuff'],
	crowd_control = L['Crowd control'],
}

-- Filter modes that no longer exist, mapped to their closest surviving match.
local LEGACY_FILTER_REMAP = {
	blizzard_default = 'all_buffs',
	player_auras = 'player_buffs',
	raid_auras = 'raid_buffs',
	all = 'all_buffs',
}

---Resolve a stored filter mode into a filter string.
---@param filterMode? string
---@return string?
function Auras:GetFilterString(filterMode)
	if not filterMode then
		return
	end

	filterMode = LEGACY_FILTER_REMAP[filterMode] or filterMode
	return self.FILTER_PRESETS_RETAIL[filterMode]
end

-- candidateFilters keys this build of the game actually accepts. Populated on
-- first use by probing Blizzard's validator, so an option we get wrong is
-- dropped loudly in the log instead of quietly matching every aura.
local validCandidateKeys

---Remove candidateFilters keys the running client does not recognise.
---@param filters table
---@return table?
function Auras:ValidateCandidateKeys(filters)
	if not validCandidateKeys then
		validCandidateKeys = {}

		-- Keys ElvUI ships as user-facing options, so they are exercised
		-- against a live client by a large user base. Trusted even when this
		-- client offers no validator.
		local confirmed = {
			includeSpellIDs = true,
			excludeSpellIDs = true,
			includeDispelTypes = true,
			maxDuration = true,
			canApplyAura = true,
			isBossAura = true,
			isBossOrRoleAura = true,
			isFromPlayerOrPlayerPet = true,
			isPriorityAura = true,
			isRoleAura = true,
			isStealable = true,
			nameplateShowAll = true,
			nameplateShowPersonal = true,
		}

		local probe = C_UnitAuras and C_UnitAuras.ValidateCandidateFilters
		for _, key in ipairs({
			'includeSpellIDs',
			'excludeSpellIDs',
			'includeDispelTypes',
			'excludeDispelTypes',
			'maxDuration',
			'canApplyAura',
			'isBossAura',
			'isBossOrRoleAura',
			'isFromPlayerOrPlayerPet',
			'isPriorityAura',
			'isRoleAura',
			'isStealable',
			'nameplateShowAll',
			'nameplateShowPersonal',
		}) do
			if not probe then
				-- Without a validator an unsupported key fails OPEN - the group
				-- matches every aura instead of erroring - so only the confirmed
				-- keys are trusted blind.
				validCandidateKeys[key] = confirmed[key] or nil
			else
				local ok = pcall(probe, { [key] = true })
				validCandidateKeys[key] = ok and true or nil
				if not ok then
					UF:debug('Aura candidate filter not supported by this client: ' .. key)
				end
			end
		end
	end

	local cleaned, used = {}, false
	for key, value in pairs(filters) do
		if validCandidateKeys[key] then
			cleaned[key] = value
			used = true
		end
	end

	if used then
		return cleaned
	end
end

---Build the candidateFilters table from a settings table.
---
---Shared by every aura display so they filter the same way: aura groups, the
---spell tracker and aura bars all describe what they want with the same keys
---rather than each rolling their own.
---
---Recognised settings, all optional:
---  includeSpellIDs / excludeSpellIDs - comma or space separated ID lists
---  maxDuration                       - seconds; also hides permanent auras
---  onlyStealable                     - unconfirmed key, dropped if unsupported
---
---Returns nil when nothing was set, which is what the aura APIs expect for
---"no candidate filtering".
---@param settings table
---@return table?
function Auras:BuildCandidateFilters(settings)
	if type(settings) ~= 'table' then
		return
	end

	local filters = {}
	local used = false

	-- "Only mine" is deliberately not here: it rides the PLAYER filter token,
	-- because isFromPlayerOrPlayerPet is unconfirmed and would fail open.
	if settings.onlyStealable then
		filters.isStealable = true
		used = true
	end

	-- Saved settings can hold a table where a number belongs: every element
	-- inherits the shared element defaults, which carry sub-tables, and a
	-- profile merge can leave one behind under any key. Comparing that errors,
	-- so the type is checked before the value is used.
	if type(settings.maxDuration) == 'number' and settings.maxDuration > 0 then
		filters.maxDuration = settings.maxDuration
		used = true
	end

	local include = self:BuildSpellIDMap(settings.includeSpellIDs)

	-- Showing mounts means allow-listing every mount spell. That is a
	-- restriction, not an addition: a container with an allow list shows only
	-- what is on it, which is why this belongs on its own container rather
	-- than being mixed into one showing everything.
	if settings.showMounts then
		local mounts = UF:BuildMountList()
		if next(mounts) then
			include = include or {}
			for spellID in pairs(mounts) do
				include[spellID] = true
			end
		end
	end

	if include then
		filters.includeSpellIDs = include
		used = true
	end

	local exclude = self:BuildSpellIDMap(settings.excludeSpellIDs)
	if exclude then
		filters.excludeSpellIDs = exclude
		used = true
	end

	if used then
		return self:ValidateCandidateKeys(filters)
	end
end

---Parse a comma or space separated list of spell IDs into the map Blizzard wants.
---@param raw? string
---@return table<number, boolean>?
function Auras:BuildSpellIDMap(raw)
	-- Only a string or number is a spell list. A table would stringify to its
	-- address and scrape digits out of it, inventing spell IDs.
	if type(raw) == 'number' then
		raw = tostring(raw)
	end
	if type(raw) ~= 'string' or raw == '' then
		return
	end

	local map, count = {}, 0
	for id in raw:gmatch('%d+') do
		map[tonumber(id)] = true
		count = count + 1
	end

	if count > 0 then
		return map
	end
end

----------------------------------------------------------------------------------------------------
-- Sorting
----------------------------------------------------------------------------------------------------

---Resolve the dispel border style for an aura button.
---
---The engine draws the dispel-type border itself, which is what brings back
---the old "show aura type" colouring: on the previous system it had to be
---switched off entirely because reading an aura's dispel type errored once
---auras became secret.
---@param style? string Key from GetDispelBorderStyleValues
---@return number|nil
function Auras:GetDispelBorderStyle(style)
	local styles = Enum.CustomAuraButtonDispelTypeTextureStyle
	if not styles then
		return nil
	end

	-- Names are resolved rather than hardcoded so a client missing one of them
	-- falls back to the standard border instead of passing nil.
	local byName = {
		border = styles.Border,
		icon = styles.Icon,
		preserve = styles.PreserveAsset,
	}

	return byName[style] or styles.Border
end

---The dispel border styles available for the options dropdown.
---@return table<string, string>
function Auras:GetDispelBorderStyleValues()
	local styles = Enum.CustomAuraButtonDispelTypeTextureStyle
	if not styles then
		return {}
	end

	local values = {}
	if styles.Border then
		values.border = L['Border']
	end
	if styles.Icon then
		values.icon = L['Corner icon']
	end
	if styles.PreserveAsset then
		values.preserve = L['Texture only']
	end

	return values
end

---@param mode? string
---@return number
function Auras:GetSortMethod(mode)
	local methods = AuraContainerSortMethod
	if not methods then
		return 0
	end

	-- Each entry is nil-tolerant: a build that lacks one of these simply falls
	-- back to sorting by expiration rather than passing nil to AddGroup.
	local lookup = {
		expiration = methods.ExpirationOnly,
		instanceID = methods.AuraInstanceIDOnly,
		name = methods.Name,
		debuffs = methods.UnitFrameDebuff,
		defensive = methods.BigDefensive,
		important = methods.ImportantOnly,
	}

	return lookup[mode] or methods.ExpirationOnly
end

---The sort methods this client actually provides, for the options dropdown.
---@return table<string, string>
function Auras:GetSortMethodValues()
	local methods = AuraContainerSortMethod
	local values = { expiration = L['Time left'] }

	if not methods then
		return values
	end

	if methods.AuraInstanceIDOnly then
		values.instanceID = L['Order the game provides']
	end
	if methods.Name then
		values.name = L['Name']
	end
	if methods.UnitFrameDebuff then
		values.debuffs = L['Debuffs first']
	end
	if methods.BigDefensive then
		values.defensive = L['Major defensives first']
	end
	if methods.ImportantOnly then
		values.important = L['Important first']
	end

	return values
end

---@param direction? string
---@return number
function Auras:GetSortDirection(direction)
	local directions = AuraContainerSortDirection
	if not directions then
		return 0
	end

	if direction == 'reversed' then
		return directions.Reversed
	end

	return directions.Normal
end

----------------------------------------------------------------------------------------------------
-- Duration coloring
----------------------------------------------------------------------------------------------------

---Build a color curve that tints duration text as an aura runs out.
---Replaces the old OnUpdate polling loop; the engine evaluates this against
---the secret expiration time for us.
---@param expiring? table
---@return table?
function Auras:GetDurationColorCurve(expiring)
	if not expiring or not expiring.enabled then
		return
	end
	if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then
		return
	end

	local curve = C_CurveUtil.CreateColorCurve()
	local threshold = expiring.threshold or 5
	local color = expiring.color or { 1, 0.1, 0.1, 1 }

	curve:AddPoint(0, CreateColor(color[1], color[2], color[3], color[4] or 1))
	curve:AddPoint(threshold, CreateColor(1, 1, 1, 1))

	return curve
end

----------------------------------------------------------------------------------------------------
-- Button styling
----------------------------------------------------------------------------------------------------

---Apply SpartanUI styling to a button the container just created.
---Runs inside initializeFrame, the only window where native script methods
---such as SetPoint and SetSize are permitted on an aura button.
---@param button table
---@param groupDB table
---@param element table
---Give an aura button the widgets that make it visible.
---
---This mirrors the library's own button setup. It has to be reproduced rather
---than called because the library only uses its default when no override is
---supplied, and an override is needed to apply SpartanUI's styling.
---
---Runs inside initializeFrame, the only window where native script methods
---such as SetSize are permitted on an aura button.
---@param element table The aura container
---@param options table Group options passed to AddGroup
---@param button table The aura button
function Auras:CreateAuraButton(element, options, button)
	if not button then
		return
	end

	local size = options.size or element.size or 16
	button:SetSize(options.width or element.width or size, options.height or element.height or size)
	button:EnableMouse(not (options.disableMouse or element.disableMouse))

	if not (options.disableCooldown or element.disableCooldown) then
		local cooldown = CreateFrame('Cooldown', '$parentCooldown', button, 'CooldownFrameTemplate')
		cooldown:SetAllPoints()

		-- The cooldown draws its own countdown when the game's cooldown numbers
		-- are switched on. Our own duration text sits on top of it, so one of
		-- the two has to go or every icon shows the time twice.
		if cooldown.SetHideCountdownNumbers then
			cooldown:SetHideCountdownNumbers(true)
		end

		button.Cooldown = cooldown
		button:SetDurationCooldown(cooldown)
	end

	local icon = button:CreateTexture(nil, 'BORDER')
	icon:SetAllPoints()
	button.Icon = icon
	button:SetIcon(icon)

	-- Text sits above the cooldown swipe, so it needs its own frame.
	local textParent = button
	if not (options.disableCooldown or element.disableCooldown) then
		textParent = CreateFrame('Frame', nil, button)
		textParent:SetAllPoints()
		textParent:SetFrameLevel(button.Cooldown:GetFrameLevel() + 1)
	end

	local stackDB = options.stackText or {}
	if options.showCount or element.showCount then
		local count = textParent:CreateFontString(nil, 'OVERLAY', 'NumberFontNormal')
		count:SetPoint(stackDB.anchor or 'BOTTOMRIGHT', stackDB.x or -1, stackDB.y or 0)
		button.Count = count
		button:SetApplicationCount(count, {})
	end

	local durationDB = options.durationText or {}
	if options.showDuration or element.showDuration then
		local time = textParent:CreateFontString(nil, 'OVERLAY', 'NumberFontNormal')
		time:SetPoint(durationDB.anchor or 'CENTER', durationDB.x or 0, durationDB.y or 0)
		button.Time = time
		button:SetDurationText(time, {
			-- Colour by remaining time is the same curve the expiring highlight
			-- uses, so turning it off simply passes no curve.
			textColor = durationDB.colorByTime ~= false and (options.durationColors or element.durationColors) or nil,
		})
	end

	if options.showBuffBorder or options.showDebuffBorder then
		local border = button:CreateTexture(nil, 'OVERLAY')
		border:SetAllPoints()
		button.Border = border
		button:AddDispelTypeTexture(border, {
			style = Auras:GetDispelBorderStyle(options.dispelBorderStyle),
			showWhenHarmful = options.showDebuffBorder,
			showWhenHelpful = options.showBuffBorder,
			customDispelColorMap = element.__owner and element.__owner.colors and element.__owner.colors.dispel,
		})
	end

	if options.showBuffIndicator or options.showDebuffIndicator then
		local indicator = button:CreateTexture(nil, 'OVERLAY', nil, 1)
		indicator:SetPoint('CENTER', button, 'TOPRIGHT')
		indicator:SetSize(18, 18)
		button.DispelIndicator = indicator
		button:AddDispelTypeTexture(indicator, {
			style = Enum.CustomAuraButtonDispelTypeTextureStyle and Enum.CustomAuraButtonDispelTypeTextureStyle.Icon,
			showWhenHarmful = options.showDebuffIndicator,
			showWhenHelpful = options.showBuffIndicator,
		})
	end

	if options.cancelButton then
		button:SetCancelAuraButtons(options.cancelButton)
	end
end

function Auras:StyleButton(button, groupDB, element)
	if not button then
		return
	end

	-- Remember the button so its styling can be redone when settings change.
	-- Buttons accept native calls outside initializeFrame, so restyling a live
	-- one is allowed and avoids making the user reload.
	if element then
		element.styledButtons = element.styledButtons or {}
		element.styledButtons[button] = groupDB
	end

	local durationDB = groupDB.durationText or {}
	local stackDB = groupDB.stackText or {}

	local function apply(fontString, settings)
		if not fontString then
			return
		end

		local size = type(settings.size) == 'number' and settings.size or (type(groupDB.fontSize) == 'number' and groupDB.fontSize or 12)
		local outline = type(settings.outline) == 'string' and settings.outline or 'OUTLINE'
		local font = SUI.Font:GetFontObject(nil, size, outline ~= 'NONE' and outline or nil)
		if font then
			fontString:SetFontObject(font)
		end
	end

	apply(button.Count, stackDB)
	apply(button.Time, durationDB)

	if element and element.PostCreateButton then
		element:PostCreateButton(button, groupDB)
	end
end

---Apply the settings a live button can still take: its size, and where its
---text sits. The container sizes buttons through the group layout, but the
---text is ours and only moves if we move it.
---@param button table
---@param groupDB table
function Auras:StyleButtonWidgets(button, groupDB)
	if not button or type(groupDB) ~= 'table' then
		return
	end

	-- Button size is not set here. The container sizes its own buttons from
	-- the group layout (elementWidth/elementHeight), and setting it again
	-- here leaves the layout positioning buttons at one size while they draw
	-- at another, which overlaps them.
	if button.EnableMouse then
		button:EnableMouse(not groupDB.clickThrough)
	end

	local stackDB = groupDB.stackText or {}
	if button.Count then
		button.Count:ClearAllPoints()
		button.Count:SetPoint(stackDB.anchor or 'BOTTOMRIGHT', stackDB.x or -1, stackDB.y or 0)
	end

	local durationDB = groupDB.durationText or {}
	if button.Time then
		button.Time:ClearAllPoints()
		button.Time:SetPoint(durationDB.anchor or 'CENTER', durationDB.x or 0, durationDB.y or 0)
	end
end

---Re-apply styling to every button a container has already created.
---
---Text size, borders and the rest are applied when a button is built, so a
---settings change would otherwise only show on buttons created afterwards.
---@param element table
---@param DB table
function Auras:RestyleButtons(element, DB)
	if not element or not element.styledButtons then
		return
	end

	-- Rebuild the group lookup so each button is restyled with its own
	-- group's current settings rather than whichever one it started with.
	local byIndex = {}
	for index = 1, self.MAX_GROUPS do
		byIndex[index] = self:ResolveGroup(DB, index)
	end

	-- Collect first: forbidden buttons are dropped from the table below, and
	-- removing entries while iterating it is not safe.
	local stale
	for button, groupDB in pairs(element.styledButtons) do
		if button.IsForbidden and button:IsForbidden() then
			-- Buttons become forbidden while auras are secret; touching one
			-- errors, so it is dropped until it is rebuilt.
			stale = stale or {}
			stale[#stale + 1] = button
		else
			local current = (button.auraGroupIndex and byIndex[button.auraGroupIndex]) or groupDB
			self:StyleButton(button, current, element)
			self:StyleButtonWidgets(button, current)
		end
	end

	for _, button in ipairs(stale or {}) do
		element.styledButtons[button] = nil
	end
end

-- Frames waiting for combat to end before their container is rebuilt.
-- A single watcher drains this; registering PLAYER_REGEN_ENABLED on the UF
-- module itself would replace SpawnFrames' GroupWatcher handler, since
-- AceEvent keys its registry by the calling object.
local pendingRebuilds = {}
local rebuildWatcher

local function DrainPendingRebuilds()
	for frame in pairs(pendingRebuilds) do
		pendingRebuilds[frame] = nil
		for _, name in ipairs({ 'BuffContainer', 'DebuffContainer', 'CustomAuras' }) do
			UF.Elements:Update(frame, name)
		end
	end
end

---Re-point the existing groups at the current settings.
---
---Containers cannot drop groups and oUF never releases a container it created,
---so creating a replacement would leak one container per settings change.
---Instead every group is created once at build time and this repoints the
---live ones, hiding the rest with a filter that matches nothing.
---@param frame table
---@param element table
---@param DB table
---Append an optional token to a filter string.
---
---A value of 1 means "the opposite of this", which the filter syntax spells
---with a leading `!`.
---@param filter string
---@param value? boolean|number
---@param token string
---@return string
function Auras:AddFilter(filter, value, token)
	if value == 1 then
		return filter .. '|!' .. token
	elseif value then
		return filter .. '|' .. token
	end

	return filter
end

---Return the source variant selected by an exact PLAYER filter token.
---Tokens such as RAID_PLAYER_DISPELLABLE describe the player's ability to
---dispel an aura, not who applied it, so substring matching is not valid here.
-- Optional conditions an aura must ALSO meet to be shown.
--
-- Every token in a filter string is an AND, so ticking one always shows fewer
-- auras, never more. Some only ever match helpful auras and some only harmful,
-- so a token is only offered on a container whose base filter can satisfy it -
-- asking for major defensives on a debuff container matches nothing, which
-- reads as the setting being broken.
---@class SUI.UF.Auras.Token
---@field key string Key stored under DB.tokens
---@field token string The filter token the game understands
---@field kind? string 'HELPFUL', 'HARMFUL', or nil for either
---@field name string
---@field desc string
Auras.TOKENS = {
	{
		key = 'raid',
		token = 'RAID',
		name = L['Only important ones'],
		desc = L['Hide everything except the auras the game marks as worth watching in a raid'],
	},
	{
		key = 'raidInCombat',
		token = 'RAID_IN_COMBAT',
		name = L['Only ones that matter in combat'],
		desc = L['Hide auras the game does not consider relevant while fighting'],
	},
	{
		key = 'dispellable',
		token = 'RAID_PLAYER_DISPELLABLE',
		kind = 'HARMFUL',
		name = L['Only what you can dispel'],
		desc = L['Hide debuffs you have no way to remove'],
	},
	{
		key = 'crowdControl',
		token = 'CROWD_CONTROL',
		kind = 'HARMFUL',
		name = L['Only crowd control'],
		desc = L['Hide everything except stuns, roots, fears and the like'],
	},
	{
		key = 'bigDefensive',
		token = 'BIG_DEFENSIVE',
		kind = 'HELPFUL',
		name = L['Only major defensives'],
		desc = L['Hide everything except the big defensive cooldowns'],
	},
	{
		key = 'externalDefensive',
		token = 'EXTERNAL_DEFENSIVE',
		kind = 'HELPFUL',
		name = L['Only defensives cast by someone else'],
		desc = L['Hide everything except protective buffs another player put on this unit'],
	},
	{
		key = 'cancelable',
		token = 'CANCELABLE',
		kind = 'HELPFUL',
		name = L['Only ones you can cancel'],
		desc = L['Hide buffs you cannot right-click off'],
	},
}

---Whether a token can ever match on a container with this base filter.
---
---A token that only marks helpful auras can never be true for a harmful one,
---so offering it would be offering a setting that always shows nothing.
---@param entry SUI.UF.Auras.Token
---@param baseFilter? string
---@return boolean
function Auras:TokenAppliesTo(entry, baseFilter)
	if not entry.kind then
		return true
	end

	return type(baseFilter) == 'string' and baseFilter:find(entry.kind, 1, true) ~= nil
end

---@param filter? string
---@return string? variant 'player' or 'others'
local function GetSourceVariant(filter)
	if type(filter) ~= 'string' then
		return
	end

	for token in filter:gmatch('[^|]+') do
		if token == 'PLAYER' then
			return 'player'
		elseif token == '!PLAYER' then
			return 'others'
		end
	end
end

---Build the filter string for one variant of a container.
---
---A container shows the same kind of aura twice over: the ones you cast and
---the ones everyone else cast. Splitting them means each half can carry its
---own extra tokens, which is how "only show dispellable debuffs from others"
---is expressed without a second container.
---@param DB table
---@param baseFilter string
---@param variant string 'player' or 'others'
---@return string
function Auras:GetVariantFilter(DB, baseFilter, variant)
	-- A custom filter is taken exactly as written. Variant visibility keeps it
	-- on one group so the same filter is never registered twice.
	if type(DB.customFilter) == 'string' and DB.customFilter ~= '' then
		return DB.customFilter
	end

	local base = baseFilter or 'HELPFUL'

	-- A chosen preset replaces the base, since it already says helpful or
	-- harmful. The variant token is still appended so the split holds.
	local preset = self:GetFilterString(DB.filterMode)
	if type(preset) == 'string' and preset ~= '' then
		base = preset
	end

	local filter = base
	if not GetSourceVariant(filter) then
		filter = filter .. (variant == 'others' and '|!PLAYER' or '|PLAYER')
	end

	-- Tokens that cannot match on this container are skipped rather than
	-- appended, so a stale saved setting cannot silently blank the container.
	local tokens = DB.tokens or {}
	for _, entry in ipairs(self.TOKENS) do
		if tokens[entry.key] and self:TokenAppliesTo(entry, base) then
			filter = self:AddFilter(filter, true, entry.token)
		end
	end

	return filter
end

---Whether one of a container's two source variants should be live.
---@param DB table
---@param baseFilter string
---@param variant string 'player' or 'others'
---@return boolean
function Auras:IsVariantEnabled(DB, baseFilter, variant)
	if DB.enabled == false or (variant == 'others' and DB.showOthers == false) then
		return false
	end

	local customFilter = type(DB.customFilter) == 'string' and DB.customFilter ~= '' and DB.customFilter or nil
	if customFilter then
		return variant == (GetSourceVariant(customFilter) or 'player')
	end

	local filter = self:GetFilterString(DB.filterMode) or baseFilter or 'HELPFUL'
	local sourceVariant = GetSourceVariant(filter)
	return sourceVariant == nil or sourceVariant == variant
end

---Attach one group per filter variant. Groups cannot be removed, so this runs
---once per container and later changes are repointed instead.
---@param element table
---@param DB table
---@param baseFilter string
---@param buildSettings fun(element: table, DB: table, variant: string): table
function Auras:AttachVariants(element, DB, baseFilter, buildSettings)
	if element.groupKeys and next(element.groupKeys) then
		self:RepointVariants(element.__owner, element, DB)
		return
	end

	element.groupKeys = {}
	element.buildSettings = buildSettings

	-- Both variants are always created, so turning "others" on later does not
	-- need a container rebuild - the group is simply pointed at a filter that
	-- matches nothing while it is off.
	for _, variant in ipairs({ 'player', 'others' }) do
		local settings = buildSettings(element, DB, variant)
		element.groupKeys[variant] = element:AddGroup(self:GetVariantFilter(DB, baseFilter, variant), settings)
	end

	element.variantSignature = self:GetVariantSignature(DB, baseFilter)
	self:ApplyVariantVisibility(element, DB, baseFilter)
end

---Describe the optional filter tokens in a stable order.
---@param tokens? table
---@return string
local function TokenSignature(tokens)
	if type(tokens) ~= 'table' then
		return ''
	end

	local parts = {}
	for _, entry in ipairs(Auras.TOKENS) do
		parts[#parts + 1] = tostring(tokens[entry.key])
	end

	return table.concat(parts, ',')
end

---Describe everything that decides what the variants show.
---@param DB table
---@param baseFilter string
---@return string
function Auras:GetVariantSignature(DB, baseFilter)
	return table.concat({
		tostring(baseFilter or ''),
		tostring(DB.filterMode or ''),
		tostring(DB.customFilter or ''),
		tostring(DB.showOthers),
		tostring(DB.number or ''),
		tostring(DB.size or ''),
		tostring(DB.spacing or ''),
		tostring(DB.perRow or ''),
		tostring(DB.sortMethod or ''),
		tostring(DB.sortDirection or ''),
		tostring(DB.onlyStealable),
		tostring(DB.maxDuration or ''),
		tostring(DB.showMounts),
		tostring(DB.includeSpellIDs or ''),
		tostring(DB.excludeSpellIDs or ''),
		tostring(DB.position and DB.position.anchor or ''),
		tostring(DB.position and DB.position.x or ''),
		tostring(DB.position and DB.position.y or ''),
		tostring(DB.growthx or ''),
		tostring(DB.growthy or ''),
		-- Tokens change the filter string, so a change here has to repoint the
		-- groups or the setting writes to the database and does nothing.
		TokenSignature(DB.tokens),
	}, ':')
end

---@param element table
---@param DB table
---@return boolean
function Auras:VariantsNeedRepoint(element, DB)
	return element.variantSignature ~= self:GetVariantSignature(DB, element.baseFilter)
end

---Apply the current source-variant visibility without destroying either group.
---@param element table
---@param DB table
---@param baseFilter string
function Auras:ApplyVariantVisibility(element, DB, baseFilter)
	self:ApplyContainerFilters(element, DB, baseFilter)
end

---Point each variant at its filter and set its live icon limit.
---
---A group matches auras whether or not its container is shown, so a disabled
---container would still draw over an enabled one. A zero frame count is the
---native off state; contradictory filter tokens are not a reliable substitute.
---@param element table
---@param DB table
---@param baseFilter string
function Auras:ApplyContainerFilters(element, DB, baseFilter)
	if not element.groupKeys then
		return
	end

	element.variantFrameCounts = element.variantFrameCounts or {}
	local maxFrameCount = type(DB.number) == 'number' and DB.number or 10
	for _, variant in ipairs({ 'player', 'others' }) do
		local key = element.groupKeys[variant]
		if key then
			local enabled = self:IsVariantEnabled(DB, baseFilter, variant)
			if element.SetAuraGroupFilterString then
				element:SetAuraGroupFilterString(key, self:GetVariantFilter(DB, baseFilter, variant))
			end
			if element.SetAuraGroupMaxFrameCount then
				local appliedMax = enabled and maxFrameCount or 0
				element:SetAuraGroupMaxFrameCount(key, appliedMax)
				element.variantFrameCounts[variant] = appliedMax
			end
		end
	end
end

---Re-point a container's variants at the current settings.
---@param frame table
---@param element table
---@param DB table
function Auras:RepointVariants(frame, element, DB)
	frame = frame or element.__owner
	if not frame then
		return
	end

	-- The game's own restriction state, not InCombatLockdown: aura state can
	-- be restricted while out of combat (an encounter, a mythic+ run) and
	-- unrestricted in combat, so a lockdown check gets both cases wrong.
	if SUI.BlizzAPI.IsCombatRestricted() then
		pendingRebuilds[frame] = true

		if not rebuildWatcher then
			rebuildWatcher = CreateFrame('Frame')
			rebuildWatcher:RegisterEvent('PLAYER_REGEN_ENABLED')
			rebuildWatcher:SetScript('OnEvent', DrainPendingRebuilds)
		end
		return
	end

	pendingRebuilds[frame] = nil

	self:PositionContainer(element, frame, DB)

	local baseFilter = element.baseFilter
	for _, variant in ipairs({ 'player', 'others' }) do
		local key = element.groupKeys and element.groupKeys[variant]
		if key then
			if element.SetAuraGroupSortMethod then
				element:SetAuraGroupSortMethod(key, self:GetSortMethod(DB.sortMethod), self:GetSortDirection(DB.sortDirection))
			end
			if element.SetAuraGroupCandidateFilters then
				local candidates = self:BuildCandidateFilters(DB)
				if candidates then
					element:SetAuraGroupCandidateFilters(key, candidates)
				end
			end
			if element.SetAuraGroupLayout then
				local size = type(DB.size) == 'number' and DB.size or 24
				local spacing = type(DB.spacing) == 'number' and DB.spacing or 2
				element:SetAuraGroupLayout(key, {
					elementWidth = size,
					elementHeight = size,
					elementSpacing = spacing,
					lineSpacing = type(DB.lineSpacing) == 'number' and DB.lineSpacing or spacing,
					groupSpacing = type(DB.groupSpacing) == 'number' and DB.groupSpacing or 4,
				})
			end
		end
	end

	self:ApplyContainerFilters(element, DB, baseFilter)
	self:RestyleButtons(element, DB)

	element.variantSignature = self:GetVariantSignature(DB, baseFilter)
	element:SetEnabled(true)
	element:ForceUpdate()
end

----------------------------------------------------------------------------------------------------
-- Container lifecycle
----------------------------------------------------------------------------------------------------

---Produce a signature describing the current group definitions.
---Describe everything about the groups that is baked in at AddGroup time.
---
---A group's options are captured when it is created, so any of these changing
---means the live groups no longer match the settings and have to be repointed.
---Position and growth are included because the container is anchored in the
---same pass.
---@param DB table
---@return string
function Auras:GetGroupSignature(DB)
	local parts = {}

	local position = DB.position or {}
	parts[#parts + 1] = table.concat({
		position.anchor or '',
		tostring(position.x or 0),
		tostring(position.y or 0),
		DB.growthx or '',
		DB.growthy or '',
		tostring(DB.width or ''),
		tostring(DB.layoutLimit or ''),
	}, ':')

	for index = 1, self.MAX_GROUPS do
		local group = self:ResolveGroup(DB, index)
		parts[#parts + 1] = table.concat({
			index,
			tostring(group.enabled),
			group.filterMode or '',
			group.customFilter or '',
			tostring(group.number or ''),
			tostring(group.perRow or ''),
			tostring(group.size or ''),
			tostring(group.spacing or ''),
			tostring(group.onlyMine),
			tostring(group.onlyStealable),
			tostring(group.maxDuration or ''),
			group.includeSpellIDs or '',
			group.excludeSpellIDs or '',
			tostring(group.clickThrough),
			-- These have live setters, so a change is applied by repointing
			-- rather than needing the container rebuilt.
			tostring(group.sortMethod or ''),
			tostring(group.sortDirection or ''),
			tostring(group.lineSpacing or ''),
			tostring(group.groupSpacing or ''),
			tostring(group.forceNewLine),
			-- Button styling is re-applied to live buttons, so these belong
			-- here rather than among the settings that need a rebuild.
			tostring(group.fontSize or ''),
			tostring(group.durationText and group.durationText.size or ''),
			tostring(group.durationText and group.durationText.outline or ''),
			tostring(group.durationText and group.durationText.anchor or ''),
			tostring(group.durationText and group.durationText.x or ''),
			tostring(group.durationText and group.durationText.y or ''),
			tostring(group.stackText and group.stackText.size or ''),
			tostring(group.stackText and group.stackText.outline or ''),
			tostring(group.stackText and group.stackText.anchor or ''),
			tostring(group.stackText and group.stackText.x or ''),
			tostring(group.stackText and group.stackText.y or ''),
		}, ':')
	end

	return table.concat(parts, '|')
end

---@param element table
---@param DB table
---@return boolean
function Auras:GroupsNeedRebuild(element, DB)
	return element.groupSignature ~= self:GetGroupSignature(DB)
end

---Describe only the settings that are frozen when a group is created.
---These cannot be changed on a live group, so a difference here means the
---user has to reload before the change shows up.
---@param DB table
---@return string
function Auras:GetGroupBuildSignature(DB)
	local parts = {}
	for index = 1, self.MAX_GROUPS do
		local group = self:ResolveGroup(DB, index)
		parts[#parts + 1] = table.concat({
			index,
			tostring(group.showCount),
			tostring(group.showDuration),
			tostring(group.showCooldown),
			tostring(group.showBuffBorder),
			tostring(group.showDebuffBorder),
			tostring(group.dispelBorderStyle or ''),
			tostring(group.showBuffIndicator),
			tostring(group.showDebuffIndicator),
			tostring(group.showStealableBorder),
			tostring(group.expiring and group.expiring.enabled),
			tostring(group.expiring and group.expiring.threshold or ''),
		}, ':')
	end

	return table.concat(parts, '|')
end

---Whether any create-time-only group setting changed since the last build.
---@param element table
---@param DB table
---@return boolean
function Auras:GroupBuildOptionsChanged(element, DB)
	-- Nothing to compare against before the first build finishes.
	if not element.groupBuildSignature then
		return false
	end

	return element.groupBuildSignature ~= self:GetGroupBuildSignature(DB)
end

function Auras:RepointGroups(frame, element, DB)
	-- The frame is the key for deferred rebuilds, so it has to be real.
	frame = frame or element.__owner
	if not frame then
		return
	end

	-- The game's own restriction state, not InCombatLockdown: aura state can
	-- be restricted while out of combat (an encounter, a mythic+ run) and
	-- unrestricted in combat, so a lockdown check gets both cases wrong.
	if SUI.BlizzAPI.IsCombatRestricted() then
		pendingRebuilds[frame] = true

		if not rebuildWatcher then
			rebuildWatcher = CreateFrame('Frame')
			rebuildWatcher:RegisterEvent('PLAYER_REGEN_ENABLED')
			rebuildWatcher:SetScript('OnEvent', DrainPendingRebuilds)
		end
		return
	end

	pendingRebuilds[frame] = nil

	-- Re-anchor first: position and growth can change independently of filters.
	self:PositionContainer(element, frame, DB)

	if element.SetAuraGroupFilterString then
		for index = 1, self.MAX_GROUPS do
			local key = element.groupKeys and element.groupKeys[index]
			if key then
				local group = self:ResolveGroup(DB, index)
				element:SetAuraGroupFilterString(key, self:GetGroupFilter(group))

				-- A group's settings are not frozen after all: the container
				-- exposes a setter for each of them, so icon size, count,
				-- sorting and the spell ID lists all change live. Icon size
				-- lives inside the layout table as elementWidth/Height.
				if element.SetAuraGroupMaxFrameCount then
					local maxFrameCount = type(group.number) == 'number' and group.number or 10
					element:SetAuraGroupMaxFrameCount(key, group.enabled and maxFrameCount or 0)
				end

				if element.SetAuraGroupSortMethod then
					element:SetAuraGroupSortMethod(key, self:GetSortMethod(group.sortMethod), self:GetSortDirection(group.sortDirection))
				end

				if element.SetAuraGroupCandidateFilters then
					local candidates = self:BuildCandidateFilters(group)
					if candidates then
						element:SetAuraGroupCandidateFilters(key, candidates)
					end
				end

				if element.SetAuraGroupLayout then
					local size = type(group.size) == 'number' and group.size or 24
					local spacing = type(group.spacing) == 'number' and group.spacing or 2
					element:SetAuraGroupLayout(key, {
						elementWidth = size,
						elementHeight = size,
						elementSpacing = spacing,
						lineSpacing = type(group.lineSpacing) == 'number' and group.lineSpacing or spacing,
						groupSpacing = type(group.groupSpacing) == 'number' and group.groupSpacing or 4,
						forceNewLine = group.forceNewLine,
					})
				end
			end
		end
	else
		-- Older build without runtime filter changes. Record the state anyway so
		-- the element still enables; the change lands on the next reload.
		UF:debug('Aura group filters cannot be changed at runtime on this client')
	end

	-- Buttons already on screen keep the styling they were built with, so
	-- restyle them rather than waiting for the user to reload.
	self:RestyleButtons(element, DB)

	-- Turning a border, timer or stack count on or off decides whether that
	-- widget is built at all, and a button that never had one cannot grow it
	-- later. Everything else now applies live.
	if self:GroupBuildOptionsChanged(element, DB) then
		SUI:Print(L['Turning aura borders and text on or off applies after you reload (/rl)'])
	end
	element.groupBuildSignature = self:GetGroupBuildSignature(DB)

	-- Record what is now live, whether or not the filters could be repointed.
	-- Leaving this stale would make every later update take the rebuild path
	-- and never enable the element.
	element.groupSignature = self:GetGroupSignature(DB)

	element:SetEnabled(true)
	element:ForceUpdate()
end

---The filter string for a group.
---@param group? table
---@return string
function Auras:GetGroupFilter(group)
	if not group or not group.enabled then
		-- Disabled groups are suppressed with maxFrameCount = 0. Keep a valid
		-- filter here so enabling the group later only has to restore its count.
		return 'HELPFUL'
	end

	-- Saved settings can hold a non-string here, so the type is checked before
	-- it reaches AddGroup, which requires a string and errors on anything else.
	if type(group.customFilter) == 'string' and group.customFilter ~= '' then
		return group.customFilter
	end

	local filter = self:GetFilterString(group.filterMode)
	if type(filter) ~= 'string' then
		filter = 'HELPFUL'
	end

	-- "Only mine" rides on the PLAYER filter token rather than the
	-- isFromPlayerOrPlayerPet candidate filter, which is not confirmed on a
	-- live client. An unsupported candidate filter fails open, whereas the
	-- token is part of the filter string and always honoured.
	if group.onlyMine and GetSourceVariant(filter) ~= 'player' then
		filter = filter .. '|PLAYER'
	end

	return filter
end

----------------------------------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------------------------------

-- Anchor points offered wherever something can be placed on a frame.
local anchors = {
	CENTER = L['Center'],
	TOP = L['Top'],
	BOTTOM = L['Bottom'],
	LEFT = L['Left'],
	RIGHT = L['Right'],
	TOPLEFT = L['Top left'],
	TOPRIGHT = L['Top right'],
	BOTTOMLEFT = L['Bottom left'],
	BOTTOMRIGHT = L['Bottom right'],
}

---Sorted list of filter presets for a dropdown.
---@return table<string, string>
function Auras:GetFilterSelectValues()
	local values = {}
	for key in pairs(self.FILTER_PRESETS_RETAIL) do
		values[key] = self.FILTER_PRESET_NAMES[key] or key
	end
	return values
end

---Read one size key straight from the sparse user settings.
---@param frame? table
---@param elementName? string
---@param key string
---@return boolean
local function HasUserSize(frame, elementName, key)
	local unitName = frame and frame.unitOnCreate
	if not unitName or not UF.DB or not UF.DB.UserSettings then
		return false
	end

	local preset = UF:GetPresetForFrame(unitName)
	local settings = UF.DB.UserSettings[preset]
	settings = settings and settings[unitName]
	settings = settings and settings.elements
	settings = settings and settings[elementName or 'BuffContainer']

	return type(settings) == 'table' and type(settings[key]) == 'number'
end

---Whether the user has set a row width for this container.
---
---The merged settings always carry a width, because every element inherits
---one from the shared element defaults, where it means the size of a single
---widget. Only the sparse user table says whether it was actually chosen.
---@param frame? table
---@param elementName? string
---@return boolean
function Auras:HasUserWidth(frame, elementName)
	return HasUserSize(frame, elementName, 'width')
end

---Whether the user has set a height for this container.
---@param frame? table
---@param elementName? string
---@return boolean
function Auras:HasUserHeight(frame, elementName)
	return HasUserSize(frame, elementName, 'height')
end

---Work out how long a row of icons may run before it wraps.
---
---This is a width in pixels, not a count. The flow layout wraps when the next
---icon would cross it, so it decides how many icons sit side by side.
---
---Priority: a width the user set, then icons-per-row translated into a width,
---then the unit frame's own width.
---@param DB table
---@param frame? table
---@param elementName? string
---@return number?
function Auras:GetLayoutLimit(DB, frame, elementName)
	local function number(value, fallback)
		return type(value) == 'number' and value or fallback
	end

	-- A width the user set is them saying where the row ends. It has to be
	-- their own value, not the merged one: every element inherits width and
	-- height from the shared element defaults, where they describe a single
	-- 20x20 widget. A container reads width as the wrap point instead, and
	-- 20px is about one icon, so the inherited default would wrap after every
	-- icon and stack them into a column.
	if self:HasUserWidth(frame, elementName) and type(DB.width) == 'number' and DB.width > 0 then
		return DB.width
	end

	-- Icons per row is the setting people reach for, being the count they can
	-- see, so it is translated into the width that fits exactly that many.
	local perRow = number(DB.perRow, 0)
	if perRow > 0 then
		return perRow * (number(DB.size, 24) + number(DB.spacing, 2))
	end

	-- Otherwise wrap at the frame's width, which keeps the icons over the
	-- frame they belong to.
	if frame and frame.GetWidth then
		local frameWidth = frame:GetWidth()
		if frameWidth and SUI.BlizzAPI.canaccessvalue(frameWidth) and frameWidth > 0 then
			return frameWidth
		end
	end
end

---Anchor an aura container to its unit frame and give it a starting size.
---
---`CreateAuras` only configures the flow layout, which decides how buttons
---flow inside the container. The container is an ordinary child frame and
---still needs a real anchor.
---@param element table
---@param frame table
---@param DB table
function Auras:PositionContainer(element, frame, DB)
	local position = DB.position or {}
	local anchor = position.anchor or 'TOPLEFT'
	local elementName = element.elementName

	local relativeTo = frame
	if position.relativeTo and position.relativeTo ~= 'Frame' and frame[position.relativeTo] then
		relativeTo = frame[position.relativeTo]
	end

	-- Level first: changing it after anchoring has been seen to drop the
	-- container's points, which leaves it unanchored and its icons invisible.
	if frame.raised and frame.raised.GetFrameLevel then
		element:SetFrameLevel(frame.raised:GetFrameLevel() + 1)
	end

	element:ClearAllPoints()
	element:SetPoint(anchor, relativeTo, position.relativePoint or anchor, position.x or 0, position.y or 0)

	-- Where a row wraps is set on the flow layout when the container is built,
	-- so re-apply it here or a width change would resize the container without
	-- moving any icons.
	local limit = self:GetLayoutLimit(DB, frame, elementName)
	if element.SetFlowLayoutMaximumLineSize and limit then
		element:SetFlowLayoutMaximumLineSize(limit)
	end

	-- Containers grow to fit their buttons but need a non-zero starting size,
	-- and it has to match the width the flow layout wraps at: a container
	-- narrower than the row it just laid out clips it back into a column.
	local width = limit or DB.width
	if not width then
		local frameWidth = frame:GetWidth()
		if frameWidth and SUI.BlizzAPI.canaccessvalue(frameWidth) and frameWidth > 0 then
			width = frameWidth
		end
	end

	-- Height covers every row this container can produce. An inherited height
	-- is not a real choice for the same reason an inherited width is not.
	local height = self:HasUserHeight(frame, elementName) and type(DB.height) == 'number' and DB.height > 0 and DB.height or nil
	if not height then
		local size = type(DB.size) == 'number' and DB.size or 24
		local spacing = type(DB.spacing) == 'number' and DB.spacing or 2
		local count = type(DB.number) == 'number' and DB.number or 10
		local perRow = type(DB.perRow) == 'number' and DB.perRow or 0

		local rows = 1
		if perRow > 0 and count > perRow then
			rows = math.ceil(count / perRow)
		end

		height = rows * (size + spacing)
	end

	element:SetSize(width or 100, height)
end

---@return table
function Auras:ResolveEntry(DB, index)
	local resolved = {}

	for key, value in pairs(self.TRACKER_DEFAULTS) do
		if type(value) == 'table' then
			local copy = {}
			for k, v in pairs(value) do
				copy[k] = v
			end
			resolved[key] = copy
		else
			resolved[key] = value
		end
	end

	local stored = type(DB) == 'table' and DB.entries and DB.entries[self:GetSlotKey(index)]
	if stored then
		for key, value in pairs(stored) do
			local default = resolved[key]

			if type(value) == 'table' and type(default) == 'table' then
				for k, v in pairs(value) do
					resolved[key][k] = v
				end
			elseif default == nil or type(value) == type(default) then
				resolved[key] = value
			end
			-- A stored value whose type does not match the default is dropped.
			-- The shared element defaults carry sub-tables (position, text)
			-- that a profile merge can leave inside a group, and handing one to
			-- the aura APIs errors: they expect numbers and strings.
		end
	end

	return resolved
end

---@param element table
function Auras:StyleTrackerButton(button, entry, element)
	if not button then
		return
	end

	local font = SUI.Font:GetFontObject(nil, type(entry.fontSize) == 'number' and entry.fontSize or 12, 'OUTLINE')

	if button.Count and font then
		button.Count:SetFontObject(font)
	end
	if button.Time and font then
		button.Time:SetFontObject(font)
	end
end

---@param frame table
function Auras:ScheduleContainerStateSync(frame)
	if frame.auraStatePending then
		return
	end
	frame.auraStatePending = true

	-- Next frame: after walkObject has enabled every element.
	C_Timer.After(0, function()
		frame.auraStatePending = nil
		self:ApplyContainerEnabledStates(frame)
	end)
end

---@param buildSettings fun(element: table, entry: table): table
function Auras:AttachSlots(element, DB, buildSettings)
	element.slotKeys = element.slotKeys or {}

	for index = 1, self.MAX_TRACKER_SLOTS do
		local entry = self:ResolveEntry(DB, index)
		element.slotKeys[index] = element:AddSlot(self:GetEntryFilter(entry), buildSettings(element, entry))
	end
end

---@param DB table
function Auras:RefreshSlots(element, DB)
	local frame = element.trackerOwner
	if not frame then
		return
	end

	for index = 1, self.MAX_TRACKER_SLOTS do
		local key = element.slotKeys and element.slotKeys[index]
		if key then
			local entry = self:ResolveEntry(DB, index)
			local spellID = entry.enabled and entry.spellId ~= '' and entry.spellId or 0

			-- Slots and groups are separate registries with their own keys, so
			-- the group APIs reject a slot key. Which spell a slot shows is
			-- driven by its candidate filters rather than a filter string.
			if element.SetAuraSlotCandidateFilters then
				element:SetAuraSlotCandidateFilters(
					key,
					self:BuildCandidateFilters({
						includeSpellIDs = spellID,
					})
				)
			end

			-- Slots auto-position relative to each other by default; anchoring
			-- them explicitly is what makes per-spell placement possible.
			-- The accessor name is unconfirmed, so try the slot form first and
			-- fall back to the group one rather than assuming either exists.
			local slot
			if element.GetAuraSlotFrame then
				slot = element:GetAuraSlotFrame(key)
			elseif element.GetAuraGroupFrame then
				slot = element:GetAuraGroupFrame(key)
			end

			if slot and slot.ClearAllPoints then
				slot:ClearAllPoints()
				local anchor = type(entry.anchor) == 'string' and entry.anchor or 'CENTER'
				local offsetX = type(entry.x) == 'number' and entry.x or 0
				local offsetY = type(entry.y) == 'number' and entry.y or 0
				slot:SetPoint(anchor, frame, anchor, offsetX, offsetY)
			end
		end
	end
end

---@return string
function Auras:GetEntryFilter(entry)
	if not entry.enabled or not entry.spellId or entry.spellId == '' then
		-- Candidate spell ID 0 suppresses inactive slots. This remains a valid
		-- base filter so the slot never relies on contradictory filter tokens.
		return 'HELPFUL'
	end

	-- AddSlot requires a string, so a saved non-string is replaced rather than
	-- passed through.
	local filter = entry.filter
	if type(filter) ~= 'string' or filter == '' then
		filter = 'HELPFUL'
	end

	if entry.onlyMine then
		filter = filter .. '|PLAYER'
	end

	return filter
end

---@return table? watcher
function Auras:CreateWatcher(frame, name, filter, candidateFilters, decorate)
	if not self:HasNativeContainers() or not frame.CreateAuras then
		return
	end

	frame.auraWatchers = frame.auraWatchers or {}
	if frame.auraWatchers[name] then
		return frame.auraWatchers[name]
	end

	local container = frame:CreateAuras({ initialAnchor = 'CENTER' })
	container:ClearAllPoints()
	container:SetAllPoints(frame)

	if frame.raised and frame.raised.GetFrameLevel then
		container:SetFrameLevel(frame.raised:GetFrameLevel() + 1)
	end

	local watcher = { frame = frame, container = container, buttons = {} }

	watcher.slotKey = container:AddSlot(filter, {
		maxFrameCount = 1,
		disableMouse = true,
		disableCooldown = true,
		candidateFilters = candidateFilters and self:ValidateCandidateKeys(candidateFilters) or nil,
		initializeFrame = function(button)
			if not button then
				return
			end

			watcher.buttons[#watcher.buttons + 1] = button

			if decorate then
				decorate(button, watcher)
			end
		end,
	})

	self:ScheduleContainerStateSync(frame)
	frame.auraWatchers[name] = watcher

	return watcher
end

---@param frame table
function Auras:ApplyContainerEnabledStates(frame)
	for _, name in ipairs({ 'BuffContainer', 'DebuffContainer', 'CustomAuras', 'AuraTracker' }) do
		local element = frame[name]
		if element and element.SetEnabled then
			local db = element.DB
			element:SetEnabled(db ~= nil and db.enabled == true)
		end
	end
end

---Build the options for one aura container.
---
---A container's settings are flat - it is one filter with one look - so this
---is a single page rather than the nested per-group tree the shared container
---needed.
---@param unitName string
---@param OptionSet AceConfig.OptionsTable
---@param elementName string
---@param displayName string
function Auras:BuildContainerOptions(unitName, OptionSet, elementName, displayName, baseFilter)
	-- These containers only exist on Retail. Building their options anywhere
	-- else adds a full page per frame for an element that can never draw,
	-- which is real work for the options validator and shows the user
	-- settings that do nothing.
	if not self:HasNativeContainers() then
		return
	end

	local function DB()
		return UF.CurrentSettings[unitName].elements[elementName] or {}
	end

	local function Set(key, val)
		local preset = UF:GetPresetForFrame(unitName)
		UF.DB.UserSettings[preset][unitName].elements[elementName][key] = val
		UF.CurrentSettings[unitName].elements[elementName][key] = val

		-- The frame may not be spawned (disabled frame, arena out of arena).
		if UF.Unit[unitName] then
			UF.Unit[unitName]:ElementUpdate(elementName)
		end
	end

	---Write one key inside a nested table, such as `tokens` or `durationText`.
	local function SetSub(key, subKey, val)
		local preset = UF:GetPresetForFrame(unitName)
		local stored = UF.DB.UserSettings[preset][unitName].elements[elementName]
		stored[key] = stored[key] or {}
		stored[key][subKey] = val

		local current = UF.CurrentSettings[unitName].elements[elementName]
		current[key] = current[key] or {}
		current[key][subKey] = val

		if UF.Unit[unitName] then
			UF.Unit[unitName]:ElementUpdate(elementName)
		end
	end

	---Read a setting, falling back when it is missing or the wrong type.
	---
	---A profile merge can leave a sub-table under any key, and handing a table
	---to a range or select widget errors.
	local function Get(key, fallback)
		local value = DB()[key]
		if type(value) ~= type(fallback) then
			return fallback
		end
		return value
	end

	local function SubDB(key)
		local db = DB()
		return type(db[key]) == 'table' and db[key] or {}
	end

	OptionSet.args.display = {
		name = L['Display'],
		type = 'group',
		order = 10,
		inline = true,
		args = {
			number = {
				name = L['Max icons'],
				type = 'range',
				order = 1,
				min = 1,
				max = 40,
				step = 1,
				get = function()
					return Get('number', 16)
				end,
				set = function(_, val)
					Set('number', val)
				end,
			},
			perRow = {
				name = L['Icons per row'],
				desc = L['How many icons sit side by side before starting a new row. Leave at 0 to fit as many as the frame is wide.'],
				type = 'range',
				order = 2,
				min = 0,
				max = 40,
				step = 1,
				get = function()
					return Get('perRow', 0)
				end,
				set = function(_, val)
					Set('perRow', val)
				end,
			},
			size = {
				name = L['Icon size'],
				type = 'range',
				order = 3,
				min = 8,
				max = 64,
				step = 1,
				get = function()
					return Get('size', 24)
				end,
				set = function(_, val)
					Set('size', val)
				end,
			},
			spacing = {
				name = L['Spacing'],
				type = 'range',
				order = 4,
				min = 0,
				max = 20,
				step = 1,
				get = function()
					return Get('spacing', 2)
				end,
				set = function(_, val)
					Set('spacing', val)
				end,
			},
			growthx = {
				name = L['Grow sideways'],
				desc = L['Which way new icons are added across a row'],
				type = 'select',
				order = 5,
				values = {
					RIGHT = L['Right'],
					LEFT = L['Left'],
				},
				get = function()
					return Get('growthx', 'RIGHT')
				end,
				set = function(_, val)
					Set('growthx', val)
				end,
			},
			growthy = {
				name = L['Grow up or down'],
				desc = L['Which way new rows are added'],
				type = 'select',
				order = 6,
				values = {
					UP = L['Up'],
					DOWN = L['Down'],
				},
				get = function()
					return Get('growthy', 'UP')
				end,
				set = function(_, val)
					Set('growthy', val)
				end,
			},
			clickThrough = {
				name = L['Click through'],
				desc = L['Stop these icons taking mouse clicks'],
				type = 'toggle',
				order = 7,
				get = function()
					return DB().clickThrough
				end,
				set = function(_, val)
					Set('clickThrough', val)
				end,
			},
		},
	}

	OptionSet.args.filtering = {
		name = L['What to show'],
		type = 'group',
		order = 20,
		inline = true,
		args = {
			filterMode = {
				name = L['Show'],
				desc = L['Which auras belong in this container'],
				type = 'select',
				order = 1,
				values = function()
					return Auras:GetFilterSelectValues()
				end,
				get = function()
					return DB().filterMode
				end,
				set = function(_, val)
					Set('filterMode', val)
				end,
			},
			showOthers = {
				name = L['Include auras from others'],
				desc = L['Show auras cast by other players as well as your own'],
				type = 'toggle',
				order = 2,
				get = function()
					return DB().showOthers ~= false
				end,
				set = function(_, val)
					Set('showOthers', val)
				end,
			},
			customFilter = {
				name = L['Custom filter'],
				desc = L['Advanced: a filter string used exactly as written, replacing the choice above'],
				type = 'input',
				order = 3,
				width = 'full',
				get = function()
					return Get('customFilter', '')
				end,
				set = function(_, val)
					Set('customFilter', val)
				end,
			},
			showMounts = {
				name = L['Show mounts'],
				desc = L['Show what the unit is riding. This narrows the container to mounts and any spell IDs you list below, so give it a container of its own.'],
				type = 'toggle',
				order = 3.5,
				get = function()
					return DB().showMounts == true
				end,
				set = function(_, val)
					Set('showMounts', val or nil)
				end,
			},
			includeSpellIDs = {
				name = L['Always show these spell IDs'],
				type = 'input',
				order = 4,
				width = 'full',
				get = function()
					return Get('includeSpellIDs', '')
				end,
				set = function(_, val)
					Set('includeSpellIDs', val)
				end,
			},
			excludeSpellIDs = {
				name = L['Never show these spell IDs'],
				type = 'input',
				order = 5,
				width = 'full',
				get = function()
					return Get('excludeSpellIDs', '')
				end,
				set = function(_, val)
					Set('excludeSpellIDs', val)
				end,
			},
			maxDuration = {
				name = L['Longest duration to show'],
				type = 'range',
				order = 6,
				min = 0,
				max = 3600,
				step = 1,
				get = function()
					return Get('maxDuration', 0)
				end,
				set = function(_, val)
					Set('maxDuration', val)
				end,
			},
		},
	}

	-- Optional filter tokens. Every one is an AND, so each ticked box shows
	-- FEWER auras. Only the ones that can match on this container are offered:
	-- a helpful-only token on a debuff container would always show nothing.
	local tokenOptions = {}
	for index, entry in ipairs(Auras.TOKENS) do
		if Auras:TokenAppliesTo(entry, baseFilter) then
			tokenOptions[entry.key] = {
				name = entry.name,
				desc = entry.desc,
				type = 'toggle',
				order = index,
				get = function()
					return SubDB('tokens')[entry.key] == true
				end,
				set = function(_, val)
					SetSub('tokens', entry.key, val or nil)
				end,
			}
		end
	end

	OptionSet.args.tokens = {
		name = L['Show less'],
		desc = L['Each of these hides more auras. They stack, so ticking two shows only what meets both.'],
		hidden = function()
			return not next(tokenOptions)
		end,
		type = 'group',
		order = 30,
		inline = true,
		args = tokenOptions,
	}

	OptionSet.args.sorting = {
		name = L['Sorting'],
		type = 'group',
		order = 40,
		inline = true,
		args = {
			sortMethod = {
				name = L['Sort by'],
				type = 'select',
				order = 1,
				values = function()
					return Auras:GetSortMethodValues()
				end,
				get = function()
					return DB().sortMethod
				end,
				set = function(_, val)
					Set('sortMethod', val)
				end,
			},
			sortDirection = {
				name = L['Sort direction'],
				type = 'select',
				order = 2,
				values = {
					normal = L['Normal'],
					reversed = L['Reversed'],
				},
				get = function()
					return DB().sortDirection
				end,
				set = function(_, val)
					Set('sortDirection', val)
				end,
			},
		},
	}
end

function Auras:BuildTrackerOptions(unitName, OptionSet, maxSlots)
	-- Slots only exist on Retail; see the note in BuildContainerOptions.
	if not self:HasNativeContainers() then
		return
	end

	local function EntryDB(index)
		return Auras:ResolveEntry(UF.CurrentSettings[unitName].elements.AuraTracker, index)
	end

	local function SetEntry(index, key, val)
		local preset = UF:GetPresetForFrame(unitName)
		local stored = UF.DB.UserSettings[preset][unitName].elements.AuraTracker
		stored.entries = stored.entries or {}
		stored.entries[Auras:GetSlotKey(index)] = stored.entries[Auras:GetSlotKey(index)] or {}
		stored.entries[Auras:GetSlotKey(index)][key] = val

		local current = UF.CurrentSettings[unitName].elements.AuraTracker
		current.entries = current.entries or {}
		current.entries[Auras:GetSlotKey(index)] = current.entries[Auras:GetSlotKey(index)] or {}
		current.entries[Auras:GetSlotKey(index)][key] = val

		-- The frame may not be spawned (disabled frame, arena out of arena).
		if UF.Unit[unitName] then
			UF.Unit[unitName]:ElementUpdate('AuraTracker')
		end
	end

	for index = 1, maxSlots do
		OptionSet.args['entry' .. index] = {
			name = function()
				local db = EntryDB(index)
				local label = (db.name ~= '' and db.name) or (db.spellId ~= '' and db.spellId) or (L['Spell'] .. ' ' .. index)
				if not db.enabled then
					label = label .. ' (' .. L['Off'] .. ')'
				end
				return label
			end,
			type = 'group',
			order = 10 + index,
			args = {
				enabled = {
					name = L['Track this spell'],
					type = 'toggle',
					order = 1,
					get = function()
						return EntryDB(index).enabled
					end,
					set = function(_, val)
						SetEntry(index, 'enabled', val)
					end,
				},
				spellId = {
					name = L['Spell ID'],
					desc = L['The spell to watch for. You can find IDs on your spellbook tooltips.'],
					type = 'input',
					order = 2,
					get = function()
						return EntryDB(index).spellId
					end,
					set = function(_, val)
						SetEntry(index, 'spellId', val)
					end,
				},
				name = {
					name = L['Name'],
					desc = L['A label for you, it is not shown on your frames'],
					type = 'input',
					order = 3,
					get = function()
						return EntryDB(index).name
					end,
					set = function(_, val)
						SetEntry(index, 'name', val)
					end,
				},
				filter = {
					name = L['Type'],
					type = 'select',
					order = 4,
					values = {
						HELPFUL = L['Buff'],
						HARMFUL = L['Debuff'],
					},
					get = function()
						return EntryDB(index).filter
					end,
					set = function(_, val)
						SetEntry(index, 'filter', val)
					end,
				},
				onlyMine = {
					name = L['Only mine'],
					desc = L['Only show it when you are the one who cast it'],
					type = 'toggle',
					order = 5,
					get = function()
						return EntryDB(index).onlyMine
					end,
					set = function(_, val)
						SetEntry(index, 'onlyMine', val)
					end,
				},
				size = {
					name = L['Icon size'],
					type = 'range',
					order = 6,
					min = 8,
					max = 64,
					step = 1,
					get = function()
						return EntryDB(index).size
					end,
					set = function(_, val)
						SetEntry(index, 'size', val)
					end,
				},
				anchor = {
					name = L['Position'],
					type = 'select',
					order = 10,
					values = anchors,
					get = function()
						return EntryDB(index).anchor
					end,
					set = function(_, val)
						SetEntry(index, 'anchor', val)
					end,
				},
				x = {
					name = L['X offset'],
					type = 'range',
					order = 11,
					min = -100,
					max = 100,
					step = 1,
					get = function()
						return EntryDB(index).x
					end,
					set = function(_, val)
						SetEntry(index, 'x', val)
					end,
				},
				y = {
					name = L['Y offset'],
					type = 'range',
					order = 12,
					min = -100,
					max = 100,
					step = 1,
					get = function()
						return EntryDB(index).y
					end,
					set = function(_, val)
						SetEntry(index, 'y', val)
					end,
				},
				showStacks = {
					name = L['Show stack count'],
					type = 'toggle',
					order = 20,
					get = function()
						return EntryDB(index).showStacks
					end,
					set = function(_, val)
						SetEntry(index, 'showStacks', val)
					end,
				},
				showDuration = {
					name = L['Show time left'],
					type = 'toggle',
					order = 21,
					get = function()
						return EntryDB(index).showDuration
					end,
					set = function(_, val)
						SetEntry(index, 'showDuration', val)
					end,
				},
				showSwipe = {
					name = L['Show cooldown sweep'],
					type = 'toggle',
					order = 22,
					get = function()
						return EntryDB(index).showSwipe
					end,
					set = function(_, val)
						SetEntry(index, 'showSwipe', val)
					end,
				},
			},
		}
	end
end

---Attach the enabled groups to a container.
---@param element table
---@param DB table
---@param buildOptions fun(element: table, groupDB: table): table
function Auras:AttachGroups(element, DB, buildOptions)
	-- Groups cannot be removed, so attaching twice leaves the first set live
	-- and drawing its own copy of every aura. Whoever calls this again just
	-- wants the current settings applied.
	if element.groupKeys and next(element.groupKeys) then
		self:RepointGroups(element.__owner, element, DB)
		return
	end

	element.groupKeys = element.groupKeys or {}

	-- Every slot is created now, including the ones currently switched off.
	-- Groups cannot be added or removed later, so the only way to make a group
	-- appear without leaking a container is to have built it up front.
	for index = 1, self.MAX_GROUPS do
		local group = self:ResolveGroup(DB, index)
		local options = buildOptions(element, group, index)
		if not group.enabled then
			options.maxFrameCount = 0
		end
		element.groupKeys[index] = element:AddGroup(self:GetGroupFilter(group), options)
	end

	element.groupSignature = self:GetGroupSignature(DB)
	element.groupBuildSignature = self:GetGroupBuildSignature(DB)
end
