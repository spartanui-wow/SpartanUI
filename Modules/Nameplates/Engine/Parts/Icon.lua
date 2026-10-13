local _, ns = ...
local P = ns.Plates
local Secret = P.Secret
local L = P.L

-- Icons (kind 'icon'). One implementation draws every icon source:
--   raidMarker      P.Secret.SetRaidMarker(texture, src:RaidMarkerSecret()) (SetSpriteSheetCell;
--                   secret on Retail and Forever, plain elsewhere). RAID_TARGET_UPDATE is a
--                   global event: the Driver delivers it to bound plates as a bus message.
--   classification  boss (a boss mob, a world boss or skull level), rare elite, elite or rare,
--                   from the plain facts (re-read on UNIT_CLASSIFICATION_CHANGED and UNIT_LEVEL).
--   quest           plate.facts.isQuest (unit tooltips: C_TooltipInfo on Retail and Forever, the
--                   hidden tooltip on the Classic family, S13), refreshed a frame after
--                   QUESTS_CHANGED so the Driver's re-read lands first.
--   faction         players flagged for PvP: their faction's mark (free-for-all mark when flagged
--                   for it). Whether the flag shows is read plainly, else faded in by the engine
--                   from the possibly secret answer (SetAlphaFromBoolean).
--   focus           a mark on your focus, from the plate's 'focus' state (or the secret form of it).
--   shield          the cannot-interrupt shield while the unit casts (SetAlphaFromBoolean).
-- Art (5.5, decided in Phase 2): game atlases where the client has them, checked once each with
-- C_Texture.GetAtlasInfo; game files otherwise; Media/Star.tga stands in for the rare and elite
-- marks when their atlases are missing, and Media/Focus.tga is the focus mark everywhere. File art
-- is tinted (atlases are already colored); spec.color tints any of them. Quirk 'iconFiles' forces
-- the file art.

local WHITE = { 1, 1, 1, 1 }
local FULL_COORDS = { 0, 1, 0, 1 }
-- The emblem sits in the top left of the 64 x 64 PvP pictures
local PVP_COORDS = { 0, 0.65625, 0, 0.65625 }

---@class Plates.IconArt
---@field atlas? string
---@field file? string Game file
---@field media? string File in the core's Media folder (host.mediaPath)
---@field tint? number[] File art color
---@field coords? number[] left, right, top, bottom

---@type table<string, Plates.IconArt>
local ART = {
	elite = { atlas = 'nameplates-icon-elite-gold', media = 'Star.tga', tint = { 1, 0.82, 0.25, 1 } },
	rareelite = { atlas = 'nameplates-icon-elite-silver', media = 'Star.tga', tint = { 0.82, 0.86, 0.92, 1 } },
	rare = { atlas = 'UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star', media = 'Star.tga', tint = { 0.7, 0.8, 1, 1 } },
	boss = { file = 'Interface\\TargetingFrame\\UI-TargetingFrame-Skull' },
	quest = { atlas = 'QuestNormal', file = 'Interface\\GossipFrame\\AvailableQuestIcon' },
	Alliance = { atlas = 'UI-HUD-UnitFrame-Player-PVP-AllianceIcon', file = 'Interface\\TargetingFrame\\UI-PVP-Alliance', coords = PVP_COORDS },
	Horde = { atlas = 'UI-HUD-UnitFrame-Player-PVP-HordeIcon', file = 'Interface\\TargetingFrame\\UI-PVP-Horde', coords = PVP_COORDS },
	ffa = { atlas = 'UI-HUD-UnitFrame-Player-PVP-FFAIcon', file = 'Interface\\TargetingFrame\\UI-PVP-FFA', coords = PVP_COORDS },
	focus = { media = 'Focus.tga', tint = { 0.35, 0.65, 1, 1 } },
	shield = { atlas = 'nameplates-InterruptShield', file = 'Interface\\Icons\\Spell_Holy_PowerWordShield' },
}

local CAST_EVENTS = {
	'UNIT_SPELLCAST_START',
	'UNIT_SPELLCAST_STOP',
	'UNIT_SPELLCAST_FAILED',
	'UNIT_SPELLCAST_INTERRUPTED',
	'UNIT_SPELLCAST_CHANNEL_START',
	'UNIT_SPELLCAST_CHANNEL_STOP',
	'UNIT_SPELLCAST_EMPOWER_START',
	'UNIT_SPELLCAST_EMPOWER_STOP',
	'UNIT_SPELLCAST_INTERRUPTIBLE',
	'UNIT_SPELLCAST_NOT_INTERRUPTIBLE',
}

local function Unpack(color)
	if type(color) ~= 'table' then
		return 1, 1, 1, 1
	end
	return color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
