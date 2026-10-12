# Nameplates (portable core + SpartanUI host)

> Module `Modules/Nameplates/`. Started 2026-10-11 (rebuild, plan `openspec/nameplates-revamp.md`, Revision 3).
> Read this file plus the plan section for your task. It is the contract every part of the module builds against.

## 1. What it is

A new nameplate engine that draws its own plates on all six clients (Retail 12.1, WoW Forever, Mists, Titan, TBC Anniversary, Classic Era). It replaces `Modules/Nameplates.lua` (the old oUF-based module) in Phase 4b.

- **Portable core** (Messenger rule, Decision 3): nothing under `Modules/Nameplates/` outside `Host/` may name SpartanUI, `SUI`, SpartanUI paths, strings, assets, commands or globals. The host hands everything host-specific to `P:Initialize(hostConfig)`.
- **Own SavedVariable**: `SpartanUINameplatesDB` (account-wide TOC line), AceDB with one shared `Default` profile.
- **Dependencies**: LibAT (Ace3, LibStub, CallbackHandler), LibSharedMedia (handed in by the host), LibRangeCheck-3.0 from Phase 5 (found through LibStub, optional).
- **No oUF.** Our own renderer: a style is data, parts are drawn by registered part implementations, data comes from a Source object (live unit or sample).
- **Inert when off**: loading the core registers no game events, installs no hooks, writes no CVars and creates no named frames. Only `P:Enable()` does any of that.

### Load path

`Modules/LoadAll.xml` (right after the old `Nameplates.lua`, before `LastTick`):

```xml
<Script file="Nameplates.lua" />                 <!-- old module, removed in 4b -->
<Include file="Nameplates\Load.xml" />           <!-- core only: Core, Data, Engine, UI, Options -->
<Script file="Nameplates\Host\SpartanUI.lua" />  <!-- the host -->
```

`Load.xml` lists core files only, so the folder lint covers it. `[AllowLoadGameType]` does not work in XML: a file with data for one client returns early elsewhere, or is listed in `SpartanUI.toc` after `Modules\LoadAll.xml` with the directive. No such TOC line exists yet: every data file loads everywhere and the code that reads it decides.

### Tester switch (Phases 2 to 4a, Decision 21)

- The old file creates the `Nameplates` module on every non-Retail client. The host finds it with `SUI:GetModule('Nameplates', true)` and wraps `OnInitialize`, `OnEnable`, `OnDisable`.
- On Retail the old file returns before creating a module, so the host creates `Nameplates` itself (`HideModule = true`). This replaces the plan's "edit the old file's early return".
- The switch is `char.engine` in the core DB (`'new'` | `'old'` | nil), read once per session (`P.Config:GetSessionEngine()`), flipped with `/sui np preview` and a reload. Switching off restores every CVar we changed right away.
- With the switch on, the module on, and no other nameplate addon loaded (`HostWantsEngine`), the host registers the options root and calls `P:Enable()` at login. Otherwise the old module runs unchanged (Classic family and Forever) or nothing runs (Retail).
- `module.ConflictsWith` is **not** set until Phase 4a, so the setup conflicts step is unchanged for non-testers. The conflict list lives in the host (`CONFLICTS`, plus ElvUI only when its plates are on; unreadable means on).
- `module.API = P.API` is set at file load on whichever module object exists.
- `/sui np restore` gives the game back its settings (settings the game locks in combat come back when combat ends, and the message says so); `/sui np caps` logs capabilities; `/sui np cap <name> on|off|clear` forces a capability or `quirk:<name>` (the same-day escape hatch, Decision 22).
- `UI/Probe.lua` (`/sui np probe`) is a developer tool: `Load.xml` wraps its line in `<!--@do-not-package@-->` and `.pkgmeta` ignores the file, so release builds leave it out. The host already handles a missing `P.Probe`.

## 2. File ownership map

