--------------------------------------------------------------------------------
---- Library Namespace
--------------------------------------------------------------------------------

local QTip = LibStub:GetLibrary('LibQTip-2.0')

local ScriptManager = QTip.ScriptManager
local TooltipManager = QTip.TooltipManager

---@class LibQTip-2.0.Tooltip: BackdropTemplate, Frame
---@field AutoHideTimerFrame? LibQTip-2.0.Timer Allocated when :SetAutoHideDelay is used.
---@field ColSpanWidths table<string, number|nil> Widths of ColSpans, keyed by index range.
---@field Columns (LibQTip-2.0.Column|nil)[] Columns allocated to the Tooltip.
---@field DefaultCellProvider LibQTip-2.0.CellProvider The default CellProvider to use for Cells allocated to the Tooltip.
---@field DefaultFont Font The default font used for Rows.
---@field DefaultHeadingFont Font The default font used for heading Rows.
---@field Height number Height, in pixels.
---@field HighlightFrame Frame The Frame for the HighlightTexture. Used for mouse-enabled Scripts.
---@field HighlightTexture Texture The texture used for Frames with mouse-enabled Scripts set on them.
---@field HorizontalCellMargin number Horizontal Cell margin, in pixels.
---@field Key string The key used to acquire the Tooltip.
---@field MaxHeight? number The maximum Tooltip height, in pixels. Contents larger than this value will be scrollable.
---@field Rows (LibQTip-2.0.Row|nil)[] Rows allocated to the Tooltip.
---@field Scripts? table<LibQTip-2.0.ScriptType, true|nil> Currently-set Scripts on the Tooltip.
---@field ScrollChild Frame
---@field ScrollFrame ScrollFrame
---@field ScrollStep number
---@field Slider LibQTip-2.0.Slider The Slider used to control scrolling within the Tooltip.
---@field VerticalCellMargin number Vertical Cell margin, in pixels.
---@field Width number Width, in pixels.
local Tooltip = TooltipManager.TooltipPrototype

---@class LibQTip-2.0.Slider: BackdropTemplate, Slider
---@field ScrollFrame ScrollFrame

---@class LibQTip-2.0.Timer: LibQTip-2.0.ScriptFrame
---@field AlternateFrame? Frame
---@field CheckElapsed number
---@field Delay number
---@field Elapsed number
---@field Tooltip LibQTip-2.0.Tooltip

--------------------------------------------------------------------------------
---- Constants
--------------------------------------------------------------------------------

---@type backdropInfo
local SliderBackdrop = BACKDROP_SLIDER_8_8
	or {
		bgFile = 'Interface\\Buttons\\UI-SliderBar-Background',
		edgeFile = 'Interface\\Buttons\\UI-SliderBar-Border',
		edgeSize = 8,
		insets = { left = 3, right = 3, top = 6, bottom = 6 },
		tile = true,
		tileEdge = true,
		tileSize = 8,
	}

--------------------------------------------------------------------------------
---- Validators
--------------------------------------------------------------------------------

local function ValidateFont(font, level, silent)
	local bad = false

	if not font then
		bad = true
	elseif type(font) == 'string' then
		local ref = _G[font]

		if not ref or type(ref) ~= 'table' or type(ref.IsObjectType) ~= 'function' or not ref:IsObjectType('Font') then
			bad = true
		end
	elseif type(font) ~= 'table' or type(font.IsObjectType) ~= 'function' or not font:IsObjectType('Font') then
		bad = true
	end

	if bad then
		if silent then
			return false
		end

		error(('Font must be a FontInstance or a string matching the name of a global FontInstance, not: %s'):format(tostring(font)), level + 1)
	end

	return true
end

---@param justification JustifyHorizontal
---@param level integer
---@param silent? boolean
local function ValidateJustification(justification, level, silent)
	if justification ~= 'LEFT' and justification ~= 'CENTER' and justification ~= 'RIGHT' then
		if silent then
			return false
		end

		error('invalid justification, must one of LEFT, CENTER or RIGHT, not: ' .. tostring(justification), level + 1)
	end

	return true
end

