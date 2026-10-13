-- @runtime lua51
-- The nameplate driver (Engine/Driver.lua, Pool.lua, Suppress.lua; plan 6.5, 6.7, 6.8): our plate
-- on every game plate with Blizzard's frame silenced the way each client allows, widgets kept,
-- click and stacking areas that match the drawn plate (and only change when the game allows it),
-- target, focus and mouseover by frame compare with the hidden-answer fallback, combat queueing,
-- restriction, Show modes, the fact poller, range and fighting fades, and the game settings it
-- writes by place and combat and gives back.
local M, H = ...
local S = M.S

if not H.ModuleExists() then
	describe('driver', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

M.Login('NameplatesTestHost')
local P = H.FreshCore()
local Driver, Suppress, CVars, Store = P.Driver, P.Suppress, P.CVars, P.Store
P:Enable()

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

local function ClearStates()
	M.SetTarget(nil)
	M.SetFocus(nil)
	M.SetMouseover(nil)
end

local function Shown(region)
	return M.Get(region, 'shown') == true
end

local function CountCalls(obj, method)
	return #M.Calls(obj, method)
end

local function Has(list, value)
	for _, v in ipairs(list) do
		if v == value then
			return true
		end
	end
	return false
end

local function CVar(name)
	return C_CVar.GetCVar(name)
end

local function Reset()
	ClearStates()
	HideAll()
	if M.lockdown then
		M.LeaveCombat()
	end
	M.SetRestricted(false)
	Store:Batch(function()
		Store:Set('behavior', nil)
		Store:Set('modes', nil)
		Store:Set('when', nil)
		Store:Set('size', 'medium')
		Store:Set('enabled', true)
	end)
	M.Advance(0.5)
end

describe('driver: plates on game plates', function()
	after_each(Reset)

	it('draws our plate on a game plate and keeps Blizzard quiet', function()
		local token, base = Enemy()
		local plate = P.API:GetPlate(base)
		assert.not_nil(plate, 'the game plate has our plate')
		assert.equal(Driver:ModeOf(plate), 'drawn')
		assert.is_true(Shown(plate.root))
		assert.equal(M.Get(plate.root, 'parent'), base)
		assert.equal(Driver:GetPlateForUnit(token), plate)
		local unitFrame = base.UnitFrame
		assert.equal(M.Get(unitFrame, 'alpha'), 0, 'Blizzard frame faded out')
		assert.same(M.RegisteredEvents(unitFrame), {}, 'Blizzard frame hears nothing')
		assert.same(M.RegisteredEvents(unitFrame.castBar), {}, 'its cast bar hears nothing')
		assert.is_true(Suppress:WasTouched(unitFrame))
	end)

	it('rescues the widget container and soft-target icon onto the game plate', function()
		local _, base = Enemy()
		for _, key in ipairs({ 'WidgetContainer', 'SoftTargetFrame' }) do
			local widget = base.UnitFrame[key]
			assert.equal(M.Get(widget, 'parent'), base, key .. ' sits on the game plate')
			local calls = M.Calls(widget, 'SetIgnoreParentAlpha')
			assert.is_true(#calls > 0 and calls[#calls][1] == true, key .. ' ignores parent alpha again on every add')
		end
	end)

	it('keeps one plate per game plate, rebinds it on every add and never caps the count', function()
		local token, base = Enemy({ name = 'First' })
		local plate = P.API:GetPlate(base)
		M.HidePlate(token)
		assert.is_nil(P.API:GetPlate(base), 'nothing draws without a unit')
		assert.is_false(Shown(plate.root))
		local token2, base2 = Enemy({ name = 'Second' })
		assert.equal(base2, base, 'the mock hands the same game plate out again')
		assert.equal(P.API:GetPlate(base2), plate, 'and our plate comes with it')
		assert.equal(plate.unit, token2)
		local count = 0
		for _ = 1, 59 do
			Enemy()
			count = count + 1
		end
		assert.equal(Driver:CountBound(), count + 1, 'every game plate draws, past 40')
	end)

	it('fires PLATE_ADDED and PLATE_REMOVED through the public API and finds the health bar', function()
		local added, removed = {}, {}
		local owner = {}
		assert.is_true(P.API:RegisterCallback('PLATE_ADDED', function(plate, unit)
			added[#added + 1] = unit
		end, owner))
		assert.is_true(P.API:RegisterCallback('PLATE_REMOVED', function(plate, unit)
			removed[#removed + 1] = unit
		end, owner))
		local token, base = Enemy()
		assert.equal(added[#added], token)
		assert.not_nil(P.API:GetHealthBar(base), 'the clean style draws a health bar')
		M.HidePlate(token)
		assert.equal(removed[#removed], token)
		assert.is_nil(P.API:GetHealthBar(base))
		P.API:UnregisterCallback('PLATE_ADDED', owner)
		P.API:UnregisterCallback('PLATE_REMOVED', owner)
	end)

	it('leaves widget-only plates and game objects to their widgets', function()
		if not UnitNameplateShowsWidgetsOnly then
			skip('this client cannot tell widget-only plates apart')
		end
		local _, base = M.ShowPlate({ name = 'Banner', widgetsOnly = true, canAttack = false, reaction = 4 })
		local plate = Driver.byBase[base]
		assert.equal(Driver:ModeOf(plate), 'widgets')
		assert.is_false(Shown(plate.root))
		assert.is_nil(P.API:GetPlate(base))
		assert.equal(M.Get(base.UnitFrame.WidgetContainer, 'parent'), base, 'the widgets still show')
		assert.equal(M.Get(base.UnitFrame, 'alpha'), 0)
	end)

	it("leaves the player's own plate to Blizzard and gives back a frame it silenced", function()
		local token, base = Enemy()
		local unitFrame = base.UnitFrame
		assert.equal(M.Get(unitFrame, 'alpha'), 0)
		M.HidePlate(token)
		local selfToken, selfBase = M.ShowPlate(M.player)
		assert.equal(selfBase, base, 'the same game plate, with the frame we silenced')
		local plate = Driver.byBase[base]
		assert.equal(Driver:ModeOf(plate), 'self')
		assert.is_false(Shown(plate.root))
		assert.equal(M.Get(unitFrame, 'alpha'), 1, 'Blizzard draws the personal plate again')
		assert.is_false(Suppress:WasTouched(unitFrame))
		M.HidePlate(selfToken)
	end)
end)

describe('driver: hiding Blizzard plates per client', function()
	after_each(function()
		P.Caps.recorded.rolesets = nil
		Reset()
	end)

	it('uses rolesets where the client has them, else a hidden parent', function()
		local _, base = Enemy()
		local unitFrame = base.UnitFrame
		local blocked, hiddenParent, faded = Suppress:StateOf(unitFrame)
		assert.is_true(faded)
		if M.HasMethod('Button', 'SetRolesets') then
			assert.is_true(blocked, 'Retail and Forever block the frame by roleset')
			assert.is_false(hiddenParent)
			local calls = M.Calls(unitFrame, 'SetRolesets')
			assert.equal(calls[#calls][1], 'alwaysBlocked')
			assert.equal(M.Get(unitFrame, 'parent'), base)
		else
			assert.is_false(blocked)
			assert.is_true(hiddenParent, 'the Classic family moves the frame to a hidden parent')
			assert.equal(M.Get(unitFrame, 'parent'), Suppress:HiddenParent())
			assert.is_false(Shown(Suppress:HiddenParent()))
		end
	end)

	it('falls back to the hidden parent when rolesets fail (S7)', function()
		if not M.HasMethod('Button', 'SetRolesets') then
			skip('no rolesets on this client')
		end
		local token, base = Enemy()
		M.HidePlate(token)
		Suppress:RestoreFrame(base.UnitFrame)
		M.Override(base.UnitFrame, 'SetRolesets', function()
			error('blocked')
		end)
		Enemy()
		local blocked, hiddenParent = Suppress:StateOf(base.UnitFrame)
		assert.is_false(blocked)
		assert.is_true(hiddenParent)
		assert.is_false(P.Caps:Get('rolesets'), 'recorded for the rest of the session')
		M.Override(base.UnitFrame, 'SetRolesets', nil)
	end)

	it('only fades and silences a frame the game locks in combat', function()
		local token, base = Enemy()
		M.HidePlate(token)
		local unitFrame = base.UnitFrame
		Suppress:RestoreFrame(unitFrame)
		assert.equal(M.Get(unitFrame, 'parent'), base)
		M.Set(unitFrame, 'protected', true)
		M.EnterCombat()
		local rolesetCalls = CountCalls(unitFrame, 'SetRolesets')
		local blockedBefore = #M.rec.blocked
		assert.no_errors(function()
			Suppress:Apply(base, nil, {})
		end)
		local blocked, hiddenParent, faded = Suppress:StateOf(unitFrame)
		assert.is_false(blocked)
		assert.is_false(hiddenParent)
		assert.is_true(faded)
		assert.equal(M.Get(unitFrame, 'parent'), base, 'no SetParent on a locked frame')
		assert.equal(CountCalls(unitFrame, 'SetRolesets'), rolesetCalls, 'no rolesets on a locked frame')
		assert.equal(#M.rec.blocked, blockedBefore)
		M.LeaveCombat()
		M.Set(unitFrame, 'protected', false)
		Suppress:RestoreFrame(unitFrame)
	end)

	it('gives every frame back when the profile turns plates off, and draws again when it is on', function()
		local token, base = Enemy()
		local plate = P.API:GetPlate(base)
		Store:Set('enabled', false)
		assert.is_false(Driver.standing)
		assert.is_nil(P.API:GetPlate(base))
		assert.is_false(Shown(plate.root))
		assert.equal(M.Get(base.UnitFrame, 'alpha'), 1)
		assert.equal(M.Get(base.UnitFrame, 'parent'), base)
		assert.equal(M.Get(base.UnitFrame.WidgetContainer, 'parent'), base.UnitFrame, 'widgets go home')
		-- New plates are left to the game while the profile does not want ours
		local _, other = Enemy({ name = 'Other' })
		assert.is_nil(P.API:GetPlate(other))
		Store:Set('enabled', true)
		assert.is_true(Driver.standing)
		assert.equal(P.API:GetPlate(base), plate, 'plates already in view draw again')
		assert.not_nil(P.API:GetPlate(other))
		M.HidePlate(token)
	end)
end)

describe('driver: click and stacking areas', function()
	after_each(function()
		P.Caps:SetOverride('hitTest', nil)
		Reset()
	end)

	it('binds the click area on the add tick, and never outside it in combat', function()
		local _, base = Enemy()
		local plate = P.API:GetPlate(base)
		local points = M.Get(base, 'hitTest')
		assert.equal(points[1][2], plate.click, 'the game takes clicks on our click frame')
		assert.equal(CountCalls(base, 'ClearAllHitTestPoints'), CountCalls(base, 'SetAllHitTestPoints'))
		local click = plate.style.regions.click
		assert.equal(M.Get(plate.click, 'w'), click.right - click.left)
		assert.equal(M.Get(plate.click, 'h'), click.top - click.bottom)
		-- A kind shown again in combat draws, but leaves the click points alone until its next add
		Store:Set('modes', { enemyNPC = 'hidden' })
		assert.equal(Driver:ModeOf(plate), 'hidden')
		M.EnterCombat()
		local before = CountCalls(base, 'SetAllHitTestPoints')
		Store:Set('modes', nil)
		assert.equal(Driver:ModeOf(plate), 'drawn')
		assert.equal(CountCalls(base, 'SetAllHitTestPoints'), before)
		assert.equal(#M.errors, 0)
	end)

	it('keeps the game click area when rebinding is off (S1)', function()
		P.Caps:SetOverride('hitTest', false)
		local calls = 0
		for _, base in ipairs(M.Bases()) do
			calls = calls + CountCalls(base, 'SetAllHitTestPoints')
		end
		local _, base = Enemy()
		local after = 0
		for _, each in ipairs(M.Bases()) do
			after = after + CountCalls(each, 'SetAllHitTestPoints')
		end
		assert.equal(after, calls, 'no game plate had its click points moved')
		assert.not_nil(P.API:GetPlate(base), 'the plate still draws')
	end)

	it('hands the stacking frame to the game plate, sized from the style', function()
		local _, base = Enemy()
		local plate = P.API:GetPlate(base)
		assert.equal(M.Get(base, 'stackingBounds'), plate.stack)
		local stack = plate.style.regions.stack
		assert.equal(M.Get(plate.stack, 'w'), stack.right - stack.left)
		assert.equal(M.Get(plate.stack, 'h'), stack.top - stack.bottom)
	end)

	it('stands on the game plate, and hangs hostile plates under units when the game puts them there', function()
		local _, enemyBase = Enemy()
		local _, friendBase = M.ShowPlate({ name = 'Friend', isPlayer = true, canAttack = false, reaction = 5 })
		local enemy, friend = Driver.byBase[enemyBase], Driver.byBase[friendBase]
		local function Point(plate)
			return M.Get(plate.root, 'points')[1]
		end
		local click = enemy.style.regions.click
		assert.same({ Point(enemy)[1], Point(enemy)[3], Point(enemy)[5] }, { 'CENTER', 'BOTTOM', -click.bottom })
		M.SetCVarState('nameplateOtherAtBase', { value = '1' })
		CVars.info.nameplateOtherAtBase = nil
		M.Fire('CVAR_UPDATE', 'nameplateOtherAtBase', '1')
		assert.same({ Point(enemy)[1], Point(enemy)[3], Point(enemy)[5] }, { 'CENTER', 'TOP', -click.top })
		assert.equal(Point(friend)[3], 'BOTTOM', 'friendly plates stay above heads')
		M.SetCVarState('nameplateOtherAtBase', { value = '0' })
		M.Fire('CVAR_UPDATE', 'nameplateOtherAtBase', '0')
		assert.equal(Point(enemy)[3], 'BOTTOM')
	end)

	it('sizes game plates to the largest click area any kind can use, without hidden kinds', function()
		local scale = Driver.CoordScale()
		local w, h = Driver:ComputePlateSize()
		assert.same(M.plateSize, { math.ceil(w * scale), math.ceil(h * scale) })
		Store:Set('when', { { kinds = { 'enemyNPC' }, size = 'large', conditions = {} } })
		local lw, lh = Driver:ComputePlateSize()
		assert.is_true(lw >= w and lh >= h)
		assert.is_true(lw > w or lh > h, 'a When entry picking large grows the plates')
		assert.same(M.plateSize, { math.ceil(lw * scale), math.ceil(lh * scale) })
		Store:Set('when', nil)
		Store:Set('modes', { enemyNPC = 'hidden', enemyPlayer = 'hidden', minor = 'hidden', friendlyPlayer = 'hidden', friendlyNPC = 'hidden' })
		local hw, hh = Driver:ComputePlateSize()
		assert.same({ hw, hh }, { 1, 1 }, 'hidden kinds take no room')
	end)

	it('waits for combat to end before sizing, and writes once however often the game resizes', function()
		M.EnterCombat()
		local before = M.plateSize
		Store:Set('size', 'large')
		assert.same(M.plateSize, before, 'nothing written in combat')
		local writes = CountCalls(M, 'SetNamePlateSize')
		for _ = 1, 5 do
			M.plateSize = { 110, 45 } -- the game sets its own size
			NamePlateDriverFrame:UpdateNamePlateOptions()
		end
		assert.equal(CountCalls(M, 'SetNamePlateSize'), writes)
		M.LeaveCombat()
		assert.equal(CountCalls(M, 'SetNamePlateSize'), writes + 1, 'one write after combat')
		local scale = Driver.CoordScale()
		local w, h = Driver:ComputePlateSize()
		assert.same(M.plateSize, { math.ceil(w * scale), math.ceil(h * scale) })
		assert.same(Driver.blizzSize, { 110, 45 }, 'the size to give back is the one the game set last')
		-- Out of combat the game's own size is put back over at once
		M.plateSize = { 120, 50 }
		NamePlateDriverFrame:UpdateNamePlateOptions()
		assert.same(M.plateSize, { math.ceil(w * scale), math.ceil(h * scale) })
		assert.same(Driver.blizzSize, { 120, 50 })
	end)

	it('makes room for the UI scale where game plates ignore it (Mists quirk)', function()
		if not P.Caps:Quirk('uiParentScale') then
			skip('only clients with Quirk uiParentScale')
		end
		local _, base = Enemy()
		local plate = P.API:GetPlate(base)
		UIParent:SetScale(1.5)
		M.Fire('UI_SCALE_CHANGED')
		assert.equal(M.Get(plate.root, 'scale'), 1.5)
		local w, h = Driver:ComputePlateSize()
		assert.same(M.plateSize, { math.ceil(w * 1.5), math.ceil(h * 1.5) })
		UIParent:SetScale(1)
		M.Fire('UI_SCALE_CHANGED')
	end)
end)

describe('driver: target, focus and mouseover', function()
	local realMouseDown = rawget(_G, 'IsMouseButtonDown')
	after_each(function()
		rawset(_G, 'IsMouseButtonDown', realMouseDown)
		Reset()
	end)

	it('moves the target state by frame compare and fades the others through the context', function()
		local token1, base1 = Enemy({ name = 'One' })
		local token2, base2 = Enemy({ name = 'Two' })
		local plate1, plate2 = P.API:GetPlate(base1), P.API:GetPlate(base2)
		local seen = 0
		P:On('TARGET_CHANGED', function()
			seen = seen + 1
		end, 'driverTest')
		M.SetTarget(token1)
		assert.is_true(plate1.states.target)
		assert.is_nil(plate2.states.target)
		assert.is_true(P.Context.hasTarget)
		M.SetTarget(token2)
		assert.is_nil(plate1.states.target)
		assert.is_true(plate2.states.target)
		M.SetTarget(nil)
		assert.is_nil(plate2.states.target)
		assert.is_false(P.Context.hasTarget)
		assert.equal(seen, 3)
		P:Off('TARGET_CHANGED', 'driverTest')
	end)

	it('gives a plate added later the states that are already set', function()
		local unit = M.AddUnit({ name = 'Late', canAttack = true, reaction = 2 })
		M.SetTarget(nil)
		M.SetToken('target', unit)
		M.Fire('PLAYER_TARGET_CHANGED')
		local _, base = M.ShowPlate(unit)
		assert.is_true(P.API:GetPlate(base).states.target)
	end)

	it('marks focus and mouseover, and clears mouseover after the mouse leaves', function()
		local token, base = Enemy()
		local plate = P.API:GetPlate(base)
		M.SetFocus(token)
		assert.is_true(plate.states.focus)
		M.SetMouseover(token)
		assert.is_true(plate.states.mouseover)
		assert.is_true(P.Scheduler:IsRunning('Driver.mouseover'))
		M.SetToken('mouseover', nil)
		M.Advance(0.25)
		assert.is_nil(plate.states.mouseover)
		assert.is_false(P.Scheduler:IsRunning('Driver.mouseover'), 'the leave check stops')
	end)

	it('waits for the mouse button to come up before clearing mouseover', function()
		local token, base = Enemy()
		local plate = P.API:GetPlate(base)
		local held = true
		rawset(_G, 'IsMouseButtonDown', function()
			return held
		end)
		M.SetMouseover(token)
		M.SetToken('mouseover', nil)
		M.Advance(0.5)
		assert.is_true(plate.states.mouseover, 'kept while a button is held (camera turning)')
		held = false
		M.Fire('GLOBAL_MOUSE_UP', 'LeftButton')
		assert.is_nil(plate.states.mouseover)
	end)

	it('falls back to hidden answers when the game will not say which plate is the target (S4)', function()
		if not M.secrets then
			skip('only clients with secrets hide the target plate')
		end
		local token1, base1 = Enemy({ name = 'One' })
		local token2, base2 = Enemy({ name = 'Two' })
		local plate1, plate2 = P.API:GetPlate(base1), P.API:GetPlate(base2)
		local arrows1, arrows2 = plate1:GetWidget('arrows'), plate2:GetWidget('arrows')
		local realUnitIsUnit = rawget(_G, 'UnitIsUnit')
		-- The comparison comes back secret (SecretWhenUnitComparisonRestricted)
		rawset(_G, 'UnitIsUnit', function(a, b)
			return S.Wrap(M.FN.UnitIsUnit(a, b))
		end)
		M.SetRestricted(true)
		M.SetTarget(token1)
		rawset(_G, 'UnitIsUnit', realUnitIsUnit)
		assert.is_true(Driver.secretStates.target == true, 'known only through hidden answers')
		assert.is_false(P.Context.hasTarget, 'no fade of other plates while hidden')
		if arrows1 and arrows2 then
			assert.equal(M.Get(arrows1.frame, 'alpha'), 1)
			assert.equal(M.Get(arrows2.frame, 'alpha'), 0)
			assert.is_true(M.Get(arrows2.frame, 'alphaSecret'), 'faded by the engine, never read')
		end
		-- No answer at all (RequiresComparableUnitTokens): faded out, still no fade of the others
		M.SetTarget(token2)
		assert.is_true(Driver.secretStates.target == true)
		assert.is_false(P.Context.hasTarget)
		M.SetRestricted(false)
		M.SetTarget(token2)
		assert.is_nil(Driver.secretStates.target)
		assert.is_true(plate2.states.target)
		assert.is_nil(plate1.states.target)
		assert.is_true(P.Context.hasTarget)
		if arrows1 and arrows2 then
			assert.equal(M.Get(arrows2.frame, 'alpha'), 1, 'the hidden fade is lifted before the plain answer')
			assert.is_true(Shown(arrows2.frame))
			assert.is_false(Shown(arrows1.frame))
			assert.equal(M.Get(arrows1.frame, 'alpha'), 1)
		end
	end)
end)

describe('driver: Show modes and minor enemies', function()
	after_each(Reset)

	it('hides a kind in Show mode hidden and draws it again', function()
		local _, base = Enemy()
		local plate = Driver.byBase[base]
		Store:Set('modes', { enemyNPC = 'hidden' })
		assert.equal(Driver:ModeOf(plate), 'hidden')
		assert.is_false(Shown(plate.root))
		assert.is_nil(P.API:GetPlate(base))
		assert.equal(M.Get(base.UnitFrame, 'alpha'), 0, 'the game plate stays hidden too')
		Store:Set('modes', nil)
		assert.equal(Driver:ModeOf(plate), 'drawn')
		assert.is_true(Shown(plate.root))
	end)

	it('gives minor enemies our small style and keeps the engine from shrinking them (S8)', function()
		local token, base = Enemy({ classification = 'minus' })
		local plate = P.API:GetPlate(base)
		assert.equal(plate.situation, 'minor')
		assert.equal(plate.style.id, 'mini')
		local calls = M.FnCalls('C_NamePlateManager.SetNamePlateSimplified')
		if C_NamePlateManager and C_NamePlateManager.SetNamePlateSimplified then
			local last = calls[#calls]
			assert.equal(last[1], token)
			assert.is_false(last[2])
		end
	end)
end)

describe('driver: fighting and range', function()
	local rangeLib
	after_each(Reset)

	it('fades enemies that are not fighting when asked, and keeps the target', function()
		Store:Set('behavior', { onlyFighting = true })
		local token, base, unit = Enemy({ inCombat = false })
		local plate = P.API:GetPlate(base)
		assert.equal(M.Get(plate.root, 'alpha'), 0)
		M.UpdateUnit(unit, { inCombat = true })
		M.Advance(1)
		assert.equal(M.Get(plate.root, 'alpha'), 1, 'the poller notices the fight')
		M.UpdateUnit(unit, { inCombat = false })
		M.Advance(1)
		assert.equal(M.Get(plate.root, 'alpha'), 0)
		M.SetTarget(token)
		assert.equal(M.Get(plate.root, 'alpha'), 1, 'the target always shows')
		assert.is_true(Driver:FeatureState('onlyFighting'))
	end)

	it("falls back to the interrupt's own range without the range library, and to nothing without either", function()
		local realInRange = C_Spell.IsSpellInRange
		local realKick = P.Context.kickSpell
		P.Context.kickSpell = 2139
		C_Spell.IsSpellInRange = function(spell, unit)
			local u = M.UnitFor(unit)
			return u ~= nil and u.near == true
		end
		Store:Set('behavior', { rangeFade = 0.5 })
		assert.equal(Driver.rangeHow, 'spell')
		local _, farBase = Enemy({ near = false })
		M.Advance(1)
		assert.equal(M.Get(P.API:GetPlate(farBase).root, 'alpha'), 0.5)
		C_Spell.IsSpellInRange = realInRange
		P.Context.kickSpell = nil
		Store:Set('behavior', { rangeFade = 0.3 })
		assert.is_nil(Driver.rangeHow, 'no way to read range: range fade stays off')
		assert.is_nil(Driver.rangeAlpha)
		local available, reason = Driver:FeatureState('rangeFade')
		assert.is_false(available)
		assert.not_nil(reason, 'a plain reason for the options')
		P.Context.kickSpell = realKick
	end)

	it('reads range from the range library when it is loaded and fades plates out of range', function()
		rangeLib = LibStub:NewLibrary('LibRangeCheck-3.0', 1) or LibStub('LibRangeCheck-3.0')
		function rangeLib:GetHarmMaxChecker(range)
			return function(unit)
				local u = M.UnitFor(unit)
				return u ~= nil and u.near == true
			end, range
		end
		Store:Set('behavior', { rangeFade = 0.4 })
		assert.equal(Driver.rangeHow, 'library')
		local _, nearBase = Enemy({ near = true })
		local _, farBase = Enemy({ near = false })
		M.Advance(1)
		assert.equal(M.Get(P.API:GetPlate(nearBase).root, 'alpha'), 1)
		assert.equal(M.Get(P.API:GetPlate(farBase).root, 'alpha'), 0.4)
		assert.is_true(Driver:FeatureState('rangeFade'))
	end)

	it('polls a bounded number of plates per tick', function()
		for _ = 1, 100 do
			Enemy()
		end
		local polled = 0
		local real = Driver.PollPlate
		Driver.PollPlate = function(self, plate)
			polled = polled + 1
			return real(self, plate)
		end
		Driver.PollTick()
		Driver.PollPlate = real
		assert.equal(polled, Driver.POLL_MAX_PER_TICK)
	end)

	it('does no per-frame work while no plates show', function()
		Enemy()
		assert.is_true(P.Scheduler:IsRunning('Driver.poll'))
		HideAll()
		M.Advance(2)
		assert.is_false(P.Scheduler:IsRunning('Driver.poll'))
		assert.equal(#M.ActiveOnUpdates(), 0)
	end)
end)

describe('driver: context, restriction and messages', function()
	after_each(function()
		M.SetPlace({ inInstance = false, instanceType = 'none', difficultyID = 0 })
		Reset()
	end)

	it('reads the place and fires CONTEXT_CHANGED once per change', function()
		local fired = 0
		P:On('CONTEXT_CHANGED', function()
			fired = fired + 1
		end, 'driverTest')
		M.SetPlace({ inInstance = true, instanceType = 'party', difficultyID = 1 })
		assert.equal(P.Context.place, 'dungeon')
		assert.equal(fired, 1, 'two zone events, one change')
		M.SetPlace({ inInstance = true, instanceType = 'scenario', difficultyID = 208 })
		assert.equal(P.Context.place, 'delve')
		M.SetPlace({ inInstance = true, instanceType = 'neighborhood', difficultyID = 0 })
		assert.equal(P.Context.place, 'world', 'housing counts as the open world')
		P:Off('CONTEXT_CHANGED', 'driverTest')
	end)

	it('fires RESTRICTION_CHANGED around combat and configures waiting plates after it', function()
		local _, base = Enemy()
		local plate = P.API:GetPlate(base)
		local seen = {}
		P:On('RESTRICTION_CHANGED', function(isRestricted)
			seen[#seen + 1] = isRestricted
		end, 'driverTest')
		M.EnterCombat()
		M.Advance(0.1)
		assert.is_true(seen[#seen], 'restricted once lockdown starts')
		plate:Configure()
		assert.is_true(plate.pendingConfigure)
		M.LeaveCombat()
		assert.is_false(seen[#seen])
		assert.is_nil(plate.pendingConfigure, 'the waiting aura settings went through')
		P:Off('RESTRICTION_CHANGED', 'driverTest')
	end)

	it('relays raid marker changes to bound plates', function()
		local _, base = Enemy()
		local plate = P.API:GetPlate(base)
		local got = 0
		local real = plate.OnMessage
		plate.OnMessage = function(self, message, ...)
			if message == 'RAID_TARGET_UPDATE' then
				got = got + 1
			end
			return real(self, message, ...)
		end
		M.Fire('RAID_TARGET_UPDATE')
		plate.OnMessage = nil
		assert.equal(got, 1)
	end)

	it('numbers arena opponents by frame compare (S18) and tells the plates', function()
		local token1, base1, unit1 = Enemy({ name = 'Rogue', isPlayer = true })
		local _, base2, unit2 = Enemy({ name = 'Mage', isPlayer = true })
		local changed = 0
		P:On('ARENA_CHANGED', function()
			changed = changed + 1
		end, 'driverTest')
		M.SetPlace({ inInstance = true, instanceType = 'arena', difficultyID = 0 })
		assert.equal(P.Context.place, 'arena')
		M.SetToken('arena1', unit2)
		M.SetToken('arena2', unit1)
		M.Fire('ARENA_OPPONENT_UPDATE', 'arena1', 'seen')
		assert.equal(P.API:GetPlate(base2).arenaIndex, 1)
		assert.equal(P.API:GetPlate(base1).arenaIndex, 2)
		assert.is_true(changed >= 1)
		-- A plate added later gets its number on the add
		M.HidePlate(token1)
		local _, base3 = M.ShowPlate(unit1)
		assert.equal(P.API:GetPlate(base3).arenaIndex, 2)
		M.SetToken('arena1', nil)
		M.SetToken('arena2', nil)
		P:Off('ARENA_CHANGED', 'driverTest')
	end)

	it('builds plates ahead of time out of combat only', function()
		local Pool = P.Pool
		M.EnterCombat()
		local built = Pool.built
		Pool:Prewarm(built + 3)
		M.Advance(1)
		assert.equal(Pool.built, built, 'nothing is built in combat')
		M.LeaveCombat()
		M.Advance(1)
		assert.equal(Pool.built, built + 3)
		assert.is_true(Pool.done)
		assert.is_false(P.Scheduler:IsRunning('Pool.prewarm'))
		-- A new game plate (NAME_PLATE_CREATED) takes a warm plate instead of building one
		local free = Pool:FreeCount()
		assert.is_true(free > 0)
		local base = M.NewObject('NamePlate', nil, WorldFrame)
		local plate = Driver:OnCreated(base)
		assert.equal(Pool:FreeCount(), free - 1)
		assert.equal(Pool.built, built + 3, 'no new plate was built')
		assert.equal(plate.base, base)
		assert.equal(M.Get(plate.root, 'parent'), base)
		assert.equal(M.Get(base, 'stackingBounds'), plate.stack)
		assert.is_false(Shown(plate.root), 'nothing shows until a unit is added')
	end)
end)

describe('driver: game settings by place and combat', function()
	after_each(function()
		M.SetPlace({ inInstance = false, instanceType = 'none', difficultyID = 0 })
		Reset()
		P.util.Wipe(Driver.yielded)
	end)

	it('turns stacking bits on and gives them back', function()
		if not Driver:FeatureState('stacking') then
			skip('no stacking setting on this client')
		end
		M.SetCVarState('nameplateStackingTypes', { value = '0' })
		Store:Set('behavior', { stacking = { enemy = true, friendly = true } })
		assert.is_true(CVars:GetBit('nameplateStackingTypes', 'enemy'))
		assert.is_true(CVars:GetBit('nameplateStackingTypes', 'friendly'))
		Store:Set('behavior', nil)
		assert.equal(CVar('nameplateStackingTypes'), '0')
		assert.is_nil(CVars:GetBackup('nameplateStackingTypes'))
	end)

	it('shows enemies only in combat when asked', function()
		M.SetCVarState('nameplateShowEnemies', { value = '1' })
		Store:Set('behavior', { enemies = 'combat' })
		assert.equal(CVar('nameplateShowEnemies'), '0')
		M.EnterCombat()
		assert.equal(CVar('nameplateShowEnemies'), '1', 'written before lockdown starts')
		M.LeaveCombat()
		assert.equal(CVar('nameplateShowEnemies'), '0')
		Store:Set('behavior', nil)
		assert.equal(CVar('nameplateShowEnemies'), '1', 'the player value comes back')
	end)

	it('shows friendly names only inside instances', function()
		if not Driver:FeatureState('friendlyNames') then
			skip('no names-only setting on this client')
		end
		M.SetCVarState('nameplateShowOnlyNameForFriendlyPlayerUnits', { value = '0' })
		Store:Set('behavior', { friendlyNames = true })
		assert.equal(CVar('nameplateShowOnlyNameForFriendlyPlayerUnits'), '0', 'the open world uses our own name plates')
		M.SetPlace({ inInstance = true, instanceType = 'raid', difficultyID = 14 })
		assert.equal(CVar('nameplateShowOnlyNameForFriendlyPlayerUnits'), '1')
		if CVars:Exists('nameplateUseClassColorForFriendlyPlayerUnitNames') then
			assert.equal(CVar('nameplateUseClassColorForFriendlyPlayerUnitNames'), '1')
		end
		M.SetPlace({ inInstance = false, instanceType = 'none', difficultyID = 0 })
		assert.equal(CVar('nameplateShowOnlyNameForFriendlyPlayerUnits'), '0')
	end)

	it('pins the distance scale to 1 when asked', function()
		if not Driver:FeatureState('pinScale') then
			skip('no distance scale on this client')
		end
		M.SetCVarState('nameplateMinScale', { value = '0.8' })
		Store:Set('behavior', { pinScale = true })
		assert.equal(CVar('nameplateMinScale'), '1')
		Store:Set('behavior', nil)
		assert.equal(CVar('nameplateMinScale'), '0.8')
	end)

	it('fades plates behind walls where the client can, with its own value in combat', function()
		if not Driver:FeatureState('fadeBehindWalls') then
			skip('no wall fade on this client')
		end
		M.SetCVarState('nameplateOccludedAlphaMult', { value = '0.4' })
		Store:Set('behavior', { fadeBehindWalls = 0.2, fadeBehindWallsCombat = 0.6 })
		assert.equal(CVar('nameplateOccludedAlphaMult'), '0.2')
		M.EnterCombat()
		assert.equal(CVar('nameplateOccludedAlphaMult'), '0.6')
		M.LeaveCombat()
		assert.equal(CVar('nameplateOccludedAlphaMult'), '0.2')
		Store:Set('behavior', nil)
		assert.equal(CVar('nameplateOccludedAlphaMult'), '0.4')
	end)

	it('uses per-place values ahead of the general ones', function()
		M.SetCVarState('nameplateShowEnemies', { value = '0' })
		Store:Set('behavior', { enemies = 'always', places = { dungeon = { enemies = 'combat' } } })
		assert.equal(CVar('nameplateShowEnemies'), '1')
		M.SetPlace({ inInstance = true, instanceType = 'party', difficultyID = 1 })
		assert.equal(CVar('nameplateShowEnemies'), '0')
		M.SetPlace({ inInstance = false, instanceType = 'none', difficultyID = 0 })
		assert.equal(CVar('nameplateShowEnemies'), '1')
	end)

	it('turns off the game enemy aura icons on the Classic family while it draws', function()
		if M.secrets then
			skip('only the Classic family')
		end
		if not CVars:Exists('nameplateEnemyNpcAuraDisplay') then
			skip('no aura display setting on this client')
		end
		M.SetCVarState('nameplateEnemyNpcAuraDisplay', { value = '7' })
		Store:Set('behavior', { pinScale = false })
		assert.is_false(CVars:GetBit('nameplateEnemyNpcAuraDisplay', 'buffs'))
		assert.is_false(CVars:GetBit('nameplateEnemyNpcAuraDisplay', 'debuffs'))
		Store:Set('enabled', false)
		assert.equal(CVar('nameplateEnemyNpcAuraDisplay'), '7', 'given back when plates stand down')
		Store:Set('enabled', true)
	end)

	it('hides the game plates of a kind hidden in every place', function()
		M.SetCVarState('nameplateShowFriendlyNpcs', { value = '1' })
		Store:Set('modes', { friendlyNPC = 'hidden' })
		assert.equal(CVar('nameplateShowFriendlyNpcs'), '0')
		Store:Set('when', { { kinds = { 'friendlyNPC' }, mode = 'full', conditions = { { id = 'place', args = 'world' } } } })
		assert.equal(CVar('nameplateShowFriendlyNpcs'), '1', 'a When entry can still show them')
	end)

	it('leaves a setting alone after something else changes it', function()
		M.SetCVarState('nameplateShowEnemies', { value = '0' })
		Store:Set('behavior', { enemies = 'always' })
		assert.equal(CVar('nameplateShowEnemies'), '1')
		C_CVar.SetCVar('nameplateShowEnemies', '0')
		assert.equal(CVars:GetAttribution('nameplateShowEnemies').by, 'other')
		assert.is_true(Driver.yielded.nameplateShowEnemies)
		M.SetPlace({ inInstance = true, instanceType = 'party', difficultyID = 1 })
		assert.equal(CVar('nameplateShowEnemies'), '0', 'not written back this session')
		Store:Set('behavior', { enemies = 'always', stacking = {} })
		assert.equal(CVar('nameplateShowEnemies'), '1', 'until the player changes our settings')
		-- Setting names ignore case in the game, so another spelling counts as the same setting
		P.util.Wipe(Driver.yielded)
		pcall(C_CVar.SetCVar, 'NamePlateShowEnemies', '0')
		assert.is_true(Driver.yielded.nameplateShowEnemies)
	end)

	it('changes no settings after the tester switch is turned off', function()
		local session = P.Config.sessionEngine
		P.Config.sessionEngine = 'new'
		P.db.char.engine = 'old'
		M.SetCVarState('nameplateShowEnemies', { value = '0' })
		Store:Set('behavior', { enemies = 'always' })
		assert.equal(CVar('nameplateShowEnemies'), '0')
		assert.is_false(Driver:OwnsSettings())
		P.Config.sessionEngine = session
		P.db.char.engine = nil
	end)
end)

describe('driver: stopping', function()
	it('gives back the plate size, the game frames and every setting when the engine stops', function()
		M.SetCVarState('nameplateShowEnemies', { value = '0' })
		Store:Set('behavior', { enemies = 'always' })
		local _, base = Enemy()
		assert.equal(CVar('nameplateShowEnemies'), '1')
		local blizz = Driver.blizzSize and { Driver.blizzSize[1], Driver.blizzSize[2] }
		P:Disable()
		assert.equal(CVar('nameplateShowEnemies'), '0')
		assert.equal(M.Get(base.UnitFrame, 'alpha'), 1)
		if blizz then
			assert.same(M.plateSize, blizz)
		end
		assert.equal(P:RegisteredEventCount(), 0, 'no game events left')
		assert.is_false(P.Scheduler:IsRunning('Driver.poll'))
		-- Starting again draws the plates in view
		P:Enable()
		assert.not_nil(P.API:GetPlate(base))
		Store:Set('behavior', nil)
		HideAll()
	end)
end)
