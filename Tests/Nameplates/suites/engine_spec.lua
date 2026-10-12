-- @runtime lua51
-- Engine pieces that run on live plates: target emphasis never reads plate geometry back, the
-- shared layout context follows the plate it lays out, aura changes wait for a restriction to
-- lift, facts keep a readable false, the group tank list never holds the player, quest reads
-- survive tables the game forbids, the secret helpers treat "no answer" as false, the Lua aura
-- scan stays off live plates where secrets exist, bars use real texture paths, and the setup look
-- step matches LibAT's variant contract.
local M, H = ...
local S = M.S

if not H.ModuleExists() then
	describe('engine', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

M.Login('NameplatesTestHost')
local P = H.FreshCore()
local Merge = P.Styles.Merge

local function NewPlate(styleId, kind, size, testAuras)
	local plate = P.Plate.New(UIParent, false)
	plate.testAuras = testAuras
	plate:ApplyStyle(Merge:Resolve(styleId, kind or 'enemyNPC', size or 'medium'))
	return plate
end

describe('engine: target emphasis', function()
	it('eases size and alpha from the values it applied, never from the frame', function()
		local plate = NewPlate('clean')
		local resolved = plate.style
		plate.art.GetSize = function()
			error('read the plate size back')
		end
		plate.art.GetWidth = plate.art.GetSize
		plate.art.GetHeight = plate.art.GetSize
		plate.art.GetAlpha = function()
			error('read the plate alpha back')
		end
		plate:SetState('target', true)
		M.Advance(0.5)
		assert.equal(M.Get(plate.art, 'w'), resolved.width + resolved.states.target.grow[1])
		assert.equal(M.Get(plate.art, 'h'), resolved.height + resolved.states.target.grow[2])
		plate:SetState('target', false)
		M.Advance(0.5)
		assert.equal(M.Get(plate.art, 'w'), resolved.width)
		assert.equal(plate.emW, resolved.width)
	end)
end)

describe('engine: layout context', function()
	local seen = {}
	P.Parts:Register({
		id = 'testAuras',
		kinds = { 'auras' },
		priority = 100,
		match = function(_, plate)
			return plate.testAuras == true
		end,
		reasons = { auras = true },
		Create = function(plate)
			return { frame = CreateFrame('Frame', nil, plate.art) }
		end,
		Layout = function(widget, _, ctx)
			seen[widget.plate] = { ctx.width, ctx.height }
		end,
		Configure = function(widget)
			widget.configured = (widget.configured or 0) + 1
		end,
		Update = function() end,
		Reset = function() end,
	})
	local clean = NewPlate('clean', 'enemyNPC', 'medium', true)
	local mini = NewPlate('mini', 'minor', 'medium', true)

	it('gives a refreshed plate its own size, not the last plate laid out', function()
		assert.not_equal(clean.style.width, mini.style.width)
		clean:Refresh({ auras = true })
		assert.same(seen[clean], { clean.style.width, clean.style.height })
	end)

	it('holds aura changes made in combat until the restriction lifts', function()
		local widget = clean:GetWidget('mine')
		local before = widget.configured or 0
		M.EnterCombat()
		clean:Refresh({ auras = true })
		assert.is_true(clean.pendingConfigure)
		assert.equal(widget.configured or 0, before)
		M.LeaveCombat()
		P.Driver.bound[clean] = true
		P.Driver:FlushPendingConfigure()
		P.Driver.bound[clean] = nil
		assert.is_nil(clean.pendingConfigure)
		assert.equal(widget.configured, before + 1)
	end)

	it('fades state-tied parts from a secret answer without testing it', function()
		local arrows = clean:GetWidget('arrows')
		assert.not_nil(arrows)
		clean:SetStateSecret('target', S.Wrap(true))
		assert.equal(M.Get(arrows.frame, 'alpha'), 1)
		clean:SetStateSecret('target', S.Wrap(false))
		assert.equal(M.Get(arrows.frame, 'alpha'), 0)
		clean:SetStateSecret('target', nil)
		assert.equal(M.Get(arrows.frame, 'alpha'), 0, 'no answer counts as not the target')
	end)
end)

describe('engine: bars and fonts', function()
	it('draws bar backgrounds with a real file path', function()
		local plate = NewPlate('clean')
		local health = plate:GetWidget('health')
		local path = M.Get(health.frame.bg, 'texture')
		assert.equal(path, 'Interface\\Buttons\\WHITE8X8')
	end)

	it('gives text that shows names a font object and plain text a face', function()
		local plate = NewPlate('clean')
		local name = plate:GetWidget('name')
		local object = name.text:GetFontObject()
		assert.not_nil(object, 'names use a font family or the game name font')
		local members = M.Get(object, 'members')
		if members then
			local own = P.Fonts.OwnAlphabet()
			local alphabets = {}
			for _, member in ipairs(members) do
				alphabets[member.alphabet] = member.file
			end
			assert.not_nil(alphabets.russian, 'Cyrillic names have a face')
			assert.not_nil(alphabets.korean, 'Korean names have a face')
			assert.not_equal(alphabets[own], nil)
		end
		local hp = plate:GetWidget('hp')
		assert.is_nil(hp.text:GetFontObject(), 'numbers use the face directly')
	end)

	it('caches one family per face, size and flags', function()
		local a = P.Fonts:Family('Fonts\\FRIZQT__.TTF', 11, 'OUTLINE')
		local b = P.Fonts:Family('Fonts\\FRIZQT__.TTF', 11, 'OUTLINE')
		assert.is_true(rawequal(a, b))
	end)
end)

describe('engine: facts', function()
	local function Facts(spec)
		local unit = M.AddUnit(spec)
		M.SetToken('nameplate9', unit)
		local facts = P.Source.NewLive('nameplate9'):ReadFacts({})
		M.SetToken('nameplate9', nil)
		return facts
	end

	it('keeps a readable false, so an elite above your level is not a mini-boss where the game can say', function()
		P.Context.playerLevel = 80
		local facts = Facts({ classification = 'elite', level = 81, isLieutenant = false, powerType = 1, canAttack = true })
		if UnitIsLieutenant then
			assert.is_false(facts.isLieutenant)
			assert.equal(facts.mobType, 'elite')
		else
			assert.is_nil(facts.isLieutenant)
			assert.equal(facts.mobType, 'miniboss', 'clients without the answer use the level rule')
		end
		if UnitIsBossMob then
			assert.is_false(facts.isBoss)
		end
		P.Context.playerLevel = 1
	end)
end)

describe('engine: group tanks', function()
	local realUnitIsUnit = rawget(_G, 'UnitIsUnit')

	local function Raid(playerIndex)
		M.group, M.groupSize = 'raid', 4
		for i = 1, 4 do
			if i == 3 then
				M.SetToken('raid3', M.player)
			else
				M.SetToken('raid' .. i, M.AddUnit({ isPlayer = true, canAttack = false, reaction = 5, role = i == 1 and 'TANK' or 'DAMAGER' }))
			end
		end
		M.player.role = 'TANK'
		M.player.raidIndex = playerIndex
	end

	local function Done()
		M.group, M.groupSize = nil, nil
		M.player.role, M.player.raidIndex = nil, nil
		for i = 1, 4 do
			M.SetToken('raid' .. i, nil)
		end
		rawset(_G, 'UnitIsUnit', realUnitIsUnit)
	end

	it('never lists the player as another tank, even when unit comparisons are hidden', function()
		Raid(3)
		if M.secrets then
			rawset(_G, 'UnitIsUnit', function(a, b)
				return S.Wrap(M.FN.UnitIsUnit(a, b))
			end)
		end
		local ctx = P.Source.ReadPlayerContext({}, 'tank')
		Done()
		assert.same(ctx.tanks, { 'raid1' })
	end)

	it('leaves a raid slot out when it cannot tell it apart from the player', function()
		if not M.secrets then
			skip('unit comparisons are never hidden on this client')
		end
		Raid(nil)
		rawset(_G, 'UnitIsUnit', function(a, b)
			return S.Wrap(M.FN.UnitIsUnit(a, b))
		end)
		local ctx = P.Source.ReadPlayerContext({}, 'tank')
		Done()
		for _, unit in ipairs(ctx.tanks) do
			assert.not_equal(unit, 'raid3')
		end
	end)

	it('reads party tanks without comparing tokens', function()
		M.group, M.groupSize = 'party', 3
		M.SetToken('party1', M.AddUnit({ isPlayer = true, reaction = 5, canAttack = false, role = 'TANK' }))
		M.SetToken('party2', M.AddUnit({ isPlayer = true, reaction = 5, canAttack = false, role = 'HEALER' }))
		rawset(_G, 'UnitIsUnit', function()
			error('compared unit tokens')
		end)
		local ctx = P.Source.ReadPlayerContext({}, 'damage')
		rawset(_G, 'UnitIsUnit', realUnitIsUnit)
		M.SetToken('party1', nil)
		M.SetToken('party2', nil)
		M.group, M.groupSize = nil, nil
		assert.same(ctx.tanks, { 'party1' })
	end)
end)

describe('engine: quest tooltips', function()
	it('skips tooltip tables the game will not let it read', function()
		if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then
			skip('this client has no tooltip data')
		end
		local real = C_TooltipInfo.GetUnit
		local answers = {
			{ lines = S.Wrap({ { type = 8, completed = false } }) },
			{ lines = { S.Wrap({ type = 8, completed = false }) } },
			S.Wrap({ lines = {} }),
		}
		local unit = M.AddUnit({ canAttack = true })
		M.SetToken('nameplate8', unit)
		local src = P.Source.NewLive('nameplate8')
		P.Context.place = 'world'
		for i, answer in ipairs(answers) do
			C_TooltipInfo.GetUnit = function()
				return answer
			end
			assert.not_equal(src:QuestPlain(), true, 'case ' .. i)
		end
		C_TooltipInfo.GetUnit = real
		M.SetToken('nameplate8', nil)
	end)
end)

describe('engine: secret helpers', function()
	it('treats no answer as false', function()
		local Secret = P.Secret
		assert.equal(S.Reveal(Secret.ChooseValue(nil, 1, 0)), 0)
		local yes, no = { r = 1, g = 0, b = 0 }, { r = 0, g = 1, b = 0 }
		assert.is_true(rawequal(Secret.ChooseColor(nil, yes, no), no))
		local frame = CreateFrame('Frame')
		Secret.SetAlphaFromBoolean(frame, nil, 1, 0)
		assert.equal(M.Get(frame, 'alpha'), 0)
		assert.equal(S.Reveal(Secret.ChooseValue(true, 1, 0)), 1)
	end)
end)

describe('engine: aura rows', function()
	it('never uses the Lua scan on live plates where secrets exist', function()
		local live = P.Plate.New(UIParent, false)
		local preview = P.Plate.New(UIParent, true)
		local spec = { kind = 'auras', row = 'myDebuffs' }
		P.Caps:SetOverride('containers', false)
		local impl = P.Parts:Resolve(spec, live)
		if P.Caps:Get('secrets') then
			assert.is_true(impl == nil or impl.id ~= 'aurasScan', 'no scan on a live plate with secrets')
		else
			assert.equal(impl and impl.id, 'aurasScan')
		end
		local previewImpl = P.Parts:Resolve(spec, preview)
		assert.is_true(previewImpl ~= nil and previewImpl.id ~= 'aurasContainer', 'previews draw sample icons')
		P.Caps:SetOverride('containers', nil)
	end)
end)

describe('engine: preview context', function()
	it('compiles colors for the context a preview plate was given', function()
		local ctx = P.Scenes.PreviewContext({ role = 'tank', tanks = { 'party1' } })
		local plate = P.Plate.New(UIParent, true, ctx)
		assert.is_true(rawequal(plate.env.ctx, ctx))
		local program = P.Colors:Program('health', ctx)
		assert.is_true(rawequal(program, P.Colors:Program('health', ctx)), 'cached per context')
		assert.is_false(rawequal(program, P.Colors:Program('health')), 'separate from the live context')
		assert.equal(program.scheme, 'threat', 'a tank preview puts threat first')
	end)
end)

describe('engine: setup look step', function()
	it('puts the size row on every card and stages style and size together', function()
		local step = P:GetSetupSteps()[1]
		assert.is_nil(step.variants, 'LibAT reads variants per card, not per step')
		local cards = step.cards(step)
		assert.truthy(#cards > 0)
		for _, card in ipairs(cards) do
			assert.not_nil(card.variants, card.title)
			assert.equal(#card.variants, 3)
		end
		step.setVariant(cards[1].value, 'large', {})
		assert.equal(step.get(), cards[1].value)
		assert.equal(step.getVariant(cards[1].value), 'large')
		step.onLeave({})
		assert.equal(P.Store:Get('size'), 'large')
		assert.equal(P.Store:Get('style'), cards[1].value)
		P.Store:Reset('size')
		P.Store:Reset('style')
		assert.equal(P.Store:Get('size'), 'medium', 'reset writes the default back')
	end)
end)
