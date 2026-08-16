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
	['raid10'] = 'CENTER,UIParent,CENTER,-465,110',
	['raid25'] = 'CENTER,UIParent,CENTER,-465,110',
	['raid40'] = 'CENTER,UIParent,CENTER,-465,110',
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

	-- Check if Style was explicitly set by user (not just the default 'War')
	-- On fresh installs, the raw DB won't have Style stored
	local rawProfile = UF.Database and UF.Database.profile
	local hasExplicitStyle = rawProfile and rawget(rawProfile, 'Style') ~= nil
	if not hasExplicitStyle then
		return
	end

	local oldStyle = UF.DB.Style
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
	elseif oldStyle ~= 'War' then
		-- All frames used same style - map all groups to it
		for groupLeader, _ in pairs(UF.Preset.FrameGroups) do
			UF.DB.Presets[groupLeader] = oldStyle
		end
	end

	UF.DB._presetMigrated = true
	UF.DB.Style = nil

	if UF.Log then
		UF.Log.info('Migrated from legacy Style "' .. tostring(oldStyle) .. '" to per-frame presets')
	end
end

---Rename aura group and tracked spell keys from '1' to slot1.
---
---Numeric-looking string keys survive a round trip through SavedVariables
---only as long as nothing normalises them to real numbers. Word keys cannot
---be normalised, so saved settings are moved onto them once.
local function MigrateAuraSlotKeys()
	if UF.DB._auraSlotKeysMigrated then
		return
	end

	local renamed = 0

	for presetName, frames in pairs(UF.DB.UserSettings) do
		if presetName ~= '**' and type(frames) == 'table' then
			for frameName, frameSettings in pairs(frames) do
				local elements = frameName ~= '**' and type(frameSettings) == 'table' and frameSettings.elements

				if type(elements) == 'table' then
					-- Only the tracker keys its entries by index; the aura
					-- containers never did, so nothing there needs renaming.
					for elementName, collection in pairs({
						AuraTracker = type(elements.AuraTracker) == 'table' and elements.AuraTracker.entries,
					}) do
						if type(collection) == 'table' then
							for index = 1, 12 do
								local old = tostring(index)
								local new = 'slot' .. index
								if collection[old] ~= nil and collection[new] == nil then
									collection[new] = collection[old]
									collection[old] = nil
									renamed = renamed + 1
								end
							end
						end
					end
				end
			end
		end
	end

	UF.DB._auraSlotKeysMigrated = true

	if UF.Log and renamed > 0 then
		UF.Log.info('Moved ' .. renamed .. ' aura entries onto named keys')
	end
end

