---@class SUI
local SUI = SUI
local L = SUI.L

---@class SUI.Module.Chatbox : SUI.Module, AceHook-3.0
local module = SUI:NewModule('Chatbox', 'AceHook-3.0')
module.DisplayName = 'Chatbox'
module.description = 'Lightweight quality of life chat improvements'
-- Other chat addons; while one is on this module stays off (setup's conflicts page offers the choice)
module.ConflictsWith = { 'Chatter', 'BasicChatMods', 'Prat-3.0', 'Chattynator', 'ChatEditBoxExtender' }
module.logger = {}

-- Shared state accessible from other files
module.ChatLevelLog = {}
module.nameColor = {}

----------------------------------------------------------------------------------------------------

---@class SUI.Chat.DB
---@field messageFormat string Format string with %TOKEN% placeholders
---@field messageFormatPreset string Last selected preset key
---@field headerButtons table Header button bar settings
local defaults = {
	LinkHover = true,
	webLinks = true,
	EditBoxTop = false,
	timestampFormat = '%I:%M',
	timestampShowAMPM = false,
	playerlevel = nil,
	messageFormat = '[%TIME%] [%CHANNEL%] %CHARACTER%: %MESSAGE%',
	messageFormatPreset = 'default',
	channelStyle = 'short',
	channelIndicator = {
		CHAT_MSG_SAY = true,
		CHAT_MSG_YELL = true,
		CHAT_MSG_GUILD = false,
		CHAT_MSG_OFFICER = true,
		CHAT_MSG_PARTY = true,
		CHAT_MSG_PARTY_LEADER = true,
		CHAT_MSG_RAID = true,
		CHAT_MSG_RAID_LEADER = true,
		CHAT_MSG_RAID_WARNING = true,
		CHAT_MSG_INSTANCE_CHAT = true,
		CHAT_MSG_INSTANCE_CHAT_LEADER = true,
		CHAT_MSG_WHISPER = true,
		CHAT_MSG_WHISPER_INFORM = true,
		CHAT_MSG_BN_WHISPER = true,
		CHAT_MSG_BN_WHISPER_INFORM = true,
		CHAT_MSG_EMOTE = true,
		dynamicChannels = true,
	},
	nameColorStyle = 'class',
	metaColor = { r = 0.49, g = 0.49, b = 0.49 },
	ChatCopyTip = true,
	fontSize = 12,
	hideChatButtons = false,
	hideSocialButton = false,
	disableChatFade = false,
	chatHistoryLines = 128,

	-- Phase 2: Multi-line / character counter
	multiLine = {
		enabled = false,
		maxLines = 5,
		showCharCounter = true,
		showChannelLabel = true,
		showLineBreakButton = true,
		opacity = 0.9,
		historySize = 250,
	},

	-- Phase 3: Highlights
	highlights = {
		enabled = false,
		keywords = {},
		highlightColor = { r = 1, g = 0.5, b = 0 },
		mentionsEnabled = true,
		mentionsColor = { r = 1, g = 0.5, b = 0 },
		mentionsSound = 'None',
		soundThrottle = 5,
		suppressInCombat = true,
		flashOnMention = true,
		flashOnWhisper = true,
	},

	-- Popup alert
	popupAlert = {
		enabled = false,
		triggerOnWhisper = true,
		triggerOnMention = true,
		triggerOnKeyword = true,
		holdDuration = 4,
		fadeInDuration = 0.5,
		fadeOutDuration = 2,
		fontSize = 16,
		suppressInCombat = true,
	},
	-- Phase 3: Interactions
	altClickInvite = true,

	-- Emoji
	emoji = { enabled = true },

	-- Phase 4: Search
	search = { enabled = true },

	-- Phase 5: Polish
	chatFade = { delay = 15, speed = 3 },
	editBoxPosition = 'BELOW',
	spamThrottle = { enabled = false, window = 5, threshold = 3 },
	channelSticky = true,
	tellTarget = true,

	editBoxBgColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.7 },

	headerButtons = {
		enabled = true,
		tabSwitcherMode = 'hover',
		buttons = {
			social = true,
			copy = true,
			search = true,
			errors = true,
			emoji = true,
			channels = true,
			voice = true,
			settings = true,
		},
	},

	chatLog = {
		enabled = true,
		maxEntries = 50,
		expireDays = 14,
		typesToLog = {
			CHAT_MSG_SAY = true,
			CHAT_MSG_YELL = true,
			CHAT_MSG_PARTY = true,
			CHAT_MSG_RAID = true,
			CHAT_MSG_GUILD = true,
			CHAT_MSG_OFFICER = true,
			CHAT_MSG_WHISPER = true,
			CHAT_MSG_WHISPER_INFORM = true,
			CHAT_MSG_INSTANCE_CHAT = true,
			CHAT_MSG_CHANNEL = true,
		},
		blacklist = {
			enabled = true,
			strings = { 'WTS' },
		},
	},
}

