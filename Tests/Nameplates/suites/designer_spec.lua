-- @runtime lua51
local M, H = ...

if not H.ModuleExists() then
	describe('designer', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

local P = H.FreshCore()
local D = P.Designer
local Schema = P.Styles.Schema
P.services.GetAccent = function()
	return 0.2, 0.4, 0.6
end
P.services.FontPath = function()
	return 'Fonts\\Fallback.ttf'
end

local plate = { left = -66, right = 66, top = 5, bottom = -5 }
local nameAnchor = { 'BOTTOMLEFT', 'health', 'TOPLEFT', 0, 2 }
local hpAnchor = { 'RIGHT', 'health', 'RIGHT', -2, 0 }
local castAnchor = { 'TOP', 'health', 'BOTTOM', 0, -2 }

local function Reset()
	P.Store:Set('tweaks', nil)
	P.Store:Set('style', 'clean')
	D.history:Clear()
	wipe(D.state.selection)
	D:SetScope('all')
	D.state.kind = 'enemyNPC'
end

local function Change(id, field)
	return P.Store:Get('tweaks.clean.changes.parts.' .. id .. '.' .. field)
end

local function Chain()
	return {
		a = { kind = 'text', anchor = { 'CENTER', 'plate', 'CENTER', 0, 0 } },
		b = { kind = 'text', anchor = { 'CENTER', 'a', 'CENTER', 0, 0 } },
		c = { kind = 'text', anchor = { 'CENTER', 'b', 'CENTER', 0, 0 } },
		d = { kind = 'text', anchor = { 'CENTER', 'plate', 'CENTER', 0, 0 } },
	}
end

describe('designer', function()
	before_each(Reset)

	describe('drop anchors', function()
		it('pins a left-aligned part fully above the plate', function()
			assert.same(D.DropAnchor({ left = -66, right = -46, bottom = 7, top = 17 }, { plate = plate }), { 'BOTTOMLEFT', 'plate', 'TOPLEFT', 0, 2 })
		end)

		it('snaps an above part within two pixels to the horizontal center', function()
			assert.same(D.DropAnchor({ left = -8.5, right = 11.5, bottom = 7, top = 17 }, { plate = plate }), { 'BOTTOM', 'plate', 'TOP', 0, 2 })
		end)

		it('pins a vertically centered part to the right with its gap', function()
			assert.same(D.DropAnchor({ left = 70, right = 90, bottom = -5, top = 5 }, { plate = plate }), { 'LEFT', 'plate', 'RIGHT', 4, 0 })
		end)

		it('pins an inside part near the right edge with an inward offset', function()
			assert.same(D.DropAnchor({ left = 44, right = 64, bottom = -2, top = 2 }, { plate = plate }), { 'RIGHT', 'plate', 'RIGHT', -2, 0 })
		end)

		it('rounds fractional offsets to half pixels', function()
			local anchor = D.DropAnchor({ left = -65.7, right = -45.7, bottom = 5.74, top = 15.74 }, { plate = plate })
			assert.same(anchor, { 'BOTTOMLEFT', 'plate', 'TOPLEFT', 0.5, 0.5 })
			assert.equal(anchor[4] * 2 % 1, 0)
			assert.equal(anchor[5] * 2 % 1, 0)
		end)

		it('chooses a nearby name over the distant plate', function()
			local anchor = D.DropAnchor({ left = 22, right = 42, bottom = 95, top = 105 }, { plate = plate, name = { left = -20, right = 20, bottom = 95, top = 105 } }, 'plate')
			assert.same(anchor, { 'LEFT', 'name', 'RIGHT', 2, 0 })
		end)

		it('breaks equal-distance ties by preferred target then plate', function()
			local rect = { left = -10, right = 10, bottom = -2, top = 2 }
			local targets = { plate = plate, name = plate, aaa = plate }
			assert.equal(D.DropAnchor(rect, targets, 'name')[2], 'name')
			assert.equal(D.DropAnchor(rect, targets)[2], 'plate')
			assert.equal(D.DropAnchor(rect, targets, 'missing')[2], 'plate')
		end)
	end)

	describe('snap guides', function()
		it('provides both edges and centers on each axis', function()
			assert.same(D.Guides(plate), { x = { -66, 0, 66 }, y = { -5, 0, 5 } })
		end)

		it('snaps the closest edges within tolerance and returns the guides', function()
			local dx, dy, x, y = D.Snap({ left = 64, right = 84, bottom = 4, top = 14 }, D.Guides(plate), 2)
			assert.same({ dx, dy, x, y }, { 2, 1, 66, 5 })
		end)

		it('returns zero corrections and nil guides outside tolerance', function()
			local dx, dy, x, y = D.Snap({ left = 80, right = 100, bottom = 20, top = 30 }, D.Guides(plate), 2)
			assert.equal(dx, 0)
			assert.equal(dy, 0)
			assert.is_nil(x)
			assert.is_nil(y)
		end)
	end)

	describe('anchor chains', function()
		it('collects the ancestor and its transitive descendants only', function()
			assert.same(D.Descendants(Chain(), 'a'), { a = true, b = true, c = true })
		end)

		it('moves only selected roots while retaining unrelated selections', function()
			assert.same(D.Roots(Chain(), { 'a', 'c' }), { 'a' })
			assert.same(D.Roots(Chain(), { 'c', 'd' }), { 'c', 'd' })
		end)

		it('excludes plate fills, glows and highlights from movable roots', function()
			local parts = Chain()
			parts.a.fill = 'plate'
			parts.b.kind = 'glow'
			parts.c.kind = 'highlight'
			assert.is_false(D.Movable(parts.a))
			assert.is_false(D.Movable(parts.b))
			assert.is_false(D.Movable(parts.c))
			assert.same(D.Roots(parts, { 'a', 'b', 'c', 'd' }), { 'd' })
		end)
	end)

	describe('grid and side picks', function()
		it('keeps a name above while aligning it right', function()
			local anchor = D.GridAnchor(nameAnchor, 'TOPRIGHT')
			assert.same(anchor, { 'BOTTOMRIGHT', 'health', 'TOPRIGHT', 0, 2 })
			assert.equal(D.GridCell(anchor), 'TOPRIGHT')
		end)

		it('keeps health text inside when switching to the left edge', function()
			assert.same(D.GridAnchor(hpAnchor, 'LEFT'), { 'LEFT', 'health', 'LEFT', 2, 0 })
		end)

		it('moves a cast below-left or outside-left as the cell requests', function()
			assert.same(D.GridAnchor(castAnchor, 'BOTTOMLEFT'), { 'TOPLEFT', 'health', 'BOTTOMLEFT', 0, -2 })
			assert.same(D.GridAnchor(castAnchor, 'LEFT'), { 'RIGHT', 'health', 'LEFT', -2, 0 })
		end)

		it('centers without changing any anchor target', function()
			for _, anchor in ipairs({ nameAnchor, hpAnchor, castAnchor, { 'LEFT', 'name', 'RIGHT', 4, 0 } }) do
				assert.same(D.GridAnchor(anchor, 'CENTER'), { 'CENTER', anchor[2], 'CENTER', 0, 0 })
				for _, cell in ipairs({ 'TOPLEFT', 'TOP', 'TOPRIGHT', 'LEFT', 'RIGHT', 'BOTTOMLEFT', 'BOTTOM', 'BOTTOMRIGHT' }) do
					assert.equal(D.GridAnchor(anchor, cell)[2], anchor[2])
				end
			end
		end)

		it('round-trips all sides and grows left and right rows outward', function()
			for _, side in ipairs({ 'above', 'below', 'left', 'right' }) do
				local anchor, grow = D.SideAnchor(nameAnchor, side)
				assert.equal(D.SideOf(anchor), side)
				assert.equal(anchor[2], 'health')
				if side == 'left' then
					assert.equal(grow, 'LEFT')
				elseif side == 'right' then
					assert.equal(grow, 'RIGHT')
				end
			end
		end)
	end)

	describe('resize fields', function()
		it('rounds bar width and height to whole numbers', function()
			assert.same(D.ResizeFields({ kind = 'bar' }, 100.3, 10.74), { width = 100, height = 11 })
		end)

		it('uses the larger icon dimension and clamps at 64', function()
			assert.same(D.ResizeFields({ kind = 'icon' }, 12, 20), { size = 20 })
			assert.same(D.ResizeFields({ kind = 'icon' }, 20, 12), { size = 20 })
			assert.same(D.ResizeFields({ kind = 'icon' }, 100, 90), { size = 64 })
			assert.same(D.ResizeFields({ kind = 'icon' }, 1, 2), { size = 4 })
		end)

		it('takes aura size from the dimension across its growth direction', function()
			assert.same(D.ResizeFields({ kind = 'auras', grow = 'RIGHT' }, 100, 18), { size = 18 })
			assert.same(D.ResizeFields({ kind = 'auras', grow = 'UP' }, 22, 100), { size = 22 })
		end)

		it('sizes text width and font with two pixels of height padding', function()
			assert.same(D.ResizeFields({ kind = 'text' }, 100.74, 16), { width = 101, ['font.size'] = 14 })
			assert.equal(D.ResizeFields({ kind = 'text' }, 100, 1)['font.size'], 6)
			assert.equal(D.ResizeFields({ kind = 'text' }, 100, 100)['font.size'], 40)
		end)

		it('clamps oversized and undersized bar values to schema ranges', function()
			assert.same(D.ResizeFields({ kind = 'bar' }, 1000, 1000), { width = 512, height = 128 })
			assert.same(D.ResizeFields({ kind = 'bar' }, -10, 0), { width = 1, height = 1 })
		end)
	end)

	describe('new parts', function()
		for _, kind in ipairs({ 'bar', 'text', 'icon', 'auras', 'glow', 'highlight', 'region' }) do
			it('creates a valid free ' .. kind .. ' with the next order', function()
				local parts = { existing = { order = 30 }, later = { order = 70 } }
				local id, spec = D.NewPart(kind, parts)
				assert.equal(id, kind .. '1')
				assert.equal(spec.kind, kind)
				assert.equal(spec.order, 71)
				local report = Schema.NewReport()
				assert.not_nil(Schema:CheckPart(spec, 'x', report, false))
				assert.equal(report.dropped, 0)
				assert.equal(report.clamped, 0)
				parts[id] = spec
				local nextId, nextSpec = D.NewPart(kind, parts)
				assert.equal(nextId, kind .. '2')
				assert.equal(nextSpec.order, 72)
			end)
		end

		it('refuses an unknown palette kind', function()
			local id, spec = D.NewPart('unknown', {})
			assert.is_nil(id)
			assert.is_nil(spec)
		end)
	end)

	describe('history', function()
		it('pushes snapshots and exchanges current states on undo and redo', function()
			local history = D.History()
			local first = { styleId = 'clean', tweaks = { value = 1 }, label = 'move' }
			assert.is_true(history:Push(first))
			assert.is_true(history:CanUndo())
			assert.same(history:Last(), first)
			local undone = history:Undo(function(id)
				assert.equal(id, 'clean')
				return { value = 2 }
			end)
			assert.same(undone, first)
			assert.is_false(history:CanUndo())
			assert.is_true(history:CanRedo())
			assert.same(
				history:Redo(function()
					return { value = 1 }
				end),
				{ styleId = 'clean', tweaks = { value = 2 }, label = 'move' }
			)
			assert.same(history:Last().tweaks, { value = 1 })
			assert.is_false(history:CanRedo())
		end)

		it('retains the newest twenty steps and discards the oldest five', function()
			local history = D.History(20)
			for i = 1, 25 do
				history:Push({ styleId = 'clean', tweaks = { value = i } })
			end
			assert.equal(#history.undo, 20)
			assert.equal(history.undo[1].tweaks.value, 6)
			for i = 25, 6, -1 do
				assert.equal(history:Undo(function() end).tweaks.value, i)
			end
			assert.is_nil(history:Undo(function() end))
		end)

		it('coalesces repeated keys but pushes different keys and later times', function()
			local history = D.History()
			assert.is_true(history:Push({ styleId = 'clean', tweaks = { value = 1 }, key = 'x', time = 10 }))
			assert.is_false(history:Push({ styleId = 'clean', tweaks = { value = 2 }, key = 'x', time = 10 + D.COALESCE / 2 }))
			assert.equal(#history.undo, 1)
			assert.equal(history:Last().tweaks.value, 1)
			assert.is_true(history:Push({ styleId = 'clean', key = 'y', time = 10 + D.COALESCE / 2 }))
			assert.is_true(history:Push({ styleId = 'clean', key = 'y', time = 10 + D.COALESCE * 2 }))
			assert.equal(#history.undo, 3)
		end)

		it('clears redo when a new step is pushed', function()
			local history = D.History()
			history:Push({ styleId = 'clean' })
			history:Undo(function() end)
			assert.is_true(history:CanRedo())
			history:Push({ styleId = 'clean', label = 'edit' })
			assert.is_false(history:CanRedo())
		end)

		it('drops only the top step', function()
			local history = D.History()
			history:Push({ styleId = 'clean', label = 'first' })
			history:Push({ styleId = 'clean', label = 'second' })
			history:Drop()
			assert.equal(#history.undo, 1)
			assert.equal(history:Last().label, 'first')
		end)
	end)

	describe('store edits', function()
		it('nudges sparsely, coalesces repeats, and restores undo and redo', function()
			D:Select('name')
			D:NudgeParts({ 'name' }, 0.5, 0)
			assert.same(Change('name', 'anchor'), { 'BOTTOMLEFT', 'health', 'TOPLEFT', 0.5, 2 })
			M.Advance(D.COALESCE / 2)
			D:NudgeParts({ 'name' }, 0.5, 0)
			assert.equal(Change('name', 'anchor')[4], 1)
			assert.equal(#D.history.undo, 1)
			assert.is_true(D:Undo())
			assert.is_nil(P.Store:Get({ 'tweaks', 'clean' }))
			assert.is_true(D:Redo())
			assert.same(Change('name', 'anchor'), { 'BOTTOMLEFT', 'health', 'TOPLEFT', 1, 2 })
		end)

		it('stores hidden true and removes a return to the base visibility', function()
			D:SetHidden('hp', true)
			assert.is_true(Change('hp', 'hidden'))
			D:SetHidden('hp', false)
			assert.is_nil(Change('hp', 'hidden'))
			assert.is_nil(P.Store:Get('tweaks.clean'))
		end)

		it('writes only the preview kind and resets its scoped part', function()
			D:SetScope('kind')
			D:SetPreviewKind('friendlyPlayer')
			D:Change('name', 'font.size', 14)
			assert.equal(P.Store:Get('tweaks.clean.situations.friendlyPlayer.parts.name.font.size'), 14)
			assert.is_nil(P.Store:Get('tweaks.clean.changes'))
			assert.same(D:ScopedKinds('name'), { 'friendlyPlayer' })
			D:ResetPart('name', 'friendlyPlayer')
			assert.is_nil(P.Store:Get('tweaks.clean'))
			assert.same(D:ScopedKinds('name'), {})
		end)

		it('adds and selects a text part that resolves into the clean style', function()
			assert.equal(D:AddPart('text'), 'text1')
			assert.equal(P.Store:Get('tweaks.clean.add.text1.kind'), 'text')
			assert.equal(D:Primary(), 'text1')
			assert.not_nil(P.Styles.Merge:Resolve('clean', 'enemyNPC', 'medium').parts.text1)
		end)

		it('removes an added part and hands its anchor to dependent parts', function()
			D:AddPart('text')
			D:SetField('hp', 'anchor', { 'CENTER', 'text1', 'CENTER', 1, 1 }, false)
			D:RemovePart('text1')
			assert.is_nil(P.Store:Get('tweaks.clean.add.text1'))
			assert.same(Change('hp', 'anchor'), { 'CENTER', 'plate', 'CENTER', 1, 1 })
			assert.is_nil(D:Primary())
			assert.is_nil(P.Styles.Merge:Resolve('clean', 'enemyNPC', 'medium').parts.text1)
		end)

		it('hides a built-in part when removal is requested', function()
			D:RemovePart('quest')
			assert.is_true(Change('quest', 'hidden'))
			assert.is_nil(P.Store:Get('tweaks.clean.remove'))
		end)

		it('stores the requested relative grid cell for an aura row', function()
			D:SetGridCell('cc', 'BOTTOM')
			assert.equal(Change('cc', 'anchor')[3], 'BOTTOM')
		end)

		it('switches the cast icon off and removes the base-valued override on enable', function()
			D:SetSubRow('cast', 'icon', false)
			assert.equal(Change('cast', 'icon'), 'none')
			D:SetSubRow('cast', 'icon', true)
			assert.is_nil(Change('cast', 'icon'))
		end)

		it('leaves no undo step when an edit changes nothing', function()
			D:Change('hp', 'font.size', D:Value('hp', 'font.size'))
			assert.is_false(D:CanUndo())
			assert.is_nil(P.Store:Get('tweaks.clean'))
		end)

		it('handles undo, redo and deletion of every selected part only', function()
			D:Select('name')
			D:Select('hp', true)
			D:NudgeParts({ 'name' }, 0.5, 0)
			assert.is_true(D:HandleKey('CTRL-Z'))
			assert.is_nil(Change('name', 'anchor'))
			assert.is_true(D:HandleKey('CTRL-Y'))
			assert.equal(Change('name', 'anchor')[4], 0.5)
			assert.is_true(D:HandleKey('DELETE'))
			assert.is_true(Change('name', 'hidden'))
			assert.is_true(Change('hp', 'hidden'))
			assert.is_nil(Change('quest', 'hidden'))
			assert.is_false(D:HandleKey('OTHER'))
		end)

		it('adds and toggles parts in the ordered selection', function()
			D:Select('name')
			D:Select('hp', true)
			assert.same(D:Selected(), { 'name', 'hp' })
			assert.equal(D:Primary(), 'name')
			D:Select('hp', true)
			assert.same(D:Selected(), { 'name' })
		end)

		it('recognizes Customize and rejects the style page path', function()
			assert.is_true(D:IsCustomizePath(P.Options.Path('customize')))
			assert.is_false(D:IsCustomizePath(P.Options.Path('style')))
		end)

		it('shows the palette and exposes undo and redo only with history', function()
			assert.is_nil(D:Footer())
			local items = D:ToolbarItems()
			assert.equal(#items, 1)
			assert.equal(items[1].kind, 'select')
			assert.is_true(rawequal(items[1].choices, D.PALETTE))
			D:NudgeParts({ 'name' }, 0.5, 0)
			assert.equal(D:Footer().text, 'Undo move')
			assert.equal(#D:ToolbarItems(), 1)
			D:Undo()
			items = D:ToolbarItems()
			assert.equal(#items, 2)
			assert.equal(items[2].kind, 'button')
			assert.equal(items[2].text, 'Redo')
			items[2].onClick()
			assert.equal(#D:ToolbarItems(), 1)
		end)

		it('clears undo, redo and selection on a profile change', function()
			D:Select('name')
			D:NudgeParts({ 'name' }, 0.5, 0)
			D:Undo()
			D:NudgeParts({ 'name' }, 1, 0)
			D:Change('hp', 'font.size', 11)
			D:Undo()
			assert.is_true(D:CanUndo())
			assert.is_true(D:CanRedo())
			assert.not_nil(D:Primary())
			P:Fire('PROFILE_CHANGED', {})
			assert.is_false(D:CanUndo())
			assert.is_false(D:CanRedo())
			assert.same(D:Selected(), {})
		end)
	end)
end)

describe('designer: the preview panel', function()
	before_each(Reset)

	local function Attached()
		local plate = P.Plate.New(UIParent, true)
		plate:ApplyStyle(P.Styles.Merge:Resolve('clean', 'enemyNPC', 'medium'))
		plate:BindSample(P.Source.NewSample('casterTarget'))
		local ctx = { canvas = UIParent, regions = {}, byPart = {} }
		ctx.Region = function(frame, target)
			ctx.regions[#ctx.regions + 1] = { frame = frame, target = target }
			if target.partId then
				ctx.byPart[target.partId] = target
			end
		end
		D:Attach(ctx, plate)
		return ctx, plate
	end

	it('registers one region per shown part, large parts first, outlining only the selection', function()
		D:Select('name')
		local ctx = Attached()
		assert.not_nil(ctx.byPart.health, 'health has a region')
		assert.not_nil(ctx.byPart.name, 'name has a region')
		assert.is_true(ctx.byPart.name.selected)
		assert.is_false(ctx.byPart.health.selected)
		local healthIndex, nameIndex
		for i, region in ipairs(ctx.regions) do
			if region.target.partId == 'health' then
				healthIndex = i
			elseif region.target.partId == 'name' then
				nameIndex = i
			end
		end
		assert.truthy(healthIndex < nameIndex, 'the bar is registered before the name above it')
		assert.is_nil(ctx.byPart.health.drag, 'a bar that fills the plate does not move')
		assert.not_nil(ctx.byPart.name.drag, 'the name moves')
		assert.same(ctx.byPart.name.path, P.Options.Path('customize'))
		assert.equal(ctx.byPart.name.option, 'part_name')
	end)

	it('selects on click, adds with Shift, and gives a resize handle to one selected part', function()
		local ctx = Attached()
		ctx.byPart.hp.onClick(ctx.byPart.hp)
		assert.equal(D:Primary(), 'hp')
		ctx = Attached()
		local handle = ctx.regions[#ctx.regions].target
		assert.equal(handle.label, 'Resize')
		assert.is_true(handle.selected)
		local shift = IsShiftKeyDown
		IsShiftKeyDown = function()
			return true
		end
		ctx.byPart.name.onClick(ctx.byPart.name)
		IsShiftKeyDown = shift
		assert.same(D:Selected(), { 'hp', 'name' })
		ctx = Attached()
		assert.not_equal(ctx.regions[#ctx.regions].target.label, 'Resize', 'no handle while several parts are picked')
	end)

	it('drags a part, snaps to the plate center, and writes one anchor on drop', function()
		D:Select('marker')
		local ctx = Attached()
		local drag = ctx.byPart.marker.drag
		drag.Start(ctx.byPart.marker)
		drag.Move(5, 30, ctx.byPart.marker)
		assert.is_nil(P.Store:Get({ 'tweaks', 'clean' }), 'nothing is written while it moves')
		drag.Move(10, 40, ctx.byPart.marker)
		drag.Stop(10, 40, ctx.byPart.marker)
		local anchor = Change('marker', 'anchor')
		assert.not_nil(anchor, 'the drop writes an anchor')
		assert.equal(anchor[4] * 2, math.floor(anchor[4] * 2), 'x is a half pixel')
		assert.equal(anchor[5] * 2, math.floor(anchor[5] * 2), 'y is a half pixel')
		assert.equal(D:Footer().text, 'Undo move')
		assert.is_true(D:Undo())
		assert.is_nil(P.Store:Get({ 'tweaks', 'clean' }))
	end)

	it('a drag that goes nowhere writes nothing and leaves no undo step', function()
		D:Select('marker')
		local ctx = Attached()
		local drag = ctx.byPart.marker.drag
		drag.Start(ctx.byPart.marker)
		drag.Move(0.1, 0, ctx.byPart.marker)
		drag.Stop(0.1, 0, ctx.byPart.marker)
		assert.is_nil(P.Store:Get({ 'tweaks', 'clean' }))
		assert.is_false(D:CanUndo())
	end)

	it('moves several picked parts together and keeps followers on their leader', function()
		D:Select('name')
		D:Select('mine', true)
		D:Select('marker', true)
		local ctx = Attached()
		local drag = ctx.byPart.name.drag
		drag.Start(ctx.byPart.name)
		drag.Move(0, 20, ctx.byPart.name)
		drag.Stop(0, 20, ctx.byPart.name)
		assert.not_nil(Change('name', 'anchor'))
		assert.not_nil(Change('marker', 'anchor'))
		assert.is_nil(Change('mine', 'anchor'), 'the row above the name follows it')
		assert.equal(#D.history.undo, 1, 'one undo step for the whole move')
	end)

	it('resizes the picked part through its handle', function()
		D:Select('marker')
		local ctx = Attached()
		local handle = ctx.regions[#ctx.regions].target
		assert.equal(handle.label, 'Resize')
		handle.drag.Start(handle)
		handle.drag.Move(8, -8, handle)
		handle.drag.Stop(8, -8, handle)
		assert.equal(Change('marker', 'size'), 24)
	end)

	it('nudges and handles keys through any picked part', function()
		D:Select('quest')
		local ctx = Attached()
		local drag = ctx.byPart.quest.drag
		drag.Nudge(2, 0, ctx.byPart.quest)
		assert.equal(Change('quest', 'anchor')[4], 2)
		assert.is_true(drag.Key('CTRL-Z', ctx.byPart.quest))
		assert.is_nil(Change('quest', 'anchor'))
		assert.is_true(drag.Key('CTRL-Y', ctx.byPart.quest))
		assert.equal(Change('quest', 'anchor')[4], 2)
		assert.is_true(drag.Key('DELETE', ctx.byPart.quest))
		assert.is_true(Change('quest', 'hidden'))
		assert.is_false(drag.Key('A', ctx.byPart.quest))
	end)

	it('names the picked part in the panel title and explains parts in tooltips', function()
		assert.is_nil(D:Title())
		D:Select('name')
		assert.equal(D:Title(), 'Text: Name')
		D:Select('hp', true)
		assert.matches(D:Title(), 'Name and 1 more')
		local ctx = Attached()
		local detail = ctx.byPart.health.detail(ctx.byPart.health)
		assert.truthy(detail == nil or type(detail) == 'string')
		D:Detach()
	end)
end)
