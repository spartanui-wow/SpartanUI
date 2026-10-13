local _, ns = ...
local P = ns.Plates

-- Crowd control by spell id (4, 6.6): the backstop for the crowd control row on the Lua scan path
-- (Engine/Parts/AurasScan.lua, Classic family and every preview). CROWD_CONTROL is in every
-- client's filter table and the scan passes it where the client takes it, but a list catches what
-- the token misses (S0). Containers (Retail, Forever) use the token only; the scan predicate in
-- AurasContainer reads this list too.
--
-- Each entry: { kind, first tier, last tier, spell ids... }, every rank. Kinds: stun, incapacitate
-- (breaks on damage), disorient, fear, horror, sleep, charm, banish, root, silence, disarm. Tiers
-- follow the client's content: era (Classic Era, and Forever, which runs Classic content), tbc
-- (TBC Anniversary), wrath (Titan), mists (Mists). The ids are the auras the game puts on the
-- target, which is not always the spell that was cast (Freezing Trap's aura is "Freezing Trap
-- Effect"). Snares (slows) are left out: they do not take control away.
--
-- Verified 2026-10-12 against Wowhead's per-client spell databases (classic, tbc, wotlk,
-- mop-classic): every id below exists in each tier it is listed for, carries an aura, and has the
-- name in its comment. Two procs show no aura text there but say "Stuns the target" (Mace Stun
-- Effect 5530, Starfire Stun 16922). Titan reads the Wrath ids; no Titan database exists to check.

P.Data = P.Data or {}

---Tier order and the tier each client's content belongs to (Retail has none: its rows run on
---aura containers and spell ids there are often hidden).
P.Data.TIERS = { era = 1, tbc = 2, wrath = 3, mists = 4 }
P.Data.CLIENT_TIERS = { era = 'era', forever = 'era', tbc = 'tbc', titan = 'wrath', mists = 'mists' }

---Spell ids that apply on a client, from tiered entries { kind, first, last, ids... }.
---@param sources table[]
---@param client string Caps:Client() name
---@return table<integer, string> ids { [spellID] = kind }
function P.Data.BuildTiered(sources, client)
	local out = {}
	local tier = P.Data.TIERS[P.Data.CLIENT_TIERS[client] or '']
	if not tier then
		return out
	end
	for _, entry in ipairs(sources) do
		local first, last = P.Data.TIERS[entry[2]], P.Data.TIERS[entry[3]]
		if first and last and tier >= first and tier <= last then
			for i = 4, #entry do
				out[entry[i]] = entry[1]
			end
		end
	end
	return out
end

