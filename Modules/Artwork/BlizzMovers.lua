local _G, SUI = _G, SUI
local module = SUI:GetModule('Artwork') ---@type SUI.Module.Artwork
local MoveIt = SUI.MoveIt

local function GetBlizzMoverPosition(name)
	local data = SUI.ThemeRegistry:GetBlizzMovers(module.CurrentSettings.Style)
	if data and data[name] then
		return data[name]
	end
	return nil
end

-- Blizz Mover Management
---@class BlizzMoverCache
---@field holder? Frame The holder frame for this mover
---@field originalPos? table Cached original position data
---@field frame? Frame The actual Blizzard frame being moved
module.BlizzMoverCache = {}

---@param frame any
---@param anchor FramePoint
local function ResetPosition(frame, _, anchor)
	local holder = frame.SUIHolder
	if holder and anchor ~= holder then
		if InCombatLockdown() then
			return
		end
		frame:ClearAllPoints()
		frame:SetPoint('CENTER' or frame.SUIHolderMountPoint, holder)
	end
end

-- function ExtraAB.Reparent()
-- 	if InCombatLockdown() then
-- 		NeedsReparent = true
-- 		ExtraAB:RegisterEvent('PLAYER_REGEN_ENABLED')
-- 		return
-- 	end

-- 	local ExtraActionBarFrame = _G['ExtraActionBarFrame']
-- 	local ZoneAbilityFrame = _G['ZoneAbilityFrame']

-- 	if ZoneAbilityFrame and ExtraAB.ZoneAbilityHolder then
-- 		ZoneAbilityFrame:SetParent(ExtraAB.ZoneAbilityHolder)
-- 	end
-- 	if ExtraActionBarFrame and ExtraAB.ExtraActionBarHolder then
-- 		ExtraActionBarFrame:SetParent(ExtraAB.ExtraActionBarHolder)
-- 		ExtraActionBarFrame:ClearAllPoints()
-- 		ExtraActionBarFrame:SetPoint('CENTER', ExtraAB.ExtraActionBarHolder, 'CENTER')
-- 	end
-- end

---Cache the original position of a frame before moving it
---@param moverName string The name identifier for this mover
---@param frame Frame The frame to cache position for
local function CacheOriginalPosition(moverName, frame)
	if not frame or module.BlizzMoverCache[moverName] and module.BlizzMoverCache[moverName].originalPos then
		return -- Already cached
	end

	if not module.BlizzMoverCache[moverName] then
		module.BlizzMoverCache[moverName] = {}
	end

	-- Get all anchor points for this frame
	local numPoints = frame:GetNumPoints()
	local points = {}

	for i = 1, numPoints do
		local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(i)
		points[i] = {
			point = point,
			relativeTo = relativeTo and relativeTo:GetName() or 'UIParent',
			relativePoint = relativePoint,
			xOfs = xOfs,
			yOfs = yOfs,
		}
	end

	module.BlizzMoverCache[moverName].originalPos = {
		points = points,
		parent = frame:GetParent() and frame:GetParent():GetName() or 'UIParent',
	}
	module.BlizzMoverCache[moverName].frame = frame

	SUI.Log('Cached original position for ' .. moverName, 'Artwork.BlizzMovers', 'debug')
end

---Restore a frame to its original position and parent
---@param moverName string The name identifier for this mover
local function RestoreOriginalPosition(moverName)
	local cache = module.BlizzMoverCache[moverName]
	if not cache or not cache.originalPos or not cache.frame then
		SUI.Log('No cached position found for ' .. moverName, 'Artwork.BlizzMovers', 'warning')
		return
	end

	if InCombatLockdown() then
		SUI.Log('Cannot restore position for ' .. moverName .. ' during combat', 'Artwork.BlizzMovers', 'warning')
		return
	end

	local frame = cache.frame
	local originalPos = cache.originalPos

	-- Restore parent
	if originalPos.parent then
		local parent = _G[originalPos.parent] or UIParent
		frame:SetParent(parent)
	end

	-- Restore all anchor points
	frame:ClearAllPoints()
	for i, pointData in ipairs(originalPos.points) do
		local relativeTo = _G[pointData.relativeTo] or UIParent
		frame:SetPoint(pointData.point, relativeTo, pointData.relativePoint, pointData.xOfs, pointData.yOfs)
	end

	SUI.Log('Restored original position for ' .. moverName, 'Artwork.BlizzMovers', 'info')
