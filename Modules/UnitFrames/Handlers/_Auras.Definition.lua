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
---| 'player_auras' # Only your own auras (uses oUF-safe isPlayerAura property)
---| 'raid_auras' # Auras flagged as raid-important by Blizzard (HELPFUL|RAID / HARMFUL|RAID)
---| 'healing_mode' # HoTs and combat-relevant buffs via RAID_IN_COMBAT filter (12.1+)
---| 'all' # No additional filtering beyond base HELPFUL/HARMFUL from oUF

---@class SUI.UF.Auras.RetailConfig
---@field filterMode SUI.UF.Auras.RetailFilterMode
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
