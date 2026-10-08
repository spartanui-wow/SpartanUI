local _, ns = ...
local M = ns.Messenger
local U = M.Util
local L = M.L

-- Turns chat events into conversation messages and decides what the normal chat window hides.
--
-- The rule that keeps messages from ever being lost: the chat filter only hides a message when
-- the router can read it and will store it. Anything unreadable (combat restrictions), censored
-- or from a Game Master stays in the normal chat. Restricted messages are fetched again by
-- line ID once the restriction lifts and added to Messenger then.

---@class Messenger.Router
local R = {}
M.Router = R

local Store = M.Store
local Contacts = M.Contacts

R.lastIncoming = nil
R.lastOutgoing = nil

----------------------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------------------

---@param lineID any
---@return boolean
local function IsCensored(lineID)
	lineID = U.Num(lineID)
	if not lineID or not (C_ChatInfo and C_ChatInfo.IsChatLineCensored) then
		return false
	end
	local ok, censored = pcall(C_ChatInfo.IsChatLineCensored, lineID)
	return ok and censored == true
end

---@param flags any
---@return boolean
local function IsStaff(flags)
	return flags == 'GM' or flags == 'DEV'
end

---@param kind MessengerKind
---@param channelBase? string
---@param channelString? string
---@return string
local function RoomName(kind, channelBase, channelString)
	if kind.key == 'CHANNEL' then
		local label = U.Str(channelString)
		if label then
			label = label:gsub('^%d+%.%s*', '')
			if label ~= '' then
				return label
			end
		end
		return channelBase or kind.label
	end
	return kind.label
end

---Conversation key for an event, or nil when the event cannot be placed.
---@param kind MessengerKind
---@param sender any
---@param bnID any
---@param channelBase any
---@return string|nil key, table|nil bnEntry
local function KeyFor(kind, sender, bnID, channelBase)
	if kind.key == 'WHISPER' then
		local full = U.FullName(sender)
		return full and Store.CharKey(full) or nil
	elseif kind.key == 'BN_WHISPER' then
		local id = U.Num(bnID)
		local entry = id and Contacts:GetBNetByID(id)
		if entry then
			return Store.BNetKey(entry.tag), entry
		end
		return nil
	elseif kind.key == 'CHANNEL' then
		local base = U.Str(channelBase)
		return base and ('ch:' .. base) or nil
	end
	return 'r:' .. kind.key
end

---True when this event belongs in Messenger (route captured, or a person already has a conversation).
---@param kind MessengerKind
---@param key string
---@param channelBase? string
---@return boolean
local function Wanted(kind, key, channelBase)
	if M:IsCaptured(kind.key, channelBase) then
		return true
	end
	return kind.group == 'people' and Store:Get(key) ~= nil
end

----------------------------------------------------------------------------------------------------
-- Mentions
----------------------------------------------------------------------------------------------------

