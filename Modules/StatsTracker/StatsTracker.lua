local SUI = SUI
local StatsTracker = SUI:NewModule('StatsTracker', 'AceEvent-3.0', 'AceTimer-3.0') ---@class StatsTracker : SUI.Module
StatsTracker.description = 'Comprehensive statistics tracking and display system'
----------------------------------------------------------------------------------------------------

---@class StatsTracker.Stat
---@field value number|string
---@field lastValue number|string
---@field displayValue string
---@field color table RGB color values
---@field progress number Progress percentage (0-1)
---@field maxValue number Maximum value for progress calculation
---@field type string Type of statistic

---@class StatsTracker.SessionData
---@field startTime number
---@field playTime number
---@field xpGained number
---@field goldGained number
---@field kills number
---@field deaths number
---@field bagsFull number
---@field xpHistory table

local MoveIt
local updateTimer
local displayFrames = {}
local sessionData = {}
local currentStats = {}
local xpHistory = {} -- For calculating XP/hour trends

-- Constants
local UPDATE_INTERVAL = 1.0 -- Update every second
local XP_HISTORY_SIZE = 600 -- Keep 10 minutes of XP data (600 seconds)
local DETECTED_CURRENCIES = {}
-- Make detected currencies globally accessible for Display.lua
_G.DETECTED_CURRENCIES = DETECTED_CURRENCIES

-- Default thresholds and colors
local STAT_CONFIG = {
	fps = {
		thresholds = { excellent = 70, good = 40, poor = 25 },
		colors = { excellent = { 0, 1, 0 }, good = { 1, 1, 0 }, poor = { 1, 0, 0 } },
		maxValue = 144,
		unit = ' fps',
		progress = true,
		label = 'FPS',
		icon = 'atlas:ui-hud-minimap-zoom-in',
	},
	latency = {
		thresholds = { excellent = 50, good = 100, poor = 200 },
		colors = { excellent = { 0, 1, 0 }, good = { 1, 1, 0 }, poor = { 1, 0, 0 } },
		maxValue = 300,
		unit = 'ms',
		progress = true,
		invert = true, -- Lower is better
		label = 'Latency',
		icon = 'Interface\\Icons\\Spell_Shadow_Web',
	},
	memory = {
		thresholds = { excellent = 100, good = 200, poor = 400 },
		colors = { excellent = { 0, 1, 0 }, good = { 1, 1, 0 }, poor = { 1, 0, 0 } },
		maxValue = 500,
		unit = 'MB',
		progress = true,
		label = 'Memory',
		icon = 'Interface\\Icons\\Trade_Engineering',
	},
	bags = {
		thresholds = { excellent = 60, good = 80, poor = 95 }, -- Percentage full
		colors = { excellent = { 0, 1, 0 }, good = { 1, 1, 0 }, poor = { 1, 0, 0 } },
		maxValue = 100,
		unit = '%',
		progress = true,
		label = 'Bags',
		icon = 'Interface\\Icons\\INV_Misc_Bag_08',
	},
	durability = {
		thresholds = { excellent = 80, good = 50, poor = 25 },
		colors = { excellent = { 0, 1, 0 }, good = { 1, 1, 0 }, poor = { 1, 0, 0 } },
		maxValue = 100,
		unit = '%',
		progress = true,
		invert = true,
		label = 'Durability',
		icon = 'Interface\\Icons\\Trade_BlackSmithing',
	},
	gold = {
		label = 'Gold',
		icon = 'Interface\\Icons\\INV_Misc_Coin_01',
	},
	sessionTime = {
		label = 'Session',
		icon = 'Interface\\Icons\\Spell_Holy_BorrowedTime',
	},
	totalTime = {
		label = 'Total Time',
		icon = 'Interface\\Icons\\Spell_Holy_BorrowedTime',
	},
	xp = {
		label = 'XP',
		icon = 'Interface\\Icons\\Spell_ChargePositive',
	},
	xpPerHour = {
		label = 'XP/Hr',
		icon = 'Interface\\Icons\\Spell_ChargePositive',
	},
	recentXpRate = {
		label = 'Recent XP/Hr',
		icon = 'Interface\\Icons\\Spell_ChargePositive',
	},
	restedXP = {
		label = 'Rested',
		icon = 'Interface\\Icons\\Spell_Nature_Regeneration',
	},
	kills = {
		label = 'Kills',
		icon = 'Interface\\Icons\\Ability_Warrior_Decisivestrike',
	},
	deaths = {
		label = 'Deaths',
		icon = 'Interface\\Icons\\Ability_Rogue_FeignDeath',
	},
	kdr = {
		label = 'K/D Ratio',
		icon = 'Interface\\Icons\\Achievement_PVP_A_A',
	},
}

