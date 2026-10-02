local _, ns = ...
local M = ns.Messenger
local U = M.Util

-- Rooms are group chats (guild, party, channels). Every chat type the player turns on gets a
-- list entry as soon as it applies (party only while in a party, a channel only while joined),
-- so they can open it and talk before anyone else has. New rooms are filled with what is
-- already known: the guild's server-side history on clients that have it, and the lines still
-- held by the normal chat windows.

---@class Messenger.Rooms
local Rm = {}
M.Rooms = Rm

local Store = M.Store

local DUPLICATE_WINDOW = 30
local HISTORY_COUNT = 100

---@return boolean
local function CanReadOfficer()
	local checks = {
		C_GuildInfo and C_GuildInfo.IsGuildOfficer,
		C_GuildInfo and C_GuildInfo.CanViewOfficerNote,
		CanViewOfficerNote,
		CanEditOfficerNote,
	}
	-- Numeric loop: missing functions leave holes that ipairs would stop at
	for i = 1, 4 do
		local check = checks[i]
		if check then
			local ok, result = pcall(check)
			if ok and result == true then
				return true
			end
		end
	end
	return false
end

---True when the player can currently take part in this room.
---@param kindKey string
---@param channel? string
---@return boolean
function Rm:IsAvailable(kindKey, channel)
	if kindKey == 'GUILD' then
		return IsInGuild() and true or false
	elseif kindKey == 'OFFICER' then
		return IsInGuild() and CanReadOfficer()
	elseif kindKey == 'PARTY' then
		return IsInGroup(LE_PARTY_CATEGORY_HOME) and true or false
	elseif kindKey == 'RAID' then
		return IsInRaid(LE_PARTY_CATEGORY_HOME) and true or false
	elseif kindKey == 'INSTANCE' then
		return IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and true or false
	elseif kindKey == 'CHANNEL' then
		local id = channel and GetChannelName(channel)
		return id ~= nil and id > 0
	end
	return true
end

---Whether a room belongs in the list right now: turned on and available.
---@param convo MessengerConversation
---@return boolean
function Rm:IsShown(convo)
	local channel = convo.kind == 'CHANNEL' and convo.target or nil
	return M:IsCaptured(convo.kind, channel) and self:IsAvailable(convo.kind, channel)
end

----------------------------------------------------------------------------------------------------
-- History
----------------------------------------------------------------------------------------------------

---True when the conversation already has this line (history can overlap live messages).
---@param convo MessengerConversation
---@param sender string|nil
---@param text string
---@param stamp number
---@return boolean
local function HasLine(convo, sender, text, stamp)
	for i = #convo.msgs, 1, -1 do
		local msg = convo.msgs[i]
		if msg.x == text and msg.s == sender and math.abs((msg.t or 0) - stamp) <= DUPLICATE_WINDOW then
			return true
		end
	end
	return false
end

---@param key string
---@param text string
---@param sender string|nil
---@param classFile string|nil
---@param stamp number
---@param outgoing boolean
---@param emote boolean
local function Import(key, text, sender, classFile, stamp, outgoing, emote)
	local convo = Store:Get(key)
	if not convo or HasLine(convo, sender, text, stamp) then
		return
	end
	Store:Add(key, {
		t = stamp,
		x = text,
		s = sender,
		cl = classFile,
		o = outgoing or nil,
		em = emote or nil,
		a = outgoing and UnitName('player') or nil,
	}, true)
end

---Copies the lines the normal chat windows still hold for this room. Each line keeps the event
---that produced it and its arrival time, so no text has to be parsed.
---@param kindKey string
---@param key string
---@param channel? string
local function ImportChatWindows(kindKey, key, channel)
	local now, uptime = time(), GetTime()
	local me = U.PlayerFullName()
	local seen = {}
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local frame = _G['ChatFrame' .. i]
		if frame and frame.ForEachMessage then
			pcall(frame.ForEachMessage, frame, function(entry)
				local extra = entry.extraData
				local event = extra and extra[4]
				local args = extra and extra[5]
				local kind = type(event) == 'string' and M.KindByEvent[event]
				if kind and kind.key == kindKey and type(args) == 'table' and type(entry.timestamp) == 'number' then
					local text, sender = U.Str(args[1]), U.Str(args[2])
					local lineID = U.Num(args[11])
					local matches = kindKey ~= 'CHANNEL' or U.ChannelName(args[8], args[9]) == channel
					if matches and text and sender and not (lineID and seen[lineID]) then
						if lineID then
							seen[lineID] = true
						end
						local full = U.FullName(sender)
						local stamp = math.floor(now - (uptime - entry.timestamp))
						Import(key, text, full, U.ClassFromGUID(args[12]), stamp, U.SameName(full, me), kindKey == 'EMOTE')
					end
				end
			end)
		end
	end
