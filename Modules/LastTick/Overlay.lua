---@type SUI
local SUI = SUI
---@class SUI.Module.LastTick
local module = SUI:GetModule('LastTick')
local canaccess = SUI.BlizzAPI.canaccessvalue

-- The drawing. Neither part ever compares health with damage in Lua, because health can be a
-- secret value:
--
-- Marker: a status bar as wide as the health bar, its right edge pinned to the end of the health
--   fill, filling right to left with (remaining damage / max health). The part past the bar's
--   left edge is clipped away, so if any green is left of the marker the enemy survives.
--
-- Kill icon: a very long, invisible status bar filled with (remaining damage / current health).
--   The icon rides the end of the fill, and a small window at the bar's far end clips it. Only
--   when damage >= health does the fill reach the end and the icon move into the window.

local WHITE = 'Interface\\Buttons\\WHITE8X8'
-- Long enough that the icon only starts to appear in the last ~0.15% before a kill
local KILL_SPAN = 16384

---@class SUI.Module.LastTick.Look
---@field texture string
---@field color number[]
---@field edge boolean
---@field edgeColor number[]
---@field iconTexture string|number
---@field iconCoords? number[]
---@field iconSize number
---@field showIcon boolean

---@class SUI.Module.LastTick.Overlay
---@field clip Frame
---@field marker StatusBar
---@field edge Texture
---@field window Frame
---@field killBar StatusBar
---@field icon Texture
---@field bar StatusBar|nil Health bar it is attached to
local Overlay = {}
Overlay.__index = Overlay
module.Overlay = Overlay

module.ICONS = {
	skull = { texture = 'Interface\\TargetingFrame\\UI-RaidTargetingIcon_8' },
	cross = { texture = 'Interface\\TargetingFrame\\UI-RaidTargetingIcon_7' },
	elite = { texture = 'Interface\\TargetingFrame\\UI-TargetingFrame-Skull' },
	flame = { texture = 'Interface\\Icons\\Spell_Shadow_Shadowburn', coords = { 0.08, 0.92, 0.08, 0.92 } },
}

---@param parent Frame
---@return SUI.Module.LastTick.Overlay
function Overlay.New(parent)
	local self = setmetatable({}, Overlay)

	local clip = CreateFrame('Frame', nil, parent)
	clip:SetClipsChildren(true)
	clip:Hide()
	self.clip = clip

	local marker = CreateFrame('StatusBar', nil, clip)
	marker:SetReverseFill(true)
	marker:SetMinMaxValues(0, 1)
	marker:SetValue(0)
	self.marker = marker

	local edge = marker:CreateTexture(nil, 'OVERLAY')
	edge:SetTexture(WHITE)
	edge:SetWidth(2)
	self.edge = edge

	clip:SetScript('OnSizeChanged', function(_, width)
		if width and canaccess(width) and width > 0 then
			marker:SetWidth(width)
		end
	end)

	local window = CreateFrame('Frame', nil, parent)
	window:SetClipsChildren(true)
	window:Hide()
	self.window = window

	local killBar = CreateFrame('StatusBar', nil, window)
	killBar:SetStatusBarTexture(WHITE)
	killBar:SetStatusBarColor(0, 0, 0, 0)
	killBar:SetMinMaxValues(0, 1)
	killBar:SetValue(0)
	killBar:SetPoint('TOPRIGHT', window, 'TOPRIGHT')
	killBar:SetPoint('BOTTOMRIGHT', window, 'BOTTOMRIGHT')
	killBar:SetWidth(KILL_SPAN)
	self.killBar = killBar

	local icon = killBar:CreateTexture(nil, 'OVERLAY')
	icon:SetPoint('TOPRIGHT', killBar:GetStatusBarTexture(), 'TOPRIGHT')
	icon:SetPoint('BOTTOMRIGHT', killBar:GetStatusBarTexture(), 'BOTTOMRIGHT')
	self.icon = icon

	return self
end

---Attach to a health bar and place the kill icon
---@param bar StatusBar Health bar
---@param iconAnchor Region|nil What the icon sits on (portrait or bar)
---@param iconPoint string Point on the icon window
---@param iconRelative string Point on the anchor
---@param x number
---@param y number
---@param look SUI.Module.LastTick.Look
function Overlay:Attach(bar, iconAnchor, iconPoint, iconRelative, x, y, look)
	self.bar = bar
	local clip, marker = self.clip, self.marker

	clip:SetParent(bar)
	clip:ClearAllPoints()
	clip:SetAllPoints(bar)
	clip:SetFrameLevel(bar:GetFrameLevel() + 2)

	local fill = bar:GetStatusBarTexture()
	local reversed = bar.GetReverseFill and bar:GetReverseFill()
	marker:ClearAllPoints()
	marker:SetPoint('TOP', bar, 'TOP')
	marker:SetPoint('BOTTOM', bar, 'BOTTOM')
	if reversed then
		marker:SetPoint('LEFT', fill, 'LEFT')
	else
		marker:SetPoint('RIGHT', fill, 'RIGHT')
	end
	marker:SetReverseFill(not reversed)
	local width = bar:GetWidth()
	if width and canaccess(width) and width > 0 then
		marker:SetWidth(width)
	end

	marker:SetStatusBarTexture(SUI.UF:FindStatusBarTexture(look.texture))
	local c = look.color
	marker:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)

	local markerFill = marker:GetStatusBarTexture()
	local edge = self.edge
	edge:ClearAllPoints()
	if reversed then
		edge:SetPoint('TOPLEFT', markerFill, 'TOPRIGHT', -1, 0)
		edge:SetPoint('BOTTOMLEFT', markerFill, 'BOTTOMRIGHT', -1, 0)
	else
		edge:SetPoint('TOPRIGHT', markerFill, 'TOPLEFT', 1, 0)
		edge:SetPoint('BOTTOMRIGHT', markerFill, 'BOTTOMLEFT', 1, 0)
	end
	local ec = look.edgeColor
	edge:SetVertexColor(ec[1], ec[2], ec[3], ec[4] or 1)
	edge:SetShown(look.edge)

	local window, icon = self.window, self.icon
	self.showIcon = look.showIcon and iconAnchor ~= nil
	if self.showIcon then
		local host = bar:GetParent() or bar
		window:SetParent(host)
		window:SetFrameStrata(host:GetFrameStrata())
		window:SetFrameLevel(host:GetFrameLevel() + 30)
		window:ClearAllPoints()
		window:SetPoint(iconPoint, iconAnchor, iconRelative, x, y)
		window:SetSize(look.iconSize, look.iconSize)
		icon:SetWidth(look.iconSize)
		icon:SetTexture(look.iconTexture)
		local coords = look.iconCoords
		if coords then
			icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
		else
			icon:SetTexCoord(0, 1, 0, 1)
		end
	else
		window:Hide()
	end
end

---Draw: `health` and `maxHealth` may be secret, `remaining` is a plain number
---@param health number
---@param maxHealth number
---@param remaining number
function Overlay:Show(health, maxHealth, remaining)
	if not self.bar then
		return
	end
	self.marker:SetMinMaxValues(0, maxHealth)
	self.marker:SetValue(remaining)
	self.clip:Show()
	if self.showIcon then
		self.killBar:SetMinMaxValues(0, health)
		self.killBar:SetValue(remaining)
		self.window:Show()
	end
end

function Overlay:Clear()
	self.clip:Hide()
	self.window:Hide()
end

function Overlay:Detach()
	self:Clear()
	self.bar = nil
end
