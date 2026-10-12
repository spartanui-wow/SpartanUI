local _, ns = ...
local P = ns.Plates
local L = P.L
local Options = P.Options

-- Colors page (3.2 #3). Phase 4a. Scheme picker (P.Colors.SCHEME_ORDER), the threat row (role,
-- when, show threat on, six colors), the mob type swatches, color-blind colors; More settings: the
-- full ordered list per piece with the RuleList widget. Lists are written whole; reordering sets
-- the scheme to 'custom'. Phase 2 offers the scheme picker and the color-blind switch.

Options:AddPage('colors', 3, function()
	local getScheme, setScheme = Options.Bind('scheme')
	local getBlind, setBlind = Options.Bind('colorBlind')
	local values = { auto = L['Pick for my role'] }
	for _, id in ipairs(P.Colors.SCHEME_ORDER) do
		values[id] = P.Colors.SCHEME_LABELS[id]
	end
	return {
		type = 'group',
		name = L['Colors'],
		args = {
			scheme = {
				type = 'select',
				name = L['What colors the bar first'],
				desc = L['When more than one color fits, the top one wins.'],
				order = 1,
				width = 'double',
				values = values,
				get = getScheme,
				set = setScheme,
			},
			colorBlind = {
				type = 'toggle',
				name = L['Color-blind friendly colors'],
				order = 2,
				width = 'full',
				get = getBlind,
				set = setBlind,
			},
		},
	}
end)
