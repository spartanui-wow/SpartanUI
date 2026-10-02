local _, ns = ...
local M = ns.Messenger
local T = M.Theme
local U = M.Util
local W = M.Widgets
local L = M.L

-- Alerts for new messages: toast cards, sound and taskbar flash. During combat alerts are held
-- (messages are still stored) and summarized in one card when combat ends.

---@class Messenger.Toast
local A = {}
M.UI.Toast = A

local WIDTH = 290
local HEIGHT = 56
local MAX_TOASTS = 3
local FADE = 0.4

local anchor
local active = {}
local pool = {}
local held = { count = 0 }
local lastSound = 0

----------------------------------------------------------------------------------------------------
-- Anchor
----------------------------------------------------------------------------------------------------

local function BuildAnchor()
	anchor = CreateFrame('Frame', 'MessengerToastAnchor', UIParent)
	anchor:SetSize(WIDTH, HEIGHT)
	anchor:SetFrameStrata('DIALOG')
	anchor:SetClampedToScreen(true)
	anchor:SetMovable(true)
	if anchor.SetDontSavePosition then
		anchor:SetDontSavePosition(true)
	end
	W.RestorePoint(anchor, M.settings.toastAnchor)

	anchor.preview = CreateFrame('Frame', nil, anchor)
	anchor.preview:SetAllPoints()
	T.Fill(anchor.preview, T.color.raised)
	T.Border(anchor.preview, T.color.focus)
	local text = T.Text(anchor.preview, 'body')
	text:SetPoint('CENTER')
	text:SetText(L['Drag to move message alerts'])
	anchor.preview:Hide()
	W.DragHandle(anchor.preview, anchor)
	function anchor:OnGeometryChanged()
		W.SavePoint(self, M.settings.toastAnchor)
	end
end

---Shows a draggable placeholder so the player can place alerts.
---@param unlocked boolean
function A:SetUnlocked(unlocked)
	if not anchor then
		BuildAnchor()
	end
	anchor.preview:SetShown(unlocked)
	anchor.preview:EnableMouse(unlocked)
end

---@return boolean
function A:IsUnlocked()
	return anchor ~= nil and anchor.preview:IsShown()
end

----------------------------------------------------------------------------------------------------
-- Cards
----------------------------------------------------------------------------------------------------

local function Layout()
	local y = 0
	for i = #active, 1, -1 do
		local card = active[i]
		card:ClearAllPoints()
		card:SetPoint('BOTTOMLEFT', anchor, 'BOTTOMLEFT', 0, y)
		y = y + card:GetHeight() + 6
	end
end

local function Release(card)
	for i, c in ipairs(active) do
		if c == card then
			table.remove(active, i)
			break
		end
	end
	card:Hide()
	card:SetScript('OnUpdate', nil)
	card.key = nil
	card.onClick = nil
	table.insert(pool, card)
	Layout()
end

local function BuildCard()
	local card = CreateFrame('Button', nil, anchor)
	card:SetSize(WIDTH, HEIGHT)
	card:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
	card.bg = T.Fill(card, { T.color.window[1], T.color.window[2], T.color.window[3], 0.97 })
	T.Border(card, T.color.edge)
	card.rule = T.Line(card, 'TOP')

	card.avatar = W.Avatar(card, 30)
	card.avatar:SetPoint('LEFT', 12, 0)

	card.close = W.IconButton(card, 'close', 18, nil, function()
		Release(card)
	end)
	card.close:SetPoint('TOPRIGHT', -4, -4)
	card.close:Hide()

	card.title = T.Text(card, 'name')
	card.title:SetPoint('TOPLEFT', card.avatar, 'TOPRIGHT', 10, 0)
	card.title:SetPoint('RIGHT', -26, 0)

	card.body = T.Text(card, 'meta', T.color.muted)
	card.body:SetPoint('BOTTOMLEFT', card.avatar, 'BOTTOMRIGHT', 10, 0)
	card.body:SetPoint('RIGHT', -12, 0)

	card.actions = {}

	card:SetScript('OnEnter', function(self)
		self.hovered = true
		self:SetAlpha(1)
		self.close:Show()
	end)
	card:SetScript('OnLeave', function(self)
		if not self:IsMouseOver() then
			self.hovered = false
			self.close:Hide()
		end
	end)
	card:SetScript('OnClick', function(self, button)
		local onClick = self.onClick
		if button == 'LeftButton' and onClick then
			onClick()
		end
		if not self.sticky or button == 'LeftButton' then
			Release(self)
		end
	end)
	return card
end

---@param card Button
---@param duration number|nil nil keeps the card until it is clicked
local function StartTimer(card, duration)
	card.remaining = duration
	card:SetAlpha(1)
	if not duration then
		card:SetScript('OnUpdate', nil)
		return
	end
	card:SetScript('OnUpdate', function(self, elapsed)
		if self.hovered then
			return
		end
		self.remaining = self.remaining - elapsed
		if self.remaining <= 0 then
			Release(self)
		elseif self.remaining < FADE then
			self:SetAlpha(self.remaining / FADE)
		end
	end)
