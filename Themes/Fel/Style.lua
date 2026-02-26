local SUI, L = SUI, SUI.L
local print = SUI.print
---@class SUI.Theme.Fel : SUI.Theme.StyleBase
local module = SUI:NewModule('Style.Fel')
---@type SUI.Module
local artFrame = CreateFrame('Frame', 'SUI_Art_Fel', SpartanUI)
module.Settings = {}
----------------------------------------------------------------------------------------------------

local function Options()
	-- Replace the plain execute buttons in General > Art Style with variant pickers.
	-- OverallStyle set switches to Fel first (variant doesn't change the style name).
	SUI.opt.args.General.args.style.args.OverallStyle.args.Fel = {
		name = 'Fel',
		type = 'select',
		dialogControl = 'ThemeVariantCard',
		values = { engulfed = 'Engulfed', calmed = 'Calmed' },
		sorting = { 'engulfed', 'calmed' },
		get = function()
			return SUI.ThemeRegistry:GetActiveVariant('Fel')
		end,
		set = function(_, val)
			SUI:SetActiveStyle('Fel')
			if SUI.UF then
				SUI.UF:SetActiveStyle('Fel')
			end
			SUI.ThemeRegistry:ApplyVariant('Fel', val)
		end,
	}
	SUI.opt.args.General.args.style.args.Artwork.args.Fel = {
		name = 'Fel',
		type = 'select',
		dialogControl = 'ThemeVariantCard',
		values = { engulfed = 'Engulfed', calmed = 'Calmed' },
		sorting = { 'engulfed', 'calmed' },
		get = function()
			return SUI.ThemeRegistry:GetActiveVariant('Fel')
		end,
		set = function(_, val)
			SUI.ThemeRegistry:ApplyVariant('Fel', val)
		end,
	}

	SUI.opt.args.Artwork.args.Fel = {
		name = L['Fel style'],
		type = 'group',
		order = 10,
		args = {
			Variant = {
				name = 'Fel',
				type = 'select',
				dialogControl = 'ThemeVariantCard',
				order = 0.1,
				values = { engulfed = 'Engulfed', calmed = 'Calmed' },
				sorting = { 'engulfed', 'calmed' },
				get = function()
					return SUI.ThemeRegistry:GetActiveVariant('Fel')
				end,
				set = function(_, val)
					SUI.ThemeRegistry:ApplyVariant('Fel', val)
				end,
			},
		},
	}
end

function module:OnInitialize()
	SUI.ThemeRegistry:Register(
		-- Metadata (always in memory)
		{
			name = 'Fel',
			displayName = 'Fel',
			apiVersion = 1,
			description = 'Demonic interface with green fel energy accents',
			setup = {
				image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Frames_Fel',
			},
			applicableTo = { player = true, target = true },
			variants = {
				{ id = 'engulfed', label = 'Engulfed' },
				{ id = 'calmed', label = 'Calmed' },
			},
			variantCallback = function(variantId)
				local felModule = SUI:GetModule('Style.Fel', true)
				if felModule then
					felModule.DB.minimap.engulfed = (variantId == 'engulfed')
					felModule:MiniMap()
				end
			end,
		},
		-- Data callback (lazy-loaded on first access)
		function()
			return {
				frames = {
					player = {
						elements = {
							SpartanArt = {
								top = {
									enabled = true,
									graphic = 'Fel',
								},
								bg = {
									enabled = true,
									graphic = 'Fel',
								},
								bottom = {
									enabled = true,
									graphic = 'Fel',
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
									graphic = 'Fel',
								},
								bg = {
									enabled = true,
									graphic = 'Fel',
								},
								bottom = {
									enabled = true,
									graphic = 'Fel',
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
				artwork = {},
				unitframes = {
					artwork = {
						top = {
							path = 'Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\UnitFrames',
							TexCoord = { 0.1796875, 0.736328125, 0, 0.099609375 },
							heightScale = 0.25,
							yScale = -0.05,
							alpha = 0.8,
						},
						bg = {
							path = 'Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\UnitFrames',
							TexCoord = { 0.02, 0.385, 0.45, 0.575 },
							PVPAlpha = 0.4,
						},
						bottom = {
							path = 'Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\UnitFrames',
							heightScale = 0.115,
							yScale = 0.0158,
							TexCoord = { 0.1796875, 0.736328125, 0.197265625, 0.244140625 },
							PVPAlpha = 0.8,
						},
					},
					displayName = 'Fel',
					setup = {
						image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Frames_Fel',
					},
				},
				barPositions = {
					['BT4BarStanceBar'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,-285,175',
					['BT4BarPetBar'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,-607,177',
					['MultiCastActionBarFrame'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,-661,191',
					['BT4BarMicroMenu'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,250,151',
					['BT4BarBagBar'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,661,174',
				},
				statusBars = {
					Left = {
						bgTexture = 'Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\StatusBar.png',
						alpha = 0.9,
						size = { 370, 20 },
						texCords = { 0.0546875, 0.9140625, 0.5555555555555556, 0 },
						MaxWidth = 48,
					},
					Right = {
						bgTexture = 'Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\StatusBar.png',
						alpha = 0.9,
						size = { 370, 20 },
						texCords = { 0.0546875, 0.9140625, 0.5555555555555556, 0 },
						MaxWidth = 48,
					},
				},
				minimap = {
					variants = {
						Fel = SUI.IsRetail and {
							size = { 180, 180 },
							position = 'CENTER,SUI_Art_Fel_Left,RIGHT,-30,22',
							engulfed = true,
							elements = {
								background = {
									texture = 'Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\Minimap-Engulfed',
									size = { 260, 260 },
									position = 'CENTER,Minimap,CENTER,5,25',
								},
							},
						} or {
							size = { 140, 140 },
							position = 'CENTER,SUI_Art_Fel_Left,RIGHT,0,-10',
							engulfed = true,
							background = {
								texture = 'Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\Minimap-Engulfed',
								size = { 220, 220 },
								position = 'CENTER,Minimap,CENTER,5,25',
							},
						},
						FelCalmed = SUI.IsRetail and {
							size = { 180, 180 },
							position = 'CENTER,SUI_Art_Fel_Left,RIGHT,-30,22',
							engulfed = false,
							elements = {
								background = {
									texture = 'Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\Minimap-Calmed',
									size = { 200, 200 },
									position = 'CENTER,Minimap,CENTER,3,-1',
								},
							},
						} or {
							size = { 140, 140 },
							position = 'CENTER,SUI_Art_Fel_Left,RIGHT,0,-10',
							engulfed = false,
							background = {
								texture = 'Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\Minimap-Calmed',
								size = { 162, 162 },
								position = 'CENTER,Minimap,CENTER,3,-1',
							},
						},
					},
				},
			}
		end
	)

	---@class SUI.Skins.Fel.Settings
	local defaults = {
		minimap = {
			engulfed = false,
		},
	}
	module.Database = SUI.SpartanUIDB:RegisterNamespace('SkinsFel', { profile = defaults })
	module.DB = module.Database.profile ---@type SUI.Skins.Fel.Settings

	-- Register profile change callbacks
	SUI.DBM:RegisterSequentialProfileRefresh(module)

	module:CreateArtwork()
	Options()
end

function module:OnEnable()
	if SUI:GetActiveStyle() ~= 'Fel' then
		module:Disable()
	else
		module:EnableArtwork()
	end
end

function module:OnDisable()
	artFrame:Hide()
	SUI.opt.args.Artwork.args.Fel.hidden = true
	UnregisterStateDriver(SUI_Art_Fel, 'visibility')
end

function module:SetupVehicleUI()
	if SUI:GetArtworkSetting('VehicleUI') then
		RegisterStateDriver(SUI_Art_Fel, 'visibility', '[overridebar][vehicleui] hide; show')
	end
end

function module:RemoveVehicleUI()
	if SUI:GetArtworkSetting('VehicleUI') then
		UnregisterStateDriver(SUI_Art_Fel, 'visibility')
	end
end

function module:CreateArtwork()
	local plate = CreateFrame('Frame', 'Fel_ActionBarPlate', SpartanUI, 'Fel_ActionBarsTemplate')
	plate:SetFrameStrata('BACKGROUND')
	plate:SetFrameLevel(1)
	plate:ClearAllPoints()
	plate:SetAllPoints(SUI_BottomAnchor)

	--Setup the Bottom Artwork
	artFrame:SetFrameStrata('BACKGROUND')
	artFrame:SetFrameLevel(1)
	artFrame:SetSize(2, 2)
	artFrame:SetPoint('BOTTOM', SUI_BottomAnchor)

	artFrame.Left = artFrame:CreateTexture('SUI_Art_Fel_Left', 'BORDER')
	artFrame.Left:SetPoint('BOTTOMRIGHT', artFrame, 'BOTTOM', 0, 0)
	artFrame.Left:SetTexture('Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\Base_Bar_Left')

	artFrame.Right = artFrame:CreateTexture('SUI_Art_Fel_Right', 'BORDER')
	artFrame.Right:SetPoint('BOTTOMLEFT', artFrame, 'BOTTOM')
	artFrame.Right:SetTexture('Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\Base_Bar_Right')
end

function module:EnableArtwork()
	hooksecurefunc('UIParent_ManageFramePositions', function()
		if TutorialFrameAlertButton then
			TutorialFrameAlertButton:SetParent(Minimap)
			TutorialFrameAlertButton:ClearAllPoints()
			TutorialFrameAlertButton:SetPoint('CENTER', Minimap, 'TOP', -2, 30)
		end
		if CastingBarFrame then
			CastingBarFrame:ClearAllPoints()
			CastingBarFrame:SetPoint('BOTTOM', SUI_Art_Fel, 'TOP', 0, 90)
		end
	end)

	module:SetupVehicleUI()

	if SUI:IsModuleEnabled('Minimap') then
		module:MiniMap()
	end

	-- Sync stored variant with current DB state so the dropdown stays accurate
	local currentVariant = module.DB.minimap.engulfed and 'engulfed' or 'calmed'
	SUI.ThemeRegistry:SetSetting('Fel', 'variant', currentVariant)
end

-- Minimap
function module:MiniMap()
	if module.DB.minimap.engulfed then
		SUI.Minimap:SetActiveStyle('Fel')
	else
		SUI.Minimap:SetActiveStyle('FelCalmed')
	end
end
