local _G, SUI, L, LSM = _G, SUI, SUI.L, SUI.Lib.LSM
local module = SUI:NewModule('Tooltips', 'AceHook-3.0') ---@type SUI.Module
module.description = 'SpartanUI tooltip skining'
local unpack = unpack
----------------------------------------------------------------------------------------------------
local targetList = {}
local tooltips = {
	GameTooltip,
	ItemRefTooltip,
	ItemRefShoppingTooltip1,
	ItemRefShoppingTooltip2,
	ItemRefShoppingTooltip3,
	AutoCompleteBox,
	FriendsTooltip,
	ConsolidatedBuffsTooltip,
	ShoppingTooltip1,
	ShoppingTooltip2,
	ShoppingTooltip3,
	WorldMapTooltip,
	WorldMapCompareTooltip1,
	WorldMapCompareTooltip2,
	WorldMapCompareTooltip3,
	DropDownList1MenuBackdrop,
	DropDownList2MenuBackdrop,
	DropDownList3MenuBackdrop,
	BNToastFrame,
	PetBattlePrimaryAbilityTooltip,
	PetBattlePrimaryUnitTooltip,
	BattlePetTooltip,
	FloatingBattlePetTooltip,
	FloatingPetBattleAbilityTooltip,
	FloatingGarrisonFollowerTooltip,
	GarrisonMissionMechanicTooltip,
	GarrisonFollowerTooltip,
	GarrisonMissionMechanicFollowerCounterTooltip,
	GarrisonFollowerAbilityTooltip,
	SmallTextTooltip,
	BrowserSettingsTooltip,
	QueueStatusFrame,
	EventTraceTooltip,
	ItemSocketingDescription,
}
local whitebg = { bgFile = 'Interface\\AddOns\\SpartanUI\\images\\blank.tga', tile = false, edgeSize = 3, insets = { left = 0, right = 1, top = 0, bottom = 1 } }
local ilvlTempData = {}

---Check if the modifier key condition is met for spell ID display
---@param setting string The modifier setting ('NONE', 'SHIFT', 'CTRL', 'ALT', 'ALL')
---@return boolean
local function IsModifierConditionMet(setting)
	if setting == 'ALL' then
		return true
	elseif setting == 'NONE' then
		return false
	elseif setting == 'SHIFT' then
		return IsShiftKeyDown()
	elseif setting == 'CTRL' then
		return IsControlKeyDown()
	elseif setting == 'ALT' then
		return IsAltKeyDown()
	end
	return false
end

-- Upgrade quality tier data for tooltip icons (Retail only)
local UPGRADE_CATEGORY_DATA = {
	[970] = { name = 'Explorer', tier = 1 },
	[971] = { name = 'Adventurer', tier = 2 },
	[972] = { name = 'Veteran', tier = 3 },
	[973] = { name = 'Champion', tier = 4 },
	[974] = { name = 'Hero', tier = 5 },
	[978] = { name = 'Myth', tier = 5 },
	[998] = { name = 'Awakened', tier = 5 },
}

local function SkinCompareHeader(tooltip)
	if not tooltip.CompareHeader then
		return
	end

	if not tooltip.CompareHeader.SUISkined then
		-- Hide default Blizzard background
		if tooltip.CompareHeader.Background then
			tooltip.CompareHeader.Background:Hide()
		end

		-- Create custom background
		if not tooltip.CompareHeader.SUIBackground then
			tooltip.CompareHeader.SUIBackground = tooltip.CompareHeader:CreateTexture(nil, 'BACKGROUND')
			tooltip.CompareHeader.SUIBackground:SetAllPoints(tooltip.CompareHeader)
			tooltip.CompareHeader.SUIBackground:SetTexture('Interface\\AddOns\\SpartanUI\\images\\blank.tga')

			-- Apply color based on settings
			local r, g, b = unpack(module.DB.Color)
			tooltip.CompareHeader.SUIBackground:SetVertexColor(r, g, b, 1)
		end

		-- Center the label
		if tooltip.CompareHeader.Label then
			tooltip.CompareHeader.Label:ClearAllPoints()
			tooltip.CompareHeader.Label:SetPoint('CENTER', tooltip.CompareHeader, 'CENTER', 0, 0)
		end

		-- Reposition and resize the header to center it on the tooltip
		tooltip.CompareHeader:ClearAllPoints()
		tooltip.CompareHeader:SetPoint('BOTTOM', tooltip, 'TOP', 0, -1)
		tooltip.CompareHeader:SetHeight(18)

		tooltip.CompareHeader.SUISkined = true
	end
end

