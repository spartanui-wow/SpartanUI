local SUI = SUI

-- Art and layout come from the shared painted-look builder (Themes/Painted.lua)
SUI.ThemePainted.Register({
	name = 'Meridian',
	displayName = 'Observatory',
	description = 'A worn brass survey instrument: dark enamel, thin brass rims and sea-glass accents, with almost no ornament.',
	accent = { 0.537, 0.710, 0.675 },
	narrowCentre = true,
	-- The name strip ends in sea-glass beads
	nameInset = 16,
	kit = 'meridian',
	colors = {
		frameBg = { 0.047, 0.078, 0.075, 0.93 },
		frameBorder = { 0.553, 0.482, 0.345, 1.00 },
	},
})
