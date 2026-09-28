local _, ns = ...
local M = ns.Messenger
local L = M.L

-- AceConfig options. Host-neutral: the host decides where the table is shown.

local MAX_CHANNEL_SLOTS = 12

---Joined numbered channels, in channel-number order. Community channels are left out.
---@return table[] { id = number, name = string }
local function JoinedChannels()
	local list = {}
	local data = { GetChannelList() }
	for i = 1, #data, 3 do
		local id, name = data[i], data[i + 1]
		if type(id) == 'number' and type(name) == 'string' and not name:find('^Community:') then
			list[#list + 1] = { id = id, name = name }
		end
	end
	return list
end

---Two toggles for one chat kind: bring it into Messenger, and whether the main chat keeps it.
---@param order number
---@param label string
---@param getRoute fun(): table|nil
---@param hidden? function
---@return table
local function RouteGroup(order, label, getRoute, hidden)
	return {
		type = 'group',
		inline = true,
		order = order,
		name = label,
		hidden = hidden,
		args = {
			capture = {
				type = 'toggle',
				order = 1,
				width = 'normal',
				name = L['Show in Messenger'],
				get = function()
					local route = getRoute()
					return route and route.capture
				end,
				set = function(_, value)
					local route = getRoute()
					if route then
						route.capture = value
						M:RoutesChanged()
					end
				end,
			},
			hide = {
				type = 'toggle',
				order = 2,
				width = 'double',
				name = L['Hide from the main chat window'],
				desc = L['When off, these messages show in both places.'],
				disabled = function()
					local route = getRoute()
					return not (route and route.capture)
				end,
				get = function()
					local route = getRoute()
					return route and route.hide
				end,
				set = function(_, value)
					local route = getRoute()
					if route then
						route.hide = value
						M:RoutesChanged()
					end
				end,
			},
		},
	}
end

---@return table
function M:BuildOptionsTable()
	local settings = function()
		return M.settings
	end

	local chats = {
		type = 'group',
		order = 2,
		name = L['Chats'],
		args = {
			about = {
				type = 'description',
				order = 0,
				fontSize = 'medium',
				name = L['Pick which chats become conversations in Messenger. Whispers are on to start with. Anything you turn on here gets its own conversation, and you choose whether the main chat window keeps showing it too.']
					.. '\n',
			},
			peopleHeader = { type = 'header', order = 1, name = L['People'] },
			groupHeader = { type = 'header', order = 20, name = L['Groups'] },
			publicHeader = { type = 'header', order = 40, name = L['Nearby'] },
			channelHeader = { type = 'header', order = 60, name = L['Channels'] },
			noChannels = {
				type = 'description',
				order = 61,
				name = L['You have not joined any channels.'],
				hidden = function()
					return #JoinedChannels() > 0
				end,
			},
		},
	}

	local orders = { WHISPER = 2, BN_WHISPER = 3, GUILD = 21, OFFICER = 22, PARTY = 23, RAID = 24, INSTANCE = 25, SAY = 41, YELL = 42, EMOTE = 43 }
	for _, kind in ipairs(M.Kinds) do
		if orders[kind.key] then
			chats.args[kind.key] = RouteGroup(orders[kind.key], kind.label, function()
				return M.settings.routes[kind.key]
			end)
		end
	end

	for slot = 1, MAX_CHANNEL_SLOTS do
		local function Channel()
			return JoinedChannels()[slot]
		end
		local group = RouteGroup(61 + slot, '', function()
			local channel = Channel()
			return channel and M.settings.channels[channel.name] or nil
		end, function()
			return Channel() == nil
		end)
		group.name = function()
			local channel = Channel()
			return channel and string.format('%d. %s', channel.id, channel.name) or ''
		end
		chats.args['channel' .. slot] = group
	end

	return {
		type = 'group',
		name = L['Messenger'],
		childGroups = 'tab',
		args = {
			open = {
				type = 'execute',
				order = 0,
				name = L['Open Messenger'],
				func = function()
					M:Open(nil, false)
				end,
			},
			general = {
				type = 'group',
				order = 1,
				name = L['General'],
				args = {
					onWhisper = {
						type = 'select',
						order = 1,
						width = 'double',
						name = L['When someone whispers you'],
						values = {
							alert = L['Show an alert'],
							open = L['Open Messenger right away'],
						},
						get = function()
							return settings().onWhisper
						end,
						set = function(_, value)
							settings().onWhisper = value
						end,
					},
					fontSize = {
						type = 'range',
						order = 10,
						name = L['Text size'],
						min = 9,
						max = 20,
						step = 1,
						get = function()
							return settings().fontSize
						end,
						set = function(_, value)
							settings().fontSize = value
							M.Theme.RefreshFonts()
						end,
					},
					alpha = {
						type = 'range',
						order = 11,
						name = L['Window background'],
						desc = L['How solid the window background is.'],
						min = 0.4,
						max = 1,
						step = 0.02,
						isPercent = true,
						get = function()
							return settings().window.alpha
						end,
						set = function(_, value)
							settings().window.alpha = value
							M:Fire('SETTINGS_CHANGED')
						end,
					},
					fadeWhileMoving = {
						type = 'range',
						order = 11.5,
						name = L['Fade while moving'],
						desc = L['How see-through Messenger gets while your character moves, so it covers less of the world. It stays solid while your mouse is over it or you are typing. 100% turns this off.'],
						min = 0.1,
						max = 1,
						step = 0.05,
						isPercent = true,
						get = function()
							return settings().fadeWhileMoving
						end,
						set = function(_, value)
							settings().fadeWhileMoving = value
						end,
					},
					timeFormat = {
						type = 'select',
						order = 12,
						name = L['Clock'],
						values = {
							auto = L['Same as the game clock'],
							['12'] = L['12 hour'],
							['24'] = L['24 hour'],
						},
						get = function()
							return settings().timeFormat
						end,
						set = function(_, value)
							settings().timeFormat = value
							M:Fire('FONTS_CHANGED')
						end,
					},
					emoji = {
						type = 'toggle',
						order = 19,
						width = 'double',
						name = L['Show emoji pictures'],
						desc = L['Turns codes like :) and :fire: into pictures, and adds an emoji button to the message box.'],
						hidden = function()
							return not (M.host and M.host.emojiPath)
						end,
						get = function()
							return settings().emoji
						end,
						set = function(_, value)
							settings().emoji = value
							M:Fire('SETTINGS_CHANGED')
						end,
					},
					minimap = {
						type = 'toggle',
						order = 20,
						width = 'double',
						name = L['Show a minimap button'],
						get = function()
							return not settings().minimap.hide
						end,
						set = function(_, value)
							M.UI.Launcher:SetMinimapShown(value)
						end,
					},
					toggleKey = {
						type = 'keybinding',
						order = 24,
						width = 'double',
						name = L['Key to open or close Messenger'],
						desc = L['Click, then press the key you want. Press Escape instead to clear it. This is the same key binding you can set under Key Bindings > AddOns, and it cannot be changed during combat.'],
						hidden = function()
							return not (M.host and M.host.toggleBinding)
						end,
						disabled = function()
							return InCombatLockdown()
						end,
						get = function()
							return GetBindingKey(M.host.toggleBinding)
						end,
						set = function(_, key)
							M.Integration:SetKey(M.host.toggleBinding, key)
						end,
					},
					replyKey = {
						type = 'toggle',
						order = 25,
						width = 'full',
						name = L['Your Reply key answers in Messenger'],
						desc = L['Hidden whispers do not reach the main chat, so the normal Reply key could answer the wrong person. With this on, your Reply key opens the last person who whispered you in Messenger. Your saved key bindings are not changed. Typing /r in the main chat box still uses the main chat.'],
						get = function()
							return settings().replyKey
						end,
						set = function(_, value)
							settings().replyKey = value
							M:Fire('SETTINGS_CHANGED')
						end,
					},
					takeOverWhispers = {
						type = 'toggle',
						order = 26,
						width = 'full',
						name = L['Whispers you start in the main chat open in Messenger'],
						desc = L['Typing /w Name, clicking a name or choosing Whisper moves you into Messenger. Heads up: while this is on, the main chat box may refuse to send during some boss fights and Mythic+ until you reload. Turn it off if that happens to you.'],
						get = function()
							return settings().takeOverWhispers
						end,
						set = function(_, value)
							settings().takeOverWhispers = value
						end,
					},
					keys = {
						type = 'description',
						order = 30,
						name = '\n'
							.. L['Tip: set keys for "Open Messenger" and "Reply to last whisper" in the game\'s Key Bindings, under AddOns. Shift-click an item while typing to link it. Type /messenger Name to start a conversation.'],
					},
				},
			},
			chats = chats,
			alerts = {
				type = 'group',
				order = 3,
				name = L['Alerts'],
				args = {
					peopleHeader = { type = 'header', order = 1, name = L['Whispers'] },
					peopleSound = {
						type = 'toggle',
						order = 2,
						name = L['Play a sound'],
						get = function()
							return settings().alerts.people.sound
						end,
						set = function(_, value)
							settings().alerts.people.sound = value
						end,
					},
					peopleToast = {
						type = 'toggle',
						order = 3,
						name = L['Show a pop-up'],
						get = function()
							return settings().alerts.people.toast
						end,
						set = function(_, value)
							settings().alerts.people.toast = value
						end,
					},
					peopleFlash = {
						type = 'toggle',
						order = 4,
						name = L['Flash the taskbar'],
						desc = L['Flashes the game icon when the game is in the background.'],
						get = function()
							return settings().alerts.people.flash
						end,
						set = function(_, value)
							settings().alerts.people.flash = value
						end,
					},
					roomsHeader = { type = 'header', order = 10, name = L['Group and channel chats'] },
					roomsSound = {
						type = 'toggle',
						order = 11,
						name = L['Play a sound'],
						get = function()
							return settings().alerts.rooms.sound
						end,
						set = function(_, value)
							settings().alerts.rooms.sound = value
						end,
					},
					roomsToast = {
						type = 'toggle',
						order = 12,
						name = L['Show a pop-up'],
						get = function()
							return settings().alerts.rooms.toast
						end,
						set = function(_, value)
							settings().alerts.rooms.toast = value
						end,
					},
					roomsFlash = {
						type = 'toggle',
						order = 13,
						name = L['Flash the taskbar'],
						get = function()
							return settings().alerts.rooms.flash
						end,
						set = function(_, value)
							settings().alerts.rooms.flash = value
						end,
					},
					combatHeader = { type = 'header', order = 20, name = L['Combat'] },
					holdInCombat = {
						type = 'toggle',
						order = 21,
						width = 'full',
						name = L['Hold alerts until combat ends'],
						desc = L['Messages are still saved. You get one pop-up after the fight.'],
						get = function()
							return settings().alerts.holdInCombat
						end,
						set = function(_, value)
							settings().alerts.holdInCombat = value
						end,
					},
					hideInCombat = {
						type = 'toggle',
						order = 22,
						width = 'full',
						name = L['Hide the Messenger window in combat'],
						desc = L['It comes back when combat ends.'],
						get = function()
							return settings().alerts.hideInCombat
						end,
						set = function(_, value)
							settings().alerts.hideInCombat = value
						end,
					},
					popupHeader = { type = 'header', order = 30, name = L['Pop-ups'] },
					toastDuration = {
						type = 'range',
						order = 31,
						name = L['Seconds on screen'],
						min = 3,
						max = 20,
						step = 1,
						get = function()
							return settings().alerts.toastDuration
						end,
						set = function(_, value)
							settings().alerts.toastDuration = value
						end,
					},
					moveToasts = {
						type = 'execute',
						order = 32,
						name = function()
							return M.UI.Toast:IsUnlocked() and L['Lock pop-up position'] or L['Move pop-ups']
						end,
						func = function()
							M.UI.Toast:SetUnlocked(not M.UI.Toast:IsUnlocked())
						end,
					},
				},
			},
			history = {
				type = 'group',
				order = 4,
				name = L['History'],
				args = {
					maxMessages = {
						type = 'range',
						order = 1,
						width = 'double',
						name = L['Messages to keep per conversation'],
						min = 100,
						max = 2000,
						step = 50,
						get = function()
							return settings().history.maxMessages
						end,
						set = function(_, value)
							settings().history.maxMessages = value
						end,
					},
					keepDays = {
						type = 'range',
						order = 2,
						width = 'double',
						name = L['Delete quiet conversations after (days)'],
						desc = L['Conversations with no new messages for this many days are removed at login. Pinned ones are kept. 0 keeps everything.'],
						min = 0,
						max = 365,
						step = 1,
						get = function()
							return settings().history.keepDays
						end,
						set = function(_, value)
							settings().history.keepDays = value
						end,
					},
					roomDays = {
						type = 'range',
						order = 3,
						width = 'double',
						name = L['Keep group and channel chat for (days)'],
						min = 1,
						max = 14,
						step = 1,
						get = function()
							return settings().history.roomDays
						end,
						set = function(_, value)
							settings().history.roomDays = value
						end,
					},
					deleteAll = {
						type = 'execute',
						order = 10,
						name = L['Delete all conversations'],
						confirm = true,
						confirmText = L['Delete every conversation and all saved messages? This cannot be undone.'],
						func = function()
							M.Store:DeleteAll()
						end,
					},
				},
			},
		},
	}
end
