local UF = SUI.UF
local L = SUI.L

local elementList = {
	---Basic
	'FrameBackground',
	'Name',
	'Health',
	'Castbar',
	'Power',
	'Portrait',
	'Dispel',
	'SpartanArt',
	not SUI.IsRetail and 'Buffs',
	not SUI.IsRetail and 'Debuffs',
	SUI.IsRetail and 'AuraGroups',
	'ClassIcon',
	'RaidTargetIndicator',
	'TargetIndicator',
	'ThreatIndicator',
	'Range',
	'Fader',
	--Friendly Only
	'AssistantIndicator',
	'GroupRoleIndicator',
	'LeaderIndicator',
	'PhaseIndicator',
	'PvPIndicator',
	'RaidRoleIndicator',
	'ReadyCheckIndicator',
	'ResurrectIndicator',
	'SummonIndicator',
	'StatusText',
	'SUI_RaidGroup',
	'AuraWatch',
	'DefensiveIndicator',
	'RaidDebuffs',
	'CornerIndicators',
	'PrivateAuras',
	'CustomText',
	not SUI.IsRetail and 'AuraDesigner',
	SUI.IsRetail and 'AuraTracker',
}

-- Tier definitions: 3 independent raid frame types
-- raid40 is the primary/legacy tier, always enabled by default
-- raid10 and raid25 are opt-in overrides for smaller group sizes
local tierDefs = {
	{
		name = 'raid10',
		maxFrames = 10,
		displayName = 'Raid (1-10)',
		enabledByDefault = false,
	},
	{
		name = 'raid25',
		maxFrames = 25,
		displayName = 'Raid (11-25)',
		enabledByDefault = false,
	},
	{
		name = 'raid40',
		maxFrames = 40,
		displayName = 'Raid',
		enabledByDefault = true,
	},
}

-- Helper: iterate all ACTIVE headers on a group holder
local function ForEachHeader(holder, fn)
	if holder.headers then
		for i, header in ipairs(holder.headers) do
			fn(header, i)
		end
	elseif holder.header then
		fn(holder.header, 1)
	end
end

-- Reset a SecureGroupHeader: hide first, then clear attributes to avoid layout errors
local function ResetHeader(header)
	header:Hide()
	if header.groupLabel then
		header.groupLabel:Hide()
	end
	header:SetAttribute('showPlayer', nil)
	header:SetAttribute('showSolo', nil)
	header:SetAttribute('showParty', nil)
	header:SetAttribute('showRaid', nil)
	header:SetAttribute('columnSpacing', nil)
	header:SetAttribute('columnAnchorPoint', nil)
	header:SetAttribute('groupBy', nil)
	header:SetAttribute('groupFilter', nil)
	header:SetAttribute('groupingOrder', nil)
	header:SetAttribute('maxColumns', nil)
	header:SetAttribute('point', nil)
	header:SetAttribute('sortDir', nil)
	header:SetAttribute('sortMethod', nil)
	header:SetAttribute('startingIndex', nil)
	header:SetAttribute('strictFiltering', nil)
	header:SetAttribute('unitsPerColumn', nil)
	header:SetAttribute('xOffset', nil)
	header:SetAttribute('yOffset', nil)
end

