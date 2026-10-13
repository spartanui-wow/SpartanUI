-- @runtime lua51
-- Phase 4a launch through the real host (plan 3.1, 5.4, 6.10, 7.4): the old module, the core and
-- the host load in LoadAll.xml order for an existing SpartanUI profile with nothing saved for the
-- new plates. The new plates are the default: on the Classic family and Forever the profile
-- switches to Clean with its old plate width and sizes and the engine starts; on Retail the plates
-- stay off (the engine does not start) until the player picks a style. Both get the What's new
-- card. Also: the War look, profile tools, setup decoration, the old plates switch and the launch
-- options.
local M, H = ...

if not (H.ModuleExists() and H.Exists(H.hostFile)) then
	describe('host launch', function()
		pending('all', 'the nameplate module or its host does not exist yet')
	end)
	return
end

-- An existing player's SpartanUI profile (setup done) with an old saved plate width
rawset(_G, 'SpartanUIDB', {
	profileKeys = {},
	profiles = { Default = { SetupWizard = { FirstLaunch = false } } },
	namespaces = { Nameplates = { profiles = { Default = { width = '150', Scale = 1, elements = { Castbar = { enabled = false } } } } } },
})
-- The player's faction banner, cut from the War look's art
local BANNER = 'Interface\\AddOns\\SpartanUI\\images\\war\\Nameplate' .. (UnitFactionGroup('player') == 'Horde' and 'Horde' or 'Alliance')
local SUI, ns, module = H.LoadNameplatesLikeTheGame()
local P = ns.Plates
local profiles = SUI:NewModule('Handler.Profiles')
profiles.compositeComponents = {}
profiles.hiddenNamespaces = {}
H.sui.themes.War = { nameplates = { style = 'war', art = { banner = BANNER } } }
-- SpartanUI's setup registration with its Done page links (Core/Handlers/SetupWizard.lua)
local finish = { links = { { title = 'Frame sizes' } } }
rawset(SUI.Setup.registration, 'config', { finish = finish })
local retail = SUI.IsRetail
local defaultHeight = SUI.IsForever and 10 or 8

local function LibATCall(path)
	local found
	for _, call in ipairs(H.libatCalls or {}) do
		if call.path == path then
			found = call
		end
	end
	return found
end

local function OldPlatesSpawned()
	for _, call in ipairs(H.oldCalls or {}) do
		if call.path == 'SUIUF.SpawnNamePlates' then
			return true
		end
	end
	return false
end

local function RootOptions()
	for _, entry in ipairs(H.sui.options) do
		if entry.name == 'Nameplates' and entry.parent == 'Root' then
			return entry.table
		end
	end
	return nil
end

