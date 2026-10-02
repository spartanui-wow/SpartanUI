---@type SUI
local SUI = SUI
local L = SUI.L

---@class SUI.Module.ActionBars : SUI.Module
local module = SUI:NewModule('ActionBars')
module.DisplayName = L['Action Bars']
module.description = 'SpartanUI action bars, pet, stance, bag and menu bars'
-- The module list's switch picks the bar system: off gives the bars back to Blizzard, on draws
-- SpartanUI's own bars. Both reload the UI.
module.ModuleToggle = {
	get = function()
		return SUI.Handlers.BarSystem:GetChosenSystem() ~= 'WoW'
	end,
	set = function(enabled)
		SUI.Handlers.BarSystem:SetChosenSystem(enabled and 'SpartanUI' or 'WoW')
	end,
}

-- Logical bar keys are shared with the Bartender4 handler so theme positions, theme
-- scales and saved mover positions carry over when switching between the two systems.
-- Bars 13-15 sit on Blizzard's Action Bars 6-8 (pages 13-15), which exist on every client
-- that has the MultiBar5-7 frames, not only Retail.
module.ACTION_BAR_IDS = _G.MultiBar5 and { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13, 14, 15 } or { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }

-- Theme bar scales were tuned against 45px buttons on Retail and 36px everywhere else,
-- so the defaults follow the same split to keep every theme's layout intact.
module.DEFAULT_BUTTON_SIZE = SUI.IsRetail and 45 or 36

module.bars = {} ---@type table<string, SUI.ActionBars.Bar>

-- Default visibility rules differ by game version: pet battles, vehicles and override bars
-- only exist on some clients.
local HAS_PETBATTLE = SUI.IsRetail or SUI.IsMOP or SUI.IsCata
local HAS_VEHICLES = HAS_PETBATTLE or SUI.IsWrath or SUI.IsForever

local function DefaultBarVisibility(id)
	if id == 1 then
		return HAS_PETBATTLE and '[petbattle] hide; show' or 'show'
	end
	if HAS_PETBATTLE then
		return '[vehicleui][petbattle][overridebar] hide; show'
	elseif HAS_VEHICLES then
		return '[vehicleui][overridebar] hide; show'
	end
	return '[overridebar] hide; show'
end

local function DefaultPetVisibility()
	if HAS_PETBATTLE then
		return '[petbattle] hide; [novehicleui,pet,nooverridebar,nopossessbar] show; hide'
	elseif HAS_VEHICLES then
		return '[novehicleui,pet,nooverridebar,nopossessbar] show; hide'
	elseif SUI.IsTBC then
		return '[pet,nooverridebar,nopossessbar] show; hide'
	end
	-- Classic Era shows mind-controlled abilities on the pet bar
	return '[pet,nooverridebar] show; hide'
end

local function DefaultStanceVisibility()
	if HAS_PETBATTLE then
		return '[vehicleui][petbattle] hide; show'
	elseif HAS_VEHICLES then
		return '[vehicleui] hide; show'
	end
	return 'show'
end

-- Micro buttons differ in shape between clients; default to whatever this client ships
local MICRO_WIDTH, MICRO_HEIGHT = 32, 40
if CharacterMicroButton then
	local w, h = CharacterMicroButton:GetSize()
	if w and w > 0 and h and h > 0 then
		MICRO_WIDTH, MICRO_HEIGHT = math.floor(w + 0.5), math.floor(h + 0.5)
	end
end

-- Themes were tuned against SpartanUI's Bartender4 setup: 32px steps with -7 padding, plus
-- Bartender4's extra -8 on modern micro menus. Match that step whatever the button width.
local MICRO_STEP = SUI.IsRetail and 17 or 25
local MICRO_SPACING = MICRO_STEP - MICRO_WIDTH

local UTILITY_VISIBILITY = HAS_PETBATTLE and '[petbattle] hide; show' or 'show'

---@param id number
---@return table
local function ActionBarDefaults(id)
	local isSideBar = (id == 5 or id == 6)
	return {
		enabled = id <= 6,
		buttons = 12,
		buttonsPerRow = isSideBar and 4 or 12,
		buttonSize = module.DEFAULT_BUTTON_SIZE,
		buttonHeight = module.DEFAULT_BUTTON_SIZE,
		keepSizeRatio = true,
		buttonSpacing = isSideBar and 4 or 3,
		backdrop = false,
		backdropSpacing = 4,
		point = 'TOPLEFT',
		alpha = 1,
		mouseover = false,
		mouseoverAlpha = 0,
		inheritGlobalFade = false,
		clickThrough = false,
		frameStrata = '',
		frameLevel = 0,
		fadeOutDelay = 0,
		showGrid = false,
		flyoutDirection = 'UP',
		zoom = true,
		hotkeyText = true,
		macroText = true,
		countText = true,
		showEquipped = true,
		visibility = DefaultBarVisibility(id),
		pagingEnabled = id == 1,
		paging = {},
		-- Bar 1 swaps into vehicle, possess and skyriding pages, and follows Shift+number paging
		vehiclePaging = id == 1,
		manualPaging = id == 1,
		-- Off when the player's own page rules should replace the class defaults entirely
		defaultClassPaging = true,
		buttonOffset = 0,
		mouseoverCast = true,
		customText = false,
		text = { hotkey = {}, count = {}, macro = {} },
	}
