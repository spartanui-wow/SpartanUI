local UF, L = SUI.UF, SUI.L

-- ============================================================
-- THREAT INDICATOR ELEMENT
-- Visual feedback for threat/aggro status
--
-- Styles:
-- 1. Glow - Frame texture with ADD blend mode (current default)
-- 2. Icon TL - Icon texture at top-left corner
-- 3. Icon TR - Icon texture at top-right corner
-- 4. Icon BL - Icon texture at bottom-left corner
-- 5. Icon BR - Icon texture at bottom-right corner
-- ============================================================

-- Threat icon texture (skull)
local THREAT_ICON = 'Interface\\TargetingFrame\\UI-TargetingFrame-Skull'

---@param frame table
---@param DB table
local function Build(frame, DB)
	local style = DB.style or 'glow'

	if style == 'aggro' then
		-- Aggro style: Blizzard raid frame aggro border
		local ThreatIndicator = frame:CreateTexture(nil, 'OVERLAY')
		ThreatIndicator:SetAtlas('RaidFrame-AgroFrame')
		ThreatIndicator.feedbackUnit = 'PLAYER'
		ThreatIndicator:Hide()

		ThreatIndicator:SetPoint('TOPLEFT', frame, 'TOPLEFT', -3, 3)
		ThreatIndicator:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 3, -3)

		frame.ThreatIndicator = ThreatIndicator
	elseif style == 'glow' then
		-- Glow style: texture around frame border
		local ThreatIndicator = frame:CreateTexture(nil, 'BACKGROUND')
		ThreatIndicator:SetTexture('Interface\\AddOns\\SpartanUI\\images\\HighlightBar')
		ThreatIndicator:SetBlendMode('ADD')
		ThreatIndicator.feedbackUnit = 'PLAYER'
		ThreatIndicator:Hide()

		-- Position around frame border
		ThreatIndicator:SetPoint('TOPLEFT', frame, 'TOPLEFT', -3, 3)
		ThreatIndicator:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 3, -3)

		frame.ThreatIndicator = ThreatIndicator
	elseif style:match('^icon_') then
		-- Icon style: skull icon at corner
		local ThreatIndicator = CreateFrame('Frame', nil, frame)
		ThreatIndicator:SetSize(DB.iconSize or 20, DB.iconSize or 20)
		ThreatIndicator.feedbackUnit = 'PLAYER'
		ThreatIndicator:Hide()

		local icon = ThreatIndicator:CreateTexture(nil, 'OVERLAY')
		icon:SetAllPoints(ThreatIndicator)
		icon:SetTexture(THREAT_ICON)
		ThreatIndicator.icon = icon

		-- Position based on corner
		local position = style:match('^icon_(.+)$') -- Extract TL/TR/BL/BR
		if position == 'TL' then
			ThreatIndicator:SetPoint('TOPLEFT', frame, 'TOPLEFT', 2, -2)
		elseif position == 'TR' then
			ThreatIndicator:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -2, -2)
		elseif position == 'BL' then
			ThreatIndicator:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 2, 2)
		elseif position == 'BR' then
			ThreatIndicator:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -2, 2)
		end

		frame.ThreatIndicator = ThreatIndicator
	end
end

