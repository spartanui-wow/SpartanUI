local _, ns = ...
local P = ns.Plates
local L = P.L
local Options = P.Options
local Store = P.Store
local CVars = P.CVars
local Situation = P.Situation
local WhenBuilder = P.WhenBuilder

-- Who and where page (3.2 #5). A table with one row per kind of plate (style, Show, "Same as
-- enemies"), the "When" list for special cases (the RuleList widget plus the shared WhenBuilder
-- editor), plate behavior, the honest note about friendly plates in instances and the game settings
-- table with "Give the game back its settings". More settings: the place-by-place table, click and
-- stacking areas, Copy and reset.
--
-- Where things are stored (all sparse, read again on every call):
--   profile.assign[kind], profile.modes[kind]   style and Show choice per kind of plate
--   profile.when                                 the special cases, written whole
--   profile.behavior[key], behavior.places[place][key]   what the Driver reads (see Engine/Driver.lua)
--   profile.cvars[name]                          game settings the player set on our pages
--   profile.tweaks[styleId].changes.regions      click and stacking area padding
--
-- Assignments (the table, the special cases, copy and reset) lock while P.Secret.IsRestricted(),
-- with a visible reason. Plate behavior never locks: the game settings it writes wait for combat to
-- end by themselves (CVars queue).

---@class Plates.WhoAndWhere
local W = { editing = nil, copyTarget = 'friendlyPlayer', copySource = 'enemyPlayer' }
Options.WhoAndWhere = W

W.LOCKED = L['The game does not allow plate changes right now. They unlock after combat.']

-- Space between plates is the game's vertical overlap setting. It is defined here until the CVar
-- registry carries it; defining is inert and repeating it changes nothing.
if not CVars.defs.nameplateOverlapV then
	CVars:Define('nameplateOverlapV', { kind = 'number', label = L['Game overlap setting'], page = 'whoAndWhere', min = 0.5, max = 3 })
end

local KIND_LABELS = WhenBuilder.KIND_LABELS
local MODE_VALUES = { full = L['Full'], name = L['Names only'], hidden = L['Hidden'] }
local MODE_ORDER = { 'full', 'name', 'hidden' }

local function Locked()
	return Options.Locked()
end

local function Copy(value)
	return P.util.Copy(value)
end

----------------------------------------------------------------------------------------------------
-- Kinds of plates: style and Show
----------------------------------------------------------------------------------------------------

---Show choice of a kind: 'full' | 'name' | 'hidden'.
---@param kind string
---@return string
function W.Mode(kind)
	return Store:Get({ 'modes', kind }) or Situation.DEFAULT_MODES[kind] or 'full'
end

---Store a Show choice; the default for the kind is stored as nothing.
---@param kind string
---@param value string
function W.SetMode(kind, value)
	if Locked() then
		return
	end
	if value == (Situation.DEFAULT_MODES[kind] or 'full') then
		value = nil
	end
	Store:Set({ 'modes', kind }, value)
end

---The style a kind uses when the player has not picked one: minor enemies use Mini, everything
---else follows the main style.
---@param kind string
---@return string
function W.DefaultStyle(kind)
	return Situation.DEFAULT_ASSIGN[kind] or Store:Get('style') or 'host'
end

