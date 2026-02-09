local UF = SUI.UF
local L = SUI.L

-- ============================================================
-- RAID DEBUFFS ELEMENT
-- Shows a large center icon for important debuffs (CC, boss mechanics)
--
-- The oUF plugin (Core/oUF_Plugins/oUF_RaidDebuffs.lua) handles:
-- - Finding the most important debuff using priority system
-- - Secret-value-safe APIs for Retail
-- - Dispel type detection and border coloring
-- - Duration display via cooldown spiral or text
--
-- This element file handles:
-- - Building the visual frame (icon, cooldown, border, text)
-- - Applying user settings (size, position, enabled state)
-- - Options UI
-- ============================================================

---@param frame table
---@param DB table
local function Build(frame, DB)
	-- Create the main container
	local element = CreateFrame('Frame', nil, frame)
	element.DB = DB
	element:SetSize(DB.size or 32, DB.size or 32)
	element:SetPoint(DB.position and DB.position.anchor or 'CENTER', frame, DB.position and DB.position.anchor or 'CENTER', DB.position and DB.position.x or 0, DB.position and DB.position.y or 0)
	element:SetFrameLevel(frame:GetFrameLevel() + 10)

	-- Background
	local bg = element:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.5)
	element.bg = bg

	-- Icon texture
	local icon = element:CreateTexture(nil, 'ARTWORK')
	icon:SetPoint('TOPLEFT', element, 'TOPLEFT', 2, -2)
	icon:SetPoint('BOTTOMRIGHT', element, 'BOTTOMRIGHT', -2, 2)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	element.icon = icon

	-- Border (colored by dispel type)
	local border = element:CreateTexture(nil, 'OVERLAY')
	border:SetAllPoints()
	border:SetTexture('Interface\\Buttons\\UI-ActionButton-Border')
	border:SetBlendMode('ADD')
	element.border = border

	-- Cooldown spiral
	local cd = CreateFrame('Cooldown', nil, element, 'CooldownFrameTemplate')
	cd:SetAllPoints(icon)
	cd:SetDrawEdge(false)
	cd:SetHideCountdownNumbers(true)
	element.cd = cd

	-- Duration text (for Classic, or as fallback)
	local time = element:CreateFontString(nil, 'OVERLAY')
	time:SetFont(SUI.Font:GetFont('UnitFrames'), 12, 'OUTLINE')
	time:SetPoint('CENTER', element, 'CENTER', 0, 0)
	time:SetJustifyH('CENTER')
	element.time = time

	-- Stack count
	local count = element:CreateFontString(nil, 'OVERLAY')
	count:SetFont(SUI.Font:GetFont('UnitFrames'), 10, 'OUTLINE')
	count:SetPoint('BOTTOMRIGHT', element, 'BOTTOMRIGHT', -1, 1)
	count:SetJustifyH('RIGHT')
	element.count = count

	element:Hide()
	frame.RaidDebuffs = element
end

---@param frame table
---@param settings? table
local function Update(frame, settings)
	local element = frame.RaidDebuffs
	if not element then
		return
	end

	local DB = settings or element.DB
	if not DB then
		return
	end
	element.DB = DB

	-- Store showDuration setting for oUF plugin to use
	element.showDuration = DB.showDuration

	-- Check if enabled
	if not DB.enabled then
		element:Hide()
		return
	end

	-- Update size from settings
	local size = DB.size or 32
	element:SetSize(size, size)

	-- Update position
	element:ClearAllPoints()
	local anchor = DB.position and DB.position.anchor or 'CENTER'
	local x = DB.position and DB.position.x or 0
	local y = DB.position and DB.position.y or 0
	element:SetPoint(anchor, frame, anchor, x, y)

	-- Force oUF to update the element
	if element.ForceUpdate then
		element:ForceUpdate()
	end
end

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	local ElementSettings = UF.CurrentSettings[unitName].elements.RaidDebuffs

	local function OptUpdate(option, val)
		UF.CurrentSettings[unitName].elements.RaidDebuffs[option] = val
		UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.RaidDebuffs[option] = val
		UF.Unit[unitName]:ElementUpdate('RaidDebuffs')
	end

	OptionSet.args.size = {
		name = L['Size'],
		desc = L['Size of the debuff icon'],
		type = 'range',
		order = 1,
		min = 16,
		max = 64,
		step = 1,
		get = function()
			return ElementSettings.size or 32
		end,
		set = function(_, val)
			OptUpdate('size', val)
		end,
	}

	OptionSet.args.showDuration = {
		name = L['Show Duration'],
		desc = L['Show duration text on the icon (Classic only - Retail uses cooldown spiral)'],
		type = 'toggle',
		order = 2,
		get = function()
			return ElementSettings.showDuration ~= false
		end,
		set = function(_, val)
			OptUpdate('showDuration', val)
		end,
	}
end

---@type SUI.UF.Elements.Settings
local Settings = {
	-- Disabled: Aura APIs return "secret" values in TWW 12.0 that can't be tested by addons
	enabled = false,
	size = 32,
	showDuration = true,
	position = {
		anchor = 'CENTER',
		x = 0,
		y = 0,
	},
	config = {
		type = 'Indicator',
		DisplayName = 'Raid Debuffs',
	},
}

UF.Elements:Register('RaidDebuffs', Build, Update, Options, Settings)
