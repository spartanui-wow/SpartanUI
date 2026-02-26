---@class SUI
local SUI = SUI
---@class SUI.Module.Chatbox
local module = SUI:GetModule('Chatbox')

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
	if module.ChatLevelLog and module.ChatLevelLog[name] and module.DB.playerlevel then
		local color = GetHexColor(GetQuestDifficultyColor(module.ChatLevelLog[name]))
		nameToChange = '|cff' .. color .. module.ChatLevelLog[name] .. '|r:' .. nameToChange
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
		'[I]',
		'[IL]',
		'[G]',
		'[P]',
		'[PL]',
		'[PL]',
		'[O]',
		'[R]',
		'[RL]',
		'[RW]',
		'[%1]',
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
		'%[(%d%d?)%. ([^%]]+)%]',
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
		if text:find('has left the battle') and not module.battleOver then
			module.LeaveCount = module.LeaveCount + 1
		end
		if text:find('The Alliance Wins!') or text:find('The Horde Wins!') then
			SUI:Print('Leavers: ' .. module.LeaveCount)
			if module.LeaveCount > 15 and module.DB.autoLeaverOutput then
				C_ChatInfo.SendChatMessage('SpartanUI: BG Leavers counter: ' .. module.LeaveCount, 'INSTANCE_CHAT')
			end
			module.battleOver = true
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

-- URL filter function
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

function module:SetupMessageMods()
	if SUI:IsModuleDisabled(module) then
		return
	end

	for i = 1, 10 do
		local ChatFrameName = ('%s%d'):format('ChatFrame', i)
		local ChatFrame = _G[ChatFrameName]

		hooksecurefunc(ChatFrame.historyBuffer, 'PushFront', ModifyMessage)
		module:HookScript(ChatFrame, 'OnHyperlinkEnter', 'OnHyperlinkEnter')
		module:HookScript(ChatFrame, 'OnHyperlinkLeave', 'OnHyperlinkLeave')
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
end
