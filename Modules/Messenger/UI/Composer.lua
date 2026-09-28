local _, ns = ...
local M = ns.Messenger
local T = M.Theme
local U = M.Util
local W = M.Widgets
local L = M.L

-- The composer wears the chat color of wherever the text will go. Switching conversations eases
-- the label, rule and send icon from the old color to the new one, so a change of destination is
-- noticed before Enter is pressed.

---@class Messenger.Composer
local Cmp = {}
M.Composer = Cmp

local EASE_TIME = 0.15
local HEIGHT = 36

---@class MessengerComposer : Frame
local Composer = {}

local drafts = {}
local composers = setmetatable({}, { __mode = 'k' })

---@return EditBox|nil
function Cmp.Focused()
	for composer in pairs(composers) do
		if composer.edit:HasFocus() then
			return composer.edit
		end
	end
	return nil
end

---@param parent Frame
---@return MessengerComposer
function Cmp.Create(parent)
	local c = CreateFrame('Frame', nil, parent)
	Mixin(c, Composer)
	c:SetHeight(HEIGHT)
	composers[c] = true

	c.bg = T.Fill(c, T.color.header)
	c.rule = T.Line(c, 'TOP', { 1, 1, 1, 0.3 })

	c.to = T.Text(c, 'name')
	c.to:SetPoint('LEFT', 12, 0)

	c.send = W.IconButton(c, 'send', 24, L['Send (Enter)'], function()
		c:Submit()
	end)
	c.send:SetPoint('RIGHT', -6, 0)

	c.emoji = W.IconButton(c, 'bubble', 24, L['Emoji'], function(btn)
		M.UI.EmojiPicker:Toggle(btn, c.edit)
	end)
	c.emoji:SetPoint('RIGHT', c.send, 'LEFT', -2, 0)

	c.counter = T.Text(c, 'meta', T.color.faint)
	c.counter:SetPoint('RIGHT', c.emoji, 'LEFT', -6, 0)

	local edit = CreateFrame('EditBox', nil, c)
	edit:SetPoint('LEFT', c.to, 'RIGHT', 10, 0)
	edit:SetPoint('RIGHT', c.counter, 'LEFT', -8, 0)
	edit:SetHeight(HEIGHT - 8)
	edit:SetAutoFocus(false)
	edit:SetAltArrowKeyMode(false)
	edit:SetHistoryLines(30)
	edit:SetMaxBytes(1600)
	edit:SetTextInsets(0, 0, 0, 0)
	edit:SetFontObject(ChatFontNormal)
	c.edit = edit

	c.placeholder = T.Text(c, 'body', T.color.faint)
	c.placeholder:SetPoint('LEFT', edit, 'LEFT', 0, 0)
	c.placeholder:SetPoint('RIGHT', edit, 'RIGHT', 0, 0)

	c:ApplyFont()
	M:On('FONTS_CHANGED', function()
		c:ApplyFont()
	end)

	edit:SetScript('OnEnterPressed', function()
		c:Submit()
	end)
	edit:SetScript('OnEscapePressed', function(self)
		self:ClearFocus()
	end)
	edit:SetScript('OnTabPressed', function()
		if c.onTab then
			c.onTab()
		end
	end)
	edit:SetScript('OnTextChanged', function()
		c:UpdateState()
	end)
	edit:SetScript('OnEditFocusGained', function()
		c:UpdateState()
	end)
	edit:SetScript('OnEditFocusLost', function()
		c:UpdateState()
	end)

	c:SetScript('OnMouseDown', function()
		if edit:IsEnabled() then
			edit:SetFocus()
		end
	end)

	c.color = { T.color.muted[1], T.color.muted[2], T.color.muted[3] }
	M:On('RESTRICTION_CHANGED', function()
		c:UpdateState()
	end)
	M:On('CONTACTS_CHANGED', function()
		c:UpdateState()
	end)
	M:On('SETTINGS_CHANGED', function()
		c:UpdateState()
	end)
	return c
end

function Composer:ApplyFont()
	local face = ChatFontNormal:GetFont() or STANDARD_TEXT_FONT
	self.edit:SetFont(face, T.BaseSize(), '')
	self.edit:SetShadowColor(0, 0, 0, 0.85)
	self.edit:SetShadowOffset(1, -1)
	self.edit:SetTextColor(T.color.text[1], T.color.text[2], T.color.text[3])
end

