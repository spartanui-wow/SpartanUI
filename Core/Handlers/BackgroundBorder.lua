---@class SUI.Handlers.BackgroundBorder
local Handler = SUI:NewModule('Handler.BackgroundBorder')

Handler.instances = {}

---@class SUI.BackgroundBorder.Settings
---@field enabled boolean
---@field displayLevel number Frame level relative to parent (negative = below, positive = above)
---@field background SUI.BackgroundBorder.Background
---@field border SUI.BackgroundBorder.Border

---@class SUI.BackgroundBorder.Background
---@field enabled boolean
---@field type 'color'|'texture' Background type
---@field color table {r, g, b, a} Background color
---@field texture string Texture path or LSM key
---@field alpha number Background alpha (0-1)
---@field classColor boolean Use player class color

---@class SUI.BackgroundBorder.Border
---@field enabled boolean
---@field sides table {top: boolean, bottom: boolean, left: boolean, right: boolean}
---@field size number Border thickness in pixels
---@field colors table {top: {r,g,b,a}, bottom: {r,g,b,a}, left: {r,g,b,a}, right: {r,g,b,a}}
---@field classColors table {top: boolean, bottom: boolean, left: boolean, right: boolean}

---Default settings for background & border
---@type SUI.BackgroundBorder.Settings
Handler.DefaultSettings = {
	enabled = false,
	displayLevel = 0,
	background = {
		enabled = true,
		type = 'color',
		color = { 0.1, 0.1, 0.1, 0.8 },
		texture = 'Interface\\Buttons\\WHITE8X8',
		alpha = 0.8,
		classColor = false,
	},
	border = {
		enabled = false,
		sides = { top = true, bottom = true, left = true, right = true },
		size = 1,
		colors = {
			top = { 1, 1, 1, 1 },
			bottom = { 1, 1, 1, 1 },
			left = { 1, 1, 1, 1 },
			right = { 1, 1, 1, 1 },
		},
		classColors = { top = false, bottom = false, left = false, right = false },
	},
}

---Create a new background & border instance
---@param parent Frame Parent frame to attach to
---@param id string Unique identifier for this instance
---@param settings? SUI.BackgroundBorder.Settings Configuration settings
---@return SUI.BackgroundBorder.Instance
function Handler:Create(parent, id, settings)
	if self.instances[id] then
		self:Destroy(id)
	end

	-- Deep copy DefaultSettings first, then merge passed settings into the copy
	-- Note: SUI:CopyData(dest, source) copies source into dest, so we need to pass {} as dest
	local defaults = SUI:CopyData({}, self.DefaultSettings)
	settings = SUI:MergeData(defaults, settings or {}, true)

	---@class SUI.BackgroundBorder.Instance
	local instance = {
		id = id,
		parent = parent,
		settings = settings,
		background = nil,
		borders = {},
		visible = true,
	}

	-- Create background frame on BACKGROUND strata so it renders behind health/power bars
	instance.background = CreateFrame('Frame', id .. '_Background', parent)
	instance.background:SetFrameStrata('BACKGROUND')
	instance.background:SetAllPoints(parent)

	-- Safely calculate frame level (clamp to valid range 0-65535)
	local baseLevel = parent:GetFrameLevel() or 0
	local displayLevel = settings.displayLevel or 0
	local bgLevel = math.max(0, math.min(65535, baseLevel + displayLevel))
	local borderLevel = math.max(0, math.min(65535, baseLevel + displayLevel + 1))

	instance.background:SetFrameLevel(bgLevel)

	-- Create background texture
	instance.background.texture = instance.background:CreateTexture(nil, 'BACKGROUND')
	instance.background.texture:SetAllPoints(instance.background)

	-- Create border frames for each side
	for _, side in ipairs({ 'top', 'bottom', 'left', 'right' }) do
		local border = CreateFrame('Frame', id .. '_Border_' .. side, parent)
		border:SetFrameStrata('BACKGROUND')
		border:SetFrameLevel(borderLevel)
		border.texture = border:CreateTexture(nil, 'BORDER')
		border.texture:SetAllPoints(border)
		border.texture:SetTexture('Interface\\Buttons\\WHITE8X8')
		instance.borders[side] = border
	end

	self.instances[id] = instance
	self:Update(id)

	return instance
