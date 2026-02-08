local _, ns = ...
local oUF = ns.oUF

-- sourced from FrameXML/TargetFrame.lua
local MAX_BOSS_FRAMES = 8

-- sourced from FrameXML/RaidFrame.lua
local MEMBERS_PER_RAID_GROUP = _G.MEMBERS_PER_RAID_GROUP or 5

local hookedFrames = {}
local hookedNameplates = {}
local isArenaHooked = false
local isBossHooked = false
local isPartyHooked = false

local hiddenParent = CreateFrame('Frame', nil, UIParent)
hiddenParent:SetAllPoints()
hiddenParent:Hide()

local function insecureHide(self)
	self:Hide()
end

local function resetParent(self, parent)
	if parent ~= hiddenParent then
		self:SetParent(hiddenParent)
	end
end

local function handleFrame(baseName, doNotReparent, hookShow)
	local frame
	if type(baseName) == 'string' then
		frame = _G[baseName]
	else
		frame = baseName
	end

	if frame then
		frame:UnregisterAllEvents()
		frame:Hide()

		if not doNotReparent then
			frame:SetParent(hiddenParent)

			if not hookedFrames[frame] then
				hooksecurefunc(frame, 'SetParent', resetParent)

				hookedFrames[frame] = true
			end
		end

		-- Hook Show() to prevent Blizzard from showing the frame again
		-- This is crucial for TBC where GROUP_ROSTER_UPDATE can re-show frames
		if hookShow and not frame.__showHooked then
			hooksecurefunc(frame, 'Show', function(self)
				self:Hide()
			end)
			frame.__showHooked = true
		end

		local health = frame.healthBar or frame.healthbar or frame.HealthBar
		if health then
			health:UnregisterAllEvents()
		end

		local power = frame.manabar or frame.ManaBar
		if power then
			power:UnregisterAllEvents()
		end

		local spell = frame.castBar or frame.spellbar or frame.CastingBarFrame
		if spell then
			spell:UnregisterAllEvents()
		end

		local altpowerbar = frame.powerBarAlt or frame.PowerBarAlt
		if altpowerbar then
			altpowerbar:UnregisterAllEvents()
		end

		local buffFrame = frame.BuffFrame
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

			-- Handle old party frames (pre-Edit Mode)
			-- Hook Show() to prevent GROUP_ROSTER_UPDATE from re-showing them
			for i = 1, MAX_PARTY_MEMBERS do
				handleFrame(string.format('PartyMemberFrame%d', i), false, true)
			end

			-- Handle Edit Mode party frames (TBC+ with Edit Mode backport)
			-- CompactPartyFrame is the new party frame system that uses Edit Mode
			if CompactPartyFrame then
				handleFrame(CompactPartyFrame, false, true)
			end

			-- Disable CompactPartyFrameMember frames (used in Edit Mode)
			-- Only attempt this if CompactPartyFrameMember1 exists
			if _G['CompactPartyFrameMember1'] then
				for i = 1, MEMBERS_PER_RAID_GROUP do
					handleFrame('CompactPartyFrameMember' .. i, false, true)
				end
			end

			-- Note: CompactRaidFrameManager_SetSetting('IsShown', '0') was previously called here
			-- but that hides the raid frame manager even when only party frames are being replaced.
			-- It should only be called when raid frames are also being replaced by oUF.
		end
	elseif unit:match('arena%d?$') then
		local id = unit:match('arena(%d)')
		if id then
			handleFrame(oUF.isRetail and 'ArenaEnemyMatchFrame' or 'ArenaEnemyFrame' .. id)
		else
			for i = 1, MAX_ARENA_ENEMIES do
				handleFrame(string.format(oUF.isRetail and 'ArenaEnemyMatchFrame%d' or 'ArenaEnemyFrame%d', i))
			end
		end

		-- this disables ArenaEnemyFramesContainer
		SetCVar('showArenaEnemyFrames', '0')
	end
end

function oUF:DisableNamePlate(frame)
	if not (frame and frame.UnitFrame) then
		return
	end
	if frame.UnitFrame:IsForbidden() then
		return
	end

	if not hookedNameplates[frame] then
		frame.UnitFrame:HookScript('OnShow', insecureHide)

		hookedNameplates[frame] = true
	end

	handleFrame(frame.UnitFrame, true)
end
