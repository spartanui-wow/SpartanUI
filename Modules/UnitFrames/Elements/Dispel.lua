local UF = SUI.UF
local L = SUI.L

-- ============================================================
-- DISPEL ELEMENT
-- Comprehensive dispel indicator for raid/party frames
--
-- Features:
-- - Colored glow/border when dispellable debuff present
-- - Dispel type icon (Magic, Curse, Disease, Poison, Bleed)
-- - Optional debuff icon display (shows the actual debuff)
-- - Cooldown spiral on debuff icon
-- - Stack count display
--
-- API Support:
-- RETAIL 12.1+: Uses RAID_PLAYER_DISPELLABLE filter for accurate detection
-- RETAIL 12.0: Uses C_UnitAuras secret-value-safe APIs with color curves
-- CLASSIC: Uses traditional aura property access
-- ============================================================

-- Dispel type colors (used for all versions)
local DispelColors = {
	Magic = { r = 0.2, g = 0.6, b = 1.0 },
	Curse = { r = 0.6, g = 0.0, b = 1.0 },
	Disease = { r = 0.6, g = 0.4, b = 0.0 },
	Poison = { r = 0.0, g = 0.6, b = 0.0 },
	Bleed = { r = 0.8, g = 0.0, b = 0.0 },
	none = { r = 0.8, g = 0, b = 0 },
}

-- Dispel type enum values for Retail (from wago.tools/db2/SpellDispelType)
local DispelTypeEnum = {
	None = 0,
	Magic = 1,
	Curse = 2,
	Disease = 3,
	Poison = 4,
	Enrage = 9,
	Bleed = 11,
}

-- Map enum to string name for color lookup
local DispelEnumToName = {
	[1] = 'Magic',
	[2] = 'Curse',
	[3] = 'Disease',
	[4] = 'Poison',
	[9] = 'Bleed', -- Enrage uses Bleed color
	[11] = 'Bleed',
}

-- Check if new RAID_PLAYER_DISPELLABLE filter is available (12.1+)
local hasPlayerDispellableFilter = AuraUtil
	and AuraUtil.ForEachAura
	and pcall(function()
		local test = AuraUtil.CreateFilterString and AuraUtil.CreateFilterString('HARMFUL', 'RAID_PLAYER_DISPELLABLE')
		return test ~= nil
	end)

if not hasPlayerDispellableFilter then
	hasPlayerDispellableFilter = Enum and Enum.AuraFilter and Enum.AuraFilter.RaidPlayerDispellable ~= nil
end

-- Color curve for Retail 12.0 dispel type detection (cached)
local dispelColorCurve = nil

-- Build the color curve for Retail 12.0
local function GetDispelColorCurve()
	if dispelColorCurve then
		return dispelColorCurve
	end

	if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then
		return nil
	end

	dispelColorCurve = C_CurveUtil.CreateColorCurve()
	dispelColorCurve:SetType(Enum.LuaCurveType.Step)

	-- None = invisible (alpha 0)
	dispelColorCurve:AddPoint(DispelTypeEnum.None, CreateColor(0, 0, 0, 0))

	-- Add each dispel type with its color and full alpha
	for enumVal, colorName in pairs(DispelEnumToName) do
		local c = DispelColors[colorName]
		if c then
			dispelColorCurve:AddPoint(enumVal, CreateColor(c.r, c.g, c.b, 1))
		end
	end

	return dispelColorCurve
end

-- Get dispel type from color curve result
local function GetDispelTypeFromColor(r, g, b)
	for typeName, typeColor in pairs(DispelColors) do
		if typeName ~= 'none' and math.abs(r - typeColor.r) < 0.1 and math.abs(g - typeColor.g) < 0.1 and math.abs(b - typeColor.b) < 0.1 then
			return typeName
		end
	end
	return nil
end

