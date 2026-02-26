---@class SUI
local SUI = SUI
local MoveIt = SUI.MoveIt

---@class SUI.MoveIt.PositionCalculator
local PositionCalculator = {}
MoveIt.PositionCalculator = PositionCalculator

---Get a frame's relative position (respects original anchoring)
---@param mover Frame The mover frame
---@return table position {point, anchorFrame, anchorPoint, x, y}
function PositionCalculator:GetRelativePosition(mover)
	if not mover then
		return nil
	end

	-- Get the mover's current anchor
	local numPoints = mover:GetNumPoints()
	if numPoints == 0 then
		return nil
	end

	local point, relativeTo, relativePoint, offsetX, offsetY = mover:GetPoint(1)

	-- Convert anchor frame name to frame object if it's a string
	local anchorFrame = relativeTo
	if type(relativeTo) == 'string' then
		anchorFrame = _G[relativeTo]
	end

	return {
		point = point,
		anchorFrame = anchorFrame or UIParent,
		anchorFrameName = (type(relativeTo) == 'string' and relativeTo) or (anchorFrame and anchorFrame:GetName()) or 'UIParent',
		anchorPoint = relativePoint or point,
		x = offsetX or 0,
		y = offsetY or 0,
	}
end

---Set a frame's relative position (preserves anchoring structure)
---@param mover Frame The mover frame
---@param position table {point, anchorFrame, anchorPoint, x, y}
function PositionCalculator:SetRelativePosition(mover, position)
	if not mover or not position then
		return
	end

	local anchorFrame = position.anchorFrame
	if type(anchorFrame) == 'string' then
		anchorFrame = _G[anchorFrame] or UIParent
	end
	anchorFrame = anchorFrame or UIParent

	mover:ClearAllPoints()
	mover:SetPoint(position.point or 'CENTER', anchorFrame, position.anchorPoint or position.point or 'CENTER', position.x or 0, position.y or 0)
end

---Calculate position during drag (keeps relative to original anchor)
---@param mover Frame The mover being dragged
---@param cursorX number Cursor X position
---@param cursorY number Cursor Y position
---@return table position {point, anchorFrame, anchorPoint, x, y}
function PositionCalculator:CalculateDragPosition(mover, cursorX, cursorY)
	-- Get the mover's original anchor info
	local currentPos = self:GetRelativePosition(mover)
	if not currentPos then
		return nil
	end

	local point = currentPos.point
	local anchorFrame = currentPos.anchorFrame
	local anchorPoint = currentPos.anchorPoint

	-- Calculate the anchor frame's anchor point position in screen coordinates
	local anchorX, anchorY = self:GetAnchorPointPosition(anchorFrame, anchorPoint)

	if MoveIt.logger then
		local moverName = mover:GetName() or 'UnknownMover'
		MoveIt.logger.debug(('CalculateDragPosition: mover=%s cursor=(%.1f,%.1f) anchor=%s at (%.1f,%.1f)'):format(moverName, cursorX, cursorY, anchorPoint, anchorX, anchorY))
	end

	-- Calculate offset from that anchor point
	local offsetX = cursorX - anchorX
	local offsetY = cursorY - anchorY

	if MoveIt.logger then
		MoveIt.logger.debug(('Initial delta: dx=%.1f, dy=%.1f'):format(offsetX, offsetY))
	end

	-- Adjust offset based on which corner of the mover we're anchoring from
	-- This ensures the mover appears where the cursor is
	local moverWidth, moverHeight = mover:GetSize()

	if point:find('LEFT') then
		-- Anchoring from left side, no adjustment needed
	elseif point:find('RIGHT') then
		offsetX = offsetX - moverWidth
	else
		-- Center
		offsetX = offsetX - (moverWidth / 2)
	end

	if point:find('TOP') then
		offsetY = offsetY - moverHeight
	elseif point:find('BOTTOM') then
		-- Anchoring from bottom, no adjustment needed
	else
		-- Center
		offsetY = offsetY - (moverHeight / 2)
	end

	if MoveIt.logger then
		MoveIt.logger.debug(('Selected anchor: %s (mover size=%.1fx%.1f)'):format(point, moverWidth, moverHeight))
		MoveIt.logger.debug(('Final offset: x=%.1f, y=%.1f'):format(offsetX, offsetY))
	end

	return {
		point = point,
		anchorFrame = anchorFrame,
		anchorFrameName = currentPos.anchorFrameName,
		anchorPoint = anchorPoint,
		x = offsetX,
		y = offsetY,
	}
