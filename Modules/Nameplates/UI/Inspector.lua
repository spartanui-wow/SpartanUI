local _, ns = ...
local P = ns.Plates
local L = P.L

-- "Why this color" (3.2 hover in the preview, 3.7 Alt-hover in the world).
--   Inspector:Explain(plate, piece)  one line, e.g. "Red: Threat (you are not tanking)". Plain
--                                    chains name the winning row; when hidden rows could have
--                                    decided, it says "One of: X, Y", because Lua cannot read the
--                                    result. In the preview the answer is always exact (samples
--                                    are plain).
--   Inspector:PieceOf(spec)          which color list a part shows (nil for parts without one)
--   Inspector:Detail(plate, widget)  the preview tooltip's detail line for a part: its color
--                                    line, else a plain sentence when the part cannot work on
--                                    this client
--   Inspector:Lines(plate)           every color line of a plate, for the Alt tooltip
--   Inspector:RuleLines(plate)       the "When something happens" rules that apply to a plate in
--                                    plain words (Actions:Describe, under a heading); empty when
--                                    there are none. Added to Detail for colored parts and to the
--                                    Alt tooltip.
-- Alt-hover: while the engine runs, holding Alt over a real plate (the Driver's mouseover plate)
-- shows a tooltip with a line per colored piece. It never reads secrets: rows the game decides
-- are named with "One of:". The watcher is set up on ENGINE_ENABLED and removed on
-- ENGINE_DISABLED (nothing is registered while the engine is off).

---@class Plates.Inspector
local Inspector = { tipShown = false }
P.Inspector = Inspector

Inspector.PIECE_LABELS = {
	health = L['Health bar'],
	border = L['Border'],
	name = L['Name'],
	cast = L['Cast bar'],
}

----------------------------------------------------------------------------------------------------
-- Words
----------------------------------------------------------------------------------------------------

---A plain color word for a color ("Red", "Blue", ...).
---@param r number
---@param g number
---@param b number
---@return string
function Inspector.ColorName(r, g, b)
	r, g, b = r or 0, g or 0, b or 0
	local max, min = math.max(r, g, b), math.min(r, g, b)
	if max < 0.15 then
		return L['Black']
	end
	local sat = (max - min) / max
	if sat < 0.2 then
		if max > 0.85 then
			return L['White']
		end
		return L['Gray']
	end
	local d = max - min
	local hue
	if max == r then
		hue = ((g - b) / d) % 6
	elseif max == g then
		hue = (b - r) / d + 2
	else
		hue = (r - g) / d + 4
	end
	hue = hue * 60
	if hue < 15 or hue >= 340 then
		return L['Red']
	elseif hue < 45 then
		return L['Orange']
	elseif hue < 70 then
		return L['Yellow']
	elseif hue < 165 then
		return L['Green']
	elseif hue < 255 then
		return L['Blue']
	elseif hue < 290 then
		return L['Purple']
	end
	return L['Pink']
end

local THREAT_WORDS = {
	tank = {
		safe = L['you are tanking'],
		losing = L['you are losing it'],
		lost = L['you are not tanking'],
	},
	other = {
		safe = L['you are safe'],
		losing = L['you are about to pull it'],
		lost = L['it is attacking you'],
	},
	offTank = L['another tank has it'],
	pet = L['your pet has it'],
	solo = L['you are on your own'],
}

local MOB_WORDS = {
	boss = L['boss'],
	miniboss = L['mini-boss'],
	caster = L['caster'],
	elite = L['elite'],
	normal = L['normal'],
	minor = L['minor'],
}

---@param state string|nil Roles.STATES
---@param role string
---@return string|nil
local function ThreatWords(state, role)
	if not state then
		return nil
	end
	if THREAT_WORDS[state] and type(THREAT_WORDS[state]) == 'string' then
		return THREAT_WORDS[state]
	end
	local set = role == 'tank' and THREAT_WORDS.tank or THREAT_WORDS.other
	return set[state]
end

---Words for the part of a mapped row that applies to this plate ("you are not tanking").
---@param row Plates.ColorRow
---@param env table
---@return string|nil
local function StateWords(row, env)
	local facts = env.facts or {}
	local ctx = env.ctx or P.Context
	local id = row.id
	if id == 'threat' then
		local src = env.src
		if not src then
			return nil
		end
		local status, readable = src:ThreatStatusPlain()
		if not readable then
			return nil
		end
		return ThreatWords(P.Roles.ThreatState(ctx.role, status, ctx.inGroup), ctx.role)
	elseif id == 'offTank' then
		return THREAT_WORDS.offTank
	elseif id == 'petTank' then
		return THREAT_WORDS.pet
	elseif id == 'mobType' then
		local mobType = facts.mobType or P.Situation.MobType(facts, ctx)
		return mobType and MOB_WORDS[mobType] or nil
	elseif id == 'class' then
		local token = facts.classToken
		local names = LOCALIZED_CLASS_NAMES_MALE
		return token and ((names and names[token]) or token:lower()) or nil
	elseif id == 'reaction' then
		local reaction = facts.reaction
		if not reaction then
			return nil
		elseif reaction <= 3 then
			return L['hostile']
		elseif reaction == 4 then
			return L['neutral']
		end
		return L['friendly']
	end
	return nil
end

---The plain color a winning row gives (rows only win on plain values).
---@param row Plates.ColorRow
---@param env table
---@return number|nil r
---@return number|nil g
---@return number|nil b
local function RowColor(row, env)
	if row.color then
		return row.color[1], row.color[2], row.color[3]
	end
	local kind = row.kind
	if kind and kind.Resolve then
		local ok, matched, r, g, b = pcall(kind.Resolve, env, row)
		if ok and matched == true then
			return r, g, b
		end
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- Explanations
----------------------------------------------------------------------------------------------------

---One line explaining a piece's color on a plate, e.g. "Red: Threat (you are not tanking)".
---@param plate Plates.Plate
---@param piece string 'health' | 'border' | 'name' | 'cast'
---@return string
function Inspector:Explain(plate, piece)
	local Colors = P.Colors
	local env = plate.env
	local program = Colors:Program(piece, env.ctx)
	local ok, winner, maybe = pcall(Colors.Explain, Colors, program, env)
	if not ok then
		return L['Default color']
	end
	maybe = maybe or {}
	if #maybe > 0 then
		local names = {}
		for _, row in ipairs(maybe) do
			names[#names + 1] = Colors:Sentence(row)
		end
		if winner then
			names[#names + 1] = Colors:Sentence(winner)
		else
			names[#names + 1] = L['Default color']
		end
		return L['One of:'] .. ' ' .. table.concat(names, ', ')
	end
	if not winner then
		local fallback = program.fallback
		if fallback then
			return Inspector.ColorName(fallback[1], fallback[2], fallback[3]) .. ': ' .. L['Default color']
		end
		return L['Default color']
	end
	if winner.kind and winner.kind.type == 'boolean' then
		-- Boolean rows already say their color ("Gray when someone else tagged it first")
		return Colors:Sentence(winner)
	end
	local r, g, b = RowColor(winner, env)
	local label = winner.kind and winner.kind.label or Colors:Sentence(winner)
	local words = StateWords(winner, env)
	local text = words and (label .. ' (' .. words .. ')') or label
	if r then
		return Inspector.ColorName(r, g, b) .. ': ' .. text
	end
	return text
end

---Which color list a part shows: its own `colors` field, else the list its kind always uses.
---@param spec table
---@return string|nil piece
---@return string|nil borderPiece The bar border's list, when it has one
function Inspector:PieceOf(spec)
	if not spec then
		return nil
	end
	local piece = spec.colors
	if not piece then
		if spec.kind == 'bar' and spec.source == 'health' then
			piece = 'health'
		elseif spec.kind == 'cast' then
			piece = 'cast'
		elseif spec.kind == 'text' and (spec.source == 'name' or spec.source == 'nameFill') then
			piece = 'name'
		end
	end
	return piece, spec.borderColors
end

---A plain sentence when a part cannot show here (from the part's own Limit helpers).
---@param spec table
---@return string|nil
local function LimitOf(spec)
	local kind, source = spec.kind, spec.source
	local helper, arg
	if kind == 'text' and P.TextParts and P.TextParts.Limit then
		helper, arg = P.TextParts.Limit, source
	elseif kind == 'icon' and P.IconParts and P.IconParts.Limit then
		helper, arg = P.IconParts.Limit, source
	elseif kind == 'glow' and P.GlowLib and P.GlowLib.Limit then
		helper, arg = P.GlowLib.Limit, source
	elseif kind == 'auras' and P.AuraScan and P.AuraScan.Limit then
		helper, arg = P.AuraScan.Limit, spec.row
	end
	if not helper or arg == nil then
		return nil
	end
	local ok, text = pcall(helper, arg)
	if ok and type(text) == 'string' and text ~= '' then
		return text
	end
	return nil
end

---The "When" rules that apply to a plate, one line each, under a heading. Nothing is read from the
---game here: Actions:Describe says "the game decides" for the rules it cannot settle.
---@param plate Plates.Plate
---@return string[] lines Empty when no rule applies
function Inspector:RuleLines(plate)
	local Actions = P.Actions
	if not (plate and Actions and Actions.Describe) then
		return {}
	end
	local ok, described = pcall(Actions.Describe, Actions, plate)
	if not ok or type(described) ~= 'table' or #described == 0 then
		return {}
	end
	local lines = { L['When something happens'] }
	for _, line in ipairs(described) do
		lines[#lines + 1] = line
	end
	return lines
end

---The detail line for a part in the preview tooltip: its color, or why it may stay empty here.
---@param plate Plates.Plate
---@param widget Plates.Widget|string A widget, or a part id on that plate
---@return string|nil
function Inspector:Detail(plate, widget)
	local spec
	if type(widget) == 'string' then
		spec = plate and plate.style and plate.style.parts[widget]
	else
		spec = widget and widget.spec
	end
	if not spec then
		return nil
	end
	local piece, borderPiece = self:PieceOf(spec)
	local lines = {}
	if piece then
		lines[#lines + 1] = self:Explain(plate, piece)
	end
	if borderPiece and borderPiece ~= piece then
		lines[#lines + 1] = (self.PIECE_LABELS.border or L['Border']) .. ': ' .. self:Explain(plate, borderPiece)
	end
	if piece or borderPiece then
		for _, line in ipairs(self:RuleLines(plate)) do
			lines[#lines + 1] = line
		end
	end
	local limit = LimitOf(spec)
	if limit then
		lines[#lines + 1] = limit
	end
	if #lines == 0 then
		return nil
	end
	return table.concat(lines, '\n')
end

---Every color line of a plate, one per colored piece its parts show, for the Alt tooltip.
---@param plate Plates.Plate
---@return string[] lines "Health bar: Red: Threat (you are not tanking)"
function Inspector:Lines(plate)
	local seen, lines = {}, {}
	for i = 1, #(plate.active or {}) do
		local widget = plate.active[i]
		local piece, borderPiece = self:PieceOf(widget.spec)
		for _, which in ipairs({ piece or false, borderPiece or false }) do
			if which and not seen[which] then
				seen[which] = true
				lines[#lines + 1] = (self.PIECE_LABELS[which] or which) .. ': ' .. self:Explain(plate, which)
			end
		end
	end
	return lines
end

----------------------------------------------------------------------------------------------------
-- Alt-hover a real plate (3.7)
----------------------------------------------------------------------------------------------------

local OWNER = 'Inspector'

---The real plate under the mouse, when the engine knows it plainly.
---@return Plates.Plate|nil
function Inspector:MouseoverPlate()
	local Driver = P.Driver
	if not Driver then
		return nil
	end
	local found
	if Driver.GetPlateForUnit then
		local ok, plate = pcall(Driver.GetPlateForUnit, Driver, 'mouseover')
		if ok and plate and plate.src and plate.states and plate.states.mouseover then
			found = plate
		end
	end
	if not found and Driver.ForEachPlate then
		Driver:ForEachPlate(function(plate)
			if not found and plate.states and plate.states.mouseover then
				found = plate
			end
		end)
	end
	return found
end

function Inspector:HideTip()
	if self.tipShown then
		self.tipShown = false
		-- Leave the tooltip alone when something else took it over since
		local owner = GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner()
		if GameTooltip and (owner == nil or owner == UIParent) then
			GameTooltip:Hide()
		end
	end
end

---Show the "why this color" tooltip for the real plate under the mouse.
---@return boolean shown
function Inspector:ShowTip()
	local plate = self:MouseoverPlate()
	if not plate or not GameTooltip then
		self:HideTip()
		return false
	end
	local lines = self:Lines(plate)
	local rules = self:RuleLines(plate)
	if #lines == 0 and #rules == 0 then
		self:HideTip()
		return false
	end
	local name, readable
	if plate.src and plate.src.NamePlain then
		name, readable = plate.src:NamePlain()
	end
	GameTooltip:SetOwner(UIParent, 'ANCHOR_CURSOR')
	GameTooltip:SetText((readable and type(name) == 'string' and name ~= '') and name or L['Why these colors'], 1, 1, 1)
	for _, line in ipairs(lines) do
		GameTooltip:AddLine(line, 0.9, 0.9, 0.9, true)
	end
	if #lines > 0 then
		GameTooltip:AddLine(L['The top color row that fits wins. Change the order on the Colors page.'], 0.55, 0.8, 1, true)
	end
	for i, line in ipairs(rules) do
		if i == 1 then
			GameTooltip:AddLine(line, 1, 0.82, 0, true)
		else
			GameTooltip:AddLine(line, 0.9, 0.9, 0.9, true)
		end
	end
	GameTooltip:Show()
	self.tipShown = true
	return true
end

local function AltDown()
	local fn = IsAltKeyDown
	return fn and fn() and true or false
end

---MODIFIER_STATE_CHANGED: Alt pressed shows the tooltip, released hides it.
function Inspector:OnModifier(key, down)
	if key ~= 'LALT' and key ~= 'RALT' then
		return
	end
	if down == 1 or down == true then
		self:ShowTip()
	else
		self:HideTip()
	end
end

function Inspector:WatchWorld(on)
	if on then
		P:RegisterEvent('MODIFIER_STATE_CHANGED', OWNER, function(_, key, down)
			Inspector:OnModifier(key, down)
		end)
		P:On('MOUSEOVER_CHANGED', function()
			if AltDown() then
				Inspector:ShowTip()
			else
				Inspector:HideTip()
			end
		end, Inspector)
	else
		P:UnregisterEvent('MODIFIER_STATE_CHANGED', OWNER)
		P:Off('MOUSEOVER_CHANGED', Inspector)
		self:HideTip()
	end
end

P:On('ENGINE_ENABLED', function()
	Inspector:WatchWorld(true)
end, OWNER)
P:On('ENGINE_DISABLED', function()
	Inspector:WatchWorld(false)
end, OWNER)