end

---@param name string
---@param frame? Frame
---@return Frame
local function GenerateHolder(name, frame)
	local holder = CreateFrame('Frame', name .. 'Holder', UIParent)
	holder:EnableMouse(false)

	local dbEntry = GetBlizzMoverPosition(name)
	if dbEntry then
		local point, anchor, secondaryPoint, x, y = strsplit(',', dbEntry)
		holder:SetPoint(point, anchor, secondaryPoint, tonumber(x) or 0, tonumber(y) or 0)
	elseif frame and frame:GetPoint() then
		local point, relativeTo, relativePoint, x, y = frame:GetPoint()
		holder:SetPoint(point, relativeTo or UIParent, relativePoint or point, x or 0, y or 0)
	else
		holder:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
	end

	if _G[name] then
		local width, height = _G[name]:GetSize()
		holder:SetSize(width, height)
	else
		holder:SetSize(256, 64)
	end

	return holder
end

---@param frame Frame
---@param holder Frame
---@param pos? FramePoint
local function AttachToHolder(frame, holder, pos)
	if not frame then
		return
	end
	frame:ClearAllPoints()
	frame:SetPoint(pos or 'CENTER', holder)
	frame.SUIHolder = holder
	frame.SUIHolderMountPoint = pos or 'CENTER'
end

-- Blizzard Movers
local function TalkingHead()
	local moverName = 'TalkingHead'

	-- Check if mover is enabled
	if not module.CurrentSettings.BlizzMoverStates[moverName].enabled then
		RestoreOriginalPosition(moverName)
		return
	end

	local point, anchor, secondaryPoint, x, y = strsplit(',', GetBlizzMoverPosition('TalkingHead') or 'TOP,SpartanUI,TOP,0,-18')
	local THUIHolder = CreateFrame('Frame', 'THUIHolder', SpartanUI)
	THUIHolder:SetPoint(point, anchor, secondaryPoint, tonumber(x) or 0, tonumber(y) or 0)
	THUIHolder:EnableMouse(false)

	local SetupTalkingHead = function()
		local frame = TalkingHeadFrame
		if not frame then
			return
		end

		-- Cache original position before moving
		CacheOriginalPosition(moverName, frame)

		--Prevent WoW from moving the frame around
		frame.ignoreFramePositionManager = true
		THUIHolder:SetSize(frame:GetSize())
		MoveIt:CreateMover(THUIHolder, 'THUIHolder', 'Talking Head Frame', nil, 'Blizzard UI')

		-- Parent frame to holder
		frame:SetParent(THUIHolder)
		frame:ClearAllPoints()
		frame:SetPoint('CENTER', THUIHolder, 'CENTER', 0, 0)

		-- Hook SetPoint to prevent Blizzard from repositioning
		hooksecurefunc(frame, 'SetPoint', function(self, _, anchor)
			if anchor ~= THUIHolder then
				self:ClearAllPoints()
				self:SetPoint('CENTER', THUIHolder, 'CENTER', 0, 0)
			end
		end)

		-- Also re-apply on show
		frame:HookScript('OnShow', function()
			frame:ClearAllPoints()
			frame:SetPoint('CENTER', THUIHolder, 'CENTER', 0, 0)
		end)

		-- Store holder reference
		if module.BlizzMoverCache[moverName] then
			if module.BlizzMoverCache[moverName] then
				module.BlizzMoverCache[moverName].holder = THUIHolder
			end
		end
	end

	if C_AddOns.IsAddOnLoaded('Blizzard_TalkingHeadUI') then
		SetupTalkingHead()
	else
		--We want the mover to be available immediately, so we load it ourselves
		local f = CreateFrame('Frame')
		f:RegisterEvent('PLAYER_ENTERING_WORLD')
		f:SetScript('OnEvent', function(frame, event)
			frame:UnregisterEvent(event)
			C_AddOns.LoadAddOn('Blizzard_TalkingHeadUI')
			SetupTalkingHead()
		end)
	end
