local _, ns = ...
local P = ns.Plates
local L = P.L

-- The options preview for the host's side-panel Stage (3.2, 5.6). P:BuildPreviewProvider() makes
-- the provider; the host registers it (host.RegisterPreview, or its own Stage call) next to the
-- options root. The Stage contract is the host's (its Stage file header); the fields used here:
--   path = Options.Path() (the Nameplates root), zoomable, refit (the scenes fit themselves to the
--   canvas), overlapPicker (right-click lists every part under the cursor)
--   GetHeight, Render, Hide, Close, Title, Hint, Toolbar, Action (the eye toggle "Show all parts"),
--   Footer ("Undo move" on Customize), width (Enlarge on Customize, only the room there is)
-- Every drawn part registers a click area with ctx.Region(frame, target), large parts first:
--   label  part name ("Spell icon"); aura rows add "sample icons"
--   detail the inspector line ("Red: Threat (you are not tanking)") or why the part may stay empty
--   path   the page that changes it (Customize for parts, Colors for rows, Who and where for kinds)
-- Scenes by page (P.Scenes): Style, Sharing and Colors without an open list show the scene picker
-- (Pull, Raid boss, Battleground, Out in the world); Customize shows Focus with "Preview as" and
-- Enlarge in the toolbar; Auras shows Focus with every aura row filled; Colors with a list open
-- shows Rows; Who and where shows Kinds. Preview plates are unbound (sample casts stop) when the
-- panel hides or the window closes.
--
-- Other parts of the module this file talks to (each feature-detected):
--   Gallery (UI/Gallery.lua): on the Style and Sharing pages every plate asks
--     Gallery:ResolveShown(situation, sizeKey) for the hovered card's or the pasted style;
--     GALLERY_HOVER and GALLERY_PREVIEW redraw the panel; Gallery:ClearPreview() when it hides.
--   Designer (UI/Designer.lua, .context/nameplates.md section 12): on Customize the large plate's
--     click areas, selection, drag, nudge and keys belong to Designer:Attach(ctx, plate) (after the
--     small plates registered theirs) and Designer:Detach(); the panel title, hint, footer and extra
--     toolbar items come from Designer:Title/Hint/Footer/ToolbarItems; "Preview as" reads and
--     writes Designer:PreviewKind/SetPreviewKind; the edited style is Designer:StyleId().
--     Without those hooks the provider registers the large plate itself with a plain drag
--     (Preview.FallbackDrag: move on screen, pick the anchor on drop with Designer.DropAnchor,
--     nudge, Delete hides the part, Ctrl-Z undoes) and keeps the kind and selection in P.Preview.
--
-- P.Preview is the state other pages talk to (session only):
--   Preview:SetColorList(piece|nil) the color list open on the Colors page (rows scene); a page
--                                   group whose key names the piece (health, border, name, cast)
--                                   is found from the path without this call
--   Preview:SetPreviewAs(kind), GetPreviewAs(), SetScene(id), GetSelected(), Select(partId)
--   Preview.PartLabel(spec, id) -> label, group   plain part names for titles and lists
--   Preview:RequestRedraw()         host.RedrawPreview when the host has it, else an options refresh

---@class Plates.Preview
local Preview = {
	kind = 'enemyNPC',
	scene = 'pull',
	enlarge = false,
	selected = nil,
	colorPiece = nil,
}
P.Preview = Preview

Preview.STANDARD_WIDTH = 340
Preview.WIDE_WIDTH = 560
-- Enlarge needs a bit more than the standard panel to be worth it
Preview.MIN_ENLARGE_ROOM = 380
Preview.FOOTER_ROOM = 30

----------------------------------------------------------------------------------------------------
-- Part names
----------------------------------------------------------------------------------------------------