end

---@param opts table { key?, convo?, title, body, r, g, b, titleColor?, onClick?, sticky?, actions? }
local function ShowCard(opts)
	if not anchor then
		BuildAnchor()
	end
	local card
	if opts.key then
		for _, c in ipairs(active) do
			if c.key == opts.key then
				card = c
				break
			end
		end
	end
	if card then
		for i, c in ipairs(active) do
			if c == card then
				table.remove(active, i)
				break
			end
		end
	else
		card = table.remove(pool) or BuildCard()
		if #active >= MAX_TOASTS then
			Release(active[1])
		end
	end
	table.insert(active, card)

	card.key = opts.key
	card.onClick = opts.onClick
	card.sticky = opts.sticky
	if opts.convo then
		card.avatar:SetConversation(opts.convo, M.Contacts:GetPresence(opts.convo))
	else
		card.avatar:SetConversation({ kind = 'WHISPER', name = 'M' }, {})
	end
	card.avatar:SetRingColor(T.color.window)
	card.rule:SetVertexColor(opts.r, opts.g, opts.b, 0.8)
	card.title:SetText(opts.title)
	local tc = opts.titleColor or T.color.text
	card.title:SetTextColor(tc[1], tc[2], tc[3])
	card.body:SetText(opts.body or '')

	for _, btn in ipairs(card.actions) do
		btn:Hide()
	end
	local width = WIDTH
	local height = HEIGHT
	if opts.actions then
		-- Cards with buttons grow to fit them, and their text wraps instead of being cut off
		local buttonsWidth = 0
		local prev
		for i, action in ipairs(opts.actions) do
			local btn = card.actions[i]
			if not btn then
				btn = W.TextButton(card, action.text, function() end)
				card.actions[i] = btn
			end
			btn:SetLabel(action.text)
			btn:SetScript('OnClick', function()
				action.onClick()
				Release(card)
			end)
			btn:ClearAllPoints()
			if prev then
				btn:SetPoint('LEFT', prev, 'RIGHT', 6, 0)
			else
				btn:SetPoint('TOPLEFT', card.body, 'BOTTOMLEFT', 0, -10)
			end
			btn:Show()
			buttonsWidth = buttonsWidth + btn:GetWidth() + (prev and 6 or 0)
			prev = btn
		end
		width = math.max(WIDTH, 52 + buttonsWidth + 14)
		local textWidth = width - 52 - 14

		card.avatar:ClearAllPoints()
		card.avatar:SetPoint('TOPLEFT', 12, -12)
		card.title:ClearAllPoints()
		card.title:SetPoint('TOPLEFT', card.avatar, 'TOPRIGHT', 10, 0)
		card.title:SetWidth(textWidth - 14)
		card.title:SetWordWrap(true)
		card.body:SetWordWrap(true)
		card.body:ClearAllPoints()
		card.body:SetPoint('TOPLEFT', card.title, 'BOTTOMLEFT', 0, -4)
		card.body:SetWidth(textWidth)
		height = 12 + card.title:GetStringHeight() + 4 + card.body:GetStringHeight() + 10 + 24 + 12
	else
		card.title:SetWordWrap(false)
		card.title:SetWidth(0)
		card.title:ClearAllPoints()
		card.title:SetPoint('TOPLEFT', card.avatar, 'TOPRIGHT', 10, 0)
		card.title:SetPoint('RIGHT', -26, 0)
		card.body:SetWordWrap(false)
		card.body:SetWidth(0)
		card.body:ClearAllPoints()
		card.body:SetPoint('BOTTOMLEFT', card.avatar, 'BOTTOMRIGHT', 10, 0)
		card.body:SetPoint('RIGHT', -12, 0)
		card.avatar:ClearAllPoints()
		card.avatar:SetPoint('LEFT', 12, 0)
	end
	card:SetWidth(width)
	card:SetHeight(height)
	card:Show()
	StartTimer(card, not opts.sticky and (opts.duration or M.settings.alerts.toastDuration) or nil)
	Layout()
end

----------------------------------------------------------------------------------------------------
-- Alert rules
----------------------------------------------------------------------------------------------------

local publicAlertAt = {}

---@param key string
---@return boolean
local function HasCard(key)
	for _, card in ipairs(active) do
		if card.key == key and card:IsShown() then
			return true
		end
	end
	return false
end

local function PlayTell()
	if GetTime() - lastSound < 1 then
		return
	end
	lastSound = GetTime()
	local sound = SOUNDKIT and SOUNDKIT.TELL_MESSAGE or 3081
	PlaySound(sound, 'Master')
end

