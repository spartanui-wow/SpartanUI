local SUI = SUI
local L = SUI.L
---@class SUI.Module.Minimap
local module = SUI.Minimap

local elementNaming = {
	['coords'] = 'Coordinates',
	['zoneText'] = 'Zone Text',
	['zoomButtons'] = 'Zoom Buttons',
	['mailIcon'] = 'Mail Icon',
	['instanceDifficulty'] = 'Instance Difficulty',
	['tracking'] = 'Tracking',
	['calendarButton'] = 'Calendar',
	['expansionButton'] = 'Expansion Button',
	['clock'] = 'Clock',
	['queueStatus'] = 'Queue Status',
	['addonButtons'] = 'Addon Buttons',
	['background'] = 'Background',
	['BorderTop'] = 'Border Top',
}

-- DB path helpers for the custom per-style settings pattern
-- These ensure the nested table path exists before writing

local function ensureCustomStylePath()
	local style = SUI:GetActiveStyle()
	if not module.DB.customSettings[style] then
		module.DB.customSettings[style] = {}
	end
	return module.DB.customSettings[style]
end

local function ensureCustomElementPath(elName)
	local customStyle = ensureCustomStylePath()
	if module.Settings and module.Settings.elements then
		if not customStyle.elements then
			customStyle.elements = {}
		end
		if not customStyle.elements[elName] then
			customStyle.elements[elName] = {}
		end
		return customStyle.elements[elName]
	else
		if not customStyle[elName] then
			customStyle[elName] = {}
		end
		return customStyle[elName]
	end
end

