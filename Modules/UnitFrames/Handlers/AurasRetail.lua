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
-- against a live client): includeSpellIDs, excludeSpellIDs, includeDispelTypes,
-- maxDuration. Only these are trusted when the client exposes no validator,
-- because an unsupported key fails OPEN - the group matches every aura rather
-- than erroring.
--
-- Still unconfirmed, from the PTR notes only: excludeDispelTypes, isStealable,
-- isRoleAura, isPriorityAura, isFromPlayerOrPlayerPet. "Only mine" therefore
-- appends the PLAYER filter token instead of using isFromPlayerOrPlayerPet.

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
-- fully consumed by preset/unit/elements/AuraGroups/groups/index, and
-- SUI:MergeData (which builds CurrentSettings) does not expand wildcards at all.
Auras.GROUP_DEFAULTS = {
	enabled = false,
	name = '',
	filterMode = 'all_buffs',
	customFilter = '',
	number = 10,
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

		-- Keys confirmed in use against a live 12.1 client (cross-checked with
		-- ElvUI, which ships these). Trusted even when no validator exists.
		local confirmed = {
			includeSpellIDs = true,
			excludeSpellIDs = true,
			includeDispelTypes = true,
			maxDuration = true,
		}

		local probe = C_UnitAuras and C_UnitAuras.ValidateCandidateFilters
		for _, key in ipairs({
			'includeSpellIDs',
			'excludeSpellIDs',
			'includeDispelTypes',
			'excludeDispelTypes',
			'maxDuration',
			'isFromPlayerOrPlayerPet',
			'isStealable',
			'isRoleAura',
			'isPriorityAura',
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

	if settings.maxDuration and settings.maxDuration > 0 then
		filters.maxDuration = settings.maxDuration
		used = true
	end

	local include = self:BuildSpellIDMap(settings.includeSpellIDs)
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
			style = Enum.CustomAuraButtonDispelTypeTextureStyle and Enum.CustomAuraButtonDispelTypeTextureStyle.Border,
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
	}, ':')

	for index = 1, self.MAX_GROUPS do
		local group = self:ResolveGroup(DB, index)
		parts[#parts + 1] = table.concat({
			index,
			tostring(group.enabled),
			group.filterMode or '',
			group.customFilter or '',
			tostring(group.number or ''),
			tostring(group.size or ''),
			tostring(group.spacing or ''),
			tostring(group.onlyMine),
			tostring(group.onlyStealable),
			tostring(group.maxDuration or ''),
			group.includeSpellIDs or '',
			group.excludeSpellIDs or '',
			tostring(group.clickThrough),
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
			tostring(group.number or ''),
			tostring(group.size or ''),
			tostring(group.spacing or ''),
			tostring(group.lineSpacing or ''),
			tostring(group.groupSpacing or ''),
			tostring(group.forceNewLine),
			tostring(group.onlyMine),
			tostring(group.onlyStealable),
			tostring(group.maxDuration or ''),
			group.includeSpellIDs or '',
			group.excludeSpellIDs or '',
			tostring(group.clickThrough),
			tostring(group.sortMethod or ''),
			tostring(group.sortDirection or ''),
			tostring(group.fontSize or ''),
			tostring(group.showCount),
			tostring(group.showDuration),
			tostring(group.showCooldown),
			tostring(group.showBuffBorder),
			tostring(group.showDebuffBorder),
			tostring(group.showBuffIndicator),
			tostring(group.showDebuffIndicator),
			tostring(group.showStealableBorder),
			tostring(group.expiring and group.expiring.enabled),
			tostring(group.expiring and group.expiring.threshold or ''),
			-- Text styling is read when a button is created, so a change only
			-- takes effect on rebuild.
			tostring(group.durationText and group.durationText.size or ''),
			tostring(group.durationText and group.durationText.outline or ''),
			tostring(group.durationText and group.durationText.anchor or ''),
			tostring(group.durationText and group.durationText.colorByTime),
			tostring(group.stackText and group.stackText.size or ''),
			tostring(group.stackText and group.stackText.outline or ''),
			tostring(group.stackText and group.stackText.anchor or ''),
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

-- Frames waiting for combat to end before their container is rebuilt.
-- A single watcher drains this; registering PLAYER_REGEN_ENABLED on the UF
-- module itself would replace SpawnFrames' GroupWatcher handler, since
-- AceEvent keys its registry by the calling object.
local pendingRebuilds = {}
local rebuildWatcher

local function DrainPendingRebuilds()
	for frame in pairs(pendingRebuilds) do
		pendingRebuilds[frame] = nil
		UF.Elements:Update(frame, 'AuraGroups')
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
function Auras:RepointGroups(frame, element, DB)
	if InCombatLockdown() then
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
			end
		end
	else
		-- Older build without runtime filter changes. Record the state anyway so
		-- the element still enables; the change lands on the next reload.
		UF:debug('Aura group filters cannot be changed at runtime on this client')
	end

	-- Icon size, icon count and the spell ID lists are baked into each group
	-- when it is created and there is no API to change them afterwards, so
	-- those only take effect on reload. Say so rather than appearing to ignore
	-- the setting.
	if self:GroupBuildOptionsChanged(element, DB) then
		SUI:Print(L['Icon size and count changes apply after you reload (/rl)'])
	end
	element.groupBuildSignature = self:GetGroupBuildSignature(DB)

	-- Record what is now live, whether or not the filters could be repointed.
	-- Leaving this stale would make every later update take the rebuild path
	-- and never enable the element.
	element.groupSignature = self:GetGroupSignature(DB)

	element:SetEnabled(true)
	element:ForceUpdate()
end

---The filter string for a group, or a never-matching one when it is disabled.
---@param group? table
---@return string
function Auras:GetGroupFilter(group)
	if not group or not group.enabled then
		-- No aura is both helpful and harmful, so this shows nothing.
		return 'HELPFUL|HARMFUL'
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
	if group.onlyMine and not filter:find('PLAYER', 1, true) then
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

---Build the per-group options tree for a frame.
---@param unitName string
---@param OptionSet AceConfig.OptionsTable
---@param maxGroups number
function Auras:BuildGroupOptions(unitName, OptionSet, maxGroups)
	-- Always returns a full table, so an unconfigured group reads as defaults
	-- instead of erroring.
	local function GroupDB(index)
		return Auras:ResolveGroup(UF.CurrentSettings[unitName].elements.AuraGroups, index)
	end

	local function SetGroup(index, key, val)
		local preset = UF:GetPresetForFrame(unitName)
		local stored = UF.DB.UserSettings[preset][unitName].elements.AuraGroups
		stored.groups = stored.groups or {}
		stored.groups[Auras:GetSlotKey(index)] = stored.groups[Auras:GetSlotKey(index)] or {}
		stored.groups[Auras:GetSlotKey(index)][key] = val

		local current = UF.CurrentSettings[unitName].elements.AuraGroups
		current.groups = current.groups or {}
		current.groups[Auras:GetSlotKey(index)] = current.groups[Auras:GetSlotKey(index)] or {}
		current.groups[Auras:GetSlotKey(index)][key] = val

		-- The frame may not be spawned (disabled frame, arena out of arena).
		if UF.Unit[unitName] then
			UF.Unit[unitName]:ElementUpdate('AuraGroups')
		end
	end

	---Write one key inside a nested per-group table, such as `expiring`.
	local function SetGroupSub(index, key, subKey, val)
		local preset = UF:GetPresetForFrame(unitName)
		local stored = UF.DB.UserSettings[preset][unitName].elements.AuraGroups
		stored.groups = stored.groups or {}
		stored.groups[Auras:GetSlotKey(index)] = stored.groups[Auras:GetSlotKey(index)] or {}
		stored.groups[Auras:GetSlotKey(index)][key] = stored.groups[Auras:GetSlotKey(index)][key] or {}
		stored.groups[Auras:GetSlotKey(index)][key][subKey] = val

		local current = UF.CurrentSettings[unitName].elements.AuraGroups
		current.groups = current.groups or {}
		current.groups[Auras:GetSlotKey(index)] = current.groups[Auras:GetSlotKey(index)] or {}
		current.groups[Auras:GetSlotKey(index)][key] = current.groups[Auras:GetSlotKey(index)][key] or {}
		current.groups[Auras:GetSlotKey(index)][key][subKey] = val

		if UF.Unit[unitName] then
			UF.Unit[unitName]:ElementUpdate('AuraGroups')
		end
	end

	for index = 1, maxGroups do
		local groupKey = 'group' .. index

		OptionSet.args[groupKey] = {
			name = function()
				local db = GroupDB(index)
				local label = (db and db.name ~= '' and db.name) or (L['Group'] .. ' ' .. index)
				if db and not db.enabled then
					label = label .. ' (' .. L['Off'] .. ')'
				end
				return label
			end,
			type = 'group',
			order = 10 + index,
			args = {
				enabled = {
					name = L['Show this group'],
					type = 'toggle',
					order = 1,
					get = function()
						return GroupDB(index).enabled
					end,
					set = function(_, val)
						SetGroup(index, 'enabled', val)
					end,
				},
				name = {
					name = L['Name'],
					desc = L['A label for you, it is not shown on your frames'],
					type = 'input',
					order = 2,
					get = function()
						return GroupDB(index).name
					end,
					set = function(_, val)
						SetGroup(index, 'name', val)
					end,
				},
				filterMode = {
					name = L['Show'],
					desc = L['Which auras belong in this group'],
					type = 'select',
					order = 3,
					values = function()
						return Auras:GetFilterSelectValues()
					end,
					get = function()
						return GroupDB(index).filterMode
					end,
					set = function(_, val)
						SetGroup(index, 'filterMode', val)
					end,
				},
				number = {
					name = L['Max icons'],
					type = 'range',
					order = 4,
					min = 1,
					max = 40,
					step = 1,
					get = function()
						return GroupDB(index).number
					end,
					set = function(_, val)
						SetGroup(index, 'number', val)
					end,
				},
				size = {
					name = L['Icon size'],
					type = 'range',
					order = 5,
					min = 8,
					max = 64,
					step = 1,
					get = function()
						return GroupDB(index).size
					end,
					set = function(_, val)
						SetGroup(index, 'size', val)
					end,
				},
				spacing = {
					name = L['Spacing'],
					type = 'range',
					order = 6,
					min = 0,
					max = 20,
					step = 1,
					get = function()
						return GroupDB(index).spacing
					end,
					set = function(_, val)
						SetGroup(index, 'spacing', val)
					end,
				},
				onlyMine = {
					name = L['Only mine'],
					desc = L['Only show auras you cast'],
					type = 'toggle',
					order = 7,
					get = function()
						return GroupDB(index).onlyMine
					end,
					set = function(_, val)
						SetGroup(index, 'onlyMine', val)
					end,
				},
				clickThrough = {
					name = L['Click through'],
					desc = L['Let clicks pass through to the frame behind these icons'],
					type = 'toggle',
					order = 8,
					get = function()
						return GroupDB(index).clickThrough
					end,
					set = function(_, val)
						SetGroup(index, 'clickThrough', val)
					end,
				},
				includeSpellIDs = {
					name = L['Always show these spell IDs'],
					desc = L['Separate each ID with a comma'],
					type = 'input',
					order = 20,
					width = 'full',
					get = function()
						return GroupDB(index).includeSpellIDs
					end,
					set = function(_, val)
						SetGroup(index, 'includeSpellIDs', val)
					end,
				},
				excludeSpellIDs = {
					name = L['Never show these spell IDs'],
					desc = L['Separate each ID with a comma'],
					type = 'input',
					order = 21,
					width = 'full',
					get = function()
						return GroupDB(index).excludeSpellIDs
					end,
					set = function(_, val)
						SetGroup(index, 'excludeSpellIDs', val)
					end,
				},
				customFilter = {
					name = L['Custom filter'],
					desc = L['Advanced. Overrides the Show setting above. Example: HELPFUL|PLAYER'],
					type = 'input',
					order = 30,
					width = 'full',
					get = function()
						return GroupDB(index).customFilter
					end,
					set = function(_, val)
						SetGroup(index, 'customFilter', val)
					end,
				},

				onlyStealable = {
					name = L['Only stealable'],
					desc = L['Only show buffs you could steal or purge. Needs game support that is not confirmed yet.'],
					type = 'toggle',
					order = 9,
					get = function()
						return GroupDB(index).onlyStealable
					end,
					set = function(_, val)
						SetGroup(index, 'onlyStealable', val)
					end,
				},
				maxDuration = {
					name = L['Longest duration to show'],
					desc = L['In seconds. Zero shows auras of any length. Setting any limit also hides permanent auras.'],
					type = 'range',
					order = 22,
					min = 0,
					max = 3600,
					step = 5,
					get = function()
						return GroupDB(index).maxDuration
					end,
					set = function(_, val)
						SetGroup(index, 'maxDuration', val)
					end,
				},

				layout = {
					name = L['Layout'],
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
								return GroupDB(index).sortMethod
							end,
							set = function(_, val)
								SetGroup(index, 'sortMethod', val)
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
								return GroupDB(index).sortDirection
							end,
							set = function(_, val)
								SetGroup(index, 'sortDirection', val)
							end,
						},
						lineSpacing = {
							name = L['Space between rows'],
							type = 'range',
							order = 3,
							min = 0,
							max = 20,
							step = 1,
							get = function()
								return GroupDB(index).lineSpacing
							end,
							set = function(_, val)
								SetGroup(index, 'lineSpacing', val)
							end,
						},
						groupSpacing = {
							name = L['Space before this group'],
							type = 'range',
							order = 4,
							min = 0,
							max = 40,
							step = 1,
							get = function()
								return GroupDB(index).groupSpacing
							end,
							set = function(_, val)
								SetGroup(index, 'groupSpacing', val)
							end,
						},
						forceNewLine = {
							name = L['Start on a new row'],
							desc = L['Begin this group on its own row instead of continuing the previous one'],
							type = 'toggle',
							order = 5,
							get = function()
								return GroupDB(index).forceNewLine
							end,
							set = function(_, val)
								SetGroup(index, 'forceNewLine', val)
							end,
						},
					},
				},

				display = {
					name = L['Icon display'],
					type = 'group',
					order = 50,
					inline = true,
					args = {
						showCount = {
							name = L['Show stack count'],
							type = 'toggle',
							order = 1,
							get = function()
								return GroupDB(index).showCount
							end,
							set = function(_, val)
								SetGroup(index, 'showCount', val)
							end,
						},
						showDuration = {
							name = L['Show time left'],
							type = 'toggle',
							order = 2,
							get = function()
								return GroupDB(index).showDuration
							end,
							set = function(_, val)
								SetGroup(index, 'showDuration', val)
							end,
						},
						showCooldown = {
							name = L['Show cooldown sweep'],
							type = 'toggle',
							order = 3,
							get = function()
								return GroupDB(index).showCooldown
							end,
							set = function(_, val)
								SetGroup(index, 'showCooldown', val)
							end,
						},
						fontSize = {
							name = L['Text size'],
							type = 'range',
							order = 4,
							min = 6,
							max = 24,
							step = 1,
							get = function()
								return GroupDB(index).fontSize
							end,
							set = function(_, val)
								SetGroup(index, 'fontSize', val)
							end,
						},
					},
				},

				borders = {
					name = L['Borders'],
					type = 'group',
					order = 60,
					inline = true,
					args = {
						showDebuffBorder = {
							name = L['Color debuff borders'],
							desc = L['Tint the border by what kind of debuff it is'],
							type = 'toggle',
							order = 1,
							get = function()
								return GroupDB(index).showDebuffBorder
							end,
							set = function(_, val)
								SetGroup(index, 'showDebuffBorder', val)
							end,
						},
						showBuffBorder = {
							name = L['Color buff borders'],
							type = 'toggle',
							order = 2,
							get = function()
								return GroupDB(index).showBuffBorder
							end,
							set = function(_, val)
								SetGroup(index, 'showBuffBorder', val)
							end,
						},
						showDebuffIndicator = {
							name = L['Debuff type icon'],
							desc = L['Show a small icon in the corner for the debuff type'],
							type = 'toggle',
							order = 3,
							get = function()
								return GroupDB(index).showDebuffIndicator
							end,
							set = function(_, val)
								SetGroup(index, 'showDebuffIndicator', val)
							end,
						},
						showBuffIndicator = {
							name = L['Buff type icon'],
							type = 'toggle',
							order = 4,
							get = function()
								return GroupDB(index).showBuffIndicator
							end,
							set = function(_, val)
								SetGroup(index, 'showBuffIndicator', val)
							end,
						},
						showStealableBorder = {
							name = L['Highlight stealable buffs'],
							type = 'toggle',
							order = 5,
							get = function()
								return GroupDB(index).showStealableBorder
							end,
							set = function(_, val)
								SetGroup(index, 'showStealableBorder', val)
							end,
						},
					},
				},

				text = {
					name = L['Text'],
					type = 'group',
					order = 65,
					inline = true,
					args = {
						durationHeader = {
							name = L['Time left'],
							type = 'header',
							order = 1,
						},
						durationSize = {
							name = L['Size'],
							type = 'range',
							order = 2,
							min = 6,
							max = 24,
							step = 1,
							get = function()
								return GroupDB(index).durationText.size
							end,
							set = function(_, val)
								SetGroupSub(index, 'durationText', 'size', val)
							end,
						},
						durationOutline = {
							name = L['Outline'],
							type = 'select',
							order = 3,
							values = { NONE = L['None'], OUTLINE = L['Thin'], THICKOUTLINE = L['Thick'] },
							get = function()
								return GroupDB(index).durationText.outline
							end,
							set = function(_, val)
								SetGroupSub(index, 'durationText', 'outline', val)
							end,
						},
						durationAnchor = {
							name = L['Position'],
							type = 'select',
							order = 4,
							values = anchors,
							get = function()
								return GroupDB(index).durationText.anchor
							end,
							set = function(_, val)
								SetGroupSub(index, 'durationText', 'anchor', val)
							end,
						},
						durationColorByTime = {
							name = L['Color by remaining time'],
							type = 'toggle',
							order = 5,
							get = function()
								return GroupDB(index).durationText.colorByTime
							end,
							set = function(_, val)
								SetGroupSub(index, 'durationText', 'colorByTime', val)
							end,
						},
						stackHeader = {
							name = L['Stack count'],
							type = 'header',
							order = 10,
						},
						stackSize = {
							name = L['Size'],
							type = 'range',
							order = 11,
							min = 6,
							max = 24,
							step = 1,
							get = function()
								return GroupDB(index).stackText.size
							end,
							set = function(_, val)
								SetGroupSub(index, 'stackText', 'size', val)
							end,
						},
						stackOutline = {
							name = L['Outline'],
							type = 'select',
							order = 12,
							values = { NONE = L['None'], OUTLINE = L['Thin'], THICKOUTLINE = L['Thick'] },
							get = function()
								return GroupDB(index).stackText.outline
							end,
							set = function(_, val)
								SetGroupSub(index, 'stackText', 'outline', val)
							end,
						},
						stackAnchor = {
							name = L['Position'],
							type = 'select',
							order = 13,
							values = anchors,
							get = function()
								return GroupDB(index).stackText.anchor
							end,
							set = function(_, val)
								SetGroupSub(index, 'stackText', 'anchor', val)
							end,
						},
					},
				},

				expiring = {
					name = L['Running out'],
					type = 'group',
					order = 70,
					inline = true,
					args = {
						enabled = {
							name = L['Color the timer as it runs out'],
							type = 'toggle',
							order = 1,
							get = function()
								return GroupDB(index).expiring.enabled
							end,
							set = function(_, val)
								SetGroupSub(index, 'expiring', 'enabled', val)
							end,
						},
						threshold = {
							name = L['Start coloring at'],
							desc = L['Seconds remaining when the timer starts changing color'],
							type = 'range',
							order = 2,
							min = 1,
							max = 30,
							step = 1,
							disabled = function()
								return not GroupDB(index).expiring.enabled
							end,
							get = function()
								return GroupDB(index).expiring.threshold
							end,
							set = function(_, val)
								SetGroupSub(index, 'expiring', 'threshold', val)
							end,
						},
						color = {
							name = L['Color'],
							type = 'color',
							order = 3,
							hasAlpha = false,
							disabled = function()
								return not GroupDB(index).expiring.enabled
							end,
							get = function()
								local c = GroupDB(index).expiring.color
								return c[1], c[2], c[3]
							end,
							set = function(_, r, g, b)
								SetGroupSub(index, 'expiring', 'color', { r, g, b, 1 })
							end,
						},
					},
				},
			},
		}
	end