end

local function FramerateFrame()
	local moverName = 'FramerateFrame'
	local frame = _G['FramerateFrame']

	if not frame then
		return
	end

	-- Check if mover is enabled
	if not module.CurrentSettings.BlizzMoverStates[moverName].enabled then
		RestoreOriginalPosition(moverName)
		return
	end

	-- Cache original position before moving
	CacheOriginalPosition(moverName, frame)

	local holder = GenerateHolder(moverName, frame)
	holder:SetSize(64, 20)
	AttachToHolder(frame, holder)
	MoveIt:CreateMover(holder, moverName, 'Framerate frame', nil, 'Blizzard UI')

	-- Store holder reference
	if module.BlizzMoverCache[moverName] then
		module.BlizzMoverCache[moverName].holder = holder
	end
end

---Disable the FramerateFrame mover
function module:DisableBlizzMover_FramerateFrame()
	RestoreOriginalPosition('FramerateFrame')
end

local function AlertFrame()
	local moverName = 'AlertFrame'
	local alertFrame = _G['AlertFrame']
	local groupLootContainer = _G['GroupLootContainer']

	if not alertFrame then
		return
	end

	-- Check if mover is enabled
	if not module.CurrentSettings.BlizzMoverStates[moverName].enabled then
		RestoreOriginalPosition(moverName)
		if groupLootContainer and module.BlizzMoverCache[moverName .. '_GroupLoot'] then
			RestoreOriginalPosition(moverName .. '_GroupLoot')
		end
		return
	end

	-- Cache original positions before moving
	CacheOriginalPosition(moverName, alertFrame)
	if groupLootContainer then
		CacheOriginalPosition(moverName .. '_GroupLoot', groupLootContainer)
	end

	local holder = GenerateHolder(moverName, alertFrame)
	holder:SetSize(180, 40)

	AttachToHolder(alertFrame, holder, 'BOTTOM')
	if groupLootContainer then
		AttachToHolder(groupLootContainer, holder, 'BOTTOM')
	end

	hooksecurefunc(alertFrame, 'SetPoint', ResetPosition)
	if groupLootContainer then
		hooksecurefunc(groupLootContainer, 'SetPoint', ResetPosition)
	end

	MoveIt:CreateMover(holder, 'AlertHolder', 'Alert frame anchor', nil, 'Blizzard UI')

	-- Store holder reference
	if module.BlizzMoverCache[moverName] then
		module.BlizzMoverCache[moverName].holder = holder
	end
end

local function VehicleLeaveButton()
	local moverName = 'VehicleLeaveButton'

	-- Use custom holder-based mover
	-- When BT4 is loaded, this mover overrides BT4's positioning
	local function MoverCreate()
		local frame = MainMenuBarVehicleLeaveButton
		if not frame then
			return
		end

		-- Check if mover is enabled
		if not module.CurrentSettings.BlizzMoverStates[moverName].enabled then
			RestoreOriginalPosition(moverName)
			return
		end

		-- Cache original position before moving
		CacheOriginalPosition(moverName, frame)

		local point, _, secondaryPoint, x, y = strsplit(',', GetBlizzMoverPosition('VehicleLeaveButton') or 'BOTTOM,SpartanUI,BOTTOM,0,250')
		local VehicleBtnHolder = CreateFrame('Frame', 'VehicleBtnHolder', SpartanUI)
		VehicleBtnHolder:EnableMouse(false)
		VehicleBtnHolder:SetSize(frame:GetSize())
		VehicleBtnHolder:SetPoint(point, UIParent, secondaryPoint, tonumber(x) or 0, tonumber(y) or 0)
		MoveIt:CreateMover(VehicleBtnHolder, moverName, 'Vehicle leave button', nil, 'Blizzard UI')

		frame:ClearAllPoints()
		frame:SetPoint('CENTER', VehicleBtnHolder, 'CENTER')
		hooksecurefunc(frame, 'SetPoint', function(_, _, parent)
			if parent ~= VehicleBtnHolder then
				frame:ClearAllPoints()
				frame:SetParent(UIParent)
				frame:SetPoint('CENTER', VehicleBtnHolder, 'CENTER')
			end
		end)

		-- Store holder reference
		if module.BlizzMoverCache[moverName] then
			module.BlizzMoverCache[moverName].holder = VehicleBtnHolder
		end
	end

	-- Delay this so unit frames have been generated
	module:ScheduleTimer(MoverCreate, 2)
