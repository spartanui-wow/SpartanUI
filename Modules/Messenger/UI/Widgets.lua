local _, ns = ...
local M = ns.Messenger
local T = M.Theme
local L = M.L

---@class Messenger.Widgets
local W = {}
M.Widgets = W

----------------------------------------------------------------------------------------------------
-- Tooltip
----------------------------------------------------------------------------------------------------

local function ShowTip(owner, text, hint)
	GameTooltip:SetOwner(owner, 'ANCHOR_TOP')
	GameTooltip:SetText(text, 1, 1, 1)
	if hint then
		GameTooltip:AddLine(hint, T.color.muted[1], T.color.muted[2], T.color.muted[3], true)
	end
	GameTooltip:Show()
end
W.ShowTip = ShowTip

----------------------------------------------------------------------------------------------------
-- Icon button
----------------------------------------------------------------------------------------------------

---@param parent Frame
---@param icon string
---@param size number
---@param tooltip? string
---@param onClick fun(self: Button, mouseButton: string)
---@return Button
function W.IconButton(parent, icon, size, tooltip, onClick)
	local btn = CreateFrame('Button', nil, parent)
	btn:SetSize(size, size)
	btn:RegisterForClicks('LeftButtonUp', 'RightButtonUp')

	btn.bg = T.Fill(btn, T.color.hover, 'BACKGROUND')
	btn.bg:Hide()

	btn.icon = btn:CreateTexture(nil, 'ARTWORK')
	btn.icon:SetPoint('CENTER')
	local glyph = math.floor(size * 0.8 + 0.5)
	btn.icon:SetSize(glyph, glyph)
	T.SetIcon(btn.icon, icon)

	btn.tint = T.color.muted
	btn.icon:SetVertexColor(unpack(btn.tint))

	function btn:SetTint(color)
		self.tint = color
		if not self:IsMouseOver() then
			self.icon:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
		end
	end

	function btn:SetIconName(name)
		T.SetIcon(self.icon, name)
	end

	btn:SetScript('OnEnter', function(self)
		self.bg:Show()
		self.icon:SetVertexColor(1, 1, 1)
		if self.tooltip then
			ShowTip(self, self.tooltip, self.hint)
		end
	end)
	btn:SetScript('OnLeave', function(self)
		self.bg:Hide()
		self.icon:SetVertexColor(self.tint[1], self.tint[2], self.tint[3], self.tint[4] or 1)
		GameTooltip:Hide()
	end)
	btn:SetScript('OnMouseDown', function(self)
		self.icon:SetPoint('CENTER', 0, -1)
	end)
	btn:SetScript('OnMouseUp', function(self)
		self.icon:SetPoint('CENTER', 0, 0)
	end)
	btn:SetScript('OnClick', onClick)
	btn.tooltip = tooltip
	return btn
end

----------------------------------------------------------------------------------------------------
-- Text button (flat, used for empty states and notices)
----------------------------------------------------------------------------------------------------

---@param parent Frame
---@param text string
---@param onClick function
---@param accent? table Fill color for the primary action
---@return Button
function W.TextButton(parent, text, onClick, accent)
	local btn = CreateFrame('Button', nil, parent)
	btn.label = T.Text(btn, 'name', accent and T.color.onLight or T.color.text)
	btn.label:SetPoint('CENTER')
	btn.label:SetText(text)
	btn:SetSize(math.max(72, btn.label:GetStringWidth() + 24), 24)

	if accent then
		btn.bg = T.Fill(btn, { accent[1], accent[2], accent[3], 0.9 })
	else
		btn.bg = T.Fill(btn, T.color.raised)
		T.Border(btn, T.color.edge)
	end
	btn.hl = T.Fill(btn, T.color.pressed, 'ARTWORK')
	btn.hl:Hide()

	function btn:SetLabel(value)
		self.label:SetText(value)
		self:SetWidth(math.max(72, self.label:GetStringWidth() + 24))
	end

	btn:SetScript('OnEnter', function(self)
		self.hl:Show()
	end)
	btn:SetScript('OnLeave', function(self)
		self.hl:Hide()
	end)
	btn:SetScript('OnClick', onClick)
	return btn
