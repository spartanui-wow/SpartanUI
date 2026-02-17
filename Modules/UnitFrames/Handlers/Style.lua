---@class SUI.UF
local UF = SUI.UF

local Style = {}
local registry = {}

---@type SUI.Style.Settings.UnitFrames
local Defaults = {
	displayName = 'Default',
	positions = {},
	artwork = {},
	setup = {
		image = 'Interface\\AddOns\\SpartanUI\\Media\\Textures\\UI-StatusBar',
	},
}

---Register a style within the registry
---@param styleName string
---@param settings SUI.Style.Settings.UnitFrames
---@param update? function
function Style:Register(styleName, settings, update)
	registry[styleName] = {
		settings = SUI:CopyData(settings, Defaults),
		update = update,
	}

	if not registry[styleName].setup then
		registry[styleName].setup = {}
	end
end

---Activates a specified style's artwork update callback.
---Does NOT change preset assignments (that's handled by UF.Preset).
---@param styleName? string
function Style:Change(styleName)
	local name = styleName or SUI:GetActiveStyle() or 'War'
	if registry[name] and registry[name].update then
		registry[name].update()
	end
end

---Returns the full list of registered styles.
---Ensures all theme data is loaded so all styles are registered via BridgeToSubsystems.
function Style:GetList()
	if SUI.ThemeRegistry then
		SUI.ThemeRegistry:EnsureAllLoaded()
	end
	return registry
end

---Get config for the specified styleName or the global artwork style
---@param styleName? string
---@return SUI.Style.Settings.UnitFrames
function Style:Get(styleName)
	if styleName == 'war' then
		styleName = 'War'
	end

	local name = styleName or SUI:GetActiveStyle() or 'War'
	if registry[name] then
		return registry[name].settings
	end
	return registry['War'] and registry['War'].settings or Defaults
end

Style.registry = registry
UF.Style = Style
