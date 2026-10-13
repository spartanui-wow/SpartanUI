-- @runtime lua51
-- Config and Migrate (plan 6.10, 7.1): the schema number is never an AceDB default, new and reset
-- profiles are stamped, old profiles run their patches exactly once, run-once steps keep their
-- own guards, and data newer than this version is left alone. Real AceDB on real Lua 5.1.
local M, H = ...

if not H.ModuleExists() then
	describe('config', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

local function Logged(level, text)
	for _, line in ipairs(H.logs.host or {}) do
		if line:find(level .. ':', 1, true) == 1 and line:find(text, 1, true) then
			return true
		end
	end
	return false
end

describe('config: defaults', function()
	local P = H.FreshCore({ initialize = false })

	it('keeps the schema number out of every default table', function()
		local defaults = P.Config:Defaults()
		assert.is_nil(defaults.profile.schema, 'profile default')
		assert.is_nil(defaults.global.schema, 'global default')
		assert.is_nil(defaults.char.schema, 'char default')
	end)

	it('returns a new table on every call', function()
		local a, b = P.Config:Defaults(), P.Config:Defaults()
		assert.is_false(rawequal(a, b))
		assert.is_false(rawequal(a.profile, b.profile))
		a.profile.size = 'large'
		assert.equal(b.profile.size, 'medium')
		assert.equal(P.Config:Defaults().profile.size, 'medium')
	end)

	it('holds scalars only, and takes host scalars but never host tables', function()
		P.host = { profileDefaults = { followHostProfile = true, list = { 1 } }, globalDefaults = { flag = 1, nested = {} } }
		local defaults = P.Config:Defaults()
		P.host = nil
		assert.is_true(defaults.profile.followHostProfile)
		assert.is_nil(defaults.profile.list)
		assert.equal(defaults.global.flag, 1)
		assert.is_nil(defaults.global.nested)
		for key, value in pairs(defaults.profile) do
			assert.is_false(type(value) == 'table', 'profile default ' .. key .. ' is a table')
		end
	end)
end)

describe('config: schema stamping', function()
	it('stamps a brand-new profile and global data with the current numbers', function()
		local P, _, sv = H.FreshCore()
		assert.equal(rawget(P.db.profile, 'schema'), P.Config.SCHEMA.profile)
		assert.equal(rawget(P.db.global, 'schema'), P.Config.SCHEMA.global)
		M.FireIfKnown('PLAYER_LOGOUT')
		local raw = rawget(_G, sv)
		assert.equal(raw.profiles.Default.schema, P.Config.SCHEMA.profile, 'kept in the SavedVariable after logout')
		assert.equal(raw.global.schema, P.Config.SCHEMA.global)
	end)

	it('stamps a profile made by switching to a new name', function()
		local P = H.FreshCore()
		P.Store:SetProfile('Second')
		assert.equal(rawget(P.db.profile, 'schema'), P.Config.SCHEMA.profile)
	end)

	it('stamps a reset profile, so it never reads as the oldest data', function()
		local P = H.FreshCore()
		P.Store:Set('size', 'large')
		P.db:ResetProfile()
		assert.equal(rawget(P.db.profile, 'schema'), P.Config.SCHEMA.profile)
		assert.equal(P.db.profile.size, 'medium', 'the reset removed the change')
	end)

	it('reads a stored profile with no number as the oldest data and patches it once', function()
		local runs = { profile = 0, global = 0 }
		local saved = {
			profileKeys = {},
			profiles = { Default = { size = 'large' } },
			global = {},
		}
		local P = H.FreshCore({
			saved = saved,
			before = function(P)
				P.Migrate:AddPatch('profile', 1, function(profile)
					runs.profile = runs.profile + 1
					profile.patched = (profile.patched or 0) + 1
				end)
				P.Migrate:AddPatch('global', 1, function()
					runs.global = runs.global + 1
				end)
			end,
		})
		assert.equal(runs.profile, 1, 'profile patch 1 ran')
		assert.equal(runs.global, 1, 'global patch 1 ran')
		assert.equal(P.db.profile.schema, 1)
		assert.equal(P.db.profile.patched, 1)
		P.Migrate:RunProfile()
		P.Migrate:RunGlobal()
		assert.equal(runs.profile, 1, 'a stamped profile never runs the patch again')
		assert.equal(runs.global, 1)
	end)

	it('runs only the new patch when the current number goes up, and new profiles skip it', function()
		local ran = {}
		local saved = {
			profileKeys = {},
			profiles = { Default = { schema = 1, size = 'large' } },
			global = { schema = 1 },
		}
		local P = H.FreshCore({
			saved = saved,
			before = function(P)
				P.Config.SCHEMA.profile = 2
				P.Migrate:AddPatch('profile', 1, function()
					ran[#ran + 1] = 1
				end)
				P.Migrate:AddPatch('profile', 2, function(profile, key)
					ran[#ran + 1] = 2 .. ':' .. key
				end)
			end,
		})
		assert.same(ran, { '2:Default' }, 'only patch 2 ran, once')
		assert.equal(P.db.profile.schema, 2)
		ran = {}
		P.Store:SetProfile('Fresh')
		assert.equal(rawget(P.db.profile, 'schema'), 2, 'a new profile starts at the current number')
		assert.same(ran, {}, 'and runs no old patches')
	end)

	it('stops at a failed patch, logs it, and resumes there next time', function()
		local fail = true
		local P = H.FreshCore({
			saved = { profileKeys = {}, profiles = { Default = { size = 'small' } }, global = {} },
			before = function(P)
				P.Migrate:AddPatch('profile', 1, function()
					if fail then
						error('patch broke')
					end
				end)
			end,
		})
		assert.is_nil(rawget(P.db.profile, 'schema'), 'not stamped after a failure')
		assert.is_true(Logged('error', 'patch broke'), 'the failure is logged')
		fail = false
		P.Migrate:RunProfile()
		assert.equal(P.db.profile.schema, 1)
	end)

	it('leaves data from a newer version alone and warns', function()
		local P = H.FreshCore({
			saved = { profileKeys = {}, profiles = { Default = { schema = 99, size = 'small' } }, global = { schema = 99 } },
		})
		assert.equal(P.db.profile.schema, 99)
		assert.equal(P.db.global.schema, 99)
		assert.equal(P.db.profile.size, 'small')
		assert.is_true(Logged('warning', 'newer'))
	end)
end)

describe('config: run-once steps', function()
	it('runs every step on every profile load, with the profile key and global table', function()
		local calls = {}
		local P = H.FreshCore({
			before = function(P)
				-- The real legacy import uses the same guards; this test checks the guard pattern alone
				P.Migrate.steps.legacyImport = function() end
				P.Migrate:AddStep('importOld', function(profile, key, global)
					calls[#calls + 1] = key
					global.migratedFromOld = global.migratedFromOld or {}
					if profile.migratedFromOld or global.migratedFromOld[key] then
						return
					end
					profile.migratedFromOld = true
					global.migratedFromOld[key] = true
					profile.size = 'large'
				end)
			end,
		})
		assert.same(calls, { 'Default' })
		assert.equal(P.db.profile.size, 'large')
		P.db:ResetProfile()
		assert.same(calls, { 'Default', 'Default' }, 'the step runs again after a reset')
		assert.equal(P.db.profile.size, 'medium', 'its global guard stops a second import into the reset profile')
		P.Store:SetProfile('Other')
		assert.equal(calls[#calls], 'Other')
		assert.equal(P.db.profile.size, 'large', 'a new profile imports once')
	end)

	it('logs a failing step and keeps going', function()
		local second = false
		local P = H.FreshCore({
			before = function(P)
				P.Migrate:AddStep('broken', function()
					error('step broke')
				end)
				P.Migrate:AddStep('after', function()
					second = true
				end)
			end,
		})
		assert.not_nil(P.db)
		assert.is_true(second)
		assert.is_true(Logged('error', 'step broke'))
	end)

	it('refuses two patches with the same number', function()
		local P = H.FreshCore({ initialize = false })
		P.Migrate:AddPatch('profile', 5, function() end)
		assert.errors(function()
			P.Migrate:AddPatch('profile', 5, function() end)
		end, 'already exists')
		assert.errors(function()
			P.Migrate:AddPatch('char', 1, function() end)
		end, 'unknown scope')
	end)
end)

describe('config: one set of plates for every character', function()
	it('drops the per-character choice an earlier version saved', function()
		for _, choice in ipairs({ 'old', 'new' }) do
			local P = H.FreshCore({ saved = { char = { [H.CharacterKey()] = { engine = choice } } } })
			assert.is_nil(rawget(P.db.char, 'engine'), choice .. ' is gone after the load')
		end
		local P = H.FreshCore()
		assert.is_nil(P.Config.GetEngineChoice, 'no switch to read')
		assert.is_nil(P.Config.SetEngineChoice, 'or to change')
		assert.is_nil(P.Config.GetSessionEngine)
	end)

	it('opens one shared profile for every character', function()
		local P = H.FreshCore()
		assert.equal(P.db:GetCurrentProfile(), 'Default')
	end)
end)
