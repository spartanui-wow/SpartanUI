local _, ns = ...
local SUI = SUI
local P = ns.Plates
if not (SUI and P) then
	return
end
local L = SUI.L

-- SpartanUI host for the nameplate core. This is the only file in Modules/Nameplates that may
-- mention SpartanUI, its paths, strings, assets or commands. It is loaded from Modules/LoadAll.xml
-- right after the core's Load.xml, and it creates the 'Nameplates' module on every client.
--
-- The engine (P:Enable) starts only when all of these hold; otherwise neither the core nor this
-- file registers a game event, installs a hook, writes a game setting or makes a named frame:
--   * the module is on and no other nameplate addon is loaded (HostWantsEngine),
--   * the current profile wants plates (profile.enabled ~= false, ProfileWantsPlates).
-- A profile that turns plates on later (What's new card, setup, the settings root, a profile
-- switch) starts the engine on the next frame. Turning the module off stops the engine and gives
-- the game back every setting the plates changed, including ones an earlier session left behind.
--
-- Who gets what (plan 7.4) is decided per profile by ImportLegacy: a profile that used the old
-- SpartanUI plates (every client but Retail) switches to Clean with its old sizes; an existing
-- Retail profile keeps the game's plates until the player picks a style on the What's new card; a
-- new profile gets setup's look step. Migrated profiles get no game setting changes; only setup
-- turns those on. The old plates' saved settings are read, never written.
--
-- Looks (plan 5.4): "Match my look" is the host style. It draws the active theme's nameplates
-- block (ThemeRegistry data), else the theme family's default: art themes get Clean on a smooth bar
-- with a dark frame, flat themes Clean on the core's flat bar. Accent and font come from the
-- theme. The profile default style is 'host', so a profile follows the theme until the player
-- picks another style, and that pick always wins (following the theme is itself a pick).

-- Folder names of addons that also draw nameplates (7.4). Code data only; titles are read at
-- runtime. Two spellings of one folder are listed because its name is not confirmed.
local CONFLICTS = { 'Plater', 'TidyPlates_ThreatPlates', 'TidyPlates', 'NeatPlates', 'Kui_Nameplates', 'KuiNameplates', 'Platynator', 'EllesmereUINameplates' }

-- A UI suite whose nameplates count only while they are on. It is left out of ConflictsWith: the
-- setup conflicts step would turn the whole suite off for its nameplates.
local SUITE = 'ElvUI'

local HOST_STYLE_ID = 'spartanui'
local WAR_STYLE_ID = 'war'
local WAR_BANNER = 'Interface\\AddOns\\SpartanUI\\images\\war\\Nameplate'
local OPTIONS_APP = 'SpartanUI'
-- LibAT.Capabilities.searchSynonyms: the first revision whose search takes one addon's own words
local SEARCH_SYNONYMS_REVISION = 2
local SETUP_ORDER = 22
local PROFILE_ADDON_ID = 'spartanui_nameplates'
local COMPONENT_ID = 'sui_nameplates'
local EXPORT_FORMAT = 'SpartanUINameplates'
local MAKEOVER_DELAY = 8

-- The setup "How do you play?" answer, as nameplate roles
local SETUP_ROLES = { healer = 'healer', tank = 'tank', dps = 'damage' }

-- Theme families without a nameplates block of their own (5.4): art themes get a smooth bar with a
-- dark frame, flat themes the core's flat bar. Both draw Clean with the theme's accent and font.
local FAMILY_LOOKS = {
	art = { style = 'clean', tokens = { bar = 'SpartanUI Default', ink = { 0, 0, 0, 1 }, shade = { 0, 0, 0, 0.55 } } },
	flat = { style = 'clean', tokens = {} },
}

local module = SUI:NewModule('Nameplates')
module.DisplayName = L['Nameplates']
module.description = 'Nameplates with ready-made styles and a live preview'
module.ConflictsWith = CONFLICTS
module.API = P.API

-- The game settings the Convenience "Recommended game tweaks" button asks for: plates shown out of
-- combat too, and no bar of your own under your character
local RECOMMENDED_CVARS = { nameplateShowAll = true, nameplateShowSelf = false }

-- The old SpartanUI plates ran on every client but Retail; their settings come over from there
local HAD_OLD_PLATES = not SUI.IsRetail

-- P:Enable ran through this host
local engineRunning = false
-- The module runs the plates this session (the profile may still have them off)
local platesActive = false
-- The login work ran: the engine may start whenever a profile turns plates on
local loginDone = false
local startQueued = false
local hooksInstalled = false
local lookWatchersInstalled = false
local lookQueued = false

local function Print(text)
	if SUI.Print then
		SUI:Print(text)
	end
end

local function Copy(value)
	return P.util.Copy(value)
end

-- Player facts go through the core's Source, the one place that reads units
local playerSource

---@return Plates.LiveSource
local function Player()
	playerSource = playerSource or P.Source.NewLive('player')
	return playerSource
end

----------------------------------------------------------------------------------------------------
-- Other nameplate addons
----------------------------------------------------------------------------------------------------

---An addon's name as its list shows it, without color codes or icons.
---@param folder string
---@return string
local function AddonTitle(folder)
	local title
	if C_AddOns and C_AddOns.GetAddOnMetadata then
		local ok, value = pcall(C_AddOns.GetAddOnMetadata, folder, 'Title')
		title = ok and type(value) == 'string' and value or nil
	end
	if not title then
		return folder
	end
	title = title:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', ''):gsub('|T.-|t', ''):gsub('^%s+', ''):gsub('%s+$', '')
	return title ~= '' and title or folder
end

---@param folder string
---@return boolean
local function Loaded(folder)
	return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(folder) and true or false
end

---A UI suite's nameplates count as a conflict only when they are on. When its setting cannot be
---read, assume they are on, so two plate engines never run together (S0).
---@param folder string
---@return boolean
local function SuitePlatesOn(folder)
	if not Loaded(folder) then
		return false
	end
	local engine = _G[folder]
	local E = type(engine) == 'table' and engine[1]
	local private = type(E) == 'table' and E.private
	local plates = type(private) == 'table' and private.nameplates
	if type(plates) == 'table' and type(plates.enable) == 'boolean' then
		return plates.enable
	end
	return true
end

---@return string|nil folder First loaded conflicting addon
local function FindConflict()
	for _, folder in ipairs(CONFLICTS) do
		if Loaded(folder) then
			return folder
		end
	end
	if SuitePlatesOn(SUITE) then
		return SUITE
	end
	return nil
