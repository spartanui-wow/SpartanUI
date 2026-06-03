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
	raid = { 'raid10', 'raid25', 'raid40' },
	boss = { 'boss', 'bosstarget' },
	arena = { 'arena' },
	pinned = { 'pinned' },
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

---Get the active preset name for a frame group.
---Uses rawget so AceDB wildcard defaults don't shadow the _default fallback,
---letting per-group entries stay sparse (only stored when they differ from _default).
---@param frameGroupLeader PresetFrameGroupName
---@return string presetName
function Preset:GetActive(frameGroupLeader)
	local explicit = rawget(UF.DB.Presets, frameGroupLeader)
	if explicit then
		return explicit
	end
	return rawget(UF.DB.Presets, '_default') or 'War'
end

---Set the preset for a specific frame group. Clears the entry when it matches
---_default so the DB stays sparse.
---@param groupLeader PresetFrameGroupName
---@param presetName string
function Preset:SetForFrame(groupLeader, presetName)
	local default = rawget(UF.DB.Presets, '_default')
	if presetName == default then
		UF.DB.Presets[groupLeader] = nil
	else
		UF.DB.Presets[groupLeader] = presetName
	end
end

---Apply a theme's default presets to all frame groups (1-click theme application).
---Stores only _default and clears any per-group entries that would shadow it.
---@param themeName string
function Preset:ApplyThemeDefaults(themeName)
	UF.DB.Presets['_default'] = themeName
	for groupLeader, _ in pairs(self.FrameGroups) do
		UF.DB.Presets[groupLeader] = nil
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

---Auto-register presets from ThemeRegistry metadata.
---Called during UF initialization after DB is available.
---Uses theme metadata for applicableTo (no lazy-load triggered).
function Preset:RegisterFromStyles()
	-- Primary: register from ThemeRegistry metadata (no lazy-load triggered)
	local themeList = SUI.ThemeRegistry and SUI.ThemeRegistry:GetList()
	if themeList then
		for themeName, metadata in pairs(themeList) do
			if metadata.applicableTo and next(metadata.applicableTo) then
				self:Register(themeName, {
					displayName = metadata.displayName or themeName,
					applicableTo = metadata.applicableTo,
					source = 'theme',
					themeName = themeName,
					setup = metadata.setup,
				})
			end
		end
	end
end

UF.Preset = Preset
