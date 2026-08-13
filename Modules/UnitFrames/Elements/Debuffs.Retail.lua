---@class SUI.UF
local UF = SUI.UF
local L = SUI.L

-- Debuffs get their own container, so they can grow down from the bottom of
-- the frame while buffs grow up from the top.

local function Build(frame, DB)
	UF.AuraContainer:Build(frame, 'DebuffContainer', DB, 'HARMFUL')
end

local function Update(frame, settings)
	UF.AuraContainer:Update(frame, 'DebuffContainer', settings, 'HARMFUL')
end

local function Options(unitName, OptionSet)
	UF.Auras:BuildContainerOptions(unitName, OptionSet, 'DebuffContainer', L['Debuffs'], 'HARMFUL')
end

local Settings = UF.AuraContainer:Settings(L['Debuffs'], {
	position = {
		anchor = 'TOPLEFT',
		relativeTo = 'Frame',
		relativePoint = 'BOTTOMLEFT',
		x = 0,
		y = -5,
	},
	growthy = 'DOWN',
	showDebuffBorder = true,
})

UF.Elements:Register('DebuffContainer', Build, Update, Options, Settings)
