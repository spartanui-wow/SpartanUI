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

	it('still brings old settings over after switching back to the new plates', function()
		if retail then
			skip('no old plates on Retail')
		end
		P.Config.sessionEngine = 'old'
		P.Config:SetEngineChoice('old')
		assert.equal(module.ImportLegacy('Default').action, 'later')
		RootOptions().args.sharing.args.useOldPlates.set(nil, false)
		-- The next session starts on the new plates
		P.Config.sessionEngine = nil
		local answer = module.ImportLegacy('Default')
		assert.is_true(answer == nil or answer.action ~= 'later')
		assert.is_false(P.Config:GetEngineChoice() == 'new', 'never marked as a tester')
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
		-- A hand-made or damaged backup goes through the same checks as a share string
		local bad = P.util.Copy(data)
		bad.styles = { badstyle = { name = 'Bad', base = { id = 'badstyle', parts = 'nope' } } }
		bad.profile.size = 'huge'
		bad.profile.junk = { 1, 2, 3 }
		bad.profile.cvars = { nameplateMaxDistance = 40, nameplateMotion = 1 }
		assert.is_true((component.import(bad)))
		assert.is_nil(P.Store:Get({ 'styles', 'badstyle' }, 'global'), 'a broken style is not saved')
		assert.is_nil(P.db.profile.junk)
		assert.not_equal(P.db.profile.size, 'huge')
		assert.equal(P.Store:Get({ 'cvars', 'nameplateMaxDistance' }), 40)
		assert.is_nil(P.Store:Get({ 'cvars', 'nameplateMotion' }))
		P.Store:Reset('size')
		P.Store:Reset('cvars')
	end)

	it('offers launch controls on the settings root', function()
		local root = RootOptions()
		assert.not_nil(root.args.turnOn)
		assert.is_true(root.args.turnOn.hidden(), 'plates are on')
		P.Store:Set('enabled', false)
		assert.is_false(root.args.turnOn.hidden())
		assert.is_false(root.args.style.args.turnOn.hidden(), 'the Style page says it too')
		root.args.turnOn.func()
		assert.is_true(P.db.profile.enabled)
		assert.is_true(root.args.style.args.turnOn.hidden())
		assert.is_nil(root.args.useOldPlates, 'the root stays empty so it opens the Style page')
		if retail then
			assert.is_nil(root.args.sharing.args.useOldPlates, 'Retail has no old plates')
		else
			local old = root.args.sharing.args.useOldPlates
			assert.not_nil(old)
			assert.is_true(old.advanced)
			assert.is_false(old.get())
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
		RootOptions().args.sharing.args.useOldPlates.set(nil, true)
		assert.equal(P.Config:GetEngineChoice(), 'old')
		assert.is_false(P.enabled, 'the new plates stop at once')
		assert.equal(C_CVar.GetCVar(name), '40')
		assert.is_true(RootOptions().args.sharing.args.useOldPlates.get())
		RootOptions().args.sharing.args.useOldPlates.set(nil, false)
		assert.is_nil(P.Config:GetEngineChoice(), 'the launch default, not the tester mark')
	end)
end)

----------------------------------------------------------------------------------------------------
-- Polish (stage C leftovers): opening settings, the What's new card and the LibAT stub
----------------------------------------------------------------------------------------------------

describe('host: opening settings', function()
	it('opens a page and scrolls to one of its controls', function()
		P.host.OpenOptions('colors', 'list')
		assert.same(H.sui.openedTo.path, { 'Nameplates', 'colors' })
		assert.equal(H.sui.openedTo.key, 'list')
		P.host.OpenOptions()
		assert.same(H.sui.openedTo.path, { 'Nameplates' })
		assert.is_nil(H.sui.openedTo.key)
	end)

	it('takes a path to a control inside an inline group', function()
		P.host.OpenOptions('sharing', { 'export', 'exportText' })
		assert.same(H.sui.openedTo.path, { 'Nameplates', 'sharing', 'export' })
		assert.equal(H.sui.openedTo.key, 'exportText')
		P.host.OpenOptions('sharing', { 'import', 'importText' })
		assert.same(H.sui.openedTo.path, { 'Nameplates', 'sharing', 'import' })
		assert.equal(H.sui.openedTo.key, 'importText')
	end)

	it('lands the Style page Share and Import buttons on real controls of the Sharing page', function()
		local sharing = RootOptions().args.sharing
		for _, name in ipairs({ 'export', 'import' }) do
			local node = sharing
			for _, key in ipairs(P.SharingPage.FOCUS[name]) do
				assert.not_nil(node.args, 'a group with controls before ' .. key)
				node = node.args[key]
				assert.not_nil(node, key .. ' is on the Sharing page')
			end
			assert.not_equal(node.type, 'group', name .. ' lands on a control, not on an inline group')
		end
	end)
end)

