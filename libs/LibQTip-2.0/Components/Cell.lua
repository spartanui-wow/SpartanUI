--------------------------------------------------------------------------------
---- Library Namespace
--------------------------------------------------------------------------------

local QTip = LibStub:GetLibrary('LibQTip-2.0')

local ScriptManager = QTip.ScriptManager
local TooltipManager = QTip.TooltipManager

---@class LibQTip-2.0.Cell: LibQTip-2.0.ScriptFrame, ColorMixin
---@field CellProvider LibQTip-2.0.CellProvider The CellProvider responsible for Cells of this type.
---@field ColSpan integer The number of columns the cell will span. Defaults to 1.
---@field ColumnIndex integer The Column index of Cell.
---@field FontString FontString The FontString used to set and display textual values on the Cell.
---@field HorizontalJustification JustifyHorizontal Cell-specific justification to use ("CENTER", "LEFT" or "RIGHT"). Defaults to the justification of the Column where the Cell resides.
---@field LeftPadding integer Pixel padding on the left side of the Cell's value. Defaults to 0.
---@field MaxWidth? integer The maximum width (in pixels) of the Cell. If the Cell's value is textual and exceeds this width, it will wrap to a new line. Must not be less than the value of MinWidth.
---@field MinWidth? integer The minimum width (in pixels) of the Cell. Must not exceed the value of MaxWidth.
---@field RightPadding integer Pixel padding on the right side of the Cell's value. Defaults to 0.
---@field RowIndex integer The Row index of Cell.
---@field Tooltip LibQTip-2.0.Tooltip The Tooltip this Cell belongs to.
local Cell = QTip.DefaultCellPrototype

--------------------------------------------------------------------------------
---- Methods
--------------------------------------------------------------------------------

-- Returns the RGBA numbers for the Cell.
---@return number red Red color, from 0 to 1
---@return number green Green color, from 0 to 1
---@return number blue Blue color, from 0 to 1
---@return number alpha Alpha level, from 0 to 1
function Cell:GetColor()
	return self:GetBackdropColor()
end

-- Returns the ColSpan value of the Cell.
function Cell:GetColSpan()
	return self.ColSpan
end

-- Returns the height of the Cell's FontString.
---@return number height
function Cell:GetContentHeight()
	local fontString = self.FontString
	fontString:SetWidth(self:GetWidth() - (self.LeftPadding + self.RightPadding))

	local height = self.FontString:GetHeight()
	fontString:SetWidth(0)

	return height
end

-- Returns the Cell's font path, height, and flags.
function Cell:GetFont()
	return self.FontString:GetFont()
end

-- Returns the FontObject assigned to the Cell.
function Cell:GetFontObject()
	return self.FontString:GetFontObject()
end

function Cell:GetJustifyH()
	return self.HorizontalJustification
end

-- Returns the left pixel padding of the Cell.
function Cell:GetLeftPadding()
	return self.LeftPadding
end

-- Returns the maximum width of the Cell.
---@return integer|nil
function Cell:GetMaxWidth()
	return self.MaxWidth
end

-- Returns the minimum width of the Cell.
---@return integer|nil
function Cell:GetMinWidth()
	return self.MinWidth
end

-- Returns the Cell's position within the containing Tooltip.
---@return number rowIndex The Row index of Cell.
---@return number columnIndex The Column index of Cell.
function Cell:GetPosition()
	return self.RowIndex, self.ColumnIndex
end

-- Returns the right pixel padding of the Cell.
---@return integer
function Cell:GetRightPadding()
	return self.RightPadding
end

-- Returns the size of the Cell.
---@return number width The width of the Cell.
---@return number height The height of the Cell.
function Cell:GetSize()
	local fontString = self.FontString

	-- Detach the FontString from the Cell to calculate size
	fontString:ClearAllPoints()

	local leftPadding = self.LeftPadding
	local rightPadding = self.RightPadding

	---@type number
	local width = fontString:GetStringWidth() + leftPadding + rightPadding
	local minWidth = self.MinWidth
	local maxWidth = self.MaxWidth

	if minWidth and width < minWidth then
		width = minWidth
	end

	if maxWidth and maxWidth < width then
		width = maxWidth
	end

	fontString:SetWidth(width - (leftPadding + rightPadding))

	-- Use GetHeight() instead of GetStringHeight() so lines which are longer than width will wrap.
	local height = fontString:GetHeight()

	fontString:SetWidth(0)
	fontString:SetPoint('TOPLEFT', self, 'TOPLEFT', leftPadding, 0)
	fontString:SetPoint('BOTTOMRIGHT', self, 'BOTTOMRIGHT', -rightPadding, 0)

	return width, height
end

-- Returns the text of the Cell.
---@return string?
function Cell:GetText()
	return self.FontString:GetText()
end

