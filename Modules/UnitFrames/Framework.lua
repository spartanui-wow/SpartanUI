---@class SUI
local SUI = SUI
local L, MoveIt = SUI.L, SUI.MoveIt
---@class SUI.UF : SUI.Module
local UF = SUI:NewModule('UnitFrames')
UF.DisplayName = L['Unit frames']
UF.description = 'CORE: SUI Unitframes'
UF.Core = true
UF.CurrentSettings = {}
UF.BuildDebug = false -- Set to true to enable verbose build logging

---@class SUI.UF.FramePositions
local UFPositionDefaults = {
	['player'] = 'BOTTOMRIGHT,UIParent,BOTTOM,-60,250',
	['pet'] = 'RIGHT,SUI_UF_player,BOTTOMLEFT,-60,0',
	['pettarget'] = 'RIGHT,SUI_UF_pet,LEFT,0,-5',
	['target'] = 'LEFT,SUI_UF_player,RIGHT,150,0',
	['targettarget'] = 'LEFT,SUI_UF_target,BOTTOMRIGHT,4,0',
	['targettargettarget'] = 'LEFT,SUI_UF_targettarget,RIGHT,4,0',
	['focus'] = 'BOTTOMLEFT,SUI_UF_target,TOP,0,30',
	['focustarget'] = 'BOTTOMLEFT,SUI_UF_focus,BOTTOMRIGHT,5,0',
	['boss'] = 'RIGHT,UIParent,RIGHT,-9,162',
	['party'] = 'TOPLEFT,UIParent,TOPLEFT,20,-40',
	['partypet'] = 'BOTTOMRIGHT,frame,BOTTOMLEFT,-2,0',
	['partytarget'] = 'LEFT,frame,RIGHT,2,0',
	['raid'] = 'TOPLEFT,UIParent,TOPLEFT,20,-40',
	['arena'] = 'RIGHT,UIParent,RIGHT,-366,191',
}
UF.Artwork = {}
UF.MountIds = {}

---@param msg string
---@param frame UnitId
---@param element string
function UF:debug(msg, frame, element)
	if UF.Log then
		UF.Log.debug((frame and frame .. '-' or '') .. (element and element .. '-' or '') .. msg)
	end
end

---Returns the path to the texture for the given LSM key, or the SUI default
---@param LSMKey string
---@return string
function UF:FindStatusBarTexture(LSMKey)
	local defaultTexture = 'Interface\\AddOns\\SpartanUI\\images\\statusbars\\Smoothv2'
	---@diagnostic disable-next-line: return-type-mismatch
	return SUI.Lib.LSM:Fetch('statusbar', LSMKey, false) or defaultTexture
end

---@param frameName UnitId
function UF:IsFriendlyFrame(frameName)
	local FriendlyFrame = {
		'player',
		'pet',
		'party',
		'partypet',
		'target',
		'targettarget',
	}
	if SUI:IsInTable(FriendlyFrame, frameName) or frameName:match('party') or frameName:match('raid') then
		return true
	end
	return false
end

---@param unit? UnitFrameName
function UF:PositionFrame(unit)
	local positionData = UFPositionDefaults
	-- If artwork is enabled load the art's position data if supplied
	local posData = UF.Style:Get(SUI.DB.Artwork.Style).positions
	if SUI:IsModuleEnabled('Artwork') and posData then
		positionData = SUI:CopyData(posData, UFPositionDefaults)
	end

	if unit then
		local UnitFrame = UF.Unit:Get(unit)
		local point, anchor, secondaryPoint, x, y = strsplit(',', positionData[unit])
		if not anchor then
			return
		end

		if UnitFrame.position then
			UnitFrame:position(point, anchor, secondaryPoint, x, y, false, true)
		else
			UnitFrame:ClearAllPoints()
			UnitFrame:SetPoint(point, anchor, secondaryPoint, x, y)
		end
	else
		for frameName, config in pairs(UF.Unit:GetBuiltFrameList()) do
			if not config.isChild then
				local UnitFrame = UF.Unit:Get(frameName)
				local point, anchor, secondaryPoint, x, y = strsplit(',', positionData[frameName])
				if not anchor then
					return
				end

				if UnitFrame.position then
					UnitFrame:position(point, anchor, secondaryPoint, x, y, false, true)
				else
					UnitFrame:ClearAllPoints()
					UnitFrame:SetPoint(point, anchor, secondaryPoint, x, y)
				end
			end
		end
	end
end

function UF:ResetSettings()
	--Reset the DB
	UF.DB.UserSettings[UF.DB.Style] = nil
	-- Trigger update
	UF:Update()
end

local function LoadDB()
	-- Load Default Settings
	UF.CurrentSettings = SUI:MergeData({}, UF.Unit.defaultConfigs)
	-- Import theme settings
	if SUI.DB.Styles[UF.DB.Style] and SUI.DB.Styles[UF.DB.Style].Frames then
		UF.CurrentSettings = SUI:MergeData(UF.CurrentSettings, SUI.DB.Styles[UF.DB.Style].Frames, true)
	elseif UF.Artwork[UF.DB.Style] then
		local skin = UF.Artwork[UF.DB.Style].skin
		UF.CurrentSettings = SUI:MergeData(UF.CurrentSettings, SUI.DB.Styles[skin].Frames, true)
	end

	-- Import player customizations
	UF.CurrentSettings = SUI:MergeData(UF.CurrentSettings, UF.DB.UserSettings[UF.DB.Style], true)

	SpartanUI.UFdefaultConfigs = UF.Unit.defaultConfigs
	SpartanUI.UFCurrentSettings = UF.CurrentSettings
