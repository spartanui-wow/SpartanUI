local SUI = SUI
---@class SUI.Theme.Midnight : SUI.Theme.StyleBase
local module = SUI:NewModule('Style.Midnight')

function module:OnInitialize()
	SUI.ThemeRegistry:Register(
		-- Metadata (always in memory)
		{
			name = 'Midnight',
			displayName = 'Midnight',
			apiVersion = 1,
			description = 'Modern, clean interface with focus on readability and well-spaced aura icons',
			setup = {
				image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Frames_Classic',
			},
			applicableTo = { player = true, target = true, raid = true, party = true },
		},
		-- Data callback (lazy-loaded on first access)
		function()
			return {
				frames = {
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
			}
		end
	)
end

function module:OnEnable() end

function module:OnDisable() end
