local _, ns = ...
local P = ns.Plates
local L = P.L
local Secret = P.Secret
local BarLib = P.BarLib
local Scheduler = P.Scheduler

-- Cast bar (kind 'cast', 4): fill and time, spell name and icon, the cannot-interrupt shield,
-- the cast target in class color, the "aimed at you" frame, the important-cast glow, the
-- interrupt-ready tint (the 'cast' color list), the kick mark, "Interrupted by NAME", the
-- interrupted or failed flash, the fade out, and lifting the cast above other plates.
--
-- Pieces (all inside widget.content, which is hidden between casts; the plate owns the holder):
--   bar         StatusBar; filled by StatusBar:SetTimerDuration from src:CastDurationSecret()
--               where Caps 'timerBars' holds. Fallbacks (S0): when the game refuses the timer
--               (Caps:Record('timerBars', false)) or the client has no duration object, a fill
--               from plain cast times on the shared scheduler (one ease per cast, never an
--               OnUpdate); when even the times are hidden, a full bar that does not move.
--   time text   a duration text binding (Caps 'durationText', which Mists' plainCastText quirk
--               turns off) with a numeric rule formatter; otherwise plain math from
--               src:CastTimesPlain() on a shared 0.1 s task; blank when neither is possible.
--   shield, aimed  textures faded by P.Secret.SetAlphaFromBoolean (always 1, 0)
--   important   an orange P.GlowLib glow (look 'important') around the bar, shown through
--               GlowLib.ShowWhenSecret from src:IsImportantSecret() (S11 on the Classic family)
--   target      UnitSpellTargetName text, colored by C_ClassColor.GetClassColor (the color table
--               is indexed only after Secret.CanIndex; white otherwise)
--   kick        the mark where the player's interrupt comes back (spec.kickMark; spec.kickFill
--               also tints the part of the bar after it). Two hidden status bars: the first
--               holds the cast's elapsed time, the second (anchored to the first one's fill
--               edge) the interrupt's remaining cooldown, both over the cast's total time and
--               both set at the same moment, so the mark at the second fill edge sits where the
--               cooldown ends; nothing is read. The frame holding them fades out for casts that
--               cannot be interrupted, and the mark fades once the interrupt is ready, checked by
--               one shared 0.1 s task that runs only while marks are shown. Plain clients and
--               previews place the mark by math. Hidden past the end of the cast (clipped).
-- Channels a unit does not report: when UNIT_SPELLCAST_CHANNEL_START arrives and the unit gives
-- no channel info (older Classic clients did this for other units), the length comes from
-- P.Data.ClassicChannels and the plain path draws it. Only on clients without secrets.
-- spec.above lifts the cast into a frame at HIGH strata under UIParent while it shows, anchored
-- across parents to the holder and kept at the plate's scale and alpha (SetIgnoreParentScale),
-- because plates draw as whole units and no strata inside one can rise above a neighbor.
-- This part sets the plate's 'casting' state while a cast shows (fades included).
-- spec.enemies / spec.friends pick the plates that show casts.

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
	'UNIT_SPELLCAST_INTERRUPTIBLE',
	'UNIT_SPELLCAST_NOT_INTERRUPTIBLE',
}

local START = { UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_EMPOWER_START = true }
local RETIME = { UNIT_SPELLCAST_DELAYED = true, UNIT_SPELLCAST_CHANNEL_UPDATE = true, UNIT_SPELLCAST_EMPOWER_UPDATE = true }
local FLAGS = { UNIT_SPELLCAST_INTERRUPTIBLE = true, UNIT_SPELLCAST_NOT_INTERRUPTIBLE = true }
-- Payload places (after the unit) of castBarID (NeverSecret) and interruptedBy in stop events
local STOP = {
	UNIT_SPELLCAST_STOP = { bar = 4 },
	UNIT_SPELLCAST_FAILED = { bar = 4, outcome = 'failed' },
	UNIT_SPELLCAST_INTERRUPTED = { bar = 5, by = 4, outcome = 'interrupted' },
	UNIT_SPELLCAST_CHANNEL_STOP = { bar = 5, by = 4 },
	UNIT_SPELLCAST_EMPOWER_STOP = { bar = 6, by = 5, complete = 4 },
}

local ART = {
	shield = { atlas = 'nameplates-InterruptShield', file = 'Interface\\CastingBar\\UI-CastingBar-Small-Shield' },
	aimed = { atlas = 'ui-hud-nameplates-targetedbyenemy' },
}
local COLOR = {
	interrupted = { 0.85, 0.2, 0.2, 1 },
	failed = { 0.5, 0.5, 0.5, 1 },
	important = { 1, 0.55, 0.1, 1 },
	aimed = { 1, 0.3, 0.3, 1 },
	kick = { 0.3, 0.85, 0.35, 1 },
}

local FADE_TIME = 0.2 -- a finished cast fades out
local HOLD_TIME = 0.5 -- the interrupted or failed flash stays this long, then fades
local FLASH_FADE = 0.3
local TEXT_TICK = 0.1
local KICK_TICK = 0.1
local LIFT_TICK = 0.1
local MARK_WIDTH = 2
local KICK_FILL_ALPHA = 0.35
-- Anchor points that let a bar without its own width stretch to the part it hangs from
local STRETCH = { TOP = { 'TOPLEFT', 'TOPRIGHT' }, BOTTOM = { 'BOTTOMLEFT', 'BOTTOMRIGHT' } }
local PREVIEW_KICK_AT = 0.7 -- where previews draw the kick mark (fraction of the bar)

local Cast = { textActive = setmetatable({}, { __mode = 'k' }), kickActive = setmetatable({}, { __mode = 'k' }), liftActive = setmetatable({}, { __mode = 'k' }) }
P.CastBar = Cast

----------------------------------------------------------------------------------------------------
-- Probes (frame methods; evaluated in P:Enable or on first use)
----------------------------------------------------------------------------------------------------

P.Caps:AddProbe('castLift', function()
	if not (CreateFrame and UIParent) then
		return false
	end
	local frame = CreateFrame('Frame')
	return frame.SetIgnoreParentScale ~= nil and frame.SetFrameStrata ~= nil
end, 'Casts can be lifted above other plates (SetIgnoreParentScale)')
P.Caps:AddProbe('clipFrames', function()
	if not CreateFrame then
		return false
	end
	return CreateFrame('Frame').SetClipsChildren ~= nil
end, 'Frames can clip their children (kick mark past the end of a cast)')

----------------------------------------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------------------------------------

local function NOOP() end
local NO_FONT = {} -- read only
local scratchTimes = {} -- plain cast times read once, never kept

