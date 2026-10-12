local _, ns = ...
local P = ns.Plates

-- Classic family backstop for the crowd control row (4, 6.6): CROWD_CONTROL is in Era's filter
-- table and is passed on Classic, but a spell list catches what the token misses (S0 confirms).
-- Only read by the Lua scan path (Engine/Parts/AurasScan.lua); containers use the token.
--
-- Data owner: spell ids per client, verified, as { [spellID] = true }.

P.Data = P.Data or {}

---@type table<integer, boolean>
P.Data.CrowdControl = {}
