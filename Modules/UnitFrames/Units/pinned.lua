local UF = SUI.UF

local elementList = {
	'FrameBackground',
	'Name',
	'Health',
	'Power',
	'Dispel',
	'SpartanArt',
	not SUI.IsRetail and 'Buffs',
	not SUI.IsRetail and 'Debuffs',
	SUI.IsRetail and 'BuffContainer',
	SUI.IsRetail and 'DebuffContainer',
	SUI.IsRetail and 'CustomAuras',
	'RaidTargetIndicator',
	'ThreatIndicator',
	'Range',
	'Fader',
	'GroupRoleIndicator',
	'ResurrectIndicator',
	'DefensiveIndicator',
	'CornerIndicators',
	'CustomText',
	not SUI.IsRetail and 'AuraDesigner',
	SUI.IsRetail and 'AuraTracker',
}

-- Build the nameList string from settings
local function BuildNameList(settings)
	local names = {}

	-- Add manually pinned names
	if settings.pinnedNames then
		for _, name in ipairs(settings.pinnedNames) do
			if name and name ~= '' then
				names[#names + 1] = name
			end
		end
	end

	-- Auto-add by role from current group roster
	if settings.autoAddRoles then
		local numMembers = GetNumGroupMembers()
		if numMembers > 0 then
			local isRaid = IsInRaid()
			for i = 1, numMembers do
				local unit = isRaid and ('raid' .. i) or ('party' .. i)
				if not isRaid and i == numMembers then
					unit = 'player'
				end
				if UnitExists(unit) then
					local role = UnitGroupRolesAssigned(unit)
					if role and settings.autoAddRoles[role] then
						local unitName = UnitName(unit)
						if unitName and SUI.BlizzAPI.canaccessvalue(unitName) then
							-- Check not already in list
							local found = false
							for _, existing in ipairs(names) do
								if existing == unitName then
									found = true
									break
								end
							end
							if not found then
								names[#names + 1] = unitName
							end
						end
					end
				end
			end
		end
	end

	return table.concat(names, ',')
end

local function GroupBuilder(holder)
	local settings = UF.CurrentSettings.pinned
	local growthMap = UF.Options.GrowthDirectionMap[settings.growthDirection] or UF.Options.GrowthDirectionMap['DOWN_RIGHT']
	local nameList = BuildNameList(settings)

	if SUI.IsRetail then
		holder.header = SUIUF:SpawnHeader(
			'SUI_UF_pinned_Header',
			nil,
			'showRaid',
			true,
			'showParty',
			true,
			'showPlayer',
			true,
			'showSolo',
			false,
			'nameList',
			nameList,
			'xoffset',
			settings.xOffset,
			'yOffset',
			settings.yOffset,
			'point',
			growthMap.point,
			'maxColumns',
			settings.maxColumns,
			'unitsPerColumn',
			settings.unitsPerColumn,
			'columnSpacing',
			settings.columnSpacing,
			'columnAnchorPoint',
			growthMap.columnAnchorPoint,
			'oUF-initialConfigFunction',
			('self:SetWidth(%d) self:SetHeight(%d)'):format(settings.width, UF:CalculateHeight('pinned')),
			'templateType',
			'Button'
		)
	else
		holder.header = SUIUF:SpawnHeader(
			'SUI_UF_pinned_Header',
			nil,
			'showRaid',
			true,
			'showParty',
			true,
			'showPlayer',
			true,
			'showSolo',
			false,
			'nameList',
			nameList,
			'xoffset',
			settings.xOffset,
			'yOffset',
			settings.yOffset,
			'point',
			growthMap.point,
			'maxColumns',
			settings.maxColumns,
			'unitsPerColumn',
			settings.unitsPerColumn,
			'columnSpacing',
			settings.columnSpacing,
			'columnAnchorPoint',
			growthMap.columnAnchorPoint,
			'initial-anchor',
			growthMap.point .. growthMap.columnAnchorPoint,
			'oUF-initialConfigFunction',
			('self:SetWidth(%d) self:SetHeight(%d)'):format(settings.width, UF:CalculateHeight('pinned'))
		)
	end
	holder.header:Show()
	holder.header:SetPoint('TOPLEFT', holder, 'TOPLEFT')

	holder.header:SetAttribute('startingIndex', -4)
	holder.header:Show()
	holder.header.initialized = true
	holder.header:SetAttribute('startingIndex', nil)
end

local function Builder(frame)
	local elementDB = frame.elementDB

	for _, elementName in pairs(elementList) do
		UF.Elements:Build(frame, elementName, elementDB[elementName])
	end
end

local function Update(frame)
	-- This is called per-child frame, skip for children
end

-- Update header attributes and nameList - called from Options and events
local function UpdateHeader()
	local holder = UF.Unit:Get('pinned')
	if not holder or not holder.header then
		return
	end
	if InCombatLockdown() then
		return
	end

	local settings = UF.CurrentSettings.pinned
	local growthMap = UF.Options.GrowthDirectionMap[settings.growthDirection] or UF.Options.GrowthDirectionMap['DOWN_RIGHT']

	local configFunc = ('self:SetWidth(%d) self:SetHeight(%d)'):format(settings.width, UF:CalculateHeight('pinned'))
	holder.header:SetAttribute('initialConfigFunction', configFunc)

	holder.header:SetAttribute('xoffset', settings.xOffset)
	holder.header:SetAttribute('yOffset', settings.yOffset)
	holder.header:SetAttribute('maxColumns', settings.maxColumns)
	holder.header:SetAttribute('unitsPerColumn', settings.unitsPerColumn)
	holder.header:SetAttribute('columnSpacing', settings.columnSpacing)
	holder.header:SetAttribute('point', growthMap.point)
	holder.header:SetAttribute('columnAnchorPoint', growthMap.columnAnchorPoint)

	local nameList = BuildNameList(settings)
	holder.header:SetAttribute('nameList', nameList)
end

-- Register events to keep nameList in sync with roster
local eventFrame = CreateFrame('Frame')
eventFrame:RegisterEvent('GROUP_ROSTER_UPDATE')
eventFrame:RegisterEvent('PLAYER_ENTERING_WORLD')
eventFrame:RegisterEvent('PLAYER_REGEN_ENABLED')
eventFrame:SetScript('OnEvent', function(_, event)
	if not UF.CurrentSettings.pinned or not UF.CurrentSettings.pinned.enabled then
		return
	end
	UpdateHeader()
end)

local function RefreshPinned()
	UpdateHeader()
	local holder = UF.Unit:Get('pinned')
	if holder and holder.UpdateAll then
		holder:UpdateAll()
	end
end

local function Options(OptionSet)
	local L = SUI.L

	UF.Options:AddGroupDisplay('pinned', OptionSet)
	UF.Options:AddGroupLayout('pinned', OptionSet)

	-- Pinned names management
	OptionSet.args.General.args.PinnedNames = {
		name = L['Pinned players'],
		type = 'group',
		order = 0.3,
		args = {
			desc = {
				name = L['Add player names to always show in this frame group. Names must match exactly (case-sensitive).'],
				type = 'description',
				order = 0,
			},
			addName = {
				name = L['Add player name'],
				type = 'input',
				order = 1,
				width = 'double',
				set = function(_, val)
					if val and val ~= '' then
						val = val:match('^%s*(.-)%s*$')
						if not UF.CurrentSettings.pinned.pinnedNames then
							UF.CurrentSettings.pinned.pinnedNames = {}
						end
						table.insert(UF.CurrentSettings.pinned.pinnedNames, val)

						if not UF.DB.UserSettings[UF:GetPresetForFrame('pinned')]['pinned'].pinnedNames then
							UF.DB.UserSettings[UF:GetPresetForFrame('pinned')]['pinned'].pinnedNames = {}
						end
						table.insert(UF.DB.UserSettings[UF:GetPresetForFrame('pinned')]['pinned'].pinnedNames, val)

						RefreshPinned()
					end
				end,
				get = function()
					return ''
				end,
			},
			currentNames = {
				name = L['Current pinned players'],
				type = 'group',
				inline = true,
				order = 2,
				args = (function()
					local args = {}
					local pinnedNames = UF.CurrentSettings.pinned and UF.CurrentSettings.pinned.pinnedNames or {}
					for i, name in ipairs(pinnedNames) do
						args['name_' .. i] = {
							name = name,
							type = 'execute',
							order = i,
							func = function()
								table.remove(UF.CurrentSettings.pinned.pinnedNames, i)
								local dbNames = UF.DB.UserSettings[UF:GetPresetForFrame('pinned')]['pinned'].pinnedNames
								if dbNames then
									table.remove(dbNames, i)
								end
								RefreshPinned()
							end,
							confirm = true,
							confirmText = L['Remove'] .. ' ' .. name .. '?',
						}
					end
					if #pinnedNames == 0 then
						args.empty = {
							name = L['No players pinned yet'],
							type = 'description',
							order = 1,
						}
					end
					return args
				end)(),
			},
		},
	}

	-- Auto-add by role
	OptionSet.args.General.args.AutoAdd = {
		name = L['Auto-add by role'],
		type = 'group',
		order = 0.4,
		inline = true,
		args = {
			desc = {
				name = L['Automatically add group members with these roles to the pinned frames.'],
				type = 'description',
				order = 0,
			},
			TANK = {
				name = L['Tanks'],
				type = 'toggle',
				order = 1,
				get = function()
					local roles = UF.CurrentSettings.pinned.autoAddRoles
					return roles and roles.TANK
				end,
				set = function(_, val)
					if not UF.CurrentSettings.pinned.autoAddRoles then
						UF.CurrentSettings.pinned.autoAddRoles = {}
					end
					UF.CurrentSettings.pinned.autoAddRoles.TANK = val

					if not UF.DB.UserSettings[UF:GetPresetForFrame('pinned')]['pinned'].autoAddRoles then
						UF.DB.UserSettings[UF:GetPresetForFrame('pinned')]['pinned'].autoAddRoles = {}
					end
					UF.DB.UserSettings[UF:GetPresetForFrame('pinned')]['pinned'].autoAddRoles.TANK = val

					RefreshPinned()
				end,
			},
			HEALER = {
				name = L['Healers'],
				type = 'toggle',
				order = 2,
				get = function()
					local roles = UF.CurrentSettings.pinned.autoAddRoles
					return roles and roles.HEALER
				end,
				set = function(_, val)
					if not UF.CurrentSettings.pinned.autoAddRoles then
						UF.CurrentSettings.pinned.autoAddRoles = {}
					end
					UF.CurrentSettings.pinned.autoAddRoles.HEALER = val

					if not UF.DB.UserSettings[UF:GetPresetForFrame('pinned')]['pinned'].autoAddRoles then
						UF.DB.UserSettings[UF:GetPresetForFrame('pinned')]['pinned'].autoAddRoles = {}
					end
					UF.DB.UserSettings[UF:GetPresetForFrame('pinned')]['pinned'].autoAddRoles.HEALER = val

					RefreshPinned()
				end,
			},
			DAMAGER = {
				name = L['DPS'],
				type = 'toggle',
				order = 3,
				get = function()
					local roles = UF.CurrentSettings.pinned.autoAddRoles
					return roles and roles.DAMAGER
				end,
				set = function(_, val)
					if not UF.CurrentSettings.pinned.autoAddRoles then
						UF.CurrentSettings.pinned.autoAddRoles = {}
					end
					UF.CurrentSettings.pinned.autoAddRoles.DAMAGER = val

					if not UF.DB.UserSettings[UF:GetPresetForFrame('pinned')]['pinned'].autoAddRoles then
						UF.DB.UserSettings[UF:GetPresetForFrame('pinned')]['pinned'].autoAddRoles = {}
					end
					UF.DB.UserSettings[UF:GetPresetForFrame('pinned')]['pinned'].autoAddRoles.DAMAGER = val

					RefreshPinned()
				end,
			},
		},
	}
end

---@type SUI.UF.Unit.Settings
local Settings = {
	enabled = false,
	width = 120,
	showParty = true,
	showPlayer = true,
	showRaid = true,
	showSolo = false,
	pinnedNames = {},
	autoAddRoles = {},
	growthDirection = 'DOWN_RIGHT',
	xOffset = 0,
	yOffset = -20,
	maxColumns = 1,
	unitsPerColumn = 10,
	columnSpacing = 2,
	elements = {
		FrameBackground = {
			enabled = false,
		},
		Buffs = {
			enabled = false,
		},
		BuffContainer = {
			enabled = false,
			position = {
				anchor = 'LEFT',
				relativeTo = 'Frame',
				x = 0,
				y = -2,
			},
			growthx = 'RIGHT',
			growthy = 'DOWN',
		},
		DebuffContainer = {
			enabled = true,
			position = {
				anchor = 'LEFT',
				relativeTo = 'Frame',
				x = 0,
				y = -2,
			},
			growthx = 'RIGHT',
			growthy = 'DOWN',
			filterMode = 'raid_debuffs',
			number = 3,
			size = 15,
			spacing = 1,
			showDebuffBorder = true,
		},
		Debuffs = {
			enabled = true,
			number = 3,
			rows = 1,
			size = 15,
			spacing = 1,
			growthx = 'RIGHT',
			growthy = 'DOWN',
			position = {
				anchor = 'LEFT',
				relativePoint = 'LEFT',
				y = -2,
			},
			retail = {
				filterMode = 'raid_debuffs',
			},
		},
		Castbar = {
			enabled = false,
		},
		ThreatIndicator = {
			enabled = true,
			points = 'Name',
		},
		Health = {
			text = {
				['1'] = {
					text = '[SUIHealth(displayDead)] [($>SUIHealth<$)(percentage,hideDead,hideMax)]',
				},
			},
		},
		ResurrectIndicator = {
			enabled = true,
		},
		GroupRoleIndicator = {
			enabled = true,
			position = {
				anchor = 'TOPRIGHT',
				x = 0,
				y = 0,
			},
		},
		RaidTargetIndicator = {
			enabled = true,
			size = 15,
			position = {
				anchor = 'RIGHT',
				x = 5,
				y = 0,
			},
		},
		Power = {
			height = 5,
		},
		DefensiveIndicator = {
			enabled = true,
			size = 15,
			position = {
				anchor = 'LEFT',
				x = 0,
				y = 0,
			},
		},
		Dispel = {
			enabled = true,
		},
	},
	config = {
		IsGroup = true,
	},
}

UF.Unit:Add('pinned', Builder, Settings, Options, GroupBuilder, Update)
