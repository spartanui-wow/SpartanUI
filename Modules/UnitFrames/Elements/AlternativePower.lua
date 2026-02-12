local UF = SUI.UF

-- ============================================================
-- ALTERNATIVE POWER ELEMENT
-- Displays encounter-specific alternative power (NOT class power)
--
-- Examples: Torghast anima, Mythic+ event power, scenario power
-- Different from AdditionalPower (druid mana, rogue energy, etc.)
-- ============================================================

---@param frame table
---@param DB table
local function Build(frame, DB)
	local AlternativePower = CreateFrame('StatusBar', nil, frame)
	AlternativePower:SetHeight(DB.height or 8)
	AlternativePower:SetStatusBarTexture(UF:FindStatusBarTexture(DB.texture or 'Blizzard'))
	AlternativePower.colorPower = DB.colorPower ~= false -- Default to true
	AlternativePower:Hide() -- Hidden by default, oUF shows when alt power exists

	-- Background
	local bg = AlternativePower:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(AlternativePower)
	bg:SetTexture(UF:FindStatusBarTexture(DB.texture or 'Blizzard'))
	bg:SetVertexColor(unpack(DB.bg.color or { 1, 1, 1, 0.2 }))
	AlternativePower.bg = bg

	-- Position
	if DB.position then
		AlternativePower:ClearAllPoints()
		local relativeTo = DB.position.relativeTo and frame[DB.position.relativeTo] or frame
		AlternativePower:SetPoint(DB.position.anchor or 'TOP', relativeTo, DB.position.relativePoint or 'BOTTOM', DB.position.x or 0, DB.position.y or -1)
	else
		-- Default: below Power bar
		AlternativePower:SetPoint('TOP', frame.Power or frame, 'BOTTOM', 0, -1)
	end

	frame.AlternativePower = AlternativePower
end

---@param frame table
---@param settings? table
local function Update(frame, settings)
	local element = frame.AlternativePower
	if not element then
		return
	end

	local DB = settings or element.DB

	-- Update bar properties
	element:SetHeight(DB.height or 8)
	element:SetStatusBarTexture(UF:FindStatusBarTexture(DB.texture or 'Blizzard'))
	element.colorPower = DB.colorPower ~= false

	-- Update background
	if element.bg then
		element.bg:SetTexture(UF:FindStatusBarTexture(DB.texture or 'Blizzard'))
		element.bg:SetVertexColor(unpack(DB.bg.color or { 1, 1, 1, 0.2 }))
	end

	-- Update position
	element:ClearAllPoints()
	if DB.position then
		local relativeTo = DB.position.relativeTo and frame[DB.position.relativeTo] or frame
		element:SetPoint(DB.position.anchor or 'TOP', relativeTo, DB.position.relativePoint or 'BOTTOM', DB.position.x or 0, DB.position.y or -1)
	else
		element:SetPoint('TOP', frame.Power or frame, 'BOTTOM', 0, -1)
	end
end

---@param frameName string
---@param OptionSet AceConfig.OptionsTable
local function Options(frameName, OptionSet)
	OptionSet.args.general = {
		name = '',
		type = 'group',
		inline = true,
		order = 1,
		args = {
			height = {
				name = SUI.L['Height'],
				desc = SUI.L['Height of the alternative power bar'],
				type = 'range',
				min = 1,
				max = 20,
				step = 1,
				order = 1,
			},
			colorPower = {
				name = SUI.L['Color by power type'],
				desc = SUI.L['Automatically color the bar based on the alternative power type'],
				type = 'toggle',
				order = 2,
			},
		},
	}

	OptionSet.args.info = {
		name = SUI.L['About Alternative Power'],
		type = 'group',
		inline = true,
		order = 100,
		args = {
			description = {
				name = SUI.L['Alternative power bars appear in specific encounters and scenarios (Torghast, Mythic+ events, etc.). They are automatically shown by the game when needed.'],
				type = 'description',
				order = 1,
				fontSize = 'medium',
			},
		},
	}
end

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = true,
	height = 8,
	width = false,
	texture = 'Blizzard',
	colorPower = true,
	bg = {
		color = { 1, 1, 1, 0.2 },
	},
	position = {
		anchor = 'TOP',
		relativeTo = 'Power',
		relativePoint = 'BOTTOM',
		x = 0,
		y = -1,
	},
	config = {
		type = 'Indicator',
		DisplayName = 'Alternative power',
	},
}

UF.Elements:Register('AlternativePower', Build, Update, Options, Settings)
