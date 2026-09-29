local SUI = SUI
---@class SUI.Theme.ModernFlat : SUI.Theme.StyleBase
local module = SUI:NewModule('Style.ModernFlat')

local BG = { 0.07, 0.07, 0.07, 0.9 }

function module:OnInitialize()
	local Flat = SUI.ThemeFlat

	SUI.ThemeRegistry:Register({
		name = 'ModernFlat',
		displayName = 'Modern Flat',
		apiVersion = 1,
		description = 'Clean flat frames with no artwork. Class-colored health, thin borders, and every frame placed near the middle of the screen.',
		setup = {
			image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_ModernFlat',
		},
		accent = { 0.33, 0.78, 1 },
		font = { face = 'Roboto Condensed Bold', preferred = 'Expressway' },
		applicableTo = { player = true, target = true, pet = true, focus = true, boss = true, arena = true, party = true, raid = true, raid10 = true, raid25 = true, raid40 = true },
	}, function()
		local frames = {}

		frames.player = Flat.Frame({ width = 180, health = 46, power = 6, cast = 14, bg = BG, name = 12 })
		Flat.Auras(frames.player.elements, nil, { number = 8, size = 26, anchor = 'BOTTOMLEFT', relativePoint = 'TOPLEFT', growthx = 'RIGHT', growthy = 'UP', y = 4 })

		frames.target = Flat.Frame({ width = 180, health = 46, power = 6, cast = 14, bg = BG, name = 12 })
		Flat.Auras(
			frames.target.elements,
			{ number = 8, size = 22, anchor = 'BOTTOMLEFT', relativePoint = 'TOPLEFT', growthx = 'RIGHT', growthy = 'UP', y = 4, filter = 'healing_mode' },
			{ number = 8, size = 26, anchor = 'TOPLEFT', relativePoint = 'BOTTOMLEFT', growthx = 'RIGHT', growthy = 'DOWN', y = -4, filter = 'player_debuffs' }
		)

		frames.targettarget = Flat.Frame({ width = 110, health = 24, power = 0, bg = BG, name = 10 })
		frames.targettarget.elements.Health.text = { ['1'] = { enabled = false }, ['2'] = { enabled = false } }

		frames.focus = Flat.Frame({ width = 150, health = 30, power = 4, cast = 12, bg = BG, name = 11 })
		Flat.Auras(frames.focus.elements, nil, { number = 5, size = 22, anchor = 'BOTTOMLEFT', relativePoint = 'TOPLEFT', growthx = 'RIGHT', growthy = 'UP', y = 4, filter = 'player_debuffs' })
		frames.focustarget = Flat.Frame({ width = 100, health = 20, power = 0, bg = BG, name = 10 })

		frames.pet = Flat.Frame({ width = 110, health = 24, power = 4, bg = BG, name = 10 })
		frames.pettarget = Flat.Frame({ width = 100, health = 20, power = 0, bg = BG, name = 10 })

		frames.boss = Flat.Frame({ width = 180, health = 32, power = 4, cast = 12, bg = BG, name = 11 })
		Flat.Auras(frames.boss.elements, nil, { number = 4, size = 26, anchor = 'RIGHT', relativePoint = 'LEFT', growthx = 'LEFT', growthy = 'DOWN', y = 0, filter = 'player_debuffs' })
		frames.arena = Flat.Frame({ width = 180, health = 32, power = 4, cast = 12, bg = BG, name = 11 })

		frames.party = Flat.Group({ width = 150, health = 38, power = 4, perRow = 5, rows = 1, spacing = 4, growth = 'DOWN_RIGHT', bg = BG, nameSize = 11 })
		Flat.Auras(frames.party.elements, nil, { number = 3, size = 20, anchor = 'LEFT', relativePoint = 'RIGHT', growthx = 'RIGHT', growthy = 'DOWN', y = 0, filter = 'raid_debuffs' })

		-- Raid cells share their borders: no gap between neighbours
		local raid = Flat.Group({ width = 125, health = 56, power = 4, perRow = 5, rows = 8, spacing = 0, growth = 'RIGHT_DOWN', bg = BG, nameSize = 10 })
		Flat.Auras(raid.elements, nil, { number = 3, size = 16, anchor = 'BOTTOMLEFT', relativePoint = 'BOTTOMLEFT', growthx = 'RIGHT', growthy = 'UP', y = 2, filter = 'raid_debuffs' })
		frames.raid10 = raid
		frames.raid25 = raid
		frames.raid40 = raid

		local barPositions, barScales = Flat.BarLayout(4)

		return {
			frames = frames,
			barPositions = barPositions,
			barScales = barScales,
			dataBars = Flat.DataBars(BG),
			minimap = Flat.Minimap(190),
			unitframes = {
				displayName = 'Modern Flat',
				setup = {
					image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_ModernFlat',
				},
				positions = {
					['player'] = 'CENTER,UIParent,CENTER,-317,-193',
					['target'] = 'CENTER,UIParent,CENTER,317,-201',
					['focus'] = 'CENTER,UIParent,CENTER,0,-285',
					['targettarget'] = 'TOPRIGHT,SUI_UF_target,BOTTOMRIGHT,0,-40',
					['pet'] = 'TOPLEFT,SUI_UF_player,BOTTOMLEFT,0,-40',
					['party'] = 'TOPLEFT,UIParent,LEFT,20,160',
					['raid10'] = 'TOPLEFT,UIParent,LEFT,20,160',
					['raid25'] = 'TOPLEFT,UIParent,LEFT,20,160',
					['raid40'] = 'TOPLEFT,UIParent,LEFT,20,160',
				},
			},
		}
	end)
end
