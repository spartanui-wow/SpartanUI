---@class SUI : AceAddon, AceEvent-3.0, AceConsole-3.0, AceSerializer-3.0
---@field MoveIt MoveIt
---@field IsRetail boolean
---@field IsClassic boolean
---@field IsTBC boolean
---@field IsWrath boolean
---@field IsCata boolean
---@field IsMOP boolean
---@field IsAnyClassic boolean
---@field wowVersion string
local SUI = LibStub('AceAddon-3.0'):NewAddon('SpartanUI', 'AceEvent-3.0', 'AceConsole-3.0', 'AceSerializer-3.0')
SUI:SetDefaultModuleLibraries('AceEvent-3.0', 'AceTimer-3.0')
_G.SUI = SUI
local type, pairs, unpack = type, pairs, unpack
local _G = _G
SUI.L = LibStub('AceLocale-3.0'):GetLocale('SpartanUI', true) ---@type SUIL
SUI.Version = C_AddOns.GetAddOnMetadata('SpartanUI', 'Version') or 0
SUI.BuildNum = C_AddOns.GetAddOnMetadata('SpartanUI', 'X-Build') or 0
SUI.Bartender4Version = (C_AddOns.GetAddOnMetadata('Bartender4', 'Version') or 0)

-- Version detection using lookup table for better maintainability
local VERSION_INFO = {
	[WOW_PROJECT_MAINLINE or 1] = { flag = 'IsRetail', name = 'Retail' },
	[WOW_PROJECT_CLASSIC or 2] = { flag = 'IsClassic', name = 'Classic' },
	[WOW_PROJECT_BURNING_CRUSADE_CLASSIC or 5] = { flag = 'IsTBC', name = 'TBC' },
	[WOW_PROJECT_WRATH_CLASSIC or 11] = { flag = 'IsWrath', name = 'Wrath' },
	[WOW_PROJECT_CATACLYSM_CLASSIC or 14] = { flag = 'IsCata', name = 'Cata' },
	[WOW_PROJECT_MISTS_CLASSIC or 19] = { flag = 'IsMOP', name = 'MOP' },
}

-- Set all version flags to false initially, then set the current one to true
for _, info in pairs(VERSION_INFO) do
	SUI[info.flag] = false
end

local currentVersion = VERSION_INFO[WOW_PROJECT_ID] or VERSION_INFO[1]
SUI[currentVersion.flag] = true ---@type boolean
SUI.wowVersion = currentVersion.name
SUI.GitHash = '@project-abbreviated-hash@' -- The ZIP packager will replace this with the Git hash.
--@alpha@
SUI.releaseType = 'ALPHA ' .. SUI.BuildNum
--@end-alpha@
--@do-not-package@
SUI.releaseType = 'DEV Build'
SUI.Version = ''
--@end-do-not-package@

---------------  Font Compatibility Fix ---------------
-- TBC Classic 2.5.5+ has EditModeManagerFrame but uses Retail-only fonts
-- Create missing font objects to prevent errors when Blizzard's EditMode code runs
if not SUI.IsRetail then
	-- List of fonts that EditMode tries to use but don't exist in Classic
	local missingFonts = {
		'GameFontDisableMed2',
		'GameFontHighlightMed2',
		'GameFontNormalMed2',
	}

	-- Check what similar fonts we have available as fallbacks
	local fallbackFont = GameFontDisable or GameFontNormal

	for _, fontName in ipairs(missingFonts) do
		if not _G[fontName] and fallbackFont then
			-- Create the missing font as an alias to an existing similar font
			local newFont = CreateFont(fontName)
			if newFont and newFont.CopyFontObject then
				newFont:CopyFontObject(fallbackFont)
			end
		end
	end
end

---------------  Add Libraries ---------------

---@class SUI.Lib
---@field AceC AceConfig-3.0
---@field AceCD AceConfigDialog-3.0
---@field AceDB AceDB-3.0
---@field AceDBO AceDBOptions-3.0
---@field AceGUI AceGUI-3.0
---@field Compress LibCompress
---@field LibBase64 LibBase64-1.0
---@field LSM LibSharedMedia-3.0
---@field LEM LibEditMode
---@field LibQTip LibQTip-2.0
SUI.Lib = {}
SUI.Handlers = {}

---@param name string
---@param libaray table|function
---@param silent? boolean
SUI.AddLib = function(name, libaray, silent)
	if not name then
		return
	end

	-- in this case: `major` is the lib table and `minor` is the minor version
	if type(libaray) == 'table' then
		SUI.Lib[name] = libaray
	else -- in this case: `major` is the lib name and `minor` is the silent switch
		SUI.Lib[name] = LibStub(libaray, silent)
	end
end

SUI.AddLib('AceC', 'AceConfig-3.0')
SUI.AddLib('AceCD', 'AceConfigDialog-3.0')
SUI.AddLib('AceDB', 'AceDB-3.0')
SUI.AddLib('AceDBO', 'AceDBOptions-3.0')
SUI.AddLib('AceGUI', 'AceGUI-3.0')
SUI.AddLib('Compress', 'LibCompress')
SUI.AddLib('Base64', 'LibBase64-1.0-SUI')
SUI.AddLib('LSM', 'LibSharedMedia-3.0')
-- Retail-only libraries (EditMode is only complete on Retail)
if SUI.IsRetail then
	SUI.AddLib('EditModeOverride', 'LibEditModeOverride-1.0', true)
end
-- Retail-only libraries (loaded conditionally via TOC)
if SUI.IsRetail then
	SUI.AddLib('LibQTip', 'LibQTip-2.0', true)
end

---Safely reload the UI with instance+combat check
---@param showMessage? boolean Whether to show error message (default: true)
---@return boolean success Whether reload was initiated or would be allowed
function SUI:SafeReloadUI(showMessage)
	if showMessage == nil then
		showMessage = true
	end

	local inInstance = IsInInstance()
	local inCombat = InCombatLockdown()

	if inInstance and inCombat then
		if showMessage then
			SUI:Print('|cffff0000Cannot reload UI while in combat in an instance|r')
		end
		return false
	end

	ReloadUI()
	return true
end

SLASH_RELOADUI1 = '/rl' -- new slash command for reloading UI
SlashCmdList.RELOADUI = function()
	SUI:SafeReloadUI()
end

-- Add Statusbar textures
SUI.Lib.LSM:Register('statusbar', 'Brushed aluminum', [[Interface\AddOns\SpartanUI\images\statusbars\BrushedAluminum]])
SUI.Lib.LSM:Register('statusbar', 'Leaves', [[Interface\AddOns\SpartanUI\images\statusbars\Leaves]])
SUI.Lib.LSM:Register('statusbar', 'Lightning', [[Interface\AddOns\SpartanUI\images\statusbars\Lightning]])
SUI.Lib.LSM:Register('statusbar', 'Metal', [[Interface\AddOns\SpartanUI\images\statusbars\metal]])
SUI.Lib.LSM:Register('statusbar', 'Recessed stone', [[Interface\AddOns\SpartanUI\images\statusbars\RecessedStone]])
SUI.Lib.LSM:Register('statusbar', 'Smoke', [[Interface\AddOns\SpartanUI\images\statusbars\Smoke]])
SUI.Lib.LSM:Register('statusbar', 'Smooth gradient', [[Interface\AddOns\SpartanUI\images\statusbars\SmoothGradient]])
SUI.Lib.LSM:Register('statusbar', 'SpartanUI Default', [[Interface\AddOns\SpartanUI\images\statusbars\Smoothv2]])
SUI.Lib.LSM:Register('statusbar', 'Glass', [[Interface\AddOns\SpartanUI\images\statusbars\glass.tga]])
SUI.Lib.LSM:Register('statusbar', 'WGlass', [[Interface\AddOns\SpartanUI\images\statusbars\Wglass]])
SUI.Lib.LSM:Register('statusbar', 'Blank', [[Interface\AddOns\SpartanUI\images\blank]])
-- Blizzard's built-in textures for health prediction
SUI.Lib.LSM:Register('statusbar', 'Blizzard', [[Interface\TargetingFrame\UI-StatusBar]])
SUI.Lib.LSM:Register('statusbar', 'Blizzard Shield', [[Interface\RaidFrame\Shield-Fill]])
SUI.Lib.LSM:Register('statusbar', 'Blizzard Absorb', [[Interface\RaidFrame\Absorb-Fill]])

