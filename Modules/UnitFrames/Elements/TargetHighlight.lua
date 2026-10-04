local UF, L = SUI.UF, SUI.L

-- Highlights a frame while its unit is your target, focus or mouseover. Each of the three gets its
-- own layer (target drawn on top), faded in and out by the TargetHighlight oUF plugin.

-- ============================================================================
-- Texture Registry: Add new textures here
-- ============================================================================
---@class TargetHighlight.TextureInfo
---@field type 'file'|'atlas'
---@field path? string File path for texture
---@field atlas? string Atlas name
---@field name string Display name
---@field defaultSize {width: number, height: number}
---@field placements string[] Supported placements

---@type table<string, TargetHighlight.TextureInfo>
local TextureRegistry = {
	DoubleArrow = {
		type = 'file',
		path = 'Interface\\AddOns\\SpartanUI\\Images\\nameplates\\DoubleArrow',
		name = 'Double Arrows',
		defaultSize = { width = 10, height = 20 },
		placements = { 'sides', 'top', 'bottom' },
	},
	SingleArrow = {
		type = 'file',
		path = 'Interface\\AddOns\\SpartanUI\\Images\\nameplates\\SingleArrow',
		name = 'Single Arrow',
		defaultSize = { width = 8, height = 16 },
		placements = { 'sides', 'top', 'bottom' },
	},
	GarrNotificationGlow = {
		type = 'atlas',
		atlas = 'Garr_NotificationGlow',
		name = 'Garrison Glow',
		defaultSize = { width = 30, height = 30 },
		placements = { 'center', 'all' },
	},
	BossBanner = {
		type = 'atlas',
		atlas = 'BossBanner-BgBanner-Top',
		name = 'Boss Banner',
		defaultSize = { width = 40, height = 20 },
		placements = { 'top', 'bottom' },
	},
	FullAlertGlow = {
		type = 'atlas',
		atlas = 'FullAlert-SoftCurveGlow',
		name = 'Alert Glow',
		defaultSize = { width = 30, height = 30 },
		placements = { 'sides', 'center' },
	},
}

-- Lowest first: when a unit is both your target and your focus, the target layer is on top
local STATES = { 'mouseover', 'focus', 'target' }

-- Texture positions each placement uses
local PLACEMENTS = {
	sides = { 'LEFT', 'RIGHT' },
	top = { 'TOP' },
	bottom = { 'BOTTOM' },
	center = { 'CENTER' },
	all = { 'TOP', 'BOTTOM', 'LEFT', 'RIGHT' },
}

local SIDES = { 'top', 'bottom', 'left', 'right' }
local WHITE = 'Interface\\Buttons\\WHITE8X8'

-- ============================================================================
-- Drawing
-- ============================================================================

---The color a state is drawn in: the target uses the texture and border colors, focus and
---mouseover use their own color for both
---@param DB table
---@param state string
---@param part 'texture'|'border'
---@return number[]
local function StateColor(DB, state, part)
	if state == 'target' then
		return DB[part].color
	end
	return DB[state .. 'Color'] or { 1, 1, 1, 1 }
end

---@param tex Texture
---@param position string
---@param parent Frame
local function PlaceTexture(tex, position, parent)
	tex:ClearAllPoints()
	tex:SetTexCoord(0, 1, 0, 1)
	if position == 'LEFT' then
		tex:SetPoint('RIGHT', parent, 'LEFT', 0, 0)
	elseif position == 'RIGHT' then
		tex:SetPoint('LEFT', parent, 'RIGHT', 0, 0)
		tex:SetTexCoord(1, 0, 1, 0)
	elseif position == 'TOP' then
		tex:SetPoint('BOTTOM', parent, 'TOP', 0, 0)
	elseif position == 'BOTTOM' then
		tex:SetPoint('TOP', parent, 'BOTTOM', 0, 0)
	else
		tex:SetAllPoints(parent)
	end
end

---Draw a layer's textures for the chosen texture and placement
---@param layer Frame
---@param DB table
---@param state string
local function PaintTextures(layer, DB, state)
	for _, tex in pairs(layer.textures) do
		tex:Hide()
	end
	local texInfo = TextureRegistry[DB.texture.textureKey]
	if not texInfo or not (DB.mode == 'texture' or DB.mode == 'both') then
		return
	end
	local color = StateColor(DB, state, 'texture')
	for _, position in ipairs(PLACEMENTS[DB.texture.placement] or PLACEMENTS.sides) do
		local tex = layer.textures[position]
		if not tex then
			tex = layer:CreateTexture(nil, 'OVERLAY')
			layer.textures[position] = tex
		end
		if texInfo.type == 'atlas' then
			tex:SetAtlas(texInfo.atlas, false)
		else
			tex:SetTexture(texInfo.path)
		end
		PlaceTexture(tex, position, layer)
		tex:SetSize(texInfo.defaultSize.width * DB.texture.scale, texInfo.defaultSize.height * DB.texture.scale)
		tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
		tex:SetAlpha(DB.texture.alpha or 1)
		tex:Show()
	end
end