function module:OnInitialize()
	---@class SUI.Tooltip.Settings
	local defaults = {
		Styles = {
			metal = {
				bgFile = 'Interface\\AddOns\\SpartanUI\\images\\statusbars\\metal',
				tile = false,
			},
			smooth = {
				bgFile = 'Interface\\AddOns\\SpartanUI\\images\\statusbars\\Smoothv2',
				tile = false,
			},
			smoke = {
				bgFile = 'Interface\\AddOns\\SpartanUI\\images\\textures\\smoke',
				tile = false,
			},
			none = {
				bgFile = 'Interface\\AddOns\\SpartanUI\\images\\blank.tga',
				tile = false,
			},
		},
		Rule1 = {
			Status = 'All',
			Combat = false,
			OverrideLoc = false,
			Anchor = { onMouse = false, Moved = false, AnchorPos = {} },
		},
		Rule2 = {
			Status = 'All',
			Combat = false,
			OverrideLoc = false,
			Anchor = { onMouse = false, Moved = false, AnchorPos = {} },
		},
		Background = 'Blizzard Dialog Background Dark',
		onMouse = false,
		VendorPrices = true,
		Override = {},
		ColorOverlay = true,
		Color = { 0, 0, 0, 0.9 },
		SuppressNoMatch = true,
		SpellID = {
			enabled = false,
			modifierKey = 'NONE',
		},
		UpgradeQualityIcons = {
			enabled = true,
		},
	}
	module.Database = SUI.SpartanUIDB:RegisterNamespace('Tooltips', { profile = defaults })
	module.DB = module.Database.profile ---@type SUI.Tooltip.Settings
end

local onShow = function(self)
	if not self.SUITip then
		return
	end

	-- Ensure module.DB is initialized before accessing settings
	if not module.DB or not module.DB.Color then
		return
	end

	-- Clear tooltip backdrop - SUITip layer provides the background
	if self.SetBackdrop then
		self:SetBackdrop(nil)
	end

	-- Update SUITip background texture
	local bgTexture = LSM:Fetch('background', module.DB.Background)
	if bgTexture and bgTexture ~= '' then
		self.SUITip.bgTexture:SetTexture(bgTexture)
	else
		-- Fallback to solid color if texture not available
		self.SUITip.bgTexture:SetColorTexture(0, 0, 0, 1)
	end

	-- Apply color based on settings
	local r, g, b, a = unpack(module.DB.Color)
	if module.DB.Background == 'none' or module.DB.ColorOverlay then
		-- Color overlay mode: apply user's color at full opacity (the color itself provides darkness)
		self.SUITip.bgTexture:SetVertexColor(r, g, b, 1)
	else
		-- Standard mode: show texture as-is with user's alpha transparency
		-- Use black as fallback if texture doesn't exist to prevent white backgrounds
		if bgTexture and bgTexture ~= '' then
			self.SUITip.bgTexture:SetVertexColor(1, 1, 1, a)
		else
			self.SUITip.bgTexture:SetVertexColor(0, 0, 0, a)
		end
	end

	self.SUITip:SetFrameLevel(0)

	-- Update CompareHeader styling if present
	SkinCompareHeader(self)
end

local onHide = function(self)
	self.SUITip.border:Hide()
	self.SUITip:ClearColors()
end

local TipCleared = function(self)
	onShow(self)
	self.SUITip:ClearColors()
	self.SUITip.border:Hide()
	self.itemCleared = nil
end

local setPoint = function(self, parent)
	if parent then
		if module.DB.onMouse then
			self:SetOwner(parent, 'ANCHOR_CURSOR')
		end
	end
end

local SetBorderColor = function(self, r, g, b, hasStatusBar)
	self.SUITip.border:Show()
	self.SUITip.border[1]:SetVertexColor(r, g, b, 1)
	self.SUITip.border[2]:SetVertexColor(r, g, b, 1)
	self.SUITip.border[3]:SetVertexColor(r, g, b, 1)
	self.SUITip.border[4]:SetVertexColor(r, g, b, 1)

	if self.NineSlice then
		SUI.Skins.RemoveTextures(self.NineSlice)
	end
end

local ClearColors = function(SUITip)
	SUITip.border[1]:SetVertexColor(0, 0, 0, 0)
	SUITip.border[2]:SetVertexColor(0, 0, 0, 0)
	SUITip.border[3]:SetVertexColor(0, 0, 0, 0)
	SUITip.border[4]:SetVertexColor(0, 0, 0, 0)
end

