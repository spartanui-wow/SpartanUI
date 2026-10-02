local SUI = SUI

-- One shared layout for the painted looks (Atlas of Echoes, Boughs of Possibility, Quiet Meridian).
-- Each look is its art plus colors; everything is placed from LAYOUT below.
--
-- The bottom art places small named frames (sockets) at the layout's coordinates. Action bars,
-- the minimap, status bars and the player and target frames attach to their socket with no
-- offset, so they line up with the art whatever scale each of them uses.
--
-- LAYOUT is plain data in "art units": the coordinate space of the SpartanUI frame, with the
-- origin at the bottom centre of the screen, x to the right and y up. The art pictures and the
-- preview tools are made from the same numbers.

---@class SUI.ThemePainted
local Painted = {}
if SUI then
	SUI.ThemePainted = Painted
end

-- stylua: ignore start
Painted.LAYOUT = {
	-- The bottom art: two halves, each drawn at 768 x 384 from a 1024 x 512 picture
	art = { halfWidth = 768, height = 384, file = { width = 1024, height = 512 } },
	-- Action buttons in art units, whatever size the bar system draws them at
	button = 34,
	spacing = 3,
	blockSpacing = 4,
	-- Every action button gets the look's frame (Button.png), drawn this much larger than the button
	buttonFrame = 1.25,
	-- Bar centres. Bars 1-4 are rows of 12, bars 5 and 6 blocks of 4 x 3.
	bars = {
		BT4Bar1 = { x = -325.5, y = 67 },
		BT4Bar2 = { x = -325.5, y = 25 },
		BT4Bar3 = { x = 325.5, y = 67 },
		BT4Bar4 = { x = 325.5, y = 25 },
		BT4Bar5 = { x = -634, y = 63, block = true },
		BT4Bar6 = { x = 634, y = 63, block = true },
	},
	-- The calm part of each look's painted trays, measured from its pictures (tools/painted/trays.py),
	-- as distances from the centre line (the right side; the left mirrors it). The bars are fitted
	-- into these; a look without an entry uses the beds below.
	trays = {
		Atlas = {
			row = { inner = 126, outer = 555, bottom = 14.5, top = 82.8 },
			block = { inner = 567.2, outer = 691, bottom = 14.2, top = 116.2 },
		},
		Meridian = {
			row = { inner = 125.2, outer = 552.8, bottom = 4.8, top = 73.8 },
			block = { inner = 563.5, outer = 706.8, bottom = 4.5, top = 106.5 },
		},
	},
	-- How far the buttons stay inside a tray's calm part
	trayMargin = 2,
	-- Dark flat areas the art keeps calm behind the buttons
	beds = {
		{ x1 = -552, y1 = 2, x2 = -99, y2 = 90 },
		{ x1 = 99, y1 = 2, x2 = 552, y2 = 90 },
		{ x1 = -714, y1 = 2, x2 = -554, y2 = 124 },
		{ x1 = 554, y1 = 2, x2 = 714, y2 = 124 },
	},
	-- The minimap, and the hole in the art it shows through
	minimap = { x = 0, y = 110, size = 176, hole = 86 },
	-- "Minimap top right": the map's top right corner from the screen's, and its bezel, drawn at
	-- 256 x 256 from a 512 x 512 picture centred on the map
	cornerMinimap = { x = -56, y = -56, bezel = 256, file = 512 },
	-- Looks registered with narrowCentre close up the bar when the minimap is top right: everything
	-- within plaque of the centre (the centre panel and the trays' inner ends) is cut away and both
	-- halves slide in by plaque - keep, joining into one bar (keep 0). The cut sits where the status
	-- bar grooves begin, so the grooves join too.
	-- The status bars on these looks are statusTrim shorter, flush with each groove's outer end, so
	-- they still fit once the grooves' inner ends are cut; centreGap is kept between the two rows.
	narrowCentre = { plaque = 150, keep = 0, edge = 0, statusTrim = 20, centreGap = 12 },
	-- Experience and reputation bars along the top of the bar art
	statusBars = {
		Left = { x = -325, y = 104, width = 390, height = 12 },
		Right = { x = 325, y = 104, width = 390, height = 12 },
	},
	-- Player and target frames (centre and size of the bar area). The cast bar covers the power
	-- bar while casting and the health bar fills the rest, so no strip sits empty between casts.
	frames = {
		player = { x = -305, y = 200 },
		target = { x = 305, y = 200 },
		width = 230,
		health = 24,
		power = 12,
		cast = 12,
		-- How far the bars sit inside the plate's window, clear of its painted border
		inset = { side = 4, top = 2, bottom = 4 },
	},
	-- The portrait mount: the ring and the piece joining it to the plate, one 256 x 256 picture at the
	-- plate's scale, centred on the portrait and drawn behind the plate at a fixed size (x from the
	-- frame's portrait-side edge)
	mount = { x = -62, size = 60, file = 256 },
	-- The plate drawn behind the player frame (the target uses it mirrored), relative to the
	-- frame's top left corner, y down; drawn at 312 x 78 from a 512 x 128 picture
	plate = {
		left = 70, top = 18, width = 312, height = 78,
		file = { width = 512, height = 128 },
		portrait = { x = -26, size = 60 },
		-- Nine-slice margins in picture pixels: the left cap holds the portrait ring, the right
		-- cap the end fittings, the top band the name strip; the rest stretches with the frame
		slice = { left = 136, right = 40, top = 36, bottom = 26 },
	},
}
-- stylua: ignore end

local L = Painted.LAYOUT

---Size of a bar in art units
---@param block? boolean
---@return number width
---@return number height
function Painted.BarSize(block)
	if block then
		return 4 * L.button + 3 * L.blockSpacing, 3 * L.button + 2 * L.blockSpacing
	end
	return 12 * L.button + 11 * L.spacing, L.button
end

-- Spacing between buttons, in the action bars' own (native) units: rows and the 4 x 3 blocks
local ROW_SPACING, BLOCK_SPACING = 3, 4

---Fit the bars into a look's painted trays: the largest button that fits (never above the layout's
---button), with each bar centred in its tray. Spacing scales with the buttons, as the action bars
---draw it.
---@param name string look id
---@param native number the action bars' native button size
---@return table<string, { x: number, y: number, button: number, width: number, height: number }>
function Painted.FitBars(name, native)
	local beds = L.beds
	local trays = L.trays[name]
		or {
			row = { inner = beds[2].x1, outer = beds[2].x2, bottom = beds[2].y1, top = beds[2].y2 },
			block = { inner = beds[4].x1, outer = beds[4].x2, bottom = beds[4].y1, top = beds[4].y2 },
		}
	local m = L.trayMargin
	local spots = {}
	-- Rows: two bars of 12 stacked in each tray
	local row = trays.row
	local rs = ROW_SPACING / native
	local w, h = row.outer - row.inner - 2 * m, row.top - row.bottom - 2 * m
	local b = math.floor(math.min(L.button, w / (12 + 11 * rs), h / (2 + rs)))
	local cx, cy = (row.inner + row.outer) / 2, (row.bottom + row.top) / 2
	local step = (b + b * rs) / 2
	local rowWidth = 12 * b + 11 * b * rs
	for key, spot in pairs({ BT4Bar1 = { -cx, cy + step }, BT4Bar2 = { -cx, cy - step }, BT4Bar3 = { cx, cy + step }, BT4Bar4 = { cx, cy - step } }) do
		spots[key] = { x = spot[1], y = spot[2], button = b, width = rowWidth, height = b }
	end
	-- Blocks: 4 x 3 at each end
	local block = trays.block
	local bs = BLOCK_SPACING / native
	w, h = block.outer - block.inner - 2 * m, block.top - block.bottom - 2 * m
	b = math.floor(math.min(L.button, w / (4 + 3 * bs), h / (3 + 2 * bs)))
	cx, cy = (block.inner + block.outer) / 2, (block.bottom + block.top) / 2
	local bw, bh = 4 * b + 3 * b * bs, 3 * b + 2 * b * bs
	spots.BT4Bar5 = { x = -cx, y = cy, button = b, width = bw, height = bh }
	spots.BT4Bar6 = { x = cx, y = cy, button = b, width = bw, height = bh }
	return spots
