---@class SUI
local SUI = SUI
---@class MoveIt
local MoveIt = SUI.MoveIt

-- Tracks which movers belong to the same anchor chain, so a frame is never snapped to one
-- of its own attached frames. Snapping itself lives in Snap.lua.

---@class SUI.MoveIt.MagnetismManager
local MagnetismManager = {}
MoveIt.MagnetismManager = MagnetismManager

---@type table<Frame, table<Frame, boolean>> child mover -> parent movers
local relationships = setmetatable({}, { __mode = 'k' })

---@param frame Frame
function MagnetismManager:RegisterFrame(frame) end

---@param frame Frame
function MagnetismManager:UnregisterFrame(frame)
	relationships[frame] = nil
end

---Record that `childMover` is positioned relative to `parentMover`
---@param childMover Frame
---@param parentMover Frame
function MagnetismManager:RegisterFrameRelationship(childMover, parentMover)
	if not childMover or not parentMover or childMover == parentMover then
		return
	end
	relationships[childMover] = relationships[childMover] or {}
	relationships[childMover][parentMover] = true
end

---The frames a frame is anchored to, from both live anchors and registered relationships
---@param frame Frame
---@return Frame[]
local function GetParents(frame)
	local parents = {}
	for i = 1, frame:GetNumPoints() do
		local _, anchor = frame:GetPoint(i)
		if anchor and anchor ~= UIParent then
			parents[#parents + 1] = anchor.mover or anchor
		end
	end
	if relationships[frame] then
		for parent in pairs(relationships[frame]) do
			parents[#parents + 1] = parent
		end
	end
	return parents
end

---True if `descendant` is anchored, directly or through other frames, to `ancestor`
---@param descendant Frame
---@param ancestor Frame
---@return boolean
function MagnetismManager:IsDescendantOf(descendant, ancestor)
	local seen = {}
	local queue = { descendant }
	while #queue > 0 do
		local current = table.remove(queue)
		if not seen[current] then
			seen[current] = true
			for _, parent in ipairs(GetParents(current)) do
				if parent == ancestor then
					return true
				end
				queue[#queue + 1] = parent
			end
		end
	end
	return false
end

---True if either mover is part of the other's anchor chain
---@param moverA Frame
---@param moverB Frame
---@return boolean
function MagnetismManager:AreRelated(moverA, moverB)
	return self:IsDescendantOf(moverA, moverB) or self:IsDescendantOf(moverB, moverA)
end

---@return boolean
function MagnetismManager:IsGridSnapActive()
	return MoveIt.DB and MoveIt.DB.GridSnapEnabled and true or false
end

function MagnetismManager:UpdateGridLines()
	if MoveIt.GridOverlay then
		MoveIt.GridOverlay:Refresh()
	end
end

function MagnetismManager:EndDragSession() end

function MagnetismManager:ClearSnapTargetHighlights() end
