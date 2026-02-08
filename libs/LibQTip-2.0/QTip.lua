--------------------------------------------------------------------------------
---- Library Namespace
--------------------------------------------------------------------------------

local Version = {
	Major = 'LibQTip-2.0',
	Minor = 1,
}

assert(LibStub, ('%s requires LibStub'):format(Version.Major))

---@class LibQTip-2.0
---@field CallbackRegistry LibQTip-2.0.CallbackRegistry CallbackHandler-1.0 interface.
---@field CellMetatable table<"__index", LibQTip-2.0.Cell> The base metatable for all Cells.
---@field CellPrototype LibQTip-2.0.Cell The prototype all Cells are derived from.
---@field CellProviderKeys string[] List of registered CellProviders, sorted alphabetically.
---@field CellProviderMetatable table<"__index", LibQTip-2.0.CellProvider> The base metatable for all CellProviders.
---@field CellProviderPrototype LibQTip-2.0.CellProvider The prototype all CellProviders are derived from.
---@field CellProviderRegistry table<string, LibQTip-2.0.CellProvider|nil> Registered CellProviders.
---@field DefaultCellPrototype LibQTip-2.0.Cell The library default Cell interface.
---@field DefaultCellProvider LibQTip-2.0.CellProvider The library default CellProvider interface.
---@field FrameMetatable table<"__index", Frame> Used for default Frame methods.
---@field RegisterCallback fun(target: table, eventName: LibQTip-2.0.EventName, handler: string|fun(eventName: LibQTip-2.0.EventName, ...: unknown)) CallbackHandler-1.0 interface.
---@field ScriptManager LibQTip-2.0.ScriptManager Manages all library Script interactions.
---@field TooltipManager LibQTip-2.0.TooltipManager Manages all library Tooltip interactions.
---@field UnregisterCallback fun(target: table, eventName: LibQTip-2.0.EventName) CallbackHandler-1.0 interface.
local QTip, oldMinor = LibStub:NewLibrary(Version.Major, Version.Minor)

if not QTip then
	return
end -- No upgrade needed

QTip.Version = Version
QTip.Version.OldMinor = oldMinor or 0

QTip.FrameMetatable = QTip.FrameMetatable or { __index = CreateFrame('Frame') }

QTip.CallbackRegistry = QTip.CallbackRegistry or LibStub:GetLibrary('CallbackHandler-1.0'):New(QTip)

QTip.CellProviderPrototype = QTip.CellProviderPrototype or {}
QTip.CellProviderMetatable = QTip.CellProviderMetatable or { __index = QTip.CellProviderPrototype }

QTip.CellPrototype = QTip.CellPrototype or setmetatable({}, QTip.FrameMetatable)
QTip.CellMetatable = QTip.CellMetatable or { __index = QTip.CellPrototype }

QTip.DefaultCellPrototype = QTip.DefaultCellPrototype or setmetatable({}, QTip.CellMetatable)
QTip.DefaultCellProvider = QTip.DefaultCellProvider
	or setmetatable({
		CellHeap = {},
		CellMetatable = { __index = QTip.DefaultCellPrototype },
		CellPrototype = QTip.DefaultCellPrototype,
		Cells = {},
	}, QTip.CellProviderMetatable)

QTip.CellProviderKeys = QTip.CellProviderKeys or { 'LibQTip-2.0 Default' }
QTip.CellProviderRegistry = QTip.CellProviderRegistry or {
	['LibQTip-2.0 Default'] = QTip.DefaultCellProvider,
}

QTip.ScriptManager = QTip.ScriptManager or {}
QTip.TooltipManager = QTip.TooltipManager or CreateFrame('Frame')

--------------------------------------------------------------------------------
---- Methods
--------------------------------------------------------------------------------

local TooltipManager = QTip.TooltipManager

-- Create or retrieve the Tooltip with the given key.
--
-- If additional arguments are passed, they are passed to :SetColumnLayout for the acquired Tooltip.
---@param key string The Tooltip key. A key unique to this Tooltip should be provided to avoid conflicts.
---@param numColumns? number Minimum number of Columns
---@param ... JustifyHorizontal Column horizontal justifications ("CENTER", "LEFT" or "RIGHT"). Defaults to "LEFT".
-- ***
-- Example Tooltip with 5 Columns justified as left, center, left, left, left:
-- ``` lua
-- local tooltip = LibStub('LibQTip-2.0'):Acquire('MyFooBarTooltip', 5, "LEFT", "CENTER")
-- ```
-- ***
---@return LibQTip-2.0.Tooltip
function QTip:AcquireTooltip(key, numColumns, ...)
	if type(key) ~= 'string' then
		error(("Parameter 'key' must be of type 'string', not '%s'"):format(type(key)), 2)
	end

	local tooltip = TooltipManager.ActiveTooltips[key]

	if not tooltip then
		tooltip = TooltipManager:AcquireTooltip(key)
		TooltipManager.ActiveTooltips[key] = tooltip
	end

	local isOk, message = pcall(tooltip.SetColumnLayout, tooltip, numColumns, ...)

	if not isOk then
		error(message, 2)
	end

	return tooltip
