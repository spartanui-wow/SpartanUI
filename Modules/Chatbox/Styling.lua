---@class SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.Chatbox
local module = SUI:GetModule('Chatbox')

local LibATErrorDisplay
local BugGrabber

local function StripTextures(object)
	for i = 1, object:GetNumRegions() do
		local region = select(i, object:GetRegions())
		if region and region:GetObjectType() == 'Texture' then
			region:SetTexture(nil)
		end
	end
end

local chatBG = {
	bgFile = [[Interface\Buttons\WHITE8X8]],
	edgeFile = [[Interface\Buttons\WHITE8X8]],
	tile = true,
	tileSize = 16,
	edgeSize = 2,
}

local DEFAULT_BG = { r = 0.05, g = 0.05, b = 0.05, a = 0.7 }

function module:ApplyChatSettings()
	SUI.DBM:RefreshSettings(module)
	module:ApplyHideChatButtons()
	module:ApplyHideSocialButton()
	module:ApplyDisableChatFade()
	module:ApplyChatHistoryLines()
end

function module:ApplyHideChatButtons()
	-- Header buttons manage Blizzard buttons themselves
	if module.CurrentSettings.headerButtons and module.CurrentSettings.headerButtons.enabled then
		return
	end

	local ChatFrameMenuBtn = _G['ChatFrameMenuButton']
	local VoiceChannelButton = _G['ChatFrameChannelButton']

	if module.CurrentSettings.hideChatButtons then
		if ChatFrameMenuBtn then
			ChatFrameMenuBtn:Hide()
			ChatFrameMenuBtn:SetScript('OnShow', function(self)
				if module.CurrentSettings.hideChatButtons then
					self:Hide()
				end
			end)
		end
		if VoiceChannelButton then
			VoiceChannelButton:Hide()
			VoiceChannelButton:SetScript('OnShow', function(self)
				if module.CurrentSettings.hideChatButtons then
					self:Hide()
				end
			end)
		end
	else
		if ChatFrameMenuBtn then
			ChatFrameMenuBtn:SetScript('OnShow', nil)
			ChatFrameMenuBtn:Show()
		end
		if VoiceChannelButton then
			VoiceChannelButton:SetScript('OnShow', nil)
			VoiceChannelButton:Show()
		end
	end

	local buttonFrameCount = 0
	for i = 1, NUM_CHAT_WINDOWS do
		local ChatFrame = _G['ChatFrame' .. i]
		if ChatFrame and ChatFrame.buttonFrame then
			buttonFrameCount = buttonFrameCount + 1
			ChatFrame.buttonFrame:SetAlpha(0)
			ChatFrame.buttonFrame:EnableMouse(true)
		end
	end

	if not module.chatButtonHooksApplied then
		module.chatButtonHooksApplied = true

		if FCF_FadeInChatFrame then
			hooksecurefunc('FCF_FadeInChatFrame', function(chatFrame)
				if module.CurrentSettings.hideChatButtons and chatFrame and chatFrame.buttonFrame then
					chatFrame.buttonFrame:SetAlpha(0)
					chatFrame.buttonFrame:EnableMouse(false)
				end
			end)
		end

		if FCF_FadeOutChatFrame then
			hooksecurefunc('FCF_FadeOutChatFrame', function(chatFrame)
				if module.CurrentSettings.hideChatButtons and chatFrame and chatFrame.buttonFrame then
					chatFrame.buttonFrame:SetAlpha(0)
					chatFrame.buttonFrame:EnableMouse(false)
				end
			end)
		end
	end
end

function module:ApplyHideSocialButton()
	-- Header buttons manage Blizzard buttons themselves
	if module.CurrentSettings.headerButtons and module.CurrentSettings.headerButtons.enabled then
		return
	end

	local QJTB = _G['QuickJoinToastButton']
	if not QJTB then
		return
	end

	if module.CurrentSettings.hideSocialButton then
		QJTB:Hide()
		QJTB:SetScript('OnShow', function(self)
			if module.CurrentSettings.hideSocialButton then
				self:Hide()
			end
		end)
	else
		QJTB:SetScript('OnShow', nil)
		QJTB:Show()
	end
end

function module:ApplyDisableChatFade()
	local function SetAllChatFading(shouldFade)
		if CHAT_FRAMES then
			for _, frameName in ipairs(CHAT_FRAMES) do
				local ChatFrame = _G[frameName]
				if ChatFrame and ChatFrame.SetFading then
					ChatFrame:SetFading(shouldFade)
				end
			end
		end
		for i = 1, 50 do
			local ChatFrame = _G['ChatFrame' .. i]
			if ChatFrame and ChatFrame.SetFading then
				ChatFrame:SetFading(shouldFade)
			end
		end
	end

	SetAllChatFading(not module.CurrentSettings.disableChatFade)

	if not module.chatFadeHooksApplied then
		module.chatFadeHooksApplied = true

		if FCF_OpenTemporaryWindow then
			hooksecurefunc('FCF_OpenTemporaryWindow', function()
				if module.CurrentSettings.disableChatFade then
					local cf = FCF_GetCurrentChatFrame and FCF_GetCurrentChatFrame()
					if cf and cf.SetFading then
						cf:SetFading(false)
					end
				end
			end)
		end

		if FloatingChatFrame_Update then
			hooksecurefunc('FloatingChatFrame_Update', function(id)
				if module.CurrentSettings.disableChatFade then
					local ChatFrame = _G['ChatFrame' .. id]
					if ChatFrame and ChatFrame.SetFading then
						ChatFrame:SetFading(false)
					end
				end
			end)
		end

		if FCF_CopyChatSettings then
			hooksecurefunc('FCF_CopyChatSettings', function(copyTo)
				if module.CurrentSettings.disableChatFade and copyTo and copyTo.SetFading then
					copyTo:SetFading(false)
				end
			end)
		end
	end
end

function module:ApplyChatHistoryLines()
	local lines = module.CurrentSettings.chatHistoryLines or 128
	for i = 1, NUM_CHAT_WINDOWS do
		local ChatFrame = _G['ChatFrame' .. i]
		if ChatFrame then
			ChatFrame:SetMaxLines(lines)
		end
	end
end

