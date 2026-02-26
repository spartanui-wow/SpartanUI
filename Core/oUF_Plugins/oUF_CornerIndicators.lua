-- oUF CornerIndicators Element
-- Shows colored squares in frame corners based on debuff types, specific spells, or buffs
--
-- RETAIL 12.1+: Uses AuraUtil.ForEachAura with filter strings
-- RETAIL 12.0: Uses secret-value-safe color curve for dispel type detection
-- CLASSIC: Uses C_UnitAuras.GetAuraDataByIndex with full access

local _, ns = ...
local oUF = ns.oUF or oUF

if not oUF then
	return
end

-- Check if new filter types are available (12.1+)
local hasNewFilters = AuraUtil
	and AuraUtil.ForEachAura
	and pcall(function()
		local test = AuraUtil.CreateFilterString and AuraUtil.CreateFilterString('HARMFUL', 'CROWD_CONTROL')
		return test ~= nil
	end)

if not hasNewFilters then
	hasNewFilters = Enum and Enum.AuraFilter and Enum.AuraFilter.CrowdControl ~= nil
end

local isRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

-- Dispel type enum values for Retail
local DispelTypeEnum = {
	None = 0,
	Magic = 1,
	Curse = 2,
	Disease = 3,
	Poison = 4,
	Enrage = 9,
	Bleed = 11,
}

-- Map enum to string name
local DispelEnumToName = {
	[1] = 'Magic',
	[2] = 'Curse',
	[3] = 'Disease',
	[4] = 'Poison',
	[9] = 'Bleed',
	[11] = 'Bleed',
}

-- Dispel type colors for color curve
local DispelColors = {
	Magic = { r = 0.2, g = 0.6, b = 1.0 },
	Curse = { r = 0.6, g = 0.0, b = 1.0 },
	Disease = { r = 0.6, g = 0.4, b = 0.0 },
	Poison = { r = 0.0, g = 0.6, b = 0.0 },
	Bleed = { r = 0.8, g = 0.0, b = 0.0 },
}

-- Color curve for Retail 12.0 dispel type detection (cached)
local dispelColorCurve = nil

local function GetDispelColorCurve()
	if dispelColorCurve then
		return dispelColorCurve
	end
	if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then
		return nil
	end
	dispelColorCurve = C_CurveUtil.CreateColorCurve()
	dispelColorCurve:SetType(Enum.LuaCurveType.Step)
	dispelColorCurve:AddPoint(DispelTypeEnum.None, CreateColor(0, 0, 0, 0))
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
		if math.abs(r - typeColor.r) < 0.1 and math.abs(g - typeColor.g) < 0.1 and math.abs(b - typeColor.b) < 0.1 then
			return typeName
		end
	end
	return nil
end

-- ============================================================
-- AURA SCANNING
-- ============================================================

-- Check if a corner's tracking condition is met for a given unit
-- Returns true if the corner should be shown
---@param unit string
---@param cornerCfg table Corner config with trackType, trackValue
---@return boolean
local function CheckCorner_NewAPI(unit, cornerCfg)
	local trackType = cornerCfg.trackType
	local trackValue = cornerCfg.trackValue

	if trackType == 'debuffType' then
		-- Scan HARMFUL auras for matching dispel type
		-- WoW 12.0: aura.dispelName can be secret - cannot use as table key OR in comparisons
		local found = false
		AuraUtil.ForEachAura(unit, 'HARMFUL', nil, function(aura)
			if aura.dispelName then
				-- Check if value is accessible before using it
				local SUI = SUI
				if SUI and SUI.BlizzAPI and SUI.BlizzAPI.canaccessvalue(aura.dispelName) then
					-- Safe to compare
					if aura.dispelName == trackValue then
						found = true
						return true -- Stop iteration
					end
				end
			end
		end, true)
		return found
	elseif trackType == 'spellID' then
		-- Check for specific spell by ID
		local aura = C_UnitAuras.GetAuraDataBySpellName(unit, trackValue, 'HELPFUL')
		if not aura then
			aura = C_UnitAuras.GetAuraDataBySpellName(unit, trackValue, 'HARMFUL')
		end
		return aura ~= nil
	elseif trackType == 'buff' then
		-- Scan HELPFUL auras for matching name
		-- WoW 12.0: aura.name can be secret - cannot use as table key OR in comparisons
		local found = false
		AuraUtil.ForEachAura(unit, 'HELPFUL', nil, function(aura)
			if aura.name then
				-- Check if value is accessible before using it
				local SUI = SUI
				if SUI and SUI.BlizzAPI and SUI.BlizzAPI.canaccessvalue(aura.name) then
					-- Safe to compare
					if aura.name == trackValue then
						found = true
						return true
					end
				end
			end
		end, true)
		return found
	end

	return false
