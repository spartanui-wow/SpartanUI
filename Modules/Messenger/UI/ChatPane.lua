local _, ns = ...
local M = ns.Messenger
local T = M.Theme
local U = M.Util
local W = M.Widgets
local L = M.L

-- One conversation view: header, restriction notice, message log and composer.
-- Used by the deck (with header) and by pop-out windows (the window title acts as the header).

---@class Messenger.ChatPane
local CP = {}
M.ChatPane = CP

local BANNER_H = 26

local InviteUnit = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
local AddFriend = (C_FriendList and C_FriendList.AddFriend) or AddFriend
local AddIgnore = (C_FriendList and C_FriendList.AddIgnore) or AddIgnore

---Actions for a conversation, shared by the header's more button and the list's right-click.
---@param convo MessengerConversation
---@param context? 'popout'
---@return MessengerMenuItem[]
function CP.ConversationMenu(convo, context)
	local key = convo.key
	local Store = M.Store
	local items = {}
	local isRoom = Store.IsRoomKey(key)

	if convo.kind == 'WHISPER' then
		table.insert(items, {
			text = L['Invite to group'],
			onClick = function()
				InviteUnit(convo.target)
			end,
		})
		if not M.Contacts:IsFriend(convo.target) then
			table.insert(items, {
				text = L['Add friend'],
				onClick = function()
					AddFriend(convo.target)
				end,
			})
		end
	elseif convo.kind == 'BN_WHISPER' then
		local entry = M.Contacts:GetBNetByTag(convo.target or '')
		if entry and entry.character then
			local who = U.JoinName(entry.character, entry.realm) or entry.character
			table.insert(items, {
				text = L['Invite to group'],
				onClick = function()
					InviteUnit(who)
				end,
			})
		end
	end

	local alias = M:GetAlias(key)
	table.insert(items, {
		text = alias and L['Change nickname'] or L['Set a nickname'],
		divider = #items > 0,
		onClick = function()
			M:Open(key, false)
			M.UI.Deck.pane:EditNickname()
		end,
	})
	if alias then
		table.insert(items, {
			text = L['Remove nickname'],
			onClick = function()
				M:SetAlias(key, nil)
			end,
		})
	end
	table.insert(items, {
		text = convo.pinned and L['Unpin'] or L['Pin to top'],
		divider = true,
		onClick = function()
			Store:SetFlag(key, 'pinned', not convo.pinned)
		end,
	})
	table.insert(items, {
		text = L['Mute alerts'],
		checked = convo.muted == true,
		onClick = function()
			Store:SetFlag(key, 'muted', not convo.muted)
		end,
	})
	if context ~= 'popout' then
		table.insert(items, {
			text = L['Open in its own window'],
			onClick = function()
				M:PopOut(key)
			end,
		})
	else
		local PopOut = M.UI.PopOut
		local saved = PopOut:Saved(key)
		table.insert(items, {
			text = L['Show controls only on mouse-over'],
			divider = true,
			checked = saved.overlay == true,
			onClick = function()
				PopOut:SetOverlay(key, not saved.overlay)
			end,
		})
		for _, opacity in ipairs({ 1, 0.8, 0.6, 0.4 }) do
			table.insert(items, {
				text = opacity == 1 and L['Solid background'] or string.format(L['See-through background: %d%%'], math.floor(opacity * 100 + 0.5)),
				checked = (saved.opacity or 1) == opacity,
				onClick = function()
					PopOut:SetOpacity(key, opacity)
				end,
			})
		end
	end
	table.insert(items, {
		text = L['Close conversation'],
		onClick = function()
			Store:SetFlag(key, 'closed', true)
		end,
	})

	if isRoom then
		table.insert(items, {
			text = L['Stop showing this chat here'],
			divider = true,
			onClick = function()
				local route = M:GetRoute(convo.kind, convo.kind == 'CHANNEL' and convo.target or nil)
				if route then
					route.capture = false
					M:RoutesChanged()
				end
				Store:SetFlag(key, 'closed', true)
			end,
		})
		table.insert(items, {
			text = L['Clear history'],
			danger = true,
			onClick = function()
				Store:Clear(key)
				M.UI.Toast:ShowUndo(string.format(L['Cleared %s'], M:GetTitle(convo)))
			end,
		})
	else
		if convo.kind == 'WHISPER' then
			table.insert(items, {
				text = L['Ignore player'],
				divider = true,
				danger = true,
				onClick = function()
					W.Confirm(string.format(L['Ignore %s? You will stop getting their messages.'], convo.name), function()
						AddIgnore(convo.target)
						Store:SetFlag(key, 'closed', true)
					end)
				end,
			})
		end
		table.insert(items, {
			text = L['Delete conversation'],
			divider = convo.kind ~= 'WHISPER',
			danger = true,
			onClick = function()
				local title = M:GetTitle(convo)
				Store:Delete(key)
				M.UI.Toast:ShowUndo(string.format(L['Deleted your conversation with %s'], title))
			end,
		})
	end
	return items
