---@class SUI
local SUI = SUI
local L = SUI.L
local MoveIt = SUI.MoveIt
local module = SUI:NewModule('Minimap') ---@class SUI.Module.Minimap : SUI.Module
module.description = 'CORE: Skins, sizes, and positions the Minimap'
module.Core = true
----------------------------------------------------------------------------------------------------
module.Settings = nil ---@type SUI.Style.Settings.Minimap
module.styleOverride = nil ---@type string|nil
module.layoutModificationPending = false ---@type boolean Track if layout modification was skipped during combat
local Registry = {}
local MinimapUpdater = CreateFrame('Frame')

-- Button Bag state (for consolidating addon minimap buttons)
local ButtonBag = {
	buttons = {},
	isOpen = false,
	frame = nil,
	toggleButton = nil,
}

-- Create a secure vehicle UI watcher frame similar to oUF's PetBattleFrameHider
local VehicleUIWatcher = CreateFrame('Frame', 'SUI_Minimap_VehicleUIWatcher', UIParent, 'SecureHandlerStateTemplate')
VehicleUIWatcher:SetAllPoints()
VehicleUIWatcher:SetFrameStrata('LOW')
-- Register state driver to detect when vehicle UI is active (not just any vehicle)
RegisterStateDriver(VehicleUIWatcher, 'visibility', '[possessbar][overridebar][vehicleui] hide; show')

---@class SUI.Minimap.Holder : FrameExpanded, SUI.MoveIt.MoverParent
local SUIMinimap = CreateFrame('Frame', 'SUI_Minimap')

---@class SUI.Style.Settings.IMinimap : SUI.Style.Settings.Minimap
local BaseSettings = {
	-- Top-level settings
	shape = 'circle',
	size = { 180, 180 },
	scaleWithArt = true,
	UnderVehicleUI = true,
	useVehicleMover = true,
	position = 'TOPRIGHT,UIParent,TOPRIGHT,-20,-20',
	vehiclePosition = 'TOPRIGHT,UIParent,TOPRIGHT,-20,-20',
	rotate = false,
	-- Elements
	elements = {
		-- Background
		background = {
			enabled = true,
			texture = 'Interface\\AddOns\\SpartanUI\\images\\minimap\\round',
			size = { 220, 220 },
			color = { 1, 1, 1, 1 },
			BlendMode = 'ADD',
			alpha = 1,
		},
		-- BorderTop (Retail only - the bar below the minimap)
		BorderTop = {
			enabled = true,
			position = 'TOP,Minimap,BOTTOM,0,-5',
			alpha = 0.8,
			scale = 1,
		},
		-- Zone Text
		ZoneText = {
			enabled = true,
			scale = 1,
			position = 'TOPLEFT,BorderTop,TOPLEFT,4,-4',
			color = { 1, 0.82, 0, 1 },
		},
		-- Coordinates
		coords = {
			enabled = true,
			scale = 1,
			size = { 80, 12 },
			position = 'BOTTOM,BorderTop,BOTTOM,-5,3',
			color = { 1, 1, 1, 1 },
			format = '%.1f, %.1f',
		},
		-- Zoom Buttons
		zoomButtons = {
			enabled = false,
			scale = 1,
			position = 'BOTTOMRIGHT,Minimap,BOTTOMRIGHT,-5,5',
		},
		-- Clock
		clock = {
			enabled = true,
			position = 'BOTTOMRIGHT,BorderTop,BOTTOMRIGHT,-10,0',
			scale = 1,
			format = '%I:%M %p',
			color = { 1, 1, 1, 1 },
		},
		-- Tracking Icon
		tracking = {
			enabled = true,
			position = 'BOTTOMLEFT,BorderTop,BOTTOMLEFT,2,1',
			scale = 1,
		},
		-- Calendar Button
		calendarButton = {
			enabled = true,
			position = 'TOPRIGHT,BorderTop,TOPRIGHT,2,2',
			scale = 1,
		},
		-- Mail Icon
		mailIcon = {
			enabled = true,
			position = 'LEFT,Tracking,RIGHT,2,0',
			scale = 1,
		},
		-- Instance Difficulty
		instanceDifficulty = {
			enabled = true,
			position = 'RIGHT,BorderTop,LEFT,2,0',
			scale = 0.8,
		},
		-- Queue Status (LFG eye)
		queueStatus = {
			enabled = true,
			position = 'BOTTOMLEFT,Minimap,BOTTOMLEFT,-15,45',
			scale = 0.85,
		},
		--Expansion Button
		expansionButton = {
			position = 'BOTTOMLEFT,Minimap,BOTTOMLEFT,0,0',
			scale = 0.6,
		},
		-- Addon Buttons
		addonButtons = {
			style = 'mouseover', -- 'always', 'mouseover', 'never', or 'bag'
			bagEnabled = false, -- Enable button bag consolidation (alternative to style='bag')
			excludeList = '', -- Comma-separated addon names to exclude from bag
			autoHideDelay = 2, -- Seconds before auto-hiding bag
			buttonsPerRow = 6, -- Number of buttons per row in the bag
			bagButtonAngle = 45, -- Angle position of bag toggle button on minimap (degrees)
			hiddenButtons = {}, -- Table of button names that are manually hidden
		},
	},
}

---@class SUI.Style.Settings.IMinimap : SUI.Style.Settings.Minimap
local BaseSettingsClassic = {
	-- Top-level settings
	shape = 'circle',
	size = { 140, 140 },
	scaleWithArt = true,
	UnderVehicleUI = true,
	position = 'TOPRIGHT,UIParent,TOPRIGHT,-20,-20',
	rotate = false,
	-- Elements (flat structure for Classic)
	background = {
		enabled = true,
		texture = 'Interface\\AddOns\\SpartanUI\\images\\minimap\\round',
		size = { 180, 180 },
		color = { 1, 1, 1, 1 },
		BlendMode = 'ADD',
		alpha = 1,
	},
	ZoneText = {
		enabled = true,
		scale = 1,
		position = 'TOP,Minimap,BOTTOM,0,-4',
		color = { 1, 0.82, 0, 1 },
	},
	coords = {
		enabled = true,
		scale = 1,
		size = { 80, 12 },
		position = 'TOP,Minimap,BOTTOM,0,-20',
		color = { 1, 1, 1, 1 },
		format = '%.1f, %.1f',
	},
	zoomButtons = {
		enabled = false,
		scale = 1,
		position = 'BOTTOMRIGHT,Minimap,BOTTOMRIGHT,-5,5',
		spacing = 2, -- Y gap between zoom in and zoom out buttons
		xOffset = 0, -- Additional X offset for the second button
	},
	clock = {
		enabled = false,
		scale = 0.7,
		position = 'TOP,Minimap,BOTTOM,0,-36',
		format = '%I:%M %p',
		color = { 1, 1, 1, 1 },
	},
	tracking = {
		enabled = true,
		scale = 1,
		position = 'TOPLEFT,Minimap,TOPLEFT,-5,-5',
	},
	mailIcon = {
		enabled = true,
		scale = 1,
	},
	instanceDifficulty = {
		enabled = true,
		scale = 0.8,
	},
	queueStatus = {
		enabled = true,
		scale = 0.85,
	},
	addonButtons = {
		style = 'mouseover', -- 'always', 'mouseover', 'never', or 'bag'
		bagEnabled = false,
		excludeList = '',
		autoHideDelay = 2,
		buttonsPerRow = 6,
		bagButtonAngle = 45,
		hiddenButtons = {}, -- Table of button names that are manually hidden
	},
}

local function IsMouseOver()
	for _, MouseFocus in ipairs(GetMouseFoci()) do
		if
			MouseFocus
			and not MouseFocus:IsForbidden()
			and ((MouseFocus:GetName() == 'Minimap') or (MouseFocus:GetParent() and MouseFocus:GetParent():GetName() and MouseFocus:GetParent():GetName():find('Mini[Mm]ap')))
		then
			return true
		end
	end

	return false
end

-- Check if Vehicle UI is actually active (not just in any vehicle)
local function IsVehicleUIActive()
	-- First check OverrideActionBar (most reliable)
	if OverrideActionBar and OverrideActionBar:IsVisible() then
		return true
	end

	-- Check if in vehicle AND has vehicle UI (excludes passengers, flight paths, etc)
	if UnitInVehicle('player') and UnitHasVehicleUI('player') then
		return true
	end

	-- Check possess bar (fallback for older content or edge cases)
	-- Note: PossessActionBar might not exist in all game versions
	if _G.PossessActionBar and _G.PossessActionBar:IsVisible() then
		return true
	end

	return false
end

-- Expose to module for options access
function module:IsVehicleUIActive()
	return IsVehicleUIActive()
end

-- Setup vehicle UI monitoring using the secure watcher frame
local function SetupVehicleUIMonitoring()
	-- Hook the watcher frame's visibility changes
	VehicleUIWatcher:HookScript('OnHide', function()
		-- Vehicle UI is now active (frame is hidden when vehicle UI shows)
		if module.Settings and module.Settings.UnderVehicleUI and module.Settings.useVehicleMover ~= false then
			module:SwitchMinimapPosition(true)
		end
	end)

	VehicleUIWatcher:HookScript('OnShow', function()
		-- Vehicle UI is no longer active (frame is shown when vehicle UI hides)
		if module.Settings and module.Settings.UnderVehicleUI and module.Settings.useVehicleMover ~= false then
			module:SwitchMinimapPosition(false)
		end
	end)
end

function module:Register(name, settings)
	Registry[name] = { settings = settings }
end

function module:UpdateSettings()
	-- Defensive check: if Artwork module isn't initialized yet, defer update
	if not SUI:GetActiveStyle() then
		return
	end

	-- Ensure active theme data is loaded (triggers BridgeToSubsystems which populates Registry)
	local currentStyle = module.styleOverride or SUI:GetActiveStyle()
	SUI.ThemeRegistry:GetData(currentStyle)

	module.Settings = nil
	-- Start with base settings (version-specific)
	---@type SUI.Style.Settings.IMinimap
	local baseSettings = SUI.IsRetail and BaseSettings or BaseSettingsClassic
	module.Settings = SUI:CopyData(baseSettings, {})
	if Registry[currentStyle] then
		module.Settings = SUI:MergeData(module.Settings, Registry[currentStyle].settings, true)
	end

	module.BaseOpt = SUI:CopyTable({}, module.Settings)
	-- Apply user custom settings
	if module.DB and module.DB.customSettings and module.DB.customSettings[currentStyle] then
		SUI:MergeData(module.Settings, module.DB.customSettings[currentStyle], true)
	end

	-- Normalize settings structure for easier access
	-- Classic uses flat structure, Retail uses nested .elements
	if not SUI.IsRetail and module.Settings.elements then
		-- Convert retail structure to classic if needed
		for key, value in pairs(module.Settings.elements) do
			if not module.Settings[key] then
				module.Settings[key] = value
			else
				-- Deep merge if both are tables to preserve theme overrides
				if type(module.Settings[key]) == 'table' and type(value) == 'table' then
					module.Settings[key] = SUI:MergeData(module.Settings[key], value, true)
				end
			end
		end
	end

	-- Debug logging for minimap settings verification
	if module.logger then
		module.logger.debug(string.format('Minimap Settings - Size: %dx%d, IsRetail: %s, Theme: %s', module.Settings.size[1], module.Settings.size[2], tostring(SUI.IsRetail), currentStyle))

		local bgSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.background or module.Settings.background
		if bgSettings then
			module.logger.debug(
				string.format('Background - Texture: %s, Size: %s', tostring(bgSettings.texture), bgSettings.size and string.format('%dx%d', bgSettings.size[1], bgSettings.size[2]) or 'nil')
			)
		end
	end
