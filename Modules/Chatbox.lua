---@class SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.Chatbox : SUI.Module, AceHook-3.0
local module = SUI:NewModule('Chatbox', 'AceHook-3.0')
module.description = 'Lightweight quality of life chat improvements'
module.logger = {}
----------------------------------------------------------------------------------------------------
local popup = CreateFrame('Frame', nil, UIParent)
local linkTypes = {
	item = true,
	enchant = true,
	spell = true,
	achievement = true,
	talent = true,
	glyph = true,
	currency = true,
	unit = true,
	quest = true,
}
local ChatLevelLog, nameColor = {}, {}
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

local LeaveCount = 0
local battleOver = false

local function StripTextures(object)
	for i = 1, object:GetNumRegions() do
		local region = select(i, object:GetRegions())
		if region and region:GetObjectType() == 'Texture' then
			region:SetTexture(nil)
		end
	end
end

function module:SetPopupText(text)
	popup.editBox:SetText(text)
	popup:Show()
end

function module:GetColor(input)
	local className, color

	if type(input) == 'string' and input:match('^Player%-') then
		-- It's a GUID, get the class from it
		_, className = GetPlayerInfoByGUID(input)
	elseif type(input) == 'string' then
		-- Assume it's already a class name
		className = input
	end

	if className then
		color = RAID_CLASS_COLORS[className]
	end

	if color then
		return ('%02x%02x%02x'):format(color.r * 255, color.g * 255, color.b * 255)
	end

	-- Default color if we couldn't determine the class color
	return 'ffffff'
end

local function get_color(c)
	if type(c.r) == 'number' and type(c.g) == 'number' and type(c.b) == 'number' and type(c.a) == 'number' then
		return c.r, c.g, c.b, c.a
	end
	if type(c.r) == 'number' and type(c.g) == 'number' and type(c.b) == 'number' then
		return c.r, c.g, c.b, 0.8
	end
	return 1.0, 1.0, 1.0, 0.8
end

local function get_var_color(a1, a2, a3, a4)
	local r, g, b, a

	if type(a1) == 'table' then
		r, g, b, a = get_color(a1)
	elseif type(a1) == 'number' and type(a2) == 'number' and type(a3) == 'number' and type(a4) == 'number' then
		r, g, b, a = a1, a2, a3, a4
	elseif type(a1) == 'number' and type(a2) == 'number' and type(a3) == 'number' and type(a4) == 'nil' then
		r, g, b, a = a1, a2, a3, 0.8
	else
		r, g, b, a = 1.0, 1.0, 1.0, 0.8
	end

	return r, g, b, a
end

local function to225(r, g, b, a)
	return r * 255, g * 255, b * 255, a
end

local function GetHexColor(a1, a2, a3, a4)
	return string.format('%02x%02x%02x', to225(get_var_color(a1, a2, a3, a4)))
end

local changeName = function(fullName, misc, nameToChange, colon)
	local name = Ambiguate(fullName, 'none')
	--Do this here instead of listening to the guild event, as the event is slower than a player login
	--leading to player logins lacking color/level, unless we held a database of the entire guild.
	--Since the event usually fires when a player logs in, doing it this way should be virtually the same.
	local hasColor = nameToChange:find('|c', nil, true)
	if (nameColor and not hasColor and not nameColor[name]) or (ChatLevelLog and not ChatLevelLog[name]) then
		for i = 1, GetNumGuildMembers() do
			local n, _, _, l, _, _, _, _, _, _, c = GetGuildRosterInfo(i)
			if n then
				n = Ambiguate(n, 'none')
				if n == name then
					if ChatLevelLog and l and l > 0 then
						ChatLevelLog[n] = tostring(l)
					end
					if nameColor and c and not hasColor then
						nameColor[n] = module:GetColor(c)
					end
					break
				end
			end
		end
	end
	if nameColor and not hasColor then
		--If the displayed name was an in-chat who result, take the data and color it.
		if not nameColor[name] then
			local num = C_FriendList.GetNumWhoResults()
			for i = 1, num do
				local tbl = C_FriendList.GetWhoInfo(i)
				local n, l, c = tbl.fullName, tbl.level, tbl.filename
				if n == name and l and l > 0 then
					if ChatLevelLog then
						ChatLevelLog[n] = tostring(l)
					end
					if nameColor and c then
						nameColor[n] = module:GetColor(c)
					end
					break
				end
			end
		end
		if nameColor[name] then
			nameToChange = '|cFF' .. nameColor[name] .. nameToChange .. '|r' -- All this code just to color player log in events, worth it?
		end
	end
	if ChatLevelLog and ChatLevelLog[name] and module.DB.playerlevel then
		local color = GetHexColor(GetQuestDifficultyColor(ChatLevelLog[name]))

		nameToChange = '|cff' .. color .. ChatLevelLog[name] .. '|r:' .. nameToChange
	end
	return '|Hplayer:' .. fullName .. misc .. '[' .. nameToChange .. ']' .. (colon == ':' and ' ' or colon) .. '|h'
end

function module:PlayerName(text)
	text = text:gsub('|Hplayer:([^:|]+)([^%[]+)%[([^%]]+)%]|h(:?)', changeName)
	return text
end

function module:TimeStamp(text)
	if module.DB.timestampFormat == '' then
		return text
	end

	-- Check if the message already has a timestamp
	if text:match('^|cff7d7d7d%[%d+:%d+:%d+%]|r') then
		return text
	end

	local timestamp = date(module.DB.timestampFormat)
	return '|cff7d7d7d' .. timestamp .. ' | |r' .. text
end

local function shortenChannel(text)
	if not module.DB.shortenChannelNames then
		return text
	end

	local rplc = {
		'[I]', --Instance
		'[IL]', --Instance Leader
		'[G]', --Guild
		'[P]', --Party
		'[PL]', --Party Leader
		'[PL]', --Party Leader (Guide)
		'[O]', --Officer
		'[R]', --Raid
		'[RL]', --Raid Leader
		'[RW]', --Raid Warning
		'[%1]', --Custom Channels
	}
	local gsub = gsub
	local chn = {
		gsub(CHAT_INSTANCE_CHAT_GET, '.*%[(.*)%].*', '%%[%1%%]'),
		gsub(CHAT_INSTANCE_CHAT_LEADER_GET, '.*%[(.*)%].*', '%%[%1%%]'),
		gsub(CHAT_GUILD_GET, '.*%[(.*)%].*', '%%[%1%%]'),
		gsub(CHAT_PARTY_GET, '.*%[(.*)%].*', '%%[%1%%]'),
		gsub(CHAT_PARTY_LEADER_GET, '.*%[(.*)%].*', '%%[%1%%]'),
		gsub(CHAT_PARTY_GUIDE_GET, '.*%[(.*)%].*', '%%[%1%%]'),
		gsub(CHAT_OFFICER_GET, '.*%[(.*)%].*', '%%[%1%%]'),
		gsub(CHAT_RAID_GET, '.*%[(.*)%].*', '%%[%1%%]'),
		gsub(CHAT_RAID_LEADER_GET, '.*%[(.*)%].*', '%%[%1%%]'),
		gsub(CHAT_RAID_WARNING_GET, '.*%[(.*)%].*', '%%[%1%%]'),
		'%[(%d%d?)%. ([^%]]+)%]', --Custom Channels
	}

	local num = #chn
	for i = 1, num do
		text = gsub(text, chn[i], rplc[i])
	end
	return text
end

local ModifyMessage = function(self)
	if SUI:IsModuleDisabled('Chatbox') then
		return
	end
	local num = self.headIndex
	if num == 0 then
		num = self.maxElements
	end
	local tbl = self.elements[num]
	local text = tbl and tbl.message

	if text then
		--Check if the message is from someone leaving the battle
		if text:find('has left the battle') and not battleOver then
			LeaveCount = LeaveCount + 1
		end
		-- See if the alliance or horde has won the battle
		if text:find('The Alliance Wins!') or text:find('The Horde Wins!') then
			--Print the number of leavers
			SUI:Print('Leavers: ' .. LeaveCount)
			--Output to Instance chat if over 15 leavers
			if LeaveCount > 15 and module.DB.autoLeaverOutput then
				C_ChatInfo.SendChatMessage('SpartanUI: BG Leavers counter: ' .. LeaveCount, 'INSTANCE_CHAT')
			end
			battleOver = true
		end

		text = tostring(text)
		text = shortenChannel(text)
		text = module:TimeStamp(text)
		text = module:PlayerName(text)

		self.elements[num].message = text
	end
