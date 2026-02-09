---@class SUI.UF.PresetDefinition
---@field displayName string Human-readable name for UI
---@field frameConfigs table<string, table> Per-frame config overrides (keys are frame names like 'player', 'raid')
---@field applicableTo table<string, boolean> Which frame group leaders this preset supports
---@field setup? UFStyleSetupSettings Preview image for options UI
---@field source string 'theme' or 'standalone'
---@field themeName? string If source='theme', which theme contributed this preset
local PresetDefinition = {}

---@alias PresetFrameGroupName
---|"player"
---|"pet"
---|"target"
---|"focus"
---|"party"
---|"raid"
---|"boss"
---|"arena"
