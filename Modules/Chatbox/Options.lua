---@class SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.Chatbox
local module = SUI:GetModule('Chatbox')

local function isBlacklistDuplicate(newString)
	for _, existingString in ipairs(module.DB.chatLog.blacklist.strings) do
		if newString:lower() == existingString:lower() then
			return true
		end
	end
	return false
end

local function applyBlacklistToHistory(blacklistString)
	local newHistory = {}
	local removed = 0
	for _, entry in ipairs(module.DB.chatLog.history) do
		if not string.find(entry.message:lower(), blacklistString:lower()) then
			table.insert(newHistory, entry)
		else
			removed = removed + 1
		end
	end
	if removed > 0 then
		SUI:Print(string.format(L['Removed %d entries containing %s'], removed, blacklistString))
	end
	module.DB.chatLog.history = newHistory
end

function module:BuildOptions()
	---@type AceConfig.OptionsTable
	local optTable = {
		type = 'group',
		name = L['Chatbox'],
		childGroups = 'tab',
		disabled = function()
			return SUI:IsModuleDisabled(module)
		end,
		get = function(info)
			return module.DB[info[#info]]
		end,
		set = function(info, val)
			module.DB[info[#info]] = val
		end,
		args = {
			----------------------------------------------------------------------------------------------------
			-- General Tab
			----------------------------------------------------------------------------------------------------
			general = {
				name = L['General'],
				type = 'group',
				order = 1,
				args = {
					timestampFormat = {
						name = L['Timestamp format'],
						type = 'select',
						order = 1,
						values = {
							[''] = 'Disabled',
							['%I:%M:%S %p'] = 'HH:MM:SS AM (12-hour)',
							['%I:%M:%S'] = 'HH:MM:SS (12-hour)',
							['%X'] = 'HH:MM:SS (24-hour)',
							['%I:%M'] = 'HH:MM (12-hour)',
							['%H:%M'] = 'HH:MM (24-hour)',
							['%M:%S'] = 'MM:SS',
						},
						get = function()
							return module.DB.timestampFormat
						end,
						set = function(_, val)
							module.DB.timestampFormat = val
						end,
					},
					playerlevel = {
						name = L['Display level'],
						type = 'toggle',
						order = 2,
						get = function()
							return module.DB.playerlevel
						end,
						set = function(_, val)
							module.DB.playerlevel = val
						end,
					},
					shortenChannelNames = {
						name = L['Shorten channel names'],
						type = 'toggle',
						order = 3,
						get = function()
							return module.DB.shortenChannelNames
						end,
						set = function(_, val)
							module.DB.shortenChannelNames = val
						end,
					},
					autoLeaverOutput = {
						name = L['Automatically output number of BG leavers to instance chat if over 15'],
						type = 'toggle',
						order = 4,
						width = 'double',
						get = function()
							return module.DB.autoLeaverOutput
						end,
						set = function(_, val)
							module.DB.autoLeaverOutput = val
						end,
					},
					linksHeader = {
						name = L['Links'],
						type = 'header',
						order = 10,
					},
					webLinks = {
						name = L['Clickable web link'],
						type = 'toggle',
						order = 11,
						get = function()
							return module.DB.webLinks
						end,
						set = function(_, val)
							module.DB.webLinks = val
						end,
					},
					LinkHover = {
						name = L['Hoveable game links'],
						type = 'toggle',
						order = 12,
						get = function()
							return module.DB.LinkHover
						end,
						set = function(_, val)
							module.DB.LinkHover = val
						end,
					},
					fontHeader = {
						name = L['Font'],
						type = 'header',
						order = 20,
					},
					fontFamily = {
						name = L['Font family'],
						desc = L['Change the font used in chat frames'],
						type = 'select',
						order = 21,
						dialogControl = 'LSM30_Font',
						values = function()
							return SUI.Lib.LSM:HashTable('font')
						end,
						get = function()
							return SUI.Font.DB.Modules.Chatbox.Face
						end,
						set = function(_, val)
							SUI.Font.DB.Modules.Chatbox.Face = val
							SUI.Font:Refresh('Chatbox')
						end,
					},
					fontOutline = {
						name = L['Font outline'],
						desc = L['Add an outline effect to chat text'],
						type = 'select',
						order = 22,
						values = {
							['outline'] = L['Outline'],
							['thickoutline'] = L['Thick outline'],
							['monochrome'] = L['Monochrome'],
							['none'] = L['None'],
						},
						get = function()
							return SUI.Font.DB.Modules.Chatbox.Type or 'outline'
						end,
						set = function(_, val)
							SUI.Font.DB.Modules.Chatbox.Type = val
							SUI.Font:Refresh('Chatbox')
						end,
					},
					uiHeader = {
						name = L['Appearance'],
						type = 'header',
						order = 30,
					},
					hideChatButtons = {
						name = L['Hide chat buttons'],
						desc = L['Hide the menu and voice channel buttons'],
						type = 'toggle',
						order = 31,
						get = function()
							return module.DB.hideChatButtons
						end,
						set = function(_, val)
							module.DB.hideChatButtons = val
							module:ApplyHideChatButtons()
						end,
					},
					hideSocialButton = {
						name = L['Hide social button'],
						desc = L['Hide the quick-join/social button'],
						type = 'toggle',
						order = 32,
						get = function()
							return module.DB.hideSocialButton
						end,
						set = function(_, val)
							module.DB.hideSocialButton = val
							module:ApplyHideSocialButton()
						end,
					},
					disableChatFade = {
						name = L['Disable chat fade'],
						desc = L['Keep chat text visible indefinitely'],
						type = 'toggle',
						order = 33,
						get = function()
							return module.DB.disableChatFade
						end,
						set = function(_, val)
							module.DB.disableChatFade = val
							module:ApplyDisableChatFade()
						end,
					},
					chatHistoryLines = {
						name = L['Chat history lines'],
						desc = L['Maximum number of lines to keep in chat history (default 128, max 4096)'],
						type = 'range',
						order = 34,
						min = 128,
						max = 4096,
						step = 128,
						get = function()
							return module.DB.chatHistoryLines
						end,
						set = function(_, val)
							module.DB.chatHistoryLines = val
							module:ApplyChatHistoryLines()
						end,
					},
					ChatCopyTip = {
						name = L['Show copy tooltip on tabs'],
						desc = L['Show Alt+Click, Shift+Click, and Shift+Ctrl+Click hints when hovering chat tabs'],
						type = 'toggle',
						order = 35,
						get = function()
							return module.DB.ChatCopyTip
						end,
						set = function(_, val)
							module.DB.ChatCopyTip = val
						end,
					},
				},
			},
			----------------------------------------------------------------------------------------------------
			-- Edit Box Tab
			----------------------------------------------------------------------------------------------------
			editBox = {
				name = L['Edit Box'],
				type = 'group',
				order = 2,
				args = {
					editBoxPosition = {
						name = L['Edit box position'],
						desc = L['Where to place the chat edit box'],
						type = 'select',
						order = 1,
						values = {
							['BELOW'] = L['Below chat'],
							['ABOVE'] = L['Above tabs'],
							['ABOVE_INSIDE'] = L['Inside top'],
							['BELOW_INSIDE'] = L['Inside bottom'],
						},
						get = function()
							if module.DB.EditBoxTop then
								return 'ABOVE'
							end
							return module.DB.editBoxPosition or 'BELOW'
						end,
						set = function(_, val)
							module.DB.editBoxPosition = val
							module.DB.EditBoxTop = (val == 'ABOVE')
							module:EditBoxPosition()
						end,
					},
					multiLineHeader = {
						name = L['Multi-line editing'],
						type = 'header',
						order = 10,
					},
					multiLineEnabled = {
						name = L['Enable multi-line editing'],
						desc = L['Use an expanded edit box that supports multiple lines of text'],
						type = 'toggle',
						order = 11,
						get = function()
							return module.DB.multiLine.enabled
						end,
						set = function(_, val)
							module.DB.multiLine.enabled = val
						end,
					},
					multiLineMaxLines = {
						name = L['Max visible lines'],
						desc = L['Maximum number of lines the edit box expands to'],
						type = 'range',
						order = 12,
						min = 1,
						max = 8,
						step = 1,
						disabled = function()
							return not module.DB.multiLine.enabled
						end,
						get = function()
							return module.DB.multiLine.maxLines
						end,
						set = function(_, val)
							module.DB.multiLine.maxLines = val
						end,
					},
					multiLineShowCharCounter = {
						name = L['Show character counter'],
						desc = L['Display character count on the edit box'],
						type = 'toggle',
						order = 13,
						get = function()
							return module.DB.multiLine.showCharCounter
						end,
						set = function(_, val)
							module.DB.multiLine.showCharCounter = val
						end,
					},
					multiLineShowChannelLabel = {
						name = L['Show channel label'],
						desc = L['Display the current chat channel name in the multi-line box'],
						type = 'toggle',
						order = 14,
						disabled = function()
							return not module.DB.multiLine.enabled
						end,
						get = function()
							return module.DB.multiLine.showChannelLabel
						end,
						set = function(_, val)
							module.DB.multiLine.showChannelLabel = val
						end,
					},
					multiLineShowLineBreakButton = {
						name = L['Show line break button'],
						desc = L['Display a button for inserting line breaks in multi-line mode'],
						type = 'toggle',
						order = 15,
						disabled = function()
							return not module.DB.multiLine.enabled
						end,
						get = function()
							return module.DB.multiLine.showLineBreakButton
						end,
						set = function(_, val)
							module.DB.multiLine.showLineBreakButton = val
						end,
					},
					multiLineOpacity = {
						name = L['Background opacity'],
						type = 'range',
						order = 16,
						min = 0.1,
						max = 1.0,
						step = 0.05,
						isPercent = true,
						disabled = function()
							return not module.DB.multiLine.enabled
						end,
						get = function()
							return module.DB.multiLine.opacity
						end,
						set = function(_, val)
							module.DB.multiLine.opacity = val
						end,
					},
					historyHeader = {
						name = L['History'],
						type = 'header',
						order = 20,
					},
					historySize = {
						name = L['Edit history size'],
						desc = L['Number of previously sent messages to remember (Up/Down arrows)'],
						type = 'range',
						order = 21,
						min = 50,
						max = 500,
						step = 50,
						get = function()
							return module.DB.multiLine.historySize
						end,
						set = function(_, val)
							module.DB.multiLine.historySize = val
						end,
					},
				},
			},
			----------------------------------------------------------------------------------------------------
			-- Copy Tab
			----------------------------------------------------------------------------------------------------
			copy = {
				name = L['Copy'],
				type = 'group',
				order = 3,
				args = {
					copyButtonHeader = {
						name = L['Copy button'],
						type = 'header',
						order = 1,
					},
					copyButtonEnabled = {
						name = L['Show copy button'],
						desc = L['Show a clickable icon on chat frames to copy all chat text'],
						type = 'toggle',
						order = 2,
						get = function()
							return module.DB.copyButton.enabled
						end,
						set = function(_, val)
							module.DB.copyButton.enabled = val
						end,
					},
					copyButtonPosition = {
						name = L['Button position'],
						type = 'select',
						order = 3,
						disabled = function()
							return not module.DB.copyButton.enabled
						end,
						values = {
							['TOPRIGHT'] = L['Top right'],
							['TOPLEFT'] = L['Top left'],
						},
						get = function()
							return module.DB.copyButton.position
						end,
						set = function(_, val)
							module.DB.copyButton.position = val
						end,
					},
					lineHeader = {
						name = L['Line copy'],
						type = 'header',
						order = 10,
					},
					clickToCopyLine = {
						name = L['Click-to-copy lines'],
						desc = L['Add a small [C] marker to each chat line that opens it in the copy popup when clicked'],
						type = 'toggle',
						order = 11,
						get = function()
							return module.DB.clickToCopyLine
						end,
						set = function(_, val)
							module.DB.clickToCopyLine = val
						end,
					},
				},
			},
			----------------------------------------------------------------------------------------------------
			-- Highlights Tab
			----------------------------------------------------------------------------------------------------
			highlights = {
				name = L['Highlights'],
				type = 'group',
				order = 4,
				args = {
					keywordHeader = {
						name = L['Keyword highlighting'],
						type = 'header',
						order = 1,
					},
					highlightEnabled = {
						name = L['Enable keyword highlighting'],
						desc = L['Highlight specific words in chat messages'],
						type = 'toggle',
						order = 2,
						get = function()
							return module.DB.highlights.enabled
						end,
						set = function(_, val)
							module.DB.highlights.enabled = val
							if module.CompileHighlightPatterns then
								module.CompileHighlightPatterns()
							end
						end,
					},
					highlightColor = {
						name = L['Highlight color'],
						type = 'color',
						order = 3,
						disabled = function()
							return not module.DB.highlights.enabled
						end,
						get = function()
							local c = module.DB.highlights.highlightColor
							return c.r, c.g, c.b
						end,
						set = function(_, r, g, b)
							module.DB.highlights.highlightColor = { r = r, g = g, b = b }
						end,
					},
					keywords = {
						name = L['Keywords (one per line)'],
						desc = L['Enter words to highlight, one per line'],
						type = 'input',
						order = 4,
						multiline = 5,
						width = 'full',
						disabled = function()
							return not module.DB.highlights.enabled
						end,
						get = function()
							return table.concat(module.DB.highlights.keywords, '\n')
						end,
						set = function(_, val)
							local keywords = {}
							for word in val:gmatch('[^\n]+') do
								word = strtrim(word)
								if word ~= '' then
									table.insert(keywords, word)
								end
							end
							module.DB.highlights.keywords = keywords
							if module.CompileHighlightPatterns then
								module.CompileHighlightPatterns()
							end
						end,
					},
					mentionHeader = {
						name = L['Mentions'],
						type = 'header',
						order = 10,
					},
					mentionsEnabled = {
						name = L['Highlight your name'],
						desc = L['Highlight messages that mention your character name'],
						type = 'toggle',
						order = 11,
						get = function()
							return module.DB.highlights.mentionsEnabled
						end,
						set = function(_, val)
							module.DB.highlights.mentionsEnabled = val
						end,
					},
					mentionsColor = {
						name = L['Mention color'],
						type = 'color',
						order = 12,
						disabled = function()
							return not module.DB.highlights.mentionsEnabled
						end,
						get = function()
							local c = module.DB.highlights.mentionsColor
							return c.r, c.g, c.b
						end,
						set = function(_, r, g, b)
							module.DB.highlights.mentionsColor = { r = r, g = g, b = b }
						end,
					},
					mentionsSound = {
						name = L['Sound alert'],
						desc = L['Play a sound when your name is mentioned'],
						type = 'select',
						order = 13,
						disabled = function()
							return not module.DB.highlights.mentionsEnabled
						end,
						values = {
							['None'] = L['None'],
							['RAID_WARNING'] = 'Raid Warning',
							['READY_CHECK'] = 'Ready Check',
							['IG_PLAYER_INVITE'] = 'Player Invite',
							['LEVELUPSOUND'] = 'Level Up',
							['QUESTCOMPLETED'] = 'Quest Completed',
						},
						get = function()
							return module.DB.highlights.mentionsSound
						end,
						set = function(_, val)
							module.DB.highlights.mentionsSound = val
						end,
					},
					soundThrottle = {
						name = L['Sound cooldown (seconds)'],
						desc = L['Minimum time between mention sound alerts'],
						type = 'range',
						order = 14,
						min = 1,
						max = 30,
						step = 1,
						disabled = function()
							return not module.DB.highlights.mentionsEnabled
						end,
						get = function()
							return module.DB.highlights.soundThrottle
						end,
						set = function(_, val)
							module.DB.highlights.soundThrottle = val
						end,
					},
					suppressInCombat = {
						name = L['Suppress sounds in combat'],
						desc = L['Do not play mention sounds while in combat'],
						type = 'toggle',
						order = 15,
						disabled = function()
							return not module.DB.highlights.mentionsEnabled
						end,
						get = function()
							return module.DB.highlights.suppressInCombat
						end,
						set = function(_, val)
							module.DB.highlights.suppressInCombat = val
						end,
					},
				},
			},
			----------------------------------------------------------------------------------------------------
			-- Interactions Tab
			----------------------------------------------------------------------------------------------------
			interactions = {
				name = L['Interactions'],
				type = 'group',
				order = 5,
				args = {
					altClickInvite = {
						name = L['Alt+Click to invite'],
						desc = L['Alt+Click a player name in chat to invite them to your group'],
						type = 'toggle',
						order = 1,
						get = function()
							return module.DB.altClickInvite
						end,
						set = function(_, val)
							module.DB.altClickInvite = val
						end,
					},
					tellTarget = {
						name = L['Enable /tt command'],
						desc = L['Type /tt to whisper your current target'],
						type = 'toggle',
						order = 2,
						get = function()
							return module.DB.tellTarget
						end,
						set = function(_, val)
							module.DB.tellTarget = val
						end,
					},
					channelSticky = {
						name = L['Sticky channels'],
						desc = L['Remember your last used chat channel when reopening the edit box'],
						type = 'toggle',
						order = 3,
						get = function()
							return module.DB.channelSticky
						end,
						set = function(_, val)
							module.DB.channelSticky = val
						end,
					},
					searchHeader = {
						name = L['Search'],
						type = 'header',
						order = 10,
					},
					searchEnabled = {
						name = L['Enable chat search'],
						desc = L['Search through chat history with Ctrl+F while the edit box is focused'],
						type = 'toggle',
						order = 11,
						get = function()
							return module.DB.search.enabled
						end,
						set = function(_, val)
							module.DB.search.enabled = val
						end,
					},
					spamHeader = {
						name = L['Spam'],
						type = 'header',
						order = 20,
					},
					spamThrottleEnabled = {
						name = L['Enable spam throttle'],
						desc = L['Hide repeated messages from the same player within a short time'],
						type = 'toggle',
						order = 21,
						get = function()
							return module.DB.spamThrottle.enabled
						end,
						set = function(_, val)
							module.DB.spamThrottle.enabled = val
						end,
					},
					spamThrottleWindow = {
						name = L['Time window (seconds)'],
						desc = L['How many seconds to watch for duplicate messages'],
						type = 'range',
						order = 22,
						min = 2,
						max = 30,
						step = 1,
						disabled = function()
							return not module.DB.spamThrottle.enabled
						end,
						get = function()
							return module.DB.spamThrottle.window
						end,
						set = function(_, val)
							module.DB.spamThrottle.window = val
						end,
					},
					spamThrottleThreshold = {
						name = L['Repeat threshold'],
						desc = L['How many identical messages before suppressing'],
						type = 'range',
						order = 23,
						min = 2,
						max = 10,
						step = 1,
						disabled = function()
							return not module.DB.spamThrottle.enabled
						end,
						get = function()
							return module.DB.spamThrottle.threshold
						end,
						set = function(_, val)
							module.DB.spamThrottle.threshold = val
						end,
					},
				},
			},
			----------------------------------------------------------------------------------------------------
			-- Chat Log Tab
			----------------------------------------------------------------------------------------------------
			chatLog = {
				name = L['Chat Log'],
				type = 'group',
				order = 6,
				args = {
					enable = {
						name = L['Enable Chat Log'],
						desc = L['Enable saving chat messages to a log'],
						type = 'toggle',
						get = function()
							return module.DB.chatLog.enabled
						end,
						set = function(_, val)
							module.DB.chatLog.enabled = val
							if val then
								module:EnableChatLog()
							else
								module:DisableChatLog()
							end
						end,
						order = 1,
					},
					clearLog = {
						name = L['Clear Chat Log'],
						desc = L['Clear all saved chat log entries'],
						type = 'execute',
						func = function()
							module:ClearChatLog()
						end,
						order = 2,
					},
					clearAllLogs = {
						name = L['Clear All Chat Logs'],
						desc = L['Clear all saved chat log entries from all profiles'],
						type = 'execute',
						func = function()
							module:ClearAllChatLogs()
						end,
						order = 2.5,
					},
					maxEntries = {
						name = L['Max Log Entries'],
						desc = L['Maximum number of chat log entries to keep'],
						type = 'range',
						disabled = function()
							return not module.DB.chatLog.enabled
						end,
						width = 'double',
						min = 1,
						max = 100,
						step = 1,
						get = function()
							return module.DB.chatLog.maxEntries
						end,
						set = function(_, val)
							module.DB.chatLog.maxEntries = val
							module:CleanupOldChatLog()
						end,
						order = 4,
					},
					expireDays = {
						name = L['Log Expiration (Days)'],
						desc = L['Number of days to keep chat log entries'],
						type = 'range',
						disabled = function()
							return not module.DB.chatLog.enabled
						end,
						width = 'double',
						min = 1,
						max = 90,
						step = 1,
						get = function()
							return module.DB.chatLog.expireDays
						end,
						set = function(_, val)
							module.DB.chatLog.expireDays = val
							module:CleanupOldChatLog()
						end,
						order = 5,
					},
					typesToLog = {
						name = L['Chat Types to Log'],
						type = 'multiselect',
						disabled = function()
							return not module.DB.chatLog.enabled
						end,
						values = {
							CHAT_MSG_SAY = L['Say'],
							CHAT_MSG_YELL = L['Yell'],
							CHAT_MSG_PARTY = L['Party'],
							CHAT_MSG_RAID = L['Raid'],
							CHAT_MSG_GUILD = L['Guild'],
							CHAT_MSG_OFFICER = L['Officer'],
							CHAT_MSG_WHISPER = L['Whisper'],
							CHAT_MSG_WHISPER_INFORM = L['Whisper Sent'],
							CHAT_MSG_INSTANCE_CHAT = L['Instance'],
							CHAT_MSG_CHANNEL = L['Channels'],
						},
						get = function(info, key)
							return module.DB.chatLog.typesToLog[key]
						end,
						set = function(info, key, value)
							module.DB.chatLog.typesToLog[key] = value
							module:EnableChatLog()
						end,
						order = 6,
					},
					blacklist = {
						name = L['Blacklist'],
						type = 'group',
						order = 7,
						inline = true,
						disabled = function()
							return not module.DB.chatLog.enabled
						end,
						args = {},
					},
				},
			},
		},
	}

	local function buildBlacklistOptions()
		local blacklistOpt = optTable.args.chatLog.args.blacklist.args
		table.wipe(blacklistOpt)

		blacklistOpt.desc = {
			name = L['Blacklisted strings will not be logged'],
			type = 'description',
			order = 1,
		}

		blacklistOpt.add = {
			name = L['Add Blacklist String'],
			desc = L['Add a string to the blacklist'],
			type = 'input',
			order = 2,
			set = function(_, val)
				if isBlacklistDuplicate(val) then
					SUI:Print(string.format(L["'%s' is already in the blacklist"], val))
				else
					table.insert(module.DB.chatLog.blacklist.strings, val)
					applyBlacklistToHistory(val)
					buildBlacklistOptions()
				end
			end,
		}

		blacklistOpt.list = {
			order = 3,
			type = 'group',
			inline = true,
			name = L['Blacklist'],
			args = {},
		}

		for index, entry in ipairs(module.DB.chatLog.blacklist.strings) do
			blacklistOpt.list.args[tostring(index) .. 'label'] = {
				type = 'description',
				width = 'double',
				fontSize = 'medium',
				order = index * 2 - 1,
				name = entry,
			}
			blacklistOpt.list.args[tostring(index)] = {
				type = 'execute',
				name = L['Delete'],
				width = 'half',
				order = index * 2,
				func = function()
					table.remove(module.DB.chatLog.blacklist.strings, index)
					buildBlacklistOptions()
				end,
			}
		end
	end

	buildBlacklistOptions()

	SUI.opt.args.Help.args.SUIModuleHelp.args.clearAllLogs = optTable.args.chatLog.args.clearAllLogs
	SUI.Options:AddOptions(optTable, 'Chatbox')
end
