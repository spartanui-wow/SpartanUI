# Unify aura filtering on the 12.1 candidate filter system

**Status:** Deferred - waiting on upstream to settle
**Raised:** 2026-08-07
**Scope:** Retail only. Classic keeps its existing filtering.

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

1. **Extract a shared filter builder.** Lift `BuildCandidateFilters` and
   `BuildSpellIDMap` out of `Elements/Auras.lua` into `UF.Auras` so all three
   paths call the same code. Low risk, no behaviour change.
2. **Give AuraBars spell ID include/exclude** through that builder. This is real
   feature parity with aura groups and needs no architecture change.
3. **Only then** consider whether AuraBars should consume a container for
   candidate selection while continuing to draw its own bars.

Step 1 and 2 can happen at any time. Step 3 should wait.

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
