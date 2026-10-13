local _, ns = ...
local P = ns.Plates

-- Role defaults (3.1, 3.5): which threat palette, where threat shows, and healer emphasis.
-- Roles are not styles. The player's role comes from profile.role ('auto' follows the spec,
-- read into P.Context.role by the engine). Everything here is pure.

---@class Plates.Roles
local Roles = {}
P.Roles = Roles

Roles.LIST = { 'tank', 'damage', 'healer' }

---Defaults per role: color scheme, where threat shows, and plate emphasis.
Roles.DEFAULTS = {
	tank = { scheme = 'threat', threatOn = { bar = true }, emphasis = 'normal' },
	damage = { scheme = 'mobType', threatOn = { border = true }, emphasis = 'normal' },
	healer = { scheme = 'mobType', threatOn = { glow = true }, emphasis = 'healer' },
}

---Threat colors by state. Tanks see "safe" when they hold the mob; damage and healers see "safe"
---when they do not. The palette itself does not flip; the state does (Roles.ThreatState).
Roles.PALETTE = {
	safe = { 0.2, 0.75, 0.3, 1 },
	losing = { 1, 0.6, 0.1, 1 },
	lost = { 0.9, 0.15, 0.15, 1 },
	offTank = { 0.35, 0.55, 1, 1 },
	pet = { 0.6, 0.45, 0.85, 1 },
	solo = { 0.85, 0.2, 0.2, 1 },
}

---Same states, colors that stay apart for the common kinds of color blindness.
Roles.PALETTE_COLORBLIND = {
	safe = { 0.0, 0.45, 0.7, 1 },
	losing = { 0.9, 0.6, 0.0, 1 },
	lost = { 0.8, 0.4, 0.0, 1 },
	offTank = { 0.35, 0.7, 0.9, 1 },
	pet = { 0.8, 0.6, 0.7, 1 },
	solo = { 0.8, 0.4, 0.0, 1 },
}

Roles.STATES = { 'safe', 'losing', 'lost', 'offTank', 'pet', 'solo' }

---The role to use.
---@param setting string|nil 'auto' | 'tank' | 'damage' | 'healer'
---@param specRole string|nil Role from the spec ('TANK'|'DAMAGER'|'HEALER' or lower case)
---@return 'tank'|'damage'|'healer'
function Roles.Resolve(setting, specRole)
	if setting == 'tank' or setting == 'damage' or setting == 'healer' then
		return setting
	end
	local role = specRole and string.lower(specRole) or nil
	if role == 'tank' then
		return 'tank'
	elseif role == 'healer' then
		return 'healer'
	end
	return 'damage'
end

---The color scheme to use when profile.scheme is 'auto'.
---@param role string
---@return string
function Roles.Scheme(role)
	local defaults = Roles.DEFAULTS[role] or Roles.DEFAULTS.damage
	return defaults.scheme
end

---Where threat shows: profile.threat.show when set, else the role default.
---@param role string
---@param show table|nil { bar = true, border = true, name = true, glow = true, size = true }
---@return table<string, boolean>
function Roles.ThreatOn(role, show)
	if type(show) == 'table' and next(show) then
		return show
	end
	local defaults = Roles.DEFAULTS[role] or Roles.DEFAULTS.damage
	return defaults.threatOn
end

---Threat state from a plain UnitThreatSituation status (0-3, nil when not on the threat list).
---@param role string
---@param status integer|nil
---@param inGroup boolean
---@return string|nil state 'safe'|'losing'|'lost'|'solo', or nil for no threat color
function Roles.ThreatState(role, status, inGroup)
	if status == nil then
		return nil
	end
	if not inGroup then
		return 'solo'
	end
	if role == 'tank' then
		if status == 3 then
			return 'safe'
		elseif status == 2 then
			return 'losing'
		end
		return 'lost'
	end
	if status == 0 then
		return 'safe'
	elseif status == 1 then
		return 'losing'
	end
	return 'lost'
end

---Threat colors for a profile: the palette (or color-blind palette) with the player's own colors
---from profile.threat.colors on top.
---@param colorBlind boolean|nil
---@param custom table|nil state -> { r, g, b, a }
---@return table<string, number[]>
function Roles.Palette(colorBlind, custom)
	local base = colorBlind and Roles.PALETTE_COLORBLIND or Roles.PALETTE
	local out = {}
	for state, color in pairs(base) do
		out[state] = (custom and custom[state]) or color
	end
	return out
end

---Healer emphasis: enemy plates are small and soft until they matter (target, casting).
---@param role string
---@return boolean
function Roles.HealerEmphasis(role)
	local defaults = Roles.DEFAULTS[role]
	return defaults ~= nil and defaults.emphasis == 'healer'
end

----------------------------------------------------------------------------------------------------
-- Healer emphasis on plates (3.1). Healers watch their group, not the enemies, so enemy plates stay
-- small and soft until they matter: the target, the focus, the one under the mouse and any enemy
-- casting come back to full size and alpha. Healers also get a stronger removable buffs row
-- (Roles.StyleFor). The player turns it off with profile.behavior.healerEmphasis = false.
-- Plate:ApplyEmphasis asks Roles.Quiet on every state change; sizes stay whole pixels.
----------------------------------------------------------------------------------------------------

