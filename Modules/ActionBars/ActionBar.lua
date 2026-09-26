---@type SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.ActionBars
local module = SUI:GetModule('ActionBars')

local LAB = LibStub('LibActionButton-1.0')
local _, playerClass = UnitClass('player')

local NUM_BUTTONS = 12
local NUM_STATES = 18

-- Bars that sit on a Blizzard action page get the matching Blizzard binding, so keys the
-- player bound in the default UI keep working. Bars 2 and 7-10 have no Blizzard binding
-- and use the CLICK bindings declared in Bindings.xml instead.
local BLIZZARD_BINDINGS = {
	[1] = 'ACTIONBUTTON%d',
	[3] = 'MULTIACTIONBAR3BUTTON%d',
	[4] = 'MULTIACTIONBAR4BUTTON%d',
	[5] = 'MULTIACTIONBAR2BUTTON%d',
	[6] = 'MULTIACTIONBAR1BUTTON%d',
	[13] = 'MULTIACTIONBAR5BUTTON%d',
	[14] = 'MULTIACTIONBAR6BUTTON%d',
	[15] = 'MULTIACTIONBAR7BUTTON%d',
}
module.BLIZZARD_BINDINGS = BLIZZARD_BINDINGS

---@param barID number
---@return string
function module:GetActionBarFrameName(barID)
	return 'SUI_ActionBar' .. barID
end

---@param barID number
---@param index number
---@return string
function module:GetActionButtonName(barID, index)
	return 'SUI_ActionBar' .. barID .. 'Button' .. index
end

---The binding command a button responds to.
---@param barID number
---@param index number
---@return string
function module:GetActionButtonBinding(barID, index)
	local blizzard = BLIZZARD_BINDINGS[barID]
	if blizzard and _G['BINDING_NAME_' .. blizzard:format(index)] then
		return blizzard:format(index)
	end
	return ('CLICK %s:Keybind'):format(self:GetActionButtonName(barID, index))
end

---LibActionButton's shared spell fly-out, so hovering it keeps its bar visible.
---@return Frame|nil
function module:GetFlyoutFrame()
	return LAB.GetSpellFlyoutFrame and LAB:GetSpellFlyoutFrame() or nil
end

-- Leaving a spell fly-out counts as leaving the bar it opened from, so mouseover bars fade
LAB.RegisterCallback(module, 'OnFlyoutButtonCreated', function(_, flyoutButton)
	flyoutButton:HookScript('OnLeave', function()
		for _, bar in pairs(module.bars) do
			if bar.mouseInside and bar.OnLeaveBar then
				bar:OnLeaveBar()
			end
		end
	end)
end)

----------------------------------------------------------------------------------------------------
-- Paging
----------------------------------------------------------------------------------------------------

-- Default per-class page swaps for bar 1. These mirror what the default UI does for each
-- game version so a fresh install behaves the way players expect.
local function BuildClassPaging()
	local modern = SUI.IsRetail
	local wrathPlus = SUI.IsWrath or SUI.IsCata or SUI.IsMOP
	local paging = {
		DRUID = '[bonusbar:1,stealth] 8; [bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10;',
		ROGUE = wrathPlus and '[bonusbar:1] 7; [bonusbar:2] 8;' or '[bonusbar:1] 7;',
	}
	if modern then
		paging.EVOKER = '[bonusbar:1] 7;'
	end
	if not modern and not SUI.IsMOP then
		paging.WARRIOR = '[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9;'
	end
	if SUI.IsClassic or SUI.IsForever then
		paging.PRIEST = '[form:1] 7;'
	elseif not modern then
		paging.PRIEST = '[bonusbar:1] 7;'
	end
	if SUI.IsMOP then
		paging.MONK = '[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9;'
	end
	if wrathPlus then
		paging.WARLOCK = '[form:1] 7;'
	end
	return paging
end
module.DefaultClassPaging = BuildClassPaging()

-- Vehicle, override, possess and skyriding bars all resolve through the same secure
-- lookup, so one condition set works on every game version.
local BASE_PAGING = '[overridebar][possessbar][shapeshift] possess; [bonusbar:5] possess; '
local MANUAL_PAGING = '[bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6; '

