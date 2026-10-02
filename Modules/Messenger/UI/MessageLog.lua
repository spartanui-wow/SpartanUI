local _, ns = ...
local M = ns.Messenger
local T = M.Theme
local U = M.Util
local W = M.Widgets
local L = M.L

-- A virtualized log. Messages are measured once per width and font size, laid out as a list of
-- items with absolute offsets, and only the rows inside the viewport are drawn from a pool.
-- Consecutive messages from the same sender within five minutes share one name line.

---@class Messenger.MessageLog
local ML = {}
M.MessageLog = ML

local PAD_X = 14
local GUTTER = 10
local GROUP_GAP = 10
local LINE_GAP = 2
local GROUP_WINDOW = 300
local PAGE = 150
local GM_ICON = '|TInterface\\ChatFrame\\UI-ChatIcon-Blizz:12:20:0:0:32:16:4:28:0:16|t '

local heightCache = setmetatable({}, { __mode = 'k' })
local displayCache = setmetatable({}, { __mode = 'k' })

---@param msg table
---@return string
local function DisplayText(msg)
	local cached = displayCache[msg]
	if cached then
		return cached
	end
	local text = M.Emoji:Render(U.RaidIcons(U.Linkify(msg.x or '')))
	if msg.gm then
		text = GM_ICON .. text
	end
	displayCache[msg] = text
	return text
end

---@param a table
---@param b table
---@return boolean
local function SameSender(a, b)
	return (a.o and true or false) == (b.o and true or false) and a.s == b.s
end

----------------------------------------------------------------------------------------------------
-- Link handling
----------------------------------------------------------------------------------------------------

local function OnLinkClick(_, link, text, button)
	local linkType, data = link:match('^(%a+):(.*)$')
	if linkType == 'url' then
		W.CopyBox(L['Copy link'], data)
		return
	end
	if linkType == 'player' and button == 'LeftButton' and not IsModifiedClick() then
		local name = strsplit(':', data)
		if name and name ~= '' then
			M:OpenWhisper(name, true)
			return
		end
	end
	SetItemRef(link, text, button, DEFAULT_CHAT_FRAME)
end

local TOOLTIP_TYPES = {
	item = true,
	spell = true,
	achievement = true,
	quest = true,
	talent = true,
	enchant = true,
	currency = true,
	instancelock = true,
	keystone = true,
	mount = true,
	battlepet = false,
}

local function OnLinkEnter(row, link)
	local linkType = link:match('^(%a+):')
	if linkType == 'url' then
		W.ShowTip(row, L['Click to copy this link'])
		return
	end
	if TOOLTIP_TYPES[linkType] then
		GameTooltip:SetOwner(row, 'ANCHOR_CURSOR')
		if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
			GameTooltip:Show()
		else
			GameTooltip:Hide()
		end
	end
end

local function OnLinkLeave()
	GameTooltip:Hide()
end

----------------------------------------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------------------------------------

---@param log Frame
local function CreateRow(log)
	local row = CreateFrame('Frame', nil, log.canvas)
	row.log = log
	row:EnableMouse(true)
	row:SetHyperlinksEnabled(true)

	row.hl = T.Fill(row, T.color.hoverSoft)
	-- Lines that mention the player, and the line a search jumped to, get a soft wash
	row.mention = T.Fill(row, T.color.mention, 'BACKGROUND', -1)
	row.mention:Hide()
	row.hl:Hide()

	row.name = T.Text(row, 'name')
	row.name:SetPoint('TOPLEFT', PAD_X, 0)

	row.time = T.Text(row, 'meta', T.color.faint)
	row.time:SetPoint('LEFT', row.name, 'RIGHT', 8, 0)

	row.hoverTime = T.Text(row, 'meta', T.color.faint)
	row.hoverTime:SetPoint('TOPRIGHT', -GUTTER - 4, -1)
	row.hoverTime:Hide()

	row.body = T.Text(row, 'body')
	row.body:SetWordWrap(true)
	if row.body.SetNonSpaceWrap then
		row.body:SetNonSpaceWrap(true)
	end
	row.body:SetJustifyV('TOP')

	row.label = T.Text(row, 'meta', T.color.faint)

	row.icon = row:CreateTexture(nil, 'ARTWORK')
	row.icon:SetSize(12, 12)

	row.lineL = row:CreateTexture(nil, 'BORDER')
	row.lineL:SetTexture(T.WHITE)
	row.lineR = row:CreateTexture(nil, 'BORDER')
	row.lineR:SetTexture(T.WHITE)
	local px = T.Pixel()
	row.lineL:SetHeight(px)
	row.lineR:SetHeight(px)

	row:SetScript('OnHyperlinkClick', OnLinkClick)
	row:SetScript('OnHyperlinkEnter', OnLinkEnter)
	row:SetScript('OnHyperlinkLeave', OnLinkLeave)
	row:SetScript('OnEnter', function(self)
		if self.item and self.item.kind == 'msg' then
			self.hl:Show()
			if not self.item.head then
				self.hoverTime:SetText(U.Clock(self.item.msg.t))
				self.hoverTime:Show()
			end
		end
	end)
	row:SetScript('OnLeave', function(self)
		self.hl:Hide()
		self.hoverTime:Hide()
	end)
	row:SetScript('OnMouseUp', function(self, button)
		local item = self.item
		if not item then
			return
		end
		if item.kind == 'more' and button == 'LeftButton' then
			self.log:ShowEarlier()
		elseif item.kind == 'msg' and button == 'RightButton' then
			self.log:MessageMenu(self, item.msg)
		end
	end)
	return row
