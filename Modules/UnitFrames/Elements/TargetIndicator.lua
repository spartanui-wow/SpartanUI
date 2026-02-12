local UF = SUI.UF

-- ============================================================================
-- Texture Registry: Add new textures here
-- ============================================================================
---@class TargetIndicator.TextureInfo
---@field type 'file'|'atlas'
---@field path? string File path for texture
---@field atlas? string Atlas name
---@field name string Display name
---@field defaultSize {width: number, height: number}
---@field placements string[] Supported placements

---@type table<string, TargetIndicator.TextureInfo>
local TextureRegistry = {
	-- File-based textures
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

	-- Atlas-based textures
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

---Apply texture to a texture frame
---@param textureFrame Texture
---@param textureKey string
local function ApplyTexture(textureFrame, textureKey)
	local texInfo = TextureRegistry[textureKey]
	if not texInfo then
		return
	end

	if texInfo.type == 'atlas' then
		textureFrame:SetAtlas(texInfo.atlas, false)
	else
		textureFrame:SetTexture(texInfo.path)
	end
end

-- ============================================================================
-- Display Creation Functions
-- ============================================================================

---Create a single texture indicator
---@param parent Frame
---@param position string 'LEFT'|'RIGHT'|'TOP'|'BOTTOM'|'CENTER'
---@param texInfo TargetIndicator.TextureInfo
---@param DB table
---@return Texture
local function CreateTexture(parent, position, texInfo, DB)
	local tex = parent:CreateTexture(nil, 'OVERLAY')
	ApplyTexture(tex, DB.texture.textureKey)

	-- Position based on placement
	local width = texInfo.defaultSize.width * DB.texture.scale
	local height = texInfo.defaultSize.height * DB.texture.scale
	tex:SetSize(width, height)

	if position == 'LEFT' then
		tex:SetPoint('RIGHT', parent, 'LEFT', 0, 0)
	elseif position == 'RIGHT' then
		tex:SetPoint('LEFT', parent, 'RIGHT', 0, 0)
		tex:SetTexCoord(1, 0, 1, 0) -- Mirror
	elseif position == 'TOP' then
		tex:SetPoint('BOTTOM', parent, 'TOP', 0, 0)
	elseif position == 'BOTTOM' then
		tex:SetPoint('TOP', parent, 'BOTTOM', 0, 0)
	elseif position == 'CENTER' then
		tex:SetAllPoints(parent)
	end

	-- Apply color tint
	tex:SetVertexColor(unpack(DB.texture.color))
	tex:SetAlpha(DB.texture.alpha)
	tex:Hide()

	return tex
end

---Clean up all texture objects
---@param element Frame
local function CleanupTextures(element)
	if element.textureObjects then
		for _, tex in pairs(element.textureObjects) do
			tex:Hide()
			tex:SetParent(nil)
		end
		element.textureObjects = {}
	end
end

---Clean up border instance
---@param element Frame
local function CleanupBorder(element)
	if element.borderInstanceId then
		SUI.Handlers.BackgroundBorder:Destroy(element.borderInstanceId)
		element.borderInstance = nil
		element.borderInstanceId = nil
	end
end

---Create texture display based on placement setting
---@param element Frame
---@param DB table
local function CreateTextureDisplay(element, DB)
	local texInfo = TextureRegistry[DB.texture.textureKey]
	if not texInfo then
		return
	end

	local placement = DB.texture.placement

	if placement == 'sides' then
		-- Create left and right textures (like current nameplate implementation)
		element.textureObjects.left = CreateTexture(element, 'LEFT', texInfo, DB)
		element.textureObjects.right = CreateTexture(element, 'RIGHT', texInfo, DB)
	elseif placement == 'top' then
		element.textureObjects.top = CreateTexture(element, 'TOP', texInfo, DB)
	elseif placement == 'bottom' then
		element.textureObjects.bottom = CreateTexture(element, 'BOTTOM', texInfo, DB)
	elseif placement == 'center' then
		element.textureObjects.center = CreateTexture(element, 'CENTER', texInfo, DB)
	elseif placement == 'all' then
		-- Create textures on all four sides
		element.textureObjects.top = CreateTexture(element, 'TOP', texInfo, DB)
		element.textureObjects.bottom = CreateTexture(element, 'BOTTOM', texInfo, DB)
		element.textureObjects.left = CreateTexture(element, 'LEFT', texInfo, DB)
		element.textureObjects.right = CreateTexture(element, 'RIGHT', texInfo, DB)
	end
end

---Create border display using BackgroundBorder handler
---@param element Frame
---@param DB table
local function CreateBorderDisplay(element, DB)
	local frame = element:GetParent()
	local borderSettings = {
		enabled = true,
		displayLevel = DB.border.displayLevel,
		background = { enabled = false },
		border = {
			enabled = true,
			size = DB.border.size,
			sides = DB.border.sides,
			colors = {
				top = DB.border.color,
				bottom = DB.border.color,
				left = DB.border.color,
				right = DB.border.color,
			},
			classColors = { top = false, bottom = false, left = false, right = false },
		},
	}

	local id = 'TargetIndicator_' .. frame:GetName()
	element.borderInstance = SUI.Handlers.BackgroundBorder:Create(frame, id, borderSettings)
	element.borderInstanceId = id

	-- Force-set enabled=true on the instance since MergeData doesn't override existing false values
	local instance = SUI.Handlers.BackgroundBorder.instances[id]
	if instance then
		instance.settings.enabled = true
		instance.settings.border.enabled = true
		instance.settings.background.enabled = false -- We don't want background
		instance.visible = false -- Start hidden until target is selected
	end

	-- Update to apply the corrected settings (starts hidden because visible=false)
	SUI.Handlers.BackgroundBorder:Update(id)
end

---Rebuild display based on current mode settings
---@param element Frame
---@param DB table
local function RebuildDisplay(element, DB)
	-- Clean up existing displays
	CleanupTextures(element)
	CleanupBorder(element)

	if DB.mode == 'texture' or DB.mode == 'both' then
		CreateTextureDisplay(element, DB)
	end

	if DB.mode == 'border' or DB.mode == 'both' then
		CreateBorderDisplay(element, DB)
	end
end

-- ============================================================================
-- Core Element Functions
-- ============================================================================

---Build the TargetIndicator element
---@param frame table
---@param DB? table
local function Build(frame, DB)
	-- Create container frame
	local element = CreateFrame('Frame', 'TargetIndicator_' .. frame:GetName(), frame)
	element:SetAllPoints(frame)
	element.DB = DB

	-- Initialize display systems
	element.textureObjects = {}
	element.borderInstance = nil
	element.borderInstanceId = nil

	-- Store frame reference
	frame.TargetIndicator = element

	-- Create initial display based on mode
	if DB then
		RebuildDisplay(element, DB)
	end
end

---Update the TargetIndicator element
---@param frame table
---@param settings? table
local function Update(frame, settings)
	local element = frame.TargetIndicator
	if not element then
		return
	end

	local DB = settings or element.DB
	element.DB = DB -- Store for future reference

	-- Check if we're the target
	local isTarget = UnitIsUnit(frame.unit, 'target') and DB.enabled and DB.ShowTarget

	-- Update texture display
	if DB.mode == 'texture' or DB.mode == 'both' then
		for _, tex in pairs(element.textureObjects) do
			if isTarget then
				tex:Show()
			else
				tex:Hide()
			end
		end
	end

	-- Update border display
	if DB.mode == 'border' or DB.mode == 'both' then
		if element.borderInstanceId then
			SUI.Handlers.BackgroundBorder:SetVisible(element.borderInstanceId, isTarget)
		end
	end
end

-- ============================================================================
-- Options Configuration
-- ============================================================================

---Generate options table for this element
---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	local function OptUpdate(option, val, subTable)
		if subTable then
			UF.CurrentSettings[unitName].elements.TargetIndicator[subTable][option] = val
			UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.TargetIndicator[subTable][option] = val
		else
			UF.CurrentSettings[unitName].elements.TargetIndicator[option] = val
			UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.TargetIndicator[option] = val
		end
		UF.Unit[unitName]:ElementUpdate('TargetIndicator')
	end

	-- Generate texture dropdown values from registry
	local textureValues = {}
	for key, texInfo in pairs(TextureRegistry) do
		textureValues[key] = texInfo.name
	end

	OptionSet.args.mode = {
		type = 'select',
		name = 'Display Mode',
		order = 1,
		values = {
			border = 'Border',
			texture = 'Texture',
			both = 'Border + Texture',
		},
		get = function()
			return UF.CurrentSettings[unitName].elements.TargetIndicator.mode
		end,
		set = function(_, val)
			OptUpdate('mode', val)
			-- Rebuild display when mode changes
			for _, frame in pairs(UF.Unit:GetFrames(unitName)) do
				if frame.TargetIndicator then
					RebuildDisplay(frame.TargetIndicator, UF.CurrentSettings[unitName].elements.TargetIndicator)
				end
			end
		end,
	}

	-- Texture settings group
	OptionSet.args.textureSettings = {
		type = 'group',
		name = 'Texture Settings',
		inline = true,
		order = 10,
		disabled = function()
			local mode = UF.CurrentSettings[unitName].elements.TargetIndicator.mode
			return mode == 'border'
		end,
		args = {
			textureKey = {
				type = 'select',
				name = 'Texture',
				order = 1,
				values = textureValues,
				get = function()
					return UF.CurrentSettings[unitName].elements.TargetIndicator.texture.textureKey
				end,
				set = function(_, val)
					OptUpdate('textureKey', val, 'texture')
					-- Rebuild display when texture changes
					for _, frame in pairs(UF.Unit:GetFrames(unitName)) do
						if frame.TargetIndicator then
							RebuildDisplay(frame.TargetIndicator, UF.CurrentSettings[unitName].elements.TargetIndicator)
						end
					end
				end,
			},
			placement = {
				type = 'select',
				name = 'Placement',
				order = 2,
				values = function()
					local key = UF.CurrentSettings[unitName].elements.TargetIndicator.texture.textureKey
					local texInfo = TextureRegistry[key]
					if not texInfo then
						return {}
					end

					local vals = {}
					for _, placement in ipairs(texInfo.placements) do
						vals[placement] = placement:gsub('^%l', string.upper)
					end
					return vals
				end,
				get = function()
					return UF.CurrentSettings[unitName].elements.TargetIndicator.texture.placement
				end,
				set = function(_, val)
					OptUpdate('placement', val, 'texture')
					-- Rebuild display when placement changes
					for _, frame in pairs(UF.Unit:GetFrames(unitName)) do
						if frame.TargetIndicator then
							RebuildDisplay(frame.TargetIndicator, UF.CurrentSettings[unitName].elements.TargetIndicator)
						end
					end
				end,
			},
			scale = {
				type = 'range',
				name = 'Scale',
				order = 3,
				min = 0.5,
				max = 3.0,
				step = 0.1,
				get = function()
					return UF.CurrentSettings[unitName].elements.TargetIndicator.texture.scale
				end,
				set = function(_, val)
					OptUpdate('scale', val, 'texture')
					-- Rebuild display when scale changes
					for _, frame in pairs(UF.Unit:GetFrames(unitName)) do
						if frame.TargetIndicator then
							RebuildDisplay(frame.TargetIndicator, UF.CurrentSettings[unitName].elements.TargetIndicator)
						end
					end
				end,
			},
			color = {
				type = 'color',
				name = 'Color',
				order = 4,
				hasAlpha = true,
				get = function()
					local c = UF.CurrentSettings[unitName].elements.TargetIndicator.texture.color
					return c[1], c[2], c[3], c[4]
				end,
				set = function(_, r, g, b, a)
					OptUpdate('color', { r, g, b, a }, 'texture')
				end,
			},
		},
	}

	-- Border settings group
	OptionSet.args.borderSettings = {
		type = 'group',
		name = 'Border Settings',
		inline = true,
		order = 20,
		disabled = function()
			local mode = UF.CurrentSettings[unitName].elements.TargetIndicator.mode
			return mode == 'texture'
		end,
		args = {
			size = {
				type = 'range',
				name = 'Border Size',
				order = 1,
				min = 1,
				max = 10,
				step = 1,
				get = function()
					return UF.CurrentSettings[unitName].elements.TargetIndicator.border.size
				end,
				set = function(_, val)
					OptUpdate('size', val, 'border')
					-- Update border when size changes
					for _, frame in pairs(UF.Unit:GetFrames(unitName)) do
						if frame.TargetIndicator and frame.TargetIndicator.borderInstance then
							SUI.Handlers.BackgroundBorder:Update('TargetIndicator_' .. frame:GetName(), {
								border = { size = val },
							})
						end
					end
				end,
			},
			color = {
				type = 'color',
				name = 'Border Color',
				order = 2,
				hasAlpha = true,
				get = function()
					local c = UF.CurrentSettings[unitName].elements.TargetIndicator.border.color
					return c[1], c[2], c[3], c[4]
				end,
				set = function(_, r, g, b, a)
					local color = { r, g, b, a }
					OptUpdate('color', color, 'border')
					-- Update border when color changes
					for _, frame in pairs(UF.Unit:GetFrames(unitName)) do
						if frame.TargetIndicator and frame.TargetIndicator.borderInstance then
							SUI.Handlers.BackgroundBorder:Update('TargetIndicator_' .. frame:GetName(), {
								border = {
									colors = {
										top = color,
										bottom = color,
										left = color,
										right = color,
									},
								},
							})
						end
					end
				end,
			},
			sides = {
				type = 'multiselect',
				name = 'Border Sides',
				order = 3,
				values = {
					top = 'Top',
					bottom = 'Bottom',
					left = 'Left',
					right = 'Right',
				},
				get = function(_, key)
					return UF.CurrentSettings[unitName].elements.TargetIndicator.border.sides[key]
				end,
				set = function(_, key, val)
					local sides = UF.CurrentSettings[unitName].elements.TargetIndicator.border.sides
					sides[key] = val
					OptUpdate('sides', sides, 'border')
					-- Update border when sides change
					for _, frame in pairs(UF.Unit:GetFrames(unitName)) do
						if frame.TargetIndicator and frame.TargetIndicator.borderInstance then
							SUI.Handlers.BackgroundBorder:Update('TargetIndicator_' .. frame:GetName(), { border = { sides = sides } })
						end
					end
				end,
			},
		},
	}
end

-- ============================================================================
-- Element Registration
-- ============================================================================

local Settings = {
	enabled = true,
	ShowTarget = true,
	ShowFocus = false,
	ShowMouseover = false,
	mode = 'texture', -- 'border', 'texture', 'both'

	-- State-specific colors
	targetColor = { 1, 1, 0, 1 }, -- Yellow for target
	focusColor = { 1, 0.5, 0, 0.8 }, -- Orange for focus
	mouseoverColor = { 1, 1, 1, 0.5 }, -- White for mouseover

	-- Texture mode settings
	texture = {
		textureKey = 'DoubleArrow', -- Key from TextureRegistry
		placement = 'sides', -- 'sides', 'top', 'bottom', 'center', 'all'
		scale = 1.0,
		color = { 1, 1, 1, 1 }, -- Tint color (used as default if no state-specific color)
		alpha = 1.0,
	},

	-- Border mode settings
	border = {
		size = 2,
		color = { 1, 1, 0, 1 }, -- Yellow default
		sides = { top = true, bottom = true, left = true, right = true },
		displayLevel = 5, -- Frame level above frame
	},

	config = {
		type = 'Indicator',
		DisplayName = 'Target Indicator',
		NoBulkUpdate = false,
	},
}

UF.Elements:Register('TargetIndicator', Build, Update, Options, Settings)