local function ApplySkin(tooltip)
	if not tooltip.SUITip then
		local SUITip = CreateFrame('Frame', nil, tooltip)
		SUITip:SetAllPoints(tooltip)
		SUITip:SetFrameLevel(0)

		-- Create background texture manually
		SUITip.bgTexture = SUITip:CreateTexture(nil, 'BACKGROUND')
		SUITip.bgTexture:SetAllPoints(SUITip)

		-- Apply background from LSM
		local bgTexture = LSM:Fetch('background', module.DB.Background)
		if bgTexture and bgTexture ~= '' then
			SUITip.bgTexture:SetTexture(bgTexture)
		else
			-- Fallback to solid color if texture not available
			SUITip.bgTexture:SetColorTexture(0, 0, 0, 1)
		end

		-- Apply color based on settings
		-- Ensure Color exists with fallback default
		local colorTable = module.DB.Color or { 0, 0, 0, 0.9 }
		local r, g, b, a = unpack(colorTable)
		if module.DB.Background == 'none' or module.DB.ColorOverlay then
			-- Color overlay mode: apply user's color at full opacity (the color itself provides darkness)
			SUITip.bgTexture:SetVertexColor(r, g, b, 1)
		else
			-- Standard mode: show texture as-is with user's alpha transparency
			-- Use black as fallback if texture doesn't exist to prevent white backgrounds
			if bgTexture and bgTexture ~= '' then
				SUITip.bgTexture:SetVertexColor(1, 1, 1, a)
			else
				SUITip.bgTexture:SetVertexColor(0, 0, 0, a)
			end
		end

		-- Create border container
		SUITip.border = CreateFrame('Frame', nil, SUITip)
		SUITip.border:SetAllPoints(SUITip)
		SUITip.border:SetFrameLevel(1)

		--TOP
		SUITip.border[1] = SUITip.border:CreateTexture(nil, 'OVERLAY')
		SUITip.border[1]:SetPoint('TOPLEFT', SUITip, 'TOPLEFT')
		SUITip.border[1]:SetPoint('TOPRIGHT', SUITip, 'TOPRIGHT')
		SUITip.border[1]:SetHeight(2)
		SUITip.border[1]:SetTexture('Interface\\AddOns\\SpartanUI\\images\\blank.tga')
		--BOTTOM
		SUITip.border[2] = SUITip.border:CreateTexture(nil, 'OVERLAY')
		SUITip.border[2]:SetPoint('BOTTOMLEFT', SUITip, 'BOTTOMLEFT')
		SUITip.border[2]:SetPoint('BOTTOMRIGHT', SUITip, 'BOTTOMRIGHT')
		SUITip.border[2]:SetHeight(2)
		SUITip.border[2]:SetTexture('Interface\\AddOns\\SpartanUI\\images\\blank.tga')
		--RIGHT
		SUITip.border[3] = SUITip.border:CreateTexture(nil, 'OVERLAY')
		SUITip.border[3]:SetPoint('TOPRIGHT', SUITip, 'TOPRIGHT')
		SUITip.border[3]:SetPoint('BOTTOMRIGHT', SUITip, 'BOTTOMRIGHT')
		SUITip.border[3]:SetWidth(2)
		SUITip.border[3]:SetTexture('Interface\\AddOns\\SpartanUI\\images\\blank.tga')
		--LEFT
		SUITip.border[4] = SUITip.border:CreateTexture(nil, 'OVERLAY')
		SUITip.border[4]:SetPoint('TOPLEFT', SUITip, 'TOPLEFT')
		SUITip.border[4]:SetPoint('BOTTOMLEFT', SUITip, 'BOTTOMLEFT')
		SUITip.border[4]:SetWidth(2)
		SUITip.border[4]:SetTexture('Interface\\AddOns\\SpartanUI\\images\\blank.tga')

		SUITip.ClearColors = ClearColors
		SUITip.border:Hide()

		tooltip.SUITip = SUITip
		tooltip.SetBorderColor = SetBorderColor

		-- Hook scripts for show/hide handling
		tooltip:HookScript('OnShow', onShow)
		tooltip:HookScript('OnHide', onHide)
	end

	-- Remove default Blizzard styling
	if tooltip.NineSlice then
		SUI.Skins.RemoveTextures(tooltip.NineSlice)
	end

	-- Clear tooltip backdrop - SUITip layer provides the background
	if tooltip.SetBackdrop then
		tooltip:SetBackdrop(nil)
	end

	-- Skin the CompareHeader if it exists (shopping tooltips)
	SkinCompareHeader(tooltip)

	tooltip.skined = true
end

local TooltipSetGeneric = function(self, tooltipData)
	if self.NineSlice then
		SUI.Skins.RemoveTextures(self.NineSlice)
	end

	ApplySkin(self)
end

---Enhanced spell tooltip handler with spell ID display
---@param self any The tooltip frame
---@param tooltipData any The tooltip data
local TooltipSetSpell = function(self, tooltipData)
	-- Apply standard skin
	if self.NineSlice then
		SUI.Skins.RemoveTextures(self.NineSlice)
	end
	ApplySkin(self)

	-- Add spell ID if enabled and conditions are met
	if module.DB and module.DB.SpellID and module.DB.SpellID.enabled and tooltipData and tooltipData.id then
		local shouldShowID = IsModifierConditionMet(module.DB.SpellID.modifierKey)

		if shouldShowID then
			-- Use ElvUI-style formatting for consistency
			local IDLine = '|cFFCA3C3C%s:|r %d'
			self:AddLine(string.format(IDLine, 'ID', tooltipData.id))
			self:Show()
		end
	end
end

