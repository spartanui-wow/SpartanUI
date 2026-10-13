local _, ns = ...
local SUI = SUI
local P = ns.Plates
if not (SUI and P) then
	return
end
local L = SUI.L

-- SpartanUI host for the nameplate core. This is the only file in Modules/Nameplates that may
-- mention SpartanUI, its paths, strings, assets or commands. It is loaded from Modules/LoadAll.xml
-- right after the old Modules/Nameplates.lua (Decision 21).
--
-- Phase 4a (launch): the new plates are the default.
--   * Classic family and Forever: the old file has already created the 'Nameplates' module. The
--     host wraps its lifecycle. The new engine runs unless this character picked "Use the old
--     nameplates" (char.engine = 'old', read once per session, reload to switch); then the old
--     module runs exactly as before, for one more release.
--   * Retail: the old file returns before creating a module, so the host creates 'Nameplates'
--     itself and only the new engine can run.
--   * Either way the engine stays off while the module is turned off or another nameplate addon
--     is loaded (HostWantsEngine).
-- Who gets what (7.4) is decided per profile by ImportLegacy: a profile that used the old plates
-- switches to Clean with its old sizes; an existing Retail profile keeps the game's plates until
-- the player picks a style on the What's new card; a new profile gets setup's look step.
-- From Phase 4b, when the old file is gone, this file creates the module on every client.

-- Folder names of addons that also draw nameplates (7.4). Code data only; titles are read at
-- runtime. Two spellings of one folder are listed because its name is not confirmed.
local CONFLICTS = { 'Plater', 'TidyPlates_ThreatPlates', 'TidyPlates', 'NeatPlates', 'Kui_Nameplates', 'KuiNameplates', 'Platynator', 'EllesmereUINameplates' }

-- A UI suite whose nameplates count only while they are on. It is left out of ConflictsWith: the
-- setup conflicts step would turn the whole suite off for its nameplates.
local SUITE = 'ElvUI'

local HOST_STYLE_ID = 'spartanui'
local WAR_STYLE_ID = 'war'
local OPTIONS_APP = 'SpartanUI'
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

local module = SUI:GetModule('Nameplates', true)
if not module then
	module = SUI:NewModule('Nameplates')
	module.createdByHost = true
end
module.DisplayName = L['Nameplates']
module.description = 'Nameplates with ready-made styles and a live preview'
module.ConflictsWith = CONFLICTS
module.API = P.API

-- The old module runs on this client (Classic family and Forever, until Phase 4b)
local oldModuleHere = not module.createdByHost
local oldInitialize, oldEnable, oldDisable = module.OnInitialize, module.OnEnable, module.OnDisable
local engineRunning = false
local hooksInstalled = false

local function Print(text)
	if SUI.Print then
		SUI:Print(text)
	end
end

local function Copy(value)
	return P.util.Copy(value)
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

---A UI suite's nameplates count as a conflict only when they are on. When its setting cannot be
---read, assume they are on, so two plate engines never run together (S0).
---@param folder string
---@return boolean
local function SuitePlatesOn(folder)
	if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(folder)) then
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
		if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(folder) then
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

---This character's name for the game's addon list, from the profile keys ("Name - Realm").
---@return string|nil
local function CharacterName()
	local keys = SUI.SpartanUIDB and SUI.SpartanUIDB.keys
	local char = type(keys) == 'table' and keys.char
	if type(char) ~= 'string' then
		return nil
	end
	local name = char:match('^(.-) %- ') or char
	return name ~= '' and name or nil
end

----------------------------------------------------------------------------------------------------
-- Which plates run
----------------------------------------------------------------------------------------------------

---This character picked "Use the old nameplates" for this session.
---@return boolean
local function UsingOldPlates()
	return P.Config:GetSessionEngine() == 'old'
end

---The new plates are the default: they run unless the old ones were picked, the module is off, or
---another nameplate addon is loaded.
---@return boolean wants
---@return string|nil reason
local function HostWantsEngine()
	if UsingOldPlates() then
		return false, 'old'
	end
	if SUI:IsModuleDisabled('Nameplates') then
		return false, 'disabled'
	end
	local conflict = FindConflict()
	if conflict then
		return false, 'conflict:' .. conflict
	end
	return true
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

