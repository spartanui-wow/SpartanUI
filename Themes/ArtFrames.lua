local SUI = SUI

-- Gives the art themes' look to every frame group, not only player and target.
-- Small single frames get every art piece the theme has; party and raid cells get only the
-- background piece, because the full art crowds a frame that small.

---@class SUI.ThemeArt
local ThemeArt = {}
SUI.ThemeArt = ThemeArt

---Frame groups an art theme covers once AddGroupFrames has run
---@param withGroups boolean the theme has a background piece for party and raid cells
---@return table<string, boolean>
function ThemeArt.ApplicableTo(withGroups)
	local groups = { player = true, target = true, pet = true, focus = true, boss = true, arena = true }
	if withGroups then
		groups.party = true
		groups.raid = true
		groups.raid10 = true
		groups.raid25 = true
		groups.raid40 = true
	end
	return groups
end

---@param graphic string theme name the art comes from
---@param sections string[] art pieces to turn on ('top', 'bg', 'bottom', 'full')
---@return table
local function Art(graphic, sections)
	local art = {}
	for _, section in ipairs(sections) do
		art[section] = { enabled = true, graphic = graphic }
	end
	return art
end

---Add art to focus, pet, boss, arena, party and raid frames. Frames the theme already
---describes keep their own settings.
---@param frames table<string, table> the theme's frames table
---@param graphic string theme name the art comes from
---@param sections string[] the art pieces the theme has
---@param groupSections? string[] pieces for party and raid cells (default: 'bg' when the theme has it)
function ThemeArt.AddGroupFrames(frames, graphic, sections, groupSections)
	if not groupSections then
		groupSections = {}
		for _, section in ipairs(sections) do
			if section == 'bg' then
				groupSections = { 'bg' }
			end
		end
	end

	for _, unit in ipairs({ 'focus', 'pet', 'boss', 'arena' }) do
		if not frames[unit] then
			frames[unit] = { elements = { SpartanArt = Art(graphic, sections) } }
		end
	end
	if #groupSections > 0 then
		for _, unit in ipairs({ 'party', 'raid10', 'raid25', 'raid40' }) do
			if not frames[unit] then
				frames[unit] = { elements = { SpartanArt = Art(graphic, groupSections) } }
			end
		end
	end
end
