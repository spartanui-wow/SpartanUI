local _, ns = ...
local P = ns.Plates
local L = P.L
local Secret = P.Secret

-- Class resource on the target plate (kind 'classPower', plan 4, Phase 5).
--
-- What it draws: the player's own points (combo points, holy power, chi, soul shards, burning
-- embers, arcane charges, essence, shadow orbs, runes) as a row of pips on the plate of the enemy
-- the player targets. Every pip is a StatusBar with SetMinMaxValues(i - 1, i) (times the fragment
-- size for shards and embers), and every pip gets the same amount, so a secret amount fills the
-- right pips without ever being read: UnitPower and GetComboPoints are
-- SecretWhenUnitPowerRestricted on Retail and Forever, even for the player. Runes are plain
-- (GetRuneCooldown) and fill as they come back, on the shared Scheduler tick.
--
-- Which resource: the first RESOURCES row that matches plain player facts
-- (Source.ReadPlayerPower: class, specialization, power type, vehicle) and lists this client. A
-- row only counts when the player's maximum for its power is above zero (holy power before level
-- 10 shows nothing yet). The number of pips and the fragment size come from the plain maximum,
-- read both as whole points and as raw fragments and compared (Scale), so a client that hands
-- back either form draws the right pips; a maximum the game hides keeps the last count shown.
-- Per client:
--   Retail    combo points (rogue, cat druid; charged points tinted), holy power, chi
--             (Windwalker), soul shards (fragments for Destruction), arcane charges (Arcane),
--             essence, runes (ready first, colored by specialization)
--   Forever   combo points on the target (rogue, cat druid)
--   Mists     combo points on the target, holy power, chi (every spec), shadow orbs (Shadow),
--             soul shards (Affliction), burning embers with fragments (Destruction), runes by type
--   Titan     combo points on the target, runes by type
--   TBC, Era  combo points on the target
-- Demonic Fury, Eclipse and Stagger are bars, not points, and are not drawn.
-- Combo points belong to the target on every client but Retail (data rule Caps.Rules.retail), read
-- with GetComboPoints('player', 'target') like the game's own combo frame (probe 'comboTarget';
-- without it the player's own combo point power is read). Quirk 'comboPointsFromPlayer' (set with
-- the cap command, quirk:comboPointsFromPlayer on) reads the player's power too: the same-day
-- escape hatch if a client changes this.
--
-- When pips show: on the target's plate only, when the target can be attacked, never while the
-- player is in a vehicle, and only when a row matches. The plate shows the part's frame (built-in
-- styles set state = 'target'); the part hides its own pip row everywhere else, so a style that
-- leaves out the state still keeps pips off other plates. When the target is known only as a
-- secret (S4), the row fades with SetAlphaFromBoolean. ClassPower:Status() gives the reason in
-- plain words when nothing can show.
--
-- Plate frames register unit events for their own unit only, so this file keeps one frame for the
-- player's power events. It is made the first time a live plate draws the part and goes quiet
-- when the engine stops. Previews read the sample (sample.classPower points, default 3) and, for
-- a player without points, draw five sample combo points so the part can still be placed.

---@class Plates.ClassPower
local ClassPower = {
	widgets = setmetatable({}, { __mode = 'k' }),
	info = {},
	lastCount = {},
	running = false,
	dirty = true,
}
P.ClassPower = ClassPower

local MAX_PIPS = 10
local WHITE = 'Interface\\Buttons\\WHITE8X8'

local PT = (Enum and Enum.PowerType) or {}
ClassPower.POWER = {
	energy = PT.Energy or 3,
	combo = PT.ComboPoints or 4,
	runes = PT.Runes or 5,
	shards = PT.SoulShards or 7,
	holy = PT.HolyPower or 9,
	chi = PT.Chi or 12,
	embers = PT.BurningEmbers or 14,
	arcane = PT.ArcaneCharges or 16,
	essence = PT.Essence or 19,
	orbs = PT.ShadowOrbs or 28,
}
local POWER = ClassPower.POWER

