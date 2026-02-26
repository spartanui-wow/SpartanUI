---@class SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.Chatbox
local module = SUI:GetModule('Chatbox')

local popup
local copyButtons = {}

function module:CreateCopyPopup()
	-- Recover existing frame across /rl
	if not popup and _G['SUI_ChatCopyPopup'] then
		popup = _G['SUI_ChatCopyPopup']
		module.popup = popup
		return
	end
	if popup then
		return
	end

	popup = CreateFrame('Frame', 'SUI_ChatCopyPopup', UIParent, 'ButtonFrameTemplate')
	ButtonFrameTemplate_HidePortrait(popup)
	ButtonFrameTemplate_HideButtonBar(popup)
	popup.Inset:Hide()
	popup:SetSize(600, 350)
	popup:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
	popup:SetFrameStrata('DIALOG')
	popup:Hide()

	popup:SetMovable(true)
	popup:EnableMouse(true)
	popup:RegisterForDrag('LeftButton')
	popup:SetScript('OnDragStart', popup.StartMoving)
	popup:SetScript('OnDragStop', popup.StopMovingOrSizing)

	popup:SetTitle('|cffffffffSpartan|cffe21f1fUI|r Chat Copy')

	popup.MainContent = CreateFrame('Frame', nil, popup)
	popup.MainContent:SetPoint('TOPLEFT', popup, 'TOPLEFT', 18, -30)
	popup.MainContent:SetPoint('BOTTOMRIGHT', popup, 'BOTTOMRIGHT', -25, 12)

	popup.TextPanel = CreateFrame('ScrollFrame', nil, popup.MainContent)
	popup.TextPanel:SetPoint('TOPLEFT', popup.MainContent, 'TOPLEFT', 6, -6)
	popup.TextPanel:SetPoint('BOTTOMRIGHT', popup.MainContent, 'BOTTOMRIGHT', 0, 2)

	popup.TextPanel.Background = popup.TextPanel:CreateTexture(nil, 'BACKGROUND')
	popup.TextPanel.Background:SetAtlas('auctionhouse-background-index', true)
	popup.TextPanel.Background:SetPoint('TOPLEFT', popup.TextPanel, 'TOPLEFT', -6, 6)
	popup.TextPanel.Background:SetPoint('BOTTOMRIGHT', popup.TextPanel, 'BOTTOMRIGHT', 0, -6)

	popup.TextPanel.ScrollBar = CreateFrame('EventFrame', nil, popup.TextPanel, 'MinimalScrollBar')
	popup.TextPanel.ScrollBar:SetPoint('TOPLEFT', popup.TextPanel, 'TOPRIGHT', 6, 0)
	popup.TextPanel.ScrollBar:SetPoint('BOTTOMLEFT', popup.TextPanel, 'BOTTOMRIGHT', 6, 0)
	ScrollUtil.InitScrollFrameWithScrollBar(popup.TextPanel, popup.TextPanel.ScrollBar)

	popup.editBox = CreateFrame('EditBox', nil, popup.TextPanel)
	popup.editBox:SetMultiLine(true)
	popup.editBox:SetFontObject('GameFontHighlight')
	popup.editBox:SetWidth(popup.TextPanel:GetWidth() - 20)
	popup.editBox:SetAutoFocus(false)
	popup.editBox:EnableMouse(true)
	popup.editBox:SetTextColor(1, 1, 1)
	popup.editBox:SetScript('OnTextChanged', function(self)
		ScrollingEdit_OnTextChanged(self, self:GetParent())
	end)
	popup.editBox:SetScript('OnCursorChanged', function(self, x, y, w, h)
		ScrollingEdit_OnCursorChanged(self, x, y - 10, w, h)
	end)
	popup.TextPanel:SetScrollChild(popup.editBox)

	popup.font = popup:CreateFontString(nil, nil, 'GameFontNormal')
	popup.font:Hide()

	popup:HookScript('OnShow', function()
		popup.TextPanel:SetVerticalScroll((popup.TextPanel:GetVerticalScrollRange()) or 0)
	end)

	module.popup = popup
end

function module:SetPopupText(text)
	if not popup then
		return
	end
	popup.editBox:SetText(text)
	popup:Show()
end

----------------------------------------------------------------------------------------------------
-- Collect chat text for copy
----------------------------------------------------------------------------------------------------