end

---Another nameplate addon the setup conflicts step can turn off (enable state, like that step).
---@return string|nil folder
local function EnabledConflict()
	for _, folder in ipairs(CONFLICTS) do
		if SUI.IsAddonEnabled and SUI:IsAddonEnabled(folder) then
			return folder
		end
	end
	return nil
end

---Every other nameplate addon that is loaded or turned on for this character.
---@return string[]
local function ConflictsToTurnOff()
	local list, seen = {}, {}
	for _, folder in ipairs(CONFLICTS) do
		if not seen[folder] and (Loaded(folder) or (SUI.IsAddonEnabled and SUI:IsAddonEnabled(folder))) then
			seen[folder] = true
			list[#list + 1] = folder
		end
	end
	return list
end

----------------------------------------------------------------------------------------------------
-- Which plates run
----------------------------------------------------------------------------------------------------

---The module runs the plates unless it is off or another nameplate addon is loaded.
---@return boolean wants
---@return string|nil reason 'disabled' | 'conflict:<folder>'
local function HostWantsEngine()
	if SUI:IsModuleDisabled('Nameplates') then
		return false, 'disabled'
	end
	local conflict = FindConflict()
	if conflict then
		return false, 'conflict:' .. conflict
	end
	return true
end

---The current profile wants plates (profile.enabled). False keeps the engine from starting.
---@return boolean
local function ProfileWantsPlates()
	local db = P.db
	return not (db and db.profile.enabled == false)
end

----------------------------------------------------------------------------------------------------
-- Looks (5.4)
----------------------------------------------------------------------------------------------------

---@param name string|nil
---@return 'art'|'flat'
local function ThemeFamily(name)
	local registry = SUI.ThemeRegistry
	local meta = registry and registry.Get and name and registry:Get(name)
	if type(meta) == 'table' and meta.artGroups then
		return 'art'
	end
	return 'flat'
end

---The active theme's nameplates block, or its family default.
---@return table block
local function ThemeBlock()
	local name = SUI.GetActiveStyle and SUI:GetActiveStyle() or nil
	local block
	if name and SUI.ThemeRegistry and SUI.ThemeRegistry.GetData then
		local data = SUI.ThemeRegistry:GetData(name)
		block = type(data) == 'table' and data.nameplates or nil
	end
	if type(block) ~= 'table' then
		block = FAMILY_LOOKS[ThemeFamily(name)]
	end
	return block
end

---Theme look for "Match my look": the theme's nameplates block plus accent and font.
---@return Plates.HostLook
local function GetHostLook()
	local block = ThemeBlock()
	local r, g, b = 1, 0.82, 0
	if SUI.UI and SUI.UI.Style and SUI.UI.Style.GetAccent then
		r, g, b = SUI.UI.Style:GetAccent()
	end
	local font = SUI.Font and SUI.Font.GetFont and SUI.Font:GetFont('Nameplates') or nil
	local tokens = Copy(block.tokens or {})
	tokens.accent = tokens.accent or { r, g, b, 1 }
	tokens.font = tokens.font or font
	return { style = block.style, tokens = tokens, art = Copy(block.art or {}), accent = { r, g, b, 1 }, font = font }
end

---The player's faction banner, cut from the War look's unit frame art (images/war). Pandaren
---who have not picked a side get the Alliance banner.
---@return string
local function WarBanner()
	local faction = Player():FactionPlain()
	return WAR_BANNER .. (faction == 'Horde' and 'Horde' or 'Alliance')
end

---The War style: Clean on a smooth bar with the player's faction banner behind it. It is a style
---of its own in the gallery, and what "Match my look" draws on the War look.
local function RegisterWarStyle()
	local clean = P.Styles.Registry:Get('clean')
	if not clean then
		return
	end
	local style = Copy(clean)
	style.id = WAR_STYLE_ID
	style.name = L['War']
	style.description = L['Your faction banner behind a smooth bar, from the War look.']
	style.order = 2
	style.matchesHost = nil
	style.internal = nil
	style.tokens = { accent = '$host', font = '$host', bar = 'SpartanUI Default', ink = { 0.08, 0.05, 0.03, 1 }, shade = { 0, 0, 0, 0.35 } }
	style.parts.banner = { order = 5, kind = 'art', art = WarBanner(), width = 164, height = 22, anchor = { 'CENTER', 'health', 'CENTER', 0, 0 }, color = { 1, 1, 1, 0.9 }, layer = -2 }
	local ok, reason = P.API:RegisterStyle(style)
	if not ok then
		P.log.warning('The War nameplate style could not be registered: ' .. tostring(reason))
	end
end

---"Match my look": the theme's style (or Clean) with the theme's accent and font, and the bar, ink
---and shade the theme gives. A style keeps its own token for anything the theme leaves out.
local function RegisterHostStyle()
	RegisterWarStyle()
	local look = GetHostLook()
	local style
	if type(look.style) == 'table' then
		style = Copy(look.style)
	else
		local base = P.Styles.Registry:Get(type(look.style) == 'string' and look.style or 'clean') or P.Styles.Registry:Get('clean')
		style = Copy(base)
	end
	local tokens = type(style.tokens) == 'table' and style.tokens or {}
	tokens.accent = '$host'
	tokens.font = '$host'
	for _, name in ipairs({ 'bar', 'ink', 'shade' }) do
		if look.tokens[name] ~= nil or tokens[name] == nil then
			tokens[name] = '$host'
		end
	end
	style.tokens = tokens
	style.id = HOST_STYLE_ID
	style.name = L['Match my look']
	style.description = L['Uses your SpartanUI look: its colors, font and bar.']
	style.matchesHost = true
	style.internal = nil
	style.order = 1
	local ok, reason = P.API:RegisterStyle(style)
	if not ok then
		P.log.warning('Match my look could not be registered: ' .. tostring(reason))
	end
end

---Register "Match my look" (and War) again and hand the core the current theme look. Data only:
---safe while the engine is off, so the gallery and setup cards always show the current theme.
local function RefreshLook()
	RegisterHostStyle()
	P.API:SetHostLook(GetHostLook())
end

---Theme, accent or font changed. Font:Refresh() calls itself once per module, so the push waits
---for the next frame and any number of calls in one frame become one. Only the 'host' choice
---follows the theme: a player who picked another style keeps it.
local function PushLook()
	if not platesActive or lookQueued then
		return
	end
	lookQueued = true
	C_Timer.After(0, function()
		lookQueued = false
		if platesActive then
			RefreshLook()
		end
	end)
end

---Theme and accent changes reach the look whether or not the engine runs (SpartanUI's own
---callbacks, no game events). They cannot be removed, so they are added once and check the state.
local function InstallLookWatchers()
	if lookWatchersInstalled then
		return
	end
	lookWatchersInstalled = true
	if SUI.Event and SUI.Event.RegisterEvent then
		SUI.Event:RegisterEvent('ARTWORK_STYLE_CHANGED', PushLook)
	end
	if SUI.UI and SUI.UI.Style and SUI.UI.Style.OnAccentChanged then
		SUI.UI.Style:OnAccentChanged(module, PushLook)
	end
end

----------------------------------------------------------------------------------------------------
-- Old saved settings (7)
----------------------------------------------------------------------------------------------------

---The old plates' defaults on this client (the values that module registered, without AceDB
---wildcards), for every key the import reads. AceDB saved only what the player changed, so most
---sizes come from here; Forever drew larger plates than the other clients.
---@return table
local function OldDefaults()
	local forever = SUI.IsForever and true or false
	return {
		width = forever and 152 or 128,
		Scale = 1,
		onlyShowPlayer = true,
		showStealableBuffs = false,
		elements = {
			Health = { enabled = true, height = forever and 10 or 8, texture = 'SpartanUI Default' },
			Name = { enabled = true, textSize = forever and 10 or 7 },
			Castbar = { enabled = true, height = 5, texture = 'SpartanUI Default', Icon = { enabled = false, size = 12 } },
			Power = { enabled = false, height = 3 },
			RaidTargetIndicator = { enabled = true, size = 15 },
			QuestMob = { enabled = true, size = 16 },
			TargetHighlight = { enabled = true },
			PvPIndicator = { enabled = false, size = 10 },
			PvPRoleIndicator = { enabled = true, size = 20 },
			ClassIcon = { enabled = false, size = 20 },
		},
	}
