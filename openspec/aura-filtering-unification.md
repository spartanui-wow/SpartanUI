# Unify aura filtering on the 12.1 candidate filter system

**Status:** Steps 1 and 2 done. Dispel, DefensiveIndicator and CornerIndicators
rebuilt on aura slots (2026-08-11). Step 3 and name-matched corners still open.
**Raised:** 2026-08-07
**Scope:** Step 3 is Retail only. Steps 1 and 2 apply on every version.

## Problem

SpartanUI filters auras in three unrelated ways:

| Path | How it filters | File |
|---|---|---|
| `AuraGroups` | Blizzard filter string + `candidateFilters` | `Modules/UnitFrames/Handlers/AurasRetail.lua` |
| `AuraTracker` | `candidateFilters.includeSpellIDs`, one spell per slot | `Modules/UnitFrames/Elements/AuraTracker.lua` |
| `AuraBars` | Manual `GetAuraSlots` scan, then Lua-side filtering | `libs/oUF_Plugins/oUF_AuraBars.lua` |

Only the first two describe what they want to the engine. AuraBars still reads
every aura and decides in Lua, which means its filtering cannot reuse anything
the other two do - spell ID lists, duration limits, dispel types are all
separate implementations or simply missing.

The end state is one filtering layer that every aura display feeds through.

## Why this is deferred rather than done

- **No forcing function.** The `AuraGroups` rewrite was mandatory: the old oUF
  aura contract was deleted. AuraBars is not in that position. It runs on a
  self-contained plugin that never used oUF's aura element, and its Retail path
  already routes duration through `C_DurationUtil` rather than doing arithmetic
  on secret values. It works today.
- **Containers draw icons, not bars.** `AuraContainer` produces `AuraButton`
  objects. A bar needs a variable-width statusbar, its own text layout and
  per-bar colouring. ElvUI is hitting this now - their recent aura bar commits
  read `bars getting out of hand - trying something else`, `what is wrong with
  these bars.. idek` and `temp disable aurabar execution`. They ended up using
  the container for filtering while still drawing bars themselves.
- **Classic cost.** Much of our AuraBars size is the shared Classic path
  (LibHealComm, legacy `UnitAura`, no-container fallbacks). Containers are
  Retail-only, so a migration means maintaining two implementations.

## Planned approach

Take the filtering, not the drawing.

1. ~~**Extract a shared filter builder.**~~ **Done.** `BuildCandidateFilters`
   now lives on `UF.Auras` alongside `BuildSpellIDMap`; aura groups and the
   spell tracker both call it.
2. ~~**Give AuraBars spell ID include/exclude.**~~ **Done.** Both lists are
   honoured on Retail (`RetailAuraFilter`) and Classic (`ClassicAuraFilter`),
   with options under "Spell lists". On Retail an unreadable secret spell ID is
   kept when only an exclude list is set and dropped when an include list
   demands a specific spell, so a hidden aura cannot bypass an allow list.
3. **Only then** consider whether AuraBars should consume a container for
   candidate selection while continuing to draw its own bars. **Still pending.**

## Also pending: the indicator elements still read the aura list

Dispel, CornerIndicators, DefensiveIndicator and AuraDesigner all call
`AuraUtil.ForEachAura` or `C_UnitAuras.GetAuraDataByIndex`. On 12.1 addon code
may not read the aura list while auras are secret - the call **throws** rather
than returning nothing:

```
GetAuraSlots(): Auras cannot be accessed when secret while tainted by 'SpartanUI'
```

**Dispel and DefensiveIndicator are now rebuilt on aura slots** and no longer
read the aura list on Retail. `UF.Auras:CreateWatcher` creates a one-aura slot
and hands its button to a callback; artwork is attached to that button, so the
engine shows and hides it along with the aura.

**CornerIndicators is converted for the cases that can be described.** A corner
tracking a dispel type uses `includeDispelTypes`; one tracking a spell ID uses
`includeSpellIDs`. Both get their own slot via `UF.Auras:CreateWatcher`.

The one remaining gap is a corner that matches a **buff by name**. There is no
candidate filter for a name, so it still scans and stays quiet while auras are
secret. Closing that needs the name resolved to a spell ID at configuration
time, which changes what the option stores - worth doing when the corner
options are next touched.

The pattern to follow is `UF.Auras:CreateWatcher`, which ElvUI arrives at the
same way in `E:Auras_SetHighlight` (`Modules/Auras/Containers.lua`): an
`AddAuraSlot` whose button carries the artwork.

Note that slots and groups are **separate registries with separate keys**. The
group APIs reject a slot key, which is why slot updates use
`SetAuraSlotCandidateFilters` rather than `SetAuraGroupFilterString`.

Remaining work is step 3, and name-matched corners.

## Trigger to revisit

When ElvUI's aura bar work stabilises - concretely, when their commit titles stop
expressing uncertainty and `origin/ptr` goes a full audit cycle without reverting
aura bar changes. Until then we would be porting a design they are still
discovering, and the 12.1-specific parts would need rewriting again when it
settles.

Track upstream state via the ElvUI cross-check audit; see the bookmark note for
the current commit and the confirmed vs unconfirmed `candidateFilters` keys.

## Constraints to respect

- Only four `candidateFilters` keys are confirmed against a live client:
  `includeSpellIDs`, `excludeSpellIDs`, `includeDispelTypes`, `maxDuration`.
  An unsupported key **fails open** - the group matches every aura instead of
  erroring - so never trust an unconfirmed key blind. See
  `UF.Auras:ValidateCandidateKeys`.
- Group options are frozen at `AddGroup` time. Only the filter string can be
  changed afterwards, via `SetAuraGroupFilterString`.
- Setting any `maxDuration` also hides permanent auras.
