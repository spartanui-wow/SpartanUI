local SUI, L = SUI, SUI.L
---@class SUI.Module.UIEnhancements
local module = SUI:GetModule('UIEnhancements')
----------------------------------------------------------------------------------------------------

-- Constants
local DENSITY_PRESETS = {
	verylow = { spawnRate = 0.08, fadeDuration = 0.3, maxElements = 10 },
	low = { spawnRate = 0.05, fadeDuration = 0.4, maxElements = 20 },
	medium = { spawnRate = 0.03, fadeDuration = 0.5, maxElements = 35 },
	high = { spawnRate = 0.02, fadeDuration = 0.6, maxElements = 50 },
	veryhigh = { spawnRate = 0.01, fadeDuration = 0.8, maxElements = 75 },
}

local MIN_MOVE_DISTANCE_SQ = 25 -- 5^2, minimum cursor movement squared to spawn trail element
local MAX_POOL_SIZE = 75
local GCD_SPELL_ID = 61304 -- Global cooldown detection spell

-- Circle style definitions: 1=file texture, 2-4=atlas textures
local CIRCLE_STYLES = {
	[1] = { type = 'file', texture = 'Interface\\AddOns\\SpartanUI\\images\\circle.tga' },
	[2] = { type = 'atlas', atlas = 'ChallengeMode-KeystoneSlotFrameGlow' },
	[3] = { type = 'atlas', atlas = 'GarrLanding-CircleGlow' },
	[4] = { type = 'atlas', atlas = 'ShipMission-RedGlowRing' },
	[5] = { type = 'file', texture = 'Interface\\AddOns\\SpartanUI\\images\\circle.png' },
}

-- State
local mouseRingFrame = nil
local gcdCooldown = nil
local trailPool = {}
local activeTrailElements = {}
local lastCursorX, lastCursorY = 0, 0
local timeAccumulator = 0
local isOnUpdateActive = false
local updateFrame = nil

---Get image data for a circle style (resolves atlas textures to file+coords for AceConfig image buttons)
---@param styleNum number The circle style number
---@return string|number texture The texture file path or ID
---@return number width Display width
---@return number height Display height
function module:GetCircleStyleImage(styleNum)
	local style = CIRCLE_STYLES[styleNum]
	if not style then
		return '', 48, 48
	end

	if style.type == 'atlas' and C_Texture and C_Texture.GetAtlasInfo then
		local info = C_Texture.GetAtlasInfo(style.atlas)
		if info then
			return info.file, 48, 48
		end
	end

	return style.texture or '', 48, 48
end

---Get image coords for a circle style (for atlas textures that need cropping)
---@param styleNum number The circle style number
---@return table|nil coords {left, right, top, bottom} or nil for full texture
function module:GetCircleStyleImageCoords(styleNum)
	local style = CIRCLE_STYLES[styleNum]
	if not style then
		return nil
	end

	if style.type == 'atlas' and C_Texture and C_Texture.GetAtlasInfo then
		local info = C_Texture.GetAtlasInfo(style.atlas)
		if info then
			return { info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord }
		end
	end

	return nil
end

---Get the number of available circle styles
---@return number count
function module:GetCircleStyleCount()
	return #CIRCLE_STYLES
end

---Apply circle style to a texture object
---@param tex Texture The texture to apply the style to
---@param styleNum number The circle style number
local function ApplyCircleStyle(tex, styleNum)
	local style = CIRCLE_STYLES[styleNum] or CIRCLE_STYLES[1]
	if style.type == 'atlas' then
		tex:SetAtlas(style.atlas)
	else
		tex:SetTexture(style.texture)
	end
end

---Update ring and trail textures to match current circle style setting
function module:UpdateCircleStyle()
	local DB = module:GetDB()
	local styleNum = DB.mouseRing.circleStyle or 1

	-- Update ring texture
	if mouseRingFrame and mouseRingFrame.ring then
		ApplyCircleStyle(mouseRingFrame.ring, styleNum)
	end

	-- Update all trail elements (both pooled and active)
	for _, element in ipairs(trailPool) do
		ApplyCircleStyle(element.texture, styleNum)
	end
	for _, element in ipairs(activeTrailElements) do
		ApplyCircleStyle(element.texture, styleNum)
	end
end

