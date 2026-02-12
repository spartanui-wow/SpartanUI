local _G, SUI = _G, SUI
local module = SUI:GetModule('Artwork') ---@type SUI.Module.Artwork
local MoveIt = SUI.MoveIt
-- Helper functions
local ReparentAB = false
local ExtraAB = SUI:NewModule('ExtraAB') ---@type SUI.Module

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

local function ResetParent(frame, parent)
	if parent ~= BossButtonHolder and not ReparentAB then
		if InCombatLockdown() then
			ReparentAB = true
			ExtraAB:RegisterEvent('PLAYER_REGEN_ENABLED')
			return
		end

		if ZoneAbilityFrame then
			ZoneAbilityFrame:SetParent(BossButtonHolder)
		end
		if ExtraActionBarFrame then
			ExtraActionBarFrame:SetParent(BossButtonHolder)
		end
	end
end

ExtraAB.PLAYER_REGEN_ENABLED = function(self)
	ExtraAB.Reparent()
end

function ExtraAB.Reparent()
	if InCombatLockdown() then
		NeedsReparent = true
		ExtraAB:RegisterEvent('PLAYER_REGEN_ENABLED')
		return
	end

	local ExtraActionBarFrame = _G['ExtraActionBarFrame']
	local ZoneAbilityFrame = _G['ZoneAbilityFrame']

	if ZoneAbilityFrame and ExtraAB.ZoneAbilityHolder then
		ZoneAbilityFrame:SetParent(ExtraAB.ZoneAbilityHolder)
	end
	if ExtraActionBarFrame and ExtraAB.ExtraActionBarHolder then
		ExtraActionBarFrame:SetParent(ExtraAB.ExtraActionBarHolder)
		ExtraActionBarFrame:ClearAllPoints()
		ExtraActionBarFrame:SetPoint('CENTER', ExtraAB.ExtraActionBarHolder, 'CENTER')
	end
end

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

	local dbEntry = SUI.DB.Styles[SUI.DB.Artwork.Style].BlizzMovers[name]
	if dbEntry then
		local point, anchor, secondaryPoint, x, y = strsplit(',', dbEntry)
		holder:SetPoint(point, anchor, secondaryPoint, x, y)
	elseif frame then
		local point, relativeTo, relativePoint, x, y = frame:GetPoint()
		holder:SetPoint(point, relativeTo, relativePoint, x, y)
	else
		-- Default position if neither DB entry nor frame is available
		holder:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
	end

	if _G[name] then
		local width, height = _G[name]:GetSize()
		holder:SetSize(width, height)
	else
		holder:SetSize(256, 64)
	end

	holder:Hide()

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
	if not SUI.DB.Artwork.BlizzMoverStates[moverName].enabled then
		RestoreOriginalPosition(moverName)
		return
	end

	local point, anchor, secondaryPoint, x, y = strsplit(',', SUI.DB.Styles[SUI.DB.Artwork.Style].BlizzMovers.TalkingHead)
	local THUIHolder = CreateFrame('Frame', 'THUIHolder', SpartanUI)
	THUIHolder:SetPoint(point, anchor, secondaryPoint, x, y)
	THUIHolder:Hide()

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

---Disable the TalkingHead mover
function module:DisableBlizzMover_TalkingHead()
	RestoreOriginalPosition('TalkingHead')
end

---Enable the TalkingHead mover
function module:EnableBlizzMover_TalkingHead()
	TalkingHead()
end

