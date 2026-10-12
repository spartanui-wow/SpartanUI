local _, ns = ...
local P = ns.Plates

-- Totem plates (Phase 9). Shaman totem data by spell id for the Classic family, where identity is
-- readable; on Retail and Forever only the player's own totems are known (UnitIsMinion).
--
-- Data owner: { [spellID] = { name = 'Searing Totem', icon = fileID|path, rank = n } }.

P.Data = P.Data or {}

---@type table<integer, table>
P.Data.Totems = {}
