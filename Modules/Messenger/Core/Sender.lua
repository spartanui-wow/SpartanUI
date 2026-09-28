local _, ns = ...
local M = ns.Messenger
local U = M.Util
local L = M.L

-- Sends composer text to a conversation. Outgoing whispers are not stored here: the server's
-- echo (the _INFORM events) is what the router records, so the log only ever shows messages
-- that were actually delivered.

---@class Messenger.Sender
local Sn = {}
M.Sender = Sn

local Store = M.Store

local SendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
local SendBNet = (C_BattleNet and C_BattleNet.SendWhisper) or BNSendWhisper

local CHUNK = 255
local BNET_CHUNK = 800
local HISTORY_SIZE = 30

local recentTargets = {}
local sentHistory = {}

---Conversation key for a name we whispered in the last 10 seconds (for "not playing" notices).
---@param name string
---@return string|nil
function Sn:RecentTarget(name)
	local entry = recentTargets[strlower(name)]
	if entry and GetTime() - entry.t < 10 then
		return entry.key
	end
	return nil
end

---Lines the player sent to this conversation this session, newest last.
---@param key string
---@return string[]
function Sn:History(key)
	sentHistory[key] = sentHistory[key] or {}
	return sentHistory[key]
end

local function Remember(key, text)
	local list = Sn:History(key)
	if list[#list] ~= text then
		table.insert(list, text)
		if #list > HISTORY_SIZE then
			table.remove(list, 1)
		end
	end
end

---Why the player cannot send to a room right now, or nil when they can.
---@param convo MessengerConversation
---@return string|nil
function Sn:RoomProblem(convo)
	local kind = convo.kind
	if (kind == 'GUILD' or kind == 'OFFICER') and not IsInGuild() then
		return L['You are not in a guild.']
	elseif kind == 'PARTY' and not IsInGroup(LE_PARTY_CATEGORY_HOME) then
		return L['You are not in a party.']
	elseif kind == 'RAID' and not IsInRaid(LE_PARTY_CATEGORY_HOME) then
		return L['You are not in a raid.']
	elseif kind == 'INSTANCE' and not IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		return L['You are not in an instance group.']
	elseif kind == 'CHANNEL' then
		local id = GetChannelName(convo.target or '')
		if not id or id == 0 then
			return L['You are not in this channel.']
		end
	end
	return nil
end

---Number of chat messages the text will be sent as.
---@param convo MessengerConversation
---@param text string
---@return number
function Sn:ChunkCount(convo, text)
	local limit = convo.kind == 'BN_WHISPER' and BNET_CHUNK or CHUNK
	return #U.Split(U.Trim(text), limit)
end

---@param convo MessengerConversation
---@return number
function Sn:Limit(convo)
	return convo.kind == 'BN_WHISPER' and BNET_CHUNK or CHUNK
end

---Sends text to a conversation.
---@param key string
---@param text string
---@return boolean ok, string|nil problem
function Sn:Send(key, text)
	text = U.Trim(text or '')
	if text == '' then
		return false
	end
	if text:sub(1, 1) == '/' then
		return false, L['Slash commands only work in the normal chat box.']
	end
	if U.IsRestricted() then
		return false, L['Sending is paused during this fight. Use the normal chat box for now.']
	end
	local convo = Store:Get(key)
	if not convo then
		return false
	end

	local chunks = U.Split(text, self:Limit(convo))
	local kind = convo.kind

	if kind == 'WHISPER' then
		local target = convo.target
		recentTargets[strlower(target)] = { key = key, t = GetTime() }
		recentTargets[strlower(U.ShortName(target))] = { key = key, t = GetTime() }
		for _, chunk in ipairs(chunks) do
			local ok, err = pcall(SendChat, chunk, 'WHISPER', nil, target)
			if not ok then
				M.log.warning('Whisper failed: ' .. tostring(err))
				return false, L['That message could not be sent.']
			end
		end
	elseif kind == 'BN_WHISPER' then
		local id = M.Contacts:GetBNetID(convo)
		if not id or not SendBNet then
			return false, string.format(L['%s is not online right now.'], M:GetTitle(convo))
		end
		for _, chunk in ipairs(chunks) do
			local ok, result = pcall(SendBNet, id, chunk)
			-- The current API returns false when the server refuses; the old one returns nothing
			if not ok or result == false then
				M.log.warning('Battle.net whisper failed: ' .. tostring(result))
				return false, L['That message could not be sent.']
			end
		end
	else
		local problem = self:RoomProblem(convo)
		if problem then
			return false, problem
		end
		local kindInfo = M.KindByKey[kind]
		local chatType = kindInfo and kindInfo.sendType
		local channelId = kind == 'CHANNEL' and GetChannelName(convo.target or '') or nil
		for _, chunk in ipairs(chunks) do
			local ok, err = pcall(SendChat, chunk, chatType, nil, channelId)
			if not ok then
				M.log.warning('Chat send failed: ' .. tostring(err))
				return false, L['That message could not be sent.']
			end
		end
	end

	Remember(key, text)
	return true
end
