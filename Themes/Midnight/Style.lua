local SUI = SUI
---@class SUI.Theme.Midnight : SUI.Theme.StyleBase
local module = SUI:NewModule('Style.Midnight')
local artFrame = CreateFrame('Frame', 'SUI_Art_Midnight', SpartanUI)
module.Settings = {}

local ART_PATH = 'Interface\\AddOns\\SpartanUI\\Themes\\Midnight\\Images\\BottomArt.png'
local MASK_PATH = 'Interface\\AddOns\\SpartanUI\\images\\Menu\\SquareMask'

-- Source image is 1754x600
local w = 1754
local h = 600
local TEX_COORDS = {
	TopLeft = { 0, (158 / w), 0, 0.2633333333333333 },
	TopRight = { (1596 / w), 1, 0, 0.2633333333333333 },
	TopEdge = { (400 / w), (420 / w), 0, (159 / h) },
	LeftEdge = { (160 / w), (318 / w), (1 / h), 0.2633333333333333 },
	-- RightEdge = { (197 / w), (355 / w), (1 / h), 0.2633333333333333 },
	RightEdge = { (1596 / w), 1, (148 / h), 0.2633333333333333 },
	BG = { 0, 1, (162 / h), 1 },
}

local VARIANT_DEFAULTS = {
	tall = { width = 460, height = 245 },
	wide = { width = 855, height = 185 },
}

local function GetOverlayDimensions()
	local variant = SUI.ThemeRegistry:GetActiveVariant('Midnight') or 'void_wide'
	local shape = variant:match('_(%w+)$') or 'tall'
	local defaults = VARIANT_DEFAULTS[shape]

	local w = SUI.ThemeRegistry:GetSetting('Midnight', 'overlayWidth') or defaults.width
	local h = SUI.ThemeRegistry:GetSetting('Midnight', 'overlayHeight') or defaults.height
	return w, h
end

local function VariantOptions()
	-- Variant pickers in General > Art Style (always visible so users can switch to Midnight)
	-- ApplyVariant handles applyStyle/applyUF from variant metadata.
	SUI.opt.args.General.args.style.args.OverallStyle.args.Midnight = {
		name = 'Midnight',
		type = 'select',
		dialogControl = 'ThemeVariantCard',
		values = { void_tall = 'Void - Tall', void_wide = 'Void - Wide', shadow_tall = 'Shadow - Tall', shadow_wide = 'Shadow - Wide' },
		sorting = { 'void_wide', 'void_tall', 'shadow_wide', 'shadow_tall' },
		get = function()
			return SUI.ThemeRegistry:GetActiveVariant('Midnight')
		end,
		set = function(_, val)
			SUI.ThemeRegistry:ApplyVariant('Midnight', val)
		end,
	}
	SUI.opt.args.General.args.style.args.Artwork.args.Midnight = {
		name = 'Midnight',
		type = 'select',
		dialogControl = 'ThemeVariantCard',
		values = { void_tall = 'Void - Tall', void_wide = 'Void - Wide', shadow_tall = 'Shadow - Tall', shadow_wide = 'Shadow - Wide' },
		sorting = { 'void_wide', 'void_tall', 'shadow_wide', 'shadow_tall' },
		get = function()
			return SUI.ThemeRegistry:GetActiveVariant('Midnight')
		end,
		set = function(_, val)
			SUI.ThemeRegistry:ApplyVariant('Midnight', val)
		end,
	}
end

local function ArtworkOptions()
	-- Theme-specific artwork options (only when Midnight is active)
	SUI.opt.args.Artwork.args.Midnight = {
		name = 'Midnight',
		type = 'group',
		order = 10,
		args = {
			Variant = {
				name = 'Midnight',
				type = 'select',
				dialogControl = 'ThemeVariantCard',
				order = 0.1,
				values = { void_tall = 'Void - Tall', void_wide = 'Void - Wide', shadow_tall = 'Shadow - Tall', shadow_wide = 'Shadow - Wide' },
				sorting = { 'void_wide', 'void_tall', 'shadow_wide', 'shadow_tall' },
				get = function()
					return SUI.ThemeRegistry:GetActiveVariant('Midnight')
				end,
				set = function(_, val)
					SUI.ThemeRegistry:ApplyVariant('Midnight', val)
				end,
			},
			overlayWidth = {
				name = 'Overlay Width',
				type = 'range',
				order = 1,
				min = 200,
				max = 1750,
				step = 5,
				get = function()
					local w = GetOverlayDimensions()
					return w
				end,
				set = function(_, val)
					SUI.ThemeRegistry:SetSetting('Midnight', 'overlayWidth', val)
					module:UpdateOverlay()
				end,
			},
			overlayHeight = {
				name = 'Overlay Height',
				type = 'range',
				order = 2,
				min = 120,
				max = 440,
				step = 5,
				get = function()
					local _, h = GetOverlayDimensions()
					return h
				end,
				set = function(_, val)
					SUI.ThemeRegistry:SetSetting('Midnight', 'overlayHeight', val)
					module:UpdateOverlay()
				end,
			},
		},
	}
