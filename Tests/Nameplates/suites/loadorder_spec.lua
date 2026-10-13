-- @runtime lua51
-- Load order and attachment (plan 6.1, Decision 21): the TOC declares the new SavedVariable
-- account-wide and loads the core only through Modules/LoadAll.xml, where the old module comes
-- first, then the core's Load.xml, then the host, then LastTick. Then the real old module file,
-- the core and the host are loaded in that order against the SpartanUI stand-in and logged in with
-- the tester switch off: the host attaches to the module the old file made (or makes a hidden one
-- on Retail, where the old file stops early), the old plates start as before, and the core does
-- nothing to the game.
--
-- Loading SpartanUI's whole TOC in the mock is not attempted: the strict client lacks most of
-- FrameXML (RegisterStateDriver, Minimap, Blizzard templates) and Libs-AddonTools, so about 140 of
-- 482 files fail to load there for reasons unrelated to nameplates.
local M, H = ...

if not (H.ModuleExists() and H.Exists(H.hostFile)) then
	describe('load order', function()
		pending('all', 'the nameplate module or its host does not exist yet')
	end)
	return
end

local ROOT = HARNESS_ROOT

local function TocLines()
	local lines = {}
	for line in io.lines(ROOT .. 'SpartanUI.toc') do
		lines[#lines + 1] = (line:gsub('\r', ''))
	end
	return lines
end

local function TocFiles()
	local out = {}
	for _, line in ipairs(TocLines()) do
		if not line:match('^%s*#') and line:match('%S') then
			local file = line:match('^(%S+)')
			out[#out + 1] = (file:gsub(string.char(92), '/'))
		end
	end
	return out
end

local function IndexOf(entries, path)
	path = H.Normalize(path)
	for i, entry in ipairs(entries) do
		if entry.kind == 'script' and entry.path == path then
			return i
		end
	end
end

describe('load order: TOC', function()
	it('declares the nameplate SavedVariable account-wide, never per character', function()
		local account, perChar
		for _, line in ipairs(TocLines()) do
			if line:match('^## SavedVariables:') then
				account = line
			elseif line:match('^## SavedVariablesPerCharacter:') then
				perChar = line
			end
		end
		assert.not_nil(account)
		assert.matches(account, 'SpartanUINameplatesDB')
		assert.is_nil(perChar and perChar:find('SpartanUINameplatesDB', 1, true))
	end)

	it('loads the nameplate folder only through Modules/LoadAll.xml', function()
		local files = TocFiles()
		assert.contains(files, 'Modules/LoadAll.xml')
		for _, file in ipairs(files) do
			assert.is_nil(file:find('^Modules/Nameplates/'), file .. ' is listed in the TOC directly')
		end
	end)

	it('ships the range library before the module folder (range fade, plan 6.1)', function()
		local files = TocFiles()
		local lib, modules
		for i, file in ipairs(files) do
			if file == 'libs/LibRangeCheck-3.0/LibRangeCheck-3.0.lua' then
				lib = i
			elseif file == 'Modules/LoadAll.xml' then
				modules = i
			end
		end
		assert.not_nil(lib, 'LibRangeCheck-3.0 is listed in the TOC')
		assert.truthy(modules and lib < modules, 'LibRangeCheck-3.0 loads before Modules/LoadAll.xml')
		assert.truthy(H.Exists(ROOT .. 'libs/LibRangeCheck-3.0/LICENSE'), 'the library keeps its license file')
	end)

	it('lists only files that exist', function()
		local missing = {}
		for _, file in ipairs(TocFiles()) do
			if not file:find('@', 1, true) and not H.Exists(ROOT .. file) then
				missing[#missing + 1] = file
			end
		end
		assert.empty(missing, 'missing TOC files')
	end)
end)

describe('load order: Modules/LoadAll.xml', function()
	local entries, first, last, all = H.NameplateLoadEntries()

	it('finds the old module and the host', function()
		assert.not_nil(first, 'Modules/Nameplates.lua is in LoadAll.xml')
		assert.not_nil(last, 'Modules/Nameplates/Host/SpartanUI.lua is in LoadAll.xml')
		assert.truthy(first < last)
	end)

	it('loads old module, every core file in Load.xml order, the host, then LastTick', function()
		local core = {}
		for _, entry in ipairs(H.ParseLoadXml(H.moduleXml)) do
			if entry.kind == 'script' then
				core[#core + 1] = entry.path
			end
		end
		assert.truthy(#core > 10)
		local between = {}
		for i = 2, #entries - 1 do
			if entries[i].kind == 'script' then
				between[#between + 1] = entries[i].path
			end
		end
		assert.same(between, core, 'exactly the core files, in order, between the old module and the host')
		local lastTick
		for i, entry in ipairs(all) do
			if entry.kind == 'script' and entry.path:find('/Modules/LastTick/', 1, true) then
				lastTick = lastTick or i
			end
		end
		assert.not_nil(lastTick, 'LastTick loads from LoadAll.xml')
		assert.truthy(last < lastTick, 'LastTick loads after the host, so it can find the API')
	end)

	it('keeps the host out of the core Load.xml', function()
		for _, entry in ipairs(H.ParseLoadXml(H.moduleXml)) do
			assert.is_nil(entry.path and entry.path:find('/Host/', 1, true), tostring(entry.path))
		end
	end)

	it('lists only script files that exist, each once', function()
		local seen, missing, twice = {}, {}, {}
		for _, entry in ipairs(all) do
			if entry.kind == 'script' then
				if not H.Exists(entry.path) then
					missing[#missing + 1] = entry.path
				end
				if seen[entry.path] then
					twice[#twice + 1] = entry.path
				end
				seen[entry.path] = true
			end
		end
		assert.empty(missing, 'missing files')
		assert.empty(twice, 'files loaded twice')
	end)
end)

-- Phase 4a: the new plates are the default, so this character picked "Use the old nameplates"
describe('load order: the old module and the host, old plates picked', function()
	local SUI, ns, module = H.LoadNameplatesLikeTheGame({ saved = { char = { [H.CharacterKey()] = { engine = 'old' } } } })
	local P = ns.Plates

	it('ends up with one Nameplates module carrying the core API', function()
		assert.not_nil(module)
		assert.is_true(rawequal(module.API, P.API))
		if SUI.IsRetail then
			assert.is_true(module.createdByHost, 'Retail: the old file stops early, the host makes the module')
		else
			assert.is_nil(module.createdByHost, 'the old file made it')
		end
	end)

	it('logs in without errors and runs the old plates, not the new engine', function()
		M.Login('SpartanUI')
		M.Advance(1)
		assert.is_true(P.initialized, 'the core opened its database')
		assert.is_false(P.enabled, 'the engine stays off')
		assert.equal(P:RegisteredEventCount(), 0)
		assert.empty(M.rec.cvarWrites, 'CVar writes')
		-- Nothing under Modules/Nameplates/ (core or host) touched the game; the old file may
		local function Ours(list)
			local out = {}
			for _, rec in ipairs(list) do
				if tostring(rec.where or ''):find('Modules/Nameplates/', 1, true) then
					out[#out + 1] = (rec.event or rec.name or rec.label or '?') .. ' at ' .. tostring(rec.where)
				end
			end
			return out
		end
		assert.empty(Ours(M.rec.events), 'events registered by the core or host')
		assert.empty(Ours(M.rec.hooks), 'hooks installed by the core or host')
		assert.empty(Ours(M.rec.globals), 'named frames made by the core or host')
		assert.empty(Ours(M.rec.tickers), 'timers started by the core or host')
		local spawned = false
		for _, call in ipairs(H.oldCalls) do
			if call.path == 'SUIUF.SpawnNamePlates' then
				spawned = true
			end
		end
		assert.equal(spawned, not SUI.IsRetail, 'the old module spawns its plates outside Retail')
		assert.not_nil(H.sui.commands.np, '/sui np is registered')
		assert.empty(H.sui.options, 'no new options while the old plates run')
	end)

	it('switches back to the new plates for the next session only', function()
		H.sui.commands.np.fn('preview')
		assert.is_nil(P.Config:GetEngineChoice(), 'the launch default, not the tester mark')
		assert.equal(P.Config:GetSessionEngine(), 'old')
		assert.is_false(P.enabled)
		H.sui.commands.np.fn('preview')
		assert.equal(P.Config:GetEngineChoice(), 'old')
	end)
end)
