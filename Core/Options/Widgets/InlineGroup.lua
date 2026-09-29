---@class SUI
local SUI = SUI
local Style = SUI.UI.Style
local W = SUI.UI.OptionWidgets

-- InlineGroup replacement: a flat panel with a hairline border and the title in muted text above.
-- Same methods as the stock AceGUI InlineGroup.

local Type, Version = 'SUI-InlineGroup', 1
local AceGUI = LibStub and LibStub('AceGUI-3.0', true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then
	return
end

local TITLE_H = 20
local PAD = 10
local BOTTOM = 2

local methods = {
	OnAcquire = function(self)
		self:SetWidth(300)
		self:SetHeight(100)
		self:SetTitle('')
	end,

	SetTitle = function(self, title)
		self.titletext:SetText(title)
		local hasTitle = title and title ~= '' and true or false
		self.titletext:SetShown(hasTitle)
		self.titleOffset = hasTitle and TITLE_H or 0
		self.border:SetPoint('TOPLEFT', 0, -self.titleOffset)
		if self.frame.height then
			self:OnHeightSet(self.frame.height)
		end
	end,

	LayoutFinished = function(self, width, height)
		if self.noAutoHeight then
			return
		end
		self:SetHeight((height or 0) + self.titleOffset + PAD * 2 + BOTTOM)
	end,

	OnWidthSet = function(self, width)
		local content = self.content
		local contentwidth = width - PAD * 2
		if contentwidth < 0 then
			contentwidth = 0
		end
		content:SetWidth(contentwidth)
		content.width = contentwidth
	end,

	OnHeightSet = function(self, height)
		local content = self.content
		local contentheight = height - self.titleOffset - PAD * 2 - BOTTOM
		if contentheight < 0 then
			contentheight = 0
		end
		content:SetHeight(contentheight)
		content.height = contentheight
	end,
}

local function Constructor()
	local frame = CreateFrame('Frame', nil, UIParent)
	frame:SetFrameStrata('FULLSCREEN_DIALOG')

	local titletext = Style:CreateText(frame, W.SMALL_SIZE, Style.color.muted)
	titletext:SetPoint('TOPLEFT', 2, 0)
	titletext:SetPoint('TOPRIGHT', -2, 0)
	titletext:SetJustifyH('LEFT')
	titletext:SetWordWrap(false)
	titletext:SetHeight(TITLE_H - 4)

	local border = CreateFrame('Frame', nil, frame)
	border:SetPoint('TOPLEFT', 0, -TITLE_H)
	border:SetPoint('BOTTOMRIGHT', 0, BOTTOM)
	-- A faint white wash instead of a solid fill, so nested groups read one step lighter
	Style:SkinPanel(border, { 1, 1, 1, 0.025 }, Style.color.line)

	--Container Support
	local content = CreateFrame('Frame', nil, border)
	content:SetPoint('TOPLEFT', PAD, -PAD)
	content:SetPoint('BOTTOMRIGHT', -PAD, PAD)

	local widget = {
		frame = frame,
		content = content,
		border = border,
		titletext = titletext,
		titleOffset = TITLE_H,
		baseType = 'InlineGroup',
		type = Type,
	}
	for method, func in pairs(methods) do
		widget[method] = func
	end

	return AceGUI:RegisterAsContainer(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
