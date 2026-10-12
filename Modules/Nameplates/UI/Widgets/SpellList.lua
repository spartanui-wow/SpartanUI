local _, ns = ...
local P = ns.Plates
local L = P.L

-- SpellList: "Always show" / "Never show" spell lists for an aura row, filled by searching spell
-- names with icons (3.2 Auras). Each entry shows icon, name, id and an "Only mine" / "Anyone"
-- choice, plus a remove button.
--
-- Search (spike S15): C_Spell.GetSpellInfo finds a name only for spells the client knows, so the
-- widget also searches a pool it can read names for: the page's own search, a curated list
-- (arg.curated, by default the crowd control and tank debuff data), spells the engine has seen
-- this session (P.Widgets:NoteSpell, fed only with readable spell ids) and the list itself. A
-- number typed in is always accepted as a spell id, even when the game has no name for it yet; its
-- name is asked for (C_Spell.RequestLoadSpellData) and filled in when it arrives.
--
-- AceConfig: type = 'select', dialogControl = P.Widgets:TypeName('SpellList'), values = {}, arg = {
--     list = fun(): { [spellID] = 'mine'|'any' },  -- read again after every change
--     onChange = fun(list, change),                 -- written whole: P.Store:Set({ 'auras', row, 'always' }, list)
--     search? = fun(text): { spellID, name?, icon? }[],
--     curated? = integer[] | { [spellID] = any } | fun(),
--     defaultWho? = 'mine'|'any',                   -- for new entries (default 'mine')
--     hint? = string | false,                       -- the line under the search box
--     tooltipIDs? = { get = fun(): boolean, set = fun(on: boolean) }, -- "Show spell IDs in tooltips"
--     unavailable? = string | fun(): string|nil,    -- show this reason instead of the list
--     lockedReason? = string | fun(): string,       -- shown while disabled
--     empty? = string,
--   }
-- Without onChange the widget fires 'OnValueChanged' with the whole list. It always fires
-- 'OnListChanged'(list, change). SetValue takes the map or a list of { spellID, who }; GetValue
-- returns a copy of the map.

---@class Plates.SpellListChange
---@field action 'add'|'who'|'remove'
---@field spellID integer
---@field who? 'mine'|'any'
---@field list table<integer, 'mine'|'any'>

local Widgets = P.Widgets or { types = {} }
P.Widgets = Widgets
local Draw = Widgets.Draw

local LABEL_H = 18
local SEARCH_H = 22
local ENTRY_H, ENTRY_GAP = 24, 2
local MAX_RESULTS = 8
local SEEN_MAX = 300
local MINE_W, ANY_W = 72, 60
local REMOVE_W = 14
local MAX_SPELL_ID = 2147483647

----------------------------------------------------------------------------------------------------
-- Spells seen this session (the "recently seen" feed)
----------------------------------------------------------------------------------------------------

local seen = { ids = {}, count = 0, serial = 0 }

---Remember a spell the engine read plainly (an aura or cast on a plate). Never pass a value that
---may be secret: it is checked, and anything unreadable is dropped.
---@param spellID integer
function Widgets:NoteSpell(spellID)
	if not P.Secret.CanAccess(spellID) or type(spellID) ~= 'number' or spellID <= 0 or spellID > MAX_SPELL_ID then
		return
	end
	if not seen.ids[spellID] then
		seen.count = seen.count + 1
	end
	seen.serial = seen.serial + 1
	seen.ids[spellID] = seen.serial
	if seen.count > SEEN_MAX + 50 then
		local list = self:SeenSpells()
		local keep = {}
		for i = 1, SEEN_MAX do
			keep[list[i]] = seen.ids[list[i]]
		end
		seen.ids = keep
		seen.count = SEEN_MAX
	end
end

