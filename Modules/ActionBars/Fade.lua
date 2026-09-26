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
	'UNIT_SPELLCAST_START',
	'UNIT_SPELLCAST_STOP',
	'UNIT_SPELLCAST_CHANNEL_START',
	'UNIT_SPELLCAST_CHANNEL_STOP',
	'UNIT_ENTERED_VEHICLE',
	'UNIT_EXITED_VEHICLE',
	'PLAYER_ENTERING_WORLD',
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
	if settings.showInCombat and InCombatLockdown() then
		return true
	end
	if settings.showWithTarget and (UnitExists('target') or UnitExists('focus')) then
		return true
	end
	if settings.showWhileCasting and (UnitCastingInfo('player') or UnitChannelInfo('player')) then
		return true
	end
	if settings.showInVehicle and UnitHasVehicleUI and UnitHasVehicleUI('player') then
		return true
	end
	if settings.showWhenHurt and PlayerIsHurt() then
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
		parent:RegisterEvent(event)
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
		module:UpdateGlobalFade()
	end)
end

---@param hovering boolean
function module:SetFadeHover(hovering)
	self.fadeHover = hovering
	self:UpdateGlobalFade()
end

----------------------------------------------------------------------------------------------------
-- Masque
----------------------------------------------------------------------------------------------------

local MASQUE_TYPES = {
	BT4BarPetBar = 'Pet',
	BT4BarStanceBar = 'Action',
	BT4BarBagBar = 'Item',
}

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
				group:AddButton(button, nil, MASQUE_TYPES[bar.key])
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
