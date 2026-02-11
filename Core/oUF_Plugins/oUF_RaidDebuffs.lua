-- oUF RaidDebuffs Element
-- Shows important debuffs (CC, boss mechanics, dispellable) on raid/party frames
--
-- RETAIL 12.1+: Uses CROWD_CONTROL and RAID_PLAYER_DISPELLABLE aura filters
-- RETAIL 12.0: Uses secret-value-safe APIs and color curves for dispel detection
-- CLASSIC: Uses full aura data access with priority system

local _, ns = ...
local oUF = ns.oUF or oUF

if not oUF then
	return
end

-- Check if new filter types are available (12.1+)
local hasNewFilters = AuraUtil
	and AuraUtil.ForEachAura
	and pcall(function()
		-- Try to use the filter - if it errors, it's not available
		local test = AuraUtil.CreateFilterString and AuraUtil.CreateFilterString('HARMFUL', 'CROWD_CONTROL')
		return test ~= nil
	end)

-- Alternative check: see if the enum exists
if not hasNewFilters then
	hasNewFilters = Enum and Enum.AuraFilter and Enum.AuraFilter.CrowdControl ~= nil
end

-- Check if addon is running on Retail
local isRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

-- TODO: Remove this version check after 12.0.x is no longer supported
-- Disable for Retail 12.0.0: Aura APIs return "secret" values that can't be compared
local buildVersion = GetBuildInfo()
if isRetail and buildVersion and buildVersion:match('^12%.0%.0') then
	return
end

-- ============================================================
-- PRIORITY & DISPEL SYSTEM
-- ============================================================

-- Priority system for debuffs (higher = more important)
local PRIORITY_BOSS = 100 -- Boss mechanics
local PRIORITY_CC = 80 -- Crowd control (fear, stun, etc)
local PRIORITY_DISPELLABLE = 60 -- Dispellable debuffs
local PRIORITY_DOT = 20 -- Damage over time

-- Dispel type colors for border
local DispelColors = {
	Magic = { r = 0.2, g = 0.6, b = 1.0 },
	Curse = { r = 0.6, g = 0.0, b = 1.0 },
	Disease = { r = 0.6, g = 0.4, b = 0.0 },
	Poison = { r = 0.0, g = 0.6, b = 0.0 },
	Bleed = { r = 0.8, g = 0.0, b = 0.0 },
	none = { r = 0.8, g = 0, b = 0 },
}

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

-- Color curve for dispel detection (cached)
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
		if typeName ~= 'none' and math.abs(r - typeColor.r) < 0.1 and math.abs(g - typeColor.g) < 0.1 and math.abs(b - typeColor.b) < 0.1 then
			return typeName
		end
	end
	return nil
end

-- ============================================================
-- NEW API: Direct filter queries (12.1+)
-- ============================================================

-- Find important debuff using new filter types
---@param unit UnitId
---@return table|nil auraData
---@return number priority
---@return string|nil dispelType
local function FindImportantDebuff_NewAPI(unit)
	if not unit or not UnitExists(unit) then
		return nil, 0, nil
	end

	-- Only check friendly units
	if not UnitCanAssist('player', unit) then
		return nil, 0, nil
	end

	local bestAura = nil
	local bestPriority = 0
	local bestDispelType = nil

	-- Check for CC first (highest priority we can detect via filter)
	AuraUtil.ForEachAura(unit, 'HARMFUL|CROWD_CONTROL', nil, function(aura)
		if not bestAura or PRIORITY_CC > bestPriority then
			bestAura = aura
			bestPriority = PRIORITY_CC
			bestDispelType = aura.dispelName
		end
		return true -- Take first CC
	end, true)

	-- If no CC, check for dispellable debuffs the player can remove
	if not bestAura then
		AuraUtil.ForEachAura(unit, 'HARMFUL|RAID_PLAYER_DISPELLABLE', nil, function(aura)
			if not bestAura or PRIORITY_DISPELLABLE > bestPriority then
				bestAura = aura
				bestPriority = PRIORITY_DISPELLABLE
				bestDispelType = aura.dispelName
			end
			return true -- Take first dispellable
		end, true)
	end

	return bestAura, bestPriority, bestDispelType