end

-- Tooltip mouseover
local showingTooltip = false
function module:OnHyperlinkEnter(f, link)
	local t = strmatch(link, '^(.-):')
	if linkTypes[t] then
		showingTooltip = true
		ShowUIPanel(GameTooltip)
		GameTooltip:SetOwner(UIParent, 'ANCHOR_CURSOR')
		GameTooltip:SetHyperlink(link)
		GameTooltip:Show()
	end
end

function module:OnHyperlinkLeave(f, link)
	if showingTooltip then
		showingTooltip = false
		HideUIPanel(GameTooltip)
	end
end

-- Module Setup
function module:OnInitialize()
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
		-- New convenience options
		hideChatButtons = false,
		hideSocialButton = false,
		disableChatFade = false,
		chatHistoryLines = 128, -- Default WoW value, can go up to 4096
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
	module.Database = SUI.SpartanUIDB:RegisterNamespace('Chatbox', { profile = defaults })
	module.DB = module.Database.profile ---@type SUI.Chat.DB

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
	local ChatAddons = { 'Chatter', 'BasicChatMods', 'Prat-3.0' }
	for _, addonName in pairs(ChatAddons) do
		if SUI:IsAddonEnabled(addonName) then
			SUI:Print('Chat module disabling ' .. addonName .. ' Detected')
			module.Override = true
			return
		end
	end

	ChatLevelLog = SUI.DBG.ChatLevelLog
	-- Create popup using Blizzard UI (similar to logging window)
	popup = CreateFrame('Frame', 'SUI_ChatCopyPopup', UIParent, 'ButtonFrameTemplate')
	ButtonFrameTemplate_HidePortrait(popup)
	ButtonFrameTemplate_HideButtonBar(popup)
	popup.Inset:Hide()
	popup:SetSize(600, 350)
	popup:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
	popup:SetFrameStrata('DIALOG')
	popup:Hide()

	-- Make the window movable
	popup:SetMovable(true)
	popup:EnableMouse(true)
	popup:RegisterForDrag('LeftButton')
	popup:SetScript('OnDragStart', popup.StartMoving)
	popup:SetScript('OnDragStop', popup.StopMovingOrSizing)

	-- Set title
	popup:SetTitle('|cffffffffSpartan|cffe21f1fUI|r Chat Copy')

	-- Create main content area
	popup.MainContent = CreateFrame('Frame', nil, popup)
	popup.MainContent:SetPoint('TOPLEFT', popup, 'TOPLEFT', 18, -30)
	popup.MainContent:SetPoint('BOTTOMRIGHT', popup, 'BOTTOMRIGHT', -25, 12)

	-- Create text display area with MinimalScrollBar
	popup.TextPanel = CreateFrame('ScrollFrame', nil, popup.MainContent)
	popup.TextPanel:SetPoint('TOPLEFT', popup.MainContent, 'TOPLEFT', 6, -6)
	popup.TextPanel:SetPoint('BOTTOMRIGHT', popup.MainContent, 'BOTTOMRIGHT', 0, 2)

	popup.TextPanel.Background = popup.TextPanel:CreateTexture(nil, 'BACKGROUND')
	popup.TextPanel.Background:SetAtlas('auctionhouse-background-index', true)
	popup.TextPanel.Background:SetPoint('TOPLEFT', popup.TextPanel, 'TOPLEFT', -6, 6)
	popup.TextPanel.Background:SetPoint('BOTTOMRIGHT', popup.TextPanel, 'BOTTOMRIGHT', 0, -6)

	-- Create minimal scrollbar
	popup.TextPanel.ScrollBar = CreateFrame('EventFrame', nil, popup.TextPanel, 'MinimalScrollBar')
	popup.TextPanel.ScrollBar:SetPoint('TOPLEFT', popup.TextPanel, 'TOPRIGHT', 6, 0)
	popup.TextPanel.ScrollBar:SetPoint('BOTTOMLEFT', popup.TextPanel, 'BOTTOMRIGHT', 6, 0)
	ScrollUtil.InitScrollFrameWithScrollBar(popup.TextPanel, popup.TextPanel.ScrollBar)

	-- Create the text edit box
	popup.editBox = CreateFrame('EditBox', nil, popup.TextPanel)
	popup.editBox:SetMultiLine(true)
	popup.editBox:SetFontObject('GameFontHighlight')
	popup.editBox:SetWidth(popup.TextPanel:GetWidth() - 20)
	popup.editBox:SetAutoFocus(false)
	popup.editBox:EnableMouse(true)
	popup.editBox:SetTextColor(1, 1, 1)
	popup.editBox:SetScript('OnTextChanged', function(self)
		ScrollingEdit_OnTextChanged(self, self:GetParent())
	end)
	popup.editBox:SetScript('OnCursorChanged', function(self, x, y, w, h)
		ScrollingEdit_OnCursorChanged(self, x, y - 10, w, h)
	end)
	popup.TextPanel:SetScrollChild(popup.editBox)

	-- Create font for text processing (keep for compatibility)
	popup.font = popup:CreateFontString(nil, nil, 'GameFontNormal')
	popup.font:Hide()

	-- Auto-scroll to bottom when shown
	popup:HookScript('OnShow', function()
		popup.TextPanel:SetVerticalScroll((popup.TextPanel:GetVerticalScrollRange()) or 0)
	end)

	-- Disable Blizz class color
	if GetCVar('chatClassColorOverride') ~= '0' then
		SetCVar('chatClassColorOverride', '0')
	end
	-- Disable Blizz time stamping
	if GetCVar('showTimestamps') ~= 'none' then
		SetCVar('showTimestamps', 'none')
		CHAT_TIMESTAMP_FORMAT = nil
	end
	ChatLevelLog = {}
	ChatLevelLog[(UnitName('player'))] = tostring((UnitLevel('player')))
end

