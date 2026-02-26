---@class SUI.UF
local UF = SUI.UF

-- Class-specific spell lists for AuraWatch
-- These spells are important buffs/debuffs that healers and raid leaders want to track
-- Organized by the class that CASTS the buff (not who receives it)

---@class SUI.UF.AuraWatchSpells
local AuraWatchSpells = {}
UF.AuraWatchSpells = AuraWatchSpells

-- Raid buffs that affect the whole group (important for buff tracking)
AuraWatchSpells.RaidBuffs = {
	-- Druid
	[1126] = { name = 'Mark of the Wild', class = 'DRUID' },
	-- Mage
	[1459] = { name = 'Arcane Intellect', class = 'MAGE' },
	-- Priest
	[21562] = { name = 'Power Word: Fortitude', class = 'PRIEST' },
	-- Warrior
	[6673] = { name = 'Battle Shout', class = 'WARRIOR' },
	-- Paladin
	[465] = { name = 'Devotion Aura', class = 'PALADIN' },
	-- Demon Hunter
	[390152] = { name = 'Chaos Brand', class = 'DEMONHUNTER' },
	-- Death Knight
	[57330] = { name = 'Horn of Winter', class = 'DEATHKNIGHT' },
	-- Evoker
	[381748] = { name = 'Blessing of the Bronze', class = 'EVOKER' },
	-- Monk
	[389684] = { name = 'Close to Heart', class = 'MONK' },
}

-- Important defensive cooldowns that healers want to track
AuraWatchSpells.Defensives = {
	-- Paladin
	[1022] = { name = 'Blessing of Protection', class = 'PALADIN' },
	[6940] = { name = 'Blessing of Sacrifice', class = 'PALADIN' },
	[204018] = { name = 'Blessing of Spellwarding', class = 'PALADIN' },
	[1044] = { name = 'Blessing of Freedom', class = 'PALADIN' },
	-- Priest
	[33206] = { name = 'Pain Suppression', class = 'PRIEST' },
	[47788] = { name = 'Guardian Spirit', class = 'PRIEST' },
	[271466] = { name = 'Luminous Barrier', class = 'PRIEST' },
	-- Druid
	[102342] = { name = 'Ironbark', class = 'DRUID' },
	-- Monk
	[116849] = { name = 'Life Cocoon', class = 'MONK' },
	-- Shaman
	[974] = { name = 'Earth Shield', class = 'SHAMAN' },
	[201633] = { name = 'Earthen Wall Totem', class = 'SHAMAN' },
	-- Evoker
	[357170] = { name = 'Time Dilation', class = 'EVOKER' },
	[370960] = { name = 'Emerald Communion', class = 'EVOKER' },
}

-- HoTs that healers want to track on group members
AuraWatchSpells.HealerHoTs = {
	-- Druid
	[774] = { name = 'Rejuvenation', class = 'DRUID' },
	[8936] = { name = 'Regrowth', class = 'DRUID' },
	[33763] = { name = 'Lifebloom', class = 'DRUID' },
	[48438] = { name = 'Wild Growth', class = 'DRUID' },
	[102351] = { name = 'Cenarion Ward', class = 'DRUID' },
	[155777] = { name = 'Germination', class = 'DRUID' },
	-- Priest (Holy)
	[139] = { name = 'Renew', class = 'PRIEST' },
	[41635] = { name = 'Prayer of Mending', class = 'PRIEST' },
	[77489] = { name = 'Echo of Light', class = 'PRIEST' },
	-- Priest (Discipline)
	[17] = { name = 'Power Word: Shield', class = 'PRIEST' },
	[194384] = { name = 'Atonement', class = 'PRIEST' },
	[1253593] = { name = 'Void Shield', class = 'PRIEST' },
	-- Shaman
	[61295] = { name = 'Riptide', class = 'SHAMAN' },
	-- Paladin
	[53563] = { name = 'Beacon of Light', class = 'PALADIN' },
	[156910] = { name = 'Beacon of Faith', class = 'PALADIN' },
	[200025] = { name = 'Beacon of Virtue', class = 'PALADIN' },
	[223306] = { name = 'Bestow Faith', class = 'PALADIN' },
	[156322] = { name = 'Eternal Flame', class = 'PALADIN' },
	[1244893] = { name = 'Beacon of the Savior', class = 'PALADIN' },
	-- Monk
	[115175] = { name = 'Soothing Mist', class = 'MONK' },
	[119611] = { name = 'Renewing Mist', class = 'MONK' },
	[124682] = { name = 'Enveloping Mist', class = 'MONK' },
	[191840] = { name = 'Essence Font', class = 'MONK' },
	[325209] = { name = 'Enveloping Breath', class = 'MONK' },
	[450769] = { name = 'Aspect of Harmony', class = 'MONK' },
	-- Evoker (Preservation)
	[355941] = { name = 'Dream Breath', class = 'EVOKER' },
	[363502] = { name = 'Dream Flight', class = 'EVOKER' },
	[364343] = { name = 'Echo', class = 'EVOKER' },
	[366155] = { name = 'Reversion', class = 'EVOKER' },
	[367230] = { name = 'Reversion', class = 'EVOKER' },
	[367364] = { name = 'Echo Reversion', class = 'EVOKER' },
	[373267] = { name = 'Lifebind', class = 'EVOKER' },
	[376788] = { name = 'Echo Dream Breath', class = 'EVOKER' },
}

