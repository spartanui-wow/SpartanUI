local _, ns = ...
local P = ns.Plates

-- Interrupt spells per class (and per rank on the Classic family), used for the interrupt-ready
-- tint (4) and the kick mark on cast bars. Pet interrupts are checked first (6.4 "pet spellbook
-- first"). The Driver picks the first spell the player knows (Kicks:Choose) and stores it in
-- P.Context.kickSpell; it picks again on Kicks.EVENTS.
--
-- One table per client (Caps:Client()). Every id was checked on 2026-10-11 against Wowhead's
-- spell database for that game version (name, class, cooldown and that it interrupts casting).
-- Rank lists are highest rank first; the cooldown is shared by every rank, so any known rank
-- gives the right answer. Each client table says where its ids were checked (`source`) and
-- whether that database matches the client exactly (`exact`); `unverified` lists ids whose
-- cooldown read has not been seen working in game yet, with the reason.

P.Data = P.Data or {}

---@class Plates.KickClient
---@field source string Where the ids were checked
---@field exact boolean The checked database is this client's own
---@field byClass table<string, integer[]> Class token -> spell ids, preferred first
---@field pet integer[] Pet interrupt spell ids, preferred first
---@field unverified table<integer, string> Spell id -> what still needs an in-game check

local ERA = {
	source = 'wowhead classic (1.15)',
	exact = true,
	byClass = {
		DRUID = { 16979 }, -- Feral Charge (bear, talent)
		MAGE = { 2139 }, -- Counterspell
		PRIEST = { 15487 }, -- Silence (talent)
		ROGUE = { 1769, 1768, 1767, 1766 }, -- Kick ranks 4-1
		SHAMAN = { 10414, 10413, 10412, 8046, 8045, 8044, 8042 }, -- Earth Shock ranks 7-1
		WARRIOR = { 6554, 6552, 1672, 1671, 72 }, -- Pummel 2-1, Shield Bash 3-1
	},
	pet = { 19647, 19244 }, -- Spell Lock ranks 2-1 (Felhunter)
	unverified = { [19647] = 'pet cooldown read', [19244] = 'pet cooldown read' },
}

---@type table<string, Plates.KickClient>
local CLIENTS = {
	retail = {
		source = 'wowhead retail (12.x)',
		exact = true,
		byClass = {
			DEATHKNIGHT = { 47528 }, -- Mind Freeze
			DEMONHUNTER = { 183752 }, -- Disrupt
			DRUID = { 106839, 78675 }, -- Skull Bash, Solar Beam
			EVOKER = { 351338 }, -- Quell
			HUNTER = { 147362, 187707 }, -- Counter Shot, Muzzle
			MAGE = { 2139 }, -- Counterspell
			MONK = { 116705 }, -- Spear Hand Strike
			PALADIN = { 96231 }, -- Rebuke
			PRIEST = { 15487 }, -- Silence
			ROGUE = { 1766 }, -- Kick
			SHAMAN = { 57994 }, -- Wind Shear
			WARLOCK = { 132409, 119910, 119914 }, -- Spell Lock (sacrificed), Command Demon: Spell Lock, Axe Toss
			WARRIOR = { 6552 }, -- Pummel
		},
		pet = { 19647, 89766 }, -- Spell Lock (Felhunter), Axe Toss (Felguard)
		unverified = {
			[19647] = 'pet cooldown read',
			[89766] = 'pet cooldown read',
			[119910] = 'command demon cooldown follows the pet',
			[119914] = 'command demon cooldown follows the pet',
		},
	},
	mists = {
		source = 'wowhead mop-classic (5.5)',
		exact = true,
		byClass = {
			DEATHKNIGHT = { 47528, 47476 }, -- Mind Freeze, Strangulate
			DRUID = { 106839, 80964, 80965, 78675 }, -- Skull Bash (and its bear and cat forms), Solar Beam
			HUNTER = { 147362, 34490 }, -- Counter Shot, Silencing Shot
			MAGE = { 2139 }, -- Counterspell
			MONK = { 116705 }, -- Spear Hand Strike
			PALADIN = { 96231 }, -- Rebuke
			PRIEST = { 15487 }, -- Silence
			ROGUE = { 1766 }, -- Kick
			SHAMAN = { 57994 }, -- Wind Shear
			WARLOCK = { 132409, 119910 }, -- Spell Lock (sacrificed), Command Demon: Spell Lock
			WARRIOR = { 6552, 102060 }, -- Pummel, Disrupting Shout
		},
		pet = { 19647, 115781 }, -- Spell Lock (Felhunter), Optical Blast (Observer)
		unverified = {
			[19647] = 'pet cooldown read',
			[115781] = 'pet cooldown read',
			[119910] = 'command demon cooldown follows the pet',
		},
	},
	titan = {
		source = 'wowhead wotlk (3.4)',
		exact = false,
		byClass = {
			DEATHKNIGHT = { 47528, 47476 }, -- Mind Freeze, Strangulate
			DRUID = { 16979 }, -- Feral Charge - Bear
			HUNTER = { 34490 }, -- Silencing Shot (talent)
			MAGE = { 2139 }, -- Counterspell
			PRIEST = { 15487 }, -- Silence (talent)
			ROGUE = { 1766 }, -- Kick (one rank since 3.0.2)
			SHAMAN = { 57994 }, -- Wind Shear (Earth Shock stopped interrupting in 3.2.0)
			WARRIOR = { 6552, 29704, 1672, 1671, 72 }, -- Pummel (one rank since 3.0.2), Shield Bash
		},
		pet = { 19647, 19244 }, -- Spell Lock ranks 2-1
		unverified = { [19647] = 'pet cooldown read', [19244] = 'pet cooldown read' },
	},
	tbc = {
		source = 'wowhead tbc (2.5)',
		exact = true,
		byClass = {
			DRUID = { 16979 }, -- Feral Charge (bear, talent)
			HUNTER = { 34490 }, -- Silencing Shot (talent)
			MAGE = { 2139 }, -- Counterspell
			PRIEST = { 15487 }, -- Silence (talent)
			ROGUE = { 38768, 1769, 1768, 1767, 1766 }, -- Kick ranks 5-1
			SHAMAN = { 25454, 10414, 10413, 10412, 8046, 8045, 8044, 8042 }, -- Earth Shock ranks 8-1
			WARRIOR = { 6554, 6552, 29704, 1672, 1671, 72 }, -- Pummel 2-1, Shield Bash 4-1
		},
		pet = { 19647, 19244 }, -- Spell Lock ranks 2-1
		unverified = { [19647] = 'pet cooldown read', [19244] = 'pet cooldown read' },
	},
	era = ERA,
	-- WoW Forever plays by Classic rules; it has no public spell database, so it uses Era's ids
	forever = {
		source = 'wowhead classic (1.15), assumed for Forever',
		exact = false,
		byClass = ERA.byClass,
		pet = ERA.pet,
		unverified = { [19647] = 'pet cooldown read', [19244] = 'pet cooldown read' },
	},
}

---@class Plates.Kicks
---@field byClass table<string, integer[]> The current client's lists (Kicks:Use)
---@field pet integer[]
---@field client string Client the lists belong to
local Kicks = { byClass = {}, pet = {}, client = 'unknown', CLIENTS = CLIENTS }
P.Data.Kicks = Kicks

---Game events after which the Driver picks the interrupt again (spells learned, pet summoned
---or dismissed, talents changed).
Kicks.EVENTS = { 'SPELLS_CHANGED', 'UNIT_PET', 'PLAYER_ENTERING_WORLD' }

---Point byClass and pet at one client's lists (a client name from Caps:Client()). Unknown
---clients get no interrupts rather than another client's ids.
---@param client string
function Kicks:Use(client)
	local data = CLIENTS[client]
	self.client = client
	self.byClass = data and data.byClass or {}
	self.pet = data and data.pet or {}
end

---The current client's table (nil on an unknown client).
---@return Plates.KickClient|nil
function Kicks:Data()
	return CLIENTS[self.client]
end

---First interrupt the player can use (pure; `known` answers whether a spell id is usable).
---@param classToken string|nil
---@param known fun(spellID: integer, isPet: boolean): boolean
---@return integer|nil spellID
---@return boolean isPet
function Kicks:Pick(classToken, known)
	for _, spell in ipairs(self.pet) do
		if known(spell, true) then
			return spell, true
		end
	end
	for _, spell in ipairs(classToken and self.byClass[classToken] or {}) do
		if known(spell, false) then
			return spell, false
		end
	end
	return nil, false
end

local function Ask(fn, spellID, bank)
	local ok, answer = pcall(fn, spellID, bank)
	return ok and answer == true
end

---Whether the player (or the pet, for isPet) has a spell: the spell book first, then the
---older global on clients that still have it.
---@param spellID integer
---@param isPet boolean
---@return boolean
function Kicks.Known(spellID, isPet)
	local book = C_SpellBook
	local banks = Enum and Enum.SpellBookSpellBank
	if book and banks then
		local bank = isPet and banks.Pet or banks.Player
		if book.IsSpellKnownOrInSpellBook and Ask(book.IsSpellKnownOrInSpellBook, spellID, bank) then
			return true
		end
		if book.IsSpellKnown and Ask(book.IsSpellKnown, spellID, bank) then
			return true
		end
		return false
	end
	local legacy = _G.IsSpellKnown
	if legacy then
		return Ask(legacy, spellID, isPet and true or false)
	end
	return false
end

---The interrupt the player can use now, for P.Context.kickSpell (the Driver writes it).
---@param classToken string|nil Player class token
---@return integer|nil spellID
---@return boolean isPet
function Kicks:Choose(classToken)
	return self:Pick(classToken, Kicks.Known)
end

Kicks:Use(P.Caps:Client())
