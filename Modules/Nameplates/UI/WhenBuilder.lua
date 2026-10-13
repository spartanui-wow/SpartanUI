local _, ns = ...
local P = ns.Plates
local L = P.L

-- The "When" builder (plan 3.2 page 5 and 3.5): one component that edits a "When" entry
--
--   { conditions = { { id = 'place', args = 'raid' }, { id = 'role', args = 'tank', negate = false } },
--     kinds = { 'enemyNPC' },          -- nil covers every kind of plate
--     style = 'slim', size = 'small',  -- the layout actions (mode = 'name' | 'hidden' for the others)
--     off = true }                     -- switched off, kept in the list
--
-- Entries are what Situation.Assign reads (profile.when, first match wins). Every condition must
-- match (AND). The builder is shared: the Who and where page uses it for special cases, and later
-- stages use it for color rows and for the actions that change color, fade or glow.
--
-- What it offers comes from data and from the catalogs, not from the page:
--   * Conditions: P.Conditions is the catalog. CHOICES below gives the ones with an argument (a
--     place, a role) and the wording players see. Any other catalog condition without an argument
--     is offered by itself under its catalog label, so a condition registered later shows up here
--     with no change to this file. Conditions with a picker (spell lists, NPC lists) are offered
--     through CHOICES rows that name the picker (Phase 8); the editor adds the picker next to them.
--     A condition that cannot work on this client (cond.Unavailable) is shown grayed out with why.
--   * Actions: WhenBuilder:RegisterAction. An action says which Conditions:AllowedActions key it
--     needs, how it reads and writes its entry fields, how it is described and which controls it
--     adds. The editor lists only the actions every chosen condition allows on this client, and
--     says why when some are cut ("On this version of WoW, X can only change color or fade").
--   * Templates: WhenBuilder:RegisterTemplate adds starting points to the list's Add menu.
--   * Phase 8 registers the emphasis actions here (grow, paint, fade, glow, mark); their entries live
--     in profile.actions and Engine/Actions.lua draws them. Every rule that fits applies there.
--
-- Contexts: 'layout' (special cases: plain conditions only, because the layout never waits for an
-- answer the game hides) and 'emphasis' (conditions the engine decides, state conditions, and the
-- actions that only change color, alpha or glow).
--
-- Everything here is pure data work except WhenBuilder:Group, which builds an AceConfig group that
-- reads and writes the entry through opts.get / opts.set on every call (nothing is captured).

---@class Plates.WhenAction
---@field id string
---@field label string Menu text ("Use a style")
---@field order? number
---@field context? 'layout'|'emphasis' nil offers it in both
---@field needs? string Key of Conditions:AllowedActions the chosen conditions must allow (default: id)
---@field Active fun(entry: table): boolean
---@field Start fun(entry: table) Set the defaults when the player picks this action
---@field Clear fun(entry: table) Remove this action's fields
---@field Describe fun(entry: table): string Phrase inside a sentence ("use Slim")
---@field Short fun(entry: table): string Two or three words for a list row ("Slim")
---@field Controls? fun(ctx: table): table<string, table> AceConfig options for its values
---@field limits? table<string, string> Client name -> badge text
---@field Available? fun(conditions: table[], client: string): boolean Optional action capability check

---@class Plates.WhenTemplate
---@field id string
---@field label string
---@field order? number
---@field context? 'layout'|'emphasis'
---@field entry fun(): table A new entry

---@class Plates.WhenChoice
---@field key string 'place:raid', '!myCombat'
---@field id string Condition id
---@field args any
---@field negate? boolean
---@field label string Menu text ("In a raid")
---@field phrase string Inside a sentence ("in a raid")
---@field group 'when'|'plate'
---@field kind string Condition kind (plain, engine, identity)
---@field phase integer
---@field available boolean False when the situation does not happen on this client
---@field badge? string
---@field picker? 'spellList'|'npcList' The editor shows this picker next to the condition

---@class Plates.WhenBuilder
local WhenBuilder = {
	PHASE = 8, -- conditions with a later phase are not offered (the phase that adds their picker raises this)
	MAX_CONDITIONS = 4,
	actions = {},
	actionOrder = {},
	templates = {},
	templateOrder = {},
}
P.WhenBuilder = WhenBuilder

WhenBuilder.KIND_LABELS = {
	enemyNPC = L['Enemy NPCs'],
	enemyPlayer = L['Enemy players'],
	friendlyNPC = L['Friendly NPCs'],
	friendlyPlayer = L['Friendly players'],
	minor = L['Minor enemies'],
}

WhenBuilder.SIZE_LABELS = { small = L['Small'], medium = L['Medium'], large = L['Large'] }
WhenBuilder.SIZE_ORDER = { 'small', 'medium', 'large' }
local SIZE_WORDS = { small = L['small'], medium = L['medium'], large = L['large'] }

---Where each context draws its line: layout entries can only use conditions Situation.Assign can
---settle from plain facts; emphasis entries may use anything the catalog has.
WhenBuilder.CONTEXTS = {
	layout = { plainOnly = true, excludeStates = true },
	emphasis = { plainOnly = false, excludeStates = false },
}

-- States only change emphasis, never the layout (3.5)
local STATE_ONLY = { target = true, focus = true, mouseover = true, casting = true }

-- Clients a situation cannot happen on (client names from Caps:Client)
local NO_DELVES = { 'era', 'tbc', 'mists', 'titan' }
local NO_ARENAS = { 'era' }

local function Plate(row)
	row.group = 'plate'
	return row
end

