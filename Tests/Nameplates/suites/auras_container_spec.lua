-- @runtime lua51
-- Aura rows on 12.1 aura containers (plan 6.6): filters and groups per row, one pooled container
-- per row (at most 3 per plate), per-add flips by reach (combat included), settings that wait
-- while the game restricts aura changes, the max-frame-count off switch, button styling (timer,
-- stacks, dispel border, pandemic glow in both 12.1.0 and 12.1.5 shapes) and the aura presence
-- tints. The mock's containers enforce Blizzard's input checks; this suite adds the parts of the
-- real container the mock has no behavior for: filter token validation, the batch of ten buttons
-- per group handed to initializeFrame, and AddAuraSlot returning its button.
-- Forever's real tank debuff data adds a second My debuffs group there; tests count it.
local M, H = ...

if not H.ModuleExists() then
	describe('aura containers', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

----------------------------------------------------------------------------------------------------
-- What the real container does that the mock does not (installed before any container exists)
----------------------------------------------------------------------------------------------------

-- AuraUtil.AuraFilters values on origin/live, origin/ptr2 and forever
local VALID_TOKENS = {
	HELPFUL = true,
	HARMFUL = true,
	PLAYER = true,
	RAID = true,
	CANCELABLE = true,
	INCLUDE_NAME_PLATE_ONLY = true,
	MAW = true,
	EXTERNAL_DEFENSIVE = true,
	CROWD_CONTROL = true,
	RAID_IN_COMBAT = true,
	RAID_PLAYER_DISPELLABLE = true,
	BIG_DEFENSIVE = true,
	IMPORTANT = true,
	DISPELLABLE = true,
}
local REGION_SHAPE = M.flavor == 'forever' or M.flavor == 'ptr' -- RemovePandemicRegion(region)
local sentFilters = {}
local fake = setmetatable({}, { __mode = 'k' }) -- fake aura button -> record

local function ValidateFilter(filter, level)
	if type(filter) ~= 'string' then
		error('filterString must be a string', level)
	end
	for component in string.gmatch(filter, '[^| ]+') do
		local bare = component:sub(1, 1) == '!' and component:sub(2) or component
		if bare == '' or not VALID_TOKENS[bare] then
			error("Unknown aura filter component: '" .. component .. "'", level)
		end
	end
end

local function CheckFilter(filter)
	ValidateFilter(filter, 4)
	sentFilters[#sentFilters + 1] = filter
end

local function IsDescendant(obj, owner)
	local node = obj
	for _ = 1, 30 do
		if node == owner then
			return true
		end
		node = M.Get(node, 'parent')
		if not node then
			return false
		end
	end
	return false
end

local function FakeButton(container)
	local b = M.NewObject('Button', nil, container)
	local rec = { calls = {}, regions = {}, animations = {}, forbidden = false }
	fake[b] = rec
	local function Log(name, ...)
		rec.calls[#rec.calls + 1] = { name = name, n = select('#', ...), ... }
	end
	local function Inbound(name, obj)
		if not IsDescendant(obj, b) then
			error(name .. ': the object must be a child of the aura button', 3)
		end
	end
	local function Method(name, fn)
		M.Override(b, name, function(_, ...)
			Log(name, ...)
			if fn then
				return fn(...)
			end
		end)
	end
	M.Override(b, 'IsForbidden', function()
		return rec.forbidden
	end)
	Method('SetIcon', function(t)
		Inbound('SetIcon', t)
	end)
	Method('SetDurationCooldown', function(c)
		Inbound('SetDurationCooldown', c)
	end)
	Method('SetDurationText', function(fs, options)
		Inbound('SetDurationText', fs)
		assert(options == nil or type(options) == 'table', 'options must be a table or nil')
	end)
	Method('ClearDurationText')
	Method('SetApplicationCount', function(fs)
		Inbound('SetApplicationCount', fs)
	end)
	Method('ClearApplicationCount')
	Method('AddDispelTypeTexture', function(t, options)
		Inbound('AddDispelTypeTexture', t)
		assert(type(options) == 'table' and options.style ~= nil, 'dispel textures need a style')
		if not REGION_SHAPE then
			return 1
		end
	end)
	Method('ClearDispelTypeTextures')
	Method('AddPandemicRegion', function(region)
		Inbound('AddPandemicRegion', region)
		for _, existing in ipairs(rec.regions) do
			assert(existing ~= region, 'a pandemic region was added twice')
		end
		rec.regions[#rec.regions + 1] = region
		if not REGION_SHAPE then
			return #rec.regions
		end
	end)
	Method('RemovePandemicRegion', function(handle)
		if REGION_SHAPE then
			assert(type(handle) == 'table', '12.1.5 removes a pandemic region by region')
			for i = #rec.regions, 1, -1 do
				if rec.regions[i] == handle then
					table.remove(rec.regions, i)
				end
			end
		else
			assert(type(handle) == 'number', '12.1.0 removes a pandemic region by index')
			table.remove(rec.regions, handle)
		end
	end)
	if REGION_SHAPE then
		Method('AddPandemicEnterAnimation')
		Method('AddPandemicActiveAnimation', function(group)
			for _, existing in ipairs(rec.animations) do
				assert(existing ~= group, 'an animation was added twice')
			end
			rec.animations[#rec.animations + 1] = group
		end)
		Method('RemovePandemicActiveAnimation', function(group)
			for i = #rec.animations, 1, -1 do
				if rec.animations[i] == group then
					table.remove(rec.animations, i)
				end
			end
		end)
	end
	return b
end

local function Count(rec, name)
	local n = 0
	for _, call in ipairs(rec.calls) do
		if call.name == name then
			n = n + 1
		end
	end
	return n
end

local buttonsOf = setmetatable({}, { __mode = 'k' }) -- container -> fake buttons
local slotsOf = setmetatable({}, { __mode = 'k' })
local WT = M.WT.AuraContainer
if WT then
	local add, setFilter, addSlot = WT.AddAuraGroup, WT.SetAuraGroupFilterString, WT.AddAuraSlot
	WT.AddAuraGroup = function(self, key, filter, options)
		CheckFilter(filter)
		add(self, key, filter, options)
		local list = buttonsOf[self] or {}
		buttonsOf[self] = list
		for _ = 1, 10 do
			local button = FakeButton(self)
			list[#list + 1] = button
			if options and options.initializeFrame then
				options.initializeFrame(button)
			end
		end
	end
	WT.SetAuraGroupFilterString = function(self, key, filter)
		CheckFilter(filter)
		return setFilter(self, key, filter)
	end
	WT.AddAuraSlot = function(self, key, filter, options)
		CheckFilter(filter)
		addSlot(self, key, filter, options)
		local slot = FakeButton(self)
		local list = slotsOf[self] or {}
		slotsOf[self] = list
		list[#list + 1] = slot
		if options and options.initializeFrame then
			options.initializeFrame(slot)
		end
		return slot
	end
end

M.Login('NameplatesTestHost')
local P = H.FreshCore()
local Merge = P.Styles.Merge
local Rows = P.AuraRows
local Containers = P.AuraContainers
local HAS_CONTAINERS = P.Caps:Get('containers')
local FOREVER = P.Caps:Client() == 'forever'

local function Keys(set)
	local out = {}
	for k in pairs(set or {}) do
		out[#out + 1] = k
	end
	table.sort(out)
	return out
end

local function Has(set, id)
	return type(set) == 'table' and set[id] == true
end

----------------------------------------------------------------------------------------------------
-- Rows and filters (every client)
----------------------------------------------------------------------------------------------------

describe('aura rows: filters', function()
	it('orders tokens so groups share engine scans', function()
		assert.equal(Rows.NormalizeFilter('PLAYER|HARMFUL|!CROWD_CONTROL|INCLUDE_NAME_PLATE_ONLY'), 'HARMFUL|!CROWD_CONTROL|INCLUDE_NAME_PLATE_ONLY|PLAYER')
		assert.equal(Rows.NormalizeFilter('HELPFUL|NOT_CANCELABLE'), 'HELPFUL|!CANCELABLE')
		assert.equal(Rows.NormalizeFilter('HARMFUL|PLAYER|PLAYER'), 'HARMFUL|PLAYER')
		assert.equal(Rows.NormalizeFilter('HARMFUL|CANCELABLE|!CANCELABLE'), 'HARMFUL|CANCELABLE|!CANCELABLE')
	end)

	it('writes a negation the game ignores as the bare token', function()
		assert.equal(Rows.NormalizeFilter('HARMFUL|!INCLUDE_NAME_PLATE_ONLY'), 'HARMFUL|INCLUDE_NAME_PLATE_ONLY')
		assert.equal(Rows.NormalizeFilter('HELPFUL|!MAW'), 'HELPFUL|MAW')
	end)

	it('drops tokens this game does not know', function()
		local filter, dropped = Rows.ValidFilter('HARMFUL|NOT_A_TOKEN|PLAYER')
		assert.equal(filter, 'HARMFUL|PLAYER')
		assert.equal(dropped, 1)
	end)

	it('reads both shapes of a spell list', function()
		local mine, any = Rows.SpellSets({ [100] = 'mine', [200] = 'any', [300] = true })
		assert.same(Keys(mine), { 100 })
		assert.same(Keys(any), { 200, 300 })
		local mine2, any2 = Rows.SpellSets({ 400, 500 })
		assert.same(Keys(mine2), {})
		assert.same(Keys(any2), { 400, 500 })
	end)

	it('tells which units a spell list reaches, like the engine does', function()
		assert.equal(Rows.Reach({ reaction = 2, canAttack = true }), 'enemy')
		assert.equal(Rows.Reach({ reaction = 4, canAttack = false }), 'enemy', 'a neutral unit cannot be helped')
		assert.equal(Rows.Reach({ reaction = 5, canAttack = false }), 'friend')
		assert.equal(Rows.Reach({ reaction = 6, canAttack = true }), 'enemy', 'a dueling friend can be attacked')
		assert.is_nil(Rows.Reach({}), 'unknown facts reach nothing')
		assert.is_true(Rows.GroupApplies(nil, {}))
		assert.is_false(Rows.GroupApplies('hostile', { reaction = 4, canAttack = false }))
		assert.is_true(Rows.GroupApplies('enemy', { reaction = 4, canAttack = false }))
	end)
end)

describe('aura rows: container groups', function()
	it('builds My debuffs from the plan filter and candidate', function()
		local groups = Rows.ContainerGroups('myDebuffs', { tankDebuffs = { on = false } })
		assert.equal(#groups, 1)
		assert.equal(groups[1].filter, 'HARMFUL|!CROWD_CONTROL|INCLUDE_NAME_PLATE_ONLY|PLAYER')
		assert.same(groups[1].candidates, { nameplateShowPersonal = true })
		assert.is_nil(groups[1].applies, 'the main group shows on every unit')
	end)

	it('shows every debuff but crowd control when Only mine is off', function()
		local groups = Rows.ContainerGroups('myDebuffs', { myDebuffs = { onlyMine = false }, tankDebuffs = { on = false } })
		assert.equal(#groups, 1)
		assert.equal(groups[1].filter, 'HARMFUL|!CROWD_CONTROL|INCLUDE_NAME_PLATE_ONLY')
		assert.is_nil(groups[1].candidates)
		local all = Rows.ContainerGroups('myDebuffs', { myDebuffs = { onlyMine = false } })
		assert.equal(#all, 1, 'tank debuffs are already in every debuff')
	end)

	it('puts always lists in their own spell-list groups and keeps them out of the main group', function()
		local auras = { myDebuffs = { always = { [100] = 'mine', [200] = 'any', [300] = 'mine' }, never = { [300] = 'any', [400] = 'mine' } }, tankDebuffs = { on = false } }
		local groups = Rows.ContainerGroups('myDebuffs', auras)
		assert.equal(#groups, 3)
		assert.equal(groups[1].filter, 'HARMFUL|INCLUDE_NAME_PLATE_ONLY|PLAYER')
		assert.same(Keys(groups[1].candidates.includeSpellIDs), { 100 }, 'never wins over always')
		assert.equal(groups[1].applies, 'enemy')
		assert.equal(groups[2].filter, 'HARMFUL|INCLUDE_NAME_PLATE_ONLY')
		assert.same(Keys(groups[2].candidates.includeSpellIDs), { 200 })
		assert.equal(groups[2].applies, 'enemy')
		assert.same(Keys(groups[3].candidates.excludeSpellIDs), { 100, 200, 300, 400 })
	end)

	it('gives Enemy buffs I can remove no spell lists (the engine skips them for buffs on enemies)', function()
		local auras = { removable = { always = { [100] = 'any' }, never = { [200] = 'any' } } }
		local groups = Rows.ContainerGroups('removable', auras)
		assert.equal(#groups, 1)
		assert.equal(groups[1].filter, 'HELPFUL|DISPELLABLE')
		assert.is_nil(groups[1].candidates)
		assert.equal(groups[1].applies, 'hostile', 'dispellable buffs on friends are not enemy buffs')
		auras.removable.important = true
		groups = Rows.ContainerGroups('removable', auras)
		assert.equal(#groups, 2)
		assert.equal(groups[2].filter, 'HELPFUL|!DISPELLABLE|IMPORTANT')
		assert.equal(groups[2].applies, 'hostile')
	end)

	it('builds crowd control from the token, with never lists as exclusions', function()
		local groups = Rows.ContainerGroups('crowdControl', { crowdControl = { never = { [118] = 'any' } } })
		assert.equal(#groups, 1)
		assert.equal(groups[1].filter, 'HARMFUL|CROWD_CONTROL')
		assert.same(Keys(groups[1].candidates.excludeSpellIDs), { 118 })
	end)

	it('makes the custom row show only the listed spells, debuffs on enemies and buffs on friends', function()
		assert.equal(#Rows.ContainerGroups('custom', nil), 0)
		local groups = Rows.ContainerGroups('custom', { custom = { always = { [774] = 'any' } } })
		assert.equal(#groups, 2)
		assert.equal(groups[1].applies, 'enemy')
		assert.equal(groups[2].filter, 'HELPFUL')
		assert.equal(groups[2].applies, 'friend')
	end)

	it('adds tank debuffs from anyone as a second My debuffs group only where the spells exist', function()
		local saved = P.Data.TankDebuffs
		P.Data.TankDebuffs = { [7386] = 'sunder', [770] = 'faerieFire' }
		local groups = Rows.ContainerGroups('myDebuffs', { tankDebuffs = { never = { [770] = 'any' } } })
		if FOREVER then
			assert.equal(#groups, 2)
			assert.equal(groups[2].filter, 'HARMFUL')
			assert.same(Keys(groups[2].candidates.includeSpellIDs), { 7386 })
			assert.equal(groups[2].applies, 'enemy')
			assert.same(Keys(groups[1].candidates.excludeSpellIDs), { 7386 }, 'my own Sunder shows once')
			local off = Rows.ContainerGroups('myDebuffs', { tankDebuffs = { on = false } })
			assert.equal(#off, 1)
			local extra = Rows.ContainerGroups('myDebuffs', { tankDebuffs = { always = { [99] = 'any' } } })
			assert.same(Keys(extra[2].candidates.includeSpellIDs), { 99, 770, 7386 })
		else
			assert.equal(#groups, 1, 'no tank group on ' .. P.Caps:Client())
		end
		P.Data.TankDebuffs = saved
	end)

	it('uses the real tank debuff data on Forever', function()
		local groups = Rows.ContainerGroups('myDebuffs', nil)
		if FOREVER then
			assert.equal(#groups, 2)
			assert.truthy(Has(groups[2].candidates.includeSpellIDs, 7386), 'Sunder Armor rank 1')
			assert.truthy(Has(groups[2].candidates.includeSpellIDs, 770), 'Faerie Fire')
		else
			assert.equal(#groups, 1)
		end
	end)

	it('sends only candidate keys the engine reads', function()
		local auras = {
			myDebuffs = { always = { [1] = 'mine', [2] = 'any' }, never = { [3] = 'any' } },
			crowdControl = { always = { [4] = 'mine' }, never = { [5] = 'any' } },
			custom = { always = { [6] = 'mine', [7] = 'any' } },
			removable = { important = true },
		}
		for _, row in ipairs(P.Styles.Schema.AURA_ROWS) do
			for _, group in ipairs(Rows.ContainerGroups(row, auras)) do
				for key in pairs(group.candidates or {}) do
					assert.truthy(P.Styles.Schema.CANDIDATE_KEYS[key], row .. ' sends ' .. key)
					assert.truthy(M.CANDIDATE_KEYS[key], 'the engine reads ' .. key)
				end
			end
		end
	end)

	it('never uses HELPFUL and HARMFUL together as a never-match', function()
		for _, row in ipairs(P.Styles.Schema.AURA_ROWS) do
			for _, group in ipairs(Rows.ContainerGroups(row, { custom = { always = { [1] = 'any' } }, removable = { important = true } })) do
				assert.falsy(group.filter:find('HELPFUL', 1, true) and group.filter:find('HARMFUL', 1, true), group.filter)
			end
		end
	end)

	it('explains what a client cannot do in plain words', function()
		for _, feature in ipairs({ 'rows', 'pandemic', 'tints', 'important', 'tankDebuffs', 'lists' }) do
			local text = Rows.Limit(feature, 'removable')
			assert.truthy(text == nil or (type(text) == 'string' and text ~= ''), feature)
		end
		if HAS_CONTAINERS then
			assert.not_nil(Rows.Limit('lists', 'removable'), 'Enemy buffs has no lists on containers')
			assert.is_nil(Rows.Limit('rows'))
		end
		assert.equal(Rows.Limit('tankDebuffs') ~= nil, P.Caps:Client() == 'retail')
	end)
end)

----------------------------------------------------------------------------------------------------
-- Live plates
----------------------------------------------------------------------------------------------------

local function Hostile(extra)
	local spec = { name = 'Gnoll', reaction = 2, canAttack = true, canAssist = false, restricted = false }
	for k, v in pairs(extra or {}) do
		spec[k] = v
	end
	return spec
end

local function Friendly(extra)
	local spec = { name = 'Guard', reaction = 5, canAttack = false, canAssist = true, restricted = false }
	for k, v in pairs(extra or {}) do
		spec[k] = v
	end
	return spec
end

local function Resolved(styleId, kind)
	return Merge:Resolve(styleId or 'clean', kind or 'enemyNPC', 'medium')
end

local function BindTo(plate, spec)
	local token = M.ShowPlate(spec)
	local src = P.Source.NewLive(token)
	src:ReadFacts(plate.facts)
	plate:Bind(token, src)
	return token
end

local function NewLivePlate(spec, resolved)
	local plate = P.Plate.New(UIParent, false)
	local token = M.ShowPlate(spec)
	local src = P.Source.NewLive(token)
	src:ReadFacts(plate.facts)
	plate:ApplyStyle(resolved or Resolved('clean', P.Situation.Classify(plate.facts)))
	plate:Bind(token, src)
	return plate, token
end

local function Unbind(plate, token)
	plate:Unbind()
	if token and M.plates[token] then
		M.HidePlate(token)
	end
end

local function ContainerOf(plate, partId)
	local widget = plate:GetWidget(partId)
	return widget and widget.rec and widget.rec.container, widget
end

local function Group(container, key)
	local st = M.State(container)
	return st and st.groups and st.groups[key]
end

local function Last(container, method)
	local calls = M.Calls(container, method)
	return calls[#calls]
end

local function Variant(resolved, key, edit)
	local copy = P.util.Copy(resolved)
	copy.key = key
	edit(copy)
	return copy
end

-- Groups the current profile gives My debuffs (2 on Forever: the tank debuffs group)
local function MineGroups()
	return #Rows.CurrentGroups('myDebuffs')
end

if not HAS_CONTAINERS then
	describe('aura rows without containers', function()
		it('draws aura rows by the Lua scan on live plates', function()
			assert.is_false(P.Caps:Get('secrets'), 'a client with secrets and no containers shows no aura rows')
			local plate, token = NewLivePlate(Hostile())
			local widget = plate:GetWidget('mine')
			assert.not_nil(widget)
			assert.equal(widget.impl.id, 'aurasScan')
			assert.equal(Containers:CountFor(plate), 0)
			Unbind(plate, token)
		end)
	end)
	return
end

describe('aura containers: one per row', function()
	it('makes one container per positioned row, anchored at the holder corner', function()
		local plate, token = NewLivePlate(Hostile())
		assert.equal(Containers:CountFor(plate), 2, 'the Clean style has two aura rows')
		local mine, widget = ContainerOf(plate, 'mine')
		assert.not_nil(mine)
		assert.equal(widget.impl.id, 'aurasContainer')
		assert.equal(M.Get(mine, 'auraTemplate'), true)
		local point = M.Get(mine, 'points')[1]
		assert.equal(point[1], 'BOTTOMLEFT', 'a row above the name grows from its bottom left')
		assert.equal(point[2], widget.frame)
		assert.equal(Last(mine, 'SetFlowLayoutAnchorPoint')[1], 'BOTTOMLEFT')
		local cc = ContainerOf(plate, 'cc')
		assert.equal(M.Get(cc, 'points')[1][1], 'TOPLEFT')
		assert.equal(Group(mine, 'g1').filter, 'HARMFUL|!CROWD_CONTROL|INCLUDE_NAME_PLATE_ONLY|PLAYER')
		assert.is_true(Group(mine, 'g1').candidateFilters.nameplateShowPersonal)
		if FOREVER then
			assert.equal(Group(mine, 'g2').filter, 'HARMFUL', 'tank debuffs from anyone')
			assert.truthy(Has(Group(mine, 'g2').candidateFilters.includeSpellIDs, 7386))
			assert.truthy(Has(Group(mine, 'g1').candidateFilters.excludeSpellIDs, 7386), 'my own Sunder shows once')
		else
			assert.same(Group(mine, 'g1').candidateFilters, { nameplateShowPersonal = true })
			assert.is_nil(Group(mine, 'g2'))
		end
		assert.equal(Group(cc, 'g1').filter, 'HARMFUL|CROWD_CONTROL')
		Unbind(plate, token)
	end)

	it('binds to the unit on add and goes back to none on remove', function()
		local plate, token = NewLivePlate(Hostile())
		local mine = ContainerOf(plate, 'mine')
		assert.equal(mine:GetUnit(), token)
		assert.is_true(mine:IsEnabled())
		assert.equal(Group(mine, 'g1').maxFrameCount, 6)
		plate:Unbind()
		assert.equal(mine:GetUnit(), 'none')
		assert.is_false(mine:IsEnabled())
		M.HidePlate(token)
	end)

	it('sets up every aura button in initializeFrame', function()
		local plate, token = NewLivePlate(Hostile())
		local mine = ContainerOf(plate, 'mine')
		local buttons = buttonsOf[mine]
		assert.equal(#buttons, 10 * MineGroups(), 'one batch of ten buttons per group')
		for _, button in ipairs(buttons) do
			local rec = fake[button]
			assert.equal(Count(rec, 'SetIcon'), 1)
			assert.equal(Count(rec, 'SetDurationCooldown'), 1)
			assert.equal(Count(rec, 'SetDurationText'), 1, 'timer text on by default')
			assert.equal(Count(rec, 'SetApplicationCount'), 1, 'stack text on by default')
			assert.equal(Count(rec, 'AddPandemicRegion'), 0, 'pandemic glow is off by default')
			assert.equal(M.Get(button, 'w'), 20)
		end
		local built, made = Containers:Stats()
		assert.truthy(built >= 2)
		assert.truthy(made >= 20)
		assert.not_nil(P.Caps.recorded.pandemic, 'the first button records the pandemic answer')
		Unbind(plate, token)
	end)

	it('sends nothing again when nothing changed', function()
		local plate, token = NewLivePlate(Hostile())
		local mine = ContainerOf(plate, 'mine')
		local before = #M.Calls(mine)
		plate:Configure()
		plate:Configure()
		assert.equal(#M.Calls(mine), before)
		Unbind(plate, token)
	end)

	it('makes no container for a row that is off', function()
		P.Store:Set({ 'auras', 'myDebuffs', 'on' }, false)
		P.Store:Set({ 'auras', 'crowdControl', 'on' }, false)
		local plate, token = NewLivePlate(Hostile())
		assert.equal(Containers:CountFor(plate), 0)
		P.Store:Set({ 'auras', 'myDebuffs', 'on' }, nil)
		P.Store:Set({ 'auras', 'crowdControl', 'on' }, nil)
		plate:Configure()
		assert.equal(Containers:CountFor(plate), 2, 'turning the rows on makes them')
		Unbind(plate, token)
	end)

	it('wraps a row with several groups at its own length', function()
		local plate, token = NewLivePlate(Hostile())
		local mine = ContainerOf(plate, 'mine')
		-- Clean: 6 icons of 20 with 2 between
		assert.equal(Last(mine, 'SetFlowLayoutMaximumLineSize')[1], 130.5)
		Unbind(plate, token)
	end)
end)

describe('aura containers: per-add flips', function()
	after_each(function()
		P.Store:Set({ 'auras' }, nil)
	end)

	it('switches a row off with max frame count 0 and binds it to none', function()
		local plate, token = NewLivePlate(Hostile())
		local cc = ContainerOf(plate, 'cc')
		assert.is_true(cc:IsEnabled())
		P.Store:Set({ 'auras', 'crowdControl', 'on' }, false)
		plate:Configure()
		assert.equal(Group(cc, 'g1').maxFrameCount, 0)
		assert.is_false(cc:IsEnabled())
		assert.equal(cc:GetUnit(), 'none')
		P.Store:Set({ 'auras', 'crowdControl', 'on' }, nil)
		plate:Configure()
		assert.equal(Group(cc, 'g1').maxFrameCount, 2)
		assert.equal(cc:GetUnit(), token)
		Unbind(plate, token)
	end)

	it('turns spell-list groups off on units the list cannot apply to, by count only', function()
		P.Store:Set({ 'auras', 'myDebuffs', 'always' }, { [589] = 'mine' })
		local plate, token = NewLivePlate(Hostile())
		local mine = ContainerOf(plate, 'mine')
		assert.equal(Group(mine, 'g1').maxFrameCount, 6, 'the list group shows on enemies')
		assert.equal(Group(mine, 'g2').maxFrameCount, 6)
		if FOREVER then
			assert.equal(Group(mine, 'g3').maxFrameCount, 6, 'tank debuffs on enemies')
		end
		local filtersBefore = #M.Calls(mine, 'SetAuraGroupFilterString')
		local candidatesBefore = #M.Calls(mine, 'SetAuraGroupCandidateFilters')
		Unbind(plate, token)
		local friendToken = BindTo(plate, Friendly())
		assert.equal(Group(mine, 'g1').maxFrameCount, 0, 'debuff lists do not apply on friends')
		assert.equal(Group(mine, 'g2').maxFrameCount, 6)
		if FOREVER then
			assert.equal(Group(mine, 'g3').maxFrameCount, 0, 'the tank list does not apply on friends')
		end
		assert.equal(mine:GetUnit(), friendToken)
		assert.equal(#M.Calls(mine, 'SetAuraGroupFilterString'), filtersBefore, 'never by rewriting filters')
		assert.equal(#M.Calls(mine, 'SetAuraGroupCandidateFilters'), candidatesBefore)
		Unbind(plate, friendToken)
	end)

	it('keeps debuff lists on for neutral units, which cannot be helped', function()
		P.Store:Set({ 'auras', 'myDebuffs', 'always' }, { [589] = 'mine' })
		local plate, token = NewLivePlate(Hostile({ reaction = 4, canAttack = false, name = 'Boar' }))
		local mine = ContainerOf(plate, 'mine')
		assert.equal(Group(mine, 'g1').maxFrameCount, 6)
		Unbind(plate, token)
	end)

	it('shows Enemy buffs I can remove on enemies only', function()
		local resolved = Variant(Resolved('clean', 'enemyNPC'), 'auras-test-removable', function(copy)
			copy.parts.cc.row = 'removable'
		end)
		local plate, token = NewLivePlate(Hostile(), resolved)
		local row = ContainerOf(plate, 'cc')
		assert.equal(Group(row, 'g1').filter, 'HELPFUL|DISPELLABLE')
		assert.is_true(row:IsEnabled())
		Unbind(plate, token)
		local friendToken = BindTo(plate, Friendly())
		assert.equal(Group(row, 'g1').maxFrameCount, 0)
		assert.is_false(row:IsEnabled(), 'nothing applies, so the engine stops reading')
		assert.equal(row:GetUnit(), 'none')
		Unbind(plate, friendToken)
	end)

	it('follows a unit whose reaction changes while it is shown', function()
		P.Store:Set({ 'auras', 'myDebuffs', 'always' }, { [589] = 'mine' })
		local plate, token = NewLivePlate(Friendly())
		local mine = ContainerOf(plate, 'mine')
		assert.equal(Group(mine, 'g1').maxFrameCount, 0)
		plate.facts.reaction, plate.facts.canAttack = 2, true
		local widget = plate:GetWidget('mine')
		widget.impl.Update(widget, plate.src, 'FACTS_POLLED')
		assert.equal(Group(mine, 'g1').maxFrameCount, 6)
		Unbind(plate, token)
	end)

	it('switches groups a row no longer uses off with max frame count 0', function()
		P.Store:Set({ 'auras', 'myDebuffs', 'always' }, { [589] = 'mine', [172] = 'any' })
		local plate, token = NewLivePlate(Hostile())
		local mine = ContainerOf(plate, 'mine')
		assert.not_nil(Group(mine, 'g3'))
		P.Store:Set({ 'auras', 'myDebuffs', 'always' }, nil)
		plate:Configure()
		assert.equal(Group(mine, 'g1').filter, 'HARMFUL|!CROWD_CONTROL|INCLUDE_NAME_PLATE_ONLY|PLAYER', 'groups are repointed, not added')
		local used = MineGroups()
		for i = used + 1, 3 do
			assert.equal(Group(mine, 'g' .. i).maxFrameCount, 0, 'g' .. i)
		end
		if mine.SetAuraGroupEnabled then
			assert.is_false(Last(mine, 'SetAuraGroupEnabled')[2])
		end
		Unbind(plate, token)
	end)
end)

describe('aura containers: restricted changes', function()
	after_each(function()
		M.SetRestricted(false)
		P.Store:Set({ 'auras' }, nil)
		P:Fire('RESTRICTION_CHANGED', false)
	end)

	it('holds settings while auras are secret, keeps the per-add flips, and applies them when the lock lifts', function()
		local plate, token = NewLivePlate(Hostile())
		local mine, widget = ContainerOf(plate, 'mine')
		M.SetRestricted(true)
		assert.is_true(P.Secret.IsRestricted())
		local calls = { 'AddAuraGroup', 'SetAuraGroupFilterString', 'SetAuraGroupCandidateFilters', 'SetAuraGroupLayout', 'SetFlowLayoutAnchorPoint' }
		local before = {}
		for _, name in ipairs(calls) do
			before[name] = #M.Calls(mine, name)
		end
		P.Store:Set({ 'auras', 'myDebuffs', 'never' }, { [8921] = 'any' })
		plate:Refresh({ auras = true })
		assert.is_true(plate.pendingConfigure)
		-- A style change while restricted lays the row out again; its new settings must wait
		plate:ApplyStyle(Variant(plate.style, 'auras-test-restricted', function(copy)
			copy.parts.mine.size = 22
		end))
		for _, name in ipairs(calls) do
			assert.equal(#M.Calls(mine, name), before[name], name .. ' waits')
		end
		assert.is_true(Containers:IsPending(widget))
		assert.not_nil(Containers:Explain(widget), 'the inspector can say why')
		assert.equal(M.Get(buttonsOf[mine][1], 'w'), 20, 'buttons keep their size until the lock lifts')

		-- A new unit still binds and flips while restricted
		Unbind(plate, token)
		local token2 = BindTo(plate, Hostile({ name = 'Kobold' }))
		assert.equal(mine:GetUnit(), token2)
		assert.is_true(mine:IsEnabled())
		assert.equal(Group(mine, 'g1').maxFrameCount, 6)

		M.SetRestricted(false)
		P:Fire('RESTRICTION_CHANGED', false)
		assert.is_false(Containers:IsPending(widget))
		assert.truthy(Has(Group(mine, 'g1').candidateFilters.excludeSpellIDs, 8921))
		assert.equal(M.Get(buttonsOf[mine][1], 'w'), 22)
		assert.is_nil(plate.pendingConfigure)
		assert.is_nil(Containers:Explain(widget))
		Unbind(plate, token2)
	end)

	it('makes no container during combat and makes it when combat ends', function()
		P.Scheduler:Enable()
		M.EnterCombat()
		local plate, token = NewLivePlate(Hostile())
		assert.equal(Containers:CountFor(plate), 0, 'containers are only made out of combat (S6)')
		local _, widget = ContainerOf(plate, 'mine')
		assert.is_nil(widget.rec)
		assert.is_true(Containers:IsPending(widget))
		M.LeaveCombat()
		assert.equal(Containers:CountFor(plate), 2)
		local mine = ContainerOf(plate, 'mine')
		assert.equal(mine:GetUnit(), token, 'the row binds as soon as it exists')
		Unbind(plate, token)
		P.Scheduler:Disable()
	end)

	it('skips buttons the game made forbidden', function()
		local plate, token = NewLivePlate(Hostile())
		local mine = ContainerOf(plate, 'mine')
		local forbidden = buttonsOf[mine][1]
		fake[forbidden].forbidden = true
		local resolved = Variant(plate.style, 'auras-test-size', function(copy)
			copy.parts.mine.size = 26
		end)
		plate:ApplyStyle(resolved)
		assert.equal(M.Get(buttonsOf[mine][2], 'w'), 26)
		assert.equal(M.Get(forbidden, 'w'), 20, 'a forbidden button is left alone')
		Unbind(plate, token)
	end)

	it('switches a hidden row off at once, even while restricted', function()
		local plate, token = NewLivePlate(Hostile())
		local cc = ContainerOf(plate, 'cc')
		M.SetRestricted(true)
		plate:ApplyStyle(Variant(plate.style, 'auras-test-no-cc', function(copy)
			copy.parts.cc = nil
			for i = #copy.order, 1, -1 do
				if copy.order[i] == 'cc' then
					table.remove(copy.order, i)
				end
			end
		end))
		assert.is_false(cc:IsEnabled(), 'the engine stops reading auras for a row that is gone')
		assert.equal(cc:GetUnit(), 'none')
		assert.equal(Containers:FreeFor(plate), 1, 'its container waits in the pool')
		Unbind(plate, token)
	end)
end)

describe('aura containers: pooling', function()
	after_each(function()
		P.Caps:SetOverride('containerMove', nil)
		P.Caps.recorded.containerMove = nil
	end)

	it('reuses a plate container across units', function()
		local plate, token = NewLivePlate(Hostile())
		local mine = ContainerOf(plate, 'mine')
		local built = Containers:Stats()
		Unbind(plate, token)
		local token2 = BindTo(plate, Hostile({ name = 'Murloc' }))
		assert.equal(ContainerOf(plate, 'mine'), mine)
		assert.equal(Containers:Stats(), built)
		assert.equal(mine:GetUnit(), token2)
		Unbind(plate, token2)
	end)

	local function RenameMine(plate, key, row)
		return Variant(plate.style, key, function(copy)
			copy.parts.debuffs = copy.parts.mine
			copy.parts.debuffs.row = row
			copy.parts.mine = nil
			for i, id in ipairs(copy.order) do
				if id == 'mine' then
					copy.order[i] = 'debuffs'
				end
			end
		end)
	end

	it('hands a container to the next style row instead of making a new one', function()
		local plate, token = NewLivePlate(Hostile())
		local mine = ContainerOf(plate, 'mine')
		local built = Containers:Stats()
		local count = Containers:CountFor(plate)
		plate:ApplyStyle(RenameMine(plate, 'auras-test-rows', 'removable'))
		plate:UpdateAll('FULL')
		local moved, widget = ContainerOf(plate, 'debuffs')
		assert.equal(moved, mine, 'the container moved to the new row')
		assert.equal(M.Get(moved, 'parent'), widget.frame)
		assert.equal(Containers:Stats(), built)
		assert.equal(Containers:CountFor(plate), count)
		assert.equal(Group(moved, 'g1').filter, 'HELPFUL|DISPELLABLE')
		assert.equal(moved:GetUnit(), token)
		assert.is_true(P.Caps:Get('containerMove'), 'the move was recorded')
		Unbind(plate, token)
	end)

	it('makes a new container when the game will not move one', function()
		P.Caps:SetOverride('containerMove', false)
		local plate, token = NewLivePlate(Hostile())
		local mine = ContainerOf(plate, 'mine')
		local count = Containers:CountFor(plate)
		plate:ApplyStyle(RenameMine(plate, 'auras-test-nomove', 'removable'))
		plate:UpdateAll('FULL')
		local fresh, widget = ContainerOf(plate, 'debuffs')
		assert.not_equal(fresh, mine)
		assert.equal(M.Get(fresh, 'parent'), widget.frame)
		assert.equal(Containers:CountFor(plate), count + 1)
		assert.equal(#M.Calls(mine, 'SetParent'), 0, 'nothing is moved')
		assert.is_false(mine:IsEnabled(), 'the old row is off')
		Unbind(plate, token)
	end)

	it('stops at three rows a plate and says so', function()
		local plate, token = NewLivePlate(Hostile())
		local many = Variant(plate.style, 'auras-test-many', function(copy)
			for i = 1, 4 do
				local id = 'extra' .. i
				copy.parts[id] = P.util.Copy(copy.parts.cc)
				copy.order[#copy.order + 1] = id
			end
		end)
		plate:ApplyStyle(many)
		assert.equal(Containers.MAX_PER_PLATE, 3)
		assert.equal(Containers:CountFor(plate), 3)
		local _, last = ContainerOf(plate, 'extra4')
		assert.is_nil(last.rec)
		assert.is_false(Containers:IsPending(last), 'a row with no room does not wait forever')
		assert.not_nil(Containers:Explain(last))
		Unbind(plate, token)
	end)
end)

describe('aura containers: button styles', function()
	it('adds and removes the pandemic glow in the shape this client uses', function()
		local plate, token = NewLivePlate(Hostile())
		local on = Variant(plate.style, 'auras-test-pandemic', function(copy)
			copy.parts.mine.pandemic = true
		end)
		plate:ApplyStyle(on)
		local mine = ContainerOf(plate, 'mine')
		local button = buttonsOf[mine][1]
		local rec = fake[button]
		assert.equal(Count(rec, 'AddPandemicRegion'), 1)
		assert.equal(#rec.regions, 1)
		assert.equal(M.Get(M.Get(rec.regions[1], 'parent'), 'parent'), button, 'the shared glow, hung from the icon')
		if REGION_SHAPE then
			assert.equal(#rec.animations, 1, '12.1.5 pulses the glow')
		end
		-- Restyling with the glow still on adds nothing twice
		plate:ApplyStyle(Variant(plate.style, 'auras-test-pandemic-big', function(copy)
			copy.parts.mine.size = 24
		end))
		assert.equal(Count(rec, 'AddPandemicRegion'), 1)
		local off = Variant(plate.style, 'auras-test-pandemic-off', function(copy)
			copy.parts.mine.pandemic = false
		end)
		plate:ApplyStyle(off)
		assert.equal(Count(rec, 'RemovePandemicRegion'), 1)
		assert.equal(#rec.regions, 0)
		if REGION_SHAPE then
			assert.equal(#rec.animations, 0)
		end
		Unbind(plate, token)
	end)

	it('lets the engine color the border by dispel type', function()
		local plate, token = NewLivePlate(Hostile())
		plate:ApplyStyle(Variant(plate.style, 'auras-test-dispel', function(copy)
			copy.parts.mine.borderStyle = 'dispel'
		end))
		local mine = ContainerOf(plate, 'mine')
		local rec = fake[buttonsOf[mine][1]]
		assert.equal(Count(rec, 'AddDispelTypeTexture'), 1)
		local call
		for _, c in ipairs(rec.calls) do
			if c.name == 'AddDispelTypeTexture' then
				call = c
			end
		end
		assert.equal(call[2].style, Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset)
		assert.is_true(call[2].showWhenHelpful)
		plate:ApplyStyle(Variant(plate.style, 'auras-test-pixel', function(copy)
			copy.parts.mine.borderStyle = 'pixel'
		end))
		assert.equal(Count(rec, 'ClearDispelTypeTextures'), 1)
		Unbind(plate, token)
	end)

	it('turns timer and stack text off and on', function()
		local plate, token = NewLivePlate(Hostile())
		plate:ApplyStyle(Variant(plate.style, 'auras-test-text', function(copy)
			copy.parts.mine.timer = false
			copy.parts.mine.stacks = false
		end))
		local mine = ContainerOf(plate, 'mine')
		local rec = fake[buttonsOf[mine][1]]
		assert.equal(Count(rec, 'ClearDurationText'), 1)
		assert.equal(Count(rec, 'ClearApplicationCount'), 1)
		plate:ApplyStyle(Variant(plate.style, 'auras-test-text-on', function(copy)
			copy.parts.mine.timer = true
			copy.parts.mine.stacks = true
		end))
		assert.equal(Count(rec, 'SetDurationText'), 2)
		assert.equal(Count(rec, 'SetApplicationCount'), 2)
		Unbind(plate, token)
	end)

	it('grows rows the way the part says', function()
		local plate, token = NewLivePlate(Hostile())
		plate:ApplyStyle(Variant(plate.style, 'auras-test-grow', function(copy)
			copy.parts.cc.grow = 'LEFT'
			copy.parts.cc.perRow = 1
			copy.parts.cc.max = 3
		end))
		local cc = ContainerOf(plate, 'cc')
		assert.equal(M.Get(cc, 'points')[1][1], 'TOPRIGHT')
		local growth = Last(cc, 'SetFlowLayoutGrowthDirection')
		assert.equal(growth[1], -1, 'left')
		assert.equal(Last(cc, 'SetFlowLayoutMaximumLineSize')[1], 24.5, 'one icon per line')
		plate:ApplyStyle(Variant(plate.style, 'auras-test-grow-up', function(copy)
			copy.parts.cc.grow = 'UP'
		end))
		-- AnchorUtil.FlowLayoutAxis.Vertical (1 on every client with containers)
		assert.equal(Last(cc, 'SetFlowLayoutAxis')[1], 1)
		Unbind(plate, token)
	end)

	it('sorts by time when the part asks', function()
		local plate, token = NewLivePlate(Hostile())
		plate:ApplyStyle(Variant(plate.style, 'auras-test-sort', function(copy)
			copy.parts.mine.sort = 'time'
		end))
		local mine = ContainerOf(plate, 'mine')
		local call = Last(mine, 'SetAuraGroupSortMethod')
		assert.equal(call[2], AuraContainerSortMethod.Expiration)
		assert.equal(call[3], AuraContainerSortDirection.Normal)
		Unbind(plate, token)
	end)

	it('only ever sends filters the game accepts', function()
		local sent = {}
		for i, filter in ipairs(sentFilters) do
			sent[i] = filter
		end
		assert.truthy(#sent > 0)
		for _, filter in ipairs(sent) do
			assert.no_errors(function()
				ValidateFilter(filter, 2)
			end)
			assert.falsy(filter:find('HELPFUL', 1, true) and filter:find('HARMFUL', 1, true), filter)
		end
	end)
end)

describe('aura containers: engine off', function()
	it('stops every container when the engine turns off', function()
		local plate, token = NewLivePlate(Hostile())
		local mine = ContainerOf(plate, 'mine')
		local cc = ContainerOf(plate, 'cc')
		assert.is_true(mine:IsEnabled())
		P:Fire('ENGINE_DISABLED')
		assert.is_false(mine:IsEnabled(), 'even before the plate is unbound')
		assert.equal(mine:GetUnit(), 'none')
		assert.is_false(cc:IsEnabled())
		Unbind(plate, token)
	end)
end)

----------------------------------------------------------------------------------------------------
-- Aura presence tints (Phase 5)
----------------------------------------------------------------------------------------------------

describe('aura presence tints', function()
	local hasKind = P.Colors:GetKind('hasAura')
	local missingKind = P.Colors:GetKind('auraMissing')

	before_each(function()
		hasKind.available = true
		missingKind.available = true
		P.Store:Set({ 'scheme' }, 'custom')
		P.Store:Set({ 'colors', 'health', 'order' }, { 'hasAura', 'auraMissing', 'reaction' })
		P.Store:Set({ 'colors', 'health', 'spells' }, { hasAura = { [589] = 'mine' }, auraMissing = { [172] = 'mine', [980] = 'mine' } })
		P.Colors:Invalidate()
	end)
	after_each(function()
		hasKind.available = false
		missingKind.available = false
		P.Store:Set({ 'colors' }, nil)
		P.Store:Reset({ 'scheme' })
		P.Colors:Invalidate()
		M.SetRestricted(false)
	end)

	it('makes no slots container while no presence row is on', function()
		hasKind.available = false
		missingKind.available = false
		P.Colors:Invalidate()
		local plate, token = NewLivePlate(Hostile())
		assert.is_nil(P.AuraPresence:State(plate))
		Unbind(plate, token)
	end)

	it('hangs tints from collapsing slots and binds them on enemies', function()
		local plate, token = NewLivePlate(Hostile())
		local st = P.AuraPresence:State(plate)
		assert.not_nil(st)
		assert.equal(#slotsOf[st.container], 3, 'one slot per tracked spell')
		for _, slot in ipairs(slotsOf[st.container]) do
			assert.equal(Count(fake[slot], 'SetIcon'), 0, 'slots draw nothing themselves')
		end
		local slotCalls = M.Calls(st.container, 'AddAuraSlot')
		assert.equal(slotCalls[1][2], 'HARMFUL|PLAYER')
		assert.same(slotCalls[1][3].candidateFilters, { includeSpellIDs = { [589] = true } })
		assert.equal(st.used, 2, 'one tint for Has, one for Missing')
		P.AuraPresence:Flip(plate)
		assert.equal(st.container:GetUnit(), token)
		assert.is_true(st.container:IsEnabled())
		assert.is_true(st.tints[1]:IsShown())
		assert.is_true(st.tints[2]:IsShown())
		local missingMask = st.masks[2]
		assert.equal(M.Get(missingMask, 'points')[1][2], st.pillars[2], 'the Missing mask rides on the pillar')
		Unbind(plate, token)
		P:Fire('PLATE_REMOVED', plate, token)
		assert.is_false(st.container:IsEnabled())
		assert.is_false(st.tints[1]:IsShown())
	end)

	it('keeps tints off on friends, where the spell list cannot apply', function()
		local plate, token = NewLivePlate(Friendly())
		local st = P.AuraPresence:State(plate)
		P.AuraPresence:Flip(plate)
		assert.is_false(st.container:IsEnabled())
		assert.equal(st.container:GetUnit(), 'none')
		for i = 1, st.used do
			assert.is_false(st.tints[i]:IsShown())
		end
		Unbind(plate, token)
	end)

	it('parks slots the rows no longer use', function()
		local plate, token = NewLivePlate(Hostile())
		local st = P.AuraPresence:State(plate)
		P.Store:Set({ 'colors', 'health', 'spells' }, { hasAura = { [589] = 'mine' } })
		P.AuraPresence:Configure(plate)
		assert.equal(st.used, 1)
		assert.equal(#slotsOf[st.container], 3, 'slots are never removed')
		if st.container.SetAuraSlotEnabled then
			assert.is_false(Last(st.container, 'SetAuraSlotEnabled')[2])
		else
			assert.same(Last(st.container, 'SetAuraSlotCandidateFilters')[2], { includeSpellIDs = { [0] = true } })
		end
		Unbind(plate, token)
	end)

	it('waits while restricted and builds when the lock lifts', function()
		M.SetRestricted(true)
		local plate, token = NewLivePlate(Hostile())
		assert.is_nil(P.AuraPresence:State(plate), 'no slots are made while restricted')
		M.SetRestricted(false)
		P:Fire('RESTRICTION_CHANGED', false)
		local st = P.AuraPresence:State(plate)
		assert.not_nil(st)
		assert.equal(#slotsOf[st.container], 3)
		Unbind(plate, token)
	end)
end)