---Move saved aura settings onto the per-type containers.
---
---Two generations are handled at once, because a profile can be at either:
---the original Buffs/Debuffs elements, and the single AuraGroups container
---that briefly replaced them. Both end up at BuffContainer/DebuffContainer/
---CustomAuras, which is one container per aura type again.
---
---Settings that still mean the same thing move across. Ones with no
---equivalent are left behind rather than guessed at: the Classic rule tables
---and whitelist/blacklist have no counterpart now that Blizzard does the
---filtering.
local function MigrateAuraContainers()
	if not SUI.IsRetail or UF.DB._auraContainersMigrated then
		return
	end

	-- Keys that mean the same thing on a container as they did on a group or
	-- on the old Buffs/Debuffs elements.
	local carried = {
		'enabled',
		'number',
		'size',
		'spacing',
		'perRow',
		'filterMode',
		'customFilter',
		'sortMethod',
		'sortDirection',
		'clickThrough',
		'showDebuffBorder',
		'showBuffBorder',
		'showBuffIndicator',
		'showDebuffIndicator',
		'showStealableBorder',
		'dispelBorderStyle',
		'showCount',
		'showDuration',
		'showCooldown',
		'onlyStealable',
		'maxDuration',
		'includeSpellIDs',
		'excludeSpellIDs',
		'durationText',
		'stackText',
		'expiring',
	}

	local migrated = 0

	---Copy the settings that still apply from one table onto a container.
	local function carry(target, source)
		if type(source) ~= 'table' then
			return
		end

		for _, key in ipairs(carried) do
			if source[key] ~= nil and target[key] == nil then
				target[key] = source[key]
			end
		end

		-- "Only mine" became the absence of the others variant.
		if source.onlyMine and target.showOthers == nil then
			target.showOthers = false
		end

		migrated = migrated + 1
	end

	for presetName, frames in pairs(UF.DB.UserSettings) do
		if presetName ~= '**' and type(frames) == 'table' then
			for frameName, frameSettings in pairs(frames) do
				local elements = frameName ~= '**' and type(frameSettings) == 'table' and frameSettings.elements

				if type(elements) == 'table' then
					local groups = type(elements.AuraGroups) == 'table' and elements.AuraGroups or nil

					local mapping = {
						{ target = 'BuffContainer', group = 'slot1', legacy = 'Buffs' },
						{ target = 'DebuffContainer', group = 'slot2', legacy = 'Debuffs' },
						{ target = 'CustomAuras', group = 'slot3' },
					}

					for _, entry in ipairs(mapping) do
						local groupDB = groups and type(groups.groups) == 'table' and groups.groups[entry.group] or nil
						local legacyDB = entry.legacy and type(elements[entry.legacy]) == 'table' and elements[entry.legacy] or nil

						if groupDB or legacyDB then
							elements[entry.target] = elements[entry.target] or {}
							local target = elements[entry.target]

							-- The group generation is newer, so it wins where
							-- both describe the same setting.
							carry(target, groupDB)
							carry(target, legacyDB)

							-- Position and growth were container-wide under
							-- AuraGroups; each container owns its own now, so
							-- both start where the shared one was and can be
							-- moved apart afterwards.
							local source = groupDB or legacyDB
							if groups then
								if groups.growthx and target.growthx == nil then
									target.growthx = groups.growthx
								end
								if groups.growthy and target.growthy == nil then
									target.growthy = groups.growthy
								end
								if type(groups.position) == 'table' and target.position == nil then
									target.position = SUI:CopyData({}, groups.position)
								end
								if groups.width and target.width == nil then
									target.width = groups.width
								end
							end

							-- The old elements carried their own growth and
							-- position, which is exactly what we want back.
							if type(source) == 'table' then
								if source.growthx then
									target.growthx = source.growthx
								end
								if source.growthy then
									target.growthy = source.growthy
								end
								if type(source.position) == 'table' then
									target.position = SUI:CopyData({}, source.position)
								end
								-- Rows became icons per row.
								if type(source.rows) == 'number' and source.rows > 1 and type(source.number) == 'number' then
									target.perRow = math.ceil(source.number / source.rows)
								end
							end
						end
					end

					-- The shared container is gone; leaving it would keep
					-- feeding a dead element name into the options tree.
					elements.AuraGroups = nil
				end
			end
		end
	end

	UF.DB._auraContainersMigrated = true

	if UF.Log and migrated > 0 then
		UF.Log.info('Moved ' .. migrated .. ' aura configs onto their own containers')
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
		elseif presetFrames and frameName:match('^raid%d+$') and presetFrames['raid'] then
			-- Legacy fallback: old themes defining 'raid' apply to all raid tiers
			UF.CurrentSettings[frameName] = SUI:MergeData(UF.CurrentSettings[frameName], presetFrames['raid'], true)
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
			-- For raid tiers, fall back to 'raid' key if tier-specific key doesn't exist in art theme
			local artFrameKey = frameName
			if frameName:match('^raid%d+$') and artFrames and not artFrames[frameName] and artFrames['raid'] then
				artFrameKey = 'raid'
			end
			if artFrames and artFrames[artFrameKey] and artFrames[artFrameKey].elements and artFrames[artFrameKey].elements.SpartanArt then
				local presetHasArt = presetFrames and presetFrames[frameName] and presetFrames[frameName].elements and presetFrames[frameName].elements.SpartanArt
				if not presetHasArt then
					if not UF.CurrentSettings[frameName].elements then
						UF.CurrentSettings[frameName].elements = {}
					end
					UF.CurrentSettings[frameName].elements.SpartanArt = SUI:MergeData(UF.CurrentSettings[frameName].elements.SpartanArt or {}, artFrames[artFrameKey].elements.SpartanArt, true)
				end
			end
		end

		-- Step 3: Merge user customizations for this preset+frame
		local userSettings = UF.DB.UserSettings[presetName]
		if userSettings and userSettings[frameName] then
			UF.CurrentSettings[frameName] = SUI:MergeData(UF.CurrentSettings[frameName], userSettings[frameName], true)
		elseif userSettings and frameName:match('^raid%d+$') and userSettings['raid'] and not userSettings[frameName] then
			-- Migration bridge: apply old 'raid' user settings to tier-specific keys
			UF.CurrentSettings[frameName] = SUI:MergeData(UF.CurrentSettings[frameName], userSettings['raid'], true)
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
			UserSettings = {
				['**'] = { ['**'] = { ['**'] = { ['**'] = { ['**'] = { ['**'] = {} } } } } },
			},
			Colors = {
				powerTypes = {},
				reactionColors = {},
			},
		},
	}
	UF.Database = SUI.SpartanUIDB:RegisterNamespace('UnitFrames', defaults)
	UF.DB = UF.Database.profile

	SUI.DBM:RegisterSequentialProfileRefresh(UF)

	-- Migrate from legacy single-style to per-frame presets
	MigrateFromLegacy()

	-- Carry Buffs/Debuffs customisations over to the new aura group element
	MigrateAuraContainers()
	MigrateAuraSlotKeys()

	-- Migrate from single 'raid' to per-tier raid types (raid10/raid25/raid40)
	if UF.DB.UserSettings then
		for presetName, presetSettings in pairs(UF.DB.UserSettings) do
			if type(presetSettings) == 'table' and presetSettings.raid and not presetSettings.raid10 then
				-- Copy existing raid settings as base for all tiers
				presetSettings.raid10 = SUI:CopyData({}, presetSettings.raid)
				presetSettings.raid25 = SUI:CopyData({}, presetSettings.raid)
				presetSettings.raid40 = SUI:CopyData({}, presetSettings.raid)
				-- Apply old raidTier overrides if they existed
				if presetSettings.raid.raidTiers then
					local tiers = presetSettings.raid.raidTiers
					if tiers.small then
						SUI:MergeData(presetSettings.raid10, tiers.small, true)
					end
					if tiers.medium then
						SUI:MergeData(presetSettings.raid25, tiers.medium, true)
					end
					if tiers.large then
						SUI:MergeData(presetSettings.raid40, tiers.large, true)
					end
				end
				presetSettings.raid = nil
			end
		end
	end
	-- Collapse per-group preset entries into _default when they all match.
	-- Older profiles stored the same preset name under every frame group
	-- (player, target, raid, ...). Reduce to a single _default entry so the
	-- saved variables stay sparse.
	if UF.DB.Presets then
		local sample, allMatch = nil, true
		local groupCount = 0
		for groupLeader, _ in pairs(UF.Preset.FrameGroups) do
			local stored = rawget(UF.DB.Presets, groupLeader)
			if stored then
				groupCount = groupCount + 1
				if sample == nil then
					sample = stored
				elseif stored ~= sample then
					allMatch = false
					break
				end
			else
				-- Missing entry would already fall through to _default; skip
			end
		end
		if allMatch and sample and groupCount >= 2 then
			local existingDefault = rawget(UF.DB.Presets, '_default')
			if not existingDefault or existingDefault == sample then
				UF.DB.Presets['_default'] = sample
				for groupLeader, _ in pairs(UF.Preset.FrameGroups) do
					UF.DB.Presets[groupLeader] = nil
				end
			end
		end
	end

	-- Repair: previous migration incorrectly deleted Presets.raid (the group leader key).
	-- Restore it from the tier-specific keys that were created.
	if UF.DB.Presets and not UF.DB.Presets.raid then
		UF.DB.Presets.raid = UF.DB.Presets.raid40 or UF.DB.Presets.raid25 or UF.DB.Presets.raid10
		UF.DB.Presets.raid10 = nil
		UF.DB.Presets.raid25 = nil
		UF.DB.Presets.raid40 = nil
	end

	-- Only the Classic aura path checks this map; Retail filters auras engine
	-- side and never reads it. Building it there means a journal lookup per
	-- collected mount at every login for nothing.
	if not SUI.IsRetail then
		UF:BuildMountList()
	end
