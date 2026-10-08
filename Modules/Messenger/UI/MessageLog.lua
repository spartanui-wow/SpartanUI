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

-- Bubble style
local BUBBLE_X = 10
local BUBBLE_Y = 6
local BUBBLE_GAP = 2
local BUBBLE_MAX = 0.78
local SMALL_CORNER = 4
local AVATAR = 22
local AVATAR_GAP = 6
local CLASS_ICONS = 'Interface\\TargetingFrame\\UI-Classes-Circles'
local CLASS_CROP = 0.08

local heightCache = setmetatable({}, { __mode = 'k' })
local bubbleCache = setmetatable({}, { __mode = 'k' })
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

	row.bubble = M.Bubble.Create(row)

	row.avatar = row:CreateTexture(nil, 'ARTWORK')
	row.avatar:SetSize(AVATAR, AVATAR)
	local mask = row:CreateMaskTexture()
	mask:SetTexture(M.mediaPath .. 'Circle', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE')
	mask:SetAllPoints(row.avatar)
	row.avatar:AddMaskTexture(mask)
	row.avatarLetter = T.Text(row, 'small')
	row.avatarLetter:SetPoint('CENTER', row.avatar, 'CENTER', 0, 0)
	row.avatarLetter:SetJustifyH('CENTER')

	row:SetScript('OnHyperlinkClick', OnLinkClick)
	row:SetScript('OnHyperlinkEnter', OnLinkEnter)
	row:SetScript('OnHyperlinkLeave', OnLinkLeave)
	row:SetScript('OnEnter', function(self)
		local item = self.item
		if item and item.kind == 'msg' then
			self.hl:Show()
			if not item.head then
				self.hoverTime:SetText(U.Clock(item.msg.t))
				self.hoverTime:Show()
			end
		elseif item and item.kind == 'bubble' and not item.tail then
			-- Times show under the last bubble of a run; the others show theirs beside the bubble
			self.hoverTime:SetText(U.Clock(item.msg.t))
			self.hoverTime:Show()
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
		elseif (item.kind == 'msg' or item.kind == 'bubble' or item.kind == 'emote') and button == 'RightButton' then
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
	row.lineR:SetHeight(T.Pixel())
	row.hl:Hide()
	row.hoverTime:Hide()
	row.hoverTime:ClearAllPoints()
	row.hoverTime:SetPoint('TOPRIGHT', -GUTTER - 4, -1)
	-- Bubbles move the time and the name; the line style expects them back in place
	row.time:ClearAllPoints()
	row.time:SetPoint('LEFT', row.name, 'RIGHT', 8, 0)
	row.bubble:Hide()
	row.avatar:Hide()
	row.avatarLetter:Hide()
	row.body:SetJustifyH('LEFT')
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
		wipe(bubbleCache)
		log:Rebuild(true)
	end)
	M:On('COLORS_CHANGED', function()
		if log.key and log:IsVisible() then
			log:Render()
		end
	end)
	M:On('ALIASES_CHANGED', function()
		if log.key then
			log:Rebuild(true)
		end
	end)
	M:On('SETTINGS_CHANGED', function()
		wipe(displayCache)
		wipe(heightCache)
		wipe(bubbleCache)
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

	if M.settings.messageStyle == 'bubbles' then
		self:BuildBubbles(convo, metaH, nameH)
		if atBottom then
			self.offset = math.max(0, self.total - self:GetHeight())
		end
		self:Render()
		return
	end

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

---Lays the log out as bubbles: the player's on the right, everyone else's on the left, and a run
---of messages from one person drawn as one group with the time under its last bubble.
---@param convo MessengerConversation
---@param metaH number
---@param nameH number
function Log:BuildBubbles(convo, metaH, nameH)
	local items = self.items
	local isRoom = M.Store.IsRoomKey(convo.key)
	local size = T.BaseSize()
	local lane = self.bodyWidth
	local avatarW = isRoom and (AVATAR + AVATAR_GAP) or 0
	local maxMine = math.floor(lane * BUBBLE_MAX) - BUBBLE_X * 2
	local maxTheirs = math.floor((lane - avatarW) * BUBBLE_MAX) - BUBBLE_X * 2
	local msgs = convo.msgs
	local first = math.max(1, #msgs - self.renderCount + 1)
	local me = UnitName('player')

	-- What each line is, and where each run from one person starts
	local entries = {}
	if first > 1 then
		entries[1] = { kind = 'more' }
	end
	local prev, prevDay
	for i = first, #msgs do
		local msg = msgs[i]
		local day = U.DayKey(msg.t or 0)
		if day ~= prevDay then
			entries[#entries + 1] = { kind = 'day', label = U.DayLabel(msg.t or 0) }
			prevDay = day
			prev = nil
		end
		if msg == self.newMarker then
			entries[#entries + 1] = { kind = 'new' }
			prev = nil
		end
		if msg.sys or msg.em then
			entries[#entries + 1] = { kind = msg.sys and 'sys' or 'emote', msg = msg }
			prev = nil
		else
			local head = not prev or not SameSender(prev, msg) or (msg.t - prev.t) > GROUP_WINDOW
			entries[#entries + 1] = { kind = 'bubble', msg = msg, mine = msg.o and true or false, head = head, room = isRoom }
			prev = msg
		end
	end
	for i, entry in ipairs(entries) do
		if entry.kind == 'bubble' then
			local nextEntry = entries[i + 1]
			entry.tail = not nextEntry or nextEntry.kind ~= 'bubble' or nextEntry.head
		end
	end

	local y = 8
	local lastKind
	for _, entry in ipairs(entries) do
		local kind = entry.kind
		local msg = entry.msg
		if kind == 'more' then
			entry.h = metaH + 16
		elseif kind == 'day' then
			entry.h = metaH + 18
		elseif kind == 'new' then
			self.markerY = y
			entry.h = metaH + 10
		elseif kind == 'sys' then
			local cache = heightCache[msg]
			if not (cache and cache.w == lane and cache.s == size) then
				cache = { w = lane, s = size, h = Measure(self.measureMeta, msg.x or '', lane - 18) }
				heightCache[msg] = cache
			end
			entry.h = cache.h + 10
		elseif kind == 'emote' then
			-- Same text and width as the line style, so the two share measurements
			local cache = heightCache[msg]
			if not (cache and cache.w == lane and cache.s == size) then
				local text = (msg.s and U.DisplayName(msg.s) or '') .. ' ' .. DisplayText(msg)
				cache = { w = lane, s = size, h = Measure(self.measure, text, lane) }
				heightCache[msg] = cache
			end
			entry.bodyH = cache.h
			entry.h = cache.h + 10
		else
			local textW = entry.mine and maxMine or maxTheirs
			local cache = bubbleCache[msg]
			if not (cache and cache.w == textW and cache.s == size) then
				local fs = self.measure
				local h = Measure(fs, DisplayText(msg), textW)
				local w = fs:GetUnboundedStringWidth()
				if w > textW then
					w = fs.GetWrappedWidth and fs:GetWrappedWidth() or textW
				end
				cache = { w = textW, s = size, h = h, bw = math.min(textW, math.ceil(w) + 1) }
				bubbleCache[msg] = cache
			end
			entry.textW = textW
			entry.bodyH = cache.h
			entry.bubbleW = cache.bw + BUBBLE_X * 2
			entry.bubbleH = cache.h + BUBBLE_Y * 2
			if entry.head then
				entry.gap = lastKind == 'bubble' and GROUP_GAP or 4
			else
				entry.gap = BUBBLE_GAP
			end
			-- Names over runs in channels, and over the player's own when an alt sent them
			entry.labelH = 0
			if entry.head and ((isRoom and not entry.mine) or (entry.mine and msg.a and msg.a ~= me)) then
				entry.labelH = nameH + 3
			end
			entry.h = entry.gap + entry.labelH + entry.bubbleH + (entry.tail and (metaH + 4) or 0)
		end
		entry.y = y
		items[#items + 1] = entry
		y = y + entry.h
		lastKind = kind
	end
	self.total = y + 10
end

---The round picture beside the last bubble of someone's run in a channel: their class, or the
---first letter of their name on their bubble color.
---@param row Frame
---@param msg table
---@param r number
---@param g number
---@param b number
local function DrawAvatar(row, msg, r, g, b)
	local avatar = row.avatar
	avatar:ClearAllPoints()
	avatar:SetPoint('BOTTOMRIGHT', row.bubble.box, 'BOTTOMLEFT', -AVATAR_GAP, 0)
	local coords = msg.cl and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[msg.cl]
	if coords then
		local l, rt, t, bt = coords[1], coords[2], coords[3], coords[4]
		local dx, dy = (rt - l) * CLASS_CROP, (bt - t) * CLASS_CROP
		avatar:SetTexture(CLASS_ICONS)
		avatar:SetTexCoord(l + dx, rt - dx, t + dy, bt - dy)
		avatar:SetVertexColor(1, 1, 1, 1)
	else
		avatar:SetTexture(T.WHITE)
		avatar:SetTexCoord(0, 1, 0, 1)
		avatar:SetVertexColor(r, g, b, 1)
		local name = msg.s and U.ShortName(msg.s) or '?'
		row.avatarLetter:SetText(strupper(name:match('^[%z\1-\127\194-\244][\128-\191]*') or '?'))
		row.avatarLetter:Show()
	end
	avatar:Show()
end

---@param row Frame
---@param item table
---@param convo MessengerConversation|nil
function Log:RenderBubble(row, item, convo)
	local msg = item.msg
	local mine = item.mine
	local box = row.bubble.box
	local top = item.gap + item.labelH
	box:ClearAllPoints()
	if mine then
		box:SetPoint('TOPRIGHT', row, 'TOPRIGHT', -(GUTTER + 6), -top)
	else
		box:SetPoint('TOPLEFT', row, 'TOPLEFT', PAD_X + (item.room and (AVATAR + AVATAR_GAP) or 0), -top)
	end

	-- Round corners, except the sender's side inside a run, which stays tight
	local big = math.floor((self.lineH or 14) / 2 + BUBBLE_Y)
	local upper = item.head and big or SMALL_CORNER
	local lower = item.tail and big or SMALL_CORNER
	local radii = mine and { big, upper, big, lower } or { upper, big, lower, big }
	row.bubble:Layout(item.bubbleW, item.bubbleH, radii)

	local r, g, b
	if convo then
		if mine then
			r, g, b = M.Colors:Mine(convo)
		else
			r, g, b = M.Colors:Theirs(convo, (M.Colors:SenderKey(convo, msg)))
		end
	end
	local fr, fg, fb
	if r then
		fr, fg, fb = T.BubbleFill(r, g, b)
	else
		fr, fg, fb = T.color.bubble[1], T.color.bubble[2], T.color.bubble[3]
	end
	row.bubble:SetColor(fr, fg, fb, 1)

	row.body:ClearAllPoints()
	row.body:SetPoint('TOPLEFT', box, 'TOPLEFT', BUBBLE_X, -BUBBLE_Y)
	row.body:SetWidth(item.textW)
	row.body:SetHeight(item.bodyH + 2)
	T.SetColor(row.body, T.color.text)
	row.body:SetText(DisplayText(msg))
	row.body:Show()

	if item.labelH > 0 then
		local label, lr, lg, lb = self:SenderLabel(msg)
		row.name:SetText(label)
		row.name:SetTextColor(lr, lg, lb)
		row.name:ClearAllPoints()
		if mine then
			row.name:SetPoint('BOTTOMRIGHT', box, 'TOPRIGHT', -4, 3)
		else
			row.name:SetPoint('BOTTOMLEFT', box, 'TOPLEFT', 4, 3)
		end
		row.name:Show()
	end

	if item.tail then
		row.time:SetText(U.Clock(msg.t))
		row.time:ClearAllPoints()
		if mine then
			row.time:SetPoint('TOPRIGHT', box, 'BOTTOMRIGHT', -4, -3)
		else
			row.time:SetPoint('TOPLEFT', box, 'BOTTOMLEFT', 4, -3)
		end
		row.time:Show()
		if item.room and not mine then
			DrawAvatar(row, msg, fr, fg, fb)
		end
	else
		row.hoverTime:ClearAllPoints()
		if mine then
			row.hoverTime:SetPoint('RIGHT', box, 'LEFT', -8, 0)
		else
			row.hoverTime:SetPoint('LEFT', box, 'RIGHT', 8, 0)
		end
	end
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
			elseif item.kind == 'bubble' or item.kind == 'emote' then
				local msg = item.msg
				if msg.mn or msg == self.flashMsg then
					local wash = msg == self.flashMsg and T.color.found or T.color.mention
					row.mention:SetVertexColor(wash[1], wash[2], wash[3], wash[4])
					row.mention:Show()
				end
				if item.kind == 'bubble' then
					self:RenderBubble(row, item, convo)
				else
					-- Emotes read as a line about the room, centered like the day separators
					local er, eg, eb = T.KindColor({ kind = 'EMOTE' })
					row.body:ClearAllPoints()
					row.body:SetPoint('TOPLEFT', PAD_X, -5)
					row.body:SetWidth(self.bodyWidth)
					row.body:SetHeight(item.bodyH + 2)
					row.body:SetJustifyH('CENTER')
					row.body:SetTextColor(er, eg, eb)
					row.body:SetText(self:SenderLabel(msg) .. ' ' .. DisplayText(msg))
					row.body:Show()
				end
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
				row.label:SetPoint('CENTER', 0, 0)
				row.label:Show()
				row.lineL:SetVertexColor(kr, kg, kb, 0.9)
				row.lineR:SetVertexColor(kr, kg, kb, 0.9)
				row.lineL:SetHeight(T.Pixel() * 2)
				row.lineR:SetHeight(T.Pixel() * 2)
				row.lineL:ClearAllPoints()
				row.lineL:SetPoint('LEFT', PAD_X, 0)
				row.lineL:SetPoint('RIGHT', row.label, 'LEFT', -10, 0)
				row.lineR:ClearAllPoints()
				row.lineR:SetPoint('LEFT', row.label, 'RIGHT', 10, 0)
				row.lineR:SetPoint('RIGHT', -GUTTER - 4, 0)
				row.lineL:Show()
				row.lineR:Show()
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

local function MenuAtCursor()
	local dropdown = _G.MessengerDropDown
	if dropdown and dropdown:IsShown() then
		local x, y = GetCursorPosition()
		local scale = dropdown:GetEffectiveScale()
		dropdown:ClearAllPoints()
		dropdown:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', x / scale, y / scale)
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
	local convo = self.key and M.Store:Get(self.key)
	local bubbles = M.settings.messageStyle == 'bubbles'
	if convo and bubbles and not msg.em then
		if msg.o then
			table.insert(items, {
				text = L['Your bubble color...'],
				divider = true,
				onClick = function()
					M.ChatPane.MyColorMenu(row, convo)
					MenuAtCursor()
				end,
			})
		else
			local key = M.Colors:SenderKey(convo, msg)
			if key then
				local name = msg.s and M:PersonLabel(msg.s) or M:GetTitle(convo)
				table.insert(items, {
					text = string.format(L['Bubble color for %s...'], name),
					divider = true,
					onClick = function()
						M.ChatPane.PersonColorMenu(row, convo, key, name)
						MenuAtCursor()
					end,
				})
			end
		end
	end
	table.insert(items, {
		text = L['Show messages as bubbles'],
		checked = bubbles,
		divider = not (convo and bubbles and not msg.em),
		onClick = function()
			M:SetMessageStyle(bubbles and 'lines' or 'bubbles')
		end,
	})
	W.OpenMenu(row, items)
	MenuAtCursor()
end
