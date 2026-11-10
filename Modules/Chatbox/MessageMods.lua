---@class SUI
local SUI = SUI
---@class SUI.Module.Chatbox
local module = SUI:GetModule('Chatbox')

-- No visible body marker - we find the body boundary by locating the end
-- of the prefix structure (after suicopy link + player link + meta color spans).

local function getAmbiguateContext()
	return 'none'
end

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
	trade = true,
	battlepet = true,
	battlePetAbil = true,
	instancelock = true,
	journal = true,
	transmogappearance = true,
	transmogillusion = true,
	conduit = true,
	api = true,
	clubTicket = true,
	garrtrade = true,
	apower = true,
	azessence = true,
	keystone = true,
	worldmap = true,
}

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

function module:GetColor(input)
	local className, color

	if type(input) == 'string' and input:match('^Player%-') then
		_, className = GetPlayerInfoByGUID(input)
	elseif type(input) == 'string' then
		className = input
	end

	if className then
		color = RAID_CLASS_COLORS[className]
	end

	if color then
		return ('%02x%02x%02x'):format(color.r * 255, color.g * 255, color.b * 255)
	end

	return 'ffffff'
end

local changeName = function(fullName, misc, nameToChange, colon)
	if SUI.BlizzAPI.issecretvalue(fullName) then
		return '|Hplayer:' .. fullName .. misc .. '[' .. nameToChange .. ']' .. (colon == ':' and ' ' or colon) .. '|h'
	end
	local name = Ambiguate(fullName, 'none')
	local hasColor = nameToChange:find('|c', nil, true)
	if (module.nameColor and not hasColor and not module.nameColor[name]) or (module.ChatLevelLog and not module.ChatLevelLog[name]) then
		for i = 1, GetNumGuildMembers() do
			local n, _, _, l, _, _, _, _, _, _, c = GetGuildRosterInfo(i)
			if n then
				n = Ambiguate(n, 'none')
				if n == name then
					if module.ChatLevelLog and l and l > 0 then
						module.ChatLevelLog[n] = tostring(l)
					end
					if module.nameColor and c and not hasColor then
						module.nameColor[n] = module:GetColor(c)
					end
					break
				end
			end
		end
	end
	if module.nameColor and not hasColor then
		if not module.nameColor[name] then
			local num = C_FriendList.GetNumWhoResults()
			for i = 1, num do
				local tbl = C_FriendList.GetWhoInfo(i)
				local n, l, c = tbl.fullName, tbl.level, tbl.filename
				if n == name and l and l > 0 then
					if module.ChatLevelLog then
						module.ChatLevelLog[n] = tostring(l)
					end
					if module.nameColor and c then
						module.nameColor[n] = module:GetColor(c)
					end
					break
				end
			end
		end
		if module.nameColor[name] then
			nameToChange = '|cFF' .. module.nameColor[name] .. nameToChange .. '|r'
		end
	end
	if module.ChatLevelLog and module.ChatLevelLog[name] and module.CurrentSettings.playerlevel then
		local color = GetHexColor(GetQuestDifficultyColor(module.ChatLevelLog[name]))
		nameToChange = '|cff' .. color .. module.ChatLevelLog[name] .. '|r:' .. nameToChange
	end
	return '|Hplayer:' .. fullName .. misc .. '[' .. nameToChange .. ']' .. (colon == ':' and ' ' or colon) .. '|h'
end

function module:PlayerName(text)
	text = text:gsub('|Hplayer:([^:|]+)([^%[]+)%[([^%]]+)%]|h(:?)', changeName)
	return text
end