function module:OnEnable()
	module:BuildOptions()
	if SUI:IsModuleDisabled(module) then
		return
	end

	-- Apply new convenience settings
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

	-- Debug timer to check chat frame state
	if module.logger then
		C_Timer.After(3, function()
			local log = module.logger
			log.debug('=== Chat Frame Debug (3 sec after enable) ===')
			log.debug('ChatFrame1.isDocked: ' .. tostring(ChatFrame1.isDocked))
			log.debug('ChatFrame1.buttonFrame exists: ' .. tostring(ChatFrame1.buttonFrame ~= nil))
			if ChatFrame1.buttonFrame then
				log.debug('ChatFrame1.buttonFrame:IsShown(): ' .. tostring(ChatFrame1.buttonFrame:IsShown()))
				log.debug('ChatFrame1.buttonFrame:IsVisible(): ' .. tostring(ChatFrame1.buttonFrame:IsVisible()))
				log.debug('ChatFrame1.buttonFrame:GetAlpha(): ' .. tostring(ChatFrame1.buttonFrame:GetAlpha()))
			end
			log.debug('ChatFrame1ButtonFrame exists: ' .. tostring(ChatFrame1ButtonFrame ~= nil))
			if ChatFrame1ButtonFrame then
				log.debug('ChatFrame1ButtonFrame:IsShown(): ' .. tostring(ChatFrame1ButtonFrame:IsShown()))
				log.debug('ChatFrame1ButtonFrame:IsVisible(): ' .. tostring(ChatFrame1ButtonFrame:IsVisible()))
				log.debug('ChatFrame1ButtonFrame:GetAlpha(): ' .. tostring(ChatFrame1ButtonFrame:GetAlpha()))
				log.debug('ChatFrame1ButtonFrame children:')
				for i, child in ipairs({ ChatFrame1ButtonFrame:GetChildren() }) do
					local name = child:GetName() or child:GetObjectType()
					local shown = child:IsShown()
					local visible = child:IsVisible()
					log.debug('  ' .. i .. ': ' .. name .. ' shown=' .. tostring(shown) .. ' visible=' .. tostring(visible))
				end
			end
			log.debug('ChatFrameMenuButton exists: ' .. tostring(ChatFrameMenuButton ~= nil))
			if ChatFrameMenuButton then
				log.debug('ChatFrameMenuButton:IsShown(): ' .. tostring(ChatFrameMenuButton:IsShown()))
				log.debug('ChatFrameMenuButton:IsVisible(): ' .. tostring(ChatFrameMenuButton:IsVisible()))
				log.debug('ChatFrameMenuButton:GetParent(): ' .. tostring(ChatFrameMenuButton:GetParent() and ChatFrameMenuButton:GetParent():GetName()))
				log.debug('ChatFrameMenuButton:GetAlpha(): ' .. tostring(ChatFrameMenuButton:GetAlpha()))
				local point, relativeTo, relativePoint, x, y = ChatFrameMenuButton:GetPoint(1)
				log.debug(
					'ChatFrameMenuButton position: '
						.. tostring(point)
						.. ' '
						.. tostring(relativeTo and relativeTo:GetName())
						.. ' '
						.. tostring(relativePoint)
						.. ' x='
						.. tostring(x)
						.. ' y='
						.. tostring(y)
				)
				local w, h = ChatFrameMenuButton:GetSize()
				log.debug('ChatFrameMenuButton size: ' .. tostring(w) .. 'x' .. tostring(h))
			end
			log.debug('ChatFrameChannelButton exists: ' .. tostring(ChatFrameChannelButton ~= nil))
			if ChatFrameChannelButton then
				log.debug('ChatFrameChannelButton:IsShown(): ' .. tostring(ChatFrameChannelButton:IsShown()))
				log.debug('ChatFrameChannelButton:IsVisible(): ' .. tostring(ChatFrameChannelButton:IsVisible()))
				log.debug('ChatFrameChannelButton:GetAlpha(): ' .. tostring(ChatFrameChannelButton:GetAlpha()))
			end
			log.debug('GeneralDockManager exists: ' .. tostring(GeneralDockManager ~= nil))
			if GeneralDockManager then
				log.debug('GeneralDockManager:IsShown(): ' .. tostring(GeneralDockManager:IsShown()))
				log.debug('GeneralDockManager:IsVisible(): ' .. tostring(GeneralDockManager:IsVisible()))
				local point, relativeTo, relativePoint, x, y = GeneralDockManager:GetPoint(1)
				log.debug(
					'GeneralDockManager position: '
						.. tostring(point)
						.. ' '
						.. tostring(relativeTo and relativeTo:GetName())
						.. ' '
						.. tostring(relativePoint)
						.. ' x='
						.. tostring(x)
						.. ' y='
						.. tostring(y)
				)
			end
			if ChatFrameChannelButton then
				local point, relativeTo, relativePoint, x, y = ChatFrameChannelButton:GetPoint(1)
				log.debug(
					'ChatFrameChannelButton position: '
						.. tostring(point)
						.. ' '
						.. tostring(relativeTo and relativeTo:GetName())
						.. ' '
						.. tostring(relativePoint)
						.. ' x='
						.. tostring(x)
						.. ' y='
						.. tostring(y)
				)
			end
			-- Check screen position
			if ChatFrameMenuButton then
				local left, bottom, width, height = ChatFrameMenuButton:GetRect()
				log.debug('ChatFrameMenuButton screen rect: left=' .. tostring(left) .. ' bottom=' .. tostring(bottom) .. ' w=' .. tostring(width) .. ' h=' .. tostring(height))
			end
			if ChatFrameChannelButton then
				local left, bottom, width, height = ChatFrameChannelButton:GetRect()
				log.debug('ChatFrameChannelButton screen rect: left=' .. tostring(left) .. ' bottom=' .. tostring(bottom) .. ' w=' .. tostring(width) .. ' h=' .. tostring(height))
			end
			log.debug('=== End Debug ===')
		end)
	end

	-- Setup Player level monitor
	module.PLAYER_TARGET_CHANGED = function()
		if UnitIsPlayer('target') and UnitIsFriend('player', 'target') then
			local n, s = UnitName('target')
			local l = UnitLevel('target')
			if n and l and l > 0 then
				if s and s ~= '' then
					n = n .. '-' .. s
				end
				ChatLevelLog[n] = tostring(l)
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
				ChatLevelLog[n] = tostring(l)
			end
		end
	end
	module:RegisterEvent('UPDATE_MOUSEOVER_UNIT')

	-- Setup everything
	module:SetupChatboxes()

	--Add a chat command to print the number of leavers
	SUI:AddChatCommand('leavers', function(output)
		--If output is true then tell the instance chat
		if output then
			C_ChatInfo.SendChatMessage('SpartanUI: BG Leavers counter: ' .. LeaveCount, 'INSTANCE_CHAT')
		end
		SUI:Print('Leavers: ' .. LeaveCount)
	end, 'Prints the number of leavers in the current battleground, addings anything after leavers will output to instance chat')

	--Add chat command to clear chat window and history
	SUI:AddChatCommand('clearchat', function()
		module:ClearChat()
	end, 'Clears the chat window and stored history (also available as /clearchat or /clear)')

	--Register standalone /clearchat command
	SLASH_CLEARCHAT1 = '/clearchat'
	SlashCmdList['CLEARCHAT'] = function()
		module:ClearChat()
	end

	--Register /clear command as alias
	SLASH_SUICLEAR1 = '/clear'
	SlashCmdList['SUICLEAR'] = function()
		module:ClearChat()
	end

	--Detect when we leave the battleground and reset the counter
	module:SecureHook('LeaveBattlefield', function()
		LeaveCount = 0
		battleOver = false
	end)

	if self.DB.chatLog.enabled then
		self:EnableChatLog()
	end
end

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

	-- Check against blacklist
	if self.DB.chatLog.blacklist.enabled then
		for _, blacklistedString in ipairs(self.DB.chatLog.blacklist.strings) do
			if message:lower():find(blacklistedString:lower(), 1, true) then
				return -- Don't log this message
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

		-- Handle channel names for all chat types
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

function module:ClearChat()
	-- Clear all chat frames
	for i = 1, NUM_CHAT_WINDOWS do
		local chatFrame = _G['ChatFrame' .. i]
		if chatFrame then
			chatFrame:Clear()
		end
	end

	-- Clear stored chat log history
	wipe(self.DB.chatLog.history)

	-- Clear edit box history
	if SUI.CharDB.ChatEditHistory then
		wipe(SUI.CharDB.ChatEditHistory)
	end

	SUI:Print(L['Chat cleared'])
end

function module:EditBoxPosition()
	for i = 1, 10 do
		local ChatFrameName = ('%s%d'):format('ChatFrame', i)
		local ChatFrame = _G[ChatFrameName]
		local ChatFrameEdit = _G[ChatFrameName .. 'EditBox']

		ChatFrameEdit:ClearAllPoints()

		if module.DB.EditBoxTop then
			local GDM = _G['GeneralDockManager']
			ChatFrameEdit:SetPoint('BOTTOMLEFT', GDM, 'TOPLEFT', 0, 1)
			ChatFrameEdit:SetPoint('BOTTOMRIGHT', GDM, 'TOPRIGHT', 0, 1)
		else
			ChatFrameEdit:SetPoint('TOPLEFT', ChatFrame.Background, 'BOTTOMLEFT', -1, -1)
			ChatFrameEdit:SetPoint('TOPRIGHT', ChatFrame.Background, 'BOTTOMRIGHT', 1, -1)
		end
	end
end

function module:ApplyChatSettings()
	-- Apply hide chat buttons setting
	module:ApplyHideChatButtons()

	-- Apply hide social button setting
	module:ApplyHideSocialButton()

	-- Apply disable chat fade setting
	module:ApplyDisableChatFade()

	-- Apply chat history lines setting
	module:ApplyChatHistoryLines()
end