local function Now()
	return P.services.GetTime()
end

---The game's own translated text (its cast bar words) when it has it, else ours.
---@param name string Global string name
---@param fallback string
---@return string
local function GameText(name, fallback)
	local text = _G[name]
	if type(text) == 'string' and text ~= '' then
		return text
	end
	return fallback
end

local function SetArt(texture, art)
	local atlas = art.atlas
	if atlas and texture.SetAtlas and C_Texture and C_Texture.GetAtlasInfo then
		local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
		if ok and info then
			texture:SetAtlas(atlas)
			return true
		end
	end
	texture:SetTexture(art.file or BarLib.WHITE)
	return art.file ~= nil
end

---Color a font string by a possibly hidden class token (C_ClassColor accepts secrets). The game may
---hand back a table addon code must not index (contract 9): then the text turns plain white, or
---keeps its color when `keep` is set, instead of breaking the cast update.
---@param fontString table
---@param classSecret any
---@param keep? boolean
local function SetClassTextColorSecret(fontString, classSecret, keep)
	local colorSecret
	if type(classSecret) ~= 'nil' and C_ClassColor and C_ClassColor.GetClassColor then
		colorSecret = C_ClassColor.GetClassColor(classSecret)
	end
	if not Secret.CanIndex(colorSecret) then
		if not keep then
			fontString:SetTextColor(1, 1, 1, 1)
		end
		return
	end
	local rSecret, gSecret, bSecret = Secret.ColorChannels(colorSecret, 1, 1, 1)
	fontString:SetTextColor(rSecret, gSecret, bSecret, 1)
end

local function SetReverse(bar, on)
	if bar.SetReverseFill then
		bar:SetReverseFill(on)
	elseif bar.SetFillStyle and Enum and Enum.StatusBarFillStyle then
		bar:SetFillStyle(on and Enum.StatusBarFillStyle.Reverse or Enum.StatusBarFillStyle.Standard)
	end
end

---Hostile plates (can attack, or reaction 1-3) take spec.enemies, the rest spec.friends.
---@param widget table
---@return boolean
local function ShowsFor(widget)
	local facts = widget.plate.facts or {}
	local reaction = facts.reaction
	local hostile = facts.canAttack == true or (type(reaction) == 'number' and reaction <= 3)
	if hostile then
		return widget.spec.enemies ~= false
	end
	return widget.spec.friends == true
end

---Plain time text: one decimal under 10 seconds, whole seconds above.
---@param seconds number
---@return string
function Cast.FormatSeconds(seconds)
	if seconds < 0 then
		seconds = 0
	end
	if seconds < 10 then
		return string.format('%.1f', seconds)
	end
	return string.format('%d', math.floor(seconds))
end

local formatter
---A numeric formatter for duration text bindings, or nil where the client has none.
---@return table|nil
function Cast.Formatter()
	if formatter == nil then
		formatter = false
		local util = C_StringUtil
		if util and util.CreateNumericRuleFormatter then
			local ok, made = pcall(util.CreateNumericRuleFormatter)
			if ok and made and made.SetBreakpoints then
				local set = pcall(made.SetBreakpoints, made, {
					{ threshold = 0, step = 0.1, format = '%.1f' },
					{ threshold = 10, step = 1, format = '%d' },
				})
				formatter = set and made or false
			end
		end
		if not formatter and util and util.CreateSecondsFormatter then
			local ok, made = pcall(util.CreateSecondsFormatter)
			formatter = ok and made or false
		end
	end
	return formatter or nil
end

---Make the formatter again on next use (tests, or a client that gained the API).
function Cast.ForgetFormatter()
	formatter = nil
end

---A binding refused the rule formatter: use the game's seconds formatter from now on (cast bars
---and cast time text share it). Returns it, or nil when the client has none.
---@return table|nil
function Cast.UseSecondsFormatter()
	local util = C_StringUtil
	local made
	if util and util.CreateSecondsFormatter then
		local ok, result = pcall(util.CreateSecondsFormatter)
		made = ok and result or nil
	end
	if formatter and formatter ~= made then
		P.log.info('Cast times use the game seconds format here')
	end
	formatter = made or false
	return made
end

----------------------------------------------------------------------------------------------------
-- Shared tasks (one each, running only while something needs them)
----------------------------------------------------------------------------------------------------

---A number that changes exactly when Cast.FormatSeconds' text does (tenths under 10 seconds,
---whole seconds above), so the shared tick writes the text only when it changes.
---@param seconds number
---@return integer
local function SecondsKey(seconds)
	if seconds < 0 then
		seconds = 0
	end
	if seconds < 10 then
		return math.floor(seconds * 10 + 0.5)
	end
	return 1000 + math.floor(seconds)
end

---Plain time text. The tick passes no `force` and skips writing a text that would not change.
---@param widget table
---@param force? boolean
local function TimeTextPlain(widget, force)
	local times = widget.times
	if not times then
		return
	end
	local now = Now()
	local total = times.finish - times.start
	local remaining = times.finish - now
	local format = widget.spec.timeFormat
	local elapsed = math.min(now - times.start, total)
	local key = SecondsKey(format == 'elapsed' and elapsed or remaining)
	if not force and key == widget.timeKey then
		return
	end
	widget.timeKey = key
	if format == 'elapsed' then
		widget.time:SetText(Cast.FormatSeconds(elapsed))
	elseif format == 'both' then
		widget.time:SetText(Cast.FormatSeconds(remaining) .. ' / ' .. Cast.FormatSeconds(total))
	else
		widget.time:SetText(Cast.FormatSeconds(remaining))
	end
end

local function TickText()
	local any = false
	for widget in pairs(Cast.textActive) do
		any = true
		TimeTextPlain(widget)
	end
	if not any then
		Scheduler:Cancel('cast.text')
	end
end

local function WatchText(widget, on)
	Cast.textActive[widget] = on or nil
	if on and not Scheduler:IsRunning('cast.text') then
		Scheduler:Every('cast.text', TEXT_TICK, TickText)
	end
end

local KickTick

local function WatchKick(widget, on)
	Cast.kickActive[widget] = on or nil
	if on and not Scheduler:IsRunning('cast.kick') then
		Scheduler:Every('cast.kick', KICK_TICK, KickTick)
	end
end

local SyncLift

local function WatchLift(widget, on)
	Cast.liftActive[widget] = on or nil
	if on and not Scheduler:IsRunning('cast.lift') then
		Scheduler:Every('cast.lift', LIFT_TICK, function()
			local any = false
			for lifted in pairs(Cast.liftActive) do
				any = true
				SyncLift(lifted)
			end
			if not any then
				Scheduler:Cancel('cast.lift')
			end
		end)
	end
