local SUI, L = SUI, SUI.L
---@class SUI.Theme.Arcane : SUI.Theme.StyleBase
local module = SUI:NewModule('Style.Arcane')
local unpack = unpack
module.Settings = {}
local Artwork_Core = SUI:GetModule('Artwork') ---@type SUI.Module.Artwork
local artFrame = CreateFrame('Frame', 'SUI_Art_Arcane', SpartanUI)
----------------------------------------------------------------------------------------------------
local function Options()
	-- Replace the plain execute buttons in General > Art Style with variant pickers.
	-- ApplyVariant handles both applyStyle and applyUF declared in the variant metadata.
	SUI.opt.args.General.args.style.args.OverallStyle.args.Arcane = {
		name = 'Arcane',
		type = 'select',
		dialogControl = 'ThemeVariantCard',
		values = { Arcane = 'Blue', ArcaneRed = 'Red' },
		sorting = { 'Arcane', 'ArcaneRed' },
		get = function()
			return SUI.ThemeRegistry:GetActiveVariant('Arcane')
		end,
		set = function(_, val)
			SUI.ThemeRegistry:ApplyVariant('Arcane', val)
		end,
	}
	SUI.opt.args.General.args.style.args.Artwork.args.Arcane = {
		name = 'Arcane',
		type = 'select',
		dialogControl = 'ThemeVariantCard',
		values = { Arcane = 'Blue', ArcaneRed = 'Red' },
		sorting = { 'Arcane', 'ArcaneRed' },
		get = function()
			return SUI.ThemeRegistry:GetActiveVariant('Arcane')
		end,
		set = function(_, val)
			SUI.ThemeRegistry:ApplyVariant('Arcane', val)
		end,
	}

	SUI.opt.args['Artwork'].args['Artwork'] = {
		name = L['Artwork Options'],
		type = 'group',
		order = 10,
		args = {
			Variant = {
				name = 'Arcane',
				type = 'select',
				dialogControl = 'ThemeVariantCard',
				order = 0.05,
				values = { Arcane = 'Blue', ArcaneRed = 'Red' },
				sorting = { 'Arcane', 'ArcaneRed' },
				get = function()
					return SUI.ThemeRegistry:GetActiveVariant('Arcane')
				end,
				set = function(_, val)
					SUI.ThemeRegistry:ApplyVariant('Arcane', val)
				end,
			},
			Color = {
				name = L['Artwork Color'],
				type = 'color',
				hasAlpha = true,
				order = 0.5,
				get = function(info)
					local art = SUI.ThemeRegistry:GetSetting('Arcane', 'Color.Art')
					if not art then
						return 1, 1, 1, 1
					end
					return unpack(art)
				end,
				set = function(info, r, g, b, a)
					SUI.ThemeRegistry:SetSetting('Arcane', 'Color.Art', { r, g, b, a })
					module:SetColor()
				end,
			},
			ColorEnabled = {
				name = L['Color enabled'],
				type = 'toggle',
				order = 0.6,
				get = function(info)
					local art = SUI.ThemeRegistry:GetSetting('Arcane', 'Color.Art')
					if art then
						return true
					else
						return false
					end
				end,
				set = function(info, val)
					if val then
						SUI.ThemeRegistry:SetSetting('Arcane', 'Color.Art', { 1, 1, 1, 1 })
						module:SetColor()
					else
						SUI.ThemeRegistry:SetSetting('Arcane', 'Color.Art', false)
						module:SetColor()
					end
				end,
			},
		},
	}
end

