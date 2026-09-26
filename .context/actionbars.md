# SpartanUI Action Bars

> SpartanUI's own action bar system (module `ActionBars`, `Modules/ActionBars/`). Added 2026-09-26.
> It replaces the old hard dependency on Bartender4, which is still supported as an alternative.

## Bar systems

`Modules/BarHandlers/Core.lua` (`SUI.Handlers.BarSystem`) decides what draws the bars. Each system registers with `AddBarSystem(name, init, enable, disable, move, refresh)`:

| System | File | What it does |
|---|---|---|
| `SpartanUI` | `Modules/ActionBars/ThemeLayout.lua` (registration) | Native bars built on LibActionButton-1.0 |
| `Bartender4` | `Modules/BarHandlers/Bartender4.lua` | Positions and scales Bartender4's bars |
| `WoW` | `Modules/BarHandlers/WoW.lua` | Leaves Blizzard's bars alone |

`BarHandler.DB.ActiveSystem` is the player's choice; `nil` means automatic. `GetEffectiveSystem()` resolves what actually runs:
- automatic: Bartender4 when it is loaded, otherwise SpartanUI
- Bartender4 chosen but not loaded: SpartanUI
- SpartanUI chosen while Bartender4 is still loaded: Bartender4 (and a chat warning) - two bar addons never run together
- SpartanUI chosen while Dominos or ElvUI's action bars are running: `None` (nothing is touched)

`SetChosenSystem()` stores the choice, disables/enables Bartender4 and reloads. Older versions wrote `ActiveSystem = 'WoW'` automatically whenever Bartender4 was missing; that value is cleared on load unless `systemChosen` is set, so those players get SpartanUI bars.

Anything outside the bar module that needs a bar goes through the handler, never through `_G.BT4Bar1`: `GetBarFrame(key)`, `GetBarOverlay(key)`, `PositionBar(key, ...)`, `SetBarTrayHidden(key, hidden)`.

## Logical bar keys

Bars are keyed by the **Bartender4 bar names** (`BT4Bar1`..`BT4Bar15`, `BT4BarPetBar`, `BT4BarStanceBar`, `BT4BarMicroMenu`, `BT4BarBagBar`, `BT4BarQueueStatus`). The key is used for:
- theme data (`barPositions` / `barScales` in `Themes/*/Style.lua`, bridged by `ThemeRegistry` into `BarSystem.BarPosition.BT4` / `BarScale.BT4`)
- MoveIt mover names, so a player's moved/scaled bars carry over when switching between Bartender4 and SpartanUI bars
- sliding tray frame lists

The actual frames are `SUI_ActionBar<N>` (buttons `SUI_ActionBar<N>Button<i>`), `SUI_PetBar`, `SUI_StanceBar`, `SUI_MicroMenu`, `SUI_BagBar`, `SUI_QueueStatus`. Theme position strings that anchor to a Bartender4 name (Gale anchors to `BT4Bar1`) are translated by `ActionBars:ParsePosition`.

## Files

| File | Purpose |
|---|---|
| `Core.lua` | Module, defaults (per game version), combat queue (`RunOutOfCombat`), `Activate`, `ApplyAll` |
| `Bar.lua` | Bar prototype: secure state header, grid layout, visibility driver, mouseover fade, backdrop, MoveIt mover |
| `ActionBar.lua` | LibActionButton bars, page driver, per-class default paging, button config |
| `HideBlizzard.lua` | Hides Blizzard's bars (Bartender4's nil-safe approach), Blizzard vehicle bar toggle |
| `PetStanceBars.lua` | Pet and stance bars reusing Blizzard's own buttons |
| `MicroBags.lua` | Micro menu, bag bar, Retail queue status eye |
| `Keybinds.lua` | Secure override-binding controller, LibKeyBound mode, binding names |
| `Fade.lua` | Global fade parent, Masque groups |
| `ThemeLayout.lua` | Theme positions/scales, fallback positions, drag reveal, bar system registration |
| `Options.lua` | AceConfig tree at `SUI.opt.args.ActionBars` |
| `Import/*.lua` | Bartender4, ElvUI and Dominos importers |
| `WizardPage.lua` | Import options under General > Bar System, setup wizard page |

