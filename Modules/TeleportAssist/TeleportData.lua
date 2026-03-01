local SUI = SUI
---@class SUI.Module.TeleportAssist
local module = SUI:GetModule('TeleportAssist')
----------------------------------------------------------------------------------------------------

-- Expansion order (newest first)
module.EXPANSION_ORDER = {
	'Home',
	'Class',
	'MID', -- Midnight (12.x)
	'TWW', -- The War Within (11.x)
	'DF', -- Dragonflight (10.x)
	'SL', -- Shadowlands (9.x)
	'BFA', -- Battle for Azeroth (8.x)
	'Legion', -- Legion (7.x)
	'WoD', -- Warlords of Draenor (6.x)
	'MoP', -- Mists of Pandaria (5.x)
	'Cata', -- Cataclysm (4.x)
	'WotLK', -- Wrath of the Lich King (3.x)
	'TBC', -- The Burning Crusade (2.x)
	'Classic', -- Classic (1.x)
}

module.EXPANSION_NAMES = {
	Home = 'Home',
	Class = 'Class',
	MID = EXPANSION_NAME11 or 'Midnight',
	TWW = EXPANSION_NAME10 or 'The War Within',
	DF = EXPANSION_NAME9 or 'Dragonflight',
	SL = EXPANSION_NAME8 or 'Shadowlands',
	BFA = EXPANSION_NAME7 or 'Battle for Azeroth',
	Legion = EXPANSION_NAME6 or 'Legion',
	WoD = EXPANSION_NAME5 or 'Warlords of Draenor',
	MoP = EXPANSION_NAME4 or 'Mists of Pandaria',
	Cata = EXPANSION_NAME3 or 'Cataclysm',
	WotLK = EXPANSION_NAME2 or 'Wrath of the Lich King',
	TBC = EXPANSION_NAME1 or 'The Burning Crusade',
	Classic = EXPANSION_NAME0 or 'Classic',
}

-- Expansion level constants for minExpansion filtering
-- 0 = Classic, 1 = TBC, 2 = WotLK, 3 = Cata, 4 = MoP, 5 = WoD, 6 = Legion, 7 = BFA, 8 = SL, 9 = DF, 10 = TWW, 11 = Midnight

---@class SUI.TeleportAssist.TeleportEntry
---@field id number Spell ID, Item ID, Toy ID, or 0 for macro/housing types
---@field spellId? number Actual spell ID if different from id (for items/toys)
---@field type 'spell'|'item'|'toy'|'macro'|'housing' Type of teleport
---@field macro? string Macro body text (for type='macro')
---@field name string Display name
---@field expansion string Expansion category
---@field icon? number|string Override icon texture
---@field class? string Class restriction (nil = all classes)
---@field race? string Race restriction (nil = all races)
---@field faction? string Faction restriction ('Alliance', 'Horde', or nil for both)
---@field isPortal? boolean True if this is a mage portal (vs teleport)
---@field isEngineering? boolean Requires engineering profession
---@field isHearthstone? boolean Is a hearthstone variant
---@field availableCheck? fun(): boolean Custom availability check function
---@field minExpansion? number Minimum expansion level required (0=Classic, 1=TBC, etc.)
---@field mapId? number UI Map ID for world map pin destination
---@field mapX? number X coordinate (0-1) on the destination map
---@field mapY? number Y coordinate (0-1) on the destination map

