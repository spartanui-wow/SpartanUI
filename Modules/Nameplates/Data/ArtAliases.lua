local _, ns = ...
local P = ns.Plates

P.Data = P.Data or {}

---@class Plates.ArtAliases
local ArtAliases = { map = {} }
P.Data.ArtAliases = ArtAliases

---Source-pixel margins are left, top, right, bottom. Colors are default picker tints;
---parts supply their own state and role colors. All files are white with straight alpha.
ArtAliases.MEDIA = {
	highlight = 'nameplatehighlight',
	glow = 'nameplateglow',
	art = 'nameplateart',
	border = 'nameplatenineslice',
	bar = 'statusbar',
	aura = 'nameplateauraborder',
	spark = 'nameplatespark',
	icon = 'nameplateicon',
	pip = 'nameplatefill',
	mask = 'nameplatemask',
	-- Fills that are not bar textures (shield stripes, power pips) stay out of the shared bar list
	fill = 'nameplatefill',
}

---The media type an entry is registered under (entry.media overrides its kind).
---@param entry table
---@return string
function ArtAliases:MediaType(entry)
	return self.MEDIA[entry.media or entry.kind]
end

ArtAliases.ENTRIES = {
	arrows = {
		alias = 'arrows',
		file = 'Arrows.tga',
		kind = 'highlight',
		recipe = 'arrows',
		preview = { 8, 16 },
		name = 'Nameplates Arrows',
		tint = { 0.38, 0.78, 0.9, 1 },
		recolor = true,
		draw = 'pair',
		aspect = 0.5,
		fit = 'arrow',
	},
	doubleArrows = {
		alias = 'doubleArrows',
		file = 'DoubleArrows.tga',
		kind = 'highlight',
		recipe = 'doubleArrows',
		preview = { 16, 16 },
		name = 'Nameplates Double Arrows',
		tint = { 0.38, 0.78, 0.9, 1 },
		recolor = true,
		draw = 'pair',
		aspect = 0.95,
		fit = 'arrow',
	},
	brackets = {
		alias = 'brackets',
		file = 'Brackets.tga',
		kind = 'highlight',
		recipe = 'brackets',
		preview = { 132, 14 },
		name = 'Nameplates Brackets',
		tint = { 0.38, 0.78, 0.9, 1 },
		recolor = true,
		draw = 'sliced',
		margins = { 8, 8, 8, 8 },
	},
	glow = {
		alias = 'glow',
		file = 'HighlightGlow.tga',
		kind = 'highlight',
		recipe = 'highlightGlow',
		preview = { 132, 14 },
		name = 'Nameplates Highlight Glow',
		tint = { 0.38, 0.78, 0.9, 1 },
		recolor = true,
		draw = 'glow',
		look = 'soft',
		margins = { 8, 8, 8, 8 },
	},
	underline = {
		alias = 'underline',
		file = 'Underline.tga',
		kind = 'highlight',
		recipe = 'underline',
		preview = { 132, 3 },
		name = 'Nameplates Underline',
		tint = { 0.38, 0.78, 0.9, 1 },
		recolor = true,
		draw = 'below',
		height = 3,
	},
	sideBars = {
		alias = 'sideBars',
		file = 'SideBars.tga',
		kind = 'highlight',
		recipe = 'sideBars',
		preview = { 3, 16 },
		name = 'Nameplates Side Bars',
		tint = { 0.38, 0.78, 0.9, 1 },
		recolor = true,
		draw = 'pair',
		aspect = 0.2,
		fit = 'plate',
	},
	borderPixel = {
		alias = 'borderPixel',
		file = 'PixelBorder.tga',
		kind = 'border',
		recipe = 'borderPixel',
		preview = { 132, 16 },
		name = 'Nameplates Pixel Border',
		tint = { 0.7, 0.76, 0.84, 1 },
		recolor = true,
		draw = 'sliced',
		margins = { 8, 8, 8, 8 },
	},
	borderThick = {
		alias = 'borderThick',
		file = 'ThickBorder.tga',
		kind = 'border',
		recipe = 'borderThick',
		preview = { 132, 16 },
		name = 'Nameplates Thick Border',
		tint = { 0.7, 0.76, 0.84, 1 },
		recolor = true,
		draw = 'sliced',
		margins = { 8, 8, 8, 8 },
	},
	borderShadow = {
		alias = 'borderShadow',
		file = 'ShadowBorder.tga',
		kind = 'border',
		recipe = 'borderShadow',
		preview = { 132, 16 },
		name = 'Nameplates Shadow Border',
		tint = { 0.7, 0.76, 0.84, 1 },
		recolor = true,
		draw = 'sliced',
		margins = { 8, 8, 8, 8 },
	},
	borderBeveled = {
		alias = 'borderBeveled',
		file = 'BeveledBorder.tga',
		kind = 'border',
		recipe = 'borderBeveled',
		preview = { 132, 16 },
		name = 'Nameplates Beveled Border',
		tint = { 0.7, 0.76, 0.84, 1 },
		recolor = true,
		draw = 'sliced',
		margins = { 8, 8, 8, 8 },
	},
	barFlat = {
		alias = 'barFlat',
		file = 'Flat.tga',
		kind = 'bar',
		recipe = 'barFlat',
		preview = { 132, 10 },
		name = 'Nameplates Flat',
		tint = { 0.38, 0.78, 0.9, 1 },
		recolor = true,
		draw = 'stretched',
	},
	barSoftGradient = {
		alias = 'barSoftGradient',
		file = 'SoftGradient.tga',
		kind = 'bar',
		recipe = 'barSoftGradient',
		preview = { 132, 10 },
		name = 'Nameplates Soft Gradient',
		tint = { 0.38, 0.78, 0.9, 1 },
		recolor = true,
		draw = 'stretched',
	},
	barGlossy = {
		alias = 'barGlossy',
		file = 'Glossy.tga',
		kind = 'bar',
		recipe = 'barGlossy',
		preview = { 132, 10 },
		name = 'Nameplates Glossy',
		tint = { 0.38, 0.78, 0.9, 1 },
		recolor = true,
		draw = 'stretched',
	},
	barStriped = {
		alias = 'barStriped',
		file = 'Striped.tga',
		kind = 'bar',
		recipe = 'barStriped',
		preview = { 132, 10 },
		name = 'Nameplates Striped',
		tint = { 0.38, 0.78, 0.9, 1 },
		recolor = true,
		draw = 'stretched',
	},
	barTopLine = {
		alias = 'barTopLine',
		file = 'TopLine.tga',
		kind = 'bar',
		recipe = 'barTopLine',
		preview = { 132, 10 },
		name = 'Nameplates Top Line',
		tint = { 0.38, 0.78, 0.9, 1 },
		recolor = true,
		draw = 'stretched',
	},
	barMatte = {
		alias = 'barMatte',
		file = 'Matte.tga',
		kind = 'bar',
		recipe = 'barMatte',
		preview = { 132, 10 },
		name = 'Nameplates Matte',
		tint = { 0.38, 0.78, 0.9, 1 },
		recolor = true,
		draw = 'stretched',
	},
	barInset = {
		alias = 'barInset',
		file = 'Inset.tga',
		kind = 'bar',
		recipe = 'barInset',
		preview = { 132, 10 },
		name = 'Nameplates Inset',
		tint = { 0.38, 0.78, 0.9, 1 },
		recolor = true,
		draw = 'stretched',
	},
	barSmooth = {
		alias = 'barSmooth',
		file = 'Smooth.tga',
		kind = 'bar',
		recipe = 'barSmooth',
		preview = { 132, 10 },
		name = 'Nameplates Smooth',
		tint = { 0.38, 0.78, 0.9, 1 },
		recolor = true,
		draw = 'stretched',
	},
	barRounded = {
		alias = 'barRounded',
		file = 'Rounded.tga',
		kind = 'bar',
		recipe = 'barRounded',
		preview = { 132, 14 },
		name = 'Nameplates Rounded',
		tint = { 0.38, 0.78, 0.9, 1 },
		recolor = true,
		draw = 'stretched',
		mask = 'roundedMask',
	},
	sparkFine = {
		alias = 'sparkFine',
		file = 'SparkFine.tga',
		kind = 'spark',
		recipe = 'sparkFine',
		preview = { 6, 20 },
		name = 'Nameplates Spark Fine',
		tint = { 1, 0.9, 0.65, 1 },
		recolor = true,
		draw = 'stretched',
	},
	sparkSoft = {
		alias = 'sparkSoft',
		file = 'SparkSoft.tga',
		kind = 'spark',
		recipe = 'sparkSoft',
		preview = { 6, 20 },
		name = 'Nameplates Spark Soft',
		tint = { 1, 0.9, 0.65, 1 },
		recolor = true,
		draw = 'stretched',
	},
	soft = {
		alias = 'soft',
		file = 'SoftGlow.tga',
		kind = 'glow',
		recipe = 'glowsoft',
		preview = { 132, 28 },
		name = 'Nameplates Soft Glow',
		tint = { 0.5, 0.8, 1, 1 },
		recolor = true,
		draw = 'sliced',
		margins = { 16, 16, 16, 16 },
	},
	important = {
		alias = 'important',
		file = 'ImportantGlow.tga',
		kind = 'glow',
		recipe = 'glowimportant',
		preview = { 132, 28 },
		name = 'Nameplates Important Glow',
		tint = { 1, 0.55, 0.1, 1 },
		recolor = true,
		draw = 'sliced',
		margins = { 16, 16, 16, 16 },
	},
	purge = {
		alias = 'purge',
		file = 'PurgeGlow.tga',
		kind = 'glow',
		recipe = 'glowpurge',
		preview = { 132, 28 },
		name = 'Nameplates Purge Glow',
		tint = { 0.3, 0.75, 1, 1 },
		recolor = true,
		draw = 'sliced',
		margins = { 16, 16, 16, 16 },
	},
	pandemic = {
		alias = 'pandemic',
		file = 'PandemicGlow.tga',
		kind = 'glow',
		recipe = 'glowpandemic',
		preview = { 132, 28 },
		name = 'Nameplates Pandemic Glow',
		tint = { 1, 0.7, 0.2, 1 },
		recolor = true,
		draw = 'sliced',
		margins = { 8, 8, 8, 8 },
	},
	threat = {
		alias = 'threat',
		file = 'ThreatGlow.tga',
		kind = 'glow',
		recipe = 'glowthreat',
		preview = { 132, 28 },
		name = 'Nameplates Threat Glow',
		tint = { 1, 0.25, 0.18, 1 },
		recolor = true,
		draw = 'sliced',
		margins = { 16, 16, 16, 16 },
	},
	auraThin = {
		alias = 'auraThin',
		file = 'AuraThin.tga',
		kind = 'aura',
		recipe = 'auraThin',
		preview = { 24, 24 },
		name = 'Nameplates Aura Thin',
		tint = { 0.8, 0.86, 0.92, 1 },
		recolor = true,
		draw = 'sliced',
		margins = { 8, 8, 8, 8 },
	},
	auraThick = {
		alias = 'auraThick',
		file = 'AuraThick.tga',
		kind = 'aura',
		recipe = 'auraThick',
		preview = { 24, 24 },
		name = 'Nameplates Aura Thick',
		tint = { 0.8, 0.86, 0.92, 1 },
		recolor = true,
		draw = 'sliced',
		margins = { 8, 8, 8, 8 },
	},
	auraRounded = {
		alias = 'auraRounded',
		file = 'AuraRounded.tga',
		kind = 'aura',
		recipe = 'auraRounded',
		preview = { 24, 24 },
		name = 'Nameplates Aura Rounded',
		tint = { 0.8, 0.86, 0.92, 1 },
		recolor = true,
		draw = 'sliced',
		margins = { 8, 8, 8, 8 },
	},
	focus = { alias = 'focus', file = 'Focus.tga', kind = 'icon', recipe = 'focus', preview = { 16, 16 }, name = 'Nameplates Focus', tint = { 0.38, 0.78, 0.9, 1 }, recolor = true, draw = 'fixed' },
	star = { alias = 'star', file = 'Star.tga', kind = 'icon', recipe = 'star', preview = { 16, 16 }, name = 'Nameplates Star', tint = { 0.38, 0.78, 0.9, 1 }, recolor = true, draw = 'fixed' },
	pip = { alias = 'pip', file = 'PowerPip.tga', kind = 'pip', recipe = 'pip', preview = { 6, 6 }, name = 'Nameplates Power Pip', tint = { 0.38, 0.78, 0.9, 1 }, recolor = true, draw = 'fixed' },
	absorb = {
		alias = 'absorb',
		file = 'AbsorbStripes.tga',
		kind = 'bar',
		media = 'fill',
		recipe = 'absorb',
		preview = { 132, 10 },
		name = 'Nameplates Absorb Stripes',
		tint = { 0.38, 0.78, 0.9, 1 },
		recolor = true,
		draw = 'stretched',
	},
	healAbsorb = {
		alias = 'healAbsorb',
		file = 'HealAbsorb.tga',
		kind = 'bar',
		media = 'fill',
		recipe = 'healAbsorb',
		preview = { 132, 10 },
		name = 'Nameplates Heal Absorb',
		tint = { 0.38, 0.78, 0.9, 1 },
		recolor = true,
		draw = 'stretched',
	},
	roundedFrame = {
		alias = 'roundedFrame',
		file = 'RoundedFrame.tga',
		kind = 'art',
		recipe = 'roundedFrame',
		preview = { 132, 14 },
		name = 'Nameplates Rounded Frame',
		tint = { 0.38, 0.78, 0.9, 1 },
		recolor = true,
		draw = 'stretched',
	},
	roundedBackground = {
		alias = 'roundedBackground',
		file = 'RoundedBackground.tga',
		kind = 'art',
		recipe = 'roundedBackground',
		preview = { 132, 14 },
		name = 'Nameplates Rounded Background',
		tint = { 0.38, 0.78, 0.9, 1 },
		recolor = true,
		draw = 'stretched',
	},
	roundedMask = {
		alias = 'roundedMask',
		file = 'RoundedMask.tga',
		kind = 'mask',
		recipe = 'roundedMask',
		preview = { 132, 14 },
		name = 'Nameplates Rounded Mask',
		tint = { 0.38, 0.78, 0.9, 1 },
		recolor = true,
		draw = 'stretched',
	},
	shield = {
		alias = 'shield',
		file = 'Shield.tga',
		kind = 'icon',
		recipe = 'shield',
		preview = { 16, 16 },
		name = 'Nameplates Shield',
		tint = { 0.38, 0.78, 0.9, 1 },
		recolor = true,
		draw = 'fixed',
	},
	quest = { alias = 'quest', file = 'Quest.tga', kind = 'icon', recipe = 'quest', preview = { 14, 14 }, name = 'Nameplates Quest', tint = { 0.38, 0.78, 0.9, 1 }, recolor = true, draw = 'fixed' },
	boss = { alias = 'boss', file = 'Boss.tga', kind = 'icon', recipe = 'boss', preview = { 16, 16 }, name = 'Nameplates Boss', tint = { 0.38, 0.78, 0.9, 1 }, recolor = true, draw = 'fixed' },
	factionAlliance = {
		alias = 'factionAlliance',
		file = 'FactionAlliance.tga',
		kind = 'icon',
		recipe = 'factionAlliance',
		preview = { 16, 16 },
		name = 'Nameplates Faction Alliance',
		tint = { 0.38, 0.78, 0.9, 1 },
		recolor = true,
		draw = 'fixed',
	},
	factionHorde = {
		alias = 'factionHorde',
		file = 'FactionHorde.tga',
		kind = 'icon',
		recipe = 'factionHorde',
		preview = { 16, 16 },
		name = 'Nameplates Faction Horde',
		tint = { 0.38, 0.78, 0.9, 1 },
		recolor = true,
		draw = 'fixed',
	},
}