end

-- ============================================================
-- LEGACY API: Classic and Retail 12.0
-- ============================================================

-- Classic: Find the most important debuff
---@param unit UnitId
---@return table|nil auraData
---@return number priority
---@return string|nil dispelType
local function FindImportantDebuff_Classic(unit)
	local bestAura = nil
	local bestPriority = 0
	local bestDispelType = nil

	for i = 1, 40 do
		local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, 'HARMFUL')
		if not aura then
			break
		end

		local priority = PRIORITY_DOT
		local dispelType = aura.dispelName

		-- Check if it's a boss aura
		if aura.isBossAura then
			priority = PRIORITY_BOSS
		elseif dispelType then
			priority = PRIORITY_DISPELLABLE
		end

		-- Check duration for CC detection (short duration debuffs are often CC)
		local duration = aura.duration or 0
		if duration > 0 and duration <= 12 then
			priority = math.max(priority, PRIORITY_CC)
		end

		if priority > bestPriority then
			bestPriority = priority
			bestAura = aura
			bestDispelType = dispelType
		end
	end

	return bestAura, bestPriority, bestDispelType
end

-- Retail 12.0: Find the most important debuff using secret-value-safe approach
---@param unit UnitId
---@return table|nil auraData with safe values only
---@return number priority
---@return string|nil dispelType
local function FindImportantDebuff_Retail_Legacy(unit)
	local curve = GetDispelColorCurve()

	local bestAura = nil
	local bestPriority = 0
	local bestDispelType = nil

	for i = 1, 40 do
		local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, 'HARMFUL')
		if not aura then
			break
		end

		local auraInstanceID = aura.auraInstanceID
		if not auraInstanceID then
			break
		end

		local priority = PRIORITY_DOT
		local dispelType = nil

		-- Check dispel type using color curve (secret-value-safe)
		if curve then
			local success, color = pcall(function()
				return C_UnitAuras.GetAuraDispelTypeColor(unit, auraInstanceID, curve)
			end)
			if success and color then
				local r, g, b, a = color:GetRGBA()
				if a and a > 0 then
					dispelType = GetDispelTypeFromColor(r, g, b)
					if dispelType then
						priority = PRIORITY_DISPELLABLE
					end
				end
			end
		end

		-- Give earlier indices higher priority as a heuristic
		-- (Blizzard sorts important debuffs first)
		if i <= 3 then
			priority = math.max(priority, PRIORITY_CC)
		end

		if priority > bestPriority then
			bestPriority = priority
			bestAura = {
				auraInstanceID = auraInstanceID,
			}
			bestDispelType = dispelType
		end

		-- Break early if we found something important
		if priority >= PRIORITY_CC then
			break
		end
	end

	return bestAura, bestPriority, bestDispelType
end

-- Main function to find important debuff
local function FindImportantDebuff(unit)
	if not unit or not UnitExists(unit) then
		return nil, 0, nil
	end

	-- Only check friendly units
	if not UnitCanAssist('player', unit) then
		return nil, 0, nil
	end

	if isRetail then
		if hasNewFilters then
			return FindImportantDebuff_NewAPI(unit)
		else
			return FindImportantDebuff_Retail_Legacy(unit)
		end
	else
		return FindImportantDebuff_Classic(unit)
	end
end

-- ============================================================
-- OUF ELEMENT
-- ============================================================