end

---Update an existing background & border instance
---@param id string Instance identifier
---@param settings? SUI.BackgroundBorder.Settings New settings (will be merged)
function Handler:Update(id, settings)
	local instance = self.instances[id]
	if not instance then
		return
	end

	-- Merge new settings if provided
	if settings then
		instance.settings = SUI:MergeData(instance.settings, settings, true)
	end

	local config = instance.settings

	-- Safely calculate frame levels (clamp to valid range 0-65535)
	local baseLevel = instance.parent:GetFrameLevel() or 0
	local displayLevel = config.displayLevel or 0
	local bgLevel = math.max(0, math.min(65535, baseLevel + displayLevel))
	local borderLevel = math.max(0, math.min(65535, baseLevel + displayLevel + 1))

	-- Update frame levels
	instance.background:SetFrameLevel(bgLevel)
	for _, border in pairs(instance.borders) do
		border:SetFrameLevel(borderLevel)
	end

	-- Update visibility
	if config.enabled and instance.visible then
		instance.background:Show()
		self:UpdateBackground(id)
		self:UpdateBorders(id)
	else
		instance.background:Hide()
		for _, border in pairs(instance.borders) do
			border:Hide()
		end
	end
end

---Get the class color for an instance's parent unit (or fall back to player)
---@param instance SUI.BackgroundBorder.Instance
---@return table|nil color RAID_CLASS_COLORS entry
local function GetInstanceClassColor(instance)
	local unit = instance.parent and instance.parent.unit or 'player'
	if not UnitExists(unit) then
		unit = 'player'
	end
	local _, classToken = UnitClass(unit)
	if not classToken then
		return nil
	end
	return (_G.CUSTOM_CLASS_COLORS and _G.CUSTOM_CLASS_COLORS[classToken]) or _G.RAID_CLASS_COLORS[classToken]
end

---Update background appearance
---@param id string Instance identifier
function Handler:UpdateBackground(id)
	local instance = self.instances[id]
	if not instance then
		return
	end

	local bg = instance.settings.background
	local texture = instance.background.texture

	if bg.enabled then
		instance.background:Show()

		if bg.type == 'texture' then
			-- Use texture background
			local texturePath = bg.texture
			-- Try to get from LibSharedMedia if it's a key
			local LSM = SUI.Lib.LSM
			if LSM and LSM:Fetch('background', texturePath, true) then
				texturePath = LSM:Fetch('background', texturePath)
			end
			texture:SetTexture(texturePath)
			texture:SetVertexColor(1, 1, 1, bg.alpha)
		else
			-- Use solid color background
			texture:SetTexture('Interface\\Buttons\\WHITE8X8')
			if bg.classColor then
				local color = GetInstanceClassColor(instance)
				if color then
					texture:SetVertexColor(color.r, color.g, color.b, bg.alpha)
				else
					texture:SetVertexColor(1, 1, 1, bg.alpha)
				end
			else
				texture:SetVertexColor(unpack(bg.color))
			end
		end
	else
		instance.background:Hide()
	end
end

