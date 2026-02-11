---@type SUI
local SUI = SUI
local L = SUI.L
---@class MoveIt
local MoveIt = SUI.MoveIt

-- Anchor point display names for options UI
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

local dynamicAnchorPoints = {
	['UIParent'] = 'Blizzard UI',
	['SpartanUI'] = 'Spartan UI',
	['SUI_BottomAnchor'] = 'SpartanUI Bottom Anchor',
	['SUI_TopAnchor'] = 'SpartanUI Top Anchor',
}

-- Expose for MoverFactory to use
MoveIt.anchorPoints = anchorPoints
MoveIt.dynamicAnchorPoints = dynamicAnchorPoints

local function GetPoints(obj)
	local point, anchor, secondaryPoint, x, y = obj:GetPoint()
	if not anchor then
		anchor = UIParent
	end

	return format('%s,%s,%s,%d,%d', point, anchor:GetName(), secondaryPoint, Round(x), Round(y))
end

local function CreateGroup(groupName)
	if SUI.opt.args.Movers.args[groupName] then
		return
	end

	SUI.opt.args.Movers.args[groupName] = {
		name = groupName,
		type = 'group',
		args = {},
	}
end

---Add a mover to the options UI
---@param MoverName string
---@param DisplayName string
---@param groupName string
---@param MoverFrame Frame
function MoveIt:AddToOptions(MoverName, DisplayName, groupName, MoverFrame)
	CreateGroup(groupName)
	SUI.opt.args.Movers.args[groupName].args[MoverName] = {
		name = DisplayName,
		type = 'group',
		inline = true,
		args = {
			position = {
				name = L['Position'],
				type = 'group',
				inline = true,
				order = 2,
				args = {
					x = {
						name = L['X Offset'],
						order = 1,
						type = 'input',
						dialogControl = 'NumberEditBox',
						get = function()
							return tostring(select(4, strsplit(',', GetPoints(MoverFrame))))
						end,
						set = function(info, val)
							--Fetch current position
							local point, anchor, secondaryPoint, _, y = strsplit(',', GetPoints(MoverFrame))
							-- Move the frame and update the DB
							MoverFrame.parent:position(point, anchor, secondaryPoint, tonumber(val), y, true)
							MoveIt.DB.movers[MoverName].MovedPoints = format('%s,%s,%s,%s,%s', point, anchor, secondaryPoint, val, y)
						end,
					},
					y = {
						name = L['Y Offset'],
						order = 2,
						type = 'input',
						dialogControl = 'NumberEditBox',
						get = function()
							return tostring(select(5, strsplit(',', GetPoints(MoverFrame))))
						end,
						set = function(info, val)
							--Fetch current position
							local point, anchor, secondaryPoint, x, _ = strsplit(',', GetPoints(MoverFrame))
							-- Move the frame and update the DB
							MoverFrame.parent:position(point, anchor, secondaryPoint, x, tonumber(val), true)
							MoveIt.DB.movers[MoverName].MovedPoints = format('%s,%s,%s,%s,%s', point, anchor, secondaryPoint, x, val)
						end,
					},
					MyAnchorPoint = {
						order = 3,
						name = L['Point'],
						type = 'select',
						values = anchorPoints,
						get = function()
							return tostring(select(1, strsplit(',', GetPoints(MoverFrame))))
						end,
						set = function(info, val)
							--Fetch current position
							local _, anchor, secondaryPoint, x, y = strsplit(',', GetPoints(MoverFrame))
							-- Move the frame and update the DB
							MoverFrame.parent:position(val, anchor, val, x, y, true)
							MoveIt.DB.movers[MoverName].MovedPoints = format('%s,%s,%s,%s,%s', val, anchor, secondaryPoint, x, y)
						end,
					},
					AnchorTo = {
						order = 4,
						name = L['Anchor'],
						type = 'select',
						values = dynamicAnchorPoints,
						get = function()
							local anchor = tostring(select(2, strsplit(',', GetPoints(MoverFrame))))
							if not dynamicAnchorPoints[anchor] then
								dynamicAnchorPoints[anchor] = anchor
							end
							return anchor
						end,
						set = function(info, val)
							--Fetch current position
							local point, _, secondaryPoint, x, y = strsplit(',', GetPoints(MoverFrame))
							-- Move the frame and update the DB
							MoverFrame.parent:position(point, (_G[val] or UIParent), secondaryPoint, x, y, true)
							MoveIt.DB.movers[MoverName].MovedPoints = format('%s,%s,%s,%s,%s', point, (_G[val] or UIParent):GetName(), secondaryPoint, x, y)
						end,
					},
					ItsAnchorPoint = {
						order = 5,
						name = L['Secondary point'],
						type = 'select',
						values = anchorPoints,
						get = function()
							return tostring(select(3, strsplit(',', GetPoints(MoverFrame))))
						end,
						set = function(info, val)
							--Fetch current position
							local point, anchor, _, x, y = strsplit(',', GetPoints(MoverFrame))
							-- Move the frame and update the DB
							MoverFrame.parent:position(point, anchor, val, x, y, true)
							MoveIt.DB.movers[MoverName].MovedPoints = format('%s,%s,%s,%s,%s', point, anchor, val, x, y)
						end,
					},
				},
			},
			ResetPosition = {
				name = L['Reset position'],
				type = 'execute',
				order = 3,
				func = function()
					MoveIt:Reset(MoverName, true)
				end,
			},
			scale = {
				name = '',
				type = 'group',
				inline = true,
				order = 4,
				args = {
					scale = {
						name = L['Scale'],
						type = 'range',
						order = 1,
						min = 0.01,
						max = 2,
						width = 'double',
						step = 0.01,
						get = function()
							return SUI:round(MoverFrame:GetScale(), 2)
						end,
						set = function(info, val)
							MoveIt.DB.movers[MoverName].AdjustedScale = val
							MoverFrame.parent:scale(val, false, true)
						end,
					},
					ResetScale = {
						name = L['Reset Scale'],
						type = 'execute',
						order = 2,
						func = function()
							MoverFrame.parent:scale()
							MoveIt.DB.movers[MoverName].AdjustedScale = nil
						end,
					},
				},
			},
		},
	}
