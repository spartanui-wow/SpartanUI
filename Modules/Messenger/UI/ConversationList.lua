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
local COMPACT_AVATAR = 32

local FILTERS = {
	{ key = 'all', label = L['All'] },
	{ key = 'unread', label = L['Unread'] },
	{ key = 'people', label = L['People'] },
	{ key = 'rooms', label = L['Rooms'] },
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

	row:SetScript('OnEnter', function(self)
		if self.convo then
			self.hl:Show()
			-- The compact rail shows only avatars, so the name and latest line move to a tooltip
			if list.compact then
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
---@return MessengerList
function CL.Create(parent, onSelect)
	local list = CreateFrame('Frame', nil, parent)
	Mixin(list, List)
	list.onSelect = onSelect
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
	search.placeholder:SetText(L['Search people and messages'])
	search.clear = W.IconButton(search, 'close', 18, nil, function()
		search:SetText('')
		search:ClearFocus()
	end)
	search.clear:SetPoint('RIGHT', -3, 0)
	search.clear:Hide()
	search.focusLine = T.Line(search, 'BOTTOM', T.color.focus)
	search.focusLine:Hide()

	local timer
	search:SetScript('OnTextChanged', function(self)
		local text = self:GetText() or ''
		self.placeholder:SetShown(text == '')
		self.clear:SetShown(text ~= '')
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
	end)
	search:SetScript('OnEnterPressed', function(self)
		self:ClearFocus()
		local first = list.firstConvo
		if first then
			list:Select(first.key)
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
	self.rowH = metrics.row
	self.search:SetHeight(metrics.search)
	local area = self.rowArea
	area:ClearAllPoints()
	if self.compact then
		area:SetPoint('TOPLEFT', 0, -6)
	else
		area:SetPoint('TOPLEFT', 0, -(10 + metrics.search + 8 + 18 + 10))
	end
	area:SetPoint('BOTTOMRIGHT', -1, 0)
end

---Narrow windows show the list as a rail of avatars.
---@param compact boolean
function List:SetCompact(compact)
	if self.compact == compact then
		return
	end
	self.compact = compact
	if compact then
		self.filter = 'all'
		self.query = ''
		self.search:SetText('')
		for _, chip in ipairs(self.chips) do
			chip:SetSelected(chip.filterKey == 'all')
		end
	end
	self.search:SetShown(not compact)
	for _, chip in ipairs(self.chips) do
		chip:SetShown(not compact)
	end
	self:ApplyMetrics()
	self:Refresh()
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
	local convos = M.Store:List(self.filter, self.query)
	local data = {}
	local pinnedCount = 0
	for _, convo in ipairs(convos) do
		if convo.pinned then
			pinnedCount = pinnedCount + 1
		end
	end
	local splitSections = not self.compact and pinnedCount > 0 and pinnedCount < #convos
	self.firstConvo = convos[1]
	for i, convo in ipairs(convos) do
		if splitSections and i == 1 then
			data[#data + 1] = { section = L['Pinned'] }
		elseif splitSections and i == pinnedCount + 1 then
			data[#data + 1] = { section = L['Recent'] }
		end
		data[#data + 1] = { convo = convo }
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

	row.avatar:ClearAllPoints()
	row.badge:ClearAllPoints()
	if self.compact then
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
	row.avatar:SetPoint('LEFT', 12, 0)
	row.badge:SetPoint('BOTTOMRIGHT', -12, 8)

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
	row.pin:SetShown(convo.pinned == true)

	row.preview:SetText(Preview(convo))
	T.SetColor(row.preview, unread and T.color.text or T.color.muted)
	row.preview:Show()

	if convo.muted then
		row.badge:SetCount(convo.unread, T.color.faint[1], T.color.faint[2], T.color.faint[3])
	else
		row.badge:SetCount(convo.unread, r, g, b)
	end
	row.section:Hide()
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
		if entry.section then
			row.convo = nil
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
	end

	self.empty:SetShown(#self.data == 0 and not self.compact)
	if #self.data == 0 and not self.compact then
		if self.query ~= '' then
			self.empty:SetText(string.format(L['Nothing matches "%s".'], self.query))
		elseif self.filter == 'unread' then
			self.empty:SetText(L['You are all caught up.'])
		elseif self.filter == 'rooms' then
			self.empty:SetText(L['No group chats yet. Turn them on in Messenger settings.'])
		else
			self.empty:SetText(L['No conversations yet.'])
		end
	end
end