local function Update(self, event, unit)
	if self.unit ~= unit and event ~= 'ForceUpdate' then
		return
	end

	local element = self.RaidDebuffs
	if not element then
		return
	end

	--[[ Callback: RaidDebuffs:PreUpdate()
	Called before the element has been updated.

	* self - the RaidDebuffs element
	--]]
	if element.PreUpdate then
		element:PreUpdate()
	end

	unit = self.unit
	if not unit or not UnitExists(unit) then
		element:Hide()
		return
	end

	local aura, priority, dispelType = FindImportantDebuff(unit)

	if aura and priority > 0 then
		local auraInstanceID = aura.auraInstanceID

		if isRetail and not hasNewFilters then
			-- Retail 12.0 Legacy: Use secret-value-safe APIs

			-- Icon texture - try to get it safely
			if element.icon then
				local iconSet = false
				pcall(function()
					local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
					if auraData and auraData.icon then
						element.icon:SetTexture(auraData.icon)
						iconSet = true
					end
				end)
				if not iconSet then
					element.icon:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')
				end
			end

			-- Duration: Use cooldown API (secret-value-safe)
			if element.cd then
				local success = pcall(function()
					local durationObj = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
					if durationObj then
						element.cd:SetCooldownFromDurationObject(durationObj)
						element.cd:Show()
					else
						element.cd:Hide()
					end
				end)
				if not success then
					element.cd:Hide()
				end
			end

			-- Hide text duration in Retail legacy (can't access values reliably)
			if element.time then
				element.time:SetText('')
			end
			element:SetScript('OnUpdate', nil)
			element.endTime = nil

			-- Stack count: Use secret-value-safe API
			if element.count then
				element.count:SetText('')
				pcall(function()
					local stackText = C_UnitAuras.GetAuraApplicationDisplayCount(unit, auraInstanceID, 2, 99)
					if stackText then
						element.count:SetText(stackText)
					end
				end)
			end
		else
			-- New API (12.1+) or Classic: Full access to aura data
			if element.icon and aura.icon then
				element.icon:SetTexture(aura.icon)
			end

			-- Duration
			local duration = aura.duration or 0
			local expiration = aura.expirationTime or 0

			if element.cd and duration > 0 and expiration > 0 then
				element.cd:SetCooldown(expiration - duration, duration)
				element.cd:Show()
			elseif element.cd then
				element.cd:Hide()
			end

			-- Text duration with OnUpdate (Classic only, or if showDuration enabled)
			if element.showDuration ~= false and duration > 0 and expiration > 0 then
				element.endTime = expiration
				-- OnUpdate is handled by the element file
			else
				element.endTime = nil
				if element.time then
					element.time:SetText('')
				end
			end

			-- Stack count
			if element.count then
				local count = aura.applications or 0
				if count > 1 then
					element.count:SetText(count)
				else
					element.count:SetText('')
				end
			end
		end

		-- Border color based on dispel type
		if element.border then
			local color = DispelColors[dispelType] or DispelColors.none
			element.border:SetVertexColor(color.r, color.g, color.b, 0.8)
		end

		element:Show()

		--[[ Callback: RaidDebuffs:PostUpdate(aura, priority, dispelType)
		Called after the element has been updated.

		* self       - the RaidDebuffs element
		* aura       - the aura data table
		* priority   - the priority value of the debuff
		* dispelType - the dispel type string or nil
		--]]
		if element.PostUpdate then
			element:PostUpdate(aura, priority, dispelType)
		end
	else
		element:Hide()
		element:SetScript('OnUpdate', nil)
		element.endTime = nil
	end
end

local function ForceUpdate(element)
	return Update(element.__owner, 'ForceUpdate', element.__owner.unit)
end

local function Enable(self)
	local element = self.RaidDebuffs
	if element then
		element.__owner = self
		element.ForceUpdate = ForceUpdate

		-- Register for aura events
		self:RegisterEvent('UNIT_AURA', Update)

		return true
	end
end

local function Disable(self)
	local element = self.RaidDebuffs
	if element then
		self:UnregisterEvent('UNIT_AURA', Update)
		element:Hide()
		element:SetScript('OnUpdate', nil)
	end
end

oUF:AddElement('RaidDebuffs', Update, Enable, Disable)
