-- @runtime lua51
local M, H = ...
local P = H.FreshCore()
local D, Merge, Schema = P.Designer, P.Styles.Merge, P.Styles.Schema
local locked, forbiddenAtInit = false, false
P.Secret.IsRestricted = function()
	return locked
end
P.services.FontPath = function()
	return 'Fonts\\Test.ttf'
end

local buttons = setmetatable({}, { __mode = 'k' })
local WT = M.WT.AuraContainer
if WT then
	local add = WT.AddAuraGroup
	WT.AddAuraGroup = function(container, key, filter, options)
		add(container, key, filter, options)
		local button = M.NewObject('Button', nil, container)
		local rec = { button = button, forbidden = forbiddenAtInit, setters = 0 }
		buttons[button] = rec
		M.Override(button, 'IsForbidden', function()
			return rec.forbidden
		end)
		for _, method in ipairs({ 'SetIcon', 'SetDurationCooldown', 'SetDurationText', 'SetApplicationCount', 'ClearDurationText', 'ClearApplicationCount' }) do
			local name = method
			M.Override(button, name, function(_, region)
				rec.setters = rec.setters + 1
				if name == 'SetDurationText' then
					rec.timer = region
				end
				if name == 'SetApplicationCount' then
					rec.stacks = region
				end
			end)
		end
		options.initializeFrame(button)
	end
end

local function Reset()
	D:Detach()
	locked, forbiddenAtInit = false, false
	P.Store:Set('style', 'clean')
	P.Store:Set('tweaks', nil)
	P.Store:Set('auras', nil)
	D.history:Clear()
	D:SetScope('all')
	D.state.kind, D.state.auraText = 'enemyNPC', nil
	wipe(D.state.selection)
end

local function Position(text)
	local p = M.Get(text, 'points')[1]
	return { p[1], p[3], p[4], p[5] }
end

local function Preview()
	local plate = P.Plate.New(UIParent, true, P.Scenes.PreviewContext({}))
	plate:ApplyStyle(Merge:Resolve('clean', 'enemyNPC', 'medium'))
	plate:BindSample(P.Source.NewSample({ facts = { canAttack = true, reaction = 2 }, auras = { myDebuffs = { { icon = 136207, duration = 18, remaining = 12, stacks = 5 } } } }))
	return plate, plate:GetWidget('mine').icons[1]
end

local function Live()
	local token, base = M.ShowPlate({ name = 'Test enemy', reaction = 2, canAttack = true })
	local plate = P.Plate.New(base, false)
	plate:ApplyStyle(Merge:Resolve('clean', 'enemyNPC', 'medium'))
	plate:Bind(token, P.Source.NewLive(token))
	local widget = plate:GetWidget('mine')
	return plate, token, widget, widget.rec and buttons[widget.rec.buttons[1]]
end

local function Stop(plate, token)
	plate:Unbind()
	if token then
		M.HidePlate(token)
	end
end

describe('aura text data and rendering', function()
	before_each(Reset)

	it('keeps old timer and stacks positions and the row font size', function()
		P.Store:Set('tweaks.clean.changes.parts.mine.font.size', 14)
		local plate, icon = Preview()
		assert.same(Position(icon.timer), { 'CENTER', 'CENTER', 0, 0 })
		assert.same(Position(icon.count), { 'BOTTOMRIGHT', 'BOTTOMRIGHT', 1, 0 })
		assert.equal(M.Get(icon.timer, 'font')[2], 14)
		assert.equal(M.Get(icon.count, 'font')[2], 14)
		Stop(plate)
	end)

	it('draws separate points, offsets and sizes without moving the row', function()
		D:SetAuraText('mine', 'timerAnchor', { point = 'TOP', relPoint = 'BOTTOM', x = 2.5, y = -3, size = 12 })
		D:SetAuraText('mine', 'stackAnchor', { point = 'BOTTOMLEFT', relPoint = 'TOPRIGHT', x = -1, y = 4, size = 8 })
		local plate, icon = Preview()
		assert.same(Position(icon.timer), { 'TOP', 'BOTTOM', 2.5, -3 })
		assert.same(Position(icon.count), { 'BOTTOMLEFT', 'TOPRIGHT', -1, 4 })
		assert.equal(M.Get(icon.timer, 'font')[2], 12)
		assert.equal(M.Get(icon.count, 'font')[2], 8)
		assert.same(plate.style.parts.mine.anchor, P.Styles.Registry:Get('clean').parts.mine.anchor)
		Stop(plate)
	end)

	it('validates partial anchors and clamps their ranges in full styles and patches', function()
		local style = P.util.Copy(P.Styles.Registry:Get('clean'))
		style.parts.mine.timerAnchor = { point = 'TOP', relPoint = 'BOTTOM', x = 100, y = -100, size = 80, other = true }
		style.situations.enemyNPC = { parts = { mine = { stackAnchor = { x = 2.5, size = 1 } } } }
		local clean, report = Schema:ValidateStyle(style)
		assert.equal(report.dropped, 1)
		assert.equal(report.clamped, 4)
		assert.same(clean.parts.mine.timerAnchor, { point = 'TOP', relPoint = 'BOTTOM', x = 64, y = -64, size = 40 })
		assert.same(clean.situations.enemyNPC.parts.mine.stackAnchor, { x = 2.5, size = 6 })
		local over, overReport = Schema:ValidateOverlay({ changes = { parts = { mine = { timerAnchor = { x = 4, size = 13 } } } } }, style.parts)
		assert.equal(overReport.dropped, 0)
		assert.same(over.changes.parts.mine.timerAnchor, { x = 4, size = 13 })
	end)

	it('drops invalid points, nonfinite numbers and a part-relative target', function()
		local report = Schema.NewReport()
		local checked = Schema:CheckPart({ kind = 'auras', timerAnchor = { point = 'wrong', relPoint = 'plate', x = math.huge, y = 0 / 0, relativeTo = 'health' } }, 'row', report)
		assert.equal(report.dropped, 5)
		assert.same(checked.timerAnchor, {})
	end)

	it('adds optional data without changing the schema or mutating old styles', function()
		local base = P.Styles.Registry:Get('clean')
		local old = P.util.Copy(base)
		local resolved = Merge.ResolveRaw(base, nil, 'enemyNPC', 'medium')
		assert.equal(Schema.CURRENT, 1)
		assert.same(Merge.AuraText(resolved.parts.mine, 'timerAnchor'), { point = 'CENTER', relPoint = 'CENTER', x = 0, y = 0, size = 9 })
		assert.same(base, old)
	end)
end)

