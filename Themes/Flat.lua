local SUI = SUI

-- Building blocks for the flat, art-free themes (Modern Flat, Healer Grid, Classic Dark).
-- Each helper returns a fresh table, so a theme can adjust one frame without touching another.

---@class SUI.ThemeFlat
local Flat = {}
SUI.ThemeFlat = Flat

local BLACK = { 0, 0, 0, 1 }

---Background fill and a 1px border around the whole frame
---@param color number[] background { r, g, b, a }
---@param borderColor? number[] defaults to black
---@return table
function Flat.Background(color, borderColor)
	local bc = borderColor or BLACK
	return {
		enabled = true,
		displayLevel = -5,
		background = {
			enabled = true,
			type = 'color',
			color = { color[1], color[2], color[3], color[4] or 1 },
			alpha = color[4] or 1,
			classColor = false,
		},
		border = {
			enabled = true,
			size = 1,
			sides = { top = true, bottom = true, left = true, right = true },
			colors = { top = bc, bottom = bc, left = bc, right = bc },
			classColors = { top = false, bottom = false, left = false, right = false },
		},
	}
end

---A class-colored health bar filling the top of the frame
---@param height number
---@param opts? { texture?: string, bg?: number[], absorb?: string, texts?: table }
---@return table
function Flat.Health(height, opts)
	opts = opts or {}
	return {
		height = height,
		texture = opts.texture or 'SpartanUI Flat',
		colorClass = true,
		colorReaction = true,
		colorSmooth = false,
		bg = { enabled = true, color = opts.bg or { 0, 0, 0, 0.5 }, useClassColor = false },
		absorbTexture = opts.absorb or 'SpartanUI Stripes Cyan',
		position = { anchor = 'TOP', relativeTo = 'Frame', relativePoint = 'TOP', x = 0, y = 0 },
		text = opts.texts or {
			['1'] = {
				enabled = true,
				text = '[SUIHealth(dynamic,displayDead)]',
				size = 11,
				position = { anchor = 'BOTTOMLEFT', x = 4, y = 3 },
			},
			['2'] = {
				enabled = true,
				text = '[perhp]%',
				size = 11,
				position = { anchor = 'BOTTOMRIGHT', x = -4, y = 3 },
			},
		},
	}
end

---A thin power bar directly under the health bar
---@param height number
---@param texture? string
---@return table
function Flat.Power(height, texture)
	return {
		enabled = height > 0,
		height = height,
		texture = texture or 'SpartanUI Flat',
		bg = { enabled = true, color = { 0, 0, 0, 0.6 }, useClassColor = false },
		position = { anchor = 'TOP', relativeTo = 'Health', relativePoint = 'BOTTOM', x = 0, y = 0 },
		text = {
			['1'] = { enabled = false },
			['2'] = { enabled = false },
		},
	}
end

---Name drawn inside the health bar
---@param size number
---@param anchor? AnchorPoint defaults to TOPLEFT
---@return table
function Flat.Name(size, anchor)
	anchor = anchor or 'TOPLEFT'
	local x = anchor:find('LEFT') and 4 or anchor:find('RIGHT') and -4 or 0
	local justify = anchor:find('LEFT') and 'LEFT' or anchor:find('RIGHT') and 'RIGHT' or 'CENTER'
	return {
		enabled = true,
		textSize = size,
		height = size + 2,
		text = '[name]',
		SetJustifyH = justify,
		position = { anchor = anchor, relativeTo = 'Health', relativePoint = anchor, x = x, y = -3 },
	}
end

---Cast bar along the bottom edge of the frame, under the power bar. Anchored to the frame
---rather than the power bar, so no layout can chain it back to itself.
---@param height number
---@param texture? string
---@return table
function Flat.Castbar(height, texture)
	return {
		enabled = height > 0,
		height = height,
		texture = texture or 'SpartanUI Flat',
		position = { anchor = 'BOTTOM', relativeTo = 'Frame', relativePoint = 'BOTTOM', x = 0, y = 0 },
		Icon = { enabled = false },
	}
end

---Elements every flat frame turns off (the art pieces the flat look replaces)
---@param elements table
---@return table elements
function Flat.StripArt(elements)
	elements.Portrait = { enabled = false }
	elements.SpartanArt = { enabled = false }
	elements.ClassIcon = { enabled = false }
	return elements
end

---A complete flat single-unit frame
---@param spec { width: number, health: number, power: number, cast?: number, bg: number[], border?: number[], texture?: string, name?: number, nameAnchor?: AnchorPoint, absorb?: string, texts?: table }
---@return table frameConfig
function Flat.Frame(spec)
	local elements = Flat.StripArt({
		FrameBackground = Flat.Background(spec.bg, spec.border),
		Health = Flat.Health(spec.health, { texture = spec.texture, absorb = spec.absorb, texts = spec.texts }),
		Power = Flat.Power(spec.power, spec.texture),
		Castbar = Flat.Castbar(spec.cast or 0, spec.texture),
		Name = Flat.Name(spec.name or 12, spec.nameAnchor),
	})
	return { width = spec.width, elements = elements }
end

