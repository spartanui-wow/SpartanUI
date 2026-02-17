local SUI, L = SUI, SUI.L
---@class SUI.Theme.Tribal : SUI.Theme.StyleBase
local module = SUI:NewModule('Style.Tribal')
local Artwork_Core = SUI:GetModule('Artwork') ---@type SUI.Module.Artwork
local artFrame = CreateFrame('Frame', 'SUI_Art_Tribal', SpartanUI)
module.Settings = {}
----------------------------------------------------------------------------------------------------
function module:OnInitialize()
	SUI.ThemeRegistry:Register({
		name = 'Tribal',
		displayName = 'Tribal',
		apiVersion = 1,
		description = 'Organic tribal-themed interface with earthy tones',
		setup = {
			image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Frames_Tribal',
		},
		applicableTo = { player = true, target = true },
	}, function()
		return {
			frames = {
				player = {
					elements = {
						SpartanArt = {
							top = {
								enabled = true,
								graphic = 'Tribal',
							},
							bg = {
								enabled = true,
								graphic = 'Tribal',
							},
							bottom = {
								enabled = true,
								graphic = 'Tribal',
							},
						},
						Name = {
							enabled = true,
							SetJustifyH = 'LEFT',
							position = {
								anchor = 'BOTTOM',
								x = 0,
								y = -16,
							},
						},
					},
				},
				target = {
					elements = {
						SpartanArt = {
							top = {
								enabled = true,
								graphic = 'Tribal',
							},
							bg = {
								enabled = true,
								graphic = 'Tribal',
							},
							bottom = {
								enabled = true,
								graphic = 'Tribal',
							},
						},
						Name = {
							enabled = true,
							SetJustifyH = 'LEFT',
							position = {
								anchor = 'BOTTOM',
								x = 0,
								y = -16,
							},
						},
					},
				},
			},
			slidingTrays = {
				left = {
					enabled = true,
					collapsed = false,
				},
				right = {
					enabled = true,
					collapsed = false,
				},
			},
			unitframes = {
				artwork = {
					top = {
						path = 'Interface\\AddOns\\SpartanUI\\Themes\\Tribal\\Images\\UnitFrames',
						TexCoord = { 0.25390625, 0.580078125, 0.583984375, 0.712890625 },
						heightScale = 0.38,
						widthScale = 0.6,
						yScale = -0.072,
					},
					bg = {
						path = 'Interface\\AddOns\\SpartanUI\\Themes\\Tribal\\Images\\UnitFrames',
						TexCoord = { 0.126953125, 0.734375, 0.171875, 0.291015625 },
					},
					bottom = {
						path = 'Interface\\AddOns\\SpartanUI\\Themes\\Tribal\\Images\\UnitFrames',
						TexCoord = { 0.869140625, 1, 0.3203125, 0.359375 },
						heightScale = 0.15,
						widthScale = 0.25,
					},
				},
				positions = {
					['player'] = 'BOTTOMRIGHT,SUI_BottomAnchor,BOTTOM,-45,250',
				},
				displayName = 'Tribal',
				setup = {
					image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Frames_Tribal',
				},
			},
			barPositions = {
				['BT4BarExtraActionBar'] = 'BOTTOM,SUI_BottomAnchor,TOP,0,70',
				['BT4BarZoneAbilityBar'] = 'BOTTOM,SUI_BottomAnchor,TOP,0,70',
				--
				['BT4BarStanceBar'] = 'TOP,SpartanUI,TOP,-309,0',
				['BT4BarPetBar'] = 'TOP,SpartanUI,TOP,-558,0',
				['MultiCastActionBarFrame'] = 'TOP,SpartanUI,TOP,-558,0',
				--
				['BT4BarMicroMenu'] = 'TOP,SpartanUI,TOP,285,0',
				['BT4BarBagBar'] = 'TOP,SpartanUI,TOP,595,0',
			},
			minimap = SUI.IsRetail and {
				size = { 180, 180 },
				position = 'CENTER,SUI_Art_Tribal_Left,RIGHT,-2,-4',
				elements = {
					background = {
						texture = 'Interface\\AddOns\\SpartanUI\\Themes\\Tribal\\Images\\minimap',
						size = { 220, 220 },
						position = 'CENTER,SUI_Art_Tribal_Left,RIGHT,-2,-4',
					},
				},
			} or {
				size = { 140, 140 },
				position = 'CENTER,SUI_Art_Tribal_Left,RIGHT,-2,-4',
				background = {
					texture = 'Interface\\AddOns\\SpartanUI\\Themes\\Tribal\\Images\\minimap',
					size = { 180, 180 },
					position = 'CENTER,SUI_Art_Tribal_Left,RIGHT,-2,-4',
				},
			},
			statusBars = {
				Left = {
					bgTexture = 'Interface\\AddOns\\SpartanUI\\Themes\\Tribal\\Images\\StatusBar',
					alpha = 0.9,
					size = { 370, 20 },
					texCords = { 0.0546875, 0.9140625, 0.5555555555555556, 0 },
					MaxWidth = 48,
				},
				Right = {
					bgTexture = 'Interface\\AddOns\\SpartanUI\\Themes\\Tribal\\Images\\StatusBar',
					alpha = 0.9,
					size = { 370, 20 },
					texCords = { 0.0546875, 0.9140625, 0.5555555555555556, 0 },
					MaxWidth = 48,
				},
			},
		}
	end)

	module:CreateArtwork()
end

