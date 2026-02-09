local UF, L = SUI.UF, SUI.L

---@param frame table
---@param DB table
local function Build(frame, DB)
	frame.Range = {
		insideAlpha = DB.insideAlpha,
		outsideAlpha = DB.outsideAlpha,
	}
end

---@param frame table
local function Update(frame)
	local DB = UF.CurrentSettings[frame.unitOnCreate].elements.Range
	frame.Range.insideAlpha = DB.insideAlpha
	frame.Range.outsideAlpha = DB.outsideAlpha
end

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	if unitName == 'player' then
		OptionSet.hidden = true
		return
	end
	OptionSet.args = {
		enabled = {
			name = L['Enabled'],
			type = 'toggle',
			order = 10,
			set = function(info, val)
				--Update memory
				UF.CurrentSettings[unitName].elements.Range.enabled = val
				--Update the DB
				UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.Range.enabled = val
				--Update the screen
				if val then
					UF.Unit[unitName]:EnableElement('Range')
				else
					UF.Unit[unitName]:DisableElement('Range')
				end
			end,
		},
		insideAlpha = {
			name = L['In range alpha'],
			type = 'range',
			min = 0,
			max = 1,
			step = 0.1,
		},
		outsideAlpha = {
			name = L['Out of range alpha'],
			type = 'range',
			min = 0,
			max = 1,
			step = 0.1,
		},
	}
end

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = true,
	insideAlpha = 1,
	outsideAlpha = 0.3,
	config = {
		NoBulkUpdate = true,
	},
}

UF.Elements:Register('Range', Build, Update, Options, Settings)