local function CollectChatText(chatFrame)
	local text = ''
	for i = 1, chatFrame:GetNumMessages() do
		local line = chatFrame:GetMessageInfo(i)
		if SUI.BlizzAPI.issecretvalue(line) then
			text = text .. '<Secret Message>\n'
		else
			popup.font:SetFormattedText('%s\n', line)
			local cleanLine = popup.font:GetText() or ''
			text = text .. cleanLine
		end
	end
	text = text:gsub('|T[^\\]+\\[^\\]+\\[Uu][Ii]%-[Rr][Aa][Ii][Dd][Tt][Aa][Rr][Gg][Ee][Tt][Ii][Nn][Gg][Ii][Cc][Oo][Nn]_(%d)[^|]+|t', '{rt%1}')
	text = text:gsub('|T13700([1-8])[^|]+|t', '{rt%1}')
	text = text:gsub('|T[^|]+|t', '')
	text = text:gsub('|K[^|]+|k', '<Protected Text>')
	-- Strip click-to-copy hyperlinks
	text = text:gsub('|Hsuicopy:%d+|h', '')
	text = text:gsub('|h', '')
	return text
end

local function TabClick(frame)
	local ChatFrameName = format('%s%d', 'ChatFrame', frame:GetID())
	local ChatFrame = _G[ChatFrameName]
	local ChatFrameEdit = _G[ChatFrameName .. 'EditBox']

	if IsShiftKeyDown() and IsControlKeyDown() then
		ChatFrame:Clear()
	elseif IsAltKeyDown() then
		module:SetPopupText(CollectChatText(ChatFrame))
	elseif IsShiftKeyDown() then
		if ChatFrame:IsVisible() then
			ChatFrame:Hide()
		else
			ChatFrame:Show()
		end
	end

	if ChatFrameEdit:IsVisible() then
		ChatFrameEdit:Hide()
	end
end

local function TabHintEnter(frame)
	if not module.DB.ChatCopyTip then
		return
	end

	ShowUIPanel(GameTooltip)
	GameTooltip:SetOwner(frame, 'ANCHOR_TOP')
	GameTooltip:AddLine('Alt+Click to copy', 0.8, 0, 0)
	GameTooltip:AddLine('Shift+Click to toggle', 0, 0.1, 1)
	GameTooltip:AddLine('Shift+Ctrl+Click to clear', 0.8, 0.4, 0)
	GameTooltip:Show()
end

local function TabHintLeave(frame)
	if not module.DB.ChatCopyTip then
		return
	end
	HideUIPanel(GameTooltip)
end

----------------------------------------------------------------------------------------------------
-- Copy Button (visible icon on chat frame)
----------------------------------------------------------------------------------------------------

local function CreateCopyButton(chatFrame, index)
	local btnName = 'SUI_ChatCopyButton' .. index
	if _G[btnName] then
		return _G[btnName]
	end

	local btn = CreateFrame('Button', btnName, chatFrame)
	btn:SetSize(20, 20)
	btn:SetAlpha(0)
	btn:SetFrameStrata(chatFrame:GetFrameStrata())
	btn:SetFrameLevel(chatFrame:GetFrameLevel() + 10)

	local tex = btn:CreateTexture(nil, 'ARTWORK')
	tex:SetAllPoints()
	tex:SetTexture('Interface\\Buttons\\UI-GuildButton-PublicNote-Up')
	tex:SetVertexColor(0.8, 0.8, 0.8, 1)
	btn.icon = tex

	-- Position based on settings
	local pos = module.DB.copyButton.position or 'TOPRIGHT'
	btn:ClearAllPoints()
	if pos == 'TOPLEFT' then
		btn:SetPoint('TOPLEFT', chatFrame, 'TOPLEFT', 2, -2)
	else
		btn:SetPoint('TOPRIGHT', chatFrame, 'TOPRIGHT', -2, -2)
	end

	-- Hover fade
	btn:SetScript('OnEnter', function(self)
		self:SetAlpha(1)
		GameTooltip:SetOwner(self, 'ANCHOR_TOP')
		GameTooltip:AddLine(L['Click to copy chat'], 1, 1, 1)
		GameTooltip:Show()
	end)
	btn:SetScript('OnLeave', function(self)
		self:SetAlpha(0.35)
		GameTooltip:Hide()
	end)

	-- Show at 0.35 alpha when mouse is over the chat frame
	chatFrame:HookScript('OnEnter', function()
		if module.DB.copyButton.enabled then
			btn:SetAlpha(0.35)
		end
	end)
	chatFrame:HookScript('OnLeave', function()
		if not btn:IsMouseOver() then
			btn:SetAlpha(0)
		end
	end)

	btn:SetScript('OnClick', function()
		module:SetPopupText(CollectChatText(chatFrame))
	end)

	return btn
end

----------------------------------------------------------------------------------------------------
-- Click-to-Copy Individual Lines
----------------------------------------------------------------------------------------------------

