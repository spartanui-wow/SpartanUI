local _, ns = ...
local P = ns.Plates

-- Aura rows on 12.1 aura containers (kind 'auras', Retail and Forever, live plates only; 6.6).
-- Owner: Phase 3.
--
-- One container per positioned row (up to 3 per plate), pooled by Engine/Pool.lua:
--   CreateFrame('AuraContainer', nil, holder, 'CustomAuraContainerTemplate')
-- We anchor and size each container ourselves (the flow layout is internal only); frames we hang
-- from a container sit in a DisableUntrustedLayoutScriptsTemplate holder.
-- Groups are created once with AddAuraGroup and then repointed: SetAuraGroupFilterString,
-- SetAuraGroupCandidateFilters, SetAuraGroupSortMethod, SetAuraGroupLayout. A group that is off
-- gets SetAuraGroupMaxFrameCount(key, 0). Never use 'HELPFUL|HARMFUL' as a never-match.
-- Spell lists (includeSpellIDs) only apply to debuffs on enemies and buffs on friends; groups
-- that cannot apply to this unit are flipped off per add with SetAuraGroupMaxFrameCount, never by
-- rewriting filter strings. Rows that are off stay bound to 'none'.
-- On every add (combat included): SetUnit(unit), SetEnabled(true), max frame count flips.
-- Filter, layout and candidate changes from settings run in Configure, which the plate only calls
-- while P.Secret.IsRestricted() is false; settings are locked meanwhile (3.2).
-- Never key a table by auraInstanceID. Never name anything 'Auras' (oUF meta element name).
-- Previews never use containers (they need a real unit): AurasScan draws sample icons there.

---@class Plates.AuraRowGroup
---@field key string Group key inside the container
---@field filter string Aura filter string (normalized)
---@field candidates? table Candidate filters (keys checked against Schema.CANDIDATE_KEYS)
---@field spellList? 'debuffOnEnemy'|'buffOnFriend' Groups that only work for one reaction
---@field clients? table<string, boolean> Only on these client names (Caps:Client())

---@class Plates.AuraRow
---@field id string
---@field label string
---@field groups Plates.AuraRowGroup[] Container groups (Retail and Forever)
---@field scan fun(aura: table, ctx: table): boolean Lua scan predicate (Classic family, plain data)
---@field scanFilter string Filter passed to C_UnitAuras.GetAuraDataByIndex on the scan path

---@class Plates.AuraRows
local AuraRows = {}
P.AuraRows = AuraRows

---Order: polarity first, other tokens sorted, each negation right after its bare token, so groups
---share engine scans. On 12.1 NOT_CANCELABLE is written !CANCELABLE.
---@param filter string
---@return string
function AuraRows.NormalizeFilter(filter)
	local polarity
	local others = {}
	for token in string.gmatch(filter or '', '[^|]+') do
		if token == 'NOT_CANCELABLE' then
			token = '!CANCELABLE'
		end
		if token == 'HELPFUL' or token == 'HARMFUL' then
			polarity = polarity or token
		else
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

local function Dispellable()
	local filters = AuraUtil and AuraUtil.AuraFilters
	return (filters and filters.Dispellable) or 'RAID_PLAYER_DISPELLABLE'
end

---The launch rows (4). Data owners may add groups; never add a candidate key outside the list.
AuraRows.ROWS = {
	myDebuffs = {
		id = 'myDebuffs',
		label = P.L['My debuffs'],
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
		label = P.L['Enemy buffs I can remove'],
		groups = {
			{ key = 'removable', filter = 'HELPFUL|' .. Dispellable() },
		},
		scanFilter = 'HELPFUL',
		scan = function(aura)
			return aura.isStealable == true or aura.dispelName == 'Magic'
		end,
	},
	crowdControl = {
		id = 'crowdControl',
		label = P.L['Crowd control'],
		groups = {
			{ key = 'cc', filter = 'HARMFUL|CROWD_CONTROL' },
		},
		scanFilter = 'HARMFUL|CROWD_CONTROL',
		scan = function(aura, ctx)
			return ctx.ccFromToken == true or (P.Data.CrowdControl[aura.spellId] == true)
		end,
	},
}

P.Parts:Register({
	id = 'aurasContainer',
	kinds = { 'auras' },
	priority = 10,
	match = function(_, plate)
		return not plate.isPreview and P.Caps:Get('containers')
	end,
	reasons = { auras = true },
	Create = function(plate)
		local holder = CreateFrame('Frame', nil, plate.art)
		return { frame = holder }
	end,
	Layout = function(widget, spec, ctx)
		local w, h = P.Styles.Merge.PartSize(spec, ctx.width, ctx.height)
		widget.frame:SetSize(w, h)
		ctx:Anchor(widget.frame, spec.anchor)
	end,
	Configure = function() end,
	Update = function() end,
	Reset = function() end,
})
