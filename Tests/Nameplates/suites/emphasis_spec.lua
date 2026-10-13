-- @runtime lua51
-- Target emphasis art and glows (plan 5.5, 3.5, 6.4): every highlight art and every glow look
-- draws on every client (the art set's pictures when they exist, plain stand-ins until then),
-- highlights follow target, focus and mouseover with their own looks and fade in on the shared
-- scheduler, glows take secret answers and colors only through sinks, the plate-wide glow
-- sources degrade with a reason where the game hides what they need, and nothing runs a
-- per-plate OnUpdate.
local M, H = ...
local S = M.S

if not H.ModuleExists() then
	describe('emphasis', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

M.Login('NameplatesTestHost')
local P = H.FreshCore()
local Merge = P.Styles.Merge
local Highlight, GlowLib, Art = P.Highlight, P.GlowLib, P.Data.ArtAliases
local LSM = LibStub('LibSharedMedia-3.0')

---A secret where the client has secrets, a plain value elsewhere.
local function Hidden(v)
	if M.secrets then
		return S.Wrap(v)
	end
	return v
end

local made = 0

---A resolved test style with the given parts (plus the usual tokens).
local function Resolved(parts, states)
	made = made + 1
	local resolved = Merge.ResolveRaw({
		id = 'emphasisTest',
		name = 'Emphasis test',
		version = 1,
		schema = 1,
		plate = { sizes = { small = { 112, 8 }, medium = { 132, 10 }, large = { 156, 12 } } },
		tokens = { accent = { 0.2, 0.4, 0.6, 1 }, font = 'Fonts\\FRIZQT__.TTF', bar = 'Nameplates Flat', ink = { 0, 0, 0, 1 }, shade = { 0, 0, 0, 0.6 } },
		parts = parts,
		states = states or { target = { grow = { 14, 2 } }, notTarget = { alpha = 0.75 } },
	}, nil, 'enemyNPC', 'medium', nil)
	resolved.key = 'emphasis' .. made
	return resolved
end

local function NewPlate(parts, states, isPreview, ctx)
	local plate = P.Plate.New(UIParent, isPreview or false, ctx)
	plate:ApplyStyle(Resolved(parts, states))
	return plate
end

local function Drawn(widget)
	local count = 0
	for _, pool in pairs(widget.pools) do
		count = count + pool.nt + pool.nl
	end
	if widget.usesGlow then
		count = count + widget.glow.count
	end
	return count
end

local function NoGeometryReads(plate)
	local function Refuse()
		error('read plate geometry back')
	end
	plate.art.GetSize, plate.art.GetWidth, plate.art.GetHeight, plate.art.GetAlpha = Refuse, Refuse, Refuse, Refuse
end

local function Forget(mediaType, key)
	local list = LSM:HashTable(mediaType)
	if list then
		list[key] = nil
	end
end

local tokenCount = 40
local function LivePlate(parts, unitSpec)
	tokenCount = tokenCount + 1
	local token = 'nameplate' .. tokenCount
	local unit = M.AddUnit(unitSpec or { canAttack = true, reaction = 2 })
	M.SetToken(token, unit)
	local plate = NewPlate(parts)
	local src = P.Source.NewLive(token)
	src:ReadFacts(plate.facts)
	plate:Bind(token, src)
	return plate, unit, token
end

describe('emphasis: highlight art', function()
	it('draws every highlight art from plain shapes until the art set paints it', function()
		for _, art in ipairs(Highlight.ARTS) do
			assert.not_nil(Art:Slot('highlight', art), art .. ' has an art slot for the art set')
			local plate = NewPlate({ hl = { order = 1, kind = 'highlight', art = art } })
			local widget = plate:GetWidget('hl')
			assert.truthy(Drawn(widget) > 0, art .. ' draws something')
		end
	end)

	it('mirrors arrows on both sides and keeps double arrows apart', function()
		local plate = NewPlate({ hl = { order = 1, kind = 'highlight', art = 'arrows' } })
		local widget = plate:GetWidget('hl')
		assert.equal(widget.pools.left.nl, 2, 'one chevron on the left')
		assert.equal(widget.pools.right.nl, 2, 'one chevron on the right')
		local point, relativeTo = widget.left:GetPoint(1)
		assert.equal(point, 'RIGHT')
		assert.is_true(rawequal(relativeTo, widget.frame), 'arrows hang from the highlight, which follows the plate')
		plate = NewPlate({ hl = { order = 1, kind = 'highlight', art = 'doubleArrows' } })
		widget = plate:GetWidget('hl')
		assert.equal(widget.pools.left.nl, 4)
		assert.equal(widget.pools.right.nl, 4)
	end)

	it('draws an unknown art key as arrows instead of nothing', function()
		local plate = NewPlate({ hl = { order = 1, kind = 'highlight', art = 'noSuchArt' } })
		assert.equal(plate:GetWidget('hl').pools.left.nl, 2)
	end)

	it('uses the art set picture once one is registered, mirrored or nine-sliced', function()
		LSM:Register(Art.MEDIA.highlight, 'arrows', 'Interface\\AddOns\\NameplatesTestHost\\Media\\Arrows.png')
		LSM:Register(Art.MEDIA.highlight, 'brackets', 'Interface\\AddOns\\NameplatesTestHost\\Media\\Brackets.png')
		local plate = NewPlate({ a = { order = 1, kind = 'highlight', art = 'arrows' }, b = { order = 2, kind = 'highlight', art = 'brackets' } })
		local arrows = plate:GetWidget('a')
		assert.equal(arrows.pools.left.nl, 0, 'no stand-in lines with a picture')
		local left, right = arrows.pools.left.textures[1], arrows.pools.right.textures[1]
		assert.matches(M.Get(left, 'texture'), 'Arrows%.png$')
		assert.same(M.Get(right, 'texCoord'), { 1, 0, 0, 1 }, 'the right picture is mirrored')
		local brackets = plate:GetWidget('b')
		local picture = brackets.pools.main.textures[1]
		assert.matches(M.Get(picture, 'texture'), 'Brackets%.png$')
		if picture.SetTextureSliceMargins then
			local calls = M.Calls(picture, 'SetTextureSliceMargins')
			assert.equal(#calls, 1, 'one nine-sliced texture, not nine textures')
		end
		Forget(Art.MEDIA.highlight, 'arrows')
		Forget(Art.MEDIA.highlight, 'brackets')
	end)

	it('follows renamed art keys', function()
		Art.map.oldArrows = 'arrows'
		assert.equal(Art:Slot('highlight', 'oldArrows').draw, 'pair')
		local plate = NewPlate({ hl = { order = 1, kind = 'highlight', art = 'oldArrows' } })
		assert.equal(plate:GetWidget('hl').pools.left.nl, 2)
		Art.map.oldArrows = nil
	end)
end)

describe('emphasis: states', function()
	it('fades the target highlight in with the plate emphasis and never reads geometry back', function()
		local plate = NewPlate({ arrows = { order = 1, kind = 'highlight', state = 'target', art = 'arrows' } })
		NoGeometryReads(plate)
		local widget = plate:GetWidget('arrows')
		assert.is_false(widget.frame:IsShown(), 'hidden until the plate is the target')
		plate:SetState('target', true)
		assert.is_true(widget.frame:IsShown())
		M.Advance(0.05)
		local mid = M.Get(widget.inner, 'alpha')
		assert.truthy(mid > 0 and mid < 1, 'fading in, got ' .. tostring(mid))
		M.Advance(0.3)
		assert.equal(M.Get(widget.inner, 'alpha'), 1)
		plate:SetState('target', false)
		assert.is_false(widget.frame:IsShown())
	end)

	it('gives mouseover and focus their own look and steps mouseover aside on the target', function()
		local plate = NewPlate({
			hover = { order = 1, kind = 'highlight', state = 'mouseover', art = 'glow' },
			focusMark = { order = 2, kind = 'highlight', state = 'focus', art = 'brackets' },
		})
		local hover, focus = plate:GetWidget('hover'), plate:GetWidget('focusMark')
		plate:SetState('mouseover', true)
		M.Advance(0.3)
		assert.near(M.Get(hover.inner, 'alpha'), Highlight.STATE_LOOK.mouseover.alpha, 1e-6)
		local vertex = M.Get(hover.glow.pieces[1], 'vertex')
		assert.near(vertex[1], 0.2 + 0.8 * Highlight.STATE_LOOK.mouseover.mix, 1e-6, 'mouseover lightens the tint')
		plate:SetState('target', true)
		assert.equal(M.Get(hover.inner, 'alpha'), 0, 'the target art is never doubled')
		plate:SetState('target', false)
		assert.near(M.Get(hover.inner, 'alpha'), Highlight.STATE_LOOK.mouseover.alpha, 1e-6)
		plate:SetState('focus', true)
		M.Advance(0.3)
		assert.near(M.Get(focus.inner, 'alpha'), Highlight.STATE_LOOK.focus.alpha, 1e-6)
	end)

	it('steps a focus highlight aside on the target only when it would double the target art', function()
		local plate = NewPlate({
			arrows = { order = 1, kind = 'highlight', state = 'target', art = 'arrows' },
			same = { order = 2, kind = 'highlight', state = 'focus', art = 'arrows' },
			other = { order = 3, kind = 'highlight', state = 'focus', art = 'brackets' },
		})
		local same, other = plate:GetWidget('same'), plate:GetWidget('other')
		plate:SetState('focus', true)
		M.Advance(0.3)
		assert.near(M.Get(same.inner, 'alpha'), Highlight.STATE_LOOK.focus.alpha, 1e-6)
		plate:SetState('target', true)
		assert.equal(M.Get(same.inner, 'alpha'), 0, 'the same arrows are not drawn twice')
		assert.near(M.Get(other.inner, 'alpha'), Highlight.STATE_LOOK.focus.alpha, 1e-6, 'other art stays')
		plate:SetState('target', false)
		assert.near(M.Get(same.inner, 'alpha'), Highlight.STATE_LOOK.focus.alpha, 1e-6)
	end)

	it('shows a target known only as a secret at the target look, without testing it', function()
		local plate = NewPlate({ arrows = { order = 1, kind = 'highlight', state = 'target', art = 'arrows', animate = 'bounce' } })
		local widget = plate:GetWidget('arrows')
		plate:SetStateSecret('target', Hidden(true))
		assert.equal(M.Get(widget.frame, 'alpha'), 1)
		assert.equal(M.Get(widget.inner, 'alpha'), 1)
		plate:SetStateSecret('target', Hidden(false))
		assert.equal(M.Get(widget.frame, 'alpha'), 0)
	end)

	it('animates with animation groups and stops them on unbind', function()
		local plate = NewPlate({
			bounce = { order = 1, kind = 'highlight', art = 'arrows', animate = 'bounce' },
			pulse = { order = 2, kind = 'highlight', art = 'underline', animate = 'pulse' },
		})
		local bounce, pulse = plate:GetWidget('bounce'), plate:GetWidget('pulse')
		assert.is_true(bounce.anims.left:IsPlaying())
		assert.is_true(bounce.anims.right:IsPlaying())
		assert.is_true(pulse.anims.pulse:IsPlaying())
		plate:Unbind()
		assert.is_false(bounce.anims.left:IsPlaying())
		assert.is_false(pulse.anims.pulse:IsPlaying())
	end)

	it('drops the target art when a plate is unbound, so a reused plate never shows it', function()
		local plate, unit, token = LivePlate({ arrows = { order = 1, kind = 'highlight', state = 'target', art = 'arrows' } })
		local widget = plate:GetWidget('arrows')
		plate:SetState('target', true)
		assert.is_true(widget.frame:IsShown())
		M.Advance(0.3)
		assert.equal(M.Get(plate.art, 'w'), plate.style.width + 14)
		plate:Unbind()
		assert.is_false(widget.frame:IsShown(), 'hidden with the unit')
		assert.equal(M.Get(plate.art, 'w'), plate.style.width, 'and the target growth goes with it')
		local src = P.Source.NewLive(token)
		src:ReadFacts(plate.facts)
		plate:Bind(token, src)
		plate:SetState('target', false)
		assert.is_false(widget.frame:IsShown(), 'a new unit that is not the target shows no arrows')
		plate:SetState('target', true)
		assert.is_true(widget.frame:IsShown())
		plate:Unbind()
		M.SetToken(token, nil)
		assert.not_nil(unit)
	end)

	it('only plays motion while the state is on', function()
		local plate = NewPlate({ arrows = { order = 1, kind = 'highlight', state = 'target', art = 'arrows', animate = 'bounce' } })
		local widget = plate:GetWidget('arrows')
		assert.is_false(widget.anims.left:IsPlaying())
		plate:SetState('target', true)
		assert.is_true(widget.anims.left:IsPlaying())
		plate:SetState('target', false)
		assert.is_false(widget.anims.left:IsPlaying())
	end)
end)

describe('emphasis: glow library', function()
	it('draws every look from stand-in rings, and the art set picture replaces them', function()
		local holder = CreateFrame('Frame', nil, UIParent)
		local glow = GlowLib.Create(holder)
		GlowLib.Layout(glow, holder, { look = 'soft', size = 6 })
		assert.equal(#glow.pieces, 0, 'a glow that never shows makes no textures')
		GlowLib.Show(glow, true)
		for _, look in ipairs(GlowLib.LOOK_ORDER) do
			assert.not_nil(Art:Slot('glow', look), look .. ' has an art slot')
			GlowLib.Layout(glow, holder, { look = look, size = 6 })
			assert.truthy(glow.count > 0, look .. ' draws rings')
			assert.is_false(M.Get(glow.picture, 'shown'))
		end
		LSM:Register(Art.MEDIA.glow, 'soft', 'Interface\\AddOns\\NameplatesTestHost\\Media\\Soft.png')
		GlowLib.Layout(glow, holder, { look = 'soft', size = 6 })
		assert.equal(glow.count, 0, 'one picture instead of rings')
		assert.is_true(M.Get(glow.picture, 'shown'))
		Forget(Art.MEDIA.glow, 'soft')
	end)

	it('takes secret answers and colors only through sinks', function()
		local holder = CreateFrame('Frame', nil, UIParent)
		local glow = GlowLib.Create(holder)
		GlowLib.Layout(glow, holder, { look = 'important', size = 6 })
		GlowLib.ShowWhenSecret(glow, Hidden(false))
		assert.equal(M.Get(glow.gate, 'alpha'), 0)
		if M.secrets then
			assert.is_true(M.Get(glow.gate, 'alphaSecret'), 'the answer reached the engine untouched')
		end
		GlowLib.ShowWhenSecret(glow, Hidden(true))
		assert.equal(M.Get(glow.gate, 'alpha'), 1)
		GlowLib.ShowWhenSecret(glow, nil)
		assert.equal(M.Get(glow.gate, 'alpha'), 0, 'no answer counts as false')
		GlowLib.SetColorSecret(glow, Hidden(1), Hidden(0.5), Hidden(0), Hidden(1))
		local vertex = M.Get(glow.pieces[1], 'vertex')
		assert.equal(vertex[2], 0.5)
		if M.secrets then
			assert.is_true(vertex.secret)
		end
	end)

	it('fades in and out on the shared scheduler and pulses with an animation group', function()
		local holder = CreateFrame('Frame', nil, UIParent)
		local glow = GlowLib.Create(holder)
		GlowLib.Layout(glow, holder, { look = 'important', size = 4 })
		GlowLib.Show(glow)
		assert.is_true(glow.anim:IsPlaying())
		M.Advance(0.3)
		assert.equal(M.Get(glow.fade, 'alpha'), 1)
		GlowLib.Hide(glow)
		assert.is_true(M.Get(glow.gate, 'shown'), 'still fading out')
		M.Advance(0.5)
		assert.is_false(M.Get(glow.gate, 'shown'))
		assert.is_false(glow.anim:IsPlaying())
		GlowLib.Layout(glow, holder, { look = 'soft', size = 4 })
		GlowLib.Show(glow)
		assert.is_false(glow.anim:IsPlaying(), 'the soft look does not pulse')
	end)
end)

describe('emphasis: glow parts', function()
	before_each(function()
		M.importantSpells = nil
	end)

	it('glows on important casts, through the secret answer where the game hides it', function()
		local plate, unit = LivePlate({ imp = { order = 1, kind = 'glow', source = 'importantCast' } })
		local glow = plate:GetWidget('imp').glow
		assert.is_false(GlowLib.IsShown(glow))
		M.importantSpells = { [500] = true }
		M.StartCast(unit, { spellID = 500, duration = 2 })
		assert.is_true(GlowLib.IsShown(glow))
		assert.equal(M.Get(glow.gate, 'alpha'), 1)
		M.StopCast(unit, 'stop')
		M.Advance(0.5)
		assert.is_false(M.Get(glow.gate, 'shown'), 'faded out with the cast')
		M.StartCast(unit, { spellID = 501, duration = 2 })
		assert.equal(M.Get(glow.gate, 'alpha'), 0, 'an ordinary cast does not glow')
		M.StopCast(unit, 'stop')
		if M.SetRestricted(true) then
			M.StartCast(unit, { spellID = 500, duration = 2 })
			assert.equal(M.Get(glow.gate, 'alpha'), 1)
			M.StopCast(unit, 'stop')
			M.SetRestricted(false)
		end
		plate:Unbind()
	end)

	it('glows when the enemy has a buff you can remove, or says why it cannot', function()
		local plate, unit = LivePlate({ purge = { order = 1, kind = 'glow', source = 'purge' } })
		local glow = plate:GetWidget('purge').glow
		M.ApplyAura(unit, { spellId = 600, dispelName = 'Magic', duration = 30 })
		if P.Caps:Get('secrets') then
			assert.is_false(GlowLib.IsShown(glow))
			assert.not_nil(GlowLib.Limit('purge'), 'a reason for the options')
			local found = false
			for _, line in ipairs(H.logs.host or {}) do
				if line:find('purge glow is off', 1, true) then
					found = true
				end
			end
			assert.is_true(found, 'logged once')
		else
			assert.is_true(GlowLib.IsShown(glow))
			assert.is_nil(GlowLib.Limit('purge'))
		end
		plate:Unbind()
	end)

	it('leaves out buffs the player listed as never removable', function()
		if P.Caps:Get('secrets') then
			skip('the purge glow is off where the game hides buff details')
		end
		P.Store:Set({ 'auras', 'removable', 'never' }, { [610] = true })
		local plate, unit = LivePlate({ purge = { order = 1, kind = 'glow', source = 'purge' } })
		local glow = plate:GetWidget('purge').glow
		M.ApplyAura(unit, { spellId = 610, dispelName = 'Magic', duration = 30 })
		assert.is_false(GlowLib.IsShown(glow), 'on the never list')
		M.ApplyAura(unit, { spellId = 611, isStealable = true, duration = 30 })
		assert.is_true(GlowLib.IsShown(glow))
		P.Store:Set({ 'auras', 'removable', 'never' }, nil)
		plate:Unbind()
	end)

	it('glows when your debuff enters its refresh window, checked by one shared task', function()
		local plate, unit = LivePlate({ pandemic = { order = 1, kind = 'glow', source = 'pandemic' } })
		local glow = plate:GetWidget('pandemic').glow
		M.ApplyAura(unit, { spellId = 700, isHarmful = true, sourceUnit = 'player', duration = 10 })
		assert.is_false(GlowLib.IsShown(glow), 'fresh debuff')
		M.Advance(7.3)
		if P.Caps:Get('secrets') then
			assert.is_false(GlowLib.IsShown(glow), 'off where the game hides aura timers')
		else
			assert.is_true(GlowLib.IsShown(glow), 'inside the last 30%')
		end
		plate:Unbind()
		M.Advance(0.3)
		assert.is_false(P.Scheduler:IsRunning('Glow.pandemic'), 'the shared check stops when nothing waits')
	end)

	it('shows the refresh window in previews from sample timers', function()
		local plate = NewPlate({ pandemic = { order = 1, kind = 'glow', source = 'pandemic' } }, nil, true)
		plate:BindSample(P.Source.NewSample('casterTarget'))
		assert.is_true(GlowLib.IsShown(plate:GetWidget('pandemic').glow))
	end)

	it('glows on the target, from the secret answer when that is all there is', function()
		local plate = NewPlate({ t = { order = 1, kind = 'glow', source = 'target' } })
		local glow = plate:GetWidget('t').glow
		plate:SetState('target', true)
		assert.is_true(GlowLib.IsShown(glow))
		plate:SetState('target', false)
		assert.is_false(GlowLib.IsShown(glow))
		plate:SetStateSecret('target', Hidden(true))
		assert.is_true(GlowLib.IsShown(glow))
		assert.equal(M.Get(glow.gate, 'alpha'), 1)
	end)

	it('never gives a plate its own OnUpdate', function()
		for _, record in ipairs(M.rec.onUpdates) do
			local where = tostring(record.where)
			assert.falsy(where:find('Highlight.lua', 1, true) or where:find('Glow.lua', 1, true) or where:find('Threat.lua', 1, true), 'OnUpdate set at ' .. where)
		end
	end)
end)