---Format time duration
---@param seconds number
---@return string
local function FormatTime(seconds)
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs = math.floor(seconds % 60)

	if hours > 0 then
		return string.format('%d:%02d:%02d', hours, minutes, secs)
	else
		return string.format('%d:%02d', minutes, secs)
	end
end

---Format number with abbreviations
---@param value number
---@param decimals? number
---@return string
local function FormatNumber(value, decimals)
	if not value or value == 0 then
		return '0'
	end

	decimals = decimals or 1
	local abs_value = math.abs(value)

	if abs_value >= 1000000000 then
		return string.format('%.' .. decimals .. 'fB', value / 1000000000)
	elseif abs_value >= 1000000 then
		return string.format('%.' .. decimals .. 'fM', value / 1000000)
	elseif abs_value >= 1000 then
		return string.format('%.' .. decimals .. 'fK', value / 1000)
	else
		return string.format('%.0f', value)
	end
end

---Calculate stat color based on thresholds
---@param statType string
---@param value number
---@return table RGB color
local function GetStatColor(statType, value)
	local config = STAT_CONFIG[statType]
	if not config or not StatsTracker.DB.adaptiveColors then
		return StatsTracker.DB.textColor or { 1, 1, 1 }
	end

	local thresholds = config.thresholds
	local colors = config.colors
	local invert = config.invert

	if invert then
		-- Lower values are better (latency, durability warnings)
		if value <= thresholds.excellent then
			return colors.excellent
		elseif value <= thresholds.good then
			return colors.good
		else
			return colors.poor
		end
	else
		-- Higher values are better (fps, etc)
		if value >= thresholds.excellent then
			return colors.excellent
		elseif value >= thresholds.good then
			return colors.good
		else
			return colors.poor
		end
	end
end

---Calculate progress percentage for progress bars
---@param statType string
---@param value number
---@return number Progress (0-1)
local function GetStatProgress(statType, value)
	local config = STAT_CONFIG[statType]
	if not config or not config.progress then
		return 0
	end

	-- Auto-adjust max value if exceeded
	if value > config.maxValue then
		config.maxValue = value * 1.2 -- Add 20% buffer
	end

	return math.min(value / config.maxValue, 1)
end

---Create icon texture string
---@param iconPath string
---@param size? number
---@return string iconString
local function CreateIconString(iconPath, size)
	size = size or 16

	-- Handle different icon types
	if iconPath:find('atlas:') then
		-- Atlas icon format: atlas:AtlasName
		local atlasName = iconPath:gsub('atlas:', '')
		return string.format('|A:%s:%d:%d:0:0|a', atlasName, size, size)
	elseif iconPath:find('Interface\\') or iconPath:find('INTERFACE\\') then
		-- Traditional texture path
		return string.format('|T%s:%d:%d:0:0|t', iconPath, size, size)
	else
		-- Assume it's an atlas name without prefix
		return string.format('|A:%s:%d:%d:0:0|a', iconPath, size, size)
	end
end

---Format stat display value with optional label and icon
---@param statType string
---@param displayValue string
---@return string Formatted display value
local function FormatStatDisplay(statType, displayValue)
	local config = STAT_CONFIG[statType]
	if not config then
		return displayValue
	end

	local result = ''

	-- Add icon if enabled
	if StatsTracker.DB.showIcons and config.icon then
		result = result .. CreateIconString(config.icon) .. ' '
	end

	-- Add label if enabled
	if StatsTracker.DB.showLabels and config.label then
		result = result .. config.label .. ': '
	end

	-- Add the actual value
	result = result .. displayValue

	return result
end