end

----------------------------------------------------------------------------------------------------
-- Aura watchers
----------------------------------------------------------------------------------------------------

---Show an indicator for as long as one aura matching a description is present.
---
---Addon code may not enumerate auras while they are secret - `ForEachAura` and
---`GetAuraDataByIndex` throw rather than returning nothing. An AuraSlot instead
---lets the engine find the aura and own the button that represents it, so the
---indicator appears and disappears with the aura and no addon code ever reads
---an aura property.
---
---`decorate` runs once per button, inside `initializeFrame`, which is the only
---window where native script calls such as SetPoint and SetSize are permitted
---on an aura button. Attach artwork to the button there and the engine handles
---the rest: when no aura matches, there is no button to show.
---
---@param frame table Unit frame to watch
---@param name string Unique name for this watcher on the frame
---@param filter string Aura filter string, e.g. 'HARMFUL|RAID_PLAYER_DISPELLABLE'
---@param candidateFilters? table Extra narrowing, e.g. includeDispelTypes
---@param decorate fun(button: table, watcher: table) Dress the button
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

----------------------------------------------------------------------------------------------------
-- Container placement and driving
----------------------------------------------------------------------------------------------------

---Work out how long a row of icons may run before it wraps.
---
---Derived from the widest enabled group, so a group set to 8 icons wraps
---after 8 rather than wherever the unit frame's width happens to end.
---@param DB table
---@return number?
function Auras:GetLayoutLimit(DB)
	local widest = 0

	-- Saved settings can hold a non-number here: the shared element defaults
	-- carry sub-tables (position, text) that a merge can leave in a group, so
	-- every value is checked before it is used in arithmetic.
	local function number(value, fallback)
		return type(value) == 'number' and value or fallback
	end

	for index = 1, self.MAX_GROUPS do
		local group = self:ResolveGroup(DB, index)
		if group.enabled then
			local perRow = number(group.number, 10) * (number(group.size, 24) + number(group.spacing, 2))
			if perRow > widest then
				widest = perRow
			end
		end
	end

	if widest > 0 then
		return widest
	end