---@param key string
---@param msg table
---@param kind MessengerKind
local function OnIncoming(key, msg, kind)
	local convo = M.Store:Get(key)
	if not convo or msg.sys then
		return
	end
	local level = M:AlertLevel(convo)
	if level == 'none' or (level == 'mentions' and not msg.mn) then
		return
	end
	local alerts = M.settings.alerts
	-- A group chat line that says the player's name alerts like a whisper
	local cfg = (msg.mn and alerts.people) or alerts[kind.group] or alerts.people
	if M:IsViewing(key) then
		return
	end

	if M.inCombat and alerts.holdInCombat then
		if cfg.sound or cfg.toast or cfg.flash then
			held.count = held.count + 1
		end
		return
	end

	-- Busy public chats pop up once, then stay quiet for a few minutes unless the player reads
	-- them; a pop-up still on screen keeps counting instead
	local quiet = false
	if kind.public and not msg.mn then
		local last = publicAlertAt[key]
		if last and GetTime() - last < (alerts.publicCooldown or 300) then
			if not HasCard(key) then
				return
			end
			quiet = true
		else
			publicAlertAt[key] = GetTime()
		end
	end

	if kind.group == 'people' and M.settings.onWhisper == 'open' and not M.UI.Deck:IsShown() then
		M:Open(key, false)
		if cfg.sound then
			PlayTell()
		end
		return
	end

	if cfg.sound and not quiet then
		PlayTell()
	end
	if cfg.flash and not quiet and FlashClientIcon then
		FlashClientIcon()
	end
	if cfg.toast then
		local r, g, b = T.KindColor(convo)
		local presence = M.Contacts:GetPresence(convo)
		local title = M:GetTitle(convo)
		local titleColor
		if M.Store.IsRoomKey(key) then
			titleColor = { r, g, b }
		else
			titleColor = { T.NameColor(presence.class or convo.class) }
		end
		if (convo.unread or 0) > 1 then
			title = string.format('%s  (%d)', title, convo.unread)
		end
		local body = M.Emoji:Render(U.Plain(msg.x or ''))
		if msg.s then
			body = U.ShortName(msg.s) .. ': ' .. body
		end
		ShowCard({
			key = key,
			convo = convo,
			title = title,
			titleColor = titleColor,
			body = body,
			r = r,
			g = g,
			b = b,
			onClick = function()
				M:Open(key, true)
			end,
		})
	end
end

local function OnCombat(inCombat)
	if inCombat or held.count == 0 then
		return
	end
	local count = held.count
	held.count = 0
	local convo = M.Store:NextUnread()
	if not convo then
		return
	end
	PlayTell()
	local c = T.color.text
	ShowCard({
		key = 'combat-summary',
		convo = convo,
		title = count == 1 and L['1 message came in during combat'] or string.format(L['%d messages came in during combat'], count),
		body = L['Click to read them.'],
		r = c[1],
		g = c[2],
		b = c[3],
		onClick = function()
			M:OpenUnread()
		end,
	})
end

---One-time notice the first time Messenger runs, with an easy way back.
function A:ShowIntro()
	if M.db.global.introShown then
		return
	end
	M.db.global.introShown = true
	local r, g, b = T.KindColor({ kind = 'WHISPER' })
	ShowCard({
		key = 'intro',
		title = L['Whispers now open in Messenger'],
		body = L['They no longer show in your main chat window, and your Reply key now answers here. You can change both any time in the settings.'],
		r = r,
		g = g,
		b = b,
		sticky = true,
		actions = {
			{
				text = L['Open Messenger'],
				onClick = function()
					M:Open(nil, false)
				end,
			},
			{
				text = L['Keep them in main chat too'],
				onClick = function()
					M.settings.routes.WHISPER.hide = false
					M.settings.routes.BN_WHISPER.hide = false
					M.settings.replyKey = false
					M:RoutesChanged()
				end,
			},
		},
	})
end

---Confirms a delete or clear with an Undo button instead of asking first.
---@param title string
function A:ShowUndo(title)
	local c = T.color.muted
	ShowCard({
		key = 'undo',
		title = title,
		body = L['Changed your mind?'],
		r = c[1],
		g = c[2],
		b = c[3],
		duration = 10,
		actions = {
			{
				text = L['Undo'],
				onClick = function()
					local key = M.Store:Undo()
					if key then
						M:Open(key, false)
					end
				end,
			},
		},
	})
end

---A short message that something could not be done.
---@param title string
---@param body? string
function A:ShowNotice(title, body)
	local c = T.color.muted
	ShowCard({
		key = 'notice',
		title = title,
		body = body or '',
		r = c[1],
		g = c[2],
		b = c[3],
		duration = 6,
	})
end

---Whether a pop-up for this conversation is on screen.
---@param key string
---@return boolean
function A:IsShowing(key)
	return HasCard(key)
end

function A:Enable()
	if not anchor then
		BuildAnchor()
	end
	if not self.listening then
		self.listening = true
		M:On('READ', function(key)
			publicAlertAt[key] = nil
		end)
		M:On('INCOMING', function(...)
			if M.enabled then
				OnIncoming(...)
			end
		end)
		M:On('COMBAT', OnCombat)
	end
end

function A:HideAll()
	for i = #active, 1, -1 do
		Release(active[i])
	end
end
