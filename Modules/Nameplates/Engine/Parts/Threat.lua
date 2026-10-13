local _, ns = ...
local P = ns.Plates
local Secret = P.Secret

-- Threat display (3.1, 4, 6.4): the pure threat model (P.Threat) and the threat part (kind 'glow',
-- source 'threat'). Owner: Phase 2.
--
-- Where threat shows is a per-role choice of channels (P.Roles.ThreatOn(role, profile.threat.show)):
--   bar, border, name  drawn by the bars and text through their color lists: Colors expands
--                      '@threat' into the off-tank, pet and threat rows only on the pieces whose
--                      channel is on, under the same "When" clause (Core/Colors.lua)
--   glow               drawn here with P.GlowLib (look 'soft' unless spec.art names another)
--   size               drawn here: the plate grows in whole pixels through plate.grows.threat,
--                      eased with the target emphasis (never SetScale)
-- Defaults (3.1): tanks get the flipped palette on the bar, damage the border, healers a glow.
-- Threat only shows where profile.threat.when allows (Always / In instances / Never; default In
-- instances) and only on enemies that are not players, the same rules the color rows use.
--
-- Six states (Roles.PALETTE): safe, losing, lost, offTank (another group tank holds it), pet (your
-- pet holds it) and solo. Threat.State works them out from plain answers:
--   tanks   you hold it -> safe; else another tank -> offTank; else your pet -> pet; else losing
--           (status 2) or lost
--   others  losing (status 1) or lost (2-3) first, so "you are about to pull" is never hidden
--           behind "the tank has it"; else pet, offTank, safe
--   not in a group: solo (unless your pet holds it)
-- The glow and size channels only show states that need attention (Threat.GLOW_STATES,
-- Threat.SIZE_SHARE): a calm state draws nothing.
--
-- Secrets (S2 and friends):
--   * src:ThreatStatusPlain() hidden -> no threat glow or size on that plate, logged once (the
--     color rows do the same).
--   * a tank's (or the pet's) "is tanking" hidden while your own status is readable -> the glow
--     color and alpha are folded per channel with P.Secret.ChooseValue (C_CurveUtil
--     .EvaluateColorValueFromBoolean), so "another tank holds it" still shows without Lua ever
--     reading the answer. Size stays put while the answer is hidden (it would have to read it).
-- Events: UNIT_THREAT_LIST_UPDATE, UNIT_THREAT_SITUATION_UPDATE; messages CONTEXT_CHANGED (role,
-- place), TANKS_CHANGED, FACTS_POLLED (can attack).

---@class Plates.Threat
local Threat = {}
P.Threat = Threat

Threat.CHANNELS = { 'bar', 'border', 'name', 'glow', 'size' }

---States the glow shows, by role group. Tanks also want to see who else holds a mob.
Threat.GLOW_STATES = {
	tank = { losing = true, lost = true, offTank = true, pet = true },
	other = { losing = true, lost = true },
}

---How much of the style's target growth a plate gets in each state (size channel).
Threat.SIZE_SHARE = { losing = 0.5, lost = 1 }
---Growth used when the style has no target growth.
Threat.DEFAULT_GROW = { 12, 2 }

local EMPTY = {}

---The "When" clause id for profile.threat.when ('always' is the player-facing word for everywhere).
---@param threat table|nil profile.threat
---@return string
function Threat.When(threat)
	local when = threat and threat.when or 'instances'
	if when == 'always' then
		return 'everywhere'
	end
	return when
end

---Whether threat applies to this plate here: an enemy that is not a player, in a place the
---setting allows.
---@param facts Plates.Facts
---@param ctx Plates.Context
---@param threat table|nil profile.threat
---@return boolean
function Threat.Applies(facts, ctx, threat)
	if not facts or not facts.canAttack or facts.isPlayer then
		return false
	end
	return P.Conditions:WhenApplies(Threat.When(threat), ctx)
end

---The threat state a role sees, from plain answers (pure).
---@param role string 'tank' | 'damage' | 'healer'
---@param status integer|nil UnitThreatSituation('player', mob): 0-3, nil when not on its list
---@param inGroup boolean
---@param otherTank boolean|nil Another group tank holds it
---@param pet boolean|nil Your pet holds it
---@return string|nil state nil when there is nothing to show
function Threat.State(role, status, inGroup, otherTank, pet)
	local Roles = P.Roles
	if role == 'tank' then
		if status == 3 then
			return Roles.ThreatState(role, status, inGroup)
		end
		if otherTank then
			return 'offTank'
		end
		if pet then
			return 'pet'
		end
		return Roles.ThreatState(role, status, inGroup)
	end
	local state = Roles.ThreatState(role, status, inGroup)
	if state == 'losing' or state == 'lost' then
		return state
	end
	if pet then
		return 'pet'
	end
	if otherTank then
		return 'offTank'
	end
	return state
end