-- Returns the text color of the Cell.
---@return number r Red color value of the Cell's text.
---@return number g Green color value of the Cell's text.
---@return number b Blue color value of the Cell's text.
---@return number a Alpha level of the Cell's text.
function Cell:GetTextColor()
	return self.FontString:GetTextColor()
end

-- This method is called on newly created Cells for initialization.
function Cell:OnCreation()
	self.ColSpan = 1
	self.LeftPadding = 0
	self.RightPadding = 0
	self.FontString = self:CreateFontString()
	self.FontString:SetFontObject(GameTooltipText)
	self:SetJustifyH('LEFT')
end

-- Invoked when the Cell's content changes.
function Cell:OnContentChanged()
	local tooltip = self.Tooltip
	local row = tooltip:GetRow(self.RowIndex)
	local columnIndex = self.ColumnIndex
	local column = tooltip:GetColumn(columnIndex)
	local width, height = self:GetSize()
	local colSpan = self.ColSpan

	if colSpan > 1 then
		local columnRange = ('%d-%d'):format(columnIndex, columnIndex + colSpan - 1)

		tooltip.ColSpanWidths[columnRange] = max(tooltip.ColSpanWidths[columnRange] or 0, width)
		TooltipManager:RegisterForCleanup(tooltip)
	else
		TooltipManager:AdjustColumnWidth(column, width)
	end

	if height > row.Height then
		TooltipManager:SetTooltipSize(tooltip, tooltip.Width, tooltip.Height + height - row.Height)

		row.Height = height
		row:SetHeight(height)
	end
end

-- Invoked when the Cell is released back to its CellProvider.
function Cell:OnRelease()
	self:SetJustifyH('LEFT')
	self:ClearAllPoints()
	self:SetParent(nil)

	self.FontString:SetFontObject(GameTooltipText)
	self:SetText('')

	-- TODO: See if this can be changed to use something else, negating the need to store RGBA on the Cell itself.
	if self.r then
		self.FontString:SetTextColor(self.r, self.g, self.b, self.a)
	end

	self.ColSpan = 1
	self.ColumnIndex = 0
	self.HorizontalJustification = 'LEFT'
	self.RowIndex = 0
	self.LeftPadding = 0
	self.MaxWidth = nil
	self.MinWidth = nil
	self.RightPadding = 0
	self.Tooltip = nil
end

-- Sets the background color for the Cell.
---@param r? number Red color value of the Cell. Defaults to the Tooltip's current red value.
---@param g? number Green color value of the Cell. Defaults to the Tooltip's current green value.
---@param b? number Blue color value of the Cell. Defaults to the Tooltip's current blue value.
---@param a? number Alpha level of the Cell. Defaults to 1.
---@return LibQTip-2.0.Cell cell
function Cell:SetColor(r, g, b, a)
	local red, green, blue, alpha

	if r and g and b and a then
		red, green, blue, alpha = r, g, b, a
	else
		red, green, blue, alpha = self.Tooltip:GetBackdropColor()
	end

	self:SetBackdrop(TooltipManager.DefaultBackdrop)
	self:SetBackdropColor(red, green, blue, alpha)

	return self
end

-- Sets the number of Columns the Cell will span. Defaults to 1.
---@param size integer The number of Columns the Cell will span. Providing a negative or zero size will count back from the rightmost Column and update the ColSpan to its effective value.
---@return LibQTip-2.0.Cell cell
function Cell:SetColSpan(size)
	local row = self.Tooltip:GetRow(self.RowIndex)
	local colSpanCells = row.ColSpanCells
	local rowCells = row.Cells

	local columnIndex = self.ColumnIndex

	size = size or 1

	-- Remove the previously-defined ColSpan.
	for cellIndex = columnIndex + 1, columnIndex + self.ColSpan - 1 do
		rowCells[cellIndex] = nil
		colSpanCells[cellIndex] = nil
	end

	local columnCount = #self.Tooltip.Columns
	local rightColumnIndex

	if size > 0 then
		rightColumnIndex = columnIndex + size - 1

		if rightColumnIndex > columnCount then
			error('ColSpan too big: Cell extends beyond right-most Column', 3)
		end
	else
		rightColumnIndex = max(columnIndex, columnCount + size)
		size = 1 + rightColumnIndex - columnIndex
	end

	-- Cleanup ColSpans
	for cellIndex = columnIndex + 1, rightColumnIndex do
		if colSpanCells[cellIndex] then
			error(('Overlapping Cells at column %d'):format({ cellIndex }), 3)
		end

		local columnCell = rowCells[cellIndex]

		if columnCell then
			TooltipManager:ReleaseCell(columnCell)
		end

		colSpanCells[cellIndex] = true
	end

	self.ColSpan = size

	self:SetPoint('RIGHT', self.Tooltip.Columns[rightColumnIndex])

	return self
end

