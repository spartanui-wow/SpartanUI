-- ThemeVariantCard: Custom AceGUI widget for theme variant selection
-- Layout: Label (top) | Image preview (middle) | Variant dropdown (bottom)
-- Implements the AceConfig select-type interface for use with dialogControl='ThemeVariantCard'

local AceGUI = LibStub('AceGUI-3.0', true)
if not AceGUI then
	return
end

local widgetType = 'ThemeVariantCard'
local widgetVersion = 1

-- ============================================================
-- Shared dropdown popup (owned by one widget instance at a time)
-- ============================================================

local dropPopup -- created lazily on first use
local dropItemPool = {} -- reuse item buttons to avoid GC

local HideDropPopup -- forward declaration

local function GetDropPopup()
	if dropPopup then
		return dropPopup
	end

	local frame = CreateFrame('Frame', 'SUI_ThemeVariantCard_Popup', UIParent, BackdropTemplateMixin and 'BackdropTemplate')
	frame:SetFrameStrata('TOOLTIP')
	frame:SetClampedToScreen(true)
	if BackdropTemplateMixin then
		frame:SetBackdrop({
			bgFile = 'Interface\\DialogFrame\\UI-DialogBox-Background-Dark',
			edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border',
			tile = true,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
	end
	frame:Hide()
	frame.items = {}

	dropPopup = frame
	return frame
end

local function CreateDropItem()
	local item = CreateFrame('Button', nil, GetDropPopup())
	item:SetHeight(22)
	item:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight', 'ADD')

	local check = item:CreateTexture(nil, 'OVERLAY')
	check:SetSize(16, 16)
	check:SetPoint('LEFT', item, 'LEFT', 4, 0)
	check:SetTexture('Interface\\Buttons\\UI-CheckBox-Check')
	check:Hide()
	item.check = check

	local text = item:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	text:SetPoint('LEFT', check, 'RIGHT', 2, 0)
	text:SetPoint('RIGHT', item, 'RIGHT', -4, 0)
	text:SetJustifyH('LEFT')
	item.text = text

	item:SetScript('OnClick', function(self)
		local owner = dropPopup and dropPopup.owner
		if owner then
			owner.value = self.variantId
			owner.dropText:SetText(self.text:GetText())
			owner:Fire('OnValueChanged', self.variantId)
		end
		HideDropPopup()
	end)

	return item
end

HideDropPopup = function()
	if not dropPopup or not dropPopup:IsShown() then
		return
	end

	for _, item in ipairs(dropPopup.items) do
		item:Hide()
		item:ClearAllPoints()
		table.insert(dropItemPool, item)
	end
	wipe(dropPopup.items)

	dropPopup.owner = nil
	dropPopup:Hide()
end

local function ShowDropPopup(self)
	local popup = GetDropPopup()

	if popup:IsShown() and popup.owner == self then
		HideDropPopup()
		return
	end

	-- Clear any existing items back to pool
	for _, item in ipairs(popup.items) do
		item:Hide()
		item:ClearAllPoints()
		table.insert(dropItemPool, item)
	end
	wipe(popup.items)

	popup.owner = self

	local y = -8
	local listOrder = self.listOrder or {}
	for i = 1, #listOrder do
		local variantId = listOrder[i]
		local label = self.list and self.list[variantId]
		if label then
			local item = table.remove(dropItemPool) or CreateDropItem()
			item:SetParent(popup)
			item:SetFrameStrata('TOOLTIP')
			item:SetPoint('TOPLEFT', popup, 'TOPLEFT', 8, y)
			item:SetPoint('RIGHT', popup, 'RIGHT', -8, 0)
			item:Show()

			item.variantId = variantId
			item.text:SetText(label)
			if variantId == self.value then
				item.check:Show()
			else
				item.check:Hide()
			end

			table.insert(popup.items, item)
			y = y - 22
		end
	end

	popup:SetWidth(self.frame:GetWidth())
	popup:SetHeight(math.abs(y) + 8)
	popup:ClearAllPoints()
	popup:SetPoint('TOPLEFT', self.dropBtn, 'BOTTOMLEFT', 0, 0)
	popup:Show()
end

-- ============================================================
-- Widget lifecycle
-- ============================================================

local function OnAcquire(self)
	self:SetHeight(107)
	self:SetWidth(120)
end

local function OnRelease(self)
	if dropPopup and dropPopup.owner == self then
		HideDropPopup()
	end

	self.value = nil
	self.list = nil
	self.listOrder = nil

	self.label:SetText('')
	self.imageBtn:ClearNormalTexture()
	self.imageBtn:SetSize(120, 60)
	self.dropText:SetText('')

	self.frame:ClearAllPoints()
	self.frame:Hide()
end

local function ClearFocus(self)
	if dropPopup and dropPopup.owner == self then
		HideDropPopup()
	end
end

local function OnHide(frame)
	local self = frame.obj
	if dropPopup and dropPopup.owner == self then
		HideDropPopup()
	end
end

-- ============================================================
-- AceConfig select-type interface
-- ============================================================

---Set the display label (option name / theme name).
---Also auto-loads the theme preview image via the setup style image path.
local function SetLabel(self, text)
	self.label:SetText(text or '')
	-- Auto-set theme image from label text (matches setup image naming convention)
	if text and text ~= '' then
		self.imageBtn:SetNormalTexture('interface\\addons\\SpartanUI\\images\\setup\\Style_' .. text)
	end
end

---Called by AceConfig after SetValue with the display string of the current value.
---We use it to update the dropdown display text directly.
local function SetText(self, text)
	self.dropText:SetText(text or '')
end

---Set the currently selected variant id. Updates the dropdown text from the list.
local function SetValue(self, value)
	self.value = value
	if value and self.list and self.list[value] then
		self.dropText:SetText(self.list[value])
	end
end

local function GetValue(self)
	return self.value
end

---Set the list of variants. list = { [variantId] = displayLabel }
---order (optional) = { variantId, ... } for display order
local function SetList(self, list, order)
	self.list = list or {}
	self.listOrder = {}
	if order then
		for i = 1, #order do
			self.listOrder[i] = order[i]
		end
	else
		for k in pairs(self.list) do
			table.insert(self.listOrder, k)
		end
	end
end

local function SetDisabled(self, disabled)
	self.disabled = disabled
	if disabled then
		self.label:SetTextColor(0.5, 0.5, 0.5)
		self.dropText:SetTextColor(0.5, 0.5, 0.5)
		self.dropBtn:Disable()
	else
		self.label:SetTextColor(1, 0.82, 0)
		self.dropText:SetTextColor(1, 1, 1)
		self.dropBtn:Enable()
	end
end

-- Dummy methods to satisfy AceConfig's full select-widget interface
local function AddItem(self, key, value)
	self.list = self.list or {}
	self.list[key] = value
	self.listOrder = self.listOrder or {}
	table.insert(self.listOrder, key)
end

local SetItemValue = AddItem
local function SetMultiselect(self, flag) end
local function GetMultiselect()
	return false
end
local function SetItemDisabled(self, key) end

-- ============================================================
-- Extra API (for setup wizard usage)
-- ============================================================

---Manually set the theme preview image (overrides the auto-set from SetLabel).
local function SetThemeImage(self, texture)
	self.imageBtn:SetNormalTexture(texture)
end

---Override the default 120×60 image size.
local function SetImageSize(self, w, h)
	self.imageBtn:SetSize(w or 120, h or 60)
	self.dropBtn:SetPoint('TOP', self.imageBtn, 'BOTTOM', 0, -3)
end

-- ============================================================
-- Constructor
-- ============================================================

local function Constructor()
	local frame = CreateFrame('Frame', nil, UIParent)
	frame:SetSize(120, 107)
	frame:Hide()

	local self = {}
	self.type = widgetType
	self.frame = frame
	frame.obj = self

	-- Theme name label at top
	local label = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
	label:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, -2)
	label:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, -2)
	label:SetHeight(20)
	label:SetJustifyH('CENTER')
	label:SetText('')
	self.label = label

	-- Image preview button
	local imageBtn = CreateFrame('Button', nil, frame)
	imageBtn:SetSize(120, 60)
	imageBtn:SetPoint('TOP', label, 'BOTTOM', 0, -2)
	imageBtn:SetHighlightAtlas('UI-CharacterCreate-LargeButton-Blue-Highlight', 'ADD')
	imageBtn:SetScript('OnClick', function(btn)
		local widget = btn:GetParent().obj
		if widget.value then
			widget:Fire('OnValueChanged', widget.value)
		elseif widget.listOrder and widget.listOrder[1] then
			widget.value = widget.listOrder[1]
			if widget.list and widget.list[widget.value] then
				widget.dropText:SetText(widget.list[widget.value])
			end
			widget:Fire('OnValueChanged', widget.value)
		end
	end)
	self.imageBtn = imageBtn

	-- Dropdown button row
	local dropBtn = CreateFrame('Button', nil, frame)
	dropBtn:SetSize(120, 22)
	dropBtn:SetPoint('TOP', imageBtn, 'BOTTOM', 0, -3)
	dropBtn.obj = self
	self.dropBtn = dropBtn

	local dropBg = dropBtn:CreateTexture(nil, 'BACKGROUND')
	dropBg:SetAllPoints(dropBtn)
	dropBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

	local dropText = dropBtn:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	dropText:SetPoint('LEFT', dropBtn, 'LEFT', 6, 0)
	dropText:SetPoint('RIGHT', dropBtn, 'RIGHT', -18, 0)
	dropText:SetJustifyH('LEFT')
	dropText:SetText('')
	self.dropText = dropText

	local arrow = dropBtn:CreateTexture(nil, 'OVERLAY')
	arrow:SetSize(16, 16)
	arrow:SetPoint('RIGHT', dropBtn, 'RIGHT', -2, 0)
	arrow:SetTexture('Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up')

	dropBtn:SetScript('OnClick', function(btn)
		ShowDropPopup(btn.obj)
	end)

	frame:SetScript('OnHide', OnHide)

	-- Assign all methods
	self.OnAcquire = OnAcquire
	self.OnRelease = OnRelease
	self.ClearFocus = ClearFocus
	self.SetLabel = SetLabel
	self.SetText = SetText
	self.SetValue = SetValue
	self.GetValue = GetValue
	self.SetList = SetList
	self.SetDisabled = SetDisabled
	self.AddItem = AddItem
	self.SetItemValue = SetItemValue
	self.SetMultiselect = SetMultiselect
	self.GetMultiselect = GetMultiselect
	self.SetItemDisabled = SetItemDisabled
	self.SetThemeImage = SetThemeImage
	self.SetImageSize = SetImageSize

	AceGUI:RegisterAsWidget(self)
	return self
end

AceGUI:RegisterWidgetType(widgetType, Constructor, widgetVersion)
