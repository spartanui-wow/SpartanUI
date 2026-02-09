local UF = SUI.UF
local L = SUI.L

-- Helper for spell info (uses unified C_Spell API available in all current versions)
local function GetSpellInfoCompat(spellInput)
	return C_Spell.GetSpellInfo(spellInput)
end

-- Healing over Time spell lists for easy healer filtering
local HealingSpells = {
	-- Druid HoTs
	[774] = true, -- Rejuvenation
	[8936] = true, -- Regrowth
	[33763] = true, -- Lifebloom
	[48438] = true, -- Wild Growth
	[102351] = true, -- Cenarion Ward
	[102342] = true, -- Ironbark
	[200389] = true, -- Cultivation
	[157982] = true, -- Tranquility
	[391891] = true, -- Adaptive Swarm (Healing)
	[383193] = true, -- Grove Tending
	[200851] = true, -- Rage of the Sleeper
	-- Priest HoTs
	[139] = true, -- Renew
	[17] = true, -- Power Word: Shield
	[194384] = true, -- Atonement
	[41635] = true, -- Prayer of Mending
	[33206] = true, -- Pain Suppression
	[47753] = true, -- Divine Aegis
	[10060] = true, -- Power Infusion
	[265202] = true, -- Holy Word: Salvation
	[372835] = true, -- Lightwell Renew
	[200183] = true, -- Apotheosis
	-- Shaman HoTs
	[61295] = true, -- Riptide
	[974] = true, -- Earth Shield
	[16237] = true, -- Ancestral Fortitude
	[201633] = true, -- Earthen Wall Totem
	[383648] = true, -- Flame Shock (Enhancement healing)
	[462844] = true, -- Surging Totem
	[108271] = true, -- Astral Shift
	-- Paladin HoTs/Buffs
	[53563] = true, -- Beacon of Light
	[200025] = true, -- Beacon of Virtue
	[156910] = true, -- Beacon of Faith
	[1022] = true, -- Blessing of Protection
	[6940] = true, -- Blessing of Sacrifice
	[1044] = true, -- Blessing of Freedom
	[305395] = true, -- Blessing of Sanctuary
	[223306] = true, -- Bestow Faith
	[148039] = true, -- Barrier of Faith
	[200654] = true, -- Tyr's Deliverance
	-- Monk HoTs
	[191840] = true, -- Essence Font
	[124682] = true, -- Enveloping Mist
	[115175] = true, -- Soothing Mist
	[116849] = true, -- Life Cocoon
	[325209] = true, -- Enveloping Breath
	[388193] = true, -- Faeline Stomp
	[343737] = true, -- Refreshing Jade Wind
	[116844] = true, -- Ring of Peace
	[122783] = true, -- Diffuse Magic
	-- Evoker HoTs
	[355941] = true, -- Dream Breath
	[364343] = true, -- Echo
	[367230] = true, -- Reversion
	[376788] = true, -- Dream Flight
	[363534] = true, -- Rewind
	[374348] = true, -- Renewing Blaze
	[378441] = true, -- Time Stop
	[370960] = true, -- Emerald Communion
	[374227] = true, -- Zephyr
	-- Demon Hunter
	[203819] = true, -- Demon Spikes
	[212800] = true, -- Blur
	[263648] = true, -- Soul Barrier
	[187827] = true, -- Metamorphosis
	-- Death Knight
	[48707] = true, -- Anti-Magic Shell
	[55233] = true, -- Vampiric Blood
	[194679] = true, -- Rune Tap
	[81256] = true, -- Dancing Rune Weapon
	[219809] = true, -- Tombstone
	-- Warrior
	[871] = true, -- Shield Wall
	[12975] = true, -- Last Stand
	[184364] = true, -- Enraged Regeneration
	[97462] = true, -- Rallying Cry
	[223658] = true, -- Safeguard
	-- General defensive/healing buffs
	[1459] = true, -- Arcane Intellect
	[21562] = true, -- Power Word: Fortitude
	[6673] = true, -- Battle Shout
	[1126] = true, -- Mark of the Wild
}