| Path | What it holds | Status (2026-10-11) | Owner |
|---|---|---|---|
| `Load.xml` | core load order | done | architect |
| `Core/Namespace.lua` | `P`, `P.VERSION`, `P.REASON`, `P.util`, message bus, core event frame, lifecycle, `P.API` | done | architect |
| `Core/Locale.lua` | `P.L` (own strings), `P:AddTranslations`, `P:HostName()` | done | everyone adds strings |
| `Core/Caps.lua` | probes, `Quirks[WOW_PROJECT_ID]`, client name, overrides | done | add probes where needed |
| `Core/Secret.lua` | `canaccessvalue`/`C_Secrets` wrappers, `IsRestricted()`, sink helpers, `Secret.SINKS` | done | architect |
| `Core/Config.lua` | AceDB open, scalar defaults, schema stamping, tester switch | done | architect |
| `Core/Store.lua` | sparse get/set by path, refresh reasons, batches, profile switch diff, follow host profile | done | architect |
| `Core/Migrate.lua` | schema patches and run-once steps | framework done; legacy import step is Phase 4a | Phase 4a |
| `Core/CVars.lua` | CVar registry, probe, backup/restore, combat queue, attribution | done; place automation is called by the Driver | Phase 2 uses it |
| `Core/Situation.lua` | `P.Context`, `Classify`, `MobType`, `PlaceFrom`, `ReadPlace`, `Assign` | done | architect |
| `Core/Conditions.lua` | condition catalog, expressions, folds, "When" clauses, kick readiness | done (Phase 8 adds actions) | Phase 8 extends |
| `Core/Roles.lua` | role defaults, threat palette and states | done | architect |
| `Core/Colors.lua` | row kinds, schemes, compile, `Apply`, `Explain` | done | Phase 4a adds UI |
| `Core/Share.lua` | `!NP:` strings, inspect/import/export | done (UI is Phase 5) | Phase 5 |
| `Core/Styles/Schema.lua` | part schema, validator, cycle check, upgrade chain, candidate keys | done | everyone adding fields |
| `Core/Styles/Registry.lua` | built-in, host and saved styles | done | architect |
| `Core/Styles/Merge.lua` | layers, tokens, defaults, re-anchoring, regions, cache | done | architect |
| `Core/Styles/Builtin_*.lua` | Clean, NamesOnly, Mini | done; Slim, Bold, Bordered, Blizzard in 4a | Phase 4a |
| `Data/*.lua` | Samples (done), ArtAliases (empty by design), Kicks, CrowdControl, TankDebuffs, Totems, ClassicChannels (shapes only) | data owners fill verified ids | data agents |
| `Engine/Scheduler.lua` | shared ticker, eases, layout queue, next frame, after combat | done | architect |
| `Engine/Source.lua` | LiveSource, SampleSource, player context, unit probes | done | Phase 2 may extend |
| `Engine/Plate.lua` | part registry (`P.Parts`), layout context, Plate lifecycle | done | architect |
| `Engine/Parts/*.lua` | one file per part implementation | stubs with contracts (Health, Text name, Icon marker work) | Phase 2 / 3 / 5 / 7 |
| `Engine/Pool.lua`, `Suppress.lua`, `Driver.lua` | pools, Blizzard suppression, the driver | stubs with full contracts; Driver has Reassign, ComputePlateSize, RefreshAll | Phase 2 |
| `UI/Widgets/*.lua` | widget registry (`P.Widgets`) + AnchorGrid, RuleList, SpellList | registry done, widgets stubbed | Phase 1 |
| `UI/Scenes.lua`, `StageProvider.lua`, `Gallery.lua`, `Inspector.lua`, `Designer.lua`, `SetupSteps.lua` | previews and designer | Gallery cards, Inspector text, setup step def done; rest stubbed | Phase 4a / 7 |
| `Options/*.lua` | options builder + one file per page | framework done; Style, Colors (scheme), Who and where (modes, restore), Sharing (follow) minimal | Phase 2 / 4a |
| `Media/` | art set (neutral names) | `Flat.tga` only | Phase 4a |
| `Host/SpartanUI.lua` | the only SpartanUI-aware file | Phase 2 tester wiring done (switch, conflicts, options root, Match my look, look pushes, profile follow, RefreshOptions, search words); the duties below are open | architect, then the owners below |
| `Tests/Nameplates/` | harness, lint, suites | separate agent | test agent |

**Host duties that are still open** (each touches the host or SpartanUI outside the module; one owner each, so parallel agents never edit the host at once):

| Duty | Phase | Owner |
|---|---|---|
| LastTick reads the health bar through `P.API:GetHealthBar` (`Modules/LastTick/Hosts.lua`, plan 6.11) | 2 | Phase 2 engine agent |
| The "Convenience" nameplate CVar takeover moves to `P.CVars` (6.7) | 2 | Phase 2 engine agent |
| `host.AddSetupSteps(P:GetSetupSteps())` and `module.ConflictsWith = CONFLICTS` | 4a | Phase 4a host agent |
| Profile Manager entry, `Nameplates` in `namespaceblacklist`, the "SpartanUI (Full Profile)" inline component (6.10) | 4a | Phase 4a host agent |
| War and other art themes register their plate art through `P.API:RegisterStyle` / theme `nameplates` blocks | 4a | Phase 4a art agent |
| The What's new card | 4a | Phase 4a host agent |
| Retire the old module and create `Nameplates` in the host on every client | 4b | Phase 4b agent |

## 3. Namespace, lifecycle and the message bus

```lua
local _, ns = ...
local P = ns.Plates   -- every core file starts like this
```

- `P:Initialize(host)` (host `OnInitialize`): opens the DB, runs migrations, follows the host profile. Inert.
- `P:Enable()` (at login, only when the host wants the engine): `Caps:RunProbes()`, registers media, then `Enable()` on `P.ENGINE_ORDER = { 'Scheduler', 'CVars', 'Pool', 'Suppress', 'Driver' }` (each in pcall). Fires `ENGINE_ENABLED`.
- `P:Disable()`: `Disable()` in reverse, then `P.CVars:RestoreAll()`. Settings the game locks in combat are queued and come back when combat ends: `P.CVars` registers its own `PLAYER_REGEN_ENABLED` flush (owner `CVars.queue`) whenever its queue holds something, whether or not the engine runs. Fires `ENGINE_DISABLED`.
- Game events for engine modules: `P:RegisterEvent(event, owner, fn)` / `P:UnregisterEvent` / `P:UnregisterAllEvents(owner)`; one lazily created frame, several owners per event. Per-plate unit events never use it (each plate has its own frame).

**Bus messages** (`P:On(message, fn, owner)`, `P:Off(message, fnOrOwner)`, `P:Fire(message, ...)`; `P:Off` with nil removes nothing):

| Message | Args | Fired by |
|---|---|---|
| `INITIALIZED` | | Namespace |
| `ENGINE_ENABLED`, `ENGINE_DISABLED` | | Namespace |
| `STORE_CHANGED` | reasons (set), keys (path list or nil), scope | Store, Registry, SetHostLook |
| `PROFILE_CHANGED` | reasons | Store |
| `PROFILES_CHANGED` | | Config (a profile was deleted) |
| `HOST_LOOK_CHANGED` | look | `P.API:SetHostLook` |
| `STYLES_CHANGED` | styleId | Registry |
| `STYLE_APPLIED` | plate, key | Plate |
| `CVAR_CHANGED` | name, value, by ('us', 'other', 'restore') | CVars |
| `PLATE_ADDED`, `PLATE_REMOVED` | plate, unit | Driver |
| `TARGET_CHANGED`, `FOCUS_CHANGED`, `MOUSEOVER_CHANGED` | | Driver |
| `CONTEXT_CHANGED` | | Driver (place, combat, role, resting). Colors drops its programs; the Driver then re-runs `Reassign` and `Refresh({ colors = true })` on every bound plate and delivers it to plates through `Plate:OnMessage` |
| `TANKS_CHANGED` | | Driver; handled like `CONTEXT_CHANGED` |
| `KICK_READY_CHANGED`, `RAID_TARGET_UPDATE`, `QUESTS_CHANGED`, `FACTS_POLLED` | | Driver (delivered to bound plates through `Plate:OnMessage`) |
| `RESTRICTION_CHANGED` | isRestricted | Driver |