-- Get player's dispellable types (what they can dispel) - used for 12.0 fallback
local playerDispelTypes = {}
local function UpdatePlayerDispelTypes()
	playerDispelTypes = {}

	local _, playerClass = UnitClass('player')
	if not playerClass then
		return
	end

	-- Determine what the player can dispel based on class/spec
	if playerClass == 'PRIEST' then
		playerDispelTypes.Magic = true
		playerDispelTypes.Disease = true
	elseif playerClass == 'PALADIN' then
		playerDispelTypes.Magic = true
		playerDispelTypes.Poison = true
		playerDispelTypes.Disease = true
	elseif playerClass == 'SHAMAN' then
		playerDispelTypes.Magic = true
		playerDispelTypes.Curse = true
		playerDispelTypes.Poison = true
	elseif playerClass == 'DRUID' then
		playerDispelTypes.Magic = true
		playerDispelTypes.Curse = true
		playerDispelTypes.Poison = true
	elseif playerClass == 'MAGE' then
		playerDispelTypes.Curse = true
	elseif playerClass == 'MONK' then
		playerDispelTypes.Magic = true
		playerDispelTypes.Poison = true
		playerDispelTypes.Disease = true
	elseif playerClass == 'EVOKER' then
		playerDispelTypes.Magic = true
		playerDispelTypes.Poison = true
		playerDispelTypes.Curse = true
		playerDispelTypes.Bleed = true
	elseif playerClass == 'WARLOCK' then
		playerDispelTypes.Magic = true
	end
end

-- ============================================================
-- NEW API: RAID_PLAYER_DISPELLABLE (12.1+)
-- ============================================================

-- Find dispellable debuff using new RAID_PLAYER_DISPELLABLE filter
---@param unit UnitId
---@return table|nil auraData
---@return string|nil dispelType
local function FindDispellableDebuff_NewAPI(unit)
	local foundAura = nil
	local foundDispelType = nil

	AuraUtil.ForEachAura(unit, 'HARMFUL|RAID_PLAYER_DISPELLABLE', nil, function(aura)
		foundAura = aura
		foundDispelType = aura.dispelName
		return true -- Stop iteration, take first
	end, true)

	return foundAura, foundDispelType
end

-- ============================================================
-- LEGACY API: Classic and Retail 12.0
-- ============================================================

-- Classic: Find dispellable debuff
---@param unit UnitId
---@param filterByPlayerDispels boolean
---@return table|nil auraData
---@return string|nil dispelType
local function FindDispellableDebuff_Classic(unit, filterByPlayerDispels)
	for i = 1, 40 do
		local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, 'HARMFUL')
		if not aura then
			break
		end

		local dispelName = aura.dispelName
		if dispelName then
			if not filterByPlayerDispels or playerDispelTypes[dispelName] then
				return aura, dispelName
			end
		end
	end
	return nil, nil
end

-- Retail 12.0: Find dispellable debuff using secret-value-safe approach
---@param unit UnitId
---@param filterByPlayerDispels boolean
---@return table|nil auraData (with auraInstanceID only for 12.0)
---@return string|nil dispelType
local function FindDispellableDebuff_Retail_Legacy(unit, filterByPlayerDispels)
	local curve = GetDispelColorCurve()
	if not curve then
		return nil, nil
	end

	for i = 1, 40 do
		local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, 'HARMFUL')
		if not aura then
			break
		end

		local auraInstanceID = aura.auraInstanceID
		if auraInstanceID then
			local success, color = pcall(function()
				return C_UnitAuras.GetAuraDispelTypeColor(unit, auraInstanceID, curve)
			end)
			if success and color then
				local r, g, b, a = color:GetRGBA()
				if a and a > 0 then
					local dispelType = GetDispelTypeFromColor(r, g, b)
					if dispelType then
						if not filterByPlayerDispels or playerDispelTypes[dispelType] then
							return { auraInstanceID = auraInstanceID }, dispelType
						end
					end
				end
			end
		end
	end
	return nil, nil
end

-- Main function to find dispellable debuff
---@param unit UnitId
---@param filterByPlayerDispels boolean
---@return table|nil auraData
---@return string|nil dispelType
local function FindDispellableDebuff(unit, filterByPlayerDispels)
	if not unit or not UnitExists(unit) then
		return nil, nil
	end

	if not UnitCanAssist('player', unit) then
		return nil, nil
	end

	if SUI.IsRetail then
		if filterByPlayerDispels and hasPlayerDispellableFilter then
			return FindDispellableDebuff_NewAPI(unit)
		else
			return FindDispellableDebuff_Retail_Legacy(unit, filterByPlayerDispels)
		end
	else
		return FindDispellableDebuff_Classic(unit, filterByPlayerDispels)
	end
