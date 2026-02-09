local UF = SUI.UF

---@param frame table
---@param DB table
local function Build(frame, DB)
	local element = CreateFrame('Frame', frame:GetName() .. 'QuestIcons', frame)
	element:SetSize(20, 20)
	element:Hide()

	for _, object in ipairs({ 'Default', 'Item', 'Skull', 'Chat' }) do
		local icon = element:CreateTexture(nil, 'BORDER', nil, 1)
		icon.Text = element:CreateFontString(nil, 'OVERLAY')
		SUI.Font:Format(icon.Text, 12, 'Nameplates')
		icon:Hide()
		icon:SetAllPoints(element)

		element[object] = icon
	end

	-- QuestIcons.Item:SetTexCoord(unpack(E.TexCoords))
	element.Chat:SetTexture([[Interface\WorldMap\ChatBubble_64.PNG]])
	element.Chat:SetTexCoord(0, 0.5, 0.5, 1)

	frame.QuestMob = element
end

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	local function OptUpdate(option, val)
		--Update memory
		UF.CurrentSettings[unitName].elements.QuestMob[option] = val
		--Update the DB
		UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.QuestMob[option] = val
		--Update the screen
		UF.frames[unitName]:ElementUpdate('QuestMob')
	end
	--local DB = UF.CurrentSettings[unitName].elements.QuestMob
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