-- DoT spells for DPS tracking
local DamageOverTimeSpells = {
	-- Warlock
	[172] = true, -- Corruption
	[980] = true, -- Agony
	[27243] = true, -- Seed of Corruption
	[348] = true, -- Immolate
	[157736] = true, -- Immolate (Destro)
	[30108] = true, -- Unstable Affliction
	[63106] = true, -- Siphon Soul
	[234153] = true, -- Drain Life
	[198590] = true, -- Drain Soul
	[5138] = true, -- Drain Mana
	-- Shadow Priest
	[589] = true, -- Shadow Word: Pain
	[34914] = true, -- Vampiric Touch
	[15407] = true, -- Mind Flay
	[48045] = true, -- Mind Sear
	[8122] = true, -- Psychic Scream
	-- Rogue
	[1943] = true, -- Rupture
	[2818] = true, -- Deadly Poison
	[8680] = true, -- Wound Poison
	[3408] = true, -- Crippling Poison
	[121411] = true, -- Crimson Tempest
	[122233] = true, -- Crimson Poison
	-- Hunter
	[1978] = true, -- Serpent Sting
	[3674] = true, -- Black Arrow
	[13795] = true, -- Immolation Trap
	[271788] = true, -- Serpent Sting (BM)
	[259491] = true, -- Serpent Sting (Survival)
	-- Mage
	[12654] = true, -- Ignite
	[22959] = true, -- Fire Vulnerability
	[31661] = true, -- Dragon's Breath
	[413841] = true, -- Frostfire Bolt
	[205708] = true, -- Chilled to the Bone
}

