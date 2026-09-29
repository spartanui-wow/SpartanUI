---@class SUI
local SUI = SUI
---@class MoveIt
local MoveIt = SUI.MoveIt

-- One move mode visit. Changes still save as they happen (other systems read the saved
-- positions live), but the state at entry is kept so "Exit without saving" can put every
-- frame back exactly where it was.

---@class SUI.MoveIt.Session
local Session = {}
MoveIt.Session = Session

---@type table<string, {MovedPoints: string|false|nil, AdjustedScale: number|nil}>|nil
local snapshot

---@param name string
---@return table
local function Capture(name)
	local data = MoveIt.DB.movers[name]
	return { MovedPoints = data.MovedPoints or false, AdjustedScale = data.AdjustedScale }
end

function Session:Begin()
	snapshot = {}
	for name, mover in pairs(MoveIt.MoverList) do
		if not mover.isCustomMover then
			snapshot[name] = Capture(name)
		end
	end
end

---@return boolean
function Session:IsOpen()
	return snapshot ~= nil
end

---Names of movers whose position or scale changed since Begin
---@return string[]
function Session:GetChanged()
	local changed = {}
	if not snapshot then
		return changed
	end
	for name, before in pairs(snapshot) do
		local now = Capture(name)
		if now.MovedPoints ~= before.MovedPoints or now.AdjustedScale ~= before.AdjustedScale then
			changed[#changed + 1] = name
		end
	end
	return changed
end

---@return boolean
function Session:HasChanges()
	return #self:GetChanged() > 0
end

---Put every changed frame back where it was at Begin
function Session:Revert()
	if not snapshot then
		return
	end
	local changed = self:GetChanged()
	for _, name in ipairs(changed) do
		local before = snapshot[name]
		local data = MoveIt.DB.movers[name]
		data.MovedPoints = before.MovedPoints or nil
		data.AdjustedScale = before.AdjustedScale
	end
	for _, name in ipairs(changed) do
		MoveIt:ApplySavedPosition(name)
	end
	if MoveIt.logger then
		MoveIt.logger.info(('Move mode: reverted %d frames'):format(#changed))
	end
end

function Session:End()
	snapshot = nil
end
