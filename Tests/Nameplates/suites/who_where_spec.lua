-- @runtime lua51
-- The Who and where page (plan 3.2 #5): the kinds table, the special cases list with its editor,
-- plate behavior, the game settings table, the place-by-place table, click and stacking areas,
-- copy and reset. Settings are checked at their storage paths and through the readers the Driver
-- uses, the page is walked the way the options dialog reads it, and the RuleList widget is driven
-- the way a player drives it.
local M, H = ...

if not H.ModuleExists() then
	describe('who and where', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

H.LoadLibs()
local P = H.FreshCore()
M.Login('NameplatesTestHost')
local AceGUI = LibStub('AceGUI-3.0')
local W = P.Options.WhoAndWhere
local WB = P.WhenBuilder
local Store, CVars, Situation, Driver = P.Store, P.CVars, P.Situation, P.Driver
local Merge = P.Styles.Merge

local function Page()
	return P.Options.pages.whoAndWhere.builder()
end

local function Group(page, ...)
	local node = page
	for _, key in ipairs({ ... }) do
		node = node.args[key]
		assert.not_nil(node, 'missing ' .. key)
	end
	return node
end

local function Reset()
	if M.lockdown then
		M.LeaveCombat()
	end
	P.db:ResetProfile()
	P.db.global.cvarBackup = nil
	P.db.char.cvarBackup = nil
	P.util.Wipe(CVars.info)
	P.util.Wipe(CVars.queue)
	P.util.Wipe(CVars.attribution)
	P.Styles.Merge:Invalidate()
	W.editing = nil
	W.copyTarget, W.copySource = 'friendlyPlayer', 'enemyPlayer'
	P.Context.place = 'world'
	M.ResetRecords()
end

local function Has(list, value)
	for _, v in ipairs(list) do
		if v == value then
			return true
		end
	end
	return false
end

local function Sorted(set)
	local out = {}
	for k in pairs(set) do
		out[#out + 1] = k
	end
	table.sort(out)
	return out
end

local IGNORED_MAIN = { description = true, header = true }

---Count the main controls of a group: not advanced, not text. An inline group counts as one.
local function MainControls(group)
	local count = 0
	for _, option in pairs(group.args or {}) do
		if not option.advanced and not IGNORED_MAIN[option.type] then
			count = count + 1
		end
	end
	return count
end

---Every inline group, with its path.
local function EachGroup(group, path, fn)
	fn(group, path)
	for key, option in pairs(group.args or {}) do
		if option.type == 'group' then
			EachGroup(option, path .. '.' .. key, fn)
		end
	end
end

---Read every control the way the dialog does.
local function Walk(group, path, seen)
	seen = seen or { controls = 0, texts = {} }
	path = path or 'page'
	for key, option in pairs(group.args or {}) do
		local where = path .. '.' .. key
		assert.truthy(option.type ~= nil, where .. ' has a type')
		for _, field in ipairs({ 'name', 'desc', 'confirmText' }) do
			local value = option[field]
			if type(value) == 'function' then
				value = value({})
			end
			if value ~= nil then
				assert.equal(type(value), 'string', where .. '.' .. field)
				seen.texts[#seen.texts + 1] = { where .. '.' .. field, value }
			end
		end
		if type(option.hidden) == 'function' then
			option.hidden({})
		end
		if option.type == 'group' then
			Walk(option, where, seen)
		else
			seen.controls = seen.controls + 1
			if type(option.disabled) == 'function' then
				option.disabled({})
			end
			if option.type == 'select' or option.type == 'multiselect' then
				local values = type(option.values) == 'function' and option.values({}) or option.values
				assert.equal(type(values), 'table', where .. ' values')
				if option.sorting ~= nil then
					local sorting = type(option.sorting) == 'function' and option.sorting({}) or option.sorting
					for _, key2 in ipairs(sorting) do
						assert.not_nil(values[key2], where .. ' sorting names ' .. tostring(key2) .. ' which has no value')
					end
				end
				if option.type == 'select' and option.dialogControl == nil and option.get then
					local current = option.get({})
					assert.truthy(current == nil or values[current] ~= nil, where .. ' shows ' .. tostring(current) .. ' which is not in its values')
				end
			elseif option.type == 'range' then
				local value = option.get({})
				assert.equal(type(value), 'number', where .. ' get')
				assert.truthy(value >= option.min - 1e-6 and value <= option.max + 1e-6, where .. ' value ' .. value .. ' is out of range')
			elseif option.type == 'toggle' then
				local value = option.get({})
				assert.equal(type(value), 'boolean', where .. ' get')
			end
		end
	end
	return seen
end

local function ClearMockCVars()
	P.util.Wipe(CVars.info)
end

describe('who and where: the page', function()
	before_each(Reset)

	it('is a page of the options table, in the fifth place', function()
		local tbl = P:BuildOptionsTable()
		local page = tbl.args.whoAndWhere
		assert.not_nil(page)
		assert.equal(page.type, 'group')
		assert.equal(page.order, 5)
		assert.equal(page.name, 'Who and where')
	end)

	it('keeps to eight main controls on the page and in every group', function()
		local page = Page()
		assert.truthy(MainControls(page) <= 8, 'page: ' .. MainControls(page))
		EachGroup(page, 'page', function(group, path)
			assert.truthy(MainControls(group) <= 8, path .. ' has ' .. MainControls(group) .. ' main controls')
		end)
	end)

	it('folds the rarely used settings under More settings', function()
		local page = Page()
		for _, key in ipairs({ 'places', 'areas', 'copy' }) do
			assert.is_true(page.args[key].advanced, key)
		end
		for _, key in ipairs({ 'kinds', 'when', 'behavior', 'games' }) do
			assert.is_nil(page.args[key].advanced, key)
		end
		local behavior = Group(page, 'behavior')
		for _, key in ipairs({ 'friendMinions', 'gameOverlap', 'onlyFighting', 'wallsAmount', 'rangeAmount', 'rangeYards' }) do
			assert.is_true(behavior.args[key].advanced, key)
		end
	end)

	it('reads every control without error, fresh and after changes', function()
		local page = Page()
		Walk(page)
		Store:Set('when', { WB:NewEntry('raidSmall'), WB:NewEntry('raidMinor') })
		W.editing = 2
		Store:Set({ 'behavior', 'enemies' }, 'combat')
		Store:Set({ 'behavior', 'fadeBehindWalls' }, 0.3)
		Store:Set({ 'behavior', 'rangeFade' }, 0.5)
		Store:Set({ 'behavior', 'places', 'raid', 'stacking', 'enemy' }, true)
		Store:Set({ 'assign', 'enemyPlayer' }, 'clean')
		CVars:Set('nameplateShowEnemies', '0', 'place')
		Walk(Page())
		M.EnterCombat()
		Walk(Page())
	end)

	it('uses plain words: no dashes, symbols or extra characters outside ASCII', function()
		local seen = Walk(Page())
		for _, item in ipairs(seen.texts) do
			assert.is_nil(item[2]:find('[\128-\255]'), item[1] .. ' has a character the game cannot draw: ' .. item[2])
		end
	end)

	it('builds the whole options table without error', function()
		local tbl = P:BuildOptionsTable()
		assert.not_nil(tbl.args.whoAndWhere.args.kinds)
	end)
end)

describe('who and where: kinds of plates', function()
	before_each(Reset)

	it('starts with the defaults in code', function()
		assert.equal(W.Style('enemyNPC'), 'host')
		assert.equal(W.Style('minor'), 'mini')
		assert.equal(W.Mode('enemyNPC'), 'full')
		assert.equal(W.Mode('friendlyNPC'), 'hidden')
		assert.equal(W.Mode('friendlyPlayer'), 'name')
		assert.is_nil(Store:Get('assign'))
		assert.is_nil(Store:Get('modes'))
	end)

	it('stores a choice only when it differs from the default', function()
		W.SetStyle('enemyPlayer', 'mini')
		assert.equal(Store:Get({ 'assign', 'enemyPlayer' }), 'mini')
		W.SetStyle('enemyPlayer', 'host')
		assert.is_nil(Store:Get('assign'), 'back to the main style is stored as nothing')
		W.SetStyle('minor', 'clean')
		assert.equal(Store:Get({ 'assign', 'minor' }), 'clean')
		W.SetStyle('minor', 'mini')
		assert.is_nil(Store:Get('assign'))
		W.SetMode('friendlyNPC', 'full')
		assert.equal(Store:Get({ 'modes', 'friendlyNPC' }), 'full')
		W.SetMode('friendlyNPC', 'hidden')
		assert.is_nil(Store:Get('modes'))
	end)

	it('follows the main style until a kind has its own', function()
		Store:Set('style', 'clean')
		assert.equal(W.Style('enemyPlayer'), 'clean')
		W.SetStyle('enemyPlayer', 'mini')
		Store:Set('style', 'host')
		assert.equal(W.Style('enemyPlayer'), 'mini')
		assert.equal(W.Style('enemyNPC'), 'host')
	end)

	it('lists styles, including Mini, never the names-only style, and always the current one', function()
		local values, order = W.StyleValues('host')
		assert.equal(values.clean, 'Clean')
		assert.equal(values.mini, 'Mini')
		assert.is_nil(values.namesOnly)
		assert.not_nil(values.host, 'Match my look is always a choice when it is the current one')
		assert.is_false(Has(order, 'namesOnly'))
		local other = W.StyleValues('saved9')
		assert.not_nil(other.saved9)
	end)

	it('draws a row per kind with a style, a Show choice and a link', function()
		local kinds = Group(Page(), 'kinds')
		for _, kind in ipairs(Situation.KINDS) do
			local row = kinds.args[kind]
			assert.not_nil(row, kind)
			assert.equal(row.args.style.type, 'select')
			assert.equal(row.args.mode.type, 'select')
			assert.same(row.args.mode.sorting, { 'full', 'name', 'hidden' })
			assert.equal(row.args.label.name, WB.KIND_LABELS[kind])
			if kind == 'enemyNPC' then
				assert.is_nil(row.args.same, 'Enemy NPCs is the one the others copy')
			else
				assert.equal(row.args.same.type, 'execute')
				assert.equal(row.args.same.name, 'Same as enemies')
			end
			local total = 0
			for _, cell in pairs(row.args) do
				assert.equal(cell.width, 'relative')
				total = total + cell.relWidth
			end
			assert.truthy(total <= 1, kind .. ' cells fit the row')
		end
	end)

	it('reads and writes through the row controls', function()
		local row = Group(Page(), 'kinds', 'enemyPlayer').args
		assert.equal(row.style.get({}), 'host')
		row.style.set({}, 'mini')
		assert.equal(row.style.get({}), 'mini')
		assert.equal(Store:Get({ 'assign', 'enemyPlayer' }), 'mini')
		assert.equal(row.mode.get({}), 'full')
		row.mode.set({}, 'name')
		assert.equal(row.mode.get({}), 'name')
		assert.equal(Store:Get({ 'modes', 'enemyPlayer' }), 'name')
		row.mode.set({}, 'full')
		assert.is_nil(Store:Get('modes'))
	end)

	it('uses the style only while Show is Full', function()
		local row = Group(Page(), 'kinds', 'enemyPlayer').args
		assert.is_false(row.style.disabled({}))
		W.SetMode('enemyPlayer', 'name')
		assert.is_true(row.style.disabled({}), 'names only draws its own look')
		W.SetMode('enemyPlayer', 'hidden')
		assert.is_true(row.style.disabled({}))
		W.SetMode('enemyPlayer', 'full')
		assert.is_false(row.style.disabled({}))
	end)

	it('copies Enemy NPCs with "Same as enemies"', function()
		W.SetStyle('enemyNPC', 'mini')
		W.SetMode('enemyNPC', 'name')
		local friend = Group(Page(), 'kinds', 'friendlyPlayer').args
		assert.is_false(friend.same.disabled({}))
		friend.same.func()
		assert.equal(W.Style('friendlyPlayer'), 'mini')
		assert.equal(W.Mode('friendlyPlayer'), 'name')
		assert.is_true(friend.same.disabled({}), 'nothing left to copy')
		assert.is_true(W.IsSameAsEnemies('friendlyPlayer'))
		local minor = Group(Page(), 'kinds', 'minor').args
		minor.same.func()
		assert.equal(W.Style('minor'), 'mini')
		assert.equal(W.Mode('minor'), 'name')
		W.SameAsEnemies('enemyNPC')
		assert.equal(W.Style('enemyNPC'), 'mini', 'Enemy NPCs is never changed by its own link')
	end)

	it('copies in one change', function()
		local count = 0
		P:On('STORE_CHANGED', function()
			count = count + 1
		end, Reset)
		W.SetStyle('enemyNPC', 'mini')
		W.SetMode('enemyNPC', 'hidden')
		count = 0
		W.SameAsEnemies('friendlyPlayer')
		P:Off('STORE_CHANGED', Reset)
		assert.equal(count, 1)
	end)

	it('says the honest thing about friendly plates in instances where the game draws them', function()
		local note = Group(Page(), 'kinds').args.note
		assert.equal(note.name, 'Inside dungeons and raids the game draws friendly plates itself. You can pick names only and class colors there, nothing more.')
		assert.equal(note.hidden({}), not P.Caps:Get('secrets'), 'the Classic family has no such limit')
	end)

	it('turns friendly names in instances on and off', function()
		local toggle = Group(Page(), 'kinds').args.friendlyNames
		assert.is_false(toggle.get({}))
		toggle.set({}, true)
		assert.is_true(Driver:Behavior('friendlyNames'))
		toggle.set({}, false)
		assert.is_nil(Store:Get('behavior'))
	end)
end)

describe('who and where: locks', function()
	before_each(Reset)

	it('locks assignments in combat with a visible reason and leaves behavior alone', function()
		local page = Page()
		assert.is_true(page.args.locked.hidden({}))
		for _, kind in ipairs(Situation.KINDS) do
			assert.is_false(Group(page, 'kinds', kind).args.mode.disabled({}))
		end
		M.EnterCombat()
		assert.is_false(page.args.locked.hidden({}))
		assert.equal(page.args.locked.name, 'The game does not allow plate changes right now. They unlock after combat.')
		for _, kind in ipairs(Situation.KINDS) do
			local row = Group(page, 'kinds', kind).args
			assert.is_true(row.mode.disabled({}), kind)
			assert.is_true(row.style.disabled({}), kind)
			if row.same then
				assert.is_true(row.same.disabled({}), kind)
			end
		end
		assert.is_true(Group(page, 'when', 'list').disabled({}))
		for _, key in ipairs({ 'target', 'source', 'copy', 'reset' }) do
			local option = Group(page, 'copy', key)
			if option.disabled then
				assert.is_true(option.disabled({}), key)
			end
		end
		for _, row in ipairs(W.PLACE_ROWS) do
			assert.is_false(Group(page, 'places', row.id).args.enemies.disabled({}), row.id)
		end
		assert.is_nil(Group(page, 'behavior').args.enemies.disabled, 'plate behavior never locks')
		assert.is_nil(Group(page, 'games').args.restore.disabled, 'giving the settings back never locks')
		M.LeaveCombat()
		assert.is_true(page.args.locked.hidden({}))
		assert.is_false(Group(page, 'kinds', 'minor').args.mode.disabled({}))
	end)
end)

describe('who and where: the special cases list', function()
	before_each(Reset)

	it('shows the stored entries as rows with plain sentences', function()
		assert.same(W.WhenRows(), {})
		Store:Set('when', {
			{ conditions = { { id = 'place', args = 'raid' }, { id = 'role', args = 'tank' } }, style = 'mini' },
			{ conditions = { { id = 'place', args = 'raid' } }, kinds = { 'minor' }, mode = 'hidden', off = true },
			{ conditions = { { id = 'place', args = 'dungeon' } } },
		})
		local rows = W.WhenRows()
		assert.equal(#rows, 3)
		assert.equal(rows[1].id, 'w1')
		assert.equal(rows[1].sentence, 'In a raid and as a tank')
		assert.equal(rows[1].whenText, 'Mini')
		assert.is_true(rows[1].on)
		assert.truthy(rows[1].removable)
		assert.is_nil(rows[1].badge)
		assert.equal(rows[1].tooltip, 'In a raid and as a tank: use Mini')
		assert.equal(rows[2].sentence, 'In a raid - Minor enemies only')
		assert.equal(rows[2].whenText, 'Hidden')
		assert.is_false(rows[2].on)
		assert.equal(rows[3].badge, 'Pick what should happen.', 'a problem shows under the row')
		assert.equal(rows[3].whenText, '-')
	end)

	it('builds the list from the stored truth every time', function()
		local list = Group(Page(), 'when', 'list')
		assert.equal(list.dialogControl, P.Widgets:TypeName('RuleList'))
		Store:Set('when', { WB:NewEntry('raidSmall') })
		assert.equal(#list.arg.rows(), 1)
		Store:Set('when', { WB:NewEntry('raidSmall'), WB:NewEntry('tankLarge') })
		assert.equal(#list.arg.rows(), 2)
		Store:Set('when', nil)
		assert.equal(#list.arg.rows(), 0)
	end)

	it('offers the templates in the Add menu', function()
		local choices = W.WhenAddChoices()
		local ids = {}
		for _, choice in ipairs(choices) do
			ids[#ids + 1] = choice.id
			assert.truthy(choice.label ~= '')
		end
		assert.truthy(Has(ids, 'tpl:raidSmall'))
		assert.truthy(Has(ids, 'tpl:blank'))
	end)

	describe('changes from the list', function()
		local function Change(action, order, rows, extra)
			local change = { action = action, order = order, rows = rows }
			for k, v in pairs(extra or {}) do
				change[k] = v
			end
			return change
		end

		local function Rows(order, off)
			local rows = {}
			for i, id in ipairs(order) do
				rows[i] = { id = id, on = not (off and off[id]) }
			end
			return rows
		end

		before_each(function()
			Store:Set('when', {
				{ conditions = { { id = 'place', args = 'raid' } }, size = 'small' },
				{ conditions = { { id = 'place', args = 'dungeon' } }, size = 'large' },
				{ conditions = { { id = 'place', args = 'pvp' } }, mode = 'name' },
			})
		end)

		it('reorders', function()
			local order = { 'w3', 'w1', 'w2' }
			W.ApplyWhenChange(Change('reorder', order, Rows(order), { id = 'w3', from = 3, index = 1 }))
			local list = Store:Get('when')
			assert.equal(list[1].mode, 'name')
			assert.equal(list[2].size, 'small')
			assert.equal(list[3].size, 'large')
		end)

		it('switches an entry off and on', function()
			local order = { 'w1', 'w2', 'w3' }
			W.ApplyWhenChange(Change('toggle', order, Rows(order, { w2 = true }), { id = 'w2', on = false }))
			assert.is_true(Store:Get('when')[2].off)
			assert.is_nil(Store:Get('when')[1].off)
			W.ApplyWhenChange(Change('toggle', order, Rows(order), { id = 'w2', on = true }))
			assert.is_nil(Store:Get('when')[2].off)
		end)

		it('removes', function()
			local order = { 'w1', 'w3' }
			W.ApplyWhenChange(Change('remove', order, Rows(order), { id = 'w2', from = 2 }))
			local list = Store:Get('when')
			assert.equal(#list, 2)
			assert.equal(list[2].mode, 'name')
			W.ApplyWhenChange(Change('remove', {}, {}, { id = 'w1' }))
			assert.is_nil(Store:Get('when'), 'an empty list is stored as nothing')
		end)

		it('adds a template at the place the list says and opens it', function()
			local order = { 'w1', 'w2', 'w3', 'tpl:raidMinor' }
			W.ApplyWhenChange(Change('add', order, Rows(order), { id = 'tpl:raidMinor', index = 4 }))
			local list = Store:Get('when')
			assert.equal(#list, 4)
			assert.same(list[4].kinds, { 'minor' })
			assert.equal(list[4].mode, 'hidden')
			assert.equal(W.editing, 4, 'the new entry opens for editing')
			assert.same(list[1], { conditions = { { id = 'place', args = 'raid' } }, size = 'small' }, 'the others are untouched')
		end)

		it('ignores a row it does not know', function()
			local order = { 'w1', 'nonsense', 'w2', 'w3', 'w9' }
			W.ApplyWhenChange(Change('reorder', order, Rows(order)))
			assert.equal(#Store:Get('when'), 3)
		end)

		it('keeps the open editor on its entry when rows move or go', function()
			W.editing = 1
			local order = { 'w2', 'w3', 'w1' }
			W.ApplyWhenChange(Change('reorder', order, Rows(order), { id = 'w1', from = 1, index = 3 }))
			assert.equal(W.editing, 3)
			order = { 'w1', 'w2' }
			W.ApplyWhenChange(Change('remove', order, Rows(order), { id = 'w3' }))
			assert.is_nil(W.editing, 'the entry it showed is gone')
		end)
	end)

	describe('the editor', function()
		before_each(function()
			Store:Set('when', {
				{ conditions = { { id = 'place', args = 'raid' } }, size = 'small' },
				{ conditions = { { id = 'place', args = 'dungeon' } }, mode = 'name' },
			})
		end)

		it('opens on a click and closes on a second click or Done', function()
			local editor = Group(Page(), 'when', 'editor')
			assert.is_true(editor.hidden())
			assert.is_nil(W.EditedEntry())
			assert.is_true(W.ToggleEditing('w2'))
			assert.is_false(editor.hidden())
			assert.equal(W.EditedEntry().mode, 'name')
			assert.is_true(W.ToggleEditing('w1'), 'another row switches the editor')
			assert.equal(W.EditedEntry().size, 'small')
			assert.is_false(W.ToggleEditing('w1'), 'the same row closes it')
			assert.is_true(editor.hidden())
			assert.is_false(W.ToggleEditing('w9'), 'a row that does not exist opens nothing')
			W.ToggleEditing('w1')
			editor.args.done.func()
			assert.is_nil(W.editing)
		end)

		it('marks the open row in the list', function()
			local list = Group(Page(), 'when', 'list')
			assert.is_nil(list.get({}))
			W.ToggleEditing('w2')
			assert.equal(list.get({}), 'w2')
		end)

		it('writes edits back to the entry it shows', function()
			local editor = Group(Page(), 'when', 'editor')
			W.ToggleEditing('w1')
			editor.args.conditions.args.condition2.set({}, 'role:tank')
			editor.args.thenGroup.args.action.set({}, 'hide')
			local list = Store:Get('when')
			assert.same(list[1], { conditions = { { id = 'place', args = 'raid' }, { id = 'role', args = 'tank' } }, mode = 'hidden' })
			assert.equal(list[2].mode, 'name', 'the other entry is untouched')
			assert.equal(editor.args.sentence.name(), 'In a raid and as a tank: hide the plate')
		end)

		it('writes nothing when no entry is open', function()
			W.SetEditedEntry({ conditions = {}, mode = 'hidden' })
			assert.equal(#Store:Get('when'), 2)
			assert.equal(Store:Get('when')[1].size, 'small')
		end)
	end)

	describe('with the list widget', function()
		local widget
		local function Open()
			local list = Group(Page(), 'when', 'list')
			widget = P.Widgets:Create('RuleList')
			assert.not_nil(widget)
			widget.frame:SetParent(UIParent)
			widget.frame:Show()
			widget:SetCustomData(list.arg)
			return widget
		end

		after_each(function()
			if widget and not widget.isQueuedForRelease then
				AceGUI:Release(widget)
			end
			widget = nil
		end)

		before_each(function()
			Store:Set('when', {
				{ conditions = { { id = 'place', args = 'raid' } }, size = 'small' },
				{ conditions = { { id = 'place', args = 'dungeon' } }, size = 'large' },
			})
		end)

		it('draws a row per special case from the stored list', function()
			Open()
			local rows = widget:GetValue()
			assert.equal(#rows, 2)
			assert.equal(rows[1].sentence, 'In a raid')
			assert.equal(rows[1].whenText, 'Small size')
			assert.equal(M.Get(widget.rowFrames[1].sentence, 'text'), 'In a raid')
		end)

		it('moves, switches and removes through the page', function()
			Open()
			widget:MoveRow('w2', -1)
			assert.equal(Store:Get('when')[1].size, 'large')
			assert.equal(widget:GetValue()[1].sentence, 'In a dungeon', 'the widget read the stored list again')
			widget:ToggleRow('w1')
			assert.is_true(Store:Get('when')[1].off)
			widget:ToggleRow('w1')
			assert.is_nil(Store:Get('when')[1].off)
			widget:RemoveRow('w1')
			assert.equal(#Store:Get('when'), 1)
			assert.equal(Store:Get('when')[1].size, 'small')
		end)

		it('adds a template and opens its editor', function()
			Open()
			widget:AddRow('tpl:battlegroundNames')
			local list = Store:Get('when')
			assert.equal(#list, 3)
			assert.equal(list[3].mode, 'name')
			assert.equal(W.editing, 3)
			assert.equal(widget:GetValue()[3].sentence, 'In a battleground')
		end)

		it('opens the editor from a row click and does not take the color picker', function()
			Open()
			widget:EditRow('w2', 'row')
			assert.equal(W.editing, 2)
			widget:EditRow('w2', 'row')
			assert.is_nil(W.editing)
		end)

		it('stays put while locked', function()
			Open()
			widget:SetDisabled(true)
			widget:MoveRow('w2', -1)
			widget:ToggleRow('w1')
			widget:RemoveRow('w1')
			assert.equal(#Store:Get('when'), 2)
			assert.equal(Store:Get('when')[1].size, 'small')
		end)
	end)

	it('lets Situation.Assign use what the list stores', function()
		Store:Set('when', { WB:NewEntry('raidMinor'), WB:NewEntry('raidSmall') })
		local settings = { style = Store:Get('style'), size = Store:Get('size'), assign = Store:Get('assign'), modes = Store:Get('modes'), when = Store:Get('when') }
		local out = {}
		local env = { facts = {}, ctx = { place = 'raid', inCombat = false, role = 'damage' }, states = {} }
		Situation.Assign('minor', env, settings, out)
		assert.equal(out.mode, 'hidden')
		assert.equal(out.whenIndex, 1)
		Situation.Assign('enemyNPC', env, settings, out)
		assert.equal(out.size, 'small')
		assert.equal(out.whenIndex, 2, 'the first entry that fits decides')
	end)
end)

describe('who and where: plate behavior', function()
	before_each(function()
		Reset()
		for _, name in ipairs({ 'nameplateShowEnemies', 'nameplateShowEnemyPets', 'nameplateShowEnemyGuardians', 'nameplateShowEnemyTotems', 'nameplateShowEnemyMinions', 'nameplateMaxDistance' }) do
			M.SetCVarState(name, { value = '1', default = '1' })
		end
		M.SetCVarState('nameplateMaxDistance', { value = '60', default = '60' })
		ClearMockCVars()
	end)

	it('chooses when enemy plates show', function()
		local enemies = Group(Page(), 'behavior').args.enemies
		assert.equal(enemies.get({}), 'game')
		enemies.set({}, 'combat')
		assert.equal(Driver:Behavior('enemies'), 'combat')
		assert.equal(enemies.get({}), 'combat')
		enemies.set({}, 'always')
		assert.equal(Driver:Behavior('enemies'), 'always')
		enemies.set({}, 'game')
		assert.is_nil(Store:Get('behavior'), 'the game decides again')
		assert.same(Sorted(enemies.values), { 'always', 'combat', 'game' })
	end)

	it('picks pets, totems and guardians from the settings this client has', function()
		local minions = Group(Page(), 'behavior').args.minions
		assert.same(Sorted(minions.values({})), { 'guardians', 'minions', 'pets', 'totems' })
		assert.is_false(minions.hidden({}))
		assert.is_true(minions.get({}, 'pets'), 'shows what the game shows')
		minions.set({}, 'pets', false)
		assert.is_false(minions.get({}, 'pets'))
		assert.is_false(Store:Get({ 'cvars', 'nameplateShowEnemyPets' }))
		assert.is_true(minions.get({}, 'totems'))
		M.RemoveCVar('nameplateShowEnemyMinions')
		ClearMockCVars()
		assert.same(Sorted(minions.values({})), { 'guardians', 'pets', 'totems' })
		for _, name in ipairs({ 'nameplateShowEnemyPets', 'nameplateShowEnemyGuardians', 'nameplateShowEnemyTotems' }) do
			M.RemoveCVar(name)
		end
		ClearMockCVars()
		assert.is_true(minions.hidden({}), 'a client without them has no box')
	end)

	it('keeps plates from overlapping for enemies and friends', function()
		local stacking = Group(Page(), 'behavior').args.stacking
		stacking.set({}, 'enemy', true)
		stacking.set({}, 'friendly', false)
		assert.same(Driver:Behavior('stacking'), { enemy = true, friendly = false })
		assert.is_true(stacking.get({}, 'enemy'))
		assert.is_false(stacking.get({}, 'friendly'))
		assert.same(stacking.values, { enemy = 'Enemies', friendly = 'Friends' })
	end)

	it("shows the game's own stacking choice until the player makes one", function()
		local stacking = Group(Page(), 'behavior').args.stacking
		if CVars:Exists('nameplateStackingTypes') then
			assert.equal(type(stacking.get({}, 'enemy')), 'boolean')
		end
		assert.is_nil(Store:Get('behavior'), 'reading changes nothing')
	end)

	it('writes the overlap setting the game uses under More settings', function()
		local overlap = Group(Page(), 'behavior').args.gameOverlap
		assert.is_true(overlap.advanced)
		assert.not_nil(CVars.defs.nameplateOverlapV)
		assert.equal(CVars.defs.nameplateOverlapV.page, 'whoAndWhere')
		assert.equal(CVars.defs.nameplateOverlapV.kind, 'number')
		M.RemoveCVar('nameplateOverlapV')
		ClearMockCVars()
		assert.is_true(overlap.hidden({}), 'a missing setting hides its control')
		M.SetCVarState('nameplateOverlapV', { value = '1.1', default = '1.1' })
		ClearMockCVars()
		assert.is_false(overlap.hidden({}))
		assert.near(overlap.get({}), 1.1, 0.001)
		overlap.set({}, 1.5)
		assert.equal(Store:Get({ 'cvars', 'nameplateOverlapV' }), 1.5)
		assert.near(overlap.get({}), 1.5, 0.001)
		assert.is_true(overlap.isPercent)
	end)

	it('sets the space between plates as the height of their stacking area', function()
		local spacing = Group(Page(), 'behavior').args.spacing
		assert.is_nil(spacing.advanced, 'a main control')
		assert.is_true(spacing.isPercent)
		assert.same({ spacing.min, spacing.max }, { 1, 3 })
		local base = spacing.get({})
		assert.truthy(base >= 1)
		spacing.set({}, 2)
		assert.near(spacing.get({}), 2, 0.05)
		spacing.set({}, base)
		assert.is_nil(Store:Get({ 'tweaks', 'clean' }))
		assert.equal(spacing.disabled({}), not (Driver:FeatureState('stacking')))
	end)

	it('sets how far away plates show', function()
		local distance = Group(Page(), 'behavior').args.distance
		assert.equal(distance.get({}), 60)
		distance.set({}, 45)
		assert.equal(Store:Get({ 'cvars', 'nameplateMaxDistance' }), 45)
		assert.equal(distance.get({}), 45)
		M.RemoveCVar('nameplateMaxDistance')
		ClearMockCVars()
		assert.is_true(distance.hidden({}))
	end)

	it('turns click through, wall fade and range fade on and off', function()
		local args = Group(Page(), 'behavior').args
		P.Caps:Record('hitTestInsets', true)
		P.Caps:Record('rangeReadable', true)
		M.SetCVarState('nameplateOccludedAlphaMult', { value = '0.4', default = '0.4' })
		ClearMockCVars()
		assert.is_false(args.clickThrough.get({}))
		args.clickThrough.set({}, true)
		assert.is_true(Driver:Behavior('clickThroughFriendly'))
		args.clickThrough.set({}, false)
		assert.is_nil(Driver:Behavior('clickThroughFriendly'))

		assert.is_false(args.fadeWalls.get({}))
		args.fadeWalls.set({}, true)
		assert.is_true(args.fadeWalls.get({}))
		assert.equal(Driver:Behavior('fadeBehindWalls'), 0.4)
		args.fadeWalls.set({}, false)
		assert.is_nil(Store:Get('behavior'))

		assert.is_false(args.rangeFade.get({}))
		args.rangeFade.set({}, true)
		assert.equal(Driver:Behavior('rangeFade'), 0.5)
		args.rangeFade.set({}, false)
		assert.is_nil(Store:Get('behavior'))
	end)

	it('shows how much plates fade and writes the plate alpha the Driver reads', function()
		local args = Group(Page(), 'behavior').args
		assert.is_true(args.wallsAmount.hidden({}), 'only while wall fade is on')
		assert.is_true(args.rangeAmount.hidden({}))
		assert.is_true(args.rangeYards.hidden({}))
		Store:Set({ 'behavior', 'fadeBehindWalls' }, 0.4)
		Store:Set({ 'behavior', 'rangeFade' }, 0.5)
		assert.is_false(args.wallsAmount.hidden({}))
		assert.is_false(args.rangeAmount.hidden({}))
		assert.near(args.wallsAmount.get({}), 0.6, 0.0001)
		args.wallsAmount.set({}, 0.75)
		assert.near(Driver:Behavior('fadeBehindWalls'), 0.25, 0.0001)
		args.rangeAmount.set({}, 0.2)
		assert.near(Driver:Behavior('rangeFade'), 0.8, 0.0001)
		args.rangeAmount.set({}, 0)
		assert.equal(Driver:Behavior('rangeFade'), 1)
		assert.equal(args.rangeYards.get({}), Driver.RANGE_YARDS)
		args.rangeYards.set({}, 30)
		assert.equal(Driver:Behavior('rangeYards'), 30)
		args.rangeYards.set({}, Driver.RANGE_YARDS)
		assert.is_nil(Store:Get({ 'behavior', 'rangeYards' }))
	end)

	it('gives a reason, not a dead switch, where the client cannot do it', function()
		local args = Group(Page(), 'behavior').args
		P.Caps:Record('hitTestInsets', false)
		assert.is_true(args.clickThrough.disabled({}))
		assert.is_false(args.clickThroughNote.hidden({}))
		assert.equal(args.clickThroughNote.name(), 'This version of the game cannot let clicks pass through plates.')
		P.Caps:Record('hitTestInsets', true)
		assert.is_false(args.clickThrough.disabled({}))
		assert.is_true(args.clickThroughNote.hidden({}))
		assert.equal(args.clickThroughNote.name(), '')

		M.RemoveCVar('nameplateOccludedAlphaMult')
		ClearMockCVars()
		assert.is_true(args.fadeWalls.disabled({}))
		assert.equal(args.fadeWallsNote.name(), 'This version of the game cannot fade plates behind walls.')

		P.Caps:Record('unitCombat', false)
		assert.is_true(args.onlyFighting.disabled({}))
		assert.equal(args.onlyFightingNote.name(), 'The game hides whether enemies are fighting, so every enemy shows.')
		assert.is_true(args.onlyFighting.advanced and args.onlyFightingNote.advanced, 'the reason folds with its switch')
	end)

	it('chooses friendly pets, totems and guardians under More settings', function()
		M.SetCVarState('nameplateShowFriendlyPlayerPets', { value = '0', default = '0' })
		ClearMockCVars()
		local friends = Group(Page(), 'behavior').args.friendMinions
		assert.is_true(friends.advanced)
		assert.not_nil(friends.values({}).pets)
		friends.set({}, 'pets', true)
		assert.is_true(Store:Get({ 'cvars', 'nameplateShowFriendlyPlayerPets' }))
	end)

	it('hands settings to the Driver, which writes them to the game', function()
		Driver.active, Driver.standing = true, true
		local enemies = Group(Page(), 'behavior').args.enemies
		M.SetCVarState('nameplateShowEnemies', { value = '0' })
		ClearMockCVars()
		enemies.set({}, 'always')
		Driver:ApplyPlaceSettings()
		assert.equal(C_CVar.GetCVar('nameplateShowEnemies'), '1')
		Group(Page(), 'behavior').args.minions.set({}, 'totems', false)
		Group(Page(), 'behavior').args.distance.set({}, 40)
		Driver:ApplyPlaceSettings()
		assert.equal(C_CVar.GetCVar('nameplateShowEnemyTotems'), '0')
		assert.equal(C_CVar.GetCVar('nameplateMaxDistance'), '40')
		Driver.active, Driver.standing = false, false
	end)
end)

describe('who and where: game settings we change', function()
	before_each(function()
		Reset()
		M.SetCVarState('nameplateShowEnemies', { value = '1', default = '1' })
		M.SetCVarState('nameplateMaxDistance', { value = '60', default = '60' })
		M.SetCVarState('nameplateShowEnemyTotems', { value = '1', default = '1' })
		ClearMockCVars()
	end)

	it('lists nothing until a setting is changed', function()
		assert.same(W.GameRows(), {})
		local games = Group(Page(), 'games')
		assert.equal(games.args.intro.name(), 'We have not changed any game settings.')
		assert.is_true(games.args.table.hidden({}))
		assert.is_true(games.args.table.args.nameplateShowEnemies_was.hidden({}))
	end)

	it('shows the old value, the current value and who changed it', function()
		CVars:Set('nameplateShowEnemies', '0', 'place')
		CVars:Set('nameplateMaxDistance', 45, 'setup')
		local rows = W.GameRows()
		assert.equal(#rows, 2)
		local byName = {}
		for _, row in ipairs(rows) do
			byName[row.name] = row
		end
		assert.same({ byName.nameplateShowEnemies.was, byName.nameplateShowEnemies.now }, { 'On', 'Off' })
		assert.equal(byName.nameplateShowEnemies.label, CVars.defs.nameplateShowEnemies.label)
		assert.equal(byName.nameplateShowEnemies.by, 'Test Host, for this place')
		assert.same({ byName.nameplateMaxDistance.was, byName.nameplateMaxDistance.now }, { '60', '45' })
		assert.equal(byName.nameplateMaxDistance.by, 'Test Host, during setup')
		local games = Group(Page(), 'games')
		local cells = games.args.table.args
		assert.is_false(games.args.table.hidden({}))
		assert.is_false(cells.nameplateShowEnemies_was.hidden({}))
		assert.equal(cells.nameplateShowEnemies_was.name(), 'On')
		assert.equal(cells.nameplateShowEnemies_now.name(), 'Off')
		assert.equal(cells.nameplateShowEnemies_by.name(), 'Test Host, for this place')
		assert.equal(cells.nameplateShowEnemies_label.name(), CVars.defs.nameplateShowEnemies.label)
		assert.truthy(games.args.intro.name():find('You can put them all back.', 1, true))
		assert.is_true(cells.nameplateShowEnemyTotems_was.hidden({}), 'untouched settings are not listed')
	end)

	it('lists rows in the order the settings are defined', function()
		CVars:Set('nameplateMaxDistance', 45)
		CVars:Set('nameplateShowEnemies', '0')
		local rows = W.GameRows()
		assert.equal(rows[1].name, 'nameplateShowEnemies')
		assert.equal(rows[2].name, 'nameplateMaxDistance')
	end)

	it('reports outside changes without naming another add-on', function()
		CVars:Enable()
		CVars:Set('nameplateShowEnemies', '0', 'place')
		C_CVar.SetCVar('nameplateMaxDistance', '80')
		local row = W.GameRow('nameplateMaxDistance')
		assert.not_nil(row, 'a setting someone else changed is listed')
		assert.equal(row.was, '-', 'we never backed it up')
		assert.equal(row.now, '80')
		assert.equal(row.by, 'The game or another add-on')
		CVars.attribution.nameplateMaxDistance.stack = 'Interface/AddOns/SomeOtherAddon/Core.lua:12: in function <x>\nInterface/AddOns/Blizzard_Foo/Bar.lua:1: in function <y>'
		assert.equal(W.WhoChanged('nameplateMaxDistance'), 'The game or another add-on')
		CVars:Disable()
	end)

	it('says a setting we changed in an earlier session', function()
		P.db.global.cvarBackup = { nameplateShowEnemyTotems = '1' }
		M.SetCVarState('nameplateShowEnemyTotems', { value = '0' })
		ClearMockCVars()
		local row = W.GameRow('nameplateShowEnemyTotems')
		assert.equal(row.by, 'Test Host, in an earlier session')
		assert.same({ row.was, row.now }, { 'On', 'Off' })
	end)

	it('writes values in words', function()
		M.SetCVarState('nameplateStackingTypes', { value = '3' })
		ClearMockCVars()
		assert.equal(W.FormatValue('nameplateShowEnemies', '1'), 'On')
		assert.equal(W.FormatValue('nameplateShowEnemies', '0'), 'Off')
		assert.equal(W.FormatValue('nameplateMaxDistance', '60'), '60')
		assert.equal(W.FormatValue('nameplateMaxDistance', '60.00'), '60')
		assert.equal(W.FormatValue('nameplateMaxDistance', '10'), '10')
		assert.equal(W.FormatValue('nameplateMinScale', '0.8'), '0.8')
		assert.equal(W.FormatValue('nameplateMinScale', '0'), '0')
		assert.equal(W.FormatValue('nameplateStackingTypes', '3'), 'enemies, friends')
		assert.equal(W.FormatValue('nameplateStackingTypes', '1'), 'enemies')
		assert.equal(W.FormatValue('nameplateStackingTypes', '0'), 'none')
		assert.equal(W.FormatValue('nameplateEnemyNpcAuraDisplay', '6'), 'debuffs, crowd control')
		assert.equal(W.FormatValue('nothingSuchSetting', 'x'), 'x')
		assert.equal(W.FormatValue('nameplateShowEnemies', nil), '-')
	end)

	it('gives the settings back with the button', function()
		CVars:Set('nameplateShowEnemies', '0', 'place')
		CVars:Set('nameplateMaxDistance', 45)
		local restore = Group(Page(), 'games').args.restore
		restore.func()
		assert.equal(C_CVar.GetCVar('nameplateShowEnemies'), '1')
		assert.equal(C_CVar.GetCVar('nameplateMaxDistance'), '60')
		assert.same(W.GameRows(), {})
		assert.is_true(Group(Page(), 'games').args.waiting.hidden({}))
		assert.equal(restore.name, 'Give the game back its settings')
		assert.is_nil(restore.disabled)
	end)

	it('says some settings wait for combat to end', function()
		M.SetCVarState('nameplateMaxDistance', { value = '60', default = '60', secure = true })
		ClearMockCVars()
		CVars:Set('nameplateMaxDistance', 45)
		M.EnterCombat()
		local games = Group(Page(), 'games')
		games.args.restore.func()
		assert.equal(C_CVar.GetCVar('nameplateMaxDistance'), '45', 'the game would not take it in combat')
		assert.is_false(games.args.waiting.hidden({}))
		assert.equal(games.args.waiting.name(), 'Some settings come back when combat ends.')
		M.LeaveCombat()
		assert.equal(C_CVar.GetCVar('nameplateMaxDistance'), '60')
		assert.is_true(games.args.waiting.hidden({}))
	end)

	it('has a heading cell and a cell per column', function()
		local cells = Group(Page(), 'games', 'table').args
		for _, field in ipairs({ 'label', 'was', 'now', 'by' }) do
			assert.not_nil(cells['head_' .. field], field)
			assert.not_nil(cells['nameplateShowEnemies_' .. field], field)
			assert.equal(cells['nameplateShowEnemies_' .. field].type, 'description')
			assert.equal(cells['nameplateShowEnemies_' .. field].width, 'relative')
		end
		local total = 0
		for _, field in ipairs({ 'label', 'was', 'now', 'by' }) do
			total = total + cells['head_' .. field].relWidth
		end
		assert.truthy(total <= 1, 'a row fits')
		assert.equal(cells.head_was.name, 'Was')
	end)
end)

describe('who and where: place by place', function()
	before_each(Reset)

	it('starts on Default everywhere', function()
		local places = Group(Page(), 'places')
		for _, row in ipairs(W.PLACE_ROWS) do
			for _, column in ipairs(W.PLACE_COLUMNS) do
				assert.equal(places.args[row.id].args[column.id].get({}), 'default', row.id .. ' ' .. column.id)
			end
		end
		assert.equal(#W.PLACE_ROWS, 5)
		assert.equal(W.PLACE_ROWS[5].label, 'Arena and battleground')
	end)

	it('stores a choice for one place and the Driver reads it only there', function()
		local raid = Group(Page(), 'places', 'raid').args
		raid.enemies.set({}, 'combat')
		raid.friendlyPlayers.set({}, 'hide')
		raid.stackEnemy.set({}, 'on')
		assert.equal(Store:Get({ 'behavior', 'places', 'raid', 'enemies' }), 'combat')
		assert.is_false(Store:Get({ 'behavior', 'places', 'raid', 'friendlyPlayers' }))
		assert.is_true(Store:Get({ 'behavior', 'places', 'raid', 'stacking', 'enemy' }))
		assert.equal(raid.enemies.get({}), 'combat')
		assert.equal(raid.friendlyPlayers.get({}), 'hide')
		assert.equal(raid.stackEnemy.get({}), 'on')
		assert.equal(raid.stackFriendly.get({}), 'default')
		P.Context.place = 'raid'
		assert.equal(Driver:Behavior('enemies'), 'combat')
		assert.is_false(Driver:Behavior('friendlyPlayers'))
		P.Context.place = 'world'
		assert.is_nil(Driver:Behavior('enemies'))
		assert.equal(Group(Page(), 'places', 'world').args.enemies.get({}), 'default')
	end)

	it('writes a place row to every place it stands for', function()
		local pvp = Group(Page(), 'places', 'pvp').args
		pvp.friendlyNPCs.set({}, 'show')
		assert.is_true(Store:Get({ 'behavior', 'places', 'arena', 'friendlyNPCs' }))
		assert.is_true(Store:Get({ 'behavior', 'places', 'battleground', 'friendlyNPCs' }))
		local dungeon = Group(Page(), 'places', 'dungeon').args
		dungeon.enemies.set({}, 'always')
		assert.equal(Store:Get({ 'behavior', 'places', 'scenario', 'enemies' }), 'always')
		pvp.friendlyNPCs.set({}, 'default')
		assert.is_nil(Store:Get({ 'behavior', 'places', 'arena' }))
		assert.is_nil(Store:Get({ 'behavior', 'places', 'battleground' }))
	end)

	it('clears a place back to the default and leaves no empty tables behind', function()
		local raid = Group(Page(), 'places', 'raid').args
		raid.enemies.set({}, 'combat')
		raid.stackFriendly.set({}, 'off')
		raid.enemies.set({}, 'default')
		raid.stackFriendly.set({}, 'default')
		assert.is_nil(Store:Get('behavior'))
	end)

	it('offers the three choices a column has', function()
		local raid = Group(Page(), 'places', 'raid').args
		assert.same(raid.enemies.sorting, { 'default', 'always', 'combat' })
		assert.same(raid.friendlyPlayers.sorting, { 'default', 'show', 'hide' })
		assert.same(raid.stackEnemy.sorting, { 'default', 'on', 'off' })
		for _, column in ipairs(W.PLACE_COLUMNS) do
			local choices = raid[column.id]
			for _, key in ipairs(choices.sorting) do
				assert.not_nil(choices.values[key])
			end
		end
	end)

	it('gives a reason for stacking where the client cannot do it', function()
		local raid = Group(Page(), 'places', 'raid').args
		assert.equal(raid.stackEnemy.disabled({}), not (Driver:FeatureState('stacking')))
		assert.is_false(raid.enemies.disabled({}))
	end)
end)

describe('who and where: click and stacking areas', function()
	before_each(Reset)

	local function ClickRect(id)
		return Merge:Resolve(id, nil, 'medium').regions.click
	end
	local function StackRect(id)
		return Merge:Resolve(id, nil, 'medium').regions.stack
	end

	it('works on the styles the plates use, the main one first', function()
		local ids = W.AreaStyles()
		assert.equal(ids[1], 'clean')
		assert.truthy(Has(ids, 'mini'), 'minor enemies')
		assert.truthy(Has(ids, Situation.NAME_STYLE), 'friendly players')
		W.SetStyle('enemyPlayer', 'mini')
		Store:Set('when', { { conditions = {}, style = 'clean' } })
		local seen = {}
		for _, id in ipairs(W.AreaStyles()) do
			assert.is_nil(seen[id], id .. ' once')
			seen[id] = true
		end
	end)

	it('starts at no extra click space', function()
		assert.equal(W.ClickExtra(), 0)
		assert.truthy(W.StackHeight() >= 1)
		assert.is_true((W.AreasAdjustable()))
	end)

	it('adds click space on every side to every style in use', function()
		local before = ClickRect('clean')
		local beforeMini = ClickRect('mini')
		W.SetClickExtra(3)
		assert.equal(W.ClickExtra(), 3)
		local after = ClickRect('clean')
		assert.equal(after.left, before.left - 3)
		assert.equal(after.right, before.right + 3)
		assert.equal(after.top, before.top + 3)
		assert.equal(after.bottom, before.bottom - 3)
		assert.equal(ClickRect('mini').right, beforeMini.right + 3)
		assert.same(Store:Get({ 'tweaks', 'clean', 'changes', 'regions', 'click', 'pad' }), { 7, 7, 9, 5 }, "the style's own padding plus three")
		assert.same(Store:Get({ 'tweaks', 'mini', 'changes', 'regions', 'click', 'pad' }), { 7, 7, 7, 7 })
		W.SetClickExtra(0)
		assert.is_nil(Store:Get('tweaks'), 'nothing is left behind')
		assert.same(ClickRect('clean'), before)
	end)

	it('keeps its own steps clear of the stacking area', function()
		local stack = StackRect('clean')
		W.SetClickExtra(5)
		assert.same(StackRect('clean'), stack)
	end)

	it("raises the stacking height to a percent of the plate's parts", function()
		local base = W.StackHeight()
		local rectBefore = StackRect('clean')
		W.SetStackHeight(2)
		assert.near(W.StackHeight(), 2, 0.05)
		local rect = StackRect('clean')
		assert.equal(rect.left, rectBefore.left, 'only the height changes')
		assert.equal(rect.right, rectBefore.right)
		assert.truthy((rect.top - rect.bottom) > (rectBefore.top - rectBefore.bottom))
		local state = W.RegionState('clean', 'stack')
		assert.near((rect.top - rect.bottom) / state.rawHeight, 2, 0.05)
		W.SetStackHeight(base)
		assert.is_nil(Store:Get({ 'tweaks', 'clean' }), "the style's own height is stored as nothing")
		assert.same(StackRect('clean'), rectBefore)
	end)

	it('does not go below the parts or above three times them', function()
		W.SetStackHeight(0.2)
		assert.equal(W.StackHeight(), W.StackHeight())
		assert.truthy(W.StackHeight() >= 1 - 0.001)
		W.SetStackHeight(9)
		assert.truthy(W.StackHeight() <= 3.05)
		for _, id in ipairs(W.AreaStyles()) do
			local pad = Store:Get({ 'tweaks', id, 'changes', 'regions', 'stack', 'pad' })
			if pad then
				for i = 1, 4 do
					assert.truthy(pad[i] >= 0 and pad[i] <= 64, id .. ' pad ' .. i)
				end
			end
		end
	end)

	it('writes values the style validator accepts', function()
		W.SetClickExtra(4)
		W.SetStackHeight(2.5)
		for _, id in ipairs(W.AreaStyles()) do
			local overlay = Store:Get({ 'tweaks', id })
			if overlay then
				local cleaned, report = P.Styles.Schema:ValidateOverlay(overlay, P.Styles.Registry:Get(id).parts)
				assert.not_nil(cleaned, id)
				assert.same({ report.dropped, report.clamped, report.fixed }, { 0, 0, 0 }, id)
			end
		end
	end)

	it('shows up as a change to the style, which Undo my changes removes', function()
		assert.is_false(Merge:HasChanges('clean'))
		W.SetClickExtra(2)
		assert.is_true(Merge:HasChanges('clean'))
		Store:Set({ 'tweaks', 'clean' }, nil)
		assert.equal(W.ClickExtra(), 0)
	end)

	it('leaves a style alone that places its areas by hand', function()
		P.Styles.Registry:RegisterBuiltin({
			id = 'handmade',
			name = 'Handmade',
			version = 1,
			schema = P.Styles.Schema.CURRENT,
			order = 500,
			plate = { sizes = { small = { 100, 8 }, medium = { 120, 10 }, large = { 140, 12 } } },
			regions = { click = { auto = false, rect = { left = -70, right = 70, top = 12, bottom = -12 } }, stack = { auto = true, pad = { 2, 2, 2, 2 } } },
			tokens = {},
			parts = {
				health = { order = 10, kind = 'bar', source = 'health', anchor = { 'CENTER', 'plate', 'CENTER', 0, 0 }, fill = 'plate' },
			},
		})
		Store:Set('style', 'handmade')
		local ok, reason = W.AreasAdjustable()
		assert.is_false(ok)
		assert.equal(reason, 'This style places its areas by hand. Change them in Customize.')
		W.SetClickExtra(3)
		assert.is_nil(Store:Get({ 'tweaks', 'handmade' }), 'a hand-made area is never padded')
		local areas = Group(Page(), 'areas')
		local spacing = Group(Page(), 'behavior').args
		assert.is_true(areas.args.padding.disabled({}))
		assert.is_true(spacing.spacing.disabled({}))
		assert.is_false(areas.args.reason.hidden({}))
		assert.is_false(spacing.spacingNote.hidden({}))
		assert.equal(areas.args.reason.name(), reason)
		assert.equal(spacing.spacingNote.name(), reason)
		Store:Set('style', 'host')
		assert.is_true(areas.args.reason.hidden({}))
		assert.is_true(spacing.spacingNote.hidden({}))
	end)

	it('draws the controls with their limits', function()
		local areas = Group(Page(), 'areas')
		assert.is_true(areas.advanced)
		assert.equal(areas.args.padding.min, 0)
		assert.equal(areas.args.padding.max, 20)
		areas.args.padding.set({}, 6)
		assert.equal(areas.args.padding.get({}), 6)
		assert.truthy(areas.args.note.name:find('eye button', 1, true), 'tells where to see the areas')
		assert.is_nil(areas.args.stackHeight, 'the stacking height is the space between plates')
	end)
end)

describe('who and where: copy and reset', function()
	before_each(Reset)

	local function Seed()
		W.SetStyle('enemyPlayer', 'mini')
		W.SetMode('enemyPlayer', 'name')
		Store:Set({ 'tweaks', 'clean', 'situations', 'enemyPlayer' }, { hide = { 'cast' } })
		Store:Set({ 'tweaks', 'mini', 'situations', 'enemyPlayer' }, { hide = { 'marker' } })
		Store:Set({ 'tweaks', 'clean', 'situations', 'minor' }, { hide = { 'power' } })
	end

	it('copies the style, the Show choice and the changes made only for those plates', function()
		Seed()
		assert.is_true(W.CopyKind('enemyPlayer', 'friendlyNPC'))
		assert.equal(W.Style('friendlyNPC'), 'mini')
		assert.equal(W.Mode('friendlyNPC'), 'name')
		assert.same(Store:Get({ 'tweaks', 'clean', 'situations', 'friendlyNPC' }), { hide = { 'cast' } })
		assert.same(Store:Get({ 'tweaks', 'mini', 'situations', 'friendlyNPC' }), { hide = { 'marker' } })
		assert.same(Store:Get({ 'tweaks', 'clean', 'situations', 'enemyPlayer' }), { hide = { 'cast' } }, 'the source keeps its own')
	end)

	it('copies copies, not references', function()
		Seed()
		W.CopyKind('enemyPlayer', 'friendlyNPC')
		Store:Set({ 'tweaks', 'clean', 'situations', 'friendlyNPC', 'hide' }, { 'name' })
		assert.same(Store:Get({ 'tweaks', 'clean', 'situations', 'enemyPlayer', 'hide' }), { 'cast' })
	end)

	it('replaces what the target had, including nothing', function()
		Seed()
		Store:Set({ 'tweaks', 'clean', 'situations', 'friendlyNPC' }, { hide = { 'name' } })
		W.CopyKind('minor', 'friendlyNPC')
		assert.same(Store:Get({ 'tweaks', 'clean', 'situations', 'friendlyNPC' }), { hide = { 'power' } })
		assert.is_nil(Store:Get({ 'tweaks', 'mini', 'situations', 'friendlyNPC' }), 'minor has none for Mini, so the copy has none')
	end)

	it('does nothing for the same kind or an unknown one', function()
		Seed()
		assert.is_false(W.CopyKind('minor', 'minor'))
		assert.is_false(W.CopyKind('minor', 'nobody'))
		assert.is_false(W.CopyKind('nobody', 'minor'))
	end)

	it('copies in one change', function()
		Seed()
		local count = 0
		P:On('STORE_CHANGED', function()
			count = count + 1
		end, Seed)
		W.CopyKind('enemyPlayer', 'friendlyNPC')
		P:Off('STORE_CHANGED', Seed)
		assert.equal(count, 1)
	end)

	it('puts one kind back to the defaults', function()
		Seed()
		W.ResetKind('enemyPlayer')
		assert.equal(W.Style('enemyPlayer'), 'host')
		assert.equal(W.Mode('enemyPlayer'), 'full')
		assert.is_nil(Store:Get({ 'tweaks', 'clean', 'situations', 'enemyPlayer' }))
		assert.is_nil(Store:Get({ 'tweaks', 'mini', 'situations', 'enemyPlayer' }))
		assert.same(Store:Get({ 'tweaks', 'clean', 'situations', 'minor' }), { hide = { 'power' } }, 'other kinds are untouched')
		W.ResetKind('minor')
		assert.is_nil(Store:Get('tweaks'), 'no empty tables are left')
		W.ResetKind('nobody')
	end)

	it('works through the page controls', function()
		Seed()
		local copy = Group(Page(), 'copy')
		assert.is_true(copy.advanced)
		assert.equal(copy.args.target.get({}), 'friendlyPlayer')
		assert.equal(copy.args.source.get({}), 'enemyPlayer')
		copy.args.target.set({}, 'friendlyNPC')
		copy.args.copy.func()
		assert.equal(W.Style('friendlyNPC'), 'mini')
		copy.args.source.set({}, 'friendlyNPC')
		assert.is_true(copy.args.copy.disabled({}), 'a kind cannot copy itself')
		assert.equal(type(copy.args.reset.confirmText), 'string', 'AceConfig needs a plain string here')
		assert.is_true(copy.args.reset.confirm)
		copy.args.reset.func()
		assert.equal(W.Style('friendlyNPC'), 'host')
		assert.same(Sorted(copy.args.target.values), Sorted(WB.KIND_LABELS))
	end)
end)

describe('who and where: restoring the game', function()
	before_each(Reset)

	it('keeps the old button working', function()
		M.SetCVarState('nameplateShowEnemies', { value = '1', default = '1' })
		ClearMockCVars()
		CVars:Set('nameplateShowEnemies', '0')
		local button = Group(Page(), 'games').args.restore
		button.func()
		assert.equal(C_CVar.GetCVar('nameplateShowEnemies'), '1')
	end)
end)

describe('who and where: pending writes and fresh callbacks', function()
	before_each(Reset)

	it('gets settings from every registry page, including internal settings', function()
		M.SetCVarState('nameplateSelectedScale', { value = '1', default = '1' })
		M.SetCVarState('nameplateMinScale', { value = '1', default = '1' })
		ClearMockCVars()
		CVars:Set('nameplateSelectedScale', 1.2)
		CVars:Set('nameplateMinScale', 0.8)
		local called, original = {}, CVars.List
		CVars.List = function(self, page)
			called[page or 'internal'] = true
			return original(self, page)
		end
		local rows = W.GameRows()
		CVars.List = original
		assert.is_true(called.whoAndWhere)
		assert.is_true(called.style)
		assert.is_true(called.internal)
		assert.equal(#rows, 2)
		local cells = Group(Page(), 'games', 'table').args
		assert.equal(cells.nameplateSelectedScale_now.name(), '1.2')
		assert.equal(cells.nameplateMinScale_now.name(), '0.8')
	end)

	it('shows pending writes before they have a backup and clears the note after combat', function()
		M.SetCVarState('nameplateMaxDistance', { value = '60', default = '60', secure = true })
		ClearMockCVars()
		local games = Group(Page(), 'games')
		M.EnterCombat()
		CVars:Set('nameplateMaxDistance', 45, 'player')
		assert.is_nil(CVars:GetBackup('nameplateMaxDistance'))
		assert.equal(W.GameRow('nameplateMaxDistance').now, '60 (waiting for combat to end)')
		assert.is_false(games.args.waiting.hidden())
		assert.equal(games.args.waiting.name(), 'Some settings take effect when combat ends.')
		M.LeaveCombat()
		assert.equal(W.GameRow('nameplateMaxDistance').now, '45')
		assert.equal(W.GameRow('nameplateMaxDistance').was, '60')
		assert.is_true(games.args.waiting.hidden())
	end)

	it('lists a queued stacking bit before its first write', function()
		M.SetCVarState('nameplateStackingTypes', { value = '0', default = '0', secure = true })
		ClearMockCVars()
		M.EnterCombat()
		CVars:SetBit('nameplateStackingTypes', 'enemy', true, 'player')
		assert.is_true(W.GamePending('nameplateStackingTypes'))
		assert.equal(W.GameRow('nameplateStackingTypes').now, 'none (waiting for combat to end)')
		assert.is_false(Group(Page(), 'games', 'table').args.nameplateStackingTypes_now.hidden())
		M.LeaveCombat()
		assert.is_false(W.GamePending('nameplateStackingTypes'))
		assert.equal(W.GameRow('nameplateStackingTypes').now, 'enemies')
	end)

	it('rejects assignment callbacks that arrive after the controls lock', function()
		Store:Set('when', { { conditions = {}, style = 'clean' } })
		W.editing = 1
		M.EnterCombat()
		W.SetStyle('enemyPlayer', 'mini')
		W.SetMode('enemyPlayer', 'hidden')
		W.SameAsEnemies('minor')
		W.CopyKind('minor', 'enemyNPC')
		W.ResetKind('minor')
		W.SetEditedEntry({ conditions = {}, mode = 'hidden' })
		W.ApplyWhenChange({ order = {}, rows = {} })
		assert.is_nil(Store:Get('assign'))
		assert.is_nil(Store:Get('modes'))
		assert.equal(Store:Get('when')[1].style, 'clean')
		assert.equal(W.editing, 1)
		M.LeaveCombat()
	end)

	it('keeps the editor on the retained row when a stale row is skipped', function()
		Store:Set('when', { { conditions = {}, style = 'clean' }, { conditions = {}, mode = 'name' } })
		W.editing = 2
		W.ApplyWhenChange({ order = { 'gone', 'w2', 'w1' }, rows = { {}, { on = true }, { on = true } } })
		assert.equal(W.editing, 1)
		assert.equal(W.EditedEntry().mode, 'name')
	end)

	it('lets place settings wait for combat like other behavior choices', function()
		local cell = Group(Page(), 'places', 'raid').args.enemies
		M.EnterCombat()
		assert.is_false(cell.disabled())
		cell.set({}, 'combat')
		assert.equal(Store:Get({ 'behavior', 'places', 'raid', 'enemies' }), 'combat')
		M.LeaveCombat()
	end)

	it('closes the editor when the profile changes', function()
		Store:Set('when', { { conditions = {}, style = 'clean' } })
		W.editing = 1
		P.db:SetProfile('Other who and where profile')
		assert.is_nil(W.editing)
		assert.is_nil(W.EditedEntry())
		P.db:SetProfile('Default')
	end)
end)

describe('who and where: client badges', function()
	before_each(Reset)
	it('keeps a valid client limit visible on a special case row', function()
		P.Conditions:Register({
			id = 'limitedPlaceForPage',
			kind = 'plain',
			label = 'In this place',
			limits = { [P.Caps:Client()] = 'Only in the open world here' },
			Test = function()
				return true
			end,
		})
		Store:Set('when', { { conditions = { { id = 'limitedPlaceForPage' } }, mode = 'name' } })
		assert.equal(W.WhenRows()[1].badge, 'Only in the open world here')
		assert.same(WB:Problems(Store:Get('when')[1], 'layout'), {})
	end)
end)

describe('who and where: imported long special cases', function()
	before_each(Reset)
	it('rebuilds the editor when opening a list entry with extra conditions', function()
		local previous = P.host.RefreshOptions
		P.host.RefreshOptions = function() end
		P:BuildOptionsTable()
		local conditions = {
			{ id = 'place', args = 'raid' },
			{ id = 'role', args = 'tank' },
			{ id = 'elite' },
			{ id = 'canAttack' },
			{ id = 'inGroup' },
			{ id = 'myCombat' },
		}
		Store:Set('when', { { conditions = conditions, mode = 'name' } })
		W.ToggleEditing('w1')
		assert.is_true(P.Options.rebuildWanted)
		local editor = Group(Page(), 'when', 'editor')
		assert.not_nil(editor.args.conditions.args.condition6)
		editor.args.conditions.args.condition6.set({}, 'remove')
		assert.equal(#Store:Get('when')[1].conditions, 5)
		M.Advance(0.1)
		P.host.RefreshOptions = previous
	end)
end)
