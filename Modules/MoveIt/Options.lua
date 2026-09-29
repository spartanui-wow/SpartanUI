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

---Build and return a position+scale options table for the given mover.
---Used by AddToOptions (Movers page) and by UnitFrames to embed position controls per-frame.
---@param MoverName string
---@param DisplayName string
---@param MoverFrame Frame
---@return AceConfig.OptionsTable
function MoveIt:GetPositionOptionsTable(MoverName, DisplayName, MoverFrame)
	return {
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
							-- Read from DB instead of current frame position
							local savedPos = MoveIt.DB.movers[MoverName].MovedPoints or MoveIt.DB.movers[MoverName].defaultPoint
							if savedPos then
								return tostring(select(4, strsplit(',', savedPos)))
							end
							return tostring(select(4, strsplit(',', GetPoints(MoverFrame))))
						end,
						set = function(info, val)
							--Fetch current position from DB
							local savedPos = MoveIt.DB.movers[MoverName].MovedPoints or MoveIt.DB.movers[MoverName].defaultPoint or GetPoints(MoverFrame)
							local point, anchor, secondaryPoint, _, y = strsplit(',', savedPos)
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
							-- Read from DB instead of current frame position
							local savedPos = MoveIt.DB.movers[MoverName].MovedPoints or MoveIt.DB.movers[MoverName].defaultPoint
							if savedPos then
								return tostring(select(5, strsplit(',', savedPos)))
							end
							return tostring(select(5, strsplit(',', GetPoints(MoverFrame))))
						end,
						set = function(info, val)
							--Fetch current position from DB
							local savedPos = MoveIt.DB.movers[MoverName].MovedPoints or MoveIt.DB.movers[MoverName].defaultPoint or GetPoints(MoverFrame)
							local point, anchor, secondaryPoint, x, _ = strsplit(',', savedPos)
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
							-- Read from DB instead of current frame position
							local savedPos = MoveIt.DB.movers[MoverName].MovedPoints or MoveIt.DB.movers[MoverName].defaultPoint
							if savedPos then
								return tostring(select(1, strsplit(',', savedPos)))
							end
							return tostring(select(1, strsplit(',', GetPoints(MoverFrame))))
						end,
						set = function(info, val)
							--Fetch current position from DB
							local savedPos = MoveIt.DB.movers[MoverName].MovedPoints or MoveIt.DB.movers[MoverName].defaultPoint or GetPoints(MoverFrame)
							local _, anchor, secondaryPoint, x, y = strsplit(',', savedPos)
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
							-- Read from DB instead of current frame position
							local savedPos = MoveIt.DB.movers[MoverName].MovedPoints or MoveIt.DB.movers[MoverName].defaultPoint
							if savedPos then
								local anchor = tostring(select(2, strsplit(',', savedPos)))
								if not dynamicAnchorPoints[anchor] then
									dynamicAnchorPoints[anchor] = anchor
								end
								return anchor
							end
							local anchor = tostring(select(2, strsplit(',', GetPoints(MoverFrame))))
							if not dynamicAnchorPoints[anchor] then
								dynamicAnchorPoints[anchor] = anchor
							end
							return anchor
						end,
						set = function(info, val)
							--Fetch current position from DB
							local savedPos = MoveIt.DB.movers[MoverName].MovedPoints or MoveIt.DB.movers[MoverName].defaultPoint or GetPoints(MoverFrame)
							local point, _, secondaryPoint, x, y = strsplit(',', savedPos)
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
							-- Read from DB instead of current frame position
							local savedPos = MoveIt.DB.movers[MoverName].MovedPoints or MoveIt.DB.movers[MoverName].defaultPoint
							if savedPos then
								return tostring(select(3, strsplit(',', savedPos)))
							end
							return tostring(select(3, strsplit(',', GetPoints(MoverFrame))))
						end,
						set = function(info, val)
							--Fetch current position from DB
							local savedPos = MoveIt.DB.movers[MoverName].MovedPoints or MoveIt.DB.movers[MoverName].defaultPoint or GetPoints(MoverFrame)
							local point, anchor, _, x, y = strsplit(',', savedPos)
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

---Add a mover to the options UI
---@param MoverName string
---@param DisplayName string
---@param groupName string
---@param MoverFrame Frame
function MoveIt:AddToOptions(MoverName, DisplayName, groupName, MoverFrame)
	CreateGroup(groupName)
	SUI.opt.args.Movers.args[groupName].args[MoverName] = MoveIt:GetPositionOptionsTable(MoverName, DisplayName, MoverFrame)
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
			howTo = {
				name = L['Open frame moving with /sui move or the Toggle movers button. While it is open you can:'],
				type = 'description',
				order = 50,
				fontSize = 'medium',
			},
			howTo1 = { name = '- ' .. L['Drag a frame to move it. It lines up with other frames and the middle of your screen.'], type = 'description', order = 51, fontSize = 'medium' },
			howTo2 = { name = '- ' .. L['Click a frame to select it, then use the arrow keys to nudge it (hold Shift for bigger steps).'], type = 'description', order = 52, fontSize = 'medium' },
			howTo3 = { name = '- ' .. L['Right-click a frame for exact position, size, attaching and reset.'], type = 'description', order = 53, fontSize = 'medium' },
			howTo4 = { name = '- ' .. L['Hold Shift while dragging to keep a straight line, or Ctrl to stop snapping.'], type = 'description', order = 54, fontSize = 'medium' },
			howTo5 = { name = '- ' .. L['Scroll to nudge (Shift for up and down), Alt+scroll to change size.'], type = 'description', order = 55, fontSize = 'medium' },
			howTo6 = { name = '- ' .. L['Alt+click resets a frame, Ctrl+click resets its size, Shift+right-click hides its box.'], type = 'description', order = 56, fontSize = 'medium' },
			howTo7 = { name = '- ' .. L['Save and exit keeps your changes. Exit without saving puts everything back.'], type = 'description', order = 57, fontSize = 'medium' },
			tips = {
				name = L['Show the help line while moving frames'],
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
			-- Mover Settings
			MoverHeader = {
				name = 'Mover Settings',
				type = 'header',
				order = 100,
			},
			anchorMode = {
				name = 'Position Anchor Mode',
				desc = 'How frame positions are saved. This affects how frames behave when you change your screen resolution.\n\n'
					.. '|cFFFFFF00Always CENTER (legacy)|r: All frames anchor to screen center (old behavior).\n\n'
					.. '|cFFFFFF00Closest edge or center|r: Frames anchor to the nearest edge or center (5 anchors).\n\n'
					.. '|cFFFFFF00Closest edge or corner|r: Frames anchor to the nearest edge or corner (9 anchors, best for resolution changes).',
				type = 'select',
				width = 'double',
				order = 100.5,
				values = {
					center = 'Always CENTER (legacy)',
					cardinal = 'Closest edge or center (5 anchors)',
					corners = 'Closest edge or corner (9 anchors)',
				},
				get = function()
					return MoveIt.DB.anchorMode or 'corners'
				end,
				set = function(_, val)
					MoveIt.DB.anchorMode = val
				end,
			},
			GridMode = {
				name = L['Grid'],
				desc = L['Show a grid behind your frames while moving them.'],
				type = 'select',
				order = 101,
				values = { off = L['Off'], dim = L['Faint'], bright = L['Bright'] },
				get = function()
					return MoveIt.GridOverlay:GetMode()
				end,
				set = function(_, val)
					MoveIt.DB.GridMode = val
					MoveIt.GridOverlay:Refresh()
				end,
			},
			GridSpacing = {
				name = L['Grid spacing'],
				desc = L['Distance between grid lines.'],
				type = 'range',
				min = 8,
				max = 128,
				step = 4,
				order = 102,
				get = function()
					return MoveIt.DB.GridSpacing or 32
				end,
				set = function(_, val)
					MoveIt.DB.GridSpacing = val
					MoveIt.GridOverlay:Refresh()
				end,
			},
			GridSnapEnabled = {
				name = L['Snap to grid'],
				desc = L['Frames jump to the nearest grid line while you drag them.'],
				type = 'toggle',
				order = 103,
				get = function()
					return MoveIt.DB.GridSnapEnabled
				end,
				set = function(_, val)
					MoveIt.DB.GridSnapEnabled = val
				end,
			},
			ElementSnapEnabled = {
				name = L['Snap to frames'],
				desc = L['Line frames up with other frames and the middle and edges of your screen.'],
				type = 'toggle',
				order = 104,
				get = function()
					return MoveIt.DB.ElementSnapEnabled ~= false
				end,
				set = function(_, val)
					MoveIt.DB.ElementSnapEnabled = val
				end,
			},
			ShowCoordinates = {
				name = L['Show position'],
				desc = L["Show a frame's position on its box while you drag or select it."],
				type = 'toggle',
				order = 105,
				get = function()
					return MoveIt.DB.ShowCoordinates
				end,
				set = function(_, val)
					MoveIt.DB.ShowCoordinates = val
				end,
			},
			SeeThrough = {
				name = L['See-through'],
				desc = L['Make the frame boxes see-through so you can see the frames under them.'],
				type = 'toggle',
				order = 106,
				get = function()
					return MoveIt.DB.SeeThrough
				end,
				set = function(_, val)
					MoveIt.DB.SeeThrough = val
				end,
			},
			-- EditMode Profile Sync (Optional Feature)
			EditModeSyncHeader = {
				name = 'EditMode Profile Sync (Optional)',
				type = 'header',
				order = 200,
				hidden = function()
					return not SUI.IsRetail or not EditModeManagerFrame
				end,
			},
			EditModeSyncDescription = {
				name = "This feature allows SpartanUI profile changes to automatically switch your EditMode profile. This only affects frames SUI doesn't manage (Chat, objective tracker, etc.). SpartanUI frame positioning is handled by custom movers.",
				type = 'description',
				fontSize = 'medium',
				order = 201,
				hidden = function()
					return not SUI.IsRetail or not EditModeManagerFrame
				end,
			},
			SyncEditModeProfile = {
				name = 'Sync EditMode Profile',
				desc = 'Automatically switch EditMode profile when changing SUI profiles.',
				type = 'toggle',
				width = 'full',
				order = 202,
				hidden = function()
					return not SUI.IsRetail or not EditModeManagerFrame
				end,
				get = function(info)
					return MoveIt.DB.SyncEditModeProfile or false
				end,
				set = function(info, val)
					MoveIt.DB.SyncEditModeProfile = val
					-- Reinitialize EditModeProfileSync
					if MoveIt.EditModeProfileSync then
						MoveIt.EditModeProfileSync:Initialize()
					end
				end,
			},
			EditModeCurrentProfile = {
				name = function()
					if not MoveIt.EditModeProfileSync then
						return 'Current EditMode Profile: |cFFFF0000Not Available|r'
					end
					local profileName = MoveIt.EditModeProfileSync:GetCurrentProfile() or 'Not set'
					return 'Current EditMode Profile: |cFFFFFF00' .. profileName .. '|r'
				end,
				type = 'description',
				order = 203,
				fontSize = 'medium',
				hidden = function()
					return not SUI.IsRetail or not EditModeManagerFrame or not MoveIt.DB.SyncEditModeProfile
				end,
			},
			EditModeSelectProfile = {
				name = 'Select EditMode Profile',
				desc = 'Select which EditMode profile to use with this SpartanUI profile.',
				type = 'select',
				width = 'double',
				order = 204,
				hidden = function()
					return not SUI.IsRetail or not EditModeManagerFrame or not MoveIt.DB.SyncEditModeProfile
				end,
				values = function()
					if not MoveIt.EditModeProfileSync then
						return {}
					end

					local profiles = {}
					local availableProfiles = MoveIt.EditModeProfileSync:GetAvailableProfiles()

					for _, profile in ipairs(availableProfiles) do
						local displayName = profile.name
						if profile.type == Enum.EditModeLayoutType.Preset then
							displayName = '[Preset] ' .. profile.name
						elseif profile.type == Enum.EditModeLayoutType.Account then
							displayName = '[Account] ' .. profile.name
						elseif profile.type == Enum.EditModeLayoutType.Character then
							displayName = '[Character] ' .. profile.name
						end
						profiles[profile.name] = displayName
					end

					return profiles
				end,
				get = function(info)
					if not MoveIt.EditModeProfileSync then
						return nil
					end
					return MoveIt.EditModeProfileSync:GetCurrentProfile()
				end,
				set = function(info, val)
					if MoveIt.EditModeProfileSync then
						MoveIt.EditModeProfileSync:SwitchToProfile(val)
						print(('SpartanUI: Now using EditMode profile "%s"'):format(val))
					end
				end,
			},
		},
	}
end