end

function module:ModifyMinimapLayout()
	module:UpdateMinimapSize()
	module:UpdateMinimapShape()

	-- Modify basic Minimap properties (retail only)
	if Minimap.SetArchBlobRingScalar then
		Minimap:SetArchBlobRingScalar(0)
	end
	if Minimap.SetQuestBlobRingScalar then
		Minimap:SetQuestBlobRingScalar(0)
	end

	-- Modify MinimapCluster (protected frame, skip in combat)
	if not InCombatLockdown() then
		MinimapCluster:EnableMouse(false)
		module.layoutModificationPending = false
	else
		module.layoutModificationPending = true
		if module.logger then
			module.logger.debug('Skipping MinimapCluster:EnableMouse() during combat - will reapply after combat ends')
		end
	end

	-- Modify MinimapBackdrop
	MinimapBackdrop:ClearAllPoints()
	MinimapBackdrop:SetPoint('CENTER', Minimap, 'CENTER', -10, -24)
	MinimapBackdrop:SetFrameLevel(Minimap:GetFrameLevel())

	MinimapCompassTexture:Hide()

	-- BorderTop and ZoneTextButton positioning (retail only)
	if SUI.IsRetail then
		module:SetupBorderTop()
	else
		-- Classic-specific modifications
		-- Hide the toggle button
		if MinimapToggleButton then
			MinimapToggleButton:Hide()
		end

		-- Enable mousewheel zoom
		Minimap:EnableMouseWheel(true)
		Minimap:SetScript('OnMouseWheel', function(_, delta)
			if delta > 0 then
				Minimap_ZoomIn()
			else
				Minimap_ZoomOut()
			end
		end)

		-- Position Minimap inside SUIMinimap holder
		Minimap:ClearAllPoints()
		Minimap:SetPoint('TOPLEFT', SUIMinimap, 'TOPLEFT', 0, 0)

		-- Hide all border textures comprehensively
		if MinimapBorderTop then
			MinimapBorderTop:Hide()
		end
		if MinimapBorder then
			MinimapBorder:Hide()
		end
		-- if MinimapBackdrop then
		-- 	MinimapBackdrop:Hide()
		-- end

		-- Hide or show north tag based on settings
		if MinimapNorthTag then
			if module.Settings.rotate then
				MinimapNorthTag:Show()
			else
				MinimapNorthTag:Hide()
			end
		end

		-- Position GameTimeFrame if it exists
		if GameTimeFrame then
			GameTimeFrame:ClearAllPoints()
			GameTimeFrame:SetPoint('TOPRIGHT', Minimap, 'TOPRIGHT', 20, -16)
			GameTimeFrame:SetScale(0.7)
			GameTimeFrame:SetFrameLevel(122)
			GameTimeFrame:GetRegions():Hide()
		end

		-- Position MiniMapInstanceDifficulty
		if MiniMapInstanceDifficulty then
			MiniMapInstanceDifficulty:ClearAllPoints()
			MiniMapInstanceDifficulty:SetPoint('TOPLEFT', Minimap, 'TOPLEFT', 4, 22)
		end

		-- Position and style MiniMapWorldMapButton
		if MiniMapWorldMapButton then
			MiniMapWorldMapButton:ClearAllPoints()
			MiniMapWorldMapButton:SetPoint('TOPRIGHT', Minimap, 'TOPRIGHT', -20, 12)
			MiniMapWorldMapButton:SetSize(32, 32)

			-- Hide all default textures
			for i = 1, MiniMapWorldMapButton:GetNumRegions() do
				local region = select(i, MiniMapWorldMapButton:GetRegions())
				if region and region:IsObjectType('Texture') then
					region:Hide()
				end
			end

			-- Create normal texture
			if not MiniMapWorldMapButton.SUI_NormalTexture then
				MiniMapWorldMapButton.SUI_NormalTexture = MiniMapWorldMapButton:CreateTexture(nil, 'BACKGROUND')
				MiniMapWorldMapButton.SUI_NormalTexture:SetAtlas('ShipMissionIcon-Bonus-MapBadge')
				MiniMapWorldMapButton.SUI_NormalTexture:SetAllPoints()
			end

			-- Create mouseover glow
			if not MiniMapWorldMapButton.SUI_HighlightTexture then
				MiniMapWorldMapButton.SUI_HighlightTexture = MiniMapWorldMapButton:CreateTexture(nil, 'HIGHLIGHT')
				MiniMapWorldMapButton.SUI_HighlightTexture:SetAtlas('ShipMission-RedGlowRing')
				MiniMapWorldMapButton.SUI_HighlightTexture:SetAllPoints()
				MiniMapWorldMapButton.SUI_HighlightTexture:SetBlendMode('ADD')
			end

			-- Create click glow
			if not MiniMapWorldMapButton.SUI_PushedTexture then
				MiniMapWorldMapButton.SUI_PushedTexture = MiniMapWorldMapButton:CreateTexture(nil, 'ARTWORK')
				MiniMapWorldMapButton.SUI_PushedTexture:SetAtlas('GarrLanding-SideToast-Glow')
				MiniMapWorldMapButton.SUI_PushedTexture:SetAllPoints()
				MiniMapWorldMapButton.SUI_PushedTexture:SetBlendMode('ADD')
				MiniMapWorldMapButton.SUI_PushedTexture:Hide()
			end

			-- Setup button textures
			MiniMapWorldMapButton:SetNormalTexture(MiniMapWorldMapButton.SUI_NormalTexture)
			MiniMapWorldMapButton:SetHighlightTexture(MiniMapWorldMapButton.SUI_HighlightTexture)
			MiniMapWorldMapButton:SetPushedTexture(MiniMapWorldMapButton.SUI_PushedTexture)
		end

		-- Position MiniMapMailFrame
		if MiniMapMailFrame then
			MiniMapMailFrame:ClearAllPoints()
			MiniMapMailFrame:SetPoint('TOPRIGHT', Minimap, 'TOPRIGHT', 21, -53)
		end

		-- Hide compass texture
		if MinimapCompassTexture then
			MinimapCompassTexture:Hide()
		end

		if MinimapCluster.BorderTop then
			MinimapCluster.BorderTop:Hide()
		end
	end

	-- Setup rotation if needed
	if MinimapCluster.SetRotateMinimap then
		if module.Settings.rotate then
			C_CVar.SetCVar('rotateMinimap', 1)
		end
	end
end

function module:UpdateMinimapSize()
	-- Set size of Minimap
	if module.Settings.size then
		Minimap:SetSize(unpack(module.Settings.size))
	end

	-- Set size of SUIMinimap (our holder)
	if SUI.IsRetail then
		-- Retail: Include BorderTop height
		local borderHeight = MinimapCluster.BorderTop and MinimapCluster.BorderTop:GetHeight() or 28
		SUIMinimap:SetSize(Minimap:GetWidth(), (Minimap:GetHeight() + borderHeight + 15))

		-- Set size of MinimapCluster BorderTop
		if MinimapCluster.BorderTop then
			MinimapCluster.BorderTop:SetWidth(Minimap:GetWidth() / 1.1)
			MinimapCluster.BorderTop:SetHeight(MinimapCluster.ZoneTextButton:GetHeight() * 2.8)
		end
	else
		-- Classic: Simpler calculation
		local extraHeight = 20
		-- Add space for coords if enabled
		if module.Settings.coords and module.Settings.coords.enabled then
			extraHeight = extraHeight + 15
		end
		SUIMinimap:SetSize(Minimap:GetWidth(), Minimap:GetHeight() + extraHeight)
	end

	-- Update overlay texture positioning if it exists to prevent clipping
	if Minimap.overlay then
		Minimap.overlay:SetAllPoints(Minimap)
	end

	-- Force minimap to refresh and re-render after size changes
	-- We delay this slightly to ensure the size changes have taken effect
	C_Timer.After(0.1, function()
		module:UpdateMinimapShape()

		-- Force minimap refresh by triggering various update methods
		if Minimap.RefreshAll then
			Minimap:RefreshAll()
		end

		-- Force a zoom update to refresh the display
		local currentZoom = Minimap:GetZoom()
		if currentZoom > 0 then
			Minimap:SetZoom(currentZoom - 1)
			C_Timer.After(0.05, function()
				Minimap:SetZoom(currentZoom)
			end)
		end

		-- Trigger minimap update events if available
		if MinimapCluster.UpdateBlips then
			MinimapCluster:UpdateBlips()
		end

		-- Force texture coordinate refresh
		if GetCVar('rotateMinimap') == '1' then
			-- Temporarily toggle rotation to force refresh
			local rotate = module.Settings.rotate
			C_CVar.SetCVar('rotateMinimap', rotate and '0' or '1')
			C_Timer.After(0.05, function()
				C_CVar.SetCVar('rotateMinimap', rotate and '1' or '0')
			end)
		end
	end)
end

function module:UpdateMinimapShape()
	-- Set Minimap shape
	Minimap:SetMaskTexture(module.Settings.shape == 'square' and 'Interface\\BUTTONS\\WHITE8X8' or 'Interface\\AddOns\\SpartanUI\\images\\minimap\\circle-overlay')

	-- Setup Minimap overlay
	if not Minimap.overlay then
		Minimap.overlay = Minimap:CreateTexture(nil, 'OVERLAY')
		Minimap.overlay:SetTexture('Interface\\AddOns\\SpartanUI\\images\\minimap\\square-overlay')
		Minimap.overlay:SetAllPoints(Minimap)
		Minimap.overlay:SetBlendMode('ADD')
	end
	Minimap.overlay:SetShown(module.Settings.shape == 'square')

	-- Setup GetMinimapShape function
	function GetMinimapShape()
		return module.Settings.shape == 'square' and 'SQUARE' or 'ROUND'
	end
end

function module:SetupElements()
	-- Modify the basic Minimap layout
	module:ModifyMinimapLayout()

	-- Setup background
	module:SetupBackground()

	-- Setup Zone Text
	module:SetupZoneText()

	-- Setup Coordinates
	module:SetupCoords()

	-- Setup Clock
	module:SetupClock()

	-- Setup Tracking Icon
	module:SetupTracking()

	-- Setup Calendar Button
	module:SetupCalendarButton()

	-- Setup Instance Difficulty
	module:SetupInstanceDifficulty()

	-- Setup Queue Status (LFG eye)
	module:SetupQueueStatus()

	-- Setup Mail Icon
	module:SetupMailIcon()

	-- Setup North Indicator
	module:SetupExpansionButton()

	-- Setup addon buttons
	module:SetupAddonButtons()

	-- Setup addon buttons
	module:SetupZoomButtons()
