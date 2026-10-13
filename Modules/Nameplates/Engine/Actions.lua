local _, ns = ...
local P = ns.Plates
local L = P.L
local Secret = P.Secret
local EMPTY = {} -- read only

-- "When" actions (Phase 8, plan 3.5 and 6.4): "When <conditions> then <action>" rules that change
-- how a plate stands out. They live in profile.actions (a list, written whole by the Who and where
-- page through the shared WhenBuilder in its 'emphasis' context). Every rule that fits applies;
-- when two rules change the same thing, the one higher in the list wins.
--
-- Entry shape (one action per entry; the layout actions stay in profile.when, Situation.Assign):
--   { conditions = { { id, args?, negate? } }, kinds = { 'enemyNPC' }?, off = true?,
--     grow  = { w, h }                    bigger by whole pixels (needs 'grow')
--     paint = 'health'|'border'|'name', color = { r, g, b, a }   (needs 'color')
--     fade  = 0-1                         the plate's alpha while it fits (needs 'alpha')
--     glow  = { r, g, b, a }              a soft glow around the plate (needs 'glow')
--     mark  = 'star'|'skull'|..., markColor = { r, g, b, a }?    a mark above the plate (needs 'mark') }
--
-- Compiler: Actions:Program() turns the list into rules once per settings change (copies, never the
-- DB tables). Each rule keeps the events and bus messages its conditions declare
-- (Conditions:CollectEvents); a plate registers exactly those (Plate:RegisterUnitEvents) and runs
-- the rules only when one of them arrives, when a state changes, or after a part it paints over
-- redrew itself. Nothing runs per frame.
--
-- Hidden answers (Retail and Forever). Conditions:Reduce settles plain clauses in Lua; a rule whose
-- answer the game keeps hides behind one or more engine clauses. Only sinks see those answers:
--   * fade, glow: SetAlphaFromBoolean / GlowLib.ShowWhenSecret on one hidden clause (several hidden
--     clauses in one rule cannot be told apart by alpha, so such a rule stays off and the builder
--     says so); the next rule below that fits plainly is the "else" value
--   * paint health / border, mark: texture colors folded with Conditions:FoldColorSecret and
--     FoldSecret (any number of hidden clauses), straight into SetVertexColor; hidden health uses
--     the low health curve (Conditions.LowHealthCurve) as the texture's alpha
--   * paint name: the name's own color list is worked out into a stand-in target (Colors:Apply),
--     then the rules are folded over it into SetTextColor
-- grow never waits for the engine: the builder only offers it for conditions with plain answers.
-- Identity conditions answer "no" when hidden, so they never reach the engine.

---@class Plates.ActionRule
---@field index integer Place in profile.actions
---@field effect string grow | paint | fade | glow | mark
---@field clauses table[]
---@field expr table { all = clauses }
---@field kinds? table<string, boolean>
---@field events table<string, boolean>
---@field messages table<string, boolean>
---@field states boolean Reads target, focus, mouseover or casting

---@class Plates.Actions
local Actions = { generation = 0, warned = {} }
P.Actions = Actions