---Build a bar's page driver. Order matters, the first matching rule wins: vehicle pages,
---then the player's own rules, then Shift+number paging, then the class defaults.
---@param bar SUI.ActionBars.Bar
---@return string
function module:GetPageDriver(bar)
	local db = bar:GetDB()
	local driver = db.vehiclePaging and BASE_PAGING or ''
	if db.pagingEnabled then
		local custom = db.paging and db.paging[playerClass]
		local hasCustom = type(custom) == 'string' and custom:gsub('%s', '') ~= ''
		if hasCustom then
			driver = driver .. custom:gsub('[\n\r]', ' ')
			if not driver:match(';%s*$') then
				driver = driver .. ';'
			end
			driver = driver .. ' '
		end
		if db.manualPaging then
			driver = driver .. MANUAL_PAGING
		end
		if not hasCustom and db.defaultClassPaging and bar.id == 1 and self.DefaultClassPaging[playerClass] then
			driver = driver .. self.DefaultClassPaging[playerClass] .. ' '
		end
	end
	return driver .. bar.id
end

local PAGE_SNIPPET = [[
	if newstate == 'possess' or newstate == 'dragon' or newstate == '11' then
		if HasVehicleActionBar and HasVehicleActionBar() then
			newstate = GetVehicleBarIndex()
		elseif HasOverrideActionBar and HasOverrideActionBar() then
			newstate = GetOverrideBarIndex()
		elseif HasTempShapeshiftActionBar and HasTempShapeshiftActionBar() then
			newstate = GetTempShapeshiftBarIndex()
		elseif HasBonusActionBar and HasBonusActionBar() and GetBonusBarIndex then
			newstate = GetBonusBarIndex()
		else
			newstate = 12
		end
	end
	self:SetAttribute('state', newstate)
	control:ChildUpdate('state', newstate)
]]

-- Button 12 turns into a leave button on vehicle pages, so a vehicle can always be left
-- even when Blizzard's own vehicle bar is not in use
local EXIT_BUTTON = {
	func = function()
		VehicleExit()
	end,
	texture = 'Interface\\Icons\\Spell_Shadow_SacrificialShield',
	tooltip = LEAVE_VEHICLE,
}

