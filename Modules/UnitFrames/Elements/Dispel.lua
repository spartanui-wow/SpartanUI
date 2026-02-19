local UF = SUI.UF
local L = SUI.L

-- Dispel type colors
local DispelColors = {
	Magic = { r = 0.2, g = 0.6, b = 1.0 },
	Curse = { r = 0.6, g = 0.0, b = 1.0 },
	Disease = { r = 0.6, g = 0.4, b = 0.0 },
	Poison = { r = 0.0, g = 0.6, b = 0.0 },
	Bleed = { r = 0.8, g = 0.0, b = 0.0 },
	none = { r = 0.8, g = 0, b = 0 },
}

-- Dispel type enum values (from wago.tools/db2/SpellDispelType)
local DispelTypeEnum = {
	None = 0,
	Magic = 1,
	Curse = 2,
	Disease = 3,
	Poison = 4,
	Enrage = 9,
	Bleed = 11,
}

local ALL_DISPEL_ENUMS = { 0, 1, 2, 3, 4, 9, 11 }

-- Map enum to string name
local DispelEnumToName = {
	[1] = 'Magic',
	[2] = 'Curse',
	[3] = 'Disease',
	[4] = 'Poison',
	[9] = 'Bleed',
	[11] = 'Bleed',
}

-- Atlas names for dispel type icons
local DispelAtlases = {
	Magic = 'RaidFrame-Icon-DebuffMagic',
	Curse = 'RaidFrame-Icon-DebuffCurse',
	Disease = 'RaidFrame-Icon-DebuffDisease',
	Poison = 'RaidFrame-Icon-DebuffPoison',
	Bleed = 'RaidFrame-Icon-DebuffBleed',
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

-- ============================================================
-- COLOR CURVES (cached, rebuilt when needed)
-- ============================================================

local borderColorCurve = nil
local typeIconCurves = {} -- Per-type curves for icon visibility

local function BuildBorderCurve(alpha)
	if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then
		return nil
	end

	local curve = C_CurveUtil.CreateColorCurve()
	curve:SetType(Enum.LuaCurveType.Step)

	-- None = invisible
	curve:AddPoint(DispelTypeEnum.None, CreateColor(0, 0, 0, 0))

	for _, enumVal in ipairs(ALL_DISPEL_ENUMS) do
		if enumVal ~= 0 then
			local colorName = DispelEnumToName[enumVal]
			local c = DispelColors[colorName]
			if c then
				curve:AddPoint(enumVal, CreateColor(c.r, c.g, c.b, alpha))
			end
		end
	end

	return curve
end

local function GetBorderCurve(alpha)
	if borderColorCurve then
		return borderColorCurve
	end
	borderColorCurve = BuildBorderCurve(alpha or 0.8)
	return borderColorCurve
end

-- Per-type icon curve: only targetEnum has alpha > 0, all others alpha = 0
local function GetTypeIconCurve(targetEnum, iconAlpha)
	if typeIconCurves[targetEnum] then
		return typeIconCurves[targetEnum]
	end

	if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then
		return nil
	end

	local curve = C_CurveUtil.CreateColorCurve()
	curve:SetType(Enum.LuaCurveType.Step)

	for _, enumVal in ipairs(ALL_DISPEL_ENUMS) do
		if enumVal == targetEnum then
			curve:AddPoint(enumVal, CreateColor(1, 1, 1, iconAlpha or 1.0))
		else
			curve:AddPoint(enumVal, CreateColor(1, 1, 1, 0))
		end
	end

	typeIconCurves[targetEnum] = curve
	return curve
end

local function InvalidateCurves()
	borderColorCurve = nil
	typeIconCurves = {}
end

-- ============================================================
-- PLAYER DISPEL TYPES (for 12.0 fallback)
-- ============================================================

local playerDispelTypes = {}
local function UpdatePlayerDispelTypes()
	playerDispelTypes = {}

	local _, playerClass = UnitClass('player')
	if not playerClass then
		return
	end

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
-- AURA DETECTION
-- ============================================================

-- 12.1+: Use RAID_PLAYER_DISPELLABLE filter
---@param unit UnitId
---@return table|nil auraData
---@return string|nil dispelType
local function FindDispellableDebuff_NewAPI(unit)
	local foundAura = nil
	local foundDispelType = nil

	AuraUtil.ForEachAura(unit, 'HARMFUL|RAID_PLAYER_DISPELLABLE', nil, function(aura)
		foundAura = aura
		foundDispelType = aura.dispelName
		return true
	end, true)

	return foundAura, foundDispelType
end

-- Classic: Direct aura property access
---@param unit UnitId
---@param filterByPlayerDispels boolean
---@return table|nil auraData
---@return string|nil dispelType
---@return number|nil slotIndex
local function FindDispellableDebuff_Classic(unit, filterByPlayerDispels)
	for i = 1, 40 do
		local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, 'HARMFUL')
		if not aura then
			break
		end

		local dispelName = aura.dispelName
		if dispelName then
			if not filterByPlayerDispels or playerDispelTypes[dispelName] then
				return aura, dispelName, i
			end
		end
	end
	return nil, nil, nil
