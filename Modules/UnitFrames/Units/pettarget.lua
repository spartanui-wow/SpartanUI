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
		Health = {
			height = 30,
		},
		Power = {
			height = 5,
			text = {
				['1'] = {
					enabled = false,
				},
			},
		},
		Name = {
			enabled = true,
			height = 10,
			position = {
				y = 0,
			},
		},
	},
	config = {
		Requires = 'pet',
	},
}

UF.Unit:Add('pettarget', Builder, Settings)
