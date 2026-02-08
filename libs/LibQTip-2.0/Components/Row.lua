--------------------------------------------------------------------------------
---- Library Namespace
--------------------------------------------------------------------------------

local QTip = LibStub:GetLibrary('LibQTip-2.0')

local ScriptManager = QTip.ScriptManager
local TooltipManager = QTip.TooltipManager

---@class LibQTip-2.0.Row: LibQTip-2.0.ScriptFrame
---@field Cells (LibQTip-2.0.Cell|nil)[] Cells indexed by Column.
---@field ColSpanCells (true|nil)[] A value of true means the Column index is part of a ColSpan.
---@field Height number Height, in pixels.
---@field Index integer The Row's index on its Tooltip
---@field IsHeading? true Determines whether the Tooltip's DefaultFont or DefaultHeadingFont should be used for Cells in this Row.
---@field Tooltip LibQTip-2.0.Tooltip The Row's Tooltip.
local Row = TooltipManager.RowPrototype

--------------------------------------------------------------------------------
---- Methods
--------------------------------------------------------------------------------

---@param columnIndex integer Column index of the Cell.
---@param cellProvider? LibQTip-2.0.CellProvider The CellProvider to use. Defaults to the Cell's Tooltip's default CellProvider.
---@return LibQTip-2.0.Cell
---@nodiscard
function Row:GetCell(columnIndex, cellProvider)
	if self.ColSpanCells[columnIndex] then
		error(('Overlapping Cells at column %d'):format(columnIndex), 3)
	end

	local existingCell = self.Cells[columnIndex]

	if existingCell then
		if cellProvider == nil or existingCell.CellProvider == cellProvider then
			return existingCell
		end

		TooltipManager:ReleaseCell(existingCell)
		self.Cells[columnIndex] = nil
	end

	return TooltipManager:AcquireCell(self.Tooltip, self, self.Tooltip:GetColumn(columnIndex), cellProvider or self.Tooltip:GetDefaultCellProvider())
end

-- Returns the RGBA numbers for the Row.
---@return number red Red color, from 0 to 1
---@return number green Green color, from 0 to 1
---@return number blue Blue color, from 0 to 1
---@return number alpha Alpha level, from 0 to 1
function Row:GetColor()
	return self:GetBackdropColor()
end

-- Sets the background color for the Row.
---@param r? number Red color value of the Row. Defaults to the Tooltip's current red value.
---@param g? number Green color value of the Row. Defaults to the Tooltip's current green value.
---@param b? number Blue color value of the Row. Defaults to the Tooltip's current blue value.
---@param a? number Alpha level of the Row. Defaults to 1.
---@return LibQTip-2.0.Row
function Row:SetColor(r, g, b, a)
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

-- Assigns a script to the Row.
---@param scriptType LibQTip-2.0.ScriptType The column ScriptType.
---@param handler fun(frame: Frame, ...) The function called when the script is run. Parameters conform to the given ScriptType.
---@param arg? string Data to be passed to the script handler.
---@return LibQTip-2.0.Row
function Row:SetScript(scriptType, handler, arg)
	ScriptManager:SetScript(self, scriptType, handler, arg)

	return self
end

-- Sets the text color for every Cell in the Row.
---@param r? number Red color value of the Row's text. Defaults to the red value of the Tooltip's default Font.
---@param g? number Green color value of the Row's text. Defaults to the green value of the Tooltip's default Font.
---@param b? number Blue color value of the Row's text. Defaults to the blue value of the Tooltip's default Font.
---@param a? number Alpha level of the Row's text. Defaults to 1.
---@return LibQTip-2.0.Row
function Row:SetTextColor(r, g, b, a)
	if not r then
		r, g, b, a = self.Tooltip:GetDefaultFont():GetTextColor()
	end

	for cellIndex = 1, #self.Cells do
		self.Cells[cellIndex]:SetTextColor(r, g, b, a)
	end

	return self
end
