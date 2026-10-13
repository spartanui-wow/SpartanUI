-- @runtime lua51
-- Plate add and remove cost (plan 6.5 budget): 40 plates removed and added again 50 times through
-- the Driver's own handlers, once with the style unchanged and once with every add laying the
-- plate out for another style. Reports time and garbage per add (as @@NOTE lines the runner
-- prints) and fails on a leak or on a cost far above the budget. The numbers run in plain Lua 5.1
-- against the mock client, so they include the mock's own work; the in-game numbers come from
-- npbench (6.5).
local M, H = ...

if not H.ModuleExists() then
	describe('bench', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

M.Login('NameplatesTestHost')
local P = H.FreshCore()
P:Enable()
M.Advance(3) -- pre-warm finishes

local Driver = P.Driver
local PLATES, ROUNDS = 40, 50

local tokens, bases, normal, minor = {}, {}, {}, {}
local coldBuilt, coldStart = P.Pool.built, os.clock()
for i = 1, PLATES do
	normal[i] = M.AddUnit({ name = 'Mob ' .. i, canAttack = true, reaction = 2, health = 900 + i, healthMax = 1000 })
	minor[i] = M.AddUnit({ name = 'Rat ' .. i, canAttack = true, reaction = 2, classification = 'minus', health = 50, healthMax = 50 })
	tokens[i], bases[i] = M.ShowPlate(normal[i])
end

local coldMs = (os.clock() - coldStart) * 1000
local coldNew = P.Pool.built - coldBuilt

local function Round(swap)
	for i = 1, PLATES do
		Driver:OnRemoved(tokens[i])
	end
	for i = 1, PLATES do
		if swap then
			M.SetToken(tokens[i], M.tokens[tokens[i]] == normal[i].guid and minor[i] or normal[i])
		end
		-- The add tick: the game lets the plate change its click points
		M.Set(bases[i], 'canHitTest', true)
		Driver:OnAdded(tokens[i])
		M.Set(bases[i], 'canHitTest', false)
	end
end

-- The mock records every call (M.Log, M.Caller: kept per object until the run ends) and every
-- event registration (a few tables each); the game does that in C. Quiet() turns the call records
-- off, and Quiet(true) the registration tables too, so what is left is ours, the parts' and the
-- mock's unit functions'.
local unitFilters = {}

local function Quiet(events)
	local log, caller = M.Log, M.Caller
	M.Log = function() end
	M.Caller = function()
		return nil
	end
	local frames = {}
	for i = 1, events and PLATES or 0 do
		local plate = Driver.byBase[bases[i]]
		local frame = plate and plate.events
		if frame then
			local events = M.Get(frame, 'events')
			frames[#frames + 1] = frame
			M.Override(frame, 'RegisterUnitEvent', function(_, event, unit)
				-- The mock's own filter shape ({ unit1, unit2 }), one table per unit reused, so unit
				-- events still reach only this plate
				local filter = unitFilters[unit]
				if not filter then
					filter = { unit }
					unitFilters[unit] = filter
				end
				events[event] = filter
			end)
			M.Override(frame, 'UnregisterAllEvents', function()
				for event in pairs(events) do
					events[event] = nil
				end
			end)
		end
	end
	return function()
		M.Log, M.Caller = log, caller
		for _, frame in ipairs(frames) do
			M.Override(frame, 'RegisterUnitEvent', nil)
			M.Override(frame, 'UnregisterAllEvents', nil)
		end
	end
end

---Garbage one FULL update of every part on one plate makes (the parts' share of an add).
---@return number kb
local function PartsShare()
	local plate = Driver.byBase[bases[1]]
	local restore = Quiet(true)
	plate:UpdateAll('FULL')
	collectgarbage('collect')
	collectgarbage('stop')
	local before = collectgarbage('count')
	for _ = 1, 100 do
		plate:UpdateAll('FULL')
	end
	local kb = (collectgarbage('count') - before) / 100
	collectgarbage('restart')
	restore()
	return kb
end

local function Forget()
	M.ResetRecords()
	for key in pairs(M.fnLog) do
		M.fnLog[key] = nil
	end
	collectgarbage('collect')
	collectgarbage('collect')
end

---@return number msPerAdd, number kbPerAdd, number retainedKb
local function Measure(swap)
	-- Two rounds first: with swap on, a plate needs both styles once before its reused tables
	-- (event lists, ease records) have the room both styles take
	Round(swap)
	Round(swap)
	-- Memory kept, with the mock's call records off (they keep every call until the run ends)
	local restore = Quiet(false)
	Forget()
	local keptBefore = collectgarbage('count')
	for _ = 1, ROUNDS do
		Round(swap)
	end
	Forget()
	local retained = collectgarbage('count') - keptBefore
	restore()
	-- Time and garbage, with the mock's bookkeeping off
	restore = Quiet(true)
	collectgarbage('collect')
	collectgarbage('stop')
	local before = collectgarbage('count')
	local t0 = os.clock()
	for _ = 1, ROUNDS do
		Round(swap)
	end
	local elapsed = os.clock() - t0
	local garbage = collectgarbage('count') - before
	collectgarbage('restart')
	restore()
	Forget()
	local adds = PLATES * ROUNDS
	return elapsed * 1000 / adds, garbage / adds, retained
end

local function Note(text)
	io.write('@@NOTE ' .. text .. '\n')
end

describe('bench: plate add and remove', function()
	it('records a first 40-plate pull beyond pre-warm and remembers its peak', function()
		Note(('%s first pull x40: %.3f ms, %d new plates beyond %d warm plates'):format(FLAVOR, coldMs, coldNew, coldBuilt))
		assert.equal(coldBuilt + coldNew, PLATES)
		assert.is_true(P.db.global.poolPeak >= PLATES)
	end)

	it('adds 40 plates 50 times with the style unchanged, within budget and without leaking', function()
		local ms, kb, retained = Measure(false)
		local parts = PartsShare()
		Note(
			('%s add+remove, style unchanged: %.3f ms, %.2f KB garbage per plate (%.2f KB of it the parts filling in); %+.1f KB kept after %d adds'):format(
				FLAVOR,
				ms,
				kb,
				parts,
				retained,
				PLATES * ROUNDS
			)
		)
		assert.equal(Driver:CountBound(), PLATES)
		assert.is_true(retained < 48, ('memory kept growing: %.1f KB'):format(retained))
		assert.is_true(ms < 1, ('an add takes %.3f ms in the mock'):format(ms))
	end)

	it('adds 40 plates 50 times with a new style on every add, within budget and without leaking', function()
		local ms, kb, retained = Measure(true)
		Note(('%s add+remove, new style each add: %.3f ms, %.2f KB garbage per plate; %+.1f KB kept after %d adds'):format(FLAVOR, ms, kb, retained, PLATES * ROUNDS))
		assert.equal(Driver:CountBound(), PLATES)
		assert.is_true(retained < 48, ('memory kept growing: %.1f KB'):format(retained))
		assert.is_true(ms < 1.5, ('a re-layout add takes %.3f ms in the mock'):format(ms))
	end)

	it('makes no new event maps when a plate binds again with the same style', function()
		local plate = Driver:GetPlate(bases[1])
		local builds = plate.mapBuilds
		Driver:OnRemoved(tokens[1])
		M.Set(bases[1], 'canHitTest', true)
		Driver:OnAdded(tokens[1])
		M.Set(bases[1], 'canHitTest', false)
		assert.equal(plate.mapBuilds, builds, 'the maps were not rebuilt, only the unit events registered again')
		assert.not_nil(next(M.RegisteredEvents(plate.events)), 'the unit events are registered')
	end)

	-- Garbage made per update and while idle, counted only for functions under Modules/Nameplates:
	-- a call/return hook keeps exclusive counts per function and subtracts its own allocations, so
	-- the mock's dispatch, call records and secret values (C work in the game) are left out.
	local function ModuleGarbage(runs, fn)
		local restore = Quiet(true)
		local stack, depth, overhead, total = {}, 0, 0, 0
		local count, getinfo = collectgarbage, debug.getinfo
		local isModule = setmetatable({}, { __mode = 'k' })
		local function Ours(f)
			local known = isModule[f]
			if known == nil then
				local info = getinfo(f, 'S')
				local src = (info and info.source or ''):gsub('\\', '/')
				known = src:find('Modules/Nameplates/', 1, true) ~= nil
				isModule[f] = known
			end
			return known
		end
		local function Hook(event)
			local c0 = count('count')
			local now = c0 - overhead
			if event == 'call' then
				local info = getinfo(2, 'f')
				depth = depth + 1
				local frame = stack[depth]
				if not frame then
					frame = {}
					stack[depth] = frame
				end
				frame.fn, frame.start, frame.child = info and info.func or false, now, 0
			elseif depth > 0 then
				-- An error caught by pcall unwinds frames without return events: pop up to the
				-- function that is returning ('tail return' has no function, so it pops one)
				local returning = event == 'return' and getinfo(2, 'f')
				returning = returning and returning.func
				local found = not returning
				for d = depth, 1, -1 do
					if stack[d].fn == returning then
						found = true
						break
					end
				end
				local done = false
				while depth > 0 and not done do
					local frame = stack[depth]
					done = not found or frame.fn == returning
					local spent = now - frame.start
					if frame.fn and Ours(frame.fn) then
						total = total + (spent - frame.child)
					end
					depth = depth - 1
					if depth > 0 then
						stack[depth].child = stack[depth].child + spent
					end
				end
			end
			overhead = overhead + (count('count') - c0)
		end
		collectgarbage('collect')
		collectgarbage('stop')
		debug.sethook(Hook, 'cr')
		for i = 1, runs do
			fn(i)
		end
		debug.sethook()
		collectgarbage('restart')
		restore()
		return total / runs
	end

	local function UnitOf(i)
		return M.UnitFor(tokens[i])
	end

	it('makes next to no garbage per update', function()
		for i = 1, 10 do
			M.ApplyAura(UnitOf(i), { spellId = 116, name = 'Frostbolt', isHarmful = true, sourceUnit = 'player', duration = 8 })
		end
		M.SetTarget(UnitOf(1))
		-- Warm up: every plate has cast and faded once, so its own fields and slots exist
		for i = 1, PLATES do
			M.StartCast(UnitOf(i), { name = 'Bolt', spellID = 686, duration = 0.2 })
		end
		M.Advance(1.5)
		local cases = {
			{
				'health x40',
				0.25,
				function(r)
					for i = 1, PLATES do
						UnitOf(i).health = 300 + r
						M.Fire('UNIT_HEALTH', tokens[i])
					end
				end,
			},
			{
				'threat x40',
				0.25,
				function()
					for i = 1, PLATES do
						M.Fire('UNIT_THREAT_LIST_UPDATE', tokens[i])
					end
				end,
			},
			{
				'auras x10',
				0.25,
				function()
					for i = 1, 10 do
						M.Fire('UNIT_AURA', tokens[i], { isFullUpdate = false })
					end
				end,
			},
			{
				'target change',
				1,
				function(r)
					M.SetTarget(UnitOf((r % PLATES) + 1))
				end,
			},
			{
				'cast start and stop x10',
				2,
				function()
					for i = 1, 10 do
						M.StartCast(UnitOf(i), { name = 'Bolt', spellID = 686, duration = 2 })
						M.StopCast(UnitOf(i), 'stop')
					end
				end,
			},
			{
				'fact poll tick',
				0.25,
				function()
					Driver.PollTick()
				end,
			},
		}
		local function RunCases(label)
			for _, case in ipairs(cases) do
				local kb = ModuleGarbage(10, case[3])
				Note(('%s per update%s, %s: %.3f KB made by the module'):format(FLAVOR, label, case[1], kb))
				assert.is_true(kb < case[2], ('%s%s makes %.3f KB'):format(case[1], label, kb))
			end
		end
		RunCases('')
		-- Restricted (secrets everywhere): hidden answers, folded colors, states from hidden answers
		if M.SetRestricted(true) then
			M.Advance(0.5)
			for _, case in ipairs(cases) do
				case[3](0)
			end
			M.Advance(1.5)
			RunCases(' (restricted)')
			M.SetRestricted(false)
			M.Advance(0.5)
		end
		M.SetTarget(nil)
		M.Advance(1)
	end)

	it('makes little garbage of its own per plate add', function()
		local same = ModuleGarbage(5, function()
			Round(false)
		end) / PLATES
		local swapped = ModuleGarbage(5, function()
			Round(true)
		end) / PLATES
		Note(('%s per add, made by the module: %.3f KB with the style unchanged, %.3f KB with a new style'):format(FLAVOR, same, swapped))
		assert.is_true(same < 0.5, ('an add makes %.3f KB'):format(same))
	end)

	it('does no per-frame work while plates show and nothing changes', function()
		M.Advance(2)
		assert.is_nil(next(P.Scheduler.eases), 'no eases run')
		local tasks = {}
		for id in pairs(P.Scheduler.tasks) do
			tasks[#tasks + 1] = id
		end
		table.sort(tasks)
		Note(('%s idle with %d plates: shared tasks %s'):format(FLAVOR, PLATES, table.concat(tasks, ', ')))
		for _, id in ipairs(tasks) do
			assert.is_true(id == 'Driver.poll' or id == 'Pool.prewarm', 'only the fact poller runs: ' .. id)
		end
		local kb = ModuleGarbage(2, function()
			M.Advance(1)
		end)
		Note(('%s idle: %.3f KB per second made by the module'):format(FLAVOR, kb))
		assert.is_true(kb < 0.1, ('idle plates make %.3f KB a second'):format(kb))
	end)

	it('keeps maps through real combat edges and tank-only changes', function()
		local builds = {}
		for i = 1, PLATES do
			builds[i] = Driver.byBase[bases[i]].mapBuilds
		end
		local kb = ModuleGarbage(4, function()
			M.EnterCombat()
			M.LeaveCombat()
			P:Fire('TANKS_CHANGED')
		end)
		for i = 1, PLATES do
			assert.equal(Driver.byBase[bases[i]].mapBuilds, builds[i])
		end
		Note(('%s combat enter+leave and tanks x40: %.3f KB made by module'):format(FLAVOR, kb))
		assert.is_true(kb < 16, 'combat edges stay within a small allocation budget')
	end)

	it('counts unit API calls in grouped target, threat and cast updates', function()
		local calls = { threat = 0, detail = 0, cast = 0 }
		local originals = { UnitThreatSituation, UnitDetailedThreatSituation, UnitCastingInfo }
		local function Wrap(key, fn)
			return function(...)
				calls[key] = calls[key] + 1
				return fn(...)
			end
		end
		rawset(_G, 'UnitThreatSituation', Wrap('threat', originals[1]))
		rawset(_G, 'UnitDetailedThreatSituation', Wrap('detail', originals[2]))
		rawset(_G, 'UnitCastingInfo', Wrap('cast', originals[3]))
		M.group, M.groupSize = 'party', 2
		local tank = M.AddUnit({ role = 'TANK' })
		M.SetToken('party1', tank)
		M.SetPlace({ inInstance = true, instanceType = 'party', difficultyID = 1 })
		M.Fire('GROUP_ROSTER_UPDATE')
		M.Advance(0.2)
		calls.threat, calls.detail = 0, 0
		M.SetTarget(UnitOf(1))
		M.SetTarget(UnitOf(2))
		M.SetFocus(UnitOf(3))
		local targetReads = calls.threat
		calls.threat = 0
		for i = 1, PLATES do
			M.Fire('UNIT_THREAT_LIST_UPDATE', tokens[i])
		end
		M.Advance(0.05)
		local threatReads = calls.threat
		calls.cast = 0
		for i = 1, 10 do
			M.StartCast(UnitOf(i), { name = 'Bolt', spellID = 686, duration = 2 })
		end
		local castReads = calls.cast
		for i = 1, 10 do
			M.StopCast(UnitOf(i), 'stop')
		end
		rawset(_G, 'UnitThreatSituation', originals[1])
		rawset(_G, 'UnitDetailedThreatSituation', originals[2])
		rawset(_G, 'UnitCastingInfo', originals[3])
		M.group, M.groupSize = nil, nil
		M.SetToken('party1', nil)
		M.SetPlace({ inInstance = false, instanceType = 'none', difficultyID = 0 })
		M.Fire('GROUP_ROSTER_UPDATE')
		M.Advance(0.2)
		Note(('%s APIs: target/focus threat=%d, threat x40=%d, details=%d, cast x10=%d'):format(FLAVOR, targetReads, threatReads, calls.detail, castReads))
		assert.is_true(targetReads <= 4, 'target and focus updates only recolor changed plates')
		assert.is_true(threatReads <= PLATES, 'one threat-status read per plate dispatch')
		assert.equal(castReads, 10, 'one cast-info read per cast start')
	end)

	it('counts real foreign aura payloads and quest-log bursts', function()
		local reads, tips = 0, 0
		local realIDs = C_UnitAuras.GetUnitAuraInstanceIDs
		local realTip = C_TooltipInfo and C_TooltipInfo.GetUnit
		C_UnitAuras.GetUnitAuraInstanceIDs = function(...)
			reads = reads + 1
			return realIDs(...)
		end
		if realTip then
			C_TooltipInfo.GetUnit = function(...)
				tips = tips + 1
				return realTip(...)
			end
		end
		for i = 1, PLATES do
			M.ApplyAura(UnitOf(i), { spellId = 589, name = 'Other debuff', isHarmful = true, sourceUnit = 'party1', duration = 8 })
		end
		local before = tips
		for i = 1, 10 do
			M.Fire('QUEST_LOG_UPDATE')
		end
		M.Advance(1)
		C_UnitAuras.GetUnitAuraInstanceIDs = realIDs
		if realTip then
			C_TooltipInfo.GetUnit = realTip
		end
		Note(('%s APIs: foreign aura x40 lists=%d, quest burst tooltips=%d'):format(FLAVOR, reads, tips - before))
		assert.equal(reads, 0, 'foreign non-CC debuffs cannot change either default row')
		assert.is_true(tips - before <= PLATES, 'quest bursts coalesce into one pass')
	end)

	it('stops all per-frame work once the plates are gone', function()
		for i = 1, PLATES do
			M.HidePlate(tokens[i])
		end
		M.Advance(2)
		assert.equal(#M.ActiveOnUpdates(), 0)
	end)
end)
