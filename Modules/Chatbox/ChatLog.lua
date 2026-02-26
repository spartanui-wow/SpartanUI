---@class SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.Chatbox
local module = SUI:GetModule('Chatbox')

local chatTypeMap = {
	CHAT_MSG_SAY = 'SAY',
	CHAT_MSG_YELL = 'YELL',
	CHAT_MSG_PARTY = 'PARTY',
	CHAT_MSG_RAID = 'RAID',
	CHAT_MSG_GUILD = 'GUILD',
	CHAT_MSG_OFFICER = 'OFFICER',
	CHAT_MSG_WHISPER = 'WHISPER',
	CHAT_MSG_WHISPER_INFORM = 'WHISPER_INFORM',
	CHAT_MSG_INSTANCE_CHAT = 'INSTANCE_CHAT',
}

function module:EnableChatLog()
	for chatType in pairs(self.DB.chatLog.typesToLog) do
		if self.DB.chatLog.typesToLog[chatType] then
			self:RegisterEvent(chatType, 'LogChatMessage')
		else
			self:UnregisterEvent(chatType)
		end
	end
	self:RestoreChatHistory()
end

function module:DisableChatLog()
	for chatType in pairs(self.DB.chatLog.typesToLog) do
		self:UnregisterEvent(chatType)
	end
end

function module:LogChatMessage(event, message, sender, languageName, channelName, _, _, _, channelIndex, channelBaseName, _, _, guid, _, _, _, _, _)
	if not self.DB.chatLog.enabled or SUI.BlizzAPI.issecretvalue(message) then
		return
	end

	if self.DB.chatLog.blacklist.enabled then
		for _, blacklistedString in ipairs(self.DB.chatLog.blacklist.strings) do
			if message:lower():find(blacklistedString:lower(), 1, true) then
				return
			end
		end
	end

	local entry = {
		timestamp = time(),
		event = event,
		sender = sender,
		message = message,
		guid = guid,
		channelName = channelName,
		channelIndex = channelIndex,
		channelBaseName = channelBaseName,
		languageName = languageName,
	}

	table.insert(self.DB.chatLog.history, entry)

	while #self.DB.chatLog.history > self.DB.chatLog.maxEntries do
		table.remove(self.DB.chatLog.history, 1)
	end
end

function module:RestoreChatHistory()
	local chatFrame = DEFAULT_CHAT_FRAME
	local playerRealm = GetRealmName()

	for _, entry in ipairs(self.DB.chatLog.history) do
		local senderName, senderRealm = entry.sender:match('(.+)%-(.+)')
		if not senderName then
			senderName = entry.sender
			senderRealm = playerRealm
		end

		local displayName = senderName
		if senderRealm ~= playerRealm then
			displayName = displayName .. '-' .. senderRealm
		end

		local chatType = chatTypeMap[entry.event] or 'SYSTEM'
		if entry.event == 'CHAT_MSG_CHANNEL' and entry.channelIndex then
			chatType = 'CHANNEL' .. entry.channelIndex
		end
		local info = ChatTypeInfo[chatType]

		local messageWithName = ''
		local channelInfo = ''
		local languageInfo = ''

		if entry.event == 'CHAT_MSG_CHANNEL' and entry.channelIndex then
			if module.DB.shortenChannelNames then
				channelInfo = string.format('[%d. %s] ', entry.channelIndex, entry.channelBaseName)
			else
				channelInfo = string.format('[%s] ', entry.channelBaseName)
			end
		elseif chatType == 'GUILD' then
			channelInfo = module.DB.shortenChannelNames and '[G] ' or '[Guild] '
		elseif chatType == 'OFFICER' then
			channelInfo = module.DB.shortenChannelNames and '[O] ' or '[Officer] '
		elseif chatType == 'RAID' then
			channelInfo = module.DB.shortenChannelNames and '[R] ' or '[Raid] '
		elseif chatType == 'PARTY' then
			channelInfo = module.DB.shortenChannelNames and '[P] ' or '[Party] '
		elseif chatType == 'INSTANCE_CHAT' then
			channelInfo = module.DB.shortenChannelNames and '[I] ' or '[Instance] '
		end

		if entry.languageName and entry.languageName ~= '' and entry.languageName ~= select(1, GetDefaultLanguage()) then
			languageInfo = string.format('[%s]', entry.languageName)
		end

		local coloredName = string.format('[|cFF%s%s|r]', module:GetColor(entry.guid), displayName)

		local function formatMessage(eventFormat, name)
			return string.format(eventFormat, name)
		end

		if entry.event == 'CHAT_MSG_SAY' then
			messageWithName = formatMessage(CHAT_SAY_GET, coloredName)
		elseif entry.event == 'CHAT_MSG_YELL' then
			messageWithName = formatMessage(CHAT_YELL_GET, coloredName)
		elseif entry.event == 'CHAT_MSG_WHISPER' or entry.event == 'CHAT_MSG_WHISPER_INFORM' then
			messageWithName = formatMessage(CHAT_WHISPER_GET, coloredName)
		elseif entry.event == 'CHAT_MSG_EMOTE' then
			messageWithName = formatMessage(CHAT_EMOTE_GET, coloredName)
		elseif entry.event == 'CHAT_MSG_CHANNEL' or entry.event == 'CHAT_MSG_GUILD' or entry.event == 'CHAT_MSG_OFFICER' then
			messageWithName = string.format('%s', coloredName)
		else
			messageWithName = string.format('%s', coloredName)
		end

		local formattedMessage = string.format('%s%s%s %s', channelInfo, messageWithName, languageInfo, entry.message)

		chatFrame:AddMessage(formattedMessage, info.r, info.g, info.b)
	end
end

function module:ClearChatLog()
	wipe(self.DB.chatLog.history)
	SUI:Print(L['Chat log cleared'])
end

function module:CleanupOldChatLog()
	if not self.DB.chatLog.history then
		return
	end

	local currentTime = time()
	local expirationTime = currentTime - (self.DB.chatLog.expireDays * 24 * 60 * 60)
	local maxEntries = self.DB.chatLog.maxEntries

	for i = #self.DB.chatLog.history, 1, -1 do
		if self.DB.chatLog.history[i].timestamp < expirationTime then
			table.remove(self.DB.chatLog.history, i)
		end
	end

	while #self.DB.chatLog.history > maxEntries do
		table.remove(self.DB.chatLog.history, 1)
	end
end

function module:AddBlacklistString(string)
	if not tContains(self.DB.chatLog.blacklist.strings, string) then
		table.insert(self.DB.chatLog.blacklist.strings, string)
	end
end

function module:RemoveBlacklistString(string)
	tDeleteItem(self.DB.chatLog.blacklist.strings, string)
end

function module:ToggleBlacklist(enable)
	self.DB.chatLog.blacklist.enabled = enable
end

function module:ClearAllChatLogs()
	wipe(self.DB.chatLog.history)

	for profileName, profileData in pairs(SUI.SpartanUIDB.profiles) do
		if profileData.Chatbox and profileData.Chatbox.chatLog then
			wipe(profileData.Chatbox.chatLog.history)
		end
	end

	SUI:Print(L['All chat logs cleared from all profiles'])
end
