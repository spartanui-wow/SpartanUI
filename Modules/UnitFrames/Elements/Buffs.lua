local UF = SUI.UF

---@param element any
---@param unit? UnitId
---@param isFullUpdate? boolean
local function updateSettings(element, unit, isFullUpdate)
	local DB = element.DB
	element.size = DB.size or 20
	element.initialAnchor = DB.position.anchor
	element.growthX = DB.growthx
	element.growthY = DB.growthy
	-- Disable showType in Retail to avoid secret aura API errors
	element.showType = not SUI.IsRetail and DB.showType
	element.num = DB.number or 10
	element.onlyShowPlayer = DB.onlyShowPlayer
	-- Set maxCols to avoid secret value errors from GetWidth() in Retail
	element.maxCols = DB.number / DB.rows
end

---@param element any
local function SizeChange(element)
	local DB = element.DB
	local w = (DB.number / DB.rows)
	if w < 1.5 then
		w = 1.5
	end
	element:SetSize((DB.size + DB.spacing) * w, (DB.spacing + DB.size) * DB.rows)
end

---@param frame table
---@param DB table
local function Build(frame, DB)
	--Buff Icons
	local element = CreateFrame('Frame', frame.unitOnCreate .. 'Buffs', frame.raised)
	element.PostUpdateButton = function(self, button, unit, data, position)
		button.data = data
		button.unit = unit
		-- Update duration display setting from element DB
		button.showDuration = self.DB and self.DB.showDuration
	end
	element.PostCreateButton = function(self, button)
		UF.Auras:PostCreateButton('Buffs', button)
	end

	---@param unit UnitId
	---@param data UnitAuraInfo
	local FilterAura = function(element, unit, data)
		return UF.Auras:Filter(element, unit, data)
	end
	local PreUpdate = function(self)
		updateSettings(element)
		-- Update sort function based on settings
		local sortMode = element.DB and element.DB.sortMode
		element.SortBuffs = UF.Auras:CreateSortFunction(sortMode)
	end

	-- Set FilterAura for both Retail and Classic
	element.FilterAura = FilterAura
	if not SUI.IsRetail then
		element.displayReasons = {}
	end
	element.PreUpdate = PreUpdate
	element.SizeChange = SizeChange
	frame.Buffs = element
end

---@param frame table
---@param settings? table
local function Update(frame, settings)
	local element = frame.Buffs
	local DB = settings or element.DB

	if DB.enabled then
		element:Show()
	else
		element:Hide()
	end

	updateSettings(element)
