local _, ns = ...
local M = ns.Messenger
local T = M.Theme
local U = M.Util
local W = M.Widgets
local L = M.L

---@class Messenger.ConversationList
local CL = {}
M.ConversationList = CL

local SECTION_H = 22

local FILTERS = {
	{ key = 'all', label = L['All'] },
	{ key = 'unread', label = L['Unread'] },
	{ key = 'people', label = L['People'] },
	{ key = 'rooms', label = L['Channels'] },
}

---@param convo MessengerConversation
---@return string
local function Preview(convo)
	local msgs = convo.msgs
	local msg = msgs[#msgs]
	if not msg then
		return L['No messages yet']
	end
	local text = M.Emoji:Render(U.Plain(msg.x or ''))
	if msg.sys then
		return text
	elseif msg.o then
		return string.format(L['You: %s'], text)
	elseif msg.s then
		return U.ShortName(msg.s) .. ': ' .. text
	end
	return text
end

---@class MessengerList : Frame
local List = {}

---@param list MessengerList
local function CreateRow(list)
	local row = CreateFrame('Button', nil, list.rowArea)
	row:SetHeight(list.rowH)
	row:RegisterForClicks('LeftButtonUp', 'RightButtonUp', 'MiddleButtonUp')

	row.selectedBg = row:CreateTexture(nil, 'BACKGROUND')
	row.selectedBg:SetAllPoints()
	row.selectedBg:SetTexture(T.WHITE)
	row.hl = T.Fill(row, T.color.hover, 'BACKGROUND', 1)
	row.hl:Hide()

	row.avatar = W.Avatar(row, 30)
	row.avatar:SetPoint('LEFT', 12, 0)

	row.time = T.Text(row, 'meta', T.color.faint)
	row.time:SetPoint('TOPRIGHT', -12, -8)
	row.time:SetJustifyH('RIGHT')

	row.pin = row:CreateTexture(nil, 'ARTWORK')
	row.pin:SetSize(12, 12)
	row.pin:SetPoint('RIGHT', row.time, 'LEFT', -3, 0)
	T.SetIcon(row.pin, 'pin')
	row.pin:SetVertexColor(T.color.faint[1], T.color.faint[2], T.color.faint[3])

	row.name = T.Text(row, 'name')
	row.name:SetPoint('TOPLEFT', row.avatar, 'TOPRIGHT', 10, 0)
	row.name:SetPoint('RIGHT', row.pin, 'LEFT', -4, 0)

	row.badge = W.Badge(row)
	row.badge:SetPoint('BOTTOMRIGHT', -12, 8)

	row.preview = T.Text(row, 'meta', T.color.muted)
	row.preview:SetPoint('BOTTOMLEFT', row.avatar, 'BOTTOMRIGHT', 10, 0)
	row.preview:SetPoint('RIGHT', row.badge, 'LEFT', -6, 0)

	row.section = T.Text(row, 'small', T.color.faint)
	row.section:SetPoint('BOTTOMLEFT', 12, 5)

	row.dot = row:CreateTexture(nil, 'ARTWORK')
	row.dot:SetSize(8, 8)
	row.dot:SetPoint('LEFT', 12, 0)
	T.SetIcon(row.dot, 'dot')
	row.dot:Hide()

	row:SetScript('OnEnter', function(self)
		if self.suggestion then
			self.hl:Show()
		elseif self.convo then
			self.hl:Show()
			-- The smaller list sizes cut the latest message short (or hide it), so show it on hover
			if list.mode ~= 'full' then
				GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
				GameTooltip:SetText(M:GetTitle(self.convo), 1, 1, 1)
				GameTooltip:AddLine(Preview(self.convo), T.color.muted[1], T.color.muted[2], T.color.muted[3], true)
				GameTooltip:Show()
			end
		end
	end)
	row:SetScript('OnLeave', function(self)
		self.hl:Hide()
		GameTooltip:Hide()
	end)
	row:SetScript('OnClick', function(self, button)
		if self.suggestion then
			list:Pick(self.suggestion)
			return
		end
		local convo = self.convo
		if not convo then
			return
		end
		if button == 'RightButton' then
			W.OpenMenu(self, M.ChatPane.ConversationMenu(convo))
			local dropdown = _G.MessengerDropDown
			if dropdown then
				dropdown:ClearAllPoints()
				dropdown:SetPoint('TOPLEFT', self, 'BOTTOMLEFT', 40, 4)
			end
		elseif button == 'MiddleButton' or IsShiftKeyDown() then
			M:PopOut(convo.key)
		else
			list:Select(convo.key)
		end
	end)
	return row
end

---@param parent Frame
---@param onSelect fun(key: string)
---@param starter? table { suggest = fun(query: string, quiet: boolean): table[], pick = fun(entry), start = fun(text), changed = fun() } lets the search box also start conversations
---@return MessengerList
function CL.Create(parent, onSelect, starter)
	local list = CreateFrame('Frame', nil, parent)
	Mixin(list, List)
	list.onSelect = onSelect
	list.starter = starter
	list.suggestions = {}
	list.filter = 'all'
	list.query = ''
	list.offset = 0
	list.data = {}
	list.rows = {}
	list.rowH = T.Metrics().row

	list.bg = T.Fill(list, T.color.list)
	T.Line(list, 'RIGHT')

	-- Search
	local search = CreateFrame('EditBox', nil, list)
	search:SetPoint('TOPLEFT', 10, -10)
	search:SetPoint('TOPRIGHT', -10, -10)
	search:SetAutoFocus(false)
	search:SetTextInsets(26, 22, 0, 0)
	search:SetFontObject(ChatFontNormal)
	search.bg = T.Fill(search, T.color.input)
	search.icon = search:CreateTexture(nil, 'ARTWORK')
	search.icon:SetSize(16, 16)
	search.icon:SetPoint('LEFT', 6, 0)
	T.SetIcon(search.icon, 'search')
	search.icon:SetVertexColor(T.color.faint[1], T.color.faint[2], T.color.faint[3])
	search.placeholder = T.Text(search, 'meta', T.color.faint)
	search.placeholder:SetPoint('LEFT', 26, 0)
	search.placeholder:SetText(starter and L['Search, or start a conversation'] or L['Search people and messages'])
	search.clear = W.IconButton(search, 'close', 18, nil, function()
		search:SetText('')
		search:ClearFocus()
		list:EndNew()
	end)
	search.clear:SetPoint('RIGHT', -3, 0)
	search.clear:Hide()
	search.focusLine = T.Line(search, 'BOTTOM', T.color.focus)
	search.focusLine:Hide()

	local timer
	search:SetScript('OnTextChanged', function(self)
		local text = self:GetText() or ''
		self.placeholder:SetShown(text == '')
		self.clear:SetShown(text ~= '' or list.newMode == true)
		if timer then
			timer:Cancel()
		end
		timer = C_Timer.NewTimer(0.2, function()
			list.query = U.Trim(text)
			list.offset = 0
			list:Refresh()
		end)
	end)
	search:SetScript('OnEscapePressed', function(self)
		self:SetText('')
		self:ClearFocus()
		list:EndNew()
	end)
	search:SetScript('OnEnterPressed', function(self)
		if timer then
			timer:Cancel()
		end
		local text = U.Trim(self:GetText() or '')
		list.query = text
		list:Refresh()
		self:ClearFocus()
		local first = list.firstConvo
		if first then
			list:Select(first.key)
		elseif text ~= '' and list.starter then
			-- Nothing to open: start one with exactly what was typed
			list:Reset()
			list.starter.start(text)
		end
	end)
	search:SetScript('OnTabPressed', function(self)
		for _, entry in ipairs(list.suggestions) do
			if not entry.message and not entry.join then
				self:SetText(entry.name)
				self:SetCursorPosition(#entry.name)
				return
			end
		end
	end)
	search:SetScript('OnEditFocusGained', function(self)
		self.focusLine:Show()
	end)
	search:SetScript('OnEditFocusLost', function(self)
		self.focusLine:Hide()
	end)
	search:SetScript('OnShow', function(self)
		self:SetFont(ChatFontNormal:GetFont(), T.BaseSize() - 1, '')
	end)
	list.search = search

	-- Filter chips
	list.chips = {}
	local prev
	for _, f in ipairs(FILTERS) do
		local chip = W.Chip(list, f.label, function()
			list:SetFilter(f.key)
		end)
		if prev then
			chip:SetPoint('LEFT', prev, 'RIGHT', 4, 0)
		else
			chip:SetPoint('TOPLEFT', search, 'BOTTOMLEFT', 0, -8)
		end
		chip.filterKey = f.key
		list.chips[#list.chips + 1] = chip
		prev = chip
	end
	list.chips[1]:SetSelected(true)

	-- Rows
	local area = CreateFrame('Frame', nil, list)
	area:SetClipsChildren(true)
	area:EnableMouseWheel(true)
	area:SetScript('OnMouseWheel', function(_, delta)
		list:Scroll(-delta)
	end)
	area:SetScript('OnSizeChanged', function()
		list:Render()
	end)
	T.Line(area, 'TOP')
	list.rowArea = area

	list.empty = T.Text(area, 'meta', T.color.faint)
	list.empty:SetPoint('TOP', 0, -24)
	list.empty:SetWidth(180)
	list.empty:SetWordWrap(true)
	list.empty:SetJustifyH('CENTER')

	M:On('LIST_CHANGED', function()
		M:Defer('list-refresh', function()
			list:Refresh()
		end)
	end)
	M:On('CONTACTS_CHANGED', function()
		list:Render()
	end)
	M:On('FONTS_CHANGED', function()
		for _, chip in ipairs(list.chips) do
			chip:Resize()
		end
		list:ApplyMetrics()
		list:Refresh()
	end)
	list:ApplyMetrics()
	return list
end

---Sizes the search box, rows and row area for the current text size and layout.
function List:ApplyMetrics()
	local metrics = T.Metrics()
	local mode = self.mode or 'full'
	self.rowH = (mode == 'slim' and metrics.slimRow) or (mode == 'icons' and metrics.iconRow) or metrics.row
	self.search:SetHeight(metrics.search)
	local area = self.rowArea
	area:ClearAllPoints()
	if mode == 'icons' then
		area:SetPoint('TOPLEFT', 0, -6)
	elseif mode == 'slim' then
		area:SetPoint('TOPLEFT', 0, -(10 + metrics.search + 10))
	else
		area:SetPoint('TOPLEFT', 0, -(10 + metrics.search + 8 + 18 + 10))
	end
	area:SetPoint('BOTTOMRIGHT', -1, 0)
end

---List sizes: 'full' (two lines per conversation), 'slim' (one line, no filter buttons) and
---'icons' (a rail of avatars with no search or filters).
---@param mode 'full'|'slim'|'icons'
function List:SetMode(mode)
	if self.mode == mode then
		return
	end
	self.mode = mode
	self.compact = mode == 'icons'
	-- Hidden filters must not keep hiding conversations
	if mode == 'icons' or (mode == 'slim' and self.filter ~= 'all') then
		self.filter = 'all'
		self.query = ''
		self.newMode = false
		self.search:SetText('')
		for _, chip in ipairs(self.chips) do
			chip:SetSelected(chip.filterKey == 'all')
		end
	end
	self.search:SetShown(mode ~= 'icons')
	for _, chip in ipairs(self.chips) do
		chip:SetShown(mode == 'full')
	end
	self:ApplyMetrics()
	self:Refresh()
end

---Puts the cursor in the search box to start a conversation: until the player types, the list
---offers the channels they can open instead of their conversations.
function List:StartNew()
	if not self.starter then
		return
	end
	self.newMode = true
	self.query = ''
	self.offset = 0
	self.search:SetText('')
	self.search.placeholder:SetText(L['Name, BattleTag or channel'])
	self.starter.changed()
	self.search:SetFocus()
	self.search.clear:Show()
	self:Refresh()
end

function List:EndNew()
	if not self.newMode then
		return
	end
	self.newMode = false
	self.search.placeholder:SetText(L['Search, or start a conversation'])
	self.search.clear:SetShown((self.search:GetText() or '') ~= '')
	self:Refresh()
	self.starter.changed()
end

---Empties the box and leaves "new conversation" mode.
function List:Reset()
	self.query = ''
	self.search:SetText('')
	self.search:ClearFocus()
	self:EndNew()
	self:Refresh()
end

---@param entry table A suggestion row's entry
function List:Pick(entry)
	self:Reset()
	self.starter.pick(entry)
end

---@param filter string
function List:SetFilter(filter)
	self.filter = filter
	self.offset = 0
	for _, chip in ipairs(self.chips) do
		chip:SetSelected(chip.filterKey == filter)
	end
	self:Refresh()
end

---@param key string
function List:Select(key)
	self.selected = key
	self:Render()
	if self.onSelect then
		self.onSelect(key)
	end
end

---@param key string|nil
function List:SetSelected(key)
	self.selected = key
	self:Render()
end

---@param delta number rows
function List:Scroll(delta)
	local visible = math.floor(self.rowArea:GetHeight() / self.rowH)
	local maxOffset = math.max(0, #self.data - visible)
	self.offset = math.max(0, math.min(self.offset + delta, maxOffset))
	self:Render()
end

function List:Refresh()
	local blank = self.query == ''
	local convos = (self.newMode and blank) and {} or M.Store:List(self.filter, self.query)
	local data = {}
	local pinnedCount = 0
	for _, convo in ipairs(convos) do
		if convo.pinned then
			pinnedCount = pinnedCount + 1
		end
	end
	local splitSections = self.mode ~= 'icons' and pinnedCount > 0 and pinnedCount < #convos
	self.firstConvo = convos[1]
	for i, convo in ipairs(convos) do
		if splitSections and i == 1 then
			data[#data + 1] = { section = L['Pinned'] }
		elseif splitSections and i == pinnedCount + 1 then
			data[#data + 1] = { section = L['Recent'] }
		end
		data[#data + 1] = { convo = convo }
	end
	self.suggestions = {}
	if self.starter and self.mode ~= 'icons' and (self.newMode or not blank) then
		local shown = {}
		for _, convo in ipairs(convos) do
			shown[convo.key] = true
		end
		for _, entry in ipairs(self.starter.suggest(self.query, #convos > 0 and not self.newMode)) do
			if not (entry.key and shown[entry.key]) then
				self.suggestions[#self.suggestions + 1] = entry
			end
		end
		if #self.suggestions > 0 then
			if #convos > 0 then
				data[#data + 1] = { section = L['Start a conversation'] }
			end
			for _, entry in ipairs(self.suggestions) do
				data[#data + 1] = { suggestion = entry }
			end
		end
	end
	self.data = data
	local visible = math.floor(self.rowArea:GetHeight() / self.rowH)
	self.offset = math.max(0, math.min(self.offset, #data - visible))
	self:Render()
end

---@param row Button
---@param convo MessengerConversation
function List:PaintRow(row, convo)
	local presence = M.Contacts:GetPresence(convo)
	local r, g, b = T.KindColor(convo)
	local selected = convo.key == self.selected
	local unread = (convo.unread or 0) > 0

	row.selectedBg:SetVertexColor(r, g, b, 0.14)
	row.selectedBg:SetShown(selected)
	row.avatar:SetConversation(convo, presence)
	row.avatar:SetRingColor(T.color.list)
	row.avatar:Show()
	row.section:Hide()
	row.dot:Hide()

	row.avatar:ClearAllPoints()
	row.badge:ClearAllPoints()
	row.name:ClearAllPoints()
	if self.mode == 'icons' then
		row.avatar:SetPoint('CENTER')
		row.badge:SetPoint('CENTER', row.avatar, 'TOPRIGHT', -2, -2)
		row.name:Hide()
		row.time:Hide()
		row.pin:Hide()
		row.preview:Hide()
		if convo.muted then
			row.badge:SetCount(convo.unread, T.color.faint[1], T.color.faint[2], T.color.faint[3])
		else
			row.badge:SetCount(convo.unread, r, g, b)
		end
		return
	end
	local slim = self.mode == 'slim'
	row.name:SetWidth(0)
	row.time:ClearAllPoints()
	row.preview:ClearAllPoints()
	if slim then
		-- One dense line: unread count, name, latest message, time. No picture.
		row.avatar:Hide()
		row.badge:SetPoint('LEFT', 8, 0)
		if (convo.unread or 0) > 0 then
			row.name:SetPoint('LEFT', row.badge, 'RIGHT', 6, 0)
		else
			row.name:SetPoint('LEFT', 10, 0)
		end
		row.time:SetPoint('RIGHT', -8, 0)
		row.preview:SetPoint('LEFT', row.name, 'RIGHT', 8, 0)
		row.preview:SetPoint('RIGHT', row.time, 'LEFT', -8, 0)
	else
		row.avatar:SetPoint('LEFT', 12, 0)
		row.badge:SetPoint('BOTTOMRIGHT', -12, 8)
		row.name:SetPoint('TOPLEFT', row.avatar, 'TOPRIGHT', 10, 0)
		row.name:SetPoint('RIGHT', row.pin, 'LEFT', -4, 0)
		row.time:SetPoint('TOPRIGHT', -12, -8)
		row.preview:SetPoint('BOTTOMLEFT', row.avatar, 'BOTTOMRIGHT', 10, 0)
		row.preview:SetPoint('RIGHT', row.badge, 'LEFT', -6, 0)
	end

	row.name:SetText(M:GetTitle(convo))
	if convo.muted then
		T.SetColor(row.name, T.color.faint)
	elseif M.Store.IsRoomKey(convo.key) then
		row.name:SetTextColor(r, g, b)
	else
		row.name:SetTextColor(T.NameColor(presence.class or convo.class))
	end
	row.name:Show()

	row.time:SetText(convo.last and U.ListTime(convo.last) or '')
	row.time:Show()
	row.pin:SetShown(not slim and convo.pinned == true)
	row.preview:SetText(Preview(convo))
	T.SetColor(row.preview, unread and T.color.text or T.color.muted)
	row.preview:Show()
	if slim then
		-- Keep room for the latest message: the name takes at most 45% of the row
		local limit = (row:GetWidth() or 0) * 0.45
		if limit > 0 and row.name:GetStringWidth() > limit then
			row.name:SetWidth(limit)
		end
	end

	if convo.muted then
		row.badge:SetCount(convo.unread, T.color.faint[1], T.color.faint[2], T.color.faint[3])
	else
		row.badge:SetCount(convo.unread, r, g, b)
	end
	row.section:Hide()
end

---One line: a dot (presence or chat color), the name, and a detail on the right.
---@param row Button
---@param entry table
function List:PaintSuggestion(row, entry)
	row.selectedBg:Hide()
	row.avatar:Hide()
	row.badge:Hide()
	row.pin:Hide()
	row.preview:Hide()
	row.section:Hide()
	local dotColor
	if entry.room or entry.join then
		dotColor = { T.KindColor({ kind = entry.kind or 'CHANNEL', target = entry.channel }) }
	elseif entry.message then
		dotColor = { T.KindColor({ kind = 'WHISPER' }) }
	else
		dotColor = T.StatusColor(entry.status) or T.color.offline
	end
	row.dot:SetVertexColor(dotColor[1], dotColor[2], dotColor[3])
	row.dot:Show()
	row.time:ClearAllPoints()
	row.time:SetPoint('RIGHT', -10, 0)
	row.time:SetText(entry.detail or '')
	row.time:Show()
	row.name:ClearAllPoints()
	row.name:SetWidth(0)
	row.name:SetPoint('LEFT', row.dot, 'RIGHT', 8, 0)
	row.name:SetPoint('RIGHT', row.time, 'LEFT', -8, 0)
	if entry.message then
		row.name:SetText(string.format(L['Message %s'], entry.name))
	else
		row.name:SetText(entry.name)
	end
	T.SetColor(row.name, T.color.text)
	row.name:Show()
end

function List:Render()
	local area = self.rowArea
	local height = area:GetHeight()
	if height <= 0 then
		return
	end
	local width = area:GetWidth()
	local y = 0
	local used = 0
	local index = self.offset + 1
	while index <= #self.data and y < height do
		local entry = self.data[index]
		used = used + 1
		local row = self.rows[used]
		if not row then
			row = CreateRow(self)
			self.rows[used] = row
		end
		row:ClearAllPoints()
		row:SetPoint('TOPLEFT', 0, -y)
		row:SetWidth(width)
		row:Show()
		row.suggestion = entry.suggestion
		if entry.suggestion then
			row.convo = nil
			local h = T.Metrics().slimRow
			row:SetHeight(h)
			self:PaintSuggestion(row, entry.suggestion)
			y = y + h
		elseif entry.section then
			row.convo = nil
			row.dot:Hide()
			row:SetHeight(SECTION_H)
			row.selectedBg:Hide()
			row.avatar:Hide()
			row.name:Hide()
			row.time:Hide()
			row.pin:Hide()
			row.preview:Hide()
			row.badge:Hide()
			row.section:SetText(entry.section)
			row.section:Show()
			y = y + SECTION_H
		else
			row.convo = entry.convo
			row:SetHeight(self.rowH)
			self:PaintRow(row, entry.convo)
			y = y + self.rowH
		end
		index = index + 1
	end
	for i = used + 1, #self.rows do
		self.rows[i]:Hide()
		self.rows[i].convo = nil
		self.rows[i].suggestion = nil
	end

	self.empty:SetShown(#self.data == 0 and self.mode ~= 'icons')
	if #self.data == 0 and self.mode ~= 'icons' then
		if self.newMode and self.query == '' then
			self.empty:SetText(L['Type a name, BattleTag or channel.'])
		elseif self.query ~= '' then
			self.empty:SetText(string.format(L['Nothing matches "%s".'], self.query))
		elseif self.filter == 'unread' then
			self.empty:SetText(L['You are all caught up.'])
		elseif self.filter == 'rooms' then
			self.empty:SetText(L['No channels open yet. Pick one from New conversation, or turn them on in the settings.'])
		else
			self.empty:SetText(L['No conversations yet.'])
		end
	end
end
