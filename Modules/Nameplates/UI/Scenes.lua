local _, ns = ...
local P = ns.Plates
local L = P.L

-- Preview scenes for the options side panel, gallery cards and setup cards (5.6). Every plate in a
-- scene is a real Plate built with Plate.New(holder, true, ctx) and filled with
-- Plate:BindSample(Source.NewSample(sample)), so previews run the same parts as real plates.
-- Preview plates stay insecure, never call Unit* and are never anchored to real plates.
--
-- Scenes (by page, 5.6; Scenes.DEFS):
--   pull         Style and Sharing pages: P.Data.PULL in a slightly staggered column, faint labels
--   raidBoss     a boss with its adds, the way a raid pull looks (scene picker, Phase 5)
--   battleground enemy and friendly players (scene picker)
--   world        out in the world, alone: a quest mob, a tagged mob, a rare (scene picker)
--   focus        Customize: one plate of the "Preview as" kind at fit scale, plus two small 1x
--                plates below for the other states (not your target and faded; casting)
--   auras        Auras: the focus plate alone, every aura row filled with sample icons
--   rows         Colors: one plate per row of the open color list, labeled with the row's
--                sentence; past 8 rows it fits to height down to 0.6, then "+N more"
--   kinds        Who and where: one plate per kind in its assigned style and Show mode; Hidden
--                draws a faint outline with the word Hidden
-- Fitting: Scenes:Render measures each plate with Merge.PartRects (pure geometry, never read back
-- from frames), picks a scale for the canvas and scales each preview plate's root (preview plates
-- only; live plates never SetScale). Labels stay at 1x so they stay readable.
-- Context: preview plates never read P.Context. Each scene builds one with
-- Scenes.PreviewContext(fields) and passes it to Plate.New / plate:SetContext, so the "pull" scene
-- can show a tank's view in a group whatever the player is doing. Colors caches one program set
-- per context table, so contexts are kept per scene and only remade when the player's role changes.
-- Samples: P.Data.Samples plus Scenes.SAMPLES (same shape). Variants (not target, casting, every
-- aura row filled, Show all parts) are copies made once per sample and kept.

---@class Plates.SceneDef
---@field id string
---@field samples? string[] Sample ids, top to bottom
---@field stagger? number Horizontal stagger in pixels
---@field gap number Vertical gap
---@field labels? boolean
---@field context? table PreviewContext fields
---@field label? string Name in the scene picker
---@field picker? boolean Offered in the toolbar's scene picker

---@class Plates.Scenes
local Scenes = {
	pools = setmetatable({}, { __mode = 'k' }),
	contexts = {},
	variants = setmetatable({}, { __mode = 'k' }),
	resolvedCache = setmetatable({}, { __mode = 'k' }),
}
P.Scenes = Scenes

Scenes.LABEL_SAMPLE_ICONS = L['sample icons']
Scenes.LABEL_HEIGHT = 12
Scenes.MAX_ROWS = 8
Scenes.MIN_ROW_SCALE = 0.6
Scenes.MARGIN = 12

Scenes.KINDS = { 'enemyNPC', 'enemyPlayer', 'friendlyNPC', 'friendlyPlayer', 'minor' }
Scenes.KIND_LABELS = {
	enemyNPC = L['Enemy NPC'],
	enemyPlayer = L['Enemy player'],
	friendlyNPC = L['Friendly NPC'],
	friendlyPlayer = L['Friendly player'],
	minor = L['Minor enemy'],
}

----------------------------------------------------------------------------------------------------
-- Scene samples (raid boss, battleground, out in the world)
----------------------------------------------------------------------------------------------------

local ICON = P.Data.SampleIcons or {}

local function Facts(extra)
	local facts = { reaction = 2, canAttack = true, isPlayer = false, playerControlled = false, isMinion = false, classification = 'normal', effectiveLevel = 62, isCaster = false, tapDenied = false }
	for k, v in pairs(extra or {}) do
		facts[k] = v
	end
	return facts
end

local function Player(classToken, hostile)
	return {
		reaction = hostile and 2 or 5,
		canAttack = hostile and true or false,
		isPlayer = true,
		playerControlled = true,
		classification = 'normal',
		effectiveLevel = 62,
		classToken = classToken,
	}
end

