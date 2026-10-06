local SUI = SUI

-- Art and layout come from the shared painted-look builder (Themes/Painted.lua)
SUI.ThemePainted.Register({
	name = 'Lamina',
	displayName = 'Lamina',
	description = 'A modern Classic: layered carved stone bound by forged straps, with tribal engravings',
	accent = { 0.600, 0.635, 0.651 },
	-- Classic's portraits face each other across the minimap
	portraits = 'inner',
	-- The top right minimap is drawn a little larger than the docked one
	cornerMinimapScale = 1.1,
	kit = 'lamina',
	colors = {
		frameBg = { 0.063, 0.086, 0.102, 0.93 },
		frameBorder = { 0.384, 0.424, 0.443, 1.00 },
	},
})