-- Channel label tables keyed by event type.
-- Each entry has: short (1-2 char), name (word), full (full name).
-- CHAT_MSG_CHANNEL and CHAT_MSG_COMMUNITIES_CHANNEL are handled dynamically.
local channelLabels = {
	CHAT_MSG_SAY = { short = 'S', name = 'Say', full = 'Say' },
	CHAT_MSG_YELL = { short = 'Y', name = 'Yell', full = 'Yell' },
	CHAT_MSG_GUILD = { short = 'G', name = 'Guild', full = 'Guild' },
	CHAT_MSG_OFFICER = { short = 'O', name = 'Officer', full = 'Officer' },
	CHAT_MSG_PARTY = { short = 'P', name = 'Party', full = 'Party' },
	CHAT_MSG_PARTY_LEADER = { short = 'P', name = 'Party', full = 'Party' },
	CHAT_MSG_RAID = { short = 'R', name = 'Raid', full = 'Raid' },
	CHAT_MSG_RAID_LEADER = { short = 'R', name = 'Raid', full = 'Raid' },
	CHAT_MSG_RAID_WARNING = { short = 'RW', name = 'Raid', full = 'Raid Warning' },
	CHAT_MSG_INSTANCE_CHAT = { short = 'I', name = 'Instance', full = 'Instance' },
	CHAT_MSG_INSTANCE_CHAT_LEADER = { short = 'I', name = 'Instance', full = 'Instance' },
	CHAT_MSG_WHISPER = { short = 'W', name = 'Whisper', full = 'Whisper' },
	CHAT_MSG_WHISPER_INFORM = { short = 'W', name = 'Whisper', full = 'Whisper' },
	CHAT_MSG_BN_WHISPER = { short = 'BW', name = 'BNet', full = 'BNet Whisper' },
	CHAT_MSG_BN_WHISPER_INFORM = { short = 'BW', name = 'BNet', full = 'BNet Whisper' },
	CHAT_MSG_BN_CONVERSATION = { short = 'BW', name = 'BNet', full = 'BNet' },
	CHAT_MSG_BN_INLINE_TOAST_BROADCAST = { short = 'BW', name = 'BNet', full = 'BNet' },
	CHAT_MSG_SYSTEM = { short = '', name = '', full = '' },
	CHAT_MSG_EMOTE = { short = 'E', name = 'Emote', full = 'Emote' },
	CHAT_MSG_TEXT_EMOTE = { short = 'E', name = 'Emote', full = 'Emote' },
}

-- Short abbreviations for well-known dynamic channel names.
-- Checked in order: full baseName (lowercased, spaces/punctuation stripped) first,
-- then first-word fallback. This distinguishes "Trade - City" from "Trade - Services".
local dynamicChannelShortFull = {
	['tradeservicescity'] = 'TS',
	['tradeservices'] = 'TS',
}
local dynamicChannelShortFirst = {
	trade = 'T',
	general = 'GN',
	localdefense = 'LD',
	lookingforgroup = 'LFG',
	worlddefense = 'WD',
	newcomerchat = 'NC',
	services = 'SV',
}

-- Build the channel string from available data based on the user's style preference.
-- For named channels (CHAT_MSG_CHANNEL / COMMUNITIES_CHANNEL), channelIndex and
-- channelBaseName are the raw values from the filter args.
local function buildChannelStr(event, channelIndex, channelBaseName)
	-- Check per-channel visibility toggle
	local ci = module.CurrentSettings.channelIndicator
	if ci then
		local isDynamic = (event == 'CHAT_MSG_CHANNEL' or event == 'CHAT_MSG_COMMUNITIES_CHANNEL')
		if isDynamic then
			if ci.dynamicChannels == false then
				return ''
			end
		elseif ci[event] == false then
			return ''
		end
	end

	local style = module.CurrentSettings.channelStyle or 'short'
	local labels = channelLabels[event]

	if labels then
		-- Fixed channel types (say, guild, whisper, etc.)
		if style == 'number' then
			return labels.short -- no number for fixed channels, fall back to short
		elseif style == 'short' then
			return labels.short
		elseif style == 'name' then
			return labels.name
		elseif style == 'full' then
			return labels.full
		elseif style == 'number_full' then
			return labels.full
		end
		return labels.short
	end

	-- Dynamic channels: CHAT_MSG_CHANNEL, CHAT_MSG_COMMUNITIES_CHANNEL
	local baseName = channelBaseName or ''
	local index = channelIndex or ''
	local firstName = baseName:match('^(%S+)') or baseName
	local fullKey = baseName:lower():gsub('[^%a]', '')

	if style == 'number' then
		return tostring(index)
	elseif style == 'short' then
		local abbrev = dynamicChannelShortFull[fullKey] or dynamicChannelShortFirst[firstName:lower()]
		if abbrev then
			return abbrev
		end
		-- Unknown channel: use first 1-2 uppercase letters
		return firstName:sub(1, 2):upper()
	elseif style == 'name' then
		return firstName
	elseif style == 'full' then
		return baseName
	elseif style == 'number_full' then
		if index ~= '' then
			return index .. '. ' .. baseName
		end
		return baseName
	end
	return firstName
