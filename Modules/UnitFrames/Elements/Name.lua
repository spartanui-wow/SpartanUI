local UF = SUI.UF

--- Builds the tag text with optional custom color prefix
---@param DB table
---@return string
local function GetTagText(DB)
	local text = DB.text or ''

	-- If custom color is enabled, prepend the hex color code
	if DB.textColor and DB.textColor.useCustomColor and DB.textColor.color then
		local r, g, b = unpack(DB.textColor.color)
		local hexColor = ('|cff%02x%02x%02x'):format((r or 1) * 255, (g or 1) * 255, (b or 1) * 255)
		text = hexColor .. text
	end

	return text
end

---@param frame table
---@param DB table
local function Build(frame, DB)
	frame.Name = frame.raised:CreateFontString(nil, 'OVERLAY')
	SUI.Font:Format(frame.Name, DB.textSize, 'UnitFrames')
	frame.Name:SetSize(frame:GetWidth(), 12)
	frame.Name:SetJustifyH(DB.SetJustifyH)
	frame.Name:SetJustifyV(DB.SetJustifyV)

	-- Position the name element based on position settings
	if DB.position then
		local relativeTo = frame
		local relativePoint = DB.position.anchor

		-- Handle nameplate-style positioning with relativeTo and relativePoint
		if DB.position.relativeTo and DB.position.relativePoint then
			if DB.position.relativeTo == 'Frame' then
				relativeTo = frame
			end
			relativePoint = DB.position.relativePoint
		end

		frame.Name:SetPoint(DB.position.anchor, relativeTo, relativePoint, DB.position.x or 0, DB.position.y or 0)
	end

	frame:Tag(frame.Name, GetTagText(DB))
end

---@param frame table
local function Update(frame)
	local DB = frame.Name.DB
	if not DB.enabled then
		frame.Name:Hide()
		return
	end
	frame.Name:Show()

	SUI.Font:Format(frame.Name, DB.textSize, 'UnitFrames')
	frame.Name:SetJustifyH(DB.SetJustifyH)
	frame.Name:SetJustifyV(DB.SetJustifyV)

	-- Update positioning
	if DB.position then
		local relativeTo = frame
		local relativePoint = DB.position.anchor

		-- Handle nameplate-style positioning with relativeTo and relativePoint
		if DB.position.relativeTo and DB.position.relativePoint then
			if DB.position.relativeTo == 'Frame' then
				relativeTo = frame
			end
			relativePoint = DB.position.relativePoint
		end

		frame.Name:ClearAllPoints()
		frame.Name:SetPoint(DB.position.anchor, relativeTo, relativePoint, DB.position.x or 0, DB.position.y or 0)
	end

	frame:Tag(frame.Name, GetTagText(DB))
end

---@param frameName string
---@param OptionSet AceConfig.OptionsTable
local function Options(frameName, OptionSet)
	UF.Options:TextBasicDisplay(frameName, OptionSet, 'Name')
end

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = true,
	width = false,
	height = 12,
	textSize = 12,
	text = '[difficulty][smartlevel] [SUI_ColorClass][name]',
	SetJustifyH = 'CENTER',
	SetJustifyV = 'MIDDLE',
	textColor = {
		useCustomColor = false,
		color = { 1, 1, 1 },
	},
	position = {
		anchor = 'TOP',
		x = 0,
		y = 15,
	},
	config = {
		type = 'Indicator',
	},
}

UF.Elements:Register('Name', Build, Update, Options, Settings)
