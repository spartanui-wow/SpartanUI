---@type SUI
local SUI = SUI
local L = SUI.L
---@class MoveIt
local MoveIt = SUI.MoveIt
local Style = SUI.UI.Style

---@param obj Frame
---@return string
local function GetPoints(obj)
	local point, anchor, secondaryPoint, x, y = obj:GetPoint()
	if not point then
		return 'CENTER,UIParent,CENTER,0,0'
	end
	local anchorName = (anchor and anchor.GetName and anchor:GetName()) or 'UIParent'
	return format('%s,%s,%s,%d,%d', point, anchorName, secondaryPoint or point, Round(x or 0), Round(y or 0))
end
MoveIt.GetPoints = GetPoints

-- Where each mover's "Settings" button leads when the owning module did not say
local OPTION_PATHS = {
	BT4BarPetBar = { 'ActionBars', 'pet' },
	BT4BarStanceBar = { 'ActionBars', 'stance' },
	BT4BarMicroMenu = { 'ActionBars', 'micro' },
	BT4BarBagBar = { 'ActionBars', 'bags' },
	BT4BarQueueStatus = { 'ActionBars', 'queue' },
	BT4BarExtraActionBar = { 'ActionBars', 'extra' },
	Minimap = { 'Modules', 'Minimap' },
	StatusBar_Left = { 'Artwork', 'StatusBars' },
	StatusBar_Right = { 'Artwork', 'StatusBars' },
}

---@class SUI.MoveIt.Mover : Button
---@field name string
---@field parent SUI.MoveIt.MoverParent
---@field label FontString
---@field DisplayName FontString Same as label; kept for older callers
---@field subtitle FontString
---@field fill Texture
---@field border SUI.UI.Style.Border
---@field groupName string
---@field displayText string
---@field defaultPoint string
---@field defaultScale number
---@field postdrag? function
---@field optionsPath? string[]
---@field noScale? boolean
---@field isMover boolean
---@field IsMoverAvailable? fun(self: SUI.MoveIt.Mover): boolean
---@field updateObj? Frame

---@class SUI.MoveIt.MoverParent : Frame
---@field mover? SUI.MoveIt.Mover
---@field position? fun(self: SUI.MoveIt.MoverParent, point?: string, anchor?: string|Frame, secondaryPoint?: string, x?: number, y?: number, forced?: boolean, defaultPos?: boolean)
---@field scale? fun(self: SUI.MoveIt.MoverParent, scale?: number, setDefault?: boolean, forced?: boolean)
---@field isMoved? fun(): boolean
---@field dirtyWidth? number
---@field dirtyHeight? number
---@field isBlizzMoverHolder? boolean

---The mover this mover is attached to, if its saved position points at another mover
---@param mover SUI.MoveIt.Mover
---@return SUI.MoveIt.Mover|nil
function MoveIt:GetAnchorMover(mover)
	local _, anchor = mover:GetPoint(1)
	if anchor and anchor ~= UIParent and anchor.isMover then
		return anchor
	end
	return nil
end

