local UF = SUI.UF

---@param frame table
---@param DB table
local function Build(frame, DB)
	frame.PhaseIndicator = frame.raised:CreateTexture(nil, 'OVERLAY')
	frame.PhaseIndicator:Hide()
end

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	local function OptUpdate(option, val)
		--Update memory
		UF.CurrentSettings[unitName].elements.PhaseIndicator[option] = val
		--Update the DB
		UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.PhaseIndicator[option] = val
		--Update the screen
		UF.frames[unitName]:ElementUpdate('PhaseIndicator')
	end
	--local DB = UF.CurrentSettings[unitName].elements.PhaseIndicator
end

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = true,
	size = 20,
	position = {
		anchor = 'TOP',
		x = 0,
		y = 0,
	},
	config = {
		type = 'Indicator',
		DisplayName = 'Phase',
	},
}

UF.Elements:Register('PhaseIndicator', Build, nil, Options, Settings)
