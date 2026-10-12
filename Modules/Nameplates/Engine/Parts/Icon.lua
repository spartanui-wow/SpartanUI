local _, ns = ...
local P = ns.Plates

-- Icons (kind 'icon'): raidMarker, classification (elite, rare, boss), quest, faction, focus,
-- shield. Owner: Phase 2.
--
-- Raid marker: P.Secret.SetRaidMarker(texture, src:RaidMarkerSecret()) (SetSpriteSheetCell).
-- RAID_TARGET_UPDATE is a global event: the Driver delivers it to bound plates as the bus message
-- of the same name. Classification comes from plate.facts.classification (plain), quest from
-- plate.facts.isQuest. Atlases are checked with C_Texture.GetAtlasInfo and fall back to files in
-- Media/ on clients that miss them (5.5).

P.Parts:Register({
	id = 'icon',
	kinds = { 'icon' },
	messages = { 'RAID_TARGET_UPDATE', 'QUESTS_CHANGED' },
	events = function(spec)
		if spec.source == 'classification' then
			return { 'UNIT_CLASSIFICATION_CHANGED' }
		end
		return {}
	end,
	Create = function(plate)
		local holder = CreateFrame('Frame', nil, plate.art)
		local texture = holder:CreateTexture(nil, 'ARTWORK')
		texture:SetAllPoints(holder)
		return { frame = holder, texture = texture }
	end,
	Layout = function(widget, spec, ctx)
		widget.frame:SetSize(spec.size or 16, spec.size or 16)
		ctx:Anchor(widget.frame, spec.anchor)
	end,
	Update = function(widget, src)
		if widget.spec.source == 'raidMarker' then
			P.Secret.SetRaidMarker(widget.texture, src:RaidMarkerSecret())
		end
	end,
	Reset = function(widget)
		widget.texture:Hide()
	end,
})