local SPEC = {
	arcane = SPEC_MAGE_ARCANE or 1,
	windwalker = SPEC_MONK_WINDWALKER or 3,
	shadow = SPEC_PRIEST_SHADOW or 3,
	affliction = SPEC_WARLOCK_AFFLICTION or 1,
	destruction = SPEC_WARLOCK_DESTRUCTION or 3,
}

local RETAIL = { retail = true }
local RETAIL_MISTS = { retail = true, mists = true }
local MISTS = { mists = true }
local DEATH_KNIGHTS = { retail = true, mists = true, titan = true }

---Resource rows, first match wins. Fields: class, power (POWER key), token (power token, also the
---color key), max (used when the game will not say), combo (combo points), needsPower (power type
---the player must be in: Energy is cat form), spec, clients (the clients that have this resource,
---Caps:Client(); nil means every client), fragments (always) or fragmentsSpec (only in that spec):
---pips fill part way, mod (fragments per point when the game will not say), runes.
---The clients list keeps a power type away from clients that do not have it (WoW Forever plays by
---Classic rules: its own interface loads only the combo point frame), so those players hear
---"your class has no points" instead of "not yet".
ClassPower.RESOURCES = {
	{ id = 'comboPoints', class = 'ROGUE', power = 'combo', token = 'COMBO_POINTS', max = 5, combo = true },
	{ id = 'comboPoints', class = 'DRUID', power = 'combo', token = 'COMBO_POINTS', max = 5, combo = true, needsPower = 'energy' },
	{ id = 'holyPower', class = 'PALADIN', power = 'holy', token = 'HOLY_POWER', max = 5, clients = RETAIL_MISTS },
	{ id = 'chi', class = 'MONK', power = 'chi', token = 'CHI', max = 5, spec = SPEC.windwalker, clients = RETAIL },
	{ id = 'chi', class = 'MONK', power = 'chi', token = 'CHI', max = 4, clients = MISTS },
	{ id = 'arcaneCharges', class = 'MAGE', power = 'arcane', token = 'ARCANE_CHARGES', max = 4, spec = SPEC.arcane, clients = RETAIL },
	{ id = 'soulShards', class = 'WARLOCK', power = 'shards', token = 'SOUL_SHARDS', max = 5, clients = RETAIL, fragmentsSpec = SPEC.destruction, mod = 10 },
	{ id = 'soulShards', class = 'WARLOCK', power = 'shards', token = 'SOUL_SHARDS', max = 4, spec = SPEC.affliction, clients = MISTS, mod = 100 },
	{ id = 'burningEmbers', class = 'WARLOCK', power = 'embers', token = 'BURNING_EMBERS', max = 4, spec = SPEC.destruction, clients = MISTS, fragments = true, mod = 10 },
	{ id = 'shadowOrbs', class = 'PRIEST', power = 'orbs', token = 'SHADOW_ORBS', max = 3, spec = SPEC.shadow, clients = MISTS },
	{ id = 'essence', class = 'EVOKER', power = 'essence', token = 'ESSENCE', max = 5, clients = RETAIL },
	{ id = 'runes', class = 'DEATHKNIGHT', power = 'runes', token = 'RUNES', max = 6, runes = true, clients = DEATH_KNIGHTS },
}

---Pip colors when the game's own power colors are missing.
ClassPower.COLORS = {
	COMBO_POINTS = { 1, 0.96, 0.41 },
	HOLY_POWER = { 0.95, 0.9, 0.6 },
	CHI = { 0.71, 1, 0.92 },
	SOUL_SHARDS = { 0.58, 0.51, 0.79 },
	BURNING_EMBERS = { 0.9, 0.35, 0.1 },
	ARCANE_CHARGES = { 0.3, 0.55, 1 },
	ESSENCE = { 0.4, 0.8, 1 },
	SHADOW_ORBS = { 0.6, 0.3, 0.85 },
	RUNES = { 0.55, 0.55, 0.6 },
}
---Runes by GetRuneType (Titan, Mists: 1 blood, 2 frost, 3 unholy, 4 death, as the game's own rune
---frame names them) and by specialization (Retail: 1 Blood, 2 Frost, 3 Unholy).
ClassPower.RUNE_TYPE_COLORS = { { 1, 0.25, 0.25 }, { 0.25, 0.75, 1 }, { 0.3, 0.85, 0.3 }, { 0.8, 0.35, 1 } }
ClassPower.RUNE_SPEC_COLORS = { { 1, 0.25, 0.25 }, { 0.25, 0.75, 1 }, { 0.3, 0.85, 0.3 } }
ClassPower.CHARGED_COLOR = { 0.25, 0.7, 1 }

