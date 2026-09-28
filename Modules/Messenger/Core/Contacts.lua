local _, ns = ...
local M = ns.Messenger
local U = M.Util
local L = M.L

-- Live details about the people and rooms in the list: presence, level, class, zone.
-- Nothing here is saved; caches are rebuilt from the friend, Battle.net and guild lists.

---@class MessengerPresence
---@field status? 'online'|'away'|'busy'|'offline'
---@field level? number
---@field class? string
---@field zone? string
---@field detail? string Extra text such as the game a Battle.net friend is playing
---@field isFriend? boolean

---@class Messenger.Contacts
local C = {}
M.Contacts = C

local friends = {}
local bnet = {}
local bnetById = {}
local guild = {}
local guildOnline = 0

local function Status(online, afk, dnd)
	if not online then
		return 'offline'
	elseif dnd then
		return 'busy'
	elseif afk then
		return 'away'
	end
	return 'online'
end

local function RefreshFriends()
	wipe(friends)
	if not (C_FriendList and C_FriendList.GetNumFriends) then
		return
	end
	for i = 1, C_FriendList.GetNumFriends() or 0 do
		local info = C_FriendList.GetFriendInfoByIndex(i)
		local full = info and U.FullName(info.name)
		if full then
			friends[strlower(full)] = {
				full = full,
				status = Status(info.connected, info.afk, info.dnd),
				level = U.Num(info.level),
				class = U.ClassFromLocalName(info.className),
				zone = U.Str(info.area),
				isFriend = true,
			}
		end
	end
end

local function RefreshBNet()
	wipe(bnet)
	wipe(bnetById)
	if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then
		return
	end
	for i = 1, BNGetNumFriends() or 0 do
		local info = C_BattleNet.GetFriendAccountInfo(i)
		local tag = info and U.Str(info.battleTag)
		if tag then
			local game = info.gameAccountInfo
			local entry = {
				id = U.Num(info.bnetAccountID),
				tag = tag,
				accountName = U.Str(info.accountName),
				status = Status(game and game.isOnline, info.isAFK or (game and game.isGameAFK), info.isDND or (game and game.isGameBusy)),
				isFriend = true,
			}
			if game and game.isOnline then
				if game.clientProgram == BNET_CLIENT_WOW and U.Str(game.characterName) then
					entry.character = U.Str(game.characterName)
					entry.realm = U.Str(game.realmName)
					entry.class = U.ClassFromLocalName(game.className)
					entry.level = U.Num(game.characterLevel)
					entry.zone = U.Str(game.areaName)
				else
					entry.detail = U.Str(game.richPresence)
				end
			end
			bnet[strlower(tag)] = entry
			if entry.id then
				bnetById[entry.id] = entry
			end
		end
	end
end

local function RefreshGuild()
	wipe(guild)
	guildOnline = 0
	if not IsInGuild() then
		return
	end
	for i = 1, GetNumGuildMembers() or 0 do
		local name, _, _, level, _, zone, _, _, online, status, classFile = GetGuildRosterInfo(i)
		local full = U.FullName(name)
		if full then
			guild[strlower(full)] = {
				full = full,
				status = Status(online, status == 1, status == 2),
				level = U.Num(level),
				class = U.Str(classFile),
				zone = U.Str(zone),
			}
			if online then
				guildOnline = guildOnline + 1
			end
		end
	end
end

local function RefreshAll()
	RefreshFriends()
	RefreshBNet()
	RefreshGuild()
	M:Fire('CONTACTS_CHANGED')
end

local refreshQueued = false
local function QueueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	C_Timer.After(0.3, function()
		refreshQueued = false
		RefreshAll()
	end)
end

local lastGuildRequest = 0

---Ask the server for a fresh guild roster, at most every 15 seconds.
function C:RequestGuild()
	if not IsInGuild() or GetTime() - lastGuildRequest < 15 then
		return
	end
	lastGuildRequest = GetTime()
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	elseif GuildRoster then
		GuildRoster()
	end
end

function C:Enable()
	local events = {
		'FRIENDLIST_UPDATE',
		'BN_FRIEND_INFO_CHANGED',
		'BN_FRIEND_ACCOUNT_ONLINE',
		'BN_FRIEND_ACCOUNT_OFFLINE',
		'BN_FRIEND_LIST_SIZE_CHANGED',
		'BN_CONNECTED',
		'GUILD_ROSTER_UPDATE',
		'GROUP_ROSTER_UPDATE',
		'PLAYER_ENTERING_WORLD',
	}
	for _, event in ipairs(events) do
		M:RegisterEvent(event, 'Contacts', QueueRefresh)
	end
	QueueRefresh()
end

function C:Disable()
	for _, event in ipairs({
		'FRIENDLIST_UPDATE',
		'BN_FRIEND_INFO_CHANGED',
		'BN_FRIEND_ACCOUNT_ONLINE',
		'BN_FRIEND_ACCOUNT_OFFLINE',
		'BN_FRIEND_LIST_SIZE_CHANGED',
		'BN_CONNECTED',
		'GUILD_ROSTER_UPDATE',
		'GROUP_ROSTER_UPDATE',
		'PLAYER_ENTERING_WORLD',
	}) do
		M:UnregisterEvent(event, 'Contacts')
	end
