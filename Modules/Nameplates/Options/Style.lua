local _, ns = ...
local P = ns.Plates
local L = P.L
local Options = P.Options

-- Style page (3.2 #1). A gallery of live cards (the host's card grid; P.Gallery draws them with the
-- real renderer), the plate size, and the actions on the style in use: Customize this style
-- (primary), Reset my changes (only when there are changes), Make a copy, Share and Import.
-- Hovering a card shows that style in the preview panel (P.Gallery:SetHover); right-click opens
-- Use, Make a copy, Share and, for the player's own styles, Rename and Delete (P.Gallery.OnMenuPick,
-- answered here). Rename and Delete ask on the page itself, because a popup would open behind the
-- settings window.
-- More settings: exact plate width and height, bar texture (a picker with pictures), font face (each
-- name drawn in its own face) and text size. They write the style's overlay (profile.tweaks[id]), so
-- "Reset my changes" takes them back with everything else.
--
-- Rules kept here: get and set read the Store on every call; settings that change what the plates
-- look like are locked while the game restricts changes, with the reason shown on the page.

local Registry, Merge, Schema = P.Styles.Registry, P.Styles.Merge, P.Styles.Schema
local Store = P.Store
local util = P.util

---@class Plates.StylePage
local Style = { notice = nil, pending = nil }
P.StylePage = Style

local SIZES = { small = L['Small'], medium = L['Medium'], large = L['Large'] }
local SIZE_KEYS = { small = true, medium = true, large = true }
local NOTICE_SECONDS = 20

----------------------------------------------------------------------------------------------------
-- The style in use
----------------------------------------------------------------------------------------------------

---Style id and plate size the settings below edit.
---@return string id A real style id (the 'host' pseudo id resolved)
---@return string sizeKey
local function Current()
	local sizeKey = Store:Get('size')
	if not SIZE_KEYS[sizeKey] then
		sizeKey = 'medium'
	end
	return Registry:ResolveId(Store:Get('style')), sizeKey
end

---The card value that is selected: 'host' for the host's look, else a style id.
---@return string
local function CardValue()
	local value = Registry:ResolveId(Store:Get('style'))
	local style = Registry:Get(value)
	if style and style.matchesHost then
		return 'host'
	end
	return value
end

local function BaseResolved(id, sizeKey)
	local base = Registry:Get(id)
	return base and Merge.ResolveRaw(base, nil, 'enemyNPC', sizeKey, P.hostLook) or nil
end

----------------------------------------------------------------------------------------------------
-- Writing the overlay (profile.tweaks[styleId], 5.2 layer 3)
----------------------------------------------------------------------------------------------------

---@class Plates.StyleOverlayEdit
local Overlay = {}
Style.Overlay = Overlay

