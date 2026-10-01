---@class SUI
local SUI = SUI
local Style = SUI.UI.Style
local W = SUI.UI.OptionWidgets

-- Dropdown replacement with its own flat list. Long lists scroll and get a search box, and the
-- list can be driven with the arrow keys, Enter and Escape. Same methods, callbacks and events as
-- the stock AceGUI Dropdown. Custom item widget types are shown as plain text.
-- The SUI-Media-* types are the same dropdown for shared media (fonts, bar textures, backgrounds,
-- borders, sounds): they show the media name and preview each item.

local Type, Version = 'SUI-Dropdown', 1
local AceGUI = LibStub and LibStub('AceGUI-3.0', true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then
	return
end

local pairs, ipairs, type, tostring, tonumber = pairs, ipairs, type, tostring, tonumber
local floor, max, min = math.floor, math.max, math.min
local tsort, tconcat = table.sort, table.concat

local ROW_H = 20
local MAX_ROWS = 12
local SEARCH_AFTER = 10
local SEARCH_H = 22
local PAD = 4

local L = SUI.L or setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})

---@class SUI.OptionsDropdownPullout : Frame
local pullout

local LSM = LibStub and LibStub('LibSharedMedia-3.0', true)
local MEDIA = { Font = 'font', Statusbar = 'statusbar', Background = 'background', Border = 'border', Sound = 'sound' }
local SWATCH_W = 40
local SPEAKER = 'Interface\\Common\\VoiceChat-Speaker'

---The file for a media item; lists map a media name to its file
local function MediaPath(self, key)
	local path = self.list and self.list[key]
	if (path == nil or path == key) and LSM then
		path = LSM:Fetch(self.media, key, true)
	end
	return path
end

---What a list item reads as: media lists show the name, other lists their text
local function ItemText(self, key)
	if self.media then
		return key ~= nil and tostring(key) or ''
	end
	return self.list[key]
end

----------------------------------------------------------------------------------------------------
-- List helpers
----------------------------------------------------------------------------------------------------

local function sortTbl(x, y)
	local num1, num2 = tonumber(x), tonumber(y)
	if num1 and num2 then -- numeric comparison, either two numbers or numeric strings
		return num1 < num2
	else -- compare everything else tostring'ed
		return tostring(x) < tostring(y)
	end
end

