---@class SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.Chatbox
local module = SUI:GetModule('Chatbox')

local function isBlacklistDuplicate(newString)
	for _, existingString in ipairs(module.CurrentSettings.chatLog.blacklist.strings) do
		if newString:lower() == existingString:lower() then
			return true
		end
	end
	return false
end

local function applyBlacklistToHistory(blacklistString)
	local newHistory = {}
	local removed = 0
	for _, entry in ipairs(module.ChatLog) do
		if not string.find(entry.message:lower(), blacklistString:lower()) then
			table.insert(newHistory, entry)
		else
			removed = removed + 1
		end
	end
	if removed > 0 then
		SUI:Print(string.format(L['Removed %d entries containing %s'], removed, blacklistString))
	end
	wipe(module.ChatLog)
	for _, entry in ipairs(newHistory) do
		table.insert(module.ChatLog, entry)
	end
end

local function deepEqual(a, b)
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= 'table' then
		return a == b
	end
	for k, v in pairs(a) do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function hasChanges()
	local db = module.DB
	local defaults = module.DBDefaults
	if not db or not defaults then
		return false
	end
	for k, v in pairs(defaults) do
		if not deepEqual(db[k], v) then
			return true
		end
	end
	return false
end

local function resetToDefaults()
	local db = module.DB
	if not db then
		return
	end
	wipe(db)
	module:ApplyChatSettings()
	module:RefreshChatAppearance()
	LibStub('AceConfigRegistry-3.0'):NotifyChange('SpartanUI')
end