end

function module:PositionItem(obj, position)
	if type(position) == 'table' then
		local name = obj:GetName()
		if name then
			SUI:Error('Minimap', 'Position for ' .. name .. ' is bad. Please report this error along with an export of your minimap settings.')
		end
		return
	end
	local point, anchor, secondaryPoint, x, y = strsplit(',', position)
	if MinimapCluster[anchor] then
		anchor = MinimapCluster[anchor]
	elseif type(anchor) == 'string' and not _G[anchor] then
		-- Anchor region doesn't exist (Classic compatibility), fall back to Minimap
		anchor = Minimap
	end

	obj:ClearAllPoints()
	obj:SetPoint(point, anchor, secondaryPoint, x, y)
end

function module:SetupBackground()
	-- Get background settings (handle both Retail nested and Classic flat structure)
	local bgSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.background or module.Settings.background

	-- Hide background if: no settings, enabled is false, or no texture is defined
	if not bgSettings or bgSettings.enabled == false or not bgSettings.texture then
		if SUIMinimap.BG then
			SUIMinimap.BG:Hide()
			SUIMinimap.BG:SetTexture(nil)
		end
		return
	end

	-- Background is enabled and has a texture - show it
	if bgSettings.enabled ~= false then
		if not SUIMinimap.BG then
			SUIMinimap.BG = SUIMinimap:CreateTexture(nil, 'BACKGROUND', nil, -8)
		end

		SUIMinimap.BG:SetTexture(bgSettings.texture)

		if bgSettings.size then
			SUIMinimap.BG:SetSize(unpack(bgSettings.size))
		end
		if bgSettings.position then
			module:PositionItem(SUIMinimap.BG, bgSettings.position)
		else
			SUIMinimap.BG:ClearAllPoints()
			SUIMinimap.BG:SetPoint('TOPLEFT', Minimap, 'TOPLEFT', -30, 30)
			SUIMinimap.BG:SetPoint('BOTTOMRIGHT', Minimap, 'BOTTOMRIGHT', 30, -30)
		end

		if bgSettings.color then
			SUIMinimap.BG:SetVertexColor(unpack(bgSettings.color))
		end
		if bgSettings.BlendMode then
			SUIMinimap.BG:SetBlendMode(bgSettings.BlendMode)
		end
		if bgSettings.alpha then
			SUIMinimap.BG:SetAlpha(bgSettings.alpha)
		end
		SUIMinimap.BG:Show()
	end
end

function module:SetupBorderTop()
	-- BorderTop is Retail only
	if not SUI.IsRetail or not MinimapCluster.BorderTop then
		return
	end

	local borderSettings = module.Settings.elements and module.Settings.elements.BorderTop
	if not borderSettings then
		return
	end

	if borderSettings.enabled == false then
		MinimapCluster.BorderTop:Hide()
		return
	end

	-- Position BorderTop
	if borderSettings.position then
		module:PositionItem(MinimapCluster.BorderTop, borderSettings.position)
	else
		MinimapCluster.BorderTop:ClearAllPoints()
		MinimapCluster.BorderTop:SetPoint('TOP', Minimap, 'BOTTOM', 0, -5)
	end

	-- Set alpha
	local alpha = borderSettings.alpha or 0.8
	MinimapCluster.BorderTop:SetAlpha(alpha)

	-- Set scale
	local scale = borderSettings.scale or 1
	MinimapCluster.BorderTop:SetScale(scale)

	MinimapCluster.BorderTop:Show()

	-- Position ZoneTextButton relative to BorderTop
	if MinimapCluster.ZoneTextButton then
		MinimapCluster.ZoneTextButton:ClearAllPoints()
		MinimapCluster.ZoneTextButton:SetPoint('TOPLEFT', MinimapCluster.BorderTop, 'TOPLEFT', 4, -4)
		MinimapCluster.ZoneTextButton:SetPoint('TOPRIGHT', MinimapCluster.BorderTop, 'TOPRIGHT', -15, -4)
	end
end

function module:SetupZoomButtons()
	local zoomSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.zoomButtons or module.Settings.zoomButtons
	if not zoomSettings then
		return
	end

	-- Check for zoom buttons (different names in different versions)
	local zoomIn = Minimap.ZoomIn or MinimapZoomIn
	local zoomOut = Minimap.ZoomOut or MinimapZoomOut
	if not zoomIn or not zoomOut then
		return
	end

	if zoomSettings.enabled then
		zoomIn:Show()
		zoomOut:Show()
		zoomIn:SetScale(zoomSettings.scale or 1)
		zoomOut:SetScale(zoomSettings.scale or 1)

		-- Position zoom buttons if position is specified
		if zoomSettings.position then
			module:PositionItem(zoomIn, zoomSettings.position)
			-- Position zoom out relative to zoom in with spacing and xOffset
			local spacing = zoomSettings.spacing or 2
			local xOffset = zoomSettings.xOffset or 0
			zoomOut:ClearAllPoints()
			zoomOut:SetPoint('TOP', zoomIn, 'BOTTOM', xOffset, -spacing)
		end

		-- Store references to zoom buttons for fade handling
		module.zoomIn = zoomIn
		module.zoomOut = zoomOut

		-- Ensure zoom buttons respect the addonButtons style setting
		local addonSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.addonButtons or module.Settings.addonButtons
		local style = addonSettings and addonSettings.style or 'mouseover'
		module.logger.debug('SetupZoomButtons - addonButtons style: ' .. tostring(style))

		if style == 'always' then
			-- Always visible - ensure alpha is 1 and stop any fade animations
			zoomIn:SetAlpha(1)
			zoomOut:SetAlpha(1)
			if zoomIn.fadeOutAnim then
				zoomIn.fadeOutAnim:Stop()
			end
			if zoomOut.fadeOutAnim then
				zoomOut.fadeOutAnim:Stop()
			end

			-- In Retail, Blizzard's MinimapMixin:OnLeave() calls Hide() on zoom buttons
			-- We need to override this behavior for 'always' mode
			if SUI.IsRetail then
				-- Hook the Hide method to prevent hiding when style is 'always'
				if not zoomIn.SUI_HideHooked then
					zoomIn.SUI_OriginalHide = zoomIn.Hide
					zoomIn.Hide = function(self)
						local currentAddonSettings = module.Settings.elements and module.Settings.elements.addonButtons or module.Settings.addonButtons
						local currentStyle = currentAddonSettings and currentAddonSettings.style or 'mouseover'
						if currentStyle == 'always' then
							return -- Don't hide when style is 'always'
						end
						zoomIn.SUI_OriginalHide(self)
					end
					zoomIn.SUI_HideHooked = true
				end
				if not zoomOut.SUI_HideHooked then
					zoomOut.SUI_OriginalHide = zoomOut.Hide
					zoomOut.Hide = function(self)
						local currentAddonSettings = module.Settings.elements and module.Settings.elements.addonButtons or module.Settings.addonButtons
						local currentStyle = currentAddonSettings and currentAddonSettings.style or 'mouseover'
						if currentStyle == 'always' then
							return -- Don't hide when style is 'always'
						end
						zoomOut.SUI_OriginalHide(self)
					end
					zoomOut.SUI_HideHooked = true
				end
			end
		elseif style == 'never' then
			-- Never visible
			zoomIn:SetAlpha(0)
			zoomOut:SetAlpha(0)
		end
		-- For 'mouseover', let the normal fade handling work
	else
		zoomIn:Hide()
		zoomOut:Hide()
	end
end

function module:SetupZoneText()
	local zoneSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.ZoneText or module.Settings.ZoneText
	if not zoneSettings then
		return
	end

	if not SUI.IsRetail then
		-- Classic: Create custom zone text display below minimap
		if zoneSettings.enabled then
			if not Minimap.ZoneText then
				Minimap.ZoneText = Minimap:CreateFontString(nil, 'OVERLAY')
				SUI.Font:Format(Minimap.ZoneText, 11, 'Minimap')
				Minimap.ZoneText:SetJustifyH('CENTER')
				Minimap.ZoneText:SetJustifyV('MIDDLE')
			end

			if zoneSettings.position then
				module:PositionItem(Minimap.ZoneText, zoneSettings.position)
			end

			local color = zoneSettings.color or zoneSettings.TextColor
			if color then
				Minimap.ZoneText:SetTextColor(unpack(color))
			end
			Minimap.ZoneText:SetShadowColor(0, 0, 0, 1)
			Minimap.ZoneText:SetScale(zoneSettings.scale or 1)
			Minimap.ZoneText:Show()

			-- Hide default zone text button and use our custom one
			if MinimapZoneTextButton then
				MinimapZoneTextButton:SetAlpha(0)
				MinimapZoneTextButton:EnableMouse(false)
			end

			-- Update zone text immediately
			module:UpdateClassicZoneText()
		elseif Minimap.ZoneText then
			Minimap.ZoneText:Hide()
			-- Restore default zone text
			if MinimapZoneTextButton then
				MinimapZoneTextButton:SetAlpha(1)
				MinimapZoneTextButton:EnableMouse(true)
			end
		end
	else
		-- Retail: Use standard ZoneTextButton
		local zoneButton = MinimapCluster.ZoneTextButton
		if not zoneButton then
			return
		end

		if zoneSettings.enabled then
			if zoneSettings.position then
				module:PositionItem(zoneButton, zoneSettings.position)
			end

			if MinimapZoneText then
				local color = zoneSettings.color or zoneSettings.TextColor
				if color then
					MinimapZoneText:SetTextColor(unpack(color))
				end
				MinimapZoneText:SetShadowColor(0, 0, 0, 1)
				SUI.Font:Format(MinimapZoneText, 10, 'Minimap')
				MinimapZoneText:SetJustifyH('CENTER')
			end

			zoneButton:SetScale(zoneSettings.scale or 1)
			zoneButton:Show()
		else
			zoneButton:Hide()
		end
	end
end

function module:UpdateClassicZoneText()
	if SUI.IsRetail or not Minimap.ZoneText or not Minimap.ZoneText:IsShown() then
		return
	end

	-- Get zone text and update our custom display
	local zoneText = GetMinimapZoneText()
	if zoneText then
		Minimap.ZoneText:SetText(zoneText)
	end
end

function module:SetupCoords()
	local coordSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.coords or module.Settings.coords
	if not coordSettings then
		return
	end

	if coordSettings.enabled then
		if not Minimap.coords then
			Minimap.coords = Minimap:CreateFontString(nil, 'OVERLAY')
		end
		SUI.Font:Format(Minimap.coords, 10, 'Minimap')

		-- For Classic/TBC, if ZoneText exists, position relative to it instead of using the position string
		if not SUI.IsRetail and Minimap.ZoneText and Minimap.ZoneText:IsShown() then
			Minimap.coords:ClearAllPoints()
			Minimap.coords:SetPoint('TOP', Minimap.ZoneText, 'BOTTOM', 0, -4)
		elseif coordSettings.position then
			module:PositionItem(Minimap.coords, coordSettings.position)
		end

		local color = coordSettings.color or coordSettings.TextColor
		if color then
			Minimap.coords:SetTextColor(unpack(color))
		end
		Minimap.coords:SetShadowColor(0, 0, 0, 1)
		Minimap.coords:SetScale(coordSettings.scale or 1)

		if coordSettings.size then
			Minimap.coords:SetSize(unpack(coordSettings.size))
		end
		Minimap.coords:SetJustifyH('CENTER')
		Minimap.coords:Show()
		module:SetupCoordinatesUpdater()
	elseif Minimap.coords then
		Minimap.coords:Hide()
	end
