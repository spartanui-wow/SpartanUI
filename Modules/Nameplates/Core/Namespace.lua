local addonName, ns = ...

-- Nameplate core. Nothing in this folder outside Host/ may reference the addon that carries it:
-- the host hands everything host-specific to P:Initialize. Loading these files must stay inert:
-- no game events, no hooks, no CVar writes and no named frames until P:Enable() runs.

---@class Plates
---@field db table|nil AceDB object, set by Config:Open
---@field host Plates.HostConfig|nil
---@field hostLook Plates.HostLook|nil Look pushed by the host (tokens, art, font, accent)
---@field initialized boolean
---@field enabled boolean
---@field log Plates.Logger
---@field L table<string, string>
---@field services Plates.Services
local P = {}
ns.Plates = P

P.addonName = addonName
P.initialized = false
P.enabled = false

---Versions: `api` lets other addons feature-detect, `core` is informational only. `schema` is
---a copy of P.Styles.Schema.CURRENT (set by Schema.lua), the one number that stamps share strings
---and drives the style upgrade chain; raise Schema.CURRENT, never this.
P.VERSION = { core = '0.1.0', api = 1, schema = 1 }

---Refresh reasons carried by change messages (5.2). Parts and engine modules react only to the
---reasons they care about.
P.REASON = {
	LOOK = 'look', -- style content, tokens, fonts, textures: parts Layout again
	SIZE = 'size', -- plate size: Layout again, base plate size recomputed
	AURAS = 'auras', -- aura rows, filters, lists: containers reconfigured (only while not restricted)
	COLORS = 'colors', -- color lists, scheme, threat palette, role: color programs recompiled
	CVARS = 'cvars', -- game settings we own
	ASSIGNMENT = 'assignment', -- which style each kind of plate uses, modes, "When" list
}

---Every reason, used for profile resets, copies and engine (re)starts.
P.ALL_REASONS = { look = true, size = true, auras = true, colors = true, cvars = true, assignment = true }

---@class Plates.Logger
---@field debug fun(msg: string)
---@field info fun(msg: string)
---@field warning fun(msg: string)
---@field error fun(msg: string)

local noop = function() end
P.log = { debug = noop, info = noop, warning = noop, error = noop }

---@class Plates.HostLook
---@field style? string|table Style id (or an inline style) the host suggests for "Match my look"
---@field tokens? table<string, any> Token values: accent, font, bar, ink, shade, ...
---@field art? table<string, any> Art keys or texture paths the host supplies (nineSlice, arrows, ...)
---@field font? string Font file path or LSM key used for `$font`
---@field accent? number[] { r, g, b, a } used for `$accent`

