---@class SUI
local SUI = SUI
local L = SUI.L
---@class MoveIt
local MoveIt = SUI.MoveIt
local Style = SUI.UI.Style

-- Small panel next to the selected frame: exact position, centering, size, attaching to
-- another frame, reset, and a link to the frame's own settings.

---@class SUI.MoveIt.Inspector
local Inspector = {}
MoveIt.Inspector = Inspector

local WIDTH = 244
local PAD = 10
local SCALE_STEP = 0.05

local POINT_NAMES = {
	TOPLEFT = 'top left',
	TOP = 'top',
	TOPRIGHT = 'top right',
	LEFT = 'left side',
	CENTER = 'middle',
	RIGHT = 'right side',
	BOTTOMLEFT = 'bottom left',
	BOTTOM = 'bottom',
	BOTTOMRIGHT = 'bottom right',
}

---@type SUI.MoveIt.Mover|nil
Inspector.mover = nil

function Inspector:Create()
	if self.panel then
		return self.panel
	end
	local Widgets = MoveIt.Widgets
	local panel = CreateFrame('Frame', 'SUI_MoveIt_Inspector', UIParent)
	panel:SetWidth(WIDTH)
	panel:SetFrameStrata('FULLSCREEN')
	panel:SetFrameLevel(60)
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:Hide()
	Style:SkinPanel(panel, Style.color.raised, Style.color.lineStrong)

	local topLine = panel:CreateTexture(nil, 'OVERLAY')
	topLine:SetTexture(Style.WHITE)
	topLine:SetPoint('TOPLEFT')
	topLine:SetPoint('TOPRIGHT')
	topLine:SetHeight(Style:PixelSize(panel) * 2)
	Style:OnAccentChanged(panel, function(r, g, b)
		topLine:SetVertexColor(r, g, b, 1)
	end)

	panel.title = Style:CreateText(panel, 13)
	panel.title:SetPoint('TOPLEFT', PAD, -PAD)
	panel.title:SetPoint('RIGHT', panel, 'RIGHT', -30, 0)
	panel.title:SetJustifyH('LEFT')
	panel.title:SetWordWrap(false)

	panel.group = Style:CreateText(panel, 9, Style.color.muted)
	panel.group:SetPoint('TOPLEFT', panel.title, 'BOTTOMLEFT', 0, -2)

	local close = Widgets:Button(panel, 'x', 20, function()
		MoveIt.MoverMode:Select(nil)
	end)
	close:SetPoint('TOPRIGHT', -6, -6)

	local y = -44
	local function Row(height)
		local top = y
		y = y - height
		return top
	end

	-- Position
	local posCaption = Widgets:Caption(panel, L['Position'])
	posCaption:SetPoint('TOPLEFT', PAD, Row(14))
	local xLabel = Style:CreateText(panel, 11, Style.color.muted)
	xLabel:SetText('X')
	local rowTop = Row(26)
	xLabel:SetPoint('TOPLEFT', PAD, rowTop - 4)
	panel.xBox = Widgets:NumberBox(panel, 70, function(value)
		Inspector:SetOffset(value, nil)
	end)
	panel.xBox:SetPoint('TOPLEFT', PAD + 14, rowTop)
	local yLabel = Style:CreateText(panel, 11, Style.color.muted)
	yLabel:SetText('Y')
	yLabel:SetPoint('TOPLEFT', PAD + 104, rowTop - 4)
	panel.yBox = Widgets:NumberBox(panel, 70, function(value)
		Inspector:SetOffset(nil, value)
	end)
	panel.yBox:SetPoint('TOPLEFT', PAD + 118, rowTop)

	panel.measured = Style:CreateText(panel, 9, Style.color.faint)
	panel.measured:SetPoint('TOPLEFT', PAD, Row(16))
	panel.measured:SetPoint('RIGHT', panel, 'RIGHT', -PAD, 0)
	panel.measured:SetJustifyH('LEFT')

	rowTop = Row(28)
	local half = (WIDTH - PAD * 2 - 6) / 2
	local centerX = Widgets:Button(panel, L['Center left to right'], half, function()
		Inspector:Center(true, false)
	end)
	centerX:SetPoint('TOPLEFT', PAD, rowTop)
	local centerY = Widgets:Button(panel, L['Center top to bottom'], half, function()
		Inspector:Center(false, true)
	end)
	centerY:SetPoint('TOPLEFT', centerX, 'TOPRIGHT', 6, 0)

	-- Size
	local sizeCaption = Widgets:Caption(panel, L['Size'])
	sizeCaption:SetPoint('TOPLEFT', PAD, Row(16))
	rowTop = Row(28)
	panel.smaller = Widgets:Button(panel, '-', 26, function()
		Inspector:StepScale(-SCALE_STEP)
	end)
	panel.smaller:SetPoint('TOPLEFT', PAD, rowTop)
	panel.scaleText = Style:CreateText(panel, 12)
	panel.scaleText:SetPoint('LEFT', panel.smaller, 'RIGHT', 0, 0)
	panel.scaleText:SetWidth(52)
	panel.scaleText:SetJustifyH('CENTER')
	panel.bigger = Widgets:Button(panel, '+', 26, function()
		Inspector:StepScale(SCALE_STEP)
	end)
	panel.bigger:SetPoint('LEFT', panel.scaleText, 'RIGHT', 0, 0)
	panel.resetScale = Widgets:Button(panel, L['Normal size'], WIDTH - PAD * 2 - 110, function()
		if Inspector.mover then
			MoveIt:SetMoverScale(Inspector.mover, nil)
			Inspector:Refresh()
		end
	end)
	panel.resetScale:SetPoint('TOPRIGHT', -PAD, rowTop)
	panel.scaleRow = { panel.smaller, panel.scaleText, panel.bigger, panel.resetScale }

	-- Attach
	local attachCaption = Widgets:Caption(panel, L['Attach'])
	attachCaption:SetPoint('TOPLEFT', PAD, Row(16))
	panel.attachText = Style:CreateText(panel, 10, Style.color.muted)
	panel.attachText:SetPoint('TOPLEFT', PAD, Row(16))
	panel.attachText:SetPoint('RIGHT', panel, 'RIGHT', -PAD, 0)
	panel.attachText:SetJustifyH('LEFT')
	panel.attachText:SetWordWrap(true)
	rowTop = Row(28)
	panel.attachButton = Widgets:Button(panel, L['Attach to another frame'], WIDTH - PAD * 2, function()
		local mover = Inspector.mover
		if not mover then
			return
		end
		if MoveIt:GetAnchorMover(mover) then
			MoveIt.Anchors:Detach(mover)
			Inspector:Refresh()
			MoveIt.MoverMode:RefreshMover(mover)
		else
			MoveIt.Anchors:BeginPick(mover)
		end
	end)
	panel.attachButton:SetPoint('TOPLEFT', PAD, rowTop)

	-- Actions
	local rule = Widgets:Rule(panel)
	rowTop = Row(10)
	rule:SetPoint('TOPLEFT', PAD, rowTop - 4)
	rule:SetPoint('TOPRIGHT', -PAD, rowTop - 4)
	rowTop = Row(28)
	local resetPos = Widgets:Button(panel, L['Reset position'], half, function()
		if Inspector.mover then
			MoveIt:Reset(Inspector.mover.name, true)
			MoveIt.MoverMode:RefreshMover(Inspector.mover)
			Inspector:Refresh()
		end
	end)
	resetPos:SetPoint('TOPLEFT', PAD, rowTop)
	local hide = Widgets:Button(panel, L['Hide for now'], half, function()
		local mover = Inspector.mover
		if mover then
			MoveIt.MoverMode:Select(nil)
			mover:Hide()
		end
	end)
	hide:SetTooltip(L['Hide this box until you close frame moving, so you can reach what is under it.'])
	hide:SetPoint('TOPLEFT', resetPos, 'TOPRIGHT', 6, 0)
	rowTop = Row(28)
	local settings = Widgets:Button(panel, L["Open this frame's settings"], WIDTH - PAD * 2, function()
		local mover = Inspector.mover
		if not mover then
			return
		end
		local path = MoveIt:GetOptionsPath(mover)
		MoveIt.MoverMode:Exit(false)
		if SUI.Options.OpenTo then
			SUI.Options:OpenTo(path)
		else
			SUI.Options:ToggleOptions(path)
		end
	end)
	settings:SetPoint('TOPLEFT', PAD, rowTop)

	panel:SetHeight(-y + PAD - 4)
	self.panel = panel
	return panel
