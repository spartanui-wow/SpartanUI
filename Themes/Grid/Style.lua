local SUI = SUI
---@class SUI.Theme.Grid : SUI.Theme.StyleBase
local module = SUI:NewModule('Style.Grid')

function module:OnInitialize()
	SUI.ThemeRegistry:Register(
		-- Metadata (always in memory)
		{
			name = 'Grid',
			displayName = 'Grid',
			apiVersion = 1,
			description = 'Compact raid and party frame layout with corner indicators',
			setup = {
				image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Frames_Grid',
			},
			applicableTo = { raid = true, party = true },
		},
		-- Data callback (lazy-loaded on first access)
		function()
			return {
				frames = {
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
			}
		end
	)
end

function module:OnEnable() end

function module:OnDisable() end
