local UF = SUI.UF

---@param frame table
---@param DB table
local function Build(frame, DB)
	local indicator = frame.raised:CreateTexture(nil, 'OVERLAY')

	-- oUF built-in QuestIndicator element uses UnitIsQuestBoss for updates
	frame.QuestIndicator = indicator
	-- SUI element system references by registered name
	frame.QuestMob = indicator
end

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	local function OptUpdate(option, val)
		UF.CurrentSettings[unitName].elements.QuestMob[option] = val
		UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.QuestMob[option] = val
		UF.frames[unitName]:ElementUpdate('QuestMob')
	end
end

---@type SUI.UF.Elements.Settings
local Settings = {
	position = {
		anchor = 'RIGHT',
	},
	config = {
		DisplayName = 'Quest',
		type = 'Indicator',
	},
}

UF.Elements:Register('QuestMob', Build, nil, Options, Settings)
