-- @runtime lua51
-- Phase 9 wiring and share format 2, on every client: the style schema takes the spec, role and
-- totem sources and the bar that steps aside for a totem; Customize names them in plain words;
-- Mini shows a known totem's icon in place of its bar (live and in previews); previews have
-- samples for spec, role and totem marks and for the special mobs color row; share strings keep
-- the special mobs list (checked like any pasted text); "When" and profile strings carry the
-- "When" actions, refuse rules a newer version made and say so, and undo them with the rest.
local M, H = ...

if not H.ModuleExists() then
	describe('phase 9 wiring', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

----------------------------------------------------------------------------------------------------
-- Codec stand-in (the mock client has none; same as sharing_spec)
----------------------------------------------------------------------------------------------------

local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local B64INDEX = {}
for i = 1, #B64 do
	B64INDEX[B64:sub(i, i)] = i - 1
end

local function EncodeBase64(data)
	local out = {}
	for i = 1, #data, 3 do
		local a, b, c = data:byte(i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local d1, d2, d3, d4 = math.floor(n / 262144) % 64, math.floor(n / 4096) % 64, math.floor(n / 64) % 64, n % 64
		out[#out + 1] = B64:sub(d1 + 1, d1 + 1) .. B64:sub(d2 + 1, d2 + 1) .. (b and B64:sub(d3 + 1, d3 + 1) or '=') .. (c and B64:sub(d4 + 1, d4 + 1) or '=')
	end
	return table.concat(out)
end

local function DecodeBase64(text)
	if #text % 4 ~= 0 or text:find('[^%w%+/=]') then
		error('not base64')
	end
	local out = {}
	for i = 1, #text, 4 do
		local chunk = text:sub(i, i + 3)
		local n, pad = 0, 0
		for j = 1, 4 do
			local ch = chunk:sub(j, j)
			if ch == '=' then
				pad = pad + 1
				n = n * 64
			else
				n = n * 64 + B64INDEX[ch]
			end
		end
		local bytes = string.char(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
		out[#out + 1] = bytes:sub(1, 3 - pad)
	end
	return table.concat(out)
end

local function Serialize(v)
	local t = type(v)
	if t == 'string' then
		return string.format('%q', v)
	elseif t == 'number' then
		return string.format('%.17g', v)
	elseif t == 'boolean' then
		return tostring(v)
	elseif t == 'table' then
		local keys = {}
		for k in pairs(v) do
			keys[#keys + 1] = k
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		local parts = {}
		for _, k in ipairs(keys) do
			parts[#parts + 1] = '[' .. Serialize(k) .. ']=' .. Serialize(v[k])
		end
		return '{' .. table.concat(parts, ',') .. '}'
	end
	error('cannot serialize a ' .. t)
end

local function Deserialize(text)
	local chunk = assert(loadstring('return ' .. text))
	setfenv(chunk, {})
	return chunk()
end

local MARK = 'packed:'
local codec = {
	SerializeCBOR = Serialize,
	DeserializeCBOR = Deserialize,
	CompressString = function(text)
		return MARK .. text
	end,
	DecompressString = function(text)
		if text:sub(1, #MARK) ~= MARK then
			error('not compressed')
		end
		return text:sub(#MARK + 1)
	end,
	EncodeBase64 = EncodeBase64,
	DecodeBase64 = DecodeBase64,
}

if not C_EncodingUtil then
	rawset(_G, 'C_EncodingUtil', {})
end
for name, fn in pairs(codec) do
	C_EncodingUtil[name] = fn
end

----------------------------------------------------------------------------------------------------

M.Login('NameplatesTestHost')

local P = H.FreshCore({
	host = {
		GetHostProfileName = function()
			return 'Default'
		end,
	},
})
P.services.GetAccent = function()
	return 1, 1, 1
end
P.services.FontPath = function()
	return 'Fonts\\Test.ttf'
end

local Schema, Merge, Registry = P.Styles.Schema, P.Styles.Merge, P.Styles.Registry
local Store, Exchange, Share = P.Store, P.Exchange, P.Share

local function Alpha(region)
	local alpha = M.Get(region, 'alpha')
	if alpha == nil then
		return 1
	end
	return alpha
end

local function Lines(info)
	return table.concat(Exchange:Describe(info), '\n')
end

---A share string, or skip on a client that cannot make one.
local function Encode(kind, payload)
	local text = Share:Encode(kind, payload)
	if not text then
		skip('this client cannot make share strings')
	end
	return text
end

---The same string stamped with another format number (the body does not depend on it).
local function Stamped(text, schema)
	return (string.gsub(text, '^!NP:%d+:', '!NP:' .. schema .. ':'))
end

----------------------------------------------------------------------------------------------------

describe('phase 9 wiring: the style schema', function()
	it('accepts the spec, role and totem sources and the bar that steps aside', function()
		local style = {
			id = 'phaseNine',
			name = 'Phase nine',
			version = 1,
			schema = 1,
			parts = {
				health = { order = 1, kind = 'bar', source = 'health', fill = 'plate', hideOnTotem = true },
				spec = { order = 2, kind = 'text', source = 'specName', anchor = { 'BOTTOM', 'health', 'TOP', 0, 2 } },
				specIcon = { order = 3, kind = 'icon', source = 'specIcon', anchor = { 'RIGHT', 'health', 'LEFT', -2, 0 }, size = 14 },
				role = { order = 4, kind = 'icon', source = 'roleIcon', anchor = { 'LEFT', 'health', 'RIGHT', 2, 0 }, size = 14 },
				totem = { order = 5, kind = 'icon', source = 'totem', anchor = { 'CENTER', 'health', 'CENTER', 0, 0 }, size = 14 },
			},
		}
		local cleaned, report, reason = Schema:ValidateStyle(style)
		assert.not_nil(cleaned, tostring(reason))
		assert.equal(0, report.dropped + report.clamped + report.fixed, table.concat(report.droppedKeys, ', '))
		assert.equal('specName', cleaned.parts.spec.source)
		assert.equal('specIcon', cleaned.parts.specIcon.source)
		assert.equal('roleIcon', cleaned.parts.role.source)
		assert.equal('totem', cleaned.parts.totem.source)
		assert.is_true(cleaned.parts.health.hideOnTotem)
	end)

	it('has a drawing for every source it accepts', function()
		for _, source in ipairs(Schema.TEXT_SOURCES) do
			assert.not_nil(P.TextParts.SOURCES[source], 'text source ' .. source)
		end
		for _, source in ipairs(Schema.ICON_SOURCES) do
			assert.not_nil(P.IconParts.SOURCES[source], 'icon source ' .. source)
		end
	end)

	it('is at format 2 and upgrades format 1 styles and overlays without changing them', function()
		assert.equal(2, Schema.CURRENT)
		assert.equal(Schema.CURRENT, P.VERSION.schema)
		local old = Registry:Get('clean')
		assert.equal(1, old.schema)
		local up = assert(Schema:Upgrade(old))
		assert.equal(2, up.schema)
		up.schema = 1
		assert.same(old, up)
		local overlay = { schema = 1, baseVersion = 1, changes = { parts = { name = { font = { size = 12 } } } } }
		local upOverlay = assert(Schema:UpgradeOverlay(overlay))
		assert.equal(2, upOverlay.schema)
		upOverlay.schema = 1
		assert.same(overlay, upOverlay)
		local newer, why = Schema:Upgrade({ schema = Schema.CURRENT + 1, name = 'Later', parts = {} })
		assert.is_nil(newer)
		assert.equal('newer', why)
	end)

	it('keeps every built-in valid with nothing dropped, clamped or fixed', function()
		local count = 0
		for id, style in pairs(Registry.builtin) do
			local upgraded = assert(Schema:Upgrade(style))
			local cleaned, report, reason = Schema:ValidateStyle(upgraded)
			assert.not_nil(cleaned, id .. ': ' .. tostring(reason))
			assert.equal(0, report.dropped + report.clamped + report.fixed, id .. ': ' .. table.concat(report.droppedKeys, ', '))
			count = count + 1
		end
		assert.truthy(count >= 8)
	end)
end)

----------------------------------------------------------------------------------------------------

describe('phase 9 wiring: Customize', function()
	before_each(function()
		Store:Set('tweaks', nil)
		Store:Reset('style')
	end)

	it('names every text and icon source in plain words', function()
		for _, source in ipairs(Schema.TEXT_SOURCES) do
			local label = P.Designer.TEXT_LABELS[source]
			assert.equal('string', type(label), 'text source ' .. source)
			assert.not_equal(source, label)
		end
		for _, source in ipairs(Schema.ICON_SOURCES) do
			local label = P.Designer.ICON_LABELS[source]
			assert.equal('string', type(label), 'icon source ' .. source)
			assert.not_equal(source, label)
		end
	end)

	it('offers the new sources on text and icon parts', function()
		local page = P:BuildOptionsTable().args.customize
		local text = page.args.part_name.args.source.values
		assert.equal('Player spec', text.specName)
		local icon = page.args.part_marker.args.source.values
		assert.equal('Player spec icon', icon.specIcon)
		assert.equal('Role icon', icon.roleIcon)
		assert.equal('Totem icon', icon.totem)
	end)

	it('says when a new source can stay empty', function()
		assert.equal('string', type(P.TextParts.Limit('specName')))
		assert.equal('string', type(P.IconParts.Limit('specIcon')))
		assert.equal('string', type(P.IconParts.Limit('roleIcon')))
		assert.equal('string', type(P.IconParts.Limit('totem')))
	end)

	it('lets a health bar step aside on totems from More settings', function()
		local page = P:BuildOptionsTable().args.customize
		local args = page.args.part_health.args
		local toggle = args.hideOnTotem
		assert.not_nil(toggle)
		assert.is_true(toggle.advanced)
		assert.is_false(toggle.get())
		toggle.set({}, true)
		assert.is_true(Store:Get({ 'tweaks', 'clean', 'changes', 'parts', 'health', 'hideOnTotem' }))
		assert.is_true(toggle.get())
		assert.is_true(Merge:Resolve('clean', 'enemyNPC', 'medium').parts.health.hideOnTotem)
		assert.is_nil(page.args.part_cast.args.hideOnTotem, 'only health bars have it')
	end)
end)

----------------------------------------------------------------------------------------------------

describe('phase 9 wiring: Mini shows a totem icon instead of its bar', function()
	local function Content(widget)
		local bar = widget.bar
		return { bar:GetStatusBarTexture(), bar.bg, bar.border, widget.over, widget.chunkClip, widget.low, widget.band }
	end

	local function AllFaded(widget)
		for _, region in ipairs(Content(widget)) do
			if Alpha(region) ~= 0 then
				return false
			end
		end
		return true
	end

	local function NoneFaded(widget)
		for _, region in ipairs(Content(widget)) do
			if Alpha(region) == 0 then
				return false
			end
		end
		return true
	end

	local function MiniPlate(spec)
		local token = M.ShowPlate(spec)
		local plate = P.Plate.New(UIParent, false)
		plate.situation = 'minor'
		local src = P.Source.NewLive(token)
		src:ReadFacts(plate.facts)
		plate:ApplyStyle(Merge:Resolve('mini', 'minor', 'medium'))
		plate:Bind(token, src)
		return plate, token
	end

	local TOTEM = { npcID = 5925, name = 'Grounding Totem', playerControlled = true, reaction = 2, canAttack = true }

	it('has a totem icon part and a health bar that steps aside', function()
		local mini = Registry:Get('mini')
		assert.is_true(mini.parts.health.hideOnTotem)
		assert.equal('icon', mini.parts.totem.kind)
		assert.equal('totem', mini.parts.totem.source)
		assert.equal('health', mini.parts.totem.anchor[2])
	end)

	it('swaps on a known totem and leaves the bar frame to the plate', function()
		local plate, token = MiniPlate(TOTEM)
		local health, icon = plate:GetWidget('health'), plate:GetWidget('totem')
		assert.is_true(AllFaded(health), 'the bar content fades')
		assert.not_equal(0, Alpha(health.frame), 'the plate keeps the bar frame')
		assert.not_equal(false, M.Get(health.frame, 'shown'))
		assert.is_true(M.Get(icon.texture, 'shown'))
		assert.matches(M.Get(icon.texture, 'texture'), 'GroundingTotem')
		plate:Unbind()
		assert.is_true(NoneFaded(health), 'unbinding gives the bar back')
		M.HidePlate(token)
	end)

	it('keeps the bar on other minor enemies, also on a reused plate', function()
		local plate, token = MiniPlate(TOTEM)
		local health = plate:GetWidget('health')
		plate:Unbind()
		M.HidePlate(token)
		local rat = M.ShowPlate({ npcID = 123456, name = 'Skittering Rat', classification = 'minus' })
		local src = P.Source.NewLive(rat)
		src:ReadFacts(plate.facts)
		plate:Bind(rat, src)
		assert.is_true(NoneFaded(health))
		assert.is_false(M.Get(plate:GetWidget('totem').texture, 'shown'))
		plate:Unbind()
		M.HidePlate(rat)
	end)

	it('gives the bar back when the game hides who the unit is', function()
		if not P.Caps:Get('secrets') then
			return
		end
		local plate, token = MiniPlate(TOTEM)
		local health = plate:GetWidget('health')
		assert.is_true(AllFaded(health))
		M.SetRestricted(true, nil, true)
		plate:OnMessage('IDENTITY_CHANGED')
		assert.is_true(NoneFaded(health), 'a hidden answer keeps the bar')
		M.SetRestricted(false)
		plate:OnMessage('IDENTITY_CHANGED')
		assert.is_true(AllFaded(health))
		plate:Unbind()
		M.HidePlate(token)
	end)

	it('stops swapping when the style no longer asks for it', function()
		local plate, token = MiniPlate(TOTEM)
		local health = plate:GetWidget('health')
		Store:Set({ 'tweaks', 'mini' }, { schema = Schema.CURRENT, baseVersion = 1, changes = { parts = { health = { hideOnTotem = false } } } })
		assert.is_true(plate:ApplyStyle(Merge:Resolve('mini', 'minor', 'medium')))
		plate:UpdateAll('FULL')
		assert.is_true(NoneFaded(health))
		Store:Set('tweaks', nil)
		plate:Unbind()
		M.HidePlate(token)
	end)

	it('makes no extra event work for health bars that never swap', function()
		local plate, token = MiniPlate({ npcID = 123456, name = 'Skittering Rat', classification = 'minus' })
		local clean = P.Plate.New(UIParent, false)
		local src = P.Source.NewLive(token)
		src:ReadFacts(clean.facts)
		clean:ApplyStyle(Merge:Resolve('clean', 'enemyNPC', 'medium'))
		clean:Bind(token, src)
		local events = P.Parts:Get('health').events(clean:GetWidget('health').spec)
		for _, event in ipairs(events) do
			assert.not_equal('UNIT_NAME_UPDATE', event)
		end
		assert.same({}, P.Parts:Get('health').messages(clean:GetWidget('health').spec))
		clean:Unbind()
		plate:Unbind()
		M.HidePlate(token)
	end)

	it('keeps "When" paints off the bar while it steps aside', function()
		Store:Set('actions', {
			{ conditions = {}, paint = 'health', color = { 1, 0, 0, 1 } },
			{ conditions = {}, paint = 'border', color = { 0, 0, 1, 1 } },
		})
		local rat, ratToken = MiniPlate({ npcID = 123456, name = 'Skittering Rat', classification = 'minus' })
		local st = P.Actions:StateOf(rat)
		assert.equal(1, M.Get(st.tint, 'vertex')[4], 'other minor enemies take the paint')
		assert.equal(1, M.Get(st.border.edges.top, 'vertex')[4])
		local totem, token = MiniPlate(TOTEM)
		local painted = P.Actions:StateOf(totem)
		if painted and painted.tint then
			assert.equal(0, M.Get(painted.tint, 'vertex')[4])
		end
		if painted and painted.border then
			assert.equal(0, M.Get(painted.border.edges.top, 'vertex')[4])
		end
		Store:Set('actions', nil)
		for _, plate in ipairs({ rat, totem }) do
			plate:Unbind()
		end
		M.HidePlate(ratToken)
		M.HidePlate(token)
	end)

	it('shows the totem icon on the preview sample', function()
		local plate = P.Plate.New(UIParent, true)
		plate:ApplyStyle(Merge:Resolve('mini', 'minor', 'medium'))
		plate:BindSample(P.Source.NewSample(P.Data.Samples.totem))
		assert.is_true(AllFaded(plate:GetWidget('health')))
		assert.is_true(M.Get(plate:GetWidget('totem').texture, 'shown'))
		plate:BindSample(P.Source.NewSample(P.Data.Samples.minorGray))
		assert.is_true(NoneFaded(plate:GetWidget('health')))
		plate:Unbind()
	end)
end)

----------------------------------------------------------------------------------------------------

describe('phase 9 wiring: previews', function()
	local canvas = CreateFrame('Frame', nil, UIParent)
	canvas:SetSize(338, 560)
	canvas:Show()

	after_each(function()
		P.Scenes:Release(canvas)
		Store:Set('colors', nil)
	end)

	it('has samples for spec, role and totem marks', function()
		local S = P.Data.Samples
		assert.equal('string', type(S.enemyPlayer.specName))
		assert.not_nil(S.enemyPlayer.specIcon)
		assert.equal('DAMAGER', S.enemyPlayer.role)
		local row = P.Data.Totems:ForNPC(S.totem.npcID, P.Caps:Client())
		assert.not_nil(row, 'the totem sample is a totem on this client')
		assert.equal(row.icon, S.totem.totemIcon)
		assert.equal('minor', P.Situation.Classify(S.totem.facts))
		local roles = {}
		for _, id in ipairs(P.Scenes.DEFS.battleground.samples) do
			local sample = P.Scenes.Sample(id)
			assert.not_nil(sample, id)
			if sample.facts.isPlayer and sample.facts.canAttack then
				assert.equal('string', type(sample.specName), id)
				roles[sample.role] = true
			end
		end
		assert.is_true(roles.HEALER and roles.TANK, 'healer and tank marks have something to show')
	end)

	it('draws the totem in the battleground scene with its icon', function()
		local result = P.Scenes:Render(canvas, 'battleground', { width = 338, height = 560 })
		local found
		for _, item in ipairs(result.items) do
			if item.sample and item.sample.id == 'totem' then
				found = item
			end
		end
		assert.not_nil(found, 'the scene has a totem')
		assert.equal('minor', found.situation)
		assert.not_nil(found.plate)
		local icon = found.plate:GetWidget('totem')
		assert.not_nil(icon, 'Mini draws minor plates')
		assert.is_true(M.Get(icon.texture, 'shown'))
	end)

	it('lets the special mobs row win with one of the player own mobs', function()
		Store:Set({ 'colors', 'npcs', '5925' }, { hint = 'Grounding Totem', color = { 0, 0.5, 1, 1 } })
		Store:Set({ 'colors', 'npcs', '77' }, { hint = 'No color here' })
		local ctx = P.Scenes.PreviewContext({})
		local program = P.Colors:Program('health', ctx)
		local row
		for _, item in ipairs(program.rows) do
			if item.id == 'npc' then
				row = item
			end
		end
		assert.not_nil(row, 'the list has a special mobs row')
		local sample, wins = P.Scenes:RowSample(program, row, ctx)
		assert.is_true(wins)
		assert.equal(5925, sample.npcID, 'the mob with a color')
		assert.equal('Grounding Totem', sample.label)
		local result = P.Scenes:Render(canvas, 'rows', { width = 338, height = 900, piece = 'health' })
		local drawn = false
		for _, item in ipairs(result.items) do
			if item.row and item.row.id == 'npc' and item.sample and item.sample.npcID == 5925 then
				drawn = true
			end
		end
		assert.is_true(drawn, 'the rows scene shows the mob')
	end)

	it('has no winning sample for the special mobs row without a color', function()
		Store:Set({ 'colors', 'npcs', '77' }, { hint = 'No color here' })
		local ctx = P.Scenes.PreviewContext({})
		local program = P.Colors:Program('health', ctx)
		for _, item in ipairs(program.rows) do
			if item.id == 'npc' then
				local _, wins = P.Scenes:RowSample(program, item, ctx)
				assert.is_false(wins)
			end
		end
	end)

	it('reveals the spec and role marks with Show all parts', function()
		local revealed = P.Scenes:Revealed(P.Data.Samples.casterTarget)
		assert.equal('string', type(revealed.specName))
		assert.not_nil(revealed.specIcon)
		assert.equal('HEALER', revealed.role)
		assert.is_nil(revealed.totemIcon, 'a totem icon would hide the bar')
		local src = P.Source.NewSample(revealed)
		assert.is_true(src:HasSpecSecret())
		assert.is_true(src:ShowRoleIconSecret())
	end)
end)

----------------------------------------------------------------------------------------------------

describe('phase 9 wiring: sharing the special mobs list', function()
	before_each(function()
		Store:Set('colors', nil)
		Exchange.undo = nil
	end)

	it('keeps the list in a colors string and puts it back', function()
		Store:Set({ 'colors', 'npcs', '5925' }, { hint = 'Grounding Totem', color = { 0, 0.5, 1, 1 }, rename = 'Ground' })
		Store:Set({ 'colors', 'npcs', '2523' }, { hint = 'Searing Totem' })
		local saved = P.util.Copy(Store:Get({ 'colors', 'npcs' }))
		local text = Exchange:BuildExport('colors')
		if not text then
			skip('this client cannot make share strings')
		end
		local info = assert(Exchange:Inspect(text))
		assert.same(saved, info.payload.colors.npcs)
		assert.equal(0, info.report.dropped + info.report.clamped)
		Store:Set('colors', nil)
		assert.is_true(Exchange:ApplyReplace(info).ok)
		assert.same(saved, Store:Get({ 'colors', 'npcs' }))
		assert.is_true(Exchange:Undo())
		assert.is_nil(Store:Get({ 'colors', 'npcs' }))
	end)

	it('checks ids, fields, names and colors', function()
		local text = Encode('colors', {
			colors = {
				npcs = {
					['5925'] = { hint = '  Grounding |cffff0000Totem|r  ', color = { 2, 0, 0, 1 }, rename = string.rep('a', 100), sound = 'bell' },
					abc = { hint = 'Letters' },
					['0'] = { hint = 'Zero' },
					['10000001'] = { hint = 'Too big' },
					['1.5'] = { hint = 'Half' },
					['77'] = 'not a table',
					['123'] = { color = { 0, 1, 0 } },
					['88'] = { hint = 42, rename = '   ' },
				},
			},
		})
		local info = assert(Exchange:Inspect(text))
		local npcs = info.payload.colors.npcs
		assert.equal('Grounding cffff0000Totemr', npcs['5925'].hint, 'escape codes and outer spaces go')
		assert.same({ 1, 0, 0, 1 }, npcs['5925'].color)
		assert.equal(Exchange.NPC_TEXT_MAX, #npcs['5925'].rename)
		assert.is_nil(npcs['5925'].sound)
		for _, key in ipairs({ 'abc', '0', '10000001', '1.5', '77' }) do
			assert.is_nil(npcs[key], key)
		end
		assert.same({ 0, 1, 0, 1 }, npcs['123'].color)
		assert.equal('Mob 123', npcs['123'].hint, 'a row always has a note')
		assert.equal('Mob 88', npcs['88'].hint)
		assert.is_nil(npcs['88'].rename)
		assert.equal(8, info.report.dropped)
		assert.equal(3, info.report.clamped)
	end)

	it('never splits a letter when it shortens a name', function()
		assert.equal('ab', Exchange.CutText('ab\195\169', 3))
		assert.equal('ab\195\169', Exchange.CutText('ab\195\169', 4))
		assert.equal('abc', Exchange.CutText('abc\226\130\172', 5))
		assert.equal('abc', Exchange.CutText('abc', 80))
	end)

	it('reads mob ids the way the Colors page writes them', function()
		assert.equal('5925', Exchange.NPCKey('5925'))
		assert.equal('5925', Exchange.NPCKey(5925))
		assert.equal('7', Exchange.NPCKey('007'))
		for _, bad in ipairs({ 'x1', '-1', '0', '1.5', 1.5, '10000001', true }) do
			assert.is_nil(Exchange.NPCKey(bad), tostring(bad))
		end
	end)

	it('keeps the list in a profile string and in a backup', function()
		Store:Set({ 'colors', 'npcs', '5925' }, { hint = 'Grounding Totem', color = { 0, 0.5, 1, 1 } })
		local text = Exchange:BuildExport('everything')
		if not text then
			skip('this client cannot make share strings')
		end
		local info = assert(Exchange:Inspect(text))
		assert.same(Store:Get({ 'colors', 'npcs' }), info.payload.profile.colors.npcs)
		local cleaned = Exchange:CleanProfile({ profile = { colors = { npcs = { ['42'] = { hint = 'Backup', junk = 1 } } } } })
		assert.same({ ['42'] = { hint = 'Backup' } }, cleaned.profile.colors.npcs)
	end)
end)

----------------------------------------------------------------------------------------------------

local RULES = {
	{ conditions = { { id = 'casting' } }, kinds = { 'enemyNPC' }, glow = { 1, 0.5, 0, 1 } },
	{ conditions = { { id = 'focus' } }, grow = { 24, 4 } },
}
local CASES = { { conditions = { { id = 'place', args = 'raid' } }, kinds = { 'minor' }, mode = 'hidden' } }
local MINE = { { conditions = { { id = 'target', negate = true } }, fade = 0.5 } }

local function ResetLists()
	Store:Set('when', nil)
	Store:Set('actions', nil)
	Exchange.undo = nil
end

describe('share format 2: "When" strings carry the rules', function()
	before_each(ResetLists)

	it('exports the special cases and the rules together', function()
		Store:Set('when', CASES)
		Store:Set('actions', RULES)
		local text = Exchange:BuildExport('when')
		if not text then
			skip('this client cannot make share strings')
		end
		assert.matches(text, '^!NP:2:when!')
		local decoded = assert(Share:Decode(text))
		assert.same(P.Actions:SharePayload(), decoded.payload)
		local info = assert(Exchange:Inspect(text))
		assert.same(CASES, info.payload)
		assert.same(RULES, info.actions)
		assert.equal(2, info.actionCount)
		assert.equal(0, info.report.newer + info.report.dropped)
		assert.truthy(Lines(info):find('It also has 2 rules for when something happens.', 1, true), Lines(info))
	end)

	it('replaces both lists and undoes both', function()
		Store:Set('when', CASES)
		Store:Set('actions', RULES)
		local text = Exchange:BuildExport('when')
		if not text then
			skip('this client cannot make share strings')
		end
		Store:Set('when', nil)
		Store:Set('actions', MINE)
		local result = Exchange:ApplyReplace(assert(Exchange:Inspect(text)))
		assert.is_true(result.ok)
		assert.matches(result.message, 'rules')
		assert.same(CASES, Store:Get('when'))
		assert.same(RULES, Store:Get('actions'))
		assert.equal('special cases and rules', Exchange.undo.label)
		assert.is_true(Exchange:Undo())
		assert.is_nil(Store:Get('when'))
		assert.same(MINE, Store:Get('actions'))
	end)

	it('leaves out rules a newer version made and tells the player', function()
		local text = Encode('when', {
			when = {},
			actions = {
				RULES[1],
				{ conditions = { { id = 'target' } }, sound = 'bell' },
				{ conditions = { { id = 'someFutureCondition' } }, glow = { 1, 1, 1, 1 } },
				{ conditions = { { id = 'target' } }, mark = 'banana' },
			},
		})
		local info = assert(Exchange:Inspect(text))
		assert.equal(1, info.actionCount)
		assert.equal(2, info.report.newer)
		assert.equal(1, info.report.dropped)
		local lines = Lines(info)
		assert.truthy(lines:find(string.format('2 rules need a newer version of %s, so they were left out.', P:HostName()), 1, true), lines)
		assert.truthy(lines:find('1 setting was not recognized', 1, true), lines)
		Exchange:ApplyReplace(info)
		assert.same({ RULES[1] }, Store:Get('actions'))
		local one = assert(Exchange:Inspect(Encode('when', { when = {}, actions = { { conditions = { { id = 'target' } }, sound = 'bell' } } })))
		assert.truthy(Lines(one):find(string.format('1 rule needs a newer version of %s, so it was left out.', P:HostName()), 1, true))
	end)

	it("leaves the player's rules alone for a string without rules", function()
		Store:Set('actions', MINE)
		local info = assert(Exchange:Inspect(Encode('when', { when = CASES })))
		assert.is_nil(info.actions)
		assert.is_nil(Lines(info):find('rule', 1, true))
		local result = Exchange:ApplyReplace(info)
		assert.is_false(result.message:find('rules', 1, true) ~= nil)
		assert.same(CASES, Store:Get('when'))
		assert.same(MINE, Store:Get('actions'))
	end)

	it('says so when using a string clears your rules', function()
		Store:Set('actions', MINE)
		local info = assert(Exchange:Inspect(Encode('when', { when = CASES, actions = {} })))
		assert.equal(0, info.actionCount)
		assert.truthy(Lines(info):find('It has no rules for when something happens, so using it also clears yours.', 1, true))
		Exchange:ApplyReplace(info)
		assert.is_nil(Store:Get('actions'))
		Store:Set('actions', nil)
		assert.is_nil(Lines(info):find('clears yours', 1, true), 'nothing to clear, nothing said')
	end)

	it('treats rules in a format 1 string as newer', function()
		local text = Stamped(Encode('when', { when = CASES, actions = RULES }), 1)
		local info = assert(Exchange:Inspect(text))
		assert.equal(0, info.actionCount)
		assert.equal(2, info.report.newer)
	end)

	it('refuses a whole string from a newer format', function()
		local decoded, reason = Share:Decode('!NP:' .. (Schema.CURRENT + 1) .. ':when!AAAA')
		assert.is_nil(decoded)
		assert.equal('newer', reason)
	end)
end)

describe('share format 2: profile strings carry the rules', function()
	before_each(ResetLists)

	it('shares the rules on purpose', function()
		local shared, kept = false, false
		for _, key in ipairs(Exchange.PROFILE_KEYS) do
			shared = shared or key == 'actions'
		end
		for _, key in ipairs(Exchange.PROFILE_KEYS_KEPT_OUT) do
			kept = kept or key == 'actions'
		end
		assert.is_true(shared)
		assert.is_false(kept)
	end)

	it('carries the rules with everything and undoes them', function()
		Store:Set('actions', RULES)
		local text = Exchange:BuildExport('everything')
		if not text then
			skip('this client cannot make share strings')
		end
		local info = assert(Exchange:Inspect(text))
		assert.same(RULES, info.payload.profile.actions)
		assert.is_nil(info.payload.keepActions)
		Store:Set('actions', MINE)
		assert.is_true(Exchange:ApplyReplace(info).ok)
		assert.same(RULES, Store:Get('actions'))
		assert.is_true(Exchange:Undo())
		assert.same(MINE, Store:Get('actions'))
	end)

	it('clears the rules when the shared profile has none', function()
		local text = Exchange:BuildExport('everything')
		if not text then
			skip('this client cannot make share strings')
		end
		Store:Set('actions', MINE)
		Exchange:ApplyReplace(assert(Exchange:Inspect(text)))
		assert.is_nil(Store:Get('actions'))
	end)

	it("keeps the player's rules for a format 1 profile string", function()
		Store:Set('actions', MINE)
		local text = Stamped(Encode('profile', { profile = { style = 'clean', actions = { { conditions = {}, fade = 0.2 } } }, styles = {} }), 1)
		local info = assert(Exchange:Inspect(text))
		assert.is_true(info.payload.keepActions)
		assert.equal(1, info.report.newer)
		assert.truthy(Lines(info):find('1 rule needs a newer version', 1, true))
		Exchange:ApplyReplace(info)
		assert.same(MINE, Store:Get('actions'))
		assert.equal('clean', Store:Get('style'))
		assert.is_true(Exchange:Undo())
	end)

	it('cleans the rules of a backup the same way', function()
		local cleaned, report = Exchange:CleanProfile({ profile = { actions = { RULES[1], { conditions = {}, sound = 'bell' }, 'junk' } } })
		assert.same({ RULES[1] }, cleaned.profile.actions)
		assert.equal(1, report.newer)
		assert.equal(1, report.dropped)
		assert.is_nil(cleaned.keepActions)
	end)
end)