end

-- Retail 12.0: Use truthiness on dispelName (safe with secrets) + class filter
---@param unit UnitId
---@param filterByPlayerDispels boolean
---@return table|nil auraData
---@return string|nil dispelType
local function FindDispellableDebuff_Retail_Legacy(unit, filterByPlayerDispels)
	for i = 1, 40 do
		local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, 'HARMFUL')
		if not aura then
			break
		end

		-- dispelName truthiness is safe with secrets - nil means not dispellable
		local dispelName = aura.dispelName
		if dispelName then
			if not filterByPlayerDispels then
				return aura, dispelName
			end
			-- Filter by player class: need accessible dispelName for table lookup
			if SUI.BlizzAPI.canaccessvalue(dispelName) then
				if playerDispelTypes[dispelName] then
					return aura, dispelName
				end
			else
				-- dispelName is secret but truthy = there IS a dispel type
				-- We can't filter by player class without knowing the type,
				-- so show it (better to show than miss a dispellable debuff)
				return aura, dispelName
			end
		end
	end
	return nil, nil
end

---@param unit UnitId
---@param filterByPlayerDispels boolean
---@return table|nil auraData
---@return string|nil dispelType
---@return number|nil slotIndex Classic only; nil on Retail
local function FindDispellableDebuff(unit, filterByPlayerDispels)
	if not unit or not UnitExists(unit) then
		return nil, nil, nil
	end

	if not UnitCanAssist('player', unit) then
		return nil, nil, nil
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
-- HELPERS: Create StatusBar border
-- ============================================================

local function CreateBorderStatusBar(parent)
	local bar = CreateFrame('StatusBar', nil, parent)
	bar:SetStatusBarTexture('Interface\\Buttons\\WHITE8x8')
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	bar:GetStatusBarTexture():SetBlendMode('BLEND')
	bar:Hide()
	return bar
end

-- ============================================================
-- ELEMENT BUILD
-- ============================================================