-- Augmentation Evoker support buffs that healers/raiders want to track
AuraWatchSpells.AugmentationBuffs = {
	[360827] = { name = 'Blistering Scales', class = 'EVOKER' },
	[395152] = { name = 'Ebon Might', class = 'EVOKER' },
	[410089] = { name = 'Prescience', class = 'EVOKER' },
	[410263] = { name = "Inferno's Blessing", class = 'EVOKER' },
	[410686] = { name = 'Symbiotic Bloom', class = 'EVOKER' },
	[413984] = { name = 'Shifting Sands', class = 'EVOKER' },
}

-- Get spells relevant to the player's class
---@param playerClass string
---@return table<integer, table>
function AuraWatchSpells:GetClassSpells(playerClass)
	local spells = {}

	-- Always include basic raid buffs
	for spellID, data in pairs(self.RaidBuffs) do
		-- Include the player's own class buffs, or common buffs others might have
		if data.class == playerClass then
			spells[spellID] = { onlyIfCastable = true, anyUnit = true, onlyShowMissing = true }
		end
	end

	-- Healers get HoTs and defensives
	local healerClasses = {
		DRUID = true,
		PRIEST = true,
		PALADIN = true,
		SHAMAN = true,
		MONK = true,
		EVOKER = true,
	}

	if healerClasses[playerClass] then
		-- Add healer's own HoTs
		for spellID, data in pairs(self.HealerHoTs) do
			if data.class == playerClass then
				spells[spellID] = { onlyIfCastable = true, anyUnit = true, onlyShowMissing = false }
			end
		end

		-- Add defensives that this class can cast
		for spellID, data in pairs(self.Defensives) do
			if data.class == playerClass then
				spells[spellID] = { onlyIfCastable = true, anyUnit = true, onlyShowMissing = false }
			end
		end

		-- Add Augmentation Evoker buffs for Evokers
		if playerClass == 'EVOKER' then
			for spellID, _ in pairs(self.AugmentationBuffs) do
				spells[spellID] = { onlyIfCastable = true, anyUnit = true, onlyShowMissing = false }
			end
		end
	end

	return spells
end

-- Get all trackable spells (for the options UI)
---@return table<integer, table>
function AuraWatchSpells:GetAllSpells()
	local spells = {}

	for spellID, data in pairs(self.RaidBuffs) do
		spells[spellID] = data
	end

	for spellID, data in pairs(self.Defensives) do
		spells[spellID] = data
	end

	for spellID, data in pairs(self.HealerHoTs) do
		spells[spellID] = data
	end

	for spellID, data in pairs(self.AugmentationBuffs) do
		spells[spellID] = data
	end

	return spells
end

-- Get default watched spells based on player class
---@return table<integer, table>
function AuraWatchSpells:GetDefaults()
	local _, playerClass = UnitClass('player')
	if not playerClass then
		-- Fallback: return empty watched list if class detection fails
		return {
			['**'] = { onlyIfCastable = true, anyUnit = true, onlyShowMissing = true, point = 'CENTER', xOffset = 0, yOffset = 0, displayInCombat = false },
		}
	end

	local classSpells = self:GetClassSpells(playerClass)
	local watched = {
		['**'] = { onlyIfCastable = true, anyUnit = true, onlyShowMissing = true, point = 'CENTER', xOffset = 0, yOffset = 0, displayInCombat = false },
	}

	for spellID, settings in pairs(classSpells) do
		watched[spellID] = settings
	end

	-- Class-specific spells are already added by GetClassSpells()
	-- DO NOT add all raid buffs - this prevents showing "Arcane Int missing" on Druid, etc.

	return watched
end
