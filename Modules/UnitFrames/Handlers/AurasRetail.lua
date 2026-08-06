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
-- VERIFICATION STATUS (2026-08-05): the group/slot/option names used here are
-- taken from oUF's 12.1 rewrite, which exercises them directly. The
-- candidateFilters keys other than includeSpellIDs come from Blizzard's PTR
-- notes and are not yet confirmed against a live client, so ValidateCandidateKeys
-- drops anything the running client rejects rather than silently filtering
-- nothing. Re-check against a 12.1 PTR build before release.

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

---Read a group's settings with defaults applied.
---Returns nil only when the group index is out of range.
---@param DB table
---@param index number|string
---@return table?
function Auras:ResolveGroup(DB, index)
	local defaults = self.GROUP_DEFAULTS
	if not defaults then
		return DB.groups and DB.groups[tostring(index)]
	end

	local stored = DB.groups and DB.groups[tostring(index)]
	local resolved = {}

	for key, value in pairs(defaults) do
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
			if type(value) == 'table' and type(resolved[key]) == 'table' then
				for k, v in pairs(value) do
					resolved[key][k] = v
				end
			else
				resolved[key] = value
			end
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
				-- No validator exposed; trust the key and let the group creation
				-- call surface any error.
				validCandidateKeys[key] = true
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

---Parse a comma or space separated list of spell IDs into the map Blizzard wants.
---@param raw? string
---@return table<number, boolean>?
function Auras:BuildSpellIDMap(raw)
	if not raw or raw == '' then
		return
	end

	local map, count = {}, 0
	for id in tostring(raw):gmatch('%d+') do
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

	local lookup = {
		expiration = methods.ExpirationOnly,
		instanceID = methods.AuraInstanceIDOnly,
	}

	return lookup[mode] or methods.ExpirationOnly
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
function Auras:StyleButton(button, groupDB, element)
	local font = SUI.Font:GetFontObject(nil, groupDB.fontSize or 12, 'OUTLINE')

	if button.Count and font then
		button.Count:SetFontObject(font)
	end
	if button.Time and font then
		button.Time:SetFontObject(font)
	end

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

	if group.customFilter and group.customFilter ~= '' then
		return group.customFilter
	end

	return self:GetFilterString(group.filterMode) or 'HELPFUL'
end

----------------------------------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------------------------------

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
		stored.groups[tostring(index)] = stored.groups[tostring(index)] or {}
		stored.groups[tostring(index)][key] = val

		local current = UF.CurrentSettings[unitName].elements.AuraGroups
		current.groups = current.groups or {}
		current.groups[tostring(index)] = current.groups[tostring(index)] or {}
		current.groups[tostring(index)][key] = val

		-- The frame may not be spawned (disabled frame, arena out of arena).
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
			},
		}
	end
end

----------------------------------------------------------------------------------------------------
-- Container placement and driving
----------------------------------------------------------------------------------------------------

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

	element:ClearAllPoints()
	element:SetPoint(anchor, relativeTo, position.relativePoint or anchor, position.x or 0, position.y or 0)

	-- Containers grow to fit their buttons, but need a non-zero starting size.
	element:SetSize(DB.width or frame:GetWidth() or 100, DB.height or 1)
end

---Enable oUF's aura meta element so containers receive their unit.
---
---oUF registers an element named 'Auras' whose Update calls SetUnit on every
---container belonging to the frame. SpartanUI's own elements only create
---containers, so without this they are never given a unit and stay empty.
---Safe to call repeatedly: EnableElement is a no-op once active.
---
---Note that oUF's Enable switches on *every* container for the frame, so each
---element re-asserts its own enabled state afterwards.
---@param frame table
function Auras:EnableContainerDriver(frame)
	if frame.EnableElement then
		frame:EnableElement('Auras')
	end

	self:ApplyContainerEnabledStates(frame)
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

	local stored = DB.entries and DB.entries[tostring(index)]
	if stored then
		for key, value in pairs(stored) do
			if type(value) == 'table' and type(resolved[key]) == 'table' then
				for k, v in pairs(value) do
					resolved[key][k] = v
				end
			else
				resolved[key] = value
			end
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

	local filter = entry.filter or 'HELPFUL'
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

			if element.SetAuraGroupFilterString then
				element:SetAuraGroupFilterString(key, self:GetEntryFilter(entry))
			end

			-- Slots auto-position relative to each other by default; anchoring
			-- them explicitly is what makes per-spell placement possible.
			local slot = element.GetAuraGroupFrame and element:GetAuraGroupFrame(key)
			if slot and slot.ClearAllPoints then
				slot:ClearAllPoints()
				slot:SetPoint(entry.anchor or 'CENTER', frame, entry.anchor or 'CENTER', entry.x or 0, entry.y or 0)
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
	local font = SUI.Font:GetFontObject(nil, entry.fontSize or 12, 'OUTLINE')

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

	local function EntryDB(index)
		return Auras:ResolveEntry(UF.CurrentSettings[unitName].elements.AuraTracker, index)
	end

	local function SetEntry(index, key, val)
		local preset = UF:GetPresetForFrame(unitName)
		local stored = UF.DB.UserSettings[preset][unitName].elements.AuraTracker
		stored.entries = stored.entries or {}
		stored.entries[tostring(index)] = stored.entries[tostring(index)] or {}
		stored.entries[tostring(index)][key] = val

		local current = UF.CurrentSettings[unitName].elements.AuraTracker
		current.entries = current.entries or {}
		current.entries[tostring(index)] = current.entries[tostring(index)] or {}
		current.entries[tostring(index)][key] = val

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