---Refresh the small text under a mover's name
---@param mover SUI.MoveIt.Mover
function MoveIt:UpdateMoverText(mover)
	if not mover or not mover.subtitle then
		return
	end
	local parts = {}
	local anchorMover = self:GetAnchorMover(mover)
	if anchorMover then
		parts[#parts + 1] = L['Attached to'] .. ' ' .. (anchorMover.displayText or anchorMover.name)
	elseif self:IsMoved(mover.name) and self.DB.movers[mover.name].MovedPoints then
		parts[#parts + 1] = L['Moved']
	end
	local adjusted = self.DB.movers[mover.name].AdjustedScale
	if adjusted then
		parts[#parts + 1] = string.format('%s %.2f', L['Scale'], adjusted)
	end
	if mover.showCoords then
		local _, _, _, x, y = mover:GetPoint(1)
		parts[#parts + 1] = string.format('%.1f, %.1f', x or 0, y or 0)
	end
	mover.subtitle:SetText(table.concat(parts, '  |  '))

	local c = anchorMover and Style.color.anchored or Style.color.text
	mover.label:SetTextColor(c[1], c[2], c[3], 1)
end

---Options path the mover's "Settings" button opens
---@param mover SUI.MoveIt.Mover
---@return string[]
function MoveIt:GetOptionsPath(mover)
	if mover.optionsPath then
		return mover.optionsPath
	end
	if OPTION_PATHS[mover.name] then
		return OPTION_PATHS[mover.name]
	end
	local barId = mover.name:match('^BT4Bar(%d+)$')
	if barId and SUI.opt.args.ActionBars and SUI.opt.args.ActionBars.args['bar' .. barId] then
		return { 'ActionBars', 'bar' .. barId }
	end
	if SUI.opt.args.UnitFrames and SUI.opt.args.UnitFrames.args[mover.name] then
		return { 'UnitFrames', mover.name }
	end
	return { 'Movers', mover.groupName or 'General', mover.name }
end

---Set where a mover's "Settings" button leads
---@param name string
---@param path string[]
function MoveIt:SetOptionsPath(name, path)
	local mover = self.MoverList[name]
	if mover then
		mover.optionsPath = path
	end
end

---Save a mover's current place. A mover attached to another mover keeps that anchor;
---everything else is stored against the nearest screen corner or edge.
---@param mover SUI.MoveIt.Mover
function MoveIt:SaveMover(mover)
	local name = mover.name
	local PositionCalculator = self.PositionCalculator
	local anchorMover = self:GetAnchorMover(mover)
	if anchorMover then
		local point, _, relativePoint, x, y = mover:GetPoint(1)
		PositionCalculator:SavePosition(name, {
			point = point,
			anchorFrameName = anchorMover:GetName(),
			anchorPoint = relativePoint,
			x = x,
			y = y,
		})
	else
		local closest = PositionCalculator:GetClosestAnchor(mover)
		local x, y = PositionCalculator:CalculateAnchorOffset(mover, closest)
		mover:ClearAllPoints()
		mover:SetPoint(closest, UIParent, closest, x, y)
		PositionCalculator:SavePosition(name, {
			point = closest,
			anchorFrameName = 'UIParent',
			anchorPoint = closest,
			x = x,
			y = y,
		})
	end
	self:UpdateMoverText(mover)
	if mover.postdrag then
		mover.postdrag(mover)
	end
end

---Move a mover by an offset in its own units, keeping any anchor it has
---@param mover SUI.MoveIt.Mover
---@param dx number
---@param dy number
function MoveIt:NudgeMover(mover, dx, dy)
	if InCombatLockdown() then
		return
	end
	local point, anchor, relativePoint, x, y = mover:GetPoint(1)
	mover:ClearAllPoints()
	mover:SetPoint(point, anchor or UIParent, relativePoint, (x or 0) + (dx or 0), (y or 0) + (dy or 0))
	self:SaveMover(mover)
end

---Set a mover's scale and remember it (nil or its default clears the saved scale)
---@param mover SUI.MoveIt.Mover
---@param value? number
function MoveIt:SetMoverScale(mover, value)
	if InCombatLockdown() or mover.noScale then
		return
	end
	value = value or mover.defaultScale or 1
	value = math.max(0.25, math.min(3, value))
	-- A frame scales around its anchor point, so anything placed with an offset drifts as it grows.
	-- Keep its centre where it was on screen and save that spot.
	local cx, cy = mover:GetCenter()
	local oldScale = mover:GetEffectiveScale()
	mover:SetScale(value)
	mover.parent:SetScale(value)
	local nx, ny = mover:GetCenter()
	local point, anchor, relativePoint, x, y = mover:GetPoint(1)
	if cx and nx and point then
		local ratio = oldScale / mover:GetEffectiveScale()
		mover:ClearAllPoints()
		mover:SetPoint(point, anchor, relativePoint, (x or 0) + cx * ratio - nx, (y or 0) + cy * ratio - ny)
		self:SaveMover(mover)
	end
	if math.abs(value - (mover.defaultScale or 1)) < 0.001 then
		self.DB.movers[mover.name].AdjustedScale = nil
	else
		self.DB.movers[mover.name].AdjustedScale = value
	end
	self:UpdateMoverText(mover)
end

---Place a mover where its saved data (or its default) says, and apply its saved scale
---@param name string
function MoveIt:ApplySavedPosition(name)
	local mover = self.MoverList[name]
	if not mover or not mover.defaultPoint then
		return
	end
	local data = self.DB.movers[name]
	local point, anchor, secondaryPoint, x, y = strsplit(',', data.MovedPoints or mover.defaultPoint)
	if type(anchor) == 'string' and not _G[anchor] then
		point, anchor, secondaryPoint, x, y = strsplit(',', mover.defaultPoint)
	end
	if type(anchor) == 'string' and not _G[anchor] then
		anchor = 'UIParent'
	end
	mover:ClearAllPoints()
	mover:SetPoint(point, anchor, secondaryPoint, tonumber(x) or 0, tonumber(y) or 0)

	local scale = data.AdjustedScale or mover.defaultScale or 1
	mover:SetScale(scale)
	mover.parent:SetScale(scale)
	self:UpdateMoverText(mover)
	if mover.postdrag then
		mover.postdrag(mover)
	end
end

---@param parent SUI.MoveIt.MoverParent
---@param name string
---@param DisplayName? string
---@param postdrag? function
---@param groupName? string
---@return nil
function MoveIt:CreateMover(parent, name, DisplayName, postdrag, groupName)
	if SUI:IsModuleDisabled('MoveIt') then
		return
	end
	-- If for some reason the parent does not exist or we have already done this exit out
	if not parent or self.MoverList[name] then
		return
	end
	if DisplayName == nil then
		DisplayName = name
	end

	local point, anchor, secondaryPoint, x, y = strsplit(',', GetPoints(parent))

	--Use dirtyWidth / dirtyHeight to set initial size if possible
	local width = parent.dirtyWidth or parent:GetWidth()
	local height = parent.dirtyHeight or parent:GetHeight()

	local f = CreateFrame('Button', 'SUI_Mover_' .. name, UIParent) ---@type SUI.MoveIt.Mover
	f:SetClampedToScreen(true)
	f:RegisterForDrag('LeftButton')
	f:EnableMouseWheel(true)
	f:SetMovable(true)
	f:SetSize(width, height)
	f:Hide()
	f.isMover = true
	f.parent = parent
	f.name = name
	f.displayText = DisplayName
	f.groupName = groupName or 'General'
	f.postdrag = postdrag
	f.defaultScale = (parent:GetScale() or 1)
	f.defaultPoint = GetPoints(parent)

	f:SetFrameLevel(parent:GetFrameLevel() + 1)
	f:SetFrameStrata('DIALOG')

	f.fill = Style:CreateFill(f, Style.color.mover)
	f.border = Style:CreateBorder(f)
	f.border:SetColor(Style:GetAccent())

	local label = Style:CreateText(f, 11)
	label:SetPoint('CENTER', 0, 4)
	label:SetPoint('LEFT', f, 'LEFT', 2, 0)
	label:SetPoint('RIGHT', f, 'RIGHT', -2, 0)
	label:SetJustifyH('CENTER')
	label:SetWordWrap(false)
	label:SetText(DisplayName)
	f.label = label
	f.DisplayName = label

	local subtitle = Style:CreateText(f, 9, Style.color.muted)
	subtitle:SetPoint('TOP', label, 'BOTTOM', 0, -1)
	subtitle:SetPoint('LEFT', f, 'LEFT', 2, 0)
	subtitle:SetPoint('RIGHT', f, 'RIGHT', -2, 0)
	subtitle:SetJustifyH('CENTER')
	subtitle:SetWordWrap(false)
	f.subtitle = subtitle

	-- Older code shows and hides these to flag a moved or scaled frame
	local textProxy = {
		Show = function()
			MoveIt:UpdateMoverText(f)
		end,
		Hide = function()
			MoveIt:UpdateMoverText(f)
		end,
	}
	f.MovedText = textProxy
	f.ScaledText = textProxy

	self.MoverList[name] = f

	if MoveIt.MagnetismManager then
		MoveIt.MagnetismManager:RegisterFrame(f)
	end

	f:SetScale(MoveIt.DB.movers[name].AdjustedScale or parent:GetScale() or 1)
	if MoveIt.DB.movers[name].AdjustedScale then
		parent:SetScale(MoveIt.DB.movers[name].AdjustedScale)
	end

	if MoveIt.DB.movers[name].MovedPoints then
		point, anchor, secondaryPoint, x, y = strsplit(',', MoveIt.DB.movers[name].MovedPoints)
	end

	-- Validate anchor frame. Reject missing frames and frames that aren't rooted at UIParent
	-- (e.g. textures or frames inside SpartanUI's scaled tree), as those cause position drift.
	local anchorObj = anchor
	if type(anchor) == 'string' then
		anchorObj = _G[anchor]
	end

	-- A saved position can point at another mover that has not been created yet (load order).
	-- Keep the saved position, use the default for now, and re-apply once that mover exists.
	if not anchorObj and MoveIt.DB.movers[name].MovedPoints and type(anchor) == 'string' and anchor:find('^SUI_Mover_') then
		MoveIt.PendingAnchors[name] = anchor
		point, anchor, secondaryPoint, x, y = strsplit(',', f.defaultPoint)
		anchorObj = _G[anchor]
	end

	local anchorInvalid = not anchorObj
	if anchorObj and type(anchor) == 'string' and anchor ~= 'UIParent' then
		-- Walk up the parent chain looking for UIParent. If we hit SpartanUI (which is scaled),
		-- the anchor is inside a scaled frame and offsets will drift.
		local p = anchorObj.GetParent and anchorObj:GetParent()
		while p and p ~= UIParent do
			if p == SpartanUI then
				anchorInvalid = true
				break
			end
			p = p.GetParent and p:GetParent()
		end
	end
	if type(anchor) == 'string' and anchor ~= 'UIParent' and anchorInvalid then
		if MoveIt.logger then
			MoveIt.logger.debug(('CreateMover %s: anchor %s is invalid or inside scaled frame, falling back to UIParent'):format(name, anchor))
		end
		anchor = 'UIParent'
		if not MoveIt.PendingAnchors[name] then
			MoveIt.DB.movers[name].MovedPoints = nil
		end
	end

	f:ClearAllPoints()
	f:SetPoint(point, anchor, secondaryPoint, tonumber(x) or 0, tonumber(y) or 0)

	local function OnDragStart(self)
		if InCombatLockdown() then
			return
		end
		if MoveIt.MoverMode:IsActive() then
			MoveIt.MoverMode:StartDrag(self)
		else
			self:StartMoving()
		end
	end

	local function OnDragStop(self)
		if MoveIt.MoverMode:IsDragging(self) then
			MoveIt.MoverMode:StopDrag(self)
			return
		end
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
		if not InCombatLockdown() then
			MoveIt:SaveMover(self)
		end
	end

	local function OnMouseDown(self, button)
		if InCombatLockdown() then
			return
		end
		if IsAltKeyDown() and button == 'LeftButton' then
			MoveIt:Reset(name, true)
		elseif IsControlKeyDown() and button == 'LeftButton' then
			MoveIt:SetMoverScale(self, nil)
		elseif IsShiftKeyDown() and button == 'RightButton' then
			self:Hide()
		elseif MoveIt.MoverMode:IsActive() then
			MoveIt.MoverMode:OnMoverClicked(self, button)
		end
	end

	local function OnMouseWheel(self, delta)
		if InCombatLockdown() then
			return
		end
		if IsAltKeyDown() then
			MoveIt:SetMoverScale(self, (self:GetScale() or 1) + delta * 0.01)
		elseif IsShiftKeyDown() then
			MoveIt:NudgeMover(self, 0, delta)
		else
			MoveIt:NudgeMover(self, delta, 0)
		end
		if MoveIt.MoverMode:IsActive() then
			MoveIt.MoverMode:RefreshMover(self)
		end
	end

	f:SetScript('OnDragStart', OnDragStart)
	f:SetScript('OnDragStop', OnDragStop)
	f:SetScript('OnMouseDown', OnMouseDown)
	f:SetScript('OnMouseWheel', OnMouseWheel)
	f:SetScript('OnEnter', function(self)
		MoveIt.MoverMode:SetHovered(self, true)
	end)
	f:SetScript('OnLeave', function(self)
		MoveIt.MoverMode:SetHovered(self, false)
	end)

	-- Kept for callers written against the older mover
	f.NudgeMover = function(self, nudgeX, nudgeY)
		MoveIt:NudgeMover(self, nudgeX or 0, nudgeY or 0)
	end
	f.Scale = function(self, amount)
		MoveIt:SetMoverScale(self, (self:GetScale() or 1) + (amount or 0))
	end

	local DragMoving = false
	local function ParentMouseDown(self)
		if IsAltKeyDown() and MoveIt.DB.AltKey and self.mover then
			OnDragStart(self.mover)
			DragMoving = true
		end
	end
	local function ParentMouseUp(self)
		if DragMoving and self.mover then
			DragMoving = false
			OnDragStop(self.mover)
		end
	end

	local function scale(self, newScale, setDefault, forced)
		if setDefault then
			f.defaultScale = newScale
		end

		-- If user has adjusted scale and we're not forcing, don't change anything
		if MoveIt.DB.movers[name].AdjustedScale and not forced then
			return
		end

		-- A moved frame keeps its scale: the saved offsets were measured at this scale
		if MoveIt.DB.movers[name].MovedPoints and not forced then
			return
		end

		local value = max((newScale or f.defaultScale), 0.01)
		f:SetScale(value)
		parent:SetScale(value)
		MoveIt:UpdateMoverText(f)

		local p, a, sp, px, py = strsplit(',', MoveIt.DB.movers[name].MovedPoints or f.defaultPoint)
		px = tonumber(px) or 0
		py = tonumber(py) or 0

		-- Validate anchor frame exists (it may reference a disabled unit frame's mover)
		if type(a) == 'string' and a ~= 'UIParent' and not _G[a] then
			a = 'UIParent'
		end

		f:ClearAllPoints()
		f:SetPoint(p, a, sp, px, py)
	end

	local function position(self, newPoint, newAnchor, newSecondaryPoint, newX, newY, forced, defaultPos)
		-- If Frame:position() was called just make sure we are anchored properly
		if not newPoint then
			self:ClearAllPoints()
			self:SetPoint('TOPLEFT', self.mover, 0, 0)
			return
		end

		-- If the frame has been moved and we are not forcing the movement, exit
		if MoveIt.DB.movers[name].MovedPoints and not forced then
			return
		end

		f:ClearAllPoints()
		f:SetPoint(newPoint, (newAnchor or UIParent), (newSecondaryPoint or newPoint), (newX or 0), (newY or 0))

		if newAnchor and newAnchor ~= UIParent and self.mover and MoveIt.MagnetismManager then
			local anchorFrame = newAnchor
			if type(newAnchor) == 'string' then
				anchorFrame = _G[newAnchor]
			end
			if anchorFrame and anchorFrame.mover then
				MoveIt.MagnetismManager:RegisterFrameRelationship(self.mover, anchorFrame.mover)
			end
		end

		if defaultPos then
			f.defaultPoint = GetPoints(f)
		end
	end

	local function SizeChanged(frame)
		if InCombatLockdown() or not frame.mover then
			return
		end
		if frame.mover.updateObj then
			frame.mover:SetSize(frame.mover.updateObj:GetSize())
		else
			frame.mover:SetSize(frame:GetSize())
		end
	end

	hooksecurefunc(parent, 'SetSize', SizeChanged)
	hooksecurefunc(parent, 'SetHeight', SizeChanged)
	hooksecurefunc(parent, 'SetWidth', SizeChanged)

	parent:HookScript('OnMouseDown', ParentMouseDown)
	parent:HookScript('OnMouseUp', ParentMouseUp)

	parent.scale = scale
	parent.position = position
	parent.mover = f
	parent.dirtyWidth = 0
	parent.dirtyHeight = 0
	parent.isMoved = function()
		return MoveIt.DB.movers[name].MovedPoints and true or false
	end

	parent:ClearAllPoints()
	parent:SetPoint('TOPLEFT', f, 0, 0)

	-- Blizz mover holders intercept mouse events when visible (HookScript enables mouse).
	-- Hide them immediately; MoverMode:Enter/Exit manages their visibility.
	if parent.isBlizzMoverHolder then
		parent:Hide()
	end

	self:UpdateMoverText(f)
	self:AddToOptions(name, DisplayName, f.groupName, f)
	MoveIt:ResolvePendingAnchors()
end

---@class SUI.MoveIt.ElementOptions
---@field frame Frame The frame to move
---@field key string Unique mover name, used for saved positions
---@field label? string Name shown on the mover
---@field group? string Group shown in options and the move mode filter
---@field optionsPath? string[] Options page the mover's Settings button opens
---@field noScale? boolean The frame cannot be scaled
---@field isAvailable? fun(): boolean Return false to hide the mover (for example a disabled bar)
---@field onMoved? fun(mover: SUI.MoveIt.Mover) Called after the frame is moved or reset

---Register a frame with the mover system using named options
---@param opts SUI.MoveIt.ElementOptions
---@return SUI.MoveIt.Mover|nil
function MoveIt:RegisterElement(opts)
	self:CreateMover(opts.frame, opts.key, opts.label, opts.onMoved, opts.group)
	local mover = self.MoverList[opts.key]
	if not mover then
		return nil
	end
	mover.optionsPath = opts.optionsPath
	mover.noScale = opts.noScale
	if opts.isAvailable then
		mover.IsMoverAvailable = function()
			return opts.isAvailable()
		end
	end
	return mover
end

---Give a frame back its own positioning. The frame stays where it is on screen.
---@param name string
function MoveIt:ReleaseMover(name)
	local mover = self.MoverList[name]
	if not mover or InCombatLockdown() then
		return
	end
	local parent = mover.parent
	if MoveIt.MoverMode:IsActive() then
		MoveIt.MoverMode:ForgetMover(mover)
	end
	mover:Hide()
	self.MoverList[name] = nil
	self.PendingAnchors[name] = nil
	if parent then
		local left, bottom = parent:GetLeft(), parent:GetBottom()
		parent.mover = nil
		parent.position = nil
		parent.scale = nil
		parent.isMoved = nil
		-- GetLeft/GetBottom are already in the frame's own units, which is what SetPoint offsets use
		if left and bottom then
			parent:ClearAllPoints()
			parent:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMLEFT', left, bottom)
		end
	end
	if SUI.opt.args.Movers and SUI.opt.args.Movers.args[mover.groupName] then
		SUI.opt.args.Movers.args[mover.groupName].args[name] = nil
	end
end

function MoveIt:RegisterExternalMover(mover, name)
	if not mover or not name then
		return
	end

	if not self.MoverList[name] then
		self.MoverList[name] = mover
		mover.name = name

		return true
	end
	return false
end

---A free-standing mover that stores its position through callbacks instead of the MoveIt database
---@param displayName string
---@param defaultPosition string "POINT,Anchor,RELPOINT,x,y"
---@param config? table { width, height, savePosition = fn(positionString), onPositionChanged = fn(mover), onHide = fn() }
---@return Button
function MoveIt:CreateCustomMover(displayName, defaultPosition, config)
	local name = 'SUI_CustomMover_' .. displayName:gsub('%s+', '')

	local cfg = {
		width = 180,
		height = 180,
		onPositionChanged = nil,
		savePosition = nil,
		onHide = nil,
	}
	if config then
		for k, v in pairs(config) do
			cfg[k] = v
		end
	end

	local mover = CreateFrame('Button', name, UIParent)
	mover:SetClampedToScreen(true)
	mover:RegisterForDrag('LeftButton', 'RightButton')
	mover:EnableMouseWheel(true)
	mover:SetMovable(true)
	mover:SetSize(cfg.width, cfg.height)
	mover:Hide()
	mover.defaultPoint = defaultPosition
	mover.displayName = displayName
	mover.savedPosition = nil
	mover:SetFrameLevel(100)
	mover:SetFrameStrata('DIALOG')

	mover.fill = Style:CreateFill(mover, Style.color.mover)
	mover.border = Style:CreateBorder(mover)
	Style:OnAccentChanged(mover, function(r, g, b)
		mover.border:SetColor(r, g, b, 0.8)
	end)

	local nameText = Style:CreateText(mover, 12)
	nameText:SetPoint('CENTER')
	nameText:SetText(displayName)
	mover.DisplayName = nameText

	local helpText = Style:CreateText(mover, 9, Style.color.muted)
	helpText:SetPoint('TOP', nameText, 'BOTTOM', 0, -2)
	helpText:SetText(L['Drag to set position'])
	mover.HelpText = helpText

	local point, anchor, secondaryPoint, x, y = strsplit(',', defaultPosition)
	mover:ClearAllPoints()
	mover:SetPoint(point, _G[anchor] or UIParent, secondaryPoint, tonumber(x) or 0, tonumber(y) or 0)

	local function SavePosition(self)
		local p, a, sp, px, py = self:GetPoint()
		local anchorName = (a and a:GetName()) or 'UIParent'
		self.savedPosition = format('%s,%s,%s,%d,%d', p, anchorName, sp, Round(px), Round(py))
		if cfg.savePosition then
			cfg.savePosition(self.savedPosition)
		end
		if cfg.onPositionChanged then
			cfg.onPositionChanged(self)
		end
	end

	mover:SetScript('OnDragStart', function(self)
		if InCombatLockdown() then
			return
		end
		self:StartMoving()
	end)
	mover:SetScript('OnDragStop', function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
		SavePosition(self)
	end)
	mover:SetScript('OnEnter', function(self)
		self.fill:SetVertexColor(Style.color.mover[1] + 0.05, Style.color.mover[2] + 0.05, Style.color.mover[3] + 0.05, 1)
	end)
	mover:SetScript('OnLeave', function(self)
		self.fill:SetVertexColor(unpack(Style.color.mover))
	end)
	mover:SetScript('OnMouseDown', function(self, button)
		if InCombatLockdown() then
			return
		elseif IsAltKeyDown() then
			self:Hide()
			if cfg.onHide then
				cfg.onHide()
			end
			return
		end

		if button == 'RightButton' then
			local dp, da, dsp, dx, dy = strsplit(',', self.defaultPoint)
			self:ClearAllPoints()
			self:SetPoint(dp, _G[da] or UIParent, dsp, tonumber(dx) or 0, tonumber(dy) or 0)
			self.savedPosition = nil
			if cfg.savePosition then
				cfg.savePosition(self.defaultPoint)
			end
			SUI:Print(L['Position reset to default'])
		end
	end)
	mover:SetScript('OnMouseWheel', function(self, delta)
		local p, a, sp, px, py = self:GetPoint()
		self:ClearAllPoints()
		if IsShiftKeyDown() then
			self:SetPoint(p, a or UIParent, sp, px, py + delta)
		else
			self:SetPoint(p, a or UIParent, sp, px + delta, py)
		end
	end)
	mover:SetScript('OnKeyDown', function(self, key)
		if key == 'ESCAPE' then
			self:Hide()
			if cfg.onHide then
				cfg.onHide()
			end
		end
	end)
	mover:EnableKeyboard(true)

	tinsert(UISpecialFrames, name)
	self.MoverList[name] = mover
	mover.isCustomMover = true

	return mover
end