end

local function CheckCorner_Classic(unit, cornerCfg)
	local trackType = cornerCfg.trackType
	local trackValue = cornerCfg.trackValue

	if trackType == 'debuffType' then
		local match = { [trackValue] = true }
		for i = 1, 40 do
			local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, 'HARMFUL')
			if not aura then
				break
			end
			if aura.dispelName and match[aura.dispelName] then
				return true
			end
		end
	elseif trackType == 'spellID' then
		-- Check both helpful and harmful
		local match = { [trackValue] = true }
		for _, filter in ipairs({ 'HELPFUL', 'HARMFUL' }) do
			for i = 1, 40 do
				local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
				if not aura then
					break
				end
				if aura.spellId and match[aura.spellId] then
					return true
				end
			end
		end
	elseif trackType == 'buff' then
		local match = { [trackValue] = true }
		for i = 1, 40 do
			local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, 'HELPFUL')
			if not aura then
				break
			end
			if aura.name and match[aura.name] then
				return true
			end
		end
	end

	return false
end

local function CheckCorner_Retail_Legacy(unit, cornerCfg)
	local trackType = cornerCfg.trackType
	local trackValue = cornerCfg.trackValue

	if trackType == 'debuffType' then
		-- Use color curve to detect dispel types (secret-value-safe)
		local curve = GetDispelColorCurve()
		if not curve then
			return false
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
						if dispelType == trackValue then
							return true
						end
					end
				end
			end
		end
	elseif trackType == 'spellID' or trackType == 'buff' then
		-- Secret values CANNOT be used as table keys - check accessibility first
		local match = { [trackValue] = true }
		for _, filter in ipairs({ 'HELPFUL', 'HARMFUL' }) do
			for i = 1, 40 do
				local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
				if not aura then
					break
				end
				if trackType == 'spellID' and aura.spellId and SUI and SUI.BlizzAPI and SUI.BlizzAPI.canaccessvalue(aura.spellId) and match[aura.spellId] then
					return true
				elseif trackType == 'buff' and aura.name and SUI and SUI.BlizzAPI and SUI.BlizzAPI.canaccessvalue(aura.name) and match[aura.name] then
					return true
				end
			end
		end
	end

	return false
end

local function CheckCorner(unit, cornerCfg)
	if not unit or not UnitExists(unit) then
		return false
	end
	if isRetail then
		if hasNewFilters then
			return CheckCorner_NewAPI(unit, cornerCfg)
		else
			return CheckCorner_Retail_Legacy(unit, cornerCfg)
		end
	else
		return CheckCorner_Classic(unit, cornerCfg)
	end
end

-- ============================================================
-- OUF ELEMENT
-- ============================================================

local function Update(self, event, unit)
	if self.unit ~= unit and event ~= 'ForceUpdate' then
		return
	end

	local element = self.CornerIndicators
	if not element then
		return
	end

	if element.PreUpdate then
		element:PreUpdate()
	end

	unit = self.unit
	if not unit or not UnitExists(unit) then
		for _, corner in pairs(element.corners) do
			corner:Hide()
		end
		return
	end

	local DB = element.DB
	if not DB or not DB.corners then
		return
	end

	for cornerKey, cornerTexture in pairs(element.corners) do
		local cornerCfg = DB.corners[cornerKey]
		if cornerCfg and cornerCfg.enabled then
			if CheckCorner(unit, cornerCfg) then
				local color = cornerCfg.color or { 1, 1, 1, 1 }
				cornerTexture:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
				cornerTexture:Show()
			else
				cornerTexture:Hide()
			end
		else
			cornerTexture:Hide()
		end
	end

	if element.PostUpdate then
		element:PostUpdate()
	end
end

local function ForceUpdate(element)
	return Update(element.__owner, 'ForceUpdate', element.__owner.unit)
end

local function Enable(self)
	local element = self.CornerIndicators
	if element then
		element.__owner = self
		element.ForceUpdate = ForceUpdate
		self:RegisterEvent('UNIT_AURA', Update)
		return true
	end
end

local function Disable(self)
	local element = self.CornerIndicators
	if element then
		self:UnregisterEvent('UNIT_AURA', Update)
		for _, corner in pairs(element.corners) do
			corner:Hide()
		end
	end
end

oUF:AddElement('CornerIndicators', Update, Enable, Disable)
