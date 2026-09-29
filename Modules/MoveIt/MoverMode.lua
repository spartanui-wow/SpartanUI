---@class SUI
local SUI = SUI
local L = SUI.L
---@class MoveIt
local MoveIt = SUI.MoveIt
local Style = SUI.UI.Style

-- Move mode: every movable frame gets a flat box you can drag, select, nudge and attach.
-- Changes save as you go; the session remembers where everything started so leaving with
-- "Exit without saving" puts it all back.

---@class SUI.MoveIt.MoverMode
local MoverMode = {}
MoveIt.MoverMode = MoverMode

local isActive = false
local isSuspended = false
---@type SUI.MoveIt.Mover|nil
local selected
---@type table<SUI.MoveIt.Mover, boolean>
local hovered = {}
---@type table<SUI.MoveIt.Mover, boolean>
local snapTargets = {}
---@type table<string, boolean>
local hiddenGroups = {}
local drag ---@type table|nil

-- Frames whose boxes capture input in ways that get in the way
local SKIPPED = {
	VehicleSeatIndicator = true,
	SUI_CustomMover_VehicleMinimapPosition = true,
}

local dragDriver = CreateFrame('Frame')
dragDriver:Hide()

---@param name string
---@param mover SUI.MoveIt.Mover
---@return boolean
local function IsEligible(name, mover)
	if not mover or not mover.parent or mover.isCustomMover or SKIPPED[name] then
		return false
	end
	if mover.IsMoverAvailable and not mover:IsMoverAvailable() then
		return false
	end
	return true
end

---@return boolean
function MoverMode:IsActive()
	return isActive
end

---@param mover? Frame
---@return boolean
function MoverMode:IsDragging(mover)
	return drag ~= nil and (mover == nil or drag.mover == mover)
end

----------------------------------------------------------------------------------------------------
-- Painting
----------------------------------------------------------------------------------------------------

---@param mover SUI.MoveIt.Mover
function MoverMode:Paint(mover)
	if not mover.fill then
		return
	end
	local c = Style.color
	local r, g, b = Style:GetAccent()
	local fillAlpha = MoveIt.DB.SeeThrough and 0.12 or c.mover[4]
	local lift = 0
	local alpha = 1
	local br, bg, bb, ba = r, g, b, 0.65

	local picking = MoveIt.Anchors.picking
	if picking then
		if mover == picking then
			br, bg, bb, ba = r, g, b, 1
		elseif MoveIt.Anchors:CanAttach(picking, mover) then
			br, bg, bb, ba = 1, 1, 1, hovered[mover] and 1 or 0.45
			lift = hovered[mover] and 0.06 or 0
		else
			alpha = 0.3
		end
	elseif snapTargets[mover] then
		br, bg, bb, ba = 1, 1, 1, 1
	elseif mover == selected then
		br, bg, bb, ba = 1, 1, 1, 0.95
		lift = 0.05
	elseif hovered[mover] then
		br, bg, bb, ba = 1, 1, 1, 0.6
		lift = 0.03
	end

	mover.fill:SetVertexColor(c.mover[1] + lift, c.mover[2] + lift, c.mover[3] + lift, fillAlpha)
	mover.border:SetColor(br, bg, bb, ba)
	mover:SetAlpha(alpha)
	mover.showCoords = MoveIt.DB.ShowCoordinates and (mover == selected or hovered[mover] or (drag and drag.mover == mover)) or false
	MoveIt:UpdateMoverText(mover)
end

function MoverMode:RepaintAll()
	for name, mover in pairs(MoveIt.MoverList) do
		if IsEligible(name, mover) then
			self:Paint(mover)
		end
	end
end

---Refresh a mover after its position, size or anchor changed
---@param mover SUI.MoveIt.Mover
function MoverMode:RefreshMover(mover)
	if not isActive then
		MoveIt:UpdateMoverText(mover)
		return
	end
	self:Paint(mover)
	if mover == selected then
		MoveIt.Inspector:Refresh()
		MoveIt.Anchors:ShowConnector(mover)
	end
end

