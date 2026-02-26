local _G, SUI, L = _G, SUI, SUI.L
local UF = SUI.UF ---@class SUI.UF
----------------------------------------------------------------------------------------------------
-- Helper for spell info (uses unified C_Spell API available in all current versions)
local function GetSpellInfoCompat(spellInput)
	return C_Spell.GetSpellInfo(spellInput)
end

local anchorPoints = {
	['TOPLEFT'] = 'TOP LEFT',
	['TOP'] = 'TOP',
	['TOPRIGHT'] = 'TOP RIGHT',
	['RIGHT'] = 'RIGHT',
	['CENTER'] = 'CENTER',
	['LEFT'] = 'LEFT',
	['BOTTOMLEFT'] = 'BOTTOM LEFT',
	['BOTTOM'] = 'BOTTOM',
	['BOTTOMRIGHT'] = 'BOTTOM RIGHT',
}

---@param optTable AceConfig.OptionsTable
local function SUIHealth(optTable)
	local mode = 'Health'
	if optTable.name == 'SUIPower' then
		mode = 'Power'
	end

	local prefix = ''
	local suffix = ''
	local options = {
		displayDead = false,
		hideDead = false,
		hideZero = false,
		hideMax = false, -- WoW 12.0: Deprecated - cannot compare secrets
		short = false,
		percentage = false,
		dynamic = false,
		formatted = true,
		plain = false,
		comma = false,
		current = true,
		max = false,
		missing = false,
	}
	local tagText = 'current'
	local tagTextMode = 'formatted'

	optTable.type = 'group'
	optTable.inline = true
	optTable.order = 0.1
	optTable.args = {
		description = {
			name = 'This is a custom dynamic text tag that you can use to display information about the ' .. mode .. ' of the unit. You can use the following options to customize the text.',
			type = 'description',
			order = 0,
		},
		output = {
			name = optTable.name or '',
			type = 'input',
			order = 1,
			width = 'full',
			get = function(info)
				local opt = ''
				for k, v in pairs(options) do
					if v and k ~= 'formatted' and k ~= 'current' then
						if opt == '' then
							opt = opt .. k
						else
							opt = opt .. ',' .. k
						end
					end
				end

				--Setup the misc stuff
				if opt ~= '' then
					opt = '(' .. opt .. ')'
				end
				local finalPrefix = ''
				local finalSuffix = ''
				if prefix ~= '' then
					finalPrefix = prefix .. '$>'
				end
				if suffix ~= '' then
					finalSuffix = '<$' .. suffix
				end

				return '[' .. finalPrefix .. optTable.name .. finalSuffix .. opt .. ']'
			end,
		},
		prefix = {
			name = 'Prefix',
			type = 'input',
			order = 2,
			get = function(info)
				return prefix
			end,
			set = function(info, value)
				prefix = value
			end,
		},
		suffix = {
			name = 'Suffix',
			type = 'input',
			order = 3,
			get = function(info)
				return suffix
			end,
			set = function(info, value)
				suffix = value
			end,
		},
		tagText = {
			name = mode .. ' text to show',
			type = 'select',
			style = 'radio',
			order = 4,
			get = function(info)
				return tagText
			end,
			set = function(info, value)
				options.missing = false
				options.current = false
				options.max = false

				tagText = value
				options[value] = true
			end,
			values = {
				['missing'] = 'Missing ' .. mode,
				['current'] = 'Current ' .. mode,
				['max'] = 'Max ' .. mode,
			},
		},
		tagTextMode = {
			name = 'How to show selected text',
			desc = 'WoW 12.0 Formatting Options:\n- Plain: Raw value (e.g., "12345")\n- Comma: Comma-separated (e.g., "12,345")\n- Formatted: Same as Comma (legacy name)\n- Short: Abbreviated with K/M/B (e.g., "12K")\n- Dynamic: Same as Short (legacy name)\n- Percentage: Show as percentage (e.g., "75%")',
			type = 'select',
			style = 'radio',
			order = 5,
			get = function(info)
				return tagTextMode
			end,
			set = function(info, value)
				options.dynamic = false
				options.short = false
				options.percentage = false
				options.formatted = false
				options.plain = false
				options.comma = false

				tagTextMode = value
				options[value] = true
			end,
			values = {
				['plain'] = 'Plain (unformatted)',
				['comma'] = 'Comma-separated',
				['formatted'] = 'Formatted (legacy)',
				['short'] = 'Short (K/M/B)',
				['dynamic'] = 'Dynamic (legacy)',
				['percentage'] = 'Percentage',
			},
		},
		options = {
			type = 'group',
			name = 'Options',
			desc = 'Options for the tag, you may select as many as you like',
			order = 6,
			get = function(info)
				return options[info[#info]]
			end,
			set = function(info, value)
				options[info[#info]] = value
			end,
			args = {
				displayDead = {
					type = 'toggle',
					name = 'Display Dead',
					desc = "Display 'DEAD' when the unit is dead",
					order = 1,
				},
				hideDead = {
					type = 'toggle',
					name = 'Hide Dead',
					desc = 'Show nothing when the unit is dead',
					order = 2,
				},
				hideMax = {
					type = 'toggle',
					name = 'Hide Max (DEPRECATED)',
					desc = 'WoW 12.0: This option no longer works due to Secret Values system preventing comparison of secret health values. Option kept for backwards compatibility but has no effect.',
					disabled = true,
					order = 3,
				},
				hideZero = {
					type = 'toggle',
					name = 'Hide Zero',
					desc = 'Show nothing when the specified health data is at 0',
					order = 4,
				},
				line = {
					type = 'description',
					name = '',
					order = 5,
				},
			},
		},
	}
end

local TagList = {
	--Health
	['SUIHealth'] = { category = 'Health', description = 'SUIHealth', func = SUIHealth },
	['curhp'] = { category = 'Health', description = 'Displays the current HP without decimals' },
	['deficit:name'] = { category = 'Health', description = 'Displays the health as a deficit and the name at full health' },
	['perhp'] = {
		category = 'Health',
		description = 'Displays percentage HP without decimals or the % sign. You can display the percent sign by adjusting the tag to [perhp<$%].',
	},
	['maxhp'] = { category = 'Health', description = 'Displays max HP without decimals' },
	['missinghp'] = {
		category = 'Health',
		description = 'Displays the missing health of the unit in whole numbers, when not at full health',
	},
	--Power
	['SUIPower'] = { category = 'Power', description = 'SUIPower', func = SUIHealth },
	['perpp'] = { category = 'Power', description = "Displays the unit's percentage power without decimals " },
	['curpp'] = { category = 'Power', description = "Displays the unit's current power without decimals" },
	['maxpp'] = {
		category = 'Power',
		description = 'Displays the max amount of power of the unit in whole numbers without decimals',
	},
	['missingpp'] = {
		category = 'Power',
		description = 'Displays the missing power of the unit in whole numbers when not at full power',
	},
	--Mana
	['curmana'] = { category = 'Mana', description = 'Displays the current mana without decimals' },
	['maxmana'] = { category = 'Mana', description = 'Displays the max amount of mana the unit can have' },
	--Status
	['status'] = { category = 'Status', description = 'Displays zzz, dead, ghost, offline' },
	['afkdnd'] = { category = 'Status', description = 'Displays AFK or DND if the unit is afk or in Do not Disturb' },
	['dead'] = { category = 'Status', description = 'Displays <DEAD> if the unit is dead' },
	['offline'] = { category = 'Status', description = "Displays 'OFFLINE' if the unit is disconnected" },
	['resting'] = { category = 'Status', description = "Displays 'zzz' if the unit is resting" },
	--Classification
	['classification'] = {
		category = 'Classification',
		description = "Displays the unit's classification (e.g. 'ELITE' and 'RARE')",
	},
	['plus'] = {
		category = 'Classification',
		description = "Displays the character '+' if the unit is an elite or rare-elite",
	},
	['rare'] = { category = 'Classification', description = "Displays 'Rare' when the unit is a rare or rareelite" },
	['shortclassification'] = {
		category = 'Classification',
		description = "Displays the unit's classification in short form (e.g. '+' for ELITE and 'R' for RARE)",
	},
	--Classpower
	['cpoints'] = {
		category = 'Classpower',
		description = 'Displays amount of combo points the player has (only for player, shows nothing on 0)',
	},
	['arcanecharges'] = { category = 'Classpower', description = 'Displays the arcane charges (Mage)' },
	['chi'] = { category = 'Classpower', description = 'Displays the chi points (Monk)' },
	['holypower'] = { category = 'Classpower', description = 'Displays the holy power (Paladin)' },
	['runes'] = { category = 'Classpower', description = 'Displays the runes (Death Knight)' },
	['soulshards'] = { category = 'Classpower', description = 'Displays the soulshards (Warlock)' },
	--Colors
	['difficulty'] = {
		category = 'Colors',
		description = 'Changes color of the next tag based on how difficult the unit is compared to the players level',
	},
	['powercolor'] = { category = 'Colors', description = 'Colors the power text based upon its type' },
	['SUI_ColorClass'] = { category = 'Colors', description = 'Changes the text color based on the class' },
	--PvP
	['faction'] = { category = 'PvP', description = "Displays 'Alliance' or 'Horde'" },
	['pvp'] = { category = 'PvP', description = "Displays 'PvP' if the unit is pvp flagged" },
	['arenaspec'] = { category = 'PvP', description = 'Displays the area spec of an unit' },
	--Party and Raid
	['group'] = { category = 'Party and Raid', description = "Displays the group number the unit is in ('1' - '8')" },
	['leader'] = { category = 'Party and Raid', description = "Displays 'L' if the unit is the group/raid leader" },
	['leaderlong'] = { category = 'Party and Raid', description = "Displays 'Leader' if the unit is the group/raid leader" },
	--Level
	['level'] = { category = 'Level', description = 'Displays the level of the unit' },
	['smartlevel'] = { category = 'Level', description = "Only display the unit's level if it is not the same as yours" },
	--Names
	['name'] = { category = 'Names', description = 'Displays the full name of the unit without any letter limitation' },
	['affix'] = { category = 'Miscellaneous', description = 'Displays low level critter mobs' },
	['specialization'] = {
		category = 'Miscellaneous',
		description = 'Displays your current specialization as text',
	},
	['threat'] = {
		category = 'Threat',
		description = 'Displays the current threat situation (Aggro is secure tanking, -- is losing threat and ++ is gaining threat)',
	},
	['title'] = { category = 'Names', description = 'Displays player title' },
	['threatcolor'] = {
		category = 'Colors',
		description = "Changes the text color, depending on the unit's threat situation",
	},
}
local Options = {}
----------------------------------------------------------------------------------------------------

---Creates the base options screen for a frame name
---@param frameName UnitFrameName
---@return AceConfig.OptionsTable
function Options:CreateFrameOptionSet(frameName, get, set)
	local OptionSet = {
		name = frameName,
		type = 'group',
		childGroups = 'tab',
		disabled = function()
			return (UF.CurrentSettings[frameName] and not UF.CurrentSettings[frameName].enabled) or false
		end,
		get = get,
		set = set,
		args = {
			General = {
				name = L['General'],
				desc = L['General display settings'],
				type = 'group',
				order = 10,
				args = {},
			},
			StatusBar = {
				name = L['Bars'],
				type = 'group',
				order = 20,
				childGroups = 'tree',
				args = {},
			},
			Indicator = {
				name = L['Indicators'],
				type = 'group',
				order = 30,
				childGroups = 'tree',
				args = {},
			},
			-- Text = {
			-- 	name = L['Text'],
			-- 	type = 'group',
			-- 	order = 40,
			-- 	childGroups = 'tree',
			-- 	args = {
			-- 		execute = {
			-- 			name = L['Text tag list'],
			-- 			type = 'execute',
			-- 			func = function(info)
			-- 				SUI.Lib.AceCD:SelectGroup('SpartanUI', 'Help', 'UnitFrames')
			-- 			end
			-- 		}
			-- 	}
			-- },
			Auras = {
				name = L['Buffs & Debuffs'],
				desc = L['Buff & Debuff display settings'],
				type = 'group',
				childGroups = 'tree',
				order = 50,
				args = {
					-- Presets will be added here by AddAuraPresetsToFrame
				},
			},
		},
	} ---@type AceConfig.OptionsTable

	return OptionSet
end

---@param OptionSet AceConfig.OptionsTable
function Options:AddGeneral(OptionSet)
	OptionSet.args.General.args = {
		General = {
			name = '',
			type = 'group',
			order = 1,
			inline = true,
			args = {
				width = {
					name = L['Frame width'],
					type = 'range',
					width = 'full',
					order = 2,
					min = 1,
					max = 300,
					step = 0.1,
				},
			},
		},
	}
end

---Add frame background options using BackgroundBorder system
---@param frameName UnitFrameName
---@param OptionSet AceConfig.OptionsTable
function Options:AddFrameBackground(frameName, OptionSet)
	local BackgroundBorder = SUI.Handlers.BackgroundBorder
	if not BackgroundBorder then
		return
	end

	local function getSettings()
		return UF.CurrentSettings[frameName].frameBackground or BackgroundBorder.DefaultSettings
	end

	local function setSettings(newSettings)
		-- Update memory
		UF.CurrentSettings[frameName].frameBackground = newSettings
		-- Update the DB
		UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].frameBackground = newSettings
	end

	local function updateDisplay()
		-- Instance IDs use the WoW frame name (e.g. 'UnitFrame_SUI_UF_player',
		-- 'UnitFrame_SUI_UF_raid_Header1UnitButton1'), not the bare unit name.
		-- Use prefix search to find all instances for this frame type.
		local settings = getSettings()
		local instances = BackgroundBorder:GetInstancesByPrefix('UnitFrame_SUI_UF_' .. frameName)
		for _, instanceID in ipairs(instances) do
			BackgroundBorder:Update(instanceID, settings)
		end
	end

	-- Generate the complete options table
	local backgroundBorderOptions = BackgroundBorder:GenerateCompleteOptions('UnitFrame_' .. frameName, getSettings, setSettings, updateDisplay)
	backgroundBorderOptions.order = 50 -- Place it after the General group

	OptionSet.args.General.args.FrameBackground = backgroundBorderOptions
end

---Add position controls to the General tab of a per-frame options page.
---For child frames (partypet): X/Y offset + anchor point inputs stored in UF DB.
---For all other frames: embeds the MoveIt position+scale table (same controls as Movers page).
---@param frameName UnitFrameName
---@param FrameOptSet AceConfig.OptionsTable
function Options:AddPosition(frameName, FrameOptSet)
	local config = UF.Unit:GetBuiltFrameList()[frameName]

	if config and config.isChild then
		-- partypet: no MoveIt mover - expose position stored in UF DB

		-- Re-applies the stored position to all live pet child frames immediately
		local function applyPosition()
			local cs = UF.CurrentSettings[frameName]
			local posX = cs.positionX or 0
			local posY = cs.positionY or 1
			local posPoint = cs.positionPoint or 'BOTTOMRIGHT'
			local posRelPoint = cs.positionRelativePoint or 'BOTTOMLEFT'
			local holder = UF.Unit:Get(frameName)
			if holder and holder.frames and not InCombatLockdown() then
				for _, f in ipairs(holder.frames) do
					if f.childType == 'pet' then
						f:ClearAllPoints()
						f:SetPoint(posPoint, f:GetParent(), posRelPoint, posX, posY)
					end
				end
			end
		end

		local function saveField(key, val)
			UF.CurrentSettings[frameName][key] = val
			UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName][key] = val
		end

		FrameOptSet.args.General.args.Position = {
			name = L['Position'],
			type = 'group',
			order = 5,
			args = {
				MyAnchorPoint = {
					name = L['Point'],
					type = 'select',
					order = 1,
					values = anchorPoints,
					get = function()
						return UF.CurrentSettings[frameName].positionPoint or 'BOTTOMRIGHT'
					end,
					set = function(_, val)
						saveField('positionPoint', val)
						applyPosition()
					end,
				},
				ItsAnchorPoint = {
					name = L['Secondary point'],
					type = 'select',
					order = 2,
					values = anchorPoints,
					get = function()
						return UF.CurrentSettings[frameName].positionRelativePoint or 'BOTTOMLEFT'
					end,
					set = function(_, val)
						saveField('positionRelativePoint', val)
						applyPosition()
					end,
				},
				x = {
					name = L['X Offset'],
					type = 'input',
					dialogControl = 'NumberEditBox',
					order = 3,
					get = function()
						return tostring(UF.CurrentSettings[frameName].positionX or 0)
					end,
					set = function(_, val)
						saveField('positionX', tonumber(val) or 0)
						applyPosition()
					end,
				},
				y = {
					name = L['Y Offset'],
					type = 'input',
					dialogControl = 'NumberEditBox',
					order = 4,
					get = function()
						return tostring(UF.CurrentSettings[frameName].positionY or 1)
					end,
					set = function(_, val)
						saveField('positionY', tonumber(val) or 1)
						applyPosition()
					end,
				},
			},
		}
	else
		-- All other frames: embed MoveIt's position+scale controls
		local mover = SUI.MoveIt:GetMover(frameName)
		if mover then
			local optTable = SUI.MoveIt:GetPositionOptionsTable(frameName, L['Position'], mover)
			optTable.order = 5
			optTable.inline = false
			FrameOptSet.args.General.args.Position = optTable
		end
	end
end

---@param frameName UnitFrameName
---@param OptionSet AceConfig.OptionsTable
function Options:AddAuraLayout(frameName, OptionSet)
	OptionSet.args.Layout = {
		name = L['Layout Configuration'],
		type = 'group',
		order = 100,
		inline = true,
		args = {
			number = {
				name = L['Number to show'],
				type = 'range',
				order = 20,
				min = 1,
				max = 30,
				step = 1,
			},
			showType = {
				name = L['Show type'],
				type = 'toggle',
				order = 30,
			},
			selfScale = {
				order = 2,
				type = 'range',
				name = L['Scaled aura size'],
				desc = L['Scale for auras that you casted or can Spellsteal, any number above 100% is bigger than default, any number below 100% is smaller than default.'],
				min = 0,
				max = 3,
				step = 0.10,
				isPercent = true,
			},
			spacing = {
				name = L['Spacing'],
				type = 'range',
				order = 41,
				min = 1,
				max = 30,
				step = 1,
			},
			rows = {
				name = L['Rows'],
				type = 'range',
				order = 50,
				min = 1,
				max = 30,
				step = 1,
			},
			growthx = {
				name = L['Growth x'],
				type = 'select',
				order = 71,
				values = {
					['RIGHT'] = 'RIGHT',
					['LEFT'] = 'LEFT',
				},
			},
			growthy = {
				name = L['Growth y'],
				type = 'select',
				order = 72,
				values = {
					['UP'] = 'UP',
					['DOWN'] = 'DOWN',
				},
			},
		},
	}
end

---@param frameName UnitFrameName
---@param FrameOptSet AceConfig.OptionsTable
function Options:AddAuraPresets(frameName, FrameOptSet)
	-- Only add presets if the AuraPresets system is loaded
	if not UF.AuraPresets then
		return
	end

	-- Add presets group at the top of the Auras section
	FrameOptSet.args.Auras.args.Presets = {
		name = L['Quick Presets'],
		type = 'group',
		order = 0,
		args = {
			desc = {
				type = 'description',
				name = L['Apply a preset configuration optimized for your role. This will update both Buff and Debuff display settings for this frame.'],
				order = 0,
				fontSize = 'medium',
			},
			preset = {
				name = L['Apply Preset'],
				desc = L['Choose a preset to apply to this unit frame'],
				type = 'select',
				width = 'double',
				order = 1,
				values = function()
					return UF.AuraPresets:GetPresetList()
				end,
				get = function()
					local branch = SUI.IsRetail and 'retail' or 'classic'
					local buffsSettings = UF.CurrentSettings[frameName] and UF.CurrentSettings[frameName].elements.Buffs
					local debuffsSettings = UF.CurrentSettings[frameName] and UF.CurrentSettings[frameName].elements.Debuffs
					if not buffsSettings or not debuffsSettings then
						return 'custom'
					end

					local buffsMode = buffsSettings[branch] and buffsSettings[branch].filterMode
					local debuffsMode = debuffsSettings[branch] and debuffsSettings[branch].filterMode

					for key, preset in pairs(UF.AuraPresets.Presets) do
						local presetBuffs = preset.Buffs and preset.Buffs[branch] and preset.Buffs[branch].filterMode
						local presetDebuffs = preset.Debuffs and preset.Debuffs[branch] and preset.Debuffs[branch].filterMode
						if buffsMode == presetBuffs and debuffsMode == presetDebuffs then
							return key
						end
					end

					return 'custom'
				end,
				set = function(_, presetKey)
					if presetKey ~= 'custom' then
						UF.AuraPresets:ApplyPreset(frameName, presetKey)
						-- Refresh the options UI
						LibStub('AceConfigRegistry-3.0'):NotifyChange('SpartanUI')
					end
				end,
			},
			spacer = {
				type = 'description',
				name = '\n',
				order = 2,
			},
			presetInfo = {
				type = 'description',
				order = 3,
				fontSize = 'small',
				name = function()
					local branch = SUI.IsRetail and 'retail' or 'classic'
					local text = '|cffffffffAvailable Presets:|r\n'
					for key, preset in pairs(UF.AuraPresets.Presets) do
						local line = '|cff00ff00' .. preset.name .. ':|r ' .. preset.description
						if SUI.IsRetail then
							local buffsMode = preset.Buffs and preset.Buffs[branch] and preset.Buffs[branch].filterMode
							local debuffsMode = preset.Debuffs and preset.Debuffs[branch] and preset.Debuffs[branch].filterMode
							local buffsFilter = buffsMode and (UF.Auras.FILTER_PRESETS[buffsMode] or buffsMode) or '?'
							local debuffsFilter = debuffsMode and (UF.Auras.FILTER_PRESETS[debuffsMode] or debuffsMode) or '?'
							line = line .. '\n    Buffs: ' .. buffsFilter:gsub('|', '||') .. '  -  Debuffs: ' .. debuffsFilter:gsub('|', '||')
						end
						text = text .. '\n' .. line
					end
					return text
				end,
			},
		},
	}
end

---@param frameName UnitFrameName
---@param OptionSet AceConfig.OptionsTable
---@param create function
function Options:AddAuraWhitelistBlacklist(frameName, OptionSet, create)
	-- Whitelist/Blacklist only available in Classic due to WoW 12.0+ API restrictions
	if not SUI.IsRetail then
		OptionSet.args.whitelist = {
			name = L['Whitelist'],
			desc = L['Whitelisted auras will always be shown'],
			type = 'group',
			order = 4,
			args = {
				desc = {
					name = L['Whitelisted auras will always be shown'],
					type = 'description',
					order = 1,
				},
				create = {
					name = L['Add spell name or ID'],
					type = 'input',
					order = 2,
					width = 'full',
					set = create,
				},
				spells = {
					order = 3,
					type = 'group',
					inline = true,
					name = L['Auras list'],
					args = {},
				},
			},
		}
		OptionSet.args.blacklist = {
			name = L['Blacklist'],
			desc = L['Blacklisted auras will never be shown'],
			type = 'group',
			order = 5,
			args = {
				desc = {
					name = L['Blacklisted auras will never be shown'],
					type = 'description',
					order = 1,
				},
				create = {
					name = L['Add spell name or ID'],
					type = 'input',
					order = 2,
					width = 'full',
					set = create,
				},
				spells = {
					order = 3,
					type = 'group',
					inline = true,
					name = L['Auras list'],
					args = {},
				},
			},
		}
	end
end

---@param frameName UnitFrameName
---@param OptionSet AceConfig.OptionsTable
---@param set function
---@param get function
function Options:AddAuraFilters(frameName, OptionSet, set, get)
	if SUI.IsRetail then
		-- Retail: Filter mode is handled by the element's inline FilterMode radio group
		-- No Filters sub-tab needed on Retail
		return
	else
		-- CLASSIC: Full filtering with duration, whitelist/blacklist
		OptionSet.args.Filters = {
			name = L['Basic filters'],
			type = 'group',
			order = 1,
			get = get,
			set = set,
			args = {},
		}

		OptionSet.args.Filters.args.duration = {
			name = L['Duration'],
			type = 'group',
			order = 1,
			inline = true,
			args = {
				enabled = {
					name = L['Duration rules enabled'],
					type = 'toggle',
					order = 1,
				},
				mode = {
					name = L['Duration mode'],
					type = 'select',
					order = 2,
					values = {
						['exclude'] = 'Exclusionary',
						['include'] = 'Inclusionary',
					},
				},
				minTime = {
					name = L['Minimum Duration'],
					desc = L["Don't display auras that are shorter than this duration (in seconds). Set to zero to disable."],
					type = 'range',
					order = 2,
					min = 0,
					max = 600,
					step = 1,
				},
				maxTime = {
					name = L['Maximum Duration'],
					desc = L["Don't display auras that are longer than this duration (in seconds). Set to zero to disable."],
					type = 'range',
					order = 3,
					min = 0,
					max = 3600,
					step = 1,
				},
			},
		}

		OptionSet.args.Filters.args.rules = {
			name = L['Basic states'],
			type = 'multiselect',
			order = 3,
			values = {
				IsDispellableByMe = L['Dispellable by me'],
				isBossAura = L['Casted by boss'],
				isHarmful = L['Harmful'],
				isHelpful = L['Helpful'],
				isMount = L['Mount'],
				showPlayers = L['Player casted'],
				isRaid = L['Raid'],
				isStealable = L['Stealable'],
			},
		}
	end
end

---@param frameName UnitFrameName
---@param frameName UnitFrameName
---@param ElementOptSet AceConfig.OptionsTable
---@param elementName SUI.UF.Elements.list
function Options:TextBasicDisplay(frameName, ElementOptSet, elementName)
	ElementOptSet.args.Text = {
		name = '',
		type = 'group',
		inline = true,
		order = 10,
		args = {
			text = {
				name = L['Text'],
				type = 'input',
				width = 'full',
				order = 1,
			},
			taglist = {
				name = L['Text tag list'],
				type = 'execute',
				func = function(info)
					SUI.Lib.AceCD:SelectGroup('SpartanUI', 'Help', 'UnitFrames')
				end,
			},
			textSize = {
				name = L['Size'],
				type = 'range',
				width = 'full',
				min = 1,
				max = 30,
				step = 1,
				order = 1.5,
			},
			SetJustifyH = {
				name = L['Horizontal alignment'],
				type = 'select',
				order = 2,
				values = {
					['LEFT'] = 'Left',
					['CENTER'] = 'Center',
					['RIGHT'] = 'Right',
				},
			},
			SetJustifyV = {
				name = L['Vertical alignment'],
				type = 'select',
				order = 3,
				values = {
					['TOP'] = 'Top',
					['MIDDLE'] = 'Middle',
					['BOTTOM'] = 'Bottom',
				},
			},
		},
	}

	-- Add text color options if elementName is provided
	if elementName then
		ElementOptSet.args.TextColor = {
			name = L['Text Color'],
			type = 'group',
			inline = true,
			order = 11,
			get = function(info)
				local dbData = UF.CurrentSettings[frameName].elements[elementName].textColor[info[#info]]
				if info.type == 'color' then
					return unpack(dbData, 1, 4)
				else
					return dbData
				end
			end,
			set = function(info, val, ...)
				if info.type == 'color' then
					--Update memory
					UF.CurrentSettings[frameName].elements[elementName].textColor[info[#info]] = { val, ... }
					--Update the DB
					UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements[elementName].textColor[info[#info]] = { val, ... }
				else
					--Update memory
					UF.CurrentSettings[frameName].elements[elementName].textColor[info[#info]] = val
					--Update the DB
					UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements[elementName].textColor[info[#info]] = val
				end
				--Update the screen
				UF.Unit[frameName]:UpdateAll()
			end,
			args = {
				useCustomColor = {
					name = L['Use custom color'],
					desc = L['Override tag-based coloring with a custom color'],
					type = 'toggle',
					order = 1,
				},
				color = {
					name = L['Color'],
					type = 'color',
					order = 2,
					hasAlpha = false,
					disabled = function()
						return not UF.CurrentSettings[frameName].elements[elementName].textColor.useCustomColor
					end,
				},
			},
		}
	end
end

---@param frameName UnitFrameName
---@param ElementOptSet AceConfig.OptionsTable
---@param elementName SUI.UF.Elements.list
function Options:StatusBarDefaults(frameName, ElementOptSet, elementName)
	ElementOptSet.args.texture = {
		type = 'select',
		dialogControl = 'LSM30_Statusbar',
		order = 2,
		width = 'double',
		name = 'Bar Texture',
		values = AceGUIWidgetLSMlists.statusbar,
	}
	ElementOptSet.args.height = {
		name = L['Height'],
		type = 'range',
		width = 'double',
		order = 5,
		min = 2,
		max = 100,
		step = 1,
	}
	ElementOptSet.args.Background = {
		name = L['Background'],
		type = 'group',
		inline = true,
		order = 20,
		get = function(info)
			local dbData = UF.CurrentSettings[frameName].elements[elementName].bg[info[#info]]
			if info.type == 'color' then
				return unpack(dbData, 1, 4)
			else
				return dbData
			end
		end,
		set = function(info, val, ...)
			if info.type == 'color' then
				--Update memory
				UF.CurrentSettings[frameName].elements[elementName].bg[info[#info]] = { val, ... }
				--Update the DB
				UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements[elementName].bg[info[#info]] = { val, ... }
			else
				--Update memory
				UF.CurrentSettings[frameName].elements[elementName].bg[info[#info]] = val
				--Update the DB
				UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements[elementName].bg[info[#info]] = val
			end
			--Update the screen
			UF.Unit[frameName]:UpdateAll()
		end,
		args = {
			enabled = {
				name = L['Enable'],
				type = 'toggle',
				order = 1,
			},
			color = {
				name = L['Color'],
				type = 'color',
				order = 2,
				hasAlpha = true,
				hidden = function()
					return UF.CurrentSettings[frameName].elements[elementName].bg.useClassColor
				end,
			},
			useClassColor = {
				name = L['Use class color'],
				desc = L["Use the player's class color for the background"],
				type = 'toggle',
				order = 3,
			},
			classColorAlpha = {
				name = L['Class color alpha'],
				desc = L['Transparency level for the class colored background'],
				type = 'range',
				order = 4,
				min = 0,
				max = 1,
				step = 0.01,
				hidden = function()
					return not UF.CurrentSettings[frameName].elements[elementName].bg.useClassColor
				end,
				get = function()
					return UF.CurrentSettings[frameName].elements[elementName].bg.classColorAlpha or 0.2
				end,
				set = function(info, val)
					--Update memory
					UF.CurrentSettings[frameName].elements[elementName].bg.classColorAlpha = val
					--Update the DB
					UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements[elementName].bg.classColorAlpha = val
					--Update the screen
					UF.Unit[frameName]:UpdateAll()
				end,
			},
		},
	}
	-- Only add BarColors if the element has customColors support
	local elementSettings = UF.CurrentSettings[frameName].elements[elementName]
	if elementSettings.customColors then
		ElementOptSet.args.BarColors = {
			name = L['Bar Colors'],
			type = 'group',
			inline = true,
			order = 25,
			get = function(info)
				local dbData = elementSettings.customColors[info[#info]]
				if info.type == 'color' then
					return unpack(dbData, 1, 4)
				else
					return dbData
				end
			end,
			set = function(info, val, ...)
				if info.type == 'color' then
					--Update memory
					elementSettings.customColors[info[#info]] = { val, ... }
					--Update the DB
					UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements[elementName].customColors[info[#info]] = { val, ... }
				else
					--Update memory
					elementSettings.customColors[info[#info]] = val
					--Update the DB
					UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements[elementName].customColors[info[#info]] = val
				end
				--Update the screen
				UF.Unit[frameName]:UpdateAll()
			end,
			args = {
				useCustom = {
					name = L['Use custom colors'],
					desc = L['Override automatic coloring with custom colors'],
					type = 'toggle',
					order = 1,
				},
				barColor = {
					name = L['Bar color'],
					type = 'color',
					order = 2,
					hasAlpha = true,
					disabled = function()
						return not elementSettings.customColors.useCustom
					end,
				},
			},
		}
	end
end

---@param ElementOptSet AceConfig.OptionsTable
function Options:IndicatorAddDisplay(ElementOptSet)
	ElementOptSet.args.display = {
		name = L['Display'],
		type = 'group',
		order = 20,
		inline = true,
		args = {
			size = {
				name = L['Size'],
				type = 'range',
				min = 0,
				max = 100,
				step = 0.1,
				order = 1,
			},
			scale = {
				name = L['Scale'],
				type = 'range',
				min = 0.1,
				max = 3,
				step = 0.01,
				order = 2,
			},
			alpha = {
				name = L['Alpha'],
				type = 'range',
				min = 0,
				max = 1,
				step = 0.01,
				order = 3,
			},
		},
	}
end

---@param anchors table
---@param ElementOptSet AceConfig.OptionsTable
---@param get function
---@param set function
function Options:AddPositioning(anchors, ElementOptSet, get, set)
	local AnchorablePoints = {
		['Frame'] = 'Unit Frame',
	}
	SUI:CopyData(AnchorablePoints, anchors)

	ElementOptSet.args.position = {
		name = L['Position'],
		type = 'group',
		order = 50,
		inline = true,
		get = get,
		set = set,
		args = {
			x = {
				name = L['X Axis'],
				type = 'range',
				order = 1,
				min = -200,
				max = 200,
				step = 1,
			},
			y = {
				name = L['Y Axis'],
				type = 'range',
				order = 2,
				min = -200,
				max = 200,
				step = 1,
			},
			anchor = {
				name = L['Anchor point'],
				type = 'select',
				order = 3,
				values = anchorPoints,
			},
			relativeTo = {
				name = 'Relative To',
				type = 'select',
				order = 3,
				values = AnchorablePoints,
			},
			relativePoint = {
				name = 'Relative Point',
				type = 'select',
				order = 3,
				values = anchorPoints,
			},
		},
	}
end

---@param frameName UnitFrameName
---@param OptionSet AceConfig.OptionsTable
---@param element SUI.UF.Elements.list
function Options:AddDynamicText(frameName, OptionSet, element)
	OptionSet.args.Text = {
		name = L['Text'],
		type = 'group',
		order = 1,
		args = {
			execute = {
				name = L['Text tag list'],
				type = 'execute',
				order = 0.1,
				func = function(info)
					SUI.Lib.AceCD:SelectGroup('SpartanUI', 'Help', 'UnitFrames')
				end,
			},
		},
	}

	for count in pairs(UF.CurrentSettings[frameName].elements[element].text) do
		OptionSet.args.Text.args[count] = {
			name = L['Text element'] .. ' ' .. count,
			type = 'group',
			inline = true,
			order = (10 + count),
			get = function(info)
				return UF.CurrentSettings[frameName].elements[element].text[count][info[#info]]
			end,
			args = {
				enabled = {
					name = L['Enabled'],
					type = 'toggle',
					order = 1,
					set = function(info, val)
						--Update memory
						UF.CurrentSettings[frameName].elements[element].text[count].enabled = val
						--Update the DB
						UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements[element].text[count].enabled = val
						--Update the screen
						if val then
							-- Safety check: ensure unit frame and element exist
							if not UF.Unit[frameName] or not UF.Unit[frameName][element] then
								return
							end
							-- Ensure TextElements table exists
							if not UF.Unit[frameName][element].TextElements then
								UF.Unit[frameName][element].TextElements = {}
							end
							-- Check if TextElement exists, create if it doesn't
							if not UF.Unit[frameName][element].TextElements[count] then
								local textConfig = UF.CurrentSettings[frameName].elements[element].text[count]
								local elementFrame = UF.Unit[frameName][element]
								local NewString = elementFrame:CreateFontString(nil, 'OVERLAY')
								SUI.Font:Format(NewString, textConfig.size, 'UnitFrames')
								NewString:SetJustifyH(textConfig.SetJustifyH)
								NewString:SetJustifyV(textConfig.SetJustifyV)
								NewString:SetPoint(textConfig.position.anchor, elementFrame, textConfig.position.anchor, textConfig.position.x, textConfig.position.y)
								UF.Unit[frameName]:Tag(NewString, textConfig.text or '')
								UF.Unit[frameName][element].TextElements[count] = NewString
							end
							UF.Unit[frameName][element].TextElements[count]:Show()
						else
							-- Safety check: ensure unit frame and element exist
							if UF.Unit[frameName] and UF.Unit[frameName][element] and UF.Unit[frameName][element].TextElements and UF.Unit[frameName][element].TextElements[count] then
								UF.Unit[frameName][element].TextElements[count]:Hide()
							end
						end
					end,
				},
				text = {
					name = L['Text'],
					type = 'input',
					width = 'full',
					order = 2,
					set = function(info, val)
						--Update memory
						UF.CurrentSettings[frameName].elements[element].text[count].text = val
						--Update the DB
						UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements[element].text[count].text = val
						--Update the screen
						if UF.Unit[frameName][element] then
							UF.Unit[frameName]:Tag(UF.Unit[frameName][element].TextElements[count], val)
							UF.Unit[frameName]:UpdateTags()
						end
					end,
				},
				size = {
					name = L['Size'],
					type = 'range',
					width = 'full',
					min = 1,
					max = 30,
					step = 1,
					order = 1.5,
					set = function(info, val)
						--Update memory
						UF.CurrentSettings[frameName].elements[element].text[count].size = val
						--Update the DB
						UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements[element].text[count].size = val
						--Update the screen
						SUI.Font:UpdateDefaultSize(UF.Unit[frameName][element].TextElements[count], val, 'UnitFrames')
					end,
				},
				position = {
					name = L['Position'],
					type = 'group',
					order = 50,
					inline = true,
					get = function(info)
						return UF.CurrentSettings[frameName].elements[element].text[count].position[info[#info]]
					end,
					set = function(info, val)
						--Update memory
						UF.CurrentSettings[frameName].elements[element].text[count].position[info[#info]] = val
						--Update the DB
						local userText = UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements[element].text[count]
						if not userText.position then
							userText.position = {}
						end
						userText.position[info[#info]] = val
						--Update the screen
						local position = UF.CurrentSettings[frameName].elements[element].text[count].position
						UF.Unit[frameName][element].TextElements[count]:ClearAllPoints()
						UF.Unit[frameName][element].TextElements[count]:SetPoint(position.anchor, UF.Unit[frameName][element], position.anchor, position.x, position.y)
					end,
					args = {
						x = {
							name = L['X Axis'],
							type = 'range',
							order = 1,
							min = -200,
							max = 200,
							step = 1,
						},
						y = {
							name = L['Y Axis'],
							type = 'range',
							order = 2,
							min = -200,
							max = 200,
							step = 1,
						},
						anchor = {
							name = L['Anchor point'],
							type = 'select',
							order = 3,
							values = anchorPoints,
						},
					},
				},
			},
		}
	end
end

---@param frameName UnitFrameName
---@param OptionSet AceConfig.OptionsTable
function Options:AddGroupDisplay(frameName, OptionSet)
	OptionSet.args.General.args.Display = {
		name = L['Display'],
		type = 'group',
		order = 0.1,
		set = function(info, val)
			local setting = info[#info]
			--Update memory
			UF.CurrentSettings[frameName][setting] = val
			--Update the DB
			UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName][setting] = val
			--Update the screen
			-- Don't forward showRaid to the oUF header: oUF uses that attribute to switch
			-- spawned frames to raid* unit tokens, which breaks party frames (no raidpet/raidtarget configs).
			-- Party frame visibility in raids is handled by VisibilityCheck/GroupWatcher instead.
			if setting ~= 'showRaid' or frameName == 'raid' then
				UF.Unit:Get(frameName).header:SetAttribute(setting, val)
			end
			UF.Unit:Get(frameName):UpdateAll()
		end,
		args = {
			showRaid = {
				name = L['Show while in raid'],
				type = 'toggle',
				order = 1,
			},
			showParty = {
				name = L['Show while in party'],
				type = 'toggle',
				order = 2,
			},
			showPlayer = {
				name = L['Show player'],
				type = 'toggle',
				order = 2,
			},
			showSolo = {
				name = L['Show solo'],
				type = 'toggle',
				order = 2,
			},
		},
	}
end

---@param frameName UnitFrameName
---@param OptionSet AceConfig.OptionsTable
function Options:AddGroupLayout(frameName, OptionSet)
	OptionSet.args.General.args.Layout = {
		name = L['Layout Configuration'],
		type = 'group',
		order = 0.2,
		set = function(info, val)
			local setting = info[#info]
			--Update memory
			UF.CurrentSettings[frameName][setting] = val
			--Update the DB
			UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName][setting] = val
			--Update the screen
			UF.Unit:Get(frameName):SetAttribute(setting, val)
		end,
		args = {
			maxColumns = {
				name = L['Max Columns'],
				type = 'range',
				order = 1,
				width = 'full',
				step = 1,
				min = 1,
				max = 40,
			},
			unitsPerColumn = {
				name = L['Units Per Column'],
				type = 'range',
				order = 2,
				width = 'full',
				step = 1,
				min = 1,
				max = 40,
			},
			columnSpacing = {
				name = L['Column Spacing'],
				type = 'range',
				order = 3,
				width = 'full',
				step = 1,
				min = -200,
				max = 200,
			},
			bar1 = { name = 'Offsets', type = 'header', order = 20 },
			yOffset = {
				name = L['Vertical offset'],
				type = 'range',
				order = 21,
				width = 'full',
				step = 1,
				min = -200,
				max = 200,
			},
			xOffset = {
				name = L['Horizonal offset'],
				type = 'range',
				order = 22,
				width = 'full',
				step = 1,
				min = -200,
				max = 200,
			},
		},
	}
end

function Options:Initialize()
	---Build Help screen

	---@type AceConfig.OptionsTable
	local HelpScreen = {
		name = L['Text tags'],
		type = 'group',
		childGroups = 'tab',
		args = {
			Health = {
				name = L['Health'],
				type = 'group',
				order = 0.1,
				args = {},
			},
			Power = {
				name = L['Power'],
				type = 'group',
				order = 0.2,
				args = {},
			},
			Names = {
				name = 'Names',
				type = 'group',
				order = 0.3,
				args = {},
			},
		},
	}
	for k, v in pairs(TagList) do
		if v.category and not HelpScreen.args[v.category] then
			HelpScreen.args[v.category] = {
				name = v.category,
				type = 'group',
				args = {},
				set = function(info, val) end,
			}
		end

		HelpScreen.args[v.category].args[k] = {
			name = v.description or '',
			type = 'input',
			width = 'full',
			get = function(info)
				return '[' .. k .. ']'
			end,
		}
		if v.func then
			v.func(HelpScreen.args[v.category].args[k])
		end
	end
	SUI.opt.args.Help.args.UnitFrames = HelpScreen

	-- Add options to Base Help group
	SUI.opt.args.Help.args.SUIModuleHelp.args.ResetUFSettings = {
		name = L['Reset unitframe customizations'],
		type = 'execute',
		width = 'double',
		order = 90,
		func = function()
			UF:ResetSettings()
		end,
	}

	-- Construct base Options object
	---@type AceConfig.OptionsTable
	local UFOptions = {
		name = L['Unit frames'],
		type = 'group',
		order = 2,
		disabled = function()
			return SUI:IsModuleDisabled(SUI.UF)
		end,
		args = {
			ResetUFSettings = {
				name = L['Reset to base style (Revert customizations)'],
				type = 'execute',
				width = 'full',
				order = 1,
				func = function()
					UF:ResetSettings()
				end,
			},
			ThemeDefaults = {
				name = L['Apply theme defaults (1-click)'],
				type = 'group',
				inline = true,
				order = 20,
				args = {},
			},
			FramePresets = {
				name = L['Frame Presets'],
				type = 'group',
				inline = true,
				order = 30,
				args = {},
			},
			EnabledFrame = {
				name = L['Enabled frames'],
				type = 'group',
				inline = true,
				order = 90,
				args = {},
			},
		},
	}

	for frameName, _ in pairs(UF.Unit:GetFrameList()) do
		UFOptions.args.EnabledFrame.args[frameName] = {
			name = frameName,
			type = 'toggle',
			get = function(info)
				return UF.CurrentSettings[frameName].enabled
			end,
			set = function(info, val)
				--Update memory
				UF.CurrentSettings[frameName].enabled = val
				--Update the DB
				UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].enabled = val
				--Update the UI
				local frame = UF.Unit:Get(frameName)
				if frame then
					if val then
						frame:Enable()
					else
						frame:Disable()
					end
				end
			end,
		}
	end

	-- Build 1-click theme default buttons
	for styleName, styleInfo in pairs(UF.Style:GetList()) do
		local data = styleInfo.settings ---@type SUI.Style.Settings.UnitFrames

		UFOptions.args.ThemeDefaults.args[styleName] = {
			name = data.displayName or styleName,
			type = 'execute',
			image = function()
				return data.setup.image or ('interface\\addons\\SpartanUI\\images\\setup\\Style_Frames_' .. styleName), 120, 60
			end,
			imageCoords = function()
				return data.setup.imageCoords or { 0, 0.5, 0, 0.5 }
			end,
			func = function()
				UF:SetActiveStyle(styleName)
			end,
		}
	end

	-- Add theme defaults section to the core styles page
	SUI.opt.args.General.args.style.args.Unitframes = UFOptions.args.ThemeDefaults

	-- Build per-group preset selectors
	local groupDisplayNames = {
		player = L['Player'],
		pet = L['Pet'],
		target = L['Target'],
		focus = L['Focus'],
		party = L['Party'],
		raid = L['Raid'],
		boss = L['Boss'],
		arena = L['Arena'],
	}
	local groupOrder = { 'player', 'target', 'party', 'raid', 'boss', 'arena', 'focus', 'pet' }

	for i, groupLeader in ipairs(groupOrder) do
		-- Build values list: all presets, marking which have explicit configs for this group
		local applicablePresets = UF.Preset:GetForFrameType(groupLeader)
		local allPresets = UF.Preset:GetList()

		-- Build the values table for the dropdown — show all presets so the user
		-- can always see/change the active preset (e.g. after 1-click theme apply).
		-- Presets with explicit configs for this group show normally; others show
		-- with "(base defaults)" suffix to indicate they'll use hardcoded defaults.
		local values = {}
		for presetName, presetDef in pairs(allPresets) do
			if applicablePresets[presetName] then
				values[presetName] = presetDef.displayName or presetName
			else
				values[presetName] = (presetDef.displayName or presetName) .. ' (base defaults)'
			end
		end

		UFOptions.args.FramePresets.args[groupLeader] = {
			name = groupDisplayNames[groupLeader] or groupLeader,
			type = 'select',
			order = i,
			values = values,
			get = function()
				return UF.Preset:GetActive(groupLeader)
			end,
			set = function(_, presetName)
				UF.Preset:SetForFrame(groupLeader, presetName)
				UF:Update()
			end,
		}
	end

	-- Build frame options
	for frameName, _ in pairs(UF.Unit:GetBuiltFrameList()) do
		local FrameOptSet = Options:CreateFrameOptionSet(frameName, function(info)
			return UF.CurrentSettings[frameName][info[#info]] or false
		end, function(info, val)
			--Update memory
			UF.CurrentSettings[frameName][info[#info]] = val
			--Update the DB
			UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName][info[#info]] = val
			--Update the screen
			UF.Unit[frameName]:UpdateAll()
		end)
		Options:AddGeneral(FrameOptSet)
		Options:AddFrameBackground(frameName, FrameOptSet)
		Options:AddPosition(frameName, FrameOptSet)
		Options:AddAuraPresets(frameName, FrameOptSet)

		-- Add Element Options
		local builtFrame = UF.Unit:Get(frameName)

		for elementName, _ in pairs(builtFrame.elementList) do
			local elementData = builtFrame.config and builtFrame.config.elements and builtFrame.config.elements[elementName]
			if not elementData or not elementData.config then
				UF:debug('Options [' .. frameName .. ']: skipping "' .. elementName .. '" - no config (elementData=' .. tostring(elementData ~= nil) .. ')')
			else
				local elementConfig = elementData.config

				local ElementSettings = UF.CurrentSettings[frameName].elements[elementName]
				local UserSetting = UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements[elementName]

				---@type AceConfig.OptionsTable
				local ElementOptSet = {
					name = elementConfig.DisplayName and L[elementConfig.DisplayName] or elementName,
					desc = elementConfig.Description or '',
					type = 'group',
					order = 1,
					get = function(info)
						return ElementSettings[info[#info]] or false
					end,
					set = function(info, val)
						--Update memory
						ElementSettings[info[#info]] = val
						--Update the DB
						UserSetting[info[#info]] = val
						--Update the screen
						builtFrame:UpdateAll()
					end,
					args = {
						resetElement = {
							name = L['Reset Element'],
							type = 'execute',
							order = 1.5,
							hidden = function()
								return not SUI.Options:hasChanges(UserSetting, UF.Unit.defaultConfigs[frameName].elements[elementName])
							end,
							func = function()
								-- Reset the element's settings to default
								UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements[elementName] = nil

								-- Trigger a full update of the UnitFrames
								UF:Update()

								-- Refresh the options UI
								LibStub('AceConfigRegistry-3.0'):NotifyChange('SpartanUI')
							end,
						},
					},
				}

				local PositionGet = function(info)
					return ElementSettings.position[info[#info]]
				end
				local PositionSet = function(info, val)
					if val == elementName then
						SUI:Print(L['Cannot set position to self'])
						return
					end
					--Update memory
					ElementSettings.position[info[#info]] = val
					--Update the DB
					UserSetting.position[info[#info]] = val
					--Update Screen
					UF.Unit[frameName]:ElementUpdate(elementName)
				end

				if elementConfig.type == 'General' then
				elseif elementConfig.type == 'StatusBar' then
					Options:StatusBarDefaults(frameName, ElementOptSet, elementName)
					Options:AddPositioning(builtFrame.elementList, ElementOptSet, PositionGet, PositionSet)
				elseif elementConfig.type == 'Indicator' then
					if not elementConfig.NoGenericOptions then
						Options:IndicatorAddDisplay(ElementOptSet)
						Options:AddPositioning(builtFrame.elementList, ElementOptSet, PositionGet, PositionSet)
					end
					if elementName == 'CombatIndicator' then
						ElementOptSet.args.display.args.glow = {
							name = L['Glow'],
							type = 'toggle',
							order = 4,
						}
					end
				elseif elementConfig.type == 'Text' then
					-- Options:IndicatorAddDisplay(ElementOptSet)
					Options:AddPositioning(builtFrame.elementList, ElementOptSet, PositionGet, PositionSet)
				elseif elementConfig.type == 'Auras' then
					if not elementConfig.NoGenericOptions then
						Options:IndicatorAddDisplay(ElementOptSet)
						Options:AddPositioning(builtFrame.elementList, ElementOptSet, PositionGet, PositionSet)
						Options:AddAuraLayout(frameName, ElementOptSet)

						-- Basic Filtering Options
						local FilterGet, FilterSet
						if SUI.IsRetail then
							-- Retail: filter mode is handled by the element's own Options function
							FilterGet = function()
								return false
							end
							FilterSet = function() end
						else
							-- Classic: full rules-based filtering via classic sub-table
							local classicSettings = ElementSettings.classic or ElementSettings
							local classicRules = classicSettings.rules or {}
							local classicUserSetting = UserSetting.classic or UserSetting

							FilterGet = function(info, key)
								if info[#info - 1] == 'duration' then
									return classicRules.duration and classicRules.duration[info[#info]] or false
								else
									return classicRules[key] or false
								end
							end
							FilterSet = function(info, key, val)
								if info[#info - 1] == 'duration' then
									if (info[#info] == 'minTime') and classicRules.duration and key > classicRules.duration.maxTime then
										return
									elseif (info[#info] == 'maxTime') and classicRules.duration and key < classicRules.duration.minTime then
										return
									end

									-- Ensure classic config structure exists
									classicSettings.rules = classicSettings.rules or {}
									classicSettings.rules.duration = classicSettings.rules.duration or {}
									classicUserSetting.rules = classicUserSetting.rules or {}
									classicUserSetting.rules.duration = classicUserSetting.rules.duration or {}

									--Update memory
									classicSettings.rules.duration[info[#info]] = key
									--Update the DB
									classicUserSetting.rules.duration[info[#info]] = key
								else
									-- Ensure classic config structure exists
									classicSettings.rules = classicSettings.rules or {}
									classicUserSetting.rules = classicUserSetting.rules or {}

									--Update memory
									classicSettings.rules[key] = (val or false)
									--Update the DB
									classicUserSetting.rules[key] = (val or nil)
								end
								--Update Screen
								UF.Unit[frameName]:ElementUpdate(elementName)
							end
						end
						Options:AddAuraFilters(frameName, ElementOptSet, FilterSet, FilterGet)

						-- Whitelist and Blacklist Options
						local buildItemList

						local spellLabel = {
							type = 'description',
							width = 'double',
							fontSize = 'medium',
							order = function(info)
								return tonumber(string.match(info[#info], '(%d+)'))
							end,
							name = function(info)
								local id = tonumber(string.match(info[#info], '(%d+)'))
								local name = 'unknown'
								if id then
									local spellInfo = GetSpellInfoCompat(id)
									if spellInfo then
										name = string.format('|T%s:14:14:0:0|t %s (#%i)', spellInfo.iconID or 'Interface\\Icons\\Inv_misc_questionmark', spellInfo.name or L['Unknown'], id)
									end
								end
								return name
							end,
						}

						-- Whitelist/Blacklist uses classic sub-table
						local wlClassicSettings = ElementSettings.classic or ElementSettings
						local wlClassicUserSetting = UserSetting.classic or UserSetting

						local spellDelete = {
							type = 'execute',
							name = L['Delete'],
							width = 'half',
							order = function(info)
								return tonumber(string.match(info[#info], '(%d+)')) + 0.5
							end,
							func = function(info)
								local id = tonumber(info[#info])
								local mode = info[#info - 2]

								--Remove Setting
								if wlClassicSettings[mode] then
									wlClassicSettings[mode][id] = nil
								end
								if wlClassicUserSetting[mode] then
									wlClassicUserSetting[mode][id] = nil
								end

								--Update Screen
								buildItemList(mode)
								UF.Unit[frameName]:ElementUpdate(elementName)
							end,
						}

						buildItemList = function(mode)
							local spellsOpt = ElementOptSet.args[mode].args.spells.args
							table.wipe(spellsOpt)

							local modeTable = wlClassicSettings[mode] or {}
							for spellID, _ in pairs(modeTable) do
								spellsOpt[spellID .. 'label'] = spellLabel
								spellsOpt[tostring(spellID)] = spellDelete
							end
						end
						local additem = function(info, input)
							local spellId
							if type(input) == 'string' then
								-- See if we got a spell link
								if input:find('|Hspell:%d+') then
									spellId = tonumber(input:match('|Hspell:(%d+)'))
								elseif input:find('%[(.-)%]') then
									local spellInfo = GetSpellInfoCompat(input:match('%[(.-)%]'))
									spellId = spellInfo and spellInfo.spellID
								else
									local spellInfo = GetSpellInfoCompat(input)
									spellId = spellInfo and spellInfo.spellID
								end
								if not spellId then
									SUI:Print('Invalid spell name or ID')
									return
								end
							end

							local mode = info[#info - 1]
							wlClassicSettings[mode] = wlClassicSettings[mode] or {}
							wlClassicSettings[mode][spellId] = true
							wlClassicUserSetting[mode] = wlClassicUserSetting[mode] or {}
							wlClassicUserSetting[mode][spellId] = true

							UF.Unit[frameName]:ElementUpdate(elementName)
							buildItemList(mode)
						end

						Options:AddAuraWhitelistBlacklist(frameName, ElementOptSet, additem)
						if not SUI.IsRetail then
							buildItemList('whitelist')
							buildItemList('blacklist')
						end
					end -- if not NoGenericOptions
				end

				--Call Elements Custom function
				UF.Elements:Options(frameName, elementName, ElementOptSet, ElementSettings)

				if not ElementOptSet.args.enabled then
					--Add a disable check to all args
					for k, v in pairs(ElementOptSet.args) do
						v.disabled = function()
							return not ElementSettings.enabled
						end
					end

					ElementOptSet.args.enabled = {
						name = L['Enabled'],
						type = 'toggle',
						order = 1,
					}
				end
				-- Add element option to screen
				FrameOptSet.args[elementConfig.type].args[elementName] = ElementOptSet
			end -- else (elementData check)
		end

		UF.Unit:BuildOptions(frameName, FrameOptSet)

		UFOptions.args[frameName] = FrameOptSet
	end

	SUI.opt.args.UnitFrames = UFOptions
end

Options.CONST = { anchorPoints = anchorPoints }

UF.Options = Options