---@param frame table
---@param DB table
local function Build(frame, DB)
	local element = CreateFrame('Frame', nil, frame)
	element:SetAllPoints(frame)
	element:SetFrameLevel(frame:GetFrameLevel() + 10)
	element.DB = DB

	-- 4 StatusBar borders (secret-value-safe coloring via SetVertexColor)
	element.borderTop = CreateBorderStatusBar(element)
	element.borderBottom = CreateBorderStatusBar(element)
	element.borderLeft = CreateBorderStatusBar(element)
	element.borderRight = CreateBorderStatusBar(element)

	-- Per-type StatusBar icons (one per dispel type, curve alpha controls visibility)
	-- Using StatusBars so SetVertexColor with secret alpha from curves works natively
	element.typeIcons = {}
	for typeName, atlas in pairs(DispelAtlases) do
		local bar = CreateFrame('StatusBar', nil, element)
		bar:SetStatusBarTexture(atlas)
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(1)
		bar:Hide()
		element.typeIcons[typeName] = bar
	end

	-- Debuff icon container
	local debuffFrame = CreateFrame('Frame', nil, element)
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
	debuffBorder:SetPoint('TOPLEFT', debuffFrame, 'TOPLEFT', -1, 1)
	debuffBorder:SetPoint('BOTTOMRIGHT', debuffFrame, 'BOTTOMRIGHT', 1, -1)
	debuffBorder:SetTexture('Interface\\Buttons\\UI-Debuff-Border')
	element.debuffBorder = debuffBorder

	-- Cooldown spiral
	local cooldown = CreateFrame('Cooldown', nil, debuffFrame, 'CooldownFrameTemplate')
	cooldown:SetAllPoints(debuffIcon)
	cooldown:SetDrawEdge(false)
	cooldown:SetHideCountdownNumbers(true)
	if cooldown.SetUseAuraDisplayTime then
		cooldown:SetUseAuraDisplayTime(true)
	end
	element.cooldown = cooldown

	-- Stack count
	local count = debuffFrame:CreateFontString(nil, 'OVERLAY')
	count:SetFont(SUI.Font:GetFont('UnitFrames'), 10, 'OUTLINE')
	count:SetPoint('BOTTOMRIGHT', debuffFrame, 'BOTTOMRIGHT', -1, 1)
	count:SetJustifyH('RIGHT')
	element.count = count

	-- Tooltip on hover
	debuffFrame:EnableMouse(true)
	local function RefreshTooltip(self)
		local tooltipUnit = self._tooltipUnit
		local instanceID = self._tooltipInstanceID
		local slotIndex = self._tooltipSlotIndex
		if not tooltipUnit then
			return
		end
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		if SUI.IsRetail and instanceID then
			GameTooltip:SetUnitDebuffByAuraInstanceID(tooltipUnit, instanceID, 'HARMFUL')
		elseif slotIndex then
			GameTooltip:SetUnitAura(tooltipUnit, slotIndex, 'HARMFUL')
		end
	end
	debuffFrame:SetScript('OnEnter', function(self)
		if not self._tooltipUnit then
			return
		end
		RefreshTooltip(self)
		GameTooltip:Show()
		self:SetScript('OnUpdate', function()
			if GameTooltip:IsOwned(self) then
				RefreshTooltip(self)
			end
		end)
	end)
	debuffFrame:SetScript('OnLeave', function(self)
		GameTooltip:Hide()
		self:SetScript('OnUpdate', nil)
	end)

	element:Hide()
	frame.Dispel = element

	UpdatePlayerDispelTypes()
end

-- ============================================================
-- LAYOUT HELPERS
-- ============================================================

local function LayoutBorders(element, DB)
	local borderDB = DB.border or {}
	if not borderDB.enabled then
		element.borderTop:Hide()
		element.borderBottom:Hide()
		element.borderLeft:Hide()
		element.borderRight:Hide()
		return
	end

	local size = borderDB.size or 2

	element.borderTop:ClearAllPoints()
	element.borderTop:SetPoint('TOPLEFT', element, 'TOPLEFT', 0, 0)
	element.borderTop:SetPoint('TOPRIGHT', element, 'TOPRIGHT', 0, 0)
	element.borderTop:SetHeight(size)

	element.borderBottom:ClearAllPoints()
	element.borderBottom:SetPoint('BOTTOMLEFT', element, 'BOTTOMLEFT', 0, 0)
	element.borderBottom:SetPoint('BOTTOMRIGHT', element, 'BOTTOMRIGHT', 0, 0)
	element.borderBottom:SetHeight(size)

	element.borderLeft:ClearAllPoints()
	element.borderLeft:SetPoint('TOPLEFT', element, 'TOPLEFT', 0, -size)
	element.borderLeft:SetPoint('BOTTOMLEFT', element, 'BOTTOMLEFT', 0, size)
	element.borderLeft:SetWidth(size)

	element.borderRight:ClearAllPoints()
	element.borderRight:SetPoint('TOPRIGHT', element, 'TOPRIGHT', 0, -size)
	element.borderRight:SetPoint('BOTTOMRIGHT', element, 'BOTTOMRIGHT', 0, size)
	element.borderRight:SetWidth(size)
end

