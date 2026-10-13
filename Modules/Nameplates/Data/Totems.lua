local _, ns = ...
local P = ns.Plates
P.Data = P.Data or {}

-- NPCs are the spell's summon effect, not the elemental called by an elemental totem.
-- Classic rows: https://classicdb.ch/?spell=<spellID> (summon effect and rank).
-- Expansion rows: https://www.wowhead.com/tbc/spell=<spellID> and /mop-classic/spell=<spellID>.
local Totems = { byNPC = {}, bySpell = {} }
P.Data.Totems = Totems
local CLASSIC = { era = true, tbc = true, titan = true, forever = true }
local LATER = { tbc = true, titan = true, forever = true }
local MISTS = { mists = true, retail = true, forever = true }
local ALL = { era = true, tbc = true, titan = true, mists = true, retail = true, forever = true }

local function Add(name, icon, clients, ranks)
	for _, pair in ipairs(ranks) do
		local spell, npc, rank = pair[1], pair[2], pair[3] or 1
		local row = { name = name, icon = 'Interface\\Icons\\' .. icon, clients = clients, spellID = spell, npcID = npc, rank = rank }
		Totems.bySpell[spell], Totems.byNPC[npc] = row, row
	end
end

Add('Grounding Totem', 'Spell_Nature_GroundingTotem', ALL, { { 8177, 5925 } })
Add('Tremor Totem', 'Spell_Nature_TremorTotem', ALL, { { 8143, 5913 } })
Add('Earthbind Totem', 'Spell_Nature_StrengthOfEarthTotem02', ALL, { { 2484, 2630 } })
Add('Searing Totem', 'Spell_Fire_SearingTotem', ALL, {
	{ 3599, 2523 },
	{ 6364, 3903, 3 },
	{ 6365, 3904, 4 },
	{ 10437, 7400, 5 },
	{ 10438, 7402, 6 },
})
Add('Healing Stream Totem', 'INV_Spear_04', ALL, {
	{ 5394, 3527 },
	{ 6375, 3906, 2 },
	{ 6377, 3907, 3 },
	{ 10463, 3909, 5 },
})
Add('Mana Spring Totem', 'Spell_Nature_ManaRegenTotem', CLASSIC, {
	{ 5675, 3573 },
	{ 10495, 7414, 2 },
	{ 10496, 7415, 3 },
	{ 10497, 7416, 4 },
})
Add('Stoneclaw Totem', 'Spell_Nature_StoneClawTotem', CLASSIC, {
	{ 5730, 3579 },
	{ 6390, 3911, 2 },
	{ 6391, 3912, 3 },
	{ 6392, 3913, 4 },
	{ 10427, 7398, 5 },
	{ 10428, 7399, 6 },
})
Add('Stoneskin Totem', 'Spell_Nature_StoneSkinTotem', CLASSIC, {
	{ 8071, 5873 },
	{ 8154, 5919, 2 },
	{ 8155, 5920, 3 },
	{ 10406, 7366, 4 },
	{ 10407, 7367, 5 },
	{ 10408, 7368, 6 },
})
Add('Strength of Earth Totem', 'Spell_Nature_EarthBindTotem', CLASSIC, {
	{ 8075, 5874 },
	{ 8160, 5921, 2 },
	{ 8161, 5922, 3 },
	{ 10442, 7403, 4 },
	{ 25361, 15464, 5 },
})
Add('Poison Cleansing Totem', 'Spell_Nature_PoisonCleansingTotem', CLASSIC, { { 8166, 5923 } })
Add('Disease Cleansing Totem', 'Spell_Nature_DiseaseCleansingTotem', CLASSIC, { { 8170, 5924 } })
Add('Magma Totem', 'Spell_Fire_SelfDestruct', ALL, { { 8190, 5929 }, { 10587, 7466, 4 } })
Add('Windfury Totem', 'Spell_Nature_Windfury', CLASSIC, { { 8512, 6112 } })
Add('Flametongue Totem', 'Spell_Nature_GuardianWard', CLASSIC, { { 8227, 5950 }, { 16387, 10557, 4 } })
Add('Mana Tide Totem', 'Spell_Frost_SummonWaterElemental', ALL, { { 16190, 10467 } })
Add('Frost Resistance Totem', 'Spell_FrostResistanceTotem_01', CLASSIC, { { 8181, 5926 }, { 10478, 7412, 2 }, { 10479, 7413, 3 } })
Add('Fire Resistance Totem', 'Spell_FireResistanceTotem_01', CLASSIC, { { 8184, 5927 } })
Add('Nature Resistance Totem', 'Spell_Nature_NatureResistanceTotem', CLASSIC, { { 10595, 7467 } })
Add('Wrath of Air Totem', 'Spell_Nature_SlowingTotem', LATER, { { 3738, 15447 } })
Add('Fire Elemental Totem', 'Spell_Fire_Elemental_Totem', LATER, { { 2894, 15439 } })
Add('Capacitor Totem', 'Spell_Nature_Brilliance', MISTS, { { 108269, 61245 } })
Add('Spirit Link Totem', 'Spell_Shaman_SpiritLink', MISTS, { { 98008, 53006 } })
Add('Healing Tide Totem', 'Ability_Shaman_HealingTide', MISTS, { { 108280, 59764 } })
Add('Earthgrab Totem', 'Spell_Nature_StrangleVines', MISTS, { { 51485, 60561 } })

Add('Fire Nova Totem', 'Spell_Fire_SealOfFire', CLASSIC, {
	{ 1535, 5879 },
	{ 8498, 6110, 2 },
	{ 8499, 6111, 3 },
	{ 11314, 7844, 4 },
	{ 11315, 7845, 5 },
})
Add('Grace of Air Totem', 'Spell_Nature_InvisibilityTotem', CLASSIC, { { 8835, 7486 }, { 10627, 7487, 2 }, { 25359, 15463, 3 } })
Add('Tranquil Air Totem', 'Spell_Nature_Brilliance', CLASSIC, { { 25908, 15803 } })

function Totems:ForNPC(id, client)
	local row = id and self.byNPC[id]
	if row and row.clients[client] then
		return row
	end
end

function Totems:ForSpell(id, client)
	local row = id and self.bySpell[id]
	if row and row.clients[client] then
		return row
	end
end