end

---The old plates renamed their target element (TargetIndicator became TargetHighlight in 8.2.1)
---and moved its saved settings when they loaded. A profile last saved before that still has the old
---name: read it as the new one, from a copy, so the old saved data stays as it is.
---@param settings table
---@return table
local function RenamedOldElements(settings)
	local elements = rawget(settings, 'elements')
	local indicator = type(elements) == 'table' and rawget(elements, 'TargetIndicator')
	if type(indicator) ~= 'table' then
		return settings
	end
	local out = Copy(settings)
	local highlight = type(out.elements.TargetHighlight) == 'table' and out.elements.TargetHighlight or {}
	for key, value in pairs(out.elements.TargetIndicator) do
		highlight[key] = value
	end
	out.elements.TargetHighlight = highlight
	out.elements.TargetIndicator = nil
	return out
end

---The SpartanUI profile went through setup at least once (an existing player's profile).
---@param key string
---@return boolean
local function HostProfileSetUp(key)
	local saved = rawget(_G, 'SpartanUIDB')
	local profiles = type(saved) == 'table' and rawget(saved, 'profiles')
	local data = type(profiles) == 'table' and rawget(profiles, key)
	local wizard = type(data) == 'table' and rawget(data, 'SetupWizard')
	return type(wizard) == 'table' and rawget(wizard, 'FirstLaunch') == false
end

---Who gets what (7.4), for one nameplate profile key (the SpartanUI profile of the same name).
---Read raw from SpartanUIDB; the old namespace is never written.
---@param profileKey string
---@return table|nil
local function ImportLegacy(profileKey)
	-- A brand-new profile: setup asks instead
	if not HostProfileSetUp(profileKey) then
		return nil
	end
	-- Retail never had SpartanUI plates: they stay off until the player picks a style
	if not HAD_OLD_PLATES then
		return { action = 'off' }
	end
	local saved = rawget(_G, 'SpartanUIDB')
	local namespaces = type(saved) == 'table' and rawget(saved, 'namespaces')
	local namespace = type(namespaces) == 'table' and rawget(namespaces, 'Nameplates')
	local profiles = type(namespace) == 'table' and rawget(namespace, 'profiles')
	local settings = type(profiles) == 'table' and rawget(profiles, profileKey)
	settings = type(settings) == 'table' and RenamedOldElements(settings) or {}
	return { action = 'import', settings = settings, defaults = OldDefaults() }
end
module.ImportLegacy = ImportLegacy

----------------------------------------------------------------------------------------------------
-- Engine start and stop
----------------------------------------------------------------------------------------------------

local function InstallHostHooks()
	if hooksInstalled then
		return
	end
	hooksInstalled = true
	if SUI.Font and SUI.Font.Refresh then
		hooksecurefunc(SUI.Font, 'Refresh', PushLook)
	end
end

local function StartEngine()
	if engineRunning or not platesActive then
		return
	end
	engineRunning = true
	InstallHostHooks()
	RefreshLook()
	P:Enable()
end

local function StopEngine()
	if engineRunning then
		engineRunning = false
		P:Disable()
	end
end

---A profile just turned plates on: start the engine on the next frame, never inside the settings
---write that asked for it.
local function MaybeStartEngine()
	if engineRunning or startQueued or not (platesActive and loginDone) then
		return
	end
	if not (ProfileWantsPlates() and HostWantsEngine()) then
		return
	end
	startQueued = true
	C_Timer.After(0, function()
		startQueued = false
		if platesActive and ProfileWantsPlates() and HostWantsEngine() then
			StartEngine()
		end
	end)
end

---Game settings an earlier session changed and never gave back (the game closed while the plates
---ran) go back to the game. Writes nothing when there is nothing to give back.
local function RestoreLeftovers()
	local db = P.db
	if db and (next(db.global.cvarBackup or {}) or next(db.char.cvarBackup or {})) then
		P.CVars:RestoreAll()
	end
end

---The nameplate half of the Convenience "Recommended game tweaks" button (plan 6.7). The settings
---are kept as this profile's game settings, so the plates write them while they draw for the
---profile, with a backup, list them in the game settings table and give them back with the rest.
---While another nameplate addon draws the plates, or the module is off, nothing changes: those
---settings belong to it, or to the game.
---@return boolean saved
function module:ApplyRecommendedSettings()
	if not P.db or not HostWantsEngine() then
		return false
	end
	P.Store:Batch(function()
		for name, value in pairs(RECOMMENDED_CVARS) do
			P.Store:Set({ 'cvars', name }, value)
		end
	end)
	return true
end

local function WhenLoggedIn(fn)
	-- AceAddon enables modules while PLAYER_LOGIN is dispatched, so registering for it here would
	-- miss it (pitfalls 2026-09-27)
	if IsLoggedIn() then
		fn()
		return
	end
	local waiter = CreateFrame('Frame')
	waiter:RegisterEvent('PLAYER_LOGIN')
	waiter:SetScript('OnEvent', function(self)
		self:UnregisterAllEvents()
		fn()
	end)
end

----------------------------------------------------------------------------------------------------
-- What's new card (3.1): "Your nameplates got a makeover"
----------------------------------------------------------------------------------------------------
--
-- Buttons, every one with somewhere to go:
--   * "Pick a style": plates on for this profile and the Style page opens. With another nameplate
--     addon loaded it is turned off for this character first, the screen reloads, and the Style
--     page opens after the reload. While ElvUI's nameplates are on only the player can turn them
--     off, so this button reads "Got it" and says how.
--   * "Not now": the card goes away until the next login.
--   * "Don't show again": the card is done for this profile (the toast's close button does the same).
-- Escape counts as "Not now". Without the window kit the card is a toast, and without the toast a
-- chat line; both close for good so they never repeat.

---@class SUI.Nameplates.Makeover
local Makeover = { tries = 0 }
module.Makeover = Makeover

---@return boolean
local function CinematicPlaying()
	local setup = LibAT and LibAT.Setup
	if setup and type(setup.IsCinematicPlaying) == 'function' then
		local ok, playing = pcall(setup.IsCinematicPlaying, setup)
		return ok and playing == true
	end
	return (InCinematic and InCinematic()) or (IsInCinematicScene and IsInCinematicScene()) or false
end

---The card is due for the current profile: its plates were brought over from the old ones, or an
---existing Retail profile is waiting for the player to turn them on. Shown while another nameplate
---addon is loaded too, with words about what switching means.
---@return boolean
function Makeover:Due()
	local state = P.Migrate:MakeoverState()
	if state ~= 'import' and state ~= 'off' then
		return false
	end
	if SUI:IsModuleDisabled('Nameplates') then
		return false
	end
	return true
end

---The card's words for the current profile, aware of other nameplate addons.
---@return string title
---@return string text
function Makeover:Text()
	local state = P.Migrate:MakeoverState()
	local lines = {}
	if state == 'import' then
		lines[#lines + 1] = L['We kept your plate size and text size. Pick a new style any time.']
	else
		lines[#lines + 1] = L['SpartanUI can draw your nameplates now, with ready-made styles and a live preview.']
	end
	local conflict = FindConflict()
	if conflict == SUITE then
		lines[#lines + 1] = string.format(L['%s draws your nameplates now. Turn its nameplates off in its own settings to use these.'], AddonTitle(conflict))
	elseif conflict then
		lines[#lines + 1] = string.format(L['%s draws your nameplates now. Picking a style turns it off for this character and reloads your screen.'], AddonTitle(conflict))
		if state == 'import' then
			lines[#lines + 1] = L['From now on, setup asks before another addon draws your nameplates.']
		end
	end
	if state == 'import' then
		return L['Your nameplates got a makeover'], table.concat(lines, '\n\n')
	end
	return L['SpartanUI nameplates are here'], table.concat(lines, '\n\n')
end

---The first button: it only acknowledges while the player has to turn the other plates off alone.
---@return string
function Makeover:PickLabel()
	if FindConflict() == SUITE then
		return L['Got it']
	end
	return L['Pick a style']
end

---"Don't show again": the card does not come back for this profile. Plates that were off stay off.
function Makeover:NotNow()
	P.Migrate:FinishMakeover()
end

---Closed for good by a button that says nothing more (the toast's close button, the chat line).
function Makeover:Dismiss()
	self:NotNow()
	if FindConflict() then
		-- No nameplate settings this session: another addon draws the plates
		Print(L['To use SpartanUI nameplates, turn off the other nameplate addon, or run SpartanUI setup again.'])
		return
	end
	Print(L['You can pick a nameplate style any time. Open SpartanUI settings and look under Nameplates.'])
end

---The next login or after a reload: do not open a window over a fight, a cinematic or setup.
---@return boolean
function Makeover:Blocked()
	local hub = LibAT and LibAT.Setup and LibAT.Setup.Hub
	local setupOpen = false
	if hub and type(hub.IsShown) == 'function' then
		local ok, shown = pcall(hub.IsShown, hub)
		setupOpen = ok and shown == true
	end
	return (InCombatLockdown and InCombatLockdown()) or CinematicPlaying() or setupOpen
end

---Open the Style page when nothing is in the way (retries for a while).
function Makeover:OpenStyleWhenSafe()
	if self:Blocked() then
		self.openTries = (self.openTries or 0) + 1
		if self.openTries < 30 and C_Timer and C_Timer.After then
			C_Timer.After(10, function()
				Makeover:OpenStyleWhenSafe()
			end)
		end
		return
	end
	SUI.Options:OpenTo({ 'Nameplates', 'style' })
end

---After the reload that "Pick a style" asked for, the Style page opens by itself, once.
function Makeover:ResumeAfterReload()
	if not P.Store:Get('styleAfterReload', 'char') then
		return
	end
	P.Store:Set('styleAfterReload', nil, 'char', {})
	if C_Timer and C_Timer.After then
		C_Timer.After(MAKEOVER_DELAY, function()
			Makeover:OpenStyleWhenSafe()
		end)
	end
end

---"Pick a style": plates on for this profile and the style page opens. Another nameplate addon is
---turned off for this character first, then the screen reloads and the page opens after it.
function Makeover:Pick()
	P.Migrate:FinishMakeover()
	P.Store:Set('enabled', true)
	local conflict = FindConflict()
	if conflict == SUITE then
		-- Its nameplates must be turned off in its own settings; ours start once they are
		Print(string.format(L['%s draws your nameplates now. Turn its nameplates off in its own settings, then reload, to use these.'], AddonTitle(conflict)))
		return
	end
	local others = ConflictsToTurnOff()
	local turnedOff = false
	-- This character only, like the setup conflicts step (never every character)
	local character = Player():NamePlain()
	if #others > 0 and type(character) == 'string' and character ~= '' and C_AddOns and C_AddOns.DisableAddOn then
		for _, folder in ipairs(others) do
			C_AddOns.DisableAddOn(folder, character)
		end
		-- Saved now, so the game's addon list cannot throw the change away
		if C_AddOns.SaveAddOns then
			C_AddOns.SaveAddOns()
		end
		turnedOff = true
	end
	if conflict then
		if turnedOff and ReloadUI then
			P.Store:Set('styleAfterReload', true, 'char', {})
			ReloadUI()
		else
			Print(string.format(L['%s draws your nameplates now. Turn it off in your addon list, then reload, to use these.'], AddonTitle(conflict)))
		end
		return
	end
	SUI.Options:OpenTo({ 'Nameplates', 'style' })
end

---Build the card window (LibAT window kit). Nil when the kit is missing.
---@return table|nil card
local function BuildCard()
	local Kit = LibAT and LibAT.UI and LibAT.UI.Kit
	if not (Kit and Kit.CreateShell and Kit.CreateButton) then
		return nil
	end
	local ok, shell =
		pcall(Kit.CreateShell, Kit, { name = 'SUI_NameplatesMakeover', title = L['Your nameplates got a makeover'], width = 480, height = 210, crest = false, titleFrame = true, close = false })
	if not ok or type(shell) ~= 'table' or not shell.CreateFontString then
		return nil
	end
	local body = shell.Body or shell
	local card = { shell = shell }
	local text = body:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	text:SetPoint('TOPLEFT', body, 'TOPLEFT', 18, -18)
	text:SetPoint('TOPRIGHT', body, 'TOPRIGHT', -18, -18)
	text:SetJustifyH('LEFT')
	text:SetWordWrap(true)
	card.text = text
	local never = Kit:CreateButton(body, L["Don't show again"], 'secondary', 150)
	never:SetPoint('BOTTOMRIGHT', body, 'BOTTOMRIGHT', -16, 14)
	local later = Kit:CreateButton(body, L['Not now'], 'secondary', 100)
	later:SetPoint('RIGHT', never, 'LEFT', -8, 0)
	local pick = Kit:CreateButton(body, L['Pick a style'], 'primary', 140)
	pick:SetPoint('RIGHT', later, 'LEFT', -8, 0)
	card.pick, card.later, card.never = pick, later, never
	pick:SetScript('OnClick', function()
		card.answered = true
		shell:Hide()
		Makeover:Pick()
	end)
	later:SetScript('OnClick', function()
		card.answered = true
		shell:Hide()
	end)
	never:SetScript('OnClick', function()
		card.answered = true
		shell:Hide()
		Makeover:NotNow()
	end)
	-- Escape counts as "Not now", and so does a cinematic closing every window
	return card
end

---Show the card now. Falls back to a toast with the same choices when the window kit is missing.
function Makeover:Show()
	local title, text = self:Text()
	if not self.card then
		self.card = BuildCard()
	end
	local card = self.card
	self.shown = true
	if card then
		card.answered = false
		card.text:SetText(text)
		card.pick:SetText(self:PickLabel())
		-- "Got it" already closes the card for good
		if FindConflict() == SUITE then
			card.never:Hide()
		else
			card.never:Show()
		end
		card.shell:Show()
		return
	end
	local hub = LibAT and LibAT.Setup and LibAT.Setup.Hub
	if hub and hub.ShowToast then
		hub:ShowToast(title .. '. ' .. text, self:PickLabel(), function()
			Makeover:Pick()
		end, {
			duration = 30,
			onDismiss = function()
				Makeover:Dismiss()
			end,
		})
		return
	end
	-- Nothing else can show it: say it once, with the way back to the styles
	Print(title .. '. ' .. text)
	self:Dismiss()
end

---Try to show the card: never in combat, during a cinematic or over the setup window. Retries for
---a while, then waits for the next login.
function Makeover:Try()
	if self.shown or not self:Due() then
		return
	end
	if self:Blocked() then
		self.tries = self.tries + 1
		if self.tries < 30 then
			self:Schedule(10)
		end
		return
	end
	local ok, err = pcall(self.Show, self)
	if not ok then
		P.log.error("The nameplate What's new card failed: " .. tostring(err))
	end
end

---@param delay number seconds
function Makeover:Schedule(delay)
	if C_Timer and C_Timer.After then
		C_Timer.After(delay, function()
			Makeover:Try()
		end)
	end
end

----------------------------------------------------------------------------------------------------
-- Profiles (6.10)
----------------------------------------------------------------------------------------------------

---The nameplate profile follows SpartanUI's profile name, copies, resets and deletes while
---"Follow my SpartanUI profile" is on. Database callbacks only, so it runs whichever plates are
---in use; a profile that turns plates on starts the engine through MaybeStartEngine.
local function FollowHostProfiles()
	local hostDB = SUI.SpartanUIDB
	if not hostDB or not hostDB.RegisterCallback then
		return
	end
	local function Following()
		return P.db and P.db.profile.followHostProfile
	end
	hostDB.RegisterCallback(module, 'OnProfileChanged', function()
		if Following() then
			P.Store:FollowHostProfile()
			if platesActive then
				Makeover.shown = false
				Makeover:Schedule(3)
			end
		end
	end)
	hostDB.RegisterCallback(module, 'OnProfileCopied', function(_, _, sourceKey)
		if Following() and sourceKey and P.db.profiles and P.db.profiles[sourceKey] then
			pcall(P.db.CopyProfile, P.db, sourceKey, true)
		end
	end)
	hostDB.RegisterCallback(module, 'OnProfileReset', function()
		if Following() then
			pcall(P.db.ResetProfile, P.db)
		end
	end)
	hostDB.RegisterCallback(module, 'OnProfileDeleted', function(_, _, key)
		if Following() and key and P.db.profiles and P.db.profiles[key] and P.db:GetCurrentProfile() ~= key then
			pcall(P.db.DeleteProfile, P.db, key, true)
		end
	end)
end

---The current nameplate profile and the saved styles it uses, for the full-profile export.
---@return table|nil
local function ExportProfile()
	local db = P.db
	if not db then
		return nil
	end
	local profile = {}
	for key, value in pairs(db.profile) do
		if key ~= 'migratedFromOld' then
			profile[key] = Copy(value)
		end
	end
	local used = {}
	if type(profile.style) == 'string' then
		used[profile.style] = true
	end
	for _, id in pairs(type(profile.assign) == 'table' and profile.assign or {}) do
		if type(id) == 'string' then
			used[id] = true
		end
	end
	for _, entry in ipairs(type(profile.when) == 'table' and profile.when or {}) do
		if type(entry) == 'table' and type(entry.style) == 'string' then
			used[entry.style] = true
		end
	end
	local styles = {}
	local saved = type(db.global.styles) == 'table' and db.global.styles or {}
	for id in pairs(used) do
		if type(saved[id]) == 'table' then
			styles[id] = Copy(saved[id])
		end
	end
	return { format = EXPORT_FORMAT, version = 1, profile = profile, styles = styles }
end

---Replace the current nameplate profile with exported data. Saved styles the data brings are added
---(a style already in the library is kept as it is).
---@param data table
---@return boolean ok
---@return string|nil reason
local function ImportProfile(data)
	local db = P.db
	if not db then
		return false, 'Nameplates are not loaded'
	end
	if type(data) ~= 'table' or data.format ~= EXPORT_FORMAT or type(data.profile) ~= 'table' then
		return false, 'This is not nameplate data'
	end
	if (tonumber(data.profile.schema) or 0) > P.Config.SCHEMA.profile then
		return false, 'These nameplate settings come from a newer version of SpartanUI'
	end
	-- The same checks as a pasted share string: styles are validated, the profile keeps only known
	-- keys with values of the right type
	local Exchange = P.Exchange
	if not (Exchange and Exchange.CleanProfile) then
		return false, 'Nameplates are not loaded'
	end
	local okClean, cleaned = pcall(Exchange.CleanProfile, Exchange, { profile = data.profile, styles = data.styles })
	if not okClean or type(cleaned) ~= 'table' then
		return false, 'This is not nameplate data'
	end
	local added = false
	for id, entry in pairs(cleaned.styles) do
		if P.Store:Get({ 'styles', id }, 'global') == nil then
			local raw = type(data.styles) == 'table' and data.styles[id]
			local source = entry.source
			if type(raw) == 'table' and type(raw.source) == 'table' and raw.source.kind == 'copy' then
				source = { kind = 'copy' }
			end
			local base = Copy(entry.base)
			base.id, base.name = id, entry.name
			P.Store:Set({ 'styles', id }, { name = entry.name, schema = P.Styles.Schema.CURRENT, base = base, source = source }, 'global')
			added = true
		end
	end
	local profile = db.profile
	local keys = {}
	for key in pairs(profile) do
		keys[#keys + 1] = key
	end
	for _, key in ipairs(keys) do
		rawset(profile, key, nil)
	end
	for key, value in pairs(cleaned.profile) do
		profile[key] = Copy(value)
	end
	-- A backup of the player's own profile also brings their role and game settings back
	if Exchange.CleanOwnSettings then
		for key, value in pairs(Exchange:CleanOwnSettings(data.profile)) do
			profile[key] = Copy(value)
		end
	end
	-- This profile's own switches come from the backup too, when they are plain switches
	for _, key in ipairs({ 'enabled', 'followHostProfile' }) do
		if type(data.profile[key]) == 'boolean' then
			profile[key] = data.profile[key]
		end
	end
	if type(data.profile.schema) == 'number' then
		profile.schema = data.profile.schema
	end
	-- Never bring the old plates' settings over this profile, even after a reset
	profile.migratedFromOld = true
	local done = type(db.global.migratedFromOld) == 'table' and db.global.migratedFromOld or {}
	done[db:GetCurrentProfile()] = true
	db.global.migratedFromOld = done
	P.Migrate:RunProfile()
	P.Store:ProfileSwapped(P.ALL_REASONS)
	if added then
		P:Fire('STYLES_CHANGED')
	end
	return true
end

---"SpartanUI (Full Profile)" gets exactly one nameplate component, and the old plates' namespace
---(kept so its settings can still be brought over) stays out of exports. Runs before the profile
---handler enables.
local function JoinProfileTools()
	local profiles = SUI:GetModule('Handler.Profiles', true)
	if type(profiles) ~= 'table' then
		return
	end
	if type(profiles.compositeComponents) == 'table' then
		local present = false
		for _, component in ipairs(profiles.compositeComponents) do
			if type(component) == 'table' and component.id == COMPONENT_ID then
				present = true
			end
		end
		if not present then
			profiles.compositeComponents[#profiles.compositeComponents + 1] = {
				id = COMPONENT_ID,
				displayName = L['Nameplates'],
				isAvailable = function()
					return P.db ~= nil
				end,
				export = ExportProfile,
				import = ImportProfile,
			}
		end
	end
	if type(profiles.hiddenNamespaces) == 'table' then
		profiles.hiddenNamespaces.Nameplates = true
	end
end
module.ExportProfile = ExportProfile
module.ImportProfile = ImportProfile

---The nameplate database as its own entry in the profile manager.
local function RegisterProfileManager()
	local manager = LibAT and LibAT.ProfileManager
	if module.profileManagerAdded or not (manager and manager.RegisterAddon and P.db) then
		return
	end
	module.profileManagerAdded = true
	local ok, err = pcall(manager.RegisterAddon, manager, {
		id = PROFILE_ADDON_ID,
		name = 'SpartanUI ' .. L['Nameplates'],
		db = P.db,
		icon = 'Interface\\AddOns\\SpartanUI\\images\\Spartan-Helm',
	})
	if not ok then
		P.log.warning('The profile manager did not take the nameplate profiles: ' .. tostring(err))
	end
end

----------------------------------------------------------------------------------------------------
-- Setup (3.1)
----------------------------------------------------------------------------------------------------

local function SetupStepHidden()
	if SUI:IsModuleDisabled('Nameplates') then
		return true
	end
	-- A copied or shared profile brings its own nameplate settings
	if SUI.Setup and SUI.Setup.IsStartingFresh and not SUI.Setup:IsStartingFresh() then
		return true
	end
	return false
end

---Under the look step while another nameplate addon draws the plates. The pick is saved either way
---and starts working once the other plates are off: the Conflicts step turns an addon off (setup
---reloads the screen at the end), ElvUI's nameplates can only be turned off in its own settings.
---@return table|nil
local function SetupBanner()
	local folder = EnabledConflict()
	if folder then
		return {
			title = string.format(L['%s draws your nameplates now'], AddonTitle(folder)),
			text = L['Turn it off on the Conflicts step. Your pick starts when setup reloads your screen.'],
			step = 'conflicts',
		}
	end
	if SuitePlatesOn(SUITE) then
		return {
			title = string.format(L['%s draws your nameplates now'], AddonTitle(SUITE)),
			text = L['Turn its nameplates off in its own settings, then reload. Your pick starts after that.'],
		}
	end
	return nil
end

---Add the core's look step to SpartanUI's setup, next to the other look steps (after the unit
---frames step, whose "How do you play?" answer gives the role).
local function AddSetupStep()
	if module.setupStepAdded or not P.host.AddSetupSteps then
		return
	end
	module.setupStepAdded = true
	local steps = P:GetSetupSteps()
	for _, step in ipairs(steps) do
		step.order = SETUP_ORDER
		step.chapter = L['Look']
		step.hidden = SetupStepHidden
		step.banner = SetupBanner
	end
	P.host.AddSetupSteps(steps)
end

---The Done page links (3.1): "Change what shows" and "Give the game back its settings". While
---another nameplate addon draws the plates there is no settings page to open, so only the second
---link is added: the setup step has still saved its choices, and this undoes them.
---@param restoreOnly? boolean
local function AddFinishLinks(restoreOnly)
	local reg = SUI.Setup and SUI.Setup.registration
	local config = type(reg) == 'table' and rawget(reg, 'config')
	local finish = type(config) == 'table' and config.finish
	if module.finishLinksAdded or type(finish) ~= 'table' then
		return
	end
	module.finishLinksAdded = true
	finish.links = finish.links or {}
	if not restoreOnly then
		table.insert(finish.links, {
			title = L['Change what shows'],
			caption = L['The parts on your nameplates and where they sit'],
			onClick = function()
				SUI.Options:OpenTo({ 'Nameplates', 'customize' })
			end,
		})
	end
	table.insert(finish.links, {
		title = L['Give the game back its settings'],
		caption = L['Undo the game settings your nameplates changed'],
		action = L['Undo'],
		onClick = function()
			if P.SetupSteps:RestoreGame() then
				Print(L['The game has its nameplate settings back.'])
			else
				Print(L['The game gets its nameplate settings back when combat ends.'])
			end
		end,
	})
end

----------------------------------------------------------------------------------------------------
-- Options (Decision 13: a top-level entry)
----------------------------------------------------------------------------------------------------

---Root settings that belong to the launch: plates off for this profile.
---@param tbl table
local function AddLaunchControls(tbl)
	tbl.args = tbl.args or {}
	local function On()
		return P.Store:Get('enabled') ~= false
	end
	local status = {
		type = 'description',
		order = 0.1,
		fontSize = 'medium',
		name = L['Nameplates are off for this profile, so the game draws its own.'],
		hidden = On,
	}
	local turnOn = {
		type = 'execute',
		order = 0.2,
		primary = true,
		name = L['Turn on nameplates'],
		desc = L['Use these nameplates on this profile. Pick a style on the Style page.'],
		hidden = On,
		func = function()
			P.Migrate:FinishMakeover()
			P.Store:Set('enabled', true)
		end,
	}
	tbl.args.plateStatus = status
	tbl.args.turnOn = turnOn
	-- The Style page says it too: a player who opens it from the sidebar would otherwise pick
	-- styles that change nothing in the world
	local stylePage = type(tbl.args.style) == 'table' and tbl.args.style
	if stylePage and type(stylePage.args) == 'table' then
		stylePage.args.plateStatus = P.util.Copy(status)
		stylePage.args.plateStatus.hidden = On
		stylePage.args.turnOn = P.util.Copy(turnOn)
		stylePage.args.turnOn.hidden = On
		stylePage.args.turnOn.func = turnOn.func
	end
end

---@return table
local function BuildOptions()
	local tbl = P:BuildOptionsTable()
	tbl.order = 4.5
	AddLaunchControls(tbl)
	return tbl
end

---"Show all parts" draws boxes on the plates in the world. It is a look-around switch, so it goes
---back off when the settings window closes (the Stage calls Close on every provider then).
---@param provider table
local function ResetShowAllOnClose(provider)
	local close = provider.Close
	provider.Close = function(...)
		local regions = P.Regions
		if regions and regions.SetShowAll then
			regions:SetShowAll(false)
		end
		if close then
			return close(...)
		end
	end
end

local function RegisterOptions()
	if module.optionsAdded then
		return
	end
	module.optionsAdded = true
	SUI.Options:AddOptions(BuildOptions(), 'Nameplates', 'Root')
	local provider = P:BuildPreviewProvider()
	if provider and SUI.OptionsWindow and SUI.OptionsWindow.Stage then
		ResetShowAllOnClose(provider)
		SUI.OptionsWindow.Stage:Register(provider)
	end
end

----------------------------------------------------------------------------------------------------
-- /sui np
----------------------------------------------------------------------------------------------------

-- BEGIN probe command (Phase 0b developer probe, UI/Probe.lua). Hidden from players: it is not in
-- the help line below or in the command's argument list. Safe when a build leaves the file out.
---/sui np probe [watch [seconds] [touch] | stop | report | clear]
---@param rest string|nil
local function ProbeCommand(rest)
	local probe = P.Probe
	if not probe then
		Print('The nameplate probe is not part of this build.')
		return
	end
	local ok, message = pcall(probe.Command, probe, rest)
	if not ok then
		P.log.error('Nameplate probe failed: ' .. tostring(message))
		message = 'The nameplate probe hit an error. See the log.'
	end
	if message then
		Print(message)
	end
end
-- END probe command

---/sui np <command>: give the game its settings back, capability tools.
---@param args string|nil
local function Command(args)
	local cmd, rest = strsplit(' ', args or '', 2)
	cmd = cmd and cmd:lower() or ''
	if cmd == 'restore' then
		if P.CVars:RestoreAll() then
			Print(L['The game has its nameplate settings back.'])
		else
			Print(L['The game gets its nameplate settings back when combat ends.'])
		end
	elseif cmd == 'caps' then
		for name, value in pairs(P.Caps:Snapshot()) do
			P.log.info(name .. ' = ' .. tostring(value))
		end
		Print(L['What this version of WoW can do was written to the log.'])
	elseif cmd == 'cap' and rest then
		local name, value = strsplit(' ', rest, 2)
		local setting = nil
		if value == 'on' then
			setting = true
		elseif value == 'off' then
			setting = false
		end
		P.Caps:SetOverride(name, setting)
		Print(L['Saved. Reload to use it.'])
	-- BEGIN probe command dispatch
	elseif cmd == 'probe' then
		ProbeCommand(rest)
	-- END probe command dispatch
	else
		Print('/sui np restore, /sui np caps, /sui np cap <name> on|off|clear')
	end
end

----------------------------------------------------------------------------------------------------
-- Host configuration (6.11) and lifecycle
----------------------------------------------------------------------------------------------------

---Open the settings window on a nameplate page, optionally scrolled to a control. The window only
---scrolls to real controls, never to an inline group's own key, so a control inside an inline group
---comes as a path: the groups first, the control last (for example { 'export', 'exportText' }).
---@param page? string
---@param optionKey? string|string[]
local function OpenOptionsAt(page, optionKey)
	local path = page and { 'Nameplates', page } or { 'Nameplates' }
	local key = optionKey
	if type(optionKey) == 'table' then
		for i = 1, #optionKey - 1 do
			path[#path + 1] = optionKey[i]
		end
		key = optionKey[#optionKey]
	end
	SUI.Options:OpenTo(path, key)
end
module.OpenOptionsAt = OpenOptionsAt

---@return Plates.HostConfig
local function HostConfig()
	return {
		name = 'SpartanUI',
		savedVariable = 'SpartanUINameplatesDB',
		mediaPath = 'Interface\\AddOns\\SpartanUI\\Modules\\Nameplates\\Media\\',
		logger = SUI.logger and SUI.logger:RegisterCategory('Nameplates') or nil,
		media = SUI.Lib and SUI.Lib.LSM or nil,
		AddOptions = function(tbl)
			SUI.Options:AddOptions(tbl, 'Nameplates', 'Root')
		end,
		OptionsPath = function(page)
			if page then
				return { 'Nameplates', page }
			end
			return { 'Nameplates' }
		end,
		OpenOptions = OpenOptionsAt,
		AddSetupSteps = function(steps)
			local reg = SUI.Setup and SUI.Setup.registration
			if not reg then
				return
			end
			for _, step in ipairs(steps) do
				reg:AddStep(step)
			end
		end,
		GetSetupRole = function()
			local UF = SUI.UF
			if type(UF) ~= 'table' or type(UF.GetSetupRole) ~= 'function' then
				return nil
			end
			return SETUP_ROLES[UF:GetSetupRole()]
		end,
		RegisterCommand = function(name, fn, description)
			SUI:AddChatCommand(name, fn, description, nil, true)
		end,
		RegisterPreview = function(provider)
			if SUI.OptionsWindow and SUI.OptionsWindow.Stage then
				ResetShowAllOnClose(provider)
				SUI.OptionsWindow.Stage:Register(provider)
			end
		end,
		-- Redraws only the preview panel, so a hovered card or a scene change never rebuilds the
		-- settings under the mouse
		RedrawPreview = function()
			local Stage = SUI.OptionsWindow and SUI.OptionsWindow.Stage
			if Stage and Stage.MarkDirty then
				Stage:MarkDirty()
			end
		end,
		ImportLegacy = ImportLegacy,
		RefreshOptions = function(rebuild)
			if not module.optionsAdded then
				return
			end
			if rebuild and SUI.opt and SUI.opt.args then
				SUI.opt.args.Nameplates = BuildOptions()
			end
			local registry = LibStub and LibStub('AceConfigRegistry-3.0', true)
			if registry then
				registry:NotifyChange(OPTIONS_APP)
			end
		end,
		AddSearchWords = function(words)
			local options = LibAT and LibAT.UI and LibAT.UI.Options
			local search = options and options.Search
			local caps = LibAT and LibAT.Capabilities
			local revision = type(caps) == 'table' and caps.searchSynonyms or nil
			if type(revision) == 'number' and revision >= SEARCH_SYNONYMS_REVISION and search and search.AddSynonyms then
				search:AddSynonyms(OPTIONS_APP, words)
			end
		end,
		GetHostLook = GetHostLook,
		GetHostProfileName = function()
			return SUI.SpartanUIDB and SUI.SpartanUIDB:GetCurrentProfile() or nil
		end,
		profileDefaults = { followHostProfile = true },
		widgets = { cardGrid = 'SUICardGrid' },
		widgetPrefix = 'SpartanUINameplates',
		conflicts = CONFLICTS,
	}
end

---The module runs the plates this session: looks, settings, Done page links, then (once logged in)
---the engine when the profile wants plates, and the What's new card.
local function ActivatePlates()
	if not platesActive then
		platesActive = true
		RefreshLook()
		InstallLookWatchers()
		RegisterOptions()
		AddFinishLinks()
	end
	WhenLoggedIn(function()
		loginDone = true
		if ProfileWantsPlates() then
			StartEngine()
		end
		Makeover:ResumeAfterReload()
		Makeover:Schedule(MAKEOVER_DELAY)
	end)
end

function module:OnInitialize()
	P:Initialize(HostConfig())
	JoinProfileTools()
	AddSetupStep()
	FollowHostProfiles()
	P:On('STORE_CHANGED', MaybeStartEngine, module)
	P:On('PROFILE_CHANGED', MaybeStartEngine, module)
end

local disabledAtLogin

function module:OnEnable()
	SUI:AddChatCommand('np', Command, 'Nameplate tools', { restore = 'Give the game back its nameplate settings' }, true)
	RegisterProfileManager()
	local wants, reason = HostWantsEngine()
	if not wants then
		platesActive = false
		P.log.info('The nameplates are not started: ' .. tostring(reason))
		RestoreLeftovers()
		-- SpartanUI does not disable listed modules at load, so AceAddon still ran this OnEnable and
		-- counts the module as on: the module list's toggle would then call an Enable() that does
		-- nothing until a reload. Mark it off so turning it on runs OnEnable again.
		if reason == 'disabled' then
			disabledAtLogin = true
			self:Disable()
			disabledAtLogin = nil
			return
		end
		-- Another nameplate addon: the card says what switching means
		if reason and reason:find('^conflict:') then
			-- Data only (no game events, hooks, settings or windows): setup's look step still offers
			-- "Match my look" and the War style, preselected, and its Done page can still hand the
			-- game its settings back
			RefreshLook()
			AddFinishLinks(true)
			WhenLoggedIn(function()
				Makeover:Schedule(MAKEOVER_DELAY)
			end)
		end
		return
	end
	ActivatePlates()
end

function module:OnDisable()
	platesActive = false
	-- Marking a module that was off at login as off: nothing ran, and leftovers were already restored
	if disabledAtLogin then
		return
	end
	if engineRunning then
		StopEngine()
		return
	end
	-- Turning the module off gives back anything an earlier session left behind
	RestoreLeftovers()
end
