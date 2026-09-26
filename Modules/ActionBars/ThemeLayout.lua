---@type SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.ActionBars
local module = SUI:GetModule('ActionBars')

-- Themes describe bar positions and scales with Bartender4 bar names. SpartanUI's own bars
-- use those names as their keys, so the same theme data drives both bar systems.

-- Matches the Bartender4 handler: SUI.DB.scale defaults to 0.92, and 1 / 0.92 cancels it
-- out so a theme's bar scale applies as written at the default UI scale.
local SCALE_NORMALIZER = 1.08696

---@return table<string, string> positions
---@return table<string, number> scales
function module:GetThemeLayout()
	local BarSystem = SUI.Handlers.BarSystem
	local style = SUI:IsModuleEnabled('Artwork') and SUI:GetActiveStyle() or nil

	local positions = SUI:CopyData({}, BarSystem.BarPosition.BT4.default)
	if style and BarSystem.BarPosition.BT4[style] then
		positions = SUI:MergeData(positions, BarSystem.BarPosition.BT4[style], true)
	end

	local scales = SUI:CopyData({}, BarSystem.BarScale.BT4.default)
	if style and BarSystem.BarScale.BT4[style] then
		scales = SUI:MergeData(scales, BarSystem.BarScale.BT4[style], true)
	end
	scales = SUI:MergeData(scales, BarSystem.DB.custom.scale.BT4, true)
	return positions, scales
end

---Turn a theme position string into SetPoint arguments, pointing Bartender4 bar names at
---the matching SpartanUI bar.
---@param position string
---@return string|nil point
---@return string|nil anchor
---@return string|nil relativePoint
---@return number x
---@return number y
function module:ParsePosition(position)
	if type(position) ~= 'string' or position == '' then
		return nil, nil, nil, 0, 0
	end
	local point, anchor, relativePoint, x, y = strsplit(',', position)
	if anchor and self.bars[anchor] then
		anchor = self.bars[anchor]:GetName()
	end
	if not anchor or not _G[anchor] then
		anchor = 'UIParent'
	end
	return point, anchor, relativePoint or point, tonumber(x) or 0, tonumber(y) or 0
end

local FALLBACK_POSITIONS = {
	BT4BarPetBar = 'BOTTOM,UIParent,BOTTOM,-300,200',
	BT4BarStanceBar = 'BOTTOM,UIParent,BOTTOM,-300,240',
	BT4BarMicroMenu = 'BOTTOMRIGHT,UIParent,BOTTOMRIGHT,-300,4',
	BT4BarBagBar = 'BOTTOMRIGHT,UIParent,BOTTOMRIGHT,-4,4',
	BT4BarQueueStatus = 'BOTTOMRIGHT,UIParent,BOTTOMRIGHT,-340,60',
}

---Where a bar sits when neither the theme nor the player has placed it.
---@param key string
---@return string point
---@return Frame|string anchor
---@return string relativePoint
---@return number x
---@return number y
function module:GetFallbackPoint(key)
	local positions = self:GetThemeLayout()
	local point, anchor, relativePoint, x, y = self:ParsePosition(positions[key])
	if point then
		return point, anchor, relativePoint, x, y
	end
	if FALLBACK_POSITIONS[key] then
		return self:ParsePosition(FALLBACK_POSITIONS[key])
	end
	-- Bars without a theme slot line up in rows above the screen's bottom centre
	local order = { 2, 7, 8, 9, 10, 13, 14, 15 }
	local id = tonumber(key:match('^BT4Bar(%d+)$')) or 1
	local row = 1
	for i, barID in ipairs(order) do
		if barID == id then
			row = i
		end
	end
	return 'BOTTOM', 'UIParent', 'BOTTOM', 0, 180 + (row - 1) * 50
end

