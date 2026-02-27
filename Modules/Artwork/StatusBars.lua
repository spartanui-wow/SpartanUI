local SUI, L = SUI, SUI.L
---@class SUI.Module.Artwork.StatusBars : SUI.Module
local module = SUI:NewModule('Artwork.StatusBars')
SUI.Artwork.StatusBars = module
module.bars = {}
local DB ---@type SUI.StatusBars.DB

local Enums = {
	Bars = {
		None = -1,
		Reputation = 1,
		Honor = 2,
		Artifact = 3,
		Experience = 4,
		Azerite = 5,
		HouseFavor = 6,
	},
	TextDisplayMode = {
		OnMouseOver = 0,
		Always = 1,
		Never = 2,
	},
}

local BarLabels = {
	[Enums.Bars.Azerite] = 'Azerite',
	[Enums.Bars.Reputation] = 'Reputation',
	[Enums.Bars.Honor] = 'Honor',
	[Enums.Bars.Artifact] = 'Artifact',
	[Enums.Bars.Experience] = 'Experience',
	[Enums.Bars.HouseFavor] = 'Housing',
}

-- Colors for Classic bars
local FACTION_BAR_COLORS = {
	[1] = { r = 1, g = 0.2, b = 0 },
	[2] = { r = 0.8, g = 0.3, b = 0 },
	[3] = { r = 0.8, g = 0.2, b = 0 },
	[4] = { r = 1, g = 0.8, b = 0 },
	[5] = { r = 0, g = 1, b = 0.1 },
	[6] = { r = 0, g = 1, b = 0.2 },
	[7] = { r = 0, g = 1, b = 0.3 },
	[8] = { r = 0, g = 0.6, b = 0.1 },
}
local COLORS = {
	Orange = { r = 1, g = 0.2, b = 0, a = 0.7 },
	Yellow = { r = 1, g = 0.8, b = 0, a = 0.7 },
	Green = { r = 0, g = 1, b = 0.1, a = 0.7 },
	Blue = { r = 0, g = 0.1, b = 1, a = 0.7 },
	Red = { r = 1, g = 0, b = 0.08, a = 0.7 },
	Light_Blue = { r = 0, g = 0.5, b = 1, a = 0.7 },
}

---@class SUI.StatusBars.DB
---@return table Database defaults based on WoW version
local function GetDBDefaults()
	if SUI.IsRetail then
		-- Retail database structure: named bars with priority system
		-- Only store user-configurable options that differ from StyleSettingsBase defaults
		return {
			AllowRep = true,
			PriorityDirection = 'ltr',
			BarPriorities = {
				[Enums.Bars.Experience] = 0,
				[Enums.Bars.Reputation] = 1,
				[Enums.Bars.Honor] = 3,
				[Enums.Bars.Azerite] = 4,
				[Enums.Bars.Artifact] = 5,
				[Enums.Bars.HouseFavor] = 6,
			},
			bars = {
				['**'] = {
					ToolTip = 'hover',
					text = Enums.TextDisplayMode.OnMouseOver,
					enabled = true,
					showTooltip = true,
				},
				Left = {
					ToolTip = 'hover',
					text = Enums.TextDisplayMode.OnMouseOver,
					enabled = true,
					showTooltip = true,
				},
				Right = {
					ToolTip = 'hover',
					text = Enums.TextDisplayMode.OnMouseOver,
					enabled = true,
					showTooltip = true,
				},
			},
		}
	else
		-- Classic database structure: indexed bars with display modes
		-- Only store user-configurable options that differ from StyleSettingsBase defaults
		return {
			[1] = {
				display = 'xp',
				text = true,
				ToolTip = 'hover',
				AutoColor = true,
				CustomColor = { r = 0, g = 0.1, b = 1, a = 0.7 },
				CustomColor2 = { r = 0, g = 0.5, b = 1, a = 0.7 },
			},
			[2] = {
				display = 'rep',
				text = true,
				ToolTip = 'hover',
				AutoColor = true,
				CustomColor = { r = 0, g = 1, b = 0.3, a = 0.7 },
				CustomColor2 = { r = 0, g = 0.5, b = 1, a = 0.7 },
			},
			default = { FontSize = 10 },
		}
	end
end

---@class SUI.Style.Settings.StatusBars.Storage
---@field Left SUI.Style.Settings.StatusBars
---@field Right SUI.Style.Settings.StatusBars

---@class SUI.Style.Settings.StatusBars
---@field bgTexture? string
local StyleSettingsBase = {
	size = { 400, 15 },
	alpha = 1,
	scale = 1,
	MaxWidth = 0,
	texCords = { 0, 1, 0, 1 },
	tooltip = {
		texture = 'Interface\\Addons\\SpartanUI\\Images\\status-tooltip',
		textureCoords = { 0.103515625, 0.8984375, 0.1796875, 0.8203125 },
		size = { 300, 100 },
		textAreaSize = { 200, 60 },
		statusBarAnchor = 'TOP',
	},
	Position = 'BOTTOMRIGHT,SUI_BottomAnchor,BOTTOM,-100,0',
	-- Classic-specific fields
	GlowImage = 'Interface\\AddOns\\SpartanUI\\Images\\status-glow',
	GlowHeight = 20,
	GlowPoint = { x = 0, y = 0 },
	Grow = 'LEFT',
	TooltipSize = { 300, 100 },
	bgTooltip = 'Interface\\Addons\\SpartanUI\\Images\\status-tooltip',
	texCordsTooltip = { 0.103515625, 0.8984375, 0.1796875, 0.8203125 },
	TooltipTextSize = { 230, 60 },
	TooltipTextWidth = 300,
	tooltipAnchor = 'TOP',
	TextColor = { 1, 1, 1, 1 },
	FontSize = 9,
}

local StyleSetting = {
	base = {
		Left = {
			Position = 'BOTTOMRIGHT,SUI_BottomAnchor,BOTTOM,-100,0',
			Grow = 'LEFT',
		},
		Right = {
			Position = 'BOTTOMLEFT,SUI_BottomAnchor,BOTTOM,100,0',
			Grow = 'RIGHT',
		},
	},
	skinsettings = {},
}
---Copy Base into left and right
for k, v in pairs(StyleSetting.base) do
	StyleSetting[k] = SUI:CopyData(v, StyleSettingsBase)
end

---@param ContainerKey string
---@return SUI.Style.Settings.StatusBars
local function GetStyleSettings(ContainerKey)
	-- Start with base defaults
	local settings = SUI:CopyData({}, StyleSetting[ContainerKey])

	-- Layer theme settings on top
	if StyleSetting.skinsettings[SUI:GetActiveStyle()] and StyleSetting.skinsettings[SUI:GetActiveStyle()][ContainerKey] then
		settings = SUI:CopyData(StyleSetting.skinsettings[SUI:GetActiveStyle()][ContainerKey], settings)
	end

	-- Layer user DB settings on top
	if DB then
		if SUI.IsRetail then
			-- Retail uses named containers
			if DB.bars and DB.bars[ContainerKey] then
				if DB.bars[ContainerKey].alpha then
					settings.alpha = DB.bars[ContainerKey].alpha
				end
				if DB.bars[ContainerKey].scale then
					settings.scale = DB.bars[ContainerKey].scale
				end
			end
		else
			-- Classic uses indexed containers
			local i = ContainerKey == 'Left' and 1 or 2
			if DB[i] then
				if DB[i].alpha then
					settings.alpha = DB[i].alpha
				end
				if DB[i].scale then
					settings.scale = DB[i].scale
				end
			end
		end
	end

	return settings
end

---@param style string
---@param settings SUI.Style.Settings.StatusBars.Storage
function module:RegisterStyle(style, settings)
	StyleSetting.skinsettings[style] = settings
end

function module:GetExperienceTooltipText()
	local currentXP = UnitXP('player')
	local maxXP = UnitXPMax('player')
	local restedXP = GetXPExhaustion() or 0
	local level = UnitLevel('player')
	local questLogXP = GetQuestLogRewardXP()

	GameTooltip:AddDoubleLine(L['Experience'], string.format('(Level %d)', level))
	GameTooltip:AddDoubleLine(L['Remaining:'], string.format('%s (%.2f%%)', SUI.Font:FormatNumber(maxXP - currentXP), ((maxXP - currentXP) / maxXP) * 100), 1, 1, 1)

	if currentXP then
		GameTooltip:AddLine(' ')
		GameTooltip:AddDoubleLine(L['XP'], string.format('%s / %s (%.2f%%)', SUI.Font:FormatNumber(currentXP), SUI.Font:FormatNumber(maxXP), (currentXP / maxXP) * 100), 1, 1, 1)
	end
	if questLogXP > 0 then
		GameTooltip:AddDoubleLine(L['Quest Log XP:'], string.format('Quest Log XP: %s (%.2f%%)', SUI.Font:FormatNumber(questLogXP), (questLogXP / maxXP) * 100), 1, 1, 1)
	end
	if restedXP > 0 then
		GameTooltip:AddDoubleLine(L['Rested:'], string.format('Rested: +%s (%.2f%%)', SUI.Font:FormatNumber(restedXP), (restedXP / maxXP) * 100), 1, 1, 1)
	end
end