local function LayoutTypeIcon(element, DB)
	local iconDB = DB.typeIcon or {}
	if not iconDB.enabled then
		for _, bar in pairs(element.typeIcons) do
			bar:Hide()
		end
		return
	end

	local size = iconDB.size or 16
	local pos = iconDB.position or {}
	local anchor = pos.anchor or 'TOPRIGHT'
	local x = pos.x or -2
	local y = pos.y or -2

	for _, bar in pairs(element.typeIcons) do
		bar:SetSize(size, size)
		bar:ClearAllPoints()
		bar:SetPoint(anchor, element, anchor, x, y)
	end
end

local function LayoutDebuffIcon(element, DB)
	local iconDB = DB.debuffIcon or {}
	if not iconDB.enabled then
		element.debuffFrame:Hide()
		return
	end

	local size = iconDB.size or 24
	local pos = iconDB.position or {}
	local anchor = pos.anchor or 'CENTER'
	local x = pos.x or 0
	local y = pos.y or 0

	element.debuffFrame:SetSize(size, size)
	element.debuffFrame:SetAlpha(iconDB.alpha or 1.0)
	element.debuffFrame:ClearAllPoints()
	element.debuffFrame:SetPoint(anchor, element, anchor, x, y)
end

-- ============================================================
-- COLOR APPLICATION
-- ============================================================

local function ApplyBorderColor(element, unit, auraInstanceID, DB)
	local borderDB = DB.border or {}
	if not borderDB.enabled then
		return
	end

	local alpha = borderDB.alpha or 0.8

	if SUI.IsRetail and C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor then
		-- Use color curve for secret-safe coloring
		local curve = GetBorderCurve(alpha)
		if curve and auraInstanceID then
			local success, color = pcall(function()
				return C_UnitAuras.GetAuraDispelTypeColor(unit, auraInstanceID, curve)
			end)
			if success and color then
				local borders = { element.borderTop, element.borderBottom, element.borderLeft, element.borderRight }
				for _, bar in ipairs(borders) do
					bar:GetStatusBarTexture():SetVertexColor(color:GetRGBA())
					bar:Show()
				end
				return
			end
		end
	end

	-- Classic fallback or curve failure: use DispelColors table directly
	local dispelType = element._currentDispelType
	local c = DispelColors.none
	if dispelType and SUI.BlizzAPI.canaccessvalue(dispelType) then
		c = DispelColors[dispelType] or DispelColors.none
	end

	local borders = { element.borderTop, element.borderBottom, element.borderLeft, element.borderRight }
	for _, bar in ipairs(borders) do
		bar:GetStatusBarTexture():SetVertexColor(c.r, c.g, c.b, alpha)
		bar:Show()
	end
end

local function ApplyTypeIcon(element, unit, auraInstanceID, dispelType, DB)
	local iconDB = DB.typeIcon or {}
	if not iconDB.enabled then
		for _, bar in pairs(element.typeIcons) do
			bar:Hide()
		end
		return
	end

	if SUI.IsRetail and C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor and auraInstanceID then
		-- Show all per-type StatusBars and let curve alpha control visibility
		-- Matching type gets alpha from curve, non-matching types get alpha=0 (invisible)
		local iconAlpha = iconDB.alpha or 1.0
		local typeChecks = {
			{ enum = DispelTypeEnum.Magic, name = 'Magic' },
			{ enum = DispelTypeEnum.Curse, name = 'Curse' },
			{ enum = DispelTypeEnum.Disease, name = 'Disease' },
			{ enum = DispelTypeEnum.Poison, name = 'Poison' },
			{ enum = DispelTypeEnum.Bleed, name = 'Bleed' },
		}
		for _, check in ipairs(typeChecks) do
			local bar = element.typeIcons[check.name]
			if bar then
				local curve = GetTypeIconCurve(check.enum, iconAlpha)
				if curve then
					local success, color = pcall(function()
						return C_UnitAuras.GetAuraDispelTypeColor(unit, auraInstanceID, curve)
					end)
					if success and color then
						bar:GetStatusBarTexture():SetVertexColor(color:GetRGBA())
						bar:Show()
					else
						bar:Hide()
					end
				else
					bar:Hide()
				end
			end
		end
	else
		-- Classic: direct dispelType access (not secret)
		for typeName, bar in pairs(element.typeIcons) do
			bar:Hide()
		end
		if dispelType and SUI.BlizzAPI.canaccessvalue(dispelType) then
			local bar = element.typeIcons[dispelType]
			if bar then
				bar:GetStatusBarTexture():SetVertexColor(1, 1, 1, iconDB.alpha or 1.0)
				bar:Show()
			end
		end
	end
