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
local CONFLICTS = { 'WIM', 'WhisperDeck' }

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

function module:OnInitialize()
	for _, addon in ipairs(CONFLICTS) do
		if SUI:IsAddonEnabled(addon) then
			module.Override = true
		end
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
