-- oUF DefensiveIndicator Element
-- Shows defensive cooldowns (Ironbark, Pain Suppression, etc.) on raid/party frames
--
-- RETAIL 12.1+: Uses BIG_DEFENSIVE aura filter for direct API access
-- RETAIL 12.0: Disabled due to secret value restrictions
-- CLASSIC: Not supported (no defensive buff display system)

local _, ns = ...
local oUF = ns.oUF or oUF

if not oUF then
	return
end

-- TODO: Remove this version check after 12.0.x is no longer supported
-- Check build version - disable for 12.0.0 due to secret value issues
local buildVersion = GetBuildInfo()
if buildVersion and buildVersion:match('^12%.0%.0') then
	return
end

-- Check if new filter types are available (12.1+)
local hasBigDefensiveFilter = AuraUtil
	and AuraUtil.FindAuraByName
	and pcall(function()
		-- Try to use the filter - if it errors, it's not available
		local test = AuraUtil.CreateFilterString('BIG_DEFENSIVE')
		return test ~= nil
	end)

-- Alternative check: see if the enum exists
if not hasBigDefensiveFilter then
	hasBigDefensiveFilter = Enum and Enum.AuraFilter and Enum.AuraFilter.BigDefensive ~= nil
end

-- ============================================================
-- LEGACY: BLIZZARD FRAME CACHE (for 12.0 fallback)
-- ============================================================

-- Cache of defensive auras from Blizzard's CompactUnitFrame
-- Exposed globally so the SUI element file can access it
---@type table<string, table<number, boolean>>
SUI_DefensiveCache = SUI_DefensiveCache or {}
local DefensiveCache = SUI_DefensiveCache

-- Track if we've hooked Blizzard's frames
local BlizzardHookActive = false

-- Capture defensive aura from Blizzard's CompactUnitFrame
---@param frame table Blizzard's CompactUnitFrame
local function CaptureDefensiveFromBlizzardFrame(frame)
	if not frame or not frame.unit then
		return
	end

	-- Skip nameplates
	local unit = frame.unit
	if unit and type(unit) == 'string' and unit:find('nameplate') then
		return
	end

	-- Initialize cache for this unit
	if not DefensiveCache[unit] then
		DefensiveCache[unit] = {}
	else
		wipe(DefensiveCache[unit])
	end

	-- Capture defensive aura from CenterDefensiveBuff frame
	-- This is Blizzard's single frame that shows the most important defensive aura
	if frame.CenterDefensiveBuff then
		local defFrame = frame.CenterDefensiveBuff
		if defFrame:IsShown() and defFrame.auraInstanceID then
			DefensiveCache[unit][defFrame.auraInstanceID] = true
		end
	end
end

-- Setup hooks to Blizzard's CompactUnitFrame aura updates
local function SetupBlizzardHooks()
	if BlizzardHookActive then
		return
	end

	-- Hook the main aura update function
	if CompactUnitFrame_UpdateAuras then
		hooksecurefunc('CompactUnitFrame_UpdateAuras', function(frame)
			CaptureDefensiveFromBlizzardFrame(frame)
		end)
		BlizzardHookActive = true
	end

	-- Also hook UpdateBuffs if it exists separately
	if CompactUnitFrame_UpdateBuffs then
		hooksecurefunc('CompactUnitFrame_UpdateBuffs', function(frame)
			CaptureDefensiveFromBlizzardFrame(frame)
		end)
	end
end

-- Scan all Blizzard compact frames to build initial cache
local function ScanAllBlizzardFrames()
	-- Scan party frames
	for i = 1, 4 do
		local frame = _G['CompactPartyFrameMember' .. i]
		if frame then
			CaptureDefensiveFromBlizzardFrame(frame)
		end
	end

	-- Scan raid frames (up to 40)
	for i = 1, 40 do
		local frame = _G['CompactRaidFrame' .. i]
		if frame then
			CaptureDefensiveFromBlizzardFrame(frame)
		end
	end

	-- Scan raid group frames
	for group = 1, 8 do
		for member = 1, 5 do
			local frame = _G['CompactRaidGroup' .. group .. 'Member' .. member]
			if frame then
				CaptureDefensiveFromBlizzardFrame(frame)
			end
		end
	end
end

-- ============================================================
-- NEW API: Direct BIG_DEFENSIVE filter (12.1+)
-- ============================================================

-- Find defensive aura using the new BIG_DEFENSIVE filter
---@param unit UnitId
---@return number|nil auraInstanceID
---@return table|nil auraData
local function FindDefensiveAura_NewAPI(unit)
	if not unit or not UnitExists(unit) then
		return nil, nil
	end

	-- Only check friendly units
	if not UnitCanAssist('player', unit) then
		return nil, nil
	end

	-- Use AuraUtil.ForEachAura with BIG_DEFENSIVE filter
	local bestAura = nil

	AuraUtil.ForEachAura(unit, 'HELPFUL|BIG_DEFENSIVE', nil, function(aura)
		-- Take the first one (highest priority)
		if not bestAura then
			bestAura = aura
			return true -- Stop iteration
		end
	end, true) -- usePackedAura = true for aura table

	if bestAura then
		return bestAura.auraInstanceID, bestAura
	end

	return nil, nil
