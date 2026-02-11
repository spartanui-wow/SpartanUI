local _G, SUI, L = _G, SUI, SUI.L

-- Retail-only module (classic uses different quest tracking)
if not SUI.IsRetail then
	return
end

local module = SUI:NewModule('ObjectiveTracker') ---@type SUI.Module.ObjectiveTracker
module.DisplayName = 'Objective Tracker'
module.description = 'Enhanced objective tracker with advanced customization options and rules builder'

----------------------------------------------------------------------------------------------------
-- Module Variables
local ObjectiveTrackerFrame
local fadeInAnim, fadeOutAnim
local backgroundFrame
local rulesEngine

----------------------------------------------------------------------------------------------------
-- Rules System Type Definitions

---@class ObjectiveRule
---@field id string Unique rule identifier
---@field name string User-friendly rule name
---@field enabled boolean Whether this rule is active
---@field priority number Lower numbers = higher priority (1 = highest)
---@field conditions ObjectiveCondition[] List of conditions (AND logic)
---@field actions ObjectiveAction[] What to do when conditions match

---@class ObjectiveCondition
---@field type ConditionType The condition type
---@field value any The condition value
---@field operator? string Comparison operator (for numeric conditions)

---@alias ConditionType
---| "groupState"    # Solo, Group, Raid
---| "combatState"   # InCombat, OutOfCombat
---| "instanceType"  # Outdoor, Dungeon, Raid, PvP, Scenario
---| "zoneType"      # City, Outdoor, Instance
---| "playerLevel"   # Level comparison
---| "timeOfDay"     # Day, Night
---| "questItemNearby" # Quest item available within range

---@class ObjectiveAction
---@field type ActionType The action type
---@field targets string[] List of objective tracker sections to affect

---@alias ActionType
---| "hide"         # Hide the specified sections
---| "show"         # Show the specified sections
---| "collapse"     # Collapse the specified sections
---| "expand"       # Expand the specified sections

-- Available tracker sections
local TRACKER_SECTIONS = {
	'achievement',
	'quest',
	'bonus',
	'scenario',
	'world',
	'campaign',
	'monthly',
	'adventure',
	'professions',
}

----------------------------------------------------------------------------------------------------
-- Database and Settings

function module:OnInitialize()
	---@class SUI.ObjectiveTracker.Database
	local defaults = {
		enabled = true,
		scale = 1.0,
		opacity = 1.0,
		mouseoverOpacity = true,
		mouseoverFadeIn = 1.0,
		mouseoverFadeOut = 0.6,
		mouseoverDelay = 0.4,
		backgroundEnabled = false,
		backgroundColor = { r = 0, g = 0, b = 0, a = 0.5 },
		-- Quest button system
		questButton = {
			enabled = false,
			scale = 1.0,
			position = {
				point = 'TOP',
				relativeTo = 'ObjectiveTrackerFrame',
				relativePoint = 'TOP',
				x = 0,
				y = 25,
			},
			maxDistance = 100,
			zoneOnly = true,
			trackingOnly = false,
		},
		rules = {
			-- Example default rule: Hide quests in raid when in combat
			['rule_1'] = {
				id = 'rule_1',
				name = 'Hide Quests in Raid Combat',
				enabled = false,
				priority = 1,
				conditions = {
					{ type = 'groupState', value = 'Raid' },
					{ type = 'combatState', value = 'InCombat' },
				},
				actions = {
					{ type = 'hide', targets = { 'quest', 'bonus' } },
				},
			},
			-- Example rule: Group combat behavior
			['rule_2'] = {
				id = 'rule_2',
				name = 'Group Combat - Hide All Except Scenario',
				enabled = false,
				priority = 2,
				conditions = {
					{ type = 'groupState', value = 'Group' },
					{ type = 'combatState', value = 'InCombat' },
					{ type = 'instanceType', value = 'Dungeon' },
				},
				actions = {
					{ type = 'hide', targets = { 'quest', 'achievement', 'bonus', 'world' } },
				},
			},
			-- Example rule: Solo outdoor quest focus
			['rule_3'] = {
				id = 'rule_3',
				name = 'Solo Outdoor - Show Only Quests',
				enabled = false,
				priority = 3,
				conditions = {
					{ type = 'groupState', value = 'Solo' },
					{ type = 'zoneType', value = 'Outdoor' },
					{ type = 'combatState', value = 'OutOfCombat' },
				},
				actions = {
					{ type = 'show', targets = { 'quest', 'world' } },
					{ type = 'hide', targets = { 'achievement', 'bonus' } },
				},
			},
			-- Example rule: Never hide when quest item is nearby
			['rule_4'] = {
				id = 'rule_4',
				name = 'Always Show When Quest Item Nearby',
				enabled = false,
				priority = 0, -- Highest priority
				conditions = {
					{ type = 'questItemNearby', value = 'true' },
				},
				actions = {
					{ type = 'show', targets = { 'quest', 'world', 'bonus' } },
				},
			},
		},
		nextRuleId = 5,
	}

	module.Database = SUI.SpartanUIDB:RegisterNamespace('ObjectiveTracker', { profile = defaults })
	module.DB = module.Database.profile ---@type SUI.ObjectiveTracker.Database

	-- Register profile change callbacks
	SUI.DBM:RegisterSequentialProfileRefresh(module)
end

function module:OnEnable()
	if SUI:IsModuleDisabled('ObjectiveTracker') then
		return
	end

	-- Initialize frame references
	ObjectiveTrackerFrame = _G.ObjectiveTrackerFrame

	-- Wait for ObjectiveTrackerFrame if it's not available yet
	if not ObjectiveTrackerFrame then
		local waitFrame = CreateFrame('Frame')
		waitFrame:RegisterEvent('ADDON_LOADED')
		waitFrame:RegisterEvent('PLAYER_LOGIN')
		waitFrame:SetScript('OnEvent', function(self, event)
			ObjectiveTrackerFrame = _G.ObjectiveTrackerFrame
			if ObjectiveTrackerFrame then
				waitFrame:UnregisterAllEvents()
				module:SetupObjectiveTracker()
			end
		end)
	else
		module:SetupObjectiveTracker()
	end

	module:SetupRulesEngine()
	module:BuildOptions()
end

function module:OnDisable()
	module:CleanupModule()
end

function module:CleanupModule()
	-- Clean up animations
	if fadeInAnim then
		fadeInAnim:Stop()
		fadeInAnim = nil
	end
	if fadeOutAnim then
		fadeOutAnim:Stop()
		fadeOutAnim = nil
	end

	-- Clean up mouseover area and timers
	if module.mouseArea then
		module.mouseArea:SetScript('OnUpdate', nil)
		module.mouseArea:Hide()
		module.mouseArea = nil
	end

	-- Clean up any pending timers
	if module.checkTimer then
		module.checkTimer:Cancel()
		module.checkTimer = nil
	end

	-- Reset ObjectiveTrackerFrame to original state
	if ObjectiveTrackerFrame then
		ObjectiveTrackerFrame:SetScale(1.0)
		ObjectiveTrackerFrame:SetAlpha(1.0)
		ObjectiveTrackerFrame:Show()
	end

	-- Clean up background frame
	if backgroundFrame then
		backgroundFrame:Hide()
	end