end

function module:SetupCoordinatesUpdater()
	if self.coordsTimer then
		return
	end

	self.coordsTimer = self:ScheduleRepeatingTimer(function()
		local mapID = C_Map.GetBestMapForUnit('player')
		if not mapID then
			return
		end
		local pos = C_Map.GetPlayerMapPosition(mapID, 'player')
		if not pos then
			return
		end
		if pos.x and pos.y then
			local coordSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.coords or module.Settings.coords
			local format = coordSettings and coordSettings.format or '%.1f, %.1f'
			Minimap.coords:SetText(string.format(format, pos.x * 100, pos.y * 100))
		end
	end, 0.5)
end

function module:SetupClock()
	local clockSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.clock or module.Settings.clock
	if not clockSettings or not clockSettings.enabled then
		if TimeManagerClockButton then
			TimeManagerClockButton:Hide()
		end
		if GameTimeFrame then
			GameTimeFrame:Hide()
		end
		return
	end

	if not GameTimeFrame then
		-- Retail: TimeManagerClockButton
		if not TimeManagerClockButton then
			C_AddOns.LoadAddOn('Blizzard_TimeManager')
		end
		if TimeManagerClockButton then
			if clockSettings.position then
				module:PositionItem(TimeManagerClockButton, clockSettings.position)
			end
			TimeManagerClockButton:SetScale(clockSettings.scale or 1)
			if TimeManagerClockTicker and clockSettings.color then
				TimeManagerClockTicker:SetTextColor(unpack(clockSettings.color))
				SUI.Font:Format(TimeManagerClockTicker, 10, 'Minimap')
			end
			TimeManagerClockButton:Show()
		end
	else
		-- Classic: GameTimeFrame is positioned in ModifyMinimapLayout
		-- Just ensure it's visible and scaled
		if GameTimeFrame then
			GameTimeFrame:SetScale(clockSettings.scale or 0.7)
			GameTimeFrame:Show()
		end
	end
end

function module:SetupMailIcon()
	local mailSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.mailIcon or module.Settings.mailIcon
	if not mailSettings then
		return
	end

	-- Get mail frame - different in Retail vs Classic
	local mailFrame
	if SUI.IsRetail then
		mailFrame = MinimapCluster.IndicatorFrame and MinimapCluster.IndicatorFrame.MailFrame
	else
		mailFrame = MiniMapMailFrame
	end

	if not mailFrame then
		return
	end

	if mailSettings.enabled then
		-- Mark the MailFrame to be ignored by the IndicatorFrame's automatic layout
		if SUI.IsRetail and mailFrame then
			mailFrame.ignoreInLayout = true
		end

		if mailSettings.position then
			module:PositionItem(mailFrame, mailSettings.position)
		end
		mailFrame:SetScale(mailSettings.scale or 1)
		-- mailFrame:Show()

		-- Hook the animation finished event to reapply our positioning
		if SUI.IsRetail and mailFrame.NewMailAnim and not mailFrame.NewMailAnim.suiHooked then
			mailFrame.NewMailAnim:HookScript('OnFinished', function()
				-- Reapply our custom positioning after animation completes
				if mailSettings.position then
					module:PositionItem(mailFrame, mailSettings.position)
				end
			end)
			mailFrame.NewMailAnim.suiHooked = true
		end

		if SUI.IsRetail and mailFrame.MailReminderAnim and not mailFrame.MailReminderAnim.suiHooked then
			mailFrame.MailReminderAnim:HookScript('OnFinished', function()
				-- Reapply our custom positioning after animation completes
				if mailSettings.position then
					module:PositionItem(mailFrame, mailSettings.position)
				end
			end)
			mailFrame.MailReminderAnim.suiHooked = true
		end
		-- else
		-- mailFrame:Hide()
	end
end

function module:SetupTracking()
	local trackingSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.tracking or module.Settings.tracking
	if not trackingSettings then
		return
	end

	-- Get tracking frame - different in Retail vs Classic
	local tracking
	if SUI.IsRetail then
		tracking = MinimapCluster.TrackingFrame or MinimapCluster.Tracking
	else
		tracking = MiniMapTracking
	end

	if not tracking then
		return
	end

	if trackingSettings.enabled then
		if trackingSettings.position then
			module:PositionItem(tracking, trackingSettings.position)
		end
		tracking:SetScale(trackingSettings.scale or 1)

		-- Hide background if it exists (Retail)
		if tracking.Background then
			tracking.Background:Hide()
		end

		tracking:Show()
	else
		tracking:Hide()
	end
end

function module:SetupCalendarButton()
	if not SUI.IsRetail then
		return
	end -- Calendar button is Retail-only

	local calendarSettings = module.Settings.elements and module.Settings.elements.calendarButton
	if not calendarSettings then
		return
	end

	if calendarSettings.enabled and GameTimeFrame then
		if calendarSettings.position then
			module:PositionItem(GameTimeFrame, calendarSettings.position)
		end
		GameTimeFrame:SetScale(calendarSettings.scale or 1)
		GameTimeFrame:Show()
	elseif GameTimeFrame then
		GameTimeFrame:Hide()
	end
end

function module:SetupInstanceDifficulty()
	local difficultySettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.instanceDifficulty or module.Settings.instanceDifficulty
	if not difficultySettings then
		return
	end

	-- Get instance difficulty frame - different in Retail vs Classic
	local difficulty
	if SUI.IsRetail then
		difficulty = MinimapCluster.InstanceDifficulty
	else
		difficulty = MiniMapInstanceDifficulty
	end

	if not difficulty then
		return
	end

	if difficultySettings.enabled then
		if difficultySettings.position then
			module:PositionItem(difficulty, difficultySettings.position)
		end
		difficulty:SetScale(difficultySettings.scale or 0.8)
	end
end

function module:SetupQueueStatus()
	local queueSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.queueStatus or module.Settings.queueStatus
	if not queueSettings then
		return
	end

	-- Get queue/battlefield frame - different in Retail vs Classic
	local queueFrame
	if SUI.IsRetail then
		queueFrame = QueueStatusButton
	else
		queueFrame = MiniMapBattlefieldFrame
	end

	if not queueFrame then
		return
	end

	if queueSettings.enabled then
		if queueSettings.position then
			module:PositionItem(queueFrame, queueSettings.position)
		end
		queueFrame:SetScale(queueSettings.scale or 0.85)
	end
end

function module:SetupExpansionButton()
	if not SUI.IsRetail then
		return
	end -- Expansion button is Retail-only
	if not ExpansionLandingPageMinimapButton then
		return
	end

	ExpansionLandingPageMinimapButton:SetScale(module.Settings.elements.expansionButton.scale)
	module:PositionItem(ExpansionLandingPageMinimapButton, module.Settings.elements.expansionButton.position)
end

local isFrameIgnored = function(item)
	local ignored = { 'HybridMinimap', 'AAP-Classic', 'HandyNotes' }
	local WildcardIgnore = { 'Questie', 'HandyNotes', 'TTMinimap' }
	if not item or not item.GetName then
		return false
	end

	local name = item:GetName()
	if name ~= nil then
		if SUI:IsInTable(ignored, name) then
			return true
		end

		for _, v in ipairs(WildcardIgnore) do
			if string.match(name, v) then
				return true
			end
		end
	end
	return false
end