local function LineCopyFilter(self, event, msg, ...)
	if not module.DB.clickToCopyLine then
		return
	end
	if SUI.BlizzAPI.issecretvalue(msg) then
		return
	end

	-- Wrap message with a clickable hyperlink
	local lineIndex = self:GetNumMessages() + 1
	local wrappedMsg = '|Hsuicopy:' .. lineIndex .. '|h|cff888888[C]|r|h ' .. msg
	return false, wrappedMsg, ...
end

-- Hook for suicopy hyperlink clicks
local origSetHyperlink

function module:HandleLineCopyClick(link)
	local linkType, lineStr = strsplit(':', link, 2)
	if linkType ~= 'suicopy' then
		return false
	end

	-- Get the line from the chat frame that was clicked
	-- The user clicked in the active chat frame
	local chatFrame = DEFAULT_CHAT_FRAME
	local lineIndex = tonumber(lineStr)
	if lineIndex and lineIndex <= chatFrame:GetNumMessages() then
		local line = chatFrame:GetMessageInfo(lineIndex)
		if line and not SUI.BlizzAPI.issecretvalue(line) then
			-- Strip the suicopy wrapper from the line text
			line = line:gsub('|Hsuicopy:%d+|h|cff888888%[C%]|r|h ', '')
			module:SetPopupText(line)
		end
	end

	return true
end

----------------------------------------------------------------------------------------------------
-- Public Functions
----------------------------------------------------------------------------------------------------

function module:ClearChat()
	for i = 1, NUM_CHAT_WINDOWS do
		local chatFrame = _G['ChatFrame' .. i]
		if chatFrame then
			chatFrame:Clear()
		end
	end

	wipe(self.DB.chatLog.history)

	if SUI.CharDB.ChatEditHistory then
		wipe(SUI.CharDB.ChatEditHistory)
	end

	SUI:Print(L['Chat cleared'])
end

function module:SetEditBoxMessage(msg)
	if not ChatFrame1EditBox:IsShown() then
		ChatEdit_ActivateChat(ChatFrame1EditBox)
	end

	local editBoxText = ChatFrame1EditBox:GetText()
	if editBoxText and editBoxText ~= '' then
		ChatFrame1EditBox:SetText('')
	end
	ChatFrame1EditBox:Insert(msg)
	ChatFrame1EditBox:HighlightText()
end

----------------------------------------------------------------------------------------------------
-- Setup
----------------------------------------------------------------------------------------------------

function module:SetupCopyChat()
	if SUI:IsModuleDisabled(module) then
		return
	end

	for i = 1, 10 do
		local ChatFrameName = ('%s%d'):format('ChatFrame', i)
		local ChatFrame = _G[ChatFrameName]
		local ChatFrameTab = _G[ChatFrameName .. 'Tab']

		ChatFrameTab:HookScript('OnClick', TabClick)
		ChatFrameTab:HookScript('OnEnter', TabHintEnter)
		ChatFrameTab:HookScript('OnLeave', TabHintLeave)

		-- Copy button
		if module.DB.copyButton.enabled then
			copyButtons[i] = CreateCopyButton(ChatFrame, i)
		end
	end

	-- Click-to-copy line filter
	if module.DB.clickToCopyLine then
		local lineEvents = {
			'CHAT_MSG_SAY',
			'CHAT_MSG_YELL',
			'CHAT_MSG_GUILD',
			'CHAT_MSG_OFFICER',
			'CHAT_MSG_PARTY',
			'CHAT_MSG_PARTY_LEADER',
			'CHAT_MSG_RAID',
			'CHAT_MSG_RAID_LEADER',
			'CHAT_MSG_INSTANCE_CHAT',
			'CHAT_MSG_INSTANCE_CHAT_LEADER',
			'CHAT_MSG_WHISPER',
			'CHAT_MSG_WHISPER_INFORM',
			'CHAT_MSG_BN_WHISPER',
			'CHAT_MSG_BN_WHISPER_INFORM',
			'CHAT_MSG_CHANNEL',
			'CHAT_MSG_COMMUNITIES_CHANNEL',
		}
		for _, event in ipairs(lineEvents) do
			ChatFrame_AddMessageEventFilter(event, LineCopyFilter)
		end

		-- Hook ItemRefTooltip for suicopy links
		local origHyperlink = ChatFrame_OnHyperlinkShow
		if origHyperlink then
			hooksecurefunc('ChatFrame_OnHyperlinkShow', function(chatFrame, link, text, button)
				module:HandleLineCopyClick(link)
			end)
		end
	end
end