end

---Anchor an aura container to its unit frame.
---
---`CreateAuras` only configures the flow layout, which decides how buttons
---flow inside the container. The container is an ordinary child frame and
---still needs a real anchor, and elements that own their layout opt out of
---SpartanUI's generic positioning pass.
---@param element table
---@param frame table
---@param DB table
function Auras:PositionContainer(element, frame, DB)
	local position = DB.position or {}
	local anchor = position.anchor or 'TOPLEFT'

	local relativeTo = frame
	if position.relativeTo and position.relativeTo ~= 'Frame' and frame[position.relativeTo] then
		relativeTo = frame[position.relativeTo]
	end

	-- Level first: changing it after anchoring has been seen to drop the
	-- container's points, which leaves it unanchored and its icons invisible.
	-- CreateAuras parents the container to the frame itself, so without this
	-- the icons draw underneath artwork overlays. The old buff element parented
	-- to frame.raised for the same reason.
	if frame.raised and frame.raised.GetFrameLevel then
		element:SetFrameLevel(frame.raised:GetFrameLevel() + 1)
	end

	element:ClearAllPoints()
	element:SetPoint(anchor, relativeTo, position.relativePoint or anchor, position.x or 0, position.y or 0)

	-- Containers grow to fit their buttons, but need a non-zero starting size.
	-- GetWidth returns 0 rather than nil on a realized frame, and can be a
	-- secret value if the frame carries secret anchors, so it is only compared
	-- once it is known to be readable.
	local width = DB.width
	if not width then
		local frameWidth = frame:GetWidth()
		if frameWidth and SUI.BlizzAPI.canaccessvalue(frameWidth) and frameWidth > 0 then
			width = frameWidth
		end
	end

	-- A container one pixel tall clips its own buttons. Height is taken from
	-- the tallest enabled group so there is room for a row of icons before the
	-- container resizes itself around them.
	local height = DB.height
	if type(height) ~= 'number' or height <= 0 then
		height = 0
		for index = 1, self.MAX_GROUPS do
			local group = self:ResolveGroup(DB, index)
			if group.enabled then
				local rowHeight = (type(group.size) == 'number' and group.size or 24) + (type(group.spacing) == 'number' and group.spacing or 2)
				if rowHeight > height then
					height = rowHeight
				end
			end
		end

		if height <= 0 then
			height = 26
		end
	end

	element:SetSize(width or 100, height)
