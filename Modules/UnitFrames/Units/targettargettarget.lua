local UF = SUI.UF
local elementList = {
	---Basic
	'FrameBackground',
	'Name',
	'Health',
	'Castbar',
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
