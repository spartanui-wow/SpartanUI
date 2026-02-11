local UF = SUI.UF

local function Builder(frame)
	local elementDB = frame.elementDB

	---Basic
	UF.Elements:Build(frame, 'Name', elementDB['Name'])
	UF.Elements:Build(frame, 'Health', elementDB['Health'])
	UF.Elements:Build(frame, 'Castbar', elementDB['Castbar'])
	UF.Elements:Build(frame, 'Power', elementDB['Power'])
	UF.Elements:Build(frame, 'Portrait', elementDB['Portrait'])
	UF.Elements:Build(frame, 'Dispel', elementDB['Dispel'])
	UF.Elements:Build(frame, 'SpartanArt', elementDB['SpartanArt'])
	UF.Elements:Build(frame, 'Buffs', elementDB['Buffs'])
	UF.Elements:Build(frame, 'Debuffs', elementDB['Debuffs'])
	UF.Elements:Build(frame, 'ClassIcon', elementDB['ClassIcon'])
	UF.Elements:Build(frame, 'RaidTargetIndicator', elementDB['RaidTargetIndicator'])
	UF.Elements:Build(frame, 'ThreatIndicator', elementDB['ThreatIndicator'])
	UF.Elements:Build(frame, 'Range', elementDB['Range'])

	--Friendly Only
	UF.Elements:Build(frame, 'AssistantIndicator', elementDB['AssistantIndicator'])
	UF.Elements:Build(frame, 'GroupRoleIndicator', elementDB['GroupRoleIndicator'])
	UF.Elements:Build(frame, 'LeaderIndicator', elementDB['LeaderIndicator'])
	UF.Elements:Build(frame, 'PhaseIndicator', elementDB['PhaseIndicator'])
	UF.Elements:Build(frame, 'PvPIndicator', elementDB['PvPIndicator'])
	UF.Elements:Build(frame, 'RaidRoleIndicator', elementDB['RaidRoleIndicator'])
	UF.Elements:Build(frame, 'ReadyCheckIndicator', elementDB['ReadyCheckIndicator'])
	UF.Elements:Build(frame, 'ResurrectIndicator', elementDB['ResurrectIndicator'])
	UF.Elements:Build(frame, 'SummonIndicator', elementDB['SummonIndicator'])
	UF.Elements:Build(frame, 'StatusText', elementDB['StatusText'])
	UF.Elements:Build(frame, 'SUI_RaidGroup', elementDB['SUI_RaidGroup'])

	UF.Elements:Build(frame, 'QuestMob', elementDB['QuestMob'])
	UF.Elements:Build(frame, 'RareElite', elementDB['RareElite'])
	-- UF.Elements:Build(frame, 'AuraBars', elementDB['AuraBars']) -- DECOMMISSIONED: Not maintaining if unavailable in retail

	UF.Elements:Build(frame, 'AuraWatch', elementDB['AuraWatch'])

	if ComboFrame then
		ComboFrame:Hide()
		ComboFrame:HookScript('OnShow', function(self)
			self:Hide()
		end)
	end
end

local function Options() end

---@type SUI.UF.Unit.Settings
local Settings = {
	anchor = {
		point = 'BOTTOMLEFT',
		relativePoint = 'BOTTOM',
		xOfs = 60,
		yOfs = 250,
	},
	elements = {
		-- AuraBars = { -- DECOMMISSIONED: Not maintaining if unavailable in retail
		-- 	enabled = true,
		-- },
		Buffs = {
			enabled = true,
			number = 16,
			size = 22,
			rows = 2,
			spacing = 1,
			growthx = 'LEFT',
			rules = {
				isMount = true,
				isPlayerAura = true,
				isRaid = true,
				isHelpful = true,
				duration = {
					enabled = true,
					mode = 'exclude',
				},
			},
			position = {
				anchor = 'TOPRIGHT',
				relativePoint = 'BOTTOMRIGHT',
				x = 0,
				y = -2,
			},
			retail = {
				filterMode = 'healing_mode', -- Show HoTs and combat-relevant buffs
			},
		},
		Debuffs = {
			enabled = true,
			number = 16,
			size = 26,
			rows = 1,
			spacing = 1,
			growthx = 'LEFT',
			position = {
				anchor = 'BOTTOMRIGHT',
				relativePoint = 'TOPRIGHT',
				x = 0,
				y = 2,
			},
			retail = {
				filterMode = 'player_debuffs', -- Show only your debuffs on target
			},
		},
		ThreatIndicator = {
			enabled = true,
			points = 'Name',
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
		QuestMob = {
			enabled = true,
		},
		RaidRoleIndicator = {
			enabled = true,
		},
		AssistantIndicator = {
			enabled = true,
		},
		ClassIcon = {
			enabled = true,
		},
		PvPIndicator = {
			enabled = true,
		},
		Power = {
			text = {
				['1'] = {
					enabled = true,
				},
			},
		},
	},
	config = {
		isFriendly = true,
	},
}

UF.Unit:Add('target', Builder, Settings)
