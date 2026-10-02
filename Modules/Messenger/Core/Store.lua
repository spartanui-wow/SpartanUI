local _, ns = ...
local M = ns.Messenger
local U = M.Util

-- Conversations with people are account-wide so an alt can pick up where a main left off.
-- Rooms (guild, party, channels) belong to the character that was in them.
--
-- Keys:
--   c:name-realm      character whisper (always lower case, always with realm)
--   b:battletag       Battle.net whisper
--   r:GUILD, r:PARTY  rooms, one per kind
--   ch:Trade          numbered channel, by base name
--
-- Message fields (short names keep SavedVariables small):
--   t time, x text, o outgoing, s sender (rooms), cl sender class, sys system line,
--   em emote, gm Game Master, a alt that sent it (outgoing whispers)

---@class MessengerConversation
---@field key string
---@field kind string
---@field name string Display name
---@field target string Whisper target, BattleTag or channel base name
---@field class? string
---@field msgs table[]
---@field unread number
---@field last number
---@field pinned? boolean
---@field alert? 'mentions'|'none' Alert level; nil means every message
---@field mentionUnread? number Unread lines that say the player's name
---@field closed? boolean

---@class Messenger.Store
local S = {}
M.Store = S

local function People()
	return M.db.global.people
end

local function Rooms()
	return M.db.char.rooms
end

---@param key string
---@return boolean
function S.IsRoomKey(key)
	local prefix = key:sub(1, 2)
	return prefix ~= 'c:' and prefix ~= 'b:'
end

---@param full string Name-Realm
---@return string
function S.CharKey(full)
	return 'c:' .. strlower(full)
end

---@param battleTag string
---@return string
function S.BNetKey(battleTag)
	return 'b:' .. strlower(battleTag)
end

---@param key string
---@return MessengerConversation|nil
function S:Get(key)
	return People()[key] or Rooms()[key]
end

---Returns the conversation, creating it when needed. Non-nil fields overwrite stored ones.
---@param key string
---@param fields table
---@return MessengerConversation convo, boolean created
function S:Ensure(key, fields)
	local convo = self:Get(key)
	local created = false
	if not convo then
		convo = { key = key, msgs = {}, unread = 0, last = time() }
		if S.IsRoomKey(key) then
			Rooms()[key] = convo
		else
			People()[key] = convo
		end
		created = true
	end
	for k, v in pairs(fields) do
		if v ~= nil then
			convo[k] = v
		end
	end
	if created then
		M:Fire('LIST_CHANGED')
	end
	return convo, created
end

