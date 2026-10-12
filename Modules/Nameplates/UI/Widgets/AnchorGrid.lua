local _, ns = ...
local P = ns.Plates
local L = P.L

-- Core AceGUI widget types (3.2, 6.11).
-- They are registered under the host's prefix (host.widgetPrefix .. 'AnchorGrid'), because
-- AceGUI's type registry is shared by every addon. No widget name in the core contains the host's
-- name. Registration happens when the options table is first built, never at load: loading these
-- files creates no frames, registers no events and installs no hooks.
--
-- This file also holds the registry (P.Widgets) and the drawing helpers the three widgets share
-- (P.Widgets.Draw). Colors and the accent come from LibAT.UI.Style, which follows the active window
-- kit; every read is checked, so a missing or partial LibAT falls back to a built-in palette.
--
-- AnchorGrid: a 3x3 grid of anchor points with four nudge arrows, so players never read an anchor
-- dropdown. Used on the Customize page for a selected part.
--   AceConfig: type = 'select', dialogControl = P.Widgets:TypeName('AnchorGrid'),
--     values = the nine point names (Schema.POINTS) with labels, get/set = the part's anchor point,
--     arg = {
--       onNudge = fun(dx: number, dy: number), -- writes the part's x/y offset through P.Store
--       offset = fun(): number, number,         -- the part's current x/y, read after every nudge
--       onReset? = fun(),                       -- "back to no offset"; default nudges by -x, -y
--       step = 0.5, bigStep = 2,                -- Shift uses bigStep
--     }
--   The widget implements the AceGUI select API (SetList, SetValue, GetValue, SetLabel,
--   SetDisabled) and fires 'OnValueChanged' with the point. Nudges never fire OnValueChanged, so
--   the page is not rebuilt while the player holds an arrow; they fire 'OnNudge'(dx, dy) and
--   'OnOffsetChanged'(x, y) for direct users. SetValue also takes { point, x, y }.

---@class Plates.Widgets
---@field types table<string, Plates.WidgetType>
---@field Draw Plates.WidgetDraw
local Widgets = P.Widgets or { types = {} }
P.Widgets = Widgets
Widgets.types = Widgets.types or {}
Widgets.registeredNames = Widgets.registeredNames or {}

---@class Plates.WidgetType
---@field version integer
---@field Constructor? fun(): table AceGUI widget constructor (nil until built)

---Full AceGUI type name for a core widget.
---@param name string 'AnchorGrid' | 'RuleList' | 'SpellList'
---@return string
function Widgets:TypeName(name)
	return ((P.host and P.host.widgetPrefix) or 'Plates') .. name
end

---Register every built widget type with AceGUI under the current prefix (safe to call again).
function Widgets:Register()
	local AceGUI = LibStub and LibStub('AceGUI-3.0', true)
	if not AceGUI then
		return
	end
	for name, def in pairs(self.types) do
		local typeName = self:TypeName(name)
		if def.Constructor and not self.registeredNames[typeName] then
			self.registeredNames[typeName] = true
			AceGUI:RegisterWidgetType(typeName, def.Constructor, def.version)
		end
	end
	self.registered = true
end

---True when a widget type is built and can be used as a dialogControl.
---@param name string
---@return boolean
function Widgets:Has(name)
	local def = self.types[name]
	return def ~= nil and def.Constructor ~= nil
end

---Create one of the core widgets outside an options table (designer panels, tests).
---@param name string 'AnchorGrid' | 'RuleList' | 'SpellList'
---@return table|nil widget AceGUI widget, released with AceGUI:Release(widget)
function Widgets:Create(name)
	self:Register()
	local AceGUI = LibStub and LibStub('AceGUI-3.0', true)
	if not (AceGUI and self:Has(name)) then
		return nil
	end
	return AceGUI:Create(self:TypeName(name))
end

----------------------------------------------------------------------------------------------------
-- Drawing helpers shared by the three widgets
----------------------------------------------------------------------------------------------------

---@class Plates.WidgetDraw
local Draw = {}
Widgets.Draw = Draw

Draw.WHITE = 'Interface\\Buttons\\WHITE8X8'

-- Used until (or unless) LibAT's style hands out real colors.
local PALETTE = {
	pane = { 0.047, 0.051, 0.059, 0.94 },
	raised = { 0.066, 0.070, 0.082, 0.96 },
	hover = { 1, 1, 1, 0.05 },
	line = { 1, 1, 1, 0.09 },
	lineStrong = { 1, 1, 1, 0.16 },
	input = { 0, 0, 0, 0.4 },
	text = { 0.93, 0.92, 0.90, 1 },
	muted = { 0.62, 0.63, 0.66, 1 },
	faint = { 0.42, 0.43, 0.46, 1 },
	onAccent = { 0.04, 0.05, 0.06, 1 },
	warn = { 1, 0.72, 0.28, 1 },
	trackOff = { 0.19, 0.20, 0.22, 1 },
}

-- Clients whose text needs the game's own font (the UI font has no glyphs for them).
local NATIVE_FONT_LOCALES = { koKR = true, zhCN = true, zhTW = true }

local function GetStyle()
	local ui = LibAT and LibAT.UI
	return ui and ui.Style or nil
end

local function IsColor(c)
	return type(c) == 'table' and type(c[1]) == 'number' and type(c[2]) == 'number' and type(c[3]) == 'number'
end

---A kit color by name (text, muted, faint, line, lineStrong, raised, pane, input, hover, warn,
---onAccent, trackOff).
---@param name string
---@return number r, number g, number b, number a
function Draw.Color(name)
	local style = GetStyle()
	local c = PALETTE[name] or PALETTE.text
	local kit = style and type(style.color) == 'table' and style.color[name] or nil
	if IsColor(kit) then
		c = kit
	end
	return c[1], c[2], c[3], (type(c[4]) == 'number' and c[4]) or 1
end

---The accent color: the host's (through LibAT), else the core's fallback.
---@return number r, number g, number b
function Draw.Accent()
	local style = GetStyle()
	if style and type(style.GetAccent) == 'function' then
		local ok, r, g, b = pcall(style.GetAccent, style)
		if ok and type(r) == 'number' and type(g) == 'number' and type(b) == 'number' then
			return r, g, b
		end
	end
	local ok, r, g, b = pcall(P.services.GetAccent)
	if ok and type(r) == 'number' and type(g) == 'number' and type(b) == 'number' then
		return r, g, b
	end
	return 1, 0.82, 0