function module:BuildOptions()
	---@type AceConfig.OptionsTable
	local optTable = {
		type = 'group',
		name = L['Chatbox'],
		childGroups = 'tab',
		disabled = function()
			return SUI:IsModuleDisabled(module) or module.Override
		end,
		get = function(info)
			return module.CurrentSettings[info[#info]]
		end,
		set = function(info, val)
			module.DB[info[#info]] = val
			SUI.DBM:RefreshSettings(module)
		end,
		args = {
			resetAll = {
				name = L['Reset to defaults'],
				desc = L['Reset all Chatbox settings back to their default values'],
				type = 'execute',
				order = 1000,
				hidden = function()
					return not hasChanges()
				end,
				func = resetToDefaults,
			},
			----------------------------------------------------------------------------------------------------
			-- General Tab
			----------------------------------------------------------------------------------------------------
			general = {
				name = L['General'],
				type = 'group',
				order = 1,
				args = {
					messageFormatPreset = {
						name = L['Message format'],
						width = 'full',
						type = 'select',
						order = 1,
						values = function()
							local vals = {}
							for k, v in pairs(module.FormatPresets) do
								vals[k] = v
							end
							vals['custom'] = L['Custom']
							return vals
						end,
						get = function()
							return module.CurrentSettings.messageFormatPreset or 'default'
						end,
						set = function(_, val)
							module.DB.messageFormatPreset = val
							if val ~= 'custom' and module.FormatPresets[val] then
								module.DB.messageFormat = module.FormatPresets[val]
							end
							module:RefreshChatAppearance()
							LibStub('AceConfigRegistry-3.0'):NotifyChange('SpartanUI')
						end,
					},
					messageFormat = {
						name = L['Format string'],
						desc = L['Tokens: %TIME% %CHANNEL% %CHARACTER% %MESSAGE%'],
						type = 'input',
						order = 2,
						width = 'full',
						get = function()
							return module.CurrentSettings.messageFormat
						end,
						set = function(_, val)
							module.DB.messageFormat = val
							module.DB.messageFormatPreset = 'custom'
							module:RefreshChatAppearance()
							LibStub('AceConfigRegistry-3.0'):NotifyChange('SpartanUI')
						end,
					},
					channelStyle = {
						name = L['Channel name style'],
						desc = L['How channel names appear in the %CHANNEL% token'],
						type = 'select',
						order = 3,
						values = {
							['short'] = 'G / T',
							['name'] = 'Guild / Trade',
							['full'] = 'Guild / Trade - City',
							['number'] = '2',
							['number_full'] = '2. Trade - City',
						},
						get = function()
							return module.CurrentSettings.channelStyle or 'short'
						end,
						set = function(_, val)
							module.DB.channelStyle = val
							module:RefreshChatAppearance()
						end,
					},
					channelIndicator = {
						name = L['Show channel indicator per channel'],
						desc = L['Choose which channels show the channel label. Channels with unique colors (like Guild) may not need one.'],
						type = 'group',
						inline = true,
						order = 3.5,
						args = {
							guild = {
								name = L['Guild'],
								type = 'toggle',
								order = 1,
								width = 'half',
								get = function()
									return module.CurrentSettings.channelIndicator.CHAT_MSG_GUILD ~= false
								end,
								set = function(_, val)
									module.DB.channelIndicator.CHAT_MSG_GUILD = val
									module.DB.channelIndicator.CHAT_MSG_OFFICER = val
									module:RefreshChatAppearance()
								end,
							},
							say = {
								name = L['Say'],
								type = 'toggle',
								order = 2,
								width = 'half',
								get = function()
									return module.CurrentSettings.channelIndicator.CHAT_MSG_SAY ~= false
								end,
								set = function(_, val)
									module.DB.channelIndicator.CHAT_MSG_SAY = val
									module:RefreshChatAppearance()
								end,
							},
							yell = {
								name = L['Yell'],
								type = 'toggle',
								order = 3,
								width = 'half',
								get = function()
									return module.CurrentSettings.channelIndicator.CHAT_MSG_YELL ~= false
								end,
								set = function(_, val)
									module.DB.channelIndicator.CHAT_MSG_YELL = val
									module:RefreshChatAppearance()
								end,
							},
							whisper = {
								name = L['Whisper'],
								type = 'toggle',
								order = 4,
								width = 'half',
								get = function()
									return module.CurrentSettings.channelIndicator.CHAT_MSG_WHISPER ~= false
								end,
								set = function(_, val)
									module.DB.channelIndicator.CHAT_MSG_WHISPER = val
									module.DB.channelIndicator.CHAT_MSG_WHISPER_INFORM = val
									module.DB.channelIndicator.CHAT_MSG_BN_WHISPER = val
									module.DB.channelIndicator.CHAT_MSG_BN_WHISPER_INFORM = val
									module:RefreshChatAppearance()
								end,
							},
							party = {
								name = L['Party'],
								type = 'toggle',
								order = 5,
								width = 'half',
								get = function()
									return module.CurrentSettings.channelIndicator.CHAT_MSG_PARTY ~= false
								end,
								set = function(_, val)
									module.DB.channelIndicator.CHAT_MSG_PARTY = val
									module.DB.channelIndicator.CHAT_MSG_PARTY_LEADER = val
									module:RefreshChatAppearance()
								end,
							},
							raid = {
								name = L['Raid'],
								type = 'toggle',
								order = 6,
								width = 'half',
								get = function()
									return module.CurrentSettings.channelIndicator.CHAT_MSG_RAID ~= false
								end,
								set = function(_, val)
									module.DB.channelIndicator.CHAT_MSG_RAID = val
									module.DB.channelIndicator.CHAT_MSG_RAID_LEADER = val
									module.DB.channelIndicator.CHAT_MSG_RAID_WARNING = val
									module:RefreshChatAppearance()
								end,
							},
							instance = {
								name = L['Instance'],
								type = 'toggle',
								order = 7,
								width = 'half',
								get = function()
									return module.CurrentSettings.channelIndicator.CHAT_MSG_INSTANCE_CHAT ~= false
								end,
								set = function(_, val)
									module.DB.channelIndicator.CHAT_MSG_INSTANCE_CHAT = val
									module.DB.channelIndicator.CHAT_MSG_INSTANCE_CHAT_LEADER = val
									module:RefreshChatAppearance()
								end,
							},
							emote = {
								name = L['Emote'],
								type = 'toggle',
								order = 8,
								width = 'half',
								get = function()
									return module.CurrentSettings.channelIndicator.CHAT_MSG_EMOTE ~= false
								end,
								set = function(_, val)
									module.DB.channelIndicator.CHAT_MSG_EMOTE = val
									module:RefreshChatAppearance()
								end,
							},
							dynamic = {
								name = L['Zone channels (Trade, General, etc.)'],
								type = 'toggle',
								order = 9,
								width = 'double',
								get = function()
									return module.CurrentSettings.channelIndicator.dynamicChannels ~= false
								end,
								set = function(_, val)
									module.DB.channelIndicator.dynamicChannels = val
									module:RefreshChatAppearance()
								end,
							},
						},
					},
					nameColorStyle = {
						name = L['Name color'],
						desc = L['How player names are colored in the %CHARACTER% token'],
						type = 'select',
						order = 4,
						values = {
							['class'] = L['Class color'],
							['none'] = L['No color'],
						},
						get = function()
							return module.CurrentSettings.nameColorStyle or 'class'
						end,
						set = function(_, val)
							module.DB.nameColorStyle = val
							module:RefreshChatAppearance()
						end,
					},
					metaColor = {
						name = L['Metadata color'],
						desc = L['Color of the timestamp, channel, and other prefix text'],
						type = 'color',
						order = 5,
						get = function()
							local c = module.CurrentSettings.metaColor or { r = 0.49, g = 0.49, b = 0.49 }
							return c.r, c.g, c.b
						end,
						set = function(_, r, g, b)
							module.DB.metaColor = { r = r, g = g, b = b }
							module:RefreshChatAppearance()
						end,
					},
					timestampFormat = {
						name = L['Time format'],
						type = 'select',
						order = 2.1,
						values = {
							[''] = 'Disabled',
							['%I:%M:%S'] = 'HH:MM:SS (12-hour)',
							['%X'] = 'HH:MM:SS (24-hour)',
							['%I:%M'] = 'HH:MM (12-hour)',
							['%H:%M'] = 'HH:MM (24-hour)',
							['%M:%S'] = 'MM:SS',
						},
						get = function()
							return module.CurrentSettings.timestampFormat
						end,
						set = function(_, val)
							module.DB.timestampFormat = val
							module:RefreshChatAppearance()
						end,
					},
					timestampShowAMPM = {
						name = L['Show AM/PM'],
						desc = L['Show AM/PM suffix on 12-hour time formats'],
						type = 'toggle',
						order = 2.2,
						hidden = function()
							local fmt = module.CurrentSettings.timestampFormat or ''
							return not fmt:find('%%I')
						end,
						get = function()
							return module.CurrentSettings.timestampShowAMPM
						end,
						set = function(_, val)
							module.DB.timestampShowAMPM = val
							module:RefreshChatAppearance()
						end,
					},
					playerlevel = {
						name = L['Show level in name'],
						desc = L['Shows level before name. Hidden when at max level or level is unknown.'],
						type = 'toggle',
						order = 4,
						get = function()
							return module.CurrentSettings.playerlevel
						end,
						set = function(_, val)
							module.DB.playerlevel = val
							module:RefreshChatAppearance()
						end,
					},
					headerButtonsHeader = {
						name = L['Header Buttons'],
						type = 'header',
						order = 6.5,
					},
					headerButtonsEnabled = {
						name = L['Show header buttons'],
						desc = L['Show icon buttons in the chat header bar'],
						type = 'toggle',
						order = 7,
						get = function()
							return module.CurrentSettings.headerButtons.enabled
						end,
						set = function(_, val)
							module.DB.headerButtons.enabled = val
							module:RefreshHeaderButtons()
						end,
					},
					tabSwitcherMode = {
						name = L['Tab switcher'],
						desc = L['How to open the tab switcher popup'],
						type = 'select',
						order = 7.5,
						hidden = function()
							return not module.CurrentSettings.headerButtons.enabled
						end,
						values = { hover = L['Mouseover'], click = L['Click'] },
						get = function()
							return module.CurrentSettings.headerButtons.tabSwitcherMode
						end,
						set = function(_, val)
							module.DB.headerButtons.tabSwitcherMode = val
							module:RefreshHeaderButtons()
						end,
					},
					headerButtonsButtonsHeader = {
						name = L['Buttons'],
						type = 'header',
						order = 11,
						hidden = function()
							return not module.CurrentSettings.headerButtons.enabled
						end,
					},
					btnSocial = {
						name = L['Social'],
						type = 'toggle',
						order = 11.1,
						hidden = function()
							return not module.CurrentSettings.headerButtons.enabled
						end,
						get = function()
							return module.CurrentSettings.headerButtons.buttons.social
						end,
						set = function(_, val)
							module.DB.headerButtons.buttons.social = val
							module:RefreshHeaderButtons()
						end,
					},
					btnCopy = {
						name = L['Copy'],
						type = 'toggle',
						order = 11.2,
						hidden = function()
							return not module.CurrentSettings.headerButtons.enabled
						end,
						get = function()
							return module.CurrentSettings.headerButtons.buttons.copy
						end,
						set = function(_, val)
							module.DB.headerButtons.buttons.copy = val
							module:RefreshHeaderButtons()
						end,
					},
					btnSearch = {
						name = L['Search'],
						type = 'toggle',
						order = 11.3,
						hidden = function()
							return not module.CurrentSettings.headerButtons.enabled
						end,
						get = function()
							return module.CurrentSettings.headerButtons.buttons.search
						end,
						set = function(_, val)
							module.DB.headerButtons.buttons.search = val
							module:RefreshHeaderButtons()
						end,
					},
					btnErrors = {
						name = L['Errors'],
						type = 'toggle',
						order = 11.35,
						hidden = function()
							return not module.CurrentSettings.headerButtons.enabled
						end,
						get = function()
							return module.CurrentSettings.headerButtons.buttons.errors
						end,
						set = function(_, val)
							module.DB.headerButtons.buttons.errors = val
							module:RefreshHeaderButtons()
						end,
					},
					btnEmoji = {
						name = L['Emoji'],
						type = 'toggle',
						order = 11.37,
						hidden = function()
							return not module.CurrentSettings.headerButtons.enabled
						end,
						get = function()
							return module.CurrentSettings.headerButtons.buttons.emoji
						end,
						set = function(_, val)
							module.DB.headerButtons.buttons.emoji = val
							module:RefreshHeaderButtons()
						end,
					},
					btnChannels = {
						name = L['Chat menu'],
						type = 'toggle',
						order = 11.4,
						hidden = function()
							return not module.CurrentSettings.headerButtons.enabled
						end,
						get = function()
							return module.CurrentSettings.headerButtons.buttons.channels
						end,
						set = function(_, val)
							module.DB.headerButtons.buttons.channels = val
							module:RefreshHeaderButtons()
						end,
					},
					btnVoice = {
						name = L['Voice'],
						type = 'toggle',
						order = 11.5,
						hidden = function()
							return not module.CurrentSettings.headerButtons.enabled
						end,
						get = function()
							return module.CurrentSettings.headerButtons.buttons.voice
						end,
						set = function(_, val)
							module.DB.headerButtons.buttons.voice = val
							module:RefreshHeaderButtons()
						end,
					},
					btnSettings = {
						name = L['Settings'],
						type = 'toggle',
						order = 11.6,
						hidden = function()
							return not module.CurrentSettings.headerButtons.enabled
						end,
						get = function()
							return module.CurrentSettings.headerButtons.buttons.settings
						end,
						set = function(_, val)
							module.DB.headerButtons.buttons.settings = val
							module:RefreshHeaderButtons()
						end,
					},
					linksHeader = {
						name = L['Links'],
						type = 'header',
						order = 15,
					},
					webLinks = {
						name = L['Clickable web link'],
						type = 'toggle',
						order = 16,
						get = function()
							return module.CurrentSettings.webLinks
						end,
						set = function(_, val)
							module.DB.webLinks = val
							SUI.DBM:RefreshSettings(module)
						end,
					},
					LinkHover = {
						name = L['Hoveable game links'],
						type = 'toggle',
						order = 17,
						get = function()
							return module.CurrentSettings.LinkHover
						end,
						set = function(_, val)
							module.DB.LinkHover = val
							SUI.DBM:RefreshSettings(module)
						end,
					},
					emoji = {
						name = L['Chat emoji'],
						desc = L['Replace text emoticons like :smile: and :D with icons'],
						type = 'toggle',
						order = 18,
						get = function()
							return module.CurrentSettings.emoji and module.CurrentSettings.emoji.enabled
						end,
						set = function(_, val)
							if not module.DB.emoji then
								module.DB.emoji = {}
							end
							module.DB.emoji.enabled = val
							SUI.DBM:RefreshSettings(module)
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
						hidden = function()
							return module.CurrentSettings.headerButtons.enabled
						end,
						get = function()
							return module.CurrentSettings.hideChatButtons
						end,
						set = function(_, val)
							module.DB.hideChatButtons = val
							module:ApplyHideChatButtons()
							SUI.DBM:RefreshSettings(module)
						end,
					},
					hideSocialButton = {
						name = L['Hide social button'],
						desc = L['Hide the quick-join/social button'],
						type = 'toggle',
						order = 32,
						hidden = function()
							return module.CurrentSettings.headerButtons.enabled
						end,
						get = function()
							return module.CurrentSettings.hideSocialButton
						end,
						set = function(_, val)
							module.DB.hideSocialButton = val
							module:ApplyHideSocialButton()
							SUI.DBM:RefreshSettings(module)
						end,
					},
					disableChatFade = {
						name = L['Disable chat fade'],
						desc = L['Keep chat text visible indefinitely'],
						type = 'toggle',
						order = 33,
						get = function()
							return module.CurrentSettings.disableChatFade
						end,
						set = function(_, val)
							module.DB.disableChatFade = val
							module:ApplyDisableChatFade()
							SUI.DBM:RefreshSettings(module)
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
							return module.CurrentSettings.chatHistoryLines
						end,
						set = function(_, val)
							module.DB.chatHistoryLines = val
							module:ApplyChatHistoryLines()
							SUI.DBM:RefreshSettings(module)
						end,
					},
					ChatCopyTip = {
						name = L['Show copy tooltip on tabs'],
						desc = L['Show Alt+Click, Shift+Click, and Shift+Ctrl+Click hints when hovering chat tabs'],
						type = 'toggle',
						order = 35,
						get = function()
							return module.CurrentSettings.ChatCopyTip
						end,
						set = function(_, val)
							module.DB.ChatCopyTip = val
							SUI.DBM:RefreshSettings(module)
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
					editBoxBgColor = {
						name = L['Background color'],
						desc = L['Background color for the edit box and search bar'],
						type = 'color',
						order = 0.5,
						hasAlpha = true,
						get = function()
							local c = module.CurrentSettings.editBoxBgColor or { r = 0.05, g = 0.05, b = 0.05, a = 0.7 }
							return c.r, c.g, c.b, c.a
						end,
						set = function(_, r, g, b, a)
							module.DB.editBoxBgColor = { r = r, g = g, b = b, a = a }
							module:RefreshEditBoxColors()
						end,
					},
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
							if module.CurrentSettings.EditBoxTop then
								return 'ABOVE'
							end
							return module.CurrentSettings.editBoxPosition or 'BELOW'
						end,
						set = function(_, val)
							module.DB.editBoxPosition = val
							module.DB.EditBoxTop = (val == 'ABOVE')
							module:EditBoxPosition()
							SUI.DBM:RefreshSettings(module)
							SUI.DBM:RefreshSettings(module)
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
							return module.CurrentSettings.multiLine.enabled
						end,
						set = function(_, val)
							module.DB.multiLine.enabled = val
							SUI.DBM:RefreshSettings(module)
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
							return not module.CurrentSettings.multiLine.enabled
						end,
						get = function()
							return module.CurrentSettings.multiLine.maxLines
						end,
						set = function(_, val)
							module.DB.multiLine.maxLines = val
							SUI.DBM:RefreshSettings(module)
						end,
					},
					multiLineShowCharCounter = {
						name = L['Show character counter'],
						desc = L['Display character count on the edit box'],
						type = 'toggle',
						order = 13,
						get = function()
							return module.CurrentSettings.multiLine.showCharCounter
						end,
						set = function(_, val)
							module.DB.multiLine.showCharCounter = val
							SUI.DBM:RefreshSettings(module)
						end,
					},
					multiLineShowChannelLabel = {
						name = L['Show channel label'],
						desc = L['Display the current chat channel name in the multi-line box'],
						type = 'toggle',
						order = 14,
						disabled = function()
							return not module.CurrentSettings.multiLine.enabled
						end,
						get = function()
							return module.CurrentSettings.multiLine.showChannelLabel
						end,
						set = function(_, val)
							module.DB.multiLine.showChannelLabel = val
							SUI.DBM:RefreshSettings(module)
						end,
					},
					multiLineShowLineBreakButton = {
						name = L['Show line break button'],
						desc = L['Display a button for inserting line breaks in multi-line mode'],
						type = 'toggle',
						order = 15,
						disabled = function()
							return not module.CurrentSettings.multiLine.enabled
						end,
						get = function()
							return module.CurrentSettings.multiLine.showLineBreakButton
						end,
						set = function(_, val)
							module.DB.multiLine.showLineBreakButton = val
							SUI.DBM:RefreshSettings(module)
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
							return not module.CurrentSettings.multiLine.enabled
						end,
						get = function()
							return module.CurrentSettings.multiLine.opacity
						end,
						set = function(_, val)
							module.DB.multiLine.opacity = val
							SUI.DBM:RefreshSettings(module)
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
							return module.CurrentSettings.multiLine.historySize
						end,
						set = function(_, val)
							module.DB.multiLine.historySize = val
							SUI.DBM:RefreshSettings(module)
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
					copyDesc = {
						name = L['Right-click the timestamp on any chat line to copy it. Alt+Click a chat tab to copy all messages in that tab.'],
						type = 'description',
						order = 1,
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
							return module.CurrentSettings.highlights.enabled
						end,
						set = function(_, val)
							module.DB.highlights.enabled = val
							if module.CompileHighlightPatterns then
								module.CompileHighlightPatterns()
								SUI.DBM:RefreshSettings(module)
							end
						end,
					},
					highlightColor = {
						name = L['Highlight color'],
						type = 'color',
						order = 3,
						disabled = function()
							return not module.CurrentSettings.highlights.enabled
						end,
						get = function()
							local c = module.CurrentSettings.highlights.highlightColor
							return c.r, c.g, c.b
						end,
						set = function(_, r, g, b)
							module.DB.highlights.highlightColor = { r = r, g = g, b = b }
							SUI.DBM:RefreshSettings(module)
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
							return not module.CurrentSettings.highlights.enabled
						end,
						get = function()
							return table.concat(module.CurrentSettings.highlights.keywords, '\n')
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
								SUI.DBM:RefreshSettings(module)
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
							return module.CurrentSettings.highlights.mentionsEnabled
						end,
						set = function(_, val)
							module.DB.highlights.mentionsEnabled = val
							SUI.DBM:RefreshSettings(module)
						end,
					},
					mentionsColor = {
						name = L['Mention color'],
						type = 'color',
						order = 12,
						disabled = function()
							return not module.CurrentSettings.highlights.mentionsEnabled
						end,
						get = function()
							local c = module.CurrentSettings.highlights.mentionsColor
							return c.r, c.g, c.b
						end,
						set = function(_, r, g, b)
							module.DB.highlights.mentionsColor = { r = r, g = g, b = b }
							SUI.DBM:RefreshSettings(module)
						end,
					},
					mentionsSound = {
						name = L['Sound alert'],
						desc = L['Play a sound when your name is mentioned'],
						type = 'select',
						order = 13,
						disabled = function()
							return not module.CurrentSettings.highlights.mentionsEnabled
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
							return module.CurrentSettings.highlights.mentionsSound
						end,
						set = function(_, val)
							module.DB.highlights.mentionsSound = val
							SUI.DBM:RefreshSettings(module)
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
							return not module.CurrentSettings.highlights.mentionsEnabled
						end,
						get = function()
							return module.CurrentSettings.highlights.soundThrottle
						end,
						set = function(_, val)
							module.DB.highlights.soundThrottle = val
							SUI.DBM:RefreshSettings(module)
						end,
					},
					suppressInCombat = {
						name = L['Suppress in combat'],
						desc = L['Suppress sounds and alerts while in combat'],
						type = 'toggle',
						order = 15,
						get = function()
							return module.CurrentSettings.highlights.suppressInCombat
						end,
						set = function(_, val)
							module.DB.highlights.suppressInCombat = val
							SUI.DBM:RefreshSettings(module)
						end,
					},
					flashHeader = {
						name = L['Taskbar flash'],
						type = 'header',
						order = 20,
					},
					flashOnMention = {
						name = L['Flash on mention or keyword'],
						desc = L['Flash the taskbar icon when your name or a keyword is mentioned'],
						type = 'toggle',
						order = 21,
						get = function()
							return module.CurrentSettings.highlights.flashOnMention
						end,
						set = function(_, val)
							module.DB.highlights.flashOnMention = val
							SUI.DBM:RefreshSettings(module)
						end,
					},
					flashOnWhisper = {
						name = L['Flash on whisper'],
						desc = L['Flash the taskbar icon when you receive a whisper'],
						type = 'toggle',
						order = 22,
						get = function()
							return module.CurrentSettings.highlights.flashOnWhisper
						end,
						set = function(_, val)
							module.DB.highlights.flashOnWhisper = val
							SUI.DBM:RefreshSettings(module)
						end,
					},
					popupHeader = {
						name = L['Popup alerts'],
						type = 'header',
						order = 30,
					},
					popupEnabled = {
						name = L['Enable popup alerts'],
						desc = L['Show a popup notification at the top of the screen for whispers, mentions, and keywords'],
						type = 'toggle',
						order = 31,
						get = function()
							return module.CurrentSettings.popupAlert.enabled
						end,
						set = function(_, val)
							module.DB.popupAlert.enabled = val
							SUI.DBM:RefreshSettings(module)
						end,
					},
					popupOnWhisper = {
						name = L['Trigger on whisper'],
						type = 'toggle',
						order = 32,
						disabled = function()
							return not module.CurrentSettings.popupAlert.enabled
						end,
						get = function()
							return module.CurrentSettings.popupAlert.triggerOnWhisper
						end,
						set = function(_, val)
							module.DB.popupAlert.triggerOnWhisper = val
							SUI.DBM:RefreshSettings(module)
						end,
					},
					popupOnMention = {
						name = L['Trigger on mention'],
						type = 'toggle',
						order = 33,
						disabled = function()
							return not module.CurrentSettings.popupAlert.enabled
						end,
						get = function()
							return module.CurrentSettings.popupAlert.triggerOnMention
						end,
						set = function(_, val)
							module.DB.popupAlert.triggerOnMention = val
							SUI.DBM:RefreshSettings(module)
						end,
					},
					popupOnKeyword = {
						name = L['Trigger on keyword'],
						type = 'toggle',
						order = 34,
						disabled = function()
							return not module.CurrentSettings.popupAlert.enabled
						end,
						get = function()
							return module.CurrentSettings.popupAlert.triggerOnKeyword
						end,
						set = function(_, val)
							module.DB.popupAlert.triggerOnKeyword = val
							SUI.DBM:RefreshSettings(module)
						end,
					},
					popupHoldDuration = {
						name = L['Hold duration (seconds)'],
						desc = L['How long the popup stays visible before fading out'],
						type = 'range',
						order = 35,
						min = 1,
						max = 15,
						step = 0.5,
						disabled = function()
							return not module.CurrentSettings.popupAlert.enabled
						end,
						get = function()
							return module.CurrentSettings.popupAlert.holdDuration
						end,
						set = function(_, val)
							module.DB.popupAlert.holdDuration = val
							SUI.DBM:RefreshSettings(module)
						end,
					},
					popupSuppressInCombat = {
						name = L['Suppress popup in combat'],
						type = 'toggle',
						order = 36,
						disabled = function()
							return not module.CurrentSettings.popupAlert.enabled
						end,
						get = function()
							return module.CurrentSettings.popupAlert.suppressInCombat
						end,
						set = function(_, val)
							module.DB.popupAlert.suppressInCombat = val
							SUI.DBM:RefreshSettings(module)
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
							return module.CurrentSettings.altClickInvite
						end,
						set = function(_, val)
							module.DB.altClickInvite = val
							SUI.DBM:RefreshSettings(module)
						end,
					},
					tellTarget = {
						name = L['Enable /tt command'],
						desc = L['Type /tt to whisper your current target'],
						type = 'toggle',
						order = 2,
						get = function()
							return module.CurrentSettings.tellTarget
						end,
						set = function(_, val)
							module.DB.tellTarget = val
							SUI.DBM:RefreshSettings(module)
						end,
					},
					channelSticky = {
						name = L['Sticky channels'],
						desc = L['Remember your last used chat channel when reopening the edit box'],
						type = 'toggle',
						order = 3,
						get = function()
							return module.CurrentSettings.channelSticky
						end,
						set = function(_, val)
							module.DB.channelSticky = val
							SUI.DBM:RefreshSettings(module)
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
							return module.CurrentSettings.search.enabled
						end,
						set = function(_, val)
							module.DB.search.enabled = val
							SUI.DBM:RefreshSettings(module)
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
							return module.CurrentSettings.spamThrottle.enabled
						end,
						set = function(_, val)
							module.DB.spamThrottle.enabled = val
							SUI.DBM:RefreshSettings(module)
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
							return not module.CurrentSettings.spamThrottle.enabled
						end,
						get = function()
							return module.CurrentSettings.spamThrottle.window
						end,
						set = function(_, val)
							module.DB.spamThrottle.window = val
							SUI.DBM:RefreshSettings(module)
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
							return not module.CurrentSettings.spamThrottle.enabled
						end,
						get = function()
							return module.CurrentSettings.spamThrottle.threshold
						end,
						set = function(_, val)
							module.DB.spamThrottle.threshold = val
							SUI.DBM:RefreshSettings(module)
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
							return module.CurrentSettings.chatLog.enabled
						end,
						set = function(_, val)
							module.DB.chatLog.enabled = val
							if val then
								module:EnableChatLog()
							else
								module:DisableChatLog()
								SUI.DBM:RefreshSettings(module)
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
							return not module.CurrentSettings.chatLog.enabled
						end,
						width = 'double',
						min = 1,
						max = 100,
						step = 1,
						get = function()
							return module.CurrentSettings.chatLog.maxEntries
						end,
						set = function(_, val)
							module.DB.chatLog.maxEntries = val
							module:CleanupOldChatLog()
							SUI.DBM:RefreshSettings(module)
						end,
						order = 4,
					},
					expireDays = {
						name = L['Log Expiration (Days)'],
						desc = L['Number of days to keep chat log entries'],
						type = 'range',
						disabled = function()
							return not module.CurrentSettings.chatLog.enabled
						end,
						width = 'double',
						min = 1,
						max = 90,
						step = 1,
						get = function()
							return module.CurrentSettings.chatLog.expireDays
						end,
						set = function(_, val)
							module.DB.chatLog.expireDays = val
							module:CleanupOldChatLog()
							SUI.DBM:RefreshSettings(module)
						end,
						order = 5,
					},
					typesToLog = {
						name = L['Chat Types to Log'],
						type = 'multiselect',
						disabled = function()
							return not module.CurrentSettings.chatLog.enabled
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
							return module.CurrentSettings.chatLog.typesToLog[key]
						end,
						set = function(info, key, value)
							module.DB.chatLog.typesToLog[key] = value
							module:EnableChatLog()
							SUI.DBM:RefreshSettings(module)
						end,
						order = 6,
					},
					blacklist = {
						name = L['Blacklist'],
						type = 'group',
						order = 7,
						inline = true,
						disabled = function()
							return not module.CurrentSettings.chatLog.enabled
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

		for index, entry in ipairs(module.CurrentSettings.chatLog.blacklist.strings) do
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

	SUI.opt.args.Help.args.Overview.args.SUIModuleHelp.args.clearAllLogs = optTable.args.chatLog.args.clearAllLogs
	SUI.Options:AddOptions(optTable, 'Chatbox')
end