Public events for other addons through `P.API:RegisterCallback`: `PLATE_ADDED`, `PLATE_REMOVED`, `STYLE_APPLIED`, `ENGINE_ENABLED`, `ENGINE_DISABLED`.

**Refresh reasons** (`P.REASON`, 5.2): `look`, `size`, `auras`, `colors`, `cvars`, `assignment`. A font toggle never rebuilds aura containers: each consumer reacts only to its reasons. `Store.REASONS` maps every top-level key to its reasons; unknown keys mean `look`.

## 4. Host contract (6.11)

`P:Initialize(hostConfig)` takes `Plates.HostConfig` (annotated in `Core/Namespace.lua`):

| Field | Required | SpartanUI value |
|---|---|---|
| `name` | yes | `'SpartanUI'`, used through `P:HostName()` in strings (`%s`) |
| `savedVariable` | yes | `'SpartanUINameplatesDB'` |
| `mediaPath` | yes | `Interface\AddOns\SpartanUI\Modules\Nameplates\Media\` |
| `widgetPrefix` | yes | `'SpartanUINameplates'` (AceGUI types `<prefix>AnchorGrid`, ...) |
| `globalPrefix` | no | defaults to `widgetPrefix`; prefix for any global name (font families, templates) |
| `logger` | no | `SUI.logger:RegisterCategory('Nameplates')` |
| `media` | no | `SUI.Lib.LSM` |
| `AddOptions`, `OptionsPath(page)`, `OpenOptions(page, key)` | no | `/sui > Nameplates` root entry |
| `AddSetupSteps(steps)` | no | adds to `SUI.Setup.registration` (Phase 4a calls it with `P:GetSetupSteps()`) |
| `RegisterCommand(name, fn, desc)`, `RegisterPreview(provider)` | no | `/sui <name>`, the Stage |
| `ImportLegacy(profileKey)` | no | raw `SpartanUIDB.namespaces.Nameplates.profiles[key]` |
| `GetHostLook()`, `GetHostProfileName()` | no | theme `nameplates` block + accent + font; SUI profile name |
| `profileDefaults`, `globalDefaults` | no | `{ followHostProfile = true }` (scalars only) |
| `widgets.cardGrid` | no | `'SUICardGrid'` |
| `conflicts` | no | folder names (code data) |
| `RefreshOptions(rebuild)` | no | `AceConfigRegistry:NotifyChange('SpartanUI')`; `rebuild` also swaps in a new `P:BuildOptionsTable()`. The core calls it once per frame after `STORE_CHANGED` (rebuild on `look`), `PROFILE_CHANGED`, `STYLES_CHANGED` (rebuild) and `RESTRICTION_CHANGED`, so changes made outside a control (preview drag, undo, profile follow, a lifted lock) show at once. The core never names an options app |
| `AddSearchWords(words)` | no | `LibAT.UI.Options.Search:AddSynonyms('SpartanUI', P.Options.SEARCH_WORDS)` (LibAT capability `searchSynonyms` 2): "aggro", "kick", "purge" and friends only apply to SpartanUI's settings |

`P.API` (other addons reach it as `SpartanUI -> GetModule('Nameplates', true) -> .API`, nil-checking each step): `GetPlate(base)`, `GetHealthBar(base)`, `RegisterStyle(style)`, `SetHostLook(look)`, `ImportStyle(text, name)`, `RegisterCallback(event, fn, owner)`, `UnregisterCallback`. `P.VERSION = { core, api, schema }`.

## 5. Data: Config, Store, Migrate

**Defaults** (`Config:Defaults()`, a fresh table every call, scalars only): `profile = { enabled, style = 'host', size = 'medium', role = 'auto', scheme = 'auto', colorBlind = false }` plus host profile defaults. Built-in styles, color orders and assignments live in code. `profile.enabled = false` makes the Driver stand down for that profile (plates unbind, Blizzard plates are not suppressed, place settings go back) until it is true again; the host's module toggle is separate and turns the whole engine off.

**The schema number is never a default** (6.10). `OnNewProfile` and `OnProfileReset` stamp `profile.schema = Config.SCHEMA.profile`; `Migrate` stamps after each patch; nil reads as 0.

**Profile shape** (sparse, only what the player changed):

```lua
profile = {
	schema = 1, style = 'clean', size = 'large',
	assign = { minor = 'mini' },             -- [kind] = styleId
	modes = { friendlyNPC = 'hidden' },      -- [kind] = 'full' | 'name' | 'hidden'
	when = { { conditions = { { id = 'place', args = 'raid' } }, kinds = { 'enemyNPC' }, style = 'slim', size = 'small', mode = nil, off = nil } },
	tweaks = { clean = { schema = 1, baseVersion = 1, changes = { plate = ..., parts = { name = { font = { size = 11 } } }, states = ..., tokens = ..., regions = ... }, add = { forces = { ...part } }, remove = { marker = true }, situations = { friendlyPlayer = { hide = { 'cast' }, parts = { ... } } } } },
	scheme = 'mobType', colors = { health = { order = { ... }, off = { quest = true }, color = { tapped = { r, g, b, a }, mobType = { boss = { ... } } }, when = { quest = 'world' }, fallback = { ... } } },
	threat = { when = 'instances', show = { border = true }, colors = { safe = { ... } } },
	casts = {}, behavior = {}, auras = { myDebuffs = { on = true, always = { [spellID] = 'mine' }, never = {} } },
	cvars = {}, followHostProfile = true, migratedFromOld = nil,
}
char = { engine = 'new', cvarBackup = { nameplateMinScale = '0.8' } }
global = { schema = 1, styles = { u3f9 = { name, schema, base = style, source = { kind = 'import', author, version, styleId } } }, cvarBackup = {}, capOverrides = {}, seen = {}, migratedFromOld = { Default = true } }
```

**Store rules** (`P.Store`):
- `Store:Get(path, scope)` / `Store:Set(path, value, scope, reasons)`; path is `'a.b.c'` or `{ 'a', 'b', 'c' }`; scope `'profile'` (default), `'global'`, `'char'`.
- Read on every call. Never keep a sub-table from the DB (profile switches replace tables).
- `Set` copies tables in, writes only when the value differs (deep compare), and `nil` removes the key and prunes empty parents. Exception: a top-level key with an AceDB default (`style`, `size`, `role`, `scheme`, `colorBlind`, `enabled`, host defaults such as `followHostProfile`) gets its default written back instead, because AceDB copies plain defaults into the profile once and a removed key would read nil until the next load. `Store:Reset(path, scope)` is the name for "back to default"; AceDB strips the default again when it saves.
- Lists (orders, "When" entries, spell lists, anchors) are written whole.
- `Store:Batch(fn)` fires one `STORE_CHANGED` with the union of reasons.
- Profile switches fire `PROFILE_CHANGED` and `STORE_CHANGED` with the union of the reasons of every top-level key whose value differs; copies and resets fire all reasons.

**Migrate**: `Migrate:AddPatch(scope, n, fn)` upgrades schema n-1 to n for `'profile'` or `'global'`. `Migrate:AddStep(id, fn(profile, key, global))` adds an idempotent run-once step that runs on every profile load and keeps its own guard. The legacy import (plan "patch 1", 7.1) is a **step**: a player's nameplate profile is brand new in this database (the old data lives in `SpartanUIDB`), so a schema stamp cannot guard it. Guards: `profile.migratedFromOld` and `global.migratedFromOld[profileKey]` (survives resets). Styles and overlays use their own chain in `Schema.lua`.

## 6. Styles

A style is data (5.1). See `Core/Styles/Builtin_Clean.lua` for the canonical example and `Schema.PART_FIELDS` for every field and range.

- Top level: `id, name, description, version (content), schema (format), order, internal, matchesHost, plate.sizes.{small,medium,large} = { w, h }, regions.{click,stack} = { auto, pad = { l, r, t, b }, rect }, tokens, parts, states, situations`.
- Part kinds: `bar` (health, power), `cast`, `text`, `icon`, `auras`, `highlight`, `glow`, `art`, `region` (Phase 7), `classPower` (Phase 5).
- Parts are keyed by stable id; `order` sets layout order; `anchor = { point, relativeTo ('plate' or a part id), relPoint, x, y }`.
- Tokens: `$name` in any part field resolves through `style.tokens`; a token whose value is `'$host'` takes the host look (`hostLook.tokens[name]`, `hostLook.font`, `hostLook.accent`), else `Merge.TOKEN_FALLBACK` (accent from LibAT, font `LibAT.UI.Style.FONT_PATH`, bar `'Nameplates Flat'`, ink black, shade black 0.6).
- Colors: `colors = 'health'|'border'|'name'|'cast'` names the color list a part uses; bars also take `borderColors`.
- Whole pixels only. Never `SetScale` for sizes or target emphasis.

**Layers** (`Merge:Resolve(styleId, situation, sizeKey)`, cached): base from `Registry` -> `$host` tokens -> overlay `profile.tweaks[id]` -> situation patch (`style.situations[kind]`, then `tweaks.situations[kind]`). States are applied at runtime by the Plate. Tables merge by key; lists replace. Removed or hidden parts hand their anchor to parts anchored to them; leftover cycles are broken by anchoring to the plate (and logged). `Merge.PART_DEFAULTS` fills every part. The cache is wiped (and `generation` bumped, so `resolved.key` changes) on `look`, `size` or `auras` reasons, `HOST_LOOK_CHANGED` and `STYLES_CHANGED`.

**Resolved style** (`Plates.ResolvedStyle`): `key, id, situation, sizeKey, width, height, tokens, parts, order, hidden, states, regions = { click, stack }` (rects relative to the plate center). Read-only for everyone.

**Registry**: `RegisterBuiltin(style)` (file load), `RegisterHostStyle(style)` (validated; via `P.API:RegisterStyle`), `ResolveId(id)` (`'host'` -> the host style with `matchesHost`, else `'clean'`), `Get(id)`, `List(includeInternal)`, `Save`, `UpdateSaved`, `Rename`, `Delete`. "Make a copy" saves `Merge:Bake(id)` (base plus overlay, tokens kept).

**Schema**: `ValidateStyle(style) -> cleaned, report, reason`, `ValidateOverlay(overlay, baseParts)`, `CheckPart`, `FieldSpec(kind, field)` (slider ranges), `FindCycle(parts)`, `Upgrade(style)` / `UpgradeOverlay(overlay)` (nil + `'newer'` for a newer schema), `AddUpgrade(n, styleFn, overlayFn)`, `CANDIDATE_KEYS`. Reports count `dropped`, `clamped`, `fixed`; cycles reject the style.

**Adding a field**: add it to `Schema.PART_FIELDS[kind]` (or `PART_COMMON`) with its range, give it a default in `Merge.PART_DEFAULTS` if parts rely on it, read it in the part's `Layout` or `Update`. A new required field or a changed meaning needs a schema number and an upgrade in `Schema:AddUpgrade`. There is one format number: `Schema.CURRENT`. Share strings are stamped and checked with it, and `P.VERSION.schema` is only a copy set by `Schema.lua`; never raise `P.VERSION.schema` by itself.

## 7. Engine contracts

### Plate (`Engine/Plate.lua`)

```lua
local plate = P.Plate.New(parent, isPreview, ctx) -- root, art (size and alpha states), events (live only); ctx defaults to P.Context
plate:ApplyStyle(resolved)   -- returns false when resolved.key is unchanged
plate:Bind(unit, liveSource) -- live: RegisterUnitEvent for the union of part events, full update
plate:BindSample(sampleSrc)  -- preview: facts from the sample, no events
plate:SetContext(ctx)        -- previews: another context (pooled plates)
plate:SetState('target', true) -- target | focus | mouseover | casting: emphasis only
plate:SetStateSecret('target', boolSecret) -- S4: state-tied parts fade by SetAlphaFromBoolean; grow and the notTarget fade stay off
plate:OnMessage(message, ...) -- Driver delivers bus messages to bound plates
plate:Refresh(reasons)       -- colors: re-register events and update; auras: Configure
plate:Configure()            -- aura settings now, or plate.pendingConfigure while restricted (Driver:FlushPendingConfigure runs it when the lock lifts)
plate:Unbind()
plate:GetHealthBar()         -- health widget's StatusBar
```

Fields: `root, art, events, click, stack, base, unit, src, isPreview, facts, states, env = { facts, ctx, states, src }, style, styleKey, situation, assignment, widgets, active, pendingConfigure, emW/emH/emA` (the size and alpha last applied). Emphasis: `style.states.target.grow` adds whole pixels; `notTarget.alpha` fades other plates while the player has a target; `casting.alpha` brings a casting plate back; all eased over 0.15 s on the Scheduler from `emW/emH/emA`. Never read size, points or alpha back from a plate: inside Blizzard's plate tree they can be secret on 12.1. Healer emphasis (Roles) is Phase 4a.

**Who shows what.** The plate owns `widget.frame`: shown while the part is in the style (and its `spec.state` is on). Parts never Show or Hide `widget.frame`; they show data on child regions (a bar inside a holder, a texture, a font string) or by their alpha. The cast part keeps its bar inside a holder and hides only the bar between casts.

**Common part fields** are applied by the plate right after `Layout` (`ctx:ApplyCommon`): `alpha` on `widget.frame`, draw order (frame level from the part's place in `style.order` plus `layer`, levels read once from our own art frame), and `pixelSnap` on `widget.textures` plus a bar's fill texture. `above` ("draw above other plates") belongs to the Driver's lift frame in Phase 5.

**Preview context.** Preview plates never read `P.Context`: scenes build one with `P.Scenes.PreviewContext(fields)` (role, inGroup, tanks, petTank, hasTarget, place) and pass it to `Plate.New`. `Colors:Program(piece, ctx)` caches per context table (weak keys), so a tank preview shows threat rows and "another tank holds it" while the player is solo.

### Part implementations (`P.Parts:Register(impl)`)

```lua
P.Parts:Register({
	id = 'myPart',                 -- registry key
	kinds = { 'text' },            -- style part kinds it draws
	match = function(spec, plate) return spec.source == 'level' end, -- optional
	priority = 10,                 -- optional, highest matching wins
	events = { 'UNIT_LEVEL' },     -- or function(spec) return { ... } end
	messages = { 'TARGET_CHANGED' }, -- bus messages, delivered to OnMessage or Update
	reasons = { colors = true },   -- extra refresh reasons that call Layout (look and size always re-lay out via the key)
	Create = function(plate, id, spec) return { frame = CreateFrame('Frame', nil, plate.art) } end,
	Layout = function(widget, spec, ctx) ctx:Anchor(widget.frame, spec.anchor) end,
	Update = function(widget, src, event, ...) end, -- event 'FULL', a unit event, a message, or 'COLORS'
	Reset = function(widget) end,  -- unbind: clear data, stop animations, keep frames
	OnState = function(widget, state, on) end, -- optional
	Configure = function(widget, spec, ctx) end, -- optional, aura settings, only while not restricted
})
```

- `Create` makes frames only (parent them to `plate.art`); widgets are cached per `impl.id .. ':' .. partId` and reused across styles.
- A widget is `{ frame = <root region>, anchor = <optional anchor region>, ... }`; the plate adds `plate, id, impl, spec, active`. Parts anchored to this one use `widget.anchor or widget.frame`.
- The plate also registers the events and messages of the color lists named in `spec.colors` / `spec.borderColors`, so a part that colors itself only calls `P.Colors:Apply`.
- Parts with `spec.state` are shown only while that state is on.
- Never `SetScale`; never per-plate `OnUpdate` (use `P.Scheduler`); never global names.

Layout context (`ctx`): `ctx.plate, ctx.style, ctx.width, ctx.height` (always the plate being laid out), `ctx:Region(id)`, `ctx:Anchor(region, anchor)`, `ctx:Font(fontSpec) -> face, size, flags`, `ctx:ApplyFont(fontString, fontSpec, forNames)` (names get a font family from `P.Fonts:Family(face, size, flags)`: the chosen face for the client's own alphabet, the game's faces for the others, one family per face/size/flags named from `host.globalPrefix`; the game's `SystemFont_NamePlate` when families are missing (S10); previews get smooth scaling), `ctx:Texture(key, mediaType)` (LSM key, art alias or a file path; nil for anything else, so `or P.BarLib.WHITE` fallbacks work), `ctx:Color(color) -> r, g, b, a`, `ctx:Program(piece)` (for the plate's own context), `ctx:Pixel()` (one physical pixel), `ctx:ApplyCommon(widget, spec, rank)`.

Resolution: `bar` -> `health` (source health, priority 10) or `bar` (power); `glow` -> `threat` (source threat, priority 10) or `glow`; `auras` -> `aurasContainer` (live plates where `Caps containers`, priority 10) or `aurasScan` (previews, and live plates only on clients without secrets; a client with secrets and no containers shows no aura rows); `highlight` and `art` -> Highlight.lua; others by kind. `P.BarLib` (Bar.lua) holds the shared status bar helpers and `BarLib.WHITE`.

**How to add a part**: pick or add a kind in `Schema.PART_KINDS` and its fields in `Schema.PART_FIELDS`; add defaults to `Merge.PART_DEFAULTS`; create `Engine/Parts/<Name>.lua` and list it in `Load.xml` after `Plate.lua`; read data only through Source methods; send `*Secret` values only to sinks; add it to the built-in styles that should show it; add a suite that lays it out on a sample plate and runs it under the strict secret mock.

### Source (`Engine/Source.lua`)

The only file that may call `Unit*` functions, `C_UnitAuras` or `C_NamePlate.GetNamePlateForUnit` (lint rule `source-only`).

- `P.Source.NewLive(unit)` -> LiveSource: `SetUnit(unit)`, `SetGuarded(on)` (pcall every read: restricted PvP tokens, 9.2).
- `P.Source.NewSample(sampleOrId)` -> SampleSource: `SetSample(sample)`, plain values from `P.Data.Samples`, `SampleAuras(row)`, `KickReady()`; cast loops every `duration` seconds through real Duration objects.

**Naming is the contract**: `...Secret()` may return a secret (sinks only); `...Plain()` returns `value, readable` (`readable == false` means the game hid it and value is nil); everything else is always plain.

| Plain (always) | Plain pair (`value, readable`) | Secret (sinks only) |
|---|---|---|
| `ReadFacts(facts)`, `PollFacts(facts)`, `CastKind()`, `CastBarID()`, `CreatureIDPlain()` (nil when identity is hidden), `QuestPlain()`, `FillHealPrediction(calculator)` | `HealthPlain`, `NamePlain`, `ClassTokenPlain`, `ThreatStatusPlain`, `ThreatPercentPlain`, `IsTankingPlain(tank)`, `NotInterruptiblePlain`, `SpellIDPlain`, `CastTimesPlain` (start, end, readable), `IsImportantPlain`, `AimedAtMePlain`, `ShowSpellTargetPlain`, `InCombatPlain`, `AuraByIndexPlain`, `AuraInstanceIDsPlain`, `AuraByInstancePlain` (aura reads return the value or nil) | `HealthSecret`, `HealthMaxSecret`, `HealthPercentSecret(curve)`, `AbsorbSecret`, `HealAbsorbSecret`, `NameSecret`, `ClassTokenSecret`, `RaidMarkerSecret`, `ThreatStatusSecret`, `ThreatPercentSecret`, `IsTankingSecret(tank)`, `CastNameSecret`, `CastIconSecret`, `CastDurationSecret`, `NotInterruptibleSecret`, `SpellIDSecret`, `IsImportantSecret`, `AimedAtMeSecret`, `SpellTargetNameSecret`, `SpellTargetClassSecret`, `ForcesSecret`, `InCombatSecret`, `IsUnitSecret(token)`, `PowerSecret(type)`, `PowerMaxSecret(type)` |

Facts from functions only some clients have keep a readable `false` (nil means "this client cannot say"); `Situation.MobType` relies on it. Static helpers (not tied to a plate): `Source.ReadPlayerContext(ctx, roleSetting)` (role, group, other tanks without the player: raid slots are skipped by the player's own `UnitInRaid` index, never by `UnitIsUnit`, which can be secret; pet, level), `Source.PlateForUnit(unit)` (pcall), `Source.PlayerClass()`, `Source.UnitExists(unit)`. Facts (`Plates.Facts` in `Situation.lua`): reaction, canAttack, isPlayer, playerControlled, isMinion, classification, effectiveLevel, isBoss, isLieutenant, isCaster, tapDenied, questBoss, isQuest, widgetsOnly, isGameObject, classToken (readable players only), inCombat, mobType.

### Scheduler (`Engine/Scheduler.lua`)

`Every(id, interval, fn(now))`, `Cancel(id)`, `IsRunning(id)`, `Ease(id, from, to, duration, apply(value), done)`, `StopEase(id)`, `QueueLayout(plate)` (calls `plate:Layout()` once next frame), `NextFrame(id, fn)`, `AfterCombat(id, fn)` (runs now or on `PLAYER_REGEN_ENABLED`). One hidden frame, shown only while it has work.

### Driver, Pool, Suppress

Their headers hold the step-by-step contracts from 6.5 (add, remove, global events, the `UpdateNamePlateOptions` hook, the fact poller, suppression order, pre-warm and container pooling, Show mode `'hidden'`, `profile.enabled`). Implemented so far: `Driver:GetPlate(base)`, `GetPlateForUnit(unit)`, `ForEachPlate(fn)`, `Reassign(plate)` (Classify -> Assign -> Merge -> ApplyStyle), `ComputePlateSize()` (largest click area over every style a kind or "When" entry can pick), `RefreshAll(reasons)`, `Broadcast(message, ...)`, `ContextChanged(message)`, `FlushPendingConfigure()`, `ProfileWantsPlates()`; `Pool:Acquire/Release`; `Suppress:HiddenParent()`. Show mode `'hidden'`: the plate root hides, nothing binds, the base keeps Blizzard's click area and stacking, Blizzard's plate stays suppressed, and the kind is left out of the plate size; the show CVars are only for a kind hidden in every place. Spike fallbacks each implementation must ship (9.1): S1 keep Blizzard's click area; S4 `SetAlphaFromBoolean(src:IsUnitSecret('target'), 1, 0)` behind `Secret.CanCompareUnitTokens`; S6 grow container pools only out of combat; S7 reparent-and-unregister when `SetRolesets` fails (record `Caps:Record('rolesets', false)`); S8 `SetNamePlateSimplified(unit, false)` on every add; S14 pcall `GetNamePlateForUnit`; Mists `Quirks.uiParentScale`.

## 8. Situations, conditions, colors, roles

- `Situation.Classify(facts)` -> `enemyNPC | enemyPlayer | friendlyNPC | friendlyPlayer | minor`. Hostile = can attack or reaction 1-3. Minor = minus, trivial, minion or player-controlled non-player.
- `Situation.Assign(kind, env, settings, out)` -> `out.style, out.mode, out.size, out.whenIndex, out.deps`. Order: `profile.when` (first match, plain conditions only), `profile.assign` / `profile.modes`, then `DEFAULT_ASSIGN = { minor = 'mini' }`, `DEFAULT_MODES = { friendlyNPC = 'hidden', friendlyPlayer = 'name' }`. Mode `'name'` draws `namesOnly`.
- `P.Context` is the one shared context table (place, inCombat, resting, role, inGroup, groupSize, tanks, petTank, playerLevel, challengeActive, kickSpell, hasTarget). Only the Driver writes it, then fires `CONTEXT_CHANGED`.
- **Conditions** (`P.Conditions:Register`): `kind = 'plain' | 'engine' | 'identity'`; `Test(env, args) -> true | false | nil` (nil only for engine conditions); engine conditions add `TestSecret(env, args)`. Plain conditions never touch `env.src`. Expressions: leaf `{ id, args, negate }`, `{ all = {...} }`, `{ any = {...} }`, `{ ['not'] = expr }`; `TestExpr` and `FoldSecret(expr, env, ifTrue, ifFalse)` (AND puts the next term in the true slot, OR in the false slot, NOT swaps). `AllowedActions(id)` gives color/alpha/glow only for non-plain conditions on clients with secrets. "When" clauses for color rows: `Conditions.WHEN` (everywhere, instances, dungeons, raids, delves, pvp, world, combat, never).
- **How to add a condition**: register it in `Core/Conditions.lua` with id, kind, label (`P.L`), `facts` it reads, `events`/`messages` that change it, and `Test` (plus `TestSecret` for engine). Engine conditions read through `src:...Plain()` first and `src:...Secret()` second. Add truth-table cases to the Situation/Conditions suite, including a strict-secret case.
- **Colors** (`P.Colors`): pieces `health, border, name, cast`; schemes `threat, mobType, class, custom` (`auto` follows the role); `'@threat'` expands to `offTank, petTank, threat` on pieces where `Roles.ThreatOn` shows threat. `Colors:Program(piece)` is cached until `colors`/`look` reasons or `CONTEXT_CHANGED`. `Colors:Apply(program, env, target, method)` resolves plain rows top to bottom, folds hidden rows above the winner per channel, and calls the sink (`SetStatusBarColor`, `SetTextColor`, else `SetVertexColor`). Returns `winner, engineRows` (plain). `Explain` and `Sentence` feed the inspector; `SuggestInsertIndex` places new rows; `BuildStepCurve` makes curve rows (low health is an overlay drawn by the health part). Threat hidden by the game gives no threat color (S2).
- **Roles**: `Roles.Resolve(setting, specRole)`, `Roles.Scheme(role)`, `Roles.ThreatOn(role, show)`, `Roles.ThreatState(role, status, inGroup)` (tank: 3 safe, 2 losing, else lost; others: 0 safe, 1 losing, else lost; solo when not grouped), `Roles.Palette(colorBlind, custom)`.

## 9. Secret discipline (6.3)

On Retail and Forever many unit values are secret for addon code. Rules (enforced by `Tests/Nameplates/lint.py` and the strict secret mock):

1. A `*Secret()` result goes straight into an approved sink, or into a local whose name ends in `Secret` that is only used as a sink argument (or passed to a function whose name ends in `Secret`).
2. Never compare, `==`, test for truth (`if x`, `x and`, `not x`), do arithmetic, concatenate, use `#`, index, call, or use as a table key.
3. The only allowed presence test is `type(x) == 'nil'` / `type(x) ~= 'nil'`.
4. Need a value in Lua logic? Call the `Plain` method and branch on `readable`.
5. Never key a table by `auraInstanceID`. Never read back a value derived from a secret.