end

local function ApplyDebuffIcon(element, unit, aura, auraInstanceID, slotIndex, dispelType, DB)
	local iconDB = DB.debuffIcon or {}
	if not iconDB.enabled then
		element.debuffFrame:Hide()
		return
	end

	-- Set icon texture
	if aura.icon then
		element.debuffIcon:SetTexture(aura.icon)
	else
		element.debuffIcon:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')
	end

	-- Border color
	if element.debuffBorder then
		local c = DispelColors.none
		if dispelType and SUI.BlizzAPI.canaccessvalue(dispelType) then
			c = DispelColors[dispelType] or DispelColors.none
		end
		element.debuffBorder:SetVertexColor(c.r, c.g, c.b, 1.0)
	end

	-- Cooldown spiral using secret-safe DurationObject API
	if element.cooldown and iconDB.showCooldown ~= false then
		if SUI.IsRetail and C_UnitAuras.GetAuraDuration and auraInstanceID then
			local success, durationObj = pcall(C_UnitAuras.GetAuraDuration, unit, auraInstanceID)
			if success and durationObj and element.cooldown.SetCooldownFromDurationObject then
				element.cooldown:SetCooldownFromDurationObject(durationObj)
				element.cooldown:Show()
			else
				element.cooldown:Hide()
			end
		elseif not SUI.IsRetail then
			-- Classic: direct duration access (not secret)
			local duration = aura.duration or 0
			local expiration = aura.expirationTime or 0
			if duration > 0 and expiration > 0 then
				element.cooldown:SetCooldown(expiration - duration, duration)
				element.cooldown:Show()
			else
				element.cooldown:Hide()
			end
		else
			element.cooldown:Hide()
		end
	elseif element.cooldown then
		element.cooldown:Hide()
	end

	-- Stack count using secret-safe DisplayCount API
	if element.count and iconDB.showCount ~= false then
		if SUI.IsRetail and C_UnitAuras.GetAuraApplicationDisplayCount and auraInstanceID then
			local success, countText = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, auraInstanceID, 2, 999)
			if success and countText then
				element.count:SetText(countText)
			else
				element.count:SetText('')
			end
		elseif not SUI.IsRetail then
			-- Classic: direct applications access (not secret)
			local applications = aura.applications
			if applications and applications > 1 then
				element.count:SetText(applications)
			else
				element.count:SetText('')
			end
		else
			element.count:SetText('')
		end
	elseif element.count then
		element.count:SetText('')
	end

	-- Store data needed for tooltip
	element.debuffFrame._tooltipUnit = unit
	element.debuffFrame._tooltipInstanceID = auraInstanceID
	element.debuffFrame._tooltipSlotIndex = slotIndex

	element.debuffFrame:Show()
end

-- ============================================================
-- HIDE ALL SUB-ELEMENTS
-- ============================================================

local function HideAll(element)
	element.borderTop:Hide()
	element.borderBottom:Hide()
	element.borderLeft:Hide()
	element.borderRight:Hide()
	for _, bar in pairs(element.typeIcons) do
		bar:Hide()
	end
	element.debuffFrame:Hide()
	if element.cooldown then
		element.cooldown:Hide()
	end
	if element.count then
		element.count:SetText('')
	end
	element:Hide()
end

-- ============================================================
-- ELEMENT UPDATE (called by oUF on UNIT_AURA and by SUI ElementUpdate)
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
		HideAll(element)
		return
	end
	element.DB = DB

	local unit = frame.unit
	if not unit then
		HideAll(element)
		return
	end

	-- Layout all sub-elements based on current DB
	LayoutBorders(element, DB)
	LayoutTypeIcon(element, DB)
	LayoutDebuffIcon(element, DB)

	local filterByPlayerDispels = DB.onlyShowDispellable ~= false
	local aura, dispelType, slotIndex = FindDispellableDebuff(unit, filterByPlayerDispels)

	if not aura then
		HideAll(element)
		return
	end

	-- Store for Classic fallback color lookup
	element._currentDispelType = dispelType

	local auraInstanceID = aura.auraInstanceID

	-- Apply visuals to all sub-elements
	ApplyBorderColor(element, unit, auraInstanceID, DB)
	ApplyTypeIcon(element, unit, auraInstanceID, dispelType, DB)
	ApplyDebuffIcon(element, unit, aura, auraInstanceID, slotIndex, dispelType, DB)

	element:Show()
