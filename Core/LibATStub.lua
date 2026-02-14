-- LibAT Dependency Stub
-- Shows a popup if Libs-AddonTools is not installed
-- This file uses ONLY raw WoW API (no Ace3, no LibAT)

if LibAT then
	return
end

local frame = CreateFrame('Frame')
frame:RegisterEvent('PLAYER_LOGIN')
frame:SetScript('OnEvent', function(self)
	self:UnregisterEvent('PLAYER_LOGIN')

	-- Create popup window
	local popup = CreateFrame('Frame', 'SUI_LibATMissing', UIParent, 'BasicFrameTemplateWithInset')
	popup:SetSize(480, 180)
	popup:SetPoint('CENTER')
	popup:SetFrameStrata('DIALOG')
	popup:SetMovable(true)
	popup:EnableMouse(true)
	popup:RegisterForDrag('LeftButton')
	popup:SetScript('OnDragStart', popup.StartMoving)
	popup:SetScript('OnDragStop', popup.StopMovingOrSizing)

	popup.TitleBg:SetHeight(30)
	popup.title = popup:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	popup.title:SetPoint('TOPLEFT', popup.TitleBg, 'TOPLEFT', 5, -3)
	popup.title:SetText('|cffffffffSpartan|cffe21f1fUI|r - Missing Dependency')

	-- Message
	local msg = popup:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
	msg:SetPoint('TOP', popup, 'TOP', 0, -45)
	msg:SetWidth(440)
	msg:SetText('Please download Libs-AddonTools.\nDue to issues with auto-updaters it was moved out of the main SpartanUI install.')

	-- URL edit box (pre-selected for easy copy)
	local editBox = CreateFrame('EditBox', nil, popup, 'InputBoxTemplate')
	editBox:SetSize(420, 20)
	editBox:SetPoint('TOP', msg, 'BOTTOM', 0, -12)
	editBox:SetAutoFocus(false)
	editBox:SetText('https://www.curseforge.com/wow/addons/libs-addontools')
	editBox:SetScript('OnEditFocusGained', function(self)
		self:HighlightText()
	end)
	editBox:SetScript('OnEscapePressed', function(self)
		self:ClearFocus()
	end)
	editBox:SetScript('OnTextChanged', function(self)
		self:SetText('https://www.curseforge.com/wow/addons/libs-addontools')
		self:HighlightText()
	end)
	editBox:HighlightText()

	-- Close button
	local closeBtn = CreateFrame('Button', nil, popup, 'UIPanelButtonTemplate')
	closeBtn:SetSize(80, 24)
	closeBtn:SetPoint('BOTTOM', popup, 'BOTTOM', 0, 12)
	closeBtn:SetText('Close')
	closeBtn:SetScript('OnClick', function()
		popup:Hide()
	end)

	popup:Show()
	editBox:SetFocus()
end)
