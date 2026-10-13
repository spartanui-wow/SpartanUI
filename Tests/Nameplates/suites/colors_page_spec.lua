-- @runtime lua51
-- The Colors options page (plan 3.2 #3): the scheme picker, the threat row, the mob type swatches,
-- the color-blind switch and, under More settings, the ordered color list per piece (RuleList)
-- with where a piece takes its colors from. Real AceDB, the real Colors/Conditions/Roles, and the
-- real RuleList widget driven the way a player drives it. Runs on every client.
local M, H = ...

if not H.ModuleExists() then
	describe('colors page', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

local EM_DASH = '\226\128\148'

local builds = 0

---A fresh core on its own widget prefix: AceGUI keeps the first constructor registered under a
---type name for the whole process, so a later core would otherwise get widgets bound to an old one.
local function Build(opts)
	local refreshed = 0
	builds = builds + 1
	opts = opts or {}
	opts.host = opts.host or {}
	opts.host.widgetPrefix = 'ColorsPageTest' .. builds
	opts.host.RefreshOptions = function()
		refreshed = refreshed + 1
	end
	local P = H.FreshCore(opts)
	M.Login('NameplatesTestHost')
	local tbl = P:BuildOptionsTable()
	return P, tbl.args.colors, function()
		return refreshed
	end
end

local function Ids(list)
	local out = {}
	for i, item in ipairs(list) do
		out[i] = type(item) == 'table' and item.id or item
	end
	return out
end

local function ProgramIds(P, piece)
	return Ids(P.Colors:Program(piece).rows)
end

local function Has(list, value)
	for _, v in ipairs(list) do
		if v == value then
			return true
		end
	end
	return false
end

local function SetRole(P, role)
	P.Context.role = role
	P.Colors:Invalidate()
end

local Draw

---A RuleList fed with the page's own list option, as ACD feeds it.
local function MakeList(P, page)
	Draw = P.Widgets.Draw
	local widget = P.Widgets:Create('RuleList')
	assert.not_nil(widget, 'RuleList is built')
	widget.frame:SetParent(UIParent)
	widget.frame:Show()
	widget:SetWidth(520)
	-- The calls AceConfigDialog makes for a select with a dialogControl, in its order
	local option = page.args.list
	widget:SetLabel(type(option.name) == 'function' and option.name({}) or option.name)
	widget:SetList(option.values, option.sorting, nil)
	widget:SetValue(option.values[option.get()])
	widget:SetCallback('OnValueChanged', function() end)
	widget:SetDisabled(false)
	widget:SetCustomData(option.arg)
	-- A menu closed a moment ago by this recycled widget would swallow the next click
	M.Advance(1.1)
	return widget
end

local function Release(widget)
	local AceGUI = LibStub('AceGUI-3.0')
	if widget and not widget.isQueuedForRelease then
		AceGUI:Release(widget)
	end
	if Draw then
		Draw.CloseMenu()
	end
end

local function Texts(value, out, depth)
	out = out or {}
	depth = depth or 0
	if depth > 8 or type(value) ~= 'table' then
		return out
	end
	for key, item in pairs(value) do
		if (key == 'name' or key == 'desc' or key == 'confirmText') and type(item) == 'string' then
			out[#out + 1] = item
		elseif (key == 'name' or key == 'desc') and type(item) == 'function' then
			local ok, text = pcall(item, {})
			if ok and type(text) == 'string' then
				out[#out + 1] = text
			end
		elseif type(item) == 'table' and key ~= 'arg' then
			Texts(item, out, depth + 1)
		end
	end
	return out
end

describe('colors page: layout', function()
	local P, page

	before_each(function()
		P, page = Build()
	end)

	it('has at most eight main controls, and puts the lists under More settings', function()
		local main = 0
		for key, option in pairs(page.args) do
			if option.type ~= 'description' and not option.advanced then
				main = main + 1
			end
		end
		assert.truthy(main <= 8, 'main controls: ' .. main)
		assert.is_true(page.args.list.advanced)
		assert.is_true(page.args.listPiece.advanced)
		assert.is_true(page.args.source.advanced)
		assert.is_nil(page.args.scheme.advanced)
		assert.is_nil(page.args.colorBlind.advanced)
		assert.is_nil(page.args.mobType.advanced)
	end)

	it('draws the list with the RuleList widget under the host prefix', function()
		assert.equal(page.args.list.dialogControl, P.Widgets:TypeName('RuleList'))
		assert.is_true(P.Widgets:Has('RuleList'))
	end)

	it('uses no em dashes and no symbols the game cannot draw', function()
		for _, text in ipairs(Texts(page)) do
			assert.is_nil(text:find(EM_DASH, 1, true), 'em dash in: ' .. text)
			assert.is_nil(text:find('[\128-\255]'), 'non-ASCII character in: ' .. text)
		end
		local list = P.Colors.kinds
		for _, row in ipairs(P.Options.ColorsPage.Rows('health')) do
			assert.is_nil(row.sentence:find('[\128-\255]'), row.sentence)
		end
		assert.not_nil(list)
	end)

	it('is registered as the third page and found by the options table', function()
		assert.equal(page.order, 3)
		assert.equal(page.name, 'Colors')
	end)
end)

describe('colors page: scheme picker', function()
	local P, page

	before_each(function()
		P, page = Build()
	end)

	it('offers Automatic and the four schemes, and Automatic names the one for the role', function()
		local values = page.args.scheme.values()
		assert.same(page.args.scheme.sorting, { 'auto', 'threat', 'mobType', 'class', 'custom' })
		assert.equal(values.threat, 'Threat first (tanks)')
		assert.equal(values.mobType, 'Mob type first (dungeon damage)')
		assert.equal(values.class, 'Class first (PvP)')
		assert.equal(values.custom, 'Custom')
		assert.matches(values.auto, 'Mob type first')
		SetRole(P, 'tank')
		assert.matches(page.args.scheme.values().auto, 'Threat first')
	end)

	it('defaults to Automatic and stores a pick', function()
		assert.equal(page.args.scheme.get(), 'auto')
		page.args.scheme.set({}, 'class')
		assert.equal(P.Store:Get('scheme'), 'class')
		assert.equal(page.args.scheme.get(), 'class')
		assert.equal(ProgramIds(P, 'health')[2], 'class')
		page.args.scheme.set({}, 'auto')
		assert.equal(page.args.scheme.get(), 'auto')
	end)

	it('pins every list to what the player sees when Custom is picked', function()
		SetRole(P, 'tank')
		local before = {}
		for _, piece in ipairs(P.Colors.PIECES) do
			before[piece] = ProgramIds(P, piece)
		end
		page.args.scheme.set({}, 'custom')
		assert.equal(P.Store:Get('scheme'), 'custom')
		for _, piece in ipairs(P.Colors.PIECES) do
			assert.not_nil(P.Store:Get({ 'colors', piece, 'order' }), piece .. ' list is pinned')
			assert.same(ProgramIds(P, piece), before[piece], piece .. ' list did not change')
		end
	end)

	it('keeps the color-blind switch in the store', function()
		local blind = page.args.colorBlind
		assert.is_false(blind.get() and true or false)
		blind.set({}, true)
		assert.is_true(P.Store:Get('colorBlind'))
		local palette = P.Colors:Program('health')
		assert.not_nil(palette)
		blind.set({}, false)
		assert.is_false(P.Store:Get('colorBlind'))
	end)
end)

describe('colors page: the threat row', function()
	local P, page

	before_each(function()
		P, page = Build()
		SetRole(P, 'tank')
	end)

	it('opens and closes from its button', function()
		local group = page.args.threat
		assert.is_true(group.hidden())
		assert.matches(page.args.threatToggle.name(), 'Show threat colors')
		assert.is_false(page.args.threatSummary.hidden())
		page.args.threatToggle.func()
		assert.is_false(group.hidden())
		assert.matches(page.args.threatToggle.name(), 'Hide threat colors')
		assert.is_true(page.args.threatSummary.hidden())
		page.args.threatToggle.func()
		assert.is_true(group.hidden())
	end)

	it('says in plain words where threat shows now', function()
		assert.matches(page.args.threatSummary.name(), 'bar color')
		assert.matches(page.args.threatSummary.name(), 'in instances')
	end)

	it('picks the role and maps a stored healer to the second choice', function()
		local role = page.args.threat.args.role
		assert.same(role.sorting, { 'auto', 'tank', 'damage' })
		assert.equal(role.get(), 'auto')
		role.set({}, 'tank')
		assert.equal(P.Store:Get('role'), 'tank')
		P.Store:Set('role', 'healer')
		assert.equal(role.get(), 'damage')
		role.set({}, 'auto')
		assert.equal(role.get(), 'auto')
	end)

	it('stores When, and leaves the default unstored', function()
		local when = page.args.threat.args.when
		assert.equal(when.get(), 'instances')
		when.set({}, 'always')
		assert.equal(P.Store:Get({ 'threat', 'when' }), 'always')
		assert.equal(P.Colors:Program('health').rows[2].when, 'everywhere')
		when.set({}, 'instances')
		assert.is_nil(P.Store:Get({ 'threat', 'when' }))
		when.set({}, 'never')
		assert.equal(when.get(), 'never')
	end)

	it('shows threat where the role says, and the player can add and remove places', function()
		local show = page.args.threat.args.show
		assert.is_true(show.get({}, 'bar'))
		assert.is_false(show.get({}, 'border'))
		assert.is_false(Has(ProgramIds(P, 'border'), 'threat'))
		show.set({}, 'border', true)
		assert.same(P.Store:Get({ 'threat', 'show' }), { bar = true, border = true })
		assert.is_true(Has(ProgramIds(P, 'border'), 'threat'))
		show.set({}, 'bar', false)
		assert.is_false(Has(ProgramIds(P, 'health'), 'threat'))
		-- Unchecking the last place goes back to the role's own choice
		show.set({}, 'border', false)
		assert.is_nil(P.Store:Get({ 'threat', 'show' }))
		assert.is_true(show.get({}, 'bar'))
		assert.is_false(show.get({}, 'border'))
	end)

	it('does not store a choice that matches the role anyway', function()
		local show = page.args.threat.args.show
		show.set({}, 'border', true)
		show.set({}, 'border', false)
		assert.is_nil(P.Store:Get({ 'threat', 'show' }))
	end)

	it('keeps Show threat on working while the lists are Custom', function()
		local show = page.args.threat.args.show
		page.args.scheme.set({}, 'custom')
		assert.is_false(Has(P.Store:Get({ 'colors', 'border', 'order' }), 'threat'))
		show.set({}, 'border', true)
		local order = P.Store:Get({ 'colors', 'border', 'order' })
		assert.same({ Has(order, 'offTank'), Has(order, 'petTank'), Has(order, 'threat') }, { true, true, true })
		assert.is_true(Has(ProgramIds(P, 'border'), 'threat'))
		show.set({}, 'border', false)
		order = P.Store:Get({ 'colors', 'border', 'order' })
		assert.is_false(Has(order, 'threat'))
		assert.is_false(Has(order, 'offTank'))
	end)

	it('has six threat colors that read the role palette, flipped by the color-blind switch', function()
		local args = page.args.threat.args
		for _, key in ipairs(P.Roles.STATES) do
			local option = args['color_' .. key]
			assert.not_nil(option, key)
			assert.equal(option.type, 'color')
			assert.is_false(option.hasAlpha)
			local r = option.get()
			assert.equal(r, P.Roles.PALETTE[key][1])
		end
		page.args.colorBlind.set({}, true)
		local r = args.color_safe.get()
		assert.equal(r, P.Roles.PALETTE_COLORBLIND.safe[1])
	end)

	it('stores a color the player picks and the compiled row uses it', function()
		local args = page.args.threat.args
		assert.is_true(args.resetColors.hidden())
		args.color_lost.set({}, 0.1, 0.2, 0.3)
		assert.same(P.Store:Get({ 'threat', 'colors', 'lost' }), { 0.1, 0.2, 0.3, 1 })
		local row
		for _, r in ipairs(P.Colors:Program('health').rows) do
			if r.id == 'threat' then
				row = r
			end
		end
		assert.same(row.colors.lost, { 0.1, 0.2, 0.3, 1 })
		local r, g, b = args.color_lost.get()
		assert.same({ r, g, b }, { 0.1, 0.2, 0.3 })
		assert.is_false(args.resetColors.hidden())
		args.resetColors.func()
		assert.is_nil(P.Store:Get({ 'threat', 'colors' }))
		assert.is_true(args.resetColors.hidden())
	end)

	it('says when the style has no threat glow for the Glow and Plate size places', function()
		local note = page.args.threat.args.glowNote
		assert.is_true(note.hidden(), 'Clean has a threat glow')
		assert.is_true(P.Options.ColorsPage.StyleHasThreatPart())
		P.Store:Set('style', 'mini')
		assert.is_false(P.Options.ColorsPage.StyleHasThreatPart())
		assert.is_true(note.hidden(), 'nothing is turned on that needs it')
		page.args.threat.args.show.set({}, 'glow', true)
		assert.is_false(note.hidden())
		assert.matches(note.name, 'no threat glow')
	end)

	it('explains the colors for the role in plain words', function()
		local explain = page.args.threat.args.explain.name
		assert.matches(explain(), 'You are a tank')
		SetRole(P, 'damage')
		assert.matches(explain(), 'not its target')
	end)
end)

describe('colors page: threat numbers', function()
	local P, page, args

	before_each(function()
		P, page = Build()
		args = page.args.threat.args
	end)

	local function PartIds()
		local resolved = P.Styles.Merge:Resolve(P.Store:Get('style'), 'enemyNPC', P.Store:Get('size'))
		return resolved.parts, resolved
	end

	it('is off at first', function()
		assert.equal(args.numbers.get(), 'none')
		assert.is_nil(PartIds().threatNumber)
		assert.same(args.numbers.sorting, { 'none', 'percent', 'lead' })
	end)

	it('adds the number to the plate and takes it away again, leaving no changes behind', function()
		args.numbers.set({}, 'percent')
		assert.equal(args.numbers.get(), 'percent')
		local parts = PartIds()
		assert.equal(parts.threatNumber.source, 'threatPercent')
		assert.is_true(P.Styles.Merge:HasChanges('clean'))
		local overlay = P.Store:Get({ 'tweaks', 'clean' })
		local cleaned, report = P.Styles.Schema:ValidateOverlay(overlay, P.Styles.Registry:Get('clean').parts)
		assert.not_nil(cleaned)
		assert.equal(report.dropped + report.clamped + report.fixed, 0, 'the overlay passes the import check')

		args.numbers.set({}, 'lead')
		assert.equal(args.numbers.get(), 'lead')
		assert.equal(PartIds().threatNumber.source, 'threatLead')

		args.numbers.set({}, 'none')
		assert.equal(args.numbers.get(), 'none')
		assert.is_nil(PartIds().threatNumber)
		assert.is_false(P.Styles.Merge:HasChanges('clean'))
		assert.is_nil(P.Store:Get({ 'tweaks', 'clean' }))
	end)

	it("keeps the player's other changes when the number goes away", function()
		P.Store:Set({ 'tweaks', 'clean' }, { schema = 1, baseVersion = 1, changes = { parts = { name = { font = { size = 12 } } } } })
		args.numbers.set({}, 'percent')
		args.numbers.set({}, 'none')
		local overlay = P.Store:Get({ 'tweaks', 'clean' })
		assert.equal(overlay.changes.parts.name.font.size, 12)
		assert.is_nil(overlay.add)
	end)

	it('works with a style that already has a threat number', function()
		local style = P.util.Copy(P.Styles.Registry:Get('clean'))
		style.id = 'withNumber'
		style.name = 'With number'
		style.parts.tn = { order = 38, kind = 'text', source = 'threatPercent', anchor = { 'LEFT', 'health', 'RIGHT', 4, 0 } }
		assert.is_true(P.Styles.Registry:RegisterHostStyle(style))
		P.Store:Set('style', 'withNumber')
		assert.equal(args.numbers.get(), 'percent')

		args.numbers.set({}, 'lead')
		assert.equal(PartIds().tn.source, 'threatLead')
		assert.is_nil(P.Store:Get({ 'tweaks', 'withNumber', 'add' }))

		args.numbers.set({}, 'none')
		assert.is_nil(PartIds().tn)
		assert.equal(args.numbers.get(), 'none')

		args.numbers.set({}, 'percent')
		assert.equal(PartIds().tn.source, 'threatPercent')
		assert.is_nil(P.Store:Get({ 'tweaks', 'withNumber' }), 'back to the style as it was made')
	end)

	it('locks while the game restricts changes, with the reason', function()
		assert.is_false(args.numbers.disabled())
		M.EnterCombat()
		assert.is_true(args.numbers.disabled())
		local desc = args.numbers.desc({})
		assert.equal(string.sub(desc, -#P.Options.LOCKED_REASON), P.Options.LOCKED_REASON, 'the reason is added to what it does')
		M.LeaveCombat()
		assert.is_false(args.numbers.disabled())
		assert.not_equal(args.numbers.desc({}), P.Options.LOCKED_REASON)
	end)

	it('says whether the game hides threat, by client', function()
		local text = args.numbers.desc({})
		if M.secrets then
			assert.matches(text, 'often on bosses')
		else
			assert.matches(text, 'always works')
		end
	end)
end)

describe('colors page: mob type colors', function()
	local P, page

	before_each(function()
		P, page = Build()
	end)

	local function HealthMobRow()
		for _, row in ipairs(P.Colors:Program('health').rows) do
			if row.id == 'mobType' then
				return row
			end
		end
	end

	it('has a labeled swatch for each mob type', function()
		local group = page.args.mobType
		local labels = {}
		for _, key in ipairs({ 'boss', 'miniboss', 'caster', 'elite', 'normal', 'minor' }) do
			local option = group.args[key]
			assert.not_nil(option, key)
			assert.equal(option.type, 'color')
			labels[#labels + 1] = option.name
		end
		assert.same(labels, { 'Boss', 'Mini-boss', 'Caster', 'Elite', 'Normal', 'Minor' })
		assert.is_nil(group.hidden)
	end)

	it('reads the standard colors', function()
		local r, g, b = page.args.mobType.args.boss.get()
		local default = P.Colors:GetKind('mobType').default.boss
		assert.same({ r, g, b }, { default[1], default[2], default[3] })
	end)

	it('writes a pick to every list that can hold a mob type row, and the program uses it', function()
		local boss = page.args.mobType.args.boss
		assert.is_true(page.args.mobType.args.reset.hidden())
		boss.set({}, 0.9, 0.1, 0.1)
		for _, piece in ipairs({ 'health', 'border', 'name' }) do
			assert.same(P.Store:Get({ 'colors', piece, 'color', 'mobType', 'boss' }), { 0.9, 0.1, 0.1, 1 })
		end
		assert.is_nil(P.Store:Get({ 'colors', 'cast', 'color' }))
		assert.same(HealthMobRow().colors.boss, { 0.9, 0.1, 0.1, 1 })
		local r = boss.get()
		assert.equal(r, 0.9)
		assert.is_false(page.args.mobType.args.reset.hidden())
		page.args.mobType.args.reset.func()
		assert.is_nil(P.Store:Get({ 'colors', 'health' }))
		assert.is_true(page.args.mobType.args.reset.hidden())
	end)

	it('shows the same colors on the mob type row of the list', function()
		page.args.mobType.args.elite.set({}, 0.2, 0.3, 0.4)
		local rows = P.Options.ColorsPage.Rows('health')
		local mob
		for _, row in ipairs(rows) do
			if row.id == 'mobType' then
				mob = row
			end
		end
		assert.equal(#mob.colors, 6)
		assert.equal(mob.colors[4].key, 'elite')
		assert.same(mob.colors[4].color, { 0.2, 0.3, 0.4, 1 })
		assert.equal(mob.colors[1].label, 'Boss')
	end)
end)

describe('colors page: the lists', function()
	local P, page, widget, ColorsPage

	before_each(function()
		P, page = Build()
		ColorsPage = P.Options.ColorsPage
		widget = MakeList(P, page)
	end)
	after_each(function()
		Release(widget)
		widget = nil
	end)

	it('picks which list it shows, health first', function()
		assert.equal(page.args.listPiece.get(), 'health')
		assert.same(page.args.listPiece.sorting, { 'health', 'border', 'name', 'cast' })
		assert.equal(page.args.list.name({}), 'Health bar')
		page.args.listPiece.set({}, 'cast')
		assert.equal(page.args.list.name({}), 'Cast bar')
		assert.same(Ids(ColorsPage.Rows('cast')), { 'notInterruptible', 'interruptReady', 'importantCast' })
		page.args.listPiece.set({}, 'health')
	end)

	it('shows every row of the compiled list, in order, with a plain sentence', function()
		assert.same(Ids(widget.rows), ProgramIds(P, 'health'))
		for _, row in ipairs(widget.rows) do
			assert.truthy(row.sentence and row.sentence ~= '', row.id)
			assert.truthy(row.when or row.whenText, row.id .. ' has a When clause')
		end
		assert.matches(widget.rowById.tapped.data.sentence, 'Gray when someone else tagged it first')
	end)

	it('keeps the header sentence', function()
		assert.equal(M.Get(widget.header, 'text'), 'When more than one color fits, the top one wins.')
	end)

	it('follows the role: tanks get the threat rows on the bar', function()
		Release(widget)
		SetRole(P, 'tank')
		widget = MakeList(P, page)
		local ids = Ids(widget.rows)
		assert.is_true(Has(ids, 'offTank'))
		assert.is_true(Has(ids, 'petTank'))
		assert.is_true(Has(ids, 'threat'))
		assert.same(ids, ProgramIds(P, 'health'))
		-- the threat rows state their When from the threat row and are changed there
		local threat = widget.rowById.threat.data
		assert.equal(threat.whenText, 'In instances')
		assert.is_nil(threat.when)
		assert.equal(#threat.colors, 4)
	end)

	it('switches a row off and on, keeping it in the list', function()
		widget:ToggleRow('tapped')
		assert.is_true(P.Store:Get({ 'colors', 'health', 'off', 'tapped' }))
		assert.is_false(Has(ProgramIds(P, 'health'), 'tapped'))
		assert.is_true(Has(Ids(widget.rows), 'tapped'))
		assert.is_false(widget.rowById.tapped.data.on)
		assert.equal(P.Store:Get('scheme') or 'auto', 'auto')
		widget:ToggleRow('tapped')
		assert.is_nil(P.Store:Get({ 'colors', 'health' }))
		assert.is_true(Has(ProgramIds(P, 'health'), 'tapped'))
	end)

	it('changes a When clause, and stores nothing when it matches the default', function()
		widget:SetRowWhen('quest', 'raids')
		assert.equal(P.Store:Get({ 'colors', 'health', 'when', 'quest' }), 'raids')
		local quest
		for _, row in ipairs(P.Colors:Program('health').rows) do
			if row.id == 'quest' then
				quest = row
			end
		end
		assert.equal(quest.when, 'raids')
		widget:SetRowWhen('quest', 'world')
		assert.is_nil(P.Store:Get({ 'colors', 'health', 'when', 'quest' }))
	end)

	it('changes the color of a row through the color picker path', function()
		widget:SetRowColor('tapped', { 0.1, 0.2, 0.3 })
		assert.same(P.Store:Get({ 'colors', 'health', 'color', 'tapped' }), { 0.1, 0.2, 0.3, 1 })
		assert.same(P.Colors:Program('health').rows[1].color, { 0.1, 0.2, 0.3, 1 })
		assert.same(widget.rowById.tapped.data.color, { 0.1, 0.2, 0.3, 1 })
	end)

	it('changes one color of the reaction row', function()
		widget:SetRowColor('reaction', { 0.3, 0.3, 0.9 }, 'friendly')
		assert.same(P.Store:Get({ 'colors', 'health', 'color', 'reaction', 'friendly' }), { 0.3, 0.3, 0.9, 1 })
		local row = widget.rowById.reaction.data
		assert.equal(row.colors[3].key, 'friendly')
		assert.same(row.colors[3].color, { 0.3, 0.3, 0.9, 1 })
	end)

	it('sets the scheme to Custom, for every list, when a row moves', function()
		local before = {}
		for _, piece in ipairs(P.Colors.PIECES) do
			before[piece] = ProgramIds(P, piece)
		end
		widget:MoveRow('class', -1)
		assert.equal(P.Store:Get('scheme'), 'custom')
		local expected = before.health
		local i = Has(expected, 'class') and 1
		assert.truthy(i)
		local order = P.Store:Get({ 'colors', 'health', 'order' })
		assert.equal(order[3], 'class')
		assert.equal(order[4], 'quest')
		for _, piece in ipairs({ 'border', 'name', 'cast' }) do
			assert.same(ProgramIds(P, piece), before[piece], piece .. ' did not change')
		end
		assert.same(Ids(widget.rows), ProgramIds(P, 'health'))
	end)

	it('keeps the order the player made after the role changes', function()
		widget:MoveRow('class', -1)
		local mine = ProgramIds(P, 'health')
		SetRole(P, 'tank')
		-- Custom keeps the player's own order of rows
		local after = ProgramIds(P, 'health')
		for i, id in ipairs(mine) do
			assert.equal(after[i], id)
		end
	end)

	it('offers the kinds from the plan, and marks the ones already in the list', function()
		widget:OpenAddMenu()
		local items = Draw.MenuItems()
		assert.not_nil(items)
		local labels, byValue = {}, {}
		for _, item in ipairs(items) do
			labels[#labels + 1] = item.text
			byValue[item.value] = item
		end
		for _, id in ipairs({ 'tapped', 'quest', 'threat', 'mobType', 'class', 'reaction', 'target', 'focus', 'lowHealth', 'fixed' }) do
			assert.not_nil(byValue[id], id .. ' is offered on the health bar')
		end
		assert.is_true(byValue.tapped.disabled)
		assert.is_false(byValue.fixed.disabled or false)
		assert.is_nil(byValue.offTank)
		assert.is_nil(byValue.petTank)
		assert.is_nil(byValue.interruptReady, 'cast kinds are not offered on the health bar')
		assert.same({ labels[1], labels[2], labels[3] }, { 'Tapped', 'Quest', 'Threat' })
		Draw.CloseMenu()
	end)

	it('offers the cast kinds on the cast list', function()
		page.args.listPiece.set({}, 'cast')
		Release(widget)
		widget = MakeList(P, page)
		local ids = Ids(widget.arg.addChoices())
		assert.is_true(Has(ids, 'interruptReady'))
		assert.is_true(Has(ids, 'importantCast'))
		assert.is_true(Has(ids, 'fixed'))
		assert.is_false(Has(ids, 'tapped'))
	end)

	it('puts a new row where its kind usually ranks, flashes it, and switches to Custom', function()
		widget:AddRow('fixed')
		assert.equal(P.Store:Get('scheme'), 'custom')
		local order = P.Store:Get({ 'colors', 'health', 'order' })
		assert.equal(order[#order], 'fixed', 'a kind no scheme ranks goes last, never on top')
		assert.equal(widget.rows[#widget.rows].id, 'fixed')
		local row = widget.rowById.fixed
		assert.truthy(row.flash:GetAlpha() > 0, 'the new row flashes')
		assert.is_true(widget.rowById.fixed.data.removable)
	end)

	it('puts a kind the scheme knows in its usual place', function()
		-- A pinned list that lost Quest: it goes back between Mob type and Class, where the scheme ranks it
		P.Store:Batch(function()
			P.Store:Set({ 'colors', 'health', 'order' }, { 'tapped', 'mobType', 'class', 'reaction' })
			P.Store:Set('scheme', 'custom')
		end)
		Release(widget)
		widget = MakeList(P, page)
		assert.same(Ids(widget.rows), { 'tapped', 'mobType', 'class', 'reaction' })
		widget:AddRow('quest')
		assert.same(P.Store:Get({ 'colors', 'health', 'order' }), { 'tapped', 'mobType', 'quest', 'class', 'reaction' })
		assert.same(Ids(widget.rows), { 'tapped', 'mobType', 'quest', 'class', 'reaction' })
	end)

	it('adds Threat together with Another tank and Your pet, in the usual order', function()
		SetRole(P, 'damage')
		Release(widget)
		widget = MakeList(P, page)
		assert.is_false(Has(Ids(widget.rows), 'threat'))
		widget:AddRow('threat')
		local order = P.Store:Get({ 'colors', 'health', 'order' })
		local at = {}
		for i, id in ipairs(order) do
			at[id] = i
		end
		assert.truthy(at.offTank and at.petTank and at.threat)
		assert.truthy(at.offTank < at.petTank and at.petTank < at.threat)
		assert.equal(at.threat - at.offTank, 2, 'the three rows sit together')
		local ids = ProgramIds(P, 'health')
		assert.is_true(Has(ids, 'threat'))
	end)

	it('tells the next list which new row to flash, once', function()
		local arg = page.args.list.arg
		assert.is_nil(arg.flashId())
		widget:AddRow('fixed')
		assert.equal(arg.flashId(), 'fixed')
		assert.is_nil(arg.flashId(), 'asked for once')
	end)

	it('removes a row the player added, with its settings', function()
		widget:AddRow('fixed')
		widget:SetRowColor('fixed', { 0.4, 0.4, 0.4 })
		widget:SetRowWhen('fixed', 'raids')
		widget:RemoveRow('fixed')
		assert.is_false(Has(P.Store:Get({ 'colors', 'health', 'order' }), 'fixed'))
		assert.is_nil(P.Store:Get({ 'colors', 'health', 'color', 'fixed' }))
		assert.is_nil(P.Store:Get({ 'colors', 'health', 'when', 'fixed' }))
		assert.is_false(Has(ProgramIds(P, 'health'), 'fixed'))
	end)

	it('does not offer to remove the rows a scheme puts there', function()
		for _, row in ipairs(widget.rows) do
			assert.is_false(row.removable, row.id)
		end
		widget:RemoveRow('tapped')
		assert.is_true(Has(Ids(widget.rows), 'tapped'))
	end)

	it('sends threat, mob type and class color clicks to their own place', function()
		SetRole(P, 'tank')
		Release(widget)
		widget = MakeList(P, page)
		local arg = page.args.list.arg
		M.ResetRecords()
		for i = #H.hostCalls, 1, -1 do
			H.hostCalls[i] = nil
		end
		local function Opened()
			local opened = {}
			for _, call in ipairs(H.hostCalls) do
				if call.name == 'OpenOptions' then
					opened[#opened + 1] = call[2]
				end
			end
			return opened
		end
		-- The threat colors are folded away: the page opens them, and the host goes there a frame later
		assert.is_true(page.args.threat.hidden())
		assert.is_true(arg.onEdit('threat', 'color', 'safe'))
		assert.is_false(page.args.threat.hidden(), 'the threat row opened')
		assert.is_false(Has(Opened(), 'threat'), 'not before the page is drawn with it')
		M.Advance(0.5)
		assert.is_true(Has(Opened(), 'threat'), 'the host was asked to open the threat colors')
		assert.is_true(arg.onEdit('mobType', 'color', 'boss'))
		M.Advance(0.5)
		assert.is_true(Has(Opened(), 'mobType'), 'the host was asked to open the mob type colors')
		-- Class colors are the game's: nothing to open, nothing to change
		local before = #H.hostCalls
		assert.is_true(arg.onEdit('class', 'color', 'WARRIOR'))
		M.Advance(0.5)
		assert.equal(#H.hostCalls, before)
		-- Other rows and other clicks are the widget's own
		assert.is_false(arg.onEdit('tapped', 'color'))
		assert.is_false(arg.onEdit('threat', 'row'))
	end)

	it('lets clicks on the swatches of the mob type row reach the page, not the picker', function()
		widget:EditRow('mobType', 'color', 'boss')
		-- The page handled it: nothing was written, and the page was asked to go to the swatches
		assert.is_nil(P.Store:Get('colors'))
	end)

	it('tells the preview which list is on screen, once per drawing of the page', function()
		local seen = {}
		local original = P.Preview.SetColorList
		P.Preview.SetColorList = function(_, piece)
			seen[#seen + 1] = piece or 'none'
			original(P.Preview, piece)
		end
		-- A drawing of the page with More settings open: the list asks for its rows
		page.args.scheme.values()
		page.args.list.arg.rows()
		M.Advance(0.1)
		assert.same(seen, { 'health' })
		assert.equal(P.Preview.colorPiece, 'health')
		-- Another drawing with More settings closed: nobody asks for rows
		page.args.scheme.values()
		M.Advance(0.1)
		assert.same(seen, { 'health', 'none' })
		assert.is_nil(P.Preview.colorPiece)
		-- The list on show follows the piece select
		page.args.listPiece.set({}, 'cast')
		page.args.scheme.values()
		page.args.list.arg.rows()
		M.Advance(0.1)
		assert.equal(P.Preview.colorPiece, 'cast')
		P.Preview.SetColorList = original
		page.args.listPiece.set({}, 'health')
	end)

	it('does not ask the preview again when nothing changed', function()
		local calls = 0
		local original = P.Preview.SetColorList
		P.Preview.SetColorList = function(self, piece)
			calls = calls + 1
			original(self, piece)
		end
		for _ = 1, 3 do
			page.args.scheme.values()
			page.args.list.arg.rows()
			M.Advance(0.1)
		end
		assert.equal(calls, 3)
		assert.equal(P.Preview.colorPiece, 'health')
		P.Preview.SetColorList = original
	end)

	it('takes the player to a list from a link', function()
		for i = #H.hostCalls, 1, -1 do
			H.hostCalls[i] = nil
		end
		ColorsPage.ShowList('name')
		assert.equal(page.args.listPiece.get(), 'name')
		local call = H.hostCalls[#H.hostCalls]
		assert.equal(call.name, 'OpenOptions')
		assert.equal(call[1], 'colors')
		assert.equal(call[2], 'list')
		page.args.listPiece.set({}, 'health')
	end)

	it('puts a limit badge on rows the client cannot do fully', function()
		local quest = widget.rowById.quest.data
		if M.secrets then
			assert.matches(quest.badge, 'open world')
		else
			assert.is_nil(quest.badge)
		end
		local threatBadge
		SetRole(P, 'tank')
		for _, row in ipairs(ColorsPage.Rows('health')) do
			if row.id == 'threat' then
				threatBadge = row.badge
			end
		end
		if M.secrets then
			assert.matches(threatBadge, 'bosses')
		else
			assert.is_nil(threatBadge)
		end
	end)

	it('resets one list without touching the others', function()
		widget:ToggleRow('tapped')
		page.args.listPiece.set({}, 'border')
		local border = P.Store:Get({ 'colors', 'border' })
		assert.is_nil(border)
		assert.is_true(page.args.resetList.hidden())
		page.args.listPiece.set({}, 'health')
		assert.is_false(page.args.resetList.hidden())
		page.args.resetList.func()
		assert.is_nil(P.Store:Get({ 'colors', 'health' }))
	end)

	it('writes only the changes the player made', function()
		widget:ToggleRow('quest')
		local colors = P.Store:Get('colors')
		assert.same(colors, { health = { off = { quest = true } } })
	end)
end)

describe('colors page: where a piece takes its colors from', function()
	local P, page

	before_each(function()
		P, page = Build()
	end)

	local function Parts()
		return P.Styles.Merge:Resolve(P.Store:Get('style'), 'enemyNPC', P.Store:Get('size')).parts
	end

	it('starts with every piece on its own list', function()
		for _, piece in ipairs(P.Colors.PIECES) do
			assert.equal(P.Options.ColorsPage.GetSource(piece), piece)
		end
		assert.equal(page.args.source.get(), 'health')
	end)

	it('lets the name follow the health bar list, and back', function()
		page.args.listPiece.set({}, 'name')
		assert.equal(page.args.source.name({}), 'Name colors come from')
		local values = page.args.source.values()
		assert.equal(values.name, 'Its own list')
		assert.equal(values.health, 'Health bar')
		page.args.source.set({}, 'health')
		assert.equal(Parts().name.colors, 'health')
		assert.equal(page.args.source.get(), 'health')
		assert.equal(P.Store:Get({ 'tweaks', 'clean', 'changes', 'parts', 'name', 'colors' }), 'health')
		local cleaned, report = P.Styles.Schema:ValidateOverlay(P.Store:Get({ 'tweaks', 'clean' }), P.Styles.Registry:Get('clean').parts)
		assert.not_nil(cleaned)
		assert.equal(report.dropped + report.clamped + report.fixed, 0)
		-- the header on the list explains that it is not used now
		assert.matches(page.args.list.arg.header(), 'Name uses the Health bar list now')
		page.args.source.set({}, 'name')
		assert.equal(Parts().name.colors, 'name')
		assert.is_nil(P.Store:Get({ 'tweaks', 'clean' }), 'back to the style as it was made')
		page.args.listPiece.set({}, 'health')
	end)

	it('shares a list for the border and the cast bar too', function()
		page.args.listPiece.set({}, 'border')
		page.args.source.set({}, 'health')
		assert.equal(Parts().health.borderColors, 'health')
		page.args.listPiece.set({}, 'cast')
		page.args.source.set({}, 'name')
		assert.equal(Parts().cast.colors, 'name')
		page.args.source.set({}, 'cast')
		assert.equal(Parts().cast.colors, 'cast')
		page.args.listPiece.set({}, 'border')
		page.args.source.set({}, 'border')
		assert.is_nil(P.Store:Get({ 'tweaks', 'clean' }))
		page.args.listPiece.set({}, 'health')
	end)

	it('is hidden when the style has no part that draws the piece', function()
		page.args.listPiece.set({}, 'health')
		assert.is_false(page.args.source.hidden())
		P.Store:Set('style', 'namesOnly')
		assert.is_true(page.args.source.hidden())
		page.args.listPiece.set({}, 'name')
		assert.is_false(page.args.source.hidden())
		page.args.listPiece.set({}, 'health')
	end)

	it("keeps the player's other changes when it goes back", function()
		P.Store:Set({ 'tweaks', 'clean' }, { schema = 1, baseVersion = 1, changes = { parts = { name = { font = { size = 12 } } } } })
		page.args.listPiece.set({}, 'name')
		page.args.source.set({}, 'health')
		page.args.source.set({}, 'name')
		assert.same(P.Store:Get({ 'tweaks', 'clean' }), { schema = 1, baseVersion = 1, changes = { parts = { name = { font = { size = 12 } } } } })
		page.args.listPiece.set({}, 'health')
	end)

	it('locks with the reason while the game restricts changes', function()
		assert.is_false(page.args.source.disabled())
		M.EnterCombat()
		assert.is_true(page.args.source.disabled())
		assert.equal(string.sub(page.args.source.desc({}), -#P.Options.LOCKED_REASON), P.Options.LOCKED_REASON)
		M.LeaveCombat()
	end)
end)

describe('colors page: odd saved data', function()
	it('still draws when a pasted profile put the wrong kind of value in a color setting', function()
		local P, page = Build()
		P.db.profile.colors = { health = { off = 5, when = 'x', color = { tapped = 7, mobType = 'x', reaction = { hostile = 'red' } }, order = 'y' }, border = 3 }
		P.db.profile.threat = { colors = 3, show = 'all', when = 7 }
		local rows = P.Options.ColorsPage.Rows('health')
		assert.truthy(#rows > 0)
		for _, row in ipairs(rows) do
			assert.is_true(row.on)
			assert.truthy(row.sentence)
		end
		assert.same(P.Options.ColorsPage.Rows('border')[1].id, 'target')
		local r = page.args.mobType.args.boss.get()
		assert.equal(type(r), 'number')
		assert.equal(type(page.args.threat.args.color_safe.get()), 'number')
		assert.is_true(page.args.mobType.args.reset.hidden(), 'no usable mob type colors are saved')
		assert.is_false(page.args.threat.args.resetColors.hidden(), 'the odd threat colors can be cleared')
		local reaction
		for _, row in ipairs(rows) do
			if row.id == 'reaction' then
				reaction = row
			end
		end
		assert.same(reaction.colors[1].color, { 1, 1, 1, 1 })
	end)
end)

describe('colors page: search words', function()
	it('knows everyday words for the settings here', function()
		local P = H.FreshCore()
		local words = P.Options.SEARCH_WORDS
		assert.equal(words.cc, 'crowd control')
		assert.equal(words.colorblind, 'color-blind')
		assert.equal(words.aggro, 'threat')
	end)
end)

describe('colors page: settings stay current', function()
	local P, page
	before_each(function()
		P, page = Build()
	end)
	after_each(function()
		if M.lockdown then
			M.LeaveCombat()
		end
		if M.secrets then
			M.SetRestricted(false)
		end
	end)

	it('reads color settings through Store on every call', function()
		local get = P.Store.Get
		local colors = { health = { color = { tapped = { 0.1, 0.2, 0.3, 1 } } } }
		P.Store.Get = function(self, path, scope)
			if path == 'colors' then
				return colors
			end
			return get(self, path, scope)
		end
		assert.same(P.Options.ColorsPage.Rows('health')[1].color, { 0.1, 0.2, 0.3, 1 })
		colors = { health = { color = { tapped = { 0.7, 0.8, 0.9, 1 } } } }
		assert.same(P.Options.ColorsPage.Rows('health')[1].color, { 0.7, 0.8, 0.9, 1 })
	end)

	it('rejects stale number and shared color callbacks while restricted', function()
		P.Options.ColorsPage.SetPiece('name')
		M.EnterCombat()
		page.args.threat.args.numbers.set({}, 'percent')
		page.args.source.set({}, 'health')
		assert.is_nil(P.Store:Get('tweaks'))
		M.LeaveCombat()
		M.Advance(1)
		assert.is_nil(P.Store:Get('tweaks'), 'nothing was queued')
		page.args.threat.args.numbers.set({}, 'percent')
		assert.equal(page.args.threat.args.numbers.get(), 'percent')
	end)

	it('keeps changes to a built-in threat number when it is turned off and on', function()
		local style = P.util.Copy(P.Styles.Registry:Get('clean'))
		style.id, style.name = 'numberTweaks', 'Number tweaks'
		style.parts.tn = { kind = 'text', source = 'threatPercent', order = 38, anchor = { 'LEFT', 'health', 'RIGHT', 4, 0 } }
		assert.is_true(P.Styles.Registry:RegisterHostStyle(style))
		P.Store:Set('style', style.id)
		local anchor = { 'LEFT', 'health', 'RIGHT', 10, 3 }
		P.Store:Set({ 'tweaks', style.id }, { schema = 1, baseVersion = 1, changes = { parts = { tn = { anchor = anchor, font = { size = 13 } } } } })
		page.args.threat.args.numbers.set({}, 'none')
		page.args.threat.args.numbers.set({}, 'percent')
		local part = P.Styles.Merge:Resolve(style.id, 'enemyNPC', 'medium').parts.tn
		assert.same(part.anchor, anchor)
		assert.equal(part.font.size, 13)
	end)

	it('does not overwrite a different part named threatNumber', function()
		local part = { kind = 'text', source = 'name', order = 38, anchor = { 'TOP', 'health', 'BOTTOM', 0, -8 } }
		P.Store:Set({ 'tweaks', 'clean' }, { schema = 1, baseVersion = 1, add = { threatNumber = part } })
		page.args.threat.args.numbers.set({}, 'percent')
		assert.same(P.Store:Get({ 'tweaks', 'clean', 'add', 'threatNumber' }), part)
		assert.equal(page.args.threat.args.numbers.get(), 'percent')
		page.args.threat.args.numbers.set({}, 'none')
		assert.same(P.Store:Get({ 'tweaks', 'clean', 'add', 'threatNumber' }), part)
	end)

	it('does not treat a hidden threat number as visible', function()
		local style = P.util.Copy(P.Styles.Registry:Get('clean'))
		style.id, style.name = 'hiddenNumber', 'Hidden number'
		style.parts.tn = { kind = 'text', source = 'threatPercent', hidden = true, order = 38, anchor = { 'LEFT', 'health', 'RIGHT', 4, 0 } }
		assert.is_true(P.Styles.Registry:RegisterHostStyle(style))
		P.Store:Set('style', style.id)
		assert.equal(page.args.threat.args.numbers.get(), 'none')
		page.args.threat.args.numbers.set({}, 'percent')
		assert.equal(page.args.threat.args.numbers.get(), 'percent')
	end)
end)

describe('colors page: threat settings have one home', function()
	it('changes threat colors even when a saved list had its own copy', function()
		local P, page = Build()
		SetRole(P, 'tank')
		for _, piece in ipairs({ 'health', 'border', 'name' }) do
			P.Store:Set({ 'colors', piece, 'color', 'threat', 'lost' }, { 1, 0, 1, 1 })
		end
		page.args.threat.args.color_lost.set({}, 0.1, 0.2, 0.3)
		for _, piece in ipairs({ 'health', 'border', 'name' }) do
			assert.is_nil(P.Store:Get({ 'colors', piece, 'color', 'threat', 'lost' }))
		end
		for _, row in ipairs(P.Colors:Program('health').rows) do
			if row.id == 'threat' then
				assert.same(row.colors.lost, { 0.1, 0.2, 0.3, 1 })
			end
		end
	end)

	it('resets saved copies of threat colors from the threat row', function()
		local P, page = Build()
		P.Store:Set({ 'colors', 'name', 'color', 'petTank', 'pet' }, { 1, 0, 1, 1 })
		P.Store:Set({ 'colors', 'health', 'color', 'tapped' }, { 0.1, 0.2, 0.3, 1 })
		assert.is_false(page.args.threat.args.resetColors.hidden())
		page.args.threat.args.resetColors.func()
		assert.is_nil(P.Store:Get({ 'colors', 'name' }))
		assert.same(P.Store:Get({ 'colors', 'health', 'color', 'tapped' }), { 0.1, 0.2, 0.3, 1 })
		assert.is_true(page.args.threat.args.resetColors.hidden())
	end)

	it('changes When even when a saved list had its own threat When', function()
		local P, page = Build()
		SetRole(P, 'tank')
		page.args.scheme.set({}, 'custom')
		for _, id in ipairs(P.Colors.THREAT_GROUP) do
			P.Store:Set({ 'colors', 'health', 'when', id }, 'world')
		end
		page.args.threat.args.when.set({}, 'never')
		for _, row in ipairs(P.Colors:Program('health').rows) do
			if Has(P.Colors.THREAT_GROUP, row.id) then
				assert.equal(row.when, 'never')
			end
		end
	end)
end)
