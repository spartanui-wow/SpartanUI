---@class SUI.UF
local UF = SUI.UF

-- Aura Filter Presets for different playstyles
-- Each preset has version-specific filter config (retail/classic) and shared visual settings

---@class SUI.UF.AuraPresets
local AuraPresets = {}
UF.AuraPresets = AuraPresets

-- Preset definitions
AuraPresets.Presets = {
	-- Healer Focus: Prioritize seeing HoTs, defensive cooldowns, and dispellable debuffs
	healer = {
		name = 'Healer Focus',
		description = 'Optimized for healers. Shows your HoTs, defensive cooldowns, and dispellable debuffs prominently.',
		Buffs = {
			showDuration = true,
			sortMode = 'priority',
			number = 12,
			size = 22,
			rows = 2,
			retail = { filterMode = 'healing_mode' },
			classic = {
				rules = {
					isFromPlayerOrPlayerPet = true,
					isHelpful = true,
					isHarmful = false,
					isBossAura = true,
					duration = { enabled = true, mode = 'include', minTime = 1, maxTime = 300 },
				},
			},
		},
		Debuffs = {
			showDuration = true,
			sortMode = 'priority',
			number = 10,
			size = 24,
			rows = 2,
			retail = { filterMode = 'raid_debuffs' },
			classic = {
				rules = {
					isHarmful = true,
					isHelpful = false,
					isBossAura = true,
					duration = { enabled = true, mode = 'include', minTime = 1, maxTime = 180 },
				},
			},
		},
	},

	-- Raider Focus: Boss mechanics and important raid auras
	raider = {
		name = 'Raider',
		description = 'Optimized for raiders. Prioritizes boss debuffs, raid cooldowns, and personal defensive buffs.',
		Buffs = {
			showDuration = true,
			sortMode = 'priority',
			number = 8,
			size = 20,
			rows = 2,
			retail = { filterMode = 'raid_buffs' },
			classic = {
				rules = {
					isFromPlayerOrPlayerPet = true,
					isHelpful = true,
					isHarmful = false,
					isBossAura = true,
					isRaid = true,
					duration = { enabled = true, mode = 'include', minTime = 1, maxTime = 180 },
				},
			},
		},
		Debuffs = {
			showDuration = true,
			sortMode = 'priority',
			number = 8,
			size = 26,
			rows = 1,
			retail = { filterMode = 'all_debuffs' },
			classic = {
				rules = {
					isHarmful = true,
					isHelpful = false,
					isBossAura = true,
					duration = { enabled = true, mode = 'include', minTime = 1, maxTime = 120 },
				},
			},
		},
	},

	-- DPS Focus: DoTs, offensive buffs, and procs
	dps = {
		name = 'DPS',
		description = 'Optimized for damage dealers. Shows your buffs and your DoTs on the target.',
		Buffs = {
			showDuration = true,
			sortMode = 'priority',
			number = 10,
			size = 20,
			rows = 2,
			retail = { filterMode = 'player_buffs' },
			classic = {
				rules = {
					isFromPlayerOrPlayerPet = true,
					isHelpful = true,
					isHarmful = false,
					isBossAura = true,
					duration = { enabled = true, mode = 'include', minTime = 1, maxTime = 60 },
				},
			},
		},
		Debuffs = {
			showDuration = true,
			sortMode = 'priority',
			number = 8,
			size = 22,
			rows = 1,
			retail = { filterMode = 'player_debuffs' },
			classic = {
				rules = {
					isFromPlayerOrPlayerPet = true,
					isHarmful = true,
					isHelpful = false,
					isBossAura = true,
					duration = { enabled = true, mode = 'include', minTime = 1, maxTime = 60 },
				},
			},
		},
	},

	-- Tank Focus: Defensive cooldowns and threat-related auras
	tank = {
		name = 'Tank',
		description = 'Optimized for tanks. Shows your defensive buffs and all debuffs on you.',
		Buffs = {
			showDuration = true,
			sortMode = 'priority',
			number = 10,
			size = 24,
			rows = 2,
			retail = { filterMode = 'player_buffs' },
			classic = {
				rules = {
					isFromPlayerOrPlayerPet = true,
					isHelpful = true,
					isHarmful = false,
					isBossAura = true,
					duration = { enabled = true, mode = 'include', minTime = 1, maxTime = 120 },
				},
			},
		},
		Debuffs = {
			showDuration = true,
			sortMode = 'priority',
			number = 8,
			size = 26,
			rows = 1,
			retail = { filterMode = 'all_debuffs' },
			classic = {
				rules = {
					isHarmful = true,
					isHelpful = false,
					isBossAura = true,
					duration = { enabled = true, mode = 'include', minTime = 1, maxTime = 60 },
				},
			},
		},
	},

	-- Minimal: Clean display with fewer auras
	minimal = {
		name = 'Minimal',
		description = 'Shows only the most important auras with a clean, small layout.',
		Buffs = {
			showDuration = true,
			sortMode = 'priority',
			number = 4,
			size = 18,
			rows = 1,
			retail = { filterMode = 'important_buffs' },
			classic = {
				rules = {
					isFromPlayerOrPlayerPet = true,
					isHelpful = true,
					isHarmful = false,
					isBossAura = true,
					duration = { enabled = true, mode = 'include', minTime = 1, maxTime = 60 },
				},
			},
		},
		Debuffs = {
			showDuration = true,
			sortMode = 'priority',
			number = 4,
			size = 20,
			rows = 1,
			retail = { filterMode = 'important_debuffs' },
			classic = {
				rules = {
					isHarmful = true,
					isHelpful = false,
					isBossAura = true,
					duration = { enabled = true, mode = 'include', minTime = 1, maxTime = 60 },
				},
			},
		},
	},
}