describe('host: the preview panel', function()
	it('turns Show all parts off when the settings window closes', function()
		local provider = H.sui.previews[1]
		assert.not_nil(provider, 'the preview panel is registered')
		P.Regions:SetShowAll(true)
		assert.is_true(P.Regions:IsShowingAll())
		provider:Close()
		assert.is_false(P.Regions:IsShowingAll(), 'the boxes do not stay on the plates in the world')
		-- Hiding the panel for another page leaves the switch alone: the player is still looking
		P.Regions:SetShowAll(true)
		provider:Hide()
		assert.is_true(P.Regions:IsShowingAll())
		P.Regions:SetShowAll(false)
	end)
end)

describe("host: the What's new card", function()
	local printed, reloads = {}, 0
	local Makeover = module.Makeover

	local function Fresh(state)
		printed, reloads = {}, 0
		rawset(SUI, 'Print', function(_, text)
			printed[#printed + 1] = text
		end)
		rawset(_G, 'ReloadUI', function()
			reloads = reloads + 1
		end)
		P.Store:Set({ 'seen', 'makeover', P.db:GetCurrentProfile() }, state or 'import', 'global')
		Makeover.shown, Makeover.card, Makeover.tries = false, nil, 0
		H.sui.openedTo = nil
		M.loadedAddons = nil
		M.enabledAddons = nil
		rawset(_G, 'ElvUI', nil)
	end

	local function Said(text)
		for _, line in ipairs(printed) do
			if line:find(text, 1, true) then
				return true
			end
		end
		return false
	end

	local function InstallKit()
		local Kit = {}
		function Kit.CreateShell()
			local shell = CreateFrame('Frame', nil, UIParent)
			shell.Body = CreateFrame('Frame', nil, shell)
			return shell
		end
		function Kit.CreateButton(_, parent, text)
			local button = CreateFrame('Button', nil, parent)
			button.shownText = text
			function button:SetText(value)
				self.shownText = value
			end
			return button
		end
		rawset(LibAT.UI, 'Kit', Kit)
	end

	local function RemoveKit()
		rawset(LibAT.UI, 'Kit', nil)
	end

	local function Click(button)
		button:GetScript('OnClick')(button)
	end

	after_each(function()
		RemoveKit()
		M.loadedAddons, M.enabledAddons = nil, nil
		rawset(_G, 'ElvUI', nil)
		rawset(_G, 'ReloadUI', nil)
		rawset(SUI, 'Print', nil)
	end)

	it('has a button for each choice, and every one leads somewhere', function()
		Fresh()
		InstallKit()
		Makeover:Show()
		local card = Makeover.card
		assert.not_nil(card, 'the window kit draws the card')
		assert.equal(card.pick.shownText, 'Pick a style')
		assert.equal(card.later.shownText, 'Not now')
		assert.equal(card.never.shownText, "Don't show again")
		assert.is_true(card.shell:IsShown())
		Click(card.pick)
		assert.is_false(card.shell:IsShown())
		assert.same(H.sui.openedTo.path, { 'Nameplates', 'style' })
		assert.equal(P.Migrate:MakeoverState(), 'done')
	end)

	it('comes back at the next login after Not now', function()
		Fresh()
		InstallKit()
		Makeover:Show()
		Click(Makeover.card.later)
		assert.is_false(Makeover.card.shell:IsShown())
		assert.equal(P.Migrate:MakeoverState(), 'import', 'nothing was answered')
		assert.is_true(Makeover:Due(), 'the next login shows it again')
		assert.is_true(Makeover.shown, 'but not again in this session')
	end)

	it("is closed for good by Don't show again", function()
		Fresh()
		InstallKit()
		Makeover:Show()
		Click(Makeover.card.never)
		assert.equal(P.Migrate:MakeoverState(), 'done')
		assert.is_false(Makeover:Due())
		assert.is_nil(H.sui.openedTo, 'nothing opens')
	end)

	it('closes the toast for good with its close button, and says where the styles are', function()
		Fresh()
		H.libatCalls = {}
		Makeover:Show()
		local call
		for _, item in ipairs(H.libatCalls) do
			if item.path == 'LibAT.Setup.Hub.ShowToast' then
				call = item
			end
		end
		assert.not_nil(call, 'a toast without the window kit')
		assert.equal(call[3], 'Pick a style')
		assert.equal(type(call[5].onDismiss), 'function')
		call[5].onDismiss()
		assert.equal(P.Migrate:MakeoverState(), 'done')
		assert.is_true(Said('under Nameplates'), 'the way back to the styles')
	end)

	it('says it once in chat, and closes for good, when nothing else can show it', function()
		Fresh()
		local hub = LibAT.Setup.Hub
		rawset(hub, 'ShowToast', false)
		Makeover:Show()
		rawset(hub, 'ShowToast', nil)
		assert.is_true(Said('Your nameplates got a makeover'))
		assert.is_true(Said('under Nameplates'))
		assert.equal(P.Migrate:MakeoverState(), 'done', 'it does not repeat at every login')
	end)

	it('only says how to turn off the other plates while ElvUI draws them', function()
		Fresh()
		M.loadedAddons = { ElvUI = true }
		rawset(_G, 'ElvUI', { { private = { nameplates = { enable = true } } } })
		assert.equal(Makeover:PickLabel(), 'Got it')
		local before = #M.FnCalls('C_AddOns.DisableAddOn')
		InstallKit()
		Makeover:Show()
		assert.is_false(Makeover.card.never:IsShown(), '"Got it" already closes the card for good')
		Click(Makeover.card.pick)
		assert.equal(#M.FnCalls('C_AddOns.DisableAddOn'), before, 'its nameplates can only be turned off in its own settings')
		assert.equal(reloads, 0)
		assert.is_true(Said('Turn its nameplates off in its own settings, then reload'))
		assert.equal(P.Migrate:MakeoverState(), 'done')
		assert.is_true(P.db.profile.enabled, 'ours start once it is off')
	end)

	it('reloads after turning another addon off, and opens the Style page after the reload', function()
		Fresh()
		M.loadedAddons = { Plater = true }
		Makeover:Pick()
		M.loadedAddons = nil
		assert.equal(reloads, 1)
		assert.is_true(P.Store:Get('styleAfterReload', 'char'))
		assert.is_nil(H.sui.openedTo, 'the page opens after the reload, not before')
		-- The next session
		Makeover:ResumeAfterReload()
		assert.is_nil(P.Store:Get('styleAfterReload', 'char'), 'asked for once')
		M.Advance(20)
		assert.same(H.sui.openedTo.path, { 'Nameplates', 'style' })
		H.sui.openedTo = nil
		Makeover:ResumeAfterReload()
		M.Advance(20)
		assert.is_nil(H.sui.openedTo, 'not again')
	end)

	it('says what to do when the other addon cannot be turned off from here', function()
		Fresh()
		M.loadedAddons = { Plater = true }
		local disable = C_AddOns.DisableAddOn
		rawset(C_AddOns, 'DisableAddOn', nil)
		local ok, err = pcall(Makeover.Pick, Makeover)
		rawset(C_AddOns, 'DisableAddOn', disable)
		M.loadedAddons = nil
		assert.is_true(ok, tostring(err))
		assert.equal(reloads, 0)
		assert.is_true(Said('Turn it off in your addon list, then reload'))
	end)
end)

describe('LibAT stub', function()
	local function Run(libat)
		local saved = rawget(_G, 'LibAT')
		rawset(_G, 'LibAT', libat)
		M.ResetRecords()
		local chunk = assert(loadfile(HARNESS_ROOT .. 'Core/LibATStub.lua'))
		local ok, err = pcall(chunk, 'SpartanUI', {})
		rawset(_G, 'LibAT', saved)
		assert.is_true(ok, tostring(err))
		local asks = 0
		for _, event in ipairs(M.rec.events) do
			if event.event == 'PLAYER_LOGIN' and tostring(event.where):find('LibATStub', 1, true) then
				asks = asks + 1
			end
		end
		return asks
	end

	local function Current()
		return { UI = { Options = {} }, Capabilities = { cardArtDraw = 1, searchSynonyms = 2 } }
	end

	it('stays quiet for a LibAT that has the settings window and the new capabilities', function()
		assert.equal(Run(Current()), 0)
	end)

	it('asks for an update when the card art hook is missing', function()
		local libat = Current()
		libat.Capabilities.cardArtDraw = nil
		assert.equal(Run(libat), 1)
	end)

	it('asks for an update when the search words are an older revision', function()
		local libat = Current()
		libat.Capabilities.searchSynonyms = 1
		assert.equal(Run(libat), 1)
	end)

	it('asks for an update for a LibAT that does not list capabilities, and lists none for it', function()
		local libat = { UI = { Options = {} } }
		assert.equal(Run(libat), 1)
		assert.equal(type(libat.Capabilities), 'table', 'reading an entry gives nil, never an error')
		assert.is_nil(libat.Capabilities.cardArtDraw)
		assert.is_nil(libat.Capabilities.searchSynonyms, 'nothing is claimed')
	end)

	it('asks for the download when LibAT is missing', function()
		assert.equal(Run(nil), 1)
	end)
end)
