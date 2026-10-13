local _, ns = ...
local P = ns.Plates
local L = P.L

-- Ordered color lists (6.4). Each colored piece (health bar, border, name, cast bar) has one list;
-- the top row that fits wins. Rows come from a scheme (threat first, mob type first, class first)
-- or from the player's own order (custom). A list is compiled once into a "program" and applied
-- on every update:
--   1. Plain rows are checked top to bottom in Lua; the first plain match sets the base color.
--   2. Rows above it that the game hides (engine rows) are folded per channel, lowest priority
--      first, with C_CurveUtil.EvaluateColorValueFromBoolean; each secret output feeds the next.
--   3. The result goes straight to the sink (SetStatusBarColor, SetVertexColor, SetTextColor).
-- So "the top row wins" stays true even when Lua cannot read the answer.
--
-- Contract for a row kind (Colors:RegisterKind):
--   boolean kinds give `expr` (a Conditions expression) and `default` = { r, g, b, a }
--   mapped kinds give Resolve(env, row) -> matched (true|false|nil), r, g, b, a and, when they
--     can be decided by the engine, FoldSecret(env, row, rSecret, gSecret, bSecret) -> r, g, b
--   curve kinds (low health, execute) are drawn as an overlay by the bar, never folded

---@class Plates.ColorKind
---@field id string
---@field label string
---@field type 'boolean'|'mapped'|'curve'
---@field pieces string[] Pieces this row makes sense on
---@field expr? table Conditions expression (boolean kinds)
---@field default table Color { r, g, b, a } (boolean) or map state -> color (mapped)
---@field when? string Default "When" clause id
---@field events? string[] Unit events (mapped kinds)
---@field messages? string[] Bus messages (mapped kinds)
---@field Resolve? fun(env: table, row: Plates.ColorRow): boolean|nil, number?, number?, number?, number?
---@field FoldSecret? fun(env: table, row: Plates.ColorRow, r: any, g: any, b: any): any, any, any
---@field Sentence? fun(row: Plates.ColorRow): string
---@field available? boolean false until the phase that builds it
---@field limits? table<string, string> Client name -> badge text

---@class Plates.ColorRow
---@field id string
---@field kind Plates.ColorKind
---@field color? number[] Boolean rows
---@field colors? table<string, number[]> Mapped rows
---@field expr? table
---@field when string

---@class Plates.ColorProgram
---@field piece string
---@field rows Plates.ColorRow[]
---@field fallback number[]
---@field overlay? Plates.ColorRow First curve row, drawn by the bar as an overlay
---@field events table<string, boolean>
---@field messages table<string, boolean>
---@field whenKeys table<string, boolean> Context keys the rows' "When" clauses read (place, inCombat)
---@field scheme string

---@class Plates.Colors
local Colors = { kinds = {}, kindOrder = {}, programs = {}, contextPrograms = setmetatable({}, { __mode = 'k' }) }
P.Colors = Colors

Colors.PIECES = { 'health', 'border', 'name', 'cast' }

---Which threat channel each piece belongs to (Roles.ThreatOn keys).
Colors.PIECE_CHANNEL = { health = 'bar', border = 'border', name = 'name' }

Colors.FALLBACK = {
	health = { 0.7, 0.7, 0.7, 1 },
	border = { 0, 0, 0, 1 },
	name = { 1, 1, 1, 1 },
	cast = { 1, 0.7, 0.1, 1 },
}

---The threat group expands to these rows, top first.
Colors.THREAT_GROUP = { 'offTank', 'petTank', 'threat' }

