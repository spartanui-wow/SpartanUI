local _, ns = ...
local P = ns.Plates
local L = P.L

-- Mini (internal): a tiny bar for minor enemies, pets and totems. Normal mobs never use it.
-- The engine's own "simplified" shrink is turned off for plates drawn with it (6.5 step 3).
-- A totem the game lets addons know about shows its own icon instead of the bar: the health part
-- fades its content (hideOnTotem) and the totem icon part shows only on known totems.

P.Styles.Registry:RegisterBuiltin({
	id = 'mini',
	name = L['Mini'],
	description = L['A tiny bar for minor enemies, pets and totems.'],
	version = 1,
	schema = 1,
	order = 910,
	internal = true,
	plate = { sizes = { small = { 48, 4 }, medium = { 60, 5 }, large = { 72, 6 } } },
	regions = { click = { auto = true, pad = { 4, 4, 4, 4 } }, stack = { auto = true, pad = { 4, 4, 2, 2 } } },
	tokens = { accent = '$host', font = '$host', bar = 'Nameplates Flat', ink = { 0, 0, 0, 1 }, shade = { 0, 0, 0, 0.6 } },
	parts = {
		health = {
			order = 10,
			kind = 'bar',
			source = 'health',
			anchor = { 'CENTER', 'plate', 'CENTER', 0, 0 },
			fill = 'plate',
			texture = '$bar',
			border = { kind = 'pixel', size = 1, color = '$ink' },
			bg = '$shade',
			colors = 'health',
			borderColors = 'border',
			hideOnTotem = true,
		},
		totem = { order = 15, kind = 'icon', source = 'totem', anchor = { 'CENTER', 'health', 'CENTER', 0, 0 }, size = 14 },
		cast = {
			order = 20,
			kind = 'cast',
			anchor = { 'TOP', 'health', 'BOTTOM', 0, -1 },
			height = 3,
			icon = 'none',
			nameText = false,
			timeText = false,
			target = false,
			shield = true,
			important = true,
			aimedAtMe = false,
		},
		marker = { order = 30, kind = 'icon', source = 'raidMarker', anchor = { 'RIGHT', 'health', 'LEFT', -2, 0 }, size = 10 },
		arrows = { order = 40, kind = 'highlight', state = 'target', art = 'arrows' },
	},
	states = { target = { grow = { 6, 1 } }, notTarget = { alpha = 0.6 }, casting = { alpha = 1 } },
})