local TooltipSetItem = function(tooltip, tooltipData)
	local itemLink = nil
	if tooltip.GetItem then
		itemLink = select(2, tooltip:GetItem())
	elseif tooltipData and tooltipData.guid and C_Item and C_Item.GetItemLinkByGUID then
		itemLink = C_Item.GetItemLinkByGUID(tooltipData.guid)
	else
		return
	end

	if itemLink then
		-- Get item quality - try C_Item API first, fallback to global GetItemInfo
		local quality
		if C_Item and C_Item.GetItemInfo then
			quality = select(3, C_Item.GetItemInfo(itemLink))
		end

		-- Update SUITip background texture for special item types
		if tooltip.SUITip and tooltip.SUITip.bgTexture then
			local blizzBgTexture = 'Interface/Tooltips/UI-Tooltip-Background'

			if C_AzeriteEmpoweredItem and C_AzeriteItem and (C_AzeriteEmpoweredItem.IsAzeriteEmpoweredItemByID(itemLink) or C_AzeriteItem.IsAzeriteItemByID(itemLink)) then
				blizzBgTexture = 'Interface/Tooltips/UI-Tooltip-Background-Azerite'
			end

			-- Use Blizzard background for items, but fallback to user's LSM background if needed
			local bgTexture = LSM:Fetch('background', module.DB.Background)
			if bgTexture and bgTexture ~= '' then
				tooltip.SUITip.bgTexture:SetTexture(bgTexture)
			else
				-- Fallback to solid color if texture not available
				tooltip.SUITip.bgTexture:SetColorTexture(0, 0, 0, 1)
			end

			-- Apply color based on settings
			local r, g, b, a = unpack(module.DB.Color)
			if module.DB.Background == 'none' or module.DB.ColorOverlay then
				-- Color overlay mode: apply user's color at full opacity (the color itself provides darkness)
				tooltip.SUITip.bgTexture:SetVertexColor(r, g, b, 1)
			else
				-- Standard mode: show texture as-is with user's alpha transparency
				-- Use black as fallback if texture doesn't exist to prevent white backgrounds
				if bgTexture and bgTexture ~= '' then
					tooltip.SUITip.bgTexture:SetVertexColor(1, 1, 1, a)
				else
					tooltip.SUITip.bgTexture:SetVertexColor(0, 0, 0, a)
				end
			end
		end

		if quality and tooltip.SetBorderColor then
			-- Get quality color - try C_Item API first, fallback to GetItemQualityColor
			local r, g, b
			if C_Item and C_Item.GetItemQualityColor then
				r, g, b = C_Item.GetItemQualityColor(quality)
			end

			if r and g and b then
				r, g, b = (r * 0.5), (g * 0.5), (b * 0.5)
				tooltip:SetBorderColor(r, g, b)
			end
		end
		tooltip.itemCleared = true

		-- Add item ID if enabled and conditions are met
		if module.DB and module.DB.SpellID and module.DB.SpellID.enabled and tooltipData and tooltipData.id then
			local shouldShowID = IsModifierConditionMet(module.DB.SpellID.modifierKey)

			if shouldShowID then
				-- Use ElvUI-style formatting for consistency
				local IDLine = '|cFFCA3C3C%s:|r %d'
				tooltip:AddLine(string.format(IDLine, 'ID', tooltipData.id))
				tooltip:Show()
			end
		end

		-- Add upgrade quality icon if enabled (Retail only)
		if SUI.IsRetail and module.DB and module.DB.UpgradeQualityIcons and module.DB.UpgradeQualityIcons.enabled then
			if C_Item and C_Item.GetItemUpgradeInfo then
				local upgradeInfo = C_Item.GetItemUpgradeInfo(itemLink)
				if upgradeInfo and upgradeInfo.trackStringID then
					local categoryData = UPGRADE_CATEGORY_DATA[upgradeInfo.trackStringID]
					if categoryData and categoryData.tier then
						local icon = CreateAtlasMarkup('Professions-ChatIcon-Quality-Tier' .. categoryData.tier, 16, 16)
						-- Find and modify the item level line
						for i = 2, tooltip:NumLines() do
							local line = _G[tooltip:GetName() .. 'TextLeft' .. i]
							if line then
								local text = line:GetText()
								if text and text:find(ITEM_LEVEL:gsub('%%d', '%%d+')) then
									line:SetText(icon .. ' ' .. text)
									break
								end
							end
						end
					end
				end
			end
		end
	end
end