---Plain words for why nothing shows (options and the inspector).
ClassPower.REASONS = {
	class = L['Your class has no points to show on your target.'],
	spec = L['Your current specialization has no points to show.'],
	form = L['Combo points show while you are in Cat Form.'],
	none = L['You do not have these points yet.'],
	vehicle = L['Points are hidden while you are in a vehicle.'],
}

---Combo points for previews when the player has no points of their own.
local SAMPLE_RESOURCE = {
	key = 'sample',
	id = 'comboPoints',
	token = 'COMBO_POINTS',
	powerType = POWER.combo,
	count = 5,
	mod = 1,
	combo = true,
	onTarget = false,
	color = ClassPower.COLORS.COMBO_POINTS,
}

----------------------------------------------------------------------------------------------------
-- Which resource the player has
----------------------------------------------------------------------------------------------------

---Why a row does not fit the player, or nil when it does. 'client' means this client does not
---have the resource at all (an unknown client is let through: its own maximum decides).
---@return string|nil
local function Miss(row, info, client)
	if row.clients and client ~= 'unknown' and not row.clients[client] then
		return 'client'
	elseif row.spec and info.spec ~= row.spec then
		return 'spec'
	elseif row.needsPower and info.powerType ~= POWER[row.needsPower] then
		return 'form'
	end
	return nil
end

local function PowerColor(token)
	local colors = _G.PowerBarColor
	local entry = type(colors) == 'table' and colors[token] or nil
	if type(entry) == 'table' and type(entry.r) == 'number' and type(entry.g) == 'number' and type(entry.b) == 'number' then
		return { entry.r, entry.g, entry.b }
	end
	local fallback = ClassPower.COLORS[token] or ClassPower.COLORS.COMBO_POINTS
	return { fallback[1], fallback[2], fallback[3] }
end

---The player's plain maximum (value, readable). A power type a client does not know is "unreadable",
---never an error.
local function MaxPlain(powerType, unmodified)
	local ok, value, readable = pcall(P.Source.PlayerPowerMaxPlain, powerType, unmodified)
	if ok and readable and type(value) == 'number' then
		return value, true
	end
	return nil, false
end

local function Fits(count)
	return count >= 1 and count <= MAX_PIPS
end

---How many pips a points resource has, and how many raw points fill one pip. The plain maximum is
---compared in both forms (whole points and raw fragments) rather than trusted, so this works
---whichever form a client hands back (Mists embers and shards are kept as fragments of 10 and 100).
---A maximum the game hides keeps the last count it showed. Returns nil when the maximum is zero.
---@return integer|nil count
---@return number mod
local function Scale(row, info, powerType)
	local whole, wholeOk = MaxPlain(powerType)
	local raw, rawOk = MaxPlain(powerType, true)
	if (wholeOk and whole <= 0) or (rawOk and raw <= 0) then
		return nil, 1
	end
	local display = P.Source.PowerDisplayModPlain(powerType)
	local plausible = wholeOk and Fits(whole)
	local count
	if plausible then
		count = math.floor(whole)
	elseif rawOk and display and display > 1 and Fits(raw / display) then
		count = math.floor(raw / display)
	elseif rawOk and row.mod and Fits(raw / row.mod) then
		count = math.floor(raw / row.mod)
	end
	if count then
		ClassPower.lastCount[row.id] = count
	else
		count = ClassPower.lastCount[row.id] or row.max
	end
	local mod = 1
	local fragments = row.fragments or (row.fragmentsSpec ~= nil and info.spec == row.fragmentsSpec)
	if fragments or not plausible then
		if rawOk then
			if raw > count and raw % count == 0 then
				mod = raw / count
			end
		elseif display and display > 1 then
			mod = display
		elseif row.mod then
			mod = row.mod
		end
	end
	return count, mod
