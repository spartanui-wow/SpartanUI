-- @runtime lua51
-- Wording (stage C polish): every string the nameplate module can show is read the way the player
-- reads it, after the English wording fixes in Core/Locale.lua. Six-grade words, no em dashes, no
-- symbols the game cannot draw, no jargon, no other addons by name, short sentences, and one name for
-- each thing. The strings come from the source files themselves (every L['...'] in the files
-- Load.xml lists, plus the host), so a string nobody opens in a test is still checked.
local M, H = ...

if not H.ModuleExists() then
	describe('wording', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

M.Login('NameplatesTestHost')
local P = H.FreshCore()

local ROOT = HARNESS_ROOT
local MODULE = ROOT .. 'Modules/Nameplates/'

local function ReadLines(path)
	local text = H.ReadFile(path)
	return text or ''
end

---Every L['text'] or L["text"] in a source text: { text, line }.
local function SourceStrings(source)
	local out = {}
	local line = 1
	local position = 1
	local length = #source
	while position <= length do
		local newline = source:find('\n', position, true) or (length + 1)
		-- A space in front, so a string at the start of a line counts; P.L[...] is the same table as L[...]
		local row = (' ' .. source:sub(position, newline - 1)):gsub('P%.L%[', '  L[')
		local from = 1
		while true do
			local s, e, quote = row:find('[^%w_.]L%[(["\'])', from)
			if not s then
				break
			end
			-- Walk to the closing quote, honoring a backslash
			local i = e + 1
			local chars = {}
			local closed = false
			while i <= #row do
				local ch = row:sub(i, i)
				if ch == '\\' then
					local nextChar = row:sub(i + 1, i + 1)
					chars[#chars + 1] = nextChar == 'n' and '\n' or nextChar
					i = i + 2
				elseif ch == quote then
					closed = true
					break
				else
					chars[#chars + 1] = ch
					i = i + 1
				end
			end
			if closed and row:sub(i + 1, i + 1) == ']' then
				out[#out + 1] = { text = table.concat(chars), line = line }
			end
			from = i + 1
		end
		line = line + 1
		position = newline + 1
	end
	return out
end

local function LoadXmlFiles()
	local text = ReadLines(MODULE .. 'Load.xml')
	local files = {}
	for file in text:gmatch('<Script file="([^"]+)"') do
		files[#files + 1] = (file:gsub(string.char(92), '/'))
	end
	return files
end

-- name -> { { text, shown, file, line } }
local corePairs = {}
local coreKeys = {}
for _, file in ipairs(LoadXmlFiles()) do
	for _, item in ipairs(SourceStrings(ReadLines(MODULE .. file))) do
		coreKeys[item.text] = true
		corePairs[#corePairs + 1] = { key = item.text, shown = P.L[item.text], file = file, line = item.line }
	end
end

local hostPairs = {}
for _, item in ipairs(SourceStrings(ReadLines(MODULE .. 'Host/SpartanUI.lua'))) do
	hostPairs[#hostPairs + 1] = { key = item.text, shown = item.text, file = 'Host/SpartanUI.lua', line = item.line }
end

local function All()
	local out = {}
	for _, item in ipairs(corePairs) do
		out[#out + 1] = item
	end
	for _, item in ipairs(hostPairs) do
		out[#out + 1] = item
	end
	return out
end

local function Where(item)
	return item.file .. ':' .. item.line .. ' "' .. item.key .. '"'
end

local function Check(rule, fn)
	local bad = {}
	for _, item in ipairs(All()) do
		local problem = fn(item.shown, item)
		if problem then
			bad[#bad + 1] = Where(item) .. ' -> ' .. tostring(problem)
		end
	end
	assert.equal(#bad, 0, rule .. ':\n  ' .. table.concat(bad, '\n  '))
end

local EM_DASH = string.char(226, 128, 148)
local EN_DASH = string.char(226, 128, 147)

-- Words a player should not meet in a settings window
local JARGON = {
	'overlay',
	'schema',
	'cvar',
	'cvars',
	'token',
	'payload',
	'lsm',
	'widget',
	'api',
	'lua',
	'engine',
	'taint',
	'hook',
	'hooks',
	'secret',
	'atlas',
	'anchor',
	'strata',
	'boolean',
	'callback',
	'mixin',
	'nil',
	'regex',
	'json',
	'cbor',
	'base64',
	'deflate',
	'hotfix',
}

-- Other addons are never named in text a player reads
local OTHER_ADDONS = { 'elvui', 'weakauras', 'platynator', 'plater', 'tidyplates', 'threatplates', 'kui', 'neatplates', 'ellesmere', 'dbm', 'bigwigs', 'bartender', 'questie', 'wowhead' }

-- One name for each thing: [phrase that must not appear] = what to say
local BANNED_PHRASES = {
	['game version'] = 'this version of WoW',
	['version of the game'] = 'this version of WoW',
	['"when" list'] = 'special cases',
	['when list'] = 'special cases',
	['hangs from'] = 'moves with',
}

local function HasWord(lower, word)
	return lower:find('%f[%w]' .. word .. '%f[%W]') ~= nil
end

describe('wording: what the files ask for', function()
	it('finds the strings in the source (the scan is not empty)', function()
		assert.truthy(#corePairs > 500, 'core strings found: ' .. #corePairs)
		assert.truthy(#hostPairs > 20, 'host strings found: ' .. #hostPairs)
	end)

	it('reads a quote, an escape and a double-quoted string the way the game does', function()
		local found = SourceStrings([=[local a = L['Don\'t panic']
local b = L["It's fine"]
local c = SomeL['not ours']
local d = L['Two']  L['strings']
local e = P.L['Held by P']]=])
		assert.same({ found[1].text, found[2].text, found[3].text, found[4].text, found[5].text }, { "Don't panic", "It's fine", 'Two', 'strings', 'Held by P' })
		assert.equal(#found, 5)
	end)
end)

describe('wording: every string the player can read', function()
	it('has no em dashes, en dashes or double hyphens used as dashes', function()
		Check('dashes', function(text)
			if text:find(EM_DASH, 1, true) or text:find(EN_DASH, 1, true) or text:find(' %-%- ') then
				return 'dash'
			end
		end)
	end)

	it('uses only symbols the game can draw (plain ASCII)', function()
		Check('non-ASCII', function(text)
			if text:find('[\128-\255]') then
				return 'a symbol outside plain ASCII'
			end
		end)
	end)

	it('has no jargon', function()
		Check('jargon', function(text)
			local lower = text:lower()
			for _, word in ipairs(JARGON) do
				if HasWord(lower, word) then
					return word
				end
			end
		end)
	end)

	it('never names another addon', function()
		Check('addon names', function(text)
			local lower = text:lower()
			for _, name in ipairs(OTHER_ADDONS) do
				if HasWord(lower, name) then
					return name
				end
			end
		end)
	end)

	it('uses one name for each thing', function()
		Check('names', function(text)
			local lower = text:lower()
			for phrase, say in pairs(BANNED_PHRASES) do
				if lower:find(phrase, 1, true) then
					return 'say "' .. say .. '" instead of "' .. phrase .. '"'
				end
			end
			if HasWord(lower, 'friends') then
				return 'say "friendly" (plates or players), not "friends"'
			end
		end)
	end)

	it('keeps sentences short', function()
		Check('long sentences', function(text)
			for sentence in (text .. ' '):gmatch('(.-[%.%?!])%s') do
				local words = 0
				for _ in sentence:gmatch('%S+') do
					words = words + 1
				end
				if words > 22 then
					return words .. ' words in "' .. sentence .. '"'
				end
			end
			local trailing = text:match('([^%.%?!]+)$')
			if trailing then
				local words = 0
				for _ in trailing:gmatch('%S+') do
					words = words + 1
				end
				if words > 22 then
					return words .. ' words without a stop'
				end
			end
		end)
	end)

	it('stays short enough to read at a glance', function()
		Check('long strings', function(text)
			if #text > 200 then
				return #text .. ' characters'
			end
		end)
	end)

	it('has no stray spaces', function()
		Check('spaces', function(text)
			if text:find('  ', 1, true) or text:find('^%s') or text:find('%s$') then
				return 'extra or edge spaces'
			end
		end)
	end)

	it('keeps the format codes a call site fills in', function()
		Check('format codes', function(text, item)
			local plain = text:gsub('%%%%', '')
			local original = item.key:gsub('%%%%', '')
			-- A percent sign in a sentence ("100% means") is fine; a code the game cannot fill is not
			local unknown = plain:match('%%([^sd%s%.,;:!?%)])')
			if unknown then
				return 'unknown format code %' .. unknown
			end
			local a, b = {}, {}
			for code in original:gmatch('%%([sd])') do
				a[#a + 1] = code
			end
			for code in plain:gmatch('%%([sd])') do
				b[#b + 1] = code
			end
			if table.concat(a) ~= table.concat(b) then
				return 'format codes changed from ' .. table.concat(a, ',') .. ' to ' .. table.concat(b, ',')
			end
		end)
	end)
end)

describe('wording: the English fixes in Core/Locale.lua', function()
	it('only change strings a file really asks for', function()
		local stale = {}
		for key in pairs(P.WORDING) do
			if not coreKeys[key] then
				stale[#stale + 1] = key
			end
		end
		table.sort(stale)
		assert.equal(#stale, 0, 'no file asks for these any more, drop them from P.WORDING:\n  ' .. table.concat(stale, '\n  '))
	end)

	it('change the words and nothing else', function()
		for key, text in pairs(P.WORDING) do
			assert.equal(P.L[key], text)
			assert.not_equal(key, text, 'a fix that changes nothing: ' .. key)
		end
	end)

	it('say Friendly, not Friends, wherever plates are named', function()
		assert.equal(P.L['Friends'], 'Friendly plates')
		assert.equal(P.L['Enemies'], 'Enemy plates')
		assert.equal(P.L['Friends overlap'], 'Friendly plates overlap')
		assert.equal(P.L['Enemies overlap'], 'Enemy plates overlap')
	end)

	it('call the list special cases and its editor When', function()
		assert.equal(P.L['My special cases'], 'My special cases')
		assert.matches(P.L['Special cases change how plates look in certain places. The first one that fits wins, so put the most specific ones at the top. Click one to edit it.'], 'Special cases')
		assert.equal(P.L['When all of these are true'], 'When all of these are true')
		assert.equal(P.L['Edit this special case'], 'Edit this special case')
	end)

	it('say one thing for "when" and one for "where" in the threat settings', function()
		assert.equal(P.L['Show threat'], 'Show threat when')
		assert.matches(P.L['Choose where threat colors appear. Never turns them off.'], '^Choose when ')
		assert.equal(P.L['Show threat on'], 'Show threat on')
	end)

	it('give the enemy buffs reason once, the same way in the list and on the row', function()
		local page = P.L['Not available for enemy buffs on this version of WoW']
		local row = P.L['The game does not let spell lists pick enemy buffs, so this row shows every buff you can remove.']
		assert.equal(page, row)
		assert.matches(page, 'On this version of WoW')
	end)

	it('name the game overlap setting for what it does', function()
		assert.equal(P.L['Game overlap setting'], 'How tightly the game stacks plates')
		assert.matches(P.L['How close the game lets plates stack. Lower numbers pack plates tighter.'], 'lower number packs')
	end)
end)

describe('wording: the host strings', function()
	local function LangKeys()
		local keys = {}
		for _, item in ipairs(SourceStrings(ReadLines(ROOT .. 'lang/enUS.lua'))) do
			keys[item.text] = true
		end
		return keys
	end

	it('are all in lang/enUS.lua', function()
		local lang = LangKeys()
		local missing = {}
		local seen = {}
		for _, item in ipairs(hostPairs) do
			if not lang[item.key] and not seen[item.key] then
				seen[item.key] = true
				missing[#missing + 1] = Where(item)
			end
		end
		assert.equal(#missing, 0, 'add these to lang/enUS.lua:\n  ' .. table.concat(missing, '\n  '))
	end)

	it('include the painted plate strings the themes use', function()
		local lang = LangKeys()
		assert.is_true(lang['The painted frame of the %s look, around a smooth bar.'] == true)
		assert.is_true(lang['Painted frame'] == true)
		local painted = {}
		for _, item in ipairs(SourceStrings((ReadLines(ROOT .. 'Themes/Painted.lua'):gsub('SUI%.L%[', 'L[')))) do
			painted[#painted + 1] = item.text
		end
		for _, text in ipairs(painted) do
			assert.is_true(lang[text] == true, 'lang/enUS.lua lacks: ' .. text)
		end
	end)

	it('add no key twice to lang/enUS.lua with the same text', function()
		local seen, repeated = {}, {}
		for _, item in ipairs(SourceStrings(ReadLines(ROOT .. 'lang/enUS.lua'))) do
			if seen[item.text] and (item.text:find('nameplate', 1, true) or item.text:find('Nameplate', 1, true)) then
				repeated[#repeated + 1] = item.text
			end
			seen[item.text] = true
		end
		assert.equal(#repeated, 0, 'repeated: ' .. table.concat(repeated, ' | '))
	end)
end)
