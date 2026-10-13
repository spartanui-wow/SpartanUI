local _, ns = ...
local P = ns.Plates
local L = P.L

-- Style gallery (3.4) for the host's card grid widget (host.widgets.cardGrid) on the Style page,
-- and for the setup look step.
--
-- Cards: P.Gallery:Cards() returns card-grid cards (value, title, caption, tag, recommended, art).
-- Match my look is first. On Era, TBC and Forever (Gallery.SUGGEST_BORDERED) Bordered follows it,
-- tagged "Suggested", because players there remember the old framed plates.
-- Each card's picture is drawn by the real renderer: a few preview plates (Plate.New(parent, true))
-- fed by SampleSource, so a card shows the player's own changes and the host's theme look. The
-- picture comes through LibAT's card art hook (LibAT.Capabilities.cardArtDraw, feature-detected):
-- art.draw(holder, data, card, width, height, state) and art.release(holder, data, card). Without
-- the hook a card shows its name and a one-line description. Plates are pooled per holder frame
-- (the grid reuses its cards), redrawn in place, and parked (unbound, no timers) when the card
-- hides or is reused.
--
-- Hover to try: the card grid calls arg.onHover(value) / arg.onHover(nil). P.Gallery:SetHover
-- remembers it and fires GALLERY_HOVER(value). A pasted style that is waiting on the Sharing page
-- is P.Gallery:SetPreview(info) / GALLERY_PREVIEW(info). The preview panel's Pull scene asks
-- P.Gallery:ResolveShown(situation, sizeKey) which style to draw: the pasted one, else the hovered
-- card's, else nil (draw the current style), and redraws on those two messages. The provider should
-- call P.Gallery:ClearPreview() when the panel hides.
--
-- Right-click on a card (arg.onContext(value, card)) opens a small menu: Use, Make a copy, Share,
-- and for the player's own styles Rename and Delete. The page that owns the menu answers picks
-- through P.Gallery.OnMenuPick(action, value).

---@class Plates.Gallery
local Gallery = {
	hover = nil,
	preview = nil,
	views = setmetatable({}, { __mode = 'k' }),
	previewCache = {},
	previewCount = 0,
}
P.Gallery = Gallery

local Registry = P.Styles.Registry
local Merge = P.Styles.Merge

---The card value the pasted style uses on the Sharing page's one-card grid.
Gallery.PREVIEW_VALUE = '@import'

---Samples a card shows, best first: your elite target mid-cast with arrows, a mini-boss casting
---something you cannot interrupt, a friendly name. Fewer are drawn when the picture is small.
Gallery.THUMB_SETS = {
	{ 'casterTarget', 'eliteMiniBoss', 'friendlyPlayer' },
	{ 'casterTarget', 'friendlyPlayer' },
	{ 'casterTarget' },
}
Gallery.THUMB_MIN_SCALE = 0.7
Gallery.THUMB_PAD = 4
Gallery.THUMB_GAP = 5

local SIZE_KEYS = { small = true, medium = true, large = true }

---Games where players remember the old framed plates. Bordered is suggested first there: it is the
---card right after "Match my look" and carries a "Suggested" tag (a presentation rule, not a
---capability).
Gallery.SUGGEST_BORDERED = { era = true, tbc = true, forever = true }

local function Trim(text)
	return (string.gsub(string.gsub(text or '', '^%s+', ''), '%s+$', ''))
end

---A name safe to show: no pipes (the game reads them as color, link and texture codes), no control
---characters, trimmed.
---@param text any
---@return string
function Gallery.CleanName(text)
	if type(text) ~= 'string' then
		return ''
	end
	text = string.gsub(text, '|', '')
	text = string.gsub(text, '%c', ' ')
	return Trim(text)
end

----------------------------------------------------------------------------------------------------
-- Cards
----------------------------------------------------------------------------------------------------

