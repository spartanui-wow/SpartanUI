---@class SUI
local SUI = SUI
local L = SUI.L
---@class MoveIt
local MoveIt = SUI.MoveIt
local Style = SUI.UI.Style

-- Attaching one frame to another. An attached frame is saved relative to the frame it is
-- attached to, so it follows when that frame moves. Saved as a normal position string whose
-- anchor is the other mover (SUI_Mover_<name>); load order is handled by PendingAnchors.

---@class SUI.MoveIt.Anchors
local Anchors = {}
MoveIt.Anchors = Anchors

local GAP = 2

local SIDES = {
	{ key = 'left', text = 'Left side', point = 'RIGHT', relativePoint = 'LEFT', x = -GAP, y = 0 },
	{ key = 'right', text = 'Right side', point = 'LEFT', relativePoint = 'RIGHT', x = GAP, y = 0 },
	{ key = 'above', text = 'Above', point = 'BOTTOM', relativePoint = 'TOP', x = 0, y = GAP },
	{ key = 'below', text = 'Below', point = 'TOP', relativePoint = 'BOTTOM', x = 0, y = -GAP },
	{ key = 'keep', text = 'Keep it where it is', point = 'CENTER', relativePoint = 'CENTER' },
}

---@type SUI.MoveIt.Mover|nil
Anchors.picking = nil

---Position of an anchor point on a UIParent-unit rectangle
---@return number x, number y
local function PointPos(l, b, r, t, point)
	local x = (l + r) / 2
	local y = (b + t) / 2
	if point:find('LEFT') then
		x = l
	elseif point:find('RIGHT') then
		x = r
	end
	if point:find('TOP') then
		y = t
	elseif point:find('BOTTOM') then
		y = b
	end
	return x, y
end

---UIParent units to the mover's own units
---@param mover Frame
---@return number
local function Ratio(mover)
	return mover:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

---Offsets that keep `mover` exactly where it is when anchored with these points
---@param mover SUI.MoveIt.Mover
---@param target Frame
---@param point string
---@param relativePoint string
---@return number x, number y
function Anchors:MeasureOffset(mover, target, point, relativePoint)
	local Snap = MoveIt.Snap
	local ml, mb, mr, mt = Snap:GetRect(mover)
	local tl, tb, tr, tt = Snap:GetRect(target)
	if not ml or not tl then
		return 0, 0
	end
	local mx, my = PointPos(ml, mb, mr, mt, point)
	local tx, ty = PointPos(tl, tb, tr, tt, relativePoint)
	local ratio = Ratio(mover)
	return (mx - tx) / ratio, (my - ty) / ratio
end

---Can `mover` be attached to `target` without making a loop?
---@param mover SUI.MoveIt.Mover
---@param target Frame
---@return boolean
function Anchors:CanAttach(mover, target)
	if not target or target == mover or not target.isMover then
		return false
	end
	return not MoveIt.MagnetismManager:IsDescendantOf(target, mover)
end

---Attach a mover to another mover on the given side
---@param mover SUI.MoveIt.Mover
---@param target SUI.MoveIt.Mover
---@param sideKey string
function Anchors:Attach(mover, target, sideKey)
	if InCombatLockdown() or not self:CanAttach(mover, target) then
		return
	end
	local side
	for _, s in ipairs(SIDES) do
		if s.key == sideKey then
			side = s
		end
	end
	if not side then
		return
	end
	local x, y = side.x, side.y
	if side.key == 'keep' then
		x, y = self:MeasureOffset(mover, target, side.point, side.relativePoint)
	end
	mover:ClearAllPoints()
	mover:SetPoint(side.point, target, side.relativePoint, x, y)
	MoveIt.MagnetismManager:RegisterFrameRelationship(mover, target)
	MoveIt:SaveMover(mover)
end

---Stop following the other frame. The frame stays where it is.
---@param mover SUI.MoveIt.Mover
function Anchors:Detach(mover)
	if InCombatLockdown() or not MoveIt:GetAnchorMover(mover) then
		return
	end
	local left, bottom = mover:GetLeft(), mover:GetBottom()
	mover:ClearAllPoints()
	mover:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMLEFT', left or 0, bottom or 0)
	MoveIt.MagnetismManager:UnregisterFrame(mover)
	MoveIt:SaveMover(mover)
end

---After a drag, put an attached mover back on its anchor with offsets that keep it where it was dropped
---@param mover SUI.MoveIt.Mover
---@param anchorInfo {target: Frame, point: string, relativePoint: string}
function Anchors:Recapture(mover, anchorInfo)
	local x, y = self:MeasureOffset(mover, anchorInfo.target, anchorInfo.point, anchorInfo.relativePoint)
	mover:ClearAllPoints()
	mover:SetPoint(anchorInfo.point, anchorInfo.target, anchorInfo.relativePoint, x, y)
end

----------------------------------------------------------------------------------------------------
-- Choosing a frame to attach to
----------------------------------------------------------------------------------------------------

---@param mover SUI.MoveIt.Mover
function Anchors:BeginPick(mover)
	self.picking = mover
	self:HideSideMenu()
	MoveIt.GridOverlay:SetPickDim(true)
	MoveIt.MoverMode:RepaintAll()
	if MoveIt.ControlToolbar then
		MoveIt.ControlToolbar:SetHint(L['Click the frame to attach to. Press Escape to cancel.'])
	end
end

