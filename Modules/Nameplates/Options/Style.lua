local _, ns = ...
local P = ns.Plates
local L = P.L
local Options = P.Options

-- Style page (3.2 #1). Phase 2: a style picker and the size. Phase 4a: live gallery cards with
-- hover-to-try, Customize this style (primary), Undo my changes, Make a copy, right-click Rename and
-- Delete; More settings: exact width and height, bar texture, font face and size.

local SIZES = { small = L['Small'], medium = L['Medium'], large = L['Large'] }

Options:AddPage('style', 1, function()
	local getStyle, setStyle = Options.Bind('style')
	local getSize, setSize = Options.Bind('size')
	local cardGrid = P.host and P.host.widgets and P.host.widgets.cardGrid
	local styleOption = {
		type = 'select',
		name = L['Style'],
		desc = L['How every nameplate looks. You can change parts of it later.'],
		order = 1,
		width = 'full',
		values = function()
			local values = {}
			for _, card in ipairs(P.Gallery:Cards()) do
				values[card.value] = card.title
			end
			return values
		end,
		get = getStyle,
		set = setStyle,
		disabled = Options.Locked,
	}
	if cardGrid then
		styleOption.dialogControl = cardGrid
		styleOption.arg = {
			size = 'look',
			cards = function()
				return P.Gallery:Cards()
			end,
		}
	end
	return {
		type = 'group',
		name = L['Style'],
		args = {
			style = styleOption,
			size = {
				type = 'select',
				name = L['Size'],
				desc = L['Plates get bigger or smaller in whole pixels, so borders stay sharp.'],
				order = 2,
				values = SIZES,
				sorting = { 'small', 'medium', 'large' },
				get = getSize,
				set = setSize,
			},
			undo = {
				type = 'execute',
				name = L['Undo my changes'],
				desc = L['Go back to the style as it was made. Your other settings stay.'],
				order = 3,
				hidden = function()
					return not P.Styles.Merge:HasChanges(P.Store:Get('style'))
				end,
				func = function()
					local id = P.Styles.Registry:ResolveId(P.Store:Get('style'))
					P.Store:Set({ 'tweaks', id }, nil)
				end,
			},
		},
	}
end)