end

----------------------------------------------------------------------------------------------------
-- Core Functionality

function module:SetupObjectiveTracker()
	if not ObjectiveTrackerFrame then
		return
	end

	-- Create a separate background frame
	if not backgroundFrame then
		backgroundFrame = CreateFrame('Frame', nil, ObjectiveTrackerFrame)
		backgroundFrame:SetAllPoints(ObjectiveTrackerFrame.NineSlice)
		backgroundFrame:SetFrameLevel(ObjectiveTrackerFrame:GetFrameLevel() - 1)

		local bg = backgroundFrame:CreateTexture(nil, 'BACKGROUND')
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.5)
		backgroundFrame.texture = bg
		backgroundFrame:Hide()
	end

	-- Apply initial settings
	module:UpdateScale()
	module:UpdateOpacity()
	module:UpdateBackground()

	-- Setup mouseover effects
	module:SetupMouseoverEffects()
end

function module:SetupMouseoverEffects()
	if not module.DB.mouseoverOpacity or not ObjectiveTrackerFrame then
		return
	end

	-- Set initial alpha
	ObjectiveTrackerFrame:SetAlpha(module.DB.mouseoverFadeOut)

	-- Track mouse state
	local isFadedIn = false
	local fadeTimer = nil

	-- Function to fade elements in/out using UIFrameFadeIn/UIFrameFadeOut (like BetterBlizzFrames)
	local function FadeInFrame()
		UIFrameFadeIn(ObjectiveTrackerFrame, 0.2, ObjectiveTrackerFrame:GetAlpha(), module.DB.mouseoverFadeIn)
	end

	local function FadeOutFrame()
		UIFrameFadeOut(ObjectiveTrackerFrame, 0.5, ObjectiveTrackerFrame:GetAlpha(), module.DB.mouseoverFadeOut)
	end

	-- Function to check if mouse is over actual objective tracker content areas
	local function IsAnyMouseOver()
		-- Check the main header
		if ObjectiveTrackerFrame.Header and ObjectiveTrackerFrame.Header:IsMouseOver() then
			return true
		end

		-- Check individual tracker modules (only the actual content areas)
		local trackerModules = {
			'AchievementObjectiveTracker',
			'QuestObjectiveTracker',
			'BonusObjectiveTracker',
			'ScenarioObjectiveTracker',
			'WorldQuestObjectiveTracker',
			'CampaignQuestObjectiveTracker',
			'MonthlyActivitiesObjectiveTracker',
			'AdventureObjectiveTracker',
			'ProfessionsRecipeTracker',
		}

		for _, moduleName in ipairs(trackerModules) do
			local trackerModule = _G[moduleName]
			if trackerModule and trackerModule:IsShown() and trackerModule:IsMouseOver() then
				return true
			end
		end

		return false
	end

	-- Show elements (fade in)
	local function ShowElements()
		-- Check if mouseover is enabled
		if not module.DB.mouseoverOpacity then
			return
		end

		if not isFadedIn then
			if fadeTimer then
				fadeTimer:Cancel()
				fadeTimer = nil
				module.checkTimer = nil
			end
			FadeInFrame()
			isFadedIn = true
		end
	end

	-- Hide elements (fade out with grace period)
	local function HideElements()
		-- Check if mouseover is enabled
		if not module.DB.mouseoverOpacity then
			return
		end

		if fadeTimer then
			fadeTimer:Cancel()
		end

		fadeTimer = C_Timer.NewTimer(module.DB.mouseoverDelay, function()
			if not IsAnyMouseOver() then
				FadeOutFrame()
				isFadedIn = false
			end
			fadeTimer = nil
			module.checkTimer = nil
		end)
		module.checkTimer = fadeTimer
	end

	-- Clean up any existing hooks to avoid duplicates
	if ObjectiveTrackerFrame.suiMouseHooked then
		-- We can't easily unhook, but we can mark and avoid re-hooking
	end

	-- Hook mouse events to individual content areas instead of the entire frame
	-- Hook the header
	if ObjectiveTrackerFrame.Header and not ObjectiveTrackerFrame.Header.suiMouseHooked then
		ObjectiveTrackerFrame.Header:HookScript('OnEnter', ShowElements)
		ObjectiveTrackerFrame.Header:HookScript('OnLeave', HideElements)
		ObjectiveTrackerFrame.Header.suiMouseHooked = true
	end

	-- Hook each tracker module
	local trackerModules = {
		'AchievementObjectiveTracker',
		'QuestObjectiveTracker',
		'BonusObjectiveTracker',
		'ScenarioObjectiveTracker',
		'WorldQuestObjectiveTracker',
		'CampaignQuestObjectiveTracker',
		'MonthlyActivitiesObjectiveTracker',
		'AdventureObjectiveTracker',
		'ProfessionsRecipeTracker',
	}

	for _, moduleName in ipairs(trackerModules) do
		local trackerModule = _G[moduleName]
		if trackerModule and not trackerModule.suiMouseHooked then
			trackerModule:HookScript('OnEnter', ShowElements)
			trackerModule:HookScript('OnLeave', HideElements)
			trackerModule.suiMouseHooked = true
		end
	end

	-- Initial state: start faded out
	FadeOutFrame()
	isFadedIn = false
end

function module:SetupRulesEngine()
	if not rulesEngine then
		rulesEngine = CreateFrame('Frame')
		rulesEngine:RegisterEvent('PLAYER_REGEN_DISABLED') -- Combat start
		rulesEngine:RegisterEvent('PLAYER_REGEN_ENABLED') -- Combat end
		rulesEngine:RegisterEvent('GROUP_JOINED')
		rulesEngine:RegisterEvent('GROUP_LEFT')
		rulesEngine:RegisterEvent('GROUP_ROSTER_UPDATE')
		rulesEngine:RegisterEvent('ZONE_CHANGED')
		rulesEngine:RegisterEvent('ZONE_CHANGED_INDOORS')
		rulesEngine:RegisterEvent('ZONE_CHANGED_NEW_AREA')
		rulesEngine:RegisterEvent('PLAYER_LEVEL_UP')
		-- Quest item detection events
		rulesEngine:RegisterEvent('QUEST_LOG_UPDATE')
		rulesEngine:RegisterEvent('QUEST_WATCH_LIST_CHANGED')
		rulesEngine:RegisterEvent('BAG_UPDATE_DELAYED')

		rulesEngine:SetScript('OnEvent', function(self, event, ...)
			module:EvaluateRules(event)
		end)

		-- Update quest button every 5 seconds for distance checks
		if module.DB.questButton.enabled then
			C_Timer.NewTicker(5, function()
				module:UpdateQuestButton()
			end)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Quest Item Detection