---Get color based on settings
---@param colorSettings table Color settings with mode, r, g, b
---@return number r Red component
---@return number g Green component
---@return number b Blue component
local function GetEffectColor(colorSettings)
	if colorSettings.mode == 'class' then
		local _, class = UnitClass('player')
		local classColor = RAID_CLASS_COLORS[class]
		if classColor then
			return classColor.r, classColor.g, classColor.b
		end
	end
	return colorSettings.r, colorSettings.g, colorSettings.b
end

---Check if mouse effects should be visible based on combat state
---@param settings table Effect settings with combatOnly field
---@return boolean visible Whether effect should be visible
local function ShouldShowEffect(settings)
	if not settings.enabled then
		return false
	end
	if settings.combatOnly then
		return InCombatLockdown()
	end
	return true
end

-- ==================== GCD HELPER FUNCTIONS ====================

---Read spell cooldown with compatibility for different API versions
---@param spellID number
---@return number|nil start
---@return number|nil duration
---@return number|nil modRate
local function ReadSpellCooldown(spellID)
	if C_Spell and C_Spell.GetSpellCooldown then
		local result = C_Spell.GetSpellCooldown(spellID)
		if type(result) == 'table' then
			return result.startTime or result.start, result.duration, result.modRate
		else
			-- Older tuple format
			local start, duration, _, modRate = C_Spell.GetSpellCooldown(spellID)
			return start, duration, modRate
		end
	end
	if GetSpellCooldown then
		local start, duration = GetSpellCooldown(spellID)
		return start, duration, nil
	end
	return nil, nil, nil
end

---Check if a cooldown is currently active (handles secret values in 12.0+)
---@param start number|nil
---@param duration number|nil
---@return boolean
local function IsCooldownActive(start, duration)
	if not start or not duration then
		return false
	end

	-- Use pcall to safely handle "secret" cooldown values in 12.0+
	local ok, result = pcall(function()
		if duration == 0 or start == 0 then
			return false
		end
		return true
	end)

	if not ok then
		-- Comparison failed due to secret values, treat as active
		return true
	end

	return result and true or false
end

-- ==================== MOUSE RING IMPLEMENTATION ====================

---Initialize the mouse ring frame
function module:InitializeMouseRing()
	if mouseRingFrame then
		return
	end

	mouseRingFrame = CreateFrame('Frame', 'SUI_MouseRing', UIParent)
	mouseRingFrame:SetFrameStrata('TOOLTIP')
	mouseRingFrame:SetFrameLevel(9999)

	-- Ring texture
	mouseRingFrame.ring = mouseRingFrame:CreateTexture(nil, 'OVERLAY')
	local DB = module:GetDB()
	ApplyCircleStyle(mouseRingFrame.ring, DB.mouseRing.circleStyle or 1)
	mouseRingFrame.ring:SetAllPoints()
	mouseRingFrame.ring:SetBlendMode('ADD')

	-- Optional center dot
	mouseRingFrame.dot = mouseRingFrame:CreateTexture(nil, 'OVERLAY')
	mouseRingFrame.dot:SetTexture('Interface\\AddOns\\SpartanUI\\images\\blank')
	mouseRingFrame.dot:SetPoint('CENTER')
	mouseRingFrame.dot:Hide()

	-- GCD Cooldown overlay (uses Blizzard's CooldownFrameTemplate for swipe animation)
	gcdCooldown = CreateFrame('Cooldown', 'SUI_MouseRing_GCD', mouseRingFrame, 'CooldownFrameTemplate')
	gcdCooldown:SetAllPoints()
	gcdCooldown:EnableMouse(false)
	gcdCooldown:SetDrawSwipe(true)
	gcdCooldown:SetDrawEdge(false)
	gcdCooldown:SetHideCountdownNumbers(true)
	if gcdCooldown.SetDrawBling then
		gcdCooldown:SetDrawBling(false)
	end
	if gcdCooldown.SetUseCircularEdge then
		gcdCooldown:SetUseCircularEdge(true)
	end
	gcdCooldown:SetFrameLevel(mouseRingFrame:GetFrameLevel() + 1)
	gcdCooldown:Hide()

	mouseRingFrame:Hide()
end

---Update GCD cooldown display
function module:UpdateGCDCooldown()
	local DB = module:GetDB()

	if not gcdCooldown or not DB.mouseRing or not DB.mouseRing.gcdEnabled then
		if gcdCooldown then
			gcdCooldown:Hide()
		end
		return
	end

	local start, duration, modRate = ReadSpellCooldown(GCD_SPELL_ID)

	if IsCooldownActive(start, duration) then
		-- Set swipe color to match ring color
		local r, g, b = GetEffectColor(DB.mouseRing.color)
		gcdCooldown:SetSwipeColor(r, g, b, DB.mouseRing.gcdAlpha or 0.8)

		-- Set swipe texture to match ring
		if gcdCooldown.SetSwipeTexture then
			gcdCooldown:SetSwipeTexture('Interface\\AddOns\\SpartanUI\\images\\circle')
		end

		-- Apply reverse setting
		if gcdCooldown.SetReverse then
			gcdCooldown:SetReverse(DB.mouseRing.gcdReverse or false)
		end

		gcdCooldown:Show()
		if modRate then
			gcdCooldown:SetCooldown(start, duration, modRate)
		else
			gcdCooldown:SetCooldown(start, duration)
		end
	else
		gcdCooldown:Hide()
	end
end

-- Mouse Trail Implementation (Object Pool Pattern)

---Create a single trail element
---@return Frame element Trail element frame
local function CreateTrailElement()
	local element = CreateFrame('Frame', nil, UIParent)
	element:SetFrameStrata('TOOLTIP')
	element:SetFrameLevel(9998)

	element.texture = element:CreateTexture(nil, 'OVERLAY')
	local DB = module:GetDB()
	ApplyCircleStyle(element.texture, DB.mouseRing.circleStyle or 1)
	element.texture:SetAllPoints()
	element.texture:SetBlendMode('ADD')

	-- Fade animation group
	element.fadeAnim = element:CreateAnimationGroup()
	local fade = element.fadeAnim:CreateAnimation('Alpha')
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0)
	fade:SetSmoothing('OUT')
	element.fadeAnim.fade = fade

	element.fadeAnim:SetScript('OnFinished', function()
		module:ReturnTrailElement(element)
	end)

	element:Hide()
	return element