---@param tooltip LibQTip-2.0.Tooltip
---@param rowIndex integer
---@param level integer
---@return boolean isValid
local function ValidateRowIndex(tooltip, rowIndex, level)
	local callerLevel = level + 1
	local rowIndexType = type(rowIndex)

	if rowIndexType ~= 'number' then
		error(("The rowIndex must be a number, not '%s'"):format(rowIndexType), callerLevel)
	end

	return true
end

--------------------------------------------------------------------------------
---- Internal Functions
--------------------------------------------------------------------------------

---@param tooltip LibQTip-2.0.Tooltip The Tooltip we're adding the Row to.
---@param isHeading boolean Whether or not this Row is a Heading.
---@param ... string Value to be displayed in each Column of the Row.
---@return LibQTip-2.0.Row row
local function BaseAddRow(tooltip, isHeading, ...)
	if #tooltip.Columns == 0 then
		error('Column layout should be defined before adding a Row', 3)
	end

	local rowIndex = #tooltip.Rows + 1
	local row = tooltip.Rows[rowIndex] or TooltipManager:AcquireRow(tooltip, rowIndex)

	tooltip.Rows[rowIndex] = row

	row.IsHeading = isHeading

	for columnIndex = 1, #tooltip.Columns do
		local value = select(columnIndex, ...)

		if value ~= nil then
			row:GetCell(columnIndex):SetText(value)
		end
	end

	return row
end

---@param frame Frame The Frame that will serve as the Tooltip anchor.
local function GetTooltipAnchor(frame)
	local x, y = frame:GetCenter()

	if not x or not y then
		return 'TOPLEFT', 'BOTTOMLEFT'
	end

	local horizontalHalf = (x > UIParent:GetWidth() * 2 / 3) and 'RIGHT' or (x < UIParent:GetWidth() / 3) and 'LEFT' or ''

	local verticalHalf = (y > UIParent:GetHeight() / 2) and 'TOP' or 'BOTTOM'

	return verticalHalf .. horizontalHalf, frame, (verticalHalf == 'TOP' and 'BOTTOM' or 'TOP') .. horizontalHalf
end

--------------------------------------------------------------------------------
---- Scripts
--------------------------------------------------------------------------------

-- Script of the auto-hiding child frame
---@param timer LibQTip-2.0.Timer
---@param elapsed number
local function AutoHideTimerFrame_OnUpdate(timer, elapsed)
	timer.CheckElapsed = timer.CheckElapsed + elapsed

	if timer.CheckElapsed > 0.1 then
		if timer.Tooltip:IsMouseOver() or (timer.AlternateFrame and timer.AlternateFrame:IsMouseOver()) then
			timer.Elapsed = 0
		else
			timer.Elapsed = timer.Elapsed + timer.CheckElapsed

			if timer.Elapsed >= timer.Delay then
				QTip:ReleaseTooltip(timer.Tooltip)
			end
		end

		timer.CheckElapsed = 0
	end
end

---@param slider LibQTip-2.0.Slider
local function Slider_OnValueChanged(slider)
	slider.ScrollFrame:SetVerticalScroll(slider:GetValue())
end

---@param self LibQTip-2.0.Tooltip
---@param delta number
local function Tooltip_OnMouseWheel(self, delta)
	local slider = self.Slider
	local currentValue = slider:GetValue()
	local minValue, maxValue = slider:GetMinMaxValues()
	local stepValue = self.ScrollStep

	if delta < 0 and currentValue < maxValue then
		slider:SetValue(min(maxValue, currentValue + stepValue))
	elseif delta > 0 and currentValue > minValue then
		slider:SetValue(max(minValue, currentValue - stepValue))
	end
end

--------------------------------------------------------------------------------
---- Methods
--------------------------------------------------------------------------------

-- Add a new Column to the right of the Tooltip.
---@param horizontalJustification? JustifyHorizontal The horizontal justification of Cells in this Column ("CENTER", "LEFT" or "RIGHT"). Defaults to "LEFT".
---@return LibQTip-2.0.Column
function Tooltip:AddColumn(horizontalJustification)
	horizontalJustification = horizontalJustification or 'LEFT'
	ValidateJustification(horizontalJustification, 2)

	local columnIndex = #self.Columns + 1
	local column = self.Columns[columnIndex] or TooltipManager:AcquireColumn(self, columnIndex, horizontalJustification)

	self.Columns[columnIndex] = column

	return column