end

---Settle each aura element's enabled state once oUF has finished building.
---
---oUF's own 'Auras' meta element is what pushes the unit into every container
---on a frame, and oUF enables it automatically for every frame it builds
---(walkObject enables every registered element right after the style function
---runs). So there is nothing to enable here.
---
---What does need handling: that automatic pass calls SetEnabled(true) on
---*every* container, which would switch on a display the user turned off. The
---elements build during the style function, before oUF's enable pass, so the
---correction is deferred to the end of the frame's build.
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

---Re-apply each aura element's own enabled setting.
---oUF's meta element enables all containers on the frame at once, which would
---otherwise switch on a container the user turned off.
---@param frame table
function Auras:ApplyContainerEnabledStates(frame)
	for _, name in ipairs({ 'AuraGroups', 'AuraTracker' }) do
		local element = frame[name]
		if element and element.SetEnabled then
			local db = element.DB
			element:SetEnabled(db ~= nil and db.enabled == true)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Tracker slots
----------------------------------------------------------------------------------------------------

---Read a tracked spell's settings with defaults applied.
---@param DB table
---@param index number|string
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

---The filter string for a tracked spell.
---A slot with no spell ID gets a filter that matches nothing, so an unused
---slot stays empty instead of showing an arbitrary aura.
---@param entry table
---@return string
function Auras:GetEntryFilter(entry)
	if not entry.enabled or not entry.spellId or entry.spellId == '' then
		return 'HELPFUL|HARMFUL'
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

