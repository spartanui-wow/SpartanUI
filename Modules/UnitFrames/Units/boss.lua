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

local function GroupBuilder(holder)
	local db = holder.config
	for i = 1, 8 do
		local frame = SUIUF:Spawn('boss' .. i, 'SUI_UF_boss' .. i)
		frame:SetID(i)
		if i == 1 then
			frame:SetPoint('TOPLEFT', holder, 'TOPLEFT', 0, 0)
		else
			frame:SetPoint('TOP', holder.frames[i - 1], 'BOTTOM', 0, db.yOffset)
		end

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
	UF.Options:AddGroupLayout('boss', OptionSet)
end

---@type SUI.UF.Unit.Settings
local Settings = {
	width = 160,
	maxColumns = 1,
	unitsPerColumn = 5,
	columnSpacing = 0,
	yOffset = -30,
	elements = {
		-- Name = {
		-- },
		Portrait = {
			enabled = false,
		},
		Castbar = {
			enabled = true,
			Icon = {
				enabled = false,
			},
		},
		Health = {
			position = {
				anchor = 'TOP',
				relativeTo = 'Castbar',
				relativePoint = 'BOTTOM',
			},
			text = {
				['1'] = {
					text = '[SUIHealth(dynamic,displayDead)] [($>SUIHealth<$)(percentage,hideDead)]',
				},
			},
		},
		Power = {
			height = 5,
		},
	},
	config = {
		IsGroup = true,
		useUnitWatch = true,
	},
}

UF.Unit:Add('boss', Builder, Settings, Options, GroupBuilder)
