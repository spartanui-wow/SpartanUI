---@class SUI.UF
local UF = SUI.UF
local L = SUI.L

-- A third container for anything the buff and debuff ones do not cover: a
-- tracked set of spell IDs, a specific filter, a second row somewhere else on
-- the frame. Off by default.

local function Build(frame, DB)
	UF.AuraContainer:Build(frame, 'CustomAuras', DB, 'HARMFUL')
end

local function Update(frame, settings)
	UF.AuraContainer:Update(frame, 'CustomAuras', settings, 'HARMFUL')
end

local function Options(unitName, OptionSet)
	UF.Auras:BuildContainerOptions(unitName, OptionSet, 'CustomAuras', L['Custom auras'])
end

local Settings = UF.AuraContainer:Settings(L['Custom auras'], {
	enabled = false,
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
