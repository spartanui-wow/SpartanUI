local _, ns = ...
local P = ns.Plates

-- Tank debuffs from anyone (4, Phase 3): armor, attack power and attack speed debuffs a tank
-- keeps up, every rank. Classic family and Forever only; on Forever they feed a second group in
-- the My debuffs container through includeSpellIDs, on the Classic family the Lua scan
-- (Engine/Parts/AurasScan.lua). Retail has none (its container row covers the player's own).
--
-- Each entry: { kind, first tier, last tier, spell ids... }. Tiers follow the client's content:
-- era (Classic Era, and Forever, which runs Classic content), tbc (TBC Anniversary), wrath
-- (Titan), mists (Mists). The ids are the auras the game puts on the target, which is not always
-- the spell that was cast (Wrath's Sunder Armor applies 58567; Mists folds several into Weakened
-- Armor and Weakened Blows).
--
-- Verified 2026-10-12 against Wowhead's per-client databases (classic, tbc, wotlk, mop-classic):
-- each id's listing (name, rank, class) and, where the cast and the aura could differ, its spell
-- page (Apply Aura or Trigger Spell). Titan reads the Wrath ids; no Titan database exists to check.

P.Data = P.Data or {}

-- P.Data.BuildTiered and P.Data.CLIENT_TIERS come from Data/CrowdControl.lua, which loads first
assert(P.Data.BuildTiered, 'Data/CrowdControl.lua must load before Data/TankDebuffs.lua')

-- stylua: ignore start
---@type table[]
P.Data.TANK_DEBUFF_SOURCES = {
	-- Sunder Armor (Warrior). Wrath has one rank whose debuff is 58567; Mists: Weakened Armor
	{ 'sunder', 'era', 'tbc', 7386, 7405, 8380, 11596, 11597 }, -- Sunder Armor
	{ 'sunder', 'tbc', 'tbc', 25225 }, -- Sunder Armor
	{ 'sunder', 'wrath', 'wrath', 58567 }, -- Sunder Armor
	-- Expose Armor (Rogue). Wrath has one rank
	{ 'exposeArmor', 'era', 'wrath', 8647 }, -- Expose Armor
	{ 'exposeArmor', 'era', 'tbc', 8649, 8650, 11197, 11198 }, -- Expose Armor
	{ 'exposeArmor', 'tbc', 'tbc', 26866 }, -- Expose Armor
	-- Faerie Fire and Faerie Fire (Feral) (Druid). Wrath has one rank of each, Mists only the first
	{ 'faerieFire', 'era', 'mists', 770 }, -- Faerie Fire
	{ 'faerieFire', 'era', 'wrath', 16857 }, -- Faerie Fire (Feral)
	{ 'faerieFire', 'era', 'tbc', 778, 9749, 9907 }, -- Faerie Fire
	{ 'faerieFire', 'era', 'tbc', 17390, 17391, 17392 }, -- Faerie Fire (Feral)
	{ 'faerieFire', 'tbc', 'tbc', 26993 }, -- Faerie Fire
	{ 'faerieFire', 'tbc', 'tbc', 27011 }, -- Faerie Fire (Feral)
	-- Curse of Recklessness (Warlock): armor
	{ 'curseOfRecklessness', 'era', 'tbc', 704, 7658, 7659, 11717 }, -- Curse of Recklessness
	{ 'curseOfRecklessness', 'tbc', 'tbc', 27226 }, -- Curse of Recklessness
	-- Demoralizing Shout (Warrior). Mists keeps the first id as a single rank
	{ 'demoShout', 'era', 'mists', 1160 }, -- Demoralizing Shout
	{ 'demoShout', 'era', 'wrath', 6190, 11554, 11555, 11556 }, -- Demoralizing Shout
	{ 'demoShout', 'tbc', 'wrath', 25202, 25203 }, -- Demoralizing Shout
	{ 'demoShout', 'wrath', 'wrath', 47437 }, -- Demoralizing Shout
	-- Demoralizing Roar (Druid). Mists reuses 99 for Disorienting Roar (crowd control)
	{ 'demoRoar', 'era', 'wrath', 99, 1735, 9490, 9747, 9898 }, -- Demoralizing Roar
	{ 'demoRoar', 'tbc', 'wrath', 26998 }, -- Demoralizing Roar
	{ 'demoRoar', 'wrath', 'wrath', 48559, 48560 }, -- Demoralizing Roar
	-- Thunder Clap (Warrior). Mists: Weakened Blows
	{ 'thunderClap', 'era', 'wrath', 6343, 8198, 8204, 8205, 11580, 11581 }, -- Thunder Clap
	{ 'thunderClap', 'tbc', 'wrath', 25264 }, -- Thunder Clap
	{ 'thunderClap', 'wrath', 'wrath', 47501, 47502 }, -- Thunder Clap
	-- Curse of Weakness (Warlock)
	{ 'curseOfWeakness', 'era', 'wrath', 702, 1108, 6205, 7646, 11707, 11708 }, -- Curse of Weakness
	{ 'curseOfWeakness', 'tbc', 'wrath', 27224, 30909 }, -- Curse of Weakness
	{ 'curseOfWeakness', 'wrath', 'wrath', 50511 }, -- Curse of Weakness
	-- Vindication (Paladin): attack power
	{ 'vindication', 'tbc', 'wrath', 67, 26017 }, -- Vindication
	-- Wrath attack speed debuffs: Frost Fever (Death Knight), Infected Wounds (Druid), Judgements
	-- of the Just (Paladin)
	{ 'frostFever', 'wrath', 'wrath', 55095 }, -- Frost Fever
	{ 'infectedWounds', 'wrath', 'wrath', 58179, 58180, 58181 }, -- Infected Wounds
	{ 'judgementsOfTheJust', 'wrath', 'wrath', 68055 }, -- Judgements of the Just
	-- Mists shared debuffs: Weakened Armor (Sunder Armor, Devastate, Expose Armor, Faerie Fire)
	-- and Weakened Blows (Thunder Clap, Keg Smash, Thrash, Hammer of the Righteous, Earth Shock)
	{ 'weakenedArmor', 'mists', 'mists', 113746 }, -- Weakened Armor
	{ 'weakenedBlows', 'mists', 'mists', 115798 }, -- Weakened Blows
}
-- stylua: ignore end

---Tank debuffs for a client: { [spellID] = kind }.
---@param client string
---@return table<integer, string>
function P.Data.TankDebuffsFor(client)
	return P.Data.BuildTiered(P.Data.TANK_DEBUFF_SOURCES, client)
end

---This client's tank debuffs: { [spellID] = kind }.
---@type table<integer, string>
P.Data.TankDebuffs = P.Data.TankDebuffsFor(P.Caps:Client())

---Spell ids as a list, for includeSpellIDs.
---@return integer[]
function P.Data.TankDebuffIDs()
	local list = {}
	for id in pairs(P.Data.TankDebuffs) do
		list[#list + 1] = id
	end
	table.sort(list)
	return list
end