---@type table<string, Plates.Sample>
Scenes.SAMPLES = {
	raidBoss = {
		id = 'raidBoss',
		label = L['Your target'],
		name = L['The Hollow King'],
		facts = Facts({ classification = 'worldboss', isBoss = true, effectiveLevel = -1 }),
		health = 63,
		healthMax = 100,
		absorb = 6,
		raidMarker = 8,
		threat = 3,
		cast = { kind = 'channel', name = L['Shadow Bolt'], icon = ICON.shadowBolt, duration = 4, important = true, notInterruptible = true },
		auras = { myDebuffs = { { icon = ICON.pain, duration = 18, remaining = 9, spellId = 589 }, { icon = ICON.sunder, duration = 30, remaining = 20, stacks = 3, spellId = 7386, mine = false } } },
		states = { target = true },
	},
	raidAdd = {
		id = 'raidAdd',
		label = L['Add'],
		name = L['Bound Shade'],
		facts = Facts({ classification = 'elite', isCaster = true }),
		health = 54,
		healthMax = 100,
		threat = 2,
		kickReady = true,
		raidMarker = 7,
		cast = { kind = 'cast', name = L['Frostbolt'], icon = ICON.frostbolt, duration = 2.5 },
	},
	raidAddOther = {
		id = 'raidAddOther',
		label = L['Another tank has it'],
		name = L['Bound Shade'],
		facts = Facts({ classification = 'elite' }),
		health = 31,
		healthMax = 100,
		threat = 0,
		tankedByOther = true,
	},
	raidMinor = {
		id = 'raidMinor',
		label = L['Minor enemy'],
		name = L['Void Spark'],
		facts = Facts({ classification = 'minus', effectiveLevel = 60 }),
		health = 100,
		healthMax = 100,
	},
	bgHealer = {
		id = 'bgHealer',
		label = L['Your target'],
		name = L['Selwyn'],
		facts = Player('PRIEST', true),
		health = 58,
		healthMax = 100,
		absorb = 12,
		kickReady = true,
		faction = 'Horde',
		pvp = true,
		cast = { kind = 'cast', name = L['Flash Heal'], icon = ICON.shield, duration = 2 },
		auras = { removable = { { icon = ICON.shield, duration = 15, remaining = 11, dispel = 'Magic', spellId = 17 } } },
		states = { target = true },
	},
	bgWarrior = {
		id = 'bgWarrior',
		label = L['Enemy player'],
		name = L['Throgg'],
		facts = Player('WARRIOR', true),
		health = 34,
		healthMax = 100,
		faction = 'Horde',
		pvp = true,
		auras = { crowdControl = { { icon = ICON.polymorph, duration = 8, remaining = 6, spellId = 118 } } },
	},
	bgRogue = {
		id = 'bgRogue',
		label = L['Enemy player'],
		name = L['Vexa'],
		facts = Player('ROGUE', true),
		health = 91,
		healthMax = 100,
		faction = 'Horde',
		pvp = true,
	},
	bgPet = {
		id = 'bgPet',
		label = L['Pet'],
		name = L['Felhunter'],
		facts = { reaction = 2, canAttack = true, isPlayer = false, playerControlled = true, isMinion = true, classification = 'normal', effectiveLevel = 62 },
		health = 80,
		healthMax = 100,
	},
	bgFriend = {
		id = 'bgFriend',
		label = L['Friendly player'],
		name = L['Arannis'],
		facts = Player('PALADIN', false),
		health = 100,
		healthMax = 100,
		faction = 'Alliance',
		pvp = true,
	},
	worldQuest = {
		id = 'worldQuest',
		label = L['Your target'],
		name = L['Cave Lurker'],
		facts = Facts({ isQuest = true, questBoss = false }),
		health = 66,
		healthMax = 100,
		threat = 3,
		quest = true,
		kickReady = true,
		cast = { kind = 'cast', name = L['Fireball'], icon = ICON.fireball, duration = 3, aimedAtMe = true, target = L['You'] },
		auras = { myDebuffs = { { icon = ICON.corruption, duration = 14, remaining = 7, spellId = 172 } } },
		states = { target = true },
	},
	worldTapped = {
		id = 'worldTapped',
		label = L['Someone else tagged it'],
		name = L['Snarling Wolf'],
		facts = Facts({ tapDenied = true }),
		health = 40,
		healthMax = 100,
	},
	worldRare = {
		id = 'worldRare',
		label = L['Rare'],
		name = L['Old Ironbark'],
		facts = Facts({ classification = 'rareelite', effectiveLevel = 63 }),
		health = 100,
		healthMax = 100,
		title = L['Ancient of the Grove'],
	},
}

----------------------------------------------------------------------------------------------------
-- Scene definitions
----------------------------------------------------------------------------------------------------

local GROUP = { inGroup = true, groupSize = 5, tanks = { 'party1' } }