local TooltipSetUnit = function(self, data)
	if self ~= GameTooltip or self:IsForbidden() then
		return
	end

	local unit = select(2, self:GetUnit())
	if not unit or not (SUI.BlizzAPI.canaccessvalue(unit)) then
		return
	end

	local unitLevel = UnitLevel(unit)
	local className, classToken = UnitClass(unit)
	local colors, lvlColor, totColor, lvlLine
	local line = 2
	local creatureClassColors = {
		worldboss = format('|cffAF5050World Boss%s|r', BOSS),
		rareelite = format('|cffAF5050RARE-ELITE%s|r', ITEM_QUALITY3_DESC),
		elite = '|cffAF5050ELITE|r',
		rare = format('|cffAF5050RARE%s|r', ITEM_QUALITY3_DESC),
	}

	if UnitIsPlayer(unit) then
		local uName, uRealm = UnitName(unit)
		local gName, _, _, gRealm = GetGuildInfo(unit)
		local realmRelation = UnitRealmRelationship(unit)
		colors = _G.RAID_CLASS_COLORS[classToken]
		local nameString = UnitPVPName(unit) or uName

		if uRealm and uRealm ~= '' then
			local tmp = ''
			if gRealm ~= uRealm then
				tmp = ' ' .. uRealm
			end

			if realmRelation == LE_REALM_RELATION_COALESCED then
				nameString = nameString .. FOREIGN_SERVER_LABEL .. tmp
			elseif realmRelation == LE_REALM_RELATION_VIRTUAL then
				nameString = nameString .. INTERACTIVE_SERVER_LABEL .. tmp
			elseif gRealm ~= uRealm then
				nameString = nameString .. '-' .. uRealm
			end
		end

		if colors then
			if UnitIsAFK(unit) then
				GameTooltipTextLeft1:SetFormattedText('|cffFF0000%s|r |c%s%s|r', L['AFK'], colors.colorStr, nameString)
			elseif UnitIsDND(unit) then
				GameTooltipTextLeft1:SetFormattedText('|cffFFA500%s|r |c%s%s|r', L['DND'], colors.colorStr, nameString)
			else
				GameTooltipTextLeft1:SetFormattedText('|c%s%s|r', colors.colorStr, nameString)
			end
		else
			GameTooltipTextLeft1:SetText(nameString)
		end

		if gName then
			if gRealm then
				gName = gName .. '-' .. gRealm
			end
			GameTooltipTextLeft2:SetText(('|cff008000%s|r'):format(gName))

			-- GetInspectItemLevel is only available in Mainline/Retail
			local iLvl = ilvlTempData[uName .. '-' .. (uRealm or GetRealmName())]
			if not iLvl and C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
				iLvl = C_PaperDollInfo.GetInspectItemLevel('mouseover')
			end
			if iLvl == 0 then
				NotifyInspect('mouseover')
			elseif iLvl then
				self:AddLine(format('|cffFED000iLvl:|r %s', iLvl))
			end

			line = line + 1
		end

		if SUI:IsTimerunner() then
			local cloakData = C_UnitAuras.GetAuraDataBySpellName(unit, "Timerunner's Advantage")
			if cloakData ~= nil then
				local total = 0
				for i = 1, 9 do
					total = total + cloakData.points[i]
				end
				self:AddLine('\n|cff00FF98Threads |cffFFFFFF' .. SUI.Font:comma_value(total))
			end
		end
	end

	for i = 2, self:NumLines() do
		local tip = _G['GameTooltipTextLeft' .. i]
		if tip and tip:GetText() and tip:GetText():find(LEVEL) then
			lvlLine = tip
		end
	end

	if lvlLine then
		local creatureClassification = UnitClassification(unit)
		local creatureType = UnitCreatureType(unit)
		local race, englishRace = UnitRace(unit)
		local factionGroup = UnitFactionGroup(unit) or 'Neutral'

		race = (race or '') .. ' ' .. (className or '')
		if factionGroup and englishRace == 'Pandaren' then
			race = factionGroup .. ' ' .. race
		end
		if GENDER_INFO then
			if gender then
				race = race .. ' ' .. gender
			end
		end

		if UnitIsWildBattlePet and (UnitIsWildBattlePet(unit) or UnitIsBattlePetCompanion(unit)) then
			unitLevel = UnitBattlePetLevel(unit) ---@type integer
			local ab = C_PetJournal.GetPetTeamAverageLevel()
			if ab then
				lvlColor = GetRelativeDifficultyColor(ab, unitLevel)
			else
				lvlColor = GetQuestDifficultyColor(unitLevel)
			end
		else
			lvlColor = GetCreatureDifficultyColor(unitLevel)
		end
		if creatureType == nil then
			creatureType = ''
		end

		lvlLine:SetFormattedText(
			'|cff%02x%02x%02x%s|r %s %s',
			lvlColor.r * 255,
			lvlColor.g * 255,
			lvlColor.b * 255,
			unitLevel > 0 and unitLevel or '|TInterface\\TARGETINGFRAME\\UI-TargetingFrame-Skull.blp:16:16|t',
			race or creatureClassColors[creatureClassification] or '',
			creatureType
		)
	end

	local unitTarget = unit .. 'target'
	if unit ~= 'player' and UnitExists(unitTarget) then
		if UnitIsPlayer(unitTarget) and (SUI.IsRetail and not UnitHasVehicleUI(unitTarget)) then
			totColor = RAID_CLASS_COLORS[select(2, UnitClass(unitTarget))]
		else
			totColor = FACTION_BAR_COLORS[UnitReaction(unitTarget, 'player')]
		end
		self:AddDoubleLine(TARGET .. ':', format('|cff%02x%02x%02x%s|r', totColor.r * 255, totColor.g * 255, totColor.b * 255, UnitName(unitTarget)))
	end

	local inittest = IsInRaid() and 'raid1' or 'party1'
	if IsInGroup() and (SUI.BlizzAPI.canaccesstable(inittest)) then
		for i = 1, GetNumGroupMembers() do
			local groupedUnit = IsInRaid() and 'raid' .. i or 'party' .. i
			if UnitIsUnit(groupedUnit .. 'target', unit) then
				local _, classToken = UnitClass(groupedUnit)
				_G.tinsert(targetList, format('|c%s%s|r', RAID_CLASS_COLORS[classToken].colorStr, UnitName(groupedUnit)))
			end
		end
		local maxTargets = #targetList
		if maxTargets > 0 and targetList ~= nil then
			self:AddLine(format('%s (|cffffffff%d|r): %s', L['Targeted By'], maxTargets, table.concat(targetList, ', ')), nil, nil, nil, true)
			wipe(targetList)
		end
	end

	if self.NineSlice then
		SUI.Skins.RemoveTextures(self.NineSlice)
	end