end

---@param mover SUI.MoveIt.Mover|nil
function Inspector:Show(mover)
	if not mover then
		self:Hide()
		return
	end
	local panel = self:Create()
	self.mover = mover
	self:Refresh()
	self:Place()
	if not panel:IsShown() then
		panel:SetAlpha(0)
		panel:Show()
		Style:FadeTo(panel, 1, 0.12)
	end
end

function Inspector:Hide()
	self.mover = nil
	if self.panel then
		self.panel:Hide()
	end
end

---@return boolean
function Inspector:IsShown()
	return self.panel ~= nil and self.panel:IsShown()
end

---Put the panel beside the mover where it fits
function Inspector:Place()
	local panel, mover = self.panel, self.mover
	if not panel or not mover then
		return
	end
	local l, b, r, t = MoveIt.Snap:GetRect(mover)
	if not l then
		return
	end
	local ratio = panel:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local width, height = UIParent:GetSize()
	local pw = WIDTH * ratio
	panel:ClearAllPoints()
	if r + pw + 12 < width then
		panel:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', (r + 8) / ratio, math.min(t, height - 70) / ratio)
	elseif l - pw - 12 > 0 then
		panel:SetPoint('TOPRIGHT', UIParent, 'BOTTOMLEFT', (l - 8) / ratio, math.min(t, height - 70) / ratio)
	else
		panel:SetPoint('TOP', UIParent, 'BOTTOMLEFT', ((l + r) / 2) / ratio, (b - 8) / ratio)
	end
