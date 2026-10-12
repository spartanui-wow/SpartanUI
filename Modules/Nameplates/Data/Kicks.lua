local _, ns = ...
local P = ns.Plates

-- Interrupt spells per class (and per rank on the Classic family), used for the interrupt-ready
-- tint (4) and, from Phase 5, the kick mark. Pet interrupts are checked first (6.4 "pet spellbook
-- first"). The engine picks the first spell the player knows and stores it in P.Context.kickSpell.
--
-- Data owner: fill byClass and pet with spell ids verified against each client's data (one entry
-- per rank on the Classic family, highest rank first). Rules.retail separates rank tables when a
-- spell id differs by client. Never guess an id.

P.Data = P.Data or {}

---@class Plates.Kicks
---@field byClass table<string, integer[]> Class token -> spell ids, preferred first
---@field pet integer[] Pet interrupt spell ids, preferred first
local Kicks = { byClass = {}, pet = {} }
P.Data.Kicks = Kicks

---First interrupt the player can use (pure; `known` answers whether a spell id is usable).
---@param classToken string|nil
---@param known fun(spellID: integer, isPet: boolean): boolean
---@return integer|nil spellID
---@return boolean isPet
function Kicks:Pick(classToken, known)
	for _, spell in ipairs(self.pet) do
		if known(spell, true) then
			return spell, true
		end
	end
	for _, spell in ipairs(classToken and self.byClass[classToken] or {}) do
		if known(spell, false) then
			return spell, false
		end
	end
	return nil, false
end
