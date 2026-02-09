local UF = SUI.UF

---@param frame table
---@param DB table
local function Build(frame, DB) end

---@param frame table
---@param DB? table
local function Update(frame, DB)
	local element = frame.WidgetXPBar
	local DB = element.DB
end

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
---@param DB? table
local function Options(unitName, OptionSet, DB)
	local function OptUpdate(option, val)
		--Update memory
		UF.CurrentSettings[unitName].elements.WidgetXPBar[option] = val
		--Update the DB
		UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.WidgetXPBar[option] = val
		--Update the screen
		UF.Unit:Get(unitName):ElementUpdate('WidgetXPBar')
	end
	--local DB = UF.CurrentSettings[unitName].elements.WidgetXPBar
end

local Settings = {
	config = {
		NoBulkUpdate = false,
	},
}

UF.Elements:Register('WidgetXPBar', Build, Update, Options, Settings)
