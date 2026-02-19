local UF = SUI.UF

local function Builder(frame)
	local elementDB = frame.elementDB
	local ElementsToBuild = {
		---Basic
		'Name',
		'Health',
		'Castbar',
		'Power',
		'Portrait',
		'Dispel',
		'SpartanArt',
		'Buffs',
		'Debuffs',
		'ClassIcon',
		'RaidTargetIndicator',
		'ThreatIndicator',
		'Range',
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
		---Player Only
		'Totems',
		'CombatIndicator',
		'Runes',
		'RestingIndicator',
		'ClassPower',
		'AdditionalPower',
		'AlternativePower', -- Encounter-specific power (Torghast, Mythic+, etc.)
		'EclipseBar', -- MOP Classic Balance Druid eclipse power bar (#565)
		'PrivateAuras',
		-- 'AuraBars' -- DECOMMISSIONED: Not maintaining if unavailable in retail
	}

	for _, elementName in pairs(ElementsToBuild) do
		UF.Elements:Build(frame, elementName, elementDB[elementName])
	end

	-- WarlockPowerFrame only exists in Wrath Classic and later, not in TBC or Vanilla
	local _, class = UnitClass('player')
	if SUI.BlizzAPI.canaccessvalue(class) and class == 'WARLOCK' and WarlockPowerFrame then
		WarlockPowerFrame:SetParent(frame)
		-- WarlockPowerFrame_OnLoad(WarlockPowerFrame)
		WarlockPowerFrame:SetFrameStrata('MEDIUM')
		WarlockPowerFrame:SetFrameLevel(4)
		WarlockPowerFrame:SetScale(0.7)
		WarlockPowerFrame:ClearAllPoints()
		WarlockPowerFrame:SetPoint('TOPRIGHT', frame.Power, 'BOTTOMRIGHT', 0, -5)
		WarlockPowerFrame:Show()
	end
end

local function Update() end

---@type SUI.UF.Unit.Settings
local Settings = {
	visibility = {
		showAlways = true,
	},
	anchor = {
		point = 'BOTTOMRIGHT',
		relativePoint = 'BOTTOM',
		xOfs = -60,
		yOfs = 250,
	},
	frameBackground = {
		enabled = false,
		displayLevel = -1,
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
	elements = {
		-- AuraBars = { -- DECOMMISSIONED: Not maintaining if unavailable in retail
		-- 	enabled = true
		-- },
		Buffs = {
			enabled = true,
			number = 32,
			size = 24,
			rows = 2,
			spacing = 2,
			rules = {
				duration = {
					enabled = true,
					mode = 'exclude',
				},
			},
			position = {
				anchor = 'TOPLEFT',
				relativePoint = 'BOTTOMLEFT',
				x = 0,
				y = -2,
			},
			retail = {
				filterMode = 'all_buffs', -- Show all player buffs by default
			},
		},
		Debuffs = {
			enabled = true,
			number = 16,
			size = 28,
			rows = 1,
			spacing = 2,
			position = {
				anchor = 'BOTTOMLEFT',
				relativePoint = 'TOPLEFT',
				x = 0,
				y = 2,
			},
			retail = {
				filterMode = 'all_debuffs', -- Show all debuffs by default
			},
		},
		Portrait = {
			enabled = true,
		},
		Castbar = {
			enabled = true,
		},
		Health = {
			position = {
				anchor = 'TOP',
				relativeTo = 'Castbar',
				relativePoint = 'BOTTOM',
			},
		},
		CombatIndicator = {
			enabled = true,
			glow = true,
			position = {
				anchor = 'TOPRIGHT',
				x = 10,
				y = 10,
			},
		},
		ClassIcon = {
			enabled = true,
		},
		RestingIndicator = {
			enabled = true,
			position = {
				anchor = 'TOPLEFT',
				x = 0,
				y = 0,
			},
		},
		Power = {
			text = {
				['1'] = {
					enabled = true,
				},
			},
		},
		PvPIndicator = {
			enabled = true,
		},
		AdditionalPower = {
			enabled = true,
		},
		SUI_RaidGroup = { enabled = true },
		PrivateAuras = {
			enabled = true,
		},
	},
	config = {
		isFriendly = true,
	},
}

UF.Unit:Add('player', Builder, Settings, nil, nil, Update)