-- stylua: ignore start
---@type table[]
P.Data.CROWD_CONTROL_SOURCES = {
	-- Mage
	{ 'incapacitate', 'era', 'wrath', 118, 12824, 12825, 12826 }, -- Polymorph
	{ 'incapacitate', 'mists', 'mists', 118 }, -- Polymorph
	{ 'incapacitate', 'era', 'mists', 28271 }, -- Polymorph: Turtle / Polymorph
	{ 'incapacitate', 'era', 'mists', 28272 }, -- Polymorph: Pig / Polymorph
	{ 'incapacitate', 'wrath', 'mists', 61305, 61721, 61780 }, -- Polymorph: Black Cat / Polymorph: Rabbit / Polymorph: Turkey / Polymorph
	{ 'root', 'era', 'wrath', 122, 865, 6131, 10230 }, -- Frost Nova
	{ 'root', 'mists', 'mists', 122 }, -- Frost Nova
	{ 'root', 'tbc', 'wrath', 27088 }, -- Frost Nova
	{ 'root', 'wrath', 'wrath', 42917 }, -- Frost Nova
	{ 'root', 'era', 'wrath', 12494 }, -- Frostbite
	{ 'root', 'tbc', 'mists', 33395 }, -- Freeze
	{ 'stun', 'era', 'wrath', 12355 }, -- Impact
	{ 'silence', 'era', 'wrath', 18469 }, -- Counterspell - Silenced / Silenced - Improved Counterspell
	{ 'silence', 'wrath', 'wrath', 55021 }, -- Silenced - Improved Counterspell
	{ 'disorient', 'tbc', 'mists', 31661 }, -- Dragon's Breath
	{ 'disorient', 'tbc', 'wrath', 33041, 33042, 33043 }, -- Dragon's Breath
	{ 'disorient', 'wrath', 'wrath', 42949, 42950 }, -- Dragon's Breath
	{ 'stun', 'wrath', 'mists', 44572 }, -- Deep Freeze
	{ 'incapacitate', 'mists', 'mists', 82691 }, -- Ring of Frost
	{ 'root', 'mists', 'mists', 102051 }, -- Frostjaw
	{ 'root', 'wrath', 'wrath', 55080 }, -- Shattered Barrier
	{ 'root', 'mists', 'mists', 111340 }, -- Ice Ward
	-- Rogue
	{ 'incapacitate', 'era', 'wrath', 6770, 2070, 11297 }, -- Sap
	{ 'incapacitate', 'mists', 'mists', 6770 }, -- Sap
	{ 'incapacitate', 'wrath', 'wrath', 51724 }, -- Sap
	{ 'incapacitate', 'era', 'mists', 1776 }, -- Gouge
	{ 'incapacitate', 'era', 'tbc', 1777, 8629, 11285, 11286 }, -- Gouge
	{ 'incapacitate', 'tbc', 'tbc', 38764 }, -- Gouge
	{ 'disorient', 'era', 'mists', 2094 }, -- Blind
	{ 'stun', 'era', 'mists', 408 }, -- Kidney Shot
	{ 'stun', 'era', 'wrath', 8643 }, -- Kidney Shot
	{ 'stun', 'era', 'mists', 1833 }, -- Cheap Shot
	{ 'silence', 'era', 'wrath', 18425 }, -- Kick - Silenced / Silenced - Improved Kick
	{ 'disarm', 'era', 'wrath', 14251 }, -- Riposte
	{ 'silence', 'tbc', 'mists', 1330 }, -- Garrote - Silence
	{ 'disarm', 'wrath', 'mists', 51722 }, -- Dismantle
	-- Warrior
	{ 'stun', 'era', 'mists', 7922 }, -- Charge Stun
	{ 'stun', 'era', 'wrath', 20253 }, -- Intercept Stun / Intercept
	{ 'stun', 'era', 'tbc', 20614, 20615 }, -- Intercept Stun
	{ 'stun', 'tbc', 'tbc', 25273, 25274 }, -- Intercept Stun
	{ 'fear', 'era', 'mists', 5246 }, -- Intimidating Shout
	{ 'fear', 'era', 'mists', 20511 }, -- Intimidating Shout
	{ 'stun', 'era', 'wrath', 12809 }, -- Concussion Blow
	{ 'stun', 'era', 'tbc', 5530 }, -- Mace Stun Effect
	{ 'stun', 'era', 'wrath', 12798 }, -- Revenge Stun
	{ 'silence', 'era', 'wrath', 18498 }, -- Shield Bash - Silenced / Silenced - Gag Order
	{ 'root', 'era', 'wrath', 23694 }, -- Improved Hamstring
	{ 'disarm', 'era', 'mists', 676 }, -- Disarm
	{ 'stun', 'wrath', 'wrath', 46968 }, -- Shockwave
	{ 'stun', 'mists', 'mists', 132168 }, -- Shockwave
	{ 'stun', 'mists', 'mists', 132169 }, -- Storm Bolt
	{ 'root', 'mists', 'mists', 107566 }, -- Staggering Shout
	{ 'root', 'mists', 'mists', 105771 }, -- Warbringer / Charge
	-- Priest
	{ 'fear', 'era', 'wrath', 8122, 8124, 10888, 10890 }, -- Psychic Scream
	{ 'fear', 'mists', 'mists', 8122 }, -- Psychic Scream
	{ 'charm', 'era', 'mists', 605 }, -- Mind Control / Dominate Mind
	{ 'charm', 'era', 'tbc', 10911, 10912 }, -- Mind Control
	{ 'incapacitate', 'era', 'wrath', 9484, 9485, 10955 }, -- Shackle Undead
	{ 'incapacitate', 'mists', 'mists', 9484 }, -- Shackle Undead
	{ 'silence', 'era', 'mists', 15487 }, -- Silence
	{ 'stun', 'era', 'tbc', 15269 }, -- Blackout
	{ 'horror', 'wrath', 'mists', 64044 }, -- Psychic Horror
	{ 'disarm', 'wrath', 'wrath', 64058 }, -- Psychic Horror
	{ 'incapacitate', 'mists', 'mists', 88625 }, -- Holy Word: Chastise
	{ 'root', 'mists', 'mists', 114404 }, -- Void Tendril's Grasp
	{ 'fear', 'mists', 'mists', 113792 }, -- Psychic Terror
	-- Warlock
	{ 'fear', 'era', 'wrath', 5782, 6213, 6215 }, -- Fear
	{ 'fear', 'mists', 'mists', 118699 }, -- Fear
	{ 'fear', 'era', 'mists', 5484 }, -- Howl of Terror
	{ 'fear', 'era', 'wrath', 17928 }, -- Howl of Terror
	{ 'horror', 'era', 'wrath', 6789, 17925, 17926 }, -- Death Coil
	{ 'horror', 'tbc', 'wrath', 27223 }, -- Death Coil
	{ 'horror', 'wrath', 'wrath', 47859, 47860 }, -- Death Coil
	{ 'horror', 'mists', 'mists', 6789 }, -- Mortal Coil
	{ 'charm', 'era', 'mists', 6358 }, -- Seduction
	{ 'banish', 'era', 'mists', 710 }, -- Banish
	{ 'banish', 'era', 'wrath', 18647 }, -- Banish
	{ 'silence', 'era', 'mists', 24259 }, -- Spell Lock
	{ 'stun', 'era', 'mists', 22703 }, -- Inferno Effect / Infernal Awakening
	{ 'stun', 'era', 'wrath', 18093 }, -- Pyroclasm
	{ 'charm', 'era', 'wrath', 1098, 11725, 11726 }, -- Enslave Demon / Subjugate Demon
	{ 'charm', 'wrath', 'wrath', 61191 }, -- Enslave Demon / Subjugate Demon
	{ 'stun', 'tbc', 'mists', 30283 }, -- Shadowfury
	{ 'stun', 'tbc', 'wrath', 30413, 30414 }, -- Shadowfury
	{ 'stun', 'wrath', 'wrath', 47846, 47847 }, -- Shadowfury
	{ 'stun', 'mists', 'mists', 89766 }, -- Axe Toss
	{ 'horror', 'mists', 'mists', 137143 }, -- Blood Horror
	{ 'stun', 'tbc', 'wrath', 30153, 30195, 30197 }, -- Intercept Stun / Intercept
	{ 'stun', 'wrath', 'wrath', 47995 }, -- Intercept Stun / Intercept
	-- Druid
	{ 'root', 'era', 'wrath', 339, 1062, 5195, 5196, 9852, 9853 }, -- Entangling Roots
	{ 'root', 'mists', 'mists', 339 }, -- Entangling Roots
	{ 'root', 'tbc', 'wrath', 26989 }, -- Entangling Roots
	{ 'root', 'wrath', 'wrath', 53308 }, -- Entangling Roots
	{ 'root', 'era', 'wrath', 19970, 19971, 19972, 19973, 19974, 19975 }, -- Entangling Roots
	{ 'root', 'tbc', 'wrath', 27010 }, -- Entangling Roots
	{ 'root', 'wrath', 'wrath', 53313 }, -- Entangling Roots
	{ 'sleep', 'era', 'wrath', 2637, 18657, 18658 }, -- Hibernate
	{ 'sleep', 'mists', 'mists', 2637 }, -- Hibernate
	{ 'stun', 'era', 'wrath', 5211, 6798, 8983 }, -- Bash
	{ 'stun', 'mists', 'mists', 5211 }, -- Mighty Bash
	{ 'stun', 'era', 'mists', 9005 }, -- Pounce
	{ 'stun', 'era', 'wrath', 9823, 9827 }, -- Pounce
	{ 'stun', 'tbc', 'wrath', 27006 }, -- Pounce
	{ 'stun', 'wrath', 'wrath', 49803 }, -- Pounce
	{ 'root', 'era', 'era', 19675 }, -- Feral Charge Effect
	{ 'root', 'tbc', 'mists', 45334 }, -- Feral Charge Effect / Immobilized
	{ 'stun', 'era', 'wrath', 16922 }, -- Starfire Stun
	{ 'stun', 'tbc', 'mists', 22570 }, -- Maim
	{ 'stun', 'wrath', 'wrath', 49802 }, -- Maim
	{ 'disorient', 'tbc', 'mists', 33786 }, -- Cyclone
	{ 'root', 'mists', 'mists', 102359 }, -- Mass Entanglement
	{ 'incapacitate', 'mists', 'mists', 99 }, -- Disorienting Roar
	{ 'silence', 'mists', 'mists', 81261 }, -- Solar Beam
	-- Hunter
	{ 'incapacitate', 'era', 'wrath', 3355, 14308, 14309 }, -- Freezing Trap Effect / Freezing Trap
	{ 'incapacitate', 'mists', 'mists', 3355 }, -- Freezing Trap
	{ 'incapacitate', 'wrath', 'wrath', 60210 }, -- Freezing Arrow Effect
	{ 'fear', 'era', 'wrath', 1513, 14326, 14327 }, -- Scare Beast
	{ 'fear', 'mists', 'mists', 1513 }, -- Scare Beast
	{ 'disorient', 'era', 'mists', 19503 }, -- Scatter Shot
	{ 'sleep', 'era', 'wrath', 19386, 24132, 24133 }, -- Wyvern Sting
	{ 'sleep', 'mists', 'mists', 19386 }, -- Wyvern Sting
	{ 'sleep', 'tbc', 'wrath', 27068 }, -- Wyvern Sting
	{ 'sleep', 'wrath', 'wrath', 49011, 49012 }, -- Wyvern Sting
	{ 'stun', 'era', 'mists', 24394 }, -- Intimidation
	{ 'stun', 'era', 'tbc', 19410 }, -- Improved Concussive Shot
	{ 'root', 'era', 'wrath', 19185 }, -- Entrapment
	{ 'root', 'wrath', 'wrath', 64803, 64804 }, -- Entrapment
	{ 'root', 'era', 'wrath', 19306, 20909, 20910 }, -- Counterattack
	{ 'root', 'tbc', 'wrath', 27067 }, -- Counterattack
	{ 'root', 'wrath', 'wrath', 48998, 48999 }, -- Counterattack
	{ 'root', 'era', 'tbc', 19229 }, -- Improved Wing Clip
	{ 'silence', 'tbc', 'mists', 34490 }, -- Silencing Shot
	{ 'disarm', 'wrath', 'wrath', 53359 }, -- Chimera Shot - Scorpid
	{ 'stun', 'mists', 'mists', 117526 }, -- Binding Shot
	{ 'root', 'mists', 'mists', 135373 }, -- Entrapment
	{ 'stun', 'wrath', 'wrath', 50519 }, -- Sonic Blast
	{ 'root', 'wrath', 'wrath', 50245 }, -- Pin
	{ 'root', 'wrath', 'wrath', 54706 }, -- Venom Web Spray
	{ 'root', 'wrath', 'wrath', 4167 }, -- Web
	-- Paladin
	{ 'stun', 'era', 'wrath', 853, 5588, 5589, 10308 }, -- Hammer of Justice
	{ 'stun', 'mists', 'mists', 853 }, -- Hammer of Justice
	{ 'incapacitate', 'era', 'mists', 20066 }, -- Repentance
	{ 'fear', 'era', 'tbc', 2878, 5627 }, -- Turn Undead / Turn Evil
	{ 'fear', 'era', 'mists', 10326 }, -- Turn Undead / Turn Evil
	{ 'stun', 'era', 'wrath', 20170 }, -- Seal of Justice / Stun
	{ 'silence', 'wrath', 'wrath', 63529 }, -- Silenced - Shield of the Templar
	{ 'stun', 'wrath', 'wrath', 2812, 10318, 27139, 48816, 48817 }, -- Holy Wrath
	{ 'stun', 'mists', 'mists', 105593 }, -- Fist of Justice
	{ 'disorient', 'mists', 'mists', 105421 }, -- Blinding Light
	{ 'silence', 'mists', 'mists', 31935 }, -- Avenger's Shield
	-- Shaman
	{ 'incapacitate', 'wrath', 'mists', 51514 }, -- Hex
	{ 'root', 'wrath', 'mists', 64695 }, -- Earthgrab
	{ 'root', 'wrath', 'mists', 63685 }, -- Freeze / Frozen Power
	{ 'stun', 'mists', 'mists', 118905 }, -- Static Charge
	-- Death Knight
	{ 'silence', 'wrath', 'mists', 47476 }, -- Strangulate
	{ 'stun', 'wrath', 'wrath', 49203 }, -- Hungering Cold
	{ 'stun', 'wrath', 'wrath', 47481 }, -- Gnaw
	{ 'stun', 'mists', 'mists', 91800 }, -- Gnaw
	{ 'stun', 'mists', 'mists', 108194 }, -- Asphyxiate
	{ 'stun', 'mists', 'mists', 91797 }, -- Monstrous Blow
	{ 'stun', 'mists', 'mists', 115001 }, -- Remorseless Winter
	-- Monk
	{ 'incapacitate', 'mists', 'mists', 115078 }, -- Paralysis
	{ 'stun', 'mists', 'mists', 119381 }, -- Leg Sweep
	{ 'silence', 'mists', 'mists', 116709 }, -- Spear Hand Strike
	{ 'root', 'mists', 'mists', 116706 }, -- Disable
	{ 'stun', 'mists', 'mists', 119392 }, -- Charging Ox Wave
	{ 'disarm', 'mists', 'mists', 117368 }, -- Grapple Weapon
	-- Racials
	{ 'stun', 'era', 'mists', 20549 }, -- War Stomp
	{ 'silence', 'tbc', 'mists', 28730 }, -- Arcane Torrent
	{ 'silence', 'tbc', 'mists', 25046 }, -- Arcane Torrent
	{ 'silence', 'wrath', 'mists', 50613 }, -- Arcane Torrent
	{ 'silence', 'mists', 'mists', 69179, 80483, 129597 }, -- Arcane Torrent
	{ 'stun', 'mists', 'mists', 107079 }, -- Quaking Palm
}
-- stylua: ignore end

---Crowd control for a client: { [spellID] = kind }.
---@param client string
---@return table<integer, string>
function P.Data.CrowdControlFor(client)
	return P.Data.BuildTiered(P.Data.CROWD_CONTROL_SOURCES, client)
end

---This client's crowd control kinds: { [spellID] = kind }.
---@type table<integer, string>
P.Data.CrowdControlKinds = P.Data.CrowdControlFor(P.Caps:Client())

---This client's crowd control: { [spellID] = true } (the shape the scan predicates read).
---@type table<integer, boolean>
P.Data.CrowdControl = {}
for id in pairs(P.Data.CrowdControlKinds) do
	P.Data.CrowdControl[id] = true
end