end

----------------------------------------------------------------------------------------------------
-- Kick mark
----------------------------------------------------------------------------------------------------

---The interrupt's cooldown as a duration object (true ignores the global cooldown), or nil.
---@param spell integer|nil
---@return any cooldownSecret
local function KickCooldownSecret(spell)
	if P.Driver and P.Driver.active and P.Context.kickDurationSpell == spell then
		return P.Context.kickDuration
	end
	if not spell or not (C_Spell and C_Spell.GetSpellCooldownDuration) then
		return nil
	end
	return C_Spell.GetSpellCooldownDuration(spell, true)
end

---Remaining cooldown from a cooldown duration object (possibly secret).
---@param cooldownSecret any
---@return any remainingSecret
local function KickRemainingSecret(cooldownSecret)
	-- np-lint: allow secret-use duration objects are engine objects; their getters return values only sinks see
	return cooldownSecret:GetRemainingDuration()
end

---Whether the interrupt is ready, from a cooldown duration object (possibly secret).
---@param cooldownSecret any
---@return any readySecret
local function KickReadySecret(cooldownSecret)
	-- np-lint: allow secret-use duration objects are engine objects; their getters return values only sinks see
	return cooldownSecret:IsZero()
end

---Total and elapsed time of a cast duration object; both may be secret.
---@param durationSecret any
---@return any totalSecret
---@return any elapsedSecret
local function CastPartsSecret(durationSecret)
	if not (durationSecret.GetTotalDuration and durationSecret.GetElapsedDuration) then -- np-lint: allow secret-use method presence on an engine object
		return nil, nil
	end
	-- np-lint: allow secret-use duration objects are engine objects; their getters return values only sinks see
	return durationSecret:GetTotalDuration(), durationSecret:GetElapsedDuration()
end

local function HideKick(widget)
	widget.kick:Hide()
	widget.kickMode = nil
	WatchKick(widget, false)
end

local function KickSpell(widget)
	local ctx = widget.plate.env.ctx or P.Context
	return ctx.kickSpell
end

---Fill textures snap to whole pixels by default, which makes the sum of the two kick bars jump
---by a pixel as values change. Turn snapping off again after every fill direction change (the
---game makes a new fill texture with snapping on).
local function Unsnap(bar)
	local fill = bar:GetStatusBarTexture()
	if fill and fill.SetSnapToPixelGrid then
		fill:SetSnapToPixelGrid(false)
		if fill.SetTexelSnappingBias then
			fill:SetTexelSnappingBias(0)
		end
	end
end

---The kick fill covers the part of the bar after the mark (where the interrupt is ready): from
---`edge` (a region and its point) to the bar's end in the direction the cast runs.
local function PlaceFill(widget, drains, region, point, x)
	local fill = widget.kickParts.fill
	fill:ClearAllPoints()
	if not widget.spec.kickFill then
		fill:Hide()
		return
	end
	local bar = widget.bar
	fill:SetPoint('TOP', bar, 'TOP', 0, 0)
	fill:SetPoint('BOTTOM', bar, 'BOTTOM', 0, 0)
	if drains then
		fill:SetPoint('LEFT', bar, 'LEFT', 0, 0)
		fill:SetPoint('RIGHT', region, point, x or 0, 0)
	else
		fill:SetPoint('LEFT', region, point, x or 0, 0)
		fill:SetPoint('RIGHT', bar, 'RIGHT', 0, 0)
	end
	fill:Show()
end

local function Orient(widget, drains)
	local kick = widget.kickParts
	SetReverse(kick.positioner, drains)
	SetReverse(kick.marker, drains)
	Unsnap(kick.positioner)
	Unsnap(kick.marker)
	kick.marker:ClearAllPoints()
	kick.mark:ClearAllPoints()
	local fillPositioner = kick.positioner:GetStatusBarTexture()
	local fillMarker = kick.marker:GetStatusBarTexture()
	if drains then
		kick.marker:SetPoint('RIGHT', fillPositioner, 'LEFT', 0, 0)
		kick.mark:SetPoint('CENTER', fillMarker, 'LEFT', 0, 0)
		PlaceFill(widget, true, fillMarker, 'LEFT')
	else
		kick.marker:SetPoint('LEFT', fillPositioner, 'RIGHT', 0, 0)
		kick.mark:SetPoint('CENTER', fillMarker, 'RIGHT', 0, 0)
		PlaceFill(widget, false, fillMarker, 'RIGHT')
	end
end

---Place the mark by plain math: `at` is the fraction along the bar from the left.
local function PlaceMark(widget, at, drains)
	local kick = widget.kickParts
	kick.positioner:Hide()
	kick.marker:Hide()
	kick.mark:ClearAllPoints()
	local x = math.floor(at * (widget.barWidth or 0) + 0.5)
	kick.mark:SetPoint('CENTER', widget.bar, 'LEFT', x, 0)
	kick.mark:SetAlpha(1)
	PlaceFill(widget, drains, widget.bar, 'LEFT', x)
	kick.fill:SetAlpha(KICK_FILL_ALPHA)
end

---Fade the mark (and the fill) once the interrupt is ready: a possibly-secret answer.
local function ShowKickReadySecret(widget, cooldownSecret)
	local kick = widget.kickParts
	local readySecret = KickReadySecret(cooldownSecret)
	Secret.SetAlphaFromBoolean(kick.mark, readySecret, 0, 1)
	Secret.SetAlphaFromBoolean(kick.fill, readySecret, 0, KICK_FILL_ALPHA)
end