end

local function VehicleSeatIndicator()
	local moverName = 'VehicleSeatIndicator'
	local SeatIndicator = _G['VehicleSeatIndicator']

	if not SeatIndicator then
		return
	end

	-- Check if mover is enabled
	if not module.CurrentSettings.BlizzMoverStates[moverName].enabled then
		RestoreOriginalPosition(moverName)
		return
	end

	-- Cache original position before moving
	CacheOriginalPosition(moverName, SeatIndicator)

	local point, anchor, secondaryPoint, x, y = strsplit(',', GetBlizzMoverPosition('VehicleSeatIndicator') or 'RIGHT,SpartanUI,RIGHT,-10,-30')
	local VehicleSeatHolder = CreateFrame('Frame', 'VehicleSeatHolder', SpartanUI)
	VehicleSeatHolder:EnableMouse(false)
	VehicleSeatHolder:SetSize(SeatIndicator:GetSize())
	VehicleSeatHolder:SetPoint(point, anchor, secondaryPoint, tonumber(x) or 0, tonumber(y) or 0)
	local function SetPosition(_, _, anchorPoint)
		if anchorPoint ~= VehicleSeatHolder then
			SeatIndicator:ClearAllPoints()
			SeatIndicator:SetPoint('TOPLEFT', VehicleSeatHolder)
		end
	end
	MoveIt:CreateMover(VehicleSeatHolder, moverName, 'Vehicle seat anchor', nil, 'Blizzard UI')

	hooksecurefunc(SeatIndicator, 'SetPoint', SetPosition)
	SeatIndicator.PositionVehicleFrameHooked = true
	SeatIndicator:ClearAllPoints()
	SeatIndicator:SetPoint('TOPLEFT', VehicleSeatHolder)

	-- Store holder reference
	if module.BlizzMoverCache[moverName] then
		module.BlizzMoverCache[moverName].holder = VehicleSeatHolder
	end
end

local function WidgetPowerBarContainer()
	local moverName = 'WidgetPowerBarContainer'
	local widgetFrame = _G['UIWidgetPowerBarContainerFrame']
	local playerPowerBarAlt = _G['PlayerPowerBarAlt']

	-- Check if mover is enabled
	if not module.CurrentSettings.BlizzMoverStates[moverName].enabled then
		RestoreOriginalPosition(moverName)
		if playerPowerBarAlt and module.BlizzMoverCache[moverName .. '_PowerBarAlt'] then
			RestoreOriginalPosition(moverName .. '_PowerBarAlt')
		end
		return
	end

	-- Cache original positions before moving
	if widgetFrame then
		CacheOriginalPosition(moverName, widgetFrame)
	end
	if playerPowerBarAlt and not C_AddOns.IsAddOnLoaded('SimplePowerBar') then
		CacheOriginalPosition(moverName .. '_PowerBarAlt', playerPowerBarAlt)
	end

	local holder = GenerateHolder(moverName, widgetFrame or playerPowerBarAlt)

	-- Default position: just below the top center widget container
	if not GetBlizzMoverPosition(moverName) then
		holder:ClearAllPoints()
		holder:SetPoint('TOP', _G['TopCenterContainerHolder'] or UIParent, 'BOTTOM', 0, -5)
	end

	if widgetFrame then
		AttachToHolder(widgetFrame, holder)
		hooksecurefunc(widgetFrame, 'SetPoint', ResetPosition)
	end

	if not C_AddOns.IsAddOnLoaded('SimplePowerBar') and playerPowerBarAlt then
		AttachToHolder(playerPowerBarAlt, holder)
		hooksecurefunc(playerPowerBarAlt, 'SetPoint', ResetPosition)
	end

	MoveIt:CreateMover(holder, moverName, 'Power bar', nil, 'Blizzard UI')

	-- Store holder reference
	if module.BlizzMoverCache[moverName] then
		if module.BlizzMoverCache[moverName] then
			module.BlizzMoverCache[moverName].holder = holder
		end
	end
