local _G, SUI, L = _G, SUI, SUI.L
local module = SUI:GetModule('Artwork') ---@type SUI.Module.Artwork
module.Trays = {}
local trayWatcher = CreateFrame('Frame')
local settings = {}
local skinTrayFrames = {} -- Skin-provided frame lists (not saved to DB)

---@class SUI.Module.MenuTrays.DB
local DbDefaults = {
	Trays = {},
}
local trayIDs = {
	'left',
	'right',
}

local SetBarVisibility = function(side, state)
	local bt4Positions = {
		['BT4BarStanceBar'] = 'left',
		['BT4BarPetBar'] = 'left',
		['MultiCastActionBarFrame'] = 'left',
		['BT4BarBagBar'] = 'right',
		['BT4BarMicroMenu'] = 'right',
	}
	if not module:GetTraySettings(side).enabled then
		return
	end

	-- Handle default BT4 frames (only if Bartender4 is installed and not moved by user)
	-- Without BT4, these frames aren't positioned in the trays, so don't touch them
	if SUI:IsAddonEnabled('Bartender4') then
		for k, v in pairs(bt4Positions) do
			if _G[k] and v == side then
				-- Check if frame has been moved by user - if so, don't manage its visibility
				local isMoved = (_G[k].isMoved and _G[k].isMoved()) or false
				if not isMoved then
					if state == 'hide' then
						_G[k]:Hide()
					elseif state == 'show' then
						_G[k]:Show()
					end
				end
			end
		end
	end

	-- Get combined frame list: skin-provided + user custom frames
	local allFrames = module:GetCombinedFrameList(side)
	if allFrames and allFrames ~= '' then
		local frames = { strsplit(',', allFrames) }
		for _, frameName in ipairs(frames) do
			local trimmed = strtrim(frameName)
			if trimmed ~= '' and _G[trimmed] then
				if state == 'hide' then
					_G[trimmed]:Hide()
				elseif state == 'show' then
					_G[trimmed]:Show()
				end
			end
		end
	end
end

local pendingTrayUpdate = false

local trayWatcherEvents = function()
	if InCombatLockdown() then
		pendingTrayUpdate = true
		return
	end

	pendingTrayUpdate = false

	-- Make sure we are in the right spot
	module:updateOffset()

	for _, key in ipairs(trayIDs) do
		if not module:GetTraySettings(key).enabled then
			module.Trays[key].expanded:Hide()
			module.Trays[key].collapsed:Hide()
		elseif module.CurrentSettings.SlidingTrays[key].collapsed then
			module.Trays[key].expanded:Hide()
			module.Trays[key].collapsed:Show()
			SetBarVisibility(key, 'hide')
		else
			module.Trays[key].expanded:Show()
			module.Trays[key].collapsed:Hide()
			SetBarVisibility(key, 'show')
		end
	end
end

function module:trayWatcherEvents()
	trayWatcherEvents()
end

local CollapseToggle = function(self)
	if InCombatLockdown() then
		SUI:Print(ERR_NOT_IN_COMBAT)
		return
	end

	local key = self.key
	if module.CurrentSettings.SlidingTrays[key].collapsed then
		if not module.DB.SlidingTrays then
			module.DB.SlidingTrays = {}
		end
		if not module.DB.SlidingTrays[key] then
			module.DB.SlidingTrays[key] = {}
		end
		module.DB.SlidingTrays[key].collapsed = false
		SUI.DBM:RefreshSettings(module)
		module.Trays[key].expanded:Show()
		module.Trays[key].collapsed:Hide()
		SetBarVisibility(key, 'show')
	else
		if not module.DB.SlidingTrays then
			module.DB.SlidingTrays = {}
		end
		if not module.DB.SlidingTrays[key] then
			module.DB.SlidingTrays[key] = {}
		end
		module.DB.SlidingTrays[key].collapsed = true
		SUI.DBM:RefreshSettings(module)
		module.Trays[key].expanded:Hide()
		module.Trays[key].collapsed:Show()
		SetBarVisibility(key, 'hide')
	end
end