---Set a value deep in a table by path (creating tables on the way), or with nil clear it and remove
---the tables that become empty.
---@param root table
---@param path string[]
---@param value any
function Overlay.SetIn(root, path, value)
	if value == nil then
		local nodes = { root }
		local node = root
		for i = 1, #path - 1 do
			node = node[path[i]]
			if type(node) ~= 'table' then
				return
			end
			nodes[#nodes + 1] = node
		end
		node[path[#path]] = nil
		for i = #path - 1, 1, -1 do
			if next(nodes[i + 1]) ~= nil then
				break
			end
			nodes[i][path[i]] = nil
		end
		return
	end
	local node = root
	for i = 1, #path - 1 do
		if type(node[path[i]]) ~= 'table' then
			node[path[i]] = {}
		end
		node = node[path[i]]
	end
	node[path[#path]] = value
end

---Change a style's overlay in one write. fn(overlay) edits a copy (Overlay.SetIn on
---{ 'changes', ... }); an overlay left with nothing in it is removed, so "Reset my changes" only
---shows when something is really different.
---@param styleId string
---@param fn fun(overlay: table)
function Overlay.Edit(styleId, fn)
	local id = Registry:ResolveId(styleId)
	local overlay = util.Copy(Store:Get({ 'tweaks', id })) or {}
	fn(overlay)
	if overlay.changes and next(overlay.changes) == nil then
		overlay.changes = nil
	end
	if not (overlay.changes or (overlay.add and next(overlay.add)) or (overlay.remove and next(overlay.remove)) or (overlay.situations and next(overlay.situations))) then
		Store:Set({ 'tweaks', id }, nil)
		return
	end
	local base = Registry:Get(id)
	overlay.schema = overlay.schema or Schema.CURRENT
	overlay.baseVersion = overlay.baseVersion or (base and base.version) or 1
	Store:Set({ 'tweaks', id }, overlay)
end

----------------------------------------------------------------------------------------------------
-- More settings: width, height, bar texture, font face, text size
----------------------------------------------------------------------------------------------------

---Plate width and height for the size picked, with the player's changes.
---@return integer width
---@return integer height
function Style.GetPlateSize()
	local id, sizeKey = Current()
	local resolved = Merge:Resolve(id, 'enemyNPC', sizeKey)
	return resolved.width, resolved.height
end

---@param width? number
---@param height? number
function Style.SetPlateSize(width, height)
	local id, sizeKey = Current()
	local now = Merge:Resolve(id, 'enemyNPC', sizeKey)
	width = math.floor((width or now.width) + 0.5)
	height = math.floor((height or now.height) + 0.5)
	local base = BaseResolved(id, sizeKey)
	local same = base ~= nil and base.width == width and base.height == height
	Overlay.Edit(id, function(overlay)
		Overlay.SetIn(overlay, { 'changes', 'plate', 'sizes', sizeKey }, (not same) and { width, height } or nil)
	end)
end

local FONT_KINDS = { text = true, cast = true, auras = true }
-- Aura rows may give their timer and stack text a size of their own (aura text editor); one left
-- out follows the row's font size
local AURA_TEXT_FIELDS = { 'timerAnchor', 'stackAnchor' }

---Parts that draw text: id list in layout order.
local function FontParts(resolved)
	local out = {}
	for _, partId in ipairs(resolved.order) do
		local spec = resolved.parts[partId]
		if FONT_KINDS[spec.kind] and type(spec.font) == 'table' and type(spec.font.size) == 'number' then
			out[#out + 1] = partId
		end
	end
	return out
end

---The part that stands for "the text size": the name, else the first text.
local function ReferencePart(resolved)
	local first
	for _, partId in ipairs(FontParts(resolved)) do
		local spec = resolved.parts[partId]
		if spec.kind == 'text' and spec.source == 'name' then
			return partId
		end
		first = first or partId
	end
	return first
end

---How much bigger (or smaller) all text is than the style made it, in points.
---@return integer
function Style.GetTextDelta()
	local id, sizeKey = Current()
	local base = BaseResolved(id, sizeKey)
	if not base then
		return 0
	end
	local ref = ReferencePart(base)
	local now = Merge:Resolve(id, 'enemyNPC', sizeKey)
	local part = ref and now.parts[ref]
	if not (part and part.font and type(part.font.size) == 'number') then
		return 0
	end
	return part.font.size - base.parts[ref].font.size
end

Style.TEXT_DELTA_MIN, Style.TEXT_DELTA_MAX = -4, 8
---The part schema's font size range (Schema FONT field).
Style.FONT_MIN, Style.FONT_MAX = 6, 40

---Text sizes the style sets for one kind of plate on its own (Clean makes the names of friendly
---players larger; an aura row's timer or stack text can have its own size). A patch like that is
---applied after the player's changes, so it needs the same change to follow the text size.
---@param styleId string
---@return { kind: string, partId: string, field: string, size: number }[] field: 'font' or an aura text field
local function PatchedSizes(styleId)
	local out = {}
	local base = Registry:Get(styleId)
	for kind, patch in pairs(base and base.situations or {}) do
		for partId, partial in pairs(patch.parts or {}) do
			if type(partial) == 'table' then
				local size = type(partial.font) == 'table' and partial.font.size
				if type(size) == 'number' then
					out[#out + 1] = { kind = kind, partId = partId, field = 'font', size = size }
				end
				for _, field in ipairs(AURA_TEXT_FIELDS) do
					local own = type(partial[field]) == 'table' and partial[field].size
					if type(own) == 'number' then
						out[#out + 1] = { kind = kind, partId = partId, field = field, size = own }
					end
				end
			end
		end
	end
	return out
end

---Make every text part bigger or smaller by the same number of points (0 keeps the style's own
---sizes). Sizes stay inside the part schema's range.
---@param delta number
function Style.SetTextDelta(delta)
	local id, sizeKey = Current()
	local base = BaseResolved(id, sizeKey)
	if not base then
		return
	end
	delta = math.floor(delta + 0.5)
	local function Wanted(size)
		local wanted = math.max(Style.FONT_MIN, math.min(Style.FONT_MAX, size + delta))
		return wanted ~= size and wanted or nil
	end
	Overlay.Edit(id, function(overlay)
		for _, partId in ipairs(FontParts(base)) do
			local spec = base.parts[partId]
			Overlay.SetIn(overlay, { 'changes', 'parts', partId, 'font', 'size' }, Wanted(spec.font.size))
			if spec.kind == 'auras' then
				for _, field in ipairs(AURA_TEXT_FIELDS) do
					-- A size of its own moves with the rest; without one the text follows the row's font
					local own = type(spec[field]) == 'table' and spec[field].size
					Overlay.SetIn(overlay, { 'changes', 'parts', partId, field, 'size' }, type(own) == 'number' and Wanted(own) or nil)
				end
			end
		end
		for _, patched in ipairs(PatchedSizes(id)) do
			Overlay.SetIn(overlay, { 'situations', patched.kind, 'parts', patched.partId, patched.field, 'size' }, Wanted(patched.size))
		end
	end)
end

---The media key for a token value: the value itself when the library knows it, else the key whose
---file it is (the host's font token is a file path).
---@param mediaType string 'statusbar' | 'font'
---@param value any
---@return string|nil
local function MediaKey(mediaType, value)
	local media = P.services.media
	if type(value) ~= 'string' or not media then
		return nil
	end
	if media.IsValid and media:IsValid(mediaType, value) then
		return value
	end
	local list = media.HashTable and media:HashTable(mediaType)
	for key, path in pairs(list or {}) do
		if path == value then
			return key
		end
	end
	return nil
end

---@param name string Token name ('bar' | 'font')
---@return any
function Style.GetToken(name)
	local id, sizeKey = Current()
	return Merge:Resolve(id, 'enemyNPC', sizeKey).tokens[name]
end

---@param name string
---@param value any
function Style.SetToken(name, value)
	local id, sizeKey = Current()
	local base = BaseResolved(id, sizeKey)
	local same = base ~= nil and base.tokens[name] == value
	Overlay.Edit(id, function(overlay)
		Overlay.SetIn(overlay, { 'changes', 'tokens', name }, (not same) and value or nil)
	end)
end

---Values for a media picker: the library's names, with the host's own pictures.
local function MediaValues(mediaType)
	return function()
		local lists = _G.AceGUIWidgetLSMlists
		if lists and lists[mediaType] then
			return lists[mediaType]
		end
		local media = P.services.media
		local out = {}
		if media and media.List then
			for _, key in ipairs(media:List(mediaType)) do
				out[key] = key
			end
		end
		return out
	end
end

---Name of the AceGUI picker widget for a media type when the client has it.
local function PickerWidget(widget)
	local AceGUI = LibStub and LibStub('AceGUI-3.0', true)
	if AceGUI and AceGUI:GetWidgetVersion(widget) then
		return widget
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- Notices and the rename / delete prompts
----------------------------------------------------------------------------------------------------

---@param text string
function Style:Notify(text)
	self.notice = { text = text, time = P.services.GetTime() }
	Options:RequestRefresh(false)
	-- The line goes away by itself: one redraw once it is old enough
	P.Scheduler:Every('StylePage.notice', NOTICE_SECONDS + 0.5, function()
		P.Scheduler:Cancel('StylePage.notice')
		Options:RequestRefresh(false)
	end)
end

---@return string|nil
function Style:NoticeText()
	local notice = self.notice
	if notice and P.services.GetTime() - notice.time < NOTICE_SECONDS then
		return notice.text
	end
	return nil
end

---@param action 'rename'|'delete'|nil
---@param id? string
function Style:Ask(action, id)
	self.pending = action and { action = action, id = id } or nil
	Options:RequestRefresh(false)
end

local function PendingName()
	local pending = Style.pending
	local style = pending and Registry:Get(pending.id)
	return style and style.name or ''
end

---@param page string
---@param optionKey? string|string[] A control of the page, or a path inside it (see SharingPage.FOCUS)
local function OpenPage(page, optionKey)
	local host = P.host
	if host and host.OpenOptions then
		host.OpenOptions(page, optionKey)
	end
end

---An answer from the card menu or a button.
---@param action string 'use' | 'copy' | 'share' | 'rename' | 'delete'
---@param value string Card value
function Style:Do(action, value)
	if action == 'use' then
		if Options.Locked() then
			return self:Notify(Options.LOCKED_REASON)
		end
		Store:Set('style', value)
	elseif action == 'copy' then
		local newId, name = P.Gallery:Copy(value)
		if newId then
			self:Notify(string.format(L['Made "%s". It is in the gallery now.'], name))
		end
	elseif action == 'share' then
		if P.SharingPage then
			P.SharingPage:ShowExport('style', value)
		end
		OpenPage('sharing', P.SharingPage and P.SharingPage.FOCUS.export)
	elseif action == 'rename' then
		self:Ask('rename', value)
	elseif action == 'delete' then
		self:Ask('delete', value)
	end
end

P.Gallery.OnMenuPick = function(action, value)
	Style:Do(action, value)
end

----------------------------------------------------------------------------------------------------
-- The page
----------------------------------------------------------------------------------------------------

---A description that adds the lock reason while changes are restricted.
local function Describe(text)
	return function()
		if Options.Locked() then
			return text .. ' ' .. Options.LOCKED_REASON
		end
		return text
	end
end

Options:AddPage('style', 1, function()
	local getSize, setSize = Options.Bind('size')
	local cardGrid = P.host and P.host.widgets and P.host.widgets.cardGrid
	local gallery = P.Gallery
	local styleOption = {
		type = 'select',
		name = L['Style'],
		desc = Describe(L['How every nameplate looks. Move over a card to see it in the preview. Right-click a card for more.']),
		order = 10,
		width = 'full',
		values = function()
			local values = {}
			for _, card in ipairs(gallery:Cards({ page = true })) do
				values[card.value] = card.title
			end
			return values
		end,
		get = CardValue,
		set = function(_, value)
			Store:Batch(function()
				Store:Set('style', value)
				-- Picking a style on a profile with the plates off means the player wants them
				if Store:Get('enabled') == false then
					Store:Set('enabled', true)
				end
			end)
			if P.Migrate and P.Migrate.FinishMakeover then
				P.Migrate:FinishMakeover()
			end
		end,
		disabled = Options.Locked,
	}
	if cardGrid then
		styleOption.dialogControl = cardGrid
		styleOption.arg = {
			size = 'look',
			cards = function()
				return gallery:Cards({ page = true })
			end,
			onHover = function(value)
				gallery:SetHover(value)
			end,
			onContext = function(value, card)
				gallery:OpenMenu(value, card)
			end,
		}
	end

	local mediaFont, mediaBar = PickerWidget('LSM30_Font'), PickerWidget('LSM30_Statusbar')

	return {
		type = 'group',
		name = L['Style'],
		args = {
			status = {
				type = 'group',
				name = '',
				inline = true,
				order = 1,
				hidden = function()
					return not (Options.Locked() or Style.pending or Style:NoticeText())
				end,
				args = {
					locked = {
						type = 'description',
						name = Options.LOCKED_REASON,
						order = 1,
						fontSize = 'medium',
						hidden = function()
							return not Options.Locked()
						end,
					},
					notice = {
						type = 'description',
						name = function()
							return Style:NoticeText() or ''
						end,
						order = 2,
						fontSize = 'medium',
						hidden = function()
							return Style:NoticeText() == nil
						end,
					},
					rename = {
						type = 'input',
						name = function()
							return string.format(L['New name for "%s"'], PendingName())
						end,
						order = 3,
						width = 'double',
						hidden = function()
							return not (Style.pending and Style.pending.action == 'rename')
						end,
						get = PendingName,
						set = function(_, value)
							local pending = Style.pending
							if not pending then
								return
							end
							local ok, name = gallery:Rename(pending.id, value)
							Style:Ask(nil)
							if ok then
								Style:Notify(string.format(L['Renamed to "%s".'], name))
							end
						end,
					},
					renameCancel = {
						type = 'execute',
						name = L['Cancel'],
						order = 4,
						hidden = function()
							return not (Style.pending and Style.pending.action == 'rename')
						end,
						func = function()
							Style:Ask(nil)
						end,
					},
					deleteAsk = {
						type = 'description',
						name = function()
							return string.format(L['Delete "%s"? You cannot get it back.'], PendingName())
						end,
						order = 5,
						fontSize = 'medium',
						hidden = function()
							return not (Style.pending and Style.pending.action == 'delete')
						end,
					},
					deleteYes = {
						type = 'execute',
						name = L['Delete it'],
						order = 6,
						hidden = function()
							return not (Style.pending and Style.pending.action == 'delete')
						end,
						disabled = function()
							local pending = Style.pending
							return Options.Locked() and pending ~= nil and Store:Get('style') == pending.id
						end,
						func = function()
							local pending = Style.pending
							if not pending then
								return
							end
							local name = PendingName()
							gallery:Delete(pending.id)
							Style:Ask(nil)
							Style:Notify(string.format(L['Deleted "%s".'], name))
						end,
					},
					deleteNo = {
						type = 'execute',
						name = L['Keep it'],
						order = 7,
						hidden = function()
							return not (Style.pending and Style.pending.action == 'delete')
						end,
						func = function()
							Style:Ask(nil)
						end,
					},
				},
			},
			style = styleOption,
			size = {
				type = 'select',
				name = L['Size'],
				desc = Describe(L['Plates get bigger or smaller in whole pixels, so borders stay sharp.']),
				order = 20,
				values = SIZES,
				sorting = { 'small', 'medium', 'large' },
				get = getSize,
				set = setSize,
				disabled = Options.Locked,
			},
			customize = {
				type = 'execute',
				name = L['Customize this style'],
				desc = L['Pick a part of the plate and change how it looks.'],
				order = 30,
				primary = true,
				func = function()
					OpenPage('customize')
				end,
			},
			undo = {
				type = 'execute',
				name = L['Reset my changes'],
				desc = Describe(L['Go back to the style as it was made. Your other settings stay.']),
				confirm = true,
				confirmText = L['Remove all your changes to this style?'],
				order = 31,
				hidden = function()
					return not Merge:HasChanges(Store:Get('style'))
				end,
				disabled = Options.Locked,
				func = function()
					Store:Set({ 'tweaks', (Current()) }, nil)
				end,
			},
			copy = {
				type = 'execute',
				name = L['Make a copy'],
				desc = Describe(L['Saves this style, with your changes, as a new style of your own. You use the copy right away.']),
				order = 32,
				disabled = Options.Locked,
				func = function()
					local newId, name = gallery:Copy(Store:Get('style'))
					if newId then
						Store:Set('style', newId)
						Style:Notify(string.format(L['Made "%s". You are using it now.'], name))
					end
				end,
			},
			share = {
				type = 'execute',
				name = L['Share'],
				desc = L['Make a text you can send to other players. It holds this style with your changes.'],
				order = 33,
				func = function()
					Style:Do('share', Store:Get('style'))
				end,
			},
			import = {
				type = 'execute',
				name = L['Import'],
				desc = L['Paste a text from another player to add their style, colors or settings.'],
				order = 34,
				func = function()
					OpenPage('sharing', P.SharingPage and P.SharingPage.FOCUS.import)
				end,
			},
			width = {
				type = 'range',
				name = L['Plate width'],
				desc = Describe(L['How wide the bar is, in pixels. This is for the size you picked above.']),
				order = 40,
				advanced = true,
				min = 20,
				max = 400,
				step = 1,
				get = function()
					return (Style.GetPlateSize())
				end,
				set = function(_, value)
					Style.SetPlateSize(value, nil)
				end,
				disabled = Options.Locked,
			},
			height = {
				type = 'range',
				name = L['Plate height'],
				desc = Describe(L['How tall the bar is, in pixels. This is for the size you picked above.']),
				order = 41,
				advanced = true,
				min = 2,
				max = 80,
				step = 1,
				get = function()
					local _, height = Style.GetPlateSize()
					return height
				end,
				set = function(_, value)
					Style.SetPlateSize(nil, value)
				end,
				disabled = Options.Locked,
			},
			barTexture = {
				type = 'select',
				name = L['Bar texture'],
				desc = Describe(L['The look of the fill in health bars and cast bars.']),
				order = 42,
				advanced = true,
				dialogControl = mediaBar,
				values = MediaValues('statusbar'),
				get = function()
					return MediaKey('statusbar', Style.GetToken('bar'))
				end,
				set = function(_, value)
					Style.SetToken('bar', value)
				end,
				disabled = Options.Locked,
			},
			font = {
				type = 'select',
				name = L['Font'],
				desc = Describe(L['The font for the text on your plates. Each name is drawn in its own font.']),
				order = 43,
				advanced = true,
				dialogControl = mediaFont,
				values = MediaValues('font'),
				get = function()
					return MediaKey('font', Style.GetToken('font'))
				end,
				set = function(_, value)
					Style.SetToken('font', value)
				end,
				disabled = Options.Locked,
			},
			textSize = {
				type = 'range',
				name = L['All text size'],
				desc = Describe(L['Makes all the text on your plates bigger or smaller together. 0 keeps the sizes the style was made with. To change one part, use Customize.']),
				order = 44,
				advanced = true,
				min = Style.TEXT_DELTA_MIN,
				max = Style.TEXT_DELTA_MAX,
				step = 1,
				get = Style.GetTextDelta,
				set = function(_, value)
					Style.SetTextDelta(value)
				end,
				disabled = Options.Locked,
			},
		},
	}
end)
