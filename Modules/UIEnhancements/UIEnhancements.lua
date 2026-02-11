local SUI, L = SUI, SUI.L
---@class SUI.Module.UIEnhancements : SUI.Module
local module = SUI:NewModule('UIEnhancements')
module.DisplayName = L['UI Enhancements']
module.description = 'Add and improve UI functionality'
----------------------------------------------------------------------------------------------------

---@class SUI.Module.UIEnhancements.DB
local DBDefaults = {
	-- DecorMerchant
	decorMerchantBulkBuy = true,
	-- LootAlertPopup
	lootAlertPopup = true,
	lootAlertChat = true,
	lootAlertSound = false,
	lootAlertSoundName = 'None',
	-- Mouse Ring Settings
	mouseRing = {
		enabled = false,
		circleStyle = 1, -- 1=circle.tga, 2=ChallengeMode-KeystoneSlotFrameGlow, 3=GarrLanding-CircleGlow, 4=ShipMission-RedGlowRing
		size = 32,
		alpha = 0.8,
		color = { mode = 'class', r = 1, g = 1, b = 1 },
		showCenterDot = false,
		centerDotSize = 4,
		combatOnly = false,
		-- GCD Mode
		gcdEnabled = false,
		gcdAlpha = 0.8,
		gcdReverse = false, -- false = swipe empties, true = swipe fills
	},
	-- Mouse Trail Settings
	mouseTrail = {
		enabled = false,
		density = 'medium',
		size = 8,
		alpha = 0.6,
		color = { mode = 'class', r = 1, g = 1, b = 1 },
		combatOnly = false,
	},
}

local DB

function module:OnInitialize()
	module.Database = SUI.SpartanUIDB:RegisterNamespace('UIEnhancements', { profile = DBDefaults })
	DB = module.Database.profile
	module.DB = DB

	-- Register profile change callbacks
	module.Database.RegisterCallback(module, 'OnProfileChanged', function()
		DB = module.Database.profile
		module.DB = DB
	end)
	module.Database.RegisterCallback(module, 'OnProfileCopied', function()
		DB = module.Database.profile
		module.DB = DB
	end)
	module.Database.RegisterCallback(module, 'OnProfileReset', function()
		DB = module.Database.profile
		module.DB = DB
	end)
end

function module:GetDB()
	return DB
end

function module:OnEnable()
	if SUI:IsModuleDisabled(module) then
		return
	end

	-- Initialize sub-modules
	module:InitializeDecorMerchant()
	module:InitializeLootAlertPopup()
	module:InitializeMouseEffects()

	-- Build options
	module:BuildOptions()
end

function module:OnDisable()
	-- Restore default behavior for all enhancement elements
	module:RestoreDecorMerchant()
	module:RestoreLootAlertPopup()
	module:RestoreMouseEffects()
end
