---@class SUI
local SUI = SUI

---@class SUI.ThemeRegistry
local ThemeRegistry = {}
SUI.ThemeRegistry = ThemeRegistry

local API_VERSION = 1

-- Internal storage
local registry = {} ---@type table<string, SUI.ThemeRegistry.Entry>
local dataCache = {} ---@type table<string, SUI.ThemeRegistry.ThemeData>
local sortedNamesCache = nil ---@type string[]|nil

-- ============================================================
-- Bridge: Forward loaded theme data to existing subsystem registries
-- Called once per theme when its data is first loaded.
-- This allows existing code (UF.Style, Minimap, StatusBars, BarSystem)
-- to continue working unchanged during the migration.
-- ============================================================
local function BridgeToSubsystems(themeName, data)
	if data.unitframes and SUI.UF and SUI.UF.Style then
		SUI.UF.Style:Register(themeName, data.unitframes)
	end
	if data.minimap then
		local minimap = SUI:GetModule('Minimap', true)
		if minimap then
			if data.minimap.variants then
				for variantName, settings in pairs(data.minimap.variants) do
					minimap:Register(variantName, settings)
				end
			else
				minimap:Register(themeName, data.minimap)
			end
		end
	end
	if data.statusBars then
		local sb = SUI:GetModule('Artwork.StatusBars', true)
		if sb and sb.RegisterStyle then
			sb:RegisterStyle(themeName, data.statusBars)
		end
	end
	if data.barPositions and SUI.Handlers and SUI.Handlers.BarSystem then
		SUI.Handlers.BarSystem.BarPosition.BT4[themeName] = data.barPositions
	end
	if data.barScales and SUI.Handlers and SUI.Handlers.BarSystem then
		SUI.Handlers.BarSystem.BarScale.BT4[themeName] = data.barScales
	end
end

-- ============================================================
-- Internal: Translate a theme's aura layout for Retail
-- ============================================================
-- Themes describe their aura layout as Buffs/Debuffs frame configs. Retail
-- 12.1 replaced those elements with a single AuraGroups container, so without
-- this every theme would fall back to the bare defaults and lose its intended
-- icon sizes, counts, growth and placement.
--
-- Buffs become group 1 and debuffs group 2, matching the order the user
-- settings migration uses. A theme that defines AuraGroups itself is left
-- alone, so a future theme can opt out by describing groups directly.
---@param frames table<string, table>
local function TranslateThemeAuras(frames)
	for _, frameConfig in pairs(frames) do
		local elements = type(frameConfig) == 'table' and frameConfig.elements

		if type(elements) == 'table' and not elements.AuraGroups then
			local buffs = type(elements.Buffs) == 'table' and elements.Buffs or nil
			local debuffs = type(elements.Debuffs) == 'table' and elements.Debuffs or nil
			-- RaidDebuffs is a Classic-only element now, so a theme's raid
			-- debuff layout has to become a third group or it is lost.
			local raidDebuffs = type(elements.RaidDebuffs) == 'table' and elements.RaidDebuffs or nil

			if buffs or debuffs or raidDebuffs then
				local target = { groups = {} }

				for _, entry in ipairs({
					{ source = buffs, key = 'slot1' },
					{ source = debuffs, key = 'slot2' },
					{ source = raidDebuffs, key = 'slot3', filterMode = 'raid_debuffs' },
				}) do
					local source = entry.source
					if source then
						local group = {}

						for _, key in ipairs({ 'enabled', 'number', 'size', 'spacing' }) do
							if source[key] ~= nil then
								group[key] = source[key]
							end
						end

						if type(source.retail) == 'table' and source.retail.filterMode then
							group.filterMode = source.retail.filterMode
						elseif entry.filterMode then
							group.filterMode = entry.filterMode
						end

						target.groups[entry.key] = group
					end
				end

				-- Growth and placement lived on each element, but 12.1 sets the
				-- growth direction on the container, so both groups now share
				-- one. Prefer whichever the theme actually turned on, since a
				-- disabled group's layout is never seen.
				local anchorSource = buffs
				if not anchorSource or (anchorSource.enabled == false and debuffs and debuffs.enabled ~= false) then
					anchorSource = debuffs or buffs
				end
				anchorSource = anchorSource or raidDebuffs
				if anchorSource.growthx then
					target.growthx = anchorSource.growthx
				end
				if anchorSource.growthy then
					target.growthy = anchorSource.growthy
				end
				if type(anchorSource.position) == 'table' then
					target.position = SUI:CopyData({}, anchorSource.position)
				end

				-- Rows are not a container setting; the flow layout wraps on
				-- width instead. Translate to the row width that produces the
				-- requested number of rows, which is what layoutLimit means.
				local rows = anchorSource.rows
				local count = anchorSource.number
				if type(rows) == 'number' and rows > 1 and type(count) == 'number' then
					local size = type(anchorSource.size) == 'number' and anchorSource.size or 24
					local spacing = type(anchorSource.spacing) == 'number' and anchorSource.spacing or 2
					target.layoutLimit = math.ceil(count / rows) * (size + spacing)
				end

				elements.AuraGroups = target
			end
		end
	end