-- Wording first, then the catalog decides what is real. Rows whose condition is missing from the
-- catalog are dropped when the list is built.
local CHOICES = {
	{ id = 'place', args = 'raid', label = L['In a raid'], phrase = L['in a raid'] },
	{ id = 'place', args = 'dungeon', label = L['In a dungeon'], phrase = L['in a dungeon'] },
	{ id = 'place', args = 'delve', label = L['In a delve'], phrase = L['in a delve'], notOn = NO_DELVES },
	{ id = 'place', args = 'pvp', label = L['In PvP'], phrase = L['in PvP'] },
	{ id = 'place', args = 'battleground', label = L['In a battleground'], phrase = L['in a battleground'] },
	{ id = 'place', args = 'arena', label = L['In an arena'], phrase = L['in an arena'], notOn = NO_ARENAS },
	{ id = 'place', args = 'instance', label = L['In any instance'], phrase = L['in an instance'] },
	{ id = 'place', args = 'world', label = L['Out in the world'], phrase = L['out in the world'] },
	{ id = 'myCombat', negate = true, label = L['Out of combat'], phrase = L['out of combat'] },
	{ id = 'myCombat', label = L['In combat'], phrase = L['in combat'] },
	{ id = 'resting', label = L['While resting'], phrase = L['while resting'] },
	{ id = 'resting', negate = true, label = L['Not resting'], phrase = L['when not resting'] },
	{ id = 'role', args = 'tank', label = L['As a tank'], phrase = L['as a tank'] },
	{ id = 'role', args = 'healer', label = L['As a healer'], phrase = L['as a healer'] },
	{ id = 'role', args = 'damage', label = L['As a damage dealer'], phrase = L['as a damage dealer'] },
	{ id = 'inGroup', label = L['In a group'], phrase = L['in a group'] },
	{ id = 'inGroup', negate = true, label = L['On my own'], phrase = L['on my own'] },
	{ id = 'challenge', label = L['During a Mythic+ run'], phrase = L['during a Mythic+ run'], notOn = NO_DELVES },

	Plate({ id = 'canAttack', label = L['Plate can be attacked'], phrase = L['plates you can attack'] }),
	Plate({ id = 'canAttack', negate = true, label = L['Plate cannot be attacked'], phrase = L['plates you cannot attack'] }),
	Plate({ id = 'elite', label = L['Plate is elite'], phrase = L['elite plates'] }),
	Plate({ id = 'rare', label = L['Plate is rare'], phrase = L['rare plates'] }),
	Plate({ id = 'mobType', args = 'boss', label = L['Plate is a boss'], phrase = L['boss plates'] }),
	Plate({ id = 'mobType', args = 'miniboss', label = L['Plate is a mini-boss'], phrase = L['mini-boss plates'] }),
	Plate({ id = 'mobType', args = 'caster', label = L['Plate is a caster'], phrase = L['caster plates'] }),
	Plate({ id = 'mobType', args = 'normal', label = L['Plate is a normal mob'], phrase = L['normal mob plates'] }),
	Plate({ id = 'mobType', args = 'minor', label = L['Plate is a minor mob'], phrase = L['minor mob plates'] }),
	Plate({ id = 'levelAbove', label = L['Plate is a higher level than you'], phrase = L['plates of a higher level than you'] }),
	Plate({ id = 'isPlayer', label = L['Plate is a player'], phrase = L['player plates'] }),
	Plate({ id = 'isNPC', label = L['Plate is an NPC'], phrase = L['NPC plates'] }),
	Plate({ id = 'minion', label = L['Plate is a pet, totem or minion'], phrase = L['pet, totem and minion plates'] }),
	Plate({ id = 'tapped', label = L['Plate was tagged by someone else'], phrase = L['plates someone else tagged'] }),
	Plate({ id = 'quest', label = L['Plate is a quest mob'], phrase = L['quest mob plates'] }),
	Plate({ id = 'reaction', args = 'hostile', label = L['Plate is hostile'], phrase = L['hostile plates'] }),
	Plate({ id = 'reaction', args = 'neutral', label = L['Plate is neutral'], phrase = L['neutral plates'] }),
	Plate({ id = 'reaction', args = 'friendly', label = L['Plate is friendly'], phrase = L['friendly plates'] }),

	-- Phase 8: what the "When" actions use. States and answers the game may keep are offered only in
	-- the emphasis context; Choices filters them out of special cases.
	Plate({ id = 'target', label = L['Plate is your target'], phrase = L['your target'] }),
	Plate({ id = 'target', negate = true, label = L['Plate is not your target'], phrase = L['plates that are not your target'] }),
	Plate({ id = 'focus', label = L['Plate is your focus'], phrase = L['your focus'] }),
	Plate({ id = 'mouseover', label = L['Plate is under your mouse'], phrase = L['the plate under your mouse'] }),
	Plate({ id = 'casting', label = L['Plate is casting'], phrase = L['plates that are casting'] }),
	Plate({ id = 'unitInCombat', label = L['Enemy is fighting'], phrase = L['enemies that are fighting'] }),
	Plate({ id = 'unitInCombat', negate = true, label = L['Enemy is not fighting'], phrase = L['enemies that are not fighting'] }),
	Plate({ id = 'lowHealth', args = 20, label = L['Health is below 20%'], phrase = L['plates below 20% health'] }),
	Plate({ id = 'lowHealth', args = 35, label = L['Health is below 35%'], phrase = L['plates below 35% health'] }),
	Plate({ id = 'lowHealth', args = 50, label = L['Health is below half'], phrase = L['plates below half health'] }),
	Plate({ id = 'totem', label = L['Plate is a totem'], phrase = L['totem plates'] }),
	Plate({ id = 'auraPresent', picker = 'spellList', label = L['Has a spell I pick'], phrase = L['plates with a spell you picked'] }),
	Plate({ id = 'auraMissing', picker = 'spellList', label = L['My debuff is missing'], phrase = L['plates missing your debuff'] }),
	Plate({ id = 'castSpell', picker = 'spellList', label = L['Casting a spell I pick'], phrase = L['plates casting a spell you picked'] }),
	Plate({ id = 'npcID', picker = 'npcList', label = L['Is an NPC I pick'], phrase = L['NPCs you picked'] }),
}

-- Conditions where two different arguments can never both be true
local EXCLUSIVE = { place = true, role = true, mobType = true, reaction = true }
local BROAD_PLACES = { instance = true, pvp = true }

local function PlaceMatches(place, wanted)
	if wanted == 'instance' then
		return place ~= 'world'
	elseif wanted == 'pvp' then
		return place == 'arena' or place == 'battleground'
	end
	return place == wanted
end

----------------------------------------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------------------------------------

local function ClauseKey(id, args, negate)
	local key = id
	if args ~= nil and type(args) ~= 'table' then
		key = key .. ':' .. tostring(args)
	end
	if negate then
		key = '!' .. key
	end
	return key
end

---Key of a stored condition ('place:raid', '!myCombat').
---@param clause table { id, args?, negate? }
---@return string
function WhenBuilder:KeyOf(clause)
	return ClauseKey(clause.id, clause.args, clause.negate)
end

local function Cap(text)
	return (string.gsub(text, '^%l', string.upper))
end

local function Join(list)
	return table.concat(list, ' ' .. L['and'] .. ' ')
end

local function Contains(list, value)
	for i = 1, #(list or {}) do
		if list[i] == value then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------------------------------------
-- Conditions
----------------------------------------------------------------------------------------------------

