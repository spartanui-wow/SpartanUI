local _, ns = ...
local P = ns.Plates
local L = P.L

-- Aura rows on 12.1 aura containers (kind 'auras', live plates where Caps 'containers': Retail
-- and Forever; 6.6). Previews never use containers (they need a real unit): AurasScan draws
-- sample icons there, and runs the Lua scan on the Classic family.
--
-- One container per positioned row (a style's aura part), at most MAX_PER_PLATE (3) per plate:
--   CreateFrame('AuraContainer', nil, holder, 'CustomAuraContainerTemplate')
-- Containers are pooled per plate (P.AuraContainers) and reused across units and styles: a row
-- the style stops showing hands its container back to the plate's pool (STYLE_APPLIED), and the
-- next row that needs one takes it (moved under the new row's holder while capability
-- 'containerMove' holds; the first real move records the answer, and a refused move falls back
-- to making a new container). Groups inside a container are generic ('g1', 'g2', ...), added
-- once with AddAuraGroup and repointed after that (SetAuraGroupFilterString,
-- SetAuraGroupCandidateFilters, SetAuraGroupSortMethod, SetAuraGroupLayout). Never
-- 'HELPFUL|HARMFUL' as a never-match: a group that is off gets SetAuraGroupMaxFrameCount(key, 0)
-- (plus SetAuraGroupEnabled(key, false) where 12.1.5 and Forever have it).
--
-- Rows (spec.row; settings in profile.auras[row] = { on, onlyMine, important, always, never }):
--   myDebuffs     HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY|!CROWD_CONTROL + { nameplateShowPersonal }
--                 ("Only mine" off: every debuff but crowd control). Forever adds tank debuffs
--                 from anyone (Data/TankDebuffs.lua, profile.auras.tankDebuffs) as a second group.
--   removable     HELPFUL|DISPELLABLE (AuraUtil.AuraFilters), enemies only; with important = true
--                 a second HELPFUL|IMPORTANT|!DISPELLABLE group. No spell lists: the engine skips
--                 them for buffs on units the player cannot help, so every aura would pass.
--   crowdControl  HARMFUL|CROWD_CONTROL.
--   custom        only what the "Always show" list names (debuffs on enemies, buffs on friends).
-- Always and never lists ride on includeSpellIDs/excludeSpellIDs of debuff groups. The engine
-- applies a spell list only to debuffs on units the player cannot help and buffs on units the
-- player can help (AuraContainerUtil.CanApplyIdentityCandidateFilters), so a list group is
-- switched off on the other units (reach, below), never by rewriting its filter.
--
-- What runs when (the game restricts aura changes in combat and in restricted instances):
--   * always, combat included (Update 'FULL' on every add, Reset on every remove): SetUnit,
--     SetEnabled and SetAuraGroupMaxFrameCount (the per-add flips by reach).
--   * only while P.Secret.IsRestricted() is false: creating containers and groups, moving a
--     container, filters, candidates, sort, group layout, flow layout, anchoring and restyling
--     buttons. Changes made while restricted stay pending (plate.pendingConfigure) and are applied
--     on RESTRICTION_CHANGED, on PLAYER_REGEN_ENABLED (Scheduler:AfterCombat) or by the Driver's
--     FlushPendingConfigure. A row that has no container yet stays empty meanwhile (S6).
-- Rows that are off (max 0, the row switched off, no unit, nothing applies) are disabled and bound
-- to 'none', so the engine does not parse auras for them.
-- We anchor each container ourselves at a corner of our own holder frame (its flow layout only
-- places buttons inside it, and it sizes itself). Other parts anchor to the holder, never to the
-- container. Buttons are styled in initializeFrame and later only while not restricted, and
-- skipped when IsForbidden(). Bookkeeping lives in our own tables, never on Blizzard frames.
-- Button pieces: icon, cooldown swipe, timer text (the engine's duration text binding), stack
-- text, a pixel border (token 'ink') or the engine's dispel type border, and the pandemic glow
-- (P.GlowLib look 'pandemic', made only once a row asks for it). The glow's fade frame is the
-- region handed to AddPandemicRegion, so the engine shows it only in the refresh window. 12.1.0
-- returns an index from AddPandemicRegion and removes by index; 12.1.5 and Forever remove by
-- region and add AddPandemicActiveAnimation (our pulse). Told apart by method, never by build.
--
-- Aura presence tints (Phase 5, S19) live at the end of this file (P.AuraPresence): one more
-- "slots" container per plate, made only while a "Has a spell" or "My debuff is missing" color
-- row is on, moves a tint over the health bar without any aura ever being read.
-- Never key a table by auraInstanceID. Never name anything 'Auras' (oUF meta element name).

local Situation = P.Situation

local IMPL_ID = 'aurasContainer'
local GROUP_KEYS = { 'g1', 'g2', 'g3', 'g4', 'g5', 'g6' }
local EMPTY = {}

local function White()
	return (P.BarLib and P.BarLib.WHITE) or 'Interface\\Buttons\\WHITE8X8'
end

local function IsRestricted()
	return P.Secret.IsRestricted()
end

local function InLockdown()
	return InCombatLockdown ~= nil and InCombatLockdown() and true or false
end

---Call a method in pcall. Returns ok and the first result.
local function Call(object, method, ...)
	local fn = object and object[method]
	if not fn then
		return false
	end
	local ok, result = pcall(fn, object, ...)
	if not ok then
		P.log.debug('Aura row call ' .. method .. ' failed: ' .. tostring(result))
	end
	return ok, result
end

local warned = {}

---Log something once per session (by key).
local function WarnOnce(key, text)
	if not warned[key] then
		warned[key] = true
		P.log.info(text)
	end
end

----------------------------------------------------------------------------------------------------
-- Rows and filters (shared with AurasScan and Glow)
----------------------------------------------------------------------------------------------------

---@class Plates.AuraRowGroup
---@field filter string Aura filter string (normalized, valid tokens only)
---@field candidates? table Candidate filters (keys checked against Schema.CANDIDATE_KEYS)
---@field applies? 'enemy'|'friend'|'hostile' Where the group shows (nil = every unit): 'enemy' for debuff spell lists (units the player cannot help), 'friend' for buff spell lists (units the player can help), 'hostile' for rows meant for enemies only
---@field sig string Signature of filter, candidates and reach, to skip repeated calls

---@class Plates.AuraRow
---@field id string
---@field label string
---@field groups table[] Base groups (documentation; ContainerGroups builds the live list)
---@field scan fun(aura: table, ctx: table): boolean Lua scan predicate (Classic family, plain data)
---@field scanFilter string Filter passed to the scan path

---@class Plates.AuraRows
local AuraRows = {}
P.AuraRows = AuraRows

-- Tokens every client with containers knows (AuraUtil.AuraFilters on 12.1.0, 12.1.5 and Forever).
-- Used only when that table cannot be read.
local KNOWN_TOKENS = {
	HELPFUL = true,
	HARMFUL = true,
	PLAYER = true,
	RAID = true,
	CANCELABLE = true,
	INCLUDE_NAME_PLATE_ONLY = true,
	MAW = true,
	EXTERNAL_DEFENSIVE = true,
	CROWD_CONTROL = true,
	RAID_IN_COMBAT = true,
	RAID_PLAYER_DISPELLABLE = true,
	BIG_DEFENSIVE = true,
	IMPORTANT = true,
	DISPELLABLE = true,
}
-- The game ignores a negation on these two (AuraUtil.lua), so it is never written
local NOT_NEGATABLE = { INCLUDE_NAME_PLATE_ONLY = true, MAW = true }

local function AuraFilters()
	local util = AuraUtil
	local filters = type(util) == 'table' and util.AuraFilters
	if type(filters) == 'table' and P.Secret.CanIndex(filters) then
		return filters
	end
	return nil
end

---True when this client's aura filter strings accept the token (bare, without '!').
---@param token string
---@return boolean
function AuraRows.KnowsToken(token)
	local filters = AuraFilters()
	if filters then
		for _, value in pairs(filters) do
			if value == token then
				return true
			end
		end
		return false
	end
	return KNOWN_TOKENS[token] == true
end

---A token from AuraUtil.AuraFilters by key, or the literal when the table cannot be read.
---@param key string
---@param literal string
---@return string
function AuraRows.Token(key, literal)
	local filters = AuraFilters()
	local value = filters and filters[key]
	if type(value) == 'string' then
		return value
	end
	return literal
end

---Order: polarity first, other tokens sorted, each negation right after its bare token, so groups
---share engine scans. On 12.1 NOT_CANCELABLE is written !CANCELABLE. Repeated tokens are dropped
---and a negation the game ignores is written bare.
---@param filter string
---@return string
function AuraRows.NormalizeFilter(filter)
	local polarity
	local others, seen = {}, {}
	for token in string.gmatch(filter or '', '[^|%s]+') do
		if token == 'NOT_CANCELABLE' then
			token = '!CANCELABLE'
		end
		if string.sub(token, 1, 1) == '!' and NOT_NEGATABLE[string.sub(token, 2)] then
			token = string.sub(token, 2)
		end
		if token == 'HELPFUL' or token == 'HARMFUL' then
			polarity = polarity or token
		elseif not seen[token] then
			seen[token] = true
			others[#others + 1] = token
		end
	end
	table.sort(others, function(a, b)
		local na, nb = string.sub(a, 1, 1) == '!', string.sub(b, 1, 1) == '!'
		local ba, bb = na and string.sub(a, 2) or a, nb and string.sub(b, 2) or b
		if ba ~= bb then
			return ba < bb
		end
		return not na and nb
	end)
	if polarity then
		table.insert(others, 1, polarity)
	end
	return table.concat(others, '|')
end

---A normalized filter with every token this client does not know removed (an unknown token makes
---the container code raise an error).
---@param filter string
---@return string filter
---@return integer dropped
function AuraRows.ValidFilter(filter)
	local kept, dropped = {}, 0
	for token in string.gmatch(AuraRows.NormalizeFilter(filter), '[^|]+') do
		local bare = string.sub(token, 1, 1) == '!' and string.sub(token, 2) or token
		if AuraRows.KnowsToken(bare) then
			kept[#kept + 1] = token
		else
			dropped = dropped + 1
		end
	end
	if dropped > 0 then
		P.log.debug('Aura filter ' .. tostring(filter) .. ' lost ' .. dropped .. ' part(s) this game does not know')
	end
	return table.concat(kept, '|'), dropped
end

---Drop candidate keys the engine does not know (a wrong key fails open and matches every aura).
---@param candidates table|nil
---@return table|nil cleaned
---@return string[] dropped
function AuraRows.CleanCandidates(candidates)
	local dropped = {}
	if type(candidates) ~= 'table' then
		return nil, dropped
	end
	local out = {}
	for key, value in pairs(candidates) do
		if P.Styles.Schema.CANDIDATE_KEYS[key] then
			out[key] = value
		else
			dropped[#dropped + 1] = tostring(key)
		end
	end
	return out, dropped
end

---Spell sets from a stored list. Takes the SpellList map { [spellID] = 'mine'|'any' } (true counts
---as 'any') or a plain array of spell ids (all 'any').
---@param list table|nil
---@return table<integer, boolean> mine
---@return table<integer, boolean> any
function AuraRows.SpellSets(list)
	local mine, any = {}, {}
	if type(list) ~= 'table' then
		return mine, any
	end
	for key, value in pairs(list) do
		local id, who
		if type(value) == 'number' then
			id, who = value, 'any'
		elseif type(key) == 'number' then
			id, who = key, value
		end
		if id and id > 0 and id == math.floor(id) then
			if who == 'mine' then
				mine[id] = true
			elseif who ~= false then
				any[id] = true
			end
		end
	end
	return mine, any
end

local function Union(...)
	local out
	for i = 1, select('#', ...) do
		for id in pairs(select(i, ...) or EMPTY) do
			out = out or {}
			out[id] = true
		end
	end
	return out
end

local function Minus(set, ...)
	for i = 1, select('#', ...) do
		for id in pairs(select(i, ...) or EMPTY) do
			set[id] = nil
		end
	end
	return set
end

local function SetSig(set)
	local ids = {}
	for id in pairs(set) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	return table.concat(ids, ',')
end

---Plain signature of a candidate table, so unchanged groups are not touched again.
---@param candidates table|nil
---@return string
function AuraRows.CandidateSig(candidates)
	if type(candidates) ~= 'table' then
		return ''
	end
	local keys = {}
	for key in pairs(candidates) do
		keys[#keys + 1] = tostring(key)
	end
	table.sort(keys)
	local parts = {}
	for i, key in ipairs(keys) do
		local value = candidates[key]
		parts[i] = key .. '=' .. (type(value) == 'table' and SetSig(value) or tostring(value))
	end
	return table.concat(parts, ';')
end

local function Group(out, filter, candidates, applies)
	local valid = AuraRows.ValidFilter(filter)
	if valid == '' then
		return
	end
	local cleaned, dropped = AuraRows.CleanCandidates(candidates)
	if #dropped > 0 then
		P.log.warning('Aura row candidate keys dropped: ' .. table.concat(dropped, ', '))
	end
	if cleaned and next(cleaned) == nil then
		cleaned = nil
	end
	out[#out + 1] = {
		filter = valid,
		candidates = cleaned,
		applies = applies,
		sig = valid .. '#' .. AuraRows.CandidateSig(cleaned) .. '#' .. tostring(applies),
	}
end

local function RowSettings(auras, rowId)
	local row = type(auras) == 'table' and auras[rowId]
	return type(row) == 'table' and row or EMPTY
end

---Always and never lists of a row; never wins over always.
local function Lists(row)
	local alwaysMine, alwaysAny = AuraRows.SpellSets(row.always)
	local neverMine, neverAny = AuraRows.SpellSets(row.never)
	Minus(alwaysMine, neverMine, neverAny)
	Minus(alwaysAny, neverAny)
	return alwaysMine, alwaysAny, neverMine, neverAny
end

---Tank debuffs from anyone. A data rule, not an engine gate: among the clients with containers
---the spells only exist on Forever. profile.auras.tankDebuffs = { on, always, never }.
---@param auras table|nil
---@return table<integer, boolean>|nil
function AuraRows.TankDebuffSet(auras)
	local row = RowSettings(auras, 'tankDebuffs')
	if row.on == false or P.Caps:Client() ~= 'forever' then
		return nil
	end
	local set = {}
	for id in pairs(P.Data.TankDebuffs or EMPTY) do
		if type(id) == 'number' then
			set[id] = true
		end
	end
	local extraMine, extraAny = AuraRows.SpellSets(row.always)
	for id in pairs(extraMine) do
		set[id] = true
	end
	for id in pairs(extraAny) do
		set[id] = true
	end
	local neverMine, neverAny = AuraRows.SpellSets(row.never)
	Minus(set, neverMine, neverAny)
	if next(set) == nil then
		return nil
	end
	return set
end

---The removable row's token: DISPELLABLE, or RAID_PLAYER_DISPELLABLE where a client lacks it.
---@return string
function AuraRows.DispellableToken()
	local dispellable = AuraRows.Token('Dispellable', 'DISPELLABLE')
	if not AuraRows.KnowsToken(dispellable) then
		dispellable = AuraRows.Token('RaidPlayerDispellable', 'RAID_PLAYER_DISPELLABLE')
	end
	return dispellable
end

---Container groups for a row, in display order. Pure: reads only the arguments, the client's
---filter tokens and the tank debuff data. Spell lists ride on includeSpellIDs/excludeSpellIDs and
---only on groups the engine applies them to (debuffs on enemies, buffs on friends).
---@param rowId string
---@param auras table|nil profile.auras
---@return Plates.AuraRowGroup[]
function AuraRows.ContainerGroups(rowId, auras)
	local out = {}
	local row = RowSettings(auras, rowId)
	local nameplate = AuraRows.Token('IncludeNameplateOnly', 'INCLUDE_NAME_PLATE_ONLY')
	local cc = AuraRows.Token('CrowdControl', 'CROWD_CONTROL')
	if rowId == 'myDebuffs' then
		local alwaysMine, alwaysAny, neverMine, neverAny = Lists(row)
		local onlyMine = row.onlyMine ~= false
		-- "Only mine" off already shows every debuff, tank debuffs included
		local tank = onlyMine and AuraRows.TankDebuffSet(auras) or nil
		if tank then
			Minus(tank, alwaysMine, alwaysAny, neverAny)
			if next(tank) == nil then
				tank = nil
			end
		end
		if next(alwaysMine) then
			Group(out, 'HARMFUL|PLAYER|' .. nameplate, { includeSpellIDs = alwaysMine }, 'enemy')
		end
		if next(alwaysAny) then
			Group(out, 'HARMFUL|' .. nameplate, { includeSpellIDs = alwaysAny }, 'enemy')
		end
		local exclude = Union(neverMine, neverAny, alwaysMine, alwaysAny, tank)
		if onlyMine then
			Group(out, 'HARMFUL|PLAYER|' .. nameplate .. '|!' .. cc, { nameplateShowPersonal = true, excludeSpellIDs = exclude })
		else
			Group(out, 'HARMFUL|' .. nameplate .. '|!' .. cc, { excludeSpellIDs = exclude })
		end
		if tank then
			Group(out, 'HARMFUL', { includeSpellIDs = tank }, 'enemy')
		end
	elseif rowId == 'crowdControl' then
		local alwaysMine, alwaysAny, neverMine, neverAny = Lists(row)
		if next(alwaysMine) then
			Group(out, 'HARMFUL|PLAYER', { includeSpellIDs = alwaysMine }, 'enemy')
		end
		if next(alwaysAny) then
			Group(out, 'HARMFUL', { includeSpellIDs = alwaysAny }, 'enemy')
		end
		Group(out, 'HARMFUL|' .. cc, { excludeSpellIDs = Union(neverMine, neverAny, alwaysMine, alwaysAny) })
	elseif rowId == 'removable' then
		-- The engine skips spell lists for buffs on enemies, so this row has no lists here
		local dispellable = AuraRows.DispellableToken()
		Group(out, 'HELPFUL|' .. dispellable, nil, 'hostile')
		local important = AuraRows.Token('Important', 'IMPORTANT')
		if row.important == true and AuraRows.KnowsToken(important) then
			Group(out, 'HELPFUL|' .. important .. '|!' .. dispellable, nil, 'hostile')
		end
	elseif rowId == 'custom' then
		local alwaysMine, alwaysAny = Lists(row)
		if next(alwaysMine) then
			Group(out, 'HARMFUL|PLAYER|' .. nameplate, { includeSpellIDs = alwaysMine }, 'enemy')
			Group(out, 'HELPFUL|PLAYER', { includeSpellIDs = alwaysMine }, 'friend')
		end
		if next(alwaysAny) then
			Group(out, 'HARMFUL|' .. nameplate, { includeSpellIDs = alwaysAny }, 'enemy')
			Group(out, 'HELPFUL', { includeSpellIDs = alwaysAny }, 'friend')
		end
	end
	return out
end

local groupCache = {}

---ContainerGroups for the current profile, cached until aura settings or the profile change.
---@param rowId string
---@return Plates.AuraRowGroup[]
function AuraRows.CurrentGroups(rowId)
	local groups = groupCache[rowId]
	if not groups then
		local profile = P.db and P.db.profile
		groups = AuraRows.ContainerGroups(rowId, profile and profile.auras)
		groupCache[rowId] = groups
	end
	return groups
end

---Forget cached groups (settings, profile or capability overrides changed).
function AuraRows.Invalidate()
	P.util.Wipe(groupCache)
end

---How spell lists reach this unit (plain facts only): 'enemy' when the player cannot help it
---(debuff lists apply), 'friend' when the player can (buff lists apply), nil when the facts cannot
---say. Reaction 5 and up stands in for "can help": the engine itself asks UnitCanAssist.
---@param facts table|nil
---@return 'enemy'|'friend'|nil
function AuraRows.Reach(facts)
	if type(facts) ~= 'table' then
		return nil
	end
	if Situation.IsHostile(facts) then
		return 'enemy'
	end
	local reaction = facts.reaction
	if type(reaction) ~= 'number' then
		return nil
	end
	return reaction >= 5 and 'friend' or 'enemy'
end

---True when a group shows on a unit with these facts.
---@param applies string|nil Plates.AuraRowGroup.applies
---@param facts table|nil
---@return boolean
function AuraRows.GroupApplies(applies, facts)
	if not applies then
		return true
	end
	if applies == 'hostile' then
		return type(facts) == 'table' and Situation.IsHostile(facts)
	end
	return AuraRows.Reach(facts) == applies
end

---The rows (labels, base groups, Lua scan predicates). Data owners may add groups; never add a
---candidate key outside Schema.CANDIDATE_KEYS.
AuraRows.ROWS = {
	myDebuffs = {
		id = 'myDebuffs',
		label = L['My debuffs'],
		groups = {
			{ key = 'mine', filter = 'HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY|!CROWD_CONTROL', candidates = { nameplateShowPersonal = true } },
			{ key = 'tank', filter = 'HARMFUL', spellList = 'debuffOnEnemy', clients = { forever = true } },
		},
		scanFilter = 'HARMFUL',
		scan = function(aura, ctx)
			if aura.isFromPlayerOrPlayerPet then
				return true
			end
			return ctx.tankDebuffs ~= nil and ctx.tankDebuffs[aura.spellId] ~= nil
		end,
	},
	removable = {
		id = 'removable',
		label = L['Enemy buffs I can remove'],
		groups = {
			{ key = 'removable', filter = 'HELPFUL|DISPELLABLE' },
			{ key = 'important', filter = 'HELPFUL|IMPORTANT|!DISPELLABLE', option = 'important' },
		},
		scanFilter = 'HELPFUL',
		scan = function(aura)
			return aura.isStealable == true or aura.dispelName == 'Magic' or aura.dispelName == 'Enrage'
		end,
	},
	crowdControl = {
		id = 'crowdControl',
		label = L['Crowd control'],
		groups = {
			{ key = 'cc', filter = 'HARMFUL|CROWD_CONTROL' },
		},
		scanFilter = 'HARMFUL|CROWD_CONTROL',
		scan = function(aura, ctx)
			return ctx.ccFromToken == true or (P.Data.CrowdControl[aura.spellId] == true)
		end,
	},
	custom = {
		id = 'custom',
		label = L['My spell list'],
		groups = {},
		scanFilter = 'HARMFUL',
		scan = function()
			return false
		end,
	},
}

---True unless the player switched the row off (profile.auras[row].on == false). Reads the DB on
---every call without building a path table (this runs on every plate add).
---@param rowId string
---@return boolean
function AuraRows.RowOn(rowId)
	local profile = P.db and P.db.profile
	local auras = profile and profile.auras
	local row = type(auras) == 'table' and auras[rowId]
	return not (type(row) == 'table' and row.on == false)
end

---Why an aura row feature cannot work on this client, as a sentence for the player, or nil when
---it can (options and designer badges). Features: 'rows', 'pandemic', 'tints', 'important',
---'tankDebuffs', 'lists' (with a row id).
---@param feature string
---@param rowId? string
---@return string|nil
function AuraRows.Limit(feature, rowId)
	local containers = P.Caps:Get('containers')
	local secrets = P.Caps:Get('secrets')
	if feature == 'rows' then
		if secrets and not containers then
			return L['This game version cannot show aura rows on these plates.']
		end
	elseif feature == 'pandemic' then
		if containers and not P.Caps:Get('pandemic') then
			return L['This game version cannot show the refresh glow on aura icons.']
		end
	elseif feature == 'tints' then
		if not P.Caps:Get('auraSlots') then
			if secrets then
				return L['This game version cannot tint plates by their auras.']
			end
		end
	elseif feature == 'important' then
		if containers and not AuraRows.KnowsToken(AuraRows.Token('Important', 'IMPORTANT')) then
			return L['This game version cannot tell which enemy buffs are important.']
		end
	elseif feature == 'tankDebuffs' then
		if P.Caps:Client() == 'retail' then
			return L['Tank debuffs from other players are not part of this game version.']
		end
	elseif feature == 'lists' then
		if containers and rowId == 'removable' then
			return L['The game does not let spell lists pick enemy buffs, so this row shows every buff you can remove.']
		end
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- Aura buttons (built in initializeFrame, restyled only while not restricted)
----------------------------------------------------------------------------------------------------

local buttonParts = setmetatable({}, { __mode = 'k' }) -- aura button -> our regions and switches
local pandemicRecorded = false

local function DispelStyle()
	local enum = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
	return enum and enum.PreserveAsset
end

local function BuildButton(button)
	local p = {}
	if button.EnableMouse then
		button:EnableMouse(false) -- icons on plates never catch clicks meant for the plate
	end
	if button.EnableMouseMotion then
		button:EnableMouseMotion(false)
	end
	if button.SetFlattensRenderLayers then
		button:SetFlattensRenderLayers(true)
	end
	local white = White()
	p.ink = button:CreateTexture(nil, 'BACKGROUND', nil, 0)
	p.ink:SetTexture(white)
	p.ink:SetAllPoints(button)
	p.dispel = button:CreateTexture(nil, 'BACKGROUND', nil, 1)
	p.dispel:SetTexture(white)
	p.dispel:SetAllPoints(button)
	p.dispel:Hide()
	p.icon = button:CreateTexture(nil, 'ARTWORK')
	p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	p.icon:SetAllPoints(button)
	p.cooldown = CreateFrame('Cooldown', nil, button)
	p.cooldown:SetAllPoints(p.icon)
	if p.cooldown.SetReverse then
		p.cooldown:SetReverse(true)
	end
	if p.cooldown.SetDrawEdge then
		p.cooldown:SetDrawEdge(false)
	end
	if p.cooldown.SetDrawBling then
		p.cooldown:SetDrawBling(false)
	end
	if p.cooldown.SetHideCountdownNumbers then
		p.cooldown:SetHideCountdownNumbers(true)
	end
	p.texts = CreateFrame('Frame', nil, button)
	p.texts:SetAllPoints(button)
	local okLevel, level = pcall(button.GetFrameLevel, button)
	level = okLevel and P.Secret.Plain(level) or nil
	if type(level) == 'number' then
		p.texts:SetFrameLevel(level + 4)
	end
	local face = P.services.FontPath()
	p.timer = p.texts:CreateFontString(nil, 'OVERLAY')
	p.timer:SetFont(face, 9, 'OUTLINE')
	p.timer:SetPoint('CENTER', button, 'CENTER', 0, 0)
	p.timer:Hide()
	p.stacks = p.texts:CreateFontString(nil, 'OVERLAY')
	p.stacks:SetFont(face, 9, 'OUTLINE')
	p.stacks:SetPoint('BOTTOMRIGHT', button, 'BOTTOMRIGHT', 1, 0)
	p.stacks:Hide()
	button:SetIcon(p.icon)
	button:SetDurationCooldown(p.cooldown)
	buttonParts[button] = p
	return p
end

---The pandemic glow: a P.GlowLib glow made the first time a row asks for it. Its fade frame is the
---region the engine shows in the refresh window; 12.1.5 and Forever also play our pulse then.
local function PandemicGlow(button, p)
	local glow = p.pandemic
	if glow then
		return glow
	end
	glow = P.GlowLib.Create(button)
	p.pandemic = glow
	if button.AddPandemicActiveAnimation and glow.pulse.CreateAnimationGroup then
		local look = P.GlowLib.LOOKS.pandemic.pulse
		local group = glow.pulse:CreateAnimationGroup()
		local fade = group:CreateAnimation('Alpha')
		fade:SetFromAlpha(1)
		fade:SetToAlpha(look and look.to or 0.3)
		fade:SetDuration(look and look.duration or 0.8)
		group:SetLooping('BOUNCE')
		p.pulse = group
	end
	return glow
end

local function PandemicOn(button, p, s)
	local glow = PandemicGlow(button, p)
	local Glow = P.GlowLib
	Glow.Layout(glow, button, { look = 'pandemic', size = s.glowSize, animate = 'none' })
	Glow.SetColor(glow, s.glow[1], s.glow[2], s.glow[3], s.glow[4])
	if p.pandemicOn then
		return
	end
	Glow.Show(glow, true)
	local handle = button:AddPandemicRegion(glow.fade)
	-- 12.1.0 hands back an index and removes by index; 12.1.5 and Forever remove by region
	if type(handle) ~= 'number' or button.AddPandemicEnterAnimation then
		handle = glow.fade
	end
	p.pandemicHandle = handle
	p.pandemicOn = true
	if p.pulse and button.AddPandemicActiveAnimation then
		button:AddPandemicActiveAnimation(p.pulse)
		p.pulseOn = true
	end
end

local function PandemicOff(button, p)
	if not p.pandemicOn then
		return
	end
	if button.RemovePandemicRegion then
		button:RemovePandemicRegion(p.pandemicHandle)
	end
	if p.pulseOn and button.RemovePandemicActiveAnimation then
		button:RemovePandemicActiveAnimation(p.pulse)
	end
	p.pulseOn = false
	p.pandemicOn = false
	p.pandemicHandle = nil
	if p.pandemic then
		P.GlowLib.Hide(p.pandemic, true)
	end
end

---Apply a button style. Only call while not restricted (or from initializeFrame); skips forbidden
---buttons.
---@param button table
---@param s table Button style from the row's desired settings
---@return boolean styled
local function StyleButton(button, s)
	if button.IsForbidden and button:IsForbidden() then
		return false
	end
	local p = buttonParts[button]
	if not p then
		return false
	end
	button:SetSize(s.size, s.size)
	local inset = s.border == 'none' and 0 or s.inset
	p.icon:ClearAllPoints()
	p.icon:SetPoint('TOPLEFT', button, 'TOPLEFT', inset, -inset)
	p.icon:SetPoint('BOTTOMRIGHT', button, 'BOTTOMRIGHT', -inset, inset)
	if s.border == 'none' then
		p.ink:Hide()
	else
		p.ink:SetVertexColor(s.ink[1], s.ink[2], s.ink[3], s.ink[4])
		p.ink:Show()
	end

	-- The dispel border: the engine shows it and colors it by dispel type (PreserveAsset keeps
	-- our white texture and tints it); auras without a dispel type keep the pixel border
	local dispelStyle = DispelStyle()
	local wantDispel = s.border == 'dispel' and dispelStyle ~= nil and button.AddDispelTypeTexture ~= nil
	if wantDispel and not p.dispelOn then
		button:AddDispelTypeTexture(p.dispel, { style = dispelStyle, showWhenHarmful = true, showWhenHelpful = true })
		p.dispelOn = true
	elseif not wantDispel and p.dispelOn then
		if button.ClearDispelTypeTextures then
			button:ClearDispelTypeTextures()
		end
		p.dispel:Hide()
		p.dispelOn = false
	end

	p.timer:SetFont(s.face, s.fontSize, s.flags)
	p.stacks:SetFont(s.face, s.fontSize, s.flags)
	if s.timer and not p.timerOn then
		button:SetDurationText(p.timer, {})
		p.timer:Show()
		p.timerOn = true
	elseif not s.timer and p.timerOn then
		button:ClearDurationText()
		p.timer:Hide()
		p.timerOn = false
	end
	if s.stacks and not p.stacksOn then
		button:SetApplicationCount(p.stacks, {})
		p.stacks:Show()
		p.stacksOn = true
	elseif not s.stacks and p.stacksOn then
		button:ClearApplicationCount()
		p.stacks:Hide()
		p.stacksOn = false
	end

	if s.pandemic and button.AddPandemicRegion ~= nil then
		PandemicOn(button, p, s)
	else
		PandemicOff(button, p)
	end
	return true
end

----------------------------------------------------------------------------------------------------
-- Container pool (per plate)
----------------------------------------------------------------------------------------------------

---@class Plates.AuraContainers
local Containers = { built = 0, buttons = 0, MAX_PER_PLATE = 3, MAX_GROUPS = #GROUP_KEYS }
P.AuraContainers = Containers
Containers.GROUP_KEYS = GROUP_KEYS

local pools = setmetatable({}, { __mode = 'k' }) -- plate -> { free = { rec, ... }, count = n }

---@class Plates.AuraContainerRec Our bookkeeping for one container (never fields on the frame)
---@field container table AuraContainer
---@field plate Plates.Plate
---@field groups integer Groups added so far
---@field buttons table[] Aura buttons made so far
---@field owner? table Widget using it
---@field parent? table Frame it is parented to
---@field active (string|false)[] Reach rule per used group, for the per-add flips
---@field max table<string, number> Last max frame count sent per group
---@field unit? string Last unit sent
---@field enabled? boolean
---@field key? string Signature of the settings last applied

local function InitButton(rec, button)
	local ok, err = pcall(BuildButton, button)
	if not ok then
		WarnOnce('initButton', 'Could not set up an aura icon; that icon stays empty: ' .. tostring(err))
		return
	end
	rec.buttons[#rec.buttons + 1] = button
	Containers.buttons = Containers.buttons + 1
	if not pandemicRecorded then
		pandemicRecorded = true
		P.Caps:Record('pandemic', button.AddPandemicRegion ~= nil)
	end
	if rec.style then
		local okStyle, styleErr = pcall(StyleButton, button, rec.style)
		if not okStyle then
			P.log.debug('Aura icon style failed: ' .. tostring(styleErr))
		end
	end
end

local function NewRec(plate, parent)
	local ok, container = pcall(CreateFrame, 'AuraContainer', nil, parent, 'CustomAuraContainerTemplate')
	if not ok or not container then
		P.Caps:Record('containers', false)
		P.log.warning('The game would not make an aura row, so aura rows stay empty: ' .. tostring(container))
		return nil
	end
	local rec = { container = container, plate = plate, parent = parent, groups = 0, buttons = {}, active = {}, max = {}, filter = {}, cand = {}, sort = {}, layout = {}, groupOn = {} }
	rec.init = function(button)
		InitButton(rec, button)
	end
	Call(container, 'SetEnabled', false)
	Call(container, 'SetUnit', 'none')
	rec.enabled, rec.unit = false, 'none'
	Containers.built = Containers.built + 1
	return rec
end

---Stop a container: disabled and bound to 'none' (the engine stops reading auras for it).
---@param rec Plates.AuraContainerRec
function Containers:Disable(rec)
	if rec.enabled ~= false then
		Call(rec.container, 'SetEnabled', false)
		rec.enabled = false
	end
	if rec.unit ~= 'none' then
		Call(rec.container, 'SetUnit', 'none')
		rec.unit = 'none'
	end
end

local function InCurrentStyle(plate, widget)
	local parts = plate.style and plate.style.parts
	local spec = parts and parts[widget.id]
	return spec ~= nil and spec.kind == 'auras'
end

---Hang a container under another row's holder. Only while not restricted. The first real move
---records capability 'containerMove'; a refused move turns moving off for the session.
---@param rec Plates.AuraContainerRec
---@param holder table
---@return boolean moved
local function Move(rec, holder)
	local c = rec.container
	local ok = Call(c, 'SetParent', holder)
	local okParent, parent = pcall(c.GetParent, c)
	local moved = ok and okParent and parent == holder
	P.Caps:Record('containerMove', moved)
	if not moved then
		WarnOnce('containerMove', 'The game would not move an aura row to another spot; new rows get their own')
		return false
	end
	rec.parent = holder
	rec.corner = nil
	return true
end

---Take a free container from the pool: one already under this holder first, then (when moving
---works) any.
local function TakeFree(pool, holder, any)
	for i = #pool.free, 1, -1 do
		local rec = pool.free[i]
		if rec.parent == holder or any then
			table.remove(pool.free, i)
			return rec
		end
	end
	return nil
end

---A container for one row on a plate, or nil and why ('wait' while the game restricts changes,
---'full' at MAX_PER_PLATE, 'failed' when the client refused). Reuses a free one, then one from a
---row the plate no longer shows, then makes one (never while restricted: S6).
---@param plate Plates.Plate
---@param holder table Frame the container hangs from
---@return Plates.AuraContainerRec|nil
---@return string|nil reason
function Containers:Acquire(plate, holder)
	if IsRestricted() then
		return nil, 'wait'
	end
	local pool = pools[plate]
	if not pool then
		pool = { free = {}, all = {}, count = 0 }
		pools[plate] = pool
	end
	local canMove = P.Caps:Get('containerMove')
	local rec = TakeFree(pool, holder, canMove)
	if not rec and canMove then
		for _, widget in pairs(plate.widgets or EMPTY) do
			if widget.impl and widget.impl.id == IMPL_ID and not widget.active and widget.rec and not InCurrentStyle(plate, widget) then
				rec = widget.rec
				widget.rec = nil
				rec.owner = nil
				break
			end
		end
	end
	if rec then
		self:Disable(rec)
		if rec.parent ~= holder and not Move(rec, holder) then
			pool.free[#pool.free + 1] = rec
			rec = nil
		end
	end
	if not rec then
		if pool.count >= self.MAX_PER_PLATE then
			return nil, 'full'
		end
		rec = NewRec(plate, holder)
		if not rec then
			return nil, 'failed'
		end
		pool.count = pool.count + 1
		pool.all[pool.count] = rec
	end
	return rec
end

---Give a container back to its plate's pool (disabled, bound to 'none'). Runs in combat too.
---@param plate Plates.Plate
---@param rec Plates.AuraContainerRec
function Containers:Release(plate, rec)
	self:Disable(rec)
	if rec.owner and rec.owner.rec == rec then
		rec.owner.rec = nil
	end
	rec.owner = nil
	local pool = pools[plate]
	if pool then
		for i = 1, #pool.free do
			if pool.free[i] == rec then
				return
			end
		end
		pool.free[#pool.free + 1] = rec
	end
end

---Containers made for a plate so far.
---@param plate Plates.Plate
---@return integer
function Containers:CountFor(plate)
	local pool = pools[plate]
	return pool and pool.count or 0
end

---Free containers a plate holds (tests and npbench).
---@param plate Plates.Plate
---@return integer
function Containers:FreeFor(plate)
	local pool = pools[plate]
	return pool and #pool.free or 0
end

---Make the containers a plate's current style needs, ahead of the first pull (out of combat
---only; the plate pool calls this while it pre-warms). Returns false while restricted.
---@param plate Plates.Plate
---@return boolean
function Containers:Prewarm(plate)
	if IsRestricted() then
		return false
	end
	plate:Configure()
	return true
end

---Counts for npbench and S6: containers and aura buttons made this session.
---@return integer containers
---@return integer buttons
function Containers:Stats()
	return self.built, self.buttons
end

----------------------------------------------------------------------------------------------------
-- Desired settings for a row part
----------------------------------------------------------------------------------------------------

local function FlowEnums()
	local util = AnchorUtil
	local axis = type(util) == 'table' and util.FlowLayoutAxis or { Horizontal = 0, Vertical = 1 }
	local dir = type(util) == 'table' and util.FlowDirection or { Left = -1, Right = 1, Up = 1, Down = -1 }
	return axis, dir
end

local SORT = { default = 'Default', time = 'Expiration', name = 'Name' }

local function SortFor(sort)
	local methods, directions = AuraContainerSortMethod, AuraContainerSortDirection
	if type(methods) ~= 'table' or type(directions) ~= 'table' then
		return nil, nil
	end
	local method = methods[SORT[sort] or 'Default'] or methods.Default
	if method == nil or directions.Normal == nil then
		return nil, nil
	end
	return method, directions.Normal
end

local function Color4(value, r, g, b, a)
	if type(value) == 'table' then
		return { value[1] or value.r or r, value[2] or value.g or g, value[3] or value.b or b, value[4] or value.a or a }
	end
	return { r, g, b, a }
end

---Where the container sits in its holder and how it grows. Rows growing sideways wrap upward when
---the part sits above its anchor (a BOTTOM point), else downward; columns wrap away from a RIGHT
---point.
---@param spec table
---@return integer axis
---@return integer horizontal
---@return integer vertical
---@return string corner
function AuraRows.Flow(spec)
	local axisEnum, dir = FlowEnums()
	local grow = spec.grow or 'RIGHT'
	local point = (type(spec.anchor) == 'table' and spec.anchor[1]) or 'CENTER'
	local above = string.find(point, 'BOTTOM', 1, true) ~= nil
	local onRight = string.find(point, 'RIGHT', 1, true) ~= nil
	local axis, h, v
	if grow == 'UP' or grow == 'DOWN' then
		axis = axisEnum.Vertical
		v = grow == 'UP' and dir.Up or dir.Down
		h = onRight and dir.Left or dir.Right
	else
		axis = axisEnum.Horizontal
		h = grow == 'LEFT' and dir.Left or dir.Right
		v = above and dir.Up or dir.Down
	end
	local corner = ((v == dir.Up) and 'BOTTOM' or 'TOP') .. ((h == dir.Right) and 'LEFT' or 'RIGHT')
	return axis, h, v, corner
end

local function Pixel(ctx)
	local ok, px = pcall(ctx.Pixel, ctx)
	if ok and type(px) == 'number' and P.Secret.CanAccess(px) and px > 0 and px < 8 then
		return px
	end
	return 1
end

-- Resolved part spec -> the settings last built from it (weak: specs go with their resolved style;
-- the settings never point back at the spec, so a style that is gone is collected)
local desiredCache = setmetatable({}, { __mode = 'k' })

---Everything a row part asks of its container, plus signatures to skip unchanged calls.
---@param spec table Resolved aura part
---@param ctx Plates.LayoutContext
---@return table
function AuraRows.Desired(spec, ctx)
	-- The same resolved part gives the same settings: plates switching between styles reuse them
	-- (read only; containers keep d.button). Checked against what can change without a new spec:
	-- the groups (aura settings), the plate's pixel size and the font from media.
	local groups = AuraRows.CurrentGroups(spec.row or 'myDebuffs')
	local inset = Pixel(ctx)
	local face, fontSize, flags = ctx:Font(spec.font)
	local cached = desiredCache[spec]
	if cached and cached.groups == groups and cached.button.inset == inset and cached.button.face == face and cached.button.fontSize == fontSize and cached.button.flags == (flags or '') then
		return cached
	end
	local d = {}
	d.row = spec.row or 'myDebuffs'
	d.max = math.max(0, math.floor(spec.max or 6))
	d.size = math.max(1, math.floor(spec.size or 20))
	d.spacing = math.max(0, math.floor(spec.spacing or 2))
	d.groups = groups
	d.sortMethod, d.sortDirection = SortFor(spec.sort)
	d.sortKey = tostring(d.sortMethod) .. ':' .. tostring(d.sortDirection)
	d.axis, d.h, d.v, d.corner = AuraRows.Flow(spec)
	-- Icons per line: a row with several groups (lists, tank debuffs) wraps instead of running
	-- past the part's own length
	local perLine = math.min(math.floor(spec.perRow or d.max), d.max)
	if perLine >= 1 then
		d.lineSize = perLine * d.size + (perLine - 1) * d.spacing + 0.5
	end
	d.flowKey = table.concat({ d.axis, d.h, d.v, d.corner, tostring(d.lineSize) }, ':')
	d.layoutKey = d.size .. ':' .. d.spacing
	local tokens = ctx.style and ctx.style.tokens or EMPTY
	local ink = Color4(tokens.ink, 0, 0, 0, 1)
	local glow = P.GlowLib and P.GlowLib.SOURCE_COLORS and P.GlowLib.SOURCE_COLORS.pandemic or { 1, 0.85, 0.25, 1 }
	local b = {
		size = d.size,
		inset = inset,
		border = spec.borderStyle or 'pixel',
		timer = spec.timer ~= false,
		stacks = spec.stacks ~= false,
		pandemic = spec.pandemic == true,
		face = face,
		fontSize = fontSize,
		flags = flags or '',
		ink = ink,
		glow = { glow[1], glow[2], glow[3], glow[4] or 1 },
		glowSize = math.max(1, math.floor(d.size / 10 + 0.5)),
	}
	d.button = b
	d.buttonKey = table.concat({
		b.size,
		b.inset,
		b.border,
		tostring(b.timer),
		tostring(b.stacks),
		tostring(b.pandemic),
		tostring(face),
		fontSize,
		b.flags,
		table.concat(ink, ','),
		table.concat(b.glow, ','),
		b.glowSize,
	}, '|')
	local sigs = {}
	for i, group in ipairs(d.groups) do
		sigs[i] = group.sig
	end
	d.key = table.concat(sigs, '/') .. '|' .. d.sortKey .. '|' .. d.layoutKey .. '|' .. d.flowKey .. '|' .. d.buttonKey
	desiredCache[spec] = d
	return d
end

----------------------------------------------------------------------------------------------------
-- Applying settings (only while not restricted) and the per-add flips (always)
----------------------------------------------------------------------------------------------------

local pendingWidgets = setmetatable({}, { __mode = 'k' })

local function SetMax(rec, key, count)
	if rec.max[key] ~= count then
		if Call(rec.container, 'SetAuraGroupMaxFrameCount', key, count) then
			rec.max[key] = count
		end
	end
end

-- 12.1.5 and Forever: a group that is off also leaves the layout (12.1.0 has max 0 only)
local function GroupOn(rec, key, on)
	if rec.container.SetAuraGroupEnabled and rec.groupOn[key] ~= on then
		if Call(rec.container, 'SetAuraGroupEnabled', key, on) then
			rec.groupOn[key] = on
		end
	end
end

local function GroupLayout(d, index)
	return {
		elementSpacing = d.spacing,
		lineSpacing = d.spacing,
		groupSpacing = d.spacing,
		groupLineSpacing = d.spacing,
		elementWidth = d.size,
		elementHeight = d.size,
		layoutIndex = index,
	}
end

local function RestyleButtons(rec)
	local styled = 0
	for _, button in ipairs(rec.buttons) do
		local ok, done = pcall(StyleButton, button, rec.style)
		if ok and done then
			styled = styled + 1
		elseif not ok then
			P.log.debug('Aura icon style failed: ' .. tostring(done))
		end
	end
	return styled
end

---Send a row's settings to its container. Returns true when applied, else why it waits ('wait'
---while restricted, 'full' at the per-plate limit, 'failed' when the client refused).
---@param widget table
---@return boolean|string
local function ApplyConfig(widget)
	local d = widget.desired
	if not d then
		return true
	end
	if IsRestricted() then
		return 'wait'
	end
	local rec = widget.rec
	if not rec then
		local reason
		rec, reason = Containers:Acquire(widget.plate, widget.frame)
		if not rec then
			return reason or 'failed'
		end
		widget.rec = rec
	end
	rec.owner = widget
	local c = rec.container

	if rec.styleKey ~= d.buttonKey then
		rec.style = d.button
		RestyleButtons(rec)
		rec.styleKey = d.buttonKey
	end

	local used, complete = 0, true
	for i, group in ipairs(d.groups) do
		local key = GROUP_KEYS[i]
		if not key then
			WarnOnce('groups', 'An aura row asked for more groups than a row can hold; the extra ones are left out')
			break
		end
		if i > rec.groups then
			local ok = Call(c, 'AddAuraGroup', key, group.filter, {
				initializeFrame = rec.init,
				maxFrameCount = 0,
				candidateFilters = group.candidates,
				sortMethod = d.sortMethod,
				sortDirection = d.sortDirection,
				layout = GroupLayout(d, i),
			})
			if not ok then
				complete = false
				break
			end
			rec.groups = i
			rec.filter[key], rec.cand[key], rec.sort[key], rec.layout[key], rec.max[key] = group.filter, group.sig, d.sortKey, d.layoutKey .. ':' .. i, 0
			rec.groupOn[key] = true
		else
			if rec.filter[key] ~= group.filter and Call(c, 'SetAuraGroupFilterString', key, group.filter) then
				rec.filter[key] = group.filter
			end
			if rec.cand[key] ~= group.sig and Call(c, 'SetAuraGroupCandidateFilters', key, group.candidates or {}) then
				rec.cand[key] = group.sig
			end
			if d.sortMethod ~= nil and rec.sort[key] ~= d.sortKey and Call(c, 'SetAuraGroupSortMethod', key, d.sortMethod, d.sortDirection) then
				rec.sort[key] = d.sortKey
			end
			if rec.layout[key] ~= d.layoutKey .. ':' .. i and Call(c, 'SetAuraGroupLayout', key, GroupLayout(d, i)) then
				rec.layout[key] = d.layoutKey .. ':' .. i
			end
			GroupOn(rec, key, true)
		end
		used = i
	end
	-- Groups this row does not use (another row or older settings had them): off
	for i = used + 1, rec.groups do
		SetMax(rec, GROUP_KEYS[i], 0)
		GroupOn(rec, GROUP_KEYS[i], false)
	end
	for i = #rec.active, 1, -1 do
		rec.active[i] = nil
	end
	for i = 1, used do
		rec.active[i] = d.groups[i].applies or false
	end

	if rec.flowKey ~= d.flowKey then
		Call(c, 'SetFlowLayoutAxis', d.axis)
		Call(c, 'SetFlowLayoutAnchorPoint', d.corner)
		Call(c, 'SetFlowLayoutGrowthDirection', d.h, d.v)
		Call(c, 'SetFlowLayoutPadding', 0, 0, 0, 0)
		Call(c, 'SetFlowLayoutMaximumLineSize', d.lineSize)
		rec.flowKey = d.flowKey
	end
	if rec.corner ~= d.corner then
		c:ClearAllPoints()
		c:SetPoint(d.corner, widget.frame, d.corner, 0, 0)
		rec.corner = d.corner
	end
	-- A group the game refused is tried again on the next Configure
	rec.key = complete and d.key or nil
	return true
end

---The per-add flips: unit, enabled and max frame counts by the unit's reach. Runs in combat.
---@param widget table
local function Flip(widget)
	local rec = widget.rec
	if not rec or rec.owner ~= widget then
		return
	end
	local plate = widget.plate
	local d = widget.desired
	local unit = plate.unit
	local wanted = widget.active and d ~= nil and d.max > 0 and AuraRows.RowOn(d.row)
	local any = false
	if unit ~= nil or not wanted then
		-- A row switched off gets max 0 on every group as well as 'none'; between units only
		-- the binding changes
		local facts = plate.facts
		for i = 1, #rec.active do
			local count = 0
			if wanted and AuraRows.GroupApplies(rec.active[i] or nil, facts) then
				count = d.max
				any = true
			end
			SetMax(rec, GROUP_KEYS[i], count)
		end
	end
	if any then
		if rec.unit ~= unit then
			Call(rec.container, 'SetUnit', unit)
			rec.unit = unit
		end
		if rec.enabled ~= true then
			Call(rec.container, 'SetEnabled', true)
			rec.enabled = true
		end
	else
		Containers:Disable(rec)
	end
end

local function FlushPending()
	if IsRestricted() or next(pendingWidgets) == nil then
		return
	end
	local plates = {}
	for widget in pairs(pendingWidgets) do
		pendingWidgets[widget] = nil
		if widget.active and widget.plate and widget.plate.style then
			plates[widget.plate] = true
		end
	end
	for plate in pairs(plates) do
		plate:Configure()
	end
end
Containers.FlushPending = FlushPending

local function MarkPending(widget)
	pendingWidgets[widget] = true
	widget.plate.pendingConfigure = true
	if InLockdown() then
		P.Scheduler:AfterCombat('aurasContainer.flush', FlushPending)
	end
end

---True when the widget's settings wait for the game to allow aura changes.
---@param widget table
---@return boolean
function Containers:IsPending(widget)
	return pendingWidgets[widget] == true
end

---Send the desired settings now, or keep them pending. A row that is off makes no container.
local function Sync(widget)
	local d = widget.desired
	local rec = widget.rec
	widget.noRoom = nil
	if rec and rec.owner == widget and rec.key == d.key then
		pendingWidgets[widget] = nil
		Flip(widget)
		return
	end
	if not rec and (d.max == 0 or not AuraRows.RowOn(d.row) or #d.groups == 0) then
		pendingWidgets[widget] = nil
		return
	end
	local result = ApplyConfig(widget)
	if result == true then
		pendingWidgets[widget] = nil
	elseif result == 'wait' then
		MarkPending(widget)
	else
		-- No room (or the client refused): the row stays empty until the style changes
		pendingWidgets[widget] = nil
		widget.noRoom = result
		if result == 'full' then
			WarnOnce('full', 'A plate holds at most ' .. Containers.MAX_PER_PLATE .. ' aura rows; the rest stay empty')
		end
	end
	Flip(widget)
end

---Why a live row shows nothing, as plain words for the inspector, or nil when it is drawing.
---@param widget table
---@return string|nil
function Containers:Explain(widget)
	if not widget or not widget.desired then
		return nil
	end
	local d = widget.desired
	if widget.noRoom == 'full' then
		return string.format(L['A plate can show %d aura rows. This row is one too many.'], Containers.MAX_PER_PLATE)
	elseif widget.noRoom then
		return L['The game would not make this aura row.']
	elseif pendingWidgets[widget] then
		return L['The game does not allow aura changes right now. They apply after combat.']
	elseif not AuraRows.RowOn(d.row) then
		return L['This row is turned off.']
	elseif d.max == 0 or #d.groups == 0 then
		return L['This row has nothing to show.']
	end
	return nil
end

P.Parts:Register({
	id = IMPL_ID,
	kinds = { 'auras' },
	priority = 10,
	match = function(_, plate)
		return not plate.isPreview and P.Caps:Get('containers')
	end,
	messages = { 'FACTS_POLLED' },
	Create = function(plate)
		local holder = CreateFrame('Frame', nil, plate.art)
		return { frame = holder }
	end,
	Layout = function(widget, spec, ctx)
		local w, h = P.Styles.Merge.PartSize(spec, ctx.width, ctx.height)
		widget.frame:SetSize(w, h)
		ctx:Anchor(widget.frame, spec.anchor)
		widget.desired = AuraRows.Desired(spec, ctx)
		Sync(widget)
	end,
	Configure = function(widget, spec, ctx)
		widget.desired = AuraRows.Desired(spec, ctx)
		Sync(widget)
	end,
	Update = function(widget, _, event)
		if event == 'FULL' or event == 'FACTS_POLLED' then
			Flip(widget)
		end
	end,
	Reset = function(widget)
		local rec = widget.rec
		if rec and rec.owner == widget then
			Containers:Disable(rec)
		end
	end,
})

-- Rows the new style no longer shows give their containers back at once (disabled, so the engine
-- stops reading auras for a hidden row). Runs in combat too: only SetEnabled and SetUnit.
P:On('STYLE_APPLIED', function(plate)
	if not plate or plate.isPreview or not pools[plate] then
		return
	end
	for _, widget in pairs(plate.widgets) do
		if widget.impl and widget.impl.id == IMPL_ID and not widget.active and widget.rec then
			pendingWidgets[widget] = nil
			Containers:Release(plate, widget.rec)
		end
	end
end, Containers)
P:On('STORE_CHANGED', function(reasons)
	if reasons and (reasons.auras or reasons.look) then
		AuraRows.Invalidate()
	end
end, Containers)
P:On('PROFILE_CHANGED', function()
	AuraRows.Invalidate()
end, Containers)
P:On('RESTRICTION_CHANGED', function(isRestricted)
	if not isRestricted then
		FlushPending()
	end
end, Containers)
P:On('ENGINE_DISABLED', function()
	P.util.Wipe(pendingWidgets)
	for _, pool in pairs(pools) do
		for _, rec in ipairs(pool.all) do
			Containers:Disable(rec)
		end
	end
end, Containers)

P.Caps:AddProbe('pandemic', function()
	return P.Caps:Get('containers')
end, 'Aura icons can glow in the pandemic window (the first aura icon records the real answer)')
P.Caps:AddProbe('containerMove', function()
	return P.Caps:Get('containers')
end, 'An aura row can move to another spot on its plate (the first real move records the answer; off: new rows get their own)')

----------------------------------------------------------------------------------------------------
-- Aura presence tints (Phase 5, S19): "Has a spell" and "My debuff is missing" color rows
----------------------------------------------------------------------------------------------------
-- Only while such a row is in the health bar's color list. A "slots" container holds one
-- AddAuraSlot button per tracked spell (includeSpellIDs), each with SetCollapsesLayout(true): a
-- slot with no aura collapses to nothing. Tint textures sit on the health bar over its fill and
-- are masked by a mask that hangs from the slots (made on DisableUntrustedLayoutScriptsTemplate
-- frames), so the engine moves the mask onto the bar when the aura is up ("Has") or when none
-- of the spells are up ("Missing"). No aura is ever read.
--   Has:     a slot below the bar (BOTTOMLEFT at -D); the mask sits on the slot's top, so it
--            covers the bar while the aura is up.
--   Missing: N slots chained below the bar (from -N*D) and a pillar N*D tall on the last one; the
--            mask sits on the pillar's top, so it covers the bar only while every slot is empty.
-- D is taller than the bar can grow, so target growth never leaves a strip uncovered.
-- Spell lists only apply to debuffs on units the player cannot help, so slots and tints are on
-- only there (AuraRows.Reach == 'enemy'). Only the health piece is tinted; the border piece keeps
-- its other rows. Spells per row: profile.colors[piece].spells[rowId] = { [spellID] = 'mine'|'any' }.
-- Classic family: the auraPresent and auraMissing conditions answer from plain reads (AurasScan),
-- so these rows work there without slots.

---@class Plates.AuraPresence
local Presence = { MAX_SLOTS = 12, MARGIN = 32 }
P.AuraPresence = Presence
Presence.KINDS = { hasAura = 'has', auraMissing = 'missing' }

local presence = setmetatable({}, { __mode = 'k' }) -- plate -> state
local presencePending = setmetatable({}, { __mode = 'k' })
local NEVER = { [0] = true }

P.Caps:AddProbe('auraSlots', function()
	if not P.Caps:Get('containers') then
		return false
	end
	local frame = CreateFrame('Frame')
	return frame.SetCollapsesLayout ~= nil
end, 'Aura slots can collapse, for the "Has a spell" and "My debuff is missing" tints')

local function HealthWidget(plate)
	for i = 1, #plate.active do
		local widget = plate.active[i]
		if widget.impl.id == 'health' and widget.bar then
			return widget
		end
	end
	return nil
end

---Presence rows in the plate's health color list, top first. Empty until Phase 5 makes the two
---row kinds available.
---@param plate Plates.Plate
---@return table[] rows
---@return table|nil health The health widget
function Presence:Rows(plate)
	local out = {}
	local health = HealthWidget(plate)
	if not health or not plate.style then
		return out, nil
	end
	local piece = health.spec.colors or 'health'
	local program = P.Colors:Program(piece, plate.env.ctx)
	for rank, row in ipairs(program.rows) do
		local kind = self.KINDS[row.id]
		if kind then
			local mine, any = AuraRows.SpellSets(P.Store:Get({ 'colors', piece, 'spells', row.id }))
			if next(mine) or next(any) then
				out[#out + 1] = { kind = kind, id = row.id, rank = rank, color = row.color or { 1, 1, 1, 1 }, when = row.when, mine = mine, any = any }
			end
		end
	end
	return out, health
end

local function SlotInit(button)
	if button.EnableMouse then
		button:EnableMouse(false)
	end
	if button.EnableMouseMotion then
		button:EnableMouseMotion(false)
	end
	if button.SetCollapsesLayout then
		button:SetCollapsesLayout(true)
	end
end

local function Tint(st, index, bar, texture)
	local tint = st.tints[index]
	if not tint then
		tint = bar:CreateTexture(nil, 'OVERLAY', nil, 6)
		local mask = st.wrap:CreateMaskTexture()
		mask:SetTexture(White(), 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE')
		tint:AddMaskTexture(mask)
		st.tints[index] = tint
		st.masks[index] = mask
	end
	tint:SetTexture(texture)
	tint:ClearAllPoints()
	tint:SetPoint('TOPLEFT', bar, 'TOPLEFT', 0, 0)
	local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if fill then
		tint:SetPoint('BOTTOMRIGHT', fill, 'BOTTOMRIGHT', 0, 0)
	else
		tint:SetPoint('BOTTOMRIGHT', bar, 'BOTTOMRIGHT', 0, 0)
	end
	return tint, st.masks[index]
end

local function HideTints(st, from)
	for i = from or 1, #st.tints do
		st.tints[i]:Hide()
	end
end

---Stop a plate's slots (disabled, 'none') and hide its tints.
---@param plate Plates.Plate
function Presence:Disable(plate)
	local st = presence[plate]
	if not st then
		return
	end
	if st.enabled ~= false then
		Call(st.container, 'SetEnabled', false)
		st.enabled = false
	end
	if st.unit ~= 'none' then
		Call(st.container, 'SetUnit', 'none')
		st.unit = 'none'
	end
	HideTints(st)
end

local function Slot(st, index, filter, spellID)
	local key = 's' .. index
	local candidates = { includeSpellIDs = { [spellID] = true } }
	local sig = filter .. '#' .. spellID
	local frame = st.slots[index]
	if not frame then
		local ok, made = Call(st.container, 'AddAuraSlot', key, filter, { candidateFilters = candidates, initializeFrame = SlotInit })
		if not ok or not made then
			return nil
		end
		st.slots[index] = made
		st.sig[index] = sig
		return made
	end
	if st.sig[index] ~= sig then
		Call(st.container, 'SetAuraSlotFilterString', key, filter)
		Call(st.container, 'SetAuraSlotCandidateFilters', key, candidates)
		st.sig[index] = sig
	end
	if st.container.SetAuraSlotEnabled then
		Call(st.container, 'SetAuraSlotEnabled', key, true)
	end
	return frame
end

local function ParkSlot(st, index)
	local key = 's' .. index
	if st.container.SetAuraSlotEnabled then
		Call(st.container, 'SetAuraSlotEnabled', key, false)
	elseif st.sig[index] ~= 'never' then
		-- 12.1.0 has no slot switch: a spell list nothing matches (slots only run where debuff
		-- lists apply)
		Call(st.container, 'SetAuraSlotCandidateFilters', key, { includeSpellIDs = NEVER })
		st.sig[index] = 'never'
	end
end

local function SpellsOf(row)
	local spells = {}
	for id in pairs(row.mine) do
		spells[#spells + 1] = { id, 'HARMFUL|PLAYER' }
	end
	for id in pairs(row.any) do
		if not row.mine[id] then
			spells[#spells + 1] = { id, 'HARMFUL' }
		end
	end
	table.sort(spells, function(a, b)
		return a[1] < b[1]
	end)
	return spells
end

local function PaintTint(st, index, bar, texture, row, anchor, D)
	local tint, mask = Tint(st, index, bar, texture)
	tint:SetDrawLayer('OVERLAY', math.max(-8, math.min(7, 7 - row.rank)))
	tint:SetVertexColor(row.color[1], row.color[2], row.color[3], row.color[4] or 1)
	mask:ClearAllPoints()
	mask:SetPoint('BOTTOMLEFT', anchor, 'TOPLEFT', 0, 0)
	mask:SetPoint('BOTTOMRIGHT', anchor, 'TOPRIGHT', 0, 0)
	mask:SetHeight(D)
	st.rowOf[index] = row
end

---Build or repoint a plate's slots and tints. Only while not restricted (else pending).
---@param plate Plates.Plate
---@return boolean applied
function Presence:Configure(plate)
	if plate.isPreview then
		return true
	end
	local rows, health = self:Rows(plate)
	local st = presence[plate]
	if #rows == 0 then
		presencePending[plate] = nil
		if st then
			st.rows = rows
			self:Disable(plate)
		end
		return true
	end
	if not P.Caps:Get('auraSlots') then
		WarnOnce('auraSlots', 'This game cannot move aura tints, so "Has a spell" and "My debuff is missing" colors stay off')
		if st then
			st.rows = EMPTY
			self:Disable(plate)
		end
		return true
	end
	if IsRestricted() then
		presencePending[plate] = true
		plate.pendingConfigure = true
		if InLockdown() then
			P.Scheduler:AfterCombat('auraPresence.flush', function()
				Presence:FlushPending()
			end)
		end
		return false
	end
	presencePending[plate] = nil
	if not st then
		local ok, container = pcall(CreateFrame, 'AuraContainer', nil, plate.art, 'CustomAuraContainerTemplate')
		if not ok or not container then
			WarnOnce('slotsContainer', 'The game would not make the aura tint helper: ' .. tostring(container))
			return true
		end
		st = { container = container, slots = {}, sig = {}, tints = {}, masks = {}, pillars = {}, rowOf = {} }
		st.wrap = CreateFrame('Frame', nil, plate.art, 'DisableUntrustedLayoutScriptsTemplate')
		st.wrap:SetAllPoints(plate.art)
		presence[plate] = st
		self:Disable(plate)
	end
	st.rows = rows

	local bar = health.bar
	local W, H = P.Styles.Merge.PartSize(health.spec, plate.style.width, plate.style.height)
	local D = H + self.MARGIN
	local slotW = W + self.MARGIN * 2
	local texture = P.LayoutContext.Texture(P.LayoutContext, health.spec.texture) or White()
	local slotIndex, tintIndex = 0, 0
	for _, row in ipairs(rows) do
		local spells = SpellsOf(row)
		if row.kind == 'has' then
			for _, spell in ipairs(spells) do
				if slotIndex < self.MAX_SLOTS then
					slotIndex = slotIndex + 1
					local slot = Slot(st, slotIndex, spell[2], spell[1])
					if slot then
						slot:ClearAllPoints()
						slot:SetPoint('BOTTOMLEFT', bar, 'BOTTOMLEFT', 0, -D)
						slot:SetSize(slotW, D)
						tintIndex = tintIndex + 1
						PaintTint(st, tintIndex, bar, texture, row, slot, D)
					end
				end
			end
		else
			local count = math.min(#spells, self.MAX_SLOTS - slotIndex)
			local last
			for i = 1, count do
				slotIndex = slotIndex + 1
				local slot = Slot(st, slotIndex, spells[i][2], spells[i][1])
				if slot then
					slot:ClearAllPoints()
					if last then
						slot:SetPoint('BOTTOMLEFT', last, 'TOPLEFT', 0, 0)
					else
						slot:SetPoint('BOTTOMLEFT', bar, 'BOTTOMLEFT', 0, -D * count)
					end
					slot:SetSize(slotW, D)
					last = slot
				end
			end
			if last then
				tintIndex = tintIndex + 1
				local pillar = st.pillars[tintIndex]
				if not pillar then
					pillar = CreateFrame('Frame', nil, plate.art, 'DisableUntrustedLayoutScriptsTemplate')
					st.pillars[tintIndex] = pillar
				end
				pillar:ClearAllPoints()
				pillar:SetPoint('BOTTOMLEFT', last, 'TOPLEFT', 0, 0)
				pillar:SetSize(slotW, D * count)
				PaintTint(st, tintIndex, bar, texture, row, pillar, D)
			end
		end
	end
	for i = slotIndex + 1, #st.slots do
		ParkSlot(st, i)
	end
	st.used = tintIndex
	HideTints(st, tintIndex + 1)
	self:Flip(plate)
	return true
end

---Per-add: bind the slots to the unit and show the tints of rows that apply here. Runs in combat.
---@param plate Plates.Plate
function Presence:Flip(plate)
	local st = presence[plate]
	if not st or not st.rows or #st.rows == 0 then
		return
	end
	local unit = plate.unit
	if not unit or AuraRows.Reach(plate.facts) ~= 'enemy' or (st.used or 0) == 0 then
		self:Disable(plate)
		return
	end
	if st.unit ~= unit then
		Call(st.container, 'SetUnit', unit)
		st.unit = unit
	end
	if st.enabled ~= true then
		Call(st.container, 'SetEnabled', true)
		st.enabled = true
	end
	local ctx = plate.env.ctx or P.Context
	for i = 1, st.used do
		local row = st.rowOf[i]
		if row and P.Conditions:WhenApplies(row.when, ctx) then
			st.tints[i]:Show()
		else
			st.tints[i]:Hide()
		end
	end
end

---Re-run Configure on every plate that waited for the game to allow aura changes.
function Presence:FlushPending()
	if IsRestricted() then
		return
	end
	for plate in pairs(presencePending) do
		presencePending[plate] = nil
		self:Configure(plate)
	end
end

---Configure every live plate (settings, role or place changed).
function Presence:ConfigureAll()
	local driver = P.Driver
	local bound = driver and driver.bound or EMPTY
	for plate in pairs(bound) do
		self:Configure(plate)
	end
	for plate in pairs(presence) do
		if not bound[plate] then
			self:Configure(plate)
		end
	end
end

---Tint state of a plate (tests and the inspector).
---@param plate Plates.Plate
---@return table|nil
function Presence:State(plate)
	return presence[plate]
end

P:On('STYLE_APPLIED', function(plate)
	if plate and not plate.isPreview then
		Presence:Configure(plate)
	end
end, Presence)
P:On('PLATE_ADDED', function(plate)
	if plate then
		Presence:Flip(plate)
	end
end, Presence)
P:On('PLATE_REMOVED', function(plate)
	if plate then
		Presence:Disable(plate)
	end
end, Presence)
P:On('STORE_CHANGED', function(reasons)
	if reasons and (reasons.colors or reasons.look or reasons.size) and next(presence) then
		Presence:ConfigureAll()
	end
end, Presence)
P:On('CONTEXT_CHANGED', function()
	if next(presence) then
		Presence:ConfigureAll()
	end
end, Presence)
P:On('RESTRICTION_CHANGED', function(isRestricted)
	if not isRestricted then
		Presence:FlushPending()
	end
end, Presence)
P:On('ENGINE_DISABLED', function()
	P.util.Wipe(presencePending)
	for plate in pairs(presence) do
		Presence:Disable(plate)
	end
end, Presence)