Sinks: see `Secret.SINKS` (game APIs documented as accepting secrets from addon code, plus `P.Secret.ChooseValue/ChooseColor/SetAlphaFromBoolean/SetVertexColorFromBoolean/SetRaidMarker/Plain/CanAccess/CanIndex/IsSecret`, `P.Colors:Apply`, `P.Conditions:FoldSecret`). The lint reads that list (one source) plus the data files; `SetAlpha` is documented to take secrets but stays refused (`notSinks`) until an in-game check, so "hide at full health" on clients with secrets uses a step ColorCurve into `SetTextColor` instead. Always pass both alphas to `SetAlphaFromBoolean` (`1, 0`). The four boolean helpers treat a missing answer (nil, for example a unit that is not on the threat list) as false, because the engine functions do not take nil. Index a table from the game only after `Secret.CanIndex` (`canaccesstable`): a table can pass `canaccessvalue` and still be forbidden.

```lua
-- Right
bar:SetMinMaxValues(0, src:HealthMaxSecret())
bar:SetValue(src:HealthSecret())
P.Secret.SetAlphaFromBoolean(shield, src:NotInterruptibleSecret(), 1, 0)
local markerSecret = src:RaidMarkerSecret()
P.Secret.SetRaidMarker(icon, markerSecret)
local status, readable = src:ThreatStatusPlain()
if readable and status == 3 then ... end

-- Wrong (each fails the lint or errors in game)
if src:HealthSecret() < 1000 then end
local percent = src:HealthSecret() / src:HealthMaxSecret()
if src:NotInterruptibleSecret() then end
cache[src:NameSecret()] = true
text:SetText('HP: ' .. src:HealthSecret()) -- concatenation produces a secret; use SetFormattedText
```

