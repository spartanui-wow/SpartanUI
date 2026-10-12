local _, ns = ...
local P = ns.Plates

-- Capability probes and per-client quirks (6.8). Features are gated by what the client can do,
-- never by "is this Retail": Forever has secrets but is not Retail, and some APIs exist on every
-- client without telling them apart. A function existing does not prove it works, so anything
-- verified broken in game goes into QUIRKS, and a probe answered by a real object (the first
-- plate, the first aura button) is stored with Caps:Record.
--
-- Probes run lazily (first Caps:Get) or all at once in P:Enable through Caps:RunProbes. They are
-- wrapped in pcall and must be safe on all six clients. Probes that need unit functions live in
-- Engine/Source.lua (the only file allowed to touch Unit* globals) and register with AddProbe.

---@class Plates.Caps
local Caps = { values = {}, probes = {}, order = {}, recorded = {}, docs = {} }
P.Caps = Caps

---Project ids. Forever reports WOW_PROJECT_CAMELOT (18), which is not always defined.
Caps.PROJECT = {
	MAINLINE = WOW_PROJECT_MAINLINE or 1,
	CLASSIC = WOW_PROJECT_CLASSIC or 2,
	TBC = WOW_PROJECT_BURNING_CRUSADE_CLASSIC or 5,
	WRATH = WOW_PROJECT_WRATH_CLASSIC or 11,
	CATA = WOW_PROJECT_CATACLYSM_CLASSIC or 14,
	FOREVER = WOW_PROJECT_CAMELOT or 18,
	MISTS = WOW_PROJECT_MISTS_CLASSIC or 19,
}

---Things verified broken (or misbehaving) in game, keyed by WOW_PROJECT_ID. Each entry forces a
---fallback path on. Mists starts with two from 9.1 (S0, S1); confirm them in game.
Caps.QUIRKS = {
	[Caps.PROJECT.MISTS] = {
		uiParentScale = true, -- SetNamePlateSize values and click/stack region scale times UIParent:GetScale()
		plainCastText = true, -- duration formatting misbehaves; cast time text by plain math
	},
}

---Quirks keyed by client name, for clients we cannot tell apart by project id. Titan has no
---local client: its entry exists so a fallback can be forced with Caps:SetOverride.
Caps.CLIENT_QUIRKS = {
	titan = {},
}

---@return integer
function Caps:Interface()
	if not self.interface then
		local version = GetBuildInfo and select(4, GetBuildInfo())
		self.interface = tonumber(version) or 0
	end
	return self.interface
end

---Short client name, for logs and data rules only. Never gate an engine feature on it.
---@return 'retail'|'forever'|'mists'|'titan'|'tbc'|'era'|'unknown'
function Caps:Client()
	if self.client then
		return self.client
	end
	local build = self:Interface()
	local project = WOW_PROJECT_ID
	local client = 'unknown'
	if build >= 110000 then
		client = 'retail'
	elseif project == self.PROJECT.FOREVER or (build >= 16000 and build < 20000) then
		client = 'forever'
	elseif build >= 50000 and build < 60000 then
		client = 'mists'
	elseif build >= 38000 and build < 39000 then
		client = 'titan'
	elseif build >= 20000 and build < 30000 then
		client = 'tbc'
	elseif build >= 10000 and build < 16000 then
		client = 'era'
	end
	self.client = client
	return client
end

---Data rules (threat numbers, rank tables), separate from engine capabilities.
Caps.Rules = setmetatable({}, {
	__index = function(_, key)
		if key == 'retail' then
			return Caps:Interface() >= 110000
		end
		return nil
	end,
})