end

-- Format presets (module-level so Options.lua can access them)
module.FormatPresets = {
	default = '[%TIME%] [%CHANNEL%] %CHARACTER%: %MESSAGE%',
	nobrackets = '[%TIME%] [%CHANNEL%] %CHARACTER%: %MESSAGE%',
	compact = '[%TIME%] %CHARACTER%: %MESSAGE%',
	nochannel = '[%TIME%] [%CHARACTER%]: %MESSAGE%',
	timeonly = '[%TIME%] %MESSAGE%',
}

-- Helper: strip [TOKEN] brackets when token is empty
local function substituteToken(str, tokenName, value)
	if value == '' then
		str = str:gsub('%[%%' .. tokenName .. '%%%]%s*', '')
		str = str:gsub('%%' .. tokenName .. '%%%s*', '')
	else
		str = str:gsub('%%' .. tokenName .. '%%', value)
	end
	return str
end

----------------------------------------------------------------------------------------------------
-- Prefix building (shared between live filter and retroactive refresh)
----------------------------------------------------------------------------------------------------

-- Per-line metadata stored for retroactive re-rendering.
-- Keyed by suicopy line index. Capped to prevent unbounded growth.
module.lineData = module.lineData or {}
local LINE_DATA_MAX = 500

-- Tag pattern embedded in message text by the filter for AddMessage correlation.
-- Using an invisible hyperlink ensures the tag survives Blizzard's formatting pipeline.
local SUI_SEQ_PATTERN = '|Hsuiseq:(%d+)|h|h'

local function pruneLineData()
	local count = 0
	local minKey
	for k in pairs(module.lineData) do
		count = count + 1
		if not minKey or k < minKey then
			minKey = k
		end
	end
	if count > LINE_DATA_MAX and minKey then
		local cutoff = minKey + (count - LINE_DATA_MAX)
		for k in pairs(module.lineData) do
			if k < cutoff then
				module.lineData[k] = nil
			end
		end
	end
end

-- Outgoing whisper events where we prepend "To" before the name
local informEvents = {
	CHAT_MSG_WHISPER_INFORM = true,
	CHAT_MSG_BN_WHISPER_INFORM = true,
}

-- BNet chat events that use |HBNplayer: links
local bnetEvents = {
	CHAT_MSG_BN_WHISPER = true,
	CHAT_MSG_BN_WHISPER_INFORM = true,
	CHAT_MSG_BN_CONVERSATION = true,
	CHAT_MSG_BN_INLINE_TOAST_BROADCAST = true,
}

---The part of a player link after "player:". It carries the chat line the same way the game's own
---chat does, because the right-click menu only offers to report a message when it has that line.
---@param senderName string
---@param event string
---@param lineID any
---@param channelIndex any
---@return string
local function playerLinkTarget(senderName, event, lineID, channelIndex)
	if type(lineID) ~= 'number' or not SUI.BlizzAPI.canaccessvalue(lineID) or lineID <= 0 then
		return senderName
	end

	local chatType = event:sub(10)
	local chatGroup = chatType
	if ChatFrameUtil and ChatFrameUtil.GetChatCategory then
		chatGroup = ChatFrameUtil.GetChatCategory(chatType) or chatType
	end

	local chatTarget = ''
	if FCFManager_GetChatTarget and SUI.BlizzAPI.canaccessvalue(channelIndex) then
		chatTarget = FCFManager_GetChatTarget(chatGroup, senderName, channelIndex) or ''
	end

	return senderName .. ':' .. lineID .. ':' .. chatGroup .. ':' .. chatTarget
end

