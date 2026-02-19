local UF = SUI.UF

-- DefensiveIndicator Element
-- Shows defensive cooldowns (Ironbark, Pain Suppression, etc.) on raid/party frames
-- Uses Blizzard's CenterDefensiveBuff data to determine which defensive to display
-- This works in combat because we leverage Blizzard's pre-filtered aura decisions
--
-- Note: The Blizzard frame hooks and cache are managed by Core\oUF_Plugins\oUF_DefensiveIndicator.lua
-- which exposes SUI_DefensiveCache globally

-- Reference the global cache set up by the oUF plugin
-- Falls back to empty table if plugin hasn't loaded yet (shouldn't happen)
local function GetDefensiveCache()
	return SUI_DefensiveCache or {}
end

-- ============================================================
-- ELEMENT FUNCTIONS
-- ============================================================

---@param frame table
---@param DB table
local function Build(frame, DB)
	-- Create the defensive indicator frame
	local element = CreateFrame('Frame', '$parent_DefensiveIndicator', frame)
	element.DB = DB

	local size = DB.size or 24
	element:SetSize(size, size)
	element:SetPoint(DB.position.anchor or 'CENTER', frame, DB.position.anchor or 'CENTER', DB.position.x or 0, DB.position.y or 0)
	element:SetFrameLevel(frame:GetFrameLevel() + 10)

	-- Main icon texture
	local icon = element:CreateTexture(nil, 'ARTWORK')
	icon:SetAllPoints()
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- Trim edges
	element.icon = icon

	-- Cooldown frame
	local cooldown = CreateFrame('Cooldown', '$parent_Cooldown', element, 'CooldownFrameTemplate')
	cooldown:SetAllPoints()
	cooldown:SetDrawEdge(false)
	cooldown:SetDrawBling(false)
	element.cooldown = cooldown

	-- Border textures
	local borderSize = DB.borderSize or 2
	local borderColor = DB.borderColor or { 0, 0.8, 0, 1 } -- Green default

	element.borderLeft = element:CreateTexture(nil, 'OVERLAY')
	element.borderLeft:SetColorTexture(unpack(borderColor))
	element.borderLeft:SetPoint('TOPLEFT', 0, 0)
	element.borderLeft:SetPoint('BOTTOMLEFT', 0, 0)
	element.borderLeft:SetWidth(borderSize)

	element.borderRight = element:CreateTexture(nil, 'OVERLAY')
	element.borderRight:SetColorTexture(unpack(borderColor))
	element.borderRight:SetPoint('TOPRIGHT', 0, 0)
	element.borderRight:SetPoint('BOTTOMRIGHT', 0, 0)
	element.borderRight:SetWidth(borderSize)

	element.borderTop = element:CreateTexture(nil, 'OVERLAY')
	element.borderTop:SetColorTexture(unpack(borderColor))
	element.borderTop:SetPoint('TOPLEFT', borderSize, 0)
	element.borderTop:SetPoint('TOPRIGHT', -borderSize, 0)
	element.borderTop:SetHeight(borderSize)

	element.borderBottom = element:CreateTexture(nil, 'OVERLAY')
	element.borderBottom:SetColorTexture(unpack(borderColor))
	element.borderBottom:SetPoint('BOTTOMLEFT', borderSize, 0)
	element.borderBottom:SetPoint('BOTTOMRIGHT', -borderSize, 0)
	element.borderBottom:SetHeight(borderSize)

	-- Stack count text
	local count = element:CreateFontString(nil, 'OVERLAY', 'NumberFontNormal')
	count:SetPoint('BOTTOMRIGHT', -2, 2)
	element.count = count

	element:Hide()

	frame.DefensiveIndicator = element
end

