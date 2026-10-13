local _, ns = ...
local P = ns.Plates
local L = P.L
local Options = P.Options
local util = P.util

-- Customize page (3.2 #2). A part list in groups (Bar, Text, Cast, Auras, Icons, Emphasis), each
-- row with an eye switch; picking a part (here or in the preview panel) outlines it in the panel
-- and shows only that part's settings: Position (drag in the panel, or the anchor grid with
-- nudges), Size, Text, "Color comes from" (with a link to the Colors page) and Reset this part.
-- The Cast bar part holds every cast setting; each aura row part holds its row card; the Target
-- highlight part holds the art picker and target emphasis. More settings for any part: layer,
-- alpha, pixel snapping, draw above other plates.
--
-- The page keeps no state: the selection, the "Preview as" kind and the scope live in P.Designer
-- (session only), and every edit goes through P.Designer, which writes the player's overlay
-- profile.tweaks[styleId] (or tweaks[styleId].situations[kind] with "Only for these plates") as
-- one undo step. Every part's group is built at once and hidden unless it is the selected part,
-- so picking a part only needs a redraw, never a new table. Every get reads the style again.

local Designer = P.Designer

---@class Plates.CustomizePage
local Customize = {}
P.CustomizePage = Customize

local POINT_LABELS = {
	TOPLEFT = L['Top left'],
	TOP = L['Top'],
	TOPRIGHT = L['Top right'],
	LEFT = L['Left'],
	CENTER = L['Center'],
	RIGHT = L['Right'],
	BOTTOMLEFT = L['Bottom left'],
	BOTTOM = L['Bottom'],
	BOTTOMRIGHT = L['Bottom right'],
}
local OUTLINES = { [''] = L['None'], OUTLINE = L['Thin'], THICKOUTLINE = L['Thick'] }
local OUTLINE_ORDER = { '', 'OUTLINE', 'THICKOUTLINE' }
local JUSTIFY = { LEFT = L['Left'], CENTER = L['Center'], RIGHT = L['Right'] }
local PIECES = { health = L['Health bar colors'], border = L['Border colors'], name = L['Name colors'], cast = L['Cast bar colors'] }
local PIECE_ORDER = { 'health', 'border', 'name', 'cast' }
local SIDES = { above = L['Above'], left = L['Left'], right = L['Right'], below = L['Below'] }
local SIDE_ORDER = { 'above', 'left', 'right', 'below' }
local HIGHLIGHT_ARTS = {
	arrows = L['Arrows'],
	doubleArrows = L['Double arrows'],
	brackets = L['Brackets'],
	glow = L['Glow'],
	underline = L['Underline'],
	sideBars = L['Side bars'],
}
local HIGHLIGHT_ORDER = { 'arrows', 'doubleArrows', 'brackets', 'glow', 'underline', 'sideBars' }
local ANIMATE = { none = L['None'], pulse = L['Pulse'], bounce = L['Bounce'] }
local BLEND = { BLEND = L['Normal'], ADD = L['Bright'] }
local BORDERS = { none = L['None'], pixel = L['Thin line'], thick = L['Thick line'], shadow = L['Shadow'], beveled = L['Beveled'] }
local BORDER_ORDER = { 'none', 'pixel', 'thick', 'shadow', 'beveled' }
local AURA_BORDERS = { none = L['None'], pixel = L['Thin line'], dispel = L['Color by type'] }
local SORTS = { default = L['Game order'], time = L['Time left'], name = L['Name'] }
local TIME_FORMATS = { remaining = L['Time left'], elapsed = L['Time spent'], both = L['Both'] }
local KICK_MARKS = { off = L['Off'], line = L['Line'], fill = L['Line and fill'] }
local KICK_ORDER = { 'off', 'line', 'fill' }
local ICON_SIDES = { left = L['Left'], right = L['Right'], none = L['None'] }
local REGIONS = { click = L['Click area'], stack = L['Stacking area'] }
local ABSORB_MODES = { overlay = L['Over the missing health'], extend = L['Make room for it'] }

----------------------------------------------------------------------------------------------------
-- Reading and writing
----------------------------------------------------------------------------------------------------

local function Spec(id)
	return Designer:Spec(id) or {}
end

local function Value(id, field)
	return Designer:Value(id, field)
end

---get/set for one part field. transform(value) turns the control's value into the stored one.
local function Field(id, field, transform, read)
	local function Get()
		local value = Value(id, field)
		if read then
			return read(value)
		end
		return value
	end
	local function Set(_, value)
		if transform then
			value = transform(value)
		end
		Designer:Change(id, field, value)
	end
	return Get, Set
end

local function Tokens()
	return Designer:Effective(nil).style.tokens or {}
end

---A color field as r, g, b, a (tokens resolved to show the color the plate draws).
local function ColorGet(id, field, fallback)
	return function()
		local value = Value(id, field)
		if type(value) == 'string' then
			value = P.Styles.Merge.ResolveTokens(value, Tokens(), P.hostLook)
		end
		if type(value) ~= 'table' then
			value = fallback or { 1, 1, 1, 1 }
		end
		return value[1] or 1, value[2] or 1, value[3] or 1, value[4] or 1
	end
end

local function ColorSet(id, field)
	return function(_, r, g, b, a)
		Designer:Change(id, field, { r, g, b, a or 1 })
	end
end

---Style-wide state fields (target growth, fades) for the Target highlight part.
local function StateValue(state, field)
	local effective = Designer:Effective(nil).style
	local states = effective.states or {}
	local kind = Designer:ScopeKind()
	local patch = kind and effective.situations and effective.situations[kind]
	if patch and patch.states then
		states = P.Styles.Merge.Deep(states, patch.states)
	end
	return states[state] and states[state][field]
end

local function SetState(state, field, value)
	local styleId = Designer:StyleId()
	local kind = Designer:ScopeKind()
	local below
	local path
	if kind then
		path = { 'tweaks', styleId, 'situations', kind, 'states', state, field }
		local states = Designer:Effective(nil).style.states
		below = states and states[state] and states[state][field]
	else
		path = { 'tweaks', styleId, 'changes', 'states', state, field }
		local states = Designer:Effective(nil).base.states
		below = states and states[state] and states[state][field]
	end
	if value ~= nil and util.Equal(below, value) then
		value = nil
	end
	Designer:Edit('edit', function()
		P.Store:Set(path, value)
	end, 'state:' .. state .. ':' .. field)
