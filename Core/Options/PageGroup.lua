---@class SUI
local SUI = SUI
local Style = SUI.UI.Style

-- A tab group without tabs: the options window's sidebar is its tree and picks the page. Shows
-- the page title over its content. AceConfigDialog treats it as a TabGroup (baseType).
-- Values are tree paths joined with "\001", the same unique values a TreeGroup uses, and the
-- status table keeps the selected value and which tree entries are open (status.groups).

local Type, Version = 'SUI-PageGroup', 2
local AceGUI = LibStub and LibStub('AceGUI-3.0', true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then
	return
end

local HEADER = 38
local SEP = '\001'

---Find a tree entry by its unique value
---@return table|nil entry
local function FindEntry(list, value)
	local node, entry = list, nil
	for key in (value .. SEP):gmatch('(.-)' .. SEP) do
		entry = nil
		for _, candidate in ipairs(node or {}) do
			if candidate.value == key then
				entry = candidate
				break
			end
		end
		if not entry then
			return nil
		end
		node = entry.children
	end
	return entry
end

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
		local found = value and FindEntry(self.tablist or {}, value)
		-- A page with nothing of its own opens its first sub-page
		while found and found.empty and found.children do
			local child
			for _, candidate in ipairs(found.children) do
				if not candidate.disabled then
					child = candidate
					break
				end
			end
			if not child then
				break
			end
			self:SetExpanded(value, true)
			value = value .. SEP .. child.value
			found = child
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

	---@param value string
	---@return boolean
	IsExpanded = function(self, value)
		local status = self.status or self.localstatus
		return status.groups and status.groups[value] and true or false
	end,

	---@param value string
	---@param expanded boolean
	SetExpanded = function(self, value, expanded)
		local status = self.status or self.localstatus
		status.groups = status.groups or {}
		status.groups[value] = expanded and true or nil
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