function module:OnEnable()
	if SUI:GetActiveStyle() ~= 'Tribal' then
		module:Disable()
	else
		--Setup Sliding Trays
		module:SlidingTrays()

		hooksecurefunc('UIParent_ManageFramePositions', function()
			if TutorialFrameAlertButton then
				TutorialFrameAlertButton:SetParent(Minimap)
				TutorialFrameAlertButton:ClearAllPoints()
				TutorialFrameAlertButton:SetPoint('CENTER', Minimap, 'TOP', -2, 30)
			end
			if CastingBarFrame then
				CastingBarFrame:ClearAllPoints()
				CastingBarFrame:SetPoint('BOTTOM', SUI_Art_Tribal, 'TOP', 0, 90)
			end
		end)

		module:SetupVehicleUI()

		if SUI:IsModuleEnabled('Minimap') then
			module:MiniMap()
		end
	end
end

function module:OnDisable()
	SUI_Art_Tribal:Hide()
	UnregisterStateDriver(SUI_Art_Tribal, 'visibility')
end

--	Module Calls
function module:TooltipLoc(tooltip, parent)
	if parent == 'UIParent' then
		tooltip:ClearAllPoints()
		tooltip:SetPoint('BOTTOMRIGHT', 'SUI_Art_Tribal', 'TOPRIGHT', 0, 10)
	end
end

function module:SetupVehicleUI()
	if SUI:GetArtworkSetting('VehicleUI') then
		RegisterStateDriver(SUI_Art_Tribal, 'visibility', '[overridebar][vehicleui] hide; show')
	end
end

function module:RemoveVehicleUI()
	if SUI:GetArtworkSetting('VehicleUI') then
		UnregisterStateDriver(SUI_Art_Tribal, 'visibility')
	end
end

function module:CreateArtwork()
	if Tribal_ActionBarPlate then
		return
	end

	local BarBGSettings = {
		name = 'Tribal',
		TexturePath = 'Interface\\AddOns\\SpartanUI\\Themes\\Tribal\\Images\\Barbg',
		TexCoord = { 0.07421875, 0.92578125, 0.359375, 0.6796875 },
		color = { 0, 0, 0, 0.5 }, -- Tribal theme uses black backgrounds
	}

	local plate = CreateFrame('Frame', 'Tribal_ActionBarPlate', SUI_Art_Tribal)
	plate:SetSize(1002, 139)
	plate:SetFrameStrata('BACKGROUND')
	plate:SetFrameLevel(1)
	plate:SetAllPoints(SUI_BottomAnchor)

	for i = 1, 4 do
		plate['BG' .. i] = Artwork_Core:CreateBarBG(BarBGSettings, i, Tribal_ActionBarPlate)
	end
	plate.BG1:SetPoint('BOTTOMRIGHT', plate, 'BOTTOM', -110, 70)
	plate.BG2:SetPoint('BOTTOMRIGHT', plate, 'BOTTOM', -110, 25)
	plate.BG3:SetPoint('BOTTOMLEFT', plate, 'BOTTOM', 110, 70)
	plate.BG4:SetPoint('BOTTOMLEFT', plate, 'BOTTOM', 110, 25)

	--Setup the Bottom Artwork
	artFrame:SetFrameStrata('BACKGROUND')
	artFrame:SetFrameLevel(1)
	artFrame:SetSize(2, 2)
	artFrame:SetPoint('BOTTOM', SUI_BottomAnchor)

	artFrame.Left = artFrame:CreateTexture('SUI_Art_Tribal_Left', 'BORDER')
	artFrame.Left:SetTexture('Interface\\AddOns\\SpartanUI\\Themes\\Tribal\\Images\\Art-Left')
	artFrame.Left:SetPoint('BOTTOMRIGHT', artFrame, 'BOTTOM', 0, 0)
	artFrame.Left:SetScale(0.75)
	artFrame.Left:SetAlpha(0.85)

	artFrame.Right = artFrame:CreateTexture('SUI_Art_Tribal_Right', 'BORDER')
	artFrame.Right:SetTexture('Interface\\AddOns\\SpartanUI\\Themes\\Tribal\\Images\\Art-Right')
	artFrame.Right:SetPoint('BOTTOMLEFT', artFrame, 'BOTTOM')
	artFrame.Right:SetScale(0.75)
	artFrame.Right:SetAlpha(0.85)
end

-- Artwork Stuff
function module:SlidingTrays()
	-- Uses all default options from DefaultTraySettings
	Artwork_Core:SlidingTrays()

	-- Register frames that this skin places in trays
	Artwork_Core:RegisterSkinTrayFrames('Tribal', {
		left = 'BT4BarPetBar,BT4BarStanceBar,MultiCastActionBarFrame',
		right = 'BT4BarMicroMenu,BT4BarBagBar',
	})

	if BT4BarBagBar and BT4BarPetBar.position then
		BT4BarPetBar:position('TOPLEFT', 'SlidingTray_left', 'TOPLEFT', 50, -2)
		BT4BarStanceBar:position('TOPRIGHT', 'SlidingTray_left', 'TOPRIGHT', -50, -2)
		BT4BarMicroMenu:position('TOPLEFT', 'SlidingTray_right', 'TOPLEFT', 50, -2)
		BT4BarBagBar:position('TOPRIGHT', 'SlidingTray_right', 'TOPRIGHT', -100, -2)
	end
end

-- Minimap
function module:MiniMap()
	if Minimap.ZoneText ~= nil then
		Minimap.ZoneText:ClearAllPoints()
		Minimap.ZoneText:SetPoint('TOPLEFT', Minimap, 'BOTTOMLEFT', 0, -5)
		Minimap.ZoneText:SetPoint('TOPRIGHT', Minimap, 'BOTTOMRIGHT', 0, -5)
		Minimap.ZoneText:Hide()
		MinimapZoneText:Show()
	end
end
