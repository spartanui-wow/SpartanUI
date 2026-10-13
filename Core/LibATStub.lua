-- LibAT Dependency Stub
-- Shows a popup if Libs-AddonTools is not installed, or is too old for this SpartanUI
-- This file uses ONLY raw WoW API (no Ace3, no LibAT)

-- The settings window and its controls live in Libs-AddonTools. Later additions are listed in
-- LibAT.Capabilities (name -> revision), set by the file that builds each feature. Dev builds have
-- no version number, so the feature is tested instead of a version. Every addition below is also
-- feature-detected where it is used, so an old copy never errors: this check only asks for the
-- update.
--   cardArtDraw      cards draw live pictures (the nameplate style cards)
--   searchSynonyms   2: settings search takes an addon's own everyday words
local NEEDED = { cardArtDraw = 1, searchSynonyms = 2 }

local function Current()
	if not (LibAT and LibAT.UI and LibAT.UI.Options) then
		return false
	end
	local caps = LibAT.Capabilities
	if type(caps) ~= 'table' then
		return false
	end
	for name, revision in pairs(NEEDED) do
		if type(caps[name]) ~= 'number' or caps[name] < revision then
			return false
		end
	end
	return true
end

if Current() then
	return
end
local outdated = LibAT ~= nil
-- An old copy has no capability list: give it an empty one, so code that reads an entry gets nil
-- (the feature is missing) and never an error. Nothing is claimed.
if outdated and type(LibAT.Capabilities) ~= 'table' then
	LibAT.Capabilities = {}
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
	popup.title:SetText('|cffffffffSpartan|cffe21f1fUI|r - ' .. (outdated and 'Update Needed' or 'Missing Dependency'))

	-- Message
	local msg = popup:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
	msg:SetPoint('TOP', popup, 'TOP', 0, -45)
	msg:SetWidth(440)
	if outdated then
		msg:SetText('Please update Libs-AddonTools.\nThis version of SpartanUI needs a newer copy to show its settings.')
	else
		msg:SetText('Please download Libs-AddonTools.\nDue to issues with auto-updaters it was moved out of the main SpartanUI install.')
	end

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
