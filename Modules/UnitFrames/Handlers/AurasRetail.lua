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

---Whether the client provides the native aura container objects.
---@return boolean
function Auras:HasNativeContainers()
	return SUI.IsRetail and C_UnitAuras ~= nil and AuraContainerSortMethod ~= nil
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
---Groups cannot be removed from a container once added, so any change to the
---set of groups requires a fresh container.
---@param DB table
---@return string
local function GroupSignature(DB)
	local parts = {}
	for index = 1, 10 do
		local group = DB.groups and DB.groups[tostring(index)]
		if group and group.enabled then
			parts[#parts + 1] = table.concat({
				index,
				group.filterMode or '',
				group.customFilter or '',
				tostring(group.number or ''),
				tostring(group.onlyMine),
				tostring(group.onlyStealable),
				tostring(group.maxDuration or ''),
				group.includeSpellIDs or '',
				group.excludeSpellIDs or '',
			}, ':')
		end
	end

	return table.concat(parts, '|')
end

---@param element table
---@param DB table
---@return boolean
function Auras:GroupsNeedRebuild(element, DB)
	return element.groupSignature ~= GroupSignature(DB)
end

---Rebuild a frame's aura container from scratch.
---Groups cannot be detached from a container, so changing which groups exist
---means replacing the container. Deferred out of combat because container
---creation is restricted while the player is locked down.
---@param frame table
---@param element table
---@param DB table
function Auras:RebuildContainer(frame, element, DB)
	if InCombatLockdown() then
		if not frame.auraRebuildPending then
			frame.auraRebuildPending = true
			UF:RegisterEvent('PLAYER_REGEN_ENABLED', function()
				if frame.auraRebuildPending then
					frame.auraRebuildPending = false
					UF.Elements:Update(frame, 'Auras')
				end
			end)
		end
		return
	end

	frame.auraRebuildPending = false

	if element.SetEnabled then
		element:SetEnabled(false)
	end
	element:Hide()
	frame.Auras = nil

	UF.Elements:Build(frame, 'Auras', DB)
	UF.Elements:Update(frame, 'Auras', DB)
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
	local function GroupDB(index)
		return UF.CurrentSettings[unitName].elements.Auras.groups[tostring(index)]
	end

	local function SetGroup(index, key, val)
		local preset = UF:GetPresetForFrame(unitName)
		local stored = UF.DB.UserSettings[preset][unitName].elements.Auras
		stored.groups = stored.groups or {}
		stored.groups[tostring(index)] = stored.groups[tostring(index)] or {}
		stored.groups[tostring(index)][key] = val

		UF.CurrentSettings[unitName].elements.Auras.groups[tostring(index)][key] = val
		UF.Unit[unitName]:ElementUpdate('Auras')
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

---Attach the enabled groups to a container.
---@param element table
---@param DB table
---@param buildOptions fun(element: table, groupDB: table): table
function Auras:AttachGroups(element, DB, buildOptions)
	element.groupKeys = element.groupKeys or {}

	for index = 1, 10 do
		local group = DB.groups and DB.groups[tostring(index)]
		if group and group.enabled then
			local filter = group.customFilter
			if not filter or filter == '' then
				filter = self:GetFilterString(group.filterMode) or 'HELPFUL'
			end

			element.groupKeys[index] = element:AddGroup(filter, buildOptions(element, group))
		end
	end

	element.groupSignature = GroupSignature(DB)
end
