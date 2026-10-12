local _, ns = ...
local P = ns.Plates

-- Old art keys mapped to new ones (5.1). Empty at launch on purpose: share strings carry LSM keys
-- for years, and art gets renamed. Add a line here whenever a key changes; never reuse an old key
-- for different art.

---@class Plates.Data
P.Data = P.Data or {}

---@class Plates.ArtAliases
local ArtAliases = { map = {} }
P.Data.ArtAliases = ArtAliases

---The current key for a possibly renamed art key (follows chains, stops on loops).
---@param key string
---@return string
function ArtAliases:Resolve(key)
	local seen = {}
	while self.map[key] and not seen[key] do
		seen[key] = true
		key = self.map[key]
	end
	return key
end
