local _, ns = ...
local SUI = SUI
local P = ns.Plates
if not (SUI and P) then
	return
end
local L = SUI.L

-- SpartanUI host for the nameplate core. This is the only file in Modules/Nameplates that may
-- mention SpartanUI, its paths, strings, assets or commands. It is loaded from Modules/LoadAll.xml
-- right after the old Modules/Nameplates.lua, so during Phases 2 to 4a it attaches to the old
-- module (Decision 21):
--   * Classic family and Forever: the old file has already created the 'Nameplates' module. The
--     host wraps its lifecycle: with the tester switch on (char.engine = 'new', read once per
--     session, changed with /sui np preview and a reload) the new engine starts instead of the
--     old SpawnNamePlates; otherwise the old module runs exactly as before.
--   * Retail: the old file returns before creating a module, so there is nothing to collide with;
--     the host creates 'Nameplates' itself, hidden from the module list, and only the new engine
--     can run there (behind the same switch).
-- From Phase 4b, when the old file is gone, this file creates the module on every client.
-- Options are registered as a top-level entry (Decision 13) only while the new engine runs.

-- Folder names of addons that also draw nameplates (7.4). Code data only; titles are read at
-- runtime. Not set as module.ConflictsWith until Phase 4a, so the setup conflicts step does not
-- change for players who are not testing.
local CONFLICTS = { 'Plater', 'TidyPlates_ThreatPlates', 'TidyPlates', 'NeatPlates', 'Kui_Nameplates', 'Platynator', 'EllesmereUINameplates' }

local SUITE = 'ElvUI'

local HOST_STYLE_ID = 'spartanui'
local OPTIONS_APP = 'SpartanUI'

local module = SUI:GetModule('Nameplates', true)
if not module then
	module = SUI:NewModule('Nameplates')
	module.DisplayName = L['Nameplates']
	module.description = 'New nameplates (testing)'
	module.HideModule = true
	module.createdByHost = true
end
module.API = P.API

local oldInitialize, oldEnable, oldDisable = module.OnInitialize, module.OnEnable, module.OnDisable
local engineRunning = false
local hooksInstalled = false

local function Print(text)
	if SUI.Print then
		SUI:Print(text)
	end
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

---The tester switch is on, the module is on, and no other nameplate addon is loaded.
---@return boolean wants
---@return string|nil reason
local function HostWantsEngine()
	if P.Config:GetSessionEngine() ~= 'new' then
		return false, 'switch'
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

---Theme look for "Match my look": the theme's optional `nameplates` block plus accent and font.
---@return Plates.HostLook
local function GetHostLook()
	local block
	if SUI.ThemeRegistry and SUI.GetActiveStyle then
		local data = SUI.ThemeRegistry:GetData(SUI:GetActiveStyle())
		block = data and data.nameplates
	end
	block = type(block) == 'table' and block or {}
	local r, g, b = 1, 0.82, 0
	if SUI.UI and SUI.UI.Style and SUI.UI.Style.GetAccent then
		r, g, b = SUI.UI.Style:GetAccent()
	end
	local font = SUI.Font and SUI.Font.GetFont and SUI.Font:GetFont('Nameplates') or nil
	local tokens = P.util.Copy(block.tokens or {})
	tokens.accent = tokens.accent or { r, g, b, 1 }
	tokens.font = tokens.font or font
	return { style = block.style, tokens = tokens, art = P.util.Copy(block.art or {}), accent = { r, g, b, 1 }, font = font }
end

---"Match my look": the theme's inline style, or Clean drawn with the theme's tokens.
local function RegisterHostStyle()
	local look = GetHostLook()
	local style
	if type(look.style) == 'table' then
		style = P.util.Copy(look.style)
	else
		local base = P.Styles.Registry:Get(type(look.style) == 'string' and look.style or 'clean') or P.Styles.Registry:Get('clean')
		style = P.util.Copy(base)
		style.tokens = { accent = '$host', font = '$host', bar = '$host', ink = '$host', shade = '$host' }
	end
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
---nameplate style, so "Match my look" is registered again first.
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

local function RegisterOptions()
	if module.optionsAdded then
		return
	end
	module.optionsAdded = true
	local tbl = P:BuildOptionsTable()
	tbl.order = 4.5
	SUI.Options:AddOptions(tbl, 'Nameplates', 'Root')
	local provider = P:BuildPreviewProvider()
	if provider and SUI.OptionsWindow and SUI.OptionsWindow.Stage then
		SUI.OptionsWindow.Stage:Register(provider)
	end
end

local function SwitchText(on)
	if on then
		return L['The new nameplates turn on after you reload. Type /rl to reload now.']
	end
	return L['The new nameplates turn off after you reload. Type /rl to reload now.']
end

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

---/sui np <command>: the tester switch and two developer tools.
---@param args string|nil
local function Command(args)
	local cmd, rest = strsplit(' ', args or '', 2)
	cmd = cmd and cmd:lower() or ''
	if cmd == 'preview' then
		local on = P.Config:GetEngineChoice() ~= 'new'
		P.Config:SetEngineChoice(on and 'new' or 'old')
		if not on and engineRunning then
			P.CVars:RestoreAll()
		end
		Print(SwitchText(on))
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

---Host configuration handed to the core (6.11).
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
		RegisterCommand = function(name, fn, description)
			SUI:AddChatCommand(name, fn, description, nil, true)
		end,
		RegisterPreview = function(provider)
			if SUI.OptionsWindow and SUI.OptionsWindow.Stage then
				SUI.OptionsWindow.Stage:Register(provider)
			end
		end,
		ImportLegacy = function(profileKey)
			local raw = SpartanUIDB and SpartanUIDB.namespaces and SpartanUIDB.namespaces.Nameplates
			return raw and raw.profiles and raw.profiles[profileKey] or nil
		end,
		RefreshOptions = function(rebuild)
			if not module.optionsAdded then
				return
			end
			if rebuild and SUI.opt and SUI.opt.args then
				local tbl = P:BuildOptionsTable()
				tbl.order = 4.5
				SUI.opt.args.Nameplates = tbl
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
end

function module:OnEnable()
	SUI:AddChatCommand('np', Command, 'Nameplate testing tools', { preview = 'Turn the new nameplates on or off for this character (reload needed)' }, true)
	local wants, reason = HostWantsEngine()
	if not wants then
		if reason and reason ~= 'switch' then
			P.log.info('New nameplates are switched on but not started: ' .. reason)
		end
		if oldEnable then
			oldEnable(self)
		end
		return
	end
	RegisterOptions()
	WhenLoggedIn(StartEngine)
end

function module:OnDisable()
	if engineRunning then
		engineRunning = false
		P:Disable()
		return
	end
	-- The old module's OnDisable assumes its own options exist
	if oldDisable and SUI.opt and SUI.opt.args.Modules and SUI.opt.args.Modules.args.Nameplates then
		oldDisable(self)
	end
end
