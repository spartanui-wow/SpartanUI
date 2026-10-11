local _, ns = ...
local M = ns.Messenger
local T = M.Theme
local U = M.Util
local W = M.Widgets
local L = M.L
local Store = M.Store

-- The hover card of the data broker icon: a small view of Messenger. One line per conversation
-- (who, unread count, age, latest line), and a second card beside a hovered line with that
-- conversation's last messages. Uses LibQTip-2.0 when some addon has loaded it, otherwise a
-- plain game tooltip.

---@class Messenger.LauncherTip
local Tip = {}
M.UI.LauncherTip = Tip

local MAIN_KEY = 'LibsMessengerTip'
local PREVIEW_KEY = 'LibsMessengerTipPreview'
local COLUMNS = 4
local MAX_LINES = 15
local PLAIN_LINES = 8
local LINE_CHARS = 48
local PREVIEW_MESSAGES = 8
local PREVIEW_WIDTH = 320
-- Longer messages are shown as plain shortened text, so a pasted wall of links stays readable
local LONG_MESSAGE = 600
local LONG_CHARS = 300
local GROUP_WINDOW = 300
local HIDE_DELAY = 0.25
local ICON_SIZE = 12
local ICONS_W, ICONS_H = 256, 128
local GM_ICON = '|TInterface\\ChatFrame\\UI-ChatIcon-Blizz:12:20:0:0:32:16:4:28:0:16|t '

local SECTIONS = {
	{ key = 'people', label = L['People'] },
	{ key = 'rooms', label = L['Channels'] },
}

Tip.rows = {}

---@return table|nil
local function QTip()
	return LibStub and LibStub('LibQTip-2.0', true) or nil
end

----------------------------------------------------------------------------------------------------
-- Text
----------------------------------------------------------------------------------------------------

---@param text string
---@return string
local function Paint(text, r, g, b)
	return '|c' .. T.Hex(r, g, b) .. text .. '|r'
end

---@param text string
---@param color number[]
---@return string
local function PaintToken(text, color)
	return Paint(text, color[1], color[2], color[3])
end

---An icon from Messenger's sheet as inline markup, tinted.
---@param name string
---@return string
local function Icon(name, r, g, b)
	local path, left, right, top, bottom = T.IconCoords(name)
	return string.format(
		'|T%s:%d:%d:0:0:%d:%d:%d:%d:%d:%d:%d:%d:%d|t',
		path,
		ICON_SIZE,
		ICON_SIZE,
		ICONS_W,
		ICONS_H,
		left * ICONS_W,
		right * ICONS_W,
		top * ICONS_H,
		bottom * ICONS_H,
		math.floor(r * 255 + 0.5),
		math.floor(g * 255 + 0.5),
		math.floor(b * 255 + 0.5)
	)
end

---Plain text with no escape sequences left, so it can be cut anywhere. A typed pipe ("||")
---becomes \001 until Restore puts it back.
---@param text string
---@return string
local function Flatten(text)
	text = U.Plain(text)
	text = text:gsub('|K.-|k', ''):gsub('|n', ' ')
	text = text:gsub('||', '\001'):gsub('|', '')
	text = text:gsub('%s+', ' ')
	return U.Trim(text)
end

---@param text string
---@return string
local function Restore(text)
	return (text:gsub('\001', '||'))
end

---Cuts text to a number of characters (not bytes), ending it with "...".
---@param text string
---@param limit number
---@return string
local function Shorten(text, limit)
	local count = 0
	local cut
	for pos in text:gmatch('()[^\128-\191]') do
		count = count + 1
		if count > limit then
			cut = pos
			break
		end
	end
	if cut then
		return U.Trim(text:sub(1, cut - 1)) .. '...'
	end
	return text
end

---Time since a moment, short: "now", "5m", "3h", "2d", then the date.
---@param t number|nil
---@return string
local function Age(t)
	t = U.Num(t)
	if not t then
		return ''
	end
	local seconds = math.max(0, time() - t)
	if seconds < 60 then
		return L['now']
	elseif seconds < 3600 then
		return string.format(L['%dm'], math.floor(seconds / 60))
	elseif seconds < 86400 then
		return string.format(L['%dh'], math.floor(seconds / 3600))
	elseif seconds < 7 * 86400 then
		return string.format(L['%dd'], math.floor(seconds / 86400))
	end
	return U.ListTime(t)
