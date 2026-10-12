-- Lua 5.1 and WoW Lua globals for both runners.
-- Under lupa (Lua 5.1) most of this is already there; under the LuaLS binary (Lua 5.4/5.5) the
-- 5.1 functions WoW addons rely on are added back. Keep this file valid Lua 5.1: no bitwise
-- operators, no goto, no integer division.

local IS51 = _VERSION == 'Lua 5.1'
RUNTIME = RUNTIME or (IS51 and 'lua51' or 'luals')

local rawtype = type
local floor = math.floor

unpack = unpack or table.unpack
loadstring = loadstring or load
if not getfenv then
	getfenv = function()
		return _G
	end
	setfenv = function(f)
		return f
	end
end
math.pow = math.pow or function(a, b)
	return a ^ b
end
math.mod = math.mod or math.fmod
math.ldexp = math.ldexp or function(m, e)
	return m * 2 ^ e
end
table.getn = table.getn or function(t)
	return #t
end

-- WoW's xpcall passes extra arguments to the function; plain Lua 5.1 does not
if IS51 then
	local xpcall51 = xpcall
	xpcall = function(f, handler, ...)
		local n = select('#', ...)
		if n == 0 then
			return xpcall51(f, handler)
		end
		local args = { ... }
		return xpcall51(function()
			return f(unpack(args, 1, n))
		end, handler)
	end
end

-- Lua 5.4 refuses %d for a number with a fraction and prints 150.0 for a float; WoW's 5.1 does neither.
if not IS51 then
	local format54 = string.format
	string.format = function(fmt, ...)
		local n = select('#', ...)
		if n == 0 or rawtype(fmt) ~= 'string' then
			return format54(fmt, ...)
		end
		local args = { ... }
		local i = 0
		for spec in fmt:gmatch('%%[-+ #0]*%d*%.?%d*([%a%%])') do
			if spec ~= '%' then
				i = i + 1
				local v = args[i]
				if rawtype(v) == 'number' and spec:match('[diouxXc]') and v ~= floor(v) then
					args[i] = v < 0 and -floor(-v) or floor(v)
				end
			end
		end
		return format54(fmt, unpack(args, 1, n))
	end
	local tostring54 = tostring
	tostring = function(v)
		if rawtype(v) == 'number' then
			return format54('%.14g', v)
		end
		return tostring54(v)
	end
end

-- bit library, as WoW ships it, written without bitwise operators so it parses on Lua 5.1
do
	local MOD = 4294967296
	local function norm(a)
		a = a % MOD
		if a < 0 then
			a = a + MOD
		end
		return floor(a)
	end
	local function op(a, b, fn)
		a, b = norm(a), norm(b)
		local result, place = 0, 1
		for _ = 1, 32 do
			local abit, bbit = a % 2, b % 2
			if fn(abit, bbit) then
				result = result + place
			end
			a, b = (a - abit) / 2, (b - bbit) / 2
			place = place * 2
		end
		return result
	end
	local function tosigned(v)
		if v >= 2147483648 then
			return v - MOD
		end
		return v
	end
	bit = {
		band = function(a, b, ...)
			local r = op(a, b, function(x, y)
				return x == 1 and y == 1
			end)
			if select('#', ...) > 0 then
				return bit.band(r, ...)
			end
			return tosigned(r)
		end,
		bor = function(a, b, ...)
			local r = op(a, b or 0, function(x, y)
				return x == 1 or y == 1
			end)
			if select('#', ...) > 0 then
				return bit.bor(r, ...)
			end
			return tosigned(r)
		end,
		bxor = function(a, b, ...)
			local r = op(a, b or 0, function(x, y)
				return x ~= y
			end)
			if select('#', ...) > 0 then
				return bit.bxor(r, ...)
			end
			return tosigned(r)
		end,
		bnot = function(a)
			return tosigned(MOD - 1 - norm(a))
		end,
		lshift = function(a, n)
			return tosigned(norm(norm(a) * 2 ^ n))
		end,
		rshift = function(a, n)
			return tosigned(floor(norm(a) / 2 ^ n))
		end,
		arshift = function(a, n)
			local v = norm(a)
			local shifted = floor(v / 2 ^ n)
			if v >= 2147483648 then
				shifted = shifted + MOD - 2 ^ (32 - n)
			end
			return tosigned(norm(shifted))
		end,
		mod = function(a, b)
			return a % b
		end,
	}
end

-- WoW's global aliases for the string, table and math libraries
strbyte, strchar, strfind, strlen, strlower, strupper, strrep, strsub, strrev = string.byte, string.char, string.find, string.len, string.lower, string.upper, string.rep, string.sub, string.reverse
strmatch, gmatch, gsub, format = string.match, string.gmatch, string.gsub, string.format
abs, ceil, floor, max, min, sqrt, exp, log, log10 = math.abs, math.ceil, math.floor, math.max, math.min, math.sqrt, math.exp, math.log, math.log10 or function(x)
	return math.log(x, 10)
end
sin, cos, tan, asin, acos, atan, atan2, deg, rad = math.sin, math.cos, math.tan, math.asin, math.acos, math.atan, math.atan2 or math.atan, math.deg, math.rad
mod, fmod, random, frexp, ldexp = math.fmod, math.fmod, math.random, math.frexp or function(x)
	return x, 0
end, math.ldexp
fastrandom = math.random
tinsert, tremove, sort, getn = table.insert, table.remove, table.sort, table.getn
foreach = function(t, fn)
	for k, v in pairs(t) do
		local r = fn(k, v)
		if r ~= nil then
			return r
		end
	end
end
foreachi = function(t, fn)
	for i, v in ipairs(t) do
		local r = fn(i, v)
		if r ~= nil then
			return r
		end
	end
end
date, time, difftime = os.date, os.time, os.difftime

strtrim = function(s, chars)
	chars = chars or ' \t\r\n'
	local class = '[' .. chars:gsub('%%', '%%%%'):gsub('%]', '%%]') .. ']'
	return (s:gsub('^' .. class .. '+', ''):gsub(class .. '+$', ''))
end
strsplit = function(delimiter, text, pieces)
	local out = {}
	local start = 1
	local class = '[' .. delimiter:gsub('%%', '%%%%'):gsub('%]', '%%]') .. ']'
	while true do
		if pieces and #out == pieces - 1 then
			out[#out + 1] = text:sub(start)
			break
		end
		local s, e = text:find(class, start)
		if not s then
			out[#out + 1] = text:sub(start)
			break
		end
		out[#out + 1] = text:sub(start, s - 1)
		start = e + 1
	end
	return unpack(out)
end
strjoin = function(delimiter, ...)
	return table.concat({ ... }, delimiter)
end
strconcat = function(...)
	return table.concat({ ... })
end
strlenutf8 = function(s)
	local _, count = s:gsub('[^\128-\191]', '')
	return count
end
strcmputf8i = function(a, b)
	a, b = a:lower(), b:lower()
	if a == b then
		return 0
	end
	return a < b and -1 or 1
end
wipe = function(t)
	for k in pairs(t) do
		t[k] = nil
	end
	return t
end
table.wipe = wipe
tostringall = function(...)
	local n = select('#', ...)
	local t = { ... }
	for i = 1, n do
		t[i] = tostring(t[i])
	end
	return unpack(t, 1, n)
end
