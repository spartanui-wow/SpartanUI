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

local function GetOption(info)
	local element = info[#info - 1]
	local option = info[#info]

	-- Handle both Retail (nested) and Classic (flat) structures
	local elementSettings = module.Settings.elements and module.Settings.elements[element] or module.Settings[element]
	if not elementSettings then
		return nil
	end

	local customSettings = module.DB.customSettings[SUI:GetActiveStyle()]
	if customSettings then
		local customElement = customSettings.elements and customSettings.elements[element] or customSettings[element]
		if customElement and customElement[option] ~= nil then
			return customElement[option]
		end
	end

	return elementSettings[option]
end

local function SetOption(info, value)
	local element = info[#info - 1]
	local option = info[#info]

	-- Handle both Retail (nested) and Classic (flat) structures
	if module.Settings.elements then
		-- Retail structure
		module.Settings.elements[element][option] = value
		if not module.DB.customSettings[SUI:GetActiveStyle()].elements then
			module.DB.customSettings[SUI:GetActiveStyle()].elements = {}
		end
		if not module.DB.customSettings[SUI:GetActiveStyle()].elements[element] then
			module.DB.customSettings[SUI:GetActiveStyle()].elements[element] = {}
		end
		module.DB.customSettings[SUI:GetActiveStyle()].elements[element][option] = value
	else
		-- Classic flat structure
		if module.Settings[element] then
			module.Settings[element][option] = value
		end
		if not module.DB.customSettings[SUI:GetActiveStyle()][element] then
			module.DB.customSettings[SUI:GetActiveStyle()][element] = {}
		end
		module.DB.customSettings[SUI:GetActiveStyle()][element][option] = value
	end

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
	if not elementsToCheck and not SUI.IsRetail then
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

	-- Handle both Retail (nested) and Classic (flat) structures
	local elementSettings = module.Settings.elements and module.Settings.elements[element] or module.Settings[element]
	if not elementSettings then
		return nil
	end

	local positionString = elementSettings.position

	local customSettings = module.DB.customSettings[SUI:GetActiveStyle()]
	if customSettings then
		local customElement = customSettings.elements and customSettings.elements[element] or customSettings[element]
		if customElement and customElement.position and type(customElement.position) == 'string' then
			positionString = customElement.position
		end
	end

	if not positionString then
		return nil
	end

	local point, relativeTo, relativePoint, x, y = strsplit(',', positionString)
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

	-- Handle both Retail (nested) and Classic (flat) structures
	local elementSettings = module.Settings.elements and module.Settings.elements[element] or module.Settings[element]
	if not elementSettings then
		return
	end

	local positionString = elementSettings.position

	local customSettings = module.DB.customSettings[SUI:GetActiveStyle()]
	if customSettings then
		local customElement = customSettings.elements and customSettings.elements[element] or customSettings[element]
		if customElement and type(customElement.position) == 'string' then
			positionString = customElement.position
		end
	end

	if not positionString then
		return
	end

	local point, relativeTo, relativePoint, x, y = strsplit(',', positionString)
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

	if module.Settings.elements then
		-- Retail structure
		if not module.DB.customSettings[SUI:GetActiveStyle()].elements then
			module.DB.customSettings[SUI:GetActiveStyle()].elements = {}
		end
		if not module.DB.customSettings[SUI:GetActiveStyle()].elements[element] then
			module.DB.customSettings[SUI:GetActiveStyle()].elements[element] = {}
		end
		module.Settings.elements[element].position = newPositionString
		module.DB.customSettings[SUI:GetActiveStyle()].elements[element].position = newPositionString
	else
		-- Classic flat structure
		if not module.DB.customSettings[SUI:GetActiveStyle()][element] then
			module.DB.customSettings[SUI:GetActiveStyle()][element] = {}
		end
		module.Settings[element].position = newPositionString
		module.DB.customSettings[SUI:GetActiveStyle()][element].position = newPositionString
	end

	module:Update(true)
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
							return module.Settings.shape
						end,
						set = function(_, value)
							module.DB.customSettings[SUI:GetActiveStyle()].shape = value
							module:Update(true)
						end,
					},
					size = {
						name = L['Size'],
						type = 'range',
						order = 2,
						min = 120,
						max = 300,
						step = 1,
						get = function()
							return module.Settings.size[1]
						end,
						set = function(_, value)
							module.DB.customSettings[SUI:GetActiveStyle()].size = { value, value }
							module:Update(true)
						end,
					},
					scaleWithArt = {
						name = L['Scale with UI'],
						type = 'toggle',
						order = 3,
						get = function()
							return module.Settings.scaleWithArt
						end,
						set = function(_, value)
							module.DB.customSettings[SUI:GetActiveStyle()].scaleWithArt = value
							module:Update(true)
						end,
					},
					rotate = {
						name = L['Rotate the minimap'],
						type = 'toggle',
						order = 3,
						get = function()
							return module.Settings.rotate
						end,
						set = function(_, value)
							module.DB.customSettings[SUI:GetActiveStyle()].rotate = value
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
									local currentStyle = SUI:GetActiveStyle()
									if not module.DB.customSettings[currentStyle] then
										module.DB.customSettings[currentStyle] = {}
									end
									module.DB.customSettings[currentStyle].useVehicleMover = val

									-- Update runtime settings after saving to DB
									if module.Settings then
										module.Settings.useVehicleMover = val
									end

									-- Update will handle the vehicle monitoring setup/cleanup automatically
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
	if not elementsSource and not SUI.IsRetail then
		-- Build elements source from flat Classic structure
		elementsSource = {}
		for key, value in pairs(module.Settings) do
			if classicElementKeys[key] and type(value) == 'table' then
				elementsSource[key] = value
			end
		end
	end

	-- Helper functions to get/set element settings regardless of structure
	local function getElementSettings(elName)
		if SUI.IsRetail then
			return module.Settings.elements and module.Settings.elements[elName]
		else
			return module.Settings[elName]
		end
	end

	local function getBaseElementSettings(elName)
		if SUI.IsRetail then
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
		if SUI.IsRetail then
			return module.DB.customSettings[style].elements and module.DB.customSettings[style].elements[elName]
		else
			return module.DB.customSettings[style][elName]
		end
	end

	local function ensureCustomElementPath(elName)
		local style = SUI:GetActiveStyle()
		if not module.DB.customSettings[style] then
			module.DB.customSettings[style] = {}
		end
		if SUI.IsRetail then
			if not module.DB.customSettings[style].elements then
				module.DB.customSettings[style].elements = {}
			end
			if not module.DB.customSettings[style].elements[elName] then
				module.DB.customSettings[style].elements[elName] = {}
			end
			return module.DB.customSettings[style].elements[elName]
		else
			if not module.DB.customSettings[style][elName] then
				module.DB.customSettings[style][elName] = {}
			end
			return module.DB.customSettings[style][elName]
		end
	end

	local function clearCustomElement(elName)
		local style = SUI:GetActiveStyle()
		if not module.DB.customSettings[style] then
			return
		end
		if SUI.IsRetail then
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
						return elementSettings.scale
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
						return elementSettings.alpha
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
						local elSettings = getElementSettings(elementName)
						if elSettings then
							elSettings.color = { r, g, b, a }
						end
						customPath.color = { r, g, b, a }
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
						local elSettings = getElementSettings(elementName)
						if elSettings then
							elSettings.spacing = val
						end
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
						local elSettings = getElementSettings(elementName)
						if elSettings then
							elSettings.xOffset = val
						end
						customPath.xOffset = val
						module:Update(true)
					end,
				}
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
									local addonBtnSettings = getElementSettings('addonButtons')
									if addonBtnSettings then
										addonBtnSettings.excludeList = value
									end
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
									local addonBtnSettings = getElementSettings('addonButtons')
									if addonBtnSettings then
										addonBtnSettings.autoHideDelay = value
									end
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
									local addonBtnSettings = getElementSettings('addonButtons')
									if addonBtnSettings then
										addonBtnSettings.excludeList = value
									end
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