end

---Run fn(r, g, b) now and whenever the accent or window kit changes (held weakly by owner).
---@param owner table
---@param fn fun(r: number, g: number, b: number)
function Draw.OnAccent(owner, fn)
	local style = GetStyle()
	if style and type(style.OnAccentChanged) == 'function' then
		pcall(style.OnAccentChanged, style, owner, fn)
	end
end

---Font file for widget text. Korean and Chinese clients use the game's font.
---@return string
function Draw.FontFace()
	local locale = GetLocale and GetLocale()
	if not (locale and NATIVE_FONT_LOCALES[locale]) then
		local ok, path = pcall(P.services.FontPath)
		if ok and type(path) == 'string' and path ~= '' then
			return path
		end
	end
	return (type(STANDARD_TEXT_FONT) == 'string' and STANDARD_TEXT_FONT) or 'Fonts\\FRIZQT__.TTF'
end

---@param fs FontString
---@param size number
function Draw.SetFont(fs, size)
	fs:SetFont(Draw.FontFace(), size, '')
	fs:SetShadowColor(0, 0, 0, 0.9)
	fs:SetShadowOffset(1, -1)
end

---A one-line, left-justified FontString in a kit color.
---@param parent Frame
---@param size number
---@param colorName? string
---@param layer? string
---@return FontString
function Draw.Text(parent, size, colorName, layer)
	local fs = parent:CreateFontString(nil, layer or 'OVERLAY')
	Draw.SetFont(fs, size)
	fs:SetTextColor(Draw.Color(colorName or 'text'))
	fs:SetJustifyH('LEFT')
	fs:SetWordWrap(false)
	return fs
end

---@param parent Frame
---@param layer? string
---@param sublevel? number
---@return Texture
function Draw.Rect(parent, layer, sublevel)
	local tex = parent:CreateTexture(nil, layer or 'ARTWORK', nil, sublevel)
	tex:SetTexture(Draw.WHITE)
	return tex
end

---Paint a texture (or a text) in a kit color.
---@param region Texture|FontString
---@param name string
---@param alpha? number
function Draw.Paint(region, name, alpha)
	local r, g, b, a = Draw.Color(name)
	if region.SetTextColor then
		region:SetTextColor(r, g, b, alpha or a)
	else
		region:SetVertexColor(r, g, b, alpha or a)
	end
end

---Size of one physical screen pixel in the region's own units.
---@param region? ScriptRegion
---@return number
function Draw.PixelSize(region)
	local height
	if GetPhysicalScreenSize then
		local _, h = GetPhysicalScreenSize()
		height = h
	end
	local scale = region and region.GetEffectiveScale and region:GetEffectiveScale()
	if type(height) ~= 'number' or height <= 0 or type(scale) ~= 'number' or scale <= 0 then
		return 1
	end
	return 768 / height / scale
end

---A border of one physical pixel on the inside edge of a frame.
---@param frame Frame
---@param layer? string
---@return table border { frame, [1..4] = edges }
function Draw.Border(frame, layer)
	local border = { frame = frame }
	for i = 1, 4 do
		border[i] = Draw.Rect(frame, layer or 'BORDER')
	end
	Draw.LayoutBorder(border)
	return border
end

---Place the four edges again (after a scale change).
---@param border table
function Draw.LayoutBorder(border)
	local px = Draw.PixelSize(border.frame)
	local top, bottom, left, right = border[1], border[2], border[3], border[4]
	top:ClearAllPoints()
	top:SetPoint('TOPLEFT')
	top:SetPoint('TOPRIGHT')
	top:SetHeight(px)
	bottom:ClearAllPoints()
	bottom:SetPoint('BOTTOMLEFT')
	bottom:SetPoint('BOTTOMRIGHT')
	bottom:SetHeight(px)
	left:ClearAllPoints()
	left:SetPoint('TOPLEFT', 0, -px)
	left:SetPoint('BOTTOMLEFT', 0, px)
	left:SetWidth(px)
	right:ClearAllPoints()
	right:SetPoint('TOPRIGHT', 0, -px)
	right:SetPoint('BOTTOMRIGHT', 0, px)
	right:SetWidth(px)
end

---@param border table
---@param r number
---@param g number
---@param b number
---@param a? number
function Draw.BorderColor(border, r, g, b, a)
	for i = 1, 4 do
		border[i]:SetVertexColor(r, g, b, a or 1)
	end
end

local atlasKnown = {}

---True when the client has the atlas (checked once per name).
---@param atlas string
---@return boolean
function Draw.HasAtlas(atlas)
	local known = atlasKnown[atlas]
	if known == nil then
		known = false
		if C_Texture and C_Texture.GetAtlasInfo then
			local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
			known = ok and info ~= nil
		end
		atlasKnown[atlas] = known
	end
	return known
end

---Forget atlas answers (tests).
function Draw.ForgetAtlases()
	P.util.Wipe(atlasKnown)
end

---Icons the widgets draw. Each atlas has a texture file to fall back to on clients without it.
Draw.ICONS = {
	remove = { atlas = 'common-icon-redx', file = 'Interface\\Buttons\\UI-GroupLoot-Pass-Up' },
	search = { atlas = 'common-search-magnifyingglass', file = 'Interface\\Common\\UI-Searchbox-Icon' },
	clear = { atlas = 'common-search-clearbutton', file = 'Interface\\FriendsFrame\\ClearBroadcastIcon' },
	unknown = { file = 'Interface\\Icons\\INV_Misc_QuestionMark', coords = { 0.08, 0.92, 0.08, 0.92 } },
}

---Set a texture from an atlas when the client has it, else from a file.
---@param tex Texture
---@param key string Draw.ICONS key
function Draw.Icon(tex, key)
	local def = Draw.ICONS[key]
	if not def then
		return
	end
	if def.atlas and Draw.HasAtlas(def.atlas) then
		tex:SetAtlas(def.atlas)
		return
	end
	tex:SetTexture(def.file)
	local c = def.coords
	if c then
		tex:SetTexCoord(c[1], c[2], c[3], c[4])
	else
		tex:SetTexCoord(0, 1, 0, 1)
	end
