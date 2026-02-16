---@class SUI
local SUI = SUI
local MoveIt = SUI.MoveIt

---@class SUI.MoveIt.MagnetismManager
---@field magnetismRange number Pixels to trigger snap
---@field sqrMagnetismRange number Pre-calculated squared range
---@field sqrCornerMagnetismRange number Corner snaps have larger range
---@field enabled boolean Whether magnetism is enabled
---@field magneticFrames table<Frame, boolean> Registered frames for snapping
---@field previewLinesAvailable boolean Whether preview lines are supported
---@field previewLinePool ObjectPoolMixin|nil Pool for preview lines
---@field currentDragFrame Frame|nil Frame currently being dragged
local MagnetismManager = {}
MoveIt.MagnetismManager = MagnetismManager

-- Configuration
MagnetismManager.magnetismRange = 8
MagnetismManager.sqrMagnetismRange = 64
MagnetismManager.sqrCornerMagnetismRange = 128 -- 2x normal range for corners
-- On Retail, magnetism is enabled by default; on Classic, disabled by default (hold Shift to enable)
MagnetismManager.enabled = SUI.IsRetail and true or false
MagnetismManager.magneticFrames = {}
MagnetismManager.previewLinesAvailable = false
MagnetismManager.currentDragFrame = nil
MagnetismManager.debugLogging = true -- Set to true for verbose snap detection logging

-- UIParent cached values
MagnetismManager.uiParentCenterX = 0
MagnetismManager.uiParentCenterY = 0
MagnetismManager.uiParentLeft = 0
MagnetismManager.uiParentRight = 0
MagnetismManager.uiParentTop = 0
MagnetismManager.uiParentBottom = 0
MagnetismManager.uiParentWidth = 0
MagnetismManager.uiParentHeight = 0

-- Grid snapping
MagnetismManager.gridLines = { horizontal = {}, vertical = {} }
MagnetismManager.gridSpacing = 100 -- Default, will be read from EditMode settings
MagnetismManager.gridEnabled = false

-- Snap target highlighting (flashing border on potential snap targets)
MagnetismManager.currentSnapTargets = {} -- Track currently highlighted snap target frames
MagnetismManager.snapTargetFlashState = false -- Toggle for flash animation
MagnetismManager.snapTargetFlashFrame = nil -- Frame for OnUpdate animation
MagnetismManager.snapTargetFlashInterval = 0.15 -- Flash interval in seconds (fast flash)
MagnetismManager.snapTargetFlashElapsed = 0

-- Frame relationship tracking for circular dependency detection
-- Stores {childMover = parentMover} relationships based on initial positioning
MagnetismManager.frameRelationships = {}

-- Colorblind-friendly colors for snap target highlighting
-- Using blue/purple tones that contrast with orange selection
MagnetismManager.SNAP_TARGET_COLORS = {
	flash1 = { 0.4, 0.6, 1.0, 1.0 }, -- Light blue
	flash2 = { 0.7, 0.5, 0.9, 1.0 }, -- Light purple/magenta
}

---Update UIParent dimensions cache
function MagnetismManager:UpdateUIParentPoints()
	self.uiParentCenterX, self.uiParentCenterY = UIParent:GetCenter()

	local left = UIParent:GetLeft() or 0
	local bottom = UIParent:GetBottom() or 0
	local width = UIParent:GetWidth() or 0
	local height = UIParent:GetHeight() or 0

	self.uiParentWidth = width
	self.uiParentHeight = height
	self.uiParentLeft = left
	self.uiParentRight = left + width
	self.uiParentBottom = bottom
	self.uiParentTop = bottom + height

	if MoveIt.logger then
		MoveIt.logger.debug(('UIParent: center=(%.0f,%.0f) left=%.0f bottom=%.0f width=%.0f height=%.0f'):format(self.uiParentCenterX or 0, self.uiParentCenterY or 0, left, bottom, width, height))
	end
end

---Set the magnetism range
---@param range number Pixel range for snapping
function MagnetismManager:SetMagnetismRange(range)
	self.magnetismRange = range
	self.sqrMagnetismRange = range * range
	self.sqrCornerMagnetismRange = self.sqrMagnetismRange * 2
end

---Check if magnetism is currently active
---On Retail: respects the enabled setting
---On Classic: magnetism is active when Shift is held (regardless of enabled setting)
---@return boolean
function MagnetismManager:IsActive()
	if SUI.IsRetail then
		return self.enabled
	else
		-- On Classic, Shift key enables magnetism temporarily
		return IsShiftKeyDown()
	end
end

---Register a frame for magnetism
---@param frame Frame The frame to register
function MagnetismManager:RegisterFrame(frame)
	if frame then
		self.magneticFrames[frame] = true
	end
end

---Unregister a frame from magnetism
---@param frame Frame The frame to unregister
function MagnetismManager:UnregisterFrame(frame)
	if frame then
		self.magneticFrames[frame] = nil
	end
end

---Initialize preview lines (Retail only)
function MagnetismManager:InitializePreviewLines()
	-- Check if CreateLine API is available (Retail only)
	if not UIParent.CreateLine then
		self.previewLinesAvailable = false
		if MoveIt.logger then
			MoveIt.logger.debug('Preview lines not available (CreateLine API missing)')
		end
		return
	end

	self.previewLinesAvailable = true

	-- Create container frame at high strata
	self.previewLineContainer = CreateFrame('Frame', 'SUI_MoveIt_PreviewLines', UIParent)
	self.previewLineContainer:SetAllPoints()
	self.previewLineContainer:SetFrameStrata('TOOLTIP')
	self.previewLineContainer:Hide()

	-- Create line pool
	if CreateObjectPool then
		self.previewLinePool = CreateObjectPool(function(pool)
			local line = self.previewLineContainer:CreateLine(nil, 'OVERLAY')
			line:SetThickness(2)
			line:SetColorTexture(1, 0.82, 0, 0.8) -- Gold color
			return line
		end, function(pool, line)
			line:Hide()
			line:ClearAllPoints()
		end)
	end

	if MoveIt.logger then
		MoveIt.logger.info('Preview lines initialized')
	end
end

---Get a frame's sides in screen coordinates
---@param frame Frame The frame
---@return number left, number right, number bottom, number top
function MagnetismManager:GetFrameSides(frame)
	local left = frame:GetLeft() or 0
	local right = frame:GetRight() or 0
	local bottom = frame:GetBottom() or 0
	local top = frame:GetTop() or 0
	return left, right, bottom, top
end

---Get a frame's center in screen coordinates
---@param frame Frame The frame
---@return number centerX, number centerY
function MagnetismManager:GetFrameCenter(frame)
	local centerX, centerY = frame:GetCenter()
	return centerX or 0, centerY or 0
end

---Check if frame A is to the left of frame B
---@param frameA Frame First frame
---@param frameB Frame Second frame
---@return boolean
function MagnetismManager:IsToTheLeftOfFrame(frameA, frameB)
	local centerAX = select(1, frameA:GetCenter()) or 0
	local centerBX = select(1, frameB:GetCenter()) or 0
	return centerAX < centerBX
end

---Check if frame A is above frame B
---@param frameA Frame First frame
---@param frameB Frame Second frame
---@return boolean
function MagnetismManager:IsAboveFrame(frameA, frameB)
	local centerAY = select(2, frameA:GetCenter()) or 0
	local centerBY = select(2, frameB:GetCenter()) or 0
	return centerAY > centerBY
end

---Register a frame relationship (child mover is anchored to parent mover)
---Called when a frame is initially positioned with another frame as anchor
---@param childMover Frame The mover whose parent frame is being anchored
---@param parentMover Frame The mover whose parent frame is the anchor target
function MagnetismManager:RegisterFrameRelationship(childMover, parentMover)
	if not childMover or not parentMover then
		return
	end

	self.frameRelationships[childMover] = parentMover

	if MoveIt.logger then
		local childName = childMover.name or childMover:GetName() or 'unknown'
		local parentName = parentMover.name or parentMover:GetName() or 'unknown'
		MoveIt.logger.info(('Registered relationship: %s -> %s'):format(childName, parentName))
	end
end

---Check if two movers have a registered parent/child relationship
---@param moverA Frame First mover
---@param moverB Frame Second mover
---@return boolean
function MagnetismManager:HasFrameRelationship(moverA, moverB)
	if not moverA or not moverB then
		return false
	end

	-- Check if moverA is anchored to moverB or vice versa
	return self.frameRelationships[moverA] == moverB or self.frameRelationships[moverB] == moverA
