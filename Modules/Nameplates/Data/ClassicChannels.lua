local _, ns = ...
local P = ns.Plates

-- Era channel durations: spell id -> channel length in seconds, for the plain-math cast bar path
-- when a client reports a channel without usable times. Read only on clients without Retail data
-- rules; the table stays empty elsewhere.
--
-- Data owner: verified values for Classic Era (and TBC Anniversary if needed).

P.Data = P.Data or {}

---@type table<integer, number>
P.Data.ClassicChannels = {}
