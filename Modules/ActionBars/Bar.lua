---@type SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.ActionBars
local module = SUI:GetModule('ActionBars')

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local BACKDROP = {
	bgFile = 'Interface\\Buttons\\WHITE8x8',
	edgeFile = 'Interface\\Buttons\\WHITE8x8',
	edgeSize = 1,
}

---@class SUI.ActionBars.Bar : Frame, SecureHandlerStateTemplate
---@field key string Logical key shared with themes and movers (BT4Bar1, BT4BarPetBar ...)
---@field displayName string
---@field buttons Button[]
---@field numButtons number Buttons currently laid out
---@field GetDB fun(self): table Current merged settings for this bar
---@field UpdateButtons? fun(self) Subclass hook: create/refresh buttons before layout
---@field PostApply? fun(self) Subclass hook after all settings are applied
local Bar = {}

---Create a new bar frame. Bars are secure state headers so their visibility and paging
---can be driven by macro conditions in combat.
---@param key string
---@param frameName string
---@param displayName string
---@param getDB fun(): table
---@return SUI.ActionBars.Bar
function module:NewBar(key, frameName, displayName, getDB)
	local bar = CreateFrame('Frame', frameName, UIParent, 'SecureHandlerStateTemplate') ---@type SUI.ActionBars.Bar
	Mixin(bar, Bar)
	bar.key = key
	bar.displayName = displayName
	bar.buttons = {}
	bar.numButtons = 0
	bar.GetDB = function()
		return getDB()
	end
	bar:SetMovable(true)
	bar:SetClampedToScreen(false)
	bar:SetSize(1, 1)

	local backdrop = CreateFrame('Frame', nil, bar, BackdropTemplateMixin and 'BackdropTemplate')
	backdrop:SetAllPoints()
	backdrop:SetFrameLevel(max(bar:GetFrameLevel() - 1, 0))
	backdrop:SetBackdrop(BACKDROP)
	backdrop:Hide()
	bar.backdrop = backdrop

	bar:HookScript('OnEnter', Bar.OnEnterBar)
	bar:HookScript('OnLeave', Bar.OnLeaveBar)

	self.bars[key] = bar
	return bar
end

----------------------------------------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------------------------------------

-- Native button sizes, captured before SpartanUI ever touches a button. Kept in a side
-- table so nothing is written onto Blizzard's own button frames.
local nativeSizes = setmetatable({}, { __mode = 'k' })

---@param button Button
---@return number width
---@return number height
local function GetNativeSize(button)
	local size = nativeSizes[button]
	if not size then
		local w, h = button:GetSize()
		size = { w = (w and w > 0) and w or 36, h = (h and h > 0) and h or 36 }
		nativeSizes[button] = size
	end
	return size.w, size.h
end
module.GetNativeButtonSize = GetNativeSize

---Undo SpartanUI's scaling on a button handed back to Blizzard.
---@param button Button
function module:RestoreButtonSize(button)
	local w, h = GetNativeSize(button)
	button:SetScale(1)
	button:SetSize(w, h)
end

---Size a bar needs for `count` buttons with the given settings.
---@param db table
---@param count number
---@return number width
---@return number height
function module:CalculateBarSize(db, count)
	local width = db.buttonSize or module.DEFAULT_BUTTON_SIZE
	local height = db.keepSizeRatio ~= false and width or (db.buttonHeight or width)
	local spacing = db.buttonSpacing or 0
	local margin = db.backdropSpacing or 0
	if count <= 0 then
		return max(width, 1), max(height, 1)
	end
	local perRow = max(1, min(db.buttonsPerRow or count, count))
	local rows = ceil(count / perRow)
	return perRow * width + (perRow - 1) * spacing + margin * 2, rows * height + (rows - 1) * spacing + margin * 2
end