end

---Time since the newest message (a conversation's own time can be when it was opened).
---@param convo MessengerConversation
---@return string
local function LastAge(convo)
	local msg = convo.msgs and convo.msgs[#convo.msgs]
	return msg and Age(msg.t) or ''
end

---@param t number|nil
---@return string
local function Stamp(t)
	t = U.Num(t)
	if not t then
		return ''
	end
	if U.DayKey(t) == U.DayKey(time()) then
		return U.Clock(t)
	end
	return U.ListTime(t) .. ' ' .. U.Clock(t)
end

---A player's name as Messenger shows it in a list: their nickname, or the short name.
---@param full string
---@return string
local function ShortPerson(full)
	return M:GetAlias(Store.CharKey(full)) or U.ShortName(full)
end

---The latest line of a conversation on one line, without markup.
---@param convo MessengerConversation
---@return string text, number[] color
local function LatestLine(convo)
	local msg = convo.msgs and convo.msgs[#convo.msgs]
	if not msg then
		return L['No messages yet'], T.color.faint
	end
	local raw = U.Str(msg.x)
	if not raw then
		return L['Message not available yet'], T.color.faint
	end
	local text = Flatten(raw)
	local sender = U.Str(msg.s)
	if msg.o and not msg.sys then
		text = string.format(L['You: %s'], text)
	elseif sender and not msg.sys then
		text = ShortPerson(sender) .. (msg.em and ' ' or ': ') .. text
	end
	text = Restore(Shorten(text, LINE_CHARS))
	if M.settings.emoji then
		text = M.Emoji:Render(text)
	end
	local unread = (U.Num(convo.unread) or 0) > 0
	return text, unread and T.color.text or T.color.muted
end

---Unread count as Messenger's list badge shows it: in the chat's color when it alerts, grey when not.
---Only alerting counts add up to the totals, like the icon's own number.
---@param convo MessengerConversation
---@return number alertingCount, string text
local function Unread(convo)
	local level = M:AlertLevel(convo)
	local unread = U.Num(convo.unread) or 0
	local mentions = U.Num(convo.mentionUnread) or 0
	local count, alerting = unread, level == 'all'
	if level == 'mentions' and mentions > 0 then
		count, alerting = mentions, true
	end
	if count <= 0 then
		return 0, ''
	end
	if alerting then
		local r, g, b = T.KindColor(convo)
		return count, Paint(tostring(count), r, g, b)
	end
	return 0, PaintToken(tostring(count), T.color.faint)
end

---@param convo MessengerConversation
---@return string
local function Title(convo)
	return U.Str(M:GetTitle(convo)) or U.Str(convo.name) or convo.key
end

---Name color: class color for people when known, the chat's color for channels.
---@param convo MessengerConversation
---@return number r, number g, number b
local function TitleColor(convo)
	if Store.IsRoomKey(convo.key) then
		return T.KindColor(convo)
	end
	local presence = M.Contacts:GetPresence(convo)
	return T.NameColor(U.Str(presence.class) or U.Str(convo.class))
end

---@param convo MessengerConversation
---@return string
local function NameCell(convo)
	local kr, kg, kb = T.KindColor(convo)
	local parts = { Icon('dot', kr, kg, kb), ' ', Paint(Title(convo), TitleColor(convo)) }
	local faint = T.color.faint
	if convo.kind == 'BN_WHISPER' then
		parts[#parts + 1] = ' ' .. PaintToken(L['Battle.net'], faint)
	end
	if convo.pinned then
		parts[#parts + 1] = ' ' .. Icon('pin', faint[1], faint[2], faint[3])
	end
	local level = M:AlertLevel(convo)
	if level ~= 'all' then
		parts[#parts + 1] = ' ' .. Icon(level == 'none' and 'bellOff' or 'at', faint[1], faint[2], faint[3])
	end
	return table.concat(parts)
end

---Who wrote a message, and in which color.
---@param convo MessengerConversation
---@param msg table
---@return string name, number r, number g, number b
local function Sender(convo, msg)
	if msg.o then
		local me = UnitName('player')
		local name = U.Str(msg.a) or me
		if name == me then
			local _, classFile = UnitClass('player')
			local r, g, b = T.NameColor(classFile)
			return L['You'], r, g, b
		end
		local c = T.color.muted
		return name, c[1], c[2], c[3]
	end
	local sender = U.Str(msg.s)
	if sender then
		local r, g, b = T.NameColor(U.Str(msg.cl))
		return M:PersonLabel(sender), r, g, b
	end
	local r, g, b = TitleColor(convo)
	return Title(convo), r, g, b
end

---A message's text for the second card, with links, raid icons and emoji like the message log.
---@param msg table
---@return string|nil
local function MessageText(msg)
	local raw = U.Str(msg.x)
	if not raw then
		return nil
	end
	local text
	if #raw > LONG_MESSAGE then
		text = Restore(Shorten(Flatten(raw), LONG_CHARS))
	else
		text = U.RaidIcons(U.Linkify(raw))
	end
	if M.settings.emoji then
		text = M.Emoji:Render(text)
	end
	if msg.gm then
		text = GM_ICON .. text
	end
	return text
end

----------------------------------------------------------------------------------------------------
-- Placement
----------------------------------------------------------------------------------------------------

---Puts a frame beside the main card, level with a line of it, on whichever side has room.
---@param frame Frame
---@param main Frame
---@param region Frame
local function PlaceBeside(frame, main, region)
	local mainTop, regionTop, mainRight = main:GetTop(), region:GetTop(), main:GetRight()
	if not (mainTop and regionTop and mainRight) then
		frame:ClearAllPoints()
		frame:SetPoint('TOPLEFT', main, 'TOPRIGHT', 0, 0)
		return
	end
	local mainScale, scale = main:GetEffectiveScale(), frame:GetEffectiveScale()
	local y = (regionTop - mainTop) * mainScale / scale
	local screenRight = UIParent:GetRight() * UIParent:GetEffectiveScale()
	frame:ClearAllPoints()
	if mainRight * mainScale + frame:GetWidth() * scale > screenRight then
		frame:SetPoint('TOPRIGHT', main, 'TOPLEFT', 0, y)
	else
		frame:SetPoint('TOPLEFT', main, 'TOPRIGHT', 0, y)
	end
end

---Where a tooltip goes next to an anchor: away from the nearest screen edges.
---@param anchor Frame
---@return string point, Frame relativeTo, string relativePoint
local function SmartPoint(anchor)
	local x, y = anchor:GetCenter()
	if not x or not y then
		return 'TOPLEFT', anchor, 'BOTTOMLEFT'
	end
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	local horizontal = (x > width * 2 / 3) and 'RIGHT' or (x < width / 3) and 'LEFT' or ''
	local vertical = (y > height / 2) and 'TOP' or 'BOTTOM'
	return vertical .. horizontal, anchor, (vertical == 'TOP' and 'BOTTOM' or 'TOP') .. horizontal
end

----------------------------------------------------------------------------------------------------
-- Row helpers
----------------------------------------------------------------------------------------------------

---Adds a row whose first cell spans every column.
---@param tooltip table
---@param text string
---@param maxWidth? number Wrap the text at this width
---@param color? number[] Text color, for text that carries its own color codes (links)
---@return table row, table cell
local function AddWideRow(tooltip, text, maxWidth, color)
	local row = tooltip:AddRow()
	local cell = row:GetCell(1)
	cell:SetColSpan(0)
	if maxWidth then
		cell:SetMaxWidth(maxWidth)
	end
	cell:SetText(text)
	if color then
		cell:SetTextColor(color[1], color[2], color[3])
	end
	return row, cell
end

---Gives every cell of a row the same scripts. The conversation key travels as the script
---argument, so handlers get (cell, key, ...) whatever the library passes in between.
---@param row table
---@param key any
---@param handlers table<string, function>
local function SetRowScripts(row, key, handlers)
	for index = 1, COLUMNS do
		local cell = row.Cells[index]
		if cell then
			for scriptType, handler in pairs(handlers) do
				cell:SetScript(scriptType, handler, key)
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------------------------------------

---True when Messenger's drop-down menu is open on one of this card's lines.
---@return boolean
local function MenuOpen()
	local dropdown = _G.MessengerDropDown
	return dropdown ~= nil and dropdown:IsShown() and Tip.menuOwner ~= nil and W.LastMenuOwner() == Tip.menuOwner
end

-- The card stays open while the mouse is over the broker icon or the card's drop-down menu
local keepOpen = {
	IsMouseOver = function()
		if Tip.anchor and Tip.anchor:IsMouseOver() then
			return true
		end
		return MenuOpen()
	end,
}

---Hides the card, then runs an action.
---@param fn function
---@return function
local function Closing(fn)
	return function()
		Tip:Hide()
		fn()
	end
end

---@param cell Frame
---@param key string
local function OpenLineMenu(cell, key)
	local convo = Store:Get(key)
	local main = Tip.tooltip
	if not convo or not main then
		return
	end
	Tip:ReleasePreview()
	local items = {
		{
			text = Store.IsRoomKey(key) and L['Write a message'] or L['Reply'],
			onClick = Closing(function()
				M:Open(key, true)
			end),
		},
	}
	if (U.Num(convo.unread) or 0) > 0 then
		table.insert(items, {
			text = L['Mark as read'],
			onClick = function()
				Store:MarkRead(key)
			end,
		})
	end
	table.insert(items, {
		text = L['Open in its own window'],
		onClick = Closing(function()
			M:PopOut(key)
		end),
	})
	table.insert(items, {
		text = convo.pinned and L['Unpin'] or L['Pin to top'],
		onClick = function()
			Store:SetFlag(key, 'pinned', not convo.pinned)
		end,
	})
	W.OpenMenu(cell, items)
	local dropdown = _G.MessengerDropDown
	if dropdown and dropdown:IsShown() then
		Tip.menuOwner = cell
		PlaceBeside(dropdown, main, cell)
	end
end

local function OnLineClick(cell, key, button)
	if not M.enabled or not Store:Get(key) then
		return
	end
	if button == 'RightButton' then
		OpenLineMenu(cell, key)
		return
	end
	local popOut = button == 'MiddleButton' or IsShiftKeyDown()
	Tip:Hide()
	if popOut then
		M:PopOut(key)
	else
		M:Open(key, false)
	end
end

local function OnLineEnter(cell, key)
	if not MenuOpen() then
		Tip:ShowPreview(key, cell)
	end
end

local function OnLineLeave(_, key)
	if Tip.previewKey == key then
		Tip:ReleasePreview()
	end
end

local function OnSectionClick(_, sectionKey, button)
	if button ~= 'LeftButton' and button ~= 'RightButton' then
		return
	end
	local collapsed = M.settings.launcher.collapsed
	collapsed[sectionKey] = not collapsed[sectionKey] or nil
	Tip:Refresh()
end

local function OnMoreClick()
	Tip:Hide()
	M:Open(nil, false)
end

local function OnMarkAllClick()
	for _, convo in ipairs(Store:List('unread')) do
		Store:MarkRead(convo.key)
	end
end

local LINE_SCRIPTS = { OnMouseUp = OnLineClick, OnEnter = OnLineEnter, OnLeave = OnLineLeave }

----------------------------------------------------------------------------------------------------
-- Main card
----------------------------------------------------------------------------------------------------

---@param tooltip table
---@param convo MessengerConversation
function Tip:AddLine(tooltip, convo)
	local _, unreadText = Unread(convo)
	local preview, color = LatestLine(convo)
	local row = tooltip:AddRow(NameCell(convo), unreadText, PaintToken(preview, color), PaintToken(LastAge(convo), T.color.faint))
	SetRowScripts(row, convo.key, LINE_SCRIPTS)
	self.rows[convo.key] = row
	self.lineCount = self.lineCount + 1
end

---@param tooltip table
---@param section table
---@param list MessengerConversation[]
---@return boolean collapsed
function Tip:AddSection(tooltip, section, list)
	local collapsed = M.settings.launcher.collapsed[section.key] == true
	local unread = 0
	for _, convo in ipairs(list) do
		unread = unread + Unread(convo)
	end
	local faint = T.color.faint
	local label = PaintToken(collapsed and '+' or '-', faint) .. '  ' .. PaintToken(section.label, T.color.text)
	local count
	if unread > 0 then
		count = PaintToken(string.format(L['%d unread'], unread), T.color.text)
	else
		count = PaintToken(tostring(#list), faint)
	end
	local row = tooltip:AddRow()
	local cell = row:GetCell(1)
	cell:SetColSpan(COLUMNS - 1)
	cell:SetText(label)
	row:GetCell(COLUMNS):SetText(count)
	local raised = T.color.raised
	row:SetColor(raised[1], raised[2], raised[3], raised[4])
	SetRowScripts(row, section.key, { OnMouseUp = OnSectionClick })
	return collapsed
end

---@param tooltip table
function Tip:Build(tooltip)
	wipe(self.rows)
	self.lineCount = 0
	local faint, muted = T.color.faint, T.color.muted
	local enabled = M.enabled and M.db ~= nil

	local total = enabled and Store:TotalUnread() or 0
	local head = tooltip:AddHeadingRow()
	local title = head:GetCell(1)
	title:SetColSpan(COLUMNS - 1)
	title:SetText(L['Messenger'])
	if total > 0 then
		head:GetCell(COLUMNS):SetText(PaintToken(string.format(L['%d unread'], total), T.color.text))
	else
		head:GetCell(COLUMNS):SetText(PaintToken(L['All caught up'], faint))
	end

	if not enabled then
		AddWideRow(tooltip, PaintToken(L['Messenger is turned off.'], muted))
	else
		local convos = Store:List('all')
		if #convos == 0 then
			tooltip:AddSeparator(1, 1, 1, 1, 0.12)
			AddWideRow(tooltip, PaintToken(L['No conversations yet.'], T.color.text))
			AddWideRow(tooltip, PaintToken(L['Whispers you get will show up here.'], muted))
		else
			local groups = { people = {}, rooms = {} }
			for _, convo in ipairs(convos) do
				local list = Store.IsRoomKey(convo.key) and groups.rooms or groups.people
				list[#list + 1] = convo
			end
			for _, section in ipairs(SECTIONS) do
				local list = groups[section.key]
				if #list > 0 then
					tooltip:AddSeparator(1, 1, 1, 1, 0.12)
					if not self:AddSection(tooltip, section, list) then
						for i = 1, math.min(#list, MAX_LINES) do
							self:AddLine(tooltip, list[i])
						end
						if #list > MAX_LINES then
							local row = AddWideRow(tooltip, PaintToken(string.format(L['%d more in Messenger'], #list - MAX_LINES), muted))
							SetRowScripts(row, section.key, { OnMouseUp = OnMoreClick })
						end
					end
				end
			end
			if total > 0 then
				tooltip:AddSeparator(1, 1, 1, 1, 0.12)
				local row = AddWideRow(tooltip, PaintToken(L['Mark all as read'], T.color.text))
				SetRowScripts(row, 'all', { OnMouseUp = OnMarkAllClick })
			end
		end
	end

	tooltip:AddSeparator(1, 1, 1, 1, 0.12)
	local function Hint(action, result)
		return PaintToken(action, muted) .. ' ' .. PaintToken(result, faint)
	end
	if self.lineCount > 0 then
		AddWideRow(tooltip, Hint(L['Click a chat:'], L['open it']) .. '   ' .. Hint(L['Shift-click:'], L['own window']) .. '   ' .. Hint(L['Right-click:'], L['more']))
	end
	local key = M:GetToggleKeyText()
	local iconHints = Hint(L['Click the icon:'], L['open Messenger']) .. '   ' .. Hint(L['Right-click the icon:'], L['settings'])
	if key then
		iconHints = iconHints .. '   ' .. Hint(key .. ':', L['open or close'])
	end
	AddWideRow(tooltip, iconHints)
end

local function OnMainHide(tooltip)
	Tip:ReleasePreview()
	if MenuOpen() then
		W.CloseMenu()
	end
	Tip.menuOwner = nil
	wipe(Tip.rows)
	if Tip.tooltip == tooltip then
		Tip.tooltip = nil
	end
	local lib = QTip()
	if lib and tooltip:IsAcquiredBy(MAIN_KEY) then
		lib:ReleaseTooltip(tooltip)
	end
end

---@return boolean
function Tip:IsShown()
	local tooltip = self.tooltip
	return tooltip ~= nil and tooltip:IsAcquiredBy(MAIN_KEY) and tooltip:IsShown()
end

---Shows the card for the broker icon (or a plain game tooltip without LibQTip-2.0).
---@param anchor Frame
function Tip:Show(anchor)
	local lib = QTip()
	if not lib or not anchor then
		self:ShowPlain(anchor)
		return
	end
	self.anchor = anchor
	local tooltip = self.tooltip
	if not (tooltip and tooltip:IsAcquiredBy(MAIN_KEY)) then
		tooltip = lib:AcquireTooltip(MAIN_KEY, COLUMNS, 'LEFT', 'RIGHT', 'LEFT', 'RIGHT')
		tooltip:SetScript('OnHide', OnMainHide)
		self.tooltip = tooltip
	end
	self:ReleasePreview()
	tooltip:Clear()
	self:Build(tooltip)
	tooltip:SetMaxHeight(UIParent:GetHeight() * 0.6)
	tooltip:SmartAnchorTo(anchor)
	tooltip:SetAutoHideDelay(HIDE_DELAY, keepOpen)
	tooltip:UpdateLayout()
	tooltip:Show()
end

---Rebuilds an open card in place after conversations change, keeping the second card up.
function Tip:Refresh()
	if not self:IsShown() or not self.anchor then
		return
	end
	local hovered = self.previewKey
	self:Show(self.anchor)
	local row = hovered and self.rows[hovered]
	if row and row:IsMouseOver() then
		self:ShowPreview(hovered, row)
	end
end

function Tip:Hide()
	local lib = QTip()
	local tooltip = self.tooltip
	if lib and tooltip and tooltip:IsAcquiredBy(MAIN_KEY) then
		lib:ReleaseTooltip(tooltip)
	end
	self.tooltip = nil
	self:ReleasePreview()
	if self.plainShown then
		self.plainShown = false
		GameTooltip:Hide()
	end
end

----------------------------------------------------------------------------------------------------
-- Second card: the last messages of one conversation
----------------------------------------------------------------------------------------------------

---@param preview table
---@param convo MessengerConversation
local function BuildPreview(preview, convo)
	local faint, muted, textColor = T.color.faint, T.color.muted, T.color.text
	local head = preview:AddHeadingRow()
	local title = head:GetCell(1)
	title:SetColSpan(0)
	title:SetText(Paint(Title(convo), TitleColor(convo)))
	AddWideRow(preview, PaintToken(M.Contacts:Describe(convo), faint), PREVIEW_WIDTH)
	preview:AddSeparator(1, 1, 1, 1, 0.12)

	local msgs = convo.msgs or {}
	local count = #msgs
	if count == 0 then
		AddWideRow(preview, PaintToken(L['No messages yet'], muted))
	else
		local first = math.max(1, count - PREVIEW_MESSAGES + 1)
		if first > 1 then
			AddWideRow(preview, PaintToken(string.format(L['%d earlier messages in Messenger'], first - 1), faint))
		end
		local previous
		for i = first, count do
			local msg = msgs[i]
			local body = MessageText(msg)
			if msg.sys then
				AddWideRow(preview, body or L['Message not available yet'], PREVIEW_WIDTH, faint)
				previous = nil
			elseif msg.em then
				local name = Sender(convo, msg)
				local r, g, b = T.KindColor({ kind = 'EMOTE' })
				AddWideRow(preview, name .. ' ' .. (body or L['Message not available yet']), PREVIEW_WIDTH, { r, g, b })
				previous = nil
			else
				local newGroup = not previous
					or (previous.o and true or false) ~= (msg.o and true or false)
					or U.Str(previous.s) ~= U.Str(msg.s)
					or (U.Num(msg.t) or 0) - (U.Num(previous.t) or 0) > GROUP_WINDOW
				if newGroup then
					local name, r, g, b = Sender(convo, msg)
					preview:AddRow(Paint(name, r, g, b), PaintToken(Stamp(msg.t), faint))
				end
				if body then
					AddWideRow(preview, body, PREVIEW_WIDTH, textColor)
				else
					AddWideRow(preview, PaintToken(L['Message not available yet'], faint), PREVIEW_WIDTH)
				end
				previous = msg
			end
		end
	end
	preview:AddSeparator(1, 1, 1, 1, 0.12)
	AddWideRow(preview, PaintToken(L['Click to open this conversation'], faint))
end

---@param key string
---@param region Frame The hovered line
function Tip:ShowPreview(key, region)
	local lib = QTip()
	local main = self.tooltip
	local convo = Store:Get(key)
	if not lib or not main or not convo or not self:IsShown() then
		return
	end
	self:ReleasePreview()
	local preview = lib:AcquireTooltip(PREVIEW_KEY, 2, 'LEFT', 'RIGHT')
	self.preview = preview
	self.previewKey = key
	BuildPreview(preview, convo)
	preview:SetMaxHeight(UIParent:GetHeight() * 0.6)
	PlaceBeside(preview, main, region)
	preview:UpdateLayout()
	-- The width is known only after layout: place it again in case it has to switch sides
	PlaceBeside(preview, main, region)
	preview:SetClampedToScreen(true)
	preview:Show()
end

function Tip:ReleasePreview()
	local preview = self.preview
	self.preview = nil
	self.previewKey = nil
	local lib = QTip()
	if lib and preview and preview:IsAcquiredBy(PREVIEW_KEY) then
		lib:ReleaseTooltip(preview)
	end
end

----------------------------------------------------------------------------------------------------
-- Plain game tooltip (no LibQTip-2.0)
----------------------------------------------------------------------------------------------------

---Fills a game tooltip with the unread count, the latest conversations and click hints.
---@param tooltip GameTooltip
function Tip:FillPlain(tooltip)
	local textColor, muted, faint = T.color.text, T.color.muted, T.color.faint
	local enabled = M.enabled and M.db ~= nil
	local unread = enabled and Store:TotalUnread() or 0
	if unread > 0 then
		tooltip:AddDoubleLine(L['Messenger'], string.format(L['%d unread'], unread), 1, 1, 1, textColor[1], textColor[2], textColor[3])
	else
		tooltip:AddDoubleLine(L['Messenger'], L['No unread messages'], 1, 1, 1, muted[1], muted[2], muted[3])
	end
	if enabled then
		local convos = Store:List('all')
		for i = 1, math.min(#convos, PLAIN_LINES) do
			local convo = convos[i]
			local _, unreadText = Unread(convo)
			tooltip:AddDoubleLine(NameCell(convo) .. (unreadText ~= '' and '  ' .. unreadText or ''), LastAge(convo), 1, 1, 1, faint[1], faint[2], faint[3])
		end
		if #convos > PLAIN_LINES then
			tooltip:AddLine(string.format(L['%d more in Messenger'], #convos - PLAIN_LINES), faint[1], faint[2], faint[3])
		end
	end
	tooltip:AddLine(' ')
	local key = M:GetToggleKeyText()
	if key then
		tooltip:AddLine(string.format(L['Click or press %s to open. Right-click for settings.'], key), muted[1], muted[2], muted[3])
	else
		tooltip:AddLine(L['Click to open. Right-click for settings.'], muted[1], muted[2], muted[3])
	end
end

---@param anchor Frame|nil
function Tip:ShowPlain(anchor)
	if not anchor then
		return
	end
	GameTooltip:SetOwner(anchor, 'ANCHOR_NONE')
	GameTooltip:ClearAllPoints()
	GameTooltip:SetPoint(SmartPoint(anchor))
	self:FillPlain(GameTooltip)
	GameTooltip:Show()
	self.plainShown = true
end

----------------------------------------------------------------------------------------------------
-- Broker hooks
----------------------------------------------------------------------------------------------------

---Display addons that call OnEnter.
---@param anchor Frame
function Tip:OnEnter(anchor)
	self:Show(anchor)
end

---@param anchor Frame
function Tip:OnLeave(anchor)
	-- The rich card hides itself after a short delay, so the mouse can move onto it
	if self.plainShown and (not anchor or GameTooltip:GetOwner() == anchor) then
		self.plainShown = false
		GameTooltip:Hide()
	end
end

---Display addons that only fill in a game tooltip.
---@param tooltip GameTooltip
function Tip:OnTooltipShow(tooltip)
	self:FillPlain(tooltip)
end

---Whether the interactive card can be drawn. Displays prefer OnTooltipShow over OnEnter when a
---broker offers both, so the launcher only offers it when this is false.
---@return boolean
function Tip:IsRich()
	return QTip() ~= nil
end

function Tip:Enable()
	if self.enabled then
		return
	end
	self.enabled = true
	local function Changed()
		if Tip:IsShown() then
			M:Defer('launcher-tip', function()
				Tip:Refresh()
			end)
		end
	end
	M:On('LIST_CHANGED', Changed)
	M:On('CONTACTS_CHANGED', Changed)
	M:On('ALIASES_CHANGED', Changed)
	M:On('SETTINGS_CHANGED', Changed)
end