end

---Collect the spell IDs of every mount, for the "show mounts" aura filter.
---
---This is a journal lookup per collected mount, which on a full collection is
---hundreds of calls, so it is built on demand and only once.
---@return table<number, number>
function UF:BuildMountList()
	if UF.MountIdsBuilt then
		return UF.MountIds
	end

	if C_MountJournal and C_MountJournal.GetMountIDs then
		for _, mountID in next, C_MountJournal.GetMountIDs() do
			local _, spellID = C_MountJournal.GetMountInfoByID(mountID)
			if spellID then
				UF.MountIds[spellID] = spellID
			end
		end

		UF.MountIdsBuilt = true
	end

	return UF.MountIds
end

-- Apply user color overrides to oUF's color tables
function UF:ApplyColorOverrides()
	if not UF.DB or not UF.DB.Colors then
		return
	end

	local colors = UF.DB.Colors

	-- Apply per-power-type color overrides
	if colors.powerTypes then
		for token, colorTable in pairs(colors.powerTypes) do
			if SUIUF and SUIUF.colors and SUIUF.colors.power then
				SUIUF.colors.power[token] = SUIUF:CreateColor(colorTable[1], colorTable[2], colorTable[3])
			end
		end
	end

	-- Apply per-reaction color overrides
	if colors.reactionColors then
		for level, colorTable in pairs(colors.reactionColors) do
			if SUIUF and SUIUF.colors and SUIUF.colors.reaction then
				SUIUF.colors.reaction[tonumber(level)] = SUIUF:CreateColor(colorTable[1], colorTable[2], colorTable[3])
			end
		end
	end
end

