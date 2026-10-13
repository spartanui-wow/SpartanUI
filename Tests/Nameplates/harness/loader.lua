-- Loads libraries and the nameplate module into the mock client.
--   H.LoadLibs()            Ace3 (real files from libs/Ace3) and LibSharedMedia
--   H.LoadCore(opts)        every file Modules/Nameplates/Load.xml lists, in order, with a host stub
--   H.LoadSpartanUIHost()   the SpartanUI host file against a small SUI mock (harness/suimock.lua)
--   H.HostStub(overrides)   a host table in the shape P:Initialize expects (plan 6.11)

local M, T = ...
local S = M.S
local rawtype = S.rawtype
local rawtostring = S.rawtostring

local H = { root = HARNESS_ROOT, hostCalls = {}, logs = {}, loaded = {} }
local ROOT = HARNESS_ROOT

local function normalize(path)
	path = path:gsub('\\', '/')
	local parts = {}
	for part in path:gmatch('[^/]+') do
		if part == '..' and #parts > 0 and parts[#parts] ~= '..' then
			parts[#parts] = nil
		elseif part ~= '.' then
			parts[#parts + 1] = part
		end
	end
	local out = table.concat(parts, '/')
	if path:sub(1, 1) == '/' then
		out = '/' .. out
	end
	return out
end
H.Normalize = normalize

function H.Exists(path)
	local fh = io.open(path, 'r')
	if fh then
		fh:close()
		return true
	end
	return false
end

function H.ReadFile(path)
	local fh = io.open(path, 'rb')
	if not fh then
		return nil
	end
	local text = fh:read('*a')
	fh:close()
	return text
end

---Run one addon file the way the client does: the chunk gets (addonName, addonTable).
function H.LoadFile(path, addonName, ns)
	local chunk, err = loadfile(path)
	if not chunk then
		error('cannot load ' .. path .. ': ' .. rawtostring(err), 2)
	end
	local ok, runErr = xpcall(chunk, function(e)
		return rawtostring(e) .. '\n' .. debug.traceback('', 2)
	end, addonName, ns)
	if not ok then
		error('error while loading ' .. path .. ':\n' .. rawtostring(runErr), 0)
	end
	H.loaded[#H.loaded + 1] = path
end

----------------------------------------------------------------------------------------------------
-- XML: <Script file>, <Include file>, and virtual templates the addon defines
----------------------------------------------------------------------------------------------------

---Entries of a Load.xml in load order, following <Include> files.
---@return table[] entries { kind = 'script'|'template'|'other', path, name, tag }
function H.ParseLoadXml(path, out, seen)
	out = out or {}
	seen = seen or {}
	path = normalize(path)
	if seen[path] then
		return out
	end
	seen[path] = true
	local text = H.ReadFile(path)
	if not text then
		error('missing XML file ' .. path, 2)
	end
	local dir = path:match('^(.*)/[^/]*$') or '.'
	text = text:gsub('<!%-%-.-%-%->', '')
	for tag in text:gmatch('<(%a[%w_]*%s[^>]*)>') do
		local name = tag:match('^(%a[%w_]*)')
		local file = tag:match('file%s*=%s*"([^"]+)"')
		if name == 'Script' and file then
			out[#out + 1] = { kind = 'script', path = normalize(dir .. '/' .. file) }
		elseif name == 'Include' and file then
			local included = normalize(dir .. '/' .. file)
			if included:match('%.lua$') then
				out[#out + 1] = { kind = 'script', path = included }
			else
				H.ParseLoadXml(included, out, seen)
			end
		elseif tag:find('virtual%s*=%s*"true"') and tag:match('name%s*=%s*"([^"]+)"') then
			out[#out + 1] = { kind = 'template', name = tag:match('name%s*=%s*"([^"]+)"'), tag = name }
		elseif name ~= 'Ui' and tag:match('name%s*=%s*"([^"]+)"') then
			out[#out + 1] = { kind = 'other', name = tag:match('name%s*=%s*"([^"]+)"'), tag = name }
		end
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- Libraries
----------------------------------------------------------------------------------------------------

local LIBS = {
	'libs/Ace3/LibStub/LibStub.lua',
	'libs/Ace3/CallbackHandler-1.0/CallbackHandler-1.0.lua',
	'libs/Ace3/AceAddon-3.0/AceAddon-3.0.lua',
	'libs/Ace3/AceEvent-3.0/AceEvent-3.0.lua',
	'libs/Ace3/AceTimer-3.0/AceTimer-3.0.lua',
	'libs/Ace3/AceBucket-3.0/AceBucket-3.0.lua',
	'libs/Ace3/AceHook-3.0/AceHook-3.0.lua',
	'libs/Ace3/AceDB-3.0/AceDB-3.0.lua',
	'libs/Ace3/AceLocale-3.0/AceLocale-3.0.lua',
	'libs/Ace3/AceConsole-3.0/AceConsole-3.0.lua',
	'libs/Ace3/AceSerializer-3.0/AceSerializer-3.0.lua',
	'libs/Ace3/AceConfig-3.0/AceConfigRegistry-3.0/AceConfigRegistry-3.0.lua',
	'libs/Ace3/AceConfig-3.0/AceConfigCmd-3.0/AceConfigCmd-3.0.lua',
	'libs/Ace3/AceGUI-3.0/AceGUI-3.0.lua',
	'libs/LibSharedMedia-3.0/LibSharedMedia-3.0.lua',
}

---Load the shared libraries once. AceConfigDialog is a recording stand-in (it needs every AceGUI widget).
function H.LoadLibs()
	if H.libsLoaded then
		return
	end
	H.libsLoaded = true
	for _, lib in ipairs(LIBS) do
		H.LoadFile(ROOT .. lib, 'SpartanUI', {})
	end
	local dialog = LibStub:NewLibrary('AceConfigDialog-3.0', 999999)
	if dialog then
		H.dialogCalls = {}
		local record = function(name)
			return function(_, ...)
				H.dialogCalls[#H.dialogCalls + 1] = { name, ... }
			end
		end
		dialog.Open = record('Open')
		dialog.Close = record('Close')
		dialog.SelectGroup = record('SelectGroup')
		dialog.SetDefaultSize = record('SetDefaultSize')
		dialog.AddToBlizOptions = function(_, app, name)
			H.dialogCalls[#H.dialogCalls + 1] = { 'AddToBlizOptions', app, name }
			return nil, app
		end
	end
end

---A LibAT stand-in: every field is a callable proxy that records the call path.
---It is permissive on purpose; LibAT itself is not under test here.
function H.InstallLibATStub()
	if rawget(_G, 'LibAT') then
		return LibAT
	end
	H.libatCalls = {}
	local function proxy(path)
		return setmetatable({}, {
			__index = function(t, k)
				local child = proxy(path .. '.' .. rawtostring(k))
				rawset(t, k, child)
				return child
			end,
			__call = function(_, ...)
				H.libatCalls[#H.libatCalls + 1] = { path = path, n = select('#', ...), ... }
			end,
		})
	end
	LibAT = proxy('LibAT')
	return LibAT
end

----------------------------------------------------------------------------------------------------
-- Host stub (plan 6.11)
----------------------------------------------------------------------------------------------------

local function recorder(name)
	return function(...)
		H.hostCalls[#H.hostCalls + 1] = { name = name, n = select('#', ...), ... }
	end
end

---A host table with neutral values. Nothing in it names a real addon, so a core that leans on the
---host's identity shows up in tests. overrides replace fields.
function H.HostStub(overrides)
	local logger = H.Logger('host')
	local host = {
		name = 'Test Host',
		savedVariable = 'NameplatesTestDB',
		mediaPath = 'Interface\\AddOns\\NameplatesTestHost\\Media\\',
		logger = logger,
		media = LibStub and LibStub('LibSharedMedia-3.0', true) or nil,
		AddOptions = recorder('AddOptions'),
		OptionsPath = function(page)
			return { 'Nameplates', page }
		end,
		OpenOptions = recorder('OpenOptions'),
		AddSetupSteps = recorder('AddSetupSteps'),
		RegisterCommand = recorder('RegisterCommand'),
		RegisterPreview = recorder('RegisterPreview'),
		ImportLegacy = function()
			H.hostCalls[#H.hostCalls + 1] = { name = 'ImportLegacy', n = 0 }
			return nil
		end,
		GetHostLook = function()
			return nil
		end,
		GetHostProfileName = function()
			return 'Default'
		end,
		profileDefaults = {},
		widgets = { cardGrid = 'TestCardGrid' },
		widgetPrefix = 'TestNameplates',
		conflicts = {},
	}
	for k, v in pairs(overrides or {}) do
		host[k] = v
	end
	return host
end

---A logger like the ones hosts hand in; lines go to H.logs[category].
function H.Logger(category)
	local lines = {}
	H.logs[category] = lines
	local function level(name)
		return function(msg)
			lines[#lines + 1] = name .. ': ' .. rawtostring(msg)
		end
	end
	return { debug = level('debug'), info = level('info'), warning = level('warning'), error = level('error'), critical = level('critical') }
end

----------------------------------------------------------------------------------------------------
-- The module
----------------------------------------------------------------------------------------------------

H.moduleXml = ROOT .. 'Modules/Nameplates/Load.xml'
H.hostFile = ROOT .. 'Modules/Nameplates/Host/SpartanUI.lua'

function H.ModuleExists()
	return H.Exists(H.moduleXml)
end

---Load the nameplate core into the mock.
---opts: xml (path), addonName (default 'NameplatesTestHost'), ns (addon table), libs (false to skip),
---libat (false to skip the LibAT stand-in)
---@return table ns, table report { files, templates, other }
function H.LoadCore(opts)
	opts = opts or {}
	if opts.libs ~= false then
		H.LoadLibs()
	end
	if opts.libat ~= false then
		H.InstallLibATStub()
	end
	local xml = opts.xml or H.moduleXml
	local ns = opts.ns or {}
	local addonName = opts.addonName or 'NameplatesTestHost'
	local report = { files = {}, templates = {}, other = {} }
	for _, entry in ipairs(H.ParseLoadXml(xml)) do
		if entry.kind == 'script' then
			H.LoadFile(entry.path, addonName, ns)
			report.files[#report.files + 1] = entry.path
		elseif entry.kind == 'template' then
			M.RegisterTemplate(entry.name)
			report.templates[#report.templates + 1] = entry.name
		else
			report.other[#report.other + 1] = entry.name
		end
	end
	H.ns = ns
	return ns, report
end

local freshCount = 0

---Load a new, separate copy of the core with its own SavedVariable, so one suite can start from
---several database states. opts: saved (raw SavedVariable table to start from), host (host field
---overrides), before(P) (runs after loading, before P:Initialize), initialize (false to skip it).
---@return table P, table ns, string savedVariable
function H.FreshCore(opts)
	opts = opts or {}
	H.LoadLibs()
	H.InstallLibATStub()
	freshCount = freshCount + 1
	local sv = opts.savedVariable or ('NameplatesTestDB' .. freshCount)
	rawset(_G, sv, opts.saved)
	local ns = H.LoadCore({ libs = false, ns = {} })
	local P = ns.Plates
	if opts.before then
		opts.before(P)
	end
	if opts.initialize ~= false then
		local overrides = { savedVariable = sv }
		for k, v in pairs(opts.host or {}) do
			overrides[k] = v
		end
		P:Initialize(H.HostStub(overrides))
	end
	return P, ns, sv
end

---Load the SpartanUI host file after the core, against the SUI mock. The host creates the
---Nameplates module itself.
---opts: ns (the core's addon table), file (host path)
---@return table SUI, table ns
function H.LoadSpartanUIHost(opts)
	opts = opts or {}
	H.LoadLibs()
	local SUI = H.InstallSUIMock(opts)
	local ns = opts.ns or H.ns or {}
	H.LoadFile(opts.file or H.hostFile, 'SpartanUI', ns)
	return SUI, ns
end

---A permissive stand-in for a SpartanUI system the mock does not model. Every index and call
---returns another stand-in, and calls are recorded in the returned list as { path, n, ... }.
---@param path string
---@param calls? table
---@return table proxy, table calls
function H.DeepProxy(path, calls)
	calls = calls or {}
	local function make(p)
		return setmetatable({}, {
			__index = function(t, k)
				local child = make(p .. '.' .. rawtostring(k))
				rawset(t, k, child)
				return child
			end,
			__call = function(_, ...)
				calls[#calls + 1] = { path = p, n = select('#', ...), ... }
				return make(p .. '()')
			end,
		})
	end
	return make(path), calls
end

H.loadAllXml = ROOT .. 'Modules/LoadAll.xml'
-- The old nameplate module, retired in Phase 4b; it must not come back
H.oldModuleFile = ROOT .. 'Modules/Nameplates.lua'

---The nameplate entries of Modules/LoadAll.xml in load order: every core file the Include of
---Nameplates/Load.xml lists, then the host, exactly as the client walks the XML.
---@return table[] entries, integer firstIndex, integer lastIndex, table all
function H.NameplateLoadEntries()
	local all = H.ParseLoadXml(H.loadAllXml)
	local folder = normalize(ROOT .. 'Modules/Nameplates') .. '/'
	local first, last
	for i, entry in ipairs(all) do
		if entry.kind == 'script' then
			if entry.path:sub(1, #folder) == folder then
				first = first or i
			end
			if entry.path == normalize(H.hostFile) then
				last = i
			end
		end
	end
	local out = {}
	if first and last then
		for i = first, last do
			out[#out + 1] = all[i]
		end
	end
	return out, first, last, all
end

---Load the core and the host in LoadAll.xml order against the SUI mock, as the game does: the host
---creates the Nameplates module.
---opts: saved (raw SpartanUINameplatesDB to start from)
---@return table SUI, table ns, table module
function H.LoadNameplatesLikeTheGame(opts)
	opts = opts or {}
	H.LoadLibs()
	H.InstallLibATStub()
	local SUI = H.InstallSUIMock({})
	rawset(SUI, 'opt', { args = {} })
	rawset(SUI, 'Print', function(_, text)
		H.sui.printed = H.sui.printed or {}
		H.sui.printed[#H.sui.printed + 1] = text
	end)
	rawset(_G, 'SpartanUINameplatesDB', opts.saved)
	local ns = {}
	H.loadedEntries = {}
	for _, entry in ipairs(H.NameplateLoadEntries()) do
		if entry.kind == 'script' then
			H.LoadFile(entry.path, 'SpartanUI', ns)
			H.loadedEntries[#H.loadedEntries + 1] = entry.path
		elseif entry.kind == 'template' then
			M.RegisterTemplate(entry.name)
		end
	end
	H.ns = ns
	return SUI, ns, SUI:GetModule('Nameplates', true)
end

---The AceDB character key the client would use for the logged-in character.
---@return string
function H.CharacterKey()
	H.LoadLibs()
	if not H.charKey then
		H.charKey = LibStub('AceDB-3.0'):New('NameplatesKeyProbeDB').keys.char
		rawset(_G, 'NameplatesKeyProbeDB', nil)
	end
	return H.charKey
end

---Create the SUI mock (once) and return it.
function H.InstallSUIMock(opts)
	if rawget(_G, 'SUI') then
		return SUI
	end
	H.LoadLibs()
	local chunk = assert(loadfile(ROOT .. 'Tests/Nameplates/harness/suimock.lua'))
	return chunk(M, H, opts or {})
end

return H