-- Raid target icons by name (the game's own picture on every client, cells in a 4x4 sheet)
Actions.MARKS = { star = 1, circle = 2, diamond = 3, triangle = 4, moon = 5, square = 6, cross = 7, skull = 8 }
Actions.MARK_ORDER = { 'star', 'circle', 'diamond', 'triangle', 'moon', 'square', 'cross', 'skull' }
Actions.MARK_LABELS = {
	star = L['Star'],
	circle = L['Circle'],
	diamond = L['Diamond'],
	triangle = L['Triangle'],
	moon = L['Moon'],
	square = L['Square'],
	cross = L['Cross'],
	skull = L['Skull'],
}
Actions.MARK_FILE = 'Interface\\TargetingFrame\\UI-RaidTargetingIcons'
Actions.MARK_SIZE = 18
Actions.MAX_MARKS = 3

Actions.PIECES = { 'health', 'border', 'name' }
Actions.PIECE_LABELS = { health = L['Health bar'], border = L['Border'], name = L['Name'] }

Actions.GROW_MIN, Actions.GROW_MAX = -40, 60
Actions.STATE_IDS = { target = true, focus = true, mouseover = true, casting = true }

local KINDS = {}
for _, kind in ipairs(P.Situation.KINDS) do
	KINDS[kind] = true
end

----------------------------------------------------------------------------------------------------
-- Effects: the entry fields each action owns, how to read them and how to clean them
----------------------------------------------------------------------------------------------------

local function Color(value)
	if type(value) ~= 'table' then
		return nil
	end
	local out = {}
	for i = 1, 4 do
		local c = value[i]
		if c == nil and i == 4 then
			c = 1
		end
		if type(c) ~= 'number' then
			return nil
		end
		out[i] = math.max(0, math.min(1, c))
	end
	return out
end

local function Whole(value, low, high)
	if type(value) ~= 'number' then
		return nil
	end
	return math.max(low, math.min(high, math.floor(value + 0.5)))
end

---@class Plates.ActionEffect
---@field id string
---@field needs string Conditions:AllowedActions key
---@field since integer Share format number (Schema.CURRENT) the effect first shipped in
---@field fields table<string, boolean> Entry fields it owns
---@field Active fun(entry: table): boolean
---@field Clean fun(entry: table, out: table): boolean Copy its fields into out; false when they are broken

Actions.EFFECTS = {
	grow = {
		id = 'grow',
		needs = 'grow',
		since = 1,
		fields = { grow = true },
		Active = function(entry)
			return type(entry.grow) == 'table'
		end,
		Clean = function(entry, out)
			local w = Whole(entry.grow[1], Actions.GROW_MIN, Actions.GROW_MAX)
			local h = Whole(entry.grow[2] or 0, Actions.GROW_MIN, Actions.GROW_MAX)
			if not (w and h) then
				return false
			end
			out.grow = { w, h }
			return true
		end,
	},
	paint = {
		id = 'paint',
		needs = 'color',
		since = 1,
		fields = { paint = true, color = true },
		Active = function(entry)
			return type(entry.paint) == 'string'
		end,
		Clean = function(entry, out)
			local color = Color(entry.color)
			local ok = false
			for _, piece in ipairs(Actions.PIECES) do
				if entry.paint == piece then
					ok = true
				end
			end
			if not (ok and color) then
				return false
			end
			out.paint, out.color = entry.paint, color
			return true
		end,
	},
	fade = {
		id = 'fade',
		needs = 'alpha',
		since = 1,
		fields = { fade = true },
		Active = function(entry)
			return type(entry.fade) == 'number'
		end,
		Clean = function(entry, out)
			out.fade = math.max(0, math.min(1, entry.fade))
			return true
		end,
	},
	glow = {
		id = 'glow',
		needs = 'glow',
		since = 1,
		fields = { glow = true },
		Active = function(entry)
			return type(entry.glow) == 'table'
		end,
		Clean = function(entry, out)
			out.glow = Color(entry.glow)
			return out.glow ~= nil
		end,
	},
	mark = {
		id = 'mark',
		needs = 'mark',
		since = 1,
		fields = { mark = true, markColor = true },
		Active = function(entry)
			return type(entry.mark) == 'string'
		end,
		Clean = function(entry, out)
			if not Actions.MARKS[entry.mark] then
				return false
			end
			out.mark = entry.mark
			if entry.markColor ~= nil then
				out.markColor = Color(entry.markColor)
				if not out.markColor then
					return false
				end
			end
			return true
		end,
	},
}
Actions.EFFECT_ORDER = { 'grow', 'paint', 'fade', 'glow', 'mark' }

-- Entry field -> the effect that owns it
local FIELD_EFFECT = {}
for id, def in pairs(Actions.EFFECTS) do
	for field in pairs(def.fields) do
		FIELD_EFFECT[field] = id
	end
end
local ENTRY_FIELDS = { conditions = true, kinds = true, off = true }

---The effect an entry carries, or nil.
---@param entry table
---@return string|nil
function Actions.EffectOf(entry)
	if type(entry) ~= 'table' then
		return nil
	end
	for _, id in ipairs(Actions.EFFECT_ORDER) do
		if Actions.EFFECTS[id].Active(entry) then
			return id
		end
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- Cleaning (stored lists and share strings). A field or condition this version does not know means
-- the entry was made by a newer version: it is refused, never half imported.
----------------------------------------------------------------------------------------------------

local MAX_LIST = 60
local MAX_CLAUSES = 8

local function CleanArgs(args, depth)
	local t = type(args)
	if t == 'number' then
		if args ~= args or args > 1e9 or args < -1e9 then
			return nil, false
		end
		return args, true
	elseif t == 'string' then
		return string.sub(args, 1, 64), true
	elseif t == 'boolean' then
		return args, true
	elseif t == 'table' and (depth or 0) < 1 then
		local out, n = {}, 0
		for key, value in pairs(args) do
			n = n + 1
			if n > MAX_LIST then
				break
			end
			local keyOk = type(key) == 'number' and key == math.floor(key) and key > 0 and key < 2147483648
			if keyOk and (value == true or value == 'mine' or value == 'any') then
				out[key] = value
			elseif keyOk and type(value) == 'number' and value == math.floor(value) and value > 0 and value < 2147483648 then
				out[key] = value
			else
				return nil, false
			end
		end
		return out, true
	end
	return nil, false
end

---Check one entry. Returns a clean copy, or nil and why: 'newer' (made by a newer version: an
---unknown field, condition or effect), 'empty' (no action), 'shape' (broken values).
---@param entry any
---@param schema? integer The share string's format number (default Schema.CURRENT)
---@return table|nil clean
---@return string|nil reason
function Actions:CleanEntry(entry, schema)
	if type(entry) ~= 'table' then
		return nil, 'shape'
	end
	local effect
	for key in pairs(entry) do
		if not ENTRY_FIELDS[key] then
			local owner = FIELD_EFFECT[key]
			if not owner then
				return nil, 'newer'
			end
			if effect and effect ~= owner then
				return nil, 'shape'
			end
			effect = owner
		end
	end
	if not effect then
		return nil, 'empty'
	end
	local def = self.EFFECTS[effect]
	local current = (P.Styles and P.Styles.Schema and P.Styles.Schema.CURRENT) or 1
	if def.since > (schema or current) then
		return nil, 'newer'
	end
	local clean = {}
	if entry.conditions ~= nil then
		if type(entry.conditions) ~= 'table' or #entry.conditions > MAX_CLAUSES then
			return nil, 'shape'
		end
		clean.conditions = {}
		for _, clause in ipairs(entry.conditions) do
			if type(clause) ~= 'table' or type(clause.id) ~= 'string' then
				return nil, 'shape'
			end
			if not P.Conditions:Get(clause.id) then
				return nil, 'newer'
			end
			local item = { id = clause.id }
			if clause.args ~= nil then
				local args, ok = CleanArgs(clause.args)
				if not ok then
					return nil, 'shape'
				end
				item.args = args
			end
			if clause.negate == true then
				item.negate = true
			end
			clean.conditions[#clean.conditions + 1] = item
		end
	end
	if entry.kinds ~= nil then
		if type(entry.kinds) ~= 'table' then
			return nil, 'shape'
		end
		clean.kinds = {}
		for _, kind in ipairs(entry.kinds) do
			if not KINDS[kind] then
				return nil, 'shape'
			end
			clean.kinds[#clean.kinds + 1] = kind
		end
		if #clean.kinds == 0 then
			return nil, 'shape'
		end
	end
	if entry.off == true then
		clean.off = true
	end
	if not def.Clean(entry, clean) then
		return nil, 'shape'
	end
	return clean
end

---@class Plates.ActionCleanReport
---@field kept integer
---@field dropped integer
---@field newer integer Entries made by a newer version (refused)

---Check a whole list (profile.actions, or the actions of a "When" share string).
---@param list any
---@param schema? integer
---@return table[] clean
---@return Plates.ActionCleanReport report
function Actions:CleanList(list, schema)
	local out, report = {}, { kept = 0, dropped = 0, newer = 0 }
	if type(list) ~= 'table' then
		if list ~= nil then
			report.dropped = 1
		end
		return out, report
	end
	for _, entry in ipairs(list) do
		local clean, reason = nil, 'shape'
		if #out < MAX_LIST then
			clean, reason = self:CleanEntry(entry, schema)
		end
		if clean then
			out[#out + 1] = clean
			report.kept = report.kept + 1
		elseif reason == 'newer' then
			report.newer = report.newer + 1
		else
			report.dropped = report.dropped + 1
		end
	end
	return out, report
end

---The "When" share payload with the actions next to the special cases: { when, actions }.
---@return table payload
function Actions:SharePayload()
	return { when = P.util.Copy(P.Store:Get('when') or {}), actions = P.util.Copy(P.Store:Get('actions') or {}) }
end

----------------------------------------------------------------------------------------------------
-- Compiler
----------------------------------------------------------------------------------------------------

---True when every clause of the rule allows its effect on this client and can work here.
---@param clauses table[]
---@param needs string
---@return boolean
function Actions.Works(clauses, needs)
	for _, clause in ipairs(clauses) do
		local cond = P.Conditions:Get(clause.id)
		if not cond or not P.Conditions:AllowedActions(clause.id)[needs] then
			return false
		end
		if cond.Unavailable and cond.Unavailable() then
			return false
		end
	end
	return true
end

local program

---The compiled rules for the profile (rebuilt after settings change).
---@return table program { rules = Plates.ActionRule[], generation }
function Actions:Program()
	if program then
		return program
	end
	self.generation = self.generation + 1
	program = { rules = {}, generation = self.generation }
	local list = P.Store and P.Store:Get('actions')
	if type(list) ~= 'table' then
		return program
	end
	for index, entry in ipairs(list) do
		local clean = self:CleanEntry(entry)
		if clean and not clean.off then
			local effect = self.EffectOf(clean)
			local clauses = clean.conditions or {}
			if effect and self.Works(clauses, self.EFFECTS[effect].needs) then
				local rule = { index = index, effect = effect, clauses = clauses, expr = { all = clauses }, events = {}, messages = {}, states = false }
				P.Conditions:CollectEvents(rule.expr, rule.events, rule.messages)
				for _, clause in ipairs(clauses) do
					if self.STATE_IDS[clause.id] then
						rule.states = true
					end
				end
				if clean.kinds then
					rule.kinds = {}
					for _, kind in ipairs(clean.kinds) do
						rule.kinds[kind] = true
					end
				end
				for field in pairs(self.EFFECTS[effect].fields) do
					rule[field] = clean[field]
				end
				program.rules[#program.rules + 1] = rule
			end
		end
	end
	return program
end

---Forget the compiled rules (settings or the profile changed).
function Actions:Invalidate()
	program = nil
end

---True when a rule asks whether an enemy is fighting. The Driver's fact poller then keeps sending
---FACTS_POLLED while that answer is hidden, as it does for combat color rows, so a fade the game
---decides follows the fight.
---@return boolean
function Actions:ReadsCombat()
	local prog = self:Program()
	if prog.readsCombat == nil then
		prog.readsCombat = false
		for _, rule in ipairs(prog.rules) do
			for _, clause in ipairs(rule.clauses) do
				if clause.id == 'unitInCombat' then
					prog.readsCombat = true
				end
			end
		end
	end
	return prog.readsCombat
end

----------------------------------------------------------------------------------------------------
-- Per plate
----------------------------------------------------------------------------------------------------

local states = setmetatable({}, { __mode = 'k' })

local function State(plate)
	local st = states[plate]
	if not st then
		st = { rules = {}, events = {}, messages = {}, marks = {}, pending = {}, grow = { 0, 0 } }
		st.capture = {
			SetTextColor = function(self, rSecret, gSecret, bSecret, a)
				self.rSecret = rSecret
				self.gSecret = gSecret
				self.bSecret = bSecret
				self.a = a
			end,
		}
		states[plate] = st
	end
	return st
end

---@param plate Plates.Plate
---@return table|nil st
function Actions:StateOf(plate)
	return states[plate]
end

---Pick the rules that apply to a plate's kind and the events they need. Cheap when nothing changed
---(same program, same kind), so binding a unit again makes no tables.
---@param plate Plates.Plate
---@return table st
function Actions:Attach(plate)
	local prog = self:Program()
	local kind = plate.situation or (plate.style and plate.style.situation)
	local st = states[plate]
	if st and st.program == prog and st.kind == kind then
		plate.actionsOn = (#st.rules > 0 or st.drawn) or nil
		return st
	end
	st = State(plate)
	st.program, st.kind = prog, kind
	P.util.Wipe(st.rules)
	P.util.Wipe(st.events)
	P.util.Wipe(st.messages)
	st.readsStates, st.repaint = false, false
	for _, rule in ipairs(prog.rules) do
		if not rule.kinds or (kind and rule.kinds[kind]) then
			st.rules[#st.rules + 1] = rule
			for event in pairs(rule.events) do
				st.events[event] = true
			end
			for message in pairs(rule.messages) do
				st.messages[message] = true
			end
			if rule.states then
				st.readsStates = true
			end
			if rule.effect == 'paint' and (rule.paint == 'name' or rule.paint == 'border') then
				st.repaint = true
			end
		end
	end
	if #st.rules > 0 then
		plate.actionEvents, plate.actionMessages = st.events, st.messages
		plate.actionStates, plate.actionRepaint = st.readsStates, st.repaint
	else
		plate.actionEvents, plate.actionMessages, plate.actionStates, plate.actionRepaint = nil, nil, nil, nil
	end
	plate.actionsOn = (#st.rules > 0 or st.drawn) or nil
	return st
end

local function HealthWidget(plate)
	for i = 1, #plate.active do
		local widget = plate.active[i]
		if widget.impl.id == 'health' and widget.bar then
			return widget
		end
	end
	return nil
end

local function NameWidget(plate)
	for i = 1, #plate.active do
		local widget = plate.active[i]
		local spec = widget.spec
		if spec.kind == 'text' and spec.source == 'name' and widget.text then
			return widget
		end
	end
	return nil
end

local function WarnOnce(key, text)
	if not Actions.warned[key] then
		Actions.warned[key] = true
		P.log.warning(text)
	end
end

---The texture the health tint uses: the bar's own fill picture where it can be read, else white.
local function FillFile(bar)
	local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if fill and fill.GetTexture then
		local ok, file = pcall(fill.GetTexture, fill)
		file = ok and Secret.Plain(file) or nil
		if type(file) == 'string' or type(file) == 'number' then
			return file
		end
	end
	return (P.BarLib and P.BarLib.WHITE) or 'Interface\\Buttons\\WHITE8X8'
end

local function White()
	return (P.BarLib and P.BarLib.WHITE) or 'Interface\\Buttons\\WHITE8X8'
end

---Make or move the drawing pieces after the plate laid itself out (a new style can move the
---health bar or the name). Pieces are made only when a rule needs them.
---@param plate Plates.Plate
function Actions:Layout(plate)
	local st = states[plate]
	if not st then
		return
	end
	st.laidOut = plate.styleKey
	local health = HealthWidget(plate)
	local bar = health and health.bar
	if st.tint then
		if bar then
			local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
			for _, tint in ipairs({ st.tint, st.lowTint }) do
				tint:SetParent(bar)
				tint:ClearAllPoints()
				tint:SetPoint('TOPLEFT', bar, 'TOPLEFT', 0, 0)
				tint:SetPoint('BOTTOMRIGHT', fill or bar, 'BOTTOMRIGHT', 0, 0)
				tint:SetTexture(FillFile(bar))
			end
		end
		st.tintBar = bar
	end
	if st.border then
		local frame = st.border
		if bar then
			frame:SetParent(bar)
			frame:ClearAllPoints()
			frame:SetAllPoints(bar)
			local level = Secret.Plain(bar:GetFrameLevel())
			if type(level) == 'number' then
				frame:SetFrameLevel(level + 3)
			end
			local holder = bar.border
			local pixels = holder and holder.kind and holder.pixels or 1
			local pixel = (holder and holder.pixel) or plate:LayoutContext():Pixel()
			local t = math.max(pixels, 1) * pixel
			local e = frame.edges
			e.top:ClearAllPoints()
			e.top:SetPoint('BOTTOMLEFT', bar, 'TOPLEFT', -t, 0)
			e.top:SetPoint('BOTTOMRIGHT', bar, 'TOPRIGHT', t, 0)
			e.top:SetHeight(t)
			e.bottom:ClearAllPoints()
			e.bottom:SetPoint('TOPLEFT', bar, 'BOTTOMLEFT', -t, 0)
			e.bottom:SetPoint('TOPRIGHT', bar, 'BOTTOMRIGHT', t, 0)
			e.bottom:SetHeight(t)
			e.left:ClearAllPoints()
			e.left:SetPoint('TOPRIGHT', bar, 'TOPLEFT', 0, 0)
			e.left:SetPoint('BOTTOMRIGHT', bar, 'BOTTOMLEFT', 0, 0)
			e.left:SetWidth(t)
			e.right:ClearAllPoints()
			e.right:SetPoint('TOPLEFT', bar, 'TOPRIGHT', 0, 0)
			e.right:SetPoint('BOTTOMLEFT', bar, 'BOTTOMRIGHT', 0, 0)
			e.right:SetWidth(t)
			frame:Show()
		else
			frame:Hide()
		end
		st.borderBar = bar
	end
	if st.glow then
		P.GlowLib.Layout(st.glow, plate.art, P.GlowLib.Opts('soft', 5), plate:LayoutContext())
	end
	if st.marksFrame then
		local name = NameWidget(plate)
		local anchor = name and name.text or plate.art
		local size = self.MARK_SIZE
		for i = 1, #st.marks do
			local tex = st.marks[i]
			tex:ClearAllPoints()
			tex:SetSize(size, size)
			if i == 1 then
				tex:SetPoint('BOTTOM', anchor, 'TOP', 0, 2)
			else
				tex:SetPoint('LEFT', st.marks[i - 1], 'RIGHT', 2, 0)
			end
		end
	end
end

local function NeedTint(plate, st)
	if st.tint then
		return st.tint
	end
	local health = HealthWidget(plate)
	if not health then
		return nil
	end
	st.tint = health.bar:CreateTexture(nil, 'OVERLAY', nil, 3)
	st.lowTint = health.bar:CreateTexture(nil, 'OVERLAY', nil, 4)
	st.tint:SetVertexColor(1, 1, 1, 0)
	st.lowTint:SetVertexColor(1, 1, 1, 0)
	Actions:Layout(plate)
	return st.tint
end

local function NeedBorder(plate, st)
	if st.border then
		return st.border
	end
	local health = HealthWidget(plate)
	if not health then
		return nil
	end
	local frame = CreateFrame('Frame', nil, health.bar)
	frame.edges = {}
	for _, side in ipairs({ 'top', 'bottom', 'left', 'right' }) do
		local edge = frame:CreateTexture(nil, 'OVERLAY', nil, 7)
		edge:SetTexture(White())
		edge:SetVertexColor(1, 1, 1, 0)
		frame.edges[side] = edge
		frame.edges[#frame.edges + 1] = edge
	end
	st.border = frame
	st.borderTarget = {
		SetVertexColor = function(_, r, g, b, a)
			for i = 1, #frame.edges do
				frame.edges[i]:SetVertexColor(r, g, b, a)
			end
		end,
	}
	Actions:Layout(plate)
	return frame
end

local function NeedGlow(plate, st)
	if not st.glow then
		st.glow = P.GlowLib.Create(plate.art)
		Actions:Layout(plate)
	end
	return st.glow
end

local function NeedMarks(plate, st, count)
	if not st.marksFrame then
		st.marksFrame = CreateFrame('Frame', nil, plate.art)
		st.marksFrame:SetAllPoints(plate.art)
	end
	local made = #st.marks
	if made < count then
		for i = made + 1, count do
			local tex = st.marksFrame:CreateTexture(nil, 'OVERLAY')
			tex:SetTexture(Actions.MARK_FILE)
			tex:Hide()
			st.marks[i] = tex
		end
		Actions:Layout(plate)
	end
	return st.marks
end

---Texture coordinates of a raid target icon cell (plain).
---@param mark string
---@return number left, number right, number top, number bottom
function Actions.MarkCoords(mark)
	local index = (Actions.MARKS[mark] or 1) - 1
	local col, row = index % 4, math.floor(index / 4)
	return col / 4, (col + 1) / 4, row / 4, (row + 1) / 4
end

----------------------------------------------------------------------------------------------------
-- Running the rules
----------------------------------------------------------------------------------------------------

local Conditions = P.Conditions

---The engine's answer for the single hidden clause of a rule (the caller swaps for negate).
local function LeafSecret(leaf, env)
	local cond = Conditions:Get(leaf.id)
	return cond.TestSecret(env, leaf.args)
end

local function RunGrow(plate, st, env)
	local w, h = 0, 0
	for _, rule in ipairs(st.rules) do
		if rule.effect == 'grow' and Conditions:Reduce(rule.clauses, env) == true then
			w, h = rule.grow[1], rule.grow[2]
			break
		end
	end
	if w ~= st.grow[1] or h ~= st.grow[2] then
		st.grow[1], st.grow[2] = w, h
		plate.grows = plate.grows or {}
		plate.grows.actions = (w ~= 0 or h ~= 0) and st.grow or nil
		plate:ApplyEmphasis(false)
	end
end

local function RunFade(plate, st, env)
	local onRule, secretRule, secretLeaf
	for _, rule in ipairs(st.rules) do
		if rule.effect == 'fade' then
			local result, leaf = Conditions:Reduce(rule.clauses, env)
			if result == true then
				onRule = rule
				break
			elseif result == nil and leaf and not secretRule then
				secretRule, secretLeaf = rule, leaf
			end
		end
	end
	local below = onRule and onRule.fade or 1
	local fader = plate.fader
	if secretRule then
		local conditionSecret = LeafSecret(secretLeaf, env)
		local negate = secretLeaf.negate == true
		local on, off = secretRule.fade, below
		if negate then
			on, off = off, on
		end
		Secret.SetAlphaFromBoolean(fader, conditionSecret, on, off)
		st.faded = true
	elseif below ~= 1 or st.faded then
		fader:SetAlpha(below)
		st.faded = below ~= 1
	end
end

local function RunGlow(plate, st, env)
	local onRule, secretRule, secretLeaf, any
	for _, rule in ipairs(st.rules) do
		if rule.effect == 'glow' then
			any = true
			local result, leaf = Conditions:Reduce(rule.clauses, env)
			if result == true then
				onRule = rule
				break
			elseif result == nil and leaf and not secretRule then
				secretRule, secretLeaf = rule, leaf
			end
		end
	end
	if not any and not st.glow then
		return
	end
	local GlowLib = P.GlowLib
	if not onRule and not secretRule then
		if st.glow then
			GlowLib.Hide(st.glow)
		end
		return
	end
	local glow = NeedGlow(plate, st)
	if secretRule then
		local conditionSecret = LeafSecret(secretLeaf, env)
		local negate = secretLeaf.negate == true
		local top = secretRule.glow
		if onRule then
			-- A glow shows either way; the hidden answer only picks its color
			local other = onRule.glow
			local a, b = top, other
			if negate then
				a, b = other, top
			end
			GlowLib.SetColorSecret(
				glow,
				Secret.ChooseValue(conditionSecret, a[1], b[1]),
				Secret.ChooseValue(conditionSecret, a[2], b[2]),
				Secret.ChooseValue(conditionSecret, a[3], b[3]),
				Secret.ChooseValue(conditionSecret, a[4], b[4])
			)
			GlowLib.Show(glow)
		else
			GlowLib.SetColor(glow, top[1], top[2], top[3], top[4])
			GlowLib.ShowWhenSecret(glow, conditionSecret)
			if negate then
				Secret.SetAlphaFromBoolean(glow.gate, conditionSecret, 0, 1)
			end
		end
		return
	end
	local c = onRule.glow
	GlowLib.SetColor(glow, c[1], c[2], c[3], c[4])
	GlowLib.Show(glow)
end

---The one hidden clause of a rule when it is low health (the curve path), else nil.
local function CurveLeaf(rule, env)
	local result, leaf = Conditions:Reduce(rule.clauses, env)
	if result == nil and leaf and leaf.id == 'lowHealth' then
		return leaf
	end
	return nil
end

---Settle the paint rules for one piece in Lua: the first rule that fits plainly decides the base,
---rules above it whose answer the game keeps wait in st.pending (folded by FoldPaintSecret), and
---the first hidden low health rule goes to the curve path (curveOut). Returns whether any rule can
---change the color (plain).
local function PaintPlan(st, env, piece, curveOut)
	local pending = st.pending
	for j = #pending, 1, -1 do
		pending[j] = nil
	end
	st.decided = nil
	curveOut.leaf, curveOut.rule = nil, nil
	for _, rule in ipairs(st.rules) do
		if rule.effect == 'paint' and rule.paint == piece then
			local result, leaf = Conditions:Reduce(rule.clauses, env)
			if result == true then
				st.decided = rule
				break
			elseif result == nil then
				if leaf and leaf.id == 'lowHealth' then
					if not curveOut.rule then
						curveOut.leaf, curveOut.rule = leaf, rule
					end
				else
					pending[#pending + 1] = rule
				end
			end
		end
	end
	return st.decided ~= nil or #pending > 0
end

---The color for one piece after PaintPlan (6.4): the deciding rule's color (or the base), with the
---hidden rules above it folded per channel, lowest priority first. Inputs and results may be secret.
local function FoldPaintSecret(st, env, rSecret, gSecret, bSecret, aSecret)
	local decided = st.decided
	if decided then
		local c = decided.color
		rSecret, gSecret, bSecret, aSecret = c[1], c[2], c[3], c[4]
	end
	local pending = st.pending
	for j = #pending, 1, -1 do
		local rule = pending[j]
		local c = rule.color
		rSecret, gSecret, bSecret = Conditions:FoldColorSecret(rule.expr, env, c[1], c[2], c[3], rSecret, gSecret, bSecret)
		aSecret = Conditions:FoldSecret(rule.expr, env, c[4], aSecret)
	end
	return rSecret, gSecret, bSecret, aSecret
end

local curveScratch = {}

---Low health as a texture's alpha where health is hidden: the curve's output goes straight to the
---texture. Returns true when it drew.
local function DrawCurve(texture, src, rule, leaf)
	local c = rule.color or rule.markColor or { 1, 1, 1, 1 }
	local curve = Conditions.LowHealthCurve(leaf.args, c[4] or 1, leaf.negate == true)
	if not curve or not src.HealthPercentSecret then
		return false
	end
	local alphaSecret = src:HealthPercentSecret(curve)
	if type(alphaSecret) == 'nil' then
		return false
	end
	texture:SetVertexColor(c[1], c[2], c[3], alphaSecret)
	return true
end

local function HasPaint(st, piece)
	for _, rule in ipairs(st.rules) do
		if rule.effect == 'paint' and rule.paint == piece then
			return true
		end
	end
	return false
end

local function RunPaintHealth(plate, st, env)
	if not HasPaint(st, 'health') then
		if st.tint then
			st.tint:SetVertexColor(1, 1, 1, 0)
			st.lowTint:SetVertexColor(1, 1, 1, 0)
		end
		return
	end
	local tint = NeedTint(plate, st)
	if not tint then
		return
	end
	if st.tintBar ~= HealthWidget(plate).bar then
		Actions:Layout(plate)
	end
	if PaintPlan(st, env, 'health', curveScratch) then
		local rSecret, gSecret, bSecret, aSecret = FoldPaintSecret(st, env, 0, 0, 0, 0)
		tint:SetVertexColor(rSecret, gSecret, bSecret, aSecret)
	else
		tint:SetVertexColor(1, 1, 1, 0)
	end
	local drew = false
	if curveScratch.rule then
		drew = DrawCurve(st.lowTint, env.src, curveScratch.rule, curveScratch.leaf)
	end
	if not drew then
		st.lowTint:SetVertexColor(1, 1, 1, 0)
	end
end

local function RunPaintBorder(plate, st, env)
	if not HasPaint(st, 'border') then
		if st.border then
			st.borderTarget:SetVertexColor(1, 1, 1, 0)
		end
		return
	end
	local frame = NeedBorder(plate, st)
	if not frame then
		return
	end
	if st.borderBar ~= HealthWidget(plate).bar then
		Actions:Layout(plate)
	end
	if PaintPlan(st, env, 'border', curveScratch) then
		local rSecret, gSecret, bSecret, aSecret = FoldPaintSecret(st, env, 0, 0, 0, 0)
		st.borderTarget:SetVertexColor(rSecret, gSecret, bSecret, aSecret)
	elseif curveScratch.rule then
		if not DrawCurve(frame.edges[1], env.src, curveScratch.rule, curveScratch.leaf) then
			st.borderTarget:SetVertexColor(1, 1, 1, 0)
		else
			for i = 2, #frame.edges do
				DrawCurve(frame.edges[i], env.src, curveScratch.rule, curveScratch.leaf)
			end
		end
	else
		st.borderTarget:SetVertexColor(1, 1, 1, 0)
	end
end

local WHITE_COLOR = { 1, 1, 1, 1 }

---The name's own color (what the text part drew), into the stand-in target: possibly secret.
local function NameBase(widget, st)
	local capture = st.capture
	local spec = widget.spec
	if spec.colors then
		local env = widget.plate.env
		P.Colors:Apply(P.Colors:Program(spec.colors, env.ctx), env, capture, 'SetTextColor')
	else
		local c = spec.color or widget.autoColor or WHITE_COLOR
		capture:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
	end
	return capture
end

local function RunPaintName(plate, st, env)
	local widget = NameWidget(plate)
	if not HasPaint(st, 'name') or not widget then
		if st.namePainted and widget then
			local base = NameBase(widget, st)
			widget.text:SetTextColor(base.rSecret, base.gSecret, base.bSecret, base.a)
		end
		st.namePainted = nil
		return
	end
	local base = NameBase(widget, st)
	local any = PaintPlan(st, env, 'name', curveScratch)
	if any or st.namePainted then
		local rSecret, gSecret, bSecret = FoldPaintSecret(st, env, base.rSecret, base.gSecret, base.bSecret, base.a)
		widget.text:SetTextColor(rSecret, gSecret, bSecret, base.a)
	end
	st.namePainted = any or nil
end

local function RunMarks(plate, st, env)
	local index = 0
	for _, rule in ipairs(st.rules) do
		if rule.effect == 'mark' and index < Actions.MAX_MARKS then
			index = index + 1
			local marks = NeedMarks(plate, st, index)
			local tex = marks[index]
			local c = rule.markColor or WHITE_COLOR
			local left, right, top, bottom = Actions.MarkCoords(rule.mark)
			tex:SetTexCoord(left, right, top, bottom)
			tex:Show()
			local result = Conditions:Reduce(rule.clauses, env)
			if result == true then
				tex:SetVertexColor(c[1], c[2], c[3], c[4])
			elseif result == false then
				tex:SetVertexColor(c[1], c[2], c[3], 0)
			else
				local leaf = CurveLeaf(rule, env)
				if not (leaf and DrawCurve(tex, env.src, rule, leaf)) then
					local alphaSecret = Conditions:FoldSecret(rule.expr, env, c[4], 0)
					tex:SetVertexColor(c[1], c[2], c[3], alphaSecret)
				end
			end
		end
	end
	for i = index + 1, #st.marks do
		st.marks[i]:Hide()
	end
end

---Run a plate's rules now (an event or message they listen to arrived, a state changed, or a part
---they paint over redrew itself).
---@param plate Plates.Plate
function Actions:Run(plate)
	local st = states[plate]
	if not st then
		return
	end
	local env = plate.env
	if #st.rules == 0 then
		if st.drawn then
			self:Clear(plate)
		end
		return
	end
	if not env.src then
		return
	end
	if st.laidOut ~= plate.styleKey then
		self:Layout(plate)
	end
	st.drawn = true
	local ok, err = pcall(function()
		RunGrow(plate, st, env)
		RunFade(plate, st, env)
		RunGlow(plate, st, env)
		RunPaintHealth(plate, st, env)
		RunPaintBorder(plate, st, env)
		RunPaintName(plate, st, env)
		RunMarks(plate, st, env)
	end)
	if not ok then
		WarnOnce('run', 'A "When" action could not run: ' .. tostring(err))
	end
end

---Take everything the rules drew off the plate (unbind, or the rules are gone).
---@param plate Plates.Plate
function Actions:Clear(plate)
	local st = states[plate]
	if not st then
		return
	end
	st.drawn = nil
	plate.actionsOn = #st.rules > 0 or nil
	if st.grow[1] ~= 0 or st.grow[2] ~= 0 then
		st.grow[1], st.grow[2] = 0, 0
		if plate.grows then
			plate.grows.actions = nil
		end
		plate:ApplyEmphasis(true)
	end
	if plate.fader and st.faded then
		plate.fader:SetAlpha(1)
		st.faded = nil
	end
	if st.glow then
		P.GlowLib.Reset(st.glow)
	end
	if st.tint then
		st.tint:SetVertexColor(1, 1, 1, 0)
		st.lowTint:SetVertexColor(1, 1, 1, 0)
	end
	if st.border then
		st.borderTarget:SetVertexColor(1, 1, 1, 0)
	end
	for i = 1, #st.marks do
		st.marks[i]:Hide()
	end
	st.namePainted = nil
end

---Plain words for the inspector: the rules that apply to a plate right now ("Fade: yes", "Glow:
---the game decides").
---@param plate Plates.Plate
---@return string[] lines
function Actions:Describe(plate)
	local out = {}
	local st = states[plate]
	if not st then
		return out
	end
	for _, rule in ipairs(st.rules) do
		local result, _, unknown = Conditions:Reduce(rule.clauses, plate.env)
		local state = L['no']
		if result == true then
			state = L['yes']
		elseif result == nil then
			state = unknown > 1 and L['the game decides (only one hidden condition can work here)'] or L['the game decides']
		end
		out[#out + 1] = string.format(L['Rule %d: %s'], rule.index, state)
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- Keeping plates current
----------------------------------------------------------------------------------------------------

---Attach and run again on every drawn plate (settings, role or profile changed).
function Actions:RefreshAll()
	local Driver = P.Driver
	if not (Driver and Driver.ForEachPlate) then
		return
	end
	Driver:ForEachPlate(function(plate)
		Actions:Refresh(plate)
	end)
end

---Re-attach one plate (its rules may have changed), register its events again and run it.
---@param plate Plates.Plate
function Actions:Refresh(plate)
	if plate.RefreshRole then
		plate:RefreshRole()
	end
	self:Attach(plate)
	if plate.RegisterUnitEvents then
		plate:RegisterUnitEvents()
	end
	self:Run(plate)
end

local function SettingsChanged(reasons, keys)
	local touched = reasons == nil or reasons.assignment or reasons.colors
	if not touched and type(keys) == 'table' then
		for _, key in ipairs(keys) do
			if key == 'actions' then
				touched = true
			end
		end
	end
	if touched then
		Actions:Invalidate()
		Actions:RefreshAll()
	end
end

P:On('STORE_CHANGED', SettingsChanged, Actions)
P:On('PROFILE_CHANGED', function()
	Actions:Invalidate()
	Actions:RefreshAll()
end, Actions)
P:On('CONTEXT_CHANGED', function(keys)
	if keys == nil or keys.role then
		Actions:RefreshAll()
	end
end, Actions)