---Style id of a kind ('host' stands for the style that matches the host's look).
---@param kind string
---@return string
function W.Style(kind)
	return Store:Get({ 'assign', kind }) or W.DefaultStyle(kind)
end

---@param kind string
---@param value string
function W.SetStyle(kind, value)
	if Locked() then
		return
	end
	if value == W.DefaultStyle(kind) then
		value = nil
	end
	Store:Set({ 'assign', kind }, value)
end

---Style choices for a dropdown (id -> name) and their order.
---@param current? string
---@return table<string, string> values
---@return string[] order
function W.StyleValues(current)
	return WhenBuilder:StyleValues(current)
end

local function SameStyle(a, b)
	local Registry = P.Styles.Registry
	return Registry:ResolveId(a) == Registry:ResolveId(b)
end

---True when a kind already looks and shows like Enemy NPCs.
---@param kind string
---@return boolean
function W.IsSameAsEnemies(kind)
	return SameStyle(W.Style(kind), W.Style('enemyNPC')) and W.Mode(kind) == W.Mode('enemyNPC')
end

---"Same as enemies": copy the style and Show choice of Enemy NPCs.
---@param kind string
function W.SameAsEnemies(kind)
	if Locked() or kind == 'enemyNPC' then
		return
	end
	Store:Batch(function()
		W.SetStyle(kind, W.Style('enemyNPC'))
		W.SetMode(kind, W.Mode('enemyNPC'))
	end)
end

----------------------------------------------------------------------------------------------------
-- Special cases ("When" list)
----------------------------------------------------------------------------------------------------

local function WhenList()
	local list = Store:Get('when')
	return type(list) == 'table' and Copy(list) or {}
end

local function WriteWhen(list)
	if #list == 0 then
		Store:Set('when', nil)
	else
		Store:Set('when', list)
	end
end

local function EntryIndex(id)
	return type(id) == 'string' and tonumber(string.match(id, '^w(%d+)$')) or nil
end

---The special cases as RuleList rows. Row ids are 'w' plus the place in the list, so a reorder
---arrives as a list of old places in their new order.
---@return Plates.RuleRow[]
function W.WhenRows()
	local rows = {}
	for index, entry in ipairs(WhenList()) do
		local problems = WhenBuilder:Problems(entry, 'layout')
		rows[#rows + 1] = {
			id = 'w' .. index,
			sentence = WhenBuilder:Sentence(entry),
			whenText = WhenBuilder:Short(entry, 'layout'),
			on = not entry.off,
			removable = true,
			badge = problems[1] or WhenBuilder:EntryBadge(entry, 'layout'),
			tooltip = WhenBuilder:Describe(entry, 'layout'),
		}
	end
	return rows
end

---The Add menu: one choice per template.
---@return table[]
function W.WhenAddChoices()
	local out = {}
	for _, template in ipairs(WhenBuilder:Templates('layout')) do
		out[#out + 1] = { id = 'tpl:' .. template.id, label = template.label }
	end
	return out
end

---Open (or close, when it is already open) the editor for a list row.
---@param id string|number Row id
---@return boolean open
function W.ToggleEditing(id)
	local index = EntryIndex(id)
	if index and W.editing ~= index and WhenList()[index] then
		W.editing = index
	else
		W.editing = nil
	end
	Options:RequestRefresh(true)
	return W.editing ~= nil
end

---The entry in the editor (a copy), or nil.
---@return table|nil
function W.EditedEntry()
	local index = W.editing
	if not index then
		return nil
	end
	local entry = WhenList()[index]
	return entry and Copy(entry) or nil
end

---Store the edited entry back in its place.
---@param entry table
function W.SetEditedEntry(entry)
	if Locked() then
		return
	end
	local index = W.editing
	local list = WhenList()
	if index and list[index] then
		list[index] = entry
		WriteWhen(list)
	end
end

---Apply a RuleList change (reorder, switch, remove or add) to the stored list. The widget hands
---over the whole new order and the on/off state of every row, so one routine covers all four.
---@param change Plates.RuleChange
function W.ApplyWhenChange(change)
	if Locked() then
		return
	end
	local old = WhenList()
	local list = {}
	local editing
	for position, id in ipairs(change.order or {}) do
		local entry
		local index = EntryIndex(id)
		if index and old[index] then
			entry = Copy(old[index])
			if index == W.editing then
				editing = #list + 1
			end
		elseif type(id) == 'string' and string.sub(id, 1, 4) == 'tpl:' then
			entry = WhenBuilder:NewEntry(string.sub(id, 5))
			if entry and change.action == 'add' then
				editing = #list + 1
			end
		end
		if entry then
			local row = change.rows and change.rows[position]
			entry.off = (row and row.on == false) or nil
			list[#list + 1] = entry
		end
	end
	W.editing = editing
	WriteWhen(list)
	Options:RequestRefresh(true)
end

----------------------------------------------------------------------------------------------------
-- Plate behavior
----------------------------------------------------------------------------------------------------

local function Behavior(key)
	return Store:Get({ 'behavior', key })
end

local function SetBehavior(key, value)
	Store:Set({ 'behavior', key }, value)
end

---Whether a plate behavior works here, and why not.
---@param id string
---@return boolean available
---@return string|nil reason
function W.Feature(id)
	return P.Driver:FeatureState(id)
end

local function FeatureOK(id)
	return (P.Driver:FeatureState(id))
end

local function FeatureNote(id, order, advanced)
	return {
		type = 'description',
		order = order,
		advanced = advanced,
		name = function()
			local ok, reason = P.Driver:FeatureState(id)
			return (not ok and reason) or ''
		end,
		hidden = function()
			return (P.Driver:FeatureState(id))
		end,
	}
end

local ENEMY_MINIONS = {
	{ key = 'pets', cvar = 'nameplateShowEnemyPets', label = L['Pets'] },
	{ key = 'guardians', cvar = 'nameplateShowEnemyGuardians', label = L['Guardians'] },
	{ key = 'totems', cvar = 'nameplateShowEnemyTotems', label = L['Totems'] },
	{ key = 'minions', cvar = 'nameplateShowEnemyMinions', label = L['Pets and minions'] },
}
local FRIEND_MINIONS = {
	{ key = 'pets', cvar = 'nameplateShowFriendlyPlayerPets', label = L['Pets'] },
	{ key = 'guardians', cvar = 'nameplateShowFriendlyPlayerGuardians', label = L['Guardians'] },
	{ key = 'totems', cvar = 'nameplateShowFriendlyPlayerTotems', label = L['Totems'] },
	{ key = 'minions', cvar = 'nameplateShowFriendlyPlayerMinions', label = L['Pets and minions'] },
}
W.ENEMY_MINIONS, W.FRIEND_MINIONS = ENEMY_MINIONS, FRIEND_MINIONS

---The pets, totems and guardians switches this client has (a missing setting hides its box).
---@param list table[]
---@return table<string, string> values
---@return string[] order
function W.MinionValues(list)
	local values, order = {}, {}
	for _, row in ipairs(list) do
		if CVars:Exists(row.cvar) then
			values[row.key] = row.label
			order[#order + 1] = row.key
		end
	end
	return values, order
end

local function MinionRow(list, key)
	for _, row in ipairs(list) do
		if row.key == key then
			return row
		end
	end
	return nil
end

local function GameBool(name)
	local own = Store:Get({ 'cvars', name })
	if own ~= nil then
		return own == true or own == 1 or own == '1'
	end
	local value = CVars:Get(name)
	return value ~= nil and value ~= '0' and value ~= ''
end

---Whether a pet, totem or guardian kind gets a plate: the player's choice, else the game's.
---@param list table[]
---@param key string
---@return boolean
function W.MinionOn(list, key)
	local row = MinionRow(list, key)
	return row ~= nil and GameBool(row.cvar)
end

---@param list table[]
---@param key string
---@param on boolean
function W.SetMinion(list, key, on)
	local row = MinionRow(list, key)
	if row then
		Store:Set({ 'cvars', row.cvar }, on and true or false)
	end
end

---Enemy plates: 'game' (leave it to the game), 'always' or 'combat'.
---@return string
function W.Enemies()
	return Behavior('enemies') or 'game'
end

---@param value string
function W.SetEnemies(value)
	SetBehavior('enemies', value ~= 'game' and value or nil)
end

---Whether plates push each other apart for enemies or friends: the player's choice, else the game's.
---@param key 'enemy'|'friendly'
---@return boolean
function W.Stacking(key)
	local own = Store:Get({ 'behavior', 'stacking', key })
	if own ~= nil then
		return own
	end
	return CVars:GetBit('nameplateStackingTypes', key) == true
end

---@param key 'enemy'|'friendly'
---@param on boolean
function W.SetStacking(key, on)
	Store:Set({ 'behavior', 'stacking', key }, on and true or false)
end

---A numeric game setting for a slider: the player's choice, else the game's value, else the
---default, kept inside the slider's range.
---@param name string
---@param fallback number
---@param min number
---@param max number
---@return number
function W.NumberCVar(name, fallback, min, max)
	local value = Store:Get({ 'cvars', name })
	if type(value) ~= 'number' then
		value = tonumber(CVars:Get(name))
	end
	if value == nil then
		value = tonumber(CVars:Probe(name).default) or fallback
	end
	return math.max(min, math.min(max, value))
end

local function ToggleNumber(key, defaultValue)
	return {
		get = function()
			return type(Behavior(key)) == 'number'
		end,
		set = function(_, on)
			if on then
				SetBehavior(key, type(Behavior(key)) == 'number' and Behavior(key) or defaultValue)
			else
				SetBehavior(key, nil)
			end
		end,
	}
end

---How much plates fade, 0 (not at all) to 1 (gone), for a behavior that stores the plate's alpha.
---@param key string
---@param fallback number Alpha used while none is stored
---@return number
function W.FadeAmount(key, fallback)
	local alpha = Behavior(key)
	if type(alpha) ~= 'number' then
		alpha = fallback
	end
	return math.max(0, math.min(1, 1 - alpha))
end

---@param key string
---@param amount number
function W.SetFadeAmount(key, amount)
	SetBehavior(key, math.max(0, math.min(1, 1 - amount)))
end

----------------------------------------------------------------------------------------------------
-- Game settings table
----------------------------------------------------------------------------------------------------

local BIT_LABELS = {
	enemy = L['enemies'],
	friendly = L['friends'],
	buffs = L['buffs'],
	debuffs = L['debuffs'],
	crowdControl = L['crowd control'],
}

local WHY_LABELS = {
	place = L['for this place'],
	setup = L['during setup'],
	player = L['you asked for it'],
	restore = L['put back'],
}

---A game setting's value as words.
---@param name string
---@param value any
---@return string
function W.FormatValue(name, value)
	if value == nil then
		return '-'
	end
	local def = CVars.defs[name]
	if not def then
		return tostring(value)
	end
	if def.kind == 'bool' then
		local text = tostring(value)
		return (text == '1' or text == 'true') and L['On'] or L['Off']
	elseif def.kind == 'number' then
		local number = tonumber(value)
		if not number then
			return tostring(value)
		end
		return (string.gsub(string.format('%.2f', number), '%.?0+$', ''))
	elseif def.kind == 'bitfield' then
		local number = tonumber(value) or 0
		local on = {}
		for key, index in pairs(def.bits or {}) do
			if math.floor(number / 2 ^ (index - 1)) % 2 == 1 then
				on[#on + 1] = { index = index, text = BIT_LABELS[key] or key }
			end
		end
		table.sort(on, function(a, b)
			return a.index < b.index
		end)
		local words = {}
		for i, item in ipairs(on) do
			words[i] = item.text
		end
		return #words > 0 and table.concat(words, ', ') or L['none']
	end
	return tostring(value)
end

---Who last changed a game setting, in words.
---@param name string
---@return string
function W.WhoChanged(name)
	local attribution = CVars:GetAttribution(name)
	local host = P:HostName()
	if attribution then
		if attribution.by == 'other' then
			return L['The game or another add-on']
		end
		local why = WHY_LABELS[attribution.why]
		if why then
			return string.format(L['%s, %s'], host, why)
		end
		return host
	end
	if CVars:GetBackup(name) ~= nil then
		return string.format(L['%s, in an earlier session'], host)
	end
	return L['Not known']
end

---Every game setting in registry order, including settings with no player control.
---@return table[]
function W.GameDefinitions()
	local pages, seen, byName, out = {}, {}, {}, {}
	for _, name in ipairs(CVars.order) do
		local page = CVars.defs[name].page or false
		if not seen[page] then
			seen[page] = true
			pages[#pages + 1] = page
		end
	end
	for _, page in ipairs(pages) do
		for _, row in ipairs(CVars:List(page or nil)) do
			byName[row.def.name] = row
		end
	end
	for _, name in ipairs(CVars.order) do
		if byName[name] then
			out[#out + 1] = byName[name]
		end
	end
	return out
end

---@param name string
---@return boolean
function W.GamePending(name)
	if CVars.queue[name] then
		return true
	end
	for key in pairs((CVars.defs[name] or {}).bits or {}) do
		if CVars.queue[name .. ':' .. key] then
			return true
		end
	end
	return false
end

---One line of the game settings table, or nil when we have not changed that setting.
---@param name string
---@return { name: string, label: string, was: string, now: string, by: string }|nil
function W.GameRow(name)
	local def = CVars.defs[name]
	if not def or not CVars:Exists(name) then
		return nil
	end
	local backup = CVars:GetBackup(name)
	local attribution = CVars:GetAttribution(name)
	if backup == nil and not W.GamePending(name) and not (attribution and attribution.by == 'other') then
		return nil
	end
	local now = W.FormatValue(name, CVars:Get(name))
	if W.GamePending(name) then
		now = string.format(L['%s (waiting for combat to end)'], now)
	end
	return {
		name = name,
		label = def.label,
		was = backup ~= nil and W.FormatValue(name, backup) or '-',
		now = now,
		by = W.WhoChanged(name),
	}
end

---Every row of the table now.
---@return table[]
function W.GameRows()
	local rows = {}
	for _, definition in ipairs(W.GameDefinitions()) do
		local row = W.GameRow(definition.def.name)
		if row then
			rows[#rows + 1] = row
		end
	end
	return rows
end

---"Give the game back its settings". Returns true when everything is back already.
---@return boolean done
function W.RestoreGame()
	local done = CVars:RestoreAll()
	if not done then
		P.log.info('Some nameplate settings come back when combat ends')
	end
	Options:RequestRefresh(false)
	return done
end

----------------------------------------------------------------------------------------------------
-- Place by place
----------------------------------------------------------------------------------------------------

W.PLACE_ROWS = {
	{ id = 'world', places = { 'world' }, label = L['Out in the world'] },
	{ id = 'dungeon', places = { 'dungeon', 'scenario' }, label = L['Dungeon'] },
	{ id = 'raid', places = { 'raid' }, label = L['Raid'] },
	{ id = 'delve', places = { 'delve' }, label = L['Delve'] },
	{ id = 'pvp', places = { 'arena', 'battleground' }, label = L['Arena and battleground'] },
}

W.PLACE_COLUMNS = {
	{ id = 'enemies', label = L['Enemy plates'], key = 'enemies', choice = 'enemies' },
	{ id = 'friendlyPlayers', label = L['Friendly players'], key = 'friendlyPlayers', choice = 'showHide' },
	{ id = 'friendlyNPCs', label = L['Friendly NPCs'], key = 'friendlyNPCs', choice = 'showHide' },
	{ id = 'stackEnemy', label = L['Enemies overlap'], key = 'stacking', sub = 'enemy', choice = 'onOff' },
	{ id = 'stackFriendly', label = L['Friends overlap'], key = 'stacking', sub = 'friendly', choice = 'onOff' },
}

local PLACE_CHOICES = {
	enemies = { values = { default = L['Default'], always = L['Always'], combat = L['In combat'] }, order = { 'default', 'always', 'combat' } },
	showHide = { values = { default = L['Default'], show = L['Show'], hide = L['Hide'] }, order = { 'default', 'show', 'hide' } },
	onOff = { values = { default = L['Default'], on = L['On'], off = L['Off'] }, order = { 'default', 'on', 'off' } },
}
W.PLACE_CHOICES = PLACE_CHOICES

local function PlacePath(place, column)
	local path = { 'behavior', 'places', place, column.key }
	if column.sub then
		path[#path + 1] = column.sub
	end
	return path
end

---The choice shown for a row and column ('default' when the place has nothing of its own).
---@param row table PLACE_ROWS entry
---@param column table PLACE_COLUMNS entry
---@return string
function W.PlaceValue(row, column)
	local stored = Store:Get(PlacePath(row.places[1], column))
	if stored == nil then
		return 'default'
	elseif column.choice == 'enemies' then
		return stored
	elseif column.choice == 'showHide' then
		return stored and 'show' or 'hide'
	end
	return stored and 'on' or 'off'
end

---@param row table
---@param column table
---@param choice string
function W.SetPlaceValue(row, column, choice)
	local value
	if choice == 'default' then
		value = nil
	elseif column.choice == 'enemies' then
		value = choice
	elseif column.choice == 'showHide' then
		value = choice == 'show'
	else
		value = choice == 'on'
	end
	Store:Batch(function()
		for _, place in ipairs(row.places) do
			Store:Set(PlacePath(place, column), value)
		end
	end)
end

----------------------------------------------------------------------------------------------------
-- Click and stacking areas
----------------------------------------------------------------------------------------------------

local function PadOf(spec)
	local pad = spec and spec.pad
	if type(pad) == 'table' then
		return { pad[1] or 0, pad[2] or 0, pad[3] or 0, pad[4] or 0 }
	end
	return { 0, 0, 0, 0 }
end

---Styles whose areas the controls change: every style the plates use, plus the names-only style
---(friendly players use it by default).
---@return string[] ids Resolved style ids, the main style first
function W.AreaStyles()
	local Registry = P.Styles.Registry
	local seen, out = {}, {}
	local function Add(id)
		if id == nil then
			return
		end
		local resolved = Registry:ResolveId(id)
		if not seen[resolved] then
			seen[resolved] = true
			out[#out + 1] = resolved
		end
	end
	Add(Store:Get('style'))
	for _, kind in ipairs(Situation.KINDS) do
		Add(W.Style(kind))
	end
	for _, entry in ipairs(WhenList()) do
		Add(entry.style)
	end
	Add(Situation.NAME_STYLE)
	return out
end

---What a style's click or stacking area is made of right now.
---@param styleId string
---@param which 'click'|'stack'
---@return { adjustable: boolean, base: integer[], pad: integer[], rawHeight: number, height: number }|nil
function W.RegionState(styleId, which)
	local Registry, Merge = P.Styles.Registry, P.Styles.Merge
	local id = Registry:ResolveId(styleId)
	local base = Registry:Get(id)
	if not base then
		return nil
	end
	local baseSpec = base.regions and base.regions[which]
	local overlay = Store:Get({ 'tweaks', id, 'changes', 'regions', which })
	local pad = PadOf((overlay and overlay.pad) and overlay or baseSpec)
	local resolved = Merge:Resolve(id, nil, Store:Get('size') or 'medium')
	local rect = resolved and resolved.regions and resolved.regions[which]
	if not rect then
		return nil
	end
	local adjustable = true
	if (overlay and overlay.auto == false) or (baseSpec and baseSpec.auto == false) then
		adjustable = false
	end
	for _, spec in pairs(resolved.parts or {}) do
		if spec.kind == 'region' and (spec.region or 'click') == which and spec.width and spec.height then
			adjustable = false
		end
	end
	local height = rect.top - rect.bottom
	return { adjustable = adjustable, base = PadOf(baseSpec), pad = pad, rawHeight = height - pad[3] - pad[4], height = height }
end

---True when the areas can be changed here, and why not otherwise.
---@return boolean ok
---@return string|nil reason
function W.AreasAdjustable()
	local main = W.AreaStyles()[1]
	local click = W.RegionState(main, 'click')
	local stack = W.RegionState(main, 'stack')
	if not click or not stack then
		return false, L['This style has no click area to change.']
	end
	if not click.adjustable or not stack.adjustable then
		return false, L['This style places its areas by hand. Change them in Customize.']
	end
	return true
end

---Extra pixels of click area on every side, on top of what each style already has.
---@return integer
function W.ClickExtra()
	local state = W.RegionState(W.AreaStyles()[1], 'click')
	if not state then
		return 0
	end
	return math.max(0, state.pad[1] - state.base[1])
end

---@param extra integer
function W.SetClickExtra(extra)
	extra = math.max(0, math.min(32, math.floor((tonumber(extra) or 0) + 0.5)))
	Store:Batch(function()
		for _, id in ipairs(W.AreaStyles()) do
			local state = W.RegionState(id, 'click')
			if state and state.adjustable then
				local path = { 'tweaks', id, 'changes', 'regions', 'click', 'pad' }
				if extra == 0 then
					Store:Set(path, nil)
				else
					local pad = {}
					for i = 1, 4 do
						pad[i] = math.max(0, math.min(64, state.base[i] + extra))
					end
					Store:Set(path, pad)
				end
			end
		end
	end)
end

---How tall the stacking area is next to the plate's parts, as a fraction (1 = just the parts).
---@return number
function W.StackHeight()
	local state = W.RegionState(W.AreaStyles()[1], 'stack')
	if not state or state.rawHeight <= 0 then
		return 1
	end
	return state.height / state.rawHeight
end

---@param fraction number 1 to 3
function W.SetStackHeight(fraction)
	fraction = math.max(1, math.min(3, tonumber(fraction) or 1))
	Store:Batch(function()
		for _, id in ipairs(W.AreaStyles()) do
			local state = W.RegionState(id, 'stack')
			if state and state.adjustable and state.rawHeight > 0 then
				local path = { 'tweaks', id, 'changes', 'regions', 'stack', 'pad' }
				local total = math.floor(state.rawHeight * (fraction - 1) + 0.5)
				if total == state.base[3] + state.base[4] then
					Store:Set(path, nil)
				else
					local top = math.min(64, math.ceil(total / 2))
					local bottom = math.max(0, math.min(64, total - math.ceil(total / 2)))
					Store:Set(path, { state.base[1], state.base[2], top, bottom })
				end
			end
		end
	end)
end

----------------------------------------------------------------------------------------------------
-- Copy and reset
----------------------------------------------------------------------------------------------------

local function TweakIds()
	local ids = {}
	for id in pairs(Store:Get('tweaks') or {}) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	return ids
end

---Copy the style, the Show choice and the changes made only for one kind onto another kind.
---@param from string
---@param to string
---@return boolean copied
function W.CopyKind(from, to)
	if Locked() or from == to or not (KIND_LABELS[from] and KIND_LABELS[to]) then
		return false
	end
	Store:Batch(function()
		W.SetStyle(to, W.Style(from))
		W.SetMode(to, W.Mode(from))
		for _, id in ipairs(TweakIds()) do
			local patch = Store:Get({ 'tweaks', id, 'situations', from })
			Store:Set({ 'tweaks', id, 'situations', to }, patch ~= nil and Copy(patch) or nil)
		end
	end)
	return true
end

---Put one kind back to the default style and Show choice and drop the changes made only for it.
---@param kind string
function W.ResetKind(kind)
	if Locked() or not KIND_LABELS[kind] then
		return
	end
	Store:Batch(function()
		Store:Set({ 'assign', kind }, nil)
		Store:Set({ 'modes', kind }, nil)
		for _, id in ipairs(TweakIds()) do
			Store:Set({ 'tweaks', id, 'situations', kind }, nil)
		end
	end)
end

----------------------------------------------------------------------------------------------------
-- The page
----------------------------------------------------------------------------------------------------

local function Heading(text, relWidth, order)
	return { type = 'description', name = text, fontSize = 'small', width = 'relative', relWidth = relWidth, order = order }
end

local function KindsGroup()
	local args = {
		head = {
			type = 'group',
			name = '',
			inline = true,
			order = 1,
			args = {
				plates = Heading(L['Plates'], 0.2, 1),
				style = Heading(L['Style'], 0.32, 2),
				show = Heading(L['Show'], 0.22, 3),
			},
		},
	}
	for index, kind in ipairs(Situation.KINDS) do
		local label = KIND_LABELS[kind]
		local row = {
			label = { type = 'description', name = label, fontSize = 'medium', width = 'relative', relWidth = 0.2, order = 1 },
			style = {
				type = 'select',
				name = '',
				desc = string.format(L['The style for %s. It is not used when Show is Names only or Hidden.'], label),
				order = 2,
				width = 'relative',
				relWidth = 0.32,
				values = function()
					return (W.StyleValues(W.Style(kind)))
				end,
				sorting = function()
					local _, order = W.StyleValues(W.Style(kind))
					return order
				end,
				get = function()
					return W.Style(kind)
				end,
				set = function(_, value)
					W.SetStyle(kind, value)
				end,
				disabled = function()
					return Locked() or W.Mode(kind) ~= 'full'
				end,
			},
			mode = {
				type = 'select',
				name = '',
				desc = string.format(L['How much to draw for %s. Full is the whole plate, Names only is just the name, Hidden draws nothing.'], label),
				order = 3,
				width = 'relative',
				relWidth = 0.22,
				values = MODE_VALUES,
				sorting = MODE_ORDER,
				get = function()
					return W.Mode(kind)
				end,
				set = function(_, value)
					W.SetMode(kind, value)
				end,
				disabled = Locked,
			},
		}
		if kind ~= 'enemyNPC' then
			row.same = {
				type = 'execute',
				name = L['Same as enemies'],
				desc = L['Use the style and the Show choice of Enemy NPCs.'],
				order = 4,
				width = 'relative',
				relWidth = 0.24,
				func = function()
					W.SameAsEnemies(kind)
				end,
				disabled = function()
					return Locked() or W.IsSameAsEnemies(kind)
				end,
			}
		end
		args[kind] = { type = 'group', name = '', inline = true, order = 1 + index, args = row }
	end
	args.note = {
		type = 'description',
		order = 20,
		name = L['Inside dungeons and raids the game draws friendly plates itself. You can pick names only and class colors there, nothing more.'],
		hidden = function()
			return not P.Caps:Get('secrets')
		end,
	}
	args.friendlyNames = {
		type = 'toggle',
		order = 21,
		width = 'full',
		name = L['Names only in class colors for friends in dungeons and raids'],
		desc = L['The game draws friendly plates itself inside dungeons and raids. This makes them show names only, in class colors.'],
		get = function()
			return Behavior('friendlyNames') == true
		end,
		set = function(_, value)
			SetBehavior('friendlyNames', value and true or nil)
		end,
		disabled = function()
			return not FeatureOK('friendlyNames')
		end,
	}
	args.friendlyNamesNote = FeatureNote('friendlyNames', 22)
	return { type = 'group', name = L['Kinds of plates'], inline = true, order = 2, args = args }
end

local function WhenGroup()
	local listType = P.Widgets:Has('RuleList') and P.Widgets:TypeName('RuleList') or nil
	local args = {}
	args.list = {
		type = 'select',
		name = '',
		order = 1,
		width = 'full',
		dialogControl = listType,
		values = {},
		get = function()
			return W.editing and ('w' .. W.editing) or nil
		end,
		set = function() end,
		disabled = Locked,
		arg = {
			header = L['Special cases change how plates look in certain places. The first one that fits wins, so put the most specific ones at the top. Click one to edit it.'],
			addLabel = L['Add a special case'],
			empty = L['No special cases yet. Add one to change plates in a raid, in PvP and more.'],
			lockedReason = W.LOCKED,
			rows = W.WhenRows,
			addChoices = W.WhenAddChoices,
			onChange = W.ApplyWhenChange,
			onEdit = function(id, what)
				if what == 'row' then
					W.ToggleEditing(id)
					return true
				end
				return false
			end,
		},
	}
	args.editor = WhenBuilder:Group({
		context = 'layout',
		order = 2,
		get = W.EditedEntry,
		set = W.SetEditedEntry,
		disabled = Locked,
		onDone = function()
			W.editing = nil
			Options:RequestRefresh(false)
		end,
	})
	return { type = 'group', name = L['Special cases'], inline = true, order = 3, args = args }
end

local function BehaviorGroup()
	local fadeWalls = ToggleNumber('fadeBehindWalls', 0.4)
	local rangeFade = ToggleNumber('rangeFade', 0.5)
	local args = {}

	args.enemies = {
		type = 'select',
		name = L['Enemy plates'],
		desc = L['When enemy plates show. Always keeps them on. In combat shows them only while you fight. Leave it to the game keeps the game setting.'],
		order = 1,
		values = { game = L['Leave it to the game'], always = L['Always'], combat = L['In combat'] },
		sorting = { 'game', 'always', 'combat' },
		get = W.Enemies,
		set = function(_, value)
			W.SetEnemies(value)
		end,
	}

	args.minions = {
		type = 'multiselect',
		name = L['Enemy pets, totems and guardians'],
		desc = L['Pick which of these get a plate.'],
		order = 2,
		values = function()
			return (W.MinionValues(ENEMY_MINIONS))
		end,
		sorting = function()
			local _, order = W.MinionValues(ENEMY_MINIONS)
			return order
		end,
		get = function(_, key)
			return W.MinionOn(ENEMY_MINIONS, key)
		end,
		set = function(_, key, value)
			W.SetMinion(ENEMY_MINIONS, key, value)
		end,
		hidden = function()
			return next((W.MinionValues(ENEMY_MINIONS))) == nil
		end,
	}

	args.stacking = {
		type = 'multiselect',
		name = L['Keep plates from overlapping'],
		desc = L['Plates push each other apart so you can read them in a crowd.'],
		order = 3,
		values = { enemy = L['Enemies'], friendly = L['Friends'] },
		sorting = { 'enemy', 'friendly' },
		get = function(_, key)
			return W.Stacking(key)
		end,
		set = function(_, key, value)
			W.SetStacking(key, value)
		end,
		disabled = function()
			return not FeatureOK('stacking')
		end,
	}
	args.stackingNote = FeatureNote('stacking', 3.1)

	args.spacing = {
		type = 'range',
		name = L['Space between plates'],
		desc = L['How tall each plate counts when plates push each other apart. 100% is just the plate. Bigger numbers leave more room between plates.'],
		order = 4,
		min = 1,
		max = 3,
		step = 0.05,
		isPercent = true,
		get = W.StackHeight,
		set = function(_, value)
			W.SetStackHeight(value)
		end,
		disabled = function()
			return not (W.AreasAdjustable()) or not FeatureOK('stacking')
		end,
	}
	args.spacingNote = {
		type = 'description',
		order = 4.1,
		name = function()
			local _, reason = W.AreasAdjustable()
			return reason or ''
		end,
		hidden = function()
			return (W.AreasAdjustable())
		end,
	}

	args.clickThrough = {
		type = 'toggle',
		name = L['Click through friendly plates'],
		desc = L['Clicks go to the player or object behind a friendly plate.'],
		order = 5,
		width = 'full',
		get = function()
			return Behavior('clickThroughFriendly') == true
		end,
		set = function(_, value)
			SetBehavior('clickThroughFriendly', value and true or nil)
		end,
		disabled = function()
			return not FeatureOK('clickThroughFriendly')
		end,
	}
	args.clickThroughNote = FeatureNote('clickThroughFriendly', 5.1)

	args.fadeWalls = {
		type = 'toggle',
		name = L['Fade plates behind walls'],
		desc = L['Plates fade when something blocks your view of the enemy.'],
		order = 6,
		width = 'full',
		get = fadeWalls.get,
		set = fadeWalls.set,
		disabled = function()
			return not FeatureOK('fadeBehindWalls')
		end,
	}
	args.fadeWallsNote = FeatureNote('fadeBehindWalls', 6.1)

	args.rangeFade = {
		type = 'toggle',
		name = L['Fade plates out of range'],
		desc = L['Plates of enemies that are far away look fainter.'],
		order = 7,
		width = 'full',
		get = rangeFade.get,
		set = rangeFade.set,
		disabled = function()
			return not FeatureOK('rangeFade')
		end,
	}
	args.rangeFadeNote = FeatureNote('rangeFade', 7.1)

	args.distance = {
		type = 'range',
		name = L['How far away plates show'],
		desc = L['In yards. A bigger number shows more plates and can cost speed in big pulls.'],
		order = 8,
		min = 10,
		max = 100,
		step = 1,
		get = function()
			return W.NumberCVar('nameplateMaxDistance', 60, 10, 100)
		end,
		set = function(_, value)
			Store:Set({ 'cvars', 'nameplateMaxDistance' }, value)
		end,
		hidden = function()
			return not CVars:Exists('nameplateMaxDistance')
		end,
	}

	-- More settings
	args.friendMinions = {
		type = 'multiselect',
		name = L['Friendly pets, totems and guardians'],
		desc = L['Pick which of these get a plate.'],
		order = 20,
		advanced = true,
		values = function()
			return (W.MinionValues(FRIEND_MINIONS))
		end,
		sorting = function()
			local _, order = W.MinionValues(FRIEND_MINIONS)
			return order
		end,
		get = function(_, key)
			return W.MinionOn(FRIEND_MINIONS, key)
		end,
		set = function(_, key, value)
			W.SetMinion(FRIEND_MINIONS, key, value)
		end,
		hidden = function()
			return next((W.MinionValues(FRIEND_MINIONS))) == nil
		end,
	}
	args.gameOverlap = {
		type = 'range',
		name = L['Game overlap setting'],
		desc = L['How close the game lets plates stack. Lower numbers pack plates tighter.'],
		order = 20.5,
		advanced = true,
		min = 0.5,
		max = 3,
		step = 0.05,
		isPercent = true,
		get = function()
			return W.NumberCVar('nameplateOverlapV', 1.1, 0.5, 3)
		end,
		set = function(_, value)
			Store:Set({ 'cvars', 'nameplateOverlapV' }, value)
		end,
		hidden = function()
			return not CVars:Exists('nameplateOverlapV')
		end,
	}
	args.onlyFighting = {
		type = 'toggle',
		name = L['Only show enemies that are fighting'],
		desc = L['Hides the plates of enemies that are not in a fight. Your target and focus always show.'],
		order = 21,
		width = 'full',
		advanced = true,
		get = function()
			return Behavior('onlyFighting') == true
		end,
		set = function(_, value)
			SetBehavior('onlyFighting', value and true or nil)
		end,
		disabled = function()
			return not FeatureOK('onlyFighting')
		end,
	}
	args.onlyFightingNote = FeatureNote('onlyFighting', 21.1, true)
	args.wallsAmount = {
		type = 'range',
		name = L['How much plates fade behind walls'],
		order = 22,
		advanced = true,
		min = 0,
		max = 1,
		step = 0.05,
		isPercent = true,
		get = function()
			return W.FadeAmount('fadeBehindWalls', 0.4)
		end,
		set = function(_, value)
			W.SetFadeAmount('fadeBehindWalls', value)
		end,
		hidden = function()
			return type(Behavior('fadeBehindWalls')) ~= 'number'
		end,
	}
	args.rangeAmount = {
		type = 'range',
		name = L['How much plates fade out of range'],
		order = 23,
		advanced = true,
		min = 0,
		max = 1,
		step = 0.05,
		isPercent = true,
		get = function()
			return W.FadeAmount('rangeFade', 0.5)
		end,
		set = function(_, value)
			W.SetFadeAmount('rangeFade', value)
		end,
		hidden = function()
			return type(Behavior('rangeFade')) ~= 'number'
		end,
	}
	args.rangeYards = {
		type = 'range',
		name = L['Fade beyond this many yards'],
		order = 24,
		advanced = true,
		min = 10,
		max = 60,
		step = 5,
		get = function()
			return Behavior('rangeYards') or P.Driver.RANGE_YARDS
		end,
		set = function(_, value)
			SetBehavior('rangeYards', value ~= P.Driver.RANGE_YARDS and value or nil)
		end,
		hidden = function()
			return type(Behavior('rangeFade')) ~= 'number'
		end,
	}
	return { type = 'group', name = L['Plate behavior'], inline = true, order = 4, args = args }
end

local GAME_COLUMNS = { { 'label', 0.34 }, { 'was', 0.16 }, { 'now', 0.16 }, { 'by', 0.32 } }

local function GameGroup()
	local args = {}
	args.intro = {
		type = 'description',
		order = 1,
		name = function()
			if #W.GameRows() == 0 then
				return L['We have not changed any game settings.']
			end
			return L['These are the game settings we changed, or that someone else changed after us. You can put them all back.']
		end,
	}
	-- One flat table of text cells: a heading row, then four cells for each setting we changed. The
	-- flow layout wraps every four cells into a row, and a setting we have not touched has no cells.
	local titles = { label = L['Setting'], was = L['Was'], now = L['Now'], by = L['Changed by'] }
	local cells = {}
	for column, spec in ipairs(GAME_COLUMNS) do
		cells['head_' .. spec[1]] = Heading(titles[spec[1]], spec[2], column / 10)
	end
	for index, definition in ipairs(W.GameDefinitions()) do
		local name = definition.def.name
		for column, spec in ipairs(GAME_COLUMNS) do
			local field = spec[1]
			cells[name .. '_' .. field] = {
				type = 'description',
				order = 10 + index + column / 10,
				width = 'relative',
				relWidth = spec[2],
				name = function()
					local row = W.GameRow(name)
					return row and row[field] or ''
				end,
				hidden = function()
					return W.GameRow(name) == nil
				end,
			}
		end
	end
	args.table = {
		type = 'group',
		name = '',
		inline = true,
		order = 2,
		hidden = function()
			return #W.GameRows() == 0
		end,
		args = cells,
	}
	args.waiting = {
		type = 'description',
		order = 20,
		name = function()
			for _, entry in pairs(CVars.queue) do
				if not entry.restore then
					return L['Some settings take effect when combat ends.']
				end
			end
			return L['Some settings come back when combat ends.']
		end,
		hidden = function()
			return not CVars:HasQueued()
		end,
	}
	args.restore = {
		type = 'execute',
		name = L['Give the game back its settings'],
		desc = L['Puts back every game nameplate setting we changed. Some wait for combat to end. Your plate choices can change them again.'],
		order = 21,
		func = function()
			W.RestoreGame()
		end,
	}
	return { type = 'group', name = L['Game settings we change'], inline = true, order = 5, args = args }
end

local function PlacesGroup()
	local args = {
		intro = {
			type = 'description',
			order = 1,
			name = L['Pick different plate behavior in different places. Default uses the choices above.'],
		},
	}
	local head = { place = Heading(L['Place'], 0.16, 1) }
	for column, spec in ipairs(W.PLACE_COLUMNS) do
		head[spec.id] = Heading(spec.label, 0.16, column + 1)
	end
	args.head = { type = 'group', name = '', inline = true, order = 2, args = head }
	for rowIndex, row in ipairs(W.PLACE_ROWS) do
		local cells = { place = { type = 'description', name = row.label, fontSize = 'medium', width = 'relative', relWidth = 0.16, order = 1 } }
		for columnIndex, column in ipairs(W.PLACE_COLUMNS) do
			local choices = PLACE_CHOICES[column.choice]
			cells[column.id] = {
				type = 'select',
				name = '',
				desc = string.format(L['%s: %s'], row.label, column.label),
				order = columnIndex + 1,
				width = 'relative',
				relWidth = 0.16,
				values = choices.values,
				sorting = choices.order,
				get = function()
					return W.PlaceValue(row, column)
				end,
				set = function(_, value)
					W.SetPlaceValue(row, column, value)
				end,
				disabled = function()
					return column.key == 'stacking' and not FeatureOK('stacking')
				end,
			}
		end
		args[row.id] = { type = 'group', name = '', inline = true, order = 2 + rowIndex / 10, args = cells }
	end
	return { type = 'group', name = L['Place by place'], inline = true, order = 10, advanced = true, args = args }
end

local function AreasGroup()
	local function NotAdjustable()
		return not (W.AreasAdjustable())
	end
	local args = {
		note = {
			type = 'description',
			order = 1,
			name = L['Use the eye button above the preview to see the click area and the stacking area.'],
		},
		padding = {
			type = 'range',
			name = L['Extra click space'],
			desc = L['Makes the area you can click on each plate bigger, in pixels, on every side.'],
			order = 2,
			min = 0,
			max = 20,
			step = 1,
			get = W.ClickExtra,
			set = function(_, value)
				W.SetClickExtra(value)
			end,
			disabled = NotAdjustable,
		},
		reason = {
			type = 'description',
			order = 4,
			name = function()
				local _, reason = W.AreasAdjustable()
				return reason or ''
			end,
			hidden = function()
				return (W.AreasAdjustable())
			end,
		},
	}
	return { type = 'group', name = L['Click area'], inline = true, order = 11, advanced = true, args = args }
end

local function CopyGroup()
	local args = {
		target = {
			type = 'select',
			name = L['Plates to change'],
			order = 1,
			values = KIND_LABELS,
			sorting = Situation.KINDS,
			get = function()
				return W.copyTarget
			end,
			set = function(_, value)
				W.copyTarget = value
			end,
		},
		source = {
			type = 'select',
			name = L['Copy from'],
			desc = L['Copies the style, the Show choice and the changes made only for those plates.'],
			order = 2,
			values = KIND_LABELS,
			sorting = Situation.KINDS,
			get = function()
				return W.copySource
			end,
			set = function(_, value)
				W.copySource = value
			end,
		},
		copy = {
			type = 'execute',
			name = L['Copy'],
			order = 3,
			width = 0.6,
			func = function()
				W.CopyKind(W.copySource, W.copyTarget)
			end,
			disabled = function()
				return Locked() or W.copySource == W.copyTarget
			end,
		},
		reset = {
			type = 'execute',
			name = L['Reset these plates'],
			desc = L['Puts the plates picked in Plates to change back to the default style and Show choice.'],
			order = 4,
			confirm = true,
			confirmText = L['Put these plates back to the default style and Show choice? Changes made only for them are removed.'],
			func = function()
				W.ResetKind(W.copyTarget)
			end,
			disabled = Locked,
		},
	}
	return { type = 'group', name = L['Copy and reset'], inline = true, order = 12, advanced = true, args = args }
end

-- Another profile has another list: the editor must not point into it
P:On('PROFILE_CHANGED', function()
	W.editing = nil
end, W)

-- The game settings table follows what the Driver writes as places change
P:On('CVAR_CHANGED', function()
	Options:RequestRefresh(false)
end, W)

Options:AddPage('whoAndWhere', 5, function()
	return {
		type = 'group',
		name = L['Who and where'],
		args = {
			locked = {
				type = 'description',
				order = 0,
				name = W.LOCKED,
				hidden = function()
					return not Locked()
				end,
			},
			kinds = KindsGroup(),
			when = WhenGroup(),
			behavior = BehaviorGroup(),
			games = GameGroup(),
			places = PlacesGroup(),
			areas = AreasGroup(),
			copy = CopyGroup(),
		},
	}
end)