-- Default tray settings with explicit coordinates for each orientation and state
local DefaultTraySettings = {
	trayImage = 'Interface\\AddOns\\SpartanUI\\images\\Trays.png',
	-- Order of number is left, right, top, bottom                                                                                                                                                                  │
	-- │   UpTex expanded: 78px, Right 512, top 0, bottom 47                                                                                                                                                            │
	-- │   UpTex Collapse:  78px, right 512, top 47, bottom 65                                                                                                                                                          │
	-- │   DownTex expanded: 78, 512, 47, 0                                                                                                                                                                             │
	-- │   DownTex collapse: 78, 512, 65, 47                                                                                                                                                                            │
	-- │   Left Expanded: 0, 47, 0, 434                                                                                                                                                                                 │
	-- │   Left Collapse: 47, 67, 0, 434

	-- Explicit coordinate definitions for each direction and state
	coordinates = {
		-- UP direction (default)
		up = {
			expanded = {
				background = { 0.15234375, 1, 0.0, 0.091796875 }, -- Expanded: 78,512,0,47
				arrowPosition = { 'BOTTOM', 0, 2 },
			},
			collapsed = {
				background = { 0.15234375, 1, 0.091796875, 0.126953125 }, -- Collapse: 78,512,47,65
				arrowPosition = { 'TOP', 0, -6 },
			},
		},
		-- DOWN direction
		down = {
			expanded = {
				background = { 0.15234375, 1, 0.091796875, 0 }, -- Expanded: 78,512,47,0
				arrowPosition = { 'TOP', 0, -2 },
			},
			collapsed = {
				background = { 0.15234375, 1, 0.126953125, 0.091796875 }, -- Collapse: 78,512,65,47
				arrowPosition = { 'BOTTOM', 0, 6 },
			},
		},
		-- LEFT direction
		left = {
			expanded = {
				background = { 0, 0.091796875, 0, 0.84765625 }, -- 0, 47, 0, 434
				arrowPosition = { 'RIGHT', -2, 0 },
			},
			collapsed = {
				background = { 0.091796875, 0.130859375, 0.0, 0.84765625 }, -- 47, 67, 0, 434
				arrowPosition = { 'LEFT', 6, 0 },
			},
		},
		-- RIGHT direction
		right = {
			expanded = {
				background = { 0.091796875, 0.0, 0, 0.84765625 }, -- 47, 0, 0, 434
				arrowPosition = { 'LEFT', 2, 0 },
			},
			collapsed = {
				background = { 0.130859375, 0.091796875, 0.0, 0.84765625 }, -- 67, 47, 0, 434
				arrowPosition = { 'RIGHT', -6, 0 },
			},
		},
	},
	-- Arrow icon coordinates
	arrows = {
		default = { 0.962890625, 0.98046875, 0.033203125, 0.06640625 }, -- 493,502,17,34
		mouseover = { 0.984375, 1.0, 0.033203125, 0.06640625 }, -- 504,512,17,34
	},
}

-- Artwork Stuff
function module:SlidingTrays(StyleSettings)
	-- Initialize DB if this is the first call
	if not module.TrayDB then
		module.TrayDB = SUI.SpartanUIDB:RegisterNamespace('MenuTrays', { profile = DbDefaults })
		module.TrayData = module.TrayDB.profile ---@type SUI.Module.MenuTrays.DB

		-- Register profile change callbacks
		module.TrayDB.RegisterCallback(module, 'OnProfileChanged', function()
			module.TrayData = module.TrayDB.profile
		end)
		module.TrayDB.RegisterCallback(module, 'OnProfileCopied', function()
			module.TrayData = module.TrayDB.profile
		end)
		module.TrayDB.RegisterCallback(module, 'OnProfileReset', function()
			module.TrayData = module.TrayDB.profile
		end)
	end

	-- Start with default settings
	settings = SUI:CopyTable({}, DefaultTraySettings)

	-- Apply skin settings if provided
	if StyleSettings then
		settings = SUI:CopyTable(settings, StyleSettings)
		-- Store the skin name and register the skin settings
		local skinName = SUI:GetActiveStyle()
		if not module.TrayData.Trays[skinName] then
			module.TrayData.Trays[skinName] = {}
		end
		-- Store skin defaults for this style
		module.TrayData.Trays[skinName].skinDefaults = StyleSettings
	end

	-- Store the current skin name for later use
	settings.currentSkin = SUI:GetActiveStyle()

	module:Options()

	-- Use provided tray image or default fallback
	local trayImage = settings.trayImage or 'Interface\\AddOns\\SpartanUI\\images\\Trays.png'

	for _, key in ipairs(trayIDs) do
		if not module.Trays[key] then
			local tray = CreateFrame('Frame', 'SlidingTray_' .. key, _G['SUI_Art_' .. SUI:GetActiveStyle()])
			tray:SetFrameStrata('BACKGROUND')
			tray:SetAlpha(0.8)
			tray:SetSize(400, 45)

			local expanded = CreateFrame('Frame', nil, tray)
			expanded:SetAllPoints()
			local collapsed = CreateFrame('Frame', nil, tray)
			collapsed:SetAllPoints()

			local bgExpanded = expanded:CreateTexture(nil, 'BACKGROUND')
			bgExpanded:SetAllPoints()

			local bgCollapsed = collapsed:CreateTexture(nil, 'BACKGROUND')
			bgCollapsed:SetPoint('TOPLEFT', tray)
			bgCollapsed:SetPoint('TOPRIGHT', tray)
			bgCollapsed:SetHeight(18)

			local btnUp = CreateFrame('BUTTON', nil, expanded)
			local UpTex = expanded:CreateTexture()
			local UpTexMouseover = expanded:CreateTexture()
			UpTex:Hide()
			UpTexMouseover:Hide()
			btnUp:SetSize(130, 9)
			UpTex:SetAllPoints(btnUp)
			UpTexMouseover:SetAllPoints(btnUp)
			btnUp:SetNormalTexture('')
			btnUp:SetHighlightTexture(UpTexMouseover)
			btnUp:SetPushedTexture('')
			btnUp:SetDisabledTexture('')
			btnUp:SetPoint('BOTTOM', tray, 'BOTTOM', 1, 2)

			local btnDown = CreateFrame('BUTTON', nil, collapsed)
			local DownTex = collapsed:CreateTexture()
			local DownTexMouseover = collapsed:CreateTexture()
			DownTex:Hide()
			DownTexMouseover:Hide()
			btnDown:SetSize(130, 9)
			DownTex:SetAllPoints(btnDown)
			DownTexMouseover:SetAllPoints(btnDown)
			btnDown:SetNormalTexture('')
			btnDown:SetHighlightTexture(DownTexMouseover)
			btnDown:SetPushedTexture('')
			btnDown:SetDisabledTexture('')
			btnDown:SetPoint('TOP', tray, 'TOP', 2, -6)

			btnUp.key = key
			btnDown.key = key
			btnUp:SetScript('OnClick', CollapseToggle)
			btnDown:SetScript('OnClick', CollapseToggle)

			expanded.bg = bgExpanded
			expanded.btnUp = btnUp
			expanded.texture = UpTex
			expanded.textureMouseover = UpTexMouseover

			collapsed.bg = bgCollapsed
			collapsed.btnDown = btnDown
			collapsed.texture = DownTex
			collapsed.textureMouseover = DownTexMouseover

			tray.expanded = expanded
			tray.collapsed = collapsed

			if module.CurrentSettings.SlidingTrays[key].collapsed then
				SetBarVisibility(key, 'hide')
			else
				SetBarVisibility(key, 'show')
			end

			module.Trays[key] = tray
		end

		-- Apply new coordinate-based settings
		module:ApplyTrayCoordinates(key, trayImage)
	end

	module.Trays.left:SetPoint('TOP', SUI_TopAnchor, 'TOP', -300, 0)
	module.Trays.right:SetPoint('TOP', SUI_TopAnchor, 'TOP', 300, 0)

	-- Update tray sizes from database settings
	module:UpdateTraySizes()

	-- Add trays to MoveIt system after initial positioning to avoid taint
	if SUI.MoveIt then
		for _, key in ipairs(trayIDs) do
			if module.Trays[key] then
				-- Set dirty dimensions for proper mover sizing
				module.Trays[key].dirtyWidth = module.Trays[key]:GetWidth()
				module.Trays[key].dirtyHeight = module.Trays[key]:GetHeight()
				SUI.MoveIt:CreateMover(module.Trays[key], 'MenuTray_' .. key, key:gsub('^%l', string.upper) .. ' Menu Tray', nil, 'Menu Trays')
			end
		end
	end

	trayWatcher:SetScript('OnEvent', function(self, event)
		if event == 'PLAYER_REGEN_ENABLED' then
			if pendingTrayUpdate then
				trayWatcherEvents()
			end
			return
		end
		trayWatcherEvents()
	end)
	trayWatcher:RegisterEvent('PLAYER_LOGIN')
	trayWatcher:RegisterEvent('PLAYER_ENTERING_WORLD')
	trayWatcher:RegisterEvent('ZONE_CHANGED')
	trayWatcher:RegisterEvent('ZONE_CHANGED_INDOORS')
	trayWatcher:RegisterEvent('ZONE_CHANGED_NEW_AREA')
	trayWatcher:RegisterEvent('UNIT_EXITED_VEHICLE')
	trayWatcher:RegisterEvent('PET_BATTLE_CLOSE')
	trayWatcher:RegisterEvent('PLAYER_REGEN_ENABLED')

	return module.Trays