---True when a group chat line says the player's name or one of their watch words, as a whole word.
---@param text string
---@return boolean
function R:IsMention(text)
	local alerts = M.settings.alerts
	if not alerts.mentions then
		return false
	end
	local padded = ' ' .. strlower(U.Plain(text)) .. ' '
	local words = { UnitName('player') }
	for word in (alerts.mentionWords or ''):gmatch('[^,]+') do
		word = U.Trim(word)
		if word ~= '' then
			words[#words + 1] = word
		end
	end
	for _, word in ipairs(words) do
		local escaped = strlower(word):gsub('([%(%)%.%%%+%-%*%?%[%]%^%$])', '%%%1')
		if padded:find('[^%w\128-\255]' .. escaped .. '[^%w\128-\255]') then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------------------------------------
-- Recording
----------------------------------------------------------------------------------------------------

---Stores one readable chat line.
---@param event string
---@param text string
---@param sender string
---@param guid any
---@param bnID any
---@param flags any
---@param channelBase any
---@param channelString any
---@param stamp? number
function R:Record(event, text, sender, guid, bnID, flags, channelBase, channelString, stamp)
	local kind = M.KindByEvent[event]
	if not kind then
		return
	end
	local key, bnEntry = KeyFor(kind, sender, bnID, channelBase)
	if not key or not Wanted(kind, key, U.Str(channelBase)) then
		return
	end

	local outgoing = kind.events[event] == true
	local msg = { t = stamp or time(), x = text }
	if IsStaff(flags) then
		msg.gm = true
	end

	if kind.key == 'WHISPER' then
		local full = U.FullName(sender)
		local fields = { kind = 'WHISPER', name = U.DisplayName(full), target = full }
		if not outgoing then
			fields.class = U.ClassFromGUID(guid)
			-- A Battle.net friend on a character we have not seen them on yet
			local readable = U.Str(guid)
			if readable and C_BattleNet and C_BattleNet.GetAccountInfoByGUID and not M.Colors:TagFor(full) then
				local ok, account = pcall(C_BattleNet.GetAccountInfoByGUID, readable)
				if ok and account then
					M.Colors:Link(full, account.battleTag)
				end
			end
		end
		Store:Ensure(key, fields)
	elseif kind.key == 'BN_WHISPER' then
		Store:Ensure(key, {
			kind = 'BN_WHISPER',
			name = bnEntry.tag:match('^([^#]+)') or bnEntry.tag,
			target = bnEntry.tag,
		})
	else
		local full = U.FullName(sender)
		outgoing = full ~= nil and U.SameName(full, U.PlayerFullName())
		msg.s = full
		msg.cl = U.ClassFromGUID(guid)
		if not outgoing and R:IsMention(text) then
			msg.mn = true
		end
		if kind.key == 'EMOTE' then
			msg.em = true
		end
		Store:Ensure(key, { kind = kind.key, name = RoomName(kind, U.Str(channelBase), channelString), target = U.Str(channelBase) })
	end

	if outgoing then
		msg.o = true
		msg.a = UnitName('player')
	end
	Store:Add(key, msg)

	if kind.group == 'people' then
		if outgoing then
			R.lastOutgoing = key
		else
			R.lastIncoming = key
		end
	end
	if not outgoing then
		M:Fire('INCOMING', key, msg, kind)
	end
end

---@param key string
---@param text string
local function AddSystemLine(key, text)
	if Store:Get(key) then
		Store:Add(key, { sys = true, x = text })
	end
end

----------------------------------------------------------------------------------------------------
-- Restricted messages
----------------------------------------------------------------------------------------------------

local deferred = {}
local drainTicker

local function StopTicker()
	if drainTicker then
		drainTicker:Cancel()
		drainTicker = nil
	end
end

---@return boolean
function R:HasDeferred()
	return #deferred > 0
end

local function Drain()
	if #deferred == 0 then
		StopTicker()
		return
	end
	if U.IsRestricted() then
		return
	end
	local remaining = {}
	local now = time()
	for _, item in ipairs(deferred) do
		local okText, text = pcall(C_ChatInfo.GetChatLineText, item.lineID)
		local okSender, sender = pcall(C_ChatInfo.GetChatLineSenderName, item.lineID)
		local okGuid, guid = pcall(C_ChatInfo.GetChatLineSenderGUID, item.lineID)
		text = okText and U.Str(text) or nil
		sender = okSender and U.Str(sender) or nil
		guid = okGuid and U.Str(guid) or nil
		if text and sender then
			local bnID
			local kind = M.KindByEvent[item.event]
			if kind and kind.key == 'BN_WHISPER' then
				local entry = Contacts:GetBNetByAccountName(sender)
				bnID = entry and entry.id
			end
			if kind and (kind.key ~= 'BN_WHISPER' or bnID) then
				R:Record(item.event, text, sender, guid, bnID, item.flags, item.channelBase, item.channelString, item.t)
			else
				M.log.debug('Could not place a restricted Battle.net line after the fight')
			end
		elseif now - item.t < 120 then
			table.insert(remaining, item)
		end
	end
	deferred = remaining
	if #deferred == 0 then
		StopTicker()
	end
	M:Fire('RESTRICTION_CHANGED')
end

---@param event string
---@param lineID any
---@param flags any
---@param channelBase any
---@param channelString any
local function Defer(event, lineID, flags, channelBase, channelString)
	lineID = U.Num(lineID)
	if not lineID or not (C_ChatInfo and C_ChatInfo.GetChatLineText) then
		return
	end
	table.insert(deferred, {
		event = event,
		lineID = lineID,
		flags = flags,
		channelBase = U.Str(channelBase),
		channelString = U.Str(channelString),
		t = time(),
	})
	if not drainTicker then
		drainTicker = C_Timer.NewTicker(2, Drain)
	end
	M:Fire('RESTRICTION_CHANGED')
end

----------------------------------------------------------------------------------------------------
-- Other addons' chat filters (spam blockers, blacklists)
----------------------------------------------------------------------------------------------------

local ProcessFilters = ChatFrameUtil and ChatFrameUtil.ProcessMessageEventFilters
local checkingOthers = false

---True when another addon's chat filter would drop this line. Only the drop decision is used;
---text rewrites by other filters are ignored so stored messages stay clean.
---@return boolean
local function DroppedByOtherFilters(event, ...)
	local frame = DEFAULT_CHAT_FRAME
	if not frame then
		return false
	end
	checkingOthers = true
	local ok, dropped = false, false
	if ProcessFilters then
		ok, dropped = pcall(ProcessFilters, frame, event, ...)
	elseif ChatFrame_GetMessageEventFilters then
		ok = true
		for _, filter in ipairs(ChatFrame_GetMessageEventFilters(event) or {}) do
			local called, hide = pcall(filter, frame, event, ...)
			if called and hide then
				dropped = true
				break
			end
		end
	end
	checkingOthers = false
	return ok and dropped == true
end

----------------------------------------------------------------------------------------------------
-- Event handlers
----------------------------------------------------------------------------------------------------

local function OnChatEvent(event, ...)
	local text, sender, _, channelString, _, flags, _, channelIndex, channelBase, _, lineID, guid, bnID = ...
	channelBase = event == 'CHAT_MSG_CHANNEL' and U.ChannelName(channelIndex, channelBase) or nil
	if not M.enabled then
		return
	end
	local kind = M.KindByEvent[event]
	if not kind then
		return
	end
	if kind.group == 'rooms' and not M:IsCaptured(kind.key, U.Str(channelBase)) then
		return
	end
	if IsCensored(lineID) then
		return
	end
	if U.AnySecret(text, sender, guid, bnID) then
		Defer(event, lineID, flags, channelBase, channelString)
		return
	end
	text = U.Str(text)
	if not text or DroppedByOtherFilters(event, ...) then
		return
	end
	R:Record(event, text, sender, guid, bnID, flags, channelBase, channelString)
end

local function OnAwayMessage(event, text, sender)
	if U.AnySecret(text, sender) then
		return
	end
	local full = U.FullName(sender)
	text = U.Str(text)
	if not full or not text then
		return
	end
	local pattern = event == 'CHAT_MSG_DND' and L['%s is busy: %s'] or L['%s is away: %s']
	AddSystemLine(Store.CharKey(full), string.format(pattern, U.DisplayName(full), text))
end

local notFoundPattern
local function OnSystemMessage(_, text)
	text = U.Str(text)
	if not text or not ERR_CHAT_PLAYER_NOT_FOUND_S then
		return
	end
	if not notFoundPattern then
		notFoundPattern = '^' .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub('([%(%)%.%%%+%-%*%?%[%]%^%$])', '%%%1'):gsub('%%%%s', '(.+)') .. '$'
	end
	local name = text:match(notFoundPattern)
	if not name then
		return
	end
	local key = M.Sender:RecentTarget(name)
	if key then
		local convo = Store:Get(key)
		AddSystemLine(key, string.format(L['%s is offline or not playing right now.'], convo and convo.name or name))
	end
end

----------------------------------------------------------------------------------------------------
-- Normal chat window filter
----------------------------------------------------------------------------------------------------

local function ShouldHide(event, text, sender, flags, channelBase, lineID, bnID)
	local kind = M.KindByEvent[event]
	if not kind then
		return false
	end
	local route = M:GetRoute(kind.key, U.Str(channelBase))
	if not route or not route.hide then
		return false
	end
	if not route.capture or IsStaff(flags) or U.AnySecret(text, sender) or not U.Str(text) or IsCensored(lineID) then
		return false
	end
	if kind.key == 'BN_WHISPER' and U.IsSecret(bnID) then
		return false
	end
	local key = KeyFor(kind, sender, bnID, channelBase)
	return key ~= nil and Wanted(kind, key, U.Str(channelBase))
end

local function ChatFilter(_, event, text, sender, _, _, _, flags, _, channelIndex, channelBase, _, lineID, _, bnID)
	if not M.enabled or checkingOthers then
		return false
	end
	channelBase = event == 'CHAT_MSG_CHANNEL' and U.ChannelName(channelIndex, channelBase) or nil
	local ok, hide = pcall(ShouldHide, event, text, sender, flags, channelBase, lineID, bnID)
	return ok and hide == true
end

local function AwayFilter(_, _, text, sender)
	if not M.enabled or U.AnySecret(text, sender) then
		return false
	end
	local route = M:GetRoute('WHISPER')
	local full = U.FullName(sender)
	return route and route.capture and route.hide and full ~= nil and Store:Get(Store.CharKey(full)) ~= nil or false
end

local AddFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
local RemoveFilter = (ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter) or ChatFrame_RemoveMessageEventFilter

----------------------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------------------

local registered = {}

---Registers chat events for the kinds that currently need them. Call after routing changes.
function R:RefreshEvents()
	local wantChannels = false
	for name, route in pairs(M.settings.channels) do
		if name ~= '*' and route.capture then
			wantChannels = true
		end
	end
	for _, kind in ipairs(M.Kinds) do
		local want = kind.group == 'people' or (kind.key == 'CHANNEL' and wantChannels) or M:IsCaptured(kind.key)
		for event in pairs(kind.events) do
			if want and not registered[event] then
				registered[event] = M:RegisterEvent(event, 'Router', OnChatEvent)
			elseif not want and registered[event] then
				M:UnregisterEvent(event, 'Router')
				registered[event] = nil
			end
		end
	end
end

function R:Enable()
	self:RefreshEvents()
	M:RegisterEvent('CHANNEL_UI_UPDATE', 'Router', U.ResetChannels)
	M:RegisterEvent('CHAT_MSG_CHANNEL_NOTICE', 'Router', U.ResetChannels)
	M:RegisterEvent('CHAT_MSG_AFK', 'Router', OnAwayMessage)
	M:RegisterEvent('CHAT_MSG_DND', 'Router', OnAwayMessage)
	M:RegisterEvent('CHAT_MSG_SYSTEM', 'Router', OnSystemMessage)
	M:RegisterEvent('ADDON_RESTRICTION_STATE_CHANGED', 'Router', function()
		C_Timer.After(0.5, Drain)
		M:Fire('RESTRICTION_CHANGED')
	end)
	M:RegisterEvent('PLAYER_REGEN_DISABLED', 'Router', function()
		M.inCombat = true
		M:Fire('COMBAT', true)
	end)
	M:RegisterEvent('PLAYER_REGEN_ENABLED', 'Router', function()
		M.inCombat = false
		M:Fire('COMBAT', false)
		C_Timer.After(1, Drain)
	end)
	M.inCombat = UnitAffectingCombat('player') and true or false

	if AddFilter and not R.filtersAdded then
		R.filtersAdded = true
		for event in pairs(M.KindByEvent) do
			AddFilter(event, ChatFilter)
		end
		AddFilter('CHAT_MSG_AFK', AwayFilter)
		AddFilter('CHAT_MSG_DND', AwayFilter)
	end
end

function R:Disable()
	for event in pairs(registered) do
		M:UnregisterEvent(event, 'Router')
	end
	wipe(registered)
	for _, event in ipairs({
		'CHANNEL_UI_UPDATE',
		'CHAT_MSG_CHANNEL_NOTICE',
		'CHAT_MSG_AFK',
		'CHAT_MSG_DND',
		'CHAT_MSG_SYSTEM',
		'ADDON_RESTRICTION_STATE_CHANGED',
		'PLAYER_REGEN_DISABLED',
		'PLAYER_REGEN_ENABLED',
	}) do
		M:UnregisterEvent(event, 'Router')
	end
	if RemoveFilter and R.filtersAdded then
		R.filtersAdded = false
		for event in pairs(M.KindByEvent) do
			RemoveFilter(event, ChatFilter)
		end
		RemoveFilter('CHAT_MSG_AFK', AwayFilter)
		RemoveFilter('CHAT_MSG_DND', AwayFilter)
	end
	StopTicker()
end
