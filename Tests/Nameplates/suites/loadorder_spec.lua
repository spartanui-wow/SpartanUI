-- @runtime lua51
-- Load order (plan 6.1, Phase 4b): the TOC declares the nameplate SavedVariable account-wide and
-- loads the core only through Modules/LoadAll.xml, where the core's Load.xml comes first, then the
-- host, then LastTick. The old module file is gone from the folder and from the load list. Then the
-- core and the host are loaded in that order against the SpartanUI stand-in for a character that
-- picked the old plates in an earlier version: the host creates the one Nameplates module, the saved
-- choice is dropped, the old settings come over to Clean and the plates start.
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

	it('finds the core and the host', function()
		assert.not_nil(first, 'the core is in LoadAll.xml')
		assert.not_nil(last, 'Modules/Nameplates/Host/SpartanUI.lua is in LoadAll.xml')
		assert.truthy(first < last)
	end)

	it('no longer has the old module', function()
		assert.is_false(H.Exists(H.oldModuleFile), 'Modules/Nameplates.lua is deleted')
		assert.is_nil(IndexOf(all, H.oldModuleFile), 'and not in LoadAll.xml')
		assert.is_false(H.Exists(ROOT .. 'Core/Handlers/BackgroundBorder_Examples.lua'))
	end)

	it('loads every core file in Load.xml order, the host, then LastTick', function()
		local core = {}
		for _, entry in ipairs(H.ParseLoadXml(H.moduleXml)) do
			if entry.kind == 'script' then
				core[#core + 1] = entry.path
			end
		end
		assert.truthy(#core > 10)
		local loaded = {}
		for i = 1, #entries - 1 do
			if entries[i].kind == 'script' then
				loaded[#loaded + 1] = entries[i].path
			end
		end
		assert.same(loaded, core, 'exactly the core files, in order, right before the host')
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

-- An earlier version saved "Use the old nameplates" for this character, on a SpartanUI profile that
-- went through setup and saved an old plate width
describe('load order: the host, for a character that was on the old plates', function()
	rawset(_G, 'SpartanUIDB', {
		profileKeys = {},
		profiles = { Default = { SetupWizard = { FirstLaunch = false } } },
		namespaces = { Nameplates = { profiles = { Default = { width = '140', elements = { TargetIndicator = { enabled = false } } } } } },
	})
	local SUI, ns, module = H.LoadNameplatesLikeTheGame({ saved = { char = { [H.CharacterKey()] = { engine = 'old' } } } })
	local P = ns.Plates

	it('ends up with one Nameplates module, made by the host, carrying the core API', function()
		assert.not_nil(module)
		assert.is_true(rawequal(module.API, P.API))
		assert.is_true(rawequal(SUI:GetModule('Nameplates'), module))
	end)

	it('logs in without errors and starts the plates where the profile wants them', function()
		M.Login('SpartanUI')
		M.Advance(1)
		assert.is_true(P.initialized, 'the core opened its database')
		assert.equal(P.enabled, not SUI.IsRetail, 'Retail waits for the player to pick a style')
		assert.not_nil(H.sui.commands.np, '/sui np is registered')
		local errors = {}
		for _, line in ipairs(H.logs.Nameplates or {}) do
			if line:find('^error:') then
				errors[#errors + 1] = line
			end
		end
		assert.empty(errors, 'logged errors')
	end)

	it('drops the saved choice and brings the old settings over', function()
		assert.is_nil(rawget(P.db.char, 'engine'), 'the old choice is gone')
		local profile = P.db.profile
		assert.is_true(profile.migratedFromOld)
		if SUI.IsRetail then
			assert.is_false(profile.enabled, 'Retail never had the old plates: they wait for the player')
			assert.equal(P.Migrate:MakeoverState(), 'off')
		else
			assert.equal(profile.style, 'clean')
			assert.same(profile.tweaks.clean.changes.plate.sizes.medium, { 140, SUI.IsForever and 10 or 8 })
			assert.is_true(profile.tweaks.clean.remove.arrows, 'the target arrows the player turned off, saved under their old name')
			assert.equal(P.Migrate:MakeoverState(), 'import')
			local _, text = module.Makeover:Text()
			assert.is_nil(text:find('old nameplates', 1, true), 'no way back to plates that are gone')
		end
		assert.equal(SpartanUIDB.namespaces.Nameplates.profiles.Default.elements.TargetIndicator.enabled, false, 'the old saved data is left alone')
	end)

	it('has no switch to the old plates left', function()
		H.sui.printed = {}
		H.sui.commands.np.fn('preview')
		assert.is_nil(rawget(P.db.char, 'engine'))
		assert.equal(#H.sui.printed, 1, 'only the help line')
		assert.is_nil(H.sui.printed[1]:find('preview', 1, true), 'the help line does not offer it')
		assert.is_nil(P.Config.GetEngineChoice)
		assert.is_nil(P.Config.SetEngineChoice)
		for _, entry in ipairs(H.sui.options) do
			if entry.name == 'Nameplates' then
				local sharing = entry.table.args.sharing
				assert.is_nil(entry.table.args.useOldPlates)
				assert.is_nil(sharing and sharing.args.useOldPlates)
			end
		end
	end)
end)
