local _, ns = ...
local P = ns.Plates
local L = P.L

-- Clean: flat bar, 1 px border, name above, cast below. The fallback when no host look exists
-- and the migration target. Built-ins are written in the import format: the headless test runs
-- each one through Schema:ValidateStyle, so nothing here may fail an import check.

P.Styles.Registry:RegisterBuiltin({
	id = 'clean',
	name = L['Clean'],
	description = L['Flat bar with a thin border. Name above, cast bar below.'],
	version = 1,
	schema = 1,
	order = 10,
	plate = { sizes = { small = { 112, 8 }, medium = { 132, 10 }, large = { 156, 12 } } }, -- whole pixels, never SetScale
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
		},
		name = {
			order = 20,
			kind = 'text',
			source = 'name',
			anchor = { 'BOTTOMLEFT', 'health', 'TOPLEFT', 0, 2 },
			justify = 'LEFT',
			colors = 'name',
			font = { face = '$font', size = 10, flags = 'OUTLINE' },
		},
		hp = { order = 30, kind = 'text', source = 'healthPercent', anchor = { 'RIGHT', 'health', 'RIGHT', -2, 0 }, justify = 'RIGHT', font = { size = 9 } },
		forces = { order = 35, kind = 'text', source = 'forces', anchor = { 'LEFT', 'health', 'LEFT', 14, 0 }, justify = 'LEFT', font = { size = 9 } },
		elite = { order = 36, kind = 'icon', source = 'classification', anchor = { 'LEFT', 'health', 'LEFT', 2, 0 }, size = 10 },
		cast = { order = 40, kind = 'cast', anchor = { 'TOP', 'health', 'BOTTOM', 0, -2 }, height = 8, icon = 'left', target = true, shield = true, important = true, aimedAtMe = true },
		power = { order = 45, kind = 'classPower', state = 'target', anchor = { 'TOP', 'cast', 'BOTTOM', 0, -3 }, size = 5, spacing = 2 },
		mine = { order = 50, kind = 'auras', row = 'myDebuffs', anchor = { 'BOTTOMLEFT', 'name', 'TOPLEFT', 0, 2 }, size = 20, max = 6, grow = 'RIGHT' },
		cc = { order = 60, kind = 'auras', row = 'crowdControl', anchor = { 'LEFT', 'health', 'RIGHT', 4, 0 }, size = 24, max = 2 },
		marker = { order = 70, kind = 'icon', source = 'raidMarker', anchor = { 'RIGHT', 'health', 'LEFT', -4, 0 }, size = 16 },
		quest = { order = 75, kind = 'icon', source = 'quest', anchor = { 'BOTTOMRIGHT', 'health', 'TOPRIGHT', 0, 2 }, size = 14 },
		arrows = { order = 80, kind = 'highlight', state = 'target', art = 'arrows' },
		hover = { order = 79, kind = 'highlight', state = 'mouseover', art = 'glow', color = { 1, 1, 1, 1 } },
		threat = { order = 90, kind = 'glow', source = 'threat' },
	},
	states = {
		target = { grow = { 14, 2 } }, -- about 10%, in whole pixels
		notTarget = { alpha = 0.75 },
		casting = { alpha = 1 }, -- a casting plate ignores the notTarget fade
	},
	situations = {
		friendlyPlayer = { hide = { 'health', 'cast', 'hp' }, parts = { name = { font = { size = 12 } } } },
	},
})