---Spells noted this session, newest first.
---@return integer[]
function Widgets:SeenSpells()
	local list = {}
	for id in pairs(seen.ids) do
		list[#list + 1] = id
	end
	table.sort(list, function(a, b)
		return seen.ids[a] > seen.ids[b]
	end)
	return list
end

---Forget the seen spells (tests).
function Widgets:ForgetSeenSpells()
	seen.ids = {}
	seen.count = 0
	seen.serial = 0
end

----------------------------------------------------------------------------------------------------
-- Spell names and icons
----------------------------------------------------------------------------------------------------

local infoCache = {}
local pending = {}
local live = setmetatable({}, { __mode = 'k' })
local loader

local function Readable(value)
	return P.Secret.CanAccess(value) and value or nil
end

---Spell id, name and icon from an id or a name the client knows.
---@param spell integer|string
---@return integer|nil spellID, string|nil name, number|string|nil icon
local function SpellInfo(spell)
	local id, name, icon
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, spell)
		if ok and type(info) == 'table' then
			id, name, icon = Readable(info.spellID), Readable(info.name), Readable(info.iconID or info.originalIconID)
		end
	end
	if not name and GetSpellInfo then
		local ok, n, _, i, _, _, _, sid = pcall(GetSpellInfo, spell)
		if ok then
			id, name, icon = Readable(sid), Readable(n), Readable(i)
		end
	end
	if type(name) ~= 'string' or name == '' then
		return nil
	end
	if type(id) ~= 'number' then
		id = type(spell) == 'number' and spell or nil
	end
	return id, name, icon
end

local function RefreshLive()
	for widget in pairs(live) do
		if widget.frame:IsShown() then
			widget:Refresh()
		end
	end
end

local function Loader_OnEvent(frame, event, spellID, success)
	if event ~= 'SPELL_DATA_LOAD_RESULT' or type(spellID) ~= 'number' or not pending[spellID] then
		return
	end
	pending[spellID] = nil
	if next(pending) == nil then
		frame:UnregisterEvent('SPELL_DATA_LOAD_RESULT')
	end
	if success then
		RefreshLive()
	end
end

---Ask the client for a spell's name (spells it has not loaded yet answer later).
local function RequestLoad(spellID)
	if pending[spellID] or not (C_Spell and C_Spell.RequestLoadSpellData) then
		return
	end
	if C_Spell.DoesSpellExist then
		local ok, exists = pcall(C_Spell.DoesSpellExist, spellID)
		if ok and exists == false then
			return
		end
	end
	if not loader then
		loader = CreateFrame('Frame')
		loader:SetScript('OnEvent', Loader_OnEvent)
	end
	pending[spellID] = true
	loader:RegisterEvent('SPELL_DATA_LOAD_RESULT')
	pcall(C_Spell.RequestLoadSpellData, spellID)
end

---Name and icon for a spell id, cached once found.
---@param spellID integer
---@return string|nil name, number|string|nil icon
local function Lookup(spellID)
	local hit = infoCache[spellID]
	if hit then
		return hit.name, hit.icon
	end
	local _, name, icon = SpellInfo(spellID)
	if name then
		infoCache[spellID] = { name = name, icon = icon }
		return name, icon
	end
	RequestLoad(spellID)
	return nil
end

local function Trim(text)
	return (string.gsub(text or '', '^%s*(.-)%s*$', '%1'))
end