`Secret.IsRestricted()` (`InCombatLockdown()` or `C_Secrets.ShouldAurasBeSecret()`, after login, where secrets exist) gates every settings lock and every aura container change; `ADDON_RESTRICTION_STATE_CHANGED` and `PLAYER_REGEN_ENABLED` lift it.

## 10. Flavor gating (6.8)

- Gate on capabilities, never on "is Retail": `P.Caps:Get(name)`. Probes are pcall-wrapped and safe on all six clients; frame and unit probes are registered by engine files and evaluated in `P:Enable()`.
- Probes now: `secrets, containers, pingable, tooltipData, profiler, simplified, hitTestInsets, plateSize, durations, durationText, colorFromBoolean, colorMixinFromBoolean, colorCurves, encoding, fontFamily, auraInstanceIDs, restrictionEvents, challengeMode, forces, important, kickCooldown, classColor, cvarInfo, cvarBitfield` (Caps.lua); `lieutenant, bossMob, questBoss, healPrediction, castDurations, timerBars, spellTarget, creatureID` (Source.lua); `rolesets` (Suppress.lua). Real-object answers (first plate's hit-test points, first aura button's pandemic methods) use `Caps:Record(name, value)`.
- Quirks: `Caps:Quirk(name)`, keyed by `WOW_PROJECT_ID` (`Caps.QUIRKS`; Mists starts with `uiParentScale`, `plainCastText`) and by client name (`Caps.CLIENT_QUIRKS`, Titan ready). Overrides: `Caps:SetOverride(name | 'quirk:'..name, value)` (stored in `global.capOverrides`, set from `/sui np cap`).
- `Caps:Client()` (`retail, forever, mists, titan, tbc, era`) and `Caps.Rules.retail` are for data rules and logs only.
- APIs present on all six cannot tell clients apart (`IsSpellImportant`, duration text bindings, forces): gate on the run or the data, not the API.

