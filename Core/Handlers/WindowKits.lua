---@class SUI
local SUI = SUI

-- Window kits: the art and colors SpartanUI's themes lend to its own windows (setup, settings, tools).
-- Each kit only fills in the window's layers; the layout and behavior live in Lib's AddonTools.
---@class SUI.WindowKits
local WindowKits = {}
SUI.WindowKits = WindowKits

local ROOT = 'Interface\\AddOns\\SpartanUI\\images\\kits\\'

-- Themes without a kit of their own in their registry metadata
local LOOK_KITS = {
	War = 'war',
	Midnight = 'midnight',
	Classic = 'classic',
	Fel = 'fel',
	Digital = 'digital',
	ModernFlat = 'modernflat',
	HealerGrid = 'healergrid',
	ClassicDark = 'classicdark',
	Arcane = 'arcane',
	Tribal = 'tribal',
	Transparent = 'transparent',
}

local function Hex(value, alpha)
	return { tonumber(value:sub(1, 2), 16) / 255, tonumber(value:sub(3, 4), 16) / 255, tonumber(value:sub(5, 6), 16) / 255, alpha }
end

---The eight frame pieces plus rail and panel art every painted kit folder carries.
local function PaintedAssets(folder)
	local path = ROOT .. folder .. '\\'
	return {
		windowBorder = {
			cornerSize = 24,
			-- The corners carry a 24px beam in 64px, so at 24px it is 9px; the edges draw the same 9px
			edgeSize = 9,
			-- Edge strips are 32px with the 24px beam first
			edgeCrop = 0.75,
			tileLength = 96,
			pieces = {
				topLeft = path .. 'frame-top-left.png',
				topRight = path .. 'frame-top-right.png',
				bottomLeft = path .. 'frame-bottom-left.png',
				bottomRight = path .. 'frame-bottom-right.png',
				top = path .. 'frame-top.png',
				bottom = path .. 'frame-bottom.png',
				left = path .. 'frame-left.png',
				right = path .. 'frame-right.png',
			},
		},
		backdrop = path .. 'backdrop.png',
		materialTile = path .. 'material.png',
		divider = path .. 'divider.png',
		marker = path .. 'marker.png',
		['node-done'] = path .. 'node-done.png',
		['node-upcoming'] = path .. 'node-upcoming.png',
	}
end

---A painted look's kit: the shared frame pieces plus the crest mounted on the frame's top edge
---@param folder string
---@param crest? { width: number, height: number, overlap: number } a crest of another shape
local function LookAssets(folder, crest)
	local assets = PaintedAssets(folder)
	crest = crest or { width = 128, height = 64, overlap = 20 }
	assets.crest = { texture = ROOT .. folder .. '\\crest.png', width = crest.width, height = crest.height, overlap = crest.overlap }
	return assets
end

-- Painted kits keep their title and footer bars inside the frame's beam
local PAINTED_LAYOUT = { barInset = 9, sideInset = 18, dividerHeight = 16 }

local function Register(id, config)
	LibAT.UI.Kit:Register(id, config)
end

---Art-free themes get a flat kit: 1px trim, their own surface tone, buttons from the theme accent.
---@param base number[] Darkest surface color; the others are lifted from it
---@param trim number[]
---@param accent number[]
---@param alpha number How see-through the panels are
local function RegisterFlat(id, name, base, trim, accent, alpha)
	local function Lift(amount, a)
		return { base[1] + amount, base[2] + amount, base[3] + amount, a }
	end
	Register(id, {
		name = name,
		colors = {
			surface = { [0] = Lift(0, 0.95), [1] = Lift(0.025, alpha), [2] = Lift(0.05, math.min(alpha + 0.04, 1)), [3] = Lift(0.085, 0.98) },
			bar = Lift(0.02, 0.97),
			text = { 0.94, 0.95, 0.96 },
			secondary = { 0.72, 0.75, 0.78 },
			muted = { 0.52, 0.55, 0.59 },
			trim = trim,
			trimHi = { trim[1] + 0.18, trim[2] + 0.18, trim[3] + 0.18 },
			path = accent,
			tick = accent,
		},
		button = {
			primary = { top = accent, bottom = { accent[1] * 0.55, accent[2] * 0.55, accent[3] * 0.55 }, edge = accent, text = { 0.03, 0.04, 0.05 } },
		},
	})
