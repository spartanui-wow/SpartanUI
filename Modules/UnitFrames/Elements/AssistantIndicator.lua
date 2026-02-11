local UF = SUI.UF

---@param frame table
---@param DB table
local function Build(frame, DB)
	frame.AssistantIndicator = frame.raised:CreateTexture(nil, 'BORDER')
end

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = true,
	size = 12,
	position = {
		anchor = 'TOP',
		x = 0,
		y = 6,
	},
	config = {
		type = 'Indicator',
		DisplayName = 'Raid Assistant',
	},
}

UF.Elements:Register('AssistantIndicator', Build, nil, nil, Settings)