---The faction banner from the War theme's own nameplates block (a full texture path).
---@return string|nil
local function WarBanner()
	local registry = SUI.ThemeRegistry
	local data = registry and registry.GetData and registry:GetData('War')
	local block = type(data) == 'table' and data.nameplates
	local art = type(block) == 'table' and block.art
	local banner = type(art) == 'table' and art.banner
	return type(banner) == 'string' and banner or nil
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
	local banner = WarBanner()
	if banner then
		style.parts.banner = { order = 5, kind = 'art', art = banner, width = 164, height = 22, anchor = { 'CENTER', 'health', 'CENTER', 0, 0 }, color = { 1, 1, 1, 0.9 }, layer = -2 }
	end
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

---Theme, accent or font changed. Font:Refresh() calls itself once per module, so the push waits
---for the next frame and any number of calls in one frame become one. The theme may bring its own
---nameplate style, so "Match my look" is registered again first. Only the 'host' choice follows the
---theme: a player who picked another style keeps it.
local function PushLook()
	if not engineRunning then
		return
	end
	P.Scheduler:NextFrame('host.look', function()
		if engineRunning then
			RegisterHostStyle()
			P.API:SetHostLook(GetHostLook())
		end
	end)
end

----------------------------------------------------------------------------------------------------
-- Old saved settings (7)
----------------------------------------------------------------------------------------------------

---The old module's effective defaults on this client, without AceDB wildcards: its own registered
---defaults when it is loaded, else the values it used.
---@return table
local function OldDefaults()
	local database = rawget(module, 'Database')
	local defaults = type(database) == 'table' and type(database.defaults) == 'table' and database.defaults.profile
	if type(defaults) == 'table' and type(defaults.elements) == 'table' then
		local out = {}
		for key, value in pairs(defaults) do
			if key ~= 'elements' then
				out[key] = Copy(value)
			end
		end
		local wild = type(defaults.elements['**']) == 'table' and defaults.elements['**'] or {}
		local elements = {}
		for name, spec in pairs(defaults.elements) do
			if name ~= '**' and type(spec) == 'table' then
				local merged = Copy(wild)
				for key, value in pairs(spec) do
					merged[key] = Copy(value)
				end
				elements[name] = merged
			end
		end
		out.elements = elements
		return out
	end
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
			PvPRoleIndicator = { enabled = true },
		},
	}
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
---@param profileKey string
---@return table|nil
local function ImportLegacy(profileKey)
	-- A character that turned the new plates on while they were being tested keeps what it has
	if P.Config:GetEngineChoice() == 'new' then
		return nil
	end
	-- A brand-new profile: setup asks instead
	if not HostProfileSetUp(profileKey) then
		return nil
	end
	-- Retail never had SpartanUI plates: they stay off until the player picks a style
	if not oldModuleHere then
		return { action = 'off' }
	end
	local saved = rawget(_G, 'SpartanUIDB')
	local namespaces = type(saved) == 'table' and rawget(saved, 'namespaces')
	local namespace = type(namespaces) == 'table' and rawget(namespaces, 'Nameplates')
	local profiles = type(namespace) == 'table' and rawget(namespace, 'profiles')
	local settings = type(profiles) == 'table' and rawget(profiles, profileKey)
	return { action = 'import', settings = type(settings) == 'table' and settings or {}, defaults = OldDefaults() }
end

----------------------------------------------------------------------------------------------------
-- Switching between the old and the new plates
----------------------------------------------------------------------------------------------------

local function StopEngine()
	if engineRunning then
		engineRunning = false
		P:Disable()
	end
end

---"Use the old nameplates" (this character, after a reload). Turning the old ones on gives the game
---its settings back right away and stops the new plates, so nothing they set stays behind.
---@param old boolean
local function SetOldPlates(old)
	P.Config:SetEngineChoice(old and 'old' or 'new')
	if old then
		StopEngine()
		P.CVars:RestoreAll()
		Print(L['The old nameplates come back after you reload. Type /rl to reload now.'])
	else
		Print(L['The new nameplates turn on after you reload. Type /rl to reload now.'])
	end