---Lay out the first `count` buttons in a grid growing away from `db.point`.
---Buttons are scaled rather than resized: Blizzard's button art has fixed-size textures
---that misalign when the frame itself changes size, while scaling keeps it intact.
---@param count number
function Bar:LayoutButtons(count)
	local db = self:GetDB()
	local buttons = self.buttons
	count = min(count or #buttons, #buttons)
	self.numButtons = count

	local width = db.buttonSize or module.DEFAULT_BUTTON_SIZE
	local height = db.keepSizeRatio ~= false and width or (db.buttonHeight or width)
	local spacing = db.buttonSpacing or 0
	local margin = db.backdropSpacing or 0

	self:SetSize(module:CalculateBarSize(db, count))
	if count == 0 then
		if not self.manageButtonVisibility then
			for _, button in ipairs(buttons) do
				button:Hide()
			end
		end
		return
	end

	local perRow = max(1, min(db.buttonsPerRow or count, count))

	local point = db.point or 'TOPLEFT'
	local xDir = point:find('RIGHT') and -1 or 1
	local yDir = point:find('BOTTOM') and 1 or -1

	for i, button in ipairs(buttons) do
		if i <= count then
			local _, nativeHeight = GetNativeSize(button)
			local scale = height / nativeHeight
			local col = (i - 1) % perRow
			local row = floor((i - 1) / perRow)
			button:SetParent(self.buttonParent or self)
			button:SetScale(scale)
			button:SetSize(width / scale, nativeHeight)
			button:ClearAllPoints()
			button:SetPoint(point, self, point, xDir * (margin + col * (width + spacing)) / scale, yDir * (margin + row * (height + spacing)) / scale)
			if not self.manageButtonVisibility then
				button:Show()
			end
			self:StyleButton(button, db)
		elseif not self.manageButtonVisibility then
			button:Hide()
		end
	end
end

---Shared visual styling for every button type.
---@param button Button
---@param db table
function Bar:StyleButton(button, db)
	-- Only spell icons get cropped; micro and bag buttons use atlas art that texcoords would break
	local icon = self.cropIcons and (button.icon or button.Icon)
	if icon and not module.masqueGroups[self.key] then
		if db.zoom then
			icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		else
			icon:SetTexCoord(0, 1, 0, 1)
		end
	end
	button:EnableMouse(not db.clickThrough)
end

----------------------------------------------------------------------------------------------------
-- Visibility and fading
----------------------------------------------------------------------------------------------------

---Validate a macro-condition visibility string, falling back to 'show' if it is broken.
---@param conditions string|nil
---@return string
local function SafeConditions(conditions)
	if type(conditions) ~= 'string' or conditions:gsub('%s', '') == '' then
		return 'show'
	end
	local ok, result = pcall(SecureCmdOptionParse, conditions)
	if not ok or (result ~= nil and result ~= 'show' and result ~= 'hide' and result ~= '') then
		return 'show'
	end
	return conditions
end
module.SafeConditions = SafeConditions

function Bar:UpdateVisibility()
	local db = self:GetDB()
	UnregisterStateDriver(self, 'visibility')
	if not db.enabled or self.forceHidden then
		self:Hide()
		return
	end
	if self.trayHidden then
		RegisterStateDriver(self, 'visibility', 'hide')
		return
	end
	local conditions = SafeConditions(db.visibility)
	-- Blizzard's vehicle bar takes over in vehicles when the player chose to use it
	if self.hideInBlizzardVehicle and module:UseBlizzardVehicleUI() then
		conditions = '[overridebar][vehicleui] hide; ' .. conditions
	end
	RegisterStateDriver(self, 'visibility', conditions)
end

---Sliding trays collapse some bars out of sight.
---@param hidden boolean
function Bar:SetTrayHidden(hidden)
	if self.trayHidden == hidden then
		return
	end
	self.trayHidden = hidden
	if InCombatLockdown() then
		module:RunOutOfCombat('tray:' .. self.key, self.UpdateVisibility, self)
		return
	end
	self:UpdateVisibility()
end

function Bar:IsMouseInside()
	if self:IsMouseOver() then
		return true
	end
	local flyout = module.GetFlyoutFrame and module:GetFlyoutFrame()
	if flyout and flyout:IsShown() and flyout:IsMouseOver() then
		local parent = flyout:GetParent()
		return parent and parent.GetParent and parent:GetParent() == self
	end
	return false
end

function Bar:UpdateFade()
	local db = self:GetDB()
	local alpha = db.alpha or 1
	if db.mouseover and not self.mouseInside and not module.gridShown and not self.keepVisible then
		alpha = db.mouseoverAlpha or 0
	end
	self:SetAlpha(alpha)
end

function Bar:OnEnterBar()
	self.mouseInside = true
	self:UpdateFade()
	if self:GetDB().inheritGlobalFade then
		module:SetFadeHover(true)
	end
end

function Bar:OnLeaveBar()
	-- Moving between buttons fires leave on the old button before enter on the next one,
	-- so only drop the hover state once the cursor has truly left the bar.
	if self:IsMouseInside() then
		return
	end
	self.mouseInside = false
	self:UpdateFade()
	if module.fadeHover then
		module:SetFadeHover(false)
	end
end

-- Buttons already hooked for hover, tracked here so nothing is written onto Blizzard's frames
local hoverHooked = setmetatable({}, { __mode = 'k' })

---Hook a child so hovering it counts as hovering the bar.
---@param child Frame
function Bar:RegisterHoverChild(child)
	if hoverHooked[child] then
		return
	end
	hoverHooked[child] = true
	local bar = self
	child:HookScript('OnEnter', function()
		bar:OnEnterBar()
	end)
	child:HookScript('OnLeave', function()
		bar:OnLeaveBar()
	end)
end

function Bar:UpdateBackdrop()
	local db = self:GetDB()
	if db.backdrop then
		local colors = module.CurrentSettings.backdropColors or {}
		local bg = colors.background or { 0, 0, 0, 0.5 }
		local border = colors.border or { 0, 0, 0, 1 }
		self.backdrop:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 0.5)
		self.backdrop:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
		self.backdrop:Show()
	else
		self.backdrop:Hide()
	end
