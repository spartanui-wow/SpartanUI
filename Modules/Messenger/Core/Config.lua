local _, ns = ...
local M = ns.Messenger
local L = M.L

----------------------------------------------------------------------------------------------------
-- Chat kinds: every chat type Messenger can hold, in the order the options list them
----------------------------------------------------------------------------------------------------

---@class MessengerKind
---@field key string
---@field label string
---@field group 'people'|'rooms'
---@field colorType string ChatTypeInfo key
---@field sendType? string SendChatMessage chat type
---@field initial string Avatar letter for rooms
---@field events table<string, boolean> event -> true when the event is the player's own message echo

---@type MessengerKind[]
M.Kinds = {
	{ key = 'WHISPER', label = L['Whispers'], group = 'people', colorType = 'WHISPER', events = { CHAT_MSG_WHISPER = false, CHAT_MSG_WHISPER_INFORM = true } },
	{ key = 'BN_WHISPER', label = L['Battle.net whispers'], group = 'people', colorType = 'BN_WHISPER', events = { CHAT_MSG_BN_WHISPER = false, CHAT_MSG_BN_WHISPER_INFORM = true } },
	{ key = 'GUILD', label = L['Guild'], group = 'rooms', colorType = 'GUILD', sendType = 'GUILD', initial = 'G', events = { CHAT_MSG_GUILD = false } },
	{ key = 'OFFICER', label = L['Officer'], group = 'rooms', colorType = 'OFFICER', sendType = 'OFFICER', initial = 'O', events = { CHAT_MSG_OFFICER = false } },
	{ key = 'PARTY', label = L['Party'], group = 'rooms', colorType = 'PARTY', sendType = 'PARTY', initial = 'P', events = { CHAT_MSG_PARTY = false, CHAT_MSG_PARTY_LEADER = false } },
	{
		key = 'RAID',
		label = L['Raid'],
		group = 'rooms',
		colorType = 'RAID',
		sendType = 'RAID',
		initial = 'R',
		events = { CHAT_MSG_RAID = false, CHAT_MSG_RAID_LEADER = false, CHAT_MSG_RAID_WARNING = false },
	},
	{
		key = 'INSTANCE',
		label = L['Instance'],
		group = 'rooms',
		colorType = 'INSTANCE_CHAT',
		sendType = 'INSTANCE_CHAT',
		initial = 'I',
		events = { CHAT_MSG_INSTANCE_CHAT = false, CHAT_MSG_INSTANCE_CHAT_LEADER = false },
	},
	{ key = 'SAY', label = L['Say'], group = 'rooms', colorType = 'SAY', sendType = 'SAY', initial = 'S', events = { CHAT_MSG_SAY = false } },
	{ key = 'YELL', label = L['Yell'], group = 'rooms', colorType = 'YELL', sendType = 'YELL', initial = 'Y', events = { CHAT_MSG_YELL = false } },
	{ key = 'EMOTE', label = L['Emotes'], group = 'rooms', colorType = 'EMOTE', sendType = 'EMOTE', initial = 'E', events = { CHAT_MSG_EMOTE = false } },
	{ key = 'CHANNEL', label = L['Channels'], group = 'rooms', colorType = 'CHANNEL', sendType = 'CHANNEL', initial = '#', events = { CHAT_MSG_CHANNEL = false } },
}

M.KindByKey = {}
M.KindByEvent = {}
for _, kind in ipairs(M.Kinds) do
	M.KindByKey[kind.key] = kind
	for event in pairs(kind.events) do
		M.KindByEvent[event] = kind
	end
end

----------------------------------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------------------------------

local function Route(capture)
	return { capture = capture, hide = true }
end

M.defaults = {
	profile = {
		routes = {
			WHISPER = Route(true),
			BN_WHISPER = Route(true),
			GUILD = Route(false),
			OFFICER = Route(false),
			PARTY = Route(false),
			RAID = Route(false),
			INSTANCE = Route(false),
			SAY = Route(false),
			YELL = Route(false),
			EMOTE = Route(false),
		},
		channels = {
			['*'] = Route(false),
		},
		window = {
			width = 720,
			height = 460,
			point = 'CENTER',
			x = 0,
			y = 60,
			alpha = 0.94,
		},
		fontSize = 13,
		timeFormat = 'auto',
		replyKey = true,
		takeOverWhispers = true,
		fadeWhileMoving = 0.5,
		emoji = true,
		onWhisper = 'alert',
		alerts = {
			people = { sound = true, toast = true, flash = true },
			rooms = { sound = false, toast = false, flash = false },
			holdInCombat = true,
			hideInCombat = false,
			toastDuration = 6,
		},
		toastAnchor = {
			point = 'BOTTOMLEFT',
			x = 24,
			y = 300,
		},
		minimap = {
			hide = false,
		},
		history = {
			maxMessages = 500,
			keepDays = 0,
			roomDays = 3,
		},
	},
	global = {
		people = {},
		introShown = false,
	},
	char = {
		defaultKeyOffered = false,
		rooms = {},
		popouts = {},
	},
}

---Route settings for a kind, or for a numbered channel by its base name.
---@param kindKey string
---@param channel? string
---@return table|nil
function M:GetRoute(kindKey, channel)
	if kindKey == 'CHANNEL' then
		return channel and self.settings.channels[channel] or nil
	end
	return self.settings.routes[kindKey]
end

---@param kindKey string
---@param channel? string
---@return boolean
function M:IsCaptured(kindKey, channel)
	local route = self:GetRoute(kindKey, channel)
	return route ~= nil and route.capture == true
end
