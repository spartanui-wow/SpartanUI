---@class SUI
local SUI = SUI
local L = SUI.L
local Style = SUI.UI.Style
local W = SUI.UI.OptionWidgets

-- SpartanUI's options window. AceConfigDialog fills the content area; the window adds a
-- sidebar with the tree of pages and sub-pages, a search box, a preview panel beside it (the
-- Stage), and a footer for actions. Its frame, bars and panels come from the active window kit.

local Type, Version = 'SUI-Window', 2
local AceGUI = LibStub and LibStub('AceGUI-3.0', true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then
	return
end

local SIDEBAR = 196
-- Space between the content panel's edge and the settings inside it
local CONTENT_PAD = 10
local NAV_HEIGHT = 26
local SUB_HEIGHT = 22
local INDENT = 12
local SEP = '\001'
-- Small enough for any screen, large enough that the sidebar, page title and footer never meet
local MIN_W, MIN_H = 760, 460
-- Room the settings keep when a preview panel opens beside them
local STAGE_GAP = 4

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
	local toggle = button.toggle
	if toggle and toggle:IsShown() then
		local gc = toggle.hovered and c.text or c.muted
		toggle.glyph:SetColor(gc[1], gc[2], gc[3], 1)
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

	-- Opens and closes a page's sub-pages without selecting it
	local toggle = CreateFrame('Button', nil, button)
	toggle:SetSize(18, 18)
	toggle:SetPoint('RIGHT', -6, 0)
	toggle.glyph = W:CreatePlusMinus(toggle)
	toggle.glyph.anchor:SetPoint('CENTER', toggle, 'CENTER', 0, 0)
	toggle:SetScript('OnEnter', function(self)
		self.hovered = true
		PaintNav(button)
	end)
	toggle:SetScript('OnLeave', function(self)
		self.hovered = false
		PaintNav(button)
	end)
	toggle:SetScript('OnClick', function()
		if button.onToggle then
			button.onToggle(button)
		end
	end)
	toggle:Hide()
	button.toggle = toggle
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
		self:RaiseFooter()
		self:SetTitle()
		self:ApplyStatus()
		self:SetStageWidth(0)
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
		local layout = LibAT.UI.Kit:GetActive().layout
		local content = self.content
		local contentwidth = math.max(0, width - layout.sideInset * 2 - SIDEBAR - 12 - CONTENT_PAD * 2)
		content:SetWidth(contentwidth)
		content.width = contentwidth
	end,

	OnHeightSet = function(self, height)
		local layout = LibAT.UI.Kit:GetActive().layout
		local content = self.content
		local chrome = layout.barInset * 2 + layout.titleHeight + layout.footerHeight + 18
		local contentheight = math.max(0, height - chrome - CONTENT_PAD * 2)
		content:SetHeight(contentheight)
		content.height = contentheight
	end,

	SetTitle = function(self, title)
		self.titletext:SetText(title or '')
	end,

	SetStatusText = function(self, text) end,

	---The footer sits above the settings so its buttons are never covered
	RaiseFooter = function(self)
		self.footer:SetFrameLevel(self.frame:GetFrameLevel() + 30)
	end,

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

	---Width of the preview panel attached to the window's side (0 hides it). The panel sits
	---outside the window, so the settings keep their full width.
	---@param width number
	SetStageWidth = function(self, width)
		width = math.max(0, width or 0)
		if width == self.stageWidth then
			return
		end
		self.stageWidth = width
		self.stage:SetWidth(math.max(0.001, width))
		self.stage:SetShown(width > 0)
		self:PlaceStage()
	end,

	---Attach the preview panel to the right edge, or the left edge when the right has no room
	PlaceStage = function(self)
		local frame, stage = self.frame, self.stage
		local right, left = frame:GetRight(), frame:GetLeft()
		local screen = UIParent:GetRight() or UIParent:GetWidth()
		local width = math.max(0, self.stageWidth or 0)
		local onLeft = right and left and (right + STAGE_GAP + width > screen) and (left - STAGE_GAP - width >= 0)
		stage:ClearAllPoints()
		if onLeft then
			stage:SetPoint('TOPRIGHT', frame, 'TOPLEFT', -STAGE_GAP, 0)
			stage:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMLEFT', -STAGE_GAP, 0)
		else
			stage:SetPoint('TOPLEFT', frame, 'TOPRIGHT', STAGE_GAP, 0)
			stage:SetPoint('BOTTOMLEFT', frame, 'BOTTOMRIGHT', STAGE_GAP, 0)
		end
	end,

	---Show the tree of pages in the sidebar
	---@param tabs table[] { value, text, disabled, empty?, children? }
	---@param page table The page group that shows the selected page
	SetNavigation = function(self, tabs, page)
		self.navTabs = tabs
		self.page = page
		if not self.searching then
			self:RefreshNav(true)
		end
	end,

	---Rows of the sidebar tree that are on show: every page, and the sub-pages of open pages
	---@return table[] rows { entry, value, level, hasChildren, expanded }
	GetNavRows = function(self)
		local rows = {}
		local page = self.page
		local function Add(list, level, parent)
			for _, entry in ipairs(list) do
				local value = parent and (parent .. SEP .. entry.value) or entry.value
				local hasChildren = entry.children ~= nil and #entry.children > 0
				local expanded = hasChildren and page ~= nil and page:IsExpanded(value)
				rows[#rows + 1] = { entry = entry, value = value, level = level, hasChildren = hasChildren, expanded = expanded }
				if expanded then
					Add(entry.children, level + 1, value)
				end
			end
		end
		Add(self.navTabs or {}, 1)
		return rows
	end,

	---Select a sidebar entry: open its sub-pages and show its settings
	---@param row table
	SelectNav = function(self, row)
		local page = self.page
		if not page then
			return
		end
		-- A page with nothing of its own just opens and closes
		if row.hasChildren and row.entry.empty and row.expanded then
			page:SetExpanded(row.value, false)
			self:RefreshNav()
			return
		end
		if row.hasChildren then
			page:SetExpanded(row.value, true)
		end
		page:SelectTab(row.value)
		self:RefreshNav(true)
	end,

	---@param reveal? boolean Scroll the sidebar so the selected entry is in view
	RefreshNav = function(self, reveal)
		local rows = self:GetNavRows()
		local selected = self.page and self.page:GetSelected()
		local y, selectedTop, selectedBottom = 0, nil, nil
		for i, row in ipairs(rows) do
			local button = self.navButtons[i] or CreateNavButton(self)
			self.navButtons[i] = button
			local height = row.level == 1 and NAV_HEIGHT or SUB_HEIGHT
			button:ClearAllPoints()
			button:SetPoint('TOPLEFT', self.navList, 'TOPLEFT', 0, -y)
			button:SetPoint('RIGHT', self.navList, 'RIGHT', 0, 0)
			button:SetHeight(height)
			Style:SetFont(button.label, row.level == 1 and 12 or 11)
			button.label:ClearAllPoints()
			button.label:SetPoint('LEFT', 14 + (row.level - 1) * INDENT, 0)
			button.label:SetPoint('RIGHT', row.hasChildren and -26 or -8, 0)
			button.label:SetText(row.entry.text)
			button.sub:SetText('')
			button.value = row.value
			button.row = row
			button.disabled = row.entry.disabled
			button.selected = row.value == selected
			button.onClick = function(btn)
				self:SelectNav(btn.row)
			end
			button.onToggle = function(btn)
				if self.page then
					self.page:SetExpanded(btn.row.value, not btn.row.expanded)
					self:RefreshNav()
				end
			end
			button.toggle:SetShown(row.hasChildren)
			button.toggle.glyph:SetExpanded(row.expanded)
			button:Show()
			PaintNav(button)
			if button.selected then
				selectedTop, selectedBottom = y, y + height
			end
			y = y + height
		end
		for i = #rows + 1, #self.navButtons do
			self.navButtons[i]:Hide()
		end
		self.navList:SetHeight(math.max(1, y))
		self:ClampNavScroll(reveal and selectedTop, selectedBottom)
	end,

	---Keep the sidebar scroll in range, optionally bringing a span of the list into view
	---@param top? number
	---@param bottom? number
	ClampNavScroll = function(self, top, bottom)
		local scroll = self.navScroll
		local view = scroll:GetHeight() or 0
		local maxScroll = math.max(0, (self.navList:GetHeight() or 0) - view)
		local value = scroll:GetVerticalScroll() or 0
		if top and bottom and view > 0 then
			if top < value then
				value = top
			elseif bottom > value + view then
				value = bottom - view
			end
		end
		scroll:SetVerticalScroll(math.max(0, math.min(maxScroll, value)))
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
			Style:SetFont(button.label, 12)
			button.label:ClearAllPoints()
			button.label:SetPoint('TOPLEFT', 14, -5)
			button.label:SetPoint('RIGHT', -8, 0)
			button.label:SetText(result.text)
			button.sub:SetText(result.sub or '')
			button.row = nil
			button.disabled = false
			button.selected = false
			button.onClick = result.onClick
			button.onToggle = nil
			button.toggle:Hide()
			button:Show()
			PaintNav(button)
		end
		for i = #results + 1, #self.navButtons do
			self.navButtons[i]:Hide()
		end
		self.noResults:SetShown(#results == 0)
		self.navList:SetHeight(math.max(1, #results * (NAV_HEIGHT + 10)))
		self.navScroll:SetVerticalScroll(0)
	end,

	ClearSearch = function(self)
		self.searching = false
		self.noResults:Hide()
		if self.searchBox:GetText() ~= '' then
			self.searchBox:SetText('')
		end
		self:RefreshNav(true)
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

	LibAT.UI.Kit:DressShell(frame, { footer = true })

	frame:SetScript('OnShow', function(self)
		self.obj:Fire('OnShow')
	end)
	frame:SetScript('OnHide', function(self)
		self.obj:Fire('OnClose')
	end)
	frame:SetScript('OnMouseDown', function()
		AceGUI:ClearFocus()
	end)

	-- Title bar: drag handle, logo, title (the kit draws the bar and the close button)
	local header = frame.TitleBar
	header:EnableMouse(true)
	header:SetScript('OnMouseDown', function()
		frame:StartMoving()
		AceGUI:ClearFocus()
	end)
	header:SetScript('OnMouseUp', function()
		frame:StopMovingOrSizing()
		SaveStatus(frame)
		frame.obj:PlaceStage()
	end)
	frame.TitleText:Hide()

	local logo = header:CreateTexture(nil, 'ARTWORK')
	logo:SetTexture('Interface\\AddOns\\SpartanUI\\images\\setup\\SUISetup')
	logo:SetTexCoord(0, 0.611328125, 0, 0.6640625)
	logo:SetSize(80, 23)
	logo:SetPoint('LEFT', 12, 0)

	local titletext = Style:CreateText(header, 13, Style.color.muted)
	titletext:SetPoint('LEFT', logo, 'RIGHT', 10, 0)

	-- Sidebar
	local sidebar = CreateFrame('Frame', nil, frame)
	sidebar:SetPoint('TOPLEFT', frame.Body, 'TOPLEFT')
	sidebar:SetPoint('BOTTOMLEFT', frame.Body, 'BOTTOMLEFT')
	sidebar:SetWidth(SIDEBAR)
	LibAT.UI.Kit:SkinPanel(sidebar, { elevation = 1, shadow = false })

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
		local maxScroll = math.max(0, navList:GetHeight() - (self:GetHeight() or 0))
		if self:GetVerticalScroll() > maxScroll then
			self:SetVerticalScroll(maxScroll)
		end
	end)

	local noResults = Style:CreateText(sidebar, 11, Style.color.faint)
	noResults:SetPoint('TOPLEFT', navScroll, 'TOPLEFT', 14, -6)
	noResults:SetPoint('RIGHT', sidebar, 'RIGHT', -10, 0)
	noResults:SetJustifyH('LEFT')
	noResults:SetText(L['Nothing found. Try another word.'])
	noResults:Hide()

	-- Preview panel, attached outside the window
	local stage = CreateFrame('Frame', nil, frame)
	stage:SetPoint('TOPLEFT', frame, 'TOPRIGHT', STAGE_GAP, 0)
	stage:SetPoint('BOTTOMLEFT', frame, 'BOTTOMRIGHT', STAGE_GAP, 0)
	stage:SetWidth(0.001)
	stage:EnableMouse(true)
	stage:Hide()
	LibAT.UI.Kit:SkinPanel(stage, { elevation = 1 })

	local contentPanel = CreateFrame('Frame', nil, frame)
	contentPanel:SetPoint('TOPLEFT', sidebar, 'TOPRIGHT', 12, 0)
	contentPanel:SetPoint('BOTTOMRIGHT', frame.Body, 'BOTTOMRIGHT')
	LibAT.UI.Kit:SkinPanel(contentPanel, { elevation = 1, shadow = false })
	-- Pages scroll inside the panel (their scroll frames keep settings inside it). The panel itself
	-- must not clip its children: in game that hid the whole page.

	local content = CreateFrame('Frame', nil, contentPanel)
	content:SetPoint('TOPLEFT', CONTENT_PAD, -CONTENT_PAD)
	content:SetPoint('BOTTOMRIGHT', -CONTENT_PAD, CONTENT_PAD)

	-- Footer and resize grip come from the kit
	local footer = frame.Footer
	local sizer = frame.ResizeHandle
	sizer:Show()
	function frame:OnResized()
		SaveStatus(self)
	end

	local widget = {
		localstatus = {},
		titletext = titletext,
		content = content,
		frame = frame,
		header = header,
		sidebar = sidebar,
		contentPanel = contentPanel,
		searchBox = searchBox,
		navScroll = navScroll,
		navList = navList,
		navButtons = {},
		noResults = noResults,
		stage = stage,
		stageWidth = -1,
		footer = footer,
		sizer = sizer,
		type = Type,
		baseType = 'Frame',
	}
	for method, func in pairs(methods) do
		widget[method] = func
	end

	-- A kit with a different frame size changes the room the settings get
	LibAT.UI.Kit:Track(contentPanel, function()
		widget:OnWidthSet(frame:GetWidth())
		widget:OnHeightSet(frame:GetHeight())
	end)

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

	Style:OnAccentChanged(frame, function()
		for _, button in ipairs(widget.navButtons) do
			if button:IsShown() then
				PaintNav(button)
			end
		end
	end)

	local registered = AceGUI:RegisterAsContainer(widget)
	registered:RaiseFooter()
	registered:SetStageWidth(0)
	return registered
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
