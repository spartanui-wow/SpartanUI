local _, ns = ...
local P = ns.Plates

-- Text parts (kind 'text'): name, level, healthPercent, healthValue, forces, title, threatPercent,
-- castName, castTime, castTarget. Owner: Phase 2.
--
-- Events by source: name UNIT_NAME_UPDATE; level UNIT_LEVEL; healthPercent and healthValue
-- UNIT_HEALTH, UNIT_MAXHEALTH; threatPercent UNIT_THREAT_LIST_UPDATE; forces none (read on bind);
-- cast sources the cast events.
-- Sinks: SetText, SetFormattedText, SetTextColor. Health percent: src:HealthPercentSecret() into
-- SetFormattedText('%d%%', value). Values: AbbreviateNumbers.
-- "Hide at full health" (spec.hideAtFull), never by reading a hidden value:
--   * clients without secrets: plain math from src:HealthPlain(), then a plain SetAlpha;
--   * clients with secrets: a step ColorCurve (alpha 1 below full, 0 at full) evaluated by
--     src:HealthPercentSecret(curve), handed to SetTextColor. The curve then owns the text color
--     (spec.color), so spec.colors is skipped while hideAtFull is on. SetAlpha with a secret
--     value is not used until an in-game check confirms it.
-- Fonts go through ctx:ApplyFont; sources that can show a player name (NAME_SOURCES) get a font
-- family so non-Latin names render (P.Fonts; the game's name font when families are missing).
-- Colors: spec.colors -> P.Colors:Apply(program, env, fontString, 'SetTextColor'); else spec.color.

-- Sources whose text can be a player's name
local NAME_SOURCES = { name = true, castTarget = true, title = true }

local SOURCE_EVENTS = {
	name = { 'UNIT_NAME_UPDATE' },
	level = { 'UNIT_LEVEL' },
	healthPercent = { 'UNIT_HEALTH', 'UNIT_MAXHEALTH' },
	healthValue = { 'UNIT_HEALTH', 'UNIT_MAXHEALTH' },
	threatPercent = { 'UNIT_THREAT_LIST_UPDATE' },
	castName = { 'UNIT_SPELLCAST_START', 'UNIT_SPELLCAST_STOP', 'UNIT_SPELLCAST_CHANNEL_START', 'UNIT_SPELLCAST_CHANNEL_STOP' },
	castTarget = { 'UNIT_SPELLCAST_START', 'UNIT_SPELLCAST_STOP', 'UNIT_SPELLCAST_CHANNEL_START', 'UNIT_SPELLCAST_CHANNEL_STOP' },
}

P.Parts:Register({
	id = 'text',
	kinds = { 'text' },
	events = function(spec)
		return SOURCE_EVENTS[spec.source] or {}
	end,
	Create = function(plate)
		local holder = CreateFrame('Frame', nil, plate.art)
		holder:SetSize(1, 1)
		local text = holder:CreateFontString(nil, 'OVERLAY')
		text:SetAllPoints(holder)
		return { frame = holder, text = text }
	end,
	Layout = function(widget, spec, ctx)
		local _, size = ctx:Font(spec.font)
		ctx:ApplyFont(widget.text, spec.font, NAME_SOURCES[spec.source])
		widget.text:SetJustifyH(spec.justify or 'CENTER')
		local width = (spec.width and spec.width > 0) and spec.width or ctx.width
		widget.frame:SetSize(width, size + 2)
		ctx:Anchor(widget.frame, spec.anchor)
	end,
	Update = function(widget, src)
		local spec = widget.spec
		if spec.source == 'name' then
			widget.text:SetText(src:NameSecret())
			if spec.colors then
				local env = widget.plate.env
				P.Colors:Apply(P.Colors:Program(spec.colors, env.ctx), env, widget.text, 'SetTextColor')
			end
		end
	end,
	Reset = function(widget)
		widget.text:SetText('')
	end,
})
