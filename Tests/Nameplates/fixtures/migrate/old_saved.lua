-- Old nameplate settings in the shapes real SpartanUI saved files hold (plan 7.2 fixtures).
-- Written by hand, with made-up character names, after the shapes found in the saved files of
-- the Anniversary, Mists, Forever, Era and Era PTR clients (2026-10-13):
--   * most old profiles saved nothing but empty element tables, or AceDB '**' wildcard copies
--     stored as data (elements.<name>.text['**'], PvPRoleIndicator['**'], empty position tables);
--   * one Forever profile turned the target highlight off;
--   * Forever has first and last names with no realm, "Unknown" profiles from a new character's
--     first login, and realm-style keys from older builds;
--   * some profiles never finished setup (no SetupWizard.FirstLaunch = false): brand new.
-- Hand-made cases add what the old options could store: a width typed as text, a scale, a name
-- size, cast bar and icon changes, a power bar, aura toggles.
--
-- Returns fixtures[flavor] = { db = <SpartanUIDB>, expect = { [profileKey] = expectation } }.
-- expectation: kind 'import' | 'new' | 'off'; for imports, optional width, height, nameSize (the
-- client default when left out), remove (parts the player turned off), castHeight, power, auras.

local function Wild()
	return {
		['**'] = {
			SetJustifyH = 'CENTER',
			SetJustifyV = 'MIDDLE',
			enabled = false,
			position = { anchor = 'CENTER', x = 0, y = 0 },
			size = 10,
			text = '',
		},
	}
end

-- Every element saved as an empty table (the most common real shape)
local function EmptyElements()
	return {
		elements = {
			Auras = {},
			Castbar = {},
			DispelHighlight = {},
			Name = {},
			Power = {},
			PvPIndicator = {},
			QuestMob = {},
			RaidTargetIndicator = {},
			RareElite = {},
			ThreatIndicator = {},
			XPBar = {},
		},
	}
end

-- Every element carrying the old wildcard defaults as data
local function WildcardElements()
	local elements = {}
	for _, name in ipairs({ 'Auras', 'Castbar', 'ClassIcon', 'ClassPower', 'Health', 'Power', 'PvPIndicator', 'QuestMob', 'RaidTargetIndicator', 'RareElite', 'Runes' }) do
		elements[name] = { text = Wild() }
	end
	elements.Dispel = {}
	elements.PvPRoleIndicator = { ['**'] = { display = true }, position = {}, text = Wild() }
	return { elements = elements }
end

local SET_UP = { SetupWizard = { FirstLaunch = false } }

local function SetUp()
	return { SetupWizard = { FirstLaunch = false } }
end

local function Classic(extra)
	local db = {
		profileKeys = {},
		profiles = {
			['Player1 - Realm'] = SetUp(),
			['Player2 - Realm'] = SetUp(),
			['Player3 - Realm'] = SetUp(),
			['Player4 - Realm'] = SetUp(),
			['Player5 - Realm'] = SetUp(),
			['Player6 - Realm'] = {},
		},
		namespaces = {
			Nameplates = {
				profiles = {
					['Player1 - Realm'] = EmptyElements(),
					['Player2 - Realm'] = WildcardElements(),
					-- Player3 never saved anything for the old plates
					['Player4 - Realm'] = {
						width = '150',
						Scale = 1.2,
						elements = {
							Name = { textSize = 9, position = { relativeTo = 2 } },
							Castbar = { height = 7, Icon = { enabled = true }, text = Wild() },
							Health = { colorReaction = false },
							Background = { enabled = true },
						},
						ShowThreat = true,
					},
					['Player5 - Realm'] = {
						onlyShowPlayer = false,
						showStealableBuffs = true,
						elements = {
							Power = { enabled = true, height = 4 },
							QuestMob = { enabled = false },
							TargetHighlight = { enabled = false },
						},
					},
					['Player6 - Realm'] = EmptyElements(),
				},
			},
		},
	}
	local expect = {
		['Player1 - Realm'] = { kind = 'import' },
		['Player2 - Realm'] = { kind = 'import' },
		['Player3 - Realm'] = { kind = 'import' },
		['Player4 - Realm'] = { kind = 'import', width = 180, scale = 1.2, nameSize = 11, castHeight = 8, castIcon = true },
		['Player5 - Realm'] = { kind = 'import', remove = { 'quest', 'arrows' }, power = true, auras = true },
		['Player6 - Realm'] = { kind = 'new' },
	}
	for key, value in pairs(extra or {}) do
		db.profiles[key] = value.profile
		db.namespaces.Nameplates.profiles[key] = value.settings
		expect[key] = value.expect
	end
	return { db = db, expect = expect }
end

local fixtures = {}

fixtures.era = Classic()
fixtures.tbc = Classic()
fixtures.titan = Classic()
fixtures.mists = Classic()
fixtures.forever = Classic({
	['First1 Last1'] = { profile = SET_UP, settings = { elements = { TargetHighlight = { enabled = false } } }, expect = { kind = 'import', remove = { 'arrows' } } },
	['First2 Last2 - Realm'] = { profile = {}, settings = EmptyElements(), expect = { kind = 'new' } },
	['Unknown - Realm'] = { profile = {}, settings = EmptyElements(), expect = { kind = 'new' } },
	['Unknown'] = { profile = SetUp(), settings = EmptyElements(), expect = { kind = 'import' } },
})

-- Retail never had SpartanUI plates: existing profiles stay off until the player picks a style
fixtures.retail = {
	db = {
		profileKeys = {},
		profiles = { ['Player1 - Realm'] = SetUp(), ['Player2 - Realm'] = SetUp(), ['Player3 - Realm'] = {} },
	},
	expect = {
		['Player1 - Realm'] = { kind = 'off' },
		['Player2 - Realm'] = { kind = 'off' },
		['Player3 - Realm'] = { kind = 'new' },
	},
}
fixtures.ptr = fixtures.retail

return fixtures