describe('host launch', function()
	it('starts the new plates by default at login where the old ones ran', function()
		M.Login('SpartanUI')
		M.Advance(1)
		assert.is_nil(P.Config:GetSessionEngine(), 'no switch saved')
		if retail then
			assert.is_false(P.enabled, 'an existing Retail profile waits for the player')
			assert.equal(P:RegisteredEventCount(), 0, 'and the plates leave the game alone meanwhile')
		else
			assert.is_true(P.enabled, 'the engine is on')
		end
		assert.not_nil(RootOptions(), 'Nameplates is a top-level settings entry')
		assert.is_false(OldPlatesSpawned(), 'the old plates do not run')
	end)

	it('shows the module as a normal SpartanUI part that knows its conflicts', function()
		assert.is_nil(module.HideModule)
		assert.equal(module.DisplayName, 'Nameplates')
		assert.contains(module.ConflictsWith, 'Plater')
		assert.contains(module.ConflictsWith, 'Platynator')
		assert.not_contains(module.ConflictsWith, 'ElvUI')
		assert.is_true(rawequal(module.API, P.API))
	end)

	it('gives each client the right start for an existing profile (7.4)', function()
		local profile = P.db.profile
		assert.is_true(profile.migratedFromOld)
		if retail then
			assert.is_false(profile.enabled, 'Retail never had these plates: they wait for the player')
			assert.equal(P.Migrate:MakeoverState(), 'off')
			assert.is_nil(rawget(profile, 'tweaks'))
		else
			assert.equal(profile.style, 'clean')
			assert.same(profile.tweaks.clean.changes.plate.sizes.medium, { 150, defaultHeight })
			assert.is_true(profile.tweaks.clean.remove.cast, 'a part the player turned off stays off')
			assert.equal(P.Migrate:MakeoverState(), 'import')
		end
		assert.is_nil(rawget(profile, 'behavior'), 'migrated players get no game setting changes')
		assert.equal(SpartanUIDB.namespaces.Nameplates.profiles.Default.width, '150', 'the old settings stay for one release')
	end)

	it('reads the old defaults the old module registered', function()
		if retail then
			skip('no old module on Retail')
		end
		local database = rawget(module, 'Database')
		assert.not_nil(database, 'the old module opened its namespace')
		assert.equal(database.defaults.profile.width, SUI.IsForever and 152 or 128)
	end)

	it("shows the What's new card once the player is in the world", function()
		assert.is_true(module.Makeover:Due())
		local title, text = module.Makeover:Text()
		assert.equal(title, 'Your nameplates got a makeover')
		if retail then
			assert.matches(text, 'can draw your nameplates now')
		else
			assert.matches(text, 'kept your plate size and text size')
		end
		M.Advance(10)
		assert.is_true(module.Makeover.shown)
		assert.not_nil(LibATCall('LibAT.Setup.Hub.ShowToast'), 'without the window kit the card falls back to a toast')
	end)

	it('says what switching means when another nameplate addon is loaded', function()
		M.loadedAddons = { Plater = true }
		local _, text = module.Makeover:Text()
		M.loadedAddons = nil
		assert.matches(text, 'Plater draws your nameplates now')
		assert.matches(text, 'turns it off for this character')
	end)

	it('turns plates on and opens the style page on Pick a style', function()
		module.Makeover:Pick()
		assert.equal(P.Migrate:MakeoverState(), 'done')
		assert.is_true(P.db.profile.enabled)
		assert.same(H.sui.openedTo.path, { 'Nameplates', 'style' })
		assert.is_false(module.Makeover:Due())
		M.Advance(0.1)
		assert.is_true(P.enabled, 'the plates start without a reload')
	end)

	it('turns the other addon off for this character before switching', function()
		M.loadedAddons = { Plater = true }
		module.Makeover:Pick()
		M.loadedAddons = nil
		local calls = M.FnCalls('C_AddOns.DisableAddOn')
		assert.is_true(#calls >= 1)
		assert.equal(calls[#calls][1], 'Plater')
		assert.equal(type(calls[#calls][2]), 'string', 'for this character only')
	end)

	it('registers the War style with the faction banner and follows the War look', function()
		local war = P.Styles.Registry:Get('war')
		assert.not_nil(war)
		assert.equal(war.parts.banner.art, BANNER)
		assert.equal(P.Styles.Registry:ResolveId('host'), 'spartanui')
		local host = P.Styles.Registry:Get('spartanui')
		assert.not_nil(host.parts.banner, 'Match my look on War is the War style')
		assert.is_true(host.matchesHost)
		local resolved = P.Styles.Merge:Resolve('war', 'enemyNPC', 'medium')
		assert.not_nil(resolved)
		assert.not_nil(resolved.parts.banner)
	end)

	it('gives art themes without a block a smooth bar, and flat themes the flat one', function()
		rawset(SUI.ThemeRegistry, 'Get', function(_, name)
			if name == 'Fel' then
				return { artGroups = { sections = {} } }
			end
			return {}
		end)
		H.sui.themes.Fel = {}
		H.sui.activeStyle = 'Fel'
		H.FireSUIEvent('ARTWORK_STYLE_CHANGED')
		M.Advance(0.2)
		assert.equal(P.hostLook.tokens.bar, 'SpartanUI Default')
		assert.is_nil(P.Styles.Registry:Get('spartanui').parts.banner)
		H.sui.themes.Grid = {}
		H.sui.activeStyle = 'Grid'
		H.FireSUIEvent('ARTWORK_STYLE_CHANGED')
		M.Advance(0.2)
		assert.is_nil(P.hostLook.tokens.bar, 'the core flat bar')
		H.sui.activeStyle = 'War'
		H.FireSUIEvent('ARTWORK_STYLE_CHANGED')
		M.Advance(0.2)
	end)

	it('adds its look step to SpartanUI setup next to the other look steps', function()
		local step
		for _, item in ipairs(H.sui.setupSteps) do
			if item.id == 'nameplates-look' then
				step = item
			end
		end
		assert.not_nil(step)
		assert.equal(step.order, 22)
		assert.equal(step.chapter, 'Look')
		assert.is_false(step.hidden())
		assert.is_nil(step.banner())
		M.enabledAddons = { Plater = true }
		local banner = step.banner()
		M.enabledAddons = nil
		assert.not_nil(banner)
		assert.equal(banner.step, 'conflicts')
		assert.matches(banner.title, 'Plater')
		P.Config:SetEngineChoice('old')
		assert.is_true(step.hidden(), 'not asked while the old plates are picked')
		P.Config:SetEngineChoice(nil)
	end)

	it('adds its two links to the Done page, once', function()
		assert.equal(#finish.links, 3)
		assert.equal(finish.links[1].title, 'Frame sizes')
		local change, giveBack = finish.links[2], finish.links[3]
		assert.equal(change.title, 'Change what shows')
		assert.equal(giveBack.title, 'Give the game back its settings')
		change.onClick()
		assert.same(H.sui.openedTo.path, { 'Nameplates', 'customize' })
		local name = 'nameplateMaxDistance'
		M.SetCVarState(name, { value = '40', account = true })
		P.CVars.info[name] = nil
		P.CVars:Set(name, 60)
		P.Store:Set({ 'behavior', 'pinScale' }, true)
		giveBack.onClick()
		assert.equal(C_CVar.GetCVar(name), '40')
		assert.is_nil(P.Store:Get({ 'behavior', 'pinScale' }))
	end)

	it('waits to bring old settings over while this character still uses the old plates', function()
		P.Config.sessionEngine = 'old'
		local answer = module.ImportLegacy('Default')
		P.Config.sessionEngine = nil
		assert.equal(answer.action, 'later')
	end)

	it('reads the role from the unit frames setup answer', function()
		local UF = rawget(SUI, 'UF')
		rawset(SUI, 'UF', {
			GetSetupRole = function()
				return 'dps'
			end,
		})
		local role = P.host.GetSetupRole()
		rawset(SUI, 'UF', UF)
		assert.equal(role, 'damage')
	end)

	it('joins the profile tools: one full-profile component, the old namespace left out', function()
		assert.equal(#profiles.compositeComponents, 1)
		local component = profiles.compositeComponents[1]
		assert.equal(component.id, 'sui_nameplates')
		assert.is_true(component.isAvailable())
		assert.is_true(profiles.hiddenNamespaces.Nameplates)
		local registered = LibATCall('LibAT.ProfileManager.RegisterAddon')
		assert.not_nil(registered, 'the nameplate profiles are their own profile manager entry')
		assert.equal(registered[2].id, 'spartanui_nameplates')
		assert.is_true(rawequal(registered[2].db, P.db))
	end)

	it('exports and imports the nameplate profile', function()
		local component = profiles.compositeComponents[1]
		P.Store:Set('size', 'large')
		local data = component.export()
		assert.equal(data.format, 'SpartanUINameplates')
		assert.equal(data.profile.size, 'large')
		P.Store:Set('size', 'small')
		local ok = component.import(data)
		assert.is_true(ok)
		assert.equal(P.db.profile.size, 'large')
		assert.is_true(P.db.profile.migratedFromOld, 'an imported profile is never imported from the old plates')
		local refused, reason = component.import({ format = 'Other' })
		assert.is_false(refused)
		assert.not_nil(reason)
		local newer = P.util.Copy(data)
		newer.profile.schema = 999
		assert.is_false((component.import(newer)))
		P.Store:Reset('size')
	end)

	it('offers launch controls on the settings root', function()
		local root = RootOptions()
		assert.not_nil(root.args.turnOn)
		assert.is_true(root.args.turnOn.hidden(), 'plates are on')
		P.Store:Set('enabled', false)
		assert.is_false(root.args.turnOn.hidden())
		root.args.turnOn.func()
		assert.is_true(P.db.profile.enabled)
		if retail then
			assert.is_nil(root.args.useOldPlates, 'Retail has no old plates')
		else
			assert.not_nil(root.args.useOldPlates)
			assert.is_false(root.args.useOldPlates.get())
		end
	end)

	it('switches to the old plates for the next session and gives the game its settings back now', function()
		if retail then
			skip('no old plates on Retail')
		end
		local name = 'nameplateMaxDistance'
		M.SetCVarState(name, { value = '40', account = true })
		P.CVars.info[name] = nil
		P.CVars:Set(name, 60)
		RootOptions().args.useOldPlates.set(nil, true)
		assert.equal(P.Config:GetEngineChoice(), 'old')
		assert.is_false(P.enabled, 'the new plates stop at once')
		assert.equal(C_CVar.GetCVar(name), '40')
		assert.is_true(RootOptions().args.useOldPlates.get())
		RootOptions().args.useOldPlates.set(nil, false)
		assert.equal(P.Config:GetEngineChoice(), 'new')
	end)
end)
