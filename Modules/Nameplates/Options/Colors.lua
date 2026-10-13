local _, ns = ...
local P = ns.Plates
local L = P.L
local Options = P.Options

-- Colors page (3.2 #3).
--
-- Main controls: the scheme picker, the color-blind switch, the threat row (a button that opens
-- role, when, show-on, six colors and threat numbers) and the mob type swatches. More settings: the
-- full ordered list per colored piece (Health bar, Border, Name, Cast bar), one list at a time,
-- built with the RuleList widget, and where a piece takes its colors from.
--
-- Where things are stored (Core/Colors.lua reads the same keys):
--   scheme                       'auto' | 'threat' | 'mobType' | 'class' | 'custom'
--   colorBlind                   the color-blind palette
--   role                         'auto' | 'tank' | 'damage'
--   threat.when / .show / .colors   when threat shows, on which parts, the player's own colors
--   colors[piece].order          the list, used only while the scheme is 'custom'
--   colors[piece].off[id]        a row switched off
--   colors[piece].when[id]       a row's "When" clause
--   colors[piece].color[id]      a row's color (boolean rows), or [id][state] for rows with several
--   tweaks[style].changes.parts[part].colors / .borderColors   which list a part uses
--   tweaks[style].add.threatNumber   the threat number text, when the player turns it on
-- Every setting has one home. The threat rows of a list show their colors but are changed in the
-- threat row; the mob type colors are changed in the swatches (written to every list that can hold
-- a mob type row); class colors are the game's.
--
-- Reordering, adding or removing a row pins every list to what the player sees and switches the
-- scheme to Custom, so no list changes order behind the player's back.
--
-- The preview: while the list is on screen the page tells P.Preview which piece it shows
-- (P.Preview:SetColorList), so the panel draws one sample plate per row; it tells it nil when the
-- list is not drawn. The page is drawn again after every change, so this is decided once per
-- frame: scheme.values runs once for each drawing of the page, and the list asks for its rows
-- only when More settings is open.

---@class Plates.ColorsPage
local ColorsPage = {}
Options.ColorsPage = ColorsPage

local Colors = P.Colors
local Roles = P.Roles
local PIECES = Colors.PIECES

local THREAT_ROWS = { threat = true, offTank = true, petTank = true }
local MOB_STATES = { 'boss', 'miniboss', 'caster', 'elite', 'normal', 'minor' }
local REACTION_STATES = { 'hostile', 'neutral', 'friendly' }
local THREAT_SWATCH_STATES = { 'safe', 'losing', 'lost', 'solo' }
local CLASS_TOKENS = { 'WARRIOR', 'PALADIN', 'HUNTER', 'ROGUE', 'PRIEST', 'DEATHKNIGHT', 'SHAMAN', 'MAGE', 'WARLOCK', 'MONK', 'DRUID', 'DEMONHUNTER', 'EVOKER' }

local PIECE_LABELS = {
	health = L['Health bar'],
	border = L['Border'],
	name = L['Name'],
	cast = L['Cast bar'],
}

local STATE_LABELS = {
	boss = L['Boss'],
	miniboss = L['Mini-boss'],
	caster = L['Caster'],
	elite = L['Elite'],
	normal = L['Normal'],
	minor = L['Minor'],
	hostile = L['Enemy'],
	neutral = L['Neutral'],
	friendly = L['Friendly'],
	safe = L['Safe'],
	losing = L['Losing it'],
	lost = L['Lost it'],
	offTank = L['Another tank has it'],
	pet = L['Your pet has it'],
	solo = L['Solo'],
}

---The order "Add a color" lists kinds in (3.2). Kinds not named here follow.
local ADD_ORDER = { 'tapped', 'quest', 'threat', 'mobType', 'class', 'reaction', 'target', 'focus', 'lowHealth', 'interruptReady', 'notInterruptible', 'importantCast', 'aimedAtMe', 'fixed' }
local ADD_LABELS = { class = L['Player class'] }

---Session-only page state (the page is rebuilt often, so nothing here lives in the builder).
local state = { piece = 'health', threatOpen = false, flash = nil, rowsAsked = false }
ColorsPage.state = state

----------------------------------------------------------------------------------------------------
-- Small readers (always from the store, never kept)
----------------------------------------------------------------------------------------------------

local function Settings()
	return {
		scheme = P.Store:Get('scheme'),
		colors = P.Store:Get('colors'),
		threat = P.Store:Get('threat'),
		colorBlind = P.Store:Get('colorBlind'),
	}
end

---A table inside a table, or an empty one (a pasted string can put anything in the profile).
local function Sub(parent, key)
	local value = type(parent) == 'table' and parent[key] or nil
	return type(value) == 'table' and value or {}
end

---One piece's stored changes, with every part of it a table.
---@param settings table
---@param piece string
---@return table { order?, off, when, color }
local function CustomFor(settings, piece)
	local stored = Sub(settings.colors, piece)
	return {
		order = type(stored.order) == 'table' and stored.order or nil,
		off = Sub(stored, 'off'),
		when = Sub(stored, 'when'),
		color = Sub(stored, 'color'),
	}
end

local function Role()
	local ctx = P.Context
	return Roles.Resolve(P.Store:Get('role'), ctx and ctx.role)
end

local function EffectiveScheme()
	local scheme = P.Store:Get('scheme') or 'auto'
	if scheme == 'auto' then
		scheme = Roles.Scheme(Role())
	end
	return scheme
end

local function AsColor(c)
	if type(c) ~= 'table' then
		return { 1, 1, 1, 1 }
	end
	return { tonumber(c[1] or c.r) or 1, tonumber(c[2] or c.g) or 1, tonumber(c[3] or c.b) or 1, tonumber(c[4] or c.a) or 1 }
end

local function IdsOf(entries)
	local ids = {}
	for i, entry in ipairs(entries) do
		ids[i] = entry.id
	end
	return ids
end

local function IndexOf(list, id)
	for i, value in ipairs(list) do
		if value == id then
			return i
		end
	end
	return nil
end

local function KindFits(kind, piece)
	for _, p in ipairs(kind.pieces or {}) do
		if p == piece then
			return true
		end
	end
	return false
end

---Ordered { id, when } entries for a piece, off rows included (Colors:Compile leaves those out).
---@param piece string
---@return table[] entries
local function Entries(piece)
	local settings = Settings()
	local role = Role()
	local scheme = EffectiveScheme()
	local custom = CustomFor(settings, piece)
	local entries
	if scheme == 'custom' and type(custom.order) == 'table' then
		entries = {}
		for _, id in ipairs(custom.order) do
			entries[#entries + 1] = { id = id }
		end
		for _, entry in ipairs(Colors:SchemeRows(Roles.Scheme(role), piece, settings, role)) do
			for _, mine in ipairs(entries) do
				if mine.id == entry.id and mine.when == nil then
					mine.when = entry.when
				end
			end
		end
	else
		if scheme == 'custom' then
			scheme = Roles.Scheme(role)
		end
		entries = Colors:SchemeRows(scheme, piece, settings, role)
	end
	return entries
end

---The kinds any scheme puts on a piece, so a row the player added can be told apart.
---@param piece string
---@return table<string, boolean>
local function NaturalIds(piece)
	local set = {}
	for scheme in pairs(Colors.SCHEMES) do
		for _, entry in ipairs(Colors.SCHEMES[scheme][piece] or {}) do
			if entry == '@threat' then
				for _, id in ipairs(Colors.THREAT_GROUP) do
					set[id] = true
				end
			elseif type(entry) == 'table' then
				set[entry.id] = true
			else
				set[entry] = true
			end
		end
	end
	return set
end

----------------------------------------------------------------------------------------------------
-- Rows for the RuleList
----------------------------------------------------------------------------------------------------

---Short client note for a row that is limited here, or nil.
---@param kind Plates.ColorKind
---@return string|nil
local function BadgeFor(kind)
	local client = P.Caps:Client()
	if kind.limits and kind.limits[client] then
		return kind.limits[client]
	end
	if not P.Caps:Get('secrets') then
		return nil
	end
	local id = kind.id
	if id == 'quest' then
		return L['Only in the open world on this version of WoW']
	elseif id == 'threat' then
		return L['The game hides threat on some enemies, such as bosses']
	elseif id == 'lowHealth' and not P.Caps:Get('healthCurves') then
		return L['Needs the game to let addons see health']
	elseif id == 'class' and not P.Caps:Get('classColor') then
		return L['The game hides some player classes here. Those plates use the next color']
	end
	return nil
end

local function ClassSwatches()
	local out = {}
	for _, token in ipairs(CLASS_TOKENS) do
		local ok, c = pcall(function()
			return (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(token)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[token])
		end)
		if ok and type(c) == 'table' then
			local label = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]
			out[#out + 1] = { key = token, label = label, color = { c.r or 1, c.g or 1, c.b or 1, 1 } }
		end
	end
	return out
end

local function Swatches(stateList, colorFor)
	local out = {}
	for _, key in ipairs(stateList) do
		out[#out + 1] = { key = key, label = STATE_LABELS[key], color = colorFor(key) }
	end
	return out
end

---@param entry table
---@param custom table colors[piece] (may be empty)
---@param settings table
---@param natural table<string, boolean>
---@return Plates.RuleRow|nil
local function BuildRow(entry, custom, settings, natural)
	local id = entry.id
	local kind = Colors:GetKind(id)
	if not kind or kind.available == false then
		return nil
	end
	local mine = custom.color[id]
	local row = {
		id = id,
		sentence = Colors:Sentence({ id = id }),
		on = not custom.off[id],
		removable = not natural[id],
		badge = BadgeFor(kind),
	}
	if THREAT_ROWS[id] then
		row.whenText = P.Conditions.WHEN_LABELS[custom.when[id] or entry.when or P.Threat.When(Sub(settings, 'threat'))] or ''
		row.tooltip = L['Change these colors in the threat colors, above.']
	else
		row.when = custom.when[id] or entry.when or kind.when or 'everywhere'
		if id == 'mobType' then
			row.tooltip = L['Change these colors in the mob type colors, above.']
		elseif id == 'class' then
			row.tooltip = L['These are the class colors from the game.']
		end
	end

	if kind.type == 'mapped' then
		local base = kind.default or {}
		if THREAT_ROWS[id] then
			base = Roles.Palette(settings.colorBlind, Sub(settings.threat, 'colors'))
		end
		local function StateColor(key)
			local over = type(mine) == 'table' and mine[key]
			local color = over or base[key]
			return color and AsColor(color) or { 0.5, 0.5, 0.5, 1 }
		end
		if id == 'threat' then
			row.colors = Swatches(THREAT_SWATCH_STATES, StateColor)
		elseif id == 'offTank' then
			row.color = StateColor('offTank')
		elseif id == 'petTank' then
			row.color = StateColor('pet')
		elseif id == 'mobType' then
			row.colors = Swatches(MOB_STATES, StateColor)
		elseif id == 'reaction' then
			row.colors = Swatches(REACTION_STATES, StateColor)
		elseif id == 'class' then
			local classes = ClassSwatches()
			if #classes > 0 then
				row.colors = classes
			end
		end
	else
		row.color = AsColor((type(mine) == 'table' and mine[1] and mine) or kind.default or { 1, 1, 1, 1 })
	end
	return row
end

---The rows of one piece's list, in order, off rows included.
---@param piece string
---@return Plates.RuleRow[]
function ColorsPage.Rows(piece)
	local settings = Settings()
	local custom = CustomFor(settings, piece)
	local natural = NaturalIds(piece)
	local rows = {}
	for _, entry in ipairs(Entries(piece)) do
		local row = BuildRow(entry, custom, settings, natural)
		if row then
			rows[#rows + 1] = row
		end
	end
	return rows
end

----------------------------------------------------------------------------------------------------
-- Which list the page shows, and the preview focus
----------------------------------------------------------------------------------------------------

---@param piece string
function ColorsPage.SetPiece(piece)
	if not PIECE_LABELS[piece] then
		return
	end
	state.piece = piece
	state.flash = nil
end

---Once per drawing of the page: if the list asked for its rows meanwhile, it is on screen.
local function SettleListState()
	local open = state.rowsAsked
	state.rowsAsked = false
	local preview = P.Preview
	if preview and preview.SetColorList then
		preview:SetColorList(open and state.piece or nil)
	end
end

local function PageDrawn()
	P.Scheduler:NextFrame('Options.colorsList', SettleListState)
end

---Take the player to a piece's list (a link from a part's settings).
---@param piece string
function ColorsPage.ShowList(piece)
	ColorsPage.SetPiece(piece)
	local host = P.host
	if host and host.OpenOptions then
		host.OpenOptions('colors', 'list')
	end
end

----------------------------------------------------------------------------------------------------
-- Writing the lists
----------------------------------------------------------------------------------------------------

---Pin every list to what the player sees now (the scheme's rows), put `order` on `piece` when
---given, and switch to Custom. Lists the player already pinned are left alone.
---@param piece? string
---@param order? string[]
local function MakeCustom(piece, order)
	local Store = P.Store
	local wasCustom = EffectiveScheme() == 'custom'
	local fresh = {}
	if not wasCustom then
		for _, p in ipairs(PIECES) do
			fresh[p] = IdsOf(Entries(p))
		end
	end
	Store:Batch(function()
		if not wasCustom then
			for _, p in ipairs(PIECES) do
				Store:Set({ 'colors', p, 'order' }, fresh[p])
			end
		end
		if piece and order then
			Store:Set({ 'colors', piece, 'order' }, order)
		end
		Store:Set('scheme', 'custom')
	end)
end

---@param value string
function ColorsPage.SetScheme(value)
	if value == 'custom' and EffectiveScheme() ~= 'custom' then
		MakeCustom()
	else
		P.Store:Set('scheme', value)
	end
end

---The threat rows ride together: Threat brings Another tank and Your pet along, above it.
---@param order string[]
---@return string[]
local function WithThreatGroup(order)
	local out = {}
	for _, id in ipairs(order) do
		out[#out + 1] = id
	end
	local at = IndexOf(out, 'threat')
	if at then
		for _, id in ipairs({ 'petTank', 'offTank' }) do
			if not IndexOf(out, id) then
				table.insert(out, at, id)
			end
		end
	end
	return out
end

local function DefaultWhen(piece, id)
	for _, entry in ipairs(Entries(piece)) do
		if entry.id == id then
			local kind = Colors:GetKind(id)
			return entry.when or (kind and kind.when) or 'everywhere'
		end
	end
	local kind = Colors:GetKind(id)
	return kind and kind.when or 'everywhere'
end

---Apply one change from the RuleList to the store.
---@param piece string
---@param change Plates.RuleChange
function ColorsPage.ApplyChange(piece, change)
	local Store = P.Store
	local id, action = change.id, change.action
	if action == 'toggle' then
		Store:Set({ 'colors', piece, 'off', id }, (not change.on) or nil)
	elseif action == 'when' then
		local when = change.when
		if when == DefaultWhen(piece, id) then
			when = nil
		end
		Store:Set({ 'colors', piece, 'when', id }, when)
	elseif action == 'color' then
		if change.key ~= nil then
			Store:Set({ 'colors', piece, 'color', id, change.key }, change.color)
		else
			Store:Set({ 'colors', piece, 'color', id }, change.color)
		end
	elseif action == 'reorder' then
		MakeCustom(piece, change.order)
	elseif action == 'add' then
		-- The page is drawn again after a change, so the new list is told which row to flash
		state.flash = id
		MakeCustom(piece, id == 'threat' and WithThreatGroup(change.order) or change.order)
	elseif action == 'remove' then
		Store:Batch(function()
			MakeCustom(piece, change.order)
			Store:Set({ 'colors', piece, 'off', id }, nil)
			Store:Set({ 'colors', piece, 'when', id }, nil)
			Store:Set({ 'colors', piece, 'color', id }, nil)
		end)
	end
end

---Where a new row goes: where its kind usually ranks in the role's scheme, never silently on top.
---@param piece string
---@param id string
---@param order string[]
---@return integer
function ColorsPage.InsertIndex(piece, id, order)
	return Colors:SuggestInsertIndex(piece, id, order, Settings(), Role())
end

---Kinds "Add a color" offers for a piece (the other threat rows ride with Threat).
---@param piece string
---@return table[] choices
function ColorsPage.AddChoices(piece)
	local present = {}
	for _, entry in ipairs(Entries(piece)) do
		present[entry.id] = true
	end
	local seen, out = {}, {}
	local function Offer(id)
		local kind = Colors:GetKind(id)
		if seen[id] or not kind or kind.available == false or not KindFits(kind, piece) then
			return
		end
		if THREAT_ROWS[id] and id ~= 'threat' then
			return
		end
		seen[id] = true
		out[#out + 1] = {
			id = id,
			label = ADD_LABELS[id] or kind.label,
			when = kind.when,
			badge = BadgeFor(kind),
			color = kind.type ~= 'mapped' and type(kind.default) == 'table' and AsColor(kind.default) or nil,
			disabled = present[id] == true,
		}
	end
	for _, id in ipairs(ADD_ORDER) do
		Offer(id)
	end
	for _, id in ipairs(Colors.kindOrder) do
		Offer(id)
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- Threat settings
----------------------------------------------------------------------------------------------------

local function ThreatPalette()
	local settings = Settings()
	return Roles.Palette(settings.colorBlind, Sub(settings.threat, 'colors'))
end

-- Saved lists can carry copies that would override the shared threat controls.
local function ClearThreatCopies(field, key)
	for _, piece in ipairs(PIECES) do
		for _, id in ipairs(Colors.THREAT_GROUP) do
			local path = { 'colors', piece, field, id }
			if key then
				path[#path + 1] = key
			end
			P.Store:Set(path, nil)
		end
	end
end

function ColorsPage.SetThreatColor(key, color)
	P.Store:Batch(function()
		P.Store:Set({ 'threat', 'colors', key }, color)
		ClearThreatCopies('color', key)
	end)
end

function ColorsPage.ResetThreatColors()
	P.Store:Batch(function()
		P.Store:Set({ 'threat', 'colors' }, nil)
		ClearThreatCopies('color')
	end)
end

function ColorsPage.HasThreatColors()
	if P.Store:Get({ 'threat', 'colors' }) ~= nil then
		return true
	end
	for _, piece in ipairs(PIECES) do
		for _, id in ipairs(Colors.THREAT_GROUP) do
			if P.Store:Get({ 'colors', piece, 'color', id }) ~= nil then
				return true
			end
		end
	end
	return false
end

local CHANNEL_PIECE = { bar = 'health', border = 'border', name = 'name' }

---While the lists are Custom, "Show threat on" has to add and remove the threat rows itself.
---@param show table|nil New channel map (nil follows the role)
local function SyncThreatRows(show)
	if EffectiveScheme() ~= 'custom' then
		return
	end
	local Store = P.Store
	local on = Roles.ThreatOn(Role(), show)
	for channel, piece in pairs(CHANNEL_PIECE) do
		local order = Store:Get({ 'colors', piece, 'order' })
		if type(order) == 'table' then
			local has = IndexOf(order, 'threat') ~= nil
			if on[channel] and not has then
				local out = {}
				for _, id in ipairs(order) do
					out[#out + 1] = id
				end
				table.insert(out, ColorsPage.InsertIndex(piece, 'threat', order), 'threat')
				Store:Set({ 'colors', piece, 'order' }, WithThreatGroup(out))
			elseif not on[channel] and has then
				local out = {}
				for _, id in ipairs(order) do
					if not THREAT_ROWS[id] then
						out[#out + 1] = id
					end
				end
				Store:Set({ 'colors', piece, 'order' }, out)
			end
		end
	end
end

---@param channel string 'bar' | 'border' | 'name' | 'glow' | 'size'
---@return boolean
function ColorsPage.GetThreatShow(channel)
	return Roles.ThreatOn(Role(), P.Store:Get({ 'threat', 'show' }))[channel] == true
end

---@param channel string
---@param value boolean
function ColorsPage.SetThreatShow(channel, value)
	local Store = P.Store
	local role = Role()
	local map = {}
	for key, on in pairs(Roles.ThreatOn(role, Store:Get({ 'threat', 'show' }))) do
		if on then
			map[key] = true
		end
	end
	map[channel] = value and true or nil
	if next(map) == nil then
		-- Nothing left to show on means the role's own choice
		map = nil
	else
		local default = Roles.DEFAULTS[role] and Roles.DEFAULTS[role].threatOn or {}
		local same = true
		for key in pairs(map) do
			if not default[key] then
				same = false
			end
		end
		for key in pairs(default) do
			if not map[key] then
				same = false
			end
		end
		if same then
			map = nil
		end
	end
	Store:Batch(function()
		Store:Set({ 'threat', 'show' }, map)
		SyncThreatRows(map)
	end)
end

---@return string
function ColorsPage.GetThreatWhen()
	return P.Store:Get({ 'threat', 'when' }) or 'instances'
end

---@param value string
function ColorsPage.SetThreatWhen(value)
	P.Store:Batch(function()
		P.Store:Set({ 'threat', 'when' }, value ~= 'instances' and value or nil)
		ClearThreatCopies('when')
	end)
end

---@param value string 'auto' | 'tank' | 'damage'
function ColorsPage.SetRole(value)
	P.Store:Set('role', value)
end

----------------------------------------------------------------------------------------------------
-- Mob type colors (written to every list that can hold a mob type row)
----------------------------------------------------------------------------------------------------

local function MobTypePieces()
	local kind = Colors:GetKind('mobType')
	local out = {}
	for _, piece in ipairs(PIECES) do
		if kind and KindFits(kind, piece) then
			out[#out + 1] = piece
		end
	end
	return out
end

local function StoredMobTypes(piece)
	local mine = Sub(CustomFor(Settings(), piece).color, 'mobType')
	return next(mine) ~= nil and mine or nil
end

---@param key string boss, miniboss, caster, elite, normal or minor
---@return number[] color
function ColorsPage.GetMobTypeColor(key)
	for _, piece in ipairs(MobTypePieces()) do
		local mine = StoredMobTypes(piece)
		if mine and mine[key] then
			return AsColor(mine[key])
		end
	end
	local kind = Colors:GetKind('mobType')
	return AsColor(kind and kind.default and kind.default[key] or { 0.5, 0.5, 0.5, 1 })
end

---@param key string
---@param color number[]|nil nil puts the standard color back
function ColorsPage.SetMobTypeColor(key, color)
	local Store = P.Store
	Store:Batch(function()
		for _, piece in ipairs(MobTypePieces()) do
			Store:Set({ 'colors', piece, 'color', 'mobType', key }, color)
		end
	end)
end

---@return boolean
function ColorsPage.HasMobTypeColors()
	for _, piece in ipairs(MobTypePieces()) do
		local mine = StoredMobTypes(piece)
		if mine and next(mine) ~= nil then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------------------------------------
-- Style overlay edits (threat numbers, where a part takes its colors from)
----------------------------------------------------------------------------------------------------

local function PruneEmpty(t)
	for key, value in pairs(t) do
		if type(value) == 'table' then
			PruneEmpty(value)
			if next(value) == nil then
				t[key] = nil
			end
		end
	end
end

---The style the player is on, resolved for an enemy NPC at the chosen size.
---@return Plates.ResolvedStyle
local function ResolvedStyle()
	return P.Styles.Merge:Resolve(P.Store:Get('style'), 'enemyNPC', P.Store:Get('size'))
end

---Change the player's changes to the current style (profile.tweaks[style]) with fn(overlay,
---styleId). Empty tables are dropped, so "Undo my changes" shows only when something is left.
---@param fn fun(overlay: table, styleId: string)
function ColorsPage.EditOverlay(fn)
	if Options.Locked() then
		Options:RequestRefresh(false)
		return false
	end
	local Registry = P.Styles.Registry
	local id = Registry:ResolveId(P.Store:Get('style'))
	local overlay = P.util.Copy(P.Store:Get({ 'tweaks', id }))
	if type(overlay) ~= 'table' then
		local base = Registry:Get(id)
		overlay = { schema = P.Styles.Schema.CURRENT, baseVersion = base and base.version or 1 }
	end
	fn(overlay, id)
	PruneEmpty(overlay)
	local meaningful = false
	for key in pairs(overlay) do
		if key ~= 'schema' and key ~= 'baseVersion' then
			meaningful = true
		end
	end
	P.Store:Set({ 'tweaks', id }, meaningful and overlay or nil)
end

local NUMBER_ID = 'threatNumber'
local NUMBER_SOURCE = { percent = 'threatPercent', lead = 'threatLead' }
local SOURCE_MODE = { threatPercent = 'percent', threatLead = 'lead' }

local function NumberPart(source)
	return {
		kind = 'text',
		order = 37,
		source = source,
		anchor = { 'BOTTOMRIGHT', 'health', 'TOPRIGHT', -18, 2 },
		justify = 'RIGHT',
		font = { size = 9 },
	}
end

---Which threat number the plate shows now: 'none', 'percent' or 'lead'.
---@return string mode
---@return string|nil partId
function ColorsPage.GetThreatNumbers()
	local resolved = ResolvedStyle()
	for _, id in ipairs(resolved.order or {}) do
		local spec = resolved.parts[id]
		if spec and spec.kind == 'text' and SOURCE_MODE[spec.source] then
			return SOURCE_MODE[spec.source], id
		end
	end
	return 'none', nil
end

---@param mode string 'none' | 'percent' | 'lead'
function ColorsPage.SetThreatNumbers(mode)
	ColorsPage.EditOverlay(function(overlay, styleId)
		local base = P.Styles.Registry:Get(styleId)
		local baseIds = {}
		for id, spec in pairs(base and base.parts or {}) do
			if spec.kind == 'text' and SOURCE_MODE[spec.source] then
				baseIds[#baseIds + 1] = id
			end
		end
		table.sort(baseIds)
		overlay.add = overlay.add or {}
		overlay.remove = overlay.remove or {}
		overlay.changes = overlay.changes or {}
		overlay.changes.parts = overlay.changes.parts or {}
		local source = NUMBER_SOURCE[mode]
		if not source then
			for id, spec in pairs(overlay.add) do
				if spec.kind == 'text' and SOURCE_MODE[spec.source] then
					overlay.add[id] = nil
				end
			end
			for _, id in ipairs(baseIds) do
				overlay.remove[id] = true
				local change = overlay.changes.parts[id]
				if change then
					change.source = nil
				end
			end
			return
		end
		local found = false
		for _, id in ipairs(baseIds) do
			found = true
			overlay.remove[id] = nil
			local change = overlay.changes.parts[id] or {}
			overlay.changes.parts[id] = change
			change.source = base.parts[id].source ~= source and source or nil
			if base.parts[id].hidden then
				change.hidden = false
			else
				change.hidden = nil
			end
		end
		for _, spec in pairs(overlay.add) do
			if spec.kind == 'text' and SOURCE_MODE[spec.source] then
				found = true
				spec.source = source
				spec.hidden = nil
			end
		end
		if not found then
			local id, index = NUMBER_ID, 1
			while (base and base.parts and base.parts[id]) or overlay.add[id] or overlay.changes.parts[id] do
				index = index + 1
				id = NUMBER_ID .. index
			end
			overlay.add[id] = NumberPart(source)
			overlay.remove[id] = nil
		end
	end)
end

-- Which list a part uses. Each piece has "slots": the parts that draw it and the field that names
-- the list. Changing the list a piece takes its colors from rewrites that field on every slot.
local function SlotsFor(piece)
	local resolved = ResolvedStyle()
	local out = {}
	for _, id in ipairs(resolved.order or {}) do
		local spec = resolved.parts[id]
		if spec then
			local healthBar = spec.kind == 'bar' and (spec.source == nil or spec.source == 'health')
			if piece == 'health' and healthBar and spec.colors ~= nil then
				out[#out + 1] = { id = id, field = 'colors', kind = 'bar' }
			elseif piece == 'border' and healthBar and spec.borderColors ~= nil then
				out[#out + 1] = { id = id, field = 'borderColors', kind = 'bar' }
			elseif piece == 'name' and spec.kind == 'text' and (spec.source == 'name' or spec.source == 'nameFill') and spec.colors ~= nil then
				out[#out + 1] = { id = id, field = 'colors', kind = 'text' }
			elseif piece == 'cast' and spec.kind == 'cast' and spec.colors ~= nil then
				out[#out + 1] = { id = id, field = 'colors', kind = 'cast' }
			end
		end
	end
	return out
end

---The list a piece takes its colors from now (its own name when it uses its own), or nil when
---this style has no part that draws the piece with a list.
---@param piece string
---@return string|nil
function ColorsPage.GetSource(piece)
	local slots = SlotsFor(piece)
	if #slots == 0 then
		return nil
	end
	local spec = ResolvedStyle().parts[slots[1].id]
	return spec[slots[1].field]
end

---@param piece string
---@param source string One of the four pieces
function ColorsPage.SetSource(piece, source)
	if not PIECE_LABELS[source] then
		return
	end
	local slots = SlotsFor(piece)
	if #slots == 0 then
		return
	end
	ColorsPage.EditOverlay(function(overlay, styleId)
		local base = P.Styles.Registry:Get(styleId)
		overlay.changes = overlay.changes or {}
		overlay.changes.parts = overlay.changes.parts or {}
		for _, slot in ipairs(slots) do
			local basePart = base and base.parts and base.parts[slot.id]
			local baseValue = basePart and basePart[slot.field]
			if baseValue == nil and slot.kind == 'cast' then
				baseValue = P.Styles.Merge.PART_DEFAULTS.cast[slot.field]
			end
			local change = overlay.changes.parts[slot.id] or {}
			overlay.changes.parts[slot.id] = change
			if basePart and baseValue == source then
				change[slot.field] = nil
			else
				change[slot.field] = source
			end
		end
	end)
end

----------------------------------------------------------------------------------------------------
-- Page
----------------------------------------------------------------------------------------------------

local function SchemeLabel(id)
	return Colors.SCHEME_LABELS[id] or tostring(id)
end

local function PieceLabel()
	return PIECE_LABELS[state.piece] or ''
end

local CHANNEL_NAMES = { bar = L['bar color'], border = L['border'], name = L['name'], glow = L['glow'], size = L['plate size'] }
local WHEN_NAMES = { always = L['always'], instances = L['in instances'], never = L['never'] }

---Plain words for what the threat row does right now.
---@return string
local function ThreatSummary()
	local on = Roles.ThreatOn(Role(), P.Store:Get({ 'threat', 'show' }))
	local names = {}
	for _, channel in ipairs(P.Threat.CHANNELS) do
		if on[channel] then
			names[#names + 1] = CHANNEL_NAMES[channel]
		end
	end
	local when = ColorsPage.GetThreatWhen()
	return string.format(L['Threat shows on: %s. When: %s.'], table.concat(names, ', '), WHEN_NAMES[when] or when)
end

local function Locked()
	return Options.Locked()
end

---True when the style on show has a threat glow part (the glow and size places need one).
---@return boolean
function ColorsPage.StyleHasThreatPart()
	for _, spec in pairs(ResolvedStyle().parts) do
		if spec.kind == 'glow' and spec.source == 'threat' then
			return true
		end
	end
	return false
end

---A description that gives the lock reason while the game restricts changes.
local function DescWhenLocked(text)
	return function()
		if Locked() then
			return Options.LOCKED_REASON
		end
		if type(text) == 'function' then
			return text()
		end
		return text
	end
end

---Take the player to a setting this page keeps elsewhere (opening the threat row first, and
---waiting a frame for the page to be drawn with it).
---@param key string 'threat' | 'mobType'
function ColorsPage.OpenHome(key)
	local host = P.host
	local function Go()
		if host and host.OpenOptions then
			host.OpenOptions('colors', key)
		end
	end
	if key == 'threat' and not state.threatOpen then
		state.threatOpen = true
		Options:RequestRefresh(false)
		P.Scheduler:NextFrame('Options.colorsGoto', function()
			P.Scheduler:NextFrame('Options.colorsGoto2', Go)
		end)
	else
		P.Scheduler:NextFrame('Options.colorsGoto', Go)
	end
end

local function BuildThreatGroup()
	local args = {
		explain = {
			type = 'description',
			order = 1,
			fontSize = 'medium',
			name = function()
				if Role() == 'tank' then
					return L['You are a tank. Safe means you hold it. Losing it means it is turning to someone else. Lost it means someone else has it.']
				end
				return L['Safe means you are not its target. Losing it means you are close to pulling it. Lost it means it is attacking you.']
			end,
		},
		role = {
			type = 'select',
			order = 2,
			name = L['My role'],
			desc = L['Threat works the other way around for tanks. Pick your role here, or let the game pick it from your spec.'],
			values = { auto = L['Automatic from my spec'], tank = L['Tank'], damage = L['Damage or healer'] },
			sorting = { 'auto', 'tank', 'damage' },
			get = function()
				local value = P.Store:Get('role')
				if value == 'healer' then
					value = 'damage'
				end
				return value or 'auto'
			end,
			set = function(_, value)
				ColorsPage.SetRole(value)
			end,
		},
		when = {
			type = 'select',
			order = 3,
			name = L['Show threat'],
			desc = L['Choose where threat colors appear. Never turns them off.'],
			values = { always = L['Always'], instances = L['In instances'], never = L['Never'] },
			sorting = { 'always', 'instances', 'never' },
			get = ColorsPage.GetThreatWhen,
			set = function(_, value)
				ColorsPage.SetThreatWhen(value)
			end,
		},
		show = {
			type = 'multiselect',
			order = 4,
			name = L['Show threat on'],
			desc = L['At least one stays on. To turn threat off, set Show threat to Never.'],
			values = {
				bar = L['Bar color'],
				border = L['Border'],
				name = L['Name'],
				glow = L['Glow'],
				size = L['Plate size'],
			},
			get = function(_, key)
				return ColorsPage.GetThreatShow(key)
			end,
			set = function(_, key, value)
				ColorsPage.SetThreatShow(key, value)
			end,
		},
		glowNote = {
			type = 'description',
			order = 4.5,
			name = L['This style has no threat glow, so Glow and Plate size do nothing here.'],
			hidden = function()
				return not (ColorsPage.GetThreatShow('glow') or ColorsPage.GetThreatShow('size')) or ColorsPage.StyleHasThreatPart()
			end,
		},
		numbers = {
			type = 'select',
			order = 5,
			name = L['Threat numbers'],
			desc = DescWhenLocked(function()
				if P.Caps:Get('secrets') then
					return L['Shows a number on the plate. It stays empty when the game hides threat, often on bosses.']
				end
				return L['Shows a number on the plate. It always works on this version of WoW.']
			end),
			values = { none = L['Off'], percent = L['Threat percent'], lead = L['Ahead or behind'] },
			sorting = { 'none', 'percent', 'lead' },
			get = function()
				return (ColorsPage.GetThreatNumbers())
			end,
			set = function(_, value)
				ColorsPage.SetThreatNumbers(value)
			end,
			disabled = Locked,
		},
		resetColors = {
			type = 'execute',
			order = 30,
			name = L['Use the standard threat colors'],
			hidden = function()
				return not ColorsPage.HasThreatColors()
			end,
			func = function()
				ColorsPage.ResetThreatColors()
			end,
		},
	}
	for index, key in ipairs(Roles.STATES) do
		args['color_' .. key] = {
			type = 'color',
			hasAlpha = false,
			order = 10 + index,
			name = STATE_LABELS[key],
			get = function()
				local c = ThreatPalette()[key]
				return c[1], c[2], c[3], c[4] or 1
			end,
			set = function(_, r, g, b)
				ColorsPage.SetThreatColor(key, { r, g, b, 1 })
			end,
		}
	end
	return args
end

local function BuildMobTypeGroup()
	local args = {
		note = {
			type = 'description',
			order = 20,
			name = L['These colors show in dungeons. You can change where in More settings.'],
		},
		reset = {
			type = 'execute',
			order = 30,
			name = L['Use the standard mob colors'],
			hidden = function()
				return not ColorsPage.HasMobTypeColors()
			end,
			func = function()
				for _, key in ipairs(MOB_STATES) do
					ColorsPage.SetMobTypeColor(key, nil)
				end
			end,
		},
	}
	for index, key in ipairs(MOB_STATES) do
		args[key] = {
			type = 'color',
			hasAlpha = false,
			order = index,
			name = STATE_LABELS[key],
			get = function()
				local c = ColorsPage.GetMobTypeColor(key)
				return c[1], c[2], c[3], c[4] or 1
			end,
			set = function(_, r, g, b)
				ColorsPage.SetMobTypeColor(key, { r, g, b, 1 })
			end,
		}
	end
	return args
end

---The RuleList's arg for the piece on show (every function reads the page state when called).
local function ListArg()
	return {
		header = function()
			local text = L['When more than one color fits, the top one wins.']
			local source = ColorsPage.GetSource(state.piece)
			if source and source ~= state.piece then
				text = text .. ' ' .. string.format(L['%s uses the %s list now, so this list is not used.'], PIECE_LABELS[state.piece], PIECE_LABELS[source])
			end
			return text
		end,
		rows = function()
			state.rowsAsked = true
			return ColorsPage.Rows(state.piece)
		end,
		flashId = function()
			local id = state.flash
			state.flash = nil
			return id
		end,
		addLabel = L['Add a color'],
		addChoices = function()
			return ColorsPage.AddChoices(state.piece)
		end,
		insertIndex = function(id, order)
			return ColorsPage.InsertIndex(state.piece, id, order)
		end,
		onChange = function(change)
			ColorsPage.ApplyChange(state.piece, change)
		end,
		onEdit = function(id, what)
			if what ~= 'color' then
				return false
			end
			if THREAT_ROWS[id] then
				ColorsPage.OpenHome('threat')
				return true
			elseif id == 'mobType' then
				ColorsPage.OpenHome('mobType')
				return true
			elseif id == 'class' then
				return true
			end
			return false
		end,
	}
end

Options:AddPage('colors', 3, function()
	local getBlind, setBlind = Options.Bind('colorBlind')
	local pieceValues, pieceSorting = {}, {}
	for _, piece in ipairs(PIECES) do
		pieceValues[piece] = PIECE_LABELS[piece]
		pieceSorting[#pieceSorting + 1] = piece
	end
	return {
		type = 'group',
		name = L['Colors'],
		args = {
			scheme = {
				type = 'select',
				name = L['Color my plates by'],
				desc = L['Pick which color wins first. If you change the order in More settings, this switches to Custom.'],
				order = 1,
				width = 'double',
				values = function()
					PageDrawn()
					local values = { auto = string.format(L['Automatic: %s'], SchemeLabel(Roles.Scheme(Role()))) }
					for _, id in ipairs(Colors.SCHEME_ORDER) do
						values[id] = SchemeLabel(id)
					end
					return values
				end,
				sorting = { 'auto', 'threat', 'mobType', 'class', 'custom' },
				get = function()
					return P.Store:Get('scheme') or 'auto'
				end,
				set = function(_, value)
					ColorsPage.SetScheme(value)
				end,
			},
			colorBlind = {
				type = 'toggle',
				name = L['Color-blind friendly colors'],
				desc = L['Uses threat colors that are easier to tell apart.'],
				order = 2,
				width = 'full',
				get = getBlind,
				set = setBlind,
			},
			threatToggle = {
				type = 'execute',
				name = function()
					return state.threatOpen and L['Hide threat colors'] or L['Show threat colors']
				end,
				desc = L['Choose when threat shows, where it shows, and its colors.'],
				order = 10,
				func = function()
					state.threatOpen = not state.threatOpen
				end,
			},
			threatSummary = {
				type = 'description',
				order = 11,
				hidden = function()
					return state.threatOpen
				end,
				name = ThreatSummary,
			},
			threat = {
				type = 'group',
				inline = true,
				order = 12,
				name = L['Threat colors'],
				hidden = function()
					return not state.threatOpen
				end,
				args = BuildThreatGroup(),
			},
			mobType = {
				type = 'group',
				inline = true,
				order = 20,
				name = L['Mob type colors'],
				args = BuildMobTypeGroup(),
			},
			listPiece = {
				type = 'select',
				name = L['Color list for'],
				desc = L['Each part of a plate has its own list of colors. Pick one to see and change it.'],
				order = 40,
				advanced = true,
				values = pieceValues,
				sorting = pieceSorting,
				get = function()
					return state.piece
				end,
				set = function(_, value)
					ColorsPage.SetPiece(value)
				end,
			},
			list = {
				type = 'select',
				dialogControl = P.Widgets:TypeName('RuleList'),
				name = PieceLabel,
				order = 41,
				width = 'full',
				advanced = true,
				values = {},
				get = function()
					return nil
				end,
				set = function() end,
				arg = ListArg(),
			},
			source = {
				type = 'select',
				name = function()
					return string.format(L['%s colors come from'], PieceLabel())
				end,
				desc = DescWhenLocked(L['One list can color more than one part. Pick another list to share it.']),
				order = 42,
				advanced = true,
				hidden = function()
					return ColorsPage.GetSource(state.piece) == nil
				end,
				values = function()
					local values = {}
					for _, piece in ipairs(PIECES) do
						values[piece] = piece == state.piece and L['Its own list'] or PIECE_LABELS[piece]
					end
					return values
				end,
				sorting = pieceSorting,
				get = function()
					return ColorsPage.GetSource(state.piece)
				end,
				set = function(_, value)
					ColorsPage.SetSource(state.piece, value)
				end,
				disabled = Locked,
			},
			resetList = {
				type = 'execute',
				name = L['Reset this list'],
				desc = L['Put this list back the way the choice at the top makes it.'],
				order = 43,
				advanced = true,
				hidden = function()
					return P.Store:Get({ 'colors', state.piece }) == nil
				end,
				func = function()
					P.Store:Set({ 'colors', state.piece }, nil)
				end,
			},
		},
	}
end)
