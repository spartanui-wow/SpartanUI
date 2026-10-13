-- @runtime lua51
-- The options preview panel (plan 3.2, 3.7, 5.6): every scene renders real preview plates from
-- sample sources on every flavor, the provider registers a click area per part (large parts first)
-- with labels and inspector detail lines, the toolbar offers "Preview as", Enlarge and the scene
-- picker, the eye toggle shows every part and the areas, Customize selects and moves parts, and
-- the inspector explains colors (exact in previews, "One of:" for rows the game decides).
local M, H = ...

if not H.ModuleExists() then
	describe('preview', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

M.Login('NameplatesTestHost')
local P = H.FreshCore()
local Scenes = P.Scenes
local Preview = P.Preview
local Inspector = P.Inspector
local Options = P.Options

local canvas = CreateFrame('Frame', nil, UIParent)
canvas:SetSize(338, 560)
canvas:Show()

local function Path(page)
	return Options.Path(page)
end

---A Stage context like the host's: records every click area.
local function Ctx(page, opts)
	opts = opts or {}
	local ctx = { path = Path(page), canvas = canvas, width = opts.width or 340, maxWidth = opts.maxWidth or 900, regions = {} }
	ctx.Region = function(frame, target)
		ctx.regions[#ctx.regions + 1] = { frame = frame, target = target }
	end
	return ctx
end

local function FindRegion(ctx, label)
	for _, entry in ipairs(ctx.regions) do
		if entry.target.label == label then
			return entry
		end
	end
	return nil
end

local provider = P:BuildPreviewProvider()

local function Render(page, opts)
	local ctx = Ctx(page, opts)
	provider:Render(ctx)
	return ctx
end

describe('preview: scenes', function()
	after_each(function()
		Scenes:Release(canvas)
		P.Regions:SetShowAll(false)
	end)

	it('renders every scene with sample plates', function()
		for id in pairs(Scenes.DEFS) do
			local result = Scenes:Render(canvas, id, { width = 338, height = 560, kind = 'enemyNPC', piece = 'health' })
			assert.equal(id, result.id)
			assert.truthy(#result.items > 0, id .. ' draws something')
			for _, plate in ipairs(result.plates) do
				assert.is_true(plate.isPreview, id .. ': preview plate')
				assert.is_true(plate.src and plate.src.isSample, id .. ': sample source')
				assert.is_nil(plate.events, id .. ': previews never register events')
				assert.not_nil(plate.style, id .. ': laid out')
			end
		end
	end)

	it('fits the Pull column into the smallest canvas', function()
		local result = Scenes:Render(canvas, 'pull', { width = 338, height = 416 })
		assert.equal(5, #result.items)
		assert.truthy(result.height <= 416, 'column fits: ' .. tostring(result.height))
		assert.truthy(result.scale >= 0.5, 'scale ' .. tostring(result.scale))
	end)

	it('shows every kind on Who and where, hidden kinds as an outline', function()
		local result = Scenes:Render(canvas, 'kinds', { width = 338, height = 560 })
		assert.equal(#Scenes.KINDS, #result.items)
		local hidden = 0
		for _, item in ipairs(result.items) do
			if item.mode == 'hidden' then
				hidden = hidden + 1
				assert.is_nil(item.plate)
				assert.not_nil(item.outline)
			else
				assert.not_nil(item.plate, item.kind .. ' has a plate')
			end
		end
		-- Friendly NPCs are hidden by default
		assert.truthy(hidden >= 1)
	end)

	it('draws one plate per color row, each showing its row', function()
		local result = Scenes:Render(canvas, 'rows', { width = 338, height = 900, piece = 'health' })
		local program = P.Colors:Program('health', result.context)
		assert.equal(#program.rows, #result.items + result.more)
		local wins = 0
		for _, item in ipairs(result.items) do
			if item.rowWins then
				wins = wins + 1
				local winner = P.Colors:Explain(program, item.plate.env)
				assert.equal(item.row, winner, 'row ' .. item.row.id .. ' decides its own plate')
			end
		end
		assert.truthy(wins > 0)
	end)

	it('shrinks a long color list, then says how many are left', function()
		local result = Scenes:Render(canvas, 'rows', { width = 338, height = 120, piece = 'health' })
		assert.truthy(result.scale >= Scenes.MIN_ROW_SCALE)
		assert.truthy(result.more > 0, 'rows left out')
	end)

	it('draws the Customize plate large with the other states below', function()
		local result = Scenes:Render(canvas, 'focus', { width = 338, height = 560, kind = 'enemyNPC' })
		assert.equal(3, #result.items)
		assert.truthy(result.items[1].scale > 1, 'large plate')
		assert.equal(1, result.items[2].scale)
		assert.is_true(result.items[2].fade)
		assert.is_true(result.items[1].plate.states.target == true)
		for _, kind in ipairs(Scenes.KINDS) do
			local other = Scenes:Render(canvas, 'focus', { width = 338, height = 560, kind = kind })
			assert.equal(kind, other.items[1].situation)
		end
	end)

	it('fills every aura row with sample icons on the Auras page', function()
		local result = Scenes:Render(canvas, 'auras', { width = 338, height = 560, kind = 'enemyNPC' })
		local sample = result.items[1].sample
		for _, row in ipairs({ 'myDebuffs', 'removable', 'crowdControl', 'custom' }) do
			assert.truthy(sample.auras[row] and #sample.auras[row] > 0, row)
		end
	end)

	it('reveals hidden parts while Show all parts is on', function()
		local result = Scenes:Render(canvas, 'pull', { width = 338, height = 560, revealAll = true })
		for _, item in ipairs(result.items) do
			assert.truthy(item.sample.raidMarker, 'marker')
			assert.is_true(item.sample.quest)
		end
	end)

	it('draws a hovered gallery style', function()
		local result = Scenes:Render(canvas, 'pull', { width = 338, height = 560, styleId = 'mini' })
		for _, item in ipairs(result.items) do
			if item.mode == 'full' and item.plate then
				assert.equal('mini', item.plate.style.id)
			end
		end
	end)

	it('stops sample casts when released', function()
		local result = Scenes:Render(canvas, 'pull', { width = 338, height = 560 })
		Scenes:Release(canvas)
		for _, plate in ipairs(result.plates) do
			assert.is_nil(plate.src)
		end
	end)
end)

describe('preview: provider', function()
	after_each(function()
		provider:Hide()
		P.Regions:SetShowAll(false)
		Preview:Select(nil)
		Preview.selected = nil
		Preview.enlarge = false
		Preview.scene = 'pull'
		Preview:SetPreviewAs('enemyNPC')
	end)

	it('is built for the nameplate root and asks for the panel', function()
		assert.not_nil(provider)
		assert.same(Path(), provider.path)
		assert.is_true(provider.zoomable)
		assert.is_true(provider.refit)
		assert.is_true(provider.overlapPicker)
		assert.truthy(provider:GetHeight(Ctx('style')) > 0)
	end)

	it('registers a labeled click area for parts on every page', function()
		for _, page in ipairs({ 'style', 'customize', 'colors', 'auras', 'whoAndWhere', 'sharing' }) do
			local ctx = Render(page)
			assert.truthy(#ctx.regions > 0, page .. ' registers click areas')
			for _, entry in ipairs(ctx.regions) do
				assert.truthy(type(entry.target.label) == 'string' and entry.target.label ~= '', page .. ': labeled')
				assert.truthy(entry.target.path or entry.target.onClick, page .. ': goes somewhere')
				assert.not_nil(entry.target.selected, page .. ': selection is explicit')
			end
		end
		local root = Ctx(nil)
		provider:Render(root)
		assert.truthy(#root.regions > 0, 'the root page shows the Pull scene')
	end)

	it('registers large parts before small ones', function()
		local ctx = Render('style')
		local health = FindRegion(ctx, 'Health bar')
		local marker = FindRegion(ctx, 'Raid marker')
		assert.not_nil(health)
		local healthAt, markerAt
		for i, entry in ipairs(ctx.regions) do
			if entry == health and not healthAt then
				healthAt = i
			end
			if entry == marker and not markerAt then
				markerAt = i
			end
		end
		if markerAt then
			assert.truthy(healthAt < markerAt, 'health bar first')
		end
	end)

	it('explains the health color in the hover line', function()
		local ctx = Render('style')
		local health = FindRegion(ctx, 'Health bar')
		local detail = health.target.detail(health.target)
		assert.truthy(type(detail) == 'string' and detail ~= '')
		assert.falsy(detail:find(P.L['One of:'], 1, true), 'previews are exact: ' .. detail)
	end)

	it('labels aura rows as sample icons', function()
		local ctx = Render('auras')
		local found = false
		for _, entry in ipairs(ctx.regions) do
			if entry.target.label:find(Scenes.LABEL_SAMPLE_ICONS, 1, true) then
				found = true
				assert.same(Path('auras'), entry.target.path)
			end
		end
		assert.is_true(found)
	end)

	it('offers Preview as and Enlarge on Customize', function()
		local items = provider:Toolbar(Ctx('customize'))
		-- Ours first; the Designer may add its own after them
		assert.truthy(#items >= 2)
		assert.equal('select', items[1].kind)
		assert.equal(5, #items[1].choices)
		items[1].onSelect('friendlyPlayer')
		assert.equal('friendlyPlayer', Preview:GetPreviewAs())
		assert.equal('toggle', items[2].kind)
		assert.falsy(items[2].disabled)
		items[2].onClick()
		assert.equal(560, provider.width(provider, Ctx('customize', { maxWidth = 900 })))
		assert.equal(450, provider.width(provider, Ctx('customize', { maxWidth = 450 })))
		assert.is_nil(provider.width(provider, Ctx('style', { maxWidth = 900 })), 'only Customize is wide')
		local tight = provider:Toolbar(Ctx('customize', { maxWidth = 340 }))
		assert.is_true(tight[2].disabled)
		assert.truthy(tight[2].disabledReason)
		assert.is_nil(provider.width(provider, Ctx('customize', { maxWidth = 340 })))
	end)

	it('offers the scene picker where the Pull scene shows', function()
		for _, page in ipairs({ 'style', 'sharing', 'colors' }) do
			local items = provider:Toolbar(Ctx(page))
			assert.not_nil(items, page)
			assert.equal(#Scenes.PICKER, #items[1].choices)
		end
		assert.is_nil(provider:Toolbar(Ctx('whoAndWhere')))
		local items = provider:Toolbar(Ctx('style'))
		items[1].onSelect('battleground')
		assert.equal('battleground', Preview.scene)
		local ctx = Render('style')
		assert.equal('battleground', Preview.lastScene.id)
		assert.truthy(#ctx.regions > 0)
	end)

	it('shows the rows scene while a color list is open', function()
		Preview:SetColorList('health')
		Render('colors')
		assert.equal('rows', Preview.lastScene.id)
		assert.is_nil(provider:Toolbar(Ctx('colors')))
		Preview:SetColorList(nil)
		local ctx = Ctx('colors')
		ctx.path = { 'Nameplates', 'colors', 'border' }
		provider:Render(ctx)
		assert.equal('rows', Preview.lastScene.id, 'found from the path')
	end)

	it('toggles Show all parts and draws the areas', function()
		local action = provider:Action(Ctx('style'))
		assert.is_false(action.active)
		action.func()
		assert.is_true(P.Regions:IsShowingAll())
		assert.is_true(provider:Action(Ctx('style')).active)
		local ctx = Render('style')
		assert.not_nil(FindRegion(ctx, P.Regions.LABELS.click), 'click area box')
		assert.not_nil(FindRegion(ctx, P.Regions.LABELS.stack), 'stacking area box')
		action.func()
		assert.is_false(P.Regions:IsShowingAll())
	end)

	it('selects a part on Customize and moves it', function()
		local ctx = Render('customize')
		assert.not_nil(provider:Hint(ctx))
		local designerOwns = type(P.Designer.Attach) == 'function'
		-- The large plate's areas: the Designer's when it attaches, else the provider's own
		local function Movable(c)
			for _, entry in ipairs(c.regions) do
				local target = entry.target
				if target.onClick and not target.path and target.partId then
					return entry
				end
				if target.onClick and target.path and FindRegion(c, 'Name') == entry then
					return entry
				end
			end
			return nil
		end
		local name = Movable(ctx)
		assert.not_nil(name, 'a part on the large plate')
		assert.is_false(name.target.selected)
		name.target.onClick(name.target)
		local selectedId = Preview:GetSelected()
		assert.not_nil(selectedId)
		ctx = Render('customize')
		local again
		for _, entry in ipairs(ctx.regions) do
			if entry.target.selected then
				again = entry
			end
		end
		assert.not_nil(again, 'the picked part is outlined')
		assert.not_nil(again.target.drag, 'the selected part can be dragged')
		local title = provider:Title(ctx)
		assert.truthy(type(title) == 'string' and title ~= '')
		if designerOwns then
			return
		end
		local drag = again.target.drag
		local styleId = Preview:EditStyleId()
		local path = { 'tweaks', styleId, 'changes', 'parts', selectedId, 'anchor' }
		drag.Start(again.target)
		drag.Move(6, 3, again.target)
		drag.Stop(6, 3, again.target)
		local anchor = P.Store:Get(path)
		assert.not_nil(anchor, 'the drop wrote an anchor')
		assert.truthy(provider:Footer(Ctx('customize')), 'Undo move')
		drag.Nudge(0.5, 0, again.target)
		local nudged = P.Store:Get(path)
		assert.near(anchor[4] + 0.5, nudged[4], 0.001)
		Preview:Undo()
		assert.near(anchor[4], P.Store:Get(path)[4], 0.001)
		P.Store:Set({ 'tweaks', styleId }, nil)
	end)

	it('moves a part with the plain drag', function()
		Render('customize')
		local plate = Preview.lastScene.items[1].plate
		local widget = plate:GetWidget('name')
		assert.not_nil(widget, 'the name part')
		local drag = Preview.FallbackDrag(plate, widget, plate.style)
		local styleId = plate.style.id
		local path = { 'tweaks', styleId, 'changes', 'parts', 'name', 'anchor' }
		drag.Start()
		drag.Move(6, 3)
		drag.Stop(6, 3)
		local anchor = P.Store:Get(path)
		assert.not_nil(anchor, 'the drop wrote an anchor')
		assert.truthy(Preview:CanUndo())
		drag.Nudge(0.5, 0)
		assert.near(anchor[4] + 0.5, P.Store:Get(path)[4], 0.001)
		Preview:Undo()
		assert.near(anchor[4], P.Store:Get(path)[4], 0.001)
		assert.is_true(drag.Key('CTRL-Z'))
		assert.is_false(drag.Key('F1'))
		P.Store:Set({ 'tweaks', styleId }, nil)
	end)

	it('opens the part on Customize from other pages', function()
		local ctx = Render('style')
		local cast = FindRegion(ctx, 'Cast bar')
		assert.not_nil(cast)
		assert.same(Path('customize'), cast.target.path)
		cast.target.onClick(cast.target)
		assert.not_nil(Preview:GetSelected())
	end)

	it('sends Who and where clicks to the kind', function()
		local ctx = Render('whoAndWhere')
		for _, entry in ipairs(ctx.regions) do
			assert.same(Path('whoAndWhere'), entry.target.path)
		end
	end)

	it('lets go of its plates when hidden and when the window closes', function()
		Render('style')
		local plates = Preview.lastScene.plates
		provider:Close()
		for _, plate in ipairs(plates) do
			assert.is_nil(plate.src)
		end
	end)
end)

describe('preview: inspector', function()
	after_each(function()
		Scenes:Release(canvas)
	end)

	it('names colors in plain words', function()
		assert.equal(P.L['Red'], Inspector.ColorName(1, 0, 0))
		assert.equal(P.L['Gray'], Inspector.ColorName(0.5, 0.5, 0.5))
		assert.equal(P.L['Blue'], Inspector.ColorName(0.25, 0.55, 1))
		assert.equal(P.L['Green'], Inspector.ColorName(0.3, 0.85, 0.35))
		assert.equal(P.L['White'], Inspector.ColorName(1, 1, 1))
	end)

	it('is exact for every preview plate', function()
		local result = Scenes:Render(canvas, 'pull', { width = 338, height = 560 })
		for _, plate in ipairs(result.plates) do
			for _, piece in ipairs({ 'health', 'border', 'name', 'cast' }) do
				local line = Inspector:Explain(plate, piece)
				assert.truthy(type(line) == 'string' and line ~= '')
				assert.falsy(line:find(P.L['One of:'], 1, true), piece .. ': ' .. line)
			end
		end
	end)

	it('names the threat state on a threat color', function()
		local result = Scenes:Render(canvas, 'rows', { width = 338, height = 900, piece = 'health' })
		for _, item in ipairs(result.items) do
			if item.rowWins and item.row.id == 'threat' then
				local line = Inspector:Explain(item.plate, 'health')
				assert.truthy(line:find('(', 1, true), line)
			end
		end
	end)

	it('says "One of:" when the game decides', function()
		local result = Scenes:Render(canvas, 'pull', { width = 338, height = 560 })
		local plate = result.plates[1]
		local original = P.Colors.Explain
		P.Colors.Explain = function(_, program)
			return program.rows[#program.rows], { program.rows[1] }
		end
		local ok, line = pcall(Inspector.Explain, Inspector, plate, 'health')
		P.Colors.Explain = original
		assert.is_true(ok, tostring(line))
		assert.truthy(line:find(P.L['One of:'], 1, true), line)
	end)

	it('shows the Alt tooltip for the plate under the mouse', function()
		local result = Scenes:Render(canvas, 'pull', { width = 338, height = 560 })
		local plate = result.plates[1]
		local lines = Inspector:Lines(plate)
		assert.truthy(#lines >= 2, 'health and name at least')
		local added = {}
		M.Override(GameTooltip, 'SetOwner', function() end)
		M.Override(GameTooltip, 'AddLine', function(_, text)
			added[#added + 1] = text
		end)
		local original = Inspector.MouseoverPlate
		Inspector.MouseoverPlate = function()
			return plate
		end
		Inspector:WatchWorld(true)
		M.Fire('MODIFIER_STATE_CHANGED', 'LALT', 1)
		assert.is_true(Inspector.tipShown)
		assert.truthy(#added >= #lines)
		M.Fire('MODIFIER_STATE_CHANGED', 'LALT', 0)
		assert.is_false(Inspector.tipShown)
		Inspector:WatchWorld(false)
		Inspector.MouseoverPlate = original
		M.Fire('MODIFIER_STATE_CHANGED', 'LALT', 1)
		assert.is_false(Inspector.tipShown, 'nothing listens once the engine is off')
	end)
end)
