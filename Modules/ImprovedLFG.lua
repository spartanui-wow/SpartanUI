---@class SUI
local SUI = SUI

-- Retail-only module (requires C_LFGList API)
if not SUI.IsRetail then
	return
end

local module = SUI:NewModule('ImprovedLFG')
module.DisplayName = 'Improved LFG'
------------------------------------------
local FrameStorage = {
	role = {},
	rating = {},
}

---@class ImprovedLFGDB
local DBDefaults = {
	showClass = true,
	showLeaderRating = true,
}

---@param self LFGListSearchEntry
---@param numIcons? number
local function GetRoleIndicators(self, numIcons)
	local StoredFrame = FrameStorage.role[self]
	if StoredFrame == nil and numIcons then
		StoredFrame = {}
		for iconIndex = 1, numIcons do
			local frame = CreateFrame('Frame', nil, self, nil)
			frame:Hide()
			frame:SetFrameStrata('HIGH')
			frame:SetSize(18, 36)
			frame:SetPoint('CENTER')
			frame:SetPoint('RIGHT', self, 'RIGHT', -12 - (numIcons - iconIndex) * 18, 0)

			frame.ClassBar = frame:CreateTexture('$parentClassBar', 'OVERLAY')
			frame.ClassBar:SetSize(14, 3)
			frame.ClassBar:SetPoint('CENTER')
			frame.ClassBar:SetPoint('BOTTOM', 0, 3)

			frame.Leader = frame:CreateTexture('$parentLeaderCrown', 'OVERLAY')
			frame.Leader:SetSize(10, 5)
			frame.Leader:SetPoint('TOP', 0, -5)
			frame.Leader:SetAtlas('groupfinder-icon-leader', false, 'LINEAR')

			StoredFrame[iconIndex] = frame
		end
		FrameStorage.role[self] = StoredFrame
	end
	return StoredFrame
end

---@param self LFGListSearchEntry
local function GetListingRatingFrame(self)
	local StoredFrame = FrameStorage.rating[self]
	if StoredFrame == nil then
		StoredFrame = CreateFrame('Frame', nil, self, nil)
		StoredFrame:Hide()
		StoredFrame:SetFrameStrata('HIGH')
		StoredFrame:SetSize(35, 30)
		StoredFrame:SetPoint('TOP', 0, -4)

		StoredFrame.Label = StoredFrame:CreateFontString('$parentRating', 'ARTWORK', 'GameFontNormalSmall')
		StoredFrame.Label:SetSize(35, 15)
		StoredFrame.Label:SetPoint('TOP')
		StoredFrame.Label:SetJustifyH('RIGHT')
		StoredFrame.Label:SetTextColor(1, 1, 1)
		StoredFrame.Label:SetText('Rating')

		StoredFrame.Rating = StoredFrame:CreateFontString('$parentExtraText', 'ARTWORK', 'GameFontNormalSmall')
		StoredFrame.Rating:SetSize(35, 15)
		StoredFrame.Rating:SetPoint('BOTTOM')
		StoredFrame.Rating:SetJustifyH('RIGHT')
		StoredFrame.Rating:SetTextColor(1, 1, 1)

		FrameStorage.rating[self] = StoredFrame
	end
	return StoredFrame
end

local function IsPending(searchResultId)
	local _, appStatus, pendingStatus = C_LFGList.GetApplicationInfo(searchResultId)
	return (appStatus ~= 'none' or pendingStatus)
end

