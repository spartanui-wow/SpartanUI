local _, ns = ...
local oUF = ns.oUF

-- sourced from Blizzard_UnitFrame/TargetFrame.lua
local MAX_BOSS_FRAMES = 8 -- blizzard can spawn more than the default 5 apparently

-- sourced from Blizzard_FrameXMLBase/Shared/Constants.lua
local MEMBERS_PER_RAID_GROUP = _G.MEMBERS_PER_RAID_GROUP or 5

local hookedFrames = {}
local hookedNameplates = {}
local isArenaHooked = false
local isBossHooked = false
local isPartyHooked = false
local isRaidHooked = false

local hiddenParent = CreateFrame('Frame', nil, UIParent)
hiddenParent:SetAllPoints()
hiddenParent:Hide()

-- local function insecureHide(self)
-- 	self:Hide()
-- end

local looseFrames = {}

local watcher = CreateFrame('Frame')
watcher:RegisterEvent('PLAYER_REGEN_ENABLED')
watcher:SetScript('OnEvent', function()
	for frame in next, looseFrames do
		frame:SetParent(hiddenParent)
		frame:Hide()
	end

	table.wipe(looseFrames)
end)

local function resetParent(self, parent)
	if parent ~= hiddenParent then
		if InCombatLockdown() and self:IsProtected() then
			looseFrames[self] = true
		else
			self:SetParent(hiddenParent)
		end
	end
end

local function handleFrame(baseName, doNotReparent, isNamePlate, hookShow)
	local frame
	if type(baseName) == 'string' then
		frame = _G[baseName]
	else
		frame = baseName
	end

	if frame then
		frame:UnregisterAllEvents()
		if isNamePlate then
			-- TODO: remove this once we can adjust hitrects for nameplates
			frame:SetAlpha(0)
		else
			frame:Hide()
		end

		if not doNotReparent then
			frame:SetParent(hiddenParent)

			if not hookedFrames[frame] then
				hooksecurefunc(frame, 'SetParent', resetParent)

				hookedFrames[frame] = true
			end
		end

		-- Hook Show() to prevent Blizzard from showing the frame again
		-- This is crucial for preventing GROUP_ROSTER_UPDATE from re-showing frames
		if hookShow and not frame.__showHooked then
			hooksecurefunc(frame, 'Show', function(self)
				if InCombatLockdown() and self:IsProtected() then
					-- Can't Hide() protected frames in combat, defer to out-of-combat handler
					looseFrames[self] = true
				else
					self:Hide()
				end
			end)
			frame.__showHooked = true
		end

		-- Edit Mode isolation: Hide selection indicators to prevent Edit Mode from controlling this frame
		if frame.selectionHighlight then
			frame.selectionHighlight:Hide()
			frame.selectionHighlight:SetAlpha(0)
		end
		if frame.selectionIndicator then
			frame.selectionIndicator:Hide()
			frame.selectionIndicator:SetAlpha(0)
		end

		-- Combat-safe alpha + scale hiding for protected frames
		-- This ensures frames are invisible even if Edit Mode tries to show them
		if not InCombatLockdown() then
			pcall(function()
				frame:SetAlpha(0)
				frame:SetScale(0.001) -- Near-invisible but doesn't trigger combat lockdown
			end)
		end

		local health = frame.healthBar or frame.healthbar or frame.HealthBar or (frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar)
		if health then
			health:UnregisterAllEvents()
		end

		local power = frame.manabar or frame.ManaBar
		if power then
			power:UnregisterAllEvents()
		end

		local castbar = frame.castBar or frame.spellbar or frame.CastingBarFrame
		if castbar then
			castbar:UnregisterAllEvents()
		end

		local altpowerbar = frame.powerBarAlt or frame.PowerBarAlt
		if altpowerbar then
			altpowerbar:UnregisterAllEvents()
		end

		local buffFrame = frame.BuffFrame or frame.AurasFrame
		if buffFrame then
			buffFrame:UnregisterAllEvents()
		end

		local petFrame = frame.petFrame or frame.PetFrame
		if petFrame then
			petFrame:UnregisterAllEvents()
		end

		local totFrame = frame.totFrame
		if totFrame then
			totFrame:UnregisterAllEvents()
		end

		local classPowerBar = frame.classPowerBar
		if classPowerBar then
			classPowerBar:UnregisterAllEvents()
		end

		local ccRemoverFrame = frame.CcRemoverFrame
		if ccRemoverFrame then
			ccRemoverFrame:UnregisterAllEvents()
		end

		local debuffFrame = frame.DebuffFrame
		if debuffFrame then
			debuffFrame:UnregisterAllEvents()
		end
	end
end

