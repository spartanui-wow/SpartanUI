local _, ns = ...
local P = ns.Plates

-- Cast bar (kind 'cast') with spell icon, spell name, time, cast target, the cannot-interrupt
-- shield, the important-cast glow and the "aimed at you" mark (4). Owner: Phase 2.
--
-- Events: UNIT_SPELLCAST_START/STOP/FAILED/INTERRUPTED/DELAYED, _CHANNEL_START/UPDATE/STOP,
-- _EMPOWER_START/UPDATE/STOP, _INTERRUPTIBLE, _NOT_INTERRUPTIBLE (registered per plate).
-- Reads: src:CastKind(), src:CastBarID(), src:CastDurationSecret(), src:CastNameSecret(),
-- src:CastIconSecret(), src:NotInterruptibleSecret(), src:IsImportantSecret(),
-- src:AimedAtMeSecret(), src:SpellTargetNameSecret(), src:SpellTargetClassSecret(),
-- src:CastTimesPlain() (plain-math path).
-- Sinks: StatusBar:SetTimerDuration(duration, interpolation, direction); a duration text binding
-- (C_DurationUtil.CreateDurationTextBinding) unless P.Caps:Quirk('plainCastText') or the client
-- lacks it, then plain math from CastTimesPlain on the shared scheduler; SetText / SetTexture;
-- P.Secret.SetAlphaFromBoolean(shield, notInterruptibleSecret, 1, 0); P.Colors:Apply on the 'cast'
-- piece with 'SetStatusBarColor'; C_ClassColor.GetClassColor(targetClassSecret) into SetTextColor.
-- This part sets the plate's 'casting' state (plate:SetState('casting', on)).
-- The plate owns widget.frame (a holder that stays shown while the style has a cast bar); the
-- part shows widget.bar only while something is being cast.
-- spec.enemies / spec.friends decide which plates show it. It fades out over about 0.2 s and the
-- interrupted or failed flash fades (Scheduler:Ease). KICK_READY_CHANGED recolors it.

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

P.Parts:Register({
	id = 'cast',
	kinds = { 'cast' },
	events = CAST_EVENTS,
	messages = { 'KICK_READY_CHANGED' },
	Create = function(plate)
		local holder = CreateFrame('Frame', nil, plate.art)
		local bar = P.BarLib.Create(holder)
		bar:SetAllPoints(holder)
		bar:Hide()
		return { frame = holder, bar = bar, textures = { bar.bg } }
	end,
	Layout = function(widget, spec, ctx)
		widget.frame:SetSize(spec.width or ctx.width, spec.height or 8)
		ctx:Anchor(widget.frame, spec.anchor)
		P.BarLib.Style(widget.bar, spec, ctx)
	end,
	Update = function() end,
	Reset = function(widget)
		widget.bar:Hide()
	end,
})
