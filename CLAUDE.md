# SpartanUI — CLAUDE.md

This file covers SpartanUI-specific guidance. It **inherits** all shared rules from the root `C:\code\CLAUDE.md` and `C:\code\.context\` files — do not duplicate content that lives there.

For shared patterns (logging, annotations, StyLua, API lookups, testing, pitfalls), see the root `.context/` files.

## SpartanUI Context Files

- @.context/module-creation.md — How to create new SpartanUI modules (SUI:NewModule, DBM, options, localization)
- @.context/Database.md — SUI.DBM Configuration Override Pattern (full API reference)
- @.context/auras.md — WoW 12.0.1 aura system, all 14 filters, presets, visual customization

## Project Overview

SpartanUI is a comprehensive World of Warcraft addon that provides a complete user interface overhaul. It moves interface elements to the bottom of the screen to free up screen real estate and includes modular components for various gameplay features.

## Core Architecture

- **Core/Framework.lua** — Main addon initialization, SUI object setup, library management
  - Sets default module libraries: `SUI:SetDefaultModuleLibraries('AceEvent-3.0', 'AceTimer-3.0')`
  - All modules automatically have AceEvent-3.0 and AceTimer-3.0 mixed in
- **Framework.Definition.lua** — Type definitions and framework structure
- **SpartanUI.toc** — Addon manifest defining load order and dependencies
- **Modules/** — Feature modules (Minimap, UnitFrames, Artwork, etc.)
- **Core/Handlers/** — Core handlers (Events, Options, Profiles, etc.)
- **Themes/** — Visual themes (Classic, War, Fel, Digital, etc.) with Style.lua/xml + assets
- **libs/** — Third-party libraries (Ace3, oUF, LibSharedMedia, StdUi)

### Unit Frames Structure

```
Modules/UnitFrames/
├── Framework.lua           # Main UF framework, LoadDB(), GetPresetForFrame()
├── Options.lua             # UF options with per-group preset selectors
├── Elements/               # Individual UF elements (Health, Power, etc.)
├── Units/                  # Unit-specific configurations
├── Presets/                # Preset data (AuraPresets, etc.)
└── Handlers/               # UF handlers (Style, Auras, Preset)
    ├── Preset.lua          # Per-frame preset registry and resolution
    ├── _Preset.Definition.lua  # Preset type annotations
    └── Style.lua           # Artwork style registry (visual identity)
```

### Per-Frame Preset System

Each frame group can use a different UF preset independently. Themes provide 1-click defaults.

- **DB**: `UF.DB.Presets = { player='War', raid='Grid', party='Classic', ... }`
- **Resolution**: `UF:GetPresetForFrame(frameName)` resolves frame -> group leader -> active preset
- **User overrides**: `UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName]`
- **Never use**: `UF.DB.Style` or `UF.DB.UserSettings[UF.DB.Style]` (deprecated)

## Key Commands

- `/sui` — Opens main options window
- `/sui > ModuleName` — Navigate to specific module (e.g. `/sui > Artwork`)
- `/rl` — Reload UI

## Key File Locations

- **Core/Framework.lua:1-100** — Main addon initialization and library setup
- **Core/Handlers/ChatCommands.lua** — Chat command handling
- **Modules/LoadAll.xml** — Module loading order

## Dependencies

- **Required**: Bartender4 (action bar addon), Libs-AddonTools (UI system and utilities)
- **Optional**: Various other addons for enhanced functionality

## WoW 12.0 Secret Values System

**CRITICAL**: WoW 12.0+ introduced a "secret values" system that restricts tainted code from operating on combat API data. This affects ALL unit frame and aura code.

**Quick rules:**
- ✅ CAN: Store secrets, pass to functions, check truthiness (`if value then`), use formatting functions, pass to Blizzard APIs
- ❌ CANNOT: Compare (`==`, `>`, etc.), do arithmetic (`+`, `-`, etc.), use as table keys, iterate tables with secret keys
- **Solution**: Always check `canaccessvalue(value)` before comparisons/arithmetic/table indexing
- **Common secrets**: `UnitHealth()`, `UnitGUID()`, `aura.duration`, `aura.dispelName`, `aura.auraInstanceID`

See `C:\code\.context\common-pitfalls.md` section "2026-02-07/2026-02-12: WoW 12.0 Secret Values System" for complete reference with examples, safe patterns, and API documentation.