end

---@param row Frame
local function ResetRow(row)
	row.mention:Hide()
	row.name:Hide()
	row.time:Hide()
	row.body:Hide()
	row.label:Hide()
	-- System lines stretch the label to the full width; a reused row must not keep that
	row.label:SetWidth(0)
	row.label:SetWordWrap(false)
	row.icon:Hide()
	row.lineL:Hide()
	row.lineR:Hide()
	row.lineL:SetHeight(T.Pixel())
	row.hl:Hide()
	row.hoverTime:Hide()
end

----------------------------------------------------------------------------------------------------
-- Log
----------------------------------------------------------------------------------------------------

---@class MessengerLog : Frame
local Log = {}

---@param parent Frame
---@return MessengerLog
function ML.Create(parent)
	local log = CreateFrame('Frame', nil, parent)
	Mixin(log, Log)
	log:SetClipsChildren(true)
	log:EnableMouseWheel(true)

	log.canvas = CreateFrame('Frame', nil, log)
	log.canvas:SetAllPoints()

	log.measure = T.Text(log, 'body', nil, 'BACKGROUND')
	log.measure:SetWordWrap(true)
	if log.measure.SetNonSpaceWrap then
		log.measure:SetNonSpaceWrap(true)
	end
	log.measure:SetAlpha(0)
	log.measureName = T.Text(log, 'name', nil, 'BACKGROUND')
	log.measureName:SetAlpha(0)
	log.measureMeta = T.Text(log, 'meta', nil, 'BACKGROUND')
	log.measureMeta:SetAlpha(0)

	log.rows = {}
	log.items = {}
	log.offset = 0
	log.total = 0
	log.renderCount = PAGE
	log.pendingNew = 0

	-- Scrollbar
	log.track = log:CreateTexture(nil, 'ARTWORK')
	log.track:SetTexture(T.WHITE)
	log.track:SetVertexColor(1, 1, 1, 0.04)
	log.track:SetPoint('TOPRIGHT', -3, -4)
	log.track:SetPoint('BOTTOMRIGHT', -3, 4)
	log.track:SetWidth(3)

	local thumb = CreateFrame('Button', nil, log)
	thumb:SetWidth(9)
	thumb.tex = thumb:CreateTexture(nil, 'OVERLAY')
	thumb.tex:SetTexture(T.WHITE)
	thumb.tex:SetVertexColor(1, 1, 1, 0.22)
	thumb.tex:SetPoint('TOPRIGHT', -3, 0)
	thumb.tex:SetPoint('BOTTOMRIGHT', -3, 0)
	thumb.tex:SetWidth(3)
	thumb:SetScript('OnEnter', function(self)
		self.tex:SetVertexColor(1, 1, 1, 0.4)
	end)
	thumb:SetScript('OnLeave', function(self)
		if not self.dragging then
			self.tex:SetVertexColor(1, 1, 1, 0.22)
		end
	end)
	thumb:SetScript('OnMouseDown', function(self)
		local _, cy = GetCursorPosition()
		self.dragging = true
		self.startY = cy / self:GetEffectiveScale()
		self.startOffset = log.offset
		self:SetScript('OnUpdate', function(s)
			local _, y = GetCursorPosition()
			y = y / s:GetEffectiveScale()
			local viewH = log:GetHeight()
			local maxOffset = math.max(0, log.total - viewH)
			local travel = viewH - s:GetHeight()
			if travel > 0 then
				log:SetOffset(s.startOffset + (s.startY - y) / travel * maxOffset)
			end
		end)
	end)
	thumb:SetScript('OnMouseUp', function(self)
		self.dragging = false
		self:SetScript('OnUpdate', nil)
		self.tex:SetVertexColor(1, 1, 1, self:IsMouseOver() and 0.4 or 0.22)
	end)
	log.thumb = thumb

	-- Jump to latest
	local jump = CreateFrame('Button', nil, log)
	jump:SetHeight(22)
	jump:SetPoint('BOTTOM', 0, 8)
	jump:SetFrameLevel(log:GetFrameLevel() + 10)
	jump.bg = T.Fill(jump, T.color.pill)
	jump.text = T.Text(jump, 'small', T.color.onLight)
	jump.text:SetPoint('CENTER')
	jump:SetScript('OnClick', function()
		log:ScrollToBottom()
	end)
	jump:Hide()
	log.jump = jump

	-- Empty state
	log.empty = T.Text(log, 'body', T.color.faint)
	log.empty:SetPoint('CENTER', 0, 0)
	log.empty:SetJustifyH('CENTER')
	log.empty:Hide()

	log:SetScript('OnMouseWheel', function(self, delta)
		local step = (self.lineH or 14) * 3
		if IsShiftKeyDown() then
			step = self:GetHeight() * 0.9
		end
		if IsControlKeyDown() then
			if delta > 0 then
				self:SetOffset(0)
			else
				self:ScrollToBottom()
			end
			return
		end
		self:SetOffset(self.offset - delta * step)
	end)
	log:SetScript('OnSizeChanged', function(self)
		M:Defer('log-size-' .. tostring(self), function()
			self:Rebuild(true)
		end)
	end)
	log:SetScript('OnShow', function(self)
		self:Rebuild(true)
	end)

	M:On('MESSAGE', function(key, msg)
		if key == log.key then
			log:OnMessage(msg)
		end
	end)
	M:On('CONVO_CHANGED', function(key)
		if key == log.key then
			log:Rebuild(true)
		end
	end)
	M:On('FONTS_CHANGED', function()
		wipe(heightCache)
		log:Rebuild(true)
	end)
	M:On('ALIASES_CHANGED', function()
		if log.key then
			log:Rebuild(true)
		end
	end)
	M:On('SETTINGS_CHANGED', function()
		wipe(displayCache)
		wipe(heightCache)
		log:Rebuild(true)
	end)
	return log