---Create every tracker slot up front.
---Slots share the additive-only limitation of groups, so they are all built
---now and repointed later rather than being created on demand.
---@param element table
---@param DB table
---@param buildSettings fun(element: table, entry: table): table
function Auras:AttachSlots(element, DB, buildSettings)
	element.slotKeys = element.slotKeys or {}

	for index = 1, self.MAX_TRACKER_SLOTS do
		local entry = self:ResolveEntry(DB, index)
		element.slotKeys[index] = element:AddSlot(self:GetEntryFilter(entry), buildSettings(element, entry))
	end
end

---Repoint existing slots at the current settings and reposition them.
---@param element table
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

			-- Slots and groups are separate registries with their own keys, so
			-- the group APIs reject a slot key. Which spell a slot shows is
			-- driven by its candidate filters rather than a filter string.
			if element.SetAuraSlotCandidateFilters then
				element:SetAuraSlotCandidateFilters(
					key,
					self:BuildCandidateFilters({
						includeSpellIDs = entry.enabled and entry.spellId or nil,
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

---Style a tracker button. Runs inside initializeFrame, the only window where
---native script methods are allowed on an aura button.
---@param button table
---@param entry table
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

----------------------------------------------------------------------------------------------------
-- Groups
----------------------------------------------------------------------------------------------------

---Build the per-spell tracker options tree.
---@param unitName string
---@param OptionSet AceConfig.OptionsTable
---@param maxSlots number
function Auras:BuildTrackerOptions(unitName, OptionSet, maxSlots)
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
	element.groupKeys = element.groupKeys or {}

	-- Every slot is created now, including the ones currently switched off.
	-- Groups cannot be added or removed later, so the only way to make a group
	-- appear without leaking a container is to have built it up front.
	for index = 1, self.MAX_GROUPS do
		local group = self:ResolveGroup(DB, index)
		element.groupKeys[index] = element:AddGroup(self:GetGroupFilter(group), buildOptions(element, group))
	end

	element.groupSignature = self:GetGroupSignature(DB)
	element.groupBuildSignature = self:GetGroupBuildSignature(DB)
end