end

function module:GetTraySettings(side)
	local currentSkin = SUI:GetActiveStyle()

	-- Initialize skin data if needed
	if not module.TrayData.Trays[currentSkin] then
		module.TrayData.Trays[currentSkin] = {}
	end

	-- Build settings hierarchy: base -> skin -> user
	local finalSettings = {
		enabled = true,
		size = { width = 410, height = 45 },
		collapseDirection = 'up',
		customFrames = '',
		color = { r = 1, g = 1, b = 1, a = 1 },
	}

	-- Apply skin defaults if they exist
	if module.TrayData.Trays[currentSkin].skinDefaults and module.TrayData.Trays[currentSkin].skinDefaults.defaultTrayColor then
		finalSettings.color = module.TrayData.Trays[currentSkin].skinDefaults.defaultTrayColor
	end

	-- Apply user settings if they exist
	if module.TrayData.Trays[currentSkin][side] then
		finalSettings = SUI:CopyTable(finalSettings, module.TrayData.Trays[currentSkin][side])
	end

	return finalSettings
end

function module:SetTraySettings(side, key, value)
	local currentSkin = SUI:GetActiveStyle()

	-- Initialize skin data if needed
	if not module.TrayData.Trays[currentSkin] then
		module.TrayData.Trays[currentSkin] = {}
	end
	if not module.TrayData.Trays[currentSkin][side] then
		module.TrayData.Trays[currentSkin][side] = {}
	end

	module.TrayData.Trays[currentSkin][side][key] = value
end

