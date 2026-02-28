if SUI.IsClassic then
	return
end

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
	'Buffs',
	'Debuffs',
	'ClassIcon',
	'RaidTargetIndicator',
	'Range',
	'PVPSpecIcon',
	'GroupRoleIndicator',
	'RaidRoleIndicator',
}

local function GroupBuilder(holder)
	for i = 1, 5 do
		local frame = SUIUF:Spawn('arena' .. i, 'SUI_UF_arena' .. i)
		if i == 1 then
			frame:SetPoint('TOPLEFT', holder, 'TOPLEFT', 0, 0)
		else
			frame:SetPoint('TOP', holder.frames[i - 1], 'BOTTOM', 0, -10)
		end
		frame:SetAttribute('oUF-enableArenaPrep', true)

		holder.frames[i] = frame
	end
end

local function Builder(frame)
	local elementDB = frame.elementDB

	for _, elementName in pairs(elementList) do
		UF.Elements:Build(frame, elementName, elementDB[elementName])
	end
end

local function Options(OptionSet)
	UF.Options:AddGroupLayout('arena', OptionSet)
end

---@type SUI.UF.Unit.Settings
local Settings = {
	maxColumns = 1,
	unitsPerColumn = 5,
	columnSpacing = 1,
	yOffset = -25,
	elements = {
		Name = { text = '[SUI_ColorClass][name] [arenaspec]' },
		Power = {
			height = 5,
		},
		Portrait = {
			enabled = false,
		},
		Castbar = {
			enabled = true,
			height = 15,
		},
		Health = {
			position = {
				anchor = 'TOP',
				relativeTo = 'Castbar',
				relativePoint = 'BOTTOM',
			},
		},
		ThreatIndicator = {
			enabled = true,
			points = 'Name',
		},
		ClassIcon = {
			enabled = true,
		},
	},
	config = {
		IsGroup = true,
	},
}

UF.Unit:Add('arena', Builder, Settings, Options, GroupBuilder)