end

---How far past the frame's portrait-side edge the portrait ring reaches, plus a small gap
---@return number
function Painted.PastPortrait()
	return -L.mount.x + L.mount.size / 2 + 8 + 6
end

---How far the plate reaches below the player and target frames
---@return number
function Painted.PlateBelow()
	return L.plate.height - L.plate.top - Painted.FrameHeight()
end

---Height of the player and target frames (the bar window the plate is painted around)
---@return number
function Painted.FrameHeight()
	return L.frames.health + L.frames.power + L.frames.cast
end

if not SUI then
	return Painted
end

----------------------------------------------------------------------------------------------------
-- Unit frames
----------------------------------------------------------------------------------------------------

---The action bars' native button size on this client
---@return number
local function NativeButton()
	local ActionBars = SUI:GetModule('ActionBars', true)
	return (ActionBars and ActionBars.DEFAULT_BUTTON_SIZE) or (SUI.IsRetail and 45 or 36)
end

---Where each status bar sits: looks that close up their centre use shorter bars, flush with the
---outer end of their groove
---@param name string
---@return table<string, { x: number, y: number, width: number, height: number }>
local function StatusSpots(name)
	local spots = {}
	for key, bar in pairs(L.statusBars) do
		local width = bar.width
		if Painted.narrow and Painted.narrow[name] then
			width = bar.width - L.narrowCentre.statusTrim
		end
		local outer = math.abs(bar.x) + bar.width / 2
		local x = outer - width / 2
		spots[key] = { x = bar.x < 0 and -x or x, y = bar.y, width = width, height = bar.height }
	end
	return spots
end

local fitted = {}

---The look's fitted bar spots (see Painted.FitBars), worked out once
---@param name string
---@return table
local function BarSpots(name)
	fitted[name] = fitted[name] or Painted.FitBars(name, NativeButton())
	return fitted[name]
end

local PORTRAIT_MASK = 'Interface\\CHARACTERFRAME\\TempPortraitAlphaMask'