end

local function RegisterWar(faction, accentEdge, primaryTop, primaryBottom, path)
	local assets = PaintedAssets('war-' .. faction)
	-- The faction crest is mounted on the frame's top edge; its base covers 20px of frame and title bar
	assets.crest = { texture = ROOT .. 'war-' .. faction .. '\\crest.png', width = 128, height = 64, overlap = 20 }
	Register('war-' .. faction, {
		name = faction == 'alliance' and 'War (Alliance)' or 'War (Horde)',
		layout = PAINTED_LAYOUT,
		backdropAspect = 2,
		backdropDim = 0.3,
		windowSurfaceAlpha = 0.1,
		materialAlpha = 0.14,
		colors = {
			surface = {
				[0] = Hex('0d0c0b', 0.92),
				[1] = { 0.027, 0.031, 0.039, 0.82 },
				[2] = { 0.063, 0.063, 0.067, 0.94 },
				[3] = Hex('1e1d1c', 0.98),
			},
			bar = { 0.016, 0.02, 0.024, 0.75 },
			text = Hex('ece9e2'),
			secondary = Hex('b3aea4'),
			muted = Hex('868178'),
			trim = Hex('6d6a66'),
			trimHi = Hex('a8a39b'),
			path = path,
			tick = accentEdge,
		},
		button = {
			primary = { top = primaryTop, bottom = primaryBottom, edge = accentEdge, text = Hex('fff6e6') },
			secondary = { top = Hex('34322f'), bottom = Hex('1a1918'), edge = Hex('5d5a55'), text = Hex('ece9e2') },
		},
		assets = assets,
	})
end