function module:OnInitialize()
	-- Register Arcane theme with ThemeRegistry
	SUI.ThemeRegistry:Register(
		-- Metadata (always in memory)
		{
			name = 'Arcane',
			displayName = 'Arcane',
			apiVersion = 1,
			description = 'Mystical arcane-themed interface with blue energy accents',
			setup = {
				image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Frames_Arcane',
			},
			applicableTo = { player = true, target = true },
			variants = {
				{ id = 'Arcane', label = 'Blue', applyStyle = 'Arcane', applyUF = 'Arcane' },
				{ id = 'ArcaneRed', label = 'Red', applyStyle = 'ArcaneRed', applyUF = 'ArcaneRed' },
			},
		},
		-- Data callback (lazy-loaded on first access)
		function()
			---@type SUI.Style.Settings.StatusBars
			local StatusBarsSettings = {
				bgTexture = 'Interface\\AddOns\\SpartanUI\\Themes\\Arcane\\Images\\StatusBar',
				alpha = 0.9,
				size = { 370, 20 },
				texCords = { 0.0546875, 0.9140625, 0.5555555555555556, 0 },
				MaxWidth = 48,
			}

			return {
				frames = {
					player = {
						elements = {
							Name = {
								enabled = true,
								SetJustifyH = 'LEFT',
								position = {
									anchor = 'BOTTOM',
									x = 0,
									y = -16,
								},
							},
							SpartanArt = {
								top = {
									enabled = true,
									graphic = 'Arcane',
								},
								bg = {
									enabled = true,
									graphic = 'Arcane',
								},
								bottom = {
									enabled = true,
									graphic = 'Arcane',
								},
							},
						},
					},
					target = {
						elements = {
							Name = {
								enabled = true,
								SetJustifyH = 'LEFT',
								position = {
									anchor = 'BOTTOM',
									x = 0,
									y = -16,
								},
							},
							SpartanArt = {
								top = {
									enabled = true,
									graphic = 'Arcane',
								},
								bg = {
									enabled = true,
									graphic = 'Arcane',
								},
								bottom = {
									enabled = true,
									graphic = 'Arcane',
								},
							},
						},
					},
				},
				color = {
					Art = false,
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
				barPositions = {
					['BT4BarStanceBar'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,-285,175',
					['BT4BarPetBar'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,-607,177',
					['MultiCastActionBarFrame'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,-661,191',
					--
					['BT4BarMicroMenu'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,310,151',
					['BT4BarBagBar'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,661,174',
				},
				minimap = SUI.IsRetail and {
					size = { 180, 180 },
					position = 'CENTER,SUI_Art_Arcane_Left,RIGHT,-30,52',
					elements = {
						background = {
							texture = 'Interface\\AddOns\\SpartanUI\\Themes\\Arcane\\Images\\minimap',
							size = { 220, 220 },
						},
					},
				} or {
					size = { 140, 140 },
					position = 'CENTER,SUI_Art_Arcane_Left,RIGHT,0,20',
					background = {
						texture = 'Interface\\AddOns\\SpartanUI\\Themes\\Arcane\\Images\\minimap',
						size = { 180, 180 },
					},
				},
				unitframes = {
					displayName = 'Arcane blue',
					setup = {
						image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Frames_Arcane',
					},
					artwork = {
						top = {
							heightScale = 0.225,
							yScale = -0.09,
							path = 'Interface\\AddOns\\SpartanUI\\Themes\\Arcane\\Images\\UnitFrames',
							TexCoord = { 0, 0.458984375, 0, 0.19921875 },
						},
						bg = {
							path = 'Interface\\AddOns\\SpartanUI\\Themes\\Arcane\\Images\\UnitFrames',
							TexCoord = { 0, 0.458984375, 0.46484375, 0.75 },
						},
						bottom = {
							heightScale = 0.075,
							path = 'Interface\\AddOns\\SpartanUI\\Themes\\Arcane\\Images\\UnitFrames',
							TexCoord = { 0, 0.458984375, 0.374, 0.403 },
						},
					},
				},
				statusBars = { Left = SUI:CopyTable({}, StatusBarsSettings), Right = SUI:CopyTable({}, StatusBarsSettings) },
			}
		end
	)

	-- Register ArcaneRed theme variant with ThemeRegistry
	SUI.ThemeRegistry:Register({
		name = 'ArcaneRed',
		displayName = 'Arcane Red',
		apiVersion = 1,
		description = 'Crimson arcane-themed interface with red energy accents',
		setup = {
			image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Frames_ArcaneRed',
		},
		applicableTo = { player = true, target = true },
		variantGroup = 'Arcane',
	}, function()
		return {
			frames = {
				player = {
					elements = {
						SpartanArt = {
							top = {
								enabled = true,
								graphic = 'ArcaneRed',
							},
							bg = {
								enabled = true,
								graphic = 'ArcaneRed',
							},
							bottom = {
								enabled = true,
								graphic = 'ArcaneRed',
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
								graphic = 'ArcaneRed',
							},
							bg = {
								enabled = true,
								graphic = 'ArcaneRed',
							},
							bottom = {
								enabled = true,
								graphic = 'ArcaneRed',
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
			unitframes = {
				displayName = 'Arcane red',
				setup = {
					image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Frames_ArcaneRed',
				},
				artwork = {
					top = {
						heightScale = 0.225,
						yScale = -0.09,
						path = 'Interface\\AddOns\\SpartanUI\\Themes\\Arcane\\Images\\UnitFrames',
						TexCoord = { 0.533203125, 1, 0, 0.19921875 },
					},
					bg = {
						path = 'Interface\\AddOns\\SpartanUI\\Themes\\Arcane\\Images\\UnitFrames',
						TexCoord = { 0.533203125, 1, 0.46484375, 0.75 },
					},
					bottom = {
						heightScale = 0.075,
						path = 'Interface\\AddOns\\SpartanUI\\Themes\\Arcane\\Images\\UnitFrames',
						TexCoord = { 0.533203125, 1, 0.374, 0.403 },
					},
				},
			},
		}
	end)

	-- Enable themes in options screen
	SUI.opt.args['General'].args['style'].args['OverallStyle'].args['Arcane'].disabled = false
	SUI.opt.args['General'].args['style'].args['Artwork'].args['Arcane'].disabled = false

	module:CreateArtwork()
end

function module:OnEnable()
	local activeStyle = SUI:GetActiveStyle()
	local activeEntry = SUI.ThemeRegistry:Get(activeStyle)
	local activeGroup = (activeEntry and activeEntry.variantGroup) or activeStyle
	if activeGroup ~= 'Arcane' then
		module:Disable()
	else
		hooksecurefunc('UIParent_ManageFramePositions', function()
			if TutorialFrameAlertButton then
				TutorialFrameAlertButton:SetParent(Minimap)
				TutorialFrameAlertButton:ClearAllPoints()
				TutorialFrameAlertButton:SetPoint('CENTER', Minimap, 'TOP', -2, 30)
			end
			if CastingBarFrame then
				CastingBarFrame:ClearAllPoints()
				CastingBarFrame:SetPoint('BOTTOM', SUI_Art_Arcane, 'TOP', 0, 90)
			end
		end)

		local art = SUI.ThemeRegistry:GetSetting('Arcane', 'Color.Art')
		if art then
			module:SetColor()
		end
		Options()
		module:SetupVehicleUI()
	end
end

function module:OnDisable()
	SUI_Art_Arcane:Hide()
	UnregisterStateDriver(SUI_Art_Arcane, 'visibility')
end

function module:SetColor()
	local r, g, b, a = 1, 1, 1, 1
	local art = SUI.ThemeRegistry:GetSetting('Arcane', 'Color.Art')
	if art then
		r, g, b, a = unpack(art)
	end

	SUI_Art_Arcane.Left:SetVertexColor(r, g, b, a)
	SUI_Art_Arcane.Right:SetVertexColor(r, g, b, a)

	if _G['SUI_StatusBar_Left'] then
		_G['SUI_StatusBar_Left'].bg:SetVertexColor(r, g, b, a)
		_G['SUI_StatusBar_Left'].overlay:SetVertexColor(r, g, b, a)
	end
	if _G['SUI_StatusBar_Right'] then
		_G['SUI_StatusBar_Right'].bg:SetVertexColor(r, g, b, a)
		_G['SUI_StatusBar_Right'].overlay:SetVertexColor(r, g, b, a)
	end
end

function module:SetupVehicleUI()
	if SUI:GetArtworkSetting('VehicleUI') then
		RegisterStateDriver(SUI_Art_Arcane, 'visibility', '[overridebar][vehicleui] hide; show')
	end
end

function module:RemoveVehicleUI()
	if SUI:GetArtworkSetting('VehicleUI') then
		UnregisterStateDriver(SUI_Art_Arcane, 'visibility')
	end
end

function module:CreateArtwork()
	if Arcane_ActionBarPlate then
		return
	end

	local BarBGSettings = {
		name = 'Arcane',
		TexturePath = 'Interface\\AddOns\\SpartanUI\\Themes\\Arcane\\Images\\Barbg',
		TexCoord = { 0.07421875, 0.92578125, 0.359375, 0.6796875 },
		alpha = 0.5,
	}

	local plate = CreateFrame('Frame', 'Arcane_ActionBarPlate', SUI_Art_Arcane)
	plate:SetSize(1002, 139)
	plate:SetFrameStrata('BACKGROUND')
	plate:SetFrameLevel(1)
	plate:SetAllPoints(SUI_BottomAnchor)

	for i = 1, 4 do
		plate['BG' .. i] = Artwork_Core:CreateBarBG(BarBGSettings, i, Arcane_ActionBarPlate)
		if UnitFactionGroup('PLAYER') == 'Horde' then
			_G['Arcane_Bar' .. i .. 'BG']:SetVertexColor(1, 0, 0, 0.25)
		else
			_G['Arcane_Bar' .. i .. 'BG']:SetVertexColor(0, 0, 1, 0.25)
		end
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

	artFrame.Left = artFrame:CreateTexture('SUI_Art_Arcane_Left', 'BORDER')
	artFrame.Left:SetTexture('Interface\\AddOns\\SpartanUI\\Themes\\Arcane\\Images\\Art_Left')
	artFrame.Left:SetPoint('BOTTOMRIGHT', artFrame, 'BOTTOM', 0, 0)
	artFrame.Left:SetScale(0.75)

	artFrame.Right = artFrame:CreateTexture('SUI_Art_Arcane_Right', 'BORDER')
	artFrame.Right:SetTexture('Interface\\AddOns\\SpartanUI\\Themes\\Arcane\\Images\\Art_Right')
	artFrame.Right:SetPoint('BOTTOMLEFT', artFrame, 'BOTTOM')
	artFrame.Right:SetScale(0.75)
end