end
ClassPower.Scale = Scale

---Build the resource for a matching row, or nil when the player's maximum is zero.
local function Build(row, info, retail)
	local powerType = POWER[row.power]
	local res = { id = row.id, token = row.token, powerType = powerType, mod = 1, combo = row.combo, runes = row.runes, onTarget = false }
	if row.runes then
		if not GetRuneCooldown then
			return nil
		end
		res.count = row.max
		res.typed = P.Source.RuneTypePlain(1) ~= nil
		res.spec = info.spec
	else
		local count, mod = Scale(row, info, powerType)
		if not count then
			return nil
		end
		res.count, res.mod = count, mod
		res.onTarget = (row.combo and not retail and P.Caps:Get('comboTarget') and not P.Caps:Quirk('comboPointsFromPlayer')) and true or false
	end
	res.count = math.max(1, math.min(MAX_PIPS, math.floor(res.count)))
	res.color = PowerColor(row.token)
	res.key = table.concat({ row.id, res.count, res.mod, tostring(res.onTarget), tostring(res.spec or 0) }, ':')
	return res
end

---Work out the player's resource now. Returns nil and a reason key (ClassPower.REASONS) when
---there is none.
---@return table|nil resource
---@return string|nil reason
function ClassPower:Compute()
	local info = P.Source.ReadPlayerPower(self.info)
	local retail = P.Caps.Rules.retail and true or false
	local client = P.Caps:Client() or 'unknown'
	local reason = 'class'
	for _, row in ipairs(self.RESOURCES) do
		if row.class == info.class then
			local why = Miss(row, info, client)
			if not why then
				local res = Build(row, info, retail)
				if res then
					return res, nil
				end
				reason = 'none'
			elseif why ~= 'client' and reason == 'class' then
				reason = why
			end
		end
	end
	return nil, reason
end

---The player's resource (cached while the player's events are watched), or nil.
---@return table|nil
function ClassPower:Resource()
	if self.dirty or not self.running then
		self.resource, self.reason = self:Compute()
		self.dirty = not self.running
	end
	return self.resource
end

---The resource a preview plate draws: the player's own without fragments (samples are whole
---points), or sample combo points.
---@return table
function ClassPower:PreviewResource()
	local res = self:Resource()
	if not res then
		return SAMPLE_RESOURCE
	end
	if not self.preview or self.preview.key ~= res.key .. ':preview' then
		local copy = {}
		for k, v in pairs(res) do
			copy[k] = v
		end
		copy.mod = 1
		copy.onTarget = false
		copy.key = res.key .. ':preview'
		self.preview = copy
	end
	return self.preview
end

---Whether pips can show for the player right now, and the reason in plain words when not.
---@return boolean shown
---@return string|nil reason
function ClassPower:Status()
	local res, why = self:Compute()
	if not res then
		return false, self.REASONS[why or 'class']
	end
	if self.info.inVehicle then
		return false, self.REASONS.vehicle
	end
	return true, nil
end

----------------------------------------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------------------------------------

local function NewPip(widget, index)
	local pip = CreateFrame('StatusBar', nil, widget.row)
	pip.edge = pip:CreateTexture(nil, 'BACKGROUND', nil, -8)
	pip.edge:SetTexture(WHITE)
	pip.bg = pip:CreateTexture(nil, 'BACKGROUND', nil, -7)
	pip.bg:SetTexture(WHITE)
	pip.bg:SetAllPoints(pip)
	pip:SetMinMaxValues(0, 1)
	pip:SetValue(0)
	widget.pips[index] = pip
	return pip
end

