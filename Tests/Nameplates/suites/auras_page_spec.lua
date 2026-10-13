-- @runtime lua51
-- The Auras options page (plan 3.2 #4): an "Always show" and a "Never show" spell list for each of
-- My debuffs on enemies, Enemy buffs I can remove, Crowd control and (where the client has them)
-- Tank debuffs, drawn by the real SpellList widget and written to the profile the aura rows read.
-- Enemy buffs have no lists on clients with secret values. Everything locks, with a reason, while
-- the game restricts aura changes. Runs on every client.
local M, H = ...

if not H.ModuleExists() then
	describe('auras page', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

local EM_DASH = '\226\128\148'
local REASON = 'Not available for enemy buffs on this version of WoW'

local builds = 0

---A fresh core on its own widget prefix: AceGUI keeps the first constructor registered under a
---type name for the whole process, so a later core would otherwise get widgets bound to an old one.
local function Build()
	builds = builds + 1
	local P = H.FreshCore({ host = { widgetPrefix = 'AurasPageTest' .. builds } })
	M.Login('NameplatesTestHost')
	local page = P:BuildOptionsTable().args.auras
	return P, page
end

local function Has(list, value)
	for _, v in ipairs(list) do
		if v == value then
			return true
		end
	end
	return false
end

local Draw

---A SpellList fed with an option, as the dialog feeds it: arg first, then the disabled state.
local function MakeList(P, option)
	Draw = P.Widgets.Draw
	local widget = P.Widgets:Create('SpellList')
	assert.not_nil(widget, 'SpellList is built')
	widget.frame:SetParent(UIParent)
	widget.frame:Show()
	widget:SetWidth(460)
	-- The calls AceConfigDialog makes for a select with a dialogControl, in its order
	widget:SetLabel(option.name)
	widget:SetList(option.values, option.sorting, nil)
	widget:SetValue(option.values[option.get()])
	widget:SetCallback('OnValueChanged', function() end)
	widget:SetDisabled(option.disabled())
	widget:SetCustomData(option.arg)
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

describe('auras page: layout', function()
	local P, page

	before_each(function()
		P, page = Build()
	end)

	it('has the four sections in plan order, named for the player', function()
		local names = {}
		for _, key in ipairs({ 'myDebuffs', 'removable', 'crowdControl', 'tankDebuffs' }) do
			local group = page.args[key]
			assert.not_nil(group, key)
			assert.equal(group.type, 'group')
			assert.is_true(group.inline)
			names[#names + 1] = group.name
		end
		assert.same(names, { 'My debuffs on enemies', 'Enemy buffs I can remove', 'Crowd control', 'Tank debuffs' })
		assert.truthy(page.args.myDebuffs.order < page.args.removable.order)
		assert.truthy(page.args.removable.order < page.args.crowdControl.order)
		assert.truthy(page.args.crowdControl.order < page.args.tankDebuffs.order)
		assert.equal(page.order, 4)
		assert.equal(page.name, 'Auras')
	end)

	it('has at most eight main controls', function()
		local main = 0
		for _, option in pairs(page.args) do
			if option.type ~= 'description' and not option.advanced then
				main = main + 1
			end
		end
		assert.truthy(main <= 8, 'main controls: ' .. main)
	end)

	it('gives each section an Always show and a Never show list drawn by the SpellList widget', function()
		for _, key in ipairs({ 'myDebuffs', 'removable', 'crowdControl', 'tankDebuffs' }) do
			local args = page.args[key].args
			assert.equal(args.always.name, 'Always show', key)
			assert.equal(args.never.name, 'Never show', key)
			assert.equal(args.always.dialogControl, P.Widgets:TypeName('SpellList'))
			assert.equal(args.never.dialogControl, P.Widgets:TypeName('SpellList'))
			assert.truthy(args.always.order < args.never.order)
		end
		assert.is_true(P.Widgets:Has('SpellList'))
	end)

	it('shows Tank debuffs where the client has them, and not on Retail', function()
		local hidden = page.args.tankDebuffs.hidden()
		assert.equal(hidden, P.Caps:Client() == 'retail')
		for _, key in ipairs({ 'myDebuffs', 'removable', 'crowdControl' }) do
			assert.is_false(page.args[key].hidden())
		end
	end)

	it('uses plain words: no em dashes, no symbols the game cannot draw', function()
		for _, text in ipairs(Texts(page)) do
			assert.is_nil(text:find(EM_DASH, 1, true), 'em dash in: ' .. text)
			assert.is_nil(text:find('[\128-\255]'), 'non-ASCII character in: ' .. text)
		end
	end)

	it('leaves a spell list in plain form: each section starts empty', function()
		assert.is_nil(P.Store:Get('auras'))
		for _, key in ipairs({ 'myDebuffs', 'removable', 'crowdControl', 'tankDebuffs' }) do
			assert.same(P.Options.AurasPage.ReadList(key, 'always'), {})
			assert.same(P.Options.AurasPage.ReadList(key, 'never'), {})
		end
	end)
end)

describe('auras page: enemy buffs on clients with secret values', function()
	local P, page

	before_each(function()
		P, page = Build()
	end)

	it('says so instead of showing lists, where the game skips spell lists for enemy buffs', function()
		local args = page.args.removable.args
		if M.secrets then
			assert.equal(P.Options.AurasPage.Unavailable('removable'), REASON)
			assert.is_false(args.unavailable.hidden())
			assert.equal(args.unavailable.name(), REASON)
			assert.is_true(args.always.hidden())
			assert.is_true(args.never.hidden())
			assert.equal(args.always.arg.unavailable(), REASON)
		else
			assert.is_nil(P.Options.AurasPage.Unavailable('removable'))
			assert.is_true(args.unavailable.hidden())
			assert.is_false(args.always.hidden())
			assert.is_false(args.never.hidden())
		end
	end)

	it('shows the reason in the widget when the lists are drawn anyway', function()
		if not M.secrets then
			skip('this client takes spell lists for enemy buffs')
		end
		local widget = MakeList(P, page.args.removable.args.always)
		assert.is_false(widget.box:IsShown())
		assert.is_true(widget.locked:IsShown())
		assert.equal(M.Get(widget.locked, 'text'), REASON)
		Release(widget)
	end)

	it('keeps the lists for the other rows', function()
		for _, key in ipairs({ 'myDebuffs', 'crowdControl' }) do
			assert.is_nil(page.args[key].args.always.hidden)
			assert.is_nil(P.Options.AurasPage.Unavailable(key))
		end
	end)

	it('lets the player add the important buffs where the game can tell', function()
		local important = page.args.removable.args.important
		assert.not_nil(important)
		local hidden = important.hidden()
		if P.AuraRows.Limit('important') ~= nil or not P.Caps:Get('important') then
			assert.is_true(hidden)
		else
			assert.is_false(hidden)
			assert.is_false(important.get())
			important.set({}, true)
			assert.is_true(P.Store:Get({ 'auras', 'removable', 'important' }))
			assert.is_true(important.get())
			important.set({}, false)
			assert.is_nil(P.Store:Get({ 'auras', 'removable', 'important' }))
			assert.is_nil(P.Store:Get('auras'))
		end
	end)
end)

describe('auras page: the lists', function()
	local P, page, widget, AurasPage

	before_each(function()
		P, page = Build()
		AurasPage = P.Options.AurasPage
		widget = nil
	end)
	after_each(function()
		Release(widget)
		widget = nil
	end)

	it('adds a spell to Always show as Only mine, and stores the list whole', function()
		widget = MakeList(P, page.args.myDebuffs.args.always)
		assert.is_true(widget:AddSpell(774))
		assert.same(P.Store:Get({ 'auras', 'myDebuffs', 'always' }), { [774] = 'mine' })
		assert.same(AurasPage.ReadList('myDebuffs', 'always'), { [774] = 'mine' })
		assert.equal(#widget:GetEntries(), 1)
		assert.is_nil(P.Store:Get({ 'auras', 'myDebuffs', 'never' }))
	end)

	it('adds to Never show as Anyone by default, and to crowd control as Anyone', function()
		widget = MakeList(P, page.args.myDebuffs.args.never)
		widget:AddSpell(589)
		assert.same(P.Store:Get({ 'auras', 'myDebuffs', 'never' }), { [589] = 'any' })
		Release(widget)
		widget = MakeList(P, page.args.crowdControl.args.always)
		widget:AddSpell(118)
		assert.same(P.Store:Get({ 'auras', 'crowdControl', 'always' }), { [118] = 'any' })
	end)

	it('switches an entry between Only mine and Anyone, and removes it', function()
		widget = MakeList(P, page.args.myDebuffs.args.always)
		widget:AddSpell(774)
		M.RunScript(widget.entries[1].any, 'OnClick', 'LeftButton', false)
		assert.equal(P.Store:Get({ 'auras', 'myDebuffs', 'always', 774 }), 'any')
		M.RunScript(widget.entries[1].mine, 'OnClick', 'LeftButton', false)
		assert.equal(P.Store:Get({ 'auras', 'myDebuffs', 'always', 774 }), 'mine')
		M.RunScript(widget.entries[1].remove, 'OnClick', 'LeftButton', false)
		assert.is_nil(P.Store:Get('auras'), 'an empty list leaves nothing in the profile')
	end)

	it('reads lists that came from plain arrays of spell ids', function()
		P.Store:Set({ 'auras', 'crowdControl', 'never' }, { 118, 853 })
		assert.same(AurasPage.ReadList('crowdControl', 'never'), { [118] = 'any', [853] = 'any' })
		widget = MakeList(P, page.args.crowdControl.args.never)
		assert.equal(#widget:GetEntries(), 2)
	end)

	it('reads true as Anyone and ignores false, like the aura rows do', function()
		P.Store:Set({ 'auras', 'crowdControl', 'never' }, { [118] = true, [853] = false, [5782] = 'mine' })
		assert.same(AurasPage.ReadList('crowdControl', 'never'), { [118] = 'any', [5782] = 'mine' })
	end)

	it('keeps the other lists when one changes', function()
		widget = MakeList(P, page.args.myDebuffs.args.always)
		widget:AddSpell(774)
		Release(widget)
		widget = MakeList(P, page.args.crowdControl.args.never)
		widget:AddSpell(118)
		assert.same(P.Store:Get({ 'auras', 'myDebuffs', 'always' }), { [774] = 'mine' })
		assert.same(P.Store:Get({ 'auras', 'crowdControl', 'never' }), { [118] = 'any' })
	end)

	it('feeds the aura rows the engine builds', function()
		widget = MakeList(P, page.args.myDebuffs.args.always)
		widget:AddSpell(774)
		Release(widget)
		widget = MakeList(P, page.args.myDebuffs.args.never)
		widget:AddSpell(589)
		if P.Caps:Get('containers') then
			local groups = P.AuraRows.ContainerGroups('myDebuffs', P.Store:Get('auras'))
			local seen = false
			for _, group in ipairs(groups) do
				local include = group.candidates and group.candidates.includeSpellIDs
				if include and include[774] then
					seen = true
				end
			end
			assert.is_true(seen, 'the Always show spell reaches the container groups')
		else
			local settings = P.AuraScan.RowSettings('myDebuffs')
			assert.equal(settings.always.ids[774], 'mine')
			assert.equal(settings.never.ids[589], 'any')
		end
	end)

	it('offers the crowd control and tank debuff spells of this client first', function()
		local curated = page.args.crowdControl.args.always.arg.curated()
		local count = 0
		for _ in pairs(curated) do
			count = count + 1
		end
		if P.Caps:Client() == 'retail' then
			assert.equal(count, 0)
		else
			assert.truthy(count > 0, 'crowd control data for ' .. P.Caps:Client())
		end
		local tank = page.args.tankDebuffs.args.always.arg.curated()
		local tankCount = 0
		for _ in pairs(tank) do
			tankCount = tankCount + 1
		end
		if P.Caps:Client() == 'retail' then
			assert.equal(tankCount, 0)
		else
			assert.truthy(tankCount > 0)
		end
		assert.same(page.args.removable.args.always.arg.curated(), {})
	end)

	it('clears every list at once and keeps the other settings', function()
		P.Store:Set({ 'auras', 'tankDebuffs', 'on' }, false)
		AurasPage.WriteList('myDebuffs', 'always', { [774] = 'mine' })
		AurasPage.WriteList('crowdControl', 'never', { [118] = 'any' })
		local clear = page.args.clear
		assert.is_true(clear.advanced)
		assert.is_false(clear.hidden())
		assert.is_true(clear.confirm)
		assert.equal(type(clear.confirmText), 'string')
		clear.func()
		assert.same(P.Store:Get('auras'), { tankDebuffs = { on = false } })
		assert.is_true(clear.hidden())
	end)
end)

describe('auras page: tank debuffs', function()
	local P, page

	before_each(function()
		P, page = Build()
	end)

	it('has a switch that starts on', function()
		local on = page.args.tankDebuffs.args.on
		assert.is_true(on.get())
		on.set({}, false)
		assert.is_false(P.Store:Get({ 'auras', 'tankDebuffs', 'on' }))
		assert.is_false(on.get())
		on.set({}, true)
		assert.is_nil(P.Store:Get('auras'))
	end)

	it('turns the data off for the aura rows', function()
		local on = page.args.tankDebuffs.args.on
		on.set({}, false)
		if P.Caps:Client() == 'forever' then
			assert.is_nil(P.AuraRows.TankDebuffSet(P.Store:Get('auras')))
		elseif P.Caps:Client() ~= 'retail' and not P.Caps:Get('containers') then
			assert.is_false(P.AuraScan.RowSettings('tankDebuffs').on)
		end
	end)

	it('takes its own lists', function()
		local widget
		widget = MakeList(P, page.args.tankDebuffs.args.never)
		widget:AddSpell(7386)
		assert.same(P.Store:Get({ 'auras', 'tankDebuffs', 'never' }), { [7386] = 'any' })
		Release(widget)
	end)
end)

describe('auras page: locking', function()
	local P, page, widget

	before_each(function()
		P, page = Build()
		widget = nil
	end)
	after_each(function()
		Release(widget)
		widget = nil
		if M.lockdown then
			M.LeaveCombat()
		end
	end)

	local function ListOptions()
		local out = {}
		for _, key in ipairs({ 'myDebuffs', 'removable', 'crowdControl', 'tankDebuffs' }) do
			out[#out + 1] = page.args[key].args.always
			out[#out + 1] = page.args[key].args.never
		end
		return out
	end

	it('is open when nothing is restricted', function()
		assert.is_true(page.args.locked.hidden())
		for _, option in ipairs(ListOptions()) do
			assert.is_false(option.disabled())
		end
	end)

	it('locks every list and shows the reason in combat, and unlocks after', function()
		M.EnterCombat()
		assert.is_false(page.args.locked.hidden())
		assert.equal(page.args.locked.name, 'The game does not allow aura changes right now. They unlock after combat.')
		assert.equal(page.args.locked.name, P.Options.LOCKED_REASON)
		for _, option in ipairs(ListOptions()) do
			assert.is_true(option.disabled())
		end
		assert.is_true(page.args.tankDebuffs.args.on.disabled())
		assert.is_true(page.args.removable.args.important.disabled())
		M.LeaveCombat()
		assert.is_true(page.args.locked.hidden())
		for _, option in ipairs(ListOptions()) do
			assert.is_false(option.disabled())
		end
	end)

	it('locks while the game keeps auras secret out of combat', function()
		if not M.secrets then
			skip('no secret values on this client')
		end
		M.SetRestricted(true)
		assert.is_true(P.Options.Locked())
		assert.is_true(page.args.myDebuffs.args.always.disabled())
		M.SetRestricted(false)
		assert.is_false(page.args.myDebuffs.args.always.disabled())
	end)

	it('refuses a change while locked, shows why in the widget, and does not queue it', function()
		M.EnterCombat()
		widget = MakeList(P, page.args.myDebuffs.args.always)
		assert.is_true(widget.locked:IsShown())
		assert.equal(M.Get(widget.locked, 'text'), 'Locked until combat ends.')
		assert.is_false(widget:AddSpell(774))
		assert.is_nil(P.Store:Get('auras'))
		M.LeaveCombat()
		M.Advance(1)
		assert.is_nil(P.Store:Get('auras'), 'nothing was queued for later')
		widget:SetDisabled(page.args.myDebuffs.args.always.disabled())
		assert.is_true(widget:AddSpell(774))
		assert.same(P.Store:Get({ 'auras', 'myDebuffs', 'always' }), { [774] = 'mine' })
	end)

	it('asks the host to redraw when the lock lifts', function()
		local redraws = 0
		P.host.RefreshOptions = function()
			redraws = redraws + 1
		end
		M.EnterCombat()
		P:Fire('RESTRICTION_CHANGED', true)
		M.Advance(0.1)
		M.LeaveCombat()
		P:Fire('RESTRICTION_CHANGED', false)
		M.Advance(0.1)
		assert.truthy(redraws >= 1, 'the host was asked to redraw')
	end)
end)

describe('auras page: lists per specialization', function()
	it('keeps one path function, with room for a specialization later', function()
		local P = H.FreshCore()
		local AurasPage = P.Options.AurasPage
		assert.same(AurasPage.ListPath('myDebuffs', 'always'), { 'auras', 'myDebuffs', 'always' })
		assert.same(AurasPage.ListPath('crowdControl', 'never', 267), { 'auras', 'crowdControl', 'bySpec', 267, 'never' })
	end)

	it('never reads the specialization shape yet', function()
		local P = H.FreshCore()
		P.Store:Set({ 'auras', 'myDebuffs', 'bySpec', 267, 'always' }, { [348] = 'mine' })
		assert.same(P.Options.AurasPage.ReadList('myDebuffs', 'always'), {})
	end)
end)

describe('auras page: search words', function()
	it('knows everyday words for the settings here', function()
		local P = H.FreshCore()
		local words = P.Options.SEARCH_WORDS
		assert.equal(words.cc, 'crowd control')
		assert.equal(words.whitelist, 'always show')
		assert.equal(words.blacklist, 'never show')
		assert.equal(words.dot, 'debuff')
	end)
end)

describe('auras page: writes at the time of a change', function()
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

	it('rejects stale spell list callbacks and switches during combat without queuing', function()
		local A = P.Options.AurasPage
		A.WriteList('myDebuffs', 'always', { [774] = 'mine' })
		local before = P.util.Copy(P.Store:Get('auras'))
		M.EnterCombat()
		page.args.myDebuffs.args.always.arg.onChange({ [589] = 'any' })
		page.args.tankDebuffs.args.on.set({}, false)
		page.args.removable.args.important.set({}, true)
		page.args.clear.func()
		assert.same(P.Store:Get('auras'), before)
		M.LeaveCombat()
		M.Advance(1)
		assert.same(P.Store:Get('auras'), before, 'rejected changes were not queued')
		page.args.myDebuffs.args.always.arg.onChange({ [589] = 'any' })
		assert.same(A.ReadList('myDebuffs', 'always'), { [589] = 'any' })
	end)

	it('rejects changes when auras become secret before the dialog redraws', function()
		if not M.secrets then
			skip('this client has no secret values')
		end
		M.SetRestricted(true)
		page.args.myDebuffs.args.always.arg.onChange({ [774] = 'mine' })
		page.args.tankDebuffs.args.on.set({}, false)
		assert.is_nil(P.Store:Get('auras'))
		assert.equal(page.args.myDebuffs.args.always.arg.lockedReason(), 'Aura changes are locked right now.')
		M.SetRestricted(false)
		M.Advance(1)
		assert.is_nil(P.Store:Get('auras'))
	end)

	it('refuses enemy buff list callbacks on clients that cannot use them', function()
		if not M.secrets then
			skip('this client can use enemy buff spell lists')
		end
		page.args.removable.args.always.arg.onChange({ [774] = 'any' })
		assert.is_nil(P.Store:Get('auras'))
	end)

	it('keeps old callbacks bound to the active profile after a switch', function()
		local option = page.args.myDebuffs.args.always
		option.arg.onChange({ [774] = 'mine' })
		local old = P.util.Copy(P.Store:Get('auras'))
		P.db:SetProfile('A different character')
		assert.same(option.arg.list(), {})
		option.arg.onChange({ [589] = 'any' })
		assert.same(option.arg.list(), { [589] = 'any' })
		P.db:SetProfile('Default')
		assert.same(P.Store:Get('auras'), old)
	end)
end)
