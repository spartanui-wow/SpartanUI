local _, ns = ...
local oUF = ns.oUF or oUF

--[[
# Element: Target Highlight

Highlights a unit frame while its unit is the player's target, focus or mouseover.

## Widget

TargetHighlight - A Frame holding one layer per state in `TargetHighlight.layers` (target, focus,
mouseover). Each layer is any frame; its children (textures, border) show and hide with it.

## Notes

The layers are faded in and out with SetAlphaFromBoolean. On addon-restricted maps UnitIsUnit
returns a secret boolean, which Lua may not test but this widget method accepts.

## Options

.watch - Which states to show: { target = boolean, focus = boolean, mouseover = boolean }
         (default: target only)

## Callbacks

PreUpdate(), PostUpdate() on the element; Override(self, event) replaces the update.
--]]

local TOKENS = { target = 'target', focus = 'focus', mouseover = 'mouseover' }
local DEFAULT_WATCH = { target = true }
local POLL_INTERVAL = 0.2

---Fade a layer in when `value` is true; works on secret booleans where the client supports it
---@param layer Frame
---@param value boolean
local function ShowWhen(layer, value)
	if layer.SetAlphaFromBoolean then
		layer:SetAlphaFromBoolean(value, 1, 0)
	else
		layer:SetAlpha(value and 1 or 0)
	end
end

-- The mouseover token clears without an event when the mouse leaves a unit in the world
local function PollMouseover(element, elapsed)
	element.pollElapsed = (element.pollElapsed or 0) + elapsed
	if element.pollElapsed < POLL_INTERVAL then
		return
	end
	element.pollElapsed = 0
	if not UnitExists('mouseover') then
		element:SetScript('OnUpdate', nil)
		if not element.hovered and element.layers.mouseover then
			element.layers.mouseover:SetAlpha(0)
		end
	end
end

local function Update(self, event)
	local element = self.TargetHighlight

	if element.PreUpdate then
		element:PreUpdate()
	end

	-- Group frames have no unit until their header assigns one
	local unit = self.unit
	local watch = element.watch or DEFAULT_WATCH
	for state, layer in pairs(element.layers) do
		if not unit or not watch[state] then
			layer:SetAlpha(0)
		elseif state == 'mouseover' and element.hovered then
			layer:SetAlpha(1)
		else
			ShowWhen(layer, UnitIsUnit(unit, TOKENS[state]))
		end
	end

	if watch.mouseover and event == 'UPDATE_MOUSEOVER_UNIT' then
		element.pollElapsed = 0
		element:SetScript('OnUpdate', PollMouseover)
	end

	if element.PostUpdate then
		return element:PostUpdate()
	end
end

local function Path(self, ...)
	return (self.TargetHighlight.Override or Update)(self, ...)
end

local function ForceUpdate(element)
	return Path(element.__owner, 'ForceUpdate')
end

---Register an event only where the client has it (focus is missing on some clients)
local function RegisterIfValid(self, event)
	if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
		return
	end
	self:RegisterEvent(event, Path, true)
end

local function Enable(self)
	local element = self.TargetHighlight
	if not element then
		return
	end
	element.__owner = self
	element.ForceUpdate = ForceUpdate
	element.layers = element.layers or {}

	for _, layer in pairs(element.layers) do
		layer:SetAlpha(0)
	end

	RegisterIfValid(self, 'PLAYER_TARGET_CHANGED')
	RegisterIfValid(self, 'PLAYER_FOCUS_CHANGED')
	RegisterIfValid(self, 'UPDATE_MOUSEOVER_UNIT')

	-- Hovering this frame needs no unit comparison at all
	if not element.mouseHooked then
		element.mouseHooked = true
		self:HookScript('OnEnter', function(frame)
			local highlight = frame.TargetHighlight
			if highlight and highlight.__owner then
				highlight.hovered = true
				Path(frame, 'OnEnter')
			end
		end)
		self:HookScript('OnLeave', function(frame)
			local highlight = frame.TargetHighlight
			if highlight and highlight.__owner then
				highlight.hovered = false
				Path(frame, 'OnLeave')
			end
		end)
	end

	return true
end

local function Disable(self)
	local element = self.TargetHighlight
	if not element then
		return
	end
	self:UnregisterEvent('PLAYER_TARGET_CHANGED', Path)
	self:UnregisterEvent('PLAYER_FOCUS_CHANGED', Path)
	self:UnregisterEvent('UPDATE_MOUSEOVER_UNIT', Path)
	element:SetScript('OnUpdate', nil)
	element.__owner = nil
	for _, layer in pairs(element.layers or {}) do
		layer:SetAlpha(0)
	end
end

oUF:AddElement('TargetHighlight', Path, Enable, Disable)
