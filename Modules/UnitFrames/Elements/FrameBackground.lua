local UF = SUI.UF
local L = SUI.L

-- ============================================================
-- ELEMENT BUILD
-- ============================================================

---@param frame table
---@param DB table
local function Build(frame, DB)
	local frameName = frame:GetName() or (frame.unitOnCreate .. tostring(frame))
	local instanceID = 'UnitFrame_' .. frameName

	local element = CreateFrame('Frame', nil, frame)
	element:SetSize(1, 1)
	element:Hide()
	element.instanceID = instanceID

	frame.FrameBackground = element
end

-- ============================================================
-- ELEMENT UPDATE (called by SUI ElementUpdate pipeline)
-- ============================================================

---@param frame table
---@param settings? table
local function Update(frame, settings)
	local element = frame.FrameBackground
	if not element then
		return
	end

	local DB = settings or element.DB
	if not DB then
		return
	end
	element.DB = DB

	local instanceID = element.instanceID
	if not instanceID then
		return
	end

	if not DB.enabled then
		SUI.Handlers.BackgroundBorder:SetVisible(instanceID, false)
		return
	end

	-- Deep copy settings so we don't mutate CurrentSettings
	local bgSettings = SUI:CopyData({}, DB)

	if not SUI.Handlers.BackgroundBorder.instances[instanceID] then
		SUI.Handlers.BackgroundBorder:Create(frame, instanceID, bgSettings)
	else
		SUI.Handlers.BackgroundBorder:Update(instanceID, bgSettings)
	end
	SUI.Handlers.BackgroundBorder:SetVisible(instanceID, true)
	SUI.Handlers.BackgroundBorder:RefreshClassColors(instanceID)
end

-- ============================================================
-- oUF ELEMENT REGISTRATION
-- Registers with oUF so unit changes trigger RefreshClassColors
-- ============================================================

local function oufUpdate(self, event, unit)
	if unit and unit ~= self.unit then
		return
	end

	local element = self.FrameBackground
	if not element or not element.instanceID then
		return
	end

	SUI.Handlers.BackgroundBorder:RefreshClassColors(element.instanceID)
end

local function oufEnable(self)
	local element = self.FrameBackground
	if not element then
		return false
	end

	element.__owner = self
	self:RegisterEvent('UNIT_FACTION', oufUpdate)
	return true
end

local function oufDisable(self)
	local element = self.FrameBackground
	if not element then
		return
	end

	self:UnregisterEvent('UNIT_FACTION', oufUpdate)

	if element.instanceID then
		SUI.Handlers.BackgroundBorder:SetVisible(element.instanceID, false)
	end
end

SUIUF:AddElement('FrameBackground', oufUpdate, oufEnable, oufDisable)

-- ============================================================
-- OPTIONS
-- ============================================================

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	local function getSettings()
		return UF.CurrentSettings[unitName].elements.FrameBackground or SUI.Handlers.BackgroundBorder.DefaultSettings
	end

	local function setSettings(newSettings)
		UF.CurrentSettings[unitName].elements.FrameBackground = newSettings
		UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.FrameBackground = newSettings
	end

	local function updateDisplay()
		local settings = getSettings()
		local instances = SUI.Handlers.BackgroundBorder:GetInstancesByPrefix('UnitFrame_SUI_UF_' .. unitName)
		for _, instanceID in ipairs(instances) do
			SUI.Handlers.BackgroundBorder:Update(instanceID, settings)
		end
	end

	local backgroundBorderOptions = SUI.Handlers.BackgroundBorder:GenerateCompleteOptions('UnitFrame_' .. unitName, getSettings, setSettings, updateDisplay)
	backgroundBorderOptions.order = 50

	OptionSet.args.FrameBackground = backgroundBorderOptions
end

-- ============================================================
-- SETTINGS & REGISTRATION
-- ============================================================

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = false,
	displayLevel = 0,
	background = {
		enabled = true,
		type = 'color',
		color = { 0.1, 0.1, 0.1, 0.8 },
		texture = 'Interface\\Buttons\\WHITE8X8',
		alpha = 0.8,
		classColor = false,
	},
	border = {
		enabled = false,
		sides = { top = true, bottom = true, left = true, right = true },
		size = 1,
		colors = {
			top = { 1, 1, 1, 1 },
			bottom = { 1, 1, 1, 1 },
			left = { 1, 1, 1, 1 },
			right = { 1, 1, 1, 1 },
		},
		classColors = { top = false, bottom = false, left = false, right = false },
	},
	config = {
		type = 'General',
		NoBulkUpdate = true,
		NoGenericOptions = true,
		DisplayName = 'Background & Border',
	},
}

UF.Elements:Register('FrameBackground', Build, Update, Options, Settings)