end

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	local L = SUI.L
	local ElementSettings = UF.CurrentSettings[unitName].elements.Buffs

	local function OptUpdate(option, val)
		--Update memory
		UF.CurrentSettings[unitName].elements.Buffs[option] = val
		--Update the DB
		UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.Buffs[option] = val
		--Update the screen
		UF.Unit[unitName]:ElementUpdate('Buffs')
	end

	OptionSet.args.Display = OptionSet.args.Display or {
		name = L['Display'],
		type = 'group',
		order = 10,
		inline = true,
		args = {},
	}

	-- Visual settings (size, count, layout)
	OptionSet.args.Display.args.size = {
		name = L['Icon Size'],
		desc = L['Size of each buff icon'],
		type = 'range',
		order = 1,
		min = 10,
		max = 60,
		step = 1,
		get = function()
			return ElementSettings.size or 20
		end,
		set = function(_, val)
			OptUpdate('size', val)
		end,
	}

	OptionSet.args.Display.args.number = {
		name = L['Icon Count'],
		desc = L['Maximum number of buffs to display'],
		type = 'range',
		order = 2,
		min = 1,
		max = 40,
		step = 1,
		get = function()
			return ElementSettings.number or 10
		end,
		set = function(_, val)
			OptUpdate('number', val)
		end,
	}

	OptionSet.args.Display.args.rows = {
		name = L['Rows'],
		desc = L['Number of rows for buff icons'],
		type = 'range',
		order = 3,
		min = 1,
		max = 10,
		step = 1,
		get = function()
			return ElementSettings.rows or 2
		end,
		set = function(_, val)
			OptUpdate('rows', val)
		end,
	}

	OptionSet.args.Display.args.spacing = {
		name = L['Spacing'],
		desc = L['Space between buff icons'],
		type = 'range',
		order = 4,
		min = 0,
		max = 10,
		step = 1,
		get = function()
			return ElementSettings.spacing or 1
		end,
		set = function(_, val)
			OptUpdate('spacing', val)
		end,
	}

	OptionSet.args.Display.args.growthx = {
		name = L['Horizontal Growth'],
		desc = L['Direction buffs grow horizontally'],
		type = 'select',
		order = 5,
		values = {
			LEFT = L['Left'],
			RIGHT = L['Right'],
		},
		get = function()
			return ElementSettings.growthx or 'RIGHT'
		end,
		set = function(_, val)
			OptUpdate('growthx', val)
		end,
	}

	OptionSet.args.Display.args.growthy = {
		name = L['Vertical Growth'],
		desc = L['Direction buffs grow vertically'],
		type = 'select',
		order = 6,
		values = {
			UP = L['Up'],
			DOWN = L['Down'],
		},
		get = function()
			return ElementSettings.growthy or 'DOWN'
		end,
		set = function(_, val)
			OptUpdate('growthy', val)
		end,
	}

	-- Duration text only works in Classic (Retail uses cooldown spiral instead due to secret values)
	OptionSet.args.Display.args.showDuration = {
		name = L['Show Duration'],
		desc = SUI.IsRetail and L['Duration text unavailable in Retail - cooldown spiral shows duration instead'] or L['Display remaining duration text on aura icons'],
		type = 'toggle',
		order = 5,
		disabled = SUI.IsRetail,
		get = function()
			return ElementSettings.showDuration
		end,
		set = function(_, val)
			OptUpdate('showDuration', val)
		end,
	}

	OptionSet.args.Display.args.sortMode = {
		name = L['Sort Mode'],
		desc = SUI.IsRetail and L['Sort by priority (player auras first). Time/Name sorting unavailable in Retail.']
			or L['How to sort auras. Priority sorts by importance (boss > dispellable > player), Time sorts by remaining duration, Name sorts alphabetically.'],
		type = 'select',
		order = 6,
		values = SUI.IsRetail and {
			priority = L['Priority (Recommended)'],
		} or {
			priority = L['Priority (Recommended)'],
			time = L['Time Remaining'],
			name = L['Alphabetical'],
		},
		get = function()
			return ElementSettings.sortMode or 'priority'
		end,
		set = function(_, val)
			OptUpdate('sortMode', val)
		end,
	}

	if not SUI.IsRetail then
		-- Classic: Only Show Your Auras toggle (uses rules system)
		OptionSet.args.Display.args.onlyShowPlayer = {
			name = L['Only Show Your Auras'],
			desc = L['Only display buffs cast by you'],
			type = 'toggle',
			order = 7,
			get = function()
				return ElementSettings.onlyShowPlayer
			end,
			set = function(_, val)
				OptUpdate('onlyShowPlayer', val)
			end,
		}
	end

	-- Retail: Prominent Filter Mode radio selects (inline group on main element page)
	if SUI.IsRetail then
		OptionSet.args.FilterMode = {
			name = L['Filter Mode'],
			type = 'group',
			order = 50,
			inline = true,
			args = {
				desc = {
					type = 'description',
					name = 'WoW 12.0.1 provides 14+ filter modes for precise aura control. Select a preset below or use a custom filter string.',
					order = 0,
					fontSize = 'small',
				},
				filterMode = {
					name = L['Filter Preset'],
					desc = L['Select a predefined filter configuration'],
					type = 'select',
					order = 1,
					width = 'full',
					values = {
						blizzard_default = L['Blizzard Default (Recommended)'],
						all_buffs = L['All Buffs'],
						player_buffs = L['Player Buffs Only'],
						raid_buffs = L['Raid Buffs'],
						healing_mode = L['Healing Mode (HoTs)'],
						external_defensives = L['External Defensives'],
						big_defensives = L['Major Defensives'],
						important_buffs = L['Important Buffs'],
					},
					get = function()
						local retail = ElementSettings.retail
						return retail and retail.filterMode or 'blizzard_default'
					end,
					set = function(_, val)
						ElementSettings.retail = ElementSettings.retail or {}
						ElementSettings.retail.filterMode = val
						ElementSettings.retail.customFilter = nil -- Clear custom when selecting preset

						local userSettings = UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.Buffs
						userSettings.retail = userSettings.retail or {}
						userSettings.retail.filterMode = val
						userSettings.retail.customFilter = nil

						UF.Unit[unitName]:ElementUpdate('Buffs')
					end,
				},
				activeFilter = {
					type = 'description',
					name = function()
						local retail = ElementSettings.retail
						local customFilter = retail and retail.customFilter
						if customFilter and customFilter ~= '' then
							return '|cFF00FF00Active Filter:|r ' .. customFilter
						end

						local filterMode = retail and retail.filterMode or 'blizzard_default'
						local filterString = UF.Auras.FILTER_PRESETS[filterMode] or 'HELPFUL'
						return '|cFF808080Active Filter:|r ' .. filterString
					end,
					order = 1.5,
					fontSize = 'small',
				},
				customFilterHeader = {
					name = L['Advanced: Custom Filter String'],
					type = 'header',
					order = 5,
				},
				customFilter = {
					name = L['Filter String'],
					desc = L['Advanced: Enter raw filter string (e.g., "HELPFUL|RAID|PLAYER"). Overrides preset selection. Leave blank to use preset above.'],
					type = 'input',
					width = 'full',
					order = 6,
					get = function()
						local retail = ElementSettings.retail
						return retail and retail.customFilter or ''
					end,
					set = function(_, val)
						ElementSettings.retail = ElementSettings.retail or {}
						local userSettings = UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.Buffs
						userSettings.retail = userSettings.retail or {}

						-- Check if custom string matches any preset
						local matchedPreset = nil
						if val and val ~= '' then
							for presetKey, presetFilter in pairs(UF.Auras.FILTER_PRESETS) do
								if val == presetFilter then
									matchedPreset = presetKey
									break
								end
							end
						end

						if matchedPreset then
							-- User entered a preset string - switch to that preset
							ElementSettings.retail.filterMode = matchedPreset
							ElementSettings.retail.customFilter = nil
							userSettings.retail.filterMode = matchedPreset
							userSettings.retail.customFilter = nil
							SUI:Print('Filter matched preset: |cFF00FF00' .. matchedPreset .. '|r - switched to preset mode')
						else
							-- Actual custom string
							ElementSettings.retail.customFilter = val ~= '' and val or nil
							userSettings.retail.customFilter = val ~= '' and val or nil
						end

						UF.Unit[unitName]:ElementUpdate('Buffs')
					end,
				},
				filtersReference = {
					type = 'description',
					order = 7,
					fontSize = 'small',
					name = 'Available Filters:\nHELPFUL, HARMFUL, PLAYER, RAID, RAID_IN_COMBAT, RAID_PLAYER_DISPELLABLE, EXTERNAL_DEFENSIVE, BIG_DEFENSIVE, CROWD_CONTROL, CANCELABLE, NOT_CANCELABLE, INCLUDE_NAME_PLATE_ONLY, MAW, IMPORTANT\n\nCombine with | (pipe) character, e.g., "HELPFUL|RAID|PLAYER"',
				},
			},
		}
	end
end

---@type SUI.UF.Elements.Settings
local Settings = {
	number = 10,
	size = 20,
	spacing = 1,
	showType = true,
	showDuration = true,
	sortMode = 'priority',
	onlyShowPlayer = false,
	width = false,
	growthx = 'RIGHT',
	growthy = 'DOWN',
	rows = 2,
	position = {
		anchor = 'TOPLEFT',
		relativePoint = 'BOTTOMLEFT',
	},
	config = {
		type = 'Auras',
	},
	-- Retail filter config
	retail = {
		filterMode = 'blizzard_default',
	},
	-- Classic filter config
	classic = {
		rules = {
			duration = {
				enabled = true,
				maxTime = 180,
				minTime = 1,
			},
			isBossAura = true,
			showPlayers = true,
			isFromPlayerOrPlayerPet = false,
			isHelpful = true,
			isHarmful = false,
			isStealable = false,
			isRaid = false,
			nameplateShowPersonal = false,
			nameplateShowAll = false,
			isNameplateOnly = false,
			canApplyAura = false,
		},
		whitelist = {},
		blacklist = {},
	},
}
UF.Elements:Register('Buffs', Build, Update, Options, Settings)
