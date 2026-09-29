local _, ns = ...
local M = ns.Messenger
local T = M.Theme
local U = M.Util
local W = M.Widgets
local L = M.L

-- The main window: conversation list on the left, the open conversation on the right.

---@class Messenger.Deck
local D = {}

local LIST_W = 236
local RAIL_W = 60
local COMPACT_BELOW = 640
local MAX_SUGGESTIONS = 6

----------------------------------------------------------------------------------------------------
-- Empty state: shown when there are no conversations at all
----------------------------------------------------------------------------------------------------

local QUICK_ROOMS = {
	{ key = 'GUILD', label = L['Guild chat'] },
	{ key = 'PARTY', label = L['Party chat'] },
	{ key = 'RAID', label = L['Raid chat'] },
}

local function BuildEmpty(parent)
	local empty = CreateFrame('Frame', nil, parent)
	empty:SetAllPoints()

	local icon = empty:CreateTexture(nil, 'ARTWORK')
	icon:SetSize(40, 40)
	icon:SetPoint('BOTTOM', empty, 'CENTER', 0, 52)
	T.SetIcon(icon, 'bubble')
	icon:SetVertexColor(T.color.faint[1], T.color.faint[2], T.color.faint[3])

	local heading = T.Text(empty, 'title')
	T.Bump(heading, 3)
	heading:SetPoint('TOP', icon, 'BOTTOM', 0, -10)
	heading:SetText(L['Your conversations will show up here'])

	local body = T.Text(empty, 'body', T.color.muted)
	body:SetPoint('TOP', heading, 'BOTTOM', 0, -8)
	body:SetWidth(340)
	body:SetWordWrap(true)
	body:SetJustifyH('CENTER')
	body:SetText(L['Whispers you send and get land here. You can also bring group chats in:'])

	empty.rooms = {}
	local row = CreateFrame('Frame', nil, empty)
	row:SetSize(1, 24)
	row:SetPoint('TOP', body, 'BOTTOM', 0, -14)
	local prev
	local total = 0
	for _, room in ipairs(QUICK_ROOMS) do
		local btn = W.TextButton(row, room.label, function(self)
			local route = M:GetRoute(room.key)
			route.capture = not route.capture
			M:RoutesChanged()
			empty:Update()
		end)
		if prev then
			btn:SetPoint('LEFT', prev, 'RIGHT', 8, 0)
		else
			btn:SetPoint('LEFT', row, 'LEFT', 0, 0)
		end
		btn.roomKey = room.key
		btn.roomLabel = room.label
		empty.rooms[#empty.rooms + 1] = btn
		total = total + btn:GetWidth() + (prev and 8 or 0)
		prev = btn
	end
	row:SetWidth(total)

	local start = W.TextButton(empty, L['Start a conversation'], function()
		D:ShowNewConversation()
	end, T.color.text)
	start:SetPoint('TOP', row, 'BOTTOM', 0, -18)

	function empty:Update()
		for _, btn in ipairs(self.rooms) do
			local on = M:IsCaptured(btn.roomKey)
			local convo = { kind = btn.roomKey }
			local r, g, b = T.KindColor(convo)
			btn:SetLabel(on and string.format(L['%s: on'], btn.roomLabel) or btn.roomLabel)
			if on then
				btn.label:SetTextColor(r, g, b)
			else
				T.SetColor(btn.label, T.color.text)
			end
		end
	end
	return empty
end

----------------------------------------------------------------------------------------------------
-- New conversation picker
----------------------------------------------------------------------------------------------------

local function BuildPicker(win)
	local picker = CreateFrame('Frame', nil, win)
	picker:SetWidth(LIST_W)
	picker:SetHeight(46)
	picker:SetFrameLevel(win:GetFrameLevel() + 30)
	T.Fill(picker, T.color.popup)
	T.Line(picker, 'BOTTOM')
	picker:EnableMouse(true)
	picker:Hide()

	local label = T.Text(picker, 'meta', T.color.muted)
	label:SetPoint('TOPLEFT', 12, -6)
	label:SetText(L['To: name, Name-Realm or BattleTag'])

	local edit = CreateFrame('EditBox', nil, picker)
	edit:SetPoint('BOTTOMLEFT', 10, 6)
	edit:SetPoint('BOTTOMRIGHT', -10, 6)
	edit:SetHeight(20)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal)
	edit:SetTextInsets(4, 4, 0, 0)
	T.Fill(edit, T.color.input)
	picker.edit = edit

	picker.suggestions = {}
	local function Suggestion(i)
		local btn = picker.suggestions[i]
		if btn then
			return btn
		end
		btn = CreateFrame('Button', nil, picker)
		btn:SetHeight(22)
		btn:SetPoint('TOPLEFT', picker, 'BOTTOMLEFT', 0, -(i - 1) * 22)
		btn:SetPoint('TOPRIGHT', picker, 'BOTTOMRIGHT', 0, -(i - 1) * 22)
		btn:SetFrameLevel(picker:GetFrameLevel() + 1)
		T.Fill(btn, T.color.popup)
		btn.hl = T.Fill(btn, T.color.hover, 'ARTWORK')
		btn.hl:Hide()
		btn.text = T.Text(btn, 'body')
		btn.text:SetPoint('LEFT', 12, 0)
		btn:SetScript('OnEnter', function(self)
			self.hl:Show()
		end)
		btn:SetScript('OnLeave', function(self)
			self.hl:Hide()
		end)
		btn:SetScript('OnClick', function(self)
			D:StartConversation(self.value)
		end)
		picker.suggestions[i] = btn
		return btn
	end

	local function UpdateSuggestions()
		local text = strlower(U.Trim(edit:GetText() or ''))
		local names = text ~= '' and M.Contacts:Suggest(text) or {}
		for i = 1, MAX_SUGGESTIONS do
			local name = names[i]
			if name then
				local btn = Suggestion(i)
				btn.value = name
				btn.text:SetText(name)
				btn:Show()
			elseif picker.suggestions[i] then
				picker.suggestions[i]:Hide()
			end
		end
	end

	edit:SetScript('OnTextChanged', UpdateSuggestions)
	edit:SetScript('OnEnterPressed', function(self)
		D:StartConversation(self:GetText())
	end)
	edit:SetScript('OnEscapePressed', function()
		picker:Hide()
	end)
	edit:SetScript('OnTabPressed', function()
		local first = picker.suggestions[1]
		if first and first:IsShown() then
			edit:SetText(first.value)
			edit:SetCursorPosition(#first.value)
		end
	end)
	picker:SetScript('OnHide', function()
		edit:SetText('')
		edit:ClearFocus()
		for _, btn in ipairs(picker.suggestions) do
			btn:Hide()
		end
		D:Refresh()
	end)
	return picker
end

----------------------------------------------------------------------------------------------------
-- Window
----------------------------------------------------------------------------------------------------

function D:Build()
	if self.win then
		return
	end
	local settings = M.settings.window
	local win = W.Window('MessengerDeck', 520, 320)
	win:SetSize(settings.width, settings.height)
	W.RestorePoint(win, settings)
	win:Hide()
	self.win = win

	function win:OnGeometryChanged()
		-- Read the profile now: it may have changed since the window was built
		local current = M.settings.window
		W.SavePoint(self, current)
		current.width, current.height = math.floor(self:GetWidth() + 0.5), math.floor(self:GetHeight() + 0.5)
	end

	-- Title strip
	local title = CreateFrame('Frame', nil, win)
	title:SetPoint('TOPLEFT')
	title:SetPoint('TOPRIGHT')
	T.Fill(title, T.color.header, 'BACKGROUND', 1)
	T.Line(title, 'BOTTOM')
	W.DragHandle(title, win)

	title.icon = title:CreateTexture(nil, 'ARTWORK')
	title.icon:SetSize(18, 18)
	title.icon:SetPoint('LEFT', 12, 0)
	T.SetIcon(title.icon, 'bubble')
	title.icon:SetVertexColor(T.color.muted[1], T.color.muted[2], T.color.muted[3])

	title.text = T.Text(title, 'title')
	title.text:SetPoint('LEFT', title.icon, 'RIGHT', 8, 0)
	title.text:SetText(L['Messenger'])

	title.badge = W.Badge(title)
	title.badge:SetPoint('LEFT', title.text, 'RIGHT', 8, 0)

	title.close = W.IconButton(title, 'close', 24, L['Close'], function()
		win:Hide()
	end)
	title.close:SetPoint('RIGHT', -6, 0)
	title.gear = W.IconButton(title, 'gear', 24, L['Settings'], function()
		M:OpenOptions()
	end)
	title.gear:SetPoint('RIGHT', title.close, 'LEFT', -2, 0)
	title.new = W.IconButton(title, 'plus', 24, L['New conversation'], function()
		D:ShowNewConversation()
	end)
	title.new:SetPoint('RIGHT', title.gear, 'LEFT', -2, 0)
	title.pin = W.IconButton(title, 'pin', 24, L['Pin Messenger'], function()
		D:SetPinned(not M.settings.window.pinned)
	end)
	title.pin:SetPoint('RIGHT', title.new, 'LEFT', -2, 0)

	-- Keycap showing the open/close key, so the shortcut is always in view
	local keycap = CreateFrame('Button', nil, title)
	keycap:SetHeight(18)
	keycap:SetPoint('RIGHT', title.pin, 'LEFT', -8, 0)
	keycap.bg = T.Fill(keycap, T.color.raised)
	T.Border(keycap, T.color.edgeStrong)
	keycap.text = T.Text(keycap, 'small', T.color.muted)
	keycap.text:SetPoint('CENTER', 0, 0)
	keycap:SetScript('OnEnter', function(self)
		T.SetColor(self.text, T.color.text)
		W.ShowTip(self, string.format(L['Press %s to open or close Messenger'], self.key or ''), L['Click to change it in the settings.'])
	end)
	keycap:SetScript('OnLeave', function(self)
		T.SetColor(self.text, T.color.muted)
		GameTooltip:Hide()
	end)
	keycap:SetScript('OnClick', function()
		M:OpenOptions()
	end)
	title.keycap = keycap
	self.title = title
	self:UpdateKeyHint()

	-- Body
	local list = M.ConversationList.Create(win, function(key)
		D:Select(key)
	end)
	self.list = list

	local pane = M.ChatPane.Create(win, true)
	pane:SetPoint('TOPLEFT', list, 'TOPRIGHT')
	pane:SetPoint('BOTTOMRIGHT')
	pane.composer.onNavigate = function(step)
		D:Step(step)
	end
	pane.composer.onTab = function()
		local nextConvo = M.Store:NextUnread()
		if nextConvo then
			D:Select(nextConvo.key, true)
		end
	end
	self.pane = pane

	self.pick = T.Text(pane, 'body', T.color.faint)
	self.pick:SetPoint('CENTER')
	self.pick:SetText(L['Pick a conversation on the left.'])
	self.pick:Hide()

	self.empty = BuildEmpty(win)
	self.empty:Hide()

	self.picker = BuildPicker(win)
	self:Layout()
	win:SetScript('OnSizeChanged', function()
		D:Layout()
	end)

	self:ApplyPin()
	win:SetScript('OnShow', function()
		M.db.char.deckOpen = true
		M.UI.Fade:Kick()
		M.Contacts:RequestGuild()
		D:Refresh()
	end)
	win:SetScript('OnHide', function()
		-- Hiding the whole interface also fires OnHide; only a real close forgets the window
		if not win:IsShown() then
			M.db.char.deckOpen = nil
		end
		W.CloseMenu()
		self.picker:Hide()
	end)

	M:On('LIST_CHANGED', function()
		if win:IsShown() then
			M:Defer('deck-refresh', function()
				D:Refresh()
			end)
		end
	end)
	M:On('UNREAD_CHANGED', function()
		M:Defer('deck-badge', function()
			local total = M.Store:TotalUnread()
			local c = T.color.text
			title.badge:SetCount(total, c[1], c[2], c[3])
		end)
	end)
	M:On('SETTINGS_CHANGED', function()
		win:ApplyAlpha()
		self.empty:Update()
		self:ApplyPin()
	end)
	M:On('KEYS_CHANGED', function()
		self:UpdateKeyHint()
	end)
	M:On('FONTS_CHANGED', function()
		self:UpdateKeyHint()
		self:Layout()
	end)
	M:On('COMBAT', function(inCombat)
		if not M.settings.alerts.hideInCombat then
			return
		end
		if inCombat and win:IsShown() then
			self.hiddenForCombat = true
			win:Hide()
		elseif not inCombat and self.hiddenForCombat then
			self.hiddenForCombat = false
			win:Show()
		end
	end)
end

---Pinned: the window stays where it is, Escape leaves it open, and it comes back after a reload.
---@param pinned boolean
function D:SetPinned(pinned)
	M.settings.window.pinned = pinned
	self:ApplyPin()
end

function D:ApplyPin()
	local pinned = M.settings.window.pinned == true
	local win = self.win
	win.locked = pinned
	win.grip:SetShown(not pinned)
	W.SetEscapeCloses('MessengerDeck', not pinned)
	local pin = self.title.pin
	pin:SetTint(pinned and T.color.text or T.color.muted)
	pin.tooltip = pinned and L['Unpin Messenger'] or L['Pin Messenger']
	pin.hint = pinned and L['It can move, resize and close with Escape again.'] or L['Keeps it in place, open through Escape, and back after a reload.']
end

---Reopens a pinned window that was open before the reload.
function D:Restore()
	if M.settings.window.pinned and M.db.char.deckOpen then
		self:Open(nil, false)
	end
end

---Places the body under the title bar, and turns the list into an avatar rail when narrow.
function D:Layout()
	local win = self.win
	local titleH = T.Metrics().title
	self.title:SetHeight(titleH)
	local compact = win:GetWidth() < COMPACT_BELOW
	local list = self.list
	list:ClearAllPoints()
	list:SetPoint('TOPLEFT', 0, -titleH)
	list:SetPoint('BOTTOMLEFT', 0, 0)
	list:SetWidth(compact and RAIL_W or LIST_W)
	list:SetCompact(compact)
	self.empty:ClearAllPoints()
	self.empty:SetPoint('TOPLEFT', 0, -titleH)
	self.empty:SetPoint('BOTTOMRIGHT')
	self.picker:ClearAllPoints()
	self.picker:SetPoint('TOPLEFT', 0, -titleH)
end

---Shows the open/close key in the title bar and the close button's tooltip.
function D:UpdateKeyHint()
	local title = self.title
	if not title then
		return
	end
	local key = M:GetToggleKeyText()
	local keycap = title.keycap
	keycap.key = key
	if key then
		keycap.text:SetText(key)
		keycap:SetWidth(keycap.text:GetStringWidth() + 12)
		keycap:Show()
		title.close.hint = string.format(L['Or press %s'], key)
	else
		keycap:Hide()
		title.close.hint = nil
	end
end

---Swaps between the empty state and the list + conversation layout.
function D:Refresh()
	local hasAny = #M.Store:List('all') > 0
	self.empty:SetShown(not hasAny and not self.picker:IsShown())
	self.list:SetShown(hasAny or self.picker:IsShown())
	self.pane:SetShown(hasAny)
	if not hasAny then
		self.empty:Update()
		return
	end
	local current = self.pane.key and M.Store:Get(self.pane.key)
	if current and not M.Store:IsVisible(current) then
		self.pane:SetConversation(nil)
	end
	self.pick:SetShown(self.pane.key == nil)
	self.list:SetSelected(self.pane.key)
end

---@param key string
---@param focus? boolean
---@param force? boolean Reload the conversation even if it is already shown
function D:Select(key, focus, force)
	if not self.win then
		return
	end
	M.db.char.lastKey = key
	self.list:SetSelected(key)
	if force or self.pane.key ~= key then
		self.pane:SetConversation(key)
	end
	self.pick:Hide()
	if focus then
		self.pane:FocusComposer()
	end
end

---Moves to the previous (-1) or next (1) conversation in list order.
---@param step number
function D:Step(step)
	local keys = {}
	local current
	for _, entry in ipairs(self.list.data) do
		if entry.convo then
			keys[#keys + 1] = entry.convo.key
			if entry.convo.key == self.pane.key then
				current = #keys
			end
		end
	end
	if #keys == 0 then
		return
	end
	local index = current and (current + step) or 1
	index = math.max(1, math.min(#keys, index))
	if keys[index] ~= self.pane.key then
		self:Select(keys[index], true)
	end
end

function D:Toggle()
	self:Build()
	if self.win:IsShown() then
		self.win:Hide()
	else
		self:Open(nil, false)
	end
end

---@param key? string
---@param focus? boolean
function D:Open(key, focus)
	self:Build()
	local wasShown = self.win:IsShown()
	self.win:Show()
	self.win:Raise()
	self:Refresh()
	if not key and not self.pane.key then
		local last = M.db.char.lastKey
		local convo = last and M.Store:Get(last)
		if convo and not convo.closed then
			key = last
		else
			local first = M.Store:List('all')[1]
			key = first and first.key
		end
	end
	if not key and not wasShown then
		key = self.pane.key
	end
	if key then
		self:Refresh()
		self:Select(key, focus, not wasShown)
	end
end

function D:ShowNewConversation()
	self:Build()
	if not self.win:IsShown() then
		self.win:Show()
	end
	self.picker:Show()
	self.empty:Hide()
	self.list:Show()
	self.picker.edit:SetFocus()
end

---@param text string
function D:StartConversation(text)
	text = U.Trim(text or '')
	if text == '' then
		return
	end
	self.picker:Hide()
	if text:find('#', 1, true) then
		local entry = M.Contacts:GetBNetByTag(text)
		if entry then
			M:OpenBNet(entry, true)
			return
		end
	end
	M:OpenWhisper(text, true)
end

function D:Hide()
	if self.win then
		self.win:Hide()
	end
end

---@return boolean
function D:IsShown()
	return self.win ~= nil and self.win:IsShown()
end

M.UI.Deck = D
