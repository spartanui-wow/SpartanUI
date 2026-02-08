# SUI Database Manager - Configuration Override Pattern

## Overview

The SUI Database Manager (`SUI.DBM`) provides a unified API for module database initialization using the **Configuration Override Pattern** (also known as Sparse Configuration Storage).

## Pattern Benefits

- **Smaller SavedVariables**: Only user changes are stored in the database
- **Easier migrations**: Changing defaults doesn't require migration scripts
- **Clear intent**: Easy to see exactly what users customized
- **Industry standard**: Used by Git, Docker, Kubernetes, SQL Server config, and many modern applications

## The Configuration Override Pattern

In this pattern:
- **Defaults** are defined once in code
- **Database** stores only user-changed values (sparse/empty by default)
- **CurrentSettings** = merged defaults + user changes at runtime

This means a fresh profile will have an empty (or near-empty) database, with all behavior coming from defaults defined in code. Only when a user changes a setting does it get written to the database.

## Basic Usage

```lua
---@class SUI.Module.MyModule.DB
local DBDefaults = {
	enabled = true,
	scale = 1.0,
	position = { x = 0, y = 0 },
	nested = {
		setting = true,
		deepNested = {
			value = 'default',
		},
	},
}

---@class SUI.Module.MyModule.DBGlobal
local DBGlobalDefaults = {
	favorites = {},
}

function module:OnInitialize()
	-- Setup with Configuration Override Pattern
	SUI.DBM:SetupModule(self, DBDefaults, DBGlobalDefaults, {
		autoCalculateDepth = true, -- Recommended: auto-detect nesting depth
	})

	-- Now you have:
	-- module.DB (stores ONLY user changes)
	-- module.DBG (global settings, cross-character)
	-- module.DBDefaults (your default values)
	-- module.DBGlobalDefaults (global defaults)
	-- module.CurrentSettings (merged defaults + user changes)
end
```

## Options UI Integration

### Basic Pattern

Always read from `CurrentSettings`, write to `DB`, then call `RefreshSettings()`:

```lua
-- Simple value
get = function()
	return module.CurrentSettings.enabled
end,
set = function(_, val)
	module.DB.enabled = val
	SUI.DBM:RefreshSettings(module)
end,
```

### Using Helper Functions (Recommended)

The API provides convenience helpers for common get/set operations:

```lua
-- Simple value
get = function()
	return SUI.DBM:Get(module, 'enabled')
end,
set = function(_, val)
	SUI.DBM:Set(module, 'enabled', val)
end,

-- With callback after refresh
set = function(_, val)
	SUI.DBM:Set(module, 'enabled', val, function()
		module:UpdateUI()
	end)
end,

-- Nested values (using dot notation)
get = function()
	return SUI.DBM:Get(module, 'position.x')
end,
set = function(_, val)
	SUI.DBM:Set(module, 'position.x', val, function()
		module:UpdateFramePosition()
	end)
end,
```

## Wildcard Depth

AceDB requires explicit wildcard patterns (`['**']`) to support nested table storage. The DBM API handles this automatically:

```lua
-- Auto-detect depth (recommended):
SUI.DBM:SetupModule(module, DBDefaults, nil, {
	autoCalculateDepth = true, -- Default behavior
})

-- Manual depth (for very deep or dynamic structures):
SUI.DBM:SetupModule(module, DBDefaults, nil, {
	maxDepth = 4, -- Supports 4 levels of nesting
})
```

The depth detection works by recursively analyzing your defaults table. For most modules, auto-detection is sufficient and recommended.

## Reading Settings

**CRITICAL**: Always read from `module.CurrentSettings`, never from `module.DB`.

The DB table only contains user changes, so direct reads may return `nil` even when a default exists.

```lua
-- ✅ CORRECT:
if module.CurrentSettings.showTooltips then
	-- This will use the default value if user hasn't changed it
end

-- ❌ WRONG:
if module.DB.showTooltips then
	-- May be nil even if default is true!
	-- This will cause bugs!
end
```

## Writing Settings

Always write to `module.DB`, then call `RefreshSettings()` to update `CurrentSettings`:

```lua
-- Direct write (manual refresh required):
module.DB.enabled = false
SUI.DBM:RefreshSettings(module)

-- Or use API (auto-refresh):
SUI.DBM:Set(module, 'enabled', false)

-- Nested write with callback:
SUI.DBM:Set(module, 'position.x', 100, function()
	module:UpdateFramePosition()
end)
```