---Format a statistic display value with per-frame icons and labels
---@param statType string
---@param displayValue string
---@param frameConfig table Frame configuration for per-frame settings
---@return string Formatted display value
function StatsTracker:FormatStatDisplayForFrame(statType, displayValue, frameConfig)
	local config = STAT_CONFIG[statType]
	if not config then
		return displayValue
	end

	local result = ''

	-- Determine if icons/labels should be shown (per-frame or global)
	local showIcons = frameConfig.showIcons ~= nil and frameConfig.showIcons or self.DB.showIcons
	local showLabels = frameConfig.showLabels ~= nil and frameConfig.showLabels or self.DB.showLabels

	-- Add icon if enabled
	if showIcons and config.icon then
		result = result .. CreateIconString(config.icon) .. ' '
	end

	-- Add label if enabled
	if showLabels and config.label then
		result = result .. config.label .. ': '
	end

	result = result .. displayValue
	return result
end

---Performance Stats Collection
local function CollectPerformanceStats()
	-- FPS
	local fps = GetFramerate()
	local fpsDisplay = string.format('%.0f fps', fps)
	currentStats.fps = {
		value = fps,
		displayValue = FormatStatDisplay('fps', fpsDisplay),
		rawDisplayValue = fpsDisplay,
		color = GetStatColor('fps', fps),
		progress = GetStatProgress('fps', fps),
		type = 'performance',
	}

	-- Latency
	local latencyHome, latencyWorld = select(3, GetNetStats())
	local latency = math.max(latencyHome, latencyWorld)
	local latencyDisplay = string.format('%d ms', latency)
	currentStats.latency = {
		value = latency,
		displayValue = FormatStatDisplay('latency', latencyDisplay),
		color = GetStatColor('latency', latency),
		progress = GetStatProgress('latency', latency),
		type = 'performance',
	}

	-- Memory usage
	local memoryUsage = 0
	local numAddons = C_AddOns.GetNumAddOns()
	for i = 1, numAddons do
		memoryUsage = memoryUsage + (GetAddOnMemoryUsage(i) or 0)
	end
	memoryUsage = memoryUsage / 1024 -- Convert to MB

	local memoryDisplay = string.format('%.1f MB', memoryUsage)
	currentStats.memory = {
		value = memoryUsage,
		displayValue = FormatStatDisplay('memory', memoryDisplay),
		color = GetStatColor('memory', memoryUsage),
		progress = GetStatProgress('memory', memoryUsage),
		type = 'performance',
	}
end

---Character Stats Collection
local function CollectCharacterStats()
	-- Bag usage (compatible with different WoW versions)
	local totalSlots = 0
	local usedSlots = 0
	for bag = 0, 4 do
		local slots = C_Container.GetContainerNumSlots(bag) or 0
		totalSlots = totalSlots + slots
		for slot = 1, slots do
			local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
			if itemInfo then
				usedSlots = usedSlots + 1
			end
		end
	end

	local bagPercent = totalSlots > 0 and (usedSlots / totalSlots * 100) or 0
	local bagsDisplay = string.format('%d/%d (%d%%)', usedSlots, totalSlots, bagPercent)
	currentStats.bags = {
		value = bagPercent,
		displayValue = FormatStatDisplay('bags', bagsDisplay),
		rawDisplayValue = bagsDisplay,
		color = GetStatColor('bags', bagPercent),
		progress = GetStatProgress('bags', bagPercent),
		type = 'character',
	}

	-- Durability
	local totalDurability = 0
	local currentDurability = 0
	local itemCount = 0

	for slot = 1, 18 do -- All equipment slots
		local current, maximum = GetInventoryItemDurability(slot)
		if current and maximum then
			totalDurability = totalDurability + maximum
			currentDurability = currentDurability + current
			itemCount = itemCount + 1
		end
	end

	local durabilityPercent = 100
	if totalDurability > 0 then
		durabilityPercent = (currentDurability / totalDurability) * 100
	end

	local durabilityDisplay = string.format('%.0f%%', durabilityPercent)
	currentStats.durability = {
		value = durabilityPercent,
		displayValue = FormatStatDisplay('durability', durabilityDisplay),
		color = GetStatColor('durability', durabilityPercent),
		progress = GetStatProgress('durability', durabilityPercent),
		type = 'character',
	}

	-- Gold
	local currentGold = GetMoney()
	local goldDiff = currentGold - (sessionData.startGold or currentGold)

	local goldDisplay = GetMoneyString(currentGold)
	currentStats.gold = {
		value = currentGold,
		displayValue = FormatStatDisplay('gold', goldDisplay),
		sessionGain = goldDiff,
		sessionGainDisplay = GetMoneyString(math.abs(goldDiff), goldDiff < 0),
		color = StatsTracker.DB.textColor or { 1, 1, 1 },
		type = 'character',
	}