function WindowKits:Register()
	if not (LibAT and LibAT.UI and LibAT.UI.Kit) then
		return false
	end
	RegisterWar('alliance', Hex('c9a253'), Hex('2f62c9'), Hex('14306b'), Hex('c9a253'))
	RegisterWar('horde', Hex('4a4440'), Hex('b02a20'), Hex('5e110c'), Hex('b3261e'))

	Register('midnight', {
		name = 'Midnight',
		layout = PAINTED_LAYOUT,
		backdropAspect = 2,
		backdropDim = 0.42,
		materialAlpha = 0.16,
		colors = {
			surface = {
				[0] = Hex('07040f', 0.94),
				[1] = { 0.059, 0.035, 0.122, 0.88 },
				[2] = { 0.075, 0.051, 0.141, 0.94 },
				[3] = Hex('241a44', 0.98),
			},
			bar = { 0.07, 0.04, 0.145, 0.86 },
			text = Hex('eee8ff'),
			secondary = Hex('b5a8dc'),
			muted = Hex('7f74a6'),
			trim = Hex('4b3a8c'),
			trimHi = Hex('a487ff'),
			path = Hex('a487ff'),
			tick = Hex('bca7ff'),
		},
		button = {
			primary = { top = Hex('7651e6'), bottom = Hex('3a2380'), edge = Hex('b9a2ff'), text = Hex('fbf8ff') },
			secondary = { top = Hex('180f30'), bottom = Hex('0f0920'), edge = Hex('4b3a8c'), text = Hex('e3dbff') },
		},
		assets = PaintedAssets('midnight'),
	})

	Register('classic', {
		name = 'Classic',
		layout = PAINTED_LAYOUT,
		backdropAspect = 2,
		backdropDim = 0.48,
		materialAlpha = 0.12,
		colors = {
			surface = {
				[0] = Hex('090909', 0.94),
				[1] = { 0.063, 0.063, 0.067, 0.9 },
				[2] = Hex('181819', 0.96),
				[3] = Hex('242425', 0.98),
			},
			bar = { 0.039, 0.039, 0.043, 0.86 },
			text = Hex('e9e7e3'),
			secondary = Hex('aba8a2'),
			muted = Hex('78756f'),
			trim = Hex('4c4c4c'),
			trimHi = Hex('8e8e8e'),
			path = Hex('b8813e'),
			tick = Hex('b9b9b7'),
		},
		button = {
			primary = { top = Hex('a8722f'), bottom = Hex('573814'), edge = Hex('cfa66c'), text = Hex('fff4e2') },
			secondary = { top = Hex('3b3b3b'), bottom = Hex('1c1c1c'), edge = Hex('5e5e5e'), text = Hex('e9e7e3') },
		},
		assets = PaintedAssets('classic'),
	})

	Register('fel', {
		name = 'Fel',
		layout = PAINTED_LAYOUT,
		backdropAspect = 2,
		backdropDim = 0.42,
		materialAlpha = 0.14,
		colors = {
			surface = {
				[0] = Hex('030604', 0.94),
				[1] = { 0.024, 0.059, 0.031, 0.9 },
				[2] = { 0.027, 0.063, 0.035, 0.95 },
				[3] = Hex('122218', 0.98),
			},
			bar = { 0.02, 0.051, 0.027, 0.86 },
			text = Hex('eff9e8'),
			secondary = Hex('b1cda3'),
			muted = Hex('718f68'),
			trim = Hex('397c2c'),
			trimHi = Hex('b6ff54'),
			path = Hex('8fe33a'),
			tick = Hex('b9ff58'),
		},
		button = {
			primary = { top = Hex('7fcc28'), bottom = Hex('285f16'), edge = Hex('c4ff59'), text = Hex('f5ffe8') },
			secondary = { top = Hex('0b1a0e'), bottom = Hex('061008'), edge = Hex('397c2c'), text = Hex('e9f5e2') },
		},
		assets = PaintedAssets('fel'),
	})

	RegisterFlat('modernflat', 'Modern Flat', { 0.05, 0.065, 0.08 }, { 0.2, 0.26, 0.31 }, { 0.33, 0.78, 1 }, 0.92)
	RegisterFlat('healergrid', 'Healer Grid', { 0.055, 0.06, 0.06 }, { 0.22, 0.27, 0.24 }, { 0.32, 0.85, 0.48 }, 0.92)
	RegisterFlat('classicdark', 'Classic Dark', { 0.04, 0.035, 0.03 }, { 0.26, 0.22, 0.17 }, { 0.95, 0.7, 0.26 }, 0.82)

	Register('arcane', {
		name = 'Arcane',
		layout = PAINTED_LAYOUT,
		backdropAspect = 2,
		backdropDim = 0.4,
		materialAlpha = 0.12,
		colors = {
			surface = { [0] = Hex('080c19', 0.94), [1] = Hex('111a30', 0.9), [2] = Hex('182540', 0.94), [3] = Hex('243652', 0.98) },
			bar = Hex('111a30', 0.92),
			text = Hex('edf5ff'),
			secondary = Hex('b9cbe4'),
			muted = Hex('899dbd'),
			trim = Hex('526b93'),
			trimHi = Hex('b4dfff'),
			path = Hex('86bfff'),
			pathAhead = Hex('899dbd'),
			tick = Hex('b4dfff'),
		},
		button = {
			primary = { top = Hex('397cc0'), bottom = Hex('193c70'), edge = Hex('9bd9ff'), text = Hex('f0f8ff') },
			secondary = { top = Hex('263953'), bottom = Hex('131e32'), edge = Hex('637fa6'), text = Hex('dfedff') },
		},
		assets = PaintedAssets('arcane'),
	})

	Register('tribal', {
		name = 'Tribal',
		layout = PAINTED_LAYOUT,
		backdropAspect = 2,
		backdropDim = 0.42,
		materialAlpha = 0.12,
		colors = {
			surface = { [0] = Hex('120c08', 0.94), [1] = Hex('24180f', 0.9), [2] = Hex('302116', 0.94), [3] = Hex('402c1c', 0.98) },
			bar = Hex('24180f', 0.92),
			text = Hex('fff0d9'),
			secondary = Hex('d4b99a'),
			muted = Hex('ab8c6b'),
			trim = Hex('805a36'),
			trimHi = Hex('d8b181'),
			path = Hex('d49550'),
			pathAhead = Hex('ab8c6b'),
			tick = Hex('f0bd78'),
		},
		button = {
			primary = { top = Hex('b96b30'), bottom = Hex('633415'), edge = Hex('e9b16c'), text = Hex('fff2db') },
			secondary = { top = Hex('493221'), bottom = Hex('25190f'), edge = Hex('8a6240'), text = Hex('f3ddbf') },
		},
		assets = PaintedAssets('tribal'),
	})

	-- Glass: the game shows through the window and its panels; only menus and popups stay solid
	Register('transparent', {
		name = 'Transparent',
		layout = PAINTED_LAYOUT,
		backdropAspect = 2,
		backdropAlpha = 0.65,
		backdropDim = 0.16,
		windowSurfaceAlpha = 0.14,
		materialAlpha = 0.05,
		colors = {
			surface = { [0] = Hex('080b10', 0.6), [1] = { 15 / 255, 22 / 255, 30 / 255, 0.42 }, [2] = { 26 / 255, 36 / 255, 47 / 255, 0.52 }, [3] = Hex('253240', 0.9) },
			bar = { 15 / 255, 22 / 255, 30 / 255, 0.55 },
			text = Hex('edf5fc'),
			secondary = Hex('bccbd8'),
			muted = Hex('8fa3b5'),
			trim = Hex('435969'),
			trimHi = Hex('9cc5dc'),
			path = Hex('90bdd8'),
			pathAhead = Hex('8fa3b5'),
			tick = Hex('c0dfed'),
		},
		button = {
			primary = { top = Hex('35566d'), bottom = Hex('203746'), edge = Hex('7ca5bd'), text = Hex('f1f9ff') },
			secondary = { top = Hex('263440'), bottom = Hex('17222b'), edge = Hex('526b7e'), text = Hex('ddebf5') },
		},
		assets = PaintedAssets('transparent'),
	})

	-- Painted look: boughs
	Register('boughs', {
		name = 'Grove',
		layout = PAINTED_LAYOUT,
		backdropAspect = 2,
		backdropDim = 0.32,
		windowSurfaceAlpha = 0.1,
		materialAlpha = 0.12,
		colors = {
			surface = { [0] = Hex('141D18', 0.94), [1] = Hex('1B2420', 0.88), [2] = Hex('263025', 0.94), [3] = Hex('303C30', 0.98) },
			bar = Hex('1B2420', 0.92),
			text = Hex('E7EAD8'),
			secondary = Hex('BCC8B2'),
			muted = Hex('8E9C87'),
			trim = Hex('7C7051'),
			trimHi = Hex('A8956C'),
			path = Hex('4C5E49'),
			pathAhead = Hex('7FAC92'),
			tick = Hex('A8956C'),
		},
		button = {
			primary = { top = Hex('8BB69B'), bottom = Hex('63896F'), edge = Hex('A6C4A6'), text = Hex('132119') },
			secondary = { top = Hex('354331'), bottom = Hex('222D23'), edge = Hex('7D7254'), text = Hex('E7EAD8') },
		},
		-- The branches' tie rests on the top edge
		assets = LookAssets('boughs', { width = 128, height = 64, overlap = 4 }),
	})

	-- Painted look: meridian
	Register('meridian', {
		name = 'Observatory',
		layout = PAINTED_LAYOUT,
		backdropAspect = 2,
		backdropDim = 0.32,
		windowSurfaceAlpha = 0.1,
		materialAlpha = 0.12,
		colors = {
			surface = { [0] = Hex('17211F', 0.94), [1] = Hex('202B28', 0.88), [2] = Hex('293431', 0.94), [3] = Hex('111917', 0.98) },
			bar = Hex('202B28', 0.92),
			text = Hex('E7E5D5'),
			secondary = Hex('BCC7BF'),
			muted = Hex('899B91'),
			trim = Hex('8D7B58'),
			trimHi = Hex('BBA77C'),
			path = Hex('465650'),
			pathAhead = Hex('89B5AC'),
			tick = Hex('BBA77C'),
		},
		button = {
			primary = { top = Hex('9FC4BB'), bottom = Hex('789E95'), edge = Hex('BBA77C'), text = Hex('17211F') },
			secondary = { top = Hex('293431'), bottom = Hex('17211F'), edge = Hex('8D7B58'), text = Hex('E7E5D5') },
		},
		-- Its crest is a low crescent: sit it on the top edge rather than sinking it into the title bar
		assets = LookAssets('meridian', { width = 128, height = 64, overlap = 8 }),
	})

	-- Painted look: atlas
	Register('atlas', {
		name = 'Voyager',
		layout = PAINTED_LAYOUT,
		backdropAspect = 2,
		backdropDim = 0.32,
		windowSurfaceAlpha = 0.1,
		materialAlpha = 0.12,
		colors = {
			surface = { [0] = Hex('211C18', 0.94), [1] = Hex('28211B', 0.88), [2] = Hex('393028', 0.94), [3] = Hex('171411', 0.98) },
			bar = Hex('28211B', 0.92),
			text = Hex('F1E3C7'),
			secondary = Hex('CDBB9D'),
			muted = Hex('94836C'),
			trim = Hex('99714A'),
			trimHi = Hex('C79560'),
			path = Hex('735538'),
			pathAhead = Hex('3B3026'),
			tick = Hex('56B8B5'),
		},
		button = {
			primary = { top = Hex('348D91'), bottom = Hex('1B555D'), edge = Hex('99714A'), text = Hex('F1E3C7') },
			secondary = { top = Hex('393028'), bottom = Hex('211C18'), edge = Hex('99714A'), text = Hex('F1E3C7') },
		},
		-- A wide crest that rests on the frame's top edge rather than hanging into the window
		assets = LookAssets('atlas', { width = 160, height = 40, overlap = 12 }),
	})

	-- Digital has no painted art: 1px light lines over deep blue
	Register('digital', {
		name = 'Digital',
		colors = {
			surface = {
				[0] = Hex('04070b', 0.96),
				[1] = { 0.024, 0.047, 0.078, 0.9 },
				[2] = { 0.031, 0.063, 0.106, 0.94 },
				[3] = Hex('0e1c2e', 0.98),
			},
			bar = { 0.02, 0.047, 0.078, 0.96 },
			text = Hex('e2f4ff'),
			secondary = Hex('93b8cf'),
			muted = Hex('5f7f94'),
			trim = Hex('1d5d7e'),
			trimHi = Hex('49d6ff'),
			path = Hex('49d6ff'),
			tick = Hex('49d6ff'),
		},
		button = {
			primary = { top = Hex('12384a'), bottom = Hex('0a2230'), edge = Hex('49d6ff'), text = Hex('dff7ff') },
			secondary = { top = Hex('07111c'), bottom = Hex('050c14'), edge = Hex('1d5d7e'), text = Hex('bfe6f7') },
		},
	})
	return true