## API Reference

### SetupModule

```lua
SUI.DBM:SetupModule(module, defaults, globalDefaults, options)
```

**Parameters:**
- `module` (table): The module to setup DB for
- `defaults` (table): Default profile values (can be nested)
- `globalDefaults` (table, optional): Global defaults (cross-character)
- `options` (table, optional):
  - `autoCalculateDepth` (boolean): Auto-detect nesting depth (default: true)
  - `maxDepth` (number): Manual depth override (0-10)

**Sets up:**
- `module.Database` - AceDB namespace
- `module.DB` - Profile database (stores user changes only)
- `module.DBG` - Global database (cross-character)
- `module.DBDefaults` - Your defaults
- `module.DBGlobalDefaults` - Global defaults
- `module.CurrentSettings` - Merged defaults + user changes

### RefreshSettings

```lua
SUI.DBM:RefreshSettings(module)
```

Merges defaults with user changes into `CurrentSettings`. Call this after any manual DB write.

### Set

```lua
SUI.DBM:Set(module, key, value, callback)
```

**Parameters:**
- `module` (table): The module
- `key` (string): DB key to set (can be nested path like "position.x")
- `value` (any): Value to set
- `callback` (function, optional): Called after refresh

Writes to DB, refreshes CurrentSettings, and optionally calls callback.

### Get

```lua
local value = SUI.DBM:Get(module, key)
```

**Parameters:**
- `module` (table): The module
- `key` (string): Setting key (can be nested path like "position.x")

**Returns:** The current setting value from `CurrentSettings`.

## Common Patterns

### Toggle with Refresh

```lua
set = function(_, val)
	SUI.DBM:Set(module, 'enabled', val, function()
		if val then
			module:Enable()
		else
			module:Disable()
		end
	end)
end,
```

### Range Slider with UI Update

```lua
set = function(_, val)
	SUI.DBM:Set(module, 'scale', val, function()
		if module.frame then
			module.frame:SetScale(val)
		end
	end)
end,
```

### Reset to Defaults

```lua
-- Reset single setting
module.DB.enabled = nil -- Remove from DB
SUI.DBM:RefreshSettings(module) -- Will now use default

-- Reset entire module
table.wipe(module.DB)
SUI.DBM:RefreshSettings(module)
```

## Migration from Old Pattern

If migrating an existing module from pre-populating DB with all defaults:

1. **Identify DB structure**: Note max nesting depth in defaults
2. **Replace OnInitialize DB setup**: Use `SUI.DBM:SetupModule()`
3. **Add CurrentSettings references**: Replace `DB.` with `CurrentSettings.` for all reads
4. **Update options**: Use `CurrentSettings` for get, `DB` for set + `RefreshSettings()`
5. **Test**: Verify defaults work, settings persist, UI updates correctly

**Example migration checklist:**
- [ ] Create DBDefaults table
- [ ] Replace RegisterNamespace with SetupModule
- [ ] Change all DB reads to CurrentSettings
- [ ] Update options get/set pattern
- [ ] Add RefreshSettings after manual DB writes
- [ ] Test with empty profile
- [ ] Test setting persistence
- [ ] Verify `/reload` preserves settings

## Exceptions

### Third-Party Library State

Some third-party libraries (like LibDBIcon) require direct DB table references for their internal state management. In these cases, it's acceptable to write directly to `module.DB.libraryKey`:

```lua
-- LibDBIcon needs direct DB reference
if not module.DB.minimap then
	module.DB.minimap = {
		hide = false,
		minimapPos = 220,
	}
end
LDBIcon:Register('MyAddon', DataBroker, module.DB.minimap)
```

This is an exception to the override pattern due to library requirements, not a general practice.

## See Also

- **Existing implementations**:
  - UnitFrames: `Modules/UnitFrames/Framework.lua` (6-level depth, manual wildcards)
  - Minimap: `Modules/Minimap/Minimap.lua` (3-level depth)
  - Font: `Core/Handlers/Font.lua` (1-level wildcards)
- **Framework utilities**:
  - `SUI:CopyData()`: `Core/Framework.lua:1411` (handles `['**']` wildcards)
  - `SUI:MergeData()`: `Core/Framework.lua:1385` (merges with override flag)