end

-- ============================================================
-- ELEMENT BUILD
-- ============================================================

---@param frame table
---@param DB table
local function Build(frame, DB)
	-- Create container frame
	local element = CreateFrame('Frame', nil, frame)
	element:SetAllPoints(frame)
	element:SetFrameLevel(frame:GetFrameLevel() + 5)
	element.DB = DB

	-- Glow/border texture (full frame overlay)
	local glow = element:CreateTexture(nil, 'OVERLAY')
	glow:SetAllPoints(element)
	glow:SetTexture('Interface\\AddOns\\SpartanUI\\images\\statusbars\\pointed')
	glow:SetBlendMode('ADD')
	glow:SetAlpha(0.6)
	glow:Hide()
	element.glow = glow

	-- Dispel type icon (small corner icon)
	local typeIcon = element:CreateTexture(nil, 'OVERLAY')
	typeIcon:SetSize(16, 16)
	typeIcon:SetPoint('TOPRIGHT', element, 'TOPRIGHT', -2, -2)
	typeIcon:Hide()
	element.typeIcon = typeIcon

	-- Debuff icon container (center icon showing actual debuff)
	local iconSize = DB.iconSize or 24
	local debuffFrame = CreateFrame('Frame', nil, element)
	debuffFrame:SetSize(iconSize, iconSize)
	debuffFrame:SetPoint(
		DB.iconPosition and DB.iconPosition.anchor or 'CENTER',
		element,
		DB.iconPosition and DB.iconPosition.anchor or 'CENTER',
		DB.iconPosition and DB.iconPosition.x or 0,
		DB.iconPosition and DB.iconPosition.y or 0
	)
	debuffFrame:SetFrameLevel(element:GetFrameLevel() + 2)
	debuffFrame:Hide()
	element.debuffFrame = debuffFrame

	-- Debuff icon texture
	local debuffIcon = debuffFrame:CreateTexture(nil, 'ARTWORK')
	debuffIcon:SetAllPoints()
	debuffIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	element.debuffIcon = debuffIcon

	-- Debuff icon border (colored by dispel type)
	local debuffBorder = debuffFrame:CreateTexture(nil, 'OVERLAY')
	debuffBorder:SetAllPoints()
	debuffBorder:SetTexture('Interface\\Buttons\\UI-ActionButton-Border')
	debuffBorder:SetBlendMode('ADD')
	element.debuffBorder = debuffBorder

	-- Cooldown spiral
	local cooldown = CreateFrame('Cooldown', nil, debuffFrame, 'CooldownFrameTemplate')
	cooldown:SetAllPoints(debuffIcon)
	cooldown:SetDrawEdge(false)
	cooldown:SetHideCountdownNumbers(true)
	element.cooldown = cooldown

	-- Stack count
	local count = debuffFrame:CreateFontString(nil, 'OVERLAY')
	count:SetFont(SUI.Font:GetFont('UnitFrames'), 10, 'OUTLINE')
	count:SetPoint('BOTTOMRIGHT', debuffFrame, 'BOTTOMRIGHT', -1, 1)
	count:SetJustifyH('RIGHT')
	element.count = count

	-- Atlas names for dispel type icons
	element.dispelAtlases = {
		Magic = 'RaidFrame-Icon-DebuffMagic',
		Curse = 'RaidFrame-Icon-DebuffCurse',
		Disease = 'RaidFrame-Icon-DebuffDisease',
		Poison = 'RaidFrame-Icon-DebuffPoison',
		Bleed = 'RaidFrame-Icon-DebuffBleed',
	}

	element:Hide()
	frame.Dispel = element

	-- Initialize player dispel types for legacy fallback
	UpdatePlayerDispelTypes()
end

-- ============================================================
-- ELEMENT UPDATE
-- ============================================================

