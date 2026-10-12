local _, ns = ...
local P = ns.Plates

-- Tank debuffs from anyone (4, Phase 3): Sunder Armor, Faerie Fire, Demoralizing Shout and
-- Demoralizing Roar, every rank. Classic family and Forever only; on Forever they feed a second
-- group in the My debuffs container through includeSpellIDs, on the Classic family the Lua scan.
--
-- Data owner: { [spellID] = 'sunder' | 'faerieFire' | 'demoShout' | 'demoRoar' }, verified per client.

P.Data = P.Data or {}

---@type table<integer, string>
P.Data.TankDebuffs = {}

---Spell ids as a list, for includeSpellIDs.
---@return integer[]
function P.Data.TankDebuffIDs()
	local list = {}
	for id in pairs(P.Data.TankDebuffs) do
		list[#list + 1] = id
	end
	table.sort(list)
	return list
end