---@param name string
---@param fn fun(): boolean
---@param doc? string One line: what the probe asks
function Caps:AddProbe(name, fn, doc)
	if not self.probes[name] then
		self.order[#self.order + 1] = name
	end
	self.probes[name] = fn
	self.docs[name] = doc
	self.values[name] = nil
end

local function Overrides()
	local db = P.db
	return db and db.global and db.global.capOverrides or nil
end

---Capability answer. Overrides (set from the dev command) win, then recorded answers from real
---objects, then the probe. Unknown names are false.
---@param name string
---@return boolean
function Caps:Get(name)
	local overrides = Overrides()
	if overrides and overrides[name] ~= nil then
		return overrides[name] and true or false
	end
	if self.recorded[name] ~= nil then
		return self.recorded[name]
	end
	local value = self.values[name]
	if value == nil then
		local probe = self.probes[name]
		value = false
		if probe then
			local ok, result = pcall(probe)
			value = ok and result and true or false
		end
		self.values[name] = value
	end
	return value
end

---Store an answer only a real object can give (the first plate's hit-test points, the first aura
---button's methods). Overrides still win.
---@param name string
---@param value boolean
function Caps:Record(name, value)
	value = value and true or false
	if self.recorded[name] ~= value then
		self.recorded[name] = value
		P.log.debug('Capability ' .. name .. ' recorded as ' .. tostring(value))
	end
end

---@param name string
---@return boolean
function Caps:Quirk(name)
	local overrides = Overrides()
	local key = 'quirk:' .. name
	if overrides and overrides[key] ~= nil then
		return overrides[key] and true or false
	end
	local byProject = self.QUIRKS[WOW_PROJECT_ID]
	if byProject and byProject[name] then
		return true
	end
	local byClient = self.CLIENT_QUIRKS[self:Client()]
	return byClient and byClient[name] and true or false
end

---Force a capability or quirk on or off (nil clears). Quirks use the name 'quirk:<name>'. This
---is the same-day escape hatch when Blizzard changes something (Decision 22).
---@param name string
---@param value boolean|nil
function Caps:SetOverride(name, value)
	local db = P.db
	if not db then
		return
	end
	db.global.capOverrides = db.global.capOverrides or {}
	db.global.capOverrides[name] = value
	if next(db.global.capOverrides) == nil then
		db.global.capOverrides = nil
	end
	self.values[name] = nil
end

---Evaluate every probe now and log one summary line.
function Caps:RunProbes()
	local on, off = {}, {}
	for _, name in ipairs(self.order) do
		self.values[name] = nil
		if self:Get(name) then
			on[#on + 1] = name
		else
			off[#off + 1] = name
		end
	end
	P.log.info(string.format('Client %s (%d). On: %s. Off: %s', self:Client(), self:Interface(), table.concat(on, ', '), table.concat(off, ', ')))
end

---Copy of every answer, for bug reports and tests.
---@return table<string, boolean>
function Caps:Snapshot()
	local out = {}
	for _, name in ipairs(self.order) do
		out[name] = self:Get(name)
	end
	return out
end

---Forget cached answers (tests, or after an override changes).
function Caps:Reset()
	P.util.Wipe(self.values)
	P.util.Wipe(self.recorded)
	self.interface = nil
	self.client = nil
end

----------------------------------------------------------------------------------------------------
-- Probes that need no frame and no unit. Engine files add the rest (timerBars, hitTest,
-- rolesets, pandemic, smoothText, spriteSheet, sliceMargins, stackingBounds, lieutenant, ...).
----------------------------------------------------------------------------------------------------

local function Has(tbl, key)
	return type(tbl) == 'table' and tbl[key] ~= nil
end

local function HasTemplate(name)
	if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo) then
		return false
	end
	return C_XMLUtil.GetTemplateInfo(name) ~= nil
end

Caps:AddProbe('secrets', function()
	return C_Secrets ~= nil and C_Secrets.HasSecretRestrictions ~= nil and C_Secrets.HasSecretRestrictions() == true
end, 'The client can hand addons secret values')
Caps:AddProbe('containers', function()
	return HasTemplate('CustomAuraContainerTemplate')
end, '12.1 aura containers exist')
Caps:AddProbe('pingable', function()
	return HasTemplate('PingableUnitFrameTemplate')
end, 'Ping template exists (an empty stub on the Classic family)')
Caps:AddProbe('tooltipData', function()
	return Has(C_TooltipInfo, 'GetUnit')
end, 'C_TooltipInfo.GetUnit (Retail and Forever)')
Caps:AddProbe('profiler', function()
	return C_AddOnProfiler ~= nil
end, 'C_AddOnProfiler for timing')
Caps:AddProbe('simplified', function()
	return Has(C_NamePlateManager, 'SetNamePlateSimplified')
end, 'The engine can shrink simplified plates')
Caps:AddProbe('hitTestInsets', function()
	return Has(C_NamePlateManager, 'SetNamePlateHitTestInsets')
end, 'Click-through insets per plate type')
Caps:AddProbe('plateSize', function()
	return Has(C_NamePlate, 'SetNamePlateSize')
end, 'One global base plate size')
Caps:AddProbe('durations', function()
	return Has(C_DurationUtil, 'CreateDuration')
end, 'Duration objects')
Caps:AddProbe('durationText', function()
	return Has(C_DurationUtil, 'CreateDurationTextBinding') and not Caps:Quirk('plainCastText')
end, 'Engine-formatted countdown text')
Caps:AddProbe('colorFromBoolean', function()
	return Has(C_CurveUtil, 'EvaluateColorValueFromBoolean')
end, 'Per-channel color choice from a secret boolean')
Caps:AddProbe('colorMixinFromBoolean', function()
	return Has(C_CurveUtil, 'EvaluateColorFromBoolean')
end, 'Whole-color choice from a secret boolean (S3 decides if it chains)')
Caps:AddProbe('colorCurves', function()
	return Has(C_CurveUtil, 'CreateColorCurve')
end, 'Color curves for health-driven colors')
Caps:AddProbe('encoding', function()
	return Has(C_EncodingUtil, 'SerializeCBOR')
		and Has(C_EncodingUtil, 'DeserializeCBOR')
		and Has(C_EncodingUtil, 'CompressString')
		and Has(C_EncodingUtil, 'DecompressString')
		and Has(C_EncodingUtil, 'EncodeBase64')
		and Has(C_EncodingUtil, 'DecodeBase64')
end, 'Native share string pipeline')
Caps:AddProbe('fontFamily', function()
	return CreateFontFamily ~= nil
end, 'Font families with per-alphabet members')
Caps:AddProbe('auraInstanceIDs', function()
	return Has(C_UnitAuras, 'GetUnitAuraInstanceIDs')
end, 'Blizzard-sorted aura lists for the Lua scan path')
Caps:AddProbe('restrictionEvents', function()
	return C_RestrictedActions ~= nil
end, 'ADDON_RESTRICTION_STATE_CHANGED and restriction queries')
Caps:AddProbe('challengeMode', function()
	return Has(C_ChallengeMode, 'IsChallengeModeActive')
end, 'Mythic+ runs can be detected')
Caps:AddProbe('forces', function()
	return Has(C_ScenarioInfo, 'GetUnitCriteriaProgressValues') and Has(C_ChallengeMode, 'IsChallengeModeActive')
end, 'Mythic+ forces per unit')
Caps:AddProbe('important', function()
	return Has(C_Spell, 'IsSpellImportant')
end, 'Important-cast flag (spell data on Classic is S11)')
Caps:AddProbe('kickCooldown', function()
	return Has(C_Spell, 'GetSpellCooldownDuration')
end, 'Cooldown as a duration object for interrupt readiness')
Caps:AddProbe('classColor', function()
	return Has(C_ClassColor, 'GetClassColor')
end, 'Class colors from a (possibly secret) class token')
Caps:AddProbe('cvarInfo', function()
	return Has(C_CVar, 'GetCVarInfo')
end, 'CVar scope and secure flags can be read')
Caps:AddProbe('cvarBitfield', function()
	return Has(C_CVar, 'SetCVarBitfield') and Has(C_CVar, 'GetCVarBitfield')
end, 'Bitfield CVars')