end

local function TopCenterContainer()
	local moverName = 'TopCenterContainer'
	local frame = _G['UIWidgetTopCenterContainerFrame']

	if not frame then
		return
	end

	-- Check if mover is enabled
	if not module.CurrentSettings.BlizzMoverStates[moverName].enabled then
		RestoreOriginalPosition(moverName)
		return
	end

	-- Cache original position before moving
	CacheOriginalPosition(moverName, frame)

	local holder = GenerateHolder(moverName, frame)
	AttachToHolder(frame, holder)
	hooksecurefunc(frame, 'SetPoint', ResetPosition)
	MoveIt:CreateMover(holder, moverName, 'Top center container', nil, 'Blizzard UI')
	-- widgetFrames only exists in retail
	if frame.widgetFrames then
		for _, widget in pairs(frame.widgetFrames) do
			SUI.Skins.SkinWidgets(widget)
		end
	end
	module:RegisterEvent('PLAYER_ENTERING_WORLD')
	module:RegisterEvent('UPDATE_ALL_UI_WIDGETS')

	-- Store holder reference
	if module.BlizzMoverCache[moverName] then
		module.BlizzMoverCache[moverName].holder = holder
	end
end

function module:UPDATE_UI_WIDGET()
	module:UPDATE_ALL_UI_WIDGETS()
end
function module:UPDATE_ALL_UI_WIDGETS()
	local widgetContainer = _G['UIWidgetTopCenterContainerFrame']
	if widgetContainer and widgetContainer.widgetFrames then
		for _, widget in pairs(widgetContainer.widgetFrames) do
			SUI.Skins.SkinWidgets(widget)
		end
	end
end

function module:PLAYER_ENTERING_WORLD()
	print('PLAYER_ENTERING_WORLD')
	module:UPDATE_ALL_UI_WIDGETS()
end

local function EncounterBar()
	local moverName = 'EncounterBar'
	local frame = _G['EncounterBar']

	-- EncounterBar appears during specific raid encounters (e.g., Ultraxion fight)
	-- It may not exist until the encounter starts
	if not frame then
		if MoveIt.logger then
			MoveIt.logger.debug('EncounterBar frame not available yet')
		end
		return
	end

	-- Check if mover is enabled
	if not module.CurrentSettings.BlizzMoverStates[moverName] or not module.CurrentSettings.BlizzMoverStates[moverName].enabled then
		RestoreOriginalPosition(moverName)
		return
	end

	-- Cache original position before moving
	CacheOriginalPosition(moverName, frame)

	-- Create holder frame
	local holder = GenerateHolder(moverName, frame)
	holder:SetSize(200, 60)

	-- Default position: just below the top center widget container
	if not GetBlizzMoverPosition(moverName) then
		holder:ClearAllPoints()
		holder:SetPoint('TOP', _G['TopCenterContainerHolder'] or UIParent, 'BOTTOM', 0, -5)
	end

	-- Create mover
	MoveIt:CreateMover(holder, moverName, 'Encounter Bar', nil, 'Blizzard UI')

	-- Parent frame to holder
	frame:SetParent(holder)
	frame:ClearAllPoints()
	frame:SetPoint('CENTER', holder, 'CENTER', 0, 0)

	-- Hook SetPoint to prevent Blizzard repositioning
	hooksecurefunc(frame, 'SetPoint', function(self, _, parentFrame)
		if parentFrame ~= holder then
			self:ClearAllPoints()
			self:SetPoint('CENTER', holder, 'CENTER', 0, 0)
		end
	end)

	-- Store holder reference
	if module.BlizzMoverCache[moverName] then
		module.BlizzMoverCache[moverName].holder = holder
	end
