-- @runtime lua51
local _, H = ...

if not H.ModuleExists() then
	describe('migrate', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

local forever = WOW_PROJECT_ID == 18
local defaultWidth = forever and 152 or 128
local defaultHeight = forever and 10 or 8
local defaultNameSize = forever and 10 or 7

local function OldDefaults()
	return {
		width = defaultWidth,
		Scale = 1,
		onlyShowPlayer = true,
		showStealableBuffs = false,
		elements = {
			Health = { height = defaultHeight, texture = 'Old Default' },
			Name = { textSize = defaultNameSize },
			Castbar = { enabled = true, height = 5, texture = 'Old Default', Icon = { enabled = false, size = 12 } },
			Power = { enabled = false, height = 3 },
			RaidTargetIndicator = { enabled = true, size = 15 },
			QuestMob = { enabled = true, size = 16 },
			TargetHighlight = { enabled = true },
			PvPRoleIndicator = { enabled = true },
			PvPIndicator = { enabled = false },
		},
	}
end

local function Saved(profile)
	return { profileKeys = {}, profiles = { Default = profile or {} }, global = {} }
end

local function Fresh(importer, saved)
	return H.FreshCore({ host = { ImportLegacy = importer }, saved = saved or Saved() })
end

local function Import(settings)
	local calls = {}
	local P = Fresh(function(key)
		calls[#calls + 1] = key
		return { action = 'import', settings = settings, defaults = OldDefaults() }
	end)
	return P, calls
end

local function Combined()
	return { elements = { Power = { enabled = true, height = 4 } }, onlyShowPlayer = false, showStealableBuffs = true }
end

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

local function HasError(start)
	for i = start + 1, #(H.logs.host or {}) do
		if H.logs.host[i]:find('error:', 1, true) == 1 then
			return true
		end
	end
	return false
end

describe('migrate: legacy import', function()
	it('imports an empty old profile with the client defaults', function()
		local P = Import({})
		local profile = P.db.profile
		assert.equal(profile.style, 'clean')
		assert.same(profile.tweaks.clean.changes.plate.sizes.medium, { defaultWidth, defaultHeight })
		assert.equal(profile.tweaks.clean.changes.parts.name.font.size, defaultNameSize)
		assert.is_true(profile.migratedFromOld)
		assert.is_true(P.db.global.migratedFromOld.Default)
		assert.equal(P.Migrate:MakeoverState(), 'import')
	end)

	it('scales numeric text widths and rounds sizes to whole pixels', function()
		local P = Import({ width = '150', Scale = 1.2 })
		local changes = P.db.profile.tweaks.clean.changes
		local size = changes.plate.sizes.medium
		local nameSize = changes.parts.name.font.size
		assert.same(size, { 180, math.floor(defaultHeight * 1.2 + 0.5) })
		assert.equal(nameSize, math.floor(defaultNameSize * 1.2 + 0.5))
		for _, value in ipairs({ size[1], size[2], nameSize }) do
			assert.equal(math.floor(value), value)
		end
	end)

	it('removes the parts the player turned off', function()
		local P = Import({
			elements = {
				Castbar = { enabled = false },
				RaidTargetIndicator = { enabled = false },
				QuestMob = { enabled = false },
				TargetHighlight = { enabled = false },
			},
		})
		assert.same(P.db.profile.tweaks.clean.remove, { cast = true, marker = true, quest = true, arrows = true })
	end)

	it('keeps only changed cast heights and health textures', function()
		local changed = Import({ elements = { Castbar = { height = 9 }, Health = { texture = 'Custom Bar' } } })
		assert.equal(changed.db.profile.tweaks.clean.changes.parts.cast.height, 9)
		assert.equal(changed.db.profile.tweaks.clean.changes.parts.health.texture, 'Custom Bar')
		local unchanged = Import({ elements = { Castbar = { height = 5 }, Health = { texture = 'Old Default' } } })
		local parts = unchanged.db.profile.tweaks.clean.changes.parts
		assert.is_nil(parts.cast and parts.cast.height)
		assert.is_nil(parts.health)
	end)

	it('adds a power bar and anchors the cast bar below it', function()
		local P = Import({ elements = { Power = { enabled = true, height = 4 } } })
		local overlay = P.db.profile.tweaks.clean
		assert.not_nil(overlay.add.powerBar)
		assert.equal(overlay.add.powerBar.kind, 'bar')
		assert.equal(overlay.add.powerBar.source, 'power')
		assert.equal(overlay.add.powerBar.height, 4)
		assert.equal(overlay.changes.parts.cast.anchor[2], 'powerBar')
	end)

	it('imports debuff ownership and stealable buff visibility', function()
		local P = Import({ onlyShowPlayer = false, showStealableBuffs = true })
		assert.is_false(P.db.profile.auras.myDebuffs.onlyMine)
		assert.is_true(P.db.profile.auras.removable.on)
		assert.equal(P.db.profile.tweaks.clean.add.removable.row, 'removable')
	end)

	it('remembers the class icon above player plates when it was on, for the parts that show a class', function()
		local off = Import({ elements = { ClassIcon = { enabled = false } } })
		assert.is_nil(off.db.profile.legacy.classIcon, 'off stays off')
		local untouched = Import({})
		assert.is_nil(untouched.db.profile.legacy.classIcon, 'never set up, never remembered')
		local on = Import({ elements = { ClassIcon = { enabled = true, size = 24 } } })
		assert.is_true(on.db.profile.legacy.classIcon)
		assert.is_true(on.db.profile.legacy.healerMarks, 'the other remembered flags stay')
		assert.same(on.db.profile.tweaks.clean, off.db.profile.tweaks.clean, 'it changes no part of the style')
		local _, _, flags = on.Migrate.LegacyOverlay({ elements = { ClassIcon = { enabled = true } } }, OldDefaults())
		assert.is_true(flags.classIcon)
	end)

	it('keeps the remembered flags out of share strings', function()
		local P = Import({ elements = { ClassIcon = { enabled = true } } })
		local kept = false
		for _, key in ipairs(P.Exchange.PROFILE_KEYS_KEPT_OUT) do
			kept = kept or key == 'legacy'
		end
		assert.is_true(kept)
	end)

	it('ignores wildcards and unrelated or malformed old keys', function()
		local start = #(H.logs.host or {})
		local P
		assert.no_errors(function()
			P = Import({
				elements = { ['**'] = { enabled = true }, Runes = { text = { ['**'] = { size = 3 } } }, Name = { position = { relativeTo = 7 } } },
				ShowThreat = true,
				Background = { enabled = true },
			})
		end)
		assert.is_false(HasError(start))
		local overlay = P.db.profile.tweaks.clean
		local baseline = Import({})
		assert.same(overlay, baseline.db.profile.tweaks.clean)
		assert.same(overlay.changes.plate.sizes.medium, { defaultWidth, defaultHeight })
	end)

	it('validates combined power and aura changes without dropping or clamping', function()
		local P = Import(Combined())
		local base = P.Styles.Registry:Get('clean')
		local overlay = P.db.profile.tweaks.clean
		local cleaned, report = P.Styles.Schema:ValidateOverlay(overlay, base.parts)
		assert.not_nil(cleaned)
		assert.equal(report.dropped, 0)
		assert.equal(report.clamped, 0)
		assert.same(cleaned, overlay)
		local raw = P.Migrate.LegacyOverlay(Combined(), OldDefaults())
		local _, rawReport = P.Styles.Schema:ValidateOverlay(raw, base.parts)
		assert.equal(rawReport.dropped, 0)
		assert.equal(rawReport.clamped, 0)
	end)

	it('resolves the migrated medium width and health height', function()
		local P = Import({ width = '150', Scale = 1.2 })
		local medium = P.db.profile.tweaks.clean.changes.plate.sizes.medium
		local resolved = P.Styles.Merge:Resolve('clean', 'enemyNPC', 'medium')
		assert.equal(resolved.width, medium[1])
		assert.equal(resolved.height, medium[2])
	end)

	it('leaves tweaks unchanged when migration runs again', function()
		local P, calls = Import(Combined())
		local before = Copy(P.db.profile.tweaks)
		P.Migrate:RunProfile()
		assert.same(P.db.profile.tweaks, before)
		assert.same(calls, { 'Default' })
	end)

	it('never reimports a reset profile', function()
		local P, calls = Import({})
		assert.same(calls, { 'Default' })
		P.db:ResetProfile()
		assert.equal(P.db.profile.style, 'host')
		assert.is_nil(P.db.profile.tweaks)
		assert.same(calls, { 'Default' })
		assert.is_true(P.db.profile.migratedFromOld)
		assert.is_true(P.db.global.migratedFromOld.Default)
	end)

	it('marks a brand-new profile without changing its settings or asking for a makeover', function()
		local P = Fresh(function()
			return nil
		end)
		assert.equal(P.db.profile.style, 'host')
		assert.is_nil(P.db.profile.tweaks)
		assert.is_true(P.db.profile.migratedFromOld)
		assert.is_nil(P.Migrate:MakeoverState())
	end)

	it('keeps an off profile disabled and finishes its makeover', function()
		local P = Fresh(function()
			return { action = 'off' }
		end)
		assert.is_false(P.db.profile.enabled)
		assert.equal(P.Migrate:MakeoverState(), 'off')
		P.Migrate:FinishMakeover()
		assert.equal(P.Migrate:MakeoverState(), 'done')
	end)

	it('treats an answer it does not know as nothing to bring over', function()
		local P = Fresh(function()
			return { action = 'later' }
		end)
		assert.is_true(P.db.profile.migratedFromOld)
		assert.equal(P.db.profile.style, 'host')
		assert.is_true(P.db.profile.enabled)
		assert.is_nil(P.db.profile.tweaks)
		assert.is_nil(P.Migrate:MakeoverState())
	end)

	it('preserves profiles that already have their own settings', function()
		local saved = Saved({
			style = 'mini',
			tweaks = { clean = { schema = 1, baseVersion = 1, changes = { plate = { sizes = { medium = { 99, 9 } } } } } },
		})
		local before = Copy(saved.profiles.Default.tweaks)
		local P = Fresh(function()
			return { action = 'import', settings = { width = 200 }, defaults = OldDefaults() }
		end, saved)
		assert.is_true(P.Migrate.HasPlayerSettings(P.db.profile))
		assert.equal(P.db.profile.style, 'mini')
		assert.same(P.db.profile.tweaks.clean.changes.plate.sizes.medium, { 99, 9 })
		assert.same(P.db.profile.tweaks, before)
		assert.is_nil(P.Migrate:MakeoverState())
		assert.is_true(P.db.profile.migratedFromOld)
	end)

	it('logs a failed import without marking it and retries successfully', function()
		local calls = 0
		-- Every core gets a new host logger, so the log starts empty here
		local start = 0
		local P = Fresh(function()
			calls = calls + 1
			if calls == 1 then
				error('legacy read failed')
			end
			return { action = 'import', settings = {}, defaults = OldDefaults() }
		end)
		assert.equal(calls, 1)
		assert.is_nil(P.db.profile.migratedFromOld)
		assert.is_nil(P.db.global.migratedFromOld and P.db.global.migratedFromOld.Default)
		assert.is_true(HasError(start))
		P.Migrate:RunProfile()
		assert.equal(calls, 2)
		assert.equal(P.db.profile.style, 'clean')
		assert.same(P.db.profile.tweaks.clean.changes.plate.sizes.medium, { defaultWidth, defaultHeight })
		assert.is_true(P.db.profile.migratedFromOld)
		assert.equal(P.Migrate:MakeoverState(), 'import')
	end)

	it('imports each profile once when switching profiles', function()
		local P, calls = Import({})
		assert.same(calls, { 'Default' })
		P.Store:SetProfile('Other')
		assert.same(calls, { 'Default', 'Other' })
		assert.equal(P.db.profile.style, 'clean')
		assert.same(P.db.profile.tweaks.clean.changes.plate.sizes.medium, { defaultWidth, defaultHeight })
		assert.is_true(P.db.global.migratedFromOld.Other)
		P.Store:SetProfile('Default')
		assert.same(calls, { 'Default', 'Other' })
		assert.equal(P.db.profile.style, 'clean')
	end)

	it('imports nil settings safely using the old defaults', function()
		local start = #(H.logs.host or {})
		local P
		assert.no_errors(function()
			P = Import(nil)
		end)
		assert.is_false(HasError(start))
		assert.equal(P.db.profile.style, 'clean')
		assert.same(P.db.profile.tweaks.clean.changes.plate.sizes.medium, { defaultWidth, defaultHeight })
		assert.equal(P.db.profile.tweaks.clean.changes.parts.name.font.size, defaultNameSize)
		assert.is_true(P.db.profile.migratedFromOld)
	end)

	it('falls back to the registered clean medium size in the pure overlay builder', function()
		local P = Fresh(function()
			return nil
		end)
		local before = Copy(P.db.profile)
		local base = P.Styles.Registry:Get('clean')
		local overlay = P.Migrate.LegacyOverlay(nil, nil)
		assert.same(overlay.changes.plate.sizes.medium, base.plate.sizes.medium)
		assert.same(P.db.profile, before)
	end)
end)
