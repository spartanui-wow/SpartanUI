---@class SUI.UF
local UF = SUI.UF

-- Aura Filter Presets for different playstyles
-- These presets configure the Buffs and Debuffs elements for optimal display

---@class SUI.UF.AuraPresets
local AuraPresets = {}
UF.AuraPresets = AuraPresets

-- Preset definitions
-- Each preset contains settings for both Buffs and Debuffs elements
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
			rules = {
				isFromPlayerOrPlayerPet = true, -- Show your buffs
				isHelpful = true,
				isHarmful = false,
				isBossAura = true,
				duration = {
					enabled = true,
					mode = 'include',
					minTime = 1,
					maxTime = 300, -- 5 minutes max
				},
			},
		},
		Debuffs = {
			showDuration = true,
			sortMode = 'priority',
			number = 10,
			size = 24, -- Slightly larger for debuffs (healers need to see these)
			rows = 2,
			rules = {
				isHarmful = true,
				isHelpful = false,
				isBossAura = true,
				duration = {
					enabled = true,
					mode = 'include',
					minTime = 1,
					maxTime = 180,
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
			rules = {
				isFromPlayerOrPlayerPet = true,
				isHelpful = true,
				isHarmful = false,
				isBossAura = true,
				isRaid = true,
				duration = {
					enabled = true,
					mode = 'include',
					minTime = 1,
					maxTime = 180,
				},
			},
		},
		Debuffs = {
			showDuration = true,
			sortMode = 'priority',
			number = 8,
			size = 26, -- Large debuffs for raid awareness
			rows = 1,
			rules = {
				isHarmful = true,
				isHelpful = false,
				isBossAura = true,
				duration = {
					enabled = true,
					mode = 'include',
					minTime = 1,
					maxTime = 120,
				},
			},
		},
	},

	-- DPS Focus: DoTs, offensive buffs, and procs
	dps = {
		name = 'DPS',
		description = 'Optimized for damage dealers. Shows your DoTs, offensive buffs, and procs.',
		Buffs = {
			showDuration = true,
			sortMode = 'time', -- Sort by time for proc tracking
			number = 10,
			size = 20,
			rows = 2,
			rules = {
				isFromPlayerOrPlayerPet = true,
				isHelpful = true,
				isHarmful = false,
				isBossAura = true,
				duration = {
					enabled = true,
					mode = 'include',
					minTime = 1,
					maxTime = 60, -- Short buffs only (procs, CDs)
				},
			},
		},
		Debuffs = {
			showDuration = true,
			sortMode = 'time',
			number = 8,
			size = 22,
			rows = 1,
			rules = {
				isFromPlayerOrPlayerPet = true, -- Your DoTs
				isHarmful = true,
				isHelpful = false,
				isBossAura = true,
				duration = {
					enabled = true,
					mode = 'include',
					minTime = 1,
					maxTime = 60,
				},
			},
		},
	},

	-- Tank Focus: Defensive cooldowns and threat-related auras
	tank = {
		name = 'Tank',
		description = 'Optimized for tanks. Shows defensive cooldowns, mitigation buffs, and threat-related debuffs.',
		Buffs = {
			showDuration = true,
			sortMode = 'priority',
			number = 10,
			size = 24,
			rows = 2,
			rules = {
				isFromPlayerOrPlayerPet = true,
				isHelpful = true,
				isHarmful = false,
				isBossAura = true,
				duration = {
					enabled = true,
					mode = 'include',
					minTime = 1,
					maxTime = 120, -- Defensive CDs are often 1-2 min
				},
			},
		},
		Debuffs = {
			showDuration = true,
			sortMode = 'priority',
			number = 8,
			size = 26,
			rows = 1,
			rules = {
				isHarmful = true,
				isHelpful = false,
				isBossAura = true, -- Boss debuffs important for tanks
				duration = {
					enabled = true,
					mode = 'include',
					minTime = 1,
					maxTime = 60,
				},
			},
		},
	},

	-- Minimal: Clean display with fewer auras
	minimal = {
		name = 'Minimal',
		description = 'Clean, minimal display. Shows only the most important auras.',
		Buffs = {
			showDuration = true,
			sortMode = 'priority',
			number = 4,
			size = 18,
			rows = 1,
			rules = {
				isFromPlayerOrPlayerPet = true,
				isHelpful = true,
				isHarmful = false,
				isBossAura = true,
				duration = {
					enabled = true,
					mode = 'include',
					minTime = 1,
					maxTime = 60,
				},
			},
		},
		Debuffs = {
			showDuration = true,
			sortMode = 'priority',
			number = 4,
			size = 20,
			rows = 1,
			rules = {
				isHarmful = true,
				isHelpful = false,
				isBossAura = true,
				duration = {
					enabled = true,
					mode = 'include',
					minTime = 1,
					maxTime = 60,
				},
			},
		},
	},
}

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

	-- Apply Buffs settings
	if preset.Buffs and UF.CurrentSettings[unitName] and UF.CurrentSettings[unitName].elements.Buffs then
		local buffsSettings = UF.CurrentSettings[unitName].elements.Buffs
		local userBuffs = UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.Buffs

		for key, value in pairs(preset.Buffs) do
			if key == 'rules' then
				-- Merge rules
				for ruleKey, ruleValue in pairs(value) do
					buffsSettings.rules[ruleKey] = ruleValue
					userBuffs.rules[ruleKey] = ruleValue
				end
			else
				buffsSettings[key] = value
				userBuffs[key] = value
			end
		end

		-- Update the element
		if UF.Unit[unitName] then
			UF.Unit[unitName]:ElementUpdate('Buffs')
		end
	end

	-- Apply Debuffs settings
	if preset.Debuffs and UF.CurrentSettings[unitName] and UF.CurrentSettings[unitName].elements.Debuffs then
		local debuffsSettings = UF.CurrentSettings[unitName].elements.Debuffs
		local userDebuffs = UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.Debuffs

		for key, value in pairs(preset.Debuffs) do
			if key == 'rules' then
				-- Merge rules
				for ruleKey, ruleValue in pairs(value) do
					debuffsSettings.rules[ruleKey] = ruleValue
					userDebuffs.rules[ruleKey] = ruleValue
				end
			else
				debuffsSettings[key] = value
				userDebuffs[key] = value
			end
		end

		-- Update the element
		if UF.Unit[unitName] then
			UF.Unit[unitName]:ElementUpdate('Debuffs')
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