end

-- ============================================================
-- oUF ELEMENT REGISTRATION
-- Registers with oUF so UNIT_AURA events trigger Update automatically
-- ============================================================

local function oufUpdate(frame, event, unit)
	if unit and unit ~= frame.unit then
		return
	end
	Update(frame)
end

local function oufEnable(frame)
	if not frame.Dispel then
		return false
	end

	frame:RegisterEvent('UNIT_AURA', oufUpdate)
	return true
end

local function oufDisable(frame)
	if not frame.Dispel then
		return
	end

	frame:UnregisterEvent('UNIT_AURA', oufUpdate)
	HideAll(frame.Dispel)
end

-- Register as an oUF element named 'Dispel'
-- This hooks into oUF's EnableElement/DisableElement lifecycle
SUIUF:AddElement('Dispel', oufUpdate, oufEnable, oufDisable)

-- ============================================================
-- OPTIONS
-- ============================================================

local anchorValues = {
	TOPLEFT = 'Top Left',
	TOP = 'Top',
	TOPRIGHT = 'Top Right',
	LEFT = 'Left',
	CENTER = 'Center',
	RIGHT = 'Right',
	BOTTOMLEFT = 'Bottom Left',
	BOTTOM = 'Bottom',
	BOTTOMRIGHT = 'Bottom Right',
}

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	local function GetSettings()
		return UF.CurrentSettings[unitName].elements.Dispel
	end

	local function SetVal(path, val)
		-- Update CurrentSettings
		local current = UF.CurrentSettings[unitName].elements.Dispel
		local userDB = UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.Dispel

		local keys = {}
		for key in path:gmatch('[^.]+') do
			keys[#keys + 1] = key
		end

		-- Navigate to parent for both tables
		local cParent = current
		local uParent = userDB
		for i = 1, #keys - 1 do
			local k = keys[i]
			if not cParent[k] then
				cParent[k] = {}
			end
			if not uParent[k] then
				uParent[k] = {}
			end
			cParent = cParent[k]
			uParent = uParent[k]
		end

		local finalKey = keys[#keys]
		cParent[finalKey] = val
		uParent[finalKey] = val

		-- Invalidate curves if alpha changed
		if finalKey == 'alpha' then
			InvalidateCurves()
		end

		UF.Unit[unitName]:ElementUpdate('Dispel')
	end

	-- Border group
	OptionSet.args.Border = {
		name = L['Border'],
		type = 'group',
		order = 10,
		inline = true,
		args = {
			enabled = {
				name = L['Enable'],
				desc = L['Show colored border around frame when dispellable debuff is present'],
				type = 'toggle',
				order = 1,
				get = function()
					local s = GetSettings()
					return s.border and s.border.enabled
				end,
				set = function(_, val)
					SetVal('border.enabled', val)
				end,
			},
			size = {
				name = L['Thickness'],
				type = 'range',
				order = 2,
				min = 1,
				max = 6,
				step = 1,
				disabled = function()
					local s = GetSettings()
					return not (s.border and s.border.enabled)
				end,
				get = function()
					local s = GetSettings()
					return s.border and s.border.size or 2
				end,
				set = function(_, val)
					SetVal('border.size', val)
				end,
			},
			alpha = {
				name = L['Opacity'],
				type = 'range',
				order = 3,
				min = 0.1,
				max = 1.0,
				step = 0.05,
				disabled = function()
					local s = GetSettings()
					return not (s.border and s.border.enabled)
				end,
				get = function()
					local s = GetSettings()
					return s.border and s.border.alpha or 0.8
				end,
				set = function(_, val)
					SetVal('border.alpha', val)
				end,
			},
		},
	}

	-- Type Icon group
	OptionSet.args.TypeIcon = {
		name = L['Type Icon'],
		type = 'group',
		order = 20,
		inline = true,
		args = {
			enabled = {
				name = L['Enable'],
				desc = L['Show small icon indicating the debuff type (Magic, Curse, etc)'],
				type = 'toggle',
				order = 1,
				get = function()
					local s = GetSettings()
					return s.typeIcon and s.typeIcon.enabled
				end,
				set = function(_, val)
					SetVal('typeIcon.enabled', val)
				end,
			},
			size = {
				name = L['Size'],
				type = 'range',
				order = 2,
				min = 8,
				max = 32,
				step = 1,
				disabled = function()
					local s = GetSettings()
					return not (s.typeIcon and s.typeIcon.enabled)
				end,
				get = function()
					local s = GetSettings()
					return s.typeIcon and s.typeIcon.size or 16
				end,
				set = function(_, val)
					SetVal('typeIcon.size', val)
				end,
			},
			alpha = {
				name = L['Opacity'],
				type = 'range',
				order = 3,
				min = 0.1,
				max = 1.0,
				step = 0.05,
				disabled = function()
					local s = GetSettings()
					return not (s.typeIcon and s.typeIcon.enabled)
				end,
				get = function()
					local s = GetSettings()
					return s.typeIcon and s.typeIcon.alpha or 1.0
				end,
				set = function(_, val)
					SetVal('typeIcon.alpha', val)
				end,
			},
			anchor = {
				name = L['Position'],
				type = 'select',
				order = 4,
				values = anchorValues,
				disabled = function()
					local s = GetSettings()
					return not (s.typeIcon and s.typeIcon.enabled)
				end,
				get = function()
					local s = GetSettings()
					return s.typeIcon and s.typeIcon.position and s.typeIcon.position.anchor or 'TOPRIGHT'
				end,
				set = function(_, val)
					SetVal('typeIcon.position.anchor', val)
				end,
			},
			x = {
				name = L['X Offset'],
				type = 'range',
				order = 5,
				min = -20,
				max = 20,
				step = 1,
				disabled = function()
					local s = GetSettings()
					return not (s.typeIcon and s.typeIcon.enabled)
				end,
				get = function()
					local s = GetSettings()
					return s.typeIcon and s.typeIcon.position and s.typeIcon.position.x or -2
				end,
				set = function(_, val)
					SetVal('typeIcon.position.x', val)
				end,
			},
			y = {
				name = L['Y Offset'],
				type = 'range',
				order = 6,
				min = -20,
				max = 20,
				step = 1,
				disabled = function()
					local s = GetSettings()
					return not (s.typeIcon and s.typeIcon.enabled)
				end,
				get = function()
					local s = GetSettings()
					return s.typeIcon and s.typeIcon.position and s.typeIcon.position.y or -2
				end,
				set = function(_, val)
					SetVal('typeIcon.position.y', val)
				end,
			},
		},
	}

	-- Debuff Icon group
	OptionSet.args.DebuffIcon = {
		name = L['Debuff Icon'],
		type = 'group',
		order = 30,
		inline = true,
		args = {
			enabled = {
				name = L['Enable'],
				desc = L['Show the actual debuff spell icon on the frame'],
				type = 'toggle',
				order = 1,
				get = function()
					local s = GetSettings()
					return s.debuffIcon and s.debuffIcon.enabled
				end,
				set = function(_, val)
					SetVal('debuffIcon.enabled', val)
				end,
			},
			size = {
				name = L['Size'],
				type = 'range',
				order = 2,
				min = 12,
				max = 48,
				step = 1,
				disabled = function()
					local s = GetSettings()
					return not (s.debuffIcon and s.debuffIcon.enabled)
				end,
				get = function()
					local s = GetSettings()
					return s.debuffIcon and s.debuffIcon.size or 24
				end,
				set = function(_, val)
					SetVal('debuffIcon.size', val)
				end,
			},
			alpha = {
				name = L['Opacity'],
				type = 'range',
				order = 3,
				min = 0.1,
				max = 1.0,
				step = 0.05,
				disabled = function()
					local s = GetSettings()
					return not (s.debuffIcon and s.debuffIcon.enabled)
				end,
				get = function()
					local s = GetSettings()
					return s.debuffIcon and s.debuffIcon.alpha or 1.0
				end,
				set = function(_, val)
					SetVal('debuffIcon.alpha', val)
				end,
			},
			showCooldown = {
				name = L['Cooldown Spiral'],
				desc = L['Show cooldown spiral on the debuff icon'],
				type = 'toggle',
				order = 4,
				disabled = function()
					local s = GetSettings()
					return not (s.debuffIcon and s.debuffIcon.enabled)
				end,
				get = function()
					local s = GetSettings()
					return s.debuffIcon and s.debuffIcon.showCooldown ~= false
				end,
				set = function(_, val)
					SetVal('debuffIcon.showCooldown', val)
				end,
			},
			showCount = {
				name = L['Stack Count'],
				desc = L['Show stack count on the debuff icon'],
				type = 'toggle',
				order = 5,
				disabled = function()
					local s = GetSettings()
					return not (s.debuffIcon and s.debuffIcon.enabled)
				end,
				get = function()
					local s = GetSettings()
					return s.debuffIcon and s.debuffIcon.showCount ~= false
				end,
				set = function(_, val)
					SetVal('debuffIcon.showCount', val)
				end,
			},
			anchor = {
				name = L['Position'],
				type = 'select',
				order = 6,
				values = anchorValues,
				disabled = function()
					local s = GetSettings()
					return not (s.debuffIcon and s.debuffIcon.enabled)
				end,
				get = function()
					local s = GetSettings()
					return s.debuffIcon and s.debuffIcon.position and s.debuffIcon.position.anchor or 'CENTER'
				end,
				set = function(_, val)
					SetVal('debuffIcon.position.anchor', val)
				end,
			},
			x = {
				name = L['X Offset'],
				type = 'range',
				order = 7,
				min = -30,
				max = 30,
				step = 1,
				disabled = function()
					local s = GetSettings()
					return not (s.debuffIcon and s.debuffIcon.enabled)
				end,
				get = function()
					local s = GetSettings()
					return s.debuffIcon and s.debuffIcon.position and s.debuffIcon.position.x or 0
				end,
				set = function(_, val)
					SetVal('debuffIcon.position.x', val)
				end,
			},
			y = {
				name = L['Y Offset'],
				type = 'range',
				order = 8,
				min = -30,
				max = 30,
				step = 1,
				disabled = function()
					local s = GetSettings()
					return not (s.debuffIcon and s.debuffIcon.enabled)
				end,
				get = function()
					local s = GetSettings()
					return s.debuffIcon and s.debuffIcon.position and s.debuffIcon.position.y or 0
				end,
				set = function(_, val)
					SetVal('debuffIcon.position.y', val)
				end,
			},
		},
	}

	-- Filter group
	OptionSet.args.Filter = {
		name = L['Filter'],
		type = 'group',
		order = 40,
		inline = true,
		args = {
			onlyShowDispellable = {
				name = L['Only Your Dispels'],
				desc = SUI.IsRetail and hasPlayerDispellableFilter and L['Only show debuffs you can dispel (uses RAID_PLAYER_DISPELLABLE filter)']
					or L['Only show debuffs you can dispel based on your class'],
				type = 'toggle',
				order = 1,
				get = function()
					local s = GetSettings()
					return s.onlyShowDispellable ~= false
				end,
				set = function(_, val)
					SetVal('onlyShowDispellable', val)
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
	enabled = true,
	onlyShowDispellable = true,
	border = {
		enabled = true,
		size = 2,
		alpha = 0.8,
	},
	typeIcon = {
		enabled = true,
		size = 16,
		alpha = 1.0,
		position = {
			anchor = 'TOPRIGHT',
			x = -2,
			y = -2,
		},
	},
	debuffIcon = {
		enabled = true,
		size = 24,
		alpha = 1.0,
		showCooldown = true,
		showCount = true,
		position = {
			anchor = 'CENTER',
			x = 0,
			y = 0,
		},
	},
	config = {
		type = 'Auras',
		NoBulkUpdate = true,
		NoGenericOptions = true,
		DisplayName = 'Dispel',
	},
}

UF.Elements:Register('Dispel', Build, Update, Options, Settings)