end

---Get the screen position of an anchor point on a frame
---@param frame Frame The frame
---@param anchorPoint string The anchor point (e.g., "TOPLEFT", "CENTER")
---@return number x, number y Screen coordinates
function PositionCalculator:GetAnchorPointPosition(frame, anchorPoint)
	if not frame then
		frame = UIParent
	end

	local left = frame:GetLeft() or 0
	local right = frame:GetRight() or 0
	local top = frame:GetTop() or 0
	local bottom = frame:GetBottom() or 0

	-- Log raw coordinates for debugging scale issues
	if MoveIt.logger then
		local frameName = frame:GetName() or 'UnknownFrame'
		local frameScale = frame:GetScale() or 1.0
		local frameEffectiveScale = frame:GetEffectiveScale() or 1.0
		local parentScale = (frame:GetParent() and frame:GetParent():GetScale()) or 1.0

		MoveIt.logger.debug(
			('GetAnchorPointPosition: frame=%s anchorPoint=%s scale=%.2f effectiveScale=%.2f parentScale=%.2f'):format(frameName, anchorPoint, frameScale, frameEffectiveScale, parentScale)
		)
		MoveIt.logger.debug(('Raw coords: left=%.1f right=%.1f top=%.1f bottom=%.1f'):format(left, right, top, bottom))
	end

	local x, y

	-- Calculate X coordinate based on anchor point
	if anchorPoint:find('LEFT') then
		x = left
	elseif anchorPoint:find('RIGHT') then
		x = right
	else
		x = (left + right) / 2
	end

	-- Calculate Y coordinate based on anchor point
	if anchorPoint:find('TOP') then
		y = top
	elseif anchorPoint:find('BOTTOM') then
		y = bottom
	else
		y = (top + bottom) / 2
	end

	if MoveIt.logger then
		MoveIt.logger.debug(('Anchor %s calculated: x=%.1f, y=%.1f (unscaled)'):format(anchorPoint, x, y))
	end

	return x, y
end

---Round a number to specified decimal places
---@param num number The number to round
---@param decimals? number Number of decimal places (default 1)
---@return number
function PositionCalculator:Round(num, decimals)
	decimals = decimals or 1
	local mult = 10 ^ decimals
	return math.floor(num * mult + 0.5) / mult
end

---Calculate CENTER anchor offset for a frame relative to UIParent
---Accounts for scale differences between frame and UIParent
---@param frame Frame The frame to calculate position for
---@return number|nil offsetX X offset from UIParent CENTER
---@return number|nil offsetY Y offset from UIParent CENTER
function PositionCalculator:GetCenterOffset(frame)
	if not frame then
		return nil, nil
	end

	local centerX, centerY = frame:GetCenter()
	if not centerX or not centerY then
		return nil, nil
	end

	-- Account for scale differences between frame and UIParent
	local frameScale = frame:GetEffectiveScale()
	local uiScale = UIParent:GetEffectiveScale()

	-- Convert frame center to screen coordinates
	local screenCenterX = centerX * frameScale
	local screenCenterY = centerY * frameScale

	-- Get UIParent center in screen coordinates
	local uiCenterX, uiCenterY = UIParent:GetCenter()
	uiCenterX = uiCenterX * uiScale
	uiCenterY = uiCenterY * uiScale

	-- Calculate offset in screen coordinates
	local screenOffsetX = screenCenterX - uiCenterX
	local screenOffsetY = screenCenterY - uiCenterY

	-- Convert to frame's coordinate space (for SetPoint)
	-- When calling frame:SetPoint('CENTER', UIParent, 'CENTER', x, y),
	-- the x,y values are interpreted in the FRAME's coordinate space
	local offsetX = math.floor(screenOffsetX / frameScale + 0.5)
	local offsetY = math.floor(screenOffsetY / frameScale + 0.5)

	return offsetX, offsetY
end

---Apply CENTER anchor to a frame relative to UIParent
---Uses GetCenterOffset to calculate the position
---@param frame Frame The frame to reposition
---@return boolean success Whether the operation succeeded
function PositionCalculator:ApplyCenterAnchor(frame)
	if not frame then
		return false
	end

	local offsetX, offsetY = self:GetCenterOffset(frame)
	if not offsetX or not offsetY then
		return false
	end

	frame:ClearAllPoints()
	frame:SetPoint('CENTER', UIParent, 'CENTER', offsetX, offsetY)
	return true
