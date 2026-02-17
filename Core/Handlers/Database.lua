---@class SUI
local SUI = SUI
local L = SUI.L

---@class SUI.DBM
local DBManager = {}
SUI.DBM = DBManager

-- Sequential profile refresh callback registry
DBManager.ProfileRefreshCallbacks = {}

---Calculate wildcard depth needed for nested defaults
---@param defaults table The defaults table to analyze
---@param maxDepth? number Maximum depth to check (default 10)
---@return number depth The nesting depth required
local function CalculateWildcardDepth(defaults, maxDepth)
	maxDepth = maxDepth or 10
	local function getDepth(tbl, currentDepth)
		if currentDepth >= maxDepth then
			return currentDepth
		end
		local maxChildDepth = currentDepth
		for _, v in pairs(tbl) do
			if type(v) == 'table' then
				local childDepth = getDepth(v, currentDepth + 1)
				maxChildDepth = math.max(maxChildDepth, childDepth)
			end
		end
		return maxChildDepth
	end
	return getDepth(defaults, 0)
end

---Build AceDB defaults table with wildcard nesting
---@param depth number Nesting depth (0-10)
---@return table wildcardTable The nested wildcard structure
local function BuildWildcardTable(depth)
	if depth <= 0 then
		return {}
	end
	return { ['**'] = BuildWildcardTable(depth - 1) }
end

---Setup a module's database with Configuration Override Pattern
---@param module table The module to setup DB for
---@param defaults table Default values (flat or nested)
---@param globalDefaults? table Global defaults (optional)
---@param options? table Options: { maxDepth: number, autoCalculateDepth: boolean }
function DBManager:SetupModule(module, defaults, globalDefaults, options)
	options = options or {}
	globalDefaults = globalDefaults or {}

	-- Calculate or use provided depth for profile
	local depth = options.maxDepth
	if not depth and options.autoCalculateDepth ~= false then
		depth = CalculateWildcardDepth(defaults)
		if module.logger then
			module.logger.debug('Auto-calculated profile wildcard depth: ' .. depth)
		end
	end
	depth = depth or 0

	-- Calculate depth for global defaults (if provided)
	local globalDepth = 0
	if next(globalDefaults) then
		globalDepth = CalculateWildcardDepth(globalDefaults)
		if module.logger then
			module.logger.debug('Auto-calculated global wildcard depth: ' .. globalDepth)
		end
	end

	-- Build AceDB registration structure with wildcards
	local aceDefaults = {
		profile = depth > 0 and BuildWildcardTable(depth) or {},
		global = globalDepth > 0 and BuildWildcardTable(globalDepth) or {},
	}

	-- Register namespace
	local moduleName = type(module.GetName) == 'function' and module:GetName() or module.moduleName or 'Unknown'
	module.Database = SUI.SpartanUIDB:RegisterNamespace(moduleName, aceDefaults)

	module.DB = module.Database.profile
	module.DBG = module.Database.global
	module.DBDefaults = defaults
	module.DBGlobalDefaults = globalDefaults
	module.CurrentSettings = {}

	-- Store real defaults on the AceDB child DB so the export pipeline can strip them
	-- (AceDB only stores wildcard structure, not actual default values)
	module.Database.realDefaults = { profile = defaults, global = globalDefaults }

	-- Initialize global defaults (ensure tables exist)
	for key, defaultValue in pairs(globalDefaults) do
		if module.DBG[key] == nil and type(defaultValue) == 'table' then
			module.DBG[key] = {}
		end
	end

	-- Register profile change callbacks to auto-update DB references
	-- SetupModule uses the old RegisterProfileCallbacks internally for AceDB callback system
	self:RegisterProfileCallbacks(module)

	-- Initial load
	self:RefreshSettings(module)
end

