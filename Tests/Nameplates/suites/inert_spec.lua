-- @runtime lua51
-- "Inert when off" (plan section 8, 6.12): loading the core with the engine switched off registers
-- no events, installs no hooksecurefunc, writes no CVars and creates no global frames. Checked
-- through a full login, a pull's worth of time and a few plates appearing, with the engine never
-- enabled. The cases with the SpartanUI host loaded are in inert_host_spec.
local M, H = ...

local function where(rec)
	return (rec.event or rec.name or rec.label or '?') .. ' at ' .. (rec.where or '?')
end

local function describeFrame(rec)
	return (rec.name or '?') .. ' (' .. (rec.kind or '?') .. ') at ' .. (rec.where or '?')
end

local function assertInert(label, snapshot, opts)
	opts = opts or {}
	assert.empty(M.rec.events, label .. ' registered game events', where)
	assert.empty(M.rec.hooks, label .. ' installed hooksecurefunc', where)
	assert.empty(M.rec.cvarWrites, label .. ' wrote CVars', where)
	assert.empty(M.rec.globals, label .. ' created named (global) frames or fonts', describeFrame)
	assert.empty(M.rec.blocked, label .. ' called protected functions', where)
	local tickers = {}
	for _, t in ipairs(M.rec.tickers) do
		if not t.timer.cancelled then
			tickers[#tickers + 1] = t
		end
	end
	assert.empty(tickers, label .. ' left repeating timers running', where)
	assert.empty(M.ActiveOnUpdates(), label .. ' left OnUpdate scripts running')
	if opts.globals then
		local added = {}
		for _, name in ipairs(M.NewGlobals(snapshot)) do
			if not opts.allowGlobals or not opts.allowGlobals[name] then
				added[#added + 1] = name
			end
		end
		assert.empty(added, label .. ' added global names')
	end
end

local function exercise()
	M.Login(M.loadedAddon or 'SpartanUI')
	M.Advance(5)
	local tokens = {}
	for i = 1, 3 do
		tokens[i] = M.ShowPlate({ name = 'Mob ' .. i })
	end
	M.SetTarget(tokens[1])
	M.EnterCombat()
	M.Advance(2)
	M.LeaveCombat()
	for i = 1, 3 do
		M.HidePlate(tokens[i])
	end
	M.Advance(1)
end

describe('inert when off', function()
	if not H.ModuleExists() then
		pending('core only', 'Modules/Nameplates/Load.xml does not exist yet')
		return
	end

	it('core only: loading and initializing does nothing to the game', function()
		H.LoadLibs()
		H.InstallLibATStub()
		M.ResetRecords()
		local snapshot = M.SnapshotGlobals()
		local ns = H.LoadCore({ libs = false })
		local P = ns.Plates
		assert.not_nil(P, 'Core/Namespace.lua sets ns.Plates')
		assertInert('loading the core files', snapshot, { globals = true, allowGlobals = { NameplatesTestDB = true } })
		if P.Initialize then
			P:Initialize(H.HostStub())
			assert.is_false(P.enabled == true, 'P:Initialize must not turn the engine on')
		end
		exercise()
		assertInert('the initialized core', snapshot, { globals = true, allowGlobals = { NameplatesTestDB = true } })
		if P.RegisteredEventCount then
			assert.equal(P:RegisteredEventCount(), 0, 'P:RegisteredEventCount()')
		end
	end)
end)