end

function MoveIt:Options()
	SUI.opt.args.Movers = {
		name = L['Movers'],
		type = 'group',
		order = 800,
		disabled = function()
			return SUI:IsModuleDisabled(MoveIt)
		end,
		args = {
			MoveIt = {
				name = L['Toggle movers'],
				type = 'execute',
				order = 1,
				func = function()
					MoveIt:MoveIt()
				end,
			},
			AltKey = {
				name = L['Allow Alt+Dragging to move frames'],
				type = 'toggle',
				width = 'double',
				order = 2,
				get = function(info)
					return MoveIt.DB.AltKey
				end,
				set = function(info, val)
					MoveIt.DB.AltKey = val
				end,
			},
			ResetIt = {
				name = L['Reset moved frames'],
				type = 'execute',
				order = 3,
				func = function()
					MoveIt:Reset()
				end,
			},
			line1 = { name = '', type = 'header', order = 49 },
			line2 = {
				name = L['Movement can also be initated with the chat command:'],
				type = 'description',
				order = 50,
				fontSize = 'large',
			},
			line3 = { name = '/sui move', type = 'description', order = 51, fontSize = 'medium' },
			line22 = { name = '', type = 'header', order = 51.1 },
			line4 = {
				name = '',
				type = 'description',
				order = 52,
				fontSize = 'large',
			},
			line5 = {
				name = L['When the movement system is enabled you can:'],
				type = 'description',
				order = 53,
				fontSize = 'large',
			},
			line6 = { name = '- ' .. L['Alt+Click a mover to reset it'], type = 'description', order = 53.5, fontSize = 'medium' },
			line7 = {
				name = '- ' .. L['Shift+Click a mover to temporarily hide it'],
				type = 'description',
				order = 54,
				fontSize = 'medium',
			},
			line7a = {
				name = "- Control+Click a mover to reset it's scale",
				type = 'description',
				order = 54.2,
				fontSize = 'medium',
			},
			line7b = { name = '', type = 'description', order = 54.99, fontSize = 'medium' },
			line8 = {
				name = '- ' .. L['Use the scroll wheel to move left and right 1 coord at a time'],
				type = 'description',
				order = 55,
				fontSize = 'medium',
			},
			line9 = {
				name = '- ' .. L['Hold Shift + use the scroll wheel to move up and down 1 coord at a time'],
				type = 'description',
				order = 56,
				fontSize = 'medium',
			},
			line9a = {
				name = '- ' .. L['Hold Alt + use the scroll wheel to scale the frame'],
				type = 'description',
				order = 56.5,
				fontSize = 'medium',
			},
			line10 = {
				name = '- ' .. L['Press ESCAPE to exit the movement system quickly.'],
				type = 'description',
				order = 57,
				fontSize = 'medium',
			},
			tips = {
				name = L['Display tips when using /sui move'],
				type = 'toggle',
				width = 'double',
				order = 70,
				get = function(info)
					return MoveIt.DB.tips
				end,
				set = function(info, val)
					MoveIt.DB.tips = val
				end,
			},
			-- EditMode Control Settings (Retail only)
			EditModeHeader = {
				name = 'EditMode Profile Management',
				type = 'header',
				order = 100,
				hidden = function()
					return not SUI.IsRetail or not EditModeManagerFrame
				end,
			},
			EditModeEnabled = {
				name = 'Allow SpartanUI to manage EditMode profiles',
				desc = 'When enabled, SpartanUI will create and manage EditMode profiles that match your SUI profile.',
				type = 'toggle',
				width = 'double',
				order = 101,
				hidden = function()
					return not SUI.IsRetail or not EditModeManagerFrame
				end,
				get = function(info)
					return MoveIt.DB.EditModeControl.Enabled
				end,
				set = function(info, val)
					MoveIt.DB.EditModeControl.Enabled = val
				end,
			},
			EditModeAutoSwitch = {
				name = 'Auto-switch EditMode profile when changing SUI profile',
				desc = 'When enabled, switching your SpartanUI profile will also switch your EditMode profile.',
				type = 'toggle',
				width = 'double',
				order = 102,
				hidden = function()
					return not SUI.IsRetail or not EditModeManagerFrame
				end,
				disabled = function()
					return not MoveIt.DB.EditModeControl.Enabled
				end,
				get = function(info)
					return MoveIt.DB.EditModeControl.AutoSwitch
				end,
				set = function(info, val)
					MoveIt.DB.EditModeControl.AutoSwitch = val
				end,
			},
			EditModeCurrentProfile = {
				name = function()
					local profileName = MoveIt.DB.EditModeControl.CurrentProfile or 'Not set'
					return 'Current EditMode Profile: |cFFFFFF00' .. profileName .. '|r'
				end,
				type = 'description',
				order = 103,
				fontSize = 'medium',
				hidden = function()
					return not SUI.IsRetail or not EditModeManagerFrame
				end,
			},
			EditModeSelectProfile = {
				name = 'Select EditMode Profile',
				desc = 'Choose which EditMode profile to use with this SpartanUI profile. This profile will be automatically applied when you switch to this SUI profile or setup a new character.',
				type = 'select',
				width = 'double',
				order = 103.5,
				hidden = function()
					return not SUI.IsRetail or not EditModeManagerFrame
				end,
				disabled = function()
					return not MoveIt.DB.EditModeControl.Enabled
				end,
				values = function()
					local profiles = {}

					-- Get all available EditMode layouts
					local layoutInfo = C_EditMode.GetLayouts()
					if not layoutInfo or not layoutInfo.layouts then
						return profiles
					end

					-- Build dropdown list from available layouts
					for _, layout in ipairs(layoutInfo.layouts) do
						local layoutName = layout.layoutName
						local layoutType = layout.layoutType

						-- Add type prefix for clarity
						local displayName = layoutName
						if layoutType == Enum.EditModeLayoutType.Preset then
							displayName = '[Preset] ' .. layoutName
						elseif layoutType == Enum.EditModeLayoutType.Account then
							displayName = '[Account] ' .. layoutName
						elseif layoutType == Enum.EditModeLayoutType.Character then
							displayName = '[Character] ' .. layoutName
						end

						profiles[layoutName] = displayName
					end

					return profiles
				end,
				get = function(info)
					return MoveIt.DB.EditModeControl.CurrentProfile
				end,
				set = function(info, val)
					MoveIt.DB.EditModeControl.CurrentProfile = val

					-- Apply the selected profile immediately if enabled
					if MoveIt.DB.EditModeControl.Enabled and MoveIt.BlizzardEditMode then
						if MoveIt.logger then
							MoveIt.logger.info(('Manually set EditMode profile to "%s"'):format(val))
						end

						-- Switch to the selected profile
						MoveIt.BlizzardEditMode:SwitchToProfile(val)
					end
				end,
			},
			EditModeReapplyDefaults = {
				name = 'Re-apply SUI Default Positions',
				desc = 'Re-apply SpartanUI default frame positions to the current EditMode profile.',
				type = 'execute',
				order = 104,
				hidden = function()
					return not SUI.IsRetail or not EditModeManagerFrame
				end,
				disabled = function()
					return not MoveIt.DB.EditModeControl.Enabled
				end,
				func = function()
					if MoveIt.BlizzardEditMode then
						MoveIt.BlizzardEditMode:ApplyDefaultPositions()
						MoveIt.BlizzardEditMode:SafeApplyChanges(true)
						if MoveIt.logger then
							MoveIt.logger.info('Re-applied SUI default positions to EditMode profile')
						end
					end
				end,
			},
		},
	}
end
