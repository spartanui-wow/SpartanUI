local UF = SUI.UF
local elementList = {
	'Name',
	'Castbar',
	'Health',
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
	frame:SetParent(select(2, frame:GetPoint()))
end

local function GroupBuilder(holder)
	holder.elementList = elementList
end

local function Updater(frame)
	local db = frame.DB
	if not db or InCombatLockdown() then
		return
	end

	if db.enabled then
		frame:Enable()
	else
		frame:Disable()
	end
end

local function Options() end

---@type SUI.UF.Unit.Settings
local Settings = {
	enabled = false,
	width = 80,
	elements = {
		Health = {
			height = 25,
			text = {
				['1'] = {
					text = '[perhp]%',
					position = {
						y = 2,
						anchor = 'BOTTOM',
					},
				},
			},
		},
		Name = {
			enabled = true,
			height = 10,
			textSize = 10,
			text = '[SUI_ColorClass][name]',
			position = {
				y = 0,
			},
		},
	},
	config = {
		isChild = true,
		IsGroup = true,
	},
}

UF.Unit:Add('partytarget', Builder, Settings, nil, GroupBuilder, Updater)
