local _, ns = ...
local P = ns.Plates
local L = P.L

-- Sample units for the preview panel, gallery cards and setup cards (5.6). SampleSource reads
-- these and answers every Source method with plain values, so previews run the real parts. Data
-- is lively on purpose: a cast mid-way, health with an absorb, debuffs with timers.
-- Health values are on a 0-100 scale; casts loop every `duration` seconds.

P.Data = P.Data or {}

---@class Plates.SampleCast
---@field kind 'cast'|'channel'|'empower'
---@field name string
---@field icon string|integer
---@field duration number Seconds per loop
---@field notInterruptible? boolean
---@field important? boolean
---@field aimedAtMe? boolean
---@field target? string Name of the unit the spell is aimed at
---@field targetClass? string Class token of that unit

---@class Plates.SampleAura
---@field icon string|integer
---@field duration number
---@field remaining number Frozen time left (cooldown swipes are paused)
---@field stacks? integer
---@field dispel? string 'Magic'|'Curse'|'Disease'|'Poison'
---@field spellId? integer Lets previews follow "Never show" lists and answer aura color rows
---@field mine? boolean false: cast by someone else (a tank debuff in My debuffs)

---@class Plates.Sample
---@field id string
---@field label string Small faint label drawn next to the sample in a scene
---@field name string
---@field facts Plates.Facts
---@field health number
---@field healthMax number
---@field absorb? number
---@field healAbsorb? number
---@field level? integer
---@field raidMarker? integer
---@field threat? integer UnitThreatSituation status 0-3
---@field tankedByOther? boolean Another group tank holds it
---@field quest? boolean
---@field forces? string
---@field title? string NPC title or guild (title text)
---@field faction? string 'Alliance' | 'Horde' (faction mark, players)
---@field pvp? boolean Flagged for PvP (faction mark)
---@field arena? integer Arena opponent number (arena text)
---@field cast? Plates.SampleCast
---@field kickReady? boolean
---@field auras? table<string, Plates.SampleAura[]> Row id -> icons
---@field states? table<string, boolean> target, focus, mouseover

local ICON = {
	shadowBolt = 'Interface\\Icons\\Spell_Shadow_ShadowBolt',
	groundSlam = 'Interface\\Icons\\Ability_Warrior_WarStomp',
	frostbolt = 'Interface\\Icons\\Spell_Frost_FrostBolt02',
	fireball = 'Interface\\Icons\\Spell_Fire_FlameBolt',
	pain = 'Interface\\Icons\\Spell_Shadow_ShadowWordPain',
	corruption = 'Interface\\Icons\\Spell_Shadow_AbominationExplosion',
	polymorph = 'Interface\\Icons\\Spell_Nature_Polymorph',
	shield = 'Interface\\Icons\\Spell_Holy_PowerWordShield',
	sunder = 'Interface\\Icons\\Ability_Warrior_Sunder',
}
P.Data.SampleIcons = ICON

local function Hostile(extra)
	local facts = { reaction = 2, canAttack = true, isPlayer = false, playerControlled = false, isMinion = false, classification = 'normal', effectiveLevel = 62, isCaster = false, tapDenied = false }
	for k, v in pairs(extra or {}) do
		facts[k] = v
	end
	return facts
end