---Create a SUI-owned background frame behind a chat frame.
---This frame is NOT affected by Blizzard's FCF_FadeOutChatFrame so the background
---color persists even when the mouse leaves the chat area.
---@param chatFrame Frame
---@param index number
local function CreateSUIBackground(chatFrame, index)
	local frameName = 'SUI_ChatBackground' .. index
	if _G[frameName] then
		return _G[frameName]
	end

	local bg = CreateFrame('Frame', frameName, chatFrame, BackdropTemplateMixin and 'BackdropTemplate' or nil)
	bg:SetFrameStrata(chatFrame:GetFrameStrata())
	bg:SetFrameLevel(math.max(chatFrame:GetFrameLevel() - 1, 0))
	bg:SetPoint('TOPLEFT', chatFrame.Background or chatFrame, 'TOPLEFT', 0, 0)
	bg:SetPoint('BOTTOMRIGHT', chatFrame.Background or chatFrame, 'BOTTOMRIGHT', 0, 0)

	if bg.SetBackdrop then
		bg:SetBackdrop(chatBG)
		bg:SetBackdropColor(DEFAULT_BG.r, DEFAULT_BG.g, DEFAULT_BG.b, DEFAULT_BG.a)
		bg:SetBackdropBorderColor(DEFAULT_BG.r, DEFAULT_BG.g, DEFAULT_BG.b, DEFAULT_BG.a)
	end

	bg:Show()
	return bg
end

function module:CleanupOverride()
	-- Hide SUI chat frames that persist across /rl from a previous session
	local headerButtons = _G['SUI_ChatHeaderButtons']
	if headerButtons then
		headerButtons:Hide()
	end

	local tabDropdown = _G['SUI_ChatTabDropdown']
	if tabDropdown then
		tabDropdown:Hide()
	end

	-- Remove SUI backdrop from GeneralDockManager
	local GDM = _G['GeneralDockManager']
	if GDM and GDM.SetBackdrop then
		GDM:SetBackdrop(nil)
	end

	-- Hide SUI chat backgrounds
	for i = 1, 10 do
		local bg = _G['SUI_ChatBackground' .. i]
		if bg then
			bg:Hide()
		end
	end

	-- Restore Blizzard chat tabs
	for i = 1, NUM_CHAT_WINDOWS do
		local tab = _G['ChatFrame' .. i .. 'Tab']
		if tab then
			tab:SetScript('OnShow', nil)
			tab:Show()
		end
	end
	if GENERAL_CHAT_DOCK then
		if GENERAL_CHAT_DOCK.overflowButton then
			GENERAL_CHAT_DOCK.overflowButton:SetScript('OnShow', nil)
		end
		GENERAL_CHAT_DOCK.isDirty = true
		if FCFDock_UpdateTabs then
			FCFDock_UpdateTabs(GENERAL_CHAT_DOCK, true)
		end
	end
end