local TEXT_LABELS = {
	name = L['Name'],
	nameFill = L['Name'],
	level = L['Level'],
	healthPercent = L['Health text'],
	healthValue = L['Health text'],
	forces = L['Mythic+ forces'],
	title = L['Title'],
	threatPercent = L['Threat percent'],
	threatLead = L['Threat lead'],
	castName = L['Spell name'],
	castTime = L['Cast time'],
	castTarget = L['Cast target'],
	arena = L['Arena number'],
	specName = L['Player spec'],
}
local ICON_LABELS = {
	raidMarker = L['Raid marker'],
	classification = L['Classification icon'],
	quest = L['Quest icon'],
	faction = L['Faction mark'],
	focus = L['Focus mark'],
	shield = L['Cast shield'],
	specIcon = L['Player spec icon'],
	roleIcon = L['Role icon'],
	totem = L['Totem icon'],
}
local AURA_LABELS = {
	myDebuffs = L['My debuffs'],
	removable = L['Enemy buffs'],
	crowdControl = L['Crowd control'],
	custom = L['Always shown auras'],
}
local GLOW_LABELS = {
	threat = L['Threat glow'],
	importantCast = L['Important cast glow'],
	purge = L['Purge glow'],
	pandemic = L['Refresh glow'],
	target = L['Target glow'],
}
local HIGHLIGHT_LABELS = {
	target = L['Target highlight'],
	focus = L['Focus highlight'],
	mouseover = L['Mouseover highlight'],
}
local GROUPS = {
	bar = L['Bar'],
	text = L['Text'],
	cast = L['Cast'],
	auras = L['Auras'],
	icon = L['Icons'],
	highlight = L['Emphasis'],
	glow = L['Emphasis'],
	art = L['Art'],
	region = L['Areas'],
	classPower = L['Bar'],
}

---Plain name and group of a style part ("Spell icon", "Cast").
---@param spec table
---@param id? string Part id, the last resort
---@return string label
---@return string group
function Preview.PartLabel(spec, id)
	spec = spec or {}
	local kind = spec.kind
	local label
	if kind == 'bar' then
		label = spec.source == 'power' and L['Power bar'] or L['Health bar']
	elseif kind == 'cast' then
		label = L['Cast bar']
	elseif kind == 'text' then
		label = TEXT_LABELS[spec.source]
	elseif kind == 'icon' then
		label = ICON_LABELS[spec.source]
	elseif kind == 'auras' then
		label = AURA_LABELS[spec.row]
	elseif kind == 'glow' then
		label = GLOW_LABELS[spec.source]
	elseif kind == 'highlight' then
		label = HIGHLIGHT_LABELS[spec.state or 'target']
	elseif kind == 'classPower' then
		label = L['Class power']
	elseif kind == 'region' then
		label = P.Regions and P.Regions.LABELS[spec.region or 'click']
	elseif kind == 'art' then
		label = L['Art']
	end
	return label or tostring(id or kind or '?'), GROUPS[kind] or L['Parts']
end

----------------------------------------------------------------------------------------------------
-- State other pages talk to
----------------------------------------------------------------------------------------------------

---The Designer, when it has the hook named.
---@param name string
---@return table|nil
local function DesignerWith(name)
	local Designer = P.Designer
	if Designer and type(Designer[name]) == 'function' then
		return Designer
	end
	return nil
end

---Ask the host to draw the panel again (next frame at the latest).
function Preview:RequestRedraw()
	local host = P.host
	if host and host.RedrawPreview then
		host.RedrawPreview()
	elseif P.Options and P.Options.RequestRefresh then
		P.Options:RequestRefresh(false)
	end
end

---The color list open on the Colors page (nil: the list is closed).
---@param piece string|nil
function Preview:SetColorList(piece)
	if self.colorPiece ~= piece then
		self.colorPiece = piece
		self:RequestRedraw()
	end
end

---"Preview as" (Customize and Auras).
---@param kind string enemyNPC | enemyPlayer | friendlyNPC | friendlyPlayer | minor
function Preview:SetPreviewAs(kind)
	if not P.Scenes.KIND_LABELS[kind] then
		return
	end
	local Designer = DesignerWith('SetPreviewKind')
	if Designer then
		Designer:SetPreviewKind(kind)
	end
	if self.kind ~= kind then
		self.kind = kind
		self:RequestRedraw()
	end