---Update border appearance
---@param id string Instance identifier
function Handler:UpdateBorders(id)
	local instance = self.instances[id]
	if not instance then
		return
	end

	local border = instance.settings.border

	if not border.enabled then
		for _, borderFrame in pairs(instance.borders) do
			borderFrame:Hide()
		end
		return
	end

	-- Position and show enabled border sides
	for _, side in ipairs({ 'top', 'bottom', 'left', 'right' }) do
		local borderFrame = instance.borders[side]

		if border.sides[side] then
			borderFrame:Show()

			-- Position the border
			borderFrame:ClearAllPoints()
			if side == 'top' then
				borderFrame:SetPoint('TOPLEFT', instance.parent, 'TOPLEFT', 0, border.size)
				borderFrame:SetPoint('TOPRIGHT', instance.parent, 'TOPRIGHT', 0, border.size)
				borderFrame:SetHeight(border.size)
			elseif side == 'bottom' then
				borderFrame:SetPoint('BOTTOMLEFT', instance.parent, 'BOTTOMLEFT', 0, -border.size)
				borderFrame:SetPoint('BOTTOMRIGHT', instance.parent, 'BOTTOMRIGHT', 0, -border.size)
				borderFrame:SetHeight(border.size)
			elseif side == 'left' then
				borderFrame:SetPoint('TOPLEFT', instance.parent, 'TOPLEFT', -border.size, 0)
				borderFrame:SetPoint('BOTTOMLEFT', instance.parent, 'BOTTOMLEFT', -border.size, 0)
				borderFrame:SetWidth(border.size)
			elseif side == 'right' then
				borderFrame:SetPoint('TOPRIGHT', instance.parent, 'TOPRIGHT', border.size, 0)
				borderFrame:SetPoint('BOTTOMRIGHT', instance.parent, 'BOTTOMRIGHT', border.size, 0)
				borderFrame:SetWidth(border.size)
			end

			-- Set border color
			if border.classColors[side] then
				local color = GetInstanceClassColor(instance)
				if color then
					borderFrame.texture:SetVertexColor(color.r, color.g, color.b, 1)
				else
					borderFrame.texture:SetVertexColor(1, 1, 1, 1)
				end
			else
				local color = border.colors[side]
				borderFrame.texture:SetVertexColor(unpack(color))
			end
		else
			borderFrame:Hide()
		end
	end
end

---Refresh class colors for an instance (call when the unit changes, e.g. target switch)
---@param id string Instance identifier
function Handler:RefreshClassColors(id)
	local instance = self.instances[id]
	if not instance or not instance.settings.enabled then
		return
	end

	local needsRefresh = false
	if instance.settings.background.classColor then
		needsRefresh = true
	end
	if instance.settings.border.enabled then
		for _, side in ipairs({ 'top', 'bottom', 'left', 'right' }) do
			if instance.settings.border.classColors[side] then
				needsRefresh = true
				break
			end
		end
	end

	if needsRefresh then
		self:UpdateBackground(id)
		self:UpdateBorders(id)
	end
end

---Show/hide an instance
---@param id string Instance identifier
---@param visible boolean Show or hide
function Handler:SetVisible(id, visible)
	local instance = self.instances[id]
	if not instance then
		return
	end

	instance.visible = visible
	self:Update(id)
end

---Destroy an instance and clean up
---@param id string Instance identifier
function Handler:Destroy(id)
	local instance = self.instances[id]
	if not instance then
		return
	end

	if instance.background then
		instance.background:Hide()
		instance.background:SetParent(nil)
		instance.background = nil
	end

	for _, border in pairs(instance.borders) do
		border:Hide()
		border:SetParent(nil)
	end
	instance.borders = {}

	self.instances[id] = nil
end

---Get instance settings
---@param id string Instance identifier
---@return SUI.BackgroundBorder.Settings?
function Handler:GetSettings(id)
	local instance = self.instances[id]
	return instance and instance.settings
end