end

---Check if a frame is anchored to another frame (direct child)
---@param potentialChild Frame The frame that might be anchored to parent
---@param potentialParent Frame The frame that might be the anchor
---@return boolean
function MagnetismManager:IsFrameAnchoredTo(potentialChild, potentialParent)
	if not potentialChild or not potentialParent then
		return false
	end

	local numPoints = potentialChild:GetNumPoints()
	for i = 1, numPoints do
		local _, relativeTo = potentialChild:GetPoint(i)
		if relativeTo == potentialParent then
			return true
		end
	end
	return false
end

-- Proximity range for frame-to-frame snapping (pixels)
-- Frames must be within this distance to be considered for snapping
-- This is a pre-filter to avoid checking every frame on screen
MagnetismManager.proximityRange = 50

---Check if two frames are within proximity range (close enough to consider for snapping)
---Uses LibSimpleSticky's approach: frames must overlap in one direction to be candidates
---@param frameA Frame First frame
---@param frameB Frame Second frame
---@return boolean
function MagnetismManager:IsWithinProximity(frameA, frameB)
	if frameB == UIParent then
		return true -- UIParent/grid is always eligible
	end

	local leftA, rightA, bottomA, topA = self:GetFrameSides(frameA)
	local leftB, rightB, bottomB, topB = self:GetFrameSides(frameB)

	-- CRITICAL FIX: Check if bounding boxes overlap in at least one direction
	-- This prevents distant frames from becoming snap candidates even if aligned
	-- (e.g., HudTooltip and BT4BarQueueStatus 400px apart horizontally but same Y level)
	local xOverlap = (leftA <= rightB and leftB <= rightA)
	local yOverlap = (bottomA <= topB and bottomB <= topA)

	-- If frames don't overlap in either direction, they're too far apart
	if not (xOverlap or yOverlap) then
		if MoveIt.logger and self.debugLogging then
			local nameA = (frameA.name or 'unknown')
			local nameB = (frameB.name or 'unknown')
			MoveIt.logger.debug(('Proximity REJECT (no overlap): %s -> %s'):format(nameA, nameB))
		end
		return false
	end

	-- Calculate the closest distance between the two frames' bounding boxes
	local distX = 0
	local distY = 0

	-- X distance
	if rightA < leftB then
		distX = leftB - rightA
	elseif rightB < leftA then
		distX = leftA - rightB
	end

	-- Y distance
	if topA < bottomB then
		distY = bottomB - topA
	elseif topB < bottomA then
		distY = bottomA - topB
	end

	-- Both X and Y distance must be within proximity range
	local isWithin = distX <= self.proximityRange and distY <= self.proximityRange

	-- Debug logging for distance-based rejections
	if MoveIt.logger and self.debugLogging and not isWithin and (distX > 100 or distY > 100) then
		local nameA = (frameA.name or 'unknown')
		local nameB = (frameB.name or 'unknown')
		MoveIt.logger.debug(('Proximity REJECT (distance): %s -> %s (distX=%.1f, distY=%.1f, range=%d)'):format(nameA, nameB, distX, distY, self.proximityRange))
	end

	return isWithin
end

---Get eligible magnetic frames for snapping
---NOTE: With LibSimpleSticky handling frame-to-frame snapping, this now ONLY returns UIParent for grid snapping
---@param movingFrame Frame The frame being moved
---@return table eligibleFrames {horizontal = {}, vertical = {}}
function MagnetismManager:GetEligibleMagneticFrames(movingFrame)
	-- MagnetismManager now handles ONLY grid snapping
	-- LibSimpleSticky (via FrameSnap) handles frame-to-frame snapping
	local eligibleFrames = {
		horizontal = { UIParent },
		vertical = { UIParent },
	}

	return eligibleFrames
end

---Check if two frames are horizontally aligned (overlapping Y range)
---@param frameA Frame First frame
---@param frameB Frame Second frame
---@return boolean
function MagnetismManager:CheckHorizontalEligibility(frameA, frameB)
	local _, _, bottomA, topA = self:GetFrameSides(frameA)
	local _, _, bottomB, topB = self:GetFrameSides(frameB)

	-- Check if Y ranges overlap
	return not (topA < bottomB or bottomA > topB)
end

---Check if two frames are vertically aligned (overlapping X range)
---@param frameA Frame First frame
---@param frameB Frame Second frame
---@return boolean
function MagnetismManager:CheckVerticalEligibility(frameA, frameB)
	local leftA, rightA = self:GetFrameSides(frameA)
	local leftB, rightB = self:GetFrameSides(frameB)

	-- Check if X ranges overlap
	return not (rightA < leftB or leftA > rightB)
end

---Create magnetic frame info table
---@param frame Frame The magnetic frame
---@param point string The anchor point on the moving frame
---@param relativePoint string The anchor point on the magnetic frame
---@param distance number The distance to snap
---@param offset number Any offset to apply
---@param isHorizontal boolean Whether this is a horizontal snap
---@param isCornerSnap? boolean Whether this is a corner snap
---@return table
function MagnetismManager:GetMagneticFrameInfoTable(frame, point, relativePoint, distance, offset, isHorizontal, isCornerSnap)
	return {
		frame = frame,
		point = point,
		relativePoint = relativePoint,
		distance = distance,
		offset = offset or 0,
		isHorizontal = isHorizontal,
		isCornerSnap = isCornerSnap or false,
	}
end

---Check if we should replace the current magnetic frame info with a new one
---@param currentInfo table|nil Current magnetic frame info
---@param frame Frame New frame
---@param point string New point
---@param relativePoint string New relative point
---@param distance number New distance (in screen pixels)
---@param offset number New offset
---@param isHorizontal boolean Is horizontal snap
---@return table|nil
function MagnetismManager:CheckReplaceMagneticFrameInfo(currentInfo, frame, point, relativePoint, distance, offset, isHorizontal)
	-- Distance is already in screen pixels from GetLeft/GetRight/etc.
	-- No need to scale - just compare directly to magnetism range
	if distance > self.magnetismRange then
		return currentInfo
	end

	if not currentInfo or distance < currentInfo.distance then
		return self:GetMagneticFrameInfoTable(frame, point, relativePoint, distance, offset, isHorizontal)
	else
		return currentInfo
	end
end

---Get check points for UIParent snapping
---@param movingFrame Frame The frame being moved
---@param verticalLines boolean True for X-axis (vertical lines), false for Y-axis
---@return table
function MagnetismManager:GetUIParentCheckPoints(movingFrame, verticalLines)
	local left, right, bottom, top = self:GetFrameSides(movingFrame)
	local centerX, centerY = self:GetFrameCenter(movingFrame)

	-- Only include center snaps when grid is enabled
	-- (center line is part of the grid, not a UIParent edge)
	local includeCenter = self.gridEnabled

	if verticalLines then
		local points = {
			{ point = 'LEFT', relativePoint = 'LEFT', source = left, target = self.uiParentLeft },
			{ point = 'RIGHT', relativePoint = 'RIGHT', source = right, target = self.uiParentRight },
		}
		if includeCenter then
			table.insert(points, { point = 'CENTER', relativePoint = 'CENTER', source = centerX, target = self.uiParentCenterX })
			table.insert(points, { point = 'LEFT', relativePoint = 'CENTER', source = left, target = self.uiParentCenterX })
			table.insert(points, { point = 'RIGHT', relativePoint = 'CENTER', source = right, target = self.uiParentCenterX })
		end
		return points
	else
		local points = {
			{ point = 'TOP', relativePoint = 'TOP', source = top, target = self.uiParentTop },
			{ point = 'BOTTOM', relativePoint = 'BOTTOM', source = bottom, target = self.uiParentBottom },
		}
		if includeCenter then
			table.insert(points, { point = 'CENTER', relativePoint = 'CENTER', source = centerY, target = self.uiParentCenterY })
			table.insert(points, { point = 'TOP', relativePoint = 'CENTER', source = top, target = self.uiParentCenterY })
			table.insert(points, { point = 'BOTTOM', relativePoint = 'CENTER', source = centerY, target = self.uiParentCenterY })
		end
		return points
	end
end

