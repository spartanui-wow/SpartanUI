---@class SUI
local SUI = SUI
---@class MoveIt
local MoveIt = SUI.MoveIt
local Style = SUI.UI.Style

-- Alignment snapping while dragging. Each axis looks for the closest line within reach: the
-- left/center/right (or bottom/center/top) of another frame, the screen edges and center, and
-- grid lines when grid snapping is on. Full-screen guide lines show what the frame lined up with.
-- Everything is measured in UIParent units.

---@class SUI.MoveIt.Snap
local Snap = {}
MoveIt.Snap = Snap

local THRESHOLD = 6

---@class SUI.MoveIt.SnapTarget
---@field frame Frame
---@field l number
---@field b number
---@field r number
---@field t number

---@type SUI.MoveIt.SnapTarget[]
local targets = {}

---A frame's rectangle in UIParent units
---@param frame Frame
---@return number|nil left, number bottom, number right, number top
function Snap:GetRect(frame)
	local left, bottom, width, height = frame:GetRect()
	if not left then
		return nil, 0, 0, 0
	end
	local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return left * ratio, bottom * ratio, (left + width) * ratio, (bottom + height) * ratio
end

---Collect everything the dragged mover may line up with
---@param mover SUI.MoveIt.Mover
function Snap:BeginDrag(mover)
	wipe(targets)
	local MagnetismManager = MoveIt.MagnetismManager
	for _, other in pairs(MoveIt.MoverList) do
		if other ~= mover and other:IsShown() and not other.isCustomMover and not MagnetismManager:IsDescendantOf(other, mover) then
			local l, b, r, t = self:GetRect(other)
			if l then
				targets[#targets + 1] = { frame = other, l = l, b = b, r = r, t = t }
			end
		end
	end
end

function Snap:EndDrag()
	wipe(targets)
	self:HideGuides()
end

---Closest line to any of the three edges within reach
---@param edges number[] low, middle, high edge of the dragged frame
---@param lines table[] { pos = number, frame? = Frame }
---@return number|nil delta, table|nil line
local function Closest(edges, lines)
	local bestDelta, bestLine
	for _, line in ipairs(lines) do
		for _, edge in ipairs(edges) do
			local delta = line.pos - edge
			if math.abs(delta) <= THRESHOLD and (not bestDelta or math.abs(delta) < math.abs(bestDelta)) then
				bestDelta, bestLine = delta, line
			end
		end
	end
	return bestDelta, bestLine
end

---How far to shift a frame with this rectangle so it lines up with something
---@param l number
---@param b number
---@param r number
---@param t number
---@return number dx, number dy, table|nil xLine, table|nil yLine
function Snap:Compute(l, b, r, t)
	if IsControlKeyDown() then
		return 0, 0, nil, nil
	end
	local db = MoveIt.DB
	local width, height = UIParent:GetSize()
	local xLines, yLines = {}, {}

	if db.ElementSnapEnabled ~= false then
		xLines[#xLines + 1] = { pos = 0 }
		xLines[#xLines + 1] = { pos = width / 2 }
		xLines[#xLines + 1] = { pos = width }
		yLines[#yLines + 1] = { pos = 0 }
		yLines[#yLines + 1] = { pos = height / 2 }
		yLines[#yLines + 1] = { pos = height }
		for _, target in ipairs(targets) do
			xLines[#xLines + 1] = { pos = target.l, frame = target.frame }
			xLines[#xLines + 1] = { pos = (target.l + target.r) / 2, frame = target.frame }
			xLines[#xLines + 1] = { pos = target.r, frame = target.frame }
			yLines[#yLines + 1] = { pos = target.b, frame = target.frame }
			yLines[#yLines + 1] = { pos = (target.b + target.t) / 2, frame = target.frame }
			yLines[#yLines + 1] = { pos = target.t, frame = target.frame }
		end
	end

	local xEdges = { l, (l + r) / 2, r }
	local yEdges = { b, (b + t) / 2, t }

	if db.GridSnapEnabled then
		local spacing = db.GridSpacing or 32
		for _, edge in ipairs(xEdges) do
			xLines[#xLines + 1] = { pos = width / 2 + math.floor((edge - width / 2) / spacing + 0.5) * spacing, grid = true }
		end
		for _, edge in ipairs(yEdges) do
			yLines[#yLines + 1] = { pos = height / 2 + math.floor((edge - height / 2) / spacing + 0.5) * spacing, grid = true }
		end
	end

	local dx, xLine = Closest(xEdges, xLines)
	local dy, yLine = Closest(yEdges, yLines)
	return dx or 0, dy or 0, xLine, yLine
end

----------------------------------------------------------------------------------------------------
-- Guide lines
----------------------------------------------------------------------------------------------------

function Snap:CreateGuides()
	if self.guides then
		return
	end
	local holder = CreateFrame('Frame', nil, UIParent)
	holder:SetAllPoints(UIParent)
	holder:SetFrameStrata('FULLSCREEN_DIALOG')
	holder:EnableMouse(false)
	local vertical = holder:CreateTexture(nil, 'OVERLAY')
	vertical:SetTexture(Style.WHITE)
	vertical:Hide()
	local horizontal = holder:CreateTexture(nil, 'OVERLAY')
	horizontal:SetTexture(Style.WHITE)
	horizontal:Hide()
	self.guides = { holder = holder, vertical = vertical, horizontal = horizontal }
end

---Show guide lines for the lines the frame snapped to
---@param xLine table|nil
---@param yLine table|nil
function Snap:ShowGuides(xLine, yLine)
	self:CreateGuides()
	local guides = self.guides
	local px = Style:PixelSize(guides.holder)
	local r, g, b = Style:GetAccent()
	if xLine then
		guides.vertical:ClearAllPoints()
		guides.vertical:SetPoint('TOP', guides.holder, 'TOPLEFT', xLine.pos, 0)
		guides.vertical:SetPoint('BOTTOM', guides.holder, 'BOTTOMLEFT', xLine.pos, 0)
		guides.vertical:SetWidth(px)
		guides.vertical:SetVertexColor(r, g, b, 0.9)
		guides.vertical:Show()
	else
		guides.vertical:Hide()
	end
	if yLine then
		guides.horizontal:ClearAllPoints()
		guides.horizontal:SetPoint('LEFT', guides.holder, 'BOTTOMLEFT', 0, yLine.pos)
		guides.horizontal:SetPoint('RIGHT', guides.holder, 'BOTTOMRIGHT', 0, yLine.pos)
		guides.horizontal:SetHeight(px)
		guides.horizontal:SetVertexColor(r, g, b, 0.9)
		guides.horizontal:Show()
	else
		guides.horizontal:Hide()
	end
end

function Snap:HideGuides()
	if self.guides then
		self.guides.vertical:Hide()
		self.guides.horizontal:Hide()
	end
end
