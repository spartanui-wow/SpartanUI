local UF = SUI.UF

---@param frame table
---@param DB table
local function Build(frame, DB)
	frame.SUI_RaidGroup = frame.raised:CreateTexture(nil, 'BORDER')

	frame.SUI_RaidGroup.Text = frame:CreateFontString(nil, 'BORDER')
	frame.SUI_RaidGroup.Text:SetPoint('CENTER', frame.SUI_RaidGroup, 'CENTER', 0, 0)
	SUI.Font:Format(frame.SUI_RaidGroup.Text, DB.textSize, 'UnitFrames')
end

---@param frame table
local function Update(frame)
	local DB = frame.SUI_RaidGroup.DB
	SUI.Font:Format(frame.SUI_RaidGroup.Text, DB.textSize, 'UnitFrames')
	frame.SUI_RaidGroup.Text:SetJustifyH(DB.SetJustifyH)
	frame.SUI_RaidGroup.Text:SetJustifyV(DB.SetJustifyV)
end

---@type SUI.UF.Elements.Settings
local Settings = {
	textSize = 13,
	SetJustifyH = 'CENTER',
	SetJustifyV = 'MIDDLE',
	position = {
		anchor = 'BOTTOMRIGHT',
		x = 0,
		y = 10,
	},
	config = {
		type = 'Indicator',
		DisplayName = 'Raid Group',
	},
}

UF.Elements:Register('SUI_RaidGroup', Build, Update, nil, Settings)