local function AbilityBars()
	-- Use custom holder-based movers for both ExtraActionBar and ZoneAbility
	local NeedsReparent = false
	local ExtraAbilityContainer = _G['ExtraAbilityContainer']
	local ExtraActionBarFrame = _G['ExtraActionBarFrame']
	local ZoneAbilityFrame = _G['ZoneAbilityFrame']

	if not ExtraActionBarFrame then
		return
	end

	-- Check if movers are enabled
	local extraActionEnabled = SUI.DB.Artwork.BlizzMoverStates['ExtraActionBar'].enabled
	local zoneAbilityEnabled = SUI.DB.Artwork.BlizzMoverStates['ZoneAbility'].enabled

	if not extraActionEnabled then
		RestoreOriginalPosition('ExtraActionBar')
	end
	if not zoneAbilityEnabled and ZoneAbilityFrame then
		RestoreOriginalPosition('ZoneAbility')
	end

	if not extraActionEnabled and not zoneAbilityEnabled then
		return
	end

	-- Cache original positions before moving
	if extraActionEnabled then
		CacheOriginalPosition('ExtraActionBar', ExtraActionBarFrame)
	end
	if zoneAbilityEnabled and ZoneAbilityFrame then
		CacheOriginalPosition('ZoneAbility', ZoneAbilityFrame)
	end

	-- Create holders
	local ExtraActionBarHolder = GenerateHolder('ExtraActionBar')
	local ZoneAbilityHolder = GenerateHolder('ZoneAbility')
	ExtraAB.ExtraActionBarHolder = ExtraActionBarHolder
	ExtraAB.ZoneAbilityHolder = ZoneAbilityHolder

	ExtraActionBarHolder:SetSize(100, 70)
	ZoneAbilityHolder:SetSize(100, 70)

	if extraActionEnabled then
		ExtraActionBarHolder:Show()
	else
		ExtraActionBarHolder:Hide()
	end

	if zoneAbilityEnabled then
		ZoneAbilityHolder:Show()
	else
		ZoneAbilityHolder:Hide()
	end

	-- Set up ExtraActionBarFrame
	if extraActionEnabled then
		ExtraActionBarFrame:SetParent(ExtraActionBarHolder)
		ExtraActionBarFrame:ClearAllPoints()
		ExtraActionBarFrame:SetPoint('CENTER', ExtraActionBarHolder, 'CENTER')
		ExtraActionBarFrame.ignoreInLayout = true
	end

	-- Set up ZoneAbilityFrame
	if zoneAbilityEnabled and ZoneAbilityFrame then
		ZoneAbilityFrame:SetParent(ZoneAbilityHolder)
		ZoneAbilityFrame:ClearAllPoints()
		ZoneAbilityFrame:SetPoint('CENTER', ZoneAbilityHolder, 'CENTER')
		ZoneAbilityFrame.ignoreInLayout = true
	end

	-- Set up ExtraAbilityContainer
	if ExtraAbilityContainer and (extraActionEnabled or zoneAbilityEnabled) then
		ExtraAbilityContainer.HighlightSystem = SUI.noop
		ExtraAbilityContainer.ClearHighlight = SUI.noop
		ExtraAbilityContainer:SetScript('OnShow', nil)
		ExtraAbilityContainer:SetScript('OnUpdate', nil)
		ExtraAbilityContainer.OnUpdate = nil -- remove BaseLayoutMixin.OnUpdate
		ExtraAbilityContainer.IsLayoutFrame = nil -- dont let it get readded
	end

	-- Hook functions to prevent movement
	if extraActionEnabled then
		hooksecurefunc(ExtraActionBarFrame, 'SetPoint', function(self)
			if self:GetParent() ~= ExtraActionBarHolder then
				self:ClearAllPoints()
				self:SetPoint('CENTER', ExtraActionBarHolder, 'CENTER')
			end
		end)
	end

	if zoneAbilityEnabled and ZoneAbilityFrame then
		hooksecurefunc(ZoneAbilityFrame, 'SetPoint', function(self)
			if self:GetParent() ~= ZoneAbilityHolder then
				self:ClearAllPoints()
				self:SetPoint('CENTER', ZoneAbilityHolder, 'CENTER')
			end
		end)
	end

	-- Create movers
	if extraActionEnabled then
		MoveIt:CreateMover(ExtraActionBarHolder, 'ExtraActionBar', 'Extra action button', nil, 'Blizzard UI')
		ExtraActionBarHolder:EnableMouse(false)
		if module.BlizzMoverCache['ExtraActionBar'] then
			if module.BlizzMoverCache['ExtraActionBar'] then
				module.BlizzMoverCache['ExtraActionBar'].holder = ExtraActionBarHolder
			end
		end
	end

	if zoneAbilityEnabled and ZoneAbilityFrame then
		MoveIt:CreateMover(ZoneAbilityHolder, 'ZoneAbility', 'Zone ability button', nil, 'Blizzard UI')
		ZoneAbilityHolder:EnableMouse(false)
		if module.BlizzMoverCache['ZoneAbility'] then
			if module.BlizzMoverCache['ZoneAbility'] then
				module.BlizzMoverCache['ZoneAbility'].holder = ZoneAbilityHolder
			end
		end
	end

	-- Update the layout when new frames are added
	if ExtraAbilityContainer then
		hooksecurefunc(ExtraAbilityContainer, 'AddFrame', function()
			ExtraAB.Reparent()
		end)
	end

	if ZoneAbilityFrame then
		hooksecurefunc(ZoneAbilityFrame, 'SetParent', function(_, parent)
			if parent ~= ZoneAbilityHolder and not NeedsReparent then
				ExtraAB.Reparent()
			end
		end)
	end

	hooksecurefunc(ExtraActionBarFrame, 'SetParent', function(_, parent)
		if parent ~= ExtraActionBarHolder and not NeedsReparent then
			ExtraAB.Reparent()
		end
	end)
end

