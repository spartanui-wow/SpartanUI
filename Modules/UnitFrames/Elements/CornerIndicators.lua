local UF = SUI.UF
local L = SUI.L

-- ============================================================
-- CORNER INDICATORS ELEMENT
-- Shows colored squares in frame corners for debuff types, specific spells, or buffs
-- Inspired by Cell/VuhDo corner indicator system
--
-- The oUF plugin (Core/oUF_Plugins/oUF_CornerIndicators.lua) handles:
-- - Aura scanning with secret-value-safe APIs
-- - Debuff type detection via color curves (Retail 12.0)
-- - Show/hide logic per corner
--
-- This element file handles:
-- - Building the visual textures (4 corner squares)
-- - Applying user settings (size, colors, tracking config)
-- - Options UI for per-corner configuration
-- ============================================================

local cornerAnchors = {
	TOPLEFT = { point = 'TOPLEFT', x = 1, y = -1 },
	TOPRIGHT = { point = 'TOPRIGHT', x = -1, y = -1 },
	BOTTOMLEFT = { point = 'BOTTOMLEFT', x = 1, y = 1 },
	BOTTOMRIGHT = { point = 'BOTTOMRIGHT', x = -1, y = 1 },
}

---@param frame table
---@param DB table
local function Build(frame, DB)
	local element = CreateFrame('Frame', nil, frame)
	element:SetAllPoints(frame)
	element:SetFrameLevel(frame:GetFrameLevel() + 8)
	element.DB = DB

	element.corners = {}

	local size = DB.cornerSize or 6
	for cornerKey, anchor in pairs(cornerAnchors) do
		local tex = element:CreateTexture(nil, 'OVERLAY')
		tex:SetSize(size, size)
		tex:SetPoint(anchor.point, element, anchor.point, anchor.x, anchor.y)
		tex:SetColorTexture(1, 1, 1, 1)
		tex:Hide()
		element.corners[cornerKey] = tex
	end

	frame.CornerIndicators = element
end

---@param frame table
---@param settings? table
local function Update(frame, settings)
	local element = frame.CornerIndicators
	if not element then
		return
	end

	local DB = settings or element.DB
	if not DB then
		return
	end
	element.DB = DB

	if not DB.enabled then
		for _, corner in pairs(element.corners) do
			corner:Hide()
		end
		return
	end

	-- Update corner sizes
	local size = DB.cornerSize or 6
	for cornerKey, tex in pairs(element.corners) do
		tex:SetSize(size, size)
		-- Reposition
		local anchor = cornerAnchors[cornerKey]
		if anchor then
			tex:ClearAllPoints()
			tex:SetPoint(anchor.point, element, anchor.point, anchor.x, anchor.y)
		end
	end

	-- Force oUF to update the element
	if element.ForceUpdate then
		element:ForceUpdate()
	end
end

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	local ElementSettings = UF.CurrentSettings[unitName].elements.CornerIndicators

	local function OptUpdate(path, val)
		-- Navigate nested path like 'corners.TOPLEFT.enabled'
		local parts = { strsplit('.', path) }
		local currentSettings = UF.CurrentSettings[unitName].elements.CornerIndicators
		local dbSettings = UF.DB.UserSettings[UF.DB.Style][unitName].elements.CornerIndicators

		-- Ensure DB path exists
		if not dbSettings then
			UF.DB.UserSettings[UF.DB.Style][unitName].elements.CornerIndicators = {}
			dbSettings = UF.DB.UserSettings[UF.DB.Style][unitName].elements.CornerIndicators
		end

		-- Set value in both current and db settings
		for i = 1, #parts - 1 do
			local key = parts[i]
			if not currentSettings[key] then
				currentSettings[key] = {}
			end
			if not dbSettings[key] then
				dbSettings[key] = {}
			end
			currentSettings = currentSettings[key]
			dbSettings = dbSettings[key]
		end
		local finalKey = parts[#parts]
		currentSettings[finalKey] = val
		dbSettings[finalKey] = val

		UF.Unit[unitName]:ElementUpdate('CornerIndicators')
	end

	OptionSet.args.cornerSize = {
		name = L['Corner Size'],
		type = 'range',
		order = 1,
		min = 3,
		max = 16,
		step = 1,
		get = function()
			return ElementSettings.cornerSize or 6
		end,
		set = function(_, val)
			OptUpdate('cornerSize', val)
		end,
	}

	local cornerNames = {
		TOPLEFT = L['Top Left'],
		TOPRIGHT = L['Top Right'],
		BOTTOMLEFT = L['Bottom Left'],
		BOTTOMRIGHT = L['Bottom Right'],
	}

	local trackTypes = {
		['debuffType'] = L['Debuff Type'],
		['spellID'] = L['Spell ID'],
		['buff'] = L['Buff Name'],
	}

	local order = 10
	for cornerKey, cornerLabel in pairs(cornerNames) do
		OptionSet.args[cornerKey] = {
			name = cornerLabel,
			type = 'group',
			inline = true,
			order = order,
			args = {
				enabled = {
					name = L['Enabled'],
					type = 'toggle',
					order = 1,
					get = function()
						return ElementSettings.corners and ElementSettings.corners[cornerKey] and ElementSettings.corners[cornerKey].enabled
					end,
					set = function(_, val)
						OptUpdate('corners.' .. cornerKey .. '.enabled', val)
					end,
				},
				trackType = {
					name = L['Track Type'],
					type = 'select',
					order = 2,
					values = trackTypes,
					get = function()
						return ElementSettings.corners and ElementSettings.corners[cornerKey] and ElementSettings.corners[cornerKey].trackType or 'debuffType'
					end,
					set = function(_, val)
						OptUpdate('corners.' .. cornerKey .. '.trackType', val)
					end,
				},
				trackValue = {
					name = L['Track Value'],
					desc = L['Debuff type (Magic, Curse, Poison, Disease), spell ID, or buff name'],
					type = 'input',
					order = 3,
					get = function()
						return ElementSettings.corners and ElementSettings.corners[cornerKey] and ElementSettings.corners[cornerKey].trackValue or ''
					end,
					set = function(_, val)
						OptUpdate('corners.' .. cornerKey .. '.trackValue', val)
					end,
				},
				color = {
					name = L['Color'],
					type = 'color',
					order = 4,
					hasAlpha = true,
					get = function()
						local c = ElementSettings.corners and ElementSettings.corners[cornerKey] and ElementSettings.corners[cornerKey].color or { 1, 1, 1, 1 }
						return c[1], c[2], c[3], c[4]
					end,
					set = function(_, r, g, b, a)
						OptUpdate('corners.' .. cornerKey .. '.color', { r, g, b, a })
					end,
				},
			},
		}
		order = order + 10
	end
end

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = false,
	cornerSize = 6,
	corners = {
		TOPLEFT = { enabled = true, trackType = 'debuffType', trackValue = 'Magic', color = { 0.2, 0.6, 1.0, 1 } },
		TOPRIGHT = { enabled = true, trackType = 'debuffType', trackValue = 'Curse', color = { 0.6, 0.0, 1.0, 1 } },
		BOTTOMLEFT = { enabled = true, trackType = 'debuffType', trackValue = 'Poison', color = { 0.0, 0.6, 0.0, 1 } },
		BOTTOMRIGHT = { enabled = true, trackType = 'debuffType', trackValue = 'Disease', color = { 0.6, 0.4, 0.0, 1 } },
	},
	config = {
		type = 'Indicator',
		DisplayName = 'Corner Indicators',
		NoBulkUpdate = true,
	},
}

UF.Elements:Register('CornerIndicators', Build, Update, Options, Settings)
