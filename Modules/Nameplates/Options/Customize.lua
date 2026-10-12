local _, ns = ...
local P = ns.Plates
local L = P.L
local Options = P.Options

-- Customize page (3.2 #2). Phase 4a. A part list in groups (Bar, Text, Cast, Auras, Icons,
-- Emphasis), each row with an eye switch; picking a part shows only its settings: Position (drag in
-- the preview or the AnchorGrid with nudges), Size, Text, "Color comes from" (link to its Colors
-- row), Reset this part. The Cast bar part holds every cast setting; each aura row part holds its
-- row card; the Target highlight part holds the art picker and target emphasis.
-- Edits write profile.tweaks[styleId] (changes / add / remove) unless the player picks "Only for
-- these plates", which writes tweaks[styleId].situations[kind].

Options:AddPage('customize', 2, function()
	return Options.Placeholder(L['Customize'])
end)
