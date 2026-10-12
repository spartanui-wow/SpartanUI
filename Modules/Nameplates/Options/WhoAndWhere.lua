local _, ns = ...
local P = ns.Plates
local L = P.L
local Options = P.Options

-- Who and where page (3.2 #5). Phase 2: Show mode per kind of plate and "Give the game back its
-- settings". Phase 4a: a style per kind with "Same as Enemies", the "When" list (RuleList), plate
-- behavior (enemy plates always / in combat, pets and totems, keep plates from overlapping with
-- spacing, click through friendly plates, fade behind walls), the honest note about friendly plates
-- in instances, and the Game settings table (every CVar we own: old value, current value, who last
-- changed it). More settings: the place-by-place table, click-area padding, Copy from, Reset.

local KIND_LABELS = {
	enemyNPC = L['Enemy NPCs'],
	enemyPlayer = L['Enemy players'],
	friendlyNPC = L['Friendly NPCs'],
	friendlyPlayer = L['Friendly players'],
	minor = L['Minor enemies'],
}
local MODES = { full = L['Full'], name = L['Names only'], hidden = L['Hidden'] }

Options:AddPage('whoAndWhere', 5, function()
	local args = {}
	for index, kind in ipairs(P.Situation.KINDS) do
		args[kind] = {
			type = 'select',
			name = KIND_LABELS[kind],
			order = index,
			values = MODES,
			sorting = { 'full', 'name', 'hidden' },
			get = function()
				return P.Store:Get({ 'modes', kind }) or P.Situation.DEFAULT_MODES[kind] or 'full'
			end,
			set = function(_, value)
				if value == (P.Situation.DEFAULT_MODES[kind] or 'full') then
					value = nil
				end
				P.Store:Set({ 'modes', kind }, value)
			end,
			disabled = Options.Locked,
		}
	end
	args.note = {
		type = 'description',
		name = L['Inside dungeons and raids the game draws friendly plates itself. You can pick names only and class colors there, nothing more.'],
		order = 20,
	}
	args.restore = {
		type = 'execute',
		name = L['Give the game back its settings'],
		desc = L['Puts back every game nameplate setting we changed. Settings the game locks in combat come back when combat ends.'],
		order = 30,
		func = function()
			if not P.CVars:RestoreAll() then
				P.log.info('Some nameplate settings come back when combat ends')
			end
		end,
	}
	return { type = 'group', name = L['Who and where'], args = args }
end)
