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
		end
	end
end

---Calculates the total size of a group frame holder.
---Mirrors Blizzard's SecureGroupHeader configureChildren size formula.
---All current group frames use vertical layout (point=TOP) where:
---  singleColumnHeight = (unitsPerColumn - 1) * (frameHeight + ySpacing) + frameHeight
---  singleColumnWidth = frameWidth
---  totalWidth = singleColumnWidth + (maxColumns - 1) * (singleColumnWidth + columnSpacing)
---@param frameName UnitFrameName
---@return integer width
---@return integer height
function Unit:GroupSize(frameName)
	local CurFrameOpt = UF.CurrentSettings[frameName]
	local frameHeight = UF:CalculateHeight(frameName)
	local frameWidth = CurFrameOpt.width
	local unitsPerColumn = CurFrameOpt.unitsPerColumn or 10
	local maxColumns = CurFrameOpt.maxColumns or 1
	local columnSpacing = CurFrameOpt.columnSpacing or 0
	local ySpacing = math.abs(CurFrameOpt.yOffset or 0)

	-- Single column: frames stacked vertically with ySpacing gap between them
	local columnHeight = (unitsPerColumn - 1) * (frameHeight + ySpacing) + frameHeight
	local columnWidth = frameWidth

	-- Multiple columns expand horizontally (columnAnchorPoint = LEFT)
	local width = columnWidth + (maxColumns - 1) * (columnWidth + columnSpacing)
	local height = columnHeight

	if UF.BuildDebug then
		UF:debug(
			'GroupSize('
				.. frameName
				.. '): frameW='
				.. frameWidth
				.. ' frameH='
				.. frameHeight
				.. ' units='
				.. unitsPerColumn
				.. ' cols='
				.. maxColumns
				.. ' colSpacing='
				.. columnSpacing
				.. ' ySpacing='
				.. ySpacing
				.. ' => '
				.. width
				.. 'x'
				.. height
		)
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
