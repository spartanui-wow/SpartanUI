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

---@class SUI.OptionsWindow.StageContext
---@field path string[] Selected options path
---@field canvas Frame Frame to draw into
---@field Region fun(frame: Frame, target: {path: string[], option?: string, label?: string})

---@class SUI.OptionsWindow.Stage
local Stage = {}
SUI.OptionsWindow = SUI.OptionsWindow or {}
SUI.OptionsWindow.Stage = Stage

local APP = 'SpartanUI'
local HEADER = 22

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
	stage.header = header

	local title = Style:CreateText(header, 10, Style.color.muted)
	title:SetPoint('LEFT', 10, 0)
	title:SetText(L['Preview'])
	stage.title = title

	local hint = Style:CreateText(header, 9, Style.color.faint)
	hint:SetPoint('LEFT', title, 'RIGHT', 10, 0)
	hint:SetText(L['Click a part to jump to its settings'])
	stage.hint = hint

	local toggle = Style:CreateButton(header, L['Hide preview'], 96, function(self)
		collapsed = not collapsed
		self:SetText(collapsed and L['Show preview'] or L['Hide preview'])
		Stage:Refresh(true)
	end)
	toggle:SetHeight(18)
	toggle:SetPoint('RIGHT', -6, 0)
	stage.toggle = toggle

	local canvas = CreateFrame('Frame', nil, stage)
	canvas:SetPoint('TOPLEFT', header, 'BOTTOMLEFT', 1, 0)
	canvas:SetPoint('BOTTOMRIGHT', -1, 1)
	if canvas.SetClipsChildren then
		canvas:SetClipsChildren(true)
	end
	stage.canvas = canvas

	window.frame:HookScript('OnHide', function()
		Stage:HideProvider()
	end)
end

---Clickable area over part of the preview
---@param frame Frame
---@param target {path: string[], option?: string, label?: string}
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
				GameTooltip:Show()
			end
		end)
		region:SetScript('OnLeave', function(self)
			self.border:SetShown(self.selected and true or false)
			GameTooltip:Hide()
		end)
		region:SetScript('OnClick', function(self)
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
	if current and current.Hide then
		current:Hide()
	end
	for i = 1, #regions do
		regions[i]:Hide()
	end
end

---Redraw the stage for the current page
---@param resize? boolean Also recompute the dock height
function Stage:Refresh(resize)
	dirty = false
	local window = GetWindow()
	if not window then
		return
	end
	self:Setup(window)
	local provider = Match(currentPath)
	if provider ~= current then
		self:HideProvider()
		current = provider
		resize = true
	end
	if not provider then
		window:SetStageHeight(0)
		return
	end

	local ctx = { path = currentPath, canvas = window.stage.canvas, Region = Region }
	local height = provider:GetHeight(ctx) or 0
	if height <= 0 then
		self:HideProvider()
		window:SetStageHeight(0)
		return
	end
	if resize then
		window:SetStageHeight(collapsed and HEADER or (height + HEADER))
	end
	window.stage.canvas:SetShown(not collapsed)
	window.stage.hint:SetShown(not collapsed)
	if collapsed then
		self:HideProvider()
		return
	end

	for i = 1, #regions do
		regions[i]:Hide()
	end
	usedRegions = 0
	provider:Render(ctx)
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
