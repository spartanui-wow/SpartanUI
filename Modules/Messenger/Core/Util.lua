local _, ns = ...
local M = ns.Messenger

---@class Messenger.Util
local U = {}
M.Util = U

----------------------------------------------------------------------------------------------------
-- Secret values (WoW 12.0 chat messaging lockdown)
----------------------------------------------------------------------------------------------------

local issecretvalue = issecretvalue

---@param value any
---@return boolean
function U.IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value) == true
end

---@return boolean
function U.AnySecret(...)
	for i = 1, select('#', ...) do
		if U.IsSecret((select(i, ...))) then
			return true
		end
	end
	return false
end

---Returns the value only when it is a readable, non-empty string.
---@param value any
---@return string|nil
function U.Str(value)
	-- Secret check first: even comparing a secret value to nil is not safe
	if U.IsSecret(value) or type(value) ~= 'string' or value == '' then
		return nil
	end
	return value
end

---@param value any
---@return number|nil
function U.Num(value)
	if U.IsSecret(value) or type(value) ~= 'number' then
		return nil
	end
	return value
end

---True while the game blocks addons from reading and sending chat.
---@return boolean
function U.IsRestricted()
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
		local ok, restricted = pcall(C_ChatInfo.InChatMessagingLockdown)
		return ok and restricted == true
	end
	return false
end

----------------------------------------------------------------------------------------------------
-- Names
----------------------------------------------------------------------------------------------------

local playerRealm

---True on clients where characters have a first and last name and no realm (WoW Forever).
---Names there contain a space, and "First-Last" means the same character.
---@return boolean
function U.SurnameNames()
	if RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() == true then
		return true
	end
	return WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == (WOW_PROJECT_CAMELOT or 18)
end

---@return string
function U.PlayerRealm()
	if not playerRealm or playerRealm == '' then
		playerRealm = GetNormalizedRealmName and GetNormalizedRealmName()
		if not playerRealm or playerRealm == '' then
			playerRealm = (GetRealmName() or ''):gsub('[%s%-]', '')
		end
	end
	return playerRealm
end

---Name-Realm for any name, adding the player's realm when missing.
---@param name string|nil
---@return string|nil
function U.FullName(name)
	name = U.Str(name)
	if not name then
		return nil
	end
	if U.SurnameNames() then
		name = U.Trim((name:gsub('%-', ' '):gsub('%s+', ' ')))
		return name ~= '' and name or nil
	end
	name = name:gsub('%s', '')
	if name:find('-', 1, true) then
		return name
	end
	local realm = U.PlayerRealm()
	if realm == '' then
		return name
	end
	return name .. '-' .. realm
end

---Drops the realm when it is the player's own realm.
---@param full string
---@return string
function U.DisplayName(full)
	if U.SurnameNames() then
		return full
	end
	local name, realm = full:match('^([^%-]+)%-(.+)$')
	if name and realm == U.PlayerRealm() then
		return name
	end
	return full
end

---@param full string
---@return string
function U.ShortName(full)
	if U.SurnameNames() then
		return full
	end
	return full:match('^([^%-]+)') or full
end

---Joins a character name with its realm (or, on first-and-last-name clients, its surname).
---@param name string
---@param realm string|nil
---@return string|nil
function U.JoinName(name, realm)
	realm = U.Str(realm)
	if U.SurnameNames() then
		if realm and not strlower(name):find(strlower(realm), 1, true) then
			name = name .. ' ' .. realm
		end
		return U.FullName(name)
	end
	if realm then
		return name .. '-' .. realm:gsub('%s', '')
	end
	return U.FullName(name)
end

---Whether typed text could be a character name: one word, Name-Realm, or on first-and-last-name
---clients up to two words.
---@param text string
---@return boolean
function U.LooksLikeName(text)
	if text == '' or text:find('[#|]') then
		return false
	end
	if U.SurnameNames() then
		return text:find('^[^%s%-]+[%s%-]?[^%s%-]*$') ~= nil
	end
	return not text:find('%s') or text:find('-', 1, true) ~= nil
end

---@return string
function U.PlayerFullName()
	if U.SurnameNames() then
		local name, surname = UnitNameUnmodified('player')
		return U.JoinName(name, surname) or name
	end
	local name, realm = UnitFullName('player')
	if not realm or realm == '' then
		realm = U.PlayerRealm()
	end
	return name .. '-' .. realm
end

---@param a string|nil
---@param b string|nil
---@return boolean
function U.SameName(a, b)
	return a ~= nil and b ~= nil and strlower(a) == strlower(b)
