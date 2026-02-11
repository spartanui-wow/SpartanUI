---@class UnitAuraInfo
---@field applications number
---@field auraInstanceID number
---@field canApplyAura boolean
---@field charges number
---@field dispelName string?
---@field duration number
---@field expirationTime number
---@field icon number
---@field isBossAura boolean
---@field isFromPlayerOrPlayerPet boolean
---@field isHarmful boolean
---@field isPlayerAura boolean
---@field isHelpful boolean
---@field isNameplateOnly boolean
---@field isRaid boolean
---@field isStealable boolean
---@field maxCharges number
---@field name string
---@field nameplateShowAll boolean
---@field nameplateShowPersonal boolean
---@field points table Variable returns - Some auras return additional values that typically correspond to something shown in the tooltip, such as the remaining strength of an absorption effect.
---@field sourceUnit string?
---@field spellId number
---@field timeMod number
local UnitAuraInfo = {}

-- Retail Filter Mode: maps to Blizzard filter strings via C_UnitAuras.IsAuraFilteredOutByInstanceID
---@alias SUI.UF.Auras.RetailFilterMode
---| 'blizzard_default' # Uses HELPFUL|RAID (buffs) or HARMFUL (debuffs) — Blizzard decides what shows
---| 'player_auras' # Only your own auras (HELPFUL|PLAYER or HARMFUL|PLAYER)
---| 'player_buffs' # Your buffs only (HELPFUL|PLAYER)
---| 'player_debuffs' # Your debuffs only (HARMFUL|PLAYER)
---| 'raid_auras' # Auras flagged as raid-important by Blizzard (HELPFUL|RAID / HARMFUL|RAID)
---| 'raid_buffs' # Raid-important buffs (HELPFUL|RAID)
---| 'raid_debuffs' # Raid-important debuffs (HARMFUL|RAID)
---| 'healing_mode' # HoTs and combat-relevant buffs via RAID_IN_COMBAT filter (12.1+)
---| 'dispellable' # Dispellable debuffs (HARMFUL|RAID_PLAYER_DISPELLABLE)
---| 'external_defensives' # External defensive cooldowns (HELPFUL|EXTERNAL_DEFENSIVE)
---| 'big_defensives' # Major personal defensives (HELPFUL|BIG_DEFENSIVE)
---| 'crowd_control' # CC effects - stuns, roots, silences (HARMFUL|CROWD_CONTROL)
---| 'important_buffs' # Blizzard-flagged important buffs (HELPFUL|IMPORTANT)
---| 'important_debuffs' # Blizzard-flagged important debuffs (HARMFUL|IMPORTANT)
---| 'all' # No additional filtering beyond base HELPFUL/HARMFUL from oUF
---| 'all_buffs' # All buffs (HELPFUL)
---| 'all_debuffs' # All debuffs (HARMFUL)

---@class SUI.UF.Auras.RetailConfig
---@field filterMode SUI.UF.Auras.RetailFilterMode Filter preset mode
---@field customFilter? string Raw filter string (overrides filterMode) - e.g. "HELPFUL|RAID|PLAYER"
---@field allowMultiple? boolean Allow multiple displays of same aura type (reserved for future multi-display)
---@field displayId? number Display instance ID (reserved for future multi-display)
local SUIUnitFrameAuraRetailConfig = {}

---@class SUI.UF.Auras.ClassicConfig
---@field rules SUI.UF.Auras.ClassicRules
---@field whitelist table<string, boolean>
---@field blacklist table<string, boolean>
local SUIUnitFrameAuraClassicConfig = {}

---@class SUI.UF.Auras.ClassicRules
---@field duration SUI.UF.Auras.ClassicRules.Durations
---@field isPlayerAura boolean
---@field isBossAura boolean
---@field isHarmful boolean
---@field isHelpful boolean
---@field isMount boolean
---@field isRaid boolean
---@field isStealable boolean
---@field IsDispellableByMe boolean
---@field showPlayers boolean
---@field isFromPlayerOrPlayerPet boolean
---@field sourceUnit table<string, boolean>
local SUIUnitFrameAuraClassicRules = {}

---@alias SUI.UF.Auras.ClassicRules.Durations.mode
---| 'include'
---| 'exclude'

---@class SUI.UF.Auras.ClassicRules.Durations
---@field enabled boolean
---@field mode SUI.UF.Auras.ClassicRules.Durations.mode
---@field maxTime number
---@field minTime number
local SUIUnitFrameAuraClassicRulesDurations = {}