end

---Every window look, sorted by name, for pickers
---@return {id: string, name: string}[]
function WindowKits:GetList()
	local list = {}
	local Kit = LibAT and LibAT.UI and LibAT.UI.Kit
	if Kit then
		for id, config in pairs(Kit.registry) do
			list[#list + 1] = { id = id, name = config.name or id }
		end
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

---The window look the player picked; 'auto' follows the main look. Saved account-wide by Lib's AddonTools.
---@return string
function WindowKits:GetChoice()
	if LibAT and LibAT.Setup and LibAT.Setup.GetKit then
		return LibAT.Setup:GetKit()
	end
	return 'auto'
end

---@param id string a kit id, or 'auto'
function WindowKits:SetChoice(id)
	if LibAT and LibAT.Setup and LibAT.Setup.SetKit then
		LibAT.Setup:SetKit(id)
	end
end

---Which kit the active theme wears. War follows the player's faction.
---@return string
function WindowKits:GetActiveId()
	local style = SUI:GetActiveStyle()
	local entry = style and SUI.ThemeRegistry and SUI.ThemeRegistry:Get(style)
	local look = (entry and type(entry.variantGroup) == 'string' and entry.variantGroup) or style
	local id = (entry and type(entry.kit) == 'string' and entry.kit) or LOOK_KITS[look] or 'minimal'
	if id == 'war' then
		id = UnitFactionGroup('player') == 'Alliance' and 'war-alliance' or 'war-horde'
	end
	if not LibAT.UI.Kit.registry[id] then
		return 'minimal'
	end
	return id
end

return WindowKits