end

---Initialize the trail element pool
function module:InitializeMouseTrail()
	-- Pre-populate pool
	for i = 1, MAX_POOL_SIZE do
		local element = CreateTrailElement()
		table.insert(trailPool, element)
	end
end

---Get a trail element from the pool
---@return Frame|nil element Trail element or nil if pool is empty
function module:GetTrailElement()
	local element = table.remove(trailPool)
	if element then
		table.insert(activeTrailElements, element)
	end
	return element
end

---Return a trail element to the pool
---@param element Frame Trail element to return
function module:ReturnTrailElement(element)
	element:Hide()
	element:ClearAllPoints()
	element.fadeAnim:Stop()

	for i, active in ipairs(activeTrailElements) do
		if active == element then
			table.remove(activeTrailElements, i)
			break
		end
	end

	table.insert(trailPool, element)
end

-- Shared OnUpdate Handler

---Update mouse effects (called every frame when active)
---@param elapsed number Time since last frame
local function MouseEffectsOnUpdate(_, elapsed)
	local DB = module:GetDB()
	local scale = UIParent:GetEffectiveScale()
	local cursorX, cursorY = GetCursorPosition()
	cursorX, cursorY = cursorX / scale, cursorY / scale

	local ringVisible = ShouldShowEffect(DB.mouseRing)
	local trailVisible = ShouldShowEffect(DB.mouseTrail)

	-- Update Mouse Ring position
	if ringVisible and mouseRingFrame then
		local size = DB.mouseRing.size
		mouseRingFrame:SetSize(size, size)
		mouseRingFrame:ClearAllPoints()
		mouseRingFrame:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', cursorX, cursorY)

		local r, g, b = GetEffectColor(DB.mouseRing.color)
		mouseRingFrame.ring:SetVertexColor(r, g, b, DB.mouseRing.alpha)

		if DB.mouseRing.showCenterDot then
			mouseRingFrame.dot:SetSize(DB.mouseRing.centerDotSize, DB.mouseRing.centerDotSize)
			mouseRingFrame.dot:SetVertexColor(r, g, b, DB.mouseRing.alpha)
			mouseRingFrame.dot:Show()
		else
			mouseRingFrame.dot:Hide()
		end

		mouseRingFrame:Show()
	elseif mouseRingFrame then
		mouseRingFrame:Hide()
	end

	-- Update Mouse Trail
	if trailVisible then
		timeAccumulator = timeAccumulator + elapsed

		local dx = cursorX - lastCursorX
		local dy = cursorY - lastCursorY
		local distanceSq = dx * dx + dy * dy

		local preset = DENSITY_PRESETS[DB.mouseTrail.density] or DENSITY_PRESETS.medium

		if distanceSq >= MIN_MOVE_DISTANCE_SQ and timeAccumulator >= preset.spawnRate then
			if #activeTrailElements < preset.maxElements then
				local element = module:GetTrailElement()
				if element then
					local size = DB.mouseTrail.size
					element:SetSize(size, size)
					element:ClearAllPoints()
					element:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', cursorX, cursorY)

					local r, g, b = GetEffectColor(DB.mouseTrail.color)
					element.texture:SetVertexColor(r, g, b, DB.mouseTrail.alpha)

					element.fadeAnim.fade:SetDuration(preset.fadeDuration)
					element:Show()
					element.fadeAnim:Play()
				end
			end
			timeAccumulator = 0
		end
	end

	lastCursorX, lastCursorY = cursorX, cursorY