---Scheme row orders, top wins. '@threat' expands to the threat group on the pieces where threat
---shows (Roles.ThreatOn). A table entry may set the default "When" clause for that scheme.
Colors.SCHEMES = {
	threat = {
		health = { 'tapped', '@threat', { id = 'quest', when = 'world' }, { id = 'mobType', when = 'dungeons' }, 'class', 'reaction' },
		border = { 'target', 'focus', '@threat' },
		name = { '@threat', 'class' },
		cast = { 'notInterruptible', 'interruptReady', 'importantCast' },
	},
	mobType = {
		health = { 'tapped', { id = 'mobType', when = 'dungeons' }, '@threat', { id = 'quest', when = 'world' }, 'class', 'reaction' },
		border = { 'target', 'focus', '@threat' },
		name = { '@threat', 'class' },
		cast = { 'notInterruptible', 'interruptReady', 'importantCast' },
	},
	class = {
		health = { 'tapped', 'class', '@threat', { id = 'mobType', when = 'dungeons' }, { id = 'quest', when = 'world' }, 'reaction' },
		border = { 'target', 'focus', '@threat' },
		name = { '@threat', 'class' },
		cast = { 'notInterruptible', 'interruptReady', 'importantCast' },
	},
}
Colors.SCHEME_ORDER = { 'threat', 'mobType', 'class', 'custom' }
Colors.SCHEME_LABELS = {
	threat = L['Threat first (tanks)'],
	mobType = L['Mob type first (dungeon damage)'],
	class = L['Class first (PvP)'],
	custom = L['Custom'],
}

