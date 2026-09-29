local _, ns = ...
local M = ns.Messenger
local T = M.Theme
local W = M.Widgets
local L = M.L

-- A single conversation torn off into its own small window. Position, size and whether it was
-- open are remembered per conversation (per character), so pop-outs come back after a reload.

---@class Messenger.PopOut
local P = {}
M.UI.PopOut = P

local open = {}
local pool = {}
local count = 0

---@param key string
---@return table
local function Saved(key)
	local saved = M.db.char.popouts[key]
	if not saved then
		saved = {}
		M.db.char.popouts[key] = saved
	end
	return saved
end

local function Build()
	count = count + 1
	local win = W.Window('MessengerPopOut' .. count, 260, 220)
	tinsert(UISpecialFrames, win:GetName())

	local title = CreateFrame('Frame', nil, win)
	title:SetPoint('TOPLEFT')
	title:SetPoint('TOPRIGHT')
	title:SetHeight(T.Metrics().title - 2)
	T.Fill(title, T.color.header, 'BACKGROUND', 1)
	W.DragHandle(title, win)
	win.titleBar = title

	title.avatar = W.Avatar(title, 20)
	title.avatar:SetPoint('LEFT', 10, 0)

	title.close = W.IconButton(title, 'close', 22, L['Close'], function()
		P:Close(win.key)
	end)
	title.close:SetPoint('RIGHT', -5, 0)

	title.dock = W.IconButton(title, 'dock', 22, L['Move back to the main window'], function()
		local key = win.key
		P:Close(key)
		M:Open(key, true)
	end)
	title.dock:SetPoint('RIGHT', title.close, 'LEFT', -2, 0)

	title.more = W.IconButton(title, 'more', 22, L['More'], function(btn)
		local convo = win.key and M.Store:Get(win.key)
		if convo then
			W.OpenMenu(btn, M.ChatPane.ConversationMenu(convo, 'popout'))
		end
	end)
	title.more:SetPoint('RIGHT', title.dock, 'LEFT', -2, 0)

	title.text = T.Text(title, 'name')
	title.text:SetPoint('LEFT', title.avatar, 'RIGHT', 8, 0)
	title.text:SetPoint('RIGHT', title.more, 'LEFT', -6, 0)

	-- The rule under the title carries the conversation's chat color
	title.rule = T.Line(title, 'BOTTOM')

	win.pane = M.ChatPane.Create(win, false)
	win.pane:SetPoint('TOPLEFT', title, 'BOTTOMLEFT')
	win.pane:SetPoint('BOTTOMRIGHT')

	function win:OnGeometryChanged()
		if not self.key then
			return
		end
		local saved = Saved(self.key)
		W.SavePoint(self, saved)
		saved.w, saved.h = math.floor(self:GetWidth() + 0.5), math.floor(self:GetHeight() + 0.5)
	end

	function win:UpdateTitle()
		local convo = self.key and M.Store:Get(self.key)
		if not convo then
			return
		end
		local presence = M.Contacts:GetPresence(convo)
		title.avatar:SetConversation(convo, presence)
		title.avatar:SetRingColor(T.color.header)
		title.text:SetText(M:GetTitle(convo))
		local r, g, b = T.KindColor(convo)
		if M.Store.IsRoomKey(convo.key) then
			title.text:SetTextColor(r, g, b)
		else
			title.text:SetTextColor(T.NameColor(presence.class or convo.class))
		end
		title.rule:SetVertexColor(r, g, b, 0.5)
	end

	-- Overlay mode: controls fade away until the mouse is over the window, leaving only the
	-- messages, so a pop-out can sit over the game like part of the HUD
	local chrome = { title, win.pane.composer, win.grip, win.edge, win.shadow }
	local elapsed = 0
	win:SetScript('OnUpdate', function(self, dt)
		elapsed = elapsed + dt
		if elapsed < 0.1 then
			return
		end
		elapsed = 0
		local saved = self.key and M.db.char.popouts[self.key]
		local focused = M.UI:FocusedComposer() == self.pane.composer.edit
		local menuOpen = _G.MessengerDropDown and _G.MessengerDropDown:IsShown() and _G.MessengerDropDown.owner == title.more
		local show = not (saved and saved.overlay) or self:IsMouseOver() or focused or menuOpen
		local target = show and 1 or 0
		for _, region in ipairs(chrome) do
			local alpha = region:GetAlpha()
			if math.abs(alpha - target) > 0.01 then
				region:SetAlpha(alpha + (target - alpha) * 0.5)
			else
				region:SetAlpha(target)
			end
		end
	end)

	win:SetScript('OnHide', function(self)
		-- Hidden by Escape counts as closing. Hiding the whole interface (Alt+Z) also fires OnHide,
		-- but the window itself is still marked shown then and must stay open.
		if self.key and open[self.key] == self and not self.closing and not self:IsShown() then
			P:Close(self.key)
		end
	end)
	return win
