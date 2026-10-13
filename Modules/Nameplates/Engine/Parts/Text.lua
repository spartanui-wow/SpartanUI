local _, ns = ...
local P = ns.Plates
local L = P.L

-- Text parts (kind 'text'). One implementation draws every text source; each source is a small
-- handler below with the unit events and bus messages it needs and a Fill function.
--
-- Sources and where the data comes from (every read goes through the Source object):
--   name           src:NameSecret() into SetText; a font family so non-Latin names render (S10:
--                  the game's SystemFont_NamePlate where families are missing, see P.Fonts).
--                  Class colors for players come from the 'name' color list (readable classes).
--   nameFill       the name drawn twice: a dim copy (spec.bg) and a bright copy clipped to the
--                  fill of an invisible health bar, so the name empties as health drops. Only
--                  sinks: SetMinMaxValues / SetValue on the hidden bar; no value is read.
--   level          src:LevelPlain() (UnitEffectiveLevel, never secret); '+' for elites, the skull
--                  for bosses (level -1, a boss mob or a world boss); difficulty color by default.
--   healthPercent  plain math where health reads (Classic family, samples); else
--                  src:HealthPercentSecret() (UnitHealthPercent with CurveConstants.ScaleTo100)
--                  into SetFormattedText.
--   healthValue    AbbreviateNumbers(src:HealthSecret()) (BreakUpLargeNumbers when abbreviate is
--                  false) into SetText.
--   forces         Mythic+ forces: src:ForcesSecret() (the percent string) into SetFormattedText,
--                  only during a run (Context.challengeActive, from C_ChallengeMode).
--   title          src:TitlePlain(): an NPC's title line from its tooltip, or a player's guild.
--   threatPercent  src:ThreatPercentPlain() where the game lets us read it; else the secret
--                  value straight into SetFormattedText.
--   threatLead     your threat as a percent of the highest other threat (over 100 = you lead):
--                  src:ThreatLeadPlain(), else src:ThreatLeadSecret() into SetFormattedText.
--   castName, castTarget, castTime   the running cast; castTarget in the target's class color;
--                  castTime through a duration text binding where the client has one (and Quirk
--                  plainCastText is off), else plain math on one shared Scheduler task.
--   arena          arena opponent number (1-5) by comparing base plates (src:ArenaIndexPlain),
--                  only in arenas; re-checked on plate add, CONTEXT_CHANGED, ARENA_CHANGED (the
--                  Driver moved a number) and FACTS_POLLED.
-- "Hide at full health" (spec.hideAtFull on health text), never by reading a hidden value:
--   * health reads (Classic family, samples): plain math, then a plain SetAlpha on the text;
--   * health is secret: a curve from health to alpha (the color's alpha below full, 0 at full),
--     evaluated by the engine through src:HealthPercentSecret(curve); that alpha goes straight
--     into SetTextColor with spec.color. The curve then owns the text color, so spec.colors is
--     skipped while it is on. SetAlpha is never fed a secret (not a sink until checked in game).
-- Colors: spec.colors -> P.Colors:Apply(program, env, fontString, 'SetTextColor'); else
-- spec.color; else the source's own color (level difficulty, cast target class); else white.

---@class Plates.TextSource
---@field events string[] Unit events
---@field messages? string[] Bus messages (from MESSAGES) that refill
---@field on table<string, boolean> Events and messages that refill (built by Source)
---@field names? boolean The text can be a player's name (font family)
---@field Fill fun(widget: table, src: Plates.Source, event: string): boolean|nil true when it set the color itself

local WHITE = { 1, 1, 1, 1 }
local NAME_FILL_BG = { 0.35, 0.35, 0.35, 1 }
local SKULL = 'Interface\\TargetingFrame\\UI-TargetingFrame-Skull'

local CAST_EVENTS = {
	'UNIT_SPELLCAST_START',
	'UNIT_SPELLCAST_STOP',
	'UNIT_SPELLCAST_FAILED',
	'UNIT_SPELLCAST_INTERRUPTED',
	'UNIT_SPELLCAST_DELAYED',
	'UNIT_SPELLCAST_CHANNEL_START',
	'UNIT_SPELLCAST_CHANNEL_UPDATE',
	'UNIT_SPELLCAST_CHANNEL_STOP',
	'UNIT_SPELLCAST_EMPOWER_START',
	'UNIT_SPELLCAST_EMPOWER_UPDATE',
	'UNIT_SPELLCAST_EMPOWER_STOP',
}
local HEALTH_EVENTS = { 'UNIT_HEALTH', 'UNIT_MAXHEALTH' }

-- Bus messages a text source may use (impl.messages is one list for every source)
local CONTEXT_KEYS = { level = { playerLevel = true }, forces = { challengeActive = true, place = true }, arena = { place = true } }
local OWN_MESSAGES = { CONTEXT_CHANGED = true, FACTS_POLLED = true, ARENA_CHANGED = true }

----------------------------------------------------------------------------------------------------
-- Color helpers
----------------------------------------------------------------------------------------------------

local function Unpack(color)
	if type(color) ~= 'table' then
		return 1, 1, 1, 1
	end
	return color[1] or color.r or 1, color[2] or color.g or 1, color[3] or color.b or 1, color[4] or color.a or 1
end

---Hand a color table the engine made (a curve result, a class color) to SetTextColor. The table is
---plain; its fields may be secret and go straight to the sink.
---@param fontString table
---@param colorSecret any ColorMixin or nil
---@return boolean applied
local function SetTextColorSecret(fontString, colorSecret)
	-- A table the game forbids to index would break the cast update: use the plain color instead
	if type(colorSecret) == 'nil' or not P.Secret.CanIndex(colorSecret) then
		return false
	end
	-- np-lint: allow secret-use the engine's color table is plain; its fields go straight to SetTextColor
	fontString:SetTextColor(colorSecret.r, colorSecret.g, colorSecret.b, colorSecret.a)
	return true
end

---Class color for a possibly secret class token (C_ClassColor accepts secrets), or nil.
---@param classSecret any
---@return any colorSecret
local function ClassColorSecret(classSecret)
	if type(classSecret) == 'nil' or not (C_ClassColor and C_ClassColor.GetClassColor) then
		return nil
	end
	return C_ClassColor.GetClassColor(classSecret)
end

---Color a font string: spec.colors (color list), spec.color, the source's own color, white.
---@param widget table
---@param fontString? table default widget.text
local function ApplyColor(widget, fontString)
	local spec = widget.spec
	fontString = fontString or widget.text
	if spec.colors then
		local env = widget.plate.env
		P.Colors:Apply(P.Colors:Program(spec.colors, env.ctx), env, fontString, 'SetTextColor')
	elseif spec.color then
		fontString:SetTextColor(Unpack(spec.color))
	else
		fontString:SetTextColor(Unpack(widget.autoColor or WHITE))
	end
end

-- Curves for "hide at full health", one per text alpha
local fullCurves = {}
local fullWarned = false

---A curve from health (0 to 1) to the text's alpha: the color's own alpha below full health, 0 at
---full health. Three points so it works whether the client draws it as steps or as a line.
---@param alpha number
---@return table|nil curve
local function FullHealthCurve(alpha)
	if not (C_CurveUtil and C_CurveUtil.CreateCurve) then
		return nil
	end
	local key = string.format('%.3f', alpha)
	local curve = fullCurves[key]
	if curve == nil then
		curve = false
		local ok, made = pcall(C_CurveUtil.CreateCurve)
		if ok and made then
			made:AddPoint(0, alpha)
			made:AddPoint(0.9999, alpha)
			made:AddPoint(1, 0)
			curve = made
		end
		fullCurves[key] = curve
	end
	return curve or nil
end

---Hide health text at full health. Where health is secret the engine turns health into the
---text's alpha through a curve, and that alpha goes straight into SetTextColor with spec.color.
---Returns true when the curve now owns the text color.
---@param widget table
---@param src Plates.Source
---@return boolean ownsColor
local function HideAtFull(widget, src)
	local text = widget.text
	local health, okHealth = src:HealthPlain()
	local max, okMax = src:HealthMaxPlain()
	if okHealth and okMax and type(health) == 'number' and type(max) == 'number' then
		text:SetAlpha((max > 0 and health >= max) and 0 or 1)
		return false
	end
	text:SetAlpha(1)
	local r, g, b, a = Unpack(widget.spec.color or WHITE)
	local curve = FullHealthCurve(a)
	if curve then
		local alphaSecret = src:HealthPercentSecret(curve)
		if type(alphaSecret) ~= 'nil' then
			text:SetTextColor(r, g, b, alphaSecret)
			return true
		end
	end
	if not fullWarned then
		fullWarned = true
		P.log.info('Health text cannot hide at full health on this game version; it stays shown')
	end
	return false
end

---Level color by difficulty (the game's own helpers), or nil.
---@param level integer
---@return table|nil
local function DifficultyColor(level)
	local fn = _G.GetCreatureDifficultyColor or _G.GetQuestDifficultyColor
	if not fn then
		return nil
	end
	local ok, color = pcall(fn, level)
	if ok and type(color) == 'table' and color.r then
		return { color.r, color.g, color.b, 1 }
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- Cast time: a duration text binding, or plain math on one shared task
----------------------------------------------------------------------------------------------------

local TICK_ID = 'Text.castTime'
local ticking = setmetatable({}, { __mode = 'k' }) -- widget -> cast end time (plain seconds)
local secondsFormatter

---The cast bar's formatter (tenths under 10 seconds), shared so both cast times read the same.
---@return table|nil
local function CastFormatter()
	local castBar = P.CastBar
	return castBar and castBar.Formatter and castBar.Formatter() or nil
end

---The game's plain seconds formatter, for a binding that refuses the rule formatter.
---@return table|nil
local function SecondsFormatter()
	if secondsFormatter == nil then
		secondsFormatter = false
		local util = C_StringUtil
		if util and util.CreateSecondsFormatter then
			local ok, made = pcall(util.CreateSecondsFormatter)
			secondsFormatter = (ok and made) or false
		end
	end
	return secondsFormatter or nil
end

---Plain cast time text (tenths under 10 seconds). The shared tick skips a write whose text would
---not change; `force` writes anyway (a new cast).
---@param widget table
---@param remaining number
---@param force? boolean
local function SetRemaining(widget, remaining, force)
	local key = remaining < 10 and math.floor(remaining * 10 + 0.5) or (1000 + math.floor(remaining + 0.5))
	if not force and key == widget.castTimeKey then
		return
	end
	widget.castTimeKey = key
	if remaining < 10 then
		widget.text:SetFormattedText('%.1f', remaining)
	else
		widget.text:SetFormattedText('%.0f', remaining)
	end
end

local function Tick(now)
	for widget, finish in pairs(ticking) do
		local remaining = finish - now
		local src = widget.plate.src
		if remaining <= 0 and src and src.isSample then
			-- Sample casts loop: start the next round
			local _, nextFinish = src:CastTimesPlain()
			if nextFinish and nextFinish > now then
				ticking[widget] = nextFinish
				remaining = nextFinish - now
			end
		end
		if remaining > 0 then
			SetRemaining(widget, remaining)
		else
			ticking[widget] = nil
			widget.text:SetText('')
		end
	end
	if next(ticking) == nil then
		P.Scheduler:Cancel(TICK_ID)
	end
end

local function StopCastTime(widget)
	ticking[widget] = nil
	if widget.binding then
		widget.binding:SetEnabled(false)
	end
end

local function CastTimeBinding(widget)
	if widget.binding == nil then
		widget.binding = false
		local ok, binding = pcall(C_DurationUtil.CreateDurationTextBinding)
		if ok and binding then
			binding:SetFontString(widget.text)
			-- The rule formatter is documented as a numeric formatter; if this client refuses it,
			-- take the plain seconds one, and failing both the binding's own format
			local formatter = CastFormatter()
			if not (formatter and pcall(binding.SetFormatter, binding, formatter)) then
				formatter = SecondsFormatter()
				if formatter then
					pcall(binding.SetFormatter, binding, formatter)
				end
			end
			binding:SetZeroDurationText('')
			binding:SetExpiredText('')
			widget.binding = binding
		end
	end
	return widget.binding or nil
end

local function FillCastTime(widget, src)
	local text = widget.text
	if not src:CastKind() then
		StopCastTime(widget)
		text:SetText('')
		return
	end
	if not src.isSample and P.Caps:Get('durationText') then
		local binding = CastTimeBinding(widget)
		local durationSecret = src:CastDurationSecret()
		if binding and type(durationSecret) ~= 'nil' then
			ticking[widget] = nil
			binding:SetDuration(durationSecret)
			binding:SetEnabled(true)
			return
		end
	end
	if widget.binding then
		widget.binding:SetEnabled(false)
	end
	local _, finish, readable = src:CastTimesPlain()
	if not (readable and finish) then
		ticking[widget] = nil
		text:SetText('')
		return
	end
	ticking[widget] = finish
	SetRemaining(widget, math.max(finish - P.services.GetTime(), 0), true)
	if not P.Scheduler:IsRunning(TICK_ID) then
		P.Scheduler:Every(TICK_ID, 0.1, Tick)
	end
end

----------------------------------------------------------------------------------------------------
-- Name that fills with health
----------------------------------------------------------------------------------------------------

local function EnsureFill(widget)
	local fill = widget.fill
	if fill then
		return fill
	end
	local holder = CreateFrame('Frame', nil, widget.frame)
	holder:SetAllPoints(widget.frame)
	local bg = holder:CreateFontString(nil, 'ARTWORK')
	local bar = CreateFrame('StatusBar', nil, holder)
	bar:SetStatusBarTexture(P.BarLib.WHITE)
	bar:SetStatusBarColor(1, 1, 1, 0)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	bar:SetAllPoints(bg)
	local clip = CreateFrame('Frame', nil, holder)
	clip:SetClipsChildren(true)
	clip:SetAllPoints(bar:GetStatusBarTexture())
	local fg = clip:CreateFontString(nil, 'ARTWORK')
	fill = { holder = holder, bg = bg, bar = bar, clip = clip, fg = fg }
	widget.fill = fill
	return fill
end

local function LayoutFill(widget, spec, ctx)
	local fill = EnsureFill(widget)
	fill.holder:Show()
	local point = (spec.justify == 'LEFT' or spec.justify == 'RIGHT') and spec.justify or 'CENTER'
	for _, fontString in ipairs({ fill.bg, fill.fg }) do
		ctx:ApplyFont(fontString, spec.font, true)
		fontString:SetJustifyH(point)
		fontString:ClearAllPoints()
		fontString:SetPoint(point, widget.frame, point, 0, 0)
	end
	fill.bg:SetTextColor(Unpack(spec.bg or NAME_FILL_BG))
end

----------------------------------------------------------------------------------------------------
-- Sources
----------------------------------------------------------------------------------------------------

---@type table<string, Plates.TextSource>
local SOURCES = {}

local function Define(id, def)
	def.events = def.events or {}
	def.on = {}
	for _, event in ipairs(def.events) do
		def.on[event] = true
	end
	for _, message in ipairs(def.messages or {}) do
		def.on[message] = true
	end
	SOURCES[id] = def
end

Define('name', {
	names = true,
	events = { 'UNIT_NAME_UPDATE' },
	Fill = function(widget, src)
		widget.text:SetText(src:NameSecret())
	end,
})

Define('nameFill', {
	names = true,
	events = { 'UNIT_NAME_UPDATE', 'UNIT_HEALTH', 'UNIT_MAXHEALTH' },
	Fill = function(widget, src, event)
		local fill = widget.fill
		if not fill then
			return
		end
		if event ~= 'UNIT_HEALTH' and event ~= 'UNIT_MAXHEALTH' then
			local nameSecret = src:NameSecret()
			fill.bg:SetText(nameSecret)
			fill.fg:SetText(nameSecret)
		end
		local maxSecret = src:HealthMaxSecret()
		if type(maxSecret) ~= 'nil' then
			fill.bar:SetMinMaxValues(0, maxSecret)
		end
		local healthSecret = src:HealthSecret()
		if type(healthSecret) ~= 'nil' then
			fill.bar:SetValue(healthSecret)
		end
	end,
})

Define('level', {
	events = { 'UNIT_LEVEL', 'UNIT_CLASSIFICATION_CHANGED' },
	messages = { 'CONTEXT_CHANGED' },
	Fill = function(widget, src, event)
		local text, facts = widget.text, widget.plate.facts
		local level, readable = src:LevelPlain()
		widget.autoColor = nil
		if not readable or type(level) ~= 'number' then
			text:SetText('')
			return
		end
		local classification = facts.classification
		if event == 'UNIT_CLASSIFICATION_CHANGED' then
			classification = (src:ClassificationPlain())
		end
		if level < 0 or facts.isBoss == true or classification == 'worldboss' then
			local size = math.floor((widget.fontSize or 10) + 0.5)
			text:SetFormattedText('|T%s:%d:%d|t', SKULL, size, size)
			return
		end
		local elite = classification == 'elite' or classification == 'rareelite'
		text:SetFormattedText(elite and '%d+' or '%d', level)
		widget.autoColor = DifficultyColor(level)
	end,
})

Define('healthPercent', {
	events = HEALTH_EVENTS,
	Fill = function(widget, src)
		local text = widget.text
		local health, okHealth = src:HealthPlain()
		local max, okMax = src:HealthMaxPlain()
		if okHealth and okMax and type(health) == 'number' and type(max) == 'number' then
			if max <= 0 then
				text:SetText('')
			else
				local shown = math.floor(health / max * 100 + 0.5)
				-- Never round a hurt unit up to 100 or a living one down to 0
				if shown >= 100 and health < max then
					shown = 99
				elseif shown <= 0 and health > 0 then
					shown = 1
				end
				text:SetFormattedText('%d%%', shown)
			end
		else
			local percentSecret = src:HealthPercentSecret()
			if type(percentSecret) == 'nil' then
				text:SetText('')
			else
				text:SetFormattedText('%.0f%%', percentSecret)
			end
		end
		if widget.spec.hideAtFull then
			return HideAtFull(widget, src)
		end
	end,
})

Define('healthValue', {
	events = HEALTH_EVENTS,
	Fill = function(widget, src)
		local text = widget.text
		local healthSecret = src:HealthSecret()
		if type(healthSecret) == 'nil' then
			text:SetText('')
		elseif widget.spec.abbreviate == false and BreakUpLargeNumbers then
			text:SetText(BreakUpLargeNumbers(healthSecret))
		else
			text:SetText(AbbreviateNumbers(healthSecret))
		end
		if widget.spec.hideAtFull then
			return HideAtFull(widget, src)
		end
	end,
})

Define('forces', {
	messages = { 'CONTEXT_CHANGED' },
	Fill = function(widget, src)
		local facts = widget.plate.facts
		local text = widget.text
		if not src.isSample and (facts.isPlayer or facts.canAttack == false) then
			text:SetText('')
			return
		end
		local forcesSecret = src:ForcesSecret()
		if type(forcesSecret) == 'nil' then
			text:SetText('')
		else
			text:SetFormattedText('%s%%', forcesSecret)
		end
	end,
})

Define('title', {
	names = true,
	events = { 'UNIT_NAME_UPDATE' },
	Fill = function(widget, src)
		local title = src:TitlePlain()
		if title then
			widget.text:SetFormattedText('<%s>', title)
		else
			widget.text:SetText('')
		end
	end,
})

Define('threatPercent', {
	events = { 'UNIT_THREAT_LIST_UPDATE', 'UNIT_THREAT_SITUATION_UPDATE' },
	Fill = function(widget, src)
		local text = widget.text
		local percent, readable = src:ThreatPercentPlain()
		if readable then
			if type(percent) == 'number' and percent > 0 then
				text:SetFormattedText('%.0f%%', percent)
			else
				text:SetText('')
			end
			return
		end
		local percentSecret = src:ThreatPercentSecret()
		if type(percentSecret) == 'nil' then
			text:SetText('')
		else
			text:SetFormattedText('%.0f%%', percentSecret)
		end
	end,
})

-- Your threat as a percent of the highest threat on this enemy not counting yours, from
-- UnitThreatPercentageOfLead: above 100 while you hold it, under 100 while someone else does
-- (all six clients)
Define('threatLead', {
	events = { 'UNIT_THREAT_LIST_UPDATE', 'UNIT_THREAT_SITUATION_UPDATE' },
	Fill = function(widget, src)
		local text = widget.text
		local lead, readable = src:ThreatLeadPlain()
		if readable then
			if type(lead) == 'number' and lead > 0 then
				text:SetFormattedText('%.0f%%', lead)
			else
				text:SetText('')
			end
			return
		end
		local leadSecret = src:ThreatLeadSecret()
		if type(leadSecret) == 'nil' then
			text:SetText('')
		else
			text:SetFormattedText('%.0f%%', leadSecret)
		end
	end,
})

Define('castName', {
	events = CAST_EVENTS,
	Fill = function(widget, src)
		if src:CastKind() then
			widget.text:SetText(src:CastNameSecret())
		else
			widget.text:SetText('')
		end
	end,
})

Define('castTarget', {
	names = true,
	events = CAST_EVENTS,
	Fill = function(widget, src)
		local text = widget.text
		local show, readable = src:ShowSpellTargetPlain()
		-- Only a readable false hides it; no answer shows the name
		if not src:CastKind() or (readable and show == false) then
			text:SetText('')
			return
		end
		local nameSecret = src:SpellTargetNameSecret()
		if type(nameSecret) == 'nil' then
			text:SetText('')
			return
		end
		text:SetText(nameSecret)
		local spec = widget.spec
		if not spec.colors and not spec.color then
			return SetTextColorSecret(text, ClassColorSecret(src:SpellTargetClassSecret()))
		end
	end,
})

Define('castTime', {
	events = CAST_EVENTS,
	Fill = function(widget, src)
		FillCastTime(widget, src)
	end,
})

Define('arena', {
	messages = { 'CONTEXT_CHANGED', 'FACTS_POLLED', 'ARENA_CHANGED' },
	Fill = function(widget, src, event)
		local ctx = widget.plate.env.ctx or P.Context
		if event == 'FACTS_POLLED' and (widget.arenaIndex or ctx.place ~= 'arena') then
			return
		end
		local index
		if src.isSample or ctx.place == 'arena' then
			index = src:ArenaIndexPlain()
		end
		widget.arenaIndex = index
		if index then
			widget.text:SetFormattedText('%d', index)
		else
			widget.text:SetText('')
		end
	end,
})

----------------------------------------------------------------------------------------------------
-- Part
----------------------------------------------------------------------------------------------------

---@class Plates.TextParts
local TextParts = { SOURCES = SOURCES }
P.TextParts = TextParts

---Make the fallback seconds formatter again on next use (tests, or a client that gained the API).
function TextParts.ForgetFormatter()
	secondsFormatter = nil
end

---Why a text source may stay empty on this client, for badges in the options and designer. nil
---when it always works. Plain and safe to call any time.
---@param source string
---@return string|nil
function TextParts.Limit(source)
	if source == 'forces' then
		if not P.Caps:Get('forces') then
			return L['Not on this game version']
		end
		return L['Shows only during a Mythic+ run']
	elseif source == 'arena' then
		-- A data rule (the game has arenas or not), not an engine gate
		if P.Caps:Client() == 'era' then
			return L['This game version has no arenas']
		end
		return L['Shows only in arenas']
	elseif source == 'threatPercent' then
		return L['Empty when the game hides threat, often on bosses']
	elseif source == 'threatLead' then
		return L['Empty when you are not on its threat list. Over 100% means you hold it.']
	elseif source == 'title' then
		return L['Shows only in the open world']
	end
	return nil
end

local function ApplyShadow(fontString, font)
	if font and font.shadow then
		fontString:SetShadowColor(0, 0, 0, 1)
		fontString:SetShadowOffset(1, -1)
	else
		fontString:SetShadowOffset(0, 0)
	end
end

local NO_EVENTS = {} -- read only

P.Parts:Register({
	id = 'text',
	kinds = { 'text' },
	events = function(spec)
		local def = SOURCES[spec.source]
		return def and def.events or NO_EVENTS
	end,
	messages = function(spec)
		local def = SOURCES[spec.source]
		return def and def.messages or NO_EVENTS
	end,
	contextKeys = function(spec)
		return CONTEXT_KEYS[spec.source]
	end,
	Create = function(plate)
		local holder = CreateFrame('Frame', nil, plate.art)
		holder:SetSize(1, 1)
		local text = holder:CreateFontString(nil, 'OVERLAY')
		text:SetAllPoints(holder)
		return { frame = holder, text = text }
	end,
	Layout = function(widget, spec, ctx)
		local def = SOURCES[spec.source]
		local _, size = ctx:Font(spec.font)
		widget.fontSize = size
		local text = widget.text
		ctx:ApplyFont(text, spec.font, def and def.names or false)
		ApplyShadow(text, spec.font)
		text:SetJustifyH(spec.justify or 'CENTER')
		local width = (spec.width and spec.width > 0) and spec.width or ctx.width
		widget.frame:SetSize(width, size + 2)
		ctx:Anchor(widget.frame, spec.anchor)
		-- A part id can change source between styles: clear what the last source left behind
		StopCastTime(widget)
		widget.ownsColor, widget.autoColor, widget.arenaIndex = nil, nil, nil
		text:SetAlpha(1)
		widget.colorTarget = nil
		if spec.source == 'nameFill' then
			text:SetText('')
			text:Hide()
			LayoutFill(widget, spec, ctx)
			ApplyShadow(widget.fill.bg, spec.font)
			ApplyShadow(widget.fill.fg, spec.font)
			-- The bright copy carries the color list
			widget.colorTarget = widget.fill.fg
		else
			text:Show()
			if widget.fill then
				widget.fill.holder:Hide()
			end
		end
		if not spec.colors then
			local r, g, b, a = Unpack(spec.color or WHITE)
			text:SetTextColor(r, g, b, a)
			if widget.colorTarget then
				widget.colorTarget:SetTextColor(r, g, b, a)
			end
		end
	end,
	Update = function(widget, src, event)
		local def = SOURCES[widget.spec.source]
		if not def then
			return
		end
		if event == 'FULL' or def.on[event] then
			widget.ownsColor = def.Fill(widget, src, event) == true
		elseif OWN_MESSAGES[event] and not (widget.spec.colors and P.Colors:Program(widget.spec.colors, widget.plate.env.ctx).messages[event]) then
			-- Every text part gets these; this source does not use this one
			return
		end
		if not widget.ownsColor then
			ApplyColor(widget, widget.colorTarget)
		end
	end,
	Reset = function(widget)
		StopCastTime(widget)
		widget.text:SetText('')
		widget.text:SetAlpha(1)
		widget.ownsColor, widget.autoColor, widget.arenaIndex = nil, nil, nil
		local fill = widget.fill
		if fill then
			fill.bg:SetText('')
			fill.fg:SetText('')
			fill.bar:SetMinMaxValues(0, 1)
			fill.bar:SetValue(1)
		end
	end,
})