Scenes.DEFS = {
	pull = { id = 'pull', samples = P.Data.PULL, stagger = 6, gap = 14, labels = true, label = L['Pull'], picker = true, context = GROUP },
	raidBoss = {
		id = 'raidBoss',
		samples = { 'raidBoss', 'raidAdd', 'raidAddOther', 'raidMinor', 'friendlyPlayer' },
		stagger = 6,
		gap = 14,
		labels = true,
		label = L['Raid boss'],
		picker = true,
		context = { place = 'raid', inGroup = true, groupSize = 20, tanks = { 'raid1' } },
	},
	battleground = {
		id = 'battleground',
		samples = { 'bgHealer', 'bgWarrior', 'bgRogue', 'bgPet', 'bgFriend' },
		stagger = 6,
		gap = 14,
		labels = true,
		label = L['Battleground'],
		picker = true,
		context = { place = 'pvp', inGroup = true, groupSize = 10, tanks = {} },
	},
	world = {
		id = 'world',
		samples = { 'worldQuest', 'worldTapped', 'worldRare', 'neutral', 'friendlyNPC' },
		stagger = 6,
		gap = 14,
		labels = true,
		label = L['Out in the world'],
		picker = true,
		context = { place = 'world', inGroup = false, groupSize = 1, tanks = {} },
	},
	focus = { id = 'focus', gap = 14, labels = true, context = GROUP },
	auras = { id = 'auras', gap = 14, labels = false, context = GROUP },
	rows = { id = 'rows', gap = 10, labels = true, context = GROUP },
	kinds = { id = 'kinds', gap = 14, labels = true, context = GROUP },
}

---Scenes the toolbar's scene picker offers, in order.
Scenes.PICKER = { 'pull', 'raidBoss', 'battleground', 'world' }

---A sample by id: P.Data.Samples first, then the scene samples.
---@param id string|nil
---@return Plates.Sample|nil
function Scenes.Sample(id)
	if not id then
		return nil
	end
	return (P.Data.Samples and P.Data.Samples[id]) or Scenes.SAMPLES[id]
end

----------------------------------------------------------------------------------------------------
-- Contexts
----------------------------------------------------------------------------------------------------

---A context for preview plates: the live context's place and level with the scene's own role,
---group and tanks on top. Keep the returned table (Colors caches programs per context table).
---@param fields? table role, inGroup, tanks, petTank, hasTarget, place, ...
---@return Plates.Context
function Scenes.PreviewContext(fields)
	local live = P.Context or {}
	local ctx = {
		place = live.place or 'world',
		inCombat = false,
		resting = false,
		role = live.role or 'damage',
		inGroup = true,
		groupSize = 5,
		tanks = {},
		petTank = false,
		playerLevel = live.playerLevel or 1,
		hasTarget = true,
		kickSpell = live.kickSpell,
	}
	for k, v in pairs(fields or {}) do
		ctx[k] = v
	end
	return ctx
end

---The kept context for a scene. A new table is made when the player's role changes, because
---color programs are cached per context table.
---@param def Plates.SceneDef
---@return Plates.Context
function Scenes:ContextFor(def)
	local live = P.Context or {}
	local role = live.role or 'damage'
	local kept = self.contexts[def.id]
	if kept and kept.role == role then
		kept.playerLevel = live.playerLevel or kept.playerLevel
		return kept
	end
	local ctx = Scenes.PreviewContext(def.context)
	ctx.role = role
	self.contexts[def.id] = ctx
	return ctx
end

----------------------------------------------------------------------------------------------------
-- Sample variants (made once per sample and kept)
----------------------------------------------------------------------------------------------------

---A copy of a sample changed by fn, kept per sample and key.
---@param sample Plates.Sample
---@param key string
---@param fn fun(copy: Plates.Sample)
---@return Plates.Sample
function Scenes:Variant(sample, key, fn)
	local list = self.variants[sample]
	if not list then
		list = {}
		self.variants[sample] = list
	end
	local copy = list[key]
	if not copy then
		copy = P.util.Copy(sample)
		copy.facts = copy.facts or {}
		fn(copy)
		list[key] = copy
	end
	return copy
end

local ALL_AURAS = {
	myDebuffs = {
		{ icon = ICON.pain, duration = 18, remaining = 12, spellId = 589 },
		{ icon = ICON.corruption, duration = 14, remaining = 4, spellId = 172 },
		{ icon = ICON.sunder, duration = 30, remaining = 22, stacks = 5, spellId = 7386, mine = false },
	},
	removable = { { icon = ICON.shield, duration = 15, remaining = 9, dispel = 'Magic', spellId = 17 } },
	crowdControl = { { icon = ICON.polymorph, duration = 8, remaining = 5, spellId = 118 } },
	custom = { { icon = ICON.fireball, duration = 10, remaining = 6, spellId = 133 } },
}