function module:ApplyHideChatButtons()
	local log = module.logger
	if log then
		log.debug('ApplyHideChatButtons called, hideChatButtons=' .. tostring(module.DB.hideChatButtons))
	end

	-- Hide/show the chat frame menu button and voice channel button (Retail)
	local ChatFrameMenuBtn = _G['ChatFrameMenuButton']
	local VoiceChannelButton = _G['ChatFrameChannelButton']

	if log then
		log.debug('ChatFrameMenuButton=' .. tostring(ChatFrameMenuBtn ~= nil) .. ', ChatFrameChannelButton=' .. tostring(VoiceChannelButton ~= nil))
	end

	if module.DB.hideChatButtons then
		if ChatFrameMenuBtn then
			ChatFrameMenuBtn:Hide()
			ChatFrameMenuBtn:SetScript('OnShow', function(self)
				if module.DB.hideChatButtons then
					self:Hide()
				end
			end)
		end
		if VoiceChannelButton then
			VoiceChannelButton:Hide()
			VoiceChannelButton:SetScript('OnShow', function(self)
				if module.DB.hideChatButtons then
					self:Hide()
				end
			end)
		end
	else
		if ChatFrameMenuBtn then
			ChatFrameMenuBtn:SetScript('OnShow', nil)
			ChatFrameMenuBtn:Show()
		end
		if VoiceChannelButton then
			VoiceChannelButton:SetScript('OnShow', nil)
			VoiceChannelButton:Show()
		end
	end

	-- Hide/show the buttonFrame for each chat frame (Classic/TBC/Wrath/Cata)
	-- The buttonFrame contains scroll buttons (up, down, bottom) and is per-chatframe
	local buttonFrameCount = 0
	for i = 1, NUM_CHAT_WINDOWS do
		local ChatFrame = _G['ChatFrame' .. i]
		if ChatFrame and ChatFrame.buttonFrame then
			buttonFrameCount = buttonFrameCount + 1
			if module.DB.hideChatButtons then
				ChatFrame.buttonFrame:SetAlpha(0)
				ChatFrame.buttonFrame:EnableMouse(false)
			else
				ChatFrame.buttonFrame:SetAlpha(1)
				ChatFrame.buttonFrame:EnableMouse(true)
			end
		end
	end
	if log then
		log.debug('Found ' .. buttonFrameCount .. ' buttonFrames out of ' .. NUM_CHAT_WINDOWS .. ' chat windows')
	end

	-- Hook FCF_FadeInChatFrame and FCF_FadeOutChatFrame to prevent buttonFrame from being shown
	-- These functions control the buttonFrame alpha on mouse hover
	if not module.chatButtonHooksApplied then
		module.chatButtonHooksApplied = true
		if log then
			log.debug('Applying chat button hooks')
		end

		if FCF_FadeInChatFrame then
			if log then
				log.debug('Hooking FCF_FadeInChatFrame')
			end
			hooksecurefunc('FCF_FadeInChatFrame', function(chatFrame)
				if module.DB.hideChatButtons and chatFrame and chatFrame.buttonFrame then
					if log then
						log.debug('FCF_FadeInChatFrame hook fired, hiding buttonFrame')
					end
					chatFrame.buttonFrame:SetAlpha(0)
					chatFrame.buttonFrame:EnableMouse(false)
				end
			end)
		else
			if log then
				log.warn('FCF_FadeInChatFrame not found')
			end
		end

		if FCF_FadeOutChatFrame then
			if log then
				log.debug('Hooking FCF_FadeOutChatFrame')
			end
			hooksecurefunc('FCF_FadeOutChatFrame', function(chatFrame)
				if module.DB.hideChatButtons and chatFrame and chatFrame.buttonFrame then
					if log then
						log.debug('FCF_FadeOutChatFrame hook fired, hiding buttonFrame')
					end
					chatFrame.buttonFrame:SetAlpha(0)
					chatFrame.buttonFrame:EnableMouse(false)
				end
			end)
		else
			if log then
				log.warn('FCF_FadeOutChatFrame not found')
			end
		end
	end
end

function module:ApplyHideSocialButton()
	-- Hide/show the quick join toast button (social button)
	local QJTB = _G['QuickJoinToastButton']
	if not QJTB then
		return
	end

	if module.DB.hideSocialButton then
		QJTB:Hide()
		QJTB:SetScript('OnShow', function(self)
			if module.DB.hideSocialButton then
				self:Hide()
			end
		end)
	else
		QJTB:SetScript('OnShow', nil)
		QJTB:Show()
	end
end

function module:ApplyDisableChatFade()
	local log = module.logger
	if log then
		log.debug('ApplyDisableChatFade called, disableChatFade=' .. tostring(module.DB.disableChatFade))
	end

	-- Enable/disable chat fade for all chat frames
	local function SetAllChatFading(shouldFade)
		local count = 0
		-- Use CHAT_FRAMES global for more reliable iteration (includes temporary frames)
		if CHAT_FRAMES then
			for _, frameName in ipairs(CHAT_FRAMES) do
				local ChatFrame = _G[frameName]
				if ChatFrame and ChatFrame.SetFading then
					ChatFrame:SetFading(shouldFade)
					count = count + 1
				end
			end
		end
		-- Also iterate numbered frames as fallback/additional coverage
		for i = 1, 50 do
			local ChatFrame = _G['ChatFrame' .. i]
			if ChatFrame and ChatFrame.SetFading then
				ChatFrame:SetFading(shouldFade)
				count = count + 1
			end
		end
		if log then
			log.debug('SetAllChatFading(' .. tostring(shouldFade) .. ') applied to ' .. count .. ' frames')
		end

		-- Verify the setting was applied
		if log and ChatFrame1 then
			local currentFading = ChatFrame1:GetFading()
			log.debug('ChatFrame1:GetFading() = ' .. tostring(currentFading) .. ' (expected ' .. tostring(shouldFade) .. ')')
		end
	end

	-- Apply the setting now
	SetAllChatFading(not module.DB.disableChatFade)

	-- Hook various functions that might reset the fading state
	if not module.chatFadeHooksApplied then
		module.chatFadeHooksApplied = true
		if log then
			log.debug('Applying chat fade hooks')
		end

		-- Hook temporary chat windows
		if FCF_OpenTemporaryWindow then
			if log then
				log.debug('Hooking FCF_OpenTemporaryWindow')
			end
			hooksecurefunc('FCF_OpenTemporaryWindow', function()
				if module.DB.disableChatFade then
					local cf = FCF_GetCurrentChatFrame and FCF_GetCurrentChatFrame()
					if cf and cf.SetFading then
						cf:SetFading(false)
						if log then
							log.debug('FCF_OpenTemporaryWindow hook: disabled fading on temp window')
						end
					end
				end
			end)
		end

		-- Hook FloatingChatFrame_Update which is called on UPDATE_CHAT_WINDOWS
		if FloatingChatFrame_Update then
			if log then
				log.debug('Hooking FloatingChatFrame_Update')
			end
			hooksecurefunc('FloatingChatFrame_Update', function(id)
				if module.DB.disableChatFade then
					local ChatFrame = _G['ChatFrame' .. id]
					if ChatFrame and ChatFrame.SetFading then
						ChatFrame:SetFading(false)
						if log then
							log.debug('FloatingChatFrame_Update hook: disabled fading on ChatFrame' .. id)
						end
					end
				end
			end)
		else
			if log then
				log.warn('FloatingChatFrame_Update not found')
			end
		end

		-- Hook FCF_CopyChatSettings which copies settings between frames
		if FCF_CopyChatSettings then
			if log then
				log.debug('Hooking FCF_CopyChatSettings')
			end
			hooksecurefunc('FCF_CopyChatSettings', function(copyTo)
				if module.DB.disableChatFade and copyTo and copyTo.SetFading then
					copyTo:SetFading(false)
					if log then
						log.debug('FCF_CopyChatSettings hook: disabled fading')
					end
				end
			end)
		end
	end
end

function module:ApplyChatHistoryLines()
	-- Set the maximum number of history lines for all chat frames
	-- Default WoW is 128, max is 4096
	local lines = module.DB.chatHistoryLines or 128
	for i = 1, NUM_CHAT_WINDOWS do
		local ChatFrame = _G['ChatFrame' .. i]
		if ChatFrame then
			ChatFrame:SetMaxLines(lines)
		end
	end
end

