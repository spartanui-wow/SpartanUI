local UF = SUI.UF

---@param frame table
---@param DB table
local function Build(frame, DB)
	frame.ReadyCheckIndicator = frame.raised:CreateTexture(nil, 'OVERLAY')
end

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = true,
	size = 35,
	position = {
		anchor = 'LEFT',
		x = 0,
		y = 0,
	},
	config = {
		type = 'Indicator',
		DisplayName = 'Ready Check',
	},
}

UF.Elements:Register('ReadyCheckIndicator', Build, nil, nil, Settings)