---@param frame table
---@param data? table
local function Update(frame, data)
	local element = frame.DefensiveIndicator
	if not element then
		return
	end

	local DB = data or element.DB
	if not DB then
		return
	end
	element.DB = DB

	-- Check if enabled
	if not DB.enabled then
		element:Hide()
		return
	end

	local unit = frame.unit
	if not unit or not UnitExists(unit) then
		element:Hide()
		return
	end

	-- Get cached defensive from Blizzard's CenterDefensiveBuff
	-- The cache is populated by the oUF plugin via hooks to Blizzard's CompactUnitFrame
	local DefensiveCache = GetDefensiveCache()
	local cache = DefensiveCache[unit]
	local auraInstanceID = nil

	if cache then
		-- auraInstanceID stored as value (not key, since it can be secret)
		auraInstanceID = cache.auraInstanceID
	end

	if not auraInstanceID then
		element:Hide()
		return
	end

	-- Get aura data using the auraInstanceID
	-- This API is safe to call even in combat
	local auraData = nil
	local success = pcall(function()
		auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
	end)

	if not success or not auraData then
		element:Hide()
		return
	end

	-- Update size and position from settings
	local size = DB.size or 24
	element:SetSize(size, size)
	element:ClearAllPoints()
	element:SetPoint(DB.position.anchor or 'CENTER', frame, DB.position.anchor or 'CENTER', DB.position.x or 0, DB.position.y or 0)

	-- Set icon texture (use pcall for secret value protection)
	local textureSet = false
	pcall(function()
		element.icon:SetTexture(auraData.icon)
		textureSet = true
	end)

	if not textureSet then
		element:Hide()
		return
	end

	-- Update cooldown
	if element.cooldown then
		-- Use SetCooldownFromExpirationTime if available (safer with secrets)
		if element.cooldown.SetCooldownFromExpirationTime and auraData.expirationTime and auraData.duration then
			pcall(function()
				element.cooldown:SetCooldownFromExpirationTime(auraData.expirationTime, auraData.duration)
			end)
		end

		-- Check if aura has expiration using secret-safe API
		local hasExpiration = nil
		if C_UnitAuras.DoesAuraHaveExpirationTime then
			hasExpiration = C_UnitAuras.DoesAuraHaveExpirationTime(unit, auraInstanceID)
		end

		-- Show/hide cooldown using secret-safe API if available
		if element.cooldown.SetShownFromBoolean then
			element.cooldown:SetShownFromBoolean(hasExpiration, true, false)
		else
			element.cooldown:Show()
		end

		-- Settings
		element.cooldown:SetDrawSwipe(DB.showSwipe ~= false)
		element.cooldown:SetHideCountdownNumbers(not DB.showDuration)
	end

	-- Update stack count using secret-safe API
	element.count:SetText('')
	if C_UnitAuras.GetAuraApplicationDisplayCount then
		local stackText = C_UnitAuras.GetAuraApplicationDisplayCount(unit, auraInstanceID, 2, 99)
		if stackText then
			element.count:SetText(stackText)
		end
	end

	-- Update border
	local borderSize = DB.borderSize or 2
	local borderColor = DB.borderColor or { 0, 0.8, 0, 1 }
	local showBorder = DB.showBorder ~= false

	if showBorder then
		element.borderLeft:SetColorTexture(unpack(borderColor))
		element.borderLeft:SetWidth(borderSize)
		element.borderLeft:Show()

		element.borderRight:SetColorTexture(unpack(borderColor))
		element.borderRight:SetWidth(borderSize)
		element.borderRight:Show()

		element.borderTop:SetColorTexture(unpack(borderColor))
		element.borderTop:SetHeight(borderSize)
		element.borderTop:Show()

		element.borderBottom:SetColorTexture(unpack(borderColor))
		element.borderBottom:SetHeight(borderSize)
		element.borderBottom:Show()

		-- Inset icon from border
		element.icon:ClearAllPoints()
		element.icon:SetPoint('TOPLEFT', borderSize, -borderSize)
		element.icon:SetPoint('BOTTOMRIGHT', -borderSize, borderSize)
	else
		element.borderLeft:Hide()
		element.borderRight:Hide()
		element.borderTop:Hide()
		element.borderBottom:Hide()
		element.icon:SetAllPoints()
	end

	element:Show()
end

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	local L = SUI.L
	local ElementSettings = UF.CurrentSettings[unitName].elements.DefensiveIndicator

	local function OptUpdate(option, val)
		UF.CurrentSettings[unitName].elements.DefensiveIndicator[option] = val
		UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.DefensiveIndicator[option] = val
		UF.Unit[unitName]:ElementUpdate('DefensiveIndicator')
	end

	OptionSet.args.Display = {
		name = L['Display'],
		type = 'group',
		order = 10,
		inline = true,
		args = {
			size = {
				name = L['Size'],
				type = 'range',
				order = 1,
				min = 12,
				max = 64,
				step = 1,
				get = function()
					return ElementSettings.size
				end,
				set = function(_, val)
					OptUpdate('size', val)
				end,
			},
			showSwipe = {
				name = L['Show Cooldown Swipe'],
				type = 'toggle',
				order = 2,
				get = function()
					return ElementSettings.showSwipe ~= false
				end,
				set = function(_, val)
					OptUpdate('showSwipe', val)
				end,
			},
			showDuration = {
				name = L['Show Duration Text'],
				type = 'toggle',
				order = 3,
				get = function()
					return ElementSettings.showDuration
				end,
				set = function(_, val)
					OptUpdate('showDuration', val)
				end,
			},
		},
	}

	OptionSet.args.Border = {
		name = L['Border'],
		type = 'group',
		order = 20,
		inline = true,
		args = {
			showBorder = {
				name = L['Show Border'],
				type = 'toggle',
				order = 1,
				get = function()
					return ElementSettings.showBorder ~= false
				end,
				set = function(_, val)
					OptUpdate('showBorder', val)
				end,
			},
			borderSize = {
				name = L['Border Size'],
				type = 'range',
				order = 2,
				min = 1,
				max = 6,
				step = 1,
				get = function()
					return ElementSettings.borderSize or 2
				end,
				set = function(_, val)
					OptUpdate('borderSize', val)
				end,
			},
			borderColor = {
				name = L['Border Color'],
				type = 'color',
				order = 3,
				hasAlpha = true,
				get = function()
					local c = ElementSettings.borderColor or { 0, 0.8, 0, 1 }
					return c[1], c[2], c[3], c[4]
				end,
				set = function(_, r, g, b, a)
					OptUpdate('borderColor', { r, g, b, a })
				end,
			},
		},
	}
end

-- ============================================================
-- SETTINGS & REGISTRATION
-- ============================================================
-- Note: oUF element registration is handled by Core\oUF_Plugins\oUF_DefensiveIndicator.lua

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = false,
	size = 24,
	showSwipe = true,
	showDuration = true,
	showBorder = true,
	borderSize = 2,
	borderColor = { 0, 0.8, 0, 1 }, -- Green
	position = {
		anchor = 'CENTER',
		x = 0,
		y = 0,
	},
	config = {
		type = 'Auras',
		NoGenericOptions = true,
		DisplayName = 'Defensive',
	},
}

UF.Elements:Register('DefensiveIndicator', Build, Update, Options, Settings)