---@class Plates.HostConfig
---@field name string Display name of the host, used in every string that names it
---@field savedVariable string Global name of the SavedVariables table (declared by the host's TOC)
---@field mediaPath string Path to Modules/Nameplates/Media with trailing backslashes
---@field widgetPrefix string Prefix for the core's AceGUI widget types (<prefix>AnchorGrid, ...)
---@field globalPrefix? string Prefix for any global name the core must create (font families, templates); defaults to widgetPrefix
---@field logger? Plates.Logger
---@field media? table LibSharedMedia-3.0; the core never loads its own copy
---@field AddOptions? fun(tbl: table) Insert the options table returned by P:BuildOptionsTable()
---@field OptionsPath? fun(page?: string): string[] Options path for a page, e.g. { 'Nameplates', 'colors' }
---@field OpenOptions? fun(page?: string, optionKey?: string)
---@field AddSetupSteps? fun(steps: table[]) Add the core's setup steps to the host's first-run window
---@field RegisterCommand? fun(name: string, fn: fun(args?: string), description?: string)
---@field RegisterPreview? fun(provider: table) Register the options preview provider
---@field ImportLegacy? fun(profileKey: string): table|nil Raw settings of the module this one replaces
---@field GetHostLook? fun(): Plates.HostLook|nil
---@field GetHostProfileName? fun(): string|nil
---@field profileDefaults? table Host-only profile defaults (scalars), e.g. { followHostProfile = true }
---@field globalDefaults? table Host-only global defaults (scalars)
---@field widgets? { cardGrid?: string } AceGUI type names the core uses but does not own
---@field conflicts? string[] Folder names of addons that also draw nameplates
---@field RefreshOptions? fun(rebuild?: boolean) Redraw the open options after a change made outside a control; rebuild = true also replaces the table with a new P:BuildOptionsTable()
---@field AddSearchWords? fun(words: table<string, string|string[]>) Teach the host's settings search the core's everyday words (P.Options.SEARCH_WORDS)

---@class Plates.Services
---@field media table|nil LibSharedMedia-3.0
---@field GetAccent fun(): number, number, number Accent color (host or LibAT)
---@field FontPath fun(): string Fallback font file for `$font`
---@field GetTime fun(): number
P.services = {
	media = nil,
	GetAccent = function()
		if LibAT and LibAT.UI and LibAT.UI.GetAccentColor then
			local r, g, b = LibAT.UI.GetAccentColor()
			if type(r) == 'number' and type(g) == 'number' and type(b) == 'number' then
				return r, g, b
			end
		end
		return 1, 0.82, 0
	end,
	FontPath = function()
		local style = LibAT and LibAT.UI and LibAT.UI.Style
		if style and type(style.FONT_PATH) == 'string' then
			return style.FONT_PATH
		end
		return STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF'
	end,
	GetTime = function()
		return GetTime and GetTime() or 0
	end,
}

---Shallow helpers shared by every core file.
P.util = {}

---@param t table
function P.util.Wipe(t)
	for k in pairs(t) do
		t[k] = nil
	end
	return t
end

---Deep copy. Never copies metatables; tables used as keys are kept as-is.
---@generic T
---@param v T
---@return T
function P.util.Copy(v)
	if type(v) ~= 'table' then
		return v
	end
	local out = {}
	for k, item in pairs(v) do
		out[k] = P.util.Copy(item)
	end
	return out
end

---True when t is a list: a table whose keys are exactly 1..n (n may be 0 only for {}).
---Lists are always replaced whole by overlays and merges, never merged by index.
---@param t any
---@return boolean
function P.util.IsList(t)
	if type(t) ~= 'table' then
		return false
	end
	local n = #t
	local count = 0
	for _ in pairs(t) do
		count = count + 1
		if count > n then
			return false
		end
	end
	return n > 0 or next(t) == nil
end

---Deep equality for plain data (numbers, strings, booleans, tables of those).
---@param a any
---@param b any
---@return boolean
function P.util.Equal(a, b)
	if a == b then
		return true
	end
	if type(a) ~= 'table' or type(b) ~= 'table' then
		return false
	end
	for k, v in pairs(a) do
		if not P.util.Equal(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

---Split 'a.b.c' (or a list) into a list of keys. Numeric parts become numbers.
---@param path string|string[]
---@return table keys
function P.util.SplitPath(path)
	if type(path) == 'table' then
		return path
	end
	local keys = {}
	for part in string.gmatch(path, '[^%.]+') do
		keys[#keys + 1] = tonumber(part) or part
	end
	return keys
end

----------------------------------------------------------------------------------------------------
-- Internal message bus. Listeners are called in registration order. Removing a listener while a
-- message is being delivered is safe (the list is copied on write).
----------------------------------------------------------------------------------------------------

local listeners = {}

---@param message string
---@param fn function Called as fn(...) with the arguments given to Fire
---@param owner? any Lets P:Off remove every listener of one owner
function P:On(message, fn, owner)
	local old = listeners[message]
	local list = {}
	if old then
		for i = 1, #old do
			list[i] = old[i]
		end
	end
	list[#list + 1] = { fn = fn, owner = owner }
	listeners[message] = list
end

---Remove listeners by function or by owner. nil removes nothing (listeners without an owner
---would otherwise all match).
---@param message string
---@param fnOrOwner any
function P:Off(message, fnOrOwner)
	local old = listeners[message]
	if not old or fnOrOwner == nil then
		return
	end
	local list = {}
	for i = 1, #old do
		local entry = old[i]
		if entry.fn ~= fnOrOwner and entry.owner ~= fnOrOwner then
			list[#list + 1] = entry
		end
	end
	listeners[message] = #list > 0 and list or nil
end

---@param message string
function P:Fire(message, ...)
	local list = listeners[message]
	if not list then
		return
	end
	for i = 1, #list do
		local ok, err = pcall(list[i].fn, ...)
		if not ok then
			P.log.error('Listener for ' .. message .. ' failed: ' .. tostring(err))
			if geterrorhandler then
				geterrorhandler()(err)
			end
		end
	end
end

---Number of listeners for a message (tests and the inert check use it).
---@param message string
---@return integer
function P:ListenerCount(message)
	local list = listeners[message]
	return list and #list or 0
end

----------------------------------------------------------------------------------------------------
-- Game events for core and engine modules (not for per-plate unit events: each plate has its own
-- frame). The frame is created on the first registration, so loading the core creates nothing.
----------------------------------------------------------------------------------------------------

local eventFrame
local eventHandlers = {}

---Register a game event. Returns false when the client does not know the event.
---@param event string
---@param owner string
---@param fn fun(event: string, ...)
---@return boolean
function P:RegisterEvent(event, owner, fn)
	if not eventFrame then
		eventFrame = CreateFrame('Frame')
		eventFrame:SetScript('OnEvent', function(_, e, ...)
			local handlers = eventHandlers[e]
			if not handlers then
				return
			end
			for _, handler in pairs(handlers) do
				handler(e, ...)
			end
		end)
	end
	if not eventHandlers[event] then
		if not pcall(eventFrame.RegisterEvent, eventFrame, event) then
			return false
		end
		eventHandlers[event] = {}
	end
	eventHandlers[event][owner] = fn
	return true
end

---@param event string
---@param owner string
function P:UnregisterEvent(event, owner)
	local handlers = eventHandlers[event]
	if not handlers then
		return
	end
	handlers[owner] = nil
	if next(handlers) == nil then
		eventHandlers[event] = nil
		eventFrame:UnregisterEvent(event)
	end
end

---Drop every event registered by one owner.
---@param owner string
function P:UnregisterAllEvents(owner)
	for event, handlers in pairs(eventHandlers) do
		if handlers[owner] then
			P:UnregisterEvent(event, owner)
		end
	end
end

---Number of game events currently registered (the inert check expects 0 before Enable).
---@return integer
function P:RegisteredEventCount()
	local count = 0
	for _ in pairs(eventHandlers) do
		count = count + 1
	end
	return count
end

----------------------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------------------

---Engine modules enabled by P:Enable, in this order (disabled in reverse). Each may define
---:Enable() and :Disable(). Missing modules or methods are skipped.
P.ENGINE_ORDER = { 'Scheduler', 'CVars', 'Pool', 'Suppress', 'Driver' }

---Open the database and run migrations. Never registers events, hooks or CVar writes.
---@param host Plates.HostConfig
function P:Initialize(host)
	if self.initialized then
		return
	end
	assert(type(host) == 'table', 'Plates: P:Initialize needs a host config table')
	assert(type(host.savedVariable) == 'string', 'Plates: host.savedVariable is required')
	assert(type(host.widgetPrefix) == 'string', 'Plates: host.widgetPrefix is required')
	self.host = host
	host.globalPrefix = host.globalPrefix or host.widgetPrefix
	host.widgets = host.widgets or {}
	if host.logger then
		self.log = host.logger
	end
	self.services.media = host.media or (LibStub and LibStub('LibSharedMedia-3.0', true)) or nil

	self.Config:Open()
	self.Migrate:RunGlobal()
	self.Migrate:RunProfile()
	self.Store:FollowHostProfile()

	self.initialized = true
	self.log.debug('Nameplates core initialized (schema ' .. self.VERSION.schema .. ')')
	self:Fire('INITIALIZED')
end

---Start the engine: capability probes, game settings, plates. Call at or after PLAYER_LOGIN.
function P:Enable()
	if self.enabled or not self.initialized then
		return
	end
	self.enabled = true
	self.Caps:RunProbes()
	self:RegisterMedia()
	for _, name in ipairs(self.ENGINE_ORDER) do
		local mod = self[name]
		if mod and mod.Enable then
			local ok, err = pcall(mod.Enable, mod)
			if not ok then
				self.log.error(name .. ' failed to start: ' .. tostring(err))
				if geterrorhandler then
					geterrorhandler()(err)
				end
			end
		end
	end
	self.log.info('Nameplates engine on')
	self:Fire('ENGINE_ENABLED')
end

---Stop the engine and give the game back every setting we changed. Settings the game locks in
---combat come back when combat ends (CVars keeps its own after-combat flush for that).
function P:Disable()
	if not self.enabled then
		return
	end
	for i = #self.ENGINE_ORDER, 1, -1 do
		local mod = self[self.ENGINE_ORDER[i]]
		if mod and mod.Disable then
			local ok, err = pcall(mod.Disable, mod)
			if not ok then
				self.log.error(self.ENGINE_ORDER[i] .. ' failed to stop: ' .. tostring(err))
			end
		end
	end
	self.CVars:RestoreAll()
	self.enabled = false
	self.log.info('Nameplates engine off')
	self:Fire('ENGINE_DISABLED')
end

---@return boolean
function P:IsEnabled()
	return self.enabled
end

---Register the core's own media with LibSharedMedia under neutral names. Safe to call again.
function P:RegisterMedia()
	local media = self.services.media
	if not media or not self.host then
		return
	end
	media:Register('statusbar', 'Nameplates Flat', self.host.mediaPath .. 'Flat.tga')
end

----------------------------------------------------------------------------------------------------
-- Public API (P.API). The host exposes it as module.API; other addons must nil-check every step.
----------------------------------------------------------------------------------------------------

---@class Plates.API
local API = { VERSION = P.VERSION.api }
P.API = API

---Our plate object for a Blizzard base nameplate, or nil.
---@param base Frame
---@return table|nil
function API:GetPlate(base)
	return P.Driver and P.Driver.GetPlate and P.Driver:GetPlate(base) or nil
end

---The health StatusBar drawn on a base nameplate, or nil (used by addons that overlay health).
---@param base Frame
---@return StatusBar|nil
function API:GetHealthBar(base)
	local plate = API:GetPlate(base)
	return plate and plate.GetHealthBar and plate:GetHealthBar() or nil
end

---Register a style (built-ins and host looks). Returns false and a reason when it fails checks.
---@param style table
---@return boolean ok
---@return string|nil reason
function API:RegisterStyle(style)
	return P.Styles.Registry:RegisterHostStyle(style)
end

---Push the host look (theme tokens, art, font, accent). Invalidates resolved styles.
---@param look Plates.HostLook|nil
function API:SetHostLook(look)
	P.hostLook = look
	P:Fire('HOST_LOOK_CHANGED', look)
	P:Fire('STORE_CHANGED', { look = true }, nil, 'host')
end

---Import a shared style string as a new saved style.
---@param text string
---@param name? string
---@return string|nil styleId
---@return string|nil reason
function API:ImportStyle(text, name)
	return P.Share:ImportStyle(text, name)
end

local publicEvents = { PLATE_ADDED = true, PLATE_REMOVED = true, STYLE_APPLIED = true, ENGINE_ENABLED = true, ENGINE_DISABLED = true }

---Listen to a public event: PLATE_ADDED(plate, unit), PLATE_REMOVED(plate, unit),
---STYLE_APPLIED(plate, resolvedKey), ENGINE_ENABLED, ENGINE_DISABLED.
---@param event string
---@param fn function
---@param owner? any
---@return boolean ok
function API:RegisterCallback(event, fn, owner)
	if not publicEvents[event] or type(fn) ~= 'function' then
		return false
	end
	P:On(event, fn, owner)
	return true
end

---@param event string
---@param fnOrOwner any
function API:UnregisterCallback(event, fnOrOwner)
	P:Off(event, fnOrOwner)
end