---True when the host's card grid can draw live pictures (LibAT's art.draw hook).
---@return boolean
function Gallery:CanDraw()
	local caps = LibAT and LibAT.Capabilities
	local level = caps and caps.cardArtDraw
	return level ~= nil and level ~= false and P.Plate ~= nil and P.Source ~= nil
end

---The caption under a card's title.
---@param item Plates.StyleListItem
---@return string
function Gallery:Caption(item)
	if item.matchesHost then
		return string.format(L['Follows the look of your %s theme.'], P:HostName())
	end
	if item.source == 'saved' then
		local entry = P.Store:Get({ 'styles', item.id }, 'global')
		local source = type(entry) == 'table' and entry.source or nil
		if source and source.kind == 'import' then
			if source.author and source.author ~= '' then
				return string.format(L['By %s. Version %s.'], source.author, tostring(source.version or 1))
			end
			return L['A style you imported.']
		end
		return L['A style you made.']
	end
	return item.description or ''
end

---The style this game suggests first, or nil.
---@return string|nil styleId
function Gallery:SuggestedStyle()
	if self.SUGGEST_BORDERED[P.Caps:Client()] and Registry:Get('bordered') then
		return 'bordered'
	end
	return nil
end

---Card data for every style the player can pick (internal styles left out). The host style
---(matchesHost) is the "Match my look" card with value 'host'.
---@param opts? { page?: boolean } page = true is the settings page: no "In use" tag (the grid marks the picked card itself) and no "Recommended" badge (the setup step recommends the host look)
---@return table[] cards { value, title, caption, tag?, recommended?, art?, styleId, source }
function Gallery:Cards(opts)
	opts = opts or {}
	local current = P.Store:Get('style')
	local cards = {}
	local art = self:CanDraw() and self.ART or nil
	local suggested = self:SuggestedStyle()
	local suggestedCard
	for _, item in ipairs(Registry:List(false)) do
		local tag
		if item.matchesHost then
			tag = L['Matches your look']
		elseif item.id == suggested then
			tag = L['Suggested']
		end
		if not opts.page and (item.id == current or (current == 'host' and item.matchesHost)) then
			tag = L['In use']
		end
		local card = {
			value = item.matchesHost and 'host' or item.id,
			title = item.matchesHost and L['Match my look'] or item.name,
			caption = self:Caption(item),
			tag = tag,
			recommended = (item.matchesHost and not opts.page) or nil,
			art = art,
			styleId = item.id,
			source = item.source,
		}
		if item.id == suggested then
			suggestedCard = card
		else
			cards[#cards + 1] = card
		end
	end
	if suggestedCard then
		-- Right after "Match my look", which stays first
		local at = (cards[1] and cards[1].value == 'host') and 2 or 1
		table.insert(cards, at, suggestedCard)
	end
	return cards
end

---The shared picture for every card (the card's own value says which style to draw).
---@param styleId? string
---@return table|nil
function Gallery:Art(styleId)
	return self:CanDraw() and self.ART or nil
end

----------------------------------------------------------------------------------------------------
-- What the preview panel should draw
----------------------------------------------------------------------------------------------------

---Remember the card the mouse is over (nil: none) and tell the preview panel.
---@param value? string Card value
function Gallery:SetHover(value)
	if self.hover == value then
		return
	end
	self.hover = value
	P:Fire('GALLERY_HOVER', value)
end

---@class Plates.GalleryPreview
---@field style table Cleaned, upgraded style from a pasted string
---@field name string
---@field author? string
---@field version? integer

---Show a pasted style in the preview panel (nil to stop).
---@param info? Plates.GalleryPreview
function Gallery:SetPreview(info)
	if self.preview == info then
		return
	end
	self.preview = info
	self.previewCount = self.previewCount + 1
	P.util.Wipe(self.previewCache)
	P:Fire('GALLERY_PREVIEW', info)
end

function Gallery:ClearPreview()
	self:SetPreview(nil)
end

---@return Plates.GalleryPreview|nil
function Gallery:GetPreview()
	return self.preview
end

---A pasted style as a resolved style (pure, cached until the preview changes).
---@param situation string
---@param sizeKey string
---@return Plates.ResolvedStyle|nil
function Gallery:ResolvePreview(situation, sizeKey)
	local info = self.preview
	if not info then
		return nil
	end
	sizeKey = SIZE_KEYS[sizeKey] and sizeKey or 'medium'
	local key = situation .. '|' .. sizeKey
	local cached = self.previewCache[key]
	if cached then
		return cached
	end
	local resolved = Merge.ResolveRaw(info.style, nil, situation, sizeKey, P.hostLook)
	if not resolved then
		return nil
	end
	resolved.id = '@preview'
	resolved.key = 'preview' .. self.previewCount .. '|' .. key
	self.previewCache[key] = resolved
	return resolved
end

---The style the preview panel's Pull scene should draw for a plate of this kind: the pasted
---style, else the hovered card's style, else nil (the caller draws the current style).
---@param situation string
---@param sizeKey string
---@return Plates.ResolvedStyle|nil
function Gallery:ResolveShown(situation, sizeKey)
	if self.preview then
		return self:ResolvePreview(situation, sizeKey)
	end
	if self.hover then
		return Merge:Resolve(self.hover, situation, SIZE_KEYS[sizeKey] and sizeKey or 'medium')
	end
	return nil
end

---@param value string Card value
---@param situation string
---@param sizeKey string
---@return Plates.ResolvedStyle
function Gallery:ResolveCard(value, situation, sizeKey)
	if value == self.PREVIEW_VALUE then
		local resolved = self:ResolvePreview(situation, sizeKey)
		if resolved then
			return resolved
		end
		value = 'host'
	end
	return Merge:Resolve(value, situation, sizeKey)
end

----------------------------------------------------------------------------------------------------
-- Live card pictures
----------------------------------------------------------------------------------------------------

local function Union(a, b)
	if not a then
		return { left = b.left, right = b.right, top = b.top, bottom = b.bottom }
	end
	a.left = math.min(a.left, b.left)
	a.right = math.max(a.right, b.right)
	a.top = math.max(a.top, b.top)
	a.bottom = math.min(a.bottom, b.bottom)
	return a
end

local ICON_HAS_DATA = {
	raidMarker = function(sample)
		return sample.raidMarker ~= nil
	end,
	classification = function(sample)
		local class = sample.facts and sample.facts.classification
		return class ~= nil and class ~= 'normal' and class ~= 'trivial' and class ~= 'minus'
	end,
	quest = function(sample)
		return sample.quest == true
	end,
	faction = function(sample)
		return sample.pvp == true or sample.faction ~= nil
	end,
	focus = function(sample)
		return sample.states ~= nil and sample.states.focus == true
	end,
	shield = function()
		return false
	end,
}

local TEXT_HAS_DATA = {
	forces = function(sample)
		return sample.forces ~= nil
	end,
	title = function(sample)
		return sample.title ~= nil
	end,
	arena = function(sample)
		return sample.arena ~= nil
	end,
	castName = function(sample)
		return sample.cast ~= nil
	end,
	castTime = function(sample)
		return sample.cast ~= nil
	end,
	castTarget = function(sample)
		return sample.cast ~= nil and sample.cast.target ~= nil
	end,
	threatPercent = function(sample)
		return sample.threat ~= nil
	end,
	threatLead = function(sample)
		return sample.threat ~= nil
	end,
}

---True when a part draws something for this sample (an aura row with no sample icons, a cast bar
---on a unit that is not casting, a mark the sample does not have all stay empty).
---@param spec table Resolved part
---@param sample Plates.Sample
---@return boolean
function Gallery.PartShown(spec, sample)
	if spec.state and not (sample.states and sample.states[spec.state]) then
		return false
	end
	local kind = spec.kind
	if kind == 'region' then
		return false
	elseif kind == 'cast' then
		return sample.cast ~= nil
	elseif kind == 'auras' then
		local list = sample.auras and sample.auras[spec.row]
		return list ~= nil and #list > 0
	elseif kind == 'icon' then
		local has = ICON_HAS_DATA[spec.source]
		return has == nil or has(sample)
	elseif kind == 'text' then
		local has = TEXT_HAS_DATA[spec.source]
		return has == nil or has(sample)
	end
	return true
end

---Rectangle that holds a plate and every part that shows something for this sample, relative to
---the plate center.
---@param resolved Plates.ResolvedStyle
---@param sample Plates.Sample
---@return Plates.Rect
function Gallery.Bounds(resolved, sample)
	local rects = Merge.PartRects(resolved)
	local box = Union(nil, rects.plate)
	for _, id in ipairs(resolved.order) do
		local rect = rects[id]
		if rect and Gallery.PartShown(resolved.parts[id], sample) then
			box = Union(box, rect)
		end
	end
	return box
end

local sharedContext

---One context for every card plate, so the color programs are made once (Colors caches them
---per context table).
---@return Plates.Context
local function CardContext()
	if not sharedContext then
		local make = P.Scenes and P.Scenes.PreviewContext
		local fields = { role = 'damage', inGroup = false, groupSize = 1, hasTarget = true, place = 'world' }
		if make then
			sharedContext = make(fields)
		else
			sharedContext = { place = 'world', inCombat = false, resting = false, role = 'damage', inGroup = false, groupSize = 1, tanks = {}, petTank = false, playerLevel = 1, hasTarget = true }
		end
	end
	return sharedContext
end

---Choose how many samples fit and where each goes. Pure geometry plus style resolution.
---@param value string Card value
---@param sizeKey string
---@param width number Picture width
---@param height number Picture height
---@return { scale: number, total: number, items: table[] }
function Gallery:Plan(value, sizeKey, width, height)
	local pad, gap = self.THUMB_PAD, self.THUMB_GAP
	local best
	for index, set in ipairs(self.THUMB_SETS) do
		local items, maxWidth, total = {}, 1, 0
		for _, sampleId in ipairs(set) do
			local sample = P.Data.Samples[sampleId]
			if sample then
				local kind = P.Situation.Classify(sample.facts)
				local resolved = self:ResolveCard(value, kind, sizeKey)
				local box = Gallery.Bounds(resolved, sample)
				local w, h = box.right - box.left, box.top - box.bottom
				items[#items + 1] = { sample = sample, resolved = resolved, box = box, w = w, h = h }
				maxWidth = math.max(maxWidth, w)
				total = total + h
			end
		end
		total = total + gap * math.max(#items - 1, 0)
		local scale = math.max(0.05, math.min(1, (width - pad * 2) / math.max(maxWidth, 1), (height - pad * 2) / math.max(total, 1)))
		best = { scale = scale, items = items, total = total }
		if scale >= self.THUMB_MIN_SCALE or index == #self.THUMB_SETS then
			break
		end
	end
	-- Stack from the top of the centered group; each plate is centered on its own parts
	local y = best.total / 2
	for _, item in ipairs(best.items) do
		local box = item.box
		item.x = -(box.left + box.right) / 2
		item.y = y - box.top
		y = y - item.h - gap
	end
	return best
end

local function ViewOf(holder)
	local view = Gallery.views[holder]
	if view then
		return view
	end
	local scaler = CreateFrame('Frame', nil, holder)
	view = { scaler = scaler, plates = {}, sources = {}, bound = {} }
	Gallery.views[holder] = view
	-- A card that hides (window closed, grid swapped) stops every sample's timers
	holder:HookScript('OnHide', function()
		Gallery:Park(holder)
	end)
	return view
end

---Unbind a holder's plates (no events, no timers) and hide them. They are kept for the next draw.
---@param holder table
function Gallery:Park(holder)
	local view = self.views[holder]
	if not view then
		return
	end
	for index, plate in ipairs(view.plates) do
		if plate.src then
			plate:Unbind()
		end
		view.bound[index] = nil
	end
	view.scaler:Hide()
end

---Bring one preview plate to a style and a sample. Re-binds only when something changed.
---@param view table
---@param index integer
---@param item table A Plan item
local function Show(view, index, item)
	local plate = view.plates[index]
	if not plate then
		plate = P.Plate.New(view.scaler, true, CardContext())
		view.plates[index] = plate
		view.sources[index] = P.Source.NewSample(item.sample)
	end
	local sample = item.sample
	local source = view.sources[index]
	if plate.env.ctx ~= CardContext() then
		plate:SetContext(CardContext())
	end
	plate.root:ClearAllPoints()
	plate.root:SetPoint('CENTER', view.scaler, 'CENTER', item.x, item.y)
	if view.bound[index] ~= sample.id then
		if plate.src then
			plate:Unbind()
		end
		source:SetSample(sample)
		plate:ApplyStyle(item.resolved)
		plate:BindSample(source)
		for state, on in pairs(sample.states or {}) do
			if on then
				plate.states[state] = nil
				plate:SetState(state, true)
			end
		end
		plate:ApplyEmphasis(true)
		view.bound[index] = sample.id
	elseif plate:ApplyStyle(item.resolved) then
		plate:UpdateAll('FULL')
		plate:ApplyEmphasis(true)
	else
		plate:Refresh({ colors = true })
	end
	plate.root:Show()
end

local reported = {}

---LibAT card art draw: show the style on a few sample plates, scaled to the picture.
---@param holder table
---@param data table Card data (value, variant)
---@param card table
---@param width number
---@param height number
---@param state table
function Gallery.Draw(holder, data, card, width, height, state)
	local view = ViewOf(holder)
	local value = data and data.value or 'host'
	local sizeKey = data and data.variant
	if not SIZE_KEYS[sizeKey] then
		sizeKey = P.Store:Get('size')
		if not SIZE_KEYS[sizeKey] then
			sizeKey = 'medium'
		end
	end
	local ok, err = pcall(function()
		local plan = Gallery:Plan(value, sizeKey, width, height)
		local scaler = view.scaler
		scaler:ClearAllPoints()
		scaler:SetPoint('CENTER', holder, 'CENTER', 0, 0)
		scaler:SetSize(width / plan.scale, height / plan.scale)
		scaler:SetScale(plan.scale)
		scaler:Show()
		for index, item in ipairs(plan.items) do
			Show(view, index, item)
		end
		-- A smaller set than last time: park the plates it no longer uses
		for index = #plan.items + 1, #view.plates do
			local plate = view.plates[index]
			if plate.src then
				plate:Unbind()
			end
			plate.root:Hide()
			view.bound[index] = nil
		end
	end)
	if not ok then
		Gallery:Park(holder)
		local message = tostring(err)
		if not reported[message] then
			reported[message] = true
			P.log.error('Style card could not be drawn: ' .. message)
		end
	end
end

---LibAT card art release: the card is reused for other data.
---@param holder table
function Gallery.Release(holder)
	Gallery:Park(holder)
end

Gallery.ART = { draw = Gallery.Draw, release = Gallery.Release }

----------------------------------------------------------------------------------------------------
-- Actions on the player's styles (the Style page and the card menu call these)
----------------------------------------------------------------------------------------------------

---A name no other style has: "Name", "Name 2", "Name 3" ...
---@param base string
---@param exceptId? string Ignore this style (renaming keeps its own name)
---@return string
function Gallery:UniqueName(base, exceptId)
	base = Gallery.CleanName(base)
	if base == '' then
		base = L['My style']
	end
	base = string.sub(base, 1, 40)
	local taken = {}
	for _, item in ipairs(Registry:List(true)) do
		if item.id ~= exceptId then
			taken[string.lower(item.name or '')] = true
		end
	end
	local name, n = base, 1
	while taken[string.lower(name)] do
		n = n + 1
		name = base .. ' ' .. n
	end
	return name
end

---Save a copy of a style (its base with the player's changes baked in) as a new style.
---@param value string Card value or style id
---@return string|nil newId
---@return string|nil name
function Gallery:Copy(value)
	local id = Registry:ResolveId(value)
	local baked = Merge:Bake(id)
	if not baked then
		return nil
	end
	local name = self:UniqueName(string.format(L['%s copy'], baked.name or id))
	baked.internal = nil
	baked.matchesHost = nil
	local newId = Registry:Save(baked, name, { kind = 'copy' })
	return newId, name
end

---@param id string
---@param name string
---@return boolean ok
---@return string|nil name The name that was set
function Gallery:Rename(id, name)
	if not Registry:IsSaved(id) then
		return false
	end
	name = Gallery.CleanName(name)
	if name == '' then
		return false
	end
	name = self:UniqueName(name, id)
	Registry:Rename(id, name)
	return true, name
end

---Delete one of the player's styles. The profile stops using it (back to the host look when it
---was the style in use) and loses the changes made to it.
---@param id string
---@return boolean ok
function Gallery:Delete(id)
	if not Registry:IsSaved(id) then
		return false
	end
	local Store = P.Store
	Store:Batch(function()
		if Store:Get('style') == id then
			Store:Reset('style')
		end
		local assign = Store:Get('assign')
		if type(assign) == 'table' then
			for kind, styleId in pairs(P.util.Copy(assign)) do
				if styleId == id then
					Store:Set({ 'assign', kind }, nil)
				end
			end
		end
		local when = Store:Get('when')
		if type(when) == 'table' then
			local changed = false
			local kept = {}
			for _, entry in ipairs(P.util.Copy(when)) do
				local drop = false
				if entry.style == id then
					entry.style = nil
					changed = true
					-- An entry that only used this style has nothing left to do
					drop = entry.size == nil and entry.mode == nil and not entry.off
				end
				if not drop then
					kept[#kept + 1] = entry
				end
			end
			if changed then
				Store:Set('when', #kept > 0 and kept or nil)
			end
		end
		Store:Set({ 'tweaks', id }, nil)
	end)
	Registry:Delete(id)
	if self.hover == id then
		self:SetHover(nil)
	end
	return true
end

----------------------------------------------------------------------------------------------------
-- Right-click menu
----------------------------------------------------------------------------------------------------

---Menu rows for a card.
---@param value string Card value
---@return Plates.MenuItem[]
function Gallery:MenuItems(value)
	local items = {
		{ value = 'use', text = L['Use this style'] },
		{ value = 'copy', text = L['Make a copy'] },
		{ value = 'share', text = L['Share'] },
	}
	if Registry:IsSaved(value) then
		items[#items + 1] = { value = 'rename', text = L['Rename'] }
		items[#items + 1] = { value = 'delete', text = L['Delete'] }
	end
	return items
end

---Called with (action, value) when a menu row is picked. The Style page sets this.
---@type fun(action: string, value: string)|nil
Gallery.OnMenuPick = nil

---Open the right-click menu under a card.
---@param value string Card value
---@param card table The card frame (the menu opens under it)
---@return boolean opened
function Gallery:OpenMenu(value, card)
	local Draw = P.Widgets and P.Widgets.Draw
	if not (Draw and Draw.OpenMenu and card and value ~= self.PREVIEW_VALUE) then
		return false
	end
	Draw.OpenMenu(card, self:MenuItems(value), function(action)
		local pick = Gallery.OnMenuPick
		if pick then
			pick(action, value)
		end
	end, { width = 170 })
	return true
end
