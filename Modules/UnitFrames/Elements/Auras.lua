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

local MAX_GROUPS = UF.Auras.MAX_GROUPS

---Translate a group's settings into the options table AddGroup expects.
---@param element table
---@param groupDB table
---@return table
local function BuildContainerGroupSettings(element, groupDB)
	-- Saved settings can hold a non-number where a number is expected, since
	-- the shared element defaults carry sub-tables that a merge can leave
	-- behind. Blizzard's aura APIs will not take those.
	local function number(value, fallback)
		return type(value) == 'number' and value or fallback
	end

	local size = number(groupDB.size, 24)

	return {
		maxFrameCount = number(groupDB.number, 10),
		size = size,
		sortMethod = UF.Auras:GetSortMethod(groupDB.sortMethod),
		sortDirection = UF.Auras:GetSortDirection(groupDB.sortDirection),
		candidateFilters = UF.Auras:BuildCandidateFilters(groupDB),

		-- Sub-widgets. These are engine-drawn, so they stay correct on secret auras.
		showCount = groupDB.showCount ~= false,
		showDuration = groupDB.showDuration ~= false,
		showBuffBorder = groupDB.showBuffBorder,
		showDebuffBorder = groupDB.showDebuffBorder ~= false,
		showBuffIndicator = groupDB.showBuffIndicator,
		showDebuffIndicator = groupDB.showDebuffIndicator,
		showStealableBorder = groupDB.showStealableBorder,
		dispelBorderStyle = groupDB.dispelBorderStyle,
		disableCooldown = groupDB.showCooldown == false,
		disableMouse = groupDB.clickThrough,
		cancelButton = groupDB.cancelButton,

		-- Engine-side duration coloring replaces the old expiring-glow polling.
		durationColors = UF.Auras:GetDurationColorCurve(groupDB.expiring),

		-- Text placement and styling, read back in CreateAuraButton.
		durationText = groupDB.durationText,
		stackText = groupDB.stackText,

		layout = {
			elementSpacing = number(groupDB.spacing, 2),
			lineSpacing = number(groupDB.lineSpacing, number(groupDB.spacing, 2)),
			groupSpacing = number(groupDB.groupSpacing, 4),
			forceNewLine = groupDB.forceNewLine,
		},

		-- Blizzard calls this with just the button. oUF's own default gets
		-- (element, options, button) only because oUF wraps it in a closure;
		-- an initializeFrame supplied directly is called raw.
		-- CreateButton, not initializeFrame. Supplying initializeFrame replaces
		-- the library's own button setup, which is what gives a button its
		-- size, icon, cooldown and text - without it the buttons exist but
		-- draw nothing. This hook runs instead of that default, so it calls it
		-- first and then applies our own styling.
		CreateButton = function(auraElement, options, button)
			UF.Auras:CreateAuraButton(auraElement, options, button)
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
		-- How far a row runs before wrapping. Without this the container falls
		-- back to the frame width, so icons wrap wherever the frame happens to
		-- end rather than after the configured number of them.
		layoutLimit = DB.layoutLimit or UF.Auras:GetLayoutLimit(DB),
	})

	element.DB = DB
	element.groupKeys = {}
	frame.AuraGroups = element

	-- CreateAuras only sets the flow layout origin, which controls how buttons
	-- flow inside the container. The container itself still has to be anchored.
	UF.Auras:PositionContainer(element, frame, DB)

	-- Groups are attached at build time; they cannot be detached afterwards.
	UF.Auras:AttachGroups(element, DB, BuildContainerGroupSettings)

	-- oUF's own 'Auras' meta element is what pushes the unit into every
	-- container on this frame; without it they never receive a unit and stay
	-- empty. It drives all containers at once, so enable it only once.
	UF.Auras:ScheduleContainerStateSync(frame)
end

---@param frame table
---@param settings? table
local function Update(frame, settings)
	local element = frame.AuraGroups
	if not element then
		return
	end

	local DB = settings or element.DB
	element.DB = DB

	if not DB.enabled then
		element:SetEnabled(false)
		return
	end

	-- Re-anchor every update. The container is a plain child frame and anything
	-- that clears its points - a profile change, a preset swap, the layout
	-- being rebuilt - would otherwise leave it unanchored for good, which shows
	-- as auras simply not appearing.
	UF.Auras:PositionContainer(element, frame, DB)

	-- Changed settings mean the live groups no longer match; repoint them.
	-- AddGroup is one-way, so groups are never recreated, only re-aimed.
	if UF.Auras:GroupsNeedRebuild(element, DB) then
		UF.Auras:RepointGroups(frame, element, DB)
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
		-- The container anchors and sizes itself through the flow layout API.
		-- Letting the generic element pipeline call ClearAllPoints/SetPoint/SetSize
		-- on it fights that and breaks the layout.
		NoBulkUpdate = true,
	},
	position = {
		anchor = 'TOPLEFT',
		relativeTo = 'Frame',
		x = 0,
		y = 0,
	},
	growthx = 'RIGHT',
	growthy = 'UP',
	-- Only the groups that differ from GROUP_DEFAULTS are stored. Everything
	-- else is filled in by UF.Auras:ResolveGroup at read time.
	groups = {
		slot1 = {
			enabled = true,
			name = 'Buffs',
			filterMode = 'all_buffs',
		},
		slot2 = {
			enabled = true,
			name = 'Debuffs',
			filterMode = 'all_debuffs',
			showDebuffBorder = true,
		},
	},
}

UF.Elements:Register('AuraGroups', Build, Update, Options, Settings)
