local UF = SUI.UF
local L = SUI.L

-- ============================================================
-- RAID DEBUFFS ELEMENT (Retail + Classic)
-- Shows a single large center icon for the highest priority raid debuff
--
-- Uses modern C_UnitAuras filter system (HARMFUL|RAID) instead of legacy plugin
-- This is essentially "Debuffs with num=1 and RAID filter" but with custom positioning
-- ============================================================

---@param element any
---@param unit? UnitId
---@param isFullUpdate? boolean
local function updateSettings(element, unit, isFullUpdate)
	local DB = element.DB
	element.size = DB.size or 32
	element.num = 1 -- Always show only 1 debuff (highest priority)
	element.spacing = 0
	element.initialAnchor = 'CENTER'
	element.growthX = 'RIGHT'
	element.growthY = 'DOWN'
end

---@param frame table
---@param DB table
local function Build(frame, DB)
	-- Create debuff display using oUF's Debuffs system
	local element = CreateFrame('Frame', frame.unitOnCreate .. 'RaidDebuffs', frame.raised or frame)

	element.PostUpdateButton = function(self, button, unit, data, position)
		button.data = data
		button.unit = unit
		-- Always show duration via cooldown spiral (Retail-safe)
		button.showDuration = false -- Text duration disabled (uses cooldown spiral instead)
	end

	element.PostCreateButton = function(self, button)
		-- Use same button creation as Debuffs element
		UF.Auras:PostCreateButton('Debuffs', button)
	end

	---@param unit UnitId
	---@param data UnitAuraInfo
	local FilterAura = function(element, unit, data)
		-- Override filter to use HARMFUL|RAID specifically for raid debuffs
		local customElement = {
			DB = {
				retail = {
					filterMode = 'raid_debuffs', -- Uses HARMFUL|RAID filter
				},
				classic = element.DB.classic or {},
			},
		}
		return UF.Auras:Filter(customElement, unit, data)
	end

	local PreUpdate = function(self)
		updateSettings(element)
		-- Sort by priority (highest priority shown first)
		element.SortDebuffs = UF.Auras:CreateSortFunction('priority')
	end

	-- Set FilterAura for both Retail and Classic
	element.FilterAura = FilterAura
	element.PreUpdate = PreUpdate

	-- Position manually (not using SizeChange from Debuffs since we're always 1 icon)
	element:SetSize(DB.size or 32, DB.size or 32)
	local anchor = DB.position and DB.position.anchor or 'CENTER'
	local x = DB.position and DB.position.x or 0
	local y = DB.position and DB.position.y or 0
	element:SetPoint(anchor, frame, anchor, x, y)

	frame.RaidDebuffs = element
end

---@param frame table
---@param settings? table
local function Update(frame, settings)
	local element = frame.RaidDebuffs
	local DB = settings or element.DB

	if DB.enabled then
		element:Show()
	else
		element:Hide()
	end

	updateSettings(element)

	-- Update position
	element:ClearAllPoints()
	local anchor = DB.position and DB.position.anchor or 'CENTER'
	local x = DB.position and DB.position.x or 0
	local y = DB.position and DB.position.y or 0
	element:SetPoint(anchor, frame, anchor, x, y)

	-- Update size
	element:SetSize(DB.size or 32, DB.size or 32)

	-- Force oUF to update the element
	if element.ForceUpdate then
		element:ForceUpdate()
	end
end

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	local ElementSettings = UF.CurrentSettings[unitName].elements.RaidDebuffs

	local function OptUpdate(option, val)
		UF.CurrentSettings[unitName].elements.RaidDebuffs[option] = val
		UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.RaidDebuffs[option] = val
		UF.Unit[unitName]:ElementUpdate('RaidDebuffs')
	end

	OptionSet.args.size = {
		name = L['Size'],
		desc = L['Size of the raid debuff icon'],
		type = 'range',
		order = 1,
		min = 16,
		max = 64,
		step = 1,
		get = function()
			return ElementSettings.size or 32
		end,
		set = function(_, val)
			OptUpdate('size', val)
		end,
	}

	OptionSet.args.info = {
		name = L['About Raid Debuffs'],
		type = 'description',
		order = 2,
		fontSize = 'medium',
		width = 'full',
		get = function()
			return L["Shows the highest priority raid-relevant debuff (boss mechanics, crowd control, etc.) using WoW's RAID filter. This automatically shows important debuffs that Blizzard flags for raid awareness."]
		end,
	}
end

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = false,
	size = 32,
	position = {
		anchor = 'CENTER',
		x = 0,
		y = 0,
	},
	-- Retail filter config (uses HARMFUL|RAID)
	retail = {
		filterMode = 'raid_debuffs',
	},
	-- Classic filter config (same logic, different APIs)
	classic = {
		rules = {
			duration = false,
			caster = false,
		},
	},
	config = {
		type = 'Indicator',
		DisplayName = 'Raid Debuffs',
	},
}

UF.Elements:Register('RaidDebuffs', Build, Update, Options, Settings)
