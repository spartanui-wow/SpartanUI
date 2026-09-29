---@class SUI
local SUI = SUI
local Style = SUI.UI.Style
local W = SUI.UI.OptionWidgets

-- TabGroup replacement: flat text tabs over a hairline; the selected tab has an accent underline.
-- Same methods, callbacks and events as the stock AceGUI TabGroup.

local Type, Version = 'SUI-TabGroup', 1
local AceGUI = LibStub and LibStub('AceGUI-3.0', true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then
	return
end

local pairs, ipairs, assert, type, wipe = pairs, ipairs, assert, type, wipe

local TAB_H = 26
local TAB_PAD = 24
local TAB_GAP = 2
local TITLE_H = 20
local PAD_X = 2
local PAD_TOP = 10
local PAD_BOTTOM = 4

-- local upvalue storage used by BuildTabs
local widths = {}
local rowends = {}

----------------------------------------------------------------------------------------------------
-- Tabs
----------------------------------------------------------------------------------------------------

local function PaintTab(tab)
	local c = Style.color
	local r, g, b = Style:GetAccent()
	local hovered = tab.hovered and not tab.disabled and not tab.selected
	tab.underline:SetShown(tab.selected and not tab.disabled)
	tab.underline:SetVertexColor(r, g, b, 1)
	tab.fill:SetShown(hovered)
	W.Paint(tab.fill, c.hover)
	if tab.disabled then
		W.Paint(tab.text, c.faint)
	elseif tab.selected then
		W.Paint(tab.text, c.text)
	elseif hovered then
		W.Paint(tab.text, W.Mix(c.text, c.muted, 0.2))
	else
		W.Paint(tab.text, c.muted)
	end
end

local function Tab_SetText(tab, text)
	tab.text:SetText(text)
	tab:SetWidth(Style:MeasureText(tab.text) + TAB_PAD)
end

local function Tab_SetSelected(tab, selected)
	tab.selected = selected
	PaintTab(tab)
end

local function Tab_SetDisabled(tab, disabled)
	tab.disabled = disabled
	PaintTab(tab)
end

local function BuildTabsOnUpdate(frame)
	local self = frame.obj
	self:BuildTabs()
	frame:SetScript('OnUpdate', nil)
end

----------------------------------------------------------------------------------------------------
-- Scripts
----------------------------------------------------------------------------------------------------

local function Tab_OnClick(frame)
	if not (frame.selected or frame.disabled) then
		W.Sound(841) -- SOUNDKIT.IG_CHARACTER_INFO_TAB
		frame.obj:SelectTab(frame.value)
	end
end

local function Tab_OnEnter(frame)
	local self = frame.obj
	frame.hovered = true
	PaintTab(frame)
	self:Fire('OnTabEnter', self.tabs[frame.id].value, frame)
end

local function Tab_OnLeave(frame)
	local self = frame.obj
	frame.hovered = false
	PaintTab(frame)
	self:Fire('OnTabLeave', self.tabs[frame.id].value, frame)
end

-- Tab widths come from text measurements, which can read 0 until the font has been drawn once
local function Frame_OnShow(frame)
	frame:SetScript('OnUpdate', BuildTabsOnUpdate)
end

----------------------------------------------------------------------------------------------------
-- Methods
----------------------------------------------------------------------------------------------------

local methods = {
	OnAcquire = function(self)
		self:SetTitle()
	end,

	OnRelease = function(self)
		self.status = nil
		for k in pairs(self.localstatus) do
			self.localstatus[k] = nil
		end
		self.tablist = nil
		for _, tab in pairs(self.tabs) do
			tab.hovered = false
			tab:Hide()
		end
	end,

	CreateTab = function(self, id)
		local tabname = ('SUI_OptionsTabGroup%dTab%d'):format(self.num, id)
		local tab = CreateFrame('Button', tabname, self.frame)
		tab:SetSize(115, TAB_H)

		tab.fill = W:CreateRect(tab, 'BACKGROUND')
		tab.fill:SetAllPoints()
		tab.underline = W:CreateRect(tab, 'ARTWORK')
		tab.underline:SetPoint('BOTTOMLEFT', 0, 0)
		tab.underline:SetPoint('BOTTOMRIGHT', 0, 0)
		tab.underline:SetHeight(2)

		tab.text = Style:CreateText(tab, W.LABEL_SIZE)
		tab.text:SetPoint('LEFT', TAB_PAD / 2, 1)
		tab.text:SetPoint('RIGHT', -TAB_PAD / 2, 1)
		tab.text:SetWordWrap(false)
		tab.Text = tab.text -- compat
		tab:SetFontString(tab.text)
		tab:SetPushedTextOffset(0, 0)

		tab.obj = self
		tab.id = id

		tab:SetScript('OnClick', Tab_OnClick)
		tab:SetScript('OnEnter', Tab_OnEnter)
		tab:SetScript('OnLeave', Tab_OnLeave)

		tab.SetText = Tab_SetText
		tab.SetSelected = Tab_SetSelected
		tab.SetDisabled = Tab_SetDisabled

		return tab
	end,

	SetTitle = function(self, text)
		self.titletext:SetText(text or '')
		if text and text ~= '' then
			self.alignoffset = 25
		else
			self.alignoffset = 18
		end
		self:BuildTabs()
	end,

	SetStatusTable = function(self, status)
		assert(type(status) == 'table')
		self.status = status
	end,

	SelectTab = function(self, value)
		local status = self.status or self.localstatus
		local found
		for i, v in ipairs(self.tabs) do
			if v.value == value then
				v:SetSelected(true)
				found = true
			else
				v:SetSelected(false)
			end
		end
		status.selected = value
		if found then
			self:Fire('OnGroupSelected', value)
		end
	end,

	SetTabs = function(self, tabs)
		self.tablist = tabs
		self:BuildTabs()
	end,

	BuildTabs = function(self)
		local hastitle = (self.titletext:GetText() and self.titletext:GetText() ~= '')
		local tablist = self.tablist
		local tabs = self.tabs
		local titleOffset = hastitle and TITLE_H or 0

		if not tablist then
			self.rule:Hide()
			return
		end

		local width = self.frame.width or self.frame:GetWidth() or 0

		wipe(widths)
		wipe(rowends)

		for i, v in ipairs(tablist) do
			local tab = tabs[i]
			if not tab then
				tab = self:CreateTab(i)
				tabs[i] = tab
			end

			tab:Show()
			tab:SetText(v.text)
			tab:SetDisabled(v.disabled)
			tab.value = v.value

			widths[i] = tab:GetWidth()
		end

		for i = #tablist + 1, #tabs, 1 do
			tabs[i]:Hide()
		end

		-- rows: wrap when the next tab does not fit
		local numrows = 1
		local usedwidth = 0
		for i = 1, #tablist do
			if usedwidth ~= 0 and (width - usedwidth - widths[i]) < 0 then
				rowends[numrows] = i - 1
				numrows = numrows + 1
				usedwidth = 0
			end
			usedwidth = usedwidth + widths[i] + TAB_GAP
		end
		rowends[numrows] = #tablist

		local starttab = 1
		for row, endtab in ipairs(rowends) do
			for tabno = starttab, endtab do
				local tab = tabs[tabno]
				tab:ClearAllPoints()
				if tabno == starttab then
					tab:SetPoint('TOPLEFT', self.frame, 'TOPLEFT', 0, -(titleOffset + (row - 1) * TAB_H))
				else
					tab:SetPoint('LEFT', tabs[tabno - 1], 'RIGHT', TAB_GAP, 0)
				end
			end
			starttab = endtab + 1
		end

		local stripHeight = titleOffset + numrows * TAB_H
		self.rule:ClearAllPoints()
		self.rule:SetPoint('TOPLEFT', self.frame, 'TOPLEFT', 0, -stripHeight)
		self.rule:SetPoint('TOPRIGHT', self.frame, 'TOPRIGHT', 0, -stripHeight)
		self.rule:SetHeight(Style:PixelSize(self.frame))
		self.rule:Show()

		self.borderoffset = stripHeight
		self.border:SetPoint('TOPLEFT', 0, -self.borderoffset)
	end,

	OnWidthSet = function(self, width)
		local content = self.content
		local contentwidth = width - PAD_X * 2
		if contentwidth < 0 then
			contentwidth = 0
		end
		content:SetWidth(contentwidth)
		content.width = contentwidth
		self:BuildTabs(self)
		self.frame:SetScript('OnUpdate', BuildTabsOnUpdate)
	end,

	OnHeightSet = function(self, height)
		local content = self.content
		local contentheight = height - (self.borderoffset + PAD_TOP + PAD_BOTTOM)
		if contentheight < 0 then
			contentheight = 0
		end
		content:SetHeight(contentheight)
		content.height = contentheight
	end,

	LayoutFinished = function(self, width, height)
		if self.noAutoHeight then
			return
		end
		self:SetHeight((height or 0) + (self.borderoffset + PAD_TOP + PAD_BOTTOM))
	end,
}

----------------------------------------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------------------------------------

local function Constructor()
	local num = AceGUI:GetNextWidgetNum(Type)
	local frame = CreateFrame('Frame', nil, UIParent)
	frame:SetHeight(100)
	frame:SetWidth(100)
	frame:SetFrameStrata('FULLSCREEN_DIALOG')
	frame:SetScript('OnShow', Frame_OnShow)

	local titletext = Style:CreateText(frame, W.SMALL_SIZE, Style.color.muted)
	titletext:SetPoint('TOPLEFT', 2, 0)
	titletext:SetPoint('TOPRIGHT', -2, 0)
	titletext:SetJustifyH('LEFT')
	titletext:SetHeight(TITLE_H - 4)
	titletext:SetText('')

	local rule = W:CreateRect(frame, 'BACKGROUND')
	W.Paint(rule, Style.color.lineStrong)
	rule:Hide()

	local border = CreateFrame('Frame', nil, frame)
	border:SetPoint('TOPLEFT', 0, -TAB_H)
	border:SetPoint('BOTTOMRIGHT', 0, 0)

	local content = CreateFrame('Frame', nil, border)
	content:SetPoint('TOPLEFT', PAD_X, -PAD_TOP)
	content:SetPoint('BOTTOMRIGHT', -PAD_X, PAD_BOTTOM)

	local widget = {
		num = num,
		frame = frame,
		localstatus = {},
		alignoffset = 18,
		titletext = titletext,
		rule = rule,
		border = border,
		borderoffset = TAB_H,
		tabs = {},
		content = content,
		baseType = 'TabGroup',
		type = Type,
	}
	for method, func in pairs(methods) do
		widget[method] = func
	end
	Style:OnAccentChanged(frame, function()
		for _, tab in ipairs(widget.tabs) do
			PaintTab(tab)
		end
	end)

	return AceGUI:RegisterAsContainer(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