local function ShowMultiText(self)
	local parts = {}
	for _, key in ipairs(self.order) do
		if self.itemValues[key] then
			parts[#parts + 1] = tostring(self.list[key])
		end
	end
	self:SetText(#parts > 0 and tconcat(parts, ', ') or nil)
end

---Keys that match the search text, in list order
local function BuildVisible(self, query)
	local visible = {}
	local needle = query and query ~= '' and query:lower() or nil
	for _, key in ipairs(self.order) do
		if not needle or W.PlainText(ItemText(self, key)):lower():find(needle, 1, true) then
			visible[#visible + 1] = key
		end
	end
	return visible
end

----------------------------------------------------------------------------------------------------
-- Media previews (used by the box and by list rows)
----------------------------------------------------------------------------------------------------

local function Speaker_OnClick(play)
	if play.path and PlaySoundFile then
		PlaySoundFile(play.path, 'Master')
	end
end

local function Speaker_OnEnter(play)
	play.icon:SetVertexColor(1, 1, 1, 1)
end

local function Speaker_OnLeave(play)
	local c = Style.color.muted
	play.icon:SetVertexColor(c[1], c[2], c[3], 1)
end

local function EnsureMediaParts(holder)
	if holder.mediaBar then
		return
	end
	holder.mediaBar = holder:CreateTexture(nil, 'ARTWORK', nil, -8)
	holder.mediaBar:SetPoint('TOPLEFT', 1, -1)
	holder.mediaBar:SetPoint('BOTTOMRIGHT', -1, 1)
	holder.mediaBar:Hide()
	holder.mediaSwatch = holder:CreateTexture(nil, 'ARTWORK')
	holder.mediaSwatch:SetSize(SWATCH_W, 14)
	holder.mediaSwatch:Hide()
	holder.mediaEdge = CreateFrame('Frame', nil, holder, BackdropTemplateMixin and 'BackdropTemplate' or nil)
	holder.mediaEdge:SetSize(SWATCH_W, 16)
	holder.mediaEdge:Hide()
	local play = CreateFrame('Button', nil, holder)
	play:SetSize(16, 16)
	play.icon = play:CreateTexture(nil, 'ARTWORK')
	play.icon:SetAllPoints()
	play.icon:SetTexture(SPEAKER)
	play:SetScript('OnClick', Speaker_OnClick)
	play:SetScript('OnEnter', Speaker_OnEnter)
	play:SetScript('OnLeave', Speaker_OnLeave)
	Speaker_OnLeave(play)
	play:Hide()
	holder.mediaPlay = play
end

---Show `key` of a media dropdown on `holder` (the box or a row): the font face, a bar texture behind
---the text, a background or border swatch, or a speaker that plays the sound. Without a media owner
---every preview is put away again, since rows are shared by all dropdowns.
---@param holder Frame
---@param text FontString
---@param owner table|nil Dropdown widget
---@param key any
---@param right number Space the text normally keeps on its right
local function PaintMedia(holder, text, owner, key, right)
	local kind = owner and owner.media
	if not kind and not holder.mediaBar then
		return
	end
	EnsureMediaParts(holder)
	local path = kind and key ~= nil and MediaPath(owner, key) or nil

	if kind == 'font' and path then
		text:SetFont(path, W.LABEL_SIZE, '')
		holder.mediaFont = true
	elseif holder.mediaFont then
		Style:SetFont(text, W.LABEL_SIZE)
		holder.mediaFont = nil
	end

	holder.mediaBar:SetShown(kind == 'statusbar' and path ~= nil)
	if kind == 'statusbar' and path then
		holder.mediaBar:SetTexture(path)
		holder.mediaBar:SetVertexColor(1, 1, 1, 0.75)
	end

	local swatch = kind == 'background' and path ~= nil
	holder.mediaSwatch:SetShown(swatch)
	if swatch then
		holder.mediaSwatch:SetTexture(path)
		holder.mediaSwatch:ClearAllPoints()
		holder.mediaSwatch:SetPoint('RIGHT', holder, 'RIGHT', -right, 0)
	end

	local edge = kind == 'border' and path ~= nil
	holder.mediaEdge:SetShown(edge)
	if edge then
		holder.mediaEdge:SetBackdrop({ edgeFile = path, edgeSize = 12 })
		holder.mediaEdge:ClearAllPoints()
		holder.mediaEdge:SetPoint('RIGHT', holder, 'RIGHT', -right, 0)
	end

	local sound = kind == 'sound' and path ~= nil
	holder.mediaPlay:SetShown(sound)
	holder.mediaPlay.path = path
	if sound then
		holder.mediaPlay:ClearAllPoints()
		holder.mediaPlay:SetPoint('RIGHT', holder, 'RIGHT', -right, 0)
		holder.mediaPlay:SetFrameLevel(holder:GetFrameLevel() + 2)
	end

	local extra = (swatch or edge) and (SWATCH_W + 6) or (sound and 22 or 0)
	text:SetPoint('RIGHT', holder, 'RIGHT', -(right + extra), 0)
end

----------------------------------------------------------------------------------------------------
-- Drawing the box
----------------------------------------------------------------------------------------------------

local function PaintBox(self)
	local c = Style.color
	local state = 'normal'
	if self.disabled then
		state = 'disabled'
	elseif self.open then
		state = 'focus'
	elseif self.hovered then
		state = 'hover'
	end
	W.PaintBox(self.button, state)
	W.Paint(self.label, self.disabled and c.faint or c.text)
	W.Paint(self.text, self.disabled and c.faint or c.text)
	local arrowColor = self.disabled and c.faint or ((self.hovered or self.open) and c.text or c.muted)
	self.arrow:SetColor(arrowColor[1], arrowColor[2], arrowColor[3], 1)
	self.arrow:SetDirection(self.open and self.openUp and 'UP' or 'DOWN')
end

----------------------------------------------------------------------------------------------------
-- Pullout (one shared list; only one dropdown is open at a time)
----------------------------------------------------------------------------------------------------

local Pullout = {}

local function PaintRow(row)
	local owner = pullout.owner
	if not owner or row.key == nil then
		return
	end
	local c = Style.color
	local accent = W.Accent()
	local key = row.key
	local disabled = owner.itemDisabled[key]
	local selected
	if owner.multiselect then
		selected = owner.itemValues[key] and true or false
	else
		selected = owner.value == key
	end
	local lit = not disabled and (row.hovered or pullout.cursor == row.index)
	row.fill:SetShown(lit)
	W.Paint(row.fill, lit and { 1, 1, 1, 0.07 } or c.hover)

	if owner.multiselect then
		row.bar:Hide()
		row.box:Show()
		row.check:SetShown(selected)
		if selected then
			W.Paint(row.boxFill, accent, disabled and 0.4 or 1)
			row.boxBorder:SetColor(accent[1], accent[2], accent[3], disabled and 0.4 or 1)
		else
			W.Paint(row.boxFill, c.input)
			row.boxBorder:SetColor(c.lineStrong[1], c.lineStrong[2], c.lineStrong[3], c.lineStrong[4])
		end
		W.Paint(row.check, c.onAccent)
		row.text:SetPoint('LEFT', 26, 0)
	else
		row.box:Hide()
		row.bar:SetShown(selected)
		W.Paint(row.bar, accent)
		row.text:SetPoint('LEFT', 10, 0)
	end

	if disabled then
		W.Paint(row.text, c.faint)
	elseif selected and not owner.multiselect then
		W.Paint(row.text, W.Mix(accent, c.text, 0.25))
	elseif lit then
		W.Paint(row.text, c.text)
	else
		W.Paint(row.text, W.Mix(c.text, c.muted, 0.3))
	end
end

local function Row_OnEnter(row)
	row.hovered = true
	pullout.cursor = row.index
	Pullout.Render()
end

local function Row_OnLeave(row)
	row.hovered = false
	PaintRow(row)
end

local function Row_OnClick(row)
	Pullout.Choose(row.key)
end

local function CreateRow(index)
	local row = CreateFrame('Button', nil, pullout.list)
	row:SetHeight(ROW_H)
	row:SetPoint('TOPLEFT', 0, -(index - 1) * ROW_H)
	row:SetPoint('TOPRIGHT', 0, -(index - 1) * ROW_H)
	row.fill = W:CreateRect(row, 'BACKGROUND')
	row.fill:SetAllPoints()
	row.bar = W:CreateRect(row, 'ARTWORK')
	row.bar:SetPoint('TOPLEFT', 0, -3)
	row.bar:SetPoint('BOTTOMLEFT', 0, 3)
	row.bar:SetWidth(2)

	row.box = CreateFrame('Frame', nil, row)
	row.box:SetSize(12, 12)
	row.box:SetPoint('LEFT', 8, 0)
	row.boxFill = Style:CreateFill(row.box, Style.color.input)
	row.boxBorder = Style:CreateBorder(row.box)
	row.check = row.box:CreateTexture(nil, 'OVERLAY')
	row.check:SetTexture(W.CHECK_GLYPH)
	row.check:SetDesaturated(true)
	row.check:SetPoint('CENTER', 0, 0)
	row.check:SetSize(16, 16)

	row.text = Style:CreateText(row, W.LABEL_SIZE)
	row.text:SetPoint('LEFT', 10, 0)
	row.text:SetPoint('RIGHT', -6, 0)
	row.text:SetJustifyH('LEFT')
	row.text:SetWordWrap(false)

	row:SetScript('OnEnter', Row_OnEnter)
	row:SetScript('OnLeave', Row_OnLeave)
	row:SetScript('OnClick', Row_OnClick)
	return row
end

---Rows that fit, from the full list size so the list keeps its height while searching
local function RowCount(owner)
	return max(1, min(#owner.order, MAX_ROWS))
end

function Pullout.Render()
	local owner = pullout.owner
	if not owner then
		return
	end
	local visible = pullout.visible
	local rows = RowCount(owner)
	local maxOffset = max(0, #visible - rows)
	pullout.offset = max(0, min(pullout.offset or 0, maxOffset))

	for i = 1, rows do
		local row = pullout.rows[i]
		if not row then
			row = CreateRow(i)
			pullout.rows[i] = row
		end
		local index = pullout.offset + i
		local key = visible[index]
		row.index = index
		row.key = key
		if key ~= nil then
			row.text:SetText(ItemText(owner, key))
			PaintMedia(row, row.text, owner, key, 6)
			row:Show()
			PaintRow(row)
		else
			row:Hide()
		end
	end
	for i = rows + 1, #pullout.rows do
		pullout.rows[i]:Hide()
	end
	pullout.empty:SetShown(#visible == 0)

	pullout.updating = true
	if maxOffset > 0 then
		pullout.scrollbar:Show()
		pullout.scrollbar:SetMinMaxValues(0, maxOffset)
		pullout.scrollbar:SetValue(pullout.offset)
		pullout.scrollbar:SetThumbRatio(rows / #visible)
		pullout.list:SetPoint('BOTTOMRIGHT', -(PAD + 10), PAD)
	else
		pullout.scrollbar:Hide()
		pullout.list:SetPoint('BOTTOMRIGHT', -PAD, PAD)
	end
	pullout.updating = false
end

---Keep the keyboard cursor on screen
local function ScrollToCursor()
	local rows = RowCount(pullout.owner)
	local cursor = pullout.cursor or 1
	if cursor <= pullout.offset then
		pullout.offset = cursor - 1
	elseif cursor > pullout.offset + rows then
		pullout.offset = cursor - rows
	end
end

function Pullout.Filter()
	local owner = pullout.owner
	if not owner then
		return
	end
	local query = pullout.search:IsShown() and pullout.search:GetText() or ''
	pullout.placeholder:SetShown(query == '')
	pullout.visible = BuildVisible(owner, query)
	pullout.offset = 0
	pullout.cursor = #pullout.visible > 0 and 1 or nil
	Pullout.Render()
end

---@param key any
function Pullout.Choose(key)
	local self = pullout.owner
	if not self or key == nil or self.itemDisabled[key] then
		return
	end
	if self.multiselect then
		local checked = not self.itemValues[key]
		self.itemValues[key] = checked
		W.Sound(checked and 856 or 857)
		self:Fire('OnValueChanged', key, checked)
		if pullout.owner == self then
			ShowMultiText(self)
			Pullout.Render()
		end
	else
		W.Sound(856)
		if self.value ~= key then
			self:SetValue(key)
			self:Fire('OnValueChanged', key)
		end
		if self.open and pullout.owner == self then
			Pullout.Close(self)
		end
	end
end

---@param delta number Rows to move the cursor
local function MoveCursor(delta)
	local count = #pullout.visible
	if count == 0 then
		return
	end
	local cursor = (pullout.cursor or 0) + delta
	pullout.cursor = max(1, min(count, cursor))
	ScrollToCursor()
	Pullout.Render()
end

---@return boolean handled
local function HandleKey(key)
	if key == 'ESCAPE' then
		Pullout.Close(pullout.owner)
	elseif key == 'UP' then
		MoveCursor(-1)
	elseif key == 'DOWN' then
		MoveCursor(1)
	elseif key == 'PAGEUP' then
		MoveCursor(-RowCount(pullout.owner))
	elseif key == 'PAGEDOWN' then
		MoveCursor(RowCount(pullout.owner))
	elseif key == 'HOME' then
		MoveCursor(-#pullout.visible)
	elseif key == 'END' then
		MoveCursor(#pullout.visible)
	elseif key == 'ENTER' or key == 'SPACE' then
		Pullout.Choose(pullout.visible[pullout.cursor or 0])
	else
		return false
	end
	return true
end

local function Pullout_OnKeyDown(frame, key)
	local handled = HandleKey(key)
	if not InCombatLockdown() then
		frame:SetPropagateKeyboardInput(not handled)
	end
end

local function Pullout_OnMouseWheel(frame, delta)
	pullout.offset = (pullout.offset or 0) - delta * 2
	Pullout.Render()
end

local function Search_OnTextChanged(box)
	Pullout.Filter()
end

local function Search_OnEscapePressed(box)
	if box:GetText() ~= '' then
		box:SetText('')
	else
		Pullout.Close(pullout.owner)
	end
end

local function Search_OnEnterPressed(box)
	Pullout.Choose(pullout.visible[pullout.cursor or 0])
end

local function Search_OnArrowPressed(box, key)
	if key == 'UP' or key == 'DOWN' then
		HandleKey(key)
	end
end

local function Scrollbar_OnValueChanged(bar, value)
	if pullout.updating then
		return
	end
	pullout.offset = floor(value + 0.5)
	Pullout.Render()
end

local function GetPullout()
	if pullout then
		return pullout
	end
	pullout = CreateFrame('Frame', 'SUI_OptionsDropdownPullout', UIParent) ---@type SUI.OptionsDropdownPullout
	pullout:Hide()
	pullout:SetFrameStrata('TOOLTIP')
	pullout:SetClampedToScreen(true)
	pullout:EnableMouse(true)
	pullout:EnableMouseWheel(true)
	pullout:SetScript('OnMouseWheel', Pullout_OnMouseWheel)
	pullout:SetScript('OnKeyDown', Pullout_OnKeyDown)
	Style:SkinPanel(pullout, Style.color.raised, Style.color.lineStrong)
	pullout.rows = {}
	pullout.visible = {}
	pullout.offset = 0

	local searchBox = CreateFrame('Frame', nil, pullout)
	searchBox:SetPoint('TOPLEFT', PAD, -PAD)
	searchBox:SetPoint('TOPRIGHT', -PAD, -PAD)
	searchBox:SetHeight(SEARCH_H)
	W:SkinBox(searchBox)
	pullout.searchBox = searchBox

	local search = CreateFrame('EditBox', nil, searchBox)
	search:SetAllPoints()
	search:SetAutoFocus(false)
	search:SetTextInsets(8, 8, 0, 0)
	search:SetMaxLetters(64)
	Style:SetFont(search, W.LABEL_SIZE)
	search:SetTextColor(Style.color.text[1], Style.color.text[2], Style.color.text[3])
	search:SetScript('OnTextChanged', Search_OnTextChanged)
	search:SetScript('OnEscapePressed', Search_OnEscapePressed)
	search:SetScript('OnEnterPressed', Search_OnEnterPressed)
	search:SetScript('OnArrowPressed', Search_OnArrowPressed)
	search:SetScript('OnEditFocusGained', function()
		W.PaintBox(searchBox, 'focus')
	end)
	search:SetScript('OnEditFocusLost', function()
		W.PaintBox(searchBox, 'normal')
	end)
	pullout.search = search

	local placeholder = Style:CreateText(searchBox, W.LABEL_SIZE, Style.color.faint)
	placeholder:SetPoint('LEFT', 8, 0)
	placeholder:SetText(L['Search'])
	pullout.placeholder = placeholder

	local list = CreateFrame('Frame', nil, pullout)
	list:SetPoint('TOPLEFT', PAD, -PAD)
	list:SetPoint('BOTTOMRIGHT', -PAD, PAD)
	pullout.list = list

	local empty = Style:CreateText(list, W.SMALL_SIZE, Style.color.muted)
	empty:SetPoint('TOPLEFT', 10, -4)
	empty:SetPoint('RIGHT', -6, 0)
	empty:SetJustifyH('LEFT')
	empty:SetText(L['Nothing found. Try another word.'])
	empty:Hide()
	pullout.empty = empty

	local scrollbar = W:CreateScrollBar(pullout)
	scrollbar:SetPoint('TOPRIGHT', list, 'TOPRIGHT', 10, 0)
	scrollbar:SetPoint('BOTTOMRIGHT', pullout, 'BOTTOMRIGHT', -PAD, PAD)
	scrollbar:SetValueStep(1)
	scrollbar:SetScript('OnValueChanged', Scrollbar_OnValueChanged)
	scrollbar:Hide()
	pullout.scrollbar = scrollbar

	pullout:SetScript('OnHide', function(frame)
		frame:UnregisterEvent('GLOBAL_MOUSE_DOWN')
		if frame.owner then
			Pullout.Close(frame.owner)
		end
	end)
	Style:OnAccentChanged(pullout, function()
		if pullout:IsShown() then
			Pullout.Render()
		end
	end)
	return pullout
end

---@param self table Dropdown widget
function Pullout.Open(self)
	local frame = GetPullout()
	if frame.owner and frame.owner ~= self then
		Pullout.Close(frame.owner)
	end
	frame.owner = self
	frame:SetScale(self.frame:GetEffectiveScale() / UIParent:GetEffectiveScale())
	frame:SetWidth(self.pulloutWidth or self.button:GetWidth() or 200)

	local hasSearch = #self.order > SEARCH_AFTER
	frame.searchBox:SetShown(hasSearch)
	frame.search:SetShown(hasSearch)
	frame.search:SetText('')
	local top = PAD + (hasSearch and (SEARCH_H + PAD) or 0)
	frame.list:ClearAllPoints()
	frame.list:SetPoint('TOPLEFT', PAD, -top)
	frame.list:SetPoint('BOTTOMRIGHT', -PAD, PAD)
	local height = top + RowCount(self) * ROW_H + PAD
	frame:SetHeight(height)

	-- Open upward when there is no room below
	local scale = self.button:GetEffectiveScale()
	local bottom = (self.button:GetBottom() or 0) * scale
	local screenTop = (UIParent:GetTop() or 0) * UIParent:GetEffectiveScale()
	local needed = height * frame:GetEffectiveScale()
	local above = screenTop - (self.button:GetTop() or 0) * scale
	self.openUp = bottom < needed and above > bottom
	frame:ClearAllPoints()
	if self.openUp then
		frame:SetPoint('BOTTOMLEFT', self.button, 'TOPLEFT', 0, 2)
	else
		frame:SetPoint('TOPLEFT', self.button, 'BOTTOMLEFT', 0, -2)
	end
	frame:SetFrameLevel(self.frame:GetFrameLevel() + 30)

	frame.visible = BuildVisible(self, nil)
	frame.cursor = nil
	frame.offset = 0
	for i, key in ipairs(frame.visible) do
		if (not self.multiselect and key == self.value) or (self.multiselect and frame.cursor == nil and self.itemValues[key]) then
			frame.cursor = i
		end
	end
	if frame.cursor then
		frame.offset = frame.cursor - floor(RowCount(self) / 2)
	end
	frame.placeholder:Show()
	frame:Show()
	Pullout.Render()

	-- Keyboard: while searching the box has it, otherwise the list takes only the keys it uses.
	-- Key input cannot be passed on in combat, so the list does not take keys then.
	if InCombatLockdown() then
		frame:EnableKeyboard(false)
	else
		frame:EnableKeyboard(true)
		frame:SetPropagateKeyboardInput(true)
	end
	if hasSearch then
		frame.search:SetFocus()
	end

	W.WatchGlobalClicks(frame, function()
		if frame.owner and not W.MouseOverAny(frame, frame.owner.button) then
			Pullout.Close(frame.owner)
		end
	end)

	self.open = true
	PaintBox(self)
	self:Fire('OnOpened')
end

---@param self table|nil Dropdown widget; only its own list is closed
function Pullout.Close(self)
	if not pullout or not self or pullout.owner ~= self then
		return
	end
	pullout.owner = nil
	pullout.search:ClearFocus()
	pullout:EnableKeyboard(false)
	pullout:Hide()
	for _, row in ipairs(pullout.rows) do
		row.hovered = false
	end
	self.open = nil
	PaintBox(self)
	self:Fire('OnClosed')
end

----------------------------------------------------------------------------------------------------
-- Scripts
----------------------------------------------------------------------------------------------------

local function Control_OnEnter(frame)
	local self = frame.obj
	self.hovered = true
	PaintBox(self)
	self:Fire('OnEnter')
end

local function Control_OnLeave(frame)
	local self = frame.obj
	self.hovered = false
	PaintBox(self)
	self:Fire('OnLeave')
end

local function Dropdown_OnHide(frame)
	local self = frame.obj
	if self.open then
		Pullout.Close(self)
	end
end

local function Dropdown_TogglePullout(frame)
	local self = frame.obj
	if self.disabled then
		return
	end
	if self.open then
		Pullout.Close(self)
		AceGUI:ClearFocus()
	else
		-- focus first: taking focus closes whichever dropdown had the shared list
		AceGUI:SetFocus(self)
		W.Sound(856)
		Pullout.Open(self)
	end
end

local function Frame_OnShow(frame)
	frame.obj.arrow:Layout()
end

----------------------------------------------------------------------------------------------------
-- Methods
----------------------------------------------------------------------------------------------------

local methods = {
	OnAcquire = function(self)
		self.hovered = false
		self:SetHeight(W.LABELED_HEIGHT)
		self:SetWidth(200)
		self:SetLabel()
		self:SetPulloutWidth(nil)
		self.list = {}
		wipe(self.order)
		wipe(self.itemValues)
		wipe(self.itemDisabled)
		PaintBox(self)
	end,

	OnRelease = function(self)
		if self.open then
			Pullout.Close(self)
		end

		self:SetText('')
		self:SetDisabled(false)
		self:SetMultiselect(false)

		self.value = nil
		self.list = nil
		self.open = nil
		self.hovered = false
		self.itemType = nil
		wipe(self.order)
		wipe(self.itemValues)
		wipe(self.itemDisabled)

		self.frame:ClearAllPoints()
		self.frame:Hide()
	end,

	SetDisabled = function(self, disabled)
		self.disabled = disabled
		if disabled then
			if self.open then
				Pullout.Close(self)
			end
			self.button:Disable()
		else
			self.button:Enable()
		end
		PaintBox(self)
	end,

	ClearFocus = function(self)
		if self.open then
			Pullout.Close(self)
		end
	end,

	SetText = function(self, text)
		self.text:SetText(text or '')
	end,

	SetLabel = function(self, text)
		if text and text ~= '' then
			self.label:SetText(text)
			self.label:Show()
			self:SetHeight(W.LABELED_HEIGHT)
			self.alignoffset = W.LABELED_ALIGN
		else
			self.label:SetText('')
			self.label:Hide()
			self:SetHeight(W.UNLABELED_HEIGHT)
			self.alignoffset = W.UNLABELED_ALIGN
		end
	end,

	SetValue = function(self, value)
		if self.media then
			self:SetText(value ~= nil and tostring(value) or '')
			PaintMedia(self.button, self.text, value ~= nil and self or nil, value, 22)
		else
			self:SetText(self.list[value] or '')
		end
		self.value = value
		if self.open and pullout and pullout.owner == self then
			Pullout.Render()
		end
	end,

	GetValue = function(self)
		return self.value
	end,

	SetItemValue = function(self, item, value)
		if not self.multiselect then
			return
		end
		self.itemValues[item] = value and true or false
		ShowMultiText(self)
		if self.open and pullout and pullout.owner == self then
			Pullout.Render()
		end
	end,

	SetItemDisabled = function(self, item, disabled)
		self.itemDisabled[item] = disabled and true or nil
		if self.open and pullout and pullout.owner == self then
			Pullout.Render()
		end
	end,

	SetList = function(self, list, order, itemType)
		if not list and self.media and LSM then
			list = LSM:HashTable(self.media)
		end
		self.list = list or {}
		self.itemType = itemType
		wipe(self.order)
		wipe(self.itemValues)
		wipe(self.itemDisabled)
		if list then
			if type(order) ~= 'table' then
				for key in pairs(list) do
					self.order[#self.order + 1] = key
				end
				tsort(self.order, sortTbl)
			else
				for _, key in ipairs(order) do
					self.order[#self.order + 1] = key
				end
			end
			if self.multiselect then
				ShowMultiText(self)
			end
		end
		if self.open and pullout and pullout.owner == self then
			Pullout.Filter()
		end
	end,

	AddItem = function(self, value, text, itemType)
		self.list[value] = text
		self.order[#self.order + 1] = value
		if self.open and pullout and pullout.owner == self then
			Pullout.Filter()
		end
	end,

	SetMultiselect = function(self, multi)
		self.multiselect = multi
		if multi then
			ShowMultiText(self)
		end
	end,

	GetMultiselect = function(self)
		return self.multiselect
	end,

	SetPulloutWidth = function(self, width)
		self.pulloutWidth = width
	end,
}

----------------------------------------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------------------------------------

---@param kind? string A MEDIA key for a shared media dropdown
local function Constructor(kind)
	local widgetType = kind and ('SUI-Media-' .. kind) or Type
	local count = AceGUI:GetNextWidgetNum(widgetType)
	local frame = CreateFrame('Frame', nil, UIParent)
	frame:Hide()
	frame:SetScript('OnHide', Dropdown_OnHide)
	frame:SetScript('OnShow', Frame_OnShow)

	local label = Style:CreateText(frame, W.LABEL_SIZE)
	label:SetPoint('TOPLEFT', 0, 0)
	label:SetPoint('TOPRIGHT', 0, 0)
	label:SetJustifyH('LEFT')
	label:SetWordWrap(false)
	label:SetHeight(20)
	label:Hide()

	local button = CreateFrame('Button', 'SUI_Options' .. (kind or '') .. 'Dropdown' .. count, frame)
	button:SetPoint('BOTTOMLEFT', 0, 0)
	button:SetPoint('BOTTOMRIGHT', 0, 0)
	button:SetHeight(W.INPUT_HEIGHT)
	W:SkinBox(button)
	button:SetScript('OnEnter', Control_OnEnter)
	button:SetScript('OnLeave', Control_OnLeave)
	button:SetScript('OnClick', Dropdown_TogglePullout)

	local text = Style:CreateText(button, W.LABEL_SIZE)
	text:SetPoint('LEFT', 8, 0)
	text:SetPoint('RIGHT', -22, 0)
	text:SetJustifyH('LEFT')
	text:SetWordWrap(false)

	local arrow = W:CreateArrow(button, 4)
	arrow.anchor:SetPoint('RIGHT', button, 'RIGHT', -8, 0)

	local widget = {
		type = widgetType,
		media = kind and MEDIA[kind],
		frame = frame,
		count = count,
		button = button,
		text = text,
		label = label,
		arrow = arrow,
		alignoffset = W.LABELED_ALIGN,
		list = {},
		order = {},
		itemValues = {},
		itemDisabled = {},
	}
	for method, func in pairs(methods) do
		widget[method] = func
	end
	frame.obj, button.obj = widget, widget
	Style:OnAccentChanged(frame, function()
		PaintBox(widget)
	end)

	return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(Type, function()
	return Constructor()
end, Version)

for kind in pairs(MEDIA) do
	AceGUI:RegisterWidgetType('SUI-Media-' .. kind, function()
		return Constructor(kind)
	end, Version)
end