end

-- Return an iterator on the registered CellProviders.
function QTip:CellProviderPairs()
	return pairs(self.CellProviderRegistry)
end

do
	---@param templateCellProvider? LibQTip-2.0.CellProvider An existing provider used as a template for the new provider.
	---@return LibQTip-2.0.Cell
	---@return table<"__index", LibQTip-2.0.Cell>
	local function GetCellPrototype(templateCellProvider)
		if not templateCellProvider then
			return QTip.DefaultCellProvider:GetCellPrototype()
		end

		if not templateCellProvider.GetCellPrototype then
			error("The supplied CellProvider has no 'GetCellPrototype' method.", 3)
		end

		return templateCellProvider:GetCellPrototype()
	end

	-- Creates a new CellProvider, using an existing CellProvider or the LibQTip-2.0 default CellProvider as a template.
	---@param templateCellProvider? LibQTip-2.0.CellProvider An existing CellProvider used as a template for the new CellProvider.
	---@return LibQTip-2.0.CreateCellProviderValues values The new CellProvider, new Cell prototype, and base Cell prototype.
	---@nodiscard
	function QTip:CreateCellProvider(templateCellProvider)
		local baseCellPrototype, baseCellMetatable = GetCellPrototype(templateCellProvider)

		---@type LibQTip-2.0.Cell
		local newCellPrototype = setmetatable({}, baseCellMetatable)

		return {
			newCellProvider =
				---@type LibQTip-2.0.CellProvider
				setmetatable({
					CellHeap = {},
					Cells = {},
					CellPrototype = newCellPrototype,
					CellMetatable = { __index = newCellPrototype },
				}, self.CellProviderMetatable),
			newCellPrototype = newCellPrototype,
			baseCellPrototype = baseCellPrototype,
		}
	end
end

-- Retrieves a registered CellProvider using the provided key.
---@param key string The CellProvider key.
---@return LibQTip-2.0.CellProvider|nil
function QTip:GetCellProvider(key)
	if type(key) ~= 'string' then
		error(("Parameter 'key' must be of type 'string', not '%s'"):format(type(key)), 2)
	end

	return self.CellProviderRegistry[key]
end

-- Returns an alphabetically-sorted list of all registered CellProvider keys.
---@return LibQTip-2.0.CellProvider[]
function QTip:GetCellProviderKeys()
	return self.CellProviderKeys
end

-- Check if a Tooltip has been acquired with the specified key.
---@param key string The Tooltip key.
---@return boolean
function QTip:IsAcquiredTooltip(key)
	if type(key) ~= 'string' then
		error(("Parameter 'key' must be of type 'string', not '%s'"):format(type(key)), 2)
	end

	return not not TooltipManager.ActiveTooltips[key]
end

-- Registers a CellProvider using the provided key. Registration fails if the key has already been used.
---@param key string The CellProvider key.
---@param cellProvider LibQTip-2.0.CellProvider The CellProvider to register.
---@return boolean isSuccess Whether or not the CellProvider was successfully registered.
function QTip:RegisterCellProvider(key, cellProvider)
	if type(key) ~= 'string' then
		error(("Parameter 'key' must be of type 'string', not '%s'"):format(type(key)), 2)
	end

	local registry = self.CellProviderRegistry

	if registry[key] then
		return false
	end

	registry[key] = cellProvider

	local list = self.CellProviderKeys

	table.wipe(list)

	for registryKey in pairs(registry) do
		table.insert(list, registryKey)
	end

	table.sort(list)

	self.CallbackRegistry:Fire('OnRegisterCellProvider', key)

	return true
end

-- Return an acquired Tooltip to the heap. The Tooltip is cleared and hidden.
---@param tooltip LibQTip-2.0.Tooltip The Tooltip to release. Any invalid values are silently ignored.
function QTip:ReleaseTooltip(tooltip)
	local key = tooltip and tooltip.Key

	if not key or TooltipManager.ActiveTooltips[key] ~= tooltip then
		return
	end

	TooltipManager:ReleaseTooltip(tooltip)
end

-- Return an iterator on the acquired Tooltips.
function QTip:TooltipPairs()
	return pairs(TooltipManager.ActiveTooltips)
end

--------------------------------------------------------------------------------
---- Types
--------------------------------------------------------------------------------

---@class LibQTip-2.0.CallbackRegistry: CallbackHandlerRegistry
---@field Fire fun(self: LibQTip-2.0.CallbackRegistry, eventName: LibQTip-2.0.EventName, ...: unknown)

---@alias LibQTip-2.0.EventName
---|"OnRegisterCellProvider"
---|"OnReleaseTooltip"

---@class LibQTip-2.0.CreateCellProviderValues
---@field newCellProvider LibQTip-2.0.CellProvider The new CellProvider.
---@field newCellPrototype LibQTip-2.0.Cell The prototype of the new Cell.
---@field baseCellPrototype LibQTip-2.0.Cell The prototype of the base CellProvider Cells. It may be used to call base Cell methods.