-- Hearthstone variants (for random hearthstone feature)
---@type table<number, {isToy?: boolean, isItem?: boolean, icon: number, id: number, spellId: number, minExpansion?: number}>
module.HEARTHSTONE_VARIANTS = {
	-- Standard
	{ isItem = true, icon = 134414, id = 6948, spellId = 8690, minExpansion = 0 }, -- Default Hearthstone
	-- Toys (all require toy box which was added in WoD, minExpansion = 5 minimum, or higher based on when added)
	{ isToy = true, icon = 236222, id = 54452, spellId = 75136, minExpansion = 5 }, -- Ethereal Portal
	{ isToy = true, icon = 458254, id = 64488, spellId = 94716, minExpansion = 5 }, -- The Innkeeper's Daughter
	{ isToy = true, icon = 255348, id = 93672, spellId = 136508, minExpansion = 5 }, -- Dark Portal
	{ isToy = true, icon = 2124576, id = 162973, spellId = 278244, minExpansion = 7 }, -- Greatfather Winter's Hearthstone
	{ isToy = true, icon = 2124575, id = 163045, spellId = 278559, minExpansion = 7 }, -- Headless Horseman's Hearthstone
	{ isToy = true, icon = 2491049, id = 165669, spellId = 285362, minExpansion = 7 }, -- Lunar Elder's Hearthstone
	{ isToy = true, icon = 2491048, id = 165670, spellId = 285424, minExpansion = 7 }, -- Peddlefeet's Lovely Hearthstone
	{ isToy = true, icon = 2491065, id = 165802, spellId = 286031, minExpansion = 7 }, -- Noble Gardener's Hearthstone
	{ isToy = true, icon = 2491064, id = 166746, spellId = 286331, minExpansion = 7 }, -- Fire Eater's Hearthstone
	{ isToy = true, icon = 2491063, id = 166747, spellId = 286353, minExpansion = 7 }, -- Brewfest Reveler's Hearthstone
	{ isToy = true, icon = 2491049, id = 168907, spellId = 298068, minExpansion = 7 }, -- Holographic Digitalization Hearthstone
	{ isToy = true, icon = 3084684, id = 172179, spellId = 308742, minExpansion = 8 }, -- Eternal Traveler's Hearthstone
	{ isToy = true, icon = 3528303, id = 188952, spellId = 363799, minExpansion = 8 }, -- Dominated Hearthstone
	{ isToy = true, icon = 3950360, id = 190196, spellId = 366945, minExpansion = 8 }, -- Enlightened Hearthstone
	{ isToy = true, icon = 3954409, id = 190237, spellId = 367013, minExpansion = 8 }, -- Broker Translocation Matrix
	{ isToy = true, icon = 4571434, id = 193588, spellId = 375357, minExpansion = 9 }, -- Timewalker's Hearthstone
	{ isToy = true, icon = 4080564, id = 200630, spellId = 391042, minExpansion = 9 }, -- Ohn'ir Windsage's Hearthstone
	{ isToy = true, icon = 1708140, id = 206195, spellId = 412555, minExpansion = 9 }, -- Path of the Naaru
	{ isToy = true, icon = 5333528, id = 208704, spellId = 420418, minExpansion = 9 }, -- Deepdweller's Earth Hearthstone
	{ isToy = true, icon = 2491064, id = 209035, spellId = 422284, minExpansion = 9 }, -- Hearthstone of the Flame
	{ isToy = true, icon = 5524923, id = 212337, spellId = 401802, minExpansion = 10 }, -- Stone of the Hearth
	{ isToy = true, icon = 5891370, id = 228940, spellId = 463481, minExpansion = 10 }, -- Notorious Thread's Hearthstone
	{ isToy = true, icon = 6383489, id = 236687, spellId = 1220729, minExpansion = 10 }, -- Explosive Hearthstone
	{ isToy = true, icon = 4622300, id = 235016, spellId = 1217281, minExpansion = 10 }, -- Redeployment Module (TWW)
	{ isToy = true, icon = 133469, id = 245970, spellId = 1240219, minExpansion = 10 }, -- P.O.S.T. Master's Express Hearthstone
	{ isToy = true, icon = 5852174, id = 246565, spellId = 1242509, minExpansion = 10 }, -- Cosmic Hearthstone
	-- Covenant Hearthstones (Shadowlands)
	{ isToy = true, icon = 3257748, id = 184353, spellId = 345393, minExpansion = 8 }, -- Kyrian Hearthstone
	{ isToy = true, icon = 3514225, id = 183716, spellId = 342122, minExpansion = 8 }, -- Venthyr Sinstone
	{ isToy = true, icon = 3489827, id = 180290, spellId = 326064, minExpansion = 8 }, -- Night Fae Hearthstone
	{ isToy = true, icon = 3716927, id = 182773, spellId = 340200, minExpansion = 8 }, -- Necrolord Hearthstone
}

