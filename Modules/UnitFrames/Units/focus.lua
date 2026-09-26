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
	not UF.IsModernOUF and 'Buffs',
	not UF.IsModernOUF and 'Debuffs',
	UF.IsModernOUF and 'BuffContainer',
	UF.IsModernOUF and 'DebuffContainer',
	UF.IsModernOUF and 'CustomAuras',
	'RaidTargetIndicator',
	'Range',
	'Fader',
	'ThreatIndicator',
	'RaidRoleIndicator',
	'CustomText',
	not UF.IsModernOUF and 'AuraDesigner',
	UF.IsModernOUF and 'AuraTracker',
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
