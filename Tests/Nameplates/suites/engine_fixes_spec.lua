-- @runtime lua51
-- Engine fixes from the stage B review (2026-10-12): the shared scheduler when callbacks add work,
-- parts a style drops mid-cast, state-tied part alpha, region boxes above every part, a hidden plate
-- scale, class colors the game hands back as tables addon code may not index, game objects and
-- click areas left to or taken back from Blizzard, the enemy show setting with minor enemies, quest
-- goals in grouped tooltips, the class color for players whose class is hidden, the threat lead
-- text, the S11 important-cast badge and the spell data added for Mists, TBC and Wrath.
local M, H = ...
local S = M.S

if not H.ModuleExists() then
	describe('engine fixes', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

M.Login('NameplatesTestHost')
local P = H.FreshCore()
local Driver, Store, Scheduler = P.Driver, P.Store, P.Scheduler
P:Enable()
local SECRETS = P.Caps:Get('secrets')

local STYLE = {
	id = 'fixTest',
	name = 'Fix test',
	version = 1,
	schema = 1,
	order = 993,
	internal = true,
	plate = { sizes = { small = { 100, 8 }, medium = { 120, 10 }, large = { 140, 12 } } },
	parts = {
		health = { order = 1, kind = 'bar', source = 'health', fill = 'plate' },
		mark = { order = 2, kind = 'text', source = 'name', state = 'target', alpha = 0.5, anchor = { 'BOTTOM', 'health', 'TOP', 0, 2 } },
		top = { order = 3, kind = 'text', source = 'level', layer = 8, anchor = { 'LEFT', 'health', 'RIGHT', 2, 0 } },
		lead = { order = 4, kind = 'text', source = 'threatLead', anchor = { 'RIGHT', 'health', 'LEFT', -2, 0 } },
	},
}
P.Styles.Registry:RegisterBuiltin(STYLE)

local function Enemy(spec)
	spec = spec or {}
	if spec.canAttack == nil then
		spec.canAttack = true
	end
	spec.reaction = spec.reaction or 2
	spec.name = spec.name or 'Gnoll'
	return M.ShowPlate(spec)
end

local function HideAll()
	local tokens = {}
	for token in pairs(M.plates) do
		tokens[#tokens + 1] = token
	end
	for _, token in ipairs(tokens) do
		M.HidePlate(token)
	end
end

local function Reset()
	M.SetTarget(nil)
	HideAll()
	if M.lockdown then
		M.LeaveCombat()
	end
	M.SetRestricted(false)
	Store:Batch(function()
		Store:Set('modes', nil)
		Store:Set('scheme', nil)
		Store:Set('when', nil)
	end)
	M.Advance(0.5)
end

local function TestPlate(isPreview)
	local plate = P.Plate.New(UIParent, isPreview)
	plate:ApplyStyle(P.Styles.Merge:Resolve('fixTest', 'enemyNPC', 'medium'))
	return plate
end

describe('engine fixes: shared scheduler', function()
	it('runs tasks added by a task on a later tick, and cancelling the current task is safe', function()
		local started, ranAt, count = nil, {}, 0
		local fns = {}
		for i = 1, 60 do
			fns[i] = function(now)
				count = count + 1
				ranAt[#ranAt + 1] = now
				Scheduler:Cancel('fix.child' .. i)
			end
		end
		Scheduler:Every('fix.parent', 0.1, function(now)
			started = now
			Scheduler:Cancel('fix.parent')
			for i = 1, 60 do
				Scheduler:Every('fix.child' .. i, 0.1, fns[i])
			end
		end)
		M.Advance(1)
		assert.not_nil(started, 'the first task ran')
		assert.equal(count, 60, 'every task it added ran once')
		for _, at in ipairs(ranAt) do
			assert.is_true(at > started, 'a task added in a tick waits for a later one')
		end
		assert.equal(#M.errors, 0)
	end)

	it('runs eases started from another ease callback', function()
		local done = 0
		local function Noop() end
		local function Done()
			done = done + 1
		end
		Scheduler:Ease('fix.first', 0, 1, 0.1, Noop, function()
			for i = 1, 40 do
				Scheduler:Ease('fix.next' .. i, 0, 1, 0.1, Noop, Done)
			end
		end)
		M.Advance(1)
		assert.equal(done, 40)
		assert.is_nil(next(Scheduler.eases), 'nothing left running')
		assert.equal(#M.errors, 0)
	end)
end)

describe('engine fixes: plates', function()
	after_each(Reset)

	it('resets a cast part the new style drops in the middle of a cast', function()
		local token, base, unit = Enemy()
		local plate = P.API:GetPlate(base)
		assert.not_nil(plate:GetWidget('cast'), 'the clean style has a cast bar')
		local cast = plate:GetWidget('cast')
		M.StartCast(unit, { name = 'Bolt', spellID = 686, duration = 5 })
		assert.is_true(plate.states.casting == true, 'casting')
		Store:Set('modes', { enemyNPC = 'name' })
		assert.is_nil(plate:GetWidget('cast'), 'the names-only style has no cast bar')
		assert.is_nil(plate.states.casting, 'the casting state ended with the part')
		assert.is_nil(cast.state, 'the dropped cast part was reset')
		assert.is_nil(P.CastBar.textActive[cast], 'no shared text task for it')
		M.StopCast(unit, 'stop')
		M.HidePlate(token)
	end)

	it('keeps a state-tied part at its own alpha after a hidden answer', function()
		local plate = TestPlate(true)
		local mark = plate:GetWidget('mark')
		assert.near(M.Get(mark.frame, 'alpha'), 0.5, 1e-6)
		plate:SetStateSecret('target', SECRETS and S.Wrap(true) or true)
		assert.near(S.Reveal(M.Get(mark.frame, 'alpha')), 0.5, 1e-6, 'shown at the part alpha, not 1')
		plate:SetStateSecret('target', SECRETS and S.Wrap(false) or false)
		assert.near(S.Reveal(M.Get(mark.frame, 'alpha')), 0, 1e-6)
	end)

	it('draws region boxes above parts on the top layer', function()
		local plate = TestPlate(true)
		local top = plate:GetWidget('top')
		P.Regions:ShowBoxes(plate, true)
		local boxes = P.Regions.boxes[plate]
		assert.not_nil(boxes)
		assert.is_true(M.Get(boxes.click, 'level') > M.Get(top.frame, 'level'), 'the click box draws over a layer 8 part')
		P.Regions:ShowBoxes(plate, nil)
	end)

	it('measures a pixel when the plate scale is hidden', function()
		if not SECRETS then
			skip('only clients with secrets can hide a scale')
		end
		local plate = TestPlate(true)
		M.Override(plate.art, 'GetEffectiveScale', function()
			return S.Wrap(0.8)
		end)
		local ctx = setmetatable({ plate = plate }, { __index = P.LayoutContext })
		local pixel = ctx:Pixel()
		assert.is_true(type(pixel) == 'number' and not S.IsSecret(pixel) and pixel > 0, 'a plain pixel from the UI parent')
		M.Override(plate.art, 'GetEffectiveScale', nil)
	end)

	it('colors a cast target white when the game hands back a color table it forbids', function()
		if not SECRETS then
			skip('only clients with secrets hand back forbidden tables')
		end
		local realName, realClass = rawget(_G, 'UnitSpellTargetName'), rawget(_G, 'UnitSpellTargetClass')
		local realColor = C_ClassColor.GetClassColor
		rawset(_G, 'UnitSpellTargetName', function()
			return S.Wrap('Bob')
		end)
		rawset(_G, 'UnitSpellTargetClass', function()
			return S.Wrap('WARRIOR')
		end)
		C_ClassColor.GetClassColor = function()
			return S.Wrap({ r = 1, g = 0, b = 0 })
		end
		local ok, err = pcall(function()
			local token, base, unit = Enemy()
			local plate = P.API:GetPlate(base)
			M.StartCast(unit, { name = 'Bolt', spellID = 686, duration = 5 })
			local cast = plate:GetWidget('cast')
			assert.equal(cast.state, 'casting', 'the cast started in spite of the color table')
			local color = M.Get(cast.target, 'textColor')
			for i = 1, 4 do
				assert.equal(S.Reveal(color[i]), 1, 'plain white')
			end
			M.StopCast(unit, 'stop')
			M.HidePlate(token)
		end)
		rawset(_G, 'UnitSpellTargetName', realName)
		rawset(_G, 'UnitSpellTargetClass', realClass)
		C_ClassColor.GetClassColor = realColor
		assert.is_true(ok, tostring(err))
		assert.equal(#M.errors, 0)
	end)
end)

describe('engine fixes: driver', function()
	after_each(function()
		P.Caps:SetOverride('hitTest', nil)
		Reset()
	end)

	it('takes the click area back after Blizzard sets its own, in combat once combat ends', function()
		local _, base = Enemy()
		local plate = P.API:GetPlate(base)
		local function Blizzard()
			M.Set(base, 'canHitTest', true)
			base:SetHitTestPoints({ { point = 'TOPLEFT', relativeTo = base, relativePoint = 'TOPLEFT' } })
			M.Set(base, 'canHitTest', false)
		end
		local function Ours()
			local points = M.Get(base, 'hitTest')
			return points and points[1] and points[1][2] == plate.click
		end
		assert.is_true(Ours())
		-- Out of combat the game lets a plate change its click points
		M.Set(base, 'canHitTest', true)
		Blizzard()
		M.Set(base, 'canHitTest', true)
		NamePlateDriverFrame:UpdateNamePlateOptions()
		assert.is_true(Ours(), 'taken back at once')
		M.EnterCombat()
		Blizzard()
		NamePlateDriverFrame:UpdateNamePlateOptions()
		assert.is_false(Ours(), 'left alone in combat')
		M.Set(base, 'canHitTest', true)
		M.LeaveCombat()
		assert.is_true(Ours(), 'taken back when combat ends')
		M.Set(base, 'canHitTest', false)
	end)

	it('leaves game objects to Blizzard, which draws their name', function()
		if not UnitIsGameObject then
			skip('this client cannot tell game objects apart')
		end
		local _, base = M.ShowPlate({ name = 'Mailbox', isGameObject = true, canAttack = false, reaction = 4 })
		local plate = Driver.byBase[base]
		assert.equal(Driver:ModeOf(plate), 'blizzard')
		assert.is_nil(P.API:GetPlate(base))
		assert.is_false(M.Get(plate.root, 'shown') == true)
		assert.is_false(P.Suppress:WasTouched(base.UnitFrame), 'Blizzard plate untouched')
		assert.not_equal(M.Get(base.UnitFrame, 'alpha'), 0)
	end)

	it('keeps enemy plates on while minor enemies are shown', function()
		if not P.CVars:Exists('nameplateShowEnemies') then
			skip('no enemy show setting')
		end
		M.SetCVarState('nameplateShowEnemies', { value = '1' })
		Store:Set('modes', { enemyNPC = 'hidden', enemyPlayer = 'hidden' })
		assert.equal(C_CVar.GetCVar('nameplateShowEnemies'), '1', 'totems and minor mobs still need enemy plates')
		Store:Set('modes', { enemyNPC = 'hidden', enemyPlayer = 'hidden', minor = 'hidden' })
		assert.equal(C_CVar.GetCVar('nameplateShowEnemies'), '0', 'every enemy kind hidden everywhere')
		Store:Set('modes', nil)
		assert.equal(C_CVar.GetCVar('nameplateShowEnemies'), '1', 'given back')
	end)

	it("re-reads the context only for the player's own pet", function()
		Scheduler.nextFrame['Driver.context'] = nil
		M.Fire('UNIT_PET', 'party1')
		assert.is_nil(Scheduler.nextFrame['Driver.context'], "another member's pet changes nothing")
		M.Fire('UNIT_PET', 'player')
		assert.not_nil(Scheduler.nextFrame['Driver.context'])
		M.Advance(0.1)
	end)

	it('leaves range fade unavailable without a range library', function()
		if LibStub and LibStub('LibRangeCheck-3.0', true) then
			skip('range library is loaded')
		end
		local available, reason = Driver:FeatureState('rangeFade')
		assert.is_false(available)
		assert.not_nil(reason)
	end)
end)

describe('engine fixes: quest goals in tooltips', function()
	local function Line(kind, text, extra)
		local line = { type = kind, leftText = text }
		for k, v in pairs(extra or {}) do
			line[k] = v
		end
		return line
	end

	it("reads only the player's own goals, with or without the completed flag", function()
		if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then
			skip('this client has no tooltip data')
		end
		local real = C_TooltipInfo.GetUnit
		local related = C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest
		local reads = 0
		local lines
		C_TooltipInfo.GetUnit = function()
			reads = reads + 1
			return { lines = lines }
		end
		local unit = M.AddUnit({ canAttack = true, reaction = 2 })
		M.SetToken('nameplate9', unit)
		local src = P.Source.NewLive('nameplate9')
		local placeBefore = P.Context.place
		P.Context.place = 'world'
		local me = UnitGUID('player')
		local ok, err = pcall(function()
			lines = {
				Line(17, 'Wolf Trouble'),
				Line(18, 'Buddy', { guid = 'Player-1-0BADF00D' }),
				Line(8, 'Wolves slain: 3/8'),
				Line(18, 'Tester', { guid = me }),
				Line(8, 'Wolves slain: 8/8'),
			}
			assert.is_false(src:QuestPlain(), "a group member's open goal is not the player's")
			lines[5] = Line(8, 'Wolves slain: 5/8')
			assert.is_true(src:QuestPlain(), "the player's own open goal")
			lines = { Line(17, 'Explore'), Line(8, 'Area explored: 45%') }
			assert.is_true(src:QuestPlain(), 'a percent goal with no completed flag')
			lines = { Line(17, 'Explore'), Line(8, 'Area explored: 100%') }
			assert.is_false(src:QuestPlain())
			lines = { Line(17, 'Wolf Trouble'), Line(8, 'Wolves slain: 8/8', { completed = false }) }
			assert.is_true(src:QuestPlain(), 'the completed flag decides when present')
			if C_QuestLog then
				C_QuestLog.UnitIsRelatedToActiveQuest = function()
					return false
				end
				local before = reads
				assert.is_false(src:QuestPlain())
				assert.equal(reads, before, 'no tooltip read for a unit no quest cares about')
				P.Caps:SetOverride('quirk:noQuestGate', true)
				assert.is_true(src:QuestPlain(), 'the escape hatch reads the tooltip anyway')
				P.Caps:SetOverride('quirk:noQuestGate', nil)
			end
		end)
		C_TooltipInfo.GetUnit = real
		if C_QuestLog then
			C_QuestLog.UnitIsRelatedToActiveQuest = related
		end
		P.Context.place = placeBefore
		M.SetToken('nameplate9', nil)
		assert.is_true(ok, tostring(err))
	end)
end)

describe('engine fixes: colors and text', function()
	after_each(Reset)

	it('colors an enemy player by class when the game hides the class', function()
		if not SECRETS then
			skip('only clients with secrets hide a class')
		end
		Store:Set('scheme', 'class')
		M.SetRestricted(true)
		local _, base = Enemy({ name = 'Duelist', isPlayer = true, class = 'WARRIOR', className = 'Warrior' })
		local plate = P.API:GetPlate(base)
		assert.is_nil(plate.facts.classToken, 'the class is hidden')
		local color = M.Get(plate:GetHealthBar(), 'barColor')
		local want = RAID_CLASS_COLORS.WARRIOR
		assert.near(S.Reveal(color[1]), want.r, 1e-6)
		assert.near(S.Reveal(color[2]), want.g, 1e-6)
		assert.near(S.Reveal(color[3]), want.b, 1e-6)
		assert.equal(#M.errors, 0)
	end)

	it('shows the threat lead on previews and real plates', function()
		local preview = TestPlate(true)
		preview:BindSample(P.Source.NewSample({ id = 'leadTest', facts = { canAttack = true, reaction = 2 }, threat = 3 }))
		assert.equal(M.Get(preview:GetWidget('lead').text, 'text'), '130%')
		local real = rawget(_G, 'UnitThreatPercentageOfLead')
		rawset(_G, 'UnitThreatPercentageOfLead', function()
			return 87.4
		end)
		local ok, err = pcall(function()
			local token, _, unit = Enemy()
			local plate = TestPlate(false)
			local src = P.Source.NewLive(token)
			src:ReadFacts(plate.facts)
			plate:Bind(token, src)
			local text = M.Get(plate:GetWidget('lead').text, 'text')
			assert.equal(S.Reveal(text), '87%')
			plate:Unbind()
			M.HidePlate(token)
		end)
		rawset(_G, 'UnitThreatPercentageOfLead', real)
		assert.is_true(ok, tostring(err))
		assert.contains(P.Styles.Schema.TEXT_SOURCES, 'threatLead')
		assert.not_nil(P.TextParts.Limit('threatLead'))
	end)

	it('warns that important casts may never show until the game marks one (S11)', function()
		if SECRETS then
			assert.is_nil(P.GlowLib.Limit('importantCast'), 'the engine answers per cast here')
			return
		end
		if not P.Caps:Get('important') then
			skip('no important-cast flag on this client')
		end
		assert.not_nil(P.GlowLib.Limit('importantCast'), 'nothing marked important yet')
		M.importantSpells = { [686] = true }
		local token, base, unit = Enemy()
		M.StartCast(unit, { name = 'Bolt', spellID = 686, duration = 2 })
		local _ = P.API:GetPlate(base)
		assert.is_nil(P.GlowLib.Limit('importantCast'), 'a real cast was marked important')
		M.StopCast(unit, 'stop')
		M.HidePlate(token)
		M.importantSpells = nil
	end)
end)

describe('engine fixes: spell data', function()
	it('has the Mists, TBC and Wrath ids the review found missing', function()
		local mists = P.Data.CrowdControlFor('mists')
		for _, id in ipairs({ 120086, 122242, 123407, 76780, 136634, 54786, 119072, 115268, 118345, 137460, 31117, 64058 }) do
			assert.not_nil(mists[id], 'mists crowd control ' .. id)
		end
		assert.is_nil(P.Data.CrowdControlFor('titan')[14251], 'Wrath Riposte is an attack-speed slow')
		assert.is_nil(P.Data.CrowdControlFor('titan')[18093], 'Wrath Pyroclasm is a self buff')
		assert.not_nil(P.Data.CrowdControlFor('tbc')[44041], 'TBC Chastise')
		assert.not_nil(P.Data.CrowdControlFor('titan')[60995], 'Demon Charge on Wrath content')
		assert.is_nil(P.Data.CrowdControlFor('era')[60995])
		assert.equal(P.Data.TankDebuffsFor('tbc')[26018], 'vindication')
		assert.is_nil(P.Data.TankDebuffsFor('titan')[26018], 'Wrath has two ranks')
		assert.contains(P.Data.Kicks.CLIENTS.mists.pet, 89766)
		assert.not_nil(P.Data.Kicks.CLIENTS.mists.unverified[89766])
	end)
end)

describe('engine fixes: update budgets', function()
	after_each(Reset)
	it('puts each widget in an event or message list once, for every built-in style', function()
		for _, entry in ipairs(P.Styles.Registry:List(true)) do
			local plate = P.Plate.New(UIParent, true)
			plate:ApplyStyle(P.Styles.Merge:Resolve(entry.id, 'enemyNPC', 'medium'))
			for _, map in ipairs({ plate.eventWidgets, plate.messageWidgets }) do
				for _, list in pairs(map) do
					local seen = {}
					for _, widget in ipairs(list) do
						assert.is_nil(seen[widget], entry.id .. ': duplicate widget')
						seen[widget] = true
					end
				end
			end
		end
	end)
	it('keeps event maps and avoids recoloring for combat and resting alone', function()
		local _, base = Enemy()
		local plate = P.API:GetPlate(base)
		local builds = plate.mapBuilds
		local real, calls = P.Colors.Apply, 0
		P.Colors.Apply = function(self, ...)
			calls = calls + 1
			return real(self, ...)
		end
		P:Fire('CONTEXT_CHANGED', { inCombat = true })
		P:Fire('CONTEXT_CHANGED', { resting = true, groupSize = true })
		P.Colors.Apply = real
		assert.equal(calls, 0)
		assert.equal(plate.mapBuilds, builds)
	end)
	it('reuses the maps when a plate switches back to a previous style', function()
		local plate = P.Plate.New(UIParent, true)
		local clean = P.Styles.Merge:Resolve('clean', 'enemyNPC', 'medium')
		local mini = P.Styles.Merge:Resolve('mini', 'minor', 'medium')
		plate:ApplyStyle(clean)
		plate:ApplyStyle(mini)
		local builds = plate.mapBuilds
		plate:ApplyStyle(clean)
		assert.equal(plate.mapBuilds, builds)
	end)
	it('reads a cast once per dispatch', function()
		local _, base, unit = Enemy()
		local real = rawget(_G, 'UnitCastingInfo')
		local calls = 0
		rawset(_G, 'UnitCastingInfo', function(...)
			calls = calls + 1
			return real(...)
		end)
		M.StartCast(unit, { name = 'Bolt', spellID = 686, duration = 5 })
		rawset(_G, 'UnitCastingInfo', real)
		assert.equal(calls, 1)
		M.StopCast(unit, 'stop')
	end)
	it('shares one cooldown duration across the interrupt-ready broadcast', function()
		Enemy()
		local real, before = C_Spell.GetSpellCooldownDuration, P.Context.kickSpell
		local calls = 0
		C_Spell.GetSpellCooldownDuration = function(...)
			calls = calls + 1
			return real(...)
		end
		P.Context.kickSpell = 2139
		Driver:CheckKick(true)
		for i = 1, 20 do
			P.Conditions.KickReadyPlain()
			P.Conditions.KickReadySecret()
		end
		C_Spell.GetSpellCooldownDuration, P.Context.kickSpell = real, before
		assert.equal(calls, 1)
	end)
	it('does not call a unit comparison the game refuses', function()
		if not C_Secrets then
			skip('no comparison gate')
		end
		local realGate, realUnit = C_Secrets.CanCompareUnitTokens, rawget(_G, 'UnitIsUnit')
		local calls = 0
		C_Secrets.CanCompareUnitTokens = function()
			return false
		end
		rawset(_G, 'UnitIsUnit', function()
			calls = calls + 1
			error('refused comparison')
		end)
		local src = P.Source.NewLive('nameplate1')
		assert.is_nil(src:IsUnitSecret('target'))
		C_Secrets.CanCompareUnitTokens = realGate
		rawset(_G, 'UnitIsUnit', realUnit)
		assert.equal(calls, 0)
	end)
	it('shares a harmful aura scan between matching rows and skips unchanged icons', function()
		if SECRETS then
			skip('live aura scans require plain aura data')
		end
		local token, base, unit = Enemy()
		local plate = P.API:GetPlate(base)
		local src = plate.src
		local real, calls = src.AuraInstanceIDsPlain, 0
		src.AuraInstanceIDsPlain = function(self, ...)
			calls = calls + 1
			return real(self, ...)
		end
		M.ApplyAura(unit, { spellId = 118, name = 'Polymorph', icon = 123, isHarmful = true, sourceUnit = 'player', duration = 8 })
		plate:OnEvent('UNIT_AURA', token, { isFullUpdate = true })
		local once = calls
		assert.is_true(once <= 2, 'at most one harmful scan per dispatch')
		local widget = plate:GetWidget('cc') or plate:GetWidget('crowdControl')
		if widget and widget.icons[1] then
			local texture = widget.icons[1].texture
			local before = #M.Calls(texture, 'SetTexture')
			plate:OnEvent('UNIT_AURA', token, { isFullUpdate = true })
			assert.equal(#M.Calls(texture, 'SetTexture'), before)
		end
		src.AuraInstanceIDsPlain = real
	end)
end)

describe('engine fixes: threat event pairs', function()
	after_each(Reset)
	it('renders the list and situation notifications once with one threat read', function()
		M.group, M.groupSize = 'party', 2
		M.SetPlace({ inInstance = true, instanceType = 'party', difficultyID = 1 })
		Store:Set('role', 'healer')
		local _, base, unit = Enemy()
		local real, calls = rawget(_G, 'UnitThreatSituation'), 0
		rawset(_G, 'UnitThreatSituation', function(...)
			calls = calls + 1
			return real(...)
		end)
		M.SetThreat(unit, M.player, { status = 3 })
		rawset(_G, 'UnitThreatSituation', real)
		local plate = P.API:GetPlate(base)
		local shown = P.GlowLib.IsShown(plate:GetWidget('threat').glow)
		M.group, M.groupSize = nil, nil
		assert.is_true(shown)
		assert.equal(calls, 1)
		assert.is_nil(P.Scheduler.nextFrame[plate.threatJobId])
		Store:Set('role', nil)
		M.SetPlace({ inInstance = false, instanceType = 'none', difficultyID = 0 })
	end)
end)
