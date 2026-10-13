local _, ns = ...
local P = ns.Plates
local L = P.L
local Secret = P.Secret

-- Aura rows by Lua scan (kind 'auras', 4, 6.6): live plates on clients without secrets (Mists,
-- Titan, TBC, Era), and every preview on every client (sample icons). A client with secrets and
-- no aura containers (a failed probe, or the containers capability forced off) shows no aura rows
-- (Scan.Limit says why).
--
-- Rows (spec.row):
--   myDebuffs     my debuffs (player or pet), plus tank debuffs from anyone on enemies
--                 (Data/TankDebuffs.lua, every rank); crowd control is left to its own row, like
--                 the container's !CROWD_CONTROL. "Only mine" off shows every debuff.
--   removable     enemy buffs that can be stolen or dispelled (stealable, Magic or Enrage), plus
--                 buffs the game marks important when the row's `important` option is on. Era's
--                 filter table has no IMPORTANT or DISPELLABLE token, so this reads aura fields.
--   crowdControl  crowd control, decided three ways (any one is enough):
--                   1. Data/CrowdControl.lua by spell id (every rank), the backstop;
--                   2. C_Spell.IsSpellCrowdControl, the test the game's own Classic nameplates
--                      use (probe 'spellCrowdControl');
--                   3. the CROWD_CONTROL filter token, only where 2 is missing (probe 'ccFilter',
--                      then a runtime check: a call that errors, or a result holding a known tank
--                      debuff, turns it off for the session with Caps:Record) (S0).
--   custom        only what the "Always show" list names.
-- Lists (profile.auras[row] = { on, always = { [spellID] = 'mine'|'any' }, never = { ... },
-- onlyMine, important }; profile.auras.tankDebuffs = { on, always, never }) are read through
-- P.Store on every scan. List entries also match by spell name, so one entry covers every rank.
-- Never beats always. A plain array of ids counts as 'any' (the same reading as AuraRows).
--
-- Reads: src:AuraByIndexPlain(index, filter), src:AuraInstanceIDsPlain(filter, rule, direction)
-- and src:AuraByInstancePlain(id) (all plain on these clients). Where the client sorts aura lists
-- (Caps 'auraInstanceIDs') Blizzard sorts and we filter in that order; otherwise Lua sorts.
-- UNIT_AURA's updateInfo skips updates that cannot change the row. No table is ever keyed by
-- auraInstanceID: shown ids live in a list and are compared one by one.
-- Icons come from the widget's own pool (grown in Layout, never in Update). Timers use a duration
-- text binding where Caps 'durationText' says so (off on Mists by quirk), else plain math on one
-- shared Scheduler task, which also drives the pandemic glow (my auras with 30% or less left,
-- drawn with P.GlowLib's pandemic look).
-- Previews: src.isSample; draw src:SampleAuras(row) with cooldown swipes paused at a fixed time.
-- A scene can set plate.fillAuras = true to fill empty rows with stock sample icons (Auras page).
-- This file also answers the auraPresent / auraMissing conditions with plain reads on clients
-- without secrets and on previews (the "My debuff is missing" reminder on the Classic family).

---@class Plates.AuraScan
local Scan = {}
P.AuraScan = Scan

Scan.MAX_SCAN = 40
Scan.PANDEMIC = (P.GlowLib and P.GlowLib.PANDEMIC) or 0.3
Scan.TICK = 0.2
Scan.TICK_ID = 'aurasScanTimers'

local WHITE = 'Interface\\Buttons\\WHITE8X8'

---Border colors by dispel type (the game's standard debuff colors, plus Enrage). The game names
---the Enrage type with an empty string.
Scan.DISPEL_COLORS = {
	Magic = { 0.2, 0.6, 1 },
	Curse = { 0.6, 0, 1 },
	Disease = { 0.6, 0.4, 0 },
	Poison = { 0, 0.6, 0 },
	Enrage = { 1, 0.35, 0 },
	none = { 0.8, 0, 0 },
}
Scan.DISPEL_COLORS[''] = Scan.DISPEL_COLORS.Enrage
Scan.BORDER_COLOR = { 0, 0, 0 }
Scan.PANDEMIC_COLOR = (P.GlowLib and P.GlowLib.SOURCE_COLORS and P.GlowLib.SOURCE_COLORS.pandemic) or { 1, 0.85, 0.25, 1 }

local MINE_SOURCES = { player = true, pet = true, vehicle = true }

----------------------------------------------------------------------------------------------------
-- Settings and lists
----------------------------------------------------------------------------------------------------

-- Spell names by id (plain, the same for every rank)
local nameCache = {}

---@param spellID number
---@return string|nil
function Scan.SpellName(spellID)
	if type(spellID) ~= 'number' then
		return nil
	end
	local name = nameCache[spellID]
	if name then
		return name
	end
	if C_Spell and C_Spell.GetSpellName then
		name = C_Spell.GetSpellName(spellID)
	elseif GetSpellInfo then
		name = GetSpellInfo(spellID)
	end
	if type(name) == 'string' and name ~= '' then
		nameCache[spellID] = name
		return name
	end
	return nil
end

-- Index per stored list, rebuilt whenever the list table changes (Store writes lists whole)
local indexByList = setmetatable({}, { __mode = 'k' })
local EMPTY_INDEX = { ids = {}, names = {} }

---Who an entry is for: 'mine' or 'any' (true and other values count as 'any', false as off).
local function Who(value)
	if value == 'mine' then
		return 'mine'
	elseif value == false or value == nil then
		return nil
	end
	return 'any'
end

---An index for a spell list: { ids = { [id] = 'mine'|'any' }, names = { [name] = 'mine'|'any' } }.
---Takes the SpellList map { [spellID] = 'mine'|'any' } or a plain array of ids (all 'any'), so
---one entry covers every rank through its name.
---@param list table|nil
---@return table index
function Scan.ListIndex(list)
	if type(list) ~= 'table' then
		return EMPTY_INDEX
	end
	local cached = indexByList[list]
	if cached then
		return cached
	end
	local index, complete = { ids = {}, names = {} }, true
	for key, value in pairs(list) do
		local id, who
		if type(value) == 'number' then
			id, who = value, 'any'
		elseif type(key) == 'number' then
			id, who = key, Who(value)
		end
		if who and type(id) == 'number' and id > 0 then
			index.ids[id] = who
			local name = Scan.SpellName(id)
			if name then
				-- 'any' wins when two ranks of one spell disagree
				if index.names[name] ~= 'any' then
					index.names[name] = who
				end
			else
				complete = false
			end
		end
	end
	-- A name the client has not loaded yet is looked up again next time
	if complete then
		indexByList[list] = index
	end
	return index
end

---What a list index says about an aura: 'mine', 'any' or nil, by id first, then by name.
---@param index table
---@param aura table
---@return string|nil
local function ListWho(index, aura)
	local who = index.ids[aura.spellId]
	if who == nil and aura.name then
		who = index.names[aura.name]
	end
	return who
end

---One row's settings, read from the profile now (never kept between scans).
---@param row string
---@param out? table Reused table
---@return table settings { on, onlyMine, important, always, never } (always and never are indexes)
function Scan.RowSettings(row, out)
	out = out or {}
	-- Read straight from the live profile (this runs on every scan), never kept between scans
	local profile = P.db and P.db.profile
	local auras = profile and profile.auras
	local stored = type(auras) == 'table' and auras[row] or nil
	if type(stored) ~= 'table' then
		stored = nil
	end
	out.on = not stored or stored.on ~= false
	out.onlyMine = not stored or stored.onlyMine ~= false
	out.important = stored ~= nil and stored.important == true
	out.always = Scan.ListIndex(stored and stored.always)
	out.never = Scan.ListIndex(stored and stored.never)
	return out
end

---True when a list index names the aura for this caster ('mine' needs it to be mine).
---@param index table
---@param aura table
---@param mine boolean
---@return boolean
local function Listed(index, aura, mine)
	local who = ListWho(index, aura)
	if who == 'mine' then
		return mine
	end
	return who ~= nil
end

---Cast by the player or the player's pet or vehicle (plain on the scan path).
---@param aura table
---@return boolean
function Scan.IsMine(aura)
	if aura.isFromPlayerOrPlayerPet then
		return true
	end
	local source = aura.sourceUnit
	return type(source) == 'string' and MINE_SOURCES[source] == true
end

---Hostile for aura rows: can be attacked, or a hostile reaction (Situation.Classify's rule).
---@param facts table|nil
---@return boolean
function Scan.IsHostile(facts)
	if type(facts) ~= 'table' then
		return false
	end
	if facts.canAttack == true then
		return true
	end
	local reaction = facts.reaction
	return type(reaction) == 'number' and reaction <= 3
end

----------------------------------------------------------------------------------------------------
-- Crowd control and removable buffs
----------------------------------------------------------------------------------------------------

-- The game's own answer per spell id (plain on the scan path, the same for every unit)
local spellFlagCache = {}

---C_Spell.IsSpellCrowdControl for a spell id, cached. False where the client lacks it.
---@param spellID any
---@return boolean
function Scan.SpellIsCrowdControl(spellID)
	if type(spellID) ~= 'number' or not P.Caps:Get('spellCrowdControl') then
		return false
	end
	local known = spellFlagCache[spellID]
	if known ~= nil then
		return known
	end
	local ok, result = pcall(C_Spell.IsSpellCrowdControl, spellID)
	known = ok and Secret.CanAccess(result) and result == true or false
	spellFlagCache[spellID] = known
	return known
end

---Is this aura instance in the CROWD_CONTROL token result (a list, compared one by one)?
---@param env table
---@param id any
---@return boolean
local function InToken(env, id)
	local ids = env.tokenIDs
	if id == nil or not ids then
		return false
	end
	for i = 1, #ids do
		if ids[i] == id then
			return true
		end
	end
	return false
end

---Crowd control by the spell list, the game's spell flag or the filter token.
---@param aura table
---@param env? table Scan env (tokenIDs)
---@return boolean
function Scan.IsCrowdControl(aura, env)
	local id = aura.spellId
	if P.Data.CrowdControl[id] then
		return true
	end
	if Scan.SpellIsCrowdControl(id) then
		return true
	end
	return env ~= nil and InToken(env, aura.auraInstanceID)
end

---A buff someone can take away: stolen (Spellsteal), or dispelled as Magic or Enrage.
---@param aura table
---@param important? boolean Also count buffs the game marks important
---@return boolean
function Scan.IsRemovable(aura, important)
	local dispel = aura.dispelName
	if aura.isStealable == true or dispel == 'Magic' or dispel == 'Enrage' or dispel == '' then
		return true
	end
	if important and P.Caps:Get('important') and type(aura.spellId) == 'number' then
		local ok, result = pcall(C_Spell.IsSpellImportant, aura.spellId)
		return ok and Secret.CanAccess(result) and result == true or false
	end
	return false
end

----------------------------------------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------------------------------------

local function AcceptMine(aura, env)
	local settings = env.settings
	local mine = Scan.IsMine(aura)
	if Listed(settings.never, aura, mine) then
		return false
	end
	if Listed(settings.always, aura, mine) then
		return true
	end
	-- Crowd control has its own row (the container group is HARMFUL|PLAYER|...|!CROWD_CONTROL)
	if Scan.IsCrowdControl(aura, env) then
		return false
	end
	if mine then
		return true
	end
	local tank = env.tank
	if env.hostile and tank and tank.on and not Listed(tank.never, aura, false) and (P.Data.TankDebuffs[aura.spellId] ~= nil or Listed(tank.always, aura, false)) then
		return true
	end
	return settings.onlyMine == false
end

local function AcceptRemovable(aura, env)
	local settings = env.settings
	local mine = Scan.IsMine(aura)
	if Listed(settings.never, aura, mine) then
		return false
	end
	if Listed(settings.always, aura, mine) then
		return true
	end
	return Scan.IsRemovable(aura, settings.important)
end

local function AcceptCrowdControl(aura, env)
	local settings = env.settings
	local mine = Scan.IsMine(aura)
	if Listed(settings.never, aura, mine) then
		return false
	end
	if Listed(settings.always, aura, mine) then
		return true
	end
	return Scan.IsCrowdControl(aura, env)
end

local function AcceptCustom(aura, env)
	local settings = env.settings
	local mine = Scan.IsMine(aura)
	if Listed(settings.never, aura, mine) then
		return false
	end
	return Listed(settings.always, aura, mine)
end

---Row definitions for the scan path. harmful and helpful pick the polarities scanned; token rows
---read the CROWD_CONTROL filter where the game's spell flag is missing. Accept(aura, env) is also
---used by the purge glow (Glow.lua), with env = { settings, tank, tokenIDs, hostile }.
---@type table<string, { harmful?: boolean, helpful?: boolean, enemyOnly?: boolean, token?: boolean, Accept: fun(aura: table, env: table): boolean }>
Scan.ROWS = {
	myDebuffs = { harmful = true, token = true, Accept = AcceptMine },
	removable = { helpful = true, enemyOnly = true, Accept = AcceptRemovable },
	crowdControl = { harmful = true, token = true, Accept = AcceptCrowdControl },
	custom = { harmful = true, helpful = true, Accept = AcceptCustom },
}

local SORT_RULES = { default = 'Default', time = 'ExpirationOnly', name = 'NameOnly' }

---Blizzard sort rule for a sort setting, or nil when the client cannot sort aura lists.
---@param sort string|nil
---@return integer|nil rule
---@return integer|nil direction
local function BlizzardSort(sort)
	if not P.Caps:Get('auraInstanceIDs') then
		return nil
	end
	local rules = Enum and Enum.UnitAuraSortRule
	local directions = Enum and Enum.UnitAuraSortDirection
	local rule = rules and rules[SORT_RULES[sort or 'default'] or 'Default']
	if not rule then
		return nil
	end
	return rule, directions and directions.Normal or 0
end

local sortNow = 0

local function Remaining(aura)
	local expiration = aura.expirationTime or 0
	if (aura.duration or 0) <= 0 or expiration <= 0 then
		return math.huge
	end
	return expiration - sortNow
end

local function ByTime(a, b)
	return Remaining(a) < Remaining(b)
end

local function ByName(a, b)
	return (a.name or '') < (b.name or '')
end

---Collect the auras of one polarity that a row accepts, in sort order. Returns true when the
---client sorted them.
---@param src Plates.Source
---@param filter string
---@param sort string|nil
---@param accept function
---@param env table
---@param out table
---@return boolean sorted
local function Gather(src, filter, sort, accept, env, out)
	local rule, direction = BlizzardSort(sort)
	if rule then
		local ok, ids = pcall(src.AuraInstanceIDsPlain, src, filter, rule, direction)
		if not ok then
			-- The sorted list failed on this client: read by index from now on
			P.Caps:Record('auraInstanceIDs', false)
			P.log.warning('Sorted aura lists failed here; aura rows read auras one by one: ' .. tostring(ids))
			ids = nil
		end
		if type(ids) == 'table' then
			for i = 1, #ids do
				local aura = src:AuraByInstancePlain(ids[i])
				if aura and accept(aura, env) then
					out[#out + 1] = aura
				end
			end
			return true
		end
	end
	for index = 1, Scan.MAX_SCAN do
		local aura = src:AuraByIndexPlain(index, filter)
		if not aura then
			break
		end
		if accept(aura, env) then
			out[#out + 1] = aura
		end
	end
	return false
end

---Turn the CROWD_CONTROL token off for this session.
---@param why string
local function DropToken(why)
	P.Caps:Record('ccFilter', false)
	P.log.warning(why)
end

---Should rows read the CROWD_CONTROL filter? Only where the game's spell flag is missing.
---@return boolean
function Scan.UsesToken()
	return P.Caps:Get('ccFilter') and not P.Caps:Get('spellCrowdControl')
end

---Fill env.tokenIDs from the CROWD_CONTROL filter, where rows read it.
---@param env table
---@param src Plates.Source
local function GatherToken(env, src)
	local ids = env.tokenIDs
	P.util.Wipe(ids)
	if not Scan.UsesToken() then
		return
	end
	local filter = 'HARMFUL|' .. ((AuraUtil and AuraUtil.AuraFilters and AuraUtil.AuraFilters.CrowdControl) or 'CROWD_CONTROL')
	for index = 1, Scan.MAX_SCAN do
		local ok, aura = pcall(src.AuraByIndexPlain, src, index, filter)
		if not ok then
			P.util.Wipe(ids)
			DropToken('The game refused the crowd control filter; using the spell list only')
			return
		end
		if not aura then
			break
		end
		-- A token that matches a known tank debuff is being ignored by the client
		if P.Data.TankDebuffs[aura.spellId] then
			P.util.Wipe(ids)
			DropToken('The crowd control filter matched a debuff that is not crowd control; using the spell list only')
			return
		end
		ids[#ids + 1] = aura.auraInstanceID
	end
end

local scanEnv = { settings = {}, tank = {}, tokenIDs = {}, hostile = false }

---Scan the unit and return the auras the row shows, in order (widget.picks, reused).
---@param widget table
---@param src Plates.Source
---@return table picks
function Scan.Collect(widget, src)
	local spec = widget.spec
	local picks = widget.picks
	P.util.Wipe(picks)
	local row = spec.row or 'myDebuffs'
	local def = Scan.ROWS[row]
	local env = scanEnv
	Scan.RowSettings(row, env.settings)
	if not def or not env.settings.on or (spec.max or 6) <= 0 then
		return picks
	end
	env.hostile = widget.hostile == true
	if def.enemyOnly and not env.hostile then
		return picks
	end
	Scan.RowSettings('tankDebuffs', env.tank)
	if def.token then
		GatherToken(env, src)
	else
		P.util.Wipe(env.tokenIDs)
	end
	local sorted = true
	if def.harmful then
		sorted = Gather(src, 'HARMFUL', spec.sort, def.Accept, env, picks) and sorted
	end
	if def.helpful then
		sorted = Gather(src, 'HELPFUL', spec.sort, def.Accept, env, picks) and sorted
	end
	local merged = def.harmful and def.helpful
	if spec.sort == 'time' and (merged or not sorted) then
		sortNow = P.services.GetTime()
		table.sort(picks, ByTime)
	elseif spec.sort == 'name' and (merged or not sorted) then
		table.sort(picks, ByName)
	end
	return picks
end

---Why a row cannot show on this client, as a sentence for the player, or nil when it can. For
---option badges and the designer.
---@param row string
---@return string|nil
function Scan.Limit(row)
	if not P.Caps:Get('secrets') then
		if row == 'crowdControl' and not (P.Caps:Get('spellCrowdControl') or P.Caps:Get('ccFilter')) then
			return L['This game version only knows crowd control from a built-in spell list.']
		end
		return nil
	end
	if not P.Caps:Get('containers') then
		return L['The game hides aura details here, so aura rows cannot show on real plates.']
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- Icons
----------------------------------------------------------------------------------------------------

---Where icon i (0-based) sits in the holder: point, x, y. Rows wrap toward the free side of the
---part's own anchor point (a row hanging from a BOTTOM point wraps up).
---@param spec table
---@param i integer
---@return string point
---@return number x
---@return number y
function Scan.IconPoint(spec, i)
	local size, gap = spec.size or 20, spec.spacing or 2
	local perRow = math.max(1, math.min(spec.perRow or spec.max or 6, 40))
	local col, line = i % perRow, math.floor(i / perRow)
	local step = size + gap
	local grow = spec.grow or 'RIGHT'
	local anchorPoint = (type(spec.anchor) == 'table' and spec.anchor[1]) or 'CENTER'
	if grow == 'UP' or grow == 'DOWN' then
		local toRight = string.find(anchorPoint, 'RIGHT', 1, true) == nil
		local vertical = grow == 'UP' and 'BOTTOM' or 'TOP'
		local horizontal = toRight and 'LEFT' or 'RIGHT'
		return vertical .. horizontal, (toRight and 1 or -1) * line * step, (grow == 'UP' and 1 or -1) * col * step
	end
	local up = string.find(anchorPoint, 'BOTTOM', 1, true) ~= nil
	local vertical = up and 'BOTTOM' or 'TOP'
	local horizontal = grow == 'LEFT' and 'RIGHT' or 'LEFT'
	return vertical .. horizontal, (grow == 'LEFT' and -1 or 1) * col * step, (up and 1 or -1) * line * step
end

---Build one icon: border, picture, cooldown swipe, then a text layer above the swipe.
---@param widget table
---@return table icon
local function NewIcon(widget)
	local icon = CreateFrame('Frame', nil, widget.frame)
	icon.border = icon:CreateTexture(nil, 'BACKGROUND')
	icon.border:SetAllPoints(icon)
	icon.border:SetTexture(WHITE)
	icon.texture = icon:CreateTexture(nil, 'ARTWORK')
	icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local cooldown = CreateFrame('Cooldown', nil, icon)
	cooldown:SetAllPoints(icon.texture)
	if cooldown.SetReverse then
		cooldown:SetReverse(true)
	end
	if cooldown.SetHideCountdownNumbers then
		cooldown:SetHideCountdownNumbers(true)
	end
	if cooldown.SetDrawEdge then
		cooldown:SetDrawEdge(false)
	end
	if cooldown.SetSwipeTexture then
		cooldown:SetSwipeTexture(WHITE)
	end
	if cooldown.SetSwipeColor then
		cooldown:SetSwipeColor(0, 0, 0, 0.6)
	end
	icon.cooldown = cooldown
	icon.overlay = CreateFrame('Frame', nil, icon)
	icon.overlay:SetAllPoints(icon)
	icon.timer = icon.overlay:CreateFontString(nil, 'OVERLAY')
	icon.timer:SetPoint('CENTER', icon, 'CENTER', 0, 0)
	icon.count = icon.overlay:CreateFontString(nil, 'OVERLAY')
	icon.count:SetPoint('BOTTOMRIGHT', icon, 'BOTTOMRIGHT', 1, 0)
	icon:Hide()
	local textures = widget.textures
	textures[#textures + 1] = icon.border
	textures[#textures + 1] = icon.texture
	return icon
end

---Keep the swipe above the picture and the text above the swipe. Levels are read from our own
---frames only; a level the game hides (previews on clients with secrets) is skipped.
---@param icon table
local function FixLevels(icon)
	local base = Secret.Plain(icon:GetFrameLevel())
	if type(base) ~= 'number' or base == icon.levelBase then
		return
	end
	icon.levelBase = base
	icon.cooldown:SetFrameLevel(base + 1)
	icon.overlay:SetFrameLevel(base + 2)
end

---The pandemic glow around one icon (P.GlowLib, made the first time a row asks for it).
---@param icon table
---@param ctx Plates.LayoutContext
local function LayoutGlow(icon, ctx)
	local GlowLib = P.GlowLib
	if not GlowLib then
		return
	end
	if not icon.pglow then
		icon.pglow = GlowLib.Create(icon.overlay)
	end
	GlowLib.Layout(icon.pglow, icon, GlowLib.Opts('pandemic', 2), ctx)
	local c = Scan.PANDEMIC_COLOR
	GlowLib.SetColor(icon.pglow, c[1], c[2], c[3], c[4] or 1)
end

---Size, place and style the icon pool for a spec (grows the pool, never shrinks it).
---@param widget table
---@param spec table
---@param ctx Plates.LayoutContext
function Scan.LayoutIcons(widget, spec, ctx)
	local count = math.max(0, math.min(spec.max or 6, 40))
	local icons = widget.icons
	for i = #icons + 1, count do
		icons[i] = NewIcon(widget)
	end
	local size = spec.size or 20
	local border = spec.borderStyle ~= 'none'
	local px = border and ctx:Pixel() or 0
	for i = 1, #icons do
		local icon = icons[i]
		if i <= count then
			local point, x, y = Scan.IconPoint(spec, i - 1)
			icon:SetSize(size, size)
			icon:ClearAllPoints()
			icon:SetPoint(point, widget.frame, point, x, y)
			icon.texture:ClearAllPoints()
			icon.texture:SetPoint('TOPLEFT', icon, 'TOPLEFT', px, -px)
			icon.texture:SetPoint('BOTTOMRIGHT', icon, 'BOTTOMRIGHT', -px, px)
			if border then
				icon.border:Show()
			else
				icon.border:Hide()
			end
			ctx:ApplyFont(icon.timer, spec.font)
			ctx:ApplyFont(icon.count, spec.font)
			if spec.pandemic == true then
				LayoutGlow(icon, ctx)
			end
			icon.levelBase = nil
		else
			icon:Hide()
		end
	end
	widget.count = count
end

---Border color for an aura under a border style.
---@param icon table
---@param spec table
---@param dispel string|nil
---@param harmful boolean
local function ColorBorder(icon, spec, dispel, harmful)
	local color = Scan.BORDER_COLOR
	if icon.pandemic then
		color = Scan.PANDEMIC_COLOR
	elseif spec.borderStyle == 'dispel' then
		if type(dispel) == 'string' and Scan.DISPEL_COLORS[dispel] then
			color = Scan.DISPEL_COLORS[dispel]
		elseif harmful then
			color = Scan.DISPEL_COLORS.none
		end
	end
	icon.border:SetVertexColor(color[1], color[2], color[3], 1)
end

---Turn the pandemic glow on or off (my auras with 30% or less left).
---@param icon table
---@param on boolean
local function SetPandemic(icon, on)
	on = on and true or false
	if icon.pandemic == on then
		return
	end
	icon.pandemic = on
	local glow = icon.pglow
	if glow then
		if on then
			P.GlowLib.Show(glow)
		else
			P.GlowLib.Hide(glow)
		end
	end
	ColorBorder(icon, icon.spec, icon.dispel, icon.harmful)
end

---Plain countdown text: whole seconds, tenths under 3 s, minutes and hours above.
---@param remaining number
---@return string
function Scan.FormatRemaining(remaining)
	if type(remaining) ~= 'number' or remaining <= 0 or remaining == math.huge then
		return ''
	end
	if remaining >= 3600 then
		return string.format(L['%dh'], math.ceil(remaining / 3600))
	end
	if remaining >= 60 then
		return string.format(L['%dm'], math.ceil(remaining / 60))
	end
	if remaining < 3 then
		return string.format('%.1f', remaining)
	end
	return tostring(math.ceil(remaining))
end

-- Icons that need the shared tick (plain timer text or the pandemic check)
local ticking = setmetatable({}, { __mode = 'k' })

---Refresh one ticking icon. Returns false when it no longer needs the tick.
---@param icon table
---@param now number
---@return boolean
local function TickIcon(icon, now)
	if not icon:IsShown() then
		return false
	end
	local remaining = icon.expiration - now
	if icon.plainTimer then
		icon.timer:SetText(Scan.FormatRemaining(remaining))
	end
	if icon.watchPandemic then
		SetPandemic(icon, remaining > 0 and remaining <= icon.total * Scan.PANDEMIC)
	end
	return remaining > 0
end

local function Tick(now)
	for icon in pairs(ticking) do
		if not TickIcon(icon, now) then
			ticking[icon] = nil
		end
	end
	if next(ticking) == nil then
		P.Scheduler:Cancel(Scan.TICK_ID)
	end
end

local function StartTick(icon)
	ticking[icon] = true
	if not P.Scheduler:IsRunning(Scan.TICK_ID) then
		P.Scheduler:Every(Scan.TICK_ID, Scan.TICK, Tick)
	end
end

---How many icons are on the shared tick (tests and the inspector).
---@return integer
function Scan.TickingCount()
	local n = 0
	for _ in pairs(ticking) do
		n = n + 1
	end
	return n
end

---Countdown text bound in the engine (where Caps 'durationText' says it works), else plain.
---@param icon table
---@param expiration number
---@param duration number
---@return boolean bound
local function BindTimer(icon, expiration, duration)
	if not (P.Caps:Get('durationText') and C_DurationUtil and C_DurationUtil.CreateDurationTextBinding and C_DurationUtil.CreateDuration) then
		return false
	end
	local binding = icon.binding
	if not binding then
		binding = C_DurationUtil.CreateDurationTextBinding()
		binding:SetFontString(icon.timer)
		local formatter = C_StringUtil and C_StringUtil.CreateSecondsFormatter and C_StringUtil.CreateSecondsFormatter()
		if formatter then
			binding:SetFormatter(formatter)
		end
		binding:SetExpiredText('')
		binding:SetZeroDurationText('')
		icon.binding = binding
		icon.duration = C_DurationUtil.CreateDuration()
	end
	icon.duration:SetTimeFromEnd(expiration, duration)
	binding:SetDuration(icon.duration)
	binding:SetEnabled(true)
	return true
end

---Stop the engine binding and the shared tick for an icon.
---@param icon table
local function UnbindTimer(icon)
	if icon.binding then
		icon.binding:SetEnabled(false)
	end
	icon.plainTimer = nil
	icon.watchPandemic = nil
	ticking[icon] = nil
end

---Fill one icon from aura data (live) or a sample entry (preview).
---@param widget table
---@param icon table
---@param data table { icon, duration, expiration, stacks, dispel, harmful, mine, frozen }
---@param now number
local function DrawIcon(widget, icon, data, now)
	local spec = widget.spec
	icon.spec = spec
	icon.dispel, icon.harmful = data.dispel, data.harmful
	icon.texture:SetTexture(data.icon)
	local stacks = data.stacks or 0
	if spec.stacks ~= false and stacks > 1 then
		icon.count:SetText(tostring(stacks))
	else
		icon.count:SetText('')
	end
	local duration, expiration = data.duration or 0, data.expiration or 0
	local timed = duration > 0 and expiration > 0
	icon.expiration, icon.total = expiration, duration
	UnbindTimer(icon)
	local pandemic = false
	if timed then
		icon.cooldown:SetCooldown(expiration - duration, duration)
		icon.cooldown:Show()
		local remaining = expiration - now
		local watch = spec.pandemic == true and data.mine == true
		pandemic = watch and remaining <= duration * Scan.PANDEMIC
		if data.frozen then
			if icon.cooldown.Pause then
				icon.cooldown:Pause()
			end
			icon.timer:SetText(spec.timer ~= false and Scan.FormatRemaining(remaining) or '')
		else
			if icon.cooldown.Resume then
				icon.cooldown:Resume()
			end
			if spec.timer == false then
				icon.timer:SetText('')
			elseif not BindTimer(icon, expiration, duration) then
				icon.plainTimer = true
				icon.timer:SetText(Scan.FormatRemaining(remaining))
			end
			icon.watchPandemic = watch or nil
			if icon.plainTimer or icon.watchPandemic then
				StartTick(icon)
			end
		end
	else
		if icon.cooldown.Clear then
			icon.cooldown:Clear()
		end
		icon.cooldown:Hide()
		icon.timer:SetText('')
	end
	icon.pandemic = nil
	SetPandemic(icon, pandemic)
	icon:Show()
	FixLevels(icon)
end

local drawData = {}

---Hide every icon from index `from` on.
---@param widget table
---@param from integer
local function HideFrom(widget, from)
	for i = from, #widget.icons do
		local icon = widget.icons[i]
		UnbindTimer(icon)
		if icon.pglow then
			P.GlowLib.Reset(icon.pglow)
		end
		icon.pandemic = nil
		icon:Hide()
	end
end

---Draw the picks (live aura tables) into the icon pool and remember which ids are shown.
---@param widget table
---@param picks table
function Scan.Draw(widget, picks)
	local count = math.min(#picks, widget.count or 0)
	local shown = widget.shownIDs
	P.util.Wipe(shown)
	local now = P.services.GetTime()
	local data = drawData
	for i = 1, count do
		local aura = picks[i]
		data.icon = aura.icon
		data.duration = aura.duration
		data.expiration = aura.expirationTime
		data.stacks = aura.applications
		data.dispel = aura.dispelName
		data.harmful = aura.isHarmful == true
		data.mine = Scan.IsMine(aura)
		data.frozen = nil
		DrawIcon(widget, widget.icons[i], data, now)
		shown[#shown + 1] = aura.auraInstanceID
	end
	HideFrom(widget, count + 1)
end

---Stock sample icons for rows a scene asks to fill (plate.fillAuras) when the sample has none.
---@param row string
---@return Plates.SampleAura[]
function Scan.FillIcons(row)
	local icons = P.Data.SampleIcons or {}
	if row == 'removable' then
		return { { icon = icons.shield, duration = 15, remaining = 9, dispel = 'Magic', spellId = 17 } }
	elseif row == 'crowdControl' then
		return { { icon = icons.polymorph, duration = 8, remaining = 5, spellId = 118 } }
	end
	return {
		{ icon = icons.pain, duration = 18, remaining = 12, spellId = 589 },
		{ icon = icons.corruption, duration = 14, remaining = 4, spellId = 172 },
		{ icon = icons.sunder, duration = 30, remaining = 22, stacks = 5, spellId = 7386, mine = false },
	}
end

local sampleAura = {}

---Is a sample entry hidden by the row's "Never show" list (by spell id or name)?
---@param settings table
---@param entry Plates.SampleAura
---@param mine boolean
---@return boolean
local function SampleNever(settings, entry, mine)
	if type(entry.spellId) ~= 'number' then
		return false
	end
	sampleAura.spellId = entry.spellId
	sampleAura.name = Scan.SpellName(entry.spellId)
	return Listed(settings.never, sampleAura, mine)
end

---Draw sample icons (previews): swipes paused at a fixed time, plain frozen text.
---@param widget table
---@param src Plates.SampleSource
function Scan.DrawSamples(widget, src)
	local spec = widget.spec
	local row = spec.row or 'myDebuffs'
	local list = src:SampleAuras(row) or {}
	if #list == 0 and widget.plate.fillAuras then
		list = Scan.FillIcons(row)
	end
	local settings = Scan.RowSettings(row, scanEnv.settings)
	local limit = settings.on and math.min(widget.count or 0, spec.max or 6) or 0
	P.util.Wipe(widget.shownIDs)
	local now = P.services.GetTime()
	local data = drawData
	local count = 0
	for i = 1, #list do
		local entry = list[i]
		local mine = (row == 'myDebuffs' or row == 'custom') and entry.mine ~= false
		if count < limit and not SampleNever(settings, entry, mine) then
			count = count + 1
			local duration = entry.duration or 0
			local remaining = math.min(entry.remaining or duration, duration)
			data.icon = entry.icon
			data.duration = duration
			data.expiration = duration > 0 and (now + remaining) or 0
			data.stacks = entry.stacks
			data.dispel = entry.dispel
			data.harmful = row ~= 'removable'
			data.mine = mine
			data.frozen = true
			DrawIcon(widget, widget.icons[count], data, now)
		end
	end
	HideFrom(widget, count + 1)
end

---Scan (or read the sample) and draw.
---@param widget table
---@param src Plates.Source
function Scan.Refresh(widget, src)
	if not (widget.spec and widget.active and src) then
		return
	end
	widget.hostile = Scan.IsHostile(widget.plate.facts)
	if src.isSample then
		P.util.Wipe(widget.picks)
		Scan.DrawSamples(widget, src)
		return
	end
	Scan.Draw(widget, Scan.Collect(widget, src))
end

---Is any id from a list in the shown list?
---@param shown table
---@param ids table|nil
---@return boolean
local function AnyShown(shown, ids)
	if type(ids) ~= 'table' then
		return false
	end
	for i = 1, #ids do
		local id = ids[i]
		for j = 1, #shown do
			if shown[j] == id then
				return true
			end
		end
	end
	return false
end

---Can this UNIT_AURA change the row? A full update, an added aura of a scanned polarity, or a
---change to an aura we show.
---@param widget table
---@param info table|nil updateInfo
---@return boolean
function Scan.Relevant(widget, info)
	if type(info) ~= 'table' or info.isFullUpdate then
		return true
	end
	local def = Scan.ROWS[widget.spec.row or 'myDebuffs']
	if not def then
		return false
	end
	local added = info.addedAuras
	if type(added) == 'table' then
		for i = 1, #added do
			local aura = added[i]
			if (def.harmful and aura.isHarmful) or (def.helpful and aura.isHelpful) then
				return true
			end
		end
	end
	return AnyShown(widget.shownIDs, info.removedAuraInstanceIDs) or AnyShown(widget.shownIDs, info.updatedAuraInstanceIDs)
end

----------------------------------------------------------------------------------------------------
-- The part
----------------------------------------------------------------------------------------------------

P.Caps:AddProbe('ccFilter', function()
	return AuraUtil ~= nil and AuraUtil.AuraFilters ~= nil and AuraUtil.AuraFilters.CrowdControl ~= nil
end, 'CROWD_CONTROL filter on the Lua aura scan (S0; a refused call turns it off)')
P.Caps:AddProbe('spellCrowdControl', function()
	return C_Spell ~= nil and C_Spell.IsSpellCrowdControl ~= nil
end, "The game's own crowd control flag per spell, as its Classic nameplates use it")

P.Parts:Register({
	id = 'aurasScan',
	kinds = { 'auras' },
	match = function(_, plate)
		return plate.isPreview or not P.Caps:Get('secrets')
	end,
	events = { 'UNIT_AURA' },
	messages = { 'FACTS_POLLED' },
	reasons = { auras = true },
	Create = function(plate)
		local holder = CreateFrame('Frame', nil, plate.art)
		return { frame = holder, icons = {}, picks = {}, shownIDs = {}, textures = {}, count = 0 }
	end,
	Layout = function(widget, spec, ctx)
		local w, h = P.Styles.Merge.PartSize(spec, ctx.width, ctx.height)
		widget.frame:SetSize(w, h)
		ctx:Anchor(widget.frame, spec.anchor)
		Scan.LayoutIcons(widget, spec, ctx)
		-- Redraw what we already have in the new places; settings changes rescan in Configure
		local src = widget.plate.src
		if src then
			if src.isSample then
				Scan.DrawSamples(widget, src)
			else
				Scan.Draw(widget, widget.picks)
			end
		end
	end,
	Configure = function(widget)
		local src = widget.plate.src
		if src then
			Scan.Refresh(widget, src)
		end
	end,
	Update = function(widget, src, event, _, info)
		if event == 'COLORS' then
			return
		elseif event == 'UNIT_AURA' then
			if not Scan.Relevant(widget, info) then
				return
			end
		elseif event == 'FACTS_POLLED' then
			if Scan.IsHostile(widget.plate.facts) == (widget.hostile == true) then
				return
			end
		end
		Scan.Refresh(widget, src)
	end,
	Reset = function(widget)
		P.util.Wipe(widget.picks)
		P.util.Wipe(widget.shownIDs)
		HideFrom(widget, 1)
	end,
})

----------------------------------------------------------------------------------------------------
-- Aura presence for color rows ("Has <spell>", "My debuff is missing")
----------------------------------------------------------------------------------------------------

-- Color row kind for each condition: color rows carry no arguments, their spells live in
-- profile.colors[piece].spells[rowKind] (the same place the container's presence tints read)
Scan.PRESENCE_ROWS = { auraPresent = 'hasAura', auraMissing = 'auraMissing' }

-- Spell sets per argument table: { ids = { [id] = true }, names = { [name] = true }, any }
local argSets = setmetatable({}, { __mode = 'k' })

---Spell ids and names named by a condition argument: a list { 589, 172 } or a set
---{ [589] = true } or { [589] = 'mine' }.
---@param args table|nil
---@return table|nil
local function ArgSet(args)
	if type(args) ~= 'table' then
		return nil
	end
	local set = argSets[args]
	if set then
		return set
	end
	local index = Scan.ListIndex(args)
	set = { ids = index.ids, names = index.names, any = next(index.ids) ~= nil }
	if indexByList[args] then
		argSets[args] = set
	end
	return set
end

---Spells the player picked for a presence color row, every piece together (args for the
---conditions when a color row calls them without any). Rebuilt when color settings change.
local rowSpells = {}

P:On('STORE_CHANGED', function(reasons)
	if not reasons or reasons.colors or reasons.look then
		P.util.Wipe(rowSpells)
	end
end, Scan)
P:On('PROFILE_CHANGED', function()
	P.util.Wipe(rowSpells)
end, Scan)

---@param rowKind string 'hasAura' | 'auraMissing'
---@return table list { [spellID] = 'mine'|'any' } (empty when none are picked)
function Scan.RowSpells(rowKind)
	local list = rowSpells[rowKind]
	if list then
		return list
	end
	list = {}
	local colors = P.Store and P.Store:Get('colors')
	if type(colors) == 'table' then
		for _, piece in pairs(colors) do
			local spells = type(piece) == 'table' and type(piece.spells) == 'table' and piece.spells[rowKind]
			if type(spells) == 'table' then
				for key, value in pairs(spells) do
					local id, who
					if type(value) == 'number' then
						id, who = value, 'any'
					elseif type(key) == 'number' then
						id, who = key, Who(value)
					end
					if who and type(id) == 'number' and list[id] ~= 'any' then
						list[id] = who
					end
				end
			end
		end
	end
	rowSpells[rowKind] = list
	return list
end

local PRESENCE_FILTERS = { 'HARMFUL', 'HELPFUL' }
local MINE_FILTERS = { 'HARMFUL' }

---Whether the unit has one of the spells (from anyone, or only mine). Plain reads only.
---@param src Plates.Source
---@param args table|nil
---@param mineOnly boolean
---@return boolean
function Scan.HasAura(src, args, mineOnly)
	local set = ArgSet(args)
	if not (set and set.any) then
		return false
	end
	if src.isSample then
		for _, list in pairs(src.sample and src.sample.auras or {}) do
			for i = 1, #list do
				local entry = list[i]
				if entry.spellId and set.ids[entry.spellId] and (not mineOnly or entry.mine ~= false) then
					return true
				end
			end
		end
		return false
	end
	for _, filter in ipairs(mineOnly and MINE_FILTERS or PRESENCE_FILTERS) do
		for index = 1, Scan.MAX_SCAN do
			local aura = src:AuraByIndexPlain(index, filter)
			if not aura then
				break
			end
			if (set.ids[aura.spellId] or (aura.name and set.names[aura.name])) and (not mineOnly or Scan.IsMine(aura)) then
				return true
			end
		end
	end
	return false
end

---Answer auraPresent / auraMissing with plain reads on clients without secrets and on previews;
---clients with secrets keep the base answer (aura slots, S19). Without arguments (a color row)
---the spells come from the row's own list.
---@param id string
---@param missing boolean
function Scan.WrapPresence(id, missing)
	local cond = P.Conditions and P.Conditions:Get(id)
	if not cond or cond.scanWrapped then
		return
	end
	local base = cond.Test
	cond.Test = function(env, args)
		local src = env and env.src
		if src and (src.isSample or not P.Caps:Get('secrets')) then
			if type(args) ~= 'table' then
				args = Scan.RowSpells(Scan.PRESENCE_ROWS[id])
			end
			if missing then
				-- A reminder only makes sense on something you can put a debuff on
				if not Scan.IsHostile(env.facts) or next(args) == nil then
					return false
				end
				return not Scan.HasAura(src, args, true)
			end
			return Scan.HasAura(src, args, false)
		end
		return base(env, args)
	end
	local events = {}
	for _, event in ipairs(cond.events or {}) do
		events[#events + 1] = event
	end
	events[#events + 1] = 'UNIT_AURA'
	cond.events = events
	cond.scanWrapped = true
end

Scan.WrapPresence('auraPresent', false)
Scan.WrapPresence('auraMissing', true)
