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
	['boss'] = 'RIGHT,UIParent,RIGHT,-366,162',
	['bosstarget'] = 'LEFT,SUI_UF_boss1,RIGHT,4,0',
	['party'] = 'CENTER,UIParent,CENTER,-540,110',
	['partypet'] = 'BOTTOMRIGHT,frame,BOTTOMLEFT,-2,0',
	['partytarget'] = 'LEFT,frame,RIGHT,2,0',
	['raid'] = 'CENTER,UIParent,CENTER,-465,110',
	['arena'] = 'RIGHT,UIParent,RIGHT,-366,191',
}
UF.Artwork = {}
UF.MountIds = {}

---@param msg string
---@param frame? UnitId
---@param element? string
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
	---@diagnostic disable-next-line: undefined-field
	if SUI:IsInTable(FriendlyFrame, frameName) or frameName:match('party') or frameName:match('raid') then
		return true
	end
	return false
end

---@param unit? UnitFrameName
function UF:PositionFrame(unit)
	local positionData = UFPositionDefaults
	-- If artwork is enabled load the art's position data if supplied
	local posData = UF.Style:Get(SUI:GetActiveStyle()).positions
	if SUI:IsModuleEnabled('Artwork') and posData then
		positionData = SUI:CopyData(posData, UFPositionDefaults)
	end

	if unit then
		local UnitFrame = UF.Unit:Get(unit)
		local point, anchor, secondaryPoint, x, y = strsplit(',', positionData[unit])
		if not anchor or not _G[anchor] then
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
			if not config.isChild and positionData[frameName] then
				local UnitFrame = UF.Unit:Get(frameName)
				local point, anchor, secondaryPoint, x, y = strsplit(',', positionData[frameName])
				if anchor and _G[anchor] then
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
end

---Get the active preset name for a given frame (resolves frame groups)
---@param frameName string
---@return string presetName
function UF:GetPresetForFrame(frameName)
	local groupLeader = UF.Preset:GetGroupLeader(frameName)
	return UF.Preset:GetActive(groupLeader)
end

function UF:ResetSettings()
	-- Reset user customizations for all active presets
	for groupLeader, _ in pairs(UF.Preset.FrameGroups) do
		local presetName = UF.Preset:GetActive(groupLeader)
		UF.DB.UserSettings[presetName] = nil
	end
	-- Trigger update
	UF:Update()
end

---Migrate from legacy single-style DB to per-frame preset system
local function MigrateFromLegacy()
	if UF.DB._presetMigrated then
		return
	end

	local oldStyle = UF.DB.Style
	if not oldStyle then
		UF.DB._presetMigrated = true
		return
	end

	if oldStyle == 'Grid' then
		-- Grid only had raid+party configs; other frames should use artwork style
		local artStyle = SUI:GetActiveStyle() or 'War'
		for groupLeader, _ in pairs(UF.Preset.FrameGroups) do
			if groupLeader == 'raid' or groupLeader == 'party' then
				UF.DB.Presets[groupLeader] = 'Grid'
			else
				UF.DB.Presets[groupLeader] = artStyle
			end
		end
		-- Move orphaned Grid user settings for non-group frames to the artwork style bucket
		local gridUS = UF.DB.UserSettings['Grid']
		if gridUS then
			for frameName, settings in pairs(gridUS) do
				if frameName ~= 'raid' and frameName ~= 'party' and type(settings) == 'table' and next(settings) then
					if not UF.DB.UserSettings[artStyle] then
						UF.DB.UserSettings[artStyle] = {}
					end
					if not UF.DB.UserSettings[artStyle][frameName] then
						UF.DB.UserSettings[artStyle][frameName] = settings
					end
				end
			end
		end
	else
		-- All frames used same style - map all groups to it
		-- Only need to explicitly set if different from the wildcard default ('War')
		if oldStyle ~= 'War' then
			for groupLeader, _ in pairs(UF.Preset.FrameGroups) do
				UF.DB.Presets[groupLeader] = oldStyle
			end
		end
	end

	UF.DB._presetMigrated = true

	if UF.Log then
		UF.Log.info('Migrated from legacy Style "' .. oldStyle .. '" to per-frame presets')
	end
end