end

-- ============================================================
-- LEGACY API: Cache-based lookup (12.0)
-- ============================================================

-- Find defensive aura using cached Blizzard frame data
---@param unit UnitId
---@return number|nil auraInstanceID
local function FindDefensiveAura_LegacyAPI(unit)
	-- Scan Blizzard frames to update cache
	ScanAllBlizzardFrames()

	-- Get cached defensive from Blizzard's CenterDefensiveBuff
	local cache = DefensiveCache[unit]
	if cache then
		-- Get the first (and typically only) defensive
		for id in pairs(cache) do
			return id
		end
	end

	return nil
end

-- ============================================================
-- OUF ELEMENT
-- ============================================================

local function Update(self, event, unit)
	if self.unit ~= unit and event ~= 'ForceUpdate' then
		return
	end

	local element = self.DefensiveIndicator
	if not element then
		return
	end

	-- Respect the enabled setting from SUI's element DB
	if element.DB and not element.DB.enabled then
		element:Hide()
		return
	end

	--[[ Callback: DefensiveIndicator:PreUpdate()
	Called before the element has been updated.

	* self - the DefensiveIndicator element
	--]]
	if element.PreUpdate then
		element:PreUpdate()
	end

	unit = self.unit
	if not unit or not UnitExists(unit) then
		element:Hide()
		return
	end

	-- Find defensive aura using appropriate API
	local auraInstanceID, auraData

	if hasBigDefensiveFilter then
		-- Use new 12.1+ API
		auraInstanceID, auraData = FindDefensiveAura_NewAPI(unit)
	else
		-- Fall back to legacy cache-based approach
		auraInstanceID = FindDefensiveAura_LegacyAPI(unit)
	end

	if not auraInstanceID then
		element:Hide()
		return
	end

	-- Get aura data if we don't have it yet (legacy path)
	if not auraData then
		local success
		success, auraData = pcall(function()
			return C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
		end)
		if not success or not auraData then
			element:Hide()
			return
		end
	end

	-- Set icon texture (use pcall for secret value protection)
	local textureSet = false
	if element.icon then
		pcall(function()
			element.icon:SetTexture(auraData.icon)
			textureSet = true
		end)
	end

	if not textureSet then
		element:Hide()
		return
	end

	-- Update cooldown
	if element.cooldown then
		-- Try new duration API first (secret-value-safe)
		local durationSet = false
		if C_UnitAuras.GetAuraDuration then
			pcall(function()
				local durationObj = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
				if durationObj and element.cooldown.SetCooldownFromDurationObject then
					element.cooldown:SetCooldownFromDurationObject(durationObj)
					durationSet = true
				end
			end)
		end

		-- Fall back to expiration time method
		if not durationSet and element.cooldown.SetCooldownFromExpirationTime and auraData.expirationTime and auraData.duration then
			pcall(function()
				element.cooldown:SetCooldownFromExpirationTime(auraData.expirationTime, auraData.duration)
				durationSet = true
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
		elseif durationSet then
			element.cooldown:Show()
		end
	end

	-- Update stack count using secret-safe API
	if element.count then
		element.count:SetText('')
		if C_UnitAuras.GetAuraApplicationDisplayCount then
			pcall(function()
				local stackText = C_UnitAuras.GetAuraApplicationDisplayCount(unit, auraInstanceID, 2, 99)
				if stackText then
					element.count:SetText(stackText)
				end
			end)
		end
	end

	element:Show()

	--[[ Callback: DefensiveIndicator:PostUpdate(auraInstanceID, auraData)
	Called after the element has been updated.

	* self           - the DefensiveIndicator element
	* auraInstanceID - the aura instance ID of the defensive
	* auraData       - the aura data table from C_UnitAuras
	--]]
	if element.PostUpdate then
		element:PostUpdate(auraInstanceID, auraData)
	end
end

local function ForceUpdate(element)
	return Update(element.__owner, 'ForceUpdate', element.__owner.unit)
end

local function Enable(self)
	local element = self.DefensiveIndicator
	if element then
		element.__owner = self
		element.ForceUpdate = ForceUpdate

		-- Setup Blizzard hooks for legacy fallback
		if not hasBigDefensiveFilter then
			SetupBlizzardHooks()
			ScanAllBlizzardFrames()
		end

		-- Register for aura events
		self:RegisterEvent('UNIT_AURA', Update)

		return true
	end
end

local function Disable(self)
	local element = self.DefensiveIndicator
	if element then
		self:UnregisterEvent('UNIT_AURA', Update)
		element:Hide()
	end
end

oUF:AddElement('DefensiveIndicator', Update, Enable, Disable)