---Disable the ExtraActionBar mover
function module:DisableBlizzMover_ExtraActionBar()
	RestoreOriginalPosition('ExtraActionBar')
end

---Enable the ExtraActionBar mover
function module:EnableBlizzMover_ExtraActionBar()
	AbilityBars()
end

---Disable the ZoneAbility mover
function module:DisableBlizzMover_ZoneAbility()
	RestoreOriginalPosition('ZoneAbility')
end

---Enable the ZoneAbility mover
function module:EnableBlizzMover_ZoneAbility()
	AbilityBars()
end

local function FramerateFrame()
	local moverName = 'FramerateFrame'
	local frame = _G['FramerateFrame']

	if not frame then
		return
	end

	-- Check if mover is enabled
	if not SUI.DB.Artwork.BlizzMoverStates[moverName].enabled then
		RestoreOriginalPosition(moverName)
		return
	end

	-- Cache original position before moving
	CacheOriginalPosition(moverName, frame)

	local holder = GenerateHolder(moverName)
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

---Enable the FramerateFrame mover
function module:EnableBlizzMover_FramerateFrame()
	FramerateFrame()
end

local function AlertFrame()
	local moverName = 'AlertFrame'
	local alertFrame = _G['AlertFrame']
	local groupLootContainer = _G['GroupLootContainer']

	if not alertFrame then
		return
	end

	-- Check if mover is enabled
	if not SUI.DB.Artwork.BlizzMoverStates[moverName].enabled then
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

	local holder = GenerateHolder(moverName)
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

---Disable the AlertFrame mover
function module:DisableBlizzMover_AlertFrame()
	RestoreOriginalPosition('AlertFrame')
	RestoreOriginalPosition('AlertFrame_GroupLoot')
end

---Enable the AlertFrame mover
function module:EnableBlizzMover_AlertFrame()
	AlertFrame()
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
		if not SUI.DB.Artwork.BlizzMoverStates[moverName].enabled then
			RestoreOriginalPosition(moverName)
			return
		end

		-- Cache original position before moving
		CacheOriginalPosition(moverName, frame)

		local point, _, secondaryPoint, x, y = strsplit(',', SUI.DB.Styles[SUI.DB.Artwork.Style].BlizzMovers.VehicleLeaveButton)
		local VehicleBtnHolder = CreateFrame('Frame', 'VehicleBtnHolder', SpartanUI)
		VehicleBtnHolder:SetSize(frame:GetSize())
		VehicleBtnHolder:SetPoint(point, UIParent, secondaryPoint, x, y)
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

---Disable the VehicleLeaveButton mover
function module:DisableBlizzMover_VehicleLeaveButton()
	RestoreOriginalPosition('VehicleLeaveButton')
end

---Enable the VehicleLeaveButton mover
function module:EnableBlizzMover_VehicleLeaveButton()
	VehicleLeaveButton()
end

local function VehicleSeatIndicator()
	local moverName = 'VehicleSeatIndicator'
	local SeatIndicator = _G['VehicleSeatIndicator']

	if not SeatIndicator then
		return
	end

	-- Check if mover is enabled
	if not SUI.DB.Artwork.BlizzMoverStates[moverName].enabled then
		RestoreOriginalPosition(moverName)
		return
	end

	-- Cache original position before moving
	CacheOriginalPosition(moverName, SeatIndicator)

	local point, anchor, secondaryPoint, x, y = strsplit(',', SUI.DB.Styles[SUI.DB.Artwork.Style].BlizzMovers.VehicleSeatIndicator)
	local VehicleSeatHolder = CreateFrame('Frame', 'VehicleSeatHolder', SpartanUI)
	VehicleSeatHolder:SetSize(SeatIndicator:GetSize())
	VehicleSeatHolder:SetPoint(point, anchor, secondaryPoint, x, y)
	VehicleSeatHolder:Hide()
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

---Disable the VehicleSeatIndicator mover
function module:DisableBlizzMover_VehicleSeatIndicator()
	RestoreOriginalPosition('VehicleSeatIndicator')
end

---Enable the VehicleSeatIndicator mover
function module:EnableBlizzMover_VehicleSeatIndicator()
	VehicleSeatIndicator()
end

local function WidgetPowerBarContainer()
	local moverName = 'WidgetPowerBarContainer'
	local widgetFrame = _G['UIWidgetPowerBarContainerFrame']
	local playerPowerBarAlt = _G['PlayerPowerBarAlt']

	-- Check if mover is enabled
	if not SUI.DB.Artwork.BlizzMoverStates[moverName].enabled then
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

	local holder = GenerateHolder(moverName)

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

