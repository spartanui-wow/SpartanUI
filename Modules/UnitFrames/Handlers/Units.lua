---@class SUI.UF
local UF = SUI.UF

local BuiltFrames = {} ---@type table<UnitFrameName, table>
local FrameData = {} ---@type table<UnitFrameName, table>

local Unit = {
	UnitsLoaded = {}, ---@type table<UnitFrameName, SUI.UF.Unit.Config>
	UnitsBuilt = {}, ---@type table<UnitFrameName, SUI.UF.Unit.Config>
	GroupsLoaded = {}, ---@type table<UnitFrameName, SUI.UF.Unit.Config>
	defaultConfigs = {}, ---@type table<string, SUI.UF.Unit.Settings>
}

---@param frameName string
---@param builder function
---@param settings? SUI.UF.Unit.Settings
---@param options? function
---@param groupbuilder? function
---@param updater? function
function Unit:Add(frameName, builder, settings, options, groupbuilder, updater)
	---@type SUI.UF.Unit.Settings
	local Defaults = {
		enabled = true,
		width = 180,
		scale = 1,
		moved = false,
		visibility = {
			alphaDelay = 1,
			hideDelay = 3,
			showAlways = false,
			showInCombat = true,
			showWithTarget = false,
			showInRaid = false,
			showInParty = false,
		},
		position = {
			point = 'BOTTOM',
			relativeTo = 'Frame',
			relativePoint = 'BOTTOM',
			xOfs = 0,
			yOfs = 0,
		},
		elements = {},
		config = {
			IsGroup = false,
		},
	}
	local ElementList = UF.Elements.List

	FrameData[frameName] = {
		builder = builder,
		updater = updater,
		settings = settings,
		options = options,
		groupbuilder = groupbuilder,
	}

	for elementName, elementData in pairs(ElementList) do
		Defaults.elements[elementName] = elementData.ElementSettings
	end

	Unit.defaultConfigs[frameName] = SUI:CopyData(settings, Defaults)

	Unit.UnitsLoaded[frameName] = Unit.defaultConfigs[frameName].config
	if Unit.defaultConfigs[frameName].config.IsGroup then
		Unit.GroupsLoaded[frameName] = Unit.defaultConfigs[frameName].config
	end
end

---@param frame table
function Unit:Update(frame)
	if not frame.unitOnCreate then
		local frameName = frame:GetName() or 'Unknown'
		SUI:Error('Frame missing unitOnCreate property. Frame name: ' .. frameName, 'UnitFrames')
		return
	end

	local frameData = FrameData[frame.unitOnCreate]
	if not frameData then
		SUI:Error('No FrameData found for unit: ' .. tostring(frame.unitOnCreate), 'UnitFrames')
		return
	end

	if not frameData.updater then
		return
	end

	frameData.updater(frame)

	-- Resize group holders so mover SizeChanged hook fires
	-- Only resize the holder itself, not individual child frames
	local unitName = frame.unitOnCreate
	if Unit.defaultConfigs[unitName] and Unit.defaultConfigs[unitName].config.IsGroup then
		local holder = BuiltFrames[unitName]
		if holder then
			holder:SetSize(Unit:GroupSize(unitName))
			Unit:LayoutGroupFrames(unitName)
		end
	end
end

-- Which way a frame's edge points from the previous one, per anchor point
local STEP = { TOP = { 0, -1 }, BOTTOM = { 0, 1 }, LEFT = { 1, 0 }, RIGHT = { -1, 0 } }

---The anchor points a group grows by, from its growth direction setting
---@param settings table
---@return string point How frames stack in a column
---@return string columnAnchorPoint Where new columns go
function Unit:GrowthPoints(settings)
	local map = UF.Options and UF.Options.GrowthDirectionMap
	local growth = map and (map[settings.growthDirection or 'DOWN_RIGHT'] or map.DOWN_RIGHT)
	if not growth then
		return 'TOP', 'LEFT'
	end
	return growth.point, growth.columnAnchorPoint
end

