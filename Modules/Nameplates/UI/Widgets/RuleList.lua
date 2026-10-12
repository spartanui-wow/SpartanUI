local _, ns = ...
local P = ns.Plates
local L = P.L

-- RuleList: the ordered color list editor (3.2 Colors > More settings), also the base for the
-- "When" list on Who and where.
--
-- Each row: up and down handles, a mini bar with the color (a striped bar for rows with several
-- colors), the plain sentence, a client badge when limited, a "When" dropdown, an on/off switch
-- and, for rows the player added, a remove button. "Add a color" opens a list of row kinds; the new
-- row goes where arg.insertIndex says (P.Colors:SuggestInsertIndex) and flashes once.
--
-- AceConfig: type = 'select', dialogControl = P.Widgets:TypeName('RuleList'), values = {} (or row
--   ids), arg = {
--     header = 'When more than one color fits, the top one wins.', -- string or function
--     rows = fun(): Plates.RuleRow[],            -- read again after every change (the stored truth)
--     whenChoices? = string[] | { id, label }[] | fun(), -- default Conditions.WHEN_ORDER/LABELS
--     addChoices? = fun(): { id, label, color?, when?, badge?, disabled? }[],
--     addLabel? = 'Add a color',
--     insertIndex? = fun(id, order): integer,    -- where a new row goes
--     onChange? = fun(change: Plates.RuleChange), -- every change; the page writes the list whole
--     onReorder? = fun(id, from, to, order), onToggle? = fun(id, on), onWhen? = fun(id, whenId),
--     onColor? = fun(id, color, key), onAdd? = fun(id, index), onRemove? = fun(id),
--     onEdit? = fun(id, what: 'row'|'color', key): boolean, -- true when the page handled it
--     onHover? = fun(id|nil),                    -- the preview shows one sample plate per row
--     pickColor? = false,                        -- turn off the built-in color picker
--     empty? = string, lockedReason? = string | fun(): string,
--   }
-- Without any arg handler for a change the widget fires 'OnValueChanged' with the whole row list
-- (AceConfig then calls the option's set). AceGUI callbacks for direct users: 'OnRuleChanged'
-- (change), 'OnReorder'(id, from, to), 'OnToggle'(id, on), 'OnEdit'(id, what, key),
-- 'OnRowEnter'(id), 'OnRowLeave'(id). SetValue takes a row list; GetValue returns a copy.
-- Reordering sets the scheme to Custom: that is the page's job in onChange (change.action).

---@class Plates.RuleRow
---@field id string|number Unique row key (a color kind id, or a "When" entry key)
---@field sentence string Plain sentence ("Gray when someone else tagged it first")
---@field color? number[] { r, g, b, a } for the mini bar
---@field colors? { key: string, label?: string, color: number[] }[] Several colors (mob type)
---@field when? string "When" clause id; nil hides the dropdown
---@field whenText? string Fixed text in place of the dropdown
---@field on? boolean nil reads as on
---@field badge? string Client badge ("Retail: only in the open world")
---@field locked? boolean Cannot move or be turned off
---@field removable? boolean Shows a remove button
---@field tooltip? string Extra line for the row tooltip

---@class Plates.RuleChange
---@field action 'reorder'|'toggle'|'when'|'color'|'add'|'remove'
---@field id string|number
---@field order (string|number)[] Row ids in their new order
---@field rows Plates.RuleRow[] Copy of every row after the change
---@field from? integer Old position (reorder, remove)
---@field index? integer New position (reorder, add)
---@field on? boolean toggle
---@field when? string when
---@field color? number[] color
---@field key? string color: which color of a row with several

local Widgets = P.Widgets or { types = {} }
P.Widgets = Widgets
local Draw = Widgets.Draw

local ROW_H, ROW_H_BADGE, ROW_GAP = 26, 38, 2
local LABEL_H = 18
local HANDLE_W, HANDLE_H = 14, 11
local SWATCH_W, SWATCH_H = 34, 12
local WHEN_W, WHEN_W_NARROW = 116, 84
local SWITCH_W = 26
local REMOVE_W = 14
local ADD_H = 22
local FLASH_TIME = 0.9

local CHANGE_HANDLERS = {
	reorder = 'onReorder',
	toggle = 'onToggle',
	when = 'onWhen',
	color = 'onColor',
	add = 'onAdd',
	remove = 'onRemove',
}

local function Resolve(value)
	if type(value) == 'function' then
		return value()
	end
	return value
end

local function NormalizeRows(list)
	local out = {}
	if type(list) ~= 'table' then
		return out
	end
	for _, row in ipairs(list) do
		if type(row) == 'table' and row.id ~= nil then
			local copy = P.util.Copy(row)
			if copy.on == nil then
				copy.on = true
			end
			out[#out + 1] = copy
		end
	end
	return out
end

local function OrderOf(rows)
	local order = {}
	for i, row in ipairs(rows) do
		order[i] = row.id
	end
	return order
end

local function IndexOf(rows, id)
	for i, row in ipairs(rows) do
		if row.id == id then
			return i
		end
	end
	return nil
end

local function SameColor(a, b)
	return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and (a[4] or 1) == (b[4] or 1)
end

---"When" choices as { id, label } in display order.
local function WhenChoices(arg)
	local conditions = P.Conditions
	local labels = conditions and conditions.WHEN_LABELS or {}
	local raw = arg and Resolve(arg.whenChoices)
	local out = {}
	if type(raw) == 'table' and #raw > 0 then
		for _, entry in ipairs(raw) do
			if type(entry) == 'table' and entry.id ~= nil then
				out[#out + 1] = { id = entry.id, label = entry.label or labels[entry.id] or tostring(entry.id) }
			elseif type(entry) == 'string' then
				out[#out + 1] = { id = entry, label = labels[entry] or entry }
			end
		end
	elseif type(raw) == 'table' then
		local order = conditions and conditions.WHEN_ORDER or {}
		local used = {}
		for _, id in ipairs(order) do
			if raw[id] then
				out[#out + 1] = { id = id, label = raw[id] }
				used[id] = true
			end
		end
		for id, label in pairs(raw) do
			if not used[id] then
				out[#out + 1] = { id = id, label = label }
			end
		end
	else
		for _, id in ipairs(conditions and conditions.WHEN_ORDER or {}) do
			out[#out + 1] = { id = id, label = labels[id] or id }
		end
	end
	return out
end

local function WhenLabel(self, row)
	if row.whenText then
		return row.whenText
	end
	for _, choice in ipairs(WhenChoices(self.arg)) do
		if choice.id == row.when then
			return choice.label
		end
	end
	return tostring(row.when)
end

----------------------------------------------------------------------------------------------------
-- Color picker. Hooks the game's picker on first use only; a change is reported once, when the
-- picker closes without Cancel. Works with the picker every client ships
-- (ColorPickerFrame:SetupColorPickerAndShow).
----------------------------------------------------------------------------------------------------

local pickerSession
local pickerHooked = false

local function PickerClosed()
	local session = pickerSession
	if not session then
		return
	end
	pickerSession = nil
	if not session.cancelled and not SameColor(session.first, session.last) and session.onDone then
		session.onDone(session.last)
	end
end

---@param color number[]
---@param onLive fun(color: number[]) Called while the player drags (preview only)
---@param onDone fun(color: number[]) Called once with the final color
---@return boolean opened
local function OpenColorPicker(color, onLive, onDone, owner)
	local frame = ColorPickerFrame
	if not (frame and frame.SetupColorPickerAndShow and frame.GetColorRGB and frame.HookScript) then
		return false
	end
	if frame:IsShown() then
		frame:Hide()
	end
	if not pickerHooked then
		pickerHooked = true
		frame:HookScript('OnHide', PickerClosed)
	end
	local r, g, b, a = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
	local session = { first = { r, g, b, a }, last = { r, g, b, a }, onDone = onDone }
	pickerSession = session
	local info = {
		r = r,
		g = g,
		b = b,
		hasOpacity = false,
		swatchFunc = function()
			if pickerSession ~= session then
				return
			end
			local nr, ng, nb = frame:GetColorRGB()
			if type(nr) == 'number' and type(ng) == 'number' and type(nb) == 'number' then
				session.last = { nr, ng, nb, a }
				onLive(session.last)
			end
		end,
		cancelFunc = function()
			if pickerSession ~= session then
				return
			end
			session.cancelled = true
			onLive(session.first)
		end,
	}
	local ok = pcall(frame.SetupColorPickerAndShow, frame, info)
	if not ok then
		pickerSession = nil
		return false
	end
	if frame.SetFrameStrata then
		frame:SetFrameStrata('FULLSCREEN_DIALOG')
	end
	if owner and frame.SetFrameLevel then
		frame:SetFrameLevel(math.min(65535, (owner:GetFrameLevel() or 0) + 10))
	end
	if frame.SetClampedToScreen then
		frame:SetClampedToScreen(true)
	end
	return true
end

----------------------------------------------------------------------------------------------------
-- Changes
----------------------------------------------------------------------------------------------------

local Refresh

---Report a change the widget already applied to self.rows, then read the stored truth again.
local function Emit(self, change)
	change.order = OrderOf(self.rows)
	change.rows = P.util.Copy(self.rows)
	local arg = self.arg or {}
	local token = self.token
	local handled = false
	if type(arg.onChange) == 'function' then
		arg.onChange(change)
		handled = true
	end
	local specific = arg[CHANGE_HANDLERS[change.action]]
	if type(specific) == 'function' then
		handled = true
		local action = change.action
		if action == 'reorder' then
			specific(change.id, change.from, change.index, change.order)
		elseif action == 'toggle' then
			specific(change.id, change.on)
		elseif action == 'when' then
			specific(change.id, change.when)
		elseif action == 'color' then
			specific(change.id, change.color, change.key)
		elseif action == 'add' then
			specific(change.id, change.index)
		else
			specific(change.id)
		end
	end
	if self.token ~= token then
		return
	end
	self:Fire('OnRuleChanged', change)
	if change.action == 'reorder' then
		self:Fire('OnReorder', change.id, change.from, change.index)
	elseif change.action == 'toggle' then
		self:Fire('OnToggle', change.id, change.on)
	end
	if self.token ~= token then
		return
	end
	if not handled then
		self:Fire('OnValueChanged', P.util.Copy(self.rows))
	end
	if self.token == token then
		Refresh(self)
	end
end

local function Move(self, index, delta)
	local rows = self.rows
	local target = index + delta
	local row = rows[index]
	if self.disabled or not row or row.locked or target < 1 or target > #rows then
		return
	end
	rows[index], rows[target] = rows[target], rows[index]
	Draw.Sound(856)
	Emit(self, { action = 'reorder', id = row.id, from = index, index = target })
end

local function Toggle(self, index)
	local row = self.rows[index]
	if self.disabled or not row or row.locked then
		return
	end
	row.on = not row.on
	Draw.Sound(row.on and 856 or 857)
	Emit(self, { action = 'toggle', id = row.id, on = row.on })
end

local function SetWhen(self, id, whenId)
	local index = IndexOf(self.rows, id)
	local row = index and self.rows[index]
	if self.disabled or not row or row.when == whenId then
		return
	end
	row.when = whenId
	Emit(self, { action = 'when', id = id, when = whenId })
end

local function SetColor(self, id, key, color)
	local index = IndexOf(self.rows, id)
	local row = index and self.rows[index]
	if self.disabled or not row then
		return
	end
	local copy = { color[1], color[2], color[3], color[4] or 1 }
	if key ~= nil and type(row.colors) == 'table' then
		for _, entry in ipairs(row.colors) do
			if entry.key == key then
				entry.color = copy
			end
		end
	else
		row.color = copy
	end
	Emit(self, { action = 'color', id = id, key = key, color = copy })
end

local function Remove(self, index)
	local row = self.rows[index]
	if self.disabled or not row or not row.removable then
		return
	end
	table.remove(self.rows, index)
	Draw.Sound(857)
	Emit(self, { action = 'remove', id = row.id, from = index })
end

local function Add(self, choice)
	if self.disabled or type(choice) ~= 'table' or choice.id == nil or IndexOf(self.rows, choice.id) then
		return
	end
	local arg = self.arg or {}
	local order = OrderOf(self.rows)
	local index = #self.rows + 1
	if type(arg.insertIndex) == 'function' then
		index = tonumber(arg.insertIndex(choice.id, order)) or index
	end
	index = math.max(1, math.min(#self.rows + 1, math.floor(index)))
	table.insert(self.rows, index, {
		id = choice.id,
		sentence = choice.sentence or choice.label or tostring(choice.id),
		color = choice.color and P.util.Copy(choice.color) or nil,
		colors = choice.colors and P.util.Copy(choice.colors) or nil,
		when = choice.when,
		badge = choice.badge,
		on = true,
		removable = choice.removable ~= false,
	})
	self.flashId = choice.id
	Draw.Sound(856)
	Emit(self, { action = 'add', id = choice.id, index = index })
end

local function Edit(self, row, what, key)
	if self.disabled or not row then
		return
	end
	local arg = self.arg or {}
	local token = self.token
	local handled = false
	if type(arg.onEdit) == 'function' then
		handled = arg.onEdit(row.id, what, key) == true
	end
	if self.token ~= token then
		return
	end
	self:Fire('OnEdit', row.id, what, key)
	if handled or what ~= 'color' or arg.pickColor == false or self.token ~= token then
		return
	end
	local current = row.color
	if key ~= nil and type(row.colors) == 'table' then
		for _, entry in ipairs(row.colors) do
			if entry.key == key then
				current = entry.color
			end
		end
	end
	if type(current) ~= 'table' then
		return
	end
	local id = row.id
	OpenColorPicker(current, function(color)
		-- Live preview on the mini bar only; nothing is stored until the picker closes
		if self.token == token then
			local frameRow = self.rowById and self.rowById[id]
			if frameRow then
				for _, segment in ipairs(frameRow.segments) do
					if segment:IsShown() and segment.key == key then
						segment.fill:SetVertexColor(color[1], color[2], color[3], 1)
					end
				end
			end
		end
	end, function(color)
		if self.token == token then
			SetColor(self, id, key, color)
		end
	end, self.frame)
end

----------------------------------------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------------------------------------

local function RowEnter(row)
	local self = row.obj
	row.hovered = true
	row.bg:SetVertexColor(Draw.Color('hover'))
	if self.hoverId ~= row.data.id then
		self.hoverId = row.data.id
		local arg = self.arg
		if arg and type(arg.onHover) == 'function' then
			arg.onHover(row.data.id)
		end
		self:Fire('OnRowEnter', row.data.id)
	end
end

local function RowLeave(row)
	local self = row.obj
	if row:IsMouseOver() then
		return
	end
	row.hovered = false
	row.bg:SetVertexColor(0, 0, 0, 0)
	if self.hoverId == row.data.id then
		self.hoverId = nil
		local arg = self.arg
		if arg and type(arg.onHover) == 'function' then
			arg.onHover(nil)
		end
		self:Fire('OnRowLeave', row.data.id)
	end
end

local function Row_OnEnter(row)
	RowEnter(row)
	local data = row.data
	local body = data.badge
	if data.tooltip then
		body = body and (body .. '\n' .. data.tooltip) or data.tooltip
	end
	Draw.ShowTooltip(row, data.sentence, body)
end

local function Row_OnLeave(row)
	Draw.HideTooltip()
	RowLeave(row)
end

local function Child_OnEnter(child)
	RowEnter(child.row)
end

local function Child_OnLeave(child)
	RowLeave(child.row)
end

local function FlashUpdate(row, elapsed)
	row.flashTime = (row.flashTime or 0) + elapsed
	local t = row.flashTime / FLASH_TIME
	if t >= 1 then
		row.flash:SetAlpha(0)
		row:SetScript('OnUpdate', nil)
		return
	end
	row.flash:SetAlpha(0.35 * (1 - t))
end

local function StartFlash(row)
	local r, g, b = Draw.Accent()
	row.flash:SetVertexColor(r, g, b, 1)
	row.flash:SetAlpha(0.35)
	row.flashTime = 0
	row:SetScript('OnUpdate', FlashUpdate)
end

local function StopFlash(row)
	row:SetScript('OnUpdate', nil)
	row.flash:SetAlpha(0)
end

local function Segment(row, index)
	local segment = row.segments[index]
	if segment then
		return segment
	end
	segment = CreateFrame('Button', nil, row.swatch)
	segment.fill = Draw.Rect(segment, 'ARTWORK')
	segment.fill:SetAllPoints()
	segment.row = row
	segment:SetScript('OnEnter', function(self)
		RowEnter(self.row)
		Draw.ShowTooltip(self, self.label or self.row.data.sentence, L['Click to change the color.'])
	end)
	segment:SetScript('OnLeave', function(self)
		Draw.HideTooltip()
		RowLeave(self.row)
	end)
	segment:SetScript('OnClick', function(self)
		Edit(self.row.obj, self.row.data, 'color', self.key)
	end)
	row.segments[index] = segment
	return segment
end

local function CreateRow(self)
	local row = CreateFrame('Button', nil, self.frame)
	row.obj = self
	row:SetHeight(ROW_H)
	row.bg = Draw.Rect(row, 'BACKGROUND')
	row.bg:SetAllPoints()
	row.bg:SetVertexColor(0, 0, 0, 0)
	row.flash = Draw.Rect(row, 'BACKGROUND', 1)
	row.flash:SetAllPoints()
	row.flash:SetAlpha(0)
	row.mark = Draw.Rect(row, 'ARTWORK')
	row.mark:SetWidth(2)
	row.mark:SetPoint('TOPLEFT')
	row.mark:SetPoint('BOTTOMLEFT')

	row.up = Draw.Button(row, nil, HANDLE_W, HANDLE_H)
	row.up:SetPoint('BOTTOMLEFT', row, 'LEFT', 3, 1)
	row.up.glyph = Draw.Arrow(row.up, 'UP', 3)
	row.up.glyph.anchor:SetPoint('CENTER')
	Draw.SetTooltip(row.up, L['Move up'], L['Rows higher in the list win.'])
	row.down = Draw.Button(row, nil, HANDLE_W, HANDLE_H)
	row.down:SetPoint('TOPLEFT', row, 'LEFT', 3, -1)
	row.down.glyph = Draw.Arrow(row.down, 'DOWN', 3)
	row.down.glyph.anchor:SetPoint('CENTER')
	Draw.SetTooltip(row.down, L['Move down'], L['Rows higher in the list win.'])

	row.swatch = CreateFrame('Frame', nil, row)
	row.swatch:SetSize(SWATCH_W, SWATCH_H)
	row.swatch:SetPoint('LEFT', HANDLE_W + 10, 0)
	row.swatch.border = Draw.Border(row.swatch, 'OVERLAY')
	row.segments = {}

	row.sentence = Draw.Text(row, 12, 'text')
	row.badge = Draw.Text(row, 10, 'warn')

	row.whenButton = Draw.Button(row, '', WHEN_W, 20)
	row.whenButton.label:ClearAllPoints()
	row.whenButton.label:SetPoint('LEFT', 6, 0)
	row.whenButton.label:SetPoint('RIGHT', -16, 0)
	row.whenButton.label:SetJustifyH('LEFT')
	row.whenButton.glyph = Draw.Arrow(row.whenButton, 'DOWN', 3)
	row.whenButton.glyph.anchor:SetPoint('RIGHT', -6, 0)
	Draw.SetTooltip(row.whenButton, L['When'], L['Where this applies.'])
	row.whenText = Draw.Text(row, 11, 'muted')
	row.whenText:SetJustifyH('RIGHT')

	row.switch = Draw.Switch(row)
	Draw.SetTooltip(row.switch, L['On or off'], nil)

	row.remove = Draw.Button(row, nil, REMOVE_W, REMOVE_W)
	row.remove.icon = row.remove:CreateTexture(nil, 'ARTWORK')
	row.remove.icon:SetPoint('TOPLEFT', 2, -2)
	row.remove.icon:SetPoint('BOTTOMRIGHT', -2, 2)
	Draw.Icon(row.remove.icon, 'remove')
	Draw.SetTooltip(row.remove, L['Remove'], nil)

	for _, child in ipairs({ row.up, row.down, row.whenButton, row.switch, row.remove }) do
		child.row = row
		child.onEnter = Child_OnEnter
		child.onLeave = Child_OnLeave
	end
	row.up.onClick = function()
		Move(self, row.index, -1)
	end
	row.down.onClick = function()
		Move(self, row.index, 1)
	end
	row.switch.onClick = function()
		Toggle(self, row.index)
	end
	row.remove.onClick = function()
		Remove(self, row.index)
	end
	row.whenButton.onClick = function(button)
		if Draw.MenuJustClosedBy(button) then
			return
		end
		local data = row.data
		local items = {}
		for _, choice in ipairs(WhenChoices(self.arg)) do
			items[#items + 1] = { value = choice.id, text = choice.label, checked = choice.id == data.when }
		end
		-- A pick after the widget was released and reused for another option must do nothing
		local token = self.token
		Draw.OpenMenu(button, items, function(value)
			if self.token == token then
				SetWhen(self, data.id, value)
			end
		end, { width = math.max(button:GetWidth() or 0, 140) })
	end

	row:SetScript('OnEnter', Row_OnEnter)
	row:SetScript('OnLeave', Row_OnLeave)
	row:SetScript('OnClick', function()
		Edit(self, row.data, 'row')
	end)
	row:SetScript('OnHide', StopFlash)
	row:SetScript('OnShow', function()
		Draw.LayoutBorder(row.swatch.border)
	end)
	return row
end

local function PaintSwatch(row, data)
	local list
	if type(data.colors) == 'table' and #data.colors > 0 then
		list = data.colors
	elseif type(data.color) == 'table' then
		list = { { color = data.color } }
	end
	if not list then
		row.swatch:Hide()
		return false
	end
	row.swatch:Show()
	local width = SWATCH_W / #list
	for i, entry in ipairs(list) do
		local segment = Segment(row, i)
		segment:ClearAllPoints()
		segment:SetPoint('TOPLEFT', (i - 1) * width, 0)
		segment:SetSize(width, SWATCH_H)
		local c = type(entry.color) == 'table' and entry.color or { 0.5, 0.5, 0.5 }
		segment.fill:SetVertexColor(tonumber(c[1]) or 0.5, tonumber(c[2]) or 0.5, tonumber(c[3]) or 0.5, 1)
		segment.key = entry.key
		segment.label = entry.label
		segment:Show()
	end
	for i = #list + 1, #row.segments do
		row.segments[i]:Hide()
	end
	Draw.BorderColor(row.swatch.border, 0, 0, 0, 0.8)
	return true
end

local function LayoutRow(self, row, width)
	local data = row.data
	local disabled = self.disabled
	local tall = data.badge ~= nil and data.badge ~= ''
	row:SetHeight(tall and ROW_H_BADGE or ROW_H)

	local count = #self.rows
	Draw.SetEnabled(row.up, not disabled and not data.locked and row.index > 1)
	Draw.SetEnabled(row.down, not disabled and not data.locked and row.index < count)

	local right = -4
	if data.removable and not data.locked then
		row.remove:Show()
		row.remove:ClearAllPoints()
		row.remove:SetPoint('RIGHT', right, 0)
		Draw.SetEnabled(row.remove, not disabled)
		right = right - REMOVE_W - 6
	else
		row.remove:Hide()
	end

	row.switch:ClearAllPoints()
	row.switch:SetPoint('RIGHT', right, 0)
	Draw.SetSwitch(row.switch, data.on ~= false)
	Draw.SetEnabled(row.switch, not disabled and not data.locked)
	right = right - SWITCH_W - 8

	local whenWidth = width < 380 and WHEN_W_NARROW or WHEN_W
	if data.whenText then
		row.whenButton:Hide()
		row.whenText:Show()
		row.whenText:ClearAllPoints()
		row.whenText:SetPoint('RIGHT', right, 0)
		row.whenText:SetWidth(whenWidth)
		row.whenText:SetText(data.whenText)
		right = right - whenWidth - 8
	elseif data.when ~= nil then
		row.whenText:Hide()
		row.whenButton:Show()
		row.whenButton:SetWidth(whenWidth)
		row.whenButton:ClearAllPoints()
		row.whenButton:SetPoint('RIGHT', right, 0)
		row.whenButton.label:SetText(WhenLabel(self, data))
		Draw.SetEnabled(row.whenButton, not disabled)
		right = right - whenWidth - 8
	else
		row.whenText:Hide()
		row.whenButton:Hide()
	end

	local hasSwatch = PaintSwatch(row, data)
	local lift = tall and 6 or 0
	row.sentence:ClearAllPoints()
	if hasSwatch then
		row.sentence:SetPoint('LEFT', row.swatch, 'RIGHT', 8, lift)
	else
		row.sentence:SetPoint('LEFT', row, 'LEFT', HANDLE_W + 10, lift)
	end
	row.sentence:SetPoint('RIGHT', row, 'RIGHT', right, lift)
	row.sentence:SetText(data.sentence or tostring(data.id))
	Draw.Paint(row.sentence, (disabled or data.on == false) and 'faint' or 'text')

	row.badge:SetShown(tall)
	if tall then
		row.badge:ClearAllPoints()
		row.badge:SetPoint('TOPLEFT', row.sentence, 'BOTTOMLEFT', 0, -3)
		row.badge:SetPoint('RIGHT', row, 'RIGHT', right, 0)
		row.badge:SetText(data.badge)
		Draw.Paint(row.badge, disabled and 'faint' or 'warn')
	end

	local ar, ag, ab = Draw.Accent()
	row.mark:SetShown(self.selected ~= nil and self.selected == data.id)
	row.mark:SetVertexColor(ar, ag, ab, 1)
	if hasSwatch then
		row.swatch:SetAlpha((disabled or data.on == false) and 0.45 or 1)
	end
end

local function TextHeight(fs, width)
	if width and width > 0 then
		fs:SetWidth(width)
	end
	local height = fs:GetStringHeight()
	return (type(height) == 'number' and height > 0) and height or 12
end

---Place everything for the current width. Returns the widget's height.
local function Place(self)
	local width = self.frame.width or self.frame:GetWidth() or 0
	if type(width) ~= 'number' then
		width = 0
	end
	local y = 0

	if self.label:IsShown() then
		y = y + LABEL_H
	end

	local header = Resolve(self.arg and self.arg.header)
	if type(header) == 'string' and header ~= '' then
		self.header:Show()
		self.header:SetText(header)
		self.header:ClearAllPoints()
		self.header:SetPoint('TOPLEFT', 0, -y)
		y = y + TextHeight(self.header, width) + 6
	else
		self.header:Hide()
	end

	local reason = self.disabled and Resolve(self.arg and self.arg.lockedReason)
	if type(reason) == 'string' and reason ~= '' then
		self.locked:Show()
		self.locked:SetText(reason)
		self.locked:ClearAllPoints()
		self.locked:SetPoint('TOPLEFT', 0, -y)
		y = y + TextHeight(self.locked, width) + 6
	else
		self.locked:Hide()
	end

	self.rowById = {}
	for i, data in ipairs(self.rows) do
		local row = self.rowFrames[i]
		if not row then
			row = CreateRow(self)
			self.rowFrames[i] = row
		end
		row.index = i
		row.data = data
		self.rowById[data.id] = row
		row:ClearAllPoints()
		row:SetPoint('TOPLEFT', self.frame, 'TOPLEFT', 0, -y)
		row:SetPoint('RIGHT', self.frame, 'RIGHT', 0, 0)
		LayoutRow(self, row, width)
		row:Show()
		y = y + (row:GetHeight() or ROW_H) + ROW_GAP
	end
	for i = #self.rows + 1, #self.rowFrames do
		local row = self.rowFrames[i]
		row:Hide()
		row.data = nil
	end

	if #self.rows == 0 then
		local empty = Resolve(self.arg and self.arg.empty)
		self.empty:SetText(type(empty) == 'string' and empty or L['Nothing here yet.'])
		self.empty:Show()
		self.empty:ClearAllPoints()
		self.empty:SetPoint('TOPLEFT', 4, -y - 4)
		y = y + 24
	else
		self.empty:Hide()
	end

	local arg = self.arg
	if arg and type(arg.addChoices) == 'function' then
		local addLabel = Resolve(arg.addLabel)
		self.add.label:SetText(type(addLabel) == 'string' and addLabel or L['Add a color'])
		self.add:SetWidth(math.max(110, (self.add.label:GetStringWidth() or 0) + 24))
		self.add:ClearAllPoints()
		self.add:SetPoint('TOPLEFT', 0, -y - 4)
		Draw.SetEnabled(self.add, not self.disabled)
		self.add:Show()
		y = y + ADD_H + 6
	else
		self.add:Hide()
	end

	return y
end

local function Layout(self)
	if not Draw.RunLayout(self, Place) then
		return
	end
	local flashId = self.flashId
	if flashId ~= nil then
		self.flashId = nil
		local row = self.rowById[flashId]
		if row then
			StartFlash(row)
		end
	end
end

---Read the rows again (from arg.rows when given) and redraw.
Refresh = function(self)
	local arg = self.arg
	if arg and arg.rows ~= nil then
		self.rows = NormalizeRows(Resolve(arg.rows))
	end
	Layout(self)
end

local function OpenAddMenu(self)
	local arg = self.arg
	if self.disabled or not (arg and type(arg.addChoices) == 'function') then
		return
	end
	if Draw.MenuJustClosedBy(self.add) then
		return
	end
	local choices = arg.addChoices() or {}
	local byId = {}
	local items = {}
	for _, choice in ipairs(choices) do
		if type(choice) == 'table' and choice.id ~= nil then
			byId[choice.id] = choice
			local present = IndexOf(self.rows, choice.id) ~= nil
			items[#items + 1] = {
				value = choice.id,
				text = choice.label or tostring(choice.id),
				note = present and L['In the list'] or choice.badge,
				disabled = present or choice.disabled == true,
				tooltip = choice.tooltip,
			}
		end
	end
	if #items == 0 then
		items[1] = { text = L['Nothing more to add.'], disabled = true }
	end
	local token = self.token
	Draw.OpenMenu(self.add, items, function(value)
		if self.token == token then
			Add(self, byId[value])
		end
	end, { width = 220, maxRows = 20 })
end

---Close the popup list when any button of this widget owns it (the add button or a row's When).
local function CloseMenus(self)
	Draw.CloseMenu(self.add)
	for _, row in ipairs(self.rowFrames or {}) do
		Draw.CloseMenu(row.whenButton)
	end
end

----------------------------------------------------------------------------------------------------
-- Widget
----------------------------------------------------------------------------------------------------

local methods = {
	OnAcquire = function(self)
		self.token = (self.token or 0) + 1
		-- AceGUI keeps the last container in .parent after a release; never lay that one out
		self.parent = nil
		self.laying = false
		self.layoutDepth = 0
		self.arg = nil
		self.rows = {}
		self.selected = nil
		self.hoverId = nil
		self.flashId = nil
		self.disabled = false
		self:SetWidth(400)
		self:SetLabel('')
		Refresh(self)
	end,

	OnRelease = function(self)
		self.token = (self.token or 0) + 1
		CloseMenus(self)
		for _, row in ipairs(self.rowFrames) do
			StopFlash(row)
			row:Hide()
			row.data = nil
		end
		if self.hoverId ~= nil and self.arg and type(self.arg.onHover) == 'function' then
			self.arg.onHover(nil)
		end
		self.hoverId = nil
		self.arg = nil
		self.rows = {}
		self.parent = nil
	end,

	---AceConfig hands the option's arg here (rows, handlers, header, choices).
	SetCustomData = function(self, arg)
		self.arg = type(arg) == 'table' and arg or nil
		Refresh(self)
	end,

	SetLabel = function(self, text)
		text = text or ''
		self.label:SetText(text)
		self.label:SetShown(text ~= '')
		Layout(self)
	end,

	---values from AceConfig: id -> sentence. Used as plain rows only when nothing else gives rows.
	SetList = function(self, values, sorting)
		if type(values) ~= 'table' or (self.arg and self.arg.rows ~= nil) then
			return
		end
		local order = {}
		if type(sorting) == 'table' then
			for _, id in ipairs(sorting) do
				order[#order + 1] = id
			end
		else
			for id in pairs(values) do
				order[#order + 1] = id
			end
			table.sort(order, function(a, b)
				return tostring(a) < tostring(b)
			end)
		end
		local rows = {}
		for _, id in ipairs(order) do
			if values[id] ~= nil then
				rows[#rows + 1] = { id = id, sentence = tostring(values[id]), on = true }
			end
		end
		if #rows > 0 then
			self.rows = rows
			Layout(self)
		end
	end,

	---A row list, or (from AceConfig) the id of the row to mark.
	SetValue = function(self, value)
		if type(value) == 'table' then
			self.rows = NormalizeRows(value)
		else
			self.selected = value
		end
		Layout(self)
	end,

	---@return Plates.RuleRow[]
	GetValue = function(self)
		return P.util.Copy(self.rows)
	end,

	SetDisabled = function(self, disabled)
		self.disabled = disabled and true or false
		if self.disabled then
			CloseMenus(self)
		end
		Draw.Paint(self.label, self.disabled and 'faint' or 'text')
		Layout(self)
	end,

	---Turn a row on or off as the switch would.
	ToggleRow = function(self, id)
		local index = IndexOf(self.rows, id)
		if index then
			Toggle(self, index)
		end
	end,

	---Move a row up (delta -1) or down (delta 1) as the handles would.
	MoveRow = function(self, id, delta)
		local index = IndexOf(self.rows, id)
		if index then
			Move(self, index, delta)
		end
	end,

	---Add a row of a kind offered by arg.addChoices, as the Add menu would.
	AddRow = function(self, id)
		local arg = self.arg
		if not (arg and type(arg.addChoices) == 'function') then
			return
		end
		for _, choice in ipairs(arg.addChoices() or {}) do
			if type(choice) == 'table' and choice.id == id and not choice.disabled then
				Add(self, choice)
				return
			end
		end
	end,

	RemoveRow = function(self, id)
		local index = IndexOf(self.rows, id)
		if index then
			Remove(self, index)
		end
	end,

	SetRowWhen = function(self, id, whenId)
		SetWhen(self, id, whenId)
	end,

	SetRowColor = function(self, id, color, key)
		if type(color) == 'table' then
			SetColor(self, id, key, color)
		end
	end,

	EditRow = function(self, id, what, key)
		local index = IndexOf(self.rows, id)
		if index then
			Edit(self, self.rows[index], what or 'row', key)
		end
	end,

	OpenAddMenu = function(self)
		OpenAddMenu(self)
	end,

	OnWidthSet = function(self)
		Draw.LayoutPass(self, Layout)
	end,

	ClearFocus = function(self)
		CloseMenus(self)
	end,

	-- AceConfig may call these on select controls; a rule list has no use for them.
	SetMultiselect = function() end,
	SetItemValue = function() end,
	SetPulloutWidth = function() end,
}

local function Constructor()
	local AceGUI = LibStub('AceGUI-3.0')
	local frame = CreateFrame('Frame', nil, UIParent)
	frame:Hide()

	---@type table
	local widget = { frame = frame, type = Widgets:TypeName('RuleList'), rows = {}, rowFrames = {}, rowById = {} }

	widget.label = Draw.Text(frame, 12, 'text')
	widget.label:SetPoint('TOPLEFT', 0, -2)
	widget.label:SetPoint('TOPRIGHT', 0, -2)

	widget.header = Draw.Text(frame, 11, 'muted')
	widget.header:SetWordWrap(true)
	widget.locked = Draw.Text(frame, 11, 'warn')
	widget.locked:SetWordWrap(true)
	widget.empty = Draw.Text(frame, 11, 'faint')

	widget.add = Draw.Button(frame, L['Add a color'], 110, ADD_H)
	widget.add.onClick = function()
		OpenAddMenu(widget)
	end

	for name, fn in pairs(methods) do
		widget[name] = fn
	end

	Draw.OnAccent(frame, function()
		if widget.rows and frame:IsShown() then
			Layout(widget)
		end
	end)

	return AceGUI:RegisterAsWidget(widget)
end

Widgets.types.RuleList = { version = 1, Constructor = Constructor }