## Key design decisions

**Buttons are scaled, not resized.** `Bar:LayoutButtons` sets `button:SetScale(height / nativeHeight)` and divides offsets by that scale. Blizzard's button art (bags, micro buttons, pet/stance buttons, the default action button border) has fixed-size textures that misalign when the frame itself is resized. Native sizes live in a weak side table, never on the button.

**Default button sizes match theme tuning.** Theme `barScales` were tuned against Bartender4 layouts: 45px action buttons on Retail, 36px elsewhere, 30px pet/stance, 30/37px bags. Keep those defaults or every theme's layout shifts. Theme scale is applied as `SUI.DB.scale * themeScale * 1.08696` (1/0.92 cancels the default UI scale), identical to the Bartender4 handler.

**Pet and stance bars reuse Blizzard's buttons.** `PetActionBar` and `StanceBar` are parented to the hidden frame but keep their events, so Blizzard's code keeps updating icons, cooldowns (secret-safe) and autocast, and `BONUSACTIONBUTTON`/`SHAPESHIFTBUTTON` bindings keep working natively.

**Key bindings.** Bars on Blizzard action pages use Blizzard's binding names (`ACTIONBUTTON`, `MULTIACTIONBAR1-7BUTTON`) as LibActionButton's `keyBoundTarget`; `UpdateKeybinds` redirects those keys to SpartanUI buttons with override bindings held by the secure frame `SUI_ActionBarBindings`. Its state driver drops the redirects in pet battles, and in vehicles when the Artwork "Use Blizzard Vehicle UI" setting is on (Blizzard's `GetActionButtonForID` then routes ACTIONBUTTON1-6 to `OverrideActionBar`). Bars 2 and 7-10 have no Blizzard binding and use `CLICK SUI_ActionBar<N>Button<i>:Keybind`, declared in the root `Bindings.xml`.

**Paging.** Bar 1's driver is `[overridebar][possessbar][shapeshift] possess; [bonusbar:5] possess;` + (paging enabled: `[bar:2] 2 ... [bar:6] 6;` + class rules) + `1`. `possess` is resolved inside the secure `_onstate-page` snippet (vehicle, override, temp shapeshift, bonus bar index), which works on every client. `paging[CLASS]` holds a player's custom rules; empty means the per-version default in `DefaultClassPaging`.

**Blizzard vehicle UI.** SpartanUI defaults to Blizzard's vehicle bar (`Artwork.VehicleUI = true`). In that mode `OverrideActionBar` stays alive and action/stance bars get `[overridebar][vehicleui] hide;` prepended to their visibility.

## Importers

Importers only work while the source addon is loaded (its SavedVariables are only in memory then). Each returns a result in SpartanUI's settings shape plus positions, scales and binding migrations; `ActionBars:RunImport` wipes the module DB, writes the result sparsely, stores scales/positions in MoveIt, migrates custom binding commands, optionally disables the source, then switches to SpartanUI bars (reload).

- Imported scales always apply (so imported sizes look the same); positions are optional because most players want bars in their SpartanUI theme's slots.
- Bartender4 profiles named `SpartanUI*` were positioned and scaled by SpartanUI itself; those already carry over through shared mover names, so the importer skips positions and scales for them.
- All three sources store sparse AceDB data; every importer merges the source addon's own live defaults before converting.

## Not built yet

- Extra action button / zone ability holders: left to Blizzard (EditMode on modern clients), as the previous Bartender4 setup did.
- Desaturate-on-cooldown, per-bar fonts, backdrop colour options, ElvUI export-string import.