function module:SetupStyling()
	if SUI:IsModuleDisabled(module) then
		return
	end

	local icon = 'Interface\\Addons\\SpartanUI\\images\\chatbox\\chaticons'

	local GDM = _G['GeneralDockManager']
	if not GDM.SetBackdrop then
		Mixin(GDM, BackdropTemplateMixin)
	end

	if GDM.SetBackdrop then
		GDM:SetBackdrop(chatBG)
		GDM:SetBackdropColor(DEFAULT_BG.r, DEFAULT_BG.g, DEFAULT_BG.b, DEFAULT_BG.a)
		GDM:SetBackdropBorderColor(DEFAULT_BG.r, DEFAULT_BG.g, DEFAULT_BG.b, DEFAULT_BG.a)
	end
	GDM:ClearAllPoints()
	GDM:SetPoint('BOTTOMLEFT', _G['ChatFrame1Background'], 'TOPLEFT', -1, 1)
	GDM:SetPoint('BOTTOMRIGHT', _G['ChatFrame1Background'], 'TOPRIGHT', 1, 1)

	ChatAlertFrame:ClearAllPoints()
	ChatAlertFrame:SetPoint('BOTTOMLEFT', GDM, 'TOPLEFT', 0, 2)

	-- Only style Blizzard GDM buttons if header buttons are disabled
	if not (module.CurrentSettings.headerButtons and module.CurrentSettings.headerButtons.enabled) then
		local QJTB = _G['QuickJoinToastButton']
		if QJTB then
			QJTB:ClearAllPoints()
			QJTB:SetSize(18, 18)
			StripTextures(QJTB)

			QJTB:ClearAllPoints()
			QJTB:SetPoint('TOPRIGHT', GDM, 'TOPRIGHT', -2, -3)
			QJTB.FriendCount:Hide()
			hooksecurefunc(QJTB, 'UpdateQueueIcon', function(frame)
				if not frame.displayedToast then
					return
				end
				frame.FriendsButton:SetTexture(icon)
				frame.QueueButton:SetTexture(icon)
				frame.FlashingLayer:SetTexture(icon)
				frame.FriendsButton:SetShown(false)
				frame.FriendCount:SetShown(false)
			end)
			hooksecurefunc(QJTB, 'SetPoint', function(frame, point, anchor)
				if anchor ~= GDM and point ~= 'TOPRIGHT' then
					frame:ClearAllPoints()
					frame:SetPoint('TOPRIGHT', GDM, 'TOPRIGHT', -2, -3)
				end
			end)

			local function updateTexture()
				QJTB.FriendsButton:SetTexture(icon)
				QJTB.QueueButton:SetTexture(icon)
			end
			QJTB:HookScript('OnMouseDown', updateTexture)
			QJTB:HookScript('OnMouseUp', updateTexture)
			updateTexture()

			QJTB.FriendsButton:SetTexture(icon)
			QJTB.FriendsButton:SetTexCoord(0.08, 0.4, 0.6, 0.9)
			QJTB.FriendsButton:ClearAllPoints()
			QJTB.FriendsButton:SetPoint('CENTER')
			QJTB.FriendsButton:SetSize(18, 18)

			QJTB.QueueButton:SetTexture(icon)
			QJTB.QueueButton:SetTexCoord(0.6, 0.9, 0.08, 0.4)
			QJTB.QueueButton:ClearAllPoints()
			QJTB.QueueButton:SetPoint('CENTER')
			QJTB.QueueButton:SetSize(18, 18)

			QJTB.FlashingLayer:SetTexture(icon)
			QJTB.FlashingLayer:SetTexCoord(0.6, 0.9, 0.08, 0.4)
			QJTB.FlashingLayer:ClearAllPoints()
			QJTB.FlashingLayer:SetPoint('CENTER')
			QJTB.FlashingLayer:SetSize(20, 20)

			QJTB.Toast:ClearAllPoints()
			QJTB.Toast:SetPoint('BOTTOMLEFT', QJTB, 'TOPLEFT')
			QJTB.Toast2:ClearAllPoints()
			QJTB.Toast2:SetPoint('BOTTOMLEFT', QJTB, 'TOPLEFT')
		end

		local VoiceChannelButton = _G['ChatFrameChannelButton']
		if VoiceChannelButton then
			VoiceChannelButton:ClearAllPoints()
			VoiceChannelButton:SetParent(GDM)
			local QJTB = _G['QuickJoinToastButton']
			if QJTB then
				VoiceChannelButton:SetPoint('RIGHT', QJTB, 'LEFT', -1, 0)
			else
				VoiceChannelButton:SetPoint('TOPRIGHT', GDM, 'TOPRIGHT', -2, -3)
			end
			StripTextures(VoiceChannelButton)
			VoiceChannelButton:SetSize(18, 18)
			if not VoiceChannelButton.Icon then
				VoiceChannelButton.Icon = VoiceChannelButton:CreateTexture(nil, 'ARTWORK')
				VoiceChannelButton.Icon:SetAllPoints(VoiceChannelButton)
			end
			VoiceChannelButton.Icon:SetTexture(icon)
			VoiceChannelButton.Icon:SetTexCoord(0.1484375, 0.359375, 0.1484375, 0.359375)
			VoiceChannelButton.Icon:SetScale(0.8)
		end

		if ChatFrameMenuButton then
			ChatFrameMenuButton:ClearAllPoints()
			ChatFrameMenuButton:SetParent(GDM)
			local VoiceChannelButton = _G['ChatFrameChannelButton']
			local QJTB = _G['QuickJoinToastButton']
			if VoiceChannelButton then
				ChatFrameMenuButton:SetPoint('RIGHT', VoiceChannelButton, 'LEFT', -1, -2)
			elseif QJTB then
				ChatFrameMenuButton:SetPoint('RIGHT', QJTB, 'LEFT', -1, 0)
			else
				ChatFrameMenuButton:SetPoint('TOPRIGHT', GDM, 'TOPRIGHT', -2, -3)
			end
			ChatFrameMenuButton:SetSize(18, 18)
			StripTextures(ChatFrameMenuButton)
			if not ChatFrameMenuButton.Icon then
				ChatFrameMenuButton.Icon = ChatFrameMenuButton:CreateTexture(nil, 'ARTWORK')
				ChatFrameMenuButton.Icon:SetAllPoints(ChatFrameMenuButton)
			end
			ChatFrameMenuButton.Icon:SetTexture(icon)
			ChatFrameMenuButton.Icon:SetTexCoord(0.6, 0.9, 0.6, 0.9)
		end
	end

	BNToastFrame:ClearAllPoints()
	BNToastFrame:SetPoint('BOTTOM', GDM, 'TOP')
	local function fixbnetpos(frame, _, anchor)
		if anchor ~= GDM then
			frame:ClearAllPoints()
			BNToastFrame:SetPoint('BOTTOM', GDM, 'TOP')
		end
	end
	hooksecurefunc(BNToastFrame, 'SetPoint', fixbnetpos)

	-- Per-frame styling
	local function disable(element)
		if element.UnregisterAllEvents then
			element:UnregisterAllEvents()
			element:SetParent(nil)
		end
		element.Show = element.Hide
		element:Hide()
	end

	for i = 1, 10 do
		local ChatFrameName = ('%s%d'):format('ChatFrame', i)
		local ChatFrame = _G[ChatFrameName]

		ChatFrame:SetClampRectInsets(0, 0, 0, 0)
		ChatFrame:SetClampedToScreen(false)

		-- Create SUI-owned background that persists through Blizzard's fade system
		CreateSUIBackground(ChatFrame, i)

		if ChatFrame.SetBackdrop then
			ChatFrame:SetBackdrop(nil)
		end

		-- Scrollbar
		if ChatFrame.ScrollBar and ChatFrame.ScrollBar.ThumbTexture then
			ChatFrame.ScrollBar.ThumbTexture:SetColorTexture(1, 1, 1, 0.4)
			ChatFrame.ScrollBar.ThumbTexture:SetWidth(10)

			StripTextures(ChatFrame.ScrollToBottomButton)
			local BG = ChatFrame.ScrollToBottomButton:CreateTexture(nil, 'ARTWORK')
			BG:SetAllPoints(ChatFrame.ScrollToBottomButton)
			BG:SetTexture('Interface\\Addons\\SpartanUI\\images\\chatbox\\bottomArrow')
			BG:SetAlpha(0.4)
			ChatFrame.ScrollToBottomButton.BG = BG
			ChatFrame.ScrollToBottomButton:ClearAllPoints()
			ChatFrame.ScrollToBottomButton:SetSize(20, 20)
			ChatFrame.ScrollToBottomButton:SetPoint('BOTTOMRIGHT', ChatFrame.ResizeButton, 'TOPRIGHT', -4, 0)
		end

		-- Tab skinning
		local ChatFrameTab = _G[ChatFrameName .. 'Tab']
		ChatFrameTab.Text:ClearAllPoints()
		ChatFrameTab.Text:SetPoint('CENTER', ChatFrameTab)

		-- Tab textures are named per engine, not per flavor: the modern engine uses
		-- ActiveLeft/HighlightLeft/Left, the legacy one leftSelectedTexture and friends.
		-- Detect the actual field so clients that mix the two (Forever) work either way.
		if ChatFrameTab.ActiveLeft then
			local sides = { 'Left', 'Middle', 'Right' }
			local modes = { 'Active', 'Highlight', '' }
			for _, mode in ipairs(modes) do
				for _, side in ipairs(sides) do
					local tex = ChatFrameTab[mode .. side]
					if tex then
						tex:SetTexture(nil)
					end
				end
			end
		else
			for _, v in ipairs({ 'left', 'middle', 'right' }) do
				for _, suffix in ipairs({ 'HighlightTexture', 'SelectedTexture', 'Texture' }) do
					local tex = ChatFrameTab[v .. suffix]
					if tex then
						tex:SetTexture(nil)
					end
				end
			end
		end

		-- Selection area
		if ChatFrame.Selection then
			ChatFrame.Selection:ClearAllPoints()
			ChatFrame.Selection:SetPoint('TOPLEFT', ChatFrame, 'TOPLEFT', 0, 30)
			ChatFrame.Selection:SetPoint('BOTTOMRIGHT', ChatFrame, 'BOTTOMRIGHT', 25, -32)
		end

		-- Font
		SUI.Font:Format(ChatFrame, module.CurrentSettings.fontSize, 'Chatbox')

		-- ButtonFrame - always disable; SUI replaces these controls with its own header bar
		local buttonFrame = _G[ChatFrameName .. 'ButtonFrame']
		if buttonFrame then
			disable(buttonFrame)
		end
	end

	module:SetupHeaderButtons()
end

----------------------------------------------------------------------------------------------------
-- Header Buttons
----------------------------------------------------------------------------------------------------