end

-- Public API

---Initialize mouse effects (called from UIEnhancements OnEnable)
function module:InitializeMouseEffects()
	module:InitializeMouseRing()
	module:InitializeMouseTrail()

	-- Create update frame
	if not updateFrame then
		updateFrame = CreateFrame('Frame')
	end

	-- Register events
	updateFrame:RegisterEvent('PLAYER_REGEN_DISABLED')
	updateFrame:RegisterEvent('PLAYER_REGEN_ENABLED')
	updateFrame:RegisterEvent('SPELL_UPDATE_COOLDOWN')
	updateFrame:RegisterEvent('ACTIONBAR_UPDATE_COOLDOWN')
	if updateFrame.RegisterUnitEvent then
		updateFrame:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'player')
	end

	updateFrame:SetScript('OnEvent', function(_, event, unit, _, spellID)
		if event == 'PLAYER_REGEN_DISABLED' or event == 'PLAYER_REGEN_ENABLED' then
			module:ApplyMouseEffectSettings()
		elseif event == 'SPELL_UPDATE_COOLDOWN' or event == 'ACTIONBAR_UPDATE_COOLDOWN' then
			module:UpdateGCDCooldown()
		elseif event == 'UNIT_SPELLCAST_SUCCEEDED' and unit == 'player' then
			-- Update GCD based on the spell we just cast
			module:UpdateGCDCooldown()
		end
	end)

	-- Apply settings now so effects are active on login if enabled
	module:ApplyMouseEffectSettings()
end

---Apply mouse effect settings (called when settings change or combat state changes)
function module:ApplyMouseEffectSettings()
	local DB = module:GetDB()
	local ringEnabled = DB.mouseRing and DB.mouseRing.enabled
	local trailEnabled = DB.mouseTrail and DB.mouseTrail.enabled
	local needsOnUpdate = ringEnabled or trailEnabled

	if needsOnUpdate and not isOnUpdateActive then
		updateFrame:SetScript('OnUpdate', MouseEffectsOnUpdate)
		isOnUpdateActive = true
		-- Reset state
		timeAccumulator = 0
		local scale = UIParent:GetEffectiveScale()
		local cursorX, cursorY = GetCursorPosition()
		lastCursorX, lastCursorY = cursorX / scale, cursorY / scale
	elseif not needsOnUpdate and isOnUpdateActive then
		updateFrame:SetScript('OnUpdate', nil)
		if mouseRingFrame then
			mouseRingFrame:Hide()
		end
		isOnUpdateActive = false
	end
end

---Restore mouse effects to default state (called from UIEnhancements OnDisable)
function module:RestoreMouseEffects()
	if updateFrame then
		updateFrame:SetScript('OnUpdate', nil)
		updateFrame:UnregisterAllEvents()
	end

	if mouseRingFrame then
		mouseRingFrame:Hide()
	end

	-- Return all active trail elements to pool
	for i = #activeTrailElements, 1, -1 do
		module:ReturnTrailElement(activeTrailElements[i])
	end

	isOnUpdateActive = false
end