end

-- ============================================================
-- Internal: Ensure a theme's full data is loaded and cached
-- ============================================================
---@param themeName string
---@return SUI.ThemeRegistry.ThemeData|nil
local function EnsureLoaded(themeName)
	if dataCache[themeName] then
		return dataCache[themeName]
	end

	local entry = registry[themeName]
	if not entry or not entry.dataCallback then
		return nil
	end

	dataCache[themeName] = entry.dataCallback()

	-- Themes still describe auras as Buffs/Debuffs. Retail draws them through
	-- AuraGroups, so translate once here rather than in every theme.
	if SUI.IsRetail and type(dataCache[themeName]) == 'table' and type(dataCache[themeName].frames) == 'table' then
		TranslateThemeAuras(dataCache[themeName].frames)
	end

	BridgeToSubsystems(themeName, dataCache[themeName])
	return dataCache[themeName]
end

-- ============================================================
-- Registration
-- ============================================================

---Register a theme with lightweight metadata and an optional lazy-load data callback.
---Metadata is always kept in memory. The dataCallback is only invoked when a
---consumer first requests the theme's full data (frame configs, artwork, etc.).
---@param metadata SUI.ThemeRegistry.Metadata
---@param dataCallback? fun(): SUI.ThemeRegistry.ThemeData
function ThemeRegistry:Register(metadata, dataCallback)
	-- Validate required fields
	if not metadata or type(metadata.name) ~= 'string' or metadata.name == '' then
		if SUI.logger then
			SUI.logger.error('ThemeRegistry: Register called without a valid name')
		end
		return
	end
	if type(metadata.apiVersion) ~= 'number' then
		if SUI.logger then
			SUI.logger.error('ThemeRegistry: Register called without apiVersion for theme "' .. metadata.name .. '"')
		end
		return
	end

	-- Warn if overwriting
	if registry[metadata.name] then
		if SUI.logger then
			SUI.logger.warning('ThemeRegistry: Overwriting existing theme "' .. metadata.name .. '"')
		end
		-- Clear cached data so it reloads from the new callback
		dataCache[metadata.name] = nil
	end

	-- Fallback displayName
	if not metadata.displayName or metadata.displayName == '' then
		metadata.displayName = metadata.name
	end

	-- Store as registry entry
	---@type SUI.ThemeRegistry.Entry
	local entry = {
		name = metadata.name,
		displayName = metadata.displayName,
		apiVersion = metadata.apiVersion,
		description = metadata.description,
		setup = metadata.setup,
		applicableTo = metadata.applicableTo,
		dataCallback = dataCallback,
		variants = metadata.variants,
		variantGroup = metadata.variantGroup,
		variantCallback = metadata.variantCallback,
	}
	registry[metadata.name] = entry

	-- Invalidate sorted names cache
	sortedNamesCache = nil
