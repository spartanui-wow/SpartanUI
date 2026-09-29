---@class SUI
local SUI = SUI
local Style = SUI.UI.Style
local W = SUI.UI.OptionWidgets

-- TreeGroup replacement: flat rows, the selected row gets an accent bar and a lifted fill, groups
-- open and close with a drawn +/- toggle, and the list has a thin flat scrollbar.
-- Same methods, callbacks, events and status table as the stock AceGUI TreeGroup.

local Type, Version = 'SUI-TreeGroup', 1
local AceGUI = LibStub and LibStub('AceGUI-3.0', true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then
	return
end

local next, pairs, ipairs, assert, type = next, pairs, ipairs, assert, type
local math_min, math_max, floor = math.min, math.max, math.floor
local select, tremove, unpack, tconcat = select, table.remove, unpack, table.concat

-- Recycling functions
local new, del
do
	local pool = setmetatable({}, { __mode = 'k' })
	function new()
		local t = next(pool)
		if t then
			pool[t] = nil
			return t
		else
			return {}
		end
	end
	function del(t)
		for k in pairs(t) do
			t[k] = nil
		end
		pool[t] = true
	end
end

local DEFAULT_TREE_WIDTH = 175
local DEFAULT_TREE_SIZABLE = true
local ROW_H = 20
local TREE_PAD = 6
local INDENT = 12
local SCROLL_SPACE = 12
local CONTENT_LEFT, CONTENT_RIGHT, CONTENT_TOP, CONTENT_BOTTOM = 14, 4, 8, 4

----------------------------------------------------------------------------------------------------
-- Support functions
----------------------------------------------------------------------------------------------------

local function GetButtonUniqueValue(line)
	local parent = line.parent
	if parent and parent.value then
		return GetButtonUniqueValue(parent) .. '\001' .. line.value
	else
		return line.value
	end
end

local function PaintButton(button)
	local c = Style.color
	local r, g, b = Style:GetAccent()
	local disabled = button.disabled
	local hovered = button.hovered and not disabled
	if button.selected then
		button.fill:Show()
		button.fill:SetVertexColor(1, 1, 1, hovered and 0.1 or 0.075)
		button.bar:Show()
		button.bar:SetVertexColor(r, g, b, 1)
	elseif hovered then
		button.fill:Show()
		W.Paint(button.fill, c.hover)
		button.bar:Hide()
	else
		button.fill:Hide()
		button.bar:Hide()
	end
	local textColor
	if disabled then
		textColor = c.faint
	elseif button.selected or hovered then
		textColor = c.text
	elseif button.level == 1 then
		textColor = W.Mix(c.text, c.muted, 0.2)
	else
		textColor = c.muted
	end
	W.Paint(button.text, textColor)
	local toggleColor = button.toggle.hovered and c.text or c.muted
	button.toggle.glyph:SetColor(toggleColor[1], toggleColor[2], toggleColor[3], 1)
end

local function UpdateButton(button, treeline, selected, canExpand, isExpanded)
	local self = button.obj
	local toggle = button.toggle
	local text = treeline.text or ''
	local icon = treeline.icon
	local iconCoords = treeline.iconCoords
	local level = treeline.level
	local value = treeline.value
	local uniquevalue = treeline.uniquevalue
	local disabled = treeline.disabled

	button.treeline = treeline
	button.value = value
	button.uniquevalue = uniquevalue
	button.selected = selected and true or false
	button.level = level
	button.disabled = disabled

	local indent = 10 + (level - 1) * INDENT
	Style:SetFont(button.text, level == 1 and W.LABEL_SIZE or W.SMALL_SIZE)
	button.text:SetPoint('LEFT', indent + (icon and 18 or 0), 0)
	button.text:SetText(text)
	button:EnableMouse(not disabled)

	if icon then
		button.icon:SetTexture(icon)
		button.icon:SetPoint('LEFT', indent, 0)
		button.icon:Show()
	else
		button.icon:SetTexture(nil)
		button.icon:Hide()
	end

	if iconCoords then
		button.icon:SetTexCoord(unpack(iconCoords))
	else
		button.icon:SetTexCoord(0, 1, 0, 1)
	end

	if canExpand then
		toggle.glyph:SetExpanded(isExpanded)
		toggle:Show()
		button.text:SetPoint('RIGHT', -20, 0)
	else
		toggle:Hide()
		button.text:SetPoint('RIGHT', -4, 0)
	end
	PaintButton(button)
end

local function ShouldDisplayLevel(tree)
	local result = false
	for k, v in ipairs(tree) do
		if v.children == nil and v.visible ~= false then
			result = true
		elseif v.children then
			result = result or ShouldDisplayLevel(v.children)
		end
		if result then
			return result
		end
	end
	return false
end

local function addLine(self, v, tree, level, parent)
	local line = new()
	line.value = v.value
	line.text = v.text
	line.icon = v.icon
	line.iconCoords = v.iconCoords
	line.disabled = v.disabled
	line.tree = tree
	line.level = level
	line.parent = parent
	line.visible = v.visible
	line.uniquevalue = GetButtonUniqueValue(line)
	if v.children then
		line.hasChildren = true
	else
		line.hasChildren = nil
	end
	self.lines[#self.lines + 1] = line
	return line
end

--fire an update after one frame to catch the treeframes height
local function FirstFrameUpdate(frame)
	local self = frame.obj
	frame:SetScript('OnUpdate', nil)
	self:RefreshTree(nil, true)
end

local function BuildUniqueValue(...)
	local n = select('#', ...)
	if n == 1 then
		return ...
	else
		return (...) .. '\001' .. BuildUniqueValue(select(2, ...))
	end
end

----------------------------------------------------------------------------------------------------
-- Scripts
----------------------------------------------------------------------------------------------------

local function Expand_OnClick(frame)
	local button = frame.button
	local self = button.obj
	local status = (self.status or self.localstatus).groups
	status[button.uniquevalue] = not status[button.uniquevalue]
	self:RefreshTree()
end

local function Expand_OnEnter(frame)
	frame.hovered = true
	PaintButton(frame.button)
end

local function Expand_OnLeave(frame)
	frame.hovered = false
	PaintButton(frame.button)
end

local function Button_OnClick(frame)
	local self = frame.obj
	self:Fire('OnClick', frame.uniquevalue, frame.selected)
	if not frame.selected then
		self:SetSelected(frame.uniquevalue)
		frame.selected = true
		PaintButton(frame)
		self:RefreshTree()
	end
	AceGUI:ClearFocus()
end

local function Button_OnDoubleClick(button)
	local self = button.obj
	local status = (self.status or self.localstatus).groups
	status[button.uniquevalue] = not status[button.uniquevalue]
	self:RefreshTree()
end

local function Button_OnEnter(frame)
	local self = frame.obj
	frame.hovered = true
	PaintButton(frame)
	self:Fire('OnButtonEnter', frame.uniquevalue, frame)

	if self.enabletooltips then
		local tooltip = AceGUI.tooltip
		tooltip:SetOwner(frame, 'ANCHOR_NONE')
		tooltip:ClearAllPoints()
		tooltip:SetPoint('LEFT', frame, 'RIGHT')
		tooltip:SetText(frame.text:GetText() or '', 1, 0.82, 0, 1, true)

		tooltip:Show()
	end
end

local function Button_OnLeave(frame)
	local self = frame.obj
	frame.hovered = false
	PaintButton(frame)
	self:Fire('OnButtonLeave', frame.uniquevalue, frame)

	if self.enabletooltips then
		AceGUI.tooltip:Hide()
	end
end

local function OnScrollValueChanged(frame, value)
	if frame.obj.noupdate then
		return
	end
	local self = frame.obj
	local status = self.status or self.localstatus
	status.scrollvalue = floor(value + 0.5)
	self:RefreshTree()
	AceGUI:ClearFocus()
end

local function Tree_OnSizeChanged(frame)
	frame.obj:RefreshTree()
end

local function Tree_OnMouseWheel(frame, delta)
	local self = frame.obj
	if self.showscroll then
		local scrollbar = self.scrollbar
		local min, max = scrollbar:GetMinMaxValues()
		local value = scrollbar:GetValue()
		local newvalue = math_min(max, math_max(min, value - delta))
		if value ~= newvalue then
			scrollbar:SetValue(newvalue)
		end
	end
end

local function Dragger_OnLeave(frame)
	frame.line:Hide()
end

local function Dragger_OnEnter(frame)
	local r, g, b = Style:GetAccent()
	frame.line:SetVertexColor(r, g, b, 0.9)
	frame.line:Show()
end

local function Dragger_OnMouseDown(frame)
	local treeframe = frame:GetParent()
	treeframe:StartSizing('RIGHT')
end

local function Dragger_OnMouseUp(frame)
	local treeframe = frame:GetParent()
	local self = treeframe.obj
	local treeframeParent = treeframe:GetParent()
	treeframe:StopMovingOrSizing()
	treeframe:SetUserPlaced(false)
	--Without this :GetHeight will get stuck on the current height, causing the tree contents to not resize
	treeframe:SetHeight(0)
	treeframe:ClearAllPoints()
	treeframe:SetPoint('TOPLEFT', treeframeParent, 'TOPLEFT', 0, 0)
	treeframe:SetPoint('BOTTOMLEFT', treeframeParent, 'BOTTOMLEFT', 0, 0)

	local status = self.status or self.localstatus
	status.treewidth = treeframe:GetWidth()

	treeframe.obj:Fire('OnTreeResize', treeframe:GetWidth())
	-- recalculate the content width
	treeframe.obj:OnWidthSet(status.fullwidth)
	-- update the layout of the content
	treeframe.obj:DoLayout()
end

local function Tree_OnShow(frame)
	local self = frame.obj
	for _, button in ipairs(self.buttons) do
		button.toggle.glyph:Layout()
	end
	self.divider:SetWidth(Style:PixelSize(frame))
end

----------------------------------------------------------------------------------------------------
-- Methods
----------------------------------------------------------------------------------------------------

local methods = {
	OnAcquire = function(self)
		self:SetTreeWidth(DEFAULT_TREE_WIDTH, DEFAULT_TREE_SIZABLE)
		self:EnableButtonTooltips(true)
		self.frame:SetScript('OnUpdate', FirstFrameUpdate)
	end,

	OnRelease = function(self)
		self.status = nil
		self.tree = nil
		self.frame:SetScript('OnUpdate', nil)
		for k, v in pairs(self.localstatus) do
			if k == 'groups' then
				for k2 in pairs(v) do
					v[k2] = nil
				end
			else
				self.localstatus[k] = nil
			end
		end
		self.localstatus.scrollvalue = 0
		self.localstatus.treewidth = DEFAULT_TREE_WIDTH
		self.localstatus.treesizable = DEFAULT_TREE_SIZABLE
		for _, button in ipairs(self.buttons) do
			button.hovered = false
			button.toggle.hovered = false
		end
	end,

	EnableButtonTooltips = function(self, enable)
		self.enabletooltips = enable
	end,

	CreateButton = function(self)
		local num = AceGUI:GetNextWidgetNum('SUI-TreeGroupButton')
		local button = CreateFrame('Button', ('SUI_OptionsTreeButton%d'):format(num), self.treeframe)
		button.obj = self
		button:SetHeight(ROW_H)
		button:RegisterForClicks('LeftButtonUp')

		button.fill = W:CreateRect(button, 'BACKGROUND')
		button.fill:SetAllPoints()
		button.fill:Hide()
		button.bar = W:CreateRect(button, 'ARTWORK')
		button.bar:SetPoint('TOPLEFT', 0, 0)
		button.bar:SetPoint('BOTTOMLEFT', 0, 0)
		button.bar:SetWidth(2)
		button.bar:Hide()

		local icon = button:CreateTexture(nil, 'OVERLAY')
		icon:SetWidth(14)
		icon:SetHeight(14)
		button.icon = icon

		button.text = Style:CreateText(button, W.LABEL_SIZE)
		button.text:SetJustifyH('LEFT')
		button.text:SetWordWrap(false)
		button.text:SetHeight(14) -- Prevents text wrapping
		button.text:SetPoint('LEFT', 10, 0)
		button.text:SetPoint('RIGHT', -4, 0)

		local toggle = CreateFrame('Button', nil, button)
		toggle:SetSize(16, 16)
		toggle:SetPoint('RIGHT', -4, 0)
		toggle.glyph = W:CreatePlusMinus(toggle)
		toggle.glyph.anchor:SetPoint('CENTER', toggle, 'CENTER', 0, 0)
		toggle.button = button
		toggle:SetScript('OnClick', Expand_OnClick)
		toggle:SetScript('OnEnter', Expand_OnEnter)
		toggle:SetScript('OnLeave', Expand_OnLeave)
		button.toggle = toggle

		button:SetScript('OnClick', Button_OnClick)
		button:SetScript('OnDoubleClick', Button_OnDoubleClick)
		button:SetScript('OnEnter', Button_OnEnter)
		button:SetScript('OnLeave', Button_OnLeave)

		return button
	end,

	SetStatusTable = function(self, status)
		assert(type(status) == 'table')
		self.status = status
		if not status.groups then
			status.groups = {}
		end
		if not status.scrollvalue then
			status.scrollvalue = 0
		end
		if not status.treewidth then
			status.treewidth = DEFAULT_TREE_WIDTH
		end
		if status.treesizable == nil then
			status.treesizable = DEFAULT_TREE_SIZABLE
		end
		self:SetTreeWidth(status.treewidth, status.treesizable)
		self:RefreshTree()
	end,

	--sets the tree to be displayed
	SetTree = function(self, tree, filter)
		self.filter = filter
		if tree then
			assert(type(tree) == 'table')
		end
		self.tree = tree
		self:RefreshTree()
	end,

	BuildLevel = function(self, tree, level, parent)
		local groups = (self.status or self.localstatus).groups

		for i, v in ipairs(tree) do
			if v.children then
				if not self.filter or ShouldDisplayLevel(v.children) then
					local line = addLine(self, v, tree, level, parent)
					if groups[line.uniquevalue] then
						self:BuildLevel(v.children, level + 1, line)
					end
				end
			elseif v.visible ~= false or not self.filter then
				addLine(self, v, tree, level, parent)
			end
		end
	end,

	RefreshTree = function(self, scrollToSelection, fromOnUpdate)
		local buttons = self.buttons
		local lines = self.lines
		while lines[1] do
			local t = tremove(lines)
			for k in pairs(t) do
				t[k] = nil
			end
			del(t)
		end

		if not self.tree then
			for i = 1, #buttons do
				buttons[i]:Hide()
			end
			return
		end
		--Build the list of visible entries from the tree and status tables
		local status = self.status or self.localstatus
		local groupstatus = status.groups
		local tree = self.tree

		local treeframe = self.treeframe

		status.scrollToSelection = status.scrollToSelection or scrollToSelection -- needs to be cached in case the control hasn't been drawn yet (code bails out below)

		self:BuildLevel(tree, 1)

		local numlines = #lines

		local maxlines = floor(((self.treeframe:GetHeight() or 0) - TREE_PAD * 2) / ROW_H)
		if maxlines <= 0 then
			return
		end

		if self.frame:GetParent() == UIParent and not fromOnUpdate then
			self.frame:SetScript('OnUpdate', FirstFrameUpdate)
			return
		end

		local first, last

		scrollToSelection = status.scrollToSelection
		status.scrollToSelection = nil

		if numlines <= maxlines then
			--the whole tree fits in the frame
			status.scrollvalue = 0
			self:ShowScroll(false)
			first, last = 1, numlines
		else
			self:ShowScroll(true)
			--scrolling will be needed
			self.noupdate = true
			self.scrollbar:SetMinMaxValues(0, numlines - maxlines)
			self.scrollbar:SetThumbRatio(maxlines / numlines)
			--check if we are scrolled down too far
			if numlines - status.scrollvalue < maxlines then
				status.scrollvalue = numlines - maxlines
			end
			self.noupdate = nil
			first, last = status.scrollvalue + 1, status.scrollvalue + maxlines
			--show selection?
			if scrollToSelection and status.selected then
				local show
				for i, line in ipairs(lines) do -- find the line number
					if line.uniquevalue == status.selected then
						show = i
					end
				end
				if not show then
					-- selection was deleted or something?
				elseif show >= first and show <= last then
					-- all good
				else
					-- scrolling needed!
					if show < first then
						status.scrollvalue = show - 1
					else
						status.scrollvalue = show - maxlines
					end
					first, last = status.scrollvalue + 1, status.scrollvalue + maxlines
				end
			end
			if self.scrollbar:GetValue() ~= status.scrollvalue then
				self.scrollbar:SetValue(status.scrollvalue)
			end
		end

		local buttonnum = 1
		for i = first, last do
			local line = lines[i]
			local button = buttons[buttonnum]
			if not button then
				button = self:CreateButton()

				buttons[buttonnum] = button
				button:SetParent(treeframe)
				button:SetFrameLevel(treeframe:GetFrameLevel() + 1)
				button:ClearAllPoints()
				if buttonnum == 1 then
					if self.showscroll then
						button:SetPoint('TOPRIGHT', -SCROLL_SPACE, -TREE_PAD)
						button:SetPoint('TOPLEFT', 0, -TREE_PAD)
					else
						button:SetPoint('TOPRIGHT', 0, -TREE_PAD)
						button:SetPoint('TOPLEFT', 0, -TREE_PAD)
					end
				else
					button:SetPoint('TOPRIGHT', buttons[buttonnum - 1], 'BOTTOMRIGHT', 0, 0)
					button:SetPoint('TOPLEFT', buttons[buttonnum - 1], 'BOTTOMLEFT', 0, 0)
				end
			end

			UpdateButton(button, line, status.selected == line.uniquevalue, line.hasChildren, groupstatus[line.uniquevalue])
			button:Show()
			buttonnum = buttonnum + 1
		end

		-- We hide the remaining buttons after updating others to avoid a blizzard bug that keeps them interactable even if hidden when hidden before updating the buttons.
		for i = buttonnum, #buttons do
			buttons[i]:Hide()
		end
	end,

	SetSelected = function(self, value)
		local status = self.status or self.localstatus
		if status.selected ~= value then
			status.selected = value
			self:Fire('OnGroupSelected', value)
		end
	end,

	Select = function(self, uniquevalue, ...)
		self.filter = false
		local status = self.status or self.localstatus
		local groups = status.groups
		local path = { ... }
		for i = 1, #path do
			groups[tconcat(path, '\001', 1, i)] = true
		end
		status.selected = uniquevalue
		self:RefreshTree(true)
		self:Fire('OnGroupSelected', uniquevalue)
	end,

	SelectByPath = function(self, ...)
		self:Select(BuildUniqueValue(...), ...)
	end,

	SelectByValue = function(self, uniquevalue)
		self:Select(uniquevalue, ('\001'):split(uniquevalue))
	end,

	ShowScroll = function(self, show)
		self.showscroll = show
		if show then
			self.scrollbar:Show()
			if self.buttons[1] then
				self.buttons[1]:SetPoint('TOPRIGHT', self.treeframe, 'TOPRIGHT', -SCROLL_SPACE, -TREE_PAD)
			end
		else
			self.scrollbar:Hide()
			if self.buttons[1] then
				self.buttons[1]:SetPoint('TOPRIGHT', self.treeframe, 'TOPRIGHT', 0, -TREE_PAD)
			end
		end
	end,

	OnWidthSet = function(self, width)
		local content = self.content
		local treeframe = self.treeframe
		local status = self.status or self.localstatus
		status.fullwidth = width

		local contentwidth = width - status.treewidth - CONTENT_LEFT - CONTENT_RIGHT
		if contentwidth < 0 then
			contentwidth = 0
		end
		content:SetWidth(contentwidth)
		content.width = contentwidth

		local maxtreewidth = math_min(400, width - 50)

		if maxtreewidth > 100 and status.treewidth > maxtreewidth then
			self:SetTreeWidth(maxtreewidth, status.treesizable)
		end
		if treeframe.SetResizeBounds then
			treeframe:SetResizeBounds(100, 1, maxtreewidth, 1600)
		else
			treeframe:SetMaxResize(maxtreewidth, 1600)
		end
	end,

	OnHeightSet = function(self, height)
		local content = self.content
		local contentheight = height - CONTENT_TOP - CONTENT_BOTTOM
		if contentheight < 0 then
			contentheight = 0
		end
		content:SetHeight(contentheight)
		content.height = contentheight
	end,

	SetTreeWidth = function(self, treewidth, resizable)
		if not resizable then
			if type(treewidth) == 'number' then
				resizable = false
			elseif type(treewidth) == 'boolean' then
				resizable = treewidth
				treewidth = DEFAULT_TREE_WIDTH
			else
				resizable = false
				treewidth = DEFAULT_TREE_WIDTH
			end
		end
		self.treeframe:SetWidth(treewidth)
		self.dragger:EnableMouse(resizable)

		local status = self.status or self.localstatus
		status.treewidth = treewidth
		status.treesizable = resizable

		-- recalculate the content width
		if status.fullwidth then
			self:OnWidthSet(status.fullwidth)
		end
	end,

	GetTreeWidth = function(self)
		local status = self.status or self.localstatus
		return status.treewidth or DEFAULT_TREE_WIDTH
	end,

	LayoutFinished = function(self, width, height)
		if self.noAutoHeight then
			return
		end
		self:SetHeight((height or 0) + CONTENT_TOP + CONTENT_BOTTOM)
	end,
}

----------------------------------------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------------------------------------

local function Constructor()
	local num = AceGUI:GetNextWidgetNum(Type)
	local frame = CreateFrame('Frame', nil, UIParent)

	local treeframe = CreateFrame('Frame', nil, frame)
	treeframe:SetPoint('TOPLEFT')
	treeframe:SetPoint('BOTTOMLEFT')
	treeframe:SetWidth(DEFAULT_TREE_WIDTH)
	treeframe:EnableMouseWheel(true)
	treeframe:SetResizable(true)
	if treeframe.SetResizeBounds then -- WoW 10.0
		treeframe:SetResizeBounds(100, 1, 400, 1600)
	else
		treeframe:SetMinResize(100, 1)
		treeframe:SetMaxResize(400, 1600)
	end
	treeframe:SetScript('OnUpdate', FirstFrameUpdate)
	treeframe:SetScript('OnSizeChanged', Tree_OnSizeChanged)
	treeframe:SetScript('OnMouseWheel', Tree_OnMouseWheel)
	treeframe:SetScript('OnShow', Tree_OnShow)

	local treeFill = Style:CreateFill(treeframe, { 0, 0, 0, 0.18 })
	treeFill:SetAllPoints()
	local divider = W:CreateRect(treeframe, 'BORDER')
	divider:SetPoint('TOPRIGHT')
	divider:SetPoint('BOTTOMRIGHT')
	divider:SetWidth(1)
	W.Paint(divider, Style.color.line)

	local dragger = CreateFrame('Frame', nil, treeframe)
	dragger:SetWidth(8)
	dragger:SetPoint('TOP', treeframe, 'TOPRIGHT')
	dragger:SetPoint('BOTTOM', treeframe, 'BOTTOMRIGHT')
	dragger.line = W:CreateRect(dragger, 'OVERLAY')
	dragger.line:SetPoint('TOP')
	dragger.line:SetPoint('BOTTOM')
	dragger.line:SetWidth(2)
	dragger.line:Hide()
	dragger:SetScript('OnEnter', Dragger_OnEnter)
	dragger:SetScript('OnLeave', Dragger_OnLeave)
	dragger:SetScript('OnMouseDown', Dragger_OnMouseDown)
	dragger:SetScript('OnMouseUp', Dragger_OnMouseUp)

	local scrollbar = W:CreateScrollBar(treeframe, ('SUI_OptionsTreeGroup%dScrollBar'):format(num))
	scrollbar:SetScript('OnValueChanged', nil)
	scrollbar:SetPoint('TOPRIGHT', -2, -TREE_PAD)
	scrollbar:SetPoint('BOTTOMRIGHT', -2, TREE_PAD)
	scrollbar:SetMinMaxValues(0, 0)
	scrollbar:SetValueStep(1)
	scrollbar:SetValue(0)
	scrollbar:SetScript('OnValueChanged', OnScrollValueChanged)
	scrollbar:Hide()

	local border = CreateFrame('Frame', nil, frame)
	border:SetPoint('TOPLEFT', treeframe, 'TOPRIGHT')
	border:SetPoint('BOTTOMRIGHT')

	--Container Support
	local content = CreateFrame('Frame', nil, border)
	content:SetPoint('TOPLEFT', CONTENT_LEFT, -CONTENT_TOP)
	content:SetPoint('BOTTOMRIGHT', -CONTENT_RIGHT, CONTENT_BOTTOM)

	local widget = {
		frame = frame,
		lines = {},
		levels = {},
		buttons = {},
		hasChildren = {},
		localstatus = { groups = {}, scrollvalue = 0 },
		filter = false,
		treeframe = treeframe,
		divider = divider,
		dragger = dragger,
		scrollbar = scrollbar,
		border = border,
		content = content,
		baseType = 'TreeGroup',
		type = Type,
	}
	for method, func in pairs(methods) do
		widget[method] = func
	end
	treeframe.obj, dragger.obj, scrollbar.obj = widget, widget, widget
	Style:OnAccentChanged(frame, function()
		for _, button in ipairs(widget.buttons) do
			PaintButton(button)
		end
	end)

	return AceGUI:RegisterAsContainer(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