---Buff and debuff rows for a single-unit frame
---@param elements table frame elements to add to
---@param buffs? { number: number, size: number, anchor: AnchorPoint, relativePoint: AnchorPoint, growthx: string, growthy: string, y: number, filter?: string }
---@param debuffs? { number: number, size: number, anchor: AnchorPoint, relativePoint: AnchorPoint, growthx: string, growthy: string, y: number, filter?: string }
function Flat.Auras(elements, buffs, debuffs)
	local function Row(def)
		if not def then
			return { enabled = false }
		end
		return {
			enabled = true,
			number = def.number,
			size = def.size,
			rows = def.rows or 1,
			spacing = 2,
			growthx = def.growthx,
			growthy = def.growthy,
			position = { anchor = def.anchor, relativePoint = def.relativePoint, x = 0, y = def.y },
			retail = def.filter and { filterMode = def.filter } or nil,
		}
	end
	elements.Buffs = Row(buffs)
	elements.Debuffs = Row(debuffs)
end

---Minimap settings for the art-free themes: a plain square in the top right corner
---@param size number
---@return table
function Flat.Minimap(size)
	if SUI.BlizzAPI.HasModernMinimap() then
		return {
			UnderVehicleUI = false,
			scaleWithArt = false,
			position = 'TOPRIGHT,UIParent,TOPRIGHT,-12,-12',
			shape = 'square',
			size = { size, size },
			elements = {
				background = { enabled = false },
			},
		}
	end
	return {
		UnderVehicleUI = false,
		scaleWithArt = false,
		position = 'TOPRIGHT,UIParent,TOPRIGHT,-12,-12',
		shape = 'square',
		size = { size, size },
		background = { enabled = false },
	}
end

---Action bars in three centered rows with two side blocks, the layout the flat themes share
---@param rowY? number bottom of the first row
---@return table positions, table scales
function Flat.BarLayout(rowY)
	local y = rowY or 4
	local positions = {
		['BT4Bar1'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,0,' .. y,
		['BT4Bar2'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,0,' .. (y + 40),
		['BT4Bar3'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,0,' .. (y + 80),
		['BT4Bar4'] = 'BOTTOMRIGHT,SUI_BottomAnchor,BOTTOM,-240,' .. y,
		['BT4Bar5'] = 'BOTTOMLEFT,SUI_BottomAnchor,BOTTOM,240,' .. y,
		['BT4Bar6'] = 'BOTTOMRIGHT,SUI_BottomAnchor,BOTTOM,-240,' .. (y + 40),
		['BT4BarPetBar'] = 'BOTTOMLEFT,SUI_BottomAnchor,BOTTOM,-225,' .. (y + 122),
		['BT4BarStanceBar'] = 'BOTTOMRIGHT,SUI_BottomAnchor,BOTTOM,225,' .. (y + 122),
		['MultiCastActionBarFrame'] = 'BOTTOMLEFT,SUI_BottomAnchor,BOTTOM,-225,' .. (y + 122),
		['BT4BarExtraActionBar'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,0,' .. (y + 170),
		['BT4BarZoneAbilityBar'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,0,' .. (y + 170),
		['BT4BarMicroMenu'] = 'BOTTOMRIGHT,UIParent,BOTTOMRIGHT,-6,6',
		['BT4BarBagBar'] = 'BOTTOMRIGHT,UIParent,BOTTOMRIGHT,-6,40',
	}
	local scales = {
		['BT4Bar1'] = 0.8,
		['BT4Bar2'] = 0.8,
		['BT4Bar3'] = 0.8,
		['BT4Bar4'] = 0.8,
		['BT4Bar5'] = 0.8,
		['BT4Bar6'] = 0.8,
		['BT4Bar7'] = 0.8,
		['BT4Bar8'] = 0.8,
		['BT4Bar9'] = 0.8,
		['BT4Bar10'] = 0.8,
		['BT4BarPetBar'] = 0.7,
		['BT4BarStanceBar'] = 0.7,
		['MultiCastActionBarFrame'] = 0.7,
		['BT4BarExtraActionBar'] = 0.8,
		['BT4BarMicroMenu'] = 0.65,
		['BT4BarBagBar'] = 0.65,
	}
	return positions, scales
end

---Group frames laid out as a grid of equal cells
---@param spec { width: number, health: number, power: number, perRow: number, rows: number, spacing: number, growth: string, bg: number[], nameSize: number, texture?: string }
---@return table frameConfig
function Flat.Group(spec)
	local frame = Flat.Frame({
		width = spec.width,
		health = spec.health,
		power = spec.power,
		bg = spec.bg,
		texture = spec.texture,
		name = spec.nameSize,
		nameAnchor = 'TOP',
		texts = {
			['1'] = {
				enabled = true,
				text = '[SUIHealthDeficit]',
				size = spec.nameSize,
				position = { anchor = 'CENTER', x = 0, y = -4 },
			},
			['2'] = { enabled = false },
		},
	})
	frame.growthDirection = spec.growth
	frame.unitsPerColumn = spec.perRow
	frame.maxColumns = spec.rows
	frame.xOffset = spec.spacing
	frame.yOffset = -spec.spacing
	frame.columnSpacing = spec.spacing
	return frame
end

---Lib's DataBar look and spot for the flat themes: a slim strip across the top middle
---@param bg number[] bar background { r, g, b, a }
---@return table
function Flat.DataBars(bg)
	return {
		look = {
			font = { size = 11 },
			bar = {
				background = { show = true, color = { bg[1], bg[2], bg[3], bg[4] or 0.9 } },
				border = { show = true, color = { 0, 0, 0, 1 }, size = 1 },
			},
		},
		bars = {
			main = { position = 'TOP,UIParent,TOP,0,0', width = 700, height = 22 },
		},
	}
end
