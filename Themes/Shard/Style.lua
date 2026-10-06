local SUI = SUI

-- Art and layout come from the shared painted-look builder (Themes/Painted.lua)
SUI.ThemePainted.Register({
	name = 'Shard',
	displayName = 'Shard',
	description = 'A modern Classic: carved stone wings and a minimap medallion, with tribal engravings',
	accent = { 0.643, 0.690, 0.714 },
	-- Classic's portraits face each other across the minimap
	portraits = 'inner',
	-- The top right minimap is drawn a little larger than the docked one
	cornerMinimapScale = 1.21,
	cornerMinimapPad = 3,
	defaultVariant = 'corner',
	kit = 'shard',
	colors = {
		frameBg = { 0.055, 0.063, 0.071, 0.93 },
		frameBorder = { 0.467, 0.498, 0.514, 1.00 },
	},
})