---@param frame table
---@param DB table
local function Build(frame, DB)
	local element = CreateFrame('Frame', '$parent_AuraBars', frame)

	element.spellTimeFont = SUI.Font:GetFont('Player')
	element.spellNameFont = SUI.Font:GetFont('Player')
	element.PostCreateButton = function(self, button)
		UF.Auras:PostCreateButton('Buffs', button)
	end

	---@param unit UnitId
	---@param data UnitAuraInfo
	local FilterAura = function(element, unit, data)
		-- Use enhanced filtering system
		return UF.Auras:Filter(element, unit, data, element.DB.rules) and element:CustomAuraFilter(unit, data)
	end
	element.FilterAura = FilterAura

	-- Enhanced custom filter function for AuraBars
	---@param unit UnitId
	---@param data UnitAuraInfo
	function element:CustomAuraFilter(unit, data)
		local DB = self.DB

		-- Retail vs Classic filtering approach
		-- Retail: Cannot access spellId due to secret values - use boolean properties only
		-- Classic: Full access to spellId for spell-specific filtering
		if SUI.IsRetail then
			return self:RetailAuraFilter(unit, data)
		else
			return self:ClassicAuraFilter(unit, data)
		end
	end

	-- Retail filtering: ONLY safe properties (isPlayerAura, isHarmfulAura from oUF)
	-- ALL other aura data properties are SECRET VALUES in WoW 12.0+ and will crash if tested
	---@param unit UnitId
	---@param data UnitAuraInfo
	function element:RetailAuraFilter(unit, data)
		local DB = self.DB

		-- In Retail 12.0+, we can ONLY safely use:
		--   - isPlayerAura: created by oUF using C_UnitAuras.IsAuraFilteredOutByInstanceID
		--   - isHarmfulAura: created by oUF from the filter string (not from data)
		--   - auraInstanceID: integer, always safe
		-- Properties like isBossAura, isFromPlayerOrPlayerPet, isHelpful, isHarmful, etc.
		-- are SECRET VALUES and testing them will crash the addon!

		-- Filter mode determines what we show
		-- Since we can't detect boss auras or specific types, we filter by player ownership only
		if DB.filterMode == 'healer' then
			-- Healer mode: Show player's auras (we can't tell if they're HoTs)
			-- isHarmfulAura is safe (from oUF filter string), so show helpful only
			if data.isPlayerAura and not data.isHarmfulAura then
				return true
			end
		elseif DB.filterMode == 'dps' then
			-- DPS mode: Show player's harmful auras (DoTs)
			if data.isPlayerAura and data.isHarmfulAura then
				return true
			end
		elseif DB.filterMode == 'tank' then
			-- Tank mode: Show player's helpful auras
			if data.isPlayerAura and not data.isHarmfulAura then
				return true
			end
		elseif DB.filterMode == 'custom' then
			-- Custom mode: Show player-cast auras only
			if data.isPlayerAura then
				return true
			end
		else
			-- Default: Show player's own auras
			if data.isPlayerAura then
				return true
			end
		end

		return false
	end

	-- Classic filtering: Full spellId access for spell-specific filtering
	---@param unit UnitId
	---@param data UnitAuraInfo
	function element:ClassicAuraFilter(unit, data)
		local DB = self.DB

		-- If using legacy custom filter, fall back to that
		if DB.useLegacyFilter then
			if (data.sourceUnit == 'player' or data.sourceUnit == 'vehicle' or data.isBossAura) and data.duration ~= 0 and data.duration <= 900 then
				return true
			end
			return false
		end

		-- Raider mode: always show boss auras regardless of role
		if DB.raiderMode and data.isBossAura then
			return true
		end

		-- Enhanced filtering with role presets
		if DB.filterMode == 'healer' then
			-- Healer mode: ONLY show HoTs and defensive buffs in the list
			if HealingSpells[data.spellId] then
				return true
			end
			-- Also show boss auras for healers
			if data.isBossAura then
				return true
			end
		elseif DB.filterMode == 'dps' then
			-- DPS mode: ONLY show DoTs and offensive buffs in the list
			if DamageOverTimeSpells[data.spellId] and data.sourceUnit == 'player' then
				return true
			end
			-- Also show boss auras for DPS
			if data.isBossAura then
				return true
			end
		elseif DB.filterMode == 'tank' then
			-- Tank mode: show defensive buffs and important short debuffs
			if data.sourceUnit == 'player' and (HealingSpells[data.spellId] or data.duration <= 60) then
				return true
			end
			-- Also show boss auras for tanks
			if data.isBossAura then
				return true
			end
		elseif DB.filterMode == 'custom' then
			-- Custom mode: use fallback filtering rules
			if data.isBossAura or (data.sourceUnit == 'player' and data.duration > 0 and data.duration <= DB.maxDuration) then
				return true
			end
		end

		return false
	end

	local function PostCreateBar(_, bar)
		bar:SetStatusBarTexture(UF:FindStatusBarTexture(DB.texture))

		bar.spark:SetTexture(UF:FindStatusBarTexture(DB.texture))
		bar.spark:SetVertexColor(1, 1, 1, 0.4)
		bar.spark:SetSize(2, DB.size)

		bar.bg = bar:CreateTexture(nil, 'BORDER')
		bar.bg:SetAllPoints(bar)
		bar.bg:SetTexture(UF:FindStatusBarTexture(DB.texture))
		bar.bg:SetVertexColor(0, 0, 0, 0.4)
		bar.bg:Show()
	end
	element.PostCreateBar = PostCreateBar

	-- Legacy CustomFilter for compatibility
	---@param element any
	---@param unit any
	---@param bar any
	---@param auraData AuraData
	element.CustomFilter = function(element, unit, bar, auraData)
		-- Convert bar data to standard format for new filter
		local data = {
			spellId = auraData.spellId,
			sourceUnit = auraData.sourceUnit,
			isBossAura = auraData.isBossAura,
			duration = auraData.duration,
			name = auraData.name,
			isHelpful = not auraData.isHarmful,
			isHarmful = auraData.isHarmful,
		}
		return element:CustomAuraFilter(unit, data)
	end

	element.displayReasons = {}
	element.initialAnchor = 'BOTTOMRIGHT'

	frame.AuraBars = element
end

---@param frame table
---@param settings? table
local function Update(frame, settings)
	local element = frame.AuraBars
	if not frame.AuraBars then
		return
	end
	local DB = settings or element.DB

	if DB.enabled then
		element:Show()
	else
		element:Hide()
	end

	element.anchoredBars = DB.anchoredBars or 0
	element.width = (DB.width or frame:GetWidth()) - DB.size
	element.size = DB.size or 14
	element.sparkEnabled = DB.sparkEnabled or true
	element.spacing = DB.spacing or 2
	element.initialAnchor = DB.initialAnchor or 'BOTTOMLEFT'
	element.growth = DB.growth or 'UP'
	element.maxBars = DB.maxBars or 32
	element.barSpacing = DB.barSpacing or 2