---Apply the theme's position and scale to one bar. A bar the player moved or scaled keeps
---their placement.
---@param bar SUI.ActionBars.Bar
---@param positions? table<string, string>
---@param scales? table<string, number>
function module:ApplyThemeToBar(bar, positions, scales)
	if not positions or not scales then
		positions, scales = self:GetThemeLayout()
	end
	local key = bar.key
	-- A theme that placed this bar itself (sliding trays) keeps that placement
	local override = self.themeOverrides and self.themeOverrides[key]
	if override then
		positions = setmetatable({ [key] = override }, { __index = positions })
	end
	local MoveIt = SUI:GetModule('MoveIt', true) ---@type MoveIt
	local uiScale = SUI.DB.scale or 0.92
	local themeScale = scales[key] or scales.BT4Bar1 or 1
	local point, anchor, relativePoint, x, y = self:ParsePosition(positions[key])
	if bar.mover then
		local moverData = MoveIt and MoveIt.DB and MoveIt.DB.movers and MoveIt.DB.movers[key]
		if bar.scale and not (moverData and moverData.AdjustedScale) then
			bar:scale(uiScale * themeScale * SCALE_NORMALIZER, true, true)
		end
		if point and bar.position then
			bar:position(point, anchor, relativePoint, x, y, false, true)
		end
	else
		-- Without MoveIt there is nothing to remember a player's placement, so the theme decides
		bar:SetScale(uiScale * themeScale * SCALE_NORMALIZER)
		if point then
			bar:ClearAllPoints()
			bar:SetPoint(point, anchor, relativePoint, x, y)
		end
	end
end

---Let a theme place a bar somewhere other than its registered position, for example inside a
---sliding tray. Kept until the theme changes.
---@param key string
---@param point string
---@param anchor Frame|string
---@param relativePoint string
---@param x number
---@param y number
function module:SetThemeOverride(key, point, anchor, relativePoint, x, y)
	self.themeOverrides = self.themeOverrides or {}
	local anchorName = anchor or 'UIParent'
	if type(anchor) == 'table' then
		anchorName = anchor:GetName() or 'UIParent'
	end
	self.themeOverrides[key] = ('%s,%s,%s,%s,%s'):format(point, anchorName, relativePoint or point, x or 0, y or 0)
	self.themeOverrideStyle = SUI:GetActiveStyle()
	local bar = self.bars[key]
	if bar and self.active then
		self:RunOutOfCombat('themebar:' .. key, self.ApplyThemeToBar, self, bar)
	end
end

---Apply theme positions and scales to every bar.
function module:ApplyThemeLayout()
	if not self.active then
		return
	end
	if InCombatLockdown() then
		self:RunOutOfCombat('themelayout', self.ApplyThemeLayout, self)
		return
	end
	-- Overrides belong to the theme that set them
	if self.themeOverrideStyle and self.themeOverrideStyle ~= SUI:GetActiveStyle() then
		self.themeOverrides = nil
		self.themeOverrideStyle = nil
	end
	local positions, scales = self:GetThemeLayout()
	for _, bar in pairs(self.bars) do
		self:ApplyThemeToBar(bar, positions, scales)
	end
end

---Frames registered with MoveIt, for the "move bars" button.
---@return string[]
function module:GetMoverNames()
	local names = {}
	for key, bar in pairs(self.bars) do
		if bar.mover and bar:GetDB().enabled and not bar.forceHidden then
			names[#names + 1] = key
		end
	end
	return names
end

----------------------------------------------------------------------------------------------------
-- Drag-and-drop reveal
----------------------------------------------------------------------------------------------------

local gridWatcher = CreateFrame('Frame')
gridWatcher:RegisterEvent('ACTIONBAR_SHOWGRID')
gridWatcher:RegisterEvent('ACTIONBAR_HIDEGRID')
gridWatcher:SetScript('OnEvent', function(_, event)
	if not module.active then
		return
	end
	-- Hidden and faded bars reappear while dragging a spell so it can be dropped on them
	module.gridShown = event == 'ACTIONBAR_SHOWGRID' or module.keyBoundMode
	for _, bar in pairs(module.bars) do
		bar:UpdateFade()
	end
	module:UpdateGlobalFade()
end)

----------------------------------------------------------------------------------------------------
-- Bar system registration
----------------------------------------------------------------------------------------------------

local BarSystem = SUI.Handlers.BarSystem
BarSystem:AddBarSystem(
	'SpartanUI',
	function() end,
	function()
		module:Activate()
	end,
	nil,
	function()
		-- The standard move mode: clicking again, Escape or its toolbar all leave it
		local MoveIt = SUI:GetModule('MoveIt', true) ---@type MoveIt
		if MoveIt and MoveIt.MoverMode then
			MoveIt.MoverMode:Toggle()
		end
	end,
	function()
		module:ApplyThemeLayout()
	end
)