end

----------------------------------------------------------------------------------------------------
-- Filter chip
----------------------------------------------------------------------------------------------------

---@param parent Frame
---@param text string
---@param onClick function
---@return Button
function W.Chip(parent, text, onClick)
	local chip = CreateFrame('Button', nil, parent)
	chip.label = T.Text(chip, 'small', T.color.muted)
	chip.label:SetPoint('CENTER')
	chip.label:SetText(text)
	chip:SetSize(chip.label:GetStringWidth() + 16, 18)
	chip.bg = T.Fill(chip, T.color.selected)
	chip.bg:Hide()

	function chip:SetSelected(selected)
		self.selected = selected
		self.bg:SetShown(selected)
		T.SetColor(self.label, selected and T.color.text or T.color.muted)
	end

	function chip:Resize()
		self:SetWidth(self.label:GetStringWidth() + 16)
	end

	chip:SetScript('OnEnter', function(self)
		if not self.selected then
			T.SetColor(self.label, T.color.text)
		end
	end)
	chip:SetScript('OnLeave', function(self)
		if not self.selected then
			T.SetColor(self.label, T.color.muted)
		end
	end)
	chip:SetScript('OnClick', onClick)
	return chip
end

----------------------------------------------------------------------------------------------------
-- Unread badge
----------------------------------------------------------------------------------------------------

---@param parent Frame
---@return Frame
function W.Badge(parent)
	local badge = CreateFrame('Frame', nil, parent)
	badge:SetSize(18, 15)
	badge.bg = T.Fill(badge, T.color.solid)
	badge.text = T.Text(badge, 'small', T.color.onLight)
	badge.text:SetPoint('CENTER', 0, 0)

	---@param count number
	---@param r? number
	---@param g? number
	---@param b? number
	function badge:SetCount(count, r, g, b)
		if not count or count <= 0 then
			self:Hide()
			return
		end
		self.text:SetText(count > 99 and '99+' or tostring(count))
		self:SetWidth(math.max(15, self.text:GetStringWidth() + 8))
		self.bg:SetVertexColor(r or 1, g or 1, b or 1, 1)
		self:Show()
	end
	badge:Hide()
	return badge
end

----------------------------------------------------------------------------------------------------
-- Avatar: class icon for people, a colored initial for rooms, plus a presence dot
----------------------------------------------------------------------------------------------------

local CLASS_ICONS = 'Interface\\TargetingFrame\\UI-Classes-Circles'
-- Crop the gold ring baked into the class circle art
local CROP = 0.08

