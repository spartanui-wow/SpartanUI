---@type SUI
local SUI = SUI
local L = SUI.L

-- Last Tick: tracks the player's damage over time spells on enemies and shows, on the health
-- bar, how much damage they still have to deal, plus a kill icon when that is enough to finish
-- the enemy off. Works on SpartanUI's own frames, Blizzard's target and focus frames and
-- nameplates.
--
-- On clients with secret combat values (Retail and Forever) the addon can never compare damage
-- with health itself. Both numbers go into status bars, which may draw secret values, and the
-- geometry of those bars does the comparison (see Overlay.lua).

---@class SUI.Module.LastTick : SUI.Module
local module = SUI:NewModule('LastTick')
module.DisplayName = L['Last Tick']
module.description = 'Shows the damage your DoTs still have to deal and whether they will finish the enemy off'

-- Retail and Forever hide health, auras and combo points from addon code in combat, and
-- registering the combat log raises a blocked action warning on Forever. There is no safe way to
-- probe for that, so the rule set is chosen by client. Elsewhere the combat log and auras give
-- exact ticks and durations.
module.Restricted = SUI.IsRetail or SUI.IsForever

---@class SUI.Module.LastTick.DB
local DBDefaults = {
	target = true,
	focus = true,
	nameplates = true,
	marker = {
		texture = 'Solid',
		color = { 1, 0.82, 0.15, 0.6 },
		edge = true,
		edgeColor = { 1, 1, 1, 0.9 },
	},
	icon = {
		style = 'skull',
		size = 24,
		placement = 'portrait',
		x = 0,
		y = 0,
	},
	plateIcon = {
		enabled = true,
		size = 14,
	},
}

local DBGlobalDefaults = {
	learned = {},
}

local REFRESH_INTERVAL = 0.1

local driver = CreateFrame('Frame')
driver:Hide()
local sinceRefresh = 0
driver:SetScript('OnUpdate', function(_, elapsed)
	sinceRefresh = sinceRefresh + elapsed
	if sinceRefresh >= REFRESH_INTERVAL then
		sinceRefresh = 0
		module:Refresh()
	end
end)

---A unit's GUID, or nil when the client hides it
---@param unit string
---@return string|nil
function module:SafeGUID(unit)
	local guid = UnitGUID(unit)
	if guid and SUI.BlizzAPI.canaccessvalue(guid) then
		return guid
	end
	return nil
end

---@param message string
function module:Log(message)
	if module.logger then
		module.logger.debug(message)
	end
end

---Start drawing; called whenever a DoT is added
function module:Wake()
	if SUI:IsModuleEnabled(module) then
		driver:Show()
	end
end

function module:Refresh()
	local tracker, hosts = module.Tracker, module.Hosts
	local now = GetTime()
	tracker:Prune(now)
	local any = tracker:HasAny()

	for _, slot in pairs(hosts.slots) do
		local shown = false
		local unit = slot.unit
		if any and unit and UnitExists(unit) then
			local guid = module:SafeGUID(unit)
			if guid and tracker:Has(guid) then
				if UnitIsDead(unit) then
					tracker:Clear(guid)
				elseif hosts:Prepare(slot) then
					tracker:Observe(unit, guid, now)
					local remaining = tracker:Remaining(guid, now)
					if remaining > 0 then
						slot.overlay:Show(UnitHealth(unit), UnitHealthMax(unit), remaining)
						shown = true
					end
				end
			end
		end
		if not shown and slot.overlay then
			slot.overlay:Clear()
		end
	end

	if not any then
		driver:Hide()
	end
end

---Re-apply the look and placement to every overlay after a setting changes
function module:ApplySettings()
	if module.Hosts then
		module.Hosts:Reattach()
	end
	module:Refresh()
end

function module:OnInitialize()
	if SUI.logger then
		module.logger = SUI.logger:RegisterCategory('LastTick')
	end
	SUI.DBM:SetupModule(module, DBDefaults, DBGlobalDefaults, { autoCalculateDepth = true })
	-- Replaces SetupModule's profile callbacks with ones that also redraw
	SUI.DBM:RegisterProfileCallbacks(module, 'ApplySettings')
end

function module:OnEnable()
	module:BuildOptions()
	if SUI:IsModuleDisabled(module) then
		return
	end
	module.Tracker:Enable()
	module.Hosts:Enable()
end

function module:OnDisable()
	module.Tracker:Disable()
	module.Hosts:Disable()
	driver:Hide()
end