end

local function ApplyTooltipSkins()
	GameTooltipStatusBarTexture:SetTexture('Interface\\AddOns\\SpartanUI\\images\\statusbars\\Smoothv2')

	GameTooltipStatusBar:ClearAllPoints()
	GameTooltipStatusBar:SetPoint('TOPLEFT', GameTooltip, 'BOTTOMLEFT', 0, 0)
	GameTooltipStatusBar:SetPoint('TOPRIGHT', GameTooltip, 'BOTTOMRIGHT', 0, 0)

	GameTooltipStatusBar.bg = GameTooltipStatusBar:CreateTexture(nil, 'BACKGROUND')
	GameTooltipStatusBar.bg:SetColorTexture(0.3, 0.3, 0.3, 0.6)
	GameTooltipStatusBar.bg:SetAllPoints(GameTooltipStatusBar)

	for i, tooltip in pairs(tooltips) do
		if not tooltip then
			return
		end
		ApplySkin(tooltip)
	end
end

function module:ZONE_CHANGED()
	ilvlTempData = {}
end

function module:INSPECT_READY()
	if UnitIsPlayer('mouseover') then
		local uName, uRealm = UnitName('mouseover')
		-- GetInspectItemLevel is only available in Mainline/Retail
		if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
			local ilvl = C_PaperDollInfo.GetInspectItemLevel('mouseover')
			if ilvl ~= 0 then
				ilvlTempData[uName .. '-' .. (uRealm or GetRealmName())] = ilvl
			end
		end
	end
end

function module:UpdateBG()
	for _, tooltip in pairs(tooltips) do
		if tooltip.SUITip and tooltip.SUITip.bgTexture then
			-- Update background texture
			local bgTexture = LSM:Fetch('background', module.DB.Background)
			if bgTexture and bgTexture ~= '' then
				tooltip.SUITip.bgTexture:SetTexture(bgTexture)
			else
				-- Fallback to solid color if texture not available
				tooltip.SUITip.bgTexture:SetColorTexture(0, 0, 0, 1)
			end

			-- Apply color based on settings
			local r, g, b, a = unpack(module.DB.Color)
			if module.DB.Background == 'none' or module.DB.ColorOverlay then
				-- Color overlay mode: apply user's color at full opacity (the color itself provides darkness)
				tooltip.SUITip.bgTexture:SetVertexColor(r, g, b, 1)
			else
				-- Standard mode: show texture as-is with user's alpha transparency
				-- Use black as fallback if texture doesn't exist to prevent white backgrounds
				if bgTexture and bgTexture ~= '' then
					tooltip.SUITip.bgTexture:SetVertexColor(1, 1, 1, a)
				else
					tooltip.SUITip.bgTexture:SetVertexColor(0, 0, 0, a)
				end
			end
		end

		if tooltip.NineSlice then
			SUI.Skins.RemoveTextures(tooltip.NineSlice)
		end

		-- Update CompareHeader color if it exists
		if tooltip.CompareHeader and tooltip.CompareHeader.SUIBackground then
			local r, g, b = unpack(module.DB.Color)
			tooltip.CompareHeader.SUIBackground:SetVertexColor(r, g, b, 1)
		end
	end

	-- Update any active LibQTip tooltips
	local LibQTip = SUI.Lib.LibQTip
	if LibQTip then
		for key, tooltip in LibQTip:TooltipPairs() do
			if tooltip.SUITip and tooltip.SUITip.bgTexture then
				local bgTexture = LSM:Fetch('background', module.DB.Background)
				if bgTexture and bgTexture ~= '' then
					tooltip.SUITip.bgTexture:SetTexture(bgTexture)
				else
					tooltip.SUITip.bgTexture:SetColorTexture(0, 0, 0, 1)
				end

				local r, g, b, a = unpack(module.DB.Color)
				if module.DB.Background == 'none' or module.DB.ColorOverlay then
					tooltip.SUITip.bgTexture:SetVertexColor(r, g, b, 1)
				else
					if bgTexture and bgTexture ~= '' then
						tooltip.SUITip.bgTexture:SetVertexColor(1, 1, 1, a)
					else
						tooltip.SUITip.bgTexture:SetVertexColor(0, 0, 0, a)
					end
				end
			end
		end
	end