end

-- ============================================================
-- Metadata Access (no lazy-load triggered)
-- ============================================================

---Get metadata for a registered theme (does not trigger data loading)
---@param themeName string
---@return SUI.ThemeRegistry.Metadata|nil
function ThemeRegistry:Get(themeName)
	return registry[themeName]
end

---Get all registered theme metadata (does not trigger data loading)
---@return table<string, SUI.ThemeRegistry.Metadata>
function ThemeRegistry:GetList()
	return registry
end

---Get sorted list of theme names for UI dropdowns (does not trigger data loading)
---@return string[]
function ThemeRegistry:GetSortedNames()
	if sortedNamesCache then
		return sortedNamesCache
	end

	sortedNamesCache = {}
	for name, _ in pairs(registry) do
		table.insert(sortedNamesCache, name)
	end
	table.sort(sortedNamesCache)
	return sortedNamesCache
end

-- ============================================================
-- Variant API
-- ============================================================

---Returns the variant list for a theme, or nil if none declared.
---@param themeName string
---@return { id: string, label: string }[]|nil
function ThemeRegistry:GetVariants(themeName)
	local entry = registry[themeName]
	return entry and entry.variants
end

---Returns true if this theme is a sub-theme (variantGroup is set).
---Sub-themes are excluded from the top-level setup wizard card list.
---@param themeName string
---@return boolean
function ThemeRegistry:IsSubTheme(themeName)
	local entry = registry[themeName]
	return entry ~= nil and entry.variantGroup ~= nil
end

---Returns the stored active variant id, falling back to the first declared variant.
---@param themeName string
---@return string|nil
function ThemeRegistry:GetActiveVariant(themeName)
	local entry = registry[themeName]
	if not entry or not entry.variants then
		return nil
	end
	local stored = ThemeRegistry:GetSetting(themeName, 'variant')
	return stored or entry.variants[1].id
end

---Stores the variant selection, applies standard applyStyle/applyUF fields, then invokes the theme's variantCallback.
---@param themeName string
---@param variantId string
function ThemeRegistry:ApplyVariant(themeName, variantId)
	ThemeRegistry:SetSetting(themeName, 'variant', variantId)
	local entry = registry[themeName]

	local variantData
	if entry and entry.variants then
		for _, v in ipairs(entry.variants) do
			if v.id == variantId then
				variantData = v
				break
			end
		end
	end

	if variantData then
		if variantData.applyStyle then
			local artModule = SUI:GetModule('Artwork', true)
			if artModule then
				artModule:SetActiveStyle(variantData.applyStyle)
			end
		end
		if variantData.applyUF and SUI.UF then
			SUI.UF:SetActiveStyle(variantData.applyUF)
		end
	end

	if entry and entry.variantCallback then
		entry.variantCallback(variantId, variantData)
	end
end

-- ============================================================
-- Data Access (triggers lazy-load on first access, then cached)
-- ============================================================

---Get the full theme data (triggers lazy load if needed)
---@param themeName string
---@return SUI.ThemeRegistry.ThemeData|nil
function ThemeRegistry:GetData(themeName)
	return EnsureLoaded(themeName)
end

---Get frame configs for a theme (triggers lazy load)
---@param themeName string
---@return table<string, table>|nil
function ThemeRegistry:GetFrameConfigs(themeName)
	local data = EnsureLoaded(themeName)
	return data and data.frames
end

---Get BlizzMover defaults for a theme (triggers lazy load)
---@param themeName string
---@return table<string, string>|nil
function ThemeRegistry:GetBlizzMovers(themeName)
	local data = EnsureLoaded(themeName)
	return data and data.blizzMovers
end

---Get default color settings for a theme (triggers lazy load)
---@param themeName string
---@return table|nil
function ThemeRegistry:GetColor(themeName)
	local data = EnsureLoaded(themeName)
	return data and data.color