---Draw a layer's border just outside the frame
---@param layer Frame
---@param DB table
---@param state string
local function PaintBorder(layer, DB, state)
	local show = DB.mode == 'border' or DB.mode == 'both'
	local size = DB.border.size or 2
	local color = StateColor(DB, state, 'border')
	for _, side in ipairs(SIDES) do
		local edge = layer.border[side]
		if not edge then
			edge = layer:CreateTexture(nil, 'BORDER')
			edge:SetTexture(WHITE)
			layer.border[side] = edge
		end
		if show and DB.border.sides[side] then
			edge:ClearAllPoints()
			if side == 'top' then
				edge:SetPoint('BOTTOMLEFT', layer, 'TOPLEFT', -size, 0)
				edge:SetPoint('BOTTOMRIGHT', layer, 'TOPRIGHT', size, 0)
				edge:SetHeight(size)
			elseif side == 'bottom' then
				edge:SetPoint('TOPLEFT', layer, 'BOTTOMLEFT', -size, 0)
				edge:SetPoint('TOPRIGHT', layer, 'BOTTOMRIGHT', size, 0)
				edge:SetHeight(size)
			elseif side == 'left' then
				edge:SetPoint('TOPRIGHT', layer, 'TOPLEFT', 0, 0)
				edge:SetPoint('BOTTOMRIGHT', layer, 'BOTTOMLEFT', 0, 0)
				edge:SetWidth(size)
			else
				edge:SetPoint('TOPLEFT', layer, 'TOPRIGHT', 0, 0)
				edge:SetPoint('BOTTOMLEFT', layer, 'BOTTOMRIGHT', 0, 0)
				edge:SetWidth(size)
			end
			edge:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
			edge:Show()
		else
			edge:Hide()
		end
	end
end

---Draw every layer and decide which states to watch
---@param element Frame
---@param DB table
local function Paint(element, DB)
	element.DB = DB
	for state, layer in pairs(element.layers) do
		PaintTextures(layer, DB, state)
		PaintBorder(layer, DB, state)
	end
	element.watch = {
		target = DB.enabled and DB.ShowTarget and true or false,
		focus = DB.enabled and DB.ShowFocus and true or false,
		mouseover = DB.enabled and DB.ShowMouseover and true or false,
	}
end

-- ============================================================================
-- Core Element Functions
-- ============================================================================

---@param frame table
---@param DB? table
local function Build(frame, DB)
	-- Parented to the raised layer so it sits above dispel and role icons
	local parent = frame.raised or frame
	local element = CreateFrame('Frame', nil, parent)
	element:SetAllPoints(frame)
	element:SetFrameLevel(parent:GetFrameLevel() + 20)
	element.layers = {}
	for i, state in ipairs(STATES) do
		local layer = CreateFrame('Frame', nil, element)
		layer:SetAllPoints(element)
		layer:SetFrameLevel(element:GetFrameLevel() + i)
		layer:SetAlpha(0)
		layer.textures = {}
		layer.border = {}
		element.layers[state] = layer
	end
	frame.TargetHighlight = element
	-- Nameplates build without a later update, so draw now
	if DB and DB.texture and DB.border then
		Paint(element, DB)
	end
end

---@param frame table
---@param settings? table
local function Update(frame, settings)
	local element = frame.TargetHighlight
	if not element then
		return
	end
	local DB = settings or element.DB
	if not DB or not DB.texture or not DB.border then
		return
	end
	element:ClearAllPoints()
	element:SetAllPoints(frame)
	Paint(element, DB)

	-- The options preview shows how it looks on the first sample frame
	if frame.isPreview then
		for state, layer in pairs(element.layers) do
			layer:SetAlpha((state == 'target' and element.watch.target and (frame.previewIndex or 1) % 100 == 1) and 1 or 0)
		end
		return
	end

	if element.__owner and element.ForceUpdate then
		element:ForceUpdate()
	end
end

