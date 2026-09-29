---@class SUI
local SUI = SUI
local Style = SUI.UI.Style

-- A tab group without tabs: the options window's sidebar picks the page. Shows the page title
-- over its content. AceConfigDialog treats it as a TabGroup (baseType).

local Type, Version = 'SUI-PageGroup', 1
local AceGUI = LibStub and LibStub('AceGUI-3.0', true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then
	return
end

local HEADER = 38

local methods = {
	OnAcquire = function(self)
		self.tablist = nil
		self.titletext:SetText('')
	end,

	OnRelease = function(self)
		self.status = nil
		wipe(self.localstatus)
		self.tablist = nil
	end,

	SetTitle = function(self, text) end,

	SetStatusTable = function(self, status)
		assert(type(status) == 'table')
		self.status = status
	end,

	SelectTab = function(self, value)
		local status = self.status or self.localstatus
		local found
		for _, tab in ipairs(self.tablist or {}) do
			if tab.value == value then
				found = tab
			end
		end
		status.selected = value
		self.titletext:SetText(found and found.text or '')
		if found then
			self:Fire('OnGroupSelected', value)
		end
	end,

	SetTabs = function(self, tabs)
		self.tablist = tabs
	end,

	---@return string|nil
	GetSelected = function(self)
		local status = self.status or self.localstatus
		return status.selected
	end,

	BuildTabs = function(self) end,

	OnWidthSet = function(self, width)
		local content = self.content
		local contentwidth = math.max(0, width)
		content:SetWidth(contentwidth)
		content.width = contentwidth
	end,

	OnHeightSet = function(self, height)
		local content = self.content
		local contentheight = math.max(0, height - HEADER)
		content:SetHeight(contentheight)
		content.height = contentheight
	end,

	LayoutFinished = function(self, width, height)
		if self.noAutoHeight then
			return
		end
		self:SetHeight((height or 0) + HEADER)
	end,
}

local function Constructor()
	local frame = CreateFrame('Frame', nil, UIParent)
	frame:SetSize(100, 100)
	frame:Hide()

	local titletext = Style:CreateText(frame, 18)
	titletext:SetPoint('TOPLEFT', 4, -6)
	titletext:SetPoint('TOPRIGHT', -4, -6)
	titletext:SetJustifyH('LEFT')

	local rule = frame:CreateTexture(nil, 'ARTWORK')
	rule:SetTexture(Style.WHITE)
	rule:SetPoint('TOPLEFT', 0, -(HEADER - 6))
	rule:SetPoint('TOPRIGHT', 0, -(HEADER - 6))
	rule:SetHeight(Style:PixelSize(frame))
	rule:SetVertexColor(unpack(Style.color.line))

	local content = CreateFrame('Frame', nil, frame)
	content:SetPoint('TOPLEFT', 0, -HEADER)
	content:SetPoint('BOTTOMRIGHT', 0, 0)

	local widget = {
		frame = frame,
		content = content,
		titletext = titletext,
		localstatus = {},
		type = Type,
		baseType = 'TabGroup',
	}
	for method, func in pairs(methods) do
		widget[method] = func
	end
	return AceGUI:RegisterAsContainer(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