---@param key string
function module:ChatEdit_OnKeyDown(key)
	-- Make sure we are setup and valid
	local history = SUI.CharDB.ChatEditHistory
	if (not history) or #history == 0 then
		return
	end

	--Grab the next item in the history
	if key == 'DOWN' then
		self.historyIndex = self.historyIndex - 1

		if self.historyIndex < 1 then
			self.historyIndex = 0
			self:SetText('')
			return
		end
	elseif key == 'UP' then
		self.historyIndex = self.historyIndex + 1

		if self.historyIndex > #history then
			self.historyIndex = #history
		end
	else
		return
	end

	--Display the history item
	self:SetText(strtrim(history[#history - (self.historyIndex - 1)]))
end

---@param line string
function module:ChatEdit_AddHistory(_, line)
	line = line and strtrim(line)

	if line and strlen(line) > 0 then
		local cmd = strmatch(line, '^/%w+')
		-- block secure commands from history
		if cmd and IsSecureCmd(cmd) then
			return
		end

		for index, text in pairs(SUI.CharDB.ChatEditHistory) do
			if text == line then
				tremove(SUI.CharDB.ChatEditHistory, index)
				break
			end
		end

		tinsert(SUI.CharDB.ChatEditHistory, line)

		if #SUI.CharDB.ChatEditHistory > 50 then
			tremove(SUI.CharDB.ChatEditHistory, 1)
		end
	end
end

function module:SetupChatboxes()
	if SUI:IsModuleDisabled(module) then
		return
	end
	-- DEFAULT_CHATFRAME_ALPHA = 0.7
	-- DEFAULT_CHATFRAME_COLOR = {r = .05, g = .05, b = .05}
	-- DEFAULT_TAB_SELECTED_COLOR_TABLE = {r = .9, g = .9, b = .9}

	local icon = 'Interface\\Addons\\SpartanUI\\images\\chatbox\\chaticons'

	local chatBG = {
		bgFile = [[Interface\Buttons\WHITE8X8]],
		edgeFile = [[Interface\Buttons\WHITE8X8]],
		tile = true,
		tileSize = 16,
		edgeSize = 2,
	}

	local c = { r = 0.05, g = 0.05, b = 0.05, a = 0.7 }
	local filterFunc = function(a, b, msg, ...)
		if not module.DB.webLinks then
			return
		end

		local newMsg, found = gsub(
			msg,
			'[^ "£%^`¬{}%[%]\\|<>]*[^ \'%-=%./,"£%^`¬{}%[%]\\|<>%d][^ \'%-=%./,"£%^`¬{}%[%]\\|<>%d]%.[^ \'%-=%./,"£%^`¬{}%[%]\\|<>%d][^ \'%-=%./,"£%^`¬{}%[%]\\|<>%d][^ "£%^`¬{}%[%]\\|<>]*',
			'|cffffffff|Hbcmurl~%1|h[%1]|h|r'
		)
		if found > 0 then
			return false, newMsg, ...
		end
		newMsg, found = gsub(
			msg,
			-- This is our IPv4/v6 pattern at the beggining of a sentence.
			'^%x+[%.:]%x+[%.:]%x+[%.:]%x+[^ "£%^`¬{}%[%]\\|<>]*',
			'|cffffffff|Hbcmurl~%1|h[%1]|h|r'
		)
		if found > 0 then
			return false, newMsg, ...
		end
		newMsg, found = gsub(
			msg,
			-- Mid-sentence IPv4/v6 pattern
			' %x+[%.:]%x+[%.:]%x+[%.:]%x+[^ "£%^`¬{}%[%]\\|<>]*',
			'|cffffffff|Hbcmurl~%1|h[%1]|h|r'
		)
		if found > 0 then
			return false, newMsg, ...
		end
	end

	--Copying Functions
	local TabClick = function(frame)
		local ChatFrameName = format('%s%d', 'ChatFrame', frame:GetID())
		local ChatFrame = _G[ChatFrameName]
		local ChatFrameEdit = _G[ChatFrameName .. 'EditBox']

		if IsShiftKeyDown() and IsControlKeyDown() then
			-- Shift+Control+Click to clear the chat tab
			ChatFrame:Clear()
		elseif IsAltKeyDown() then
			local text = ''
			-- Fix special pipe methods e.g. 5 |4hour:hours; Example: copying /played text
			for i = 1, ChatFrame:GetNumMessages() do
				local line = ChatFrame:GetMessageInfo(i)
				if SUI.BlizzAPI.issecretvalue(line) then
					text = text .. '<Secret Message>\n'
				else
					popup.font:SetFormattedText('%s\n', line)
					local cleanLine = popup.font:GetText() or ''
					text = text .. cleanLine
				end
			end
			text = text:gsub('|T[^\\]+\\[^\\]+\\[Uu][Ii]%-[Rr][Aa][Ii][Dd][Tt][Aa][Rr][Gg][Ee][Tt][Ii][Nn][Gg][Ii][Cc][Oo][Nn]_(%d)[^|]+|t', '{rt%1}')

			text = text:gsub('|T13700([1-8])[^|]+|t', '{rt%1}') -- raid icons
			text = text:gsub('|T[^|]+|t', '') -- Remove icons to prevent copying issues
			text = text:gsub('|K[^|]+|k', '<Protected Text>') -- Remove protected text
			module:SetPopupText(text)
		elseif IsShiftKeyDown() then
			if ChatFrame:IsVisible() then
				ChatFrame:Hide()
			else
				ChatFrame:Show()
			end
		end

		if ChatFrameEdit:IsVisible() then
			ChatFrameEdit:Hide()
		end
	end
	local TabHintEnter = function(frame)
		if not module.DB.ChatCopyTip then
			return
		end

		ShowUIPanel(GameTooltip)
		GameTooltip:SetOwner(frame, 'ANCHOR_TOP')
		GameTooltip:AddLine('Alt+Click to copy', 0.8, 0, 0)
		GameTooltip:AddLine('Shift+Click to toggle', 0, 0.1, 1)
		GameTooltip:AddLine('Shift+Ctrl+Click to clear', 0.8, 0.4, 0)
		GameTooltip:Show()
	end
	local TabHintLeave = function(frame)
		if not module.DB.ChatCopyTip then
			return
		end

		HideUIPanel(GameTooltip)
	end

	local GDM = _G['GeneralDockManager']
	if not GDM.SetBackdrop then
		Mixin(GDM, BackdropTemplateMixin)
	end

	if GDM.SetBackdrop then
		GDM:SetBackdrop(chatBG)
		GDM:SetBackdropColor(c.r, c.g, c.b, c.a)
		GDM:SetBackdropBorderColor(c.r, c.g, c.b, c.a)
	end
	GDM:ClearAllPoints()
	GDM:SetPoint('BOTTOMLEFT', _G['ChatFrame1Background'], 'TOPLEFT', -1, 1)
	GDM:SetPoint('BOTTOMRIGHT', _G['ChatFrame1Background'], 'TOPRIGHT', 1, 1)

	ChatAlertFrame:ClearAllPoints()
	ChatAlertFrame:SetPoint('BOTTOMLEFT', GDM, 'TOPLEFT', 0, 2)

	local QJTB = _G['QuickJoinToastButton']
	if QJTB then
		QJTB:ClearAllPoints()
		QJTB:SetSize(18, 18)
		StripTextures(QJTB)

		QJTB:ClearAllPoints()
		QJTB:SetPoint('TOPRIGHT', GDM, 'TOPRIGHT', -2, -3)
		QJTB.FriendCount:Hide()
		hooksecurefunc(QJTB, 'UpdateQueueIcon', function(frame)
			if not frame.displayedToast then
				return
			end
			frame.FriendsButton:SetTexture(icon)
			frame.QueueButton:SetTexture(icon)
			frame.FlashingLayer:SetTexture(icon)
			frame.FriendsButton:SetShown(false)
			frame.FriendCount:SetShown(false)
		end)
		hooksecurefunc(QJTB, 'SetPoint', function(frame, point, anchor)
			if anchor ~= GDM and point ~= 'TOPRIGHT' then
				frame:ClearAllPoints()
				frame:SetPoint('TOPRIGHT', GDM, 'TOPRIGHT', -2, -3)
			end
		end)

		local function updateTexture()
			QJTB.FriendsButton:SetTexture(icon)
			QJTB.QueueButton:SetTexture(icon)
		end
		QJTB:HookScript('OnMouseDown', updateTexture)
		QJTB:HookScript('OnMouseUp', updateTexture)
		updateTexture()

		QJTB.FriendsButton:SetTexture(icon)
		QJTB.FriendsButton:SetTexCoord(0.08, 0.4, 0.6, 0.9)
		QJTB.FriendsButton:ClearAllPoints()
		QJTB.FriendsButton:SetPoint('CENTER')
		QJTB.FriendsButton:SetSize(18, 18)

		QJTB.QueueButton:SetTexture(icon)
		QJTB.QueueButton:SetTexCoord(0.6, 0.9, 0.08, 0.4)
		QJTB.QueueButton:ClearAllPoints()
		QJTB.QueueButton:SetPoint('CENTER')
		QJTB.QueueButton:SetSize(18, 18)

		QJTB.FlashingLayer:SetTexture(icon)
		QJTB.FlashingLayer:SetTexCoord(0.6, 0.9, 0.08, 0.4)
		QJTB.FlashingLayer:ClearAllPoints()
		QJTB.FlashingLayer:SetPoint('CENTER')
		QJTB.FlashingLayer:SetSize(20, 20)

		QJTB.Toast:ClearAllPoints()
		QJTB.Toast:SetPoint('BOTTOMLEFT', QJTB, 'TOPLEFT')
		QJTB.Toast2:ClearAllPoints()
		QJTB.Toast2:SetPoint('BOTTOMLEFT', QJTB, 'TOPLEFT')
	end

	BNToastFrame:ClearAllPoints()
	BNToastFrame:SetPoint('BOTTOM', GDM, 'TOP')
	local function fixbnetpos(frame, _, anchor)
		if anchor ~= GDM then
			frame:ClearAllPoints()
			BNToastFrame:SetPoint('BOTTOM', GDM, 'TOP')
		end
	end
	hooksecurefunc(BNToastFrame, 'SetPoint', fixbnetpos)

	local VoiceChannelButton = _G['ChatFrameChannelButton']
	if VoiceChannelButton then
		VoiceChannelButton:ClearAllPoints()
		VoiceChannelButton:SetParent(GDM)
		-- Position relative to QJTB if it exists, otherwise to the right edge of GDM
		if QJTB then
			VoiceChannelButton:SetPoint('RIGHT', QJTB, 'LEFT', -1, 0)
		else
			VoiceChannelButton:SetPoint('TOPRIGHT', GDM, 'TOPRIGHT', -2, -3)
		end
		StripTextures(VoiceChannelButton)
		VoiceChannelButton:SetSize(18, 18)
		-- Create Icon if it doesn't exist (Classic/TBC)
		if not VoiceChannelButton.Icon then
			VoiceChannelButton.Icon = VoiceChannelButton:CreateTexture(nil, 'ARTWORK')
			VoiceChannelButton.Icon:SetAllPoints(VoiceChannelButton)
		end
		VoiceChannelButton.Icon:SetTexture(icon)
		VoiceChannelButton.Icon:SetTexCoord(0.1484375, 0.359375, 0.1484375, 0.359375)
		VoiceChannelButton.Icon:SetScale(0.8)
	end

	if ChatFrameMenuButton then
		ChatFrameMenuButton:ClearAllPoints()
		ChatFrameMenuButton:SetParent(GDM)
		-- Position relative to VoiceChannelButton if it exists, otherwise to GDM
		if VoiceChannelButton then
			ChatFrameMenuButton:SetPoint('RIGHT', VoiceChannelButton, 'LEFT', -1, -2)
		elseif QJTB then
			ChatFrameMenuButton:SetPoint('RIGHT', QJTB, 'LEFT', -1, 0)
		else
			ChatFrameMenuButton:SetPoint('TOPRIGHT', GDM, 'TOPRIGHT', -2, -3)
		end
		ChatFrameMenuButton:SetSize(18, 18)
		StripTextures(ChatFrameMenuButton)
		if not ChatFrameMenuButton.Icon then
			ChatFrameMenuButton.Icon = ChatFrameMenuButton:CreateTexture(nil, 'ARTWORK')
			ChatFrameMenuButton.Icon:SetAllPoints(ChatFrameMenuButton)
		end
		ChatFrameMenuButton.Icon:SetTexture(icon)
		ChatFrameMenuButton.Icon:SetTexCoord(0.6, 0.9, 0.6, 0.9)
	end

	for i = 1, 10 do
		local ChatFrameName = ('%s%d'):format('ChatFrame', i)

		--Allow arrow keys editing in the edit box
		local ChatFrameEdit = _G[ChatFrameName .. 'EditBox']

		--Setup Chatbox History
		ChatFrameEdit:SetAltArrowKeyMode(false)
		ChatFrameEdit.historyIndex = 0

		ChatFrameEdit:HookScript('OnKeyDown', module.ChatEdit_OnKeyDown)
		module:SecureHook(ChatFrameEdit, 'AddHistoryLine', 'ChatEdit_AddHistory')

		-- Setup chat message modification
		local ChatFrame = _G[ChatFrameName]
		hooksecurefunc(ChatFrame.historyBuffer, 'PushFront', ModifyMessage)
		module:HookScript(ChatFrame, 'OnHyperlinkEnter', OnHyperlinkEnter)
		module:HookScript(ChatFrame, 'OnHyperlinkLeave', OnHyperlinkLeave)

		if ChatFrame.Selection then
			ChatFrame.Selection:ClearAllPoints()
			ChatFrame.Selection:SetPoint('TOPLEFT', ChatFrame, 'TOPLEFT', 0, 30)
			ChatFrame.Selection:SetPoint('BOTTOMRIGHT', ChatFrame, 'BOTTOMRIGHT', 25, -32)
		end

		-- Now we can skin everything
		-- First lets setup some settings
		ChatFrame:SetClampRectInsets(0, 0, 0, 0)
		ChatFrame:SetClampedToScreen(false)

		-- Setup main BG
		local _, _, r, g, b, a = FCF_GetChatWindowInfo(i)
		if r == 0 and g == 0 and b == 0 and ((SUI.IsRetail and a < 0.16 and a > 0.15) or (SUI.IsClassic and a < 0.1)) then
			FCF_SetWindowColor(ChatFrame, DEFAULT_CHATFRAME_COLOR.r, DEFAULT_CHATFRAME_COLOR.g, DEFAULT_CHATFRAME_COLOR.b)
			FCF_SetWindowAlpha(ChatFrame, DEFAULT_CHATFRAME_ALPHA)
		end
		if ChatFrame.SetBackdrop then
			ChatFrame:SetBackdrop(nil)
		end

		--Setup Scrollbar
		if ChatFrame.ScrollBar and ChatFrame.ScrollBar.ThumbTexture then
			ChatFrame.ScrollBar.ThumbTexture:SetColorTexture(1, 1, 1, 0.4)
			ChatFrame.ScrollBar.ThumbTexture:SetWidth(10)

			StripTextures(ChatFrame.ScrollToBottomButton)
			local BG = ChatFrame.ScrollToBottomButton:CreateTexture()
			BG = ChatFrame.ScrollToBottomButton:CreateTexture(nil, 'ARTWORK')
			BG:SetAllPoints(ChatFrame.ScrollToBottomButton)
			BG:SetTexture('Interface\\Addons\\SpartanUI\\images\\chatbox\\bottomArrow')
			BG:SetAlpha(0.4)
			ChatFrame.ScrollToBottomButton.BG = BG
			ChatFrame.ScrollToBottomButton:ClearAllPoints()
			ChatFrame.ScrollToBottomButton:SetSize(20, 20)
			ChatFrame.ScrollToBottomButton:SetPoint('BOTTOMRIGHT', ChatFrame.ResizeButton, 'TOPRIGHT', -4, 0)
		end

		--Skin the Tab
		local ChatFrameTab = _G[ChatFrameName .. 'Tab']
		ChatFrameTab:HookScript('OnClick', TabClick)
		ChatFrameTab:HookScript('OnEnter', TabHintEnter)
		ChatFrameTab:HookScript('OnLeave', TabHintLeave)
		ChatFrameTab.Text:ClearAllPoints()
		ChatFrameTab.Text:SetPoint('CENTER', ChatFrameTab)

		if SUI.IsRetail then
			local sides = { 'Left', 'Middle', 'Right' }
			local modes = { 'Active', 'Highlight', '' }

			for _, mode in ipairs(modes) do
				for _, side in ipairs(sides) do
					ChatFrameTab[mode .. side]:SetTexture(nil)
				end
			end
		else
			for _, v in ipairs({ 'left', 'middle', 'right' }) do
				ChatFrameTab[v .. 'HighlightTexture']:SetTexture(nil)
				ChatFrameTab[v .. 'SelectedTexture']:SetTexture(nil)
				ChatFrameTab[v .. 'Texture']:SetTexture(nil)
			end
		end

		-- Setup Editbox
		local EBLeft = _G[ChatFrameName .. 'EditBoxLeft']
		local EBMid = _G[ChatFrameName .. 'EditBoxMid']
		local EBRight = _G[ChatFrameName .. 'EditBoxRight']
		EBLeft:Hide()
		EBRight:Hide()
		EBMid:Hide()

		local header = _G[ChatFrameName .. 'EditBoxHeader']
		local _, s, m = header:GetFont()
		SUI.Font:Format(header, s, 'Chatbox')
		SUI.Font:Format(ChatFrame, module.DB.fontSize, 'Chatbox')
		SUI.Font:Format(ChatFrameEdit, module.DB.fontSize, 'Chatbox')

		if _G[ChatFrameName .. 'EditBoxFocusLeft'] ~= nil then
			_G[ChatFrameName .. 'EditBoxFocusLeft']:SetTexture(nil)
		end
		if _G[ChatFrameName .. 'EditBoxFocusRight'] ~= nil then
			_G[ChatFrameName .. 'EditBoxFocusRight']:SetTexture(nil)
		end
		if _G[ChatFrameName .. 'EditBoxFocusMid'] ~= nil then
			_G[ChatFrameName .. 'EditBoxFocusMid']:SetTexture(nil)
		end

		ChatFrameEdit:Hide()
		ChatFrameEdit:SetHeight(22)

		local function disable(element)
			if element.UnregisterAllEvents then
				element:UnregisterAllEvents()
				element:SetParent(nil)
			end
			element.Show = element.Hide

			element:Hide()
		end

		if not ChatFrameEdit.SetBackdrop then
			Mixin(ChatFrameEdit, BackdropTemplateMixin)
		end
		if ChatFrameEdit.SetBackdrop then
			ChatFrameEdit:SetBackdrop(chatBG)
			local bg = { ChatFrame.Background:GetVertexColor() }
			ChatFrameEdit:SetBackdropColor(unpack(bg))
			ChatFrameEdit:SetBackdropBorderColor(unpack(bg))
		end

		local function BackdropColorUpdate(frame, r, g, b)
			local bg = { ChatFrame.Background:GetVertexColor() }
			if ChatFrameEdit.SetBackdrop then
				ChatFrameEdit:SetBackdropColor(unpack(bg))
				ChatFrameEdit:SetBackdropBorderColor(unpack(bg))
			end
		end
		hooksecurefunc(ChatFrame.Background, 'SetVertexColor', BackdropColorUpdate)

		-- Edit box focus textures (retail only)
		local EBFocusLeft = _G[ChatFrameName .. 'EditBoxFocusLeft']
		local EBFocusMid = _G[ChatFrameName .. 'EditBoxFocusMid']
		local EBFocusRight = _G[ChatFrameName .. 'EditBoxFocusRight']
		if EBFocusLeft and EBFocusMid and EBFocusRight then
			EBFocusLeft:SetVertexColor(c.r, c.g, c.b, c.a)
			EBFocusMid:SetVertexColor(c.r, c.g, c.b, c.a)
			EBFocusRight:SetVertexColor(c.r, c.g, c.b, c.a)

			-- Ensure the edit box hides all textures
			local EditBoxFocusHide = function(frame)
				ChatFrameEdit:Hide()
			end
			hooksecurefunc(EBFocusMid, 'Hide', EditBoxFocusHide)
		end

		-- Only disable the ButtonFrame if hideChatButtons is enabled
		-- The ButtonFrame contains scroll buttons (up, down, bottom) that users may want
		local buttonFrame = _G[ChatFrameName .. 'ButtonFrame']
		if buttonFrame then
			if module.DB.hideChatButtons then
				disable(buttonFrame)
			end
			-- Note: If hideChatButtons is false, ApplyHideChatButtons() will handle visibility
		end
	end

	module:EditBoxPosition()

	ChatFrame_AddMessageEventFilter('CHAT_MSG_CHANNEL', filterFunc)
	ChatFrame_AddMessageEventFilter('CHAT_MSG_YELL', filterFunc)
	ChatFrame_AddMessageEventFilter('CHAT_MSG_GUILD', filterFunc)
	ChatFrame_AddMessageEventFilter('CHAT_MSG_OFFICER', filterFunc)
	ChatFrame_AddMessageEventFilter('CHAT_MSG_PARTY', filterFunc)
	ChatFrame_AddMessageEventFilter('CHAT_MSG_PARTY_LEADER', filterFunc)
	ChatFrame_AddMessageEventFilter('CHAT_MSG_RAID', filterFunc)
	ChatFrame_AddMessageEventFilter('CHAT_MSG_RAID_LEADER', filterFunc)
	ChatFrame_AddMessageEventFilter('CHAT_MSG_INSTANCE_CHAT', filterFunc)
	ChatFrame_AddMessageEventFilter('CHAT_MSG_INSTANCE_CHAT_LEADER', filterFunc)
	ChatFrame_AddMessageEventFilter('CHAT_MSG_SAY', filterFunc)
	ChatFrame_AddMessageEventFilter('CHAT_MSG_WHISPER', filterFunc)
	ChatFrame_AddMessageEventFilter('CHAT_MSG_WHISPER_INFORM', filterFunc)
	ChatFrame_AddMessageEventFilter('CHAT_MSG_BN_WHISPER', filterFunc)
	ChatFrame_AddMessageEventFilter('CHAT_MSG_BN_WHISPER_INFORM', filterFunc)
	ChatFrame_AddMessageEventFilter('CHAT_MSG_BN_CONVERSATION', filterFunc)
	ChatFrame_AddMessageEventFilter('CHAT_MSG_BN_INLINE_TOAST_BROADCAST', filterFunc)
	ChatFrame_AddMessageEventFilter('CHAT_MSG_COMMUNITIES_CHANNEL', filterFunc)
end

local SetHyperlink = ItemRefTooltip.SetHyperlink
function ItemRefTooltip:SetHyperlink(data, ...)
	local isURL, link = strsplit('~', data)
	if isURL and isURL == 'bcmurl' then
		module:SetPopupText(link)
	else
		SetHyperlink(self, data, ...)
	end
end

function module:CleanupOldChatLog()
	if not self.DB.chatLog.history then
		return
	end

	local currentTime = time()
	local expirationTime = currentTime - (self.DB.chatLog.expireDays * 24 * 60 * 60)
	local maxEntries = self.DB.chatLog.maxEntries

	-- Remove expired entries
	for i = #self.DB.chatLog.history, 1, -1 do
		if self.DB.chatLog.history[i].timestamp < expirationTime then
			table.remove(self.DB.chatLog.history, i)
		end
	end

	-- Trim to max entries
	while #self.DB.chatLog.history > maxEntries do
		table.remove(self.DB.chatLog.history, 1)
	end
end

-- Add functions to manage the blacklist
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
	-- Clear the current profile's chat log
	wipe(self.DB.chatLog.history)

	-- Clear chat logs from all other profiles
	for profileName, profileData in pairs(SUI.SpartanUIDB.profiles) do
		if profileData.Chatbox and profileData.Chatbox.chatLog then
			wipe(profileData.Chatbox.chatLog.history)
		end
	end

	SUI:Print(L['All chat logs cleared from all profiles'])
end

function module:BuildOptions()
	--@type AceConfig.OptionsTable
	local optTable = {
		type = 'group',
		name = L['Chatbox'],
		childGroups = 'tab',
		disabled = function()
			return SUI:IsModuleDisabled(module)
		end,
		get = function(info)
			return module.DB[info[#info]]
		end,
		set = function(info, val)
			module.DB[info[#info]] = val
			module:EditBoxPosition()
		end,
		args = {
			timestampFormat = {
				name = L['Timestamp format'],
				type = 'select',
				order = 2,
				values = {
					[''] = 'Disabled',
					['%I:%M:%S %p'] = 'HH:MM:SS AM (12-hour)',
					['%I:%M:%S'] = 'HH:MM:SS (12-hour)',
					['%X'] = 'HH:MM:SS (24-hour)',
					['%I:%M'] = 'HH:MM (12-hour)',
					['%H:%M'] = 'HH:MM (24-hour)',
					['%M:%S'] = 'MM:SS',
				},
			},
			autoLeaverOutput = {
				name = L['Automatically output number of BG leavers to instance chat if over 15'],
				type = 'toggle',
			},
			shortenChannelNames = {
				name = L['Shorten channel names'],
				type = 'toggle',
			},
			EditBoxTop = {
				name = L['Edit box on top'],
				type = 'toggle',
			},
			playerlevel = {
				name = L['Display level'],
				type = 'toggle',
				order = 1,
			},
			webLinks = {
				name = L['Clickable web link'],
				type = 'toggle',
				order = 20,
			},
			LinkHover = {
				name = L['Hoveable game links'],
				type = 'toggle',
				order = 21,
			},
			convenienceHeader = {
				name = L['Convenience'],
				type = 'header',
				order = 30,
			},
			hideChatButtons = {
				name = L['Hide chat buttons'],
				desc = L['Hide the menu and voice channel buttons'],
				type = 'toggle',
				order = 31,
				set = function(info, val)
					module.DB.hideChatButtons = val
					module:ApplyHideChatButtons()
				end,
			},
			hideSocialButton = {
				name = L['Hide social button'],
				desc = L['Hide the quick-join/social button'],
				type = 'toggle',
				order = 32,
				set = function(info, val)
					module.DB.hideSocialButton = val
					module:ApplyHideSocialButton()
				end,
			},
			disableChatFade = {
				name = L['Disable chat fade'],
				desc = L['Keep chat text visible indefinitely'],
				type = 'toggle',
				order = 33,
				set = function(info, val)
					module.DB.disableChatFade = val
					module:ApplyDisableChatFade()
				end,
			},
			chatHistoryLines = {
				name = L['Chat history lines'],
				desc = L['Maximum number of lines to keep in chat history (default 128, max 4096)'],
				type = 'range',
				order = 34,
				min = 128,
				max = 4096,
				step = 128,
				set = function(info, val)
					module.DB.chatHistoryLines = val
					module:ApplyChatHistoryLines()
				end,
			},
			chatLog = {
				name = L['Chat Log'],
				type = 'group',
				args = {
					enable = {
						name = L['Enable Chat Log'],
						desc = L['Enable saving chat messages to a log'],
						type = 'toggle',
						get = function()
							return module.DB.chatLog.enabled
						end,
						set = function(_, val)
							module.DB.chatLog.enabled = val
							if val then
								module:EnableChatLog()
							else
								module:DisableChatLog()
							end
						end,
						order = 1,
					},
					clearLog = {
						name = L['Clear Chat Log'],
						desc = L['Clear all saved chat log entries'],
						type = 'execute',
						func = function()
							module:ClearChatLog()
						end,
						order = 2,
					},
					clearAllLogs = {
						name = L['Clear All Chat Logs'],
						desc = L['Clear all saved chat log entries from all profiles'],
						type = 'execute',
						func = function()
							module:ClearAllChatLogs()
						end,
						order = 2.5, -- Place it after the existing clear log button
					},
					maxEntries = {
						name = L['Max Log Entries'],
						desc = L['Maximum number of chat log entries to keep'],
						type = 'range',
						disabled = function()
							return not module.DB.chatLog.enabled
						end,
						width = 'double',
						min = 1,
						max = 100,
						step = 1,
						get = function()
							return module.DB.chatLog.maxEntries
						end,
						set = function(_, val)
							module.DB.chatLog.maxEntries = val
							module:CleanupOldChatLog()
						end,
						order = 4,
					},
					expireDays = {
						name = L['Log Expiration (Days)'],
						desc = L['Number of days to keep chat log entries'],
						type = 'range',
						disabled = function()
							return not module.DB.chatLog.enabled
						end,
						width = 'double',
						min = 1,
						max = 90,
						step = 1,
						get = function()
							return module.DB.chatLog.expireDays
						end,
						set = function(_, val)
							module.DB.chatLog.expireDays = val
							module:CleanupOldChatLog()
						end,
						order = 5,
					},
					typesToLog = {
						name = L['Chat Types to Log'],
						type = 'multiselect',
						disabled = function()
							return not module.DB.chatLog.enabled
						end,
						values = {
							CHAT_MSG_SAY = L['Say'],
							CHAT_MSG_YELL = L['Yell'],
							CHAT_MSG_PARTY = L['Party'],
							CHAT_MSG_RAID = L['Raid'],
							CHAT_MSG_GUILD = L['Guild'],
							CHAT_MSG_OFFICER = L['Officer'],
							CHAT_MSG_WHISPER = L['Whisper'],
							CHAT_MSG_WHISPER_INFORM = L['Whisper Sent'],
							CHAT_MSG_INSTANCE_CHAT = L['Instance'],
							CHAT_MSG_CHANNEL = L['Channels'],
						},
						get = function(info, key)
							return module.DB.chatLog.typesToLog[key]
						end,
						set = function(info, key, value)
							module.DB.chatLog.typesToLog[key] = value
							module:EnableChatLog()
						end,
						order = 6,
					},
					blacklist = {
						name = L['Blacklist'],
						type = 'group',
						order = 7,
						inline = true,
						disabled = function()
							return not module.DB.chatLog.enabled
						end,
						args = {},
					},
				},
			},
		},
	}

	local function isBlacklistDuplicate(newString)
		for _, existingString in ipairs(module.DB.chatLog.blacklist.strings) do
			if newString:lower() == existingString:lower() then
				return true
			end
		end
		return false
	end

	local function applyBlacklistToHistory(blacklistString)
		local newHistory = {}
		local removed = 0
		for _, entry in ipairs(module.DB.chatLog.history) do
			if not string.find(entry.message:lower(), blacklistString:lower()) then
				table.insert(newHistory, entry)
			else
				removed = removed + 1
			end
		end
		if removed > 0 then
			SUI:Print(string.format(L['Removed %d entries containing %s'], removed, blacklistString))
		end
		module.DB.chatLog.history = newHistory
	end

	local function buildBlacklistOptions()
		local blacklistOpt = optTable.args.chatLog.args.blacklist.args
		table.wipe(blacklistOpt)

		blacklistOpt.desc = {
			name = L['Blacklisted strings will not be logged'],
			type = 'description',
			order = 1,
		}

		blacklistOpt.add = {
			name = L['Add Blacklist String'],
			desc = L['Add a string to the blacklist'],
			type = 'input',
			order = 2,
			set = function(_, val)
				if isBlacklistDuplicate(val) then
					SUI:Print(string.format(L["'%s' is already in the blacklist"], val))
				else
					table.insert(module.DB.chatLog.blacklist.strings, val)
					applyBlacklistToHistory(val)
					buildBlacklistOptions()
				end
			end,
		}

		blacklistOpt.list = {
			order = 3,
			type = 'group',
			inline = true,
			name = L['Blacklist'],
			args = {},
		}

		for index, entry in ipairs(module.DB.chatLog.blacklist.strings) do
			blacklistOpt.list.args[tostring(index) .. 'label'] = {
				type = 'description',
				width = 'double',
				fontSize = 'medium',
				order = index * 2 - 1,
				name = entry,
			}
			blacklistOpt.list.args[tostring(index)] = {
				type = 'execute',
				name = L['Delete'],
				width = 'half',
				order = index * 2,
				func = function()
					table.remove(module.DB.chatLog.blacklist.strings, index)
					buildBlacklistOptions()
				end,
			}
		end
	end

	buildBlacklistOptions()

	SUI.opt.args.Help.args.SUIModuleHelp.args.clearAllLogs = optTable.args.chatLog.args.clearAllLogs
	SUI.Options:AddOptions(optTable, 'Chatbox')
end

function module:SetEditBoxMessage(msg)
	if not ChatFrame1EditBox:IsShown() then
		ChatEdit_ActivateChat(ChatFrame1EditBox)
	end

	local editBoxText = ChatFrame1EditBox:GetText()
	if editBoxText and editBoxText ~= '' then
		ChatFrame1EditBox:SetText('')
	end
	ChatFrame1EditBox:Insert(msg)
	ChatFrame1EditBox:HighlightText()
end

SUI.Chat = module