---Register profile change callbacks for a module (legacy RegisterNamespace support)
---Call this for modules still using RegisterNamespace instead of SetupModule
---@param module table The module to register callbacks for
---@param refreshMethod? string Optional method name to call after DB update (e.g., 'UpdateSettings', 'ApplyTheme')
function DBManager:RegisterProfileCallbacks(module, refreshMethod)
	if not module.Database then
		if module.logger then
			module.logger.warning('RegisterProfileCallbacks called but module.Database is nil')
		end
		return
	end

	-- Create callback function that updates DB references
	local function onProfileChanged()
		if module.Database then
			module.DB = module.Database.profile
			if module.Database.global then
				module.DBG = module.Database.global
			end
			-- If using SetupModule (has CurrentSettings), refresh it
			if module.CurrentSettings and module.DBDefaults then
				DBManager:RefreshSettings(module)
			end
			-- Call optional refresh method to reapply settings
			if refreshMethod and type(module[refreshMethod]) == 'function' then
				module[refreshMethod](module)
			end
		end
	end

	-- Register all three profile change events
	module.Database.RegisterCallback(module, 'OnProfileChanged', onProfileChanged)
	module.Database.RegisterCallback(module, 'OnProfileCopied', onProfileChanged)
	module.Database.RegisterCallback(module, 'OnProfileReset', onProfileChanged)
end

---Refresh CurrentSettings by merging defaults with user changes
---@param module table The module to refresh
function DBManager:RefreshSettings(module)
	-- Start with copy of defaults
	module.CurrentSettings = SUI:CopyData({}, module.DBDefaults)
	-- Merge user settings over defaults (override mode)
	module.CurrentSettings = SUI:MergeData(module.CurrentSettings, module.DB, true)
end

---Standard setter for options - writes to DB and refreshes
---@param module table The module
---@param key string|string[] DB key to set (can be nested path like "minimap.hide")
---@param value any Value to set
---@param callback? function Optional callback after refresh
function DBManager:Set(module, key, value, callback)
	-- Handle nested keys: "minimap.hide" -> DB.minimap.hide
	if type(key) == 'string' and key:find('%.') then
		local keys = {}
		for k in key:gmatch('[^%.]+') do
			table.insert(keys, k)
		end

		local target = module.DB
		for i = 1, #keys - 1 do
			local k = keys[i]
			if not target[k] then
				target[k] = {}
			end
			target = target[k]
		end
		target[keys[#keys]] = value
	else
		module.DB[key] = value
	end

	self:RefreshSettings(module)
	if callback then
		callback()
	end
end

---Get a value from CurrentSettings (convenience helper)
---@param module table The module
---@param key string|string[] Setting key (can be nested path)
---@return any value The setting value
function DBManager:Get(module, key)
	if type(key) == 'string' and key:find('%.') then
		local target = module.CurrentSettings
		for k in key:gmatch('[^%.]+') do
			if type(target) ~= 'table' then
				return nil
			end
			target = target[k]
		end
		return target
	else
		return module.CurrentSettings[key]
	end
end

---Register a module for sequential profile refresh
---This replaces RegisterProfileCallbacks for the new sequential system
---@param module table The module to register
---@param refreshMethod? string Optional method name to call after DB update
function DBManager:RegisterSequentialProfileRefresh(module, refreshMethod)
	table.insert(DBManager.ProfileRefreshCallbacks, {
		module = module,
		refreshMethod = refreshMethod,
	})
end

---Execute all profile refresh callbacks sequentially
---Called by UpdateModuleConfigs when profiles change
function DBManager:ExecuteProfileRefresh()
	for _, entry in ipairs(DBManager.ProfileRefreshCallbacks) do
		local module = entry.module
		local refreshMethod = entry.refreshMethod

		-- Update DB references
		if module.Database then
			module.DB = module.Database.profile
			if module.Database.global then
				module.DBG = module.Database.global
			end

			-- If using SetupModule (has CurrentSettings), refresh it
			if module.CurrentSettings and module.DBDefaults then
				DBManager:RefreshSettings(module)
			end

			-- Call optional refresh method to reapply settings
			if refreshMethod and type(module[refreshMethod]) == 'function' then
				module[refreshMethod](module)
			end
		end
	end
end
