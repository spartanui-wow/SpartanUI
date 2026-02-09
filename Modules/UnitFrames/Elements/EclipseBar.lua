local UF, L = SUI.UF, SUI.L

-- EclipseBar is only used in MOP Classic for Balance Druids
-- This element creates the Eclipse (sun/moon) power bar display

---@param frame table
---@param DB table
local function Build(frame, DB)
	-- Only build for player frame and only in MOP
	if frame.unitOnCreate ~= 'player' or not SUI.IsMOP then
		return
	end

	-- Check if player is a Druid
	local _, class = UnitClass('player')
	if class ~= 'DRUID' then
		return
	end

	-- Create the main eclipse bar container
	local EclipseBar = CreateFrame('Frame', nil, frame)
	EclipseBar:SetSize(DB.width or 150, DB.height or 14)

	-- Create the Lunar (moon) bar - fills when going towards lunar eclipse
	local LunarBar = CreateFrame('StatusBar', nil, EclipseBar)
	LunarBar:SetStatusBarTexture(UF:FindStatusBarTexture(DB.texture or 'Smoothv2'))
	LunarBar:SetStatusBarColor(0.3, 0.3, 0.8, 1) -- Blue/purple for lunar
	LunarBar:SetAllPoints(EclipseBar)
	EclipseBar.LunarBar = LunarBar

	-- Create the Solar (sun) bar - fills when going towards solar eclipse
	local SolarBar = CreateFrame('StatusBar', nil, EclipseBar)
	SolarBar:SetStatusBarTexture(UF:FindStatusBarTexture(DB.texture or 'Smoothv2'))
	SolarBar:SetStatusBarColor(1, 0.8, 0, 1) -- Yellow/orange for solar
	SolarBar:SetAllPoints(EclipseBar)
	SolarBar:SetReverseFill(true)
	EclipseBar.SolarBar = SolarBar

	-- Create background
	local bg = EclipseBar:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(EclipseBar)
	bg:SetTexture(UF:FindStatusBarTexture(DB.texture or 'Smoothv2'))
	bg:SetVertexColor(0.1, 0.1, 0.1, 0.8)
	EclipseBar.bg = bg

	-- Log creation
	if SUI.logger then
		SUI.logger.debug('EclipseBar: Created for player frame (MOP Druid)')
	end

	-- Register with oUF
	frame.EclipseBar = EclipseBar
end

---@param frame table
local function Update(frame)
	local element = frame.EclipseBar
	if not element then
		return
	end

	local DB = element.DB
	if not DB then
		return
	end

	-- Update size
	element:SetSize(DB.width or 150, DB.height or 14)

	-- Update position
	element:ClearAllPoints()
	if DB.position then
		if DB.position.relativeTo == 'Frame' then
			element:SetPoint(DB.position.anchor, frame, DB.position.relativePoint or DB.position.anchor, DB.position.x or 0, DB.position.y or 0)
		else
			local relativeTo = frame[DB.position.relativeTo]
			if relativeTo then
				element:SetPoint(DB.position.anchor, relativeTo, DB.position.relativePoint or DB.position.anchor, DB.position.x or 0, DB.position.y or 0)
			end
		end
	end

	-- Update textures
	if element.LunarBar then
		element.LunarBar:SetStatusBarTexture(UF:FindStatusBarTexture(DB.texture or 'Smoothv2'))
	end
	if element.SolarBar then
		element.SolarBar:SetStatusBarTexture(UF:FindStatusBarTexture(DB.texture or 'Smoothv2'))
	end
	if element.bg then
		element.bg:SetTexture(UF:FindStatusBarTexture(DB.texture or 'Smoothv2'))
	end
end

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	local ElementSettings = UF.CurrentSettings[unitName].elements.EclipseBar

	local function OptUpdate(option, val)
		UF.CurrentSettings[unitName].elements.EclipseBar[option] = val
		UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.EclipseBar[option] = val
		UF.Unit[unitName]:ElementUpdate('EclipseBar')
	end

	OptionSet.args.texture = {
		type = 'select',
		dialogControl = 'LSM30_Statusbar',
		order = 2,
		width = 'double',
		name = L['Bar Texture'],
		desc = L['Select the texture used for the eclipse bar'],
		values = AceGUIWidgetLSMlists.statusbar,
		get = function()
			return ElementSettings.texture
		end,
		set = function(_, val)
			OptUpdate('texture', val)
		end,
	}
end

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = true,
	width = 150,
	height = 14,
	texture = 'Smoothv2',
	alpha = 1,
	scale = 1,
	position = {
		anchor = 'BOTTOM',
		relativeTo = 'Power',
		relativePoint = 'TOP',
		x = 0,
		y = 5,
	},
	config = {
		NoBulkUpdate = true,
		type = 'StatusBar',
		DisplayName = 'Eclipse Bar',
		Description = 'Balance Druid Eclipse (Sun/Moon) power bar - MOP Classic only',
	},
}

UF.Elements:Register('EclipseBar', Build, Update, Options, Settings)