end

---@param buttonsPerRow number
---@param extra? table
---@return table
local function SpecialBarDefaults(buttonsPerRow, extra)
	local defaults = {
		enabled = true,
		buttonsPerRow = buttonsPerRow,
		buttonSize = module.DEFAULT_BUTTON_SIZE,
		buttonHeight = module.DEFAULT_BUTTON_SIZE,
		keepSizeRatio = true,
		buttonSpacing = 3,
		backdrop = false,
		backdropSpacing = 4,
		point = 'TOPLEFT',
		alpha = 1,
		mouseover = false,
		mouseoverAlpha = 0,
		inheritGlobalFade = false,
		clickThrough = false,
		frameStrata = '',
		frameLevel = 0,
		fadeOutDelay = 0,
		zoom = true,
		hotkeyText = true,
		visibility = UTILITY_VISIBILITY,
	}
	if extra then
		for k, v in pairs(extra) do
			defaults[k] = v
		end
	end
	return defaults
end

---@class SUI.ActionBars.DB
local DBDefaults = {
	lockButtons = true,
	rightClickSelfCast = false,
	outOfRangeColoring = 'button',
	tooltip = 'enabled',
	showCooldownText = true,
	hideBorder = false,
	themeButtonArt = true,
	spellCastVFX = true,
	assistedHighlight = true,
	checkSelfCast = true,
	checkFocusCast = true,
	procGlow = true,
	colors = {
		range = { 0.8, 0.1, 0.1 },
		mana = { 0.5, 0.5, 1.0 },
		usable = { 1, 1, 1 },
		notUsable = { 0.4, 0.4, 0.4 },
	},
	text = {
		hotkey = { face = '', size = 12, flags = 'OUTLINE', color = { 0.75, 0.75, 0.75 }, anchor = 'TOPRIGHT', x = -2, y = -4 },
		count = { face = '', size = 14, flags = 'OUTLINE', color = { 1, 1, 1 }, anchor = 'BOTTOMRIGHT', x = -2, y = 4 },
		macro = { face = '', size = 10, flags = 'OUTLINE', color = { 1, 1, 1 }, anchor = 'BOTTOM', x = 0, y = 2 },
	},
	globalFade = {
		enabled = false,
		alpha = 0.3,
		showInCombat = true,
		showWithTarget = true,
		showWhileCasting = true,
		showWhenHurt = true,
		showInVehicle = true,
	},
	masque = true,
	backdropColors = {
		background = { 0, 0, 0, 0.5 },
		border = { 0, 0, 0, 1 },
	},
	bars = {},
	pet = SpecialBarDefaults(10, {
		visibility = DefaultPetVisibility(),
		buttonSize = 30,
		buttonSpacing = 3,
		hotkeyText = false,
	}),
	stance = SpecialBarDefaults(10, {
		visibility = DefaultStanceVisibility(),
		buttonSize = 30,
		buttonSpacing = 1,
		hotkeyText = false,
	}),
	micro = SpecialBarDefaults(13, {
		buttonSize = MICRO_WIDTH,
		buttonHeight = MICRO_HEIGHT,
		keepSizeRatio = false,
		buttonSpacing = MICRO_SPACING,
		backdropSpacing = 0,
		visibility = UTILITY_VISIBILITY,
		zoom = false,
	}),
	bags = SpecialBarDefaults(7, {
		buttonSize = SUI.IsRetail and 30 or 37,
		buttonSpacing = 0,
		backdropSpacing = 0,
		visibility = UTILITY_VISIBILITY,
		zoom = false,
		onlyBackpack = false,
		showReagentBag = true,
		showKeyring = true,
		reverse = false,
	}),
	totem = SpecialBarDefaults(1, {
		visibility = '[vehicleui] hide; show',
	}),
	queue = SpecialBarDefaults(1, {
		buttonSize = 45,
		visibility = 'show',
	}),
	-- Off by default: Blizzard (Edit Mode on modern clients) keeps placing these buttons
	extra = SpecialBarDefaults(1, {
		enabled = false,
		visibility = 'show',
		hideArtwork = false,
	}),
}

for _, id in ipairs(module.ACTION_BAR_IDS) do
	DBDefaults.bars[id] = ActionBarDefaults(id)
end

module.ActionBarDefaults = ActionBarDefaults

----------------------------------------------------------------------------------------------------
-- Combat queue
----------------------------------------------------------------------------------------------------

