local _, ns = ...
local P = ns.Plates
local L = P.L

-- The condition catalog (6.4) under color rows, "When" special cases and the "When" actions
-- (Phase 8, Engine/Actions.lua). Each condition is one of:
--   plain    never secret: any action is allowed (style swap, hide, names only, size, color, ...)
--   engine   may be secret on Retail and Forever: color, alpha, glow and marks only (overlay
--            pieces the engine fades or tints); secretActions narrows that further
--   identity NPC id, unit name, spell id: checked with C_Secrets.ShouldUnitIdentityBeSecret first;
--            when hidden the condition simply does not match, so it never needs the engine and
--            allows every action
--
-- Contract for a condition:
--   Test(env, args)       -> true | false | nil. nil means "the game hides the answer"; only
--                            engine conditions may return nil.
--   TestSecret(env, args) -> boolean, possibly secret. Engine conditions only; the result may only
--                            reach a sink (Secret.ChooseValue, SetAlphaFromBoolean, ...).
-- env is { facts = Plates.Facts, ctx = Plates.Context, states = table, src = Plates.Source }.
-- Plain conditions must never touch env.src (Assign runs them before a source exists).

---@class Plates.Condition
---@field id string
---@field kind 'plain'|'engine'|'identity'
---@field label string
---@field facts? string[] Facts it reads (Assign re-runs only when one changes)
---@field events? string[] Unit events that can change the answer
---@field messages? string[] Bus messages that can change the answer
---@field argType? 'place'|'mobType'|'reaction'|'role'|'spellList'|'npcList'|'number'
---@field phase? integer Not offered before this phase
---@field limits? table<string, string> Client name -> short badge text shown next to it
---@field secretActions? table<string, boolean> Engine conditions: the actions they allow where the game hides answers (default color, alpha, glow, mark)
---@field Unavailable? fun(): string|nil A player sentence when the condition cannot work on this client
---@field Test fun(env: table, args: any): boolean|nil
---@field TestSecret? fun(env: table, args: any): any

---@class Plates.Conditions
local Conditions = { catalog = {}, order = {} }
P.Conditions = Conditions