---Pages that hold vehicle, override and possess actions on this client.
---@return number[]
local function GetExitPages()
	local pages = {}
	local seen = {}
	for _, name in ipairs({ 'GetVehicleBarIndex', 'GetOverrideBarIndex', 'GetTempShapeshiftBarIndex' }) do
		local fn = (C_ActionBar and C_ActionBar[name]) or _G[name]
		local page = fn and fn()
		if page and not seen[page] then
			seen[page] = true
			pages[#pages + 1] = page
		end
	end
	-- Older clients page possess and vehicles through bonus bar 5 (pages 11-12)
	if #pages == 0 then
		pages = { 11, 12 }
	end
	return pages
end

----------------------------------------------------------------------------------------------------
-- Action bar prototype
----------------------------------------------------------------------------------------------------

---@class SUI.ActionBars.ActionBar : SUI.ActionBars.Bar
---@field id number
local ActionBar = {}

---Assign each button its action slot on every page, shifted by the bar's button offset.
function ActionBar:UpdateButtonStates()
	local db = self:GetDB()
	local offset = math.max(0, math.min(db.buttonOffset or 0, NUM_BUTTONS - 1))
	local exit = db.vehiclePaging and true or false
	if self.appliedOffset == offset and self.appliedExit == exit then
		return
	end
	self.appliedOffset, self.appliedExit = offset, exit
	local exitPages = exit and GetExitPages() or {}
	for i, button in ipairs(self.buttons) do
		local slot = (i + offset - 1) % NUM_BUTTONS + 1
		for state = 1, NUM_STATES do
			button:SetState(state, 'action', (state - 1) * NUM_BUTTONS + slot)
		end
		-- State 0 is used before the page driver fires for the first time
		button:SetState(0, 'action', (self.id - 1) * NUM_BUTTONS + slot)
		if i == NUM_BUTTONS then
			for _, page in ipairs(exitPages) do
				button:SetState(page, 'custom', EXIT_BUTTON)
			end
		end
	end
	for _, button in ipairs(self.buttons) do
		button:UpdateAction(true)
	end
end

function ActionBar:UpdateButtons()
	local db = self:GetDB()
	local count = math.max(0, math.min(db.buttons or NUM_BUTTONS, NUM_BUTTONS))
	self.manageButtonVisibility = true
	self:UpdateButtonStates()
	self:LayoutButtons(count)

	local enabled = db.enabled and not self.forceHidden
	for i, button in ipairs(self.buttons) do
		if enabled and i <= count then
			button:SetAttribute('statehidden', nil)
			button:Show()
		else
			button:SetAttribute('statehidden', true)
			button:Hide()
		end
		self:RegisterHoverChild(button)
	end

	self:UpdatePaging()
end

function ActionBar:UpdatePaging()
	UnregisterStateDriver(self, 'page')
	local driver = module:GetPageDriver(self)
	self:SetAttribute('state-page', tostring(self.id))
	RegisterStateDriver(self, 'page', driver)
end

---Resolve the fly-out direction, working out AUTOMATIC from where the bar sits on screen.
---@return string
function ActionBar:GetFlyoutDirection()
	local direction = self:GetDB().flyoutDirection or 'UP'
	if direction ~= 'AUTOMATIC' then
		return direction
	end
	local db = self:GetDB()
	local x, y = self:GetCenter()
	if not x or not y then
		return 'UP'
	end
	-- Compare in screen space: the bar is usually scaled differently from UIParent
	local ratio = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
	x, y = x * ratio, y * ratio
	local screenWidth, screenHeight = UIParent:GetSize()
	local vertical = (db.buttonsPerRow or NUM_BUTTONS) == 1 and (db.buttons or NUM_BUTTONS) > 1
	if vertical then
		return x > screenWidth / 2 and 'LEFT' or 'RIGHT'
	end
	return y > screenHeight / 2 and 'DOWN' or 'UP'
end

function ActionBar:PostApply()
	module:UpdateActionBarConfig(self)
end

---Called after the player drops the bar's mover: an automatic fly-out may now face another way.
function ActionBar:OnMoved()
	if self:GetDB().flyoutDirection == 'AUTOMATIC' then
		module:UpdateActionBarConfig(self)
	end
end

---@param id number
---@return SUI.ActionBars.ActionBar
local function CreateActionBar(id)
	local key = 'BT4Bar' .. id
	local bar = module:NewBar(key, module:GetActionBarFrameName(id), L['Bar'] .. ' ' .. id, function()
		return module.CurrentSettings.bars[id]
	end) ---@type SUI.ActionBars.ActionBar
	Mixin(bar, ActionBar)
	bar.id = id
	bar.hideInBlizzardVehicle = true
	bar.cropIcons = true

	bar:SetAttribute('_onstate-page', PAGE_SNIPPET)

	for i = 1, NUM_BUTTONS do
		bar.buttons[i] = LAB:CreateButton(i, module:GetActionButtonName(id, i), bar, nil)
	end
	bar:UpdateButtonStates()

	return bar
end

function module:CreateActionBars()
	for _, id in ipairs(self.ACTION_BAR_IDS) do
		if not self.bars['BT4Bar' .. id] then
			CreateActionBar(id)
		end
	end
end

---@return fun(): number, SUI.ActionBars.ActionBar
function module:IterateActionBars()
	local i = 0
	return function()
		i = i + 1
		local id = self.ACTION_BAR_IDS[i]
		if id then
			return id, self.bars['BT4Bar' .. id]
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Button configuration
----------------------------------------------------------------------------------------------------

---LibActionButton text settings for one element. Buttons are scaled to their size, which
---would shrink or grow the text with them, so sizes and offsets are divided by that scale.
---@param text table
---@param scale number The button's scale
---@param justifyH string
---@return table
local function BuildTextConfig(text, scale, justifyH)
	local color = text.color or { 1, 1, 1 }
	local face = text.face and text.face ~= '' and SUI.Lib.LSM:Fetch('font', text.face, true) or false
	return {
		font = {
			font = face,
			size = (text.size or 12) / scale,
			flags = text.flags or 'OUTLINE',
		},
		color = { color[1] or 1, color[2] or 1, color[3] or 1 },
		position = {
			anchor = text.anchor or 'CENTER',
			relAnchor = text.anchor or 'CENTER',
			offsetX = (text.x or 0) / scale,
			offsetY = (text.y or 0) / scale,
		},
		justifyH = justifyH or 'CENTER',
	}
end

---@param anchor string
---@return string
local function JustifyFor(anchor)
	if anchor and anchor:find('RIGHT') then
		return 'RIGHT'
	elseif anchor and anchor:find('LEFT') then
		return 'LEFT'
	end
	return 'CENTER'
end

---Build and push the LibActionButton config for one action bar.
---@param bar SUI.ActionBars.ActionBar
function module:UpdateActionBarConfig(bar)
	if InCombatLockdown() then
		self:RunOutOfCombat('config:' .. bar.key, self.UpdateActionBarConfig, self, bar)
		return
	end
	local global = self.CurrentSettings
	local db = bar:GetDB()
	local text = global.text
	if db.customText and type(db.text) == 'table' then
		text = SUI:MergeData(SUI:CopyData({}, global.text), db.text, true)
	end

	local flyoutDirection = bar:GetFlyoutDirection()
	for i, button in ipairs(bar.buttons) do
		local scale = button:GetScale()
		if not scale or scale <= 0 then
			scale = 1
		end
		local config = {
			outOfRangeColoring = global.outOfRangeColoring,
			tooltip = global.tooltip,
			showGrid = db.showGrid,
			colors = {
				range = global.colors.range,
				mana = global.colors.mana,
			},
			hideElements = {
				macro = not db.macroText,
				hotkey = not db.hotkeyText,
				equipped = not db.showEquipped,
				-- Cropped icons drop Blizzard's rounded frame, as Bartender4's zoom does
				border = global.hideBorder or db.zoom,
			},
			keyBoundTarget = self:GetActionButtonBinding(bar.id, i),
			keyBoundClickButton = 'Keybind',
			flyoutDirection = flyoutDirection,
			actionButtonUI = true,
			assistedHighlight = global.assistedHighlight,
			spellCastVFX = global.spellCastVFX,
			text = {
				hotkey = BuildTextConfig(text.hotkey, scale, JustifyFor(text.hotkey.anchor)),
				count = BuildTextConfig(text.count, scale, JustifyFor(text.count.anchor)),
				macro = BuildTextConfig(text.macro, scale, JustifyFor(text.macro.anchor)),
			},
		}
		button:UpdateConfig(config)

		-- LibActionButton only keeps config keys that have a default, and cooldownCount has
		-- none, so it is set on the stored config (read again on every cooldown update)
		button.config.cooldownCount = global.showCooldownText and true or false
		if button.cooldown then
			button.cooldown:SetHideCountdownNumbers(not global.showCooldownText)
		end
		if button.Count then
			button.Count:SetAlpha(db.countText and 1 or 0)
		end

		button:SetAttribute('buttonlock', global.lockButtons)
		-- Unlocked buttons still pick up on a mouse press instead of casting on key-down
		button:SetAttribute('unlockedpreventdrag', true)
		button:SetAttribute('checkselfcast', global.checkSelfCast and true or nil)
		button:SetAttribute('checkfocuscast', global.checkFocusCast and true or nil)
		button:SetAttribute('checkmouseovercast', db.mouseoverCast and true or nil)
		button:SetAttribute('*unit2', global.rightClickSelfCast and 'player' or nil)
	end
end

function module:UpdateButtonConfig()
	for _, bar in self:IterateActionBars() do
		if bar then
			self:UpdateActionBarConfig(bar)
		end
	end
end

module.ActionBarPrototype = ActionBar
