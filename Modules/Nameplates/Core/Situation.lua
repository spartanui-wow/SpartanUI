local _, ns = ...
local P = ns.Plates

-- Situations change the layout; states (target, focus, mouseover, casting) only change emphasis.
-- Classify and Assign are pure functions over plain facts and a context table, tested headless
-- as truth tables. Only non-secret facts are used (Decision 9). Players never see the word
-- "situation": the options call these "kinds of plates" and the "When" list.

---@class Plates.Facts Plain facts about a unit, read by Source:ReadFacts (nil = unknown)
---@field reaction? integer 1-8 (1-3 hostile, 4 neutral, 5-8 friendly)
---@field canAttack? boolean
---@field isPlayer? boolean
---@field playerControlled? boolean
---@field isMinion? boolean
---@field classification? string 'worldboss'|'rareelite'|'elite'|'rare'|'normal'|'trivial'|'minus'
---@field effectiveLevel? integer -1 means skull level
---@field isBoss? boolean Retail and Forever only
---@field isLieutenant? boolean Retail and Forever only
---@field isCaster? boolean Has a mana bar
---@field tapDenied? boolean
---@field questBoss? boolean
---@field isQuest? boolean Quest objective (tooltip or questBoss)
---@field widgetsOnly? boolean
---@field isGameObject? boolean
---@field classToken? string Readable class token (players), nil when hidden
---@field inCombat? boolean Readable combat flag, nil when hidden
---@field mobType? string Set by Situation.MobType

---@class Plates.Context Shared, plain state of the player and the place (one table, updated by the Driver)
---@field place 'world'|'dungeon'|'raid'|'delve'|'scenario'|'arena'|'battleground'
---@field instanceType string
---@field difficultyID integer
---@field inInstance boolean
---@field inCombat boolean
---@field resting boolean
---@field role 'tank'|'damage'|'healer'
---@field inGroup boolean
---@field groupSize integer
---@field tanks string[] Unit tokens of other group tanks
---@field petTank boolean The player has a pet that can hold threat
---@field playerLevel integer
---@field challengeActive boolean A Mythic+ run is active
---@field kickSpell? integer Interrupt spell id in use (Data/Kicks)
---@field hasTarget boolean

---@class Plates.Situation
local Situation = {}
P.Situation = Situation

---The one shared context table. The Driver keeps it current (place, combat, role, group, kick
---spell) and fires CONTEXT_CHANGED; everything else only reads it.
---@type Plates.Context
P.Context = {
	place = 'world',
	instanceType = 'none',
	difficultyID = 0,
	inInstance = false,
	inCombat = false,
	resting = false,
	role = 'damage',
	inGroup = false,
	groupSize = 1,
	tanks = {},
	petTank = false,
	playerLevel = 1,
	challengeActive = false,
	kickSpell = nil,
	hasTarget = false,
}

---Every kind of plate, in options order.
Situation.KINDS = { 'enemyNPC', 'enemyPlayer', 'friendlyNPC', 'friendlyPlayer', 'minor' }

---Every place, in options order.
Situation.PLACES = { 'world', 'dungeon', 'raid', 'delve', 'scenario', 'arena', 'battleground' }

---Built-in defaults, used when the player has no entry (sparse storage).
Situation.DEFAULT_ASSIGN = { minor = 'mini' }
Situation.DEFAULT_MODES = { friendlyNPC = 'hidden', friendlyPlayer = 'name' }

---Style used for 'name' mode.
Situation.NAME_STYLE = 'namesOnly'

---Facts each decision reads, so a change to one fact re-runs Assign only where it matters.
Situation.CLASSIFY_FACTS = { 'reaction', 'canAttack', 'isPlayer', 'playerControlled', 'isMinion', 'classification' }

---@param facts Plates.Facts
---@return boolean
function Situation.IsHostile(facts)
	if facts.canAttack then
		return true
	end
	local reaction = facts.reaction
	return reaction ~= nil and reaction <= 3
end

---The kind of plate for these facts.
---@param facts Plates.Facts
---@return 'enemyNPC'|'enemyPlayer'|'friendlyNPC'|'friendlyPlayer'|'minor'
function Situation.Classify(facts)
	local hostile = Situation.IsHostile(facts)
	if facts.isPlayer then
		return hostile and 'enemyPlayer' or 'friendlyPlayer'
	end
	if not hostile then
		return 'friendlyNPC'
	end
	local class = facts.classification
	if class == 'minus' or class == 'trivial' or facts.isMinion or facts.playerControlled then
		return 'minor'
	end
	return 'enemyNPC'
end