---@param kind Plates.ColorKind
function Colors:RegisterKind(kind)
	assert(kind.id and kind.type, 'Colors:RegisterKind needs id and type')
	if not self.kinds[kind.id] then
		self.kindOrder[#self.kindOrder + 1] = kind.id
	end
	self.kinds[kind.id] = kind
	self:Invalidate()
end

---@param id string
---@return Plates.ColorKind|nil
function Colors:GetKind(id)
	return self.kinds[id]
end

---Forget compiled programs (settings, role or context changes).
function Colors:Invalidate()
	P.util.Wipe(self.programs)
	P.util.Wipe(self.contextPrograms)
end

local function SchemeFor(settings, ctx)
	local scheme = settings.scheme or 'auto'
	if scheme == 'auto' then
		scheme = P.Roles.Scheme(ctx.role)
	end
	return scheme
end

local function ThreatWhen(settings)
	local when = settings.threat and settings.threat.when or 'instances'
	if when == 'always' then
		return 'everywhere'
	end
	return when
end

---Expanded row entries { id, when } for a piece in a scheme (no player order applied).
---@param scheme string
---@param piece string
---@param settings table Profile view
---@param role string
---@return table[] entries
function Colors:SchemeRows(scheme, piece, settings, role)
	local list = (self.SCHEMES[scheme] or self.SCHEMES.mobType)[piece] or {}
	local threatOn = P.Roles.ThreatOn(role, settings.threat and settings.threat.show)
	local channel = self.PIECE_CHANNEL[piece]
	local out = {}
	for _, entry in ipairs(list) do
		if entry == '@threat' then
			if channel and threatOn[channel] then
				for _, id in ipairs(self.THREAT_GROUP) do
					out[#out + 1] = { id = id, when = ThreatWhen(settings) }
				end
			end
		elseif type(entry) == 'table' then
			out[#out + 1] = { id = entry.id, when = entry.when }
		else
			out[#out + 1] = { id = entry }
		end
	end
	return out
end

local function Color4(c)
	return { c[1] or c.r or 1, c[2] or c.g or 1, c[3] or c.b or 1, c[4] or c.a or 1 }
end

---Compile one piece's list into a program (pure; cached by Colors:Program).
---@param piece string
---@param settings table Profile view: scheme, colors, threat, colorBlind
---@param ctx Plates.Context
---@return Plates.ColorProgram
function Colors:Compile(piece, settings, ctx)
	local scheme = SchemeFor(settings, ctx)
	local custom = settings.colors and settings.colors[piece] or {}
	local entries
	if scheme == 'custom' and type(custom.order) == 'table' then
		entries = {}
		for _, id in ipairs(custom.order) do
			entries[#entries + 1] = { id = id }
		end
		for _, entry in ipairs(self:SchemeRows(P.Roles.Scheme(ctx.role), piece, settings, ctx.role)) do
			-- keep scheme "When" defaults for rows the player did not change
			for _, mine in ipairs(entries) do
				if mine.id == entry.id and mine.when == nil then
					mine.when = entry.when
				end
			end
		end
	else
		if scheme == 'custom' then
			scheme = P.Roles.Scheme(ctx.role)
		end
		entries = self:SchemeRows(scheme, piece, settings, ctx.role)
	end

	local palette = P.Roles.Palette(settings.colorBlind, settings.threat and settings.threat.colors)
	local program = {
		piece = piece,
		rows = {},
		fallback = Color4(custom.fallback or self.FALLBACK[piece] or { 1, 1, 1, 1 }),
		events = {},
		messages = {},
		whenKeys = {},
		contextKeys = { role = true },
		scheme = scheme,
	}
	for _, entry in ipairs(entries) do
		local kind = self.kinds[entry.id]
		local off = custom.off and custom.off[entry.id]
		if kind and kind.available ~= false and not off then
			local row = { id = entry.id, kind = kind, expr = kind.expr }
			row.when = (custom.when and custom.when[entry.id]) or entry.when or kind.when or 'everywhere'
			local mine = custom.color and custom.color[entry.id]
			if kind.type == 'mapped' then
				local base = kind.default
				if entry.id == 'threat' or entry.id == 'offTank' or entry.id == 'petTank' then
					base = palette
				end
				row.colors = {}
				for state, color in pairs(base or {}) do
					row.colors[state] = Color4((type(mine) == 'table' and mine[state]) or color)
				end
				-- States the kind has no default for (class tokens) come only from the player
				if type(mine) == 'table' then
					for state, color in pairs(mine) do
						if row.colors[state] == nil and type(state) == 'string' and type(color) == 'table' then
							row.colors[state] = Color4(color)
						end
					end
				end
			else
				row.color = Color4((type(mine) == 'table' and mine[1] and mine) or kind.default or { 1, 1, 1, 1 })
			end
			if kind.type == 'curve' then
				program.overlay = program.overlay or row
			else
				program.rows[#program.rows + 1] = row
			end
			if row.id == 'unitInCombat' then
				program.readsCombat = true
			end
			if row.expr then
				P.Conditions:CollectEvents(row.expr, program.events, program.messages)
			end
			for _, e in ipairs(kind.events or {}) do
				program.events[e] = true
			end
			for _, m in ipairs(kind.messages or {}) do
				program.messages[m] = true
			end
			local deps = program.contextKeys
			if row.id == 'threat' or row.id == 'offTank' or row.id == 'petTank' then
				deps.inGroup, deps.petTank, deps.place = true, true, true
			elseif row.id == 'mobType' then
				deps.playerLevel = true
			end
			-- Context keys this row's "When" clause reads (Colors:ReadsContext)
			local when = row.when
			if when == 'combat' then
				program.whenKeys.inCombat = true
				deps.inCombat = true
				program.messages.CONTEXT_CHANGED = true
			elseif when ~= 'everywhere' and when ~= 'never' then
				program.whenKeys.place = true
				deps.place = true
				program.messages.CONTEXT_CHANGED = true
			end
		end
	end
	return program
end

---Whether a changed context key can affect one compiled program, or any program when omitted.
---@param keys? table<string, boolean>
---@param program? Plates.ColorProgram
---@return boolean
function Colors:ReadsContext(keys, program)
	if keys == nil then
		return true
	end
	if program then
		for key in pairs(program.contextKeys) do
			if keys[key] then
				return true
			end
		end
		return false
	end
	for i = 1, #self.PIECES do
		if self:ReadsContext(keys, self:Program(self.PIECES[i])) then
			return true
		end
	end
	return false
end

---Compiled program for a piece, cached until settings, role or context change. Preview plates
---pass their own context (role, group, tanks); those programs are cached per context table.
---@param piece string
---@param ctx? Plates.Context default P.Context
---@return Plates.ColorProgram
function Colors:Program(piece, ctx)
	local cache = self.programs
	if ctx and ctx ~= P.Context then
		cache = self.contextPrograms[ctx]
		if not cache then
			cache = {}
			self.contextPrograms[ctx] = cache
		end
	end
	local program = cache[piece]
	if not program then
		local settings = P.db and P.db.profile or {}
		program = self:Compile(piece, settings, ctx or P.Context)
		cache[piece] = program
	end
	return program
end

local function ResolveRow(row, env)
	local kind = row.kind
	if kind.type == 'boolean' then
		local result = true
		if row.expr then
			result = P.Conditions:TestExpr(row.expr, env)
		end
		if result == true then
			return true, row.color[1], row.color[2], row.color[3], row.color[4]
		end
		return result
	end
	if kind.Resolve then
		return kind.Resolve(env, row)
	end
	return false
end

local function FoldRowSecret(row, env, rSecret, gSecret, bSecret)
	local kind = row.kind
	if kind.type == 'boolean' then
		local color = row.color
		return P.Conditions:FoldColorSecret(row.expr, env, color[1], color[2], color[3], rSecret, gSecret, bSecret)
	end
	if kind.FoldSecret then
		return kind.FoldSecret(env, row, rSecret, gSecret, bSecret)
	end
	return rSecret, gSecret, bSecret
end

local pending = {}

---Work out the color and hand it straight to the sink named by method: 'SetStatusBarColor',
---'SetTextColor' or 'SetVertexColor' (the default). This is an approved sink
---entry point: callers never see a possibly-secret color.
---@param program Plates.ColorProgram
---@param env table { facts, ctx, states, src }
---@param target table
---@param method string
---@return integer|nil winner Index of the plain row that decided (nil = fallback)
---@return integer engineRows How many hidden rows could still override it
function Colors:Apply(program, env, target, method)
	local rows = program.rows
	local ctx = env.ctx or P.Context
	local fallback = program.fallback
	local r, g, b, a = fallback[1], fallback[2], fallback[3], fallback[4]
	local winner
	local count = 0
	for i = 1, #rows do
		local row = rows[i]
		if P.Conditions:WhenApplies(row.when, ctx) then
			local matched, mr, mg, mb, ma = ResolveRow(row, env)
			if matched == true then
				r, g, b, a = mr, mg, mb, ma or 1
				winner = i
				break
			elseif matched == nil then
				count = count + 1
				pending[count] = i
			end
		end
	end
	local rSecret, gSecret, bSecret = r, g, b
	for j = count, 1, -1 do
		rSecret, gSecret, bSecret = FoldRowSecret(rows[pending[j]], env, rSecret, gSecret, bSecret)
		pending[j] = nil
	end
	if method == 'SetStatusBarColor' then
		target:SetStatusBarColor(rSecret, gSecret, bSecret, a)
	elseif method == 'SetTextColor' then
		target:SetTextColor(rSecret, gSecret, bSecret, a)
	else
		target:SetVertexColor(rSecret, gSecret, bSecret, a)
	end
	return winner, count
end

---Plain explanation for the inspector: the winning row and the hidden rows that could override
---it, top first. Never reads a secret.
---@param program Plates.ColorProgram
---@param env table
---@return Plates.ColorRow|nil winner
---@return Plates.ColorRow[] maybe
function Colors:Explain(program, env)
	local maybe = {}
	local ctx = env.ctx or P.Context
	for i = 1, #program.rows do
		local row = program.rows[i]
		if P.Conditions:WhenApplies(row.when, ctx) then
			local matched = ResolveRow(row, env)
			if matched == true then
				return row, maybe
			elseif matched == nil then
				maybe[#maybe + 1] = row
			end
		end
	end
	return nil, maybe
end

---Plain sentence for a row ("Gray when someone else tagged it first").
---@param row Plates.ColorRow|{ id: string }
---@return string
function Colors:Sentence(row)
	local kind = self.kinds[row.id]
	if kind and kind.Sentence then
		return kind.Sentence(row)
	end
	return kind and kind.label or row.id
end

---Where a newly added row should go: before the first row that ranks lower in the role's
---scheme, never silently on top (3.2).
---@param piece string
---@param id string
---@param order string[] Current order
---@param settings table
---@param role string
---@return integer index
function Colors:SuggestInsertIndex(piece, id, order, settings, role)
	local rank = {}
	for index, entry in ipairs(self:SchemeRows(P.Roles.Scheme(role), piece, settings, role)) do
		rank[entry.id] = index
	end
	local mine = rank[id] or math.huge
	for index, other in ipairs(order) do
		local theirs = rank[other] or math.huge
		if theirs > mine then
			return index
		end
	end
	return #order + 1
end

---A step color curve for curve rows: transparent above the threshold, the row color at or below.
---@param color number[]
---@param threshold number 0-1 health fraction
---@return table|nil curve
function Colors:BuildStepCurve(color, threshold)
	if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then
		return nil
	end
	local curve = C_CurveUtil.CreateColorCurve()
	if curve.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then
		curve:SetType(Enum.LuaCurveType.Step)
	end
	curve:AddPoint(0, CreateColor(color[1], color[2], color[3], color[4] or 1))
	curve:AddPoint(threshold, CreateColor(color[1], color[2], color[3], 0))
	return curve
end

P:On('STORE_CHANGED', function(reasons)
	if reasons and (reasons.colors or reasons.look) then
		Colors:Invalidate()
	end
end, Colors)
P:On('CONTEXT_CHANGED', function(keys)
	-- Programs are compiled from the role only (its scheme and threat rows); other keys change
	-- what rows answer, not the programs
	if keys == nil or keys.role then
		Colors:Invalidate()
	end
end, Colors)

----------------------------------------------------------------------------------------------------
-- Row kinds
----------------------------------------------------------------------------------------------------

local function Boolean(id, label, condition, default, pieces, sentence, extra)
	local kind = { id = id, label = label, type = 'boolean', expr = condition and { id = condition } or nil, default = default, pieces = pieces }
	kind.Sentence = function()
		return sentence
	end
	for k, v in pairs(extra or {}) do
		kind[k] = v
	end
	Colors:RegisterKind(kind)
end

Boolean('tapped', L['Tapped'], 'tapped', { 0.5, 0.5, 0.5, 1 }, { 'health', 'name' }, L['Gray when someone else tagged it first'])
Boolean('quest', L['Quest'], 'quest', { 0.95, 0.8, 0.2, 1 }, { 'health', 'name', 'border' }, L['Yellow when it is part of a quest'], { when = 'world' })
Boolean('target', L['Target'], 'target', { 1, 1, 1, 1 }, { 'border', 'health', 'name' }, L['White when it is your target'])
Boolean('focus', L['Focus'], 'focus', { 0.35, 0.65, 1, 1 }, { 'border', 'health', 'name' }, L['Blue when it is your focus'])
Boolean('interruptReady', L['Interrupt ready'], 'interruptReady', { 0.3, 0.85, 0.35, 1 }, { 'cast', 'border' }, L['Green when your interrupt is ready'])
Boolean('notInterruptible', L['Cannot interrupt'], 'notInterruptible', { 0.55, 0.55, 0.55, 1 }, { 'cast' }, L['Gray when the cast cannot be interrupted'])
Boolean('importantCast', L['Important cast'], 'importantCast', { 0.85, 0.35, 1, 1 }, { 'cast', 'border' }, L['Purple when the cast is important'])
Boolean('aimedAtMe', L['Aimed at you'], 'aimedAtMe', { 1, 0.3, 0.3, 1 }, { 'cast', 'border' }, L['Red when the cast is aimed at you'])
Boolean('fixed', L['Fixed color'], nil, { 1, 1, 1, 1 }, { 'health', 'border', 'name', 'cast' }, L['Always this color'])
Boolean('unitInCombat', L['Fighting'], 'unitInCombat', { 0.9, 0.4, 0.2, 1 }, { 'health', 'border' }, L['Orange when it is fighting'], { available = false })
Boolean('auraMissing', L['My debuff is missing'], 'auraMissing', { 1, 0.5, 0.1, 1 }, { 'health', 'border' }, L['Orange when your debuff is missing'], { available = false })
Boolean('hasAura', L['Has a spell'], 'auraPresent', { 0.3, 0.8, 1, 1 }, { 'health', 'border' }, L['Blue when it has the spell you picked'], { available = false })

local function Readable(src, method, ...)
	if not src then
		return nil, false
	end
	return src[method](src, ...)
end

local threatWarned = false

Colors:RegisterKind({
	id = 'threat',
	label = L['Threat'],
	type = 'mapped',
	pieces = { 'health', 'border', 'name' },
	default = P.Roles.PALETTE,
	events = { 'UNIT_THREAT_LIST_UPDATE', 'UNIT_THREAT_SITUATION_UPDATE' },
	messages = { 'CONTEXT_CHANGED' },
	Resolve = function(env, row)
		local facts = env.facts or {}
		if not facts.canAttack or facts.isPlayer then
			return false
		end
		local status, readable = Readable(env.src, 'ThreatStatusPlain')
		if not readable then
			-- S2 fallback: no threat color when the game hides threat
			if not threatWarned then
				threatWarned = true
				P.log.info('Threat is hidden by the game here; threat colors are off for those plates')
			end
			return false
		end
		local ctx = env.ctx or P.Context
		local state = P.Roles.ThreatState(ctx.role, status, ctx.inGroup)
		local color = state and row.colors[state]
		if not color then
			return false
		end
		return true, color[1], color[2], color[3], color[4]
	end,
	Sentence = function()
		return L['Threat colors for your role']
	end,
})

local function TankRow(id, label, sentence, Tanks)
	Colors:RegisterKind({
		id = id,
		label = label,
		type = 'mapped',
		pieces = { 'health', 'border', 'name' },
		default = P.Roles.PALETTE,
		events = { 'UNIT_THREAT_LIST_UPDATE', 'UNIT_THREAT_SITUATION_UPDATE' },
		messages = { 'TANKS_CHANGED', 'CONTEXT_CHANGED' },
		Resolve = function(env, row)
			local facts = env.facts or {}
			local src = env.src
			if not src or not facts.canAttack or facts.isPlayer then
				return false
			end
			local ctx = env.ctx or P.Context
			if ctx.role ~= 'tank' then
				-- Damage and healers see "you are about to pull" before "the tank has it" (P.Threat.State)
				local status, known = src:ThreatStatusPlain()
				if known and type(status) == 'number' and status >= 1 then
					return false
				end
			end
			local unknown = false
			local tanks = Tanks(ctx)
			for i = 1, #tanks do
				local tanking, readable = src:IsTankingPlain(tanks[i])
				if not readable then
					unknown = true
				elseif tanking then
					local color = row.colors[id == 'petTank' and 'pet' or 'offTank']
					return true, color[1], color[2], color[3], color[4]
				end
			end
			if unknown then
				return nil
			end
			return false
		end,
		-- Folding the same color once per tank gives "any tank holds it"
		FoldSecret = function(env, row, rSecret, gSecret, bSecret)
			local src = env.src
			local color = row.colors[id == 'petTank' and 'pet' or 'offTank']
			local tanks = Tanks(env.ctx or P.Context)
			local Secret = P.Secret
			for i = 1, #tanks do
				-- A readable answer already settled in Resolve; only hidden ones are folded
				local _, readable = src:IsTankingPlain(tanks[i])
				if not readable then
					local tankingSecret = src:IsTankingSecret(tanks[i])
					rSecret = Secret.ChooseValue(tankingSecret, color[1], rSecret)
					gSecret = Secret.ChooseValue(tankingSecret, color[2], gSecret)
					bSecret = Secret.ChooseValue(tankingSecret, color[3], bSecret)
				end
			end
			return rSecret, gSecret, bSecret
		end,
		Sentence = function()
			return sentence
		end,
	})
end

local NO_TANKS = {}
TankRow('offTank', L['Another tank'], L['Blue when another tank is holding it'], function(ctx)
	return ctx.tanks or NO_TANKS
end)
local PET = { 'pet' }
TankRow('petTank', L['Your pet'], L['Purple when your pet is holding it'], function(ctx)
	return ctx.petTank and PET or NO_TANKS
end)

Colors:RegisterKind({
	id = 'mobType',
	label = L['Mob type'],
	type = 'mapped',
	pieces = { 'health', 'border', 'name' },
	when = 'dungeons',
	default = {
		boss = { 0.95, 0.35, 0.1, 1 },
		miniboss = { 0.75, 0.3, 0.9, 1 },
		caster = { 0.25, 0.55, 1, 1 },
		elite = { 0.9, 0.7, 0.2, 1 },
		normal = { 0.8, 0.2, 0.2, 1 },
		minor = { 0.55, 0.55, 0.55, 1 },
	},
	events = { 'UNIT_CLASSIFICATION_CHANGED' },
	Resolve = function(env, row)
		local facts = env.facts or {}
		if facts.isPlayer or not P.Situation.IsHostile(facts) then
			return false
		end
		local mobType = facts.mobType or P.Situation.MobType(facts, env.ctx)
		local color = row.colors[mobType]
		if not color then
			return false
		end
		return true, color[1], color[2], color[3], color[4]
	end,
	Sentence = function()
		return L['Mob type colors: boss, mini-boss, caster, elite, normal, minor']
	end,
})

Colors:RegisterKind({
	id = 'class',
	label = L['Class'],
	type = 'mapped',
	pieces = { 'health', 'name', 'border' },
	default = {},
	Resolve = function(env, row)
		local facts = env.facts or {}
		if not facts.isPlayer then
			return false
		end
		local token = facts.classToken
		if not token then
			-- The game hides this player's class (identity restricted): the engine colors it from
			-- the hidden token (FoldSecret), where the client takes one and gives a token at all
			local src = env.src
			if src and not src.isSample and P.Caps:Get('classColor') then
				local classSecret = src:ClassTokenSecret()
				if type(classSecret) ~= 'nil' then
					return nil
				end
			end
			return false
		end
		local mine = row.colors[token]
		if mine then
			return true, mine[1], mine[2], mine[3], mine[4]
		end
		local color = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(token)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[token])
		if not color then
			return false
		end
		return true, color.r, color.g, color.b, 1
	end,
	-- Every player has a class, so with the token hidden the row still wins over the rows below it:
	-- the class color from C_ClassColor (which takes a hidden token) replaces their color. A color
	-- table the game will not let us index leaves the rows below in place.
	FoldSecret = function(env, _, rSecret, gSecret, bSecret)
		local src = env.src
		if not (src and C_ClassColor and C_ClassColor.GetClassColor) then
			return rSecret, gSecret, bSecret
		end
		local classSecret = src:ClassTokenSecret()
		if type(classSecret) == 'nil' then
			return rSecret, gSecret, bSecret
		end
		local colorSecret = C_ClassColor.GetClassColor(classSecret)
		return P.Secret.ColorChannels(colorSecret, rSecret, gSecret, bSecret)
	end,
	Sentence = function()
		return L['Class colors for players']
	end,
})

Colors:RegisterKind({
	id = 'reaction',
	label = L['Reaction'],
	type = 'mapped',
	pieces = { 'health', 'name', 'border' },
	default = {
		hostile = { 0.85, 0.2, 0.2, 1 },
		neutral = { 0.95, 0.8, 0.2, 1 },
		friendly = { 0.25, 0.8, 0.3, 1 },
	},
	events = { 'UNIT_FACTION' },
	Resolve = function(env, row)
		local reaction = env.facts and env.facts.reaction
		if not reaction then
			return false
		end
		local state = reaction <= 3 and 'hostile' or reaction == 4 and 'neutral' or 'friendly'
		local color = row.colors[state]
		return true, color[1], color[2], color[3], color[4]
	end,
	Sentence = function()
		return L['Red for enemies, yellow for neutral, green for friends']
	end,
})

Colors:RegisterKind({
	id = 'lowHealth',
	label = L['Low health'],
	type = 'curve',
	pieces = { 'health' },
	default = { 1, 0.85, 0.1, 1 },
	threshold = 0.35,
	Sentence = function()
		return L['Yellow when health is low']
	end,
})
