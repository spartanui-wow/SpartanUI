-- @runtime lua51
-- The core's options widgets (plan 3.2, 6.1, 6.11): AnchorGrid, RuleList and SpellList, registered
-- with AceGUI under the host's prefix and driven the way AceConfig and players drive them. Runs on
-- every flavor, so atlas, font and spell lookups are checked against each client's API list.
local M, H = ...

if not H.ModuleExists() then
	describe('options widgets', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

H.LoadLibs()
H.InstallLibATStub()
local ns = H.LoadCore({ libs = false })
local P = ns.Plates
P:Initialize(H.HostStub())
local AceGUI = LibStub('AceGUI-3.0')
local Widgets = P.Widgets
local Draw = Widgets.Draw
local PREFIX = H.HostStub().widgetPrefix

local function click(frame, button)
	M.RunScript(frame, 'OnClick', button or 'LeftButton', false)
end

local function create(name)
	local widget = Widgets:Create(name)
	assert.not_nil(widget, 'Widgets:Create(' .. name .. ')')
	widget.frame:SetParent(UIParent)
	widget.frame:Show()
	return widget
end

local function release(widget)
	if widget and not widget.isQueuedForRelease then
		AceGUI:Release(widget)
	end
	Draw.CloseMenu()
end

local function contains(list, value)
	for _, v in ipairs(list or {}) do
		if v == value then
			return true
		end
	end
	return false
end

local function itemValues(items)
	local out = {}
	for i, item in ipairs(items or {}) do
		out[i] = item.value
	end
	return out
end

describe('widget registry', function()
	it('registers the three types under the host prefix', function()
		Widgets:Register()
		for _, name in ipairs({ 'AnchorGrid', 'RuleList', 'SpellList' }) do
			assert.is_true(Widgets:Has(name), name .. ' is built')
			assert.equal(Widgets:TypeName(name), PREFIX .. name)
			assert.equal(AceGUI:GetWidgetVersion(PREFIX .. name), 1, PREFIX .. name .. ' registered')
		end
	end)

	it('creates no named frames, events or hooks when widgets are made and released', function()
		M.ResetRecords()
		for _, name in ipairs({ 'AnchorGrid', 'RuleList', 'SpellList' }) do
			release(create(name))
		end
		assert.empty(M.rec.globals, 'named frames')
		assert.empty(M.rec.events, 'registered events')
		assert.empty(M.rec.hooks, 'hooks')
	end)

	it('reads kit colors and the accent as numbers, with or without real LibAT colors', function()
		local r, g, b, a = Draw.Color('text')
		assert.equal(type(r), 'number')
		assert.equal(type(g), 'number')
		assert.equal(type(b), 'number')
		assert.equal(type(a), 'number')
		local ar, ag, ab = Draw.Accent()
		assert.equal(type(ar), 'number')
		assert.equal(type(ag), 'number')
		assert.equal(type(ab), 'number')
		assert.equal(type(Draw.FontFace()), 'string')
	end)

	it('falls back to texture files when the client lacks an atlas', function()
		local tex = UIParent:CreateTexture(nil, 'ARTWORK')
		M.missingAtlases = { ['common-icon-redx'] = true }
		Draw.ForgetAtlases()
		Draw.Icon(tex, 'remove')
		assert.equal(M.Get(tex, 'texture'), Draw.ICONS.remove.file)
		assert.is_nil(M.Get(tex, 'atlas'))
		M.missingAtlases = nil
		Draw.ForgetAtlases()
		Draw.Icon(tex, 'remove')
		assert.equal(M.Get(tex, 'atlas'), 'common-icon-redx')
		Draw.Icon(tex, 'unknown')
		assert.equal(M.Get(tex, 'texture'), Draw.ICONS.unknown.file)
	end)
end)

describe('AnchorGrid', function()
	local widget
	after_each(function()
		release(widget)
		widget = nil
	end)

	it('picks a point and fires OnValueChanged', function()
		widget = create('AnchorGrid')
		widget:SetList({ CENTER = 'Center' })
		widget:SetValue('CENTER')
		assert.equal(widget:GetValue(), 'CENTER')
		local got
		widget:SetCallback('OnValueChanged', function(_, _, point)
			got = point
		end)
		click(widget.cells[1])
		assert.equal(got, 'TOPLEFT')
		assert.equal(widget:GetValue(), 'TOPLEFT')
		widget:SetValue('NOTAPOINT')
		assert.is_nil(widget:GetValue())
	end)

	it('nudges through arg.onNudge, reads the offset back and repeats while held', function()
		widget = create('AnchorGrid')
		local x, y = 0, 0
		widget:SetCustomData({
			onNudge = function(dx, dy)
				x, y = x + dx, y + dy
			end,
			offset = function()
				return x, y
			end,
		})
		local up = widget.nudges[1]
		M.RunScript(up, 'OnMouseDown', 'LeftButton')
		assert.equal(y, 0.5)
		M.RunScript(up, 'OnMouseUp', 'LeftButton')
		assert.equal(M.Get(widget.yText, 'text'), 'Y 0.5')
		widget:Nudge(1, 0, true)
		assert.equal(x, 2)
		assert.equal(M.Get(widget.xText, 'text'), 'X 2')

		M.RunScript(up, 'OnMouseDown', 'LeftButton')
		M.Advance(0.7)
		assert.truthy(y > 1, 'holding the arrow keeps nudging')
		M.RunScript(up, 'OnMouseUp', 'LeftButton')
		assert.is_false(contains(M.ActiveOnUpdates(), up), 'the repeat stops on release')

		widget:ResetOffset()
		assert.equal(x, 0)
		assert.equal(y, 0)
		assert.equal(M.Get(widget.xText, 'text'), 'X 0')
	end)

	it('keeps its own offset and fires callbacks when no arg is given', function()
		widget = create('AnchorGrid')
		local moved
		widget:SetCallback('OnOffsetChanged', function(_, _, x, y)
			moved = { x, y }
		end)
		widget:SetValue({ point = 'LEFT', x = 1, y = -1 })
		widget:Nudge(-1, 0)
		assert.same(moved, { 0.5, -1 })
		assert.equal(widget:GetValue(), 'LEFT')
	end)

	it('ignores clicks and nudges while disabled', function()
		widget = create('AnchorGrid')
		local nudged, changed = false, false
		widget:SetCustomData({
			onNudge = function()
				nudged = true
			end,
		})
		widget:SetCallback('OnValueChanged', function()
			changed = true
		end)
		widget:SetDisabled(true)
		click(widget.cells[5])
		M.RunScript(widget.nudges[2], 'OnMouseDown', 'LeftButton')
		assert.is_false(changed)
		assert.is_false(nudged)
		assert.is_false(contains(M.ActiveOnUpdates(), widget.nudges[2]))
	end)

	it('survives being released by its own nudge', function()
		widget = create('AnchorGrid')
		local w = widget
		widget:SetCustomData({
			onNudge = function()
				AceGUI:Release(w)
			end,
		})
		widget = nil
		M.RunScript(w.nudges[1], 'OnMouseDown', 'LeftButton')
		assert.is_false(contains(M.ActiveOnUpdates(), w.nudges[1]))
	end)
end)

local function sampleRows()
	return {
		{ id = 'tapped', sentence = 'Gray when someone else tagged it first', color = { 0.5, 0.5, 0.5, 1 }, when = 'everywhere' },
		{
			id = 'threat',
			sentence = 'Threat colors',
			colors = { { key = 'safe', label = 'Safe', color = { 0, 1, 0, 1 } }, { key = 'lost', label = 'Lost it', color = { 1, 0, 0, 1 } } },
			when = 'instances',
			badge = 'Retail: only in the open world',
		},
		{ id = 'class', sentence = 'Class color', color = { 1, 1, 0, 1 }, when = 'everywhere', removable = true },
	}
end

describe('RuleList', function()
	local widget, stored, last, arg

	before_each(function()
		stored = sampleRows()
		last = nil
		arg = {
			header = 'When more than one color fits, the top one wins.',
			rows = function()
				return stored
			end,
			onChange = function(change)
				stored = change.rows
				last = change
			end,
		}
		widget = create('RuleList')
		widget:SetWidth(520)
		widget:SetCustomData(arg)
	end)
	after_each(function()
		release(widget)
		widget = nil
	end)

	it('draws one row per entry, with the badge on its own line', function()
		assert.equal(#widget:GetValue(), 3)
		assert.equal(M.Get(widget.rowFrames[1].sentence, 'text'), 'Gray when someone else tagged it first')
		assert.is_true(widget.rowFrames[2].badge:IsShown())
		assert.is_false(widget.rowFrames[1].badge:IsShown())
		assert.is_true(widget.header:IsShown())
		assert.truthy(widget.frame.height > 3 * 26, 'height covers every row')
	end)

	it('moves a row and reports the new order', function()
		click(widget.rowFrames[2].up)
		assert.equal(last.action, 'reorder')
		assert.equal(last.id, 'threat')
		assert.equal(last.from, 2)
		assert.equal(last.index, 1)
		assert.same(last.order, { 'threat', 'tapped', 'class' })
		assert.equal(widget:GetValue()[1].id, 'threat')
	end)

	it('does not move the top row up or the bottom row down', function()
		assert.is_true(widget.rowFrames[1].up.disabled)
		assert.is_true(widget.rowFrames[3].down.disabled)
		click(widget.rowFrames[1].up)
		click(widget.rowFrames[3].down)
		assert.is_nil(last)
	end)

	it('turns a row off', function()
		click(widget.rowFrames[1].switch)
		assert.equal(last.action, 'toggle')
		assert.equal(last.id, 'tapped')
		assert.is_false(last.on)
		assert.is_false(stored[1].on)
		assert.is_false(widget.rowFrames[1].switch.checked)
	end)

	it('changes the When clause from the popup list', function()
		click(widget.rowFrames[1].whenButton)
		local items = Draw.MenuItems()
		assert.not_nil(items, 'the When list opens')
		assert.same(itemValues(items), P.Conditions.WHEN_ORDER)
		assert.is_true(Draw.PickMenuIndex(3))
		assert.equal(last.action, 'when')
		assert.equal(last.when, P.Conditions.WHEN_ORDER[3])
		assert.equal(stored[1].when, P.Conditions.WHEN_ORDER[3])
		assert.is_nil(Draw.MenuItems(), 'the list closes after a pick')
	end)

	it('closes an open When list when it is released, so a reused widget never takes the pick', function()
		click(widget.rowFrames[1].whenButton)
		assert.not_nil(Draw.MenuItems(), 'the When list opens')
		-- Released by AceGUI directly, without the helper's blanket CloseMenu
		AceGUI:Release(widget)
		assert.is_nil(Draw.MenuItems(), 'the list closes with its widget')
		local changes = 0
		local other = create('RuleList')
		other:SetWidth(520)
		other:SetCustomData({
			rows = function()
				return sampleRows()
			end,
			onChange = function()
				changes = changes + 1
			end,
		})
		assert.is_false(Draw.PickMenuIndex(2), 'nothing is left to pick')
		assert.equal(changes, 0, 'the new owner of the widget heard nothing')
		widget = other
	end)

	it('adds a color where insertIndex says, marks rows already there, and flashes the new row', function()
		arg.addChoices = function()
			return { { id = 'quest', label = 'Quest' }, { id = 'tapped', label = 'Tapped' } }
		end
		arg.insertIndex = function(id, order)
			assert.equal(id, 'quest')
			assert.same(order, { 'tapped', 'threat', 'class' })
			return 2
		end
		widget:SetCustomData(arg)
		assert.is_true(widget.add:IsShown())
		widget:OpenAddMenu()
		local items = Draw.MenuItems()
		assert.equal(#items, 2)
		assert.is_true(items[2].disabled, 'a kind already in the list cannot be added twice')
		assert.is_true(Draw.PickMenuIndex(1))
		assert.equal(last.action, 'add')
		assert.equal(last.index, 2)
		assert.same(last.order, { 'tapped', 'quest', 'threat', 'class' })
		local row = widget.rowById.quest
		assert.not_nil(row)
		assert.truthy(row.flash:GetAlpha() > 0, 'the new row flashes')
		M.Advance(1.2)
		assert.equal(row.flash:GetAlpha(), 0)
		assert.is_false(contains(M.ActiveOnUpdates(), row), 'the flash stops')
	end)

	it('removes a row the player added', function()
		assert.is_false(widget.rowById.tapped.remove:IsShown())
		click(widget.rowById.class.remove)
		assert.equal(last.action, 'remove')
		assert.equal(last.id, 'class')
		assert.equal(#stored, 2)
	end)

	it('lets the page handle edits first', function()
		local edited
		arg.onEdit = function(id, what, key)
			edited = { id, what, key }
			return true
		end
		click(widget.rowById.threat.segments[2])
		assert.same(edited, { 'threat', 'color', 'lost' })
		click(widget.rowById.tapped)
		assert.same(edited, { 'tapped', 'row' })
	end)

	it('stores a color change for one color of a row with several', function()
		widget:SetRowColor('threat', { 0.2, 0.4, 0.6 }, 'safe')
		assert.equal(last.action, 'color')
		assert.equal(last.key, 'safe')
		assert.same(stored[2].colors[1].color, { 0.2, 0.4, 0.6, 1 })
	end)

	it('reports hover to the preview', function()
		local hovered = 'none'
		arg.onHover = function(id)
			hovered = id
		end
		M.RunScript(widget.rowFrames[2], 'OnEnter')
		assert.equal(hovered, 'threat')
		M.mouseFocus = nil
		M.RunScript(widget.rowFrames[2], 'OnLeave')
		assert.is_nil(hovered)
	end)

	it('ignores clicks while disabled and shows the reason', function()
		arg.lockedReason = 'Locked for now.'
		widget:SetDisabled(true)
		assert.is_true(widget.locked:IsShown())
		assert.equal(M.Get(widget.locked, 'text'), 'Locked for now.')
		click(widget.rowFrames[1].switch)
		click(widget.rowFrames[2].up)
		widget:ToggleRow('class')
		assert.is_nil(last)
	end)

	it('fires OnValueChanged with the rows when no handler takes the change', function()
		release(widget)
		widget = create('RuleList')
		widget:SetValue(sampleRows())
		local got
		widget:SetCallback('OnValueChanged', function(_, _, rows)
			got = rows
		end)
		widget:ToggleRow('class')
		assert.not_nil(got)
		assert.equal(got[3].id, 'class')
		assert.is_false(got[3].on)
		assert.is_false(widget:GetValue()[3].on)
	end)

	it('keeps locked rows in place', function()
		stored[2].locked = true
		widget:SetCustomData(arg)
		widget:MoveRow('threat', -1)
		widget:ToggleRow('threat')
		assert.is_nil(last)
		assert.is_true(widget.rowById.threat.switch.disabled)
	end)

	it('is safe when the page releases it during a change', function()
		local w = widget
		arg.onChange = function()
			AceGUI:Release(w)
		end
		widget = nil
		click(w.rowFrames[1].switch)
		assert.equal(#w.rows, 0, 'the released widget kept no rows')
	end)
end)

describe('SpellList', function()
	local widget, stored, last, arg

	before_each(function()
		stored = {}
		last = nil
		arg = {
			list = function()
				return stored
			end,
			onChange = function(list, change)
				stored = list
				last = change
			end,
		}
		widget = create('SpellList')
		widget:SetWidth(420)
		widget:SetCustomData(arg)
		Widgets:ForgetSeenSpells()
	end)
	after_each(function()
		release(widget)
		widget = nil
	end)

	it('adds a typed spell id from the results', function()
		widget:Search('774')
		local items = Draw.MenuItems()
		assert.not_nil(items)
		assert.equal(items[1].value, 774)
		assert.is_true(Draw.PickMenuIndex(1))
		assert.equal(stored[774], 'mine')
		assert.equal(last.action, 'add')
		assert.equal(M.Get(widget.edit, 'text'), '')
		assert.equal(#widget:GetEntries(), 1)
		assert.is_true(widget.entries[1]:IsShown())
	end)

	it('accepts an id the game has no name for yet', function()
		local original = C_Spell.GetSpellInfo
		C_Spell.GetSpellInfo = function()
			return nil
		end
		local ok, err = pcall(function()
			widget:Search('424242')
			local items = Draw.MenuItems()
			assert.equal(items[1].value, 424242)
			assert.matches(items[1].text, '424242')
			M.RunScript(widget.edit, 'OnEnterPressed')
			assert.equal(stored[424242], 'mine')
			assert.is_false(widget:GetEntries()[1].known)
		end)
		C_Spell.GetSpellInfo = original
		assert.is_true(ok, tostring(err))
	end)

	it('finds names among spells seen this session and the curated list', function()
		Widgets:NoteSpell(8936)
		widget:Search('spell 89')
		assert.is_true(contains(itemValues(Draw.MenuItems()), 8936))
		arg.curated = { 5000 }
		widget:Search('spell 50')
		assert.is_true(contains(itemValues(Draw.MenuItems()), 5000))
	end)

	it('says so when nothing matches', function()
		widget:Search('zzzz')
		local items = Draw.MenuItems()
		assert.equal(#items, 1)
		assert.is_true(items[1].disabled)
		assert.matches(items[1].text, 'No spells found')
	end)

	it('never remembers a secret spell id', function()
		if not M.secrets then
			skip('no secret values on this client')
		end
		Widgets:NoteSpell(M.S.Wrap(1234))
		assert.is_false(contains(Widgets:SeenSpells(), 1234))
		Widgets:NoteSpell(1234)
		assert.is_true(contains(Widgets:SeenSpells(), 1234))
	end)

	it('switches between Only mine and Anyone, and removes entries', function()
		widget:AddSpell(774)
		click(widget.entries[1].any)
		assert.equal(stored[774], 'any')
		assert.equal(last.action, 'who')
		assert.is_true(widget.entries[1].any.active)
		click(widget.entries[1].remove)
		assert.is_nil(stored[774])
		assert.equal(last.action, 'remove')
		assert.is_false(widget.entries[1]:IsShown())
		assert.is_true(widget.empty:IsShown())
	end)

	it('takes a list of entries as well as a map', function()
		arg.list = nil
		widget:SetCustomData(arg)
		widget:SetValue({ { spellID = 1, who = 'any' }, { id = 2 } })
		assert.same(widget:GetValue(), { [1] = 'any', [2] = 'mine' })
		arg.defaultWho = 'any'
		widget:SetValue({ [3] = 'mine', [4] = true })
		assert.same(widget:GetValue(), { [3] = 'mine', [4] = 'any' })
	end)

	it('shows the reason instead of the lists when they cannot be used', function()
		arg.unavailable = 'Not available for enemy buffs on this version of WoW.'
		widget:SetCustomData(arg)
		assert.is_false(widget.box:IsShown())
		assert.is_true(widget.locked:IsShown())
		assert.matches(M.Get(widget.locked, 'text'), 'Not available')
	end)

	it('ignores edits while disabled', function()
		widget:AddSpell(774)
		widget:SetDisabled(true)
		assert.is_false(widget:AddSpell(775))
		click(widget.entries[1].any)
		assert.equal(stored[774], 'mine')
		assert.is_nil(stored[775])
	end)

	it('offers the spell id tooltip switch when the page gives one', function()
		local on = false
		arg.tooltipIDs = {
			get = function()
				return on
			end,
			set = function(value)
				on = value
			end,
		}
		widget:SetCustomData(arg)
		assert.is_true(widget.tooltipRow:IsShown())
		click(widget.tooltipSwitch)
		assert.is_true(on)
		assert.is_true(widget.tooltipSwitch.checked)
	end)

	it('fires OnValueChanged with the map when no handler takes the change', function()
		release(widget)
		widget = create('SpellList')
		local got
		widget:SetCallback('OnValueChanged', function(_, _, value)
			got = value
		end)
		widget:AddSpell(33763)
		assert.same(got, { [33763] = 'mine' })
	end)
end)