end

---Spell icon (file id or path); a question mark when there is none.
---@param tex Texture
---@param icon? number|string
function Draw.SpellIcon(tex, icon)
	if icon then
		tex:SetTexture(icon)
		tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	else
		Draw.Icon(tex, 'unknown')
	end
end

---@param id number
function Draw.Sound(id)
	if PlaySound then
		pcall(PlaySound, id)
	end
end

---Shift held (bigger nudges). False on clients or tests without the function.
---@return boolean
function Draw.ShiftDown()
	return IsShiftKeyDown ~= nil and IsShiftKeyDown() and true or false
end

---Tooltip with a title and a wrapped body; a spell tooltip when spellID is given and the client can.
---@param owner Frame
---@param title? string
---@param body? string
---@param spellID? integer
function Draw.ShowTooltip(owner, title, body, spellID)
	local tip = GameTooltip
	if not (tip and tip.SetOwner) then
		return
	end
	tip:SetOwner(owner, 'ANCHOR_RIGHT')
	local shown = false
	if spellID and tip.SetSpellByID then
		shown = pcall(tip.SetSpellByID, tip, spellID)
	end
	if not shown then
		tip:SetText(title or '', 1, 1, 1, 1, true)
	end
	if body and body ~= '' then
		local r, g, b = Draw.Color('muted')
		tip:AddLine(body, r, g, b, true)
	end
	tip:Show()
end

function Draw.HideTooltip()
	if GameTooltip and GameTooltip.Hide then
		GameTooltip:Hide()
	end
end

---Lay out every container above a widget whose height changed outside a layout pass.
---@param widget table AceGUI widget
function Draw.RelayoutParents(widget)
	local parent = widget.parent
	local depth = 0
	while parent and depth < 12 do
		if type(parent.DoLayout) == 'function' then
			parent:DoLayout()
		end
		parent = parent.parent
		depth = depth + 1
	end
end

---Set a widget's height, re-laying out its parents when it changed outside a layout pass.
---widget.layoutDepth > 0 marks a layout pass (OnWidthSet), where the parent reads the new height
---itself. frame.height is set first, so a size handler that runs during SetHeight sees no change.
---@param widget table
---@param height number
function Draw.SetWidgetHeight(widget, height)
	local old = widget.frame.height
	if old == height then
		return
	end
	local quiet = old == nil or (widget.layoutDepth or 0) > 0
	widget.frame.height = height
	widget:SetHeight(height)
	if not quiet then
		Draw.RelayoutParents(widget)
	end
end

---Run a widget's layout function once at a time; a size handler that fires while it runs is
---ignored. place(widget) returns the widget's height.
---@param widget table
---@param place fun(widget: table): number
---@return boolean ran
function Draw.RunLayout(widget, place)
	if widget.laying then
		return false
	end
	widget.laying = true
	local ok, height = pcall(place, widget)
	widget.laying = false
	if not ok then
		if geterrorhandler then
			geterrorhandler()(height)
		end
		return false
	end
	Draw.SetWidgetHeight(widget, math.max(tonumber(height) or 0, 8))
	return true
end

---OnWidthSet for widgets that lay themselves out: counts the pass so the height change is quiet.
---@param widget table
---@param layout fun(widget: table)
function Draw.LayoutPass(widget, layout)
	widget.layoutDepth = (widget.layoutDepth or 0) + 1
	layout(widget)
	widget.layoutDepth = widget.layoutDepth - 1
end

----------------------------------------------------------------------------------------------------
-- Small arrow glyph from whole-pixel rows
----------------------------------------------------------------------------------------------------

local ArrowMethods = {}

---@param direction 'UP'|'DOWN'|'LEFT'|'RIGHT'
function ArrowMethods:SetDirection(direction)
	self.direction = direction
	self:Layout()
end

function ArrowMethods:SetColor(r, g, b, a)
	for _, part in ipairs(self.parts) do
		part:SetVertexColor(r, g, b, a or 1)
	end
end

function ArrowMethods:Layout()
	local px = Draw.PixelSize(self.parent)
	local n = self.rows
	local long = (2 * n - 1) * px
	local horizontal = self.direction == 'LEFT' or self.direction == 'RIGHT'
	if horizontal then
		self.anchor:SetSize(n * px, long)
	else
		self.anchor:SetSize(long, n * px)
	end
	for i, part in ipairs(self.parts) do
		local size = (2 * (n - i) + 1) * px
		part:ClearAllPoints()
		if self.direction == 'DOWN' then
			part:SetSize(size, px)
			part:SetPoint('TOP', self.anchor, 'TOP', 0, -(i - 1) * px)
		elseif self.direction == 'UP' then
			part:SetSize(size, px)
			part:SetPoint('BOTTOM', self.anchor, 'BOTTOM', 0, (i - 1) * px)
		elseif self.direction == 'RIGHT' then
			part:SetSize(px, size)
			part:SetPoint('LEFT', self.anchor, 'LEFT', (i - 1) * px, 0)
		else
			part:SetSize(px, size)
			part:SetPoint('RIGHT', self.anchor, 'RIGHT', -(i - 1) * px, 0)
		end
	end
end

---A small solid triangle. Place it with arrow.anchor.
---@param parent Frame
---@param direction 'UP'|'DOWN'|'LEFT'|'RIGHT'
---@param rows? number Height in physical pixels (default 4)
---@return table arrow
function Draw.Arrow(parent, direction, rows)
	local arrow = { parent = parent, rows = rows or 4, parts = {}, direction = direction or 'DOWN' }
	arrow.anchor = parent:CreateTexture(nil, 'ARTWORK')
	for i = 1, arrow.rows do
		arrow.parts[i] = Draw.Rect(parent, 'ARTWORK')
	end
	for name, fn in pairs(ArrowMethods) do
		arrow[name] = fn
	end
	arrow:Layout()
	return arrow
end

----------------------------------------------------------------------------------------------------
-- Flat button and switch. State lives in our own fields (button.disabled, .active, .hovered), so
-- painting never depends on the client's IsEnabled.
----------------------------------------------------------------------------------------------------

