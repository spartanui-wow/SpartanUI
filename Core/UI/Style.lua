---@class SUI
local SUI = SUI

-- SpartanUI's tool windows (frame mover, options window, setup) draw with the shared style from
-- Lib's AddonTools (LibAT.UI.Style), the same one its settings window and controls use. This adds
-- SpartanUI's accent: the active theme's color, or the player's own choice. LibAT asks for it
-- through the accent provider, so every kit window, from any addon, uses the same accent.

---@class SUI.UI.Style : LibAT.UI.Style
local Style = setmetatable({}, { __index = LibAT.UI.Style })
SUI.UI = SUI.UI or {}
SUI.UI.Style = Style

local DEFAULT_ACCENT = { 0.886, 0.122, 0.122 }

-- Accent per theme. A theme can also set `accent = { r, g, b }` in its registry metadata.
local THEME_ACCENTS = {
	Classic = { 1, 0.78, 0.22 },
	Fel = { 0.42, 0.86, 0.22 },
	Arcane = { 0.33, 0.66, 1 },
	ArcaneRed = { 0.95, 0.30, 0.25 },
	Digital = { 0.20, 0.82, 0.95 },
	Midnight = { 0.58, 0.40, 0.95 },
	Midnight_Void = { 0.58, 0.40, 0.95 },
	Midnight_Shadow = { 0.70, 0.55, 1 },
	Tribal = { 0.92, 0.60, 0.26 },
	Transparent = { 0.35, 0.72, 1 },
	Grid = { 0.05, 0.82, 0.62 },
}

---@return table|nil
local function GetStyleDB()
	return SUI.DB and SUI.DB.UIStyle
end

---Accent color for the active theme, or the player's choice
---@return number r, number g, number b
function Style:GetAccent()
	local db = GetStyleDB()
	if db then
		if db.accentMode == 'class' then
			local _, class = UnitClass('player')
			local color = class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
			if color then
				return color.r, color.g, color.b
			end
		elseif db.accentMode == 'custom' and db.customAccent then
			return db.customAccent.r or 1, db.customAccent.g or 1, db.customAccent.b or 1
		end
	end

	local themeName = SUI.DB and SUI.GetActiveStyle and SUI:GetActiveStyle()
	if themeName then
		local entry = SUI.ThemeRegistry and SUI.ThemeRegistry:Get(themeName)
		local accent = (entry and entry.accent) or THEME_ACCENTS[themeName]
		if not accent and themeName == 'War' then
			accent = UnitFactionGroup('player') == 'Alliance' and { 0.25, 0.55, 1 } or { 0.9, 0.22, 0.16 }
		end
		if accent then
			return accent[1], accent[2], accent[3]
		end
	end
	return DEFAULT_ACCENT[1], DEFAULT_ACCENT[2], DEFAULT_ACCENT[3]
end

local watcher = CreateFrame('Frame')
watcher:RegisterEvent('PLAYER_LOGIN')
watcher:SetScript('OnEvent', function()
	LibAT.UI.SetAccentProvider(function()
		return Style:GetAccent()
	end)
	-- SUI.Event loads after the core UI files
	if SUI.Event then
		SUI.Event:RegisterEvent('ARTWORK_STYLE_CHANGED', function()
			LibAT.UI.NotifyAccentChanged()
		end)
	end
end)