local ICON_PATH = 'Interface\\AddOns\\SpartanUI\\images\\chatbox\\'
local HEADER_ICON_SIZE = 16
local HEADER_GAP = 6

local HEADER_BUTTON_DEFS = {
	-- LEFT group
	{
		key = 'social',
		icon = 'social',
		side = 'left',
		tooltip = L['Social'],
		action = function()
			ToggleFriendsFrame()
		end,
	},
	{
		key = 'copy',
		icon = 'copy',
		side = 'left',
		tooltip = L['Click to copy chat'],
		action = function()
			if module.CollectChatText then
				module:SetPopupText(module.CollectChatText(DEFAULT_CHAT_FRAME))
			end
		end,
	},
	{
		key = 'search',
		icon = 'search',
		side = 'left',
		tooltip = L['Search chat'],
		action = function()
			module:ToggleChatSearch(1)
		end,
	},
	{
		key = 'errors',
		icon = 'errors',
		side = 'left',
		tooltip = L['Errors'],
		action = function()
			if LibATErrorDisplay then
				LibATErrorDisplay.BugWindow:OpenErrorWindow()
			end
		end,
		special = 'errors',
	},
	-- RIGHT group (reverse order: rightmost first, since layout anchors right-to-left)
	{
		key = 'settings',
		icon = 'settings',
		side = 'right',
		tooltip = L['Chat settings'],
		action = function()
			if SlashCmdList['ACECONSOLE_SUI'] then
				SlashCmdList['ACECONSOLE_SUI']('> Modules > Chatbox')
			end
		end,
	},
	{
		key = 'channels',
		icon = 'chat-channels',
		side = 'right',
		tooltip = L['Chat menu'],
		action = function()
			local btn = _G['ChatFrameMenuButton']
			if btn then
				btn:SetMenuOpen(not btn:IsMenuOpen())
			end
		end,
	},
	{
		key = 'voice',
		icon = 'voice',
		side = 'right',
		tooltip = L['Voice chat'],
		action = function()
			local v = _G['ChatFrameChannelButton']
			if v then
				v:Click()
			end
		end,
	},
	{
		key = 'emoji',
		icon = 'emojis/SlightSmile-BW',
		side = 'right',
		tooltip = L['Emoji'],
		action = function(btn)
			module:ToggleEmojiPicker(btn)
		end,
		special = 'emoji',
	},
}

local function CreateHeaderIconButton(parent, iconFile, tooltipText, action)
	local btn = CreateFrame('Button', nil, parent)
	btn:SetSize(HEADER_ICON_SIZE, HEADER_ICON_SIZE)

	local iconTex = btn:CreateTexture(nil, 'ARTWORK')
	iconTex:SetTexture(ICON_PATH .. iconFile .. '.png')
	iconTex:SetSize(HEADER_ICON_SIZE, HEADER_ICON_SIZE)
	iconTex:SetPoint('LEFT', btn, 'LEFT', 0, 0)
	iconTex:SetVertexColor(0.7, 0.7, 0.7, 1)
	btn.iconTex = iconTex

	btn:SetScript('OnEnter', function(self)
		self.iconTex:SetVertexColor(1, 1, 1, 1)
		GameTooltip:SetOwner(self, 'ANCHOR_TOP')
		GameTooltip:AddLine(tooltipText, 1, 1, 1)
		GameTooltip:Show()
	end)
	btn:SetScript('OnLeave', function(self)
		self.iconTex:SetVertexColor(0.7, 0.7, 0.7, 1)
		GameTooltip:Hide()
	end)
	btn:SetScript('OnClick', function(self)
		action(self)
	end)

	return btn
end

function module:ShowBlizzHeaderButtons(show)
	local blizzButtons = {
		_G['QuickJoinToastButton'],
		_G['ChatFrameChannelButton'],
	}
	for _, btn in ipairs(blizzButtons) do
		if btn then
			if show then
				btn:SetScript('OnShow', nil)
				btn:Show()
			else
				btn:Hide()
				btn:SetScript('OnShow', function(self)
					self:Hide()
				end)
			end
		end
	end
	local menuBtn = _G['ChatFrameMenuButton']
	if menuBtn then
		if show then
			menuBtn:SetAlpha(1)
			menuBtn:SetSize(18, 18)
		else
			local container = _G['SUI_ChatHeaderButtons']
			if container then
				menuBtn:SetParent(container)
				menuBtn:ClearAllPoints()
				menuBtn:SetPoint('CENTER', container, 'CENTER', 0, 0)
				menuBtn:SetSize(1, 1)
				menuBtn:SetAlpha(0)
				menuBtn:Show()
			end
		end
	end
end

function module:SetupHeaderButtons()
	local db = module.CurrentSettings.headerButtons
	if not db or not db.enabled then
		return
	end

	-- Error tracking setup (needed on both fresh load and /rl recovery)
	if LibAT and LibAT.ErrorDisplay then
		LibATErrorDisplay = LibAT.ErrorDisplay
	elseif _G.LibATErrorDisplay then
		LibATErrorDisplay = _G.LibATErrorDisplay
	end
	BugGrabber = _G.BugGrabber

	-- Recover existing container across /rl
	if _G['SUI_ChatHeaderButtons'] then
		-- Re-register BugGrabber callback (file-locals reset on /rl)
		local eventFrame = _G['SUI_ChatHeaderEvents']
		if eventFrame and BugGrabber then
			if EventRegistry and EventRegistry.RegisterCallback then
				EventRegistry:RegisterCallback('BugGrabber.BugGrabbed', function()
					module:UpdateHeaderErrorButton()
				end, eventFrame)
			elseif BugGrabber.RegisterCallback then
				BugGrabber.RegisterCallback(eventFrame, 'BugGrabber_BugGrabbed', function()
					module:UpdateHeaderErrorButton()
				end)
			end
		end
		module:RefreshHeaderButtons()
		return
	end

	local GDM = _G['GeneralDockManager']
	if not GDM then
		return
	end

	local container = CreateFrame('Frame', 'SUI_ChatHeaderButtons', GDM)
	container:SetAllPoints(GDM)
	container:SetFrameLevel(GDM:GetFrameLevel() + 5)
	container.buttons = {}

	-- Separate event frame so social/error events don't conflict
	local eventFrame = CreateFrame('Frame', 'SUI_ChatHeaderEvents', container)
	eventFrame:RegisterEvent('FRIENDLIST_UPDATE')
	eventFrame:RegisterEvent('BN_FRIEND_LIST_SIZE_CHANGED')
	eventFrame:RegisterEvent('BN_FRIEND_INFO_CHANGED')
	eventFrame:RegisterEvent('PLAYER_ENTERING_WORLD')
	eventFrame:SetScript('OnEvent', function()
		module:UpdateHeaderFriendCount()
	end)

	-- Register BugGrabber callback on the event frame (persistent across refreshes)
	if BugGrabber then
		if EventRegistry and EventRegistry.RegisterCallback then
			EventRegistry:RegisterCallback('BugGrabber.BugGrabbed', function()
				module:UpdateHeaderErrorButton()
			end, eventFrame)
		elseif BugGrabber.RegisterCallback then
			BugGrabber.RegisterCallback(eventFrame, 'BugGrabber_BugGrabbed', function()
				module:UpdateHeaderErrorButton()
			end)
		end
		-- Hook Reset so clearing errors updates the button
		if not module.bugGrabberResetHooked and BugGrabber.Reset then
			module.bugGrabberResetHooked = true
			hooksecurefunc(BugGrabber, 'Reset', function()
				C_Timer.After(0.1, function()
					module:UpdateHeaderErrorButton()
				end)
			end)
		end
	end

	module:RefreshHeaderButtons()
