---@class SUI
local SUI = SUI
local L = SUI.L
local Style = SUI.UI.Style

-- The Stage: a live preview docked above the settings in the options window. Modules register
-- a provider for a part of the options tree; the Stage shows the provider that matches the
-- page being viewed and refreshes it (at most once per frame) when a setting changes.

---@class SUI.OptionsWindow.StageProvider
---@field path string[] Options path prefix this provider covers, e.g. { 'UnitFrames' }
---@field GetHeight fun(self, ctx: SUI.OptionsWindow.StageContext): number Height wanted (0 = nothing to show)
---@field Render fun(self, ctx: SUI.OptionsWindow.StageContext) Draw or refresh the preview
---@field Hide? fun(self) Hide everything the provider drew
---@field Footer? fun(self, ctx: SUI.OptionsWindow.StageContext): {text: string, tooltip?: string, func: fun()}|nil Optional button shown at the bottom of the panel
---@field Close? fun(self) Called when the options window closes
---@field Action? fun(self, ctx: SUI.OptionsWindow.StageContext): {text: string, tooltip?: string, active?: boolean, func: fun()}|nil Optional button shown in the panel header

---@class SUI.OptionsWindow.StageContext
---@field path string[] Selected options path
---@field canvas Frame Frame to draw into
---@field Region fun(frame: Frame, target: {path: string[], option?: string, label?: string, onShiftClick?: fun()})

---@class SUI.OptionsWindow.Stage
local Stage = {}
SUI.OptionsWindow = SUI.OptionsWindow or {}
SUI.OptionsWindow.Stage = Stage

local APP = 'SpartanUI'
local HEADER = 42
local PANEL_WIDTH = 340

---@type SUI.OptionsWindow.StageProvider[]
local providers = {}
---@type SUI.OptionsWindow.StageProvider|nil
local current
local currentPath = {}
local collapsed = false
local dirty = false
local regions = {}
local usedRegions = 0