---@param frame table
---@param settings? table
local function Update(frame, settings)
	local element = frame.ThreatIndicator
	if not element then
		return
	end

	local DB = settings or element.DB

	-- Rebuild if style changed
	local currentStyle = DB.style or 'glow'
	local needsRebuild = false

	if (currentStyle == 'glow' or currentStyle == 'aggro') and element:GetObjectType() ~= 'Texture' then
		needsRebuild = true
	elseif currentStyle:match('^icon_') and element:GetObjectType() ~= 'Frame' then
		needsRebuild = true
	end

	if needsRebuild then
		-- Hide old element
		element:Hide()
		element:SetParent(nil)

		-- Rebuild with new style
		Build(frame, DB)
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
			style = {
				name = L['Threat indicator style'],
				desc = L['Visual style for displaying threat/aggro status'],
				type = 'select',
				order = 1,
				values = {
					['aggro'] = L['Aggro border'],
					['glow'] = L['Glow (frame border)'],
					['icon_TL'] = L['Icon - Top Left'],
					['icon_TR'] = L['Icon - Top Right'],
					['icon_BL'] = L['Icon - Bottom Left'],
					['icon_BR'] = L['Icon - Bottom Right'],
				},
			},
			iconSize = {
				name = L['Icon size'],
				desc = L['Size of threat icon (for icon styles only)'],
				type = 'range',
				min = 10,
				max = 40,
				step = 1,
				order = 2,
				disabled = function()
					local style = UF.CurrentSettings[frameName].elements.ThreatIndicator.style
					return not style or style == 'glow' or style == 'aggro'
				end,
			},
		},
	}

	OptionSet.args.colors = {
		name = L['Threat Colors'],
		type = 'group',
		inline = true,
		order = 2,
		args = {
			color0 = {
				name = L['Not in threat table'],
				type = 'color',
				order = 1,
				hasAlpha = true,
				get = function()
					local c = UF.CurrentSettings[frameName].elements.ThreatIndicator.colors[0]
					return c[1], c[2], c[3], c[4]
				end,
				set = function(_, r, g, b, a)
					UF.CurrentSettings[frameName].elements.ThreatIndicator.colors[0] = { r, g, b, a }
					UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements.ThreatIndicator.colors[0] = { r, g, b, a }
					UF.Unit[frameName]:ElementUpdate('ThreatIndicator')
				end,
			},
			color1 = {
				name = L['Gaining threat'],
				type = 'color',
				order = 2,
				hasAlpha = true,
				get = function()
					local c = UF.CurrentSettings[frameName].elements.ThreatIndicator.colors[1]
					return c[1], c[2], c[3], c[4]
				end,
				set = function(_, r, g, b, a)
					UF.CurrentSettings[frameName].elements.ThreatIndicator.colors[1] = { r, g, b, a }
					UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements.ThreatIndicator.colors[1] = { r, g, b, a }
					UF.Unit[frameName]:ElementUpdate('ThreatIndicator')
				end,
			},
			color2 = {
				name = L['High threat'],
				type = 'color',
				order = 3,
				hasAlpha = true,
				get = function()
					local c = UF.CurrentSettings[frameName].elements.ThreatIndicator.colors[2]
					return c[1], c[2], c[3], c[4]
				end,
				set = function(_, r, g, b, a)
					UF.CurrentSettings[frameName].elements.ThreatIndicator.colors[2] = { r, g, b, a }
					UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements.ThreatIndicator.colors[2] = { r, g, b, a }
					UF.Unit[frameName]:ElementUpdate('ThreatIndicator')
				end,
			},
			color3 = {
				name = L['Tanking / Maximum threat'],
				type = 'color',
				order = 4,
				hasAlpha = true,
				get = function()
					local c = UF.CurrentSettings[frameName].elements.ThreatIndicator.colors[3]
					return c[1], c[2], c[3], c[4]
				end,
				set = function(_, r, g, b, a)
					UF.CurrentSettings[frameName].elements.ThreatIndicator.colors[3] = { r, g, b, a }
					UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements.ThreatIndicator.colors[3] = { r, g, b, a }
					UF.Unit[frameName]:ElementUpdate('ThreatIndicator')
				end,
			},
		},
	}
end

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = true,
	style = 'glow', -- 'glow', 'icon_TL', 'icon_TR', 'icon_BL', 'icon_BR'
	iconSize = 20,
	colors = {
		[0] = { 0.69, 0.69, 0.69, 1 }, -- Not in threat table
		[1] = { 1, 1, 0.47, 1 }, -- Gaining threat (yellow)
		[2] = { 1, 0.6, 0, 1 }, -- High threat (orange)
		[3] = { 1, 0, 0, 1 }, -- Tanking (red)
	},
	config = {
		type = 'Indicator',
		DisplayName = 'Threat',
	},
}

UF.Elements:Register('ThreatIndicator', Build, Update, Options, Settings)
