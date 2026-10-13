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
	-- Called on every layout; a key that was never renamed makes no table
	if not self.map[key] then
		return key
	end
	local seen = {}
	while self.map[key] and not seen[key] do
		seen[key] = true
		key = self.map[key]
	end
	return key
end

---LibSharedMedia types the art set registers its pictures under (5.5); other addons may add more
---pictures there. A style's art key is looked up with ctx:Texture(key, ArtAliases.MEDIA[kind]).
ArtAliases.MEDIA = { highlight = 'nameplatehighlight', glow = 'nameplateglow', art = 'nameplateart' }

---Art slots the art set fills (Phase 4a), by part kind and key. Until a slot has a picture (an
---LSM entry under MEDIA[kind] with the slot key, or `file` here, relative to the host's media
---path), the parts draw a stand-in built from plain textures and lines, so every key always draws
---something. Pictures are white on alpha and tinted by the part.
--- draw 'pair'   one picture left of the plate, mirrored on the right; `aspect` is its width per
---               height; `fit` 'arrow' sizes it from the plate height, 'plate' stretches it to it
--- draw 'sliced' one picture around the plate, cut with nine-slice `margins` { l, t, r, b }
--- draw 'below'  a strip under the plate, `height` pixels tall
--- draw 'glow'   drawn by P.GlowLib with the named glow `look`
ArtAliases.SLOTS = {
	highlight = {
		arrows = { draw = 'pair', aspect = 0.5, fit = 'arrow' },
		doubleArrows = { draw = 'pair', aspect = 0.95, fit = 'arrow' },
		brackets = { draw = 'sliced', margins = { 8, 8, 8, 8 } },
		glow = { draw = 'glow', look = 'soft' },
		underline = { draw = 'below', height = 3 },
		sideBars = { draw = 'pair', aspect = 0.2, fit = 'plate' },
	},
	glow = {
		soft = { draw = 'sliced', margins = { 16, 16, 16, 16 } },
		important = { draw = 'sliced', margins = { 16, 16, 16, 16 } },
		purge = { draw = 'sliced', margins = { 16, 16, 16, 16 } },
		pandemic = { draw = 'sliced', margins = { 8, 8, 8, 8 } },
	},
}

---The slot for an art key, or nil (art from another addon, drawn stretched).
---@param kind string 'highlight' | 'glow'
---@param key string|nil
---@return table|nil
function ArtAliases:Slot(kind, key)
	local slots = self.SLOTS[kind]
	if not slots or type(key) ~= 'string' then
		return nil
	end
	return slots[self:Resolve(key)]
end