-- ============================================================================
-- Options Configuration
-- ============================================================================

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	local function Current()
		return UF.CurrentSettings[unitName].elements.TargetHighlight
	end
	local function OptUpdate(option, val, subTable)
		local user = UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.TargetHighlight
		if subTable then
			Current()[subTable][option] = val
			user[subTable][option] = val
		else
			Current()[option] = val
			user[option] = val
		end
		UF.Unit[unitName]:ElementUpdate('TargetHighlight')
	end
	local function ColorOption(name, order, read, write, disabled)
		return {
			type = 'color',
			name = name,
			order = order,
			hasAlpha = true,
			disabled = disabled,
			get = function()
				local c = read()
				return c[1], c[2], c[3], c[4]
			end,
			set = function(_, r, g, b, a)
				write({ r, g, b, a })
			end,
		}
	end

	local textureValues = {}
	for key, texInfo in pairs(TextureRegistry) do
		textureValues[key] = texInfo.name
	end

	OptionSet.args.showFor = {
		type = 'group',
		name = L['Highlight when the unit is'],
		inline = true,
		order = 0.5,
		args = {
			ShowTarget = {
				type = 'toggle',
				name = L['Your target'],
				order = 1,
				get = function()
					return Current().ShowTarget
				end,
				set = function(_, val)
					OptUpdate('ShowTarget', val)
				end,
			},
			ShowFocus = {
				type = 'toggle',
				name = L['Your focus'],
				order = 2,
				get = function()
					return Current().ShowFocus
				end,
				set = function(_, val)
					OptUpdate('ShowFocus', val)
				end,
			},
			focusColor = ColorOption(L['Focus color'], 3, function()
				return Current().focusColor
			end, function(color)
				OptUpdate('focusColor', color)
			end, function()
				return not Current().ShowFocus
			end),
			ShowMouseover = {
				type = 'toggle',
				name = L['Under your mouse'],
				order = 4,
				get = function()
					return Current().ShowMouseover
				end,
				set = function(_, val)
					OptUpdate('ShowMouseover', val)
				end,
			},
			mouseoverColor = ColorOption(L['Mouseover color'], 5, function()
				return Current().mouseoverColor
			end, function(color)
				OptUpdate('mouseoverColor', color)
			end, function()
				return not Current().ShowMouseover
			end),
		},
	}

	OptionSet.args.mode = {
		type = 'select',
		name = L['Display mode'],
		order = 1,
		values = {
			border = L['Border'],
			texture = L['Texture'],
			both = L['Border and texture'],
		},
		get = function()
			return Current().mode
		end,
		set = function(_, val)
			OptUpdate('mode', val)
		end,
	}

	OptionSet.args.textureSettings = {
		type = 'group',
		name = L['Texture settings'],
		inline = true,
		order = 10,
		disabled = function()
			return Current().mode == 'border'
		end,
		args = {
			textureKey = {
				type = 'select',
				name = L['Texture'],
				order = 1,
				values = textureValues,
				get = function()
					return Current().texture.textureKey
				end,
				set = function(_, val)
					OptUpdate('textureKey', val, 'texture')
					-- Keep a placement the new texture supports
					local texInfo = TextureRegistry[val]
					local placement = Current().texture.placement
					if texInfo and not tContains(texInfo.placements, placement) then
						OptUpdate('placement', texInfo.placements[1], 'texture')
					end
				end,
			},
			placement = {
				type = 'select',
				name = L['Placement'],
				order = 2,
				values = function()
					local texInfo = TextureRegistry[Current().texture.textureKey]
					local vals = {}
					for _, placement in ipairs(texInfo and texInfo.placements or {}) do
						vals[placement] = placement:gsub('^%l', string.upper)
					end
					return vals
				end,
				get = function()
					return Current().texture.placement
				end,
				set = function(_, val)
					OptUpdate('placement', val, 'texture')
				end,
			},
			scale = {
				type = 'range',
				name = L['Scale'],
				order = 3,
				min = 0.5,
				max = 3.0,
				step = 0.1,
				get = function()
					return Current().texture.scale
				end,
				set = function(_, val)
					OptUpdate('scale', val, 'texture')
				end,
			},
			color = ColorOption(L['Target color'], 4, function()
				return Current().texture.color
			end, function(color)
				OptUpdate('color', color, 'texture')
			end),
		},
	}

	OptionSet.args.borderSettings = {
		type = 'group',
		name = L['Border settings'],
		inline = true,
		order = 20,
		disabled = function()
			return Current().mode == 'texture'
		end,
		args = {
			size = {
				type = 'range',
				name = L['Border size'],
				order = 1,
				min = 1,
				max = 10,
				step = 1,
				get = function()
					return Current().border.size
				end,
				set = function(_, val)
					OptUpdate('size', val, 'border')
				end,
			},
			color = ColorOption(L['Target color'], 2, function()
				return Current().border.color
			end, function(color)
				OptUpdate('color', color, 'border')
			end),
			sides = {
				type = 'multiselect',
				name = L['Border sides'],
				order = 3,
				values = {
					top = L['Top'],
					bottom = L['Bottom'],
					left = L['Left'],
					right = L['Right'],
				},
				get = function(_, key)
					return Current().border.sides[key]
				end,
				set = function(_, key, val)
					local sides = Current().border.sides
					sides[key] = val
					OptUpdate('sides', sides, 'border')
				end,
			},
		},
	}
end

-- ============================================================================
-- Element Registration
-- ============================================================================

local Settings = {
	enabled = false,
	ShowTarget = true,
	ShowFocus = false,
	ShowMouseover = false,
	mode = 'texture', -- 'border', 'texture', 'both'
	focusColor = { 1, 0.5, 0, 0.8 },
	mouseoverColor = { 1, 1, 1, 0.5 },

	texture = {
		textureKey = 'DoubleArrow',
		placement = 'sides', -- 'sides', 'top', 'bottom', 'center', 'all'
		scale = 1.0,
		color = { 1, 1, 1, 1 }, -- Target color
		alpha = 1.0,
	},

	border = {
		size = 2,
		color = { 1, 1, 0, 1 }, -- Target color
		sides = { top = true, bottom = true, left = true, right = true },
	},

	config = {
		type = 'Indicator',
		DisplayName = 'Target highlight',
		-- Covers the whole frame; it places itself
		NoBulkUpdate = true,
	},
}

UF.Elements:Register('TargetHighlight', Build, Update, Options, Settings)