end

function module:OnInitialize()
	SUI.ThemeRegistry:Register(
		-- Metadata (always in memory)
		{
			name = 'Midnight',
			displayName = 'Midnight',
			apiVersion = 1,
			description = 'Modern, clean interface with focus on readability and well-spaced aura icons',
			setup = {
				image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Midnight.png',
			},
			applicableTo = { player = true, target = true, pet = true, focus = true, boss = true, arena = true, raid = true, raid10 = true, raid25 = true, raid40 = true, party = true },
			variants = {
				{ id = 'void_wide', label = 'Void - Wide', applyStyle = 'Midnight', applyUF = 'Midnight_Void' },
				{ id = 'void_tall', label = 'Void - Tall', applyStyle = 'Midnight', applyUF = 'Midnight_Void' },
				{ id = 'shadow_tall', label = 'Shadow - Tall', applyStyle = 'Midnight', applyUF = 'Midnight_Shadow' },
				{ id = 'shadow_wide', label = 'Shadow - Wide', applyStyle = 'Midnight', applyUF = 'Midnight_Shadow' },
			},
			variantCallback = function(variantId)
				SUI.ThemeRegistry:SetSetting('Midnight', 'overlayWidth', nil)
				SUI.ThemeRegistry:SetSetting('Midnight', 'overlayHeight', nil)
				module:UpdateOverlay()
				module:UpdateBarLayout(variantId)
			end,
		},
		-- Data callback (lazy-loaded on first access)
		function()
			return {
				minimap = {
					position = 'TOPRIGHT,UIParent,TOPRIGHT,-20,-20',
					size = { 250, 250 },
					elements = {
						background = {
							texture = 'Interface\\AddOns\\SpartanUI\\Themes\\Midnight\\Images\\Minimap.png',
							size = { 204, 204 },
							alpha = 0.9,
							position = 'CENTER,Minimap,CENTER,-4,-5',
							BlendMode = 'BLEND',
						},
						BorderTop = {
							scale = 1.05,
							color = { 0.302, 0.102, 0.4, 1 },
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
				statusBars = {
					Left = {
						size = { 370, 20 },
						Position = 'BOTTOMRIGHT,SUI_BottomAnchor,BOTTOM,-15,1',
						bgColor = { 0, 0, 0, 0.8 },
						barOffsetX = 1,
						atlasBorder = {
							left = 'midnight-scenario-barframe-borderleft',
							center = 'midnight-scenario-barframe-bordercenter',
							right = 'midnight-scenario-barframe-borderright',
							capWidth = 31,
							height = 35,
						},
					},
					Right = {
						size = { 370, 20 },
						Position = 'BOTTOMLEFT,SUI_BottomAnchor,BOTTOM,15,1',
						bgColor = { 0, 0, 0, 0.8 },
						barOffsetX = 1,
						atlasBorder = {
							left = 'midnight-scenario-barframe-borderleft',
							center = 'midnight-scenario-barframe-bordercenter',
							right = 'midnight-scenario-barframe-borderright',
							capWidth = 31,
							height = 35,
						},
					},
				},
				barPositions = module:GetBarPositions((SUI.DB and SUI.DB.ThemeSettings and SUI.DB.ThemeSettings['Midnight'] and SUI.DB.ThemeSettings['Midnight'].variant) or 'void_wide'),
			}
		end
	)

	-- Shared UF layout for all Midnight variants (no color settings - those differ per variant)
	local function GetSharedFrameConfigs()
		local shared = {
			Portrait = { enabled = false },
			ClassIcon = { enabled = false },
			Castbar = { height = 15, Icon = {
				enabled = false,
			} },
			Power = {
				text = {
					['1'] = { enabled = false },
				},
				position = { y = 0 },
			},
		}
		local sharedCompact = {
			Portrait = { enabled = false },
			Castbar = { enabled = false },
		}

		return {
			player = {
				width = 250,
				elements = {
					Castbar = shared.Castbar,
					Portrait = shared.Portrait,
					ClassIcon = shared.ClassIcon,
					Power = shared.Power,
					Health = {
						height = 50,
						text = {
							['2'] = {
								enabled = true,
								text = '[SUIHealth(percentage)]%',
								position = { anchor = 'TOPRIGHT', x = -3, y = -3 },
							},
						},
					},
					Name = {
						textSize = 16,
						height = 16,
					},
					Buffs = {
						enabled = false,
						number = 32,
						size = 20,
						rows = 4,
						spacing = 3,
						growthx = 'RIGHT',
						growthy = 'UP',
						position = { anchor = 'BOTTOMLEFT', relativePoint = 'TOPLEFT', x = 0, y = 5 },
					},
					Debuffs = {
						enabled = true,
						number = 16,
						size = 20,
						rows = 2,
						spacing = 3,
						growthx = 'RIGHT',
						growthy = 'DOWN',
						position = { anchor = 'TOPLEFT', relativePoint = 'BOTTOMLEFT', x = 0, y = -5 },
					},
					ClassPower = {
						position = { anchor = 'TOPLEFT', relativeTo = 'Frame', relativePoint = 'BOTTOMLEFT' },
					},
				},
			},
			target = {
				width = 250,
				elements = {
					Castbar = shared.Castbar,
					Portrait = shared.Portrait,
					ClassIcon = shared.ClassIcon,
					Power = shared.Power,
					Health = {
						height = 50,
						text = {
							['2'] = {
								enabled = true,
								text = '[SUIHealth(percentage)]%',
								position = { anchor = 'TOPRIGHT', x = -3, y = -3 },
							},
						},
					},
					Name = {
						textSize = 16,
						height = 16,
					},
					Buffs = {
						enabled = true,
						number = 16,
						size = 26,
						rows = 2,
						spacing = 3,
						growthx = 'LEFT',
						growthy = 'UP',
						position = { anchor = 'BOTTOMRIGHT', relativePoint = 'TOPRIGHT', x = 0, y = 5 },
						retail = { filterMode = 'healing_mode' },
					},
					Debuffs = {
						enabled = true,
						number = 16,
						size = 30,
						rows = 2,
						spacing = 3,
						growthx = 'LEFT',
						growthy = 'DOWN',
						position = { anchor = 'TOPRIGHT', relativePoint = 'BOTTOMRIGHT', x = 0, y = -5 },
						retail = { filterMode = 'player_debuffs' },
					},
				},
			},
			targettarget = {
				elements = {
					Health = {
						text = {
							['1'] = {
								text = '[SUIHealth(percentage)]%',
								position = { anchor = 'BOTTOMRIGHT', x = -2, y = 2 },
							},
						},
					},
				},
			},
			pet = {
				width = 120,
				elements = {
					Portrait = shared.Portrait,
					ClassIcon = shared.ClassIcon,
					Castbar = shared.Castbar,
					Power = shared.Power,
					Name = {
						text = '[name]',
						textSize = 10,
						height = 10,
						position = { anchor = 'TOPLEFT', relativePoint = 'TOPLEFT', x = 1, y = -1 },
					},
					Health = {
						text = {
							['1'] = {
								enabled = true,
								text = '[SUIHealth(percentage)]%',
								position = { anchor = 'BOTTOMRIGHT', x = -2 },
							},
						},
					},
				},
			},
			pettarget = {
				elements = {},
			},
			focus = {
				width = 200,
				elements = {
					Portrait = shared.Portrait,
					ClassIcon = shared.ClassIcon,
					Buffs = {
						enabled = true,
						number = 8,
						size = 22,
						rows = 1,
						spacing = 2,
						growthx = 'RIGHT',
						growthy = 'UP',
						position = { anchor = 'BOTTOMLEFT', relativePoint = 'TOPLEFT', x = 0, y = 5 },
						retail = { filterMode = 'healing_mode' },
					},
					Debuffs = {
						enabled = true,
						number = 8,
						size = 22,
						rows = 1,
						spacing = 2,
						growthx = 'RIGHT',
						growthy = 'DOWN',
						position = { anchor = 'TOPLEFT', relativePoint = 'BOTTOMLEFT', x = 0, y = -5 },
						retail = { filterMode = 'player_debuffs' },
					},
				},
			},
			focustarget = {
				elements = {},
			},
			boss = {
				width = 200,
				elements = {
					Portrait = shared.Portrait,
					ClassIcon = shared.ClassIcon,
					Buffs = {
						enabled = true,
						number = 8,
						size = 22,
						rows = 1,
						spacing = 2,
						growthx = 'RIGHT',
						growthy = 'UP',
						position = { anchor = 'BOTTOMLEFT', relativePoint = 'TOPLEFT', x = 0, y = 5 },
						retail = { filterMode = 'healing_mode' },
					},
					Debuffs = {
						enabled = true,
						number = 8,
						size = 22,
						rows = 1,
						spacing = 2,
						growthx = 'RIGHT',
						growthy = 'DOWN',
						position = { anchor = 'TOPLEFT', relativePoint = 'BOTTOMLEFT', x = 0, y = -5 },
						retail = { filterMode = 'player_debuffs' },
					},
				},
			},
			bosstarget = {
				elements = {},
			},
			arena = {
				width = 200,
				elements = {
					Portrait = shared.Portrait,
					ClassIcon = shared.ClassIcon,
					Buffs = {
						enabled = true,
						number = 8,
						size = 22,
						rows = 1,
						spacing = 2,
						growthx = 'RIGHT',
						growthy = 'UP',
						position = { anchor = 'BOTTOMLEFT', relativePoint = 'TOPLEFT', x = 0, y = 5 },
						retail = { filterMode = 'healing_mode' },
					},
					Debuffs = {
						enabled = true,
						number = 8,
						size = 22,
						rows = 1,
						spacing = 2,
						growthx = 'RIGHT',
						growthy = 'DOWN',
						position = { anchor = 'TOPLEFT', relativePoint = 'BOTTOMLEFT', x = 0, y = -5 },
						retail = { filterMode = 'player_debuffs' },
					},
				},
			},
			raid40 = {
				width = 95,
				maxColumns = 5,
				unitsPerColumn = 8,
				elements = {
					Health = { height = 36 },
					Power = { height = 4 },
					Portrait = sharedCompact.Portrait,
					Castbar = sharedCompact.Castbar,
					Buffs = {
						enabled = true,
						number = 3,
						size = 15,
						rows = 1,
						spacing = 2,
						growthx = 'RIGHT',
						growthy = 'UP',
						position = { anchor = 'BOTTOMLEFT', relativePoint = 'BOTTOMLEFT', x = 2, y = 3 },
						retail = { filterMode = 'healing_mode' },
					},
					Debuffs = {
						enabled = true,
						number = 5,
						size = 15,
						rows = 1,
						spacing = 2,
						growthx = 'RIGHT',
						growthy = 'DOWN',
						position = { anchor = 'TOPRIGHT', relativePoint = 'TOPRIGHT', x = 0, y = -3 },
						retail = { filterMode = 'raid_debuffs' },
					},
				},
			},
			raid10 = {
				width = 110,
				maxColumns = 2,
				unitsPerColumn = 5,
				elements = {
					Health = { height = 40 },
					Power = { height = 4 },
					Portrait = sharedCompact.Portrait,
					Castbar = sharedCompact.Castbar,
					Buffs = {
						enabled = true,
						number = 5,
						size = 18,
						rows = 1,
						spacing = 2,
						growthx = 'RIGHT',
						growthy = 'UP',
						position = { anchor = 'BOTTOMLEFT', relativePoint = 'BOTTOMLEFT', x = 2, y = 3 },
						retail = { filterMode = 'healing_mode' },
					},
					Debuffs = {
						enabled = true,
						number = 5,
						size = 18,
						rows = 1,
						spacing = 2,
						growthx = 'RIGHT',
						growthy = 'DOWN',
						position = { anchor = 'TOPRIGHT', relativePoint = 'TOPRIGHT', x = 0, y = -3 },
						retail = { filterMode = 'raid_debuffs' },
					},
				},
			},
			raid25 = {
				width = 95,
				maxColumns = 5,
				unitsPerColumn = 5,
				elements = {
					Health = { height = 36 },
					Power = { height = 4 },
					Portrait = sharedCompact.Portrait,
					Castbar = sharedCompact.Castbar,
					Buffs = {
						enabled = true,
						number = 3,
						size = 15,
						rows = 1,
						spacing = 2,
						growthx = 'RIGHT',
						growthy = 'UP',
						position = { anchor = 'BOTTOMLEFT', relativePoint = 'BOTTOMLEFT', x = 2, y = 3 },
						retail = { filterMode = 'healing_mode' },
					},
					Debuffs = {
						enabled = true,
						number = 5,
						size = 15,
						rows = 1,
						spacing = 2,
						growthx = 'RIGHT',
						growthy = 'DOWN',
						position = { anchor = 'TOPRIGHT', relativePoint = 'TOPRIGHT', x = 0, y = -3 },
						retail = { filterMode = 'raid_debuffs' },
					},
				},
			},
			party = {
				width = 180,
				yOffset = -1,
				elements = {
					Name = {
						text = '[SUI_smartlevel] [SUI_ColorClass][name]',
					},
					Health = {
						height = 65,
						text = {
							['1'] = {
								text = '[SUIHealth(percentage)]%',
								position = { anchor = 'BOTTOM', y = 1 },
							},
						},
						position = { anchor = 'TOP', relativeTo = 'Frame', relativePoint = 'TOP', y = 0 },
					},
					Power = { height = 5 },
					Portrait = sharedCompact.Portrait,
					Castbar = sharedCompact.Castbar,
					RaidDebuffs = {
						enabled = false,
					},
					Buffs = {
						enabled = true,
						number = 3,
						size = 15,
						rows = 1,
						spacing = 2,
						growthx = 'RIGHT',
						growthy = 'UP',
						position = { anchor = 'BOTTOMLEFT', relativePoint = 'BOTTOMLEFT', x = 2, y = 3 },
						retail = { filterMode = 'healing_mode' },
					},
					Debuffs = {
						enabled = true,
						number = 5,
						size = 15,
						rows = 1,
						spacing = 2,
						growthx = 'RIGHT',
						growthy = 'DOWN',
						position = { anchor = 'TOP', relativePoint = 'BOTTOM', x = 0, y = -3 },
						retail = { filterMode = 'raid_debuffs' },
					},
				},
			},
			partypet = {
				enabled = true,
				elements = {
					Name = {
						text = '[name]',
						textSize = 8,
						height = 8,
						position = { anchor = 'TOPLEFT', relativePoint = 'TOPLEFT', x = 1, y = -1 },
					},
					text = {
						['1'] = {
							size = 8,
						},
					},
					Power = {
						enabled = false,
					},
				},
			},
			partytarget = {
				elements = {},
			},
		}
	end

	-- Apply color scheme to shared frame configs
	local function ApplyColorScheme(frames, scheme)
		for frameName, frameConfig in pairs(frames) do
			if not frameConfig.elements then
				frameConfig.elements = {}
			end
			local elements = frameConfig.elements

			local isCompact = (frameName:match('^raid%d+$') or frameName == 'party' or frameName == 'partypet' or frameName == 'partytarget')

			if scheme == 'void' then
				-- Void: Black bars, class-colored missing health
				elements.Health = elements.Health or {}
				elements.Health.customColors = { useCustom = true, barColor = { 0, 0, 0, 1 } }
				elements.Health.bg = { useClassColor = true, classColorAlpha = 1 }

				elements.Power = elements.Power or {}
				elements.Power.customColors = { useCustom = true, barColor = { 0, 0, 0, 1 } }
				elements.Power.bg = { useClassColor = false }
			elseif scheme == 'shadow' then
				-- Shadow: Class-colored bars, dark missing health
				elements.Health = elements.Health or {}
				elements.Health.colorClass = true
				elements.Health.colorSmooth = false
				elements.Health.bg = { color = { 0, 0, 0, 0.8 }, useClassColor = false }

				elements.Power = elements.Power or {}
				elements.Power.colorClass = true
				elements.Power.bg = { color = { 0, 0, 0, 0.8 } }
			end

			if isCompact then
				elements.FrameBackground = {
					enabled = true,
					background = {
						enabled = true,
						type = 'color',
						color = { 0, 0, 0, 1 },
						classColor = false,
					},
					border = {
						enabled = false,
					},
					displayLevel = -1,
				}
			else
				elements.FrameBackground = {
					enabled = true,
					background = {
						enabled = true,
						type = 'color',
						color = { 0, 0, 0, 1 },
						classColor = false,
					},
					border = {
						enabled = true,
						classColors = {
							top = true,
							right = true,
							left = true,
							bottom = true,
						},
						sides = {
							top = true,
							right = true,
							left = true,
							bottom = true,
						},
						size = 2,
					},
					displayLevel = -1,
				}
			end

			-- Name and Health text positioning
			if not isCompact then
				elements.Name = elements.Name or {}
				elements.Name.SetJustifyH = 'LEFT'
				elements.Name.SetJustifyV = 'TOP'
				elements.Name.text = elements.Name.text or '[difficulty][SUI_smartlevel] [SUI_ColorClass][name]'
				elements.Name.position = { anchor = 'TOPLEFT', relativeTo = 'Health', relativePoint = 'TOPLEFT', x = 3, y = -3 }

				elements.HealthText = elements.HealthText or {}
				elements.HealthText['1'] = { position = { anchor = 'BOTTOMRIGHT' } }
			elseif frameName == 'party' then
				elements.Name = elements.Name or {}
				elements.Name.SetJustifyH = 'LEFT'
				elements.Name.SetJustifyV = 'TOP'
				elements.Name.text = elements.Name.text or '[difficulty][SUI_smartlevel] [SUI_ColorClass][name]'
				elements.Name.position = { anchor = 'TOPLEFT', relativeTo = 'Health', relativePoint = 'TOPLEFT', x = 3, y = -3 }
			end

			-- Threat highlights the whole frame, not just name
			elements.ThreatIndicator = elements.ThreatIndicator or {}
			elements.ThreatIndicator.points = {
				{ anchor = 'TOPLEFT', relativeTo = 'Frame', x = -3, y = 3 },
				{ anchor = 'BOTTOMRIGHT', relativeTo = 'Frame', x = 3, y = -3 },
			}
		end
		return frames
	end

	-- Register Midnight_Void sub-theme
	local allFrameGroups = {
		player = true,
		target = true,
		pet = true,
		focus = true,
		boss = true,
		arena = true,
		raid = true,
		raid10 = true,
		raid25 = true,
		raid40 = true,
		party = true,
		partypet = true,
		partytarget = true,
	}
	SUI.ThemeRegistry:Register({
		name = 'Midnight_Void',
		displayName = 'Midnight Void',
		apiVersion = 1,
		description = 'Black bars with class-colored missing health',
		setup = { image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Frames_Midnight_Void.png' },
		applicableTo = allFrameGroups,
		variantGroup = 'Midnight',
	}, function()
		local frameConfigs = ApplyColorScheme(GetSharedFrameConfigs(), 'void')
		return {
			frames = frameConfigs,
			unitframes = {
				displayName = 'Midnight Void',
				setup = { image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Frames_Midnight_Void.png' },
			},
		}
	end)

	-- Register Midnight_Shadow sub-theme
	SUI.ThemeRegistry:Register({
		name = 'Midnight_Shadow',
		displayName = 'Midnight Shadow',
		apiVersion = 1,
		description = 'Class-colored bars with dark missing health',
		setup = { image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Frames_Midnight_Shadow.png' },
		applicableTo = allFrameGroups,
		variantGroup = 'Midnight',
	}, function()
		local frameConfigs = ApplyColorScheme(GetSharedFrameConfigs(), 'shadow')
		return {
			frames = frameConfigs,
			unitframes = {
				displayName = 'Midnight Shadow',
				setup = { image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Frames_Midnight_Shadow.png' },
			},
		}
	end)

	if SUI.Artwork then
		if Midnight_ActionBarPlate then
			return
		end

		local BarBGSettings = {
			name = 'Midnight',
			TexturePath = 'Interface\\AddOns\\SpartanUI\\Themes\\War\\Images\\Barbg',
			TexCoord = { 0.07421875, 0.92578125, 0.359375, 0.6796875 },
			alpha = 0.5,
			color = { 0.33, 0.16, 0.45, 0.6 },
		}

		local plate = CreateFrame('Frame', 'Midnight_ActionBarPlate', artFrame)
		plate:SetSize(1002, 139)
		plate:SetFrameStrata('BACKGROUND')
		plate:SetFrameLevel(1)
		plate:SetAllPoints(SUI_BottomAnchor)

		for i = 1, 6 do
			plate['BG' .. i] = SUI.Artwork:CreateBarBG(BarBGSettings, i, plate)
			plate['BG' .. i]:SetFrameLevel(4)
			-- plate['BG' .. i]:SetAlpha(0.6)
		end
		module.plate = plate

		local CORNER_WIDTH = 100
		local CORNER_HEIGHT = 100
		local TOP_EDGE_HEIGHT = 100
		local SIDE_EDGE_WIDTH = 100

		-- Setup the Bottom Artwork
		artFrame:SetFrameStrata('BACKGROUND')
		artFrame:SetFrameLevel(1)
		artFrame:SetSize(2, 2)
		artFrame:SetPoint('BOTTOM', SUI_BottomAnchor)

		-- Overlay frame defines the visible window - frame pieces border it
		local overlayW, overlayH = GetOverlayDimensions()
		artFrame.Overlay = CreateFrame('Frame', 'SUI_Art_Midnight_Overlay', artFrame)
		artFrame.Overlay:SetSize(overlayW, overlayH)
		artFrame.Overlay:SetPoint('BOTTOM', artFrame, 'BOTTOM', 0, 0)
		artFrame.Overlay:SetFrameLevel(2)

		-- BG texture at natural size, centered on overlay, masked to overlay bounds
		-- Source BG region is full width (1754px) x 73% height (438px)
		artFrame.BG = artFrame.Overlay:CreateTexture('SUI_Art_Midnight_BG', 'BACKGROUND')
		artFrame.BG:SetTexture(ART_PATH)
		artFrame.BG:SetTexCoord(unpack(TEX_COORDS.BG))
		artFrame.BG:SetSize(1754, 438)
		artFrame.BG:SetPoint('CENTER', artFrame.Overlay, 'CENTER', 0, 0)

		-- Rectangle mask clips BG to the overlay frame
		artFrame.Mask = artFrame.Overlay:CreateMaskTexture()
		artFrame.Mask:SetTexture(MASK_PATH, 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE')
		artFrame.Mask:SetAllPoints(artFrame.Overlay)
		artFrame.BG:AddMaskTexture(artFrame.Mask)

		-- Top-left corner
		artFrame.TL = artFrame.Overlay:CreateTexture('SUI_Art_Midnight_TL', 'ARTWORK')
		artFrame.TL:SetTexture(ART_PATH)
		artFrame.TL:SetTexCoord(unpack(TEX_COORDS.TopLeft))
		artFrame.TL:SetSize(CORNER_WIDTH, CORNER_HEIGHT)
		artFrame.TL:SetPoint('TOPLEFT', artFrame.Overlay, 'TOPLEFT', -6, 6)

		-- Top-right corner
		artFrame.TR = artFrame.Overlay:CreateTexture('SUI_Art_Midnight_TR', 'ARTWORK')
		artFrame.TR:SetTexture(ART_PATH)
		artFrame.TR:SetTexCoord(unpack(TEX_COORDS.TopRight))
		artFrame.TR:SetSize(CORNER_WIDTH, CORNER_HEIGHT)
		artFrame.TR:SetPoint('TOPRIGHT', artFrame.Overlay, 'TOPRIGHT', 6, 6)

		-- Top edge (between corners along overlay top)
		artFrame.TopEdge = artFrame.Overlay:CreateTexture('SUI_Art_Midnight_TopEdge', 'ARTWORK')
		artFrame.TopEdge:SetTexture(ART_PATH, 'REPEAT', 'CLAMP')
		artFrame.TopEdge:SetTexCoord(unpack(TEX_COORDS.TopEdge))
		artFrame.TopEdge:SetHeight(TOP_EDGE_HEIGHT)
		artFrame.TopEdge:SetPoint('TOPLEFT', artFrame.TL, 'TOPRIGHT', 0, 0)
		artFrame.TopEdge:SetPoint('TOPRIGHT', artFrame.TR, 'TOPLEFT', 0, 0)

		-- Left edge (from below TL corner to overlay bottom)
		artFrame.LeftEdge = artFrame.Overlay:CreateTexture('SUI_Art_Midnight_LeftEdge', 'ARTWORK')
		artFrame.LeftEdge:SetTexture(ART_PATH, 'CLAMP', 'REPEAT')
		artFrame.LeftEdge:SetTexCoord(unpack(TEX_COORDS.LeftEdge))
		artFrame.LeftEdge:SetWidth(SIDE_EDGE_WIDTH)
		artFrame.LeftEdge:SetPoint('TOPLEFT', artFrame.TL, 'BOTTOMLEFT', 0, 3)
		artFrame.LeftEdge:SetPoint('BOTTOMLEFT', artFrame.Overlay, 'BOTTOMLEFT', 0, -1)

		-- Right edge (from below TR corner to overlay bottom)
		artFrame.RightEdge = artFrame.Overlay:CreateTexture('SUI_Art_Midnight_RightEdge', 'ARTWORK')
		artFrame.RightEdge:SetTexture(ART_PATH, 'CLAMP', 'REPEAT')
		artFrame.RightEdge:SetTexCoord(unpack(TEX_COORDS.RightEdge))
		artFrame.RightEdge:SetWidth(SIDE_EDGE_WIDTH)
		artFrame.RightEdge:SetPoint('TOPRIGHT', artFrame.TR, 'BOTTOMRIGHT', 0, 3)
		artFrame.RightEdge:SetPoint('BOTTOMRIGHT', artFrame.Overlay, 'BOTTOMRIGHT', 0, -1)
	end

	VariantOptions()
end

function module:UpdateOverlay()
	if not artFrame.Overlay then
		return
	end
	local w, h = GetOverlayDimensions()
	artFrame.Overlay:SetSize(w, h)
end

-- Shared bar positions that don't change between tall/wide
local sharedBarPositions = {
	['BT4Bar5'] = 'BOTTOMRIGHT,SUI_Art_Midnight_Overlay,BOTTOMLEFT,-10,10',
	['BT4Bar6'] = 'BOTTOMLEFT,SUI_Art_Midnight_Overlay,BOTTOMRIGHT,9,10',
	--
	['BT4BarExtraActionBar'] = 'BOTTOM,SUI_BottomAnchor,TOP,0,130',
	['BT4BarZoneAbilityBar'] = 'BOTTOM,SUI_BottomAnchor,TOP,0,130',
	--
	['BT4BarStanceBar'] = 'TOP,SpartanUI,TOP,-301,0',
	['BT4BarPetBar'] = 'TOP,SpartanUI,TOP,-558,0',
	['MultiCastActionBarFrame'] = 'TOP,SpartanUI,TOP,-558,0',
	--
	['BT4BarMicroMenu'] = 'TOP,SpartanUI,TOP,324,0',
	['BT4BarBagBar'] = 'TOP,SpartanUI,TOP,595,0',
}

function module:GetBarPositions(variantId)
	local positions = SUI:CopyData(sharedBarPositions, {})
	local isTall = variantId and variantId:match('_tall$')

	if isTall then
		-- Stacked: 4 bars centered, one above the other
		positions['BT4Bar1'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,0,210'
		positions['BT4Bar2'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,0,150'
		positions['BT4Bar3'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,0,90'
		positions['BT4Bar4'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,0,30'
	else
		-- Wide: 2x2 grid layout
		positions['BT4Bar1'] = 'BOTTOMRIGHT,SUI_BottomAnchor,BOTTOM,-2,104'
		positions['BT4Bar2'] = 'BOTTOMRIGHT,SUI_BottomAnchor,BOTTOM,-2,47'
		positions['BT4Bar3'] = 'BOTTOMLEFT,SUI_BottomAnchor,BOTTOM,2,104'
		positions['BT4Bar4'] = 'BOTTOMLEFT,SUI_BottomAnchor,BOTTOM,2,47'
	end

	return positions
end

function module:UpdateBarBGPositions(variantId)
	local plate = module.plate
	if not plate then
		return
	end
	local isTall = variantId and variantId:match('_tall$')

	for i = 1, 4 do
		plate['BG' .. i]:ClearAllPoints()
	end

	if isTall then
		-- Stacked: 4 BGs centered, one above the other
		plate.BG1:SetPoint('BOTTOM', plate, 'BOTTOM', 0, 127)
		plate.BG2:SetPoint('BOTTOM', plate, 'BOTTOM', 0, 70)
		plate.BG3:SetPoint('BOTTOM', plate, 'BOTTOM', 0, 13)
		plate.BG4:SetPoint('BOTTOM', plate, 'BOTTOM', 0, -44)
	else
		-- Wide: 2x2 grid
		plate.BG1:SetPoint('BOTTOMRIGHT', plate, 'BOTTOM', -2, 70)
		plate.BG2:SetPoint('BOTTOMRIGHT', plate, 'BOTTOM', -2, 25)
		plate.BG3:SetPoint('BOTTOMLEFT', plate, 'BOTTOM', 2, 70)
		plate.BG4:SetPoint('BOTTOMLEFT', plate, 'BOTTOM', 2, 25)
	end
end

function module:UpdateBarLayout(variantId)
	if not SUI.Handlers or not SUI.Handlers.BarSystem then
		return
	end

	SUI.Handlers.BarSystem.BarPosition.BT4['Midnight'] = module:GetBarPositions(variantId)
	SUI.Handlers.BarSystem:Refresh()
	module:UpdateBarBGPositions(variantId)
end

---Build wizard options for Midnight theme - called by Artwork Options wizard page
---@param frame Frame The container frame to populate
---@param width number Available width
---@return number height Total height used
function module:BuildWizardOptions(frame, width)
	if not LibAT then
		return 0
	end

	local artwork = SUI:GetModule('Artwork', true)

	local defs = {
		sizeHeader = {
			type = 'header',
			name = 'Overlay Size',
			order = 1,
		},
		overlayWidth = {
			type = 'slider',
			name = 'Width',
			min = 200,
			max = 1750,
			step = 5,
			order = 2,
			get = function()
				local w = GetOverlayDimensions()
				return w
			end,
			set = function(_, val)
				SUI.ThemeRegistry:SetSetting('Midnight', 'overlayWidth', val)
				module:UpdateOverlay()
			end,
		},
		overlayHeight = {
			type = 'slider',
			name = 'Height',
			min = 120,
			max = 440,
			step = 5,
			order = 3,
			get = function()
				local _, h = GetOverlayDimensions()
				return h
			end,
			set = function(_, val)
				SUI.ThemeRegistry:SetSetting('Midnight', 'overlayHeight', val)
				module:UpdateOverlay()
			end,
		},
	}

	if artwork then
		defs.trayHeader = {
			type = 'header',
			name = 'Sliding Trays',
			order = 10,
		}
		defs.leftTrayEnable = {
			type = 'checkbox',
			name = 'Enable left tray',
			desc = 'Show the sliding tray on the left side of the action bar',
			order = 11,
			get = function()
				return artwork:GetTraySettings('left').enabled
			end,
			set = function(_, val)
				artwork:SetTraySettings('left', 'enabled', val)
				artwork:trayWatcherEvents()
			end,
		}
		defs.rightTrayEnable = {
			type = 'checkbox',
			name = 'Enable right tray',
			desc = 'Show the sliding tray on the right side of the action bar',
			order = 12,
			get = function()
				return artwork:GetTraySettings('right').enabled
			end,
			set = function(_, val)
				artwork:SetTraySettings('right', 'enabled', val)
				artwork:trayWatcherEvents()
			end,
		}
	end

	local _, h = LibAT.UI.BuildWidgets(frame, defs, width)
	frame:SetHeight(h)
	return h
end

function module:OnEnable()
	if SUI:GetActiveStyle() ~= 'Midnight' then
		module:Disable()
	else
		ArtworkOptions()
		if SUI.Artwork then
			module:SlidingTrays()
			if Midnight_ActionBarPlate then
				for i = 1, 6 do
					local overlay = SUI.Handlers.BarSystem:GetBarOverlay('BT4Bar' .. i)
					if overlay then
						Midnight_ActionBarPlate['BG' .. i]:SetAllPoints(overlay)
					end
				end
			end
		end
		if SUI:GetArtworkSetting('VehicleUI') then
			RegisterStateDriver(artFrame, 'visibility', '[overridebar][vehicleui] hide; show')
		else
			artFrame:Show()
		end
	end
end

function module:OnDisable()
	artFrame:Hide()
	UnregisterStateDriver(artFrame, 'visibility')
end

-- Artwork Stuff
function module:SlidingTrays()
	-- Determine faction-based color
	SUI.Artwork:SlidingTrays({
		defaultTrayColor = { r = 0.33, g = 0.16, b = 0.45, a = 1 },
	})

	-- Register frames that this skin places in trays
	SUI.Artwork:RegisterSkinTrayFrames('Midnight', {
		left = 'BT4BarPetBar,BT4BarStanceBar,MultiCastActionBarFrame',
		right = 'BT4BarMicroMenu,BT4BarBagBar',
	})

	local BarSystem = SUI.Handlers.BarSystem
	BarSystem:PositionBar('BT4BarPetBar', 'TOPLEFT', 'SlidingTray_left', 'TOPLEFT', 50, -2)
	BarSystem:PositionBar('BT4BarStanceBar', 'TOPRIGHT', 'SlidingTray_left', 'TOPRIGHT', -50, -2)
	BarSystem:PositionBar('BT4BarMicroMenu', 'TOPLEFT', 'SlidingTray_right', 'TOPLEFT', 50, -2)
	BarSystem:PositionBar('BT4BarBagBar', 'TOPRIGHT', 'SlidingTray_right', 'TOPRIGHT', -100, -2)
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