end

local pendingClub = {}

---@param classID any
---@return string|nil
local function ClassFileFromID(classID)
	classID = U.Num(classID)
	if not classID or not (C_CreatureInfo and C_CreatureInfo.GetClassInfo) then
		return nil
	end
	local info = C_CreatureInfo.GetClassInfo(classID)
	return info and U.Str(info.classFile)
end

---@param clubId any
---@param streamId any
---@param key string
local function ReadClubHistory(clubId, streamId, key)
	local ranges = C_Club.GetMessageRanges(clubId, streamId)
	local range = ranges and ranges[#ranges]
	if not range then
		return false
	end
	local messages = C_Club.GetMessagesBefore(clubId, streamId, range.newestMessageId, HISTORY_COUNT)
	for _, info in ipairs(messages or {}) do
		local text = not info.destroyed and U.Str(info.content)
		local author = info.author
		local name = author and U.Str(author.name)
		local epoch = info.messageId and U.Num(info.messageId.epoch)
		if text and name and epoch and not name:find('|K', 1, true) then
			Import(key, text, U.FullName(name), ClassFileFromID(author.classID), math.floor(epoch / 1000000), author.isSelf == true, false)
		end
	end
	return true
end

---Guild and officer chat keep server-side history on clients with communities.
---@param kindKey string
---@param key string
local function ImportGuildHistory(kindKey, key)
	if not (C_Club and C_Club.GetGuildClubId and C_Club.GetStreams and C_Club.GetMessagesBefore and Enum and Enum.ClubStreamType) then
		return
	end
	local wanted = kindKey == 'GUILD' and Enum.ClubStreamType.Guild or Enum.ClubStreamType.Officer
	local ok = pcall(function()
		local clubId = C_Club.GetGuildClubId()
		if not clubId then
			return
		end
		for _, stream in ipairs(C_Club.GetStreams(clubId) or {}) do
			if stream.streamType == wanted then
				if not ReadClubHistory(clubId, stream.streamId, key) then
					-- Nothing downloaded yet: ask for it and finish when it arrives
					pendingClub[tostring(clubId) .. ':' .. tostring(stream.streamId)] = key
					C_Club.RequestMoreMessagesBefore(clubId, stream.streamId, nil, HISTORY_COUNT)
				end
			end
		end
	end)
	if not ok then
		M.log.debug('Guild history is not available yet')
	end
end

local function OnClubHistory(_, clubId, streamId)
	local id = tostring(clubId) .. ':' .. tostring(streamId)
	local key = pendingClub[id]
	if key and not U.IsRestricted() then
		pendingClub[id] = nil
		pcall(ReadClubHistory, clubId, streamId, key)
	end
end

---Fills a newly created room with the history that is already available.
---@param kindKey string
---@param key string
---@param channel? string
function Rm:Backfill(kindKey, key, channel)
	if U.IsRestricted() then
		return
	end
	if kindKey == 'GUILD' or kindKey == 'OFFICER' then
		ImportGuildHistory(kindKey, key)
	end
	ImportChatWindows(kindKey, key, channel)
end

----------------------------------------------------------------------------------------------------
-- Keeping the list in step with the player's groups, guild and channels
----------------------------------------------------------------------------------------------------

---@param kind MessengerKind
---@param channel? string
---@param reopen boolean
local function EnsureRoom(kind, channel, reopen)
	local key = Rm.KeyFor(kind.key, channel)
	local existing = Store:Get(key)
	local fields = { kind = kind.key, target = channel }
	if not existing then
		fields.name = channel or kind.label
	end
	if reopen and existing and existing.closed then
		fields.closed = false
	end
	local _, created = Store:Ensure(key, fields)
	if created or (existing and #existing.msgs == 0) then
		Rm:Backfill(kind.key, key, channel)
	end
end

---@param kindKey string
---@param channel? string
---@return string
function Rm.KeyFor(kindKey, channel)
	return kindKey == 'CHANNEL' and ('ch:' .. channel) or ('r:' .. kindKey)
end

---Base names of the channels the player is in, in channel number order.
---@return {name: string, id: number}[]
local function JoinedChannels()
	local out = {}
	local data = { GetChannelList() }
	for i = 1, #data, 3 do
		local id, name = data[i], data[i + 1]
		if type(name) == 'string' and not name:find('^Community:') then
			out[#out + 1] = { name = name, id = id }
		end
	end
	return out
end

local NEARBY = { SAY = true, YELL = true, EMOTE = true }

---Channels the player could open right now, for starting a conversation from the search box. With no search
---text, only group chats and joined channels are offered (Say and Yell are always there and would
---crowd out the rest).
---@param prefix string lower case, may be empty
---@return {name: string, detail: string, kind: string, channel?: string, room: boolean}[]
function Rm:Choices(prefix)
	local out = {}
	local function add(kindKey, name, channel)
		local lower = strlower(name)
		local matches
		if prefix == '' then
			matches = not NEARBY[kindKey]
		else
			matches = lower:find(prefix, 1, true) == 1
			if not matches and channel then
				local id = GetChannelName(channel)
				matches = id and id > 0 and tostring(id) == prefix
			end
		end
		if matches then
			out[#out + 1] = {
				name = name,
				detail = M.Contacts:Describe({ kind = kindKey, target = channel }),
				kind = kindKey,
				channel = channel,
				room = true,
			}
		end
	end
	for _, kind in ipairs(M.Kinds) do
		if kind.group == 'rooms' and kind.key ~= 'CHANNEL' and self:IsAvailable(kind.key) then
			add(kind.key, kind.label)
		end
	end
	for _, channel in ipairs(JoinedChannels()) do
		add('CHANNEL', channel.name, channel.name)
	end
	return out
end

---Finds an open-able channel by its exact name ("guild", "Trade").
---@param text string
---@return string|nil kindKey, string|nil channel
function Rm:Find(text)
	local lower = strlower(text)
	for _, kind in ipairs(M.Kinds) do
		if kind.group == 'rooms' and kind.key ~= 'CHANNEL' and strlower(kind.label) == lower and self:IsAvailable(kind.key) then
			return kind.key
		end
	end
	for _, channel in ipairs(JoinedChannels()) do
		if strlower(channel.name) == lower then
			return 'CHANNEL', channel.name
		end
	end
	return nil
end

local pendingJoin

---Joins a chat channel the player is not in yet and opens it once the game confirms.
---@param name string
---@return boolean started
function Rm:Join(name)
	name = U.Trim(name or '')
	if name == '' or name:find('[%s#]') or U.IsRestricted() then
		return false
	end
	local frameID = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.GetID and DEFAULT_CHAT_FRAME:GetID() or nil
	local ok, zoneChannel, joined = pcall(JoinPermanentChannel, name, nil, frameID, 1)
	if not ok or not zoneChannel then
		return false
	end
	name = U.Str(joined) or name
	M.settings.channels[name].capture = true
	M.Router:RefreshEvents()
	M:Fire('SETTINGS_CHANGED')
	pendingJoin = { name = strlower(name), expires = GetTime() + 10 }
	self:Sync(false)
	return true
end

---Creates list entries for every room that is turned on and available.
---@param reopen? boolean Also bring back rooms the player closed (used when a chat is turned on)
function Rm:Sync(reopen)
	if not M.enabled then
		return
	end
	for _, kind in ipairs(M.Kinds) do
		if kind.group == 'rooms' and kind.key ~= 'CHANNEL' and M:IsCaptured(kind.key) and self:IsAvailable(kind.key) then
			EnsureRoom(kind, nil, reopen == true)
		end
	end
	local openKey
	for _, channel in ipairs(JoinedChannels()) do
		if M:IsCaptured('CHANNEL', channel.name) then
			EnsureRoom(M.KindByKey.CHANNEL, channel.name, reopen == true)
			if pendingJoin and pendingJoin.name == strlower(channel.name) then
				openKey = Rm.KeyFor('CHANNEL', channel.name)
			end
		end
	end
	if pendingJoin and (openKey or GetTime() > pendingJoin.expires) then
		pendingJoin = nil
	end
	M:Fire('LIST_CHANGED')
	M:Fire('UNREAD_CHANGED')
	if openKey then
		M:Open(openKey, true)
	end
end

local EVENTS = { 'GROUP_ROSTER_UPDATE', 'PLAYER_GUILD_UPDATE', 'CHANNEL_UI_UPDATE', 'CHAT_MSG_CHANNEL_NOTICE', 'PLAYER_ENTERING_WORLD', 'CLUB_STREAMS_LOADED' }

local function QueueSync()
	M:Defer('rooms-sync', function()
		Rm:Sync(false)
	end)
end

function Rm:Enable()
	for _, event in ipairs(EVENTS) do
		M:RegisterEvent(event, 'Rooms', QueueSync)
	end
	M:RegisterEvent('CLUB_MESSAGE_HISTORY_RECEIVED', 'Rooms', OnClubHistory)
	self:Sync(false)
end

function Rm:Disable()
	for _, event in ipairs(EVENTS) do
		M:UnregisterEvent(event, 'Rooms')
	end
	M:UnregisterEvent('CLUB_MESSAGE_HISTORY_RECEIVED', 'Rooms')
end