local function GetOption(info)
	local element = info[#info - 1]
	local option = info[#info]

	-- module.Settings is already the merged result (base + theme + user customizations)
	local elementSettings = module.Settings and (module.Settings.elements and module.Settings.elements[element] or module.Settings[element])
	if not elementSettings then
		return nil
	end

	return elementSettings[option]
end

local function SetOption(info, value)
	local element = info[#info - 1]
	local option = info[#info]

	-- Persist to custom settings DB only - Update(true) rebuilds module.Settings from DB
	local customPath = ensureCustomElementPath(element)
	customPath[option] = value

	module:Update(true)
end

local function GetRelativeToValues()
	local values = {
		Minimap = L['Minimap'],
		MinimapCluster = L['Minimap Cluster'],
		UIParent = L['Screen'],
		BorderTop = L['Border Top'],
	}

	-- Add other Minimap elements - handle both Retail and Classic structures
	local elementsToCheck = module.Settings.elements
	if not elementsToCheck and not module.UsesModernMinimap then
		-- For Classic, check known element keys at top level
		elementsToCheck = {}
		local classicKeys = { 'background', 'ZoneText', 'coords', 'zoomButtons', 'clock', 'tracking', 'mailIcon', 'instanceDifficulty', 'queueStatus', 'addonButtons' }
		for _, key in ipairs(classicKeys) do
			if module.Settings[key] and type(module.Settings[key]) == 'table' then
				elementsToCheck[key] = module.Settings[key]
			end
		end
	end

	if elementsToCheck then
		for elementName, elementSettings in pairs(elementsToCheck) do
			if elementSettings.enabled then
				values[elementName] = L[elementName] or elementName
			end
		end
	end

	-- Add special cases
	local specialCases = {
		'Tracking',
		'Calendar',
		'Coordinates',
		'Clock',
		'ZoneText',
		'MailIcon',
		'InstanceDifficulty',
		'QueueStatus',
	}

	for _, case in ipairs(specialCases) do
		if not values[case] then
			values[case] = L[case] or case
		end
	end

	return values
end

local function GetPositionOption(info)
	local element = info[#info - 2]
	local positionPart = info[#info]

	-- module.Settings is already the merged result (base + theme + user customizations)
	local elementSettings = module.Settings and (module.Settings.elements and module.Settings.elements[element] or module.Settings[element])
	if not elementSettings or not elementSettings.position then
		return nil
	end

	local point, relativeTo, relativePoint, x, y = strsplit(',', elementSettings.position)
	if positionPart == 'point' then
		return point
	elseif positionPart == 'relativeTo' then
		return relativeTo
	elseif positionPart == 'relativePoint' then
		return relativePoint
	elseif positionPart == 'x' then
		return tonumber(x)
	elseif positionPart == 'y' then
		return tonumber(y)
	end
end

local function SetPositionOption(info, value)
	local element = info[#info - 2]
	local positionPart = info[#info]

	-- module.Settings is already the merged result (base + theme + user customizations)
	local elementSettings = module.Settings and (module.Settings.elements and module.Settings.elements[element] or module.Settings[element])
	if not elementSettings or not elementSettings.position then
		return
	end

	local point, relativeTo, relativePoint, x, y = strsplit(',', elementSettings.position)
	if positionPart == 'point' then
		point = value
	elseif positionPart == 'relativeTo' then
		relativeTo = value
	elseif positionPart == 'relativePoint' then
		relativePoint = value
	elseif positionPart == 'x' then
		x = value
	elseif positionPart == 'y' then
		y = value
	end

	local newPositionString = string.format('%s,%s,%s,%s,%s', point, relativeTo, relativePoint, x, y)

	-- Persist to custom settings DB only
	local customPath = ensureCustomElementPath(element)
	customPath.position = newPositionString

	-- Update the live settings and reposition just this element (avoid full rebuild on every slider tick)
	elementSettings.position = newPositionString
	module:RepositionElement(element)
end

local anchorValues = {
	TOP = L['Top'],
	TOPLEFT = L['Top Left'],
	TOPRIGHT = L['Top Right'],
	BOTTOM = L['Bottom'],
	BOTTOMLEFT = L['Bottom Left'],
	BOTTOMRIGHT = L['Bottom Right'],
	LEFT = L['Left'],
	RIGHT = L['Right'],
	CENTER = L['Center'],
}

-- Options
function module:BuildOptions()
	local anchorPoints = {
		['TOPLEFT'] = 'TOP LEFT',
		['TOP'] = 'TOP',
		['TOPRIGHT'] = 'TOP RIGHT',
		['RIGHT'] = 'RIGHT',
		['CENTER'] = 'CENTER',
		['LEFT'] = 'LEFT',
		['BOTTOMLEFT'] = 'BOTTOM LEFT',
		['BOTTOM'] = 'BOTTOM',
		['BOTTOMRIGHT'] = 'BOTTOM RIGHT',
	}

	---@type AceConfig.OptionsTable
	local options = {
		type = 'group',
		name = L['Minimap'],
		disabled = function()
			return SUI:IsModuleDisabled(module)
		end,
		childGroups = 'tab',
		args = {
			general = {
				name = L['General'],
				type = 'group',
				order = 1,
				args = {
					shape = {
						name = L['Shape'],
						type = 'select',
						order = 1,
						values = {
							circle = L['Circle'],
							square = L['Square'],
						},
						get = function()
							return module.Settings and module.Settings.shape
						end,
						set = function(_, value)
							ensureCustomStylePath().shape = value
							module:Update(true)
						end,
					},
					size = {
						name = L['Size'],
						type = 'range',
						order = 2,
						min = 120,
						max = 500,
						step = 1,
						get = function()
							return module.Settings and module.Settings.size and module.Settings.size[1]
						end,
						set = function(_, value)
							ensureCustomStylePath().size = { value, value }
							module:Update(true)
						end,
					},
					scaleWithArt = {
						name = L['Scale with UI'],
						type = 'toggle',
						order = 3,
						get = function()
							return module.Settings and module.Settings.scaleWithArt
						end,
						set = function(_, value)
							ensureCustomStylePath().scaleWithArt = value
							module:Update(true)
						end,
					},
					rotate = {
						name = L['Rotate the minimap'],
						type = 'toggle',
						order = 3,
						get = function()
							return module.Settings and module.Settings.rotate
						end,
						set = function(_, value)
							ensureCustomStylePath().rotate = value
							module:Update(true)
						end,
					},
					autoZoomGroup = {
						name = L['Auto Zoom-Out'],
						type = 'group',
						order = 5,
						inline = true,
						args = {
							autoZoomEnabled = {
								name = L['Enabled'],
								desc = L['Automatically zoom out after zooming in'],
								type = 'toggle',
								order = 1,
								get = function()
									return module.Settings.autoZoom and module.Settings.autoZoom.enabled
								end,
								set = function(_, val)
									local customStyle = ensureCustomStylePath()
									if not customStyle.autoZoom then
										customStyle.autoZoom = {}
									end
									customStyle.autoZoom.enabled = val
									module:Update(true)
								end,
							},
							autoZoomDelay = {
								name = L['Delay (seconds)'],
								desc = L['How long to wait before zooming back out'],
								type = 'range',
								order = 2,
								min = 1,
								max = 15,
								step = 1,
								get = function()
									return module.Settings and module.Settings.autoZoom and module.Settings.autoZoom.delay or 5
								end,
								set = function(_, val)
									local customStyle = ensureCustomStylePath()
									if not customStyle.autoZoom then
										customStyle.autoZoom = {}
									end
									customStyle.autoZoom.delay = val
									module:Update(true)
								end,
							},
						},
					},
					rightClickMenu = {
						name = L['Right-Click Menu'],
						desc = L['Show a context menu with UI shortcuts when right-clicking the minimap'],
						type = 'toggle',
						order = 6,
						hidden = function()
							return not module.UsesModernMinimap
						end,
						get = function()
							return module.Settings.rightClickMenu ~= false
						end,
						set = function(_, val)
							ensureCustomStylePath().rightClickMenu = val
							module:Update(true)
						end,
					},
					resetElement = {
						name = L['Reset Element'],
						type = 'execute',
						order = 50,
						hidden = function()
							return not SUI.Options:hasChanges(module.DB.customSettings[SUI:GetActiveStyle()], module.BaseOpt)
						end,
						func = function()
							-- Reset the element's settings to default
							module.DB.customSettings[SUI:GetActiveStyle()] = nil

							-- Trigger a full update of the UnitFrames
							module:Update(true)
						end,
					},
					vehiclePosition = {
						name = L['Vehicle UI Position'],
						type = 'group',
						order = 25,
						inline = true,
						hidden = function()
							-- Only show vehicle options if the skin defines the minimap as being under Vehicle UI
							if not module.Settings then
								return true
							end -- Hide if settings not loaded
							return not module.Settings.UnderVehicleUI
						end,
						args = {
							skinInfo = {
								name = L['Skin Position Info'],
								desc = L['This skin positions the minimap under the Blizzard Vehicle UI. You can configure how the minimap behaves when in a vehicle.'],
								type = 'description',
								width = 'full',
								order = 0,
							},
							enable = {
								name = L['Configure Vehicle Position'],
								desc = L['Open the mover to set the minimap position when in a vehicle'],
								type = 'execute',
								order = 1,
								func = function()
									module:VehicleUIMoverShow()
								end,
							},
							reset = {
								name = L['Reset Position'],
								desc = L['Reset the vehicle minimap position to default'],
								type = 'execute',
								order = 2,
								func = function()
									module:ResetVehiclePosition()
								end,
							},
							useVehicleMover = {
								name = L['Use Vehicle Position'],
								desc = L['When enabled, the minimap will move to a different position when in a vehicle. When disabled, the minimap stays in its normal position.'],
								type = 'toggle',
								order = 3,
								get = function()
									if not module.Settings then
										return true
									end -- Default to true if settings not loaded
									return module.Settings.useVehicleMover ~= false -- Default to true if nil or true
								end,
								set = function(_, val)
									ensureCustomStylePath().useVehicleMover = val
									module:Update(true)
								end,
							},
						},
					},
				},
			},
			elements = {
				name = L['Elements'],
				type = 'group',
				order = 2,
				childGroups = 'tree',
				args = {},
			},
		},
	}

	-- Build options for each element
	-- Handle both Retail (nested .elements) and Classic (flat) structures
	-- Define which keys are elements (not top-level settings) for Classic
	local classicElementKeys = {
		background = true,
		ZoneText = true,
		coords = true,
		zoomButtons = true,
		clock = true,
		tracking = true,
		mailIcon = true,
		instanceDifficulty = true,
		queueStatus = true,
		addonButtons = true,
	}

	-- Helper to get the elements table (Retail) or extract elements from flat structure (Classic)
	local elementsSource = module.Settings.elements
	if not elementsSource and not module.UsesModernMinimap then
		-- Build elements source from flat Classic structure
		elementsSource = {}
		for key, value in pairs(module.Settings) do
			if classicElementKeys[key] and type(value) == 'table' then
				elementsSource[key] = value
			end
		end
	end

	-- Helper functions to get/set element settings regardless of structure
	-- Modern-engine clients (Retail, Forever) keep minimap pieces under `elements`
	local nested = module.Settings.elements ~= nil

	local function getElementSettings(elName)
		if nested then
			return module.Settings.elements and module.Settings.elements[elName]
		else
			return module.Settings[elName]
		end
	end

	local function getBaseElementSettings(elName)
		if nested then
			return module.BaseOpt.elements and module.BaseOpt.elements[elName]
		else
			return module.BaseOpt[elName]
		end
	end

	local function getCustomElementSettings(elName)
		local style = SUI:GetActiveStyle()
		if not module.DB.customSettings[style] then
			return nil
		end
		if nested then
			return module.DB.customSettings[style].elements and module.DB.customSettings[style].elements[elName]
		else
			return module.DB.customSettings[style][elName]
		end
	end

	local function clearCustomElement(elName)
		local style = SUI:GetActiveStyle()
		if not module.DB.customSettings[style] then
			return
		end
		if nested then
			if module.DB.customSettings[style].elements then
				module.DB.customSettings[style].elements[elName] = nil
			end
		else
			module.DB.customSettings[style][elName] = nil
		end
	end

	if elementsSource then
		for elementName, elementSettings in pairs(elementsSource) do
			options.args.elements.args[elementName] = {
				name = L[elementNaming[elementName] or elementName],
				type = 'group',
				get = GetOption,
				set = SetOption,
				args = {
					resetElement = {
						name = L['Reset Element'],
						type = 'execute',
						order = 0,
						hidden = function()
							return not SUI.Options:hasChanges(getCustomElementSettings(elementName), getBaseElementSettings(elementName))
						end,
						func = function()
							clearCustomElement(elementName)
							module:Update(true)
						end,
					},
					enabled = {
						name = L['Enabled'],
						type = 'toggle',
						order = 1,
						get = function()
							local elSettings = getElementSettings(elementName)
							return elSettings and elSettings.enabled
						end,
						set = SetOption,
					},
				},
			}
			if elementSettings.position then
				options.args.elements.args[elementName].args.position = {
					name = L['Position'],
					type = 'group',
					order = 2,
					inline = true,
					args = {
						point = {
							name = L['Anchor'],
							type = 'select',
							order = 1,
							values = anchorValues,
							get = GetPositionOption,
							set = SetPositionOption,
						},
						relativeTo = {
							name = L['Relative To'],
							type = 'select',
							order = 2,
							values = GetRelativeToValues,
							get = GetPositionOption,
							set = SetPositionOption,
						},
						relativePoint = {
							name = L['Relative Anchor'],
							type = 'select',
							order = 3,
							values = anchorValues,
							get = GetPositionOption,
							set = SetPositionOption,
						},
						x = {
							name = L['X Offset'],
							type = 'range',
							order = 4,
							min = -100,
							max = 100,
							step = 1,
							get = GetPositionOption,
							set = SetPositionOption,
						},
						y = {
							name = L['Y Offset'],
							type = 'range',
							order = 5,
							min = -100,
							max = 100,
							step = 1,
							get = GetPositionOption,
							set = SetPositionOption,
						},
					},
				}
			end

			if elementSettings.scale then
				options.args.elements.args[elementName].args.scale = {
					name = L['Scale'],
					type = 'range',
					order = 3,
					min = 0.1,
					max = 2,
					step = 0.05,
					get = function()
						local elSettings = getElementSettings(elementName)
						return elSettings and elSettings.scale or 1
					end,
					set = SetOption,
				}
			end

			if elementSettings.alpha then
				options.args.elements.args[elementName].args.alpha = {
					name = L['Alpha'],
					type = 'range',
					order = 3.5,
					min = 0,
					max = 1,
					step = 0.05,
					get = function()
						local elSettings = getElementSettings(elementName)
						return elSettings and elSettings.alpha or 1
					end,
					set = SetOption,
				}
			end

			if elementSettings.color then
				options.args.elements.args[elementName].args.color = {
					name = L['Color'],
					type = 'color',
					order = 3,
					hasAlpha = true,
					get = function()
						local elSettings = getElementSettings(elementName)
						return unpack(elSettings and elSettings.color or { 1, 1, 1, 1 })
					end,
					set = function(_, r, g, b, a)
						local customPath = ensureCustomElementPath(elementName)
						customPath.color = { r, g, b, a }
						module:Update(true)
					end,
				}
			end

			-- Background-specific options: size, blend mode, texture preset, position offsets
			if elementName == 'background' then
				local defaultBgPosition = 'CENTER,Minimap,CENTER,0,0'

				local function getBgPositionPart(part)
					local elSettings = getElementSettings(elementName)
					local posStr = elSettings and elSettings.position or defaultBgPosition
					if type(posStr) ~= 'string' then
						posStr = defaultBgPosition
					end
					local point, relativeTo, relativePoint, x, y = strsplit(',', posStr)
					if part == 'point' then
						return point
					elseif part == 'relativeTo' then
						return relativeTo
					elseif part == 'relativePoint' then
						return relativePoint
					elseif part == 'x' then
						return tonumber(x) or 0
					elseif part == 'y' then
						return tonumber(y) or 0
					end
				end

				local function setBgPositionPart(part, value)
					local elSettings = getElementSettings(elementName)
					local posStr = elSettings and elSettings.position or defaultBgPosition
					if type(posStr) ~= 'string' then
						posStr = defaultBgPosition
					end
					local point, relativeTo, relativePoint, x, y = strsplit(',', posStr)
					if part == 'x' then
						x = value
					elseif part == 'y' then
						y = value
					end
					local newPos = string.format('%s,%s,%s,%s,%s', point, relativeTo, relativePoint, x, y)
					local customPath = ensureCustomElementPath(elementName)
					customPath.position = newPos
					module:Update(true)
				end

				options.args.elements.args[elementName].args.size = {
					name = L['Size'],
					desc = L['Size of the background texture (square)'],
					type = 'range',
					order = 4,
					min = 100,
					max = 500,
					step = 1,
					get = function()
						local elSettings = getElementSettings(elementName)
						return elSettings and elSettings.size and elSettings.size[1] or 200
					end,
					set = function(_, val)
						local customPath = ensureCustomElementPath(elementName)
						customPath.size = { val, val }
						module:Update(true)
					end,
				}

				options.args.elements.args[elementName].args.bgPosition = {
					name = L['Position'],
					type = 'group',
					order = 4.5,
					inline = true,
					args = {
						x = {
							name = L['X Offset'],
							type = 'range',
							order = 1,
							min = -100,
							max = 100,
							step = 1,
							get = function()
								return getBgPositionPart('x')
							end,
							set = function(_, val)
								setBgPositionPart('x', val)
							end,
						},
						y = {
							name = L['Y Offset'],
							type = 'range',
							order = 2,
							min = -100,
							max = 100,
							step = 1,
							get = function()
								return getBgPositionPart('y')
							end,
							set = function(_, val)
								setBgPositionPart('y', val)
							end,
						},
					},
				}

				options.args.elements.args[elementName].args.blendMode = {
					name = L['Blend Mode'],
					desc = L['How the background texture blends with the scene'],
					type = 'select',
					order = 5,
					values = {
						['BLEND'] = 'Blend',
						['ADD'] = 'Add (Glow)',
						['ALPHAKEY'] = 'Alpha Key',
						['MOD'] = 'Mod',
						['DISABLE'] = 'Disable',
					},
					get = function()
						local elSettings = getElementSettings(elementName)
						return elSettings and elSettings.BlendMode or 'BLEND'
					end,
					set = function(_, val)
						local customPath = ensureCustomElementPath(elementName)
						customPath.BlendMode = val
						module:Update(true)
					end,
				}

				options.args.elements.args[elementName].args.texturePreset = {
					name = L['Texture'],
					desc = L['Choose a background texture from available themes'],
					type = 'select',
					order = 6,
					values = function()
						local textures = {}
						local suiMinimap = _G['SUI_Minimap']
						if suiMinimap and suiMinimap.Registry then
							for themeName, data in pairs(suiMinimap.Registry) do
								local bgData = data.settings and data.settings.elements and data.settings.elements.background
								if not bgData then
									bgData = data.settings and data.settings.background
								end
								if bgData and bgData.texture then
									textures[bgData.texture] = themeName
								end
							end
						end
						return textures
					end,
					get = function()
						local elSettings = getElementSettings(elementName)
						return elSettings and elSettings.texture or ''
					end,
					set = function(_, val)
						local customPath = ensureCustomElementPath(elementName)
						customPath.texture = val
						module:Update(true)
					end,
				}
			end

			-- Zoom buttons specific options - spacing and xOffset for second button
			if elementName == 'zoomButtons' then
				options.args.elements.args[elementName].args.spacing = {
					name = L['Button Spacing'],
					desc = L['Vertical gap between zoom in and zoom out buttons'],
					type = 'range',
					order = 4,
					min = 0,
					max = 30,
					step = 1,
					get = function()
						local elSettings = getElementSettings(elementName)
						return elSettings and elSettings.spacing or 2
					end,
					set = function(_, val)
						local customPath = ensureCustomElementPath(elementName)
						customPath.spacing = val
						module:Update(true)
					end,
				}
				options.args.elements.args[elementName].args.xOffset = {
					name = L['Second Button X Offset'],
					desc = L['Horizontal offset for the zoom out button relative to zoom in'],
					type = 'range',
					order = 5,
					min = -30,
					max = 30,
					step = 1,
					get = function()
						local elSettings = getElementSettings(elementName)
						return elSettings and elSettings.xOffset or 0
					end,
					set = function(_, val)
						local customPath = ensureCustomElementPath(elementName)
						customPath.xOffset = val
						module:Update(true)
					end,
				}
			end

			-- Coordinate format dropdown
			if elementName == 'coords' then
				options.args.elements.args[elementName].args.format = {
					name = L['Format'],
					desc = L['How coordinates are displayed'],
					type = 'select',
					order = 4,
					values = {
						['%d, %d'] = L['Whole numbers'] .. ' (45, 67)',
						['%.1f, %.1f'] = L['One decimal'] .. ' (45.3, 67.8)',
						['%.2f, %.2f'] = L['Two decimals'] .. ' (45.32, 67.81)',
					},
					get = function()
						local elSettings = getElementSettings(elementName)
						return elSettings and elSettings.format or '%.1f, %.1f'
					end,
					set = function(_, val)
						local customPath = ensureCustomElementPath(elementName)
						customPath.format = val
						module:Update(true)
					end,
				}
			end

			-- Zone text specific options
			if elementName == 'ZoneText' then
				options.args.elements.args[elementName].args.displayMode = {
					name = L['Display Mode'],
					desc = L['When to show zone text'],
					type = 'select',
					order = 4,
					values = {
						['show'] = L['Always'],
						['mouseover'] = L['Mouseover'],
						['hide'] = L['Hidden'],
					},
					get = function()
						local elSettings = getElementSettings(elementName)
						return elSettings and elSettings.displayMode or 'show'
					end,
					set = function(_, val)
						local customPath = ensureCustomElementPath(elementName)
						customPath.displayMode = val
						module:Update(true)
					end,
				}
				options.args.elements.args[elementName].args.pvpColoring = {
					name = L['PvP Zone Coloring'],
					desc = L['Color the zone text based on zone PvP status (friendly, contested, hostile, sanctuary)'],
					type = 'toggle',
					order = 5,
					get = function()
						local elSettings = getElementSettings(elementName)
						return elSettings and elSettings.pvpColoring
					end,
					set = function(_, val)
						local customPath = ensureCustomElementPath(elementName)
						customPath.pvpColoring = val
						module:Update(true)
					end,
				}
			end

			-- Per-element font options for text elements
			if elementName == 'ZoneText' or elementName == 'coords' or elementName == 'clock' then
				local LSM = LibStub('LibSharedMedia-3.0', true)
				if LSM then
					options.args.elements.args[elementName].args.fontSettings = {
						name = L['Font'],
						type = 'group',
						order = 10,
						inline = true,
						args = {
							fontDesc = {
								name = L['Leave blank to use the global Minimap font setting'],
								type = 'description',
								order = 0,
								fontSize = 'medium',
							},
							fontFace = {
								name = L['Font Face'],
								type = 'select',
								order = 1,
								dialogControl = 'LSM30_Font',
								values = LSM:HashTable('font'),
								get = function()
									local elSettings = getElementSettings(elementName)
									return elSettings and elSettings.font and elSettings.font.face or ''
								end,
								set = function(_, val)
									local customPath = ensureCustomElementPath(elementName)
									if not customPath.font then
										customPath.font = {}
									end
									customPath.font.face = val
									module:Update(true)
								end,
							},
							fontSize = {
								name = L['Font Size'],
								type = 'range',
								order = 2,
								min = 6,
								max = 30,
								step = 1,
								get = function()
									local elSettings = getElementSettings(elementName)
									return elSettings and elSettings.font and elSettings.font.size or 10
								end,
								set = function(_, val)
									local customPath = ensureCustomElementPath(elementName)
									if not customPath.font then
										customPath.font = {}
									end
									customPath.font.size = val
									module:Update(true)
								end,
							},
							fontOutline = {
								name = L['Font Outline'],
								type = 'select',
								order = 3,
								values = {
									[''] = L['None'],
									['OUTLINE'] = L['Outline'],
									['THICKOUTLINE'] = L['Thick Outline'],
									['MONOCHROME'] = L['Monochrome'],
								},
								get = function()
									local elSettings = getElementSettings(elementName)
									return elSettings and elSettings.font and elSettings.font.outline or ''
								end,
								set = function(_, val)
									local customPath = ensureCustomElementPath(elementName)
									if not customPath.font then
										customPath.font = {}
									end
									customPath.font.outline = val
									module:Update(true)
								end,
							},
							resetFont = {
								name = L['Reset to Global'],
								desc = L['Reset to the global Minimap font setting'],
								type = 'execute',
								order = 4,
								func = function()
									local customPath = ensureCustomElementPath(elementName)
									customPath.font = { face = nil, size = nil, outline = nil }
									module:Update(true)
								end,
							},
						},
					}
				end
			end

			if elementSettings.style then
				options.args.elements.args[elementName].args.enabled.hidden = true

				options.args.elements.args[elementName].args.style = {
					name = L['Style'],
					type = 'select',
					order = 4,
					values = {
						['always'] = L['Always'],
						['mouseover'] = L['Mouseover'],
						['never'] = L['Never'],
						['bag'] = L['Button Bag'],
					},
				}

				-- Add button bag specific options for addonButtons
				if elementName == 'addonButtons' then
					options.args.elements.args[elementName].args.bagSettings = {
						name = L['Button Bag Settings'],
						type = 'group',
						order = 5,
						inline = true,
						hidden = function()
							local addonBtnSettings = getElementSettings('addonButtons')
							return not addonBtnSettings or addonBtnSettings.style ~= 'bag'
						end,
						args = {
							excludeList = {
								name = L['Exclude List'],
								desc = L['Comma-separated list of addon names to exclude from the button bag (e.g., "BugSack,Bartender4")'],
								type = 'input',
								order = 1,
								width = 'full',
								get = function()
									local addonBtnSettings = getElementSettings('addonButtons')
									return addonBtnSettings and addonBtnSettings.excludeList or ''
								end,
								set = function(_, value)
									local customPath = ensureCustomElementPath('addonButtons')
									customPath.excludeList = value
									module:Update(true)
								end,
							},
							autoHideDelay = {
								name = L['Auto-hide Delay'],
								desc = L['Seconds before the button bag auto-hides when mouse leaves'],
								type = 'range',
								order = 1,
								min = 0.5,
								max = 10,
								step = 0.5,
								get = function()
									local addonBtnSettings = getElementSettings('addonButtons')
									return addonBtnSettings and addonBtnSettings.autoHideDelay or 2
								end,
								set = function(_, value)
									local customPath = ensureCustomElementPath('addonButtons')
									customPath.autoHideDelay = value
									module:Update(true)
								end,
							},
							buttonsPerRow = {
								name = L['Buttons Per Row'],
								desc = L['Number of buttons to display per row in the button bag'],
								type = 'range',
								order = 2,
								min = 2,
								max = 12,
								step = 1,
								get = function()
									local addonBtnSettings = getElementSettings('addonButtons')
									return addonBtnSettings and addonBtnSettings.buttonsPerRow or 6
								end,
								set = function(_, value)
									local customPath = ensureCustomElementPath('addonButtons')
									local addonBtnSettings = getElementSettings('addonButtons')
									if addonBtnSettings then
										addonBtnSettings.buttonsPerRow = value
									end
									customPath.buttonsPerRow = value
									-- Refresh the bag if open
									module:RefreshButtonBag()
								end,
							},
						},
					}

					-- Add button visibility options (list of detected buttons with toggles)
					options.args.elements.args[elementName].args.buttonVisibility = {
						name = L['Button Visibility'],
						type = 'group',
						order = 6,
						inline = true,
						args = {
							description = {
								name = L['Toggle visibility of individual addon buttons. Disabled buttons will be hidden from the minimap.'],
								type = 'description',
								order = 0,
								fontSize = 'medium',
							},
							refreshList = {
								name = L['Refresh Button List'],
								desc = L['Scan for newly loaded addon buttons'],
								type = 'execute',
								order = 0.5,
								func = function()
									-- Force options rebuild to refresh button list
									module:BuildOptions()
								end,
							},
						},
					}

					-- Dynamically add toggles for each detected button
					local availableButtons = module:GetAvailableButtons()
					local buttonOrder = 1
					for buttonName, isHidden in pairs(availableButtons) do
						options.args.elements.args[elementName].args.buttonVisibility.args['btn_' .. buttonName] = {
							name = buttonName,
							desc = L['Toggle visibility of '] .. buttonName,
							type = 'toggle',
							order = buttonOrder,
							width = 'full',
							get = function()
								return not module:IsButtonHidden(buttonName)
							end,
							set = function(_, value)
								module:SetButtonHidden(buttonName, not value)
							end,
						}
						buttonOrder = buttonOrder + 1
					end

					-- Add a message if no buttons found
					if buttonOrder == 1 then
						options.args.elements.args[elementName].args.buttonVisibility.args.noButtons = {
							name = L['No addon buttons detected. Buttons will appear here after addons with minimap buttons are loaded.'],
							type = 'description',
							order = 1,
							fontSize = 'medium',
						}
					end

					-- Add advanced exclude list option (text input for pattern matching)
					options.args.elements.args[elementName].args.advancedExclude = {
						name = L['Advanced Exclude List'],
						type = 'group',
						order = 7,
						inline = true,
						args = {
							excludeListDesc = {
								name = L['Enter comma-separated patterns to exclude buttons by partial name match (e.g., "Questie,HandyNotes"). This is in addition to the individual button toggles above.'],
								type = 'description',
								order = 0,
								fontSize = 'medium',
							},
							excludeList = {
								name = L['Exclude Patterns'],
								type = 'input',
								order = 1,
								width = 'full',
								get = function()
									local addonBtnSettings = getElementSettings('addonButtons')
									return addonBtnSettings and addonBtnSettings.excludeList or ''
								end,
								set = function(_, value)
									local customPath = ensureCustomElementPath('addonButtons')
									customPath.excludeList = value
									module:Update(true)
								end,
							},
						},
					}
				end
			end
		end
	end -- end of if elementsSource then

	SUI.Options:AddOptions(options, 'Minimap')
end