function module:Options()
	-- Ensure we have the DB initialized
	if not module.TrayData then
		return
	end

	-- Apply default color from style settings if provided and not already set by user
	if settings and settings.defaultTrayColor then
		for _, side in ipairs({ 'left', 'right' }) do
			local currentSettings = module:GetTraySettings(side)
			-- Only apply if user hasn't customized the color (check if it's still default)
			if currentSettings.color.r == 1 and currentSettings.color.g == 1 and currentSettings.color.b == 1 and currentSettings.color.a == 1 then
				module:SetTraySettings(side, 'color', settings.defaultTrayColor)
			end
		end
	end

	local function getFrameListColor(frameList)
		if not frameList or frameList == '' then
			return ''
		end
		local frames = { strsplit(',', frameList) }
		local allValid = true
		for _, frameName in ipairs(frames) do
			local trimmed = strtrim(frameName)
			if trimmed ~= '' and not _G[trimmed] then
				allValid = false
				break
			end
		end
		return allValid and '|cff00ff00' or '|cffff0000' -- green if valid, red if invalid
	end

	local function resetTrayToDefaults(side)
		-- Clear user settings for this side, which will fall back to skin defaults
		local currentSkin = SUI:GetActiveStyle()
		if module.TrayData.Trays[currentSkin] and module.TrayData.Trays[currentSkin][side] then
			module.TrayData.Trays[currentSkin][side] = nil
		end
		-- Update the trays immediately
		if module.Trays and module.Trays[side] and settings then
			module:ApplyTrayCoordinates(side, settings.trayImage)
			module:UpdateTraySizes()
			trayWatcherEvents()
		end
	end

	SUI.opt.args.Artwork.args.Trays = {
		name = L['Slider Trays'],
		type = 'group',
		args = {
			-- Left Tray
			LeftTrayGroup = {
				name = L['Left Tray'],
				type = 'group',
				inline = true,
				order = 1,
				args = {
					enabled = {
						name = L['Enable left tray'],
						type = 'toggle',
						order = 1,
						get = function(info)
							return module:GetTraySettings('left').enabled
						end,
						set = function(info, val)
							module:SetTraySettings('left', 'enabled', val)
							trayWatcherEvents() -- Update visibility immediately
						end,
					},
					size = {
						name = L['Tray Size'],
						type = 'group',
						inline = true,
						order = 2,
						hidden = function()
							return not module:GetTraySettings('left').enabled
						end,
						args = {
							width = {
								name = L['Width'],
								type = 'range',
								order = 1,
								min = 50,
								max = 1300,
								step = 5,
								get = function(info)
									return module:GetTraySettings('left').size.width
								end,
								set = function(info, val)
									local size = module:GetTraySettings('left').size
									size.width = val
									module:SetTraySettings('left', 'size', size)
									module:UpdateTraySizes()
									module:updateOffset()
								end,
							},
							height = {
								name = L['Height'],
								type = 'range',
								order = 2,
								min = 10,
								max = 150,
								step = 1,
								get = function(info)
									return module:GetTraySettings('left').size.height
								end,
								set = function(info, val)
									local size = module:GetTraySettings('left').size
									size.height = val
									module:SetTraySettings('left', 'size', size)
									module:UpdateTraySizes()
									module:updateOffset()
								end,
							},
						},
					},
					collapseDirection = {
						name = L['Collapse Direction'],
						type = 'select',
						order = 3,
						hidden = function()
							return not module:GetTraySettings('left').enabled
						end,
						values = {
							left = L['Left'],
							right = L['Right'],
							up = L['Up'],
							down = L['Down'],
						},
						get = function(info)
							return module:GetTraySettings('left').collapseDirection
						end,
						set = function(info, val)
							module:SetTraySettings('left', 'collapseDirection', val)
							module:UpdateTextureOrientations()
							module:UpdateArrowPositions()
							module:UpdateBackgroundPositions()
							if settings then
								local trayImage = settings.trayImage or 'Interface\\AddOns\\SpartanUI\\images\\Trays.png'
								module:ApplyTrayCoordinates('left', trayImage)
							end
							module:updateOffset()
						end,
					},
					frameManager = {
						name = L['Frame Manager'],
						type = 'group',
						inline = true,
						order = 4,
						hidden = function()
							return not module:GetTraySettings('left').enabled
						end,
						args = {
							description = {
								type = 'description',
								name = L['Manage which frames are hidden/shown with this tray. Skin-provided frames are shown in blue, custom frames in white.'],
								order = 1,
							},
							skinFrames = {
								name = function()
									local skinFrames = ''
									if skinTrayFrames[SUI:GetActiveStyle()] and skinTrayFrames[SUI:GetActiveStyle()].left then
										skinFrames = skinTrayFrames[SUI:GetActiveStyle()].left
									end
									return '|cff4A9AFF' .. L['Skin Frames'] .. '|r: ' .. (skinFrames ~= '' and skinFrames or L['None'])
								end,
								type = 'description',
								order = 2,
								width = 'full',
							},
							customFrames = {
								name = function()
									local frames = module:GetTraySettings('left').customFrames
									local color = getFrameListColor(frames)
									return color .. L['Custom Frames'] .. '|r'
								end,
								type = 'input',
								multiline = true,
								order = 3,
								width = 'full',
								desc = L['Comma-separated list of additional frame names to hide/show with this tray. Frame names will be colored: |cff00ff00green if found|r, |cffff0000red if not found|r.'],
								get = function(info)
									return module:GetTraySettings('left').customFrames
								end,
								set = function(info, val)
									module:SetTraySettings('left', 'customFrames', val)
								end,
							},
							addFrame = {
								name = L['Add Frame'],
								type = 'input',
								order = 4,
								desc = L['Enter frame name to add to custom frames list'],
								get = function()
									return ''
								end,
								set = function(info, val)
									if val and val ~= '' then
										local current = module:GetTraySettings('left').customFrames
										if current == '' then
											module:SetTraySettings('left', 'customFrames', val)
										else
											module:SetTraySettings('left', 'customFrames', current .. ',' .. val)
										end
									end
								end,
							},
							clearFrames = {
								name = L['Clear All Custom'],
								type = 'execute',
								order = 5,
								desc = L['Clear all custom frames from this tray'],
								func = function()
									module:SetTraySettings('left', 'customFrames', '')
								end,
							},
						},
					},
					color = {
						name = L['Tray Color'],
						type = 'color',
						order = 6,
						hasAlpha = true,
						hidden = function()
							return not module:GetTraySettings('left').enabled
						end,
						desc = L['Choose the color tint for the tray textures'],
						get = function(info)
							local color = module:GetTraySettings('left').color
							return color.r, color.g, color.b, color.a
						end,
						set = function(info, r, g, b, a)
							module:SetTraySettings('left', 'color', { r = r, g = g, b = b, a = a })
							if module.Trays and module.Trays.left and settings then
								local trayImage = settings.trayImage or 'Interface\\\\AddOns\\\\SpartanUI\\\\images\\\\Trays.png'
								module:ApplyTrayCoordinates('left', trayImage)
							end
						end,
					},
					resetToDefaults = {
						name = L['Reset to Defaults'],
						type = 'execute',
						order = 7,
						hidden = function()
							return not module:GetTraySettings('left').enabled
						end,
						desc = L['Reset this tray to default settings'],
						func = function()
							resetTrayToDefaults('left')
						end,
					},
				},
			},
			-- Right Tray
			RightTrayGroup = {
				name = L['Right Tray'],
				type = 'group',
				inline = true,
				order = 2,
				args = {
					enabled = {
						name = L['Enable right tray'],
						type = 'toggle',
						order = 1,
						get = function(info)
							return module:GetTraySettings('right').enabled
						end,
						set = function(info, val)
							module:SetTraySettings('right', 'enabled', val)
							trayWatcherEvents() -- Update visibility immediately
						end,
					},
					size = {
						name = L['Tray Size'],
						type = 'group',
						inline = true,
						order = 2,
						hidden = function()
							return not module:GetTraySettings('right').enabled
						end,
						args = {
							width = {
								name = L['Width'],
								type = 'range',
								order = 1,
								min = 50,
								max = 1300,
								step = 5,
								get = function(info)
									return module:GetTraySettings('right').size.width
								end,
								set = function(info, val)
									local size = module:GetTraySettings('right').size
									size.width = val
									module:SetTraySettings('right', 'size', size)
									module:UpdateTraySizes()
									module:updateOffset()
								end,
							},
							height = {
								name = L['Height'],
								type = 'range',
								order = 2,
								min = 10,
								max = 150,
								step = 1,
								get = function(info)
									return module:GetTraySettings('right').size.height
								end,
								set = function(info, val)
									local size = module:GetTraySettings('right').size
									size.height = val
									module:SetTraySettings('right', 'size', size)
									module:UpdateTraySizes()
									module:updateOffset()
								end,
							},
						},
					},
					collapseDirection = {
						name = L['Collapse Direction'],
						type = 'select',
						order = 3,
						hidden = function()
							return not module:GetTraySettings('right').enabled
						end,
						values = {
							left = L['Left'],
							right = L['Right'],
							up = L['Up'],
							down = L['Down'],
						},
						get = function(info)
							return module:GetTraySettings('right').collapseDirection
						end,
						set = function(info, val)
							module:SetTraySettings('right', 'collapseDirection', val)
							module:UpdateTextureOrientations()
							module:UpdateArrowPositions()
							module:UpdateBackgroundPositions()
							if settings then
								local trayImage = settings.trayImage or 'Interface\\AddOns\\SpartanUI\\images\\Trays.png'
								module:ApplyTrayCoordinates('right', trayImage)
							end
							module:updateOffset()
						end,
					},
					frameManager = {
						name = L['Frame Manager'],
						type = 'group',
						inline = true,
						order = 4,
						hidden = function()
							return not module:GetTraySettings('right').enabled
						end,
						args = {
							description = {
								type = 'description',
								name = L['Manage which frames are hidden/shown with this tray. Skin-provided frames are shown in blue, custom frames in white.'],
								order = 1,
							},
							skinFrames = {
								name = function()
									local skinFrames = ''
									if skinTrayFrames[SUI:GetActiveStyle()] and skinTrayFrames[SUI:GetActiveStyle()].right then
										skinFrames = skinTrayFrames[SUI:GetActiveStyle()].right
									end
									return '|cff4A9AFF' .. L['Skin Frames'] .. '|r: ' .. (skinFrames ~= '' and skinFrames or L['None'])
								end,
								type = 'description',
								order = 2,
								width = 'full',
							},
							customFrames = {
								name = function()
									local frames = module:GetTraySettings('right').customFrames
									local color = getFrameListColor(frames)
									return color .. L['Custom Frames'] .. '|r'
								end,
								type = 'input',
								multiline = true,
								order = 3,
								width = 'full',
								desc = L['Comma-separated list of additional frame names to hide/show with this tray. Frame names will be colored: |cff00ff00green if found|r, |cffff0000red if not found|r.'],
								get = function(info)
									return module:GetTraySettings('right').customFrames
								end,
								set = function(info, val)
									module:SetTraySettings('right', 'customFrames', val)
								end,
							},
							addFrame = {
								name = L['Add Frame'],
								type = 'input',
								order = 4,
								desc = L['Enter frame name to add to custom frames list'],
								get = function()
									return ''
								end,
								set = function(info, val)
									if val and val ~= '' then
										local current = module:GetTraySettings('right').customFrames
										if current == '' then
											module:SetTraySettings('right', 'customFrames', val)
										else
											module:SetTraySettings('right', 'customFrames', current .. ',' .. val)
										end
									end
								end,
							},
							clearFrames = {
								name = L['Clear All Custom'],
								type = 'execute',
								order = 5,
								desc = L['Clear all custom frames from this tray'],
								func = function()
									module:SetTraySettings('right', 'customFrames', '')
								end,
							},
						},
					},
					color = {
						name = L['Tray Color'],
						type = 'color',
						order = 6,
						hasAlpha = true,
						hidden = function()
							return not module:GetTraySettings('right').enabled
						end,
						desc = L['Choose the color tint for the tray textures'],
						get = function(info)
							local color = module:GetTraySettings('right').color
							return color.r, color.g, color.b, color.a
						end,
						set = function(info, r, g, b, a)
							module:SetTraySettings('right', 'color', { r = r, g = g, b = b, a = a })
							if module.Trays and module.Trays.right and settings then
								local trayImage = settings.trayImage or 'Interface\\\\AddOns\\\\SpartanUI\\\\images\\\\Trays.png'
								module:ApplyTrayCoordinates('right', trayImage)
							end
						end,
					},
					resetToDefaults = {
						name = L['Reset to Defaults'],
						type = 'execute',
						order = 7,
						hidden = function()
							return not module:GetTraySettings('right').enabled
						end,
						desc = L['Reset this tray to default settings'],
						func = function()
							resetTrayToDefaults('right')
						end,
					},
				},
			},
		},
	}
