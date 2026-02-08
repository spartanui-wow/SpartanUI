--------------------------------------------------------------------------------
---- Library Namespace
--------------------------------------------------------------------------------

local QTip = LibStub:GetLibrary('LibQTip-2.0')

---@class LibQTip-2.0.CellProvider
---@field CellHeap LibQTip-2.0.Cell[] Cells available for reuse.
---@field CellMetatable table<"__index", LibQTip-2.0.Cell> The metatable for all Cells from this CellProvider.
---@field CellPrototype LibQTip-2.0.Cell The prototype for all Cells from this CellProvider.
---@field Cells table<LibQTip-2.0.Cell, true|nil> Cells currently in use.
local CellProvider = QTip.CellProviderPrototype

--------------------------------------------------------------------------------
---- Methods
--------------------------------------------------------------------------------

-- Acquire a new cell to be displayed in the Tooltip.
--
-- LibQTip manages parent, framelevel, anchors, visibility and size of the Cell.
---@return LibQTip-2.0.Cell cell The acquired cell.
function CellProvider:AcquireCell()
	---@type LibQTip-2.0.Cell|nil
	local cell = tremove(self.CellHeap)

	if not cell then
		cell = setmetatable(CreateFrame('Frame', nil, UIParent, 'BackdropTemplate'), self.CellMetatable) --[[@as LibQTip-2.0.Cell]]

		Mixin(cell, ColorMixin)

		if type(cell.OnCreation) == 'function' then
			cell:OnCreation()
		end
	end

	cell.CellProvider = self

	self.Cells[cell] = true

	return cell
end

-- Return an iterator on currently acquired Cells.
---@return fun(tooltip: table<LibQTip-2.0.Cell, true|nil>, index?: LibQTip-2.0.Cell): LibQTip-2.0.Cell, true|nil
---@return table<LibQTip-2.0.Cell, true|nil>
function CellProvider:CellPairs()
	return pairs(self.Cells)
end

-- Return the prototype and metatable used to create new Cells.
---@return LibQTip-2.0.Cell cellPrototype The prototype on which Cells are based.
---@return table<"__index", LibQTip-2.0.Cell> cellMetatable The metatable used to create a new Cell.
function CellProvider:GetCellPrototype()
	return self.CellPrototype, self.CellMetatable
end

-- Release a Cell that LibQTip is no longer using. The Cell has already been hidden, unanchored and orphaned by LibQTip.
---@param cell LibQTip-2.0.Cell The Cell to release.
function CellProvider:ReleaseCell(cell)
	if not self.Cells[cell] then
		return
	end

	if type(cell.OnRelease) == 'function' then
		cell:OnRelease()
	end

	self.Cells[cell] = nil
	tinsert(self.CellHeap, cell)
end