end

function module:OnEnable()
	module:BuildOptions()
	if SUI:IsModuleDisabled('Tooltips') then
		return
	end
	module:RegisterEvent('INSPECT_READY')
	module:RegisterEvent('ZONE_CHANGED')

	--Do Setup
	ApplyTooltipSkins()
	hooksecurefunc('GameTooltip_SetDefaultAnchor', setPoint)
	hooksecurefunc('GameTooltip_SetDefaultAnchor', function(tooltip)
		ApplySkin(tooltip)
	end)

	hooksecurefunc('SharedTooltip_SetBackdropStyle', function(self)
		ApplySkin(self)
	end)

	GameTooltip:HookScript('OnTooltipCleared', TipCleared)

	-- Skin LibQTip-2.0 tooltips automatically
	-- Note: Can't reuse ApplySkin() because LibQTip blocks HookScript calls,
	-- and RemoveTextures doesn't reach NineSlice child frames.
	local LibQTip = SUI.Lib.LibQTip
	if LibQTip then
		local function SkinLibQTip(tooltip)
			if not tooltip then
				return
			end

			-- Hide the NineSlice border (LibQTip uses TooltipBackdropTemplate)
			-- NineSlice is re-initialized on every acquisition, so we must hide it each time
			if tooltip.NineSlice then
				tooltip.NineSlice:Hide()
			end

			-- Clear any backdrop the tooltip has
			if tooltip.SetBackdrop then
				tooltip:SetBackdrop(nil)
			end

			-- Create SUITip child frame if it doesn't exist
			if not tooltip.SUITip then
				local SUITip = CreateFrame('Frame', nil, tooltip)
				SUITip:SetAllPoints(tooltip)
				SUITip:SetFrameLevel(tooltip:GetFrameLevel())

				-- Background texture
				SUITip.bgTexture = SUITip:CreateTexture(nil, 'BACKGROUND')
				SUITip.bgTexture:SetAllPoints(SUITip)

				-- Border (4-sided, same style as existing ApplySkin)
				SUITip.border = CreateFrame('Frame', nil, SUITip)
				SUITip.border:SetAllPoints(SUITip)
				SUITip.border:SetFrameLevel(SUITip:GetFrameLevel() + 1)

				local blank = 'Interface\\AddOns\\SpartanUI\\images\\blank.tga'
				--TOP
				SUITip.border[1] = SUITip.border:CreateTexture(nil, 'OVERLAY')
				SUITip.border[1]:SetPoint('TOPLEFT', SUITip, 'TOPLEFT')
				SUITip.border[1]:SetPoint('TOPRIGHT', SUITip, 'TOPRIGHT')
				SUITip.border[1]:SetHeight(2)
				SUITip.border[1]:SetTexture(blank)
				--BOTTOM
				SUITip.border[2] = SUITip.border:CreateTexture(nil, 'OVERLAY')
				SUITip.border[2]:SetPoint('BOTTOMLEFT', SUITip, 'BOTTOMLEFT')
				SUITip.border[2]:SetPoint('BOTTOMRIGHT', SUITip, 'BOTTOMRIGHT')
				SUITip.border[2]:SetHeight(2)
				SUITip.border[2]:SetTexture(blank)
				--RIGHT
				SUITip.border[3] = SUITip.border:CreateTexture(nil, 'OVERLAY')
				SUITip.border[3]:SetPoint('TOPRIGHT', SUITip, 'TOPRIGHT')
				SUITip.border[3]:SetPoint('BOTTOMRIGHT', SUITip, 'BOTTOMRIGHT')
				SUITip.border[3]:SetWidth(2)
				SUITip.border[3]:SetTexture(blank)
				--LEFT
				SUITip.border[4] = SUITip.border:CreateTexture(nil, 'OVERLAY')
				SUITip.border[4]:SetPoint('TOPLEFT', SUITip, 'TOPLEFT')
				SUITip.border[4]:SetPoint('BOTTOMLEFT', SUITip, 'BOTTOMLEFT')
				SUITip.border[4]:SetWidth(2)
				SUITip.border[4]:SetTexture(blank)

				SUITip.border:Hide()
				tooltip.SUITip = SUITip
			end

			-- Apply current theme settings to background
			local bgTexture = LSM:Fetch('background', module.DB.Background)
			if bgTexture and bgTexture ~= '' then
				tooltip.SUITip.bgTexture:SetTexture(bgTexture)
			else
				tooltip.SUITip.bgTexture:SetColorTexture(0, 0, 0, 1)
			end

			local r, g, b, a = unpack(module.DB.Color)
			if module.DB.Background == 'none' or module.DB.ColorOverlay then
				tooltip.SUITip.bgTexture:SetVertexColor(r, g, b, 1)
			else
				if bgTexture and bgTexture ~= '' then
					tooltip.SUITip.bgTexture:SetVertexColor(1, 1, 1, a)
				else
					tooltip.SUITip.bgTexture:SetVertexColor(0, 0, 0, a)
				end
			end

			tooltip.SUITip:Show()
		end

		-- Hook the PUBLIC QTip:AcquireTooltip (not TooltipManager's internal method)
		-- The internal method fires before ActiveTooltips is populated; the public one fires after
		hooksecurefunc(LibQTip, 'AcquireTooltip', function(self, key)
			local tooltip = LibQTip.TooltipManager.ActiveTooltips[key]
			SkinLibQTip(tooltip)
		end)

		-- Skin any already-active LibQTip tooltips
		for key, tooltip in LibQTip:TooltipPairs() do
			SkinLibQTip(tooltip)
		end
	end

	-- TooltipDataProcessor is Retail-only (10.0.2+), use old-style hooks for Classic
	if TooltipDataProcessor then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, TooltipSetItem)
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, TooltipSetUnit)
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, TooltipSetSpell)
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Mount, TooltipSetGeneric)
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Quest, TooltipSetGeneric)
	else
		-- Classic compatibility: use old-style tooltip hooks
		GameTooltip:HookScript('OnTooltipSetItem', TooltipSetItem)
		GameTooltip:HookScript('OnTooltipSetUnit', TooltipSetUnit)
		GameTooltip:HookScript('OnTooltipSetSpell', TooltipSetSpell)
	end