---Put the kick mark where the interrupt comes back during this cast, or hide it. `refresh` is a
---later check during the same cast (the interrupt was used or came back): a missing cooldown
---answer then keeps the mark where it is instead of making it blink.
---@param widget table
---@param src Plates.Source
---@param refresh? boolean
local function ApplyKick(widget, src, refresh)
	local spec = widget.spec
	if not spec.kickMark or widget.state ~= 'casting' or not P.Caps:Get('kickCooldown') then
		HideKick(widget)
		return
	end
	local drains = widget.kind == 'channel'
	Secret.SetAlphaFromBoolean(widget.kick, src:NotInterruptibleSecret(), 0, 1)
	if src.isSample then
		-- Previews draw the mark only for samples that say the interrupt is cooling down
		if not (src.sample and src.sample.kickReady == false) then
			HideKick(widget)
			return
		end
		widget.kick:Show()
		PlaceMark(widget, drains and (1 - PREVIEW_KICK_AT) or PREVIEW_KICK_AT, drains)
		widget.kickMode = 'preview'
		return
	end
	local spell = KickSpell(widget)
	local cooldownSecret = KickCooldownSecret(spell)
	if type(cooldownSecret) == 'nil' then
		if not (refresh and widget.kickMode == 'bars' and spell == widget.kickSpell) then
			HideKick(widget)
		end
		return
	end
	-- Ready now (and the game says so): nothing to mark, no task to run
	local ready, readyReadable = Secret.Plain(KickReadySecret(cooldownSecret))
	if readyReadable and ready == true then
		HideKick(widget)
		return
	end
	local remainingSecret = KickRemainingSecret(cooldownSecret)
	local kick = widget.kickParts
	-- Chained bars: nothing is read, the engine places the mark. Both values are taken now, as a
	-- pair, so their sum stays the moment the interrupt comes back.
	local durationSecret = widget.durationSecret
	if type(durationSecret) ~= 'nil' and type(remainingSecret) ~= 'nil' then
		local totalSecret, elapsedSecret = CastPartsSecret(durationSecret)
		if type(totalSecret) ~= 'nil' and type(elapsedSecret) ~= 'nil' then
			Orient(widget, drains)
			kick.positioner:SetMinMaxValues(0, totalSecret)
			kick.positioner:SetValue(elapsedSecret)
			kick.marker:SetMinMaxValues(0, totalSecret)
			kick.marker:SetValue(remainingSecret)
			kick.positioner:Show()
			kick.marker:Show()
			ShowKickReadySecret(widget, cooldownSecret)
			widget.kick:Show()
			widget.kickMode = 'bars'
			widget.kickSpell = spell
			WatchKick(widget, true)
			return
		end
	end
	-- Plain math (clients without secrets, or when the duration object cannot help)
	local times = widget.times
	local remaining, readable = Secret.Plain(remainingSecret)
	if not times then
		local start, finish, timesReadable = src:CastTimesPlain()
		if timesReadable and start and finish then
			times = scratchTimes
			times.start, times.finish = start, finish
		end
	end
	if not (times and readable and type(remaining) == 'number' and times.finish > times.start) then
		HideKick(widget)
		return
	end
	local readyAt = Now() + remaining
	local at = (readyAt - times.start) / (times.finish - times.start)
	if remaining <= 0 or at <= 0 or at >= 1 then
		HideKick(widget)
		return
	end
	widget.kick:Show()
	PlaceMark(widget, drains and (1 - at) or at, drains)
	widget.kickMode = 'plain'
	widget.kickSpell = spell
	widget.kickReadyAt = readyAt
	WatchKick(widget, true)
end

KickTick = function()
	local any = false
	local now = Now()
	for widget in pairs(Cast.kickActive) do
		any = true
		if widget.kickMode == 'bars' then
			local cooldownSecret = KickCooldownSecret(widget.kickSpell)
			-- A missing answer keeps the mark as it is (a passing read miss, not a reason to blink)
			if type(cooldownSecret) ~= 'nil' then
				local ready, readable = Secret.Plain(KickReadySecret(cooldownSecret))
				if readable and ready == true then
					-- Ready for the rest of this cast unless the interrupt is used, which sends
					-- KICK_READY_CHANGED and places the mark again
					HideKick(widget)
				else
					ShowKickReadySecret(widget, cooldownSecret)
				end
			end
		elseif widget.kickMode == 'plain' then
			if now >= (widget.kickReadyAt or 0) then
				HideKick(widget)
			end
		else
			WatchKick(widget, false)
		end
	end
	if not any then
		Scheduler:Cancel('cast.kick')
	end
end

----------------------------------------------------------------------------------------------------
-- Lift above other plates
----------------------------------------------------------------------------------------------------

local function PlateScale(widget)
	local scale, readable = Secret.Plain(widget.frame:GetEffectiveScale())
	if readable and type(scale) == 'number' and scale > 0 then
		return scale
	end
	return nil
end

---The alpha the cast would have on the plate (our fades and the game's own plate alpha, such
---as plates behind walls), or nil when it cannot be read: a "When" fade drawn from a hidden answer
---gives the fader a hidden alpha, and GetEffectiveAlpha then errors or answers with a secret. A cast
---whose plate alpha cannot be read stays in its plate, so it fades with it.
---@return number|nil
local function PlateAlpha(widget)
	local frame = widget.frame
	if not frame.GetEffectiveAlpha then
		return widget.plate.emA or 1
	end
	local ok, value = pcall(frame.GetEffectiveAlpha, frame)
	if not ok then
		return nil
	end
	local alpha, readable = Secret.Plain(value)
	if readable and type(alpha) == 'number' then
		return alpha
	end
	return nil
end

local Unlift

---Keep the lifted cast at the plate's scale and alpha (plates scale with distance), and out of
---sight while the holder is not visible.
SyncLift = function(widget)
	local lift = widget.lift
	if not (lift and widget.lifted) then
		WatchLift(widget, false)
		return
	end
	local scale = PlateScale(widget)
	if scale and scale ~= widget.liftScale then
		widget.liftScale = scale
		lift:SetScale(scale)
	end
	local alpha = PlateAlpha(widget)
	if not alpha then
		Unlift(widget)
		return
	end
	if alpha ~= widget.liftAlpha then
		widget.liftAlpha = alpha
		lift:SetAlpha(alpha)
	end
	local visible = Secret.Plain(widget.frame:IsVisible())
	lift:SetShown(visible ~= false)
end

Unlift = function(widget)
	if not widget.lifted then
		return
	end
	widget.lifted = nil
	WatchLift(widget, false)
	local content = widget.content
	content:SetParent(widget.frame)
	local strata = widget.frame.GetFrameStrata and widget.frame:GetFrameStrata()
	if type(strata) == 'string' then
		content:SetFrameStrata(strata)
	end
	local level = Secret.Plain(widget.frame:GetFrameLevel())
	if type(level) == 'number' then
		content:SetFrameLevel(level + 1)
	end
	content:ClearAllPoints()
	content:SetAllPoints(widget.frame)
	if widget.lift then
		widget.lift:Hide()
	end
end

