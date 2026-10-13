local _, ns = ...
local P = ns.Plates

-- The core's own strings. Keys are the English text; a missing translation shows the key.
-- Hosts may add translations with P:AddTranslations, but never replace this table. Write every
-- string for a 6th grade reader, with no em dashes and no symbols the game cannot draw.
-- Strings that name the host use %s and P.host.name, never a fixed addon name.

---@type table<string, string>
P.L = setmetatable({}, {
	__index = function(t, k)
		t[k] = k
		return k
	end,
})

-- English wording that differs from the key a file asks for (the wording pass of stage C). A file
-- asks for L['old text'] and the player reads the new text, so a page owner's file does not have to
-- change when its words get clearer. Rules: one name for each thing ("Friendly" for friendly
-- plates, "special cases" for the list and "When" for its editor, "this version of WoW"), short
-- sentences, no jargon. Hosts may still translate by the key. Suite wording_spec checks every string.
---@type table<string, string>
P.WORDING = {
	-- Friendly, never "Friends"
	['Enemies'] = 'Enemy plates',
	['Friends'] = 'Friendly plates',
	['Enemies overlap'] = 'Enemy plates overlap',
	['Friends overlap'] = 'Friendly plates overlap',
	['enemies'] = 'enemy plates',
	['friends'] = 'friendly plates',
	['Names only in class colors for friends in dungeons and raids'] = 'Names only in class colors for friendly players in dungeons and raids',
	['Red for enemies, yellow for neutral, green for friends'] = 'Red for enemy plates, yellow for neutral, green for friendly.',
	['Reaction'] = 'Friend or foe',
	-- One word for "when" and one for "where"
	['Show threat'] = 'Show threat when',
	['Choose where threat colors appear. Never turns them off.'] = 'Choose when threat colors appear. Never turns them off.',
	['Color-blind friendly colors'] = 'Color-blind mode',
	['Uses threat colors that are easier to tell apart.'] = 'Swaps the threat colors for ones that are easier to tell apart.',
	-- Why a row cannot pick enemy buffs, said the same way everywhere
	['Not available for enemy buffs on this version of WoW'] = 'On this version of WoW, spell lists cannot pick enemy buffs. The row shows every buff you can remove.',
	['The game does not let spell lists pick enemy buffs, so this row shows every buff you can remove.'] = 'On this version of WoW, spell lists cannot pick enemy buffs. The row shows every buff you can remove.',
	-- The game's own overlap setting
	['Game overlap setting'] = 'How tightly the game stacks plates',
	['How close the game lets plates stack. Lower numbers pack plates tighter.'] = "The game's own setting for stacked plates. A lower number packs plates closer together.",
	-- Customize
	['Hangs from'] = 'Moves with',
	['The part it moves with. It stays where it is now.'] = 'Pick which part this one follows. It stays where it is now.',
	['Pick where it sits on the part it hangs from. The arrows nudge it. You can also drag it in the preview.'] = 'Pick where it sits on the part it moves with. The arrows nudge it. You can also drag it in the preview.',
	['Where the row sits next to the part it hangs from.'] = 'Where the row sits next to the part it moves with.',
	['Line up'] = 'Text alignment',
	['Names Only'] = 'Names only',
	-- "This version of WoW", never "this game version" or "this version of the game"
	['This game version cannot show aura rows on these plates.'] = 'This version of WoW cannot show aura rows on these plates.',
	['This game version cannot show the refresh glow on aura icons.'] = 'This version of WoW cannot show the refresh glow on aura icons.',
	['This game version cannot tint plates by their auras.'] = 'This version of WoW cannot tint plates by their auras.',
	['This game version may never mark a cast as important, so this may not show.'] = 'This version of WoW may never mark a cast as important, so this may not show.',
	['This game version cannot tell which enemy buffs are important.'] = 'This version of WoW cannot tell which enemy buffs are important.',
	['Tank debuffs from other players are not part of this game version.'] = 'Tank debuffs from other players are not part of this version of WoW.',
	['This game version only knows crowd control from a built-in spell list.'] = 'This version of WoW only knows crowd control from a built-in spell list.',
	['This game version cannot tell which casts are important.'] = 'This version of WoW cannot tell which casts are important.',
	['No probe results for this game version yet.'] = 'No probe results for this version of WoW yet.',
	['As a healer, enemy plates stay small and soft until they matter: your target, your focus, the one under your mouse and any enemy that casts. You also get a bigger row of buffs you can remove.'] = 'As a healer, enemy plates stay small and soft until they matter. They grow for your target, your focus, the plate under your mouse and any caster. You also get a bigger row of buffs you can remove.',
	['Not on this game version'] = 'Not on this version of WoW',
	['This game version has no arenas'] = 'This version of WoW has no arenas',
	['This version of the game cannot let clicks pass through plates.'] = 'This version of WoW cannot let clicks pass through plates.',
	['This version of the game cannot fade plates behind walls.'] = 'This version of WoW cannot fade plates behind walls.',
	['This version of the game cannot keep plates from overlapping.'] = 'This version of WoW cannot keep plates from overlapping.',
	['This version of the game cannot show names only on friendly plates.'] = 'This version of WoW cannot show names only on friendly plates.',
	['This version of the game does not shrink far away plates.'] = 'This version of WoW does not shrink far away plates.',
}
for key, text in pairs(P.WORDING) do
	rawset(P.L, key, text)