function Anchors:CancelPick()
	if not self.picking then
		return
	end
	self.picking = nil
	self:HideSideMenu()
	MoveIt.GridOverlay:SetPickDim(false)
	MoveIt.MoverMode:RepaintAll()
	if MoveIt.ControlToolbar then
		MoveIt.ControlToolbar:SetHint(nil)
	end
end

---@return boolean
function Anchors:IsPicking()
	return self.picking ~= nil
end

---A mover was clicked while picking
---@param target SUI.MoveIt.Mover
function Anchors:OnTargetClicked(target)
	local mover = self.picking
	if not mover then
		return
	end
	if not self:CanAttach(mover, target) then
		return
	end
	self:ShowSideMenu(mover, target)
end

function Anchors:CreateSideMenu()
	if self.sideMenu then
		return self.sideMenu
	end
	local menu = CreateFrame('Frame', nil, UIParent)
	menu:SetFrameStrata('FULLSCREEN_DIALOG')
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	Style:SkinPanel(menu, Style.color.raised, Style.color.lineStrong)
	menu.title = Style:CreateText(menu, 11)
	menu.title:SetPoint('TOPLEFT', 8, -8)
	menu.buttons = {}
	local previous
	for i, side in ipairs(SIDES) do
		local button = MoveIt.Widgets:Button(menu, L[side.text], 150, function()
			local mover, target = menu.mover, menu.target
			Anchors:HideSideMenu()
			Anchors:CancelPick()
			Anchors:Attach(mover, target, side.key)
			MoveIt.MoverMode:Select(mover)
		end)
		if previous then
			button:SetPoint('TOPLEFT', previous, 'BOTTOMLEFT', 0, -3)
		else
			button:SetPoint('TOPLEFT', menu.title, 'BOTTOMLEFT', 0, -8)
		end
		previous = button
		menu.buttons[i] = button
	end
	menu:SetSize(166, 8 + 14 + 8 + #SIDES * 25 + 5)
	menu:Hide()
	self.sideMenu = menu
	return menu
end

---@param mover SUI.MoveIt.Mover
---@param target SUI.MoveIt.Mover
function Anchors:ShowSideMenu(mover, target)
	local menu = self:CreateSideMenu()
	menu.mover = mover
	menu.target = target
	menu.title:SetText(L['Attach to'] .. ' ' .. (target.displayText or target.name))
	local scale = menu:GetEffectiveScale()
	local x, y = GetCursorPosition()
	menu:ClearAllPoints()
	menu:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', x / scale + 8, y / scale - 8)
	menu:Show()
end

function Anchors:HideSideMenu()
	if self.sideMenu then
		self.sideMenu:Hide()
	end
end

---@return boolean
function Anchors:IsSideMenuShown()
	return self.sideMenu ~= nil and self.sideMenu:IsShown()
end

----------------------------------------------------------------------------------------------------
-- Connector line between an attached frame and its anchor
----------------------------------------------------------------------------------------------------

function Anchors:CreateConnector()
	if self.connector then
		return self.connector
	end
	local holder = CreateFrame('Frame', nil, UIParent)
	holder:SetAllPoints(UIParent)
	holder:SetFrameStrata('FULLSCREEN')
	holder:EnableMouse(false)
	local function Segment()
		local tex = holder:CreateTexture(nil, 'OVERLAY')
		tex:SetTexture(Style.WHITE)
		tex:SetVertexColor(Style.color.anchored[1], Style.color.anchored[2], Style.color.anchored[3], 0.9)
		return tex
	end
	holder.horizontal = Segment()
	holder.vertical = Segment()
	holder.dot = Segment()
	holder:Hide()
	self.connector = holder
	return holder
end

---Draw an L-shaped line from the mover's center to the center of the frame it is attached to
---@param mover SUI.MoveIt.Mover|nil
function Anchors:ShowConnector(mover)
	local target = mover and MoveIt:GetAnchorMover(mover)
	if not target then
		self:HideConnector()
		return
	end
	local holder = self:CreateConnector()
	local Snap = MoveIt.Snap
	local ml, mb, mr, mt = Snap:GetRect(mover)
	local tl, tb, tr, tt = Snap:GetRect(target)
	if not ml or not tl then
		self:HideConnector()
		return
	end
	local mx, my = (ml + mr) / 2, (mb + mt) / 2
	local tx, ty = (tl + tr) / 2, (tb + tt) / 2
	local width = Style:PixelSize(holder) * 2

	holder.horizontal:ClearAllPoints()
	holder.horizontal:SetPoint('LEFT', holder, 'BOTTOMLEFT', math.min(mx, tx), my)
	holder.horizontal:SetSize(math.max(width, math.abs(tx - mx)), width)
	holder.vertical:ClearAllPoints()
	holder.vertical:SetPoint('BOTTOM', holder, 'BOTTOMLEFT', tx, math.min(my, ty))
	holder.vertical:SetSize(width, math.max(width, math.abs(ty - my)))
	holder.dot:ClearAllPoints()
	holder.dot:SetPoint('CENTER', holder, 'BOTTOMLEFT', tx, ty)
	holder.dot:SetSize(width * 3, width * 3)
	holder:Show()
	Style:Loop(holder, function(elapsed)
		holder:SetAlpha(0.55 + 0.45 * math.abs(math.sin(elapsed * 2.5)))
	end)
end

function Anchors:HideConnector()
	if self.connector then
		Style:Stop(self.connector)
		self.connector:Hide()
	end
end