end

---Gameplay Stats Collection
local function CollectGameplayStats()
	-- Session playtime
	local sessionTime = GetTime() - sessionData.startTime
	local sessionTimeDisplay = FormatTime(sessionTime)
	currentStats.sessionTime = {
		value = sessionTime,
		displayValue = FormatStatDisplay('sessionTime', sessionTimeDisplay),
		color = StatsTracker.DB.textColor or { 1, 1, 1 },
		type = 'session',
	}

	-- Total playtime
	local totalTime = time() - (sessionData.characterCreated or time())
	local totalTimeDisplay = FormatTime(totalTime)
	currentStats.totalTime = {
		value = totalTime,
		displayValue = FormatStatDisplay('totalTime', totalTimeDisplay),
		color = StatsTracker.DB.textColor or { 1, 1, 1 },
		type = 'session',
	}

	-- XP tracking (only for characters that can gain XP)
	local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 80
	if UnitLevel('player') < maxLevel then
		local currentXP = UnitXP('player')
		local maxXP = UnitXPMax('player')
		local restedXP = GetXPExhaustion() or 0

		-- Calculate XP gained this session
		local xpGained = currentXP - (sessionData.startXP or currentXP)

		-- XP per hour calculation
		local xpPerHour = 0
		if sessionTime > 0 then
			xpPerHour = (xpGained / sessionTime) * 3600
		end

		-- Track XP history for trend calculation
		table.insert(xpHistory, { time = GetTime(), xp = currentXP })
		if #xpHistory > XP_HISTORY_SIZE then
			table.remove(xpHistory, 1)
		end

		-- Calculate recent XP rate (last 10 minutes)
		local recentXpRate = 0
		if #xpHistory >= 2 then
			local oldestEntry = xpHistory[1]
			local timeDiff = GetTime() - oldestEntry.time
			local xpDiff = currentXP - oldestEntry.xp
			if timeDiff > 0 then
				recentXpRate = (xpDiff / timeDiff) * 3600
			end
		end

		local xpDisplay = string.format('%s / %s', FormatNumber(currentXP), FormatNumber(maxXP))
		currentStats.xp = {
			value = currentXP,
			displayValue = FormatStatDisplay('xp', xpDisplay),
			progress = currentXP / maxXP,
			color = StatsTracker.DB.textColor or { 1, 1, 1 },
			type = 'gameplay',
		}

		local xpPerHourDisplay = FormatNumber(xpPerHour) .. ' XP/hr'
		currentStats.xpPerHour = {
			value = xpPerHour,
			displayValue = FormatStatDisplay('xpPerHour', xpPerHourDisplay),
			color = StatsTracker.DB.textColor or { 1, 1, 1 },
			type = 'gameplay',
		}

		local recentXpRateDisplay = FormatNumber(recentXpRate) .. ' XP/hr (recent)'
		currentStats.recentXpRate = {
			value = recentXpRate,
			displayValue = FormatStatDisplay('recentXpRate', recentXpRateDisplay),
			color = StatsTracker.DB.textColor or { 1, 1, 1 },
			type = 'gameplay',
		}

		local restedXPDisplay = FormatNumber(restedXP) .. ' rested'
		currentStats.restedXP = {
			value = restedXP,
			displayValue = FormatStatDisplay('restedXP', restedXPDisplay),
			color = restedXP > 0 and { 0, 0.8, 1 } or StatsTracker.DB.textColor or { 1, 1, 1 },
			type = 'gameplay',
		}
	end

	-- Kill/Death tracking
	local killsDisplay = string.format('%d', sessionData.kills)
	currentStats.kills = {
		value = sessionData.kills,
		displayValue = FormatStatDisplay('kills', killsDisplay),
		color = StatsTracker.DB.textColor or { 1, 1, 1 },
		type = 'combat',
	}

	local deathsDisplay = string.format('%d', sessionData.deaths)
	currentStats.deaths = {
		value = sessionData.deaths,
		displayValue = FormatStatDisplay('deaths', deathsDisplay),
		color = sessionData.deaths > 0 and { 1, 0.5, 0.5 } or StatsTracker.DB.textColor or { 1, 1, 1 },
		type = 'combat',
	}

	local kdr = sessionData.deaths > 0 and (sessionData.kills / sessionData.deaths) or sessionData.kills
	local kdrDisplay = string.format('%.1f', kdr)
	currentStats.kdr = {
		value = kdr,
		displayValue = FormatStatDisplay('kdr', kdrDisplay),
		color = kdr >= 2 and { 0, 1, 0 } or kdr >= 1 and { 1, 1, 0 } or { 1, 0.5, 0.5 },
		type = 'combat',
	}
