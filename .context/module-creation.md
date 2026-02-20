# SpartanUI Module Creation Guide

> SpartanUI-specific module patterns. For shared Ace3 module patterns (lifecycle, file organization, AceConfig structure), see the root `.context/ace3-guide.md`.

## 1. Module Structure

```lua
---@class SUI.Module.ModuleName : SUI.Module
local module = SUI:NewModule('ModuleName')
module.DisplayName = L['Display Name']
module.description = 'Brief description of module functionality'
```

## 2. Logger (Subcategory Registration)

SpartanUI modules register as subcategories under the SUI logger — **do not** use `LibAT.Logger.RegisterAddon()` directly (that creates a separate top-level entry).

```lua
function module:OnInitialize()
	if SUI.logger then
		module.logger = SUI.logger:RegisterCategory('ModuleName')
	end
end

-- Usage:
if module.logger then
	module.logger.info('System initialized')
	module.logger.debug('Debug value: ' .. tostring(value))
	module.logger.warning('Deprecated function called')
	module.logger.error('Critical error occurred')
end
```

## 3. Database (Configuration Override Pattern)

Use the unified Database API (`SUI.DBM`) for all module settings. See `.context/Database.md` for full documentation.

```lua
---@class SUI.Module.ModuleName.DB
local DBDefaults = {
	enabled = true,
	scale = 1.0,
	position = { x = 0, y = 0 },
	nested = {
		setting = true,
	},
}

---@class SUI.Module.ModuleName.DBGlobal
local DBGlobalDefaults = {
	favorites = {},
}

function module:OnInitialize()
	SUI.DBM:SetupModule(self, DBDefaults, DBGlobalDefaults, {
		autoCalculateDepth = true,
	})

	-- Now available:
	-- module.DB             - stores ONLY user changes (sparse)
	-- module.DBG            - global settings (cross-character)
	-- module.DBDefaults     - your default values
	-- module.CurrentSettings - merged defaults + user changes
end
```

**Critical rules:**
- **Read from** `module.CurrentSettings` (merged defaults + user changes)
- **Write to** `module.DB` (only stores changes from defaults)
- **Call** `SUI.DBM:RefreshSettings(module)` after any DB write

## 4. Options UI

Options integrate with SUI's AceConfig system. Read from `CurrentSettings`, write to `DB`:

```lua
function module:BuildOptions()
	local options = {
		type = 'group',
		name = module.DisplayName,
		disabled = function()
			return SUI:IsModuleDisabled(module)
		end,
		args = {
			setting = {
				name = L['Setting Name'],
				type = 'toggle',
				order = 1,
				get = function()
					return module.CurrentSettings.enabled
				end,
				set = function(_, val)
					module.DB.enabled = val
					SUI.DBM:RefreshSettings(module)
				end,
			},
		},
	}

	SUI.Options:AddOptions(options, 'ModuleName')
end
```

**Helper alternative** (auto-refresh):

```lua
get = function()
	return SUI.DBM:Get(module, 'enabled')
end,
set = function(_, val)
	SUI.DBM:Set(module, 'enabled', val, function()
		-- Optional callback after refresh
	end)
end,
```

## 5. Localization

Use `SUI.L` for all user-facing strings:

```lua
local L = SUI.L
module.DisplayName = L['Module Display Name']

-- In Options:
name = L['Setting Name'],
desc = L['Setting description for tooltip'],
```

Add new strings to `lang/enUS.lua` (default fallback).

## 6. Lifecycle Example (Complete)

```lua
function module:OnInitialize()
	-- 1. Database
	SUI.DBM:SetupModule(self, DBDefaults, DBGlobalDefaults, {
		autoCalculateDepth = true,
	})

	-- 2. Logger
	if SUI.logger then
		module.logger = SUI.logger:RegisterCategory('ModuleName')
	end
end

function module:OnEnable()
	if SUI:IsModuleDisabled('ModuleName') then
		return
	end

	-- Register events, create UI, start timers
end

function module:OnDisable()
	-- Cleanup: unregister events, hide UI, stop timers
end
```

## 7. Type Annotations

Use LuaLS annotations for all public APIs and DB structures:

```lua
---@class SUI.Module.ModuleName.DB
---@field enabled boolean Enable the module
---@field scale number UI scale (0.5-2.0)

---Function description
---@param paramName type Parameter description
---@return type Description of return value
function module:PublicFunction(paramName)
	-- implementation
end
```

See root `.context/patterns.md` for general annotation patterns.
