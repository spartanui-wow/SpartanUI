local _, ns = ...
local P = ns.Plates
local L = P.L
local Options = P.Options

-- Auras page (3.2 #4). The lists only: size, count and side live on each row's part (Customize).
-- Sections: My debuffs on enemies, Enemy buffs I can remove, Crowd control, and Tank debuffs
-- where the client has them (every client but Retail). Each section has an "Always show" and a
-- "Never show" SpellList (entries Only mine / Anyone), written whole to
-- profile.auras[row].always / .never, which the aura parts read (P.AuraRows, P.AuraScan).
--
-- Enemy buffs on clients with secret values: the game skips spell lists for buffs on enemies, so
-- that section says "Not available for enemy buffs on this version of WoW" instead of lists.
--
-- Locked while the game restricts changes (Options.Locked: combat, or the game hiding auras in
-- restricted instances): every control here is disabled with a visible reason and unlocks when
-- the lock lifts. Nothing is queued silently.
--
-- Per-specialization lists (open question 14) have no screen. The data shape is reserved:
-- profile.auras[row].bySpec[specID] = { always = {...}, never = {...} }. Reading and writing a list
-- go through AurasPage.ListPath, so adding it later changes one function.

---@class Plates.AurasPage
local AurasPage = {}
Options.AurasPage = AurasPage

local UNAVAILABLE = L['Not available for enemy buffs on this version of WoW']

---Section definitions in page order. `who` is the default for new entries in each list.
---@type table[]
AurasPage.SECTIONS = {
	{
		row = 'myDebuffs',
		name = L['My debuffs on enemies'],
		note = L['Debuffs you put on enemies. Always show adds spells to the row. Never show hides them.'],
		who = { always = 'mine', never = 'any' },
	},
	{
		row = 'removable',
		name = L['Enemy buffs I can remove'],
		note = L['Buffs on enemies that you can steal or dispel.'],
		who = { always = 'any', never = 'any' },
	},
	{
		row = 'crowdControl',
		name = L['Crowd control'],
		note = L['Stuns, fears and other effects that take control away from an enemy.'],
		who = { always = 'any', never = 'any' },
	},
	{
		row = 'tankDebuffs',
		name = L['Tank debuffs'],
		note = L['Debuffs from other players that help tanks, such as armor and attack speed debuffs.'],
		who = { always = 'any', never = 'any' },
	},
}

----------------------------------------------------------------------------------------------------
-- Lists in the store
----------------------------------------------------------------------------------------------------

---Where a row's list lives. One place, so lists per specialization can be added later.
---@param row string
---@param which string 'always' | 'never'
---@param specID? integer Reserved: not used by any screen yet, and not read by the aura parts
---@return string[] path
function AurasPage.ListPath(row, which, specID)
	if specID then
		return { 'auras', row, 'bySpec', specID, which }
	end
	return { 'auras', row, which }
end

---A stored list as { [spellID] = 'mine'|'any' }. The aura parts also accept a plain array of ids.
---@param raw any
---@return table<integer, string>
local function Normalize(raw)
	local out = {}
	if type(raw) ~= 'table' then
		return out
	end
	for key, value in pairs(raw) do
		if type(value) == 'number' then
			out[value] = 'any'
		elseif type(key) == 'number' and value ~= false and value ~= nil then
			out[key] = value == 'mine' and 'mine' or 'any'
		end
	end
	return out
end

---@param row string
---@param which string 'always' | 'never'
---@return table<integer, string>
function AurasPage.ReadList(row, which)
	return Normalize(P.Store:Get(AurasPage.ListPath(row, which)))
end

---Write a list whole. An empty list removes the key, so the profile stays small.
---@param row string
---@param which string
---@param list table<integer, string>
function AurasPage.WriteList(row, which, list)
	if Options.Locked() or AurasPage.Unavailable(row) then
		Options:RequestRefresh(false)
		return false
	end
	local clean = Normalize(list)
	P.Store:Set(AurasPage.ListPath(row, which), next(clean) ~= nil and clean or nil)
end

---@return boolean
function AurasPage.HasLists()
	local auras = P.Store:Get('auras')
	if type(auras) ~= 'table' then
		return false
	end
	for _, row in pairs(auras) do
		if type(row) == 'table' and (row.always ~= nil or row.never ~= nil) then
			return true
		end
	end
	return false
end

---Forget every spell list (the rows' other settings stay).
function AurasPage.ClearLists()
	if Options.Locked() then
		Options:RequestRefresh(false)
		return false
	end
	local Store = P.Store
	Store:Batch(function()
		for _, section in ipairs(AurasPage.SECTIONS) do
			Store:Set(AurasPage.ListPath(section.row, 'always'), nil)
			Store:Set(AurasPage.ListPath(section.row, 'never'), nil)
		end
	end)
end

----------------------------------------------------------------------------------------------------
-- What this client can do
----------------------------------------------------------------------------------------------------

---Why a section has no lists here, or nil when it does.
---@param row string
---@return string|nil
function AurasPage.Unavailable(row)
	if row == 'removable' and P.Caps:Get('secrets') then
		return UNAVAILABLE
	end
	return nil
end

---False where the client has no tank debuffs from other players (Retail).
---@param row string
---@return boolean
function AurasPage.SectionShown(row)
	if row == 'tankDebuffs' then
		return P.AuraRows.Limit('tankDebuffs') == nil
	end
	return true
end

---Spell ids the search offers first, by section.
local function Curated(row)
	local data = P.Data or {}
	if row == 'crowdControl' then
		return data.CrowdControl or {}
	elseif row == 'tankDebuffs' or row == 'myDebuffs' then
		return AurasPage.SectionShown('tankDebuffs') and data.TankDebuffs or {}
	end
	return {}
end

local function ShortLockedReason()
	return Options.LOCKED_REASON
end

----------------------------------------------------------------------------------------------------
-- Page
----------------------------------------------------------------------------------------------------

local function ListOption(section, which, order)
	local arg = {
		list = function()
			return AurasPage.ReadList(section.row, which)
		end,
		onChange = function(list)
			AurasPage.WriteList(section.row, which, list)
		end,
		defaultWho = section.who[which],
		curated = function()
			return Curated(section.row)
		end,
		unavailable = function()
			return AurasPage.Unavailable(section.row)
		end,
		lockedReason = ShortLockedReason,
	}
	if which == 'never' then
		-- The search hint under the first list is enough
		arg.hint = false
	end
	return {
		type = 'select',
		dialogControl = P.Widgets:TypeName('SpellList'),
		name = which == 'always' and L['Always show'] or L['Never show'],
		order = order,
		width = 'full',
		values = {},
		get = function()
			return nil
		end,
		set = function() end,
		disabled = Options.Locked,
		arg = arg,
	}
end

local function SectionGroup(section, order)
	local row = section.row
	local args = {
		note = { type = 'description', order = 1, name = section.note },
	}
	-- A client that cannot take spell lists for this row shows the reason once, not two empty lists
	args.unavailable = {
		type = 'description',
		order = 2,
		fontSize = 'medium',
		hidden = function()
			return AurasPage.Unavailable(row) == nil
		end,
		name = function()
			return AurasPage.Unavailable(row) or ''
		end,
	}
	if row == 'tankDebuffs' then
		args.on = {
			type = 'toggle',
			order = 3,
			width = 'full',
			name = L['Show tank debuffs'],
			desc = L['Shows these debuffs on enemies, whoever put them there.'],
			get = function()
				return P.Store:Get({ 'auras', 'tankDebuffs', 'on' }) ~= false
			end,
			set = function(_, value)
				if Options.Locked() then
					Options:RequestRefresh(false)
					return
				end
				-- On is the default, so only Off is stored
				if value then
					P.Store:Set({ 'auras', 'tankDebuffs', 'on' }, nil)
				else
					P.Store:Set({ 'auras', 'tankDebuffs', 'on' }, false)
				end
			end,
			disabled = Options.Locked,
		}
	end
	if row == 'removable' then
		args.important = {
			type = 'toggle',
			order = 3,
			width = 'full',
			name = L['Also show important enemy buffs'],
			desc = L['Adds buffs the game marks as important, even when you cannot remove them.'],
			hidden = function()
				return P.AuraRows.Limit('important') ~= nil or not P.Caps:Get('important')
			end,
			get = function()
				return P.Store:Get({ 'auras', 'removable', 'important' }) == true
			end,
			set = function(_, value)
				if Options.Locked() then
					Options:RequestRefresh(false)
					return
				end
				P.Store:Set({ 'auras', 'removable', 'important' }, value and true or nil)
			end,
			disabled = Options.Locked,
		}
	end
	local always = ListOption(section, 'always', 10)
	local never = ListOption(section, 'never', 11)
	args.always = always
	args.never = never
	if row == 'removable' then
		-- Lists are hidden entirely where the game skips them
		always.hidden = function()
			return AurasPage.Unavailable(row) ~= nil
		end
		never.hidden = always.hidden
	end
	return {
		type = 'group',
		inline = true,
		order = order,
		name = section.name,
		hidden = function()
			return not AurasPage.SectionShown(row)
		end,
		args = args,
	}
end

Options:AddPage('auras', 4, function()
	local args = {
		locked = {
			type = 'description',
			order = 1,
			fontSize = 'medium',
			name = Options.LOCKED_REASON,
			hidden = function()
				return not Options.Locked()
			end,
		},
		rowsLimit = {
			type = 'description',
			order = 2,
			fontSize = 'medium',
			name = function()
				return P.AuraRows.Limit('rows') or ''
			end,
			hidden = function()
				return P.AuraRows.Limit('rows') == nil
			end,
		},
		intro = {
			type = 'description',
			order = 3,
			name = L['Choose spells to always show or never show in each row. You change how big a row is, and where it sits, in Customize.'],
		},
		clear = {
			type = 'execute',
			order = 50,
			advanced = true,
			name = L['Clear all my spell lists'],
			desc = L['Removes every spell you added to the Always show and Never show lists.'],
			confirm = true,
			confirmText = L['Remove every spell from these lists?'],
			hidden = function()
				return not AurasPage.HasLists()
			end,
			disabled = Options.Locked,
			func = function()
				AurasPage.ClearLists()
			end,
		},
	}
	for index, section in ipairs(AurasPage.SECTIONS) do
		args[section.row] = SectionGroup(section, 10 + index)
	end
	return {
		type = 'group',
		name = L['Auras'],
		args = args,
	}
end)