-- Sets the Cell's basic font properties.
---@param path string Path to the font file.
---@param height number Size in points.
---@param flags string Any comma-delimited combination of OUTLINE, THICK and MONOCHROME; otherwise must be at least an empty string.
---@return LibQTip-2.0.Cell cell
function Cell:SetFont(path, height, flags)
	self.FontString:SetFont(path, height, flags)

	return self
end

-- Sets the FontObject for the Cell's FontString.
---@param font? FontObject|Font The rendering Font. Defaults to the Tooltip's DefaultFont or DefaultHeadingFont, depending on the Cell's designation.
---@return LibQTip-2.0.Cell cell
function Cell:SetFontObject(font)
	self.FontString:SetFontObject(
		type(font) == 'string' and _G[font] or font or (self.Tooltip:GetRow(self.RowIndex).IsHeading and self.Tooltip:GetDefaultHeadingFont() or self.Tooltip:GetDefaultFont())
	)

	return self
end

-- Sets the text displayed in the Cell using format specifiers.
-- ***
-- Equivalent to:
--
-- ``` lua
-- cell:SetText(string.format("format", value))
-- ```
--
-- ...but does not create a throwaway Lua string object, resulting in greater memory-usage efficiency.
-- ***
---@param format string The format specifiers for the text to display in the Cell.
---@param ... unknown A list of values to be included in the formatted string.
---@return LibQTip-2.0.Cell cell
function Cell:SetFormattedText(format, ...)
	self.FontString:SetFormattedText(tostring(format), ...)
	self:OnContentChanged()

	return self
end

-- Sets the horizontal justification of the Cell's FontString.
---@param horizontalJustification JustifyHorizontal Cell-specific justification to use.
---@return LibQTip-2.0.Cell cell
function Cell:SetJustifyH(horizontalJustification)
	self.HorizontalJustification = horizontalJustification
	self.FontString:SetJustifyH(horizontalJustification)

	return self
end

-- Sets the left pixel padding of the Cell.
---@param pixels integer
---@return LibQTip-2.0.Cell cell
function Cell:SetLeftPadding(pixels)
	self.LeftPadding = pixels

	return self
end

-- Sets the maximum width of the Cell.
---@param maxWidth? integer
---@return LibQTip-2.0.Cell cell
function Cell:SetMaxWidth(maxWidth)
	local minWidth = self.MinWidth

	if maxWidth and minWidth and (maxWidth < minWidth) then
		error(("maxWidth (%d) cannot be less than the Cell's MinWidth (%d)"):format(maxWidth, minWidth), 2)
	end

	if maxWidth and (maxWidth < (self.LeftPadding + self.RightPadding)) then
		error(("maxWidth (%d) cannot be less than the sum of the Cell's LeftPadding (%d) and RightPadding (%d)"):format(maxWidth, self.LeftPadding, self.RightPadding), 2)
	end

	self.MaxWidth = maxWidth

	return self
end

-- Sets the minimum width of the Cell.
---@param minWidth? integer
---@return LibQTip-2.0.Cell cell
function Cell:SetMinWidth(minWidth)
	local maxWidth = self.MaxWidth

	if maxWidth and minWidth and (minWidth > maxWidth) then
		error(("minWidth (%d) cannot be greater than the Cell's MaxWidth (%d)"):format(minWidth, maxWidth), 2)
	end

	self.MinWidth = minWidth

	return self
end

-- Sets the right pixel padding of the Cell.
---@param pixels integer
---@return LibQTip-2.0.Cell cell
function Cell:SetRightPadding(pixels)
	self.RightPadding = pixels

	return self
end

-- Assigns a script to the Cell.
---@param scriptType LibQTip-2.0.ScriptType The ScriptType to assign to the Cell.
---@param handler fun(frame: Frame, ...) The function called when the script is run. Parameters conform to the given ScriptType.
---@param arg? unknown Data to be passed to the script function.
---@return LibQTip-2.0.Cell cell
function Cell:SetScript(scriptType, handler, arg)
	ScriptManager:SetScript(self, scriptType, handler, arg)

	return self
end

-- Sets the text displayed in the Cell.
---@param text string The text to display in the Cell.
---@return LibQTip-2.0.Cell cell
function Cell:SetText(text)
	self.FontString:SetText(tostring(text))
	self:OnContentChanged()

	return self
end

-- Sets the text color for the Cell.
---@param r? number Red color value of the Cell's text. Defaults to the red value of the Cell's FontString.
---@param g? number Green color value of the Cell's text. Defaults to the green value of the Cell's FontString.
---@param b? number Blue color value of the Cell's text. Defaults to the blue value of the Cell's FontString.
---@param a? number Alpha level of the Cell's text. Defaults to 1.
---@return LibQTip-2.0.Cell cell
function Cell:SetTextColor(r, g, b, a)
	if not self.r then
		self:SetRGBA(self.FontString:GetTextColor())
	end

	if not r then
		r, g, b, a = self:GetRGBA()
	end

	self.FontString:SetTextColor(r or 0, g or 0, b or 0, a or 1)

	return self
end