function module:HasQuestItemNearby()
	local settings = module.DB.questButton
	return module:GetClosestQuestItem(settings.maxDistance, settings.zoneOnly, settings.trackingOnly) ~= nil
end

function module:GetClosestQuestItem(maxDistanceYd, zoneOnly, trackingOnly)
	-- Simplified version of ExtraQuestButton logic
	for index = 1, C_QuestLog.GetNumQuestWatches() do
		local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(index)
		if questID then
			local distance, itemLink = module:GetQuestDistanceWithItem(questID, maxDistanceYd, zoneOnly)
			if itemLink then
				return itemLink, distance
			end
		end
	end

	-- Check world quests if not tracking only
	if not trackingOnly then
		for index = 1, C_QuestLog.GetNumWorldQuestWatches() do
			local questID = C_QuestLog.GetQuestIDForWorldQuestWatchIndex(index)
			if questID then
				local distance, itemLink = module:GetQuestDistanceWithItem(questID, maxDistanceYd, zoneOnly)
				if itemLink then
					return itemLink, distance
				end
			end
		end
	end

	return nil
end

function module:GetQuestDistanceWithItem(questID, maxDistanceYd, zoneOnly)
	local questLogIndex = C_QuestLog.GetLogIndexForQuestID(questID)
	if not questLogIndex then
		return nil
	end

	local itemLink = GetQuestLogSpecialItemInfo(questLogIndex)
	if not itemLink then
		return nil
	end

	if C_Item.GetItemCount(itemLink) == 0 then
		return nil -- No point showing items we don't have
	end

	-- Check if quest is on current zone if zoneOnly is enabled
	if zoneOnly and not C_QuestLog.IsOnMap(questID) then
		return nil
	end

	-- Check distance
	local distanceSq = C_QuestLog.GetDistanceSqToQuest(questID)
	if distanceSq then
		local distanceYd = math.sqrt(distanceSq)
		if distanceYd <= maxDistanceYd then
			return distanceYd, itemLink
		end
	end

	return nil
end

----------------------------------------------------------------------------------------------------
-- Quest Button Implementation

local questButton

function module:CreateQuestButton()
	if questButton then
		return questButton
	end

	questButton = CreateFrame('Button', 'SUI_ObjectiveQuestButton', ObjectiveTrackerFrame, 'ActionButtonTemplate, SecureActionButtonTemplate')
	questButton:SetSize(32, 32)
	questButton:SetAttribute('type', 'item')

	-- Initialize button mixin
	Mixin(questButton, ItemMixin)

	-- Style the button
	questButton:SetNormalTexture([[Interface\Buttons\UI-Quickslot2]])
	questButton:SetPushedTexture([[Interface\Buttons\UI-Quickslot-Depress]])
	questButton:SetHighlightTexture([[Interface\Buttons\ButtonHilight-Square]], 'ADD')

	-- Add cooldown frame
	local cooldown = CreateFrame('Cooldown', questButton:GetName() .. 'Cooldown', questButton, 'CooldownFrameTemplate')
	cooldown:SetAllPoints()
	questButton.cooldown = cooldown

	-- Add count text
	local count = questButton:CreateFontString(nil, 'OVERLAY', 'NumberFontNormal')
	count:SetPoint('BOTTOMRIGHT', -2, 2)
	questButton.Count = count

	questButton:Hide()

	-- Set up secure visibility attribute driver
	RegisterAttributeDriver(questButton, 'state-visibility', 'hide')

	questButton:RegisterEvent('BAG_UPDATE_DELAYED')
	questButton:RegisterEvent('BAG_UPDATE_COOLDOWN')

	questButton:SetScript('OnEvent', function(self, event)
		if event == 'BAG_UPDATE_DELAYED' then
			module:UpdateQuestButtonCount()
		elseif event == 'BAG_UPDATE_COOLDOWN' then
			module:UpdateQuestButtonCooldown()
		end
	end)

	questButton:SetScript('OnEnter', function(self)
		local itemLink = self:GetItemLink()
		if itemLink then
			GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
			GameTooltip:SetHyperlink(itemLink)
		end
	end)

	questButton:SetScript('OnLeave', function(self)
		GameTooltip_Hide(self)
	end)

	return questButton
end

function module:UpdateQuestButton()
	if not module.DB.questButton.enabled then
		if questButton then
			-- Use secure method to hide the button
			if InCombatLockdown() then
				questButton:SetAttribute('state-visibility', 'hide')
			else
				questButton:Hide()
			end
		end
		return
	end

	if not questButton then
		questButton = module:CreateQuestButton()
	end

	local settings = module.DB.questButton
	local itemLink, distance = module:GetClosestQuestItem(settings.maxDistance, settings.zoneOnly, settings.trackingOnly)

	if itemLink then
		if itemLink ~= questButton:GetItemLink() then
			questButton:SetItemLink(itemLink)
			questButton:SetIcon(C_Item.GetItemIconByID(questButton:GetItemID()))
			questButton:SetAttribute('item', 'item:' .. questButton:GetItemID())

			module:UpdateQuestButtonCount()
			module:UpdateQuestButtonCooldown()

			SUI.Log('Quest button updated with item: ' .. itemLink, 'ObjectiveTracker', 'debug')
		end

		-- Use secure method to show the button
		if InCombatLockdown() then
			questButton:SetAttribute('state-visibility', 'show')
		else
			questButton:Show()
		end
		module:PositionQuestButton()
	else
		-- Use secure method to hide the button
		if InCombatLockdown() then
			questButton:SetAttribute('state-visibility', 'hide')
		else
			questButton:Hide()
			questButton:SetAttribute('item', nil)
		end
	end
end

function module:UpdateQuestButtonCount()
	if not questButton or questButton:IsItemEmpty() then
		return
	end

	local count = C_Item.GetItemCount(questButton:GetItemLink())
	if count > 1 then
		questButton.Count:SetText(count)
		questButton.Count:Show()
	else
		questButton.Count:Hide()
	end
end

function module:UpdateQuestButtonCooldown()
	if not questButton or questButton:IsItemEmpty() then
		return
	end

	local start, duration = C_Item.GetItemCooldown(questButton:GetItemID())
	if duration > 0 then
		questButton.cooldown:SetCooldown(start, duration)
		questButton.cooldown:Show()
	else
		questButton.cooldown:Hide()
	end
end

function module:PositionQuestButton()
	if not questButton then
		return
	end

	local pos = module.DB.questButton.position
	questButton:ClearAllPoints()
	questButton:SetPoint(pos.point, _G[pos.relativeTo], pos.relativePoint, pos.x, pos.y)
	questButton:SetScale(module.DB.questButton.scale)
