local _, ns = ...
local P = ns.Plates

-- Channel lengths for clients that announce a channel (UNIT_SPELLCAST_CHANNEL_START with its
-- spell id) but give no channel info for other units, as older Classic clients did. Today's
-- Classic Era documents UnitChannelInfo for any unit, so this is a backstop: the cast part reads
-- it only on clients without secrets, when a channel start arrives and the unit reports no
-- cast, so the table never changes anything on a client whose channel info works.
--
-- Every rank is listed by id, because rank lengths can differ (Arcane Missiles ranks 1 and 2).
-- An id that is missing (an NPC copy of a player spell) falls back to the spell's name, using
-- the longest length listed for that name. Lengths were checked on 2026-10-11 against Wowhead's
-- Classic Era database ("Channeled (N sec cast)"); Mind Control, Eyes of the Beast, the
-- bandages and the death ray were checked again on 2026-10-12. `unverified` lists what still
-- needs an in-game look.

P.Data = P.Data or {}

---@class Plates.ClassicChannels
---@field byId table<integer, number> Spell id -> channel length in seconds
---@field source string
---@field checked string
---@field unverified table<string, string> What still needs an in-game check
local Channels = {
	source = 'wowhead classic (1.15) tooltips',
	checked = '2026-10-12',
	unverified = {
		otherUnits = 'whether any current Classic client still hides channel info for other units',
		npcNames = 'NPC copies of player channels share the player spell name and length',
	},
	byId = {
		-- Mage
		[5143] = 3, -- Arcane Missiles rank 1
		[5144] = 4, -- rank 2
		[5145] = 5,
		[8416] = 5,
		[8417] = 5,
		[10211] = 5,
		[10212] = 5,
		[25345] = 5,
		[10] = 8, -- Blizzard
		[6141] = 8,
		[8427] = 8,
		[10185] = 8,
		[10186] = 8,
		[10187] = 8,
		[12051] = 8, -- Evocation
		-- Priest
		[15407] = 3, -- Mind Flay
		[17311] = 3,
		[17312] = 3,
		[17313] = 3,
		[17314] = 3,
		[18807] = 3,
		[2096] = 60, -- Mind Vision
		[10909] = 60,
		[605] = 60, -- Mind Control
		[10911] = 60,
		[10912] = 60,
		[10797] = 6, -- Starshards
		[19296] = 6,
		[19299] = 6,
		[19302] = 6,
		[19303] = 6,
		[19304] = 6,
		[19305] = 6,
		-- Warlock
		[689] = 5, -- Drain Life
		[699] = 5,
		[709] = 5,
		[7651] = 5,
		[11699] = 5,
		[11700] = 5,
		[5138] = 5, -- Drain Mana
		[6226] = 5,
		[11703] = 5,
		[11704] = 5,
		[1120] = 15, -- Drain Soul
		[8288] = 15,
		[8289] = 15,
		[11675] = 15,
		[755] = 10, -- Health Funnel
		[3698] = 10,
		[3699] = 10,
		[3700] = 10,
		[11693] = 10,
		[11694] = 10,
		[11695] = 10,
		[1949] = 15, -- Hellfire
		[11683] = 15,
		[11684] = 15,
		[5740] = 8, -- Rain of Fire
		[6219] = 8,
		[11677] = 8,
		[11678] = 8,
		-- Druid
		[740] = 10, -- Tranquility
		[8918] = 10,
		[9862] = 10,
		[9863] = 10,
		[16914] = 10, -- Hurricane
		[17401] = 10,
		[17402] = 10,
		-- Hunter
		[1510] = 6, -- Volley
		[14294] = 6,
		[14295] = 6,
		[136] = 5, -- Mend Pet
		[3111] = 5,
		[3661] = 5,
		[3662] = 5,
		[13542] = 5,
		[13543] = 5,
		[13544] = 5,
		[6197] = 60, -- Eagle Eye
		[1002] = 60, -- Eyes of the Beast
		[1515] = 20, -- Tame Beast
		-- Anyone
		[746] = 6, -- First Aid (Linen Bandage)
		[1159] = 6, -- Heavy Linen Bandage
		[3267] = 7, -- Wool Bandage
		[3268] = 7, -- Heavy Wool Bandage
		[7926] = 8, -- Silk Bandage
		[7927] = 8, -- Heavy Silk Bandage
		[10838] = 8, -- Mageweave Bandage
		[10839] = 8, -- Heavy Mageweave Bandage
		[18608] = 8, -- Runecloth Bandage
		[18610] = 8, -- Heavy Runecloth Bandage
		[13278] = 4, -- Gnomish Death Ray
	},
}
P.Data.ClassicChannels = Channels

local function SpellName(spellID)
	if C_Spell and C_Spell.GetSpellName then
		local ok, name = pcall(C_Spell.GetSpellName, spellID)
		if ok and type(name) == 'string' then
			return name
		end
	end
	local legacy = _G.GetSpellInfo
	if legacy then
		local ok, name = pcall(legacy, spellID)
		if ok and type(name) == 'string' then
			return name
		end
	end
	return nil
end

---Spell name -> longest listed length, built on first use (names follow the client language).
---@return table<string, number>
function Channels:Names()
	if not self.names then
		local names = {}
		for spellID, seconds in pairs(self.byId) do
			local name = SpellName(spellID)
			if name and (names[name] or 0) < seconds then
				names[name] = seconds
			end
		end
		self.names = names
	end
	return self.names
end

---Channel length for a plain spell id, or nil when the spell is not listed.
---@param spellID integer
---@return number|nil seconds
function Channels:Duration(spellID)
	local tier = P.Data.CLIENT_TIERS[P.Caps:Client()]
	if tier ~= P.Data.CLIENT_TIERS.era then
		return nil
	end
	if type(spellID) ~= 'number' then
		return nil
	end
	local seconds = self.byId[spellID]
	if seconds then
		return seconds
	end
	local name = SpellName(spellID)
	return name and self:Names()[name] or nil
end
