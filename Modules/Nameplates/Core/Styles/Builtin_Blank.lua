local _, ns = ...
local P = ns.Plates
local L = P.L

P.Styles.Registry:RegisterBuiltin({
	id = 'blank',
	name = L['Blank'],
	description = L['A health bar to start your own design.'],
	version = 1,
	schema = 1,
	order = 70,
	-- A starting point, not a look: Customize's "Start from a blank style" is its only home
	internal = true,
	plate = { sizes = { small = { 112, 8 }, medium = { 132, 10 }, large = { 156, 12 } } },
	regions = { click = { auto = true, pad = { 4, 4, 6, 2 } }, stack = { auto = true, pad = { 6, 6, 4, 4 } } },
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
			absorb = true,
			healAbsorb = true,
			absorbTexture = 'Nameplates Absorb Stripes',
		},
	},
	states = {},
	situations = {},
})