function module:SetupAddonButtons()
	-- Check if bag mode is active - if so, don't set up fading
	local addonSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.addonButtons or module.Settings.addonButtons
	local style = addonSettings and addonSettings.style or 'mouseover'

	if style == 'bag' then
		-- Bag mode handles buttons differently, skip fading setup
		return
	end

	local function setupButtonFading(button)
		local name = button:GetName()
		if button.fadeInAnim then
			return
		end -- Already set up

		button.fadeInAnim = button:CreateAnimationGroup()
		local fadeIn = button.fadeInAnim:CreateAnimation('Alpha')
		fadeIn:SetFromAlpha(0)
		fadeIn:SetToAlpha(1)
		fadeIn:SetDuration(0.2)
		button.fadeInAnim:SetToFinalAlpha(true)

		button.fadeOutAnim = button:CreateAnimationGroup()
		local fadeOut = button.fadeOutAnim:CreateAnimation('Alpha')
		fadeOut:SetFromAlpha(1)
		fadeOut:SetToAlpha(0)
		fadeOut:SetDuration(0.3)
		fadeOut:SetStartDelay(0.5)
		button.fadeOutAnim:SetToFinalAlpha(true)

		-- Set initial alpha based on style setting
		if style == 'always' then
			button:SetAlpha(1)
		else
			-- For 'mouseover' and 'never', start hidden
			button:SetAlpha(0)
		end
	end

	-- Check if a button is a disabled zoom button
	local function isDisabledZoomButton(button)
		local zoomIn = Minimap.ZoomIn or MinimapZoomIn
		local zoomOut = Minimap.ZoomOut or MinimapZoomOut
		if button == zoomIn or button == zoomOut then
			local zoomSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.zoomButtons or module.Settings.zoomButtons
			if zoomSettings and not zoomSettings.enabled then
				return true
			end
		end
		return false
	end

	local function showAllButtons()
		-- Check the current style
		local currentSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.addonButtons or module.Settings.addonButtons
		local currentStyle = currentSettings and currentSettings.style or 'mouseover'

		-- For 'always' mode, ensure buttons stay visible by stopping any fade animations
		-- For 'mouseover' mode, show buttons on hover
		-- For 'never' mode, do nothing (buttons stay hidden)
		if currentStyle == 'never' then
			return
		end

		for _, child in ipairs({ Minimap:GetChildren() }) do
			if child:IsObjectType('Button') and child.fadeInAnim and not isDisabledZoomButton(child) then
				child.fadeInAnim:Stop()
				child.fadeOutAnim:Stop()
				child:SetAlpha(1)
			end
		end

		-- Explicitly handle zoom buttons (they may be parented to MinimapCluster, not Minimap)
		local zoomSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.zoomButtons or module.Settings.zoomButtons
		if zoomSettings and zoomSettings.enabled then
			if module.zoomIn then
				if module.zoomIn.fadeInAnim then
					module.zoomIn.fadeInAnim:Stop()
				end
				if module.zoomIn.fadeOutAnim then
					module.zoomIn.fadeOutAnim:Stop()
				end
				module.zoomIn:SetAlpha(1)
			end
			if module.zoomOut then
				if module.zoomOut.fadeInAnim then
					module.zoomOut.fadeInAnim:Stop()
				end
				if module.zoomOut.fadeOutAnim then
					module.zoomOut.fadeOutAnim:Stop()
				end
				module.zoomOut:SetAlpha(1)
			end
		end

		-- Process MinimapBackdrop children for Classic
		if not SUI.IsRetail and MinimapBackdrop then
			for _, child in ipairs({ MinimapBackdrop:GetChildren() }) do
				if child.fadeInAnim and not isDisabledZoomButton(child) then
					child.fadeInAnim:Stop()
					child.fadeOutAnim:Stop()
					child:SetAlpha(1)
				end
			end
		end
	end

	local function hideAllButtons()
		-- Check the current style - only hide on mouse leave for 'mouseover' mode
		local currentSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.addonButtons or module.Settings.addonButtons
		local currentStyle = currentSettings and currentSettings.style or 'mouseover'

		-- For 'always' mode, ensure buttons stay visible - stop any fade animations and keep alpha at 1
		if currentStyle == 'always' then
			for _, child in ipairs({ Minimap:GetChildren() }) do
				if child:IsObjectType('Button') and child.fadeOutAnim and not isDisabledZoomButton(child) then
					child.fadeInAnim:Stop()
					child.fadeOutAnim:Stop()
					child:SetAlpha(1)
				end
			end

			-- Explicitly handle zoom buttons for 'always' mode
			local zoomSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.zoomButtons or module.Settings.zoomButtons
			if zoomSettings and zoomSettings.enabled then
				if module.zoomIn then
					if module.zoomIn.fadeOutAnim then
						module.zoomIn.fadeOutAnim:Stop()
					end
					module.zoomIn:SetAlpha(1)
				end
				if module.zoomOut then
					if module.zoomOut.fadeOutAnim then
						module.zoomOut.fadeOutAnim:Stop()
					end
					module.zoomOut:SetAlpha(1)
				end
			end

			-- Process MinimapBackdrop children for Classic
			if not SUI.IsRetail and MinimapBackdrop then
				for _, child in ipairs({ MinimapBackdrop:GetChildren() }) do
					if child.fadeOutAnim and not isDisabledZoomButton(child) then
						child.fadeInAnim:Stop()
						child.fadeOutAnim:Stop()
						child:SetAlpha(1)
					end
				end
			end
			return
		end

		-- For 'never' mode, keep buttons hidden
		if currentStyle == 'never' then
			return
		end

		-- For 'mouseover' mode, fade out buttons
		for _, child in ipairs({ Minimap:GetChildren() }) do
			if child:IsObjectType('Button') and child.fadeOutAnim and not isDisabledZoomButton(child) then
				child.fadeInAnim:Stop()
				child.fadeOutAnim:Play()
			end
		end

		-- For mouseover mode, also fade out zoom buttons
		local zoomSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.zoomButtons or module.Settings.zoomButtons
		if zoomSettings and zoomSettings.enabled then
			if module.zoomIn and module.zoomIn.fadeOutAnim then
				module.zoomIn.fadeInAnim:Stop()
				module.zoomIn.fadeOutAnim:Play()
			end
			if module.zoomOut and module.zoomOut.fadeOutAnim then
				module.zoomOut.fadeInAnim:Stop()
				module.zoomOut.fadeOutAnim:Play()
			end
		end

		-- Process MinimapBackdrop children for Classic
		if not SUI.IsRetail and MinimapBackdrop then
			for _, child in ipairs({ MinimapBackdrop:GetChildren() }) do
				if child.fadeOutAnim and not isDisabledZoomButton(child) then
					child.fadeInAnim:Stop()
					child.fadeOutAnim:Play()
				end
			end
		end
	end

	-- Set up fading for existing buttons
	for _, child in ipairs({ Minimap:GetChildren() }) do
		if child:IsObjectType('Button') then
			setupButtonFading(child)
			child:HookScript('OnEnter', showAllButtons)
			child:HookScript('OnLeave', hideAllButtons)
		end
	end

	-- Process MinimapBackdrop children for Classic
	if not SUI.IsRetail and MinimapBackdrop then
		for _, child in ipairs({ MinimapBackdrop:GetChildren() }) do
			-- if child:IsObjectType('Button') then
			setupButtonFading(child)
			child:HookScript('OnEnter', showAllButtons)
			child:HookScript('OnLeave', hideAllButtons)
			-- end
		end
	end

	-- Hook the Minimap to catch newly added buttons
	Minimap:HookScript('OnEvent', function(self, event, ...)
		if event == 'ADDON_LOADED' then
			C_Timer.After(0.1, function()
				for _, child in ipairs({ self:GetChildren() }) do
					if child:IsObjectType('Button') and not child.fadeInAnim and not isFrameIgnored(child) then
						setupButtonFading(child)
						child:HookScript('OnEnter', showAllButtons)
						child:HookScript('OnLeave', hideAllButtons)
					end
				end

				-- Process MinimapBackdrop children for Classic
				if not SUI.IsRetail and MinimapBackdrop then
					for _, child in ipairs({ MinimapBackdrop:GetChildren() }) do
						if child:IsObjectType('Button') and not child.fadeInAnim and not isFrameIgnored(child) then
							setupButtonFading(child)
							child:HookScript('OnEnter', showAllButtons)
							child:HookScript('OnLeave', hideAllButtons)
						end
					end
				end
			end)
		end
	end)
	Minimap:RegisterEvent('ADDON_LOADED')

	-- Hook the Minimap itself for mouse events
	Minimap:HookScript('OnEnter', showAllButtons)
	Minimap:HookScript('OnLeave', hideAllButtons)

	-- Also hook SUIMinimap holder frame to ensure mouse events are caught
	-- This is especially important for Classic where the holder might intercept events
	SUIMinimap:HookScript('OnEnter', showAllButtons)
	SUIMinimap:HookScript('OnLeave', hideAllButtons)

	-- Hook MinimapBackdrop for Classic clients
	if not SUI.IsRetail and MinimapBackdrop then
		MinimapBackdrop:HookScript('OnEnter', showAllButtons)
		MinimapBackdrop:HookScript('OnLeave', hideAllButtons)
	end

	-- Register for LibDBIcon callback to catch icons created after initial setup
	local LDBIcon = LibStub and LibStub('LibDBIcon-1.0', true)
	if LDBIcon then
		LDBIcon.RegisterCallback(module, 'LibDBIcon_IconCreated', function(_, button, name)
			if button and not button.fadeInAnim and not isFrameIgnored(button) then
				setupButtonFading(button)
				button:HookScript('OnEnter', showAllButtons)
				button:HookScript('OnLeave', hideAllButtons)
			end
		end)
	end
end

function module:UpdateAddonButtons()
	local addonSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.addonButtons or module.Settings.addonButtons
	if not addonSettings then
		return
	end

	local style = addonSettings.style or 'mouseover'

	-- Handle button bag mode
	if style == 'bag' then
		-- Setup button bag (will check if already setup)
		module:SetupButtonBag()
		-- Show the toggle button if it exists
		if ButtonBag.toggleButton then
			ButtonBag.toggleButton:Show()
		end
		return
	else
		-- If switching away from bag mode, destroy the bag
		if ButtonBag.frame or ButtonBag.toggleButton then
			module:DestroyButtonBag()
		end
	end

	if style == 'always' then
		for _, child in ipairs({ Minimap:GetChildren() }) do
			if child:IsObjectType('Button') and not isFrameIgnored(child) then
				child:SetAlpha(1)
			end
		end
		-- Process MinimapBackdrop children for Classic
		if not SUI.IsRetail and MinimapBackdrop then
			for _, child in ipairs({ MinimapBackdrop:GetChildren() }) do
				if child:IsObjectType('Button') and not isFrameIgnored(child) then
					child:SetAlpha(1)
				end
			end
		end
	elseif style == 'never' then
		for _, child in ipairs({ Minimap:GetChildren() }) do
			if child:IsObjectType('Button') and not isFrameIgnored(child) then
				child:SetAlpha(0)
			end
		end
		-- Process MinimapBackdrop children for Classic
		if not SUI.IsRetail and MinimapBackdrop then
			for _, child in ipairs({ MinimapBackdrop:GetChildren() }) do
				if child:IsObjectType('Button') and not isFrameIgnored(child) then
					child:SetAlpha(0)
				end
			end
		end
	else -- "mouseover"
		-- The showing/hiding is handled by the OnEnter/OnLeave scripts
		for _, child in ipairs({ Minimap:GetChildren() }) do
			if child:IsObjectType('Button') and not isFrameIgnored(child) then
				child:SetAlpha(0) -- Start hidden
			end
		end
		-- Process MinimapBackdrop children for Classic
		if not SUI.IsRetail and MinimapBackdrop then
			for _, child in ipairs({ MinimapBackdrop:GetChildren() }) do
				if child:IsObjectType('Button') and not isFrameIgnored(child) then
					child:SetAlpha(0) -- Start hidden
				end
			end
		end
	end

	-- Apply manual button visibility settings (hide individually disabled buttons)
	module:ApplyAllButtonVisibility()
end