---Every part that is usually hidden shows: raid marker, quest icon, focus mark and absorb (the
---eye toggle, "Show all parts").
---@param sample Plates.Sample
---@return Plates.Sample
function Scenes:Revealed(sample)
	return self:Variant(sample, 'reveal', function(copy)
		copy.raidMarker = copy.raidMarker or 8
		copy.quest = true
		copy.facts.isQuest = true
		copy.absorb = copy.absorb or 10
		copy.states = copy.states or {}
		copy.states.focus = true
	end)
end

---The focus plate with every aura row filled with sample icons (Auras page).
---@param sample Plates.Sample
---@return Plates.Sample
function Scenes:WithAllAuras(sample)
	return self:Variant(sample, 'auras', function(copy)
		copy.auras = P.util.Copy(ALL_AURAS)
		copy.states = copy.states or {}
		copy.states.target = true
	end)
end

---Not the target, no cast: the faded plate under the focus plate.
---@param sample Plates.Sample
---@return Plates.Sample
function Scenes:NotTarget(sample)
	return self:Variant(sample, 'notTarget', function(copy)
		copy.states = {}
		copy.cast = nil
		copy.label = L['Not your target']
	end)
end

---Not the target, casting.
---@param sample Plates.Sample
---@return Plates.Sample
function Scenes:Casting(sample)
	return self:Variant(sample, 'casting', function(copy)
		copy.states = {}
		copy.cast = copy.cast or { kind = 'cast', name = L['Shadow Bolt'], icon = ICON.shadowBolt, duration = 3 }
		copy.label = L['Casting']
	end)
end

----------------------------------------------------------------------------------------------------
-- Rows scene: a sample that makes each color row win
----------------------------------------------------------------------------------------------------

-- First guess per row kind; Scenes:RowSample checks it and tries other samples when a row above
-- would win instead.
Scenes.ROW_GUESS = {
	tapped = 'worldTapped',
	quest = 'questMob',
	threat = 'threatLosing',
	offTank = 'offTanked',
	petTank = 'offTanked',
	mobType = 'eliteMiniBoss',
	class = 'enemyPlayer',
	reaction = 'neutral',
	target = 'casterTarget',
	focus = 'casterTarget',
	lowHealth = 'lowHealth',
	interruptReady = 'casterTarget',
	notInterruptible = 'uninterruptible',
	importantCast = 'boss',
	aimedAtMe = 'enemyPlayer',
	fixed = 'casterTarget',
}

local ROW_CANDIDATES = {
	'casterTarget',
	'eliteMiniBoss',
	'minorGray',
	'offTanked',
	'enemyPlayer',
	'friendlyPlayer',
	'friendlyNPC',
	'boss',
	'neutral',
	'questMob',
	'threatSafe',
	'threatLosing',
	'threatLost',
	'uninterruptible',
	'worldTapped',
	'worldRare',
	'raidAdd',
	'bgHealer',
}

---Explain env for a sample (plain: samples are never secret).
local function RowEnv(sample, ctx)
	local facts = {}
	local src = P.Source.NewSample(sample)
	src:ReadFacts(facts)
	return { facts = facts, ctx = ctx, states = sample.states or {}, src = src }
end