end

----------------------------------------------------------------------------------------------------
-- Channels
----------------------------------------------------------------------------------------------------

local channelNames

function U.ResetChannels()
	channelNames = nil
end

---The name a joined channel has in the channel list ("Trade", "General"), from its number.
---Chat lines for zone channels can carry the zone in their name, so the number is the
---reliable key. Both inputs are readable during chat restrictions.
---@param index any channel number (chat event arg8)
---@param base any channel base name (chat event arg9)
---@return string|nil
function U.ChannelName(index, base)
	index = U.Num(index)
	if index and index > 0 then
		if not channelNames then
			channelNames = {}
			local data = { GetChannelList() }
			for i = 1, #data, 3 do
				if type(data[i]) == 'number' and type(data[i + 1]) == 'string' then
					channelNames[data[i]] = data[i + 1]
				end
			end
		end
		if channelNames[index] then
			return channelNames[index]
		end
	end
	base = U.Str(base)
	return base and (base:gsub('%s+%-%s+.*$', '')) or nil
end

----------------------------------------------------------------------------------------------------
-- Classes
----------------------------------------------------------------------------------------------------

local classByLocalName

---@param localized string|nil
---@return string|nil classFile
function U.ClassFromLocalName(localized)
	localized = U.Str(localized)
	if not localized then
		return nil
	end
	if not classByLocalName then
		classByLocalName = {}
		for file, text in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do
			classByLocalName[text] = file
		end
		for file, text in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do
			classByLocalName[text] = file
		end
	end
	return classByLocalName[localized] or (RAID_CLASS_COLORS[localized] and localized) or nil
end

---@param guid string|nil
---@return string|nil classFile
function U.ClassFromGUID(guid)
	guid = U.Str(guid)
	if not guid or not guid:find('^Player%-') then
		return nil
	end
	local ok, _, classFile = pcall(GetPlayerInfoByGUID, guid)
	if ok then
		return U.Str(classFile)
	end
	return nil
end

---@param classFile string|nil
---@return number|nil r, number|nil g, number|nil b
function U.ClassColor(classFile)
	if not classFile then
		return nil
	end
	local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
	local c = colors and colors[classFile]
	if c then
		return c.r, c.g, c.b
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- Time
----------------------------------------------------------------------------------------------------

---@return boolean
local function Use24h()
	local fmt = M.settings and M.settings.timeFormat or 'auto'
	if fmt == '24' then
		return true
	elseif fmt == '12' then
		return false
	end
	return GetCVarBool and GetCVarBool('timeMgrUseMilitaryTime') or false
end

---@param t number
---@return string
function U.Clock(t)
	if Use24h() then
		return date('%H:%M', t)
	end
	local text = date('%I:%M %p', t):gsub('^0', '')
	return text
end

---@param t number
---@return number
local function DayStart(t)
	local d = date('*t', t)
	d.hour, d.min, d.sec = 0, 0, 0
	return time(d)
end

---@param t number
---@return string
local function Weekday(t)
	local wday = tonumber(date('%w', t)) + 1
	if CALENDAR_WEEKDAY_NAMES and CALENDAR_WEEKDAY_NAMES[wday] then
		return CALENDAR_WEEKDAY_NAMES[wday]
	end
	return date('%A', t)
end

---Label for a day separator in the message log.
---@param t number
---@return string
function U.DayLabel(t)
	local today = DayStart(time())
	local day = DayStart(t)
	if day == today then
		return M.L['Today']
	elseif day == DayStart(today - 1) then
		return M.L['Yesterday']
	elseif today - day < 6 * 86400 then
		return Weekday(t)
	end
	return date('%d %b %Y', t)
end

---Short time for the conversation list.
---@param t number
---@return string
function U.ListTime(t)
	local today = DayStart(time())
	local day = DayStart(t)
	if day == today then
		return U.Clock(t)
	elseif day == DayStart(today - 1) then
		return M.L['Yesterday']
	elseif today - day < 6 * 86400 then
		return Weekday(t):sub(1, 3)
	end
	return date('%d %b', t)
end

---@param t number
---@return number
function U.DayKey(t)
	return DayStart(t)
end

----------------------------------------------------------------------------------------------------
-- Text
----------------------------------------------------------------------------------------------------

---Removes color codes, textures and link markup, keeping link text.
---@param text string
---@return string
function U.Plain(text)
	text = text:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')
	text = text:gsub('|H.-|h(.-)|h', '%1')
	text = text:gsub('|T.-|t', ''):gsub('|A.-|a', '')
	return text