local function Paint(widget, res)
	local color = widget.fixedColor or res.color
	local ink = widget.ink or { 0, 0, 0, 1 }
	local px = widget.pixel or 1
	for i = 1, #widget.pips do
		local pip = widget.pips[i]
		pip:SetStatusBarTexture(widget.texture or WHITE)
		pip:SetStatusBarColor(color[1], color[2], color[3], 1)
		pip.bg:SetVertexColor(color[1] * 0.25, color[2] * 0.25, color[3] * 0.25, 0.9)
		pip.edge:ClearAllPoints()
		pip.edge:SetPoint('TOPLEFT', pip, 'TOPLEFT', -px, px)
		pip.edge:SetPoint('BOTTOMRIGHT', pip, 'BOTTOMRIGHT', px, -px)
		pip.edge:SetVertexColor(ink[1], ink[2], ink[3], ink[4] or 1)
		pip.charged = nil
	end
end

---Place the pips for a resource: whole pixels, centered in the part.
local function LayoutPips(widget, res)
	local count = res.count
	local width, height, gap = widget.width or 1, widget.height or 1, widget.spacing or 0
	local pipW = math.max(1, math.floor((width - (count - 1) * gap) / count))
	local used = count * pipW + (count - 1) * gap
	local x = math.floor((width - used) / 2)
	for i = 1, count do
		local pip = widget.pips[i] or NewPip(widget, i)
		pip:ClearAllPoints()
		pip:SetPoint('TOPLEFT', widget.row, 'TOPLEFT', x + (i - 1) * (pipW + gap), 0)
		pip:SetSize(pipW, height)
		if res.runes then
			pip:SetMinMaxValues(0, 1)
		else
			pip:SetMinMaxValues((i - 1) * res.mod, i * res.mod)
		end
		pip:Show()
	end
	for i = count + 1, #widget.pips do
		widget.pips[i]:Hide()
	end
	widget.count, widget.resKey = count, res.key
	Paint(widget, res)
end

local function RuneColor(res, runeType)
	if runeType and ClassPower.RUNE_TYPE_COLORS[runeType] then
		return ClassPower.RUNE_TYPE_COLORS[runeType]
	end
	return ClassPower.RUNE_SPEC_COLORS[res.spec or 0] or res.color
end

---Fill rune pips; returns true while a rune is still coming back.
local function FillRunes(widget, src, res)
	local now = P.services.GetTime()
	local recharging = false
	local runes = {}
	for i = 1, res.count do
		local start, duration, ready, readable = src:RunePlain(i)
		local progress = 0
		if readable and ready then
			progress = 1
		elseif readable and duration and duration > 0 then
			progress = math.max(0, math.min(1, (now - start) / duration))
			recharging = true
		end
		runes[i] = { progress = progress, type = res.typed and P.Source.RuneTypePlain(i) or nil, index = i }
	end
	if not res.typed then
		-- Clients without rune types show ready runes first, then the ones closest to coming back
		table.sort(runes, function(a, b)
			if a.progress ~= b.progress then
				return a.progress > b.progress
			end
			return a.index < b.index
		end)
	end
	local fixed = widget.fixedColor
	for i = 1, res.count do
		local pip, rune = widget.pips[i], runes[i]
		pip:SetValue(rune.progress)
		local color = fixed or RuneColor(res, rune.type)
		pip:SetStatusBarColor(color[1], color[2], color[3], 1)
		pip.bg:SetVertexColor(color[1] * 0.25, color[2] * 0.25, color[3] * 0.25, 0.9)
	end
	return recharging
end

local marks = {} -- reused: charged pip index -> true, emptied after every paint

---Tint charged combo points (plain list only; a hidden list leaves every pip in its own color).
local function PaintCharged(widget, res, src)
	local charged = res.combo and src:ChargedPointsPlain() or nil
	local color = widget.fixedColor or res.color
	local chargedColor = ClassPower.CHARGED_COLOR
	if charged then
		for i = 1, #charged do
			marks[charged[i]] = true
		end
	end
	for i = 1, res.count do
		local pip = widget.pips[i]
		local want = marks[i] or nil
		if pip.charged ~= want then
			pip.charged = want
			local c = want and chargedColor or color
			pip:SetStatusBarColor(c[1], c[2], c[3], 1)
		end
	end
	P.util.Wipe(marks)
end