end

-- Apply coordinate-based tray settings based on collapse direction
function module:ApplyTrayCoordinates(key, trayImage)
	if not module.Trays[key] or not settings or not settings.coordinates then
		return
	end

	local tray = module.Trays[key]
	local traySettings = module:GetTraySettings(key)
	local direction = (traySettings and traySettings.collapseDirection) or 'up'

	-- Set textures to the tray image
	tray.expanded.bg:SetTexture(trayImage)
	tray.collapsed.bg:SetTexture(trayImage)
	tray.expanded.texture:SetTexture(trayImage)
	tray.expanded.textureMouseover:SetTexture(trayImage)
	tray.collapsed.texture:SetTexture(trayImage)
	tray.collapsed.textureMouseover:SetTexture(trayImage)

	-- Make sure textures are visible
	tray.expanded.texture:Show()
	tray.expanded.textureMouseover:Show()
	tray.collapsed.texture:Show()
	tray.collapsed.textureMouseover:Show()

	-- Apply color from database settings
	if traySettings and traySettings.color then
		local color = traySettings.color
		tray.expanded.bg:SetVertexColor(color.r, color.g, color.b, color.a or 1)
		tray.collapsed.bg:SetVertexColor(color.r, color.g, color.b, color.a or 1)
		tray.expanded.texture:SetVertexColor(color.r, color.g, color.b, color.a or 1)
		tray.expanded.textureMouseover:SetVertexColor(color.r, color.g, color.b, color.a or 1)
		tray.collapsed.texture:SetVertexColor(color.r, color.g, color.b, color.a or 1)
		tray.collapsed.textureMouseover:SetVertexColor(color.r, color.g, color.b, color.a or 1)
	end

	-- Get coordinates for the specified direction
	local coords = settings.coordinates[direction]
	if not coords then
		return
	end

	-- Apply expanded state coordinates
	if coords.expanded then
		if coords.expanded.background then
			tray.expanded.bg:SetTexCoord(unpack(coords.expanded.background))
		end
		-- Use the default arrow coordinates for the arrow icon, not the tray coordinates
		if settings.arrows and settings.arrows.default then
			tray.expanded.texture:SetTexCoord(unpack(settings.arrows.default))
		end
		if coords.expanded.arrowPosition then
			local pos = coords.expanded.arrowPosition
			tray.expanded.btnUp:ClearAllPoints()
			tray.expanded.btnUp:SetPoint(pos[1], tray, pos[1], pos[2] or 0, pos[3] or 0)
		end
	end

	-- Apply collapsed state coordinates
	if coords.collapsed then
		if coords.collapsed.background then
			tray.collapsed.bg:SetTexCoord(unpack(coords.collapsed.background))
		end
		-- Use the default arrow coordinates for the arrow icon, not the tray coordinates
		if settings.arrows and settings.arrows.default then
			tray.collapsed.texture:SetTexCoord(unpack(settings.arrows.default))
		end
		if coords.collapsed.arrowPosition then
			local pos = coords.collapsed.arrowPosition
			tray.collapsed.btnDown:ClearAllPoints()
			tray.collapsed.btnDown:SetPoint(pos[1], tray, pos[1], pos[2] or 0, pos[3] or 0)
		end
	end

	-- Apply mouseover arrow coordinates
	if settings.arrows and settings.arrows.mouseover then
		tray.expanded.textureMouseover:SetTexCoord(unpack(settings.arrows.mouseover))
		tray.collapsed.textureMouseover:SetTexCoord(unpack(settings.arrows.mouseover))
	end