-- Main teleport compendium
---@type SUI.TeleportAssist.TeleportEntry[]
module.TELEPORT_DATA = {
	-- ==================== HOME ====================
	-- Hearthstone handled separately via HEARTHSTONE_VARIANTS
	-- Housing handled separately via PLAYER_HOUSE_LIST_UPDATED event

	-- ==================== CLASS TELEPORTS ====================
	-- Mage Hall of the Guardian
	{ id = 193759, type = 'spell', name = 'Hall of the Guardian', expansion = 'Class', class = 'MAGE', minExpansion = 6 },
	-- Druid Dreamwalk
	{ id = 193753, type = 'spell', name = 'Dreamwalk', expansion = 'Class', class = 'DRUID', minExpansion = 6 },
	-- Death Knight Death Gate
	{ id = 50977, type = 'spell', name = 'Death Gate', expansion = 'Class', class = 'DEATHKNIGHT', minExpansion = 2 },
	-- Shaman Astral Recall
	{ id = 556, type = 'spell', name = 'Astral Recall', expansion = 'Class', class = 'SHAMAN', minExpansion = 0 },
	-- Monk Zen Pilgrimage
	{ id = 126892, type = 'spell', name = 'Zen Pilgrimage', expansion = 'Class', class = 'MONK', minExpansion = 4 },
	-- Dark Iron Dwarf Mole Machine
	{ id = 265225, type = 'spell', name = 'Mole Machine', expansion = 'Class', race = 'DarkIronDwarf', minExpansion = 7 },
	-- Vulpera Camp
	{ id = 312372, type = 'spell', name = 'Make Camp', expansion = 'Class', race = 'Vulpera', minExpansion = 7 },

	-- ==================== MIDNIGHT (12.x) ====================
	-- Mage Teleports
	{
		id = 1259190,
		type = 'spell',
		name = 'Teleport: Silvermoon City',
		expansion = 'MID',
		class = 'MAGE',
		faction = 'Horde',
		icon = 'inv_12_mage_teleport',
		minExpansion = 11,
	},
	{
		id = 1259194,
		type = 'spell',
		name = 'Portal: Silvermoon City',
		expansion = 'MID',
		class = 'MAGE',
		faction = 'Horde',
		isPortal = true,
		icon = 'inv_12_mage_portal',
		minExpansion = 11,
	},
	-- Dungeons
	{ id = 1254572, type = 'spell', name = "Magisters' Terrace", expansion = 'MID', minExpansion = 11 },
	{ id = 1254559, type = 'spell', name = 'Maisara Caverns', expansion = 'MID', minExpansion = 11 },
	{ id = 1254563, type = 'spell', name = 'Nexus-Point Xenas', expansion = 'MID', minExpansion = 11 },
	{ id = 1254400, type = 'spell', name = 'Windrunner Spire', expansion = 'MID', minExpansion = 11 },

	-- ==================== THE WAR WITHIN (11.x) ====================
	-- Dungeons
	{ id = 445269, type = 'spell', name = 'Stonevault', expansion = 'TWW', minExpansion = 10, mapId = 2274, mapX = 0.535, mapY = 0.432 },
	{ id = 445416, type = 'spell', name = 'City of Threads', expansion = 'TWW', minExpansion = 10, mapId = 2274, mapX = 0.451, mapY = 0.792 },
	{ id = 445414, type = 'spell', name = 'Cinderbrew Meadery', expansion = 'TWW', minExpansion = 10, mapId = 2274, mapX = 0.841, mapY = 0.207 },
	{ id = 445417, type = 'spell', name = 'The Dawnbreaker', expansion = 'TWW', minExpansion = 10, mapId = 2274, mapX = 0.406, mapY = 0.584 },
	{ id = 1216786, type = 'spell', name = 'Priory of the Sacred Flame', expansion = 'TWW', minExpansion = 10, mapId = 2274, mapX = 0.372, mapY = 0.479 },
	{ id = 1237215, type = 'spell', name = 'Ara-Kara, City of Echoes', expansion = 'TWW', minExpansion = 10, mapId = 2274, mapX = 0.467, mapY = 0.851 },
	{ id = 445440, type = 'spell', name = 'Darkflame Cleft', expansion = 'TWW', minExpansion = 10, mapId = 2274, mapX = 0.574, mapY = 0.490 },
	{ id = 445444, type = 'spell', name = 'The Rookery', expansion = 'TWW', minExpansion = 10, mapId = 2274, mapX = 0.693, mapY = 0.212 },
	{ id = 445441, type = 'spell', name = 'The Necrotic Wake', expansion = 'TWW', minExpansion = 10, mapId = 1533, mapX = 0.401, mapY = 0.455 },
	{ id = 445443, type = 'spell', name = 'Grim Batol', expansion = 'TWW', minExpansion = 10, mapId = 241, mapX = 0.192, mapY = 0.541 },
	-- Mage Teleports
	{ id = 446540, type = 'spell', name = 'Teleport: Dornogal', expansion = 'TWW', class = 'MAGE', minExpansion = 10, mapId = 2274, mapX = 0.689, mapY = 0.202 },
	{ id = 446534, type = 'spell', name = 'Portal: Dornogal', expansion = 'TWW', class = 'MAGE', isPortal = true, minExpansion = 10, mapId = 2274, mapX = 0.689, mapY = 0.202 },
	-- Engineering
	{ id = 448126, spellId = 448126, type = 'toy', name = 'Wormhole Generator: Khaz Algar', expansion = 'TWW', isEngineering = true, minExpansion = 10 },
	-- Raids
	{ id = 1226482, type = 'spell', name = 'Liberation of Undermine', expansion = 'TWW', minExpansion = 10, mapId = 2346, mapX = 0.420, mapY = 0.503 },
	{ id = 1239155, type = 'spell', name = 'Manaforge Omega', expansion = 'TWW', minExpansion = 10, mapId = 2371, mapX = 0.417, mapY = 0.622 },
	-- Delve Hearthstones
	{ id = 230850, type = 'toy', name = "Delver's Dirigible", expansion = 'TWW', isHearthstone = true, minExpansion = 10 },
	{ id = 243056, type = 'toy', name = 'Radiant Remnant', expansion = 'TWW', isHearthstone = true, minExpansion = 10 },

	-- ==================== DRAGONFLIGHT (10.x) ====================
	-- Dungeons
	{ id = 393256, type = 'spell', name = 'Ruby Life Pools', expansion = 'DF', minExpansion = 9, mapId = 1978, mapX = 0.536, mapY = 0.405 },
	{ id = 393262, type = 'spell', name = 'The Nokhud Offensive', expansion = 'DF', minExpansion = 9, mapId = 1978, mapX = 0.459, mapY = 0.519 },
	{ id = 393267, type = 'spell', name = 'Brackenhide Hollow', expansion = 'DF', minExpansion = 9, mapId = 1978, mapX = 0.357, mapY = 0.757 },
	{ id = 393273, type = 'spell', name = "Algeth'ar Academy", expansion = 'DF', minExpansion = 9, mapId = 1978, mapX = 0.639, mapY = 0.394 },
	{ id = 393276, type = 'spell', name = 'Neltharus', expansion = 'DF', minExpansion = 9, mapId = 1978, mapX = 0.434, mapY = 0.363 },
	{ id = 393279, type = 'spell', name = 'The Azure Vault', expansion = 'DF', minExpansion = 9, mapId = 1978, mapX = 0.476, mapY = 0.823 },
	{ id = 393283, type = 'spell', name = 'Halls of Infusion', expansion = 'DF', minExpansion = 9, mapId = 1978, mapX = 0.639, mapY = 0.486 },
	{ id = 393222, type = 'spell', name = 'Uldaman: Legacy of Tyr', expansion = 'DF', minExpansion = 9, mapId = 13, mapX = 0.527, mapY = 0.646 },
	{ id = 424197, type = 'spell', name = 'Dawn of the Infinite', expansion = 'DF', minExpansion = 9, mapId = 1978, mapX = 0.656, mapY = 0.540 },
	-- Mage Teleports
	{ id = 395277, type = 'spell', name = 'Teleport: Valdrakken', expansion = 'DF', class = 'MAGE', minExpansion = 9, mapId = 1978, mapX = 0.563, mapY = 0.500 },
	{ id = 395289, type = 'spell', name = 'Portal: Valdrakken', expansion = 'DF', class = 'MAGE', isPortal = true, minExpansion = 9, mapId = 1978, mapX = 0.563, mapY = 0.500 },
	-- Raids
	{ id = 432254, type = 'spell', name = 'Vault of the Incarnates', expansion = 'DF', minExpansion = 9, mapId = 2025, mapX = 0.749, mapY = 0.555 },
	{ id = 432257, type = 'spell', name = 'Aberrus, the Shadowed Crucible', expansion = 'DF', minExpansion = 9, mapId = 2133, mapX = 0.484, mapY = 0.119 },
	{ id = 432258, type = 'spell', name = 'Amirdrassil, the Dreams Hope', expansion = 'DF', minExpansion = 9, mapId = 2200, mapX = 0.273, mapY = 0.310 },
	-- Engineering
	{ id = 198156, type = 'toy', name = 'Wyrmhole Generator', expansion = 'DF', isEngineering = true, minExpansion = 9 },

	-- ==================== SHADOWLANDS (9.x) ====================
	-- Dungeons
	{ id = 354462, type = 'spell', name = 'The Necrotic Wake', expansion = 'SL', minExpansion = 8, mapId = 1550, mapX = 0.685, mapY = 0.603 },
	{ id = 354463, type = 'spell', name = 'Plaguefall', expansion = 'SL', minExpansion = 8, mapId = 1550, mapX = 0.655, mapY = 0.272 },
	{ id = 354464, type = 'spell', name = 'Mists of Tirna Scithe', expansion = 'SL', minExpansion = 8, mapId = 1550, mapX = 0.455, mapY = 0.824 },
	{ id = 354465, type = 'spell', name = 'Halls of Atonement', expansion = 'SL', minExpansion = 8, mapId = 1550, mapX = 0.311, mapY = 0.554 },
	{ id = 354466, type = 'spell', name = 'Spires of Ascension', expansion = 'SL', minExpansion = 8, mapId = 1550, mapX = 0.736, mapY = 0.526 },
	{ id = 354467, type = 'spell', name = 'Theater of Pain', expansion = 'SL', minExpansion = 8, mapId = 1550, mapX = 0.633, mapY = 0.227 },
	{ id = 354468, type = 'spell', name = 'De Other Side', expansion = 'SL', minExpansion = 8, mapId = 1550, mapX = 0.541, mapY = 0.844 },
	{ id = 354469, type = 'spell', name = 'Sanguine Depths', expansion = 'SL', minExpansion = 8, mapId = 1550, mapX = 0.250, mapY = 0.482 },
	{ id = 367416, type = 'spell', name = 'Tazavesh', expansion = 'SL', minExpansion = 8, mapId = 1550, mapX = 0.332, mapY = 0.716 },
	-- Raids
	{ id = 373190, type = 'spell', name = 'Castle Nathria', expansion = 'SL', minExpansion = 8, mapId = 1525, mapX = 0.464, mapY = 0.414 },
	{ id = 373191, type = 'spell', name = 'Sanctum of Domination', expansion = 'SL', minExpansion = 8, mapId = 1543, mapX = 0.697, mapY = 0.320 },
	{ id = 373192, type = 'spell', name = 'Sepulcher of the First Ones', expansion = 'SL', minExpansion = 8, mapId = 1970, mapX = 0.805, mapY = 0.534 },
	-- Mage Teleports
	{ id = 344587, type = 'spell', name = 'Teleport: Oribos', expansion = 'SL', class = 'MAGE', minExpansion = 8, mapId = 1550, mapX = 0.466, mapY = 0.516 },
	{ id = 344597, type = 'spell', name = 'Portal: Oribos', expansion = 'SL', class = 'MAGE', isPortal = true, minExpansion = 8, mapId = 1550, mapX = 0.466, mapY = 0.516 },
	-- Engineering
	{ id = 172924, type = 'toy', name = 'Wormhole Generator: Shadowlands', expansion = 'SL', isEngineering = true, minExpansion = 8 },
	-- Items
	{ id = 180817, type = 'item', name = 'Cypher of Relocation', expansion = 'SL', minExpansion = 8 },

	-- ==================== BATTLE FOR AZEROTH (8.x) ====================
	-- Dungeons
	{ id = 410071, type = 'spell', name = 'Freehold', expansion = 'BFA', minExpansion = 7, mapId = 876, mapX = 0.628, mapY = 0.747 },
	{ id = 410074, type = 'spell', name = 'Underrot', expansion = 'BFA', minExpansion = 7, mapId = 875, mapX = 0.574, mapY = 0.370 },
	{ id = 373274, type = 'spell', name = 'Operation: Mechagon', expansion = 'BFA', minExpansion = 7, mapId = 876, mapX = 0.199, mapY = 0.281 },
	{ id = 424167, type = 'spell', name = 'Waycrest Manor', expansion = 'BFA', minExpansion = 7, mapId = 876, mapX = 0.298, mapY = 0.555 },
	{ id = 424187, type = 'spell', name = "Atal'Dazar", expansion = 'BFA', minExpansion = 7, mapId = 875, mapX = 0.488, mapY = 0.611 },
	{ id = 445418, type = 'spell', name = 'Siege of Boralus', expansion = 'BFA', faction = 'Alliance', minExpansion = 7, mapId = 895, mapX = 0.734, mapY = 0.233 },
	{ id = 464256, type = 'spell', name = 'Siege of Boralus', expansion = 'BFA', faction = 'Horde', minExpansion = 7, mapId = 895, mapX = 0.734, mapY = 0.233 },
	{ id = 467553, type = 'spell', name = 'Motherlode', expansion = 'BFA', faction = 'Alliance', minExpansion = 7, mapId = 862, mapX = 0.561, mapY = 0.598 },
	{ id = 467555, type = 'spell', name = 'Motherlode', expansion = 'BFA', faction = 'Horde', minExpansion = 7, mapId = 862, mapX = 0.561, mapY = 0.598 },
	-- Mage Teleports - Alliance
	{ id = 281403, type = 'spell', name = 'Teleport: Boralus', expansion = 'BFA', class = 'MAGE', faction = 'Alliance', minExpansion = 7, mapId = 876, mapX = 0.578, mapY = 0.557 },
	{ id = 281400, type = 'spell', name = 'Portal: Boralus', expansion = 'BFA', class = 'MAGE', faction = 'Alliance', isPortal = true, minExpansion = 7, mapId = 876, mapX = 0.578, mapY = 0.557 },
	-- Mage Teleports - Horde
	{ id = 281404, type = 'spell', name = "Teleport: Dazar'alor", expansion = 'BFA', class = 'MAGE', faction = 'Horde', minExpansion = 7, mapId = 875, mapX = 0.568, mapY = 0.628 },
	{ id = 281402, type = 'spell', name = "Portal: Dazar'alor", expansion = 'BFA', class = 'MAGE', faction = 'Horde', isPortal = true, minExpansion = 7, mapId = 875, mapX = 0.568, mapY = 0.628 },
	-- Engineering
	{ id = 168807, type = 'toy', name = 'Wormhole Generator: Kul Tiras', expansion = 'BFA', isEngineering = true, faction = 'Alliance', minExpansion = 7 },
	{ id = 168808, type = 'toy', name = 'Wormhole Generator: Zandalar', expansion = 'BFA', isEngineering = true, faction = 'Horde', minExpansion = 7 },

	-- ==================== LEGION (7.x) ====================
	-- Dungeons
	{ id = 424153, type = 'spell', name = 'Black Rook Hold', expansion = 'Legion', minExpansion = 6, mapId = 619, mapX = 0.293, mapY = 0.328 },
	{ id = 393766, type = 'spell', name = 'Court of Stars', expansion = 'Legion', minExpansion = 6, mapId = 619, mapX = 0.495, mapY = 0.505 },
	{ id = 424163, type = 'spell', name = 'Darkheart Thicket', expansion = 'Legion', minExpansion = 6, mapId = 619, mapX = 0.370, mapY = 0.292 },
	{ id = 393764, type = 'spell', name = 'Halls of Valor', expansion = 'Legion', minExpansion = 6, mapId = 619, mapX = 0.639, mapY = 0.379 },
	{ id = 410078, type = 'spell', name = "Neltharion's Lair", expansion = 'Legion', minExpansion = 6, mapId = 619, mapX = 0.476, mapY = 0.288 },
	{ id = 373262, type = 'spell', name = 'Return to Karazhan', expansion = 'Legion', minExpansion = 6, mapId = 13, mapX = 0.500, mapY = 0.817 },
	{ id = 1254551, type = 'spell', name = 'Seat of the Triumvirate', expansion = 'Legion', minExpansion = 6 },
	-- Mage Teleports
	{ id = 224869, type = 'spell', name = 'Teleport: Dalaran (Broken Isles)', expansion = 'Legion', class = 'MAGE', minExpansion = 6, mapId = 619, mapX = 0.457, mapY = 0.639 },
	{ id = 224871, type = 'spell', name = 'Portal: Dalaran (Broken Isles)', expansion = 'Legion', class = 'MAGE', isPortal = true, minExpansion = 6, mapId = 619, mapX = 0.457, mapY = 0.639 },
	-- Engineering
	{ id = 151652, type = 'toy', name = 'Wormhole Generator: Argus', expansion = 'Legion', isEngineering = true, minExpansion = 6 },
	-- Toys
	{ id = 140192, type = 'toy', name = 'Dalaran Hearthstone', expansion = 'Legion', isHearthstone = true, minExpansion = 6, mapId = 619, mapX = 0.457, mapY = 0.639 },
	{ id = 141605, type = 'toy', name = "Flight Master's Whistle", expansion = 'Legion', minExpansion = 6 },
	-- Items
	{ id = 64457, type = 'item', name = 'The Last Relic of Argus', expansion = 'Legion', isHearthstone = true, minExpansion = 6 },
	{ id = 140324, type = 'toy', name = 'Mobile Telemancy Beacon', expansion = 'Legion', isHearthstone = true, minExpansion = 6 },

	-- ==================== WARLORDS OF DRAENOR (6.x) ====================
	-- Dungeons
	{ id = 159897, type = 'spell', name = 'Auchindoun', expansion = 'WoD', minExpansion = 5, mapId = 535, mapX = 0.462, mapY = 0.739 },
	{ id = 159895, type = 'spell', name = 'Bloodmaul Slag Mines', expansion = 'WoD', minExpansion = 5, mapId = 525, mapX = 0.500, mapY = 0.250 },
	{ id = 159901, type = 'spell', name = 'Everbloom', expansion = 'WoD', minExpansion = 5, mapId = 543, mapX = 0.595, mapY = 0.456 },
	{ id = 159900, type = 'spell', name = 'Grimrail Depot', expansion = 'WoD', minExpansion = 5, mapId = 543, mapX = 0.551, mapY = 0.317 },
	{ id = 159896, type = 'spell', name = 'Iron Docks', expansion = 'WoD', minExpansion = 5, mapId = 543, mapX = 0.454, mapY = 0.113 },
	{ id = 159899, type = 'spell', name = 'Shadowmoon Burial Grounds', expansion = 'WoD', minExpansion = 5, mapId = 539, mapX = 0.318, mapY = 0.425 },
	{ id = 159898, type = 'spell', name = 'Skyreach', expansion = 'WoD', minExpansion = 5, mapId = 542, mapX = 0.355, mapY = 0.336 },
	{ id = 159902, type = 'spell', name = 'Upper Blackrock Spire', expansion = 'WoD', minExpansion = 5, mapId = 33, mapX = 0.790, mapY = 0.337 },
	-- Mage Teleports - Alliance
	{ id = 176248, type = 'spell', name = 'Teleport: Stormshield', expansion = 'WoD', class = 'MAGE', faction = 'Alliance', minExpansion = 5, mapId = 572, mapX = 0.733, mapY = 0.470 },
	{ id = 176246, type = 'spell', name = 'Portal: Stormshield', expansion = 'WoD', class = 'MAGE', faction = 'Alliance', isPortal = true, minExpansion = 5, mapId = 572, mapX = 0.733, mapY = 0.470 },
	-- Mage Teleports - Horde
	{ id = 176242, type = 'spell', name = 'Teleport: Warspear', expansion = 'WoD', class = 'MAGE', faction = 'Horde', minExpansion = 5, mapId = 572, mapX = 0.733, mapY = 0.398 },
	{ id = 176244, type = 'spell', name = 'Portal: Warspear', expansion = 'WoD', class = 'MAGE', faction = 'Horde', isPortal = true, minExpansion = 5, mapId = 572, mapX = 0.733, mapY = 0.398 },
	-- Engineering
	{ id = 112059, type = 'toy', name = 'Wormhole Centrifuge', expansion = 'WoD', isEngineering = true, minExpansion = 5 },
	-- Toys/Items
	{ id = 110560, type = 'toy', name = 'Garrison Hearthstone', expansion = 'WoD', isHearthstone = true, minExpansion = 5 },
	{ id = 128353, type = 'item', name = "Admiral's Compass", expansion = 'WoD', isHearthstone = true, minExpansion = 5 },

	-- ==================== MISTS OF PANDARIA (5.x) ====================
	-- Dungeons
	{ id = 131225, type = 'spell', name = 'Gate of the Setting Sun', expansion = 'MoP', minExpansion = 4, mapId = 388, mapX = 0.759, mapY = 0.202 },
	{ id = 131222, type = 'spell', name = "Mogu'shan Palace", expansion = 'MoP', minExpansion = 4, mapId = 379, mapX = 0.590, mapY = 0.730 },
	{ id = 131232, type = 'spell', name = 'Scholomance', expansion = 'MoP', minExpansion = 4, mapId = 22, mapX = 0.686, mapY = 0.730 },
	{ id = 131231, type = 'spell', name = 'Scarlet Halls', expansion = 'MoP', minExpansion = 4, mapId = 18, mapX = 0.838, mapY = 0.347 },
	{ id = 131229, type = 'spell', name = 'Scarlet Monastery', expansion = 'MoP', minExpansion = 4, mapId = 18, mapX = 0.838, mapY = 0.347 },
	{ id = 131228, type = 'spell', name = 'Siege of Niuzao Temple', expansion = 'MoP', minExpansion = 4, mapId = 388, mapX = 0.346, mapY = 0.815 },
	{ id = 131206, type = 'spell', name = 'Shado-Pan Monastery', expansion = 'MoP', minExpansion = 4, mapId = 379, mapX = 0.369, mapY = 0.488 },
	{ id = 131205, type = 'spell', name = 'Stormstout Brewery', expansion = 'MoP', minExpansion = 4, mapId = 376, mapX = 0.359, mapY = 0.692 },
	{ id = 131204, type = 'spell', name = 'Temple of the Jade Serpent', expansion = 'MoP', minExpansion = 4, mapId = 371, mapX = 0.561, mapY = 0.578 },
	-- Mage Teleports - Alliance
	{ id = 132621, type = 'spell', name = 'Teleport: Vale of Eternal Blossoms', expansion = 'MoP', class = 'MAGE', faction = 'Alliance', minExpansion = 4, mapId = 424, mapX = 0.569, mapY = 0.553 },
	{
		id = 132620,
		type = 'spell',
		name = 'Portal: Vale of Eternal Blossoms',
		expansion = 'MoP',
		class = 'MAGE',
		faction = 'Alliance',
		isPortal = true,
		minExpansion = 4,
		mapId = 424,
		mapX = 0.569,
		mapY = 0.553,
	},
	-- Mage Teleports - Horde
	{ id = 132627, type = 'spell', name = 'Teleport: Vale of Eternal Blossoms', expansion = 'MoP', class = 'MAGE', faction = 'Horde', minExpansion = 4, mapId = 424, mapX = 0.524, mapY = 0.500 },
	{
		id = 132625,
		type = 'spell',
		name = 'Portal: Vale of Eternal Blossoms',
		expansion = 'MoP',
		class = 'MAGE',
		faction = 'Horde',
		isPortal = true,
		minExpansion = 4,
		mapId = 424,
		mapX = 0.524,
		mapY = 0.500,
	},
	-- Engineering
	{ id = 87215, type = 'toy', name = 'Wormhole Generator: Pandaria', expansion = 'MoP', isEngineering = true, minExpansion = 4 },

	-- ==================== CATACLYSM (4.x) ====================
	-- Dungeons
	{ id = 445424, type = 'spell', name = 'Grim Batol', expansion = 'Cata', minExpansion = 3, mapId = 12, mapX = 0.535, mapY = 0.556 },
	{ id = 424142, type = 'spell', name = 'Throne of the Tides', expansion = 'Cata', minExpansion = 3, mapId = 13, mapX = 0.316, mapY = 0.627 },
	{ id = 410080, type = 'spell', name = 'Vortex Pinnacle', expansion = 'Cata', minExpansion = 3, mapId = 12, mapX = 0.525, mapY = 0.937 },
	-- Mage Teleports - Alliance
	{ id = 88342, type = 'spell', name = 'Teleport: Tol Barad', expansion = 'Cata', class = 'MAGE', faction = 'Alliance', minExpansion = 3 },
	{ id = 88346, type = 'spell', name = 'Portal: Tol Barad', expansion = 'Cata', class = 'MAGE', faction = 'Alliance', isPortal = true, minExpansion = 3 },
	-- Mage Teleports - Horde
	{ id = 88344, type = 'spell', name = 'Teleport: Tol Barad', expansion = 'Cata', class = 'MAGE', faction = 'Horde', minExpansion = 3 },
	{ id = 88345, type = 'spell', name = 'Portal: Tol Barad', expansion = 'Cata', class = 'MAGE', faction = 'Horde', isPortal = true, minExpansion = 3 },
	-- Mage Teleports - Theramore/Stonard
	{ id = 49359, type = 'spell', name = 'Teleport: Theramore', expansion = 'Cata', class = 'MAGE', faction = 'Alliance', minExpansion = 3, mapId = 12, mapX = 0.592, mapY = 0.660 },
	{ id = 49360, type = 'spell', name = 'Portal: Theramore', expansion = 'Cata', class = 'MAGE', faction = 'Alliance', isPortal = true, minExpansion = 3, mapId = 12, mapX = 0.592, mapY = 0.660 },
	{ id = 49358, type = 'spell', name = 'Teleport: Stonard', expansion = 'Cata', class = 'MAGE', faction = 'Horde', minExpansion = 3, mapId = 13, mapX = 0.524, mapY = 0.798 },
	{ id = 49361, type = 'spell', name = 'Portal: Stonard', expansion = 'Cata', class = 'MAGE', faction = 'Horde', isPortal = true, minExpansion = 3, mapId = 13, mapX = 0.524, mapY = 0.798 },
	-- Items
	{ id = 58487, type = 'item', name = 'Potion of Deepholm', expansion = 'Cata', isHearthstone = true, minExpansion = 3 },
	{ id = 43824, type = 'toy', name = 'The Schools of Arcane Magic - Mastery', expansion = 'Cata', isHearthstone = true, minExpansion = 3 },

	-- ==================== WRATH OF THE LICH KING (3.x) ====================
	-- Dungeons
	{ id = 1254555, type = 'spell', name = 'Pit of Saron', expansion = 'WotLK', minExpansion = 2, mapId = 118, mapX = 0.547, mapY = 0.291 },
	-- Mage Teleports
	{ id = 53140, type = 'spell', name = 'Teleport: Dalaran (Northrend)', expansion = 'WotLK', class = 'MAGE', minExpansion = 2, mapId = 113, mapX = 0.480, mapY = 0.406 },
	{ id = 53142, type = 'spell', name = 'Portal: Dalaran (Northrend)', expansion = 'WotLK', class = 'MAGE', isPortal = true, minExpansion = 2, mapId = 113, mapX = 0.480, mapY = 0.406 },
	-- Engineering
	{ id = 48933, type = 'toy', name = 'Wormhole Generator: Northrend', expansion = 'WotLK', isEngineering = true, minExpansion = 2 },
	-- Items
	{ id = 52251, type = 'item', name = "Jaina's Locket", expansion = 'WotLK', isHearthstone = true, minExpansion = 2 },

	-- ==================== THE BURNING CRUSADE (2.x) ====================
	-- Mage Teleports
	{ id = 33690, type = 'spell', name = 'Teleport: Shattrath', expansion = 'TBC', class = 'MAGE', minExpansion = 1, mapId = 101, mapX = 0.418, mapY = 0.660 },
	{ id = 33691, type = 'spell', name = 'Portal: Shattrath', expansion = 'TBC', class = 'MAGE', isPortal = true, minExpansion = 1, mapId = 101, mapX = 0.418, mapY = 0.660 },
	{ id = 32271, type = 'spell', name = 'Teleport: Exodar', expansion = 'TBC', class = 'MAGE', faction = 'Alliance', minExpansion = 1, mapId = 12, mapX = 0.297, mapY = 0.248 },
	{ id = 32266, type = 'spell', name = 'Portal: Exodar', expansion = 'TBC', class = 'MAGE', faction = 'Alliance', isPortal = true, minExpansion = 1, mapId = 12, mapX = 0.297, mapY = 0.248 },
	{ id = 32272, type = 'spell', name = 'Teleport: Silvermoon', expansion = 'TBC', class = 'MAGE', faction = 'Horde', minExpansion = 1, mapId = 13, mapX = 0.567, mapY = 0.132 },
	{ id = 32267, type = 'spell', name = 'Portal: Silvermoon', expansion = 'TBC', class = 'MAGE', faction = 'Horde', isPortal = true, minExpansion = 1, mapId = 13, mapX = 0.567, mapY = 0.132 },
	-- Engineering
	{ id = 30544, type = 'toy', name = "Ultrasafe Transporter: Toshley's Station", expansion = 'TBC', isEngineering = true, minExpansion = 1, mapId = 101, mapX = 0.412, mapY = 0.344 },
	{ id = 30542, type = 'toy', name = 'Dimensional Ripper: Area 52', expansion = 'TBC', isEngineering = true, minExpansion = 1, mapId = 101, mapX = 0.524, mapY = 0.248 },
	-- Toys
	{ id = 151016, type = 'toy', name = 'Fractured Necrolyte Skull', expansion = 'TBC', isHearthstone = true, minExpansion = 6 },

	-- ==================== CLASSIC (1.x) ====================
	-- Mage Teleports - Alliance
	{ id = 3561, type = 'spell', name = 'Teleport: Stormwind', expansion = 'Classic', class = 'MAGE', faction = 'Alliance', minExpansion = 0, mapId = 13, mapX = 0.426, mapY = 0.708 },
	{ id = 10059, type = 'spell', name = 'Portal: Stormwind', expansion = 'Classic', class = 'MAGE', faction = 'Alliance', isPortal = true, minExpansion = 0, mapId = 13, mapX = 0.426, mapY = 0.708 },
	{ id = 3562, type = 'spell', name = 'Teleport: Ironforge', expansion = 'Classic', class = 'MAGE', faction = 'Alliance', minExpansion = 0, mapId = 13, mapX = 0.433, mapY = 0.580 },
	{ id = 11416, type = 'spell', name = 'Portal: Ironforge', expansion = 'Classic', class = 'MAGE', faction = 'Alliance', isPortal = true, minExpansion = 0, mapId = 13, mapX = 0.433, mapY = 0.580 },
	{ id = 3565, type = 'spell', name = 'Teleport: Darnassus', expansion = 'Classic', class = 'MAGE', faction = 'Alliance', minExpansion = 0, mapId = 12, mapX = 0.395, mapY = 0.115 },
	{ id = 11419, type = 'spell', name = 'Portal: Darnassus', expansion = 'Classic', class = 'MAGE', faction = 'Alliance', isPortal = true, minExpansion = 0, mapId = 12, mapX = 0.395, mapY = 0.115 },
	-- Mage Teleports - Horde
	{ id = 3567, type = 'spell', name = 'Teleport: Orgrimmar', expansion = 'Classic', class = 'MAGE', faction = 'Horde', minExpansion = 0, mapId = 12, mapX = 0.582, mapY = 0.426 },
	{ id = 11417, type = 'spell', name = 'Portal: Orgrimmar', expansion = 'Classic', class = 'MAGE', faction = 'Horde', isPortal = true, minExpansion = 0, mapId = 12, mapX = 0.582, mapY = 0.426 },
	{ id = 3563, type = 'spell', name = 'Teleport: Undercity', expansion = 'Classic', class = 'MAGE', faction = 'Horde', minExpansion = 0, mapId = 13, mapX = 0.439, mapY = 0.339 },
	{ id = 11418, type = 'spell', name = 'Portal: Undercity', expansion = 'Classic', class = 'MAGE', faction = 'Horde', isPortal = true, minExpansion = 0, mapId = 13, mapX = 0.439, mapY = 0.339 },
	{ id = 3566, type = 'spell', name = 'Teleport: Thunder Bluff', expansion = 'Classic', class = 'MAGE', faction = 'Horde', minExpansion = 0, mapId = 12, mapX = 0.465, mapY = 0.570 },
	{ id = 11420, type = 'spell', name = 'Portal: Thunder Bluff', expansion = 'Classic', class = 'MAGE', faction = 'Horde', isPortal = true, minExpansion = 0, mapId = 12, mapX = 0.465, mapY = 0.570 },
	-- Ancient Dalaran
	{ id = 120145, type = 'spell', name = 'Teleport: Ancient Dalaran', expansion = 'Classic', class = 'MAGE', minExpansion = 0, mapId = 13, mapX = 0.447, mapY = 0.407 },
	{ id = 120146, type = 'spell', name = 'Portal: Ancient Dalaran', expansion = 'Classic', class = 'MAGE', isPortal = true, minExpansion = 0, mapId = 13, mapX = 0.447, mapY = 0.407 },
	-- Engineering
	{ id = 18986, type = 'toy', name = 'Ultrasafe Transporter: Gadgetzan', expansion = 'Classic', isEngineering = true, minExpansion = 0, mapId = 12, mapX = 0.555, mapY = 0.823 },
	{ id = 18984, type = 'toy', name = 'Dimensional Ripper: Everlook', expansion = 'Classic', isEngineering = true, minExpansion = 0, mapId = 12, mapX = 0.599, mapY = 0.222 },
	-- Items
	{ id = 37863, type = 'item', name = "Direbrew's Remote", expansion = 'Classic', isHearthstone = true, minExpansion = 0 },
	{ id = 50287, type = 'item', name = 'Boots of the Bay', expansion = 'Classic', isHearthstone = true, minExpansion = 0, mapId = 13, mapX = 0.536, mapY = 0.940 },
}
