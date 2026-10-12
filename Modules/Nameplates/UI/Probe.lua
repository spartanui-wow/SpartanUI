local _, ns = ...
local P = ns.Plates
local L = P.L
local Secret = P.Secret

-- Developer probe for the design spikes (plan 9.1, Phase 0b). Hidden from players: the host wires
-- it to a developer chat command and lists it nowhere. Nothing runs until that command does, so
-- loading this file stays inert (no events, frames, hooks or CVar writes).
--
-- Commands (the host passes everything after its own command word):
--   probe                      run every check a script can answer right now, then save and log it
--   probe watch [seconds] [touch]
--                              listen to plates (default 90 s): add-tick checks, casts, threat,
--                              target and combat changes. "touch" also runs the checks that change
--                              Blizzard's plates for one tick and put them back at once (hit-test
--                              rebinding, rolesets, reparenting), plus the two in-combat checks that
--                              could taint or be blocked (a next-frame click-area question from a
--                              timer, aura containers made in combat). Reload after a touch run.
--   probe stop | report | clear | help
--
-- Rules: every check runs inside pcall and never writes a game setting. Values that may be secret
-- only go to sinks or to Secret.IsSecret / CanAccess / Plain, and only plain values are stored.
-- Unit reads go through the Source object. Results go to the host logger and to global.devProbe
-- in the core's SavedVariable (newest last, at most MAX_RUNS), with the client, build, place and
-- time, so they can be read from the SavedVariables file after logout.

---@class Plates.ProbeResult
---@field status 'answered'|'partial'|'no data'|'skipped'|'error'|'running'
---@field note string One line for the log and the report
---@field ms? number Time the check took

---@class Plates.ProbeRun
---@field kind 'run'|'watch'
---@field stamp string
---@field client string
---@field results table<string, Plates.ProbeResult>

---@class Plates.Probe
local Probe = { watch = nil, sweeping = false, containers = {}, built = 0, capture = nil }
P.Probe = Probe

Probe.VERSION = 1
Probe.MAX_RUNS = 30
Probe.SAMPLE = 25
Probe.WATCH_SECONDS = 90
Probe.WATCH_MAX = 600
Probe.TOUCH_LIMIT = 3
Probe.SWEEP_LAST = 200000
Probe.SWEEP_STEP = 4000
Probe.MAX_CONTAINERS = 4
Probe.REPEAT = 50
Probe.MAX_LIST = 25

---Order of the checks in logs and reports.
Probe.ORDER = { 'S0', 'S1', 'S2', 'S3', 'S4', 'S6', 'S7', 'S8', 'S10', 'S11', 'S12', 'S13', 'S14', 'S16', 'S17' }

----------------------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------------------

local function Now()
	if debugprofilestop then
		return debugprofilestop()
	end
	return (GetTime and GetTime() or 0) * 1000
end

local function Round(value, places)
	if type(value) ~= 'number' then
		return nil
	end
	local m = 10 ^ (places or 0)
	return math.floor(value * m + 0.5) / m
end

---A plain number, or nil when the value is missing or hidden.
local function Num(value, places)
	if not Secret.CanAccess(value) or type(value) ~= 'number' then
		return nil
	end
	if places then
		return Round(value, places)
	end
	return value
end

---true or false, or 'hidden' when the game keeps the value from us.
local function Bool(value)
	if not Secret.CanAccess(value) then
		return 'hidden'
	end
	return value and true or false
end

---Bool for a Try or Call result: the error text when the call failed.
local function Answer(ok, value)
	if not ok then
		return 'error: ' .. tostring(value)
	end
	return Bool(value)
end

---A plain short string for logs and saved data.
local function Text(value, limit)
	if not Secret.CanAccess(value) then
		return 'hidden'
	end
	local text = tostring(value)
	limit = limit or 160
	if #text > limit then
		text = string.sub(text, 1, limit - 3) .. '...'
	end
	return text
end

local function Short(err)
	local text = Text(err, 400)
	text = string.gsub(text, '^[^:]*%.lua:%d+: ', '')
	return Text(text, 160)
end

---pcall that turns an error into a short plain string.
local function Try(fn, ...)
	local ok, a, b, c, d = pcall(fn, ...)
	if not ok then
		return false, Short(a)
	end
	return true, a, b, c, d
end

---Call a method only when the object has it. Errors become short strings.
local function Call(object, method, ...)
	local fn = object and object[method]
	if type(fn) ~= 'function' then
		return false, 'missing'
	end
	return Try(fn, object, ...)
end

---'ok' or the error text.
local function Step(fn)
	local ok, err = pcall(fn)
	if ok then
		return 'ok'
	end
	return Short(err)
end

---Resolve 'C_Name.Function' or a global name, for the API list.
local function Lookup(path)
	local value = _G
	for part in string.gmatch(path, '[^%.]+') do
		if type(value) ~= 'table' then
			return nil
		end
		value = value[part]
	end
	return value
end

local function InCombat()
	return (InCombatLockdown and InCombatLockdown()) and true or false
end

local function After(seconds, fn)
	if C_Timer and C_Timer.After then
		C_Timer.After(seconds, function()
			local ok, err = pcall(fn)
			if not ok then
				P.log.warning('Probe: a delayed check failed: ' .. Short(err))
			end
		end)
	end
end

local function Result(status, note, fields)
	fields = fields or {}
	fields.status = status
	fields.note = note
	return fields
end

local function YesNo(value)
	if value == true then
		return 'yes'
	elseif value == false then
		return 'no'
	end
	return tostring(value)
end

local function Count(t, key, amount)
	t[key] = (t[key] or 0) + (amount or 1)
end

----------------------------------------------------------------------------------------------------
-- Saved data
----------------------------------------------------------------------------------------------------

local function Saved()
	local db = P.db
	local global = db and db.global
	if type(global) ~= 'table' then
		return nil
	end
	local saved = global.devProbe
	if type(saved) ~= 'table' or type(saved.runs) ~= 'table' then
		saved = { version = Probe.VERSION, runs = {} }
		global.devProbe = saved
	end
	return saved
end