---Generate options table for AceConfig integration
---@param id string Instance identifier
---@param getFunc function Function to get current settings
---@param setFunc function Function to save settings changes
---@param updateFunc function Function to call after changes
---@return AceConfig.OptionsTable
function Handler:GenerateOptions(id, getFunc, setFunc, updateFunc)
	local L = SUI.L

	return {
		type = 'group',
		name = L['Background & Border'] or 'Background & Border',
		order = 100,
		args = {
			enabled = {
				type = 'toggle',
				name = L['Enable'] or 'Enable',
				desc = L['Enable background and border system'] or 'Enable background and border system',
				order = 1,
				get = function()
					return getFunc().enabled
				end,
				set = function(_, val)
					local settings = getFunc()
					settings.enabled = val
					setFunc(settings)
					if updateFunc then
						updateFunc()
					end
				end,
			},
			displayLevel = {
				type = 'range',
				name = L['Display Level'] or 'Display Level',
				desc = L['Frame level relative to parent (negative = below art, positive = above art)'] or 'Frame level relative to parent (negative = below art, positive = above art)',
				order = 2,
				min = -10,
				max = 10,
				step = 1,
				get = function()
					return getFunc().displayLevel
				end,
				set = function(_, val)
					local settings = getFunc()
					settings.displayLevel = val
					setFunc(settings)
					if updateFunc then
						updateFunc()
					end
				end,
			},
			background = {
				type = 'group',
				name = L['Background'] or 'Background',
				order = 10,
				inline = true,
				args = {
					enabled = {
						type = 'toggle',
						name = L['Enable Background'] or 'Enable Background',
						order = 1,
						get = function()
							return getFunc().background.enabled
						end,
						set = function(_, val)
							local settings = getFunc()
							settings.background.enabled = val
							setFunc(settings)
							if updateFunc then
								updateFunc()
							end
						end,
					},
					type = {
						type = 'select',
						name = L['Background Type'] or 'Background Type',
						order = 2,
						values = {
							color = L['Solid Color'] or 'Solid Color',
							texture = L['Texture'] or 'Texture',
						},
						disabled = function()
							return not getFunc().background.enabled
						end,
						get = function()
							return getFunc().background.type
						end,
						set = function(_, val)
							local settings = getFunc()
							settings.background.type = val
							setFunc(settings)
							if updateFunc then
								updateFunc()
							end
						end,
					},
					color = {
						type = 'color',
						name = L['Background Color'] or 'Background Color',
						order = 3,
						hasAlpha = true,
						disabled = function()
							local bg = getFunc().background
							return not bg.enabled or bg.type ~= 'color' or bg.classColor
						end,
						get = function()
							local color = getFunc().background.color
							return unpack(color)
						end,
						set = function(_, r, g, b, a)
							local settings = getFunc()
							settings.background.color = { r, g, b, a }
							setFunc(settings)
							if updateFunc then
								updateFunc()
							end
						end,
					},
					classColor = {
						type = 'toggle',
						name = L['Use Class Color'] or 'Use Class Color',
						order = 4,
						disabled = function()
							local bg = getFunc().background
							return not bg.enabled or bg.type ~= 'color'
						end,
						get = function()
							return getFunc().background.classColor
						end,
						set = function(_, val)
							local settings = getFunc()
							settings.background.classColor = val
							setFunc(settings)
							if updateFunc then
								updateFunc()
							end
						end,
					},
					texture = {
						type = 'select',
						dialogControl = 'LSM30_Background',
						name = L['Background Texture'] or 'Background Texture',
						order = 5,
						values = function()
							local LSM = SUI.Lib.LSM
							return LSM and LSM:HashTable('background') or {}
						end,
						disabled = function()
							local bg = getFunc().background
							return not bg.enabled or bg.type ~= 'texture'
						end,
						get = function()
							return getFunc().background.texture
						end,
						set = function(_, val)
							local settings = getFunc()
							settings.background.texture = val
							setFunc(settings)
							if updateFunc then
								updateFunc()
							end
						end,
					},
					alpha = {
						type = 'range',
						name = L['Background Alpha'] or 'Background Alpha',
						order = 6,
						min = 0,
						max = 1,
						step = 0.01,
						disabled = function()
							return not getFunc().background.enabled
						end,
						get = function()
							return getFunc().background.alpha
						end,
						set = function(_, val)
							local settings = getFunc()
							settings.background.alpha = val
							setFunc(settings)
							if updateFunc then
								updateFunc()
							end
						end,
					},
				},
			},
			border = {
				type = 'group',
				name = L['Border'] or 'Border',
				order = 20,
				inline = true,
				args = {
					enabled = {
						type = 'toggle',
						name = L['Enable Border'] or 'Enable Border',
						order = 1,
						get = function()
							return getFunc().border.enabled
						end,
						set = function(_, val)
							local settings = getFunc()
							settings.border.enabled = val
							setFunc(settings)
							if updateFunc then
								updateFunc()
							end
						end,
					},
					size = {
						type = 'range',
						name = L['Border Size'] or 'Border Size',
						order = 2,
						min = 1,
						max = 10,
						step = 1,
						disabled = function()
							return not getFunc().border.enabled
						end,
						get = function()
							return getFunc().border.size
						end,
						set = function(_, val)
							local settings = getFunc()
							settings.border.size = val
							setFunc(settings)
							if updateFunc then
								updateFunc()
							end
						end,
					},
					sides = {
						type = 'multiselect',
						name = L['Border Sides'] or 'Border Sides',
						order = 3,
						values = {
							top = L['Top'] or 'Top',
							bottom = L['Bottom'] or 'Bottom',
							left = L['Left'] or 'Left',
							right = L['Right'] or 'Right',
						},
						disabled = function()
							return not getFunc().border.enabled
						end,
						get = function(_, key)
							return getFunc().border.sides[key]
						end,
						set = function(_, key, val)
							local settings = getFunc()
							settings.border.sides[key] = val
							setFunc(settings)
							if updateFunc then
								updateFunc()
							end
						end,
					},
					colors = {
						type = 'group',
						name = L['Border Colors'] or 'Border Colors',
						order = 10,
						inline = true,
						disabled = function()
							return not getFunc().border.enabled
						end,
						args = {},
					},
					classColors = {
						type = 'group',
						name = L['Use Class Color'] or 'Use Class Color',
						order = 20,
						inline = true,
						disabled = function()
							return not getFunc().border.enabled
						end,
						args = {},
					},
				},
			},
		},
	}