---@param self LFGListSearchEntry
---@param searchResultInfo LfgSearchResultData
local function DetailRoles(self, searchResultInfo)
	--Grab this now and hide it, we will show it later if needed
	local classSquares = GetRoleIndicators(self, #self.DataDisplay.Enumerate.Icons)
	for _, frame in pairs(classSquares) do
		frame:Hide()
	end

	local activityInfo = C_LFGList.GetActivityInfoTable(searchResultInfo.activityID)

	--See if the listing has roles, or if we are applied to the listing.
	if activityInfo.displayType ~= Enum.LFGListDisplayType.RoleEnumerate or IsPending(self.resultID) then
		return
	end

	--Pull member data from the listing
	local memberList = {}
	for i = 1, searchResultInfo.numMembers do
		local role, class = C_LFGList.GetSearchResultMemberInfo(self.resultID, i)
		local color = searchResultInfo.isDelisted and { r = 0.2, g = 0.2, b = 0.2 } or RAID_CLASS_COLORS[class]
		table.insert(memberList, {
			role = role,
			class = class,
			color = color,
			leader = (i == 1),
		})
	end

	--Sort the member data by role
	local order = {
		['TANK'] = 1,
		['HEALER'] = 2,
		['DAMAGER'] = 3,
	}
	table.sort(memberList, function(a, b)
		if order[a.role] ~= order[b.role] then
			return order[a.role] < order[b.role]
		end
		return a.class < b.class
	end)

	--Now manage what we show
	for i = 1, #classSquares do
		local member = memberList[i]
		--Hide the elements incase of a change in role
		classSquares[i].ClassBar:Hide()
		classSquares[i].Leader:Hide()

		--Update the display
		if member then
			classSquares[i]:Show()
			classSquares[i].ClassBar:Show()
			classSquares[i].ClassBar:SetColorTexture(member.color.r, member.color.g, member.color.b, 1)
			if member.leader then
				classSquares[i].Leader:Show()
				classSquares[i].Leader:SetDesaturated(searchResultInfo.isDelisted)
				classSquares[i].Leader:SetAlpha(searchResultInfo.isDelisted and 0.5 or 1.0)
			end
		else
			classSquares[i]:Hide()
		end
	end
end

---@param self LFGListSearchEntry
---@param searchResultInfo LfgSearchResultData
local function LeaderRating(self, searchResultInfo)
	local activityInfo = C_LFGList.GetActivityInfoTable(searchResultInfo.activityID)
	--Grab this now and hide it, we will show it later if needed
	local frame = GetListingRatingFrame(self)
	frame:Hide()

	--Reset width
	self.Name:SetWidth(176)
	self.ActivityName:SetWidth(176)

	if IsPending(self.resultID) then
		return
	end

	local position = -130
	local rating = 0
	local ratingColor = { r = 1.0, g = 1.0, b = 1.0 }
	if activityInfo.isMythicPlusActivity then
		position = -115
		rating = searchResultInfo.leaderOverallDungeonScore or 0
		ratingColor = C_ChallengeMode.GetDungeonScoreRarityColor(rating) or ratingColor
	elseif activityInfo.isRatedPvpActivity and searchResultInfo.leaderPvpRatingInfo then
		position = activityInfo.categoryID == 4 and -80 or -130
		rating = searchResultInfo.leaderPvpRatingInfo.rating or 0
		local PVPUtilGetTierName = {
			[0] = { tier = 0, minRating = 0, quality = 0 }, -- Unranked
			[1] = { tier = 1, minRating = 1000, quality = 1 }, -- Combatant I
			[2] = { tier = 3, minRating = 1400, quality = 2 }, -- Challenger I
			[3] = { tier = 5, minRating = 1800, quality = 3 }, -- Rival I
			[4] = { tier = 7, minRating = 2100, quality = 4 }, -- Duelist
			[5] = { tier = 8, minRating = 2400, quality = 5 }, -- Elite
			[6] = { tier = 2, minRating = 1200, quality = 1 }, -- Combatant II
			[7] = { tier = 4, minRating = 1600, quality = 2 }, -- Challenger II
			[8] = { tier = 6, minRating = 1950, quality = 3 }, -- Rival II
		}
		local r, g, b = C_Item.GetItemQualityColor(PVPUtilGetTierName[searchResultInfo.leaderPvpRatingInfo.tier or 0].quality)
		ratingColor = { r = r, g = g, b = b } or ratingColor
	else
		return
	end

	local textWidth = 312 - 10 - 35 + position
	--Account for voice chat icon
	if searchResultInfo.voiceChat and searchResultInfo.voiceChat ~= '' then
		textWidth = textWidth - 20
	end

	local finalColor = searchResultInfo.isDelisted and LFG_LIST_DELISTED_FONT_COLOR or ratingColor

	self.Name:SetWidth(textWidth)
	self.ActivityName:SetWidth(textWidth)

	--Wish we could attach this to the listing so its destoryed when the listing is. But we cant due to taint.
	frame:SetPoint('RIGHT', position, 0)
	frame.Rating:SetText(rating)
	frame.Rating:SetTextColor(finalColor.r, finalColor.g, finalColor.b)
	frame:Show()
end

local function Options()
	---@type AceConfig.OptionsTable
	local OptTable = {
		name = module.DisplayName,
		type = 'group',
		disabled = function()
			return SUI:IsModuleDisabled(module)
		end,
		get = function(info)
			return module.DB[info[#info]]
		end,
		set = function(info, value)
			module.DB[info[#info]] = value
		end,
		args = {
			showClass = {
				name = 'Show Class under role indicators',
				type = 'toggle',
				width = 'full',
			},
			showLeaderRating = {
				name = 'Show Leader Rating',
				type = 'toggle',
				width = 'full',
			},
		},
	}

	SUI.Options:AddOptions(OptTable, 'ImprovedLFG', nil)
end

function module:OnInitialize()
	module.Database = SUI.SpartanUIDB:RegisterNamespace('ImprovedLFG', { profile = DBDefaults })
	---@type ImprovedLFGDB
	module.DB = module.Database.profile

	-- Register profile change callbacks
	SUI.DBM:RegisterSequentialProfileRefresh(module)
end

function module:OnEnable()
	Options()

	local function LFGSearchUpdate(self)
		local searchResultInfo = C_LFGList.GetSearchResultInfo(self.resultID)

		--Do Leader Rating
		if module.DB.showLeaderRating and SUI:IsModuleEnabled(module) then
			LeaderRating(self, searchResultInfo)
		else
			local frame = GetListingRatingFrame(self)
			if frame then
				frame:Hide()
			end
		end

		--Do class bars
		if module.DB.showClass and SUI:IsModuleEnabled(module) then
			DetailRoles(self, searchResultInfo)
		else
			local roleimages = GetRoleIndicators(self)
			if roleimages then
				for _, v in ipairs(roleimages) do
					v:Hide()
				end
			end
		end
	end
	hooksecurefunc('LFGListSearchEntry_Update', LFGSearchUpdate)

	if SUI:IsAddonEnabled('PremadeGroupsFilter') then
		module.Override = true
	end
end

function module:OnDisable() end

---@class LFGListSearchEntry : Frame
---@field ActivityName FontString
---@field Name FontString
---@field PendingLabel FontString
---@field ApplicationBG Texture
---@field Highlight Texture
---@field VoiceChat Texture
---@field RoleDescription FontString
---@field Role FontString
---@field ExpirationTime string
---@field OfflineNotice string
---@field CancelButton Button
---@field resultID number
---@field expiration number
---@field GetElementData function
---@field GetOrderIndex function
---@field SetOrderIndex function
---@field DataDisplay LFGListSearchEntryData

---@class LFGListSearchEntryData : Frame
---@field Enumerate LFGListSearchEntryDataEnumerate

---@class LFGListSearchEntryDataEnumerate
---@field Icon1 Texture
---@field Icon2 Texture
---@field Icon3 Texture
---@field Icon4 Texture
---@field Icon5 Texture
---@field Icons table
