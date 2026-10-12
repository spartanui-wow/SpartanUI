-- A small describe/it/assert API for the nameplate suites (documented in Tests/Nameplates/README.md).
-- Results go to stdout as lines the Python runner reads:
--   @@PASS <name>   @@FAIL <name>   @@SKIP <name> | <reason>   @@RESULT pass=N fail=N skip=N

local M = ...
local S = M.S
local rawtype = S.rawtype
local rawtostring = S.rawtostring
local luaassert = assert

local T = { pass = 0, fail = 0, skip = 0, stack = {}, hooks = {}, only = nil }

local function out(line)
	io.write(line, '\n')
end

local function dump(v, depth, seen)
	depth = depth or 0
	if S.IsSecret(v) then
		return '<secret ' .. dump(S.Reveal(v), depth) .. '>'
	end
	local t = rawtype(v)
	if t == 'string' then
		return ('%q'):format(v)
	end
	if t ~= 'table' then
		return rawtostring(v)
	end
	if M.State(v) then
		return '<' .. rawtostring(M.TypeOf(v)) .. ' ' .. rawtostring(M.Get(v, 'name') or '') .. '>'
	end
	seen = seen or {}
	if seen[v] or depth > 3 then
		return '{...}'
	end
	seen[v] = true
	local parts, n = {}, 0
	for k, val in pairs(v) do
		n = n + 1
		if n > 12 then
			parts[#parts + 1] = '...'
			break
		end
		parts[#parts + 1] = (rawtype(k) == 'string' and k or ('[' .. dump(k, depth + 1, seen) .. ']')) .. ' = ' .. dump(val, depth + 1, seen)
	end
	return '{ ' .. table.concat(parts, ', ') .. ' }'
end
T.dump = dump

local SKIP = {}

local function fail(msg, level)
	error(msg, (level or 1) + 2)
end

local function deepEqual(a, b, seen)
	if S.IsSecret(a) or S.IsSecret(b) then
		return S.IsSecret(a) and S.IsSecret(b) and deepEqual(S.Reveal(a), S.Reveal(b), seen)
	end
	if a == b then
		return true
	end
	if rawtype(a) ~= 'table' or rawtype(b) ~= 'table' then
		return false
	end
	seen = seen or {}
	if seen[a] == b then
		return true
	end
	seen[a] = b
	for k, v in pairs(a) do
		if not deepEqual(v, b[k], seen) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local A = {}

function A.equal(actual, expected, msg)
	if S.IsSecret(actual) or S.IsSecret(expected) then
		fail((msg or 'equal') .. ': got a secret value; use assert.secret or reveal it with M.S.Reveal')
	end
	if actual ~= expected then
		fail(('%s: expected %s, got %s'):format(msg or 'equal', dump(expected), dump(actual)))
	end
end
function A.not_equal(actual, unexpected, msg)
	if actual == unexpected then
		fail(('%s: did not expect %s'):format(msg or 'not_equal', dump(actual)))
	end
end
function A.same(actual, expected, msg)
	if not deepEqual(actual, expected) then
		fail(('%s: expected %s, got %s'):format(msg or 'same', dump(expected), dump(actual)))
	end
end
function A.truthy(v, msg)
	if not v then
		fail((msg or 'truthy') .. ': got ' .. dump(v))
	end
end
function A.falsy(v, msg)
	if v then
		fail((msg or 'falsy') .. ': got ' .. dump(v))
	end
end
function A.is_true(v, msg)
	if v ~= true then
		fail((msg or 'is_true') .. ': got ' .. dump(v))
	end
end
function A.is_false(v, msg)
	if v ~= false then
		fail((msg or 'is_false') .. ': got ' .. dump(v))
	end
end
function A.is_nil(v, msg)
	if v ~= nil then
		fail((msg or 'is_nil') .. ': got ' .. dump(v))
	end
end
function A.not_nil(v, msg)
	if v == nil then
		fail((msg or 'not_nil') .. ': got nil')
	end
end
function A.matches(str, pattern, msg)
	if rawtype(str) ~= 'string' or not str:find(pattern) then
		fail(('%s: %s does not match %q'):format(msg or 'matches', dump(str), pattern))
	end
end
function A.near(actual, expected, epsilon, msg)
	if rawtype(actual) ~= 'number' or math.abs(actual - expected) > (epsilon or 1e-6) then
		fail(('%s: expected about %s, got %s'):format(msg or 'near', dump(expected), dump(actual)))
	end
end
---Expect fn to raise; returns the error message. pattern is a plain substring.
function A.errors(fn, pattern, msg)
	local ok, err = pcall(fn)
	if ok then
		fail((msg or 'errors') .. ': expected an error')
	end
	err = rawtostring(err)
	if pattern and not err:find(pattern, 1, true) then
		fail(('%s: error %q does not contain %q'):format(msg or 'errors', err, pattern))
	end
	return err
end
function A.no_errors(fn, msg)
	local ok, err = pcall(fn)
	if not ok then
		fail((msg or 'no_errors') .. ': ' .. rawtostring(err))
	end
end
function A.secret(v, msg)
	if not S.IsSecret(v) then
		fail((msg or 'secret') .. ': expected a secret value, got ' .. dump(v))
	end
end
function A.not_secret(v, msg)
	if S.IsSecret(v) then
		fail((msg or 'not_secret') .. ': got a secret value')
	end
end
function A.contains(list, value, msg)
	for _, v in pairs(list or {}) do
		if v == value then
			return
		end
	end
	fail(('%s: %s not found in %s'):format(msg or 'contains', dump(value), dump(list)))
end
function A.not_contains(list, value, msg)
	for _, v in pairs(list or {}) do
		if v == value then
			fail(('%s: %s found in %s'):format(msg or 'not_contains', dump(value), dump(list)))
		end
	end
end
---Expect an empty table; the message lists what was there.
function A.empty(t, msg, describeItem)
	if t and next(t) ~= nil then
		local items = {}
		for _, v in pairs(t) do
			items[#items + 1] = describeItem and describeItem(v) or dump(v)
			if #items >= 8 then
				items[#items + 1] = '...'
				break
			end
		end
		fail((msg or 'empty') .. ':\n      ' .. table.concat(items, '\n      '))
	end
end
function A.fail(msg)
	fail(msg or 'failed')
end
---Take error-handler reports (M.errors) matching a plain substring, so the test does not fail on them.
function A.reported(pattern, msg)
	for i, e in ipairs(M.errors) do
		if rawtostring(e):find(pattern, 1, true) then
			table.remove(M.errors, i)
			return e
		end
	end
	fail(('%s: no reported error contains %q'):format(msg or 'reported', pattern))
end

-- assert(...) keeps Lua's own behavior for libraries; assert.x(...) are the test helpers
assert = setmetatable(A, {
	__call = function(_, v, message, ...)
		if not v then
			error(message or 'assertion failed!', 2)
		end
		return v, message, ...
	end,
})

local function fullName(name)
	local parts = {}
	for i = 1, #T.stack do
		parts[i] = T.stack[i].name
	end
	parts[#parts + 1] = name
	return table.concat(parts, ' > ')
end

function describe(name, fn)
	T.stack[#T.stack + 1] = { name = name, before = {}, after = {} }
	local ok, err = xpcall(fn, function(e)
		return rawtostring(e) .. '\n' .. debug.traceback('', 2)
	end)
	if not ok then
		T.fail = T.fail + 1
		out('@@FAIL ' .. fullName('(describe body)'))
		out(err)
	end
	T.stack[#T.stack] = nil
end

function before_each(fn)
	local top = T.stack[#T.stack]
	luaassert(top, 'before_each must be inside describe')
	table.insert(top.before, fn)
end

function after_each(fn)
	local top = T.stack[#T.stack]
	luaassert(top, 'after_each must be inside describe')
	table.insert(top.after, fn)
end

---Skip the running test with a reason.
function skip(reason)
	error({ [SKIP] = true, reason = reason or '' }, 0)
end

function pending(name, reason)
	T.skip = T.skip + 1
	out('@@SKIP ' .. fullName(name) .. ' | ' .. (reason or 'pending'))
end

function it(name, fn)
	local full = fullName(name)
	if T.only and not full:find(T.only, 1, true) then
		return
	end
	M.errors = {}
	local function handler(e)
		if rawtype(e) == 'table' and e[SKIP] then
			return e
		end
		local msg = rawtostring(e)
		if msg:find('stack traceback', 1, true) then
			return msg
		end
		return msg .. '\n' .. debug.traceback('', 2)
	end
	local ok, err = true, nil
	for _, level in ipairs(T.stack) do
		for _, hook in ipairs(level.before) do
			if ok then
				ok, err = xpcall(hook, handler)
			end
		end
	end
	if ok then
		ok, err = xpcall(fn, handler)
	end
	for i = #T.stack, 1, -1 do
		for _, hook in ipairs(T.stack[i].after) do
			local hookOk, hookErr = xpcall(hook, handler)
			if ok and not hookOk then
				ok, err = false, hookErr
			end
		end
	end
	if not ok and rawtype(err) == 'table' and err[SKIP] then
		T.skip = T.skip + 1
		out('@@SKIP ' .. full .. ' | ' .. err.reason)
		return
	end
	if ok and #M.errors > 0 then
		ok = false
		err = 'errors reported through the error handler:\n' .. table.concat(M.errors, '\n')
	end
	if ok then
		T.pass = T.pass + 1
		out('@@PASS ' .. full)
	else
		T.fail = T.fail + 1
		out('@@FAIL ' .. full)
		out(rawtostring(err))
	end
	M.errors = {}
end

function T.Report()
	out(('@@RESULT pass=%d fail=%d skip=%d'):format(T.pass, T.fail, T.skip))
	io.stdout:flush()
end

return T
