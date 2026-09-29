local SUI = SUI
---@class SUI.Theme.HealerGrid : SUI.Theme.StyleBase
local module = SUI:NewModule('Style.HealerGrid')

local BG = { 0.07, 0.07, 0.07, 0.9 }
local CELL_BG = { 0.25, 0.25, 0.25, 0.75 }

---Healing extras shared by party and raid cells
---@param elements table
---@param buffSize number
---@param debuffSize number
---@param defensiveSize number
local function HealerCell(elements, buffSize, debuffSize, defensiveSize)
	SUI.ThemeFlat.Auras(
		elements,
		{ number = 3, size = buffSize, anchor = 'BOTTOMRIGHT', relativePoint = 'BOTTOMRIGHT', growthx = 'LEFT', growthy = 'UP', y = 2, filter = 'healing_mode' },
		{ number = 3, size = debuffSize, anchor = 'BOTTOMLEFT', relativePoint = 'BOTTOMLEFT', growthx = 'RIGHT', growthy = 'UP', y = 2, filter = 'raid_debuffs' }
	)
	elements.Name.text = '[SUI_ColorClass][name]'
	elements.DefensiveIndicator = {
		enabled = true,
		size = defensiveSize,
		showSwipe = true,
		showDuration = true,
		position = { anchor = 'CENTER', x = 0, y = 0 },
	}
	elements.Dispel = { enabled = true, border = { enabled = true, size = 2, alpha = 0.9 } }
	elements.Range = { enabled = true, insideAlpha = 1, outsideAlpha = 0.4 }
	elements.GroupRoleIndicator = { enabled = true, size = 12, position = { anchor = 'TOPLEFT', x = 2, y = -2 } }
	elements.ThreatIndicator = { enabled = true }
	elements.ResurrectIndicator = { enabled = true }
	elements.SummonIndicator = { enabled = true }
	elements.PrivateAuras = { enabled = true }
end

function module:OnInitialize()
	local Flat = SUI.ThemeFlat

	SUI.ThemeRegistry:Register({
		name = 'HealerGrid',
		displayName = 'Healer Grid',
		apiVersion = 1,
		description = 'Big party and raid frames in the middle of the screen, sorted by role, with your heals, dispels and defensives easy to see.',
		setup = {
			image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_HealerGrid',
		},
		accent = { 0.32, 0.85, 0.48 },
		font = { face = 'Roboto Condensed Bold', preferred = 'Expressway' },
		applicableTo = { player = true, target = true, pet = true, focus = true, boss = true, arena = true, party = true, raid = true, raid10 = true, raid25 = true, raid40 = true },
	}, function()
		local frames = {}

		frames.player = Flat.Frame({ width = 200, health = 36, power = 5, cast = 12, bg = BG, name = 12 })
		Flat.Auras(frames.player.elements, nil, { number = 6, size = 24, anchor = 'BOTTOMLEFT', relativePoint = 'TOPLEFT', growthx = 'RIGHT', growthy = 'UP', y = 4 })
		frames.target = Flat.Frame({ width = 200, health = 36, power = 5, cast = 12, bg = BG, name = 12 })
		Flat.Auras(
			frames.target.elements,
			{ number = 6, size = 20, anchor = 'BOTTOMLEFT', relativePoint = 'TOPLEFT', growthx = 'RIGHT', growthy = 'UP', y = 4, filter = 'healing_mode' },
			{ number = 6, size = 24, anchor = 'TOPLEFT', relativePoint = 'BOTTOMLEFT', growthx = 'RIGHT', growthy = 'DOWN', y = -4, filter = 'player_debuffs' }
		)
		frames.targettarget = Flat.Frame({ width = 110, health = 22, power = 0, bg = BG, name = 10 })
		frames.targettarget.elements.Health.text = { ['1'] = { enabled = false }, ['2'] = { enabled = false } }
		frames.focus = Flat.Frame({ width = 150, health = 28, power = 4, cast = 12, bg = BG, name = 11 })
		frames.focustarget = Flat.Frame({ width = 100, health = 20, power = 0, bg = BG, name = 10 })
		frames.pet = Flat.Frame({ width = 110, health = 22, power = 4, bg = BG, name = 10 })
		frames.pettarget = Flat.Frame({ width = 100, health = 20, power = 0, bg = BG, name = 10 })
		frames.boss = Flat.Frame({ width = 170, health = 30, power = 4, cast = 12, bg = BG, name = 11 })
		frames.arena = Flat.Frame({ width = 170, health = 30, power = 4, cast = 12, bg = BG, name = 11 })

		-- Party: one row of five 125x64 cells
		frames.party = Flat.Group({ width = 125, health = 60, power = 4, perRow = 5, rows = 1, spacing = 2, growth = 'RIGHT_DOWN', bg = CELL_BG, nameSize = 11 })
		frames.party.mode = 'ASSIGNEDROLE'
		HealerCell(frames.party.elements, 24, 18, 30)

		-- Raids up to 25: 110x56 cells, five per row
		local mid = Flat.Group({ width = 110, health = 52, power = 4, perRow = 5, rows = 5, spacing = 2, growth = 'RIGHT_DOWN', bg = CELL_BG, nameSize = 11 })
		mid.mode = 'ASSIGNEDROLE'
		HealerCell(mid.elements, 20, 16, 26)
		frames.raid10 = SUI:CopyData({ enabled = true }, mid)
		frames.raid25 = SUI:CopyData({ enabled = true }, mid)

		-- Larger raids: 90x44 cells so 40 players still fit
		frames.raid40 = Flat.Group({ width = 90, health = 41, power = 3, perRow = 5, rows = 8, spacing = 2, growth = 'RIGHT_DOWN', bg = CELL_BG, nameSize = 10 })
		frames.raid40.mode = 'ASSIGNEDROLE'
		HealerCell(frames.raid40.elements, 16, 14, 22)

		local barPositions, barScales = Flat.BarLayout(4)
		-- The group frames own the middle, so the extra buttons sit under the player frame
		barPositions['BT4BarExtraActionBar'] = 'BOTTOMRIGHT,SUI_BottomAnchor,BOTTOM,-360,170'
		barPositions['BT4BarZoneAbilityBar'] = 'BOTTOMRIGHT,SUI_BottomAnchor,BOTTOM,-440,170'

		return {
			frames = frames,
			barPositions = barPositions,
			barScales = barScales,
			minimap = Flat.Minimap(190),
			unitframes = {
				displayName = 'Healer Grid',
				setup = {
					image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_HealerGrid',
				},
				positions = {
					['player'] = 'BOTTOMRIGHT,UIParent,BOTTOM,-340,250',
					['target'] = 'BOTTOMLEFT,UIParent,BOTTOM,340,250',
					['focus'] = 'BOTTOMLEFT,SUI_UF_target,TOPLEFT,0,40',
					['targettarget'] = 'TOPRIGHT,SUI_UF_target,BOTTOMRIGHT,0,-30',
					['pet'] = 'TOPLEFT,SUI_UF_player,BOTTOMLEFT,0,-30',
					['party'] = 'BOTTOM,UIParent,BOTTOM,0,170',
					['raid10'] = 'BOTTOM,UIParent,BOTTOM,0,170',
					['raid25'] = 'BOTTOM,UIParent,BOTTOM,0,170',
					['raid40'] = 'BOTTOM,UIParent,BOTTOM,0,170',
				},
			},
		}
	end)
end