end

-- Update tray sizes from database settings
function module:UpdateTraySizes()
	if not module.Trays then
		return
	end

	-- Update container dimensions based on collapse direction (this handles the actual SetSize)
	module:UpdateContainerDimensions()
	-- Update arrow positions and background positioning when tray sizes change
	module:UpdateArrowPositions()
	module:UpdateBackgroundPositions()
end

-- Update texture orientations based on collapse direction
function module:UpdateTextureOrientations()
	if not module.Trays or not settings then
		return
	end

	for _, key in ipairs(trayIDs) do
		if module.Trays[key] and module:GetTraySettings(key) then
			local direction = module:GetTraySettings(key).collapseDirection or 'up'

			-- Use arrow coordinates from settings
			local arrowDefault = settings.arrows and settings.arrows.default or { 0.962890625, 0.98046875, 0.033203125, 0.06640625 }
			local arrowMouseover = settings.arrows and settings.arrows.mouseover or { 0.984375, 1.0, 0.033203125, 0.06640625 }

			-- Use default arrow coordinates for both states - direction-specific positioning is handled in ApplyTrayCoordinates
			local expandedCoord = arrowDefault
			local collapsedCoord = arrowDefault

			-- Reset rotation for all directions - we'll rely on coordinate manipulation and container orientation
			module.Trays[key].expanded.texture:SetRotation(0)
			module.Trays[key].collapsed.texture:SetRotation(0)

			module.Trays[key].expanded.texture:SetTexCoord(unpack(expandedCoord))
			module.Trays[key].collapsed.texture:SetTexCoord(unpack(collapsedCoord))

			-- Apply mouseover coordinates
			module.Trays[key].expanded.textureMouseover:SetTexCoord(unpack(arrowMouseover))
			module.Trays[key].collapsed.textureMouseover:SetTexCoord(unpack(arrowMouseover))
		end
	end

	-- Update container dimensions for left/right collapse
	module:UpdateContainerDimensions()
	-- Update arrow positions after texture changes
	module:UpdateArrowPositions()
	-- Update background positioning after direction changes
	module:UpdateBackgroundPositions()
	-- Fix visibility after all changes
	module:trayWatcherEvents()