---A sample whose color for this piece comes from the row, so the plate shows the row's color.
---@param program Plates.ColorProgram
---@param row Plates.ColorRow
---@param ctx Plates.Context
---@return Plates.Sample sample
---@return boolean wins False when no sample lets this row win (a row above always wins)
function Scenes:RowSample(program, row, ctx)
	local guess = Scenes.Sample(Scenes.ROW_GUESS[row.id] or 'casterTarget') or P.Data.Samples.casterTarget
	if row.id == 'focus' then
		guess = self:Variant(guess, 'focusOnly', function(copy)
			copy.states = { focus = true }
		end)
	end
	local candidates = { guess }
	for _, id in ipairs(ROW_CANDIDATES) do
		local sample = Scenes.Sample(id)
		if sample and sample ~= guess then
			candidates[#candidates + 1] = sample
		end
	end
	for _, sample in ipairs(candidates) do
		local ok, winner = pcall(P.Colors.Explain, P.Colors, program, RowEnv(sample, ctx))
		if ok and winner == row then
			return sample, true
		end
	end
	return guess, false
end

----------------------------------------------------------------------------------------------------
-- Pools
----------------------------------------------------------------------------------------------------

---@param canvas table
---@return table pool
function Scenes:Pool(canvas)
	local pool = self.pools[canvas]
	if not pool then
		local holder = CreateFrame('Frame', nil, canvas)
		holder:SetPoint('CENTER', canvas, 'CENTER', 0, 0)
		holder:SetSize(1, 1)
		pool = { holder = holder, slots = {}, labels = {}, outlines = {}, used = 0, usedLabels = 0, usedOutlines = 0 }
		self.pools[canvas] = pool
	end
	return pool
end

local function Label(pool, text, x, y)
	pool.usedLabels = pool.usedLabels + 1
	local label = pool.labels[pool.usedLabels]
	if not label then
		label = pool.holder:CreateFontString(nil, 'OVERLAY')
		label:SetFont(P.services.FontPath(), 9, '')
		label:SetTextColor(1, 1, 1, 0.55)
		label:SetJustifyH('LEFT')
		pool.labels[pool.usedLabels] = label
	end
	label:SetText(text or '')
	label:ClearAllPoints()
	label:SetPoint('BOTTOMLEFT', pool.holder, 'CENTER', x, y)
	label:Show()
	return label
end

local WHITE = 'Interface\\Buttons\\WHITE8X8'

---A faint outline with the word Hidden (Show mode 'hidden').
local function Outline(pool, cx, cy, w, h)
	pool.usedOutlines = pool.usedOutlines + 1
	local box = pool.outlines[pool.usedOutlines]
	if not box then
		box = CreateFrame('Frame', nil, pool.holder)
		local edges = {}
		for i = 1, 4 do
			local edge = box:CreateTexture(nil, 'BORDER')
			edge:SetTexture(WHITE)
			edge:SetVertexColor(1, 1, 1, 0.3)
			edges[i] = edge
		end
		edges[1]:SetPoint('TOPLEFT')
		edges[1]:SetPoint('TOPRIGHT')
		edges[1]:SetHeight(1)
		edges[2]:SetPoint('BOTTOMLEFT')
		edges[2]:SetPoint('BOTTOMRIGHT')
		edges[2]:SetHeight(1)
		edges[3]:SetPoint('TOPLEFT')
		edges[3]:SetPoint('BOTTOMLEFT')
		edges[3]:SetWidth(1)
		edges[4]:SetPoint('TOPRIGHT')
		edges[4]:SetPoint('BOTTOMRIGHT')
		edges[4]:SetWidth(1)
		box.edges = edges
		box.text = box:CreateFontString(nil, 'OVERLAY')
		box.text:SetFont(P.services.FontPath(), 10, '')
		box.text:SetTextColor(1, 1, 1, 0.45)
		box.text:SetPoint('CENTER')
		box.text:SetText(L['Hidden'])
		pool.outlines[pool.usedOutlines] = box
	end
	box:ClearAllPoints()
	box:SetSize(math.max(1, w), math.max(1, h))
	box:SetPoint('CENTER', pool.holder, 'CENTER', cx, cy)
	box:Show()
	return box
end

---The pooled plate for slot i, on this scene's context.
local function Slot(pool, i, ctx, sample)
	local slot = pool.slots[i]
	if not slot then
		slot = { plate = P.Plate.New(pool.holder, true, ctx), src = P.Source.NewSample(sample), ctx = ctx }
		pool.slots[i] = slot
	elseif slot.ctx ~= ctx then
		slot.plate:SetContext(ctx)
		slot.ctx = ctx
	end
	return slot
end

----------------------------------------------------------------------------------------------------
-- Style resolution for a sample
----------------------------------------------------------------------------------------------------

local scratch = { deps = {} }
local EMPTY = {}

---Resolve a style table that is not in the registry (a pasted string), kept per table.
---@param style table A validated style
---@param situation string
---@param sizeKey string
---@return Plates.ResolvedStyle|nil
function Scenes:ResolveTable(style, situation, sizeKey)
	local list = self.resolvedCache[style]
	if not list then
		list = {}
		self.resolvedCache[style] = list
	end
	local Merge = P.Styles.Merge
	local key = (situation or '') .. '|' .. (sizeKey or 'medium') .. '|' .. tostring(Merge.generation)
	local resolved = list[key]
	if not resolved then
		local ok, result = pcall(Merge.ResolveRaw, style, nil, situation, sizeKey, P.hostLook)
		if not ok or type(result) ~= 'table' then
			return nil
		end
		resolved = result
		resolved.id = style.id or 'preview'
		resolved.key = 'preview:' .. tostring(style) .. '|' .. key
		list[key] = resolved
	end
	return resolved
end

---What a sample looks like with the player's settings: situation, Show mode and resolved style.
---@param sample Plates.Sample
---@param ctx Plates.Context
---@param opts table
---@param forced? string A kind to draw as the edited style ("Preview as"), always in full
---@return string situation
---@return string mode 'full' | 'name' | 'hidden'
---@return Plates.ResolvedStyle|nil resolved
function Scenes:Assign(sample, ctx, opts, forced)
	local Situation = P.Situation
	local facts = sample.facts or EMPTY
	local situation = forced or Situation.Classify(facts)
	local settings = (P.db and P.db.profile) or EMPTY
	local env = { facts = facts, ctx = ctx, states = sample.states or EMPTY }
	local out = Situation.Assign(situation, env, settings, scratch)
	local mode, styleId, sizeKey = out.mode, out.style, out.size
	if opts.sizeKey then
		sizeKey = opts.sizeKey
	end
	if forced then
		mode = 'full'
		styleId = opts.focusStyleId or settings.style or 'host'
	end
	local resolved
	if mode ~= 'name' and opts.resolveShown then
		-- The gallery's hovered card or a pasted style (nil: the player's own style)
		local ok, shown = pcall(opts.resolveShown, situation, sizeKey)
		resolved = ok and shown or nil
	end
	if not resolved and mode ~= 'name' and opts.style then
		resolved = self:ResolveTable(opts.style, situation, sizeKey)
	end
	if not resolved then
		if mode ~= 'name' and opts.styleId then
			styleId = opts.styleId
		end
		resolved = P.Styles.Merge:Resolve(styleId, situation, sizeKey)
	end
	return situation, mode, resolved