---@param parent Frame
---@param size number
---@return Frame
function W.Avatar(parent, size)
	local av = CreateFrame('Frame', nil, parent)
	av:SetSize(size, size)

	local mask = av:CreateMaskTexture()
	mask:SetTexture(M.mediaPath .. 'Circle', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE')
	mask:SetAllPoints(av)

	av.disc = av:CreateTexture(nil, 'BACKGROUND')
	av.disc:SetAllPoints()
	av.disc:SetTexture(T.WHITE)
	av.disc:AddMaskTexture(mask)

	av.icon = av:CreateTexture(nil, 'ARTWORK')
	av.icon:SetAllPoints()
	av.icon:AddMaskTexture(mask)

	av.initial = T.Text(av, 'initial')
	av.initial:SetPoint('CENTER', 0, 0)
	av.initial:SetJustifyH('CENTER')

	local dotSize = math.max(7, math.floor(size * 0.32))
	av.dotRing = av:CreateTexture(nil, 'OVERLAY', nil, 1)
	av.dotRing:SetSize(dotSize + 3, dotSize + 3)
	av.dotRing:SetPoint('CENTER', av, 'BOTTOMRIGHT', -dotSize * 0.35, dotSize * 0.35)
	T.SetIcon(av.dotRing, 'dot')
	av.dotRing:SetVertexColor(T.color.window[1], T.color.window[2], T.color.window[3], 1)
	av.dot = av:CreateTexture(nil, 'OVERLAY', nil, 2)
	av.dot:SetSize(dotSize, dotSize)
	av.dot:SetPoint('CENTER', av.dotRing)
	T.SetIcon(av.dot, 'dot')

	---@param convo MessengerConversation
	---@param presence? MessengerPresence
	function av:SetConversation(convo, presence)
		presence = presence or {}
		local classFile = presence.class or convo.class
		local coords = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
		if coords and (convo.kind == 'WHISPER' or convo.kind == 'BN_WHISPER') then
			local l, r, t, b = coords[1], coords[2], coords[3], coords[4]
			local dx, dy = (r - l) * CROP, (b - t) * CROP
			self.icon:SetTexture(CLASS_ICONS)
			self.icon:SetTexCoord(l + dx, r - dx, t + dy, b - dy)
			self.icon:Show()
			self.initial:Hide()
			self.disc:SetVertexColor(0, 0, 0, 1)
			local offline = presence.status == 'offline'
			self.icon:SetDesaturated(offline)
			self.icon:SetAlpha(offline and 0.5 or 1)
		else
			local r, g, b = T.KindColor(convo)
			self.icon:Hide()
			self.disc:SetVertexColor(r * 0.28, g * 0.28, b * 0.28, 1)
			local kind = M.KindByKey[convo.kind]
			local letter
			if convo.kind == 'CHANNEL' then
				letter = (convo.name or '#'):match('^[%z\1-\127\194-\244][\128-\191]*') or '#'
			elseif kind and kind.initial then
				letter = kind.initial
			else
				-- convo.name, not the live title: a Battle.net title can be a protected name token
				letter = (convo.name or '?'):match('^[%z\1-\127\194-\244][\128-\191]*') or '?'
			end
			self.initial:SetText(strupper(letter))
			self.initial:SetTextColor(r, g, b)
			self.initial:Show()
		end

		local statusColor = T.StatusColor(presence.status)
		if statusColor then
			self.dot:SetVertexColor(statusColor[1], statusColor[2], statusColor[3])
			self.dot:Show()
			self.dotRing:Show()
		else
			self.dot:Hide()
			self.dotRing:Hide()
		end
	end

	---@param color table
	function av:SetRingColor(color)
		self.dotRing:SetVertexColor(color[1], color[2], color[3], 1)
	end

	return av
end

----------------------------------------------------------------------------------------------------
-- Drop-down menu (one shared instance)
----------------------------------------------------------------------------------------------------

local menu

local function CloseMenu()
	if menu then
		menu:Hide()
	end
end
W.CloseMenu = CloseMenu

---The frame the last menu opened from, so a menu entry can open a follow-up menu in its place.
---@return Frame|nil
function W.LastMenuOwner()
	return menu and menu.owner
end

local function BuildMenu()
	menu = CreateFrame('Frame', 'MessengerDropDown', UIParent)
	menu:SetFrameStrata('FULLSCREEN_DIALOG')
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	T.Fill(menu, T.color.popup)
	T.Border(menu, T.color.edgeStrong)
	menu.rows = {}
	menu:Hide()
	menu:SetScript('OnEvent', function(self)
		if not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then
			self:Hide()
		end
	end)
	-- Clicking outside closes the menu. Older clients may not have the event; Escape still works.
	menu:SetScript('OnShow', function(self)
		pcall(self.RegisterEvent, self, 'GLOBAL_MOUSE_DOWN')
	end)
	menu:SetScript('OnHide', function(self)
		pcall(self.UnregisterEvent, self, 'GLOBAL_MOUSE_DOWN')
	end)
	tinsert(UISpecialFrames, 'MessengerDropDown')
end

local function MenuRow(index)
	local row = menu.rows[index]
	if row then
		return row
	end
	row = CreateFrame('Button', nil, menu)
	row:SetHeight(22)
	row.hl = T.Fill(row, T.color.hover)
	row.hl:Hide()
	row.check = row:CreateTexture(nil, 'ARTWORK')
	row.check:SetSize(14, 14)
	row.check:SetPoint('LEFT', 8, 0)
	T.SetIcon(row.check, 'check')
	row.swatch = row:CreateTexture(nil, 'ARTWORK')
	row.swatch:SetSize(14, 14)
	row.swatch:SetPoint('LEFT', 8, 0)
	row.swatch:SetTexture(M.mediaPath .. 'Circle')
	row.text = T.Text(row, 'body')
	row.text:SetPoint('LEFT', 26, 0)
	row.divider = T.Line(row, 'TOP')
	row:SetScript('OnEnter', function(self)
		if self:IsEnabled() then
			self.hl:Show()
		end
	end)
	row:SetScript('OnLeave', function(self)
		self.hl:Hide()
	end)
	row:SetScript('OnClick', function(self)
		CloseMenu()
		if self.item and self.item.onClick then
			self.item.onClick()
		end
	end)
	menu.rows[index] = row
	return row
end

---@class MessengerMenuItem
---@field text string
---@field onClick? function
---@field checked? boolean
---@field disabled? boolean
---@field danger? boolean
---@field divider? boolean Draw a separator above this item
---@field swatch? number[] A round color sample { r, g, b } in front of the text; a check then sits on the right
---@field note? boolean Quiet text that cannot be clicked, such as a heading

---Opens a menu under an anchor. Clicking elsewhere or pressing Escape closes it.
---@param anchor Frame
---@param items MessengerMenuItem[]
function W.OpenMenu(anchor, items)
	if not menu then
		BuildMenu()
	end
	if menu:IsShown() and menu.owner == anchor then
		CloseMenu()
		return
	end
	local width = 140
	local y = -4
	for i, item in ipairs(items) do
		local row = MenuRow(i)
		row.item = item
		row.text:SetText(item.text)
		local color = item.note and T.color.muted or item.disabled and T.color.faint or (item.danger and T.color.danger or T.color.text)
		T.SetColor(row.text, color)
		row.check:SetShown(item.checked == true)
		row.check:SetVertexColor(T.color.text[1], T.color.text[2], T.color.text[3])
		row.check:ClearAllPoints()
		if item.swatch then
			row.check:SetPoint('RIGHT', -8, 0)
			row.swatch:SetVertexColor(item.swatch[1], item.swatch[2], item.swatch[3])
		else
			row.check:SetPoint('LEFT', 8, 0)
		end
		row.swatch:SetShown(item.swatch ~= nil)
		row.text:ClearAllPoints()
		row.text:SetPoint('LEFT', item.note and 10 or 26, 0)
		row.divider:SetShown(item.divider == true)
		row:SetEnabled(not item.disabled and not item.note)
		if item.divider then
			y = y - 4
		end
		row:ClearAllPoints()
		row:SetPoint('TOPLEFT', 0, y)
		row:SetPoint('TOPRIGHT', 0, y)
		row:Show()
		y = y - 22
		width = math.max(width, row.text:GetStringWidth() + (item.swatch and 58 or 40))
	end
	for i = #items + 1, #menu.rows do
		menu.rows[i]:Hide()
	end
	menu:SetSize(width, -y + 4)
	menu.owner = anchor
	menu:ClearAllPoints()
	menu:SetPoint('TOPRIGHT', anchor, 'BOTTOMRIGHT', 0, -2)
	menu:Show()
end

----------------------------------------------------------------------------------------------------
-- Bubble colors
----------------------------------------------------------------------------------------------------

---Opens the game's color picker. onPick gets { r, g, b }; Cancel puts the old color back.
---@param r number
---@param g number
---@param b number
---@param onPick fun(color: number[])
function W.PickColor(r, g, b, onPick)
	local picker = ColorPickerFrame
	if not (picker and picker.SetupColorPickerAndShow) then
		return
	end
	local function Changed()
		local nr, ng, nb = picker:GetColorRGB()
		onPick({ nr, ng, nb })
	end
	picker:SetupColorPickerAndShow({
		r = r,
		g = g,
		b = b,
		hasOpacity = false,
		swatchFunc = Changed,
		cancelFunc = function()
			onPick({ r, g, b })
		end,
	})
end

---@class MessengerColorMenu
---@field title? string Heading over the choices
---@field note? string Quiet line under the heading
---@field current string|table|nil The saved choice (nil = the default)
---@field defaultText string
---@field defaultColor? number[] Source color { r, g, b } of the default; grey when nil
---@field onPick fun(value: string|table|nil)

---A menu of bubble colors, each with a sample of the bubble it makes.
---@param anchor Frame
---@param opts MessengerColorMenu
function W.OpenColorMenu(anchor, opts)
	local Colors = M.Colors
	local function Sample(r, g, b)
		if not r then
			return { T.color.bubble[1], T.color.bubble[2], T.color.bubble[3] }
		end
		return { T.BubbleFill(r, g, b) }
	end
	local items = {}
	if opts.title then
		items[#items + 1] = { text = opts.title, note = true }
	end
	if opts.note then
		items[#items + 1] = { text = opts.note, note = true }
	end
	local current = opts.current
	local default = opts.defaultColor
	items[#items + 1] = {
		text = opts.defaultText,
		divider = #items > 0,
		checked = current == nil,
		swatch = Sample(default and default[1], default and default[2], default and default[3]),
		onClick = function()
			opts.onPick(nil)
		end,
	}
	for _, color in ipairs(Colors.Palette) do
		items[#items + 1] = {
			text = color.label,
			checked = current == color.id,
			swatch = Sample(color.r, color.g, color.b),
			onClick = function()
				opts.onPick(color.id)
			end,
		}
	end
	local custom = type(current) == 'table' and current or nil
	if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
		items[#items + 1] = {
			text = M.L['Pick any color...'],
			checked = custom ~= nil,
			swatch = custom and Sample(custom[1], custom[2], custom[3]) or nil,
			divider = true,
			onClick = function()
				local r, g, b = Colors.Resolve(current)
				if not r and default then
					r, g, b = default[1], default[2], default[3]
				end
				W.PickColor(r or 0.5, g or 0.5, b or 0.54, opts.onPick)
			end,
		}
	end
	W.OpenMenu(anchor, items)
end

----------------------------------------------------------------------------------------------------
-- Confirmation
----------------------------------------------------------------------------------------------------

StaticPopupDialogs['MESSENGER_CONFIRM'] = {
	text = '%s',
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, data)
		if data and data.onAccept then
			data.onAccept()
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

---@param text string
---@param onAccept function
function W.Confirm(text, onAccept)
	StaticPopup_Show('MESSENGER_CONFIRM', text, nil, { onAccept = onAccept })
end

----------------------------------------------------------------------------------------------------
-- Copy box (links and message text)
----------------------------------------------------------------------------------------------------

local copyFrame

---@param title string
---@param text string
function W.CopyBox(title, text)
	if not copyFrame then
		copyFrame = CreateFrame('Frame', 'MessengerCopyBox', UIParent)
		copyFrame:SetSize(420, 96)
		copyFrame:SetPoint('CENTER', 0, 120)
		copyFrame:SetFrameStrata('DIALOG')
		copyFrame:EnableMouse(true)
		T.Fill(copyFrame, T.color.popup)
		T.Border(copyFrame, T.color.edgeStrong)
		copyFrame.title = T.Text(copyFrame, 'title')
		copyFrame.title:SetPoint('TOPLEFT', 12, -10)
		copyFrame.hint = T.Text(copyFrame, 'meta', T.color.muted)
		copyFrame.hint:SetPoint('BOTTOMLEFT', 12, 10)
		copyFrame.hint:SetText(L['Press Ctrl+C to copy, then Escape to close.'])
		local close = W.IconButton(copyFrame, 'close', 20, nil, function()
			copyFrame:Hide()
		end)
		close:SetPoint('TOPRIGHT', -6, -6)

		local box = CreateFrame('EditBox', nil, copyFrame)
		box:SetPoint('TOPLEFT', 12, -34)
		box:SetPoint('TOPRIGHT', -12, -34)
		box:SetHeight(24)
		box:SetAutoFocus(false)
		box:SetFontObject(ChatFontNormal)
		box:SetTextInsets(6, 6, 0, 0)
		T.Fill(box, T.color.input)
		box:SetScript('OnEscapePressed', function()
			copyFrame:Hide()
		end)
		box:SetScript('OnTextChanged', function(self, user)
			if user then
				self:SetText(copyFrame.value)
				self:HighlightText()
			end
		end)
		copyFrame.box = box
		tinsert(UISpecialFrames, 'MessengerCopyBox')
	end
	copyFrame.title:SetText(title)
	copyFrame.value = text
	copyFrame.box:SetText(text)
	copyFrame:Show()
	copyFrame.box:SetFocus()
	copyFrame.box:HighlightText()
end

----------------------------------------------------------------------------------------------------
-- Window chrome shared by the deck and pop-outs
----------------------------------------------------------------------------------------------------

local windows = setmetatable({}, { __mode = 'k' })

---A window look's frame behind a window's content, without the title bar, close button, crest or footer.
---@param win Frame
---@param Kit table
local function BuildSkin(win, Kit)
	local skin = CreateFrame('Frame', nil, win)
	skin:SetAllPoints()
	Kit:DressShell(skin, { titleBar = false, close = false, crest = false, footer = false })
	-- Behind the window's panels, with the painted frame over their edges
	local level = win:GetFrameLevel()
	skin:SetFrameLevel(level)
	skin.VisualRoot:SetFrameLevel(level)
	skin.FrameArt:SetFrameLevel(level + 40)
	win.skin = skin
	Kit:Track(skin, function(_, config)
		if T.SkinId() == 'default' then
			return
		end
		T.ApplySkin(config)
		-- Content stays inside the frame's beam
		local border = config.assets.windowBorder
		local inset = 1
		if border and border.pieces then
			inset = math.max(config.layout.barInset or 0, border.edgeSize or 1)
		end
		win.inner:ClearAllPoints()
		win.inner:SetPoint('TOPLEFT', inset, -inset)
		win.inner:SetPoint('BOTTOMRIGHT', -inset, inset)
		win:ApplyAlpha()
	end)
end

---@param name string Global frame name
---@param minW number
---@param minH number
---@return Frame
function W.Window(name, minW, minH)
	local win = CreateFrame('Frame', name, UIParent)
	win:SetFrameStrata('MEDIUM')
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:SetMovable(true)
	win:SetResizable(true)
	win:EnableMouse(true)
	if win.SetResizeBounds then
		win:SetResizeBounds(minW, minH)
	else
		win:SetMinResize(minW, minH)
	end

	if win.SetDontSavePosition then
		win:SetDontSavePosition(true)
	end

	win.bg = T.Fill(win, T.color.window)
	-- The edge sits on its own frame above the panels, which would otherwise cover it
	win.edge = CreateFrame('Frame', nil, win)
	win.edge:SetAllPoints()
	win.edge:SetFrameLevel(win:GetFrameLevel() + 40)
	T.Border(win.edge, T.color.edge)

	win.shadow = win:CreateTexture(nil, 'BACKGROUND', nil, -8)
	win.shadow:SetTexture(T.WHITE)
	win.shadow:SetVertexColor(0, 0, 0, 0.35)
	win.shadow:SetPoint('TOPLEFT', -3, 3)
	win.shadow:SetPoint('BOTTOMRIGHT', 3, -4)

	-- Content anchors here, so a skin's frame can take the edge of the window
	win.inner = CreateFrame('Frame', nil, win)
	win.inner:SetAllPoints()

	local grip = CreateFrame('Button', nil, win)
	grip:SetSize(14, 14)
	grip:SetPoint('BOTTOMRIGHT', win.inner, 'BOTTOMRIGHT', -2, 2)
	-- Above a skin's painted frame
	grip:SetFrameLevel(win:GetFrameLevel() + 45)
	grip:SetNormalTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up')
	grip:SetHighlightTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight')
	grip:SetPushedTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down')
	grip:GetNormalTexture():SetAlpha(0.5)
	grip:SetScript('OnMouseDown', function()
		win:StartSizing('BOTTOMRIGHT')
	end)
	grip:SetScript('OnMouseUp', function()
		win:StopMovingOrSizing()
		if win.OnGeometryChanged then
			win:OnGeometryChanged()
		end
	end)
	win.grip = grip

	function win:ApplyAlpha()
		local a = T.Alpha() * (self.opacity or 1)
		self.bg:SetVertexColor(T.color.window[1], T.color.window[2], T.color.window[3], a)
		local skin = self.skin
		if skin and skin:IsShown() and skin.kitConfig then
			-- The kit's own solidity, scaled by the player's background setting
			local ground = skin.kitConfig.colors.surface[0]
			skin.Surface:SetVertexColor(ground[1], ground[2], ground[3], a * (ground[4] or 1))
		end
	end

	---Draws the window in the chosen skin: Messenger's own flat look, or a window look's frame.
	function win:ApplySkin()
		local id = T.SkinId()
		local Kit = T.Kit()
		if id == 'default' or not Kit then
			self.bg:Show()
			self.edge:Show()
			self.shadow:Show()
			if self.skin then
				self.skin:Hide()
			end
			self.inner:ClearAllPoints()
			self.inner:SetAllPoints()
			self:ApplyAlpha()
			return
		end
		self.bg:Hide()
		self.edge:Hide()
		self.shadow:Hide()
		if not self.skin then
			BuildSkin(self, Kit)
		end
		local wasShown = self.skin:IsShown()
		self.skin:Show()
		if self.skin.skinId ~= id then
			self.skin.skinId = id
			Kit:SetFrameKit(self.skin, id)
		elseif not wasShown then
			self.skin:ApplyKit()
		else
			self:ApplyAlpha()
		end
	end

	windows[win] = true
	win:ApplySkin()
	return win
end

---Redraws every Messenger window in the chosen skin.
function W.ApplySkin()
	if T.SkinId() == 'default' then
		T.ApplySkin(nil)
	end
	for win in pairs(windows) do
		win:ApplySkin()
	end
end

-- A profile switch can bring a different skin
M:On('SETTINGS_CHANGED', W.ApplySkin)

---Stores a frame's position in a settings table.
---@param frame Frame
---@param saved table
function W.SavePoint(frame, saved)
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	saved.point, saved.relativePoint = point, relativePoint
	saved.x, saved.y = math.floor(x + 0.5), math.floor(y + 0.5)
end

---Restores a position stored by SavePoint. Returns false when nothing was stored.
---@param frame Frame
---@param saved table
---@return boolean
function W.RestorePoint(frame, saved)
	if not saved.point then
		return false
	end
	frame:ClearAllPoints()
	frame:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
	return true
end

---Adds or removes a named window from the list Escape closes.
---@param name string
---@param closes boolean
function W.SetEscapeCloses(name, closes)
	for i = #UISpecialFrames, 1, -1 do
		if UISpecialFrames[i] == name then
			table.remove(UISpecialFrames, i)
		end
	end
	if closes then
		tinsert(UISpecialFrames, name)
	end
end

---Makes a region drag its window.
---@param region Frame
---@param win Frame
function W.DragHandle(region, win)
	region:EnableMouse(true)
	region:RegisterForDrag('LeftButton')
	region:SetScript('OnDragStart', function()
		if not win.locked then
			win:StartMoving()
		end
	end)
	region:SetScript('OnDragStop', function()
		win:StopMovingOrSizing()
		if win.OnGeometryChanged then
			win:OnGeometryChanged()
		end
	end)
end
