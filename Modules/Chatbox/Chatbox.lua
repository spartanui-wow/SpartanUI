---@class SUI
local SUI = SUI
local L = SUI.L

---@class SUI.Module.Chatbox : SUI.Module, AceHook-3.0
local module = SUI:NewModule('Chatbox', 'AceHook-3.0')
module.description = 'Lightweight quality of life chat improvements'
module.logger = {}

-- Shared state accessible from other files
module.ChatLevelLog = {}
module.nameColor = {}
module.LeaveCount = 0
module.battleOver = false

----------------------------------------------------------------------------------------------------

---@class SUI.Chat.DB
local defaults = {
	LinkHover = true,
	autoLeaverOutput = true,
	shortenChannelNames = true,
	webLinks = true,
	EditBoxTop = false,
	timestampFormat = '%X',
	playerlevel = nil,
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
	},
	copyButton = { enabled = true, position = 'TOPRIGHT' },
	clickToCopyLine = true,

	-- Phase 3: Interactions
	altClickInvite = true,

	-- Phase 4: Search
	search = { enabled = true },

	-- Phase 5: Polish
	chatFade = { delay = 15, speed = 3 },
	editBoxPosition = 'BELOW',
	spamThrottle = { enabled = false, window = 5, threshold = 3 },
	channelSticky = true,
	tellTarget = true,

	chatLog = {
		enabled = true,
		maxEntries = 50,
		expireDays = 14,
		history = {},
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

function module:OnInitialize()
	module.Database = SUI.SpartanUIDB:RegisterNamespace('Chatbox', { profile = defaults })
	module.DB = module.Database.profile ---@type SUI.Chat.DB

	SUI.DBM:RegisterSequentialProfileRefresh(module)

	module.logger = SUI.logger:RegisterCategory('Chatbox')

	if not SUI.CharDB.ChatHistory then
		SUI.CharDB.ChatHistory = {}
	end
	if not SUI.CharDB.ChatEditHistory then
		SUI.CharDB.ChatEditHistory = {}
	end

	if SUI:IsModuleDisabled(module) then
		return
	end

	local ChatAddons = { 'Chatter', 'BasicChatMods', 'Prat-3.0', 'Chattynator', 'ChatEditBoxExtender' }
	for _, addonName in pairs(ChatAddons) do
		if SUI:IsAddonEnabled(addonName) then
			SUI:Print('Chat module disabling ' .. addonName .. ' Detected')
			module.Override = true
			return
		end
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
					if module.DB and module.DB.chatLog and module.DB.chatLog.history then
						wipe(module.DB.chatLog.history)
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
			if n and l and l > 0 then
				if s and s ~= '' then
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
			if n and l and l > 0 then
				if s and s ~= '' then
					n = n .. '-' .. s
				end
				module.ChatLevelLog[n] = tostring(l)
			end
		end
	end
	module:RegisterEvent('UPDATE_MOUSEOVER_UNIT')

	-- Setup all subsystems
	module:SetupStyling()
	module:SetupMessageMods()
	module:SetupEditBox()
	module:SetupCopyChat()
	module:SetupHighlights()
	module:SetupInteractions()
	module:SetupSearch()

	-- BG leaver commands
	SUI:AddChatCommand('leavers', function(output)
		if output then
			C_ChatInfo.SendChatMessage('SpartanUI: BG Leavers counter: ' .. module.LeaveCount, 'INSTANCE_CHAT')
		end
		SUI:Print('Leavers: ' .. module.LeaveCount)
	end, 'Prints the number of leavers in the current battleground, addings anything after leavers will output to instance chat')

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

	module:SecureHook('LeaveBattlefield', function()
		module.LeaveCount = 0
		module.battleOver = false
	end)

	if self.DB.chatLog.enabled then
		self:EnableChatLog()
	end
end

SUI.Chat = module