---Should this widget show pips now (plain checks only)?
local function Wanted(widget)
	local plate = widget.plate
	if plate.isPreview then
		return plate.states.target == true
	end
	if plate.facts.canAttack == false or ClassPower.info.inVehicle then
		return false
	end
	return plate.states.target == true or widget.secretTarget == true
end

---Fill one widget from its plate's source.
---@param widget Plates.Widget
---@param src? Plates.Source
local function Fill(widget, src)
	local plate = widget.plate
	src = src or plate.src
	if not plate.isPreview then
		ClassPower:Start()
	end
	local res = plate.isPreview and ClassPower:PreviewResource() or ClassPower:Resource()
	if not (res and src and widget.active and Wanted(widget)) then
		widget.row:Hide()
		return
	end
	if widget.resKey ~= res.key or widget.count ~= res.count then
		LayoutPips(widget, res)
	end
	widget.row:Show()
	if res.runes then
		if FillRunes(widget, src, res) and not plate.isPreview then
			ClassPower:WatchRunes()
		end
		return
	end
	local amountSecret
	if res.onTarget then
		amountSecret = src:TargetComboPointsSecret()
	else
		amountSecret = src:PlayerPowerSecret(res.powerType, res.mod > 1 or nil)
	end
	if type(amountSecret) == 'nil' then
		amountSecret = 0
	end
	for i = 1, res.count do
		widget.pips[i]:SetValue(amountSecret)
	end
	PaintCharged(widget, res, src)
end
ClassPower.Fill = Fill

---Fill the widgets on the target's plate (or on every plate while the target is only known as a
---secret).
function ClassPower:FillTargets()
	for widget in pairs(self.widgets) do
		local plate = widget.plate
		if widget.active and not plate.isPreview and plate.src and (plate.states.target or widget.secretTarget) then
			Fill(widget)
		end
	end
end

---The player's resource may have changed shape: work it out again and redraw every widget.
function ClassPower:Invalidate()
	self.dirty = true
	self:Resource()
	for widget in pairs(self.widgets) do
		if widget.active and widget.plate.src then
			Fill(widget)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- The player's events
----------------------------------------------------------------------------------------------------

-- UNIT_POWER_FREQUENT, like the game's own point bars (every point shows at once); filtered by
-- power token below, so energy and mana ticks cost one compare
local UNIT_EVENTS = { 'UNIT_POWER_FREQUENT', 'UNIT_MAXPOWER', 'UNIT_DISPLAYPOWER', 'UNIT_POWER_POINT_CHARGE', 'UNIT_ENTERED_VEHICLE', 'UNIT_EXITED_VEHICLE' }
local EVENTS = {
	'PLAYER_ENTERING_WORLD',
	'PLAYER_SPECIALIZATION_CHANGED',
	'PLAYER_TALENT_UPDATE',
	'ACTIVE_TALENT_GROUP_CHANGED',
	'UPDATE_SHAPESHIFT_FORM',
	'PLAYER_LEVEL_UP',
	'SPELLS_CHANGED',
	'RUNE_POWER_UPDATE',
	'RUNE_TYPE_UPDATE',
	'COMBO_TARGET_CHANGED',
}
ClassPower.UNIT_EVENTS, ClassPower.EVENTS = UNIT_EVENTS, EVENTS
-- Events that only change the amount; every other one can change the resource itself
local AMOUNT_EVENTS = { UNIT_POWER_FREQUENT = true, UNIT_POWER_UPDATE = true, UNIT_POWER_POINT_CHARGE = true, RUNE_POWER_UPDATE = true, COMBO_TARGET_CHANGED = true }

local function OnEvent(_, event, _, powerToken)
	if not AMOUNT_EVENTS[event] then
		ClassPower:Invalidate()
		return
	end
	local res = ClassPower:Resource()
	if not res then
		return
	end
	if event == 'UNIT_POWER_FREQUENT' or event == 'UNIT_POWER_UPDATE' then
		-- Skip other powers (energy and mana ticks) when the token is readable
		local token, readable = Secret.Plain(powerToken)
		if readable and type(token) == 'string' and token ~= res.token then
			return
		end
	end
	ClassPower:FillTargets()
end