end

-- Update container dimensions - swap width/height for left/right collapse
function module:UpdateContainerDimensions()
	if not module.Trays then
		return
	end

	for _, key in ipairs(trayIDs) do
		if module.Trays[key] and module:GetTraySettings(key) then
			local direction = module:GetTraySettings(key).collapseDirection or 'up'
			local size = module:GetTraySettings(key).size
			local tray = module.Trays[key]

			if size and size.width and size.height then
				if direction == 'left' or direction == 'right' then
					-- For horizontal collapse, swap dimensions: width becomes height, height becomes width
					tray:SetSize(size.height, size.width)

					-- Update MoveIt mover dimensions to match
					if SUI.MoveIt then
						tray.dirtyWidth = size.height
						tray.dirtyHeight = size.width
						SUI.MoveIt:UpdateMover('MenuTray_' .. key, tray, false)
					end
				else
					-- For vertical collapse (up/down), use normal dimensions
					tray:SetSize(size.width, size.height)

					-- Update MoveIt mover dimensions to match
					if SUI.MoveIt then
						tray.dirtyWidth = size.width
						tray.dirtyHeight = size.height
						SUI.MoveIt:UpdateMover('MenuTray_' .. key, tray, false)
					end
				end
			end
		end
	end
end

-- Update arrow button positions and sizes based on tray size and collapse direction
function module:UpdateArrowPositions()
	if not module.Trays then
		return
	end

	for _, key in ipairs(trayIDs) do
		if module.Trays[key] and module:GetTraySettings(key) then
			local tray = module.Trays[key]
			local size = module:GetTraySettings(key).size
			local direction = module:GetTraySettings(key).collapseDirection or 'up'

			if size and size.width and size.height then
				local btnUp = tray.expanded.btnUp
				local btnDown = tray.collapsed.btnDown

				local arrowWidth, arrowHeight

				-- Clear existing points
				btnUp:ClearAllPoints()
				btnDown:ClearAllPoints()

				if direction == 'up' then
					-- UP: Arrow at bottom when expanded (to collapse up), arrow at top when collapsed (to expand down)
					arrowWidth = math.min(math.max(size.width * 0.33, 80), 200)
					arrowHeight = 9
					btnUp:SetPoint('BOTTOM', tray, 'BOTTOM', 0, 2) -- Collapse button at bottom
					btnDown:SetPoint('TOP', tray, 'TOP', 0, -6) -- Expand button at top when collapsed
				elseif direction == 'down' then
					-- DOWN: Arrow at top when expanded (to collapse down), arrow at bottom when collapsed (to expand up)
					arrowWidth = math.min(math.max(size.width * 0.33, 80), 200)
					arrowHeight = 9
					btnUp:SetPoint('TOP', tray, 'TOP', 0, -2) -- Collapse button at top
					btnDown:SetPoint('BOTTOM', tray, 'BOTTOM', 0, 6) -- Expand button at bottom when collapsed
				elseif direction == 'left' then
					-- LEFT: Arrow at right when expanded (to collapse left), arrow at left when collapsed (to expand right)
					arrowWidth = 9
					arrowHeight = math.min(math.max(size.height * 0.7, 20), 40)
					btnUp:SetPoint('RIGHT', tray, 'RIGHT', -2, 0) -- Collapse button at right
					btnDown:SetPoint('LEFT', tray, 'LEFT', 6, 0) -- Expand button at left when collapsed
				elseif direction == 'right' then
					-- RIGHT: Arrow at left when expanded (to collapse right), arrow at right when collapsed (to expand left)
					arrowWidth = 9
					arrowHeight = math.min(math.max(size.height * 0.7, 20), 40)
					btnUp:SetPoint('LEFT', tray, 'LEFT', 2, 0) -- Collapse button at left
					btnDown:SetPoint('RIGHT', tray, 'RIGHT', -6, 0) -- Expand button at right when collapsed
				else
					-- Default (up)
					arrowWidth = math.min(math.max(size.width * 0.33, 80), 200)
					arrowHeight = 9
					btnUp:SetPoint('BOTTOM', tray, 'BOTTOM', 0, 2)
					btnDown:SetPoint('TOP', tray, 'TOP', 0, -6)
				end

				-- Update button sizes
				btnUp:SetSize(arrowWidth, arrowHeight)
				btnDown:SetSize(arrowWidth, arrowHeight)
			end
		end
	end