-- Helper: build the grouping order string based on settings
local function BuildGroupingOrder(settings)
	if settings.mode == 'GROUP' then
		local order = { '1', '2', '3', '4', '5', '6', '7', '8' }
		if settings.invertGroupingOrder then
			local reversed = {}
			for i = #order, 1, -1 do
				reversed[#reversed + 1] = order[i]
			end
			return table.concat(reversed, ',')
		end
		return table.concat(order, ',')
	elseif settings.mode == 'CLASS' then
		local classOrder = settings.classOrder
			or {
				'WARRIOR',
				'PALADIN',
				'HUNTER',
				'ROGUE',
				'PRIEST',
				'DEATHKNIGHT',
				'SHAMAN',
				'MAGE',
				'WARLOCK',
				'MONK',
				'DRUID',
				'DEMONHUNTER',
				'EVOKER',
			}
		if settings.invertGroupingOrder then
			local reversed = {}
			for i = #classOrder, 1, -1 do
				reversed[#reversed + 1] = classOrder[i]
			end
			return table.concat(reversed, ',')
		end
		return table.concat(classOrder, ',')
	else
		local roleOrder = settings.roleOrder or { 'TANK', 'HEALER', 'DAMAGER', 'NONE' }
		if settings.invertGroupingOrder then
			local reversed = {}
			for i = #roleOrder, 1, -1 do
				reversed[#reversed + 1] = roleOrder[i]
			end
			return table.concat(reversed, ',')
		end
		return table.concat(roleOrder, ',')
	end
end

-- Helper: build the groupBy attribute value based on settings
-- In multi-header mode with GROUP, each sub-header is filtered by groupFilter
-- so within each group we sort by role (or other secondary sort)
local function BuildGroupBy(settings, isMultiHeader)
	if settings.raidWideSorting then
		return nil
	end
	if isMultiHeader then
		-- Multi-header: each header shows one group, sort within by role/class/name
		return settings.withinGroupSort or 'ASSIGNEDROLE'
	end
	return settings.mode
end

-- Helper: build the groupingOrder for within-group sorting (multi-header mode)
local function BuildWithinGroupOrder(settings)
	local sortBy = settings.withinGroupSort or 'ASSIGNEDROLE'
	if sortBy == 'CLASS' then
		local classOrder = settings.classOrder
			or {
				'WARRIOR',
				'PALADIN',
				'HUNTER',
				'ROGUE',
				'PRIEST',
				'DEATHKNIGHT',
				'SHAMAN',
				'MAGE',
				'WARLOCK',
				'MONK',
				'DRUID',
				'DEMONHUNTER',
				'EVOKER',
			}
		return table.concat(classOrder, ',')
	elseif sortBy == 'ASSIGNEDROLE' then
		local roleOrder = settings.roleOrder or { 'TANK', 'HEALER', 'DAMAGER', 'NONE' }
		return table.concat(roleOrder, ',')
	end
	return 'TANK,HEALER,DAMAGER,NONE'
end

-- Build visibility conditions based on which tiers are enabled.
-- When only raid40 is enabled, it shows for all raid sizes (legacy behavior).
-- When raid10/raid25 are enabled, they claim their size ranges and raid40 adjusts.
function UF:GetRaidTierVisibility(tierName)
	local raid10Enabled = UF.CurrentSettings.raid10 and UF.CurrentSettings.raid10.enabled
	local raid25Enabled = UF.CurrentSettings.raid25 and UF.CurrentSettings.raid25.enabled

	if tierName == 'raid10' then
		-- Show when in raid AND fewer than 11 members
		return '[@raid11,exists] hide; [group:raid] show; hide'
	elseif tierName == 'raid25' then
		-- Show when 11+ members AND fewer than 26
		return '[@raid26,exists] hide; [@raid11,exists][group:raid] show; hide'
	elseif tierName == 'raid40' then
		if raid10Enabled and raid25Enabled then
			-- Both smaller tiers active: raid40 only shows for 26+
			return '[@raid26,exists][group:raid] show; hide'
		elseif raid25Enabled then
			-- Only raid25 active: raid40 shows when 26+
			return '[@raid26,exists][group:raid] show; hide'
		elseif raid10Enabled then
			-- Only raid10 active: raid40 shows when 11+
			return '[@raid11,exists][group:raid] show; hide'
		else
			-- No smaller tiers: raid40 covers all sizes (legacy behavior, no customVisibility)
			return ''
		end
	end
	return ''
end

-- Shared element builder for all tiers
local function Builder(frame)
	local frameName = frame:GetName() or 'Unknown'
	local elementDB = frame.elementDB

	if UF.BuildDebug then
		UF:debug('Raid Builder ENTRY - Frame: ' .. frameName)
	end

	for index, elementName in pairs(elementList) do
		if UF.BuildDebug then
			UF:debug('Raid Builder - Building element [' .. index .. ']: ' .. elementName .. ' for frame: ' .. frameName)
		end
		UF.Elements:Build(frame, elementName, elementDB[elementName])
	end

	if UF.BuildDebug then
		UF:debug('Raid Builder EXIT - Completed building all elements for: ' .. frameName)
	end
end

-- Spawn a single header with the given attributes
-- isPerGroupHeader: true when this header represents one raid group (multi-header mode)
local function SpawnSingleHeader(holder, tierName, headerName, settings, configFunc, growthMap, groupFilter, isPerGroupHeader)
	local groupBy = settings.mode
	local groupOrder = BuildGroupingOrder(settings)

	-- In multi-header mode, each header shows one group, sort within by role/class
	if isPerGroupHeader then
		groupBy = BuildGroupBy(settings, true)
		groupOrder = BuildWithinGroupOrder(settings)
	end

	-- raidWideSorting: no groupBy, flat sort
	if settings.raidWideSorting then
		groupBy = nil
		groupOrder = nil
	end

	local header
	if SUI.IsRetail then
		local args = {
			headerName,
			nil,
			'showRaid',
			true,
			'showParty',
			settings.showParty,
			'showPlayer',
			settings.showPlayer,
			'showSolo',
			settings.showSolo,
			'xoffset',
			settings.xOffset,
			'yOffset',
			settings.yOffset,
			'point',
			growthMap.point,
			'sortMethod',
			(settings.sortMethod or 'INDEX'):lower(),
			'sortDir',
			settings.sortDir or 'ASC',
			'maxColumns',
			settings.maxColumns,
			'unitsPerColumn',
			settings.unitsPerColumn,
			'columnSpacing',
			settings.columnSpacing,
			'columnAnchorPoint',
			growthMap.columnAnchorPoint,
			'oUF-initialConfigFunction',
			configFunc,
			'templateType',
			'Button',
		}
		if groupBy then
			args[#args + 1] = 'groupBy'
			args[#args + 1] = groupBy
		end
		if groupOrder then
			args[#args + 1] = 'groupingOrder'
			args[#args + 1] = groupOrder
		end
		if groupFilter then
			args[#args + 1] = 'groupFilter'
			args[#args + 1] = tostring(groupFilter)
		end
		header = SUIUF:SpawnHeader(unpack(args))
	else
		local args = {
			headerName,
			nil,
			'raid',
			'showRaid',
			true,
			'showParty',
			settings.showParty,
			'showPlayer',
			settings.showPlayer,
			'showSolo',
			settings.showSolo,
			'xoffset',
			settings.xOffset,
			'yOffset',
			settings.yOffset,
			'point',
			growthMap.point,
			'sortMethod',
			(settings.sortMethod or 'INDEX'):lower(),
			'sortDir',
			settings.sortDir or 'ASC',
			'maxColumns',
			settings.maxColumns,
			'unitsPerColumn',
			settings.unitsPerColumn,
			'columnSpacing',
			settings.columnSpacing,
			'columnAnchorPoint',
			growthMap.columnAnchorPoint,
			'oUF-initialConfigFunction',
			configFunc,
		}
		if groupBy then
			args[#args + 1] = 'groupBy'
			args[#args + 1] = groupBy
		end
		if groupOrder then
			args[#args + 1] = 'groupingOrder'
			args[#args + 1] = groupOrder
		end
		if groupFilter then
			args[#args + 1] = 'groupFilter'
			args[#args + 1] = tostring(groupFilter)
		end
		header = SUIUF:SpawnHeader(unpack(args))
	end

	return header
end

-- Lazily create a per-group header if it doesn't exist yet
local function EnsureGroupHeader(holder, tierName, groupNum, settings, configFunc, growthMap)
	if not holder.groupHeaders then
		holder.groupHeaders = {}
	end
	if holder.groupHeaders[groupNum] then
		return holder.groupHeaders[groupNum]
	end

	local headerName = 'SUI_UF_' .. tierName .. '_G' .. groupNum .. '_Header'
	local header = SpawnSingleHeader(holder, tierName, headerName, settings, configFunc, growthMap, groupNum, true)

	-- Pre-create frames (max 5 per group)
	header:SetAttribute('startingIndex', -5)
	header:Show()
	header.initialized = true
	header:SetAttribute('startingIndex', nil)
	header.groupNum = groupNum

	-- Create group label (starts hidden, Update controls visibility)
	local label = header:CreateFontString(nil, 'OVERLAY')
	label:SetPoint('BOTTOM', header, 'TOP', 0, 2)
	label:SetFont(STANDARD_TEXT_FONT, 10, 'OUTLINE')
	label:Hide()
	header.groupLabel = label

	-- Start hidden; the Update function decides which headers are active
	ResetHeader(header)

	holder.groupHeaders[groupNum] = header
	return header
end

-- Factory: create GroupBuilder for a specific tier
local function CreateGroupBuilder(tierName, maxFrames)
	return function(holder)
		if UF.BuildDebug then
			UF:debug(tierName .. ' GroupBuilder ENTRY - Creating header')
		end

		local settings = UF.CurrentSettings[tierName]
		---@diagnostic disable-next-line: undefined-field
		local configFunc = ('self:SetWidth(%d) self:SetHeight(%d)'):format(settings.width, UF:CalculateHeight(tierName))
		local growthMap = UF.Options.GrowthDirectionMap[settings.growthDirection] or UF.Options.GrowthDirectionMap['DOWN_RIGHT']

		-- Always create the main single header
		local headerName = 'SUI_UF_' .. tierName .. '_Header'
		holder.mainHeader = SpawnSingleHeader(holder, tierName, headerName, settings, configFunc, growthMap)
		holder.mainHeader:SetPoint('TOPLEFT', holder, 'TOPLEFT')

		-- Force creation of frames upfront
		holder.mainHeader:SetAttribute('startingIndex', -maxFrames)
		holder.mainHeader:Show()
		holder.mainHeader.initialized = true
		holder.mainHeader:SetAttribute('startingIndex', nil)

		-- Pre-create per-group headers if multi-header mode is active
		holder.groupHeaders = {}
		local useMultiHeader = settings.useGroupHeaders and settings.mode == 'GROUP' and not settings.raidWideSorting
		if useMultiHeader then
			for groupNum = 1, 8 do
				EnsureGroupHeader(holder, tierName, groupNum, settings, configFunc, growthMap)
			end
		end

		-- Set active header references based on current mode
		-- (the Update function will finalize visibility and attributes)
		holder.header = holder.mainHeader
		holder.headers = nil

		if UF.BuildDebug then
			UF:debug(tierName .. ' GroupBuilder EXIT - Created ' .. maxFrames .. ' frames')
		end
	end
end

-- Apply common attributes to a single header
local function ApplyHeaderAttributes(header, settings, configFunc, growthMap, isMultiHeader)
	header:SetAttribute('initialConfigFunction', configFunc)
	header:SetAttribute('xoffset', settings.xOffset)
	header:SetAttribute('yOffset', settings.yOffset)
	header:SetAttribute('maxColumns', settings.maxColumns)
	header:SetAttribute('unitsPerColumn', settings.unitsPerColumn)
	header:SetAttribute('columnSpacing', settings.columnSpacing)
	header:SetAttribute('showPlayer', settings.showPlayer)
	header:SetAttribute('showSolo', settings.showSolo)
	header:SetAttribute('showParty', settings.showParty)
	header:SetAttribute('sortMethod', (settings.sortMethod or 'INDEX'):lower())
	header:SetAttribute('sortDir', settings.sortDir or 'ASC')
	header:SetAttribute('point', growthMap.point)
	header:SetAttribute('columnAnchorPoint', growthMap.columnAnchorPoint)

	if settings.raidWideSorting then
		header:SetAttribute('groupBy', nil)
		header:SetAttribute('groupingOrder', nil)
	elseif isMultiHeader then
		local groupBy = BuildGroupBy(settings, true)
		local groupOrder = BuildWithinGroupOrder(settings)
		if groupBy then
			header:SetAttribute('groupBy', groupBy)
		end
		if groupOrder then
			header:SetAttribute('groupingOrder', groupOrder)
		end
	else
		header:SetAttribute('groupBy', settings.mode)
		header:SetAttribute('groupingOrder', BuildGroupingOrder(settings))
	end
end

-- Factory: create Update function for a specific tier
local function CreateUpdate(tierName)
	return function(frame)
		if not frame then
			return
		end

		local settings = UF.CurrentSettings[tierName]
		local growthMap = UF.Options.GrowthDirectionMap[settings.growthDirection] or UF.Options.GrowthDirectionMap['DOWN_RIGHT']
		---@diagnostic disable-next-line: undefined-field
		local configFunc = ('self:SetWidth(%d) self:SetHeight(%d)'):format(settings.width, UF:CalculateHeight(tierName))

		local wantMultiHeader = settings.useGroupHeaders and settings.mode == 'GROUP' and not settings.raidWideSorting

		if wantMultiHeader then
			-- Switch to multi-header mode: reset the main header, activate per-group headers
			if frame.mainHeader then
				ResetHeader(frame.mainHeader)
			end

			-- Lazily create per-group headers that don't exist yet
			for groupNum = 1, 8 do
				EnsureGroupHeader(frame, tierName, groupNum, settings, configFunc, growthMap)
			end

			-- Build active header list based on group visibility
			local activeHeaders = {}
			local groupSpacing = settings.groupSpacing or 10
			local prevHeader = nil

			for groupNum = 1, 8 do
				local header = frame.groupHeaders[groupNum]
				if header then
					if not settings.groupVisibility or settings.groupVisibility[groupNum] ~= false then
						-- Activate this header
						ApplyHeaderAttributes(header, settings, configFunc, growthMap, true)
						header:SetAttribute('groupFilter', tostring(groupNum))

						-- Position
						header:ClearAllPoints()
						if prevHeader then
							header:SetPoint('TOPLEFT', prevHeader, 'TOPRIGHT', groupSpacing, 0)
						else
							header:SetPoint('TOPLEFT', frame, 'TOPLEFT')
						end
						header:Show()

						-- Group label
						if header.groupLabel then
							if settings.groupLabels and settings.groupLabels.enabled then
								header.groupLabel:SetFont(STANDARD_TEXT_FONT, settings.groupLabels.textSize or 10, 'OUTLINE')
								local fmt = settings.groupLabels.format or 'Group %d'
								header.groupLabel:SetText(fmt:format(groupNum))
								if settings.groupLabels.color then
									header.groupLabel:SetTextColor(unpack(settings.groupLabels.color))
								end
								header.groupLabel:Show()
							else
								header.groupLabel:Hide()
							end
						end

						activeHeaders[#activeHeaders + 1] = header
						prevHeader = header
					else
						-- Hidden group
						ResetHeader(header)
					end
				end
			end

			frame.headers = activeHeaders
			frame.header = activeHeaders[1]
		else
			-- Switch to single-header mode: reset all per-group headers, activate main header
			if frame.groupHeaders then
				for _, header in pairs(frame.groupHeaders) do
					ResetHeader(header)
				end
			end

			if frame.mainHeader then
				frame.mainHeader:ClearAllPoints()
				frame.mainHeader:SetPoint('TOPLEFT', frame, 'TOPLEFT')
				ApplyHeaderAttributes(frame.mainHeader, settings, configFunc, growthMap, false)

				-- Apply groupFilter for per-group visibility
				if settings.groupVisibility then
					local visibleGroups = {}
					for i = 1, 8 do
						if settings.groupVisibility[i] ~= false then
							visibleGroups[#visibleGroups + 1] = tostring(i)
						end
					end
					if #visibleGroups < 8 then
						frame.mainHeader:SetAttribute('groupFilter', table.concat(visibleGroups, ','))
					else
						frame.mainHeader:SetAttribute('groupFilter', nil)
					end
				else
					frame.mainHeader:SetAttribute('groupFilter', nil)
				end

				frame.mainHeader:Show()
			end

			frame.headers = nil
			frame.header = frame.mainHeader
		end

		-- Update customVisibility to match current tier enable states
		settings.customVisibility = UF:GetRaidTierVisibility(tierName)
	end
end

-- Helper: update a setting in both CurrentSettings and DB, then refresh all headers
local function SetRaidSetting(tierName, key, val)
	UF.CurrentSettings[tierName][key] = val
	UF.DB.UserSettings[UF:GetPresetForFrame(tierName)][tierName][key] = val
end

local function RefreshRaidHeaders(tierName)
	local holder = UF.Unit:Get(tierName)
	if holder then
		UF.Unit:Update(holder)
		-- Re-register state drivers for the new active header set
		if holder.UpdateAll then
			holder:UpdateAll()
		end
	end
end

-- Factory: create Options function for a specific tier
local function CreateOptions(tierName)
	return function(OptionSet)
		UF.Options:AddGroupDisplay(tierName, OptionSet)
		UF.Options:AddGroupLayout(tierName, OptionSet)

		OptionSet.args.General.args.Layout.args.bar2 = { name = 'Offsets', type = 'header', order = 20 }

		-- Sort order (primary grouping mode)
		OptionSet.args.General.args.Layout.args.mode = {
			name = L['Sort order'],
			type = 'select',
			order = 11,
			values = {
				['GROUP'] = L['Groups'],
				['NAME'] = L['Name'],
				['ASSIGNEDROLE'] = L['Roles'],
				['CLASS'] = L['Class'],
			},
			set = function(info, val)
				SetRaidSetting(tierName, 'mode', val)
				local holder = UF.Unit:Get(tierName)
				if holder then
					ForEachHeader(holder, function(header)
						if val == 'GROUP' and holder.headers then
							header:SetAttribute('groupBy', BuildGroupBy(UF.CurrentSettings[tierName], true))
							header:SetAttribute('groupingOrder', BuildWithinGroupOrder(UF.CurrentSettings[tierName]))
						else
							header:SetAttribute('groupBy', val)
							header:SetAttribute('groupingOrder', BuildGroupingOrder(UF.CurrentSettings[tierName]))
						end
					end)
				end
			end,
		}

		-- Invert grouping order
		OptionSet.args.General.args.Layout.args.invertGroupingOrder = {
			name = L['Reverse sort order'],
			desc = L['Reverses the group or role order'],
			type = 'toggle',
			order = 11.1,
			get = function()
				return UF.CurrentSettings[tierName].invertGroupingOrder
			end,
			set = function(_, val)
				SetRaidSetting(tierName, 'invertGroupingOrder', val)
				local holder = UF.Unit:Get(tierName)
				if holder then
					ForEachHeader(holder, function(header)
						if holder.headers then
							header:SetAttribute('groupingOrder', BuildWithinGroupOrder(UF.CurrentSettings[tierName]))
						else
							header:SetAttribute('groupingOrder', BuildGroupingOrder(UF.CurrentSettings[tierName]))
						end
					end)
				end
			end,
		}

		-- Raid-wide sorting (flat list, no grouping)
		OptionSet.args.General.args.Layout.args.raidWideSorting = {
			name = L['Flat list sorting'],
			desc = L['Ignore groups and sort all raid members as one flat list'],
			type = 'toggle',
			order = 11.2,
			get = function()
				return UF.CurrentSettings[tierName].raidWideSorting
			end,
			set = function(_, val)
				SetRaidSetting(tierName, 'raidWideSorting', val)
				local holder = UF.Unit:Get(tierName)
				if holder then
					ForEachHeader(holder, function(header)
						if val then
							header:SetAttribute('groupBy', nil)
							header:SetAttribute('groupingOrder', nil)
						else
							header:SetAttribute('groupBy', UF.CurrentSettings[tierName].mode)
							header:SetAttribute('groupingOrder', BuildGroupingOrder(UF.CurrentSettings[tierName]))
						end
					end)
				end
			end,
		}

		-- Use group headers (multi-header mode)
		OptionSet.args.General.args.Layout.args.useGroupHeaders = {
			name = L['Per-group headers'],
			desc = L['Create a separate header for each raid group. Lets you show group labels and sort by group first, then by role.'],
			type = 'toggle',
			order = 11.3,
			hidden = function()
				return UF.CurrentSettings[tierName].raidWideSorting
			end,
			get = function()
				return UF.CurrentSettings[tierName].useGroupHeaders
			end,
			set = function(_, val)
				SetRaidSetting(tierName, 'useGroupHeaders', val)
				RefreshRaidHeaders(tierName)
			end,
		}

		-- Within-group sort (only visible in multi-header mode)
		OptionSet.args.General.args.Layout.args.withinGroupSort = {
			name = L['Within-group sort'],
			desc = L['How to sort players within each raid group'],
			type = 'select',
			order = 11.4,
			hidden = function()
				return not UF.CurrentSettings[tierName].useGroupHeaders or UF.CurrentSettings[tierName].raidWideSorting
			end,
			values = {
				['ASSIGNEDROLE'] = L['Roles'],
				['CLASS'] = L['Class'],
				['NAME'] = L['Name'],
			},
			get = function()
				return UF.CurrentSettings[tierName].withinGroupSort or 'ASSIGNEDROLE'
			end,
			set = function(_, val)
				SetRaidSetting(tierName, 'withinGroupSort', val)
				local holder = UF.Unit:Get(tierName)
				if holder then
					ForEachHeader(holder, function(header)
						header:SetAttribute('groupBy', val)
						header:SetAttribute('groupingOrder', BuildWithinGroupOrder(UF.CurrentSettings[tierName]))
					end)
				end
			end,
		}

		-- Group spacing (only visible in multi-header mode)
		OptionSet.args.General.args.Layout.args.groupSpacing = {
			name = L['Group spacing'],
			desc = L['Space between raid group headers'],
			type = 'range',
			order = 11.5,
			min = 0,
			max = 100,
			step = 1,
			hidden = function()
				return not UF.CurrentSettings[tierName].useGroupHeaders
			end,
			get = function()
				return UF.CurrentSettings[tierName].groupSpacing or 10
			end,
			set = function(_, val)
				SetRaidSetting(tierName, 'groupSpacing', val)
			end,
		}

		-- Role order header
		OptionSet.args.General.args.Layout.args.roleOrderHeader = {
			name = L['Role priority'],
			type = 'header',
			order = 12,
			hidden = function()
				local mode = UF.CurrentSettings[tierName].mode
				return mode ~= 'ASSIGNEDROLE' or UF.CurrentSettings[tierName].raidWideSorting
			end,
		}

		-- Role order: individual role positions (1-4)
		local roleLabels = {
			TANK = L['Tank'],
			HEALER = L['Healer'],
			DAMAGER = L['DPS'],
			NONE = L['None'],
		}
		for idx, role in ipairs({ 'TANK', 'HEALER', 'DAMAGER', 'NONE' }) do
			OptionSet.args.General.args.Layout.args['roleOrder_' .. role] = {
				name = roleLabels[role],
				desc = L['Position in the role sort order (1 = first)'],
				type = 'select',
				order = 12 + idx * 0.1,
				values = { [1] = '1', [2] = '2', [3] = '3', [4] = '4' },
				hidden = function()
					local mode = UF.CurrentSettings[tierName].mode
					return mode ~= 'ASSIGNEDROLE' or UF.CurrentSettings[tierName].raidWideSorting
				end,
				get = function()
					local roleOrder = UF.CurrentSettings[tierName].roleOrder or { 'TANK', 'HEALER', 'DAMAGER', 'NONE' }
					for i, r in ipairs(roleOrder) do
						if r == role then
							return i
						end
					end
					return idx
				end,
				set = function(_, newPos)
					local roleOrder = UF.CurrentSettings[tierName].roleOrder or { 'TANK', 'HEALER', 'DAMAGER', 'NONE' }
					-- Remove this role from current position
					local oldPos
					for i, r in ipairs(roleOrder) do
						if r == role then
							oldPos = i
							break
						end
					end
					if oldPos then
						table.remove(roleOrder, oldPos)
					end
					table.insert(roleOrder, newPos, role)
					SetRaidSetting(tierName, 'roleOrder', roleOrder)
					local holder = UF.Unit:Get(tierName)
					if holder then
						ForEachHeader(holder, function(header)
							header:SetAttribute('groupingOrder', BuildGroupingOrder(UF.CurrentSettings[tierName]))
						end)
					end
				end,
			}
		end

		-- Per-group visibility header
		OptionSet.args.General.args.Layout.args.groupVisibilityHeader = {
			name = L['Group visibility'],
			type = 'header',
			order = 14,
		}

		-- Per-group visibility toggles (1-8)
		for groupNum = 1, 8 do
			OptionSet.args.General.args.Layout.args['groupVis_' .. groupNum] = {
				name = L['Group'] .. ' ' .. groupNum,
				type = 'toggle',
				order = 14 + groupNum * 0.1,
				width = 0.5,
				get = function()
					local gv = UF.CurrentSettings[tierName].groupVisibility
					if not gv then
						return true
					end
					return gv[groupNum] ~= false
				end,
				set = function(_, val)
					local gv = UF.CurrentSettings[tierName].groupVisibility
					if not gv then
						gv = {}
						UF.CurrentSettings[tierName].groupVisibility = gv
					end
					gv[groupNum] = val
					-- Persist
					if not UF.DB.UserSettings[UF:GetPresetForFrame(tierName)][tierName].groupVisibility then
						UF.DB.UserSettings[UF:GetPresetForFrame(tierName)][tierName].groupVisibility = {}
					end
					UF.DB.UserSettings[UF:GetPresetForFrame(tierName)][tierName].groupVisibility[groupNum] = val

					-- Update headers
					local holder = UF.Unit:Get(tierName)
					if holder then
						if holder.headers then
							-- Multi-header: show/hide individual group headers
							for _, header in ipairs(holder.headers) do
								if header.groupNum == groupNum then
									if val then
										header:Show()
									else
										header:Hide()
									end
								end
							end
						elseif holder.header then
							-- Single-header: rebuild groupFilter
							local visibleGroups = {}
							for i = 1, 8 do
								if gv[i] ~= false then
									visibleGroups[#visibleGroups + 1] = tostring(i)
								end
							end
							if #visibleGroups < 8 then
								holder.header:SetAttribute('groupFilter', table.concat(visibleGroups, ','))
							else
								holder.header:SetAttribute('groupFilter', nil)
							end
						end
					end
				end,
			}
		end

		-- Group labels header
		OptionSet.args.General.args.Layout.args.groupLabelsHeader = {
			name = L['Group labels'],
			type = 'header',
			order = 16,
			hidden = function()
				return not UF.CurrentSettings[tierName].useGroupHeaders
			end,
		}

		OptionSet.args.General.args.Layout.args.groupLabelsEnabled = {
			name = L['Show group labels'],
			desc = L['Display a label above each raid group'],
			type = 'toggle',
			order = 16.1,
			hidden = function()
				return not UF.CurrentSettings[tierName].useGroupHeaders
			end,
			get = function()
				local gl = UF.CurrentSettings[tierName].groupLabels
				return gl and gl.enabled
			end,
			set = function(_, val)
				if not UF.CurrentSettings[tierName].groupLabels then
					UF.CurrentSettings[tierName].groupLabels = { enabled = false, textSize = 10, format = 'Group %d' }
				end
				UF.CurrentSettings[tierName].groupLabels.enabled = val
				if not UF.DB.UserSettings[UF:GetPresetForFrame(tierName)][tierName].groupLabels then
					UF.DB.UserSettings[UF:GetPresetForFrame(tierName)][tierName].groupLabels = {}
				end
				UF.DB.UserSettings[UF:GetPresetForFrame(tierName)][tierName].groupLabels.enabled = val
				RefreshRaidHeaders(tierName)
			end,
		}

		OptionSet.args.General.args.Layout.args.groupLabelsSize = {
			name = L['Label text size'],
			type = 'range',
			order = 16.2,
			min = 6,
			max = 20,
			step = 1,
			hidden = function()
				local gl = UF.CurrentSettings[tierName].groupLabels
				return not UF.CurrentSettings[tierName].useGroupHeaders or not (gl and gl.enabled)
			end,
			get = function()
				local gl = UF.CurrentSettings[tierName].groupLabels
				return gl and gl.textSize or 10
			end,
			set = function(_, val)
				if not UF.CurrentSettings[tierName].groupLabels then
					UF.CurrentSettings[tierName].groupLabels = { enabled = true, textSize = 10, format = 'Group %d' }
				end
				UF.CurrentSettings[tierName].groupLabels.textSize = val
				if not UF.DB.UserSettings[UF:GetPresetForFrame(tierName)][tierName].groupLabels then
					UF.DB.UserSettings[UF:GetPresetForFrame(tierName)][tierName].groupLabels = {}
				end
				UF.DB.UserSettings[UF:GetPresetForFrame(tierName)][tierName].groupLabels.textSize = val
				RefreshRaidHeaders(tierName)
			end,
		}
	end
end

-- Base element settings shared by all tiers
local baseElements = {
	FrameBackground = {
		enabled = false,
		displayLevel = -5,
		background = {
			enabled = false,
			type = 'color',
			color = { 0.1, 0.1, 0.1, 0.8 },
			alpha = 0.8,
			classColor = false,
		},
		border = {
			enabled = false,
			sides = { top = true, bottom = true, left = true, right = true },
			size = 1,
			colors = {
				top = { 1, 1, 1, 1 },
				bottom = { 1, 1, 1, 1 },
				left = { 1, 1, 1, 1 },
				right = { 1, 1, 1, 1 },
			},
			classColors = { top = false, bottom = false, left = false, right = false },
		},
	},
	AuraWatch = {
		enabled = true,
		size = 16,
	},
	ResurrectIndicator = {
		enabled = true,
	},
	SummonIndicator = {
		enabled = true,
	},
	RaidTargetIndicator = {
		size = 16,
		alpha = 0.65,
		position = {
			x = 2,
		},
	},
	RaidRoleIndicator = {
		enabled = true,
		size = 10,
		alpha = 0.7,
		position = {
			anchor = 'BOTTOMLEFT',
			x = 0,
			y = 0,
		},
	},
	ReadyCheckIndicator = {
		size = 15,
		position = {
			anchor = 'RIGHT',
			x = -5,
		},
	},
	ThreatIndicator = {
		enabled = true,
		points = 'Name',
	},
	Name = {
		enabled = true,
		height = 10,
		textSize = 10,
		text = '[SUI_ColorClass][name]',
		position = {
			y = 0,
		},
	},
	SUI_RaidGroup = {
		textSize = 9,
		SetJustifyH = 'CENTER',
		SetJustifyV = 'MIDDLE',
		position = {
			anchor = 'BOTTOMRIGHT',
			x = 0,
			y = 5,
		},
	},
	GroupRoleIndicator = {
		enabled = true,
		size = 15,
		alpha = 0.75,
		ShowDPS = false,
		position = {
			anchor = 'TOPRIGHT',
			x = -1,
			y = 1,
		},
	},
	TargetIndicator = {
		enabled = true,
		ShowTarget = true,
		mode = 'border',
		texture = {
			textureKey = 'DoubleArrow',
			placement = 'sides',
			scale = 1.0,
			color = { 1, 1, 1, 1 },
			alpha = 1.0,
		},
		border = {
			size = 2,
			color = { 0, 1, 0, 1 },
			sides = { top = true, bottom = true, left = true, right = true },
			displayLevel = 5,
		},
	},
	DefensiveIndicator = {
		enabled = true,
		size = 20,
		showSwipe = true,
		showDuration = true,
		showBorder = true,
		borderSize = 2,
		borderColor = { 0, 0.8, 0, 1 },
		position = {
			anchor = 'CENTER',
			x = 0,
			y = 0,
		},
	},
	RaidDebuffs = {
		enabled = true,
		size = 28,
		showDuration = true,
		position = {
			anchor = 'CENTER',
			x = 0,
			y = 0,
		},
	},
	Dispel = {
		enabled = true,
	},
	PrivateAuras = {
		enabled = true,
	},
}

-- Per-tier setting overrides (layout + element differences)
local tierOverrides = {
	raid10 = {
		width = 110,
		maxColumns = 2,
		unitsPerColumn = 5,
		columnSpacing = 2,
		elements = {
			AuraGroups = {
				enabled = true,
				position = {
					anchor = 'BOTTOMRIGHT',
					relativeTo = 'Frame',
					x = 0,
					y = 2,
				},
				growthx = 'RIGHT',
				growthy = 'UP',
				groups = {
					['1'] = {
						enabled = true,
						name = 'HoTs',
						filterMode = 'healing_mode',
						onlyMine = true,
						number = 5,
						size = 18,
						spacing = 1,
					},
					['2'] = {
						enabled = true,
						name = 'Raid debuffs',
						filterMode = 'raid_debuffs',
						number = 5,
						size = 18,
						spacing = 1,
						showDebuffBorder = true,
						forceNewLine = true,
					},
				},
			},
			Buffs = {
				enabled = true,
				onlyShowPlayer = true,
				healingMode = true,
				number = 5,
				rows = 3,
				size = 18,
				spacing = 1,
				growthx = 'RIGHT',
				growthy = 'UP',
				position = {
					anchor = 'BOTTOMRIGHT',
					relativePoint = 'BOTTOMRIGHT',
					x = 0,
					y = 2,
				},
				retail = {
					filterMode = 'healing_mode',
				},
			},
			Debuffs = {
				enabled = true,
				rows = 1,
				number = 5,
				size = 18,
				spacing = 1,
				growthy = 'DOWN',
				growthx = 'LEFT',
				position = {
					anchor = 'LEFT',
					relativePoint = 'LEFT',
					x = 0,
					y = -2,
				},
				retail = {
					filterMode = 'raid_debuffs',
					disableInPvP = true,
				},
			},
			Health = {
				height = 35,
				text = {
					['1'] = {
						text = '[SUIHealth(missing,displayDead)] [($>SUIHealth<$)(percentage,hideDead)]',
					},
				},
			},
			Power = {
				height = 4,
				position = {
					y = 0,
				},
				text = {
					['1'] = {
						enabled = false,
					},
				},
			},
		},
	},
	raid25 = {
		width = 95,
		maxColumns = 5,
		unitsPerColumn = 5,
		columnSpacing = 2,
		elements = {
			AuraGroups = {
				enabled = true,
				position = {
					anchor = 'BOTTOMRIGHT',
					relativeTo = 'Frame',
					x = 0,
					y = 2,
				},
				growthx = 'RIGHT',
				growthy = 'UP',
				groups = {
					['1'] = {
						enabled = true,
						name = 'HoTs',
						filterMode = 'healing_mode',
						onlyMine = true,
						number = 5,
						size = 18,
						spacing = 1,
					},
					['2'] = {
						enabled = true,
						name = 'Raid debuffs',
						filterMode = 'raid_debuffs',
						number = 5,
						size = 18,
						spacing = 1,
						showDebuffBorder = true,
						forceNewLine = true,
					},
				},
			},
			Buffs = {
				enabled = true,
				onlyShowPlayer = true,
				healingMode = true,
				number = 5,
				rows = 3,
				size = 15,
				spacing = 1,
				growthx = 'RIGHT',
				growthy = 'UP',
				position = {
					anchor = 'BOTTOMRIGHT',
					relativePoint = 'BOTTOMRIGHT',
					x = 0,
					y = 2,
				},
				retail = {
					filterMode = 'healing_mode',
				},
			},
			Debuffs = {
				enabled = true,
				rows = 1,
				number = 5,
				size = 15,
				spacing = 1,
				growthy = 'DOWN',
				growthx = 'LEFT',
				position = {
					anchor = 'LEFT',
					relativePoint = 'LEFT',
					x = 0,
					y = -2,
				},
				retail = {
					filterMode = 'raid_debuffs',
					disableInPvP = true,
				},
			},
			Health = {
				height = 30,
				text = {
					['1'] = {
						text = '[SUIHealth(missing,displayDead)] [($>SUIHealth<$)(percentage,hideDead)]',
					},
				},
			},
			Power = {
				height = 2,
				position = {
					y = 0,
				},
				text = {
					['1'] = {
						enabled = false,
					},
				},
			},
		},
	},
	raid40 = {
		width = 95,
		maxColumns = 4,
		unitsPerColumn = 10,
		columnSpacing = 2,
		elements = {
			AuraGroups = {
				enabled = true,
				position = {
					anchor = 'BOTTOMRIGHT',
					relativeTo = 'Frame',
					x = 0,
					y = 2,
				},
				growthx = 'RIGHT',
				growthy = 'UP',
				groups = {
					['1'] = {
						enabled = true,
						name = 'HoTs',
						filterMode = 'healing_mode',
						onlyMine = true,
						number = 5,
						size = 18,
						spacing = 1,
					},
					['2'] = {
						enabled = true,
						name = 'Raid debuffs',
						filterMode = 'raid_debuffs',
						number = 5,
						size = 18,
						spacing = 1,
						showDebuffBorder = true,
						forceNewLine = true,
					},
				},
			},
			Buffs = {
				enabled = true,
				onlyShowPlayer = true,
				healingMode = true,
				number = 5,
				rows = 3,
				size = 15,
				spacing = 1,
				growthx = 'RIGHT',
				growthy = 'UP',
				position = {
					anchor = 'BOTTOMRIGHT',
					relativePoint = 'BOTTOMRIGHT',
					x = 0,
					y = 2,
				},
				retail = {
					filterMode = 'healing_mode',
				},
			},
			Debuffs = {
				enabled = true,
				rows = 1,
				number = 5,
				size = 15,
				spacing = 1,
				growthy = 'DOWN',
				growthx = 'LEFT',
				position = {
					anchor = 'LEFT',
					relativePoint = 'LEFT',
					x = 0,
					y = -2,
				},
				retail = {
					filterMode = 'raid_debuffs',
					disableInPvP = true,
				},
			},
			Health = {
				height = 30,
				text = {
					['1'] = {
						text = '[SUIHealth(missing,displayDead)] [($>SUIHealth<$)(percentage,hideDead)]',
					},
				},
			},
			Power = {
				height = 2,
				position = {
					y = 0,
				},
				text = {
					['1'] = {
						enabled = false,
					},
				},
			},
		},
	},
}

-- Build base settings shared across all tiers
local function BuildBaseSettings()
	return {
		showParty = false,
		showPlayer = true,
		showRaid = true,
		showSolo = false,
		customVisibility = '',
		difficultyVisibility = {
			enabled = false,
		},
		mode = 'ASSIGNEDROLE',
		sortMethod = 'INDEX',
		sortDir = 'ASC',
		growthDirection = 'DOWN_RIGHT',
		xOffset = 2,
		yOffset = -3,
		-- Multi-header and sorting
		useGroupHeaders = false,
		withinGroupSort = 'ASSIGNEDROLE',
		invertGroupingOrder = false,
		raidWideSorting = false,
		groupSpacing = 10,
		roleOrder = { 'TANK', 'HEALER', 'DAMAGER', 'NONE' },
		groupLabels = {
			enabled = false,
			textSize = 10,
			format = 'Group %d',
		},
		visibility = {
			showAlways = false,
			showInRaid = true,
			showInParty = false,
		},
		config = {
			IsGroup = true,
			isFriendly = true,
		},
	}
end

-- Register all 3 tiers
for _, tier in ipairs(tierDefs) do
	local settings = BuildBaseSettings()
	settings.enabled = tier.enabledByDefault

	-- Apply tier-specific layout overrides
	local overrides = tierOverrides[tier.name]
	settings.width = overrides.width
	settings.maxColumns = overrides.maxColumns
	settings.unitsPerColumn = overrides.unitsPerColumn
	settings.columnSpacing = overrides.columnSpacing

	-- Build elements: start with shared base, then merge tier-specific overrides
	settings.elements = SUI:CopyData({}, baseElements)
	for elementName, elementOverride in pairs(overrides.elements) do
		settings.elements[elementName] = elementOverride
	end

	UF.Unit:Add(tier.name, Builder, settings, CreateOptions(tier.name), CreateGroupBuilder(tier.name, tier.maxFrames), CreateUpdate(tier.name))
end
