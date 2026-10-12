local _, ns = ...
local P = ns.Plates
local L = P.L
local Options = P.Options

-- Auras page (3.2 #4). Phase 3. Sections: My debuffs on enemies, Enemy buffs I can remove, Crowd
-- control, Tank debuffs (Classic family and Forever). Each has "Always show" and "Never show"
-- SpellList widgets; on Retail and Forever the Enemy buffs section shows a reason instead of lists.
-- Everything here is disabled while Options.Locked(), with Options.LOCKED_REASON.

Options:AddPage('auras', 4, function()
	return Options.Placeholder(L['Auras'])
end)
