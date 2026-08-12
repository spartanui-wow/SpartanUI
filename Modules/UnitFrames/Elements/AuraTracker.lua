---@class SUI.UF
local UF = SUI.UF
local L = SUI.L

-- Per-spell aura tracking for Retail 12.1+.
--
-- Where AuraGroups answers "what is on this unit", this answers "is this
-- specific thing up, and where do I want to see it". Each tracked spell gets
-- an AuraSlot: a group capped at one aura, which unlike a group can be
-- anchored wherever the user wants.
--
-- Replaces the old AuraDesigner, AuraWatch and HotsListing paths, which all
-- did the same job through per-aura Lua filtering and manual button creation.

local MAX_SLOTS = UF.Auras.MAX_TRACKER_SLOTS

---Build the settings for one tracked spell's slot.
---@param element table
---@param entry table
---@return table
local function BuildSlotSettings(element, entry)
	return {
		maxFrameCount = 1,
		size = type(entry.size) == 'number' and entry.size or 26,

		-- The spell ID list is what pins this slot to one aura. Built through
		-- the shared filter builder so every aura display filters alike.
		candidateFilters = UF.Auras:BuildCandidateFilters({
			includeSpellIDs = entry.spellId,
		}),

		showCount = entry.showStacks ~= false,
		showDuration = entry.showDuration ~= false,
		disableCooldown = entry.showSwipe == false,
		disableMouse = true,

		durationColors = UF.Auras:GetDurationColorCurve(entry.expiring),

		-- Called with just the button; see the note in Elements/Auras.lua.
		-- CreateButton rather than initializeFrame: supplying initializeFrame
		-- replaces the library's own button setup, leaving a button with no
		-- icon and no size. See the note in Elements/Auras.lua.
		CreateButton = function(auraElement, options, button)
			UF.Auras:CreateAuraButton(auraElement, options, button)
			UF.Auras:StyleTrackerButton(button, entry, element)
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
		initialAnchor = 'CENTER',
	})

	element.DB = DB
	element.slotKeys = {}
	element.trackerOwner = frame
	frame.AuraTracker = element

	-- The container is just the host for the slots; each slot is anchored
	-- individually in RefreshSlots. Anchor the host over the frame so slots
	-- placed at CENTER land on the frame rather than at an arbitrary origin.
	element:ClearAllPoints()
	element:SetAllPoints(frame)

	-- Draw above artwork overlays, as the old per-spell indicators did.
	if frame.raised and frame.raised.GetFrameLevel then
		element:SetFrameLevel(frame.raised:GetFrameLevel() + 1)
	end

	UF.Auras:AttachSlots(element, DB, BuildSlotSettings)

	-- Containers only receive their unit through oUF's 'Auras' meta element.
	UF.Auras:ScheduleContainerStateSync(frame)
end

---@param frame table
---@param settings? table
local function Update(frame, settings)
	local element = frame.AuraTracker
	if not element then
		return
	end

	local DB = settings or element.DB
	element.DB = DB

	if not DB.enabled then
		element:SetEnabled(false)
		return
	end

	UF.Auras:RefreshSlots(element, DB)

	element:SetEnabled(true)
	element:ForceUpdate()
end

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	UF.Auras:BuildTrackerOptions(unitName, OptionSet, MAX_SLOTS)
end

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = false,
	config = {
		type = 'Auras',
		DisplayName = L['Aura Tracker'],
		-- Slots are positioned individually, not as one block.
		NoBulkUpdate = true,
	},
	-- Only entries that differ from TRACKER_DEFAULTS are stored.
	entries = {},
}

UF.Elements:Register('AuraTracker', Build, Update, Options, Settings)
