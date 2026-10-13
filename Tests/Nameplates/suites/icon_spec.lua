-- @runtime lua51
-- Icon parts on live plates and samples, on every client: the raid marker goes through the sprite
-- sheet sink (secret on Retail and Forever, forced hidden elsewhere), classification, quest,
-- faction, focus and shield marks pick game atlases where the client has them and fall back to
-- game or bundled files, and hidden answers only reach alpha sinks.
local M, H = ...
local S = M.S

if not H.ModuleExists() then
	describe('icon parts', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

M.Login('NameplatesTestHost')

local function I(source, extra)
	local part = { kind = 'icon', source = source, anchor = { 'CENTER', 'plate', 'CENTER', 0, 0 }, size = 14 }
	for k, v in pairs(extra or {}) do
		part[k] = v
	end
	return part
end

local STYLE = {
	id = 'iconTest',
	name = 'Icon test',
	version = 1,
	schema = 1,
	order = 991,
	internal = true,
	plate = { sizes = { small = { 100, 8 }, medium = { 120, 10 }, large = { 140, 12 } } },
	parts = {
		health = { order = 1, kind = 'bar', source = 'health', fill = 'plate' },
		marker = I('raidMarker', { order = 10 }),
		class = I('classification', { order = 11 }),
		quest = I('quest', { order = 12 }),
		faction = I('faction', { order = 13 }),
		focus = I('focus', { order = 14 }),
		shield = I('shield', { order = 15 }),
		tinted = I('classification', { order = 16, color = { 0, 1, 0, 1 } }),
	},
}

local function Core(opts)
	local P = H.FreshCore(opts)
	P.Styles.Registry:RegisterBuiltin(STYLE)
	return P
end

local P = Core()

local function Icon(plate, id)
	local widget = plate:GetWidget(id)
	assert.not_nil(widget, 'part ' .. id)
	return widget.texture, widget
end

local function Shown(texture)
	return M.Get(texture, 'shown') ~= false
end

local function Live(spec, core)
	core = core or P
	local token, base, unit = M.ShowPlate(spec)
	local plate = core.Plate.New(UIParent, false)
	local src = core.Source.NewLive(token)
	src:ReadFacts(plate.facts)
	plate:ApplyStyle(core.Styles.Merge:Resolve('iconTest', 'enemyNPC', 'medium'))
	plate:Bind(token, src)
	return plate, unit, token, base
end

local function Done(plate, token)
	plate:Unbind()
	M.HidePlate(token)
end

describe('icon parts: loading', function()
	it('accepts every icon source in a style', function()
		local cleaned, report, reason = P.Styles.Schema:ValidateStyle(STYLE)
		assert.not_nil(cleaned, tostring(reason))
		assert.equal(report.dropped, 0, table.concat(report.droppedKeys, ', '))
		for _, source in ipairs(P.Styles.Schema.ICON_SOURCES) do
			assert.not_nil(P.IconParts.SOURCES[source], 'icon source ' .. source .. ' has a handler')
		end
	end)

	it('only uses file paths with folders and bundled art from the host media path', function()
		for key, art in pairs(P.IconParts.ART) do
			assert.truthy(art.atlas or art.file or art.media, key)
			if art.file then
				assert.matches(art.file, '\\', key .. ' is a file path')
			end
		end
	end)
end)

describe('icon parts: raid marker', function()
	it('draws the marker cell and hides without one', function()
		local plate, unit, token = Live({ raidMarker = 8 })
		local texture = Icon(plate, 'marker')
		assert.is_true(Shown(texture))
		local cells = M.Calls(texture, 'SetSpriteSheetCell')
		assert.truthy(#cells > 0, 'the sprite sheet sink drew it')
		assert.equal(S.Reveal(cells[#cells][1]), 8)
		unit.raidMarker = nil
		plate:OnMessage('RAID_TARGET_UPDATE')
		assert.is_false(Shown(texture))
		Done(plate, token)
	end)

	it('draws a hidden marker index without reading it', function()
		local plate, unit, token = Live({ raidMarker = 3 })
		M.SetRestricted(true, nil, true)
		plate:OnMessage('RAID_TARGET_UPDATE')
		local texture = Icon(plate, 'marker')
		local cells = M.Calls(texture, 'SetSpriteSheetCell')
		assert.is_true(S.IsSecret(cells[#cells][1]), 'the index stayed hidden')
		assert.equal(S.Reveal(cells[#cells][1]), 3)
		assert.is_true(Shown(texture))
		M.SetRestricted(false)
		unit.raidMarker = nil
		Done(plate, token)
	end)
end)

describe('icon parts: classification', function()
	it('marks elites, rare elites, rares and bosses with game atlases', function()
		local plate, unit, token = Live({ classification = 'elite', level = 61 })
		local texture = Icon(plate, 'class')
		assert.is_true(Shown(texture))
		assert.equal(M.Get(texture, 'atlas'), 'nameplates-icon-elite-gold')
		M.UpdateUnit(unit, { classification = 'rareelite' }, { 'UNIT_CLASSIFICATION_CHANGED' })
		assert.equal(M.Get(texture, 'atlas'), 'nameplates-icon-elite-silver')
		M.UpdateUnit(unit, { classification = 'rare' }, { 'UNIT_CLASSIFICATION_CHANGED' })
		assert.equal(M.Get(texture, 'atlas'), 'UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star')
		M.UpdateUnit(unit, { classification = 'normal' }, { 'UNIT_CLASSIFICATION_CHANGED' })
		assert.is_false(Shown(texture))
		M.UpdateUnit(unit, { level = -1 }, { 'UNIT_LEVEL' })
		assert.is_true(Shown(texture))
		assert.matches(M.Get(texture, 'texture'), 'UI%-TargetingFrame%-Skull')
		Done(plate, token)
	end)

	it('tints marks with the part color', function()
		local plate, _, token = Live({ classification = 'elite' })
		local texture = Icon(plate, 'tinted')
		local color = M.Get(texture, 'vertex')
		assert.equal(color[1], 0)
		assert.equal(color[2], 1)
		Done(plate, token)
	end)

	it('falls back to bundled art, tinted, when the atlas is missing', function()
		M.missingAtlases = { ['nameplates-icon-elite-gold'] = true }
		local core = Core()
		local plate, _, token = Live({ classification = 'elite' }, core)
		local texture = Icon(plate, 'class')
		assert.is_nil(M.Get(texture, 'atlas'))
		assert.equal(M.Get(texture, 'texture'), core.host.mediaPath .. 'Star.tga')
		local color = M.Get(texture, 'vertex')
		assert.near(color[2], 0.82, 0.001, 'gold tint')
		Done(plate, token)
		M.missingAtlases = nil
	end)

	it('uses game and bundled files for every mark under the iconFiles quirk', function()
		P.Caps:SetOverride('quirk:iconFiles', true)
		local plate, unit, token = Live({ classification = 'rare', isPlayer = false })
		local texture = Icon(plate, 'class')
		assert.matches(M.Get(texture, 'texture'), 'Star%.tga$')
		plate:SetState('focus', true)
		assert.matches(M.Get(Icon(plate, 'focus'), 'texture'), 'Focus%.tga$')
		M.StartCast(unit, { name = 'Bolt', duration = 2, notInterruptible = true })
		assert.matches(M.Get(Icon(plate, 'shield'), 'texture'), '\\')
		M.StopCast(unit, 'stop')
		P.Caps:SetOverride('quirk:iconFiles', nil)
		Done(plate, token)
	end)
end)

describe('icon parts: quest', function()
	it('marks quest mobs and looks again a frame after the quest log changes', function()
		local plate, _, token = Live({ questBoss = true })
		local texture = Icon(plate, 'quest')
		if not UnitIsQuestBoss then
			plate.facts.isQuest = true
			plate:UpdateAll('FULL')
		end
		assert.is_true(Shown(texture))
		assert.equal(M.Get(texture, 'atlas'), 'QuestNormal')
		plate.facts.isQuest = nil
		plate:OnMessage('QUESTS_CHANGED')
		assert.is_true(Shown(texture), 'waits for the Driver to re-read the facts')
		M.Advance(0.1)
		assert.is_false(Shown(texture))
		Done(plate, token)
	end)
end)

describe('icon parts: faction', function()
	it('marks players flagged for PvP and nobody else', function()
		local plate, unit, token = Live({ isPlayer = true, faction = 'Horde', pvp = true })
		local texture = Icon(plate, 'faction')
		assert.is_true(Shown(texture))
		assert.equal(M.Get(texture, 'atlas'), 'UI-HUD-UnitFrame-Player-PVP-HordeIcon')
		assert.equal(M.Get(texture, 'alpha'), 1)
		M.UpdateUnit(unit, { pvp = false }, { 'UNIT_FACTION' })
		assert.equal(M.Get(texture, 'alpha'), 0)
		Done(plate, token)
		local npc, _, npcToken = Live({ isPlayer = false, pvp = true })
		assert.is_false(Shown(Icon(npc, 'faction')))
		Done(npc, npcToken)
	end)

	it('fades the mark from a hidden PvP flag without reading it', function()
		local plate, _, token = Live({ isPlayer = true, faction = 'Alliance', pvp = true })
		M.SetRestricted(true, nil, true)
		plate:UpdateAll('FULL')
		local texture = Icon(plate, 'faction')
		assert.is_true(M.Get(texture, 'alphaSecret'), 'the engine faded it from the hidden flag')
		assert.equal(M.Get(texture, 'alpha'), 1)
		assert.equal(M.Get(texture, 'atlas'), 'UI-HUD-UnitFrame-Player-PVP-AllianceIcon')
		M.SetRestricted(false)
		Done(plate, token)
	end)
end)

describe('icon parts: focus and shield', function()
	it('marks your focus from a plain or a hidden state', function()
		local plate, _, token = Live({})
		local texture = Icon(plate, 'focus')
		assert.is_false(Shown(texture))
		plate:SetState('focus', true)
		assert.is_true(Shown(texture))
		local color = M.Get(texture, 'vertex')
		assert.near(color[3], 1, 0.001, 'focus blue')
		plate:SetState('focus', false)
		assert.is_false(Shown(texture))
		plate:SetStateSecret('focus', S.Wrap(true))
		assert.is_true(Shown(texture))
		assert.equal(M.Get(texture, 'alpha'), 1)
		assert.is_true(M.Get(texture, 'alphaSecret'))
		plate:SetStateSecret('focus', S.Wrap(false))
		assert.equal(M.Get(texture, 'alpha'), 0)
		Done(plate, token)
	end)

	it('keeps a hidden focus answer through refills until the focus is known again', function()
		local plate, _, token = Live({})
		local texture = Icon(plate, 'focus')
		local secretStates = P.Driver.secretStates
		secretStates.focus = true
		plate:SetStateSecret('focus', S.Wrap(true))
		plate:UpdateAll('FULL')
		assert.is_true(Shown(texture), 'a refill keeps the engine answer')
		assert.equal(M.Get(texture, 'alpha'), 1)
		plate:OnMessage('FOCUS_CHANGED')
		assert.is_true(Shown(texture), 'still known only from hidden answers')
		-- The focus is plain again (cleared, or found by frame compare elsewhere)
		secretStates.focus = nil
		plate:OnMessage('FOCUS_CHANGED')
		assert.is_false(Shown(texture), 'the plain answer takes over')
		Done(plate, token)
	end)

	it('shows the shield only on casts that cannot be interrupted', function()
		local plate, unit, token = Live({ canAttack = true })
		local texture = Icon(plate, 'shield')
		assert.is_false(Shown(texture))
		M.StartCast(unit, { name = 'Bolt', duration = 2, notInterruptible = true })
		assert.is_true(Shown(texture))
		assert.equal(M.Get(texture, 'alpha'), 1)
		M.StopCast(unit, 'stop')
		assert.is_false(Shown(texture))
		M.StartCast(unit, { name = 'Bolt', duration = 2, notInterruptible = false })
		assert.equal(M.Get(texture, 'alpha'), 0)
		M.StopCast(unit, 'stop')
		M.SetRestricted(true, nil, true)
		M.StartCast(unit, { name = 'Bolt', duration = 2, notInterruptible = true })
		assert.equal(M.Get(texture, 'alpha'), 1)
		M.StopCast(unit, 'stop')
		M.SetRestricted(false)
		Done(plate, token)
	end)
end)

describe('icon parts: lifecycle and previews', function()
	it('clears a role texture when the sample no longer has a role', function()
		local texture = UIParent:CreateTexture()
		local widget = { texture = texture, spec = {}, plate = { facts = {} } }
		local src = P.Source.NewSample({ role = 'TANK' })
		P.IconParts.SOURCES.roleIcon.Fill(widget, src)
		assert.matches(M.Get(texture, 'texture'), 'DefensiveStance')
		assert.equal(M.Get(texture, 'alpha'), 1)
		src:SetSample({})
		P.IconParts.SOURCES.roleIcon.Fill(widget, src)
		assert.is_nil(M.Get(texture, 'texture'))
		assert.equal(M.Get(texture, 'alpha'), 0)
	end)

	it('hides every mark on unbind', function()
		local plate, _, token = Live({ raidMarker = 2, classification = 'elite' })
		plate:Unbind()
		for _, id in ipairs({ 'marker', 'class', 'quest', 'faction', 'focus', 'shield' }) do
			assert.is_false(Shown(Icon(plate, id)), id)
		end
		M.HidePlate(token)
	end)

	it('draws every sample', function()
		for id, sample in pairs(P.Data.Samples) do
			local plate = P.Plate.New(UIParent, true)
			plate:ApplyStyle(P.Styles.Merge:Resolve('iconTest', 'enemyNPC', 'medium'))
			plate:BindSample(P.Source.NewSample(id))
			assert.equal(Shown(Icon(plate, 'marker')), sample.raidMarker ~= nil, id .. ' marker')
			assert.equal(Shown(Icon(plate, 'quest')), sample.quest == true, id .. ' quest')
			if id == 'boss' then
				assert.matches(M.Get(Icon(plate, 'class'), 'texture'), 'Skull')
			end
			plate:Unbind()
		end
	end)

	it('gives a reason for marks that can stay empty', function()
		assert.not_nil(P.IconParts.Limit('quest'))
		assert.not_nil(P.IconParts.Limit('faction'))
		assert.is_nil(P.IconParts.Limit('raidMarker'))
	end)
end)