end

---@param key string|nil
function Log:SetConversation(key)
	self.key = key
	self.renderCount = PAGE
	self.pendingNew = 0
	self.newMarker = nil
	local convo = key and M.Store:Get(key)
	if convo and (convo.unread or 0) > 0 then
		-- Unread counts only incoming lines, so walk back over exactly that many of them
		local remaining = convo.unread
		for i = #convo.msgs, 1, -1 do
			local msg = convo.msgs[i]
			if not msg.o and not msg.sys then
				remaining = remaining - 1
				if remaining == 0 then
					self.newMarker = msg
					break
				end
			end
		end
	end
	self.jump:Hide()
	self:Rebuild(false)
	if self.newMarker and self.markerY then
		self:SetOffset(self.markerY - 24)
	else
		self:ScrollToBottom()
	end
end

---Scrolls to the newest message containing the text and briefly highlights it.
---@param query string
---@return boolean found
function Log:JumpTo(query)
	local convo = self.key and M.Store:Get(self.key)
	if not convo or not query or query == '' then
		return false
	end
	local needle = strlower(query)
	local index
	for i = #convo.msgs, 1, -1 do
		local text = convo.msgs[i].x
		if text and strlower(U.Plain(text)):find(needle, 1, true) then
			index = i
			break
		end
	end
	if not index then
		return false
	end
	local msg = convo.msgs[index]
	self.renderCount = math.max(self.renderCount, #convo.msgs - index + 1)
	self.flashMsg = msg
	self:Rebuild(false)
	for _, item in ipairs(self.items) do
		if item.msg == msg then
			self:SetOffset(item.y - 24)
			break
		end
	end
	C_Timer.After(2, function()
		if self.flashMsg == msg then
			self.flashMsg = nil
			self:Render()
		end
	end)
	return true
end

---@return boolean
function Log:IsAtBottom()
	return self.offset >= math.max(0, self.total - self:GetHeight()) - 2
end

---@param key string
---@return boolean
function Log:IsViewing(key)
	return self.key == key and self:IsVisible() and self:IsAtBottom()
end

function Log:ScrollToBottom()
	self.pendingNew = 0
	self.jump:Hide()
	self:SetOffset(math.huge)
end

---@param offset number
function Log:SetOffset(offset)
	local maxOffset = math.max(0, self.total - self:GetHeight())
	self.offset = math.max(0, math.min(offset, maxOffset))
	self:Render()
	if self:IsAtBottom() then
		self.pendingNew = 0
		self.jump:Hide()
		if self.key and self:IsVisible() then
			M.Store:MarkRead(self.key)
		end
	end
end

function Log:ShowEarlier()
	local before = self.total
	self.renderCount = self.renderCount + PAGE
	self:Rebuild(false)
	self:SetOffset(self.offset + (self.total - before))
end

---@param msg table
function Log:OnMessage(msg)
	local wasAtBottom = self:IsAtBottom()
	local unseen = not wasAtBottom or not self:IsVisible()
	if unseen and not msg.o and not msg.sys then
		self.pendingNew = self.pendingNew + 1
		if not self.newMarker then
			self.newMarker = msg
		end
	end
	self:Rebuild(false)
	if wasAtBottom or msg.o then
		self:ScrollToBottom()
	else
		self:SetOffset(self.offset)
		self.jump.text:SetText(string.format(L['%d new - jump to latest'], self.pendingNew))
		self.jump:SetWidth(self.jump.text:GetStringWidth() + 20)
		self.jump:SetShown(self.pendingNew > 0)
	end
end

---@param fs FontString
---@param text string
---@param width number
---@return number
local function Measure(fs, text, width)
	fs:SetWidth(width)
	fs:SetText(text)
	return fs:GetStringHeight()
end

---Rebuilds items and offsets. keepBottom keeps the view pinned to the newest message.
---@param keepBottom boolean
function Log:Rebuild(keepBottom)
	local atBottom = keepBottom and self:IsAtBottom()
	local items = {}
	self.items = items
	self.markerY = nil

	local convo = self.key and M.Store:Get(self.key)
	local width = math.floor(self:GetWidth() - PAD_X - GUTTER - 6)
	if width < 60 then
		self.total = 0
		self:Render()
		return
	end
	self.bodyWidth = width
	local size = T.BaseSize()
	self.lineH = Measure(self.measure, 'Ag', 400)
	local nameH = Measure(self.measureName, 'Ag', 400)
	local metaH = Measure(self.measureMeta, 'Ag', 400)

	if not convo or #convo.msgs == 0 then
		self.total = 0
		if convo then
			self.empty:SetText(string.format(L['No messages with %s yet.'], M:GetTitle(convo)))
		else
			self.empty:SetText('')
		end
		self.empty:Show()
		self:Render()
		return
	end
	self.empty:Hide()

	local isRoom = M.Store.IsRoomKey(convo.key)
	local msgs = convo.msgs
	local first = math.max(1, #msgs - self.renderCount + 1)
	local y = 8
	local function add(item)
		item.y = y
		items[#items + 1] = item
		y = y + item.h
	end

	if first > 1 then
		add({ kind = 'more', h = metaH + 16 })
	end

	local prev, prevDay
	for i = first, #msgs do
		local msg = msgs[i]
		local day = U.DayKey(msg.t or 0)
		if day ~= prevDay then
			add({ kind = 'day', h = metaH + 18, label = U.DayLabel(msg.t or 0) })
			prevDay = day
			prev = nil
		end
		if msg == self.newMarker then
			self.markerY = y
			add({ kind = 'new', h = metaH + 10 })
			prev = nil
		end
		if msg.sys then
			local cache = heightCache[msg]
			local h
			if cache and cache.w == width and cache.s == size then
				h = cache.h
			else
				h = Measure(self.measureMeta, msg.x or '', width - 18)
				heightCache[msg] = { w = width, s = size, h = h }
			end
			add({ kind = 'sys', msg = msg, h = h + 10 })
			prev = nil
		else
			local head = not prev or msg.em or prev.em or not SameSender(prev, msg) or (msg.t - prev.t) > GROUP_WINDOW
			local cache = heightCache[msg]
			local bodyH
			if cache and cache.w == width and cache.s == size then
				bodyH = cache.h
			else
				local text = DisplayText(msg)
				if msg.em then
					text = (msg.s and U.DisplayName(msg.s) or '') .. ' ' .. text
				end
				bodyH = Measure(self.measure, text, width)
				heightCache[msg] = { w = width, s = size, h = bodyH }
			end
			local gap = head and GROUP_GAP or LINE_GAP
			if not prev then
				gap = 4
			end
			local h = gap + bodyH
			if head and not msg.em then
				h = h + nameH + 2
			end
			add({ kind = 'msg', msg = msg, head = head, gap = gap, bodyH = bodyH, nameH = nameH, h = h, room = isRoom })
			prev = msg
		end
	end
	self.total = y + 10

	if atBottom then
		self.offset = math.max(0, self.total - self:GetHeight())
	end
	self:Render()
end

---@param msg table
---@return string text, number r, number g, number b
function Log:SenderLabel(msg)
	local convo = M.Store:Get(self.key)
	if msg.o then
		local name = msg.a or UnitName('player')
		local r, g, b
		if name == UnitName('player') then
			local _, classFile = UnitClass('player')
			r, g, b = T.NameColor(classFile)
		else
			r, g, b = T.color.muted[1], T.color.muted[2], T.color.muted[3]
		end
		return name, r, g, b
	end
	if msg.s then
		local r, g, b = T.NameColor(msg.cl)
		local display = M:PersonLabel(msg.s)
		return '|Hplayer:' .. msg.s .. '|h' .. display .. '|h', r, g, b
	end
	if convo then
		local presence = M.Contacts:GetPresence(convo)
		local r, g, b = T.NameColor(presence.class or convo.class)
		if convo.kind == 'WHISPER' then
			return '|Hplayer:' .. convo.target .. '|h' .. M:GetTitle(convo) .. '|h', r, g, b
		end
		return M:GetTitle(convo), r, g, b
	end
	return '?', 1, 1, 1
end

function Log:Render()
	local viewH = self:GetHeight()
	local width = self:GetWidth()
	local shift = self.total < viewH and (viewH - self.total) or 0
	local top = self.offset
	local bottom = top + viewH
	local convo = self.key and M.Store:Get(self.key)
	local kr, kg, kb = T.KindColor(convo)

	local used = 0
	for _, item in ipairs(self.items) do
		if item.y + item.h >= top and item.y <= bottom then
			used = used + 1
			local row = self.rows[used]
			if not row then
				row = CreateRow(self)
				self.rows[used] = row
			end
			ResetRow(row)
			row.item = item
			row:ClearAllPoints()
			row:SetPoint('TOPLEFT', self.canvas, 'TOPLEFT', 0, -(item.y - top + shift))
			row:SetSize(width, item.h)
			row:Show()

			if item.kind == 'msg' then
				local msg = item.msg
				if msg.mn or msg == self.flashMsg then
					local wash = msg == self.flashMsg and T.color.found or T.color.mention
					row.mention:SetVertexColor(wash[1], wash[2], wash[3], wash[4])
					row.mention:Show()
				end
				local bodyTop = item.gap
				if item.head and not msg.em then
					local label, r, g, b = self:SenderLabel(msg)
					row.name:SetText(label)
					row.name:SetTextColor(r, g, b)
					row.name:ClearAllPoints()
					row.name:SetPoint('TOPLEFT', PAD_X, -item.gap)
					row.name:Show()
					row.time:SetText(U.Clock(msg.t))
					row.time:Show()
					bodyTop = item.gap + item.nameH + 2
				end
				local text = DisplayText(msg)
				if msg.em then
					local label = self:SenderLabel(msg)
					text = label .. ' ' .. text
					local er, eg, eb = T.KindColor({ kind = 'EMOTE' })
					row.body:SetTextColor(er, eg, eb)
				else
					T.SetColor(row.body, T.color.text)
				end
				row.body:ClearAllPoints()
				row.body:SetPoint('TOPLEFT', PAD_X, -bodyTop)
				row.body:SetWidth(self.bodyWidth)
				row.body:SetHeight(item.bodyH + 2)
				row.body:SetText(text)
				row.body:Show()
			elseif item.kind == 'day' then
				row.label:SetText(item.label)
				T.SetColor(row.label, T.color.faint)
				row.label:ClearAllPoints()
				row.label:SetPoint('CENTER', 0, -2)
				row.label:Show()
				local c = T.color.line
				row.lineL:SetVertexColor(c[1], c[2], c[3], c[4])
				row.lineR:SetVertexColor(c[1], c[2], c[3], c[4])
				row.lineL:ClearAllPoints()
				row.lineL:SetPoint('LEFT', PAD_X, -2)
				row.lineL:SetPoint('RIGHT', row.label, 'LEFT', -10, 0)
				row.lineR:ClearAllPoints()
				row.lineR:SetPoint('LEFT', row.label, 'RIGHT', 10, 0)
				row.lineR:SetPoint('RIGHT', -GUTTER - 4, -2)
				row.lineL:Show()
				row.lineR:Show()
			elseif item.kind == 'new' then
				row.label:SetText(L['New'])
				row.label:SetTextColor(kr, kg, kb)
				row.label:ClearAllPoints()
				row.label:SetPoint('RIGHT', -GUTTER - 4, 0)
				row.label:Show()
				row.lineL:SetVertexColor(kr, kg, kb, 0.9)
				row.lineL:SetHeight(T.Pixel() * 2)
				row.lineL:ClearAllPoints()
				row.lineL:SetPoint('LEFT', PAD_X, 0)
				row.lineL:SetPoint('RIGHT', row.label, 'LEFT', -8, 0)
				row.lineL:Show()
			elseif item.kind == 'sys' then
				T.SetIcon(row.icon, 'info')
				row.icon:SetVertexColor(T.color.faint[1], T.color.faint[2], T.color.faint[3])
				row.icon:ClearAllPoints()
				row.icon:SetPoint('TOPLEFT', PAD_X, -5)
				row.icon:Show()
				row.label:SetWidth(self.bodyWidth - 18)
				row.label:SetWordWrap(true)
				row.label:SetText(item.msg.x)
				T.SetColor(row.label, T.color.muted)
				row.label:ClearAllPoints()
				row.label:SetPoint('TOPLEFT', PAD_X + 18, -5)
				row.label:Show()
			elseif item.kind == 'more' then
				row.label:SetWidth(0)
				row.label:SetWordWrap(false)
				row.label:SetText(L['Show earlier messages'])
				T.SetColor(row.label, T.color.muted)
				row.label:ClearAllPoints()
				row.label:SetPoint('CENTER')
				row.label:Show()
			end
			if item.kind ~= 'sys' then
				row.label:SetWordWrap(false)
				row.label:SetWidth(0)
			end
		end
	end
	for i = used + 1, #self.rows do
		self.rows[i]:Hide()
		self.rows[i].item = nil
	end

	-- Scrollbar
	local scrollable = self.total > viewH + 1
	self.track:SetShown(scrollable)
	self.thumb:SetShown(scrollable)
	if scrollable then
		local thumbH = math.max(24, viewH * viewH / self.total)
		local maxOffset = self.total - viewH
		local pos = (viewH - thumbH) * (self.offset / maxOffset)
		self.thumb:SetHeight(thumbH)
		self.thumb:ClearAllPoints()
		self.thumb:SetPoint('TOPRIGHT', 0, -pos)
	end
end

---Right-click menu on a message.
---@param row Frame
---@param msg table
function Log:MessageMenu(row, msg)
	local items = {
		{
			text = L['Copy text'],
			onClick = function()
				W.CopyBox(L['Copy message'], U.Plain(msg.x or ''))
			end,
		},
	}
	if msg.s and not msg.o then
		table.insert(items, {
			text = string.format(L['Whisper %s'], U.DisplayName(msg.s)),
			onClick = function()
				M:OpenWhisper(msg.s, true)
			end,
		})
	end
	W.OpenMenu(row, items)
	local dropdown = _G.MessengerDropDown
	if dropdown then
		local x, y = GetCursorPosition()
		local scale = dropdown:GetEffectiveScale()
		dropdown:ClearAllPoints()
		dropdown:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', x / scale, y / scale)
	end
end
