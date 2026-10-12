-- A small SpartanUI for loading Modules/Nameplates/Host/SpartanUI.lua headless.
-- SUI is a real AceAddon ('SpartanUI') with stand-ins for the parts a host touches: L, logger,
-- DBM, Options, OptionsWindow.Stage, Setup, ThemeRegistry, Lib.LSM, DB, SpartanUIDB and the
-- module helpers. Reads of fields the mock does not have are listed in H.suiMissing, so a suite
-- can show what the host reached for. Loaded as a chunk: loadfile(...)(M, H, opts).

local M, H, opts = ...
local S = M.S
local rawtostring = S.rawtostring

local SUI = LibStub('AceAddon-3.0'):NewAddon('SpartanUI', 'AceEvent-3.0', 'AceConsole-3.0')
SUI:SetDefaultModuleLibraries('AceEvent-3.0', 'AceTimer-3.0')
_G.SUI = SUI
H.sui = { options = {}, commands = {}, setupSteps = {}, previews = {}, dbm = {}, themeCalls = {} }

-- Flavor flags, worked out the way Core/Framework.lua does
local flags = { [1] = 'IsRetail', [2] = 'IsClassic', [5] = 'IsTBC', [11] = 'IsWrath', [14] = 'IsCata', [19] = 'IsMOP' }
for _, flag in pairs(flags) do
	SUI[flag] = false
end
SUI[flags[WOW_PROJECT_ID] or 'IsRetail'] = true
SUI.IsForever = WOW_PROJECT_ID == 18
if SUI.IsForever then
	SUI.IsRetail = false
end
SUI.IsAnyClassic = not SUI.IsRetail
SUI.wowVersion = M.flavor

SUI.L = setmetatable({}, {
	__index = function(t, k)
		rawset(t, k, k)
		return k
	end,
})

SUI.logger = {
	RegisterCategory = function(_, name)
		return H.Logger(name)
	end,
}

local function deepCopy(t)
	if type(t) ~= 'table' then
		return t
	end
	local out = {}
	for k, v in pairs(t) do
		out[k] = deepCopy(v)
	end
	return out
end

local function merge(into, from)
	for k, v in pairs(from) do
		if type(v) == 'table' and type(into[k]) == 'table' then
			merge(into[k], v)
		else
			into[k] = deepCopy(v)
		end
	end
	return into
end

