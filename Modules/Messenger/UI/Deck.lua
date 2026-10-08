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
local SLIM_W = 210
local RAIL_W = 60
local COMPACT_BELOW = 640
local LIST_WIDTH = { full = LIST_W, slim = SLIM_W, icons = RAIL_W }
local MAX_PEOPLE = 6

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
	body:SetText(L['Whispers you send and get land here. You can also bring channels in:'])

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
	title:SetPoint('TOPLEFT', win.inner)
	title:SetPoint('TOPRIGHT', win.inner)
	T.Fill(title, T.color.header, 'BACKGROUND', 1)
	T.Line(title, 'BOTTOM')
	W.DragHandle(title, win)

	-- Folds the conversation list down to pictures and back; right-click picks a size
	title.list = W.IconButton(title, 'sidebar', 24, nil, function(btn, mouseButton)
		if mouseButton == 'RightButton' then
			local current = M.settings.listMode
			local function item(text, mode)
				return {
					text = text,
					checked = current == mode,
					onClick = function()
						D:SetListMode(mode)
					end,
				}
			end
			W.OpenMenu(btn, {
				item(L['Full list'], 'full'),
				item(L['Compact list'], 'slim'),
				item(L['Pictures only'], 'icons'),
				item(L['Automatic'], 'auto'),
			})
			local dropdown = _G.MessengerDropDown
			if dropdown then
				dropdown:ClearAllPoints()
				dropdown:SetPoint('TOPLEFT', btn, 'BOTTOMLEFT', 0, -2)
			end
		else
			D:ToggleList()
		end
	end)
	title.list:SetPoint('LEFT', 6, 0)

	title.icon = title:CreateTexture(nil, 'ARTWORK')
	title.icon:SetSize(18, 18)
	title.icon:SetPoint('LEFT', title.list, 'RIGHT', 4, 0)
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
		D:Select(key, false, false, self.list and self.list.query)
	end, {
		suggest = function(query, quiet)
			return D:Suggestions(query, quiet)
		end,
		pick = function(entry)
			D:PickSuggestion(entry)
		end,
		start = function(text)
			D:StartConversation(text)
		end,
		changed = function()
			D:Layout()
			D:Refresh()
		end,
	})
	self.list = list

	local pane = M.ChatPane.Create(win, true)
	pane:SetPoint('TOPLEFT', list, 'TOPRIGHT')
	pane:SetPoint('BOTTOMRIGHT', win.inner)
	pane.composer.onNavigate = function(step)
		return D:Step(step)
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

	-- First run on this account: pick how messages and the list look
	self.welcome = M.Welcome.Create(win)
	self.welcome:SetFrameLevel(win:GetFrameLevel() + 30)

	self:Layout()
	win:SetScript('OnSizeChanged', function()
		D:Layout()
	end)

	self:ApplyPin()
	win:SetScript('OnShow', function()
		M.db.char.deckOpen = true
		if M.Welcome.Pending() and not self.welcome:IsShown() then
			self.welcome:Start()
		end
		M.UI.Fade:Kick()
		M.Contacts:RequestGuild()
		D:Refresh()
	end)
	win:SetScript('OnHide', function()
		-- Hiding the whole interface also fires OnHide; only a real close forgets the window
		if not win:IsShown() and not self.hiddenForCombat and M.enabled then
			M.db.char.deckOpen = nil
		end
		W.CloseMenu()
		self.list:EndNew()
	end)

	M:On('LIST_CHANGED', function()
		if win:IsShown() then
			M:Defer('deck-refresh', function()
				D:Refresh()
			end)
		end
	end)
	M:On('SKIN_CHANGED', function()
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
		self:Layout()
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

---The list size in use: the player's choice, or for "automatic" full width unless the window is narrow.
---@return 'full'|'slim'|'icons'
function D:ListMode()
	local choice = M.settings.listMode
	if choice == 'full' or choice == 'slim' or choice == 'icons' then
		return choice
	end
	return self.win:GetWidth() < COMPACT_BELOW and 'icons' or 'full'
end

---@param mode 'auto'|'full'|'slim'|'icons'
function D:SetListMode(mode)
	M.settings.listMode = mode
	if self.win then
		self:Layout()
	end
end

local NEXT_LIST_MODE = { full = 'slim', slim = 'icons', icons = 'full' }

---The title bar button steps through the list sizes: full, one line, pictures.
function D:ToggleList()
	self:SetListMode(NEXT_LIST_MODE[self:ListMode()])
end

function D:UpdateListButton()
	local button = self.title and self.title.list
	if not button then
		return
	end
	local mode = self:ListMode()
	if mode == 'full' then
		button.tooltip = L['Make the list one line per conversation']
	elseif mode == 'slim' then
		button.tooltip = L['Shrink the list to pictures']
	else
		button.tooltip = L['Show the full conversation list']
	end
	button.hint = L['Right-click to pick a list size.']
end

---Places the body under the title bar, and sizes the list for the chosen mode.
function D:Layout()
	local win = self.win
	local titleH = T.Metrics().title
	self.title:SetHeight(titleH)
	local mode = self:ListMode()
	local list = self.list
	-- Starting a conversation needs the search box, which the picture column does not have
	if list.newMode and mode == 'icons' then
		mode = 'slim'
	end
	list:ClearAllPoints()
	list:SetPoint('TOPLEFT', win.inner, 'TOPLEFT', 0, -titleH)
	list:SetPoint('BOTTOMLEFT', win.inner, 'BOTTOMLEFT', 0, 0)
	list:SetWidth(LIST_WIDTH[mode])
	list:SetMode(mode)
	self:UpdateListButton()
	self.empty:ClearAllPoints()
	self.empty:SetPoint('TOPLEFT', win.inner, 'TOPLEFT', 0, -titleH)
	self.empty:SetPoint('BOTTOMRIGHT', win.inner)
	self.welcome:ClearAllPoints()
	self.welcome:SetPoint('TOPLEFT', win.inner, 'TOPLEFT', 0, -titleH)
	self.welcome:SetPoint('BOTTOMRIGHT', win.inner)
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
	local starting = self.list.newMode == true
	self.empty:SetShown(not hasAny and not starting)
	self.list:SetShown(hasAny or starting)
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
---@param query? string Search text: scroll to the newest message containing it
function D:Select(key, focus, force, query)
	if not self.win then
		return
	end
	M.db.char.lastKey = key
	self.list:SetSelected(key)
	if force or self.pane.key ~= key then
		self.pane:SetConversation(key)
	end
	local convo = M.Store:Get(key)
	if query and query ~= '' and convo and not strlower(M:GetTitle(convo)):find(strlower(query), 1, true) then
		self.pane.log:JumpTo(query)
	end
	self.pick:Hide()
	-- Typing would land in a message box hidden under the first-run picks
	if focus and not self.welcome:IsShown() then
		self.pane:FocusComposer()
	end
end

---Moves to the previous (-1) or next (1) conversation in list order.
---@param step number
---@return boolean switched
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
		return false
	end
	local index = current and (current + step) or 1
	index = math.max(1, math.min(#keys, index))
	if keys[index] ~= self.pane.key then
		self:Select(keys[index], true)
		return true
	end
	return false
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

---The list's search box doubles as the "new conversation" box.
function D:ShowNewConversation()
	self:Build()
	if not self.win:IsShown() then
		self.win:Show()
	end
	self.list:StartNew()
end

---@param name string Name, Name-Realm or BattleTag
---@return string|nil
local function PersonKey(name)
	if name:find('#', 1, true) then
		return M.Store.BNetKey(name)
	end
	local full = U.FullName(name)
	return full and M.Store.CharKey(full) or nil
end

---New conversations the search box offers for the typed text: a whisper to exactly what was
---typed, matching people, channels, then joining a channel the player is not in. With nothing
---typed it lists channels that are not open yet.
---@param typed string
---@param quiet? boolean Leave out the whisper and join rows (the search already found conversations)
---@return table[]
function D:Suggestions(typed, quiet)
	typed = U.Trim(typed or '')
	local prefix = strlower(typed)
	local rooms = M.Rooms:Choices(prefix)
	for _, entry in ipairs(rooms) do
		entry.key = M.Rooms.KeyFor(entry.kind, entry.channel)
	end
	if prefix == '' then
		local out = {}
		for _, entry in ipairs(rooms) do
			local convo = M.Store:Get(entry.key)
			if not (convo and not convo.closed and M.Rooms:IsShown(convo)) then
				out[#out + 1] = entry
			end
		end
		return out
	end
	local out = {}
	local people = M.Contacts:Suggest(prefix)
	local exactPerson = false
	for _, entry in ipairs(people) do
		entry.key = PersonKey(entry.name)
		if strlower(entry.name) == prefix then
			exactPerson = true
		end
	end
	local channelName = M.Rooms:Find(typed)
	if not quiet and not exactPerson and not channelName and U.LooksLikeName(typed) and not typed:find('^%d+$') then
		out[#out + 1] = { name = typed, detail = L['Whisper'], message = true, key = PersonKey(typed) }
	end
	for i = 1, math.min(#people, MAX_PEOPLE) do
		out[#out + 1] = people[i]
	end
	for _, entry in ipairs(rooms) do
		out[#out + 1] = entry
	end
	if not quiet and not typed:find('[%s#%-]') and #typed >= 2 and not typed:find('^%d+$') and not channelName then
		out[#out + 1] = { name = typed, detail = L['Join this channel'], join = true }
	end
	return out
end

---@param entry table
function D:PickSuggestion(entry)
	if not entry then
		return
	end
	self.list:Reset()
	if entry.room then
		M:OpenRoom(entry.kind, entry.channel, true)
	elseif entry.join then
		if not M.Rooms:Join(entry.name) then
			M.UI.Toast:ShowNotice(L['That channel could not be joined'], L['Check the name, or try again after the fight.'])
		end
	else
		self:StartConversation(entry.name)
	end
end

---@param text string
function D:StartConversation(text)
	text = U.Trim(text or '')
	if text == '' then
		return
	end
	local kindKey, channel = M.Rooms:Find(text)
	if kindKey then
		M:OpenRoom(kindKey, channel, true)
		return
	end
	if text:find('#', 1, true) then
		local entry = M.Contacts:GetBNetByTag(text)
		if entry then
			M:OpenBNet(entry, true)
			return
		end
	end
	-- Anything that cannot be a character name was a search
	if U.LooksLikeName(text) then
		M:OpenWhisper(text, true)
	end
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
