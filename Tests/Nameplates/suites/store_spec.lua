-- @runtime lua51
-- Store (plan 5.2, 6.10, contracts 5): sparse reads and writes by path, change messages with
-- refresh reasons, batches, list writes, and the profile switch diff. Runs on real Lua 5.1 against
-- the real AceDB, because "write only when it differs" and the defaults AceDB copies into a live
-- profile are value-sensitive.
local M, H = ...

if not H.ModuleExists() then
	describe('store', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

local function Keys(set)
	local out = {}
	for k in pairs(set or {}) do
		out[#out + 1] = k
	end
	table.sort(out)
	return table.concat(out, ',')
end

---Collect STORE_CHANGED and PROFILE_CHANGED messages.
local function Listen(P)
	local log = { store = {}, profile = {} }
	P:On('STORE_CHANGED', function(reasons, keys, scope)
		log.store[#log.store + 1] = { reasons = reasons, keys = keys, scope = scope }
	end, log)
	P:On('PROFILE_CHANGED', function(reasons)
		log.profile[#log.profile + 1] = { reasons = reasons }
	end, log)
	function log.Clear()
		log.store, log.profile = {}, {}
	end
	return log
end

local P, _, sv = H.FreshCore()
local Store = P.Store
local log = Listen(P)

describe('store: reads and writes by path', function()
	before_each(function()
		log.Clear()
	end)

	it('reads defaults through the live profile and writes nothing for them', function()
		assert.equal(Store:Get('size'), 'medium')
		assert.equal(Store:Get('style'), 'host')
		assert.is_false(Store:Set('size', 'medium'), 'writing the default changes nothing')
		assert.equal(#log.store, 0, 'no change message for a value that did not change')
	end)

	it('accepts dotted paths and key lists, and turns number parts into numbers', function()
		assert.is_true(Store:Set('tweaks.clean.changes.parts.name.font.size', 12))
		assert.equal(Store:Get({ 'tweaks', 'clean', 'changes', 'parts', 'name', 'font', 'size' }), 12)
		assert.is_true(Store:Set('when.2.style', 'mini'))
		assert.equal(P.db.profile.when[2].style, 'mini', 'the 2 in the path is a number key')
		assert.is_nil(P.db.profile.when['2'], 'never a string key')
		Store:Set('when', nil)
		Store:Set('tweaks', nil)
	end)

	it('returns nil for a path through a missing or non-table value', function()
		assert.is_nil(Store:Get('tweaks.nothing.here'))
		Store:Set('size', 'large')
		assert.is_nil(Store:Get('size.more'), 'a string is not walked into')
		Store:Set('size', nil)
	end)

	it('copies tables in, so the caller may keep editing its own', function()
		local order = { 'tapped', 'class' }
		Store:Set('colors.health.order', order)
		order[3] = 'reaction'
		assert.same(Store:Get('colors.health.order'), { 'tapped', 'class' })
		Store:Set('colors', nil)
	end)

	it('writes only when the value differs, comparing tables deeply', function()
		assert.is_true(Store:Set('assign', { minor = 'mini', enemyNPC = 'clean' }))
		log.Clear()
		assert.is_false(Store:Set('assign', { enemyNPC = 'clean', minor = 'mini' }), 'same content, other table')
		assert.equal(#log.store, 0)
		assert.is_true(Store:Set('assign.minor', 'clean'))
		assert.equal(#log.store, 1)
		Store:Set('assign', nil)
	end)

	it('removes the key on nil and prunes empty parents, keeping siblings', function()
		Store:Set('tweaks.clean.changes.parts.name.font.size', 11)
		Store:Set('tweaks.clean.changes.parts.hp.font.size', 9)
		Store:Set('tweaks.clean.changes.parts.name.font.size', nil)
		assert.is_nil(Store:Get('tweaks.clean.changes.parts.name'), 'empty name table pruned')
		assert.equal(Store:Get('tweaks.clean.changes.parts.hp.font.size'), 9, 'sibling kept')
		Store:Set('tweaks.clean.changes.parts.hp.font.size', nil)
		assert.is_nil(rawget(P.db.profile, 'tweaks'), 'every empty parent up to the profile is gone')
	end)

	it('does not create tables when removing a missing key', function()
		log.Clear()
		assert.is_false(Store:Set('tweaks.mini.changes.plate', nil))
		assert.is_nil(rawget(P.db.profile, 'tweaks'))
		assert.equal(#log.store, 0)
	end)

	it('replaces lists whole, never merging by index', function()
		Store:Set('when', { { style = 'a' }, { style = 'b' }, { style = 'c' } })
		Store:Set('when', { { style = 'x' } })
		local when = Store:Get('when')
		assert.equal(#when, 1)
		assert.equal(when[1].style, 'x')
		assert.is_nil(when[2])
		Store:Set('when', nil)
	end)

	it('keeps the profile sparse: only changed keys are stored', function()
		Store:Set('size', 'large')
		Store:Set('assign.minor', 'clean')
		Store:Set('assign.minor', nil)
		local stored = {}
		for k, v in pairs(P.db.profile) do
			if v ~= P.db.defaults.profile[k] then
				stored[#stored + 1] = k
			end
		end
		table.sort(stored)
		assert.same(stored, { 'schema', 'size' })
		Store:Set('size', nil)
	end)

	it('reads global and character scopes', function()
		assert.is_true(Store:Set('capOverrides.containers', false, 'global'))
		assert.equal(Store:Get('capOverrides.containers', 'global'), false)
		assert.equal(P.db.global.capOverrides.containers, false)
		assert.is_true(Store:Set('engine', 'new', 'char'))
		assert.equal(P.db.char.engine, 'new')
		Store:Set('capOverrides', nil, 'global')
		Store:Set('engine', nil, 'char')
	end)
end)

describe('store: change messages', function()
	before_each(function()
		log.Clear()
	end)

	it('fires the reasons listed for the top-level key, the key list and the scope', function()
		Store:Set('scheme', 'class')
		assert.equal(#log.store, 1)
		assert.equal(Keys(log.store[1].reasons), 'colors')
		assert.same(log.store[1].keys, { 'scheme' })
		assert.equal(log.store[1].scope, 'profile')
		log.Clear()
		Store:Set('tweaks.clean.changes.plate.sizes.medium', { 140, 10 })
		assert.equal(Keys(log.store[1].reasons), 'auras,look,size')
		log.Clear()
		Store:Set('modes.friendlyNPC', 'name')
		assert.equal(Keys(log.store[1].reasons), 'assignment')
		Store:Set('scheme', nil)
		Store:Set('tweaks', nil)
		Store:Set('modes', nil)
	end)

	it('fires every reason for the enabled switch', function()
		Store:Set('enabled', false)
		assert.equal(Keys(log.store[1].reasons), 'assignment,auras,colors,cvars,look,size')
		Store:Set('enabled', nil)
	end)

	it('uses look for keys it does not know, and the given reasons when passed', function()
		Store:Set('somethingNew', 1)
		assert.equal(Keys(log.store[1].reasons), 'look')
		log.Clear()
		Store:Set('somethingNew', 2, nil, { colors = true })
		assert.equal(Keys(log.store[1].reasons), 'colors')
		Store:Set('somethingNew', nil)
	end)

	it('uses the global and character tables for their scopes', function()
		Store:Set('styles.u0001', { name = 'Mine', base = { parts = {} } }, 'global')
		assert.equal(Keys(log.store[1].reasons), 'auras,look,size')
		assert.equal(log.store[1].scope, 'global')
		log.Clear()
		Store:Set('cvarBackup.nameplateMinScale', '0.8', 'char')
		assert.equal(Keys(log.store[1].reasons), '')
		assert.equal(log.store[1].scope, 'char')
		Store:Set('styles', nil, 'global')
		Store:Set('cvarBackup', nil, 'char')
	end)

	it('fires one message for a batch with the union of reasons and every key', function()
		Store:Batch(function()
			Store:Set('scheme', 'threat')
			Store:Set('size', 'small')
			Store:Batch(function()
				Store:Set('modes.minor', 'hidden')
			end)
		end)
		assert.equal(#log.store, 1)
		assert.equal(Keys(log.store[1].reasons), 'assignment,colors,look,size')
		assert.equal(#log.store[1].keys, 3)
		log.Clear()
		Store:Batch(function()
			Store:Set('scheme', 'threat')
		end)
		assert.equal(#log.store, 0, 'a batch with no change fires nothing')
		Store:Set('scheme', nil)
		Store:Set('size', nil)
		Store:Set('modes', nil)
	end)

	it('still fires the writes made before an error in a batch, then raises it', function()
		assert.errors(function()
			Store:Batch(function()
				Store:Set('scheme', 'class')
				error('boom')
			end)
		end, 'boom')
		assert.equal(#log.store, 1)
		assert.equal(Keys(log.store[1].reasons), 'colors')
		log.Clear()
		Store:Set('size', 'large')
		assert.equal(#log.store, 1, 'writes after the failed batch fire on their own again')
		Store:Set('scheme', nil)
		Store:Set('size', nil)
	end)
end)

describe('store: profiles', function()
	before_each(function()
		log.Clear()
	end)

	it('fires only the reasons of keys that differ when switching profiles', function()
		Store:Set('size', 'large')
		Store:SetProfile('Second')
		assert.equal(P.db:GetCurrentProfile(), 'Second')
		assert.equal(#log.profile, 1)
		assert.equal(Keys(log.profile[1].reasons), 'look,size', 'size differs, nothing else does')
		local last = log.store[#log.store]
		assert.equal(Keys(last.reasons), 'look,size')
		assert.is_nil(last.keys)
		log.Clear()
		Store:SetProfile('Default')
		assert.equal(Keys(log.profile[1].reasons), 'look,size')
	end)

	it('fires nothing to rebuild when two profiles hold the same values', function()
		Store:Set('size', nil)
		Store:SetProfile('Second')
		Store:Set('size', nil)
		log.Clear()
		Store:SetProfile('Default')
		assert.equal(#log.profile, 1)
		assert.equal(Keys(log.profile[1].reasons), '')
	end)

	it('reads the new profile on every call after a switch', function()
		Store:Set('scheme', 'class')
		Store:SetProfile('Third')
		assert.equal(Store:Get('scheme'), 'auto')
		Store:SetProfile('Default')
		assert.equal(Store:Get('scheme'), 'class')
		Store:Set('scheme', nil)
	end)

	it('fires every reason after a copy and a reset', function()
		P.db:CopyProfile('Second')
		assert.equal(Keys(log.profile[#log.profile].reasons), 'assignment,auras,colors,cvars,look,size')
		log.Clear()
		P.db:ResetProfile()
		assert.equal(Keys(log.profile[#log.profile].reasons), 'assignment,auras,colors,cvars,look,size')
	end)

	it('ignores an empty or unchanged profile name', function()
		local before = P.db:GetCurrentProfile()
		Store:SetProfile('')
		Store:SetProfile(before)
		assert.equal(P.db:GetCurrentProfile(), before)
		assert.equal(#log.profile, 0)
	end)

	it('keeps the SavedVariable sparse after logout', function()
		Store:Set('size', 'small')
		M.FireIfKnown('PLAYER_LOGOUT')
		local raw = rawget(_G, sv).profiles[P.db:GetCurrentProfile()]
		assert.equal(raw.size, 'small')
		assert.is_nil(raw.style, 'defaults are not saved')
		assert.is_nil(raw.enabled, 'defaults are not saved')
		Store:Set('size', nil)
	end)
end)

describe('store: following the host profile', function()
	it('switches to the host profile name when follow is on', function()
		local P2 = H.FreshCore({
			host = {
				profileDefaults = { followHostProfile = true },
				GetHostProfileName = function()
					return 'Raiding'
				end,
			},
		})
		assert.equal(P2.db:GetCurrentProfile(), 'Raiding')
	end)

	it('stays on Default when the host passes no follow default', function()
		local P3 = H.FreshCore({
			host = {
				GetHostProfileName = function()
					return 'Raiding'
				end,
			},
		})
		assert.equal(P3.db:GetCurrentProfile(), 'Default')
		assert.is_nil(P3.db.profile.followHostProfile)
	end)
end)
