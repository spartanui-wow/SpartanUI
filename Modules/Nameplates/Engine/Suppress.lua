local _, ns = ...
local P = ns.Plates

-- Blizzard plate suppression per client (4, S7). Owner: Phase 2.
--
-- On EVERY NAME_PLATE_UNIT_ADDED (Blizzard hands out a pooled UnitFrame each time, and its own add
-- handler has already run and set it up again):
--   1. Rescue UnitFrame.WidgetContainer and UnitFrame.SoftTargetFrame: reparent them to the base
--      plate (shown in every mode, so widget-only plates, game objects and plates in Show mode
--      'hidden' keep their widgets and soft-target icon) and call SetIgnoreParentAlpha(true) again.
--   2. Primary on Retail and Forever, when Caps 'rolesets' and not Quirk 'noRolesets':
--      UnitFrame:SetRolesets('alwaysBlocked') in pcall. SetRolesets is a protected function, so it
--      is skipped while the unit frame reports itself protected in combat (it would be blocked, not
--      error). A failure records Caps 'rolesets' = false (Caps:Record) and falls through to step 3
--      for the rest of the session.
--   3. Proven fallback on every client (S7): reparent the UnitFrame to Suppress.hidden (a hidden,
--      unnamed frame). SetParent is skipped too while the frame is protected in combat.
--   4. Always: alpha 0 on the UnitFrame (also under rolesets, until S7 confirms they hide it), and
--      UnregisterAllEvents on it and on UnitFrame.CastBarsContainer.castBar (nil-guarded;
--      UnitFrame.castBar is checked only as a fallback shape).
-- Forbidden plates are never touched. Widget-only plates (facts.widgetsOnly) and game objects get
-- the same treatment as drawn plates: the Driver then draws nothing, so only the rescued widget
-- container and soft-target icon show. The player's own plate (Classic family personal plate) is
-- left to Blizzard: the Driver calls Release(base), which gives back a pooled frame we touched.
-- RestoreAll() gives every touched frame back (profile.enabled = false, engine off): rolesets
-- cleared with SetRolesets(nil), the frame back on its base plate at full alpha, widgets back on
-- their unit frame. Events stay unregistered until Blizzard sets the frame up again on its next
-- add, so a reload is still advised.
-- Never write fields onto Blizzard frames: per-frame bookkeeping lives in weak local tables.

---@class Plates.Suppress
local Suppress = { warned = false }
P.Suppress = Suppress

local weak = { __mode = 'k' }
local touched = setmetatable({}, weak) -- unitFrame -> true
local blocked = setmetatable({}, weak) -- unitFrame -> true while SetRolesets('alwaysBlocked') holds
local reparented = setmetatable({}, weak) -- unitFrame -> true while it sits on the hidden frame
local faded = setmetatable({}, weak) -- unitFrame -> true while we hold its alpha at 0
local homeOf = setmetatable({}, weak) -- unitFrame -> base plate it was last seen on
local rescued = setmetatable({}, weak) -- widget frame -> { owner = unitFrame, ignore = boolean }

local RESCUE_KEYS = { 'WidgetContainer', 'SoftTargetFrame' }

---@return table hidden
function Suppress:HiddenParent()
	if not self.hidden then
		self.hidden = CreateFrame('Frame')
		self.hidden:Hide()
	end
	return self.hidden
end

---The cast bar Blizzard's nameplate unit frame owns (CastBarsContainer.castBar on all six clients).
---@param unitFrame table
---@return table|nil
local function CastBarOf(unitFrame)
	local container = unitFrame.CastBarsContainer
	local castBar = container and container.castBar
	if castBar then
		return castBar
	end
	return unitFrame.castBar
end

local function Unregister(frame)
	if frame and frame.UnregisterAllEvents then
		pcall(frame.UnregisterAllEvents, frame)
	end
end

---True for a frame addon code must not touch (forbidden plates in instances).
---@param frame table
---@return boolean
local function Forbidden(frame)
	if not frame.IsForbidden then
		return false
	end
	local ok, value = pcall(frame.IsForbidden, frame)
	return not ok or value == true
end

---True while protected changes (SetRolesets, SetParent) to this frame would be blocked.
---@param frame table
---@return boolean
local function LockedNow(frame)
	if not (InCombatLockdown and InCombatLockdown()) then
		return false
	end
	if not frame.IsProtected then
		return false
	end
	local ok, protected = pcall(frame.IsProtected, frame)
	return not ok or protected == true
end
Suppress.LockedNow = LockedNow

---Move the widget container and soft-target icon onto the base plate so they keep showing.
---@param base table
---@param unitFrame table
function Suppress:Rescue(base, unitFrame)
	for i = 1, #RESCUE_KEYS do
		local widget = unitFrame[RESCUE_KEYS[i]]
		if widget and widget.SetParent and not LockedNow(widget) then
			local info = rescued[widget]
			if not info then
				local ignoring = false
				if widget.IsIgnoringParentAlpha then
					local ok, value = pcall(widget.IsIgnoringParentAlpha, widget)
					ignoring = ok and value == true
				end
				rescued[widget] = { owner = unitFrame, ignore = ignoring }
			else
				info.owner = unitFrame
			end
			widget:SetParent(base)
			if widget.SetIgnoreParentAlpha then
				widget:SetIgnoreParentAlpha(true)
			end
		end
	end
