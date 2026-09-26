# LibClassicSpellActionCount-1.0

A small library that provides a function lib:GetActionCount(slot) that returns an action's reagent count for spells. With Patch 1.13.3, Blizzard's own implementation of GetActionCount was broken either deliberately or accidentally. This library offers a working replacement.

### lib:GetActionCount(slot)

Acts like a drop in replacement for Blizzard's own `GetActionCount`, but will also correctly return the reagent count for any spells or macros that show spells.

### lib:GetSpellReagentCount(idOrName)

Returns the reagent count for a given spell ID or name. Due to limitations of `GetSpellInfo`, when using a spell name, resolution will only work for spells known to the player. In contrast to `GetActionCount`, this returns `nil` if the spell is unknown/does not exist.
