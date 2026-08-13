local UF = SUI.UF
local elementList = {
	---Basic
	'FrameBackground',
	'Name',
	'Health',
	'Castbar',
	'Power',
	'Portrait',
	'SpartanArt',
	not SUI.IsRetail and 'Buffs',
	not SUI.IsRetail and 'Debuffs',
	SUI.IsRetail and 'BuffContainer',
	SUI.IsRetail and 'DebuffContainer',
	SUI.IsRetail and 'CustomAuras',
	'RaidTargetIndicator',
	'Range',
	'Fader',
	'ThreatIndicator',
	'RaidRoleIndicator',
	'CustomText',
	not SUI.IsRetail and 'AuraDesigner',
	SUI.IsRetail and 'AuraTracker',
}

local function Builder(frame)
	local elementDB = frame.elementDB

	for _, elementName in pairs(elementList) do
		UF.Elements:Build(frame, elementName, elementDB[elementName])
	end
end

local function Options() end

---@type SUI.UF.Unit.Settings
local Settings = {
	width = 100,
	elements = {
		BuffContainer = {
			enabled = false,
		},
		DebuffContainer = {
			enabled = true,
			filterMode = 'player_debuffs',
			showDebuffBorder = true,
		},
		Debuffs = {
			enabled = true,
			onlyShowPlayer = true,
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
		Power = { enabled = false },
	},
	config = {
		isFriendly = true,
	},
}

UF.Unit:Add('focus', Builder, Settings)
