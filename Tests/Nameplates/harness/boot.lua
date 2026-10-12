-- Runs one suite under one flavor. Started by Tests/Nameplates/run.py, either through the LuaLS
-- binary (arguments: root flavor suite [only]) or inside lupa's Lua 5.1 (globals set beforehand).
-- The suite chunk is called with (M, H, T): the mock, the loader and the test API.

HARNESS_ROOT = HARNESS_ROOT or (arg and arg[1])
FLAVOR = FLAVOR or (arg and arg[2]) or 'retail'
SUITE = SUITE or (arg and arg[3])
SUITE_ONLY = SUITE_ONLY or (arg and arg[4] ~= '' and arg[4]) or nil

if not HARNESS_ROOT or not SUITE then
	io.write('@@FAIL boot\nusage: boot.lua <repo root/> <flavor> <suite file> [name filter]\n@@RESULT pass=0 fail=1 skip=0\n')
	return
end
HARNESS_ROOT = HARNESS_ROOT:gsub('\\', '/')
if HARNESS_ROOT:sub(-1) ~= '/' then
	HARNESS_ROOT = HARNESS_ROOT .. '/'
end

local HARNESS = HARNESS_ROOT .. 'Tests/Nameplates/harness/'

local function bootError(stage, err)
	io.write('@@FAIL ' .. stage .. '\n' .. tostring(err) .. '\n@@RESULT pass=0 fail=1 skip=0\n')
end

local okShims, shimErr = pcall(dofile, HARNESS .. 'shims.lua')
if not okShims then
	return bootError('harness shims', shimErr)
end

local okMock, M = xpcall(function()
	return dofile(HARNESS .. 'wowmock.lua')
end, function(e)
	return tostring(e) .. '\n' .. debug.traceback('', 2)
end)
if not okMock then
	return bootError('mock client (' .. FLAVOR .. ')', M)
end

local T = assert(loadfile(HARNESS .. 'testapi.lua'))(M)
T.only = SUITE_ONLY
local H = assert(loadfile(HARNESS .. 'loader.lua'))(M, T)
M.H = H

io.write(('@@INFO flavor=%s runtime=%s client=%s %s\n'):format(FLAVOR, RUNTIME, M.data.meta.version, M.data.meta.build))

local chunk, loadErr = loadfile(SUITE)
if not chunk then
	return bootError('suite load', loadErr)
end
local ok, err = xpcall(chunk, function(e)
	return M.S.rawtostring(e) .. '\n' .. debug.traceback('', 2)
end, M, H, T)
if not ok then
	T.fail = T.fail + 1
	io.write('@@FAIL (suite body)\n' .. M.S.rawtostring(err) .. '\n')
end
T.Report()