---Is this frame one of the painted look's own player or target frames?
---@param frame table unit frame
---@return string|nil unit 'player' or 'target'
local function PaintedUnit(frame)
	local unit = frame._realFrameName or frame.unitOnCreate
	if unit ~= 'player' and unit ~= 'target' then
		return nil
	end
	local art = frame.DB and frame.DB.elements and frame.DB.elements.SpartanArt
	local graphic = art and art.full and art.full.graphic
	if not frame.isPreview and (not Painted.active or graphic ~= Painted.active) then
		return nil
	end
	return unit
end

---Where the bars sit inside the plate's window, clear of its painted border
---@return table healthPoints
---@return table lowerPoints points for the power and cast bars
function Painted.BarPoints()
	local inset = L.frames.inset
	local lowerTop = inset.bottom + L.frames.power
	local health = {
		{ anchor = 'TOPLEFT', relativeTo = 'Frame', x = inset.side, y = -inset.top },
		{ anchor = 'TOPRIGHT', relativeTo = 'Frame', x = -inset.side, y = -inset.top },
		{ anchor = 'BOTTOMLEFT', relativeTo = 'Frame', x = inset.side, y = lowerTop },
		{ anchor = 'BOTTOMRIGHT', relativeTo = 'Frame', x = -inset.side, y = lowerTop },
	}
	local lower = {
		{ anchor = 'BOTTOMLEFT', relativeTo = 'Frame', x = inset.side, y = inset.bottom },
		{ anchor = 'BOTTOMRIGHT', relativeTo = 'Frame', x = -inset.side, y = inset.bottom },
	}
	return health, lower
end

-- 3D portraits cannot be masked round: the model is sized so the ring hides its corners and is
-- drawn just below the art, with a dark disc behind it filling the opening's edges
local MODEL_SIZE = 0.9