end

---Generate border color and class color options for each side
---@param options AceConfig.OptionsTable Base options table from GenerateOptions
---@param getFunc function Function to get current settings
---@param setFunc function Function to save settings changes
---@param updateFunc function Function to call after changes
function Handler:AddBorderSideOptions(options, getFunc, setFunc, updateFunc)
	local L = SUI.L
	local sides = { 'top', 'bottom', 'left', 'right' }
	local sideNames = {
		top = L['Top'] or 'Top',
		bottom = L['Bottom'] or 'Bottom',
		left = L['Left'] or 'Left',
		right = L['Right'] or 'Right',
	}

	-- Add color options for each side
	for i, side in ipairs(sides) do
		options.args.border.args.colors.args[side] = {
			type = 'color',
			name = sideNames[side],
			order = i,
			hasAlpha = true,
			disabled = function()
				local settings = getFunc()
				return not settings.border.enabled or not settings.border.sides[side] or settings.border.classColors[side]
			end,
			get = function()
				local color = getFunc().border.colors[side] or { 1, 1, 1, 1 }
				return unpack(color)
			end,
			set = function(_, r, g, b, a)
				local settings = getFunc()
				settings.border.colors[side] = { r, g, b, a }
				setFunc(settings)
				if updateFunc then
					updateFunc()
				end
			end,
		}

		-- Add class color toggle for each side
		options.args.border.args.classColors.args[side] = {
			type = 'toggle',
			name = sideNames[side],
			order = i,
			disabled = function()
				local settings = getFunc()
				return not settings.border.enabled or not settings.border.sides[side]
			end,
			get = function()
				return getFunc().border.classColors[side]
			end,
			set = function(_, val)
				local settings = getFunc()
				settings.border.classColors[side] = val
				setFunc(settings)
				if updateFunc then
					updateFunc()
				end
			end,
		}
	end

	return options
end

---Convenience method: Create complete options table with all sides configured
---@param id string Instance identifier
---@param getFunc function Function to get current settings
---@param setFunc function Function to save settings changes
---@param updateFunc function Function to call after changes
---@return AceConfig.OptionsTable Complete options table
function Handler:GenerateCompleteOptions(id, getFunc, setFunc, updateFunc)
	local options = self:GenerateOptions(id, getFunc, setFunc, updateFunc)
	return self:AddBorderSideOptions(options, getFunc, setFunc, updateFunc)
end

---Convenience method: Quick setup for unit frames
---@param frame Frame Unit frame to add background/border to
---@param frameName string Frame identifier (e.g., 'player', 'target')
---@param settings? SUI.BackgroundBorder.Settings Initial settings
---@return SUI.BackgroundBorder.Instance
function Handler:SetupUnitFrame(frame, frameName, settings)
	local id = 'UnitFrame_' .. frameName
	return self:Create(frame, id, settings)
end

---Convenience method: Quick setup for nameplates
---@param frame Frame Nameplate frame
---@param settings? SUI.BackgroundBorder.Settings Initial settings
---@return SUI.BackgroundBorder.Instance
function Handler:SetupNameplate(frame, settings)
	local id = 'Nameplate_' .. (frame:GetName() or tostring(frame))
	return self:Create(frame, id, settings)
