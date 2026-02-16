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