---Watch the player's power events (safe to call often). Called when a live plate draws the part.
function ClassPower:Start()
	if self.running then
		return
	end
	if not self.events then
		self.events = CreateFrame('Frame')
		self.events:SetScript('OnEvent', OnEvent)
	end
	-- Registering an event a client does not have raises an error; those are skipped
	local frame = self.events
	for _, event in ipairs(UNIT_EVENTS) do
		local ok = pcall(frame.RegisterUnitEvent, frame, event, 'player')
		if not ok and event == 'UNIT_POWER_FREQUENT' then
			pcall(frame.RegisterUnitEvent, frame, 'UNIT_POWER_UPDATE', 'player')
		end
	end
	for _, event in ipairs(EVENTS) do
		pcall(frame.RegisterEvent, frame, event)
	end
	self.running = true
	self.dirty = true
end

---Stop watching (the engine turned off).
function ClassPower:Stop()
	if self.events then
		self.events:UnregisterAllEvents()
	end
	P.Scheduler:Cancel('ClassPower.runes')
	self.running = false
	self.dirty = true
end

---Keep runes filling while one is coming back (shared tick, only while needed).
function ClassPower:WatchRunes()
	if P.Scheduler:IsRunning('ClassPower.runes') then
		return
	end
	P.Scheduler:Every('ClassPower.runes', 0.1, function()
		local res = ClassPower.resource
		local busy = false
		if res and res.runes then
			for widget in pairs(ClassPower.widgets) do
				local plate = widget.plate
				if widget.active and not plate.isPreview and plate.src and widget.row:IsShown() then
					busy = FillRunes(widget, plate.src, res) or busy
				end
			end
		end
		if not busy then
			P.Scheduler:Cancel('ClassPower.runes')
		end
	end)
end

P:On('ENGINE_DISABLED', function()
	ClassPower:Stop()
end, ClassPower)

-- A client without GetComboPoints reads the player's own combo point power instead
P.Caps:AddProbe('comboTarget', function()
	return GetComboPoints ~= nil
end, 'GetComboPoints (combo points read from the target on the Classic family and Forever)')

----------------------------------------------------------------------------------------------------
-- The part
----------------------------------------------------------------------------------------------------

P.Parts:Register({
	id = 'classPower',
	kinds = { 'classPower' },
	Create = function(plate)
		local holder = CreateFrame('Frame', nil, plate.art)
		local row = CreateFrame('Frame', nil, holder)
		row:SetAllPoints(holder)
		row:Hide()
		return { frame = holder, row = row, pips = {} }
	end,
	Layout = function(widget, spec, ctx)
		local frame = widget.frame
		local height = spec.size or 6
		frame:SetSize(ctx.width, height)
		ctx:Anchor(frame, spec.anchor)
		local tokens = ctx.style and ctx.style.tokens or {}
		widget.width, widget.height, widget.spacing = ctx.width, height, spec.spacing or 2
		widget.texture = ctx:Texture(spec.shape) or ctx:Texture(tokens.bar) or WHITE
		widget.ink = type(tokens.ink) == 'table' and { ctx:Color(tokens.ink) } or { 0, 0, 0, 1 }
		widget.fixedColor = type(spec.color) == 'table' and { ctx:Color(spec.color) } or nil
		widget.pixel = ctx:Pixel()
		widget.resKey = nil
		ClassPower.widgets[widget] = true
		if widget.plate.src then
			Fill(widget)
		end
	end,
	Update = function(widget, src)
		Fill(widget, src)
	end,
	Reset = function(widget)
		widget.secretTarget = nil
		widget.row:SetAlpha(1)
		widget.row:Hide()
	end,
	OnState = function(widget, state, on)
		if state ~= 'target' then
			return
		end
		widget.secretTarget = nil
		widget.row:SetAlpha(1)
		if on then
			Fill(widget)
		else
			widget.row:Hide()
		end
	end,
	OnStateSecret = function(widget, state, boolSecret)
		if state ~= 'target' then
			return
		end
		widget.secretTarget = true
		Fill(widget)
		Secret.SetAlphaFromBoolean(widget.row, boolSecret, 1, 0)
	end,
})
