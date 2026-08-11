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
	element:EnableMouse(false)
	element.disableMouse = true

	element.spellTimeFont = SUI.Font:GetFont('Player')
	element.spellNameFont = SUI.Font:GetFont('Player')
	element.PostCreateButton = function(self, button)
		UF.Auras:PostCreateButton('Buffs', button)
	end

	---@param unit UnitId
	---@param data UnitAuraInfo
	local FilterAura = function(element, unit, data)
		-- Use the base filter dispatcher (reads retail/classic config from element.DB)
		-- Then apply AuraBars-specific role filtering
		return UF.Auras:Filter(element, unit, data) and element:CustomAuraFilter(unit, data)
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

	-- Retail filtering: All filtering is done at the API level via filter strings
	-- set on friendlyAuraType/enemyAuraType in Update(). CustomFilter just passes through.
	---@param unit UnitId
	---@param data UnitAuraInfo
	function element:RetailAuraFilter(unit, data)
		local DB = self.DB
		if not DB then
			return true
		end

		-- Spell ID lists, matching what aura groups offer. spellId is a secret
		-- for restricted units, so an unreadable one cannot be matched either
		-- way: it is kept when only an exclude list is set, and dropped when an
		-- include list demands a specific spell.
		local include = UF.Auras:BuildSpellIDMap(DB.includeSpellIDs)
		local exclude = UF.Auras:BuildSpellIDMap(DB.excludeSpellIDs)

		if not include and not exclude then
			return true
		end

		local spellId = data.spellId
		if not spellId or not SUI.BlizzAPI.canaccessvalue(spellId) then
			return include == nil
		end

		if exclude and exclude[spellId] then
			return false
		end

		if include then
			return include[spellId] == true
		end

		return true
	end

	-- Classic filtering: Full spellId access for spell-specific filtering
	---@param unit UnitId
	---@param data UnitAuraInfo
	function element:ClassicAuraFilter(unit, data)
		local DB = self.DB
		local canAccess = SUI.BlizzAPI.canaccessvalue

		-- Spell ID lists apply on every version. Classic has no secret values,
		-- so spellId is always readable here.
		local include = UF.Auras:BuildSpellIDMap(DB.includeSpellIDs)
		local exclude = UF.Auras:BuildSpellIDMap(DB.excludeSpellIDs)
		if include or exclude then
			local listedSpellId = data.spellId
			if listedSpellId and canAccess(listedSpellId) then
				if exclude and exclude[listedSpellId] then
					return false
				end
				if include and not include[listedSpellId] then
					return false
				end
			elseif include then
				return false
			end
		end

		-- Guard: secret values from combat restriction predicates
		local duration = data.duration
		local canAccessDuration = canAccess(duration)
		local sourceUnit = data.sourceUnit
		local canAccessSource = canAccess(sourceUnit)
		local spellId = data.spellId
		local canAccessSpellId = canAccess(spellId)
		local isBossAura = data.isBossAura
		local canAccessBoss = canAccess(isBossAura)

		-- If using legacy custom filter, fall back to that
		if DB.useLegacyFilter then
			local isPlayer = canAccessSource and (sourceUnit == 'player' or sourceUnit == 'vehicle')
			local isBoss = canAccessBoss and isBossAura
			if (isPlayer or isBoss) and canAccessDuration and duration ~= 0 and duration <= 900 then
				return true
			end
			return false
		end

		-- Raider mode: always show boss auras regardless of role
		if DB.raiderMode and canAccessBoss and isBossAura then
			return true
		end

		-- Enhanced filtering with role presets
		if DB.filterMode == 'healer' then
			if canAccessSpellId and HealingSpells[spellId] then
				return true
			end
			if canAccessBoss and isBossAura then
				return true
			end
		elseif DB.filterMode == 'dps' then
			if canAccessSpellId and DamageOverTimeSpells[spellId] and canAccessSource and sourceUnit == 'player' then
				return true
			end
			if canAccessBoss and isBossAura then
				return true
			end
		elseif DB.filterMode == 'tank' then
			if canAccessSource and sourceUnit == 'player' and (canAccessSpellId and HealingSpells[spellId] or (canAccessDuration and duration <= 60)) then
				return true
			end
			if canAccessBoss and isBossAura then
				return true
			end
		elseif DB.filterMode == 'custom' then
			local isBoss = canAccessBoss and isBossAura
			local isPlayerCustom = canAccessSource and sourceUnit == 'player' and canAccessDuration and duration > 0 and duration <= DB.maxDuration
			if isBoss or isPlayerCustom then
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

	-- CustomFilter bridge between plugin and SUI filtering
	-- Plugin calls: CustomFilter(element, unit, bar, auraData, name)
	-- auraData is the full AuraData struct on Retail, nil on Classic
	element.CustomFilter = function(element, unit, bar, auraData, name)
		if SUI.IsRetail then
			return element:RetailAuraFilter(unit, auraData)
		end

		if not auraData then
			auraData = {
				spellId = bar.spellID,
				sourceUnit = bar.caster,
				duration = bar.duration,
				name = bar.spell,
			}
		end
		return element:CustomAuraFilter(unit, auraData)
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

	if SUI.IsRetail then
		local filterMode = DB.filterMode or 'healer'
		if filterMode == 'healer' then
			element.friendlyAuraType = 'HELPFUL|PLAYER|RAID_IN_COMBAT'
			element.enemyAuraType = 'HARMFUL|PLAYER'
		elseif filterMode == 'dps' then
			element.friendlyAuraType = 'HELPFUL|PLAYER'
			element.enemyAuraType = 'HARMFUL|PLAYER'
		elseif filterMode == 'tank' then
			element.friendlyAuraType = 'HELPFUL|PLAYER|RAID_IN_COMBAT'
			element.enemyAuraType = 'HARMFUL|PLAYER'
		elseif filterMode == 'custom' then
			element.friendlyAuraType = 'HELPFUL|PLAYER'
			element.enemyAuraType = 'HARMFUL|PLAYER'
		else
			element.friendlyAuraType = 'HELPFUL|PLAYER|RAID_IN_COMBAT'
			element.enemyAuraType = 'HARMFUL|PLAYER'
		end
	end
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
	OptionSet.args.SpellLists = {
		name = L['Spell lists'],
		type = 'group',
		order = 49,
		inline = true,
		args = {
			includeSpellIDs = {
				name = L['Always show these spell IDs'],
				desc = L['Separate each ID with a comma'],
				type = 'input',
				order = 1,
				width = 'full',
				get = function()
					return UF.CurrentSettings[unitName].elements.AuraBars.includeSpellIDs
				end,
				set = function(_, val)
					OptUpdate('includeSpellIDs', val)
				end,
			},
			excludeSpellIDs = {
				name = L['Never show these spell IDs'],
				desc = L['Separate each ID with a comma'],
				type = 'input',
				order = 2,
				width = 'full',
				get = function()
					return UF.CurrentSettings[unitName].elements.AuraBars.excludeSpellIDs
				end,
				set = function(_, val)
					OptUpdate('excludeSpellIDs', val)
				end,
			},
		},
	}

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
	local FilterGet, FilterSet
	if SUI.IsRetail then
		FilterGet = function()
			return false
		end
		FilterSet = function() end
	else
		local classicSettings = ElementSettings.classic or ElementSettings
		local classicRules = classicSettings.rules or {}
		local userAuraBars = UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.AuraBars
		local classicUserSetting = userAuraBars.classic or userAuraBars

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
				classicSettings.rules = classicSettings.rules or {}
				classicSettings.rules.duration = classicSettings.rules.duration or {}
				classicUserSetting.rules = classicUserSetting.rules or {}
				classicUserSetting.rules.duration = classicUserSetting.rules.duration or {}

				classicSettings.rules.duration[info[#info]] = key
				classicUserSetting.rules.duration[info[#info]] = key
			else
				classicSettings.rules = classicSettings.rules or {}
				classicUserSetting.rules = classicUserSetting.rules or {}

				classicSettings.rules[info[#info]] = key
				classicUserSetting.rules[info[#info]] = key
			end
			UF.Unit[unitName]:ElementUpdate('AuraBars')
		end
	end

	UF.Options:AddAuraFilters(unitName, OptionSet, FilterSet, FilterGet)

	-- Add whitelist/blacklist options (Classic only - already guarded in AddAuraWhitelistBlacklist)
	local wlClassicSettings = ElementSettings.classic or ElementSettings
	local wlUserAuraBars = UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.AuraBars
	local wlClassicUserSetting = wlUserAuraBars.classic or wlUserAuraBars

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
	-- Spell ID lists, same format and behaviour as aura groups
	includeSpellIDs = '',
	excludeSpellIDs = '',
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
	-- Retail filter config (base filter uses filterMode from Auras:Filter)
	retail = {
		filterMode = 'player_auras',
	},
	-- Classic filter config
	classic = {
		rules = {
			duration = {
				enabled = false,
				mode = 'exclude',
				maxTime = 900,
				minTime = 1,
			},
			showPlayers = true,
			isBossAura = true,
		},
		whitelist = {},
		blacklist = {},
	},
	config = {
		type = 'Auras',
		DisplayName = 'Aura Bars',
	},
}

UF.Elements:Register('AuraBars', Build, Update, Options, Settings)