end

---@return string
function Preview:GetPreviewAs()
	local Designer = DesignerWith('PreviewKind')
	local kind = Designer and Designer:PreviewKind()
	if kind and P.Scenes.KIND_LABELS[kind] then
		return kind
	end
	return self.kind
end

---@param id string A scene in P.Scenes.PICKER
function Preview:SetScene(id)
	if P.Scenes.DEFS[id] and P.Scenes.DEFS[id].picker and self.scene ~= id then
		self.scene = id
		self:RequestRedraw()
	end
end

---The selected part on Customize (the primary one when several are selected).
---@return string|nil
function Preview:GetSelected()
	local Designer = DesignerWith('Primary')
	if Designer then
		return Designer:Primary()
	end
	Designer = DesignerWith('GetSelected')
	if Designer then
		return Designer:GetSelected()
	end
	return self.selected
end

---Select a part on Customize (nil clears).
---@param partId string|nil
function Preview:Select(partId)
	local Designer = DesignerWith('Select')
	if Designer then
		if partId == nil and Designer.ClearSelection then
			Designer:ClearSelection()
		else
			Designer:Select(partId)
		end
		return
	end
	if self.selected ~= partId then
		self.selected = partId
		-- The Customize page shows only the selected part's settings
		if P.Options and P.Options.RequestRefresh then
			P.Options:RequestRefresh(true)
		end
	end
end

---The style the Customize page edits.
---@return string
function Preview:EditStyleId()
	local Designer = DesignerWith('StyleId')
	local id = Designer and Designer:StyleId()
	if id then
		return id
	end
	local style = P.db and P.Store:Get('style') or 'host'
	return P.Styles.Registry:ResolveId(style)
end

----------------------------------------------------------------------------------------------------
-- Pages
----------------------------------------------------------------------------------------------------

