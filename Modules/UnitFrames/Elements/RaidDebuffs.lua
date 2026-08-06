local UF = SUI.UF
local L = SUI.L

-- ============================================================
-- RAID DEBUFFS ELEMENT (Retail + Classic)
-- Shows raid-relevant debuffs with full layout control
-- Uses HARMFUL|RAID filter via the standard aura filter system
-- ============================================================

---@param element any
local function updateSettings(element)
	local DB = element.DB
	element.size = DB.size or 12
	element.initialAnchor = DB.position and DB.position.anchor or 'BOTTOMLEFT'
	element.growthX = DB.growthx or 'RIGHT'
	element.growthY = DB.growthy or 'DOWN'
	element.spacing = DB.spacing or 1
	element.num = DB.number or 3
	-- Set maxCols to avoid secret value errors from GetWidth() in Retail
	local rows = DB.rows or 1
	element.maxCols = (DB.number or 3) / rows
end

---@param element any
local function SizeChange(element)
	local DB = element.DB
	local cols = (DB.number or 3) / (DB.rows or 1)
	if cols < 1.5 then
		cols = 1.5
	end
	local size = DB.size or 12
	local spacing = DB.spacing or 1
	element:SetSize((size + spacing) * cols, (spacing + size) * (DB.rows or 1))
end

---@param frame table
---@param DB table
local function Build(frame, DB)
	local element = CreateFrame('Frame', frame.unitOnCreate .. 'RaidDebuffs', frame.raised or frame)

	element.PostUpdateButton = function(self, button, unit, data, position)
		button.data = data
		button.unit = unit
		button.showDuration = false
	end

	element.PostCreateButton = function(self, button)
		UF.Auras:PostCreateButton('Debuffs', button)
	end

	---@param unit UnitId
	---@param data UnitAuraInfo
	local FilterAura = function(element, unit, data)
		local customElement = {
			DB = {
				retail = {
					filterMode = 'raid_debuffs',
				},
				classic = element.DB.classic or {},
			},
		}
		return UF.Auras:Filter(customElement, unit, data)
	end

	local PreUpdate = function(self)
		updateSettings(element)
		element.SortDebuffs = UF.Auras:CreateSortFunction('priority')
	end

	element.FilterAura = FilterAura
	if not SUI.IsRetail then
		element.displayReasons = {}
	end
	element.PreUpdate = PreUpdate
	element.SizeChange = SizeChange

	-- Hide in PvP whenever something tries to show this element
	element:HookScript('OnShow', function(self)
		local retail = DB.retail
		if retail and retail.disableInPvP ~= false then
			local _, instanceType = IsInInstance()
			if instanceType == 'pvp' or instanceType == 'arena' then
				self:Hide()
			end
		end
	end)

	frame.RaidDebuffs = element
end

---@param frame table
---@param settings? table
local function Update(frame, settings)
	local element = frame.RaidDebuffs
	local DB = settings or element.DB

	-- Hide in PvP if configured
	local disableInPvP = DB.retail and DB.retail.disableInPvP ~= false
	local inPvP = false
	if disableInPvP then
		local _, instanceType = IsInInstance()
		inPvP = instanceType == 'pvp' or instanceType == 'arena'
	end

	if DB.enabled and not inPvP then
		element:Show()
	else
		element:Hide()
	end

	updateSettings(element)
end

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	-- Retail covers raid debuffs with an AuraGroups group instead.
	if SUI.IsRetail then
		return
	end

	local ElementSettings = UF.CurrentSettings[unitName].elements.RaidDebuffs

	local function OptUpdate(option, val)
		UF.CurrentSettings[unitName].elements.RaidDebuffs[option] = val
		UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.RaidDebuffs[option] = val
		UF.Unit[unitName]:ElementUpdate('RaidDebuffs')
	end

	OptionSet.args.Display = {
		name = L['Display'],
		type = 'group',
		order = 10,
		inline = true,
		args = {
			size = {
				name = L['Icon Size'],
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
			},
			number = {
				name = L['Icon Count'],
				type = 'range',
				order = 2,
				min = 1,
				max = 10,
				step = 1,
				get = function()
					return ElementSettings.number or 3
				end,
				set = function(_, val)
					OptUpdate('number', val)
				end,
			},
			rows = {
				name = L['Rows'],
				type = 'range',
				order = 3,
				min = 1,
				max = 5,
				step = 1,
				get = function()
					return ElementSettings.rows or 1
				end,
				set = function(_, val)
					OptUpdate('rows', val)
				end,
			},
			spacing = {
				name = L['Spacing'],
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
			},
			growthx = {
				name = L['Horizontal Growth'],
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
			},
			growthy = {
				name = L['Vertical Growth'],
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
			},
			showCooldown = {
				name = L['Show cooldown spiral'],
				type = 'toggle',
				order = 7,
				get = function()
					return ElementSettings.showCooldown ~= false
				end,
				set = function(_, val)
					OptUpdate('showCooldown', val)
				end,
			},
		},
	}

	OptionSet.args.filterInfo = {
		name = L['Filter'],
		type = 'group',
		inline = true,
		order = 20,
		args = {
			filterDesc = {
				name = L['Filter: RAID (locked)\n\nShows raid-relevant debuffs that Blizzard flags for raid awareness - boss mechanics, crowd control, and other important effects. Uses the HARMFUL|RAID filter which cannot be changed.'],
				type = 'description',
				order = 1,
				fontSize = 'medium',
				width = 'full',
			},
		},
	}
end

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = true,
	size = 12,
	number = 3,
	rows = 1,
	spacing = 1,
	growthx = 'RIGHT',
	growthy = 'DOWN',
	showCooldown = true,
	position = {
		anchor = 'BOTTOMLEFT',
		relativePoint = 'BOTTOMLEFT',
		x = 1,
		y = 1,
	},
	retail = {
		filterMode = 'raid_debuffs',
		disableInPvP = true,
	},
	classic = {
		rules = {
			duration = false,
			caster = false,
		},
	},
	config = {
		type = 'Auras',
		DisplayName = 'Raid Debuffs',
	},
}

UF.Elements:Register('RaidDebuffs', Build, Update, Options, Settings)