function UF:OnEnable()
	if SUI:IsModuleDisabled('UnitFrames') then
		return
	end

	-- Load theme frame configs (must happen in OnEnable, after themes register in OnInitialize)
	LoadDB()

	-- Apply user color customizations to oUF
	UF:ApplyColorOverrides()

	-- Register presets from ThemeRegistry metadata
	UF.Preset:RegisterFromStyles()

	-- Compute raid tier visibility conditions before spawning
	if UF.GetRaidTierVisibility then
		for _, tierName in ipairs({ 'raid10', 'raid25', 'raid40' }) do
			if UF.CurrentSettings[tierName] then
				UF.CurrentSettings[tierName].customVisibility = UF:GetRaidTierVisibility(tierName)
			end
		end
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

	-- Build options (must happen after movers are created so AddPosition can reference them)
	UF.Options:Initialize()

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

	-- Suppress Blizzard party/raid frames that SUI replaces
	local partyEnabled = UF.CurrentSettings.party and UF.CurrentSettings.party.enabled
	local raidEnabled = (UF.CurrentSettings.raid10 and UF.CurrentSettings.raid10.enabled)
		or (UF.CurrentSettings.raid25 and UF.CurrentSettings.raid25.enabled)
		or (UF.CurrentSettings.raid40 and UF.CurrentSettings.raid40.enabled)

	if partyEnabled or raidEnabled then
		local BlizzardHider = CreateFrame('Frame', 'SUI_BlizzardHider', UIParent)
		BlizzardHider:SetAllPoints()
		BlizzardHider:Hide()

		local MEMBERS_PER_RAID_GROUP = _G.MEMBERS_PER_RAID_GROUP or 5
		local blizzardRaidDisabled = false
		local blizzardSetUnitHooked = false

		local function DisableBlizzardRaidFrames()
			if blizzardRaidDisabled then
				return
			end
			blizzardRaidDisabled = true

			-- Suppress CompactRaidFrameContainer via reparent + hooks
			-- Do NOT hide CompactRaidFrameManager - preserves raid tools slide-out
			if CompactRaidFrameContainer then
				CompactRaidFrameContainer:UnregisterAllEvents()
				CompactRaidFrameContainer:Hide()
				CompactRaidFrameContainer:SetParent(BlizzardHider)

				if not CompactRaidFrameContainer.__suiSetParentHooked then
					CompactRaidFrameContainer.__suiSetParentHooked = true
					hooksecurefunc(CompactRaidFrameContainer, 'SetParent', function(self, parent)
						if parent ~= BlizzardHider then
							self:SetParent(BlizzardHider)
						end
					end)
				end

				if not CompactRaidFrameContainer.__suiShowHooked then
					CompactRaidFrameContainer.__suiShowHooked = true
					hooksecurefunc(CompactRaidFrameContainer, 'Show', function(self)
						if not InCombatLockdown() then
							self:Hide()
						end
					end)
				end
			end

			-- Tell Blizzard to stop showing raid frames (sets container.enabled = false)
			-- Does NOT hide the manager or raid tools slide-out
			if CompactRaidFrameManager_SetSetting then
				pcall(CompactRaidFrameManager_SetSetting, 'IsShown', '0')
			end

			-- Hook CompactUnitFrame_SetUnit to suppress newly created raid frames
			if not blizzardSetUnitHooked and CompactUnitFrame_SetUnit then
				blizzardSetUnitHooked = true
				hooksecurefunc('CompactUnitFrame_SetUnit', function(frame, unit)
					if not frame or not raidEnabled then
						return
					end
					if InCombatLockdown() then
						return
					end
					-- Only process valid WoW frames with GetParent; nameplates and other
					-- non-frame objects also trigger CompactUnitFrame_SetUnit.
					if type(frame) ~= 'table' or type(frame.GetParent) ~= 'function' then
						return
					end
					local ok, parent = pcall(frame.GetParent, frame)
					if not ok then
						return
					end
					while parent do
						if parent == CompactRaidFrameContainer then
							frame:UnregisterAllEvents()
							frame:Hide()
							return
						end
						ok, parent = pcall(parent.GetParent, parent)
						if not ok then
							return
						end
					end
				end)
			end

			-- Disable existing CompactRaidFrame instances
			for i = 1, 40 do
				local frame = _G['CompactRaidFrame' .. i]
				if frame then
					frame:UnregisterAllEvents()
					frame:Hide()
				end
			end
			for i = 1, 8 do
				local group = _G['CompactRaidGroup' .. i]
				if group then
					group:Hide()
					for j = 1, MEMBERS_PER_RAID_GROUP do
						local member = _G['CompactRaidGroup' .. i .. 'Member' .. j]
						if member then
							member:UnregisterAllEvents()
							member:Hide()
						end
					end
				end
			end
		end

		local function ReEnforceBlizzardHiding()
			if InCombatLockdown() then
				return
			end

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
					-- Re-enforce container suppression
					if CompactRaidFrameContainer then
						CompactRaidFrameContainer:Hide()
					end
					-- Iterate any frames Blizzard may have re-created
					for i = 1, 40 do
						local frame = _G['CompactRaidFrame' .. i]
						if frame then
							frame:UnregisterAllEvents()
							frame:Hide()
						end
					end
				end
			end)
		end

		-- Initial suppression
		if raidEnabled then
			DisableBlizzardRaidFrames()
		end
		if partyEnabled then
			ReEnforceBlizzardHiding()
		end

		-- Watcher to re-enforce suppression on roster changes, zone changes, and combat end
		local BlizzardWatcher = CreateFrame('Frame')
		BlizzardWatcher:SetScript('OnEvent', function()
			C_Timer.After(0.1, ReEnforceBlizzardHiding)
		end)
		BlizzardWatcher:RegisterEvent('GROUP_ROSTER_UPDATE')
		BlizzardWatcher:RegisterEvent('PLAYER_ENTERING_WORLD')
		BlizzardWatcher:RegisterEvent('PLAYER_REGEN_ENABLED')
	end

	SUI:AddChatCommand('auradebug', function(args)
		local frameName = (args and args ~= '' and args) or 'player'
		local frame = UF.Unit and UF.Unit:Get(frameName)

		-- An aura container carries secret anchors, which spread to anything
		-- derived from them - IsShown, GetAlpha, GetWidth, GetNumPoints. tostring
		-- on a secret errors, so every value read off the container goes through
		-- here rather than straight into a message.
		local function show(value)
			if not SUI.BlizzAPI.canaccessvalue(value) then
				return '<secret>'
			end
			return tostring(value)
		end

		---Call a method and report the result without erroring on a secret.
		local function get(object, method, ...)
			if not object or not object[method] then
				return '<no ' .. method .. '>'
			end
			local ok, result = pcall(object[method], object, ...)
			if not ok then
				return '<errored>'
			end
			return show(result)
		end

		if not frame then
			SUI:Print('No frame called ' .. frameName)
			return
		end

		SUI:Print('|cff00FF98Aura state for ' .. frameName .. '|r')
		SUI:Print('  unit: ' .. show(frame.unit) .. '   built: ' .. show(frame.IsBuilt))

		local element = frame.BuffContainer
		if not element then
			SUI:Print('  |cffFF5252no BuffContainer element|r - the frame did not build one')
			SUI:Print('  native containers available: ' .. tostring(UF.Auras:HasNativeContainers()))
			return
		end

		-- Count every aura container parented to this frame. There should be
		-- one per aura element; more than that means a build created extra
		-- ones, and each draws its own copy of every aura.
		do
			local containers, names = 0, {}
			for _, child in ipairs({ frame:GetChildren() }) do
				if child.AddAuraGroup or child.AddSlot then
					containers = containers + 1
					names[#names + 1] = (child.GetName and child:GetName()) or '?'
				end
			end
			local expected = (frame.BuffContainer and 1 or 0) + (frame.DebuffContainer and 1 or 0) + (frame.CustomAuras and 1 or 0) + (frame.AuraTracker and 1 or 0)
			for _ in pairs(frame.auraWatchers or {}) do
				expected = expected + 1
			end
			SUI:Print(('  aura containers on this frame: %d (expected %d)%s'):format(containers, expected, containers > expected and '  |cffFF5252<- EXTRA CONTAINERS|r' or ''))
			SUI:Print('    ' .. table.concat(names, ', '))

			-- Which container is actually drawing. A container with no unit
			-- shows nothing, so if auras are on screen while the buff
			-- container has no unit, another container is drawing them.
			for _, child in ipairs({ frame:GetChildren() }) do
				if child.AddAuraGroup or child.AddSlot then
					local label = (child.GetName and child:GetName()) or '?'
					local role = (child == frame.BuffContainer and 'BuffContainer')
						or (child == frame.DebuffContainer and 'DebuffContainer')
						or (child == frame.CustomAuras and 'CustomAuras')
						or (child == frame.AuraTracker and 'AuraTracker')
						or 'watcher/other'
					-- Name the watcher, and count the buttons it has actually
					-- built. A per-spell watcher should own exactly one.
					if role == 'watcher/other' then
						for watcherName, watcher in pairs(frame.auraWatchers or {}) do
							if watcher.container == child then
								role = 'watcher:' .. watcherName .. ' buttons=' .. #(watcher.buttons or {})
							end
						end
					end
					SUI:Print(('    %s [%s] unit=%s shown=%s'):format(label, role, get(child, 'GetUnit'), get(child, 'IsShown')))
				end
			end
		end

		-- Per container: what it is enabled to, and the live filter each of its
		-- variants is pointed at. Two containers drawing the same aura will
		-- show the same filter string here.
		for _, name in ipairs({ 'BuffContainer', 'DebuffContainer', 'CustomAuras' }) do
			local c = frame[name]
			if c then
				local db = c.DB or {}
				-- Where the enabled flag comes from matters: a value in the
				-- user table is a saved setting, otherwise it is the default.
				local preset = UF:GetPresetForFrame(frameName)
				local userTbl = UF.DB.UserSettings[preset]
				userTbl = userTbl and userTbl[frameName]
				userTbl = userTbl and userTbl.elements
				userTbl = userTbl and userTbl[name]
				local userEnabled = type(userTbl) == 'table' and userTbl.enabled

				SUI:Print(
					('  %s: enabled=%s (saved=%s) base=%s filterMode=%s showOthers=%s'):format(name, show(db.enabled), show(userEnabled), show(c.baseFilter), show(db.filterMode), show(db.showOthers))
				)
				for _, variant in ipairs({ 'player', 'others' }) do
					local key = c.groupKeys and c.groupKeys[variant]
					if key then
						local live = UF.Auras:GetVariantFilter(db, c.baseFilter, variant)
						local off = not UF.Auras:IsVariantEnabled(db, c.baseFilter, variant)
						local appliedMax = c.variantFrameCounts and c.variantFrameCounts[variant]
						SUI:Print(('     %s -> %s   applied max: %s'):format(variant, off and 'disabled' or live:gsub('|', '||'), show(appliedMax)))
					end
				end
			end
		end

		SUI:Print('  container exists, enabled setting: ' .. show(element.DB and element.DB.enabled))
		SUI:Print('  container unit: ' .. get(element, 'GetUnit'))
		SUI:Print('  shown: ' .. get(element, 'IsShown') .. '   alpha: ' .. get(element, 'GetAlpha'))

		local points = element:GetNumPoints()
		if not SUI.BlizzAPI.canaccessvalue(points) then
			SUI:Print('  anchoring is secret on this container, cannot be read')
		elseif points > 0 then
			-- IsAnchoringRestricted answers this directly on 12.1; the pcall is
			-- the fallback for clients that lack it.
			if element.IsAnchoringRestricted and element:IsAnchoringRestricted() then
				SUI:Print('  anchoring is restricted on this container, cannot be read')
				return
			end

			local ok, a, _, rp, x, y = pcall(element.GetPoint, element)
			if ok then
				SUI:Print(('  anchored: %s -> %s  offset %s,%s'):format(show(a), show(rp), show(x), show(y)))
			else
				SUI:Print('  anchored, but the points cannot be read')
			end
		else
			SUI:Print('  |cffFF5252not anchored|r - the container has no position')
		end

		SUI:Print(('  size: %sx%s   level: %s'):format(get(element, 'GetWidth'), get(element, 'GetHeight'), get(element, 'GetFrameLevel')))
		SUI:Print('  anchors secret: ' .. get(element, 'IsAnchoringSecret'))

		-- How the icons are meant to flow. A row that will not wrap shows up
		-- as a single column, so report what the layout was actually told.
		local DB = element.DB or {}
		SUI:Print(('  wrap width: %s   (width=%s layoutLimit=%s)'):format(tostring(UF.Auras:GetLayoutLimit(DB, frame)), tostring(DB.width), tostring(DB.layoutLimit)))
		SUI:Print(('  growth: %s / %s'):format(tostring(DB.growthx), tostring(DB.growthy)))

		-- Whether the line size can be changed after the container is built is
		-- the open question: oUF only ever sets it in Create. If the live value
		-- does not match what we asked for, it is create-time only and the
		-- setting needs a rebuild rather than an update.
		if element.GetFlowLayoutMaximumLineSize then
			local live = get(element, 'GetFlowLayoutMaximumLineSize')
			local want = show(UF.Auras:GetLayoutLimit(DB, frame))
			SUI:Print(('  live line size: %s   wanted: %s   %s'):format(live, want, live == want and '|cff00FF98match|r' or '|cffFF5252MISMATCH|r'))
		end

		for _, method in ipairs({ 'GetFlowLayoutMaximumLineSize', 'GetFlowLayoutAxis', 'GetFlowLayoutGrowthDirection', 'GetFlowLayoutAnchorPoint' }) do
			SUI:Print(('  %s: %s'):format(method:gsub('GetFlowLayout', ''), get(element, method)))
		end

		for index = 1, UF.Auras.MAX_GROUPS do
			local group = UF.Auras:ResolveGroup(element.DB or {}, index)
			local key = element.groupKeys and element.groupKeys[index]
			if group.enabled or key then
				SUI:Print(('  group %d: %s  enabled=%s  filter=%s  key=%s'):format(
					index,
					tostring(group.name ~= '' and group.name or '-'),
					tostring(group.enabled),
					-- Double the pipes: the chat frame eats |R and friends as
					-- colour escapes, which makes a filter look corrupted.
					(tostring(UF.Auras:GetGroupFilter(group)):gsub('|', '||')),
					tostring(key)
				))
				SUI:Print(
					('     perRow=%s size=%s spacing=%s max=%s forceNewLine=%s'):format(
						tostring(group.perRow),
						tostring(group.size),
						tostring(group.spacing),
						tostring(group.number),
						tostring(group.forceNewLine)
					)
				)
			end
		end
	end, 'Report why a frame is or is not showing auras')

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

	SUI:AddChatCommand('testframes', function(args)
		if InCombatLockdown() then
			SUI:Print('Cannot toggle test mode during combat')
			return
		end
		if args and args ~= '' then
			UF.TestMode:Toggle(args)
		else
			if UF.TestMode:IsActive() then
				UF.TestMode:DisableAll()
			else
				UF.TestMode:EnableAll()
			end
		end
	end, 'Toggle unit frame test/preview mode')

	-- Register setup wizard pages
	self:RegisterSetupWizardPages()
end

function UF:RegisterSetupWizardPages()
	if not LibAT or not LibAT.SetupWizard then
		return
	end

	if LibAT.SetupWizard:GetPage('spartanui', 'unitframes') then
		return
	end

	-- Build a sorted list of presets applicable to a given group leader
	local function GetSortedPresets(groupLeader)
		local list = {}
		local source = groupLeader and UF.Preset:GetForFrameType(groupLeader) or UF.Preset:GetList()
		if not next(source) then
			source = UF.Preset:GetList()
		end
		for name, def in pairs(source) do
			list[#list + 1] = { name = name, def = def }
		end
		table.sort(list, function(a, b)
			return (a.def.displayName or a.name) < (b.def.displayName or b.name)
		end)
		return list
	end

	-- Build image card preset picker into contentFrame
	-- getActive: function() -> current preset name
	-- setActive: function(name) -> apply preset
	local function BuildPresetCards(contentFrame, groupLeader, getActive, setActive)
		local UI = LibAT.UI
		local width = contentFrame:GetWidth()
		local cardW = 120
		local cardH = 100
		local imgH = 60
		local pad = 8
		local cols = math.max(1, math.floor((width + pad) / (cardW + pad)))
		local presets = GetSortedPresets(groupLeader)
		local cards = {}

		local function refresh()
			local active = getActive()
			for _, card in ipairs(cards) do
				if card.presetName == active then
					card:SetBackdropBorderColor(1, 0.82, 0, 1)
				else
					card:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
				end
			end
		end

		for i, entry in ipairs(presets) do
			local col = (i - 1) % cols
			local row = math.floor((i - 1) / cols)
			local x = col * (cardW + pad)
			local y = -row * (cardH + pad)

			local card = CreateFrame('Button', nil, contentFrame, BackdropTemplateMixin and 'BackdropTemplate')
			card:SetSize(cardW, cardH)
			card:SetPoint('TOPLEFT', contentFrame, 'TOPLEFT', x, y)
			card:SetBackdrop({
				bgFile = 'Interface\\Buttons\\WHITE8x8',
				edgeFile = 'Interface\\Buttons\\WHITE8x8',
				edgeSize = 1,
			})
			card:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
			card.presetName = entry.name

			-- Preview image
			if entry.def.setup and entry.def.setup.image then
				local tex = card:CreateTexture(nil, 'ARTWORK')
				tex:SetPoint('TOPLEFT', card, 'TOPLEFT', 2, -2)
				tex:SetPoint('TOPRIGHT', card, 'TOPRIGHT', -2, -2)
				tex:SetHeight(imgH)
				tex:SetTexture(entry.def.setup.image)
				tex:SetTexCoord(0, 1, 0, 1)
			end

			-- Name label
			local nameLabel = UI.CreateLabel(card, entry.def.displayName or entry.name, 'GameFontNormalSmall')
			nameLabel:SetPoint('BOTTOMLEFT', card, 'BOTTOMLEFT', 4, 6)
			nameLabel:SetPoint('BOTTOMRIGHT', card, 'BOTTOMRIGHT', -4, 6)
			nameLabel:SetJustifyH('CENTER')

			-- Highlight texture
			local hl = card:CreateTexture(nil, 'HIGHLIGHT')
			hl:SetAllPoints()
			hl:SetColorTexture(1, 1, 1, 0.08)
			card:SetHighlightTexture(hl)

			local presetName = entry.name
			card:SetScript('OnClick', function()
				setActive(presetName)
				UF:Update()
				refresh()
			end)

			cards[#cards + 1] = card
		end

		refresh()

		local rows = math.ceil(#presets / cols)
		local totalH = rows * (cardH + pad)
		contentFrame:SetHeight(totalH + 20)
		return totalH
	end

	-- UF Overview page — set all frames at once
	LibAT.SetupWizard:AddPage('spartanui', {
		id = 'unitframes',
		name = 'Unit Frames',
		order = 30,
		builder = function(contentFrame)
			local UI = LibAT.UI

			local desc = UI.CreateLabel(
				contentFrame,
				'Choose a visual style for your unit frames.\nClick a preset to apply it to all frame groups at once.\nUse the child pages to customize each group individually.',
				'GameFontNormal'
			)
			desc:SetPoint('TOP', contentFrame, 'TOP', 0, -10)
			desc:SetPoint('LEFT', contentFrame, 'LEFT', 10, 0)
			desc:SetPoint('RIGHT', contentFrame, 'RIGHT', -10, 0)
			desc:SetJustifyH('CENTER')
			desc:SetWordWrap(true)

			local inner = CreateFrame('Frame', nil, contentFrame)
			inner:SetPoint('TOPLEFT', contentFrame, 'TOPLEFT', 10, -50)
			inner:SetPoint('RIGHT', contentFrame, 'RIGHT', -10, 0)
			inner:SetHeight(1)

			BuildPresetCards(inner, nil, function()
				return UF.Preset:GetActive('player')
			end, function(val)
				UF.Preset:ApplyThemeDefaults(val)
			end)
			contentFrame:SetHeight(inner:GetHeight() + 70)
		end,
		children = {},
	})

	-- Build common settings widgets (width, heights, portrait, buff filter) for a frame group
	local function BuildFrameSettings(contentFrame, frameName, width)
		local UI = LibAT.UI

		local function getFrameCS()
			return UF.CurrentSettings[frameName]
		end
		local function getElemCS(elemName)
			local cs = getFrameCS()
			return cs and cs.elements and cs.elements[elemName]
		end
		local function saveFrameSetting(key, val)
			local cs = getFrameCS()
			if cs then
				cs[key] = val
			end
			UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName][key] = val
			UF:Update()
		end
		local function saveElemSetting(elemName, key, val)
			local cs = getElemCS(elemName)
			if cs then
				cs[key] = val
			end
			UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements[elemName][key] = val
			if UF.Unit[frameName] then
				UF.Unit[frameName]:ElementUpdate(elemName)
			end
		end

		local defs = {
			frameWidth = {
				type = 'slider',
				name = 'Frame Width',
				order = 1,
				min = 50,
				max = 400,
				step = 1,
				get = function()
					local cs = getFrameCS()
					return cs and cs.width or 200
				end,
				set = function(_, val)
					saveFrameSetting('width', val)
				end,
			},
			healthHeight = {
				type = 'slider',
				name = 'Health Bar Height',
				order = 2,
				min = 4,
				max = 60,
				step = 1,
				get = function()
					local cs = getElemCS('Health')
					return cs and cs.height or 20
				end,
				set = function(_, val)
					saveElemSetting('Health', 'height', val)
				end,
			},
			powerHeight = {
				type = 'slider',
				name = 'Power Bar Height',
				order = 3,
				min = 2,
				max = 30,
				step = 1,
				get = function()
					local cs = getElemCS('Power')
					return cs and cs.height or 8
				end,
				set = function(_, val)
					saveElemSetting('Power', 'height', val)
				end,
			},
			castHeight = {
				type = 'slider',
				name = 'Cast Bar Height',
				order = 4,
				min = 4,
				max = 40,
				step = 1,
				get = function()
					local cs = getElemCS('Castbar')
					return cs and cs.height or 14
				end,
				set = function(_, val)
					saveElemSetting('Castbar', 'height', val)
				end,
			},
			portrait = {
				type = 'checkbox',
				name = 'Show Portrait',
				order = 5,
				get = function()
					local cs = getElemCS('Portrait')
					return cs and cs.enabled or false
				end,
				set = function(_, val)
					saveElemSetting('Portrait', 'enabled', val)
				end,
			},
		}

		-- Only add aura preset selector if system is loaded and frame has auras.
		-- Both flavors keep buffs and debuffs in their own element now; only
		-- the names differ.
		local auraHost = SUI.IsRetail and 'BuffContainer' or 'Buffs'
		if UF.AuraPresets and getElemCS(auraHost) then
			defs.buffFilter = {
				type = 'dropdown',
				name = 'Buff/Debuff Filter',
				order = 6,
				values = UF.AuraPresets:GetPresetList(),
				get = function()
					local buffsMode, debuffsMode

					if SUI.IsRetail then
						local buffsCS = getElemCS('BuffContainer')
						local debuffsCS = getElemCS('DebuffContainer')
						if not buffsCS or not debuffsCS then
							return 'custom'
						end
						buffsMode = buffsCS.filterMode
						debuffsMode = debuffsCS.filterMode
					else
						local buffsCS = getElemCS('Buffs')
						local debuffsCS = getElemCS('Debuffs')
						if not buffsCS or not debuffsCS then
							return 'custom'
						end
						buffsMode = buffsCS.classic and buffsCS.classic.filterMode
						debuffsMode = debuffsCS.classic and debuffsCS.classic.filterMode
					end

					local branch = SUI.IsRetail and 'retail' or 'classic'
					for key, preset in pairs(UF.AuraPresets.Presets) do
						local pb = preset.Buffs and preset.Buffs[branch] and preset.Buffs[branch].filterMode
						local pd = preset.Debuffs and preset.Debuffs[branch] and preset.Debuffs[branch].filterMode
						if buffsMode == pb and debuffsMode == pd then
							return key
						end
					end
					return 'custom'
				end,
				set = function(_, val)
					if val ~= 'custom' then
						UF.AuraPresets:ApplyPreset(frameName, val)
					end
				end,
			}
		end

		local _, h = UI.BuildWidgets(contentFrame, defs, width)
		contentFrame:SetHeight(h + 10)
		return h
	end

	-- Personal Frames child (player, target, focus, pet)
	LibAT.SetupWizard:AddPage('spartanui', {
		id = 'uf-personal',
		name = 'Personal Frames',
		order = 1,
		builder = function(contentFrame)
			local UI = LibAT.UI
			local width = contentFrame:GetWidth()
			local totalY = 10

			local groups = {
				{ leader = 'player', label = 'Player Frame' },
				{ leader = 'target', label = 'Target Frame' },
				{ leader = 'focus', label = 'Focus Frame' },
				{ leader = 'pet', label = 'Pet Frame' },
			}

			for _, g in ipairs(groups) do
				local hdr = UI.CreateHeader(contentFrame, g.label)
				hdr:SetPoint('TOPLEFT', contentFrame, 'TOPLEFT', 0, -totalY)
				totalY = totalY + 22

				local inner = CreateFrame('Frame', nil, contentFrame)
				inner:SetPoint('TOPLEFT', contentFrame, 'TOPLEFT', 0, -totalY)
				inner:SetWidth(width)
				inner:SetHeight(1)

				local leader = g.leader
				local h = BuildFrameSettings(inner, leader, width)
				totalY = totalY + h + 20
			end

			contentFrame:SetHeight(totalY + 10)
		end,
	}, 'unitframes')

	-- Group Frames child (party, raid, boss, arena)
	LibAT.SetupWizard:AddPage('spartanui', {
		id = 'uf-group',
		name = 'Group Frames',
		order = 2,
		builder = function(contentFrame)
			local UI = LibAT.UI
			local width = contentFrame:GetWidth()
			local totalY = 10

			local groups = {
				{ leader = 'party', label = 'Party Frames' },
				{ leader = 'raid25', label = 'Raid Frames' },
				{ leader = 'boss', label = 'Boss Frames' },
				{ leader = 'arena', label = 'Arena Frames' },
			}

			for _, g in ipairs(groups) do
				local hdr = UI.CreateHeader(contentFrame, g.label)
				hdr:SetPoint('TOPLEFT', contentFrame, 'TOPLEFT', 0, -totalY)
				totalY = totalY + 22

				local inner = CreateFrame('Frame', nil, contentFrame)
				inner:SetPoint('TOPLEFT', contentFrame, 'TOPLEFT', 0, -totalY)
				inner:SetWidth(width)
				inner:SetHeight(1)

				local leader = g.leader
				local h = BuildFrameSettings(inner, leader, width)
				totalY = totalY + h + 20
			end

			contentFrame:SetHeight(totalY + 10)
		end,
	}, 'unitframes')
end

function UF:ReloadDB()
	self:Update()
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