end

---True when SetRolesets may be tried on this frame.
---@param unitFrame table
---@return boolean
local function CanUseRolesets(unitFrame)
	return unitFrame.SetRolesets ~= nil and P.Caps:Get('rolesets') and not P.Caps:Quirk('noRolesets')
end

---Silence Blizzard's unit frame on a base plate and rescue its widgets.
---@param base table
---@param plate Plates.Plate|nil
---@param facts Plates.Facts|nil
---@return boolean suppressed
function Suppress:Apply(base, plate, facts)
	local unitFrame = base and base.UnitFrame
	if not unitFrame or Forbidden(base) or Forbidden(unitFrame) then
		return false
	end
	touched[unitFrame] = true
	homeOf[unitFrame] = base
	self:Rescue(base, unitFrame)

	local locked = LockedNow(unitFrame)
	local hidden = false
	if not locked and CanUseRolesets(unitFrame) then
		if pcall(unitFrame.SetRolesets, unitFrame, 'alwaysBlocked') then
			blocked[unitFrame] = true
			hidden = true
		else
			P.Caps:Record('rolesets', false)
			if not self.warned then
				self.warned = true
				P.log.warning('Hiding game plates the first way failed; using the second way for this session')
			end
		end
	end
	if not hidden and not locked then
		unitFrame:SetParent(self:HiddenParent())
		reparented[unitFrame] = true
	end
	unitFrame:SetAlpha(0)
	faded[unitFrame] = true
	Unregister(unitFrame)
	Unregister(CastBarOf(unitFrame))
	return true
end

---Give one unit frame back (best effort; its events come back on its next add). Changes the game
---blocks in combat stay until the frame's next add or a later restore.
---@param unitFrame table
function Suppress:RestoreFrame(unitFrame)
	if Forbidden(unitFrame) then
		touched[unitFrame] = nil
		return
	end
	local locked = LockedNow(unitFrame)
	if blocked[unitFrame] and not locked then
		pcall(unitFrame.SetRolesets, unitFrame, nil)
		blocked[unitFrame] = nil
	end
	if reparented[unitFrame] and not locked then
		local home = homeOf[unitFrame]
		-- Only a frame still assigned to its base goes back there; pooled frames get their parent
		-- from Blizzard on their next add
		if home and home.UnitFrame == unitFrame then
			unitFrame:SetParent(home)
		end
		reparented[unitFrame] = nil
	end
	if faded[unitFrame] then
		unitFrame:SetAlpha(1)
		faded[unitFrame] = nil
	end
	for i = 1, #RESCUE_KEYS do
		local widget = unitFrame[RESCUE_KEYS[i]]
		local info = widget and rescued[widget]
		if info and info.owner == unitFrame and not LockedNow(widget) then
			widget:SetParent(unitFrame)
			if widget.SetIgnoreParentAlpha then
				widget:SetIgnoreParentAlpha(info.ignore)
			end
			rescued[widget] = nil
		end
	end
	if not (blocked[unitFrame] or reparented[unitFrame]) then
		touched[unitFrame] = nil
	end
end

---Give one base plate's unit frame back.
---@param base table
function Suppress:Restore(base)
	local unitFrame = base and base.UnitFrame
	if unitFrame and touched[unitFrame] then
		self:RestoreFrame(unitFrame)
	end
end

---A plate we leave to Blizzard (the player's own plate): the pooled unit frame it got may be one
---we silenced on an earlier add, so give it back.
---@param base table
function Suppress:Release(base)
	self:Restore(base)
end

---Give every touched frame back (profile.enabled = false, engine off).
function Suppress:RestoreAll()
	local frames = {}
	for unitFrame in pairs(touched) do
		frames[#frames + 1] = unitFrame
	end
	for i = 1, #frames do
		self:RestoreFrame(frames[i])
	end
	if #frames > 0 then
		P.log.info('Game nameplates are back; a reload gives them back fully')
	end
end

---@param unitFrame table
---@return boolean
function Suppress:WasTouched(unitFrame)
	return touched[unitFrame] == true
end

---How a unit frame is hidden right now (tests and the probe).
---@param unitFrame table
---@return boolean blockedByRolesets
---@return boolean onHiddenFrame
---@return boolean fadedOut
function Suppress:StateOf(unitFrame)
	return blocked[unitFrame] == true, reparented[unitFrame] == true, faded[unitFrame] == true
end

function Suppress:Enable()
	self.warned = false
end

function Suppress:Disable()
	self:RestoreAll()
end

P.Caps:AddProbe('rolesets', function()
	local frame = CreateFrame('Frame')
	return frame.SetRolesets ~= nil
end, 'Frame:SetRolesets exists (whether it works in combat is S7)')
