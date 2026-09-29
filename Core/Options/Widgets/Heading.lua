---@class SUI
local SUI = SUI
local Style = SUI.UI.Style
local W = SUI.UI.OptionWidgets

-- Heading replacement: small upper case caption in the accent color followed by a hairline.
-- Same methods as the stock AceGUI Heading.

local Type, Version = 'SUI-Heading', 1
local AceGUI = LibStub and LibStub('AceGUI-3.0', true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then
	return
end

local issecretvalue = issecretvalue

local function IsSecret(value)
	return issecretvalue and issecretvalue(value) or false
end

local function Paint(self)
	local r, g, b = Style:GetAccent()
	self.label:SetTextColor(W.Lerp(r, 1, 0.2), W.Lerp(g, 1, 0.2), W.Lerp(b, 1, 0.2))
	self.left:SetVertexColor(r, g, b, 0.9)
	W.Paint(self.right, Style.color.line)
end

local function LayoutLines(self)
	local px = Style:PixelSize(self.frame)
	self.left:SetHeight(px * 2)
	self.right:SetHeight(px)
end

local methods = {
	OnAcquire = function(self)
		self:SetText()
		self:SetFullWidth()
		self:SetHeight(26)
	end,

	OnRelease = function(self)
		self.label:SetText('')
	end,

	SetText = function(self, text)
		local secret = IsSecret(text)
		local shown = text
		-- Color codes and texture markup break when upper cased, so only plain text is changed
		if not secret and type(text) == 'string' and not text:find('|', 1, true) then
			shown = text:upper()
		end
		self.label:SetText(shown or '')
		self.right:ClearAllPoints()
		if secret or (text and text ~= '') then
			self.label:Show()
			self.left:Show()
			self.right:SetPoint('LEFT', self.label, 'RIGHT', 8, 0)
		else
			self.label:Hide()
			self.left:Hide()
			self.right:SetPoint('LEFT', self.frame, 'LEFT', 0, 0)
		end
		self.right:SetPoint('RIGHT', self.frame, 'RIGHT', 0, 0)
	end,
}

local function Constructor()
	local frame = CreateFrame('Frame', nil, UIParent)
	frame:Hide()

	-- Short accent tick in front of the caption
	local left = W:CreateRect(frame, 'BACKGROUND')
	left:SetWidth(10)
	left:SetPoint('LEFT', frame, 'LEFT', 0, -3)

	local label = Style:CreateText(frame, W.SMALL_SIZE)
	label:SetPoint('LEFT', left, 'RIGHT', 6, 0)
	label:SetJustifyH('LEFT')
	label:SetWordWrap(false)

	local right = W:CreateRect(frame, 'BACKGROUND')
	right:SetPoint('LEFT', label, 'RIGHT', 8, 0)
	right:SetPoint('RIGHT', frame, 'RIGHT', 0, 0)

	local widget = {
		label = label,
		left = left,
		right = right,
		frame = frame,
		type = Type,
	}
	for method, func in pairs(methods) do
		widget[method] = func
	end
	frame:SetScript('OnShow', function()
		LayoutLines(widget)
	end)
	LayoutLines(widget)
	Style:OnAccentChanged(frame, function()
		Paint(widget)
	end)

	return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
