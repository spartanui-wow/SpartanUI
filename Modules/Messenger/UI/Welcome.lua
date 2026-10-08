local _, ns = ...
local M = ns.Messenger
local T = M.Theme
local W = M.Widgets
local L = M.L

-- First run: the first time the window opens on this account, two quick picks over the window.
-- How messages look (lines or bubbles), then how much room the list takes. Each choice is a card
-- with a small drawing of the result. Clicking a card applies it and moves on; the choices are
-- normal settings in the shared profile and can be changed later.

---@class Messenger.Welcome
local WL = {}
M.Welcome = WL

local CARD_GAP = 14
local CARD_MAX_W = 250
local CARD_H = 196
local PREVIEW_H = 124
local PAD = 10

-- Sample conversation drawn in the previews
local THEM = 'Thrallsdad'
local THEM_CLASS = 'SHAMAN'
local LINES = {
	{ them = true, text = 'Ready for the raid?' },
	{ them = true, text = 'Bring a flask' },
	{ them = false, text = 'On my way!' },
}

---@param parent Frame
---@param color table
---@param layer? string
---@return Texture
local function Rect(parent, color, layer)
	local tex = parent:CreateTexture(nil, layer or 'ARTWORK')
	tex:SetTexture(T.WHITE)
	tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
	return tex
end

---@param parent Frame
---@param size number
---@param r number
---@param g number
---@param b number
---@return Texture
local function Dot(parent, size, r, g, b)
	local tex = parent:CreateTexture(nil, 'ARTWORK')
	tex:SetTexture(M.mediaPath .. 'Circle')
	tex:SetSize(size, size)
	tex:SetVertexColor(r, g, b, 1)
	return tex
end

local function WhisperColor()
	return T.KindColor({ kind = 'WHISPER' })
end

