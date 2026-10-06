local SUI, L = SUI, SUI.L

-- Painted strips for Lib's DataBar, one per look that has art. Each strip is a left end cap
-- (mirrored for the right end) and a middle that repeats across the bar, so it stays sharp at any
-- width. The pictures are drawn for a bar along the bottom of the screen; DataBar flips them for
-- a bar along the top.

---@class SUI.ThemeDataBars
local Art = {}
SUI.ThemeDataBars = Art

local ROOT = 'Interface\\AddOns\\SpartanUI\\Themes\\'

---@class SUI.ThemeDataBars.Strip
---@field id string
---@field theme string ThemeRegistry name the strip belongs to
---@field name string
---@field file string Path under Themes, without the -Cap/-Tile/-Card suffix
---@field capWidth number Cap file width in pixels (files are 64 tall)
---@field textColor number[]
---@field labelColor number[]
---@field highlight number[]

---@type SUI.ThemeDataBars.Strip[]
Art.list = {
	-- stylua: ignore start
	{ id = 'arcane', theme = 'Arcane', name = 'Arcane', file = 'Arcane\\Images\\DataBar-Blue', capWidth = 128, textColor = { 0.96, 0.95, 0.91 }, labelColor = { 0.663, 0.835, 0.969 }, highlight = { 0.569, 0.788, 0.961, 0.18 } },
	{ id = 'arcanered', theme = 'ArcaneRed', name = 'Arcane Red', file = 'Arcane\\Images\\DataBar-Red', capWidth = 128, textColor = { 0.96, 0.95, 0.91 }, labelColor = { 0.949, 0.722, 0.737 }, highlight = { 0.933, 0.643, 0.663, 0.18 } },
	{ id = 'classic', theme = 'Classic', name = 'Classic', file = 'Classic\\Images\\DataBar', capWidth = 128, textColor = { 0.96, 0.95, 0.91 }, labelColor = { 0.878, 0.804, 0.62 }, highlight = { 0.843, 0.749, 0.514, 0.18 } },
	{ id = 'digital', theme = 'Digital', name = 'Digital', file = 'Digital\\Images\\DataBar', capWidth = 128, textColor = { 0.96, 0.95, 0.91 }, labelColor = { 0.631, 0.835, 0.937 }, highlight = { 0.529, 0.788, 0.918, 0.18 } },
	{ id = 'fel', theme = 'Fel', name = 'Fel', file = 'Fel\\Images\\DataBar', capWidth = 128, textColor = { 0.96, 0.95, 0.91 }, labelColor = { 0.757, 0.89, 0.588 }, highlight = { 0.69, 0.859, 0.475, 0.18 } },
	{ id = 'tribal', theme = 'Tribal', name = 'Tribal', file = 'Tribal\\Images\\DataBar', capWidth = 128, textColor = { 0.96, 0.95, 0.91 }, labelColor = { 0.882, 0.8, 0.667 }, highlight = { 0.847, 0.741, 0.573, 0.18 } },
	{ id = 'war-alliance', theme = 'War', name = 'War (Alliance)', file = 'War\\Images\\DataBar-Alliance', capWidth = 128, textColor = { 0.96, 0.95, 0.91 }, labelColor = { 0.91, 0.824, 0.588 }, highlight = { 0.886, 0.773, 0.471, 0.18 } },
	{ id = 'war-horde', theme = 'War', name = 'War (Horde)', file = 'War\\Images\\DataBar-Horde', capWidth = 128, textColor = { 0.96, 0.95, 0.91 }, labelColor = { 0.906, 0.71, 0.69 }, highlight = { 0.878, 0.627, 0.604, 0.18 } },
	{ id = 'midnight', theme = 'Midnight', name = 'Midnight', file = 'Midnight\\Images\\DataBar', capWidth = 128, textColor = { 0.96, 0.95, 0.91 }, labelColor = { 0.827, 0.761, 0.945 }, highlight = { 0.776, 0.694, 0.929, 0.18 } },
	{ id = 'atlas', theme = 'Atlas', name = 'Voyager', file = 'Atlas\\Images\\DataBar', capWidth = 128, textColor = { 0.96, 0.95, 0.91 }, labelColor = { 0.831, 0.761, 0.6 }, highlight = { 0.784, 0.694, 0.486, 0.18 } },
	{ id = 'boughs', theme = 'Boughs', name = 'Grove', file = 'Boughs\\Images\\DataBar', capWidth = 128, textColor = { 0.96, 0.95, 0.91 }, labelColor = { 0.788, 0.851, 0.675 }, highlight = { 0.729, 0.808, 0.584, 0.18 } },
	{ id = 'meridian', theme = 'Meridian', name = 'Observatory', file = 'Meridian\\Images\\DataBar', capWidth = 128, textColor = { 0.96, 0.95, 0.91 }, labelColor = { 0.729, 0.867, 0.831 }, highlight = { 0.655, 0.831, 0.784, 0.18 } },
	-- stylua: ignore end
}

---@type table<string, SUI.ThemeDataBars.Strip>
Art.byId = {}
for _, strip in ipairs(Art.list) do
	Art.byId[strip.id] = strip
end

---The War strip for the player's faction
---@return string id
function Art.WarId()
	return UnitFactionGroup('player') == 'Horde' and 'war-horde' or 'war-alliance'
end

---DataBar `look.bar` block that draws a strip
---@param id string
---@return table|nil bar
function Art.Bar(id)
	local strip = Art.byId[id]
	if not strip then
		return nil
	end
	local base = ROOT .. strip.file
	return {
		background = { show = false },
		border = { show = false },
		-- Keep plugin text off the end ornaments (a cap is about 22 units tall on the default bar)
		padding = { left = math.floor(strip.capWidth / 64 * 18), right = math.floor(strip.capWidth / 64 * 18) },
		art = {
			texture = base .. '.png',
			strip = {
				cap = base .. '-Cap.png',
				tile = base .. '-Tile.png',
				capAspect = strip.capWidth / 64,
				tileAspect = 4,
			},
			facing = 'up',
			card = { texture = base .. '-Card.png', texCoord = { 0.15, 0.85, 0, 1 } },
		},
	}
end

---DataBar `look` block for a strip: its colors and its art
---@param id string
---@return table|nil look
function Art.Look(id)
	local strip = Art.byId[id]
	if not strip then
		return nil
	end
	return {
		font = { size = 11 },
		textColor = { strip.textColor[1], strip.textColor[2], strip.textColor[3], 1 },
		labelColor = { strip.labelColor[1], strip.labelColor[2], strip.labelColor[3], 1 },
		highlight = { strip.highlight[1], strip.highlight[2], strip.highlight[3], strip.highlight[4] or 0.2 },
		bar = Art.Bar(id),
	}
end

---A theme's `dataBars` block for a strip. `extra` adds fields such as `bars` (spots on screen).
---@param id string
---@param extra? table
---@return table dataBars
function Art.DataBars(id, extra)
	local block = { look = Art.Look(id) }
	for key, value in pairs(extra or {}) do
		block[key] = value
	end
	return block
end

---Caption for a strip's card in DataBar's setup and settings
---@param strip SUI.ThemeDataBars.Strip
---@return string
function Art.Description(strip)
	return string.format(L['The bar from the %s look. It stays the same when you change your SpartanUI look.'], strip.name)
end