-- Button Bag functionality
function module:SetupButtonBag()
	local addonSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.addonButtons or module.Settings.addonButtons
	if not addonSettings then
		if module.logger then
			module.logger.debug('ButtonBag: No addonSettings found')
		end
		return
	end

	-- Button bag is enabled either via style='bag' or bagEnabled=true
	local bagEnabled = addonSettings.style == 'bag' or addonSettings.bagEnabled
	if module.logger then
		module.logger.info('ButtonBag: Setup called - style=' .. tostring(addonSettings.style) .. ', bagEnabled=' .. tostring(bagEnabled))
	end

	if not bagEnabled then
		-- If bag is disabled, destroy it if it was previously active
		if ButtonBag.frame and ButtonBag.frame:IsShown() then
			module:DestroyButtonBag()
		end
		return
	end

	local LDBIcon = LibStub and LibStub('LibDBIcon-1.0', true)
	if not LDBIcon then
		if module.logger then
			module.logger.warning('ButtonBag: LibDBIcon-1.0 not available')
		end
		return
	end

	-- Create the bag container frame
	if not ButtonBag.frame then
		local bagFrame = CreateFrame('Frame', 'SUI_MinimapButtonBag', UIParent, BackdropTemplateMixin and 'BackdropTemplate')
		bagFrame:SetSize(200, 40)
		bagFrame:SetFrameStrata('MEDIUM')
		bagFrame:SetFrameLevel(1)
		bagFrame:SetBackdrop({
			bgFile = 'Interface\\Buttons\\WHITE8X8',
			edgeFile = 'Interface\\Buttons\\WHITE8X8',
			edgeSize = 1,
		})
		bagFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
		bagFrame:SetBackdropBorderColor(0, 0, 0, 1)
		bagFrame:Hide()
		bagFrame:EnableMouse(true)

		-- Auto-hide timer
		bagFrame.hideTimer = nil
		bagFrame:SetScript('OnEnter', function(self)
			if self.hideTimer then
				self.hideTimer:Cancel()
				self.hideTimer = nil
			end
		end)
		bagFrame:SetScript('OnLeave', function(self)
			local delay = addonSettings.autoHideDelay or 2
			self.hideTimer = C_Timer.NewTimer(delay, function()
				module:CloseButtonBag()
			end)
		end)

		ButtonBag.frame = bagFrame
	end

	-- Create the toggle button - use LibDBIcon style positioning
	if not ButtonBag.toggleButton then
		local toggleBtn = CreateFrame('Button', 'SUI_MinimapButtonBagToggle', Minimap)
		toggleBtn:SetSize(32, 32)
		toggleBtn:SetFrameStrata('MEDIUM')
		toggleBtn:SetFrameLevel(8)
		toggleBtn:SetHighlightTexture(136477) -- Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight
		toggleBtn:RegisterForDrag('LeftButton')
		toggleBtn:SetMovable(true)

		-- Use simple icon approach like most minimap buttons
		local icon = toggleBtn:CreateTexture(nil, 'ARTWORK')
		icon:SetSize(20, 20)
		icon:SetPoint('CENTER')
		icon:SetTexture('Interface\\Icons\\INV_Misc_Bag_07') -- Bag icon
		toggleBtn.icon = icon

		-- Create overlay/border
		local overlay = toggleBtn:CreateTexture(nil, 'OVERLAY')
		overlay:SetSize(54, 54)
		overlay:SetPoint('TOPLEFT')
		overlay:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
		toggleBtn.overlay = overlay

		-- Position on minimap edge using angle
		local function UpdateButtonPosition()
			local angle = addonSettings.bagButtonAngle or 45
			local radius = (Minimap:GetWidth() / 2) + 5
			local rads = math.rad(angle)
			local x = math.cos(rads) * radius
			local y = math.sin(rads) * radius
			toggleBtn:ClearAllPoints()
			toggleBtn:SetPoint('CENTER', Minimap, 'CENTER', x, y)
		end

		-- Dragging to reposition around minimap edge
		toggleBtn:SetScript('OnDragStart', function(self)
			self.isDragging = true
		end)

		toggleBtn:SetScript('OnDragStop', function(self)
			self.isDragging = false
			-- Calculate angle from center of minimap
			local mx, my = Minimap:GetCenter()
			local px, py = self:GetCenter()
			local angle = math.deg(math.atan2(py - my, px - mx))

			-- Save the angle
			addonSettings.bagButtonAngle = angle
			if not module.DB.customSettings[SUI:GetActiveStyle()].elements then
				module.DB.customSettings[SUI:GetActiveStyle()].elements = {}
			end
			if not module.DB.customSettings[SUI:GetActiveStyle()].elements.addonButtons then
				module.DB.customSettings[SUI:GetActiveStyle()].elements.addonButtons = {}
			end
			module.DB.customSettings[SUI:GetActiveStyle()].elements.addonButtons.bagButtonAngle = angle

			UpdateButtonPosition()
		end)

		toggleBtn:SetScript('OnUpdate', function(self)
			if self.isDragging then
				local mx, my = Minimap:GetCenter()
				local px, py = GetCursorPosition()
				local scale = Minimap:GetEffectiveScale()
				px, py = px / scale, py / scale

				local angle = math.atan2(py - my, px - mx)
				local radius = (Minimap:GetWidth() / 2) + 5
				local x = math.cos(angle) * radius
				local y = math.sin(angle) * radius

				self:ClearAllPoints()
				self:SetPoint('CENTER', Minimap, 'CENTER', x, y)
			end
		end)

		toggleBtn:RegisterForClicks('LeftButtonUp', 'RightButtonUp')

		toggleBtn:SetScript('OnClick', function(self, button)
			if button == 'LeftButton' and not self.isDragging then
				if ButtonBag.isOpen then
					module:CloseButtonBag()
				else
					module:OpenButtonBag()
				end
			elseif button == 'RightButton' then
				-- Open SUI options to Modules > Minimap > Addon Buttons section
				SUI.Options:ToggleOptions({ 'Modules', 'Minimap', 'elements', 'addonButtons' })
			end
		end)

		toggleBtn:SetScript('OnEnter', function(self)
			GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
			GameTooltip:AddLine('Minimap Button Bag')
			GameTooltip:AddLine('Left-click to toggle addon buttons', 1, 1, 1)
			GameTooltip:AddLine('Right-click for options', 1, 1, 1)
			GameTooltip:AddLine('Drag to reposition', 0.7, 0.7, 0.7)
			GameTooltip:Show()

			-- Cancel bag hide timer if hovering toggle
			if ButtonBag.frame and ButtonBag.frame.hideTimer then
				ButtonBag.frame.hideTimer:Cancel()
				ButtonBag.frame.hideTimer = nil
			end
		end)

		toggleBtn:SetScript('OnLeave', function()
			GameTooltip:Hide()

			-- Start hide timer if bag is open
			if ButtonBag.isOpen then
				local delay = addonSettings.autoHideDelay or 2
				ButtonBag.frame.hideTimer = C_Timer.NewTimer(delay, function()
					module:CloseButtonBag()
				end)
			end
		end)

		ButtonBag.toggleButton = toggleBtn
		UpdateButtonPosition()
	end

	-- Collect and hide all LibDBIcon buttons
	module:CollectButtonBagButtons()

	-- Register callback for newly created buttons
	LDBIcon.RegisterCallback(ButtonBag, 'LibDBIcon_IconCreated', function(_, button, name)
		C_Timer.After(0.1, function()
			module:AddButtonToBag(button, name)
		end)
	end)
end

---Get all available LibDBIcon buttons for the options panel
---@return table<string, boolean> buttonList Table of button names mapped to their hidden state
function module:GetAvailableButtons()
	local buttons = {}
	local LDBIcon = LibStub and LibStub('LibDBIcon-1.0', true)
	if not LDBIcon then
		return buttons
	end

	local buttonList = LDBIcon:GetButtonList()
	for _, name in ipairs(buttonList) do
		-- Skip SpartanUI's own buttons
		if not name:find('SpartanUI') and not name:find('SUI_') then
			buttons[name] = module:IsButtonHidden(name)
		end
	end

	return buttons
end

---Check if a specific button is hidden via the hiddenButtons setting
---@param buttonName string The button name to check
---@return boolean isHidden Whether the button is hidden
function module:IsButtonHidden(buttonName)
	if not buttonName then
		return false
	end

	local addonSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.addonButtons or module.Settings.addonButtons
	if not addonSettings or not addonSettings.hiddenButtons then
		return false
	end

	return addonSettings.hiddenButtons[buttonName] == true
end

---Set the hidden state of a specific button
---@param buttonName string The button name
---@param hidden boolean Whether to hide the button
function module:SetButtonHidden(buttonName, hidden)
	if not buttonName then
		return
	end

	local addonSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.addonButtons or module.Settings.addonButtons
	if not addonSettings then
		return
	end

	-- Ensure hiddenButtons table exists in settings
	if not addonSettings.hiddenButtons then
		addonSettings.hiddenButtons = {}
	end
	addonSettings.hiddenButtons[buttonName] = hidden or nil -- nil to remove from table when not hidden

	-- Save to custom settings
	local style = SUI:GetActiveStyle()
	if not module.DB.customSettings[style] then
		module.DB.customSettings[style] = {}
	end

	if SUI.IsRetail then
		if not module.DB.customSettings[style].elements then
			module.DB.customSettings[style].elements = {}
		end
		if not module.DB.customSettings[style].elements.addonButtons then
			module.DB.customSettings[style].elements.addonButtons = {}
		end
		if not module.DB.customSettings[style].elements.addonButtons.hiddenButtons then
			module.DB.customSettings[style].elements.addonButtons.hiddenButtons = {}
		end
		module.DB.customSettings[style].elements.addonButtons.hiddenButtons[buttonName] = hidden or nil
	else
		if not module.DB.customSettings[style].addonButtons then
			module.DB.customSettings[style].addonButtons = {}
		end
		if not module.DB.customSettings[style].addonButtons.hiddenButtons then
			module.DB.customSettings[style].addonButtons.hiddenButtons = {}
		end
		module.DB.customSettings[style].addonButtons.hiddenButtons[buttonName] = hidden or nil
	end

	-- Apply the change immediately
	module:ApplyButtonVisibility(buttonName, hidden)
end

---Apply visibility change to a specific button
---@param buttonName string The button name
---@param hidden boolean Whether the button should be hidden
function module:ApplyButtonVisibility(buttonName, hidden)
	local LDBIcon = LibStub and LibStub('LibDBIcon-1.0', true)
	if not LDBIcon then
		return
	end

	local button = LDBIcon:GetMinimapButton(buttonName)
	if not button then
		return
	end

	if hidden then
		button:Hide()
		button.SUI_ManuallyHidden = true
	else
		button.SUI_ManuallyHidden = nil
		-- Only show if not in button bag mode or if bag is open
		local addonSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.addonButtons or module.Settings.addonButtons
		local style = addonSettings and addonSettings.style or 'mouseover'
		if style ~= 'bag' or ButtonBag.isOpen then
			button:Show()
		end
	end
end

---Apply all button visibility settings (called during Update)
function module:ApplyAllButtonVisibility()
	local LDBIcon = LibStub and LibStub('LibDBIcon-1.0', true)
	if not LDBIcon then
		return
	end

	local buttonList = LDBIcon:GetButtonList()
	for _, name in ipairs(buttonList) do
		if module:IsButtonHidden(name) then
			local button = LDBIcon:GetMinimapButton(name)
			if button then
				button:Hide()
				button.SUI_ManuallyHidden = true
			end
		end
	end
end

function module:IsButtonExcluded(buttonName)
	if not buttonName then
		return true
	end

	-- Always exclude SpartanUI's own buttons
	if buttonName:find('SpartanUI') or buttonName:find('SUI_') then
		return true
	end

	-- Check if manually hidden via the button visibility settings
	if module:IsButtonHidden(buttonName) then
		return true
	end

	local addonSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.addonButtons or module.Settings.addonButtons
	if not addonSettings then
		return false
	end

	local excludeList = addonSettings.excludeList or ''
	if excludeList == '' then
		return false
	end

	-- Check exclude list (case insensitive)
	for exclude in string.gmatch(excludeList, '[^,]+') do
		exclude = strtrim(exclude):lower()
		if exclude ~= '' and buttonName:lower():find(exclude) then
			return true
		end
	end

	return false
end

