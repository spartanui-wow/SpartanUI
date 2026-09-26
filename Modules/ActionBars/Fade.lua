---@type SUI
local SUI = SUI
---@class SUI.Module.ActionBars
local module = SUI:GetModule('ActionBars')

module.masqueGroups = {}

----------------------------------------------------------------------------------------------------
-- Global fade
----------------------------------------------------------------------------------------------------

-- Bars that opt in are parented to one shared frame whose alpha drops while the player is
-- idle. Alpha is not a protected property, so this works in combat too.

local fadeEvents = {
	'PLAYER_REGEN_DISABLED',
	'PLAYER_REGEN_ENABLED',
	'PLAYER_TARGET_CHANGED',
	'PLAYER_FOCUS_CHANGED',
	'PLAYER_ENTERING_WORLD',
	'UPDATE_POSSESS_BAR',
	'UPDATE_OVERRIDE_ACTIONBAR',
	'UPDATE_VEHICLE_ACTIONBAR',
	'UPDATE_BONUS_ACTIONBAR',
	'PLAYER_CAN_GLIDE_CHANGED',
	'PLAYER_IS_GLIDING_CHANGED',
}

-- Only the player's own casts and vehicle changes matter; registering these for every unit
-- would wake the fade on every cast in a raid
local playerEvents = {
	'UNIT_SPELLCAST_START',
	'UNIT_SPELLCAST_STOP',
	'UNIT_SPELLCAST_CHANNEL_START',
	'UNIT_SPELLCAST_CHANNEL_STOP',
	'UNIT_SPELLCAST_EMPOWER_START',
	'UNIT_SPELLCAST_EMPOWER_STOP',
	'UNIT_ENTERED_VEHICLE',
	'UNIT_EXITED_VEHICLE',
}

---@return boolean
local function PlayerIsHurt()
	local health, maxHealth = UnitHealth('player'), UnitHealthMax('player')
	local canAccess = SUI.BlizzAPI and SUI.BlizzAPI.canaccessvalue or canaccessvalue
	if canAccess and (not canAccess(health) or not canAccess(maxHealth)) then
		return false
	end
	return health and maxHealth and health < maxHealth
end

---@return boolean
function module:ShouldShowFadedBars()
	local settings = self.CurrentSettings.globalFade
	if self.fadeHover or self.gridShown then
		return true
	end
	-- Combat lockdown only starts after PLAYER_REGEN_DISABLED, so ask about the player instead
	if settings.showInCombat and (self.enteringCombat or UnitAffectingCombat('player')) then
		return true
	end
	if settings.showWithTarget and (UnitExists('target') or UnitExists('focus')) then
		return true
	end
	if settings.showWhileCasting and (UnitCastingInfo('player') or UnitChannelInfo('player')) then
		return true
	end
	if settings.showInVehicle then
		if UnitHasVehicleUI and UnitHasVehicleUI('player') then
			return true
		end
		-- Possess, override and skyriding pages count as being in a vehicle
		local possess = (C_ActionBar and C_ActionBar.IsPossessBarVisible) or IsPossessBarVisible
		local override = (C_ActionBar and C_ActionBar.HasOverrideActionBar) or HasOverrideActionBar
		if (possess and possess()) or (override and override()) then
			return true
		end
		if C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
			-- Mounting up for skyriding only makes gliding possible; taking off is a separate event
			local isGliding, canGlide = C_PlayerInfo.GetGlidingInfo()
			if isGliding or canGlide then
				return true
			end
		end
	end
	-- Health is protected on Retail, where this rule is not offered
	if settings.showWhenHurt and not SUI.IsRetail and PlayerIsHurt() then
		return true
	end
	return false
end

function module:UpdateGlobalFade()
	local parent = self.fadeParent
	if not parent then
		return
	end
	local settings = self.CurrentSettings.globalFade
	if not settings.enabled or self:ShouldShowFadedBars() then
		parent:SetAlpha(1)
	else
		parent:SetAlpha(settings.alpha or 0.3)
	end
end

function module:SetupGlobalFade()
	if self.fadeParent then
		return
	end
	local parent = CreateFrame('Frame', 'SUI_ActionBarFadeParent', UIParent)
	parent:SetAllPoints(UIParent)
	self.fadeParent = parent

	for _, event in ipairs(fadeEvents) do
		pcall(parent.RegisterEvent, parent, event)
	end
	for _, event in ipairs(playerEvents) do
		pcall(parent.RegisterUnitEvent, parent, event, 'player')
	end
	-- Health is only watched where it is not a protected value
	if not SUI.IsRetail then
		parent:RegisterUnitEvent('UNIT_HEALTH', 'player')
		parent:RegisterUnitEvent('UNIT_MAXHEALTH', 'player')
	end
	parent:SetScript('OnEvent', function(_, event, unit)
		if unit and type(unit) == 'string' and event:find('^UNIT_') and unit ~= 'player' then
			return
		end
		if event == 'PLAYER_REGEN_DISABLED' then
			module.enteringCombat = true
		elseif event == 'PLAYER_REGEN_ENABLED' then
			module.enteringCombat = false
		end
		module:UpdateGlobalFade()
	end)
end

---@param hovering boolean
function module:SetFadeHover(hovering)
	-- Leaving one faded bar must not undo the hover of another faded bar the cursor is on
	if not hovering then
		for _, bar in pairs(self.bars) do
			if bar.mouseInside and bar.GetDB and bar:GetDB().inheritGlobalFade then
				hovering = true
				break
			end
		end
	end
	self.fadeHover = hovering
	self:UpdateGlobalFade()
end

----------------------------------------------------------------------------------------------------
-- Masque
----------------------------------------------------------------------------------------------------

local MASQUE_TYPES = {
	BT4BarPetBar = 'Pet',
	BT4BarStanceBar = 'Action',
}

---@param button Button
---@return string
local function BagMasqueType(button)
	if button == _G.CharacterReagentBag0Slot then
		return 'ReagentBag'
	elseif button == MainMenuBarBackpackButton then
		return 'Backpack'
	end
	return 'BagSlot'
end

-- Bars holding a single Blizzard frame rather than buttons
local NO_MASQUE = {
	BT4BarMicroMenu = true,
	BT4BarQueueStatus = true,
	MultiCastActionBarFrame = true,
}

local masqueAdded = setmetatable({}, { __mode = 'k' })

---Skin any of a bar's buttons Masque has not seen yet. Bag buttons are gathered after the
---groups exist, so this also runs from the bag bar's layout.
---@param bar SUI.ActionBars.Bar
function module:AddMasqueButtons(bar)
	local group = self.masqueGroups[bar.key]
	if not group then
		return
	end
	for _, button in ipairs(bar.allButtons or bar.buttons) do
		if not masqueAdded[button] then
			masqueAdded[button] = true
			if button.AddToMasque then
				button:AddToMasque(group)
			else
				local kind = bar.key == 'BT4BarBagBar' and BagMasqueType(button) or MASQUE_TYPES[bar.key]
				group:AddButton(button, nil, kind)
			end
		end
	end
end

function module:SetupMasque()
	local Masque = LibStub('Masque', true)
	if not Masque or not self.CurrentSettings.masque then
		return
	end
	for key, bar in pairs(self.bars) do
		if not NO_MASQUE[key] and not self.masqueGroups[key] then
			self.masqueGroups[key] = Masque:Group('SpartanUI', bar.displayName, key)
			self:AddMasqueButtons(bar)
		end
	end
end