end

function Inspector:Refresh()
	local panel, mover = self.panel, self.mover
	if not panel or not mover then
		return
	end
	panel.title:SetText(mover.displayText or mover.name)
	panel.group:SetText(mover.groupName or '')

	local point, _, relativePoint, x, y = mover:GetPoint(1)
	if not panel.xBox:HasFocus() then
		panel.xBox:SetText(MoveIt.PositionCalculator:FormatNumber(MoveIt.PositionCalculator:Round(x or 0, 2)))
	end
	if not panel.yBox:HasFocus() then
		panel.yBox:SetText(MoveIt.PositionCalculator:FormatNumber(MoveIt.PositionCalculator:Round(y or 0, 2)))
	end

	local anchorMover = MoveIt:GetAnchorMover(mover)
	if anchorMover then
		panel.measured:SetText(string.format(L['Measured from the %s of %s'], L[POINT_NAMES[relativePoint] or 'middle'], anchorMover.displayText or anchorMover.name))
		panel.attachText:SetText(string.format(L['Follows %s when it moves.'], anchorMover.displayText or anchorMover.name))
		panel.attachButton:SetText(L['Stop following'])
	else
		panel.measured:SetText(string.format(L['Measured from the %s of the screen'], L[POINT_NAMES[relativePoint or point] or 'middle']))
		panel.attachText:SetText(L['Make this frame follow another frame.'])
		panel.attachButton:SetText(L['Attach to another frame'])
	end

	panel.scaleText:SetText(string.format('%.2f', mover:GetScale() or 1))
	for _, widget in ipairs(panel.scaleRow) do
		if widget.SetEnabled then
			widget:SetEnabled(not mover.noScale)
		end
	end
end

---Set one or both offsets exactly, keeping the anchor
---@param x number|nil
---@param y number|nil
function Inspector:SetOffset(x, y)
	local mover = self.mover
	if not mover or InCombatLockdown() then
		return
	end
	local point, anchor, relativePoint, curX, curY = mover:GetPoint(1)
	mover:ClearAllPoints()
	mover:SetPoint(point, anchor or UIParent, relativePoint, x or curX, y or curY)
	MoveIt:SaveMover(mover)
	MoveIt.MoverMode:RefreshMover(mover)
	self:Refresh()
end

---Move the frame to the middle of the screen on one or both axes
---@param horizontal boolean
---@param vertical boolean
function Inspector:Center(horizontal, vertical)
	local mover = self.mover
	if not mover then
		return
	end
	local l, b, r, t = MoveIt.Snap:GetRect(mover)
	if not l then
		return
	end
	local width, height = UIParent:GetSize()
	local ratio = mover:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local dx = horizontal and (width / 2 - (l + r) / 2) / ratio or 0
	local dy = vertical and (height / 2 - (b + t) / 2) / ratio or 0
	MoveIt:NudgeMover(mover, dx, dy)
	MoveIt.MoverMode:RefreshMover(mover)
	self:Refresh()
end

---@param delta number
function Inspector:StepScale(delta)
	local mover = self.mover
	if not mover then
		return
	end
	local value = math.floor(((mover:GetScale() or 1) + delta) * 100 + 0.5) / 100
	MoveIt:SetMoverScale(mover, value)
	MoveIt.MoverMode:RefreshMover(mover)
	self:Refresh()
	self:Place()
end
