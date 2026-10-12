-- @runtime lua51
-- Share strings (plan 3.6, contracts 12): "!NP:<schema>:<kind>!<body>" round trips for every kind,
-- bad strings are refused with a reason, strings from a newer version are never imported, and a
-- style import is upgraded, validated, saved, and can later update its base while the player's
-- own changes stay. The mock client has no codec, so this suite installs a plain stand-in for
-- C_EncodingUtil (a Lua-literal serializer, a marker for compression and real base64).
local M, H = ...

if not H.ModuleExists() then
	describe('share', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

----------------------------------------------------------------------------------------------------
-- Codec stand-in
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

local function InstallCodec()
	if not C_EncodingUtil then
		rawset(_G, 'C_EncodingUtil', {})
	end
	for name, fn in pairs(codec) do
		C_EncodingUtil[name] = fn
	end
end
InstallCodec()

----------------------------------------------------------------------------------------------------

local P = H.FreshCore()
local Share = P.Share
local Store = P.Store
local Registry, Merge, Schema = P.Styles.Registry, P.Styles.Merge, P.Styles.Schema
P.services.GetAccent = function()
	return 1, 1, 1
end
P.services.FontPath = function()
	return 'Fonts\\Test.ttf'
end

local function Body(kind, payload, schema)
	return '!NP:' .. (schema or P.VERSION.schema) .. ':' .. kind .. '!' .. EncodeBase64(MARK .. Serialize(payload))
end

describe('share: strings', function()
	it('round trips every kind', function()
		local payloads = {
			style = { style = Merge:Bake('clean'), name = 'Clean copy', author = 'Jane', version = 3 },
			colors = { scheme = 'custom', colors = { health = { order = { 'tapped', 'reaction' }, color = { tapped = { 0.5, 0.5, 0.5, 1 } } } }, threat = { when = 'always' } },
			when = { when = { { conditions = { { id = 'place', args = 'raid' } }, style = 'mini', size = 'small' } } },
			profile = { profile = { size = 'large', scheme = 'mobType' }, styles = {} },
		}
		for kind, payload in pairs(payloads) do
			local text, reason = Share:Encode(kind, payload)
			assert.not_nil(text, kind .. ': ' .. tostring(reason))
			assert.matches(text, '^!NP:' .. P.VERSION.schema .. ':' .. kind .. '!')
			local decoded, why = Share:Decode(text)
			assert.not_nil(decoded, kind .. ': ' .. tostring(why))
			assert.equal(decoded.kind, kind)
			assert.equal(decoded.schema, P.VERSION.schema)
			assert.same(decoded.payload, payload, kind .. ' payload')
		end
	end)

	it('keeps decimals exactly through a round trip', function()
		local text = Share:Encode('colors', { colors = { health = { fallback = { 0.1, 0.7, 0.35, 0.6 } } } })
		local decoded = Share:Decode(text)
		assert.same(decoded.payload.colors.health.fallback, { 0.1, 0.7, 0.35, 0.6 })
	end)

	it('reads strings with spaces around them and line breaks inside', function()
		local text = Share:Encode('when', { when = {} })
		local prefix, body = text:match('^(.-!)(.+)$')
		local wrapped = '  \n' .. prefix .. body:sub(1, 10) .. '\n' .. body:sub(11) .. '  \n'
		local decoded, why = Share:Decode(wrapped)
		assert.not_nil(decoded, tostring(why))
		assert.same(decoded.payload, { when = {} })
	end)

	it('refuses a kind it does not know when building a string', function()
		local text, reason = Share:Encode('banana', {})
		assert.is_nil(text)
		assert.equal(reason, 'kind')
	end)

	local bad = {
		{ '', 'format' },
		{ 'hello there', 'format' },
		{ '!NP:style!abcd', 'format' },
		{ '!NP:x:style!abcd', 'format' },
		{ '!NP:1:style!', 'format' },
		{ '!NP:1:banana!' .. EncodeBase64(MARK .. '{}'), 'kind' },
		{ '!NP:1:style!@@@@', 'decode' },
		{ '!NP:1:style!' .. EncodeBase64('not compressed'), 'decode' },
		{ '!NP:1:style!' .. EncodeBase64(MARK .. 'return os.exit()'), 'decode' },
		{ '!NP:1:style!' .. EncodeBase64(MARK .. '"just text"'), 'decode' },
	}
	for i, case in ipairs(bad) do
		it(('refuses bad string %d with "%s"'):format(i, case[2]), function()
			local decoded, reason = Share:Decode(case[1])
			assert.is_nil(decoded)
			assert.equal(reason, case[2])
		end)
	end

	it('refuses things that are not text', function()
		local decoded, reason = Share:Decode(nil)
		assert.is_nil(decoded)
		assert.equal(reason, 'format')
		decoded, reason = Share:Decode({})
		assert.equal(reason, 'format')
	end)

	it('refuses a string from a newer version before reading its body', function()
		local newer = Body('style', { style = Merge:Bake('clean'), name = 'From later' }, P.VERSION.schema + 1)
		local decoded, reason = Share:Decode(newer)
		assert.is_nil(decoded)
		assert.equal(reason, 'newer')
		decoded, reason = Share:Decode('!NP:' .. (P.VERSION.schema + 1) .. ':style!garbage')
		assert.equal(reason, 'newer', 'even with a broken body')
		local id, why = Share:ImportStyle(newer)
		assert.is_nil(id)
		assert.equal(why, 'newer')
		assert.is_nil(P.db.global.styles, 'nothing was saved')
	end)

	it('reports unavailable when the client has no codec', function()
		local saved = C_EncodingUtil.SerializeCBOR
		C_EncodingUtil.SerializeCBOR = nil
		local text, reason = Share:Encode('when', { when = {} })
		C_EncodingUtil.SerializeCBOR = saved
		assert.is_nil(text)
		assert.equal(reason, 'unavailable')
	end)

	it('has player text for every reason, naming the host for newer strings', function()
		for _, reason in ipairs({ 'newer', 'unavailable', 'kind', 'cycle', 'format', 'decode' }) do
			local text = Share:ReasonText(reason)
			assert.equal(type(text), 'string')
			assert.truthy(#text > 0)
		end
		assert.matches(Share:ReasonText('newer'), P:HostName(), 'names the host')
	end)
end)

describe('share: styles', function()
	before_each(function()
		Store:Set('tweaks', nil)
		Store:Set('styles', nil, 'global')
	end)

	it('exports the base with the player changes baked in and imports it as a new style', function()
		Store:Set('tweaks.clean.changes.parts.name.font.size', 13)
		Store:Set('tweaks.clean.remove.forces', true)
		local text = Share:ExportStyle('clean', 'Jane')
		assert.not_nil(text)
		Store:Set('tweaks', nil)
		local id, reason = Share:ImportStyle(text)
		assert.not_nil(id, tostring(reason))
		assert.is_true(Registry:IsSaved(id))
		local entry = P.db.global.styles[id]
		assert.equal(entry.source.kind, 'import')
		assert.equal(entry.source.author, 'Jane')
		assert.equal(entry.source.styleId, 'clean')
		local resolved = Merge:Resolve(id, 'enemyNPC', 'medium')
		assert.equal(resolved.parts.name.font.size, 13)
		assert.is_nil(resolved.parts.forces)
		assert.equal(Merge:Resolve('clean', 'enemyNPC', 'medium').parts.name.font.size, 10, 'Clean itself is untouched')
	end)

	it('never overwrites: importing twice makes two styles', function()
		local text = Share:ExportStyle('mini')
		local a = Share:ImportStyle(text, 'First')
		local b = Share:ImportStyle(text, 'Second')
		assert.not_equal(a, b)
		assert.equal(Registry:Get(a).name, 'First')
		assert.equal(Registry:Get(b).name, 'Second')
	end)

	it('updates the base of an earlier import and keeps the player changes to it', function()
		local base = Merge:Bake('clean')
		base.id = 'shared1'
		base.version = 1
		local v1 = Share:Encode('style', { style = base, name = 'Shared', author = 'Jane', version = 1 })
		local id = Share:ImportStyle(v1)
		Store:Set({ 'tweaks', id, 'changes', 'parts', 'hp', 'font', 'size' }, 12)
		local updated = Merge:Bake('clean')
		updated.id = 'shared1'
		updated.parts.cast.height = 12
		local v2 = Share:Encode('style', { style = updated, name = 'Shared', author = 'Jane', version = 2 })
		local preview = Share:InspectStyle(v2)
		assert.equal(preview.updateOf, id)
		assert.is_true(preview.isNewer)
		assert.equal(Share:ImportStyle(v2, nil, 'update'), id)
		local resolved = Merge:Resolve(id, 'enemyNPC', 'medium')
		assert.equal(resolved.parts.cast.height, 12, 'the new base')
		assert.equal(resolved.parts.hp.font.size, 12, 'the player change is kept')
		assert.equal(P.db.global.styles[id].source.version, 2)
		local again = Share:InspectStyle(v2)
		assert.is_false(again.isNewer, 'the same version is not newer')
	end)

	it('does not treat another author with the same style id as an update', function()
		local base = Merge:Bake('clean')
		base.id = 'shared2'
		Share:ImportStyle(Share:Encode('style', { style = base, name = 'One', author = 'Jane', version = 1 }))
		local preview = Share:InspectStyle(Share:Encode('style', { style = base, name = 'Two', author = 'Sam', version = 2 }))
		assert.is_nil(preview.updateOf)
	end)

	it('cleans what it does not know and reports it, without rejecting the style', function()
		local style = Merge:Bake('mini')
		style.parts.health.mystery = 1
		style.extra = true
		style.parts.health.height = 5000
		local preview, reason = Share:InspectStyle(Share:Encode('style', { style = style, name = 'Odd' }))
		assert.not_nil(preview, tostring(reason))
		assert.equal(preview.report.dropped, 2)
		assert.equal(preview.report.clamped, 1)
		assert.is_nil(preview.style.parts.health.mystery)
	end)

	it('refuses a style whose parts point at each other in a loop', function()
		local style = Merge:Bake('mini')
		style.parts.marker.anchor = { 'LEFT', 'arrows', 'RIGHT', 0, 0 }
		style.parts.arrows.anchor = { 'LEFT', 'marker', 'RIGHT', 0, 0 }
		local id, reason = Share:ImportStyle(Share:Encode('style', { style = style, name = 'Loop' }))
		assert.is_nil(id)
		assert.equal(reason, 'cycle')
	end)

	it('refuses a style made for a newer format inside an older string', function()
		local style = Merge:Bake('mini')
		style.schema = Schema.CURRENT + 1
		local id, reason = Share:ImportStyle(Share:Encode('style', { style = style, name = 'Later' }))
		assert.is_nil(id)
		assert.equal(reason, 'newer')
	end)

	it('refuses other kinds of strings and payloads with no parts', function()
		local _, reason = Share:InspectStyle(Share:Encode('colors', { scheme = 'class' }))
		assert.equal(reason, 'kind')
		_, reason = Share:InspectStyle(Share:Encode('style', { name = 'Nothing' }))
		assert.equal(reason, 'noParts')
	end)

	it('shortens long names and authors', function()
		local long = string.rep('n', 80)
		local preview = Share:InspectStyle(Share:Encode('style', { style = Merge:Bake('mini'), name = long, author = long }))
		assert.equal(#preview.name, 48)
		assert.equal(#preview.author, 48)
	end)

	it('imports through the public API', function()
		local id = P.API:ImportStyle(Share:ExportStyle('mini'), 'From API')
		assert.not_nil(id)
		assert.equal(Registry:Get(id).name, 'From API')
	end)
end)