---@param button table
function Draw.PaintButton(button)
	local ar, ag, ab = Draw.Accent()
	local fill, border, label = button.fill, button.border, button.label
	if button.disabled then
		Draw.Paint(fill, 'raised', 0.5)
		Draw.BorderColor(border, Draw.Color('line'))
		if label then
			Draw.Paint(label, 'faint')
		end
	elseif button.active then
		fill:SetVertexColor(ar, ag, ab, button.hovered and 0.32 or 0.22)
		Draw.BorderColor(border, ar, ag, ab, 0.9)
		if label then
			Draw.Paint(label, 'text')
		end
	else
		local r, g, b, a = Draw.Color('raised')
		local lift = button.hovered and 0.035 or 0
		fill:SetVertexColor(r + lift, g + lift, b + lift, a)
		local lr, lg, lb, la = Draw.Color('lineStrong')
		Draw.BorderColor(border, lr, lg, lb, button.hovered and 0.3 or la)
		if label then
			Draw.Paint(label, button.hovered and 'text' or 'muted')
		end
	end
	if button.glyph then
		if button.disabled then
			button.glyph:SetColor(Draw.Color('faint'))
		elseif button.hovered or button.active then
			button.glyph:SetColor(ar, ag, ab, 1)
		else
			button.glyph:SetColor(Draw.Color('muted'))
		end
	end
	if button.icon then
		button.icon:SetAlpha(button.disabled and 0.35 or (button.hovered and 1 or 0.75))
	end
end

local function Button_OnEnter(button)
	button.hovered = true
	Draw.PaintButton(button)
	if button.tooltipTitle or button.tooltipBody then
		Draw.ShowTooltip(button, button.tooltipTitle, button.tooltipBody)
	end
	if button.onEnter then
		button.onEnter(button)
	end
end

local function Button_OnLeave(button)
	button.hovered = false
	Draw.PaintButton(button)
	if button.tooltipTitle or button.tooltipBody then
		Draw.HideTooltip()
	end
	if button.onLeave then
		button.onLeave(button)
	end
end

local function Button_OnClick(button, mouseButton)
	if not button.disabled and button.onClick then
		button.onClick(button, mouseButton)
	end
end

local function Button_OnShow(button)
	Draw.LayoutBorder(button.border)
	if button.glyph then
		button.glyph:Layout()
	end
end

---A flat kit button. Set button.onClick(button, mouseButton); it is not called while disabled.
---@param parent Frame
---@param text? string
---@param width? number
---@param height? number
---@return table button
function Draw.Button(parent, text, width, height)
	local button = CreateFrame('Button', nil, parent)
	button:SetSize(width or 60, height or 20)
	button.fill = Draw.Rect(button, 'BACKGROUND')
	button.fill:SetAllPoints()
	button.border = Draw.Border(button)
	if text then
		button.label = Draw.Text(button, 11)
		button.label:SetPoint('LEFT', 4, 0)
		button.label:SetPoint('RIGHT', -4, 0)
		button.label:SetJustifyH('CENTER')
		button.label:SetText(text)
	end
	button:SetScript('OnEnter', Button_OnEnter)
	button:SetScript('OnLeave', Button_OnLeave)
	button:SetScript('OnClick', Button_OnClick)
	button:SetScript('OnShow', Button_OnShow)
	Draw.PaintButton(button)
	return button
end

---@param button table
---@param enabled boolean
function Draw.SetEnabled(button, enabled)
	button.disabled = not enabled
	if button.SetEnabled then
		button:SetEnabled(enabled and true or false)
	end
	if button.isSwitch then
		Draw.PaintSwitch(button)
	else
		Draw.PaintButton(button)
	end
end

---@param button table
---@param title? string
---@param body? string
function Draw.SetTooltip(button, title, body)
	button.tooltipTitle = title
	button.tooltipBody = body
end

---@param switch table
function Draw.PaintSwitch(switch)
	local ar, ag, ab = Draw.Accent()
	local on = switch.checked
	if on then
		switch.track:SetVertexColor(ar, ag, ab, switch.disabled and 0.35 or (switch.hovered and 0.95 or 0.85))
		Draw.BorderColor(switch.border, ar, ag, ab, switch.disabled and 0.4 or 1)
		Draw.Paint(switch.knob, 'text', switch.disabled and 0.5 or 1)
	else
		Draw.Paint(switch.track, 'trackOff', switch.disabled and 0.5 or 1)
		local r, g, b, a = Draw.Color('lineStrong')
		Draw.BorderColor(switch.border, r, g, b, switch.hovered and 0.35 or a)
		Draw.Paint(switch.knob, 'muted', switch.disabled and 0.5 or 1)
	end
	switch.knob:ClearAllPoints()
	if on then
		switch.knob:SetPoint('RIGHT', switch, 'RIGHT', -2, 0)
	else
		switch.knob:SetPoint('LEFT', switch, 'LEFT', 2, 0)
	end
end

local function Switch_OnEnter(switch)
	switch.hovered = true
	Draw.PaintSwitch(switch)
	if switch.tooltipTitle or switch.tooltipBody then
		Draw.ShowTooltip(switch, switch.tooltipTitle, switch.tooltipBody)
	end
	if switch.onEnter then
		switch.onEnter(switch)
	end
end

local function Switch_OnLeave(switch)
	switch.hovered = false
	Draw.PaintSwitch(switch)
	Draw.HideTooltip()
	if switch.onLeave then
		switch.onLeave(switch)
	end
end

---An on/off switch. Set switch.onClick(switch); show a value with Draw.SetSwitch.
---@param parent Frame
---@return table switch
function Draw.Switch(parent)
	local switch = CreateFrame('Button', nil, parent)
	switch.isSwitch = true
	switch:SetSize(26, 14)
	switch.track = Draw.Rect(switch, 'BACKGROUND')
	switch.track:SetAllPoints()
	switch.border = Draw.Border(switch)
	switch.knob = Draw.Rect(switch, 'ARTWORK')
	switch.knob:SetSize(10, 10)
	switch.checked = false
	switch:SetScript('OnEnter', Switch_OnEnter)
	switch:SetScript('OnLeave', Switch_OnLeave)
	switch:SetScript('OnClick', Button_OnClick)
	switch:SetScript('OnShow', Button_OnShow)
	Draw.PaintSwitch(switch)
	return switch
