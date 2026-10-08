local _, ns = ...
local M = ns.Messenger
local U = M.Util

-- Bubble colors. A person's color is kept for the whole account, under their BattleTag when one
-- is known, so every character a Battle.net friend plays shows in the same color. Characters are
-- tied to a BattleTag as they are seen: on the Battle.net friend list, or when a friend whispers.
--
-- Saved:
--   db.global.colors     person key ('b:battletag' or 'c:name-realm') -> palette id or { r, g, b }
--   db.global.bnetChars  lower case Name-Realm -> lower case BattleTag

---@class Messenger.Colors
local C = {}
M.Colors = C

---@class MessengerBubbleColor
---@field id string
---@field label string
---@field r number
---@field g number
---@field b number

---@type MessengerBubbleColor[]
C.Palette = {
	{ id = 'blue', label = M.L['Blue'], r = 0.16, g = 0.52, b = 1 },
	{ id = 'teal', label = M.L['Teal'], r = 0.1, g = 0.74, b = 0.74 },
	{ id = 'green', label = M.L['Green'], r = 0.2, g = 0.74, b = 0.34 },
	{ id = 'lime', label = M.L['Lime'], r = 0.58, g = 0.8, b = 0.16 },
	{ id = 'yellow', label = M.L['Yellow'], r = 0.95, g = 0.8, b = 0.16 },
	{ id = 'orange', label = M.L['Orange'], r = 1, g = 0.52, b = 0.1 },
	{ id = 'red', label = M.L['Red'], r = 0.92, g = 0.24, b = 0.24 },
	{ id = 'pink', label = M.L['Pink'], r = 0.95, g = 0.38, b = 0.68 },
	{ id = 'purple', label = M.L['Purple'], r = 0.62, g = 0.4, b = 0.95 },
	{ id = 'indigo', label = M.L['Indigo'], r = 0.4, g = 0.44, b = 0.95 },
	{ id = 'brown', label = M.L['Brown'], r = 0.66, g = 0.46, b = 0.3 },
	{ id = 'grey', label = M.L['Grey'], r = 0.5, g = 0.5, b = 0.54 },
}

C.ById = {}
for _, color in ipairs(C.Palette) do
	C.ById[color.id] = color
end

-- Colors handed out to people with none of their own (grey is left for "no color")
local AUTO = {}
for _, color in ipairs(C.Palette) do
	if color.id ~= 'grey' then
		AUTO[#AUTO + 1] = color
	end
end

---The source color for a saved value: a palette id or a custom { r, g, b }.
---@param value string|table|nil
---@return number|nil r, number|nil g, number|nil b
function C.Resolve(value)
	if type(value) == 'table' and value[1] then
		return value[1], value[2], value[3]
	end
	local color = type(value) == 'string' and C.ById[value]
	if color then
		return color.r, color.g, color.b
	end
	return nil
end

---@return table
local function Colors()
	return M.db.global.colors
end

---@return table
local function Links()
	return M.db.global.bnetChars
end

----------------------------------------------------------------------------------------------------
-- Who a color belongs to
----------------------------------------------------------------------------------------------------

---Remembers that a character belongs to a Battle.net account.
---@param full string|nil Name-Realm
---@param battleTag string|nil
function C:Link(full, battleTag)
	full, battleTag = U.Str(full), U.Str(battleTag)
	if not full or not battleTag or not M.db then
		return
	end
	local lower, tag = strlower(full), strlower(battleTag)
	local links = Links()
	if links[lower] == tag then
		return
	end
	links[lower] = tag
	-- A color picked for the character before we knew whose it was moves to the account
	local colors = Colors()
	local charKey = M.Store.CharKey(full)
	local bnetKey = M.Store.BNetKey(battleTag)
	if colors[charKey] and not colors[bnetKey] then
		colors[bnetKey] = colors[charKey]
	end
	colors[charKey] = nil
	M:Fire('COLORS_CHANGED')
end

---The BattleTag a character belongs to, when known.
---@param full string Name-Realm
---@return string|nil lower case BattleTag
function C:TagFor(full)
	return Links()[strlower(full)]
end

---The key a character's color is saved under: their BattleTag when known, else the character.
---@param full string Name-Realm
---@return string
function C:KeyForCharacter(full)
	local tag = self:TagFor(full)
	if tag then
		return M.Store.BNetKey(tag)
	end
	return M.Store.CharKey(full)
end

---The person who sent a message, as a color key. nil for the player's own messages and system lines.
---@param convo MessengerConversation
---@param msg table
---@return string|nil key, string|nil name Name shown in menus
function C:SenderKey(convo, msg)
	if msg.o or msg.sys then
		return nil
	end
	if msg.s then
		return self:KeyForCharacter(msg.s), msg.s
	end
	return self:ConversationKey(convo)
end

---The person a conversation is with, as a color key. nil for channels.
---@param convo MessengerConversation
---@return string|nil key, string|nil name
function C:ConversationKey(convo)
	if convo.kind == 'WHISPER' and convo.target then
		return self:KeyForCharacter(convo.target), convo.target
	elseif convo.kind == 'BN_WHISPER' and convo.target then
		return M.Store.BNetKey(convo.target), convo.target
	end
	return nil
end

---@param key string Color key
---@return boolean
function C.IsAccountKey(key)
	return key:sub(1, 2) == 'b:'
end

----------------------------------------------------------------------------------------------------
-- Reading and choosing
----------------------------------------------------------------------------------------------------

---The color the player picked for a person, if any.
---@param key string
---@return string|table|nil
function C:Get(key)
	return Colors()[key]
end

---@param key string
---@param value string|table|nil nil goes back to no color
function C:Set(key, value)
	Colors()[key] = value
	M:Fire('COLORS_CHANGED')
end

---A stable color picked from the key, so a person keeps the same color without choosing one.
---@param key string
---@return MessengerBubbleColor
function C.Auto(key)
	local hash = 0
	for i = 1, #key do
		hash = (hash * 31 + key:byte(i)) % 2147483647
	end
	return AUTO[hash % #AUTO + 1]
end

---The player's own bubble color for a conversation.
---@param convo MessengerConversation|nil
---@return number r, number g, number b
function C:Mine(convo)
	local r, g, b = C.Resolve(M.settings.bubbles.mine)
	if r then
		return r, g, b
	end
	return M.Theme.KindColor(convo)
end

---Another person's bubble color. Returns nil when the bubble should be grey.
---@param convo MessengerConversation
---@param key string|nil Color key of the person
---@return number|nil r, number|nil g, number|nil b
function C:Theirs(convo, key)
	if not key then
		return nil
	end
	local r, g, b = C.Resolve(self:Get(key))
	if r then
		return r, g, b
	end
	return self:DefaultTheirs(convo, key)
end

---The color a person gets when the player has not picked one. nil means grey.
---@param convo MessengerConversation
---@param key string
---@return number|nil r, number|nil g, number|nil b
function C:DefaultTheirs(convo, key)
	local mode = M.settings.bubbles.others
	if mode == 'color' or (mode == 'auto' and M.Store.IsRoomKey(convo.key)) then
		local auto = C.Auto(key)
		return auto.r, auto.g, auto.b
	end
	return nil
end
