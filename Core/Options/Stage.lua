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
---@field zoomable? boolean The player can zoom with the mouse wheel and drag the preview around

---@class SUI.OptionsWindow.StageContext
---@field path string[] Selected options path
---@field canvas Frame Frame to draw into (sized like the panel; zoom and dragging move it as a whole)
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
local views = {} -- zoom and drag per page: views[key] = { zoom, x, y }
local NO_VIEW = { zoom = 1, x = 0, y = 0 }
local MAX_ZOOM = 4

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
	local ACD = LibStub('AceConfigDialog-3.0-LibAT', true)
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
-- Zoom and drag
----------------------------------------------------------------------------------------------------

---The zoom and drag of the page being shown (each unit frame keeps its own while the window is open)
---@return table view
local function CurrentView()
	if not current or not current.zoomable then
		return NO_VIEW
	end
	local key = table.concat(currentPath, '', 1, math.min(#currentPath, 2))
	views[key] = views[key] or { zoom = 1, x = 0, y = 0 }
	return views[key]
end

---Move and scale the drawing layer to the current view
---@param stage table
local function ApplyView(stage)
	local view = CurrentView()
	local canvas, layer = stage.canvas, stage.view
	local width, height = canvas:GetSize()
	-- Keep part of the preview on screen however far it is dragged
	view.x = math.max(-width * view.zoom / 2, math.min(width * view.zoom / 2, view.x))
	view.y = math.max(-height * view.zoom / 2, math.min(height * view.zoom / 2, view.y))
	layer:SetSize(math.max(1, width), math.max(1, height))
	layer:SetScale(view.zoom)
	layer:ClearAllPoints()
	-- Offsets are in the layer's own (zoomed) units
	layer:SetPoint('CENTER', canvas, 'CENTER', view.x / view.zoom, view.y / view.zoom)
	if stage.resetView then
		stage.resetView:SetShown(view ~= NO_VIEW and (view.zoom ~= 1 or view.x ~= 0 or view.y ~= 0))
	end
end

---Cursor position relative to the canvas center, in canvas units
local function CursorOffset(canvas)
	local scale = canvas:GetEffectiveScale()
	local x, y = GetCursorPosition()
	local cx, cy = canvas:GetCenter()
	return x / scale - (cx or 0), y / scale - (cy or 0)
end

---Zoom in or out around the cursor
---@param stage table
---@param delta number
local function Zoom(stage, delta)
	local view = CurrentView()
	if view == NO_VIEW then
		return
	end
	local old = view.zoom
	view.zoom = math.max(1, math.min(MAX_ZOOM, old * (delta > 0 and 1.25 or 0.8)))
	if view.zoom == 1 then
		view.x, view.y = 0, 0
	else
		-- The point under the cursor stays under the cursor
		local mx, my = CursorOffset(stage.canvas)
		local factor = view.zoom / old
		view.x = mx - (mx - view.x) * factor
		view.y = my - (my - view.y) * factor
	end
	ApplyView(stage)
end

-- Drags the preview while the left button is held
local panner = CreateFrame('Frame')
panner:Hide()
panner:SetScript('OnUpdate', function(self)
	if not IsMouseButtonDown('LeftButton') then
		self:Hide()
		return
	end
	local x, y = CursorOffset(self.stage.canvas)
	self.view.x = self.startX + x - self.cursorX
	self.view.y = self.startY + y - self.cursorY
	ApplyView(self.stage)
end)

---@param stage table
local function StartPan(stage)
	local view = CurrentView()
	if view == NO_VIEW then
		return
	end
	panner.stage, panner.view = stage, view
	panner.cursorX, panner.cursorY = CursorOffset(stage.canvas)
	panner.startX, panner.startY = view.x, view.y
	panner:Show()
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

	-- Previews draw on this layer, so zooming and dragging never need a redraw
	local layer = CreateFrame('Frame', nil, canvas)
	layer:SetPoint('CENTER')
	layer:SetSize(1, 1)
	stage.view = layer
	canvas:SetScript('OnSizeChanged', function()
		ApplyView(stage)
	end)
	canvas:EnableMouseWheel(true)
	canvas:SetScript('OnMouseWheel', function(_, delta)
		Zoom(stage, delta)
	end)
	canvas:EnableMouse(true)
	canvas:SetScript('OnMouseDown', function(_, button)
		if button == 'LeftButton' then
			StartPan(stage)
		end
	end)

	local resetView = Style:CreateButton(canvas, L['Reset zoom'], nil, function()
		local view = CurrentView()
		view.zoom, view.x, view.y = 1, 0, 0
		ApplyView(stage)
	end)
	resetView:SetHeight(20)
	resetView:FitText()
	resetView:SetPoint('TOPRIGHT', canvas, 'TOPRIGHT', -6, -6)
	resetView:SetFrameLevel(canvas:GetFrameLevel() + 900)
	resetView:Hide()
	stage.resetView = resetView

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

----------------------------------------------------------------------------------------------------
-- Click areas
----------------------------------------------------------------------------------------------------

-- The click areas under the cursor (topmost first) and the one Alt has stepped down to
local hover = { stack = {}, depth = 1 }

---@param region Button
---@param highlighted boolean
local function PaintBorder(region, highlighted)
	local r, g, b = Style:GetAccent()
	if highlighted then
		region.border:SetColor(r, g, b, 1)
		region.border:SetShown(true)
	elseif region.selected then
		region.border:SetColor(r, g, b, 0.9)
		region.border:SetShown(true)
	else
		region.border:SetShown(false)
	end
end

---Every shown click area under the cursor, topmost first
---@return Button[]
local function RegionsUnderCursor()
	local list = {}
	for i = 1, usedRegions do
		local region = regions[i]
		if region:IsShown() and region:IsMouseOver() then
			list[#list + 1] = region
		end
	end
	table.sort(list, function(a, b)
		return a:GetFrameLevel() > b:GetFrameLevel()
	end)
	return list
end

---The click area a click on `region` acts on: the one Alt stepped down to, or the region itself
---@param region Button
---@return Button
local function Picked(region)
	if hover.owner == region and hover.stack[hover.depth] then
		return hover.stack[hover.depth]
	end
	return region
end

local function ClearHover()
	for _, region in ipairs(hover.stack) do
		PaintBorder(region, false)
	end
	hover.owner = nil
	hover.stack = {}
	hover.depth = 1
end

local function ShowHover()
	local owner = hover.owner
	if not owner then
		return
	end
	local picked = Picked(owner)
	for _, region in ipairs(hover.stack) do
		PaintBorder(region, region == picked)
	end
	PaintBorder(picked, true)
	local target = picked.target
	if not target.label then
		GameTooltip:Hide()
		return
	end
	GameTooltip:SetOwner(owner, 'ANCHOR_TOP')
	GameTooltip:SetText(target.label, 1, 1, 1)
	GameTooltip:AddLine(L['Click to change these settings'], nil, nil, nil, true)
	if target.onShiftClick then
		GameTooltip:AddLine(L['Shift+click to hide it from the preview'], nil, nil, nil, true)
	end
	if #hover.stack > 1 then
		GameTooltip:AddLine(string.format(L['Press Alt for the part underneath (%d of %d)'], hover.depth, #hover.stack), 0.55, 0.8, 1, true)
	end
	GameTooltip:Show()
end

-- Alt steps down through the parts stacked under the cursor, then back to the top one
local altWatcher = CreateFrame('Frame')
altWatcher:RegisterEvent('MODIFIER_STATE_CHANGED')
altWatcher:SetScript('OnEvent', function(_, _, key, down)
	if down ~= 1 or (key ~= 'LALT' and key ~= 'RALT') then
		return
	end
	local owner = hover.owner
	if not owner or not owner:IsVisible() or not owner:IsMouseOver() then
		return
	end
	local current = Picked(owner)
	for _, region in ipairs(hover.stack) do
		PaintBorder(region, false)
	end
	-- The cursor may have moved since it entered; look again
	hover.stack = RegionsUnderCursor()
	local index = 0
	for i, region in ipairs(hover.stack) do
		if region == current then
			index = i
		end
	end
	hover.depth = #hover.stack > 0 and (index % #hover.stack + 1) or 1
	ShowHover()
end)

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
		region:RegisterForDrag('LeftButton')
		region:SetScript('OnMouseDown', function(self)
			self.dragged = nil
		end)
		region:SetScript('OnDragStart', function(self)
			self.dragged = true
			GameTooltip:Hide()
			StartPan(window.stage)
		end)
		region:SetScript('OnEnter', function(self)
			ClearHover()
			hover.owner = self
			hover.stack = RegionsUnderCursor()
			if #hover.stack == 0 then
				hover.stack = { self }
			end
			ShowHover()
		end)
		region:SetScript('OnLeave', function(self)
			ClearHover()
			PaintBorder(self, false)
			GameTooltip:Hide()
		end)
		region:SetScript('OnClick', function(self)
			if self.dragged then
				self.dragged = nil
				return
			end
			local target = Picked(self).target
			if IsShiftKeyDown() and target.onShiftClick then
				GameTooltip:Hide()
				target.onShiftClick()
				Stage:MarkDirty()
				return
			end
			local ACD = LibStub('AceConfigDialog-3.0-LibAT')
			ACD:Navigate(APP, target.path, target.option)
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

	local ctx = { path = currentPath, canvas = stage.view, Region = Region }
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

	ClearHover()
	for i = 1, #regions do
		regions[i]:Hide()
	end
	usedRegions = 0
	ApplyView(stage)
	stage.hint:SetText(provider.zoomable and L['Click a part to change it. Scroll to zoom, drag to move.'] or L['Click a part to jump to its settings'])
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

local ACD = LibStub('AceConfigDialog-3.0-LibAT', true)
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
