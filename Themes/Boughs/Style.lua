local SUI = SUI

-- Art and layout come from the shared painted-look builder (Themes/Painted.lua)
SUI.ThemePainted.Register({
	name = 'Boughs',
	displayName = 'Grove',
	description = 'Dark living wood, moss and small leaves around a forest-lens minimap',
	accent = { 0.498, 0.675, 0.573 },
	-- The plate has no name strip; the name sits above it
	nameAbove = true,
	-- The top right map reaches past the round mask's soft edge
	cornerMinimapPad = 4,
	-- The map in the bar covers the dark rim inside the ring
	dockedMinimapSize = 182,
	kit = 'boughs',
	colors = {
		frameBg = { 0.078, 0.118, 0.098, 0.95 },
		frameBorder = { 0.486, 0.439, 0.318, 1.00 },
	},
})