## 11. CVars (6.7)

`P.CVars:Define(name, def)` (refuses `nameplateMotion`), `Probe(name) -> { exists, actual, account, character, locked, secure, readOnly }`, `Get`, `GetBit`, `Set(name, value, why) -> 'set'|'same'|'queued'|'missing'|'locked'|'failed'`, `SetBit(name, bitKey, on, why)`, `FlushQueue()`, `HasQueued()`, `Restore(name)`, `RestoreAll() -> done` (false when some settings wait for combat to end; tell the player only "done" when it is true), `GetBackup(name)`, `GetAttribution(name)`, `List(page)`. The combat queue flushes itself on `PLAYER_REGEN_ENABLED` even while the engine is off; `CVars:Disable` drops queued writes but keeps queued restores. First write backs up the player's value (account CVars in `global.cvarBackup`, character CVars in `char.cvarBackup`). Secure CVars queue in combat. Attribution hooks `C_CVar.SetCVar`/`SetCVarBitfield` once on the first Enable. Old show-CVar names are probed through `def.alt`.

## 12. Previews, gallery, options, share

- Previews run the real parts on `SampleSource`; preview plates are `Plate.New(canvas, true)` + `BindSample`. Scenes (`UI/Scenes.lua`): `pull`, `focus`, `rows`, `kinds`. Aura rows in previews draw sample icons (AurasScan).
- `P:BuildPreviewProvider()` returns the Stage provider (nil until Phase 4a; it sets `refit = true`, the Stage's opt-in for a redraw when the canvas changes size). `P.Gallery:Cards()` returns card-grid cards (`value, title, caption, tag, recommended, art`). `P:GetSetupSteps()` returns the look step: LibAT reads `variants` per card, so `SetupSteps.Cards()` puts the Small / Medium / Large row on every card, and `setVariant(value, variant)` stages that card's style and the size together. `P.Inspector:Explain(plate, piece)` gives the "why this color" line.
- Options: `P:BuildOptionsTable()`; pages register with `P.Options:AddPage(id, order, builder)` (ids `style, customize, colors, auras, whoAndWhere, sharing`). Use `Options.Bind(path, scope, reasons)` for get/set, `Options.Locked` for restricted settings (`Options.LOCKED_REASON`), `Options.Path(page)` for paths, `host.widgets.cardGrid` and `P.Widgets:TypeName('AnchorGrid'|'RuleList'|'SpellList')` for widget types. At most 8 main controls per page; the rest `advanced = true`.
- Share strings: `!NP:<schema>:<kind>!<base64(deflate(cbor))>`, kinds `style, colors, when, profile`. `P.Share:Encode/Decode/InspectStyle/ImportStyle(text, name, 'new'|'update')/ExportStyle(id, author)/ReasonText(reason)`. Newer strings are refused; everything is upgraded and validated.

## 13. Tests (`Tests/Nameplates/`)

The harness is owned by the test agent; read `Tests/Nameplates/README.md` for its API (`describe/it/assert`, `H.LoadCore`, `H.LoadSpartanUIHost`, `M.Login`, `M.ShowPlate`, strict secret values, per-flavor mocks). Rules for suites:

- One file per area in `Tests/Nameplates/suites/` (`<area>_spec.lua`), one process per flavor (retail, forever, mists, titan, tbc, era).
- Value-sensitive suites (Store, CVars, Share, Migrate, Merge geometry) run on lupa `lua51`; mark them `-- @runtime lua51`.
- Load the core exactly as the game does: every file in `Load.xml` order, each chunk called with `('SpartanUI', ns)`; read `ns.Plates`.
- Test pure functions directly (Classify/Assign truth tables, Merge, Schema, Colors compile, Conditions folds); drive engine code through the mock client (`NAME_PLATE_*` events, secrets on Retail and Forever).
- Every built-in style must pass `Schema:ValidateStyle` with zero drops, clamps and fixes; every aura candidate key must be in `Schema.CANDIDATE_KEYS`.
- Keep the "inert when off" suite green: no events, hooks, CVar writes or named frames until `P:Enable()`.
- Run `python Tests/Nameplates/lint.py` and `stylua --check Modules/Nameplates` before handing work back.

## 14. Rules that bite

- Lua 5.1 only; no `print` (use `P.log`); no emojis or symbols the game cannot draw; no em dashes; 6th grade wording; never name other addons in code comments or strings (folder names in the host's conflict data are the one exception).
- Never name anything `Auras` or `TargetIndicator` (oUF element names).
- Never write fields onto Blizzard frames; keep bookkeeping in weak local tables.
- Never parse `NamePlateN` names or cap at 40 plates.
- Never write `nameplateMotion`; never edit `NamePlateDriverFrame`'s event registrations.
- Fonts that show player names use a font family (non-Latin names).
- PNG paths include `.png`; new texture files need a client restart.
- Decision 20/22: tester phases commit as `chore:`; Blizzard breakage fixes go straight to master as `fixes:` after in-game confirmation.
