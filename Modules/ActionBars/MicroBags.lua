---@type SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.ActionBars
local module = SUI:GetModule('ActionBars')

-- Micro menu and bag buttons are not protected, so unlike the action bars they can be
-- moved at any time, including in combat.

----------------------------------------------------------------------------------------------------
-- Micro menu
----------------------------------------------------------------------------------------------------

-- Used only on clients without Blizzard's unified MicroMenu frame
local FALLBACK_MICRO_BUTTONS = {
	'CharacterMicroButton',
	'ProfessionMicroButton',
	'PlayerSpellsMicroButton',
	'SpellbookMicroButton',
	'TalentMicroButton',
	'AchievementMicroButton',
	'QuestLogMicroButton',
	'HousingMicroButton',
	'SocialsMicroButton',
	'GuildMicroButton',
	'PVPMicroButton',
	'LFGMicroButton',
	'LFDMicroButton',
	'CollectionsMicroButton',
	'EJMicroButton',
	'WorldMapMicroButton',
	'StoreMicroButton',
	'MainMenuMicroButton',
	'HelpMicroButton',
}

---Every micro button in display order, captured once from Blizzard's menu.
---@return Button[]
local function CollectMicroButtons()
	local list = {}
	if MicroMenu and MicroMenu.GetChildren then
		for _, child in ipairs({ MicroMenu:GetChildren() }) do
			if child.layoutIndex then
				list[#list + 1] = child
			end
		end
		table.sort(list, function(a, b)
			return a.layoutIndex < b.layoutIndex
		end)
	end
	if #list == 0 then
		for _, name in ipairs(FALLBACK_MICRO_BUTTONS) do
			if _G[name] then
				list[#list + 1] = _G[name]
			end
		end
	end
	return list
end

---@class SUI.ActionBars.MicroMenu : SUI.ActionBars.Bar
local MicroBar = {}

function MicroBar:UpdateButtons()
	self.manageButtonVisibility = true
	if self.lent or not self:GetDB().enabled then
		return
	end
	-- The bar is a secure frame, so resizing it has to wait for combat to end
	if InCombatLockdown() then
		module:RunOutOfCombat('micro', self.UpdateButtons, self)
		return
	end
	local shown = {}
	for _, button in ipairs(self.allButtons) do
		button:SetParent(self)
		self:RegisterHoverChild(button)
		if button:IsShown() then
			shown[#shown + 1] = button
		end
	end
	self.buttons = shown
	self:LayoutButtons(#shown)
end

---Give the buttons back to Blizzard's menu while the vehicle bar or pet battle UI shows it.
function MicroBar:LendToBlizzard()
	self.lent = true
	for _, button in ipairs(self.allButtons) do
		module:RestoreButtonSize(button)
		button:SetParent(MicroMenu)
	end
end

function MicroBar:Reclaim()
	self.lent = false
	self:UpdateButtons()
end

---@param parent Frame|nil
function MicroBar:OnBlizzardReparent(parent)
	local blizzardOwnsIt = parent and parent ~= MicroMenuContainer and parent ~= module.hider and parent ~= UIParent
	if parent == OverrideActionBar and not module:UseBlizzardVehicleUI() then
		blizzardOwnsIt = false
	end
	if blizzardOwnsIt then
		self:LendToBlizzard()
	elseif self.lent then
		self:Reclaim()
	end
end

function module:CreateMicroMenu()
	if self.bars.BT4BarMicroMenu then
		return
	end
	local bar = self:NewBar('BT4BarMicroMenu', 'SUI_MicroMenu', L['Micro menu'], function()
		return module.CurrentSettings.micro
	end) ---@type SUI.ActionBars.MicroMenu
	Mixin(bar, MicroBar)
	bar.allButtons = CollectMicroButtons()
	bar.buttons = {}

	-- Blizzard shows and hides some buttons (store, help) as the game state changes
	if UpdateMicroButtons then
		hooksecurefunc('UpdateMicroButtons', function()
			if module:IsActive() and not bar.lent then
				bar:UpdateButtons()
			end
		end)
	end

	if MicroMenu then
		hooksecurefunc(MicroMenu, 'SetParent', function(_, parent)
			if module:IsActive() and bar:GetDB().enabled then
				bar:OnBlizzardReparent(parent)
			end
		end)
	end

	-- Blizzard only hands the menu back through the main bar's OnShow, which never fires
	-- while that bar is hidden, so take the buttons back once the pet battle or vehicle ends
	local function reclaimIfDone()
		if not (module:IsActive() and bar.lent) then
			return
		end
		local inPetBattle = C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle()
		local overrideShown = OverrideActionBar and OverrideActionBar:IsShown()
		if not inPetBattle and not overrideShown then
			bar:Reclaim()
		end
	end
	local watcher = CreateFrame('Frame')
	if C_PetBattles then
		watcher:RegisterEvent('PET_BATTLE_CLOSE')
	end
	watcher:RegisterUnitEvent('UNIT_EXITED_VEHICLE', 'player')
	watcher:SetScript('OnEvent', reclaimIfDone)
	if ActionBarController_UpdateAll then
		hooksecurefunc('ActionBarController_UpdateAll', reclaimIfDone)
	end
end

----------------------------------------------------------------------------------------------------
-- Bag bar
----------------------------------------------------------------------------------------------------

local noop = function() end

---@class SUI.ActionBars.BagBar : SUI.ActionBars.Bar
local BagBar = {}

---@return Button[]
function BagBar:GetOrderedButtons()
	local db = self:GetDB()
	local list = {}
	local function add(button)
		if button then
			list[#list + 1] = button
		end
	end

	if db.showKeyring and KeyRingButton and (not C_ActionBar or not C_ActionBar.ShouldShowKeyring or C_ActionBar.ShouldShowKeyring()) then
		add(KeyRingButton)
	end
	if db.showReagentBag then
		add(_G.CharacterReagentBag0Slot)
	end
	if not db.onlyBackpack then
		for i = 3, 0, -1 do
			add(_G['CharacterBag' .. i .. 'Slot'])
		end
	end
	add(MainMenuBarBackpackButton)

	if db.reverse then
		local reversed = {}
		for i = #list, 1, -1 do
			reversed[#reversed + 1] = list[i]
		end
		list = reversed
	end
	return list
end

function BagBar:UpdateButtons()
	self.manageButtonVisibility = true
	if not self:GetDB().enabled then
		return
	end
	if InCombatLockdown() then
		module:RunOutOfCombat('bags', self.UpdateButtons, self)
		return
	end
	local wanted = self:GetOrderedButtons()
	local keep = {}
	for _, button in ipairs(wanted) do
		keep[button] = true
	end

	-- Buttons the player turned off go back to Blizzard's hidden bag bar
	for _, button in ipairs(self.buttons or {}) do
		if not keep[button] then
			module:RestoreButtonSize(button)
			button:SetParent(module.hider)
		end
	end

	for _, button in ipairs(wanted) do
		button:SetParent(self)
		button:Show()
		self:RegisterHoverChild(button)
	end
	self.buttons = wanted
	self:LayoutButtons(#wanted)
	module:AddMasqueButtons(self)
end

function module:CreateBagBar()
	if self.bars.BT4BarBagBar then
		return
	end
	local bar = self:NewBar('BT4BarBagBar', 'SUI_BagBar', L['Bag bar'], function()
		return module.CurrentSettings.bags
	end) ---@type SUI.ActionBars.BagBar
	Mixin(bar, BagBar)
	bar.buttons = {}

	-- Retail collapses the bag slots through an expand toggle; keep them all visible.
	-- Left alone when Blizzard's own bag bar is in use so its toggle keeps working.
	if not bar:GetDB().enabled then
		return
	end
	for _, name in ipairs({ 'CharacterReagentBag0Slot', 'CharacterBag0Slot', 'CharacterBag1Slot', 'CharacterBag2Slot', 'CharacterBag3Slot' }) do
		local slot = _G[name]
		if slot and slot.SetBarExpanded then
			slot.SetBarExpanded = noop
		end
	end
	if BagsBar and EventRegistry then
		EventRegistry:UnregisterCallback('MainMenuBarManager.OnExpandChanged', BagsBar)
	end
	if BagsBar and BagsBar.Layout then
		hooksecurefunc(BagsBar, 'Layout', function()
			if module:IsActive() then
				bar:UpdateButtons()
			end
		end)
	end
end

----------------------------------------------------------------------------------------------------
-- Queue status (Retail's group finder eye)
----------------------------------------------------------------------------------------------------

function module:CreateQueueStatus()
	if self.bars.BT4BarQueueStatus or not QueueStatusButton or not SUI.IsRetail then
		return
	end
	local bar = self:NewBar('BT4BarQueueStatus', 'SUI_QueueStatus', L['Queue Status'], function()
		return module.CurrentSettings.queue
	end)
	bar.UpdateButtons = function(self)
		self:SetSize(45, 45)
		QueueStatusButton:SetParent(self)
		QueueStatusButton:ClearAllPoints()
		QueueStatusButton:SetPoint('CENTER', self, 'CENTER')
	end
	hooksecurefunc(QueueStatusButton, 'UpdatePosition', function()
		if module:IsActive() and QueueStatusButton:GetParent() == bar then
			QueueStatusButton:ClearAllPoints()
			QueueStatusButton:SetPoint('CENTER', bar, 'CENTER')
		end
	end)
end