---Disable the WidgetPowerBarContainer mover
function module:DisableBlizzMover_WidgetPowerBarContainer()
	RestoreOriginalPosition('WidgetPowerBarContainer')
	RestoreOriginalPosition('WidgetPowerBarContainer_PowerBarAlt')
end

---Enable the WidgetPowerBarContainer mover
function module:EnableBlizzMover_WidgetPowerBarContainer()
	WidgetPowerBarContainer()
end

local function TopCenterContainer()
	local moverName = 'TopCenterContainer'
	local frame = _G['UIWidgetTopCenterContainerFrame']

	if not frame then
		return
	end

	-- Check if mover is enabled
	if not SUI.DB.Artwork.BlizzMoverStates[moverName].enabled then
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

---Disable the TopCenterContainer mover
function module:DisableBlizzMover_TopCenterContainer()
	RestoreOriginalPosition('TopCenterContainer')
end

---Enable the TopCenterContainer mover
function module:EnableBlizzMover_TopCenterContainer()
	TopCenterContainer()
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
	if not SUI.DB.Artwork.BlizzMoverStates[moverName] or not SUI.DB.Artwork.BlizzMoverStates[moverName].enabled then
		RestoreOriginalPosition(moverName)
		return
	end

	-- Cache original position before moving
	CacheOriginalPosition(moverName, frame)

	-- Create holder frame
	local holder = CreateFrame('Frame', 'SUI_EncounterBarHolder', UIParent)
	holder:SetSize(200, 60) -- Default encounter bar size

	-- Position from style
	local point, anchor, secondaryPoint, x, y = strsplit(',', SUI.DB.Styles[SUI.DB.Artwork.Style].BlizzMovers.EncounterBar or 'CENTER,UIParent,CENTER,0,0')
	holder:SetPoint(point, anchor, secondaryPoint, tonumber(x) or 0, tonumber(y) or 0)

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

---Disable the EncounterBar mover
function module:DisableBlizzMover_EncounterBar()
	RestoreOriginalPosition('EncounterBar')
end

---Enable the EncounterBar mover
function module:EnableBlizzMover_EncounterBar()
	EncounterBar()
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
	if not SUI.DB.Artwork.BlizzMoverStates[moverName] or not SUI.DB.Artwork.BlizzMoverStates[moverName].enabled then
		RestoreOriginalPosition(moverName)
		return
	end

	-- Cache original position before moving
	CacheOriginalPosition(moverName, frame)

	-- Create holder frame
	local holder = CreateFrame('Frame', 'SUI_ArchaeologyBarHolder', UIParent)
	holder:SetSize(200, 40) -- Default archaeology bar size

	-- Position from style
	local point, anchor, secondaryPoint, x, y = strsplit(',', SUI.DB.Styles[SUI.DB.Artwork.Style].BlizzMovers.ArchaeologyBar or 'CENTER,UIParent,CENTER,0,0')
	holder:SetPoint(point, anchor, secondaryPoint, tonumber(x) or 0, tonumber(y) or 0)

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

---Disable the ArchaeologyBar mover
function module:DisableBlizzMover_ArchaeologyBar()
	RestoreOriginalPosition('ArchaeologyBar')
end

---Enable the ArchaeologyBar mover
function module:EnableBlizzMover_ArchaeologyBar()
	ArchaeologyBar()
end

-- This is the main inpoint
function module.BlizzMovers()
	-- Log version info for debugging (#564)
	if SUI.logger then
		local versionInfo = SUI.IsRetail and 'Retail' or (SUI.IsTBC and 'TBC' or (SUI.IsWrath and 'Wrath' or (SUI.IsCata and 'Cata' or (SUI.IsMOP and 'MOP' or 'Classic'))))
		SUI.logger.debug('BlizzMovers: Initializing for ' .. versionInfo .. ', EditModeManagerFrame=' .. tostring(EditModeManagerFrame ~= nil))
	end

	-- Frames using LibEditModeOverride (Retail only):
	-- In TBC/Classic, these will fall back to custom holder-based movers
	TalkingHead() -- TalkingHeadFrame (systemID 13)
	VehicleLeaveButton() -- MainMenuBarVehicleLeaveButton (systemID 14)
	AbilityBars() -- ExtraActionBarFrame + ZoneAbilityFrame (systemID 11)
	EncounterBar() -- EncounterBar (systemID 10)
	ArchaeologyBar() -- ArcheologyDigsiteProgressBar (systemID 21)

	-- Frames using custom movers (all versions):
	FramerateFrame() -- No EditMode support
	AlertFrame() -- No EditMode support
	TopCenterContainer() -- No EditMode support (UIWidgetTopCenterContainerFrame)
	VehicleSeatIndicator() -- Has EditMode but not well supported
	WidgetPowerBarContainer() -- No EditMode support
end
