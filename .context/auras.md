# WoW 12.0.x Aura System

> SpartanUI's aura system supports all 13 Blizzard aura filters with full visual customization.

## All 13 WoW Aura Filters

**Basic Filters:**
- `HELPFUL` - All beneficial auras
- `HARMFUL` - All harmful auras

**Targeting Filters:**
- `PLAYER` - Only auras you cast
- `RAID` - Raid-important auras (major CDs, mechanics)
- `RAID_IN_COMBAT` - Combat-relevant auras (HoTs, active buffs)
- `RAID_PLAYER_DISPELLABLE` - Debuffs you can dispel

**Defensive/Offensive Filters:**
- `EXTERNAL_DEFENSIVE` - External saves (Guardian Spirit, Pain Suppression, etc.)
- `BIG_DEFENSIVE` - Major personal defensives
- `CROWD_CONTROL` - Stuns, roots, silences, fears

**Action Filters:**
- `CANCELABLE` - Auras you can right-click to remove
- `NOT_CANCELABLE` - Auras that cannot be removed

**Special Filters:**
- `INCLUDE_NAME_PLATE_ONLY` - Nameplate-specific auras
- `MAW` - Shadowlands Maw powers

**Removed by Blizzard (2026-07-14):** the `IMPORTANT` filter token was deleted from the game in a mid-2026 12.0.x build. The old `important_buffs`/`important_debuffs` filter modes are remapped to `raid_buffs`/`raid_debuffs` at runtime (`LEGACY_FILTER_REMAP` in `Modules/UnitFrames/Handlers/Auras.lua`) so saved user settings keep working.

## Filter Presets (Buffs)

| Preset | Filter String | Use Case |
|--------|--------------|----------|
| `all_buffs` | `HELPFUL` | Show everything (player default) |
| `player_buffs` | `HELPFUL\|PLAYER` | Only your buffs |
| `raid_buffs` | `HELPFUL\|RAID` | Major raid CDs |
| `healing_mode` | `HELPFUL\|RAID_IN_COMBAT` | HoTs and active buffs (target/raid default) |
| `external_defensives` | `HELPFUL\|EXTERNAL_DEFENSIVE` | Track external saves |
| `big_defensives` | `HELPFUL\|BIG_DEFENSIVE` | Track major defensives |

## Filter Presets (Debuffs)

| Preset | Filter String | Use Case |
|--------|--------------|----------|
| `all_debuffs` | `HARMFUL` | Show everything |
| `player_debuffs` | `HARMFUL\|PLAYER` | Only your debuffs (target default) |
| `raid_debuffs` | `HARMFUL\|RAID` | Raid mechanics (raid/party default) |
| `dispellable` | `HARMFUL\|RAID_PLAYER_DISPELLABLE` | Only what you can cleanse |
| `crowd_control` | `HARMFUL\|CROWD_CONTROL` | Stuns, roots, etc. (PvP) |

## Custom Filter Strings

Power users can create custom combinations by entering raw filter strings in the UI:

```lua
-- Example: Show your auras + raid-important auras
"HELPFUL|PLAYER|RAID"

-- Example: Show only dispellable debuffs you cast
"HARMFUL|PLAYER|RAID_PLAYER_DISPELLABLE"

-- Example: Show all crowd control effects
"HARMFUL|CROWD_CONTROL"
```

## Visual Customization Options

Every buff/debuff display has full layout control:

| Setting | Range | Description |
|---------|-------|-------------|
| **Icon Size** | 10-60px | Size of each aura icon |
| **Icon Count** | 1-40 | Maximum auras to display |
| **Rows** | 1-10 | Number of rows |
| **Spacing** | 0-10px | Space between icons |
| **Horizontal Growth** | Left/Right | Direction icons grow horizontally |
| **Vertical Growth** | Up/Down | Direction icons grow vertically |

## Retail Defaults (WoW 12.0.5)

**Player Frame:**
- Buffs: Show all (`all_buffs`)
- Debuffs: Show all (`all_debuffs`)

**Target Frame:**
- Buffs: HoTs + combat buffs (`healing_mode`)
- Debuffs: Player-cast only (`player_debuffs`)

**Raid/Party Frames:**
- Buffs: HoTs + combat buffs (`healing_mode`)
- Debuffs: All raid-relevant (`raid_debuffs`)

## Midnight Theme

Clean theme with modern aesthetics:

**Player Frame:**
- 32 buffs (28px, 4 rows, grow up)
- 16 debuffs (32px, 2 rows, grow down)

**Target Frame:**
- 16 buffs (26px, 2 rows, HoTs)
- 16 debuffs (30px, 2 rows, player-only)

**Raid Frames:**
- Compact 5x8 layout
- 3 HoT buffs (18px)
- 5 raid debuffs (22px)
- No portraits/castbars for cleaner look

## Key Files

| File | Purpose |
|------|---------|
| `Modules/UnitFrames/Handlers/Auras.lua` | Core filter logic, all 14 filter constants |
| `Modules/UnitFrames/Handlers/_Auras.Definition.lua` | Type definitions for filter modes |
| `Modules/UnitFrames/Elements/Buffs.lua` | Buff element with visual customization UI |
| `Modules/UnitFrames/Elements/Debuffs.lua` | Debuff element with visual customization UI |
| `Themes/Midnight/Style.lua` | Midnight theme registration |
| `Core/Framework.lua` (line ~1200) | Midnight frame configs in `SUI.DB.Styles.Midnight.Frames` |

## Implementation Notes

- Filter system uses `C_UnitAuras.IsAuraFilteredOutByInstanceID()` for Retail
- Classic uses legacy rules system (duration, whitelist/blacklist, boolean filters)
- Sorting limited to priority in Retail (time/name disabled due to secret values)
- Duration text disabled in Retail (cooldown spiral shows duration instead)
- Custom filter strings override preset selection
- All settings persist per-profile via AceDB

## Migration from Old System

The system automatically handles legacy configs:
- Old 5-filter system (`blizzard_default`, `player_auras`, `raid_auras`, `healing_mode`, `all`) still works
- New presets use more specific names (`all_buffs`, `player_buffs`, etc.)
- Existing user settings preserved and migrated transparently
