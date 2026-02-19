local UF = SUI.UF
local elementList = {
	---Basic
	'Name',
	'Health',
	'Castbar',
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
	enabled = false,
	width = 100,
	elements = {
		auras = {
			Debuffs = {
				size = 10,
			},
		},
		ThreatIndicator = {
			enabled = true,
			points = 'Name',
		},
		Health = {
			height = 30,
		},
		Power = {
			height = 5,
		},
	},
	config = {
		Requires = 'target',
		isFriendly = true,
	},
}

UF.Unit:Add('targettargettarget', Builder, Settings)