end

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	local ElementSettings = UF.CurrentSettings[unitName].elements.AuraBars
	local function OptUpdate(option, val)
		UF.CurrentSettings[unitName].elements.AuraBars[option] = val
		UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.AuraBars[option] = val
		UF.Unit[unitName]:ElementUpdate('AuraBars')
	end

	-- Add Filter Mode options
	OptionSet.args.FilterMode = {
		name = L['Filter Mode'],
		type = 'group',
		order = 50,
		inline = true,
		args = {
			filterMode = {
				name = L['Filtering Mode'],
				desc = SUI.IsRetail and L['Choose how aura bars are filtered. Healer shows your helpful auras, DPS shows your harmful auras, Tank shows your defensive auras.']
					or L['Choose how aura bars are filtered. Healer mode shows HoTs, DPS mode shows DoTs, Tank mode shows defensive buffs.'],
				type = 'select',
				order = 1,
				values = {
					healer = SUI.IsRetail and L['Healer (Your Helpful Auras)'] or L['Healer (HoTs & Defensive)'],
					dps = SUI.IsRetail and L['DPS (Your Harmful Auras)'] or L['DPS (DoTs & Offensive)'],
					tank = SUI.IsRetail and L['Tank (Your Defensive Auras)'] or L['Tank (Defensive & Short Buffs)'],
					custom = SUI.IsRetail and L['Custom (Your Auras + Boss)'] or L['Custom (Use Advanced Filters)'],
				},
				get = function()
					return ElementSettings.filterMode
				end,
				set = function(_, val)
					OptUpdate('filterMode', val)
				end,
			},
			raiderMode = {
				name = L['Raider Mode'],
				desc = L['Always show all boss buffs and debuffs regardless of role preset'],
				type = 'toggle',
				order = 2,
				get = function()
					return ElementSettings.raiderMode
				end,
				set = function(_, val)
					OptUpdate('raiderMode', val)
				end,
			},
			useLegacyFilter = {
				name = L['Use Legacy Filtering'],
				desc = L['Use the original filtering system (player/vehicle/boss auras under 15 minutes) instead of role-based filtering'],
				type = 'toggle',
				order = 3,
				hidden = function()
					return SUI.IsRetail
				end, -- Hidden in Retail - legacy filter uses duration which is unavailable
				get = function()
					return ElementSettings.useLegacyFilter
				end,
				set = function(_, val)
					OptUpdate('useLegacyFilter', val)
				end,
			},
			maxDuration = {
				name = L['Maximum Duration'],
				desc = L['Maximum duration in seconds for player auras to be shown (when not using role presets)'],
				type = 'range',
				order = 4,
				hidden = function()
					return SUI.IsRetail
				end, -- Hidden in Retail - duration access unavailable
				min = 30,
				max = 3600,
				step = 30,
				get = function()
					return ElementSettings.maxDuration
				end,
				set = function(_, val)
					OptUpdate('maxDuration', val)
				end,
			},
		},
	}

	-- Add standard filtering options using the shared system
	local FilterGet = function(info, key)
		if info[#info - 1] == 'duration' then
			return ElementSettings.rules.duration[info[#info]] or false
		else
			return ElementSettings.rules[key] or false
		end
	end

	local FilterSet = function(info, key, val)
		if info[#info - 1] == 'duration' then
			if (info[#info] == 'minTime') and key > ElementSettings.rules.duration.maxTime then
				return
			elseif (info[#info] == 'maxTime') and key < ElementSettings.rules.duration.minTime then
				return
			end
			UF.CurrentSettings[unitName].elements.AuraBars.rules.duration[info[#info]] = key
			UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.AuraBars.rules.duration[info[#info]] = key
		else
			UF.CurrentSettings[unitName].elements.AuraBars.rules[info[#info]] = key
			UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.AuraBars.rules[info[#info]] = key
		end
		UF.Unit[unitName]:ElementUpdate('AuraBars')
	end

	UF.Options:AddAuraFilters(unitName, OptionSet, FilterSet, FilterGet)

	-- Add whitelist/blacklist options
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

		ElementSettings.rules[info[#info - 1]][spellId] = true
		UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.AuraBars.rules[info[#info - 1]][spellId] = true

		UF.Unit[unitName]:ElementUpdate('AuraBars')
	end

	UF.Options:AddAuraWhitelistBlacklist(unitName, OptionSet, additem)

	OptionSet.args.Layout = {
		name = L['Layout'],
		type = 'group',
		order = 100,
		inline = true,
		args = {
			growth = {
				name = L['Growth Direction'],
				desc = L['Choose the direction in which aura bars grow'],
				type = 'select',
				order = 1,
				values = {
					UP = L['Up'],
					DOWN = L['Down'],
				},
				get = function()
					return ElementSettings.growth
				end,
				set = function(_, val)
					OptUpdate('growth', val)
				end,
			},
			maxBars = {
				name = L['Maximum Bars'],
				desc = L['Set the maximum number of aura bars to display'],
				type = 'range',
				order = 2,
				min = 1,
				max = 40,
				step = 1,
				get = function()
					return ElementSettings.maxBars
				end,
				set = function(_, val)
					OptUpdate('maxBars', val)
				end,
			},
			barSpacing = {
				name = L['Bar Spacing'],
				desc = L['Set the space between aura bars'],
				type = 'range',
				order = 3,
				min = 0,
				max = 20,
				step = 1,
				get = function()
					return ElementSettings.barSpacing
				end,
				set = function(_, val)
					OptUpdate('barSpacing', val)
				end,
			},
		},
	}

	OptionSet.args.Appearance = {
		name = L['Appearance'],
		type = 'group',
		order = 200,
		inline = true,
		args = {
			fgalpha = {
				name = L['Foreground Alpha'],
				desc = L['Set the opacity of the aura bar foreground'],
				type = 'range',
				order = 1,
				min = 0,
				max = 1,
				step = 0.01,
				get = function()
					return ElementSettings.fgalpha
				end,
				set = function(_, val)
					OptUpdate('fgalpha', val)
				end,
			},
			bgalpha = {
				name = L['Background Alpha'],
				desc = L['Set the opacity of the aura bar background'],
				type = 'range',
				order = 2,
				min = 0,
				max = 1,
				step = 0.01,
				get = function()
					return ElementSettings.bgalpha
				end,
				set = function(_, val)
					OptUpdate('bgalpha', val)
				end,
			},
			spellNameSize = {
				name = L['Spell Name Font Size'],
				desc = L['Set the font size for spell names on aura bars'],
				type = 'range',
				order = 3,
				min = 6,
				max = 20,
				step = 1,
				get = function()
					return ElementSettings.spellNameSize
				end,
				set = function(_, val)
					OptUpdate('spellNameSize', val)
				end,
			},
			spellTimeSize = {
				name = L['Spell Time Font Size'],
				desc = L['Set the font size for spell durations on aura bars'],
				type = 'range',
				order = 4,
				min = 6,
				max = 20,
				step = 1,
				get = function()
					return ElementSettings.spellTimeSize
				end,
				set = function(_, val)
					OptUpdate('spellTimeSize', val)
				end,
			},
		},
	}
end

---@type SUI.UF.Elements.Settings
local Settings = {
	size = 14,
	width = false,
	sparkEnabled = true,
	spacing = 2,
	initialAnchor = 'BOTTOMLEFT',
	growth = 'UP',
	maxBars = 32,
	fgalpha = 1,
	bgalpha = 1,
	spellNameSize = 10,
	spellTimeSize = 10,
	gap = 1,
	scaleTime = false,
	icon = true,
	-- Enhanced filtering options
	filterMode = 'healer', -- 'healer', 'dps', 'tank', 'custom' - default to healer as primary AuraBars use case
	raiderMode = true, -- Show boss auras by default
	useLegacyFilter = false, -- Legacy filter disabled by default (uses duration which is unavailable in Retail)
	maxDuration = 900, -- 15 minutes in seconds (Classic only)
	position = {
		anchor = 'BOTTOMLEFT',
		relativePoint = 'TOPLEFT',
		x = 7,
		y = 20,
	},
	rules = {
		duration = {
			enabled = false,
			mode = 'exclude',
			maxTime = 900,
			minTime = 1,
		},
		showPlayers = true,
		isBossAura = true,
		whitelist = {},
		blacklist = {},
	},
	config = {
		type = 'Auras',
		DisplayName = 'Aura Bars',
	},
}

UF.Elements:Register('AuraBars', Build, Update, Options, Settings)
