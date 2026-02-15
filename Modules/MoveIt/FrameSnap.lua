---@class SUI
local SUI = SUI
---@class MoveIt
local MoveIt = SUI.MoveIt

-- Get LibSimpleSticky BEFORE registering the module
local LibSticky = LibStub and LibStub('LibSimpleSticky-1.0', true)
if not LibSticky then
	return
end

---@class SUI.MoveIt.FrameSnap
local FrameSnap = {}
MoveIt.FrameSnap = FrameSnap

---Start frame-to-frame snapping using LibSimpleSticky
---@param frame Frame The frame being dragged
function FrameSnap:StartSnapping(frame)
	if MoveIt.logger then
		MoveIt.logger.debug(('FrameSnap:StartSnapping called for %s (ElementSnapEnabled=%s)'):format(frame.name or 'unknown', tostring(MoveIt.DB.ElementSnapEnabled)))
	end

	if not MoveIt.DB.ElementSnapEnabled then
		if MoveIt.logger then
			MoveIt.logger.debug('Frame snapping disabled - skipping')
		end
		return
	end

	-- Build list of frames to snap to
	local snapFrames = {}

	-- Add SUI anchors
	if SUI_BottomAnchor and SUI_BottomAnchor:IsShown() then
		table.insert(snapFrames, SUI_BottomAnchor)
	end
	if SUI_TopAnchor and SUI_TopAnchor:IsShown() then
		table.insert(snapFrames, SUI_TopAnchor)
	end

	-- Add other visible movers (except self and parent/child relationships)
	for name, mover in pairs(MoveIt.MoverList or {}) do
		if mover and mover:IsShown() and mover ~= frame then
			-- Skip frames with circular dependencies
			local isAnchored = MoveIt.MagnetismManager:IsFrameAnchoredTo(mover, frame)
			local hasRelationship = MoveIt.MagnetismManager:HasFrameRelationship(mover, frame)

			if not isAnchored and not hasRelationship then
				table.insert(snapFrames, mover)
			end
		end
	end

	-- Use LibSimpleSticky's StartMoving with 15px snap range
	LibSticky:StartMoving(frame, snapFrames, 0, 0, 0, 0)
end

---Stop frame-to-frame snapping
---@param frame Frame The frame being dragged
---@return boolean wasSnapped True if frame snapped to another frame
---@return Frame|nil snapTarget The frame we snapped to (if any)
function FrameSnap:StopSnapping(frame)
	local wasSnapped, snapTarget = LibSticky:StopMoving(frame)

	if wasSnapped and snapTarget then
		-- Anchor the frame to the snap target using LibSimpleSticky's method
		LibSticky:AnchorFrame(frame)

		if MoveIt.logger and MoveIt.MagnetismManager.debugLogging then
			local frameName = frame.name or 'unknown'
			local targetName = snapTarget.name or (snapTarget == UIParent and 'UIParent') or 'unknown'
			MoveIt.logger.debug(('FrameSnap: %s snapped to %s'):format(frameName, targetName))
		end
	end

	return wasSnapped, snapTarget
end

---Check if frame snapping is enabled
---@return boolean
function FrameSnap:IsEnabled()
	return MoveIt.DB.ElementSnapEnabled ~= false
end