---Mob type for color rows: 'boss'|'miniboss'|'caster'|'elite'|'normal'|'minor'.
---Retail and Forever use UnitIsBossMob/UnitIsLieutenant; the Classic family uses classification
---and level (boss = world boss or skull level, mini-boss = elite above the player's level).
---@param facts Plates.Facts
---@param ctx? Plates.Context
---@return string
function Situation.MobType(facts, ctx)
	local class = facts.classification
	if class == 'minus' or class == 'trivial' or facts.isMinion then
		return 'minor'
	end
	local level = facts.effectiveLevel
	if facts.isBoss or class == 'worldboss' or level == -1 then
		return 'boss'
	end
	local elite = class == 'elite' or class == 'rareelite'
	if facts.isLieutenant then
		return 'miniboss'
	end
	if facts.isLieutenant == nil and elite and ctx and ctx.playerLevel and level and level > ctx.playerLevel then
		return 'miniboss'
	end
	if facts.isCaster then
		return 'caster'
	end
	if elite then
		return 'elite'
	end
	return 'normal'
end

---Place from instance information (pure). Housing instances count as the open world, a delve
---is difficulty 208.
---@param inInstance boolean
---@param instanceType string|nil 'none'|'party'|'raid'|'scenario'|'arena'|'pvp'|'neighborhood'|'interior'
---@param difficultyID integer|nil
---@return string place
function Situation.PlaceFrom(inInstance, instanceType, difficultyID)
	if not inInstance then
		return 'world'
	end
	if difficultyID == 208 then
		return 'delve'
	end
	if instanceType == 'party' then
		return 'dungeon'
	elseif instanceType == 'raid' then
		return 'raid'
	elseif instanceType == 'scenario' then
		return 'scenario'
	elseif instanceType == 'arena' then
		return 'arena'
	elseif instanceType == 'pvp' then
		return 'battleground'
	end
	return 'world'
end

---Fill the place fields of the context from the game (no unit reads). Unit-based fields (role,
---tanks, level) are filled by P.Source.ReadPlayerContext.
---@param ctx Plates.Context
---@return Plates.Context
function Situation.ReadPlace(ctx)
	local inInstance, instanceType = false, 'none'
	if IsInInstance then
		inInstance, instanceType = IsInInstance()
	end
	local difficultyID = 0
	if inInstance and GetInstanceInfo then
		difficultyID = select(3, GetInstanceInfo()) or 0
	end
	ctx.inInstance = inInstance and true or false
	ctx.instanceType = instanceType or 'none'
	ctx.difficultyID = difficultyID
	ctx.place = Situation.PlaceFrom(ctx.inInstance, ctx.instanceType, difficultyID)
	ctx.resting = IsResting and IsResting() and true or false
	ctx.challengeActive = (C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive()) and true or false
	return ctx
end

---@class Plates.Assignment Result of Assign (reuse one per plate)
---@field style string Style id to draw ('namesOnly' when mode is 'name')
---@field mode 'full'|'name'|'hidden'
---@field size 'small'|'medium'|'large'
---@field whenIndex integer|nil Index of the "When" entry that decided, if any
---@field deps table<string, boolean> Facts and context fields this decision read

---@class Plates.WhenEntry One "When" special case (profile.when, first match wins)
---@field conditions? table[] { id = conditionId, args = any } all must match (plain conditions only)
---@field kinds? string[] Kinds of plate it applies to (nil = all)
---@field style? string
---@field size? 'small'|'medium'|'large'
---@field mode? 'full'|'name'|'hidden'
---@field off? boolean

local function Mark(deps, list)
	if deps and list then
		for i = 1, #list do
			deps[list[i]] = true
		end
	end
end

---Decide style, size and mode for a kind of plate (pure).
---Order: profile.when (top to bottom, first match), then profile.assign / profile.modes, then the
---defaults in code. Mode 'name' always draws the names-only style.
---@param situation string
---@param env table { facts = Plates.Facts, ctx = Plates.Context, states = table } (Conditions env)
---@param settings table Profile view: style, size, assign, modes, when
---@param out Plates.Assignment Filled and returned (deps is wiped first)
---@return Plates.Assignment
function Situation.Assign(situation, env, settings, out)
	out.deps = out.deps or {}
	P.util.Wipe(out.deps)
	Mark(out.deps, Situation.CLASSIFY_FACTS)
	local style = (settings.assign and settings.assign[situation]) or Situation.DEFAULT_ASSIGN[situation] or settings.style or 'host'
	local mode = (settings.modes and settings.modes[situation]) or Situation.DEFAULT_MODES[situation] or 'full'
	local size = settings.size or 'medium'
	out.whenIndex = nil

	local when = settings.when
	if type(when) == 'table' then
		for index = 1, #when do
			local entry = when[index]
			if not entry.off and Situation.EntryApplies(entry, situation, env, out.deps) then
				style = entry.style or style
				size = entry.size or size
				mode = entry.mode or mode
				out.whenIndex = index
				break
			end
		end
	end

	if mode == 'name' then
		style = Situation.NAME_STYLE
	end
	out.style, out.mode, out.size = style, mode, size
	return out
end

---True when a "When" entry matches. Entries that use a condition the engine decides (secret on
---Retail and Forever) cannot change layout and never match here.
---@param entry Plates.WhenEntry
---@param situation string
---@param env table
---@param deps? table<string, boolean>
---@return boolean
function Situation.EntryApplies(entry, situation, env, deps)
	if entry.kinds then
		local found = false
		for i = 1, #entry.kinds do
			if entry.kinds[i] == situation then
				found = true
			end
		end
		if not found then
			return false
		end
	end
	local Conditions = P.Conditions
	for _, clause in ipairs(entry.conditions or {}) do
		local cond = Conditions:Get(clause.id)
		if not cond or cond.kind ~= 'plain' then
			return false
		end
		Mark(deps, cond.facts)
		local result = cond.Test(env, clause.args)
		if clause.negate then
			result = result == false
		end
		if result ~= true then
			return false
		end
	end
	return true
end