---States the glow shows for a role.
---@param role string
---@return table<string, boolean>
function Threat.GlowStates(role)
	return role == 'tank' and Threat.GLOW_STATES.tank or Threat.GLOW_STATES.other
end

---Extra plate growth for a state (size channel), in whole pixels, or nil.
---@param state string|nil
---@param style table|nil Resolved style (its target growth sets the scale)
---@return integer|nil w
---@return integer|nil h
function Threat.GrowFor(state, style)
	local share = state and Threat.SIZE_SHARE[state]
	if not share then
		return nil, nil
	end
	local target = style and style.states and style.states.target
	local grow = target and target.grow or Threat.DEFAULT_GROW
	return math.floor(grow[1] * share + 0.5), math.floor(grow[2] * share + 0.5)
end

local hiddenScratch = {}

---Read a plate's threat. Plain answers only; the units whose "is tanking" answer is hidden are
---listed so a caller can fold them through a sink.
---@param src Plates.Source
---@param ctx Plates.Context
---@return string|nil state
---@return boolean readable false when the game hides your own threat on this unit (S2)
---@return string[] hidden Group tanks whose answer is hidden (a shared list; copy to keep)
---@return boolean petHidden
function Threat.Read(src, ctx)
	local hidden = hiddenScratch
	P.util.Wipe(hidden)
	local status, readable = src:ThreatStatusPlain()
	if not readable then
		return nil, false, hidden, false
	end
	local otherTank, pet, petHidden = false, false, false
	local tanks = ctx.tanks or EMPTY
	for i = 1, #tanks do
		local holds, known = src:IsTankingPlain(tanks[i])
		if not known then
			hidden[#hidden + 1] = tanks[i]
		elseif holds then
			otherTank = true
		end
	end
	if ctx.petTank then
		local holds, known = src:IsTankingPlain('pet')
		if not known then
			petHidden = true
		elseif holds then
			pet = true
		end
	end
	return Threat.State(ctx.role or 'damage', status, ctx.inGroup and true or false, otherTank, pet), true, hidden, petHidden
end

---What the threat glow and size channels show on a plate right now, for the inspector and tests.
---@param plate Plates.Plate
---@return string|nil state
---@return string reason 'shown' | 'calm' | 'channelsOff' | 'notHere' | 'hidden'
function Threat.Describe(plate)
	local env = plate.env
	local ctx = env.ctx or P.Context
	local profile = P.db and P.db.profile or EMPTY
	local threat = type(profile.threat) == 'table' and profile.threat or EMPTY
	local on = P.Roles.ThreatOn(ctx.role or 'damage', threat.show)
	if not (on.glow or on.size) then
		return nil, 'channelsOff'
	end
	if not plate.src or not Threat.Applies(plate.facts, ctx, threat) then
		return nil, 'notHere'
	end
	local state, readable = Threat.Read(plate.src, ctx)
	if not readable then
		return nil, 'hidden'
	end
	if state and (Threat.GlowStates(ctx.role)[state] or Threat.SIZE_SHARE[state]) then
		return state, 'shown'
	end
	return state, 'calm'
end

----------------------------------------------------------------------------------------------------
-- The threat part
----------------------------------------------------------------------------------------------------

local warned = false

local function WarnHidden()
	if warned then
		return
	end
	warned = true
	P.log.info('Threat is hidden by the game here; the threat glow and size are off for those plates')
end

-- The threat widget that last set a plate's growth (weak), so a style without a threat part can
-- take the growth back (Plate:ApplyStyle does not reset parts that leave the style)
local growers = setmetatable({}, { __mode = 'k' })

---@param instant? boolean Skip the ease (unbind)
local function SetGrow(widget, w, h, instant)
	w, h = w or 0, h or 0
	if widget.growW == w and widget.growH == h then
		return
	end
	widget.growW, widget.growH = w, h
	local plate = widget.plate
	plate.grows = plate.grows or {}
	if w == 0 and h == 0 then
		plate.grows.threat = nil
		growers[plate] = nil
	else
		local vec = widget.growVec
		vec[1], vec[2] = w, h
		plate.grows.threat = vec
		growers[plate] = widget
	end
	plate:ApplyEmphasis(instant or false)
end

---Fold the hidden "is tanking" answers into the glow color and alpha (never read in Lua).
local function FoldHidden(widget, src, state, glows, palette, hidden, petHidden)
	local base = state and glows[state] and palette[state] or nil
	local rSecret, gSecret, bSecret, aSecret
	if base then
		rSecret, gSecret, bSecret, aSecret = base[1], base[2], base[3], base[4] or 1
	else
		local off = palette.offTank
		rSecret, gSecret, bSecret, aSecret = off[1], off[2], off[3], 0
	end
	if petHidden then
		local color = palette.pet
		local heldSecret = src:IsTankingSecret('pet')
		rSecret = Secret.ChooseValue(heldSecret, color[1], rSecret)
		gSecret = Secret.ChooseValue(heldSecret, color[2], gSecret)
		bSecret = Secret.ChooseValue(heldSecret, color[3], bSecret)
		aSecret = Secret.ChooseValue(heldSecret, color[4] or 1, aSecret)
	end
	local color = palette.offTank
	for i = 1, #hidden do
		local heldSecret = src:IsTankingSecret(hidden[i])
		rSecret = Secret.ChooseValue(heldSecret, color[1], rSecret)
		gSecret = Secret.ChooseValue(heldSecret, color[2], gSecret)
		bSecret = Secret.ChooseValue(heldSecret, color[3], bSecret)
		aSecret = Secret.ChooseValue(heldSecret, color[4] or 1, aSecret)
	end
	P.GlowLib.SetColorSecret(widget.glow, rSecret, gSecret, bSecret, aSecret)
	P.GlowLib.Show(widget.glow)
end

local function Refresh(widget, src)
	local GlowLib = P.GlowLib
	local plate = widget.plate
	local ctx = plate.env.ctx or P.Context
	local profile = P.db and P.db.profile or EMPTY
	local threat = type(profile.threat) == 'table' and profile.threat or EMPTY
	local role = ctx.role or 'damage'
	local on = P.Roles.ThreatOn(role, threat.show)
	local glowOn, sizeOn = on.glow == true, on.size == true
	if not (glowOn or sizeOn) or not Threat.Applies(plate.facts, ctx, threat) then
		GlowLib.Hide(widget.glow)
		SetGrow(widget, 0, 0)
		return
	end
	local state, readable, hidden, petHidden = Threat.Read(src, ctx)
	if not readable then
		WarnHidden()
		GlowLib.Hide(widget.glow)
		SetGrow(widget, 0, 0)
		return
	end
	-- Hidden answers only matter where they could change a tank's state
	local unsure = role == 'tank' and (#hidden > 0 or petHidden) and state ~= 'safe' and state ~= 'offTank' and state ~= 'pet'
	if sizeOn and not unsure then
		SetGrow(widget, Threat.GrowFor(state, plate.style))
	else
		SetGrow(widget, 0, 0)
	end
	if not glowOn then
		GlowLib.Hide(widget.glow)
		return
	end
	local palette = P.Roles.Palette(profile.colorBlind, threat.colors)
	local glows = Threat.GlowStates(role)
	if unsure then
		FoldHidden(widget, src, state, glows, palette, hidden, petHidden)
		return
	end
	local color = state and glows[state] and palette[state]
	if color then
		GlowLib.SetColor(widget.glow, color[1], color[2], color[3], color[4] or 1)
		GlowLib.Show(widget.glow)
	else
		GlowLib.Hide(widget.glow)
	end
end

-- A style without that threat part takes its growth back; a threat part in the new style (another
-- part id) works its growth out again
P:On('STYLE_APPLIED', function(plate)
	local widget = growers[plate]
	if not widget or widget.active then
		return
	end
	SetGrow(widget, 0, 0, true)
	for i = 1, #plate.active do
		local other = plate.active[i]
		if other.impl.id == 'threat' and plate.src then
			other.growW, other.growH = 0, 0
			Refresh(other, plate.src)
		end
	end
end, 'Threat')

P.Parts:Register({
	id = 'threat',
	kinds = { 'glow' },
	priority = 10,
	match = function(spec)
		return spec.source == 'threat'
	end,
	events = { 'UNIT_THREAT_LIST_UPDATE', 'UNIT_THREAT_SITUATION_UPDATE' },
	messages = { 'CONTEXT_CHANGED', 'TANKS_CHANGED', 'FACTS_POLLED' },
	reasons = { colors = true },
	Create = function(plate)
		local holder = CreateFrame('Frame', nil, plate.art)
		return { frame = holder, glow = P.GlowLib.Create(holder), textures = {}, growW = 0, growH = 0, growVec = { 0, 0 } }
	end,
	Layout = function(widget, spec, ctx)
		local anchor = spec.anchor
		local region = ctx:Region(anchor and anchor[2] or 'plate')
		local x, y = anchor and anchor[4] or 0, anchor and anchor[5] or 0
		widget.frame:ClearAllPoints()
		widget.frame:SetPoint('TOPLEFT', region, 'TOPLEFT', x, y)
		widget.frame:SetPoint('BOTTOMRIGHT', region, 'BOTTOMRIGHT', x, y)
		local GlowLib = P.GlowLib
		GlowLib.Layout(widget.glow, widget.frame, GlowLib.Opts(GlowLib.LookFor(spec), spec.size, spec.art, spec.blend, spec.animate), ctx)
		widget.textures = widget.glow.textures
		if widget.plate.src then
			Refresh(widget, widget.plate.src)
		end
	end,
	Update = function(widget, src)
		Refresh(widget, src)
	end,
	Reset = function(widget)
		P.GlowLib.Reset(widget.glow)
		if widget.growW ~= 0 or widget.growH ~= 0 then
			SetGrow(widget, 0, 0, true)
		end
	end,
})