local function Lift(widget)
	if not widget.spec.above or widget.plate.isPreview or widget.lifted or not P.Caps:Get('castLift') then
		return
	end
	local scale = PlateScale(widget)
	local alpha = PlateAlpha(widget)
	if not scale or not alpha then
		return
	end
	local lift = widget.lift
	if not lift then
		lift = CreateFrame('Frame', nil, UIParent)
		lift:SetFrameStrata('HIGH')
		lift:SetIgnoreParentScale(true)
		lift:SetSize(1, 1)
		lift:EnableMouse(false)
		if lift.EnableMouseMotion then
			lift:EnableMouseMotion(false)
		end
		widget.lift = lift
	end
	-- Matches the plate's own scale so the cast keeps its size in whole plate pixels
	widget.liftScale = scale
	lift:SetScale(scale)
	widget.liftAlpha = alpha
	lift:SetAlpha(alpha)
	lift:Show()
	local content = widget.content
	content:SetParent(lift)
	content:SetFrameStrata('HIGH')
	content:ClearAllPoints()
	content:SetAllPoints(widget.frame)
	widget.lifted = true
	WatchLift(widget, true)
end

----------------------------------------------------------------------------------------------------
-- Drawing a cast
----------------------------------------------------------------------------------------------------

---A next-frame slot per widget and job ('loop', 'clear', 'fade'), made once in Create, so a cast
---that ends makes no closures.
local function LaterSlot(widget, id)
	local slot = { id = id }
	slot.run = function()
		local fn = slot.fn
		slot.fn = nil
		if fn and widget.gen == slot.gen then
			fn()
		end
	end
	return slot
end

---Run fn on the next frame unless a new cast or a clear came first. Ease callbacks hand their
---work here: adding eases from inside the scheduler's own ease loop is not safe.
local function Later(widget, what, fn)
	local slot = widget.later[what]
	slot.gen, slot.fn = widget.gen, fn
	Scheduler:NextFrame(slot.id, slot.run)
end

---Plain cast times on a table the widget keeps (a cast start makes no table).
local function SetTimes(widget, start, finish)
	local times = widget.timesBuf
	if not times then
		times = {}
		widget.timesBuf = times
	end
	times.start, times.finish = start, finish
	widget.times = times
end

local function StopTiming(widget)
	Scheduler:StopEase(widget.fillId)
	Scheduler:StopEase(widget.loopId)
	Scheduler:StopEase(widget.fadeId)
	WatchText(widget, false)
	if widget.binding and widget.bindingOn then
		widget.binding:SetEnabled(false)
		widget.bindingOn = nil
	end
end

---Hide everything right away (no cast, unbind, a plate that stops showing casts).
local function Clear(widget)
	widget.gen = (widget.gen or 0) + 1
	StopTiming(widget)
	HideKick(widget)
	P.GlowLib.Reset(widget.important)
	Unlift(widget)
	widget.content:Hide()
	widget.content:SetAlpha(1)
	widget.time:SetText('')
	widget.state = nil
	widget.fake = nil
	widget.times = nil
	widget.durationSecret = nil
	widget.castBarID = nil
	local plate = widget.plate
	if plate.states.casting then
		plate:SetState('casting', false)
	end
end

local function ApplyColor(widget)
	local env = widget.plate.env
	P.Colors:Apply(P.Colors:Program(widget.spec.colors or 'cast', env.ctx), env, widget.bar, 'SetStatusBarColor')
end

---The fill when the timer cannot run: plain times on a per-frame ease, else a still full bar.
local function FillPlain(widget, drains)
	local bar, times = widget.bar, widget.times
	if not times then
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(1)
		return
	end
	local start, finish = times.start, times.finish
	bar:SetMinMaxValues(start, finish)
	widget.fillStart, widget.fillFinish, widget.fillDrains = start, finish, drains
	widget.fillApply()
	local left = finish - Now()
	if left > 0 then
		-- The ease is only the per-frame tick; the value comes from the clock, so it stays linear
		Scheduler:Ease(widget.fillId, 0, 1, left, widget.fillApply)
	end
end

local function StartTimer(widget, durationSecret, direction)
	local interpolation = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0
	-- np-lint: allow secret-use pcall around a documented sink; a refusal is the S0 spike outcome
	local ok, err = pcall(widget.bar.SetTimerDuration, widget.bar, durationSecret, interpolation, direction)
	if not ok then
		P.Caps:Record('timerBars', false)
		P.log.warning('Cast bars cannot use the game timer here; using cast times instead (' .. tostring(err) .. ')')
	end
	return ok
end

local function ApplyFill(widget, src)
	local drains = widget.kind == 'channel'
	local durationSecret = widget.durationSecret
	if type(durationSecret) ~= 'nil' and P.Caps:Get('timerBars') then
		local directions = Enum and Enum.StatusBarTimerDirection
		local direction = directions and (drains and directions.RemainingTime or directions.ElapsedTime) or (drains and 1 or 0)
		-- np-lint: allow secret-use StartTimer only hands the duration object to SetTimerDuration
		if StartTimer(widget, durationSecret, direction) then
			return
		end
	end
	FillPlain(widget, drains)
end

-- formatter -> { elapsed = parts, both = parts }: the SetTextFormat lists, made once per formatter
local formatParts = setmetatable({}, { __mode = 'k' })

---Point a binding at the time format. False when the client refuses the formatter.
---@return boolean ok
local function BindingFormat(binding, format, made)
	local property = Enum and Enum.DurationTextBindingProperty
	if format == 'remaining' or not (property and binding.SetTextFormat) then
		return (pcall(binding.SetFormatter, binding, made))
	end
	local parts = formatParts[made]
	if not parts then
		parts = {
			elapsed = { { property = property.ElapsedDuration, formatter = made } },
			both = { { property = property.RemainingDuration, formatter = made }, { property = property.TotalDuration, formatter = made } },
		}
		formatParts[made] = parts
	end
	if format == 'elapsed' then
		return (pcall(binding.SetTextFormat, binding, '{}', parts.elapsed))
	end
	return (pcall(binding.SetTextFormat, binding, '{} / {}', parts.both))
end

local function ApplyTime(widget, src)
	local time = widget.time
	if not widget.spec.timeText then
		time:SetText('')
		return
	end
	local durationSecret = widget.durationSecret
	local made = P.Caps:Get('durationText') and Cast.Formatter() or nil
	if type(durationSecret) ~= 'nil' and made and C_DurationUtil and C_DurationUtil.CreateDurationTextBinding then
		local binding = widget.binding
		if not binding then
			binding = C_DurationUtil.CreateDurationTextBinding()
			binding:SetFontString(time)
			binding:SetExpiredText('')
			binding:SetZeroDurationText('')
			widget.binding = binding
		end
		local formatted = BindingFormat(binding, widget.spec.timeFormat, made)
		if not formatted then
			-- The rule formatter was refused: the game's seconds format, else plain text below
			local seconds = Cast.UseSecondsFormatter()
			formatted = seconds ~= nil and BindingFormat(binding, widget.spec.timeFormat, seconds)
		end
		if formatted then
			binding:SetDuration(durationSecret)
			binding:SetEnabled(true)
			widget.bindingOn = true
			return
		end
	end
	if widget.times then
		TimeTextPlain(widget, true)
		WatchText(widget, true)
		return
	end
	time:SetText('')
