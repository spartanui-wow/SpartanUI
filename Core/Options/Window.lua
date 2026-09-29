---@class SUI
local SUI = SUI
local L = SUI.L
local Style = SUI.UI.Style

-- SpartanUI's options window. AceConfigDialog fills the content area; the window adds a
-- sidebar that picks the top level page, a search box, a dock above the content for a live
-- preview (the Stage), and a footer for actions.

local Type, Version = 'SUI-Window', 1
local AceGUI = LibStub and LibStub('AceGUI-3.0', true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then
	return
end

local HEADER = 42
local FOOTER = 40
local SIDEBAR = 196
local NAV_HEIGHT = 26
local MIN_W, MIN_H = 760, 460

local function SaveStatus(frame)
	local self = frame.obj
	local status = self.status or self.localstatus
	status.width = frame:GetWidth()
	status.height = frame:GetHeight()
	status.top = frame:GetTop()
	status.left = frame:GetLeft()
end

----------------------------------------------------------------------------------------------------
-- Sidebar buttons
----------------------------------------------------------------------------------------------------

local function PaintNav(button)
	local c = Style.color
	local r, g, b = Style:GetAccent()
	if button.selected then
		button.fill:SetVertexColor(1, 1, 1, 0.07)
		button.bar:SetVertexColor(r, g, b, 1)
		button.bar:Show()
		button.label:SetTextColor(c.text[1], c.text[2], c.text[3])
	else
		button.fill:SetVertexColor(1, 1, 1, button.hovered and 0.04 or 0)
		button.bar:Hide()
		local tc = button.disabled and c.faint or (button.hovered and c.text or c.muted)
		button.label:SetTextColor(tc[1], tc[2], tc[3])
	end
end

local function CreateNavButton(window)
	local button = CreateFrame('Button', nil, window.navList)
	button:SetHeight(NAV_HEIGHT)
	button.fill = Style:CreateFill(button, { 1, 1, 1, 0 })
	button.bar = button:CreateTexture(nil, 'OVERLAY')
	button.bar:SetTexture(Style.WHITE)
	button.bar:SetPoint('TOPLEFT')
	button.bar:SetPoint('BOTTOMLEFT')
	button.bar:SetWidth(Style:PixelSize(button) * 3)
	button.label = Style:CreateText(button, 12)
	button.label:SetPoint('LEFT', 14, 0)
	button.label:SetPoint('RIGHT', -8, 0)
	button.label:SetJustifyH('LEFT')
	button.label:SetWordWrap(false)
	button.sub = Style:CreateText(button, 9, Style.color.faint)
	button.sub:SetPoint('BOTTOMLEFT', button.label, 'BOTTOMLEFT', 0, -10)
	button.sub:SetPoint('RIGHT', -8, 0)
	button.sub:SetJustifyH('LEFT')
	button.sub:SetWordWrap(false)
	button:SetScript('OnEnter', function(self)
		self.hovered = true
		PaintNav(self)
	end)
	button:SetScript('OnLeave', function(self)
		self.hovered = false
		PaintNav(self)
	end)
	button:SetScript('OnClick', function(self)
		if self.disabled then
			return
		end
		if self.onClick then
			self.onClick(self)
		end
	end)
	return button
end

----------------------------------------------------------------------------------------------------
-- Methods
----------------------------------------------------------------------------------------------------

local methods = {
	OnAcquire = function(self)
		self.frame:SetParent(UIParent)
		self.frame:SetFrameStrata('FULLSCREEN_DIALOG')
		self.frame:SetFrameLevel(100)
		self:SetTitle()
		self:ApplyStatus()
		self:SetStageHeight(0)
		self:Show()
	end,

	OnRelease = function(self)
		self.status = nil
		wipe(self.localstatus)
		self.navTabs = nil
		self.page = nil
		self:ClearSearch()
	end,

	OnWidthSet = function(self, width)
		local content = self.content
		local contentwidth = math.max(0, width - SIDEBAR - 24)
		content:SetWidth(contentwidth)
		content.width = contentwidth
	end,

	OnHeightSet = function(self, height)
		local content = self.content
		local stageGap = self.stageHeight > 0 and (self.stageHeight + 8) or 0
		local contentheight = math.max(0, height - HEADER - 10 - stageGap - FOOTER - 4)
		content:SetHeight(contentheight)
		content.height = contentheight
	end,

	SetTitle = function(self, title)
		self.titletext:SetText(title or '')
	end,

	SetStatusText = function(self, text) end,

	Hide = function(self)
		self.frame:Hide()
	end,

	Show = function(self)
		self.frame:Show()
	end,

	EnableResize = function(self, state)
		self.sizer:SetShown(state and true or false)
	end,

	SetStatusTable = function(self, status)
		assert(type(status) == 'table')
		self.status = status
		self:ApplyStatus()
	end,

	ApplyStatus = function(self)
		local status = self.status or self.localstatus
		local frame = self.frame
		self:SetWidth(math.max(MIN_W, status.width or 1000))
		self:SetHeight(math.max(MIN_H, status.height or 700))
		frame:ClearAllPoints()
		if status.top and status.left then
			frame:SetPoint('TOP', UIParent, 'BOTTOM', 0, status.top)
			frame:SetPoint('LEFT', UIParent, 'LEFT', status.left, 0)
		else
			frame:SetPoint('CENTER')
		end
	end,

	---Height of the preview dock above the content (0 hides it)
	---@param height number
	SetStageHeight = function(self, height)
		self.stageHeight = math.max(0, height or 0)
		self.stage:SetHeight(math.max(0.001, self.stageHeight))
		self.stage:SetShown(self.stageHeight > 0)
		self.content:ClearAllPoints()
		self.content:SetPoint('TOPLEFT', self.stage, 'BOTTOMLEFT', 0, self.stageHeight > 0 and -8 or 0)
		self.content:SetPoint('BOTTOMRIGHT', self.frame, 'BOTTOMRIGHT', -12, FOOTER + 4)
		self:OnHeightSet(self.frame:GetHeight())
		self:DoLayout()
	end,

	---Show the top level pages in the sidebar
	---@param tabs table[] { value, text, disabled }
	---@param page table The page group that shows the selected page
	SetNavigation = function(self, tabs, page)
		self.navTabs = tabs
		self.page = page
		if not self.searching then
			self:RefreshNav()
		end
	end,

	RefreshNav = function(self)
		local tabs = self.navTabs or {}
		local selected = self.page and self.page:GetSelected()
		for i, tab in ipairs(tabs) do
			local button = self.navButtons[i] or CreateNavButton(self)
			self.navButtons[i] = button
			button:ClearAllPoints()
			button:SetPoint('TOPLEFT', self.navList, 'TOPLEFT', 0, -(i - 1) * NAV_HEIGHT)
			button:SetPoint('RIGHT', self.navList, 'RIGHT', 0, 0)
			button:SetHeight(NAV_HEIGHT)
			button.label:ClearAllPoints()
			button.label:SetPoint('LEFT', 14, 0)
			button.label:SetPoint('RIGHT', -8, 0)
			button.label:SetText(tab.text)
			button.sub:SetText('')
			button.value = tab.value
			button.disabled = tab.disabled
			button.selected = tab.value == selected
			button.onClick = function(btn)
				if self.page then
					self.page:SelectTab(btn.value)
					self:RefreshNav()
				end
			end
			button:Show()
			PaintNav(button)
		end
		for i = #tabs + 1, #self.navButtons do
			self.navButtons[i]:Hide()
		end
		self.navList:SetHeight(math.max(1, #tabs * NAV_HEIGHT))
	end,

	---Show search results in the sidebar
	---@param results table[] { text, sub, onClick }
	ShowResults = function(self, results)
		self.searching = true
		for i, result in ipairs(results) do
			local button = self.navButtons[i] or CreateNavButton(self)
			self.navButtons[i] = button
			button:ClearAllPoints()
			button:SetPoint('TOPLEFT', self.navList, 'TOPLEFT', 0, -(i - 1) * (NAV_HEIGHT + 10))
			button:SetPoint('RIGHT', self.navList, 'RIGHT', 0, 0)
			button:SetHeight(NAV_HEIGHT + 10)
			button.label:ClearAllPoints()
			button.label:SetPoint('TOPLEFT', 14, -5)
			button.label:SetPoint('RIGHT', -8, 0)
			button.label:SetText(result.text)
			button.sub:SetText(result.sub or '')
			button.disabled = false
			button.selected = false
			button.onClick = result.onClick
			button:Show()
			PaintNav(button)
		end
		for i = #results + 1, #self.navButtons do
			self.navButtons[i]:Hide()
		end
		self.noResults:SetShown(#results == 0)
		self.navList:SetHeight(math.max(1, #results * (NAV_HEIGHT + 10)))
	end,

	ClearSearch = function(self)
		self.searching = false
		self.noResults:Hide()
		if self.searchBox:GetText() ~= '' then
			self.searchBox:SetText('')
		end
		self:RefreshNav()
	end,
}

----------------------------------------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------------------------------------

local function Constructor()
	local frame = CreateFrame('Frame', 'SUI_OptionsWindow', UIParent)
	frame:Hide()
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:SetClampedToScreen(true)
	frame:SetFrameStrata('FULLSCREEN_DIALOG')
	frame:SetFrameLevel(100)
	frame:SetToplevel(true)
	if frame.SetResizeBounds then
		frame:SetResizeBounds(MIN_W, MIN_H)
	elseif frame.SetMinResize then
		frame:SetMinResize(MIN_W, MIN_H)
	end
	if frame.SetDontSavePosition then
		frame:SetDontSavePosition(true)
	end
	tinsert(UISpecialFrames, 'SUI_OptionsWindow')

	Style:SkinPanel(frame, Style.color.pane, Style.color.lineStrong)

	frame:SetScript('OnShow', function(self)
		self.obj:Fire('OnShow')
	end)
	frame:SetScript('OnHide', function(self)
		self.obj:Fire('OnClose')
	end)
	frame:SetScript('OnMouseDown', function()
		AceGUI:ClearFocus()
	end)

	-- Header: drag handle, logo, title, close
	local header = CreateFrame('Frame', nil, frame)
	header:SetPoint('TOPLEFT')
	header:SetPoint('TOPRIGHT')
	header:SetHeight(HEADER)
	header:EnableMouse(true)
	header:SetScript('OnMouseDown', function()
		frame:StartMoving()
		AceGUI:ClearFocus()
	end)
	header:SetScript('OnMouseUp', function()
		frame:StopMovingOrSizing()
		SaveStatus(frame)
	end)
	Style:CreateFill(header, Style.color.header)

	local logo = header:CreateTexture(nil, 'ARTWORK')
	logo:SetTexture('Interface\\AddOns\\SpartanUI\\images\\setup\\SUISetup')
	logo:SetTexCoord(0, 0.611328125, 0, 0.6640625)
	logo:SetSize(96, 28)
	logo:SetPoint('LEFT', 12, 0)

	local titletext = Style:CreateText(header, 13, Style.color.muted)
	titletext:SetPoint('LEFT', logo, 'RIGHT', 10, 0)

	local accentLine = header:CreateTexture(nil, 'OVERLAY')
	accentLine:SetTexture(Style.WHITE)
	accentLine:SetPoint('BOTTOMLEFT')
	accentLine:SetPoint('BOTTOMRIGHT')
	accentLine:SetHeight(Style:PixelSize(header) * 2)

	local close = CreateFrame('Button', nil, header)
	close:SetSize(30, 30)
	close:SetPoint('RIGHT', -6, 0)
	close.label = Style:CreateText(close, 14, Style.color.muted)
	close.label:SetPoint('CENTER')
	close.label:SetText('x')
	close:SetScript('OnEnter', function(self)
		self.label:SetTextColor(Style.color.text[1], Style.color.text[2], Style.color.text[3])
	end)
	close:SetScript('OnLeave', function(self)
		self.label:SetTextColor(Style.color.muted[1], Style.color.muted[2], Style.color.muted[3])
	end)
	close:SetScript('OnClick', function()
		PlaySound(799)
		frame.obj:Hide()
	end)

	-- Sidebar
	local sidebar = CreateFrame('Frame', nil, frame)
	sidebar:SetPoint('TOPLEFT', header, 'BOTTOMLEFT', 0, 0)
	sidebar:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 0, FOOTER)
	sidebar:SetWidth(SIDEBAR)
	Style:CreateFill(sidebar, Style.color.raised)
	local sideRule = sidebar:CreateTexture(nil, 'ARTWORK')
	sideRule:SetTexture(Style.WHITE)
	sideRule:SetPoint('TOPRIGHT')
	sideRule:SetPoint('BOTTOMRIGHT')
	sideRule:SetWidth(Style:PixelSize(sidebar))
	sideRule:SetVertexColor(unpack(Style.color.line))

	local searchBox = CreateFrame('EditBox', nil, sidebar)
	searchBox:SetHeight(24)
	searchBox:SetPoint('TOPLEFT', 10, -10)
	searchBox:SetPoint('TOPRIGHT', -10, -10)
	searchBox:SetAutoFocus(false)
	searchBox:SetTextInsets(8, 22, 0, 0)
	Style:SetFont(searchBox, 12)
	searchBox:SetTextColor(Style.color.text[1], Style.color.text[2], Style.color.text[3])
	Style:CreateFill(searchBox, Style.color.input)
	searchBox.border = Style:CreateBorder(searchBox)
	searchBox.border:SetColor(unpack(Style.color.lineStrong))
	local placeholder = Style:CreateText(searchBox, 12, Style.color.faint)
	placeholder:SetPoint('LEFT', 8, 0)
	placeholder:SetText(L['Search settings'])
	local clear = CreateFrame('Button', nil, searchBox)
	clear:SetSize(20, 20)
	clear:SetPoint('RIGHT', -2, 0)
	clear.label = Style:CreateText(clear, 12, Style.color.muted)
	clear.label:SetPoint('CENTER')
	clear.label:SetText('x')
	clear:Hide()

	local navScroll = CreateFrame('ScrollFrame', nil, sidebar)
	navScroll:SetPoint('TOPLEFT', searchBox, 'BOTTOMLEFT', -10, -10)
	navScroll:SetPoint('BOTTOMRIGHT', sidebar, 'BOTTOMRIGHT', -1, 6)
	navScroll:EnableMouseWheel(true)
	local navList = CreateFrame('Frame', nil, navScroll)
	navList:SetSize(SIDEBAR - 1, 1)
	navScroll:SetScrollChild(navList)
	navScroll:SetScript('OnMouseWheel', function(self, delta)
		local maxScroll = math.max(0, navList:GetHeight() - self:GetHeight())
		local value = math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * NAV_HEIGHT * 2))
		self:SetVerticalScroll(value)
	end)
	navScroll:SetScript('OnSizeChanged', function(self, width)
		navList:SetWidth(width or SIDEBAR - 1)
	end)

	local noResults = Style:CreateText(sidebar, 11, Style.color.faint)
	noResults:SetPoint('TOPLEFT', navScroll, 'TOPLEFT', 14, -6)
	noResults:SetPoint('RIGHT', sidebar, 'RIGHT', -10, 0)
	noResults:SetJustifyH('LEFT')
	noResults:SetText(L['Nothing found. Try another word.'])
	noResults:Hide()

	-- Preview dock and content
	local stage = CreateFrame('Frame', nil, frame)
	stage:SetPoint('TOPLEFT', sidebar, 'TOPRIGHT', 12, -10)
	stage:SetPoint('RIGHT', frame, 'RIGHT', -12, 0)
	stage:SetHeight(0.001)
	stage:Hide()
	Style:SkinPanel(stage, Style.color.raised, Style.color.line)

	local content = CreateFrame('Frame', nil, frame)

	-- Footer
	local footer = CreateFrame('Frame', nil, frame)
	footer:SetPoint('BOTTOMLEFT')
	footer:SetPoint('BOTTOMRIGHT')
	footer:SetHeight(FOOTER)
	Style:CreateFill(footer, Style.color.header)
	local footRule = footer:CreateTexture(nil, 'ARTWORK')
	footRule:SetTexture(Style.WHITE)
	footRule:SetPoint('TOPLEFT')
	footRule:SetPoint('TOPRIGHT')
	footRule:SetHeight(Style:PixelSize(footer))
	footRule:SetVertexColor(unpack(Style.color.line))

	local sizer = CreateFrame('Frame', nil, frame)
	sizer:SetSize(16, 16)
	sizer:SetPoint('BOTTOMRIGHT')
	sizer:SetFrameLevel(footer:GetFrameLevel() + 5)
	sizer:EnableMouse(true)
	for i = 1, 3 do
		local dot = sizer:CreateTexture(nil, 'OVERLAY')
		dot:SetTexture(Style.WHITE)
		dot:SetVertexColor(Style.color.faint[1], Style.color.faint[2], Style.color.faint[3], 0.8)
		dot:SetSize(2, 2)
		dot:SetPoint('BOTTOMRIGHT', -3 - (i - 1) * 4, 3)
		if i > 1 then
			local up = sizer:CreateTexture(nil, 'OVERLAY')
			up:SetTexture(Style.WHITE)
			up:SetVertexColor(Style.color.faint[1], Style.color.faint[2], Style.color.faint[3], 0.8)
			up:SetSize(2, 2)
			up:SetPoint('BOTTOMRIGHT', -3, 3 + (i - 1) * 4)
		end
	end
	sizer:SetScript('OnMouseDown', function()
		frame:StartSizing('BOTTOMRIGHT')
		AceGUI:ClearFocus()
	end)
	sizer:SetScript('OnMouseUp', function()
		frame:StopMovingOrSizing()
		SaveStatus(frame)
	end)

	local widget = {
		localstatus = {},
		titletext = titletext,
		content = content,
		frame = frame,
		header = header,
		sidebar = sidebar,
		searchBox = searchBox,
		navScroll = navScroll,
		navList = navList,
		navButtons = {},
		noResults = noResults,
		stage = stage,
		stageHeight = 0,
		footer = footer,
		sizer = sizer,
		type = Type,
		baseType = 'Frame',
	}
	for method, func in pairs(methods) do
		widget[method] = func
	end

	-- Search
	local pending
	searchBox:SetScript('OnTextChanged', function(self, userInput)
		local text = self:GetText() or ''
		placeholder:SetShown(text == '' and not self:HasFocus())
		clear:SetShown(text ~= '')
		if not userInput then
			return
		end
		if pending then
			pending:Cancel()
		end
		pending = C_Timer.NewTimer(0.15, function()
			pending = nil
			if SUI.OptionsWindow and SUI.OptionsWindow.Search then
				SUI.OptionsWindow.Search:Run(widget, text)
			end
		end)
	end)
	searchBox:SetScript('OnEditFocusGained', function(self)
		local r, g, b = Style:GetAccent()
		self.border:SetColor(r, g, b, 1)
		placeholder:Hide()
	end)
	searchBox:SetScript('OnEditFocusLost', function(self)
		self.border:SetColor(unpack(Style.color.lineStrong))
		placeholder:SetShown((self:GetText() or '') == '')
	end)
	searchBox:SetScript('OnEscapePressed', function(self)
		if (self:GetText() or '') ~= '' then
			widget:ClearSearch()
		end
		self:ClearFocus()
	end)
	searchBox:SetScript('OnEnterPressed', function(self)
		self:ClearFocus()
		local first = widget.searching and widget.navButtons[1]
		if first and first:IsShown() and first.onClick then
			first.onClick(first)
		end
	end)
	clear:SetScript('OnClick', function()
		widget:ClearSearch()
	end)

	Style:OnAccentChanged(frame, function(r, g, b)
		accentLine:SetVertexColor(r, g, b, 1)
		for _, button in ipairs(widget.navButtons) do
			if button:IsShown() then
				PaintNav(button)
			end
		end
	end)

	local registered = AceGUI:RegisterAsContainer(widget)
	registered:SetStageHeight(0)
	return registered
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