end

-- Add a new heading Row at the bottom of the Tooltip.
--
-- Provided values are displayed on the Row using the DefaultHeadingFont. Nil values are ignored.
--
-- If the number of values is greater than the number of Columns, an error is raised.
---@param ... string Value to be displayed in each Column of the Row.
---@return LibQTip-2.0.Row row
function Tooltip:AddHeadingRow(...)
	local row = BaseAddRow(self, true, ...)

	return row
end

-- Add a new Row at the bottom of the Tooltip.
--
-- Provided values are displayed on the Row with the regular Font. Nil values are ignored.
--
-- If the number of values is greater than the number of Columns, an error is raised.
---@param ... string Value to be displayed in each Column of the Row.
---@return LibQTip-2.0.Row row
function Tooltip:AddRow(...)
	return BaseAddRow(self, false, ...)
end

-- Adds a graphical separator Row at the bottom of the Tooltip.
---@param height? number Height, in pixels, of the separator. Defaults to 1.
---@param r? number Red color value of the separator. Defaults to NORMAL_FONT_COLOR.r
---@param g? number Green color value of the separator. Defaults to NORMAL_FONT_COLOR.g
---@param b? number Blue color value of the separator. Defaults to NORMAL_FONT_COLOR.b
---@param a? number Alpha level of the separator. Defaults to 1.
---@return LibQTip-2.0.Row row
function Tooltip:AddSeparator(height, r, g, b, a)
	local row = self:AddRow()
	local color = NORMAL_FONT_COLOR

	height = height or 1

	TooltipManager:SetTooltipSize(self, self.Width, self.Height + height)

	row.Height = height
	row:SetHeight(height)
	row:SetBackdrop(TooltipManager.DefaultBackdrop)
	row:SetBackdropColor(r or color.r, g or color.g, b or color.b, a or 1)

	return row
end

-- Reset the contents of the Tootip. The Column layout is preserved but all Rows are removed.
---@return LibQTip-2.0.Tooltip
function Tooltip:Clear()
	for _, row in pairs(self.Rows) do
		TooltipManager:ReleaseRow(row)
	end

	wipe(self.Rows)

	for _, column in ipairs(self.Columns) do
		column.Width = 0
		column:SetWidth(1)

		wipe(column.Cells)
	end

	wipe(self.ColSpanWidths)

	self.HorizontalCellMargin = nil
	self.VerticalCellMargin = nil

	TooltipManager:AdjustTooltipSize(self)

	return self
end

-- Returns the Column at the given index.
---@param columnIndex integer
---@return LibQTip-2.0.Column
---@nodiscard
function Tooltip:GetColumn(columnIndex)
	ValidateRowIndex(self, columnIndex, 2)

	local column = self.Columns[columnIndex]

	if not column then
		error(('There is no column at index %d'):format(columnIndex), 2)
	end

	return column
end

-- Returns the total number of Columns on the Tooltip.
---@return number columnCount
function Tooltip:GetColumnCount()
	return #self.Columns
end

-- Returns the CellProvider used for Cell functionality.
---@return LibQTip-2.0.CellProvider
---@nodiscard
function Tooltip:GetDefaultCellProvider()
	return self.DefaultCellProvider
end

-- Return the Font used for regular Rows.
---@return Font
---@nodiscard
function Tooltip:GetDefaultFont()
	return self.DefaultFont
end

-- Return the Tooltip's DefaultHeadingFont used for heading Rows.
---@return Font
---@nodiscard
function Tooltip:GetDefaultHeadingFont()
	return self.DefaultHeadingFont
end

-- Works identically to the default UI's texture:GetTexCoord() API, for the Tooltip's highlight Texture.
---@return number ULx
---@return number ULy
---@return number LLx
---@return number LLy
---@return number URx
---@return number URy
---@return number LRx
---@return number LRy
function Tooltip:GetHighlightTexCoord()
	return self.HighlightTexture:GetTexCoord()
end