end

----------------------------------------------------------------------------------------------------
-- What's new card (3.1): "Your nameplates got a makeover"
----------------------------------------------------------------------------------------------------

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

---The card is due for the current profile.
---@return boolean
function Makeover:Due()
	local state = P.Migrate:MakeoverState()
	if state ~= 'import' and state ~= 'off' then
		return false
	end
	if UsingOldPlates() or SUI:IsModuleDisabled('Nameplates') then
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
		lines[#lines + 1] = L['From now on, setup asks before another addon draws your nameplates.']
	end
	return L['Your nameplates got a makeover'], table.concat(lines, '\n\n')
end

---"Not now": the card does not come back for this profile. Plates that were off stay off.
function Makeover:NotNow()
	P.Migrate:FinishMakeover()
end

---"Pick a style": plates on for this profile and the style page opens. Another nameplate addon is
---turned off for this character first, then the screen reloads.
function Makeover:Pick()
	P.Migrate:FinishMakeover()
	P.Store:Set('enabled', true)
	local conflict = FindConflict()
	if conflict and conflict ~= SUITE then
		local character = CharacterName()
		if character and C_AddOns and C_AddOns.DisableAddOn then
			for _, folder in ipairs(CONFLICTS) do
				if C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(folder) then
					C_AddOns.DisableAddOn(folder, character)
				end
			end
			-- Saved now, so the game's addon list cannot throw the change away
			if C_AddOns.SaveAddOns then
				C_AddOns.SaveAddOns()
			end
			if ReloadUI then
				ReloadUI()
			end
		end
		return
	end
	if conflict == SUITE then
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
		pcall(Kit.CreateShell, Kit, { name = 'SUI_NameplatesMakeover', title = L['Your nameplates got a makeover'], width = 440, height = 210, crest = false, titleFrame = true, close = false })
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
	local pick = Kit:CreateButton(body, L['Pick a style'], 'primary', 150)
	pick:SetPoint('BOTTOMRIGHT', body, 'BOTTOMRIGHT', -16, 14)
	local later = Kit:CreateButton(body, L['Not now'], 'secondary', 110)
	later:SetPoint('RIGHT', pick, 'LEFT', -8, 0)
	pick:SetScript('OnClick', function()
		card.answered = true
		shell:Hide()
		Makeover:Pick()
	end)
	later:SetScript('OnClick', function()
		card.answered = true
		shell:Hide()
		Makeover:NotNow()
	end)
	-- Escape counts as "Not now", but a cinematic closing every window does not
	shell:HookScript('OnHide', function()
		if not card.answered and not CinematicPlaying() then
			card.answered = true
			Makeover:NotNow()
		end
	end)
	return card
end

---Show the card now. Falls back to a toast with the same choice when the window kit is missing.
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
		card.shell:Show()
		return
	end
	local hub = LibAT and LibAT.Setup and LibAT.Setup.Hub
	if hub and hub.ShowToast then
		hub:ShowToast(title .. '. ' .. text, L['Pick a style'], function()
			Makeover:Pick()
		end, { duration = 30 })
		return
	end
	Print(title .. '. ' .. text)
end

---Try to show the card: never in combat, during a cinematic or over the setup window. Retries for
---a while, then waits for the next login.
function Makeover:Try()
	if self.shown or not engineRunning or not self:Due() then
		return
	end
	local hub = LibAT and LibAT.Setup and LibAT.Setup.Hub
	local setupOpen = false
	if hub and type(hub.IsShown) == 'function' then
		local ok, shown = pcall(hub.IsShown, hub)
		setupOpen = ok and shown == true
	end
	if (InCombatLockdown and InCombatLockdown()) or CinematicPlaying() or setupOpen then
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

local function FollowHostProfiles()
	local hostDB = SUI.SpartanUIDB
	if not hostDB or not hostDB.RegisterCallback then
		return
	end
	local function Following()
		return engineRunning and P.db and P.db.profile.followHostProfile
	end
	hostDB.RegisterCallback(module, 'OnProfileChanged', function()
		if Following() then
			P.Store:FollowHostProfile()
			Makeover.shown = false
			Makeover:Schedule(3)
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
	local added = false
	for id, entry in pairs(type(data.styles) == 'table' and data.styles or {}) do
		if type(id) == 'string' and type(entry) == 'table' and P.Store:Get({ 'styles', id }, 'global') == nil then
			P.Store:Set({ 'styles', id }, entry, 'global')
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
	for key, value in pairs(data.profile) do
		profile[key] = Copy(value)
	end
	profile.migratedFromOld = true
	P.Migrate:RunProfile()
	P.Store:ProfileSwapped(P.ALL_REASONS)
	if added then
		P:Fire('STYLES_CHANGED')
	end
	return true
end

---"SpartanUI (Full Profile)" gets exactly one nameplate component, and the old module's namespace
---leaves exports once these plates are in use. Runs before the profile handler enables.
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
	if type(profiles.hiddenNamespaces) == 'table' and not UsingOldPlates() then
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
	if UsingOldPlates() or SUI:IsModuleDisabled('Nameplates') then
		return true
	end
	-- A copied or shared profile brings its own nameplate settings
	if SUI.Setup and SUI.Setup.IsStartingFresh and not SUI.Setup:IsStartingFresh() then
		return true
	end
	return false
end

local function SetupBanner()
	local folder = EnabledConflict()
	if not folder then
		return nil
	end
	return {
		title = string.format(L['%s draws your nameplates now'], AddonTitle(folder)),
		text = L['Your pick is used once you turn it off on the Conflicts step.'],
		step = 'conflicts',
	}
end

---Add the core's look step to SpartanUI's setup, next to the other look steps.
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

---The Done page links (3.1): "Change what shows" and "Give the game back its settings".
local function AddFinishLinks()
	local reg = SUI.Setup and SUI.Setup.registration
	local config = type(reg) == 'table' and rawget(reg, 'config')
	local finish = type(config) == 'table' and config.finish
	if module.finishLinksAdded or type(finish) ~= 'table' then
		return
	end
	module.finishLinksAdded = true
	finish.links = finish.links or {}
	table.insert(finish.links, {
		title = L['Change what shows'],
		caption = L['The parts on your nameplates and where they sit'],
		onClick = function()
			SUI.Options:OpenTo({ 'Nameplates', 'customize' })
		end,
	})
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

---Root settings that belong to the launch: plates off for this profile, and the old plates.
---@param tbl table
local function AddLaunchControls(tbl)
	tbl.args = tbl.args or {}
	local function On()
		return P.Store:Get('enabled') ~= false
	end
	tbl.args.plateStatus = {
		type = 'description',
		order = 0.1,
		fontSize = 'medium',
		name = L['Nameplates are off for this profile, so the game draws its own.'],
		hidden = On,
	}
	tbl.args.turnOn = {
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
	if oldModuleHere then
		tbl.args.useOldPlates = {
			type = 'toggle',
			order = 0.9,
			width = 'full',
			name = L['Use the old nameplates'],
			desc = L['Go back to the nameplates from before this update, for this character. They will be removed in a later update. You need to reload.'],
			get = function()
				return P.Config:GetEngineChoice() == 'old'
			end,
			set = function(_, value)
				SetOldPlates(value and true or false)
			end,
		}
	end
end

---@return table
local function BuildOptions()
	local tbl = P:BuildOptionsTable()
	tbl.order = 4.5
	AddLaunchControls(tbl)
	return tbl
end

local function RegisterOptions()
	if module.optionsAdded then
		return
	end
	module.optionsAdded = true
	SUI.Options:AddOptions(BuildOptions(), 'Nameplates', 'Root')
	local provider = P:BuildPreviewProvider()
	if provider and SUI.OptionsWindow and SUI.OptionsWindow.Stage then
		SUI.OptionsWindow.Stage:Register(provider)
	end
end

---With the old plates in use, their settings page offers the way back.
local function OfferNewPlates()
	local opt = rawget(SUI, 'opt')
	local modules = type(opt) == 'table' and type(opt.args) == 'table' and opt.args.Modules
	local group = type(modules) == 'table' and type(modules.args) == 'table' and modules.args.Nameplates
	if type(group) ~= 'table' then
		return
	end
	group.args = type(group.args) == 'table' and group.args or {}
	group.args.useNewPlates = {
		type = 'execute',
		order = 0.5,
		width = 'full',
		name = L['Use the new nameplates'],
		desc = L['Ready-made styles, a live preview and more. You need to reload.'],
		func = function()
			SetOldPlates(false)
		end,
	}
end

----------------------------------------------------------------------------------------------------
-- Engine start
----------------------------------------------------------------------------------------------------

local function InstallHostHooks()
	if hooksInstalled then
		return
	end
	hooksInstalled = true
	if SUI.Event and SUI.Event.RegisterEvent then
		SUI.Event:RegisterEvent('ARTWORK_STYLE_CHANGED', PushLook)
	end
	if SUI.UI and SUI.UI.Style and SUI.UI.Style.OnAccentChanged then
		SUI.UI.Style:OnAccentChanged(module, PushLook)
	end
	if SUI.Font and SUI.Font.Refresh then
		hooksecurefunc(SUI.Font, 'Refresh', PushLook)
	end
	FollowHostProfiles()
end

local function StartEngine()
	if engineRunning then
		return
	end
	engineRunning = true
	InstallHostHooks()
	RegisterHostStyle()
	P.API:SetHostLook(GetHostLook())
	P:Enable()
	AddFinishLinks()
	Makeover:Schedule(MAKEOVER_DELAY)
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

---/sui np <command>: switch between the new and old plates (developers), give the game its
---settings back, capability tools.
---@param args string|nil
local function Command(args)
	local cmd, rest = strsplit(' ', args or '', 2)
	cmd = cmd and cmd:lower() or ''
	if cmd == 'preview' then
		SetOldPlates(P.Config:GetEngineChoice() ~= 'old')
	elseif cmd == 'restore' then
		if P.CVars:RestoreAll() then
			Print(L['The game has its nameplate settings back.'])
		else
			Print(L['The game gets its nameplate settings back when combat ends.'])
		end
	elseif cmd == 'caps' then
		for name, value in pairs(P.Caps:Snapshot()) do
			P.log.info(name .. ' = ' .. tostring(value))
		end
		Print(L['Capabilities were written to the log.'])
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
		Print('/sui np preview, /sui np restore, /sui np caps, /sui np cap <name> on|off|clear')
	end
end

----------------------------------------------------------------------------------------------------
-- Host configuration (6.11) and lifecycle
----------------------------------------------------------------------------------------------------

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
		OpenOptions = function(page, optionKey)
			SUI.Options:OpenTo(page and { 'Nameplates', page } or { 'Nameplates' }, optionKey)
		end,
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
				SUI.OptionsWindow.Stage:Register(provider)
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
			if search and search.AddSynonyms then
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

function module:OnInitialize()
	if oldInitialize then
		oldInitialize(self)
	end
	P:Initialize(HostConfig())
	JoinProfileTools()
	AddSetupStep()
end

function module:OnEnable()
	SUI:AddChatCommand('np', Command, 'Nameplate tools', { preview = 'Switch this character between the new and the old nameplates (reload needed)' }, true)
	RegisterProfileManager()
	local wants, reason = HostWantsEngine()
	if not wants then
		if reason and reason ~= 'old' then
			P.log.info('The new nameplates are not started: ' .. reason)
		end
		-- Anything a session that ended badly left behind goes back to the game
		local db = P.db
		if db and (next(db.global.cvarBackup or {}) or next(db.char.cvarBackup or {})) then
			P.CVars:RestoreAll()
		end
		if oldEnable then
			oldEnable(self)
			if reason == 'old' then
				OfferNewPlates()
			end
		end
		return
	end
	RegisterOptions()
	WhenLoggedIn(StartEngine)
end

function module:OnDisable()
	if engineRunning then
		StopEngine()
		return
	end
	-- The old module's OnDisable assumes its own options exist
	if oldDisable and SUI.opt and SUI.opt.args.Modules and SUI.opt.args.Modules.args.Nameplates then
		oldDisable(self)
	end
end
