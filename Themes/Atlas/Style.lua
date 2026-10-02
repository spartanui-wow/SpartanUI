local SUI = SUI

-- Art and layout come from the shared painted-look builder (Themes/Painted.lua)
SUI.ThemePainted.Register({
	name = 'Atlas',
	displayName = 'Voyager',
	description = "Made for WoW Forever: an adventurer's map case in dark leather and bronze, with a runed compass ring around the minimap and a teal sea map behind every window.",
	accent = { 0.337, 0.722, 0.710 },
	narrowCentre = true,
	-- Its rails rise toward the old centre panel: rebuild a wider middle when the bar joins up
	narrowBridge = 66,
	-- The plate has no name strip; the name sits above it
	nameAbove = true,
	kit = 'atlas',
	colors = {
		frameBg = { 0.098, 0.082, 0.071, 0.93 },
		frameBorder = { 0.600, 0.443, 0.290, 1.00 },
	},
})