describe('aura text on container buttons', function()
	before_each(Reset)

	it('uses engine button setters and preserves old placement', function()
		if not P.Caps:Get('containers') then
			skip('This client uses the scan renderer')
			return
		end
		local plate, token, widget, rec = Live()
		assert.not_nil(rec.timer)
		assert.not_nil(rec.stacks)
		assert.same(Position(rec.timer), { 'CENTER', 'CENTER', 0, 0 })
		assert.same(Position(rec.stacks), { 'BOTTOMRIGHT', 'BOTTOMRIGHT', 1, 0 })
		assert.equal(M.Get(rec.timer, 'font')[2], 9)
		Stop(plate, token)
	end)

	it('restyles pooled buttons when either anchor changes and makes no new container', function()
		if not P.Caps:Get('containers') then
			skip('This client uses the scan renderer')
			return
		end
		local plate, token, widget, rec = Live()
		local container = widget.rec.container
		D:SetAuraText('mine', 'timerAnchor', { point = 'BOTTOM', relPoint = 'TOP', x = 1, y = 4, size = 14 })
		D:SetAuraText('mine', 'stackAnchor', { point = 'TOPLEFT', relPoint = 'TOPLEFT', x = -2, y = 1, size = 11 })
		plate:ApplyStyle(Merge:Resolve('clean', 'enemyNPC', 'medium'))
		assert.equal(widget.rec.container, container)
		assert.same(Position(rec.timer), { 'BOTTOM', 'TOP', 1, 4 })
		assert.same(Position(rec.stacks), { 'TOPLEFT', 'TOPLEFT', -2, 1 })
		assert.equal(M.Get(rec.timer, 'font')[2], 14)
		assert.equal(M.Get(rec.stacks, 'font')[2], 11)
		Stop(plate, token)
	end)

	it('does not touch forbidden buttons during initialization or restyling', function()
		if not P.Caps:Get('containers') then
			skip('This client uses the scan renderer')
			return
		end
		forbiddenAtInit = true
		local plate, token, widget = Live()
		-- Forbidden buttons are never added to the owned list.
		assert.equal(#widget.rec.buttons, 0)
		Stop(plate, token)
		forbiddenAtInit = false
		local live, unit, w, rec = Live()
		rec.forbidden = true
		local calls = #M.Calls(rec.button)
		D:SetAuraText('mine', 'timerAnchor', { x = 6 })
		live:ApplyStyle(Merge:Resolve('clean', 'enemyNPC', 'medium'))
		assert.equal(#M.Calls(rec.button), calls)
		assert.same(Position(rec.timer), { 'CENTER', 'CENTER', 0, 0 })
		Stop(live, unit)
	end)

	it('keeps text unchanged during restrictions then applies pending placement', function()
		if not P.Caps:Get('containers') then
			skip('This client uses the scan renderer')
			return
		end
		local plate, token, widget, rec = Live()
		locked = true
		P.Store:Set('tweaks.clean.changes.parts.mine.timerAnchor', { x = 7, size = 12 })
		plate:ApplyStyle(Merge:Resolve('clean', 'enemyNPC', 'medium'))
		assert.same(Position(rec.timer), { 'CENTER', 'CENTER', 0, 0 })
		assert.equal(M.Get(rec.timer, 'font')[2], 9)
		locked = false
		plate:Configure()
		assert.same(Position(rec.timer), { 'CENTER', 'CENTER', 7, 0 })
		assert.equal(M.Get(rec.timer, 'font')[2], 12)
		Stop(plate, token)
	end)
end)
