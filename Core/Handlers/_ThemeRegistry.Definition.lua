---@class SUI
local SUI = SUI

-- ============================================================
-- Theme Registry Type Definitions
-- ============================================================

---Metadata registered with every theme (always in memory, lightweight)
---@class SUI.ThemeRegistry.Metadata
---@field name string Internal theme name (e.g., 'War', 'Classic') - REQUIRED
---@field displayName string Human-readable display name - REQUIRED
---@field apiVersion number Theme API version for compatibility checking - REQUIRED
---@field description? string Short description of the theme
---@field setup? SUI.ThemeRegistry.SetupInfo Preview info for the setup wizard
---@field applicableTo? table<string, boolean> Which frame groups this theme provides configs for

---Setup wizard preview info
---@class SUI.ThemeRegistry.SetupInfo
---@field image? string Path to preview image texture

---Full theme data returned by the lazy-load callback
---@class SUI.ThemeRegistry.ThemeData
---@field frames? table<string, table> Per-frame UF config overrides
---@field unitframes? table UF artwork settings (textures, positions, callbacks)
---@field minimap? table Minimap layout settings
---@field statusBars? table Status bar appearance settings
---@field barPositions? table<string, string> Bartender4 bar position strings
---@field barScales? table<string, number> Bartender4 bar scale values
---@field blizzMovers? table<string, string> Default Blizzard frame position strings
---@field slidingTrays? table Sliding tray configuration
---@field color? table Default color settings (user-overridable via ThemeSettings)
---@field options? table<string, any> Per-theme custom options (user-overridable via ThemeSettings)
---@field callbacks? SUI.ThemeRegistry.Callbacks Theme lifecycle callbacks

---Theme lifecycle callbacks
---@class SUI.ThemeRegistry.Callbacks
---@field createArtwork? function Called when theme artwork should be created
---@field onEnable? function Called when theme is activated
---@field onDisable? function Called when theme is deactivated

---Internal registry entry combining metadata with data loading state
---@class SUI.ThemeRegistry.Entry : SUI.ThemeRegistry.Metadata
---@field dataCallback? fun(): SUI.ThemeRegistry.ThemeData Lazy-load callback

---@class SUI.ThemeRegistry
---@field Register fun(self: SUI.ThemeRegistry, metadata: SUI.ThemeRegistry.Metadata, dataCallback?: fun(): SUI.ThemeRegistry.ThemeData)
---@field Get fun(self: SUI.ThemeRegistry, themeName: string): SUI.ThemeRegistry.Metadata|nil
---@field GetData fun(self: SUI.ThemeRegistry, themeName: string): SUI.ThemeRegistry.ThemeData|nil
---@field GetFrameConfigs fun(self: SUI.ThemeRegistry, themeName: string): table<string, table>|nil
---@field GetBlizzMovers fun(self: SUI.ThemeRegistry, themeName: string): table<string, string>|nil
---@field GetColor fun(self: SUI.ThemeRegistry, themeName: string): table|nil
---@field GetList fun(self: SUI.ThemeRegistry): table<string, SUI.ThemeRegistry.Metadata>
---@field GetSortedNames fun(self: SUI.ThemeRegistry): string[]
---@field GetSetting fun(self: SUI.ThemeRegistry, themeName: string, key: string): any
---@field SetSetting fun(self: SUI.ThemeRegistry, themeName: string, key: string, value: any)
