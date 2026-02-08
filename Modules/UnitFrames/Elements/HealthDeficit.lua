local UF = SUI.UF

-- ============================================================
-- HEALTH DEFICIT ELEMENT
-- Shows missing health as colored text (e.g., "-15K")
-- Thin wrapper around the SUIHealthDeficit oUF tag
-- ============================================================

--- Builds the tag text with optional custom color prefix
---@param DB table
---@return string
local function GetTagText(DB)
	return DB.text or '[SUIHealthDeficit]'
end

---@param frame table
---@param DB table
local function Build(frame, DB)
	frame.HealthDeficit = frame:CreateFontString(nil, 'OVERLAY')
	SUI.Font:Format(frame.HealthDeficit, DB.textSize or 10, 'UnitFrames')
	frame:Tag(frame.HealthDeficit, GetTagText(DB))
end

---@param frame table
local function Update(frame)
	local element = frame.HealthDeficit
	local DB = element.DB
	SUI.Font:Format(frame.HealthDeficit, DB.textSize or 10, 'UnitFrames')
	frame:Tag(frame.HealthDeficit, GetTagText(DB))
end

---@param frameName string
---@param OptionSet AceConfig.OptionsTable
local function Options(frameName, OptionSet)
	UF.Options:TextBasicDisplay(frameName, OptionSet, 'HealthDeficit')
end

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = false,
	textSize = 10,
	text = '[SUIHealthDeficit]',
	SetJustifyH = 'CENTER',
	SetJustifyV = 'MIDDLE',
	position = {
		anchor = 'CENTER',
		x = 0,
		y = -2,
	},
	config = {
		type = 'Indicator',
		DisplayName = 'Health Deficit',
	},
}

UF.Elements:Register('HealthDeficit', Build, Update, Options, Settings)