---@param frame table
---@param settings? table
local function Update(frame, settings)
	local element = frame.Dispel
	if not element then
		return
	end

	local DB = settings or element.DB
	if not DB or not DB.enabled then
		element:Hide()
		return
	end
	element.DB = DB

	local unit = frame.unit
	if not unit then
		element:Hide()
		return
	end

	local filterByPlayerDispels = DB.onlyShowDispellable ~= false
	local aura, dispelType = FindDispellableDebuff(unit, filterByPlayerDispels)

	if aura and dispelType then
		local color = DispelColors[dispelType] or DispelColors.none

		-- Update glow
		if element.glow then
			if DB.showGlow ~= false then
				element.glow:SetVertexColor(color.r, color.g, color.b, DB.glowAlpha or 0.6)
				element.glow:Show()
			else
				element.glow:Hide()
			end
		end

		-- Update type icon (small corner icon)
		if element.typeIcon then
			if DB.showTypeIcon ~= false then
				local atlas = element.dispelAtlases[dispelType]
				if atlas then
					element.typeIcon:SetAtlas(atlas)
					element.typeIcon:Show()
				else
					element.typeIcon:Hide()
				end
			else
				element.typeIcon:Hide()
			end
		end

		-- Update debuff icon (center icon showing actual debuff)
		if element.debuffFrame and DB.showDebuffIcon then
			local iconSize = DB.iconSize or 24
			element.debuffFrame:SetSize(iconSize, iconSize)

			-- Update position
			element.debuffFrame:ClearAllPoints()
			local anchor = DB.iconPosition and DB.iconPosition.anchor or 'CENTER'
			local x = DB.iconPosition and DB.iconPosition.x or 0
			local y = DB.iconPosition and DB.iconPosition.y or 0
			element.debuffFrame:SetPoint(anchor, element, anchor, x, y)

			local auraInstanceID = aura.auraInstanceID

			-- Set icon texture
			if SUI.IsRetail and not hasPlayerDispellableFilter then
				-- 12.0 Legacy: Need to fetch icon separately
				local iconSet = false
				if auraInstanceID then
					pcall(function()
						local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
						if auraData and auraData.icon then
							element.debuffIcon:SetTexture(auraData.icon)
							iconSet = true
						end
					end)
				end
				if not iconSet then
					element.debuffIcon:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')
				end
			else
				-- 12.1+ or Classic: Full aura data available
				if aura.icon then
					element.debuffIcon:SetTexture(aura.icon)
				end
			end

			-- Border color
			if element.debuffBorder then
				element.debuffBorder:SetVertexColor(color.r, color.g, color.b, 0.8)
			end

			-- Cooldown
			if element.cooldown then
				if SUI.IsRetail and not hasPlayerDispellableFilter then
					-- 12.0 Legacy: Use duration object API
					if auraInstanceID and C_UnitAuras.GetAuraDuration then
						pcall(function()
							local durationObj = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
							if durationObj and element.cooldown.SetCooldownFromDurationObject then
								element.cooldown:SetCooldownFromDurationObject(durationObj)
								element.cooldown:Show()
							else
								element.cooldown:Hide()
							end
						end)
					else
						element.cooldown:Hide()
					end
				else
					-- 12.1+ or Classic: Direct duration access
					local duration = aura.duration or 0
					local expiration = aura.expirationTime or 0
					if duration > 0 and expiration > 0 then
						element.cooldown:SetCooldown(expiration - duration, duration)
						element.cooldown:Show()
					else
						element.cooldown:Hide()
					end
				end
			end

			-- Stack count
			if element.count then
				if SUI.IsRetail and not hasPlayerDispellableFilter then
					-- 12.0 Legacy: Use safe API
					element.count:SetText('')
					if auraInstanceID and C_UnitAuras.GetAuraApplicationDisplayCount then
						pcall(function()
							local stackText = C_UnitAuras.GetAuraApplicationDisplayCount(unit, auraInstanceID, 2, 99)
							if stackText then
								element.count:SetText(stackText)
							end
						end)
					end
				else
					-- 12.1+ or Classic
					local applications = aura.applications or 0
					if applications > 1 then
						element.count:SetText(applications)
					else
						element.count:SetText('')
					end
				end
			end

			element.debuffFrame:Show()
		elseif element.debuffFrame then
			element.debuffFrame:Hide()
		end

		element:Show()
	else
		element:Hide()
	end