function module:GetReputationTooltipText()
	local data
	if C_Reputation and C_Reputation.GetWatchedFactionData then
		data = C_Reputation.GetWatchedFactionData()
	else
		-- Classic fallback
		local name, standingID, barMin, barMax, barValue, factionID = GetWatchedFactionInfo()
		if name then
			data = {
				name = name,
				reaction = standingID,
				factionID = factionID,
				currentStanding = barValue,
				currentReactionThreshold = barMin,
				nextReactionThreshold = barMax,
			}
		end
	end
	if not data then
		return
	end

	GameTooltip:AddLine(data.name)
	GameTooltip:AddLine(' ')

	local friendshipInfo = C_GossipInfo and C_GossipInfo.GetFriendshipReputation and C_GossipInfo.GetFriendshipReputation(data.factionID)
	local isMajorFaction = C_Reputation and C_Reputation.IsMajorFaction and C_Reputation.IsMajorFaction(data.factionID)

	if friendshipInfo and friendshipInfo.friendshipFactionID > 0 then
		-- Friendship reputation
		GameTooltip:AddDoubleLine(STANDING .. ':', friendshipInfo.reaction, 1, 1, 1)
		if friendshipInfo.nextThreshold then
			local current = friendshipInfo.standing - (friendshipInfo.reactionThreshold or 0)
			local total = friendshipInfo.nextThreshold - (friendshipInfo.reactionThreshold or 0)
			GameTooltip:AddDoubleLine(REPUTATION .. ':', string.format('%d / %d (%d%%)', current, total, (current / total) * 100), 1, 1, 1)
		end
	elseif isMajorFaction and C_MajorFactions and C_MajorFactions.GetMajorFactionData then
		-- Major faction (Dragonflight renown system)
		local majorFactionData = C_MajorFactions.GetMajorFactionData(data.factionID)
		local renownLevel = majorFactionData.renownLevel
		local renownReputationEarned = majorFactionData.renownReputationEarned
		local renownLevelThreshold = majorFactionData.renownLevelThreshold

		GameTooltip:AddDoubleLine(RENOWN_LEVEL_LABEL, renownLevel, BLUE_FONT_COLOR.r, BLUE_FONT_COLOR.g, BLUE_FONT_COLOR.b)
		GameTooltip:AddDoubleLine(REPUTATION .. ':', string.format('%d / %d (%d%%)', renownReputationEarned, renownLevelThreshold, (renownReputationEarned / renownLevelThreshold) * 100), 1, 1, 1)
	else
		-- Standard reputation
		local standingText = _G['FACTION_STANDING_LABEL' .. data.reaction] or UNKNOWN
		GameTooltip:AddDoubleLine(STANDING .. ':', standingText, 1, 1, 1)

		if data.reaction < 8 then -- Not at max standing
			local current = data.currentStanding - data.currentReactionThreshold
			local total = data.nextReactionThreshold - data.currentReactionThreshold
			GameTooltip:AddDoubleLine(REPUTATION .. ':', string.format('%d / %d (%d%%)', current, total, (current / total) * 100), 1, 1, 1)
		end
	end

	-- Paragon reputation (if applicable, retail only)
	if C_Reputation and C_Reputation.IsFactionParagon and C_Reputation.IsFactionParagon(data.factionID) then
		local currentValue, threshold, _, hasRewardPending = C_Reputation.GetFactionParagonInfo(data.factionID)
		local current = currentValue % threshold
		GameTooltip:AddDoubleLine(L['Paragon'] .. ':', string.format('%d / %d (%d%%)', current, threshold, (current / threshold) * 100), 1, 1, 1)
		if hasRewardPending then
			GameTooltip:AddLine(L['Reward Available'], 0, 1, 0)
		end
	end
end