end

---Get sliding tray config for a theme (triggers lazy load)
---@param themeName string
---@return table|nil
function ThemeRegistry:GetSlidingTrays(themeName)
	local data = EnsureLoaded(themeName)
	return data and data.slidingTrays
end

---Get theme callbacks (triggers lazy load)
---@param themeName string
---@return SUI.ThemeRegistry.Callbacks|nil
function ThemeRegistry:GetCallbacks(themeName)
	local data = EnsureLoaded(themeName)
	return data and data.callbacks
end

---Load all registered themes' data (triggers lazy load for any not yet loaded).
---Used by subsystem consumers that need the complete list (e.g., UF Style dropdowns).
function ThemeRegistry:EnsureAllLoaded()
	for themeName, _ in pairs(registry) do
		EnsureLoaded(themeName)
	end
end

---Check if a theme's data has been loaded (without triggering load)
---@param themeName string
---@return boolean
function ThemeRegistry:IsLoaded(themeName)
	return dataCache[themeName] ~= nil
end

-- ============================================================
-- Per-Theme User Settings
-- Merges code-defined defaults (from data.options/data.color)
-- with user overrides stored in SUI.DB.ThemeSettings
-- ============================================================

---Get a per-theme setting, merging code default with user override.
---Supports dot-notation for nested keys (e.g., 'Color.Art').
---@param themeName string
---@param key string Setting key (supports dot notation)
---@return any
function ThemeRegistry:GetSetting(themeName, key)
	-- Check user override first
	local userSettings = SUI.DB and SUI.DB.ThemeSettings and SUI.DB.ThemeSettings[themeName]
	if userSettings then
		local userValue = userSettings
		if key:find('%.') then
			for k in key:gmatch('[^%.]+') do
				if type(userValue) ~= 'table' then
					userValue = nil
					break
				end
				userValue = userValue[k]
			end
		else
			userValue = userSettings[key]
		end
		if userValue ~= nil then
			return userValue
		end
	end

	-- Fall back to code-defined defaults
	local data = EnsureLoaded(themeName)
	if not data then
		return nil
	end

	-- Check data.options first, then data.color for Color.* keys
	if data.options then
		local optValue = data.options
		if key:find('%.') then
			for k in key:gmatch('[^%.]+') do
				if type(optValue) ~= 'table' then
					optValue = nil
					break
				end
				optValue = optValue[k]
			end
		else
			optValue = data.options[key]
		end
		if optValue ~= nil then
			return optValue
		end
	end

	-- Check data.color for 'Color.*' keys
	if data.color and key:find('^Color%.') then
		local colorKey = key:match('^Color%.(.+)$')
		if colorKey and data.color[colorKey] ~= nil then
			return data.color[colorKey]
		end
	end

	return nil
end

---Set a user override for a per-theme setting.
---Supports dot-notation for nested keys.
---@param themeName string
---@param key string Setting key (supports dot notation)
---@param value any
function ThemeRegistry:SetSetting(themeName, key, value)
	if not SUI.DB or not SUI.DB.ThemeSettings then
		return
	end

	if not SUI.DB.ThemeSettings[themeName] then
		SUI.DB.ThemeSettings[themeName] = {}
	end

	if key:find('%.') then
		local target = SUI.DB.ThemeSettings[themeName]
		local keys = {}
		for k in key:gmatch('[^%.]+') do
			table.insert(keys, k)
		end
		for i = 1, #keys - 1 do
			if not target[keys[i]] then
				target[keys[i]] = {}
			end
			target = target[keys[i]]
		end
		target[keys[#keys]] = value
	else
		SUI.DB.ThemeSettings[themeName][key] = value
	end
end

-- ============================================================
-- Utility
-- ============================================================

---Get the current Theme API version
---@return number
function ThemeRegistry:GetAPIVersion()
	return API_VERSION
end