---Load and merge settings per-frame based on each frame's active preset
local function LoadDB()
	-- Step 1: Start with hardcoded defaults for all frames
	UF.CurrentSettings = SUI:MergeData({}, UF.Unit.defaultConfigs)

	-- Step 2: For each frame, resolve its preset and merge config
	for frameName, _ in pairs(UF.Unit.defaultConfigs) do
		local groupLeader = UF.Preset:GetGroupLeader(frameName)
		local presetName = UF.Preset:GetActive(groupLeader)

		-- Merge preset config for this specific frame
		local presetFrames = SUI.ThemeRegistry:GetFrameConfigs(presetName)
		if presetFrames and presetFrames[frameName] then
			UF.CurrentSettings[frameName] = SUI:MergeData(UF.CurrentSettings[frameName], presetFrames[frameName], true)
		elseif UF.Artwork[presetName] then
			-- Fallback for aliased styles (e.g., ArcaneRed -> Arcane skin)
			local skin = UF.Artwork[presetName].skin
			local skinFrames = SUI.ThemeRegistry:GetFrameConfigs(skin)
			if skinFrames and skinFrames[frameName] then
				UF.CurrentSettings[frameName] = SUI:MergeData(UF.CurrentSettings[frameName], skinFrames[frameName], true)
			end
		end

		-- SpartanArt fallback: if preset doesn't define SpartanArt, inherit from global artwork theme
		local artStyle = SUI:GetActiveStyle()
		if artStyle and artStyle ~= presetName then
			local artFrames = SUI.ThemeRegistry:GetFrameConfigs(artStyle)
			if artFrames and artFrames[frameName] and artFrames[frameName].elements and artFrames[frameName].elements.SpartanArt then
				local presetHasArt = presetFrames and presetFrames[frameName] and presetFrames[frameName].elements and presetFrames[frameName].elements.SpartanArt
				if not presetHasArt then
					if not UF.CurrentSettings[frameName].elements then
						UF.CurrentSettings[frameName].elements = {}
					end
					UF.CurrentSettings[frameName].elements.SpartanArt = SUI:MergeData(UF.CurrentSettings[frameName].elements.SpartanArt or {}, artFrames[frameName].elements.SpartanArt, true)
				end
			end
		end

		-- Step 3: Merge user customizations for this preset+frame
		local userSettings = UF.DB.UserSettings[presetName]
		if userSettings and userSettings[frameName] then
			UF.CurrentSettings[frameName] = SUI:MergeData(UF.CurrentSettings[frameName], userSettings[frameName], true)
		end
	end

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
			Style = 'War', -- DEPRECATED: kept for migration detection
			Presets = {
				['**'] = 'War', -- AceDB wildcard: default all frame groups to 'War'
			},
			_presetMigrated = false,
			UserSettings = {
				['**'] = { ['**'] = { ['**'] = { ['**'] = { ['**'] = { ['**'] = {} } } } } },
			},
		},
	}
	UF.Database = SUI.SpartanUIDB:RegisterNamespace('UnitFrames', defaults)
	UF.DB = UF.Database.profile

	-- Register profile change callbacks with refresh method
	-- Register for sequential profile refresh with Update method
	SUI.DBM:RegisterSequentialProfileRefresh(UF, 'Update')

	-- Migrate from legacy single-style to per-frame presets
	MigrateFromLegacy()

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

	-- Load theme frame configs (must happen in OnEnable, after themes register in OnInitialize)
	LoadDB()

	-- Register presets from ThemeRegistry metadata
	UF.Preset:RegisterFromStyles()

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
				-- Resize holder to match calculated group size
				frame:SetSize(UF.Unit:GroupSize(unit))

				if UF.BuildDebug then
					local holderW, holderH = frame:GetSize()
					UF:debug('Group holder ' .. unit .. ' size after SetSize: ' .. holderW .. 'x' .. holderH)

					-- Log header size if it exists
					if frame.header then
						local headerW, headerH = frame.header:GetSize()
						UF:debug('  Header size: ' .. headerW .. 'x' .. headerH)
						-- Log first child frame size
						local child1 = frame.header:GetAttribute('child1')
						if child1 then
							local cw, ch = child1:GetSize()
							UF:debug('  Child1 size: ' .. cw .. 'x' .. ch)
						end
					end

					-- Log child frame sizes from holder.frames
					if frame.frames then
						UF:debug('  Child frames count: ' .. #frame.frames)
						for i, child in ipairs(frame.frames) do
							if i <= 3 then -- just first 3
								local cw, ch = child:GetSize()
								UF:debug('  frames[' .. i .. '] size: ' .. cw .. 'x' .. ch)
							end
						end
					end
				end
			end
		end
	end

	-- Create movers
	for unit, config in pairs(UF.Unit:GetBuiltFrameList()) do
		if not config.isChild then
			MoveIt:CreateMover(UF.Unit:Get(unit), unit, nil, nil, 'Unit frames')

			if UF.BuildDebug and config.IsGroup then
				local frame = UF.Unit:Get(unit)
				if frame and frame.mover then
					local mw, mh = frame.mover:GetSize()
					UF:debug('Mover for ' .. unit .. ' size: ' .. mw .. 'x' .. mh)
				end
			end
		end
	end

	-- Register frame relationships for magnetism after movers are created
	if MoveIt.MagnetismManager then
		local positionData = UFPositionDefaults
		local posData = UF.Style:Get(SUI:GetActiveStyle()).positions
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

	-- Prevent Blizzard's EditMode from showing movers for SUI-managed unit frames
	-- When user opens Blizzard's EditMode independently, uncheck SUI-managed frame types
	if EditModeManagerFrame and SUI.IsRetail then
		hooksecurefunc(EditModeManagerFrame, 'EnterEditMode', function()
			local frames = { 'Boss', 'Raid', 'Arena', 'Party' }
			for _, v in ipairs(frames) do
				local container = EditModeManagerFrame.AccountSettings
					and EditModeManagerFrame.AccountSettings.SettingsContainer
					and EditModeManagerFrame.AccountSettings.SettingsContainer[v .. 'Frames']
				if container and container.SetControlChecked then
					container:SetControlChecked(false)
				end
			end
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

	-- Seed group visibility into the new preset's UserSettings when not yet customized.
	-- This prevents party/raid frames from vanishing when switching to a preset
	-- the user hasn't configured visibility for yet.
	local reloadNeeded = false
	for frameName, prev in pairs(prevGroupVis) do
		local presetName = UF:GetPresetForFrame(frameName)
		local us = UF.DB.UserSettings[presetName]
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

---Set all frame presets to a theme's defaults (1-click theme application)
---@param style string
function UF:SetActiveStyle(style)
	UF.Style:Change(style)
	UF.Preset:ApplyThemeDefaults(style)

	-- Refresh Settings
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