module.DBDefaults = defaults

function module:OnInitialize()
	module.logger = SUI.logger:RegisterCategory('Chatbox')

	SUI.DBM:SetupModule(self, defaults, nil, { autoCalculateDepth = true })

	SUI.DBM:RegisterSequentialProfileRefresh(module)

	-- Migration: sidePanel -> headerButtons
	if module.DB.sidePanel then
		if not module.DB.headerButtons then
			module.DB.headerButtons = {}
		end
		if module.DB.sidePanel.enabled ~= nil then
			module.DB.headerButtons.enabled = module.DB.sidePanel.enabled
		end
		if module.DB.sidePanel.buttons then
			if not module.DB.headerButtons.buttons then
				module.DB.headerButtons.buttons = {}
			end
			for k, v in pairs(module.DB.sidePanel.buttons) do
				module.DB.headerButtons.buttons[k] = v
			end
		end
		module.DB.sidePanel = nil
		SUI.DBM:RefreshSettings(module)
	end

	if not SUI.CharDB.ChatLog then
		SUI.CharDB.ChatLog = {}
	end
	if not SUI.CharDB.ChatEditHistory then
		SUI.CharDB.ChatEditHistory = {}
	end
	module.ChatLog = SUI.CharDB.ChatLog

	-- One-time migration: move chat history from profile DB to CharDB
	if module.DB.chatLog and module.DB.chatLog.history and #module.DB.chatLog.history > 0 then
		if #SUI.CharDB.ChatLog == 0 then
			for _, entry in ipairs(module.DB.chatLog.history) do
				table.insert(SUI.CharDB.ChatLog, entry)
			end
		end
		module.DB.chatLog.history = nil
	end

	if SUI:IsModuleDisabled(module) then
		return
	end

	local conflicts = SUI:GetModuleConflicts(module)
	if #conflicts > 0 then
		SUI:Print('Chat module disabling ' .. conflicts[1] .. ' Detected')
		module.Override = true
		module:CleanupOverride()
		return
	end

	module.ChatLevelLog = {}
	module.ChatLevelLog[(UnitName('player'))] = tostring((UnitLevel('player')))

	-- Disable Blizz class color
	if GetCVar('chatClassColorOverride') ~= '0' then
		SetCVar('chatClassColorOverride', '0')
	end
	-- Disable Blizz time stamping
	if GetCVar('showTimestamps') ~= 'none' then
		SetCVar('showTimestamps', 'none')
		CHAT_TIMESTAMP_FORMAT = nil
	end

	-- Create copy popup during init (before OnEnable hooks need it)
	module:CreateCopyPopup()
end

