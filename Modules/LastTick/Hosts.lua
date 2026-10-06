---@type SUI
local SUI = SUI
---@class SUI.Module.LastTick
local module = SUI:GetModule('LastTick')
local Overlay = module.Overlay

-- Where overlays go. Target and focus use SpartanUI's unit frame when it is on, otherwise
-- Blizzard's frame. Nameplates use SpartanUI's plate when one is drawn on top, otherwise
-- Blizzard's. Overlays live on the frame they draw on, so they hide with it.

---@class SUI.Module.LastTick.Slot
---@field key string
---@field unit string|nil
---@field kind 'frame'|'plate'
---@field overlay SUI.Module.LastTick.Overlay|nil
---@field bar StatusBar|nil
---@field plate Frame|nil

---@class SUI.Module.LastTick.Hosts
local Hosts = {}
module.Hosts = Hosts

---@type table<string, SUI.Module.LastTick.Slot>
Hosts.slots = {}
---@type table<Frame, SUI.Module.LastTick.Overlay>
local plateOverlays = setmetatable({}, { __mode = 'k' })
local frameOverlays = {}
local pendingReattach = false
local events = CreateFrame('Frame')

---@param path string Dotted path from a global, e.g. 'TargetFrame.TargetFrameContainer.Portrait'
---@return table|nil
local function Resolve(path)
	local node = _G
	for key in path:gmatch('[^%.]+') do
		node = type(node) == 'table' and node[key] or nil
		if not node then
			return nil
		end
	end
	return node
end

local BLIZZARD = {
	target = {
		bars = { 'TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar', 'TargetFrame.HealthBar', 'TargetFrameHealthBar' },
		portraits = { 'TargetFrame.TargetFrameContainer.Portrait', 'TargetFramePortrait' },
	},
	focus = {
		bars = { 'FocusFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar', 'FocusFrame.HealthBar', 'FocusFrameHealthBar' },
		portraits = { 'FocusFrame.TargetFrameContainer.Portrait', 'FocusFramePortrait' },
	},
}

---@param list string[]
---@return table|nil
local function First(list)
	for _, path in ipairs(list) do
		local found = Resolve(path)
		if found then
			return found
		end
	end
	return nil
end

---SpartanUI's own frame for a unit, when it is drawn
---@param unit string
---@return table|nil
local function SpartanFrame(unit)
	if not (SUI.UF and SUI:IsModuleEnabled('UnitFrames') and SUI.UF.Unit and SUI.UF.Unit.Get) then
		return nil
	end
	local frame = SUI.UF.Unit:Get(unit)
	if frame and frame.Health and frame.DB and frame.DB.enabled then
		return frame
	end
	return nil
end

---Health bar and portrait for a unit frame slot
---@param unit string
---@return StatusBar|nil bar, Region|nil portrait
local function FrameParts(unit)
	local frame = SpartanFrame(unit)
	if frame then
		local portrait = frame.Portrait
		if not (portrait and portrait.DB and portrait.DB.enabled) then
			portrait = nil
		end
		return frame.Health, portrait
	end
	local blizzard = BLIZZARD[unit]
	if blizzard then
		return First(blizzard.bars), First(blizzard.portraits)
	end
	return nil, nil
end

---@return SUI.Module.LastTick.Look
local function Look(forPlate)
	local settings = module.CurrentSettings
	local iconSettings = forPlate and settings.plateIcon or settings.icon
	local icon = module.ICONS[settings.icon.style] or module.ICONS.skull
	return {
		texture = settings.marker.texture,
		color = settings.marker.color,
		edge = settings.marker.edge,
		edgeColor = settings.marker.edgeColor,
		iconTexture = icon.texture,
		iconCoords = icon.coords,
		iconSize = iconSettings.size,
		showIcon = forPlate and settings.plateIcon.enabled or not forPlate,
	}
end

---Attach a unit frame slot to whatever frame shows that unit now
---@param slot SUI.Module.LastTick.Slot
local function AttachFrame(slot)
	local bar, portrait = FrameParts(slot.key)
	if not bar then
		if slot.overlay then
			slot.overlay:Detach()
		end
		slot.bar = nil
		return
	end
	local overlay = frameOverlays[slot.key]
	if not overlay then
		overlay = Overlay.New(bar)
		frameOverlays[slot.key] = overlay
	end
	slot.overlay = overlay
	slot.bar = bar

	local icon = module.CurrentSettings.icon
	local anchor, point, relative = bar, 'LEFT', 'RIGHT'
	if icon.placement == 'portrait' and portrait then
		anchor, point, relative = portrait, 'CENTER', 'CENTER'
	elseif icon.placement == 'center' then
		point, relative = 'CENTER', 'CENTER'
	end
	overlay:Attach(bar, anchor, point, relative, icon.x, icon.y, Look(false))
end

