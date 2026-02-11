local UF = SUI.UF

---@param frame table
---@param DB table
local function Build(frame, DB)
	frame.LeaderIndicator = frame.raised:CreateTexture(nil, 'BORDER')
	frame.LeaderIndicator:Hide()
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
		DisplayName = 'Leader',
	},
}

UF.Elements:Register('LeaderIndicator', Build, nil, nil, Settings)
