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
		-- Text duration disabled (cooldown spiral used instead)
		button.showDuration = false
		if button.cooldown then
			if DB.showCooldown ~= false then
				button.cooldown:Show()
			else
				button.cooldown:Hide()
			end
		end
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

	-- Hide in PvP if the retail filter config says so
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

	OptionSet.args.general = {
		name = L['General'],
		type = 'group',
		inline = true,
		order = 1,
		args = {
			size = {
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
			},
			showCooldown = {
				name = L['Show cooldown spiral'],
				desc = L['Show the duration countdown spiral on the icon'],
				type = 'toggle',
				order = 2,
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
		order = 2,
		args = {
			filterDesc = {
				name = L['Filter: RAID (locked)\n\nShows the single highest priority raid-relevant debuff - boss mechanics, crowd control, and other effects that Blizzard flags for raid awareness. Uses the HARMFUL|RAID filter which cannot be changed.'],
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
	enabled = false,
	size = 32,
	showCooldown = true,
	position = {
		anchor = 'CENTER',
		x = 0,
		y = 0,
	},
	-- Retail filter config (uses HARMFUL|RAID)
	retail = {
		filterMode = 'raid_debuffs',
		disableInPvP = true,
	},
	-- Classic filter config (same logic, different APIs)
	classic = {
		rules = {
			duration = false,
			caster = false,
		},
	},
	config = {
		type = 'Auras',
		NoGenericOptions = true,
		DisplayName = 'Raid Debuffs',
	},
}

UF.Elements:Register('RaidDebuffs', Build, Update, Options, Settings)