end

---Convenience method: Quick setup for artwork elements
---@param frame Frame Artwork frame
---@param elementName string Element identifier
---@param settings? SUI.BackgroundBorder.Settings Initial settings
---@return SUI.BackgroundBorder.Instance
function Handler:SetupArtwork(frame, elementName, settings)
	local id = 'Artwork_' .. elementName
	return self:Create(frame, id, settings)
end

---Convenience method: Get a simple color-only background preset
---@param color? table Color table {r, g, b, a}
---@param alpha? number Override alpha value
---@return SUI.BackgroundBorder.Settings
function Handler:CreateColorBackground(color, alpha)
	color = color or { 0.1, 0.1, 0.1, 0.8 }
	alpha = alpha or color[4] or 0.8

	return {
		enabled = true,
		displayLevel = 0,
		background = {
			enabled = true,
			type = 'color',
			color = color,
			alpha = alpha,
			classColor = false,
		},
		border = {
			enabled = false,
		},
	}
end

---Convenience method: Get a background + border preset
---@param backgroundColor? table Background color {r, g, b, a}
---@param borderColor? table Border color {r, g, b, a}
---@param borderSize? number Border thickness
---@return SUI.BackgroundBorder.Settings
function Handler:CreateBackgroundWithBorder(backgroundColor, borderColor, borderSize)
	backgroundColor = backgroundColor or { 0.1, 0.1, 0.1, 0.8 }
	borderColor = borderColor or { 1, 1, 1, 1 }
	borderSize = borderSize or 1

	return {
		enabled = true,
		displayLevel = 0,
		background = {
			enabled = true,
			type = 'color',
			color = backgroundColor,
			alpha = backgroundColor[4] or 0.8,
			classColor = false,
		},
		border = {
			enabled = true,
			sides = { top = true, bottom = true, left = true, right = true },
			size = borderSize,
			colors = {
				top = borderColor,
				bottom = borderColor,
				left = borderColor,
				right = borderColor,
			},
			classColors = { top = false, bottom = false, left = false, right = false },
		},
	}
end

---Convenience method: Get a class-colored background preset
---@param useClassBorder? boolean Whether to use class color for border too
---@param alpha? number Background alpha
---@return SUI.BackgroundBorder.Settings
function Handler:CreateClassColoredBackground(useClassBorder, alpha)
	alpha = alpha or 0.8

	return {
		enabled = true,
		displayLevel = 0,
		background = {
			enabled = true,
			type = 'color',
			color = { 1, 1, 1, alpha }, -- Will be overridden by class color
			alpha = alpha,
			classColor = true,
		},
		border = {
			enabled = useClassBorder or false,
			sides = { top = true, bottom = true, left = true, right = true },
			size = 1,
			colors = {
				top = { 1, 1, 1, 1 },
				bottom = { 1, 1, 1, 1 },
				left = { 1, 1, 1, 1 },
				right = { 1, 1, 1, 1 },
			},
			classColors = {
				top = useClassBorder or false,
				bottom = useClassBorder or false,
				left = useClassBorder or false,
				right = useClassBorder or false,
			},
		},
	}
end

---Convenience method: Mass update multiple instances
---@param ids table Array of instance IDs
---@param settings SUI.BackgroundBorder.Settings Settings to apply to all
function Handler:UpdateMultiple(ids, settings)
	for _, id in ipairs(ids) do
		self:Update(id, settings)
	end
end

---Convenience method: Mass destroy multiple instances
---@param ids table Array of instance IDs
function Handler:DestroyMultiple(ids)
	for _, id in ipairs(ids) do
		self:Destroy(id)
	end
end

---Convenience method: Get all instances matching a prefix
---@param prefix string ID prefix to match (e.g., 'UnitFrame_')
---@return table Array of instance IDs
function Handler:GetInstancesByPrefix(prefix)
	local matches = {}
	for id, _ in pairs(self.instances) do
		if id:match('^' .. prefix) then
			table.insert(matches, id)
		end
	end
	return matches
end

-- Make the handler globally accessible
SUI.Handlers.BackgroundBorder = Handler