function module:OnEnable()
	module:BuildOptions()
	if SUI:IsModuleDisabled(module) then
		return
	end

	module:ApplyChatSettings()

	-- Hook chat frame Clear() to also clear SUI's chat history
	if not module.clearHookApplied then
		module.clearHookApplied = true
		for i = 1, NUM_CHAT_WINDOWS do
			local chatFrame = _G['ChatFrame' .. i]
			if chatFrame and chatFrame.Clear then
				hooksecurefunc(chatFrame, 'Clear', function()
					if module.ChatLog then
						wipe(module.ChatLog)
						if module.logger then
							module.logger.debug('Chat frame cleared, wiped SUI chat log history')
						end
					end
				end)
			end
		end
	end

	-- Setup player level tracking
	module.PLAYER_TARGET_CHANGED = function()
		if UnitIsPlayer('target') and UnitIsFriend('player', 'target') then
			local n, s = UnitName('target')
			local l = UnitLevel('target')
			if n and SUI.BlizzAPI.canaccessvalue(n) and l and SUI.BlizzAPI.canaccessvalue(l) and l > 0 then
				if s and SUI.BlizzAPI.canaccessvalue(s) and s ~= '' then
					n = n .. '-' .. s
				end
				module.ChatLevelLog[n] = tostring(l)
			end
		end
	end
	module:RegisterEvent('PLAYER_TARGET_CHANGED')

	module.UPDATE_MOUSEOVER_UNIT = function()
		if UnitIsPlayer('mouseover') and UnitIsFriend('player', 'mouseover') then
			local n, s = UnitName('mouseover')
			local l = UnitLevel('mouseover')
			if n and SUI.BlizzAPI.canaccessvalue(n) and l and SUI.BlizzAPI.canaccessvalue(l) and l > 0 then
				if s and SUI.BlizzAPI.canaccessvalue(s) and s ~= '' then
					n = n .. '-' .. s
				end
				module.ChatLevelLog[n] = tostring(l)
			end
		end
	end
	module:RegisterEvent('UPDATE_MOUSEOVER_UNIT')

	-- Cache levels from guild roster
	module.GUILD_ROSTER_UPDATE = function()
		local numGuild = GetNumGuildMembers()
		if not numGuild then
			return
		end
		for i = 1, numGuild do
			local n, _, _, l, _, _, _, _, _, _, c = GetGuildRosterInfo(i)
			if n and SUI.BlizzAPI.canaccessvalue(n) and l and SUI.BlizzAPI.canaccessvalue(l) and l > 0 then
				n = Ambiguate(n, 'none')
				module.ChatLevelLog[n] = tostring(l)
				if c and SUI.BlizzAPI.canaccessvalue(c) and module.nameColor then
					module.nameColor[n] = module:GetColor(c)
				end
			end
		end
	end
	module:RegisterEvent('GUILD_ROSTER_UPDATE')

	-- Cache levels from group roster
	module.GROUP_ROSTER_UPDATE = function()
		for i = 1, GetNumGroupMembers() do
			local unit = IsInRaid() and ('raid' .. i) or ('party' .. i)
			if UnitExists(unit) and UnitIsPlayer(unit) then
				local n, s = UnitName(unit)
				local l = UnitLevel(unit)
				if n and SUI.BlizzAPI.canaccessvalue(n) and l and SUI.BlizzAPI.canaccessvalue(l) and l > 0 then
					if s and SUI.BlizzAPI.canaccessvalue(s) and s ~= '' then
						n = n .. '-' .. s
					end
					n = Ambiguate(n, 'none')
					module.ChatLevelLog[n] = tostring(l)
				end
			end
		end
	end
	module:RegisterEvent('GROUP_ROSTER_UPDATE')

	-- Cache levels from friends list
	module.FRIENDLIST_UPDATE = function()
		for i = 1, C_FriendList.GetNumOnlineFriends() do
			local info = C_FriendList.GetFriendInfoByIndex(i)
			if info and info.name and SUI.BlizzAPI.canaccessvalue(info.name) and info.level and SUI.BlizzAPI.canaccessvalue(info.level) and info.level > 0 then
				module.ChatLevelLog[info.name] = tostring(info.level)
			end
		end
	end
	module:RegisterEvent('FRIENDLIST_UPDATE')

	-- Cache levels from /who results
	module.WHO_LIST_UPDATE = function()
		local num = C_FriendList.GetNumWhoResults()
		for i = 1, num do
			local info = C_FriendList.GetWhoInfo(i)
			if info and info.fullName and SUI.BlizzAPI.canaccessvalue(info.fullName) and info.level and SUI.BlizzAPI.canaccessvalue(info.level) and info.level > 0 then
				local n = Ambiguate(info.fullName, 'none')
				module.ChatLevelLog[n] = tostring(info.level)
				if info.filename and SUI.BlizzAPI.canaccessvalue(info.filename) and module.nameColor then
					module.nameColor[n] = module:GetColor(info.filename)
				end
			end
		end
	end
	module:RegisterEvent('WHO_LIST_UPDATE')

	-- Setup all subsystems
	module:SetupStyling()
	module:SetupMessageMods()
	module:SetupEditBox()
	module:SetupCopyChat()
	module:SetupHighlights()
	module:SetupPopupAlert()
	module:SetupInteractions()
	module:SetupSearch()
	module:SetupEmoji()
	module:SetupEmojiPicker()

	SUI:AddChatCommand('clearchat', function()
		module:ClearChat()
	end, 'Clears the chat window and stored history (also available as /clearchat or /clear)')

	SLASH_CLEARCHAT1 = '/clearchat'
	SlashCmdList['CLEARCHAT'] = function()
		module:ClearChat()
	end

	SLASH_SUICLEAR1 = '/clear'
	SlashCmdList['SUICLEAR'] = function()
		module:ClearChat()
	end

	if self.CurrentSettings.chatLog.enabled then
		self:EnableChatLog()
	end
end

SUI.Chat = module