end

---Calculate a smart default goal based on current currency amount
---@param currentAmount number
---@return number
function StatsTracker:CalculateSmartGoal(currentAmount)
	if currentAmount <= 0 then
		return 100 -- Default goal if no currency
	elseif currentAmount < 10 then
		return math.max(50, currentAmount * 10) -- Small amounts: 10x multiplier, minimum 50
	elseif currentAmount < 100 then
		return math.ceil(currentAmount * 2.5) -- Medium amounts: 2.5x multiplier
	elseif currentAmount < 1000 then
		return math.ceil(currentAmount * 1.5) -- Larger amounts: 1.5x multiplier
	elseif currentAmount < 5000 then
		return math.ceil(currentAmount * 1.2) -- High amounts: 1.2x multiplier
	else
		return math.ceil(currentAmount * 1.1) -- Very high amounts: 1.1x multiplier
	end
end

---Discover and populate DETECTED_CURRENCIES for options UI
function StatsTracker:DiscoverCurrencies()
	-- Only proceed if player is logged in and APIs are available
	if not UnitName('player') or not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyListSize then
		return
	end

	-- Only reset if empty to preserve existing data
	if not DETECTED_CURRENCIES or not next(DETECTED_CURRENCIES) then
		DETECTED_CURRENCIES = {}
	end

	-- Scan the currency list using proper API structure
	local listSize = C_CurrencyInfo.GetCurrencyListSize()
	if listSize and listSize > 0 then
		for i = 1, listSize do
			local currencyInfo = C_CurrencyInfo.GetCurrencyListInfo(i)
			if currencyInfo and not currencyInfo.isHeader and currencyInfo.name and currencyInfo.currencyID then
				local currencyID = currencyInfo.currencyID
				local name = currencyInfo.name
				local quantity = currencyInfo.quantity or 0
				local iconFileID = currencyInfo.iconFileID
				local statKey = 'currency_' .. currencyID

				-- Store for options menu (show all discovered currencies)
				if not DETECTED_CURRENCIES[statKey] then
					DETECTED_CURRENCIES[statKey] = {
						name = name,
						icon = iconFileID,
						id = currencyID,
						quantity = quantity,
					}
				end
			end
		end
	end

	-- Update global reference
	_G.DETECTED_CURRENCIES = DETECTED_CURRENCIES
end

