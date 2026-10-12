local _, ns = ...
local P = ns.Plates
local L = P.L

-- Names Only (internal): text and raid marker, used for friendly players and for every plate
-- shown in "Names only" mode. Not offered in the gallery.

P.Styles.Registry:RegisterBuiltin({
	id = 'namesOnly',
	name = L['Names Only'],
	description = L['Just the name, in class color for players.'],
	version = 1,
	schema = 1,
	order = 900,
	internal = true,
	plate = { sizes = { small = { 100, 12 }, medium = { 120, 14 }, large = { 140, 16 } } },
	regions = { click = { auto = true, pad = { 2, 2, 2, 2 } }, stack = { auto = true, pad = { 4, 4, 2, 2 } } },
	tokens = { accent = '$host', font = '$host', bar = 'Nameplates Flat', ink = { 0, 0, 0, 1 }, shade = { 0, 0, 0, 0.6 } },
	parts = {
		name = {
			order = 10,
			kind = 'text',
			source = 'name',
			anchor = { 'CENTER', 'plate', 'CENTER', 0, 0 },
			justify = 'CENTER',
			colors = 'name',
			font = { face = '$font', size = 12, flags = 'OUTLINE' },
		},
		marker = { order = 20, kind = 'icon', source = 'raidMarker', anchor = { 'BOTTOM', 'name', 'TOP', 0, 2 }, size = 14 },
		arrows = { order = 30, kind = 'highlight', state = 'target', art = 'underline' },
	},
	states = { notTarget = { alpha = 0.9 } },
})