-- Returns the Tooltip's highlight Texture.
function Tooltip:GetHighlightTexture()
	return self.HighlightTexture:GetTexture()
end

-- Returns the Row at the given index.
---@param rowIndex integer
---@return LibQTip-2.0.Row
---@nodiscard
function Tooltip:GetRow(rowIndex)
	ValidateRowIndex(self, rowIndex, 2)

	local row = self.Rows[rowIndex]

	if not row then
		error(('There is no Row at index %d'):format(rowIndex), 2)
	end

	return row
end

-- Returns the total number of Rows on the Tooltip.
---@return number rowCount
---@nodiscard
function Tooltip:GetRowCount()
	return #self.Rows
end

-- Returns the step size for the Tooltip's scroll bar.
---@return number
function Tooltip:GetScrollStep()
	return self.ScrollStep
end

-- Disallow the use of the HookScript method to avoid one AddOn breaking all others.
function Tooltip:HookScript()
	geterrorhandler()(':HookScript is not allowed on LibQTip tooltips')
end

-- Determine whether or not the Tooltip has been acquired by the specified key.
---@param key string The key to check.
---@return boolean
---@nodiscard
function Tooltip:IsAcquiredBy(key)
	return key ~= nil and self.Key == key
end

-- Convenience wrapper on LibQTip to release the Tooltip.
function Tooltip:Release()
	QTip:ReleaseTooltip(self)
end

-- Sets the length of time in which the mouse pointer can be outside of the Tooltip, or an alternate Frame, before the Tooltip is automatically hidden and then released.
---@param delay? number Whole or fractional seconds.
---@param alternateFrame? Frame If specified, the Tooltip will not be automatically hidden while the mouse pointer is over it.
-- Usage:
--
-- :SetAutoHideDelay(0.25) => hides after 0.25sec outside of the tooltip
--
-- :SetAutoHideDelay(0.25, someFrame) => hides after 0.25sec outside of both the tooltip and someFrame
--
-- :SetAutoHideDelay() => disable auto-hiding (default)
---@return LibQTip-2.0.Tooltip
function Tooltip:SetAutoHideDelay(delay, alternateFrame)
	local timerFrame = self.AutoHideTimerFrame
	delay = tonumber(delay) or 0

	if delay > 0 then
		if not timerFrame then
			timerFrame = TooltipManager:AcquireTimer(self)
			timerFrame:SetScript('OnUpdate', AutoHideTimerFrame_OnUpdate)

			self.AutoHideTimerFrame = timerFrame
		end

		timerFrame.AlternateFrame = alternateFrame
		timerFrame.CheckElapsed = 0
		timerFrame.Delay = delay
		timerFrame.Elapsed = 0
		timerFrame.Tooltip = self

		timerFrame:Show()
	elseif timerFrame then
		self.AutoHideTimerFrame = nil

		TooltipManager:ReleaseTimer(timerFrame)
	end

	return self
end

-- Sets the horizontal margin size of all Cells within the Tooltip.
--
-- This method can only be used before Rows have been added.
---@param size integer The desired margin size. Must be a positive number or zero.
---@return LibQTip-2.0.Tooltip
function Tooltip:SetCellMarginH(size)
	if #self.Rows > 0 then
		error('Unable to set horizontal margin while the Tooltip has Rows.', 2)
	end

	if not size or type(size) ~= 'number' or size < 0 then
		error('Margin size must be a positive number or zero.', 2)
	end

	self.HorizontalCellMargin = size

	return self
end

-- Sets the vertical margin size of all Cells within the Tooltip.
--
-- This method can only be used before Rows have been added.
---@param size integer The desired margin size. Must be a positive number or zero.
---@return LibQTip-2.0.Tooltip
function Tooltip:SetCellMarginV(size)
	if #self.Rows > 0 then
		error('Unable to set vertical margin while the Tooltip has Rows.', 2)
	end

	if not size or type(size) ~= 'number' or size < 0 then
		error('Margin size must be a positive number or zero.', 2)
	end

	self.VerticalCellMargin = size

	return self
end