end

-- Parts that draw around others rather than taking room
local OVERLAY_KINDS = { highlight = true, glow = true, region = true }

---Bounds of a resolved style around the plate center (pure geometry).
---@param resolved Plates.ResolvedStyle
---@param states? table
---@return number left
---@return number right
---@return number top
---@return number bottom
function Scenes.Bounds(resolved, states)
	local rects = P.Styles.Merge.PartRects(resolved)
	local W, H = resolved.width, resolved.height
	local left, right, top, bottom = -W / 2, W / 2, H / 2, -H / 2
	for _, id in ipairs(resolved.order) do
		local spec = resolved.parts[id]
		local r = rects[id]
		if r and not OVERLAY_KINDS[spec.kind] and (not spec.state or (states and states[spec.state])) then
			left, right = math.min(left, r.left), math.max(right, r.right)
			top, bottom = math.max(top, r.top), math.min(bottom, r.bottom)
		end
	end
	-- Room for highlights and glows around the plate
	return left - 4, right + 4, top + 4, bottom - 4
end

----------------------------------------------------------------------------------------------------
-- Rendering
----------------------------------------------------------------------------------------------------

---@class Plates.SceneItem
---@field plate? Plates.Plate Nil for a hidden kind (outline only)
---@field outline? table
---@field sample Plates.Sample
---@field situation string
---@field mode string
---@field resolved? Plates.ResolvedStyle
---@field label? string
---@field scale number
---@field focus? boolean The large plate of the focus and auras scenes
---@field row? Plates.ColorRow Rows scene: the row this plate shows
---@field rowWins? boolean
---@field kind? string Kinds scene: the kind this plate stands for
---@field cx number Center of the plate on the scene holder (canvas units)
---@field cy number