function oUF:DisableBlizzard(unit)
	if not unit then
		return
	end

	if unit == 'player' then
		handleFrame(PlayerFrame)
	elseif unit == 'pet' then
		handleFrame(PetFrame)
	elseif unit == 'target' then
		handleFrame(TargetFrame)
	elseif unit == 'focus' then
		handleFrame(FocusFrame)
	elseif unit:match('boss%d?$') then
		if not isBossHooked then
			isBossHooked = true

			-- it's needed because the layout manager can bring frames that are
			-- controlled by containers back from the dead when a user chooses
			-- to revert all changes
			-- for now I'll just reparent it, but more might be needed in the
			-- future, watch it
			handleFrame(BossTargetFrameContainer)

			-- do not reparent frames controlled by containers, the vert/horiz
			-- layout code will go insane because it won't be able to calculate
			-- the size properly, 0 or negative sizes in turn will break the
			-- layout manager, fun...
			for i = 1, MAX_BOSS_FRAMES do
				handleFrame('Boss' .. i .. 'TargetFrame', true)
			end
		end
	elseif unit:match('party%d?$') then
		if not isPartyHooked then
			isPartyHooked = true

			-- Hook Show() to prevent GROUP_ROSTER_UPDATE from re-showing party frames
			handleFrame(PartyFrame, false, false, true)

			for frame in PartyFrame.PartyMemberFramePool:EnumerateActive() do
				handleFrame(frame, true, false, true)
			end

			for i = 1, MEMBERS_PER_RAID_GROUP do
				handleFrame('CompactPartyFrameMember' .. i, false, false, true)
			end

			-- Edit Mode: Hide CompactPartyFrame container selection indicators
			if CompactPartyFrame then
				handleFrame(CompactPartyFrame, false, false, true)
				if CompactPartyFrame.selectionHighlight then
					CompactPartyFrame.selectionHighlight:Hide()
					CompactPartyFrame.selectionHighlight:SetAlpha(0)
				end
				if CompactPartyFrame.selectionIndicator then
					CompactPartyFrame.selectionIndicator:Hide()
					CompactPartyFrame.selectionIndicator:SetAlpha(0)
				end
			end

			-- Unregister GROUP_ROSTER_UPDATE from UIParent to prevent party frame updates
			-- This event constantly triggers party frame visibility updates
			UIParent:UnregisterEvent('GROUP_ROSTER_UPDATE')
		end
	elseif unit:match('raid%d?$') then
		if not isRaidHooked then
			isRaidHooked = true

			-- Hide CompactRaidFrameManager and its selection indicators
			if CompactRaidFrameManager then
				handleFrame(CompactRaidFrameManager, true, false, true)
				if CompactRaidFrameManager_SetSetting then
					CompactRaidFrameManager_SetSetting('IsShown', '0')
				end
				if CompactRaidFrameManager.selectionHighlight then
					CompactRaidFrameManager.selectionHighlight:Hide()
					CompactRaidFrameManager.selectionHighlight:SetAlpha(0)
				end
			end

			-- Hide CompactRaidFrameContainer and its Edit Mode selection indicators
			if CompactRaidFrameContainer then
				handleFrame(CompactRaidFrameContainer, true, false, true)
				if CompactRaidFrameContainer.selectionHighlight then
					CompactRaidFrameContainer.selectionHighlight:Hide()
					CompactRaidFrameContainer.selectionHighlight:SetAlpha(0)
				end
				if CompactRaidFrameContainer.selectionIndicator then
					CompactRaidFrameContainer.selectionIndicator:Hide()
					CompactRaidFrameContainer.selectionIndicator:SetAlpha(0)
				end

				-- Disable the ApplyToFrames and ApplyMultipleToFrames methods to prevent Edit Mode
				-- from trying to update unit frames we've disabled
				CompactRaidFrameContainer.ApplyToFrames = function()
					-- No-op: SpartanUI controls raid frames
				end
				CompactRaidFrameContainer.ApplyMultipleToFrames = function()
					-- No-op: SpartanUI controls raid frames
				end

				-- Disable the OnEvent script to prevent Edit Mode callbacks
				CompactRaidFrameContainer:SetScript('OnEvent', nil)
			end
		end
	elseif unit:match('arena%d?$') then
		if not isArenaHooked then
			isArenaHooked = true

			handleFrame(CompactArenaFrame)

			for _, frame in next, CompactArenaFrame.memberUnitFrames do
				handleFrame(frame, true)
			end
		end
	end
end

function oUF:DisableBlizzardNamePlate(frame)
	if not (frame and frame.UnitFrame) then
		return
	end
	if frame.UnitFrame:IsForbidden() then
		return
	end

	if not hookedNameplates[frame] then
		-- BUG: the hit rect (for clicking) is tied to the original UnitFrame object on the
		--      nameplate, so we can't hide it. instead we force it to be invisible, and adjust
		--      the hit rect insets around it so it matches the nameplate object itself, but we
		--      do that in SpawnNamePlates instead
		-- TODO: remove this hack once we can adjust hitrects ourselves, coming in a later build
		local locked = false
		hooksecurefunc(frame.UnitFrame, 'SetAlpha', function(UnitFrame)
			if locked or UnitFrame:IsForbidden() then
				return
			end
			locked = true
			UnitFrame:SetAlpha(0)
			locked = false
		end)

		hookedNameplates[frame] = true
	end

	handleFrame(frame.UnitFrame, true, true)
end
