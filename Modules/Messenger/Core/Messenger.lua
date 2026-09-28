local _, ns = ...
local M = ns.Messenger
local U = M.Util

-- Lifecycle and the public API used by hosts, key bindings and the UI.

local Store = M.Store

---Views (deck, pop-outs) register here so unread counting knows what the player can see.
---@type table<table, boolean>
M.views = {}

---@param key string
---@return boolean
function M:IsViewing(key)
	for view in pairs(self.views) do
		if view:IsViewing(key) then
			return true
		end
	end
	return false
end

---Title for a conversation. Battle.net names come from the live friend list when available.
---@param convo MessengerConversation
---@return string
function M:GetTitle(convo)
	if convo.kind == 'BN_WHISPER' and convo.target then
		local entry = self.Contacts:GetBNetByTag(convo.target)
		if entry and entry.accountName then
			return entry.accountName
		end
	end
	return convo.name or convo.key
end

---@param host MessengerHost
function M:Initialize(host)
	self.host = host
	self.mediaPath = host.mediaPath
	if host.logger then
		self.log = host.logger
	end
	self.defaults.profile.minimap.hide = host.minimapHiddenByDefault and true or false
	self.db = LibStub('AceDB-3.0'):New(host.savedVariable, self.defaults, true)
	self.settings = self.db.profile

	local function ProfileChanged()
		self.settings = self.db.profile
		if self.enabled then
			self.Router:RefreshEvents()
		end
		self:Fire('SETTINGS_CHANGED')
	end
	self.db.RegisterCallback(self, 'OnProfileChanged', ProfileChanged)
	self.db.RegisterCallback(self, 'OnProfileCopied', ProfileChanged)
	self.db.RegisterCallback(self, 'OnProfileReset', ProfileChanged)
end

function M:Enable()
	if self.enabled or not self.db then
		return
	end
	self.enabled = true
	Store:Prune()
	self.Contacts:Enable()
	self.Router:Enable()
	self.Rooms:Enable()
	self.Integration:Enable()
	self.UI:Enable()
	self.log.info('Messenger enabled')
end

function M:Disable()
	if not self.enabled then
		return
	end
	self.enabled = false
	self.Router:Disable()
	self.Rooms:Disable()
	self.Contacts:Disable()
	self.Integration:Disable()
	self.UI:Disable()
	self.log.info('Messenger disabled')
end

---Call after changing which chats are captured.
function M:RoutesChanged()
	if self.enabled then
		self.Router:RefreshEvents()
		self.Rooms:Sync(true)
	end
	self:Fire('SETTINGS_CHANGED')
end

----------------------------------------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------------------------------------

function M:Toggle()
	if self.enabled then
		self.UI.Deck:Toggle()
	end
end

---Opens the deck on a conversation.
---@param key? string
---@param focus? boolean Put the cursor in the composer
function M:Open(key, focus)
	if self.enabled then
		self.UI.Deck:Open(key, focus)
	end
end

---Starts or resumes a whisper conversation with a character.
---@param name string Name or Name-Realm
---@param focus? boolean
---@return string|nil key
function M:OpenWhisper(name, focus)
	local full = U.FullName(name)
	if not full or not self.enabled then
		return nil
	end
	local key = Store.CharKey(full)
	local convo = Store:Get(key)
	Store:Ensure(key, { kind = 'WHISPER', name = convo and convo.name or U.DisplayName(full), target = convo and convo.target or full, closed = false })
	self:Open(key, focus ~= false)
	return key
end

---Starts or resumes a Battle.net conversation.
---@param entry table { tag = BattleTag }
---@param focus? boolean
---@return string|nil key
function M:OpenBNet(entry, focus)
	if not entry or not entry.tag or not self.enabled then
		return nil
	end
	local key = Store.BNetKey(entry.tag)
	Store:Ensure(key, { kind = 'BN_WHISPER', name = entry.tag:match('^([^#]+)') or entry.tag, target = entry.tag, closed = false })
	self:Open(key, focus ~= false)
	return key
end

---Opens the last person who whispered, ready to answer.
function M:ReplyLast()
	local key = self.Router.lastIncoming
	if key and Store:Get(key) then
		self:Open(key, true)
	else
		self:Open(nil, false)
	end
end

---Opens the most recent unread conversation.
function M:OpenUnread()
	local convo = Store:NextUnread()
	self:Open(convo and convo.key or nil, convo ~= nil)
end

---Tears a conversation off into its own window.
---@param key string
function M:PopOut(key)
	if self.enabled and Store:Get(key) then
		self.UI.PopOut:Open(key, true)
	end
end

---The open/close key as the game shows it (for example "Ctrl-O"), or nil when none is set.
---@return string|nil
function M:GetToggleKeyText()
	local command = self.host and self.host.toggleBinding
	local key = command and GetBindingKey(command)
	if not key then
		return nil
	end
	return GetBindingText and GetBindingText(key) or key
end

function M:OpenOptions()
	if self.host and self.host.OpenOptions then
		self.host.OpenOptions()
	end
end