end

---Calculate the closest anchor point to a frame's current position
---Supports three modes: center (always CENTER), cardinal (5 anchors), corners (9 anchors)
---@param frame Frame The frame to calculate anchor for
---@return string anchor The closest anchor point (e.g., "TOPLEFT", "CENTER", "BOTTOMRIGHT")
function PositionCalculator:GetClosestAnchor(frame)
	if not frame then
		return 'CENTER'
	end

	-- Get anchor mode from database (default to corners)
	local anchorMode = (MoveIt.DB and MoveIt.DB.anchorMode) or 'corners'

	-- Legacy mode: always use CENTER
	if anchorMode == 'center' then
		return 'CENTER'
	end

	-- Get frame center position
	local frameX, frameY = frame:GetCenter()
	if not frameX or not frameY then
		return 'CENTER'
	end

	local screenWidth = UIParent:GetWidth()
	local screenHeight = UIParent:GetHeight()

	-- Define anchor positions
	local anchors = {
		CENTER = { x = screenWidth / 2, y = screenHeight / 2 },
		TOP = { x = screenWidth / 2, y = screenHeight },
		BOTTOM = { x = screenWidth / 2, y = 0 },
		LEFT = { x = 0, y = screenHeight / 2 },
		RIGHT = { x = screenWidth, y = screenHeight / 2 },
	}

	-- Add corner anchors for 'corners' mode
	if anchorMode == 'corners' then
		anchors.TOPLEFT = { x = 0, y = screenHeight }
		anchors.TOPRIGHT = { x = screenWidth, y = screenHeight }
		anchors.BOTTOMLEFT = { x = 0, y = 0 }
		anchors.BOTTOMRIGHT = { x = screenWidth, y = 0 }
	end

	-- Find closest anchor using Euclidean distance
	local closestAnchor = 'CENTER'
	local minDistance = math.huge

	for anchor, pos in pairs(anchors) do
		local dx = frameX - pos.x
		local dy = frameY - pos.y
		local distance = math.sqrt(dx * dx + dy * dy)

		if distance < minDistance then
			minDistance = distance
			closestAnchor = anchor
		end
	end

	if MoveIt.logger then
		MoveIt.logger.debug(('GetClosestAnchor: frame at (%.1f,%.1f), closest=%s (distance=%.1f)'):format(frameX, frameY, closestAnchor, minDistance))
	end

	return closestAnchor
end

---Calculate the offset from a specific anchor point to a frame's position
---Accounts for frame scale differences between frame and UIParent
---@param frame Frame The frame to calculate offset for
---@param anchorPoint string The anchor point (e.g., "TOPLEFT", "CENTER", "BOTTOMRIGHT")
---@return number offsetX X offset from anchor point
---@return number offsetY Y offset from anchor point
function PositionCalculator:CalculateAnchorOffset(frame, anchorPoint)
	if not frame or not anchorPoint then
		return 0, 0
	end

	-- Get frame center position and size
	local frameX, frameY = frame:GetCenter()
	if not frameX or not frameY then
		return 0, 0
	end

	local frameWidth = frame:GetWidth() or 0
	local frameHeight = frame:GetHeight() or 0

	-- Calculate the position of the frame's anchor point (not center!)
	-- This is what SetPoint will actually position
	local frameAnchorX = frameX
	local frameAnchorY = frameY

	-- Adjust for horizontal anchor position on the frame
	if anchorPoint:find('LEFT') then
		frameAnchorX = frameX - (frameWidth / 2)
	elseif anchorPoint:find('RIGHT') then
		frameAnchorX = frameX + (frameWidth / 2)
	end
	-- else CENTER: no adjustment needed

	-- Adjust for vertical anchor position on the frame
	if anchorPoint:find('TOP') then
		frameAnchorY = frameY + (frameHeight / 2)
	elseif anchorPoint:find('BOTTOM') then
		frameAnchorY = frameY - (frameHeight / 2)
	end
	-- else CENTER: no adjustment needed

	-- Account for scale differences between frame and UIParent
	local frameScale = frame:GetEffectiveScale()
	local uiScale = UIParent:GetEffectiveScale()

	-- Convert frame anchor position to screen coordinates
	local screenFrameAnchorX = frameAnchorX * frameScale
	local screenFrameAnchorY = frameAnchorY * frameScale

	-- Get UIParent anchor point position in screen coordinates
	local screenWidth = UIParent:GetWidth() * uiScale
	local screenHeight = UIParent:GetHeight() * uiScale

	local uiAnchorX, uiAnchorY

	-- Calculate X coordinate of UIParent anchor point
	if anchorPoint:find('LEFT') then
		uiAnchorX = 0
	elseif anchorPoint:find('RIGHT') then
		uiAnchorX = screenWidth
	else
		uiAnchorX = screenWidth / 2
	end

	-- Calculate Y coordinate of UIParent anchor point
	if anchorPoint:find('TOP') then
		uiAnchorY = screenHeight
	elseif anchorPoint:find('BOTTOM') then
		uiAnchorY = 0
	else
		uiAnchorY = screenHeight / 2
	end

	-- Calculate offset in screen coordinates
	local screenOffsetX = screenFrameAnchorX - uiAnchorX
	local screenOffsetY = screenFrameAnchorY - uiAnchorY

	-- Convert to frame's coordinate space (for SetPoint)
	-- When calling frame:SetPoint(anchor, UIParent, anchor, x, y),
	-- the x,y values are interpreted in the FRAME's coordinate space
	local offsetX = math.floor(screenOffsetX / frameScale + 0.5)
	local offsetY = math.floor(screenOffsetY / frameScale + 0.5)

	if MoveIt.logger then
		MoveIt.logger.debug(
			('CalculateAnchorOffset: anchor=%s, frameCenter=(%.1f,%.1f) size=(%.1fx%.1f), frameAnchor=(%.1f,%.1f), offset=(%.1f,%.1f)'):format(
				anchorPoint,
				frameX,
				frameY,
				frameWidth,
				frameHeight,
				frameAnchorX,
				frameAnchorY,
				offsetX,
				offsetY
			)
		)
	end

	return offsetX, offsetY