end

local function ArchaeologyBar()
	local moverName = 'ArchaeologyBar'
	local frame = _G['ArchaeologyDigsiteProgressBar']

	-- ArchaeologyBar appears when using archaeology
	if not frame then
		if MoveIt.logger then
			MoveIt.logger.debug('ArchaeologyBar frame not available yet')
		end
		return
	end

	-- Check if mover is enabled
	if not module.CurrentSettings.BlizzMoverStates[moverName] or not module.CurrentSettings.BlizzMoverStates[moverName].enabled then
		RestoreOriginalPosition(moverName)
		return
	end

	-- Cache original position before moving
	CacheOriginalPosition(moverName, frame)

	-- Create holder frame
	local holder = GenerateHolder(moverName, frame)
	holder:SetSize(200, 40)

	-- Create mover
	MoveIt:CreateMover(holder, moverName, 'Archaeology Bar', nil, 'Blizzard UI')

	-- Parent frame to holder
	frame:SetParent(holder)
	frame:ClearAllPoints()
	frame:SetPoint('CENTER', holder, 'CENTER', 0, 0)

	-- Hook SetPoint to prevent Blizzard repositioning
	hooksecurefunc(frame, 'SetPoint', function(self, _, parentFrame)
		if parentFrame ~= holder then
			self:ClearAllPoints()
			self:SetPoint('CENTER', holder, 'CENTER', 0, 0)
		end
	end)

	-- Store holder reference
	if module.BlizzMoverCache[moverName] then
		module.BlizzMoverCache[moverName].holder = holder
	end
end

local function HudTooltip()
	local moverName = 'HudTooltip'
	local frame = _G['GameTooltipDefaultContainer']

	if not frame then
		return
	end

	-- Check if mover is enabled
	if not module.CurrentSettings.BlizzMoverStates[moverName].enabled then
		RestoreOriginalPosition(moverName)
		return
	end

	-- Cache original position before moving
	CacheOriginalPosition(moverName, frame)

	local holder = GenerateHolder(moverName, frame)
	holder:SetSize(frame:GetSize())

	-- Attach using BOTTOMRIGHT so GameTooltip_SetDefaultAnchor reads a corner
	-- anchor from GetPoint(1) and positions tooltips correctly
	frame:ClearAllPoints()
	frame:SetPoint('BOTTOMRIGHT', holder, 'BOTTOMRIGHT')
	frame.SUIHolder = holder
	frame.SUIHolderMountPoint = 'BOTTOMRIGHT'

	-- Prevent Blizzard Edit Mode from repositioning the container
	hooksecurefunc(frame, 'SetPoint', function(self, _, anchor)
		if self.SUIHolder and anchor ~= self.SUIHolder then
			if InCombatLockdown() then
				return
			end
			self:ClearAllPoints()
			self:SetPoint('BOTTOMRIGHT', self.SUIHolder, 'BOTTOMRIGHT')
		end
	end)

	MoveIt:CreateMover(holder, moverName, 'HUD Tooltip', nil, 'Blizzard UI')

	-- Store holder reference
	if module.BlizzMoverCache[moverName] then
		module.BlizzMoverCache[moverName].holder = holder
	end
end

-- This is the main inpoint
function module.BlizzMovers()
	TalkingHead() -- TalkingHeadFrame (systemID 13)
	VehicleLeaveButton() -- MainMenuBarVehicleLeaveButton (systemID 14)
	ArchaeologyBar() -- ArcheologyDigsiteProgressBar (systemID 21)
	FramerateFrame() -- No EditMode support
	AlertFrame() -- No EditMode support
	TopCenterContainer() -- No EditMode support (UIWidgetTopCenterContainerFrame)
	EncounterBar() -- EncounterBar (systemID 10)
	VehicleSeatIndicator() -- Has EditMode but not well supported
	WidgetPowerBarContainer() -- No EditMode support
	HudTooltip() -- Override Blizzard Edit Mode tooltip positioning
end
