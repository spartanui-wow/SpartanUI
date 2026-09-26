---@type SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.ActionBars
local module = SUI:GetModule('ActionBars')

local NUM_PET_SLOTS = NUM_PET_ACTION_SLOTS or 10
local NUM_STANCE_SLOTS_MAX = NUM_STANCE_SLOTS or 10

-- Blizzard's pet and stance buttons are reused rather than rebuilt. Their parent bars stay
-- registered for events, so Blizzard's own code keeps updating icons, cooldowns, autocast
-- and key bindings. Only the buttons are moved onto SpartanUI's bars.

---@param prefix string
---@param count number
---@param parentBar? Frame
---@return Button[]
local function CollectBlizzardButtons(prefix, count, parentBar)
	local buttons = {}
	for i = 1, count do
		local button = (parentBar and parentBar.actionButtons and parentBar.actionButtons[i]) or _G[prefix .. i]
		if button then
			buttons[#buttons + 1] = button
		end
	end
	return buttons
end

----------------------------------------------------------------------------------------------------
-- Pet bar
----------------------------------------------------------------------------------------------------

---@class SUI.ActionBars.PetBar : SUI.ActionBars.Bar
local PetBar = {}

function PetBar:UpdateButtons()
	self.manageButtonVisibility = true
	for _, button in ipairs(self.buttons) do
		button:SetParent(self)
		self:RegisterHoverChild(button)
	end
	self:LayoutButtons(#self.buttons)
	local db = self:GetDB()
	for _, button in ipairs(self.buttons) do
		local hotkey = button.HotKey
		if hotkey then
			hotkey:SetAlpha(db.hotkeyText and 1 or 0)
		end
	end
end

function module:CreatePetBar()
	if self.bars.BT4BarPetBar then
		return
	end
	local bar = self:NewBar('BT4BarPetBar', 'SUI_PetBar', L['Pet Bar'], function()
		return module.CurrentSettings.pet
	end) ---@type SUI.ActionBars.PetBar
	Mixin(bar, PetBar)
	bar.cropIcons = true
	bar.buttons = CollectBlizzardButtons('PetActionButton', NUM_PET_SLOTS, PetActionBar)

	-- Blizzard tints out-of-range pet abilities from its own bar's OnUpdate, which stops
	-- running once that bar is hidden, so the tint is refreshed here instead
	if GetPetActionInfo and ActionButton_UpdateRangeIndicator then
		local canAccess = SUI.BlizzAPI.canaccessvalue
		local elapsedTotal = 0
		-- A child frame of its own, so the bar's OnUpdate stays free for hover polling
		local ranger = CreateFrame('Frame', nil, bar)
		ranger:SetScript('OnUpdate', function(_, elapsed)
			elapsedTotal = elapsedTotal + elapsed
			if elapsedTotal < (TOOLTIP_UPDATE_TIME or 0.2) then
				return
			end
			elapsedTotal = 0
			for i, button in ipairs(bar.buttons) do
				local checksRange, inRange = select(8, GetPetActionInfo(i))
				if canAccess(checksRange) and canAccess(inRange) then
					ActionButton_UpdateRangeIndicator(button, checksRange, inRange)
				end
			end
		end)
	end
end

----------------------------------------------------------------------------------------------------
-- Stance bar
----------------------------------------------------------------------------------------------------

---@class SUI.ActionBars.StanceBar : SUI.ActionBars.Bar
local StanceBarMixin = {}

function StanceBarMixin:UpdateButtons()
	self.manageButtonVisibility = true
	local numForms = GetNumShapeshiftForms() or 0
	for _, button in ipairs(self.buttons) do
		button:SetParent(self)
		self:RegisterHoverChild(button)
	end
	self:LayoutButtons(math.min(numForms, #self.buttons))
	-- Classes without stances get no bar and no mover
	self.forceHidden = numForms == 0
	local db = self:GetDB()
	for _, button in ipairs(self.buttons) do
		local hotkey = button.HotKey
		if hotkey then
			hotkey:SetAlpha(db.hotkeyText and 1 or 0)
		end
	end
end

function module:CreateStanceBar()
	if self.bars.BT4BarStanceBar then
		return
	end
	local blizzardBar = _G.StanceBar or _G.StanceBarFrame
	local bar = self:NewBar('BT4BarStanceBar', 'SUI_StanceBar', L['Stance Bar'], function()
		return module.CurrentSettings.stance
	end) ---@type SUI.ActionBars.StanceBar
	Mixin(bar, StanceBarMixin)
	bar.hideInBlizzardVehicle = true
	bar.cropIcons = true
	bar.buttons = CollectBlizzardButtons(_G.StanceButton1 and 'StanceButton' or 'ShapeshiftButton', NUM_STANCE_SLOTS_MAX, blizzardBar)

	-- Learning or losing a form changes how many buttons the bar needs
	local watcher = CreateFrame('Frame')
	watcher:RegisterEvent('UPDATE_SHAPESHIFT_FORMS')
	watcher:RegisterEvent('PLAYER_ENTERING_WORLD')
	watcher:SetScript('OnEvent', function()
		if module:IsActive() then
			bar:Apply()
		end
	end)
end

----------------------------------------------------------------------------------------------------
-- Totem bar (Wrath-era shamans)
----------------------------------------------------------------------------------------------------

function module:CreateTotemBar()
	local totems = _G.MultiCastActionBarFrame
	-- Only Wrath and Cataclysm shamans have a totem bar
	local hasTotemBar = (SUI.IsWrath or SUI.IsCata) and totems and HasMultiCastActionBar and select(2, UnitClass('player')) == 'SHAMAN'
	if self.bars.MultiCastActionBarFrame or not hasTotemBar then
		return
	end
	local bar = self:NewBar('MultiCastActionBarFrame', 'SUI_TotemBar', L['Totem Bar'], function()
		return module.CurrentSettings.totem
	end)
	-- Edit Mode replaces the anchoring methods on its frames; the Base versions skip its hooks
	local clearPoints = totems.ClearAllPointsBase or totems.ClearAllPoints
	local setPoint = totems.SetPointBase or totems.SetPoint
	bar.UpdateButtons = function(self)
		self:SetSize(230, 40)
		if not self:GetDB().enabled then
			return
		end
		if not totems.system then
			totems:SetScript('OnShow', nil)
			totems:SetScript('OnHide', nil)
			totems:SetScript('OnUpdate', nil)
			totems.ignoreFramePositionManager = true
		end
		totems:SetParent(self)
		clearPoints(totems)
		setPoint(totems, 'TOPLEFT', self, 'TOPLEFT', 3, 1)
	end
end