end

local atlasKnown = {}

---True when the client has an atlas (asked once per name).
---@param name string
---@return boolean
local function HasAtlas(name)
	local known = atlasKnown[name]
	if known == nil then
		known = false
		if C_Texture and C_Texture.GetAtlasInfo then
			local ok, info = pcall(C_Texture.GetAtlasInfo, name)
			known = ok and info ~= nil
		end
		atlasKnown[name] = known
	end
	return known
end

local function MediaFile(name)
	local path = P.host and P.host.mediaPath
	if type(path) ~= 'string' then
		return nil
	end
	return path .. name
end

---Put the art for a mark on the texture (no show). false when there is no art for it here.
---@param widget table
---@param key string
---@return boolean
local function ApplyArt(widget, key)
	local art = ART[key]
	local texture = widget.texture
	local tint
	if art.atlas and not P.Caps:Quirk('iconFiles') and HasAtlas(art.atlas) then
		texture:SetAtlas(art.atlas)
	else
		local path = (art.media and MediaFile(art.media)) or art.file
		if not path then
			return false
		end
		texture:SetTexture(path)
		local coords = art.coords or FULL_COORDS
		texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
		tint = art.tint
	end
	texture:SetVertexColor(Unpack(widget.spec.color or tint or WHITE))
	widget.artKey = key
	return true
end

---Show a mark at full alpha. false when there is no art for it here.
---@param widget table
---@param key string
---@return boolean
local function ShowArt(widget, key)
	if widget.artKey ~= key and not ApplyArt(widget, key) then
		widget.texture:Hide()
		return false
	end
	widget.texture:SetAlpha(1)
	widget.texture:Show()
	return true
end

local function HideArt(widget)
	widget.texture:Hide()
end

----------------------------------------------------------------------------------------------------
-- Sources
----------------------------------------------------------------------------------------------------

---@class Plates.IconSource
---@field events string[]
---@field on table<string, boolean> Events and messages that refill
---@field Fill fun(widget: table, src: Plates.Source, event: string)

---@type table<string, Plates.IconSource>
local SOURCES = {}

local function Define(id, def)
	def.events = def.events or {}
	def.on = {}
	for _, event in ipairs(def.events) do
		def.on[event] = true
	end
	for _, message in ipairs(def.messages or {}) do
		def.on[message] = true
	end
	SOURCES[id] = def
end

Define('raidMarker', {
	messages = { 'RAID_TARGET_UPDATE' },
	Fill = function(widget, src)
		local texture = widget.texture
		if widget.artKey ~= 'raidMarker' then
			texture:SetVertexColor(Unpack(widget.spec.color or WHITE))
			widget.artKey = 'raidMarker'
		end
		texture:SetAlpha(1)
		Secret.SetRaidMarker(texture, src:RaidMarkerSecret())
	end,
})

Define('classification', {
	events = { 'UNIT_CLASSIFICATION_CHANGED', 'UNIT_LEVEL' },
	Fill = function(widget, src, event)
		local facts = widget.plate.facts
		local classification, level = facts.classification, facts.effectiveLevel
		if event == 'UNIT_CLASSIFICATION_CHANGED' then
			classification = (src:ClassificationPlain())
		elseif event == 'UNIT_LEVEL' then
			level = (src:LevelPlain())
		end
		local key
		if facts.isBoss == true or classification == 'worldboss' or level == -1 then
			key = 'boss'
		elseif classification == 'rareelite' or classification == 'elite' or classification == 'rare' then
			key = classification
		end
		if key then
			ShowArt(widget, key)
		else
			HideArt(widget)
		end
	end,
})

Define('quest', {
	Fill = function(widget)
		if widget.plate.facts.isQuest then
			ShowArt(widget, 'quest')
		else
			HideArt(widget)
		end
	end,
})

Define('faction', {
	events = { 'UNIT_FACTION' },
	Fill = function(widget, src)
		if not widget.plate.facts.isPlayer then
			HideArt(widget)
			return
		end
		local ffa, ffaReadable = src:IsFreeForAllPlain()
		if ffaReadable and ffa then
			ShowArt(widget, 'ffa')
			return
		end
		local faction = src:FactionPlain()
		if (faction ~= 'Alliance' and faction ~= 'Horde') or not ShowArt(widget, faction) then
			HideArt(widget)
			return
		end
		local flagged, readable = src:IsPvPPlain()
		if readable then
			widget.texture:SetAlpha(flagged and 1 or 0)
		else
			Secret.SetAlphaFromBoolean(widget.texture, src:IsPvPSecret(), 1, 0)
		end
	end,
})

