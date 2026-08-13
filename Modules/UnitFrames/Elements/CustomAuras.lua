---@class SUI.UF
local UF = SUI.UF
local L = SUI.L

-- A third container for anything the buff and debuff ones do not cover: a
-- tracked set of spell IDs, a specific filter, a second row somewhere else on
-- the frame. Off by default.

local function Build(frame, DB)
	UF.AuraContainer:Build(frame, 'CustomAuras', DB, 'HELPFUL')
end

local function Update(frame, settings)
	UF.AuraContainer:Update(frame, 'CustomAuras', settings, 'HELPFUL')
end

local function Options(unitName, OptionSet)
	UF.Auras:BuildContainerOptions(unitName, OptionSet, 'CustomAuras', L['Custom auras'], 'HELPFUL')
end

local Settings = UF.AuraContainer:Settings(L['Custom auras'], {
	enabled = false,
	-- Sized for a handful of specific things rather than a full aura list.
	number = 8,
	perRow = 8,
	size = 22,
	position = {
		anchor = 'BOTTOMRIGHT',
		relativeTo = 'Frame',
		relativePoint = 'TOPRIGHT',
		x = 0,
		y = 5,
	},
	growthx = 'LEFT',
	growthy = 'UP',
})

UF.Elements:Register('CustomAuras', Build, Update, Options, Settings)