local function IdList(value)
	local out = {}
	value = type(value) == 'function' and value() or value
	if type(value) ~= 'table' then
		return out
	end
	if #value > 0 then
		for _, id in ipairs(value) do
			if type(id) == 'number' then
				out[#out + 1] = id
			end
		end
	else
		for id in pairs(value) do
			if type(id) == 'number' then
				out[#out + 1] = id
			end
		end
	end
	return out
end

local function CuratedIds(arg)
	if arg and arg.curated ~= nil then
		return IdList(arg.curated)
	end
	local out = {}
	local data = P.Data or {}
	for _, list in ipairs({ data.CrowdControl, data.TankDebuffs }) do
		for _, id in ipairs(IdList(list)) do
			out[#out + 1] = id
		end
	end
	return out
end

---Search results for the text: one id when it is a number, else name matches from every pool.
---@param self table
---@param text string
---@return { spellID: integer, name: string, icon?: number|string, known: boolean }[]
local function FindSpells(self, text)
	local results = {}
	local id = text:match('^%d+$') and tonumber(text)
	if id then
		if id > 0 and id <= MAX_SPELL_ID then
			local name, icon = Lookup(id)
			results[1] = { spellID = id, name = name or string.format(L['Spell %d'], id), icon = icon, known = name ~= nil }
		end
		return results
	end

	local needle = string.lower(text)
	local found = {}
	local function Add(spellID, name, icon, rank)
		if type(spellID) ~= 'number' or found[spellID] then
			return
		end
		found[spellID] = true
		results[#results + 1] = { spellID = spellID, name = name, icon = icon, known = true, rank = rank }
	end
	local function Consider(spellID)
		if type(spellID) ~= 'number' or found[spellID] then
			return
		end
		local name, icon = Lookup(spellID)
		if not name then
			return
		end
		local hay = string.lower(name)
		local rank
		if hay == needle then
			rank = 1
		elseif string.sub(hay, 1, #needle) == needle then
			rank = 2
		elseif string.find(hay, needle, 1, true) then
			rank = 3
		end
		if rank then
			Add(spellID, name, icon, rank)
		end
	end

	local arg = self.arg or {}
	if type(arg.search) == 'function' then
		for _, hit in ipairs(arg.search(text) or {}) do
			local spellID = type(hit) == 'table' and tonumber(hit.spellID or hit.id)
			if spellID then
				local name, icon = hit.name, hit.icon
				if type(name) ~= 'string' then
					name, icon = Lookup(spellID)
				end
				if name then
					Add(spellID, name, icon, 0)
				end
			end
		end
	end
	local knownID, knownName, knownIcon = SpellInfo(text)
	if knownID then
		infoCache[knownID] = infoCache[knownID] or { name = knownName, icon = knownIcon }
		Consider(knownID)
	end
	for _, spellID in ipairs(CuratedIds(arg)) do
		Consider(spellID)
	end
	for _, spellID in ipairs(Widgets:SeenSpells()) do
		Consider(spellID)
	end
	for spellID in pairs(self.map) do
		Consider(spellID)
	end

	table.sort(results, function(a, b)
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a.spellID < b.spellID
	end)
	for i = #results, MAX_RESULTS + 1, -1 do
		results[i] = nil
	end
	return results
end

local function NormalizeList(value, defaultWho)
	local map = {}
	if type(value) ~= 'table' then
		return map
	end
	for key, entry in pairs(value) do
		if type(entry) == 'table' then
			local id = tonumber(entry.spellID or entry.id or entry[1])
			local who = entry.who or entry[2]
			if id then
				map[id] = (who == 'any' or who == 'mine') and who or defaultWho
			end
		elseif type(key) == 'number' then
			map[key] = (entry == 'any' or entry == 'mine') and entry or defaultWho
		end
	end
	return map
end

local function CopyMap(map)
	local out = {}
	for id, who in pairs(map) do
		out[id] = who
	end
	return out
end

local function DefaultWho(self)
	local who = self.arg and self.arg.defaultWho
	return (who == 'any') and 'any' or 'mine'
end

----------------------------------------------------------------------------------------------------
-- Changes
----------------------------------------------------------------------------------------------------

local function Emit(self, change)
	local value = CopyMap(self.map)
	change.list = value
	local arg = self.arg or {}
	local token = self.token
	local handled = false
	if type(arg.onChange) == 'function' then
		arg.onChange(value, change)
		handled = true
	end
	if self.token ~= token then
		return
	end
	self:Fire('OnListChanged', CopyMap(self.map), change)
	if self.token ~= token then
		return
	end
	if not handled then
		self:Fire('OnValueChanged', CopyMap(self.map))
	end
	if self.token == token then
		self:Refresh()
	end
end

local function AddSpell(self, spellID)
	spellID = tonumber(spellID)
	if self.disabled or not spellID or spellID <= 0 or spellID > MAX_SPELL_ID or self.map[spellID] then
		return false
	end
	local who = DefaultWho(self)
	self.map[spellID] = who
	Draw.Sound(856)
	self.edit:SetText('')
	self.placeholder:Show()
	Draw.CloseMenu(self.box)
	Emit(self, { action = 'add', spellID = spellID, who = who })
	return true
end

local function SetWho(self, spellID, who)
	if self.disabled or not self.map[spellID] or self.map[spellID] == who then
		return
	end
	self.map[spellID] = who
	Emit(self, { action = 'who', spellID = spellID, who = who })
end

local function RemoveSpell(self, spellID)
	if self.disabled or not self.map[spellID] then
		return
	end
	self.map[spellID] = nil
	Draw.Sound(857)
	Emit(self, { action = 'remove', spellID = spellID })
end

----------------------------------------------------------------------------------------------------
-- Search box
----------------------------------------------------------------------------------------------------

local function PaintBox(self)
	local box = self.box
	local r, g, b = Draw.Accent()
	Draw.Paint(box.fill, 'input', self.disabled and 0.2 or nil)
	if self.disabled then
		Draw.BorderColor(box.border, Draw.Color('line'))
	elseif self.focused then
		Draw.BorderColor(box.border, r, g, b, 1)
	elseif box.hovered then
		Draw.BorderColor(box.border, 1, 1, 1, 0.28)
	else
		Draw.BorderColor(box.border, Draw.Color('lineStrong'))
	end
	self.searchIcon:SetAlpha(self.disabled and 0.35 or 0.8)
end

local function Search(self, text)
	text = Trim(text)
	if text == '' or self.disabled then
		Draw.CloseMenu(self.box)
		return
	end
	local results = FindSpells(self, text)
	local items = {}
	for _, hit in ipairs(results) do
		local present = self.map[hit.spellID] ~= nil
		items[#items + 1] = {
			value = hit.spellID,
			text = hit.name,
			note = present and L['In the list'] or string.format(L['ID %d'], hit.spellID),
			icon = hit.icon or 134400,
			spellID = hit.known and hit.spellID or nil,
			tooltip = (not hit.known) and L['The game does not know this spell yet. It is added by its ID.'] or nil,
			disabled = present,
		}
	end
	if #items == 0 then
		items[1] = { text = L['No spells found. Try the spell ID.'], disabled = true }
	end
	Draw.OpenMenu(self.box, items, function(value)
		AddSpell(self, value)
	end, { keepOwner = true, width = math.max(self.box:GetWidth() or 0, 220), maxRows = MAX_RESULTS })
end

local function Edit_OnTextChanged(edit, userInput)
	local self = edit.obj
	local text = edit:GetText() or ''
	self.placeholder:SetShown(text == '')
	self.clear:SetShown(text ~= '' and not self.disabled)
	if userInput then
		Search(self, text)
	end
end

local function Edit_OnEnterPressed(edit)
	local self = edit.obj
	if Draw.MenuOpenFor(self.box) then
		local items = Draw.MenuItems() or {}
		for index, item in ipairs(items) do
			if not item.disabled then
				Draw.PickMenuIndex(index)
				return
			end
		end
	end
	local text = Trim(edit:GetText())
	if text:match('^%d+$') then
		AddSpell(self, tonumber(text))
	end
end

local function Edit_OnEscapePressed(edit)
	local self = edit.obj
	if Draw.MenuOpenFor(self.box) then
		Draw.CloseMenu(self.box)
	else
		edit:ClearFocus()
	end
end

local function Edit_OnFocusGained(edit)
	local self = edit.obj
	self.focused = true
	local AceGUI = LibStub('AceGUI-3.0', true)
	if AceGUI then
		AceGUI:SetFocus(self)
	end
	PaintBox(self)
end

local function Edit_OnFocusLost(edit)
	local self = edit.obj
	self.focused = false
	PaintBox(self)
end

----------------------------------------------------------------------------------------------------
-- Entries
----------------------------------------------------------------------------------------------------

local function Entry_OnEnter(entry)
	entry.bg:SetVertexColor(Draw.Color('hover'))
	local data = entry.data
	if data then
		Draw.ShowTooltip(entry, data.name, string.format(L['ID %d'], data.spellID), data.known and data.spellID or nil)
	end
end

local function Entry_OnLeave(entry)
	if entry:IsMouseOver() then
		return
	end
	entry.bg:SetVertexColor(0, 0, 0, 0)
	Draw.HideTooltip()
end

local function Child_OnEnter(child)
	child.entry.bg:SetVertexColor(Draw.Color('hover'))
end

local function Child_OnLeave(child)
	Entry_OnLeave(child.entry)
end

local function CreateEntry(self)
	local entry = CreateFrame('Button', nil, self.frame)
	entry.obj = self
	entry:SetHeight(ENTRY_H)
	entry.bg = Draw.Rect(entry, 'BACKGROUND')
	entry.bg:SetAllPoints()
	entry.bg:SetVertexColor(0, 0, 0, 0)
	entry.icon = entry:CreateTexture(nil, 'ARTWORK')
	entry.icon:SetSize(18, 18)
	entry.icon:SetPoint('LEFT', 4, 0)
	entry.name = Draw.Text(entry, 12, 'text')
	entry.idText = Draw.Text(entry, 10, 'faint')
	entry.idText:SetJustifyH('RIGHT')

	entry.remove = Draw.Button(entry, nil, REMOVE_W, REMOVE_W)
	entry.remove:SetPoint('RIGHT', -4, 0)
	entry.remove.icon = entry.remove:CreateTexture(nil, 'ARTWORK')
	entry.remove.icon:SetPoint('TOPLEFT', 2, -2)
	entry.remove.icon:SetPoint('BOTTOMRIGHT', -2, 2)
	Draw.Icon(entry.remove.icon, 'remove')
	Draw.SetTooltip(entry.remove, L['Remove'], nil)

	entry.any = Draw.Button(entry, L['Anyone'], ANY_W, 18)
	entry.any:SetPoint('RIGHT', entry.remove, 'LEFT', -8, 0)
	Draw.SetTooltip(entry.any, L['Anyone'], L['Count this spell no matter who cast it.'])
	entry.mine = Draw.Button(entry, L['Only mine'], MINE_W, 18)
	entry.mine:SetPoint('RIGHT', entry.any, 'LEFT', 1, 0)
	Draw.SetTooltip(entry.mine, L['Only mine'], L['Count this spell only when you cast it.'])

	for _, child in ipairs({ entry.remove, entry.any, entry.mine }) do
		child.entry = entry
		child.onEnter = Child_OnEnter
		child.onLeave = Child_OnLeave
	end
	entry.remove.onClick = function()
		RemoveSpell(self, entry.data.spellID)
	end
	entry.mine.onClick = function()
		SetWho(self, entry.data.spellID, 'mine')
	end
	entry.any.onClick = function()
		SetWho(self, entry.data.spellID, 'any')
	end
	entry:SetScript('OnEnter', Entry_OnEnter)
	entry:SetScript('OnLeave', Entry_OnLeave)
	return entry
end

local function SortedEntries(self)
	local list = {}
	for spellID, who in pairs(self.map) do
		local name, icon = Lookup(spellID)
		list[#list + 1] = { spellID = spellID, who = who, name = name or string.format(L['Spell %d'], spellID), icon = icon, known = name ~= nil }
	end
	table.sort(list, function(a, b)
		if a.known ~= b.known then
			return a.known
		end
		local an, bn = string.lower(a.name), string.lower(b.name)
		if an ~= bn then
			return an < bn
		end
		return a.spellID < b.spellID
	end)
	return list
end

local function TextHeight(fs, width)
	if width and width > 0 then
		fs:SetWidth(width)
	end
	local height = fs:GetStringHeight()
	return (type(height) == 'number' and height > 0) and height or 12
end

local function Resolve(value)
	if type(value) == 'function' then
		return value()
	end
	return value
end

---Place everything for the current width. Returns the widget's height.
local function Place(self)
	local width = self.frame.width or self.frame:GetWidth() or 0
	if type(width) ~= 'number' then
		width = 0
	end
	local arg = self.arg or {}
	local y = 0

	if self.label:IsShown() then
		y = y + LABEL_H
	end

	local unavailable = Resolve(arg.unavailable)
	if type(unavailable) == 'string' and unavailable ~= '' then
		self.box:Hide()
		self.hint:Hide()
		self.tooltipRow:Hide()
		self.empty:Hide()
		self.locked:Show()
		self.locked:SetText(unavailable)
		self.locked:ClearAllPoints()
		self.locked:SetPoint('TOPLEFT', 0, -y)
		Draw.Paint(self.locked, 'muted')
		y = y + TextHeight(self.locked, width) + 6
		for _, entry in ipairs(self.entries) do
			entry:Hide()
		end
		return y
	end

	self.box:Show()
	self.box:ClearAllPoints()
	self.box:SetPoint('TOPLEFT', 0, -y)
	self.box:SetPoint('RIGHT', self.frame, 'RIGHT', 0, 0)
	PaintBox(self)
	y = y + SEARCH_H + 4

	local hint = arg.hint
	if hint == nil then
		hint = L['Search finds spells your game knows. If a spell is missing, type its ID.']
	end
	if type(hint) == 'string' and hint ~= '' then
		self.hint:Show()
		self.hint:SetText(hint)
		self.hint:ClearAllPoints()
		self.hint:SetPoint('TOPLEFT', 0, -y)
		y = y + TextHeight(self.hint, width) + 4
	else
		self.hint:Hide()
	end

	local ids = arg.tooltipIDs
	if type(ids) == 'table' and type(ids.get) == 'function' and type(ids.set) == 'function' then
		self.tooltipRow:Show()
		self.tooltipRow:ClearAllPoints()
		self.tooltipRow:SetPoint('TOPLEFT', 0, -y)
		self.tooltipRow:SetPoint('RIGHT', self.frame, 'RIGHT', 0, 0)
		Draw.SetSwitch(self.tooltipSwitch, ids.get() == true)
		Draw.SetEnabled(self.tooltipSwitch, not self.disabled)
		Draw.Paint(self.tooltipLabel, self.disabled and 'faint' or 'muted')
		y = y + 20
	else
		self.tooltipRow:Hide()
	end

	local reason = self.disabled and Resolve(arg.lockedReason)
	if type(reason) == 'string' and reason ~= '' then
		self.locked:Show()
		self.locked:SetText(reason)
		self.locked:ClearAllPoints()
		self.locked:SetPoint('TOPLEFT', 0, -y)
		Draw.Paint(self.locked, 'warn')
		y = y + TextHeight(self.locked, width) + 6
	else
		self.locked:Hide()
	end

	y = y + 2
	local list = SortedEntries(self)
	local narrow = width > 0 and width < 340
	for i, data in ipairs(list) do
		local entry = self.entries[i]
		if not entry then
			entry = CreateEntry(self)
			self.entries[i] = entry
		end
		entry.data = data
		entry:ClearAllPoints()
		entry:SetPoint('TOPLEFT', self.frame, 'TOPLEFT', 0, -y)
		entry:SetPoint('RIGHT', self.frame, 'RIGHT', 0, 0)
		Draw.SpellIcon(entry.icon, data.icon)
		entry.icon:SetDesaturated(self.disabled)
		entry.name:SetText(data.name)
		Draw.Paint(entry.name, self.disabled and 'faint' or (data.known and 'text' or 'muted'))
		entry.idText:SetText(string.format(L['ID %d'], data.spellID))
		entry.idText:SetShown(not narrow)
		entry.idText:ClearAllPoints()
		entry.idText:SetPoint('RIGHT', entry.mine, 'LEFT', -8, 0)
		entry.name:ClearAllPoints()
		entry.name:SetPoint('LEFT', entry.icon, 'RIGHT', 6, 0)
		if narrow then
			entry.name:SetPoint('RIGHT', entry.mine, 'LEFT', -8, 0)
		else
			entry.name:SetPoint('RIGHT', entry.idText, 'LEFT', -6, 0)
		end
		entry.mine.active = data.who == 'mine'
		entry.any.active = data.who == 'any'
		Draw.SetEnabled(entry.mine, not self.disabled)
		Draw.SetEnabled(entry.any, not self.disabled)
		Draw.SetEnabled(entry.remove, not self.disabled)
		entry:Show()
		y = y + ENTRY_H + ENTRY_GAP
	end
	for i = #list + 1, #self.entries do
		self.entries[i]:Hide()
		self.entries[i].data = nil
	end

	if #list == 0 then
		local empty = Resolve(arg.empty)
		self.empty:SetText(type(empty) == 'string' and empty or L['No spells yet.'])
		self.empty:Show()
		self.empty:ClearAllPoints()
		self.empty:SetPoint('TOPLEFT', 4, -y)
		y = y + 20
	else
		self.empty:Hide()
	end

	return y
end

local function Layout(self)
	Draw.RunLayout(self, Place)
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
		self.map = {}
		self.disabled = false
		self.focused = false
		live[self] = true
		self.edit:SetText('')
		self.placeholder:Show()
		self.clear:Hide()
		self:SetWidth(320)
		self:SetLabel('')
		self:SetDisabled(false)
	end,

	OnRelease = function(self)
		self.token = (self.token or 0) + 1
		live[self] = nil
		Draw.CloseMenu(self.box)
		self.edit:ClearFocus()
		self.edit:SetText('')
		for _, entry in ipairs(self.entries) do
			entry:Hide()
			entry.data = nil
		end
		self.arg = nil
		self.map = {}
		self.parent = nil
	end,

	---AceConfig hands the option's arg here (list, onChange, search, curated, ...).
	SetCustomData = function(self, arg)
		self.arg = type(arg) == 'table' and arg or nil
		self:Refresh()
	end,

	---Read the list again (from arg.list when given) and redraw.
	Refresh = function(self)
		local arg = self.arg
		if arg and arg.list ~= nil then
			self.map = NormalizeList(Resolve(arg.list), DefaultWho(self))
		end
		Layout(self)
	end,

	SetLabel = function(self, text)
		text = text or ''
		self.label:SetText(text)
		self.label:SetShown(text ~= '')
		Layout(self)
	end,

	---A map { [spellID] = 'mine'|'any' } or a list of { spellID, who }. AceConfig passes nil.
	SetValue = function(self, value)
		if type(value) == 'table' then
			self.map = NormalizeList(value, DefaultWho(self))
			Layout(self)
		end
	end,

	---@return table<integer, 'mine'|'any'>
	GetValue = function(self)
		return CopyMap(self.map)
	end,

	---Entries in display order, with names where the game has them.
	---@return { spellID: integer, who: string, name: string, icon?: number|string, known: boolean }[]
	GetEntries = function(self)
		return SortedEntries(self)
	end,

	SetList = function() end,

	SetDisabled = function(self, disabled)
		self.disabled = disabled and true or false
		self.edit:EnableMouse(not self.disabled)
		if self.edit.SetEnabled then
			self.edit:SetEnabled(not self.disabled)
		end
		if self.disabled then
			self.edit:ClearFocus()
			Draw.CloseMenu(self.box)
		end
		self.clear:SetShown((self.edit:GetText() or '') ~= '' and not self.disabled)
		Draw.Paint(self.label, self.disabled and 'faint' or 'text')
		Draw.Paint(self.edit, self.disabled and 'faint' or 'text')
		Layout(self)
	end,

	---Search as typing would, and show the results list.
	Search = function(self, text)
		self.edit:SetText(text or '')
		Search(self, text or '')
	end,

	---@param spellID integer
	---@return boolean added
	AddSpell = function(self, spellID)
		return AddSpell(self, spellID)
	end,

	---@param spellID integer
	---@param who 'mine'|'any'
	SetWho = function(self, spellID, who)
		if who == 'mine' or who == 'any' then
			SetWho(self, spellID, who)
		end
	end,

	RemoveSpell = function(self, spellID)
		RemoveSpell(self, spellID)
	end,

	ClearFocus = function(self)
		self.edit:ClearFocus()
		Draw.CloseMenu(self.box)
	end,

	OnWidthSet = function(self)
		Draw.LayoutPass(self, Layout)
	end,

	SetMultiselect = function() end,
	SetItemValue = function() end,
	SetPulloutWidth = function() end,
}

local function Constructor()
	local AceGUI = LibStub('AceGUI-3.0')
	local frame = CreateFrame('Frame', nil, UIParent)
	frame:Hide()

	---@type table
	local widget = { frame = frame, type = Widgets:TypeName('SpellList'), map = {}, entries = {} }

	widget.label = Draw.Text(frame, 12, 'text')
	widget.label:SetPoint('TOPLEFT', 0, -2)
	widget.label:SetPoint('TOPRIGHT', 0, -2)

	local box = CreateFrame('Frame', nil, frame)
	box:SetHeight(SEARCH_H)
	box:EnableMouse(true)
	box.fill = Draw.Rect(box, 'BACKGROUND')
	box.fill:SetAllPoints()
	box.border = Draw.Border(box)
	box:SetScript('OnEnter', function(self)
		self.hovered = true
		PaintBox(widget)
	end)
	box:SetScript('OnLeave', function(self)
		self.hovered = false
		PaintBox(widget)
	end)
	box:SetScript('OnMouseDown', function()
		if not widget.disabled then
			widget.edit:SetFocus()
		end
	end)
	box:SetScript('OnShow', function(self)
		Draw.LayoutBorder(self.border)
	end)
	widget.box = box

	widget.searchIcon = box:CreateTexture(nil, 'ARTWORK')
	widget.searchIcon:SetSize(14, 14)
	widget.searchIcon:SetPoint('LEFT', 6, 0)
	Draw.Icon(widget.searchIcon, 'search')

	local clear = CreateFrame('Button', nil, box)
	clear:SetSize(14, 14)
	clear:SetPoint('RIGHT', -5, 0)
	clear.icon = clear:CreateTexture(nil, 'ARTWORK')
	clear.icon:SetAllPoints()
	Draw.Icon(clear.icon, 'clear')
	clear:SetScript('OnClick', function()
		widget.edit:SetText('')
		widget.placeholder:Show()
		clear:Hide()
		Draw.CloseMenu(box)
	end)
	clear:Hide()
	widget.clear = clear

	local edit = CreateFrame('EditBox', nil, box)
	edit:SetPoint('TOPLEFT', 24, 0)
	edit:SetPoint('BOTTOMRIGHT', -22, 0)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(64)
	Draw.SetFont(edit, 12)
	edit:SetTextColor(Draw.Color('text'))
	edit.obj = widget
	edit:SetScript('OnTextChanged', Edit_OnTextChanged)
	edit:SetScript('OnEnterPressed', Edit_OnEnterPressed)
	edit:SetScript('OnEscapePressed', Edit_OnEscapePressed)
	edit:SetScript('OnEditFocusGained', Edit_OnFocusGained)
	edit:SetScript('OnEditFocusLost', Edit_OnFocusLost)
	widget.edit = edit

	local placeholder = Draw.Text(box, 12, 'faint')
	placeholder:SetPoint('LEFT', edit, 'LEFT', 0, 0)
	placeholder:SetText(L['Type a spell name or ID'])
	widget.placeholder = placeholder

	widget.hint = Draw.Text(frame, 10, 'faint')
	widget.hint:SetWordWrap(true)

	local tooltipRow = CreateFrame('Frame', nil, frame)
	tooltipRow:SetHeight(18)
	widget.tooltipRow = tooltipRow
	widget.tooltipSwitch = Draw.Switch(tooltipRow)
	widget.tooltipSwitch:SetPoint('LEFT', 0, 0)
	widget.tooltipSwitch.onClick = function(switch)
		local ids = widget.arg and widget.arg.tooltipIDs
		if type(ids) == 'table' and type(ids.set) == 'function' then
			ids.set(not switch.checked)
		end
		if type(ids) == 'table' and type(ids.get) == 'function' then
			Draw.SetSwitch(switch, ids.get() == true)
		end
	end
	widget.tooltipLabel = Draw.Text(tooltipRow, 11, 'muted')
	widget.tooltipLabel:SetPoint('LEFT', widget.tooltipSwitch, 'RIGHT', 8, 0)
	widget.tooltipLabel:SetText(L['Show spell IDs in tooltips'])

	widget.locked = Draw.Text(frame, 11, 'warn')
	widget.locked:SetWordWrap(true)
	widget.empty = Draw.Text(frame, 11, 'faint')

	for name, fn in pairs(methods) do
		widget[name] = fn
	end

	Draw.OnAccent(frame, function()
		if widget.map and frame:IsShown() then
			Layout(widget)
		end
	end)

	return AceGUI:RegisterAsWidget(widget)
end

Widgets.types.SpellList = { version = 1, Constructor = Constructor }
