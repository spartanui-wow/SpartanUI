local UF = SUI.UF
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

local function groupingOrder()
	local order = 'TANK,HEALER,DAMAGER,NONE'
	if UF.CurrentSettings.party.mode == 'GROUP' then
		order = '1,2,3,4,5,6,7,8'
	end
	return order
end

local function GroupBuilder(holder)
	local settings = UF.CurrentSettings.party
	local growthMap = UF.Options.GrowthDirectionMap[settings.growthDirection] or UF.Options.GrowthDirectionMap['DOWN_RIGHT']

	if SUI.IsRetail then
		-- Retail uses templateType
		holder.header = SUIUF:SpawnHeader(
			'SUI_UF_party_Header',
			nil,
			'showRaid',
			false, -- Always false: oUF uses this to assign raid* unit tokens, which we don't support for party
			'showParty',
			true,
			'showPlayer',
			settings.showPlayer,
			'showSolo',
			true,
			'xoffset',
			settings.xOffset,
			'yOffset',
			settings.yOffset,
			'groupBy',
			settings.mode,
			'groupingOrder',
			groupingOrder(),
			'sortMethod',
			(settings.sortMethod or 'INDEX'):lower(),
			'sortDir',
			settings.sortDir or 'ASC',
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
			('self:SetWidth(%d) self:SetHeight(%d)'):format(settings.width, UF:CalculateHeight('party')),
			'template',
			'SUI_UNITPET, SUI_UNITTARGET',
			'templateType',
			'Button'
		)
	else
		-- Classic versions use unit string and template
		holder.header = SUIUF:SpawnHeader(
			'SUI_UF_party_Header',
			nil,
			'party',
			'showRaid',
			false, -- Always false: oUF uses this to assign raid* unit tokens, which we don't support for party
			'showParty',
			true,
			'showPlayer',
			settings.showPlayer,
			'showSolo',
			true,
			'xoffset',
			settings.xOffset,
			'yOffset',
			settings.yOffset,
			'groupBy',
			settings.mode,
			'groupingOrder',
			groupingOrder(),
			'sortMethod',
			(settings.sortMethod or 'INDEX'):lower(),
			'sortDir',
			settings.sortDir or 'ASC',
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
			('self:SetWidth(%d) self:SetHeight(%d)'):format(settings.width, UF:CalculateHeight('party')),
			'template',
			'SUI_UNITPET, SUI_UNITTARGET'
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
	-- Force header to update its configuration when settings change
	if frame and frame.header then
		local settings = UF.CurrentSettings.party
		local growthMap = UF.Options.GrowthDirectionMap[settings.growthDirection] or UF.Options.GrowthDirectionMap['DOWN_RIGHT']

		-- Update the initialConfigFunction with new dimensions
		local configFunc = ('self:SetWidth(%d) self:SetHeight(%d)'):format(settings.width, UF:CalculateHeight('party'))
		frame.header:SetAttribute('initialConfigFunction', configFunc)

		-- Update header attributes that affect layout and size
		frame.header:SetAttribute('xoffset', settings.xOffset)
		frame.header:SetAttribute('yOffset', settings.yOffset)
		frame.header:SetAttribute('maxColumns', settings.maxColumns)
		frame.header:SetAttribute('unitsPerColumn', settings.unitsPerColumn)
		frame.header:SetAttribute('columnSpacing', settings.columnSpacing)
		frame.header:SetAttribute('groupBy', settings.mode)
		frame.header:SetAttribute('groupingOrder', groupingOrder())
		frame.header:SetAttribute('showPlayer', settings.showPlayer)
		frame.header:SetAttribute('sortMethod', (settings.sortMethod or 'INDEX'):lower())
		frame.header:SetAttribute('sortDir', settings.sortDir or 'ASC')
		frame.header:SetAttribute('point', growthMap.point)
		frame.header:SetAttribute('columnAnchorPoint', growthMap.columnAnchorPoint)
	end
end

local function Options(OptionSet)
	UF.Options:AddGroupDisplay('party', OptionSet)
	UF.Options:AddGroupLayout('party', OptionSet)

	OptionSet.args.General.args.Layout.args.mode = {
		name = SUI.L['Sort order'],
		type = 'select',
		order = 11,
		values = { ['GROUP'] = 'Groups', ['NAME'] = 'Name', ['ASSIGNEDROLE'] = 'Roles' },
		set = function(info, val)
			UF.CurrentSettings.party.mode = val
			UF.DB.UserSettings[UF:GetPresetForFrame('party')]['party'].mode = val
			local order = 'TANK,HEALER,DAMAGER,NONE'
			if val == 'GROUP' then
				order = '1,2,3,4,5,6,7,8'
			end
			UF.Unit:Get('party').header:SetAttribute('groupBy', val)
			UF.Unit:Get('party').header:SetAttribute('groupingOrder', order)
		end,
	}
end

---@type SUI.UF.Unit.Settings
local Settings = {
	width = 120,
	showParty = true,
	showPlayer = true,
	showRaid = false,
	showSolo = false,
	customVisibility = '',
	difficultyVisibility = {
		enabled = false,
	},
	mode = 'ASSIGNEDROLE',
	sortMethod = 'INDEX',
	sortDir = 'ASC',
	growthDirection = 'DOWN_RIGHT',
	xOffset = 0,
	yOffset = -20,
	maxColumns = 1,
	unitsPerColumn = 5,
	columnSpacing = 2,
	elements = {
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
		},
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
					number = 3,
					size = 15,
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
			number = 3,
			rows = 3,
			size = 15,
			spacing = 1,
			growthx = 'RIGHT',
			growthy = 'UP',
			position = {
				anchor = 'BOTTOMRIGHT',
				relativePoint = 'BOTTOMRIGHT',
				y = 2,
			},
			retail = {
				filterMode = 'healing_mode',
			},
		},
		Debuffs = {
			enabled = true,
			number = 5,
			rows = 1,
			size = 18,
			spacing = 1,
			growthx = 'RIGHT',
			growthy = 'DOWN',
			position = {
				anchor = 'LEFT',
				relativePoint = 'LEFT',
				y = -2,
			},
			retail = {
				filterMode = 'raid_debuffs', -- Show all raid-relevant debuffs
				disableInPvP = true,
			},
		},
		Castbar = {
			enabled = true,
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
			position = {
				anchor = 'TOP',
				relativeTo = 'Castbar',
				relativePoint = 'BOTTOM',
			},
		},
		ResurrectIndicator = {
			enabled = true,
		},
		SummonIndicator = {
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
		AssistantIndicator = {
			enabled = true,
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
		ClassIcon = {
			enabled = false,
			size = 15,
			position = {
				anchor = 'TOPLEFT',
				x = 0,
				y = 0,
			},
		},
		name = {
			position = {
				y = 12,
			},
		},
		Power = {
			height = 5,
		},
		RaidRoleIndicator = {
			position = {
				anchor = 'LEFT',
				relativePoint = 'RIGHT',
				relativeTo = 'Name',
				x = 20,
				y = -10,
			},
			size = 15,
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
				color = { 1, 1, 0, 1 },
				sides = { top = true, bottom = true, left = true, right = true },
				displayLevel = 5,
			},
		},
		DefensiveIndicator = {
			enabled = true,
			size = 15,
			showSwipe = true,
			showDuration = true,
			showBorder = true,
			borderSize = 2,
			borderColor = { 0, 0.8, 0, 1 },
			position = {
				anchor = 'LEFT',
				x = 0,
				y = 0,
			},
		},
		RaidDebuffs = {
			enabled = false,
			size = 25,
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
	},
	config = {
		IsGroup = true,
	},
}

UF.Unit:Add('party', Builder, Settings, Options, GroupBuilder, Update)