---Smaller boxes above larger ones, so a small frame sitting on a big one can still be grabbed
function MoverMode:SortLevels()
	local list = {}
	for name, mover in pairs(MoveIt.MoverList) do
		if IsEligible(name, mover) then
			list[#list + 1] = mover
		end
	end
	table.sort(list, function(a, b)
		return (a:GetWidth() * a:GetHeight()) > (b:GetWidth() * b:GetHeight())
	end)
	for i, mover in ipairs(list) do
		mover:SetFrameLevel(10 + i * 2)
	end
end

----------------------------------------------------------------------------------------------------
-- Enter / exit
----------------------------------------------------------------------------------------------------

function MoverMode:ShowMovers(fade)
	for name, mover in pairs(MoveIt.MoverList) do
		if IsEligible(name, mover) then
			if mover.parent.isBlizzMoverHolder then
				mover.parent:Show()
			end
			mover:EnableKeyboard(false)
			if not hiddenGroups[mover.groupName] then
				self:Paint(mover)
				mover:Show()
				if fade then
					mover:SetAlpha(0)
					Style:FadeTo(mover, 1, 0.18)
				end
			end
		end
	end
	self:SortLevels()
end

function MoverMode:HideMovers()
	for _, mover in pairs(MoveIt.MoverList) do
		if mover.parent then
			Style:Stop(mover)
			mover:SetAlpha(1)
			mover:Hide()
			if mover.parent.isBlizzMoverHolder then
				mover.parent:Hide()
			end
		end
	end
end

function MoverMode:Enter()
	if isActive then
		return
	end
	if InCombatLockdown() then
		SUI:Print(ERR_NOT_IN_COMBAT)
		return
	end
	if self.suppressActivation then
		return
	end

	isActive = true
	isSuspended = false
	wipe(hovered)
	wipe(snapTargets)
	selected = nil
	MoveIt.Session:Begin()

	MoveIt:ShowMoverWatcher()
	MoveIt.GridOverlay:Show()
	MoveIt.ControlToolbar:Show()
	self:ShowMovers(true)

	if MoveIt.logger then
		MoveIt.logger.info('Move mode opened')
	end
	if MoveIt.Callbacks and MoveIt.Callbacks.OnEditModeEnter then
		MoveIt.Callbacks.OnEditModeEnter()
	end
end

---Tear down everything shown in move mode, without ending the session
local function HideVisuals()
	if drag then
		MoverMode:StopDrag(drag.mover)
	end
	MoveIt.Anchors:CancelPick()
	MoveIt.Anchors:HideConnector()
	MoveIt.Inspector:Hide()
	MoveIt.Snap:HideGuides()
	MoveIt.ControlToolbar:Hide()
	MoveIt.GridOverlay:Hide()
	MoverMode:HideMovers()
	MoveIt:HideMoverWatcher()
end

---Leave move mode
---@param discard? boolean Put every frame back where it was when move mode opened
function MoverMode:Exit(discard)
	if not isActive then
		return
	end
	HideVisuals()
	if discard then
		MoveIt.Session:Revert()
	end
	MoveIt.Session:End()
	isActive = false
	isSuspended = false
	selected = nil
	wipe(hovered)
	wipe(snapTargets)
	wipe(hiddenGroups)

	if MoveIt.logger then
		MoveIt.logger.info(discard and 'Move mode closed, changes undone' or 'Move mode closed, changes kept')
	end
	if MoveIt.Callbacks and MoveIt.Callbacks.OnEditModeExit then
		MoveIt.Callbacks.OnEditModeExit()
	end
end

---Leave move mode, asking first when there are changes
function MoverMode:RequestExit()
	if not isActive then
		return
	end
	if not MoveIt.Session:HasChanges() then
		self:Exit(false)
		return
	end
	StaticPopupDialogs['SUI_MOVEIT_UNSAVED'] = {
		text = L['You moved some frames. Keep the changes?'],
		button1 = L['Keep changes'],
		button2 = L['Undo changes'],
		button3 = L['Keep moving'],
		OnAccept = function()
			MoverMode:Exit(false)
		end,
		OnCancel = function(_, _, reason)
			if reason == 'clicked' then
				MoverMode:Exit(true)
			end
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	StaticPopup_Show('SUI_MOVEIT_UNSAVED')
end

function MoverMode:Toggle()
	if isActive then
		self:RequestExit()
	else
		self:Enter()
	end
end

---Combat started: hide everything but keep the session
function MoverMode:Suspend()
	if not isActive or isSuspended then
		return
	end
	isSuspended = true
	HideVisuals()
	SUI:Print(L['Frame moving is paused until combat ends.'])
end

---Combat ended: bring move mode back
function MoverMode:Resume()
	if not isActive or not isSuspended or InCombatLockdown() then
		return
	end
	isSuspended = false
	MoveIt:ShowMoverWatcher()
	MoveIt.GridOverlay:Show()
	MoveIt.ControlToolbar:Show()
	self:ShowMovers(true)
end

---@return boolean
function MoverMode:IsSuspended()
	return isSuspended
end

----------------------------------------------------------------------------------------------------
-- Selection and mouse
----------------------------------------------------------------------------------------------------

---@param mover SUI.MoveIt.Mover|nil
function MoverMode:Select(mover)
	local previous = selected
	selected = mover
	if previous and previous ~= mover then
		self:Paint(previous)
	end
	if mover then
		self:Paint(mover)
		MoveIt.Inspector:Show(mover)
		MoveIt.Anchors:ShowConnector(mover)
	else
		MoveIt.Inspector:Hide()
		MoveIt.Anchors:HideConnector()
	end
end

---@return SUI.MoveIt.Mover|nil
function MoverMode:GetSelected()
	return selected
end

---@param mover SUI.MoveIt.Mover
---@param isHovered boolean
function MoverMode:SetHovered(mover, isHovered)
	if not isActive then
		return
	end
	hovered[mover] = isHovered or nil
	self:Paint(mover)
	if not selected and not drag then
		if isHovered then
			MoveIt.Anchors:ShowConnector(mover)
		else
			MoveIt.Anchors:HideConnector()
		end
	end
end

---@param mover SUI.MoveIt.Mover
---@param button string
function MoverMode:OnMoverClicked(mover, button)
	local Anchors = MoveIt.Anchors
	if Anchors:IsPicking() then
		if button == 'RightButton' then
			Anchors:CancelPick()
		elseif mover ~= Anchors.picking then
			Anchors:OnTargetClicked(mover)
		end
		return
	end
	self:Select(mover)
end

---Forget a mover that is being removed from the system
---@param mover SUI.MoveIt.Mover
function MoverMode:ForgetMover(mover)
	hovered[mover] = nil
	snapTargets[mover] = nil
	if selected == mover then
		self:Select(nil)
	end
end

----------------------------------------------------------------------------------------------------
-- Dragging
----------------------------------------------------------------------------------------------------

---@return number x, number y Cursor in UIParent units
local function CursorPosition()
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	return x / scale, y / scale
end

local function SetSnapTargets(xLine, yLine)
	local changed = false
	local new = {}
	if xLine and xLine.frame then
		new[xLine.frame] = true
	end
	if yLine and yLine.frame then
		new[yLine.frame] = true
	end
	for frame in pairs(snapTargets) do
		if not new[frame] then
			snapTargets[frame] = nil
			MoverMode:Paint(frame)
			changed = true
		end
	end
	for frame in pairs(new) do
		if not snapTargets[frame] then
			snapTargets[frame] = true
			MoverMode:Paint(frame)
			changed = true
		end
	end
	return changed
end

local function DragUpdate()
	local info = drag
	if not info then
		return
	end
	local mover = info.mover
	local cx, cy = CursorPosition()
	local moveX, moveY = cx - info.startX, cy - info.startY

	-- Shift keeps the drag on one axis, picked from the first few pixels of movement
	if IsShiftKeyDown() then
		if not info.axis and (math.abs(moveX) > 3 or math.abs(moveY) > 3) then
			info.axis = math.abs(moveX) >= math.abs(moveY) and 'x' or 'y'
		end
		if info.axis == 'x' then
			moveY = 0
		elseif info.axis == 'y' then
			moveX = 0
		end
	else
		info.axis = nil
	end

	local centerX = info.centerX + moveX
	local centerY = info.centerY + moveY
	local halfW, halfH = info.width / 2, info.height / 2
	local dx, dy, xLine, yLine = MoveIt.Snap:Compute(centerX - halfW, centerY - halfH, centerX + halfW, centerY + halfH)
	if info.axis == 'x' then
		dy, yLine = 0, nil
	elseif info.axis == 'y' then
		dx, xLine = 0, nil
	end
	centerX = centerX + dx
	centerY = centerY + dy

	mover:ClearAllPoints()
	mover:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', centerX / info.ratio, centerY / info.ratio)
	MoveIt.Snap:ShowGuides(xLine, yLine)
	SetSnapTargets(xLine, yLine)
	MoveIt:UpdateMoverText(mover)
	if mover == selected then
		MoveIt.Inspector:Refresh()
	end
end

---@param mover SUI.MoveIt.Mover
function MoverMode:StartDrag(mover)
	if InCombatLockdown() or MoveIt.Anchors:IsPicking() then
		return
	end
	local l, b, r, t = MoveIt.Snap:GetRect(mover)
	if not l then
		return
	end
	local anchorInfo
	local anchorMover = MoveIt:GetAnchorMover(mover)
	if anchorMover then
		local point, _, relativePoint = mover:GetPoint(1)
		anchorInfo = { target = anchorMover, point = point, relativePoint = relativePoint }
	end

	local startX, startY = CursorPosition()
	drag = {
		mover = mover,
		startX = startX,
		startY = startY,
		centerX = (l + r) / 2,
		centerY = (b + t) / 2,
		width = r - l,
		height = t - b,
		ratio = mover:GetEffectiveScale() / UIParent:GetEffectiveScale(),
		anchorInfo = anchorInfo,
	}
	self:Select(mover)
	MoveIt.Anchors:HideConnector()
	MoveIt.Snap:BeginDrag(mover)
	dragDriver:SetScript('OnUpdate', DragUpdate)
	dragDriver:Show()
end

---@param mover SUI.MoveIt.Mover
function MoverMode:StopDrag(mover)
	local info = drag
	if not info or info.mover ~= mover then
		return
	end
	drag = nil
	dragDriver:SetScript('OnUpdate', nil)
	dragDriver:Hide()
	MoveIt.Snap:EndDrag()
	SetSnapTargets(nil, nil)

	if not InCombatLockdown() then
		if info.anchorInfo then
			MoveIt.Anchors:Recapture(mover, info.anchorInfo)
		end
		MoveIt:SaveMover(mover)
	end
	self:RefreshMover(mover)
	MoveIt.Inspector:Place()
end

----------------------------------------------------------------------------------------------------
-- Keyboard
----------------------------------------------------------------------------------------------------

local ARROWS = { LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }

---Handle a key while move mode is open
---@param key string
---@return boolean handled
function MoverMode:HandleKey(key)
	if not isActive or isSuspended then
		return false
	end
	if key == 'ESCAPE' then
		local Anchors = MoveIt.Anchors
		if Anchors:IsSideMenuShown() then
			Anchors:HideSideMenu()
		elseif Anchors:IsPicking() then
			Anchors:CancelPick()
		elseif MoveIt.ControlToolbar:IsFilterMenuShown() then
			MoveIt.ControlToolbar:HideFilterMenu()
		elseif selected then
			self:Select(nil)
		else
			self:RequestExit()
		end
		return true
	end
	local arrow = ARROWS[key]
	if arrow and selected and not drag then
		local step = Style:PixelSize(selected) * (IsShiftKeyDown() and 10 or 1)
		MoveIt:NudgeMover(selected, arrow[1] * step, arrow[2] * step)
		self:RefreshMover(selected)
		return true
	end
	return false
end

----------------------------------------------------------------------------------------------------
-- Group filter
----------------------------------------------------------------------------------------------------

---@return string[]
function MoverMode:GetGroups()
	local seen, groups = {}, {}
	for name, mover in pairs(MoveIt.MoverList) do
		if IsEligible(name, mover) and not seen[mover.groupName] then
			seen[mover.groupName] = true
			groups[#groups + 1] = mover.groupName
		end
	end
	table.sort(groups)
	return groups
end

---@param group string
---@return boolean
function MoverMode:IsGroupHidden(group)
	return hiddenGroups[group] and true or false
end

---@param group string
---@param hide boolean
function MoverMode:SetGroupHidden(group, hide)
	hiddenGroups[group] = hide or nil
	for name, mover in pairs(MoveIt.MoverList) do
		if IsEligible(name, mover) and mover.groupName == group then
			if hide then
				if mover == selected then
					self:Select(nil)
				end
				mover:Hide()
			elseif isActive then
				self:Paint(mover)
				mover:Show()
			end
		end
	end
end

---@return number
function MoverMode:GetHiddenGroupCount()
	local count = 0
	for _ in pairs(hiddenGroups) do
		count = count + 1
	end
	return count
end

Style:OnAccentChanged(MoverMode, function()
	if isActive then
		MoverMode:RepaintAll()
	end
end)