---Where each frame of a group sits, the way the game's group layout places them: the frame
---centers relative to the first frame, at scale 1, plus the size of the whole layout.
---@param frameName UnitFrameName
---@param count integer
---@param perColumn? integer Frames per column (defaults to the frame's setting)
---@return table[] offsets { {x, y}, ... }
---@return number width
---@return number height
---@return number left Left edge of the layout, relative to the first frame's center
---@return number top Top edge of the layout, relative to the first frame's center
function Unit:GroupOffsets(frameName, count, perColumn)
	local settings = UF.CurrentSettings[frameName]
	local width = settings.width or 180
	local height = UF:CalculateHeight(frameName) or 40
	local point, columnPoint = self:GrowthPoints(settings)
	perColumn = math.max(1, perColumn or settings.unitsPerColumn or count)
	local spacing = settings.columnSpacing or 0
	local step, columnStep = STEP[point] or STEP.TOP, STEP[columnPoint] or STEP.LEFT

	-- In a column each frame meets the previous one edge to edge, moved by the raw offset (as the
	-- game does it); new columns start beside the first frame of the previous column
	local dx = step[1] * width + (step[1] ~= 0 and (settings.xOffset or 0) or 0)
	local dy = step[2] * height + (step[2] ~= 0 and (settings.yOffset or 0) or 0)
	local cdx = columnStep[1] * (width + spacing)
	local cdy = columnStep[2] * (height + spacing)

	local offsets = {}
	local minX, maxX, minY, maxY = 0, 0, 0, 0
	for i = 1, math.max(1, count) do
		local column = math.floor((i - 1) / perColumn)
		local row = (i - 1) - column * perColumn
		local x, y = column * cdx + row * dx, column * cdy + row * dy
		offsets[i] = { x, y }
		minX, maxX = math.min(minX, x), math.max(maxX, x)
		minY, maxY = math.min(minY, y), math.max(maxY, y)
	end
	return offsets, maxX - minX + width, maxY - minY + height, minX - width / 2, maxY + height / 2
end

---Calculates the size of a single header's layout area.
---@param frameName UnitFrameName
---@return integer width
---@return integer height
local function SingleHeaderSize(frameName)
	local CurFrameOpt = UF.CurrentSettings[frameName]
	local unitsPerColumn = CurFrameOpt.unitsPerColumn or 10
	local maxColumns = CurFrameOpt.maxColumns or 1
	local _, width, height = Unit:GroupOffsets(frameName, unitsPerColumn * maxColumns, unitsPerColumn)
	return width, height
end

local pendingLayout = {}
local layoutWatcher = CreateFrame('Frame')
layoutWatcher:SetScript('OnEvent', function(self)
	self:UnregisterEvent('PLAYER_REGEN_ENABLED')
	for frameName in pairs(pendingLayout) do
		pendingLayout[frameName] = nil
		Unit:LayoutGroupFrames(frameName)
	end
end)

---Place the frames of a group the game does not lay out itself (boss, arena) by its growth
---direction, frames per column and offsets. Groups drawn by the game's group header are skipped.
---@param frameName UnitFrameName
function Unit:LayoutGroupFrames(frameName)
	local holder = BuiltFrames[frameName]
	local settings = UF.CurrentSettings[frameName]
	local config = holder and settings and settings.config
	if not config or not config.useUnitWatch or not holder.frames or #holder.frames == 0 then
		return
	end
	if InCombatLockdown() then
		pendingLayout[frameName] = true
		layoutWatcher:RegisterEvent('PLAYER_REGEN_ENABLED')
		return
	end
	local offsets, _, _, left, top = self:GroupOffsets(frameName, #holder.frames)
	local halfWidth, halfHeight = (settings.width or 180) / 2, (UF:CalculateHeight(frameName) or 40) / 2
	for i, frame in ipairs(holder.frames) do
		frame:ClearAllPoints()
		frame:SetPoint('TOPLEFT', holder, 'TOPLEFT', offsets[i][1] - halfWidth - left, offsets[i][2] + halfHeight - top)
	end
end

---Calculates the total size of a group frame holder.
---Mirrors Blizzard's SecureGroupHeader configureChildren size formula.
---In multi-header mode, accounts for multiple group headers laid out side by side.
---@param frameName UnitFrameName
---@return integer width
---@return integer height
function Unit:GroupSize(frameName)
	local CurFrameOpt = UF.CurrentSettings[frameName]
	local holder = BuiltFrames[frameName]

	-- Multi-header mode: sum widths of all visible group headers + group spacing
	if holder and holder.headers and #holder.headers > 1 then
		local singleW, singleH = SingleHeaderSize(frameName)
		local groupSpacing = CurFrameOpt.groupSpacing or 10
		local visibleCount = #holder.headers
		local width = visibleCount * singleW + (visibleCount - 1) * groupSpacing
		local height = singleH

		if UF.BuildDebug then
			UF:debug('GroupSize(' .. frameName .. '): multi-header mode, ' .. visibleCount .. ' groups, singleW=' .. singleW .. ' => ' .. width .. 'x' .. height)
		end

		return width, height
	end

	-- Single-header mode (original calculation)
	local width, height = SingleHeaderSize(frameName)

	if UF.BuildDebug then
		UF:debug('GroupSize(' .. frameName .. '): single-header => ' .. width .. 'x' .. height)
	end

	return width, height
end

---Build a group holder
---@param groupName string
---@return SUI.UF.Unit.Frame?
function Unit:BuildGroup(groupName)
	if not Unit.defaultConfigs[groupName].config.IsGroup then
		return
	end

	local holder = CreateFrame('Frame', 'SUI_UF_' .. groupName .. '_Holder')
	holder:Hide()
	holder:SetSize(Unit:GroupSize(groupName))

	holder.frames = {}
	holder.unitOnCreate = groupName
	holder.config = UF.Unit:GetConfig(groupName)

	BuiltFrames[groupName] = holder

	FrameData[groupName].groupbuilder(BuiltFrames[groupName])

	return BuiltFrames[groupName]
end

---Returns the unitframe object
---@param frameName UnitFrameName
---@return SUI.UF.Unit.Frame
function Unit:Get(frameName)
	-- if Unit:GetConfig(frameName).config.IsGroup then
	-- 	return Unit.GroupContainer[frameName]
	-- else
	return BuiltFrames[frameName]
	-- end
end

---Get all frames for a unit (handles both single frames and groups)
---Returns an array of frames for consistent iteration
---@param frameName UnitFrameName
---@return table[] frames Array of frames
function Unit:GetFrames(frameName)
	local unitFrame = BuiltFrames[frameName]
	if not unitFrame then
		return {}
	end

	-- Check if this is a group frame (has .frames table)
	if unitFrame.frames then
		return unitFrame.frames
	end

	-- Single frame - wrap in table for consistent iteration
	return { unitFrame }
end

---Gets the current active settings for a unit frame
---@param frameName UnitFrameName
---@return SUI.UF.Unit.Settings
function Unit:GetConfig(frameName)
	return UF.CurrentSettings[frameName] ---@type SUI.UF.Unit.Settings
end

---Adds the elements needed to the passed frame for the specified unit
---@param frameName UnitFrameName
---@param frame table
function Unit:BuildFrame(frameName, frame)
	local actualFrameName = frame:GetName() or 'Unknown'
	if UF.BuildDebug then
		UF:debug('Unit:BuildFrame ENTRY - UnitName: ' .. frameName .. ', Frame: ' .. actualFrameName)
	end

	if not FrameData[frameName] then
		if UF.BuildDebug then
			UF:debug('Unit:BuildFrame - ERROR: No FrameData found for: ' .. frameName)
		end
		return
	end

	if UF.BuildDebug then
		UF:debug('Unit:BuildFrame - Calling builder function for: ' .. frameName)
	end
	FrameData[frameName].builder(frame)
	frame.config = UF.Unit:GetConfig(frameName)

	if Unit:GetConfig(frameName).config.IsGroup then
		if UF.BuildDebug then
			UF:debug('Unit:BuildFrame - This is a group frame: ' .. frameName)
		end
		if not BuiltFrames[frameName] then
			if UF.BuildDebug then
				UF:debug('Unit:BuildFrame - ERROR: No BuiltFrames entry for group: ' .. frameName)
			end
			return
		end

		table.insert(BuiltFrames[frameName].frames, frame)
		if UF.BuildDebug then
			UF:debug('Unit:BuildFrame - Added frame to group, total frames: ' .. #BuiltFrames[frameName].frames)
		end
	else
		BuiltFrames[frameName] = frame
		if UF.BuildDebug then
			UF:debug('Unit:BuildFrame - Registered as single frame: ' .. frameName)
		end
	end

	Unit.UnitsBuilt[frameName] = frame.config.config
	if UF.BuildDebug then
		UF:debug('Unit:BuildFrame EXIT - Frame built: ' .. actualFrameName)
	end
end

---Gets a table of all the frames that are currently built and their default settings
---@return table<UnitFrameName, SUI.UF.Unit.Config>
function Unit:GetBuiltFrameList()
	return Unit.UnitsBuilt
end

---Gets a table of all the frames that are currently loaded and their default settings
---@param onlyGroups any
---@return table<UnitFrameName, SUI.UF.Unit.Config>
function Unit:GetFrameList(onlyGroups)
	if onlyGroups then
		return Unit.GroupsLoaded
	end

	return Unit.UnitsLoaded
end

---Used to add unit specific frame options to the passes OptionSet
---@param frameName UnitFrameName
---@param OptionsSet AceConfig.OptionsTable
function Unit:BuildOptions(frameName, OptionsSet)
	if not FrameData[frameName] or not FrameData[frameName].options then
		return
	end

	FrameData[frameName].options(OptionsSet)
end

---Returns if the frame is used to display friendly units
---@param unit UnitFrameName
---@return boolean
function Unit:isFriendly(unit)
	local config = Unit:GetConfig(unit)

	if not unit then
		return false
	end

	return config.config.isFriendly
end

UF.Unit = Unit
