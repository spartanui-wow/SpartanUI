local SUI, L = SUI, SUI.L
---@class SUI.Module.UICleanup
local module = SUI:GetModule('UICleanup')
----------------------------------------------------------------------------------------------------

-- StopTalking functionality migrated from standalone module
-- Database is kept in separate namespace for backwards compatibility

local HeardLines = {}
local StopTalkingDB
local StopTalkingDBGlobal

---@class SUI.Module.UICleanup.StopTalkingDB
local StopTalkingDefaults = {
	persist = true,
	chatOutput = true,
	global = true,
	stopAll = false,
	history = {},
	whitelist = {},
	pageSize = 20,
	currentBlacklistPage = 1,
	currentWhitelistPage = 1,
	searchBlacklist = '',
	searchWhitelist = '',
}

function module:InitializeStopTalking()
	if not SUI.IsRetail then
		return
	end

	-- Register separate namespace for StopTalking (backwards compatibility)
	local stDB = SUI.SpartanUIDB:RegisterNamespace('StopTalking', { profile = StopTalkingDefaults, global = StopTalkingDefaults })
	StopTalkingDB = stDB.profile
	StopTalkingDBGlobal = stDB.global

	-- Register profile change callbacks
	stDB.RegisterCallback(module, 'OnProfileChanged', function()
		StopTalkingDB = stDB.profile
		StopTalkingDBGlobal = stDB.global
		module.StopTalkingDB = StopTalkingDB
		module.StopTalkingDBGlobal = StopTalkingDBGlobal
	end)
	stDB.RegisterCallback(module, 'OnProfileCopied', function()
		StopTalkingDB = stDB.profile
		StopTalkingDBGlobal = stDB.global
		module.StopTalkingDB = StopTalkingDB
		module.StopTalkingDBGlobal = StopTalkingDBGlobal
	end)
	stDB.RegisterCallback(module, 'OnProfileReset', function()
		StopTalkingDB = stDB.profile
		StopTalkingDBGlobal = stDB.global
		module.StopTalkingDB = StopTalkingDB
		module.StopTalkingDBGlobal = StopTalkingDBGlobal
	end)

	-- Store references on module
	module.StopTalkingDB = StopTalkingDB
	module.StopTalkingDBGlobal = StopTalkingDBGlobal

	-- Import globals if active
	if StopTalkingDBGlobal.global then
		for k, v in pairs(StopTalkingDB.history) do
			StopTalkingDBGlobal.history[k] = v
		end
		StopTalkingDB.history = {}
	end

	-- Register event
	module:RegisterEvent('TALKINGHEAD_REQUESTED', 'OnTalkingHeadRequested')

	-- Unregister from TalkingHeadFrame
	if TalkingHeadFrame then
		TalkingHeadFrame:UnregisterEvent('TALKINGHEAD_REQUESTED')
	end
end

function module:GetStopTalkingDB()
	return StopTalkingDB
end

function module:GetStopTalkingDBGlobal()
	return StopTalkingDBGlobal
end

function module:OnTalkingHeadRequested()
	if SUI:IsModuleDisabled(module) then
		if TalkingHeadFrame then
			TalkingHeadFrame:PlayCurrent()
		end
		return
	end

	local _, _, vo, _, _, _, name, text = C_TalkingHead.GetCurrentLineInfo()
	if not vo then
		return
	end

	-- If stopAll is enabled, immediately close all voice lines
	if StopTalkingDB.stopAll then
		if StopTalkingDB.chatOutput and name and text then
			SUI:Print(name)
			print(text)
		end
		TalkingHeadFrame:CloseImmediately()
		return
	end

	local persist = StopTalkingDB.persist
	local history = StopTalkingDBGlobal.global and StopTalkingDBGlobal.history or StopTalkingDB.history
	local whitelist = StopTalkingDBGlobal.global and StopTalkingDBGlobal.whitelist or StopTalkingDB.whitelist

	-- Check both persistent storage and session-based HeardLines
	if (persist and history[vo] and not whitelist[vo]) or (not persist and HeardLines[vo] and not whitelist[vo]) then
		-- Line has been heard before
		if StopTalkingDB.chatOutput and name and text then
			SUI:Print(name)
			print(text)
		end
		TalkingHeadFrame:CloseImmediately()
	else
		-- New line, play it and store it
		TalkingHeadFrame:PlayCurrent()
		if persist then
			history[vo] = name .. ' - ' .. text
		else
			HeardLines[vo] = name .. ' - ' .. text
		end
	end
end

function module:CleanupStopTalkingDatabase()
	-- Cleanup function to ensure all database items are strings
	local function cleanTable(tbl)
		if not tbl then
			return
		end
		local keysToRemove = {}

		for key, value in pairs(tbl) do
			if type(value) ~= 'string' then
				if type(key) == 'string' then
					tbl[key] = key
				else
					table.insert(keysToRemove, key)
				end
			end
		end

		for _, key in ipairs(keysToRemove) do
			tbl[key] = nil
		end
	end

	cleanTable(StopTalkingDB.history)
	cleanTable(StopTalkingDB.whitelist)
	cleanTable(StopTalkingDBGlobal.history)
	cleanTable(StopTalkingDBGlobal.whitelist)

	SUI:Print('StopTalking database cleaned')
end