-- Add Background textures
SUI.Lib.LSM:Register('background', 'Smoke', [[Interface\AddOns\SpartanUI\images\backgrounds\smoke]])
SUI.Lib.LSM:Register('background', 'Dragonflight', [[Interface\AddOns\SpartanUI\images\backgrounds\Dragonflight]])
SUI.Lib.LSM:Register('background', 'None', [[Interface\AddOns\SpartanUI\images\blank]])

---------------  Options Init ---------------
---@type AceConfig.OptionsTable
SUI.opt = {
	name = string.format('|cffffffffSpartan|cffe21f1fUI|r %s %s %s', SUI.wowVersion, SUI.Version, SUI.releaseType or ''),
	type = 'group',
	childGroups = 'tree',
	args = {
		General = { name = SUI.L['General'], type = 'group', order = 0, args = {} },
		Artwork = { name = SUI.L['Artwork'], type = 'group', order = 1, args = {} },
	},
}
---------------  Database  ---------------
local scale = 0.88
if SUI.IsClassic then
	scale = 0.79
end

local DBdefault = {
	Version = '0',
	SetupDone = false,
	scale = scale,
	alpha = 1,
	ActionBars = {
		Allalpha = 100,
		Allenable = true,
		popup1 = { anim = true, alpha = 100, enable = true },
		popup2 = { anim = true, alpha = 100, enable = true },
		bar1 = { alpha = 100, enable = true },
		bar2 = { alpha = 100, enable = true },
		bar3 = { alpha = 100, enable = true },
		bar4 = { alpha = 100, enable = true },
		bar5 = { alpha = 100, enable = true },
		bar6 = { alpha = 100, enable = true },
	},
	DisabledModules = {},
	SetupWizard = {
		FirstLaunch = true,
	},
	Styles = {
		['**'] = {
			Frames = {},
			Artwork = {
				barBG = {
					['**'] = {
						enabled = true,
						alpha = 1,
					},
					['1'] = {},
					['2'] = {},
					['3'] = {},
					['4'] = {},
					['5'] = {},
					['6'] = {},
					['7'] = {},
					['8'] = {},
					['9'] = {},
					['10'] = {},
					Stance = {},
					MenuBar = {},
				},
			},
			Movers = {},
			BlizzMovers = {
				['VehicleSeatIndicator'] = 'RIGHT,SpartanUI,RIGHT,-10,-30',
				['DurabilityFrame'] = 'TOPRIGHT,SpartanUI,TOPRIGHT,-30,-100',
				['TalkingHead'] = 'TOP,SpartanUI,TOP,0,-18',
				['AltPowerBar'] = 'TOP,SpartanUI,TOP,0,-18',
				['WidgetPowerBarContainer'] = 'TOP,SpartanUI,TOP,0,-50',
				['ZoneAbility'] = 'BOTTOM,UIParent,BOTTOM,0,350',
				['ExtraActionBar'] = 'BOTTOM,UIParent,BOTTOM,0,350',
				['BossButton'] = 'BOTTOM,SpartanUI,BOTTOM,0,210',
				['AlertFrame'] = 'BOTTOM,SpartanUI,BOTTOM,0,215',
				['VehicleLeaveButton'] = 'BOTTOM,SpartanUI,BOTTOM,0,250',
				['FramerateFrame'] = 'BOTTOM,SpartanUI,BOTTOM,0,210',
				['EncounterBar'] = 'TOP,UIParent,TOP,0,-90',
				['TopCenterContainer'] = 'TOP,UIParent,TOP,0,-50',
				['ArchaeologyBar'] = 'TOP,UIParent,TOP,0,-50',
			},
			Color = {
				Art = false,
				PlayerFrames = false,
				PartyFrames = false,
				RaidFrames = false,
			},
		},
		Arcane = {
			Frames = {
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
			Color = {
				Art = {
					0.4784313725490196,
					0.9137254901960784,
					1,
					0.9,
				},
			},
			SlidingTrays = {
				left = {
					enabled = true,
					collapsed = false,
				},
				right = {
					enabled = true,
					collapsed = false,
				},
			},
		},
		ArcaneRed = {
			Frames = {
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
		},
		Classic = {
			Frames = {
				player = {
					width = 153,
					scale = 0.91,
					elements = {
						Buffs = {
							rows = 4,
							growthy = 'UP',
							position = {
								y = 8,
								relativeTo = 'Name',
								relativePoint = 'TOPLEFT',
								anchor = 'BOTTOMLEFT',
								x = -23,
							},
						},
						Debuffs = {
							rows = 4,
							growthy = 'UP',
							position = {
								y = 8,
								relativeTo = 'Name',
								anchor = 'BOTTOMRIGHT',
								relativePoint = 'TOPRIGHT',
							},
						},
						Castbar = {
							height = 15,
						},
						Health = {
							offset = 2,
							height = 16,
							text = {
								['2'] = {
									enabled = true,
									text = '[perhp]%',
									position = {
										anchor = 'LEFT',
										x = -35,
										y = 0,
									},
								},
							},
						},
						Power = {
							offset = 2,
							height = 14,
							text = {
								['2'] = {
									enabled = true,
									text = '[perpp]%',
									position = {
										anchor = 'LEFT',
										x = -35,
										y = 0,
									},
								},
							},
							position = {
								y = -3,
							},
						},
						Portrait = {
							position = 'right',
						},
						RestingIndicator = {
							position = {
								anchor = 'TOPRIGHT',
								x = 102,
								y = 10,
							},
						},
						ClassIcon = {
							size = 18,
							position = {
								anchor = 'TOPRIGHT',
								x = 20,
								y = 16,
							},
						},
						PvPIndicator = {
							position = {
								anchor = 'BOTTOMRIGHT',
								x = 80,
								y = 0,
							},
						},
						RaidRoleIndicator = {
							position = {
								anchor = 'BOTTOMRIGHT',
								x = 22,
								y = 0,
							},
						},
						SpartanArt = {
							full = {
								enabled = true,
								graphic = 'Classic',
							},
						},
						RareElite = {
							mode = 'dragon',
							alpha = 1,
						},
						CombatIndicator = {
							enabled = true,
							position = {
								anchor = 'TOPRIGHT',
								x = 102,
								y = 10,
							},
						},
					},
				},
				target = {
					width = 153,
					scale = 0.91,
					elements = {
						Buffs = {
							rows = 4,
							growthy = 'UP',
							position = {
								y = 8,
								relativeTo = 'Name',
								relativePoint = 'TOPLEFT',
								anchor = 'BOTTOMLEFT',
								x = -23,
							},
						},
						Debuffs = {
							rows = 4,
							growthy = 'UP',
							position = {
								y = 8,
								relativeTo = 'Name',
								anchor = 'BOTTOMRIGHT',
								relativePoint = 'TOPRIGHT',
							},
						},
						Health = {
							offset = 2,
							height = 16,
							text = {
								['2'] = {
									enabled = true,
									text = '[perhp]%',
									position = {
										anchor = 'RIGHT',
										x = 40,
									},
								},
							},
						},
						Power = {
							offset = 2,
							height = 16,
							text = {
								['2'] = {
									enabled = true,
									text = '[perpp]%',
									position = {
										anchor = 'RIGHT',
										x = 40,
									},
								},
							},
							position = {
								y = -3,
							},
						},
						Castbar = {
							height = 15,
						},
						ClassIcon = {
							size = 18,
							position = {
								anchor = 'TOPLEFT',
								x = -22,
								y = 16,
							},
						},
						PvPIndicator = {
							position = {
								anchor = 'BOTTOMLEFT',
								x = -80,
								y = 0,
							},
						},
						RaidRoleIndicator = {
							position = {
								anchor = 'BOTTOMLEFT',
								x = -22,
								y = 0,
							},
						},
						SpartanArt = {
							full = {
								enabled = true,
								graphic = 'Classic',
							},
						},
						RareElite = {
							mode = 'dragon',
							alpha = 1,
						},
					},
				},
				pet = {
					elements = {
						Buffs = {
							enabled = false,
							position = {
								y = 22,
							},
						},
						Debuffs = {
							rows = 4,
							growthy = 'UP',
							position = {
								y = 8,
								relativeTo = 'Name',
								anchor = 'BOTTOMRIGHT',
								relativePoint = 'TOPRIGHT',
							},
						},
						Health = {
							offset = 2,
							height = 16,
							text = {
								['2'] = {
									enabled = true,
									text = '[perhp]%',
									position = {
										anchor = 'LEFT',
										x = -35,
										y = 0,
									},
								},
							},
						},
						Power = {
							offset = 2,
							height = 14,
							text = {
								['2'] = {
									enabled = true,
									text = '[perpp]%',
									position = {
										anchor = 'LEFT',
										x = -35,
										y = 0,
									},
								},
							},
						},
						Castbar = {
							height = 15,
						},
						Name = {
							position = {
								y = 5,
							},
						},
						SpartanArt = {
							full = {
								enabled = true,
								graphic = 'Classic',
							},
						},
					},
				},
				targettarget = {
					elements = {
						Buffs = {
							enabled = false,
						},
						Debuffs = {
							enabled = false,
						},
						Health = {
							offset = 2,
							height = 14,
							text = {
								['2'] = {
									enabled = true,
									text = '[perhp]%',
									position = {
										anchor = 'RIGHT',
										x = 40,
									},
								},
							},
						},
						Power = {
							offset = 1,
							height = 14,
							text = {
								['2'] = {
									enabled = true,
									text = '[perpp]%',
									position = {
										anchor = 'RIGHT',
										x = 40,
									},
								},
							},
						},
						Castbar = {
							height = 14,
						},
						SpartanArt = {
							full = {
								enabled = true,
								graphic = 'Classic',
							},
						},
					},
				},
			},
			BlizzMovers = {
				['VehicleLeaveButton'] = 'BOTTOM,SpartanUI,BOTTOM,0,195',
			},
		},
		Transparent = {
			Frames = {
				player = {
					elements = {
						SpartanArt = {
							top = {
								enabled = true,
								graphic = 'Transparent',
							},
							bg = {
								enabled = true,
								graphic = 'Transparent',
							},
						},
						Portrait = {
							position = 'right',
						},
					},
				},
				target = {
					elements = {
						SpartanArt = {
							top = {
								enabled = true,
								graphic = 'Transparent',
							},
							bg = {
								enabled = true,
								graphic = 'Transparent',
							},
						},
					},
				},
			},
			Color = {
				Art = { 0, 0.8, 0.9, 0.7 },
				PlayerFrames = { 0, 0.8, 0.9, 0.7 },
				PartyFrames = { 0, 0.8, 0.9, 0.7 },
				RaidFrames = { 0, 0.8, 0.9, 0.7 },
			},
		},
		Minimal = {
			Color = {
				Art = {
					0.6156862745098039,
					0.1215686274509804,
					0.1215686274509804,
					0.9,
				},
			},
			HideCenterGraphic = false,
			HideBottomRight = false,
			HideBottomLeft = false,
			HideTopRight = false,
			HideTopLeft = false,
		},
		Fel = {
			Artwork = {},
			Frames = {
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
		},
		Digital = {
			Artwork = {},
			Frames = {
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
		},
		War = {
			Artwork = {},
			Frames = {
				player = {
					elements = {
						SpartanArt = {
							top = {
								enabled = true,
								graphic = 'War',
							},
							bg = {
								enabled = true,
								graphic = 'War',
							},
							bottom = {
								enabled = true,
								graphic = 'War',
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
						Buffs = {
							position = {
								relativeTo = 'Name',
								y = -15,
							},
						},
						Debuffs = {
							position = {
								relativeTo = 'Name',
								y = -15,
							},
						},
					},
				},
				target = {
					elements = {
						SpartanArt = {
							top = {
								enabled = true,
								graphic = 'War',
							},
							bg = {
								enabled = true,
								graphic = 'War',
							},
							bottom = {
								enabled = true,
								graphic = 'War',
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
						Buffs = {
							position = {
								relativeTo = 'Name',
								y = -5,
							},
						},
						Debuffs = {
							position = {
								relativeTo = 'Name',
								y = -5,
							},
						},
					},
				},
			},
			SlidingTrays = {
				left = {
					enabled = true,
					collapsed = false,
				},
				right = {
					enabled = true,
					collapsed = false,
				},
			},
		},
		Tribal = {
			Artwork = {},
			Frames = {
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
			SlidingTrays = {
				left = {
					enabled = true,
					collapsed = false,
				},
				right = {
					enabled = true,
					collapsed = false,
				},
			},
		},
		Grid = {
			Frames = {
				raid = {
					width = 72,
					maxColumns = 8,
					unitsPerColumn = 5,
					columnSpacing = 2,
					xOffset = 0,
					yOffset = -2,
					elements = {
						Health = {
							height = 28,
							text = {
								['1'] = {
									enabled = false,
								},
								['2'] = {
									enabled = true,
									text = '[SUIHealthDeficit]',
									size = 10,
									position = {
										anchor = 'CENTER',
										x = 0,
										y = -2,
									},
								},
							},
						},
						Power = {
							height = 2,
							text = {
								['1'] = {
									enabled = false,
								},
							},
						},
						Name = {
							textSize = 9,
							text = '[SUI_ColorClass][name]',
							height = 10,
						},
						Portrait = {
							enabled = false,
						},
						Castbar = {
							enabled = false,
						},
						SpartanArt = {
							enabled = false,
						},
						Buffs = {
							enabled = false,
						},
						Debuffs = {
							enabled = true,
							size = 10,
							number = 3,
							rows = 1,
						},
						CornerIndicators = {
							enabled = true,
						},
						Dispel = {
							enabled = true,
						},
						RaidDebuffs = {
							enabled = true,
							size = 22,
						},
						DefensiveIndicator = {
							enabled = true,
							size = 16,
							position = {
								anchor = 'BOTTOMRIGHT',
								x = -2,
								y = 2,
							},
						},
						GroupRoleIndicator = {
							enabled = true,
							size = 10,
							position = {
								anchor = 'TOPLEFT',
								x = 1,
								y = -1,
							},
						},
						ThreatIndicator = {
							enabled = true,
						},
						Range = {
							enabled = true,
						},
					},
				},
				party = {
					width = 90,
					elements = {
						Health = {
							height = 34,
							text = {
								['1'] = {
									enabled = false,
								},
								['2'] = {
									enabled = true,
									text = '[SUIHealthDeficit]',
									size = 11,
									position = {
										anchor = 'CENTER',
										x = 0,
										y = -2,
									},
								},
							},
						},
						Power = {
							height = 3,
							text = {
								['1'] = {
									enabled = false,
								},
							},
						},
						Name = {
							textSize = 10,
							text = '[SUI_ColorClass][name]',
						},
						Portrait = {
							enabled = false,
						},
						Castbar = {
							enabled = false,
						},
						SpartanArt = {
							enabled = false,
						},
						Buffs = {
							enabled = false,
						},
						Debuffs = {
							enabled = true,
							size = 12,
							number = 4,
							rows = 1,
						},
						CornerIndicators = {
							enabled = true,
						},
						Dispel = {
							enabled = true,
						},
						RaidDebuffs = {
							enabled = true,
							size = 26,
						},
						DefensiveIndicator = {
							enabled = true,
							size = 20,
							position = {
								anchor = 'BOTTOMRIGHT',
								x = -2,
								y = 2,
							},
						},
						GroupRoleIndicator = {
							enabled = true,
							size = 12,
							position = {
								anchor = 'TOPLEFT',
								x = 1,
								y = -1,
							},
						},
						ThreatIndicator = {
							enabled = true,
						},
						Range = {
							enabled = true,
						},
					},
				},
			},
		},
		Midnight = {
			Frames = {
				player = {
					elements = {
						Buffs = {
							enabled = true,
							number = 32,
							size = 28,
							rows = 4,
							spacing = 3,
							growthx = 'RIGHT',
							growthy = 'UP',
							position = {
								anchor = 'BOTTOMLEFT',
								relativePoint = 'TOPLEFT',
								x = 0,
								y = 5,
							},
							retail = {
								filterMode = 'all_buffs',
							},
						},
						Debuffs = {
							enabled = true,
							number = 16,
							size = 32,
							rows = 2,
							spacing = 3,
							growthx = 'RIGHT',
							growthy = 'DOWN',
							position = {
								anchor = 'TOPLEFT',
								relativePoint = 'BOTTOMLEFT',
								x = 0,
								y = -5,
							},
							retail = {
								filterMode = 'all_debuffs',
							},
						},
					},
				},
				target = {
					elements = {
						Buffs = {
							enabled = true,
							number = 16,
							size = 26,
							rows = 2,
							spacing = 3,
							growthx = 'LEFT',
							growthy = 'UP',
							position = {
								anchor = 'BOTTOMRIGHT',
								relativePoint = 'TOPRIGHT',
								x = 0,
								y = 5,
							},
							retail = {
								filterMode = 'healing_mode',
							},
						},
						Debuffs = {
							enabled = true,
							number = 16,
							size = 30,
							rows = 2,
							spacing = 3,
							growthx = 'LEFT',
							growthy = 'DOWN',
							position = {
								anchor = 'TOPRIGHT',
								relativePoint = 'BOTTOMRIGHT',
								x = 0,
								y = -5,
							},
							retail = {
								filterMode = 'player_debuffs',
							},
						},
					},
				},
				raid = {
					width = 95,
					maxColumns = 5,
					unitsPerColumn = 8,
					elements = {
						Buffs = {
							enabled = true,
							number = 3,
							size = 18,
							rows = 1,
							spacing = 2,
							growthx = 'RIGHT',
							growthy = 'UP',
							position = {
								anchor = 'BOTTOMLEFT',
								relativePoint = 'TOPLEFT',
								x = 2,
								y = 3,
							},
							retail = {
								filterMode = 'healing_mode',
							},
						},
						Debuffs = {
							enabled = true,
							number = 5,
							size = 22,
							rows = 1,
							spacing = 2,
							growthx = 'RIGHT',
							growthy = 'DOWN',
							position = {
								anchor = 'TOP',
								relativePoint = 'BOTTOM',
								x = 0,
								y = -3,
							},
							retail = {
								filterMode = 'raid_debuffs',
							},
						},
						Health = {
							height = 36,
						},
						Power = {
							height = 4,
						},
						Portrait = {
							enabled = false,
						},
						Castbar = {
							enabled = false,
						},
					},
				},
				party = {
					width = 110,
					elements = {
						Buffs = {
							enabled = true,
							number = 3,
							size = 18,
							rows = 1,
							spacing = 2,
							growthx = 'RIGHT',
							growthy = 'UP',
							position = {
								anchor = 'BOTTOMLEFT',
								relativePoint = 'TOPLEFT',
								x = 2,
								y = 3,
							},
							retail = {
								filterMode = 'healing_mode',
							},
						},
						Debuffs = {
							enabled = true,
							number = 5,
							size = 22,
							rows = 1,
							spacing = 2,
							growthx = 'RIGHT',
							growthy = 'DOWN',
							position = {
								anchor = 'TOP',
								relativePoint = 'BOTTOM',
								x = 0,
								y = -3,
							},
							retail = {
								filterMode = 'raid_debuffs',
							},
						},
						Health = {
							height = 42,
						},
						Power = {
							height = 5,
						},
						Portrait = {
							enabled = false,
						},
						Castbar = {
							enabled = false,
						},
					},
				},
			},
		},
	},
	Artwork = {
		Style = 'War',
		FirstLoad = true,
		SetupDone = false,
		VehicleUI = true,
		Viewport = {
			enabled = false,
			offset = { top = 0, bottom = 0, left = 0, right = 0 },
		},
		SlidingTrays = {
			['**'] = {
				collapsed = false,
			},
		},
		Trays = {
			['**'] = {
				left = {
					enabled = true,
					size = { width = 410, height = 45 },
					collapseDirection = 'up',
					customFrames = '',
					color = { r = 1, g = 1, b = 1, a = 1 },
				},
				right = {
					enabled = true,
					size = { width = 410, height = 45 },
					collapseDirection = 'up',
					customFrames = '',
					color = { r = 1, g = 1, b = 1, a = 1 },
				},
			},
		},
		Offset = {
			Top = 0,
			TopAuto = true,
			Bottom = 0,
			BottomAuto = true,
			Horizontal = {
				Bottom = 0,
				Top = 0,
			},
		},
		BlizzMoverStates = {
			['**'] = {
				enabled = true,
			},
		},
	},
}

SUI.DBdefault = DBdefault
local GlobalDefaults = {
	ChatLevelLog = {},
	ErrorHandler = {
		SUIErrorIcon = {},
	},
}

---@class SUIDBObject
local DBdefaults = { global = GlobalDefaults, profile = DBdefault }
---@class SUIDB : SUIDBObject, AceDBObject-3.0
---@field RegisterCallback function
SUI.SpartanUIDB = SUI.Lib.AceDB:New('SpartanUIDB', DBdefaults)
--If user has not played in a long time reset the database.
local ver = SUI.SpartanUIDB.profile.Version
if ver ~= '0' and ver < '6.0.0' then
	SUI.SpartanUIDB:ResetDB()
end

-- New SUI.DB Access
SUI.DBG = SUI.SpartanUIDB.global
SUI.DB = SUI.SpartanUIDB.profile

if SUI.DB.DisabledComponents then
	SUI:CopyData(SUI.DB.DisabledModules, SUI.DB.DisabledComponents)
	SUI.DB.DisabledComponents = nil
end

local function reloaduiWindow()
	local UI = LibAT.UI
	local popup = UI.CreateWindow({
		name = 'SUI_ReloadUI',
		title = '|cffffffffSpartan|cffe21f1fUI|r - Reload UI',
		width = 400,
		height = 100,
		hidePortrait = true,
	})
	popup.Inset:Hide()

	popup.Background = popup:CreateTexture(nil, 'BACKGROUND')
	popup.Background:SetAtlas('auctionhouse-background-index', true)
	popup.Background:SetPoint('TOPLEFT', popup, 'TOPLEFT', 5, -27)
	popup.Background:SetPoint('BOTTOMRIGHT', popup, 'BOTTOMRIGHT', -5, 27)

	popup:SetPoint('TOP', UIParent, 'TOP', 0, -20)
	popup:SetFrameStrata('DIALOG')

	-- Message
	local message = UI.CreateLabel(popup, 'A reload of your UI is required.', 'GameFontNormalLarge')
	message:SetPoint('CENTER', popup.Background, 'CENTER', 0, 0)

	-- Buttons
	UI.CreateActionButtons(popup, {
		{
			text = 'CLOSE',
			width = 80,
			onClick = function()
				popup:Hide()
			end,
		},
		{
			text = 'RELOAD UI',
			width = 180,
			onClick = function()
				SUI:SafeReloadUI()
			end,
		},
	}, 5, 5, 5)

	popup:Hide()
	SUI.reloaduiWindow = popup
end

function SUI:OnInitialize()
	if not SpartanUICharDB then
		SpartanUICharDB = {}
	end
	SUI.CharDB = SpartanUICharDB

	SUI.SpartanUIDB = SUI.Lib.AceDB:New('SpartanUIDB', DBdefaults)

	-- SUI.DB Access
	SUI.DBG = SUI.SpartanUIDB.global
	SUI.DB = SUI.SpartanUIDB.profile

	--Check for any SUI.DB changes
	if SUI.DB.SetupDone and (SUI.Version ~= SUI.DB.Version) and SUI.DB.Version ~= '0' then
		SUI:DBUpgrades()
	end

	if SUI.DB.SUIProper then
		SUI.print('---------------', true)
		SUI:Print('SpartanUI has detected an unsupported SUI5 profile is being used. Please reset your profile via /suihelp')
		SUI.print('---------------', true)
		---@type Frame | BackdropTemplate
		local SUI5Indicator = CreateFrame('Button', 'SUI5Profile', UIParent, BackdropTemplateMixin and 'BackdropTemplate')
		SUI5Indicator:SetFrameStrata('DIALOG')
		SUI5Indicator:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', 0, 0)
		SUI5Indicator:SetSize(20, 20)
		SUI5Indicator:SetBackdrop({
			bgFile = 'Interface\\AddOns\\SpartanUI\\images\\blank.tga',
			edgeFile = 'Interface\\AddOns\\SpartanUI\\images\\blank.tga',
			edgeSize = 1,
		})
		SUI5Indicator:SetBackdropColor(1, 0, 0, 0.5)
		SUI5Indicator:SetBackdropBorderColor(0.00, 0.00, 0.00, 1)
		SUI5Indicator:HookScript('OnEnter', function()
			SUI.print('---------------', true)
			SUI:Print('SpartanUI has detected an unsupported SUI5 profile is being used. Please reset your profile via /suihelp')
			SUI.print('---------------', true)
		end, 'LE_SCRIPT_BINDING_TYPE_EXTRINSIC')
	end

	-- Initialize Logger (always define helper functions, check at runtime)
	---@param message string The message to log
	---@param module string The module name
	---@param level? LogLevel Log level - defaults to 'info'
	function SUI.Log(message, module, level)
		if LibAT and LibAT.Log then
			-- Use LibAT.Log directly for hierarchical module names (contains dots)
			-- This allows the logger to parse the hierarchy properly
			LibAT.Log(message, 'SpartanUI.' .. module, level or 'info')
		end
	end

	---@param moduleObj SUI.Module The SpartanUI module object
	---@param message string The message to log
	---@param component? string Optional component for logging
	---@param level? LogLevel Log level - defaults to 'info'
	function SUI.ModuleLog(moduleObj, message, component, level)
		if LibAT and LibAT.Log then
			local moduleName = moduleObj.DisplayName or moduleObj:GetName()
			-- Build hierarchical name
			local fullName = 'SpartanUI.' .. moduleName
			if component then
				fullName = fullName .. '.' .. component
			end
			LibAT.Log(message, fullName, level or 'info')
		end
	end

	-- Register with LibAT Logger if available
	if LibAT and LibAT.Logger and LibAT.Logger.RegisterAddon then
		SUI.logger = LibAT.Logger.RegisterAddon('SpartanUI')
		if SUI.logger and SUI.logger.info then
			SUI.logger.info('SpartanUI ' .. SUI.Version .. ' initializing')
		end
	end

	-- Add Profiles to Options
	SUI.opt.args['Profiles'] = SUI.Lib.AceDBO:GetOptionsTable(SUI.SpartanUIDB)
	SUI.opt.args['Profiles'].order = 999

	-- Add dual-spec support
	local LibDualSpec = LibStub('LibDualSpec-1.0', true)
	if SUI.IsRetail and LibDualSpec then
		LibDualSpec:EnhanceDatabase(self.SpartanUIDB, 'SpartanUI')
		LibDualSpec:EnhanceOptions(SUI.opt.args['Profiles'], self.SpartanUIDB)
	end

	-- Spec Setup
	SUI.SpartanUIDB.RegisterCallback(SUI, 'OnNewProfile', 'InitializeProfile')
	SUI.SpartanUIDB.RegisterCallback(SUI, 'OnProfileChanged', 'UpdateModuleConfigs')
	SUI.SpartanUIDB.RegisterCallback(SUI, 'OnProfileCopied', 'UpdateModuleConfigs')
	SUI.SpartanUIDB.RegisterCallback(SUI, 'OnProfileReset', 'UpdateModuleConfigs')

	-- Setup ReloadUI Window
	reloaduiWindow()

	local ResetDBWarning = false
	local function resetdb()
		if ResetDBWarning then
			SUI.SpartanUIDB:ResetDB()
		else
			ResetDBWarning = true
			SUI:Print('|cffff0000Warning')
			SUI:Print(SUI.L['This will reset the SpartanUI Database. If you wish to continue perform the chat command again.'])
		end
	end

	local function resetfulldb()
		if ResetDBWarning then
			if Bartender4 then
				Bartender4.db:ResetDB()
			end
			SUI.SpartanUIDB:ResetDB()
		else
			ResetDBWarning = true
			SUI:Print('|cffff0000Warning')
			SUI:Print(SUI.L['This will reset the full SpartanUI & Bartender4 database. If you wish to continue perform the chat command again.'])
		end
	end

	local function resetbartender()
		SUI.opt.args['General'].args['Bartender'].args['ResetActionBars']:func()
	end

	local function Version()
		SUI:Print(SUI.L['Version'] .. ' ' .. C_AddOns.GetAddOnMetadata('SpartanUI', 'Version'))
		SUI:Print(string.format('%s build %s', SUI.wowVersion, SUI.BuildNum))
		if SUI.Bartender4Version ~= 0 then
			SUI:Print(SUI.L['Bartender4 version'] .. ' ' .. SUI.Bartender4Version)
		end
	end

	SUI:AddChatCommand('version', Version, 'Displays version information to the chat')
	SUI:AddChatCommand('resetdb', resetdb, 'Reset SpartanUI settings')
	SUI:AddChatCommand('resetbartender', resetbartender, 'Reset all bartender4 settings')
	SUI:AddChatCommand('resetfulldb', resetfulldb, 'Reset bartender4 & SpartanUI settings (This is similar to deleting your WTF folder but will only effect this character)')
	if _G.SUIErrorDisplay then
		local function ErrHandler(arg)
			if arg == 'reset' then
				_G.SUIErrorDisplay:Reset()
			else
				_G.SUIErrorDisplay:OpenErrorWindow()
			end
		end
		local desc = 'Display SUI Error handler'
		local args = {
			reset = 'Clear all saved errors',
		}
		SUI:AddChatCommand('error', ErrHandler, desc, args)
		SUI:AddChatCommand('errors', ErrHandler, desc, args)
	end
end

function SUI:DBUpgrades()
	if SUI.DB.Artwork.Style == '' and SUI.DB.Artwork.SetupDone then
		SUI.DB.Artwork.Style = 'Classic'
	end

	-- 6.3.0
	if SUI.DB.Offset then
		SUI:CopyData(SUI.DB.Artwork.Offset, SUI.DB.Offset)
		SUI.DB.Offset = nil
	end

	SUI.DB.Version = SUI.Version
end

function SUI:InitializeProfile()
	SUI.SpartanUIDB:RegisterDefaults(DBdefaults)

	SUI:reloadui()
end
-- chat setup --

function SUI.Print(self, ...)
	local tmp = {}
	local n = 1
	tmp[1] = '|cffffffffSpartan|cffe21f1fUI|r:'
	for i = 1, select('#', ...) do
		n = n + 1
		tmp[n] = tostring(select(i, ...))
	end
	DEFAULT_CHAT_FRAME:AddMessage(table.concat(tmp, ' ', 1, n))
end

function SUI.print(msg, doNotLabel)
	if doNotLabel then
		print(msg)
	else
		SUI:Print(msg)
	end
end

function SUI:Error(err, mod)
	if mod then
		SUI:Print("|cffff0000Error|c occured in the Module '" .. mod .. "'")
	else
		SUI:Print('|cffff0000Error occured')
	end
	SUI:Print('Details: ' .. (err or 'None provided'))
	SUI:Print('Please submit a bug at |cff3370FFhttp://bugs.spartanui.net/')
end

---@return boolean
function SUI:IsTimerunner()
	return PlayerGetTimerunningSeasonID and PlayerGetTimerunningSeasonID() ~= nil
end
---------  Create SpartanUI Container  ---------
do
	-- Create Plate
	local plate = CreateFrame('Frame', 'SpartanUI', UIParent)
	plate:SetFrameStrata('BACKGROUND')
	plate:SetFrameLevel(1)
	plate:SetPoint('BOTTOMLEFT')
	plate:SetPoint('TOPRIGHT')

	-- Create Bottom Anchor
	local BottomAnchor = CreateFrame('Frame', 'SUI_BottomAnchor', SpartanUI)
	BottomAnchor:SetFrameStrata('BACKGROUND')
	BottomAnchor:SetFrameLevel(1)
	BottomAnchor:SetPoint('BOTTOM')
	BottomAnchor:SetSize(1000, 140)

	-- Create Top Anchor
	local TopAnchor = CreateFrame('Frame', 'SUI_TopAnchor', SpartanUI)
	TopAnchor:SetFrameStrata('BACKGROUND')
	TopAnchor:SetFrameLevel(1)
	TopAnchor:SetPoint('TOP')
	TopAnchor:SetSize(1000, 5)

	plate.TopAnchor = TopAnchor
	plate.BottomAnchor = BottomAnchor
end

---------------  Math and Comparison  ---------------

--[[
	Takes a target table and injects data from the source
	override allows the source to be put into the target
	even if its already populated
]]
---@param target table
---@param source table
---@param override? boolean
---@return table
function SUI:MergeData(target, source, override)
	if source == nil then
		return target
	end

	if type(target) ~= 'table' then
		target = {}
	end
	for k, v in pairs(source) do
		if type(v) == 'table' then
			target[k] = self:MergeData(target[k], v, override)
		else
			if override then
				target[k] = v
			elseif target[k] == nil then
				target[k] = v
			end
		end
	end
	return target
end

---Copied from AceDB this allows tables to be copied and used as a in memory dynamic db using the '*' and '**' wildcards
---@param dest any the table that will be updated
---@param source any The data that will be used to populate the dest, unless the target info exsists in the dest then it will be left alone
---@return any will return the dest table, this is not needed as LUA updates the dest obj you passed but can be useful for easy re-assignment
function SUI:CopyData(dest, source)
	if source == nil then
		return dest
	end

	if type(dest) ~= 'table' then
		dest = {}
	end
	for k, v in pairs(source) do
		if k == '*' or k == '**' then
			if type(v) == 'table' then
				-- This is a metatable used for table defaults
				local mt = {
					-- This handles the lookup and creation of new subtables
					__index = function(t, k)
						if k == nil then
							return nil
						end
						local tbl = {}
						SUI:CopyData(tbl, v)
						rawset(t, k, tbl)
						return tbl
					end,
				}
				setmetatable(dest, mt)
				-- handle already existing tables in the SV
				for dk, dv in pairs(dest) do
					if not rawget(source, dk) and type(dv) == 'table' then
						SUI:CopyData(dv, v)
					end
				end
			else
				-- Values are not tables, so this is just a simple return
				local mt = {
					__index = function(t, k)
						return k ~= nil and v or nil
					end,
				}
				setmetatable(dest, mt)
			end
		elseif type(v) == 'table' then
			if not rawget(dest, k) then
				rawset(dest, k, {})
			end
			if type(dest[k]) == 'table' then
				SUI:CopyData(dest[k], v)
				if source['**'] then
					SUI:CopyData(dest[k], source['**'])
				end
			end
		else
			if rawget(dest, k) == nil then
				rawset(dest, k, v)
			end
		end
	end
	return dest
end

function SUI:isPartialMatch(frameName, tab)
	local result = false

	for _, v in ipairs(tab) do
		local startpos, _ = strfind(strlower(frameName), strlower(v))
		if startpos == 1 then
			result = true
		end
	end

	return result
end

---Takes a target table and searches for the specified phrase
---@param searchTable table
---@param searchPhrase string|number
---@param all? boolean
---@return boolean
function SUI:IsInTable(searchTable, searchPhrase, all)
	if searchTable == nil or searchPhrase == nil then
		SUI:Error('Invalid isInTable call', 'Core')
		return false
	end

	assert(type(searchTable) == 'table', "Invalid argument 'searchTable' in SUI:isInTable.")

	-- If All is specified then we are dealing with a 2 string table search both keys
	if all ~= nil then
		for k, v in ipairs(searchTable) do
			if v ~= nil and searchPhrase ~= nil then
				if strlower(v) == strlower(searchPhrase) then
					return true
				end
			end
			if k ~= nil and searchPhrase ~= nil then
				if strlower(k) == strlower(searchPhrase) then
					return true
				end
			end
		end
	else
		for _, v in ipairs(searchTable) do
			if v ~= nil and searchPhrase ~= nil then
				if strlower(v) == strlower(searchPhrase) then
					return true
				end
			end
		end
	end
	return false
end

---@param currentTable table
---@param defaultTable table
---@return table
function SUI:CopyTable(currentTable, defaultTable)
	if type(currentTable) ~= 'table' then
		currentTable = {}
	end

	if type(defaultTable) == 'table' then
		for option, value in pairs(defaultTable) do
			if type(value) == 'table' then
				value = self:CopyTable(currentTable[option], value)
			end

			currentTable[option] = value
		end
	end

	return currentTable
end

function SUI:CopyDefaults(dest, src)
	-- this happens if some value in the SV overwrites our default value with a non-table
	--if type(dest) ~= "table" then return end
	for k, v in pairs(src) do
		if k == '*' or k == '**' then
			if type(v) == 'table' then
				-- This is a metatable used for table defaults
				local mt = {
					-- This handles the lookup and creation of new subtables
					__index = function(t, k)
						if k == nil then
							return nil
						end
						local tbl = {}
						SUI:CopyDefaults(tbl, v)
						rawset(t, k, tbl)
						return tbl
					end,
				}
				setmetatable(dest, mt)
				-- handle already existing tables in the SV
				for dk, dv in pairs(dest) do
					if not rawget(src, dk) and type(dv) == 'table' then
						SUI:CopyDefaults(dv, v)
					end
				end
			else
				-- Values are not tables, so this is just a simple return
				local mt = {
					__index = function(t, k)
						return k ~= nil and v or nil
					end,
				}
				setmetatable(dest, mt)
			end
		elseif type(v) == 'table' then
			if not rawget(dest, k) then
				rawset(dest, k, {})
			end
			if type(dest[k]) == 'table' then
				SUI:CopyDefaults(dest[k], v)
				if src['**'] then
					SUI:CopyDefaults(dest[k], src['**'])
				end
			end
		else
			if rawget(dest, k) == nil then
				rawset(dest, k, v)
			end
		end
	end
end

function SUI:RemoveEmptySubTables(tbl)
	if type(tbl) ~= 'table' then
		print("Bad argument #1 to 'RemoveEmptySubTables' (table expected)")
		return
	end

	for k, v in pairs(tbl) do
		if type(v) == 'table' then
			if next(v) == nil then
				tbl[k] = nil
			else
				self:RemoveEmptySubTables(v)
			end
		end
	end
end

--Compare 2 tables and remove duplicate key/value pairs
--param cleanTable : table you want cleaned
--param checkTable : table you want to check against.
--return : a copy of cleanTable with duplicate key/value pairs removed
function SUI:RemoveTableDuplicates(cleanTable, checkTable, customVars)
	if type(cleanTable) ~= 'table' then
		print("Bad argument #1 to 'RemoveTableDuplicates' (table expected)")
		return {}
	end
	if type(checkTable) ~= 'table' then
		print("Bad argument #2 to 'RemoveTableDuplicates' (table expected)")
		return {}
	end

	local rtdCleaned = {}
	for option, value in pairs(cleanTable) do
		if not customVars or (customVars[option] or checkTable[option] ~= nil) then
			-- we only want to add settings which are existing in the default table, unless it's allowed by customVars
			if type(value) == 'table' and type(checkTable[option]) == 'table' then
				rtdCleaned[option] = self:RemoveTableDuplicates(value, checkTable[option], customVars)
			elseif cleanTable[option] ~= checkTable[option] then
				-- add unique data to our clean table
				rtdCleaned[option] = value
			end
		end
	end

	--Clean out empty sub-tables
	self:RemoveEmptySubTables(rtdCleaned)

	return rtdCleaned
end

--Compare 2 tables and remove blacklisted key/value pairs
--cleanTable - table you want cleaned
--blacklistTable - table you want to check against.
--return - a copy of cleanTable with blacklisted key/value pairs removed
function SUI:FilterTableFromBlacklist(cleanTable, blacklistTable)
	if type(cleanTable) ~= 'table' then
		print("Bad argument #1 to 'FilterTableFromBlacklist' (table expected)")
		return {}
	end
	if type(blacklistTable) ~= 'table' then
		print("Bad argument #2 to 'FilterTableFromBlacklist' (table expected)")
		return {}
	end

	local tfbCleaned = {}
	for option, value in pairs(cleanTable) do
		if type(value) == 'table' and blacklistTable[option] and type(blacklistTable[option]) == 'table' then
			tfbCleaned[option] = self:FilterTableFromBlacklist(value, blacklistTable[option])
		else
			-- Filter out blacklisted keys
			if blacklistTable[option] ~= true then
				tfbCleaned[option] = value
			end
		end
	end

	--Clean out empty sub-tables
	self:RemoveEmptySubTables(tfbCleaned)

	return tfbCleaned
end

---@param inTable table
---@return string
function SUI:TableToLuaString(inTable)
	local function recurse(table, level, ret)
		for i, v in pairs(table) do
			ret = ret .. strrep('    ', level) .. '['
			if type(i) == 'string' then
				ret = ret .. '"' .. i .. '"'
			else
				ret = ret .. i
			end
			ret = ret .. '] = '

			if type(v) == 'number' then
				ret = ret .. v .. ',\n'
			elseif type(v) == 'string' then
				ret = ret .. '"' .. v:gsub('\\', '\\\\'):gsub('\n', '\\n'):gsub('"', '\\"'):gsub('\124', '\124\124') .. '",\n'
			elseif type(v) == 'boolean' then
				if v then
					ret = ret .. 'true,\n'
				else
					ret = ret .. 'false,\n'
				end
			elseif type(v) == 'table' then
				ret = ret .. '{\n'
				ret = recurse(v, level + 1, ret)
				ret = ret .. strrep('    ', level) .. '},\n'
			else
				ret = ret .. '"' .. tostring(v) .. '",\n'
			end
		end

		return ret
	end
	if type(inTable) ~= 'table' then
		print('Invalid argument #1 to SUI:TableToLuaString (table expected)')
		return ''
	end

	local ret = '{\n'
	if inTable then
		ret = recurse(inTable, 1, ret)
	end
	ret = ret .. '}'

	return ret
end

function SUI:round(num, pos)
	if num then
		local mult = 10 ^ (pos or 2)
		return floor(num * mult + 0.5) / mult
		-- return floor((num * 10 ^ 2) + 0.5) / (10 ^ 2)
	end
end

---------------  Misc Backend  ---------------

function SUI:IsAddonEnabled(addon)
	return C_AddOns.GetAddOnEnableState(addon, UnitName('player')) == 2
end

function SUI:IsAddonDisabled(addon)
	return not self:IsAddonEnabled(addon)
end

function SUI:GetiLVL(itemLink)
	if not itemLink then
		return 0
	end

	local scanningTooltip = CreateFrame('GameTooltip', 'AutoTurnInTooltip', nil, 'GameTooltipTemplate')
	local itemLevelPattern = ITEM_LEVEL:gsub('%%d', '(%%d+)')
	local itemQuality = select(3, C_Item.GetItemInfo(itemLink))

	-- if a heirloom return a huge number so we dont replace it.
	if itemQuality == 7 then
		return math.huge
	end

	-- Scan the tooltip
	-- Setup the scanning tooltip
	-- Why do this here and not in OnEnable? If the player is not questing there is no need for this to exsist.
	scanningTooltip:SetOwner(UIParent, 'ANCHOR_NONE')

	-- If the item is not in the cache populate it.
	-- if not ilevel then
	-- Load tooltip
	scanningTooltip:SetHyperlink(itemLink)

	-- Find the iLVL inthe tooltip
	for i = 2, scanningTooltip:NumLines() do
		local line = _G['AutoTurnInTooltipTextLeft' .. i]
		if line:GetText():match(itemLevelPattern) then
			return tonumber(line:GetText():match(itemLevelPattern))
		end
	end
	return 0
end

function SUI:GoldFormattedValue(rawValue)
	local gold = math.floor(rawValue / 10000)
	local silver = math.floor((rawValue % 10000) / 100)
	local copper = (rawValue % 10000) % 100

	return format(GOLD_AMOUNT_TEXTURE .. ' ' .. SILVER_AMOUNT_TEXTURE .. ' ' .. COPPER_AMOUNT_TEXTURE, gold, 0, 0, silver, 0, 0, copper, 0, 0)
end

---Initialize a new/empty profile with required data structures
---@param profile table The profile to initialize
function SUI:InitializeProfile(profile)
	-- Artwork structure required by SetActiveStyle
	if not profile.Artwork then
		profile.Artwork = {
			Style = 'Classic',
			Viewport = {
				enabled = false,
				top = 0,
				bottom = 130,
				left = 0,
				right = 0,
			},
			SetupDone = false,
		}
	else
		if not profile.Artwork.Style then
			profile.Artwork.Style = 'Classic'
		end
		if not profile.Artwork.Viewport then
			profile.Artwork.Viewport = {
				enabled = false,
				top = 0,
				bottom = 130,
				left = 0,
				right = 0,
			}
		end
	end
end

function SUI:UpdateModuleConfigs()
	-- Update main DB references to point to new profile
	SUI.DB = SUI.SpartanUIDB.profile
	SUI.DBG = SUI.SpartanUIDB.global

	-- Initialize profile with required structures
	SUI:InitializeProfile(SUI.DB)

	-- Execute all module profile refresh callbacks SEQUENTIALLY
	-- This ensures all modules update their DB references before theme application
	if SUI.DBM.ExecuteProfileRefresh then
		SUI.DBM:ExecuteProfileRefresh()
	end

	-- NOW it's safe to apply the theme - all modules are refreshed
	local currentStyle = SUI.DB.Artwork.Style
	if currentStyle then
		SUI:SetActiveStyle(currentStyle)
	end
end

function SUI:reloadui()
	SUI.reloaduiWindow:Show()
end

function SUI:SplitString(str, delim)
	assert(type(delim) == 'string' and strlen(delim) > 0, 'bad delimiter')
	local splitTable = {}
	local start = 1

	-- find each instance of a string followed by the delimiter
	while true do
		local pos = strfind(str, delim, start, true)
		if not pos then
			break
		end

		tinsert(splitTable, strsub(str, start, pos - 1))
		start = pos + strlen(delim)
	end

	-- insert final one (after last delimiter)
	tinsert(splitTable, strsub(str, start))

	return unpack(splitTable)
end

function SUI:InverseAnchor(anchor)
	if anchor == 'TOPLEFT' then
		return 'BOTTOMLEFT'
	elseif anchor == 'TOPRIGHT' then
		return 'BOTTOMRIGHT'
	elseif anchor == 'BOTTOMLEFT' then
		return 'TOPLEFT'
	elseif anchor == 'BOTTOMRIGHT' then
		return 'TOPRIGHT'
	elseif anchor == 'BOTTOM' then
		return 'TOP'
	elseif anchor == 'TOP' then
		return 'BOTTOM'
	elseif anchor == 'LEFT' then
		return 'RIGHT'
	elseif anchor == 'RIGHT' then
		return 'LEFT'
	end
end

function SUI:OnEnable()
	local AceC = SUI.Lib.AceC
	local AceCD = SUI.Lib.AceCD

	AceC:RegisterOptionsTable('SpartanUIBliz', {
		name = 'SpartanUI',
		type = 'group',
		args = {
			n3 = {
				type = 'description',
				fontSize = 'medium',
				order = 3,
				width = 'full',
				name = SUI.L['Options can be accessed by the button below or by typing /sui'],
			},
			Close = {
				name = SUI.L['Launch Options'],
				width = 'full',
				type = 'execute',
				order = 50,
				func = function()
					while CloseWindows() do
					end
					AceCD:SetDefaultSize('SpartanUI', 850, 600)
					AceCD:Open('SpartanUI')
				end,
			},
		},
	})
	AceC:RegisterOptionsTable('SpartanUI', SUI.opt)

	AceCD:AddToBlizOptions('SpartanUIBliz', 'SpartanUI')
	AceCD:SetDefaultSize('SpartanUI', 1000, 700)

	SUI:RegisterChatCommand('sui', 'ChatCommand')
	SUI:RegisterChatCommand('suihelp', function()
		SUI.Lib.AceCD:Open('SpartanUI', 'Help')
	end)
	SUI:RegisterChatCommand('spartanui', 'ChatCommand')

	--Reopen options screen if flagged to do so after a reloadui
	SUI:RegisterEvent('PLAYER_ENTERING_WORLD', function()
		if SUI.DB.OpenOptions then
			SUI:ChatCommand()
			SUI.DB.OpenOptions = false
		end
	end)

	local GameMenuButtonsStore = {} --Table to hold data for buttons to be added to GameMenu

	tinsert(GameMenuButtonsStore, {
		text = '|cffffffffSpartan|cffe21f1fUI|r',
		callback = function()
			SUI.Options:ToggleOptions()
			if not InCombatLockdown() then
				HideUIPanel(GameMenuFrame)
			end
		end,
		isDisabled = false, --If set to true will make button disabled. Can be set as a fucn to return true/false dynamically if needed
		disabledText = 'This button is somehow disabled. Probably someone was messing around with the code.', --this text will show up in tooltip when the button is disabled
	})

	--hooking to blizz button add function for game menu, since the list of those is reset every time menu is opened
	if GameMenuFrame.AddButton then
		hooksecurefunc(GameMenuFrame, 'AddButton', function(text, callback, isDisabled)
			if text == MACROS then --check for text "Macros". That button is the last before logout in default so we insert our stuff in between
				for i, data in next, GameMenuButtonsStore do --Go through buttons in the tabe and adding them based on data provided
					if i == 1 then
						GameMenuFrame:AddSection() --spacer off first button
					end

					GameMenuFrame:AddButton(data.text, data.callback, data.isDisabled, data.disabledText)
				end
			end
		end)
	end
end

-- For Setting a unifid skin across all registered Skinable modules
function SUI:SetActiveStyle(skin)
	---@type SUI.Module.Artwork
	local artModule = SUI:GetModule('Artwork')
	artModule:SetActiveStyle(skin)

	for _, submodule in SUI:IterateModules() do
		if submodule.SetActiveStyle then
			submodule:SetActiveStyle(skin)
		end
	end

	-- Ensure this is the First and last thing to occur, iincase the art style has any StyleUpdate's needed after doing the other updates
	artModule:SetActiveStyle(skin)
end

SUI.noop = function() end