---Check if grid snapping is active (uses MoveIt's own setting)
---@return boolean
function MagnetismManager:IsGridSnapActive()
	if MoveIt.DB and MoveIt.DB.GridSnapEnabled ~= nil then
		return MoveIt.DB.GridSnapEnabled
	end
	return true
end

---Check if "Snap to elements" is enabled (uses MoveIt's own setting)
---@return boolean
function MagnetismManager:IsElementSnapActive()
	if MoveIt.DB and MoveIt.DB.ElementSnapEnabled ~= nil then
		return MoveIt.DB.ElementSnapEnabled
	end
	return true
end

---Get current grid spacing from MoveIt settings
---@return number gridSpacing The grid spacing in pixels (default 32)
function MagnetismManager:GetGridSpacing()
	-- Use MoveIt's independent grid setting
	if MoveIt.DB and MoveIt.DB.GridSpacing then
		return MoveIt.DB.GridSpacing
	end

	-- Default fallback (32px is a good balance for most UI elements)
	return 32
end

---Update grid lines cache based on current settings
---Grid lines are positioned at multiples of gridSpacing from the center of the screen
function MagnetismManager:UpdateGridLines()
	self.gridLines = { horizontal = {}, vertical = {} }

	if not self:IsGridSnapActive() then
		self.gridEnabled = false
		return
	end

	self.gridEnabled = true
	self.gridSpacing = self:GetGridSpacing()

	-- Calculate center of screen
	local centerX = self.uiParentCenterX
	local centerY = self.uiParentCenterY

	-- Calculate how many grid lines fit from center to edge
	local halfNumVertical = math.floor((self.uiParentWidth / self.gridSpacing) / 2)
	local halfNumHorizontal = math.floor((self.uiParentHeight / self.gridSpacing) / 2)

	-- Add center lines (offset 0)
	table.insert(self.gridLines.vertical, centerX)
	table.insert(self.gridLines.horizontal, centerY)

	-- Add vertical grid lines (left and right of center)
	for i = 1, halfNumVertical do
		local offset = i * self.gridSpacing
		table.insert(self.gridLines.vertical, centerX + offset) -- Right of center
		table.insert(self.gridLines.vertical, centerX - offset) -- Left of center
	end

	-- Add horizontal grid lines (above and below center)
	for i = 1, halfNumHorizontal do
		local offset = i * self.gridSpacing
		table.insert(self.gridLines.horizontal, centerY + offset) -- Above center
		table.insert(self.gridLines.horizontal, centerY - offset) -- Below center
	end

	if MoveIt.logger and self.debugLogging then
		MoveIt.logger.debug(('Grid updated: spacing=%d, vertical=%d lines, horizontal=%d lines'):format(self.gridSpacing, #self.gridLines.vertical, #self.gridLines.horizontal))
	end
end

---Find closest UIParent edge or grid line
---@param movingFrame Frame The frame being moved
---@param verticalLines boolean True for vertical lines (X-axis snapping)
---@return number|nil distance, string|nil point, string|nil relativePoint, number offset, number|nil gridLinePos
function MagnetismManager:FindClosestGridLine(movingFrame, verticalLines)
	local closestDistance, closestPoint, closestRelativePoint
	local closestOffset = 0
	local closestGridLinePos = nil -- Track the actual grid line position

	-- First find closest distance to UIParent sides/center
	local uiParentCheckPoints = self:GetUIParentCheckPoints(movingFrame, verticalLines)
	for _, checkPoint in ipairs(uiParentCheckPoints) do
		local distance = math.abs(checkPoint.target - checkPoint.source)
		if not closestDistance or distance < closestDistance then
			closestDistance = distance
			closestPoint = checkPoint.point
			closestRelativePoint = checkPoint.relativePoint
			closestOffset = 0 -- UIParent edges have no offset
			closestGridLinePos = nil -- Not a grid line
		end
	end

	-- If grid is active, check grid lines for closer snaps
	if self.gridEnabled and self.gridLines then
		local gridLinesList = verticalLines and self.gridLines.vertical or self.gridLines.horizontal
		local frameCheckPoints = self:GetGridLineCheckPoints(movingFrame, verticalLines)

		for _, gridLinePos in ipairs(gridLinesList) do
			for _, checkPoint in ipairs(frameCheckPoints) do
				local distance = math.abs(gridLinePos - checkPoint.source)
				if distance < (closestDistance or math.huge) then
					closestDistance = distance
					closestPoint = checkPoint.point
					closestRelativePoint = 'CENTER' -- Grid lines are relative to CENTER

					-- Calculate offset from UIParent CENTER to this grid line
					if verticalLines then
						closestOffset = gridLinePos - self.uiParentCenterX
					else
						closestOffset = gridLinePos - self.uiParentCenterY
					end
					closestGridLinePos = gridLinePos
				end
			end
		end

		-- Grid snap logging handled in GetMagneticFrameInfos (rate limited)
	end

	return closestDistance, closestPoint, closestRelativePoint, closestOffset, closestGridLinePos
end

---Get check points for grid line snapping (frame edges and center)
---@param movingFrame Frame The frame being moved
---@param verticalLines boolean True for vertical lines (check X coords), false for horizontal (check Y coords)
---@return table checkPoints Array of {point, source} where source is the frame's coord to compare
function MagnetismManager:GetGridLineCheckPoints(movingFrame, verticalLines)
	local left, right, bottom, top = self:GetFrameSides(movingFrame)
	local centerX, centerY = self:GetFrameCenter(movingFrame)

	if verticalLines then
		-- For vertical grid lines, we check X coordinates (left, right, center)
		return {
			{ point = 'LEFT', relativePoint = 'CENTER', source = left },
			{ point = 'RIGHT', relativePoint = 'CENTER', source = right },
			{ point = 'CENTER', relativePoint = 'CENTER', source = centerX },
		}
	else
		-- For horizontal grid lines, we check Y coordinates (top, bottom, center)
		return {
			{ point = 'TOP', relativePoint = 'CENTER', source = top },
			{ point = 'BOTTOM', relativePoint = 'CENTER', source = bottom },
			{ point = 'CENTER', relativePoint = 'CENTER', source = centerY },
		}
	end
end

---Calculate squared distance between two points
---@param x1 number First X
---@param y1 number First Y
---@param x2 number Second X
---@param y2 number Second Y
---@return number
function MagnetismManager:CalculateDistanceSq(x1, y1, x2, y2)
	local dx = x2 - x1
	local dy = y2 - y1
	return dx * dx + dy * dy
end

---Get corner magnetic frame info if within range
---@param movingFrame Frame The frame being moved
---@param potentialFrameInfo table|nil Potential frame to snap to
---@return table|nil
function MagnetismManager:GetCornerMagneticFrameInfo(movingFrame, potentialFrameInfo)
	if not potentialFrameInfo or not potentialFrameInfo.frame then
		return nil
	end

	local frameLeft, frameRight, frameBottom, frameTop = self:GetFrameSides(movingFrame)
	local framePoints = {
		TOPLEFT = { x = frameLeft, y = frameTop },
		TOPRIGHT = { x = frameRight, y = frameTop },
		BOTTOMLEFT = { x = frameLeft, y = frameBottom },
		BOTTOMRIGHT = { x = frameRight, y = frameBottom },
	}

	local targetFrame = potentialFrameInfo.frame
	local targetLeft, targetRight, targetBottom, targetTop = self:GetFrameSides(targetFrame)
	local targetPoints = {
		TOPLEFT = { x = targetLeft, y = targetTop },
		TOPRIGHT = { x = targetRight, y = targetTop },
		BOTTOMLEFT = { x = targetLeft, y = targetBottom },
		BOTTOMRIGHT = { x = targetRight, y = targetBottom },
	}

	local closestPoint, closestRelativePoint, closestSqrDistance

	for framePointName, framePointPos in pairs(framePoints) do
		for targetPointName, targetPointPos in pairs(targetPoints) do
			-- Exclude diagonal corner connections
			local isDiagonal = (framePointName == 'TOPLEFT' and targetPointName == 'BOTTOMRIGHT')
				or (framePointName == 'TOPRIGHT' and targetPointName == 'BOTTOMLEFT')
				or (framePointName == 'BOTTOMLEFT' and targetPointName == 'TOPRIGHT')
				or (framePointName == 'BOTTOMRIGHT' and targetPointName == 'TOPLEFT')

			if not isDiagonal then
				local sqrDist = self:CalculateDistanceSq(framePointPos.x, framePointPos.y, targetPointPos.x, targetPointPos.y)

				if sqrDist <= self.sqrCornerMagnetismRange then
					if not closestSqrDistance or sqrDist < closestSqrDistance then
						closestPoint = framePointName
						closestRelativePoint = targetPointName
						closestSqrDistance = sqrDist
					end
				end
			end
		end
	end

	if closestSqrDistance then
		local isCornerSnap = true
		return self:GetMagneticFrameInfoTable(targetFrame, closestPoint, closestRelativePoint, math.sqrt(closestSqrDistance), 0, potentialFrameInfo.isHorizontal, isCornerSnap)
	end

	return nil
end

---Get magnetic frame info options (horizontal, vertical, and corner)
---@param movingFrame Frame The frame being moved
---@return table|nil horizontalInfo, table|nil verticalInfo, table|nil cornerInfo
function MagnetismManager:GetMagneticFrameInfoOptions(movingFrame)
	local eligibleFrames = self:GetEligibleMagneticFrames(movingFrame)
	local horizontalInfo, verticalInfo
	local potentialHorizontalCorner, potentialVerticalCorner

	local frameLeft, frameRight, frameBottom, frameTop = self:GetFrameSides(movingFrame)
	local frameCenterX, frameCenterY = self:GetFrameCenter(movingFrame)

	-- Find closest horizontal (left/right) snap
	for _, frame in ipairs(eligibleFrames.horizontal) do
		local distance, point, relativePoint, offset

		if frame == UIParent then
			distance, point, relativePoint, offset = self:FindClosestGridLine(movingFrame, true)
		else
			local targetLeft, targetRight = self:GetFrameSides(frame)
			local targetCenterX = (targetLeft + targetRight) / 2

			-- Check all horizontal snap points: edge-to-edge and edge-to-center
			local snapOptions = {
				{ dist = math.abs(frameLeft - targetRight), pt = 'LEFT', relPt = 'RIGHT' }, -- Left edge to right edge
				{ dist = math.abs(frameRight - targetLeft), pt = 'RIGHT', relPt = 'LEFT' }, -- Right edge to left edge
				{ dist = math.abs(frameLeft - targetLeft), pt = 'LEFT', relPt = 'LEFT' }, -- Left edge to left edge
				{ dist = math.abs(frameRight - targetRight), pt = 'RIGHT', relPt = 'RIGHT' }, -- Right edge to right edge
				{ dist = math.abs(frameCenterX - targetCenterX), pt = 'CENTER', relPt = 'CENTER' }, -- Center to center
				{ dist = math.abs(frameLeft - targetCenterX), pt = 'LEFT', relPt = 'CENTER' }, -- Left edge to center
				{ dist = math.abs(frameRight - targetCenterX), pt = 'RIGHT', relPt = 'CENTER' }, -- Right edge to center
			}

			-- Find closest option
			local bestOption = snapOptions[1]
			for _, opt in ipairs(snapOptions) do
				if opt.dist < bestOption.dist then
					bestOption = opt
				end
			end

			distance = bestOption.dist
			point = bestOption.pt
			relativePoint = bestOption.relPt
			offset = 0
		end

		horizontalInfo = self:CheckReplaceMagneticFrameInfo(horizontalInfo, frame, point, relativePoint, distance, offset, true)

		-- Track potential corner frame
		if frame ~= UIParent then
			potentialHorizontalCorner = self:CheckReplaceMagneticFrameInfo(potentialHorizontalCorner, frame, point, relativePoint, distance, offset, true)
		end
	end

	-- Find closest vertical (top/bottom) snap
	for _, frame in ipairs(eligibleFrames.vertical) do
		local distance, point, relativePoint, offset

		if frame == UIParent then
			distance, point, relativePoint, offset = self:FindClosestGridLine(movingFrame, false)
		else
			local _, _, targetBottom, targetTop = self:GetFrameSides(frame)
			local targetCenterY = (targetTop + targetBottom) / 2

			-- Check all vertical snap points: edge-to-edge and edge-to-center
			local snapOptions = {
				{ dist = math.abs(frameTop - targetBottom), pt = 'TOP', relPt = 'BOTTOM' }, -- Top edge to bottom edge
				{ dist = math.abs(frameBottom - targetTop), pt = 'BOTTOM', relPt = 'TOP' }, -- Bottom edge to top edge
				{ dist = math.abs(frameTop - targetTop), pt = 'TOP', relPt = 'TOP' }, -- Top edge to top edge
				{ dist = math.abs(frameBottom - targetBottom), pt = 'BOTTOM', relPt = 'BOTTOM' }, -- Bottom edge to bottom edge
				{ dist = math.abs(frameCenterY - targetCenterY), pt = 'CENTER', relPt = 'CENTER' }, -- Center to center
				{ dist = math.abs(frameTop - targetCenterY), pt = 'TOP', relPt = 'CENTER' }, -- Top edge to center
				{ dist = math.abs(frameBottom - targetCenterY), pt = 'BOTTOM', relPt = 'CENTER' }, -- Bottom edge to center
			}

			-- Find closest option
			local bestOption = snapOptions[1]
			for _, opt in ipairs(snapOptions) do
				if opt.dist < bestOption.dist then
					bestOption = opt
				end
			end

			distance = bestOption.dist
			point = bestOption.pt
			relativePoint = bestOption.relPt
			offset = 0
		end

		verticalInfo = self:CheckReplaceMagneticFrameInfo(verticalInfo, frame, point, relativePoint, distance, offset, false)

		-- Track potential corner frame
		if frame ~= UIParent then
			potentialVerticalCorner = self:CheckReplaceMagneticFrameInfo(potentialVerticalCorner, frame, point, relativePoint, distance, offset, false)
		end
	end

	-- Check for corner snaps
	local horizontalCorner = self:GetCornerMagneticFrameInfo(movingFrame, potentialHorizontalCorner)
	local verticalCorner = self:GetCornerMagneticFrameInfo(movingFrame, potentialVerticalCorner)

	local cornerInfo
	if horizontalCorner and (not verticalCorner or horizontalCorner.distance < verticalCorner.distance) then
		cornerInfo = horizontalCorner
	elseif verticalCorner then
		cornerInfo = verticalCorner
	end

	return horizontalInfo, verticalInfo, cornerInfo
end

---Get the magnetic frame infos to snap to
---@param movingFrame Frame The frame being moved
---@return table|nil magneticFrameInfos
function MagnetismManager:GetMagneticFrameInfos(movingFrame)
	local horizontalInfo, verticalInfo, cornerInfo = self:GetMagneticFrameInfoOptions(movingFrame)

	-- Debug logging (rate limited to once per 0.5 seconds to reduce spam)
	if MoveIt.logger and self.debugLogging then
		if not self.lastSnapLogTime or (GetTime() - self.lastSnapLogTime) > 0.5 then
			self.lastSnapLogTime = GetTime()
			if horizontalInfo then
				local frameName = horizontalInfo.frame == UIParent and 'UIParent' or (horizontalInfo.frame.name or 'unknown')
				MoveIt.logger.debug(('H-snap: %s->%s on %s dist=%.1f'):format(horizontalInfo.point, horizontalInfo.relativePoint, frameName, horizontalInfo.distance))
			end
			if verticalInfo then
				local frameName = verticalInfo.frame == UIParent and 'UIParent' or (verticalInfo.frame.name or 'unknown')
				MoveIt.logger.debug(('V-snap: %s->%s on %s dist=%.1f'):format(verticalInfo.point, verticalInfo.relativePoint, frameName, verticalInfo.distance))
			end
			if cornerInfo then
				local frameName = cornerInfo.frame == UIParent and 'UIParent' or (cornerInfo.frame.name or 'unknown')
				MoveIt.logger.debug(('Corner-snap: %s->%s on %s dist=%.1f'):format(cornerInfo.point, cornerInfo.relativePoint, frameName, cornerInfo.distance))
			end
		end
	end

	if cornerInfo then
		-- Prioritize corner snaps (they already handle both axes)
		return { cornerInfo }
	elseif horizontalInfo and verticalInfo then
		-- Both axes have snaps - return both for dual-axis snapping
		-- This allows snapping to grid intersections and frame corners
		return { horizontalInfo, verticalInfo }
	elseif horizontalInfo then
		return { horizontalInfo }
	elseif verticalInfo then
		return { verticalInfo }
	end

	return nil
end

---Begin a drag session
---@param movingFrame Frame The frame being dragged
function MagnetismManager:BeginDragSession(movingFrame)
	self.currentDragFrame = movingFrame
	self.loggedChildSkip = nil -- Reset per-session logging flags
	self:UpdateUIParentPoints()
	self:UpdateGridLines() -- Refresh grid lines based on current EditMode settings

	if MoveIt.logger then
		local frameName = movingFrame.name or 'unknown'
		local moverScale = movingFrame:GetScale() or 1.0
		local moverEffectiveScale = movingFrame:GetEffectiveScale() or 1.0
		local parentScale = (movingFrame:GetParent() and movingFrame:GetParent():GetScale()) or 1.0

		-- Get source frame if available (for BT4 bars)
		local sourceFrame = movingFrame.frame
		local sourceScale = sourceFrame and sourceFrame:GetScale() or 'N/A'
		local sourceEffectiveScale = sourceFrame and sourceFrame:GetEffectiveScale() or 'N/A'

		MoveIt.logger.debug(('BeginDragSession: %s (grid=%s, spacing=%d)'):format(frameName, tostring(self.gridEnabled), self.gridSpacing or 0))
		MoveIt.logger.debug(('Mover scale=%.2f effectiveScale=%.2f parentScale=%.2f'):format(moverScale, moverEffectiveScale, parentScale))

		if sourceFrame then
			MoveIt.logger.debug(('Source frame scale=%s effectiveScale=%s'):format(tostring(sourceScale), tostring(sourceEffectiveScale)))
		end

		-- Log initial position
		local centerX, centerY = movingFrame:GetCenter()
		if centerX and centerY then
			MoveIt.logger.debug(('Starting position: center=(%.1f,%.1f)'):format(centerX, centerY))
		end
	end

	if self.previewLinesAvailable and self.previewLineContainer then
		self.previewLineContainer:Show()
	end
end

---Check for snaps during drag (called every frame during drag)
---@param movingFrame Frame The frame being dragged
---@return table|nil magneticFrameInfos
function MagnetismManager:CheckForSnaps(movingFrame)
	if not self.enabled then
		return nil
	end

	-- Shift key bypasses snapping (like ElvUI's LibSimpleSticky)
	if IsShiftKeyDown() then
		self:ClearSnapTargetHighlights()
		return nil
	end

	local result = self:GetMagneticFrameInfos(movingFrame)

	-- Update snap target highlights based on current snap candidates
	self:UpdateSnapTargetHighlights(result)

	-- Only log once per second to avoid spam
	if not self.lastLogTime or (GetTime() - self.lastLogTime) > 1 then
		self.lastLogTime = GetTime()
		if MoveIt.logger and self.debugLogging then
			if result then
				MoveIt.logger.debug(('CheckForSnaps: found %d snap(s)'):format(#result))
			end
		end
	end

	return result
end

---Update snap target frame highlights (flashing borders on potential snap targets)
---@param magneticFrameInfos table|nil Current snap info
function MagnetismManager:UpdateSnapTargetHighlights(magneticFrameInfos)
	-- Collect new snap targets (only frame-to-frame snaps, not UIParent/grid)
	-- AND only if frame snapping is actually enabled
	local newTargets = {}
	if magneticFrameInfos and self:IsElementSnapActive() then
		for _, info in ipairs(magneticFrameInfos) do
			if info.frame and info.frame ~= UIParent then
				newTargets[info.frame] = true
			end
		end
	end

	-- Remove highlights from frames no longer being targeted
	for frame, _ in pairs(self.currentSnapTargets) do
		if not newTargets[frame] then
			self:RemoveSnapTargetHighlight(frame)
		end
	end

	-- Add highlights to new target frames
	for frame, _ in pairs(newTargets) do
		if not self.currentSnapTargets[frame] then
			self:AddSnapTargetHighlight(frame)
		end
	end

	-- Update current targets
	self.currentSnapTargets = newTargets

	-- Start/stop flash animation based on whether we have targets
	if next(newTargets) then
		self:StartSnapTargetFlashAnimation()
	else
		self:StopSnapTargetFlashAnimation()
	end
end

---Add flashing highlight to a snap target frame
---@param frame Frame The frame to highlight
function MagnetismManager:AddSnapTargetHighlight(frame)
	if not frame then
		return
	end

	-- Store original backdrop color if not already stored (whole frame background)
	if not frame.originalSnapBackdropColor and frame.GetBackdropColor then
		local r, g, b, a = frame:GetBackdropColor()
		frame.originalSnapBackdropColor = { r, g, b, a }
	end

	-- Store original border color if not already stored
	if not frame.originalSnapBorderColor and frame.GetBackdropBorderColor then
		local r, g, b, a = frame:GetBackdropBorderColor()
		frame.originalSnapBorderColor = { r, g, b, a }
	end

	-- Apply initial flash color to whole frame background
	if frame.SetBackdropColor then
		frame:SetBackdropColor(unpack(self.SNAP_TARGET_COLORS.flash1))
	end
	if frame.SetBackdropBorderColor then
		frame:SetBackdropBorderColor(unpack(self.SNAP_TARGET_COLORS.flash1))
	end
end

---Remove flashing highlight from a snap target frame
---@param frame Frame The frame to unhighlight
function MagnetismManager:RemoveSnapTargetHighlight(frame)
	if not frame then
		return
	end

	-- Restore original backdrop color (whole frame background)
	if frame.originalSnapBackdropColor and frame.SetBackdropColor then
		frame:SetBackdropColor(unpack(frame.originalSnapBackdropColor))
	end
	frame.originalSnapBackdropColor = nil

	-- Restore original border color
	if frame.originalSnapBorderColor and frame.SetBackdropBorderColor then
		frame:SetBackdropBorderColor(unpack(frame.originalSnapBorderColor))
	end
	frame.originalSnapBorderColor = nil
end

---Start the flash animation for snap target highlights
function MagnetismManager:StartSnapTargetFlashAnimation()
	if self.snapTargetFlashFrame and self.snapTargetFlashFrame.animating then
		return -- Already animating
	end

	if not self.snapTargetFlashFrame then
		self.snapTargetFlashFrame = CreateFrame('Frame')
	end

	self.snapTargetFlashElapsed = 0
	self.snapTargetFlashState = false
	self.snapTargetFlashFrame.animating = true

	self.snapTargetFlashFrame:SetScript('OnUpdate', function(_, delta)
		self.snapTargetFlashElapsed = self.snapTargetFlashElapsed + delta
		if self.snapTargetFlashElapsed >= self.snapTargetFlashInterval then
			self.snapTargetFlashElapsed = 0
			self.snapTargetFlashState = not self.snapTargetFlashState

			-- Apply flash color to all current snap targets (whole frame background + border)
			local color = self.snapTargetFlashState and self.SNAP_TARGET_COLORS.flash2 or self.SNAP_TARGET_COLORS.flash1
			for frame, _ in pairs(self.currentSnapTargets) do
				if frame then
					if frame.SetBackdropColor then
						frame:SetBackdropColor(unpack(color))
					end
					if frame.SetBackdropBorderColor then
						frame:SetBackdropBorderColor(unpack(color))
					end
				end
			end
		end
	end)
end

---Stop the flash animation for snap target highlights
function MagnetismManager:StopSnapTargetFlashAnimation()
	if self.snapTargetFlashFrame then
		self.snapTargetFlashFrame:SetScript('OnUpdate', nil)
		self.snapTargetFlashFrame.animating = false
	end
end

---Clear all snap target highlights
function MagnetismManager:ClearSnapTargetHighlights()
	for frame, _ in pairs(self.currentSnapTargets) do
		self:RemoveSnapTargetHighlight(frame)
	end
	self.currentSnapTargets = {}
	self:StopSnapTargetFlashAnimation()
end

---Show preview lines for snap targets
---@param magneticFrameInfos table|nil The snap info
function MagnetismManager:ShowPreviewLines(magneticFrameInfos)
	if not self.previewLinesAvailable or not self.previewLinePool then
		return
	end

	-- Release all existing lines
	self.previewLinePool:ReleaseAll()

	if not magneticFrameInfos then
		return
	end

	local linesShown = 0
	for _, info in ipairs(magneticFrameInfos) do
		-- Determine if this is a grid snap vs frame snap
		local isGridSnap = info.frame == UIParent and info.offset and info.offset ~= 0
		local isUIParentEdgeSnap = info.frame == UIParent and (not info.offset or info.offset == 0)

		local anchors = self:GetPreviewLineAnchors(info)
		for _, anchor in ipairs(anchors) do
			local line = self.previewLinePool:Acquire()
			self:SetupPreviewLine(line, info, anchor)

			-- Color the line differently based on snap type
			if isGridSnap then
				-- Grid snap: bright gold color
				line:SetColorTexture(1, 0.82, 0, 0.9)
			elseif isUIParentEdgeSnap then
				-- UIParent edge snap: gold color
				line:SetColorTexture(1, 0.82, 0, 0.8)
			else
				-- Frame-to-frame snap: cyan color to distinguish from grid
				line:SetColorTexture(0, 0.8, 1, 0.8)
			end

			line:Show()
			linesShown = linesShown + 1
		end
	end

	-- Debug: Log only once per second to avoid spam
	if MoveIt.logger and self.debugLogging and linesShown > 0 then
		if not self.lastPreviewLogTime or (GetTime() - self.lastPreviewLogTime) > 1 then
			self.lastPreviewLogTime = GetTime()
			MoveIt.logger.debug(('ShowPreviewLines: showing %d line(s)'):format(linesShown))
		end
	end
end

---Get preview line anchors for a magnetic frame info
---@param magneticFrameInfo table The snap info
---@return table anchors
function MagnetismManager:GetPreviewLineAnchors(magneticFrameInfo)
	local relativePoint = magneticFrameInfo.relativePoint
	local anchors = {}

	if relativePoint:find('CENTER') then
		if magneticFrameInfo.isHorizontal then
			table.insert(anchors, 'CenterVertical')
		else
			table.insert(anchors, 'CenterHorizontal')
		end
	else
		if relativePoint:find('TOP') then
			table.insert(anchors, 'Top')
		end
		if relativePoint:find('BOTTOM') then
			table.insert(anchors, 'Bottom')
		end
		if relativePoint:find('LEFT') then
			table.insert(anchors, 'Left')
		end
		if relativePoint:find('RIGHT') then
			table.insert(anchors, 'Right')
		end
	end

	-- Debug: Log what anchors are being returned for preview lines (rate-limited)
	if MoveIt.logger and self.debugLogging and #anchors > 0 then
		if not self.lastAnchorLogTime or (GetTime() - self.lastAnchorLogTime) > 0.5 then
			self.lastAnchorLogTime = GetTime()
			local frameName = magneticFrameInfo.frame == UIParent and 'UIParent' or (magneticFrameInfo.frame.name or magneticFrameInfo.frame:GetName() or 'unknown')
			MoveIt.logger.debug(('PreviewLine anchors for %s relPt=%s: %s'):format(frameName, relativePoint, table.concat(anchors, ', ')))
		end
	end

	return anchors
end

---Setup a preview line using WeakAuras-style approach
---@param line Line The line to setup
---@param info table The magnetic frame info
---@param anchor string The anchor type
function MagnetismManager:SetupPreviewLine(line, info, anchor)
	local frame = info.frame

	-- Calculate the actual screen position for the line
	local linePos -- The X position for vertical lines, Y position for horizontal lines
	local isVertical = false

	-- Handle all UIParent snaps (grid lines and edges/center)
	if frame == UIParent then
		local gridOffset = info.offset or 0

		if anchor == 'CenterVertical' or anchor == 'Left' or anchor == 'Right' then
			isVertical = true
			if anchor == 'CenterVertical' then
				linePos = self.uiParentCenterX + gridOffset
			elseif anchor == 'Left' then
				linePos = self.uiParentLeft
			elseif anchor == 'Right' then
				linePos = self.uiParentRight
			end
		else
			isVertical = false
			if anchor == 'CenterHorizontal' then
				linePos = self.uiParentCenterY + gridOffset
			elseif anchor == 'Top' then
				linePos = self.uiParentTop
			elseif anchor == 'Bottom' then
				linePos = self.uiParentBottom
			end
		end
	else
		-- Standard frame snap
		if not frame then
			return
		end

		local left, right, bottom, top = self:GetFrameSides(frame)
		local centerX, centerY = self:GetFrameCenter(frame)

		if anchor == 'CenterVertical' then
			isVertical = true
			linePos = centerX
		elseif anchor == 'CenterHorizontal' then
			isVertical = false
			linePos = centerY
		elseif anchor == 'Top' then
			isVertical = false
			linePos = top
		elseif anchor == 'Bottom' then
			isVertical = false
			linePos = bottom
		elseif anchor == 'Left' then
			isVertical = true
			linePos = left
		elseif anchor == 'Right' then
			isVertical = true
			linePos = right
		end
	end

	if not linePos then
		return
	end

	-- Position the line using WeakAuras-style anchoring
	-- WeakAuras pattern: SetStartPoint("TOPLEFT", UIParent, xOffset, yOffset)
	-- Note: WeakAuras passes X offset directly as 3rd parameter for vertical lines
	if isVertical then
		-- Vertical line: from top to bottom at X position
		-- The X position is relative to UIParent's left edge (screen coordinates)
		line:SetStartPoint('TOPLEFT', UIParent, linePos, 0)
		line:SetEndPoint('BOTTOMLEFT', UIParent, linePos, 0)
	else
		-- Horizontal line: from left to right at Y position
		-- The Y position is relative to UIParent's bottom edge (screen coordinates)
		line:SetStartPoint('BOTTOMLEFT', UIParent, 0, linePos)
		line:SetEndPoint('BOTTOMRIGHT', UIParent, 0, linePos)
	end
end

---Hide all preview lines
function MagnetismManager:HidePreviewLines()
	if self.previewLinesAvailable and self.previewLinePool then
		self.previewLinePool:ReleaseAll()
	end
end

---Calculate snap deltas for a frame at a hypothetical center position (used during manual drag OnUpdate)
---@param movingFrame Frame The frame being moved
---@param centerX number Hypothetical center X position
---@param centerY number Hypothetical center Y position
---@param snapInfos table Array of magnetic frame infos from CheckForSnaps
---@return number deltaX, number deltaY Total snap adjustment to apply
function MagnetismManager:GetSnapDeltas(movingFrame, centerX, centerY, snapInfos)
	if not snapInfos or #snapInfos == 0 then
		return 0, 0
	end

	local width, height = movingFrame:GetSize()
	local halfW = width / 2
	local halfH = height / 2

	-- Calculate hypothetical edges from center position
	local movingLeft = centerX - halfW
	local movingRight = centerX + halfW
	local movingTop = centerY + halfH
	local movingBottom = centerY - halfH

	local totalDeltaX, totalDeltaY = 0, 0

	for _, info in ipairs(snapInfos) do
		if not info or not info.frame then
			-- skip
		elseif info.isCornerSnap then
			-- Corner snap - match specific corners
			local movingPoint = self:GetCornerPosition(movingLeft, movingRight, movingBottom, movingTop, info.point)

			local targetLeft, targetRight, targetBottom, targetTop = self:GetFrameSides(info.frame)
			targetLeft = math.floor(targetLeft + 0.5)
			targetRight = math.floor(targetRight + 0.5)
			targetBottom = math.floor(targetBottom + 0.5)
			targetTop = math.floor(targetTop + 0.5)
			local targetPoint = self:GetCornerPosition(targetLeft, targetRight, targetBottom, targetTop, info.relativePoint)

			totalDeltaX = targetPoint.x - movingPoint.x
			totalDeltaY = targetPoint.y - movingPoint.y
		elseif info.isHorizontal then
			-- Horizontal snap (X axis)
			local gridOffset = info.offset or 0

			local targetEdgeX
			if info.frame == UIParent then
				targetEdgeX = self.uiParentCenterX + gridOffset
			else
				local targetLeft, targetRight = self:GetFrameSides(info.frame)
				targetLeft = math.floor(targetLeft + 0.5)
				targetRight = math.floor(targetRight + 0.5)
				local targetCenterX = (targetLeft + targetRight) / 2

				if info.relativePoint == 'LEFT' then
					targetEdgeX = targetLeft
				elseif info.relativePoint == 'RIGHT' then
					targetEdgeX = targetRight
				else
					targetEdgeX = targetCenterX + gridOffset
				end
			end

			local movingEdgeX
			if info.point == 'LEFT' then
				movingEdgeX = movingLeft
			elseif info.point == 'RIGHT' then
				movingEdgeX = movingRight
			else
				movingEdgeX = centerX
			end

			totalDeltaX = targetEdgeX - movingEdgeX
		else
			-- Vertical snap (Y axis)
			local gridOffset = info.offset or 0

			local targetEdgeY
			if info.frame == UIParent then
				targetEdgeY = self.uiParentCenterY + gridOffset
			else
				local _, _, targetBottom, targetTop = self:GetFrameSides(info.frame)
				targetBottom = math.floor(targetBottom + 0.5)
				targetTop = math.floor(targetTop + 0.5)
				local targetCenterY = (targetBottom + targetTop) / 2

				if info.relativePoint == 'TOP' then
					targetEdgeY = targetTop
				elseif info.relativePoint == 'BOTTOM' then
					targetEdgeY = targetBottom
				else
					targetEdgeY = targetCenterY + gridOffset
				end
			end

			local movingEdgeY
			if info.point == 'TOP' then
				movingEdgeY = movingTop
			elseif info.point == 'BOTTOM' then
				movingEdgeY = movingBottom
			else
				movingEdgeY = centerY
			end

			totalDeltaY = targetEdgeY - movingEdgeY
		end
	end

	return totalDeltaX, totalDeltaY
end

---Apply final snap and end drag session
---@param movingFrame Frame The frame that was being dragged
---Apply final snap and return whether frame was attached to another frame
---@param movingFrame Frame The frame being moved
---@return boolean wasAttachedToFrame True if frame was anchored to another frame (not UIParent)
function MagnetismManager:ApplyFinalSnap(movingFrame)
	if not self.enabled then
		if MoveIt.logger then
			MoveIt.logger.debug('ApplyFinalSnap: magnetism disabled')
		end
		return false
	end

	-- Shift key bypasses snapping (like ElvUI's LibSimpleSticky)
	if IsShiftKeyDown() then
		if MoveIt.logger then
			MoveIt.logger.debug('ApplyFinalSnap: shift key held, skipping snap')
		end
		return false
	end

	local wasAttachedToFrame = false
	local magneticFrameInfos = self:GetMagneticFrameInfos(movingFrame)
	if magneticFrameInfos then
		if MoveIt.logger then
			MoveIt.logger.debug(('ApplyFinalSnap: applying %d snap(s)'):format(#magneticFrameInfos))
		end
		for _, info in ipairs(magneticFrameInfos) do
			local attached = self:SnapFrameToInfo(movingFrame, info)
			if attached then
				wasAttachedToFrame = true
				-- Stop processing remaining snaps once attached to a frame
				-- This prevents grid snaps from overwriting frame-to-frame anchors
				break
			end
		end
	else
		if MoveIt.logger then
			MoveIt.logger.debug('ApplyFinalSnap: no snaps to apply')
		end
	end

	return wasAttachedToFrame
end

---Snap a frame to a magnetic frame info
---@param movingFrame Frame The frame to snap
---@param info table The magnetic frame info
---@return boolean wasAttachedToFrame True if frame was anchored to another frame (not UIParent)
function MagnetismManager:SnapFrameToInfo(movingFrame, info)
	if not movingFrame or not info or not info.frame then
		if MoveIt.logger then
			MoveIt.logger.debug('SnapFrameToInfo: nil check failed')
		end
		return false
	end

	-- Get current position and calculate snap offset
	local currentPos = MoveIt.PositionCalculator:GetRelativePosition(movingFrame)
	if not currentPos then
		if MoveIt.logger then
			MoveIt.logger.debug('SnapFrameToInfo: no current position')
		end
		return false
	end

	if MoveIt.logger then
		MoveIt.logger.debug(('SnapFrameToInfo: isHorizontal=%s, isCorner=%s, point=%s, relPt=%s'):format(tostring(info.isHorizontal), tostring(info.isCornerSnap), info.point, info.relativePoint))
	end

	-- Calculate the offset adjustment needed for the snap
	local movingLeft, movingRight, movingBottom, movingTop = self:GetFrameSides(movingFrame)
	local movingCenterX, movingCenterY = self:GetFrameCenter(movingFrame)

	local targetLeft, targetRight, targetBottom, targetTop = self:GetFrameSides(info.frame)
	local targetCenterX, targetCenterY = self:GetFrameCenter(info.frame)

	-- Round target coordinates to nearest pixel to ensure pixel-perfect alignment
	-- This prevents gaps when the target frame is at a fractional position
	targetLeft = math.floor(targetLeft + 0.5)
	targetRight = math.floor(targetRight + 0.5)
	targetBottom = math.floor(targetBottom + 0.5)
	targetTop = math.floor(targetTop + 0.5)
	targetCenterX = math.floor(targetCenterX + 0.5)
	targetCenterY = math.floor(targetCenterY + 0.5)

	local deltaX, deltaY = 0, 0

	-- Calculate delta based on snap points
	-- For grid snaps, info.offset contains the distance from UIParent CENTER to the grid line
	local gridOffset = info.offset or 0

	if info.isCornerSnap then
		-- Corner snap - match the specific corners
		local movingPoint = self:GetCornerPosition(movingLeft, movingRight, movingBottom, movingTop, info.point)
		local targetPoint = self:GetCornerPosition(targetLeft, targetRight, targetBottom, targetTop, info.relativePoint)
		deltaX = targetPoint.x - movingPoint.x
		deltaY = targetPoint.y - movingPoint.y

		if MoveIt.logger then
			MoveIt.logger.debug(('Corner snap coords: moving %s=(%.1f,%.1f) target %s=(%.1f,%.1f)'):format(info.point, movingPoint.x, movingPoint.y, info.relativePoint, targetPoint.x, targetPoint.y))
		end
	elseif info.isHorizontal then
		-- Horizontal snap (left/right alignment)
		-- For grid snaps to UIParent CENTER, we need to add the grid offset
		local effectiveTargetX = targetCenterX + gridOffset

		if info.point == 'LEFT' then
			if info.relativePoint == 'RIGHT' then
				deltaX = targetRight - movingLeft
				if MoveIt.logger then
					MoveIt.logger.debug(('H-snap LEFT->RIGHT: movingLeft=%.2f targetRight=%.2f delta=%.2f'):format(movingLeft, targetRight, deltaX))
				end
			elseif info.relativePoint == 'LEFT' then
				deltaX = targetLeft - movingLeft
			elseif info.relativePoint == 'CENTER' then
				-- For grid snaps, effectiveTargetX is the grid line position
				deltaX = effectiveTargetX - movingLeft
				if MoveIt.logger and gridOffset ~= 0 then
					MoveIt.logger.debug(('H-snap LEFT->CENTER (grid): movingLeft=%.2f gridLine=%.2f (center+%.0f) delta=%.2f'):format(movingLeft, effectiveTargetX, gridOffset, deltaX))
				end
			end
		elseif info.point == 'RIGHT' then
			if info.relativePoint == 'LEFT' then
				deltaX = targetLeft - movingRight
				if MoveIt.logger then
					MoveIt.logger.debug(('H-snap RIGHT->LEFT: movingRight=%.2f targetLeft=%.2f delta=%.2f'):format(movingRight, targetLeft, deltaX))
				end
			elseif info.relativePoint == 'RIGHT' then
				deltaX = targetRight - movingRight
			elseif info.relativePoint == 'CENTER' then
				-- For grid snaps, effectiveTargetX is the grid line position
				deltaX = effectiveTargetX - movingRight
				if MoveIt.logger and gridOffset ~= 0 then
					MoveIt.logger.debug(('H-snap RIGHT->CENTER (grid): movingRight=%.2f gridLine=%.2f (center+%.0f) delta=%.2f'):format(movingRight, effectiveTargetX, gridOffset, deltaX))
				end
			end
		elseif info.point == 'CENTER' then
			-- For grid snaps, effectiveTargetX is the grid line position
			deltaX = effectiveTargetX - movingCenterX
			if MoveIt.logger and gridOffset ~= 0 then
				MoveIt.logger.debug(('H-snap CENTER->CENTER (grid): movingCenterX=%.2f gridLine=%.2f (center+%.0f) delta=%.2f'):format(movingCenterX, effectiveTargetX, gridOffset, deltaX))
			end
		end
	else
		-- Vertical snap (top/bottom alignment)
		-- For grid snaps to UIParent CENTER, we need to add the grid offset
		local effectiveTargetY = targetCenterY + gridOffset

		if info.point == 'TOP' then
			if info.relativePoint == 'BOTTOM' then
				deltaY = targetBottom - movingTop
			elseif info.relativePoint == 'TOP' then
				deltaY = targetTop - movingTop
			elseif info.relativePoint == 'CENTER' then
				-- For grid snaps, effectiveTargetY is the grid line position
				deltaY = effectiveTargetY - movingTop
				if MoveIt.logger and gridOffset ~= 0 then
					MoveIt.logger.debug(('V-snap TOP->CENTER (grid): movingTop=%.2f gridLine=%.2f (center+%.0f) delta=%.2f'):format(movingTop, effectiveTargetY, gridOffset, deltaY))
				end
			end
		elseif info.point == 'BOTTOM' then
			if info.relativePoint == 'TOP' then
				deltaY = targetTop - movingBottom
			elseif info.relativePoint == 'BOTTOM' then
				deltaY = targetBottom - movingBottom
			elseif info.relativePoint == 'CENTER' then
				-- For grid snaps, effectiveTargetY is the grid line position
				deltaY = effectiveTargetY - movingBottom
				if MoveIt.logger and gridOffset ~= 0 then
					MoveIt.logger.debug(('V-snap BOTTOM->CENTER (grid): movingBottom=%.2f gridLine=%.2f (center+%.0f) delta=%.2f'):format(movingBottom, effectiveTargetY, gridOffset, deltaY))
				end
			end
		elseif info.point == 'CENTER' then
			-- For grid snaps, effectiveTargetY is the grid line position
			deltaY = effectiveTargetY - movingCenterY
			if MoveIt.logger and gridOffset ~= 0 then
				MoveIt.logger.debug(('V-snap CENTER->CENTER (grid): movingCenterY=%.2f gridLine=%.2f (center+%.0f) delta=%.2f'):format(movingCenterY, effectiveTargetY, gridOffset, deltaY))
			end
		end
	end

	-- Frame attachment: When snapping to another mover (not UIParent), anchor to it
	-- so that the moving frame follows when the target frame moves
	local isFrameToFrameSnap = info.frame ~= UIParent and info.frame ~= nil
	local targetFrameName = info.frame and (info.frame:GetName() or info.frame.name)

	-- Enable attachment for edge-to-edge and corner snaps to other movers
	-- Edge-to-edge snaps: LEFT->RIGHT, RIGHT->LEFT, TOP->BOTTOM, BOTTOM->TOP
	local isEdgeToEdgeSnap = (info.point == 'LEFT' and info.relativePoint == 'RIGHT')
		or (info.point == 'RIGHT' and info.relativePoint == 'LEFT')
		or (info.point == 'TOP' and info.relativePoint == 'BOTTOM')
		or (info.point == 'BOTTOM' and info.relativePoint == 'TOP')

	local shouldAttach = isFrameToFrameSnap and (isEdgeToEdgeSnap or info.isCornerSnap)

	if shouldAttach then
		-- ATTACHMENT MODE: Anchor the moving frame directly to the target frame
		-- This makes the moving frame move with the target frame (linked movement)
		if MoveIt.logger then
			MoveIt.logger.debug(('SnapFrameToInfo: ATTACHING %s to %s at %s->%s'):format(movingFrame.name or 'unknown', targetFrameName, info.point, info.relativePoint))
		end

		-- For edge-to-edge snaps, we need to calculate the proper anchor point
		-- The moving frame's anchor point should be set to the snap point (info.point)
		-- The relative point on target frame is info.relativePoint
		-- Offset should be 0 for perfect edge alignment

		-- For corner snaps, both axes are determined by the corner points
		-- For edge snaps (horizontal or vertical), we need to preserve the OTHER axis position

		local offsetX, offsetY = 0, 0

		if not info.isCornerSnap then
			-- For edge snaps, we need to maintain the offset on the non-snapped axis
			-- Calculate the current offset between the frames on the non-snapped axis
			if info.isHorizontal then
				-- Horizontal snap (LEFT<->RIGHT) - need to preserve Y offset
				-- Calculate Y offset from target frame's relativePoint Y to moving frame's point Y
				local movingPointY = self:GetPointY(movingFrame, info.point)
				local targetRelPointY = self:GetPointY(info.frame, info.relativePoint)
				offsetY = math.floor(movingPointY - targetRelPointY + 0.5)
			else
				-- Vertical snap (TOP<->BOTTOM) - need to preserve X offset
				local movingPointX = self:GetPointX(movingFrame, info.point)
				local targetRelPointX = self:GetPointX(info.frame, info.relativePoint)
				offsetX = math.floor(movingPointX - targetRelPointX + 0.5)
			end
		end

		-- Create the new position anchored to the target frame
		local newPos = {
			point = info.point,
			anchorFrame = info.frame,
			anchorFrameName = targetFrameName,
			anchorPoint = info.relativePoint,
			x = offsetX,
			y = offsetY,
		}

		MoveIt.PositionCalculator:SetRelativePosition(movingFrame, newPos)

		if MoveIt.logger then
			MoveIt.logger.debug(('SnapFrameToInfo: attached with anchor %s,%s,%s,%.0f,%.0f'):format(info.point, targetFrameName, info.relativePoint, offsetX, offsetY))
		end

		-- Fire callback for attachment if it exists
		if MoveIt.Callbacks and MoveIt.Callbacks.OnFrameAttached then
			MoveIt.Callbacks.OnFrameAttached(movingFrame, info.frame, info.point, info.relativePoint)
		end

		if MoveIt.logger then
			-- Verify the position was actually set
			local verifyPos = MoveIt.PositionCalculator:GetRelativePosition(movingFrame)
			if verifyPos then
				MoveIt.logger.debug(('SnapFrameToInfo: verified anchor=%s pos=%.1f,%.1f'):format(verifyPos.anchorFrameName or 'UIParent', verifyPos.x, verifyPos.y))
			end
		end

		return true -- Frame was attached to another frame
	else
		-- POSITIONING MODE: Just move the frame to align with grid/UIParent
		-- Calculate new CENTER position for the frame
		local centerX, centerY = self:GetFrameCenter(movingFrame)

		-- Apply the delta to get the snapped center position
		local newCenterX = centerX + deltaX
		local newCenterY = centerY + deltaY

		-- Calculate offset from UIParent center
		local uiCenterX, uiCenterY = UIParent:GetCenter()
		local offsetX = math.floor(newCenterX - uiCenterX + 0.5)
		local offsetY = math.floor(newCenterY - uiCenterY + 0.5)

		-- Set position using CENTER anchor for consistency
		movingFrame:ClearAllPoints()
		movingFrame:SetPoint('CENTER', UIParent, 'CENTER', offsetX, offsetY)

		if MoveIt.logger then
			MoveIt.logger.debug(('SnapFrameToInfo: grid snap delta=%.1f,%.1f newCenter=%.1f,%.1f offset=%.0f,%.0f'):format(deltaX, deltaY, newCenterX, newCenterY, offsetX, offsetY))
		end

		return false -- Frame snapped to grid, not attached to another frame
	end
end

---Get corner position coordinates
---@param left number Left edge
---@param right number Right edge
---@param bottom number Bottom edge
---@param top number Top edge
---@param corner string Corner name (TOPLEFT, TOPRIGHT, BOTTOMLEFT, BOTTOMRIGHT)
---@return table {x, y}
function MagnetismManager:GetCornerPosition(left, right, bottom, top, corner)
	if corner == 'TOPLEFT' then
		return { x = left, y = top }
	elseif corner == 'TOPRIGHT' then
		return { x = right, y = top }
	elseif corner == 'BOTTOMLEFT' then
		return { x = left, y = bottom }
	elseif corner == 'BOTTOMRIGHT' then
		return { x = right, y = bottom }
	else
		-- CENTER or unknown
		return { x = (left + right) / 2, y = (top + bottom) / 2 }
	end
end

---Get the X coordinate for a specific anchor point on a frame
---@param frame Frame The frame
---@param point string The anchor point (LEFT, RIGHT, CENTER, TOPLEFT, etc.)
---@return number x The X coordinate
function MagnetismManager:GetPointX(frame, point)
	local left, right = self:GetFrameSides(frame)
	if point:find('LEFT') then
		return left
	elseif point:find('RIGHT') then
		return right
	else
		return (left + right) / 2
	end
end

---Get the Y coordinate for a specific anchor point on a frame
---@param frame Frame The frame
---@param point string The anchor point (TOP, BOTTOM, CENTER, TOPLEFT, etc.)
---@return number y The Y coordinate
function MagnetismManager:GetPointY(frame, point)
	local _, _, bottom, top = self:GetFrameSides(frame)
	if point:find('TOP') then
		return top
	elseif point:find('BOTTOM') then
		return bottom
	else
		return (top + bottom) / 2
	end
end

---End the drag session
function MagnetismManager:EndDragSession()
	self:HidePreviewLines()
	self:ClearSnapTargetHighlights()
	self.currentDragFrame = nil

	if self.previewLineContainer then
		self.previewLineContainer:Hide()
	end
end

-- Initialize preview lines on load (delayed to ensure UIParent exists)
C_Timer.After(0.1, function()
	MagnetismManager:InitializePreviewLines()
	MagnetismManager:UpdateUIParentPoints()
end)

if MoveIt.logger then
	MoveIt.logger.info('Magnetism Manager loaded')
end