----------------------------------------------------------------------------------------------------
-- Previews (each returns a function that lays it out for the preview's current size)
----------------------------------------------------------------------------------------------------

---Names over each group, like the normal chat.
---@param box Frame
local function PreviewLines(box)
	local nr, ng, nb = T.NameColor(THEM_CLASS)
	local _, myClass = UnitClass('player')
	local mr, mg, mb = T.NameColor(myClass)
	local parts = {}
	local function Line(role, text, color)
		local fs = T.Text(box, role, color)
		fs:SetText(text)
		parts[#parts + 1] = fs
		return fs
	end
	local name1 = Line('meta', THEM)
	name1:SetTextColor(nr, ng, nb)
	local time1 = Line('small', '9:41', T.color.faint)
	local a = Line('meta', LINES[1].text)
	local b = Line('meta', LINES[2].text)
	local name2 = Line('meta', UnitName('player') or L['You'])
	name2:SetTextColor(mr, mg, mb)
	local time2 = Line('small', '9:42', T.color.faint)
	local c = Line('meta', LINES[3].text)
	return function()
		local step = T.BaseSize() + 2
		name1:ClearAllPoints()
		name1:SetPoint('TOPLEFT', PAD, -PAD)
		time1:ClearAllPoints()
		time1:SetPoint('LEFT', name1, 'RIGHT', 6, 0)
		a:ClearAllPoints()
		a:SetPoint('TOPLEFT', name1, 'BOTTOMLEFT', 0, -3)
		b:ClearAllPoints()
		b:SetPoint('TOPLEFT', a, 'BOTTOMLEFT', 0, -2)
		name2:ClearAllPoints()
		name2:SetPoint('TOPLEFT', b, 'BOTTOMLEFT', 0, -(step * 0.6))
		time2:ClearAllPoints()
		time2:SetPoint('LEFT', name2, 'RIGHT', 6, 0)
		c:ClearAllPoints()
		c:SetPoint('TOPLEFT', name2, 'BOTTOMLEFT', 0, -3)
	end
end

---Phone style: theirs grey on the left, yours in the chat's color on the right.
---@param box Frame
local function PreviewBubbles(box)
	local rows = {}
	for i, line in ipairs(LINES) do
		local bubble = M.Bubble.Create(box)
		local text = T.Text(box, 'meta')
		text:SetText(line.text)
		rows[i] = { bubble = bubble, text = text, them = line.them }
	end
	local time = T.Text(box, 'small', T.color.faint)
	time:SetText('9:42')
	return function()
		local width = box:GetWidth()
		local y = -PAD
		for i, row in ipairs(rows) do
			local textW = math.max(row.text:GetUnboundedStringWidth(), 30)
			local h = math.floor(T.BaseSize() + 8)
			local w = math.min(textW + 16, width - PAD * 2)
			local big = math.floor(h / 2)
			local first = i == 1 or rows[i - 1].them ~= row.them
			local last = i == #rows or rows[i + 1].them ~= row.them
			local upper, lower = first and big or 3, last and big or 3
			local shape = row.bubble.box
			shape:ClearAllPoints()
			if row.them then
				shape:SetPoint('TOPLEFT', box, 'TOPLEFT', PAD, y)
				row.bubble:Layout(w, h, { upper, big, lower, big })
				local c = T.color.bubble
				row.bubble:SetColor(c[1], c[2], c[3], 1)
			else
				shape:SetPoint('TOPRIGHT', box, 'TOPRIGHT', -PAD, y)
				row.bubble:Layout(w, h, { big, upper, big, lower })
				row.bubble:SetColor(T.BubbleFill(WhisperColor()))
			end
			row.text:ClearAllPoints()
			row.text:SetPoint('LEFT', shape, 'LEFT', 8, 0)
			y = y - h - (last and 8 or 2)
		end
		time:ClearAllPoints()
		time:SetPoint('TOPRIGHT', rows[#rows].bubble.box, 'BOTTOMRIGHT', -4, -3)
	end
end

local LIST_SHARE = { full = 0.44, slim = 0.36, icons = 0.15 }

---A tiny Messenger window with the list at the chosen size.
---@param box Frame
---@param mode 'full'|'slim'|'icons'
local function PreviewList(box, mode)
	local list = CreateFrame('Frame', nil, box)
	list:SetPoint('TOPLEFT')
	list:SetPoint('BOTTOMLEFT')
	local listBg = Rect(list, T.color.list, 'BACKGROUND')
	listBg:SetAllPoints()
	local divider = Rect(box, T.color.line)
	divider:SetPoint('TOPLEFT', list, 'TOPRIGHT')
	divider:SetPoint('BOTTOMLEFT', list, 'BOTTOMRIGHT')
	divider:SetWidth(1)

	local wr, wg, wb = WhisperColor()
	local gr, gg, gb = T.KindColor({ kind = 'GUILD' })
	local people = {
		{ name = THEM, class = THEM_CLASS, text = LINES[1].text, unread = true },
		{ name = L['Guild'], color = { gr, gg, gb }, text = L['Who needs a summon?'] },
		{ name = 'Mirabel', class = 'PRIEST', text = L['Thanks for the help!'] },
		{ name = 'Korgath', class = 'WARRIOR', text = L['See you tomorrow'] },
		{ name = L['Party'], color = { T.KindColor({ kind = 'PARTY' }) }, text = L['Pull in 5'] },
	}
	local rows = {}
	for i, person in ipairs(people) do
		local r, g, b
		if person.class then
			r, g, b = T.NameColor(person.class)
		else
			r, g, b = person.color[1], person.color[2], person.color[3]
		end
		local row = { dot = Dot(list, 10, r, g, b) }
		if mode ~= 'icons' then
			row.name = T.Text(list, 'small')
			row.name:SetText(person.name)
			if person.class then
				row.name:SetTextColor(T.color.text[1], T.color.text[2], T.color.text[3])
			else
				row.name:SetTextColor(r, g, b)
			end
			row.text = T.Text(list, 'small', T.color.faint)
			row.text:SetText(person.text)
		end
		if person.unread then
			row.chip = Dot(list, 5, wr, wg, wb)
		end
		rows[i] = row
	end

	-- The open conversation, as soft bars
	local bars = {}
	for i = 1, 3 do
		local bar = Rect(box, i == 3 and { T.BubbleFill(wr, wg, wb) } or T.color.bubble)
		bars[i] = bar
	end

	return function()
		local width, height = box:GetWidth(), box:GetHeight()
		local listW = math.floor(width * LIST_SHARE[mode])
		list:SetWidth(listW)
		local rowH = mode == 'full' and 26 or (mode == 'slim' and 15 or 20)
		local y = -6
		for _, row in ipairs(rows) do
			local fits = -y + rowH <= height
			row.dot:SetShown(fits)
			if row.chip then
				row.chip:SetShown(fits)
			end
			if row.name then
				row.name:SetShown(fits)
				row.text:SetShown(fits)
			end
			if fits then
				row.dot:ClearAllPoints()
				if mode == 'icons' then
					row.dot:SetSize(12, 12)
					row.dot:SetPoint('TOP', list, 'TOP', 0, y - 2)
				elseif mode == 'full' then
					row.dot:SetSize(14, 14)
					row.dot:SetPoint('TOPLEFT', list, 'TOPLEFT', 6, y - 3)
					row.name:ClearAllPoints()
					row.name:SetPoint('TOPLEFT', row.dot, 'TOPRIGHT', 5, 2)
					row.name:SetWidth(listW - 30)
					row.text:ClearAllPoints()
					row.text:SetPoint('TOPLEFT', row.name, 'BOTTOMLEFT', 0, -1)
					row.text:SetWidth(listW - 30)
				else
					row.dot:SetSize(6, 6)
					row.dot:SetPoint('TOPLEFT', list, 'TOPLEFT', 6, y - 4)
					row.name:ClearAllPoints()
					row.name:SetPoint('LEFT', row.dot, 'RIGHT', 4, 0)
					row.name:SetWidth(math.floor((listW - 16) * 0.5))
					row.text:ClearAllPoints()
					row.text:SetPoint('LEFT', row.name, 'RIGHT', 3, 0)
					row.text:SetWidth(math.floor((listW - 16) * 0.5) - 3)
				end
				if row.chip then
					row.chip:ClearAllPoints()
					row.chip:SetPoint('CENTER', row.dot, 'TOPRIGHT', -1, -1)
				end
			end
			y = y - rowH
		end
		local chatW = width - listW
		local shares = { 0.55, 0.4, 0.5 }
		local barY = -10
		for i, bar in ipairs(bars) do
			bar:ClearAllPoints()
			bar:SetSize(math.floor(chatW * shares[i]), 9)
			if i == 3 then
				bar:SetPoint('TOPRIGHT', box, 'TOPRIGHT', -8, barY)
			else
				bar:SetPoint('TOPLEFT', list, 'TOPRIGHT', 8, barY)
			end
			barY = barY - 15
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Cards
----------------------------------------------------------------------------------------------------

---@param parent Frame
---@param choice table { value, title, caption, preview = function(box) -> layout }
---@param onPick function
---@return Button
local function Card(parent, choice, onPick)
	local card = CreateFrame('Button', nil, parent)
	card.choice = choice
	card.bg = T.Fill(card, T.color.raised)
	T.Border(card, T.color.edge)

	card.box = CreateFrame('Frame', nil, card)
	card.box:SetPoint('TOPLEFT', 8, -8)
	card.box:SetPoint('TOPRIGHT', -8, -8)
	card.box:SetHeight(PREVIEW_H)
	card.box:SetClipsChildren(true)
	card.boxBg = T.Fill(card.box, T.color.window)
	card.layout = choice.preview(card.box)

	card.title = T.Text(card, 'name')
	card.title:SetPoint('TOPLEFT', card.box, 'BOTTOMLEFT', 2, -10)
	card.title:SetText(choice.title)

	card.caption = T.Text(card, 'meta', T.color.muted)
	card.caption:SetPoint('TOPLEFT', card.title, 'BOTTOMLEFT', 0, -4)
	card.caption:SetPoint('RIGHT', card, 'RIGHT', -10, 0)
	card.caption:SetWordWrap(true)
	card.caption:SetJustifyV('TOP')
	card.caption:SetText(choice.caption)

	card.check = card:CreateTexture(nil, 'OVERLAY')
	card.check:SetSize(16, 16)
	card.check:SetPoint('TOPRIGHT', card.box, 'TOPRIGHT', -4, -4)
	T.SetIcon(card.check, 'check')
	card.check:Hide()

	card:SetScript('OnEnter', function(self)
		self.bg:SetVertexColor(1, 1, 1, 0.1)
	end)
	card:SetScript('OnLeave', function(self)
		local c = T.color.raised
		self.bg:SetVertexColor(c[1], c[2], c[3], c[4])
	end)
	card:SetScript('OnClick', function()
		onPick(choice.value)
	end)
	card:SetScript('OnSizeChanged', function(self)
		self.layout()
	end)

	---Marks the card that matches the current setting.
	function card:SetCurrent(current)
		local r, g, b = WhisperColor()
		local c = current and { r, g, b, 1 } or T.color.edge
		for _, line in ipairs(self.borders) do
			line:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
		end
		self.check:SetVertexColor(r, g, b)
		self.check:SetShown(current)
	end
	return card
end

----------------------------------------------------------------------------------------------------
-- Overlay
----------------------------------------------------------------------------------------------------

local STEPS = {
	{
		heading = L['How should your messages look?'],
		body = L['Pick one. You can switch any time: right-click a message, or open the settings.'],
		current = function()
			return M.settings.messageStyle
		end,
		choices = {
			{
				value = 'lines',
				title = L['Lines'],
				caption = L['Names over each group of messages, like the normal chat.'],
				preview = PreviewLines,
			},
			{
				value = 'bubbles',
				title = L['Bubbles'],
				caption = L['Like a phone: yours on the right, theirs on the left.'],
				preview = PreviewBubbles,
			},
		},
		apply = function(value)
			M:SetMessageStyle(value)
		end,
	},
	{
		heading = L['How much room should the list take?'],
		body = L['The list on the left shows your conversations. The list button at the top left changes it later.'],
		current = function()
			return M.settings.listMode
		end,
		choices = {
			{
				value = 'full',
				title = L['Full list'],
				caption = L['Name, picture and the latest message.'],
				preview = function(box)
					return PreviewList(box, 'full')
				end,
			},
			{
				value = 'slim',
				title = L['Compact list'],
				caption = L['One short line per conversation.'],
				preview = function(box)
					return PreviewList(box, 'slim')
				end,
			},
			{
				value = 'icons',
				title = L['Pictures only'],
				caption = L['The most room for your messages.'],
				preview = function(box)
					return PreviewList(box, 'icons')
				end,
			},
		},
		apply = function(value)
			M.UI.Deck:SetListMode(value)
		end,
	},
}

---@param parent Frame The window's content area
---@return Frame
function WL.Create(parent)
	local overlay = CreateFrame('Frame', nil, parent)
	overlay:EnableMouse(true)
	overlay:EnableMouseWheel(true)
	overlay:SetScript('OnMouseWheel', function() end)
	T.Fill(overlay, T.color.window)
	overlay:Hide()

	overlay.stepText = T.Text(overlay, 'meta', T.color.faint)
	overlay.heading = T.Text(overlay, 'title')
	T.Bump(overlay.heading, 3)
	overlay.body = T.Text(overlay, 'body', T.color.muted)
	overlay.body:SetWordWrap(true)
	overlay.body:SetJustifyH('CENTER')

	overlay.back = W.TextButton(overlay, L['Back'], function()
		overlay:ShowStep(overlay.step - 1)
	end)
	overlay.skip = W.TextButton(overlay, L['Skip'], function()
		overlay:Finish()
	end)

	overlay.pages = {}
	for index, step in ipairs(STEPS) do
		local page = CreateFrame('Frame', nil, overlay)
		page.cards = {}
		for _, choice in ipairs(step.choices) do
			page.cards[#page.cards + 1] = Card(page, choice, function(value)
				step.apply(value)
				if index < #STEPS then
					overlay:ShowStep(index + 1)
				else
					overlay:Finish()
				end
			end)
		end
		page:Hide()
		overlay.pages[index] = page
	end

	function overlay:Layout()
		local width, height = self:GetWidth(), self:GetHeight()
		if width < 10 then
			return
		end
		local page = self.pages[self.step or 1]
		local count = #page.cards
		local cardW = math.min(CARD_MAX_W, math.floor((width - 40 - CARD_GAP * (count - 1)) / count))
		local rowW = cardW * count + CARD_GAP * (count - 1)
		-- Text block, cards and buttons, centered as one group
		local textH = self.heading:GetStringHeight() + self.body:GetStringHeight() + self.stepText:GetStringHeight() + 22
		local total = textH + 20 + CARD_H + 18 + 24
		local top = math.max(14, math.floor((height - total) / 2))
		self.stepText:ClearAllPoints()
		self.stepText:SetPoint('TOP', self, 'TOP', 0, -top)
		self.heading:ClearAllPoints()
		self.heading:SetPoint('TOP', self.stepText, 'BOTTOM', 0, -8)
		self.body:ClearAllPoints()
		self.body:SetPoint('TOP', self.heading, 'BOTTOM', 0, -8)
		self.body:SetWidth(math.min(rowW, 460))
		page:ClearAllPoints()
		page:SetPoint('TOP', self.body, 'BOTTOM', 0, -20)
		page:SetSize(rowW, CARD_H)
		for i, card in ipairs(page.cards) do
			card:ClearAllPoints()
			card:SetPoint('TOPLEFT', page, 'TOPLEFT', (i - 1) * (cardW + CARD_GAP), 0)
			card:SetSize(cardW, CARD_H)
			card.layout()
		end
		self.skip:ClearAllPoints()
		self.skip:SetPoint('TOPRIGHT', page, 'BOTTOMRIGHT', 0, -18)
		self.back:ClearAllPoints()
		self.back:SetPoint('TOPLEFT', page, 'BOTTOMLEFT', 0, -18)
	end

	---@param index number
	function overlay:ShowStep(index)
		index = math.max(1, math.min(#STEPS, index))
		self.step = index
		local step = STEPS[index]
		for i, page in ipairs(self.pages) do
			page:SetShown(i == index)
		end
		self.stepText:SetText(string.format(L['Step %d of %d'], index, #STEPS))
		self.heading:SetText(step.heading)
		self.body:SetText(step.body)
		local current = step.current()
		for _, card in ipairs(self.pages[index].cards) do
			card:SetCurrent(card.choice.value == current)
		end
		self.back:SetShown(index > 1)
		self.skip:SetLabel(index < #STEPS and L['Skip'] or L['Done'])
		self:Layout()
		-- Text widths can read 0 until a font has been drawn once
		C_Timer.After(0, function()
			if self:IsShown() then
				self:Layout()
			end
		end)
	end

	function overlay:Start()
		self:Show()
		self:ShowStep(1)
	end

	function overlay:Finish()
		M.db.global.styleChosen = true
		self:Hide()
		M.UI.Deck:Refresh()
	end

	overlay:SetScript('OnSizeChanged', function(self)
		if self:IsShown() then
			self:Layout()
		end
	end)
	M:On('FONTS_CHANGED', function()
		if overlay:IsShown() then
			overlay:Layout()
		end
	end)
	return overlay
end

---Whether the account still has to pick its styles.
---@return boolean
function WL.Pending()
	return M.db ~= nil and not M.db.global.styleChosen
end
