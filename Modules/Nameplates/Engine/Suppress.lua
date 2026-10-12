local _, ns = ...
local P = ns.Plates

-- Blizzard plate suppression per client (4, S7). Owner: Phase 2.
--
-- On EVERY NAME_PLATE_UNIT_ADDED (Blizzard hands out a pooled UnitFrame each time):
--   1. Primary on Retail and Forever, when Caps 'rolesets' and not Quirk 'noRolesets':
--      UnitFrame:SetRolesets('alwaysBlocked') in pcall. A failure records Caps 'rolesets' = false
--      (Caps:Record) and falls through to step 2 for the rest of the session.
--   2. Proven fallback on every client: reparent the UnitFrame to Suppress.hidden (a hidden,
--      unnamed frame) and UnregisterAllEvents on it and on UnitFrame.CastBarsContainer.castBar
--      (nil-guarded; there is no castBar alias).
--   3. Rescue UnitFrame.WidgetContainer and UnitFrame.SoftTargetFrame: reparent them to our plate
--      root and call SetIgnoreParentAlpha(true) again.
--   4. Widget-only plates (facts.widgetsOnly) and game objects keep only the widget container.
-- Restore(unitFrame) puts a frame back for the engine turning off; a reload is still advised,
-- because SetRolesets stays on Blizzard frames until reload (Decision 21).
-- Never write fields onto Blizzard frames: per-frame bookkeeping lives in weak local tables.

---@class Plates.Suppress
local Suppress = {}
P.Suppress = Suppress

local touched = setmetatable({}, { __mode = 'k' })

---@return table hidden
function Suppress:HiddenParent()
	if not self.hidden then
		self.hidden = CreateFrame('Frame')
		self.hidden:Hide()
	end
	return self.hidden
end

---Silence Blizzard's unit frame on a base plate and rescue its widgets to our plate.
---@param base table
---@param plate Plates.Plate
---@param facts Plates.Facts
function Suppress:Apply(base, plate, facts)
	if base and base.UnitFrame then
		touched[base.UnitFrame] = true
	end
end

---Give a Blizzard unit frame back (engine turning off).
---@param base table
function Suppress:Restore(base) end

---@param unitFrame table
---@return boolean
function Suppress:WasTouched(unitFrame)
	return touched[unitFrame] == true
end

P.Caps:AddProbe('rolesets', function()
	local frame = CreateFrame('Frame')
	return frame.SetRolesets ~= nil
end, 'Frame:SetRolesets exists (whether it works in combat is S7)')