end

---@param key string
---@param focus? boolean Put the cursor in the composer (not when restoring after a reload)
function P:Open(key, focus)
	local existing = open[key]
	if existing then
		existing:Show()
		existing:Raise()
		if focus then
			existing.pane:FocusComposer()
		end
		return
	end
	local win = table.remove(pool) or Build()
	win.key = key
	win.closing = nil
	open[key] = win

	local saved = Saved(key)
	saved.open = true
	if not W.RestorePoint(win, saved) then
		win:ClearAllPoints()
		local offset = (count % 6) * 24
		win:SetPoint('CENTER', UIParent, 'CENTER', 260 + offset, -40 - offset)
	end
	win:SetSize(saved.w or 340, saved.h or 360)
	win.opacity = saved.opacity
	win:ApplyAlpha()
	win:Show()
	M.UI.Fade:Kick()
	win:Raise()
	win:UpdateTitle()
	win.pane:SetConversation(key)
	if focus then
		win.pane:FocusComposer()
	end
end

---@param key string
function P:Close(key)
	local win = open[key]
	if not win then
		return
	end
	open[key] = nil
	local saved = M.db.char.popouts[key]
	if saved then
		saved.open = nil
	end
	win.closing = true
	win:Hide()
	win.closing = nil
	win.pane:SetConversation(nil)
	win.key = nil
	table.insert(pool, win)
end

---@param key string
---@param overlay boolean
function P:SetOverlay(key, overlay)
	Saved(key).overlay = overlay or nil
end

---@param key string
---@param opacity number 0.4 to 1
function P:SetOpacity(key, opacity)
	Saved(key).opacity = opacity < 1 and opacity or nil
	local win = open[key]
	if win then
		win.opacity = Saved(key).opacity
		win:ApplyAlpha()
	end
end

---@param key string
---@return table
function P:Saved(key)
	return Saved(key)
end

---Open pop-out windows by conversation key.
---@return table<string, Frame>
function P:Windows()
	return open
end

function P:CloseAll()
	for key in pairs(open) do
		self:Close(key)
	end
end

---Reopens pop-outs that were open before the reload.
function P:Restore()
	for key, saved in pairs(M.db.char.popouts) do
		if saved.open then
			if M.Store:Get(key) then
				self:Open(key)
			else
				M.db.char.popouts[key] = nil
			end
		end
	end
end

M:On('LIST_CHANGED', function()
	M:Defer('popout-titles', function()
		for _, win in pairs(open) do
			win:UpdateTitle()
		end
	end)
end)
M:On('FONTS_CHANGED', function()
	for _, win in ipairs(pool) do
		win.titleBar:SetHeight(T.Metrics().title - 2)
	end
	for _, win in pairs(open) do
		win.titleBar:SetHeight(T.Metrics().title - 2)
	end
end)
M:On('CONTACTS_CHANGED', function()
	for _, win in pairs(open) do
		win:UpdateTitle()
	end
end)
M:On('CONVO_DELETED', function(key)
	if key then
		P:Close(key)
	else
		P:CloseAll()
	end
end)
M:On('SETTINGS_CHANGED', function()
	for _, win in pairs(open) do
		win:ApplyAlpha()
	end
end)
