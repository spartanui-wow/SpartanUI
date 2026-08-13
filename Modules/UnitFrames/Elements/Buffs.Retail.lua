---@class SUI.UF
local UF = SUI.UF
local L = SUI.L

-- Buffs get their own container so they can sit and grow independently of
-- debuffs. See Elements/AuraContainer.lua for why that needs a container each.

local function Build(frame, DB)
	UF.AuraContainer:Build(frame, 'BuffContainer', DB, 'HELPFUL')
end

local function Update(frame, settings)
	UF.AuraContainer:Update(frame, 'BuffContainer', settings, 'HELPFUL')
end

local function Options(unitName, OptionSet)
	UF.Auras:BuildContainerOptions(unitName, OptionSet, 'BuffContainer', L['Buffs'], 'HELPFUL')
end

local Settings = UF.AuraContainer:Settings(L['Buffs'], {
	position = {
		anchor = 'BOTTOMLEFT',
		relativeTo = 'Frame',
		relativePoint = 'TOPLEFT',
		x = 0,
		y = 5,
	},
	growthy = 'UP',
})

UF.Elements:Register('BuffContainer', Build, Update, Options, Settings)