-- Ensure the Tooltip has at least the passed number of Columns.
--
-- The justification of existing Columns is reset to any passed values, or to "LEFT" if none are provided.
---@param columnCount number Minimum number of columns
---@param ...? JustifyHorizontal Column horizontal justifications ("CENTER", "LEFT" or "RIGHT"). Defaults to "LEFT".
-- ***
-- Example Tooltip with 5 columns justified as left, center, left, left, left:
-- ``` lua
-- tooltip:SetColumnLayout(5, "LEFT", "CENTER")
-- ```
-- ***
---@return LibQTip-2.0.Tooltip
function Tooltip:SetColumnLayout(columnCount, ...)
	if type(columnCount) ~= 'number' or columnCount < 1 then
		error(("columnCount must be a positive number, not '%s'"):format(tostring(columnCount)), 2)
	end

	for columnIndex = 1, columnCount do
		---@type JustifyHorizontal
		local horizontalJustification = select(columnIndex, ...) or 'LEFT'

		ValidateJustification(horizontalJustification, 2)

		if self.Columns[columnIndex] then
			self.Columns[columnIndex].HorizontalJustification = horizontalJustification
		else
			self:AddColumn(horizontalJustification)
		end
	end

	return self
end

-- Define the CellProvider to be used for all Cell functionality.
---@param cellProvider LibQTip-2.0.CellProvider The new default CellProvider.
---@return LibQTip-2.0.Tooltip
function Tooltip:SetDefaultCellProvider(cellProvider)
	if cellProvider then
		self.DefaultCellProvider = cellProvider
	end

	return self
end