end

---@class MessengerChatPane : Frame
local Pane = {}

---@param parent Frame
---@param showHeader boolean
---@return MessengerChatPane
function CP.Create(parent, showHeader)
	local pane = CreateFrame('Frame', nil, parent)
	Mixin(pane, Pane)
	pane.showHeader = showHeader

	-- Header
	local header = CreateFrame('Frame', nil, pane)
	header:SetPoint('TOPLEFT')
	header:SetPoint('TOPRIGHT')
	header:SetHeight(showHeader and T.Metrics().header or 0.001)
	header:SetShown(showHeader)
	pane.header = header
	if showHeader then
		T.Line(header, 'BOTTOM')

		header.avatar = W.Avatar(header, 30)
		header.avatar:SetPoint('LEFT', 14, 0)

		header.more = W.IconButton(header, 'more', 24, L['More'], function(btn)
			local convo = pane.key and M.Store:Get(pane.key)
			if convo then
				W.OpenMenu(btn, CP.ConversationMenu(convo))
			end
		end)
		header.more:SetPoint('RIGHT', -10, 0)

		header.popout = W.IconButton(header, 'popout', 24, L['Open in its own window'], function()
			if pane.key then
				M:PopOut(pane.key)
			end
		end)
		header.popout:SetPoint('RIGHT', header.more, 'LEFT', -2, 0)

		header.pin = W.IconButton(header, 'pin', 24, L['Pin to top'], function()
			local convo = pane.key and M.Store:Get(pane.key)
			if convo then
				M.Store:SetFlag(pane.key, 'pinned', not convo.pinned)
			end
		end)
		header.pin:SetPoint('RIGHT', header.popout, 'LEFT', -2, 0)

		header.title = T.Text(header, 'name')
		T.Bump(header.title, 2)
		header.title:SetPoint('TOPLEFT', header.avatar, 'TOPRIGHT', 10, 1)
		header.title:SetPoint('RIGHT', header.pin, 'LEFT', -8, 0)

		-- Double-clicking the name gives it a nickname; right-clicking a player's name opens the
		-- game's own player menu (invite, add friend, report)
		header.nameButton = CreateFrame('Button', nil, header)
		header.nameButton:SetPoint('TOPLEFT', header.title, 'TOPLEFT')
		header.nameButton:SetPoint('BOTTOMRIGHT', header.title, 'BOTTOMRIGHT')
		header.nameButton:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
		header.nameButton:SetScript('OnClick', function(_, button)
			local convo = pane.key and M.Store:Get(pane.key)
			if button == 'RightButton' and convo and convo.kind == 'WHISPER' and convo.target then
				SetItemRef('player:' .. convo.target, '[' .. convo.name .. ']', 'RightButton', DEFAULT_CHAT_FRAME)
			end
		end)
		header.nameButton:SetScript('OnDoubleClick', function()
			pane:EditNickname()
		end)
		header.nameButton:SetScript('OnEnter', function(self)
			local convo = pane.key and M.Store:Get(pane.key)
			local hint = convo and convo.kind == 'WHISPER' and L['Right-click for player options'] or nil
			W.ShowTip(self, L['Double-click to set a nickname'], hint)
		end)
		header.nameButton:SetScript('OnLeave', function()
			GameTooltip:Hide()
		end)

		header.subtitle = T.Text(header, 'meta', T.color.muted)
		header.subtitle:SetPoint('BOTTOMLEFT', header.avatar, 'BOTTOMRIGHT', 10, 0)
		header.subtitle:SetPoint('RIGHT', header.pin, 'LEFT', -8, 0)

		header.muted = header:CreateTexture(nil, 'ARTWORK')
		header.muted:SetSize(14, 14)
		T.SetIcon(header.muted, 'mute')
		header.muted:SetVertexColor(T.color.faint[1], T.color.faint[2], T.color.faint[3])
	end

	-- Restriction notice
	local banner = CreateFrame('Frame', nil, pane)
	banner:SetPoint('TOPLEFT', header, 'BOTTOMLEFT')
	banner:SetPoint('TOPRIGHT', header, 'BOTTOMRIGHT')
	banner:SetHeight(BANNER_H)
	T.Fill(banner, { T.color.warn[1], T.color.warn[2], T.color.warn[3], 0.1 })
	T.Line(banner, 'BOTTOM', { T.color.warn[1], T.color.warn[2], T.color.warn[3], 0.25 })
	banner.icon = banner:CreateTexture(nil, 'ARTWORK')
	banner.icon:SetSize(14, 14)
	banner.icon:SetPoint('LEFT', 14, 0)
	T.SetIcon(banner.icon, 'info')
	banner.icon:SetVertexColor(unpack(T.color.warn))
	banner.text = T.Text(banner, 'meta', T.color.warn)
	banner.text:SetPoint('LEFT', banner.icon, 'RIGHT', 6, 0)
	banner.text:SetPoint('RIGHT', -10, 0)
	banner.text:SetText(L['Some messages are hidden during this fight. They will show up here when it ends.'])
	banner:Hide()
	pane.banner = banner

	pane.composer = M.Composer.Create(pane)
	pane.composer:SetPoint('BOTTOMLEFT')
	pane.composer:SetPoint('BOTTOMRIGHT')

	pane.log = M.MessageLog.Create(pane)
	pane.log:SetPoint('BOTTOMLEFT', pane.composer, 'TOPLEFT')
	pane.log:SetPoint('BOTTOMRIGHT', pane.composer, 'TOPRIGHT')
	pane:LayoutTop()

	M.views[pane] = true

	M:On('CONVO_CHANGED', function(key)
		if key == pane.key then
			pane:UpdateHeader()
		end
	end)
	M:On('LIST_CHANGED', function()
		M:Defer('pane-header-' .. tostring(pane), function()
			pane:UpdateHeader()
		end)
	end)
	M:On('FONTS_CHANGED', function()
		if pane.showHeader then
			pane.header:SetHeight(T.Metrics().header)
		end
	end)
	M:On('CONTACTS_CHANGED', function()
		pane:UpdateHeader()
	end)
	M:On('RESTRICTION_CHANGED', function()
		pane:UpdateBanner()
	end)
	M:On('CONVO_DELETED', function(key)
		if key == nil or key == pane.key then
			pane:SetConversation(nil)
		end
	end)
	return pane