---How quiet plates look: width and height as a share of the style's size, and their alpha.
Roles.QUIET = { width = 0.8, height = 0.75, alpha = 0.55 }

---Kinds of plates healer emphasis quiets. Enemy players keep their size: in PvP a healer must see them.
Roles.QUIET_KINDS = { enemyNPC = true, minor = true }

---Kinds that get the stronger removable buffs row.
Roles.REMOVABLE_KINDS = { enemyNPC = true, enemyPlayer = true }

---The removable buffs row healers get when the style has none, and how much an existing one grows.
Roles.REMOVABLE_PART = { order = 56, kind = 'auras', row = 'removable', size = 22, max = 3, grow = 'LEFT' }
Roles.REMOVABLE_BOOST = { size = 4, max = 1 }

-- The setting, read from the profile when it changes (never on every plate update)
Roles.healerOff = false

local function ReadSetting()
	local behavior = P.Store and P.Store:Get('behavior')
	Roles.healerOff = type(behavior) == 'table' and behavior.healerEmphasis == false
end

if P.On then
	P:On('INITIALIZED', ReadSetting, Roles)
	P:On('PROFILE_CHANGED', ReadSetting, Roles)
	P:On('STORE_CHANGED', ReadSetting, Roles)
end

---True when healer emphasis is on for this role (the setting and the role).
---@param role string|nil
---@return boolean
function Roles.QuietOn(role)
	return not Roles.healerOff and Roles.HealerEmphasis(role)
end

---Whether a plate is quiet right now (plain): healer emphasis is on, the plate is an enemy NPC or
---a minor enemy, and it is not the target, focus, under the mouse or casting. Previews follow it
---only where they show fades (plate.previewFade).
---@param plate Plates.Plate
---@return boolean
function Roles.Quiet(plate)
	local ctx = plate.env and plate.env.ctx
	if not ctx or not Roles.QuietOn(ctx.role) then
		return false
	end
	if plate.isPreview and not plate.previewFade then
		return false
	end
	local kind = plate.situation or (plate.style and plate.style.situation)
	if not Roles.QUIET_KINDS[kind] then
		return false
	end
	local states = plate.states
	return not (states.target or states.focus or states.mouseover or states.casting)
end

---The quiet size in whole pixels.
---@param width number
---@param height number
---@return integer width
---@return integer height
function Roles.QuietSize(width, height)
	return math.max(1, math.floor(width * Roles.QUIET.width + 0.5)), math.max(1, math.floor(height * Roles.QUIET.height + 0.5))
end

-- Healer versions of resolved styles, one per resolved style (weak, rebuilt with the style)
local healerStyles = setmetatable({}, { __mode = 'k' })

local function HealerStyle(resolved)
	local cached = healerStyles[resolved]
	if cached ~= nil then
		return cached or resolved
	end
	local found
	for id, spec in pairs(resolved.parts or {}) do
		if spec.kind == 'auras' and spec.row == 'removable' then
			found = id
		end
	end
	-- The player hid the style's own removable row: leave it hidden
	if not found and resolved.hidden and resolved.hidden.removable then
		healerStyles[resolved] = false
		return resolved
	end
	local derived = {}
	for key, value in pairs(resolved) do
		derived[key] = value
	end
	local parts = {}
	for id, spec in pairs(resolved.parts or {}) do
		parts[id] = spec
	end
	if found then
		local spec = P.util.Copy(parts[found])
		spec.size = math.min(64, (spec.size or 20) + Roles.REMOVABLE_BOOST.size)
		spec.max = math.min(40, (spec.max or 2) + Roles.REMOVABLE_BOOST.max)
		parts[found] = spec
		derived.order = resolved.order
	else
		local merge = P.Styles and P.Styles.Merge
		local spec = P.util.Copy(Roles.REMOVABLE_PART)
		if merge and merge.PART_DEFAULTS and merge.PART_DEFAULTS.auras then
			spec = merge.Deep(merge.PART_DEFAULTS.auras, spec)
		end
		if type(spec.font) == 'table' and resolved.tokens and resolved.tokens.font then
			spec.font.face = resolved.tokens.font
		end
		spec.anchor = { 'RIGHT', parts.health and 'health' or 'plate', 'LEFT', -4, 0 }
		parts.healerRemovable = spec
		local order = {}
		for i, id in ipairs(resolved.order or {}) do
			order[i] = id
		end
		order[#order + 1] = 'healerRemovable'
		derived.order = order
	end
	derived.parts = parts
	derived.roleBase = resolved
	derived.key = tostring(resolved.key) .. '|healer'
	healerStyles[resolved] = derived
	return derived
end

---The style a plate draws for its role: the healer version for enemy plates while healer emphasis
---is on (live plates only; previews and the designer show the style as it is), else the style.
---@param resolved Plates.ResolvedStyle
---@param plate Plates.Plate
---@return Plates.ResolvedStyle
function Roles.StyleFor(resolved, plate)
	if plate.isPreview or not Roles.REMOVABLE_KINDS[resolved.situation] then
		return resolved
	end
	local ctx = plate.env and plate.env.ctx
	if not ctx or not Roles.QuietOn(ctx.role) then
		return resolved
	end
	return HealerStyle(resolved)
end