end

----------------------------------------------------------------------------------------------------
-- Update Functions

function module:UpdateScale()
	if ObjectiveTrackerFrame then
		-- Validate scale bounds
		local scale = math.max(0.5, math.min(2.0, module.DB.scale))
		if scale ~= module.DB.scale then
			module.DB.scale = scale
		end
		ObjectiveTrackerFrame:SetScale(scale)
	end
end

function module:UpdateOpacity()
	if not module.DB.mouseoverOpacity and ObjectiveTrackerFrame then
		-- Validate opacity bounds
		local opacity = math.max(0.1, math.min(1.0, module.DB.opacity))
		if opacity ~= module.DB.opacity then
			module.DB.opacity = opacity
		end
		ObjectiveTrackerFrame:SetAlpha(opacity)
	end
end

function module:UpdateBackground()
	if not ObjectiveTrackerFrame then
		return
	end

	if module.DB.backgroundEnabled and backgroundFrame then
		-- Show background
		if backgroundFrame.texture then
			local color = module.DB.backgroundColor
			backgroundFrame.texture:SetColorTexture(color.r, color.g, color.b, color.a)
			backgroundFrame:Show()
		end
	else
		if backgroundFrame then
			backgroundFrame:Hide()
		end
	end
end

function module:UpdateMouseoverSettings()
	-- Clean up existing mouseover effects
	if fadeInAnim then
		fadeInAnim:Stop()
		fadeInAnim = nil
	end
	if fadeOutAnim then
		fadeOutAnim:Stop()
		fadeOutAnim = nil
	end
	if module.mouseArea then
		module.mouseArea:SetScript('OnUpdate', nil)
		module.mouseArea:Hide()
		module.mouseArea = nil
	end
	if module.checkTimer then
		module.checkTimer:Cancel()
		module.checkTimer = nil
	end

	-- Only setup mouseover if ObjectiveTrackerFrame exists and mouseover is enabled
	if ObjectiveTrackerFrame and module.DB.mouseoverOpacity then
		module:SetupMouseoverEffects()
	elseif ObjectiveTrackerFrame then
		-- Reset to normal opacity when mouseover is disabled
		ObjectiveTrackerFrame:SetAlpha(module.DB.opacity)
	end
end

----------------------------------------------------------------------------------------------------
-- Rules Engine

function module:EvaluateRules(triggerEvent)
	if not module.DB.rules then
		SUI.Log('Rules evaluation skipped - rules missing', 'ObjectiveTracker', 'debug')
		return
	end

	SUI.Log('Evaluating rules triggered by: ' .. (triggerEvent or 'manual'), 'ObjectiveTracker', 'info')

	-- Get all enabled rules sorted by priority
	local activeRules = {}
	for _, rule in pairs(module.DB.rules) do
		if rule.enabled then
			table.insert(activeRules, rule)
		end
	end

	table.sort(activeRules, function(a, b)
		return a.priority < b.priority
	end)

	-- Evaluate each rule
	for _, rule in ipairs(activeRules) do
		if module:EvaluateRule(rule) then
			SUI.Log('Rule "' .. rule.name .. '" conditions met, executing actions', 'ObjectiveTracker', 'info')
			module:ExecuteRuleActions(rule)
			-- Only execute the first matching rule (highest priority)
			return
		end
	end

	SUI.Log('No rules matched current conditions', 'ObjectiveTracker', 'debug')
end

---@param rule ObjectiveRule
---@return boolean
function module:EvaluateRule(rule)
	for _, condition in ipairs(rule.conditions) do
		if not module:EvaluateCondition(condition) then
			return false
		end
	end
	return true
end

---@param condition ObjectiveCondition
---@return boolean
function module:EvaluateCondition(condition)
	local conditionType = condition.type
	local expectedValue = condition.value
	local operator = condition.operator or '=='

	if conditionType == 'groupState' then
		local currentState = module:GetGroupState()
		return currentState == expectedValue
	elseif conditionType == 'combatState' then
		local inCombat = InCombatLockdown()
		local currentState = inCombat and 'InCombat' or 'OutOfCombat'
		return currentState == expectedValue
	elseif conditionType == 'instanceType' then
		local currentType = module:GetInstanceType()
		return currentType == expectedValue
	elseif conditionType == 'zoneType' then
		local currentType = module:GetZoneType()
		return currentType == expectedValue
	elseif conditionType == 'playerLevel' then
		local currentLevel = UnitLevel('player')
		return module:CompareValues(currentLevel, expectedValue, operator)
	elseif conditionType == 'timeOfDay' then
		local currentTime = module:GetTimeOfDay()
		return currentTime == expectedValue
	elseif conditionType == 'questItemNearby' then
		local hasQuestItem = module:HasQuestItemNearby()
		local expectedState = expectedValue == 'true' or expectedValue == true
		return hasQuestItem == expectedState
	end

	return false
end

---@param rule ObjectiveRule
function module:ExecuteRuleActions(rule)
	for _, action in ipairs(rule.actions) do
		local actionType = action.type
		local targets = action.targets or {}

		SUI.Log('Executing action "' .. actionType .. '" on targets: ' .. table.concat(targets, ', '), 'ObjectiveTracker', 'info')

		for _, target in ipairs(targets) do
			if actionType == 'hide' then
				module:SetSectionVisibility(target, false)
			elseif actionType == 'show' then
				module:SetSectionVisibility(target, true)
			elseif actionType == 'collapse' then
				module:SetSectionCollapsed(target, true)
			elseif actionType == 'expand' then
				module:SetSectionCollapsed(target, false)
			end
		end
	end
end

-- Condition evaluation helper functions

function module:GetGroupState()
	if IsInRaid() then
		return 'Raid'
	elseif IsInGroup() then
		return 'Group'
	else
		return 'Solo'
	end
end

function module:GetInstanceType()
	local _, instanceType = IsInInstance()
	if instanceType == 'party' then
		return 'Dungeon'
	elseif instanceType == 'raid' then
		return 'Raid'
	elseif instanceType == 'pvp' then
		return 'PvP'
	elseif instanceType == 'scenario' then
		return 'Scenario'
	else
		return 'Outdoor'
	end
end

function module:GetZoneType()
	local inInstance = IsInInstance()
	if inInstance then
		return 'Instance'
	end

	local pvpType = C_PvP.GetZonePVPInfo()
	if pvpType == 'sanctuary' then
		return 'City'
	else
		return 'Outdoor'
	end
end

function module:GetTimeOfDay()
	local hour = tonumber(date('%H'))
	if hour >= 6 and hour < 18 then
		return 'Day'
	else
		return 'Night'
	end
end