end

function module:UpdateHeaderFriendCount()
	local container = _G['SUI_ChatHeaderButtons']
	if not container or not container.buttons then
		return
	end
	for _, btn in ipairs(container.buttons) do
		if btn.key == 'social' and btn.friendCount then
			local _, bnOnline = BNGetNumFriends()
			local wowOnline = C_FriendList.GetNumOnlineFriends()
			local count = (bnOnline or 0) + (wowOnline or 0)
			if count > 0 then
				btn.friendCount:SetText(tostring(count))
				local sw = btn.friendCount:GetStringWidth()
				btn:SetWidth(HEADER_ICON_SIZE + 2 + (SUI.BlizzAPI.canaccessvalue(sw) and sw or 20))
			else
				btn.friendCount:SetText('')
				btn:SetWidth(HEADER_ICON_SIZE)
			end
		end
	end
end

function module:UpdateHeaderErrorButton()
	local container = _G['SUI_ChatHeaderButtons']
	if not container or not container.buttons then
		return
	end
	if not LibATErrorDisplay or not BugGrabber then
		return
	end
	local db = module.CurrentSettings.headerButtons
	local btnVisibility = db and db.buttons or {}
	local errors = LibATErrorDisplay.ErrorHandler:GetErrors(BugGrabber:GetSessionId())
	local errCount = #errors
	local errorBtn
	for _, btn in ipairs(container.buttons) do
		if btn.isErrorBtn then
			errorBtn = btn
			if errCount > 0 and btnVisibility.errors ~= false then
				btn:Show()
				btn.countLabel:SetText(errCount > 99 and '99+' or tostring(errCount))
				local sw = btn.countLabel:GetStringWidth()
				btn:SetWidth(HEADER_ICON_SIZE + 2 + (SUI.BlizzAPI.canaccessvalue(sw) and sw or 20))
			else
				btn:Hide()
			end
		end
	end

	-- Re-anchor tab label: attach to error button when visible, otherwise to last left button
	if container.tabLabelBtn and container.leftAnchor then
		local leftAnchor = container.leftAnchor
		if errorBtn and errorBtn:IsShown() then
			leftAnchor = errorBtn
		end
		container.tabLabelBtn:SetPoint('LEFT', leftAnchor, 'RIGHT', HEADER_GAP, 0)
	end
end

----------------------------------------------------------------------------------------------------
-- Tab Switcher: Hide Blizzard tabs, show active tab label + popup dropdown
----------------------------------------------------------------------------------------------------

local function SafeSelectDockFrame(cf)
	if not cf then
		return
	end
	C_Timer.After(0, function()
		local dock = GENERAL_CHAT_DOCK
		if dock and dock.DOCKED_CHAT_FRAMES then
			dock.selected = cf
			if module.logger then
				module.logger.debug('[BG-DEBUG] Styling: iterating dock.DOCKED_CHAT_FRAMES (pairs) line 788')
			end
			for _, frame in pairs(dock.DOCKED_CHAT_FRAMES) do
				if frame == cf then
					frame:Show()
				else
					frame:Hide()
				end
			end
		else
			cf:Show()
		end
		SELECTED_CHAT_FRAME = cf
		module:UpdateTabLabel()
	end)
end

local function GetActiveChatFrameName()
	local dock = GENERAL_CHAT_DOCK
	local activeCF = dock and dock.selected or DEFAULT_CHAT_FRAME
	if not activeCF then
		return 'General'
	end
	local id = activeCF:GetID()
	local name = GetChatWindowInfo(id)
	if name and name ~= '' then
		return name
	end
	local tab = _G[activeCF:GetName() .. 'Tab']
	if tab and tab.Text then
		local text = tab.Text:GetText()
		if text and text ~= '' then
			return text
		end
	end
	return 'Chat'
end

local function IsFrameDocked(chatFrame)
	local dock = GENERAL_CHAT_DOCK
	if not dock or not dock.DOCKED_CHAT_FRAMES then
		return false
	end
	if module.logger then
		module.logger.debug('[BG-DEBUG] Styling: iterating dock.DOCKED_CHAT_FRAMES (ipairs) line 830')
	end
	for _, frame in ipairs(dock.DOCKED_CHAT_FRAMES) do
		if frame == chatFrame then
			return true
		end
	end
	return false
end

local function StyleUndockedTab(tab)
	if not tab then
		return
	end
	local tabName = tab:GetName()
	local left = tabName and _G[tabName .. 'Left']
	local middle = tabName and _G[tabName .. 'Middle']
	local right = tabName and _G[tabName .. 'Right']
	local activeLeft = tabName and _G[tabName .. 'ActiveLeft']
	local activeMiddle = tabName and _G[tabName .. 'ActiveMiddle']
	local activeRight = tabName and _G[tabName .. 'ActiveRight']
	local highlight = tabName and _G[tabName .. 'Highlight']

	if left then
		left:SetTexture(nil)
	end
	if middle then
		middle:SetTexture(nil)
	end
	if right then
		right:SetTexture(nil)
	end
	if activeLeft then
		activeLeft:SetTexture(nil)
	end
	if activeMiddle then
		activeMiddle:SetTexture(nil)
	end
	if activeRight then
		activeRight:SetTexture(nil)
	end
	if highlight then
		highlight:SetTexture(nil)
	end

	if not tab.suiBG then
		tab.suiBG = tab:CreateTexture(nil, 'BACKGROUND')
		tab.suiBG:SetAllPoints()
		tab.suiBG:SetColorTexture(0.1, 0.1, 0.1, 0.85)
	end

	local text = tab:GetFontString()
	if text then
		text:SetTextColor(0.8, 0.8, 0.8, 1)
	end
