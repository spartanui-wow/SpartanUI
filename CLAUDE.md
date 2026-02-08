# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SpartanUI is a comprehensive World of Warcraft addon that provides a complete user interface overhaul. It moves interface elements to the bottom of the screen to free up screen real estate and includes modular components for various gameplay features.

## Core Architecture

### Main Framework

- **Core/Framework.lua**: Main addon initialization, library management, and core SUI object setup
- **SpartanUI.toc**: Addon manifest defining load order and dependencies
- **Framework.Definition.lua**: Type definitions and framework structure

### Module System

The addon uses a modular architecture where each feature is a separate module:

- **Modules/**: Contains all feature modules (Minimap, UnitFrames, Artwork, etc.)
- **Core/Handlers/**: Core functionality handlers (Events, Options, Profiles, etc.)
- Each module typically has its own Options.lua file for configuration

#### Creating New Modules

When creating a new module in SpartanUI, follow these standards:

##### 1. Module Structure

```lua
---@class SUI.Module.ModuleName : SUI.Module
local module = SUI:NewModule('ModuleName')
module.DisplayName = L['Display Name']
module.description = 'Brief description of module functionality'
```

##### 2. Logging

**REQUIRED**: All modules must use the Libs-AddonTools Logger system:

```lua
function module:OnInitialize()
	-- Register logger as subcategory under SUI
	if SUI.logger then
		module.logger = SUI.logger:RegisterCategory('ModuleName')
	end
end

-- Usage throughout module:
if module.logger then
	module.logger.info('System initialized')
	module.logger.debug('Debug value: ' .. tostring(value))
	module.logger.warning('Deprecated function called')
	module.logger.error('Critical error occurred')
end
```

**Never use `print()` statements**. Use `/logs` in-game to view all logged output.

##### 3. Database (Configuration Override Pattern)

**REQUIRED**: Use the unified Database API (`SUI.DBM`) for all module settings:

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
	-- Setup database with Configuration Override Pattern
	SUI.DBM:SetupModule(self, DBDefaults, DBGlobalDefaults, {
		autoCalculateDepth = true, -- Auto-detect nesting depth
	})

	-- Now available:
	-- module.DB - stores ONLY user changes (sparse)
	-- module.DBG - global settings (cross-character)
	-- module.DBDefaults - your default values
	-- module.CurrentSettings - merged defaults + user changes
end
```

**Critical Rules:**

- **Read from** `module.CurrentSettings` (merged defaults + user changes)
- **Write to** `module.DB` (only stores changes from defaults)
- **Call** `SUI.DBM:RefreshSettings(module)` after any DB write

See `.context/Database.md` for full documentation.

##### 4. Ace3 Module Lifecycle

All modules inherit from Ace3's module system with standard lifecycle hooks:

```lua
function module:OnInitialize()
	-- Setup DB, logger, constants
	-- Called once when addon loads
end

function module:OnEnable()
	-- Register events, create UI, start timers
	-- Called when module is enabled

	-- Check if disabled:
	if SUI:IsModuleDisabled('ModuleName') then
		return
	end
end

function module:OnDisable()
	-- Cleanup: unregister events, hide UI, stop timers
	-- Called when module is disabled
end
```

##### 5. Options UI

Options should integrate with SUI's AceConfig system:

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
					return module.CurrentSettings.enabled -- Read from CurrentSettings
				end,
				set = function(_, val)
					module.DB.enabled = val -- Write to DB
					SUI.DBM:RefreshSettings(module)
				end,
			},
		},
	}

	-- Register with SUI options system
	SUI.Options:AddOptions(options, 'ModuleName')
end
```

**Helper alternative:**

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

##### 6. File Organization

Standard module structure:

```
Modules/ModuleName/
├── ModuleName.lua      # Main logic, lifecycle hooks
├── Options.lua         # AceConfig options table
├── Data.lua           # Static data tables (optional)
└── Load.xml           # File load order (if needed)
```

##### 7. Type Annotations

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

##### 8. Localization

Use `SUI.L` for all user-facing strings:

```lua
local L = SUI.L
module.DisplayName = L['Module Display Name']

-- In Options:
name = L['Setting Name'],
desc = L['Setting description for tooltip'],
```

Add new strings to `lang/enUS.lua` (default fallback)

### Theme System

- **Themes/**: Multiple visual themes (Classic, War, Fel, Digital, etc.)
- **\_Theme.Definition.lua**: Base theme structure
- Each theme has Style.lua and Style.xml files plus image assets

### Libraries

- **libs/**: Third-party libraries including Ace3, oUF (unit frames), LibSharedMedia
- Uses LibStub for library management
- Extensive use of Ace3 framework for addon structure
- **LibAT.UI**: UI widget system provided by Libs-AddonTools for creating windows, buttons, checkboxes, etc.

## Key Commands

### Chat Commands

- `/sui` - Opens main options window
- `/sui > ModuleName` - Navigate directly to specific module options (e.g. `/sui > Artwork`)
- `/rl` - Reload UI (custom slash command)

### Development

This is a WoW addon project with no traditional build system. Development workflow:

1. Edit Lua/XML files directly
2. Use `/rl` in-game to reload changes
3. Test changes in World of Warcraft client

## File Structure Patterns

### Module Structure

```
Modules/ModuleName/
├── ModuleName.lua          # Main module logic
├── Options.lua             # Configuration options
└── Load.xml               # XML loader (if needed)
```

### Unit Frames

```
Modules/UnitFrames/
├── Framework.lua           # Main UF framework
├── Options.lua            # UF options
├── Elements/              # Individual UF elements (Health, Power, etc.)
├── Units/                 # Unit-specific configurations
└── Handlers/              # UF handlers (Style, Auras, etc.)
```

## Development Notes

### Lua Environment

- Uses World of Warcraft Lua API
- Extensive type annotations with @class and @field
- Global SUI object provides addon framework access

### Code Annotations

Use LuaLS annotations for proper documentation of function parameters and return values:

```lua
---@param paramName type Description of parameter
---@param optionalParam? type Optional parameter (note the ?)
---@return type Description of return value
---@return type|nil secondReturn Optional second return value
function MyFunction(paramName, optionalParam)
    -- function body
end
```

**Key annotation patterns:**

- `---@param name type` - Required parameter
- `---@param name? type` - Optional parameter
- `---@return type` - Return value
- `---@return type|nil` - Optional/nullable return
- `---@class ClassName` - Class definition
- `---@class ClassName : ParentClass` - Class inheritance
- `---@field fieldName type` - Class field
- `---@type type` - Variable type annotation
- `---@overload fun(params): returns` - Function overloads

**Class Extension:**
Classes can be extended by redefining them in different files. This allows adding fields and methods incrementally:

```lua
-- File 1: Initial class definition
---@class MyClass
---@field initialField string

-- File 2: Extend the same class
---@class MyClass
---@field newField number
---@field anotherMethod fun(): boolean
```

Always document function inputs and outputs to improve code maintainability and IDE support.

### Code Formatting

**IMPORTANT**: This project uses StyLua for automatic code formatting.

- **Formatter**: StyLua (https://github.com/JohnnyMorganz/StyLua)
- **Auto-format**: Runs automatically on save in VS Code
- **Git Hook**: Pre-commit hook formats all staged Lua files (excluding `libs/`)
- **Manual Format**: Run `.\format-lua.ps1` to format all files

**StyLua Configuration** (`.stylua.toml`):

```toml
syntax = "Lua51"                          # WoW uses Lua 5.1
column_width = 200                        # Target line length
line_endings = "Unix"                     # LF line endings
indent_type = "Tabs"                      # Use tabs for indentation
indent_width = 4                          # 4-space tab width
quote_style = "AutoPreferSingle"          # Prefer single quotes (''), use double when fewer escapes
call_parentheses = "Always"               # Always use parentheses on function calls
collapse_simple_statement = "Never"       # Don't collapse statements to single lines
space_after_function_names = "Never"      # No space between function name and parentheses
block_newline_gaps = "Never"              # No automatic newline gaps in blocks

[sort_requires]
enabled = false                           # Don't auto-sort require statements
```

**Best Practices**:

- Don't worry about formatting while coding - StyLua handles it automatically
- The `libs/` directory is excluded from formatting (third-party code)
- Formatting differences will be minimal thanks to the pre-commit hook
- To ignore formatting for specific code blocks, use `-- stylua: ignore` comments

### Logging and Debug Output

**IMPORTANT**: Always use the Libs-AddonTools Logger system for debug output and testing. Never use `print()` statements.

- **SpartanUI Logger**: SUI registers a top-level logger as `SUI.logger` in `Core/Framework.lua`
- **Module Logging**: Each module should register a category via `SUI.logger:RegisterCategory(moduleName)` — this creates a subcategory under "SpartanUI" in the `/logs` UI
- **Usage**: Use logger functions with appropriate log levels (debug, info, warning, error, critical)
- **Access Logs**: Use `/logs` in-game to view all logged output in a searchable UI
- **Why**: Print statements overflow the chat window and make debugging difficult. The logger provides persistent, searchable, filterable output.

**Module Logger Setup (required pattern):**

```lua
-- In OnInitialize, register a category under SUI's logger
function module:OnInitialize()
    -- ... DB setup ...
    if SUI.logger then
        module.logger = SUI.logger:RegisterCategory('ModuleName')
    end
end

-- Throughout your module code
if module.logger then
    module.logger.info('System initialized')
    module.logger.debug('Debug value: ' .. tostring(value))
    module.logger.warning('Deprecated function called')
end
```

**Do NOT use** `LibAT.Logger.RegisterAddon()` directly in SpartanUI modules — that creates a separate top-level addon entry. Always use `SUI.logger:RegisterCategory()` to keep logs organized under the SpartanUI hierarchy.

### Configuration System

- Uses AceConfig for options UI
- Profiles managed through AceDB
- Options structured as nested tables with specific AceConfig format

### Event Handling

- Uses AceEvent for event registration
- Module-based event handling
- Core event handlers in Core/Handlers/Events.lua

### Dependencies

- **Required**: Bartender4 (action bar addon), Libs-AddonTools (UI system and utilities)
- **Optional**: Various other addons for enhanced functionality

### WoW API Documentation Resources

When working with WoW addon development, use these authoritative resources:

- **TOC Format Variables**: https://warcraft.wiki.gg/wiki/TOC_format
  - Reference when modifying .toc files for available variables
- **Latest Interface Versions**: https://warcraft.wiki.gg/wiki/Template:API_LatestInterface
  - Quick lookup for current patch interface version numbers
- **API Reference**: https://warcraft.wiki.gg
  - Most up-to-date resource for all WoW API lookups
  - Primary reference for API documentation and best practices

Always use warcraft.wiki.gg as the primary reference for API lookups and documentation.

### Testing

No automated test framework available. All testing must be done manually:

1. Load addon in World of Warcraft client
2. Test functionality in-game
3. Use `/rl` to reload after making changes
4. Check for Lua errors using in-game error display or BugSack addon

**VS Code Problems Tab:**

The VS Code Problems tab will display:

- **Lua formatting issues**: Most can be fixed by simply saving the file (Ctrl+S) or running "Format Document" (Shift+Alt+F)
- **WoW API errors**: Deprecated or non-existent Blizzard globals flagged by the language server

Note: Formatting issues are easily resolved and don't need to be a primary concern during development.

**Important Notes:**

- `luac` command does not work in this environment for syntax checking
- Use VS Code IDE integration for error detection via the Problems tab
- Only focus on actual errors, not formatting issues (formatting is auto-handled on save)
- Lua syntax errors and WoW API issues will be flagged by the language server

## Important Locations

- **Core/Framework.lua:1-100** - Main addon initialization and library setup
- **Core/Handlers/ChatCommands.lua:8-32** - Chat command handling logic
- **Modules/LoadAll.xml** - Module loading order
- **SpartanUI.toc** - Addon metadata and file loading order