ArtAliases.SLOTS = {}
-- Every entry by alias and by readable name
ArtAliases.byKey = {}
for alias, entry in pairs(ArtAliases.ENTRIES) do
	ArtAliases.byKey[alias] = entry
	ArtAliases.byKey[entry.name] = entry
	local slots = ArtAliases.SLOTS[entry.kind]
	if not slots then
		slots = {}
		ArtAliases.SLOTS[entry.kind] = slots
	end
	slots[alias] = entry
	slots[entry.name] = entry
	if entry.kind == 'border' then
		ArtAliases.SLOTS.art = ArtAliases.SLOTS.art or {}
		ArtAliases.SLOTS.art[alias] = entry
		ArtAliases.SLOTS.art[entry.name] = entry
	end
end

---The current media name for an alias, following renames and stopping on loops.
function ArtAliases:Resolve(key)
	if not self.map[key] then
		return key
	end
	local seen = {}
	while self.map[key] and not seen[key] do
		seen[key] = true
		key = self.map[key]
	end
	return key
end

function ArtAliases:Slot(kind, key)
	local slots = self.SLOTS[kind]
	if not slots or type(key) ~= 'string' then
		return nil
	end
	return slots[self:Resolve(key)]
end

---Called only by the namespace's enable-time media hook. LSM accepts custom media types. The
---shared 'statusbar' list (every addon's bar picker shows it) gets readable names only; Ctx:Texture
---maps the short aliases styles use to those names.
function ArtAliases:Register(media, mediaPath)
	for alias, entry in pairs(self.ENTRIES) do
		local path = mediaPath .. entry.file
		local mediaType = self:MediaType(entry)
		media:Register(mediaType, entry.name, path)
		if mediaType ~= 'statusbar' then
			media:Register(mediaType, alias, path)
		end
		if entry.kind == 'border' then
			media:Register(self.MEDIA.art, entry.name, path)
			media:Register(self.MEDIA.art, alias, path)
		end
	end
end
