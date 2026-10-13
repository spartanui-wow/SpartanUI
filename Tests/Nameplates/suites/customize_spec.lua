-- @runtime lua51
local M, H = ...

if not H.ModuleExists() then
	describe('customize page', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

M.Login('NameplatesTestHost')
local opened
local P = H.FreshCore({
	host = {
		GetHostProfileName = function()
			return 'Default'
		end,
		OpenOptions = function(page)
			opened = page
		end,
	},
})
P.services.GetAccent = function()
	return 1, 1, 1
end
P.services.FontPath = function()
	return 'Fonts\\Test.ttf'
end
local D, C = P.Designer, P.CustomizePage
local info = {}
local locked = false
P.Secret.IsRestricted = function()
	return locked
end

local function Page()
	return P:BuildOptionsTable().args.customize
end

local function Args(id)
	return Page().args['part_' .. id].args
end

local function Change(id, field)
	local path = { 'tweaks', 'clean', 'changes', 'parts', id }
	for key in string.gmatch(field or '', '[^.]+') do
		path[#path + 1] = key
	end
	return P.Store:Get(path)
end

local function Row(key)
	for _, row in ipairs(C.Rows()) do
		if row.key == key then
			return row
		end
	end
	assert.fail('Missing row: ' .. key)
end

local function Widget()
	P.Widgets:Register()
	local w = P.Widgets:Create('PartList')
	if not w then
		skip('PartList widget unavailable')
		return
	end
	w:SetCustomData({ rows = C.Rows })
	w:SetValue(nil)
	return w
end

local function NameRow(w)
	for _, row in ipairs(w.rows) do
		if row.data and row.data.id == 'name' then
			return row
		end
	end
	assert.fail('Missing name widget row')
end

describe('customize page', function()
	before_each(function()
		P.Store:Set('tweaks', nil)
		P.Store:Set('style', 'clean')
		P.Store:Set('colors', nil)
		D.history:Clear()
		P.util.Wipe(D.state.selection)
		D:SetScope('all')
		D.state.kind = 'enemyNPC'
		locked = false
		opened = nil
	end)

	it('builds an inline group for every clean part', function()
		local page = Page()
		assert.equal(page.type, 'group')
		for id in pairs(D:Parts()) do
			local group = page.args['part_' .. id]
			assert.not_nil(group, id)
			assert.equal(group.type, 'group')
			assert.is_true(group.inline)
		end
	end)

	it('hides every part group until a part is selected', function()
		local page = Page()
		for id in pairs(D:Parts()) do
			assert.is_true(page.args['part_' .. id].hidden(), id)
		end
		D:Select('name')
		for id in pairs(D:Parts()) do
			assert.equal(page.args['part_' .. id].hidden(), id ~= 'name', id)
		end
	end)

	it('labels every part in the parts option', function()
		local values = Page().args.parts.values()
		for id in pairs(D:Parts()) do
			assert.equal(type(values[id]), 'string', id)
			assert.not_equal(values[id], '', id)
		end
	end)

	it('selects a part and reads the primary selection', function()
		local option = Page().args.parts
		assert.equal(option.get(info), D:Primary())
		option.set(info, 'name')
		assert.equal(D:Primary(), 'name')
		assert.equal(option.get(info), 'name')
	end)

	it('hides and restores hp through the parts option', function()
		local option = Page().args.parts
		option.set(info, 'hide:hp')
		assert.is_true(Change('hp', 'hidden'))
		option.set(info, 'show:hp')
		assert.is_nil(Change('hp', 'hidden'))
	end)

	it('hides and restores the cast icon through the parts option', function()
		local option = Page().args.parts
		option.set(info, 'hide:cast:icon')
		assert.equal(Change('cast', 'icon'), 'none')
		option.set(info, 'show:cast:icon')
		assert.is_nil(Change('cast', 'icon'))
	end)

	it('starts rows with a header and includes every part', function()
		assert.not_nil(C.Rows()[1].header)
		for id in pairs(D:Parts()) do
			assert.equal(Row(id).id, id)
		end
	end)

	it('orders row groups according to Designer groups', function()
		local present, expected, actual = {}, {}, {}
		for id, spec in pairs(D:Parts()) do
			local group = D.PartInfo(id, spec)
			present[group] = true
		end
		for _, group in ipairs(D.GROUPS) do
			if present[group] then
				expected[#expected + 1] = D.GROUP_LABELS[group]
			end
		end
		for _, row in ipairs(C.Rows()) do
			if row.header then
				actual[#actual + 1] = row.header
			end
		end
		assert.same(actual, expected)
	end)

	it('includes cast feature sub rows', function()
		for _, key in ipairs({ 'cast:icon', 'cast:nameText', 'cast:target' }) do
			assert.is_true(Row(key).sub)
			assert.equal(Row(key).id, 'cast')
		end
	end)

	it('includes the health absorb sub row', function()
		assert.is_true(Row('health:absorb').sub)
		assert.equal(Row('health:absorb').id, 'health')
	end)

	it('marks the selected part row', function()
		D:Select('name')
		assert.is_true(Row('name').selected)
		assert.is_false(Row('hp').selected)
	end)

	it('marks a hidden part as not shown', function()
		Page().args.parts.set(info, 'hide:hp')
		assert.is_false(Row('hp').shown)
	end)

	it('locks health with a badge on friendly players', function()
		D:SetPreviewKind('friendlyPlayer')
		assert.is_true(Row('health').locked)
		assert.equal(type(Row('health').badge), 'string')
		assert.not_equal(Row('health').badge, '')
	end)

	it('writes name text size as an undoable overlay', function()
		Args('name').fontSize.set(info, 14)
		assert.equal(Change('name', 'font.size'), 14)
		assert.is_true(D:CanUndo())
	end)

	it('preserves the empty outline flag', function()
		Args('name').outline.set(info, '')
		assert.equal(Change('name', 'font.flags'), '')
	end)

	it('switches the scope toggle in both directions', function()
		local option = Args('name').scope
		assert.is_false(option.get(info))
		option.set(info, true)
		assert.equal(D:Scope(), 'kind')
		assert.is_true(option.get(info))
		option.set(info, false)
		assert.equal(D:Scope(), 'all')
	end)

	it('writes kind scoped text size without whole style changes', function()
		local args = Args('name')
		args.scope.set(info, true)
		D:SetPreviewKind('enemyPlayer')
		args.fontSize.set(info, 14)
		assert.equal(P.Store:Get({ 'tweaks', 'clean', 'situations', 'enemyPlayer', 'parts', 'name', 'font', 'size' }), 14)
		assert.is_nil(Change('name'))
		assert.is_false(args.scopedNote.hidden())
		assert.is_false(args.resetScoped.hidden())
	end)

	it('resets the scoped part while preserving whole style edits', function()
		local args = Args('name')
		assert.is_true(args.scopedNote.hidden())
		assert.is_true(args.resetScoped.hidden())
		args.outline.set(info, '')
		args.scope.set(info, true)
		D:SetPreviewKind('enemyPlayer')
		args.fontSize.set(info, 14)
		args.resetScoped.func()
		assert.is_nil(P.Store:Get({ 'tweaks', 'clean', 'situations', 'enemyPlayer', 'parts', 'name' }))
		assert.equal(Change('name', 'font.flags'), '')
		assert.is_true(args.scopedNote.hidden())
		assert.is_true(args.resetScoped.hidden())
	end)

	it('reads and changes the name anchor cell', function()
		local option = Args('name').position
		assert.equal(option.get(info), 'TOPLEFT')
		option.set(info, 'TOPRIGHT')
		assert.equal(Change('name', 'anchor')[3], 'TOPRIGHT')
	end)

	it('nudges half a pixel and resets the anchor offset', function()
		local option = Args('name').position
		if not option.arg then
			skip('AnchorGrid unavailable')
			return
		end
		local x, y = option.arg.offset()
		option.arg.onNudge(0.5, 0)
		local nx, ny = option.arg.offset()
		assert.equal(nx, x + 0.5)
		assert.equal(ny, y)
		assert.equal(Change('name', 'anchor')[4], nx)
		option.arg.onReset()
		nx, ny = option.arg.offset()
		assert.equal(nx, 0)
		assert.equal(ny, 0)
	end)

	it('reads cast audiences and enables friendly casts', function()
		local option = Args('cast').showOn
		assert.is_true(option.get(info, 'enemies'))
		assert.is_false(option.get(info, 'friends'))
		option.set(info, 'friends', true)
		assert.is_true(Change('cast', 'friends'))
	end)

	it('toggles interrupt color in profile colors', function()
		local option = Args('cast').interruptColor
		assert.is_true(option.get(info))
		option.set(info, false)
		assert.is_true(P.Store:Get({ 'colors', 'cast', 'off', 'interruptReady' }))
		option.set(info, true)
		assert.is_nil(P.Store:Get({ 'colors', 'cast', 'off', 'interruptReady' }))
	end)

	it('changes the interrupt mark from line to fill and off', function()
		local option = Args('cast').kickMark
		assert.equal(option.get(info), 'line')
		option.set(info, 'fill')
		assert.is_true(Change('cast', 'kickFill'))
		assert.equal(option.get(info), 'fill')
		option.set(info, 'off')
		assert.is_false(Change('cast', 'kickMark'))
		assert.equal(option.get(info), 'off')
	end)

	it('writes cast width only when not matching the bar', function()
		local option = Args('cast').sameWidth
		assert.is_true(option.get(info))
		option.set(info, false)
		assert.equal(type(Change('cast', 'width')), 'number')
		assert.is_false(option.get(info))
		option.set(info, true)
		assert.is_nil(Change('cast', 'width'))
	end)

	it('writes aura row maximum and size', function()
		local args = Args('mine')
		args.max.set(info, 8)
		args.size.set(info, 26)
		assert.equal(Change('mine', 'max'), 8)
		assert.equal(Change('mine', 'size'), 26)
	end)

	it('moves the aura row to the left of the same target', function()
		local option = Args('mine').side
		local target = D:Spec('mine').anchor[2]
		assert.equal(option.get(info), 'above')
		option.set(info, 'left')
		assert.same(Change('mine', 'anchor'), { 'RIGHT', target, 'LEFT', -4, 0 })
		assert.equal(Change('mine', 'grow'), 'LEFT')
	end)

	it('locks aura maximum and shows the restricted note', function()
		local args = Args('mine')
		assert.is_false(args.max.disabled())
		assert.is_true(args.lockNote.hidden())
		locked = true
		assert.is_true(args.max.disabled())
		assert.is_false(args.lockNote.hidden())
	end)

	it('writes the target highlight art', function()
		Args('arrows').art.set(info, 'brackets')
		assert.equal(Change('arrows', 'art'), 'brackets')
	end)

	it('disables and restores target growth', function()
		local option = Args('arrows').bigger
		assert.is_true(option.get(info))
		option.set(info, false)
		assert.same(P.Store:Get({ 'tweaks', 'clean', 'changes', 'states', 'target', 'grow' }), { 0, 0 })
		option.set(info, true)
		assert.is_nil(P.Store:Get({ 'tweaks', 'clean', 'changes', 'states', 'target', 'grow' }))
	end)

	it('disables fading and reads full opacity during casting', function()
		local args = Args('arrows')
		assert.is_true(args.fade.get(info))
		assert.is_true(args.castFull.get(info))
		args.fade.set(info, false)
		assert.equal(P.Store:Get({ 'tweaks', 'clean', 'changes', 'states', 'notTarget', 'alpha' }), 1)
	end)

	it('reads health colors and opens the host colors page', function()
		local args = Args('health')
		assert.equal(args.colors.get(info), 'health')
		args.colorLink.func()
		assert.equal(opened, 'colors')
	end)

	it('resets every whole and scoped change of one part', function()
		local args = Args('name')
		assert.is_true(args.reset.hidden())
		args.fontSize.set(info, 14)
		args.outline.set(info, '')
		args.scope.set(info, true)
		D:SetPreviewKind('enemyPlayer')
		args.fontSize.set(info, 16)
		assert.is_false(args.reset.hidden())
		args.reset.func()
		assert.is_nil(Change('name'))
		assert.is_nil(P.Store:Get({ 'tweaks', 'clean', 'situations', 'enemyPlayer', 'parts', 'name' }))
		assert.is_true(args.reset.hidden())
	end)

	it('puts common controls under More settings for every part', function()
		for id in pairs(D:Parts()) do
			local args = Args(id)
			for _, key in ipairs({ 'layer', 'alpha', 'pixelSnap', 'label' }) do
				assert.is_true(args[key].advanced, id .. ':' .. key)
			end
			-- Only the cast bar can be lifted above other plates: no toggle that does nothing
			if D:Parts()[id].kind == 'cast' then
				assert.is_true(args.above.advanced, id .. ':above')
			else
				assert.is_nil(args.above, id .. ' offers no lift toggle')
			end
		end
	end)

	it('trims and clears the part label', function()
		local option = Args('name').label
		option.set(info, '  Boss name  ')
		assert.equal(Change('name', 'label'), 'Boss name')
		option.set(info, '')
		assert.is_nil(Change('name', 'label'))
	end)

	it('excludes itself and descendants from anchor targets', function()
		local values = Args('name').hangsFrom.values()
		assert.not_nil(values.plate)
		assert.is_nil(values.name)
		assert.is_nil(values.mine)
		for id in pairs(D.Descendants(D:Parts(), 'name')) do
			assert.is_nil(values[id], id)
		end
	end)

	it('adds selects and removes a new text part', function()
		Page().args.addPart.set(info, 'text')
		assert.not_nil(P.Store:Get({ 'tweaks', 'clean', 'add', 'text1' }))
		assert.equal(D:Primary(), 'text1')
		local reset = Args('text1').reset
		assert.is_false(reset.hidden())
		assert.equal(reset.name(), 'Remove this part')
		reset.func()
		assert.is_nil(P.Store:Get({ 'tweaks', 'clean', 'add', 'text1' }))
		assert.is_nil(D:Parts().text1)
	end)

	it('undoes and redoes through execute options', function()
		local page = Page()
		assert.equal(page.args.undo.disabled(), not D:CanUndo())
		assert.equal(page.args.redo.disabled(), not D:CanRedo())
		Args('name').fontSize.set(info, 14)
		assert.is_false(page.args.undo.disabled())
		page.args.undo.func()
		assert.is_nil(Change('name', 'font.size'))
		assert.is_true(page.args.undo.disabled())
		assert.is_false(page.args.redo.disabled())
		page.args.redo.func()
		assert.equal(Change('name', 'font.size'), 14)
		assert.is_false(page.args.undo.disabled())
		assert.is_true(page.args.redo.disabled())
	end)

	it('loads all Customize rows into the PartList widget', function()
		local w = Widget()
		if not w then
			return
		end
		local items = P.util.Copy(w.items)
		LibStub('AceGUI-3.0'):Release(w)
		assert.equal(#items, #C.Rows())
		assert.same(items, C.Rows())
	end)

	it('fires selection and eye values from PartList clicks', function()
		local w = Widget()
		if not w then
			return
		end
		local got
		w:SetCallback('OnValueChanged', function(_, _, value)
			got = value
		end)
		local row = NameRow(w)
		row:GetScript('OnClick')(row)
		local picked = got
		row.eye.onClick(row.eye)
		local eye = got
		LibStub('AceGUI-3.0'):Release(w)
		assert.equal(picked, 'name')
		assert.equal(eye, 'hide:name')
	end)

	it('shows Blank only when registered and saves a new profile style', function()
		local registry = P.Styles.Registry
		-- The Blank built-in may already ship (Core/Styles/Builtin_Blank.lua); take it away to check the gate
		local shipped = registry.builtin.blank
		registry.builtin.blank = nil
		assert.is_nil(registry:Get('blank'))
		assert.is_true(Page().args.blank.hidden())
		registry.builtin.blank = shipped
		if not shipped then
			registry:RegisterBuiltin({
				id = 'blank',
				name = 'Blank',
				version = 1,
				schema = 1,
				parts = { health = { kind = 'bar', source = 'health', fill = 'plate', anchor = { 'CENTER', 'plate', 'CENTER', 0, 0 } } },
			})
		end
		assert.not_nil(registry:Get('blank'))
		assert.is_false(Page().args.blank.hidden())
		C.StartBlank()
		local id = P.Store:Get('style')
		assert.not_equal(id, 'clean')
		assert.not_equal(id, 'blank')
		assert.not_nil(P.Store:Get('styles', 'global')[id])
		assert.is_true(registry:IsSaved(id))
	end)
end)

describe('customize page: rules', function()
	local function Main(args)
		local count = 0
		for _, option in pairs(args) do
			if option.type ~= 'description' and option.type ~= 'header' and not option.advanced then
				count = count + 1
			end
		end
		return count
	end

	it('keeps to eight main controls on the page and in every part group', function()
		P.Store:Set('style', 'clean')
		P.Store:Set('tweaks', nil)
		local page = P:BuildOptionsTable().args.customize
		local top = {}
		for key, option in pairs(page.args) do
			if option.type ~= 'group' then
				top[key] = option
			end
		end
		assert.truthy(Main(top) <= 8, 'page has ' .. Main(top) .. ' main controls')
		for key, option in pairs(page.args) do
			if option.type == 'group' then
				local count = Main(option.args)
				assert.truthy(count <= 8, key .. ' has ' .. count .. ' main controls')
			end
		end
	end)

	it('uses plain words: no dashes or symbols outside ASCII in names', function()
		local page = P:BuildOptionsTable().args.customize
		local function Check(args, path)
			for key, option in pairs(args) do
				local name = option.name
				if type(name) == 'function' then
					local ok, value = pcall(name, {})
					name = ok and value or nil
				end
				if type(name) == 'string' then
					assert.is_nil(string.find(name, '[\128-\255]'), path .. key .. ' name has a non-ASCII character')
				end
				if option.type == 'group' and option.args then
					Check(option.args, path .. key .. '.')
				end
			end
		end
		Check(page.args, '')
	end)
end)

describe('customize: aura text', function()
	before_each(function()
		locked = false
		P.Store:Set('style', 'clean')
		P.Store:Set('tweaks', nil)
		D.history:Clear()
		D:SetScope('all')
		D.state.kind = 'enemyNPC'
	end)

	it('has one advanced section with grids, independent sizes and reset', function()
		local group = Args('mine').auraText
		assert.equal(group.name, 'Aura text')
		assert.is_true(group.advanced)
		local args = group.args
		assert.equal(args.timerPosition.dialogControl, P.Widgets:TypeName('AnchorGrid'))
		assert.equal(args.timerSize.get(), 9)
		assert.equal(args.stackSize.get(), 9)
		args.timerPosition.set(info, 'TOP')
		args.stackPosition.arg.onNudge(-2, 0.5)
		args.timerSize.set(info, 15)
		assert.same(D:AuraText('mine', 'timerAnchor'), { point = 'TOP', relPoint = 'TOP', x = 0, y = 0, size = 15 })
		assert.equal(D:AuraText('mine', 'stackAnchor').x, -1)
		assert.equal(args.stackSize.get(), 9)
		assert.is_nil(Args('mine').fontSize, 'size settings have one home')
	end)

	it('reads saved callbacks from the current profile and scope each time', function()
		local args = Args('mine').auraText.args
		args.timerSize.set(info, 15)
		P.Store:Set('tweaks', nil)
		assert.equal(args.timerSize.get(), 9)
		D:SetScope('kind')
		D:SetPreviewKind('enemyPlayer')
		args.stackPosition.set(info, 'LEFT')
		assert.equal(P.Store:Get('tweaks.clean.situations.enemyPlayer.parts.mine.stackAnchor.point'), 'LEFT')
		assert.is_nil(Change('mine'))
	end)

	it('rejects stale setters, nudges and resets while restricted', function()
		local group = Args('mine').auraText
		local args = group.args
		args.timerPosition.arg.onNudge(3, 0)
		local before = P.util.Copy(P.Store:Get('tweaks.clean'))
		local steps = #D.history.undo
		locked = true
		assert.is_true(group.disabled())
		args.timerPosition.set(info, 'BOTTOM')
		args.timerPosition.arg.onNudge(2, 0)
		args.timerPosition.arg.onReset()
		args.stackSize.set(info, 16)
		args.reset.func()
		assert.same(P.Store:Get('tweaks.clean'), before)
		assert.equal(#D.history.undo, steps)
		locked = false
	end)

	it('resets both text positions and sizes but keeps other row changes', function()
		local args = Args('mine').auraText.args
		Args('mine').size.set(info, 26)
		args.timerSize.set(info, 15)
		args.stackPosition.set(info, 'TOPLEFT')
		args.reset.func()
		assert.is_nil(Change('mine', 'timerAnchor'))
		assert.is_nil(Change('mine', 'stackAnchor'))
		assert.equal(Change('mine', 'size'), 26)
		D:Undo()
		assert.equal(args.timerSize.get(), 15)
		assert.equal(args.stackPosition.get(), 'TOPLEFT')
	end)
end)

describe('customize: stale aura text controls', function()
	it('keeps old getters safe after an added aura row is removed', function()
		locked = false
		P.Store:Set('style', 'clean')
		P.Store:Set('tweaks', nil)
		D:SetScope('all')
		local id = D:AddPart('auras')
		local args = Args(id).auraText.args
		D:RemovePart(id)
		assert.equal(args.timerPosition.get(), 'CENTER')
		assert.equal(args.timerSize.get(), 9)
		assert.same({ args.stackPosition.arg.offset() }, { 0, 0 })
		args.timerSize.set(info, 18)
		assert.is_nil(P.Store:Get('tweaks.clean'))
	end)
end)
