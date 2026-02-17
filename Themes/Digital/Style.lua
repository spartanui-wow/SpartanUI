local SUI, L = SUI, SUI.L
---@class SUI.Theme.Digital : SUI.Theme.StyleBase
local module = SUI:NewModule('Style.Digital')
local artFrame = CreateFrame('Frame', 'SUI_Art_Digital', SpartanUI)
module.Settings = {}

----------------------------------------------------------------------------------------------------
function module:OnInitialize()
	SUI.ThemeRegistry:Register(
		-- Metadata (always in memory)
		{
			name = 'Digital',
			displayName = 'Digital',
			apiVersion = 1,
			description = 'Clean digital interface with transparent unit frame backgrounds',
			setup = {
				image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Frames_Digital',
			},
			applicableTo = { player = true, target = true },
		},
		-- Data callback (lazy-loaded on first access)
		function()
			return {
				frames = {
					player = {
						elements = {
							SpartanArt = {
								bg = {
									enabled = true,
									graphic = 'Digital',
								},
							},
						},
					},
					target = {
						elements = {
							SpartanArt = {
								bg = {
									enabled = true,
									graphic = 'Digital',
								},
							},
						},
					},
				},
				artwork = {},
				unitframes = {
					artwork = {
						bg = {
							path = 'Interface\\AddOns\\SpartanUI\\Themes\\Digital\\Images\\BarBG',
							TexCoord = { 0.0234375, 0.9765625, 0.265625, 0.7734375 },
							PVPAlpha = 0.4,
						},
					},
					displayName = 'Digital',
					setup = {
						image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Frames_Digital',
					},
				},
				barPositions = {
					['BT4BarStanceBar'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,-285,175',
					['BT4BarPetBar'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,-607,177',
					['MultiCastActionBarFrame'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,-661,191',
					['BT4BarMicroMenu'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,310,151',
					['BT4BarBagBar'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,661,174',
				},
				minimap = SUI.IsRetail and {
					size = { 180, 180 },
					position = 'CENTER,SUI_Art_Digital,CENTER,0,54',
					elements = {
						background = {
							texture = 'Interface\\AddOns\\SpartanUI\\Themes\\Digital\\Images\\Minimap',
							position = { 'TOPLEFT,Minimap,TOPLEFT,-38,41', 'BOTTOMRIGHT,Minimap,BOTTOMRIGHT,47,-44' },
						},
					},
				} or {
					size = { 140, 140 },
					position = 'CENTER,SUI_Art_Digital,CENTER,0,54',
					background = {
						texture = 'Interface\\AddOns\\SpartanUI\\Themes\\Digital\\Images\\Minimap',
						position = { 'TOPLEFT,Minimap,TOPLEFT,-38,41', 'BOTTOMRIGHT,Minimap,BOTTOMRIGHT,47,-44' },
					},
				},
				statusBars = {
					Left = {
						bgTexture = 'Interface\\AddOns\\SpartanUI\\Themes\\Tribal\\Images\\StatusBar',
						size = { 370, 20 },
						tooltip = {
							texture = 'Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\Fel-Box',
							textureCoords = { 0.03125, 0.96875, 0.2578125, 0.7578125 },
						},
						texCords = { 0.150390625, 1, 0, 1 },
						MaxWidth = 32,
					},
					Right = {
						bgTexture = 'Interface\\AddOns\\SpartanUI\\Themes\\Tribal\\Images\\StatusBar',
						size = { 370, 20 },
						tooltip = {
							texture = 'Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\Fel-Box',
							textureCoords = { 0.03125, 0.96875, 0.2578125, 0.7578125 },
						},
						texCords = { 0.150390625, 1, 0, 1 },
						MaxWidth = 32,
					},
				},
			}
		end
	)

	module:CreateArtwork()
end

function module:OnEnable()
	if SUI:GetActiveStyle() ~= 'Digital' then
		module:Disable()
	else
		module:EnableArtwork()
	end
end

function module:OnDisable()
	UnregisterStateDriver(SUI_Art_Digital, 'visibility')
	SUI_Art_Digital:Hide()
end

function module:SetupVehicleUI()
	if SUI:GetArtworkSetting('VehicleUI') then
		RegisterStateDriver(SUI_Art_Digital, 'visibility', '[overridebar][vehicleui] hide; show')
	end
end

function module:RemoveVehicleUI()
	if SUI:GetArtworkSetting('VehicleUI') then
		UnregisterStateDriver(SUI_Art_Digital, 'visibility')
	end
end

function module:CreateArtwork()
	local plate = CreateFrame('Frame', 'Digital_ActionBarPlate', SpartanUI, 'Digital_ActionBarsTemplate')
	plate:SetFrameStrata('BACKGROUND')
	plate:SetFrameLevel(1)
	plate:ClearAllPoints()
	plate:SetAllPoints(SUI_BottomAnchor)

	--Setup the Bottom Artwork
	artFrame:SetFrameStrata('BACKGROUND')
	artFrame:SetFrameLevel(1)
	artFrame:SetSize(2, 2)
	artFrame:SetPoint('BOTTOM', SUI_BottomAnchor)

	artFrame.Left = artFrame:CreateTexture('SUI_Art_War_Left', 'BORDER')
	artFrame.Left:SetPoint('BOTTOMRIGHT', artFrame, 'BOTTOM', 0, 0)
	artFrame.Left:SetTexture('Interface\\AddOns\\SpartanUI\\Themes\\Digital\\Images\\Base_Bar_Left')

	artFrame.Right = artFrame:CreateTexture('SUI_Art_War_Right', 'BORDER')
	artFrame.Right:SetPoint('BOTTOMLEFT', artFrame, 'BOTTOM')
	artFrame.Right:SetTexture('Interface\\AddOns\\SpartanUI\\Themes\\Digital\\Images\\Base_Bar_Right')
end

function module:EnableArtwork()
	module:SetupVehicleUI()
end