end

function module:BuildOptions()
	SUI.opt.args['Modules'].args['Tooltips'] = {
		type = 'group',
		name = L['Tooltips'],
		get = function(info)
			return module.DB[info[#info]]
		end,
		set = function(info, val)
			module.DB[info[#info]] = val
		end,
		disabled = function()
			return SUI:IsModuleDisabled(module)
		end,
		args = {
			Background = {
				name = L['Background'],
				type = 'select',
				order = 1,
				dialogControl = 'LSM30_Background',
				values = SUI.Lib.LSM:HashTable('background'),
			},
			color = {
				name = L['Color'],
				type = 'color',
				hasAlpha = true,
				order = 10,
				width = 'full',
				get = function(info)
					return unpack(module.DB.Color)
				end,
				set = function(info, r, g, b, a)
					module.DB.Color = { r, g, b, a }
					module:UpdateBG()
				end,
			},
			ColorOverlay = {
				name = L['Color Overlay'],
				type = 'toggle',
				order = 11,
				desc = L['Apply the color to the texture or put it over the texture'],
			},
			onMouse = {
				name = L['Display on mouse?'],
				type = 'toggle',
				order = 12,
				desc = L['TooltipOverrideDesc'],
			},
			spellIDGroup = {
				name = 'Spell/Item IDs',
				type = 'group',
				order = 20,
				inline = true,
				get = function(info)
					return module.DB.SpellID[info[#info]]
				end,
				set = function(info, val)
					module.DB.SpellID[info[#info]] = val
				end,
				args = {
					enabled = {
						name = 'Show Spell IDs',
						desc = 'Display spell IDs in tooltips',
						type = 'toggle',
						order = 1,
					},
					modifierKey = {
						name = 'Modifier Key',
						desc = 'Modifier key required to show spell IDs',
						type = 'select',
						order = 2,
						values = {
							NONE = 'Never',
							ALL = 'Always',
							SHIFT = 'Shift',
							CTRL = 'Ctrl',
							ALT = 'Alt',
						},
						disabled = function()
							return not module.DB.SpellID.enabled
						end,
					},
				},
			},
			upgradeQualityGroup = {
				name = L['Upgrade Quality Icons'],
				type = 'group',
				order = 25,
				inline = true,
				hidden = function()
					return not SUI.IsRetail
				end,
				get = function(info)
					return module.DB.UpgradeQualityIcons[info[#info]]
				end,
				set = function(info, val)
					module.DB.UpgradeQualityIcons[info[#info]] = val
				end,
				args = {
					enabled = {
						name = L['Show Upgrade Quality Icons'],
						desc = L['Display quality tier icons next to item level for upgradeable items'],
						type = 'toggle',
						order = 1,
						width = 'full',
					},
				},
			},
		},
	}
end