end

---@param switch table
---@param on boolean
function Draw.SetSwitch(switch, on)
	switch.checked = on and true or false
	Draw.PaintSwitch(switch)
end

----------------------------------------------------------------------------------------------------
-- Popup list (When choices, Add a color, spell search results). One shared frame, made the first
-- time a list opens. It closes on a pick, on a click anywhere else, or when its owner says so.
----------------------------------------------------------------------------------------------------

---@class Plates.MenuItem
---@field value any
---@field text string
---@field note? string Muted text on the right (an id, a short tag)
---@field icon? number|string Spell icon (file id or path)
---@field iconKey? string Draw.ICONS key instead of icon
---@field disabled? boolean
---@field checked? boolean
---@field tooltip? string
---@field spellID? integer Shows the spell's own tooltip on hover

local MENU_ROW = 20
local MENU_PAD = 4
local menu

local function PaintMenuRow(row)
	local item = row.item
	local ar, ag, ab = Draw.Accent()
	if row.hovered and item and not item.disabled then
		row.hl:SetVertexColor(ar, ag, ab, 0.2)
	else
		row.hl:SetVertexColor(0, 0, 0, 0)
	end
	if item and item.disabled then
		Draw.Paint(row.text, 'faint')
	else
		Draw.Paint(row.text, row.hovered and 'text' or 'muted')
	end
	row.mark:SetShown(item ~= nil and item.checked == true)
	row.mark:SetVertexColor(ar, ag, ab, 1)
end

local function PickRow(row)
	local item = row.item
	if not (menu and item) or item.disabled then
		return
	end
	local onPick = menu.onPick
	menu:Hide()
	if onPick then
		onPick(item.value, item)
	end
end

local function MenuRow_OnEnter(row)
	row.hovered = true
	PaintMenuRow(row)
	local item = row.item
	if item and (item.tooltip or item.spellID) then
		Draw.ShowTooltip(row, item.text, item.tooltip, item.spellID)
	end
end

local function MenuRow_OnLeave(row)
	row.hovered = false
	PaintMenuRow(row)
	Draw.HideTooltip()
end

local function MenuRow(index)
	local row = menu.rows[index]
	if row then
		return row
	end
	row = CreateFrame('Button', nil, menu)
	row:SetHeight(MENU_ROW)
	row.hl = Draw.Rect(row, 'BACKGROUND')
	row.hl:SetAllPoints()
	row.mark = Draw.Rect(row, 'ARTWORK')
	row.mark:SetSize(3, MENU_ROW - 8)
	row.mark:SetPoint('LEFT', 1, 0)
	row.icon = row:CreateTexture(nil, 'ARTWORK')
	row.icon:SetSize(16, 16)
	row.icon:SetPoint('LEFT', 8, 0)
	row.text = Draw.Text(row, 11, 'muted')
	row.note = Draw.Text(row, 10, 'faint')
	row.note:SetPoint('RIGHT', -6, 0)
	row.note:SetJustifyH('RIGHT')
	row:SetScript('OnEnter', MenuRow_OnEnter)
	row:SetScript('OnLeave', MenuRow_OnLeave)
	row:SetScript('OnClick', PickRow)
	menu.rows[index] = row
	return row
end

local function Menu_OnHide(self)
	self:UnregisterEvent('GLOBAL_MOUSE_DOWN')
	local onClose = self.onClose
	self.owner, self.items, self.onPick, self.onClose = nil, nil, nil, nil
	for _, row in ipairs(self.rows) do
		row.hovered = false
		row.item = nil
	end
	if onClose then
		onClose()
	end
end

local function Menu_OnEvent(self, event)
	if event ~= 'GLOBAL_MOUSE_DOWN' or self:IsMouseOver() then
		return
	end
	local owner = self.owner
	if owner and owner:IsMouseOver() then
		if self.keepOwner then
			return
		end
		-- The owner's own click comes next; remember it so that click closes the list for good
		self.closedBy, self.closedAt = owner, GetTime and GetTime() or 0
	end
	self:Hide()
end

local function GetMenu()
	if menu then
		return menu
	end
	menu = CreateFrame('Frame', nil, UIParent)
	menu:Hide()
	menu:SetFrameStrata('TOOLTIP')
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	menu.fill = Draw.Rect(menu, 'BACKGROUND')
	menu.fill:SetAllPoints()
	menu.border = Draw.Border(menu)
	menu.rows = {}
	menu:SetScript('OnHide', Menu_OnHide)
	menu:SetScript('OnEvent', Menu_OnEvent)
	return menu
end

