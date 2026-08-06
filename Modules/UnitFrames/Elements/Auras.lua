---@class SUI.UF
local UF = SUI.UF
local L = SUI.L

-- Group-based aura display for Retail 12.1+.
--
-- Blizzard owns aura creation, filtering, sorting and anchoring through
-- AuraContainer/AuraGroup. This element only describes what it wants and hands
-- that description over; it never iterates auras or touches secret values.
--
-- Each frame gets one container holding any number of user-defined groups. A
-- group is a filter plus display settings, so a single frame can show (for
-- example) defensives on one row and everything else on another.

local MAX_GROUPS = 5

---Resolve the aura filter string for a group's settings.
---@param groupDB table
---@return string
local function ResolveFilter(groupDB)
	local custom = groupDB.customFilter
	if custom and custom ~= '' then
		return custom
	end

	return UF.Auras:GetFilterString(groupDB.filterMode) or 'HELPFUL'
end

---Build the candidateFilters table Blizzard uses to narrow a group.
---Only includes keys the user actually set, since nil means "ignore" and
---false is a meaningful negation.
---@param groupDB table
---@return table?
local function BuildCandidateFilters(groupDB)
	local filters = {}
	local used = false

	if groupDB.onlyMine then
		filters.isFromPlayerOrPlayerPet = true
		used = true
	end
	if groupDB.onlyStealable then
		filters.isStealable = true
		used = true
	end
	if groupDB.maxDuration and groupDB.maxDuration > 0 then
		filters.maxDuration = groupDB.maxDuration
		used = true
	end

	local include = UF.Auras:BuildSpellIDMap(groupDB.includeSpellIDs)
	if include then
		filters.includeSpellIDs = include
		used = true
	end

	local exclude = UF.Auras:BuildSpellIDMap(groupDB.excludeSpellIDs)
	if exclude then
		filters.excludeSpellIDs = exclude
		used = true
	end

	if used then
		return UF.Auras:ValidateCandidateKeys(filters)
	end
end

---Translate a group's settings into the options table AddGroup expects.
---@param element table
---@param groupDB table
---@return table
local function BuildContainerGroupSettings(element, groupDB)
	local size = groupDB.size or 24

	return {
		maxFrameCount = groupDB.number or 10,
		size = size,
		sortMethod = UF.Auras:GetSortMethod(groupDB.sortMethod),
		sortDirection = UF.Auras:GetSortDirection(groupDB.sortDirection),
		candidateFilters = BuildCandidateFilters(groupDB),

		-- Sub-widgets. These are engine-drawn, so they stay correct on secret auras.
		showCount = groupDB.showCount ~= false,
		showDuration = groupDB.showDuration ~= false,
		showBuffBorder = groupDB.showBuffBorder,
		showDebuffBorder = groupDB.showDebuffBorder ~= false,
		showBuffIndicator = groupDB.showBuffIndicator,
		showDebuffIndicator = groupDB.showDebuffIndicator,
		showStealableBorder = groupDB.showStealableBorder,
		disableCooldown = groupDB.showCooldown == false,
		disableMouse = groupDB.clickThrough,
		cancelButton = groupDB.cancelButton,

		-- Engine-side duration coloring replaces the old expiring-glow polling.
		durationColors = UF.Auras:GetDurationColorCurve(groupDB.expiring),

		layout = {
			elementSpacing = groupDB.spacing or 2,
			lineSpacing = groupDB.lineSpacing or groupDB.spacing or 2,
			groupSpacing = groupDB.groupSpacing or 4,
			forceNewLine = groupDB.forceNewLine,
		},

		initializeFrame = function(_, button)
			UF.Auras:StyleButton(button, groupDB, element)
		end,
	}
end

---@param frame table
---@param DB table
local function Build(frame, DB)
	if not UF.Auras:HasNativeContainers() then
		return
	end

	local element = frame:CreateAuras({
		initialAnchor = DB.position and DB.position.anchor or 'TOPLEFT',
		growthX = DB.growthx or 'RIGHT',
		growthY = DB.growthy or 'UP',
		layoutLimit = DB.layoutLimit,
	})

	element.DB = DB
	element.groupKeys = {}
	frame.Auras = element

	-- Groups are attached at build time; they cannot be detached afterwards.
	UF.Auras:AttachGroups(element, DB, BuildContainerGroupSettings)
end

---@param frame table
---@param settings? table
local function Update(frame, settings)
	local element = frame.Auras
	if not element then
		return
	end

	local DB = settings or element.DB
	element.DB = DB

	if not DB.enabled then
		element:SetEnabled(false)
		return
	end

	-- A changed set of groups means the container has to be replaced, since
	-- AddGroup is one-way. Anything else is just a refresh.
	if UF.Auras:GroupsNeedRebuild(element, DB) then
		UF.Auras:RebuildContainer(frame, element, DB)
		return
	end

	element:SetEnabled(true)
	element:ForceUpdate()
end

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	UF.Auras:BuildGroupOptions(unitName, OptionSet, MAX_GROUPS)
end

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = true,
	config = {
		type = 'Auras',
		DisplayName = L['Auras'],
	},
	position = {
		anchor = 'TOPLEFT',
		relativeTo = 'Frame',
		x = 0,
		y = 0,
	},
	growthx = 'RIGHT',
	growthy = 'UP',
	groups = {
		['**'] = {
			enabled = false,
			name = '',
			filterMode = 'all_buffs',
			customFilter = '',
			number = 10,
			size = 24,
			spacing = 2,
			lineSpacing = 2,
			groupSpacing = 4,
			forceNewLine = false,
			sortMethod = 'expiration',
			sortDirection = 'normal',
			showCount = true,
			showDuration = true,
			showCooldown = true,
			showDebuffBorder = true,
			showBuffBorder = false,
			showBuffIndicator = false,
			showDebuffIndicator = false,
			showStealableBorder = false,
			clickThrough = false,
			onlyMine = false,
			onlyStealable = false,
			maxDuration = 0,
			includeSpellIDs = '',
			excludeSpellIDs = '',
			expiring = {
				enabled = false,
				threshold = 5,
				color = { 1, 0.1, 0.1, 1 },
			},
		},
		['1'] = {
			enabled = true,
			name = 'Buffs',
			filterMode = 'all_buffs',
			growthy = 'UP',
		},
		['2'] = {
			enabled = true,
			name = 'Debuffs',
			filterMode = 'all_debuffs',
			showDebuffBorder = true,
		},
	},
}

UF.Elements:Register('Auras', Build, Update, Options, Settings)
