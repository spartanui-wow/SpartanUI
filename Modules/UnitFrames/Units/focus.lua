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
	'Buffs',
	'Debuffs',
	'RaidTargetIndicator',
	'Range',
	'ThreatIndicator',
	'RaidRoleIndicator',
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
