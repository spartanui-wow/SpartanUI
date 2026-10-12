-- Secret values for the mock client.
--
-- A secret is a proxy whose every operator raises an error: arithmetic, comparison (__lt, __le,
-- __eq), length, indexing, assignment and calls. Concatenation is allowed and gives another
-- secret string, as in the game. type() reports the hidden value's type, tostring() and
-- string.format() give secret strings, and canaccessvalue/issecretvalue see through them.
--
-- What no runtime mock can catch: boolean tests (`if secret then`, `not secret`, `and`/`or`),
-- comparison with a value of another type (Lua never calls __eq then) and use as a table key.
-- The token lint covers those (Tests/Nameplates/lint.py).
--
-- Under Lua 5.1 the proxies are userdata from newproxy(), because 5.1 ignores __len on tables.

local S = {}
local rawtype = type
local rawtostring = tostring
local newproxy = newproxy

local hidden = setmetatable({}, { __mode = 'k' }) -- proxy -> { v = value, kind = type name }
S.count = 0

local function fail(what)
	error('attempt to ' .. what .. ' a secret value', 3)
end

local meta = {}
meta.__add = function()
	fail('perform arithmetic on')
end
meta.__sub = meta.__add
meta.__mul = meta.__add
meta.__div = meta.__add
meta.__mod = meta.__add
meta.__pow = meta.__add
meta.__unm = meta.__add
meta.__idiv = meta.__add
meta.__band = meta.__add
meta.__bor = meta.__add
meta.__bxor = meta.__add
meta.__bnot = meta.__add
meta.__shl = meta.__add
meta.__shr = meta.__add
meta.__lt = function()
	fail('compare')
end
meta.__le = meta.__lt
meta.__eq = meta.__lt
meta.__len = function()
	fail('get the length of')
end
meta.__index = function()
	fail('index')
end
meta.__newindex = function()
	fail('assign into')
end
meta.__call = function()
	fail('call')
end
meta.__tostring = function()
	return '<secret>'
end
meta.__metatable = 'secret'

local function reveal(x)
	local h = hidden[x]
	if h then
		return h.v
	end
	return x
end

local function isSecret(x)
	return hidden[x] ~= nil
end

---Wrap a plain value as a secret. nil stays nil; a secret stays as it is.
---@param value any
---@return any
function S.Wrap(value)
	if value == nil or hidden[value] then
		return value
	end
	local proxy
	if newproxy then
		proxy = newproxy(true)
		local m = getmetatable(proxy)
		for k, v in pairs(meta) do
			m[k] = v
		end
	else
		proxy = setmetatable({}, meta)
	end
	hidden[proxy] = { v = value, kind = rawtype(value) }
	S.count = S.count + 1
	return proxy
end

---The value behind a secret (tests only); plain values come back unchanged.
S.Reveal = reveal
S.IsSecret = isSecret

---True when any of the values is secret.
function S.Any(...)
	for i = 1, select('#', ...) do
		if hidden[(select(i, ...))] then
			return true
		end
	end
	return false
end

---Unwrap every argument (tests and the mock's own sinks).
function S.RevealAll(...)
	local n = select('#', ...)
	local t = { ... }
	for i = 1, n do
		t[i] = reveal(t[i])
	end
	return unpack(t, 1, n)
end

meta.__concat = function(a, b)
	return S.Wrap(rawtostring(reveal(a)) .. rawtostring(reveal(b)))
end

-- Global functions that see through secrets the way the game's do
type = function(v)
	local h = hidden[v]
	if h then
		return h.kind
	end
	return rawtype(v)
end

tostring = function(v)
	if hidden[v] then
		return S.Wrap(rawtostring(hidden[v].v))
	end
	return rawtostring(v)
end

local rawtonumber = tonumber
tonumber = function(v, base)
	if hidden[v] then
		return S.Wrap(rawtonumber(hidden[v].v, base))
	end
	return rawtonumber(v, base)
end

local rawformat = string.format
string.format = function(fmt, ...)
	if S.Any(fmt, ...) then
		return S.Wrap(rawformat(reveal(fmt), S.RevealAll(...)))
	end
	return rawformat(fmt, ...)
end
format = string.format

S.rawtype = rawtype
S.rawtostring = rawtostring

return S
