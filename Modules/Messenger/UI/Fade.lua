local _, ns = ...
local M = ns.Messenger

-- Windows ease to a lower opacity while the character moves, so they cover less of the world.
-- A window stays solid while the mouse is over it or its composer has the keyboard.

---@class Messenger.Fade
local F = {}
M.UI.Fade = F

local RATE = 4
local moving = false
local driver = CreateFrame('Frame')
driver:Hide()

---@param frame Frame
---@param ancestor Frame
---@return boolean
local function IsInside(frame, ancestor)
	while frame do
		if frame == ancestor then
			return true
		end
		frame = frame:GetParent()
	end
	return false
end

---@return Frame[]
local function Windows()
	local list = {}
	local deck = M.UI.Deck.win
	if deck and deck:IsShown() then
		list[#list + 1] = deck
	end
	for _, win in pairs(M.UI.PopOut:Windows()) do
		if win:IsShown() then
			list[#list + 1] = win
		end
	end
	return list
end

---@param win Frame
---@return number
local function Target(win)
	local faded = M.settings.fadeWhileMoving or 1
	if not moving or faded >= 1 or win:IsMouseOver() then
		return 1
	end
	local focused = M.UI:FocusedComposer()
	if focused and IsInside(focused, win) then
		return 1
	end
	return faded
end

driver:SetScript('OnUpdate', function(self, elapsed)
	local settled = true
	for _, win in ipairs(Windows()) do
		local current = win:GetAlpha()
		local target = Target(win)
		if math.abs(current - target) > 0.01 then
			local step = RATE * elapsed
			if current < target then
				win:SetAlpha(math.min(target, current + step))
			else
				win:SetAlpha(math.max(target, current - step))
			end
			settled = false
		elseif current ~= target then
			win:SetAlpha(target)
		end
	end
	-- Keep checking the mouse while moving; stop once everything is solid again
	if settled and not moving then
		self:Hide()
	end
end)

---Re-checks opacity, e.g. when a window opens after being hidden while faded.
function F:Kick()
	driver:Show()
end

function F:Enable()
	M:RegisterEvent('PLAYER_STARTED_MOVING', 'Fade', function()
		moving = true
		driver:Show()
	end)
	M:RegisterEvent('PLAYER_STOPPED_MOVING', 'Fade', function()
		moving = false
		driver:Show()
	end)
end

function F:Disable()
	M:UnregisterEvent('PLAYER_STARTED_MOVING', 'Fade')
	M:UnregisterEvent('PLAYER_STOPPED_MOVING', 'Fade')
	moving = false
	driver:Show()
end
