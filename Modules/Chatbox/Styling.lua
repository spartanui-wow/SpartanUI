---@class SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.Chatbox
local module = SUI:GetModule('Chatbox')

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
	module:ApplyHideChatButtons()
	module:ApplyHideSocialButton()
	module:ApplyDisableChatFade()
	module:ApplyChatHistoryLines()
end

function module:ApplyHideChatButtons()
	local ChatFrameMenuBtn = _G['ChatFrameMenuButton']
	local VoiceChannelButton = _G['ChatFrameChannelButton']

	if module.DB.hideChatButtons then
		if ChatFrameMenuBtn then
			ChatFrameMenuBtn:Hide()
			ChatFrameMenuBtn:SetScript('OnShow', function(self)
				if module.DB.hideChatButtons then
					self:Hide()
				end
			end)
		end
		if VoiceChannelButton then
			VoiceChannelButton:Hide()
			VoiceChannelButton:SetScript('OnShow', function(self)
				if module.DB.hideChatButtons then
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
				if module.DB.hideChatButtons and chatFrame and chatFrame.buttonFrame then
					chatFrame.buttonFrame:SetAlpha(0)
					chatFrame.buttonFrame:EnableMouse(false)
				end
			end)
		end

		if FCF_FadeOutChatFrame then
			hooksecurefunc('FCF_FadeOutChatFrame', function(chatFrame)
				if module.DB.hideChatButtons and chatFrame and chatFrame.buttonFrame then
					chatFrame.buttonFrame:SetAlpha(0)
					chatFrame.buttonFrame:EnableMouse(false)
				end
			end)
		end
	end
end

function module:ApplyHideSocialButton()
	local QJTB = _G['QuickJoinToastButton']
	if not QJTB then
		return
	end

	if module.DB.hideSocialButton then
		QJTB:Hide()
		QJTB:SetScript('OnShow', function(self)
			if module.DB.hideSocialButton then
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

	SetAllChatFading(not module.DB.disableChatFade)

	if not module.chatFadeHooksApplied then
		module.chatFadeHooksApplied = true

		if FCF_OpenTemporaryWindow then
			hooksecurefunc('FCF_OpenTemporaryWindow', function()
				if module.DB.disableChatFade then
					local cf = FCF_GetCurrentChatFrame and FCF_GetCurrentChatFrame()
					if cf and cf.SetFading then
						cf:SetFading(false)
					end
				end
			end)
		end

		if FloatingChatFrame_Update then
			hooksecurefunc('FloatingChatFrame_Update', function(id)
				if module.DB.disableChatFade then
					local ChatFrame = _G['ChatFrame' .. id]
					if ChatFrame and ChatFrame.SetFading then
						ChatFrame:SetFading(false)
					end
				end
			end)
		end

		if FCF_CopyChatSettings then
			hooksecurefunc('FCF_CopyChatSettings', function(copyTo)
				if module.DB.disableChatFade and copyTo and copyTo.SetFading then
					copyTo:SetFading(false)
				end
			end)
		end
	end
end

function module:ApplyChatHistoryLines()
	local lines = module.DB.chatHistoryLines or 128
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

	BNToastFrame:ClearAllPoints()
	BNToastFrame:SetPoint('BOTTOM', GDM, 'TOP')
	local function fixbnetpos(frame, _, anchor)
		if anchor ~= GDM then
			frame:ClearAllPoints()
			BNToastFrame:SetPoint('BOTTOM', GDM, 'TOP')
		end
	end
	hooksecurefunc(BNToastFrame, 'SetPoint', fixbnetpos)

	local VoiceChannelButton = _G['ChatFrameChannelButton']
	if VoiceChannelButton then
		VoiceChannelButton:ClearAllPoints()
		VoiceChannelButton:SetParent(GDM)
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

		if SUI.IsRetail then
			local sides = { 'Left', 'Middle', 'Right' }
			local modes = { 'Active', 'Highlight', '' }
			for _, mode in ipairs(modes) do
				for _, side in ipairs(sides) do
					ChatFrameTab[mode .. side]:SetTexture(nil)
				end
			end
		else
			for _, v in ipairs({ 'left', 'middle', 'right' }) do
				ChatFrameTab[v .. 'HighlightTexture']:SetTexture(nil)
				ChatFrameTab[v .. 'SelectedTexture']:SetTexture(nil)
				ChatFrameTab[v .. 'Texture']:SetTexture(nil)
			end
		end

		-- Selection area
		if ChatFrame.Selection then
			ChatFrame.Selection:ClearAllPoints()
			ChatFrame.Selection:SetPoint('TOPLEFT', ChatFrame, 'TOPLEFT', 0, 30)
			ChatFrame.Selection:SetPoint('BOTTOMRIGHT', ChatFrame, 'BOTTOMRIGHT', 25, -32)
		end

		-- Font
		SUI.Font:Format(ChatFrame, module.DB.fontSize, 'Chatbox')

		-- ButtonFrame (only disable if hideChatButtons enabled)
		local buttonFrame = _G[ChatFrameName .. 'ButtonFrame']
		if buttonFrame and module.DB.hideChatButtons then
			disable(buttonFrame)
		end
	end
end
