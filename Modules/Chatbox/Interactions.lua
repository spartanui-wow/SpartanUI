---@class SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.Chatbox
local module = SUI:GetModule('Chatbox')

-- Track last-used chat channel per session
local lastChatType = nil
local lastChatTarget = nil

----------------------------------------------------------------------------------------------------
-- Alt+Click Invite
----------------------------------------------------------------------------------------------------

local function OnHyperlinkClick(chatFrame, link, text, button)
	if not module.DB.altClickInvite then
		return
	end
	if not IsAltKeyDown() then
		return
	end

	local linkType, playerName = strsplit(':', link, 3)
	if linkType ~= 'player' or not playerName then
		return
	end

	-- Strip realm if same realm
	local name, realm = strsplit('-', playerName)
	local myRealm = GetRealmName():gsub('%s+', '')

	local inviteName
	if realm and realm ~= '' and realm ~= myRealm then
		inviteName = playerName
	else
		inviteName = name
	end

	if C_PartyInfo and C_PartyInfo.InviteUnit then
		C_PartyInfo.InviteUnit(inviteName)
	else
		InviteUnit(inviteName)
	end

	SUI:Print(string.format(L['Invited %s to group'], inviteName))
end

----------------------------------------------------------------------------------------------------
-- /tt - Whisper Target
----------------------------------------------------------------------------------------------------

local function HandleTellTarget()
	if not module.DB.tellTarget then
		return
	end

	local target = UnitName('target')
	if not target then
		SUI:Print(L['No target selected'])
		return
	end

	if not UnitIsPlayer('target') then
		SUI:Print(L['Target is not a player'])
		return
	end

	local _, realm = UnitFullName('target')
	if realm and realm ~= '' then
		target = target .. '-' .. realm
	end

	ChatFrame_OpenChat('/w ' .. target .. ' ', DEFAULT_CHAT_FRAME)
end

----------------------------------------------------------------------------------------------------
-- Channel Sticky
----------------------------------------------------------------------------------------------------

local function OnChatTypeChanged(editBox)
	if not module.DB.channelSticky then
		return
	end

	local chatType = editBox:GetAttribute('chatType')
	if chatType then
		lastChatType = chatType
		if chatType == 'WHISPER' then
			lastChatTarget = editBox:GetAttribute('tellTarget')
		elseif chatType == 'CHANNEL' then
			lastChatTarget = editBox:GetAttribute('channelTarget')
		else
			lastChatTarget = nil
		end
	end
end

local function RestoreLastChannel(editBox)
	if not module.DB.channelSticky then
		return
	end
	if not lastChatType then
		return
	end

	editBox:SetAttribute('chatType', lastChatType)
	if lastChatType == 'WHISPER' and lastChatTarget then
		editBox:SetAttribute('tellTarget', lastChatTarget)
	elseif lastChatType == 'CHANNEL' and lastChatTarget then
		editBox:SetAttribute('channelTarget', lastChatTarget)
	end

	ChatEdit_UpdateHeader(editBox)
end

----------------------------------------------------------------------------------------------------
-- Spam Throttle
----------------------------------------------------------------------------------------------------

local recentMessages = {}
local THROTTLE_CLEANUP_INTERVAL = 30

local function SpamFilter(self, event, msg, sender, ...)
	if not module.DB.spamThrottle.enabled then
		return
	end
	if SUI.BlizzAPI.issecretvalue(msg) or SUI.BlizzAPI.issecretvalue(sender) then
		return
	end

	local key = sender .. ':' .. msg
	local now = GetTime()
	local window = module.DB.spamThrottle.window or 5
	local threshold = module.DB.spamThrottle.threshold or 3

	if not recentMessages[key] then
		recentMessages[key] = { count = 1, first = now, last = now }
		return
	end

	local entry = recentMessages[key]
	if now - entry.first > window then
		-- Reset window
		entry.count = 1
		entry.first = now
		entry.last = now
		return
	end

	entry.count = entry.count + 1
	entry.last = now

	if entry.count > threshold then
		-- Suppress and show count on first suppression
		if entry.count == threshold + 1 then
			local countMsg = string.format('|cff888888[%dx] %s|r', entry.count, msg)
			return false, countMsg, sender, ...
		end
		return true -- suppress completely
	end
end

local function CleanupThrottleCache()
	local now = GetTime()
	for key, entry in pairs(recentMessages) do
		if now - entry.last > 60 then
			recentMessages[key] = nil
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Setup
----------------------------------------------------------------------------------------------------

function module:SetupInteractions()
	if SUI:IsModuleDisabled(module) then
		return
	end

	-- Alt+Click invite
	if module.DB.altClickInvite then
		for i = 1, 10 do
			local chatFrame = _G['ChatFrame' .. i]
			if chatFrame then
				chatFrame:HookScript('OnHyperlinkClick', OnHyperlinkClick)
			end
		end
	end

	-- /tt command
	if module.DB.tellTarget then
		SLASH_SUITARGETWHISPER1 = '/tt'
		SlashCmdList['SUITARGETWHISPER'] = HandleTellTarget
	end

	-- Channel sticky
	if module.DB.channelSticky then
		for i = 1, 10 do
			local editBox = _G['ChatFrame' .. i .. 'EditBox']
			if editBox then
				editBox:HookScript('OnShow', RestoreLastChannel)
				hooksecurefunc('ChatEdit_UpdateHeader', function(eb)
					if eb == editBox then
						OnChatTypeChanged(eb)
					end
				end)
			end
		end
	end

	-- Spam throttle
	if module.DB.spamThrottle.enabled then
		local spamEvents = {
			'CHAT_MSG_SAY',
			'CHAT_MSG_YELL',
			'CHAT_MSG_CHANNEL',
		}
		for _, event in ipairs(spamEvents) do
			ChatFrame_AddMessageEventFilter(event, SpamFilter)
		end

		-- Periodic cleanup
		module:ScheduleRepeatingTimer('SpamThrottleCleanup', THROTTLE_CLEANUP_INTERVAL)
	end

	module.SpamThrottleCleanup = CleanupThrottleCache
end
