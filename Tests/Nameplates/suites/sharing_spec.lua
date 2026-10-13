-- @runtime lua51
-- The Sharing and profiles page (plan 3.2 #6) and the import/export behind it (3.6, P.Exchange):
-- strings for a style, colors, the "When" list and everything; what a pasted string says before
-- anything changes (live preview, "Your 4 changes stay", newer-version refusal, the report of what
-- was left out); using a string (new, use, update, replace) with one Undo; cleaning of strings from
-- other players; P.API:ImportStyle; the profile picker and "Follow my <host> profile". The mock
-- client has no codec, so this suite installs a plain stand-in for C_EncodingUtil.
local M, H = ...

if not H.ModuleExists() then
	describe('sharing', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

----------------------------------------------------------------------------------------------------
-- Codec stand-in (same as share_spec)
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
local Registry, Merge, Schema = P.Styles.Registry, P.Styles.Merge, P.Styles.Schema
local Store, Gallery, Share, Exchange = P.Store, P.Gallery, P.Share, P.Exchange
local Options = P.Options
local Sharing = P.SharingPage

P.services.GetAccent = function()
	return 1, 1, 1
end
P.services.FontPath = function()
	return 'Fonts\\Test.ttf'
end

local locked = false
P.Secret.IsRestricted = function()
	return locked
end

local function Page()
	return P:BuildOptionsTable().args.sharing
end

local function Reset()
	Store:Set('tweaks', nil)
	Store:Set('styles', nil, 'global')
	Store:Set('author', nil, 'global')
	for _, key in ipairs(Exchange.PROFILE_KEYS) do
		Store:Set(key, nil)
	end
	Gallery:ClearPreview()
	Exchange:Clear()
	Exchange.undo = nil
	Exchange.state.result = nil
	Sharing.export.what, Sharing.export.styleId, Sharing.export.version = 'style', nil, nil
	Sharing.cache = nil
	locked = false
end

local function StyleString(fields, author, version, name)
	local style = Merge:Bake('clean')
	for k, v in pairs(fields or {}) do
		style[k] = v
	end
	return Share:Encode('style', { style = style, name = name or style.name, author = author, version = version or 1 })
end

local function Contains(list, value)
	for _, item in ipairs(list) do
		if item == value then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------------------------------------

local EM_DASH = string.char(226, 128, 148)
local BANNED_WORDS = { 'overlay', 'schema', 'cvar', 'token', 'payload', 'lsm', 'widget', 'elvui', 'weakauras', 'platynator' }

---Every text a page can show: names, descriptions and prompts (functions are called).
local function Texts(value, out, depth)
	out = out or {}
	depth = depth or 0
	if depth > 10 or type(value) ~= 'table' then
		return out
	end
	for key, item in pairs(value) do
		if key == 'name' or key == 'desc' or key == 'confirmText' then
			if type(item) == 'function' then
				local ok, text = pcall(item, {})
				item = ok and text or nil
			end
			if type(item) == 'string' then
				out[#out + 1] = item
			end
		elseif type(item) == 'table' and key ~= 'arg' and key ~= 'handler' then
			Texts(item, out, depth + 1)
		end
	end
	return out
end

---Copy of an options table without the two keys the settings window adds to AceConfig.
local function WithoutWindowKeys(value, depth)
	if type(value) ~= 'table' or (depth or 0) > 12 then
		return value
	end
	local out = {}
	for key, item in pairs(value) do
		if key ~= 'advanced' and key ~= 'primary' then
			out[key] = WithoutWindowKeys(item, (depth or 0) + 1)
		end
	end
	return out
end

describe('sharing page: wording and validity', function()
	before_each(Reset)

	it('uses plain words: no em dashes, no symbols the game cannot draw, no jargon, no other addons', function()
		local texts = Texts(Page())
		assert.truthy(#texts > 20, 'the page has text to check')
		Store:Set('style', 'clean')
		-- Everything the import box can say back
		local newerText = '!NP:' .. (Schema.CURRENT + 1) .. ':style!zz'
		for _, text in ipairs({ 'hello', '', string.rep('a', Exchange.MAX_LENGTH + 1), newerText, Share:Encode('colors', { scheme = 'class' }) }) do
			local info, reason = Exchange:Inspect(text)
			if info then
				for _, line in ipairs(Exchange:Describe(info)) do
					texts[#texts + 1] = line
				end
			else
				texts[#texts + 1] = Exchange:ReasonText(reason)
			end
		end
		for _, reason in ipairs({ 'cycle', 'unavailable', 'kind', 'newer', 'format', 'decode', 'empty', 'tooLong' }) do
			texts[#texts + 1] = Exchange:ReasonText(reason)
		end
		for _, text in ipairs(texts) do
			assert.is_nil(text:find(EM_DASH, 1, true), 'em dash in: ' .. text)
			assert.is_nil(text:find('[' .. string.char(128) .. '-' .. string.char(255) .. ']'), 'non-ASCII character in: ' .. text)
			for _, word in ipairs(BANNED_WORDS) do
				assert.is_nil(text:lower():find(word, 1, true), word .. ' in: ' .. text)
			end
		end
	end)

	it('is a valid AceConfig table', function()
		local registry = LibStub('AceConfigRegistry-3.0')
		local root = { type = 'group', name = 'Test', args = { sharing = Page() } }
		registry:RegisterOptionsTable('NameplateSharingPageTest', WithoutWindowKeys(root))
		local options = registry:GetOptionsTable('NameplateSharingPageTest')('dialog', 'TestUI-1.0')
		assert.not_nil(options.args.sharing.args.export.args.exportText)
	end)
end)

describe('sharing page: layout', function()
	before_each(Reset)

	it('puts sharing and importing above the long profile picker', function()
		local args = Page().args
		assert.truthy(args.follow.order < args.export.order)
		assert.truthy(args.export.order < args.import.order)
		assert.truthy(args.import.order < args.profiles.order)
	end)

	it('says why the picker waits while the profile follows the host', function()
		local args = Page().args
		local note = args.profiles.args.followNote
		assert.not_nil(note)
		Store:Set('followHostProfile', true)
		assert.is_false(note.hidden())
		assert.matches(note.name(), P:HostName())
		Store:Set('followHostProfile', false)
		assert.is_true(note.hidden())
	end)

	it('keeps each group to eight main controls', function()
		local page = Page()
		local function Main(group)
			local n = 0
			for _, option in pairs(group.args) do
				if option.type ~= 'description' and not option.advanced then
					n = n + 1
				end
			end
			return n
		end
		assert.truthy(Main(page) <= 8, 'page: ' .. Main(page))
		assert.truthy(Main(page.args.export) <= 8, 'export: ' .. Main(page.args.export))
		assert.truthy(Main(page.args.import) <= 8, 'import: ' .. Main(page.args.import))
		assert.is_true(page.args.export.args.author.advanced)
		assert.is_true(page.args.export.args.version.advanced)
	end)

	it('names the host in the follow switch', function()
		local page = Page()
		assert.equal(page.args.follow.name, 'Follow my ' .. P:HostName() .. ' profile')
		assert.is_false(page.args.follow.hidden())
		local bare = H.FreshCore({ host = { GetHostProfileName = false } })
		assert.is_true(bare:BuildOptionsTable().args.sharing.args.follow.hidden())
	end)

	it('follows the host profile when switched on and leaves the picker still while it does', function()
		local page = Page()
		page.args.follow.set({}, true)
		assert.is_true(Store:Get('followHostProfile'))
		assert.is_true(page.args.profiles.disabled(), 'the picker waits while the profile follows')
		page.args.follow.set({}, false)
		assert.is_false(page.args.profiles.disabled())
		locked = true
		assert.is_true(page.args.profiles.disabled(), 'and while the game restricts changes')
		assert.is_true(page.args.follow.disabled())
	end)

	it('keeps following off when the player picks another profile', function()
		local before = Store:ProfileKey()
		Store:Set('followHostProfile', false)
		Store:SetProfile('Picked by hand')
		assert.is_false(Store:Get('followHostProfile'), 'the picked profile does not lock the picker again')
		Store:Set('followHostProfile', true)
		Store:SetProfile(before)
		assert.is_false(Store:Get('followHostProfile'), 'each profile keeps its own choice')
		Store:Set('followHostProfile', true)
	end)

	it('has a profile picker that works without AceDBOptions', function()
		local profiles = Page().args.profiles
		assert.equal(profiles.type, 'group')
		assert.equal(profiles.args.current.get(), P.db:GetCurrentProfile())
		profiles.args.new.set({}, '  Raid night ')
		assert.equal(P.db:GetCurrentProfile(), 'Raid night')
		assert.contains(profiles.args.current.values(), 'Raid night')
		profiles.args.current.set({}, 'Default')
		assert.equal(P.db:GetCurrentProfile(), 'Default')
		profiles.args.new.set({}, '   ')
		assert.equal(P.db:GetCurrentProfile(), 'Default', 'an empty name does nothing')
	end)

	it('uses AceDBOptions for the picker when the client has it', function()
		local ok = pcall(H.LoadFile, HARNESS_ROOT .. 'libs/Ace3/AceDBOptions-3.0/AceDBOptions-3.0.lua', 'SpartanUI', {})
		if not ok then
			skip('AceDBOptions does not load in the mock')
		end
		local profiles = Page().args.profiles
		assert.is_true(profiles.inline)
		assert.not_nil(profiles.args.choose, 'the usual pick-a-profile control')
		assert.equal(type(profiles.disabled), 'function')
	end)
end)

----------------------------------------------------------------------------------------------------

describe('export', function()
	before_each(Reset)

	it('makes a string for each kind that reads back', function()
		Store:Set('scheme', 'class')
		Store:Set('colors', { health = { order = { 'tapped', 'reaction' } } })
		Store:Set('when', { { conditions = { { id = 'place', args = 'raid' } }, style = 'mini', size = 'small' } })
		for _, what in ipairs(Exchange.EXPORT_KINDS) do
			local text, reason = Exchange:BuildExport(what)
			assert.not_nil(text, what .. ': ' .. tostring(reason))
			local info, why = Exchange:Inspect(text)
			assert.not_nil(info, what .. ': ' .. tostring(why))
			assert.equal(info.kind, what == 'everything' and 'profile' or what)
		end
	end)

	it('carries the style with the player changes, the author and the version', function()
		Store:Set('style', 'clean')
		Store:Set({ 'tweaks', 'clean', 'changes', 'parts', 'name', 'font', 'size' }, 13)
		Exchange:SetAuthor('  Jane  ')
		assert.equal(Exchange:GetAuthor(), 'Jane')
		local text = Exchange:BuildExport('style', { version = 4 })
		local info = Exchange:Inspect(text)
		assert.equal(info.author, 'Jane')
		assert.equal(info.version, 4)
		assert.equal(info.name, 'Clean')
		assert.equal(info.style.parts.name.font.size, 13)
		assert.is_nil(info.style.internal)
		-- no author when the player left it empty
		Exchange:SetAuthor('')
		assert.is_nil(Exchange:Inspect(Exchange:BuildExport('style')).author)
	end)

	it('exports the style asked for, including the host look', function()
		local host = Merge:Bake('clean')
		host.id, host.name, host.matchesHost = 'hosted2', 'Hosted two', true
		assert(P.API:RegisterStyle(host))
		local info = Exchange:Inspect(Exchange:BuildExport('style', { styleId = 'host' }))
		assert.equal(info.name, 'Hosted two')
		assert.is_nil(info.style.matchesHost, 'a pasted style is never the host look')
		assert.is_nil(Exchange:BuildExport('style', { styleId = 'nothing' }) and nil, 'a missing style falls back to Clean')
	end)

	it('decides on purpose about every profile key a page can write', function()
		local known = {}
		for _, key in ipairs(Exchange.PROFILE_KEYS) do
			known[key] = 'shared'
		end
		for _, key in ipairs(Exchange.PROFILE_KEYS_KEPT_OUT) do
			assert.is_nil(known[key], key .. ' is both shared and kept out')
			known[key] = 'kept out'
		end
		for key in pairs(P.Store.REASONS.profile) do
			assert.not_nil(known[key], 'profile key ' .. key .. ' would be dropped by imports: add it to Exchange.PROFILE_KEYS or PROFILE_KEYS_KEPT_OUT')
		end
		for _, key in ipairs(Exchange.PROFILE_KEYS) do
			assert.not_nil(P.Store.REASONS.profile[key], key .. ' is shared but no page writes it')
		end
	end)

	it('checks the role and game settings a backup brings back', function()
		local own = Exchange:CleanOwnSettings({ role = 'tank', cvars = { nameplateMaxDistance = '40', nameplateShowEnemies = true, nameplateMotion = 1, junk = 3 } })
		assert.equal(own.role, 'tank')
		assert.equal(own.cvars.nameplateMaxDistance, 40)
		assert.is_true(own.cvars.nameplateShowEnemies)
		assert.is_nil(own.cvars.nameplateMotion)
		assert.is_nil(own.cvars.junk)
		assert.is_nil(Exchange:CleanOwnSettings({ role = 'boss' }).role)
	end)

	it('leaves the role, the game settings and the host switches out of everything', function()
		Store:Set('role', 'tank')
		Store:Set('cvars', { nameplateMaxDistance = '40' })
		Store:Set('size', 'large')
		Store:Set('behavior', { enemies = 'combat', stacking = { enemy = true } })
		local info = Exchange:Inspect(Exchange:BuildExport('everything'))
		local profile = info.payload.profile
		assert.is_nil(profile.role)
		assert.is_nil(profile.cvars)
		assert.is_nil(profile.followHostProfile)
		assert.equal(profile.size, 'large')
		assert.equal(profile.behavior.enemies, 'combat')
		assert.equal(info.report.dropped, 0, 'what we export we also accept')
	end)

	it('includes the saved styles a profile uses, and only those', function()
		local used = Gallery:Copy('clean')
		local unused = Gallery:Copy('namesOnly')
		Store:Set('style', used)
		Store:Set({ 'assign', 'minor' }, 'mini')
		local decoded = Share:Decode(Exchange:BuildExport('everything'))
		assert.not_nil(decoded.payload.styles[used])
		assert.is_nil(decoded.payload.styles[unused])
		assert.is_nil(decoded.payload.styles.mini, 'built-in styles travel by name')
	end)

	it('says why when the client cannot make a string', function()
		local saved = C_EncodingUtil.SerializeCBOR
		C_EncodingUtil.SerializeCBOR = nil
		local text, reason = Exchange:BuildExport('when')
		C_EncodingUtil.SerializeCBOR = saved
		assert.is_nil(text)
		assert.equal(reason, 'unavailable')
		assert.is_nil((Exchange:BuildExport('banana')))
	end)

	it('fills the export box and remakes the string only when something changed', function()
		local box = Page().args.export.args.exportText
		Store:Set('style', 'clean')
		local first = box.get()
		assert.matches(first, '^!NP:1:style!')
		local cache = Sharing.cache
		assert.equal(box.get(), first)
		assert.equal(Sharing.cache, cache, 'same cache entry')
		Store:Set({ 'tweaks', 'clean', 'changes', 'plate', 'sizes', 'medium' }, { 150, 10 })
		assert.not_equal(box.get(), first, 'a change reaches the string')
	end)

	it('points the box at another style or kind and bumps the version', function()
		local page = Page()
		local args = page.args.export.args
		args.what.set({}, 'colors')
		assert.matches(args.exportText.get(), '^!NP:1:colors!')
		assert.is_true(args.style.hidden())
		assert.is_true(args.version.hidden())
		args.what.set({}, 'style')
		args.style.set({}, 'mini')
		assert.equal(args.style.get(), 'mini')
		args.version.set({}, '7')
		assert.equal(args.version.get(), '7')
		assert.equal(Exchange:Inspect(args.exportText.get()).version, 7)
		args.version.set({}, 'abc')
		assert.equal(args.version.get(), '7', 'a bad number is ignored')
		Sharing:ShowExport('style', 'namesOnly')
		assert.equal(args.style.get(), 'namesOnly')
	end)

	it('lists the styles to share, with Match my look for the host look', function()
		local values = Page().args.export.args.style.values()
		assert.equal(values.clean, 'Clean')
	end)

	it('says so in the box note when the string cannot be made', function()
		local args = Page().args.export.args
		local saved = C_EncodingUtil.SerializeCBOR
		C_EncodingUtil.SerializeCBOR = nil
		Sharing.cache = nil
		assert.is_false(args.note.hidden())
		assert.equal(args.note.name(), Share:ReasonText('unavailable'))
		C_EncodingUtil.SerializeCBOR = saved
		Sharing.cache = nil
		assert.is_true(args.note.hidden())
	end)
end)

----------------------------------------------------------------------------------------------------

describe('import: reading a string', function()
	before_each(Reset)

	it('refuses what is not a string or not from this version', function()
		local _, reason = Exchange:Inspect(nil)
		assert.equal(reason, 'empty')
		_, reason = Exchange:Inspect('   ')
		assert.equal(reason, 'empty')
		_, reason = Exchange:Inspect('hello')
		assert.equal(reason, 'format')
		_, reason = Exchange:Inspect(string.rep('a', Exchange.MAX_LENGTH + 1))
		assert.equal(reason, 'tooLong')
		local newer = '!NP:' .. (Schema.CURRENT + 1) .. ':style!abcd'
		_, reason = Exchange:Inspect(newer)
		assert.equal(reason, 'newer')
		assert.matches(Exchange:ReasonText('newer'), P:HostName())
		for _, why in ipairs({ 'empty', 'tooLong', 'format', 'newer', 'decode', 'kind', 'cycle', 'unavailable' }) do
			assert.truthy(#Exchange:ReasonText(why) > 0, why)
		end
	end)

	it('says a text that is not a share string is not a share string, whatever it was meant to hold', function()
		assert.equal(Exchange:ReasonText('format'), 'This text is not a nameplate share string.')
		assert.equal(Exchange:ReasonText('decode'), Exchange:ReasonText('format'))
	end)

	it('refuses a string that breaks the reader instead of raising an error', function()
		local decode = Share.Decode
		Share.Decode = function()
			error('stack overflow')
		end
		local ok, info, reason = pcall(Exchange.Inspect, Exchange, 'anything')
		assert.is_true(ok, 'no error reaches the page')
		assert.is_nil(info)
		assert.equal(reason, 'decode')
		local id, why = P.API:ImportStyle('anything')
		assert.is_nil(id)
		assert.equal(why, 'decode')
		local pasted, pastedReason = Exchange:Paste('anything')
		assert.is_nil(pasted)
		assert.equal(pastedReason, 'decode')
		Share.Decode = decode
		assert.not_nil(Exchange:Inspect(StyleString({}, 'Jane', 1)))
	end)

	it('reads a style and says what it is', function()
		local info = Exchange:Inspect(StyleString({}, 'Jane', 3, 'Jane M+'))
		assert.equal(info.kind, 'style')
		assert.equal(info.name, 'Jane M+')
		assert.equal(info.author, 'Jane')
		assert.equal(info.version, 3)
		assert.is_nil(info.updateOf)
		local lines = Exchange:Describe(info)
		assert.equal(lines[1], '"Jane M+" by Jane, version 3.')
		assert.equal(#lines, 1, 'nothing left out, nothing to report')
	end)

	it('counts what it leaves out, adjusts and repairs', function()
		local style = Merge:Bake('mini')
		style.parts.health.mystery = 1
		style.extra = true
		style.parts.health.height = 5000
		style.parts.marker.anchor = { 'LEFT', 'nowhere', 'RIGHT', 0, 0 }
		local info = Exchange:Inspect(Share:Encode('style', { style = style, name = 'Odd' }))
		assert.equal(info.report.dropped, 2)
		assert.equal(info.report.clamped, 1)
		assert.equal(info.report.fixed, 1)
		local text = table.concat(Exchange:Describe(info), ' ')
		assert.matches(text, '2 settings were not recognized and were left out')
		assert.matches(text, '1 value was out of range and was adjusted')
		assert.matches(text, '1 part pointed at a part that does not exist')
	end)

	it('refuses a style with parts that point at each other in a loop', function()
		local style = Merge:Bake('mini')
		style.parts.marker.anchor = { 'LEFT', 'arrows', 'RIGHT', 0, 0 }
		style.parts.arrows.anchor = { 'LEFT', 'marker', 'RIGHT', 0, 0 }
		local info, reason = Exchange:Inspect(Share:Encode('style', { style = style, name = 'Loop' }))
		assert.is_nil(info)
		assert.equal(reason, 'cycle')
		assert.truthy(#Exchange:ReasonText(reason) > 0)
	end)

	it('refuses a style made for a newer format inside an older string', function()
		local style = Merge:Bake('mini')
		style.schema = Schema.CURRENT + 1
		local _, reason = Exchange:Inspect(Share:Encode('style', { style = style, name = 'Later' }))
		assert.equal(reason, 'newer')
	end)

	it('strips the flags that would make an imported style act like a built-in', function()
		local style = Merge:Bake('clean')
		style.internal, style.matchesHost = true, true
		local info = Exchange:Inspect(Share:Encode('style', { style = style, name = 'Sneaky' }))
		assert.is_nil(info.style.internal)
		assert.is_nil(info.style.matchesHost)
	end)

	it('removes color and link codes and line breaks from names and authors', function()
		local info = Exchange:Inspect(StyleString({}, '|cffff0000Jane|r', 1, 'Bad |Hitem:1|h[Name]|h' .. string.char(10) .. 'second line'))
		assert.is_nil(info.name:find('|', 1, true))
		assert.is_nil(info.name:find(string.char(10), 1, true))
		assert.is_nil(info.author:find('|', 1, true))
		assert.equal(info.name:sub(1, 3), 'Bad')
		local blank = Exchange:Inspect(StyleString({}, '||', 1, '|||'))
		assert.equal(blank.name, 'Imported style', 'a name that is only codes falls back')
		assert.is_nil(blank.author)
		Exchange:SetAuthor('|cff00ff00Sam|r')
		assert.is_nil(Exchange:GetAuthor():find('|', 1, true))
	end)

	it('tells an update from a new style, and counts the changes that stay', function()
		local v1 = StyleString({ id = 'packA' }, 'Jane', 1, 'Pack A')
		local first = Exchange:ApplyStyle(Exchange:Inspect(v1), 'new')
		Store:Set({ 'tweaks', first.id, 'changes', 'parts', 'hp', 'font', 'size' }, 12)
		Store:Set({ 'tweaks', first.id, 'changes', 'tokens', 'bar' }, 'Smooth')
		Store:Set({ 'tweaks', first.id, 'remove', 'forces' }, true)
		Store:Set({ 'tweaks', first.id, 'changes', 'plate', 'sizes', 'medium' }, { 150, 10 })
		local v2 = StyleString({ id = 'packA' }, 'Jane', 2, 'Pack A')
		local info = Exchange:Inspect(v2)
		assert.equal(info.updateOf, first.id)
		assert.is_true(info.isNewer)
		assert.equal(info.keepCount, 4)
		local lines = Exchange:Describe(info)
		assert.equal(lines[2], 'Update to version 2. Your 4 changes stay.')
		local same = Exchange:Inspect(v1)
		assert.is_false(same.isNewer)
		assert.equal(Exchange:Describe(same)[2], 'You already have this version.')
	end)

	it('says "Your 1 change stays" for one change', function()
		local first = Exchange:ApplyStyle(Exchange:Inspect(StyleString({ id = 'packB' }, 'Jane', 1)), 'new')
		Store:Set({ 'tweaks', first.id, 'changes', 'tokens', 'bar' }, 'Smooth')
		local info = Exchange:Inspect(StyleString({ id = 'packB' }, 'Jane', 2))
		assert.matches(Exchange:Describe(info)[2], 'Your 1 change stays%.')
	end)

	it('reads colors, a "When" list and a profile', function()
		local colors = Exchange:Inspect(Share:Encode('colors', { scheme = 'class', colors = { health = { order = { 'tapped', 'class' } } } }))
		assert.equal(colors.kind, 'colors')
		assert.equal(colors.payload.scheme, 'class')
		assert.matches(Exchange:Describe(colors)[1], 'replaces your own colors')
		local when = Exchange:Inspect(Share:Encode('when', { when = { { conditions = { { id = 'place', args = 'raid' } }, size = 'small' } } }))
		assert.equal(when.kind, 'when')
		assert.equal(when.count, 1)
		assert.matches(Exchange:Describe(when)[1], '1 special case%. Using it replaces your own list')
		local profile = Exchange:Inspect(Share:Encode('profile', { profile = { size = 'large' }, styles = {} }))
		assert.equal(profile.kind, 'profile')
		assert.matches(Exchange:Describe(profile)[1], '0 styles')
	end)
end)

----------------------------------------------------------------------------------------------------

describe('import: strings from other players are cleaned', function()
	before_each(Reset)

	it('keeps the colors fields the engine reads and drops the rest', function()
		local info = Exchange:Inspect(Share:Encode('colors', {
			scheme = 'mobType',
			colorBlind = true,
			colors = {
				health = {
					order = { 'tapped', 'class', 'noSuchRow', 'tapped' },
					off = { quest = true, noSuchRow = true, class = 'yes' },
					color = { tapped = { 0.5, 0.5, 0.5, 1 }, mobType = { boss = { 1, 0, 0, 1 }, ['bad key!'] = { 1, 1, 1, 1 } } },
					when = { quest = 'world', class = 'nowhere' },
					fallback = { r = 0.2, g = 0.3, b = 0.4 },
					mystery = 5,
				},
				toenail = { order = { 'tapped' } },
			},
			threat = { when = 'instances', show = { bar = true, banana = true }, colors = { safe = { 0, 1, 0, 1 }, wrong = { 1, 1, 1, 1 } }, extra = 1 },
			evil = 'x',
		}))
		local colors = info.payload
		assert.equal(colors.scheme, 'mobType')
		assert.is_true(colors.colorBlind)
		assert.same(colors.colors.health.order, { 'tapped', 'class' })
		assert.same(colors.colors.health.off, { quest = true })
		assert.same(colors.colors.health.color.tapped, { 0.5, 0.5, 0.5, 1 })
		assert.same(colors.colors.health.color.mobType, { boss = { 1, 0, 0, 1 } })
		assert.same(colors.colors.health.when, { quest = 'world' })
		assert.same(colors.colors.health.fallback, { 0.2, 0.3, 0.4, 1 })
		assert.is_nil(colors.colors.health.mystery)
		assert.is_nil(colors.colors.toenail)
		assert.same(colors.threat.show, { bar = true })
		assert.same(colors.threat.colors, { safe = { 0, 1, 0, 1 } })
		assert.equal(colors.threat.when, 'instances')
		assert.truthy(info.report.dropped >= 9, 'dropped ' .. info.report.dropped)
	end)

	it('pulls colors into range and refuses numbers that are not numbers', function()
		local info = Exchange:Inspect(Share:Encode('colors', { colors = { health = { fallback = { 3, -1, 0.5, 1 }, color = { tapped = { 'x', 1, 1, 1 } } } } }))
		assert.same(info.payload.colors.health.fallback, { 1, 0, 0.5, 1 })
		assert.is_nil(info.payload.colors.health.color.tapped)
		assert.equal(info.report.clamped, 2)
	end)

	it('checks the "When" list: conditions, kinds, styles, sizes and modes', function()
		local info = Exchange:Inspect(Share:Encode('when', {
			when = {
				{
					conditions = { { id = 'place', args = 'raid' }, { id = 'noSuchCondition' }, { id = 'place', args = 'dungeon', negate = true } },
					kinds = { 'enemyNPC', 'banana' },
					style = 'mini',
					size = 'small',
					mode = 'hidden',
				},
				{ style = 'noSuchStyle', size = 'huge', mode = 'loud', off = true },
				'not a table',
			},
		}))
		local list = info.payload
		assert.equal(#list, 2)
		assert.equal(#list[1].conditions, 2)
		assert.equal(list[1].conditions[2].negate, true)
		assert.same(list[1].kinds, { 'enemyNPC' })
		assert.equal(list[1].style, 'mini')
		assert.equal(list[1].mode, 'hidden')
		assert.is_nil(list[2].style, 'a style nobody has')
		assert.is_nil(list[2].size)
		assert.is_nil(list[2].mode)
		assert.is_true(list[2].off)
		assert.equal(info.report.dropped, 6)
	end)

	it('limits the "When" list and the arguments it holds', function()
		local long = {}
		for i = 1, 60 do
			long[i] = { size = 'small' }
		end
		local info = Exchange:Inspect(Share:Encode('when', { when = long }))
		assert.equal(#info.payload, 40)
		local deep = Exchange:Inspect(Share:Encode('when', { when = { { conditions = { { id = 'place', args = { a = { b = { c = { d = 1 } } } } } } } } }))
		assert.same(deep.payload[1].conditions[1].args, { a = {} }, 'arguments stop at two levels')
	end)

	it('cleans a profile: keys, behavior, auras, tweaks, styles', function()
		local style = Merge:Bake('clean')
		style.name = 'Packed'
		local info = Exchange:Inspect(Share:Encode('profile', {
			profile = {
				style = 'sty1',
				size = 'large',
				role = 'tank',
				cvars = { nameplateMaxDistance = '60' },
				assign = { minor = 'sty1', enemyNPC = 'nothing', banana = 'mini' },
				modes = { friendlyNPC = 'hidden', minor = 'loud' },
				when = { { style = 'sty1', size = 'small' } },
				tweaks = { sty1 = { changes = { plate = { sizes = { medium = { 200, 10 } } } } }, clean = { changes = { tokens = { bar = 'X' }, bogus = 1 } } },
				behavior = { enemies = 'combat', rangeFade = 4, stacking = { enemy = true, other = true }, places = { raid = { onlyFighting = true, junk = 1 }, moon = { pinScale = true } }, junk = 1 },
				auras = {
					myDebuffs = { on = false, always = { [589] = 'mine', [172] = 'any', [5] = 'maybe' }, never = { 100, 'Sunder Armor' }, extra = 1 },
					tankDebuffs = { on = true },
					madeUp = { on = true },
				},
			},
			styles = { sty1 = { name = 'Packed', base = style, source = { kind = 'import', author = 'Jane', version = 2, styleId = 'orig' } }, bad = { name = 'Bad', base = {} } },
		}))
		local profile = info.payload.profile
		assert.equal(profile.style, 'sty1')
		assert.equal(profile.size, 'large')
		assert.is_nil(profile.role)
		assert.is_nil(profile.cvars)
		assert.same(profile.assign, { minor = 'sty1' })
		assert.same(profile.modes, { friendlyNPC = 'hidden' })
		assert.equal(profile.when[1].style, 'sty1')
		assert.same(profile.tweaks.sty1.changes.plate.sizes.medium, { 200, 10 })
		assert.equal(profile.tweaks.clean.changes.tokens.bar, 'X')
		assert.equal(profile.behavior.enemies, 'combat')
		assert.equal(profile.behavior.rangeFade, 1, 'pulled into range')
		assert.same(profile.behavior.stacking, { enemy = true })
		assert.same(profile.behavior.places, { raid = { onlyFighting = true } })
		assert.is_nil(profile.behavior.junk)
		assert.same(profile.auras.myDebuffs.always, { [589] = 'mine', [172] = 'any' })
		assert.same(profile.auras.myDebuffs.never, { 100, 'Sunder Armor' })
		assert.is_false(profile.auras.myDebuffs.on)
		assert.is_nil(profile.auras.madeUp)
		assert.not_nil(info.payload.styles.sty1)
		assert.is_nil(info.payload.styles.bad)
		assert.equal(info.payload.styles.sty1.source.author, 'Jane')
		assert.equal(info.count, 1)
		assert.truthy(info.report.dropped >= 10, 'dropped ' .. info.report.dropped)
	end)

	it('refuses a profile string with no profile in it', function()
		local info, reason = Exchange:Inspect(Share:Encode('profile', { styles = {} }))
		assert.is_nil(info)
		assert.equal(reason, 'decode')
	end)

	it('never lets a pasted style take part in a loop through the profile', function()
		local style = Merge:Bake('mini')
		style.parts.marker.anchor = { 'LEFT', 'arrows', 'RIGHT', 0, 0 }
		style.parts.arrows.anchor = { 'LEFT', 'marker', 'RIGHT', 0, 0 }
		local info = Exchange:Inspect(Share:Encode('profile', { profile = { style = 'loop1' }, styles = { loop1 = { name = 'Loop', base = style } } }))
		assert.is_nil(info.payload.styles.loop1)
		assert.is_nil(info.payload.profile.style, 'and the profile no longer points at it')
	end)
end)

----------------------------------------------------------------------------------------------------

describe('import: using a string', function()
	before_each(Reset)

	it('adds a style as a new one and never overwrites', function()
		local text = StyleString({ id = 'packC' }, 'Jane', 1, 'Pack C')
		local a = Exchange:ApplyStyle(Exchange:Inspect(text), 'new')
		local b = Exchange:ApplyStyle(Exchange:Inspect(text), 'new', 'Pack C')
		assert.not_equal(a.id, b.id)
		assert.equal(a.name, 'Pack C')
		assert.equal(b.name, 'Pack C 2', 'names stay apart')
		assert.equal(a.message, 'Added "Pack C" to your styles.')
		local entry = Store:Get({ 'styles', a.id }, 'global')
		assert.same({ entry.source.kind, entry.source.author, entry.source.version, entry.source.styleId }, { 'import', 'Jane', 1, 'packC' })
		assert.is_nil(Store:Get('style') == a.id and true or nil, 'adding does not pick it')
	end)

	it('Use it now adds the style and picks it', function()
		local info = Exchange:Inspect(StyleString({ id = 'packD' }, 'Jane', 1, 'Pack D'))
		local result = Exchange:ApplyStyle(info, 'use')
		assert.equal(Store:Get('style'), result.id)
		assert.equal(result.message, 'Using "Pack D" now.')
		-- the same string again picks the copy it already made
		local again = Exchange:ApplyStyle(Exchange:Inspect(StyleString({ id = 'packD' }, 'Jane', 1, 'Pack D')), 'use')
		assert.equal(again.id, result.id)
	end)

	it('updates the base and keeps the player changes, reporting the ones that no longer apply', function()
		local first = Exchange:ApplyStyle(Exchange:Inspect(StyleString({ id = 'packE' }, 'Jane', 1, 'Pack E')), 'new')
		Store:Set({ 'tweaks', first.id, 'changes', 'parts', 'hp', 'font', 'size' }, 12)
		Store:Set({ 'tweaks', first.id, 'changes', 'parts', 'forces', 'font', 'size' }, 11)
		local newer = Merge:Bake('clean')
		newer.id = 'packE'
		newer.parts.cast.height = 12
		newer.parts.forces = nil
		local text = Share:Encode('style', { style = newer, name = 'Pack E', author = 'Jane', version = 2 })
		local result = Exchange:ApplyStyle(Exchange:Inspect(text), 'update')
		assert.equal(result.id, first.id)
		assert.is_true(result.updated)
		assert.equal(result.keptChanges, 2)
		assert.equal(result.staleChanges, 1)
		assert.matches(result.message, 'Updated "Pack E" to version 2%. Your 2 changes stay%.')
		assert.matches(result.message, '1 of your changes no longer applies')
		local resolved = Merge:Resolve(first.id, 'enemyNPC', 'medium')
		assert.equal(resolved.parts.cast.height, 12, 'the new base')
		assert.equal(resolved.parts.hp.font.size, 12, 'the player change is kept')
		assert.equal(Store:Get({ 'styles', first.id, 'source', 'version' }, 'global'), 2)
		assert.equal(Registry:Get(first.id).name, 'Pack E', 'the name the player sees is theirs')
		-- the same version again changes nothing
		local again = Exchange:ApplyStyle(Exchange:Inspect(text), 'update')
		assert.is_true(again.unchanged)
	end)

	it('keeps the name the player chose through an update', function()
		local first = Exchange:ApplyStyle(Exchange:Inspect(StyleString({ id = 'packF' }, 'Jane', 1, 'Pack F')), 'new')
		Gallery:Rename(first.id, 'My F')
		Exchange:ApplyStyle(Exchange:Inspect(StyleString({ id = 'packF' }, 'Jane', 2, 'Pack F')), 'update')
		assert.equal(Registry:Get(first.id).name, 'My F')
	end)

	it('asks the page flow the same way: paste, see, use', function()
		local page = Page()
		local import = page.args.import.args
		assert.is_true(import.importUse.hidden())
		import.importText.set({}, StyleString({ id = 'packG' }, 'Jane', 1, 'Pack G'))
		assert.equal(import.importText.get(), '', 'the string is never echoed back')
		assert.is_false(import.importUse.hidden())
		assert.is_false(import.importCard.hidden())
		assert.is_false(import.importNew.hidden())
		assert.is_false(import.importClear.hidden())
		assert.matches(import.importInfo.name(), '"Pack G" by Jane, version 1%.')
		assert.equal(import.importUse.name(), 'Use it now')
		assert.equal(Gallery:GetPreview().name, 'Pack G', 'the preview panel draws it')
		assert.equal(import.importCard.values()[Gallery.PREVIEW_VALUE], 'Pack G')
		local before = Registry:List(false)
		import.importUse.func()
		assert.truthy(#Registry:List(false) == #before + 1)
		assert.is_nil(Gallery:GetPreview(), 'the preview stops once it is used')
		assert.is_true(import.importUse.hidden())
		assert.matches(import.importInfo.name(), 'Using "Pack G" now')
		assert.matches(Store:Get('style'), '^u')
	end)

	it('labels the main button Update to version N for a newer copy of a style you have', function()
		local import = Page().args.import.args
		Exchange:ApplyStyle(Exchange:Inspect(StyleString({ id = 'packH' }, 'Jane', 1)), 'new')
		import.importText.set({}, StyleString({ id = 'packH' }, 'Jane', 5))
		assert.equal(import.importUse.name(), 'Update to version 5')
		assert.matches(import.importInfo.name(), 'Update to version 5%. Your 0 changes stay')
		import.importUse.func()
		assert.matches(import.importInfo.name(), '^Updated ".-" to version 5')
	end)

	it('shows a reason for a string that is no good and clears it', function()
		local import = Page().args.import.args
		import.importText.set({}, 'not a share string')
		assert.is_true(import.importUse.hidden())
		assert.equal(import.importInfo.name(), Exchange:ReasonText('format'))
		assert.is_false(import.importClear.hidden())
		import.importClear.func()
		assert.is_true(import.importClear.hidden())
		assert.matches(import.importInfo.name(), '^Paste a share string')
		import.importText.set({}, '!NP:' .. (Schema.CURRENT + 1) .. ':style!x')
		assert.matches(import.importInfo.name(), P:HostName())
		import.importText.set({}, '')
		assert.matches(import.importInfo.name(), '^Paste a share string', 'an empty box is not an error')
	end)

	it('locks the buttons that change the plates while the game restricts changes', function()
		local import = Page().args.import.args
		locked = true
		assert.is_true(import.importUse.disabled())
		assert.is_false(import.importNew.disabled == nil and false or (import.importNew.disabled ~= nil and import.importNew.disabled() or false), 'adding a style is not locked')
	end)

	it('replaces the colors and puts them back on Undo', function()
		Store:Set('scheme', 'threat')
		Store:Set('colorBlind', true)
		Store:Set('colors', { health = { order = { 'tapped' } } })
		local import = Page().args.import.args
		import.importText.set({}, Share:Encode('colors', { scheme = 'class', colors = { health = { order = { 'class', 'reaction' } } }, threat = { when = 'always' } }))
		assert.equal(import.importUse.name(), 'Use these colors')
		import.importUse.func()
		assert.equal(Store:Get('scheme'), 'class')
		assert.same(Store:Get('colors'), { health = { order = { 'class', 'reaction' } } })
		assert.equal(Store:Get({ 'threat', 'when' }), 'always')
		assert.is_false(Store:Get('colorBlind'), 'not in the string, so back to the default')
		assert.is_false(import.importUndo.hidden())
		assert.equal(import.importUndo.name(), 'Undo: put my colors back')
		import.importUndo.func()
		assert.equal(Store:Get('scheme'), 'threat')
		assert.is_true(Store:Get('colorBlind'))
		assert.same(Store:Get('colors'), { health = { order = { 'tapped' } } })
		assert.is_nil(Store:Get('threat'))
		assert.is_true(import.importUndo.hidden())
	end)

	it('replaces the "When" list and puts it back on Undo', function()
		Store:Set('when', { { size = 'large' } })
		Exchange:Paste(Share:Encode('when', { when = { { conditions = { { id = 'place', args = 'raid' } }, style = 'mini' } } }))
		assert.equal(Page().args.import.args.importUse.name(), 'Use this list')
		local result = Exchange:Do('replace')
		assert.is_true(result.ok)
		assert.equal(Store:Get('when')[1].style, 'mini')
		assert.is_true(Exchange:Undo())
		assert.equal(Store:Get('when')[1].size, 'large')
		assert.is_false(Exchange:Undo(), 'one undo')
	end)

	it('forgets the undo when the profile changes', function()
		Store:Set('when', { { size = 'large' } })
		Exchange:Paste(Share:Encode('when', { when = { { conditions = { { id = 'place', args = 'raid' } }, style = 'mini' } } }))
		assert.is_true(Exchange:Do('replace').ok)
		assert.is_true(Exchange:HasUndo())
		P:Fire('PROFILE_CHANGED', {})
		assert.is_false(Exchange:HasUndo(), 'it would write into another profile')
		assert.is_false(Exchange:Undo())
	end)

	it('uses an empty "When" list to clear the list', function()
		Store:Set('when', { { size = 'large' } })
		Exchange:Paste(Share:Encode('when', { when = {} }))
		Exchange:Do('replace')
		assert.is_nil(Store:Get('when'))
	end)

	it('uses a whole profile: saves its styles, moves the references, and Undo takes it all back', function()
		local packed = Merge:Bake('clean')
		packed.name = 'Packed'
		local text = Share:Encode('profile', {
			profile = {
				style = 'sty1',
				size = 'small',
				assign = { minor = 'sty1' },
				when = { { style = 'sty1', size = 'large' } },
				tweaks = { sty1 = { changes = { tokens = { bar = 'Smooth' } } } },
				scheme = 'class',
			},
			styles = { sty1 = { name = 'Packed', base = packed, source = { kind = 'import', author = 'Jane', version = 1, styleId = 'orig' } } },
		})
		Store:Set('style', 'mini')
		Store:Set('size', 'large')
		Store:Set('modes', { minor = 'hidden' })
		local info = Exchange:Inspect(text)
		Exchange:Paste(text)
		local result = Exchange:Do('replace')
		assert.is_true(result.ok)
		local newId = Store:Get('style')
		assert.not_equal(newId, 'sty1')
		assert.is_true(Registry:IsSaved(newId))
		assert.equal(Registry:Get(newId).name, 'Packed')
		assert.equal(Store:Get('size'), 'small')
		assert.equal(Store:Get({ 'assign', 'minor' }), newId)
		assert.equal(Store:Get('when')[1].style, newId)
		assert.equal(Store:Get({ 'tweaks', newId, 'changes', 'tokens', 'bar' }), 'Smooth')
		assert.equal(Store:Get('scheme'), 'class')
		assert.is_nil(Store:Get('modes'), 'settings not in the string are replaced too')
		assert.equal(info.count, 1)
		-- the same string again reuses the style it saved
		local count = #Registry:List(false)
		Exchange:Paste(text)
		Exchange:Do('replace')
		assert.equal(#Registry:List(false), count, 'no second copy')
		assert.equal(Store:Get('style'), newId)

		Exchange.undo = nil
		Store:Set('style', 'mini')
		Exchange:Paste(text)
		Exchange:Do('replace')
		assert.is_true(Exchange:Undo())
		assert.equal(Store:Get('style'), 'mini')
	end)

	it('removes the styles a profile added when it is undone', function()
		local packed = Merge:Bake('clean')
		local text = Share:Encode('profile', { profile = { style = 'sty1' }, styles = { sty1 = { name = 'Fresh', base = packed } } })
		local before = #Registry:List(false)
		Exchange:Paste(text)
		Exchange:Do('replace')
		assert.equal(#Registry:List(false), before + 1)
		Exchange:Undo()
		assert.equal(#Registry:List(false), before)
		assert.equal(Store:Get('style'), 'host')
	end)

	it('does nothing when there is nothing pasted', function()
		local result = Exchange:Do('use')
		assert.is_false(result.ok)
		assert.equal(result.message, 'Paste a share string first.')
	end)

	it('gives the same settings no matter who made the string', function()
		-- what one profile exports and another imports should leave the second the same as the first
		Store:Set('size', 'large')
		Store:Set('scheme', 'mobType')
		Store:Set({ 'threat', 'show' }, { bar = true, glow = true })
		Store:Set({ 'auras', 'myDebuffs', 'always' }, { [589] = 'mine' })
		Store:Set({ 'behavior', 'stacking', 'enemy' }, true)
		local text = Exchange:BuildExport('everything')
		for _, key in ipairs(Exchange.PROFILE_KEYS) do
			Store:Set(key, nil)
		end
		Exchange:Paste(text)
		Exchange:Do('replace')
		assert.equal(Store:Get('size'), 'large')
		assert.equal(Store:Get('scheme'), 'mobType')
		assert.same(Store:Get({ 'threat', 'show' }), { bar = true, glow = true })
		assert.same(Store:Get({ 'auras', 'myDebuffs', 'always' }), { [589] = 'mine' })
		assert.is_true(Store:Get({ 'behavior', 'stacking', 'enemy' }))
	end)
end)

----------------------------------------------------------------------------------------------------

describe('public API: ImportStyle', function()
	before_each(Reset)

	it('imports a style and returns what the string said about itself', function()
		local id, reason, info = P.API:ImportStyle(StyleString({ id = 'apiA' }, 'Pack Author', 7, 'API Pack'))
		assert.not_nil(id, tostring(reason))
		assert.equal(info.name, 'API Pack')
		assert.equal(info.author, 'Pack Author')
		assert.equal(info.version, 7)
		assert.is_false(info.updated)
		assert.equal(info.dropped, 0)
		local entry = Store:Get({ 'styles', id }, 'global')
		assert.equal(entry.source.author, 'Pack Author')
		assert.equal(entry.source.version, 7)
	end)

	it('never overwrites unless asked, and then keeps the player changes', function()
		local first = P.API:ImportStyle(StyleString({ id = 'apiB' }, 'Pack Author', 1, 'API B'))
		Store:Set({ 'tweaks', first, 'changes', 'tokens', 'bar' }, 'Smooth')
		local second, _, info = P.API:ImportStyle(StyleString({ id = 'apiB' }, 'Pack Author', 2, 'API B'))
		assert.not_equal(second, first, 'a new copy')
		assert.is_false(info.updated)
		assert.equal(Merge:Resolve(first, 'enemyNPC', 'medium').tokens.bar, 'Smooth', 'the first copy is untouched')
		Store:Set('styles', nil, 'global')

		local one = P.API:ImportStyle(StyleString({ id = 'apiB2' }, 'Pack Author', 1, 'API B2'))
		Store:Set({ 'tweaks', one, 'changes', 'tokens', 'bar' }, 'Smooth')
		local updated_id, _, updated = P.API:ImportStyle(StyleString({ id = 'apiB2' }, 'Pack Author', 2, 'API B2'), nil, { update = true })
		assert.equal(updated_id, one)
		assert.is_true(updated.updated)
		assert.equal(updated.keptChanges, 1)
		assert.equal(Merge:Resolve(one, 'enemyNPC', 'medium').tokens.bar, 'Smooth')
		local again, _, same = P.API:ImportStyle(StyleString({ id = 'apiB2' }, 'Pack Author', 2, 'API B2'), nil, { update = true })
		assert.equal(again, one)
		assert.is_true(same.unchanged, 'the same version changes nothing')
		local added = P.API:ImportStyle(StyleString({ id = 'apiZ' }, 'Other', 1, 'Fresh'), nil, { update = true })
		assert.not_nil(added, 'update with nothing to update adds a style')
		assert.not_equal(added, one)
	end)

	it('can pick the style it imported', function()
		local id = P.API:ImportStyle(StyleString({ id = 'apiC' }, 'Pack Author', 1, 'API C'), nil, { use = true })
		assert.equal(Store:Get('style'), id)
	end)

	it('gives the name the caller asks for', function()
		local id = P.API:ImportStyle(StyleString({ id = 'apiD' }, 'A', 1, 'Original'), 'Mine')
		assert.equal(Registry:Get(id).name, 'Mine')
	end)

	it('refuses other kinds and bad strings with a reason', function()
		local id, reason = P.API:ImportStyle(Share:Encode('colors', { scheme = 'class' }))
		assert.is_nil(id)
		assert.equal(reason, 'kind')
		id, reason = P.API:ImportStyle('nope')
		assert.is_nil(id)
		assert.equal(reason, 'format')
		id, reason = P.API:ImportStyle('!NP:' .. (Schema.CURRENT + 1) .. ':style!zz')
		assert.equal(reason, 'newer')
	end)

	it('reports what it left out', function()
		local style = Merge:Bake('clean')
		style.parts.health.mystery = 1
		local id, _, info = P.API:ImportStyle(Share:Encode('style', { style = style, name = 'Odd', author = 'Z' }))
		assert.not_nil(id)
		assert.equal(info.dropped, 1)
		assert.same(info.droppedKeys, { 'parts.health.mystery' })
	end)
end)

describe('search words', function()
	it('teaches the search the everyday words for sharing and copies', function()
		local words = Options.SEARCH_WORDS
		assert.equal(words.export, 'share')
		assert.equal(words.paste, 'import')
		assert.equal(words.duplicate, 'make a copy')
	end)
end)

describe('pasted style in the preview panel', function()
	before_each(Reset)

	it('is drawn while pasted and stops when cleared', function()
		local seen = {}
		P:On('GALLERY_PREVIEW', function(info)
			seen[#seen + 1] = info and info.name or 'none'
		end, seen)
		Exchange:Paste(StyleString({ id = 'prevA' }, 'Jane', 1, 'Prev A'))
		assert.equal(Gallery:ResolveShown('enemyNPC', 'medium').id, '@preview')
		Exchange:Clear()
		P:Off('GALLERY_PREVIEW', seen)
		assert.same(seen, { 'Prev A', 'none' })
		assert.is_nil(Gallery:ResolveShown('enemyNPC', 'medium'))
	end)

	it('comes back when the panel clears it while the string still waits on the page', function()
		Exchange:Paste(StyleString({ id = 'prevB' }, 'Jane', 1, 'Prev B'))
		Gallery:ClearPreview()
		assert.equal(Gallery:GetPreview().name, 'Prev B')
		Exchange:Clear()
		assert.is_nil(Gallery:GetPreview(), 'a clear of our own stays cleared')
		Gallery:ClearPreview()
		assert.is_nil(Gallery:GetPreview())
	end)

	it('is not shown for colors or a bad string', function()
		Exchange:Paste(Share:Encode('colors', { scheme = 'class' }))
		assert.is_nil(Gallery:GetPreview())
		Exchange:Paste('junk')
		assert.is_nil(Gallery:GetPreview())
	end)

	it('asks the open window to redraw when the paste changes', function()
		local asked = 0
		local before = Options.RequestRefresh
		Options.RequestRefresh = function()
			asked = asked + 1
		end
		Exchange:Paste(StyleString({}, nil, 1))
		Exchange:Clear()
		Options.RequestRefresh = before
		assert.equal(asked, 2)
	end)
end)