end

function Pane:LayoutTop()
	self.log:ClearAllPoints()
	self.log:SetPoint('BOTTOMLEFT', self.composer, 'TOPLEFT')
	self.log:SetPoint('BOTTOMRIGHT', self.composer, 'TOPRIGHT')
	if self.banner:IsShown() then
		self.log:SetPoint('TOPLEFT', self.banner, 'BOTTOMLEFT')
	else
		self.log:SetPoint('TOPLEFT', self.header, 'BOTTOMLEFT')
	end
end

function Pane:UpdateBanner()
	local show = self.key ~= nil and (U.IsRestricted() or M.Router:HasDeferred())
	if show ~= self.banner:IsShown() then
		self.banner:SetShown(show)
		self:LayoutTop()
	end
end

function Pane:UpdateHeader()
	if not self.showHeader then
		return
	end
	local header = self.header
	local convo = self.key and M.Store:Get(self.key)
	if not convo then
		header.title:SetText('')
		header.subtitle:SetText('')
		header.avatar:Hide()
		header.pin:Hide()
		header.popout:Hide()
		header.more:Hide()
		header.nameButton:Hide()
		header.muted:Hide()
		return
	end
	local presence = M.Contacts:GetPresence(convo)
	header.nameButton:SetShown(true)
	header.avatar:SetConversation(convo, presence)
	header.avatar:SetRingColor(T.color.header)
	header.avatar:Show()
	header.title:SetText(M:GetTitle(convo))
	if M.Store.IsRoomKey(convo.key) then
		header.title:SetTextColor(T.KindColor(convo))
	else
		header.title:SetTextColor(T.NameColor(presence.class or convo.class))
	end
	local detail = M.Contacts:Describe(convo)
	if M:GetAlias(convo.key) then
		-- Under a nickname, keep the real name in view
		local real = M:GetRealTitle(convo)
		detail = detail ~= '' and (real .. '  -  ' .. detail) or real
	end
	header.subtitle:SetText(detail)
	header.pin:Show()
	header.pin:SetTint(convo.pinned and T.color.text or T.color.muted)
	header.pin.tooltip = convo.pinned and L['Unpin'] or L['Pin to top']
	header.popout:Show()
	header.more:Show()
	header.muted:ClearAllPoints()
	header.muted:SetPoint('LEFT', header.title, 'LEFT', math.min(header.title:GetStringWidth(), header.title:GetWidth()) + 6, 0)
	header.muted:SetShown(convo.muted == true)