function module:CompareValues(current, expected, operator)
	if operator == '==' then
		return current == expected
	elseif operator == '!=' then
		return current ~= expected
	elseif operator == '>' then
		return current > expected
	elseif operator == '<' then
		return current < expected
	elseif operator == '>=' then
		return current >= expected
	elseif operator == '<=' then
		return current <= expected
	end
	return false
end

function module:SetSectionVisibility(sectionName, visible)
	local sectionMap = {
		achievement = 'AchievementObjectiveTracker',
		quest = 'QuestObjectiveTracker',
		bonus = 'BonusObjectiveTracker',
		scenario = 'ScenarioObjectiveTracker',
		world = 'WorldQuestObjectiveTracker',
		campaign = 'CampaignQuestObjectiveTracker',
		monthly = 'MonthlyActivitiesObjectiveTracker',
		adventure = 'AdventureObjectiveTracker',
		professions = 'ProfessionsRecipeTracker',
	}

	local moduleKey = sectionMap[sectionName]
	local trackerModule = _G[moduleKey]
	if trackerModule then
		local success = pcall(function()
			if visible then
				if trackerModule.Show then
					trackerModule:Show()
				end
			else
				if trackerModule.Hide then
					trackerModule:Hide()
				end
			end
		end)
		if success then
			SUI.Log('Set section "' .. sectionName .. '" visibility to ' .. tostring(visible), 'ObjectiveTracker', 'debug')
		end
	end
end

function module:SetSectionCollapsed(sectionName, collapsed)
	local sectionMap = {
		achievement = 'AchievementObjectiveTracker',
		quest = 'QuestObjectiveTracker',
		bonus = 'BonusObjectiveTracker',
		scenario = 'ScenarioObjectiveTracker',
		world = 'WorldQuestObjectiveTracker',
		campaign = 'CampaignQuestObjectiveTracker',
		monthly = 'MonthlyActivitiesObjectiveTracker',
		adventure = 'AdventureObjectiveTracker',
		professions = 'ProfessionsRecipeTracker',
	}

	local moduleKey = sectionMap[sectionName]
	local trackerModule = _G[moduleKey]
	if trackerModule then
		local success = pcall(function()
			if trackerModule.SetCollapsed then
				trackerModule:SetCollapsed(collapsed)
			elseif trackerModule.Header and trackerModule.Header.MinimizeButton then
				local isCurrentlyCollapsed = trackerModule.collapsed or false
				if collapsed ~= isCurrentlyCollapsed then
					trackerModule.Header.MinimizeButton:Click()
				end
			end
		end)
		if success then
			SUI.Log('Set section "' .. sectionName .. '" collapsed to ' .. tostring(collapsed), 'ObjectiveTracker', 'debug')
		end
	end
end

-- Rule management functions

function module:CreateRule(name, conditions, actions)
	local ruleId = 'rule_' .. module.DB.nextRuleId
	module.DB.nextRuleId = module.DB.nextRuleId + 1

	local rule = {
		id = ruleId,
		name = name or 'New Rule',
		enabled = true,
		priority = module:GetNextPriority(),
		conditions = conditions or {},
		actions = actions or {},
	}

	module.DB.rules[ruleId] = rule
	SUI.Log('Created new rule: ' .. rule.name, 'ObjectiveTracker', 'info')
	return ruleId
end

function module:DeleteRule(ruleId)
	if module.DB.rules[ruleId] then
		local ruleName = module.DB.rules[ruleId].name
		module.DB.rules[ruleId] = nil
		SUI.Log('Deleted rule: ' .. ruleName, 'ObjectiveTracker', 'info')
	end
end

function module:GetNextPriority()
	local maxPriority = 0
	for _, rule in pairs(module.DB.rules) do
		if rule.priority > maxPriority then
			maxPriority = rule.priority
		end
	end
	return maxPriority + 1
end

----------------------------------------------------------------------------------------------------
-- Public API

function module:ToggleObjectiveTracker()
	if ObjectiveTrackerFrame:IsShown() then
		module:SetObjectiveTrackerVisible(false)
	else
		module:SetObjectiveTrackerVisible(true)
	end
end

function module:SetObjectiveTrackerVisible(visible)
	if visible then
		ObjectiveTrackerFrame:Show()
	else
		ObjectiveTrackerFrame:Hide()
	end
end

function module:ToggleSection(sectionType, visible)
	if not ObjectiveTrackerFrame then
		return
	end

	local sectionMap = {
		achievement = 'AchievementObjectiveTracker',
		quest = 'QuestObjectiveTracker',
		bonus = 'BonusObjectiveTracker',
		scenario = 'ScenarioObjectiveTracker',
		world = 'WorldQuestObjectiveTracker',
	}

	local moduleKey = sectionMap[sectionType]
	local trackerModule = _G[moduleKey]
	if trackerModule then
		-- Use pcall to safely attempt the visibility change
		local success, err = pcall(function()
			if trackerModule.SetShown then
				trackerModule:SetShown(visible)
			elseif visible then
				if trackerModule.Show then
					trackerModule:Show()
				end
			else
				if trackerModule.Hide then
					trackerModule:Hide()
				end
			end
		end)
		if not success then
			-- Silently fail, different versions may have different methods
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Options Panel

function module:GetRulesBuilderOptions()
	local args = {
		description = {
			type = 'description',
			name = L['Create rules to control objective tracker behavior based on different conditions. Rules are evaluated in priority order (lower numbers first).'],
			order = 1,
		},
		newRule = {
			type = 'group',
			name = L['Create New Rule'],
			inline = true,
			order = 2,
			args = {
				newRuleName = {
					type = 'input',
					name = L['Rule Name'],
					desc = L['Enter a name for the new rule'],
					get = function()
						return module.newRuleName or ''
					end,
					set = function(_, value)
						module.newRuleName = value
					end,
					order = 1,
				},
				createRule = {
					type = 'execute',
					name = L['Create Rule'],
					desc = L['Create a new rule with the specified name'],
					disabled = function()
						return not module.newRuleName or module.newRuleName:trim() == ''
					end,
					func = function()
						local name = module.newRuleName:trim()
						if name ~= '' then
							module:CreateRule(name)
							module.newRuleName = nil
							-- Refresh options to show new rule
							LibStub('AceConfigRegistry-3.0'):NotifyChange('SpartanUI')
						end
					end,
					order = 2,
				},
			},
		},
		spacer1 = {
			type = 'description',
			name = '\n',
			order = 3,
		},
		priorityManagement = {
			type = 'group',
			name = L['Rule Priority Management'],
			inline = true,
			order = 4,
			args = module:GetPriorityManagementOptions(),
		},
		spacer2 = {
			type = 'description',
			name = '\n',
			order = 5,
		},
	}

	-- Add existing rules
	local ruleOrder = 10
	local rulesList = {}

	for ruleId, rule in pairs(module.DB.rules or {}) do
		table.insert(rulesList, rule)
	end

	table.sort(rulesList, function(a, b)
		return a.priority < b.priority
	end)

	for _, rule in ipairs(rulesList) do
		args['rule_' .. rule.id] = {
			type = 'group',
			name = rule.name .. ' (Priority: ' .. rule.priority .. ')',
			inline = false,
			order = ruleOrder,
			args = module:GetRuleEditorOptions(rule),
		}
		ruleOrder = ruleOrder + 1
	end

	return args