local function walk(tbl, path, create)
	local node = tbl
	local keys = {}
	for key in path:gmatch('[^.]+') do
		keys[#keys + 1] = key
	end
	for i = 1, #keys - 1 do
		if node[keys[i]] == nil then
			if not create then
				return nil
			end
			node[keys[i]] = {}
		end
		node = node[keys[i]]
	end
	return node, keys[#keys]
end

SUI.DBM = {
	SetupModule = function(_, module, defaults, globalDefaults)
		module.DB = {}
		module.DBG = {}
		module.DBDefaults = defaults or {}
		module.DBGlobalDefaults = globalDefaults or {}
		module.CurrentSettings = merge(deepCopy(module.DBDefaults), module.DB)
		H.sui.dbm[#H.sui.dbm + 1] = module
	end,
	RefreshSettings = function(_, module)
		module.CurrentSettings = merge(deepCopy(module.DBDefaults or {}), module.DB or {})
	end,
	Get = function(_, module, path)
		local node, key = walk(module.CurrentSettings, path, false)
		return node and node[key]
	end,
	Set = function(self, module, path, value, callback)
		local node, key = walk(module.DB, path, true)
		node[key] = value
		self:RefreshSettings(module)
		if callback then
			callback()
		end
	end,
	RegisterProfileCallbacks = function() end,
}

SUI.Options = {
	AddOptions = function(_, tbl, name, parent)
		H.sui.options[#H.sui.options + 1] = { table = tbl, name = name, parent = parent }
	end,
	OpenTo = function(_, path, key)
		H.sui.openedTo = { path = path, key = key }
	end,
	OpenModuleSettings = function(_, name)
		H.sui.openedTo = { path = { name } }
	end,
}

SUI.OptionsWindow = {
	Stage = {
		Register = function(_, provider)
			H.sui.previews[#H.sui.previews + 1] = provider
		end,
	},
}

SUI.Setup = {
	registration = {
		AddStep = function(_, step)
			H.sui.setupSteps[#H.sui.setupSteps + 1] = step
			return step
		end,
	},
	AddHelpers = function() end,
}

-- The theme registry's API is not modeled; every call is recorded and returns nothing
SUI.ThemeRegistry = setmetatable({}, {
	__index = function(_, method)
		return function(...)
			H.sui.themeCalls[#H.sui.themeCalls + 1] = { method = method, n = select('#', ...), ... }
		end
	end,
})

-- Look sources the host reads and the hooks it installs: theme data, accent, fonts, events
H.sui.themes = { War = {} }
H.sui.activeStyle = 'War'
H.sui.accent = { 1, 0.82, 0 }
H.sui.events = {}
H.sui.accentListeners = {}
rawset(SUI.ThemeRegistry, 'GetData', function(_, name)
	return H.sui.themes[name]
end)
function SUI:GetActiveStyle()
	return H.sui.activeStyle
end
SUI.Event = {
	RegisterEvent = function(_, event, fn)
		H.sui.events[event] = H.sui.events[event] or {}
		table.insert(H.sui.events[event], fn)
	end,
}
---Fire a SpartanUI event the host registered through SUI.Event.
function H.FireSUIEvent(event, ...)
	for _, fn in ipairs(H.sui.events[event] or {}) do
		fn(event, ...)
	end
end
SUI.UI = {
	Style = {
		GetAccent = function()
			return H.sui.accent[1], H.sui.accent[2], H.sui.accent[3]
		end,
		OnAccentChanged = function(_, owner, fn)
			H.sui.accentListeners[#H.sui.accentListeners + 1] = fn
		end,
	},
}
-- Font:Refresh() with no module refreshes every module by calling itself, like the real one
SUI.Font = { modules = { 'Global', 'Nameplates', 'UnitFrames', 'Chat' } }
function SUI.Font:GetFont()
	return 'Fonts\\FRIZQT__.TTF'
end
function SUI.Font:Refresh(key)
	if not key then
		for _, name in ipairs(self.modules) do
			self:Refresh(name)
		end
	end
end

SUI.Lib = { LSM = LibStub('LibSharedMedia-3.0', true) }
SUI.BlizzAPI = {
	canaccessvalue = canaccessvalue or function()
		return true
	end,
	issecretvalue = issecretvalue or function()
		return false
	end,
}
SUI.DB = { DisabledModules = {}, Artwork = { Style = 'War' }, scale = 0.92, Styles = {} }
SUI.SpartanUIDB = LibStub('AceDB-3.0'):New('SpartanUIDB', { profile = {} }, true)

function SUI:IsModuleDisabled(name)
	if type(name) == 'table' then
		name = name:GetName()
	end
	return SUI.DB.DisabledModules[name] and true or false
end
function SUI:IsModuleEnabled(name)
	return not SUI:IsModuleDisabled(name)
end
function SUI:GetModuleConflicts()
	return {}
end
function SUI:IsAddonEnabled(addon)
	return M.enabledAddons and M.enabledAddons[addon] or false
end
function SUI:IsAddonDisabled(addon)
	return not SUI:IsAddonEnabled(addon)
end
function SUI:AddChatCommand(name, fn, description)
	H.sui.commands[name] = { fn = fn, description = description }
end

-- The old Modules/Nameplates.lua creates the module at file load in Phases 2 to 4a (Decision 21)
if opts.oldModule ~= false then
	SUI:NewModule('Nameplates')
end

-- Record reads of fields the mock does not have. AceAddon reads some optional fields itself.
local ACEADDON_OPTIONAL = {
	defaultModuleLibraries = true,
	defaultModulePrototype = true,
	defaultModuleState = true,
	enabledState = true,
	OnInitialize = true,
	OnEnable = true,
	OnDisable = true,
	OnModuleCreated = true,
	OnEmbedInitialize = true,
	OnEmbedEnable = true,
	OnEmbedDisable = true,
	baseName = true,
	moduleName = true,
}
H.suiMissing = {}
local meta = getmetatable(SUI)
meta.__index = function(_, key)
	if not ACEADDON_OPTIONAL[key] then
		H.suiMissing[rawtostring(key)] = (H.suiMissing[rawtostring(key)] or 0) + 1
	end
	return nil
end

return SUI