---Collect currency information using proper retail API structure
local function CollectCurrencyStats()
	-- Clear previous currency stats
	for statKey in pairs(currentStats) do
		if statKey:find('^currency_') then
			currentStats[statKey] = nil
		end
	end

	-- Discover currencies (populates DETECTED_CURRENCIES)
	StatsTracker:DiscoverCurrencies()

	-- Scan the currency list using proper API structure
	if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize then
		local listSize = C_CurrencyInfo.GetCurrencyListSize()
		for i = 1, listSize do
			local currencyInfo = C_CurrencyInfo.GetCurrencyListInfo(i)
			if currencyInfo and not currencyInfo.isHeader and currencyInfo.name then
				local currencyID = currencyInfo.currencyID
				local name = currencyInfo.name
				local quantity = currencyInfo.quantity or 0
				local iconFileID = currencyInfo.iconFileID
				local statKey = 'currency_' .. currencyID

				-- Update quantity in DETECTED_CURRENCIES
				if DETECTED_CURRENCIES[statKey] then
					DETECTED_CURRENCIES[statKey].quantity = quantity
				end

				-- Add to current stats if player has some or enabled in settings
				if quantity > 0 or (StatsTracker.DB.enabledStats and StatsTracker.DB.enabledStats[statKey]) then
					-- Create dynamic STAT_CONFIG entry
					if not STAT_CONFIG[statKey] then
						STAT_CONFIG[statKey] = {
							label = name,
							icon = iconFileID and ('Interface\\Icons\\' .. iconFileID) or 'Interface\\Icons\\INV_Misc_Coin_01',
						}
					end

					local displayValue = FormatNumber(quantity)
					currentStats[statKey] = {
						value = quantity,
						displayValue = FormatStatDisplay(statKey, displayValue),
						rawDisplayValue = displayValue,
						color = StatsTracker.DB.textColor or { 1, 1, 1 },
						type = 'currency',
						currencyID = currencyID,
						currencyName = name,
					}
				end
			end
		end
	end

	-- Also check commonly tracked currencies directly by ID for reliability
	local importantCurrencies = {
		3008, -- Valorstones
		2815, -- Resonance Crystals (Kej)
		2812, -- Aspect Crests
		2809, -- Whelpling Crests
		2807, -- Drake Crests
		2806, -- Wyrm Crests
		2245, -- Flightstones
		1792, -- Honor
		1602, -- Conquest
		1166, -- Timewarped Badge
	}

	for _, currencyID in ipairs(importantCurrencies) do
		local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(currencyID)
		if currencyInfo and currencyInfo.name then
			local name = currencyInfo.name
			local quantity = currencyInfo.quantity or 0
			local iconFileID = currencyInfo.iconFileID
			local statKey = 'currency_' .. currencyID

			-- Ensure it's in detected currencies
			if not DETECTED_CURRENCIES[statKey] then
				DETECTED_CURRENCIES[statKey] = {
					name = name,
					icon = iconFileID,
					id = currencyID,
					quantity = quantity,
				}
			end

			-- Add to stats if enabled or has quantity
			if quantity > 0 or (StatsTracker.DB.enabledStats and StatsTracker.DB.enabledStats[statKey]) then
				if not STAT_CONFIG[statKey] then
					STAT_CONFIG[statKey] = {
						label = name,
						icon = iconFileID and ('Interface\\Icons\\' .. iconFileID) or 'Interface\\Icons\\INV_Misc_Coin_01',
					}
				end

				local displayValue = FormatNumber(quantity)

				-- Calculate progress if goal is set
				local goal = StatsTracker.DB.currencyGoals[statKey] or 0
				local progress = nil
				if goal > 0 then
					progress = math.min(1, quantity / goal)
				end

				currentStats[statKey] = {
					value = quantity,
					displayValue = FormatStatDisplay(statKey, displayValue),
					rawDisplayValue = displayValue,
					color = StatsTracker.DB.textColor or { 1, 1, 1 },
					type = 'currency',
					currencyID = currencyID,
					currencyName = name,
					progress = progress,
					goal = goal,
				}
			end
		end
	end
end

---Main update function
local function UpdateStats()
	if not StatsTracker.DB.enabled then
		return
	end

	CollectPerformanceStats()
	CollectCharacterStats()
	CollectGameplayStats()
	CollectCurrencyStats()

	-- Update display frames
	StatsTracker:UpdateDisplayFrames()
end

---Initialize session data
function StatsTracker:InitializeSession()
	sessionData = {
		startTime = GetTime(),
		startXP = UnitXP('player'),
		startGold = GetMoney(),
		kills = 0,
		deaths = 0,
		characterCreated = time() - (GetTime() / time()), -- Approximate character creation time
	}

	-- Clear XP history for new session
	xpHistory = {}
end

---Handle player kill events
function StatsTracker:PLAYER_REGEN_ENABLED()
	-- Exited combat - could check for honor gains here for PvP kills
end

---Handle player death
function StatsTracker:PLAYER_DEAD()
	sessionData.deaths = sessionData.deaths + 1
end