---@param convo MessengerConversation
local function Trim(convo)
	local max = M.settings.history.maxMessages
	if S.IsRoomKey(convo.key) then
		max = math.min(max, 300)
	end
	local count = #convo.msgs
	if count <= max + 25 then
		return
	end
	local keep = {}
	for i = count - max + 1, count do
		keep[#keep + 1] = convo.msgs[i]
	end
	convo.msgs = keep
end

---Whether a conversation belongs in the list: not closed, and for rooms turned on and available.
---@param convo MessengerConversation
---@return boolean
function S:IsVisible(convo)
	if convo.closed then
		return false
	end
	if S.IsRoomKey(convo.key) and M.Rooms then
		return M.Rooms:IsShown(convo)
	end
	return true
end

---Appends a message and updates unread state.
---@param key string
---@param msg table
---@param quiet? boolean Imported history: never counts as unread
function S:Add(key, msg, quiet)
	local convo = self:Get(key)
	if not convo then
		return
	end
	msg.t = msg.t or time()
	-- Lines recovered after a fight arrive late; keep the log in time order
	local msgs = convo.msgs
	local index = #msgs + 1
	while index > 1 and (msgs[index - 1].t or 0) > msg.t do
		index = index - 1
	end
	table.insert(msgs, index, msg)
	Trim(convo)
	convo.last = math.max(convo.last or 0, msg.t)
	if not quiet then
		convo.closed = nil
	end
	if msg.o and not quiet then
		convo.unread = 0
		convo.mentionUnread = nil
	elseif not quiet and not msg.o and not msg.sys and not M:IsViewing(key) then
		convo.unread = (convo.unread or 0) + 1
		if msg.mn then
			convo.mentionUnread = (convo.mentionUnread or 0) + 1
		end
	end
	M:Fire('MESSAGE', key, msg)
	M:Fire('LIST_CHANGED')
	M:Fire('UNREAD_CHANGED')
end

---@param key string
function S:MarkRead(key)
	local convo = self:Get(key)
	if not convo then
		return
	end
	convo.mentionUnread = nil
	if convo.unread and convo.unread > 0 then
		convo.unread = 0
		M:Fire('LIST_CHANGED')
		M:Fire('UNREAD_CHANGED')
	end
	M:Fire('READ', key)
end

---@param key string
---@param flag 'pinned'|'closed'
---@param value boolean|nil
function S:SetFlag(key, flag, value)
	local convo = self:Get(key)
	if not convo then
		return
	end
	convo[flag] = value or nil
	if flag == 'closed' and value then
		convo.unread = 0
		convo.mentionUnread = nil
	end
	M:Fire('CONVO_CHANGED', key)
	M:Fire('LIST_CHANGED')
	M:Fire('UNREAD_CHANGED')
end

---@param key string
-- The last delete or clear, kept for this session so it can be undone
local lastRemoved

function S:Clear(key)
	local convo = self:Get(key)
	if not convo then
		return
	end
	lastRemoved = { key = key, msgs = convo.msgs, unread = convo.unread }
	convo.msgs = {}
	convo.unread = 0
	M:Fire('CONVO_CHANGED', key)
	M:Fire('LIST_CHANGED')
	M:Fire('UNREAD_CHANGED')
end

---@param key string
function S:Delete(key)
	local convo = self:Get(key)
	if convo then
		lastRemoved = { key = key, convo = convo }
	end
	People()[key] = nil
	Rooms()[key] = nil
	M:Fire('CONVO_DELETED', key)
	M:Fire('LIST_CHANGED')
	M:Fire('UNREAD_CHANGED')
end

---Brings back the last deleted conversation or cleared messages.
---@return string|nil key
function S:Undo()
	local removed = lastRemoved
	if not removed then
		return nil
	end
	lastRemoved = nil
	if removed.convo then
		-- The person may have written again during the undo window: keep those lines too
		local current = self:Get(removed.key)
		if current then
			for _, msg in ipairs(current.msgs) do
				table.insert(removed.convo.msgs, msg)
			end
			removed.convo.unread = (removed.convo.unread or 0) + (current.unread or 0)
			removed.convo.last = math.max(removed.convo.last or 0, current.last or 0)
		end
		if S.IsRoomKey(removed.key) then
			Rooms()[removed.key] = removed.convo
		else
			People()[removed.key] = removed.convo
		end
	else
		local convo = self:Get(removed.key)
		if not convo then
			return nil
		end
		-- Anything that arrived after the clear stays, after the restored lines
		for _, msg in ipairs(convo.msgs) do
			table.insert(removed.msgs, msg)
		end
		convo.msgs = removed.msgs
		convo.unread = (removed.unread or 0) + (convo.unread or 0)
	end
	M:Fire('CONVO_CHANGED', removed.key)
	M:Fire('LIST_CHANGED')
	M:Fire('UNREAD_CHANGED')
	return removed.key
end

function S:DeleteAll()
	lastRemoved = nil
	wipe(People())
	wipe(Rooms())
	M:Fire('CONVO_DELETED', nil)
	M:Fire('LIST_CHANGED')
	M:Fire('UNREAD_CHANGED')
end

---@return number
function S:TotalUnread()
	local total = 0
	for _, tbl in ipairs({ People(), Rooms() }) do
		for _, convo in pairs(tbl) do
			local level = M:AlertLevel(convo)
			if level ~= 'none' and self:IsVisible(convo) then
				total = total + ((level == 'mentions' and convo.mentionUnread or convo.unread) or 0)
			end
		end
	end
	return total
end

---@param convo MessengerConversation
---@param query string lower case
---@return boolean
local function Matches(convo, query)
	if strlower(convo.name or ''):find(query, 1, true) or strlower(M:GetAlias(convo.key) or ''):find(query, 1, true) then
		return true
	end
	local msgs = convo.msgs
	for i = #msgs, math.max(1, #msgs - 200), -1 do
		local text = msgs[i].x
		if text and strlower(U.Plain(text)):find(query, 1, true) then
			return true
		end
	end
	return false
end

---Visible conversations, pinned first, then most recent.
---@param filter 'all'|'unread'|'people'|'rooms'
---@param query? string
---@return MessengerConversation[]
function S:List(filter, query)
	local list = {}
	query = query and query ~= '' and strlower(query) or nil
	for _, tbl in ipairs({ People(), Rooms() }) do
		for _, convo in pairs(tbl) do
			local show = self:IsVisible(convo)
			if show and filter == 'unread' then
				show = (convo.unread or 0) > 0
			elseif show and filter == 'people' then
				show = not S.IsRoomKey(convo.key)
			elseif show and filter == 'rooms' then
				show = S.IsRoomKey(convo.key)
			end
			if show and query then
				show = Matches(convo, query)
			end
			if show then
				list[#list + 1] = convo
			end
		end
	end
	table.sort(list, function(a, b)
		if (a.pinned and true or false) ~= (b.pinned and true or false) then
			return a.pinned and true or false
		end
		if (a.last or 0) ~= (b.last or 0) then
			return (a.last or 0) > (b.last or 0)
		end
		return a.key < b.key
	end)
	return list
end

---Most recent conversation with unread messages, or nil.
---@return MessengerConversation|nil
function S:NextUnread()
	for _, convo in ipairs(self:List('unread')) do
		if M:AlertLevel(convo) ~= 'none' then
			return convo
		end
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- One-time repair: first-and-last names saved before Messenger understood them
----------------------------------------------------------------------------------------------------

---Older versions removed the space from "First Last" names and added a realm, so they were saved
---as "FirstLast-Realm". A name with a dash and no space cannot be a real name on these clients.
---The surname starts at the last capital letter that follows a small one.
---@param name any
---@return any
local function Unsquash(name)
	if type(name) ~= 'string' or name:find(' ', 1, true) or not name:find('-', 1, true) then
		return name
	end
	local base = name:match('^([^%-]+)%-') or name
	local first, last = base:match('^(.*%l)(%u[^%u]*)$')
	if first then
		return first .. ' ' .. last
	end
	return base
end

---@param convo MessengerConversation
local function RepairLines(convo)
	for _, msg in ipairs(convo.msgs) do
		msg.s = Unsquash(msg.s)
	end
end

---Fixes saved names once per account (conversations with people) and per character (channels).
---Only runs on clients with first-and-last names.
function S:RepairSquashedNames()
	if not U.SurnameNames() then
		return
	end
	local global, char = M.db.global, M.db.char
	if not global.surnamesRepaired then
		global.surnamesRepaired = true
		local people = People()
		local moves = {}
		for key, convo in pairs(people) do
			RepairLines(convo)
			if convo.kind == 'WHISPER' then
				local target = Unsquash(convo.target)
				if target ~= convo.target then
					moves[#moves + 1] = { from = key, to = S.CharKey(target), target = target }
				end
			end
		end
		for _, move in ipairs(moves) do
			local convo = people[move.from]
			people[move.from] = nil
			convo.target = move.target
			convo.name = move.target
			local existing = people[move.to]
			if existing then
				-- Both spellings were in use: keep one conversation with every line in time order
				for _, msg in ipairs(convo.msgs) do
					existing.msgs[#existing.msgs + 1] = msg
				end
				table.sort(existing.msgs, function(a, b)
					return (a.t or 0) < (b.t or 0)
				end)
				existing.unread = (existing.unread or 0) + (convo.unread or 0)
				existing.last = math.max(existing.last or 0, convo.last or 0)
			else
				convo.key = move.to
				people[move.to] = convo
			end
			if char.lastKey == move.from then
				char.lastKey = move.to
			end
			if char.popouts[move.from] then
				char.popouts[move.to] = char.popouts[move.to] or char.popouts[move.from]
				char.popouts[move.from] = nil
			end
		end
		if #moves > 0 then
			M.log.info(string.format('Repaired %d saved first-and-last names', #moves))
		end
	end
	if not char.surnamesRepaired then
		char.surnamesRepaired = true
		for _, convo in pairs(Rooms()) do
			RepairLines(convo)
		end
	end
end

---Older versions only had "mute"; it is the "No alerts" level now.
function S:MigrateAlerts()
	for _, tbl in ipairs({ People(), Rooms() }) do
		for _, convo in pairs(tbl) do
			if convo.muted then
				convo.alert = 'none'
				convo.muted = nil
			end
		end
	end
end

---Drops old history according to settings. Runs once at login.
function S:Prune()
	local history = M.settings.history
	local now = time()
	if history.keepDays and history.keepDays > 0 then
		local cutoff = now - history.keepDays * 86400
		for key, convo in pairs(People()) do
			if not convo.pinned and (convo.last or 0) < cutoff then
				People()[key] = nil
			end
		end
	end
	local roomCutoff = now - (history.roomDays or 3) * 86400
	for key, convo in pairs(Rooms()) do
		local keep = {}
		for _, msg in ipairs(convo.msgs) do
			if (msg.t or 0) >= roomCutoff then
				keep[#keep + 1] = msg
			end
		end
		convo.msgs = keep
		if #keep == 0 and not convo.pinned then
			Rooms()[key] = nil
		end
	end
	for _, tbl in ipairs({ People(), Rooms() }) do
		for _, convo in pairs(tbl) do
			if type(convo.msgs) ~= 'table' then
				convo.msgs = {}
			end
			convo.unread = convo.unread or 0
			Trim(convo)
		end
	end
end
