local SUI = SUI
---@class SUI.Theme.ClassicDark : SUI.Theme.StyleBase
local module = SUI:NewModule('Style.ClassicDark')

local BG = { 0.04, 0.04, 0.04, 0.7 }
local TEXTURE = 'Smooth gradient'

function module:OnInitialize()
	local Flat = SUI.ThemeFlat

	SUI.ThemeRegistry:Register({
		name = 'ClassicDark',
		displayName = 'Classic Dark',
		apiVersion = 1,
		description = 'Dark see-through frames with soft bars. Your frames sit low in the middle, with room between them for your cooldowns.',
		setup = {
			image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_ClassicDark',
		},
		accent = { 0.95, 0.7, 0.26 },
		font = { face = 'Roboto Condensed Bold', preferred = 'Expressway' },
		applicableTo = { player = true, target = true, pet = true, focus = true, boss = true, arena = true, party = true, raid = true, raid10 = true, raid25 = true, raid40 = true },
	}, function()
		local frames = {}
		local function Frame(spec)
			spec.bg = spec.bg or BG
			spec.texture = TEXTURE
			spec.absorb = 'SpartanUI Stripes'
			return Flat.Frame(spec)
		end

		frames.player = Frame({ width = 220, health = 36, power = 8, cast = 16, name = 12 })
		Flat.Auras(frames.player.elements, nil, { number = 8, size = 28, anchor = 'BOTTOMLEFT', relativePoint = 'TOPLEFT', growthx = 'RIGHT', growthy = 'UP', y = 4 })

		frames.target = Frame({ width = 220, health = 36, power = 8, cast = 16, name = 12 })
		Flat.Auras(
			frames.target.elements,
			{ number = 16, size = 22, rows = 2, anchor = 'TOPLEFT', relativePoint = 'BOTTOMLEFT', growthx = 'RIGHT', growthy = 'DOWN', y = -4, filter = 'healing_mode' },
			{ number = 8, size = 28, anchor = 'BOTTOMLEFT', relativePoint = 'TOPLEFT', growthx = 'RIGHT', growthy = 'UP', y = 4, filter = 'player_debuffs' }
		)

		frames.targettarget = Frame({ width = 120, health = 28, power = 4, name = 10 })
		frames.targettarget.elements.Health.text = { ['1'] = { enabled = false }, ['2'] = { enabled = false } }
		frames.focus = Frame({ width = 150, health = 28, power = 4, cast = 12, name = 11 })
		Flat.Auras(frames.focus.elements, nil, { number = 4, size = 22, anchor = 'BOTTOMLEFT', relativePoint = 'TOPLEFT', growthx = 'RIGHT', growthy = 'UP', y = 4, filter = 'player_debuffs' })
		frames.focustarget = Frame({ width = 100, health = 20, power = 0, name = 10 })
		frames.pet = Frame({ width = 120, health = 24, power = 4, name = 10 })
		frames.pettarget = Frame({ width = 100, health = 20, power = 0, name = 10 })
		frames.boss = Frame({ width = 190, health = 32, power = 6, cast = 14, name = 11 })
		Flat.Auras(frames.boss.elements, nil, { number = 4, size = 28, anchor = 'RIGHT', relativePoint = 'LEFT', growthx = 'LEFT', growthy = 'DOWN', y = 0, filter = 'player_debuffs' })
		frames.arena = Frame({ width = 190, health = 32, power = 6, cast = 14, name = 11 })

		frames.party = Flat.Group({ width = 180, health = 34, power = 6, perRow = 5, rows = 1, spacing = 8, growth = 'DOWN_RIGHT', bg = BG, nameSize = 11, texture = TEXTURE })
		Flat.Auras(frames.party.elements, { number = 4, size = 18, anchor = 'LEFT', relativePoint = 'RIGHT', growthx = 'RIGHT', growthy = 'DOWN', y = 0, filter = 'healing_mode' }, {
			number = 3,
			size = 22,
			anchor = 'RIGHT',
			relativePoint = 'LEFT',
			growthx = 'LEFT',
			growthy = 'DOWN',
			y = 0,
			filter = 'raid_debuffs',
		})

		local raid = Flat.Group({ width = 80, health = 36, power = 3, perRow = 5, rows = 8, spacing = 2, growth = 'DOWN_RIGHT', bg = BG, nameSize = 10, texture = TEXTURE })
		Flat.Auras(raid.elements, nil, { number = 2, size = 16, anchor = 'BOTTOMRIGHT', relativePoint = 'BOTTOMRIGHT', growthx = 'LEFT', growthy = 'UP', y = 2, filter = 'raid_debuffs' })
		raid.elements.Range = { enabled = true, insideAlpha = 1, outsideAlpha = 0.4 }
		frames.raid10 = raid
		frames.raid25 = raid
		frames.raid40 = raid

		local barPositions, barScales = Flat.BarLayout(4)

		return {
			frames = frames,
			barPositions = barPositions,
			barScales = barScales,
			dataBars = Flat.DataBars(BG),
			minimap = Flat.Minimap(180),
			unitframes = {
				displayName = 'Classic Dark',
				setup = {
					image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_ClassicDark',
				},
				-- Focus, player, target and target of target in one line, with an empty strip in
				-- the middle for the cooldown display
				positions = {
					['player'] = 'BOTTOMRIGHT,UIParent,BOTTOM,-150,240',
					['target'] = 'BOTTOMLEFT,UIParent,BOTTOM,150,240',
					['focus'] = 'BOTTOMRIGHT,SUI_UF_player,BOTTOMLEFT,-24,0',
					['targettarget'] = 'BOTTOMLEFT,SUI_UF_target,BOTTOMRIGHT,24,0',
					['pet'] = 'TOPLEFT,SUI_UF_player,BOTTOMLEFT,0,-24',
					['party'] = 'BOTTOMLEFT,UIParent,BOTTOMLEFT,20,220',
					['raid10'] = 'BOTTOMLEFT,UIParent,BOTTOMLEFT,20,220',
					['raid25'] = 'BOTTOMLEFT,UIParent,BOTTOMLEFT,20,220',
					['raid40'] = 'BOTTOMLEFT,UIParent,BOTTOMLEFT,20,220',
				},
			},
		}
	end)
end