end

local function ApplyTarget(widget, src)
	local target = widget.target
	if not widget.spec.target then
		target:SetText('')
		return
	end
	local show, readable = src:ShowSpellTargetPlain()
	if readable and show == false then
		target:SetText('')
		return
	end
	local nameSecret = src:SpellTargetNameSecret()
	if type(nameSecret) == 'nil' then
		target:SetText('')
		return
	end
	target:SetText(nameSecret)
	SetClassTextColorSecret(target, src:SpellTargetClassSecret())
end

---Shield, important glow, aimed frame, colors and the kick frame's alpha: everything that changes
---when a cast becomes (or stops being) interruptible.
local function ApplyFlags(widget, src)
	local spec = widget.spec
	if spec.shield then
		Secret.SetAlphaFromBoolean(widget.shield, src:NotInterruptibleSecret(), 1, 0)
	else
		widget.shield:SetAlpha(0)
	end
	local important, importantReadable = false, true
	if spec.important and (src.isSample or P.Caps:Get('important')) then
		important, importantReadable = src:IsImportantPlain()
	end
	if importantReadable and important ~= true then
		-- A plain "no" stops the glow's pulse too; only a hidden answer keeps it running unseen
		P.GlowLib.Hide(widget.important, true)
	else
		P.GlowLib.ShowWhenSecret(widget.important, src:IsImportantSecret())
	end
	if spec.aimedAtMe then
		Secret.SetAlphaFromBoolean(widget.aimed, src:AimedAtMeSecret(), 1, 0)
	else
		widget.aimed:SetAlpha(0)
	end
	Secret.SetAlphaFromBoolean(widget.kick, src:NotInterruptibleSecret(), 0, 1)
	ApplyColor(widget)
end

local function ApplyName(widget, src)
	local name = widget.name
	name:SetTextColor(1, 1, 1, 1)
	if not widget.spec.nameText then
		name:SetText('')
		return
	end
	if widget.fake then
		name:SetText(widget.fake.name or '')
		return
	end
	local nameSecret = src:CastNameSecret()
	if type(nameSecret) == 'nil' then
		name:SetText('')
	else
		name:SetText(nameSecret)
	end
end

local function ApplyIcon(widget, src)
	if widget.spec.icon == 'none' then
		return
	end
	if widget.fake then
		widget.icon:SetTexture(widget.fake.icon)
		return
	end
	widget.icon:SetTexture(src:CastIconSecret())
end

local Start

---Previews loop their sample cast: start again when the loop ends.
local function LoopSample(widget, src)
	local times = widget.times
	if not times then
		return
	end
	local left = times.finish - Now()
	if left <= 0 then
		return
	end
	Scheduler:Ease(widget.loopId, 0, 1, left, NOOP, function()
		Later(widget, 'loop', function()
			if widget.plate.src == src and widget.state == 'casting' then
				Start(widget, src)
			end
		end)
	end)
end

---Begin drawing the cast the source reports now (or a fake Era channel already in widget.fake).
Start = function(widget, src)
	widget.gen = (widget.gen or 0) + 1
	StopTiming(widget)
	local fake = widget.fake
	widget.kind = fake and 'channel' or src:CastKind() or 'cast'
	local barID = not fake and Secret.Plain(src:CastBarID()) or nil
	widget.castBarID = type(barID) == 'number' and barID or nil
	widget.durationSecret = nil
	widget.times = nil
	if fake then
		SetTimes(widget, fake.start, fake.finish)
	else
		widget.durationSecret = src:CastDurationSecret()
		local start, finish, readable = src:CastTimesPlain()
		if readable and type(start) == 'number' and type(finish) == 'number' and finish > start then
			SetTimes(widget, start, finish)
		end
	end
	widget.state = 'casting'
	local content = widget.content
	content:SetAlpha(1)
	content:Show()
	ApplyName(widget, src)
	ApplyIcon(widget, src)
	ApplyFill(widget, src)
	ApplyTime(widget, src)
	ApplyTarget(widget, src)
	ApplyFlags(widget, src)
	ApplyKick(widget, src)
	Lift(widget)
	if not widget.plate.states.casting then
		widget.plate:SetState('casting', true)
	end
	if src.isSample then
		LoopSample(widget, src)
	end
end

---Try the Era fallback: a channel start for a unit that reports no channel.
local function StartFake(widget, src, spellID)
	-- Clients with secrets report every channel (and their lengths differ from Classic's)
	if P.Caps:Get('secrets') then
		return false
	end
	local id = Secret.Plain(spellID)
	local seconds = P.Data.ClassicChannels and P.Data.ClassicChannels:Duration(id)
	if not seconds then
		return false
	end
	local name, icon
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, id)
		if ok and type(info) == 'table' then
			name, icon = info.name, info.iconID
		end
	end
	local now = Now()
	widget.fake = { start = now, finish = now + seconds, name = name, icon = icon }
	Start(widget, src)
	return true
end

local function FadeOut(widget, from, duration)
	Scheduler:Ease(widget.fadeId, from, 0, duration, widget.fadeApply, widget.fadeDone)
end

---The cast ended: done (fade), failed or interrupted (flash, hold, fade). `interrupter` is the
---event's interruptedBy GUID; it may be secret, so only type() and Source.InterrupterSecret see it.
local function Finish(widget, outcome, interrupter)
	StopTiming(widget)
	HideKick(widget)
	local bar = widget.bar
	widget.fake = nil
	widget.shield:SetAlpha(0)
	P.GlowLib.Hide(widget.important, true)
	widget.aimed:SetAlpha(0)
	widget.time:SetText('')
	if outcome == 'done' then
		widget.state = 'done'
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(widget.kind == 'channel' and 0 or 1)
		FadeOut(widget, 1, FADE_TIME)
		return
	end
	widget.state = outcome
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	local color = COLOR[outcome] or COLOR.interrupted
	bar:SetStatusBarColor(color[1], color[2], color[3], color[4])
	local name = widget.name
	if outcome == 'failed' then
		name:SetText(GameText('FAILED', L['Failed']))
	else
		local nameSecret, classSecret
		if widget.spec.interrupter ~= false then
			nameSecret, classSecret = P.Source.InterrupterSecret(interrupter)
		end
		if type(nameSecret) == 'nil' then
			name:SetText(GameText('INTERRUPTED', L['Interrupted']))
		else
			name:SetFormattedText(GameText('SPELL_INTERRUPTED_BY', L['Interrupted by %s']), nameSecret)
			SetClassTextColorSecret(name, classSecret, true)
		end
	end
	local content = widget.content
	content:SetAlpha(1)
	Scheduler:Ease(widget.fadeId, 0, 1, HOLD_TIME, NOOP, widget.holdDone)