end

function module:GetPriorityManagementOptions()
	local args = {
		description = {
			type = 'description',
			name = L['Reorder rules by priority (lower numbers execute first). Use arrows to move rules up/down.'],
			order = 1,
		},
	}

	-- Get all rules sorted by priority
	local rulesList = {}
	for ruleId, rule in pairs(module.DB.rules or {}) do
		table.insert(rulesList, rule)
	end
	table.sort(rulesList, function(a, b)
		return a.priority < b.priority
	end)

	local order = 10
	for i, rule in ipairs(rulesList) do
		args['priority_' .. rule.id] = {
			type = 'group',
			name = string.format('%d. %s', rule.priority, rule.name),
			inline = true,
			order = order,
			args = {
				moveUp = {
					type = 'execute',
					name = '↑',
					desc = L['Move rule up (higher priority)'],
					disabled = function()
						return i == 1 -- First rule can't move up
					end,
					func = function()
						module:MoveRulePriority(rule.id, -1)
						LibStub('AceConfigRegistry-3.0'):NotifyChange('SpartanUI')
					end,
					order = 1,
					width = 0.3,
				},
				moveDown = {
					type = 'execute',
					name = '↓',
					desc = L['Move rule down (lower priority)'],
					disabled = function()
						return i == #rulesList -- Last rule can't move down
					end,
					func = function()
						module:MoveRulePriority(rule.id, 1)
						LibStub('AceConfigRegistry-3.0'):NotifyChange('SpartanUI')
					end,
					order = 2,
					width = 0.3,
				},
				enabled = {
					type = 'toggle',
					name = L['Enabled'],
					desc = L['Enable or disable this rule'],
					get = function()
						return rule.enabled
					end,
					set = function(_, value)
						rule.enabled = value
						module:EvaluateRules('manual')
					end,
					order = 3,
					width = 0.5,
				},
				spacer = {
					type = 'description',
					name = '',
					order = 4,
					width = 'full',
				},
			},
		}
		order = order + 1
	end

	return args
end

function module:MoveRulePriority(ruleId, direction)
	local rule = module.DB.rules[ruleId]
	if not rule then
		return
	end

	-- Get all rules sorted by priority
	local rulesList = {}
	for id, r in pairs(module.DB.rules) do
		table.insert(rulesList, r)
	end
	table.sort(rulesList, function(a, b)
		return a.priority < b.priority
	end)

	-- Find current position
	local currentIndex
	for i, r in ipairs(rulesList) do
		if r.id == ruleId then
			currentIndex = i
			break
		end
	end

	if not currentIndex then
		return
	end

	local newIndex = currentIndex + direction
	if newIndex < 1 or newIndex > #rulesList then
		return
	end

	-- Swap priorities
	local otherRule = rulesList[newIndex]
	local tempPriority = rule.priority
	rule.priority = otherRule.priority
	otherRule.priority = tempPriority

	SUI.Log('Moved rule "' .. rule.name .. '" ' .. (direction > 0 and 'down' or 'up'), 'ObjectiveTracker', 'info')
end

function module:GetRuleEditorOptions(rule)
	local conditionTypes = {
		groupState = L['Group State'],
		combatState = L['Combat State'],
		instanceType = L['Instance Type'],
		zoneType = L['Zone Type'],
		playerLevel = L['Player Level'],
		timeOfDay = L['Time of Day'],
	}

	local groupStates = { Solo = L['Solo'], Group = L['Group'], Raid = L['Raid'] }
	local combatStates = { InCombat = L['In Combat'], OutOfCombat = L['Out of Combat'] }
	local instanceTypes = { Outdoor = L['Outdoor'], Dungeon = L['Dungeon'], Raid = L['Raid'], PvP = L['PvP'], Scenario = L['Scenario'] }
	local zoneTypes = { City = L['City'], Outdoor = L['Outdoor'], Instance = L['Instance'] }
	local timeStates = { Day = L['Day'], Night = L['Night'] }
	local operators = { ['=='] = L['Equals'], ['!='] = L['Not Equals'], ['>'] = L['Greater Than'], ['<'] = L['Less Than'], ['>='] = L['Greater or Equal'], ['<='] = L['Less or Equal'] }

	local actionTypes = {
		hide = L['Hide'],
		show = L['Show'],
		collapse = L['Collapse'],
		expand = L['Expand'],
	}

	local trackerSections = {}
	for _, section in ipairs(TRACKER_SECTIONS) do
		trackerSections[section] = L[section:gsub('^%l', string.upper)] or section
	end

	local args = {
		enabled = {
			type = 'toggle',
			name = L['Enabled'],
			desc = L['Enable or disable this rule'],
			get = function()
				return rule.enabled
			end,
			set = function(_, value)
				rule.enabled = value
				if module.DB.rulesEnabled then
					module:EvaluateRules('manual')
				end
			end,
			order = 1,
		},
		priority = {
			type = 'range',
			name = L['Priority'],
			desc = L['Rule priority (lower numbers execute first)'],
			min = 1,
			max = 20,
			step = 1,
			get = function()
				return rule.priority
			end,
			set = function(_, value)
				rule.priority = value
				module:EvaluateRules('manual')
				LibStub('AceConfigRegistry-3.0'):NotifyChange('SpartanUI')
			end,
			order = 2,
		},
		spacer1 = {
			type = 'description',
			name = '\n' .. L['Conditions (ALL must be true):'],
			order = 10,
		},
		deleteRule = {
			type = 'execute',
			name = L['Delete Rule'],
			desc = L['Delete this rule permanently'],
			confirm = true,
			confirmText = L['Are you sure you want to delete this rule?'],
			func = function()
				module:DeleteRule(rule.id)
				LibStub('AceConfigRegistry-3.0'):NotifyChange('SpartanUI')
			end,
			order = 99,
		},
	}

	-- Add condition editors
	local condOrder = 20
	for i, condition in ipairs(rule.conditions) do
		args['condition_' .. i] = module:GetConditionEditorOptions(rule, condition, i, condOrder)
		condOrder = condOrder + 1
	end

	-- Add new condition button
	args.addCondition = {
		type = 'execute',
		name = L['Add Condition'],
		desc = L['Add a new condition to this rule'],
		func = function()
			table.insert(rule.conditions, { type = 'groupState', value = 'Solo' })
			SUI.Options:Refresh()
		end,
		order = condOrder,
	}

	-- Add action editors
	args.spacer2 = {
		type = 'description',
		name = '\n' .. L['Actions (what to do when conditions match):'],
		order = condOrder + 10,
	}

	local actionOrder = condOrder + 20
	for i, action in ipairs(rule.actions) do
		args['action_' .. i] = module:GetActionEditorOptions(rule, action, i, actionOrder)
		actionOrder = actionOrder + 1
	end

	-- Add new action button
	args.addAction = {
		type = 'execute',
		name = L['Add Action'],
		desc = L['Add a new action to this rule'],
		func = function()
			table.insert(rule.actions, { type = 'hide', targets = { 'quest' } })
			SUI.Options:Refresh()
		end,
		order = actionOrder,
	}

	return args
