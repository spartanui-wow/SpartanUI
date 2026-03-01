local SUI, L = SUI, SUI.L
---@class SUI.Module.TeleportAssist
local module = SUI:GetModule('TeleportAssist')
----------------------------------------------------------------------------------------------------

function module:BuildOptions()
	local DB = module.DB

	---@type AceConfig.OptionsTable
	local OptionTable = {
		type = 'group',
		name = L['Teleport Assist'],
		disabled = function()
			return SUI:IsModuleDisabled(module)
		end,
		args = {
			intro = {
				type = 'description',
				order = 1,
				fontSize = 'medium',
				name = L['Quick access panel for all your teleports, portals, and travel items.'] .. '\n\n' .. L['Use /tp to toggle the frame.'],
			},
			openFrame = {
				type = 'execute',
				name = L['Open Teleport Panel'],
				order = 2,
				func = function()
					module:ToggleTeleportAssist()
				end,
			},
			spacer1 = {
				type = 'header',
				name = L['Display Settings'],
				order = 10,
			},
			buttonsPerRow = {
				name = L['Buttons Per Row'],
				desc = L['Number of teleport buttons per row'],
				type = 'range',
				order = 11,
				min = 4,
				max = 12,
				step = 1,
				get = function()
					return SUI.DBM:Get(module, 'buttonsPerRow')
				end,
				set = function(_, val)
					SUI.DBM:Set(module, 'buttonsPerRow', val, function()
						if module.RefreshTeleportAssist then
							module:RefreshTeleportAssist()
						end
					end)
				end,
			},
			buttonSize = {
				name = L['Button Size'],
				desc = L['Size of teleport buttons in pixels'],
				type = 'range',
				order = 12,
				min = 24,
				max = 48,
				step = 2,
				get = function()
					return SUI.DBM:Get(module, 'buttonSize')
				end,
				set = function(_, val)
					SUI.DBM:Set(module, 'buttonSize', val, function()
						if module.RefreshTeleportAssist then
							module:RefreshTeleportAssist()
						end
					end)
				end,
			},
			frameScale = {
				name = L['Frame Scale'],
				desc = L['Scale of the teleport frame'],
				type = 'range',
				order = 13,
				min = 0.5,
				max = 2.0,
				step = 0.1,
				get = function()
					return SUI.DBM:Get(module, 'frameScale')
				end,
				set = function(_, val)
					SUI.DBM:Set(module, 'frameScale', val, function()
						if module.RefreshTeleportAssist then
							module:RefreshTeleportAssist()
						end
					end)
				end,
			},
			spacer2 = {
				type = 'header',
				name = L['Display Options'],
				order = 20,
			},
			displayMode = {
				name = L['Display Mode'],
				desc = L['Choose how teleports are displayed'],
				type = 'select',
				order = 21,
				values = {
					list = L['List'],
					grid = L['Grid'],
					compact = L['Compact'],
				},
				get = function()
					return SUI.DBM:Get(module, 'displayMode')
				end,
				set = function(_, val)
					SUI.DBM:Set(module, 'displayMode', val, function()
						if module.RefreshTeleportAssist then
							module:RefreshTeleportAssist()
						end
						if module.WorldMapIntegration and module.WorldMapIntegration.Refresh then
							module.WorldMapIntegration:Refresh()
						end
					end)
				end,
			},
			labelMode = {
				name = L['Label Mode'],
				desc = L['Choose how labels are displayed'],
				type = 'select',
				order = 22,
				values = {
					full = L['Show Full Labels'],
					abbreviated = L['Show Abbreviated Labels'],
					none = L['Hide Labels'],
				},
				get = function()
					return SUI.DBM:Get(module, 'labelMode')
				end,
				set = function(_, val)
					SUI.DBM:Set(module, 'labelMode', val, function()
						if module.RefreshTeleportAssist then
							module:RefreshTeleportAssist()
						end
						if module.WorldMapIntegration and module.WorldMapIntegration.Refresh then
							module.WorldMapIntegration:Refresh()
						end
					end)
				end,
			},
			hideHearthstoneLabels = {
				name = L['Hide Hearthstone Labels'],
				desc = L['Hide labels for hearthstone items only'],
				type = 'toggle',
				order = 23,
				get = function()
					return SUI.DBM:Get(module, 'hideHearthstoneLabels')
				end,
				set = function(_, val)
					SUI.DBM:Set(module, 'hideHearthstoneLabels', val, function()
						if module.RefreshTeleportAssist then
							module:RefreshTeleportAssist()
						end
						if module.WorldMapIntegration and module.WorldMapIntegration.Refresh then
							module.WorldMapIntegration:Refresh()
						end
					end)
				end,
			},
			showAllHearthstones = {
				name = L['Show All Hearthstones'],
				desc = L['Show all hearthstone variants, even if you do not own them'],
				type = 'toggle',
				order = 24,
				get = function()
					return SUI.DBM:Get(module, 'showAllHearthstones')
				end,
				set = function(_, val)
					SUI.DBM:Set(module, 'showAllHearthstones', val, function()
						if module.RefreshTeleportAssist then
							module:RefreshTeleportAssist()
						end
						if module.WorldMapIntegration and module.WorldMapIntegration.Refresh then
							module.WorldMapIntegration:Refresh()
						end
					end)
				end,
			},
			spacer2b = {
				type = 'header',
				name = L['Behavior'],
				order = 30,
			},
			showFavoritesFirst = {
				name = L['Show Favorites First'],
				desc = L['Display favorited teleports at the top of the list'],
				type = 'toggle',
				order = 31,
				get = function()
					return SUI.DBM:Get(module, 'showFavoritesFirst')
				end,
				set = function(_, val)
					SUI.DBM:Set(module, 'showFavoritesFirst', val, function()
						if module.RefreshTeleportAssist then
							module:RefreshTeleportAssist()
						end
						if module.WorldMapIntegration and module.WorldMapIntegration.Refresh then
							module.WorldMapIntegration:Refresh()
						end
					end)
				end,
			},
			hideUnavailable = {
				name = L['Hide Unavailable'],
				desc = L['Hide teleports that are not available to your character'],
				type = 'toggle',
				order = 32,
				get = function()
					return SUI.DBM:Get(module, 'hideUnavailable')
				end,
				set = function(_, val)
					SUI.DBM:Set(module, 'hideUnavailable', val, function()
						if module.RefreshTeleportAssist then
							module:RefreshTeleportAssist()
						end
						if module.WorldMapIntegration and module.WorldMapIntegration.Refresh then
							module.WorldMapIntegration:Refresh()
						end
					end)
				end,
			},
			showTooltips = {
				name = L['Show Tooltips'],
				desc = L['Show tooltips when hovering over teleport buttons'],
				type = 'toggle',
				order = 33,
				get = function()
					return SUI.DBM:Get(module, 'showTooltips')
				end,
				set = function(_, val)
					SUI.DBM:Set(module, 'showTooltips', val)
				end,
			},
			mapPinsHeader = {
				type = 'header',
				name = L['World Map Pins'],
				order = 24.5,
				hidden = function()
					return not SUI.IsRetail
				end,
			},
			showMapPins = {
				name = L['Show Map Pins'],
				desc = L['Show teleport destination pins on the world map'],
				type = 'toggle',
				order = 24.6,
				hidden = function()
					return not SUI.IsRetail
				end,
				get = function()
					return SUI.DBM:Get(module, 'showMapPins')
				end,
				set = function(_, val)
					SUI.DBM:Set(module, 'showMapPins', val, function()
						if module.WorldMapIntegration and module.WorldMapIntegration.RefreshPins then
							module.WorldMapIntegration:RefreshPins()
						end
					end)
				end,
			},
			mapPinSize = {
				name = L['Map Pin Size'],
				desc = L['Size of teleport pins on the world map'],
				type = 'range',
				order = 24.7,
				min = 10,
				max = 64,
				step = 2,
				hidden = function()
					return not SUI.IsRetail
				end,
				get = function()
					return SUI.DBM:Get(module, 'mapPinSize')
				end,
				set = function(_, val)
					SUI.DBM:Set(module, 'mapPinSize', val, function()
						if module.WorldMapIntegration and module.WorldMapIntegration.RefreshPins then
							module.WorldMapIntegration:RefreshPins()
						end
					end)
				end,
			},
			challengesHeader = {
				type = 'header',
				name = L['Mythic+ Integration'],
				order = 24.8,
				hidden = function()
					return not SUI.IsRetail
				end,
			},
			showChallengesButtons = {
				name = L['M+ Teleport Buttons'],
				desc = L['Show teleport buttons on dungeon icons in the Mythic+ window'],
				type = 'toggle',
				order = 24.9,
				hidden = function()
					return not SUI.IsRetail
				end,
				get = function()
					return SUI.DBM:Get(module, 'showChallengesButtons')
				end,
				set = function(_, val)
					SUI.DBM:Set(module, 'showChallengesButtons', val)
				end,
			},
			minimapHeader = {
				type = 'header',
				name = L['Minimap Button'],
				order = 25,
			},
			showMinimapButton = {
				name = L['Show Minimap Button'],
				desc = L['Show or hide the minimap button'],
				type = 'toggle',
				order = 26,
				width = 'full',
				get = function()
					return not DB.minimap.hide
				end,
				set = function(_, val)
					DB.minimap.hide = not val
					module:UpdateMinimapButton()
				end,
			},
			spacer3 = {
				type = 'header',
				name = '',
				order = 30,
			},
			clearFavorites = {
				type = 'execute',
				name = L['Clear All Favorites'],
				desc = L['Remove all favorites'],
				order = 32,
				confirm = true,
				confirmText = L['Are you sure you want to clear all favorites?'],
				func = function()
					local DBG = module.DBG
					table.wipe(DBG.favorites)
					module:UpdateSettings()
				end,
			},
		},
	}

	SUI.Options:AddOptions(OptionTable, 'TeleportAssist')
end