---Blends the destination color in over EASE_TIME.
---@param r number
---@param g number
---@param b number
function Composer:EaseColor(r, g, b)
	local from = { self.color[1], self.color[2], self.color[3] }
	local elapsed = 0
	self.targetColor = { r, g, b }
	self:SetScript('OnUpdate', function(frame, dt)
		elapsed = elapsed + dt
		local p = math.min(1, elapsed / EASE_TIME)
		p = 1 - (1 - p) * (1 - p)
		local cr = from[1] + (r - from[1]) * p
		local cg = from[2] + (g - from[2]) * p
		local cb = from[3] + (b - from[3]) * p
		frame:PaintColor(cr, cg, cb)
		if p >= 1 then
			frame:SetScript('OnUpdate', nil)
		end
	end)
end

function Composer:PaintColor(r, g, b)
	self.color[1], self.color[2], self.color[3] = r, g, b
	self.to:SetTextColor(r, g, b)
	self.rule:SetVertexColor(r, g, b, self.edit:HasFocus() and 0.9 or 0.45)
	self.send:SetTint({ r, g, b, 1 })
end

---@param key string|nil
function Composer:SetConversation(key)
	if self.key then
		drafts[self.key] = self.edit:GetText()
	end
	self.key = key
	local convo = key and M.Store:Get(key)
	self.edit:ClearHistory()
	if key then
		for _, line in ipairs(M.Sender:History(key)) do
			self.edit:AddHistoryLine(line)
		end
	end
	self.edit:SetText(key and drafts[key] or '')
	if convo then
		local title = M:GetTitle(convo)
		if M.Store.IsRoomKey(key) then
			self.to:SetText(title)
		else
			self.to:SetText(string.format(L['To %s'], title))
		end
		self:EaseColor(T.KindColor(convo))
	else
		self.to:SetText('')
	end
	self:UpdateState()
end

---@return string|nil
function Composer:Problem()
	local convo = self.key and M.Store:Get(self.key)
	if not convo then
		return nil
	end
	if U.IsRestricted() then
		return L['Sending is paused during this fight.']
	end
	if M.Store.IsRoomKey(self.key) then
		return M.Sender:RoomProblem(convo)
	end
	if convo.kind == 'BN_WHISPER' and not M.Contacts:GetBNetID(convo) then
		return string.format(L['%s is not online right now.'], M:GetTitle(convo))
	end
	return nil
end

function Composer:UpdateState()
	local convo = self.key and M.Store:Get(self.key)
	local text = self.edit:GetText() or ''
	local problem = self:Problem()

	self.edit:SetEnabled(convo ~= nil and problem == nil)
	local emoji = M.Emoji:IsAvailable()
	if emoji and not self.emojiIconSet then
		self.emojiIconSet = true
		self.emoji.icon:SetTexture(M.Emoji:Path('SlightSmile-BW'))
		self.emoji.icon:SetTexCoord(0, 1, 0, 1)
	end
	self.emoji:SetShown(emoji)
	if problem then
		self.placeholder:SetText(problem)
		T.SetColor(self.placeholder, T.color.warn)
	elseif convo then
		self.placeholder:SetText(string.format(L['Message %s'], M:GetTitle(convo)))
		T.SetColor(self.placeholder, T.color.faint)
	end
	self.placeholder:SetShown(text == '' and not self.edit:HasFocus() or (problem ~= nil))

	local shownMessage = self.flash and GetTime() < self.flash
	if not shownMessage then
		self.counter:SetText('')
		if convo and text ~= '' then
			local limit = M.Sender:Limit(convo)
			local bytes = #text
			if bytes > limit then
				self.counter:SetText(string.format(L['%d messages'], M.Sender:ChunkCount(convo, text)))
				T.SetColor(self.counter, T.color.muted)
			elseif bytes > limit * 0.8 then
				self.counter:SetText(bytes .. ' / ' .. limit)
				T.SetColor(self.counter, T.color.faint)
			end
		end
	end

	if self.targetColor then
		self.rule:SetVertexColor(self.color[1], self.color[2], self.color[3], self.edit:HasFocus() and 0.9 or 0.45)
	end
end

---Shows a short notice in the counter slot.
---@param text string
function Composer:Notice(text)
	self.counter:SetText(text)
	T.SetColor(self.counter, T.color.warn)
	self.flash = GetTime() + 4
	C_Timer.After(4.1, function()
		self.flash = nil
		self:UpdateState()
	end)
end

function Composer:Submit()
	if not self.key then
		return
	end
	local text = self.edit:GetText() or ''
	if U.Trim(text) == '' then
		self.edit:ClearFocus()
		return
	end
	local ok, problem = M.Sender:Send(self.key, text)
	if ok then
		self.edit:AddHistoryLine(U.Trim(text))
		self.edit:SetText('')
		drafts[self.key] = nil
	elseif problem then
		self:Notice(problem)
	end
end

function Composer:Focus()
	if self.edit:IsEnabled() then
		self.edit:SetFocus()
	end
end