end

local function HideBlizzardTabs()
	for i = 1, NUM_CHAT_WINDOWS do
		local tab = _G['ChatFrame' .. i .. 'Tab']
		local cf = _G['ChatFrame' .. i]
		if tab and cf then
			-- Hide all tabs first; SUI's header bar replaces the tab system
			tab:Hide()
			tab:SetScript('OnShow', function(self)
				-- Allow undocked, visible frames to keep their tab
				if not IsFrameDocked(cf) and cf:IsShown() then
					self:SetScript('OnShow', nil)
					StyleUndockedTab(self)
				else
					self:Hide()
				end
			end)
		end
	end
	if GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.overflowButton then
		GENERAL_CHAT_DOCK.overflowButton:Hide()
		GENERAL_CHAT_DOCK.overflowButton:SetScript('OnShow', function(self)
			self:Hide()
		end)
	end
end

local function RestoreBlizzardTabs()
	for i = 1, NUM_CHAT_WINDOWS do
		local tab = _G['ChatFrame' .. i .. 'Tab']
		if tab then
			tab:SetScript('OnShow', nil)
		end
	end
	if GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.overflowButton then
		GENERAL_CHAT_DOCK.overflowButton:SetScript('OnShow', nil)
	end
	if GENERAL_CHAT_DOCK then
		GENERAL_CHAT_DOCK.isDirty = true
		FCFDock_UpdateTabs(GENERAL_CHAT_DOCK, true)
	end
end

local tabDropdown -- file-local for /rl recovery
local tabDropdownCloseTimer

local function CloseTabDropdown()
	if tabDropdown and tabDropdown:IsShown() then
		tabDropdown:Hide()
	end
	if tabDropdownCloseTimer then
		tabDropdownCloseTimer:Cancel()
		tabDropdownCloseTimer = nil
	end
end

local function HasUnreadTabs()
	for i = 1, NUM_CHAT_WINDOWS do
		local tab = _G['ChatFrame' .. i .. 'Tab']
		if tab then
			local cf = _G['ChatFrame' .. i]
			local dock = GENERAL_CHAT_DOCK
			local isActive = dock and dock.selected == cf
			if not isActive and tab.isFlashing then
				return true
			end
		end
	end
	return false
end