---@param provider SUI.OptionsWindow.StageProvider
function Stage:Register(provider)
	providers[#providers + 1] = provider
end

---Provider with the longest path prefix matching `path`
---@param path string[]
---@return SUI.OptionsWindow.StageProvider|nil
local function Match(path)
	local best, bestLength = nil, -1
	for _, provider in ipairs(providers) do
		local matches = #provider.path <= #path
		for i = 1, #provider.path do
			if provider.path[i] ~= path[i] then
				matches = false
			end
		end
		if matches and #provider.path > bestLength then
			best, bestLength = provider, #provider.path
		end
	end
	return best
end

local function GetWindow()
	local ACD = LibStub('AceConfigDialog-3.0-SUI', true)
	local window = ACD and ACD.OpenFrames[APP]
	if window and window.stage then
		return window
	end
	return nil
end

local function SamePath(a, b)
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

----------------------------------------------------------------------------------------------------
-- Stage chrome
----------------------------------------------------------------------------------------------------

---@param window table
function Stage:Setup(window)
	local stage = window.stage
	if stage.canvas then
		return
	end
	local header = CreateFrame('Frame', nil, stage)
	header:SetPoint('TOPLEFT')
	header:SetPoint('TOPRIGHT')
	header:SetHeight(HEADER)
	header:EnableMouse(true)
	header:SetScript('OnMouseDown', function()
		window.frame:StartMoving()
	end)
	header:SetScript('OnMouseUp', function()
		window.frame:StopMovingOrSizing()
		window:PlaceStage()
	end)
	Style:CreateFill(header, Style.color.header)
	stage.header = header

	local title = Style:CreateText(header, 12, Style.color.muted)
	title:SetPoint('TOPLEFT', 12, -8)
	title:SetText(L['Preview'])
	stage.title = title

	local hint = Style:CreateText(header, 9, Style.color.faint)
	hint:SetPoint('TOPLEFT', title, 'BOTTOMLEFT', 0, -3)
	hint:SetPoint('RIGHT', header, 'RIGHT', -10, 0)
	hint:SetJustifyH('LEFT')
	hint:SetText(L['Click a part to jump to its settings'])
	stage.hint = hint

	local toggle = Style:CreateButton(header, L['Hide'], 60, function()
		Stage:SetCollapsed(true)
	end)
	toggle:SetHeight(20)
	toggle:SetPoint('RIGHT', header, 'RIGHT', -10, 0)
	stage.toggle = toggle

	local action = Style:CreateButton(header, '', nil, function(self)
		if self.onAction then
			self.onAction()
			Stage:MarkDirty()
		end
	end)
	action:SetHeight(20)
	action:SetPoint('RIGHT', toggle, 'LEFT', -6, 0)
	action:Hide()
	stage.action = action

	-- Sits in the window's title bar while the panel is hidden
	local reopen = Style:CreateButton(window.header, L['Show preview'], nil, function()
		Stage:SetCollapsed(false)
	end)
	reopen:SetHeight(22)
	reopen:SetPoint('RIGHT', window.header, 'RIGHT', -44, 0)
	reopen:Hide()
	stage.reopen = reopen

	local canvas = CreateFrame('Frame', nil, stage)
	canvas:SetPoint('TOPLEFT', header, 'BOTTOMLEFT', 1, -1)
	canvas:SetPoint('BOTTOMRIGHT', -1, 1)
	if canvas.SetClipsChildren then
		canvas:SetClipsChildren(true)
	end
	stage.canvas = canvas

	local footer = Style:CreateButton(canvas, '', nil, function(self)
		if self.onAction then
			self.onAction()
			Stage:MarkDirty()
		end
	end)
	footer:SetHeight(20)
	footer:SetPoint('BOTTOM', canvas, 'BOTTOM', 0, 6)
	footer:SetFrameLevel(canvas:GetFrameLevel() + 900)
	footer:Hide()
	stage.footer = footer

	window.frame:HookScript('OnHide', function()
		Stage:HideProvider()
		for _, provider in ipairs(providers) do
			if provider.Close then
				provider:Close()
			end
		end
	end)
end

---Hide the preview panel (a button brings it back) or show it again
---@param value boolean
function Stage:SetCollapsed(value)
	collapsed = value and true or false
	self:Refresh(true)
end

---Clickable area over part of the preview
---@param frame Frame
---@param target {path: string[], option?: string, label?: string, onShiftClick?: fun()}
local function Region(frame, target)
	local window = GetWindow()
	if not window or not frame or not frame:IsShown() then
		return
	end
	usedRegions = usedRegions + 1
	local region = regions[usedRegions]
	if not region then
		region = CreateFrame('Button', nil, window.stage.canvas)
		region.border = Style:CreateBorder(region)
		region.border:SetShown(false)
		region:SetScript('OnEnter', function(self)
			local r, g, b = Style:GetAccent()
			self.border:SetColor(r, g, b, 1)
			self.border:SetShown(true)
			if self.target.label then
				GameTooltip:SetOwner(self, 'ANCHOR_TOP')
				GameTooltip:SetText(self.target.label, 1, 1, 1)
				GameTooltip:AddLine(L['Click to change these settings'], nil, nil, nil, true)
				if self.target.onShiftClick then
					GameTooltip:AddLine(L['Shift+click to hide it from the preview'], nil, nil, nil, true)
				end
				GameTooltip:Show()
			end
		end)
		region:SetScript('OnLeave', function(self)
			self.border:SetShown(self.selected and true or false)
			GameTooltip:Hide()
		end)
		region:SetScript('OnClick', function(self)
			if IsShiftKeyDown() and self.target.onShiftClick then
				GameTooltip:Hide()
				self.target.onShiftClick()
				Stage:MarkDirty()
				return
			end
			local ACD = LibStub('AceConfigDialog-3.0-SUI')
			ACD:Navigate(APP, self.target.path, self.target.option)
		end)
		regions[usedRegions] = region
	end
	region.target = target
	region:ClearAllPoints()
	region:SetAllPoints(frame)
	-- Later regions sit above earlier ones, so register large parts first and small parts last
	region:SetFrameStrata(window.stage.canvas:GetFrameStrata())
	region:SetFrameLevel(window.stage.canvas:GetFrameLevel() + 150 + usedRegions)
	region.selected = SamePath(target.path, currentPath)
	if region.selected then
		local r, g, b = Style:GetAccent()
		region.border:SetColor(r, g, b, 0.9)
	end
	region.border:SetShown(region.selected)
	region:Show()
end

----------------------------------------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------------------------------------

function Stage:HideProvider()
	local window = GetWindow()
	if window and window.stage.footer then
		window.stage.footer:Hide()
	end
	if current and current.Hide then
		current:Hide()
	end
	for i = 1, #regions do
		regions[i]:Hide()
	end
end

---Redraw the stage for the current page
---@param resize? boolean Also re-open or close the panel
function Stage:Refresh(resize)
	dirty = false
	local window = GetWindow()
	if not window then
		return
	end
	self:Setup(window)
	local stage = window.stage
	local provider = Match(currentPath)
	if provider ~= current then
		self:HideProvider()
		current = provider
		resize = true
	end

	local ctx = { path = currentPath, canvas = stage.canvas, Region = Region }
	local wanted = provider and (provider:GetHeight(ctx) or 0) > 0
	if not wanted then
		self:HideProvider()
		stage.reopen:Hide()
		window:SetStageWidth(0)
		return
	end
	if collapsed then
		self:HideProvider()
		window:SetStageWidth(0)
		stage.reopen:FitText()
		stage.reopen:Show()
		return
	end
	stage.reopen:Hide()
	if resize or window.stageWidth <= 0 then
		window:SetStageWidth(PANEL_WIDTH)
	end

	for i = 1, #regions do
		regions[i]:Hide()
	end
	usedRegions = 0
	provider:Render(ctx)

	local footerInfo = provider.Footer and provider:Footer(ctx)
	local footer = stage.footer
	if footerInfo then
		footer.onAction = footerInfo.func
		footer:SetText(footerInfo.text)
		footer:SetTooltip(footerInfo.tooltip)
		footer:Show()
	else
		footer:Hide()
	end

	local actionInfo = provider.Action and provider:Action(ctx)
	local action = stage.action
	if actionInfo then
		action.onAction = actionInfo.func
		action:SetText(actionInfo.text)
		action:SetTooltip(actionInfo.tooltip)
		action:SetActive(actionInfo.active)
		action:Show()
		stage.hint:SetPoint('RIGHT', action, 'LEFT', -6, 0)
	else
		action:Hide()
		stage.hint:SetPoint('RIGHT', stage.header, 'RIGHT', -10, 0)
	end
end

---@param path string[]
function Stage:OnGroupSelected(path)
	currentPath = path or {}
	self:Refresh(true)
end

-- Settings changes can arrive every frame while a slider drags; draw at most once per frame
local driver = CreateFrame('Frame')
driver:Hide()
driver:SetScript('OnUpdate', function(self)
	self:Hide()
	if dirty then
		Stage:Refresh(false)
	end
end)

function Stage:MarkDirty()
	dirty = true
	driver:Show()
end

local ACD = LibStub('AceConfigDialog-3.0-SUI', true)
if ACD and ACD.RegisterCallback then
	ACD.RegisterCallback(Stage, 'GroupSelected', function(_, appName, path)
		if appName == APP then
			Stage:OnGroupSelected(path)
		end
	end)
	ACD.RegisterCallback(Stage, 'OptionSet', function(_, appName)
		if appName == APP then
			Stage:MarkDirty()
		end
	end)
end