end

function module:GetConditionEditorOptions(rule, condition, index, baseOrder)
	local conditionTypes = {
		groupState = L['Group State'],
		combatState = L['Combat State'],
		instanceType = L['Instance Type'],
		zoneType = L['Zone Type'],
		playerLevel = L['Player Level'],
		timeOfDay = L['Time of Day'],
		questItemNearby = L['Quest Item Nearby'],
	}

	local valueOptions = {}
	if condition.type == 'groupState' then
		valueOptions = { Solo = L['Solo'], Group = L['Group'], Raid = L['Raid'] }
	elseif condition.type == 'combatState' then
		valueOptions = { InCombat = L['In Combat'], OutOfCombat = L['Out of Combat'] }
	elseif condition.type == 'instanceType' then
		valueOptions = { Outdoor = L['Outdoor'], Dungeon = L['Dungeon'], Raid = L['Raid'], PvP = L['PvP'], Scenario = L['Scenario'] }
	elseif condition.type == 'zoneType' then
		valueOptions = { City = L['City'], Outdoor = L['Outdoor'], Instance = L['Instance'] }
	elseif condition.type == 'timeOfDay' then
		valueOptions = { Day = L['Day'], Night = L['Night'] }
	elseif condition.type == 'questItemNearby' then
		valueOptions = { ['true'] = L['Yes'], ['false'] = L['No'] }
	end

	local operators = { ['=='] = L['Equals'], ['!='] = L['Not Equals'], ['>'] = L['Greater Than'], ['<'] = L['Less Than'], ['>='] = L['Greater or Equal'], ['<='] = L['Less or Equal'] }

	return {
		type = 'group',
		name = L['Condition'] .. ' ' .. index,
		inline = true,
		order = baseOrder,
		args = {
			conditionType = {
				type = 'select',
				name = L['Type'],
				desc = L['Type of condition to check'],
				values = conditionTypes,
				get = function()
					return condition.type
				end,
				set = function(_, value)
					condition.type = value
					-- Reset value when type changes
					if value == 'groupState' then
						condition.value = 'Solo'
					elseif value == 'combatState' then
						condition.value = 'InCombat'
					elseif value == 'instanceType' then
						condition.value = 'Outdoor'
					elseif value == 'zoneType' then
						condition.value = 'City'
					elseif value == 'playerLevel' then
						condition.value = 80
						condition.operator = '=='
					elseif value == 'timeOfDay' then
						condition.value = 'Day'
					elseif value == 'questItemNearby' then
						condition.value = 'true'
					end
					LibStub('AceConfigRegistry-3.0'):NotifyChange('SpartanUI')
				end,
				order = 1,
			},
			conditionValue = {
				type = condition.type == 'playerLevel' and 'range' or 'select',
				name = L['Value'],
				desc = L['Value to compare against'],
				values = condition.type ~= 'playerLevel' and valueOptions or nil,
				min = condition.type == 'playerLevel' and 1 or nil,
				max = condition.type == 'playerLevel' and 80 or nil,
				step = condition.type == 'playerLevel' and 1 or nil,
				get = function()
					return condition.value
				end,
				set = function(_, value)
					condition.value = value
					module:EvaluateRules('manual')
				end,
				order = 2,
			},
			conditionOperator = {
				type = 'select',
				name = L['Operator'],
				desc = L['Comparison operator'],
				values = operators,
				hidden = function()
					return condition.type ~= 'playerLevel'
				end,
				get = function()
					return condition.operator or '=='
				end,
				set = function(_, value)
					condition.operator = value
					module:EvaluateRules('manual')
				end,
				order = 3,
			},
			removeCondition = {
				type = 'execute',
				name = L['Remove'],
				desc = L['Remove this condition'],
				func = function()
					table.remove(rule.conditions, index)
					LibStub('AceConfigRegistry-3.0'):NotifyChange('SpartanUI')
				end,
				order = 4,
			},
		},
	}
end

function module:GetActionEditorOptions(rule, action, index, baseOrder)
	local actionTypes = {
		hide = L['Hide'],
		show = L['Show'],
		collapse = L['Collapse'],
		expand = L['Expand'],
	}

	local trackerSections = {}
	for _, section in ipairs(TRACKER_SECTIONS) do
		trackerSections[section] = L[section:gsub('^%l', string.upper)] or section
	end

	-- Get current targets as comma-separated string
	local currentTargets = table.concat(action.targets or {}, ', ')

	return {
		type = 'group',
		name = L['Action'] .. ' ' .. index,
		inline = true,
		order = baseOrder,
		args = {
			actionType = {
				type = 'select',
				name = L['Action'],
				desc = L['What to do with the target sections'],
				values = actionTypes,
				get = function()
					return action.type
				end,
				set = function(_, value)
					action.type = value
					module:EvaluateRules('manual')
				end,
				order = 1,
			},
			actionTargets = {
				type = 'input',
				name = L['Targets'],
				desc = L['Comma-separated list of sections (e.g., quest, achievement, bonus)'],
				multiline = false,
				get = function()
					return currentTargets
				end,
				set = function(_, value)
					local targets = {}
					for target in value:gmatch('[^,]+') do
						local trimmed = target:trim()
						if trimmed ~= '' then
							table.insert(targets, trimmed)
						end
					end
					action.targets = targets
					module:EvaluateRules('manual')
				end,
				order = 2,
			},
			removeAction = {
				type = 'execute',
				name = L['Remove'],
				desc = L['Remove this action'],
				func = function()
					table.remove(rule.actions, index)
					LibStub('AceConfigRegistry-3.0'):NotifyChange('SpartanUI')
				end,
				order = 3,
			},
		},
	}
end