-- Build a native |Hplayer:Name|h or |HBNplayer:...|h link for native click behavior.
-- Returns: plainName, playerLink
local function buildCharacterStr(data)
	local senderName = data.senderName
	local senderClass = data.senderClass
	if not senderName or senderName == '' or SUI.BlizzAPI.issecretvalue(senderName) then
		return '', ''
	end

	local event = data.event or ''
	local isBNet = bnetEvents[event]
	local isInform = informEvents[event]
	local toPrefix = isInform and 'To ' or ''

	-- For BNet events, resolve display name and class from BNet API
	if isBNet and data.bnSenderID then
		local accountInfo = C_BattleNet and C_BattleNet.GetAccountInfoByID(data.bnSenderID)
		if accountInfo then
			local gameInfo = accountInfo.gameAccountInfo
			-- Prefer battleTag (without #numbers) since accountName may be |K protected
			local displayName = (accountInfo.battleTag and accountInfo.battleTag:gsub('#%d+$', '')) or accountInfo.accountName or senderName

			-- Get class color from game account info
			local hex
			local nameColorStyle = module.CurrentSettings.nameColorStyle or 'class'
			if nameColorStyle ~= 'none' and gameInfo and gameInfo.className and gameInfo.className ~= '' then
				hex = module:GetColor(gameInfo.className)
			end

			-- Build |HBNplayer: link for proper click behavior
			local chatType = event:sub(10) -- strip "CHAT_MSG_"
			local linkText
			if hex then
				linkText = '[|cFF' .. hex .. displayName .. '|r]'
			else
				linkText = '[' .. displayName .. ']'
			end
			local playerLink = GetBNPlayerLink(senderName, linkText, data.bnSenderID, data.lineID or 0, chatType, 0)
			return toPrefix .. displayName, toPrefix .. playerLink
		end
	end

	local charStr = Ambiguate(senderName, getAmbiguateContext())
	local nameColorStyle = module.CurrentSettings.nameColorStyle or 'class'

	local hex
	if nameColorStyle ~= 'none' then
		hex = module.nameColor and module.nameColor[charStr]
		if not hex and senderClass then
			hex = module:GetColor(senderClass)
			module.nameColor[charStr] = hex
		end
	end

	-- Level prefix
	local levelPrefix = ''
	if module.CurrentSettings.playerlevel and module.ChatLevelLog and module.ChatLevelLog[charStr] then
		local level = module.ChatLevelLog[charStr]
		local color = GetHexColor(GetQuestDifficultyColor(level))
		levelPrefix = '|cff' .. color .. level .. '|r:'
	end

	local linkTarget = playerLinkTarget(senderName, event, data.lineID, data.channelIndex)
	local playerLink
	if hex then
		playerLink = levelPrefix .. '|cFF' .. hex .. '|Hplayer:' .. linkTarget .. '|h' .. charStr .. '|h|r'
	else
		playerLink = levelPrefix .. '|Hplayer:' .. linkTarget .. '|h' .. charStr .. '|h'
	end

	return toPrefix .. charStr, toPrefix .. playerLink
end

-- Build a prefix string from stored line data and current settings.
-- Returns: metaPrefix (with placeholder for character), playerLink, charPlaceholder
local function buildPrefix(data)
	local fmt = module.CurrentSettings.messageFormat
	if not fmt or fmt == '' then
		return '', ''
	end

	-- TIME token
	local timeStr = ''
	if module.CurrentSettings.timestampFormat and module.CurrentSettings.timestampFormat ~= '' then
		local timeFmt = module.CurrentSettings.timestampFormat
		if module.CurrentSettings.timestampShowAMPM and timeFmt:find('%%I') then
			timeFmt = timeFmt .. ' %p'
		end
		timeStr = date(timeFmt, data.timestamp)
	end

	-- CHANNEL token
	local channelStr = buildChannelStr(data.event, data.channelIndex, data.channelBaseName)

	-- CHARACTER token
	local charStr, playerLink = buildCharacterStr(data)

	-- Use a unique placeholder for the character so we can split around it
	local CHAR_PLACEHOLDER = '\1CHAR\1'
	local prefix = fmt:gsub('%%MESSAGE%%.*$', '')
	prefix = substituteToken(prefix, 'TIME', timeStr)
	prefix = substituteToken(prefix, 'CHANNEL', channelStr)
	if charStr ~= '' then
		prefix = prefix:gsub('%[%%CHARACTER%%%]', CHAR_PLACEHOLDER)
		prefix = prefix:gsub('%%CHARACTER%%', CHAR_PLACEHOLDER)
	else
		prefix = substituteToken(prefix, 'CHARACTER', '')
	end
	prefix = prefix:gsub('%[%%LEVEL%%%]%s*:?%s*', '')
	prefix = prefix:gsub('%%LEVEL%%%s*:?%s*', '')
	prefix = prefix:gsub('[%s%-]+$', '')

	return prefix, playerLink, CHAR_PLACEHOLDER
end

-- Wrap prefix text in suicopy hyperlink with current meta color.
-- Player link is kept outside suicopy so Blizzard handles native click behavior.
local function wrapPrefix(metaPrefix, lineIndex, playerLink, charPlaceholder)
	if metaPrefix == '' then
		return ''
	end
	local mc = module.CurrentSettings.metaColor or { r = 0.49, g = 0.49, b = 0.49 }
	local metaHex = ('ff%02x%02x%02x'):format(mc.r * 255, mc.g * 255, mc.b * 255)

	if playerLink and playerLink ~= '' and charPlaceholder and metaPrefix:find(charPlaceholder, 1, true) then
		local pos = metaPrefix:find(charPlaceholder, 1, true)
		local before = metaPrefix:sub(1, pos - 1)
		local after = metaPrefix:sub(pos + #charPlaceholder)
		local result = ''
		if before ~= '' then
			result = '|Hsuicopy:' .. lineIndex .. '|h|c' .. metaHex .. before .. '|r|h'
		else
			result = '|Hsuicopy:' .. lineIndex .. '|h|h'
		end
		result = result .. playerLink
		if after ~= '' then
			result = result .. '|c' .. metaHex .. after .. '|r'
		end
		return result .. ' '
	end

	return '|Hsuicopy:' .. lineIndex .. '|h|c' .. metaHex .. metaPrefix .. '|r|h '
end

-- Expose for ChatLog history restore
module.buildPrefix = buildPrefix
module.wrapPrefix = wrapPrefix

----------------------------------------------------------------------------------------------------
-- Retroactive refresh: re-compose all SUI-formatted lines with current settings
----------------------------------------------------------------------------------------------------

function module:RefreshChatAppearance()
	SUI.DBM:RefreshSettings(module)

	local lineData = module.lineData
	if not lineData then
		return
	end

	for i = 1, NUM_CHAT_WINDOWS do
		local chatFrame = _G['ChatFrame' .. i]
		if chatFrame and chatFrame.TransformMessages then
			chatFrame:TransformMessages(function(message, r, g, b, ...)
				if not message then
					return false
				end
				local idx = message:match('|Hsuicopy:(%d+)|h')
				return idx and lineData[tonumber(idx)] ~= nil
			end, function(message, r, g, b, ...)
				local idx = tonumber(message:match('|Hsuicopy:(%d+)|h'))
				local data = lineData[idx]
				if not data then
					return message, r, g, b, ...
				end
				-- Extract body by stripping the prefix components
				local body = message
				body = body:gsub('^|Hsuicopy:%d+|h.-|h ?', '')
				body = body:gsub('^|cff%x%x%x%x%x%x%d+|r:', '')
				body = body:gsub('^|c%x%x%x%x%x%x%x%x|Hplayer:[^|]+|h[^|]*|h|r', '')
				body = body:gsub('^|Hplayer:[^|]+|h[^|]*|h', '')
				body = body:gsub('^|c%x%x%x%x%x%x%x%x[^|]*|r ?', '')
				body = body:gsub('^:%s*', '')
				body = body:gsub('^|T:0:0:0:0:0:0:0:0|t', '')
				local metaPrefix, playerLink, charPlaceholder = buildPrefix(data)
				local wrapped = wrapPrefix(metaPrefix, idx, playerLink, charPlaceholder)
				local newR, newG, newB = r, g, b
				local ccDB = module.CurrentSettings.channelColors
				if ccDB and ccDB.enabled and data.event and ccDB.colors[data.event] then
					local cc = ccDB.colors[data.event]
					newR, newG, newB = cc.r, cc.g, cc.b
					if ccDB.colorEntireMessage then
						local hex = ('%02x%02x%02x'):format(cc.r * 255, cc.g * 255, cc.b * 255)
						body = body:gsub('^|cff%x%x%x%x%x%x(.+)|r$', '%1')
						body = '|cff' .. hex .. body .. '|r'
					end
				end
				return wrapped .. body, newR, newG, newB, ...
			end)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Live message filter
----------------------------------------------------------------------------------------------------

local messageFormatFilter = function(chatFrame, event, msg, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, ...)
	local fmt = module.CurrentSettings.messageFormat
	if not fmt or fmt == '' then
		return
	end

	-- Skip system messages (quest completions, experience, loot, etc.)
	if event == 'CHAT_MSG_SYSTEM' then
		return
	end

	-- Skip text emotes (/dance, /meow, etc.) - these are pre-formatted by the server
	-- as complete sentences like "You meow at Player." with no separate sender.
	if event == 'CHAT_MSG_TEXT_EMOTE' then
		return
	end

	-- Skip whisper events when WIM (WoW Instant Messenger) is loaded.
	-- WIM creates its own chat frames that lack our AddMessage hook,
	-- so the |Hsuiseq:| tag would bleed through as visible text.
	if WIM and (event == 'CHAT_MSG_WHISPER' or event == 'CHAT_MSG_WHISPER_INFORM' or event == 'CHAT_MSG_BN_WHISPER' or event == 'CHAT_MSG_BN_WHISPER_INFORM') then
		return
	end

	-- Resolve sender class and level from GUID and available sources
	local senderClass
	-- Guard: playerName can be a secret string in PvP - never use as table key
	if SUI.BlizzAPI.issecretvalue(playerName) then
		return
	end
	local charStr = Ambiguate(playerName or '', getAmbiguateContext())
	local lineID = select(2, ...)
	local senderGUID = select(3, ...)
	local bnSenderID = select(4, ...)
	if senderGUID and type(senderGUID) == 'string' and senderGUID:match('^Player%-') then
		local _, className = GetPlayerInfoByGUID(senderGUID)
		if className then
			senderClass = className
			if charStr ~= '' then
				module.nameColor[charStr] = module:GetColor(className)
			end
		end
	end

	module.prefixSeq = (module.prefixSeq or 0) + 1
	local seq = module.prefixSeq

	local data = {
		timestamp = time(),
		event = event,
		channelIndex = channelIndex,
		channelBaseName = channelBaseName,
		senderName = playerName,
		senderClass = senderClass,
		bnSenderID = bnSenderID,
		lineID = lineID,
	}
	module.lineData[seq] = data
	pruneLineData()

	local metaPrefix = buildPrefix(data)
	if metaPrefix == '' then
		return
	end

	-- Embed sequence tag in the message text so the AddMessage hook can
	-- correlate the prefix with the correct message across all chat frames.
	local tag = '|Hsuiseq:' .. seq .. '|h|h'
	return false, tag .. msg, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, ...
end

-- Tooltip mouseover
local showingTooltip = false
-- Link types that open windows instead of showing tooltips; skip hover for these.
local hoverBlacklist = {
	trade = true,
	garrtrade = true,
	clubTicket = true,
	worldmap = true,
}

function module:OnHyperlinkEnter(f, link)
	local t = strmatch(link, '^(.-):')
	if linkTypes[t] and not hoverBlacklist[t] then
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

-- URL filter function
local filterFunc = function(a, b, msg, ...)
	if not module.CurrentSettings.webLinks or SUI.BlizzAPI.issecretvalue(msg) then
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
	newMsg, found = gsub(msg, '^%x+[%.:]%x+[%.:]%x+[%.:]%x+[^ "£%^`¬{}%[%]\\|<>]*', '|cffffffff|Hbcmurl~%1|h[%1]|h|r')
	if found > 0 then
		return false, newMsg, ...
	end
	newMsg, found = gsub(msg, ' %x+[%.:]%x+[%.:]%x+[%.:]%x+[^ "£%^`¬{}%[%]\\|<>]*', '|cffffffff|Hbcmurl~%1|h[%1]|h|r')
	if found > 0 then
		return false, newMsg, ...
	end
end

-- ItemRefTooltip hook for URL clicking
local SetHyperlink = ItemRefTooltip.SetHyperlink
function ItemRefTooltip:SetHyperlink(data, ...)
	local isURL, link = strsplit('~', data)
	if isURL and isURL == 'bcmurl' then
		module:SetPopupText(link)
	else
		SetHyperlink(self, data, ...)
	end
end

local allChatEvents = {
	'CHAT_MSG_SAY',
	'CHAT_MSG_YELL',
	'CHAT_MSG_GUILD',
	'CHAT_MSG_OFFICER',
	'CHAT_MSG_PARTY',
	'CHAT_MSG_PARTY_LEADER',
	'CHAT_MSG_RAID',
	'CHAT_MSG_RAID_LEADER',
	'CHAT_MSG_INSTANCE_CHAT',
	'CHAT_MSG_INSTANCE_CHAT_LEADER',
	'CHAT_MSG_WHISPER',
	'CHAT_MSG_WHISPER_INFORM',
	'CHAT_MSG_BN_WHISPER',
	'CHAT_MSG_BN_WHISPER_INFORM',
	'CHAT_MSG_BN_CONVERSATION',
	'CHAT_MSG_BN_INLINE_TOAST_BROADCAST',
	'CHAT_MSG_CHANNEL',
	'CHAT_MSG_COMMUNITIES_CHANNEL',
	'CHAT_MSG_EMOTE',
	'CHAT_MSG_TEXT_EMOTE',
}

-- Convert a CHAT_*_GET GlobalString like "%s says: " into a Lua gsub pattern.
-- %s becomes (.-) to capture the player hyperlink; special regex chars are escaped.
local function chatGetPattern(globalStr)
	if not globalStr then
		return nil
	end
	return '^' .. globalStr
		:gsub('([%^%$%(%)%%%.%[%]%*%+%-%?])', '%%%1')
		:gsub('%%%%s', '(.-)') -- escaped %s -> (.-)
		:gsub('%%s', '(.-)')
end

-- Built lazily on first use so GlobalStrings are fully loaded.
local verbPatterns
local function getVerbPatterns()
	if verbPatterns then
		return verbPatterns
	end
	verbPatterns = {}
	local function add(gs)
		local p = chatGetPattern(gs)
		if p then
			verbPatterns[#verbPatterns + 1] = p
		end
	end
	-- Each pattern captures the player hyperlink as %1; replacement keeps just "Name: "
	add(CHAT_SAY_GET)
	add(CHAT_YELL_GET)
	add(CHAT_WHISPER_GET)
	add(CHAT_WHISPER_INFORM_GET)
	add(CHAT_PARTY_GET)
	add(CHAT_PARTY_LEADER_GET)
	add(CHAT_RAID_GET)
	add(CHAT_RAID_LEADER_GET)
	add(CHAT_RAID_WARNING_GET)
	add(CHAT_GUILD_GET)
	add(CHAT_OFFICER_GET)
	add(CHAT_INSTANCE_CHAT_GET)
	add(CHAT_INSTANCE_CHAT_LEADER_GET)
	add(CHAT_BN_WHISPER_GET)
	add(CHAT_BN_WHISPER_INFORM_GET)
	return verbPatterns
end

-- Strip the verb phrase from a fully-composed chat line.
-- e.g. "|Hplayer:Libidos|h[Libidos]|h says: hello" -> "|Hplayer:Libidos|h[Libidos]|h: hello"
local function stripVerb(text)
	for _, pattern in ipairs(getVerbPatterns()) do
		local result, n = text:gsub(pattern, '%1: ')
		if n > 0 then
			return result
		end
	end
	return text
end

-- Strip everything up to and including the last player/BNplayer hyperlink + colon in a composed line,
-- leaving just the message body. Used when %CHARACTER% is already in the prefix.
-- Handles both simple lines (starts with player link) and channel lines where Blizzard
-- prepends a channel tag before the player link: "ChannelTag |Hplayer:...|h[Name]|h: msg"
local playerLinkPattern = '|Hplayer:[^|]+|h%[[^%]]*%]|h:?%s*'
-- BNet links may contain |K...|k protected text in the link data and display text,
-- so we can't use [^|]+ (which stops at pipe chars). Use non-greedy .- instead.
local bnPlayerLinkPattern = '|HBNplayer:.-|h%[.-%]|h:?%s*'
local function stripSenderPrefix(text)
	-- Find the last player or BNplayer link in the line and strip everything up to end of it
	local lastEnd = 0
	for _, pat in ipairs({ playerLinkPattern, bnPlayerLinkPattern }) do
		local s, e = text:find(pat)
		while s do
			if e > lastEnd then
				lastEnd = e
			end
			s, e = text:find(pat, e + 1)
		end
	end
	if lastEnd > 0 then
		return text:sub(lastEnd + 1)
	end
	return text
end

----------------------------------------------------------------------------------------------------
-- Duplicate /played suppression
----------------------------------------------------------------------------------------------------

local lastPlayedTime = 0
local PLAYED_SUPPRESS_WINDOW = 3

local playedTotalPattern
local playedLevelPattern
local function getPlayedPatterns()
	if not playedTotalPattern then
		local function toPattern(gs)
			return '^' .. gs:gsub('%%s', '.+') .. '$'
		end
		playedTotalPattern = toPattern(TIME_PLAYED_TOTAL)
		playedLevelPattern = toPattern(TIME_PLAYED_LEVEL)
	end
	return playedTotalPattern, playedLevelPattern
end

local function playedFilter(chatFrame, event, msg, ...)
	if not msg or SUI.BlizzAPI.issecretvalue(msg) then
		return
	end
	local totalPat, levelPat = getPlayedPatterns()
	if msg:find(totalPat) or msg:find(levelPat) then
		local now = GetTime()
		if (now - lastPlayedTime) < PLAYED_SUPPRESS_WINDOW then
			return true
		end
		lastPlayedTime = now
	end
end

function module:SetupMessageMods()
	if SUI:IsModuleDisabled(module) then
		return
	end

	for i = 1, 10 do
		local ChatFrameName = ('%s%d'):format('ChatFrame', i)
		local ChatFrame = _G[ChatFrameName]

		if ChatFrame then
			module:HookScript(ChatFrame, 'OnHyperlinkEnter', 'OnHyperlinkEnter')
			module:HookScript(ChatFrame, 'OnHyperlinkLeave', 'OnHyperlinkLeave')

			-- Post-hook AddMessage to find the sequence tag embedded by messageFormatFilter,
			-- look up the prefix data, and replace Blizzard's formatting with SUI's.
			-- Uses hooksecurefunc (post-hook) + TransformMessages to avoid tainting
			-- Blizzard's secure AddMessage execution chain (which causes "attempted to
			-- iterate a forbidden table" errors with WoW 12.0 secret values).
			if not ChatFrame._suiAddMessageHooked then
				ChatFrame._suiAddMessageHooked = true
				hooksecurefunc(ChatFrame, 'AddMessage', function(frame, text, ...)
					if not text or not SUI.BlizzAPI.canaccessvalue(text) then
						return
					end
					if not text:match(SUI_SEQ_PATTERN) then
						return
					end

					local ok, err = pcall(function()
						frame:TransformMessages(function(message)
							if not message or not SUI.BlizzAPI.canaccessvalue(message) then
								return false
							end
							return message:match(SUI_SEQ_PATTERN) ~= nil
						end, function(message, r, g, b, ...)
							local seqStr = message:match(SUI_SEQ_PATTERN)
							if not seqStr then
								return message, r, g, b, ...
							end
							local seq = tonumber(seqStr)
							local data = seq and module.lineData[seq]
							message = message:gsub('|Hsuiseq:%d+|h|h', '', 1)

							if data then
								local metaPrefix, playerLink, charPlaceholder = buildPrefix(data)
								local wrapped = wrapPrefix(metaPrefix, seq, playerLink, charPlaceholder)
								message = stripVerb(message)
								message = stripSenderPrefix(message)
								message = wrapped .. message

								local ccDB = module.CurrentSettings.channelColors
								if ccDB and ccDB.enabled and data.event and ccDB.colors[data.event] then
									local cc = ccDB.colors[data.event]
									r, g, b = cc.r, cc.g, cc.b
									if ccDB.colorEntireMessage then
										local hex = ('%02x%02x%02x'):format(cc.r * 255, cc.g * 255, cc.b * 255)
										message = '|cff' .. hex .. message .. '|r'
									end
								end
							end

							return message, r, g, b, ...
						end)
					end)
					if not ok and module.logger then
						module.logger.error('AddMessage post-hook error: ' .. tostring(err))
					end
				end)
			end
		end
	end

	-- Register message format filter on all chat event types
	for _, event in ipairs(allChatEvents) do
		ChatFrame_AddMessageEventFilter(event, messageFormatFilter)
	end

	-- Register URL filters
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

	-- Suppress duplicate /played output (addons like Libs-TimePlayed trigger extra RequestTimePlayed calls)
	ChatFrame_AddMessageEventFilter('CHAT_MSG_SYSTEM', playedFilter)
end
