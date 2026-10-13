-- @runtime lua51
-- Migration through the real host (plan 7): the core and the host load like the game over a
-- SpartanUIDB shaped like real saved files (fixtures/migrate/old_saved.lua), then every
-- profile in it is switched to once. Checks 7.2 (effective per-client sizes in Clean's overlay,
-- parts the player turned off, power bar, auras), 7.3 (wildcards and junk dropped, nothing
-- clamped), 7.4 (Retail profiles off, new profiles on, no game settings), and that each profile is
-- imported once and the old saved data is left alone.
local M, H = ...

if not (H.ModuleExists() and H.Exists(H.hostFile)) then
	describe('migrate fixtures', function()
		pending('all', 'the nameplate module or its host does not exist yet')
	end)
	return
end

local fixtures = assert(loadfile(HARNESS_ROOT .. 'Tests/Nameplates/fixtures/migrate/old_saved.lua'))()
local fixture = fixtures[M.flavor] or fixtures.era

local function Copy(value)
	if type(value) ~= 'table' then
		return value
	end
	local out = {}
	for key, item in pairs(value) do
		out[key] = Copy(item)
	end
	return out
end

local before = Copy(fixture.db.namespaces)
rawset(_G, 'SpartanUIDB', fixture.db)
local SUI, ns, module = H.LoadNameplatesLikeTheGame()
local P = ns.Plates
local forever = SUI.IsForever
local DEFAULT_WIDTH = forever and 152 or 128
local DEFAULT_HEIGHT = forever and 10 or 8
local DEFAULT_NAME = forever and 10 or 7

local function Round(value)
	return math.floor(value + 0.5)
end

---Every key path in a table that is a literal '**'.
local function Wildcards(tbl, path, out)
	out = out or {}
	for key, value in pairs(tbl) do
		local here = path .. '.' .. tostring(key)
		if key == '**' then
			out[#out + 1] = here
		end
		if type(value) == 'table' then
			Wildcards(value, here, out)
		end
	end
	return out
end

local keys = {}
for key in pairs(fixture.expect) do
	keys[#keys + 1] = key
end
table.sort(keys)

local imported = {}
local calls = {}

describe('migrate fixtures', function()
	it('logs in without errors', function()
		M.Login('SpartanUI')
		M.Advance(1)
		-- Count the host's answers from here on (the fixture profiles are visited after login)
		local hostImport = P.host.ImportLegacy
		P.host.ImportLegacy = function(key)
			calls[key] = (calls[key] or 0) + 1
			return hostImport(key)
		end
		local errors = {}
		for _, line in ipairs(H.logs.Nameplates or {}) do
			if line:find('^error:') then
				errors[#errors + 1] = line
			end
		end
		assert.empty(errors, 'logged errors')
	end)

	for _, key in ipairs(keys) do
		local expect = fixture.expect[key]
		it('brings over ' .. key .. ' as ' .. expect.kind, function()
			P.Store:SetProfile(key)
			assert.equal(P.db:GetCurrentProfile(), key)
			local profile = P.db.profile
			assert.is_true(profile.migratedFromOld)
			assert.is_true(P.db.global.migratedFromOld[key])
			assert.is_nil(rawget(profile, 'behavior'), 'no game setting changes')
			assert.is_nil(rawget(profile, 'cvars'), 'no game setting changes')
			assert.empty(Wildcards(profile, 'profile'), 'wildcards in the new profile')
			if expect.kind == 'new' then
				assert.equal(profile.style, 'host')
				assert.is_true(profile.enabled)
				assert.is_nil(rawget(profile, 'tweaks'))
				assert.is_nil(P.Migrate:MakeoverState(key))
				return
			end
			if expect.kind == 'off' then
				assert.is_false(profile.enabled)
				assert.is_nil(rawget(profile, 'tweaks'))
				assert.equal(P.Migrate:MakeoverState(key), 'off')
				return
			end
			imported[#imported + 1] = key
			assert.equal(profile.style, 'clean')
			assert.equal(P.Migrate:MakeoverState(key), 'import')
			local overlay = profile.tweaks.clean
			local scale = expect.scale or 1
			assert.same(overlay.changes.plate.sizes.medium, { expect.width or DEFAULT_WIDTH, Round((expect.height or DEFAULT_HEIGHT) * scale) })
			assert.equal(overlay.changes.parts.name.font.size, expect.nameSize or Round(DEFAULT_NAME * scale))
			local removed = {}
			for _, part in ipairs(expect.remove or {}) do
				removed[part] = true
			end
			assert.same(overlay.remove or {}, removed)
			local cast = overlay.changes.parts.cast or {}
			assert.equal(cast.height, expect.castHeight)
			assert.equal(cast.icon, expect.castIcon and 'left' or nil)
			assert.equal(overlay.add and overlay.add.powerBar and true or nil, expect.power)
			if expect.auras then
				assert.is_false(profile.auras.myDebuffs.onlyMine)
				assert.is_true(profile.auras.removable.on)
			else
				assert.is_nil(rawget(profile, 'auras'))
			end
			local base = P.Styles.Registry:Get('clean')
			local _, report = P.Styles.Schema:ValidateOverlay(overlay, base.parts)
			assert.equal(report.dropped, 0, 'dropped')
			assert.equal(report.clamped, 0, 'clamped')
			local resolved = P.Styles.Merge:Resolve('clean', 'enemyNPC', 'medium')
			assert.equal(resolved.width, overlay.changes.plate.sizes.medium[1])
		end)
	end

	it('imports each profile once, and again never after a switch back', function()
		for _, key in ipairs(keys) do
			assert.equal(calls[key], 1, key)
		end
		local first = imported[1] or keys[1]
		P.Store:SetProfile(first)
		local snapshot = Copy(P.db.profile)
		P.Store:SetProfile(keys[#keys] ~= first and keys[#keys] or keys[1])
		P.Store:SetProfile(first)
		P.Migrate:RunProfile()
		assert.equal(calls[first], 1)
		assert.same(P.db.profile, snapshot)
	end)

	it('leaves the old saved settings untouched', function()
		local now = rawget(_G, 'SpartanUIDB').namespaces
		for key, settings in pairs(before and before.Nameplates and before.Nameplates.profiles or {}) do
			assert.same(now.Nameplates.profiles[key], settings, key)
		end
	end)

	it("offers the What's new card for brought-over profiles only", function()
		for _, key in ipairs(keys) do
			P.Store:SetProfile(key)
			local kind = fixture.expect[key].kind
			assert.equal(module.Makeover:Due(), kind == 'import' or kind == 'off', key)
		end
	end)
end)
