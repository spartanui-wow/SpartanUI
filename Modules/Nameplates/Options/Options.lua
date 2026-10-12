local _, ns = ...
local P = ns.Plates
local L = P.L

-- Settings (3.2, 3.3, 6.9). AceConfig tables rendered by LibAT; the host inserts the table from
-- P:BuildOptionsTable() as a top-level entry. Owner: Phase 2 (plain pages) and Phase 4a (six
-- full pages with the preview).
--
-- Rules for every page builder:
--   * get and set resolve their Store path on every call (Options.Bind) and never keep sub-tables.
--   * At most 8 main controls per page; everything else is `advanced = true` ("More settings").
--     Every setting has exactly one home. The main action on a page may be `primary = true`.
--   * Settings that touch auras, style switches, profile switches and "Who and where" assignments
--     are disabled while P.Secret.IsRestricted(), with Options.LOCKED_REASON as the description.
--   * Options paths come from host.OptionsPath (Options.Path), never written out in the core.
--   * Widget types: the host's card grid is host.widgets.cardGrid; core widgets are
--     P.Widgets:TypeName('AnchorGrid'|'RuleList'|'SpellList').
--   * Text is for a 6th grade reader: short sentences, what happens to the player's plates.
--   * Changes made outside a control (preview drag and nudge, undo, profile switches, a lifted
--     restriction, a new saved style) reach the open window through host.RefreshOptions, called
--     once per frame by the listeners at the end of this file. Never notify an options app here:
--     the app id belongs to the host.

---@class Plates.Options
local Options = { pages = {}, order = {} }
P.Options = Options

Options.LOCKED_REASON = L['The game does not allow aura changes right now. They unlock after combat.']

Options.PAGES = { 'style', 'customize', 'colors', 'auras', 'whoAndWhere', 'sharing' }

---Everyday words the settings search should also understand, mapped to the words our settings
---use. Handed to host.AddSearchWords once, so they only apply to the host's own settings.
Options.SEARCH_WORDS = {
	plate = 'nameplate',
	plates = 'nameplate',
	np = 'nameplate',
	aggro = 'threat',
	kick = 'interrupt',
	kicks = 'interrupt',
	execute = 'low health',
	purge = { 'dispel', 'can remove' },
	dispel = { 'purge', 'can remove' },
	stack = 'overlap',
	stacking = 'overlap',
	overlap = 'stack',
	overlapping = 'stack',
	hitbox = 'click',
	clickable = 'click',
	clickthrough = 'click through',
	marker = 'target icon',
	markers = { 'marker', 'target icon' },
	skull = { 'marker', 'target icon' },
	dot = 'debuff',
	dots = 'debuff',
}

---Register a page builder. builder() returns an AceConfig group.
---@param id string
---@param order number
---@param builder fun(): table
function Options:AddPage(id, order, builder)
	if not self.pages[id] then
		self.order[#self.order + 1] = id
	end
	self.pages[id] = { order = order, builder = builder }
end

---Options path for a page (host-defined).
---@param page? string
---@return string[]
function Options.Path(page)
	local host = P.host
	if host and host.OptionsPath then
		return host.OptionsPath(page)
	end
	return page and { 'Nameplates', page } or { 'Nameplates' }
end

---AceConfig get and set bound to a Store path, read fresh on every call.
---@param path string|table
---@param scope? 'profile'|'global'|'char'
---@param reasons? table
---@return fun(): any get
---@return fun(info: table, value: any) set
function Options.Bind(path, scope, reasons)
	local function Get()
		return P.Store:Get(path, scope)
	end
	local function Set(_, value)
		P.Store:Set(path, value, scope, reasons)
	end
	return Get, Set
end

---AceConfig `disabled` for settings that lock while the game restricts changes.
---@return boolean
function Options.Locked()
	return P.Secret.IsRestricted()
end

---The options table for the host to insert. Registers the core widget types and media first.
---@return table
function P:BuildOptionsTable()
	P.Widgets:Register()
	P:RegisterMedia()
	Options.built = true
	local host = P.host
	if host and host.AddSearchWords and not Options.searchWordsAdded then
		Options.searchWordsAdded = true
		host.AddSearchWords(Options.SEARCH_WORDS)
	end
	local tbl = {
		type = 'group',
		name = L['Nameplates'],
		childGroups = 'tree',
		args = {},
	}
	for _, id in ipairs(Options.order) do
		local page = Options.pages[id]
		local ok, group = pcall(page.builder)
		if ok and type(group) == 'table' then
			group.order = page.order
			tbl.args[id] = group
		elseif not ok then
			P.log.error('Nameplate options page ' .. id .. ' failed: ' .. tostring(group))
		end
	end
	return tbl
end

---Placeholder page for pages that are not built yet (testers only).
---@param name string
---@return table
function Options.Placeholder(name)
	return {
		type = 'group',
		name = name,
		args = {
			soon = { type = 'description', name = L['This page is coming soon.'], order = 1, fontSize = 'medium' },
		},
	}
end

---Ask the host to redraw the options once on the next frame. rebuild also asks for a new table
---(pages whose groups depend on the current style, such as Customize).
---@param rebuild? boolean
function Options:RequestRefresh(rebuild)
	local host = P.host
	if not (self.built and host and host.RefreshOptions) then
		return
	end
	self.rebuildWanted = self.rebuildWanted or rebuild or false
	P.Scheduler:NextFrame('Options.refresh', function()
		local wanted = Options.rebuildWanted
		Options.rebuildWanted = false
		host.RefreshOptions(wanted)
	end)
end

P:On('STORE_CHANGED', function(reasons)
	Options:RequestRefresh(reasons and reasons.look and true or false)
end, Options)
P:On('PROFILE_CHANGED', function()
	Options:RequestRefresh(true)
end, Options)
P:On('STYLES_CHANGED', function()
	Options:RequestRefresh(true)
end, Options)
P:On('RESTRICTION_CHANGED', function()
	Options:RequestRefresh(false)
end, Options)