end

local function EventBarID(info, ...)
	if not info.bar then
		return nil
	end
	local id = Secret.Plain((select(info.bar, ...)))
	return type(id) == 'number' and id or nil
end

local function OnStop(widget, src, event, ...)
	local info = STOP[event]
	if not widget.state then
		return
	end
	-- A late event for an older cast
	local id = EventBarID(info, ...)
	if id and widget.castBarID and id ~= widget.castBarID then
		return
	end
	-- A new cast already runs: show it instead
	if not widget.fake and src:CastKind() then
		Start(widget, src)
		return
	end
	if widget.fake and event ~= 'UNIT_SPELLCAST_CHANNEL_STOP' then
		return
	end
	local interrupter
	if info.by then
		interrupter = select(info.by, ...)
		-- A readable empty GUID names nobody (the game's own bar treats it like a missing one)
		local guid, readable = Secret.Plain(interrupter)
		if readable and guid == '' then
			interrupter = nil
		end
	end
	local outcome = info.outcome
	if not outcome then
		outcome = type(interrupter) ~= 'nil' and 'interrupted' or 'done'
		if info.complete and outcome == 'done' then
			-- An empower that stopped before it was done was broken off, as the game's own bar shows it
			local complete, readable = Secret.Plain((select(info.complete, ...)))
			if readable and complete == false then
				outcome = 'interrupted'
			end
		end
	end
	if widget.state ~= 'casting' then
		-- Already ending: only an interrupt may replace a failed flash (it names who did it)
		if not (outcome == 'interrupted' and widget.state == 'failed') then
			return
		end
	end
	Finish(widget, outcome, interrupter)
end

----------------------------------------------------------------------------------------------------
-- Part
----------------------------------------------------------------------------------------------------

local function Overlay(parent, layer)
	local texture = parent:CreateTexture(nil, layer or 'OVERLAY')
	texture:SetAlpha(0)
	return texture
end

P.Parts:Register({
	id = 'cast',
	kinds = { 'cast' },
	events = CAST_EVENTS,
	messages = { 'KICK_READY_CHANGED' },
	Create = function(plate)
		local holder = CreateFrame('Frame', nil, plate.art)
		local content = CreateFrame('Frame', nil, holder)
		content:SetAllPoints(holder)
		content:Hide()
		local important = P.GlowLib.Create(content)
		local bar = BarLib.Create(content)
		bar:SetAllPoints(content)
		local icon = content:CreateTexture(nil, 'ARTWORK')
		local overlay = CreateFrame('Frame', nil, bar)
		overlay:SetAllPoints(bar)
		local aimed = Overlay(overlay)
		local shield = Overlay(overlay)
		local name = overlay:CreateFontString(nil, 'OVERLAY')
		local time = overlay:CreateFontString(nil, 'OVERLAY')
		local target = overlay:CreateFontString(nil, 'OVERLAY')
		-- Kick mark: a frame the size of the bar that clips its children
		local kick = CreateFrame('Frame', nil, bar)
		kick:SetAllPoints(bar)
		if kick.SetClipsChildren then
			kick:SetClipsChildren(true)
		end
		kick:Hide()
		local positioner = CreateFrame('StatusBar', nil, kick)
		positioner:SetAllPoints(bar)
		positioner:SetStatusBarTexture(BarLib.WHITE)
		positioner:GetStatusBarTexture():SetAlpha(0)
		local marker = CreateFrame('StatusBar', nil, kick)
		marker:SetStatusBarTexture(BarLib.WHITE)
		marker:GetStatusBarTexture():SetAlpha(0)
		local fill = kick:CreateTexture(nil, 'ARTWORK')
		fill:SetTexture(BarLib.WHITE)
		fill:Hide()
		local mark = kick:CreateTexture(nil, 'OVERLAY')
		mark:SetTexture(BarLib.WHITE)
		local widget = {
			frame = holder,
			content = content,
			bar = bar,
			icon = icon,
			overlay = overlay,
			name = name,
			time = time,
			target = target,
			shield = shield,
			important = important,
			aimed = aimed,
			kick = kick,
			kickParts = { positioner = positioner, marker = marker, mark = mark, fill = fill },
			textures = { bar.bg },
		}
		local key = 'cast:' .. tostring(widget)
		widget.key = key
		-- Ids, slots and callbacks made once, so casts starting and ending make no closures
		widget.fillId, widget.loopId, widget.fadeId = key .. 'fill', key .. 'loop', key .. 'fade'
		widget.later = { loop = LaterSlot(widget, key .. 'loop'), clear = LaterSlot(widget, key .. 'clear'), fade = LaterSlot(widget, key .. 'fade') }
		widget.fillApply = function()
			local start, finish = widget.fillStart, widget.fillFinish
			local now = math.min(math.max(Now(), start), finish)
			bar:SetValue(widget.fillDrains and (start + finish - now) or now)
		end
		widget.fadeApply = function(value)
			content:SetAlpha(value)
		end
		widget.clearNow = function()
			Clear(widget)
		end
		widget.fadeDone = function()
			Later(widget, 'clear', widget.clearNow)
		end
		widget.flashOut = function()
			FadeOut(widget, 1, FLASH_FADE)
		end
		widget.holdDone = function()
			Later(widget, 'fade', widget.flashOut)
		end
		SetArt(shield, ART.shield)
		if not SetArt(aimed, ART.aimed) then
			aimed:SetVertexColor(COLOR.aimed[1], COLOR.aimed[2], COLOR.aimed[3], 0.6)
			aimed:SetBlendMode('ADD')
		end
		-- The bar can follow what it hangs from (target growth): keep the kick bars at its width
		holder:SetScript('OnSizeChanged', function(_, w, h)
			local width, height = Secret.Plain(w), Secret.Plain(h)
			if type(width) == 'number' and width > 0 and type(height) == 'number' and height > 0 then
				widget.barWidth, widget.measuredWidth = width, width
				marker:SetSize(width, height)
			end
		end)
		-- A lifted cast lives outside the plate: hide it with the plate and bring it back with it
		holder:SetScript('OnHide', function()
			if widget.lifted and widget.lift then
				widget.lift:Hide()
			end
		end)
		holder:SetScript('OnShow', function()
			if widget.lifted then
				SyncLift(widget)
			end
		end)
		return widget
	end,
	Layout = function(widget, spec, ctx)
		local width = spec.width or ctx.width
		local height = spec.height or 8
		local holder = widget.frame
		local anchor = spec.anchor
		local from = anchor and STRETCH[anchor[1]]
		local to = anchor and STRETCH[anchor[3] or anchor[1]]
		if not spec.width and from and to then
			-- No width of its own and hung above or below something: as wide as that part
			local region = ctx:Region(anchor[2])
			holder:ClearAllPoints()
			holder:SetPoint(from[1], region, to[1], anchor[4] or 0, anchor[5] or 0)
			holder:SetPoint(from[2], region, to[2], anchor[4] or 0, anchor[5] or 0)
			holder:SetHeight(height)
			-- The width the holder last measured is still right when this layout keeps its size
			-- (OnSizeChanged then does not fire again, for example a re-layout of the grown
			-- target plate); before the first measure, the width of the part it hangs from
			local regionSpec = ctx.style and ctx.style.parts and ctx.style.parts[anchor[2]]
			width = widget.measuredWidth or (regionSpec and BarLib.LayoutWidth(regionSpec, ctx.plate, ctx.width)) or ctx.plate.emW or ctx.width
		else
			holder:SetSize(width, height)
			ctx:Anchor(holder, anchor)
		end
		if not widget.lifted then
			widget.content:ClearAllPoints()
			widget.content:SetAllPoints(holder)
		end
		local bar = widget.bar
		BarLib.Style(bar, spec, ctx)
		widget.barWidth = width

		local icon = widget.icon
		local iconSize = (spec.iconSize and spec.iconSize > 0) and spec.iconSize or height
		icon:ClearAllPoints()
		if spec.icon == 'none' then
			icon:Hide()
		else
			icon:SetSize(iconSize, iconSize)
			if spec.icon == 'right' then
				icon:SetPoint('BOTTOMLEFT', bar, 'BOTTOMRIGHT', 1, 0)
			else
				icon:SetPoint('BOTTOMRIGHT', bar, 'BOTTOMLEFT', -1, 0)
			end
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			icon:Show()
		end

		local shield = widget.shield
		shield:ClearAllPoints()
		local shieldW = math.max(8, math.floor(height * 1.2 + 0.5))
		local shieldH = math.max(10, math.floor(height * 1.5 + 0.5))
		shield:SetSize(shieldW, shieldH)
		if spec.icon == 'none' then
			shield:SetPoint('CENTER', bar, 'LEFT', 0, 0)
		else
			shield:SetPoint('CENTER', icon, 'CENTER', 0, 0)
		end

		local Glow = P.GlowLib
		Glow.Layout(widget.important, bar, Glow.Opts('important', math.max(3, math.floor(height * 0.5 + 0.5))), ctx)
		local glowColor = Glow.SOURCE_COLORS.importantCast or COLOR.important
		Glow.SetColor(widget.important, glowColor[1], glowColor[2], glowColor[3], glowColor[4] or 1)
		widget.aimed:ClearAllPoints()
		widget.aimed:SetPoint('TOPLEFT', bar, 'TOPLEFT', -4, 4)
		widget.aimed:SetPoint('BOTTOMRIGHT', bar, 'BOTTOMRIGHT', 4, -4)

		local name, time, target = widget.name, widget.time, widget.target
		ctx:ApplyFont(name, spec.font, true)
		ctx:ApplyFont(time, spec.font, false)
		local font = spec.font or NO_FONT
		local targetFont = widget.targetFont or {}
		widget.targetFont = targetFont
		targetFont.face, targetFont.size, targetFont.flags = font.face, math.max(6, (font.size or 9) - 1), font.flags
		ctx:ApplyFont(target, targetFont, true)
		time:ClearAllPoints()
		time:SetPoint('RIGHT', bar, 'RIGHT', -2, 0)
		time:SetJustifyH('RIGHT')
		name:ClearAllPoints()
		name:SetPoint('LEFT', bar, 'LEFT', 2, 0)
		name:SetPoint('RIGHT', time, 'LEFT', -2, 0)
		name:SetJustifyH('LEFT')
		if name.SetWordWrap then
			name:SetWordWrap(false)
		end
		target:ClearAllPoints()
		target:SetPoint('TOP', bar, 'BOTTOM', 0, -1)
		target:SetJustifyH('CENTER')
		name:SetShown(spec.nameText ~= false)
		time:SetShown(spec.timeText ~= false)
		target:SetShown(spec.target == true)

		local kick = widget.kickParts
		kick.marker:SetSize(width, height)
		kick.mark:SetSize(MARK_WIDTH, height)
		local mark = P.Colors.GetKind and P.Colors:GetKind('interruptReady')
		local color = mark and mark.default or COLOR.kick
		kick.mark:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
		kick.fill:SetVertexColor(color[1], color[2], color[3], 1)
		if not spec.kickFill then
			kick.fill:Hide()
		end

		if widget.lifted and not spec.above then
			Unlift(widget)
		end
	end,
	Update = function(widget, src, event, ...)
		if event == 'COLORS' then
			if widget.state == 'casting' then
				ApplyColor(widget)
			end
			return
		end
		if event == 'FULL' then
			if not ShowsFor(widget) then
				Clear(widget)
			elseif src:CastKind() then
				widget.fake = nil
				Start(widget, src)
			elseif widget.fake and Now() < widget.fake.finish then
				Start(widget, src)
			elseif widget.state == 'casting' then
				Clear(widget)
			end
			return
		end
		if START[event] then
			if not ShowsFor(widget) then
				Clear(widget)
				return
			end
			widget.fake = nil
			if src:CastKind() then
				Start(widget, src)
			elseif event == 'UNIT_SPELLCAST_CHANNEL_START' then
				StartFake(widget, src, (select(3, ...)))
			end
			return
		end
		if STOP[event] then
			OnStop(widget, src, event, ...)
			return
		end
		if widget.state ~= 'casting' then
			return
		end
		if RETIME[event] then
			if not widget.fake and src:CastKind() then
				Start(widget, src)
			end
		elseif FLAGS[event] then
			ApplyFlags(widget, src)
			ApplyKick(widget, src, true)
		else
			-- An event from the cast color list (another row's trigger)
			ApplyColor(widget)
		end
	end,
	OnMessage = function(widget, message)
		if widget.state ~= 'casting' then
			return
		end
		ApplyColor(widget)
		if message == 'KICK_READY_CHANGED' then
			local src = widget.plate.src
			if src then
				ApplyKick(widget, src, true)
			end
		end
	end,
	Reset = function(widget)
		Clear(widget)
	end,
})
