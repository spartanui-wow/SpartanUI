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

**Paging.** A bar's driver is built in this order (first match wins): vehicle pages if `vehiclePaging` (`[overridebar][possessbar][shapeshift] possess; [bonusbar:5] possess;`), then the player's own `paging[CLASS]` rules, then `[bar:2..6]` if `manualPaging`, then the per-version `DefaultClassPaging` (bar 1 only, when there are no custom rules and `defaultClassPaging` is on), then the bar's own page. `possess`/`dragon`/`11` are resolved inside the secure `_onstate-page` snippet (vehicle, override, temp shapeshift, bonus bar index). `buttonOffset` shifts which slot of the page each button shows.

**Bars 13-15** exist wherever `MultiBar5` does (every current client, not only Retail): they are Blizzard's Action Bars 6-8 on pages 13-15.

**Leaving vehicles.** Button 12 of every bar with `vehiclePaging` gets LibActionButton's `custom` type on the vehicle/override/temp-shapeshift pages (pages 11-12 on clients without those functions): `VehicleExit()`. Blizzard's `PossessActionBar` is deliberately left alone - it only appears while possessing and carries the cancel button.

**Micro menu and bag bar fall back to Blizzard.** With either bar turned off, SpartanUI leaves Blizzard's `MicroMenu`/`BagsBar` alone instead of hiding the buttons; toggling it asks for a reload. While Blizzard's vehicle bar or pet battle UI takes the micro menu (`MicroMenu:SetParent` hook), the buttons are lent back and reclaimed afterwards.

**Text styling.** `text.hotkey/count/macro` in the module root is the shared style; an action bar with `customText = true` merges its own `bars[id].text` over it. Importers set this for bars whose fonts differ from bar 1 (ElvUI) or were changed (Bartender4).

**Blizzard vehicle UI.** SpartanUI defaults to Blizzard's vehicle bar (`Artwork.VehicleUI = true`). In that mode `OverrideActionBar` stays alive, action/stance bars get `[vehicleui] hide;` prepended, and the binding controller follows Bartender4: `[overridebar] override; [vehicleui] vehicle;` - in vehicle mode (or an override bar on a vehicle page, `actionpage > 10`) the ACTIONBUTTON1-6 keys get priority bindings to `OverrideActionBarButton1-6`. Plain override bars with no Blizzard skin are shown by Blizzard on the main bar, so bar 1 stays visible and pages into them.

**Combat rules.** The micro menu and bag bar are secure frames (they need visibility drivers), so their relayouts from Blizzard hooks (`UpdateMicroButtons`, `BagsBar.Layout`) are deferred with `RunOutOfCombat`. Blizzard only returns the micro menu through `MainActionBar`'s OnShow, which never fires while it is hidden, so `PET_BATTLE_CLOSE`, `UNIT_EXITED_VEHICLE` and `ActionBarController_UpdateAll` reclaim it.

## Importers

Importers only work while the source addon is loaded (its SavedVariables are only in memory then). Each returns a result in SpartanUI's settings shape plus positions, scales and binding migrations; `ActionBars:RunImport` wipes the module DB, writes the result sparsely, stores scales/positions in MoveIt, migrates custom binding commands, optionally disables the source, then switches to SpartanUI bars (reload).

- Everything is converted before anything is written, and the apply step runs in a pcall that restores the previous settings and movers on failure. The source addon is always turned off afterwards (two bar addons cannot run together).
- Dominos paging uses Dominos' own live `BarStates` registry (exact order and resolved `[form:N]` for the player's class); Bartender4 paging is converted for every class in the profile; ElvUI rules are kept whenever they differ from SpartanUI's default.
- Sizes and placement travel together. With "Also copy bar positions" on, the source's button sizes, scale and positions are copied. With it off (the wizard's default), everything that shapes a bar on screen (button size, buttons per row, growth corner, spacing, layering) is dropped and MoveIt is left alone, so bars keep the theme's size and slots.
- Bartender4 profiles named `SpartanUI*` were positioned and scaled by SpartanUI itself; those already carry over through shared mover names, so the importer skips positions and scales for them.
- All three sources store sparse AceDB data; every importer merges the source addon's own live defaults before converting.

**Themes placing bars.** `BarSystem:PositionBar` (sliding trays) stores an override via `ActionBars:SetThemeOverride`; `ApplyThemeToBar` uses it instead of the registry position so the loading-screen re-apply does not undo it. Overrides are dropped when the theme changes.

**Frames SpartanUI takes from Blizzard** (micro menu, bag bar, queue eye, extra action holder) only change hands cleanly at login, so a profile switch or reset that changes their `enabled` state asks for a reload (`CheckOwnershipChange`).

**Extra action / zone ability** holder (`BT4BarExtraActionBar`) is optional and off by default; when off, Blizzard/Edit Mode places them as before.

## Not built yet

- Desaturate-on-cooldown, cooldown text styling, fade animations, per-bar smart targeting / auto-assist, keybind mode for pet/stance buttons, ElvUI export-string import.
- LibActionButton treats WoW Forever as Retail (project id); unverified there.

## In-game test checklist

Run on each client (Retail, Mists, TBC Anniversary, Classic Era, Forever) with Bartender4, ElvUI and Dominos disabled unless a step says otherwise. `/sui bars` reports the running bar system and why.

1. Fresh profile: bars sit in the theme's slots at the theme's size; Blizzard's bars, bag bar, micro menu and XP strip are gone; no Lua errors after `/rl`.
2. Spells cast from every bar, by click and by key (bar 1 `ACTIONBUTTON`, bars 3-6 Blizzard multi-bar keys, bar 2 and 7-10 through the SpartanUI entries under Key Bindings > AddOns).
3. Paging: druid forms/prowl, rogue stealth, warrior stances (Classic), shift+number page swaps, skyriding (Retail).
4. Vehicle with "Use Blizzard Vehicle UI" on: Blizzard's vehicle bar shows, keys 1-6 drive it, SpartanUI bars hide. With it off: bar 1 shows the vehicle actions.
5. Pet battle (Retail/Mists): keys 1-6 reach the pet battle UI.
6. Pet bar appears with a pet; stance bar only for classes with forms; totem bar for Wrath-era shamans.
7. Micro menu and bags: every button works; micro menu moves into Blizzard's vehicle bar and pet battle UI and comes back afterwards.
8. `/sui move`: every enabled bar has a mover, disabled bars do not; moving/scaling survives `/rl`.
9. Options: every per-bar setting applies live out of combat and is deferred (not errored) in combat.
10. Sliding trays hide/show the pet, stance, micro and bag bars.
11. Imports: enable each source addon, import its current profile with and without positions, confirm the source addon is turned off and the bars match.
12. Switch Bar System to Bartender4 and back; the Bartender4 path must behave exactly as before.