end

---Save a mover's position to the database
---@param name string The mover name
---@param position table The position {point, anchorFrameName, anchorPoint, x, y}
function PositionCalculator:SavePosition(name, position)
	if not MoveIt.DB or not MoveIt.DB.movers then
		return
	end

	if not position then
		return
	end

	-- Round coordinates
	local x = self:Round(position.x or 0, 0)
	local y = self:Round(position.y or 0, 0)

	-- Format: "POINT,AnchorFrame,ANCHORPOINT,x,y"
	local positionString = string.format('%s,%s,%s,%d,%d', position.point or 'CENTER', position.anchorFrameName or 'UIParent', position.anchorPoint or position.point or 'CENTER', x, y)

	MoveIt.DB.movers[name].MovedPoints = positionString

	if MoveIt.logger then
		MoveIt.logger.debug(('Saved position: %s = %s'):format(name, positionString))
	end
end

---Load a mover's position from the database
---@param name string The mover name
---@return table|nil position {point, anchorFrameName, anchorPoint, x, y}
function PositionCalculator:LoadPosition(name)
	if not MoveIt.DB or not MoveIt.DB.movers or not MoveIt.DB.movers[name] then
		return nil
	end

	local positionString = MoveIt.DB.movers[name].MovedPoints
	if not positionString then
		return nil
	end

	-- Parse: "POINT,AnchorFrame,ANCHORPOINT,x,y"
	local point, anchorFrameName, anchorPoint, x, y = strsplit(',', positionString)

	if not point then
		return nil
	end

	return {
		point = point,
		anchorFrameName = anchorFrameName or 'UIParent',
		anchorFrame = _G[anchorFrameName] or UIParent,
		anchorPoint = anchorPoint or point,
		x = tonumber(x) or 0,
		y = tonumber(y) or 0,
	}
end

---Get a mover's default position from its defaultPoint property
---@param mover Frame The mover frame
---@return table|nil position {point, anchorFrameName, anchorPoint, x, y}
function PositionCalculator:GetDefaultPosition(mover)
	if not mover or not mover.defaultPoint then
		return nil
	end

	-- Parse: "POINT,AnchorFrame,ANCHORPOINT,x,y"
	local point, anchorFrameName, anchorPoint, x, y = strsplit(',', mover.defaultPoint)

	if not point then
		return nil
	end

	return {
		point = point,
		anchorFrameName = anchorFrameName or 'UIParent',
		anchorFrame = _G[anchorFrameName] or UIParent,
		anchorPoint = anchorPoint or point,
		x = tonumber(x) or 0,
		y = tonumber(y) or 0,
	}
end

if MoveIt.logger then
	MoveIt.logger.info('Position Calculator loaded')
end
