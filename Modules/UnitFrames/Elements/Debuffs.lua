local UF = SUI.UF

---@param element any
---@param unit? UnitId
---@param isFullUpdate? boolean
local function updateSettings(element, unit, isFullUpdate)
	local DB = element.DB
	element.size = DB.size or 20
	element.initialAnchor = DB.position.anchor
	element['growth-x'] = DB.growthx
	element['growth-y'] = DB.growthy
	-- Buffs.spacing = DB.spacing
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
	--Debuff Icons
	local element = CreateFrame('Frame', frame.unitOnCreate .. 'Debuffs', frame.raised)
	element.PostUpdateButton = function(self, button, unit, data, position)
		button.data = data
		button.unit = unit
		-- Update duration display setting from element DB
		button.showDuration = self.DB and self.DB.showDuration
	end
	element.PostCreateButton = function(self, button)
		UF.Auras:PostCreateButton('Debuffs', button)
	end

	---@param unit UnitId
	---@param data UnitAuraInfo
	local FilterAura = function(element, unit, data)
		UF:debug('Debuffs FilterAura called for unit: ' .. tostring(unit) .. ', auraID: ' .. tostring(data and data.auraInstanceID or 'nil'))
		return UF.Auras:Filter(element, unit, data, element.DB.rules)
	end
	local PreUpdate = function(self)
		updateSettings(element)
		-- Update sort function based on settings
		local sortMode = element.DB and element.DB.sortMode
		element.SortDebuffs = UF.Auras:CreateSortFunction(sortMode)
	end

	-- Set FilterAura for both Retail and Classic
	element.FilterAura = FilterAura
	if not SUI.IsRetail then
		element.displayReasons = {}
	end
	element.PreUpdate = PreUpdate
	element.SizeChange = SizeChange

	frame.Debuffs = element
end

---@param frame table
---@param settings? table
local function Update(frame, settings)
	local element = frame.Debuffs
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
	local ElementSettings = UF.CurrentSettings[unitName].elements.Debuffs

	local function OptUpdate(option, val)
		--Update memory
		UF.CurrentSettings[unitName].elements.Debuffs[option] = val
		--Update the DB
		UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.Debuffs[option] = val
		--Update the screen
		UF.Unit[unitName]:ElementUpdate('Debuffs')
	end

	OptionSet.args.Display = OptionSet.args.Display or {
		name = L['Display'],
		type = 'group',
		order = 10,
		inline = true,
		args = {},
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
end

---@type SUI.UF.Elements.Settings
local Settings = {
	number = 10,
	size = 20,
	spacing = 1,
	width = false,
	ShowBoss = true,
	showType = true,
	showDuration = true, -- Show duration text on aura icons
	sortMode = 'priority', -- Sort mode: 'priority', 'time', 'name', or nil for default
	growthx = 'LEFT',
	growthy = 'UP',
	rows = 2,
	position = {
		anchor = 'TOPRIGHT',
		relativePoint = 'BOTTOMRIGHT',
	},
	rules = {
		duration = {
			enabled = true,
			maxTime = 180,
			minTime = 1,
		},
		-- Classic filters (preserved)
		isHarmful = true,
		isBossAura = true,
		-- Retail boolean filters (12.0.0+)
		isFromPlayerOrPlayerPet = false,
		isHelpful = false,
		isStealable = false,
		isRaid = false,
		nameplateShowPersonal = false,
		nameplateShowAll = false,
		isNameplateOnly = false,
		canApplyAura = false,
	},
	config = {
		type = 'Auras',
	},
}
UF.Elements:Register('Debuffs', Build, Update, Options, Settings)