---@param unit string
---@return StatusBar|nil
local function PlateBar(unit)
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	if not ok or not plate or (plate.IsForbidden and plate:IsForbidden()) then
		return nil
	end
	-- SpartanUI (oUF) draws its plate as plate.unitFrame; Blizzard's is plate.UnitFrame
	local spartan = plate.unitFrame
	if spartan and spartan.Health and spartan:IsShown() then
		return spartan.Health, plate
	end
	local blizzard = plate.UnitFrame
	if blizzard then
		local bar = blizzard.healthBar or (blizzard.HealthBarsContainer and blizzard.HealthBarsContainer.healthBar)
		return bar, plate
	end
	return nil
end

---@param slot SUI.Module.LastTick.Slot
---@return boolean
local function AttachPlate(slot)
	local bar, plate = PlateBar(slot.unit)
	if not bar then
		return false
	end
	if slot.bar == bar and slot.overlay then
		return true
	end
	if bar.IsProtected and bar:IsProtected() and InCombatLockdown() then
		return false
	end
	local overlay = plateOverlays[plate]
	if not overlay then
		overlay = Overlay.New(plate)
		plateOverlays[plate] = overlay
	end
	slot.overlay = overlay
	slot.bar = bar
	slot.plate = plate
	overlay:Attach(bar, bar, 'LEFT', 'RIGHT', 2, 0, Look(true))
	return true
end

---Make sure a slot's overlay is attached before drawing
---@param slot SUI.Module.LastTick.Slot
---@return boolean ready
function Hosts:Prepare(slot)
	if slot.kind == 'plate' then
		return AttachPlate(slot)
	end
	return slot.overlay ~= nil and slot.bar ~= nil
end

---Re-attach every slot (settings, profile or frame changes). Waits for combat to end, since
---unit frames are protected.
function Hosts:Reattach()
	if InCombatLockdown() then
		pendingReattach = true
		return
	end
	pendingReattach = false
	local settings = module.CurrentSettings
	for _, unit in ipairs({ 'target', 'focus' }) do
		local slot = Hosts.slots[unit]
		if settings[unit] then
			if not slot then
				slot = { key = unit, unit = unit, kind = 'frame' }
				Hosts.slots[unit] = slot
			end
			AttachFrame(slot)
		elseif slot then
			if slot.overlay then
				slot.overlay:Detach()
			end
			Hosts.slots[unit] = nil
		end
	end
	for key, slot in pairs(Hosts.slots) do
		if slot.kind == 'plate' then
			if settings.nameplates then
				slot.bar = nil
			else
				if slot.overlay then
					slot.overlay:Detach()
				end
				Hosts.slots[key] = nil
			end
		end
	end
end

local function OnPlateAdded(unit)
	if not module.CurrentSettings.nameplates or not UnitCanAttack('player', unit) then
		return
	end
	Hosts.slots[unit] = { key = unit, unit = unit, kind = 'plate' }
end

local function OnPlateRemoved(unit)
	local slot = Hosts.slots[unit]
	if slot and slot.kind == 'plate' then
		if slot.overlay then
			slot.overlay:Detach()
		end
		Hosts.slots[unit] = nil
	end
end

events:SetScript('OnEvent', function(_, event, unit)
	if event == 'NAME_PLATE_UNIT_ADDED' then
		OnPlateAdded(unit)
	elseif event == 'NAME_PLATE_UNIT_REMOVED' then
		OnPlateRemoved(unit)
	elseif event == 'PLAYER_REGEN_ENABLED' then
		if pendingReattach then
			Hosts:Reattach()
		end
	elseif event == 'PLAYER_ENTERING_WORLD' then
		Hosts:Reattach()
	elseif not InCombatLockdown() then
		-- Target or focus changed: pick up unit frame changes made since (portrait, frame on/off)
		Hosts:Reattach()
	end
end)

function Hosts:Enable()
	events:RegisterEvent('NAME_PLATE_UNIT_ADDED')
	events:RegisterEvent('NAME_PLATE_UNIT_REMOVED')
	events:RegisterEvent('PLAYER_REGEN_ENABLED')
	events:RegisterEvent('PLAYER_ENTERING_WORLD')
	events:RegisterEvent('PLAYER_TARGET_CHANGED')
	if C_EventUtils and C_EventUtils.IsEventValid and C_EventUtils.IsEventValid('PLAYER_FOCUS_CHANGED') then
		events:RegisterEvent('PLAYER_FOCUS_CHANGED')
	end
	Hosts:Reattach()
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		if plate.namePlateUnitToken then
			OnPlateAdded(plate.namePlateUnitToken)
		end
	end
end

function Hosts:Disable()
	events:UnregisterAllEvents()
	for _, slot in pairs(Hosts.slots) do
		if slot.overlay then
			slot.overlay:Detach()
		end
	end
	wipe(Hosts.slots)
end