---@class Plates.SceneResult
---@field id string
---@field width number Bounds of everything drawn, in canvas units
---@field height number
---@field scale number Scale used for the column (focus: the large plate's scale)
---@field plates Plates.Plate[]
---@field items Plates.SceneItem[]
---@field more integer Rows left out ("+N more")
---@field context Plates.Context

---Build the item list for a scene.
local function Items(self, def, ctx, opts)
	local items = {}
	local id = def.id
	local function Add(sample, item)
		item.sample = opts.revealAll and self:Revealed(sample) or sample
		items[#items + 1] = item
		return item
	end
	if id == 'focus' or id == 'auras' then
		local kind = opts.kind or 'enemyNPC'
		local kindSamples = P.Data.KIND_SAMPLES or EMPTY
		local base = Scenes.Sample(kindSamples[kind]) or P.Data.Samples.casterTarget
		local big
		if id == 'auras' then
			big = self:WithAllAuras(base)
		else
			big = self:Variant(base, 'focusTarget', function(copy)
				copy.states = copy.states or {}
				copy.states.target = true
			end)
		end
		Add(big, { forced = kind, focus = true })
		if id == 'focus' then
			Add(self:NotTarget(base), { forced = kind, label = L['Not your target'], fade = true })
			Add(self:Casting(base), { forced = kind, label = L['Casting'] })
		end
	elseif id == 'rows' then
		local program = P.Colors:Program(opts.piece or 'health', ctx)
		for _, row in ipairs(program.rows) do
			local sample, wins = self:RowSample(program, row, ctx)
			local label = P.Colors:Sentence(row)
			if not wins then
				label = label .. ' ' .. L['(a row above wins here)']
			end
			Add(sample, { row = row, rowWins = wins, label = label })
		end
	elseif id == 'kinds' then
		local kindSamples = P.Data.KIND_SAMPLES or EMPTY
		for _, kind in ipairs(Scenes.KINDS) do
			local sample = Scenes.Sample(kindSamples[kind]) or P.Data.Samples.casterTarget
			Add(sample, { kind = kind, label = Scenes.KIND_LABELS[kind] })
		end
	else
		for _, sampleId in ipairs(def.samples or EMPTY) do
			local sample = Scenes.Sample(sampleId)
			if sample then
				Add(sample, { label = sample.label })
			end
		end
	end
	return items
end

---Resolve one item: its situation, Show mode, style and bounds.
local function ResolveItem(self, item, ctx, opts)
	local situation, mode, resolved
	if item.kind then
		-- Who and where shows each kind in its own Show mode and style
		local settings = (P.db and P.db.profile) or EMPTY
		local env = { facts = item.sample.facts or EMPTY, ctx = ctx, states = item.sample.states or EMPTY }
		local out = P.Situation.Assign(item.kind, env, settings, scratch)
		situation, mode = item.kind, out.mode
		resolved = P.Styles.Merge:Resolve(out.style, item.kind, opts.sizeKey or out.size)
		if item.label and mode == 'name' then
			item.label = item.label .. ' (' .. L['Names only'] .. ')'
		end
	else
		situation, mode, resolved = self:Assign(item.sample, ctx, opts, item.forced)
	end
	item.situation, item.mode, item.resolved = situation, mode, resolved
	if resolved then
		item.l, item.r, item.t, item.b = Scenes.Bounds(resolved, item.sample.states)
	else
		item.l, item.r, item.t, item.b = -60, 60, 8, -8
	end
	item.w, item.h = item.r - item.l, item.t - item.b
end

---Lay a plate out and fill it from its sample, keeping a running cast loop when nothing changed.
local function Fill(slot, item)
	local plate, src = slot.plate, slot.src
	plate.previewFade = item.fade or nil
	local relaid = plate:ApplyStyle(item.resolved)
	if slot.sample ~= item.sample or not plate.src then
		if plate.src then
			plate:Unbind()
		end
		src:SetSample(item.sample)
		slot.sample = item.sample
		plate:BindSample(src)
	elseif relaid then
		plate:UpdateAll('FULL')
		plate:ApplyEmphasis(true)
	else
		plate:Refresh({ colors = true })
		plate:ApplyEmphasis(true)
	end
end

---Pick scales for the items so they fit the canvas. Returns the column scale, the label height
---to use and how many rows were left out.
local function FitItems(def, items, cw, ch, opts)
	local margin = Scenes.MARGIN
	local labelH = def.labels and Scenes.LABEL_HEIGHT or 0
	if def.id == 'focus' or def.id == 'auras' then
		local big = items[1]
		local small = 0
		for i = 2, #items do
			small = small + items[i].h + labelH + def.gap
			items[i].scale = 1
		end
		local availH = ch - margin * 2 - small
		local scale = math.min((cw - margin * 2) / math.max(1, big.w), availH / math.max(1, big.h), opts.maxScale or 2.5)
		scale = math.max(0.5, scale)
		big.scale = scale
		return scale, labelH, 0
	end
	local maxScale = opts.maxScale or 1.25
	local minScale = def.id == 'rows' and Scenes.MIN_ROW_SCALE or 0.5
	local function Fit(withLabels)
		local sumH, maxW = 0, 1
		for _, item in ipairs(items) do
			sumH = sumH + item.h
			maxW = math.max(maxW, item.w)
		end
		local fixed = (withLabels and labelH or 0) * #items + def.gap * math.max(0, #items - 1)
		return math.min(maxScale, (ch - margin * 2 - fixed) / math.max(1, sumH), (cw - margin * 2 - (def.stagger or 0) * 2) / maxW)
	end
	local scale = Fit(labelH > 0)
	local more = 0
	if def.id == 'rows' and scale < minScale then
		-- Keep what fits at the smallest scale and say how many are left
		while #items > 1 and Fit(true) < minScale do
			items[#items] = nil
			more = more + 1
		end
		scale = Fit(true)
	elseif labelH > 0 and scale < 0.9 then
		-- Labels go first when the column is short of room
		local without = Fit(false)
		if without > scale + 0.05 then
			labelH = 0
			scale = without
		end
	end
	scale = math.max(minScale, scale)
	for _, item in ipairs(items) do
		item.scale = scale
	end
	return scale, labelH, more
end

---Draw a scene on a canvas (preview plates are pooled per canvas).
---@param canvas table
---@param sceneId string
---@param opts? { width?: number, height?: number, styleId?: string, style?: table, resolveShown?: fun(situation: string, sizeKey: string): Plates.ResolvedStyle|nil, kind?: string, piece?: string, revealAll?: boolean, focusStyleId?: string, sizeKey?: string, maxScale?: number }
---@return Plates.SceneResult
function Scenes:Render(canvas, sceneId, opts)
	opts = opts or EMPTY
	local def = self.DEFS[sceneId] or self.DEFS.pull
	local ctx = self:ContextFor(def)
	local pool = self:Pool(canvas)
	pool.usedLabels, pool.usedOutlines = 0, 0
	local cw, ch = opts.width, opts.height
	if not cw or not ch then
		local w, h = canvas:GetSize()
		cw = cw or P.Secret.Plain(w) or 338
		ch = ch or P.Secret.Plain(h) or 416
	end
	local items = Items(self, def, ctx, opts)
	for _, item in ipairs(items) do
		ResolveItem(self, item, ctx, opts)
	end
	local scale, labelH, more = FitItems(def, items, cw, ch, opts)

	local total = 0
	for i, item in ipairs(items) do
		total = total + item.h * item.scale + ((item.label and labelH > 0) and labelH or 0)
		if i > 1 then
			total = total + def.gap
		end
	end
	if more > 0 then
		total = total + Scenes.LABEL_HEIGHT + 4
	end

	local y = total / 2
	local maxW = 0
	local plates = {}
	local slotIndex = 0
	for i, item in ipairs(items) do
		if i > 1 then
			y = y - def.gap
		end
		local s = item.scale
		local stagger = def.stagger and ((i % 2 == 1) and -def.stagger or def.stagger) or 0
		local cx = stagger - (item.l + item.r) / 2 * s
		if item.label and labelH > 0 then
			Label(pool, item.label, stagger - item.w * s / 2, y - labelH)
			y = y - labelH
		end
		local cy = y - item.t * s
		item.cx, item.cy = cx, cy
		if item.mode == 'hidden' or not item.resolved then
			local w = (item.resolved and item.resolved.width or 120) * s
			local h = (item.resolved and item.resolved.height or 14) * s
			item.outline = Outline(pool, cx, cy, w, h)
		else
			slotIndex = slotIndex + 1
			local slot = Slot(pool, slotIndex, ctx, item.sample)
			local plate = slot.plate
			plate.root:SetScale(s)
			plate.root:ClearAllPoints()
			plate.root:SetPoint('CENTER', pool.holder, 'CENTER', cx / s, cy / s)
			Fill(slot, item)
			item.plate = plate
			plates[#plates + 1] = plate
		end
		y = y - item.h * s
		maxW = math.max(maxW, item.w * s + math.abs(stagger) * 2)
	end
	if more > 0 then
		Label(pool, string.format(L['+%d more'], more), -maxW / 2, y - Scenes.LABEL_HEIGHT - 4)
	end
	-- Plates, labels and outlines this scene did not use
	for i = slotIndex + 1, #pool.slots do
		local slot = pool.slots[i]
		if slot.plate.src then
			slot.plate:Unbind()
		end
		slot.sample = nil
	end
	for i = pool.usedLabels + 1, #pool.labels do
		pool.labels[i]:Hide()
	end
	for i = pool.usedOutlines + 1, #pool.outlines do
		pool.outlines[i]:Hide()
	end
	pool.holder:Show()
	pool.used = slotIndex
	return { id = def.id, width = maxW, height = total, scale = scale, plates = plates, items = items, more = more, context = ctx }
end

---Hide every preview plate drawn on a canvas and stop their sample casts.
---@param canvas table
function Scenes:Release(canvas)
	local pool = self.pools[canvas]
	if not pool then
		return
	end
	for _, slot in ipairs(pool.slots) do
		if slot.plate.src then
			slot.plate:Unbind()
		end
		slot.sample = nil
	end
	for _, label in ipairs(pool.labels) do
		label:Hide()
	end
	for _, box in ipairs(pool.outlines) do
		box:Hide()
	end
	pool.holder:Hide()
	pool.used = 0
end