-- Retail-only presets (hidden on Classic where the full filter system covers these use cases)
if SUI.IsRetail then
	AuraPresets.Presets.show_all = {
		name = 'Show All',
		description = 'Shows every buff and debuff with no filtering.',
		Buffs = {
			showDuration = true,
			sortMode = 'priority',
			number = 16,
			size = 18,
			rows = 2,
			retail = { filterMode = 'all_buffs' },
		},
		Debuffs = {
			showDuration = true,
			sortMode = 'priority',
			number = 16,
			size = 18,
			rows = 2,
			retail = { filterMode = 'all_debuffs' },
		},
	}

	AuraPresets.Presets.pvp = {
		name = 'PvP',
		description = 'PvP-oriented. Shows your buffs and all crowd control debuffs.',
		Buffs = {
			showDuration = true,
			sortMode = 'priority',
			number = 10,
			size = 22,
			rows = 2,
			retail = { filterMode = 'player_buffs' },
		},
		Debuffs = {
			showDuration = true,
			sortMode = 'priority',
			number = 10,
			size = 22,
			rows = 2,
			retail = { filterMode = 'crowd_control' },
		},
	}

	AuraPresets.Presets.raid_healer = {
		name = 'Raid Healer',
		description = 'Healing layout for organized raiding. HoTs on buffs, raid-important debuffs.',
		Buffs = {
			showDuration = true,
			sortMode = 'priority',
			number = 14,
			size = 24,
			rows = 2,
			retail = { filterMode = 'healing_mode' },
		},
		Debuffs = {
			showDuration = true,
			sortMode = 'priority',
			number = 8,
			size = 26,
			rows = 1,
			retail = { filterMode = 'raid_debuffs' },
		},
	}
end

-- Get list of preset names for dropdown
---@return table<string, string>
function AuraPresets:GetPresetList()
	local list = {
		custom = SUI.L['Custom'],
	}
	for key, preset in pairs(self.Presets) do
		list[key] = preset.name
	end
	return list
end

-- Apply a preset to a specific unit
---@param unitName string
---@param presetKey string
function AuraPresets:ApplyPreset(unitName, presetKey)
	local preset = self.Presets[presetKey]
	if not preset then
		return
	end

	local branch = SUI.IsRetail and 'retail' or 'classic'

	for _, elementName in ipairs({ 'Buffs', 'Debuffs' }) do
		local presetElement = preset[elementName]
		if presetElement and UF.CurrentSettings[unitName] and UF.CurrentSettings[unitName].elements[elementName] then
			local currentSettings = UF.CurrentSettings[unitName].elements[elementName]
			local userSettings = UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements[elementName]

			-- Apply shared visual settings
			for key, value in pairs(presetElement) do
				if key ~= 'retail' and key ~= 'classic' and key ~= 'rules' then
					currentSettings[key] = value
					userSettings[key] = value
				end
			end

			-- Apply version-specific filter config
			local filterConfig = presetElement[branch]
			if filterConfig then
				currentSettings[branch] = currentSettings[branch] or {}
				userSettings[branch] = userSettings[branch] or {}
				for key, value in pairs(filterConfig) do
					currentSettings[branch][key] = value
					userSettings[branch][key] = value
				end
			end

			-- Update the element
			if UF.Unit[unitName] then
				UF.Unit[unitName]:ElementUpdate(elementName)
			end
		end
	end

	SUI:Print(string.format('Applied "%s" aura preset to %s', preset.name, unitName))
end

-- Apply preset to all group units (party and raid)
---@param presetKey string
function AuraPresets:ApplyPresetToGroups(presetKey)
	local groupUnits = { 'party', 'raid' }
	for _, unitName in ipairs(groupUnits) do
		self:ApplyPreset(unitName, presetKey)
	end
end
