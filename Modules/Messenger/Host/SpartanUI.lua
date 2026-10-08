local _, ns = ...
local SUI = SUI
local L = SUI.L
local M = ns.Messenger

-- SpartanUI host adapter. This is the only Messenger file that knows about SpartanUI: it turns
-- the portable core into a SpartanUI module, puts its settings under /sui > Modules, and adds a
-- button to the SpartanUI chat header. Shipping Messenger as its own addon means replacing this
-- file with a standalone host.

---@class SUI.Module.Messenger : SUI.Module
local module = SUI:NewModule('Messenger')
module.DisplayName = L['Messenger']
module.description = 'Whispers and chats as instant-messenger style conversations'

-- Addons that already manage whispers; running two would split conversations between them
module.ConflictsWith = { 'WIM', 'WhisperDeck' }

local HEADER_KEY = 'messenger'

BINDING_HEADER_SUIMESSENGER = L['Messenger']
_G['BINDING_NAME_SUIMESSENGER_TOGGLE'] = L['Open Messenger']
_G['BINDING_NAME_SUIMESSENGER_REPLY'] = L['Reply to last whisper']
_G['BINDING_NAME_SUIMESSENGER_UNREAD'] = L['Open next unread conversation']

function SUIMessenger_Toggle()
	M:Toggle()
end

function SUIMessenger_Reply()
	M:ReplyLast()
end

function SUIMessenger_Unread()
	M:OpenUnread()
end

local function UpdateHeaderCount()
	local container = _G['SUI_ChatHeaderButtons']
	if not container or not container.buttons then
		return
	end
	for _, btn in ipairs(container.buttons) do
		if btn.key == HEADER_KEY and btn.unreadLabel then
			local unread = M.enabled and M.Store:TotalUnread() or 0
			btn.unreadLabel:SetText(unread > 0 and tostring(unread) or '')
			local width = btn.unreadLabel:GetStringWidth()
			btn:SetWidth(16 + (unread > 0 and SUI.BlizzAPI.canaccessvalue(width) and (width + 2) or 0))
		end
	end
end

local function AddChatHeaderButton()
	local chat = SUI:GetModule('Chatbox', true)
	if not chat or not chat.AddHeaderButton then
		return
	end
	chat:AddHeaderButton({
		key = HEADER_KEY,
		icon = 'messenger',
		side = 'left',
		tooltip = L['Messenger'],
		action = function()
			M:Toggle()
		end,
		onCreate = function(btn)
			local label = btn:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
			label:SetPoint('LEFT', btn.iconTex, 'RIGHT', 2, 0)
			label:SetFont(label:GetFont(), 9, 'OUTLINE')
			local info = ChatTypeInfo and ChatTypeInfo.WHISPER
			label:SetTextColor(info and info.r or 1, info and info.g or 0.5, info and info.b or 1, 1)
			btn.unreadLabel = label
			btn:HookScript('OnEnter', function(self)
				local key = M:GetToggleKeyText()
				if key and GameTooltip:IsOwned(self) then
					GameTooltip:AddLine(string.format(L['Press %s to open or close'], key), 0.6, 0.6, 0.6)
					GameTooltip:Show()
				end
			end)
			C_Timer.After(0, UpdateHeaderCount)
		end,
	})
	M:On('UNREAD_CHANGED', UpdateHeaderCount)
end

---Messenger's switches on the setup window's Helpers page
local function RegisterSetupStep()
	if not (SUI.Setup and SUI.Setup.AddHelpers) then
		return
	end
	local function Routes(keys, value)
		for _, key in ipairs(keys) do
			local route = M:GetRoute(key)
			if route then
				route.capture = value
			end
		end
		M:RoutesChanged()
	end
	local function AllCaptured(keys)
		for _, key in ipairs(keys) do
			if not M:IsCaptured(key) then
				return false
			end
		end
		return true
	end
	local WHISPERS = { 'WHISPER', 'BN_WHISPER' }
	local GROUP_CHAT = { 'GUILD', 'PARTY' }
	SUI.Setup:AddHelpers('messages', {
		{
			key = 'messenger:whispers',
			title = L['Keep whispers as conversations in Messenger'],
			caption = L['Whispers leave the main chat and open in their own window.'],
			recommended = true,
			module = 'Messenger',
			get = function()
				return M.settings ~= nil and AllCaptured(WHISPERS)
			end,
			set = function(value)
				if M.settings then
					Routes(WHISPERS, value)
				end
			end,
		},
		{
			key = 'messenger:takeover',
			title = L['Whispers you start in the main chat open there too'],
			caption = L['Typing /w Name or clicking a name moves you into Messenger.'],
			module = 'Messenger',
			get = function()
				return M.settings ~= nil and M.settings.takeOverWhispers == true
			end,
			set = function(value)
				if M.settings then
					M.settings.takeOverWhispers = value
					M:Fire('SETTINGS_CHANGED')
				end
			end,
		},
		{
			key = 'messenger:groupchat',
			title = L['Also keep guild and party chat in Messenger'],
			caption = L['You can pick each chat later in Messenger settings.'],
			module = 'Messenger',
			get = function()
				return M.settings ~= nil and AllCaptured(GROUP_CHAT)
			end,
			set = function(value)
				if M.settings then
					Routes(GROUP_CHAT, value)
				end
			end,
		},
	})
end

function module:OnInitialize()
	if #SUI:GetModuleConflicts(module) > 0 then
		module.Override = true
	end

	M:Initialize({
		name = 'SpartanUI',
		savedVariable = 'SpartanUIMessengerDB',
		mediaPath = 'Interface\\AddOns\\SpartanUI\\Modules\\Messenger\\Media\\',
		logger = SUI.logger and SUI.logger:RegisterCategory('Messenger') or nil,
		minimapHiddenByDefault = true,
		replyBinding = 'SUIMESSENGER_REPLY',
		toggleBinding = 'SUIMESSENGER_TOGGLE',
		defaultToggleKey = 'CTRL-O',
		emojiPath = 'Interface\\AddOns\\SpartanUI\\images\\chatbox\\emojis\\',
		OpenOptions = function()
			SUI.Options:OpenModuleSettings('Messenger')
		end,
	})
end

function module:OnEnable()
	local options = M:BuildOptionsTable()
	options.name = module.DisplayName
	options.disabled = function()
		return SUI:IsModuleDisabled(module)
	end
	SUI.Options:AddOptions(options, 'Messenger')
	RegisterSetupStep()

	if SUI:IsModuleDisabled(module) then
		return
	end
	M:Enable()
	SUI.Messenger = M
	if not module.headerAdded then
		module.headerAdded = true
		AddChatHeaderButton()
	end
	UpdateHeaderCount()
	SUI:AddChatCommand('messenger', function()
		M:Toggle()
	end, 'Open or close Messenger', nil, true)
end

function module:OnDisable()
	M:Disable()
	UpdateHeaderCount()
end