local function OpenTabDropdown(anchorFrame)
	if not tabDropdown then
		tabDropdown = CreateFrame('Frame', 'SUI_ChatTabDropdown', UIParent, BackdropTemplateMixin and 'BackdropTemplate' or nil)
		tabDropdown:SetFrameStrata('TOOLTIP')
		tabDropdown:SetClampedToScreen(true)
		if tabDropdown.SetBackdrop then
			tabDropdown:SetBackdrop({
				bgFile = [[Interface\Buttons\WHITE8X8]],
				edgeFile = [[Interface\Buttons\WHITE8X8]],
				tile = true,
				tileSize = 16,
				edgeSize = 1,
			})
			tabDropdown:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
			tabDropdown:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
		end
	end

	-- Clean up old entry buttons
	if tabDropdown.entries then
		for _, entry in ipairs(tabDropdown.entries) do
			entry:Hide()
			entry:SetParent(nil)
		end
	end
	tabDropdown.entries = {}

	local dock = GENERAL_CHAT_DOCK
	if not dock or not dock.DOCKED_CHAT_FRAMES then
		return
	end

	local activeCF = dock.selected or DEFAULT_CHAT_FRAME
	local entryHeight = 20
	local entryPadding = 2
	local sidePadding = 8
	local maxWidth = 80

	-- Build entries for each docked chat frame
	if module.logger then
		module.logger.debug('[BG-DEBUG] Styling: iterating dock.DOCKED_CHAT_FRAMES (ipairs) line 995')
	end
	for _, cf in ipairs(dock.DOCKED_CHAT_FRAMES) do
		local id = cf:GetID()
		if cf then
			local name = GetChatWindowInfo(id)
			if not name or name == '' then
				local tab = _G[cf:GetName() .. 'Tab']
				name = tab and tab.Text and tab.Text:GetText() or ('Chat ' .. id)
			end

			local isActive = (cf == activeCF)

			local entry = CreateFrame('Button', nil, tabDropdown)
			entry:SetHeight(entryHeight)

			local label = entry:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
			label:SetPoint('LEFT', entry, 'LEFT', sidePadding, 0)
			label:SetText(name)
			entry.label = label

			if isActive then
				label:SetTextColor(1, 0.82, 0, 1)
			else
				label:SetTextColor(0.7, 0.7, 0.7, 1)
			end

			-- Unread indicator
			local tab = _G[cf:GetName() .. 'Tab']
			if not isActive and tab and tab.isFlashing then
				local dot = entry:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
				dot:SetPoint('RIGHT', entry, 'RIGHT', -sidePadding, 0)
				dot:SetText('*')
				dot:SetTextColor(1, 0.5, 0, 1)
			end

			local stringWidth = label:GetStringWidth()
			if SUI.BlizzAPI.canaccessvalue(stringWidth) then
				local textWidth = stringWidth + sidePadding * 2 + 12
				if textWidth > maxWidth then
					maxWidth = textWidth
				end
			end

			entry:SetScript('OnEnter', function(self)
				if tabDropdownCloseTimer then
					tabDropdownCloseTimer:Cancel()
					tabDropdownCloseTimer = nil
				end
				if not isActive then
					self.label:SetTextColor(1, 1, 1, 1)
				end
			end)
			entry:SetScript('OnLeave', function(self)
				if not isActive then
					self.label:SetTextColor(0.7, 0.7, 0.7, 1)
				end
				-- Start close timer for hover mode
				local mode = module.CurrentSettings.headerButtons.tabSwitcherMode or 'hover'
				if mode == 'hover' then
					if tabDropdownCloseTimer then
						tabDropdownCloseTimer:Cancel()
					end
					tabDropdownCloseTimer = C_Timer.NewTimer(0.3, function()
						CloseTabDropdown()
					end)
				end
			end)
			entry:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
			entry:SetScript('OnClick', function(self, clickBtn)
				if clickBtn == 'RightButton' then
					local entryId = cf:GetID()
					CURRENT_CHAT_FRAME_ID = entryId
					self.GetID = function()
						return entryId
					end
					if FCF_Tab_SetupMenu then
						FCF_Tab_SetupMenu(self)
					end
					CloseTabDropdown()
					return
				end
				SafeSelectDockFrame(cf)
				CloseTabDropdown()
			end)

			tabDropdown.entries[#tabDropdown.entries + 1] = entry
		end
	end

	-- Layout entries and size the dropdown
	local totalHeight = entryPadding
	for i, entry in ipairs(tabDropdown.entries) do
		entry:SetWidth(maxWidth)
		entry:ClearAllPoints()
		entry:SetPoint('TOPLEFT', tabDropdown, 'TOPLEFT', 0, -totalHeight)
		entry:SetPoint('TOPRIGHT', tabDropdown, 'TOPRIGHT', 0, -totalHeight)
		totalHeight = totalHeight + entryHeight
	end
	totalHeight = totalHeight + entryPadding

	tabDropdown:SetSize(maxWidth, totalHeight)
	tabDropdown:ClearAllPoints()
	tabDropdown:SetPoint('BOTTOM', anchorFrame, 'TOP', 0, 4)

	-- Hover mode: cancel close timer when mouse enters dropdown
	tabDropdown:SetScript('OnEnter', function()
		if tabDropdownCloseTimer then
			tabDropdownCloseTimer:Cancel()
			tabDropdownCloseTimer = nil
		end
	end)
	tabDropdown:SetScript('OnLeave', function()
		local mode = module.CurrentSettings.headerButtons.tabSwitcherMode or 'hover'
		if mode == 'hover' then
			if tabDropdownCloseTimer then
				tabDropdownCloseTimer:Cancel()
			end
			tabDropdownCloseTimer = C_Timer.NewTimer(0.3, function()
				CloseTabDropdown()
			end)
		end
	end)

	tabDropdown:Show()
end

function module:UpdateTabLabel()
	local container = _G['SUI_ChatHeaderButtons']
	if not container or not container.tabLabel then
		return
	end
	container.tabLabel:SetText(GetActiveChatFrameName())

	-- Unread indicator
	if container.unreadDot then
		if HasUnreadTabs() then
			container.unreadDot:Show()
		else
			container.unreadDot:Hide()
		end
	end
end

function module:RefreshHeaderButtons()
	SUI.DBM:RefreshSettings(module)
	local container = _G['SUI_ChatHeaderButtons']
	if not container then
		return
	end

	local db = module.CurrentSettings.headerButtons
	if not db or not db.enabled then
		container:Hide()
		module:ShowBlizzHeaderButtons(true)
		RestoreBlizzardTabs()
		return
	end

	container:Show()
	module:ShowBlizzHeaderButtons(false)
	HideBlizzardTabs()

	-- Destroy old child buttons
	if container.buttons then
		for _, btn in ipairs(container.buttons) do
			btn:Hide()
			btn:SetParent(nil)
		end
	end
	container.buttons = {}

	-- Destroy old tab label
	if container.tabLabelBtn then
		container.tabLabelBtn:Hide()
		container.tabLabelBtn:SetParent(nil)
		container.tabLabelBtn = nil
		container.tabLabel = nil
		container.unreadDot = nil
	end

	-- Collect enabled buttons, split by side field
	local btnVisibility = db.buttons or {}
	local leftButtons = {}
	local rightButtons = {}
	for _, def in ipairs(HEADER_BUTTON_DEFS) do
		if btnVisibility[def.key] ~= false then
			local btn = CreateHeaderIconButton(container, def.icon, def.tooltip, def.action)
			btn.key = def.key
			btn.def = def
			container.buttons[#container.buttons + 1] = btn

			-- Social button: add friend count (text is part of the button hitbox)
			if def.key == 'social' then
				local friendCount = btn:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
				friendCount:SetPoint('LEFT', btn.iconTex, 'RIGHT', 2, 0)
				friendCount:SetTextColor(0.6, 0.8, 1, 1)
				friendCount:SetFont(friendCount:GetFont(), 9, 'OUTLINE')
				btn.friendCount = friendCount
				btn:SetWidth(HEADER_ICON_SIZE + 14)
			end

			-- Errors button: hidden by default, anchored after layout
			if def.special == 'errors' then
				btn:Hide()
				local countLabel = btn:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
				countLabel:SetPoint('LEFT', btn.iconTex, 'RIGHT', 2, 0)
				countLabel:SetTextColor(1, 0.2, 0.2, 1)
				countLabel:SetFont(countLabel:GetFont(), 9, 'OUTLINE')
				btn.countLabel = countLabel
				btn.isErrorBtn = true
			end

			if def.special ~= 'errors' then
				if def.side == 'left' then
					leftButtons[#leftButtons + 1] = btn
				else
					rightButtons[#rightButtons + 1] = btn
				end
			end
		end
	end

	-- Layout LEFT group: anchor left-to-right from GDM left edge
	for i, btn in ipairs(leftButtons) do
		btn:ClearAllPoints()
		if i == 1 then
			btn:SetPoint('LEFT', container, 'LEFT', 4, 0)
		else
			btn:SetPoint('LEFT', leftButtons[i - 1], 'RIGHT', HEADER_GAP, 0)
		end
	end

	-- Anchor error button next to last left button (floats, not part of layout)
	for _, btn in ipairs(container.buttons) do
		if btn.isErrorBtn then
			btn:ClearAllPoints()
			local anchor = leftButtons[#leftButtons]
			if anchor then
				btn:SetPoint('LEFT', anchor, 'RIGHT', HEADER_GAP, 0)
			else
				btn:SetPoint('LEFT', container, 'LEFT', 4, 0)
			end
		end
	end

	-- Layout RIGHT group: anchor right-to-left from GDM right edge
	for i, btn in ipairs(rightButtons) do
		btn:ClearAllPoints()
		if i == 1 then
			btn:SetPoint('RIGHT', container, 'RIGHT', -4, 0)
		else
			btn:SetPoint('RIGHT', rightButtons[i - 1], 'LEFT', -HEADER_GAP, 0)
		end
	end

	-- Create active tab label centered between button groups
	local tabLabelBtn = CreateFrame('Button', nil, container)
	tabLabelBtn:SetHeight(HEADER_ICON_SIZE)

	local tabLabel = tabLabelBtn:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	tabLabel:SetPoint('CENTER', tabLabelBtn, 'CENTER', 0, 0)
	tabLabel:SetTextColor(0.6, 0.6, 0.6, 1)
	tabLabel:SetText(GetActiveChatFrameName())
	container.tabLabel = tabLabel

	-- Unread activity dot
	local unreadDot = tabLabelBtn:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	unreadDot:SetPoint('LEFT', tabLabel, 'RIGHT', 3, 0)
	unreadDot:SetText('*')
	unreadDot:SetTextColor(1, 0.5, 0, 1)
	unreadDot:Hide()
	container.unreadDot = unreadDot

	-- Stretch to fill the entire gap between left and right button groups
	-- rightButtons are ordered outermost-first (settings at [1], emoji at [#rightButtons])
	tabLabelBtn:ClearAllPoints()
	local lastLeft = leftButtons[#leftButtons]
	local innermostRight = rightButtons[#rightButtons]
	-- Store left anchor for dynamic re-anchoring when error button shows/hides
	container.leftAnchor = lastLeft or container
	if lastLeft and innermostRight then
		tabLabelBtn:SetPoint('LEFT', lastLeft, 'RIGHT', HEADER_GAP, 0)
		tabLabelBtn:SetPoint('RIGHT', innermostRight, 'LEFT', -HEADER_GAP, 0)
	elseif lastLeft then
		tabLabelBtn:SetPoint('LEFT', lastLeft, 'RIGHT', HEADER_GAP, 0)
		tabLabelBtn:SetPoint('RIGHT', container, 'RIGHT', -4, 0)
	elseif innermostRight then
		tabLabelBtn:SetPoint('LEFT', container, 'LEFT', 4, 0)
		tabLabelBtn:SetPoint('RIGHT', innermostRight, 'LEFT', -HEADER_GAP, 0)
	else
		tabLabelBtn:SetPoint('LEFT', container, 'LEFT', 4, 0)
		tabLabelBtn:SetPoint('RIGHT', container, 'RIGHT', -4, 0)
	end

	container.tabLabelBtn = tabLabelBtn
	tabLabelBtn:RegisterForClicks('LeftButtonUp', 'RightButtonUp')

	-- Trigger behavior based on mode
	local hoverTimer
	local mode = db.tabSwitcherMode or 'hover'

	tabLabelBtn:SetScript('OnEnter', function(self)
		tabLabel:SetTextColor(1, 0.82, 0, 1)
		if mode == 'hover' then
			if tabDropdownCloseTimer then
				tabDropdownCloseTimer:Cancel()
				tabDropdownCloseTimer = nil
			end
			if hoverTimer then
				hoverTimer:Cancel()
			end
			hoverTimer = C_Timer.NewTimer(0.15, function()
				OpenTabDropdown(self)
				hoverTimer = nil
			end)
		end
		if not GameTooltip:IsForbidden() then
			GameTooltip:SetOwner(self, 'ANCHOR_NONE')
			GameTooltip:SetPoint('BOTTOMLEFT', self, 'TOPRIGHT', 2, 2)
			GameTooltip:AddLine('Shift+Click to clear chat', 0.8, 0.4, 0)
			GameTooltip:AddLine('Right-Click for tab menu', 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end
	end)

	tabLabelBtn:SetScript('OnLeave', function()
		tabLabel:SetTextColor(0.6, 0.6, 0.6, 1)
		if mode == 'hover' then
			if hoverTimer then
				hoverTimer:Cancel()
				hoverTimer = nil
			end
			if tabDropdownCloseTimer then
				tabDropdownCloseTimer:Cancel()
			end
			tabDropdownCloseTimer = C_Timer.NewTimer(0.3, function()
				CloseTabDropdown()
			end)
		end
		if not GameTooltip:IsForbidden() then
			GameTooltip:Hide()
		end
	end)

	tabLabelBtn:SetScript('OnClick', function(self, clickBtn)
		if clickBtn == 'RightButton' then
			local dock = GENERAL_CHAT_DOCK
			local activeCF = dock and dock.selected or DEFAULT_CHAT_FRAME
			if activeCF then
				local id = activeCF:GetID()
				CURRENT_CHAT_FRAME_ID = id
				self.GetID = function()
					return id
				end
				if FCF_Tab_SetupMenu then
					FCF_Tab_SetupMenu(self)
				end
			end
			CloseTabDropdown()
			return
		end
		if IsShiftKeyDown() then
			local dock = GENERAL_CHAT_DOCK
			local activeCF = dock and dock.selected or DEFAULT_CHAT_FRAME
			if activeCF then
				activeCF:Clear()
				SUI:Print('Chat cleared')
			end
			CloseTabDropdown()
			return
		end
		if mode == 'click' then
			if tabDropdown and tabDropdown:IsShown() then
				CloseTabDropdown()
			else
				OpenTabDropdown(self)
			end
		end
	end)

	-- Click mode: close on click outside (GLOBAL_MOUSE_DOWN)
	if not module.tabDropdownGlobalMouseHooked then
		module.tabDropdownGlobalMouseHooked = true
		local globalCloseFrame = CreateFrame('Frame', nil, UIParent)
		globalCloseFrame:RegisterEvent('GLOBAL_MOUSE_DOWN')
		globalCloseFrame:SetScript('OnEvent', function()
			if not tabDropdown or not tabDropdown:IsShown() then
				return
			end
			local curMode = module.CurrentSettings.headerButtons.tabSwitcherMode or 'hover'
			if curMode ~= 'click' then
				return
			end
			if tabDropdown:IsMouseOver() then
				return
			end
			local container2 = _G['SUI_ChatHeaderButtons']
			if container2 and container2.tabLabelBtn and container2.tabLabelBtn:IsMouseOver() then
				return
			end
			CloseTabDropdown()
		end)
	end

	-- Hook tab selection to keep label updated
	if not module.tabSelectHooked then
		module.tabSelectHooked = true
		hooksecurefunc('FCFDock_SelectWindow', function()
			C_Timer.After(0, function()
				module:UpdateTabLabel()
			end)
		end)
		-- Hook tab flashing for unread indicator
		if FCFTab_FlashTab then
			hooksecurefunc('FCFTab_FlashTab', function()
				module:UpdateTabLabel()
			end)
		end
		if FCFTab_StopFlashTab then
			hooksecurefunc('FCFTab_StopFlashTab', function()
				module:UpdateTabLabel()
			end)
		end
		-- Re-evaluate tab visibility when frames are docked/undocked
		if FCF_DockFrame then
			hooksecurefunc('FCF_DockFrame', function()
				C_Timer.After(0, function()
					HideBlizzardTabs()
					module:UpdateTabLabel()
				end)
			end)
		end
		if FCF_UnDockFrame then
			hooksecurefunc('FCF_UnDockFrame', function(frame)
				C_Timer.After(0, function()
					-- Immediately restore the tab for the undocked frame
					if frame then
						local tab = _G[frame:GetName() .. 'Tab']
						if tab then
							tab:SetScript('OnShow', nil)
							tab:Show()
							StyleUndockedTab(tab)
						end
					end
					HideBlizzardTabs()
					module:UpdateTabLabel()
				end)
			end)
		end
	end

	-- Update friend count and error state
	C_Timer.After(0.1, function()
		module:UpdateHeaderFriendCount()
		module:UpdateHeaderErrorButton()
		module:UpdateTabLabel()
	end)
end