end

---Turns the name at the top into a text box for a nickname. Enter or clicking away saves,
---Escape cancels, and an empty box goes back to the real name.
function Pane:EditNickname()
	local header = self.header
	local convo = self.key and M.Store:Get(self.key)
	if not self.showHeader or not convo then
		return
	end
	local edit = header.nickname
	if not edit then
		edit = CreateFrame('EditBox', nil, header)
		edit:SetPoint('LEFT', header.title, 'LEFT', -4, 0)
		edit:SetPoint('RIGHT', header.title, 'RIGHT')
		edit:SetAutoFocus(false)
		edit:SetMaxLetters(48)
		edit:SetTextInsets(4, 4, 0, 0)
		T.Fill(edit, T.color.input)
		edit.focusLine = T.Line(edit, 'BOTTOM', T.color.focus)
		edit.hint = T.Text(edit, 'meta', T.color.faint)
		edit.hint:SetPoint('TOPLEFT', edit, 'BOTTOMLEFT', 4, -2)
		edit.hint:SetText(L['Enter to save, Escape to cancel. Leave empty for the real name.'])
		local function Finish(save)
			if not edit:IsShown() then
				return
			end
			local key = edit.key
			edit:Hide()
			edit:ClearFocus()
			header.title:Show()
			header.subtitle:Show()
			if save and key then
				M:SetAlias(key, edit:GetText())
			end
		end
		edit:SetScript('OnEnterPressed', function()
			Finish(true)
		end)
		edit:SetScript('OnEscapePressed', function()
			Finish(false)
		end)
		edit:SetScript('OnEditFocusLost', function()
			Finish(true)
		end)
		edit.Finish = Finish
		header.nickname = edit
	end
	local face, size, flags = header.title:GetFont()
	edit:SetFont(face or STANDARD_TEXT_FONT, size or T.BaseSize(), flags or '')
	edit:SetHeight((size or T.BaseSize()) + 8)
	edit.key = self.key
	edit:SetText(M:GetAlias(self.key) or M:GetRealTitle(convo))
	header.title:Hide()
	header.subtitle:Hide()
	edit:Show()
	edit:SetFocus()
	edit:HighlightText()
end

---@param key string|nil
function Pane:SetConversation(key)
	if self.header.nickname and self.header.nickname:IsShown() then
		self.header.nickname.Finish(true)
	end
	self.key = key
	self:UpdateHeader()
	self:UpdateBanner()
	self.log:SetConversation(key)
	self.composer:SetConversation(key)
	self.composer:SetShown(key ~= nil)
end

---@param key string
---@return boolean
function Pane:IsViewing(key)
	return self:IsVisible() and self.log:IsViewing(key)
end

function Pane:FocusComposer()
	self.composer:Focus()
end