local function BuildAll(self)
	local Conditions, client = P.Conditions, P.Caps:Client()
	local list, byKey, covered = {}, {}, {}
	local function Add(row)
		local cond = Conditions:Get(row.id)
		if not cond then
			return
		end
		local key = ClauseKey(row.id, row.args, row.negate)
		if byKey[key] then
			return
		end
		local choice = {
			key = key,
			id = row.id,
			args = row.args,
			negate = row.negate or nil,
			label = row.label,
			phrase = row.phrase,
			group = row.group or 'when',
			kind = cond.kind,
			phase = cond.phase or 0,
			available = true,
			picker = row.picker,
		}
		if Contains(row.notOn, client) then
			choice.available = false
			choice.badge = L['Does not happen on this version of WoW']
		end
		local reason = cond.Unavailable and cond.Unavailable()
		if type(reason) == 'string' then
			choice.available = false
			choice.badge = L['Not on this version of WoW']
			choice.reason = reason
		end
		local limit = cond.limits and cond.limits[client]
		if type(limit) == 'string' then
			choice.badge = limit
		end
		list[#list + 1] = choice
		byKey[key] = choice
	end
	for _, row in ipairs(CHOICES) do
		covered[row.id] = true
		Add(row)
	end
	-- Anything else in the catalog that needs no argument is offered under its own label
	for _, id in ipairs(Conditions.order) do
		local cond = Conditions:Get(id)
		if cond and not covered[id] and cond.argType == nil then
			local label = cond.label or id
			Add({ id = id, label = label, phrase = string.lower(label), group = (cond.facts and #cond.facts > 0) and 'plate' or 'when' })
		end
	end
	return list, byKey
end

---Every choice the catalog and the wording tables give, whatever the context.
---@return Plates.WhenChoice[] list
---@return table<string, Plates.WhenChoice> byKey
function WhenBuilder:All()
	local signature = #P.Conditions.order .. '|' .. P.Caps:Client()
	local changed = not self.allList or self.allSignature ~= signature
	for index, id in ipairs(P.Conditions.order) do
		if not self.allCatalog or self.allCatalog[index] ~= P.Conditions:Get(id) then
			changed = true
			break
		end
	end
	if changed then
		self.allList, self.allByKey = BuildAll(self)
		self.allSignature = signature
		self.allCatalog = {}
		for index, id in ipairs(P.Conditions.order) do
			self.allCatalog[index] = P.Conditions:Get(id)
		end
	end
	return self.allList, self.allByKey
end

---Choices offered in a context, in menu order.
---@param context? 'layout'|'emphasis'
---@return Plates.WhenChoice[]
function WhenBuilder:Choices(context)
	local rules = self.CONTEXTS[context or 'layout'] or self.CONTEXTS.layout
	local out = {}
	for _, choice in ipairs((self:All())) do
		local offered = choice.phase <= self.PHASE
		if rules.plainOnly and choice.kind ~= 'plain' then
			offered = false
		end
		if rules.excludeStates and STATE_ONLY[choice.id] then
			offered = false
		end
		if offered then
			out[#out + 1] = choice
		end
	end
	return out
end

---The choice a stored condition stands for. A condition the catalog no longer has (or a choice the
---wording tables do not know) still gets a readable one, marked unavailable when it is gone.
---@param clause table
---@return Plates.WhenChoice
function WhenBuilder:ChoiceFor(clause)
	local _, byKey = self:All()
	local key = self:KeyOf(clause)
	if byKey[key] then
		return byKey[key]
	end
	local cond = P.Conditions:Get(clause.id)
	local label = cond and cond.label or tostring(clause.id)
	if clause.args ~= nil and type(clause.args) ~= 'table' then
		label = label .. ' ' .. tostring(clause.args)
	end
	if clause.negate then
		label = string.format(L['Not: %s'], label)
	end
	return {
		key = key,
		id = clause.id,
		args = clause.args,
		negate = clause.negate,
		label = label,
		phrase = string.lower(label),
		group = 'when',
		kind = cond and cond.kind or 'plain',
		phase = cond and cond.phase or 0,
		available = cond ~= nil,
	}
end

---A new stored condition for a choice key, or nil.
---@param key string
---@return table|nil clause
function WhenBuilder:ClauseForKey(key)
	local _, byKey = self:All()
	local choice = byKey[key]
	if not choice then
		return nil
	end
	return { id = choice.id, args = choice.args, negate = choice.negate }
end

----------------------------------------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------------------------------------

---Register an action (or replace one with the same id).
---@param def Plates.WhenAction
function WhenBuilder:RegisterAction(def)
	assert(type(def) == 'table' and def.id and def.Active and def.Start and def.Clear and def.Describe, 'RegisterAction needs id, Active, Start, Clear and Describe')
	if not self.actions[def.id] then
		self.actionOrder[#self.actionOrder + 1] = def.id
	end
	self.actions[def.id] = def
	table.sort(self.actionOrder, function(a, b)
		local oa, ob = self.actions[a].order or 100, self.actions[b].order or 100
		if oa ~= ob then
			return oa < ob
		end
		return a < b
	end)
end

local function InContext(def, context)
	return context == nil or def.context == nil or def.context == context
end

---Registered actions of a context, in menu order.
---@param context? 'layout'|'emphasis'
---@return Plates.WhenAction[]
function WhenBuilder:ActionList(context)
	local out = {}
	for _, id in ipairs(self.actionOrder) do
		local def = self.actions[id]
		if InContext(def, context) then
			out[#out + 1] = def
		end
	end
	return out
end

---The action an entry carries (the first registered one that finds its fields), or nil.
---@param entry table
---@param context? 'layout'|'emphasis'
---@return Plates.WhenAction|nil
function WhenBuilder:ActionOf(entry, context)
	for _, def in ipairs(self:ActionList(context)) do
		if def.Active(entry) then
			return def
		end
	end
	return nil
end

---Actions the chosen conditions allow on this client (a set of Conditions:AllowedActions keys).
---@param conditions? table[]
---@return table<string, boolean>
function WhenBuilder:AllowedSet(conditions)
	local allowed
	for _, clause in ipairs(conditions or {}) do
		local set = P.Conditions:AllowedActions(clause.id)
		if allowed == nil then
			allowed = {}
			for key in pairs(set) do
				allowed[key] = true
			end
		else
			for key in pairs(allowed) do
				if not set[key] then
					allowed[key] = nil
				end
			end
		end
	end
	if allowed then
		return allowed
	end
	local all = {}
	for _, key in ipairs(P.Conditions.ACTION_KEYS) do
		all[key] = true
	end
	return all
end

---Actions that can work for these conditions here, in menu order. Only these are offered.
---@param context? 'layout'|'emphasis'
---@param conditions? table[]
---@return Plates.WhenAction[]
function WhenBuilder:Actions(context, conditions)
	local rules = self.CONTEXTS[context or 'layout'] or self.CONTEXTS.layout
	for _, clause in ipairs(conditions or {}) do
		local choice = self:ChoiceFor(clause)
		if not choice.available or choice.phase > self.PHASE or (rules.plainOnly and choice.kind ~= 'plain') or (rules.excludeStates and STATE_ONLY[clause.id]) then
			return {}
		end
	end
	local allowed = self:AllowedSet(conditions)
	local out = {}
	for _, def in ipairs(self:ActionList(context)) do
		if allowed[def.needs or def.id] and (not def.Available or def.Available(conditions or {}, P.Caps:Client())) then
			out[#out + 1] = def
		end
	end
	return out
end

---Switch an entry to another action: the old action's fields go, the new one's defaults arrive.
---@param entry table Changed in place
---@param id string
---@param context? 'layout'|'emphasis'
---@return table entry
function WhenBuilder:SetAction(entry, id, context)
	local def
	for _, offered in ipairs(self:Actions(context, entry.conditions)) do
		if offered.id == id then
			def = offered
			break
		end
	end
	if not def then
		return entry
	end
	local current = self:ActionOf(entry, context)
	if current and current.id == id then
		return entry
	end
	if current then
		current.Clear(entry)
	end
	def.Start(entry)
	return entry
end

----------------------------------------------------------------------------------------------------
-- Styles for the style pickers
----------------------------------------------------------------------------------------------------

---Display name of a style id ('host' is the style that matches the host's look).
---@param id string|nil
---@return string
function WhenBuilder.StyleName(id)
	local Registry = P.Styles.Registry
	local style = Registry:Get(Registry:ResolveId(id))
	return style and style.name or tostring(id)
end

---Style choices for a dropdown: values (id -> name) and their order. 'host' stands for the style
---that matches the host's look. The names-only style is a Show choice, not a style, so it is left out;
---the current value is always present.
---@param current? string
---@return table<string, string> values
---@return string[] order
function WhenBuilder:StyleValues(current)
	local values, order = {}, {}
	for _, item in ipairs(P.Styles.Registry:List(true)) do
		if item.id ~= P.Situation.NAME_STYLE then
			local value = item.matchesHost and 'host' or item.id
			values[value] = item.name
			order[#order + 1] = value
		end
	end
	if current and values[current] == nil then
		values[current] = current == 'host' and L['Match my look'] or WhenBuilder.StyleName(current)
		order[#order + 1] = current
	end
	return values, order
end

----------------------------------------------------------------------------------------------------
-- The layout actions (the ones Situation.Assign understands)
----------------------------------------------------------------------------------------------------

local function ClearLayout(entry)
	entry.style = nil
	entry.size = nil
	entry.mode = nil
end

WhenBuilder:RegisterAction({
	id = 'style',
	label = L['Use a style'],
	order = 10,
	context = 'layout',
	needs = 'style',
	Active = function(entry)
		return entry.style ~= nil and entry.mode == nil
	end,
	Start = function(entry)
		ClearLayout(entry)
		entry.style = P.Store:Get('style') or 'host'
	end,
	Clear = ClearLayout,
	Describe = function(entry)
		local name = WhenBuilder.StyleName(entry.style)
		if entry.size then
			return string.format(L['use %s at %s size'], name, SIZE_WORDS[entry.size] or tostring(entry.size))
		end
		return string.format(L['use %s'], name)
	end,
	Short = function(entry)
		local name = WhenBuilder.StyleName(entry.style)
		if entry.size then
			return string.format(L['%s, %s'], name, SIZE_WORDS[entry.size] or tostring(entry.size))
		end
		return name
	end,
	Controls = function(ctx)
		return {
			style = {
				type = 'select',
				name = L['Style'],
				order = 1,
				width = 1.2,
				values = function()
					local entry = ctx.get()
					return (WhenBuilder:StyleValues(entry and entry.style))
				end,
				sorting = function()
					local entry = ctx.get()
					local _, order = WhenBuilder:StyleValues(entry and entry.style)
					return order
				end,
				get = function()
					local entry = ctx.get()
					return entry and entry.style
				end,
				set = function(_, value)
					ctx.update(function(entry)
						entry.style = value
					end)
				end,
			},
			size = {
				type = 'select',
				name = L['Size'],
				desc = L['Plates get bigger or smaller in whole pixels.'],
				order = 2,
				width = 0.9,
				values = {
					keep = L['My usual size'],
					small = WhenBuilder.SIZE_LABELS.small,
					medium = WhenBuilder.SIZE_LABELS.medium,
					large = WhenBuilder.SIZE_LABELS.large,
				},
				sorting = { 'keep', 'small', 'medium', 'large' },
				get = function()
					local entry = ctx.get()
					return entry and entry.size or 'keep'
				end,
				set = function(_, value)
					ctx.update(function(entry)
						entry.size = value ~= 'keep' and value or nil
					end)
				end,
			},
		}
	end,
})

WhenBuilder:RegisterAction({
	id = 'size',
	label = L['Change the size'],
	order = 20,
	context = 'layout',
	needs = 'size',
	Active = function(entry)
		return entry.size ~= nil and entry.style == nil and entry.mode == nil
	end,
	Start = function(entry)
		ClearLayout(entry)
		entry.size = 'small'
	end,
	Clear = ClearLayout,
	Describe = function(entry)
		return string.format(L['use %s size'], SIZE_WORDS[entry.size] or tostring(entry.size))
	end,
	Short = function(entry)
		return string.format(L['%s size'], WhenBuilder.SIZE_LABELS[entry.size] or tostring(entry.size))
	end,
	Controls = function(ctx)
		return {
			size = {
				type = 'select',
				name = L['Size'],
				desc = L['Plates get bigger or smaller in whole pixels.'],
				order = 1,
				width = 0.9,
				values = WhenBuilder.SIZE_LABELS,
				sorting = WhenBuilder.SIZE_ORDER,
				get = function()
					local entry = ctx.get()
					return entry and entry.size
				end,
				set = function(_, value)
					ctx.update(function(entry)
						entry.size = value
					end)
				end,
			},
		}
	end,
})

WhenBuilder:RegisterAction({
	id = 'name',
	label = L['Show names only'],
	order = 30,
	context = 'layout',
	needs = 'name',
	Active = function(entry)
		return entry.mode == 'name'
	end,
	Start = function(entry)
		ClearLayout(entry)
		entry.mode = 'name'
	end,
	Clear = ClearLayout,
	Describe = function()
		return L['show names only']
	end,
	Short = function()
		return L['Names only']
	end,
})

WhenBuilder:RegisterAction({
	id = 'hide',
	label = L['Hide the plate'],
	order = 40,
	context = 'layout',
	needs = 'hide',
	Active = function(entry)
		return entry.mode == 'hidden'
	end,
	Start = function(entry)
		ClearLayout(entry)
		entry.mode = 'hidden'
	end,
	Clear = ClearLayout,
	Describe = function()
		return L['hide the plate']
	end,
	Short = function()
		return L['Hidden']
	end,
})

----------------------------------------------------------------------------------------------------
-- The emphasis actions (Phase 8): profile.actions, drawn by Engine/Actions.lua
----------------------------------------------------------------------------------------------------

local EFFECTS = P.Actions and P.Actions.EFFECTS or {}

local function ClearEffects(entry)
	for _, def in pairs(EFFECTS) do
		for field in pairs(def.fields) do
			entry[field] = nil
		end
	end
end

local function ColorControl(ctx, name, field, order, advanced)
	return {
		type = 'color',
		name = name,
		order = order,
		hasAlpha = true,
		advanced = advanced,
		get = function()
			local entry = ctx.get()
			local c = entry and entry[field] or { 1, 1, 1, 1 }
			return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
		end,
		set = function(_, r, g, b, a)
			ctx.update(function(entry)
				entry[field] = { r, g, b, a or 1 }
			end)
		end,
	}
end

local function Effect(id)
	return EFFECTS[id] or {
		Active = function()
			return false
		end,
	}
end

WhenBuilder:RegisterAction({
	id = 'grow',
	label = L['Make it bigger'],
	order = 110,
	context = 'emphasis',
	needs = 'grow',
	Active = function(entry)
		return Effect('grow').Active(entry)
	end,
	Start = function(entry)
		ClearEffects(entry)
		entry.grow = { 20, 4 }
	end,
	Clear = ClearEffects,
	Describe = function(entry)
		local g = entry.grow or { 0, 0 }
		return string.format(L['make it %d pixels wider and %d taller'], g[1] or 0, g[2] or 0)
	end,
	Short = function(entry)
		local g = entry.grow or { 0, 0 }
		return string.format(L['Bigger by %d'], g[1] or 0)
	end,
	Controls = function(ctx)
		local function Slider(name, index, order)
			return {
				type = 'range',
				name = name,
				desc = L['Plates grow in whole pixels, so edges stay sharp. Use a number below 0 to make them smaller.'],
				order = order,
				min = P.Actions and P.Actions.GROW_MIN or -40,
				max = P.Actions and P.Actions.GROW_MAX or 60,
				step = 1,
				get = function()
					local entry = ctx.get()
					return entry and entry.grow and entry.grow[index] or 0
				end,
				set = function(_, value)
					ctx.update(function(entry)
						entry.grow = entry.grow or { 0, 0 }
						entry.grow[index] = math.floor(value + 0.5)
					end)
				end,
			}
		end
		return { width = Slider(L['Wider by'], 1, 1), height = Slider(L['Taller by'], 2, 2) }
	end,
})

WhenBuilder:RegisterAction({
	id = 'paint',
	label = L['Change a color'],
	order = 120,
	context = 'emphasis',
	needs = 'color',
	Active = function(entry)
		return Effect('paint').Active(entry)
	end,
	Start = function(entry)
		ClearEffects(entry)
		entry.paint = 'health'
		entry.color = { 1, 0.5, 0.1, 1 }
	end,
	Clear = ClearEffects,
	Describe = function(entry)
		local labels = P.Actions and P.Actions.PIECE_LABELS or {}
		return string.format(L['color the %s'], string.lower(labels[entry.paint] or tostring(entry.paint)))
	end,
	Short = function(entry)
		local labels = P.Actions and P.Actions.PIECE_LABELS or {}
		return string.format(L['%s color'], labels[entry.paint] or tostring(entry.paint))
	end,
	Controls = function(ctx)
		return {
			piece = {
				type = 'select',
				name = L['Color this'],
				order = 1,
				values = P.Actions and P.Actions.PIECE_LABELS or {},
				sorting = P.Actions and P.Actions.PIECES or {},
				get = function()
					local entry = ctx.get()
					return entry and entry.paint
				end,
				set = function(_, value)
					ctx.update(function(entry)
						entry.paint = value
					end)
				end,
			},
			color = ColorControl(ctx, L['Color'], 'color', 2),
		}
	end,
})

WhenBuilder:RegisterAction({
	id = 'fade',
	label = L['Fade the plate'],
	order = 130,
	context = 'emphasis',
	needs = 'alpha',
	Active = function(entry)
		return Effect('fade').Active(entry)
	end,
	Start = function(entry)
		ClearEffects(entry)
		entry.fade = 0.4
	end,
	Clear = ClearEffects,
	Describe = function(entry)
		return string.format(L['fade it to %d%%'], math.floor((entry.fade or 1) * 100 + 0.5))
	end,
	Short = function(entry)
		return string.format(L['Faded to %d%%'], math.floor((entry.fade or 1) * 100 + 0.5))
	end,
	Controls = function(ctx)
		return {
			fade = {
				type = 'range',
				name = L['How much shows'],
				desc = L['0% hides the picture, 100% shows it fully. You can still click a faded plate.'],
				order = 1,
				min = 0,
				max = 1,
				step = 0.05,
				isPercent = true,
				get = function()
					local entry = ctx.get()
					return entry and entry.fade or 1
				end,
				set = function(_, value)
					ctx.update(function(entry)
						entry.fade = value
					end)
				end,
			},
		}
	end,
})

WhenBuilder:RegisterAction({
	id = 'glow',
	label = L['Make it glow'],
	order = 140,
	context = 'emphasis',
	needs = 'glow',
	Active = function(entry)
		return Effect('glow').Active(entry)
	end,
	Start = function(entry)
		ClearEffects(entry)
		entry.glow = { 1, 0.6, 0.1, 1 }
	end,
	Clear = ClearEffects,
	Describe = function()
		return L['make it glow']
	end,
	Short = function()
		return L['Glow']
	end,
	Controls = function(ctx)
		return { glow = ColorControl(ctx, L['Glow color'], 'glow', 1) }
	end,
})

WhenBuilder:RegisterAction({
	id = 'mark',
	label = L['Show a mark'],
	order = 150,
	context = 'emphasis',
	needs = 'mark',
	Active = function(entry)
		return Effect('mark').Active(entry)
	end,
	Start = function(entry)
		ClearEffects(entry)
		entry.mark = 'star'
	end,
	Clear = ClearEffects,
	Describe = function(entry)
		local labels = P.Actions and P.Actions.MARK_LABELS or {}
		return string.format(L['show a %s above it'], string.lower(labels[entry.mark] or tostring(entry.mark)))
	end,
	Short = function(entry)
		local labels = P.Actions and P.Actions.MARK_LABELS or {}
		return string.format(L['%s mark'], labels[entry.mark] or tostring(entry.mark))
	end,
	Controls = function(ctx)
		return {
			mark = {
				type = 'select',
				name = L['Mark'],
				order = 1,
				values = P.Actions and P.Actions.MARK_LABELS or {},
				sorting = P.Actions and P.Actions.MARK_ORDER or {},
				get = function()
					local entry = ctx.get()
					return entry and entry.mark
				end,
				set = function(_, value)
					ctx.update(function(entry)
						entry.mark = value
					end)
				end,
			},
			markColor = ColorControl(ctx, L['Mark color'], 'markColor', 2, true),
		}
	end,
})

----------------------------------------------------------------------------------------------------
-- Templates (starting points in the list's Add menu)
----------------------------------------------------------------------------------------------------

---@param def Plates.WhenTemplate
function WhenBuilder:RegisterTemplate(def)
	assert(type(def) == 'table' and def.id and def.entry, 'RegisterTemplate needs id and entry')
	if not self.templates[def.id] then
		self.templateOrder[#self.templateOrder + 1] = def.id
	end
	self.templates[def.id] = def
	table.sort(self.templateOrder, function(a, b)
		local oa, ob = self.templates[a].order or 100, self.templates[b].order or 100
		if oa ~= ob then
			return oa < ob
		end
		return a < b
	end)
end

---@param context? 'layout'|'emphasis'
---@return Plates.WhenTemplate[]
function WhenBuilder:Templates(context)
	local out = {}
	for _, id in ipairs(self.templateOrder) do
		local def = self.templates[id]
		if InContext(def, context) then
			out[#out + 1] = def
		end
	end
	return out
end

---A new entry from a template, or nil for an unknown id.
---@param id string
---@return table|nil entry
function WhenBuilder:NewEntry(id)
	local def = self.templates[id]
	if not def then
		return nil
	end
	return P.util.Copy(def.entry())
end

WhenBuilder:RegisterTemplate({
	id = 'raidSmall',
	label = L['Smaller plates in raids'],
	order = 10,
	context = 'layout',
	entry = function()
		return { conditions = { { id = 'place', args = 'raid' } }, size = 'small' }
	end,
})
WhenBuilder:RegisterTemplate({
	id = 'raidMinor',
	label = L['Hide minor enemies in raids'],
	order = 20,
	context = 'layout',
	entry = function()
		return { conditions = { { id = 'place', args = 'raid' } }, kinds = { 'minor' }, mode = 'hidden' }
	end,
})
WhenBuilder:RegisterTemplate({
	id = 'battlegroundNames',
	label = L['Names only in battlegrounds'],
	order = 30,
	context = 'layout',
	entry = function()
		return { conditions = { { id = 'place', args = 'battleground' } }, mode = 'name' }
	end,
})
WhenBuilder:RegisterTemplate({
	id = 'tankLarge',
	label = L['Larger plates when I tank'],
	order = 40,
	context = 'layout',
	entry = function()
		return { conditions = { { id = 'role', args = 'tank' } }, size = 'large' }
	end,
})
WhenBuilder:RegisterTemplate({
	id = 'blank',
	label = L['Start from scratch'],
	order = 90,
	context = 'layout',
	-- Changes nothing until the player edits it: it picks the style the plates already use
	entry = function()
		return { conditions = { { id = 'place', args = 'dungeon' } }, style = P.Store:Get('style') or 'host' }
	end,
})

WhenBuilder:RegisterTemplate({
	id = 'casters',
	label = L['Make casters stand out'],
	order = 110,
	context = 'emphasis',
	entry = function()
		return { conditions = { { id = 'casting' } }, kinds = { 'enemyNPC', 'enemyPlayer' }, glow = { 1, 0.6, 0.1, 1 } }
	end,
})
WhenBuilder:RegisterTemplate({
	id = 'notFighting',
	label = L["Fade enemies I'm not fighting"],
	order = 120,
	context = 'emphasis',
	entry = function()
		return { conditions = { { id = 'unitInCombat', negate = true } }, kinds = { 'enemyNPC', 'minor' }, fade = 0.4 }
	end,
})
WhenBuilder:RegisterTemplate({
	id = 'focusBig',
	label = L['Big plate for my focus'],
	order = 130,
	context = 'emphasis',
	entry = function()
		return { conditions = { { id = 'focus' } }, grow = { 24, 4 } }
	end,
})
WhenBuilder:RegisterTemplate({
	id = 'lowHealthWarn',
	label = L['Warn when low on health'],
	order = 140,
	context = 'emphasis',
	entry = function()
		return { conditions = { { id = 'lowHealth', args = 35 } }, kinds = { 'enemyNPC', 'enemyPlayer' }, paint = 'health', color = { 1, 0.85, 0.1, 1 } }
	end,
})
WhenBuilder:RegisterTemplate({
	id = 'totems',
	label = L['Mark totems'],
	order = 150,
	context = 'emphasis',
	entry = function()
		return { conditions = { { id = 'totem' } }, mark = 'triangle', markColor = { 0.4, 1, 0.4, 1 } }
	end,
})
WhenBuilder:RegisterTemplate({
	id = 'blankAction',
	label = L['Start from scratch'],
	order = 190,
	context = 'emphasis',
	entry = function()
		return { conditions = { { id = 'target' } }, glow = { 1, 1, 1, 1 } }
	end,
})

----------------------------------------------------------------------------------------------------
-- Words
----------------------------------------------------------------------------------------------------

---Names of the kinds an entry covers ("Enemy NPCs and Minor enemies"), or nil when it covers all.
---@param kinds? string[]
---@return string|nil
function WhenBuilder:KindsText(kinds)
	if type(kinds) ~= 'table' then
		return nil
	end
	local names = {}
	for _, kind in ipairs(P.Situation.KINDS) do
		if Contains(kinds, kind) then
			names[#names + 1] = self.KIND_LABELS[kind]
		end
	end
	if #names == 0 or #names == #P.Situation.KINDS then
		return nil
	end
	return Join(names)
end

---The "if" half of a sentence: "In a raid and as a tank, for elite plates - Enemy NPCs only".
---@param entry table
---@return string
function WhenBuilder:Sentence(entry)
	local whenParts, plateParts = {}, {}
	for _, clause in ipairs(entry.conditions or {}) do
		local choice = self:ChoiceFor(clause)
		local list = choice.group == 'plate' and plateParts or whenParts
		list[#list + 1] = choice.phrase
	end
	local text
	if #whenParts > 0 then
		text = Cap(Join(whenParts))
	end
	if #plateParts > 0 then
		local plates = string.format(L['for %s'], Join(plateParts))
		text = text and (text .. ', ' .. plates) or Cap(plates)
	end
	text = text or L['Always']
	local kinds = self:KindsText(entry.kinds)
	if kinds then
		text = text .. ' - ' .. string.format(L['%s only'], kinds)
	end
	return text
end

---What the entry does, as a phrase ("use Slim at small size"), or nil while no action is picked.
---@param entry table
---@param context? 'layout'|'emphasis'
---@return string|nil
function WhenBuilder:ActionText(entry, context)
	local def = self:ActionOf(entry, context)
	return def and def.Describe(entry) or nil
end

---Two or three words for a list row ("Slim", "Hidden"), or a dash.
---@param entry table
---@param context? 'layout'|'emphasis'
---@return string
function WhenBuilder:Short(entry, context)
	local def = self:ActionOf(entry, context)
	return def and def.Short and def.Short(entry) or '-'
end

---The whole entry in one sentence.
---@param entry table
---@param context? 'layout'|'emphasis'
---@return string
function WhenBuilder:Describe(entry, context)
	local action = self:ActionText(entry, context) or L['nothing yet']
	return self:Sentence(entry) .. ': ' .. action
end

---A line about client limits for the chosen conditions, or nil. Conditions the engine decides can
---only change color, fade or glow on clients where the game hides unit values.
---@param conditions? table[]
---@return string|nil
function WhenBuilder:Badge(conditions)
	local Conditions, client = P.Conditions, P.Caps:Client()
	local lines = {}
	for _, clause in ipairs(conditions or {}) do
		local cond = Conditions:Get(clause.id)
		if cond then
			local choice = self:ChoiceFor(clause)
			local limit = cond.limits and cond.limits[client]
			if type(limit) == 'string' then
				lines[#lines + 1] = limit
			end
			if cond.kind ~= 'plain' then
				if P.Caps:Get('secrets') then
					lines[#lines + 1] = string.format(L['On this version of WoW, "%s" can only change color or fade.'], choice.label)
				else
					lines[#lines + 1] = string.format(L['On Retail and Forever, "%s" can only change color or fade.'], choice.label)
				end
			end
		end
	end
	if #lines == 0 then
		return nil
	end
	return table.concat(lines, ' ')
end

---@param entry table
---@param context? string
---@return string|nil
function WhenBuilder:EntryBadge(entry, context)
	local conditionBadge = self:Badge(entry.conditions)
	local action = self:ActionOf(entry, context)
	local actionBadge = action and action.limits and action.limits[P.Caps:Client()]
	if type(actionBadge) ~= 'string' then
		return conditionBadge
	end
	return conditionBadge and (conditionBadge .. ' ' .. actionBadge) or actionBadge
end

---Plain sentences about what is wrong with an entry on this client (empty when it is fine).
---@param entry table
---@param context? 'layout'|'emphasis'
---@return string[]
function WhenBuilder:Problems(entry, context)
	local out = {}
	local Conditions = P.Conditions
	local action = self:ActionOf(entry, context)
	if not action then
		out[#out + 1] = L['Pick what should happen.']
	else
		local allowed = false
		for _, offered in ipairs(self:Actions(context, entry.conditions)) do
			if offered.id == action.id then
				allowed = true
				break
			end
		end
		if not allowed then
			out[#out + 1] = L['These conditions cannot do that on this version of WoW.']
		end
	end
	local rules = self.CONTEXTS[context or 'layout'] or self.CONTEXTS.layout
	local seen, clauses, places = {}, {}, {}
	for _, place in ipairs(P.Situation.PLACES) do
		places[place] = true
	end
	local hasPlace, contradiction = false, false
	for _, clause in ipairs(entry.conditions or {}) do
		local cond = Conditions:Get(clause.id)
		local choice = self:ChoiceFor(clause)
		if not cond then
			out[#out + 1] = L['A condition in this special case no longer exists.']
		else
			if not choice.available then
				out[#out + 1] = string.format(L['"%s" does not happen on this version of WoW.'], choice.label)
			end
			if (rules.plainOnly and cond.kind ~= 'plain') or (rules.excludeStates and STATE_ONLY[clause.id]) then
				out[#out + 1] = string.format(L['"%s" cannot change how plates look.'], choice.label)
			end
		end
		if clauses[ClauseKey(clause.id, clause.args, not clause.negate)] then
			contradiction = true
		end
		clauses[self:KeyOf(clause)] = true
		if clause.id == 'place' then
			hasPlace = true
			for place in pairs(places) do
				local matches = PlaceMatches(place, clause.args)
				if (clause.negate and matches) or (not clause.negate and not matches) then
					places[place] = nil
				end
			end
		end
		if EXCLUSIVE[clause.id] and not clause.negate and not (clause.id == 'place' and BROAD_PLACES[clause.args]) then
			local before = seen[clause.id]
			if before ~= nil and before ~= clause.args then
				contradiction = true
			end
			seen[clause.id] = clause.args
		end
	end
	if contradiction or (hasPlace and next(places) == nil) then
		out[#out + 1] = L['These conditions can never be true together.']
	end
	if type(entry.kinds) == 'table' and #entry.kinds == 0 then
		out[#out + 1] = L['No kinds of plates are picked.']
	end
	for _, clause in ipairs(entry.conditions or {}) do
		local choice = self:ChoiceFor(clause)
		if choice.reason then
			out[#out + 1] = choice.reason
		end
		if choice.picker == 'spellList' and (type(clause.args) ~= 'table' or next(clause.args) == nil) then
			out[#out + 1] = string.format(L['Pick at least one spell for "%s".'], choice.label)
		elseif choice.picker == 'npcList' and (type(clause.args) ~= 'table' or next(clause.args) == nil) then
			out[#out + 1] = string.format(L['Type at least one NPC ID for "%s".'], choice.label)
		end
	end
	if action and P.Caps:Get('secrets') then
		local hidden = 0
		for _, clause in ipairs(entry.conditions or {}) do
			local cond = Conditions:Get(clause.id)
			if cond and cond.kind == 'engine' then
				hidden = hidden + 1
				if cond.curve and (action.needs == 'alpha' or action.needs == 'glow' or (action.needs == 'color' and entry.paint == 'name')) then
					out[#out + 1] = L['On this version of WoW, low health can only tint the health bar or border, or show a mark.']
				end
			end
		end
		if hidden > 1 and (action.needs == 'alpha' or action.needs == 'glow') then
			out[#out + 1] = L['On this version of WoW, fading or a glow can only wait for one condition the game decides. Remove one.']
		end
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- The editor (an AceConfig group)
----------------------------------------------------------------------------------------------------

---@class Plates.WhenGroupOptions
---@field get fun(): table|nil A copy of the entry being edited; nil hides the editor
---@field set fun(entry: table) Store the edited entry
---@field context? 'layout'|'emphasis'
---@field kinds? boolean false hides "Applies to"
---@field hidden? fun(): boolean
---@field disabled? fun(): boolean
---@field onDone? fun()
---@field name? string
---@field order? number

local function SlotValues(opts, index)
	local entry = opts.get() or {}
	local conditions = entry.conditions or {}
	local used = {}
	for i, clause in ipairs(conditions) do
		if i ~= index then
			used[WhenBuilder:KeyOf(clause)] = true
		end
	end
	local current = conditions[index]
	local currentKey = current and WhenBuilder:KeyOf(current)
	local values, order = {}, {}
	if not current then
		values.add = L['Add a condition']
		order[#order + 1] = 'add'
	end
	for _, choice in ipairs(WhenBuilder:Choices(opts.context)) do
		if (choice.available and not used[choice.key]) or choice.key == currentKey then
			local text = choice.label
			if choice.badge then
				text = text .. ' (' .. choice.badge .. ')'
			end
			values[choice.key] = text
			order[#order + 1] = choice.key
		elseif choice.reason and not used[choice.key] then
			-- Grayed out: it cannot work on this client; picking it shows why under the editor
			values[choice.key] = '|cff808080' .. choice.label .. ' (' .. choice.badge .. ')|r'
			order[#order + 1] = choice.key
		end
	end
	if current and values[currentKey] == nil then
		values[currentKey] = WhenBuilder:ChoiceFor(current).label
		order[#order + 1] = currentKey
	end
	if current then
		values.remove = L['Remove this condition']
		order[#order + 1] = 'remove'
	end
	return values, order
end

local function ActionValues(opts)
	local entry = opts.get()
	local values, order = {}, {}
	local current = entry and WhenBuilder:ActionOf(entry, opts.context)
	if not current then
		values.none = L['Pick what should happen']
		order[#order + 1] = 'none'
	end
	for _, def in ipairs(WhenBuilder:Actions(opts.context, entry and entry.conditions)) do
		local limit = def.limits and def.limits[P.Caps:Client()]
		values[def.id] = type(limit) == 'string' and (def.label .. ' (' .. limit .. ')') or def.label
		order[#order + 1] = def.id
	end
	if current and values[current.id] == nil then
		values[current.id] = string.format(L['%s (cannot work here)'], current.label)
		order[#order + 1] = current.id
	end
	return values, order
end

---Build the editor for one entry. It is an inline group: a sentence, one dropdown per condition
---(a new empty one while there is room), the action and the controls the action adds, "Applies
---to", the client badge and what is wrong with the entry.
---@param opts Plates.WhenGroupOptions
---@return table group
function WhenBuilder:Group(opts)
	opts.context = opts.context or 'layout'
	local function Disabled()
		return opts.disabled ~= nil and opts.disabled() or false
	end
	local function Update(fn)
		if Disabled() then
			return
		end
		local entry = opts.get()
		if entry then
			entry = P.util.Copy(entry)
			if fn(entry) ~= false then
				opts.set(entry)
			end
		end
	end
	local function Missing()
		return opts.get() == nil
	end

	local args = {
		sentence = {
			type = 'description',
			order = 1,
			fontSize = 'medium',
			name = function()
				local entry = opts.get()
				return entry and WhenBuilder:Describe(entry, opts.context) or ''
			end,
		},
	}
	local conditionArgs = { header = { type = 'header', order = 1, name = L['When all of these are true'] } }
	local thenArgs = { header = { type = 'header', order = 1, name = L['Then'] } }

	local initial = opts.get()
	local slots = math.max(self.MAX_CONDITIONS, #(initial and initial.conditions or {}))
	for index = 1, slots do
		conditionArgs['condition' .. index] = {
			type = 'select',
			name = index == 1 and L['When'] or L['And'],
			advanced = index > self.MAX_CONDITIONS or nil,
			order = 2 + index,
			width = 1.6,
			values = function()
				return (SlotValues(opts, index))
			end,
			sorting = function()
				local _, order = SlotValues(opts, index)
				return order
			end,
			get = function()
				local entry = opts.get()
				local clause = entry and entry.conditions and entry.conditions[index]
				return clause and WhenBuilder:KeyOf(clause) or 'add'
			end,
			set = function(_, value)
				Update(function(entry)
					entry.conditions = entry.conditions or {}
					local values = SlotValues(opts, index)
					if value == 'remove' and entry.conditions[index] then
						table.remove(entry.conditions, index)
					elseif value ~= 'add' and values[value] then
						local clause = WhenBuilder:ClauseForKey(value)
						if clause then
							entry.conditions[math.min(index, #entry.conditions + 1)] = clause
						end
					end
				end)
			end,
			hidden = function()
				local entry = opts.get()
				return entry == nil or index > #(entry.conditions or {}) + 1
			end,
			disabled = Disabled,
		}
	end

	-- Pickers for conditions that take a list (spells, NPCs). Two spell lists and one NPC list per
	-- entry: the n-th clause with that picker is edited by the n-th control.
	local function PickerClause(entry, picker, nth)
		local seen = 0
		for index, clause in ipairs(entry and entry.conditions or {}) do
			if WhenBuilder:ChoiceFor(clause).picker == picker then
				seen = seen + 1
				if seen == nth then
					return clause, index
				end
			end
		end
		return nil, nil
	end
	local spellType = P.Widgets and P.Widgets.Has and P.Widgets:Has('SpellList') and P.Widgets:TypeName('SpellList') or nil
	for nth = 1, 2 do
		conditionArgs['spells' .. nth] = {
			type = 'select',
			name = function()
				local entry = opts.get()
				local clause = PickerClause(entry, 'spellList', nth)
				return clause and string.format(L['Spells for "%s"'], WhenBuilder:ChoiceFor(clause).label) or ''
			end,
			order = 7 + nth / 10,
			width = 'full',
			dialogControl = spellType,
			values = {},
			get = function()
				return nil
			end,
			set = function() end,
			hidden = function()
				local entry = opts.get()
				return spellType == nil or PickerClause(entry, 'spellList', nth) == nil
			end,
			disabled = Disabled,
			arg = {
				list = function()
					local clause = PickerClause(opts.get(), 'spellList', nth)
					local list = {}
					if clause and type(clause.args) == 'table' then
						for key, value in pairs(clause.args) do
							if type(key) == 'number' and value ~= false then
								list[key] = (value == 'mine' or value == 'any') and value or 'any'
							elseif type(value) == 'number' then
								list[value] = 'any'
							end
						end
					end
					return list
				end,
				onChange = function(list)
					Update(function(entry)
						local _, index = PickerClause(entry, 'spellList', nth)
						if not index then
							return false
						end
						local copy = {}
						for id, who in pairs(list or {}) do
							copy[id] = who
						end
						entry.conditions[index].args = next(copy) and copy or nil
					end)
				end,
				defaultWho = 'any',
				empty = L['No spells picked yet.'],
			},
		}
	end
	conditionArgs.npcs = {
		type = 'input',
		name = L['NPC IDs'],
		desc = L['Type NPC IDs with spaces or commas between them. Turn on IDs in tooltips to find them.'],
		order = 7.5,
		width = 'full',
		get = function()
			local clause = PickerClause(opts.get(), 'npcList', 1)
			local ids = {}
			for _, id in ipairs(clause and type(clause.args) == 'table' and clause.args or {}) do
				ids[#ids + 1] = tostring(id)
			end
			return table.concat(ids, ', ')
		end,
		set = function(_, text)
			Update(function(entry)
				local _, index = PickerClause(entry, 'npcList', 1)
				if not index then
					return false
				end
				local ids = {}
				for number in string.gmatch(text or '', '%d+') do
					local id = tonumber(number)
					if id and id > 0 and id < 2147483648 and #ids < 60 then
						ids[#ids + 1] = id
					end
				end
				entry.conditions[index].args = #ids > 0 and ids or nil
			end)
		end,
		hidden = function()
			return PickerClause(opts.get(), 'npcList', 1) == nil
		end,
		disabled = Disabled,
	}

	thenArgs.action = {
		type = 'select',
		name = L['Do this'],
		order = 11,
		width = 1.6,
		values = function()
			return (ActionValues(opts))
		end,
		sorting = function()
			local _, order = ActionValues(opts)
			return order
		end,
		get = function()
			local entry = opts.get()
			local def = entry and WhenBuilder:ActionOf(entry, opts.context)
			return def and def.id or 'none'
		end,
		set = function(_, value)
			if value == 'none' then
				return
			end
			Update(function(entry)
				WhenBuilder:SetAction(entry, value, opts.context)
			end)
		end,
		hidden = Missing,
		disabled = Disabled,
	}

	for position, def in ipairs(self:ActionList(opts.context)) do
		if def.Controls then
			local function Available(entry)
				local active = WhenBuilder:ActionOf(entry, opts.context)
				if not active or active.id ~= def.id then
					return false
				end
				for _, offered in ipairs(WhenBuilder:Actions(opts.context, entry.conditions)) do
					if offered.id == def.id then
						return true
					end
				end
				return false
			end
			local function UpdateAction(fn)
				Update(function(entry)
					if not Available(entry) then
						return false
					end
					return fn(entry)
				end)
			end
			local function Protect(control)
				local ownDisabled = control.disabled
				control.disabled = function(info)
					local entry = opts.get()
					return Disabled() or entry == nil or not Available(entry) or (type(ownDisabled) == 'function' and ownDisabled(info)) or ownDisabled == true
				end
				for _, child in pairs(control.args or {}) do
					Protect(child)
				end
			end
			local controls = def.Controls({ get = opts.get, update = UpdateAction, context = opts.context })
			for key, control in pairs(controls or {}) do
				local inner = control.hidden
				control.order = 11 + position / 10 + (control.order or 0) / 100
				control.hidden = function(info)
					local entry = opts.get()
					local active = entry and WhenBuilder:ActionOf(entry, opts.context)
					if not active or active.id ~= def.id then
						return true
					end
					return (type(inner) == 'function' and inner(info)) or inner == true
				end
				Protect(control)
				thenArgs['action_' .. def.id .. '_' .. key] = control
			end
		end
	end

	args.conditions = { type = 'group', name = '', inline = true, order = 2, hidden = Missing, args = conditionArgs }
	args.thenGroup = { type = 'group', name = '', inline = true, order = 10, hidden = Missing, args = thenArgs }

	if opts.kinds ~= false then
		args.kinds = {
			type = 'multiselect',
			name = L['Applies to'],
			desc = L['Pick the kinds of plates this covers. All of them are covered unless you uncheck some.'],
			order = 30,
			values = self.KIND_LABELS,
			sorting = P.Situation.KINDS,
			get = function(_, kind)
				local entry = opts.get()
				return entry ~= nil and (entry.kinds == nil or Contains(entry.kinds, kind))
			end,
			set = function(_, kind, value)
				Update(function(entry)
					local picked = {}
					for _, known in ipairs(P.Situation.KINDS) do
						local on = entry.kinds == nil or Contains(entry.kinds, known)
						if known == kind then
							on = value and true or false
						end
						if on then
							picked[#picked + 1] = known
						end
					end
					if #picked == 0 then
						return -- at least one kind stays picked
					end
					entry.kinds = #picked < #P.Situation.KINDS and picked or nil
				end)
			end,
			hidden = Missing,
			disabled = Disabled,
		}
	end

	args.badge = {
		type = 'description',
		order = 40,
		name = function()
			local entry = opts.get()
			return entry and WhenBuilder:EntryBadge(entry, opts.context) or ''
		end,
		hidden = function()
			local entry = opts.get()
			return entry == nil or WhenBuilder:EntryBadge(entry, opts.context) == nil
		end,
	}
	args.problems = {
		type = 'description',
		order = 41,
		name = function()
			local entry = opts.get()
			return entry and table.concat(WhenBuilder:Problems(entry, opts.context), ' ') or ''
		end,
		hidden = function()
			local entry = opts.get()
			return entry == nil or #WhenBuilder:Problems(entry, opts.context) == 0
		end,
	}
	if opts.onDone then
		args.done = {
			type = 'execute',
			name = L['Done'],
			order = 50,
			width = 0.6,
			func = function()
				opts.onDone()
			end,
			hidden = Missing,
		}
	end

	return {
		type = 'group',
		name = opts.name or L['Edit this special case'],
		inline = true,
		order = opts.order,
		hidden = function()
			return (opts.hidden ~= nil and opts.hidden()) or opts.get() == nil
		end,
		args = args,
	}
end