end

---Add translations for the current locale. Existing keys are overwritten, the table is kept.
---@param locale string|nil Only applied when it matches GetLocale() (nil applies always)
---@param strings table<string, string>
function P:AddTranslations(locale, strings)
	if locale and GetLocale and GetLocale() ~= locale then
		return
	end
	for key, text in pairs(strings) do
		rawset(self.L, key, text)
	end
end

---The host's name for strings such as "Follow my %s profile".
---@return string
function P:HostName()
	return (self.host and self.host.name) or ''
end

P:AddTranslations('enUS', {
	['Special mobs'] = 'Special mobs',
	['The color you picked for this mob'] = 'The color you picked for this mob',
	['Shows enemy player specs when the game shares them'] = 'Shows enemy player specs when the game shares them',
	['Shows known totems when the game shares their names'] = 'Shows known totems when the game shares their names',
	['Type a mob id using numbers.'] = 'Type a mob id using numbers.',
	['Target a mob whose name the game lets you see.'] = 'Target a mob whose name the game lets you see.',
	['Works out in the world and in old content. In current dungeons and raids the game hides which mob is which.'] = 'Works out in the world and in old content. In current dungeons and raids the game hides which mob is which.',
	['Add my target'] = 'Add my target',
	['Add a mob id'] = 'Add a mob id',
	['Mob'] = 'Mob',
	['Name to help me find it'] = 'Name to help me find it',
	['Use a special color'] = 'Use a special color',
	['Plate color'] = 'Plate color',
	['New name'] = 'New name',
	['Leave this empty to keep the mob name.'] = 'Leave this empty to keep the mob name.',
	['Remove this mob'] = 'Remove this mob',
})

P:AddTranslations('enUS', {
	['Aura text'] = 'Aura text',
	['Time left position'] = 'Time left position',
	['Time left size'] = 'Time left size',
	['Stack position'] = 'Stack position',
	['Stack size'] = 'Stack size',
	['Stacks'] = 'Stacks',
	['Reset aura text'] = 'Reset aura text',
	['Pick where the text sits on each icon. The arrows move it a little.'] = 'Pick where the text sits on each icon. The arrows move it a little.',
	['Put the time left and stacks back where this style puts them.'] = 'Put the time left and stacks back where this style puts them.',
	['Drag this text. Arrow keys move it a little. Ctrl-Z undoes.'] = 'Drag this text. Arrow keys move it a little. Ctrl-Z undoes.',
	['Drag the time left or stacks on the larger icon. Ctrl-Z undoes.'] = 'Drag the time left or stacks on the larger icon. Ctrl-Z undoes.',
	['Move time left and stacks on the larger icon in the preview.'] = 'Move time left and stacks on the larger icon in the preview.',
	['Show a larger sample icon to move time left and stacks.'] = 'Show a larger sample icon to move time left and stacks.',
})
