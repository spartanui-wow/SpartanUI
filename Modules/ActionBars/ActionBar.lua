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

----------------------------------------------------------------------------------------------------
-- Paging
----------------------------------------------------------------------------------------------------

-- Default per-class page swaps for bar 1. These mirror what the default UI does for each
-- game version so a fresh install behaves the way players expect.
local function BuildClassPaging()
	local modern = SUI.IsRetail
	local wrathPlus = SUI.IsWrath or SUI.IsCata or SUI.IsMOP
	local paging = {
		DRUID = '[bonusbar:1,stealth] 8; [bonusbar:1] 7; [bonusbar:2] 10; [bonusbar:3] 9; [bonusbar:4] 10;',
		ROGUE = wrathPlus and '[bonusbar:1] 7; [bonusbar:2] 8;' or '[bonusbar:1] 7;',
	}
	if modern then
		paging.EVOKER = '[bonusbar:1] 7;'
	end
	if not modern and not SUI.IsMOP then
		paging.WARRIOR = '[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9;'
	end
	if not modern and not SUI.IsClassic and not SUI.IsForever then
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

---@param bar SUI.ActionBars.Bar
---@return string
function module:GetPageDriver(bar)
	local db = bar:GetDB()
	local driver = ''
	if bar.id == 1 then
		driver = BASE_PAGING
		if db.pagingEnabled then
			driver = driver .. MANUAL_PAGING
		end
	end
	if db.pagingEnabled then
		local custom = db.paging and db.paging[playerClass]
		if type(custom) == 'string' and custom:gsub('%s', '') ~= '' then
			driver = driver .. custom:gsub('[\n\r]', ' ')
			if not driver:match(';%s*$') then
				driver = driver .. ';'
			end
			driver = driver .. ' '
		elseif bar.id == 1 and self.DefaultClassPaging[playerClass] then
			driver = driver .. self.DefaultClassPaging[playerClass] .. ' '
		end
	end
	return driver .. bar.id
end

local PAGE_SNIPPET = [[
	if newstate == 'possess' or newstate == '11' then
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

----------------------------------------------------------------------------------------------------
-- Action bar prototype
----------------------------------------------------------------------------------------------------

---@class SUI.ActionBars.ActionBar : SUI.ActionBars.Bar
---@field id number
local ActionBar = {}

function ActionBar:UpdateButtons()
	local db = self:GetDB()
	local count = math.max(0, math.min(db.buttons or NUM_BUTTONS, NUM_BUTTONS))
	self.manageButtonVisibility = true
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
	local screenWidth, screenHeight = UIParent:GetSize()
	if not x or not y then
		return 'UP'
	end
	local vertical = (db.buttonsPerRow or NUM_BUTTONS) == 1 and (db.buttons or NUM_BUTTONS) > 1
	if vertical then
		return x > screenWidth / 2 and 'LEFT' or 'RIGHT'
	end
	return y > screenHeight / 2 and 'DOWN' or 'UP'
end

function ActionBar:PostApply()
	module:UpdateActionBarConfig(self)
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
		local button = LAB:CreateButton(i, module:GetActionButtonName(id, i), bar, nil)
		for state = 1, NUM_STATES do
			button:SetState(state, 'action', (state - 1) * NUM_BUTTONS + i)
		end
		-- State 0 is used before the page driver fires for the first time
		button:SetState(0, 'action', (id - 1) * NUM_BUTTONS + i)
		bar.buttons[i] = button
	end

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

---@param text table
---@param visible boolean
---@return table
local function BuildTextConfig(text, visible, justifyH)
	local color = text.color or { 1, 1, 1 }
	local face = text.face and text.face ~= '' and SUI.Lib.LSM:Fetch('font', text.face, true) or false
	return {
		font = {
			font = face,
			size = text.size or 12,
			flags = text.flags or 'OUTLINE',
		},
		color = { color[1] or 1, color[2] or 1, color[3] or 1, visible and 1 or 0 },
		position = {
			anchor = text.anchor or 'CENTER',
			relAnchor = text.anchor or 'CENTER',
			offsetX = text.x or 0,
			offsetY = text.y or 0,
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

	local flyoutDirection = bar:GetFlyoutDirection()
	for i, button in ipairs(bar.buttons) do
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
			},
			keyBoundTarget = self:GetActionButtonBinding(bar.id, i),
			keyBoundClickButton = 'Keybind',
			flyoutDirection = flyoutDirection,
			actionButtonUI = true,
			assistedHighlight = true,
			spellCastVFX = true,
			text = {
				hotkey = BuildTextConfig(text.hotkey, true, JustifyFor(text.hotkey.anchor)),
				count = BuildTextConfig(text.count, db.countText, JustifyFor(text.count.anchor)),
				macro = BuildTextConfig(text.macro, true, JustifyFor(text.macro.anchor)),
			},
		}
		if not global.showCooldownText then
			config.cooldownCount = false
		end
		button:UpdateConfig(config)

		button:SetAttribute('buttonlock', global.lockButtons)
		button:SetAttribute('checkselfcast', true)
		button:SetAttribute('checkfocuscast', true)
		button:SetAttribute('checkmouseovercast', true)
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