---Open the popup list under (or above) owner. Opening it again for the same owner updates it.
---@param owner Frame
---@param items Plates.MenuItem[]
---@param onPick fun(value: any, item: Plates.MenuItem)
---@param opts? { width?: number, keepOwner?: boolean, onClose?: fun(), maxRows?: integer }
---@return Frame menu
function Draw.OpenMenu(owner, items, onPick, opts)
	opts = opts or {}
	local m = GetMenu()
	if m:IsShown() and m.owner ~= owner then
		m:Hide()
	end
	m.owner, m.items, m.onPick, m.onClose, m.keepOwner = owner, items, onPick, opts.onClose, opts.keepOwner
	m.closedBy = nil

	local ownerScale = owner:GetEffectiveScale()
	local rootScale = UIParent:GetEffectiveScale()
	if type(ownerScale) ~= 'number' or ownerScale <= 0 then
		ownerScale = 1
	end
	if type(rootScale) == 'number' and rootScale > 0 then
		m:SetScale(ownerScale / rootScale)
	end
	m:SetWidth(opts.width or math.max(owner:GetWidth() or 0, 160))

	local count = math.min(#items, opts.maxRows or 16)
	for i = 1, count do
		local row = MenuRow(i)
		local item = items[i]
		row.item = item
		row:ClearAllPoints()
		row:SetPoint('TOPLEFT', MENU_PAD, -(MENU_PAD + (i - 1) * MENU_ROW))
		row:SetPoint('TOPRIGHT', -MENU_PAD, -(MENU_PAD + (i - 1) * MENU_ROW))
		local hasIcon = item.icon ~= nil or item.iconKey ~= nil
		row.icon:SetShown(hasIcon)
		if item.iconKey then
			Draw.Icon(row.icon, item.iconKey)
		elseif item.icon then
			Draw.SpellIcon(row.icon, item.icon)
		end
		row.text:ClearAllPoints()
		row.text:SetPoint('LEFT', hasIcon and 30 or 8, 0)
		row.text:SetPoint('RIGHT', row.note, 'LEFT', -6, 0)
		row.text:SetText(item.text or '')
		row.note:SetText(item.note or '')
		row.hovered = false
		PaintMenuRow(row)
		row:Show()
	end
	for i = count + 1, #m.rows do
		m.rows[i]:Hide()
		m.rows[i].item = nil
	end
	local height = MENU_PAD * 2 + math.max(count, 1) * MENU_ROW
	m:SetHeight(height)

	local fr, fg, fb = Draw.Color('raised')
	m.fill:SetVertexColor(fr, fg, fb, 0.98)
	Draw.BorderColor(m.border, Draw.Color('lineStrong'))
	Draw.LayoutBorder(m.border)

	-- Open upward when there is no room below the owner
	local bottom = (owner:GetBottom() or 0) * ownerScale
	m:ClearAllPoints()
	if bottom < height * ownerScale + 8 then
		m:SetPoint('BOTTOMLEFT', owner, 'TOPLEFT', 0, 2)
	else
		m:SetPoint('TOPLEFT', owner, 'BOTTOMLEFT', 0, -2)
	end
	m:Show()
	m:RegisterEvent('GLOBAL_MOUSE_DOWN')
	return m
end

---Close the list (only when owner owns it, if given).
---@param owner? Frame
function Draw.CloseMenu(owner)
	if menu and menu:IsShown() and (owner == nil or menu.owner == owner) then
		menu:Hide()
	end
end

---@param owner Frame
---@return boolean
function Draw.MenuOpenFor(owner)
	return menu ~= nil and menu:IsShown() and menu.owner == owner
end

---True once, right after a click on owner closed its list (so the owner's click does not reopen it).
---@param owner Frame
---@return boolean
function Draw.MenuJustClosedBy(owner)
	if not (menu and menu.closedBy == owner) then
		return false
	end
	menu.closedBy = nil
	local now = GetTime and GetTime() or 0
	return now - (menu.closedAt or 0) < 1
end

---Pick a list row by index, as a click would (Enter in a search box, tests).
---@param index integer
---@return boolean picked
function Draw.PickMenuIndex(index)
	if not (menu and menu:IsShown()) then
		return false
	end
	local row = menu.rows[index]
	if not (row and row.item) or row.item.disabled then
		return false
	end
	PickRow(row)
	return true
end

---Items currently in the list (tests and keyboard picks).
---@return Plates.MenuItem[]|nil
function Draw.MenuItems()
	return menu and menu:IsShown() and menu.items or nil
end

----------------------------------------------------------------------------------------------------
-- AnchorGrid widget
----------------------------------------------------------------------------------------------------

local CELL, GAP = 16, 2
local GRID = CELL * 3 + GAP * 2
local LABEL_H = 18
local READOUT_W = 44
local BODY_W = GRID * 2 + 12 + 8 + READOUT_W
local REPEAT_DELAY, REPEAT_RATE = 0.4, 0.06

local Schema = P.Styles and P.Styles.Schema
local POINTS = (Schema and Schema.POINTS) or { 'TOPLEFT', 'TOP', 'TOPRIGHT', 'LEFT', 'CENTER', 'RIGHT', 'BOTTOMLEFT', 'BOTTOM', 'BOTTOMRIGHT' }
local IS_POINT = {}
for _, point in ipairs(POINTS) do
	IS_POINT[point] = true
end

local POINT_LABELS = {
	TOPLEFT = L['Top left'],
	TOP = L['Top'],
	TOPRIGHT = L['Top right'],
	LEFT = L['Left'],
	CENTER = L['Center'],
	RIGHT = L['Right'],
	BOTTOMLEFT = L['Bottom left'],
	BOTTOM = L['Bottom'],
	BOTTOMRIGHT = L['Bottom right'],
}

-- Nudge pad: column, row, unit x, unit y, arrow direction, tooltip title
local NUDGES = {
	{ 2, 1, 0, 1, 'UP', L['Move up'] },
	{ 1, 2, -1, 0, 'LEFT', L['Move left'] },
	{ 3, 2, 1, 0, 'RIGHT', L['Move right'] },
	{ 2, 3, 0, -1, 'DOWN', L['Move down'] },
}

local function Half(value)
	return math.floor(value * 2 + 0.5) / 2
end

local function FormatOffset(value)
	value = Half(value)
	if value == 0 then
		return '0'
	end
	if value == math.floor(value) then
		return string.format('%d', value)
	end
	return string.format('%.1f', value)
end

local function PaintGrid(self)
	local ar, ag, ab = Draw.Accent()
	for _, cell in ipairs(self.cells) do
		local selected = cell.point == self.point
		if self.disabled then
			Draw.Paint(cell.fill, selected and 'muted' or 'raised', selected and 0.4 or 0.5)
			Draw.BorderColor(cell.border, Draw.Color('line'))
			Draw.Paint(cell.dot, 'faint', 0.6)
		elseif selected then
			cell.fill:SetVertexColor(ar, ag, ab, 0.9)
			Draw.BorderColor(cell.border, ar, ag, ab, 1)
			Draw.Paint(cell.dot, 'onAccent')
		else
			local r, g, b, a = Draw.Color('raised')
			local lift = cell.hovered and 0.05 or 0
			cell.fill:SetVertexColor(r + lift, g + lift, b + lift, a)
			if cell.hovered then
				Draw.BorderColor(cell.border, ar, ag, ab, 0.8)
			else
				Draw.BorderColor(cell.border, Draw.Color('lineStrong'))
			end
			Draw.Paint(cell.dot, cell.hovered and 'text' or 'faint')
		end
	end
end

local function UpdateReadout(self)
	self.xText:SetText(string.format('X %s', FormatOffset(self.x or 0)))
	self.yText:SetText(string.format('Y %s', FormatOffset(self.y or 0)))
	local moved = (self.x or 0) ~= 0 or (self.y or 0) ~= 0
	Draw.SetEnabled(self.reset, moved and not self.disabled)
end

local function ReadOffset(self)
	local arg = self.arg
	if arg and type(arg.offset) == 'function' then
		local x, y = arg.offset()
		self.x, self.y = tonumber(x) or 0, tonumber(y) or 0
	end
end

local function PointLabel(self, point)
	local labels = self.labels
	local text = labels and labels[point]
	if type(text) == 'string' and text ~= '' then
		return text
	end
	return POINT_LABELS[point] or point
end

local function Cell_OnClick(cell)
	local self = cell.obj
	if self.disabled then
		return
	end
	Draw.Sound(856)
	self:SetValue(cell.point)
	self:Fire('OnValueChanged', cell.point)
end

local function Cell_OnEnter(cell)
	cell.hovered = true
	PaintGrid(cell.obj)
	Draw.ShowTooltip(cell, PointLabel(cell.obj, cell.point), L['Click to pin the part to this spot.'])
end

local function Cell_OnLeave(cell)
	cell.hovered = false
	PaintGrid(cell.obj)
	Draw.HideTooltip()
end

local function Cell_OnShow(cell)
	Draw.LayoutBorder(cell.border)
end

local function StopRepeat(button)
	button:SetScript('OnUpdate', nil)
	button.held = nil
end

local function NudgeRepeat(button, elapsed)
	local self = button.obj
	if self.disabled or not button.held then
		StopRepeat(button)
		return
	end
	button.held = button.held + elapsed
	if button.held >= button.nextAt then
		button.nextAt = button.nextAt + REPEAT_RATE
		self:Nudge(button.ux, button.uy, Draw.ShiftDown())
	end
end

local function Nudge_OnMouseDown(button, mouseButton)
	local self = button.obj
	if self.disabled or (mouseButton and mouseButton ~= 'LeftButton') then
		return
	end
	local token = self.token
	self:Nudge(button.ux, button.uy, Draw.ShiftDown())
	-- A widget released by the nudge (its page was rebuilt) does not repeat
	if self.token == token and not self.disabled then
		button.held = 0
		button.nextAt = REPEAT_DELAY
		button:SetScript('OnUpdate', NudgeRepeat)
	end
end

local function NudgeTooltip(self)
	local arg = self.arg or {}
	local step = FormatOffset(tonumber(arg.step) or 0.5)
	local big = FormatOffset(tonumber(arg.bigStep) or 2)
	return string.format(L['Each click moves it %s px. Hold Shift to move %s px.'], step, big)
end

local methods = {
	OnAcquire = function(self)
		self.token = (self.token or 0) + 1
		self.arg = nil
		self.labels = nil
		self.point = nil
		self.x, self.y = 0, 0
		self:SetLabel('')
		self:SetWidth(BODY_W)
		self:SetCustomData(nil)
		self:SetDisabled(false)
	end,

	OnRelease = function(self)
		self.token = (self.token or 0) + 1
		self.arg = nil
		self.labels = nil
		for _, button in ipairs(self.nudges) do
			StopRepeat(button)
		end
		for _, cell in ipairs(self.cells) do
			cell.hovered = false
		end
	end,

	---AceConfig hands the option's arg here (onNudge, offset, onReset, step, bigStep).
	SetCustomData = function(self, arg)
		self.arg = type(arg) == 'table' and arg or nil
		ReadOffset(self)
		local tip = NudgeTooltip(self)
		for _, button in ipairs(self.nudges) do
			Draw.SetTooltip(button, button.title, tip)
		end
		UpdateReadout(self)
	end,

	SetLabel = function(self, text)
		text = text or ''
		local shown = text ~= ''
		self.label:SetText(text)
		self.label:SetShown(shown)
		self.labelHit:SetShown(shown)
		local top = shown and LABEL_H or 0
		self.body:ClearAllPoints()
		self.body:SetPoint('TOPLEFT', self.frame, 'TOPLEFT', 0, -top)
		self:SetHeight(top + GRID + 4)
	end,

	---values: point -> label (the AceConfig select list). Only the labels are used.
	SetList = function(self, values)
		self.labels = type(values) == 'table' and values or nil
	end,

	---A point name, or { point, x, y } for direct use.
	SetValue = function(self, value)
		if type(value) == 'table' then
			local point = value.point or value[1]
			self.point = IS_POINT[point] and point or nil
			self.x = tonumber(value.x or value[2]) or 0
			self.y = tonumber(value.y or value[3]) or 0
			UpdateReadout(self)
		else
			self.point = IS_POINT[value] and value or nil
		end
		PaintGrid(self)
	end,

	---@return string|nil point
	GetValue = function(self)
		return self.point
	end,

	SetOffset = function(self, x, y)
		self.x, self.y = tonumber(x) or 0, tonumber(y) or 0
		UpdateReadout(self)
	end,

	---@return number x, number y
	GetOffset = function(self)
		return self.x or 0, self.y or 0
	end,

	---Move by whole steps: ux and uy are -1, 0 or 1; big uses bigStep.
	Nudge = function(self, ux, uy, big)
		local arg = self.arg or {}
		local step = big and (tonumber(arg.bigStep) or 2) or (tonumber(arg.step) or 0.5)
		self:MoveBy(ux * step, uy * step)
	end,

	---Move by an exact amount (the page that stores it rounds to half pixels).
	MoveBy = function(self, dx, dy)
		if self.disabled or (dx == 0 and dy == 0) then
			return
		end
		local token = self.token
		local arg = self.arg
		if arg and type(arg.onNudge) == 'function' then
			arg.onNudge(dx, dy)
		end
		if self.token ~= token then
			return
		end
		self:Fire('OnNudge', dx, dy)
		if self.token ~= token then
			return
		end
		if arg and type(arg.offset) == 'function' then
			ReadOffset(self)
		else
			self.x, self.y = Half((self.x or 0) + dx), Half((self.y or 0) + dy)
		end
		UpdateReadout(self)
		self:Fire('OnOffsetChanged', self.x, self.y)
	end,

	---Back to no offset.
	ResetOffset = function(self)
		if self.disabled then
			return
		end
		local arg = self.arg
		if not (arg and type(arg.onReset) == 'function') then
			self:MoveBy(-(self.x or 0), -(self.y or 0))
			return
		end
		local token = self.token
		arg.onReset()
		if self.token ~= token then
			return
		end
		if type(arg.offset) == 'function' then
			ReadOffset(self)
		else
			self.x, self.y = 0, 0
		end
		UpdateReadout(self)
		self:Fire('OnOffsetChanged', self.x, self.y)
	end,

	SetDisabled = function(self, disabled)
		self.disabled = disabled and true or false
		for _, cell in ipairs(self.cells) do
			cell:EnableMouse(not self.disabled)
		end
		for _, button in ipairs(self.nudges) do
			Draw.SetEnabled(button, not self.disabled)
			if self.disabled then
				StopRepeat(button)
			end
		end
		Draw.Paint(self.label, self.disabled and 'faint' or 'text')
		Draw.Paint(self.xText, self.disabled and 'faint' or 'muted')
		Draw.Paint(self.yText, self.disabled and 'faint' or 'muted')
		PaintGrid(self)
		UpdateReadout(self)
	end,
}

local function Repaint(widget)
	PaintGrid(widget)
	for _, button in ipairs(widget.nudges) do
		Draw.PaintButton(button)
	end
	Draw.PaintButton(widget.reset)
end

local function Constructor()
	local AceGUI = LibStub('AceGUI-3.0')
	local frame = CreateFrame('Frame', nil, UIParent)
	frame:Hide()

	---@type table
	local widget = { frame = frame, type = Widgets:TypeName('AnchorGrid'), cells = {}, nudges = {} }

	local label = Draw.Text(frame, 12, 'text')
	label:SetPoint('TOPLEFT', 0, -2)
	label:SetPoint('TOPRIGHT', 0, -2)
	widget.label = label

	-- The label carries the option's own tooltip (AceConfig listens to OnEnter and OnLeave)
	local labelHit = CreateFrame('Frame', nil, frame)
	labelHit:SetPoint('TOPLEFT')
	labelHit:SetPoint('TOPRIGHT')
	labelHit:SetHeight(LABEL_H - 2)
	labelHit:EnableMouse(true)
	labelHit:SetScript('OnEnter', function()
		widget:Fire('OnEnter')
	end)
	labelHit:SetScript('OnLeave', function()
		widget:Fire('OnLeave')
	end)
	widget.labelHit = labelHit

	local body = CreateFrame('Frame', nil, frame)
	body:SetPoint('TOPLEFT', 0, -LABEL_H)
	body:SetSize(BODY_W, GRID)
	widget.body = body

	for i, point in ipairs(POINTS) do
		local cell = CreateFrame('Button', nil, body)
		cell:SetSize(CELL, CELL)
		cell:SetPoint('TOPLEFT', ((i - 1) % 3) * (CELL + GAP), -math.floor((i - 1) / 3) * (CELL + GAP))
		cell.fill = Draw.Rect(cell, 'BACKGROUND')
		cell.fill:SetAllPoints()
		cell.border = Draw.Border(cell)
		-- The dot sits where the part would pin, so the grid reads like a map of the plate
		local dx = point:find('LEFT') and 3 or (point:find('RIGHT') and -3 or 0)
		local dy = point:find('TOP') and -3 or (point:find('BOTTOM') and 3 or 0)
		cell.dot = Draw.Rect(cell, 'ARTWORK')
		cell.dot:SetSize(4, 4)
		cell.dot:SetPoint(point, cell, point, dx, dy)
		cell.point = point
		cell.obj = widget
		cell:SetScript('OnClick', Cell_OnClick)
		cell:SetScript('OnEnter', Cell_OnEnter)
		cell:SetScript('OnLeave', Cell_OnLeave)
		cell:SetScript('OnShow', Cell_OnShow)
		widget.cells[i] = cell
	end

	local pad = CreateFrame('Frame', nil, body)
	pad:SetSize(GRID, GRID)
	pad:SetPoint('TOPLEFT', GRID + 12, 0)
	widget.pad = pad

	for i, spec in ipairs(NUDGES) do
		local button = Draw.Button(pad, nil, CELL, CELL)
		button:SetPoint('TOPLEFT', (spec[1] - 1) * (CELL + GAP), -(spec[2] - 1) * (CELL + GAP))
		button.ux, button.uy = spec[3], spec[4]
		button.title = spec[6]
		button.obj = widget
		button.glyph = Draw.Arrow(button, spec[5], 4)
		button.glyph.anchor:SetPoint('CENTER')
		button:SetScript('OnClick', nil)
		button:SetScript('OnMouseDown', Nudge_OnMouseDown)
		button:SetScript('OnMouseUp', StopRepeat)
		button:SetScript('OnHide', StopRepeat)
		Draw.SetTooltip(button, spec[6], nil)
		Draw.PaintButton(button)
		widget.nudges[i] = button
	end

	local reset = Draw.Button(pad, nil, CELL, CELL)
	reset:SetPoint('TOPLEFT', CELL + GAP, -(CELL + GAP))
	reset.icon = Draw.Rect(reset, 'ARTWORK')
	reset.icon:SetSize(4, 4)
	reset.icon:SetPoint('CENTER')
	Draw.Paint(reset.icon, 'text')
	reset.onClick = function()
		widget:ResetOffset()
	end
	Draw.SetTooltip(reset, L['Back to no offset'], nil)
	widget.reset = reset

	local xText = Draw.Text(body, 11, 'muted')
	xText:SetPoint('TOPLEFT', pad, 'TOPRIGHT', 8, -CELL - GAP + 2)
	xText:SetWidth(READOUT_W)
	widget.xText = xText
	local yText = Draw.Text(body, 11, 'muted')
	yText:SetPoint('TOPLEFT', xText, 'BOTTOMLEFT', 0, -3)
	yText:SetWidth(READOUT_W)
	widget.yText = yText

	for name, fn in pairs(methods) do
		widget[name] = fn
	end

	Draw.OnAccent(frame, function()
		Repaint(widget)
	end)

	return AceGUI:RegisterAsWidget(widget)
end

Widgets.types.AnchorGrid = { version = 1, Constructor = Constructor }