-- Define the Font used when adding new Rows.
---@param font FontObject|Font The new default [Font](https://wowpedia.fandom.com/wiki/UIOBJECT_Font).
---@return LibQTip-2.0.Tooltip
function Tooltip:SetDefaultFont(font)
	ValidateFont(font, 2)

	self.DefaultFont = type(font) == 'string' and _G[font] or font --[[@as Font]]

	return self
end

-- Define the Font used when adding new heading Rows.
---@param font FontObject|Font The new default heading [Font](https://wowpedia.fandom.com/wiki/UIOBJECT_Font).
---@return LibQTip-2.0.Tooltip
function Tooltip:SetDefaultHeadingFont(font)
	ValidateFont(font, 2)

	self.DefaultHeadingFont = type(font) == 'string' and _G[font] or font --[[@as Font]]

	return self
end

-- Works identically to the default UI's texture:SetTexCoord() API, for the Tooltip's highlight Texture.
---@param ... number Arguments to pass to texture:SetTexCoord()
---@overload fun(ULx: number, ULy: number, LLx: number, LLy: number, URx: number, URy: number, LRx: number, LRy: number)
---@overload fun(minX: number, maxX: number, minY: number, maxY: number)
---@return LibQTip-2.0.Tooltip
function Tooltip:SetHighlightTexCoord(...)
	self.HighlightTexture:SetTexCoord(...)

	return self
end

-- Sets the Texture of the highlight when mousing over a Row or Cell that has a script assigned to it.
--
-- Works identically to the default UI's texture:SetTexture() API.
---@param filePath string|number Path to a texture (usually in Interface\\) or a FileDataID.
---@param horizontalWrap? WrapMode How to sample texture coordinates beyond the (0, 1) range horizontally.
---@param verticalWrap? string How to sample texture coordinates beyond the (0, 1) range vertically.
---@param filterMode? FilterMode
---@return LibQTip-2.0.Tooltip
function Tooltip:SetHighlightTexture(filePath, horizontalWrap, verticalWrap, filterMode)
	self.HighlightTexture:SetTexture(filePath, horizontalWrap, verticalWrap, filterMode)

	return self
end

-- Sets the maximum Tooltip height, in pixels.
---@param height number The maximum height to set.
---@return LibQTip-2.0.Tooltip
function Tooltip:SetMaxHeight(height)
	self.MaxHeight = height

	return self
end

-- Assigns a script to the Tooltip.
---@param scriptType LibQTip-2.0.ScriptType|"OnMouseWheel"
---@param handler? fun(arg, ...)
---@return LibQTip-2.0.Tooltip
function Tooltip:SetScript(scriptType, handler)
	ScriptManager:RawSetScript(self, scriptType, handler)

	self.Scripts[scriptType] = handler and true or nil

	return self
end

-- Set the step size for the scroll bar.
---@param step number The new step size.
---@return LibQTip-2.0.Tooltip
function Tooltip:SetScrollStep(step)
	self.ScrollStep = step

	return self
end

-- Anchor the Tooltip to the given Frame, ensuring that it is always on screen.
---@param frame Frame The Frame that will serve as the Tooltip anchor.
---@return LibQTip-2.0.Tooltip
function Tooltip:SmartAnchorTo(frame)
	if not frame then
		error('Invalid frame provided.', 2)
	end

	self:ClearAllPoints()
	self:SetClampedToScreen(true)
	self:SetPoint(GetTooltipAnchor(frame))

	return self
end

-- Resizes the Tooltip to fit the screen and show a scrollbar if needed.
---@return LibQTip-2.0.Tooltip
function Tooltip:UpdateLayout()
	self:SetClampedToScreen(false)

	-- All data is in the Tooltip; fix ColSpan width and prevent the TooltipManager from messing up the Tooltip later.
	TooltipManager:AdjustCellSizes(self)
	TooltipManager.LayoutRegistry[self] = nil

	local scale = self:GetScale()
	local topOffset = self:GetTop()
	local bottomOffset = self:GetBottom()
	local screenSize = UIParent:GetHeight() / scale
	local tooltipSize = (topOffset - bottomOffset)
	local maxHeight = self.MaxHeight

	-- If the Tooltip would be too high, limit its height and show the slider.
	if bottomOffset < 0 or topOffset > screenSize or (maxHeight and tooltipSize > maxHeight) then
		local shrink = (bottomOffset < 0 and (5 - bottomOffset) or 0) + (topOffset > screenSize and (topOffset - screenSize + 5) or 0)

		if maxHeight and tooltipSize - shrink > maxHeight then
			shrink = tooltipSize - maxHeight
		end

		self:SetHeight(2 * TooltipManager.PixelSize.CellPadding + self.Height - shrink)
		self:SetWidth(2 * TooltipManager.PixelSize.CellPadding + self.Width + 20)

		self.ScrollFrame:SetPoint('RIGHT', self, 'RIGHT', -(TooltipManager.PixelSize.CellPadding + 20), 0)

		if not self.Slider then
			local slider = CreateFrame('Slider', nil, self, 'BackdropTemplate') --[[@as LibQTip-2.0.Slider]]
			slider.ScrollFrame = self.ScrollFrame

			slider:SetOrientation('VERTICAL')
			slider:SetPoint('TOPRIGHT', self, 'TOPRIGHT', -TooltipManager.PixelSize.CellPadding, -TooltipManager.PixelSize.CellPadding)
			slider:SetPoint('BOTTOMRIGHT', self, 'BOTTOMRIGHT', -TooltipManager.PixelSize.CellPadding, TooltipManager.PixelSize.CellPadding)
			slider:SetBackdrop(SliderBackdrop)
			slider:SetThumbTexture([[Interface\Buttons\UI-SliderBar-Button-Vertical]])
			slider:SetMinMaxValues(0, 1)
			slider:SetValueStep(1)
			slider:SetWidth(12)
			slider:SetScript('OnValueChanged', Slider_OnValueChanged)
			slider:SetValue(0)

			self.Slider = slider
		end

		self.Slider:SetMinMaxValues(0, shrink)
		self.Slider:Show()

		self:EnableMouseWheel(true)
		self:SetScript('OnMouseWheel', Tooltip_OnMouseWheel)
	else
		self:SetHeight(2 * TooltipManager.PixelSize.CellPadding + self.Height)
		self:SetWidth(2 * TooltipManager.PixelSize.CellPadding + self.Width)

		self.ScrollFrame:SetPoint('RIGHT', self, 'RIGHT', -TooltipManager.PixelSize.CellPadding, 0)

		if self.Slider then
			self.Slider:SetValue(0)
			self.Slider:Hide()

			self:EnableMouseWheel(false)
			self:SetScript('OnMouseWheel', nil)
		end
	end

	return self
end