---True while the Driver knows the focus only from hidden answers (S4). The mark's alpha then
---carries the engine's answer from OnStateSecret, and a refill must leave it alone.
---@return boolean
local function FocusOnlyFromEngine()
	local driver = P.Driver
	return driver ~= nil and driver.secretStates ~= nil and driver.secretStates.focus == true
end

Define('focus', {
	-- After a focus change the Driver relays FOCUS_CHANGED once every plate has its state
	messages = { 'FOCUS_CHANGED' },
	Fill = function(widget)
		if widget.focusFromEngine then
			if FocusOnlyFromEngine() then
				return
			end
			widget.focusFromEngine = nil
		end
		if widget.plate.states.focus then
			ShowArt(widget, 'focus')
		else
			HideArt(widget)
		end
	end,
})

Define('shield', {
	events = CAST_EVENTS,
	Fill = function(widget, src)
		if not src:CastKind() or not ShowArt(widget, 'shield') then
			HideArt(widget)
			return
		end
		Secret.SetAlphaFromBoolean(widget.texture, src:NotInterruptibleSecret(), 1, 0)
	end,
})

----------------------------------------------------------------------------------------------------
-- Part
----------------------------------------------------------------------------------------------------

---@class Plates.IconParts
local IconParts = { SOURCES = SOURCES, ART = ART }
P.IconParts = IconParts

---Why an icon source may stay empty on this client, for badges in the options and designer. nil
---when it always works.
---@param source string
---@return string|nil
function IconParts.Limit(source)
	if source == 'quest' then
		if not P.Caps:Get('tooltipData') then
			return L['Shows only when the game lists quest goals in the mob tooltip']
		end
		return L['Shows only in the open world']
	elseif source == 'faction' then
		return L['Shows only on players flagged for PvP']
	end
	return nil
end

local function Fill(widget, src, event)
	local def = SOURCES[widget.spec.source]
	if def then
		def.Fill(widget, src, event)
	end
end

local NO_EVENTS = {} -- read only

P.Parts:Register({
	id = 'icon',
	kinds = { 'icon' },
	messages = { 'RAID_TARGET_UPDATE', 'QUESTS_CHANGED', 'FOCUS_CHANGED' },
	events = function(spec)
		local def = SOURCES[spec.source]
		return def and def.events or NO_EVENTS
	end,
	Create = function(plate)
		local holder = CreateFrame('Frame', nil, plate.art)
		local texture = holder:CreateTexture(nil, 'ARTWORK')
		texture:SetAllPoints(holder)
		texture:Hide()
		return { frame = holder, texture = texture, textures = { texture } }
	end,
	Layout = function(widget, spec, ctx)
		local size = spec.size or 16
		widget.frame:SetSize(size, size)
		ctx:Anchor(widget.frame, spec.anchor)
		local key = widget.artKey
		widget.artKey = nil
		if widget.lastSource ~= spec.source then
			-- A part id can change source between styles: drop what the last one showed
			widget.lastSource = spec.source
			HideArt(widget)
		elseif key == 'raidMarker' then
			widget.texture:SetVertexColor(Unpack(spec.color or WHITE))
			widget.artKey = key
		elseif key then
			-- Same mark: take the new color without showing a hidden mark
			ApplyArt(widget, key)
		end
	end,
	Update = function(widget, src, event)
		local def = SOURCES[widget.spec.source]
		if not def then
			return
		end
		if event == 'QUESTS_CHANGED' then
			if widget.spec.source == 'quest' then
				-- The Driver re-reads quest facts on the same message; look a frame later
				if not widget.questJob then
					widget.questJob = tostring(widget) .. 'quest'
					widget.questFill = function()
						if widget.active and widget.plate.src then
							Fill(widget, widget.plate.src, 'FULL')
						end
					end
				end
				P.Scheduler:NextFrame(widget.questJob, widget.questFill)
			end
			return
		end
		if event == 'FULL' or def.on[event] then
			def.Fill(widget, src, event)
		end
	end,
	OnState = function(widget, state)
		if state == 'focus' and widget.spec.source == 'focus' and widget.plate.src then
			widget.focusFromEngine = nil
			Fill(widget, widget.plate.src, 'FULL')
		end
	end,
	OnStateSecret = function(widget, state, boolSecret)
		if state == 'focus' and widget.spec.source == 'focus' and ShowArt(widget, 'focus') then
			widget.focusFromEngine = true
			Secret.SetAlphaFromBoolean(widget.texture, boolSecret, 1, 0)
		end
	end,
	Reset = function(widget)
		widget.focusFromEngine = nil
		widget.texture:Hide()
		widget.texture:SetAlpha(1)
	end,
})