end

function Bar:UpdateParent()
	local db = self:GetDB()
	local parent = (db.inheritGlobalFade and module.fadeParent) or UIParent
	if self:GetParent() ~= parent then
		self:SetParent(parent)
	end
end

----------------------------------------------------------------------------------------------------
-- Movers
----------------------------------------------------------------------------------------------------

function Bar:EnsureMover()
	if not self:GetPoint() then
		self:ClearAllPoints()
		self:SetPoint(module:GetFallbackPoint(self.key))
	end
	if self.mover or SUI:IsModuleDisabled('MoveIt') then
		return
	end
	local MoveIt = SUI:GetModule('MoveIt') ---@type MoveIt
	MoveIt:CreateMover(self, self.key, self.displayName, nil, L['Action Bars'])
	local mover = MoveIt.MoverList[self.key]
	if mover then
		local bar = self
		-- Disabled bars should not show a mover in move mode
		mover.IsMoverAvailable = function()
			local db = bar:GetDB()
			return db and db.enabled and not bar.forceHidden
		end
		MoveIt:UpdateMover(self.key, self, true)
	end
end

----------------------------------------------------------------------------------------------------
-- Apply
----------------------------------------------------------------------------------------------------

---Apply every setting for this bar. Must run out of combat.
function Bar:Apply()
	if InCombatLockdown() then
		module:RunOutOfCombat('bar:' .. self.key, self.Apply, self)
		return
	end
	local db = self:GetDB()
	if not db then
		return
	end

	self:UpdateParent()

	if self.UpdateButtons then
		self:UpdateButtons()
	end

	self:UpdateBackdrop()
	-- Empty strata and level zero leave the frame's own layering alone
	if db.frameStrata and db.frameStrata ~= '' then
		self:SetFrameStrata(db.frameStrata)
	end
	if db.frameLevel and db.frameLevel > 0 then
		self:SetFrameLevel(db.frameLevel)
	end
	self:EnableMouse(not db.clickThrough and db.mouseover)
	self:UpdateVisibility()
	self:UpdateFade()

	if db.enabled and not self.forceHidden then
		self:EnsureMover()
	end
	if self.mover then
		local MoveIt = SUI:GetModule('MoveIt') ---@type MoveIt
		MoveIt:UpdateMover(self.key, self, true)
		if not (db.enabled and not self.forceHidden) then
			self.mover:Hide()
		end
	end

	if self.PostApply then
		self:PostApply()
	end
end

module.BarPrototype = Bar