---@type table<string, Plates.Sample>
P.Data.Samples = {
	casterTarget = {
		id = 'casterTarget',
		label = L['Your target'],
		name = L['Shadowguard Caster'],
		facts = Hostile({ classification = 'elite', isCaster = true }),
		health = 72,
		healthMax = 100,
		absorb = 8,
		raidMarker = 8,
		threat = 3,
		kickReady = true,
		cast = { kind = 'cast', name = L['Shadow Bolt'], icon = ICON.shadowBolt, duration = 3, aimedAtMe = true, target = L['You'] },
		auras = {
			myDebuffs = { { icon = ICON.pain, duration = 18, remaining = 12, spellId = 589 }, { icon = ICON.corruption, duration = 14, remaining = 4, spellId = 172 } },
			crowdControl = {},
		},
		states = { target = true },
	},
	eliteMiniBoss = {
		id = 'eliteMiniBoss',
		label = L['Mini-boss'],
		name = L['Bonecrusher Brute'],
		facts = Hostile({ classification = 'elite', isLieutenant = true, effectiveLevel = 63 }),
		health = 45,
		healthMax = 100,
		threat = 2,
		cast = { kind = 'cast', name = L['Ground Slam'], icon = ICON.groundSlam, duration = 2.5, notInterruptible = true, important = true },
	},
	minorGray = {
		id = 'minorGray',
		label = L['Minor enemy'],
		name = L['Skittering Rat'],
		facts = Hostile({ classification = 'minus', effectiveLevel = 60 }),
		health = 100,
		healthMax = 100,
	},
	offTanked = {
		id = 'offTanked',
		label = L['Another tank has it'],
		name = L['Ravenous Ghoul'],
		facts = Hostile(),
		health = 18,
		healthMax = 100,
		threat = 0,
		tankedByOther = true,
	},
	friendlyPlayer = {
		id = 'friendlyPlayer',
		label = L['Friendly player'],
		name = L['Arannis'],
		facts = { reaction = 5, canAttack = false, isPlayer = true, playerControlled = true, classification = 'normal', effectiveLevel = 62, classToken = 'PRIEST' },
		health = 100,
		healthMax = 100,
	},
	enemyPlayer = {
		id = 'enemyPlayer',
		label = L['Enemy player'],
		name = L['Kordath'],
		facts = { reaction = 2, canAttack = true, isPlayer = true, playerControlled = true, classification = 'normal', effectiveLevel = 62, classToken = 'MAGE' },
		health = 64,
		healthMax = 100,
		cast = { kind = 'cast', name = L['Frostbolt'], icon = ICON.frostbolt, duration = 2, aimedAtMe = true, target = L['You'] },
		auras = {
			crowdControl = { { icon = ICON.polymorph, duration = 8, remaining = 5, spellId = 118 } },
			removable = { { icon = ICON.shield, duration = 15, remaining = 9, dispel = 'Magic', spellId = 17 } },
		},
	},
	friendlyNPC = {
		id = 'friendlyNPC',
		label = L['Friendly NPC'],
		name = L['Guard Captain'],
		facts = { reaction = 5, canAttack = false, isPlayer = false, playerControlled = false, classification = 'normal', effectiveLevel = 62 },
		health = 100,
		healthMax = 100,
	},
	boss = {
		id = 'boss',
		label = L['Boss'],
		name = L['The Hollow King'],
		facts = Hostile({ classification = 'worldboss', isBoss = true, effectiveLevel = -1 }),
		health = 88,
		healthMax = 100,
		threat = 3,
		cast = { kind = 'channel', name = L['Shadow Bolt'], icon = ICON.shadowBolt, duration = 4, important = true },
	},
	neutral = {
		id = 'neutral',
		label = L['Neutral'],
		name = L['Wandering Boar'],
		facts = { reaction = 4, canAttack = true, isPlayer = false, classification = 'normal', effectiveLevel = 58 },
		health = 100,
		healthMax = 100,
	},
	lowHealth = {
		id = 'lowHealth',
		label = L['Low health'],
		name = L['Ravenous Ghoul'],
		facts = Hostile(),
		health = 12,
		healthMax = 100,
		threat = 3,
		states = { target = true },
	},
	questMob = {
		id = 'questMob',
		label = L['Quest mob'],
		name = L['Cave Lurker'],
		facts = Hostile({ isQuest = true, questBoss = false }),
		health = 100,
		healthMax = 100,
		quest = true,
	},
	threatSafe = { id = 'threatSafe', label = L['Safe'], name = L['Ravenous Ghoul'], facts = Hostile(), health = 70, healthMax = 100, threat = 3 },
	threatLosing = { id = 'threatLosing', label = L['Losing it'], name = L['Ravenous Ghoul'], facts = Hostile(), health = 70, healthMax = 100, threat = 2 },
	threatLost = { id = 'threatLost', label = L['Lost it'], name = L['Ravenous Ghoul'], facts = Hostile(), health = 70, healthMax = 100, threat = 0 },
	uninterruptible = {
		id = 'uninterruptible',
		label = L['Cannot be interrupted'],
		name = L['Shadowguard Caster'],
		facts = Hostile({ classification = 'elite', isCaster = true }),
		health = 60,
		healthMax = 100,
		cast = { kind = 'cast', name = L['Fireball'], icon = ICON.fireball, duration = 3, notInterruptible = true },
	},
	tankDebuffs = {
		id = 'tankDebuffs',
		label = L['Tank debuffs'],
		name = L['Ravenous Ghoul'],
		facts = Hostile(),
		health = 80,
		healthMax = 100,
		auras = { myDebuffs = { { icon = ICON.sunder, duration = 30, remaining = 22, stacks = 5, spellId = 7386, mine = false } } },
	},
}

---Sample ids in the order the "Pull" scene stacks them (3.2).
P.Data.PULL = { 'casterTarget', 'eliteMiniBoss', 'minorGray', 'offTanked', 'friendlyPlayer' }

---One sample per kind of plate, for the "Kinds" scene and "Preview as".
P.Data.KIND_SAMPLES = {
	enemyNPC = 'casterTarget',
	enemyPlayer = 'enemyPlayer',
	friendlyNPC = 'friendlyNPC',
	friendlyPlayer = 'friendlyPlayer',
	minor = 'minorGray',
}
