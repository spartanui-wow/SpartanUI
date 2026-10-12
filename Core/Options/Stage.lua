---@class SUI
local SUI = SUI
local L = SUI.L
local Style = SUI.UI.Style

-- The Stage: a live preview in the panel attached beside the options window (LibAT's `stage`
-- frame, sized and placed by the window's SetStageWidth and PlaceStage). Modules register a
-- provider for a part of the options tree; the Stage shows the provider that matches the page
-- being viewed and redraws it (at most once per frame) when a setting changes or the panel
-- changes size.
--
-- Only path, GetHeight and Render are required. Every other provider and target field is
-- optional, and a provider that leaves one out gets the panel exactly as it was before.

---@class SUI.OptionsWindow.StageProvider
---@field path string[] Options path prefix this provider covers, e.g. { 'UnitFrames' }
---@field GetHeight fun(self, ctx: SUI.OptionsWindow.StageContext): number More than 0 shows the panel (it always fills the window's height); 0 hides it
---@field Render fun(self, ctx: SUI.OptionsWindow.StageContext) Draw or refresh the preview
---@field Hide? fun(self) Hide everything the provider drew
---@field Footer? fun(self, ctx: SUI.OptionsWindow.StageContext): {text: string, tooltip?: string, func: fun()}|nil Optional button shown at the bottom of the panel
---@field Close? fun(self) Called when the options window closes
---@field Action? fun(self, ctx: SUI.OptionsWindow.StageContext): {text: string, tooltip?: string, active?: boolean, func: fun()}|nil Optional button shown in the panel header
---@field zoomable? boolean The player can zoom with the mouse wheel and drag the preview around
---@field Title? fun(self, ctx: SUI.OptionsWindow.StageContext): string|nil Panel title (nil keeps "Preview")
---@field Hint? fun(self, ctx: SUI.OptionsWindow.StageContext): string|nil Line under the title (nil keeps the standard hint)
---@field Toolbar? fun(self, ctx: SUI.OptionsWindow.StageContext): SUI.OptionsWindow.StageToolbarItem[]|nil Controls for a strip under the header; the canvas starts below it
---@field width? number|fun(self, ctx: SUI.OptionsWindow.StageContext): number|nil Panel width wanted. Capped at ctx.maxWidth and never below the standard width
---@field overlapPicker? boolean Right-click a part to list every part under the cursor and pick one
---@field refit? boolean Redraw when the canvas changes size, for drawings that fit themselves to the canvas (at most once per frame)

---@class SUI.OptionsWindow.StageContext
---@field path string[] Selected options path
---@field canvas Frame Frame to draw into (sized like the canvas; zoom and dragging move it as a whole)
---@field Region fun(frame: Frame|Texture, target: SUI.OptionsWindow.StageTarget) Clickable area over a part; register large parts first
---@field width number Current panel width
---@field maxWidth number Widest panel the screen has room for beside the window (never below the standard width)

---@class SUI.OptionsWindow.StageTarget
---@field path? string[] Options page a click opens
---@field option? string Option to scroll to on that page
---@field label? string Tooltip title. Parts without one get no tooltip and stay out of the overlap picker
---@field onShiftClick? fun() Shift+click runs this instead of opening the page
---@field selected? boolean Outline the part as selected. When nil, a part is selected when its path is the page being viewed
---@field onClick? fun(target: SUI.OptionsWindow.StageTarget): boolean|nil Runs before the page opens; return true to stay
---@field drag? SUI.OptionsWindow.StageDrag The player can move this part once it is selected
---@field detail? string|fun(target: SUI.OptionsWindow.StageTarget): string|nil Extra tooltip line under the title

---@class SUI.OptionsWindow.StageDrag
---@field Start? fun(target: SUI.OptionsWindow.StageTarget)
---@field Move? fun(dx: number, dy: number, target: SUI.OptionsWindow.StageTarget) Cursor movement since Start, in the dragged frame's own units (fit scale and zoom taken out)
---@field Stop? fun(dx: number, dy: number, target: SUI.OptionsWindow.StageTarget)
---@field Nudge? fun(dx: number, dy: number, target: SUI.OptionsWindow.StageTarget) Arrow keys: 0.5, or 2 with Shift. Without it a nudge runs Start, Move and Stop
---@field Key? fun(key: string, target: SUI.OptionsWindow.StageTarget): boolean|nil Any other key while arrows would nudge, named like a binding ('DELETE', 'CTRL-Z'); return true when handled

---@class SUI.OptionsWindow.StageToolbarItem
---@field kind? 'button'|'toggle'|'select'
---@field text? string Button text (a select shows its label and the picked choice instead)
---@field label? string Select only, e.g. 'Show'
---@field value? any Select only: the picked choice
---@field choices? {value: any, text: string}[] Select only
---@field onSelect? fun(value: any) Select only
---@field onClick? fun() Button and toggle
---@field active? boolean Toggle only
---@field disabled? boolean
---@field disabledReason? string Tooltip while disabled
---@field tooltip? string
---@field align? 'left'|'right'

---@class SUI.OptionsWindow.Stage
local Stage = {}
SUI.OptionsWindow = SUI.OptionsWindow or {}
SUI.OptionsWindow.Stage = Stage

local APP = 'SpartanUI'
local HEADER = 42
local TOOLBAR = 26
local PANEL_WIDTH = 340
-- LibAT keeps 4 between the window and the panel; keep a little more off the screen edge
local SIDE_GAP = 8
local NUDGE_STEP, NUDGE_STEP_BIG = 0.5, 2
local ARROWS = { LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }
local POPUP_ROW, POPUP_PAD = 20, 6

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
-- The selected part the arrow keys move, found while the provider draws
local nudge = {}

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

---Widest panel the screen has room for on either side of the window, measured the way LibAT's
---PlaceStage decides the side, so a width that fits here never hangs off the screen there
---@param window table
---@return number
local function RoomBeside(window)
	local frame = window.frame
	local right, left = frame:GetRight(), frame:GetLeft()
	local screen = UIParent:GetRight() or UIParent:GetWidth()
	if not right or not left or not screen then
		return PANEL_WIDTH
	end
	return math.max(PANEL_WIDTH, math.floor(math.max(screen - right, left) - SIDE_GAP))
end

---@param provider SUI.OptionsWindow.StageProvider
---@param ctx SUI.OptionsWindow.StageContext
---@return number
local function WantedWidth(provider, ctx)
	local width = provider.width
	if type(width) == 'function' then
		width = width(provider, ctx)
	end
	if type(width) ~= 'number' or width <= PANEL_WIDTH then
		return PANEL_WIDTH
	end
	return math.floor(math.min(width, ctx.maxWidth))
end

---Scale of a drawn part, for a frame or a texture (whose scale is its parent's)
local function EffectiveScale(object, fallback)
	if object and object.GetEffectiveScale then
		return object:GetEffectiveScale()
	end
	local parent = object and object.GetParent and object:GetParent()
	if parent and parent.GetEffectiveScale then
		return parent:GetEffectiveScale()
	end
	return fallback:GetEffectiveScale()
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
	local key = table.concat(currentPath, '', 1, math.min(#currentPath, 2))
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
-- Moving a part
----------------------------------------------------------------------------------------------------

-- Moves the selected part while the left button is held
local partDrag = CreateFrame('Frame')
partDrag:Hide()

local function FinishPartDrag()
	if not partDrag:IsShown() then
		return
	end
	partDrag:Hide()
	local target = partDrag.target
	partDrag.target = nil
	if target and target.drag and target.drag.Stop then
		target.drag.Stop(partDrag.dx, partDrag.dy, target)
	end
	Stage:MarkDirty()
end

partDrag:SetScript('OnUpdate', function(self)
	if not IsMouseButtonDown('LeftButton') then
		FinishPartDrag()
		return
	end
	local x, y = GetCursorPosition()
	local dx, dy = (x - self.cursorX) / self.scale, (y - self.cursorY) / self.scale
	if dx ~= self.dx or dy ~= self.dy then
		self.dx, self.dy = dx, dy
		local drag = self.target.drag
		if drag.Move then
			drag.Move(dx, dy, self.target)
		end
	end
end)

---@param region Button
local function StartPartDrag(region)
	FinishPartDrag()
	local target = region.target
	-- The part's own scale holds both the provider's fit scale and the zoom
	local scale = EffectiveScale(region.part, region)
	partDrag.target = target
	partDrag.scale = (scale and scale > 0) and scale or 1
	partDrag.cursorX, partDrag.cursorY = GetCursorPosition()
	partDrag.dx, partDrag.dy = 0, 0
	if target.drag.Start then
		target.drag.Start(target)
	end
	partDrag:Show()
end

----------------------------------------------------------------------------------------------------
-- Small lists (toolbar choices and the overlap picker)
----------------------------------------------------------------------------------------------------

local function CreatePopup(stage)
	local popup = CreateFrame('Frame', nil, stage)
	popup:SetClampedToScreen(true)
	popup:EnableMouse(true)
	Style:SkinPanel(popup, Style.color.raised, Style.color.lineStrong)
	popup.heading = Style:CreateText(popup, 9, Style.color.faint)
	popup.heading:SetPoint('TOPLEFT', POPUP_PAD + 2, -POPUP_PAD)
	popup.rows = {}
	popup:Hide()
	-- A click anywhere else closes it
	popup:SetScript('OnUpdate', function(self)
		local down = IsMouseButtonDown('LeftButton') or IsMouseButtonDown('RightButton')
		if down and not self:IsMouseOver() and not (self.opener and self.opener:IsMouseOver()) then
			self:Hide()
		end
	end)
	popup:SetScript('OnHide', function(self)
		local onClose = self.onClose
		self.onClose, self.opener = nil, nil
		if onClose then
			onClose()
		end
	end)
	stage.popup = popup
	return popup
end

local function PopupRow(popup, index)
	local row = popup.rows[index]
	if row then
		return row
	end
	row = Style:CreateButton(popup, '', nil, function(self)
		local item = self.item
		popup:Hide()
		if item and item.onClick then
			item.onClick()
		end
	end)
	row:SetHeight(POPUP_ROW)
	row:HookScript('OnEnter', function(self)
		if self.item and self.item.onEnter then
			self.item.onEnter()
		end
	end)
	row:HookScript('OnLeave', function(self)
		if self.item and self.item.onLeave then
			self.item.onLeave()
		end
	end)
	popup.rows[index] = row
	return row
end

---Show a list of choices under `opener`, or at the cursor when there is none
---@param stage table
---@param opener? Frame
---@param heading? string
---@param items {text: string, active?: boolean, onClick?: fun(), onEnter?: fun(), onLeave?: fun()}[]
---@param onClose? fun()
local function ShowPopup(stage, opener, heading, items, onClose)
	local popup = stage.popup or CreatePopup(stage)
	if popup:IsShown() then
		popup:Hide()
	end
	popup.heading:SetText(heading or '')
	popup.heading:SetShown(heading ~= nil)
	local top = heading and (POPUP_PAD + 14) or POPUP_PAD
	local width = 140
	for i, item in ipairs(items) do
		local row = PopupRow(popup, i)
		row.item = item
		row:SetText(item.text)
		row:SetActive(item.active)
		width = math.max(width, row:GetWidth())
	end
	for i = #items + 1, #popup.rows do
		popup.rows[i].item = nil
		popup.rows[i]:Hide()
	end
	-- Above the click areas and the zoom button, whatever level the window was raised to
	local level = math.min(stage:GetFrameLevel() + 1200, 9900)
	popup:SetFrameLevel(level)
	for i = 1, #items do
		local row = popup.rows[i]
		row:SetWidth(width)
		row:ClearAllPoints()
		row:SetPoint('TOPLEFT', popup, 'TOPLEFT', POPUP_PAD, -(top + (i - 1) * (POPUP_ROW + 2)))
		row:SetFrameLevel(level + 2)
		row:Show()
	end
	popup:SetSize(width + POPUP_PAD * 2, top + #items * (POPUP_ROW + 2) - 2 + POPUP_PAD)
	popup:ClearAllPoints()
	if opener then
		popup:SetPoint('TOPLEFT', opener, 'BOTTOMLEFT', 0, -2)
	else
		local scale = popup:GetEffectiveScale()
		local x, y = GetCursorPosition()
		popup:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', x / scale + 4, y / scale - 4)
	end
	popup.opener, popup.onClose = opener, onClose
	popup:Show()
end

local function ClosePopup()
	local window = GetWindow()
	local popup = window and window.stage.popup
	if popup and popup:IsShown() then
		popup:Hide()
	end
end

----------------------------------------------------------------------------------------------------
-- Toolbar
----------------------------------------------------------------------------------------------------

---@param item SUI.OptionsWindow.StageToolbarItem
---@return string
local function ChoiceText(item)
	for _, choice in ipairs(item.choices or {}) do
		if choice.value == item.value then
			return choice.text or tostring(choice.value)
		end
	end
	return item.text or ''
end

local function OnToolbarClick(button)
	local item = button.item
	if not item or item.disabled then
		return
	end
	if item.kind ~= 'select' then
		if item.onClick then
			item.onClick()
		end
		Stage:MarkDirty()
		return
	end
	local stage = button.stage
	if stage.popup and stage.popup:IsShown() and stage.popup.opener == button then
		stage.popup:Hide()
		return
	end
	local entries = {}
	for _, choice in ipairs(item.choices or {}) do
		entries[#entries + 1] = {
			text = choice.text or tostring(choice.value),
			active = choice.value == item.value,
			onClick = function()
				if item.onSelect then
					item.onSelect(choice.value)
				end
				Stage:MarkDirty()
			end,
		}
	end
	ShowPopup(stage, button, nil, entries)
end

local function ToolbarButton(bar, index)
	local button = bar.controls[index]
	if button then
		return button
	end
	button = Style:CreateButton(bar, '', nil, OnToolbarClick)
	button:SetHeight(20)
	button.stage = bar.stage
	if button.SetMotionScriptsWhileDisabled then
		-- A grayed-out control still says why on hover
		button:SetMotionScriptsWhileDisabled(true)
	end
	local arrow = button:CreateTexture(nil, 'OVERLAY')
	arrow:SetSize(8, 8)
	arrow:SetPoint('RIGHT', button, 'RIGHT', -6, 0)
	local Kit = LibAT and LibAT.UI and LibAT.UI.Kit
	button.hasArrow = Kit and Kit.SetAsset and Kit.GetActive and Kit:SetAsset(arrow, Kit:GetActive(), 'triangle') and true or false
	if button.hasArrow and arrow.SetRotation then
		-- The triangle points right; a drop-down points down
		arrow:SetRotation(math.rad(-90))
	end
	button.arrow = arrow
	bar.controls[index] = button
	return button
end

---Lay out the provider's toolbar controls, or hide the strip when there are none
---@param stage table
---@param items SUI.OptionsWindow.StageToolbarItem[]|nil
---@return boolean shown
local function LayoutToolbar(stage, items)
	local bar = stage.toolbar
	items = type(items) == 'table' and items or {}
	local count = #items
	local left, right = 8, 8
	for i = 1, count do
		local item = items[i]
		local button = ToolbarButton(bar, i)
		button.item = item
		local isSelect = item.kind == 'select'
		if isSelect then
			button:SetText((item.label and (item.label .. ': ') or '') .. ChoiceText(item))
			if button.hasArrow then
				button:SetWidth(button:GetWidth() + 12)
			end
		else
			button:SetText(item.text or '')
		end
		button.arrow:SetShown(isSelect and button.hasArrow)
		button:SetActive(item.kind == 'toggle' and item.active)
		local tip = item.disabled and (item.disabledReason or item.tooltip) or item.tooltip
		button:SetTooltip(tip, tip and button.label:GetText() or nil)
		if item.disabled then
			button:Disable()
		else
			button:Enable()
		end
		button:ClearAllPoints()
		if item.align == 'right' then
			button:SetPoint('RIGHT', bar, 'RIGHT', -right, 0)
			right = right + button:GetWidth() + 6
		else
			button:SetPoint('LEFT', bar, 'LEFT', left, 0)
			left = left + button:GetWidth() + 6
		end
		button:Show()
	end
	for i = count + 1, #bar.controls do
		bar.controls[i].item = nil
		bar.controls[i]:Hide()
	end
	local shown = count > 0
	if shown ~= stage.toolbarShown then
		stage.toolbarShown = shown
		bar:SetShown(shown)
		stage.canvas:ClearAllPoints()
		stage.canvas:SetPoint('TOPLEFT', shown and bar or stage.header, 'BOTTOMLEFT', 1, -1)
		stage.canvas:SetPoint('BOTTOMRIGHT', -1, 1)
	end
	return shown
end

----------------------------------------------------------------------------------------------------
-- Stage chrome
----------------------------------------------------------------------------------------------------

---Some providers size the panel to the room beside the window; that room changes when it moves
local function RoomMayHaveChanged()
	if current and current.width ~= nil then
		Stage:MarkDirty()
	end
end

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

	local toolbar = CreateFrame('Frame', nil, stage)
	toolbar:SetPoint('TOPLEFT', header, 'BOTTOMLEFT', 0, 0)
	toolbar:SetPoint('TOPRIGHT', header, 'BOTTOMRIGHT', 0, 0)
	toolbar:SetHeight(TOOLBAR)
	Style:CreateFill(toolbar, Style.color.raised)
	toolbar.controls = {}
	toolbar.stage = stage
	toolbar:Hide()
	stage.toolbar = toolbar
	stage.toolbarShown = false

	local canvas = CreateFrame('Frame', nil, stage)
	canvas:SetPoint('TOPLEFT', header, 'BOTTOMLEFT', 1, -1)
	canvas:SetPoint('BOTTOMRIGHT', -1, 1)
	if canvas.SetClipsChildren then
		canvas:SetClipsChildren(true)
	end
	stage.canvas = canvas
	stage.renderedWidth, stage.renderedHeight = 0, 0

	-- Previews draw on this layer, so zooming and dragging never need a redraw
	local layer = CreateFrame('Frame', nil, canvas)
	layer:SetPoint('CENTER')
	layer:SetSize(1, 1)
	stage.view = layer
	canvas:SetScript('OnSizeChanged', function(_, width, height)
		ApplyView(stage)
		-- Providers that fit their drawing to the canvas ask for a new drawing at a new size
		if current and current.refit and (math.abs((width or 0) - stage.renderedWidth) >= 0.5 or math.abs((height or 0) - stage.renderedHeight) >= 0.5) then
			Stage:MarkDirty()
		end
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
	window.frame:HookScript('OnSizeChanged', RoomMayHaveChanged)
	if type(window.PlaceStage) == 'function' then
		hooksecurefunc(window, 'PlaceStage', RoomMayHaveChanged)
	end
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

---@param target SUI.OptionsWindow.StageTarget
---@return string|nil
local function DetailText(target)
	local detail = target.detail
	if type(detail) == 'function' then
		detail = detail(target)
	end
	if type(detail) == 'string' and detail ~= '' then
		return detail
	end
	return nil
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
	local detail = DetailText(target)
	if detail then
		GameTooltip:AddLine(detail, 0.9, 0.9, 0.9, true)
	end
	if not target.drag then
		GameTooltip:AddLine(L['Click to change these settings'], nil, nil, nil, true)
	elseif picked.selected then
		GameTooltip:AddLine(L['Drag to move it, or nudge with the arrow keys'], nil, nil, nil, true)
	else
		GameTooltip:AddLine(L['Click to select it'], nil, nil, nil, true)
	end
	if target.onShiftClick then
		GameTooltip:AddLine(L['Shift+click to hide it from the preview'], nil, nil, nil, true)
	end
	if #hover.stack > 1 then
		GameTooltip:AddLine(string.format(L['Press Alt for the part underneath (%d of %d)'], hover.depth, #hover.stack), 0.55, 0.8, 1, true)
		if current and current.overlapPicker then
			GameTooltip:AddLine(L['Right-click to list every part here'], 0.55, 0.8, 1, true)
		end
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

---What a click on a part does: Shift hides it, then the provider's own click, then its page
---@param region Button
local function Activate(region)
	local target = region.target
	if IsShiftKeyDown() and target.onShiftClick then
		GameTooltip:Hide()
		target.onShiftClick()
		Stage:MarkDirty()
		return
	end
	if target.onClick then
		local handled = target.onClick(target)
		Stage:MarkDirty()
		if handled then
			return
		end
	end
	if target.path then
		local ACD = LibStub('AceConfigDialog-3.0-LibAT')
		ACD:Navigate(APP, target.path, target.option)
	end
end

---List every named part under the cursor; hovering an entry outlines that part, clicking picks it
local function OpenPicker()
	local window = GetWindow()
	if not window then
		return
	end
	local stack = RegionsUnderCursor()
	local function Outline(chosen)
		for _, other in ipairs(stack) do
			if other:IsShown() then
				PaintBorder(other, other == chosen)
			end
		end
	end
	local items = {}
	for _, region in ipairs(stack) do
		local target = region.target
		if target.label then
			items[#items + 1] = {
				text = target.label,
				active = region.selected,
				onEnter = function()
					Outline(region)
				end,
				onLeave = function()
					Outline(nil)
				end,
				onClick = function()
					Activate(region)
				end,
			}
		end
	end
	if #items == 0 then
		return
	end
	ClearHover()
	GameTooltip:Hide()
	ShowPopup(window.stage, nil, L['Parts here'], items, function()
		Outline(nil)
	end)
end

---Clickable area over part of the preview
---@param frame Frame|Texture
---@param target SUI.OptionsWindow.StageTarget
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
			-- Only a part that is already selected moves; dragging anything else moves the view
			local picked = Picked(self)
			if picked.target.drag and picked.selected then
				ClearHover()
				StartPartDrag(picked)
			else
				StartPan(window.stage)
			end
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
		region:SetScript('OnClick', function(self, button)
			if button == 'RightButton' then
				if current and current.overlapPicker then
					OpenPicker()
				end
				return
			end
			if self.dragged then
				self.dragged = nil
				return
			end
			Activate(Picked(self))
		end)
		regions[usedRegions] = region
	end
	region.target = target
	region.part = frame
	region:ClearAllPoints()
	region:SetAllPoints(frame)
	if current and current.overlapPicker then
		region:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
	else
		region:RegisterForClicks('LeftButtonUp')
	end
	-- Later regions sit above earlier ones, so register large parts first and small parts last
	region:SetFrameStrata(window.stage.canvas:GetFrameStrata())
	region:SetFrameLevel(window.stage.canvas:GetFrameLevel() + 150 + usedRegions)
	if target.selected ~= nil then
		region.selected = target.selected and true or false
	else
		region.selected = SamePath(target.path or {}, currentPath)
	end
	if region.selected then
		local r, g, b = Style:GetAccent()
		region.border:SetColor(r, g, b, 0.9)
		if target.drag then
			nudge.target = target
		end
	end
	region.border:SetShown(region.selected)
	region:Show()
end

----------------------------------------------------------------------------------------------------
-- Arrow keys
----------------------------------------------------------------------------------------------------

-- SetPropagateKeyboardInput is restricted in combat and EnableKeyboard is protected, so the key
-- frame is made and shown only out of combat, only while a movable part is selected and the
-- cursor is over the panel, and every key it does not use goes on to the game.
local keyWatcher

---@param key string
---@return boolean handled
local function HandleKey(key)
	local target = nudge.target
	local drag = target and target.drag
	if not drag then
		return false
	end
	local arrow = ARROWS[key]
	if arrow then
		local step = IsShiftKeyDown() and NUDGE_STEP_BIG or NUDGE_STEP
		local dx, dy = arrow[1] * step, arrow[2] * step
		if drag.Nudge then
			drag.Nudge(dx, dy, target)
		else
			if drag.Start then
				drag.Start(target)
			end
			if drag.Move then
				drag.Move(dx, dy, target)
			end
			if drag.Stop then
				drag.Stop(dx, dy, target)
			end
		end
		Stage:MarkDirty()
		return true
	end
	if not drag.Key or key:find('SHIFT$') or key:find('CTRL$') or key:find('ALT$') or key:find('META$') then
		return false
	end
	local name = key
	if IsShiftKeyDown() then
		name = 'SHIFT-' .. name
	end
	if IsControlKeyDown() then
		name = 'CTRL-' .. name
	end
	if IsAltKeyDown() then
		name = 'ALT-' .. name
	end
	if drag.Key(name, target) then
		Stage:MarkDirty()
		return true
	end
	return false
end

local function OnKeyDown(self, key)
	if InCombatLockdown() then
		return
	end
	-- A provider error must not leave the game's keys swallowed
	local ok, handled = pcall(HandleKey, key)
	self:SetPropagateKeyboardInput(not (ok and handled))
	if not ok then
		geterrorhandler()(handled)
	end
end

-- Key releases always reach the game: a movement key let go over the panel must stop the move
local function OnKeyUp(self)
	if not InCombatLockdown() then
		self:SetPropagateKeyboardInput(true)
	end
end

---@param on boolean
local function SetKeyCapture(on)
	if on then
		if InCombatLockdown() then
			return
		end
		if not keyWatcher then
			keyWatcher = CreateFrame('Frame', nil, UIParent)
			keyWatcher:SetFrameStrata('TOOLTIP')
			keyWatcher:EnableKeyboard(true)
			keyWatcher:SetScript('OnKeyDown', OnKeyDown)
			keyWatcher:SetScript('OnKeyUp', OnKeyUp)
			keyWatcher:Hide()
		end
		if not keyWatcher:IsShown() then
			keyWatcher:SetPropagateKeyboardInput(true)
			keyWatcher:Show()
		end
	elseif keyWatcher and keyWatcher:IsShown() then
		if not InCombatLockdown() then
			keyWatcher:SetPropagateKeyboardInput(true)
		end
		keyWatcher:Hide()
	end
end

-- Turns key capture on and off as the cursor enters and leaves the panel
local keyGate = CreateFrame('Frame')
keyGate:Hide()
keyGate.elapsed = 0
keyGate:SetScript('OnUpdate', function(self, elapsed)
	self.elapsed = self.elapsed + elapsed
	if self.elapsed < 0.05 then
		return
	end
	self.elapsed = 0
	local window = GetWindow()
	local stage = window and window.stage
	local wanted = nudge.target ~= nil and stage ~= nil and stage:IsVisible() and stage:IsMouseOver() and not partDrag:IsShown() and not InCombatLockdown()
	SetKeyCapture(wanted and true or false)
end)
keyGate:SetScript('OnHide', function()
	SetKeyCapture(false)
end)
-- Combat lockdown starts just after this event, so the key frame can still let go of keys here
keyGate:RegisterEvent('PLAYER_REGEN_DISABLED')
keyGate:SetScript('OnEvent', function()
	if keyWatcher then
		keyWatcher:Hide()
		if not InCombatLockdown() then
			keyWatcher:SetPropagateKeyboardInput(true)
		end
	end
end)

local function UpdateKeyGate()
	if nudge.target then
		keyGate:Show()
	else
		keyGate:Hide()
	end
end

----------------------------------------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------------------------------------

function Stage:HideProvider()
	FinishPartDrag()
	ClosePopup()
	nudge.target = nil
	UpdateKeyGate()
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

	---@type SUI.OptionsWindow.StageContext
	local ctx = { path = currentPath, canvas = stage.view, Region = Region, width = math.max(0, window.stageWidth or 0), maxWidth = RoomBeside(window) }
	local wanted = provider and (provider:GetHeight(ctx) or 0) > 0
	if not provider or not wanted then
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
	if provider.width == nil then
		if resize or window.stageWidth <= 0 then
			window:SetStageWidth(PANEL_WIDTH)
		end
	else
		local width = WantedWidth(provider, ctx)
		if resize or window.stageWidth ~= width then
			window:SetStageWidth(width)
		end
	end
	ctx.width = window.stageWidth

	ClosePopup()
	ClearHover()
	for i = 1, #regions do
		regions[i]:Hide()
	end
	usedRegions = 0
	nudge.target = nil
	LayoutToolbar(stage, provider.Toolbar and provider:Toolbar(ctx) or nil)
	stage.renderedWidth, stage.renderedHeight = stage.canvas:GetSize()
	ApplyView(stage)
	stage.title:SetText(provider.Title and provider:Title(ctx) or L['Preview'])
	local hint = provider.Hint and provider:Hint(ctx)
	if not hint then
		hint = provider.zoomable and L['Click a part to change it. Scroll to zoom, drag to move.'] or L['Click a part to jump to its settings']
	end
	stage.hint:SetText(hint)
	provider:Render(ctx)
	UpdateKeyGate()

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
