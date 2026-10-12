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
