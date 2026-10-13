-- @runtime lua51
-- Text parts on live plates and samples, on every client: each source fills from the Source
-- object, values the game hides go straight into sinks (strict secret mock on Retail and
-- Forever), health text hides at full health without reading a hidden value, cast time runs on
-- the shared scheduler where no binding exists, arena labels compare base plates, the name fill
-- uses only bar sinks, and the scan tooltip on the Classic family is made only when first used.
local M, H = ...
local S = M.S

if not H.ModuleExists() then
	describe('text parts', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

M.Login('NameplatesTestHost')
local P = H.FreshCore()
local Merge = P.Styles.Merge

local function T(source, extra)
	local part = { kind = 'text', source = source, anchor = { 'CENTER', 'plate', 'CENTER', 0, 0 }, font = { size = 10 } }
	for k, v in pairs(extra or {}) do
		part[k] = v
	end
	return part
end

local STYLE = {
	id = 'textTest',
	name = 'Text test',
	version = 1,
	schema = 1,
	order = 990,
	internal = true,
	plate = { sizes = { small = { 100, 8 }, medium = { 120, 10 }, large = { 140, 12 } } },
	parts = {
		health = { order = 1, kind = 'bar', source = 'health', fill = 'plate' },
		name = T('name', { order = 10, colors = 'name' }),
		fill = T('nameFill', { order = 11, bg = { 0.2, 0.2, 0.2, 1 }, justify = 'LEFT' }),
		level = T('level', { order = 12 }),
		pct = T('healthPercent', { order = 13 }),
		pctHide = T('healthPercent', { order = 14, hideAtFull = true, color = { 1, 1, 0, 1 } }),
		value = T('healthValue', { order = 15 }),
		valueLong = T('healthValue', { order = 16, abbreviate = false }),
		valueHide = T('healthValue', { order = 17, hideAtFull = true }),
		forces = T('forces', { order = 18 }),
		title = T('title', { order = 19 }),
		threat = T('threatPercent', { order = 20 }),
		castName = T('castName', { order = 21 }),
		castTarget = T('castTarget', { order = 22 }),
		castTime = T('castTime', { order = 23 }),
		arena = T('arena', { order = 24 }),
	},
}
P.Styles.Registry:RegisterBuiltin(STYLE)

local function Text(plate, id)
	local widget = plate:GetWidget(id)
	assert.not_nil(widget, 'part ' .. id)
	return widget.text, widget
end

local function Shown(fontString)
	return S.Reveal(M.Get(fontString, 'text'))
end

local function Live(spec)
	local token, base, unit = M.ShowPlate(spec)
	local plate = P.Plate.New(UIParent, false)
	local src = P.Source.NewLive(token)
	src:ReadFacts(plate.facts)
	plate:ApplyStyle(Merge:Resolve('textTest', 'enemyNPC', 'medium'))
	plate:Bind(token, src)
	return plate, unit, token, base
end

local function Done(plate, token)
	plate:Unbind()
	M.HidePlate(token)
end

describe('text parts: loading', function()
	it('makes no scan tooltip until a plate needs one', function()
		assert.is_nil(rawget(_G, P.host.globalPrefix .. 'ScanTip'))
	end)

	it('accepts every text source and the new fields in a style', function()
		local cleaned, report, reason = P.Styles.Schema:ValidateStyle(STYLE)
		assert.not_nil(cleaned, tostring(reason))
		assert.equal(report.dropped, 0, table.concat(report.droppedKeys, ', '))
		assert.equal(report.clamped, 0)
		assert.equal(report.fixed, 0)
		for _, source in ipairs(P.Styles.Schema.TEXT_SOURCES) do
			assert.not_nil(P.TextParts.SOURCES[source], 'text source ' .. source .. ' has a handler')
		end
	end)

	it('counts the name fill in the click area like the name', function()
		assert.is_true(Merge.REGION_TEXT_SOURCES.nameFill == true)
	end)

	it('gives a reason for sources that can stay empty', function()
		assert.not_nil(P.TextParts.Limit('forces'))
		assert.not_nil(P.TextParts.Limit('arena'))
		assert.is_nil(P.TextParts.Limit('name'))
	end)
end)

describe('text parts: names', function()
	it('refreshes special mob names and both fill copies when the list changes', function()
		local plate, _, token = Live({ name = 'Original name', npcID = 5925 })
		P.Store:Set({ 'colors', 'npcs', '5925' }, { hint = 'Hint', rename = 'New name' })
		plate:Refresh({ colors = true })
		assert.equal(Shown(Text(plate, 'name')), 'New name')
		local fill = plate:GetWidget('fill').fill
		assert.equal(Shown(fill.bg), 'New name')
		assert.equal(Shown(fill.fg), 'New name')
		P.Store:Set({ 'colors', 'npcs' }, nil)
		plate:Refresh({ colors = true })
		assert.equal(Shown(Text(plate, 'name')), 'Original name')
		assert.equal(Shown(fill.bg), 'Original name')
		Done(plate, token)
	end)

	it('shows the name and keeps names on a font for every alphabet', function()
		local plate, _, token = Live({ name = 'Gnoll Brute', health = 500, healthMax = 1000 })
		local text = Text(plate, 'name')
		assert.equal(Shown(text), 'Gnoll Brute')
		assert.not_nil(text:GetFontObject(), 'names use a font family or the game name font')
		Done(plate, token)
	end)

	it('fills the name with health through bar sinks only', function()
		local plate, unit, token = Live({ name = 'Gnoll Brute', health = 300, healthMax = 1000 })
		local _, widget = Text(plate, 'fill')
		local fill = widget.fill
		assert.not_nil(fill, 'name fill frames')
		assert.equal(Shown(fill.bg), 'Gnoll Brute')
		assert.equal(Shown(fill.fg), 'Gnoll Brute')
		assert.equal(S.Reveal(M.Get(fill.bar, 'max')), 1000)
		assert.equal(S.Reveal(M.Get(fill.bar, 'value')), 300)
		assert.is_false(M.Get(widget.text, 'shown'), 'the plain copy is hidden')
		local bg = M.Get(fill.bg, 'textColor')
		assert.near(bg[1], 0.2, 0.001)
		M.UpdateUnit(unit, { health = 800 }, { 'UNIT_HEALTH' })
		assert.equal(S.Reveal(M.Get(fill.bar, 'value')), 800)
		Done(plate, token)
	end)
end)

describe('text parts: level', function()
	it('shows the level, a plus for elites and the skull for bosses', function()
		local plate, unit, token = Live({ level = 62, classification = 'elite' })
		local text = Text(plate, 'level')
		assert.equal(Shown(text), '62+')
		M.UpdateUnit(unit, { classification = 'normal' }, { 'UNIT_CLASSIFICATION_CHANGED' })
		assert.equal(Shown(text), '62')
		M.UpdateUnit(unit, { level = -1 }, { 'UNIT_LEVEL' })
		assert.matches(Shown(text), 'UI%-TargetingFrame%-Skull')
		Done(plate, token)
		local boss, _, bossToken = Live({ level = 63, classification = 'elite', isBoss = true })
		if UnitIsBossMob then
			assert.matches(Shown(Text(boss, 'level')), 'Skull')
		end
		Done(boss, bossToken)
	end)
end)

describe('text parts: health', function()
	it('shows health percent by plain math where health reads, never 100 while hurt', function()
		local plate, unit, token = Live({ health = 500, healthMax = 1000 })
		local text = Text(plate, 'pct')
		assert.equal(Shown(text), '50%')
		M.UpdateUnit(unit, { health = 999 }, { 'UNIT_HEALTH' })
		assert.equal(Shown(text), '99%')
		M.UpdateUnit(unit, { health = 1 }, { 'UNIT_HEALTH' })
		assert.equal(Shown(text), '1%')
		M.UpdateUnit(unit, { health = 1000 }, { 'UNIT_HEALTH' })
		assert.equal(Shown(text), '100%')
		Done(plate, token)
	end)

	it('abbreviates health values, or writes them out', function()
		local plate, _, token = Live({ health = 1500, healthMax = 3000 })
		assert.equal(Shown(Text(plate, 'value')), '1.5K')
		if BreakUpLargeNumbers then
			assert.equal(Shown(Text(plate, 'valueLong')), '1,500')
		end
		Done(plate, token)
	end)

	it('hides health text at full health by plain math where health reads', function()
		local plate, unit, token = Live({ health = 1000, healthMax = 1000 })
		local text = Text(plate, 'pctHide')
		assert.equal(M.Get(text, 'alpha'), 0)
		M.UpdateUnit(unit, { health = 400 }, { 'UNIT_HEALTH' })
		assert.equal(M.Get(text, 'alpha'), 1)
		local color = M.Get(text, 'textColor')
		assert.equal(color[1], 1)
		assert.equal(color[3], 0, 'its own color stays')
		Done(plate, token)
	end)

	it('hides health text at full health from hidden health through the text color only', function()
		if not (C_CurveUtil and C_CurveUtil.CreateCurve) then
			skip('no curves on this client')
		end
		local plate, unit, token = Live({ health = 1000, healthMax = 1000 })
		-- Classic clients never hide health; force it there so the same path runs everywhere
		M.SetRestricted(true, nil, true)
		M.UpdateUnit(unit, { health = 1000 }, { 'UNIT_HEALTH' })
		local text = Text(plate, 'pctHide')
		local color = M.Get(text, 'textColor')
		assert.is_true(color.secret, 'alpha came from the engine')
		assert.equal(color[4], 0, 'clear at full health')
		assert.equal(M.Get(text, 'alpha'), 1, 'SetAlpha never takes the hidden answer')
		assert.equal(color[1], 1)
		M.UpdateUnit(unit, { health = 400 }, { 'UNIT_HEALTH' })
		color = M.Get(text, 'textColor')
		assert.equal(color[4], 1, 'shown below full health')
		assert.is_true(S.IsSecret(M.Get(Text(plate, 'pct'), 'text')), 'percent text came from a hidden value')
		assert.is_true(S.IsSecret(M.Get(Text(plate, 'value'), 'text')), 'value text came from a hidden value')
		M.SetRestricted(false)
		Done(plate, token)
	end)
end)

describe('text parts: forces, title and threat', function()
	it('shows Mythic+ forces only during a run', function()
		local plate, _, token = Live({ canAttack = true })
		local text = Text(plate, 'forces')
		assert.equal(Shown(text), '')
		local real = C_ScenarioInfo and C_ScenarioInfo.GetUnitCriteriaProgressValues
		if not real then
			Done(plate, token)
			skip('no forces function on this client')
		end
		C_ScenarioInfo.GetUnitCriteriaProgressValues = function()
			return 4, 1.25, '1.25'
		end
		P.Context.challengeActive = true
		plate:OnMessage('CONTEXT_CHANGED')
		assert.equal(Shown(text), '1.25%')
		P.Context.challengeActive = false
		plate:OnMessage('CONTEXT_CHANGED')
		assert.equal(Shown(text), '')
		C_ScenarioInfo.GetUnitCriteriaProgressValues = real
		Done(plate, token)
	end)

	it('reads an NPC title from tooltip data and skips the level line', function()
		if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then
			skip('no tooltip data on this client')
		end
		local real = C_TooltipInfo.GetUnit
		local second = { type = 0, leftText = 'Innkeeper' }
		C_TooltipInfo.GetUnit = function()
			return { lines = { { type = 2, leftText = 'Bob' }, second } }
		end
		P.Context.place = 'world'
		local plate, _, token = Live({ name = 'Bob', canAttack = false, reaction = 5 })
		assert.equal(Shown(Text(plate, 'title')), '<Innkeeper>')
		second.type, second.leftText = 47, 'Level 30'
		plate:UpdateAll('FULL')
		assert.equal(Shown(Text(plate, 'title')), '')
		P.Context.place = 'dungeon'
		second.type, second.leftText = 0, 'Innkeeper'
		plate:UpdateAll('FULL')
		assert.equal(Shown(Text(plate, 'title')), '', 'no tooltip reads inside instances')
		P.Context.place = 'world'
		C_TooltipInfo.GetUnit = real
		Done(plate, token)
	end)

	it('scans a hidden tooltip for titles and quest goals on clients without tooltip data', function()
		if C_TooltipInfo and C_TooltipInfo.GetUnit then
			skip('this client has tooltip data')
		end
		P.Context.place = 'world'
		local tip = P.Source.ScanTooltip()
		assert.not_nil(tip, 'the scan tooltip exists')
		assert.is_nil(tip:GetName(), 'the scanner has no global frame name')
		local lines = {}
		local function Line(text)
			return {
				GetText = function()
					return text
				end,
			}
		end
		rawset(tip, 'SetOwner', function() end)
		rawset(tip, 'ClearLines', function() end)
		rawset(tip, 'SetUnit', function() end)
		rawset(tip, 'NumLines', function()
			return #lines
		end)
		rawset(tip, 'GetLeftLine', function(_, i)
			return lines[i]
		end)
		lines = { Line('Cave Lurker'), Line('Lurker Tamer'), Line('Level 12 Beast'), Line('Clear the Cave'), Line(' - Cave Lurker slain: 3/8') }
		local plate, _, token = Live({ name = 'Cave Lurker' })
		assert.equal(Shown(Text(plate, 'title')), '<Lurker Tamer>')
		assert.is_true(plate.facts.isQuest == true, 'an unfinished goal makes it a quest mob')
		lines[5] = Line(' - Cave Lurker slain: 8/8')
		local src = P.Source.NewLive(token)
		assert.is_false(src:QuestPlain())
		P.Caps:SetOverride('quirk:noTooltipScan', true)
		assert.is_nil(src:QuestPlain(), 'the quirk turns scans off')
		P.Caps:SetOverride('quirk:noTooltipScan', nil)
		Done(plate, token)
	end)

	it('shows threat percent where it reads, and from the hidden value where it does not', function()
		local plate, unit, token = Live({ canAttack = true })
		local text = Text(plate, 'threat')
		assert.equal(Shown(text), '')
		M.SetThreat(unit, M.player, { status = 3, scaledPercent = 100 })
		assert.equal(Shown(text), '100%')
		if M.secrets then
			-- The mock never hides threat read against the player, so hide it here the way the game can
			local realAsk, realThreat = P.Secret.ShouldUnitThreatValuesBeSecret, rawget(_G, 'UnitDetailedThreatSituation')
			P.Secret.ShouldUnitThreatValuesBeSecret = function()
				return true
			end
			rawset(_G, 'UnitDetailedThreatSituation', function(...)
				local a, b, c, d, e = realThreat(...)
				return S.Wrap(a), S.Wrap(b), S.Wrap(c), S.Wrap(d), S.Wrap(e)
			end)
			M.SetThreat(unit, M.player, { status = 1, scaledPercent = 62.4 })
			assert.is_true(S.IsSecret(M.Get(text, 'text')), 'shown from the hidden value')
			assert.equal(S.Reveal(M.Get(text, 'text')), '62%')
			P.Secret.ShouldUnitThreatValuesBeSecret = realAsk
			rawset(_G, 'UnitDetailedThreatSituation', realThreat)
		end
		Done(plate, token)
	end)
end)

describe('text parts: casts', function()
	it('shows the spell name and the target in class color', function()
		local plate, unit, token = Live({ canAttack = true })
		local realName, realClass = rawget(_G, 'UnitSpellTargetName'), rawget(_G, 'UnitSpellTargetClass')
		rawset(_G, 'UnitSpellTargetName', function()
			return 'Tester'
		end)
		rawset(_G, 'UnitSpellTargetClass', function()
			return 'MAGE'
		end)
		-- The mock's CreateColor is a stub on some flavors, so its class colors come back empty
		local realClassColor = C_ClassColor.GetClassColor
		local asked
		C_ClassColor.GetClassColor = function(token)
			asked = token
			return { r = 0.25, g = 0.78, b = 0.92, a = 1 }
		end
		M.StartCast(unit, { name = 'Fireball', duration = 2 })
		assert.equal(Shown(Text(plate, 'castName')), 'Fireball')
		local target = Text(plate, 'castTarget')
		assert.equal(Shown(target), 'Tester')
		local color = M.Get(target, 'textColor')
		assert.near(color[3], 0.92, 0.001)
		M.StopCast(unit, 'stop')
		assert.equal(Shown(Text(plate, 'castName')), '')
		assert.equal(Shown(target), '')
		assert.equal(S.Reveal(asked), 'MAGE')
		-- A color table the game forbids to index: the plain color, and no error
		C_ClassColor.GetClassColor = function()
			return S.Wrap({ r = 0.25, g = 0.78, b = 0.92, a = 1 })
		end
		M.StartCast(unit, { name = 'Fireball', duration = 2 })
		assert.equal(Shown(target), 'Tester')
		color = M.Get(target, 'textColor')
		assert.near(color[1], 1, 0.001, 'white when the class color cannot be read')
		M.StopCast(unit, 'stop')
		C_ClassColor.GetClassColor = realClassColor
		rawset(_G, 'UnitSpellTargetName', realName)
		rawset(_G, 'UnitSpellTargetClass', realClass)
		Done(plate, token)
	end)

	it('counts cast time down on the shared scheduler where no binding exists', function()
		P.Caps:SetOverride('durationText', false)
		local plate, unit, token = Live({ canAttack = true })
		local text = Text(plate, 'castTime')
		M.StartCast(unit, { name = 'Fireball', duration = 2 })
		assert.equal(Shown(text), '2.0')
		M.Advance(1)
		local left = tonumber(Shown(text))
		assert.truthy(left and left <= 1.05 and left >= 0.85, 'counted down: ' .. tostring(Shown(text)))
		assert.equal(#M.ActiveOnUpdates() <= 1, true, 'one shared driver frame, no per-plate OnUpdate')
		M.Advance(1.5)
		assert.equal(Shown(text), '')
		assert.is_false(P.Scheduler:IsRunning('Text.castTime'), 'the task stops when no cast runs')
		P.Caps:SetOverride('durationText', nil)
		Done(plate, token)
	end)

	it('hands the cast duration to a text binding where the client has one', function()
		if not P.Caps:Get('durationText') then
			skip('no duration text binding here')
		end
		local plate, unit, token = Live({ canAttack = true })
		local _, widget = Text(plate, 'castTime')
		M.StartCast(unit, { name = 'Fireball', duration = 2 })
		assert.truthy(widget.binding, 'a binding was made')
		assert.is_false(P.Scheduler:IsRunning('Text.castTime'), 'no Lua ticking with a binding')
		M.StopCast(unit, 'stop')
		Done(plate, token)
	end)

	it('takes the seconds formatter when a binding refuses the cast formatter', function()
		if not (P.Caps:Get('durationText') and C_StringUtil) then
			skip('no duration text binding here')
		end
		local rule, seconds = { kind = 'rule' }, { kind = 'seconds' }
		local realFormatter, realSeconds = P.CastBar.Formatter, C_StringUtil.CreateSecondsFormatter
		local realCreate = C_DurationUtil.CreateDurationTextBinding
		local given
		P.CastBar.Formatter = function()
			return rule
		end
		C_StringUtil.CreateSecondsFormatter = function()
			return seconds
		end
		C_DurationUtil.CreateDurationTextBinding = function()
			local binding = {}
			local function Noop() end
			binding.SetFontString, binding.SetZeroDurationText, binding.SetExpiredText = Noop, Noop, Noop
			binding.SetDuration, binding.SetEnabled = Noop, Noop
			binding.SetFormatter = function(_, formatter)
				if formatter == rule then
					error('not a numeric formatter')
				end
				given = formatter
			end
			return binding
		end
		P.TextParts.ForgetFormatter()
		local plate, unit, token = Live({ canAttack = true })
		M.StartCast(unit, { name = 'Fireball', duration = 2 })
		assert.equal(given, seconds, 'the seconds formatter was handed over')
		M.StopCast(unit, 'stop')
		P.CastBar.Formatter, C_StringUtil.CreateSecondsFormatter = realFormatter, realSeconds
		C_DurationUtil.CreateDurationTextBinding = realCreate
		P.TextParts.ForgetFormatter()
		Done(plate, token)
	end)
end)

describe('text parts: arena labels', function()
	it('numbers arena opponents by comparing plates, only in arenas', function()
		local plate, unit, token = Live({ isPlayer = true, canAttack = true })
		local text = Text(plate, 'arena')
		M.SetToken('arena2', unit)
		assert.equal(Shown(text), '')
		P.Context.place = 'arena'
		plate:OnMessage('CONTEXT_CHANGED')
		assert.equal(Shown(text), '2')
		-- The Driver moved the numbers: the label follows at once, not on the next poll
		M.SetToken('arena2', nil)
		M.SetToken('arena4', unit)
		plate:OnMessage('ARENA_CHANGED')
		assert.equal(Shown(text), '4')
		M.SetToken('arena4', nil)
		M.SetToken('arena2', unit)
		plate:OnMessage('ARENA_CHANGED')
		if M.secrets then
			M.SetRestricted(true, { 'identity' })
			plate:UpdateAll('FULL')
			assert.equal(Shown(text), '', 'no label when the game will not hand out arena plates')
			M.SetRestricted(false)
		end
		P.Context.place = 'world'
		M.SetToken('arena2', nil)
		Done(plate, token)
	end)
end)

describe('text parts: restricted plates', function()
	it('fills every source from hidden values without errors', function()
		local plate, unit, token = Live({ name = 'Hidden', health = 700, healthMax = 1000, canAttack = true })
		M.SetRestricted(true, nil, true)
		M.StartCast(unit, { name = 'Shadow Bolt', duration = 2 })
		plate:UpdateAll('FULL')
		M.SetThreat(unit, M.player, { status = 2, scaledPercent = 90 })
		M.UpdateUnit(unit, { health = 650 }, { 'UNIT_HEALTH', 'UNIT_NAME_UPDATE' })
		assert.is_true(S.IsSecret(M.Get(Text(plate, 'name'), 'text')))
		M.StopCast(unit, 'stop')
		M.SetRestricted(false)
		Done(plate, token)
	end)

	it('clears every text on unbind', function()
		local plate, _, token = Live({ name = 'Gone', health = 10, healthMax = 100 })
		plate:Unbind()
		for _, id in ipairs({ 'name', 'pct', 'value', 'level' }) do
			assert.equal(Shown(Text(plate, id)), '')
		end
		M.HidePlate(token)
	end)
end)

describe('text parts: previews', function()
	it('fills every source from every sample', function()
		for id in pairs(P.Data.Samples) do
			local plate = P.Plate.New(UIParent, true)
			plate:ApplyStyle(Merge:Resolve('textTest', 'enemyNPC', 'medium'))
			plate:BindSample(P.Source.NewSample(id))
			if id == 'casterTarget' then
				assert.equal(Shown(Text(plate, 'pct')), '72%')
				assert.equal(Shown(Text(plate, 'name')), P.Data.Samples.casterTarget.name)
				assert.equal(Shown(Text(plate, 'level')), '62+')
			elseif id == 'boss' then
				assert.matches(Shown(Text(plate, 'level')), 'Skull')
			end
			plate:Unbind()
		end
		M.Advance(4)
	end)
end)