function module:GetHonorTooltipText()
	local honorLevel = UnitHonorLevel('player')
	local currentHonor = UnitHonor('player')
	local maxHonor = UnitHonorMax('player')

	if currentHonor == 0 and maxHonor == 0 then
		return -- If something odd happened and both values are 0 don't show anything
	end

	GameTooltip:AddLine(HONOR)
	GameTooltip:AddLine(' ')

	-- Current Honor Level
	GameTooltip:AddDoubleLine(
		HONOR_LEVEL_LABEL:format(honorLevel),
		string.format('%s / %s (%d%%)', SUI.Font:FormatNumber(currentHonor), SUI.Font:FormatNumber(maxHonor), ((currentHonor / maxHonor) * 100)),
		NORMAL_FONT_COLOR.r,
		NORMAL_FONT_COLOR.g,
		NORMAL_FONT_COLOR.b,
		1,
		1,
		1
	)

	-- Next Honor Level Reward (retail only)
	if C_PvP and C_PvP.GetNextHonorLevelForReward then
		local nextHonorLevelForReward = C_PvP.GetNextHonorLevelForReward(honorLevel)
		if nextHonorLevelForReward then
			local nextRewardInfo = C_PvP.GetHonorRewardInfo and C_PvP.GetHonorRewardInfo(nextHonorLevelForReward)
			if nextRewardInfo then
				GameTooltip:AddLine(' ')
				GameTooltip:AddDoubleLine(L['Next Honor Reward'], string.format(L['Level %d'], nextHonorLevelForReward), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1, 1, 1)
				local rewardItemID = C_AchievementInfo and C_AchievementInfo.GetRewardItemID and C_AchievementInfo.GetRewardItemID(nextRewardInfo.achievementRewardedID)
				if rewardItemID and C_Item and C_Item.GetItemNameByID then
					GameTooltip:AddDoubleLine('|---', C_Item.GetItemNameByID(rewardItemID), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1, 1, 1)
				end
			end
		end
	end

	local brackets = {
		[1] = L['2v2'],
		[2] = L['3v3'],
		[3] = L['Solo Shuffle'],
		[4] = L['Rated Battleground'],
	}
	local hasRating = false
	local function AddPVPRatings()
		-- Arena Scores
		GameTooltip:AddLine(' ')
		GameTooltip:AddLine(L['PvP Ratings:'], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
	end
	for i, bracketName in ipairs(brackets) do
		local rating, seasonBest = GetPersonalRatedInfo(i)
		if rating > 0 then
			if not hasRating then
				AddPVPRatings()
				hasRating = true
			end
			GameTooltip:AddDoubleLine(bracketName, string.format('%d (%d)', rating, seasonBest), 1, 1, 1, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
		end
	end
end

function module:GetHouseFavorTooltipText(bar)
	-- Check if C_Housing API is available
	if not C_Housing then
		return
	end

	-- Get the tracked house GUID
	local trackedHouseGUID = C_Housing.GetTrackedHouseGuid()
	if not trackedHouseGUID then
		return
	end

	-- Try to get house level from the bar's stored data first
	local houseLevel, houseFavor, houseFavorNeeded

	if bar and bar.houseLevelFavor then
		-- Use data stored on the bar (similar to Blizzard's implementation)
		houseLevel = bar.houseLevelFavor.houseLevel or 1
		local currentFavor = bar.houseLevelFavor.houseFavor or 0
		local minBarFavor = C_Housing.GetHouseLevelFavorForLevel(houseLevel) or 0
		local maxBarFavor = C_Housing.GetHouseLevelFavorForLevel(houseLevel + 1) or 1
		houseFavor = currentFavor - minBarFavor
		houseFavorNeeded = maxBarFavor - minBarFavor
	else
		-- Fallback: try to get from bar values directly
		if bar and bar.StatusBar then
			local current = bar.StatusBar:GetValue()
			local min, max = bar.StatusBar:GetMinMaxValues()
			houseLevel = bar.level or 1
			houseFavor = current - min
			houseFavorNeeded = max - min
		else
			return
		end
	end

	if not houseLevel or not houseFavorNeeded then
		return
	end

	-- Use Blizzard's tooltip format
	if HOUSING_DASHBOARD_HOUSE_LEVEL then
		GameTooltip_AddNormalLine(GameTooltip, string.format(HOUSING_DASHBOARD_HOUSE_LEVEL, houseLevel))
	else
		GameTooltip_AddNormalLine(GameTooltip, string.format('House Level %d', houseLevel))
	end

	if HOUSING_DASHBOARD_NEIGHBORHOOD_FAVOR then
		GameTooltip_AddHighlightLine(GameTooltip, string.format(HOUSING_DASHBOARD_NEIGHBORHOOD_FAVOR, houseFavor, houseFavorNeeded))
	else
		GameTooltip_AddHighlightLine(GameTooltip, string.format('%d / %d', houseFavor, houseFavorNeeded))
	end

	if HOUSING_DASHBOARD_NEIGHBORHOOD_FAVOR_TOOLTIP then
		GameTooltip_AddHighlightLine(GameTooltip, HOUSING_DASHBOARD_NEIGHBORHOOD_FAVOR_TOOLTIP)
	end
end

function module:OnInitialize()
	local defaults = GetDBDefaults()
	module.Database = SUI.SpartanUIDB:RegisterNamespace('StatusBars', { profile = defaults })
	DB = module.Database.profile

	-- Register for sequential profile refresh
	SUI.DBM:RegisterSequentialProfileRefresh(module, 'UpdateBars')

	-- Migrate old settings
	if SUI.DB.StatusBars then
		-- Check if old bar was set to honor
		for i = 1, 2 do
			if SUI.DB.StatusBars and SUI.DB.StatusBars[i] and SUI.DB.StatusBars[i].display == 'honor' then
				SetCVar('showHonorAsExperience', 1)
			end
		end
		-- Remove old settings
		SUI.DB.StatusBars = nil
	end

	-- Database migration: detect version mismatch
	if not SUI.IsRetail and DB.BarPriorities and not DB[1] then
		-- User has Retail structure on Classic - reset to defaults
		module.Database:ResetProfile()
		if LibAT and LibAT.Logger then
			local logger = LibAT.Logger.RegisterAddon('SpartanUI')
			logger.warning('StatusBar settings reset due to WoW version change')
		end
	elseif SUI.IsRetail and DB[1] and not DB.BarPriorities then
		-- User has Classic structure on Retail - reset to defaults
		module.Database:ResetProfile()
		if LibAT and LibAT.Logger then
			local logger = LibAT.Logger.RegisterAddon('SpartanUI')
			logger.warning('StatusBar settings reset due to WoW version change')
		end
	end
end

function module:OnEnable()
	-- NO EARLY RETURN - let factory dispatch to correct version
	module:factory()
	module:BuildOptions()
end

function module:factory()
	if SUI.IsRetail then
		self:factory_Retail()
	else
		self:factory_Classic()
	end
end

----------------------------------------------------------------------------------------------------
-- RETAIL IMPLEMENTATION
----------------------------------------------------------------------------------------------------

function module:factory_Retail()
	local barManager = self:CreateBarManager_Retail()
	self:CreateBarContainers_Retail(barManager)
	if barManager.OnLoad then
		barManager:OnLoad()
	end
end

function module:UpdateBars()
	-- Refresh local DB reference (may have changed after profile switch)
	DB = module.Database.profile

	local barManager = _G['SUI_StatusBar_Manager']
	if barManager then
		-- Update the shown bars
		barManager:UpdateBarsShown()

		-- Update text visibility for both containers
		self:UpdateBarTextVisibility('Left')
		self:UpdateBarTextVisibility('Right')

		-- Update container alphas, scale, and visibility
		for _, key in ipairs({ 'Left', 'Right' }) do
			local barContainer = module.bars[key]
			if barContainer then
				-- Refresh the merged style settings
				local mergedSettings = GetStyleSettings(key)
				barContainer.settings = mergedSettings

				if DB.bars[key].enabled then
					-- Check if this container actually has a bar to show
					local hasActiveBar = false
					for _, bar in pairs(barContainer.bars) do
						if bar:IsShown() and bar.barIndex and bar.barIndex ~= Enums.Bars.None then
							hasActiveBar = true
							break
						end
					end

					if hasActiveBar then
						barContainer:SetAlpha(mergedSettings.alpha or 1)
						barContainer:SetScale(mergedSettings.scale or 1)
						barContainer:Show()
					else
						barContainer:Hide()
					end
				else
					barContainer:Hide()
				end
			end
		end

		-- Refresh the options display
		self:RefreshBarPriorityOptions()
	end
end

function module:UpdateBarTextVisibility(containerKey)
	local barContainer = module.bars[containerKey]
	if not barContainer then
		return
	end

	if not DB or not DB.bars or not DB.bars[containerKey] then
		return
	end

	local textMode = DB.bars[containerKey].text

	for _, bar in pairs(barContainer.bars) do
		if textMode == Enums.TextDisplayMode.Always then
			bar.OverlayFrame.Text:Show()
		else -- OnMouseOver
			bar.OverlayFrame.Text:Hide()
		end

		-- Update the bar's UpdateTextVisibility function
		bar.UpdateTextVisibility = function(self)
			local blizzMode = self:ShouldBarTextBeDisplayed()
			self.OverlayFrame.Text:SetShown(textMode == Enums.TextDisplayMode.Always and blizzMode)
		end
	end
end

function module:RefreshBarPriorityOptions()
	local options = SUI.opt.args['Artwork'].args['StatusBars'].args.BarPriorities.args
	for barIndex, priority in pairs(DB.BarPriorities) do
		local optionKey = BarLabels[barIndex]
		if options[optionKey] then
			options[optionKey].order = priority
		end
	end
end

function module:CreateBarManager_Retail()
	local barManager = CreateFrame('Frame', 'SUI_StatusBar_Manager', SpartanUI)
	for k, v in pairs(StatusTrackingManagerMixin) do
		barManager[k] = v
	end

	barManager.UpdateBarsShown = function(self)
		-- Guard: ensure DB and DB.bars exist
		if not DB or not DB.bars then
			return
		end

		local function onFinishedAnimating(barContainer)
			barContainer:UnsubscribeFromOnFinishedAnimating(self)
			self:UpdateBarsShown()
		end

		-- If any bar is animating then wait for that animation to end before updating shown bars
		for i, barContainer in ipairs(self.barContainers) do
			if barContainer:IsAnimating() then
				barContainer:SubscribeToOnFinishedAnimating(self, onFinishedAnimating)
				return
			end
		end

		-- Check if containers are enabled and hide disabled ones
		for i, barContainer in ipairs(self.barContainers) do
			local containerKey = i == 1 and 'Left' or 'Right'
			if DB.bars[containerKey] and not DB.bars[containerKey].enabled then
				barContainer:SetShownBar(Enums.Bars.None)
			end
		end

		-- Determine what bars should be shown
		local newBarIndicesToShow = {}
		for _, barIndex in pairs(Enums.Bars) do
			if (barIndex == Enums.Bars.Reputation and DB.AllowRep and self:CanShowBar(barIndex)) or (barIndex ~= Enums.Bars.Reputation and self:CanShowBar(barIndex)) then
				table.insert(newBarIndicesToShow, barIndex)
			end
		end

		-- Sort based on priority
		table.sort(newBarIndicesToShow, function(left, right)
			return self:GetBarPriority(left) < self:GetBarPriority(right)
		end)

		-- Filter out containers that are disabled
		local enabledContainers = {}
		for i, barContainer in ipairs(self.barContainers) do
			local containerKey = i == 1 and 'Left' or 'Right'
			if DB.bars[containerKey] and DB.bars[containerKey].enabled then
				table.insert(enabledContainers, { container = barContainer, index = i })
			end
		end

		-- We can only show as many bars as we have enabled containers for
		while #newBarIndicesToShow > #enabledContainers do
			table.remove(newBarIndicesToShow)
		end

		-- Assign the bar indices to the enabled bar containers
		for i = 1, #self.barContainers do
			local barContainer = self.barContainers[i]
			local containerKey = i == 1 and 'Left' or 'Right'
			local newBarIndex = Enums.Bars.None

			-- Only assign bars to enabled containers
			if DB.bars[containerKey] and DB.bars[containerKey].enabled then
				local enabledIndex = 0
				for j = 1, i do
					local checkKey = j == 1 and 'Left' or 'Right'
					if DB.bars[checkKey] and DB.bars[checkKey].enabled then
						enabledIndex = enabledIndex + 1
					end
				end

				if #newBarIndicesToShow == 1 then
					-- Special case for single bar - show on first enabled container
					if enabledIndex == 1 then
						newBarIndex = newBarIndicesToShow[1]
					end
				else
					if DB.PriorityDirection == 'ltr' then
						newBarIndex = newBarIndicesToShow[enabledIndex] or Enums.Bars.None
					else
						newBarIndex = newBarIndicesToShow[#newBarIndicesToShow - enabledIndex + 1] or Enums.Bars.None
					end
				end
			end

			barContainer:SetShownBar(newBarIndex)
		end

		self.shownBarIndices = newBarIndicesToShow
	end

	barManager:SetScript('OnLoad', barManager.OnLoad)
	barManager:SetScript('OnEvent', barManager.OnEvent)

	barManager.GetBarPriority = function(self, barIndex)
		if not DB.BarPriorities then
			return 0
		end -- Sometimes we get called before Initilize has been called. This is a safe guard.

		return DB.BarPriorities[barIndex] or 0
	end

	return barManager
end

function module:CreateBarContainers_Retail(barManager)
	for i, key in ipairs({ 'Left', 'Right' }) do
		local barContainer = self:CreateBarContainer_Retail(barManager, key, i)
		self:SetupBarContainerBehavior(barContainer, i)
		module.bars[key] = barContainer
	end
end

function module:CreateBarContainer_Retail(barManager, key, index)
	local barStyle = GetStyleSettings(key)
	local barContainer = CreateFrame('Frame', 'SUI_StatusBar_' .. key, barManager, 'StatusTrackingBarContainerTemplate')
	barContainer.barStyle = barStyle

	barContainer:SetSize(unpack(barStyle.size))
	barContainer:SetFrameStrata('LOW')
	barContainer:SetFrameLevel(20)

	-- Hide with SpartanUI
	SpartanUI:HookScript('OnHide', function()
		barContainer:Hide()
	end)
	SpartanUI:HookScript('OnShow', function()
		barContainer:Show()
	end)

	self:SetupBarContainerVisuals(barContainer, barStyle)
	self:SetupBarContainerPosition(barContainer, barStyle, index)
	self:SetupBarContainerMouseEvents(barContainer, index)

	-- Create MoveIt mover for this statusbar
	if SUI.MoveIt then
		-- Set dirtyWidth/dirtyHeight to match the visual statusbar size (with padding)
		barContainer.dirtyWidth = barStyle.size[1] - 30
		barContainer.dirtyHeight = barStyle.size[2] - 5
		SUI.MoveIt:CreateMover(barContainer, 'StatusBar_' .. key, key .. ' Status Bar', nil, 'StatusBars')
	end

	return barContainer
end

function module:SetupBarContainerVisuals(barContainer, barStyle)
	barContainer.BarFrameTexture:Hide()

	-- Create a low-level background frame so the bg draws behind the status bars
	if not barContainer.bgFrame then
		barContainer.bgFrame = CreateFrame('Frame', nil, barContainer)
		barContainer.bgFrame:SetAllPoints(barContainer)
		barContainer.bgFrame:SetFrameLevel(barContainer:GetFrameLevel() - 10)
	end

	-- Create background texture on the low-level frame
	barContainer.bg = barContainer.bgFrame:CreateTexture(nil, 'BACKGROUND')
	if barStyle.bgColor then
		barContainer.bg:SetColorTexture(unpack(barStyle.bgColor))
		barContainer.bg:SetPoint('TOPLEFT', barContainer.bgFrame, 'TOPLEFT', 12, -2.5)
		barContainer.bg:SetPoint('BOTTOMRIGHT', barContainer.bgFrame, 'BOTTOMRIGHT', -12, 2)
		barContainer.bg:Show()
	elseif barStyle.bgTexture then
		barContainer.bg:SetTexture(barStyle.bgTexture)
		barContainer.bg:SetAllPoints(barContainer.bgFrame)
		barContainer.bg:SetTexCoord(unpack(barStyle.texCords))
		barContainer.bg:Show()
	else
		barContainer.bg:SetTexture('')
		barContainer.bg:SetAllPoints(barContainer.bgFrame)
		barContainer.bg:SetTexCoord(unpack(barStyle.texCords))
		barContainer.bg:Hide()
	end

	-- Create overlay (not needed when using solid bgColor)
	barContainer.overlay = barContainer:CreateTexture(nil, 'OVERLAY')
	if not barStyle.bgColor and barStyle.bgTexture then
		barContainer.overlay:SetTexture(barStyle.bgTexture)
		barContainer.overlay:SetAllPoints(barContainer.bg)
		barContainer.overlay:SetTexCoord(unpack(barStyle.texCords))
		barContainer.overlay:Show()
	else
		barContainer.overlay:SetTexture('')
		barContainer.overlay:SetAllPoints(barContainer.bg)
		barContainer.overlay:Hide()
	end

	-- Apply atlas border if configured
	self:ApplyAtlasBorder(barContainer, barStyle)

	barContainer.settings = barStyle
end

---Apply a 3-part atlas border (left cap, tiling center, right cap) to a bar container.
---@param barContainer Frame
---@param barStyle table Style settings with optional atlasBorder field
function module:ApplyAtlasBorder(barContainer, barStyle)
	local ab = barStyle.atlasBorder
	if not ab then
		-- Hide existing atlas border textures if switching away from a theme that had them
		if barContainer.atlasBorderLeft then
			barContainer.atlasBorderLeft:Hide()
		end
		if barContainer.atlasBorderCenter then
			barContainer.atlasBorderCenter:Hide()
		end
		if barContainer.atlasBorderRight then
			barContainer.atlasBorderRight:Hide()
		end
		return
	end

	-- Left cap
	if not barContainer.atlasBorderLeft then
		barContainer.atlasBorderLeft = barContainer:CreateTexture(nil, 'OVERLAY', nil, 2)
	end
	local left = barContainer.atlasBorderLeft
	left:SetAtlas(ab.left)
	left:ClearAllPoints()
	left:SetPoint('LEFT', barContainer, 'LEFT', ab.leftOffset or 0, 0)
	left:SetSize(ab.capWidth or 16, ab.height or barStyle.size[2])
	left:Show()

	-- Right cap
	if not barContainer.atlasBorderRight then
		barContainer.atlasBorderRight = barContainer:CreateTexture(nil, 'OVERLAY', nil, 2)
	end
	local right = barContainer.atlasBorderRight
	right:SetAtlas(ab.right)
	right:ClearAllPoints()
	right:SetPoint('RIGHT', barContainer, 'RIGHT', ab.rightOffset or 0, 0)
	right:SetSize(ab.capWidth or 16, ab.height or barStyle.size[2])
	right:Show()

	-- Tiling center
	if not barContainer.atlasBorderCenter then
		barContainer.atlasBorderCenter = barContainer:CreateTexture(nil, 'OVERLAY', nil, 1)
	end
	local center = barContainer.atlasBorderCenter
	center:SetAtlas(ab.center, true)
	center:SetHorizTile(true)
	center:ClearAllPoints()
	center:SetPoint('LEFT', left, 'RIGHT', 0, 0)
	center:SetPoint('RIGHT', right, 'LEFT', 0, 0)
	center:SetHeight(ab.height or barStyle.size[2])
	center:Show()
end

function module:SetupBarContainerPosition(barContainer, barStyle, index)
	local point, anchor, secondaryPoint, x, y = strsplit(',', barStyle.Position)
	barContainer:ClearAllPoints()
	barContainer:SetPoint(point, anchor, secondaryPoint, x, y)
	local containerKey = index == 1 and 'Left' or 'Right'

	-- Set initial visibility, alpha, and scale based on enabled state
	-- Note: We start hidden and let UpdateBars() show containers that have content
	-- barStyle already contains merged settings (Defaults > Theme > User)
	if DB.bars[containerKey].enabled then
		barContainer:SetAlpha(barStyle.alpha or 1)
		barContainer:SetScale(barStyle.scale or 1)
	end
	barContainer:Hide() -- Start hidden, UpdateBars will show if there's content
end

function module:HandleBarOnEnter(bar, containerKey)
	-- Update HouseFavor text if needed
	if bar.barIndex == Enums.Bars.HouseFavor then
		-- Get current bar values
		local current = bar.StatusBar:GetValue()
		local min, max = bar.StatusBar:GetMinMaxValues()
		if max > min then
			local currentProgress = current - min
			local totalLevelXP = max - min
			local houseLevel = bar.level or (bar.houseLevelFavor and bar.houseLevelFavor.houseLevel) or 1
			-- Format: Level # X/Y
			bar.OverlayFrame.Text:SetFormattedText('Level %d %d/%d', houseLevel, currentProgress, totalLevelXP)
		end
	end

	-- Show text if configured for mouseover
	if DB.bars[containerKey].text == Enums.TextDisplayMode.OnMouseOver then
		bar.OverlayFrame.Text:Show()
	end

	-- Show custom tooltip using the bar's data (if enabled)
	if DB.bars[containerKey].showTooltip then
		GameTooltip:ClearLines()
		GameTooltip:SetOwner(bar, 'ANCHOR_CURSOR')
		if bar.barIndex == Enums.Bars.Experience then
			module:GetExperienceTooltipText()
		elseif bar.barIndex == Enums.Bars.Reputation then
			module:GetReputationTooltipText()
		elseif bar.barIndex == Enums.Bars.Honor then
			module:GetHonorTooltipText()
		elseif bar.barIndex == Enums.Bars.HouseFavor then
			module:GetHouseFavorTooltipText(bar)
		end
		GameTooltip:Show()
	end
end

function module:HandleBarOnLeave(bar, containerKey)
	-- Hide text if configured for mouseover
	if DB.bars[containerKey].text == Enums.TextDisplayMode.OnMouseOver then
		bar.OverlayFrame.Text:Hide()
	end
	-- Hide tooltip (if it was enabled)
	if DB.bars[containerKey].showTooltip then
		GameTooltip:Hide()
	end
end

function module:SetupBarContainerMouseEvents(barContainer, index)
	-- Add mouse events to the container itself to handle cases where mover blocks individual bar events
	barContainer:EnableMouse(true)
	local containerKey = index == 1 and 'Left' or 'Right'

	barContainer:SetScript('OnEnter', function(self)
		-- Find the active bar in this container and trigger its tooltip
		for _, bar in pairs(self.bars) do
			if bar:IsShown() and bar.barIndex and bar.barIndex ~= Enums.Bars.None then
				module:HandleBarOnEnter(bar, containerKey)
				break -- Only handle the first active bar
			end
		end
	end)

	barContainer:SetScript('OnLeave', function(self)
		-- Hide text and tooltip for all bars in this container
		for _, bar in pairs(self.bars) do
			if bar:IsShown() and bar.barIndex and bar.barIndex ~= Enums.Bars.None then
				module:HandleBarOnLeave(bar, containerKey)
			end
		end
	end)
end

function module:SetupBarContainerBehavior(barContainer, index)
	local width, height = unpack(barContainer.settings.size)
	for _, bar in pairs(barContainer.bars) do
		self:SetupBar(bar, barContainer, width, height, index)
	end

	SpartanUI:HookScript('OnHide', function()
		barContainer:Hide()
	end)
	SpartanUI:HookScript('OnShow', function()
		barContainer:Show()
	end)
end

function module:SetupBar(bar, barContainer, width, height, index)
	bar:SetSize(width - 30, height - 5)
	bar.StatusBar:SetSize(width - 30, height - 5)
	bar:ClearAllPoints()
	local barOffsetX = barContainer.settings and barContainer.settings.barOffsetX or 0
	bar:SetPoint('BOTTOM', barContainer, 'BOTTOM', barOffsetX, 0)
	bar:SetUsingParentLevel(false)
	bar:SetFrameLevel(barContainer:GetFrameLevel() - 5)

	-- Ensure mouse events work
	bar:EnableMouse(true)

	self:SetupBarText(bar, barContainer.settings, index)

	bar:HookScript('OnEnter', function(self)
		local containerKey = index == 1 and 'Left' or 'Right'
		module:HandleBarOnEnter(self, containerKey)
	end)

	bar:HookScript('OnLeave', function(self)
		local containerKey = index == 1 and 'Left' or 'Right'
		module:HandleBarOnLeave(self, containerKey)
	end)
end

function module:SetActiveStyle(style)
	-- Dispatch to the correct version
	if not SUI.IsRetail then
		return self:SetActiveStyle_Classic(style)
	end

	-- Update the style for each container (Left and Right)
	for _, key in ipairs({ 'Left', 'Right' }) do
		local barContainer = module.bars[key]
		if barContainer then
			local newStyle = GetStyleSettings(key)

			-- Update size
			barContainer:SetSize(unpack(newStyle.size))

			-- Update background
			if newStyle.bgColor then
				barContainer.bg:ClearAllPoints()
				barContainer.bg:SetColorTexture(unpack(newStyle.bgColor))
				barContainer.bg:SetPoint('TOPLEFT', barContainer.bgFrame, 'TOPLEFT', 5, -2)
				barContainer.bg:SetPoint('BOTTOMRIGHT', barContainer.bgFrame, 'BOTTOMRIGHT', -5, 2)
				barContainer.bg:Show()
				barContainer.overlay:SetTexture('')
				barContainer.overlay:Hide()
			elseif newStyle.bgTexture then
				barContainer.bg:ClearAllPoints()
				barContainer.bg:SetTexture(newStyle.bgTexture)
				barContainer.bg:SetAllPoints(barContainer.bgFrame)
				barContainer.bg:Show()
				if newStyle.texCords then
					barContainer.bg:SetTexCoord(unpack(newStyle.texCords))
				else
					barContainer.bg:SetTexCoord(0, 1, 0, 1)
				end
				barContainer.overlay:SetTexture(newStyle.bgTexture)
				barContainer.overlay:Show()
				if newStyle.texCords then
					barContainer.overlay:SetTexCoord(unpack(newStyle.texCords))
				else
					barContainer.overlay:SetTexCoord(0, 1, 0, 1)
				end
			else
				barContainer.bg:SetTexture('')
				barContainer.bg:Hide()
				barContainer.overlay:SetTexture('')
				barContainer.overlay:Hide()
			end

			-- Update position
			local point, anchor, secondaryPoint, x, y = strsplit(',', newStyle.Position)
			barContainer:ClearAllPoints()
			barContainer:SetPoint(point, anchor, secondaryPoint, x, y)

			-- Update individual bars (Retail only - barContainer.bars exists from template)
			if barContainer.bars then
				for _, bar in pairs(barContainer.bars) do
					bar:SetSize(newStyle.size[1] - 30, newStyle.size[2] - 5)
					bar.StatusBar:SetSize(newStyle.size[1] - 30, newStyle.size[2] - 5)

					-- Update text if needed
					self:SetupBarText(bar, newStyle, key == 'Left' and 1 or 2)
				end
			end

			-- Update atlas border
			self:ApplyAtlasBorder(barContainer, newStyle)

			-- Store the new style settings
			barContainer.settings = newStyle
		end
	end

	-- Refresh the bars
	self:UpdateBars()
end

function module:SetupBarText(bar, StyleSetting, index)
	local containerKey = index == 1 and 'Left' or 'Right'
	local textMode = DB.bars[containerKey].text
	SUI.Font:Format(bar.OverlayFrame.Text, StyleSetting.Font or 10, 'StatusBars')
	bar.OverlayFrame.Text:SetShown(textMode == Enums.TextDisplayMode.Always)

	-- Update the bar's UpdateTextVisibility function
	bar.UpdateTextVisibility = function(self)
		local blizzMode = self:ShouldBarTextBeDisplayed()
		self.OverlayFrame.Text:SetShown(textMode == Enums.TextDisplayMode.Always and blizzMode)
	end
end

----------------------------------------------------------------------------------------------------
-- CLASSIC IMPLEMENTATION
----------------------------------------------------------------------------------------------------

local function SetBarColor_Classic(statusbar, side)
	local display = DB[side].display
	local color1 = DB[side].CustomColor
	local color2 = DB[side].CustomColor2
	local r, g, b, a

	if DB[side].AutoColor then
		if display == 'xp' then
			color1 = COLORS.Blue
			color2 = COLORS.Light_Blue
		elseif display == 'az' then
			color1 = COLORS.Orange
		elseif display == 'honor' then
			color1 = COLORS.Red
		elseif display == 'rep' then
			local standingID
			if GetWatchedFactionInfo then
				standingID = select(2, GetWatchedFactionInfo())
			elseif C_Reputation and C_Reputation.GetWatchedFactionData then
				local data = C_Reputation.GetWatchedFactionData()
				standingID = data and data.reaction
			end
			color1 = FACTION_BAR_COLORS[standingID] or FACTION_BAR_COLORS[7]
		end
	end
	r, g, b, a = color1.r, color1.g, color1.b, color1.a

	statusbar.Fill:SetVertexColor(r, g, b, a)
	statusbar.FillGlow:SetVertexColor(r, g, b, a)
	if display == 'xp' then
		r, g, b, a = color2.r, color2.g, color2.b, color2.a
		statusbar.Lead:SetVertexColor(r, g, b, a)
		statusbar.LeadGlow:SetVertexColor(r, g, b, a)
	end
end

local function updateText_Classic(statusbar)
	-- Reset graphics to avoid issues
	statusbar.Fill:SetWidth(0.1)
	statusbar.Lead:SetWidth(0.1)
	-- Reset Text
	statusbar.Text:SetText('')

	local side = statusbar.i
	local valFill, valMax, valPercent
	local remaining = ''

	if (DB[side].display == 'xp') and UnitLevel('player') <= GetMaxPlayerLevel() then
		local rested, now, goal = GetXPExhaustion() or 0, UnitXP('player'), UnitXPMax('player')
		if now ~= 0 then
			rested = (rested / goal) * statusbar:GetWidth()

			if
				(rested + (now / goal) * (statusbar:GetWidth() - (statusbar.settings.MaxWidth - math.abs(statusbar.settings.GlowPoint.x))))
				> (statusbar:GetWidth() - (statusbar.settings.MaxWidth - math.abs(statusbar.settings.GlowPoint.x)))
			then
				rested = (statusbar:GetWidth() - (statusbar.settings.MaxWidth - math.abs(statusbar.settings.GlowPoint.x)))
					- (now / goal) * (statusbar:GetWidth() - (statusbar.settings.MaxWidth - math.abs(statusbar.settings.GlowPoint.x)))
			end

			if rested == 0 then
				rested = 0.001
			end
			statusbar.Lead:SetWidth(rested)
		end
		valFill = now
		valMax = goal
		remaining = SUI.Font:comma_value(goal - now)
		valPercent = (UnitXP('player') / UnitXPMax('player') * 100)
	elseif DB[side].display == 'rep' then
		local name, low, high, current, factionID
		if GetWatchedFactionInfo then
			name, _, low, high, current, factionID = GetWatchedFactionInfo()
		elseif C_Reputation and C_Reputation.GetWatchedFactionData then
			local data = C_Reputation.GetWatchedFactionData()
			if data then
				name = data.name
				factionID = data.factionID
				current = data.currentStanding
				low = data.currentReactionThreshold
				high = data.nextReactionThreshold
			end
		end
		if SUI.IsRetail and C_Reputation and C_Reputation.GetFactionParagonInfo and factionID then
			local currentValue, threshold, _, _, _ = C_Reputation.GetFactionParagonInfo(factionID)
			if currentValue ~= nil then
				current = currentValue % threshold
				low = 0
				high = threshold
			end
		end
		local repLevelLow = current and (current - low) or 0
		local repLevelHigh = high and (high - low) or 0

		if repLevelHigh == 0 and name then
			valFill = 42000
			valMax = 42000
			valPercent = 100
		elseif name then
			valFill = repLevelLow
			valMax = repLevelHigh
			valPercent = (repLevelLow / repLevelHigh) * 100
		end
	elseif DB[side].display == 'az' then
		if C_AzeriteItem and C_AzeriteItem.HasActiveAzeriteItem and C_AzeriteItem.HasActiveAzeriteItem() then
			local azeriteItemLocation = C_AzeriteItem.FindActiveAzeriteItem()
			if not azeriteItemLocation then
				return
			end
			local xp, totalLevelXP = C_AzeriteItem.GetAzeriteItemXPInfo(azeriteItemLocation)
			valMax = totalLevelXP - xp
			local ratio = (xp / totalLevelXP)
			valFill = xp
			valPercent = ratio * 100
		end
	elseif DB[side].display == 'honor' then
		valFill = UnitHonor('player')
		valMax = UnitHonorMax('player')
		valPercent = ((valFill / valMax) * 100)
	end

	if type(valPercent) == 'number' then
		if valPercent ~= 0 and valPercent then
			local ratio = (valPercent / 100)
			if (ratio * statusbar:GetWidth()) > statusbar:GetWidth() then
				statusbar.Fill:SetWidth(statusbar:GetWidth())
			else
				statusbar.Fill:SetWidth(ratio * (statusbar:GetWidth() - (statusbar.settings.MaxWidth - math.abs(statusbar.settings.GlowPoint.x))))
			end
		end
		if DB[side].text and valFill and valMax then
			statusbar.Text:SetFormattedText('( %s / %s ) %d%% %s', SUI.Font:comma_value(valFill), SUI.Font:comma_value(valMax), valPercent, remaining or '')
		end
	end

	SetBarColor_Classic(statusbar, side)
end

local function GetFactionDetails_Classic(name)
	if not name then
		return
	end
	local description = ' '
	for i = 1, GetNumFactions() do
		if name == GetFactionInfo(i) then
			description = select(2, GetFactionInfo(i))
		end
	end
	return description
end

local function showXPTooltip_Classic(statusbar)
	local xptip1 = string.gsub(EXHAUST_TOOLTIP1, '\n', ' ')
	local XP_LEVEL_TEMPLATE = '( %s / %s ) %d%% ' .. COMBAT_XP_GAIN
	local xprest = TUTORIAL_TITLE26 .. ' (%d%%) -'
	local a = format('Level %s ', UnitLevel('player'))
	local b = format(XP_LEVEL_TEMPLATE, SUI.Font:comma_value(UnitXP('player')), SUI.Font:comma_value(UnitXPMax('player')), (UnitXP('player') / UnitXPMax('player') * 100))
	statusbar.tooltip.TextFrame.HeaderText:SetText(a .. b)
	local rested, text = GetXPExhaustion() or 0, ''
	if rested > 0 then
		text = format(xptip1, format(xprest, (rested / UnitXPMax('player')) * 100), 200)
		statusbar.tooltip.TextFrame.MainText:SetText(text)
	else
		statusbar.tooltip.TextFrame.MainText:SetText(format(xptip1, EXHAUST_TOOLTIP2, 100))
	end
	statusbar.tooltip:Show()
end

local function showRepTooltip_Classic(statusbar)
	local name, react, low, high, current
	if GetWatchedFactionInfo then
		name, react, low, high, current = GetWatchedFactionInfo()
	elseif C_Reputation and C_Reputation.GetWatchedFactionData then
		local data = C_Reputation.GetWatchedFactionData()
		if data then
			name = data.name
			react = data.reaction
			low = data.currentReactionThreshold
			high = data.nextReactionThreshold
			current = data.currentStanding
		end
	end

	local repLevelLow = current and (current - low) or 0
	local repLevelHigh = high and (high - low) or 0
	local percentage

	if name then
		local text = GetFactionDetails_Classic(name)
		if repLevelHigh == 0 then
			percentage = 100
		else
			percentage = (repLevelLow / repLevelHigh) * 100
		end
		statusbar.tooltip.TextFrame.HeaderText:SetText(
			format('%s ( %s / %s ) %d%% %s', name, SUI.Font:comma_value(repLevelLow), SUI.Font:comma_value(repLevelHigh), percentage, _G['FACTION_STANDING_LABEL' .. react])
		)
		statusbar.tooltip.TextFrame.MainText:SetText('|cffffd200' .. text .. '|r')
		statusbar.tooltip:Show()
	else
		statusbar.tooltip.TextFrame.HeaderText:SetText(REPUTATION)
		statusbar.tooltip.TextFrame.MainText:SetText(REPUTATION_STANDING_DESCRIPTION)
	end
end

local function showHonorTooltip_Classic(statusbar)
	local honorLevel = UnitHonorLevel('player')
	local currentHonor = UnitHonor('player')
	local maxHonor = UnitHonorMax('player')

	if currentHonor == 0 and maxHonor == 0 then
		return
	end

	statusbar.tooltip.TextFrame.HeaderText:SetFormattedText(HONOR_LEVEL_LABEL, honorLevel)
	statusbar.tooltip.TextFrame.MainText:SetFormattedText('( %s / %s ) %d%%', SUI.Font:comma_value(currentHonor), SUI.Font:comma_value(maxHonor), ((currentHonor / maxHonor) * 100))

	statusbar.tooltip:Show()
end

local function showAzeriteTooltip_Classic(statusbar)
	if C_AzeriteItem and C_AzeriteItem.HasActiveAzeriteItem and C_AzeriteItem.HasActiveAzeriteItem() then
		local azeriteItemLocation = C_AzeriteItem.FindActiveAzeriteItem()
		if not azeriteItemLocation then
			return
		end
		local azeriteItem = Item:CreateFromItemLocation(azeriteItemLocation)
		local xp, totalLevelXP = C_AzeriteItem.GetAzeriteItemXPInfo(azeriteItemLocation)
		local currentLevel = C_AzeriteItem.GetPowerLevel(azeriteItemLocation)
		local xpToNextLevel = totalLevelXP - xp
		if currentLevel and xpToNextLevel then
			statusbar.tooltip.TextFrame.HeaderText:SetText(AZERITE_POWER_TOOLTIP_TITLE:format(currentLevel, xpToNextLevel), HIGHLIGHT_FONT_COLOR:GetRGB())
			if azeriteItem:GetItemName() then
				statusbar.tooltip.TextFrame.MainText:SetText(AZERITE_POWER_TOOLTIP_BODY:format(azeriteItem:GetItemName()))
			end
		end
	end
	statusbar.tooltip:Show()
end

function module:factory_Classic()
	for i, key in ipairs({ 'Left', 'Right' }) do
		local StyleSetting = GetStyleSettings(key)

		-- Status Bar
		local statusbar = CreateFrame('Frame', 'SUI_StatusBar_' .. key, SpartanUI)
		statusbar:SetSize(unpack(StyleSetting.size))
		statusbar:SetFrameStrata('BACKGROUND')

		-- Status Bar Images
		statusbar.bg = statusbar:CreateTexture(nil, 'BACKGROUND')
		statusbar.bg:SetTexture(StyleSetting.bgImg or StyleSetting.bgTexture or '')
		statusbar.bg:SetAllPoints(statusbar)
		statusbar.bg:SetTexCoord(unpack(StyleSetting.texCords))

		statusbar.overlay = statusbar:CreateTexture(nil, 'OVERLAY')
		statusbar.overlay:SetTexture(StyleSetting.bgImg or StyleSetting.bgTexture or '')
		statusbar.overlay:SetAllPoints(statusbar.bg)
		statusbar.overlay:SetTexCoord(unpack(StyleSetting.texCords))

		statusbar.Fill = statusbar:CreateTexture(nil, 'BORDER')
		statusbar.Fill:SetTexture(StyleSetting.GlowImage)
		statusbar.Fill:SetSize(0.1, StyleSetting.GlowHeight)

		statusbar.Lead = statusbar:CreateTexture(nil, 'BORDER')
		statusbar.Lead:SetTexture(StyleSetting.GlowImage)
		statusbar.Lead:SetSize(0.1, StyleSetting.GlowHeight)

		statusbar.FillGlow = statusbar:CreateTexture(nil, 'ARTWORK')
		statusbar.FillGlow:SetTexture(StyleSetting.GlowImage)
		statusbar.FillGlow:SetAllPoints(statusbar.Fill)

		statusbar.LeadGlow = statusbar:CreateTexture(nil, 'ARTWORK')
		statusbar.LeadGlow:SetTexture(StyleSetting.GlowImage)
		statusbar.LeadGlow:SetAllPoints(statusbar.Lead)

		-- Calculate GlowPoint offset based on MaxWidth if not explicitly set
		local glowOffsetX = StyleSetting.GlowPoint.x
		if glowOffsetX == 0 and StyleSetting.MaxWidth > 0 then
			if StyleSetting.Grow == 'LEFT' then
				glowOffsetX = -StyleSetting.MaxWidth
			else
				glowOffsetX = StyleSetting.MaxWidth
			end
		end

		if StyleSetting.Grow == 'LEFT' then
			statusbar.Fill:SetPoint('RIGHT', statusbar, 'RIGHT', glowOffsetX, StyleSetting.GlowPoint.y)
			statusbar.Lead:SetPoint('RIGHT', statusbar.Fill, 'LEFT', 0, 0)
		else
			statusbar.Fill:SetPoint('LEFT', statusbar, 'LEFT', glowOffsetX, StyleSetting.GlowPoint.y)
			statusbar.Lead:SetPoint('LEFT', statusbar.Fill, 'RIGHT', 0, 0)
		end

		-- Status Bar Text
		statusbar.Text = statusbar:CreateFontString(nil, 'OVERLAY')
		local tmp = DB.default.FontSize
		if StyleSetting.FontSize and DB[i].FontSize == DB.default.FontSize then
			tmp = StyleSetting.FontSize
		end
		SUI.Font:Format(statusbar.Text, tmp)
		statusbar.Text:SetJustifyH('CENTER')
		statusbar.Text:SetJustifyV('MIDDLE')
		statusbar.Text:SetAllPoints(statusbar)
		statusbar.Text:SetTextColor(unpack(StyleSetting.TextColor))

		-- Tooltip
		local tooltip = CreateFrame('Frame')
		tooltip:SetParent(statusbar)
		tooltip:SetFrameStrata('TOOLTIP')
		tooltip:SetSize(unpack(StyleSetting.TooltipSize))
		if StyleSetting.tooltipAnchor == 'TOP' then
			tooltip:SetPoint('BOTTOM', statusbar, 'TOP')
		else
			tooltip:SetPoint('TOP', statusbar, 'BOTTOM')
		end

		tooltip.bg = tooltip:CreateTexture(nil, 'BORDER')
		tooltip.bg:SetTexture(StyleSetting.bgTooltip)
		tooltip.bg:SetAllPoints(tooltip)
		tooltip.bg:SetTexCoord(unpack(StyleSetting.texCordsTooltip))

		local TextFrame = CreateFrame('Frame')
		TextFrame:SetFrameStrata('TOOLTIP')
		TextFrame:SetParent(tooltip)
		TextFrame:SetSize(unpack(StyleSetting.TooltipTextSize))
		TextFrame:SetPoint('CENTER', tooltip, 'CENTER')

		TextFrame.HeaderText = TextFrame:CreateFontString(nil, 'OVERLAY')
		SUI.Font:Format(TextFrame.HeaderText, 10)
		TextFrame.HeaderText:SetPoint('TOPLEFT', TextFrame)
		TextFrame.HeaderText:SetPoint('TOPRIGHT', TextFrame)
		TextFrame.HeaderText:SetHeight((0.18 * TextFrame:GetHeight()))

		TextFrame.MainText = TextFrame:CreateFontString(nil, 'OVERLAY')
		SUI.Font:Format(TextFrame.MainText, 8)
		TextFrame.MainText:SetPoint('TOPLEFT', TextFrame.HeaderText, 'BOTTOMLEFT', 0, -2)
		TextFrame.MainText:SetPoint('TOPRIGHT', TextFrame.HeaderText, 'BOTTOMRIGHT', 0, -2)
		TextFrame.MainText:SetHeight((0.82 * TextFrame:GetHeight()))

		TextFrame.MainText2 = TextFrame:CreateFontString(nil, 'OVERLAY')
		SUI.Font:Format(TextFrame.MainText2, 8)
		TextFrame.MainText2:SetPoint('TOPLEFT', TextFrame.MainText, 'BOTTOMLEFT', 0, -2)
		TextFrame.MainText2:SetPoint('TOPRIGHT', TextFrame.MainText, 'BOTTOMRIGHT', 0, -2)
		TextFrame.MainText2:SetHeight((0.82 * TextFrame:GetHeight()))

		TextFrame.HeaderText:SetJustifyH('LEFT')
		TextFrame.MainText:SetJustifyH('LEFT')
		TextFrame.MainText:SetJustifyV('TOP')

		-- Assign to globals
		tooltip.TextFrame = TextFrame
		statusbar.tooltip = tooltip
		statusbar.settings = StyleSetting
		statusbar.i = i
		module.bars[key] = statusbar

		-- Position
		local point, anchor, secondaryPoint, x, y = strsplit(',', StyleSetting.Position)
		statusbar:ClearAllPoints()
		statusbar:SetPoint(point, anchor, secondaryPoint, x, y)
		statusbar:SetAlpha(StyleSetting.alpha or 1)
		statusbar:SetScale(StyleSetting.scale or 1)

		-- Setup Actions
		statusbar:RegisterEvent('PLAYER_ENTERING_WORLD')
		statusbar:RegisterEvent('UNIT_INVENTORY_CHANGED')
		statusbar:RegisterEvent('PLAYER_XP_UPDATE')
		statusbar:RegisterEvent('PLAYER_LEVEL_UP')
		statusbar:RegisterEvent('UPDATE_FACTION')

		if SUI.IsRetail then
			statusbar:RegisterEvent('ARTIFACT_XP_UPDATE')
		end

		-- Statusbar Update event
		statusbar:SetScript('OnEvent', function(self)
			if DB[i].display ~= 'disabled' then
				self:Show()
				updateText_Classic(self)
			else
				self:Hide()
			end
		end)

		-- Tooltip Display Events
		statusbar:SetScript('OnEnter', function()
			if DB[i].display == 'rep' and DB[i].ToolTip == 'hover' then
				showRepTooltip_Classic(statusbar)
			end
			if DB[i].display == 'xp' and DB[i].ToolTip == 'hover' then
				showXPTooltip_Classic(statusbar)
			end
			if DB[i].display == 'az' and DB[i].ToolTip == 'hover' then
				showAzeriteTooltip_Classic(statusbar)
			end
			if DB[i].display == 'honor' and DB[i].ToolTip == 'hover' then
				showHonorTooltip_Classic(statusbar)
			end
		end)
		statusbar:SetScript('OnMouseDown', function()
			if DB[i].display == 'rep' and DB[i].ToolTip == 'click' then
				showRepTooltip_Classic(statusbar)
			end
			if DB[i].display == 'xp' and DB[i].ToolTip == 'click' then
				showXPTooltip_Classic(statusbar)
			end
			if DB[i].display == 'az' and DB[i].ToolTip == 'click' then
				showAzeriteTooltip_Classic(statusbar)
			end
			if DB[i].display == 'honor' and DB[i].ToolTip == 'click' then
				showHonorTooltip_Classic(statusbar)
			end
		end)
		statusbar:SetScript('OnLeave', function()
			statusbar.tooltip:Hide()
		end)

		-- Hide with SpartanUI
		SpartanUI:HookScript('OnHide', function()
			statusbar:Hide()
		end)
		SpartanUI:HookScript('OnShow', function()
			statusbar:Show()
		end)

		-- Hook the visibility of the tooltip to the text
		tooltip:HookScript('OnHide', function()
			tooltip.TextFrame:Hide()
		end)
		tooltip:HookScript('OnShow', function()
			tooltip.TextFrame:Show()
		end)
		-- Hide the new tooltip
		tooltip:Hide()

		-- MoveIt integration
		if SUI.MoveIt then
			-- Set dirtyWidth/dirtyHeight to match the visual statusbar size (with padding)
			statusbar.dirtyWidth = StyleSetting.size[1] - 30
			statusbar.dirtyHeight = StyleSetting.size[2] - 5
			SUI.MoveIt:CreateMover(statusbar, 'StatusBar_' .. key, key .. ' Status Bar', nil, 'StatusBars')
		end
	end

	SUI:RegisterMessage('StatusBarUpdate', function()
		for i, key in ipairs({ 'Left', 'Right' }) do
			-- Refresh the merged style settings
			local mergedSettings = GetStyleSettings(key)
			module.bars[key].settings = mergedSettings

			if DB[i].display ~= 'disabled' then
				module.bars[key]:Show()
				updateText_Classic(module.bars[key])
			else
				module.bars[key]:Hide()
			end
			module.bars[key]:SetAlpha(mergedSettings.alpha or 1)
			module.bars[key]:SetScale(mergedSettings.scale or 1)
		end
	end)
end

function module:SetActiveStyle_Classic(style)
	-- Update the style for each container (Left and Right)
	for i, key in ipairs({ 'Left', 'Right' }) do
		local statusbar = module.bars[key]
		if statusbar then
			local newStyle = GetStyleSettings(key)

			-- Update size
			statusbar:SetSize(unpack(newStyle.size))

			-- Update background texture
			if newStyle.bgTexture or newStyle.bgImg then
				statusbar.bg:SetTexture(newStyle.bgImg or newStyle.bgTexture)
				if newStyle.texCords then
					statusbar.bg:SetTexCoord(unpack(newStyle.texCords))
				end
			end

			-- Update overlay texture
			if newStyle.bgTexture or newStyle.bgImg then
				statusbar.overlay:SetTexture(newStyle.bgImg or newStyle.bgTexture)
				if newStyle.texCords then
					statusbar.overlay:SetTexCoord(unpack(newStyle.texCords))
				end
			end

			-- Update glow textures
			if newStyle.GlowImage then
				statusbar.Fill:SetTexture(newStyle.GlowImage)
				statusbar.Lead:SetTexture(newStyle.GlowImage)
				statusbar.FillGlow:SetTexture(newStyle.GlowImage)
				statusbar.LeadGlow:SetTexture(newStyle.GlowImage)

				if newStyle.GlowHeight then
					statusbar.Fill:SetHeight(newStyle.GlowHeight)
					statusbar.Lead:SetHeight(newStyle.GlowHeight)
				end

				-- Update glow positions
				local glowOffsetX = newStyle.GlowPoint.x
				if glowOffsetX == 0 and newStyle.MaxWidth > 0 then
					if newStyle.Grow == 'LEFT' then
						glowOffsetX = -newStyle.MaxWidth
					else
						glowOffsetX = newStyle.MaxWidth
					end
				end

				statusbar.Fill:ClearAllPoints()
				statusbar.Lead:ClearAllPoints()
				if newStyle.Grow == 'LEFT' then
					statusbar.Fill:SetPoint('RIGHT', statusbar, 'RIGHT', glowOffsetX, newStyle.GlowPoint.y)
					statusbar.Lead:SetPoint('RIGHT', statusbar.Fill, 'LEFT', 0, 0)
				else
					statusbar.Fill:SetPoint('LEFT', statusbar, 'LEFT', glowOffsetX, newStyle.GlowPoint.y)
					statusbar.Lead:SetPoint('LEFT', statusbar.Fill, 'RIGHT', 0, 0)
				end
			end

			-- Update tooltip
			if statusbar.tooltip then
				if newStyle.TooltipSize then
					statusbar.tooltip:SetSize(unpack(newStyle.TooltipSize))
				end
				if newStyle.bgTooltip then
					statusbar.tooltip.bg:SetTexture(newStyle.bgTooltip)
					if newStyle.texCordsTooltip then
						statusbar.tooltip.bg:SetTexCoord(unpack(newStyle.texCordsTooltip))
					end
				end
				if statusbar.tooltip.TextFrame and newStyle.TooltipTextSize then
					statusbar.tooltip.TextFrame:SetSize(unpack(newStyle.TooltipTextSize))
				end
			end

			-- Update text color
			if newStyle.TextColor then
				statusbar.Text:SetTextColor(unpack(newStyle.TextColor))
			end

			-- Update position
			local point, anchor, secondaryPoint, x, y = strsplit(',', newStyle.Position)
			statusbar:ClearAllPoints()
			statusbar:SetPoint(point, anchor, secondaryPoint, x, y)

			-- Store the new style settings
			statusbar.settings = newStyle

			-- Update the display
			if DB[i].display ~= 'disabled' then
				statusbar:Show()
				updateText_Classic(statusbar)
			else
				statusbar:Hide()
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- OPTIONS SYSTEM
----------------------------------------------------------------------------------------------------

function module:BuildOptions()
	if SUI.IsRetail then
		self:BuildOptions_Retail()
	else
		self:BuildOptions_Classic()
	end
end

function module:BuildOptions_Retail()
	SUI.opt.args['Artwork'].args['StatusBars'] = {
		name = L['Status bars'],
		type = 'group',
		args = {
			IsWatchingHonorAsXP = {
				name = 'Enable Honor bar',
				type = 'toggle',
				order = 2,
				get = function()
					return GetCVarBool('showHonorAsExperience')
				end,
				set = function(_, value)
					SetCVar('showHonorAsExperience', value)
				end,
			},
			ShowHousingXP = {
				name = 'Show Housing XP',
				type = 'toggle',
				order = 2.5,
				hidden = function()
					-- Only show this option if C_Housing API is available
					return not (C_Housing and C_Housing.GetTrackedHouseGuid)
				end,
				get = function()
					-- Check if there's actually a tracked house
					if C_Housing and C_Housing.GetTrackedHouseGuid then
						return C_Housing.GetTrackedHouseGuid() ~= nil
					end
					return false
				end,
				set = function(_, value)
					if not C_Housing then
						return
					end

					if value then
						-- Track a house - find the highest level house
						if C_Housing.GetPlayerHouses then
							local houses = C_Housing.GetPlayerHouses()
							if houses and #houses > 0 then
								-- Find the house with the highest level
								local bestHouse = houses[1]
								local bestLevel = (C_Housing.GetHouseLevel and C_Housing.GetHouseLevel(bestHouse.houseGUID)) or 0

								for i = 2, #houses do
									local level = (C_Housing.GetHouseLevel and C_Housing.GetHouseLevel(houses[i].houseGUID)) or 0
									if level > bestLevel then
										bestHouse = houses[i]
										bestLevel = level
									end
								end

								if C_Housing.SetTrackedHouseGuid then
									C_Housing.SetTrackedHouseGuid(bestHouse.houseGUID)
								end
							end
						end
					else
						-- Untrack the house
						if C_Housing.SetTrackedHouseGuid then
							C_Housing.SetTrackedHouseGuid(nil)
						end
					end

					self:UpdateBars()
				end,
			},
			EnableReputation = {
				name = 'Enable Reputation',
				type = 'toggle',
				order = 3,
				get = function()
					return DB.AllowRep
				end,
				set = function(_, value)
					DB.AllowRep = value
					self:UpdateBars()
				end,
			},
			PriorityDirection = {
				name = 'Priority Direction',
				type = 'select',
				order = 4,
				values = {
					['ltr'] = 'Left to Right',
					['rtl'] = 'Right to Left',
				},
				get = function()
					return DB.PriorityDirection
				end,
				set = function(_, value)
					DB.PriorityDirection = value
					self:UpdateBars()
				end,
			},
			BarPriorities = self:CreateBarPrioritiesOptions(),
			Font = self:CreateFontOptions(),
			Left = self:CreateContainerOptions('Left', 110),
			Right = self:CreateContainerOptions('Right', 120),
		},
	}
end

function module:BuildOptions_Classic()
	local StatusBars = {
		['xp'] = L['Experiance'],
		['rep'] = L['Reputation'],
		['honor'] = L['Honor'],
		['disabled'] = L['Disabled'],
	}

	-- Add Azerite for versions that support it (BFA Classic)
	if C_AzeriteItem and C_AzeriteItem.HasActiveAzeriteItem then
		StatusBars['az'] = L['Azerite Bar']
	end

	local ids = {
		[1] = 'one',
		[2] = 'two',
	}

	-- Build Holder
	SUI.opt.args['Artwork'].args['StatusBars'] = {
		name = L['Status bars'],
		type = 'group',
		args = {},
	}

	-- Bar Display dropdowns
	for i, _ in ipairs({ 'Left', 'Right' }) do
		SUI.opt.args['Artwork'].args['StatusBars'].args[ids[i]] = {
			name = L['Status bar'] .. ' ' .. i,
			order = i,
			type = 'group',
			inline = true,
			args = {
				display = {
					name = L['Display mode'],
					type = 'select',
					order = 1,
					values = StatusBars,
					get = function(info)
						return DB[i].display
					end,
					set = function(info, val)
						DB[i].display = val
						SUI:SendMessage('StatusBarUpdate')
					end,
				},
				text = {
					name = L['Display statusbar text'],
					type = 'toggle',
					order = 2,
					get = function(info)
						return DB[i].text
					end,
					set = function(info, val)
						DB[i].text = val
						SUI:SendMessage('StatusBarUpdate')
					end,
				},
				TooltipDisplay = {
					name = L['Tooltip display mode'],
					type = 'select',
					order = 3,
					values = {
						['hover'] = L['On mouse over'],
						['click'] = L['On click'],
						['off'] = L['Disabled'],
					},
					get = function(info)
						return DB[i].ToolTip
					end,
					set = function(info, val)
						DB[i].ToolTip = val
						SUI:SendMessage('StatusBarUpdate')
					end,
				},
				colors = {
					name = 'name',
					type = 'group',
					inline = true,
					get = function(info)
						return DB[i][info[#info]]
					end,
					set = function(info, val)
						DB[i][info[#info]] = val
						SUI:SendMessage('StatusBarUpdate')
					end,
					args = {
						AutoColor = {
							name = L['Auto color'],
							type = 'toggle',
							order = 3,
							get = function(info)
								return DB[i].AutoColor
							end,
							set = function(info, val)
								DB[i].AutoColor = val
								SUI:SendMessage('StatusBarUpdate')
							end,
						},
						CustomColor = {
							name = L['Primary custom color'],
							type = 'color',
							hasAlpha = true,
							order = 4,
							get = function(info)
								local colors = DB[i].CustomColor
								return colors.r, colors.g, colors.b, colors.a
							end,
							set = function(info, r, g, b, a)
								local colors = DB[i].CustomColor
								colors.r, colors.g, colors.b, colors.a = r, g, b, a
								SUI:SendMessage('StatusBarUpdate')
							end,
						},
						CustomColor2 = {
							name = L['Secondary custom color'],
							type = 'color',
							hasAlpha = true,
							order = 5,
							get = function(info)
								local colors = DB[i].CustomColor2
								return colors.r, colors.g, colors.b, colors.a
							end,
							set = function(info, r, g, b, a)
								local colors = DB[i].CustomColor2
								colors.r, colors.g, colors.b, colors.a = r, g, b, a
								SUI:SendMessage('StatusBarUpdate')
							end,
						},
					},
				},
				alpha = {
					name = 'Transparency',
					type = 'range',
					order = 10,
					min = 0,
					max = 1,
					step = 0.01,
					get = function(info)
						-- Show the effective value (merged from defaults > theme > user)
						local key = i == 1 and 'Left' or 'Right'
						local settings = GetStyleSettings(key)
						return settings.alpha or 1
					end,
					set = function(info, val)
						DB[i].alpha = val
						SUI:SendMessage('StatusBarUpdate')
					end,
				},
				scale = {
					name = 'Scale',
					type = 'range',
					order = 11,
					min = 0.5,
					max = 2,
					step = 0.01,
					get = function(info)
						-- Show the effective value (merged from defaults > theme > user)
						local key = i == 1 and 'Left' or 'Right'
						local settings = GetStyleSettings(key)
						return settings.scale or 1
					end,
					set = function(info, val)
						DB[i].scale = val
						SUI:SendMessage('StatusBarUpdate')
					end,
				},
			},
		}
	end
end

function module:CreateContainerOptions(containerKey, order)
	return {
		name = containerKey .. ' Status Bar',
		type = 'group',
		inline = true,
		order = order,
		args = {
			enabled = {
				name = 'Enable ' .. containerKey .. ' Bar',
				type = 'toggle',
				order = 0,
				get = function()
					return DB.bars[containerKey].enabled
				end,
				set = function(_, value)
					DB.bars[containerKey].enabled = value
					self:UpdateBars()
				end,
			},
			text = {
				name = 'Text Display',
				type = 'select',
				order = 1,
				disabled = function()
					return not DB.bars[containerKey].enabled
				end,
				values = {
					[Enums.TextDisplayMode.OnMouseOver] = 'On Mouse Over',
					[Enums.TextDisplayMode.Always] = 'Always',
					[Enums.TextDisplayMode.Never] = 'Never',
				},
				get = function()
					return DB.bars[containerKey].text
				end,
				set = function(_, value)
					DB.bars[containerKey].text = value
					self:UpdateBars()
				end,
			},
			alpha = {
				name = 'Alpha',
				type = 'range',
				order = 2,
				min = 0,
				max = 1,
				step = 0.01,
				disabled = function()
					return not DB.bars[containerKey].enabled
				end,
				get = function()
					-- Show the effective value (merged from defaults > theme > user)
					local settings = GetStyleSettings(containerKey)
					return settings.alpha or 1
				end,
				set = function(_, value)
					DB.bars[containerKey].alpha = value
					self:UpdateBars()
				end,
			},
			scale = {
				name = 'Scale',
				type = 'range',
				order = 2.5,
				min = 0.5,
				max = 2,
				step = 0.01,
				disabled = function()
					return not DB.bars[containerKey].enabled
				end,
				get = function()
					-- Show the effective value (merged from defaults > theme > user)
					local settings = GetStyleSettings(containerKey)
					return settings.scale or 1
				end,
				set = function(_, value)
					DB.bars[containerKey].scale = value
					self:UpdateBars()
				end,
			},
			showTooltip = {
				name = 'Show Tooltip on Mouseover',
				type = 'toggle',
				order = 3,
				disabled = function()
					return not DB.bars[containerKey].enabled
				end,
				get = function()
					return DB.bars[containerKey].showTooltip
				end,
				set = function(_, value)
					DB.bars[containerKey].showTooltip = value
				end,
			},
		},
	}
end

function module:CreateFontOptions()
	return {
		name = 'Font Settings',
		type = 'group',
		order = 100,
		inline = true,
		get = function(info)
			return SUI.Font.DB.Modules.StatusBars[info[#info]]
		end,
		set = function(info, val)
			SUI.Font.DB.Modules.StatusBars[info[#info]] = val
			SUI.Font:Refresh('StatusBars')
		end,
		args = {
			Face = {
				type = 'select',
				name = L['Font face'],
				order = 1,
				dialogControl = 'LSM30_Font',
				values = SUI.Lib.LSM:HashTable('font'),
			},
			Type = {
				name = L['Font style'],
				type = 'select',
				order = 2,
				values = {
					['normal'] = L['Normal'],
					['monochrome'] = L['Monochrome'],
					['outline'] = L['Outline'],
					['thickoutline'] = L['Thick outline'],
				},
			},
			Size = {
				name = L['Adjust font size'],
				type = 'range',
				order = 3,
				width = 'double',
				min = -15,
				max = 15,
				step = 1,
			},
		},
	}
end

function module:CreateBarPrioritiesOptions()
	local options = {
		name = 'Bar Priorities',
		type = 'group',
		order = 50,
		inline = true,
		args = {},
	}

	local function isBarAtTop(barIndex)
		return DB.BarPriorities[barIndex] == 0
	end

	local function isBarAtBottom(barIndex)
		local highest = 0
		for _, priority in pairs(DB.BarPriorities) do
			if priority > highest then
				highest = priority
			end
		end
		return DB.BarPriorities[barIndex] == highest
	end

	local function moveBar(barIndex, direction)
		local currentPriority = DB.BarPriorities[barIndex]
		local newPriority = currentPriority + (direction == 'up' and -1 or 1)

		for otherBarIndex, priority in pairs(DB.BarPriorities) do
			if priority == newPriority then
				DB.BarPriorities[otherBarIndex] = currentPriority
				DB.BarPriorities[barIndex] = newPriority
				break
			end
		end

		self:UpdateBars()
	end

	for i, v in pairs(DB.BarPriorities) do
		options.args[BarLabels[i]] = {
			name = '',
			type = 'group',
			order = v,
			args = {
				label = {
					type = 'description',
					width = 'double',
					fontSize = 'medium',
					order = 1,
					name = BarLabels[i],
				},
				up = {
					type = 'execute',
					name = 'Up',
					width = 'half',
					order = 2,
					disabled = function()
						return isBarAtTop(i)
					end,
					func = function()
						moveBar(i, 'up')
					end,
				},
				down = {
					type = 'execute',
					name = 'Down',
					width = 'half',
					order = 3,
					disabled = function()
						return isBarAtBottom(i)
					end,
					func = function()
						moveBar(i, 'down')
					end,
				},
			},
		}
	end

	return options
end