function module:BuildOptions()
	local options = {
		type = 'group',
		name = L['Objective Tracker'],
		args = {
			description = {
				type = 'description',
				name = L['Configure the objective tracker with advanced options including keybinds, opacity, scaling, rules builder, and individual section control.'],
				order = 1,
			},
			rulesToggle = {
				type = 'group',
				name = L['Rules System'],
				inline = true,
				order = 1.5,
				args = {
					testRules = {
						type = 'execute',
						name = L['Test Rules'],
						desc = L['Manually test current rules against current conditions'],
						func = function()
							module:EvaluateRules('manual')
							print('SpartanUI: Rules evaluation complete - check chat for details')
						end,
						order = 1,
					},
				},
			},
			appearance = {
				type = 'group',
				name = L['Appearance'],
				inline = true,
				order = 3,
				args = {
					scale = {
						type = 'range',
						name = L['Scale'],
						desc = L['Adjust the scale of the objective tracker'],
						min = 0.5,
						max = 2.0,
						step = 0.05,
						get = function()
							return module.DB.scale
						end,
						set = function(_, value)
							module.DB.scale = value
							module:UpdateScale()
						end,
						order = 1,
					},
					opacity = {
						type = 'range',
						name = L['Opacity'],
						desc = L['Base opacity when mouseover is disabled'],
						min = 0.1,
						max = 1.0,
						step = 0.05,
						disabled = function()
							return module.DB.mouseoverOpacity
						end,
						get = function()
							return module.DB.opacity
						end,
						set = function(_, value)
							module.DB.opacity = value
							module:UpdateOpacity()
						end,
						order = 3,
					},
				},
			},
			mouseover = {
				type = 'group',
				name = L['Mouseover Effects'],
				inline = true,
				order = 4,
				args = {
					mouseoverOpacity = {
						type = 'toggle',
						name = L['Enable Mouseover'],
						desc = L['Enable opacity changes on mouseover'],
						get = function()
							return module.DB.mouseoverOpacity
						end,
						set = function(_, value)
							module.DB.mouseoverOpacity = value
							module:UpdateMouseoverSettings()
						end,
						order = 1,
					},
					mouseoverFadeIn = {
						type = 'range',
						name = L['Mouseover Opacity'],
						desc = L['Opacity when mouse is over the tracker'],
						min = 0.1,
						max = 1.0,
						step = 0.05,
						disabled = function()
							return not module.DB.mouseoverOpacity
						end,
						get = function()
							return module.DB.mouseoverFadeIn
						end,
						set = function(_, value)
							module.DB.mouseoverFadeIn = value
							module:UpdateMouseoverSettings()
						end,
						order = 2,
					},
					mouseoverFadeOut = {
						type = 'range',
						name = L['Normal Opacity'],
						desc = L['Opacity when mouse is not over the tracker'],
						min = 0.0,
						max = 1.0,
						step = 0.05,
						disabled = function()
							return not module.DB.mouseoverOpacity
						end,
						get = function()
							return module.DB.mouseoverFadeOut
						end,
						set = function(_, value)
							module.DB.mouseoverFadeOut = value
							module:UpdateMouseoverSettings()
						end,
						order = 3,
					},
					mouseoverDelay = {
						type = 'range',
						name = L['Fade Out Delay'],
						desc = L['Delay in seconds before fading out when mouse leaves the tracker'],
						min = 0.0,
						max = 2.0,
						step = 0.1,
						disabled = function()
							return not module.DB.mouseoverOpacity
						end,
						get = function()
							return module.DB.mouseoverDelay
						end,
						set = function(_, value)
							module.DB.mouseoverDelay = value
							module:UpdateMouseoverSettings()
						end,
						order = 4,
					},
				},
			},
			background = {
				type = 'group',
				name = L['Background'],
				inline = true,
				order = 5,
				args = {
					backgroundEnabled = {
						type = 'toggle',
						name = L['Show Background'],
						desc = L['Show a simple color background behind the objective tracker'],
						get = function()
							return module.DB.backgroundEnabled
						end,
						set = function(_, value)
							module.DB.backgroundEnabled = value
							module:UpdateBackground()
						end,
						order = 1,
					},
					backgroundColor = {
						type = 'color',
						name = L['Background Color'],
						desc = L['Color of the objective tracker background'],
						hasAlpha = true,
						disabled = function()
							return not module.DB.backgroundEnabled
						end,
						get = function()
							local color = module.DB.backgroundColor
							return color.r, color.g, color.b, color.a
						end,
						set = function(_, r, g, b, a)
							module.DB.backgroundColor = { r = r, g = g, b = b, a = a }
							module:UpdateBackground()
						end,
						order = 2,
					},
					spacer1 = {
						type = 'description',
						name = ' ',
						order = 3,
					},
				},
			},
			rulesBuilder = {
				type = 'group',
				name = L['Rules Builder'],
				inline = false,
				order = 6,
				args = module:GetRulesBuilderOptions(),
			},
			questButton = {
				type = 'group',
				name = L['Quest Button'],
				inline = true,
				order = 6.5,
				args = {
					enabled = {
						type = 'toggle',
						name = L['Enable Quest Button'],
						desc = L['Show a button for nearby quest items'],
						get = function()
							return module.DB.questButton.enabled
						end,
						set = function(_, value)
							module.DB.questButton.enabled = value
							if value then
								module:CreateQuestButton()
								module:UpdateQuestButton()
							elseif questButton then
								questButton:Hide()
							end
						end,
						order = 1,
					},
					scale = {
						type = 'range',
						name = L['Button Scale'],
						desc = L['Scale of the quest button'],
						min = 0.5,
						max = 2.0,
						step = 0.1,
						disabled = function()
							return not module.DB.questButton.enabled
						end,
						get = function()
							return module.DB.questButton.scale
						end,
						set = function(_, value)
							module.DB.questButton.scale = value
							module:PositionQuestButton()
						end,
						order = 2,
					},
					maxDistance = {
						type = 'range',
						name = L['Max Distance'],
						desc = L['Maximum distance to show quest items (yards)'],
						min = 10,
						max = 1000,
						step = 10,
						disabled = function()
							return not module.DB.questButton.enabled
						end,
						get = function()
							return module.DB.questButton.maxDistance
						end,
						set = function(_, value)
							module.DB.questButton.maxDistance = value
							module:UpdateQuestButton()
						end,
						order = 3,
					},
					zoneOnly = {
						type = 'toggle',
						name = L['Current Zone Only'],
						desc = L['Only show quest items for quests in the current zone'],
						disabled = function()
							return not module.DB.questButton.enabled
						end,
						get = function()
							return module.DB.questButton.zoneOnly
						end,
						set = function(_, value)
							module.DB.questButton.zoneOnly = value
							module:UpdateQuestButton()
						end,
						order = 4,
					},
					trackingOnly = {
						type = 'toggle',
						name = L['Tracked Quests Only'],
						desc = L['Only show quest items for tracked quests'],
						disabled = function()
							return not module.DB.questButton.enabled
						end,
						get = function()
							return module.DB.questButton.trackingOnly
						end,
						set = function(_, value)
							module.DB.questButton.trackingOnly = value
							module:UpdateQuestButton()
						end,
						order = 5,
					},
				},
			},
		},
	}

	SUI.Options:AddOptions(options, 'ObjectiveTracker')
end