end

-- Update collapsed background positioning based on collapse direction
function module:UpdateBackgroundPositions()
	if not module.Trays then
		return
	end

	for _, key in ipairs(trayIDs) do
		if module.Trays[key] and module:GetTraySettings(key) then
			local tray = module.Trays[key]
			local direction = module:GetTraySettings(key).collapseDirection or 'up'
			local bgCollapsed = tray.collapsed.bg

			-- Clear existing points
			bgCollapsed:ClearAllPoints()

			if direction == 'up' then
				-- Strip at top when collapsing up
				bgCollapsed:SetPoint('TOPLEFT', tray)
				bgCollapsed:SetPoint('TOPRIGHT', tray)
				bgCollapsed:SetHeight(18)
				bgCollapsed:SetWidth(0) -- Auto-width
			elseif direction == 'down' then
				-- Strip at bottom when collapsing down
				bgCollapsed:SetPoint('BOTTOMLEFT', tray)
				bgCollapsed:SetPoint('BOTTOMRIGHT', tray)
				bgCollapsed:SetHeight(18)
				bgCollapsed:SetWidth(0) -- Auto-width
			elseif direction == 'left' then
				-- Strip at left when collapsing left
				bgCollapsed:SetPoint('TOPLEFT', tray)
				bgCollapsed:SetPoint('BOTTOMLEFT', tray)
				bgCollapsed:SetWidth(18)
				bgCollapsed:SetHeight(0) -- Auto-height
			elseif direction == 'right' then
				-- Strip at right when collapsing right
				bgCollapsed:SetPoint('TOPRIGHT', tray)
				bgCollapsed:SetPoint('BOTTOMRIGHT', tray)
				bgCollapsed:SetWidth(18)
				bgCollapsed:SetHeight(0) -- Auto-height
			end
		end
	end
end

-- Register skin-provided tray frames (not saved to DB)
function module:RegisterSkinTrayFrames(styleName, frames)
	if not skinTrayFrames[styleName] then
		skinTrayFrames[styleName] = {}
	end
	skinTrayFrames[styleName] = frames
end

-- Get combined frame list: skin frames + user custom frames (filtering out moved frames)
function module:GetCombinedFrameList(side)
	local skinFrames = ''
	local userFrames = ''

	-- Get skin-provided frames for current style
	if skinTrayFrames[SUI:GetActiveStyle()] and skinTrayFrames[SUI:GetActiveStyle()][side] then
		skinFrames = skinTrayFrames[SUI:GetActiveStyle()][side]
	end

	-- Get user custom frames from DB
	userFrames = module:GetTraySettings(side).customFrames or ''

	-- Frames that should only be managed when Bartender4 is installed
	-- These are BT4 bars or Blizzard frames that BT4 positions
	local bt4OnlyFrames = {
		['BT4BarStanceBar'] = true,
		['BT4BarPetBar'] = true,
		['BT4BarBagBar'] = true,
		['BT4BarMicroMenu'] = true,
		['MultiCastActionBarFrame'] = true,
	}
	local hasBT4 = SUI:IsAddonEnabled('Bartender4')

	-- Filter out moved frames from skin frames
	local filteredSkinFrames = {}
	if skinFrames ~= '' then
		local frames = { strsplit(',', skinFrames) }
		for _, frameName in ipairs(frames) do
			local trimmed = strtrim(frameName)
			if trimmed ~= '' and _G[trimmed] then
				-- Skip BT4-only frames when Bartender4 is not installed
				if bt4OnlyFrames[trimmed] and not hasBT4 then
					-- Don't include this frame
				else
					-- Check if frame has been moved by user
					local isMoved = (_G[trimmed].isMoved and _G[trimmed].isMoved()) or false
					if not isMoved then
						table.insert(filteredSkinFrames, trimmed)
					end
				end
			end
		end
	end

	-- Combine them (filtered skin frames first, then user frames)
	local combined = {}
	if #filteredSkinFrames > 0 then
		table.insert(combined, table.concat(filteredSkinFrames, ','))
	end
	if userFrames ~= '' then
		table.insert(combined, userFrames)
	end

	return table.concat(combined, ',')
end