local combatQueue = {}
local combatWatcher = CreateFrame('Frame')
combatWatcher:SetScript('OnEvent', function(self)
	self:UnregisterEvent('PLAYER_REGEN_ENABLED')
	local pending = combatQueue
	combatQueue = {}
	for _, entry in ipairs(pending) do
		local ok, err = pcall(entry.func, unpack(entry.args))
		if not ok and module.logger then
			module.logger.error('Deferred action bar update failed: ' .. tostring(err))
		end
	end
end)

---Run a function now, or once combat ends if the UI is locked down.
---Secure frames (bars, buttons, state drivers) cannot be changed in combat.
---@param key string Deduplication key; a later request with the same key replaces the earlier one
---@param func function
---@param ... any
function module:RunOutOfCombat(key, func, ...)
	if not InCombatLockdown() then
		func(...)
		return
	end
	for i = #combatQueue, 1, -1 do
		if combatQueue[i].key == key then
			table.remove(combatQueue, i)
		end
	end
	table.insert(combatQueue, { key = key, func = func, args = { ... } })
	combatWatcher:RegisterEvent('PLAYER_REGEN_ENABLED')
end

----------------------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------------------

---True when SpartanUI is the active bar system for this session.
---@return boolean
function module:IsActive()
	return self.active == true
end

function module:OnInitialize()
	if SUI.logger then
		module.logger = SUI.logger:RegisterCategory('ActionBars')
	end

	SUI.DBM:SetupModule(self, DBDefaults, nil, { autoCalculateDepth = true })
	SUI.DBM:RegisterSequentialProfileRefresh(self)
end

---Called by the bar system handler when SpartanUI is the chosen bar system.
function module:Activate()
	if self.active then
		return
	end
	if InCombatLockdown() then
		self:RunOutOfCombat('activate', self.Activate, self)
		return
	end
	self.active = true
	self.ownershipAtLogin = self:GetBlizzardOwnership()

	self:HideBlizzard()
	self:SetupGlobalFade()
	self:CreateActionBars()
	self:CreatePetBar()
	self:CreateStanceBar()
	self:CreateMicroMenu()
	self:CreateBagBar()
	self:CreateQueueStatus()
	self:CreateTotemBar()
	self:CreateExtraBar()
	self:SetupKeybinds()
	self:SetupMasque()
	self:ApplyAll()
	self:BuildOptions()

	self:RegisterEvent('PLAYER_ENTERING_WORLD', function()
		self:RunOutOfCombat('reapply', self.ApplyAll, self)
	end)
end

---Re-apply every setting to every bar.
function module:ApplyAll()
	if not self.active then
		return
	end
	if InCombatLockdown() then
		self:RunOutOfCombat('applyall', self.ApplyAll, self)
		return
	end
	for _, bar in pairs(self.bars) do
		bar:Apply()
	end
	self:ApplyThemeLayout()
	self:UpdateGlobalFade()
	self:UpdateKeybinds()
	self:SyncButtonLock()
end

---Pet and stance buttons are Blizzard's and follow the game's own lock setting, so keep that
---setting and SpartanUI's in step: SpartanUI's wins when bars are applied, and a change made
---in the game's options is copied back.
function module:SyncButtonLock()
	local wanted = self.CurrentSettings.lockButtons and '1' or '0'
	if GetCVar('lockActionBars') ~= wanted then
		SetCVar('lockActionBars', wanted)
	end
	if self.lockWatcher then
		return
	end
	local watcher = CreateFrame('Frame')
	watcher:RegisterEvent('CVAR_UPDATE')
	watcher:SetScript('OnEvent', function(_, _, name)
		if not module.active or (name ~= 'lockActionBars' and name ~= 'LOCK_ACTIONBAR_TEXT') then
			return
		end
		local locked = GetCVarBool('lockActionBars') and true or false
		if locked ~= (module.CurrentSettings.lockButtons and true or false) then
			module:SetSetting({}, 'lockButtons', locked)
			module:RunOutOfCombat('buttonconfig', module.UpdateButtonConfig, module)
		end
	end)
	self.lockWatcher = watcher
end

---Which Blizzard button groups SpartanUI takes over. Changing any of these moves Blizzard's
---own frames around, which only happens cleanly at login.
---@return string
function module:GetBlizzardOwnership()
	local current = self.CurrentSettings
	return ('%s:%s:%s'):format(tostring(current.micro.enabled), tostring(current.bags.enabled), tostring(current.extra.enabled))
end

---Ask for a reload when a profile change or reset hands Blizzard frames over differently.
function module:CheckOwnershipChange()
	if self.active and self.ownershipAtLogin and self.ownershipAtLogin ~= self:GetBlizzardOwnership() then
		SUI:reloadui()
	end
end

function module:ReloadDB()
	self:ApplyAll()
	self:CheckOwnershipChange()
end

---@param key string Logical bar key (BT4Bar1, BT4BarPetBar ...)
---@return SUI.ActionBars.Bar|nil
function module:GetBar(key)
	return self.bars[key]
end

SUI.ActionBars = module