end

local function BaseState(state, field)
	local states = Designer:Effective(nil).base.states
	return states and states[state] and states[state][field]
end

local function LockedAuras()
	return Options.Locked()
end

local function HostOpen(page)
	local host = P.host
	if host and host.OpenOptions then
		host.OpenOptions(page)
	end
end

local function FontChoices()
	local values = { ['$font'] = L['Style font'] }
	local media = P.services and P.services.media
	if media and media.List then
		local ok, list = pcall(media.List, media, 'font')
		if ok and type(list) == 'table' then
			for _, name in ipairs(list) do
				values[name] = name
			end
		end
	end
	return values
end

local function Sorted(map)
	local keys = {}
	for k in pairs(map) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	return keys
end

----------------------------------------------------------------------------------------------------
-- The part list
----------------------------------------------------------------------------------------------------

---@class Plates.PartRow
---@field header? string Group heading
---@field id? string Part id (rows and sub rows)
---@field key? string Eye key: the part id, or 'id:sub'
---@field label? string
---@field sub? boolean A feature row under its part
---@field shown? boolean
---@field selected? boolean
---@field locked? boolean The eye cannot change (the style hides it on these plates)
---@field badge? string
---@field tooltip? string

---Rows for the part list, grouped (pure over the Designer state).
---@return Plates.PartRow[]
function Customize.Rows()
	local kind = Designer:ScopeKind()
	local view = Designer:Effective(kind or Designer:PreviewKind())
	local whole = Designer:Effective(kind)
	local byGroup = {}
	for id, spec in pairs(view.parts) do
		local group, label = Designer.PartInfo(id, spec)
		byGroup[group] = byGroup[group] or {}
		table.insert(byGroup[group], { id = id, spec = spec, label = label, order = spec.order or 0 })
	end
	local rows = {}
	for _, group in ipairs(Designer.GROUPS) do
		local list = byGroup[group]
		if list then
			table.sort(list, function(a, b)
				if a.order ~= b.order then
					return a.order < b.order
				end
				return a.id < b.id
			end)
			rows[#rows + 1] = { header = Designer.GROUP_LABELS[group] }
			for _, item in ipairs(list) do
				local id, spec = item.id, item.spec
				local hiddenHere = view.hidden[id]
				local shown = not whole.hidden[id]
				local badge
				local scoped = Designer:ScopedKinds(id)
				if hiddenHere == 'style' then
					badge = L['Hidden on these plates']
				elseif #scoped > 0 then
					badge = #scoped == 1 and string.format(L['%s only'], Designer.KIND_LABELS[scoped[1]]) or L['Changed for some plates']
				elseif Designer:IsAdded(id) then
					badge = L['Added']
				end
				rows[#rows + 1] = {
					id = id,
					key = id,
					label = item.label,
					shown = shown,
					selected = Designer:IsSelected(id),
					locked = hiddenHere == 'style',
					badge = badge,
				}
				for _, sub in ipairs(Designer.SUB_ROWS[spec.kind] or {}) do
					if not sub.when or sub.when(spec) then
						rows[#rows + 1] = { id = id, key = id .. ':' .. sub.key, label = sub.label, sub = true, shown = shown and sub.on(spec), selected = false, locked = not shown }
					end
				end
			end
		end
	end
	return rows
end

---Apply a value from the part list: a part id selects it; 'show:key' and 'hide:key' are the eyes.
---@param value string
function Customize.ApplyListValue(value)
	if type(value) ~= 'string' then
		return
	end
	local action, key = string.match(value, '^(%a+):(.+)$')
	if action == 'show' or action == 'hide' then
		local id, sub = string.match(key, '^([^:]+):(.+)$')
		if id then
			Designer:SetSubRow(id, sub, action == 'show')
		else
			Designer:SetHidden(key, action == 'hide')
		end
		return
	end
	Designer:Select(value, IsShiftKeyDown and IsShiftKeyDown() or false)
end

-- The PartList widget (an AceConfig select): rows with an eye switch; a click picks the part.
local ROW_H, HEADER_H, SUB_INDENT, LABEL_H = 22, 20, 18, 18

local Widgets = P.Widgets
local Draw = Widgets and Widgets.Draw

local function PaintRow(row)
	if not Draw then
		return
	end
	local data = row.data or {}
	local r, g, b = Draw.Accent()
	if data.selected then
		row.fill:SetVertexColor(r, g, b, 0.22)
		row.mark:SetVertexColor(r, g, b, 1)
		row.mark:Show()
	elseif row.hovered then
		row.fill:SetVertexColor(Draw.Color('hover'))
		row.mark:Hide()
	else
		row.fill:SetVertexColor(0, 0, 0, 0)
		row.mark:Hide()
	end
	Draw.Paint(row.label, (data.shown and not data.locked) and 'text' or 'muted')
end

local function Row_OnEnter(row)
	row.hovered = true
	PaintRow(row)
	local data = row.data or {}
	if Draw and data.label then
		local body = data.sub and L['Turn this on or off.'] or L['Click to change this part. The switch shows or hides it.']
		if data.locked then
			body = data.sub and L['Show the part first.'] or L['This style hides it on these plates.']
		end
		Draw.ShowTooltip(row, data.label, body)
	end
end

local function Row_OnLeave(row)
	row.hovered = false
	PaintRow(row)
	if Draw then
		Draw.HideTooltip()
	end
end

local function Row_OnClick(row)
	local widget = row.obj
	local data = row.data
	if not (widget and data and data.id) or widget.disabled then
		return
	end
	widget:Fire('OnValueChanged', data.id)
end

local function Eye_OnClick(switch)
	local row = switch.row
	local widget = row and row.obj
	local data = row and row.data
	if not (widget and data and data.key) or widget.disabled or data.locked then
		return
	end
	widget:Fire('OnValueChanged', (data.shown and 'hide:' or 'show:') .. data.key)
end

local function GetRow(widget, index)
	local row = widget.rows[index]
	if row then
		return row
	end
	row = CreateFrame('Button', nil, widget.frame)
	row:SetHeight(ROW_H)
	row.obj = widget
	row.fill = Draw.Rect(row, 'BACKGROUND')
	row.fill:SetAllPoints()
	row.mark = Draw.Rect(row, 'ARTWORK')
	row.mark:SetWidth(2)
	row.mark:SetPoint('TOPLEFT')
	row.mark:SetPoint('BOTTOMLEFT')
	row.eye = Draw.Switch(row)
	row.eye.row = row
	row.eye.onClick = Eye_OnClick
	row.label = Draw.Text(row, 12, 'text')
	row.badge = Draw.Text(row, 10, 'muted')
	row.badge:SetJustifyH('RIGHT')
	row.badge:SetPoint('RIGHT', row, 'RIGHT', -6, 0)
	row:SetScript('OnEnter', Row_OnEnter)
	row:SetScript('OnLeave', Row_OnLeave)
	row:SetScript('OnClick', Row_OnClick)
	widget.rows[index] = row
	return row
end

local function GetHeader(widget, index)
	local header = widget.headers[index]
	if not header then
		header = Draw.Text(widget.frame, 10, 'faint')
		widget.headers[index] = header
	end
	return header
end

local function PlaceList(widget)
	local items = widget.items or {}
	local top = 0
	if widget.labelText and widget.labelText ~= '' then
		top = LABEL_H
	end
	local rowIndex, headerIndex = 0, 0
	for _, item in ipairs(items) do
		if item.header then
			headerIndex = headerIndex + 1
			local header = GetHeader(widget, headerIndex)
			header:ClearAllPoints()
			header:SetPoint('TOPLEFT', widget.frame, 'TOPLEFT', 2, -top - 6)
			header:SetText(string.upper(item.header))
			header:Show()
			top = top + HEADER_H
		else
			rowIndex = rowIndex + 1
			local row = GetRow(widget, rowIndex)
			row.data = item
			row:ClearAllPoints()
			row:SetPoint('TOPLEFT', widget.frame, 'TOPLEFT', 0, -top)
			row:SetPoint('TOPRIGHT', widget.frame, 'TOPRIGHT', 0, -top)
			local indent = item.sub and SUB_INDENT or 0
			row.eye:ClearAllPoints()
			row.eye:SetPoint('LEFT', row, 'LEFT', 8 + indent, 0)
			Draw.SetSwitch(row.eye, item.shown)
			Draw.SetEnabled(row.eye, not (item.locked or widget.disabled))
			Draw.SetTooltip(row.eye, item.shown and L['Hide it'] or L['Show it'], nil)
			row.label:ClearAllPoints()
			row.label:SetPoint('LEFT', row.eye, 'RIGHT', 8, 0)
			row.label:SetPoint('RIGHT', row.badge, 'LEFT', -6, 0)
			Draw.SetFont(row.label, item.sub and 11 or 12)
			row.label:SetText(item.label or '')
			row.badge:SetText(item.badge or '')
			row:Show()
			PaintRow(row)
			top = top + ROW_H + 1
		end
	end
	for i = rowIndex + 1, #widget.rows do
		widget.rows[i]:Hide()
	end
	for i = headerIndex + 1, #widget.headers do
		widget.headers[i]:Hide()
	end
	return top + 4
end

local function Relayout(widget)
	if Draw then
		Draw.RunLayout(widget, PlaceList)
	end
end

local function Reload(widget)
	local arg = widget.arg
	local ok, items = false, nil
	if arg and type(arg.rows) == 'function' then
		ok, items = pcall(arg.rows)
	end
	widget.items = (ok and type(items) == 'table') and items or {}
	Relayout(widget)
end

local listMethods = {
	OnAcquire = function(self)
		self.arg = nil
		self.items = {}
		self.disabled = false
		self:SetLabel('')
	end,
	OnRelease = function(self)
		self.arg = nil
		self.items = {}
		for _, row in ipairs(self.rows) do
			row.data = nil
			row.hovered = false
			row:Hide()
		end
	end,
	OnWidthSet = function(self)
		if Draw then
			Draw.LayoutPass(self, Relayout)
		end
	end,
	SetLabel = function(self, text)
		self.labelText = text or ''
		self.label:SetText(self.labelText)
		self.label:SetShown(self.labelText ~= '')
		Relayout(self)
	end,
	SetList = function(self, values)
		self.values = values
	end,
	SetValue = function(self, value)
		self.value = value
		Reload(self)
	end,
	GetValue = function(self)
		return self.value
	end,
	SetDisabled = function(self, disabled)
		self.disabled = disabled and true or false
		Relayout(self)
	end,
	SetCustomData = function(self, arg)
		self.arg = type(arg) == 'table' and arg or nil
		Reload(self)
	end,
}

local function PartListConstructor()
	local AceGUI = LibStub('AceGUI-3.0')
	local frame = CreateFrame('Frame', nil, UIParent)
	frame:Hide()
	local widget = { frame = frame, type = Widgets:TypeName('PartList'), rows = {}, headers = {}, items = {} }
	widget.label = Draw.Text(frame, 12, 'text')
	widget.label:SetPoint('TOPLEFT', 0, -2)
	for name, fn in pairs(listMethods) do
		widget[name] = fn
	end
	Draw.OnAccent(frame, function()
		for _, row in ipairs(widget.rows) do
			PaintRow(row)
		end
	end)
	return AceGUI:RegisterAsWidget(widget)
end

if Widgets and Draw then
	Widgets.types.PartList = { version = 1, Constructor = PartListConstructor }
end

----------------------------------------------------------------------------------------------------
-- Controls for one part
----------------------------------------------------------------------------------------------------

local function Scope(order)
	return {
		type = 'toggle',
		order = order,
		width = 'full',
		name = function()
			return string.format(L['Only for %s'], Designer.KIND_PLURALS[Designer:PreviewKind()] or '')
		end,
		desc = L['Changes go only to the plates picked in "Show" at the top of the preview. Turn it off to change every plate.'],
		get = function()
			return Designer:Scope() == 'kind'
		end,
		set = function(_, on)
			Designer:SetScope(on and 'kind' or 'all')
		end,
	}
end

local function ScopedNote(id, order)
	return {
		type = 'description',
		order = order,
		fontSize = 'small',
		width = 'full',
		name = function()
			local names = {}
			for _, kind in ipairs(Designer:ScopedKinds(id)) do
				names[#names + 1] = Designer.KIND_LABELS[kind]
			end
			return string.format(L['These plates have their own changes for this part: %s'], table.concat(names, ', '))
		end,
		hidden = function()
			return #Designer:ScopedKinds(id) == 0
		end,
	}
end

local function ResetScoped(id, order)
	return {
		type = 'execute',
		order = order,
		name = function()
			return string.format(L['Reset %s changes'], Designer.KIND_LABELS[Designer:PreviewKind()] or '')
		end,
		desc = L['Remove the changes made only for these plates. The rest of the style stays.'],
		hidden = function()
			local kind = Designer:PreviewKind()
			for _, scoped in ipairs(Designer:ScopedKinds(id)) do
				if scoped == kind then
					return false
				end
			end
			return true
		end,
		func = function()
			Designer:ResetPart(id, Designer:PreviewKind())
		end,
	}
end

local function Position(id, order, locked)
	local option = {
		type = 'select',
		order = order,
		name = L['Position'],
		desc = L['Pick where it sits on the part it hangs from. The arrows nudge it. You can also drag it in the preview.'],
		values = POINT_LABELS,
		get = function()
			return Designer.GridCell(Spec(id).anchor)
		end,
		set = function(_, cell)
			Designer:SetGridCell(id, cell)
		end,
		disabled = locked,
	}
	if Widgets and Widgets.Has and Widgets:Has('AnchorGrid') then
		option.dialogControl = Widgets:TypeName('AnchorGrid')
		option.arg = {
			step = 0.5,
			bigStep = 2,
			onNudge = function(dx, dy)
				Designer:NudgePart(id, dx, dy)
			end,
			offset = function()
				local anchor = Spec(id).anchor
				return anchor and anchor[4] or 0, anchor and anchor[5] or 0
			end,
			onReset = function()
				Designer:ResetOffset(id)
			end,
		}
	end
	return option
end

local function HangsFrom(id, order)
	return {
		type = 'select',
		order = order,
		advanced = true,
		name = L['Hangs from'],
		desc = L['The part it moves with. It stays where it is now.'],
		values = function()
			local values = { plate = L['The plate'] }
			local parts = Designer:Parts()
			for _, partId in ipairs(Designer:TargetChoices(id)) do
				local _, label = Designer.PartInfo(partId, parts[partId])
				values[partId] = label
			end
			return values
		end,
		get = function()
			local anchor = Spec(id).anchor
			return anchor and anchor[2] or 'plate'
		end,
		set = function(_, targetId)
			Designer:SetTarget(id, targetId)
		end,
	}
end

-- extra.fallback: what an unset field shows (a value, or a function of the part id)
local function Fallback(id, extra, default)
	local fallback = extra and extra.fallback
	if type(fallback) == 'function' then
		return fallback(id)
	elseif fallback ~= nil then
		return fallback
	end
	return default
end

local function WithExtra(option, extra)
	for k, v in pairs(extra or {}) do
		if k ~= 'fallback' then
			option[k] = v
		end
	end
	return option
end

local function Range(id, field, order, name, desc, min, max, step, extra)
	local read, set = Field(id, field)
	local function Get()
		local value = read()
		if type(value) ~= 'number' then
			value = Fallback(id, extra, min)
		end
		return value
	end
	return WithExtra({ type = 'range', order = order, name = name, desc = desc, min = min, max = max, step = step or 1, get = Get, set = set }, extra)
end

local function Toggle(id, field, order, name, desc, extra)
	local get, set = Field(id, field, function(value)
		return value and true or false
	end, function(value)
		return value and true or false
	end)
	return WithExtra({ type = 'toggle', order = order, name = name, desc = desc, get = get, set = set }, extra)
end

local function Select(id, field, order, name, desc, values, sorting, extra)
	local read, set = Field(id, field)
	local function Get()
		local value = read()
		if value == nil then
			value = Fallback(id, extra, nil)
		end
		return value
	end
	return WithExtra({ type = 'select', order = order, name = name, desc = desc, values = values, sorting = sorting, get = Get, set = set }, extra)
end

local function Color(id, field, order, name, desc, extra)
	return WithExtra({ type = 'color', order = order, name = name, desc = desc, hasAlpha = true, get = ColorGet(id, field), set = ColorSet(id, field) }, extra)
end

local function ColorFrom(id, order)
	return {
		type = 'select',
		order = order,
		name = L['Color comes from'],
		desc = L['Which color list paints it. Change the lists on the Colors page.'],
		values = PIECES,
		sorting = PIECE_ORDER,
		get = function()
			return Spec(id).colors
		end,
		set = function(_, piece)
			Designer:Change(id, 'colors', piece)
		end,
	}
end

local function ColorLink(order)
	return {
		type = 'execute',
		order = order,
		name = L['Change these colors'],
		desc = L['Opens the Colors page.'],
		hidden = function()
			return not (P.host and P.host.OpenOptions)
		end,
		func = function()
			HostOpen('colors')
		end,
	}
end

local function Common(id, spec, args)
	args.label = {
		type = 'input',
		order = 200,
		advanced = true,
		name = L['Name in the list'],
		desc = L['A name of your own for this part. Leave it empty for the usual name.'],
		get = function()
			return Spec(id).label or ''
		end,
		set = function(_, text)
			text = type(text) == 'string' and string.gsub(text, '^%s*(.-)%s*$', '%1') or ''
			Designer:Change(id, 'label', text ~= '' and string.sub(text, 1, 48) or nil)
		end,
	}
	args.layer = Range(id, 'layer', 201, L['Layer'], L['Parts on a higher layer draw on top of lower ones.'], -8, 8, 1, { advanced = true, fallback = 0 })
	args.alpha = Range(id, 'alpha', 202, L['See-through'], L['How solid the part is. 100% is fully solid.'], 0, 1, 0.05, { advanced = true, isPercent = true, fallback = 1 })
	args.pixelSnap = Toggle(id, 'pixelSnap', 203, L['Keep edges sharp'], L['Lines up the part with screen pixels, so thin lines stay crisp.'], { advanced = true })
	args.above =
		Toggle(id, 'above', 204, spec.kind == 'cast' and L['Lift casts above other plates'] or L['Draw above other plates'], L['Draws this part over plates that overlap it.'], { advanced = true })
	if Designer.Movable(spec) then
		args.hangsFrom = HangsFrom(id, 205)
	end
end

local function Reset(id, order)
	return {
		type = 'execute',
		order = order,
		name = function()
			return Designer:IsAdded(id) and L['Remove this part'] or L['Reset this part']
		end,
		desc = function()
			return Designer:IsAdded(id) and L['Takes away the part you added. Undo brings it back.'] or L['Puts this part back the way the style made it.']
		end,
		hidden = function()
			return not (Designer:IsAdded(id) or Designer:HasChanges(id))
		end,
		func = function()
			if Designer:IsAdded(id) then
				Designer:RemovePart(id)
			else
				Designer:ResetPart(id)
			end
		end,
	}
end

local KindArgs = {}

function KindArgs.bar(id, spec, args)
	if spec.fill == 'plate' then
		if spec.source == 'health' then
			args.absorbMode = Select(id, 'absorbMode', 3, L['Shields'], L['Where shields show on the bar.'], ABSORB_MODES, { 'overlay', 'extend' }, { fallback = 'overlay' })
			args.lostHealth = Toggle(id, 'lostHealth', 4, L['Show health just lost'], L['A chunk of the bar fades out after each hit.'])
			args.execute = Range(id, 'execute', 5, L['Mark low health below'], L['Draws a mark on the bar at this much health. 0% turns it off.'], 0, 0.9, 0.05, { isPercent = true })
		end
	else
		args.position = Position(id, 3)
		args.width = Range(id, 'width', 4, L['Width'], nil, 1, 512, 1)
		args.height = Range(id, 'height', 5, L['Height'], nil, 1, 128, 1)
	end
	args.colors = ColorFrom(id, 6)
	args.colorLink = ColorLink(7)
	args.borderKind = Select(id, 'border.kind', 100, L['Border'], nil, BORDERS, BORDER_ORDER, { advanced = true })
	args.borderSize = Range(id, 'border.size', 101, L['Border size'], nil, 0, 8, 1, { advanced = true, fallback = 1 })
	args.bg = Color(id, 'bg', 102, L['Background'], L['The color behind the bar.'], { advanced = true })
	args.interpolate = Toggle(id, 'interpolate', 103, L['Smooth changes'], L['The bar slides to its new value instead of jumping.'], { advanced = true })
	args.reverse = Toggle(id, 'reverse', 104, L['Fill from the right'], nil, { advanced = true })
end

function KindArgs.cast(id, _, args)
	args.showOn = {
		type = 'multiselect',
		order = 3,
		name = L['Show cast bars on'],
		values = { enemies = L['Enemies'], friends = L['Friends'] },
		get = function(_, key)
			return Value(id, key) and true or false
		end,
		set = function(_, key, on)
			Designer:Change(id, key, on and true or false)
		end,
	}
	args.interruptColor = {
		type = 'toggle',
		order = 4,
		name = L['Color it when my interrupt is ready'],
		desc = L['The cast bar turns green while your interrupt can be used.'],
		get = function()
			return not P.Store:Get({ 'colors', 'cast', 'off', 'interruptReady' })
		end,
		set = function(_, on)
			P.Store:Set({ 'colors', 'cast', 'off', 'interruptReady' }, (not on) or nil)
		end,
	}
	args.important = Toggle(id, 'important', 5, L['Glow on important casts'], L['Casts the game marks as important get a glow.'])
	args.target = Toggle(id, 'target', 7, L['Show who the spell is aimed at'], L['Adds the name of the target, in its class color.'])
	args.shield = Toggle(id, 'shield', 8, L['Shield on casts I cannot interrupt'], nil)
	-- Eight main controls at most: these two fold into More settings (dragging still moves it)
	args.aimedAtMe = Toggle(id, 'aimedAtMe', 98, L['Mark casts aimed at me'], nil, { advanced = true })
	args.position = Position(id, 99)
	args.position.advanced = true
	args.height = Range(id, 'height', 100, L['Height'], nil, 1, 64, 1, { advanced = true })
	args.sameWidth = {
		type = 'toggle',
		order = 101,
		advanced = true,
		name = L['Same width as the bar'],
		get = function()
			return Spec(id).width == nil
		end,
		set = function(_, on)
			if on then
				Designer:Change(id, 'width', nil)
			else
				local resolved = P.Styles.Merge:Resolve(Designer:StyleId(), Designer:PreviewKind(), P.Store:Get('size'))
				Designer:Change(id, 'width', resolved and resolved.width or 132)
			end
		end,
	}
	args.width = Range(id, 'width', 102, L['Width'], nil, 1, 512, 1, {
		advanced = true,
		hidden = function()
			return Spec(id).width == nil
		end,
	})
	args.iconSide = Select(id, 'icon', 103, L['Spell icon'], nil, ICON_SIDES, { 'left', 'right', 'none' }, { advanced = true })
	args.timeText = Toggle(id, 'timeText', 104, L['Show the time'], nil, { advanced = true })
	args.timeFormat = Select(id, 'timeFormat', 105, L['Time shows'], nil, TIME_FORMATS, { 'remaining', 'elapsed', 'both' }, { advanced = true })
	args.kickMark = {
		type = 'select',
		order = 106,
		advanced = true,
		name = L['Mark when my interrupt comes back'],
		desc = L['Shows on the cast bar where your interrupt will be ready again.'],
		values = KICK_MARKS,
		sorting = KICK_ORDER,
		get = function()
			if Value(id, 'kickMark') == false then
				return 'off'
			end
			return Value(id, 'kickFill') and 'fill' or 'line'
		end,
		set = function(_, choice)
			Designer:Edit('edit', function()
				Designer:SetField(id, 'kickMark', choice ~= 'off')
				Designer:SetField(id, 'kickFill', choice == 'fill')
			end)
		end,
	}
	args.interrupter = Toggle(id, 'interrupter', 107, L['Show who interrupted it'], nil, { advanced = true })
	args.fontSize = Range(id, 'font.size', 108, L['Text size'], nil, 6, 40, 1, { advanced = true })
	args.colors = ColorFrom(id, 109)
	args.colors.advanced = true
	args.colorLink = ColorLink(110)
	args.colorLink.advanced = true
end

local function TextSources()
	local values = {}
	for _, source in ipairs(P.Styles.Schema.TEXT_SOURCES) do
		values[source] = Designer.TEXT_LABELS[source] or source
	end
	return values
end

local function SourceLimit(kind, source)
	local limit
	if kind == 'text' and P.TextParts and P.TextParts.Limit then
		limit = P.TextParts.Limit(source)
	elseif kind == 'icon' and P.IconParts and P.IconParts.Limit then
		limit = P.IconParts.Limit(source)
	end
	return (type(limit) == 'string' and limit ~= '') and limit or nil
end

function KindArgs.text(id, spec, args)
	args.source = Select(id, 'source', 3, L['Shows'], function()
		return SourceLimit('text', Spec(id).source) or L['What the text shows.']
	end, TextSources())
	args.fontSize = Range(id, 'font.size', 4, L['Text size'], nil, 6, 40, 1)
	args.outline = Select(id, 'font.flags', 99, L['Outline'], nil, OUTLINES, OUTLINE_ORDER, { advanced = true, fallback = 'OUTLINE' })
	args.position = Position(id, 6)
	args.colors = ColorFrom(id, 7)
	args.colorLink = ColorLink(8)
	args.face = Select(id, 'font.face', 100, L['Font'], L['The style font follows your look.'], FontChoices, nil, { advanced = true, fallback = '$font' })
	args.justify = Select(id, 'justify', 101, L['Line up'], nil, JUSTIFY, { 'LEFT', 'CENTER', 'RIGHT' }, { advanced = true, fallback = 'CENTER' })
	args.width = Range(id, 'width', 102, L['Width'], L['0 makes it as wide as the plate.'], 0, 512, 1, { advanced = true })
	args.color = Color(id, 'color', 103, L['Color'], L['Used when no color list paints it.'], { advanced = true })
	args.shadow = Toggle(id, 'font.shadow', 104, L['Shadow'], nil, { advanced = true })
	if spec.source == 'healthPercent' or spec.source == 'healthValue' then
		args.hideAtFull = Toggle(id, 'hideAtFull', 105, L['Hide at full health'], nil, { advanced = true })
	end
	if spec.source == 'healthValue' then
		args.abbreviate = Toggle(id, 'abbreviate', 106, L['Short numbers'], L['Shows 12.3k instead of 12345.'], { advanced = true })
	end
end

function KindArgs.icon(id, _, args)
	local values = {}
	for _, source in ipairs(P.Styles.Schema.ICON_SOURCES) do
		values[source] = Designer.ICON_LABELS[source] or source
	end
	args.source = Select(id, 'source', 3, L['Shows'], function()
		return SourceLimit('icon', Spec(id).source) or L['What the icon shows.']
	end, values)
	args.size = Range(id, 'size', 4, L['Size'], nil, 4, 64, 1)
	args.position = Position(id, 5)
	args.color = Color(id, 'color', 100, L['Tint'], L['Colors the icon.'], { advanced = true })
end

local function AuraTextPosition(id, field, name, order)
	local option = {
		type = 'select',
		name = name,
		order = order,
		desc = L['Pick where the text sits on each icon. The arrows move it a little.'],
		values = POINT_LABELS,
		sorting = P.Styles.Schema.POINTS,
		disabled = LockedAuras,
		get = function()
			local anchor = Designer:AuraText(id, field)
			return anchor and anchor.relPoint or 'CENTER'
		end,
		set = function(_, cell)
			Designer:SetAuraTextCell(id, field, cell)
		end,
	}
	if Widgets and Widgets:Has('AnchorGrid') then
		option.dialogControl = Widgets:TypeName('AnchorGrid')
		option.arg = {
			step = 0.5,
			bigStep = 2,
			onNudge = function(dx, dy)
				Designer:NudgeAuraText(id, field, dx, dy)
			end,
			offset = function()
				local anchor = Designer:AuraText(id, field)
				return anchor and anchor.x or 0, anchor and anchor.y or 0
			end,
			onReset = function()
				Designer:SetAuraText(id, field, { x = 0, y = 0 })
			end,
		}
	end
	return option
end

local function AuraTextSize(id, field, name, order)
	local range = P.Styles.Schema:FieldSpec('auras', field).fields.size
	return {
		type = 'range',
		name = name,
		order = order,
		min = range.min,
		max = range.max,
		step = 1,
		disabled = LockedAuras,
		get = function()
			local anchor = Designer:AuraText(id, field)
			return anchor and anchor.size or 9
		end,
		set = function(_, size)
			Designer:SetAuraText(id, field, { size = size }, 'auraTextSize:' .. id .. ':' .. field)
		end,
	}
end

function Customize.AuraTextGroup(id)
	return {
		type = 'group',
		inline = true,
		advanced = true,
		name = L['Aura text'],
		order = 107,
		disabled = LockedAuras,
		args = {
			note = { type = 'description', order = 1, name = L['Move time left and stacks on the larger icon in the preview.'] },
			timerPosition = AuraTextPosition(id, 'timerAnchor', L['Time left position'], 2),
			timerSize = AuraTextSize(id, 'timerAnchor', L['Time left size'], 3),
			stackPosition = AuraTextPosition(id, 'stackAnchor', L['Stack position'], 4),
			stackSize = AuraTextSize(id, 'stackAnchor', L['Stack size'], 5),
			reset = {
				type = 'execute',
				name = L['Reset aura text'],
				order = 6,
				disabled = LockedAuras,
				desc = L['Put the time left and stacks back where this style puts them.'],
				func = function()
					Designer:ResetAuraText(id)
				end,
			},
		},
	}
end

function KindArgs.auras(id, _, args)
	local locked = { disabled = LockedAuras }
	args.lockNote = {
		type = 'description',
		order = 2.5,
		width = 'full',
		fontSize = 'small',
		name = Options.LOCKED_REASON,
		hidden = function()
			return not Options.Locked()
		end,
	}
	args.max = Range(id, 'max', 3, L['How many'], nil, 0, 40, 1, locked)
	args.size = Range(id, 'size', 4, L['Icon size'], nil, 8, 64, 1, locked)
	args.side = {
		type = 'select',
		order = 5,
		name = L['Side'],
		desc = L['Where the row sits next to the part it hangs from.'],
		values = SIDES,
		sorting = SIDE_ORDER,
		disabled = LockedAuras,
		get = function()
			return Designer.SideOf(Spec(id).anchor)
		end,
		set = function(_, side)
			local anchor, grow = Designer.SideAnchor(Spec(id).anchor, side, Spec(id).grow)
			Designer:Edit('move', function()
				Designer:SetField(id, 'anchor', anchor)
				Designer:SetField(id, 'grow', grow)
			end)
		end,
	}
	args.position = Position(id, 6, LockedAuras)
	args.perRow = Range(id, 'perRow', 100, L['Icons per line'], nil, 1, 40, 1, {
		advanced = true,
		disabled = LockedAuras,
		fallback = function()
			return Value(id, 'max') or 6
		end,
	})
	args.spacing = Range(id, 'spacing', 101, L['Space between icons'], nil, 0, 16, 1, { advanced = true, disabled = LockedAuras })
	args.sort = Select(id, 'sort', 102, L['Order'], nil, SORTS, { 'default', 'time', 'name' }, { advanced = true, disabled = LockedAuras })
	args.timer = Toggle(id, 'timer', 103, L['Show time left'], nil, { advanced = true, disabled = LockedAuras })
	args.stacks = Toggle(id, 'stacks', 104, L['Show stacks'], nil, { advanced = true, disabled = LockedAuras })
	args.borderStyle = Select(id, 'borderStyle', 105, L['Icon border'], nil, AURA_BORDERS, { 'none', 'pixel', 'dispel' }, { advanced = true, disabled = LockedAuras })
	args.pandemic = Toggle(id, 'pandemic', 106, L['Glow when it is time to refresh'], function()
		local limit = P.AuraRows and P.AuraRows.Limit and P.AuraRows.Limit('pandemic', Spec(id).row)
		return (type(limit) == 'string' and limit ~= '') and limit or L['Your effects glow in their last 30% so you know to cast them again.']
	end, { advanced = true, disabled = LockedAuras })
	args.auraText = Customize.AuraTextGroup(id)
end

function KindArgs.highlight(id, spec, args)
	args.art = Select(id, 'art', 3, L['Picture'], nil, HIGHLIGHT_ARTS, HIGHLIGHT_ORDER)
	args.color = Color(id, 'color', 4, L['Color'], nil)
	args.animate = Select(id, 'animate', 99, L['Motion'], nil, ANIMATE, { 'none', 'pulse', 'bounce' }, { advanced = true, fallback = 'none' })
	if spec.state == 'target' then
		args.bigger = {
			type = 'toggle',
			order = 6,
			name = L['Make my target bigger'],
			desc = L['Your target grows a little, in whole pixels, so borders stay sharp.'],
			get = function()
				local grow = StateValue('target', 'grow')
				return type(grow) == 'table' and ((grow[1] or 0) > 0 or (grow[2] or 0) > 0)
			end,
			set = function(_, on)
				local base = BaseState('target', 'grow')
				local baseOn = type(base) == 'table' and ((base[1] or 0) > 0 or (base[2] or 0) > 0)
				if on then
					SetState('target', 'grow', baseOn and base or { 14, 2 })
				else
					SetState('target', 'grow', { 0, 0 })
				end
			end,
		}
		args.fade = {
			type = 'toggle',
			order = 7,
			name = L['Fade plates that are not my target'],
			get = function()
				local alpha = StateValue('notTarget', 'alpha')
				return type(alpha) == 'number' and alpha < 1
			end,
			set = function(_, on)
				local base = BaseState('notTarget', 'alpha')
				if on then
					SetState('notTarget', 'alpha', (type(base) == 'number' and base < 1) and base or 0.75)
				else
					SetState('notTarget', 'alpha', 1)
				end
			end,
		}
		args.castFull = {
			type = 'toggle',
			order = 8,
			name = L['Bring plates back to full when they cast'],
			disabled = function()
				local alpha = StateValue('notTarget', 'alpha')
				return not (type(alpha) == 'number' and alpha < 1)
			end,
			get = function()
				return StateValue('casting', 'alpha') == 1
			end,
			set = function(_, on)
				SetState('casting', 'alpha', on and 1 or nil)
			end,
		}
		args.growWidth = {
			type = 'range',
			order = 100,
			advanced = true,
			name = L['Grow wider by'],
			min = 0,
			max = 64,
			step = 1,
			get = function()
				local grow = StateValue('target', 'grow')
				return type(grow) == 'table' and grow[1] or 0
			end,
			set = function(_, value)
				local grow = StateValue('target', 'grow')
				SetState('target', 'grow', { value, type(grow) == 'table' and grow[2] or 0 })
			end,
		}
		args.growHeight = {
			type = 'range',
			order = 101,
			advanced = true,
			name = L['Grow taller by'],
			min = 0,
			max = 64,
			step = 1,
			get = function()
				local grow = StateValue('target', 'grow')
				return type(grow) == 'table' and grow[2] or 0
			end,
			set = function(_, value)
				local grow = StateValue('target', 'grow')
				SetState('target', 'grow', { type(grow) == 'table' and grow[1] or 0, value })
			end,
		}
		args.fadeTo = {
			type = 'range',
			order = 102,
			advanced = true,
			name = L['Fade other plates to'],
			isPercent = true,
			min = 0.1,
			max = 1,
			step = 0.05,
			get = function()
				local alpha = StateValue('notTarget', 'alpha')
				return type(alpha) == 'number' and alpha or 1
			end,
			set = function(_, value)
				SetState('notTarget', 'alpha', value)
			end,
		}
	end
	args.size = Range(id, 'size', 110, L['Size'], nil, 0, 64, 1, { advanced = true })
	args.pad = Range(id, 'pad', 111, L['Space around the plate'], nil, 0, 32, 1, { advanced = true, fallback = 2 })
	args.blend = Select(id, 'blend', 112, L['Blend'], nil, BLEND, { 'BLEND', 'ADD' }, { advanced = true, fallback = 'BLEND' })
end

function KindArgs.glow(id, spec, args)
	-- The threat glow only takes the threat colors: a color picker here would do nothing
	if spec.source == 'threat' then
		args.color = ColorLink(3)
		args.color.desc = L['The threat glow uses the threat colors from the Colors page.']
	else
		args.color = Color(id, 'color', 3, L['Color'], nil)
	end
	args.size = Range(id, 'size', 4, L['Size'], nil, 0, 32, 1)
	args.animate = Select(id, 'animate', 5, L['Motion'], nil, { none = L['None'], pulse = L['Pulse'] }, { 'none', 'pulse' }, { fallback = 'none' })
	args.blend = Select(id, 'blend', 100, L['Blend'], nil, BLEND, { 'BLEND', 'ADD' }, { advanced = true, fallback = 'BLEND' })
end

function KindArgs.classPower(id, _, args)
	args.size = Range(id, 'size', 3, L['Size'], nil, 2, 32, 1)
	args.spacing = Range(id, 'spacing', 4, L['Space between'], nil, 0, 16, 1)
	args.position = Position(id, 5)
	args.color = Color(id, 'color', 100, L['Color'], L['One color for every point. Reset the part to use each power color.'], { advanced = true })
end

function KindArgs.region(id, _, args)
	args.region = Select(id, 'region', 3, L['Area'], L['Click area: where a click picks the unit. Stacking area: how much room plates keep apart.'], REGIONS, { 'click', 'stack' })
	args.width = Range(id, 'width', 4, L['Width'], nil, 1, 1024, 1)
	args.height = Range(id, 'height', 5, L['Height'], nil, 1, 512, 1)
	args.position = Position(id, 6)
end

function KindArgs.art(id, _, args)
	args.width = Range(id, 'width', 3, L['Width'], nil, 1, 512, 1)
	args.height = Range(id, 'height', 4, L['Height'], nil, 1, 256, 1)
	args.color = Color(id, 'color', 5, L['Color'], nil)
	args.position = Position(id, 6)
end

---The settings group for one part (shown only while it is the selected part).
---@param id string
---@param spec table
---@return table group
function Customize.PartGroup(id, spec)
	local args = {
		scope = Scope(1),
		scopedNote = ScopedNote(id, 1.1),
		resetScoped = ResetScoped(id, 1.2),
	}
	local build = KindArgs[spec.kind]
	if build then
		build(id, spec, args)
	end
	Common(id, spec, args)
	args.reset = Reset(id, 50)
	return {
		type = 'group',
		inline = true,
		order = 10,
		name = function()
			local _, label = Designer.PartInfo(id, Spec(id))
			return label
		end,
		hidden = function()
			return Designer:Primary() ~= id
		end,
		args = args,
	}
end

----------------------------------------------------------------------------------------------------
-- The page
----------------------------------------------------------------------------------------------------

---Make a copy of the Blank style and use it (Phase 7 starting point).
function Customize.StartBlank()
	local Registry = P.Styles.Registry
	if not Registry:Get('blank') then
		return
	end
	local style = P.Styles.Merge:Bake('blank')
	if not style then
		return
	end
	local id = Registry:Save(style, L['My style'], { kind = 'copy' })
	P.Store:Set('style', id)
	Designer.history:Clear()
	Designer:ClearSelection()
end

Options:AddPage('customize', 2, function()
	local args = {
		intro = {
			type = 'description',
			order = 1,
			fontSize = 'medium',
			width = 'full',
			name = function()
				if Designer:Primary() then
					return L['Change the part below, or drag it in the preview. Pick another part in the list or the preview.']
				end
				return L['Pick a part to change it: click it in the preview, or in this list.']
			end,
		},
		parts = {
			type = 'select',
			order = 2,
			width = 'full',
			name = L['Parts'],
			desc = L['Click a part to change it. The switch shows or hides it.'],
			values = function()
				local values = {}
				for id, spec in pairs(Designer:Parts()) do
					local _, label = Designer.PartInfo(id, spec)
					values[id] = label
				end
				return values
			end,
			get = function()
				return Designer:Primary()
			end,
			set = function(_, value)
				Customize.ApplyListValue(value)
			end,
		},
		addPart = {
			type = 'select',
			order = 90,
			advanced = true,
			name = L['Add a part'],
			desc = L['Adds a new part to this style. It is picked right away so you can move it.'],
			values = function()
				local values = {}
				for _, item in ipairs(Designer.PALETTE) do
					values[item.value] = item.text
				end
				return values
			end,
			sorting = (function()
				local order = {}
				for _, item in ipairs(Designer.PALETTE) do
					order[#order + 1] = item.value
				end
				return order
			end)(),
			get = function()
				return nil
			end,
			set = function(_, kind)
				Designer:AddPart(kind)
			end,
		},
		undo = {
			type = 'execute',
			order = 91,
			advanced = true,
			name = L['Undo'],
			desc = L['Takes back your last change on this page or in the preview. Ctrl-Z does the same.'],
			disabled = function()
				return not Designer:CanUndo()
			end,
			func = function()
				Designer:Undo()
			end,
		},
		redo = {
			type = 'execute',
			order = 92,
			advanced = true,
			name = L['Redo'],
			desc = L['Brings back what you undid. Ctrl-Y does the same.'],
			disabled = function()
				return not Designer:CanRedo()
			end,
			func = function()
				Designer:Redo()
			end,
		},
		blank = {
			type = 'execute',
			order = 93,
			advanced = true,
			name = L['Start from a blank style'],
			desc = L['Makes a new style with only a health bar, for building your own. Your current style is kept in the gallery.'],
			confirm = true,
			confirmText = L['Make a new blank style and use it?'],
			hidden = function()
				return P.Styles.Registry:Get('blank') == nil
			end,
			disabled = Options.Locked,
			func = Customize.StartBlank,
		},
	}
	if Widgets and Widgets.Has and Widgets:Has('PartList') then
		args.parts.dialogControl = Widgets:TypeName('PartList')
		args.parts.arg = { rows = Customize.Rows }
	end
	local ids = Sorted(Designer:Parts())
	for _, id in ipairs(ids) do
		args['part_' .. id] = Customize.PartGroup(id, Designer:Parts()[id])
	end
	return {
		type = 'group',
		name = L['Customize'],
		args = args,
	}
end)
