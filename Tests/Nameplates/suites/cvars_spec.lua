-- @runtime lua51
-- CVar manager (plan 6.7, contracts 11): probe-driven scope and secure flags, write only when the
-- value differs, first-write-wins backup, restore, the combat queue for secure settings,
-- attribution through the C_CVar hooks, and nameplateMotion never written. Lua 5.1 only: the
-- "same value" check compares number strings ("1" and "1.0").
local M, H = ...

if not H.ModuleExists() then
	describe('cvars', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

local P = H.FreshCore()
local CVars = P.CVars

local changes = {}
P:On('CVAR_CHANGED', function(name, value, by)
	changes[#changes + 1] = { name = name, value = value, by = by }
end, changes)

local function Writes(name)
	local out = {}
	for _, w in ipairs(M.rec.cvarWrites) do
		if not name or w.name == name then
			out[#out + 1] = w
		end
	end
	return out
end

local function Reset()
	if M.lockdown then
		M.LeaveCombat()
	end
	P.util.Wipe(CVars.info)
	P.util.Wipe(CVars.queue)
	P.util.Wipe(CVars.attribution)
	P.db.global.cvarBackup = nil
	P.db.char.cvarBackup = nil
	for i = #changes, 1, -1 do
		changes[i] = nil
	end
	M.ResetRecords()
end

describe('cvars: nameplateMotion', function()
	before_each(Reset)

	it('is never defined', function()
		assert.is_nil(CVars.defs.nameplateMotion)
		for _, name in ipairs(CVars.order) do
			assert.not_equal(name, 'nameplateMotion')
		end
	end)

	it('cannot be defined', function()
		assert.errors(function()
			CVars:Define('nameplateMotion', { kind = 'bool', label = 'x' })
		end, 'must never be written')
		assert.is_nil(CVars.defs.nameplateMotion)
	end)

	it('is refused by Set even when the client has it', function()
		M.SetCVarState('nameplateMotion', { value = '0' })
		assert.equal(CVars:Set('nameplateMotion', 1), 'locked')
		assert.empty(Writes('nameplateMotion'), 'nameplateMotion writes')
		assert.equal(C_CVar.GetCVar('nameplateMotion'), '0')
	end)
end)

describe('cvars: probing', function()
	before_each(Reset)

	it('reads scope, lock and secure flags from the client, never from code', function()
		M.SetCVarState('nameplateMinScale', { value = '1', default = '1', account = true, character = false, secure = false })
		M.SetCVarState('nameplateShowEnemies', { value = '1', character = true, secure = true })
		local scale = CVars:Probe('nameplateMinScale')
		assert.is_true(scale.exists)
		assert.is_true(scale.account)
		assert.is_false(scale.character)
		assert.is_false(scale.secure)
		assert.equal(scale.default, '1')
		local show = CVars:Probe('nameplateShowEnemies')
		assert.is_true(show.character)
		assert.is_true(show.secure)
	end)

	it('reports a missing setting, and Set and Get leave it alone', function()
		M.RemoveCVar('nameplateMotionSpeed')
		assert.is_false(CVars:Exists('nameplateMotionSpeed'))
		assert.is_nil(CVars:Get('nameplateMotionSpeed'))
		assert.equal(CVars:Set('nameplateMotionSpeed', 0.05), 'missing')
		assert.empty(Writes(), 'writes')
	end)

	it('falls back to the older name when the new one is missing', function()
		M.RemoveCVar('nameplateShowFriendlyPlayers')
		M.SetCVarState('nameplateShowFriends', { value = '0' })
		local info = CVars:Probe('nameplateShowFriendlyPlayers')
		assert.is_true(info.exists)
		assert.equal(info.actual, 'nameplateShowFriends')
		assert.equal(CVars:Set('nameplateShowFriendlyPlayers', true), 'set')
		assert.equal(C_CVar.GetCVar('nameplateShowFriends'), '1')
		M.RemoveCVar('nameplateShowFriends')
		M.SetCVarState('nameplateShowFriendlyPlayers', { value = '0' })
	end)

	it('lists the settings for one options page in definition order', function()
		local list = CVars:List('whoAndWhere')
		assert.truthy(#list > 5)
		assert.equal(list[1].def.name, 'nameplateShowEnemies')
		for _, item in ipairs(list) do
			assert.equal(item.def.page, 'whoAndWhere')
			assert.not_nil(item.info)
		end
	end)
end)

describe('cvars: values', function()
	it('turns Lua values into the strings the client stores', function()
		assert.equal(CVars.Normalize(true), '1')
		assert.equal(CVars.Normalize(false), '0')
		assert.equal(CVars.Normalize(3), '3')
		assert.equal(CVars.Normalize(1.0), '1')
		assert.equal(CVars.Normalize(0.8), '0.8')
		assert.equal(CVars.Normalize(0.125), '0.125')
		assert.equal(CVars.Normalize('0.5'), '0.5')
	end)

	it('treats equal numbers as the same value', function()
		assert.is_true(CVars.Same('1', '1.0'))
		assert.is_true(CVars.Same('0.80', '0.8'))
		assert.is_false(CVars.Same('0.8', '0.81'))
		assert.is_true(CVars.Same('abc', 'abc'))
		assert.is_false(CVars.Same(nil, '0'))
	end)
end)

describe('cvars: writing', function()
	before_each(Reset)

	it('writes once, then reports the same value without writing', function()
		M.SetCVarState('nameplateMinScale', { value = '1', account = true })
		assert.equal(CVars:Set('nameplateMinScale', 0.8, 'setup'), 'set')
		assert.equal(#Writes('nameplateMinScale'), 1)
		assert.equal(CVars:Set('nameplateMinScale', 0.8), 'same')
		assert.equal(CVars:Set('nameplateMinScale', '0.80'), 'same')
		assert.equal(#Writes('nameplateMinScale'), 1, 'still one write')
		assert.equal(changes[1].by, 'us')
		assert.equal(CVars:GetAttribution('nameplateMinScale').why, 'setup')
	end)

	it('never writes a value the client already has', function()
		M.SetCVarState('nameplateShowEnemies', { value = '1' })
		assert.equal(CVars:Set('nameplateShowEnemies', true), 'same')
		assert.empty(Writes(), 'writes')
		assert.is_nil(CVars:GetBackup('nameplateShowEnemies'), 'nothing backed up for a value we did not change')
	end)

	it('refuses locked and read-only settings', function()
		M.SetCVarState('nameplateMaxScale', { value = '1', locked = true })
		M.SetCVarState('nameplateSelectedScale', { value = '1', readOnly = true })
		assert.equal(CVars:Set('nameplateMaxScale', 1.2), 'locked')
		assert.equal(CVars:Set('nameplateSelectedScale', 1.2), 'locked')
		assert.empty(Writes(), 'writes')
		M.SetCVarState('nameplateMaxScale', { locked = false })
		M.SetCVarState('nameplateSelectedScale', { readOnly = false })
	end)
end)

describe('cvars: backup and restore', function()
	before_each(Reset)

	it('keeps the first value it changed (first write wins)', function()
		M.SetCVarState('nameplateMinScale', { value = '1', account = true })
		CVars:Set('nameplateMinScale', 0.8)
		CVars:Set('nameplateMinScale', 0.6)
		CVars:Set('nameplateMinScale', 1)
		CVars:Set('nameplateMinScale', 0.7)
		assert.equal(CVars:GetBackup('nameplateMinScale'), '1')
		assert.equal(P.db.global.cvarBackup.nameplateMinScale, '1', 'account settings go in global')
	end)

	it('backs character settings up per character', function()
		M.SetCVarState('nameplateShowEnemies', { value = '1', character = true })
		CVars:Set('nameplateShowEnemies', false)
		assert.equal(P.db.char.cvarBackup.nameplateShowEnemies, '1')
		assert.is_nil(P.db.global.cvarBackup and P.db.global.cvarBackup.nameplateShowEnemies)
	end)

	it('restores the original value and forgets the backup', function()
		M.SetCVarState('nameplateMinScale', { value = '1', account = true })
		CVars:Set('nameplateMinScale', 0.8)
		assert.is_true(CVars:Restore('nameplateMinScale'))
		assert.equal(C_CVar.GetCVar('nameplateMinScale'), '1')
		assert.is_nil(CVars:GetBackup('nameplateMinScale'))
		assert.equal(changes[#changes].by, 'restore')
		assert.equal(CVars:GetAttribution('nameplateMinScale').why, 'restore')
		assert.is_false(CVars:Restore('nameplateMinScale'), 'nothing left to restore')
	end)

	it('does not write when the value already matches the backup', function()
		M.SetCVarState('nameplateMinScale', { value = '1', account = true })
		CVars:Set('nameplateMinScale', 0.8)
		C_CVar.SetCVar('nameplateMinScale', '1')
		M.ResetRecords()
		assert.is_true(CVars:Restore('nameplateMinScale'))
		assert.empty(Writes(), 'writes')
	end)

	it('gives every setting back and removes the empty backup tables', function()
		M.SetCVarState('nameplateMinScale', { value = '1', account = true })
		M.SetCVarState('nameplateMaxScale', { value = '1', account = true })
		M.SetCVarState('nameplateShowEnemies', { value = '1', character = true })
		CVars:Set('nameplateMinScale', 0.8)
		CVars:Set('nameplateMaxScale', 1.4)
		CVars:Set('nameplateShowEnemies', false)
		CVars:RestoreAll()
		assert.equal(C_CVar.GetCVar('nameplateMinScale'), '1')
		assert.equal(C_CVar.GetCVar('nameplateMaxScale'), '1')
		assert.equal(C_CVar.GetCVar('nameplateShowEnemies'), '1')
		assert.is_nil(P.db.global.cvarBackup)
		assert.is_nil(P.db.char.cvarBackup)
	end)

	it('keeps the backup across a profile switch (it is not profile data)', function()
		M.SetCVarState('nameplateMinScale', { value = '1', account = true })
		CVars:Set('nameplateMinScale', 0.8)
		P.Store:SetProfile('Elsewhere')
		assert.equal(CVars:GetBackup('nameplateMinScale'), '1')
		P.Store:SetProfile('Default')
		CVars:RestoreAll()
	end)
end)

describe('cvars: combat queue', function()
	before_each(Reset)

	it('queues secure settings in combat and writes the last value after combat', function()
		M.SetCVarState('nameplateShowEnemies', { value = '1', secure = true, account = true })
		CVars:Enable()
		M.EnterCombat()
		assert.equal(CVars:Set('nameplateShowEnemies', false), 'queued')
		assert.equal(CVars:Set('nameplateShowEnemies', '0'), 'queued')
		assert.empty(Writes(), 'no write in combat')
		assert.empty(M.rec.blocked, 'no blocked call')
		assert.is_nil(CVars:GetBackup('nameplateShowEnemies'), 'no backup until the write happens')
		M.LeaveCombat()
		assert.equal(#Writes('nameplateShowEnemies'), 1)
		assert.equal(C_CVar.GetCVar('nameplateShowEnemies'), '0')
		assert.equal(CVars:GetBackup('nameplateShowEnemies'), '1')
		CVars:Disable()
	end)

	it('drops a queued write when the value goes back to what the client has', function()
		M.SetCVarState('nameplateShowEnemies', { value = '1', secure = true })
		M.EnterCombat()
		assert.equal(CVars:Set('nameplateShowEnemies', false), 'queued')
		assert.equal(CVars:Set('nameplateShowEnemies', true), 'same')
		M.LeaveCombat()
		CVars:FlushQueue()
		assert.empty(Writes(), 'writes')
	end)

	it('writes settings that are not secure right away, even in combat', function()
		M.SetCVarState('nameplateMinScale', { value = '1', secure = false })
		M.EnterCombat()
		assert.equal(CVars:Set('nameplateMinScale', 0.9), 'set')
		assert.equal(#Writes('nameplateMinScale'), 1)
	end)

	it('queues a restore of a secure setting until combat ends', function()
		M.SetCVarState('nameplateShowEnemies', { value = '1', secure = true })
		CVars:Set('nameplateShowEnemies', false)
		M.EnterCombat()
		assert.is_false(CVars:Restore('nameplateShowEnemies'))
		assert.equal(C_CVar.GetCVar('nameplateShowEnemies'), '0', 'not written in combat')
		M.LeaveCombat()
		CVars:FlushQueue()
		assert.equal(C_CVar.GetCVar('nameplateShowEnemies'), '1')
		assert.is_nil(CVars:GetBackup('nameplateShowEnemies'))
	end)

	it('queues bitfield changes too', function()
		M.SetCVarState('nameplateStackingTypes', { value = '0', secure = true })
		M.EnterCombat()
		assert.equal(CVars:SetBit('nameplateStackingTypes', 'enemy', true), 'queued')
		assert.empty(Writes(), 'writes')
		M.LeaveCombat()
		CVars:FlushQueue()
		assert.is_true(CVars:GetBit('nameplateStackingTypes', 'enemy'))
	end)
end)

describe('cvars: bitfields', function()
	before_each(Reset)

	it('sets and reads one bit through SetCVarBitfield, backing the whole value up', function()
		M.SetCVarState('nameplateStackingTypes', { value = '0', account = true })
		assert.is_false(CVars:GetBit('nameplateStackingTypes', 'friendly'))
		assert.equal(CVars:SetBit('nameplateStackingTypes', 'friendly', true), 'set')
		assert.is_true(CVars:GetBit('nameplateStackingTypes', 'friendly'))
		assert.is_false(CVars:GetBit('nameplateStackingTypes', 'enemy'))
		assert.equal(CVars:SetBit('nameplateStackingTypes', 'friendly', true), 'same')
		assert.equal(#Writes('nameplateStackingTypes'), 1)
		assert.equal(Writes('nameplateStackingTypes')[1].via, 'SetCVarBitfield')
		assert.equal(CVars:GetBackup('nameplateStackingTypes'), '0')
	end)

	it('reports unknown bit keys as missing', function()
		M.SetCVarState('nameplateStackingTypes', { value = '0' })
		assert.equal(CVars:SetBit('nameplateStackingTypes', 'sideways', true), 'missing')
	end)
end)

describe('cvars: attribution', function()
	before_each(Reset)

	it('installs the two C_CVar hooks once, on the first enable only', function()
		local fresh = H.FreshCore()
		M.ResetRecords()
		assert.is_false(fresh.CVars.hooked, 'loading and initializing installs nothing')
		fresh.CVars:Enable()
		fresh.CVars:Disable()
		fresh.CVars:Enable()
		local count = 0
		for _, hook in ipairs(M.rec.hooks) do
			local label = tostring(hook.name or hook.label or '')
			if label:find('SetCVar', 1, true) then
				count = count + 1
			end
		end
		assert.equal(count, M.NS.C_CVar.SetCVarBitfield and 2 or 1)
		fresh.CVars:Disable()
	end)

	it('records who changed a setting we own', function()
		M.SetCVarState('nameplateMinScale', { value = '1' })
		CVars:Enable()
		C_CVar.SetCVar('nameplateMinScale', '0.6')
		local who = CVars:GetAttribution('nameplateMinScale')
		assert.equal(who.by, 'other')
		assert.equal(changes[#changes].by, 'other')
		assert.equal(changes[#changes].value, '0.6')
		CVars:Set('nameplateMinScale', 0.7, 'player')
		assert.equal(CVars:GetAttribution('nameplateMinScale').by, 'us', 'our own write is not counted as someone else')
		CVars:Disable()
	end)

	it('counts the global SetCVar wrapper once', function()
		if not SetCVar then
			skip('this client has no SetCVar global')
		end
		M.SetCVarState('nameplateMaxScale', { value = '1' })
		CVars:Enable()
		local before = #changes
		SetCVar('nameplateMaxScale', '1.3')
		assert.equal(#changes - before, 1)
		CVars:Disable()
	end)

	it('ignores settings it does not own and every write while the engine is off', function()
		M.SetCVarState('someOtherSetting', { value = '1' })
		CVars:Enable()
		C_CVar.SetCVar('someOtherSetting', '0')
		assert.is_nil(CVars:GetAttribution('someOtherSetting'))
		CVars:Disable()
		M.SetCVarState('nameplateMinScale', { value = '1' })
		C_CVar.SetCVar('nameplateMinScale', '0.5')
		assert.is_nil(CVars:GetAttribution('nameplateMinScale'), 'no record while off')
		M.RemoveCVar('someOtherSetting')
	end)
end)

describe('cvars: the engine gives settings back', function()
	before_each(Reset)

	it('restores everything when the engine turns off', function()
		M.Login('NameplatesTestHost')
		M.SetCVarState('nameplateMinScale', { value = '1', account = true })
		P:Enable()
		CVars:Set('nameplateMinScale', 0.75)
		P:Disable()
		assert.equal(C_CVar.GetCVar('nameplateMinScale'), '1')
		assert.is_nil(CVars:GetBackup('nameplateMinScale'))
	end)

	it('gives a secure setting back after combat when the engine turns off in combat', function()
		M.Login('NameplatesTestHost')
		M.SetCVarState('nameplateShowEnemies', { value = '1', secure = true, account = true })
		P:Enable()
		assert.equal(CVars:Set('nameplateShowEnemies', false), 'set')
		M.EnterCombat()
		P:Disable()
		assert.equal(C_CVar.GetCVar('nameplateShowEnemies'), '0', 'the game locks it in combat')
		assert.is_true(CVars:HasQueued())
		M.LeaveCombat()
		assert.equal(C_CVar.GetCVar('nameplateShowEnemies'), '1', 'given back when combat ends, with nothing else running')
		assert.is_nil(CVars:GetBackup('nameplateShowEnemies'))
		assert.is_false(CVars:HasQueued())
		assert.equal(P:RegisteredEventCount(), 0, 'the after-combat listener goes away once the queue is empty')
	end)

	it('reports when a restore has to wait for combat to end, with the engine off', function()
		M.SetCVarState('nameplateShowEnemies', { value = '1', secure = true, account = true })
		CVars:Set('nameplateShowEnemies', false)
		M.EnterCombat()
		assert.is_false(CVars:RestoreAll(), 'not done yet')
		M.LeaveCombat()
		assert.equal(C_CVar.GetCVar('nameplateShowEnemies'), '1')
		assert.is_true(CVars:RestoreAll(), 'nothing left to give back')
	end)

	it('drops writes still waiting for combat when the engine turns off', function()
		M.Login('NameplatesTestHost')
		M.SetCVarState('nameplateShowEnemies', { value = '1', secure = true, account = true })
		P:Enable()
		M.EnterCombat()
		assert.equal(CVars:Set('nameplateShowEnemies', false), 'queued')
		P:Disable()
		M.LeaveCombat()
		assert.equal(C_CVar.GetCVar('nameplateShowEnemies'), '1', 'a write the engine never made is not made later')
	end)
end)
