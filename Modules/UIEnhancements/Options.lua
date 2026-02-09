local SUI, L = SUI, SUI.L
---@class SUI.Module.UIEnhancements
local module = SUI:GetModule('UIEnhancements')
----------------------------------------------------------------------------------------------------

function module:BuildOptions()
	local DB = module:GetDB()

	---@type AceConfig.OptionsTable
	local OptionTable = {
		type = 'group',
		name = L['UI Enhancements'],
		childGroups = 'tab',
		disabled = function()
			return SUI:IsModuleDisabled(module)
		end,
		args = {
			general = {
				type = 'group',
				name = L['General'],
				order = 1,
				args = {
					decorMerchantBulkBuy = {
						name = L['Decoration merchant bulk buy'],
						desc = L['Shift+Right-click decoration merchant items to buy multiple at once'],
						type = 'toggle',
						order = 1,
						width = 'full',
						get = function()
							return DB.decorMerchantBulkBuy
						end,
						set = function(_, val)
							DB.decorMerchantBulkBuy = val
							module:ApplyDecorMerchantSettings()
						end,
					},
					lootAlertHeader = {
						type = 'header',
						name = L['Loot Alerts'],
						order = 10,
					},
					lootAlertPopup = {
						name = L['Loot alert popup'],
						desc = L['Show item level comparison and one-click equip on loot alerts'],
						type = 'toggle',
						order = 11,
						width = 'full',
						get = function()
							return DB.lootAlertPopup
						end,
						set = function(_, val)
							DB.lootAlertPopup = val
							module:ApplyLootAlertPopupSettings()
						end,
					},
					lootAlertChat = {
						name = L['Upgrade chat notification'],
						desc = L['Print a message to chat when an upgrade is looted'],
						type = 'toggle',
						order = 12,
						width = 'full',
						disabled = function()
							return not DB.lootAlertPopup
						end,
						get = function()
							return DB.lootAlertChat
						end,
						set = function(_, val)
							DB.lootAlertChat = val
						end,
					},
					lootAlertSound = {
						name = L['Upgrade sound notification'],
						desc = L['Play a sound when an upgrade is looted'],
						type = 'toggle',
						order = 13,
						width = 'full',
						disabled = function()
							return not DB.lootAlertPopup
						end,
						get = function()
							return DB.lootAlertSound
						end,
						set = function(_, val)
							DB.lootAlertSound = val
						end,
					},
					lootAlertSoundName = {
						name = L['Upgrade sound'],
						desc = L['Sound to play when an upgrade is looted'],
						type = 'select',
						dialogControl = 'LSM30_Sound',
						order = 14,
						width = 'double',
						disabled = function()
							return not DB.lootAlertPopup or not DB.lootAlertSound
						end,
						values = function()
							return SUI.Lib.LSM:HashTable('sound')
						end,
						get = function()
							return DB.lootAlertSoundName
						end,
						set = function(_, val)
							DB.lootAlertSoundName = val
						end,
					},
				},
			},
			mouseEffects = {
				type = 'group',
				name = L['Mouse Effects'],
				order = 2,
				args = {
					mouseRingHeader = {
						type = 'header',
						name = L['Mouse Ring'],
						order = 1,
					},
					mouseRingEnabled = {
						name = L['Enable Mouse Ring'],
						desc = L['Show a ring around your cursor'],
						type = 'toggle',
						order = 2,
						width = 'full',
						get = function()
							return DB.mouseRing.enabled
						end,
						set = function(_, val)
							DB.mouseRing.enabled = val
							module:ApplyMouseEffectSettings()
						end,
					},
					mouseRingCircleStyleLabel = {
						name = L['Circle Style'],
						type = 'description',
						order = 2.1,
						fontSize = 'medium',
						width = 'full',
					},
					-- Circle style image buttons are injected dynamically below
					mouseRingSize = {
						name = L['Ring Size'],
						desc = L['Size of the ring in pixels'],
						type = 'range',
						order = 3,
						min = 16,
						max = 64,
						step = 1,
						disabled = function()
							return not DB.mouseRing.enabled
						end,
						get = function()
							return DB.mouseRing.size
						end,
						set = function(_, val)
							DB.mouseRing.size = val
						end,
					},
					mouseRingAlpha = {
						name = L['Ring Opacity'],
						desc = L['Opacity of the ring'],
						type = 'range',
						order = 4,
						min = 0.1,
						max = 1.0,
						step = 0.1,
						disabled = function()
							return not DB.mouseRing.enabled
						end,
						get = function()
							return DB.mouseRing.alpha
						end,
						set = function(_, val)
							DB.mouseRing.alpha = val
						end,
					},
					mouseRingColorMode = {
						name = L['Color Mode'],
						desc = L['How to color the ring'],
						type = 'select',
						order = 5,
						disabled = function()
							return not DB.mouseRing.enabled
						end,
						values = {
							class = L['Class Color'],
							custom = L['Custom Color'],
						},
						get = function()
							return DB.mouseRing.color.mode
						end,
						set = function(_, val)
							DB.mouseRing.color.mode = val
						end,
					},
					mouseRingColor = {
						name = L['Custom Color'],
						desc = L['Custom ring color'],
						type = 'color',
						order = 6,
						disabled = function()
							return not DB.mouseRing.enabled or DB.mouseRing.color.mode ~= 'custom'
						end,
						get = function()
							return DB.mouseRing.color.r, DB.mouseRing.color.g, DB.mouseRing.color.b
						end,
						set = function(_, r, g, b)
							DB.mouseRing.color.r = r
							DB.mouseRing.color.g = g
							DB.mouseRing.color.b = b
						end,
					},
					mouseRingShowDot = {
						name = L['Show Center Dot'],
						desc = L['Show a small dot at the cursor center'],
						type = 'toggle',
						order = 7,
						disabled = function()
							return not DB.mouseRing.enabled
						end,
						get = function()
							return DB.mouseRing.showCenterDot
						end,
						set = function(_, val)
							DB.mouseRing.showCenterDot = val
						end,
					},
					mouseRingDotSize = {
						name = L['Center Dot Size'],
						desc = L['Size of the center dot in pixels'],
						type = 'range',
						order = 8,
						min = 2,
						max = 12,
						step = 1,
						disabled = function()
							return not DB.mouseRing.enabled or not DB.mouseRing.showCenterDot
						end,
						get = function()
							return DB.mouseRing.centerDotSize
						end,
						set = function(_, val)
							DB.mouseRing.centerDotSize = val
						end,
					},
					mouseRingCombatOnly = {
						name = L['Combat Only'],
						desc = L['Only show the ring while in combat'],
						type = 'toggle',
						order = 9,
						disabled = function()
							return not DB.mouseRing.enabled
						end,
						get = function()
							return DB.mouseRing.combatOnly
						end,
						set = function(_, val)
							DB.mouseRing.combatOnly = val
							module:ApplyMouseEffectSettings()
						end,
					},
					mouseRingGcdHeader = {
						type = 'header',
						name = L['GCD Indicator'],
						order = 10,
					},
					mouseRingGcdEnabled = {
						name = L['Enable GCD Swipe'],
						desc = L['Show a cooldown swipe on the ring during the global cooldown'],
						type = 'toggle',
						order = 11,
						width = 'full',
						disabled = function()
							return not DB.mouseRing.enabled
						end,
						get = function()
							return DB.mouseRing.gcdEnabled
						end,
						set = function(_, val)
							DB.mouseRing.gcdEnabled = val
							module:UpdateGCDCooldown()
						end,
					},
					mouseRingGcdAlpha = {
						name = L['GCD Swipe Opacity'],
						desc = L['Opacity of the GCD swipe overlay'],
						type = 'range',
						order = 12,
						min = 0.1,
						max = 1.0,
						step = 0.1,
						disabled = function()
							return not DB.mouseRing.enabled or not DB.mouseRing.gcdEnabled
						end,
						get = function()
							return DB.mouseRing.gcdAlpha
						end,
						set = function(_, val)
							DB.mouseRing.gcdAlpha = val
						end,
					},
					mouseRingGcdReverse = {
						name = L['Reverse Swipe'],
						desc = L['Swipe fills instead of emptying'],
						type = 'toggle',
						order = 13,
						disabled = function()
							return not DB.mouseRing.enabled or not DB.mouseRing.gcdEnabled
						end,
						get = function()
							return DB.mouseRing.gcdReverse
						end,
						set = function(_, val)
							DB.mouseRing.gcdReverse = val
						end,
					},
					mouseTrailHeader = {
						type = 'header',
						name = L['Mouse Trail'],
						order = 20,
					},
					mouseTrailEnabled = {
						name = L['Enable Mouse Trail'],
						desc = L['Show a fading trail behind your cursor'],
						type = 'toggle',
						order = 21,
						width = 'full',
						get = function()
							return DB.mouseTrail.enabled
						end,
						set = function(_, val)
							DB.mouseTrail.enabled = val
							module:ApplyMouseEffectSettings()
						end,
					},
					mouseTrailDensity = {
						name = L['Trail Density'],
						desc = L['How many trail elements to spawn'],
						type = 'select',
						order = 22,
						disabled = function()
							return not DB.mouseTrail.enabled
						end,
						values = {
							verylow = L['Very Low'],
							low = L['Low'],
							medium = L['Medium'],
							high = L['High'],
							veryhigh = L['Very High'],
						},
						sorting = { 'verylow', 'low', 'medium', 'high', 'veryhigh' },
						get = function()
							return DB.mouseTrail.density
						end,
						set = function(_, val)
							DB.mouseTrail.density = val
						end,
					},
					mouseTrailSize = {
						name = L['Element Size'],
						desc = L['Size of trail elements in pixels'],
						type = 'range',
						order = 23,
						min = 4,
						max = 16,
						step = 1,
						disabled = function()
							return not DB.mouseTrail.enabled
						end,
						get = function()
							return DB.mouseTrail.size
						end,
						set = function(_, val)
							DB.mouseTrail.size = val
						end,
					},
					mouseTrailAlpha = {
						name = L['Trail Opacity'],
						desc = L['Starting opacity of trail elements'],
						type = 'range',
						order = 24,
						min = 0.1,
						max = 1.0,
						step = 0.1,
						disabled = function()
							return not DB.mouseTrail.enabled
						end,
						get = function()
							return DB.mouseTrail.alpha
						end,
						set = function(_, val)
							DB.mouseTrail.alpha = val
						end,
					},
					mouseTrailColorMode = {
						name = L['Color Mode'],
						desc = L['How to color the trail'],
						type = 'select',
						order = 25,
						disabled = function()
							return not DB.mouseTrail.enabled
						end,
						values = {
							class = L['Class Color'],
							custom = L['Custom Color'],
						},
						get = function()
							return DB.mouseTrail.color.mode
						end,
						set = function(_, val)
							DB.mouseTrail.color.mode = val
						end,
					},
					mouseTrailColor = {
						name = L['Custom Color'],
						desc = L['Custom trail color'],
						type = 'color',
						order = 26,
						disabled = function()
							return not DB.mouseTrail.enabled or DB.mouseTrail.color.mode ~= 'custom'
						end,
						get = function()
							return DB.mouseTrail.color.r, DB.mouseTrail.color.g, DB.mouseTrail.color.b
						end,
						set = function(_, r, g, b)
							DB.mouseTrail.color.r = r
							DB.mouseTrail.color.g = g
							DB.mouseTrail.color.b = b
						end,
					},
					mouseTrailCombatOnly = {
						name = L['Combat Only'],
						desc = L['Only show the trail while in combat'],
						type = 'toggle',
						order = 27,
						disabled = function()
							return not DB.mouseTrail.enabled
						end,
						get = function()
							return DB.mouseTrail.combatOnly
						end,
						set = function(_, val)
							DB.mouseTrail.combatOnly = val
							module:ApplyMouseEffectSettings()
						end,
					},
				},
			},
		},
	}

	-- Inject clickable circle style image buttons into the mouseEffects args
	local styleArgs = OptionTable.args.mouseEffects.args
	local styleCount = module:GetCircleStyleCount()
	for i = 1, styleCount do
		styleArgs['mouseRingCircleStyle' .. i] = {
			name = function()
				local current = DB.mouseRing.circleStyle or 1
				if current == i then
					return '|cff00ff00Style ' .. i .. '|r'
				end
				return 'Style ' .. i
			end,
			type = 'execute',
			order = 2.1 + (i * 0.01),
			disabled = function()
				return not DB.mouseRing.enabled
			end,
			image = function()
				return module:GetCircleStyleImage(i)
			end,
			imageCoords = function()
				return module:GetCircleStyleImageCoords(i)
			end,
			func = function()
				DB.mouseRing.circleStyle = i
				module:UpdateCircleStyle()
			end,
		}
	end

	SUI.Options:AddOptions(OptionTable, 'UIEnhancements')
end