---Page id of an options path ('style', 'customize', ...; nil for the root).
---@param path string[]
---@return string|nil
function Preview.PageOf(path)
	local root = P.Options.Path()
	local page = path and path[#root + 1] or nil
	if page ~= 'customize' then
		local Designer = DesignerWith('IsCustomizePath')
		if Designer and path and Designer:IsCustomizePath(path) then
			return 'customize'
		end
	end
	return page
end

---The color piece the Colors page has open, from Preview:SetColorList or the path.
---@param path string[]
---@return string|nil
function Preview:ColorPieceFor(path)
	if self.colorPiece then
		return self.colorPiece
	end
	local root = P.Options.Path()
	for i = #root + 2, #(path or {}) do
		local key = type(path[i]) == 'string' and path[i]:lower() or ''
		for _, piece in ipairs(P.Colors.PIECES) do
			if key == piece or key:find(piece, 1, true) then
				return piece
			end
		end
	end
	return nil
end

-- Pages where the gallery's hovered card or the pasted style is drawn
local GALLERY_PAGES = { style = true, sharing = true }

---Scene id and options for a page.
---@param page string|nil
---@param path string[]
---@return string sceneId
---@return table opts
function Preview:SceneFor(page, path)
	local opts = { revealAll = P.Regions and P.Regions:IsShowingAll() or false }
	if page == 'customize' or page == 'auras' then
		opts.kind = self:GetPreviewAs()
		opts.focusStyleId = self:EditStyleId()
		return page == 'customize' and 'focus' or 'auras', opts
	elseif page == 'whoAndWhere' then
		return 'kinds', opts
	elseif page == 'colors' then
		local piece = self:ColorPieceFor(path)
		if piece then
			opts.piece = piece
			return 'rows', opts
		end
	end
	if GALLERY_PAGES[page] and P.Gallery and P.Gallery.ResolveShown then
		opts.resolveShown = function(situation, sizeKey)
			return P.Gallery:ResolveShown(situation, sizeKey)
		end
	end
	return self.scene or 'pull', opts
end

---Whether the page shows the scene picker.
---@param page string|nil
---@param path string[]
---@return boolean
function Preview:HasPicker(page, path)
	if page == nil or GALLERY_PAGES[page] then
		return true
	end
	return page == 'colors' and self:ColorPieceFor(path) == nil
end

----------------------------------------------------------------------------------------------------
-- Moving parts without the Designer's own handlers
----------------------------------------------------------------------------------------------------

local OVERLAY_KINDS = { highlight = true, glow = true }

---@param spec table
---@return boolean
local function Movable(spec)
	if not spec or OVERLAY_KINDS[spec.kind] or spec.fill == 'plate' then
		return false
	end
	if spec.kind == 'region' and not (spec.width and spec.height) then
		return false
	end
	return type(spec.anchor) == 'table'
end

local function Half(v)
	return math.floor(v * 2 + 0.5) / 2
end

---Region a part's anchor names on this plate.
local function RelRegion(plate, name)
	if not name or name == 'plate' then
		return plate.art
	end
	local widget = plate:GetWidget(name)
	return widget and (widget.anchor or widget.frame) or plate.art
end

---Parts that hang (directly or through others) from a part: never an anchor target for it.
local function Dependents(parts, id)
	local out = { [id] = true }
	local grew = true
	while grew do
		grew = false
		for partId, spec in pairs(parts) do
			local anchor = spec.anchor
			if not out[partId] and type(anchor) == 'table' and out[anchor[2]] then
				out[partId] = true
				grew = true
			end
		end
	end
	return out
end

---Remember the overlay for undo, then run the edit.
local function Edit(styleId, label, fn)
	local Designer = P.Designer
	if Designer and type(Designer.Edit) == 'function' then
		Designer:Edit(label, fn)
		return
	end
	if Designer and type(Designer.Push) == 'function' then
		Designer:Push(styleId)
	end
	fn()
end

---Write a part's new anchor to the style's overlay (one undo step).
local function Commit(styleId, partId, anchor)
	Edit(styleId, L['Move'], function()
		P.Store:Set({ 'tweaks', styleId, 'changes', 'parts', partId, 'anchor' }, anchor)
	end)
end

---A plain drag for a part on the large Customize plate.
---@param plate Plates.Plate
---@param widget Plates.Widget
---@param resolved Plates.ResolvedStyle
---@return table drag
function Preview.FallbackDrag(plate, widget, resolved)
	local id, styleId = widget.id, resolved.id
	local start
	local drag = {}
	function drag.Start()
		start = P.util.Copy(widget.spec.anchor)
	end
	function drag.Move(dx, dy)
		if not start then
			return
		end
		local frame = widget.frame
		frame:ClearAllPoints()
		frame:SetPoint(start[1], RelRegion(plate, start[2]), start[3] or start[1], (start[4] or 0) + dx, (start[5] or 0) + dy)
	end
	function drag.Stop(dx, dy)
		start = nil
		if math.abs(dx) < 0.25 and math.abs(dy) < 0.25 then
			plate:Layout()
			return
		end
		local rects = P.Styles.Merge.PartRects(resolved)
		local r = rects[id]
		if not r then
			return
		end
		local dropped = { left = r.left + dx, right = r.right + dx, top = r.top + dy, bottom = r.bottom + dy }
		local skip = Dependents(resolved.parts, id)
		local targets = {}
		for partId, rect in pairs(rects) do
			if not skip[partId] then
				targets[partId] = rect
			end
		end
		Commit(styleId, id, P.Designer.DropAnchor(dropped, targets))
	end
	function drag.Nudge(dx, dy)
		-- The overlay's anchor wins over the drawn one: several nudges can land before a redraw
		local stored = P.Store:Get({ 'tweaks', styleId, 'changes', 'parts', id, 'anchor' })
		local anchor = P.util.Copy(type(stored) == 'table' and stored or widget.spec.anchor)
		anchor[3] = anchor[3] or anchor[1]
		anchor[4] = Half((anchor[4] or 0) + dx)
		anchor[5] = Half((anchor[5] or 0) + dy)
		Commit(styleId, id, anchor)
	end
	function drag.Key(key)
		if key == 'DELETE' then
			Edit(styleId, L['Hide'], function()
				P.Store:Set({ 'tweaks', styleId, 'remove', id }, true)
			end)
			Preview:Select(nil)
			return true
		elseif key == 'CTRL-Z' then
			Preview:Undo()
			return true
		end
		return false
	end
	return drag
end

---@return boolean
function Preview:CanUndo()
	local Designer = P.Designer
	if not Designer then
		return false
	end
	if type(Designer.CanUndo) == 'function' then
		return Designer:CanUndo() and true or false
	end
	return type(Designer.undo) == 'table' and #Designer.undo > 0
end

function Preview:Undo()
	local Designer = DesignerWith('Undo')
	if Designer then
		Designer:Undo()
	end
end

---Where a click on a part goes.
---@return string[] path
---@return string|nil option
local function PartPath(widget)
	local Designer = DesignerWith('PartPath')
	if Designer then
		local path, option = Designer:PartPath(widget.id, widget.spec)
		if path then
			return path, option
		end
	end
	return P.Options.Path('customize'), nil
end

----------------------------------------------------------------------------------------------------
-- Click areas
----------------------------------------------------------------------------------------------------

local function Area(rect, scale)
	if not rect then
		return 0
	end
	return (rect.right - rect.left) * (rect.top - rect.bottom) * scale * scale
end

---Every click area for one plate, largest first.
---@param ctx table Stage context
---@param item Plates.SceneItem
---@param page string|nil
---@param scene Plates.SceneResult
---@param selected string|nil
local function PlateRegions(ctx, item, page, scene, selected)
	local plate = item.plate
	local resolved = plate.style
	local rects = P.Styles.Merge.PartRects(resolved)
	local list = {}
	for i = 1, #plate.active do
		local widget = plate.active[i]
		if widget.frame and widget.frame:IsShown() then
			list[#list + 1] = { widget = widget, area = Area(rects[widget.id], item.scale) }
		end
	end
	table.sort(list, function(a, b)
		if a.area ~= b.area then
			return a.area > b.area
		end
		return a.widget.id < b.widget.id
	end)
	local Inspector = P.Inspector
	local movable = page == 'customize' and item.focus
	for _, entry in ipairs(list) do
		local widget = entry.widget
		local spec = widget.spec
		local label = Preview.PartLabel(spec, widget.id)
		if spec.kind == 'auras' then
			label = label .. ' - ' .. P.Scenes.LABEL_SAMPLE_ICONS
		end
		local target = { label = label, selected = false }
		target.detail = function()
			return Inspector:Detail(plate, widget)
		end
		if page == 'whoAndWhere' and item.kind then
			target.path, target.option = P.Options.Path('whoAndWhere'), item.kind
			target.label = P.Scenes.KIND_LABELS[item.kind] .. ': ' .. label
		elseif page == 'colors' and scene.id == 'rows' and Inspector:PieceOf(spec) then
			-- Already on the list this plate shows: stay
			target.onClick = function()
				return true
			end
		elseif page == 'auras' and spec.kind == 'auras' then
			target.path, target.option = P.Options.Path('auras'), spec.row
		else
			target.path, target.option = PartPath(widget)
			target.onClick = function()
				Preview:Select(widget.id)
			end
			if movable then
				target.selected = widget.id == selected
				if Movable(spec) then
					target.drag = Preview.FallbackDrag(plate, widget, resolved)
				end
			end
		end
		ctx.Region(widget.frame, target)
	end
end

---Click and stacking boxes drawn by "Show all parts" (Who and where holds their padding).
local function BoxRegions(ctx, item)
	local Regions = P.Regions
	local boxes = Regions and Regions.boxes and Regions.boxes[item.plate]
	if not boxes then
		return
	end
	for _, which in ipairs(Regions.KINDS) do
		local box = boxes[which]
		if box and box:IsShown() then
			ctx.Region(box, { label = Regions.LABELS[which], path = P.Options.Path('whoAndWhere'), selected = false })
		end
	end
end

----------------------------------------------------------------------------------------------------
-- The provider
----------------------------------------------------------------------------------------------------

local function KindChoices()
	local choices = {}
	for _, kind in ipairs(P.Scenes.KINDS) do
		choices[#choices + 1] = { value = kind, text = P.Scenes.KIND_LABELS[kind] }
	end
	return choices
end

local function SceneChoices()
	local choices = {}
	for _, id in ipairs(P.Scenes.PICKER) do
		choices[#choices + 1] = { value = id, text = P.Scenes.DEFS[id].label }
	end
	return choices
end

local function Detach()
	local Designer = DesignerWith('Detach')
	if Designer then
		pcall(Designer.Detach, Designer)
	end
end

---The Stage provider for the nameplate pages (nil when the module is missing a piece).
---@return table|nil provider
function P:BuildPreviewProvider()
	if not (P.Options and P.Scenes and P.Plate) then
		return nil
	end
	local provider = { path = P.Options.Path(), zoomable = true, refit = true, overlapPicker = true }

	function provider:GetHeight()
		return P.db and 1 or 0
	end

	function provider.width(_, ctx)
		local page = Preview.PageOf(ctx.path)
		if page == 'customize' and Preview.enlarge and (ctx.maxWidth or 0) >= Preview.MIN_ENLARGE_ROOM then
			return math.min(Preview.WIDE_WIDTH, ctx.maxWidth)
		end
		return nil
	end

	function provider:Title(ctx)
		if Preview.PageOf(ctx.path) ~= 'customize' then
			return nil
		end
		local Designer = DesignerWith('Title')
		if Designer then
			return Designer:Title(ctx)
		end
		local selected = Preview:GetSelected()
		if selected then
			local size = P.db and P.Store:Get('size') or 'medium'
			local ok, resolved = pcall(P.Styles.Merge.Resolve, P.Styles.Merge, Preview:EditStyleId(), Preview:GetPreviewAs(), size)
			local spec = ok and resolved and resolved.parts[selected]
			if spec then
				local label, group = Preview.PartLabel(spec, selected)
				return group .. ': ' .. label
			end
		end
		return nil
	end

	function provider:Hint(ctx)
		local page = Preview.PageOf(ctx.path)
		if page == 'customize' then
			local Designer = DesignerWith('Hint')
			if Designer then
				return Designer:Hint(ctx)
			end
			if Preview:GetSelected() then
				return L['Drag to move it, or nudge with the arrow keys. Ctrl-Z undoes it.']
			end
			return L['Click a part to change it']
		elseif page == 'auras' then
			return L['Sample icons. Click a row to change it.']
		elseif page == 'whoAndWhere' then
			return L['Each kind of plate in its style. Click one to change it.']
		elseif page == 'colors' and Preview:ColorPieceFor(ctx.path) then
			return L['One plate per color, top row first.']
		end
		return nil
	end

	function provider:Toolbar(ctx)
		local page = Preview.PageOf(ctx.path)
		if page == 'customize' then
			local room = (ctx.maxWidth or 0) >= Preview.MIN_ENLARGE_ROOM
			local items = {
				{
					kind = 'select',
					label = L['Show'],
					value = Preview:GetPreviewAs(),
					choices = KindChoices(),
					onSelect = function(value)
						Preview:SetPreviewAs(value)
					end,
					tooltip = L['Pick which kind of plate the preview shows. Your changes still go to the whole style.'],
				},
				{
					kind = 'toggle',
					text = L['Enlarge'],
					align = 'right',
					active = Preview.enlarge and room,
					disabled = not room,
					disabledReason = L['There is no room beside the settings window. Move the window to make room.'],
					tooltip = L['Make the preview wider. Your settings window does not move.'],
					onClick = function()
						Preview.enlarge = not Preview.enlarge
					end,
				},
			}
			local Designer = DesignerWith('ToolbarItems')
			local extra = Designer and Designer:ToolbarItems(ctx)
			for _, item in ipairs(type(extra) == 'table' and extra or {}) do
				items[#items + 1] = item
			end
			return items
		end
		if Preview:HasPicker(page, ctx.path) then
			return {
				{
					kind = 'select',
					label = L['Scene'],
					value = Preview.scene,
					choices = SceneChoices(),
					onSelect = function(value)
						Preview:SetScene(value)
					end,
					tooltip = L['Pick what the preview shows: a pull, a raid boss, a battleground or the open world.'],
				},
			}
		end
		return nil
	end

	function provider:Action()
		local Regions = P.Regions
		if not Regions then
			return nil
		end
		return {
			text = L['Show all parts'],
			tooltip = L['Show parts that are usually hidden, plus the click and stacking areas. Plates in the world show their areas too while this is on.'],
			active = Regions:IsShowingAll(),
			func = function()
				Regions:SetShowAll(not Regions:IsShowingAll())
			end,
		}
	end

	function provider:Footer(ctx)
		if Preview.PageOf(ctx.path) ~= 'customize' then
			return nil
		end
		local Designer = DesignerWith('Footer')
		if Designer then
			return Designer:Footer(ctx)
		end
		if Preview:CanUndo() then
			return {
				text = L['Undo move'],
				tooltip = L['Put the last part you moved back where it was.'],
				func = function()
					Preview:Undo()
				end,
			}
		end
		return nil
	end

	function provider:Render(ctx)
		local canvas = ctx.canvas
		Preview.canvas = canvas
		local page = Preview.PageOf(ctx.path)
		local sceneId, opts = Preview:SceneFor(page, ctx.path)
		local w, h = canvas:GetSize()
		opts.width = P.Secret.Plain(w) or 338
		opts.height = P.Secret.Plain(h) or 416
		if page == 'customize' and (self:Footer(ctx) ~= nil) then
			opts.height = opts.height - Preview.FOOTER_ROOM
		end
		local ok, scene = pcall(P.Scenes.Render, P.Scenes, canvas, sceneId, opts)
		if not ok then
			P.log.error('Nameplate preview failed: ' .. tostring(scene))
			return
		end
		Preview.lastScene, Preview.lastPage = scene, page
		local attach = page == 'customize' and DesignerWith('Attach') or nil
		local selected = page == 'customize' and Preview:GetSelected() or nil
		local focusPlate
		for _, item in ipairs(scene.items) do
			if item.plate then
				BoxRegions(ctx, item)
			end
		end
		for _, item in ipairs(scene.items) do
			if item.plate then
				if attach and item.focus then
					focusPlate = item.plate
				else
					PlateRegions(ctx, item, page, scene, selected)
				end
			elseif item.outline then
				local label = item.kind and P.Scenes.KIND_LABELS[item.kind] or item.sample.label or ''
				ctx.Region(item.outline, {
					label = label .. ': ' .. L['Hidden'],
					detail = L['These plates are hidden. Pick Full or Names only to show them.'],
					path = P.Options.Path('whoAndWhere'),
					option = item.kind,
					selected = false,
				})
			end
		end
		if attach and focusPlate then
			-- The Designer owns the large plate's click areas, selection and drag
			local attached, err = pcall(attach.Attach, attach, ctx, focusPlate)
			if not attached then
				P.log.error('Nameplate designer failed: ' .. tostring(err))
			end
		end
	end

	function provider:Hide()
		Preview.lastScene = nil
		Detach()
		if P.Gallery and P.Gallery.ClearPreview then
			P.Gallery:ClearPreview()
		end
		if Preview.canvas then
			P.Scenes:Release(Preview.canvas)
		end
	end

	function provider:Close()
		self:Hide()
		Preview.lastScene = nil
	end

	Preview.provider = provider
	return provider
end

-- Changes that come from outside the panel: the eye toggle from a command, a hovered gallery card,
-- a pasted style
local function RedrawShown()
	if Preview.lastScene then
		Preview:RequestRedraw()
	end
end
P:On('REGION_BOXES_CHANGED', RedrawShown, Preview)
P:On('GALLERY_HOVER', RedrawShown, Preview)
P:On('GALLERY_PREVIEW', RedrawShown, Preview)