local function Keep(run)
	local saved = Saved()
	if not saved then
		return
	end
	saved.runs[#saved.runs + 1] = run
	while #saved.runs > Probe.MAX_RUNS do
		table.remove(saved.runs, 1)
	end
	saved.last = run.stamp
end

----------------------------------------------------------------------------------------------------
-- Frames (created on the first command, never at load)
----------------------------------------------------------------------------------------------------

local frames

local function Frames()
	if frames then
		return frames
	end
	local holder = CreateFrame('Frame', nil, UIParent)
	holder:SetSize(64, 16)
	holder:SetPoint('BOTTOMLEFT', UIParent, 'TOPLEFT', 0, 200)
	holder:SetAlpha(0)
	local other = CreateFrame('Frame', nil, UIParent)
	other:SetSize(64, 16)
	other:SetPoint('BOTTOMLEFT', UIParent, 'TOPLEFT', 100, 200)
	other:SetAlpha(0)
	local texture = holder:CreateTexture(nil, 'ARTWORK')
	texture:SetAllPoints(holder)
	texture:SetColorTexture(1, 1, 1, 1)
	local bar = CreateFrame('StatusBar', nil, holder)
	bar:SetAllPoints(holder)
	bar:SetStatusBarTexture('Interface\\Buttons\\WHITE8X8')
	bar:SetMinMaxValues(0, 1)
	local text = holder:CreateFontString(nil, 'OVERLAY')
	text:SetFont(STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF', 12, '')
	text:SetPoint('CENTER', holder, 'CENTER')
	local hidden = CreateFrame('Frame')
	hidden:Hide()
	local hit = CreateFrame('Frame', nil, holder)
	hit:SetSize(1, 1)
	hit:SetPoint('CENTER', holder, 'CENTER')
	frames = { holder = holder, other = other, texture = texture, bar = bar, text = text, hidden = hidden, hit = hit, events = CreateFrame('Frame'), sweeper = CreateFrame('Frame') }
	return frames
end

----------------------------------------------------------------------------------------------------
-- Plates, units and place
----------------------------------------------------------------------------------------------------

local function TokenOf(base)
	local candidates = {}
	if type(base.GetUnit) == 'function' then
		local ok, token = pcall(base.GetUnit, base)
		if ok then
			candidates[#candidates + 1] = token
		end
	end
	candidates[#candidates + 1] = base.namePlateUnitToken
	candidates[#candidates + 1] = base.unitToken
	for _, token in ipairs(candidates) do
		if Secret.CanAccess(token) and type(token) == 'string' and token ~= '' then
			return token
		end
	end
	return nil
end

---Shown, non-forbidden plates with their unit tokens (sampled, so a crowd stays cheap).
---Fill in tokens the frames did not give us by asking which plate each nameplateN token shows.
---Only used when a Blizzard field is missing; stops once every plate has a token.
local function ScanTokens(list, missing)
	local byBase = {}
	local limit = math.max(40, #list * 2)
	for i = 1, limit do
		if missing <= 0 then
			break
		end
		local token = 'nameplate' .. i
		local base = P.Source.PlateForUnit(token)
		if base and not byBase[base] then
			byBase[base] = token
			missing = missing - 1
		end
	end
	for _, entry in ipairs(list) do
		if not entry.unit then
			entry.unit = byBase[entry.base]
			entry.scanned = entry.unit ~= nil
		end
	end
end

---Shown, non-forbidden plates with their unit tokens (sampled, so a crowd stays cheap).
local function Plates(limit)
	local list = {}
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then
		return list
	end
	local ok, bases = pcall(C_NamePlate.GetNamePlates)
	if not ok or type(bases) ~= 'table' then
		return list
	end
	limit = limit or Probe.SAMPLE
	local missing = 0
	for _, base in ipairs(bases) do
		if #list >= limit then
			break
		end
		local unit = TokenOf(base)
		if not unit then
			missing = missing + 1
		end
		list[#list + 1] = { base = base, unit = unit }
	end
	if missing > 0 then
		ScanTokens(list, missing)
	end
	return list
end

local function Size(region)
	local okW, w = Call(region, 'GetWidth')
	local okH, h = Call(region, 'GetHeight')
	return okW and Num(w, 2) or nil, okH and Num(h, 2) or nil
end

local function Restrictions()
	local types = Enum and Enum.AddOnRestrictionType
	local fn = C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive
	if type(types) ~= 'table' or not fn then
		return nil
	end
	local out = {}
	for name, value in pairs(types) do
		local ok, active = pcall(fn, value)
		if ok then
			out[name] = Bool(active)
		end
	end
	return out
end

local function Meta(kind)
	local version, build, _, interface = GetBuildInfo()
	local place = P.Situation.ReadPlace({})
	local meta = {
		kind = kind,
		probe = Probe.VERSION,
		core = P.VERSION.core,
		time = time and time() or 0,
		stamp = date and date('%Y-%m-%d %H:%M:%S') or '',
		client = P.Caps:Client(),
		interface = interface,
		version = version,
		build = build,
		project = WOW_PROJECT_ID,
		locale = GetLocale and GetLocale() or nil,
		engineOn = P:IsEnabled() and true or false,
		inCombat = InCombat(),
		restricted = Secret.IsRestricted(),
		aurasSecret = Secret.ShouldAurasBeSecret(),
		secrets = P.Caps:Get('secrets'),
		place = place.place,
		inInstance = place.inInstance,
		instanceType = place.instanceType,
		difficultyID = place.difficultyID,
		challenge = place.challengeActive,
		restrictions = Restrictions(),
		results = {},
	}
	if GetInstanceInfo then
		local ok, name, _, _, difficultyName, maxPlayers, _, _, instanceID = pcall(GetInstanceInfo)
		if ok then
			meta.instance = Text(name, 60)
			meta.difficulty = Text(difficultyName, 40)
			meta.maxPlayers = Num(maxPlayers)
			meta.instanceID = Num(instanceID)
		end
	end
	if C_Map and C_Map.GetBestMapForUnit then
		local ok, mapID = pcall(C_Map.GetBestMapForUnit, 'player')
		meta.mapID = ok and Num(mapID) or nil
	end
	if GetRealZoneText then
		local ok, zone = pcall(GetRealZoneText)
		meta.zone = ok and Text(zone, 60) or nil
	end
	return meta
end

----------------------------------------------------------------------------------------------------
-- Blocked-action capture (ADDON_ACTION_BLOCKED and _FORBIDDEN are synchronous events, so they
-- arrive while the call that caused them is still running)
----------------------------------------------------------------------------------------------------

local BLOCK_EVENTS = { 'ADDON_ACTION_BLOCKED', 'ADDON_ACTION_FORBIDDEN' }
local handlers = {}

local function OnEvent(_, event, ...)
	local handler = handlers[event]
	if not handler then
		return
	end
	local ok, err = pcall(handler, event, ...)
	if not ok then
		Probe.lastError = Short(err)
		local w = Probe.watch
		if w then
			Count(w.raw, 'handlerErrors')
			w.raw.lastHandlerError = Probe.lastError
		end
	end
end

local function Listen(event)
	local f = Frames()
	f.events:SetScript('OnEvent', OnEvent)
	return (pcall(f.events.RegisterEvent, f.events, event))
end

local function Unlisten(event)
	if frames then
		pcall(frames.events.UnregisterEvent, frames.events, event)
	end
end

handlers.ADDON_ACTION_BLOCKED = function(event, culprit, fn)
	local list = Probe.capture
	if list and #list < Probe.MAX_LIST then
		list[#list + 1] = { event = event, addon = Text(culprit, 60), fn = Text(fn, 80), inCombat = InCombat(), at = Round(GetTime and GetTime() or 0, 2) }
	end
end
handlers.ADDON_ACTION_FORBIDDEN = handlers.ADDON_ACTION_BLOCKED

local function CaptureBegin(list)
	Probe.capture = list
	for _, event in ipairs(BLOCK_EVENTS) do
		Listen(event)
	end
end

local function CaptureEnd()
	if Probe.watch then
		Probe.capture = Probe.watch.raw.blocked
		return
	end
	Probe.capture = nil
	for _, event in ipairs(BLOCK_EVENTS) do
		Unlisten(event)
	end
end

----------------------------------------------------------------------------------------------------
-- Sink helpers (secret values go straight into engine calls)
----------------------------------------------------------------------------------------------------

local function ApplyTimerSecret(bar, durationSecret)
	local interpolation = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or nil
	local direction = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime or nil
	bar:SetTimerDuration(durationSecret, interpolation, direction)
end

---Secret copies of the given values through the game's own wrapper, where addons may use it.
---@return boolean ok
local function Wrap(...)
	local wrap = _G.secretwrap
	if type(wrap) ~= 'function' then
		return false, 'secretwrap is missing'
	end
	return Try(wrap, ...)
end

----------------------------------------------------------------------------------------------------
-- S0: secrets, duration objects, timer bars, CROWD_CONTROL
----------------------------------------------------------------------------------------------------

local API_NAMES = {
	'C_Secrets.HasSecretRestrictions',
	'C_Secrets.ShouldAurasBeSecret',
	'C_Secrets.CanCompareUnitTokens',
	'C_Secrets.ShouldUnitThreatStateBeSecret',
	'C_Secrets.ShouldUnitIdentityBeSecret',
	'C_Secrets.ShouldUnitComparisonBeSecret',
	'C_Secrets.ShouldUnitSpellCastingBeSecret',
	'secretwrap',
	'issecretvalue',
	'canaccessvalue',
	'C_DurationUtil.CreateDuration',
	'C_DurationUtil.CreateDurationTextBinding',
	'C_StringUtil.CreateSecondsFormatter',
	'C_StringUtil.TruncateWhenZero',
	'UnitCastingDuration',
	'UnitChannelDuration',
	'UnitEmpoweredChannelDuration',
	'UnitHealthPercent',
	'UnitIsLieutenant',
	'UnitIsBossMob',
	'UnitIsQuestBoss',
	'UnitSpellTargetName',
	'UnitShouldDisplaySpellTargetName',
	'PlayerIsSpellTarget',
	'UnitNameplateShowsWidgetsOnly',
	'UnitCreatureID',
	'CreateUnitHealPredictionCalculator',
	'C_CurveUtil.EvaluateColorFromBoolean',
	'C_CurveUtil.EvaluateColorValueFromBoolean',
	'C_CurveUtil.CreateColorCurve',
	'C_Spell.IsSpellImportant',
	'C_Spell.GetSpellCooldownDuration',
	'C_NamePlate.GetNamePlateSize',
	'C_NamePlate.SetNamePlateSize',
	'C_NamePlateManager.SetNamePlateSimplified',
	'C_NamePlateManager.SetNamePlateHitTestInsets',
	'C_NamePlateManager.IsNamePlateUnitBehindCamera',
	'C_RestrictedActions.CheckAllowProtectedFunctions',
	'C_RestrictedActions.IsAddOnRestrictionActive',
	'C_TooltipInfo.GetUnit',
	'C_XMLUtil.GetTemplateInfo',
	'CreateFontFamily',
	'AuraUtil.IsValidFilterString',
	'C_UnitAuras.GetUnitAuraInstanceIDs',
	'C_ChallengeMode.IsChallengeModeActive',
	'C_ScenarioInfo.GetUnitCriteriaProgressValues',
	'C_AddOnProfiler',
	'C_EncodingUtil.SerializeCBOR',
	'C_ClassColor.GetClassColor',
	'C_CVar.GetCVarInfo',
	'C_CVar.SetCVarBitfield',
	'GetPhysicalScreenSize',
}

local METHODS = {
	bar = { 'SetTimerDuration', 'SetAlphaFromBoolean' },
	texture = { 'SetVertexColorFromBoolean', 'SetAlphaFromBoolean', 'SetSpriteSheetCell' },
	text = { 'SetSmoothScaling', 'SetAlphaFromBoolean' },
	holder = { 'SetRolesets', 'SetIgnoreParentAlpha', 'SetToDefaults', 'HasSecretAspect', 'SetAlphaFromBoolean' },
}

local FILTERS = {
	{ key = 'harmful', filter = 'HARMFUL' },
	{ key = 'cc', filter = 'HARMFUL|CROWD_CONTROL' },
	{ key = 'notCC', filter = 'HARMFUL|!CROWD_CONTROL' },
	{ key = 'helpfulCC', filter = 'HELPFUL|CROWD_CONTROL' },
	{ key = 'bogus', filter = 'HARMFUL|NOT_A_REAL_FILTER' },
}

local function CountAuras(unit, filter)
	local src = P.Source.NewLive(unit)
	local count = 0
	local ok, err = pcall(function()
		for index = 1, 40 do
			if not src:AuraByIndexPlain(index, filter) then
				break
			end
			count = count + 1
		end
	end)
	if not ok then
		return 'error: ' .. Short(err)
	end
	return count
end

local function FilterChecks()
	local out = {}
	local hasTarget = P.Source.UnitExists('target')
	local valid = AuraUtil and AuraUtil.IsValidFilterString
	for _, entry in ipairs(FILTERS) do
		local row = {}
		if valid then
			local ok, answer = Try(valid, entry.filter)
			row.valid = Answer(ok, answer)
		end
		row.player = CountAuras('player', entry.filter)
		if hasTarget then
			row.target = CountAuras('target', entry.filter)
		end
		out[entry.key] = row
	end
	return out
end

local function ReadBindingText(binding, fontString)
	local ok, text = Call(binding, 'GetFormattedText')
	if not ok or type(text) == 'nil' then
		ok, text = Call(fontString, 'GetText')
	end
	if not ok then
		return 'error: ' .. text
	end
	return Text(text, 40)
end

local function BindingCheck()
	if not (C_DurationUtil and C_DurationUtil.CreateDurationTextBinding and C_DurationUtil.CreateDuration) then
		return { create = 'missing' }
	end
	local out = {}
	local f = Frames()
	local binding = Probe.binding
	if not binding then
		local ok, made = Try(C_DurationUtil.CreateDurationTextBinding)
		if not ok then
			out.create = made
			return out
		end
		binding = made
		Probe.binding = binding
	end
	out.create = 'ok'
	out.setup = Step(function()
		if binding.SetFontString then
			binding:SetFontString(f.text)
		end
		if binding.SetFormatter and C_StringUtil and C_StringUtil.CreateSecondsFormatter then
			binding:SetFormatter(C_StringUtil.CreateSecondsFormatter())
		end
		local duration = C_DurationUtil.CreateDuration()
		duration:SetTimeFromStart(GetTime() - 2.5, 15)
		binding:SetDuration(duration)
		if binding.SetEnabled then
			binding:SetEnabled(true)
		end
	end)
	out.expect = '12.5 s left, then 12 s'
	out.textNow = ReadBindingText(binding, f.text)
	After(0.5, function()
		out.textLater = ReadBindingText(binding, f.text)
		if binding.SetEnabled then
			pcall(binding.SetEnabled, binding, false)
		end
		P.log.info('Probe S0: duration text read again: "' .. out.textLater .. '" (expected about 12 s)')
	end)
	return out
end

local function WrappedTimer(bar)
	local ok, a, b = Wrap(GetTime(), 10)
	if not ok then
		return { wrap = a }
	end
	if type(a) == 'nil' then
		return { wrap = 'secretwrap returned nothing' }
	end
	local out = { wrap = 'ok', wrapped = Secret.IsSecret(a) }
	local startSecret, lengthSecret = a, b
	out.applied = Step(function()
		local duration = C_DurationUtil.CreateDuration()
		duration:SetTimeFromStart(startSecret, lengthSecret)
		ApplyTimerSecret(bar, duration)
	end)
	return out
end

local function PlayerCast(bar)
	local src = P.Source.NewLive('player')
	local ok, kind = Try(src.CastKind, src)
	if not ok then
		return { kind = 'error: ' .. kind }
	end
	if not kind then
		return { kind = 'not casting' }
	end
	return {
		kind = kind,
		applied = Step(function()
			ApplyTimerSecret(bar, src:CastDurationSecret())
		end),
	}
end

local function CheckS0()
	local r = { apis = {}, methods = {} }
	for _, name in ipairs(API_NAMES) do
		r.apis[name] = Lookup(name) ~= nil
	end
	local f = Frames()
	for key, list in pairs(METHODS) do
		for _, method in ipairs(list) do
			r.methods[key .. ':' .. method] = f[key][method] ~= nil
		end
	end
	r.secrets = P.Caps:Get('secrets')
	if C_Secrets and C_Secrets.HasSecretRestrictions then
		local ok, answer = Try(C_Secrets.HasSecretRestrictions)
		r.hasSecretRestrictions = Answer(ok, answer)
	end
	local bar = f.bar
	r.timerMethod = bar.SetTimerDuration ~= nil
	local canDuration = C_DurationUtil and C_DurationUtil.CreateDuration
	if r.timerMethod and canDuration then
		r.timerPlain = Step(function()
			local duration = C_DurationUtil.CreateDuration()
			duration:SetTimeFromStart(GetTime(), 10)
			ApplyTimerSecret(bar, duration)
		end)
		r.timerWrapped = WrappedTimer(bar)
		r.playerCast = PlayerCast(bar)
	end
	r.textBinding = BindingCheck()
	r.filters = FilterChecks()
	local cc, bogus = r.filters.cc, r.filters.bogus
	local ccRefused = cc.valid == false or (type(cc.player) == 'string')
	local bogusRefused = bogus.valid == false or (type(bogus.player) == 'string')
	local ccText
	if ccRefused then
		ccText = 'refused'
	elseif bogusRefused then
		ccText = 'accepted (a made-up token is refused, so this means something)'
	else
		ccText = 'no error, but made-up tokens are not refused either: compare counts'
	end
	local wrapped = r.timerWrapped and (r.timerWrapped.applied or r.timerWrapped.wrap) or 'n/a'
	local note = string.format(
		'secrets %s; timer bar %s; timer bar with secret times %s; player cast %s; CROWD_CONTROL %s; duration text "%s"',
		YesNo(r.secrets),
		tostring(r.timerPlain or 'n/a'),
		tostring(wrapped),
		r.playerCast and r.playerCast.kind or 'n/a',
		ccText,
		tostring(r.textBinding.textNow or r.textBinding.create)
	)
	return Result('answered', note, r)
end

----------------------------------------------------------------------------------------------------
-- S1: hit-test rebinding and the Mists scale quirk (static part; the add-tick part is in watch)
----------------------------------------------------------------------------------------------------

local function IsLuaStub(base, method)
	local mixin = _G.NamePlateScriptBaseMixin
	local fn = base[method]
	return type(mixin) == 'table' and mixin[method] ~= nil and fn == mixin[method]
end

local function CheckS1()
	local r = { plates = {} }
	r.uiScale = Num(UIParent:GetScale(), 4)
	r.uiEffective = Num(UIParent:GetEffectiveScale(), 4)
	if C_NamePlate and C_NamePlate.GetNamePlateSize then
		local ok, w, h = Try(C_NamePlate.GetNamePlateSize)
		if ok then
			r.sizeW, r.sizeH = Num(w, 2), Num(h, 2)
		end
	end
	r.quirk = P.Caps:Quirk('uiParentScale')
	r.recorded = P.Caps.recorded.hitTest
	for _, entry in ipairs(Plates(5)) do
		local base = entry.base
		local info = { unit = entry.unit }
		info.w, info.h = Size(base)
		local okS, scale = Call(base, 'GetScale')
		info.scale = okS and Num(scale, 4) or nil
		local okE, effective = Call(base, 'GetEffectiveScale')
		info.effective = okE and Num(effective, 4) or nil
		local okC, can = Call(base, 'CanChangeHitTestPoints')
		info.canChange = Answer(okC, can)
		info.luaStub = IsLuaStub(base, 'CanChangeHitTestPoints') or IsLuaStub(base, 'SetAllHitTestPoints')
		local okP, points = Call(base, 'GetHitTestPoints')
		if okP and Secret.CanAccess(points) and type(points) == 'table' then
			info.points = #points
		end
		r.plates[#r.plates + 1] = info
	end
	local first = r.plates[1]
	if first and first.w and r.sizeW and r.sizeW > 0 then
		r.ratio = Round(first.w / r.sizeW, 3)
		if r.uiScale and r.uiScale > 0 then
			r.ratioIfScaled = Round(1 / r.uiScale, 3)
		end
	end
	if not first then
		return Result('no data', string.format('no plates on screen; UI scale %s; game plate size %sx%s', tostring(r.uiScale), tostring(r.sizeW), tostring(r.sizeH)), r)
	end
	local note = string.format(
		'UI scale %s; game plate size %sx%s; first plate %sx%s (ratio %s, %s if sizes were scaled by the UI); can change click area now %s; Lua stubs %s; run "watch touch" for the add-tick test',
		tostring(r.uiScale),
		tostring(r.sizeW),
		tostring(r.sizeH),
		tostring(first.w),
		tostring(first.h),
		tostring(r.ratio),
		tostring(r.ratioIfScaled),
		tostring(first.canChange),
		YesNo(first.luaStub)
	)
	return Result('partial', note, r)
end

----------------------------------------------------------------------------------------------------
-- S2 and S16: threat state and in-combat state on plates
----------------------------------------------------------------------------------------------------

local function NewThreatTally()
	return { plates = 0, statusHidden = 0, gameSaysHidden = 0, readable = 0, onList = 0, percentHidden = 0, gameSaysValuesHidden = 0, errors = 0 }
end

local function ThreatSample(unit, tally)
	local src = P.Source.NewLive(unit)
	tally.plates = tally.plates + 1
	local ok, hidden = Try(function()
		return Secret.IsSecret(src:ThreatStatusSecret())
	end)
	if not ok then
		tally.errors = tally.errors + 1
		tally.lastError = hidden
		return
	end
	if hidden then
		tally.statusHidden = tally.statusHidden + 1
	end
	if Secret.ShouldUnitThreatStateBeSecret('player', unit) then
		tally.gameSaysHidden = tally.gameSaysHidden + 1
	end
	local okP, status, readable = Try(src.ThreatStatusPlain, src)
	if okP and readable then
		tally.readable = tally.readable + 1
		if status ~= nil then
			tally.onList = tally.onList + 1
		end
	end
	local okV, percentHidden = Try(function()
		return Secret.IsSecret(src:ThreatPercentSecret())
	end)
	if okV and percentHidden then
		tally.percentHidden = tally.percentHidden + 1
	end
	if Secret.ShouldUnitThreatValuesBeSecret('player', unit) then
		tally.gameSaysValuesHidden = tally.gameSaysValuesHidden + 1
	end
end

local function ThreatNote(t)
	return string.format(
		'%d plates: threat state hidden on %d (the game says hidden on %d), readable on %d, on the threat list %d; threat numbers hidden on %d; errors %d',
		t.plates,
		t.statusHidden,
		t.gameSaysHidden,
		t.readable,
		t.onList,
		t.percentHidden,
		t.errors
	)
end

local function CheckS2()
	local t = NewThreatTally()
	for _, entry in ipairs(Plates()) do
		if entry.unit then
			ThreatSample(entry.unit, t)
		end
	end
	if t.plates == 0 then
		return Result('no data', 'no plates on screen', t)
	end
	return Result(t.onList > 0 and 'answered' or 'partial', ThreatNote(t), t)
end

local function NewCombatTally()
	return { plates = 0, readable = 0, hidden = 0, fighting = 0, errors = 0 }
end

local function CombatSample(unit, tally)
	local src = P.Source.NewLive(unit)
	tally.plates = tally.plates + 1
	local ok, hidden = Try(function()
		return Secret.IsSecret(src:InCombatSecret())
	end)
	if not ok then
		tally.errors = tally.errors + 1
		tally.lastError = hidden
		return
	end
	if hidden then
		tally.hidden = tally.hidden + 1
	end
	local okP, value, readable = Try(src.InCombatPlain, src)
	if okP and readable then
		tally.readable = tally.readable + 1
		if value then
			tally.fighting = tally.fighting + 1
		end
	end
end

local function CombatNote(t)
	return string.format('%d plates: in-combat state readable on %d, hidden on %d, fighting %d; errors %d', t.plates, t.readable, t.hidden, t.fighting, t.errors)
end

local function CheckS16()
	local t = NewCombatTally()
	for _, entry in ipairs(Plates()) do
		if entry.unit then
			CombatSample(entry.unit, t)
		end
	end
	if t.plates == 0 then
		return Result('no data', 'no plates on screen', t)
	end
	return Result('answered', CombatNote(t), t)
end

----------------------------------------------------------------------------------------------------
-- S3: chaining secret color choices
----------------------------------------------------------------------------------------------------

local function Colors()
	if not (CreateColor and C_CurveUtil) then
		return nil
	end
	return CreateColor(1, 0, 0, 1), CreateColor(0, 1, 0, 1), CreateColor(0, 0, 1, 1), CreateColor(1, 1, 1, 1)
end

---Runs the color chain with two booleans that are secret where possible. Stores only plain text.
local function RunColorChainSecret(r, trueSecret, falseSecret)
	local f = Frames()
	local red, green, blue, white = Colors()
	if C_CurveUtil.EvaluateColorValueFromBoolean then
		local channelSecret
		r.channel = Step(function()
			channelSecret = C_CurveUtil.EvaluateColorValueFromBoolean(trueSecret, 1, 0)
		end)
		r.channelChain = Step(function()
			channelSecret = C_CurveUtil.EvaluateColorValueFromBoolean(falseSecret, channelSecret, 0.5)
		end)
		r.channelApply = Step(function()
			f.bar:SetStatusBarColor(channelSecret, 0, 0, 1)
		end)
		r.channelHidden = Secret.IsSecret(channelSecret)
	end
	if C_CurveUtil.EvaluateColorFromBoolean and red then
		local firstSecret, chainSecret
		r.mixin = Step(function()
			firstSecret = C_CurveUtil.EvaluateColorFromBoolean(trueSecret, red, green)
		end)
		r.mixinChain = Step(function()
			chainSecret = C_CurveUtil.EvaluateColorFromBoolean(falseSecret, firstSecret, blue)
		end)
		r.mixinHidden = Secret.IsSecret(chainSecret)
		r.mixinReadable = Secret.CanAccess(chainSecret)
		if f.texture.SetVertexColorFromBoolean then
			r.mixinApply = Step(function()
				f.texture:SetVertexColorFromBoolean(trueSecret, chainSecret, white)
			end)
			local okC, rr, gg, bb = Call(f.texture, 'GetVertexColor')
			if okC then
				local rv, rReadable = Secret.Plain(rr)
				local gv = Secret.Plain(gg)
				local bv = Secret.Plain(bb)
				if rReadable then
					r.readBack = string.format('%s,%s,%s (blue 0,0,1 means the chain picked right)', tostring(Round(rv, 2)), tostring(Round(gv, 2)), tostring(Round(bv, 2)))
				else
					r.readBack = 'hidden'
				end
			end
		end
	end
	r.alphaFromBoolean = Step(function()
		Secret.SetAlphaFromBoolean(f.texture, trueSecret, 1, 0)
	end)
	f.texture:SetAlpha(1)
end

---A secret boolean the game hands us on its own (a plate compared with the target on a restricted
---map), for clients where secretwrap is not open to addons. nil when nothing is hidden right now.
local function NaturalSecret()
	for _, entry in ipairs(Plates(10)) do
		if entry.unit then
			local src = P.Source.NewLive(entry.unit)
			for _, token in ipairs({ 'target', 'player', 'mouseover' }) do
				local ok, hidden = Try(function()
					return Secret.IsSecret(src:IsUnitSecret(token))
				end)
				if ok and hidden then
					return src:IsUnitSecret(token)
				end
			end
		end
	end
	return nil
end

local function CheckS3()
	local r = {}
	if not C_CurveUtil then
		return Result('skipped', 'no color curve functions on this client', r)
	end
	local ok, a, b = Wrap(true, false)
	if ok and Secret.IsSecret(a) then
		r.source = 'secretwrap'
		local trueSecret, falseSecret = a, b
		RunColorChainSecret(r, trueSecret, falseSecret)
	else
		local naturalSecret = NaturalSecret()
		if type(naturalSecret) ~= 'nil' then
			r.source = 'a hidden plate answer (true or false is unknown)'
			RunColorChainSecret(r, naturalSecret, naturalSecret)
		else
			r.source = 'plain values (' .. (ok and 'secretwrap gave no secret' or a) .. ')'
			RunColorChainSecret(r, true, false)
		end
	end
	local note = string.format(
		'test values from %s; per-channel %s, chained %s, applied %s; whole color %s, chained %s, applied %s, result hidden %s, read back %s',
		r.source,
		tostring(r.channel),
		tostring(r.channelChain),
		tostring(r.channelApply),
		tostring(r.mixin),
		tostring(r.mixinChain),
		tostring(r.mixinApply),
		YesNo(r.mixinHidden),
		tostring(r.readBack)
	)
	local status = string.sub(r.source, 1, 5) == 'plain' and 'partial' or 'answered'
	return Result(status, note, r)
end

----------------------------------------------------------------------------------------------------
-- S4 and S14: finding plates from unit tokens
----------------------------------------------------------------------------------------------------

local TOKENS = { 'target', 'focus', 'mouseover', 'softenemy', 'softfriend', 'boss1', 'arena1' }

local function NewTargetTally()
	return { checks = 0, noTarget = 0, found = 0, notFound = 0, matchByCompare = 0, compareHidden = 0, identityHidden = 0, missingWhileMatched = 0, fallback = 'not run' }
end

---Look for the target's plate two ways: the plate lookup, and comparing each plate's unit.
local function TargetSample(t, plates)
	t.checks = t.checks + 1
	local okE, exists = Try(P.Source.UnitExists, 'target')
	if not okE or not exists then
		t.noTarget = t.noTarget + 1
		return
	end
	if Secret.ShouldUnitIdentityBeSecret('target') then
		t.identityHidden = t.identityHidden + 1
	end
	local found = P.Source.PlateForUnit('target')
	if found then
		t.found = t.found + 1
	else
		t.notFound = t.notFound + 1
	end
	local matched
	for _, entry in ipairs(plates or Plates()) do
		if entry.unit then
			local src = P.Source.NewLive(entry.unit)
			local ok, isTarget, readable = Try(function()
				return Secret.Plain(src:IsUnitSecret('target'))
			end)
			if ok and readable then
				if isTarget then
					matched = entry.base
				end
			else
				t.compareHidden = t.compareHidden + 1
			end
			if t.fallback == 'not run' then
				t.fallback = Step(function()
					P.Secret.SetAlphaFromBoolean(Frames().texture, src:IsUnitSecret('target'), 1, 0)
				end)
				Frames().texture:SetAlpha(1)
			end
		end
	end
	if matched then
		t.matchByCompare = t.matchByCompare + 1
		if not found then
			t.missingWhileMatched = t.missingWhileMatched + 1
		elseif found ~= matched then
			t.mismatch = (t.mismatch or 0) + 1
		end
	end
end

local function TargetNote(t)
	return string.format(
		'%d checks (%d without a target): plate lookup found %d, found nothing %d; plate found by comparing units %d (lookup empty while compare found it %d); compares hidden %d; target identity hidden %d; fade fallback %s',
		t.checks,
		t.noTarget,
		t.found,
		t.notFound,
		t.matchByCompare,
		t.missingWhileMatched,
		t.compareHidden,
		t.identityHidden,
		tostring(t.fallback)
	)
end

local function CheckS4()
	local t = NewTargetTally()
	TargetSample(t)
	t.canCompare = {}
	for _, entry in ipairs(Plates(5)) do
		if entry.unit then
			t.canCompare[entry.unit] = Secret.CanCompareUnitTokens('target', entry.unit)
		end
	end
	if t.noTarget > 0 then
		return Result('no data', 'no target; pick one (best on a restricted map) and run again', t)
	end
	return Result('answered', TargetNote(t), t)
end

local function CheckS14()
	local r = { plates = 0, same = 0, other = 0, none = 0, tokens = {} }
	for _, entry in ipairs(Plates()) do
		if entry.unit then
			r.plates = r.plates + 1
			local found = P.Source.PlateForUnit(entry.unit)
			if found == entry.base then
				r.same = r.same + 1
			elseif found then
				r.other = r.other + 1
			else
				r.none = r.none + 1
			end
		end
	end
	for _, token in ipairs(TOKENS) do
		local okE, exists = Try(P.Source.UnitExists, token)
		local found = P.Source.PlateForUnit(token)
		r.tokens[token] = string.format('exists %s, plate %s', okE and YesNo(exists) or 'error', found and 'yes' or 'no')
	end
	local note = string.format('%d plates: lookup by their own token gave the same plate %d, another plate %d, nothing %d; target: %s', r.plates, r.same, r.other, r.none, r.tokens.target)
	return Result(r.plates > 0 and 'answered' or 'partial', note, r)
end

----------------------------------------------------------------------------------------------------
-- S6: aura containers (create, reparent and bind costs, in or out of combat)
----------------------------------------------------------------------------------------------------

local function GroupButtons(container, key)
	local ok, count = Call(container, 'GetAuraGroupFrameCount', key)
	return ok and Num(count) or 0
end

local function ContainerTest()
	local r = { inCombat = InCombat(), restricted = Secret.IsRestricted() }
	if not P.Caps:Get('containers') then
		return Result('skipped', 'no aura containers on this client', r)
	end
	local f = Frames()
	local container
	if Probe.built < Probe.MAX_CONTAINERS then
		local memory = collectgarbage('count')
		local started = Now()
		local ok, made = Try(CreateFrame, 'AuraContainer', nil, f.holder, 'CustomAuraContainerTemplate')
		r.createMs = Round(Now() - started, 3)
		r.create = ok and 'ok' or made
		if ok and made then
			Probe.built = Probe.built + 1
			Probe.containers[#Probe.containers + 1] = made
			container = made
			pcall(made.SetEnabled, made, false)
			started = Now()
			r.addGroup = Step(function()
				made:AddAuraGroup('probeMine', 'HARMFUL|PLAYER', { maxFrameCount = 10 })
			end)
			r.addGroupMs = Round(Now() - started, 3)
			r.addCrowdControl = Step(function()
				made:AddAuraGroup('probeCC', 'HARMFUL|CROWD_CONTROL', { maxFrameCount = 10 })
			end)
			r.buttons = GroupButtons(made, 'probeMine') + GroupButtons(made, 'probeCC')
			r.luaMemoryKB = Round(collectgarbage('count') - memory, 1)
		end
	else
		r.create = 'skipped (reusing one of ' .. Probe.built .. ')'
	end
	container = container or Probe.containers[#Probe.containers]
	if not container then
		return Result('error', 'no container could be made: ' .. tostring(r.create), r)
	end
	local started = Now()
	r.reparent = Step(function()
		for i = 1, Probe.REPEAT do
			container:SetParent(i % 2 == 0 and f.holder or f.other)
		end
	end)
	r.reparentUs = Round((Now() - started) * 1000 / Probe.REPEAT, 1)
	started = Now()
	r.bind = Step(function()
		for _ = 1, Probe.REPEAT do
			container:SetUnit('player')
			container:SetEnabled(true)
			container:SetEnabled(false)
		end
	end)
	r.bindUs = Round((Now() - started) * 1000 / Probe.REPEAT, 1)
	r.unbind = Step(function()
		container:SetUnit('none')
	end)
	pcall(container.SetParent, container, f.holder)
	local when = r.inCombat and 'in combat' or 'out of combat'
	local note = string.format(
		'%s (restricted %s): create %s in %s ms, group add %s in %s ms (%s buttons, Lua memory %s KB); CROWD_CONTROL group %s; reparent %s at %s us each; bind %s at %s us each; unbind %s',
		when,
		YesNo(r.restricted),
		tostring(r.create),
		tostring(r.createMs),
		tostring(r.addGroup),
		tostring(r.addGroupMs),
		tostring(r.buttons),
		tostring(r.luaMemoryKB),
		tostring(r.addCrowdControl),
		tostring(r.reparent),
		tostring(r.reparentUs),
		tostring(r.bind),
		tostring(r.bindUs),
		tostring(r.unbind)
	)
	return Result('answered', note, r)
end

----------------------------------------------------------------------------------------------------
-- S7: Blizzard unit frames on plates (rolesets, protection; the in-combat add is in watch)
----------------------------------------------------------------------------------------------------

local function AllowedOn(frame)
	local fn = C_RestrictedActions and C_RestrictedActions.CheckAllowProtectedFunctions
	if not fn then
		return 'missing'
	end
	local ok, allowed = Try(fn, frame, true)
	if not ok then
		return 'error: ' .. allowed
	end
	return Bool(allowed)
end

local function FrameFacts(base)
	local uf = base.UnitFrame
	local info = { unitFrame = uf ~= nil }
	if not uf then
		return info
	end
	local okF, forbidden = Call(uf, 'IsForbidden')
	info.forbidden = Answer(okF, forbidden)
	local okP, protected = Call(uf, 'IsProtected')
	info.protected = Answer(okP, protected)
	info.allowed = AllowedOn(uf)
	info.hasRolesets = uf.SetRolesets ~= nil
	local okN, names = Call(uf, 'GetRolesetNames')
	if okN and Secret.CanAccess(names) and type(names) == 'table' then
		local list = {}
		for _, name in ipairs(names) do
			list[#list + 1] = Text(name, 30)
		end
		info.rolesets = table.concat(list, ',')
	end
	local okR, filtered = Call(uf, 'IsRolesetFiltered')
	info.filtered = Answer(okR, filtered)
	local okParent, parent = Call(uf, 'GetParent')
	info.parentIsBase = okParent and parent == base
	info.touchedByEngine = P.Suppress and P.Suppress.WasTouched and P.Suppress:WasTouched(uf) or false
	return info
end

local function CheckS7()
	local r = { plates = {}, inCombat = InCombat(), capRolesets = P.Caps:Get('rolesets'), recorded = P.Caps.recorded.rolesets }
	for _, entry in ipairs(Plates(5)) do
		local info = FrameFacts(entry.base)
		info.unit = entry.unit
		r.plates[#r.plates + 1] = info
	end
	local first = r.plates[1]
	if not first then
		return Result('no data', 'no plates on screen; run "watch" (with "touch" to try rolesets) during a pull', r)
	end
	local note = string.format(
		'%s: rolesets method %s; protected %s; protected calls allowed %s; rolesets "%s"; run "watch touch" during a pull for the add-in-combat test',
		r.inCombat and 'in combat' or 'out of combat',
		YesNo(first.hasRolesets),
		tostring(first.protected),
		tostring(first.allowed),
		tostring(first.rolesets)
	)
	return Result('partial', note, r)
end

----------------------------------------------------------------------------------------------------
-- S8: plate sizes by kind (simplified plates)
----------------------------------------------------------------------------------------------------

local function NewSizeTally()
	return { minor = { count = 0, w = 0, h = 0 }, other = { count = 0, w = 0, h = 0 } }
end

local function SizeSample(tally, base, unit)
	local w, h = Size(base)
	if not (w and h and unit) then
		return
	end
	local src = P.Source.NewLive(unit)
	local ok, facts = Try(src.ReadFacts, src, {})
	if not ok then
		return
	end
	local kind = P.Situation.Classify(facts) == 'minor' and 'minor' or 'other'
	local bucket = tally[kind]
	bucket.count = bucket.count + 1
	bucket.w = bucket.w + w
	bucket.h = bucket.h + h
end

local function SizeNote(t)
	local function Average(bucket)
		if bucket.count == 0 then
			return 'none'
		end
		return string.format('%sx%s (%d)', tostring(Round(bucket.w / bucket.count, 1)), tostring(Round(bucket.h / bucket.count, 1)), bucket.count)
	end
	return 'minor plates ' .. Average(t.minor) .. ', other plates ' .. Average(t.other)
end

local function CVarValue(name)
	if not (C_CVar and C_CVar.GetCVar) then
		return nil
	end
	local ok, value = Try(C_CVar.GetCVar, name)
	return ok and Text(value, 40) or nil
end

local function CheckS8()
	local t = NewSizeTally()
	for _, entry in ipairs(Plates()) do
		SizeSample(t, entry.base, entry.unit)
	end
	t.simplifiedTypes = CVarValue('nameplateSimplifiedTypes')
	t.simplifiedScale = CVarValue('nameplateSimplifiedScale')
	t.capSimplified = P.Caps:Get('simplified')
	if t.minor.count + t.other.count == 0 then
		return Result('no data', 'no plates on screen', t)
	end
	local note = SizeNote(t) .. string.format('; simplified types %s, scale %s', tostring(t.simplifiedTypes), tostring(t.simplifiedScale))
	return Result(t.minor.count > 0 and t.other.count > 0 and 'answered' or 'partial', note, t)
end

----------------------------------------------------------------------------------------------------
-- S10: font families draw non-Latin names
----------------------------------------------------------------------------------------------------

-- A Cyrillic test name, written as UTF-8 bytes so this file stays plain ASCII
local CYRILLIC = '\208\161\208\178\208\181\209\130\208\176'
local LATIN_FONT = 'Fonts\\ARIALN.TTF'
local ALPHABETS = { 'roman', 'korean', 'simplifiedchinese', 'traditionalchinese', 'russian' }
local FAMILY_SOURCES = { 'SystemFont_NamePlate', 'SystemFont_Shadow_Med1', 'SystemFont_Small', 'ChatFontNormal' }

local function FamilyMembers()
	for _, sourceName in ipairs(FAMILY_SOURCES) do
		local source = _G[sourceName]
		local members = {}
		local hasRussian = false
		if type(source) == 'table' and source.GetFontObjectForAlphabet then
			for _, alphabet in ipairs(ALPHABETS) do
				local ok, object = Call(source, 'GetFontObjectForAlphabet', alphabet)
				if ok and object then
					local okF, file, _, flags = Call(object, 'GetFont')
					if okF and type(file) == 'string' then
						members[#members + 1] = { alphabet = alphabet, file = alphabet == 'roman' and LATIN_FONT or file, height = 12, flags = type(flags) == 'string' and flags or '' }
						hasRussian = hasRussian or alphabet == 'russian'
					end
				end
			end
		end
		if hasRussian then
			return members, sourceName
		end
	end
	return {}, nil
end

local function Width(fontString)
	local method = fontString.GetUnboundedStringWidth and 'GetUnboundedStringWidth' or 'GetStringWidth'
	local ok, width = Call(fontString, method)
	return ok and Num(width, 1) or nil
end

local function FontNote(r)
	local plain = r.plainLater or r.plainNow
	local family = r.familyLater or r.familyNow
	local verdict = 'unclear'
	if family and family > 0 and plain == 0 then
		verdict = 'the family draws Cyrillic and the plain Latin font does not'
	elseif family and family > 0 then
		verdict = 'the family draws Cyrillic (the plain font did too, so the control proves less)'
	elseif family == 0 then
		verdict = 'the family drew nothing'
	end
	return string.format('family from %s with %d alphabets; Cyrillic width plain %s, family %s; %s', tostring(r.source), r.members or 0, tostring(plain), tostring(family), verdict)
end

local function CheckS10()
	local r = {}
	if not CreateFontFamily then
		return Result('skipped', 'CreateFontFamily is missing', r)
	end
	local members, source = FamilyMembers()
	r.members, r.source = #members, source
	if #members == 0 then
		return Result('partial', 'no game font family with a Cyrillic member was found', r)
	end
	local name = ((P.host and P.host.globalPrefix) or 'Plates') .. 'ProbeFontFamily'
	local family = _G[name]
	if not family then
		local ok, made = Try(CreateFontFamily, name, members)
		if not ok then
			return Result('error', 'CreateFontFamily failed: ' .. made, r)
		end
		family = made or _G[name]
	end
	local f = Frames()
	if not f.plainName then
		f.plainName = f.holder:CreateFontString(nil, 'OVERLAY')
		f.plainName:SetFont(LATIN_FONT, 12, '')
		f.plainName:SetPoint('TOPLEFT', f.holder, 'TOPLEFT')
		f.familyName = f.holder:CreateFontString(nil, 'OVERLAY')
		f.familyName:SetPoint('BOTTOMLEFT', f.holder, 'BOTTOMLEFT')
	end
	r.setFamily = Step(function()
		f.familyName:SetFontObject(family)
	end)
	f.plainName:SetText(CYRILLIC)
	f.familyName:SetText(CYRILLIC)
	r.plainNow, r.familyNow = Width(f.plainName), Width(f.familyName)
	local result = Result('partial', FontNote(r), r)
	After(0.3, function()
		r.plainLater, r.familyLater = Width(f.plainName), Width(f.familyName)
		result.status = (r.familyLater and r.familyLater > 0) and 'answered' or 'partial'
		result.note = FontNote(r)
		P.log.info('Probe S10 (measured again): ' .. result.note)
	end)
	return result
end

----------------------------------------------------------------------------------------------------
-- S11: does IsSpellImportant ever answer true on the Classic family
----------------------------------------------------------------------------------------------------

local function StartSweep(result)
	if Probe.sweeping then
		result.status = 'skipped'
		result.note = 'a sweep is already running'
		return
	end
	local fn = C_Spell and C_Spell.IsSpellImportant
	local f = Frames()
	local nextID, yes, errors, ids = 1, 0, 0, {}
	Probe.sweeping = true
	result.status = 'running'
	result.note = 'checking spell ids 1 to ' .. Probe.SWEEP_LAST .. ' in the background'
	f.sweeper:SetScript('OnUpdate', function(self)
		local last = math.min(nextID + Probe.SWEEP_STEP - 1, Probe.SWEEP_LAST)
		for id = nextID, last do
			local ok, important = pcall(fn, id)
			if not ok then
				errors = errors + 1
			elseif Secret.CanAccess(important) and important then
				yes = yes + 1
				if #ids < Probe.MAX_LIST then
					ids[#ids + 1] = id
				end
			end
		end
		nextID = last + 1
		if nextID > Probe.SWEEP_LAST then
			self:SetScript('OnUpdate', nil)
			Probe.sweeping = false
			result.checked, result.important, result.errors, result.ids = Probe.SWEEP_LAST, yes, errors, table.concat(ids, ',')
			result.status = 'answered'
			result.note = string.format('%d spell ids checked: %d important (%s), %d refused', Probe.SWEEP_LAST, yes, yes > 0 and result.ids or 'none', errors)
			P.log.info('Probe S11 sweep done: ' .. result.note)
		end
	end)
end

local function CheckS11()
	local r = { present = C_Spell ~= nil and C_Spell.IsSpellImportant ~= nil }
	if not r.present then
		return Result('skipped', 'C_Spell.IsSpellImportant is missing', r)
	end
	if P.Caps:Get('secrets') then
		return Result('skipped', 'only asked on clients without secrets; watch mode records real casts here', r)
	end
	local result = Result('running', '', r)
	StartSweep(result)
	return result
end

----------------------------------------------------------------------------------------------------
-- S12: which nameplate settings exist, their scope and the secure flag
----------------------------------------------------------------------------------------------------

local EXTRA_CVARS = {
	'nameplateShowAll',
	'nameplateShowSelf',
	'nameplateShowFriends',
	'nameplateShowFriendlyNPCs',
	'nameplateShowPersonal',
	'nameplateSize',
	'nameplateStyle',
	'nameplateGlobalScale',
	'nameplateLargerScale',
	'nameplateMinAlpha',
	'nameplateMaxAlpha',
	'nameplateMinAlphaDistance',
	'nameplateMaxAlphaDistance',
	'nameplateMinScaleDistance',
	'nameplateMaxScaleDistance',
	'nameplateSelectedAlpha',
	'nameplateNotSelectedAlpha',
	'nameplateSelfAlpha',
	'nameplateSelfScale',
	'nameplateOverlapH',
	'nameplateOverlapV',
	'nameplateOtherTopInset',
	'nameplateOtherBottomInset',
	'nameplateLargeTopInset',
	'nameplateLargeBottomInset',
	'nameplateSelfTopInset',
	'nameplateSelfBottomInset',
	'nameplateClassResourceTopInset',
	'nameplateOtherAtBase',
	'nameplateTargetBehindMaxDistance',
	'nameplateTargetRadialPosition',
	'nameplateResourceOnTarget',
	'nameplateHideHealthAndPower',
	'nameplateSimplifiedTypes',
	'nameplateSimplifiedScale',
	'nameplateShowDebuffsOnFriendly',
	'nameplateShowCastBars',
	'nameplateCastBarDisplay',
	'nameplateShowClassColor',
	'nameplateShowFriendlyClassColor',
	'nameplateShowFriendlyRealmName',
	'nameplateShowOffscreen',
	'nameplateForceShowUnitName',
	'nameplateAuraScale',
	'nameplateDebuffPadding',
	'nameplateThreatDisplay',
	'nameplateInfoDisplay',
	'nameplateFriendlyPlayerAuraDisplay',
	'nameplateShowAllPersonalAuras',
	'nameplateMotion',
	'NamePlateHorizontalScale',
	'NamePlateVerticalScale',
	'NamePlateClassificationScale',
	'ShowClassColorInNameplate',
	'ShowClassColorInFriendlyNameplate',
	'SoftTargetNameplateEnemy',
	'SoftTargetIconEnemy',
}

local function CVarInfo(name)
	local ok, value, default, account, character, locked, secure, readOnly = Try(C_CVar.GetCVarInfo, name)
	if not ok then
		return 'error: ' .. value
	end
	if value == nil then
		return nil
	end
	local scope = 'none'
	if account then
		scope = 'account'
	elseif character then
		scope = 'character'
	end
	return { v = Text(value, 40), d = Text(default, 40), scope = scope, locked = locked and true or nil, secure = secure and true or nil, readOnly = readOnly and true or nil }
end

---Up to 12 names for a log line, then how many more.
local function ListText(list)
	if #list == 0 then
		return 'none'
	end
	local shown = {}
	for i = 1, math.min(#list, 12) do
		shown[i] = list[i]
	end
	local text = table.concat(shown, ',')
	if #list > 12 then
		text = text .. string.format(' and %d more', #list - 12)
	end
	return text
end

local function CheckS12()
	local r = { exists = {}, missing = {} }
	if not (C_CVar and C_CVar.GetCVarInfo) then
		return Result('skipped', 'C_CVar.GetCVarInfo is missing', r)
	end
	local seen = {}
	local names = {}
	for _, name in ipairs(P.CVars.order) do
		local def = P.CVars.defs[name]
		names[#names + 1] = name
		for _, altName in ipairs(def and def.alt or {}) do
			names[#names + 1] = altName
		end
	end
	for _, name in ipairs(EXTRA_CVARS) do
		names[#names + 1] = name
	end
	local secure, character = {}, {}
	for _, name in ipairs(names) do
		if not seen[name] then
			seen[name] = true
			local info = CVarInfo(name)
			if type(info) == 'table' then
				r.exists[name] = info
				if info.secure then
					secure[#secure + 1] = name
				end
				if info.scope == 'character' then
					character[#character + 1] = name
				end
			elseif info then
				r.exists[name] = info
			else
				r.missing[#r.missing + 1] = name
			end
		end
	end
	r.setCVarIsWrapper = type(SetCVar) == 'function' and SetCVar ~= C_CVar.SetCVar
	local count = 0
	for _ in pairs(r.exists) do
		count = count + 1
	end
	local note = string.format('%d of %d exist; secure: %s; per character: %s; missing: %s', count, count + #r.missing, ListText(secure), ListText(character), ListText(r.missing))
	return Result('answered', note, r)
end

----------------------------------------------------------------------------------------------------
-- S13: quest lines in unit tooltips
----------------------------------------------------------------------------------------------------

local function ScanTip()
	local f = Frames()
	if not f.tip then
		local name = ((P.host and P.host.globalPrefix) or 'Plates') .. 'ProbeTooltip'
		f.tip = _G[name] or CreateFrame('GameTooltip', name, nil, 'GameTooltipTemplate')
	end
	return f.tip
end

local function TooltipDataSample(unit, t)
	local ok, data = Try(C_TooltipInfo.GetUnit, unit)
	if not ok then
		t.errors = t.errors + 1
		t.lastError = data
		return
	end
	if not Secret.CanAccess(data) then
		t.dataHidden = t.dataHidden + 1
		return
	end
	if type(data) ~= 'table' then
		t.noData = t.noData + 1
		return
	end
	local lines = data.lines
	if not Secret.CanAccess(lines) or type(lines) ~= 'table' then
		t.linesHidden = t.linesHidden + 1
		return
	end
	t.read = t.read + 1
	local objective = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective or 8
	local found = false
	for _, line in ipairs(lines) do
		if Secret.CanAccess(line) and type(line) == 'table' then
			local lineType, readable = Secret.Plain(line.type)
			if not readable then
				t.lineTypeHidden = t.lineTypeHidden + 1
			elseif lineType == objective then
				found = true
			end
		end
	end
	if found then
		t.withObjectives = t.withObjectives + 1
	end
end

local function ScanTipSample(unit, t)
	local tip = ScanTip()
	local ok, err = pcall(function()
		tip:SetOwner(WorldFrame, 'ANCHOR_NONE')
		tip:ClearLines()
		tip:SetUnit(unit)
	end)
	if not ok then
		t.errors = t.errors + 1
		t.lastError = Short(err)
		return
	end
	t.read = t.read + 1
	local found = false
	for _, region in ipairs({ tip:GetRegions() }) do
		if region.GetObjectType and region:GetObjectType() == 'FontString' then
			local text = region:GetText()
			if Secret.CanAccess(text) and type(text) == 'string' and text ~= '' then
				if string.find(text, '%d+%s*/%s*%d+') then
					found = true
					if #t.samples < 4 then
						t.samples[#t.samples + 1] = Text(text, 60)
					end
				end
			end
		end
	end
	tip:Hide()
	if found then
		t.withObjectives = t.withObjectives + 1
	end
end

local function CheckS13()
	local t = { plates = 0, read = 0, withObjectives = 0, dataHidden = 0, linesHidden = 0, lineTypeHidden = 0, noData = 0, errors = 0, identityHidden = 0, samples = {} }
	local useData = C_TooltipInfo ~= nil and C_TooltipInfo.GetUnit ~= nil
	t.path = useData and 'tooltip data' or 'tooltip text scan'
	for _, entry in ipairs(Plates(10)) do
		if entry.unit then
			t.plates = t.plates + 1
			if Secret.ShouldUnitIdentityBeSecret(entry.unit) then
				t.identityHidden = t.identityHidden + 1
			end
			if useData then
				TooltipDataSample(entry.unit, t)
			else
				ScanTipSample(entry.unit, t)
			end
		end
	end
	if t.plates == 0 then
		return Result('no data', 'no plates on screen; stand near quest mobs and run again', t)
	end
	local note = string.format(
		'%s on %d plates: read %d, with quest lines %d; data hidden %d, lines hidden %d, line types hidden %d; identity hidden %d; errors %d',
		t.path,
		t.plates,
		t.read,
		t.withObjectives,
		t.dataHidden,
		t.linesHidden,
		t.lineTypeHidden,
		t.identityHidden,
		t.errors
	)
	return Result('answered', note, t)
end

----------------------------------------------------------------------------------------------------
-- S17: pixel snapping (scales that can blur one-pixel borders)
----------------------------------------------------------------------------------------------------

local SCALE_CVARS = { 'nameplateMinScale', 'nameplateMaxScale', 'nameplateLargerScale', 'nameplateSelectedScale', 'nameplateGlobalScale', 'uiScale', 'useUiScale' }

local function CheckS17()
	local r = { cvars = {} }
	if GetPhysicalScreenSize then
		local ok, w, h = Try(GetPhysicalScreenSize)
		if ok then
			r.physicalW, r.physicalH = Num(w), Num(h)
		end
	end
	r.uiScale = Num(UIParent:GetScale(), 4)
	r.uiEffective = Num(UIParent:GetEffectiveScale(), 4)
	if r.physicalH and r.physicalH > 0 then
		r.pixelPerfect = Round(768 / r.physicalH, 4)
	end
	for _, name in ipairs(SCALE_CVARS) do
		r.cvars[name] = CVarValue(name)
	end
	local distinct, scales = {}, 0
	r.plates, r.whole, r.fraction = 0, 0, 0
	for _, entry in ipairs(Plates()) do
		local ok, effective = Call(entry.base, 'GetEffectiveScale')
		effective = ok and Num(effective, 4) or nil
		if effective and r.physicalH then
			r.plates = r.plates + 1
			if not distinct[effective] then
				distinct[effective] = true
				scales = scales + 1
			end
			local perUnit = effective * r.physicalH / 768
			if math.abs(perUnit - math.floor(perUnit + 0.5)) < 0.01 then
				r.whole = r.whole + 1
			else
				r.fraction = r.fraction + 1
			end
			r.minScale = math.min(r.minScale or effective, effective)
			r.maxScale = math.max(r.maxScale or effective, effective)
		end
	end
	r.distinctScales = scales
	local note = string.format(
		'screen %sx%s, UI scale %s (pixel perfect %s); %d plates at %d different scales (%s to %s): whole pixels per unit on %d, fractions on %d; min/max scale settings %s/%s',
		tostring(r.physicalW),
		tostring(r.physicalH),
		tostring(r.uiEffective),
		tostring(r.pixelPerfect),
		r.plates,
		scales,
		tostring(r.minScale),
		tostring(r.maxScale),
		r.whole,
		r.fraction,
		tostring(r.cvars.nameplateMinScale),
		tostring(r.cvars.nameplateMaxScale)
	)
	return Result(r.plates > 0 and 'answered' or 'partial', note, r)
end

----------------------------------------------------------------------------------------------------
-- The instant run
----------------------------------------------------------------------------------------------------

local CHECKS = {
	{ id = 'S0', fn = CheckS0 },
	{ id = 'S1', fn = CheckS1 },
	{ id = 'S2', fn = CheckS2 },
	{ id = 'S3', fn = CheckS3 },
	{ id = 'S4', fn = CheckS4 },
	{ id = 'S6', fn = ContainerTest },
	{ id = 'S7', fn = CheckS7 },
	{ id = 'S8', fn = CheckS8 },
	{ id = 'S10', fn = CheckS10 },
	{ id = 'S11', fn = CheckS11 },
	{ id = 'S12', fn = CheckS12 },
	{ id = 'S13', fn = CheckS13 },
	{ id = 'S14', fn = CheckS14 },
	{ id = 'S16', fn = CheckS16 },
	{ id = 'S17', fn = CheckS17 },
}

local function RunCheck(run, id, fn)
	local started = Now()
	local ok, result = pcall(fn, run)
	if not ok then
		result = Result('error', Short(result))
	elseif type(result) ~= 'table' then
		result = Result('error', 'the check returned nothing')
	end
	result.ms = Round(Now() - started, 2)
	run.results[id] = result
end

local function CapsState()
	local quirks = {}
	for _, name in ipairs({ 'uiParentScale', 'plainCastText', 'noRolesets' }) do
		quirks[name] = P.Caps:Quirk(name)
	end
	local overrides = P.db and P.db.global and P.db.global.capOverrides
	return P.Caps:Snapshot(), quirks, P.util.Copy(P.Caps.recorded), overrides and P.util.Copy(overrides) or nil
end

local function Header(run)
	return string.format(
		'Probe %s on %s %s (%s, interface %s) at %s: place %s, instance type %s, combat %s, restricted %s, engine on %s',
		run.kind,
		tostring(run.client),
		tostring(run.version),
		tostring(run.build),
		tostring(run.interface),
		tostring(run.stamp),
		tostring(run.place),
		tostring(run.instanceType),
		YesNo(run.inCombat),
		YesNo(run.restricted),
		YesNo(run.engineOn)
	)
end

local function LogRun(run)
	P.log.info(Header(run))
	for _, id in ipairs(Probe.ORDER) do
		local result = run.results[id]
		if result then
			P.log.info(string.format('  %s [%s] %s', id, tostring(result.status), tostring(result.note)))
		end
	end
	local blocked = run.blocked
	if type(blocked) == 'table' and #blocked > 0 then
		P.log.warning(string.format('  The game blocked %d actions during this run (first: %s from %s)', #blocked, tostring(blocked[1].fn), tostring(blocked[1].addon)))
	end
end

---Run every check that a script can answer right now, save it and write it to the log.
---@return string message Short line for chat
function Probe:Run()
	local run = Meta('run')
	run.blocked = {}
	CaptureBegin(run.blocked)
	run.caps, run.quirks, run.recorded, run.overrides = CapsState()
	for _, check in ipairs(CHECKS) do
		RunCheck(run, check.id, check.fn)
	end
	CaptureEnd()
	Keep(run)
	LogRun(run)
	return L['Probe finished. The results are saved and written to the log.']
end

----------------------------------------------------------------------------------------------------
-- Watch mode
----------------------------------------------------------------------------------------------------

local WATCH_EVENTS = {
	'NAME_PLATE_UNIT_ADDED',
	'NAME_PLATE_UNIT_REMOVED',
	'FORBIDDEN_NAME_PLATE_UNIT_ADDED',
	'UNIT_SPELLCAST_START',
	'UNIT_SPELLCAST_CHANNEL_START',
	'UNIT_SPELLCAST_EMPOWER_START',
	'UNIT_THREAT_LIST_UPDATE',
	'PLAYER_TARGET_CHANGED',
	'PLAYER_REGEN_DISABLED',
	'PLAYER_REGEN_ENABLED',
	'ADDON_RESTRICTION_STATE_CHANGED',
}

local function PlainToken(raw, unit)
	if not (Secret.CanAccess(unit) and type(unit) == 'string') then
		Count(raw, 'secretTokens')
		return nil
	end
	return unit
end

local function IsPlateToken(unit)
	return string.sub(unit, 1, 9) == 'nameplate'
end

local function TouchAllowed(w, inCombat)
	local key = inCombat and 'inCombat' or 'outOfCombat'
	return w.run.touch and not P:IsEnabled() and (w.touched[key] or 0) < Probe.TOUCH_LIMIT, key
end

---True when an anchor binding points at the frame (its relativeTo, whatever shape the table has).
local function RefersTo(anchor, frame)
	if type(anchor) ~= 'table' or not Secret.CanAccess(anchor) then
		return false
	end
	for _, value in pairs(anchor) do
		if Secret.CanAccess(value) and value == frame then
			return true
		end
	end
	return false
end

---Rebind a plate's click area to a larger frame of ours and put Blizzard's points back on the same tick.
local function TouchHitTest(base)
	local test = { inCombat = InCombat() }
	local okB, before = Call(base, 'GetHitTestPoints')
	local saved = okB and Secret.CanAccess(before) and type(before) == 'table' and before or nil
	test.before = saved and #saved or nil
	local hit = Frames().hit
	local w, h = Size(base)
	hit:ClearAllPoints()
	hit:SetPoint('CENTER', base, 'CENTER')
	hit:SetSize((w or 100) + 40, (h or 20) + 20)
	test.set = Step(function()
		base:SetAllHitTestPoints(hit)
	end)
	local okA, after = Call(base, 'GetHitTestPoints')
	if okA and Secret.CanAccess(after) and type(after) == 'table' then
		test.after = #after
		local first = after[1]
		test.bound = RefersTo(first, hit)
	end
	if saved and #saved > 0 then
		test.restore = Step(function()
			base:SetHitTestPoints(saved)
		end)
	else
		test.restore = Step(function()
			base:ClearAllHitTestPoints()
		end)
	end
	hit:ClearAllPoints()
	hit:SetPoint('CENTER', Frames().holder, 'CENTER')
	return test
end

local function HitTick(w, base, inCombat)
	local raw = w.raw
	local okC, can = Call(base, 'CanChangeHitTestPoints')
	local allowed = Answer(okC, can)
	local prefix = inCombat and 'combat' or 'calm'
	Count(raw.hit, prefix .. (allowed == true and 'Yes' or 'No'))
	-- Asking a Blizzard plate anything from a timer in combat can taint, so only touch runs do it
	if inCombat and w.run.touch then
		After(0, function()
			local okN, canNext = Call(base, 'CanChangeHitTestPoints')
			Count(raw.hit, (okN and Bool(canNext) == true) and 'nextFrameYes' or 'nextFrameNo')
		end)
	end
	local touch, key = TouchAllowed(w, inCombat)
	if touch and allowed == true and #raw.hit.tests < Probe.TOUCH_LIMIT * 2 then
		w.touched[key] = (w.touched[key] or 0) + 1
		raw.hit.tests[#raw.hit.tests + 1] = TouchHitTest(base)
	end
end

local function RolesetTick(w, base, inCombat)
	local raw = w.raw
	local uf = base.UnitFrame
	if not uf then
		Count(raw.roles, 'noUnitFrame')
		return
	end
	local allowed = AllowedOn(uf)
	local prefix = inCombat and 'combat' or 'calm'
	Count(raw.roles, prefix .. (allowed == true and 'Allowed' or (allowed == false and 'Blocked' or 'Unknown')))
	local touch = w.run.touch and not P:IsEnabled() and inCombat and #raw.roles.tests < Probe.TOUCH_LIMIT
	if not touch then
		return
	end
	local okF, forbidden = Call(uf, 'IsForbidden')
	if okF and Bool(forbidden) == true then
		return
	end
	local test = { allowed = allowed }
	local blockedBefore = #raw.blocked
	-- The Classic family has no rolesets; its suppression path (reparenting) is still tried below
	if uf.SetRolesets then
		test.set = Step(function()
			uf:SetRolesets('alwaysBlocked')
		end)
		local okR, filtered = Call(uf, 'IsRolesetFiltered')
		test.filtered = Answer(okR, filtered)
		test.clear = Step(function()
			uf:SetRolesets(nil)
		end)
	else
		test.set = 'no rolesets on this client'
	end
	local okP, parent = Call(uf, 'GetParent')
	if okP and parent then
		test.reparent = Step(function()
			uf:SetParent(Frames().hidden)
		end)
		test.reparentBack = Step(function()
			uf:SetParent(parent)
		end)
	end
	test.blocked = #raw.blocked - blockedBefore
	raw.roles.tests[#raw.roles.tests + 1] = test
end

local watchHandlers = {}

watchHandlers.NAME_PLATE_UNIT_ADDED = function(w, unit)
	local raw = w.raw
	Count(raw, 'adds')
	unit = PlainToken(raw, unit)
	if not unit then
		return
	end
	local base = P.Source.PlateForUnit(unit)
	if not base then
		Count(raw, 'lookupMissing')
		return
	end
	Count(raw, 'lookupFound')
	local inCombat = InCombat()
	HitTick(w, base, inCombat)
	RolesetTick(w, base, inCombat)
	SizeSample(raw.sizes, base, unit)
	-- Making containers in combat may be blocked (S6), so only touch runs try it
	if inCombat and w.run.touch and not raw.containersInCombat and P.Caps:Get('containers') then
		local ok, result = pcall(ContainerTest)
		raw.containersInCombat = ok and result or Result('error', Short(result))
	end
end

watchHandlers.NAME_PLATE_UNIT_REMOVED = function(w)
	Count(w.raw, 'removes')
end

watchHandlers.FORBIDDEN_NAME_PLATE_UNIT_ADDED = function(w)
	Count(w.raw, 'forbiddenAdds')
end

local function CastSample(w, unit)
	local raw = w.raw
	local casts = raw.casts
	local src = P.Source.NewLive(unit)
	local okK, kind = Try(src.CastKind, src)
	local key = okK and kind or 'unknown'
	casts.seen = casts.seen + 1
	local bucket = casts.kinds[key]
	if not bucket then
		bucket = { ok = 0, failed = 0, noDuration = 0 }
		casts.kinds[key] = bucket
	end
	local okD, present = Try(function()
		return type(src:CastDurationSecret()) ~= 'nil'
	end)
	if not (okD and present) then
		bucket.noDuration = bucket.noDuration + 1
	end
	local status = Step(function()
		ApplyTimerSecret(Frames().bar, src:CastDurationSecret())
	end)
	if status == 'ok' then
		bucket.ok = bucket.ok + 1
	else
		bucket.failed = bucket.failed + 1
		casts.lastError = status
	end
	local fn = C_Spell and C_Spell.IsSpellImportant
	local okS, spellID, readable = Try(src.SpellIDPlain, src)
	if not (okS and readable) then
		Count(raw.important, 'idHidden')
		return
	end
	if not (fn and type(spellID) == 'number') then
		return
	end
	local okI, important = Try(fn, spellID)
	local answer = Answer(okI, important)
	if answer == true then
		Count(raw.important, 'yes')
		if not w.importantSeen[spellID] and #raw.important.ids < Probe.MAX_LIST then
			w.importantSeen[spellID] = true
			raw.important.ids[#raw.important.ids + 1] = spellID
		end
	elseif answer == false then
		Count(raw.important, 'no')
	elseif answer == 'hidden' then
		Count(raw.important, 'hidden')
	else
		Count(raw.important, 'errors')
		raw.important.lastError = answer
	end
end

local function OnCastStart(w, unit)
	unit = PlainToken(w.raw, unit)
	if unit and (unit == 'player' or IsPlateToken(unit)) then
		CastSample(w, unit)
	end
end

watchHandlers.UNIT_SPELLCAST_START = OnCastStart
watchHandlers.UNIT_SPELLCAST_CHANNEL_START = OnCastStart
watchHandlers.UNIT_SPELLCAST_EMPOWER_START = OnCastStart

watchHandlers.UNIT_THREAT_LIST_UPDATE = function(w, unit)
	unit = PlainToken(w.raw, unit)
	if not (unit and IsPlateToken(unit)) then
		return
	end
	local now = GetTime and GetTime() or 0
	local last = w.threatSeen[unit]
	if last and now - last < 1 then
		return
	end
	w.threatSeen[unit] = now
	ThreatSample(unit, w.raw.threat)
	CombatSample(unit, w.raw.combat)
end

watchHandlers.PLAYER_TARGET_CHANGED = function(w)
	TargetSample(w.raw.target)
end

watchHandlers.PLAYER_REGEN_DISABLED = function(w)
	Count(w.raw, 'combatStarts')
end

watchHandlers.PLAYER_REGEN_ENABLED = function(w)
	Count(w.raw, 'combatEnds')
end

watchHandlers.ADDON_RESTRICTION_STATE_CHANGED = function(w, kind, state)
	local list = w.raw.restrictionChanges
	if #list < Probe.MAX_LIST then
		list[#list + 1] = { kind = Num(kind), state = Num(state), at = Round(GetTime and GetTime() or 0, 2), inCombat = InCombat() }
	end
end

local function Summarize(w)
	local raw, results = w.raw, w.run.results
	local hit = raw.hit
	results.S1 = Result(
		(hit.combatYes or 0) + (hit.combatNo or 0) > 0 and 'answered' or 'partial',
		string.format(
			'add tick: click area changeable in combat %d of %d, out of combat %d of %d; next frame in combat %d of %d (touch runs only); touch tests %d (see tests)',
			hit.combatYes or 0,
			(hit.combatYes or 0) + (hit.combatNo or 0),
			hit.calmYes or 0,
			(hit.calmYes or 0) + (hit.calmNo or 0),
			hit.nextFrameYes or 0,
			(hit.nextFrameYes or 0) + (hit.nextFrameNo or 0),
			#hit.tests
		),
		{ raw = 'raw.hit' }
	)
	local firstHit = hit.tests[1]
	if firstHit then
		results.S1.note = results.S1.note
			.. string.format(
				'; first touch test (in combat %s): rebind %s, points before %s after %s, bound to our frame %s, put back %s',
				YesNo(firstHit.inCombat),
				tostring(firstHit.set),
				tostring(firstHit.before),
				tostring(firstHit.after),
				YesNo(firstHit.bound),
				tostring(firstHit.restore)
			)
	end
	local roles = raw.roles
	local rolesNote = string.format(
		'protected calls on Blizzard unit frames: in combat allowed %d, blocked %d; out of combat allowed %d, blocked %d; touch tests %d',
		roles.combatAllowed or 0,
		roles.combatBlocked or 0,
		roles.calmAllowed or 0,
		roles.calmBlocked or 0,
		#roles.tests
	)
	local firstTest = roles.tests[1]
	if firstTest then
		rolesNote = rolesNote
			.. string.format('; first: set %s, cleared %s, reparent %s, blocked events %d', tostring(firstTest.set), tostring(firstTest.clear), tostring(firstTest.reparent), firstTest.blocked or 0)
	end
	results.S7 = Result((roles.combatAllowed or 0) + (roles.combatBlocked or 0) > 0 and 'answered' or 'partial', rolesNote, { raw = 'raw.roles' })
	local casts = raw.casts
	local parts = {}
	for kind, bucket in pairs(casts.kinds) do
		parts[#parts + 1] = string.format('%s %d ok/%d failed/%d without duration', kind, bucket.ok, bucket.failed, bucket.noDuration)
	end
	results.S0 = Result(
		casts.seen > 0 and 'answered' or 'no data',
		string.format('%d casts: %s; unreadable unit tokens %d; last error %s', casts.seen, #parts > 0 and table.concat(parts, ', ') or 'none', raw.secretTokens or 0, tostring(casts.lastError)),
		{ raw = 'raw.casts' }
	)
	local imp = raw.important
	results.S11 = Result(
		(imp.yes or 0) + (imp.no or 0) > 0 and 'answered' or 'no data',
		string.format(
			'cast spells checked: important %d, not %d, hidden %d, spell id hidden %d; ids %s',
			imp.yes or 0,
			imp.no or 0,
			imp.hidden or 0,
			imp.idHidden or 0,
			#imp.ids > 0 and table.concat(imp.ids, ',') or 'none'
		),
		{ raw = 'raw.important' }
	)
	results.S2 = Result(raw.threat.plates > 0 and 'answered' or 'no data', ThreatNote(raw.threat), { raw = 'raw.threat' })
	results.S16 = Result(raw.combat.plates > 0 and 'answered' or 'no data', CombatNote(raw.combat), { raw = 'raw.combat' })
	results.S4 = Result(raw.target.checks > raw.target.noTarget and 'answered' or 'no data', TargetNote(raw.target), { raw = 'raw.target' })
	results.S14 = Result(
		(raw.adds or 0) > 0 and 'answered' or 'no data',
		string.format(
			'%d plates added: plate lookup by the add token found %d, nothing %d; forbidden adds %d; removes %d',
			raw.adds or 0,
			raw.lookupFound or 0,
			raw.lookupMissing or 0,
			raw.forbiddenAdds or 0,
			raw.removes or 0
		)
	)
	results.S8 = Result(raw.sizes.minor.count + raw.sizes.other.count > 0 and 'answered' or 'no data', SizeNote(raw.sizes), { raw = 'raw.sizes' })
	if raw.containersInCombat then
		results.S6 = raw.containersInCombat
	else
		results.S6 = Result('no data', 'no plate was added in combat on a client with aura containers during a "watch touch" run')
	end
end

local function WatchEvent(event, ...)
	local w = Probe.watch
	local handler = w and watchHandlers[event]
	if handler then
		handler(w, ...)
	end
end

---Listen to plates for a while. touch also runs the checks that change Blizzard's plates for one tick.
---@param seconds? number
---@param touch? boolean
---@return string message
function Probe:Watch(seconds, touch)
	if self.watch then
		return L['The probe is already listening. Type probe stop to end it.']
	end
	seconds = math.max(10, math.min(tonumber(seconds) or self.WATCH_SECONDS, self.WATCH_MAX))
	local run = Meta('watch')
	run.seconds = seconds
	run.touch = touch and true or false
	run.done = false
	run.raw = {
		hit = { tests = {} },
		roles = { tests = {} },
		casts = { seen = 0, kinds = {} },
		important = { ids = {} },
		threat = NewThreatTally(),
		combat = NewCombatTally(),
		target = NewTargetTally(),
		sizes = NewSizeTally(),
		blocked = {},
		restrictionChanges = {},
	}
	local w = { run = run, raw = run.raw, touched = {}, threatSeen = {}, importantSeen = {} }
	self.watch = w
	Keep(run)
	CaptureBegin(run.raw.blocked)
	local missing = {}
	for _, event in ipairs(WATCH_EVENTS) do
		handlers[event] = WatchEvent
		if not Listen(event) then
			missing[#missing + 1] = event
		end
	end
	run.missingEvents = #missing > 0 and table.concat(missing, ',') or nil
	After(seconds, function()
		if Probe.watch == w then
			Probe:StopWatch()
		end
	end)
	P.log.info(
		string.format(
			'Probe: listening for %d seconds%s. Pull some enemies, change targets, and try a restricted map on clients with secrets.',
			seconds,
			run.touch and ' (touch tests on; reload afterwards)' or ''
		)
	)
	return string.format(L['The probe is listening for %d seconds.'], seconds)
end

---@return string message
function Probe:StopWatch()
	local w = self.watch
	if not w then
		return L['The probe is not listening.']
	end
	self.watch = nil
	for _, event in ipairs(WATCH_EVENTS) do
		handlers[event] = nil
		Unlisten(event)
	end
	CaptureEnd()
	local ok, err = pcall(Summarize, w)
	if not ok then
		w.run.summaryError = Short(err)
	end
	local run = w.run
	run.done = true
	run.ended = date and date('%Y-%m-%d %H:%M:%S') or ''
	run.blocked = w.raw.blocked
	run.recorded = P.util.Copy(P.Caps.recorded)
	if run.touch and run.engineOn then
		run.touchSkipped = 'the engine was on, so the touch tests were skipped; see recorded for what it found'
	end
	local saved = Saved()
	local kept = false
	for _, entry in ipairs(saved and saved.runs or {}) do
		kept = kept or entry == run
	end
	if saved and not kept then
		Keep(run)
	end
	LogRun(run)
	if run.touchSkipped then
		P.log.info('Probe: ' .. run.touchSkipped)
	elseif run.touch then
		P.log.warning('Probe: touch tests changed Blizzard plates for a moment. Reload before you play on.')
	end
	return L['The probe stopped listening. The results are saved and written to the log.']
end

----------------------------------------------------------------------------------------------------
-- Report, clear and the command
----------------------------------------------------------------------------------------------------

---Write a short summary of the newest saved results for this client to the log.
---@return string message
function Probe:Report()
	local saved = Saved()
	local runs = saved and saved.runs or {}
	if #runs == 0 then
		P.log.info('Probe: no results are saved yet')
		return L['No probe results yet.']
	end
	local client = P.Caps:Client()
	local latest = {}
	for i = #runs, 1, -1 do
		local run = runs[i]
		if type(run) == 'table' and run.client == client and run.kind and not latest[run.kind] then
			latest[run.kind] = run
		end
	end
	local any = false
	for _, kind in ipairs({ 'run', 'watch' }) do
		if latest[kind] then
			any = true
			LogRun(latest[kind])
		end
	end
	local counts = {}
	for _, run in ipairs(runs) do
		if type(run) == 'table' then
			Count(counts, tostring(run.client))
		end
	end
	local list = {}
	for name, count in pairs(counts) do
		list[#list + 1] = name .. ' ' .. count
	end
	table.sort(list)
	P.log.info('Probe: saved runs by client: ' .. table.concat(list, ', '))
	if not any then
		return L['No probe results for this game version yet.']
	end
	return L['The probe summary is in the log.']
end

---@return string message
function Probe:Clear()
	local saved = Saved()
	if saved then
		saved.runs = {}
		saved.last = nil
	end
	return L['Saved probe results were removed.']
end

local USAGE = 'probe (run the checks now), probe watch [seconds] [touch], probe stop, probe report, probe clear'

---Handle the text after the host's command word. Never errors; returns one line for chat.
---@param text? string
---@return string message
function Probe:Command(text)
	local words = {}
	for word in string.gmatch(string.lower(text or ''), '%S+') do
		words[#words + 1] = word
	end
	local action = words[1] or 'run'
	local ok, message
	if action == 'run' then
		ok, message = pcall(self.Run, self)
	elseif action == 'watch' then
		local seconds, touch
		for i = 2, #words do
			if words[i] == 'touch' then
				touch = true
			elseif tonumber(words[i]) then
				seconds = tonumber(words[i])
			end
		end
		ok, message = pcall(self.Watch, self, seconds, touch)
	elseif action == 'stop' then
		ok, message = pcall(self.StopWatch, self)
	elseif action == 'report' then
		ok, message = pcall(self.Report, self)
	elseif action == 'clear' then
		ok, message = pcall(self.Clear, self)
	else
		P.log.info('Probe commands: ' .. USAGE)
		return USAGE
	end
	if not ok then
		P.log.error('Probe ' .. action .. ' failed: ' .. Short(message))
		return L['The probe hit an error. See the log.']
	end
	return message
end