---@param cond Plates.Condition
function Conditions:Register(cond)
	assert(cond.id and cond.kind and cond.Test, 'Conditions:Register needs id, kind and Test')
	if cond.kind == 'engine' then
		assert(cond.TestSecret, 'Engine condition ' .. cond.id .. ' needs TestSecret')
	end
	if not self.catalog[cond.id] then
		self.order[#self.order + 1] = cond.id
	end
	self.catalog[cond.id] = cond
end

---@param id string
---@return Plates.Condition|nil
function Conditions:Get(id)
	return self.catalog[id]
end

---Every action key (WhenBuilder action `needs`): layout (style, hide, name, size) and emphasis
---(grow in whole pixels, alpha, color, glow, mark).
Conditions.ACTION_KEYS = { 'style', 'hide', 'name', 'size', 'grow', 'alpha', 'color', 'glow', 'mark' }

-- What an answer the game hides can still drive: sinks that take a secret boolean (alpha, color,
-- glow, a mark's alpha). Never layout or size.
Conditions.ENGINE_ACTIONS = { alpha = true, color = true, glow = true, mark = true }

---Actions a condition allows on this client. Plain and identity conditions always answer in Lua
---(identity answers "no" when hidden), so they allow everything; engine conditions allow only
---the sinks on clients with secrets.
---@param id string
---@return table<string, boolean>
function Conditions:AllowedActions(id)
	local cond = self.catalog[id]
	if not cond then
		return {}
	end
	local out = {}
	if cond.kind ~= 'engine' or not P.Caps:Get('secrets') then
		for _, key in ipairs(self.ACTION_KEYS) do
			out[key] = true
		end
		return out
	end
	for key in pairs(cond.secretActions or self.ENGINE_ACTIONS) do
		out[key] = true
	end
	return out
end

---Settle a clause list (all must hold, the shape of a "When" entry) as far as Lua can.
---@param clauses table[] { { id, args?, negate? } }
---@param env table
---@return boolean|nil result true or false when settled, nil when the game decides
---@return table|nil leaf The one clause the game decides (nil when none or several do)
---@return integer unknown How many clauses the game decides
function Conditions:Reduce(clauses, env)
	local leaf, unknown = nil, 0
	for i = 1, #clauses do
		local clause = clauses[i]
		local cond = self.catalog[clause.id]
		if not cond then
			return false, nil, 0
		end
		local r = cond.Test(env, clause.args)
		if r == nil then
			unknown = unknown + 1
			leaf = clause
		else
			r = r == true
			if clause.negate then
				r = not r
			end
			if not r then
				return false, nil, 0
			end
		end
	end
	if unknown == 0 then
		return true, nil, 0
	end
	return nil, unknown == 1 and leaf or nil, unknown
end

----------------------------------------------------------------------------------------------------
-- Expressions: a leaf { id = 'tapped', args = ..., negate = true } or { all = { ... } },
-- { any = { ... } }, { ['not'] = expr }.
----------------------------------------------------------------------------------------------------

---Plain answer for an expression: true, false, or nil when the engine must decide.
---@param expr table
---@param env table
---@return boolean|nil
function Conditions:TestExpr(expr, env)
	if expr.all then
		local unknown = false
		for i = 1, #expr.all do
			local r = self:TestExpr(expr.all[i], env)
			if r == false then
				return false
			elseif r == nil then
				unknown = true
			end
		end
		if unknown then
			return nil
		end
		return true
	elseif expr.any then
		local unknown = false
		for i = 1, #expr.any do
			local r = self:TestExpr(expr.any[i], env)
			if r == true then
				return true
			elseif r == nil then
				unknown = true
			end
		end
		if unknown then
			return nil
		end
		return false
	elseif expr['not'] then
		local r = self:TestExpr(expr['not'], env)
		if r == nil then
			return nil
		end
		return not r
	end
	local cond = self.catalog[expr.id]
	if not cond then
		return false
	end
	local r = cond.Test(env, expr.args)
	if r == nil then
		return nil
	end
	if expr.negate then
		return not r
	end
	return r == true
end

---Fold one color channel through an expression (6.4): ifTrue when it holds, ifFalse otherwise.
---Inputs and output may be secret. AND puts the next term in the true slot, OR in the false slot,
---NOT swaps them. Plain leaves are settled in Lua; engine leaves go through Secret.ChooseValue.
---@param expr table
---@param env table
---@param ifTrue any
---@param ifFalse any
---@return any valueSecret
function Conditions:FoldSecret(expr, env, ifTrue, ifFalse)
	if expr.all then
		local valueSecret = ifTrue
		for i = #expr.all, 1, -1 do
			valueSecret = self:FoldSecret(expr.all[i], env, valueSecret, ifFalse)
		end
		return valueSecret
	elseif expr.any then
		local valueSecret = ifFalse
		for i = #expr.any, 1, -1 do
			valueSecret = self:FoldSecret(expr.any[i], env, ifTrue, valueSecret)
		end
		return valueSecret
	elseif expr['not'] then
		return self:FoldSecret(expr['not'], env, ifFalse, ifTrue)
	end
	local cond = self.catalog[expr.id]
	if not cond then
		return ifFalse
	end
	if expr.negate then
		ifTrue, ifFalse = ifFalse, ifTrue
	end
	local r = cond.Test(env, expr.args)
	if r == true then
		return ifTrue
	elseif r == false or not cond.TestSecret then
		return ifFalse
	end
	return P.Secret.ChooseValue(cond.TestSecret(env, expr.args), ifTrue, ifFalse)
end

---FoldSecret for a whole color at once: the three channels are folded in one pass, so every leaf
---is asked once per color instead of once per channel (Colors folds hidden rows this way).
---@param expr table
---@param env table
---@return any rSecret
---@return any gSecret
---@return any bSecret
function Conditions:FoldColorSecret(expr, env, trSecret, tgSecret, tbSecret, frSecret, fgSecret, fbSecret)
	if expr.all then
		local rSecret, gSecret, bSecret = trSecret, tgSecret, tbSecret
		for i = #expr.all, 1, -1 do
			rSecret, gSecret, bSecret = self:FoldColorSecret(expr.all[i], env, rSecret, gSecret, bSecret, frSecret, fgSecret, fbSecret)
		end
		return rSecret, gSecret, bSecret
	elseif expr.any then
		local rSecret, gSecret, bSecret = frSecret, fgSecret, fbSecret
		for i = #expr.any, 1, -1 do
			rSecret, gSecret, bSecret = self:FoldColorSecret(expr.any[i], env, trSecret, tgSecret, tbSecret, rSecret, gSecret, bSecret)
		end
		return rSecret, gSecret, bSecret
	elseif expr['not'] then
		return self:FoldColorSecret(expr['not'], env, frSecret, fgSecret, fbSecret, trSecret, tgSecret, tbSecret)
	end
	local cond = self.catalog[expr.id]
	if not cond then
		return frSecret, fgSecret, fbSecret
	end
	if expr.negate then
		trSecret, tgSecret, tbSecret, frSecret, fgSecret, fbSecret = frSecret, fgSecret, fbSecret, trSecret, tgSecret, tbSecret
	end
	local r = cond.Test(env, expr.args)
	if r == true then
		return trSecret, tgSecret, tbSecret
	elseif r == false or not cond.TestSecret then
		return frSecret, fgSecret, fbSecret
	end
	local conditionSecret = cond.TestSecret(env, expr.args)
	local Secret = P.Secret
	return Secret.ChooseValue(conditionSecret, trSecret, frSecret), Secret.ChooseValue(conditionSecret, tgSecret, fgSecret), Secret.ChooseValue(conditionSecret, tbSecret, fbSecret)
end

---Unit events and bus messages an expression needs (added to out tables as sets).
---@param expr table
---@param events table<string, boolean>
---@param messages table<string, boolean>
function Conditions:CollectEvents(expr, events, messages)
	local list = expr.all or expr.any
	if list then
		for i = 1, #list do
			self:CollectEvents(list[i], events, messages)
		end
		return
	end
	if expr['not'] then
		self:CollectEvents(expr['not'], events, messages)
		return
	end
	local cond = self.catalog[expr.id]
	if not cond then
		return
	end
	for _, e in ipairs(cond.events or {}) do
		events[e] = true
	end
	for _, m in ipairs(cond.messages or {}) do
		messages[m] = true
	end
end

----------------------------------------------------------------------------------------------------
-- "When" clauses on color rows (where a row applies). Plain, read from the shared context.
----------------------------------------------------------------------------------------------------

Conditions.WHEN = {
	everywhere = function()
		return true
	end,
	instances = function(ctx)
		return ctx.place ~= 'world'
	end,
	world = function(ctx)
		return ctx.place == 'world'
	end,
	dungeons = function(ctx)
		return ctx.place == 'dungeon' or ctx.place == 'delve' or ctx.place == 'scenario'
	end,
	raids = function(ctx)
		return ctx.place == 'raid'
	end,
	delves = function(ctx)
		return ctx.place == 'delve'
	end,
	pvp = function(ctx)
		return ctx.place == 'arena' or ctx.place == 'battleground'
	end,
	combat = function(ctx)
		return ctx.inCombat == true
	end,
	never = function()
		return false
	end,
}
Conditions.WHEN_ORDER = { 'everywhere', 'instances', 'dungeons', 'raids', 'delves', 'pvp', 'world', 'combat', 'never' }
Conditions.WHEN_LABELS = {
	everywhere = L['Everywhere'],
	instances = L['In instances'],
	dungeons = L['In dungeons'],
	raids = L['In raids'],
	delves = L['In delves'],
	pvp = L['In PvP'],
	world = L['Out in the world'],
	combat = L['In combat'],
	never = L['Never'],
}

---@param whenId string|nil
---@param ctx Plates.Context
---@return boolean
function Conditions:WhenApplies(whenId, ctx)
	local fn = self.WHEN[whenId or 'everywhere']
	return fn ~= nil and fn(ctx) == true
end

----------------------------------------------------------------------------------------------------
-- Interrupt readiness (player spell cooldown, not a unit read). The kick spell comes from
-- P.Context.kickSpell, set by the Driver from Data/Kicks.
----------------------------------------------------------------------------------------------------

function Conditions.RefreshKick()
	local ctx = P.Context
	local spell = ctx.kickSpell
	ctx.kickDurationSpell = spell
	ctx.kickDuration = nil
	if spell and C_Spell and C_Spell.GetSpellCooldownDuration then
		ctx.kickDuration = C_Spell.GetSpellCooldownDuration(spell, true)
	end
end

local function KickDuration()
	local ctx = P.Context
	local spell = ctx and ctx.kickSpell
	if P.Driver and P.Driver.active and ctx.kickDurationSpell == spell then
		return ctx.kickDuration
	end
	if not spell or not (C_Spell and C_Spell.GetSpellCooldownDuration) then
		return nil
	end
	-- true ignores the global cooldown, or the tint would drop out on every GCD
	return C_Spell.GetSpellCooldownDuration(spell, true)
end

---@return boolean|nil ready nil when the game hides it; false when no interrupt is known
function Conditions.KickReadyPlain()
	local duration = KickDuration()
	if type(duration) == 'nil' then
		return false
	end
	local readySecret = duration:IsZero()
	local ready, readable = P.Secret.Plain(readySecret)
	if not readable then
		return nil
	end
	return ready == true
end

---@return any readySecret
function Conditions.KickReadySecret()
	local duration = KickDuration()
	if type(duration) == 'nil' then
		return false
	end
	return duration:IsZero()
end

----------------------------------------------------------------------------------------------------
-- The catalog
----------------------------------------------------------------------------------------------------

local function Facts(env)
	return env.facts or {}
end

local REACTION = { hostile = { 1, 3 }, neutral = { 4, 4 }, friendly = { 5, 8 } }

Conditions:Register({
	id = 'reaction',
	kind = 'plain',
	label = L['Reaction'],
	argType = 'reaction',
	facts = { 'reaction' },
	events = { 'UNIT_FACTION' },
	Test = function(env, args)
		local range = REACTION[args or 'hostile']
		local reaction = Facts(env).reaction
		return range ~= nil and reaction ~= nil and reaction >= range[1] and reaction <= range[2]
	end,
})
Conditions:Register({
	id = 'canAttack',
	kind = 'plain',
	label = L['Can be attacked'],
	facts = { 'canAttack' },
	events = { 'UNIT_FACTION' },
	Test = function(env)
		return Facts(env).canAttack == true
	end,
})
Conditions:Register({
	id = 'mobType',
	kind = 'plain',
	label = L['Mob type'],
	argType = 'mobType',
	facts = { 'classification', 'isBoss', 'isLieutenant', 'isCaster', 'effectiveLevel', 'isMinion' },
	events = { 'UNIT_CLASSIFICATION_CHANGED' },
	Test = function(env, args)
		local facts = Facts(env)
		local mobType = facts.mobType or P.Situation.MobType(facts, env.ctx)
		return mobType == args
	end,
})
Conditions:Register({
	id = 'elite',
	kind = 'plain',
	label = L['Elite'],
	facts = { 'classification' },
	events = { 'UNIT_CLASSIFICATION_CHANGED' },
	Test = function(env)
		local class = Facts(env).classification
		return class == 'elite' or class == 'rareelite' or class == 'worldboss'
	end,
})
Conditions:Register({
	id = 'rare',
	kind = 'plain',
	label = L['Rare'],
	facts = { 'classification' },
	events = { 'UNIT_CLASSIFICATION_CHANGED' },
	Test = function(env)
		local class = Facts(env).classification
		return class == 'rare' or class == 'rareelite'
	end,
})
Conditions:Register({
	id = 'levelAbove',
	kind = 'plain',
	label = L['Higher level than you'],
	facts = { 'effectiveLevel' },
	events = { 'UNIT_LEVEL' },
	Test = function(env)
		local level = Facts(env).effectiveLevel
		local mine = env.ctx and env.ctx.playerLevel
		return level ~= nil and mine ~= nil and (level == -1 or level > mine)
	end,
})
Conditions:Register({
	id = 'isPlayer',
	kind = 'plain',
	label = L['Player'],
	facts = { 'isPlayer' },
	Test = function(env)
		return Facts(env).isPlayer == true
	end,
})
Conditions:Register({
	id = 'isNPC',
	kind = 'plain',
	label = L['NPC'],
	facts = { 'isPlayer' },
	Test = function(env)
		return Facts(env).isPlayer ~= true
	end,
})
Conditions:Register({
	id = 'minion',
	kind = 'plain',
	label = L['Pet, totem or minion'],
	facts = { 'isMinion', 'playerControlled', 'isPlayer' },
	Test = function(env)
		local facts = Facts(env)
		return facts.isMinion == true or (facts.playerControlled == true and facts.isPlayer ~= true)
	end,
})
Conditions:Register({
	id = 'tapped',
	kind = 'plain',
	label = L['Tagged by someone else'],
	facts = { 'tapDenied' },
	events = { 'UNIT_FACTION' },
	Test = function(env)
		return Facts(env).tapDenied == true
	end,
})
Conditions:Register({
	id = 'quest',
	kind = 'plain',
	label = L['Quest mob'],
	facts = { 'isQuest', 'questBoss' },
	messages = { 'QUESTS_CHANGED' },
	Test = function(env)
		local facts = Facts(env)
		return facts.isQuest == true or facts.questBoss == true
	end,
})
Conditions:Register({
	id = 'target',
	kind = 'plain',
	label = L['Your target'],
	messages = { 'TARGET_CHANGED' },
	Test = function(env)
		return env.states ~= nil and env.states.target == true
	end,
})
Conditions:Register({
	id = 'focus',
	kind = 'plain',
	label = L['Your focus'],
	messages = { 'FOCUS_CHANGED' },
	Test = function(env)
		return env.states ~= nil and env.states.focus == true
	end,
})
Conditions:Register({
	id = 'mouseover',
	kind = 'plain',
	label = L['Under your mouse'],
	messages = { 'MOUSEOVER_CHANGED' },
	Test = function(env)
		return env.states ~= nil and env.states.mouseover == true
	end,
})
Conditions:Register({
	id = 'casting',
	kind = 'plain',
	label = L['Casting'],
	events = { 'UNIT_SPELLCAST_START', 'UNIT_SPELLCAST_STOP', 'UNIT_SPELLCAST_CHANNEL_START', 'UNIT_SPELLCAST_CHANNEL_STOP', 'UNIT_SPELLCAST_EMPOWER_START', 'UNIT_SPELLCAST_EMPOWER_STOP' },
	Test = function(env)
		return env.states ~= nil and env.states.casting == true
	end,
})
Conditions:Register({
	id = 'myCombat',
	kind = 'plain',
	label = L['You are in combat'],
	messages = { 'CONTEXT_CHANGED' },
	Test = function(env)
		return env.ctx ~= nil and env.ctx.inCombat == true
	end,
})
Conditions:Register({
	id = 'resting',
	kind = 'plain',
	label = L['You are resting'],
	messages = { 'CONTEXT_CHANGED' },
	Test = function(env)
		return env.ctx ~= nil and env.ctx.resting == true
	end,
})
Conditions:Register({
	id = 'place',
	kind = 'plain',
	label = L['Place'],
	argType = 'place',
	messages = { 'CONTEXT_CHANGED' },
	Test = function(env, args)
		local ctx = env.ctx
		if not ctx then
			return false
		end
		if args == 'pvp' then
			return ctx.place == 'arena' or ctx.place == 'battleground'
		elseif args == 'instance' then
			return ctx.place ~= 'world'
		end
		return ctx.place == args
	end,
})
Conditions:Register({
	id = 'difficulty',
	kind = 'plain',
	label = L['Difficulty'],
	argType = 'number',
	messages = { 'CONTEXT_CHANGED' },
	Test = function(env, args)
		return env.ctx ~= nil and env.ctx.difficultyID == args
	end,
})
Conditions:Register({
	id = 'role',
	kind = 'plain',
	label = L['Your role'],
	argType = 'role',
	messages = { 'CONTEXT_CHANGED' },
	Test = function(env, args)
		return env.ctx ~= nil and env.ctx.role == args
	end,
})
Conditions:Register({
	id = 'inGroup',
	kind = 'plain',
	label = L['You are in a group'],
	messages = { 'CONTEXT_CHANGED' },
	Test = function(env)
		return env.ctx ~= nil and env.ctx.inGroup == true
	end,
})
Conditions:Register({
	id = 'challenge',
	kind = 'plain',
	label = L['During a Mythic+ run'],
	messages = { 'CONTEXT_CHANGED' },
	Test = function(env)
		return env.ctx ~= nil and env.ctx.challengeActive == true
	end,
})

-- Engine conditions: the source answers with a Plain read first, the engine decides otherwise

local function EngineFromSource(id, label, plainMethod, secretMethod, events, messages)
	Conditions:Register({
		id = id,
		kind = 'engine',
		label = label,
		events = events,
		messages = messages,
		Test = function(env)
			local src = env.src
			if not src then
				return false
			end
			local value, readable = src[plainMethod](src)
			if not readable then
				return nil
			end
			return value == true
		end,
		TestSecret = function(env)
			local src = env.src
			if not src then
				return false
			end
			return src[secretMethod](src)
		end,
	})
end

local CAST_EVENTS = {
	'UNIT_SPELLCAST_START',
	'UNIT_SPELLCAST_STOP',
	'UNIT_SPELLCAST_CHANNEL_START',
	'UNIT_SPELLCAST_CHANNEL_STOP',
	'UNIT_SPELLCAST_EMPOWER_START',
	'UNIT_SPELLCAST_EMPOWER_STOP',
	'UNIT_SPELLCAST_INTERRUPTIBLE',
	'UNIT_SPELLCAST_NOT_INTERRUPTIBLE',
}

EngineFromSource('notInterruptible', L['Cannot be interrupted'], 'NotInterruptiblePlain', 'NotInterruptibleSecret', CAST_EVENTS)
EngineFromSource('importantCast', L['Important cast'], 'IsImportantPlain', 'IsImportantSecret', CAST_EVENTS)
EngineFromSource('aimedAtMe', L['Cast aimed at you'], 'AimedAtMePlain', 'AimedAtMeSecret', CAST_EVENTS)
EngineFromSource('unitInCombat', L['Enemy is fighting'], 'InCombatPlain', 'InCombatSecret', nil, { 'FACTS_POLLED' })

Conditions:Register({
	id = 'interruptReady',
	kind = 'engine',
	label = L['Your interrupt is ready'],
	messages = { 'KICK_READY_CHANGED' },
	-- Previews answer from the sample, live plates from the player's interrupt cooldown
	Test = function(env)
		local src = env and env.src
		if src and src.isSample then
			return src:KickReady()
		end
		return Conditions.KickReadyPlain()
	end,
	TestSecret = function(env)
		local src = env and env.src
		if src and src.isSample then
			return src:KickReady()
		end
		return Conditions.KickReadySecret()
	end,
})

-- Aura presence ("Has <spell>", "My debuff is missing"). The Classic family answers with plain reads
-- (Engine/Parts/AurasScan.lua wraps Test, adds UNIT_AURA and reads the spell list in args). Where
-- the game hides auras, only the health color rows can use them, through aura slots (S19); a
-- "When" action cannot, so the condition says why and the builder grays it out.
local function AurasHidden()
	if P.Caps:Get('secrets') then
		return L['The game hides which spells are on a unit on this version of WoW, so this cannot be checked here.']
	end
	return nil
end

Conditions:Register({
	id = 'auraPresent',
	kind = 'engine',
	label = L['Has a spell on it'],
	argType = 'spellList',
	phase = 8,
	Unavailable = AurasHidden,
	Test = function()
		return false
	end,
	TestSecret = function()
		return false
	end,
})
Conditions:Register({
	id = 'auraMissing',
	kind = 'engine',
	label = L['Your debuff is missing'],
	argType = 'spellList',
	phase = 8,
	Unavailable = AurasHidden,
	Test = function()
		return false
	end,
	TestSecret = function()
		return false
	end,
})

-- Low health. args is the percent (1-99, default 35). Readable health is plain math; where the game
-- hides it there is no yes or no answer at all, only a curve the engine evaluates, so the actions
-- that can use it are the ones drawn on a texture whose alpha the curve sets (Conditions.LowHealthCurve).
Conditions.LOW_HEALTH_DEFAULT = 35

---@param args any
---@return number threshold 0.01-0.99
function Conditions.LowHealthThreshold(args)
	local percent = tonumber(args) or Conditions.LOW_HEALTH_DEFAULT
	percent = math.max(1, math.min(99, percent))
	return percent / 100
end

local lowCurves = {}

---A step curve from health (0-1) to alpha: alphaOn at or below the threshold, 0 above (the other
---way round for negate, "not low"). Cached per threshold, alpha and direction. nil on clients
---without curves.
---@param args any
---@param alphaOn number
---@param negate? boolean
---@return table|nil curve
function Conditions.LowHealthCurve(args, alphaOn, negate)
	if not (C_CurveUtil and C_CurveUtil.CreateCurve) then
		return nil
	end
	alphaOn = alphaOn or 1
	local threshold = Conditions.LowHealthThreshold(args)
	local key = string.format('%.3f|%.3f|%s', threshold, alphaOn, negate and 'n' or 'y')
	local curve = lowCurves[key]
	if not curve then
		local low, high = alphaOn, 0
		if negate then
			low, high = 0, alphaOn
		end
		curve = C_CurveUtil.CreateCurve()
		if curve.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then
			curve:SetType(Enum.LuaCurveType.Step)
		end
		curve:AddPoint(0, low)
		curve:AddPoint(threshold, high)
		curve:AddPoint(1, high)
		lowCurves[key] = curve
	end
	return curve
end

Conditions:Register({
	id = 'lowHealth',
	kind = 'engine',
	label = L['Low health'],
	argType = 'percent',
	curve = true,
	secretActions = { color = true, mark = true },
	events = { 'UNIT_HEALTH', 'UNIT_MAXHEALTH' },
	Test = function(env, args)
		local src = env.src
		if not src then
			return false
		end
		local health, readable = src:HealthPlain()
		local maxValue, maxReadable = src:HealthMaxPlain()
		if not (readable and maxReadable) or type(health) ~= 'number' or type(maxValue) ~= 'number' then
			return nil
		end
		if maxValue <= 0 then
			return false
		end
		return health / maxValue <= Conditions.LowHealthThreshold(args)
	end,
	-- No boolean exists for hidden health: folds treat it as "no" and sinks use LowHealthCurve
	TestSecret = function()
		return nil
	end,
})

-- Identity conditions: hidden identity means no match

local function IdentityHidden(env)
	local src = env.src
	return not src or (src.unit and P.Secret.ShouldUnitIdentityBeSecret(src.unit))
end

---A list { 589, 172 } or a set { [589] = true } or { [589] = 'mine' | 'any' } (SpellList).
local function InList(list, value)
	if type(list) ~= 'table' or value == nil then
		return false
	end
	for i = 1, #list do
		if list[i] == value then
			return true
		end
	end
	local entry = list[value]
	return entry ~= nil and entry ~= false
end
Conditions.InList = InList

Conditions:Register({
	id = 'npcID',
	kind = 'identity',
	label = L['NPC'],
	argType = 'npcList',
	phase = 8,
	Test = function(env, args)
		if IdentityHidden(env) then
			return false
		end
		local id = env.src:CreatureIDPlain()
		return InList(args, id)
	end,
})
Conditions:Register({
	id = 'castSpell',
	kind = 'identity',
	label = L['Casting a spell'],
	argType = 'spellList',
	events = CAST_EVENTS,
	phase = 8,
	Test = function(env, args)
		if IdentityHidden(env) then
			return false
		end
		local id = env.src:SpellIDPlain()
		return InList(args, id)
	end,
})

-- Totems: known totems by NPC (Data/Totems, Classic family) and the player's own totems (Retail and
-- Forever) through the source; anything the game hides is not a totem here.
Conditions:Register({
	id = 'totem',
	kind = 'identity',
	label = L['Totem'],
	facts = { 'isMinion', 'playerControlled' },
	Test = function(env)
		local src = env.src
		if not src or not src.TotemIconPlain then
			return false
		end
		if src.unit and P.Secret.ShouldUnitIdentityBeSecret(src.unit) then
			return false
		end
		local ok, icon = pcall(src.TotemIconPlain, src)
		return ok and icon ~= nil
	end,
})