end

---@param bnetAccountID number
---@return table|nil
function C:GetBNetByID(bnetAccountID)
	local entry = bnetById[bnetAccountID]
	if entry then
		return entry
	end
	if C_BattleNet and C_BattleNet.GetAccountInfoByID then
		local ok, info = pcall(C_BattleNet.GetAccountInfoByID, bnetAccountID)
		if ok and info and U.Str(info.battleTag) then
			return { id = bnetAccountID, tag = info.battleTag, accountName = U.Str(info.accountName) }
		end
	end
	return nil
end

---@param battleTag string
---@return table|nil
function C:GetBNetByTag(battleTag)
	return bnet[strlower(battleTag)]
end

---Finds a Battle.net friend by the account name shown in chat (used after a restriction lifts).
---@param accountName string
---@return table|nil
function C:GetBNetByAccountName(accountName)
	for _, entry in pairs(bnet) do
		if entry.accountName == accountName then
			return entry
		end
	end
	return nil
end

---The current session id needed to send to a Battle.net conversation.
---@param convo MessengerConversation
---@return number|nil
function C:GetBNetID(convo)
	local entry = bnet[strlower(convo.target or '')]
	return entry and entry.id or nil
end

---@param full string Name-Realm
---@return boolean
function C:IsFriend(full)
	return friends[strlower(full)] ~= nil
end

---@param full string Name-Realm
---@return boolean
function C:IsGuildMate(full)
	return guild[strlower(full)] ~= nil
end

---Presence details for the conversation header and list.
---@param convo MessengerConversation
---@return MessengerPresence
function C:GetPresence(convo)
	if convo.kind == 'WHISPER' then
		local lower = strlower(convo.target or '')
		local entry = friends[lower] or guild[lower]
		if entry then
			return entry
		end
		return { class = convo.class }
	elseif convo.kind == 'BN_WHISPER' then
		local entry = bnet[strlower(convo.target or '')]
		if entry then
			return entry
		end
		return { status = 'offline' }
	end
	return {}
end

---One line under the name in the chat header.
---@param convo MessengerConversation
---@return string
function C:Describe(convo)
	local kind = convo.kind
	if kind == 'WHISPER' or kind == 'BN_WHISPER' then
		local p = self:GetPresence(convo)
		local parts = {}
		if kind == 'BN_WHISPER' then
			table.insert(parts, L['Battle.net'])
			if p.character then
				table.insert(parts, p.character)
			end
		end
		if p.level and p.level > 0 then
			table.insert(parts, string.format(L['Level %d'], p.level))
		end
		if p.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[p.class] then
			table.insert(parts, LOCALIZED_CLASS_NAMES_MALE[p.class])
		end
		if p.status == 'offline' then
			table.insert(parts, L['Offline'])
		elseif p.status == 'away' then
			table.insert(parts, L['Away'])
		elseif p.status == 'busy' then
			table.insert(parts, L['Busy'])
		end
		if p.zone and p.status ~= 'offline' then
			table.insert(parts, p.zone)
		elseif p.detail then
			table.insert(parts, p.detail)
		end
		if #parts == 0 then
			return L['Not on your friends list']
		end
		return table.concat(parts, '  -  ')
	elseif kind == 'GUILD' or kind == 'OFFICER' then
		local guildName = IsInGuild() and GetGuildInfo('player')
		if guildName then
			return string.format(L['%s  -  %d online'], guildName, guildOnline)
		end
		return L['You are not in a guild']
	elseif kind == 'PARTY' or kind == 'RAID' or kind == 'INSTANCE' then
		local count = GetNumGroupMembers() or 0
		if count == 0 then
			return L['You are not in a group']
		end
		return string.format(L['%d people'], count)
	elseif kind == 'CHANNEL' then
		local id = GetChannelName(convo.target or '')
		if id and id > 0 then
			return string.format(L['Channel %d'], id)
		end
		return L['You are not in this channel']
	end
	return L['Everyone nearby']
end

---Names for the "new conversation" suggestions: friends first, then guild.
---@param prefix string lower case
---@return string[]
function C:Suggest(prefix)
	local out, seen = {}, {}
	local function add(name)
		local lower = strlower(name)
		if not seen[lower] and lower:find(prefix, 1, true) == 1 then
			seen[lower] = true
			out[#out + 1] = name
		end
	end
	for _, entry in pairs(bnet) do
		if entry.status ~= 'offline' then
			add(entry.tag)
		end
	end
	for _, entry in pairs(friends) do
		add(U.DisplayName(entry.full))
	end
	for _, entry in pairs(guild) do
		if entry.status ~= 'offline' then
			add(U.DisplayName(entry.full))
		end
	end
	table.sort(out)
	return out
end