end

function UF:OnInitialize()
	if SUI:IsModuleDisabled('UnitFrames') then
		return
	end

	if SUI.logger then
		UF.Log = SUI.logger:RegisterCategory('UnitFrames')
	end

	-- Setup Database
	local defaults = {
		profile = {
			Style = 'War',
			UserSettings = {
				['**'] = { ['**'] = { ['**'] = { ['**'] = { ['**'] = { ['**'] = {} } } } } },
			},
		},
	}
	UF.Database = SUI.SpartanUIDB:RegisterNamespace('UnitFrames', defaults)
	UF.DB = UF.Database.profile

	LoadDB()

	if SUI.IsRetail then
		for _, mountID in next, C_MountJournal.GetMountIDs() do
			local _, spellID = C_MountJournal.GetMountInfoByID(mountID)
			UF.MountIds[spellID] = spellID
		end
	end
end

function UF:OnEnable()
	if SUI:IsModuleDisabled('UnitFrames') then
		return
	end

	-- Spawn Frames
	UF:SpawnFrames()

	-- Register pet battle hiding for SUI_FramesAnchor (#542)
	-- This ensures unit frames hide during pet battles in MOP and other clients
	if SUI_FramesAnchor and RegisterStateDriver then
		-- Make SUI_FramesAnchor hide during pet battles
		-- Note: [petbattle] is a secure conditional that works in Classic clients with pet battles
		RegisterStateDriver(SUI_FramesAnchor, 'visibility', '[petbattle] hide; show')
		if SUI.logger then
			SUI.logger.debug('UnitFrames: Registered pet battle visibility driver for SUI_FramesAnchor')
		end
	end

	-- Build options
	UF.Options:Initialize()

	-- Put frames into their inital position
	UF:PositionFrame()

	-- Update group frames to ensure proper sizing before mover creation
	for unit, config in pairs(UF.Unit:GetBuiltFrameList()) do
		if config.IsGroup then
			local frame = UF.Unit:Get(unit)
			if frame then
				UF.Unit:Update(frame)
			end
		end
	end

	-- Create movers
	for unit, config in pairs(UF.Unit:GetBuiltFrameList()) do
		if not config.isChild then
			MoveIt:CreateMover(UF.Unit:Get(unit), unit, nil, nil, 'Unit frames')
		end
	end

	-- Register frame relationships for magnetism after movers are created
	if MoveIt.MagnetismManager then
		local positionData = UFPositionDefaults
		local posData = UF.Style:Get(SUI.DB.Artwork.Style).positions
		if SUI:IsModuleEnabled('Artwork') and posData then
			positionData = SUI:CopyData(posData, UFPositionDefaults)
		end

		for unit, config in pairs(UF.Unit:GetBuiltFrameList()) do
			if not config.isChild then
				local posString = positionData[unit]
				if posString then
					local _, anchor = strsplit(',', posString)
					if anchor and anchor ~= 'UIParent' then
						-- Convert anchor string to frame
						local anchorFrame = _G[anchor]
						if anchorFrame and anchorFrame.mover then
							local unitFrame = UF.Unit:Get(unit)
							if unitFrame and unitFrame.mover then
								MoveIt.MagnetismManager:RegisterFrameRelationship(unitFrame.mover, anchorFrame.mover)
							end
						end
					end
				end
			end
		end
	end

	-- Edit Mode integration (Retail only - TBC has incomplete EditModeManagerFrame)
	if EditModeManagerFrame and SUI.IsRetail then
		local CheckedItems = {}
		local frames = { ['boss'] = 'Boss', ['raid'] = 'Raid', ['arena'] = 'Arena', ['party'] = 'Party' }
		for k, v in pairs(frames) do
			EditModeManagerFrame.AccountSettings.SettingsContainer[v .. 'Frames'].Button:HookScript('OnClick', function(...)
				if EditModeManagerFrame.AccountSettings.SettingsContainer[v .. 'Frames']:IsControlChecked() then
					CheckedItems[k] = v
				else
					CheckedItems[k] = nil
				end

				SUI.MoveIt:MoveIt(k)
			end)
		end

		EditModeManagerFrame:HookScript('OnHide', function()
			for k, v in pairs(CheckedItems) do
				EditModeManagerFrame.AccountSettings.SettingsContainer[v .. 'Frames']:SetControlChecked(false)
				SUI.MoveIt:MoveIt(k)
			end
			MoveIt.MoverWatcher:Hide()
			MoveIt.MoveEnabled = false
		end)
	end

	-- Ensure Blizzard party/raid frames stay hidden even after roster updates
	-- Only hide frames that SUI is actually replacing (i.e. where the unit type is enabled)
	local partyEnabled = UF.CurrentSettings.party and UF.CurrentSettings.party.enabled
	local raidEnabled = UF.CurrentSettings.raid and UF.CurrentSettings.raid.enabled

	if partyEnabled or raidEnabled then
		local function EnsureBlizzardFramesHidden()
			if not InCombatLockdown() then
				pcall(function()
					if partyEnabled then
						if PartyFrame then
							PartyFrame:Hide()
							PartyFrame:SetAlpha(0)
						end
						if CompactPartyFrame then
							CompactPartyFrame:Hide()
							CompactPartyFrame:SetAlpha(0)
						end
					end
					if raidEnabled then
						if CompactRaidFrameManager then
							CompactRaidFrameManager:Hide()
							CompactRaidFrameManager:SetAlpha(0)
						end
						if CompactRaidFrameContainer then
							CompactRaidFrameContainer:Hide()
							CompactRaidFrameContainer:SetAlpha(0)
						end
					end
				end)
			end
		end

		-- Register GROUP_ROSTER_UPDATE on our own watcher to re-hide frames
		-- (in case other code tries to show them)
		local RosterWatcher = CreateFrame('Frame')
		RosterWatcher:SetScript('OnEvent', function()
			C_Timer.After(0.1, EnsureBlizzardFramesHidden) -- Small delay to let other code finish
		end)
		RosterWatcher:RegisterEvent('GROUP_ROSTER_UPDATE')
	end

	SUI:AddChatCommand('BuffDebug', function(args)
		local unit, spellId = strsplit(' ', args)

		if not spellId then
			SUI:Print('Please specify a SpellID')
			return
		end

		if not SUI.UF.MonitoredBuffs[unit] then
			SUI.UF.MonitoredBuffs[unit] = {}
		end

		for i, v in ipairs(SUI.UF.MonitoredBuffs[unit]) do
			if v == tonumber(spellId) then
				SUI:Print('Removed ' .. spellId .. ' from the list of monitored buffs')
				if UF.Log then
					UF.Log.info('Removed ' .. spellId .. ' from monitored buffs for ' .. unit)
				end
				table.remove(SUI.UF.MonitoredBuffs[unit], i)
				return
			end
		end

		table.insert(SUI.UF.MonitoredBuffs[unit], tonumber(spellId))
		SUI:Print('Added ' .. spellId .. ' to the list of monitored buffs')
		if UF.Log then
			UF.Log.info('Added ' .. spellId .. ' to monitored buffs for ' .. unit)
		end
	end, 'Add/Remove a spellID to the list of spells to debug')
end

function UF:Update()
	-- Capture group visibility before settings reload so style switches
	-- don't lose showSolo/showParty/showRaid (pre-existing bug fix)
	local prevGroupVis = {}
	for frameName, config in pairs(UF.Unit.defaultConfigs) do
		if config.config and config.config.IsGroup and UF.CurrentSettings[frameName] then
			prevGroupVis[frameName] = {
				showSolo = UF.CurrentSettings[frameName].showSolo,
				showParty = UF.CurrentSettings[frameName].showParty,
				showRaid = UF.CurrentSettings[frameName].showRaid,
				showPlayer = UF.CurrentSettings[frameName].showPlayer,
			}
		end
	end

	-- Refresh Settings
	LoadDB()

	-- Seed group visibility into the new style's UserSettings when not yet customized.
	-- This prevents party/raid frames from vanishing when switching to a style
	-- the user hasn't configured visibility for yet.
	local reloadNeeded = false
	for frameName, prev in pairs(prevGroupVis) do
		local us = UF.DB.UserSettings[UF.DB.Style]
		if us then
			local hasUserVis = us[frameName] and (us[frameName].showSolo ~= nil or us[frameName].showParty ~= nil or us[frameName].showRaid ~= nil)
			if not hasUserVis then
				if not us[frameName] then
					us[frameName] = {}
				end
				us[frameName].showSolo = prev.showSolo
				us[frameName].showParty = prev.showParty
				us[frameName].showRaid = prev.showRaid
				us[frameName].showPlayer = prev.showPlayer
				reloadNeeded = true
			end
		end
	end
	if reloadNeeded then
		LoadDB()
	end

	-- Update positions
	UF:PositionFrame()
	--Send Custom change event
	SUI.Event:SendEvent('UNITFRAME_STYLE_CHANGED')
	-- Update all display elements
	UF:UpdateAll()
end

---@param style string
function UF:SetActiveStyle(style)
	UF.Style:Change(style)
	UF.DB.Style = style

	-- Refersh Settings
	UF:Update()
end

---@param scale integer
function UF:ScaleFrames(scale)
	if SUI:IsModuleDisabled('MoveIt') then
		return
	end

	for unitName, config in pairs(UF.Unit:GetBuiltFrameList()) do
		if not config.isChild then
			local UFrame = UF.Unit:Get(unitName)
			if UFrame and UFrame.mover then
				local newScale = UFrame.mover.defaultScale * (scale + 0.08) -- Add .08 to use .92 (the default scale) as 1.
				UFrame:scale(newScale)
			end
		end
	end
end

SUI.UF = UF