function module:CollectButtonBagButtons()
	local LDBIcon = LibStub and LibStub('LibDBIcon-1.0', true)
	if not LDBIcon then
		if module.logger then
			module.logger.warning('ButtonBag: LibDBIcon-1.0 not found')
		end
		return
	end

	wipe(ButtonBag.buttons)

	local buttonList = LDBIcon:GetButtonList()
	if module.logger then
		module.logger.info('ButtonBag: Found ' .. #buttonList .. ' LibDBIcon buttons')
	end

	for _, name in ipairs(buttonList) do
		local button = LDBIcon:GetMinimapButton(name)
		if button and not module:IsButtonExcluded(name) then
			module:AddButtonToBag(button, name)
			if module.logger then
				module.logger.debug('ButtonBag: Added button: ' .. name)
			end
		elseif module.logger then
			module.logger.debug('ButtonBag: Skipped button: ' .. name .. ' (excluded or nil)')
		end
	end

	if module.logger then
		local count = 0
		for _ in pairs(ButtonBag.buttons) do
			count = count + 1
		end
		module.logger.info('ButtonBag: Total buttons in bag: ' .. count)
	end
end

function module:AddButtonToBag(button, name)
	if not button or module:IsButtonExcluded(name) then
		return
	end

	-- Store original parent and strata for restoration
	if not button.SUI_OriginalParent then
		button.SUI_OriginalParent = button:GetParent()
		button.SUI_OriginalStrata = button:GetFrameStrata()
		button.SUI_OriginalLevel = button:GetFrameLevel()
	end

	-- Mark button as managed by bag (don't override Show to avoid taint)
	button.SUI_InButtonBag = true

	-- Use OnShow script hook instead of replacing Show (avoids taint)
	if not button.SUI_OnShowHooked then
		button:HookScript('OnShow', function(self)
			-- If bag is not open and button is managed, hide it again
			if self.SUI_InButtonBag and not ButtonBag.isOpen then
				self:Hide()
			end
		end)
		button.SUI_OnShowHooked = true
	end

	-- Hide the button
	button:Hide()

	-- Add to our list
	ButtonBag.buttons[name] = button
end

function module:OpenButtonBag()
	if not ButtonBag.frame then
		if module.logger then
			module.logger.warning('ButtonBag: Cannot open - frame is nil')
		end
		return
	end

	ButtonBag.isOpen = true

	-- Calculate grid layout
	local buttons = {}
	for name, button in pairs(ButtonBag.buttons) do
		table.insert(buttons, { name = name, button = button })
	end

	local numButtons = #buttons
	if module.logger then
		module.logger.info('ButtonBag: Opening with ' .. numButtons .. ' buttons')
	end

	if numButtons == 0 then
		if module.logger then
			module.logger.warning('ButtonBag: No buttons to display')
		end
		ButtonBag.isOpen = false
		return
	end

	-- Get settings for buttons per row
	local addonSettings = SUI.IsRetail and module.Settings.elements and module.Settings.elements.addonButtons or module.Settings.addonButtons
	local buttonsPerRow = addonSettings and addonSettings.buttonsPerRow or 6

	-- Determine columns based on setting
	local columns = math.min(numButtons, buttonsPerRow)
	local rows = math.ceil(numButtons / columns)

	local buttonSize = 28
	local padding = 4
	local frameWidth = (buttonSize + padding) * columns + padding
	local frameHeight = (buttonSize + padding) * rows + padding

	ButtonBag.frame:SetSize(frameWidth, frameHeight)

	-- Position the bag frame relative to the toggle button
	ButtonBag.frame:ClearAllPoints()
	ButtonBag.frame:SetPoint('TOPRIGHT', ButtonBag.toggleButton, 'BOTTOMLEFT', 0, -5)

	-- Position buttons in grid
	for i, data in ipairs(buttons) do
		local button = data.button
		local col = (i - 1) % columns
		local row = math.floor((i - 1) / columns)

		button:SetParent(ButtonBag.frame)
		button:ClearAllPoints()
		button:SetPoint('TOPLEFT', ButtonBag.frame, 'TOPLEFT', padding + col * (buttonSize + padding), -padding - row * (buttonSize + padding))
		button:SetSize(buttonSize, buttonSize)

		-- Ensure button is above the bag backdrop
		button:SetFrameStrata('MEDIUM')
		button:SetFrameLevel(ButtonBag.frame:GetFrameLevel() + 5)

		-- Stop any fade animations and ensure button is visible
		if button.fadeInAnim then
			button.fadeInAnim:Stop()
		end
		if button.fadeOutAnim then
			button.fadeOutAnim:Stop()
		end
		button:SetAlpha(1)

		-- Show the button (OnShow hook will allow it since ButtonBag.isOpen is true)
		button:Show()
	end

	ButtonBag.frame:Show()
end

function module:CloseButtonBag()
	if not ButtonBag.frame then
		return
	end

	ButtonBag.isOpen = false

	-- Hide all buttons and return to original parent/strata
	for name, button in pairs(ButtonBag.buttons) do
		button:Hide()
		if button.SUI_OriginalParent then
			button:SetParent(button.SUI_OriginalParent)
		end
		if button.SUI_OriginalStrata then
			button:SetFrameStrata(button.SUI_OriginalStrata)
		end
		if button.SUI_OriginalLevel then
			button:SetFrameLevel(button.SUI_OriginalLevel)
		end
	end

	ButtonBag.frame:Hide()

	if ButtonBag.frame.hideTimer then
		ButtonBag.frame.hideTimer:Cancel()
		ButtonBag.frame.hideTimer = nil
	end
end

function module:DestroyButtonBag()
	-- Restore all buttons to original state
	for name, button in pairs(ButtonBag.buttons) do
		-- Clear bag management flag so OnShow hook allows showing
		button.SUI_InButtonBag = nil

		if button.SUI_OriginalParent then
			button:SetParent(button.SUI_OriginalParent)
			button.SUI_OriginalParent = nil
		end
		if button.SUI_OriginalStrata then
			button:SetFrameStrata(button.SUI_OriginalStrata)
			button.SUI_OriginalStrata = nil
		end
		if button.SUI_OriginalLevel then
			button:SetFrameLevel(button.SUI_OriginalLevel)
			button.SUI_OriginalLevel = nil
		end
		button:Show()
	end

	wipe(ButtonBag.buttons)
	ButtonBag.isOpen = false

	if ButtonBag.frame then
		ButtonBag.frame:Hide()
	end
	if ButtonBag.toggleButton then
		ButtonBag.toggleButton:Hide()
	end
end

function module:RefreshButtonBag()
	if ButtonBag.isOpen then
		module:CloseButtonBag()
		module:OpenButtonBag()
	end
end

function module:CreateMover()
	-- Ensure SUIMinimap has a size before creating the mover
	if SUIMinimap:GetWidth() == 0 or SUIMinimap:GetHeight() == 0 then
		SUI:Error('Minimap', 'SUIMinimap has no size. Mover creation aborted.')
		return
	end

	MoveIt:CreateMover(SUIMinimap, 'Minimap')
end

function module:SwitchMinimapPosition(inVehicle)
	if inVehicle then
		SUIMinimap:ClearAllPoints()
		SUIMinimap:SetPoint('TOPLEFT', SUI_CustomMover_VehicleMinimapPosition)
	else
		SUIMinimap:ClearAllPoints()
		SUIMinimap:SetPoint('TOPLEFT', SUI_Mover_Minimap)
	end
end

function module:SetupHooks()
	Minimap:HookScript('OnShow', function()
		SUIMinimap:Show()
	end)
	Minimap:HookScript('OnHide', function()
		SUIMinimap:Hide()
	end)

	-- Note: SUIMinimap OnEnter/OnLeave hooks for button fading are now handled in SetupAddonButtons()
	-- The IsMouseOver() function is currently unused but kept for potential future use
end

function module:RegisterEvents()
	MinimapUpdater:SetScript('OnEvent', function(self, event)
		if event == 'PLAYER_REGEN_ENABLED' then
			-- Combat ended - reapply layout modifications if they were skipped
			if module.layoutModificationPending then
				if module.logger then
					module.logger.debug('Combat ended - reapplying minimap layout modifications')
				end
				module:ModifyMinimapLayout()
			end
		end

		if not InCombatLockdown() then
			module:ScheduleTimer(module.Update, 2, module, true)
		end

		-- Update zone text on zone changes for Classic
		if not SUI.IsRetail and (event == 'ZONE_CHANGED' or event == 'ZONE_CHANGED_INDOORS' or event == 'ZONE_CHANGED_NEW_AREA') then
			module:UpdateClassicZoneText()
		end
	end)
	MinimapUpdater:RegisterEvent('ADDON_LOADED')
	MinimapUpdater:RegisterEvent('ZONE_CHANGED')
	MinimapUpdater:RegisterEvent('ZONE_CHANGED_INDOORS')
	MinimapUpdater:RegisterEvent('ZONE_CHANGED_NEW_AREA')
	MinimapUpdater:RegisterEvent('MINIMAP_UPDATE_TRACKING')
	MinimapUpdater:RegisterEvent('PLAYER_REGEN_ENABLED')

	module:ScheduleRepeatingTimer(module.Update, 30, module, true)
end

function module:Update(fullUpdate)
	if SUI:IsModuleDisabled('Minimap') then
		return
	end

	module:UpdateSettings()

	-- Reapply layout modifications on full update (needed for skin changes)
	if fullUpdate then
		module:ModifyMinimapLayout()
	end

	-- Apply settings to elements
	module:SetupBackground()
	module:SetupZoneText()
	module:SetupCoords()
	module:SetupClock()
	module:SetupMailIcon()
	module:SetupTracking()
	module:SetupInstanceDifficulty()
	module:SetupQueueStatus()
	module:UpdateAddonButtons()
	module:UpdateMinimapShape()
	module:UpdateMinimapSize()
	module:SetupZoomButtons()

	-- Classic-specific updates
	if not SUI.IsRetail then
		module:UpdateClassicZoneText()
	end

	-- Retail-only elements
	if SUI.IsRetail then
		module:SetupBorderTop()
		module:SetupCalendarButton()
		module:SetupExpansionButton()

		-- Setup vehicle UI monitoring if conditions are met
		if module.Settings.UnderVehicleUI and module.Settings.useVehicleMover ~= false and SUI:GetArtworkSetting('VehicleUI') and (not MoveIt:IsMoved('Minimap')) then
			-- Initialize vehicle UI monitoring if not already done
			if not VehicleUIWatcher.monitoringSetup then
				SetupVehicleUIMonitoring()
				VehicleUIWatcher.monitoringSetup = true
			end

			-- Check current state and apply immediately if needed
			if not VehicleUIWatcher:IsVisible() then
				-- VehicleUIWatcher is hidden, meaning vehicle UI is active
				module:SwitchMinimapPosition(true)
			else
				-- VehicleUIWatcher is visible, meaning vehicle UI is not active
				module:SwitchMinimapPosition(false)
			end
		end
	end

	if fullUpdate then
		module:UpdatePosition()
		module:UpdateScale()
	end
end

function module:SetActiveStyle(style)
	-- Always update when style changes, even if the style isn't registered in the minimap Registry
	-- This ensures shape, position, and other settings are refreshed properly
	module.styleOverride = style

	module:UpdateSettings()
	module:Update(true)
end

function module:UpdatePosition()
	if module.Settings.position and not MoveIt:IsMoved('Minimap') then
		local point, anchor, secondaryPoint, x, y = strsplit(',', module.Settings.position)
		if SUIMinimap.position then
			SUIMinimap:position(point, anchor, secondaryPoint, x, y, false, true)
		else
			SUIMinimap:ClearAllPoints()
			SUIMinimap:SetPoint(point, anchor, secondaryPoint, x, y)
		end
	end

	-- Update MinimapCluster position relative to SUIMinimap
	-- MinimapContainer only exists in Retail, not Classic
	if MinimapCluster.MinimapContainer then
		MinimapCluster.MinimapContainer:ClearAllPoints()
		MinimapCluster.MinimapContainer:SetPoint('TOPLEFT', SUIMinimap, 'TOPLEFT', -30, 32)
	end
	SUIMinimap.Registry = Registry
end

function module:UpdateScale()
	if module.Settings.scaleWithArt and SUI:IsAddonDisabled('SexyMap') then
		local scale = max(SUI.DB.scale, 0.01)
		if SUIMinimap.scale then
			SUIMinimap:scale(scale)
			MinimapCluster:SetScale(scale)
		else
			SUIMinimap:SetScale(scale)
			MinimapCluster:SetScale(scale)
		end
	end
end

-- Create a vehicle UI mover frame
local VehicleMover

-- Initialize the vehicle mover
function module:InitializeVehicleMover()
	if not SUI.IsRetail then
		return
	end -- Vehicle mover is Retail-only

	-- Create the vehicle mover with our new reusable function
	local borderHeight = 0
	if MinimapCluster.BorderTop then
		borderHeight = MinimapCluster.BorderTop:GetHeight()
	end

	VehicleMover = SUI.MoveIt:CreateCustomMover('Vehicle Minimap Position', module.Settings.vehiclePosition, {
		width = Minimap:GetWidth(),
		height = (Minimap:GetHeight() + borderHeight + 15),
		savePosition = function(position)
			module.Settings.vehiclePosition = position

			-- Save to user settings
			local currentStyle = SUI:GetActiveStyle()
			if currentStyle and module.DB and module.DB.customSettings then
				if not module.DB.customSettings[currentStyle] then
					module.DB.customSettings[currentStyle] = {}
				end
				module.DB.customSettings[currentStyle].vehiclePosition = position
			end
		end,
	})

	VehicleMover.target = SUIMinimap

	-- Register for vehicle events
	module:RegisterEvent('UNIT_ENTERED_VEHICLE', 'OnVehicleChange')
	module:RegisterEvent('UNIT_EXITED_VEHICLE', 'OnVehicleChange')
	module:RegisterEvent('PLAYER_ENTERING_WORLD', 'CheckVehicleStatus')
	-- OnZone change
	module:RegisterEvent('ZONE_CHANGED_NEW_AREA', function()
		module:ScheduleTimer(module.CheckOverrideActionBar, 0.2)
	end)

	-- Check if OverrideActionBar exists and is visible
	module:RegisterEvent('UPDATE_OVERRIDE_ACTIONBAR', 'CheckOverrideActionBar')
end

-- Show the vehicle minimap mover
function module:VehicleUIMoverShow()
	if InCombatLockdown() then
		return
	end

	VehicleMover:Show()

	-- Show a notification to the user
	SUI:Print(L["You can now position the minimap for when you're in a vehicle. Right-click to reset."])
end

-- Hide the vehicle minimap mover
function module:VehicleUIMoverHide()
	VehicleMover:Hide()
end

-- Reset vehicle position to default
function module:ResetVehiclePosition()
	local point, anchor, secondaryPoint, x, y = strsplit(',', module.BaseOpt.vehiclePosition)
	VehicleMover:ClearAllPoints()
	VehicleMover:SetPoint(point, _G[anchor], secondaryPoint, x, y)

	module.Settings.vehiclePosition = module.BaseOpt.vehiclePosition
	local currentStyle = SUI:GetActiveStyle()
	if currentStyle and module.DB and module.DB.customSettings and module.DB.customSettings[currentStyle] then
		module.DB.customSettings[currentStyle].vehiclePosition = nil
	end

	SUI:Print(L['Vehicle minimap position reset to default'])
end

-- Handle vehicle state changes
function module:OnVehicleChange(event, unit)
	if unit ~= 'player' then
		return
	end

	if event == 'UNIT_ENTERED_VEHICLE' then
		-- if not firstVehicleDetected and module.Settings.UnderVehicleUI then
		-- 	firstVehicleDetected = true

		-- 	-- Ask the user if they want to set the vehicle position
		-- 	StaticPopupDialogs['SUI_MINIMAP_VEHICLE_POSITION'] = {
		-- 		text = L['Would you like to set a custom position for your minimap when in a vehicle?'],
		-- 		button1 = L['Yes'],
		-- 		button2 = L['No'],
		-- 		OnAccept = function()
		-- 			module:VehicleUIMoverShow()
		-- 		end,
		-- 		timeout = 0,
		-- 		whileDead = true,
		-- 		hideOnEscape = true,
		-- 		preferredIndex = 3,
		-- 	}

		-- 	StaticPopup_Show('SUI_MINIMAP_VEHICLE_POSITION')
		-- end

		-- Apply the vehicle position
		if module.Settings.UnderVehicleUI and module.Settings.useVehicleMover ~= false then
			module:SwitchMinimapPosition(true)
		end
	elseif event == 'UNIT_EXITED_VEHICLE' then
		-- Restore normal position
		if module.Settings.UnderVehicleUI and module.Settings.useVehicleMover ~= false then
			module:SwitchMinimapPosition(false)
		end
	end
end

-- Check vehicle status on login or reload
function module:CheckVehicleStatus()
	if not (module.Settings.UnderVehicleUI and module.Settings.useVehicleMover ~= false) then
		return
	end

	if IsVehicleUIActive() then
		module:SwitchMinimapPosition(true)
	else
		module:SwitchMinimapPosition(false)
	end
end

-- Check for OverrideActionBar visibility changes
function module:CheckOverrideActionBar()
	C_Timer.After(0.5, function()
		if IsVehicleUIActive() then
			if not module.Settings.firstVehicleDetected and module.Settings.UnderVehicleUI and module.Settings.useVehicleMover ~= false then
				module.Settings.firstVehicleDetected = true
				local currentStyle = SUI:GetActiveStyle()
				if currentStyle and module.DB and module.DB.customSettings then
					if not module.DB.customSettings[currentStyle] then
						module.DB.customSettings[currentStyle] = {}
					end
					module.DB.customSettings[currentStyle].firstVehicleDetected = true
				end

				StaticPopupDialogs['SUI_MINIMAP_VEHICLE_POSITION'] = {
					text = L['Would you like to set a custom position for your minimap when in a vehicle?'],
					button1 = L['Yes'],
					button2 = L['No'],
					OnAccept = function()
						module:VehicleUIMoverShow()
					end,
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
				}

				StaticPopup_Show('SUI_MINIMAP_VEHICLE_POSITION')
			end

			if module.Settings.UnderVehicleUI and module.Settings.useVehicleMover ~= false then
				module:SwitchMinimapPosition(true)
			end
		else
			if module.Settings.UnderVehicleUI and module.Settings.useVehicleMover ~= false then
				module:SwitchMinimapPosition(false)
			end
		end
	end)
end

function module:OnInitialize()
	-- Register logger
	if SUI.logger then
		module.logger = SUI.logger:RegisterCategory('Minimap')
	end

	---@class SUI.Minimap.Database
	local defaults = {
		enabled = true,
		style = 'Default',
		customSettings = {
			['**'] = {
				['**'] = {
					['**'] = {},
				},
			},
		},
		AutoDetectAllowUse = true,
		ManualAllowUse = false,
	}

	module.Database = SUI.SpartanUIDB:RegisterNamespace('Minimap', { profile = defaults })
	module.DB = module.Database.profile ---@type SUI.Minimap.Database

	-- Register profile change callbacks with refresh method
	-- Register for sequential profile refresh with UpdateSettings
	SUI.DBM:RegisterSequentialProfileRefresh(module, 'UpdateSettings')

	-- Initialize the settings
	module:UpdateSettings()

	-- Check for other addons modifying the minimap
	module:DetectMinimapAddons()

	local currentStyle = SUI:GetActiveStyle()
	if currentStyle and module.DB and module.DB.customSettings then
		if not module.DB.customSettings[currentStyle] then
			module.DB.customSettings[currentStyle] = {}
		end
		if C_CVar.GetCVar('rotateMinimap') == '1' and not module.DB.customSettings[currentStyle].rotate then
			module.DB.customSettings[currentStyle].rotate = true
		end
	end
end

function module:DetectMinimapAddons()
	local conflictingAddons = {
		['SexyMap'] = 'SexyMap',
		['Carbonite'] = NXTITLELOW,
		-- Add other known conflicting addons here
	}

	for addonName, addonTitle in pairs(conflictingAddons) do
		if SUI:IsAddonEnabled(addonName) then
			if addonName == 'Carbonite' then
				SUI:Print(addonTitle .. ' is loaded ...Checking settings ...')
				if Nx and Nx.db and Nx.db.profile and Nx.db.profile.MiniMap and Nx.db.profile.MiniMap.Own == true then
					SUI:Print(addonTitle .. ' is controlling the Minimap')
					SUI:Print('SpartanUI Will not modify or move the minimap unless Carbonite is a separate minimap')
					module.DB.AutoDetectAllowUse = false
				end
			else
				module.DB.AutoDetectAllowUse = false
				SUI:Print(addonTitle .. ' detected. SpartanUI will not modify the minimap.')
			end
		end
	end

	if not module.DB.AutoDetectAllowUse and not module.DB.ManualAllowUse then
		StaticPopup_Show('MiniMapNotice')
	end
end

function module:OnEnable()
	if SUI:IsModuleDisabled('Minimap') then
		return
	end

	-- Set up the SUIMinimap frame
	SUIMinimap:SetFrameStrata('BACKGROUND')
	SUIMinimap:SetFrameLevel(99)
	SUIMinimap:SetPoint('BOTTOM', UIParent, 'BOTTOM', 0, 0)
	-- Enable mouse events so OnEnter/OnLeave work for button fading
	SUIMinimap:EnableMouse(true)
	SUIMinimap:SetMouseClickEnabled(false) -- Don't intercept clicks, let them pass through to Minimap

	module:UpdateSettings()
	module:SetupElements()
	module:CreateMover()
	module:SetupHooks()
	module:RegisterEvents()

	-- Initialize Buttons & Style settings
	module:Update(true)

	-- Retail-only features
	if SUI.IsRetail then
		module:InitializeVehicleMover()

		SUI:AddChatCommand('vehicleminimap', function()
			if VehicleMover:IsShown() then
				module:VehicleUIMoverHide()
			else
				module:VehicleUIMoverShow()
			end
		end, L['Toggle vehicle minimap mover'])
	end

	-- Setup Options
	module:BuildOptions()
end

StaticPopupDialogs['MiniMapNotice'] = {
	text = '|cff33ff99SpartanUI Notice|n|r|n Another addon has been found modifying the minimap. Do you give permission for SpartanUI to move and possibly modify the minimap as your theme dictates? |n|n You can change this option in the settings should you change your mind.',
	button1 = 'Yes',
	button2 = 'No',
	OnAccept = function()
		module.DB.ManualAllowUse = true
		module:Enable()
	end,
	OnCancel = function()
		module.DB.ManualAllowUse = false
		SUI:DisableModule(module)
		SUI:SafeReloadUI()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = false,
}

SUI.Minimap = module
