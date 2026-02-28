local UF = SUI.UF
local elementList = {
	---Basic
	'FrameBackground',
	'Name',
	'Health',
	'Castbar',
	'SpartanArt',
	'RaidTargetIndicator',
	'Range',
	'ThreatIndicator',
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
	config = {
		Requires = 'boss',
	},
}

UF.Unit:Add('bosstarget', Builder, Settings)