end

-- ============================================================
-- OPTIONS
-- ============================================================

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	local ElementSettings = UF.CurrentSettings[unitName].elements.Dispel

	local function OptUpdate(option, val)
		UF.CurrentSettings[unitName].elements.Dispel[option] = val
		UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.Dispel[option] = val
		UF.Unit[unitName]:ElementUpdate('Dispel')
	end

	OptionSet.args.Highlight = {
		name = L['Highlight'],
		type = 'group',
		order = 10,
		inline = true,
		args = {
			showGlow = {
				name = L['Show Glow'],
				desc = L['Show colored glow overlay when dispellable debuff is present'],
				type = 'toggle',
				order = 1,
				get = function()
					return ElementSettings.showGlow ~= false
				end,
				set = function(_, val)
					OptUpdate('showGlow', val)
				end,
			},
			glowAlpha = {
				name = L['Glow Opacity'],
				desc = L['Opacity of the dispel highlight glow'],
				type = 'range',
				order = 2,
				min = 0.1,
				max = 1,
				step = 0.1,
				get = function()
					return ElementSettings.glowAlpha or 0.6
				end,
				set = function(_, val)
					OptUpdate('glowAlpha', val)
				end,
			},
			showTypeIcon = {
				name = L['Show Type Icon'],
				desc = L['Show dispel type icon in corner (Magic, Curse, etc)'],
				type = 'toggle',
				order = 3,
				get = function()
					return ElementSettings.showTypeIcon ~= false
				end,
				set = function(_, val)
					OptUpdate('showTypeIcon', val)
				end,
			},
		},
	}

	OptionSet.args.DebuffIcon = {
		name = L['Debuff Icon'],
		type = 'group',
		order = 20,
		inline = true,
		args = {
			showDebuffIcon = {
				name = L['Show Debuff Icon'],
				desc = L['Show the actual debuff icon in center of frame'],
				type = 'toggle',
				order = 1,
				get = function()
					return ElementSettings.showDebuffIcon
				end,
				set = function(_, val)
					OptUpdate('showDebuffIcon', val)
				end,
			},
			iconSize = {
				name = L['Icon Size'],
				desc = L['Size of the debuff icon'],
				type = 'range',
				order = 2,
				min = 12,
				max = 48,
				step = 1,
				disabled = function()
					return not ElementSettings.showDebuffIcon
				end,
				get = function()
					return ElementSettings.iconSize or 24
				end,
				set = function(_, val)
					OptUpdate('iconSize', val)
				end,
			},
		},
	}

	OptionSet.args.Filter = {
		name = L['Filter'],
		type = 'group',
		order = 30,
		inline = true,
		args = {
			onlyShowDispellable = {
				name = L['Only Your Dispels'],
				desc = SUI.IsRetail and hasPlayerDispellableFilter and L['Only show debuffs you can dispel (uses RAID_PLAYER_DISPELLABLE filter)']
					or L['Only show debuffs you can dispel based on your class'],
				type = 'toggle',
				order = 1,
				get = function()
					return ElementSettings.onlyShowDispellable ~= false
				end,
				set = function(_, val)
					OptUpdate('onlyShowDispellable', val)
				end,
			},
		},
	}
end

-- ============================================================
-- SETTINGS & REGISTRATION
-- ============================================================

---@type SUI.UF.Elements.Settings
local Settings = {
	-- Disabled: Aura APIs return "secret" values in TWW 12.0 that can't be tested by addons
	enabled = false,
	-- Highlight options
	showGlow = true,
	glowAlpha = 0.6,
	showTypeIcon = true,
	-- Debuff icon options
	showDebuffIcon = false, -- Off by default, users can enable if wanted
	iconSize = 24,
	iconPosition = {
		anchor = 'CENTER',
		x = 0,
		y = 0,
	},
	-- Filter options
	onlyShowDispellable = true,
	-- Config
	config = {
		type = 'Indicator',
		DisplayName = 'Dispel',
	},
}

UF.Elements:Register('Dispel', Build, Update, Options, Settings)