---@param frame table unit frame
local function PlacePortrait(frame)
	local unit = PaintedUnit(frame)
	if not unit then
		return
	end
	local spot = L.mount
	local x = unit == 'player' and spot.x or -spot.x
	local edge = unit == 'player' and 'LEFT' or 'RIGHT'
	local portrait = frame.Portrait2D
	if portrait then
		portrait:ClearAllPoints()
		portrait:SetSize(spot.size, spot.size)
		portrait:SetPoint('CENTER', frame, edge, x, 0)
	end
	-- Clicking the portrait (and its mount) targets and opens the menu like the frame itself
	local enabled = frame.DB.elements.Portrait and frame.DB.elements.Portrait.enabled ~= false
	if not frame.isPreview and SUI.UF and SUI.UF.SetPortraitHitRect then
		local reach = enabled and (-spot.x + spot.size / 2) or 0
		local tall = enabled and math.max(0, spot.size / 2 - frame:GetHeight() / 2) or 0
		SUI.UF:SetPortraitHitRect(frame, unit == 'player' and reach or 0, unit == 'target' and reach or 0, tall, tall)
	end
	local model = frame.Portrait3D
	local db = frame.DB.elements.Portrait
	if model and db and db.enabled ~= false and db.type == '3D' then
		local art = frame.SpartanArt
		local level = art and art:GetFrameLevel() or 2
		model:ClearAllPoints()
		model:SetSize(spot.size * MODEL_SIZE, spot.size * MODEL_SIZE)
		model:SetPoint('CENTER', frame, edge, x, 0)
		model:SetFrameStrata(art and art:GetFrameStrata() or 'BACKGROUND')
		model:SetFrameLevel(math.max(level - 1, 1))
		local back = frame.PaintedPortraitBack
		if not back then
			back = CreateFrame('Frame', nil, frame)
			back.fill = back:CreateTexture(nil, 'BACKGROUND')
			back.fill:SetAllPoints()
			back.fill:SetColorTexture(0.03, 0.03, 0.035, 1)
			if back.fill.AddMaskTexture and back.CreateMaskTexture then
				local mask = back:CreateMaskTexture()
				mask:SetTexture(PORTRAIT_MASK, 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE')
				mask:SetAllPoints(back.fill)
				back.fill:AddMaskTexture(mask)
			end
			frame.PaintedPortraitBack = back
		end
		back:SetFrameStrata(model:GetFrameStrata())
		back:SetFrameLevel(math.max(level - 2, 0))
		back:ClearAllPoints()
		back:SetSize(spot.size, spot.size)
		back:SetPoint('CENTER', frame, edge, x, 0)
		back:Show()
	elseif frame.PaintedPortraitBack then
		frame.PaintedPortraitBack:Hide()
	end
end

---Places the round portrait inside its mount's ring. Called after the art updates; the portrait's own
---update re-anchors it and then shows it, so placing again on Show always wins.
---@param frame table unit frame
---@param unit string
function Painted.UnitFrameCallback(frame, unit)
	local portrait = frame.Portrait2D
	if not portrait then
		return
	end
	if not frame.PaintedHooks and frame.ElementUpdate then
		frame.PaintedHooks = true
		hooksecurefunc(frame, 'ElementUpdate', function(self, element)
			if not PaintedUnit(self) then
				return
			end
			if element == 'Portrait' then
				-- Turning the portrait on or off shows or hides its mount
				self:ElementUpdate('SpartanArt')
			end
		end)
	end
	if not frame.PaintedPortraitShowHook then
		frame.PaintedPortraitShowHook = true
		local function Replace()
			if frame.PaintedPortraitHooked then
				PlacePortrait(frame)
			end
		end
		hooksecurefunc(portrait, 'Show', Replace)
		if frame.Portrait3D then
			hooksecurefunc(frame.Portrait3D, 'Show', Replace)
		end
	end
	if not frame.PaintedPortraitHooked then
		frame.PaintedPortraitHooked = true
		if portrait.AddMaskTexture then
			local mask = frame:CreateMaskTexture()
			mask:SetTexture(PORTRAIT_MASK, 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE')
			mask:SetAllPoints(portrait)
			portrait:AddMaskTexture(mask)
			frame.PaintedPortraitMask = mask
		end
	end
	-- The mount is drawn behind the plate: the plate's own pieces use this layer's default sublevel
	if frame.SpartanArt and frame.SpartanArt.bottom and not frame.PaintedMountLayer then
		frame.PaintedMountLayer = true
		frame.SpartanArt.bottom:SetDrawLayer('BACKGROUND', -2)
	end
	PlacePortrait(frame)
end

---Player or target frame config: flat bars inside the painted plate, a round portrait in its ring
---@param name string theme name
---@param colors table theme colors
---@param isTarget boolean
---@return table
local function UnitFrame(name, colors, isTarget)
	local Flat = SUI.ThemeFlat
	local frame = Flat.Frame({
		width = L.frames.width,
		health = L.frames.health,
		power = L.frames.power,
		cast = L.frames.cast,
		bg = colors.frameBg,
		border = colors.frameBorder,
		name = 12,
	})
	frame.scale = 0.92
	local elements = frame.elements
	-- The plate paints the window and its border; a flat background would cover them
	elements.FrameBackground = { enabled = false }
	-- Power along the bottom with the cast bar over it, health over everything above, all inset
	-- inside the window
	local health, lower = Painted.BarPoints()
	elements.Health.points = health
	elements.Power.points = lower
	elements.Castbar.points = lower
	elements.Castbar.height = L.frames.power
	-- Above the plate art (level 2); the cast bar above the power bar it covers
	elements.Power.FrameLevel = 4
	elements.Castbar.FrameLevel = 6
	elements.Portrait = { enabled = true, type = '2D', position = isTarget and 'right' or 'left' }
	-- The mount uses the art's bottom piece: the frame code tints every element's bg as a bar background
	elements.SpartanArt = { full = { enabled = true, graphic = name }, bottom = { enabled = true, graphic = name } }
	-- Auras sit outside the plate: buffs above it, debuffs below it
	local above = L.plate.top + 4
	local below = L.plate.height - L.plate.top - Painted.FrameHeight() + 4
	if isTarget then
		Flat.Auras(
			elements,
			{ number = 8, size = 22, anchor = 'BOTTOMRIGHT', relativePoint = 'TOPRIGHT', growthx = 'LEFT', growthy = 'UP', y = above, filter = 'healing_mode' },
			{ number = 8, size = 26, anchor = 'TOPRIGHT', relativePoint = 'BOTTOMRIGHT', growthx = 'LEFT', growthy = 'DOWN', y = -below, filter = 'player_debuffs' }
		)
	else
		Flat.Auras(elements, nil, { number = 8, size = 26, anchor = 'TOPLEFT', relativePoint = 'BOTTOMLEFT', growthx = 'RIGHT', growthy = 'DOWN', y = -below })
	end
	local nameX = L.frames.inset.side + 2
	elements.Name = {
		enabled = true,
		textSize = 12,
		height = 14,
		text = '[difficulty][smartlevel] [SUI_ColorClass][name]',
		SetJustifyH = isTarget and 'RIGHT' or 'LEFT',
		position = {
			anchor = isTarget and 'BOTTOMRIGHT' or 'BOTTOMLEFT',
			relativeTo = 'Frame',
			relativePoint = isTarget and 'TOPRIGHT' or 'TOPLEFT',
			x = isTarget and -nameX or nameX,
			y = 2,
		},
	}
	return frame
end

---The plate art for one side, cut in nine so it follows the frame's width and bar heights.
---Frames with the portrait turned off get the plate without a ring.
---@param root string image folder
---@param isTarget boolean
---@return table
local function Plate(root, isTarget)
	local plate = L.plate
	local right = plate.width - plate.left - L.frames.width
	local bottom = plate.height - plate.top - Painted.FrameHeight()
	return {
		-- Always the plate without a ring: the ring is its own piece (Ring), so stretching the plate
		-- for taller bars never stretches the ring
		path = root .. 'UnitFrame-NoPortrait.png',
		slice = {
			file = plate.file,
			margins = plate.slice,
			scale = plate.width / plate.file.width,
			insets = {
				left = isTarget and right or plate.left,
				right = isTarget and plate.left or right,
				top = plate.top,
				bottom = bottom,
			},
			mirror = isTarget,
		},
	}
end

---The portrait mount: the ring and the piece joining it to the plate, drawn behind the plate at a
---fixed size and centred on the portrait, so taller bars never stretch it. It shows only while the
---portrait does.
---@param root string image folder
---@param isTarget boolean
---@return table
local function Mount(root, isTarget)
	local size = L.mount.file * L.plate.width / L.plate.file.width
	-- The texture's outer edge, from the frame's portrait-side edge
	local offset = L.mount.x - size / 2
	return {
		path = function(frame)
			local elements = frame and frame.DB and frame.DB.elements
			if elements and elements.Portrait and elements.Portrait.enabled == false then
				return nil
			end
			return root .. 'UnitFrame-Mount.png'
		end,
		width = size,
		-- Square
		heightScale = 1,
		TexCoord = isTarget and { 1, 0, 0, 1 } or { 0, 1, 0, 1 },
		position = { anchor = isTarget and 'RIGHT' or 'LEFT', x = isTarget and -offset or offset, y = 0 },
	}
end

----------------------------------------------------------------------------------------------------
-- Bottom art and sockets
----------------------------------------------------------------------------------------------------

---@param name string
---@param key string
---@return string
local function SocketName(name, key)
	return 'SUI_Art_' .. name .. '_' .. key
end

---@param art Frame
---@param name string
---@param key string
---@param x number
---@param y number
---@param width number
---@param height number
local function Socket(art, name, key, x, y, width, height)
	local socket = _G[SocketName(name, key)] or CreateFrame('Frame', SocketName(name, key), art)
	socket:SetSize(width, height)
	socket:ClearAllPoints()
	socket:SetPoint('CENTER', art, 'BOTTOM', x, y)
	return socket
end

---@param name string
---@param root string
function Painted.CreateArtwork(name, root)
	local art = _G['SUI_Art_' .. name]
	if art.Left then
		return
	end
	art:SetFrameStrata('BACKGROUND')
	art:SetFrameLevel(1)
	art:SetSize(2, 2)
	art:SetPoint('BOTTOM', SUI_BottomAnchor)

	art.Left = art:CreateTexture('SUI_Art_' .. name .. '_Left', 'BORDER')
	art.Left:SetTexture(root .. 'Bottom-Left.png')
	art.Left:SetSize(L.art.halfWidth, L.art.height)
	art.Left:SetPoint('BOTTOMRIGHT', art, 'BOTTOM', 0, 0)

	art.Right = art:CreateTexture('SUI_Art_' .. name .. '_Right', 'BORDER')
	art.Right:SetTexture(root .. 'Bottom-Right.png')
	art.Right:SetSize(L.art.halfWidth, L.art.height)
	art.Right:SetPoint('BOTTOMLEFT', art, 'BOTTOM', 0, 0)

	for key, spot in pairs(BarSpots(name)) do
		Socket(art, name, key, spot.x, spot.y, spot.width, spot.height)
	end
	local minimap = Socket(art, name, 'Minimap', L.minimap.x, L.minimap.y, L.minimap.size, L.minimap.size)
	Socket(art, name, 'Center', L.minimap.x, L.minimap.y, L.minimap.size, L.minimap.size)
	art.MinimapBezel = minimap:CreateTexture('SUI_Art_' .. name .. '_MinimapBezel', 'BORDER')
	art.MinimapBezel:SetTexture(root .. 'Minimap.png')
	art.MinimapBezel:SetSize(L.cornerMinimap.bezel, L.cornerMinimap.bezel)
	art.MinimapBezel:SetPoint('CENTER', minimap, 'CENTER', 0, 0)
	art.MinimapBezel:Hide()
	for key, bar in pairs(StatusSpots(name)) do
		Socket(art, name, 'Status' .. key, bar.x, bar.y, bar.width, bar.height)
	end
	for _, unit in ipairs({ 'player', 'target' }) do
		local spot = L.frames[unit]
		Socket(art, name, unit, spot.x, spot.y, L.frames.width, Painted.FrameHeight())
	end
end

----------------------------------------------------------------------------------------------------
-- Minimap: docked in the bar, or top right in its own bezel
----------------------------------------------------------------------------------------------------

---@param name string
---@return 'docked'|'corner'
function Painted.GetVariant(name)
	local variant = SUI.ThemeRegistry and SUI.ThemeRegistry:GetActiveVariant(name)
	return variant == 'corner' and 'corner' or 'docked'
end

---The minimap module centres its holder, which is taller than the map (room for the zone text)
---and holds the map at the client's own offset. Measure where the map sits inside its holder and
---anchor the holder to the socket so the map's centre lands on it. The map's place inside the
---holder does not change when the holder moves, so this gives the same answer whenever it runs,
---even before the game has settled positions after a move.
---@param name string
function Painted.AlignMinimap(name)
	if Painted.active ~= name or InCombatLockdown() then
		return
	end
	local socket = _G[SocketName(name, 'Minimap')]
	local holder = _G.SUI_Minimap
	if not socket or not holder or not Minimap then
		return
	end
	local MoveIt = SUI:GetModule('MoveIt', true)
	if MoveIt and MoveIt.IsMoved and MoveIt:IsMoved('Minimap') then
		return
	end
	local mx, my = Minimap:GetCenter()
	local hx, hy = holder:GetCenter()
	if not mx or not hx then
		return
	end
	local scale = holder:GetEffectiveScale()
	local mapScale = Minimap:GetEffectiveScale()
	local rx = (mx * mapScale - hx * scale) / scale
	local ry = (my * mapScale - hy * scale) / scale
	holder:ClearAllPoints()
	holder:SetPoint('CENTER', socket, 'CENTER', -rx, -ry)
end

local alignQueued = {}

---Align on the next frame, once the minimap module's own changes are laid out
---@param name string
function Painted.QueueAlignMinimap(name)
	if alignQueued[name] then
		return
	end
	alignQueued[name] = true
	C_Timer.After(0, function()
		alignQueued[name] = nil
		Painted.AlignMinimap(name)
	end)
end

---@param name string
local function RefreshMinimap(name)
	local module = SUI:GetModule('Minimap', true)
	if module and module.UpdatePosition and not InCombatLockdown() then
		module:UpdatePosition()
	end
	Painted.AlignMinimap(name)
end

---Looks whose bar closes up its centre when the minimap moves to the top right
Painted.narrow = {}

---Place the bar and status bar sockets, slid toward the centre by shift (art units)
---@param name string
---@param shift number
local function PlaceBarSockets(name, shift)
	local art = _G['SUI_Art_' .. name]
	local function Place(key, x, y)
		local socket = _G[SocketName(name, key)]
		if socket then
			socket:ClearAllPoints()
			socket:SetPoint('CENTER', art, 'BOTTOM', x < 0 and x + shift or x - shift, y)
		end
	end
	local joined = shift > 0 and L.narrowCentre.keep == 0
	for key, spot in pairs(BarSpots(name)) do
		local x = spot.x
		-- Once the halves join, the rows move out just enough to keep a gap at the centre
		local inner = math.abs(spot.x) - shift - spot.width / 2
		if joined and inner < L.narrowCentre.centreGap / 2 then
			local reach = L.narrowCentre.centreGap / 2 + spot.width / 2 + shift
			x = spot.x < 0 and -reach or reach
		end
		Place(key, x, spot.y)
	end
	for key, bar in pairs(StatusSpots(name)) do
		Place('Status' .. key, bar.x, bar.y)
	end
end

local pendingSockets = {}
local socketWatcher

---Action bars hang from the sockets, so they can only move out of combat
---@param name string
---@param shift number
local function MoveBarSockets(name, shift)
	if not InCombatLockdown() then
		PlaceBarSockets(name, shift)
		return
	end
	pendingSockets[name] = shift
	if not socketWatcher then
		socketWatcher = CreateFrame('Frame')
		socketWatcher:SetScript('OnEvent', function(self)
			self:UnregisterEvent('PLAYER_REGEN_ENABLED')
			for pendingName, pendingShift in pairs(pendingSockets) do
				PlaceBarSockets(pendingName, pendingShift)
			end
			wipe(pendingSockets)
		end)
	end
	socketWatcher:RegisterEvent('PLAYER_REGEN_ENABLED')
end

---Show the active variant: the bar with or without its minimap opening, and the minimap's spot
---@param name string
---@param root string
function Painted.ApplyVariant(name, root)
	local art = _G['SUI_Art_' .. name]
	if not art or not art.Left then
		return
	end
	local corner = Painted.GetVariant(name) == 'corner'
	local narrow = L.narrowCentre
	MoveBarSockets(name, (corner and Painted.narrow[name]) and (narrow.plaque - narrow.keep) or 0)
	local suffix = corner and '-Closed' or ''
	art.Left:SetTexture(root .. 'Bottom-Left' .. suffix .. '.png')
	art.Right:SetTexture(root .. 'Bottom-Right' .. suffix .. '.png')
	local socket = _G[SocketName(name, 'Minimap')]
	socket:ClearAllPoints()
	if corner then
		socket:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', L.cornerMinimap.x, L.cornerMinimap.y)
		art.MinimapBezel:Show()
	else
		socket:SetPoint('CENTER', art, 'BOTTOM', L.minimap.x, L.minimap.y)
		art.MinimapBezel:Hide()
	end
	if Painted.active == name then
		RefreshMinimap(name)
	end
end

---@param name string
local function VariantOptions(name, displayName)
	local style = SUI.opt and SUI.opt.args.General and SUI.opt.args.General.args.style
	if not style then
		return
	end
	local values = { docked = SUI.L['Minimap in the bar'], corner = SUI.L['Minimap top right'] }
	local option = {
		name = displayName,
		type = 'select',
		dialogControl = 'ThemeVariantCard',
		values = values,
		sorting = { 'docked', 'corner' },
		get = function()
			return Painted.GetVariant(name)
		end,
		set = function(_, value)
			if SUI:GetActiveStyle() ~= name then
				SUI:SetActiveStyle(name)
				if SUI.UF then
					SUI.UF:SetActiveStyle(name)
				end
			end
			SUI.ThemeRegistry:ApplyVariant(name, value)
		end,
	}
	if style.args.OverallStyle then
		style.args.OverallStyle.args[name] = option
	end
	if style.args.Artwork then
		style.args.Artwork.args[name] = SUI:CopyData({}, option)
	end
end

----------------------------------------------------------------------------------------------------
-- Theme data
----------------------------------------------------------------------------------------------------

---Bar positions and scales: every bar sits on its socket at its fitted button size
---@param name string
---@return table positions
---@return table scales
local function BarLayout(name)
	local native = NativeButton()
	local spots = BarSpots(name)
	local positions, scales = {}, {}
	-- Bars are drawn at the theme scale times 1/0.92 relative to the art
	for key, spot in pairs(spots) do
		positions[key] = 'CENTER,' .. SocketName(name, key) .. ',CENTER,0,0'
		scales[key] = spot.button / (native * 1.08696)
	end
	local scale = scales.BT4Bar1
	local center = SocketName(name, 'Center')
	positions.BT4BarExtraActionBar = 'BOTTOM,' .. center .. ',TOP,0,70'
	positions.BT4BarZoneAbilityBar = 'BOTTOM,' .. center .. ',TOP,0,70'
	for _, key in ipairs({ 'BT4BarPetBar', 'BT4BarStanceBar', 'MultiCastActionBarFrame' }) do
		scales[key] = scale * 0.9
	end
	scales.BT4BarMicroMenu = 0.65
	scales.BT4BarBagBar = 0.65
	return positions, scales
end

---@param name string
---@param root string
---@return table
local function Minimap(name)
	local position = 'CENTER,' .. SocketName(name, 'Minimap') .. ',CENTER,0,0'
	local size = { L.minimap.size, L.minimap.size }
	if SUI.BlizzAPI.HasModernMinimap() then
		return {
			position = position,
			shape = 'circle',
			size = size,
			scaleWithArt = true,
			elements = { background = { enabled = false } },
		}
	end
	return {
		position = position,
		shape = 'circle',
		size = size,
		scaleWithArt = true,
		background = { enabled = false },
	}
end

---@param name string
---@param root string
---@return table
local function StatusBars(name, root)
	local bars = {}
	for key, bar in pairs(StatusSpots(name)) do
		bars[key] = {
			size = { bar.width, bar.height },
			Position = 'CENTER,' .. SocketName(name, 'Status' .. key) .. ',CENTER,0,0',
			bgTexture = root .. 'StatusBar.png',
			-- Drawn over the fill on classic clients: the groove's frame with its middle cut out
			overlayTexture = root .. 'StatusBar-Frame.png',
			texCords = key == 'Right' and { 1, 0, 0, 1 } or { 0, 1, 0, 1 },
			alpha = 1,
			-- Both bars fill left to right (the classic-client default fills the left one from the centre)
			Grow = 'RIGHT',
			-- Classic clients draw the fill themselves: a flat bar inside the groove's opening (the
			-- groove picture's middle 495 x 16 of 512 x 32), not the tall glow made for other looks
			GlowImage = 'Interface\\AddOns\\SpartanUI\\images\\statusbars\\Smoothv2',
			GlowHeight = bar.height * 16 / 32,
			GlowPoint = { x = bar.width * 8 / 512, y = 0 },
			-- The fill's full width is the bar width minus (MaxWidth - GlowPoint.x)
			MaxWidth = bar.width * 8 / 512 + bar.width * 17 / 512,
		}
	end
	return bars
end

----------------------------------------------------------------------------------------------------
-- Registration
----------------------------------------------------------------------------------------------------

---@class SUI.ThemePainted.Spec
---@field name string theme id, also its folder under Themes
---@field displayName string
---@field description string
---@field accent number[]
---@field kit string window kit id
---@field colors { frameBg: number[], frameBorder: number[] }
---@field narrowCentre? boolean close up the bar's centre when the minimap is top right

---Register a painted look
---@param spec SUI.ThemePainted.Spec
---@return table module
function Painted.Register(spec)
	local name = spec.name
	local root = 'Interface\\AddOns\\SpartanUI\\Themes\\' .. name .. '\\Images\\'
	local module = SUI:NewModule('Style.' .. name)
	module.Settings = {}
	CreateFrame('Frame', 'SUI_Art_' .. name, SpartanUI)

	Painted.narrow[name] = spec.narrowCentre or nil

	function module:OnInitialize()
		SUI.ThemeRegistry:Register({
			name = name,
			displayName = spec.displayName,
			apiVersion = 1,
			description = spec.description,
			setup = { image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_' .. name },
			accent = spec.accent,
			kit = spec.kit,
			applicableTo = { player = true, target = true },
			variants = {
				{ id = 'docked', label = SUI.L['Minimap in the bar'] },
				{ id = 'corner', label = SUI.L['Minimap top right'] },
			},
			variantCallback = function()
				Painted.ApplyVariant(name, root)
			end,
		}, function()
			local positions, scales = BarLayout(name)
			return {
				frames = {
					player = UnitFrame(name, spec.colors, false),
					target = UnitFrame(name, spec.colors, true),
				},
				barPositions = positions,
				barScales = scales,
				minimap = Minimap(name),
				buttonSkin = { texture = root .. 'Button.png', size = L.buttonFrame },
				statusBars = StatusBars(name, root),
				slidingTrays = {
					left = { enabled = true, collapsed = false },
					right = { enabled = true, collapsed = false },
				},
				unitframes = {
					artwork = {
						full = {
							perUnit = true,
							UnitFrameCallback = Painted.UnitFrameCallback,
							player = Plate(root, false),
							target = Plate(root, true),
						},
						bottom = {
							perUnit = true,
							player = Mount(root, false),
							target = Mount(root, true),
						},
					},
					positions = {
						player = 'CENTER,' .. SocketName(name, 'player') .. ',CENTER,0,0',
						target = 'CENTER,' .. SocketName(name, 'target') .. ',CENTER,0,0',
						-- Pet and target of target sit outside the plates, past the portrait rings
						pet = 'BOTTOMRIGHT,SUI_UF_player,BOTTOMLEFT,' .. -Painted.PastPortrait() .. ',' .. -Painted.PlateBelow(),
						targettarget = 'BOTTOMLEFT,SUI_UF_target,BOTTOMRIGHT,' .. Painted.PastPortrait() .. ',' .. -Painted.PlateBelow(),
					},
					displayName = spec.displayName,
					setup = { image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_' .. name },
				},
			}
		end)

		if SUI.Artwork then
			Painted.CreateArtwork(name, root)
			Painted.ApplyVariant(name, root)
		end
		VariantOptions(name, spec.displayName)
	end

	function module:OnEnable()
		if SUI:GetActiveStyle() ~= name then
			module:Disable()
			return
		end
		Painted.active = name
		local art = _G['SUI_Art_' .. name]
		art:Show()
		-- The look registers its data when its module starts, after the status bars and minimap have
		-- already been placed from defaults at login: load it and have them place themselves again
		SUI.ThemeRegistry:GetData(name)
		local statusBars = SUI:GetModule('Artwork.StatusBars', true)
		if statusBars and statusBars.SetActiveStyle and statusBars.bars and next(statusBars.bars) then
			statusBars:SetActiveStyle(name)
		end
		local minimap = SUI:GetModule('Minimap', true)
		if minimap and minimap.SetActiveStyle and not InCombatLockdown() then
			minimap:SetActiveStyle(name)
		end
		local minimapModule = SUI:GetModule('Minimap', true)
		if minimapModule and not Painted.minimapHooked then
			Painted.minimapHooked = true
			for _, method in ipairs({ 'UpdatePosition', 'UpdateMinimapSize' }) do
				if minimapModule[method] then
					hooksecurefunc(minimapModule, method, function()
						if Painted.active then
							Painted.QueueAlignMinimap(Painted.active)
						end
					end)
				end
			end
		end
		Painted.ApplyVariant(name, root)
		-- Sizes settle a moment after login; frames built before the look turned on get their
		-- portrait and bars seated then too
		C_Timer.After(1, function()
			Painted.AlignMinimap(name)
			for _, unit in ipairs({ 'player', 'target' }) do
				local frame = SUI.UF and SUI.UF.Unit and SUI.UF.Unit:Get(unit)
				if frame and frame.Portrait2D then
					Painted.UnitFrameCallback(frame, unit)
				end
			end
		end)
		if SUI.Artwork then
			SUI.Artwork:SlidingTrays()
			SUI.Artwork:RegisterSkinTrayFrames(name, {
				left = 'BT4BarPetBar,BT4BarStanceBar,MultiCastActionBarFrame',
				right = 'BT4BarMicroMenu,BT4BarBagBar',
			})
			local BarSystem = SUI.Handlers.BarSystem
			BarSystem:PositionBar('BT4BarPetBar', 'TOPLEFT', 'SlidingTray_left', 'TOPLEFT', 50, -2)
			BarSystem:PositionBar('BT4BarStanceBar', 'TOPRIGHT', 'SlidingTray_left', 'TOPRIGHT', -50, -2)
			BarSystem:PositionBar('BT4BarMicroMenu', 'TOPLEFT', 'SlidingTray_right', 'TOPLEFT', 50, -2)
			BarSystem:PositionBar('BT4BarBagBar', 'TOPRIGHT', 'SlidingTray_right', 'TOPRIGHT', -100, -2)
		end
		module:SetupVehicleUI()
	end

	function module:OnDisable()
		if Painted.active == name then
			Painted.active = nil
			-- Other looks draw square portraits
			for _, unit in ipairs({ 'player', 'target' }) do
				local frame = _G['SUI_UF_' .. unit]
				if frame and frame.PaintedPortraitMask and frame.Portrait2D then
					frame.Portrait2D:RemoveMaskTexture(frame.PaintedPortraitMask)
					frame.PaintedPortraitMask = nil
					frame.PaintedPortraitHooked = nil
				end
			end
		end
		local art = _G['SUI_Art_' .. name]
		art:Hide()
		UnregisterStateDriver(art, 'visibility')
	end

	function module:TooltipLoc(tooltip, parent)
		if parent == 'UIParent' then
			tooltip:ClearAllPoints()
			tooltip:SetPoint('BOTTOMRIGHT', 'SUI_Art_' .. name, 'TOPRIGHT', 0, 10)
		end
	end

	function module:SetupVehicleUI()
		if SUI:GetArtworkSetting('VehicleUI') then
			RegisterStateDriver(_G['SUI_Art_' .. name], 'visibility', '[overridebar][vehicleui] hide; show')
		end
	end

	function module:RemoveVehicleUI()
		if SUI:GetArtworkSetting('VehicleUI') then
			UnregisterStateDriver(_G['SUI_Art_' .. name], 'visibility')
		end
	end

	return module
end

return Painted