end

---@param text string
---@return string
function U.Trim(text)
	return (text:gsub('^%s+', ''):gsub('%s+$', ''))
end

---Splits text into plain runs and link runs so link markup is never cut or rewritten.
---@param text string
---@return table atoms { {text=string, link=boolean}, ... }
local function Atomize(text)
	local atoms = {}
	local i = 1
	local len = #text
	while i <= len do
		local cs, ce = text:find('|c%x%x%x%x%x%x%x%x|H.-|h.-|h|r', i)
		local ps, pe = text:find('|H.-|h.-|h', i)
		local s, e
		if cs and (not ps or cs < ps) then
			s, e = cs, ce
		elseif ps then
			s, e = ps, pe
		end
		if not s then
			table.insert(atoms, { text = text:sub(i), link = false })
			break
		end
		if s > i then
			table.insert(atoms, { text = text:sub(i, s - 1), link = false })
		end
		table.insert(atoms, { text = text:sub(s, e), link = true })
		i = e + 1
	end
	return atoms
end

---Largest cut position at or below limit that does not split a UTF-8 character.
---@param text string
---@param limit number
---@return number
local function Utf8Cut(text, limit)
	local cut = limit
	while cut > 1 do
		local nextByte = text:byte(cut + 1)
		if not nextByte or nextByte < 0x80 or nextByte >= 0xC0 then
			break
		end
		cut = cut - 1
	end
	return cut
end

---Splits a message into chat-sized chunks on word boundaries without breaking links
---or multi-byte characters.
---@param text string
---@param limit number bytes per chunk
---@return string[]
function U.Split(text, limit)
	if #text <= limit then
		return { text }
	end
	local words = {}
	for _, atom in ipairs(Atomize(text)) do
		if atom.link then
			table.insert(words, atom.text)
		else
			for word in atom.text:gmatch('%S*%s*') do
				if word ~= '' then
					table.insert(words, word)
				end
			end
		end
	end

	local chunks = {}
	local current = ''
	local function push()
		local trimmed = U.Trim(current)
		if trimmed ~= '' then
			table.insert(chunks, trimmed)
		end
		current = ''
	end
	for _, word in ipairs(words) do
		if #current + #word <= limit then
			current = current .. word
		else
			push()
			while #word > limit do
				local cut = Utf8Cut(word, limit)
				table.insert(chunks, word:sub(1, cut))
				word = word:sub(cut + 1)
			end
			current = word
		end
	end
	push()
	return chunks
end

local URL_PATTERNS = {
	'%f[%S](%a[%w+.-]+://[^%s|]+)',
	'%f[%S](www%.[%w-]+%.[^%s|]+)',
}

---Turns bare web addresses into clickable links, leaving existing links alone.
---@param text string
---@return string
function U.Linkify(text)
	if not text:find('://', 1, true) and not text:find('www.', 1, true) then
		return text
	end
	local out = {}
	for _, atom in ipairs(Atomize(text)) do
		local piece = atom.text
		if not atom.link then
			for _, pattern in ipairs(URL_PATTERNS) do
				piece = piece:gsub(pattern, function(url)
					url = url:gsub('[%.,;:!%?%)]+$', '')
					return '|cff6fb8ff|Hurl:' .. url .. '|h' .. url .. '|h|r'
				end)
			end
		end
		table.insert(out, piece)
	end
	return table.concat(out)
end

local RAID_ICON_WORDS = {
	star = 1,
	circle = 2,
	coin = 2,
	diamond = 3,
	triangle = 4,
	moon = 5,
	square = 6,
	cross = 7,
	x = 7,
	skull = 8,
}

---Replaces {skull} style markers with raid icons, the way the normal chat does.
---@param text string
---@return string
function U.RaidIcons(text)
	if not text:find('{', 1, true) then
		return text
	end
	if C_ChatInfo and C_ChatInfo.ReplaceIconAndGroupExpressions then
		local ok, result = pcall(C_ChatInfo.ReplaceIconAndGroupExpressions, text)
		if ok and type(result) == 'string' then
			return result
		end
	end
	return (
		text:gsub('{(%w+)}', function(word)
			local lower = strlower(word)
			local index = RAID_ICON_WORDS[lower] or tonumber(lower:match('^rt(%d)$'))
			if index and index >= 1 and index <= 8 then
				return '|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_' .. index .. ':0|t'
			end
		end)
	)
end
