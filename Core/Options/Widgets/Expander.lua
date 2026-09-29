---@class SUI
local SUI = SUI
local Style = SUI.UI.Style
local W = SUI.UI.OptionWidgets

-- Fold-out container for the "More settings" section: a clickable header with an arrow and a
-- hairline, and its children below while it is open. Fires OnToggle(expanded) when clicked.

local Type, Version = 'SUI-Expander', 1
local AceGUI = LibStub and LibStub('AceGUI-3.0', true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then
	return
end

local HEADER_H = 26
local INDENT = 12
local GAP = 6

local function Paint(self)
	local c = Style.color
	local hovered = self.header.hovered
	local r, g, b = Style:GetAccent()
	local textColor = hovered and c.text or c.muted
	W.Paint(self.titletext, textColor)
	if self.expanded or hovered then
		self.arrow:SetColor(r, g, b, 1)
	else
		self.arrow:SetColor(c.muted[1], c.muted[2], c.muted[3], 1)
	end
	if hovered then
		self.rule:SetVertexColor(r, g, b, 0.6)
	else
		W.Paint(self.rule, c.line)
	end
	W.Paint(self.headerFill, c.hover, hovered and 0.04 or 0)
end

local function Header_OnClick(button)
	local self = button.obj
	local token = self.token
	local expanded = not self.expanded
	AceGUI:ClearFocus()
	W.Sound(expanded and 856 or 857) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON / _OFF
	self:Fire('OnToggle', expanded)
	-- AceConfigDialog redraws the page from OnToggle and releases this widget; only a widget
	-- that is still ours updates itself
	if self.token == token then
		self:SetExpanded(expanded)
		self:DoLayout()
		if self.parent and self.parent.DoLayout then
			self.parent:DoLayout()
		end
	end
end

local function Header_OnEnter(button)
	button.hovered = true
	Paint(button.obj)
	button.obj:Fire('OnEnter')
end

local function Header_OnLeave(button)
	button.hovered = false
	Paint(button.obj)
	button.obj:Fire('OnLeave')
end

local methods = {
	OnAcquire = function(self)
		self.token = (self.token or 0) + 1
		self.header.hovered = false
		self:SetWidth(300)
		self:SetTitle('')
		self:SetExpanded(false)
	end,

	OnRelease = function(self)
		self.token = (self.token or 0) + 1
		self.header.hovered = false
	end,

	SetTitle = function(self, title)
		self.titletext:SetText(title or '')
	end,

	---Open or close without firing OnToggle
	---@param expanded boolean
	SetExpanded = function(self, expanded)
		self.expanded = expanded and true or false
		self.content:SetShown(self.expanded)
		self.arrow:SetDirection(self.expanded and 'DOWN' or 'RIGHT')
		if not self.expanded then
			self:SetHeight(HEADER_H)
		end
		Paint(self)
	end,

	---@return boolean
	GetExpanded = function(self)
		return self.expanded
	end,

	LayoutFinished = function(self, width, height)
		if self.noAutoHeight then
			return
		end
		if self.expanded then
			self:SetHeight(HEADER_H + GAP + (height or 0) + 4)
		else
			self:SetHeight(HEADER_H)
		end
	end,

	OnWidthSet = function(self, width)
		local content = self.content
		local contentwidth = width - INDENT
		if contentwidth < 0 then
			contentwidth = 0
		end
		content:SetWidth(contentwidth)
		content.width = contentwidth
	end,

	OnHeightSet = function(self, height)
		local content = self.content
		local contentheight = height - HEADER_H - GAP - 4
		if contentheight < 0 then
			contentheight = 0
		end
		content:SetHeight(contentheight)
		content.height = contentheight
	end,
}

local function Constructor()
	local frame = CreateFrame('Frame', nil, UIParent)
	frame:Hide()

	local header = CreateFrame('Button', nil, frame)
	header:SetPoint('TOPLEFT')
	header:SetPoint('TOPRIGHT')
	header:SetHeight(HEADER_H)
	header:SetScript('OnClick', Header_OnClick)
	header:SetScript('OnEnter', Header_OnEnter)
	header:SetScript('OnLeave', Header_OnLeave)

	local headerFill = W:CreateRect(header, 'BACKGROUND')
	headerFill:SetAllPoints()

	local arrow = W:CreateArrow(header, 4)
	arrow.anchor:SetPoint('CENTER', header, 'LEFT', 6, 0)

	local titletext = Style:CreateText(header, W.LABEL_SIZE)
	titletext:SetPoint('LEFT', 18, 0)
	titletext:SetPoint('RIGHT', -4, 0)
	titletext:SetJustifyH('LEFT')
	titletext:SetWordWrap(false)

	local rule = W:CreateRect(header, 'ARTWORK')
	rule:SetPoint('BOTTOMLEFT')
	rule:SetPoint('BOTTOMRIGHT')

	local content = CreateFrame('Frame', nil, frame)
	content:SetPoint('TOPLEFT', INDENT, -(HEADER_H + GAP))
	content:SetPoint('BOTTOMRIGHT', 0, 4)

	local widget = {
		frame = frame,
		header = header,
		headerFill = headerFill,
		arrow = arrow,
		titletext = titletext,
		rule = rule,
		content = content,
		expanded = false,
		type = Type,
	}
	for method, func in pairs(methods) do
		widget[method] = func
	end
	header.obj = widget
	frame:SetScript('OnShow', function()
		arrow:Layout()
		rule:SetHeight(Style:PixelSize(header))
	end)
	rule:SetHeight(Style:PixelSize(header))
	Style:OnAccentChanged(frame, function()
		Paint(widget)
	end)

	return AceGUI:RegisterAsContainer(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
