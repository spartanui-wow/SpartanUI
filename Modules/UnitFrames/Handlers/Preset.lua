---@class SUI.UF
local UF = SUI.UF

---@class SUI.UF.Preset
local Preset = {}

---@type table<string, SUI.UF.PresetDefinition>
local registry = {}

-- Frame group definitions: preset selection at group level, cascades to children.
-- 8 groups covering all 15 unit frame types.
---@type table<PresetFrameGroupName, string[]>
Preset.FrameGroups = {
	player = { 'player' },
	pet = { 'pet', 'pettarget' },
	target = { 'target', 'targettarget', 'targettargettarget' },
	focus = { 'focus', 'focustarget' },
	party = { 'party', 'partypet', 'partytarget' },
	raid = { 'raid' },
	boss = { 'boss', 'bosstarget' },
	arena = { 'arena' },
}

-- Reverse mapping: child frame name -> group leader
---@type table<string, PresetFrameGroupName>
Preset.FrameToGroup = {}

-- Build reverse mapping on load
for groupLeader, members in pairs(Preset.FrameGroups) do
	for _, frameName in ipairs(members) do
		Preset.FrameToGroup[frameName] = groupLeader
	end
end

---Get the group leader for a frame name (e.g., 'partypet' -> 'party')
---@param frameName string
---@return PresetFrameGroupName
function Preset:GetGroupLeader(frameName)
	return self.FrameToGroup[frameName] or frameName
end

---Register a preset in the registry
---@param presetName string
---@param definition SUI.UF.PresetDefinition
function Preset:Register(presetName, definition)
	registry[presetName] = definition
end

---Get the active preset name for a frame group
---@param frameGroupLeader PresetFrameGroupName
---@return string presetName
function Preset:GetActive(frameGroupLeader)
	return UF.DB.Presets[frameGroupLeader] or UF.DB.Presets['_default'] or 'War'
end

---Set the preset for a specific frame group
---@param groupLeader PresetFrameGroupName
---@param presetName string
function Preset:SetForFrame(groupLeader, presetName)
	UF.DB.Presets[groupLeader] = presetName
end

---Apply a theme's default presets to all frame groups (1-click theme application)
---Sets each frame group to the given preset name if that preset has configs for the group.
---Frame groups without configs in the preset are left at the preset name anyway
---(they'll just use base defaults, which is the expected 1-click behavior).
---@param themeName string
function Preset:ApplyThemeDefaults(themeName)
	for groupLeader, _ in pairs(self.FrameGroups) do
		UF.DB.Presets[groupLeader] = themeName
	end
end

---Get presets applicable to a specific frame group
---@param frameGroupLeader PresetFrameGroupName
---@return table<string, SUI.UF.PresetDefinition>
function Preset:GetForFrameType(frameGroupLeader)
	local result = {}
	for name, def in pairs(registry) do
		if def.applicableTo[frameGroupLeader] then
			result[name] = def
		end
	end
	return result
end

---Get the full list of registered presets
---@return table<string, SUI.UF.PresetDefinition>
function Preset:GetList()
	return registry
end

---Get a specific preset definition
---@param presetName string
---@return SUI.UF.PresetDefinition|nil
function Preset:Get(presetName)
	return registry[presetName]
end

---Auto-register presets from SUI.DB.Styles.
---Called during UF initialization after DB is available.
---Each theme's Frames data becomes a preset, with applicableTo derived from which frame types have configs.
function Preset:RegisterFromStyles()
	if not SUI.DB or not SUI.DB.Styles then
		return
	end

	for styleName, styleData in pairs(SUI.DB.Styles) do
		if styleName ~= '**' and type(styleData) == 'table' and styleData.Frames and next(styleData.Frames) then
			-- Determine which frame groups this preset applies to
			local applicableTo = {}
			for frameName, _ in pairs(styleData.Frames) do
				local groupLeader = self:GetGroupLeader(frameName)
				applicableTo[groupLeader] = true
			end

			-- Get display info from UF.Style registry if available
			local styleSetup = nil
			if UF.Style and UF.Style.registry and UF.Style.registry[styleName] then
				local styleSettings = UF.Style.registry[styleName].settings
				if styleSettings and styleSettings.setup then
					styleSetup = styleSettings.setup
				end
			end

			self:Register(styleName, {
				displayName = styleName,
				frameConfigs = styleData.Frames,
				applicableTo = applicableTo,
				source = 'theme',
				themeName = styleName,
				setup = styleSetup,
			})
		end
	end
end

UF.Preset = Preset