---Handle NPC kills (approximate)
function StatsTracker:COMBAT_LOG_EVENT_UNFILTERED()
	local _, eventType, _, sourceGUID, _, _, _, destGUID, destName = CombatLogGetCurrentEventInfo()

	if eventType == 'UNIT_DIED' and sourceGUID == UnitGUID('player') then
		-- Player killed something
		if destGUID and not UnitIsPlayer(destName) then
			sessionData.kills = sessionData.kills + 1
		end
	end
end

---Handle currency updates
function StatsTracker:CURRENCY_DISPLAY_UPDATE()
	-- Update currency stats immediately when currencies change
	CollectCurrencyStats()
	self:UpdateDisplayFrames()
end

---Handle money changes
function StatsTracker:PLAYER_MONEY()
	-- Update gold display immediately when money changes
	CollectCharacterStats()
	self:UpdateDisplayFrames()
end

function StatsTracker:OnInitialize()
	---@class StatsTracker.DB
	local defaults = {
		profile = {
			enabled = true,
			updateInterval = 1.0,
			adaptiveColors = true,
			textColor = { 1, 1, 1 },
			-- Display options
			showProgressBars = true,
			progressBarHeight = 3,
			backgroundColor = { 0, 0, 0, 0.7 },
			borderColor = { 0.3, 0.3, 0.3, 1 },
			showLabels = true,
			showIcons = false,
			elementWidth = 150,
			elementPadding = 2,
			-- Enabled stats
			enabledStats = {
				fps = true,
				latency = true,
				memory = true,
				bags = true,
				durability = true,
				gold = true,
				sessionTime = true,
				totalTime = false,
				xp = true,
				xpPerHour = true,
				recentXpRate = false,
				restedXP = true,
				kills = true,
				deaths = true,
				kdr = true,
			},
			-- Currency goals for progress tracking
			currencyGoals = {
				['**'] = 0, -- Default no goal
			},
			-- Display frames
			frames = {
				['**'] = {
					enabled = true,
					position = 'CENTER,UIParent,CENTER,0,0',
					width = 200,
					height = 20,
					scale = 1.0,
					stats = { 'fps', 'latency' },
					layout = 'vertical', -- 'horizontal' or 'vertical'
					spacing = 0,
					growDirection = 'right', -- 'up', 'down', 'left', 'right'
					mouseoverPosition = 'above', -- 'above', 'below', 'left', 'right'
					mouseoverSpacing = 0,
					statVisibility = {
						['**'] = 'always', -- 'always' or 'mouseover'
					},
				},
			},
		},
	}

	StatsTracker.Database = SUI.SpartanUIDB:RegisterNamespace('StatsTracker', defaults)
	StatsTracker.DB = StatsTracker.Database.profile

	-- Register profile change callbacks
	SUI.DBM:RegisterProfileCallbacks(StatsTracker)

	-- Get MoveIt reference
	MoveIt = SUI:GetModule('MoveIt')

	-- Initialize session
	StatsTracker:InitializeSession()

	-- Initialize display system
	StatsTracker:InitializeDisplay()

	-- Build options
	StatsTracker:Options()
end

function StatsTracker:OnEnable()
	if SUI:IsModuleDisabled('StatsTracker') then
		return
	end

	-- Register events
	self:RegisterEvent('PLAYER_DEAD')
	self:RegisterEvent('PLAYER_REGEN_ENABLED')
	self:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
	self:RegisterEvent('PLAYER_ENTERING_WORLD', 'InitializeSession')

	-- Register currency and money events for real-time updates
	self:RegisterEvent('CURRENCY_DISPLAY_UPDATE')
	self:RegisterEvent('PLAYER_MONEY')

	-- Start update timer
	updateTimer = self:ScheduleRepeatingTimer(UpdateStats, self.DB.updateInterval)

	-- Discover currencies for options UI
	self:DiscoverCurrencies()

	-- Create display frames
	self:CreateDisplayFrames()

	-- Initial update
	UpdateStats()
end

function StatsTracker:OnDisable()
	if updateTimer then
		self:CancelTimer(updateTimer)
		updateTimer = nil
	end

	-- Hide all display frames
	for _, frame in pairs(displayFrames) do
		if frame then
			frame:Hide()
		end
	end

	self:UnregisterAllEvents()
end

-- Export for external access
StatsTracker.GetCurrentStats = function()
	return currentStats
end
StatsTracker.GetSessionData = function()
	return sessionData
end
