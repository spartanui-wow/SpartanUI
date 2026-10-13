local _, ns = ...
local P = ns.Plates
local Secret = P.Secret
local EMPTY = {} -- read only

-- Plate objects and the part registry (6.3, 6.5). A plate is our insecure drawing of one Blizzard
-- base nameplate (live) or one sample in a preview. It owns:
--   root    frame that follows the base plate (live) or sits on a preview canvas
--   art     frame sized to the resolved style; every part hangs from it; states ease its size and
--           alpha in whole pixels (never SetScale)
--   events  live only: its own event frame, RegisterUnitEvent for the union of its parts' events
--           (unit tokens in payloads can be secret, so no shared frame indexes plates by unit)
--   click / stack  live only, created and sized by the Driver (click area, stacking bounds)
--
-- Lifecycle (called by the Driver for live plates, by UI/Scenes for previews):
--   Plate.New(parent, isPreview, ctx)  build frames; parts are created lazily by ApplyStyle.
--                                 ctx is the context conditions and colors read (default
--                                 P.Context); previews pass their own (Scenes.PreviewContext)
--   plate:ApplyStyle(resolved)    lay parts out; no-op when resolved.key is unchanged
--   plate:Bind(unit, src)         start events and fill every part (live)
--   plate:BindSample(src)         fill every part from a SampleSource (preview, no events)
--   plate:SetState(state, on)     target / focus / mouseover / casting; emphasis only
--   plate:SetStateSecret(state, boolSecret)  the same from a possibly-secret boolean (S4)
--   plate:Refresh(reasons)        settings changed but the style key did not
--   plate:Unbind()                stop events, Reset every part, hide
-- Switching styles never destroys frames: widgets are cached per part id and implementation and
-- hidden when the new style does not use them.
--
-- Part contract (Parts:Register):
--   Create(plate, id, spec) -> widget      frames only, no data; parent frames to plate.art
--   Layout(widget, spec, ctx)              apply size, anchor, textures, fonts; called when the
--                                          style key changes or a listed refresh reason arrives
--   Update(widget, src, event, ...)        fill with data; event is 'FULL' for a full refresh,
--                                          a unit event, or a bus message name
--   Reset(widget)                          unbind: clear data, stop animations; frames stay
--   OnState(widget, state, on)             optional; target/focus/mouseover/casting changed
--   OnStateSecret(widget, state, boolSecret) optional; the state is only known as a secret
--   Configure(widget, spec, ctx)           optional; aura filter and layout changes, called only
--                                          while P.Secret.IsRestricted() is false (otherwise the
--                                          plate marks pendingConfigure and the Driver runs it
--                                          when the restriction lifts)
-- A widget is a table with at least { frame = <root region> }; the plate adds plate, id, impl,
-- spec and active. Other parts anchor to widget.anchor or widget.frame.
--
-- Who shows what:
--   * The plate owns widget.frame: it is shown while the part is in the style (and, for parts
--     with spec.state, while that state is on). Parts never Show or Hide widget.frame.
--   * A part shows and hides its data on child regions (a bar inside a holder, a texture, a
--     font string) or by alpha on those children. The cast part hides its inner bar between casts.
--   * Common fields are applied by the plate right after Layout (ApplyCommon): spec.alpha on
--     widget.frame, draw order (frame level from the part's place in style.order plus spec.layer)
--     and spec.pixelSnap on the textures listed in widget.textures (plus a bar's fill texture).
--     spec.above ("draw above other plates") is the Driver's lift frame (Phase 5); the plate
--     leaves it alone.
-- Fonts: ctx:ApplyFont(fontString, fontSpec, forNames). Text that can show a player name passes
-- forNames = true and gets a font family (P.Fonts), so Cyrillic, Korean and Chinese names render.

---@class Plates.PartImpl
---@field id string Registry key ('health', 'bar', 'cast', ...)
---@field kinds string[] Style part kinds this implementation draws
---@field match? fun(spec: table, plate: Plates.Plate): boolean Extra test when kinds are shared
---@field priority? number Higher wins when several implementations match (default 0)
---@field events? string[]|fun(spec: table): string[] Unit events for RegisterUnitEvent
---@field messages? string[]|fun(spec: table): string[] Bus messages delivered through OnMessage (or Update)
---@field contextKeys? table<string, boolean>|fun(spec: table): table<string, boolean> Context fields the part reads
---@field reasons? table<string, boolean> Refresh reasons that call Layout again (look and size always do)
---@field Create fun(plate: Plates.Plate, id: string, spec: table): Plates.Widget
---@field Layout fun(widget: Plates.Widget, spec: table, ctx: Plates.LayoutContext)
---@field Update fun(widget: Plates.Widget, src: Plates.Source, event: string, ...)
---@field Reset fun(widget: Plates.Widget)
---@field OnState? fun(widget: Plates.Widget, state: string, on: boolean)
---@field OnStateSecret? fun(widget: Plates.Widget, state: string, boolSecret: any)
---@field OnMessage? fun(widget: Plates.Widget, message: string, ...)
---@field Configure? fun(widget: Plates.Widget, spec: table, ctx: Plates.LayoutContext)

---@class Plates.Widget
---@field frame table Root region, shown and hidden by the plate only
---@field textures? table[] Textures that follow spec.pixelSnap
---@field anchor? table Region other parts anchor to (defaults to frame)
---@field plate Plates.Plate
---@field id string Part id in the style
---@field impl Plates.PartImpl
---@field spec table Resolved spec last laid out
---@field active boolean
---@field bar? table Health widgets expose their StatusBar here (API:GetHealthBar)

---@class Plates.Parts
local Parts = { impls = {}, byKind = {} }
P.Parts = Parts

---@param impl Plates.PartImpl
function Parts:Register(impl)
	assert(impl.id and impl.kinds and impl.Create and impl.Layout and impl.Update and impl.Reset, 'Parts:Register needs id, kinds, Create, Layout, Update, Reset')
	self.impls[impl.id] = impl
	for _, kind in ipairs(impl.kinds) do
		self.byKind[kind] = self.byKind[kind] or {}
		local list = self.byKind[kind]
		local replaced = false
		for i = 1, #list do
			if list[i].id == impl.id then
				list[i] = impl
				replaced = true
			end
		end
		if not replaced then
			list[#list + 1] = impl
		end
	end
end

---The implementation that draws a part spec on a plate.
---@param spec table
---@param plate Plates.Plate
---@return Plates.PartImpl|nil
function Parts:Resolve(spec, plate)
	local best, bestPriority
	for _, impl in ipairs(self.byKind[spec.kind] or {}) do
		if not impl.match or impl.match(spec, plate) then
			local priority = impl.priority or 0
			if not best or priority > bestPriority then
				best, bestPriority = impl, priority
			end
		end
	end
	return best
end

---@param id string
---@return Plates.PartImpl|nil
function Parts:Get(id)
	return self.impls[id]
end

----------------------------------------------------------------------------------------------------
-- Layout context: one shared object, pointed at a plate before its parts lay out
----------------------------------------------------------------------------------------------------

---@class Plates.LayoutContext
---@field plate Plates.Plate
---@field style Plates.ResolvedStyle
---@field width integer
---@field height integer
local Ctx = {}
P.LayoutContext = Ctx

---Region for an anchor target: 'plate' is plate.art, a part id is that part's anchor region.
---@param id string
---@return table region
function Ctx:Region(id)
	local plate = self.plate
	if id == 'plate' or id == nil then
		return plate.art
	end
	local widget = plate:GetWidget(id)
	if widget and widget.active then
		return widget.anchor or widget.frame
	end
	return plate.art
end

---Point a region at its spec anchor { point, relativeTo, relPoint, x, y } in whole pixels.
---@param region table
---@param anchor table|nil
function Ctx:Anchor(region, anchor)
	region:ClearAllPoints()
	if not anchor then
		region:SetPoint('CENTER', self.plate.art, 'CENTER', 0, 0)
		return
	end
	region:SetPoint(anchor[1], self:Region(anchor[2]), anchor[3] or anchor[1], anchor[4] or 0, anchor[5] or 0)
end

---Font file, size and flags for a font spec. Faces may be LSM keys or file paths.
---@param font table|nil { face, size, flags }
---@return string face
---@return number size
---@return string flags
function Ctx:Font(font)
	font = font or {}
	local face = font.face
	local media = P.services.media
	if type(face) == 'string' and media and media.IsValid and media:IsValid('font', face) then
		face = media:Fetch('font', face)
	end
	if type(face) ~= 'string' then
		face = P.services.FontPath()
	end
	return face, font.size or 10, font.flags or ''
end

---Texture path for a LSM statusbar key, an art key or a path.
---@param key string|nil
---@param mediaType? string LSM type (default 'statusbar')
---@return string|nil
function Ctx:Texture(key, mediaType)
	if type(key) ~= 'string' then
		return nil
	end
	key = P.Data.ArtAliases:Resolve(key)
	local media = P.services.media
	mediaType = mediaType or 'statusbar'
	if media and media.IsValid and media:IsValid(mediaType, key) then
		return media:Fetch(mediaType, key)
	end
	-- A key no media library knows is only usable when it is a file path
	if string.find(key, '[\\/]') then
		return key
	end
	return nil
end

---Plain color values from a resolved color { r, g, b, a } (tokens are already resolved).
---@param color table|nil
---@return number r
---@return number g
---@return number b
---@return number a
function Ctx:Color(color)
	if type(color) ~= 'table' then
		return 1, 1, 1, 1
	end
	return color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
end

---Compiled color list for a piece ('health', 'border', 'name', 'cast').
---@param piece string
---@return Plates.ColorProgram
function Ctx:Program(piece)
	return P.Colors:Program(piece, self.plate.env.ctx)
end

---Set a font on a font string. Text that can show player names (forNames) gets a font family
---(P.Fonts) so non-Latin names render; other text gets the face directly. Preview text scales
---smoothly where the client can.
---@param fontString table
---@param font table|nil { face, size, flags }
---@param forNames? boolean
local fontState = setmetatable({}, { __mode = 'k' })

function Ctx:ApplyFont(fontString, font, forNames)
	local face, size, flags = self:Font(font)
	local cached = fontState[fontString]
	if cached and cached.face == face and cached.size == size and cached.flags == flags and cached.names == forNames then
		return
	end
	if not cached then
		cached = {}
		fontState[fontString] = cached
	end
	cached.face, cached.size, cached.flags, cached.names = face, size, flags, forNames
	local object = forNames and P.Fonts:Family(face, size, flags) or nil
	if object then
		fontString:SetFontObject(object)
	else
		fontString:SetFont(face, size, flags)
	end
	if self.plate.isPreview and fontString.SetSmoothScaling then
		fontString:SetSmoothScaling(true)
	end
end

---Frame levels each part may use: its own frame's level and the ones above it, for child frames
---such as the health bar's shield bars, so the next part (text over the bar) still draws on top.
Ctx.PART_LEVELS = 4

---Apply the fields every part may hold (alpha, draw order, pixel snapping). Called by the plate
---right after the part's Layout.
---@param widget Plates.Widget
---@param spec table
---@param rank integer Place of the part in style.order
function Ctx:ApplyCommon(widget, spec, rank)
	local frame = widget.frame
	if not frame then
		return
	end
	if frame.SetAlpha then
		frame:SetAlpha(spec.alpha or 1)
	end
	local base = self.plate.artLevel
	if base and frame.SetFrameLevel then
		-- Each layer step leaves room for every part of a style to keep its own levels
		local step = Ctx.PART_LEVELS
		frame:SetFrameLevel(base + 1 + rank * step + ((spec.layer or 0) + 8) * 32 * step)
	end
	if spec.pixelSnap ~= nil then
		local snap = spec.pixelSnap and true or false
		for _, texture in ipairs(widget.textures or {}) do
			if texture.SetSnapToPixelGrid then
				texture:SetSnapToPixelGrid(snap)
			end
		end
		local bar = widget.bar or widget.statusBar
		local fill = bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture()
		if fill and fill.SetSnapToPixelGrid then
			fill:SetSnapToPixelGrid(snap)
		end
	end
end

---Plain effective scale of a region, or nil when it cannot be read (a frame inside the game's
---nameplate tree can report its scale as a hidden value on 12.1).
---@param region table|nil
---@return number|nil
local function PlainScale(region)
	if not (region and region.GetEffectiveScale) then
		return nil
	end
	local ok, scale = pcall(region.GetEffectiveScale, region)
	scale = ok and Secret.Plain(scale) or nil
	if type(scale) ~= 'number' or scale <= 0 then
		return nil
	end
	return scale
end

---Size of one physical pixel in this plate's UI units (for 1 px borders). Never secret: a hidden
---plate scale falls back to the UI parent's.
---@return number
function Ctx:Pixel()
	local scale = PlainScale(self.plate.art) or PlainScale(UIParent) or 1
	local physical = GetPhysicalScreenSize and select(2, GetPhysicalScreenSize()) or 768
	physical = Secret.Plain(physical)
	if type(physical) ~= 'number' or physical <= 0 then
		return 1
	end
	return 768 / physical / scale
end

local layoutCtx = setmetatable({}, { __index = Ctx })

---Point the shared layout context at a plate and its current style.
---@param plate Plates.Plate
---@return Plates.LayoutContext
local function PointCtx(plate)
	local style = plate.style
	layoutCtx.plate, layoutCtx.style = plate, style
	layoutCtx.width = style and style.width or 0
	layoutCtx.height = style and style.height or 0
	return layoutCtx
end

----------------------------------------------------------------------------------------------------
-- Fonts for names (S10)
----------------------------------------------------------------------------------------------------

---@class Plates.Fonts
local Fonts = { families = {}, count = 0 }
P.Fonts = Fonts

local ALPHABETS = { 'roman', 'russian', 'korean', 'simplifiedchinese', 'traditionalchinese' }
-- The game's own faces, used when its name font cannot tell us its files
local GAME_FACES = {
	roman = 'Fonts\\FRIZQT__.TTF',
	russian = 'Fonts\\FRIZQT___CYR.TTF',
	korean = 'Fonts\\2002.TTF',
	simplifiedchinese = 'Fonts\\ARKai_T.ttf',
	traditionalchinese = 'Fonts\\blei00d.TTF',
}
local LOCALE_ALPHABET = { koKR = 'korean', zhCN = 'simplifiedchinese', zhTW = 'traditionalchinese', ruRU = 'russian' }

---The alphabet of the client's own language; the chosen face is set only for it.
---@return string
function Fonts.OwnAlphabet()
	local locale = GetLocale and GetLocale() or 'enUS'
	return LOCALE_ALPHABET[locale] or 'roman'
end

local function GameFace(alphabet)
	local base = _G.SystemFont_NamePlate
	if base and base.GetFontObjectForAlphabet then
		local ok, member = pcall(base.GetFontObjectForAlphabet, base, alphabet)
		if ok and member and member.GetFont then
			local okFont, file = pcall(member.GetFont, member)
			if okFont and type(file) == 'string' and file ~= '' then
				return file
			end
		end
	end
	return GAME_FACES[alphabet]
end

---The game's own name font, used when the client cannot make font families (S10).
---@return table|nil
function Fonts:Fallback()
	return _G.SystemFont_NamePlate
end

---A font family for text that can show player names: the chosen face for the client's own
---alphabet, the game's faces for the others. One family per face, size and flags, named from
---host.globalPrefix. Falls back to the game's name font when families are not available.
---@param face string
---@param size number
---@param flags string
---@return table|nil fontObject
function Fonts:Family(face, size, flags)
	if not (CreateFontFamily and P.Caps:Get('fontFamily')) then
		return self:Fallback()
	end
	local key = face .. '|' .. size .. '|' .. flags
	local family = self.families[key]
	if family == nil then
		local own = self.OwnAlphabet()
		local members = {}
		for i, alphabet in ipairs(ALPHABETS) do
			members[i] = { alphabet = alphabet, file = alphabet == own and face or GameFace(alphabet), height = size, flags = flags }
		end
		self.count = self.count + 1
		local prefix = P.host and P.host.globalPrefix or 'Nameplates'
		local ok, created = pcall(CreateFontFamily, prefix .. 'NameFont' .. self.count, members)
		family = (ok and created) or false
		if not family then
			P.log.warning('Could not make a name font; using the game name font instead')
		end
		self.families[key] = family
	end
	return family or self:Fallback()
end

----------------------------------------------------------------------------------------------------
-- Plate
----------------------------------------------------------------------------------------------------

---@class Plates.Plate
---@field root table
---@field art table
---@field events? table Live only
---@field click? table Live only (Driver)
---@field stack? table Live only (Driver)
---@field base? table Blizzard base nameplate (live)
---@field unit? string
---@field src? Plates.Source
---@field isPreview boolean
---@field facts Plates.Facts
---@field states table<string, boolean>
---@field env table { facts, ctx, states, src } passed to conditions and colors
---@field style? Plates.ResolvedStyle
---@field styleKey? string
---@field situation? string
---@field assignment Plates.Assignment
---@field widgets table<string, Plates.Widget> Keyed by impl id .. ':' .. part id
---@field active Plates.Widget[] Widgets in the current style, layout order
---@field eventWidgets table<string, Plates.Widget[]>
---@field messageWidgets table<string, Plates.Widget[]>
local Plate = {}
Plate.__index = Plate
P.Plate = Plate

---Build a plate. Live plates get an event frame; previews never register events.
---@param parent table
---@param isPreview boolean
---@param ctx? Plates.Context Context for conditions and colors (previews); default P.Context
---@return Plates.Plate
function Plate.New(parent, isPreview, ctx)
	local plate = setmetatable({}, Plate)
	plate.isPreview = isPreview and true or false
	plate.root = CreateFrame('Frame', nil, parent)
	plate.root:SetSize(1, 1)
	-- The "When" fade (Engine/Actions.lua) sits between root and art: the Driver fades root (range,
	-- only fighting), the plate eases art (target, healer emphasis), and a fade the game decides
	-- needs a frame of its own for SetAlphaFromBoolean. Alphas multiply down the chain.
	plate.fader = CreateFrame('Frame', nil, plate.root)
	plate.fader:SetSize(1, 1)
	plate.fader:SetPoint('CENTER', plate.root, 'CENTER', 0, 0)
	plate.art = CreateFrame('Frame', nil, plate.fader)
	plate.art:SetPoint('CENTER', plate.root, 'CENTER', 0, 0)
	plate.art:SetSize(1, 1)
	plate.artLevel = (Secret.Plain(plate.art:GetFrameLevel()))
	plate.facts = {}
	plate.states = {}
	plate.widgets = {}
	plate.active = {}
	plate.eventWidgets = {}
	plate.messageWidgets = {}
	plate.assignment = { deps = {} }
	plate.env = { facts = plate.facts, ctx = ctx or P.Context, states = plate.states, src = nil }
	plate.easeKey = tostring(plate)
	plate.easeSizeId, plate.easeAlphaId = plate.easeKey .. 'w', plate.easeKey .. 'a'
	plate.threatJobId, plate.threatSeen = plate.easeKey .. 'threat', {}
	plate.flushThreat = function()
		plate:FlushThreat()
	end
	-- Made once per plate, so a target change eases every plate without making closures
	plate.applySize = function(t)
		local fromW, fromH = plate.emFromW, plate.emFromH
		local w = math.floor(fromW + (plate.emToW - fromW) * t + 0.5)
		local h = math.floor(fromH + (plate.emToH - fromH) * t + 0.5)
		plate.emW, plate.emH = w, h
		plate.art:SetSize(w, h)
	end
	plate.applyAlpha = function(value)
		plate.emA = value
		plate.art:SetAlpha(value)
	end
	if not plate.isPreview then
		plate.events = CreateFrame('Frame')
		plate.events:SetScript('OnEvent', function(_, event, ...)
			plate:OnEvent(event, ...)
		end)
	end
	plate.root:Hide()
	return plate
end

---Use another context for conditions and colors (preview scenes reuse pooled plates).
---@param ctx? Plates.Context nil goes back to P.Context
function Plate:SetContext(ctx)
	self.env.ctx = ctx or P.Context
	self:RebuildEvents()
end

---The shared layout context pointed at this plate (for drawing outside a part's Layout).
---@return Plates.LayoutContext
function Plate:LayoutContext()
	return PointCtx(self)
end

---Run the "When" actions of this plate (Engine/Actions.lua) when it has any or drew any.
---@param plate Plates.Plate
local function RunActions(plate)
	local Actions = P.Actions
	if Actions and plate.actionsOn then
		Actions:Run(plate)
	end
end

---Pick this plate's "When" actions again (new style, unit or kind), so their events register.
---@param plate Plates.Plate
local function AttachActions(plate)
	local Actions = P.Actions
	if Actions then
		Actions:Attach(plate)
	end
end

---The role or the healer emphasis setting changed: lay out with the role's version of the style
---(healers get a stronger removable buffs row) and ease size and alpha to the new emphasis.
function Plate:RefreshRole()
	local base = self.baseStyle
	if not base then
		return
	end
	if self:ApplyStyle(base) then
		if self.src then
			self:UpdateAll('FULL')
			self:Configure()
		end
	else
		self:ApplyEmphasis(false)
	end
end

---@param id string Part id
---@return Plates.Widget|nil
function Plate:GetWidget(id)
	for i = 1, #self.active do
		local widget = self.active[i]
		if widget.id == id then
			return widget
		end
	end
	return nil
end

---Health StatusBar for P.API:GetHealthBar, or nil.
---@return table|nil
function Plate:GetHealthBar()
	for i = 1, #self.active do
		local widget = self.active[i]
		if widget.impl.id == 'health' and widget.bar then
			return widget.bar
		end
	end
	return nil
end

local function EventsOf(widget)
	local impl, spec = widget.impl, widget.spec
	local events = impl.events
	if type(events) == 'function' then
		events = events(spec)
	end
	return events or EMPTY
end

local COLOR_FIELDS = { 'colors', 'borderColors' }
local THREAT_EVENTS = { 'UNIT_THREAT_LIST_UPDATE', 'UNIT_THREAT_SITUATION_UPDATE' }

local function Add(map, key, widget)
	local list = map[key]
	if not list then
		list = {}
		map[key] = list
	end
	for i = 1, #list do
		if list[i] == widget then
			return
		end
	end
	list[#list + 1] = widget
end

---Rebuild the event and message maps (and, when bound, the unit event registrations).
function Plate:RebuildEvents()
	local cache = self.eventMapCache
	if not cache then
		cache = setmetatable({}, { __mode = 'k' })
		self.eventMapCache = cache
	end
	local cached = self.style and cache[self.style]
	if cached and cached.ctx == self.env.ctx then
		self.mapPrograms, self.mapCtx = cached.programs, cached.ctx
		if self:EventMapsCurrent() then
			self.eventWidgets, self.messageWidgets = cached.events, cached.messages
			self:RegisterUnitEvents()
			return
		end
	end
	local eventWidgets, messageWidgets, programs = {}, {}, {}
	self.mapBuilds = (self.mapBuilds or 0) + 1
	for i = 1, #self.active do
		local widget = self.active[i]
		local events = EventsOf(widget)
		for j = 1, #events do
			Add(eventWidgets, events[j], widget)
		end
		local messages = widget.impl.messages
		if type(messages) == 'function' then
			messages = messages(widget.spec)
		end
		messages = messages or EMPTY
		for j = 1, #messages do
			Add(messageWidgets, messages[j], widget)
		end
		-- Parts that use a color list also follow that list's events and messages
		for _, field in ipairs(COLOR_FIELDS) do
			local piece = widget.spec[field]
			if piece then
				local program = P.Colors:Program(piece, self.env.ctx)
				programs[#programs + 1] = program
				for event in pairs(program.events) do
					Add(eventWidgets, event, widget)
				end
				for message in pairs(program.messages) do
					Add(messageWidgets, message, widget)
				end
			end
		end
	end
	self.eventWidgets, self.messageWidgets = eventWidgets, messageWidgets
	self.mapPrograms, self.mapCtx = programs, self.env.ctx
	if self.style then
		cache[self.style] = { events = eventWidgets, messages = messageWidgets, programs = programs, ctx = self.env.ctx }
	end
	self:RegisterUnitEvents()
end

---Register the unit events of the current maps on the plate's own frame (live plates with a unit).
function Plate:RegisterUnitEvents()
	local frame = self.events
	if not (frame and self.unit) then
		return
	end
	-- The parts' events plus the events of this plate's "When" actions
	local extra = self.actionEvents or EMPTY
	local old = self.registeredMap
	local same = self.registeredUnit == self.unit and old ~= nil
	if same then
		for event in pairs(old) do
			if not self.eventWidgets[event] and not extra[event] then
				same = false
				break
			end
		end
		for event in pairs(self.eventWidgets) do
			if not old[event] then
				same = false
				break
			end
		end
		for event in pairs(extra) do
			if not old[event] then
				same = false
				break
			end
		end
	end
	if same then
		return
	end
	frame:UnregisterAllEvents()
	local map = self.eventWidgets
	if next(extra) then
		map = {}
		for event in pairs(self.eventWidgets) do
			map[event] = true
		end
		for event in pairs(extra) do
			map[event] = true
		end
	end
	self.registeredUnit, self.registeredMap = self.unit, map
	for event in pairs(map) do
		pcall(frame.RegisterUnitEvent, frame, event, self.unit)
	end
end

---True while the event maps still match the color programs they were built from (Colors makes new
---programs when settings or the context change), so binding a unit only registers events again and
---makes no tables (the Driver binds on every NAME_PLATE_UNIT_ADDED).
---@return boolean
function Plate:EventMapsCurrent()
	local programs = self.mapPrograms
	if not programs or self.mapCtx ~= self.env.ctx then
		return false
	end
	local n = 0
	for i = 1, #self.active do
		local spec = self.active[i].spec
		for j = 1, #COLOR_FIELDS do
			local piece = spec[COLOR_FIELDS[j]]
			if piece then
				n = n + 1
				if programs[n] ~= P.Colors:Program(piece, self.env.ctx) then
					return false
				end
			end
		end
	end
	return n == #programs
end

---Lay the plate out for a resolved style. Returns true when it re-laid out.
---@param resolved Plates.ResolvedStyle
---@return boolean
function Plate:ApplyStyle(resolved)
	resolved = resolved.roleBase or resolved
	self.baseStyle = resolved
	-- The role's version of the style (Roles.StyleFor: healers get a stronger removable buffs row)
	resolved = P.Roles.StyleFor(resolved, self)
	if self.styleKey == resolved.key then
		return false
	end
	self.style = resolved
	-- The pool can move a plate to another base plate, which changes the art frame's level
	self.artLevel = Secret.Plain(self.art:GetFrameLevel()) or self.artLevel
	local ctx = PointCtx(self)
	self.art:SetSize(resolved.width, resolved.height)

	-- Remember what was showing: a part the new style drops is reset below (a cast part that goes
	-- away mid-cast would otherwise never see its stop event and keep the casting state)
	local before = self.before or {}
	self.before = before
	for i = 1, #self.active do
		before[i] = self.active[i]
	end
	for _, widget in pairs(self.widgets) do
		widget.active = false
	end
	P.util.Wipe(self.active)
	for _, id in ipairs(resolved.order) do
		local spec = resolved.parts[id]
		local impl = Parts:Resolve(spec, self)
		if impl then
			local key = impl.id .. ':' .. id
			local widget = self.widgets[key]
			if not widget then
				widget = impl.Create(self, id, spec)
				widget.plate, widget.id, widget.impl = self, id, impl
				self.widgets[key] = widget
			end
			widget.spec = spec
			widget.active = true
			self.active[#self.active + 1] = widget
			impl.Layout(widget, spec, ctx)
			ctx:ApplyCommon(widget, spec, #self.active)
		end
	end
	for i = #before, 1, -1 do
		local widget = before[i]
		before[i] = nil
		if not widget.active and self.src then
			widget.impl.Reset(widget)
		end
	end
	for _, widget in pairs(self.widgets) do
		if widget.frame then
			if widget.active and (not widget.spec.state or self.states[widget.spec.state]) then
				widget.frame:Show()
			else
				widget.frame:Hide()
			end
		end
	end
	self.styleKey = resolved.key
	AttachActions(self)
	self:RebuildEvents()
	if P.Actions then
		P.Actions:Layout(self)
	end
	self:ApplyEmphasis(true)
	P:Fire('STYLE_APPLIED', self, resolved.key)
	return true
end

---Lay out again with the current style (used by Scheduler:QueueLayout).
function Plate:Layout()
	local resolved = self.baseStyle or self.style
	if not resolved then
		return
	end
	self.styleKey = nil
	self:ApplyStyle(resolved)
	if self.src then
		self:UpdateAll('FULL')
	end
end

---Fill every active part.
---@param event? string Default 'FULL'
function Plate:UpdateAll(event)
	local src = self.src
	if not src then
		return
	end
	-- One dispatch reads the game once: live sources keep cast info for its length
	local begin = src.BeginRead
	if begin then
		begin(src)
	end
	for i = 1, #self.active do
		local widget = self.active[i]
		widget.impl.Update(widget, src, event or 'FULL')
	end
	RunActions(self)
	if begin then
		src:EndRead()
	end
end

---Merge the paired threat notifications; a list-only notification flushes next frame.
function Plate:FlushThreat()
	local src, unit = self.src, self.threatUnit
	self.threatPending, self.threatUnit = nil, nil
	P.Scheduler.nextFrame[self.threatJobId] = nil
	if not src or unit ~= self.unit then
		return
	end
	local seen = self.threatSeen
	P.util.Wipe(seen)
	if src.BeginRead then
		src:BeginRead()
	end
	for _, event in ipairs(THREAT_EVENTS) do
		local list = self.eventWidgets[event] or EMPTY
		for i = 1, #list do
			local widget = list[i]
			if not seen[widget] then
				seen[widget] = true
				widget.impl.Update(widget, src, event, unit)
			end
		end
	end
	if self.actionRepaint or (self.actionEvents and (self.actionEvents.UNIT_THREAT_LIST_UPDATE or self.actionEvents.UNIT_THREAT_SITUATION_UPDATE)) then
		RunActions(self)
	end
	if src.EndRead then
		src:EndRead()
	end
end

---Unit event from this plate's own frame.
---@param event string
function Plate:OnEvent(event, ...)
	if self.src and event == 'UNIT_THREAT_LIST_UPDATE' then
		self.threatPending, self.threatUnit = true, self.unit
		P.Scheduler:NextFrame(self.threatJobId, self.flushThreat)
		return
	elseif event == 'UNIT_THREAT_SITUATION_UPDATE' and self.threatPending then
		self:FlushThreat()
		return
	end
	local list = self.eventWidgets[event]
	local src = self.src
	local actions = self.actionsOn and ((self.actionEvents and self.actionEvents[event]) or (list and self.actionRepaint))
	if not src or not (list or actions) then
		return
	end
	local begin = src.BeginRead
	if begin then
		begin(src)
	end
	for i = 1, #(list or EMPTY) do
		local widget = list[i]
		widget.impl.Update(widget, src, event, ...)
	end
	if actions then
		RunActions(self)
	end
	if begin then
		src:EndRead()
	end
end

---Bus message delivered by the Driver to bound plates (TARGET_CHANGED, KICK_READY_CHANGED, ...).
---@param message string
function Plate:OnMessage(message, ...)
	local list = self.messageWidgets[message]
	local src = self.src
	local actions = self.actionsOn and ((self.actionMessages and self.actionMessages[message]) or (list and self.actionRepaint))
	if not src or not (list or actions) then
		return
	end
	local begin = src.BeginRead
	if begin then
		begin(src)
	end
	list = list or EMPTY
	local keys = message == 'CONTEXT_CHANGED' and select(1, ...) or nil
	for i = 1, #list do
		local widget = list[i]
		local relevant = keys == nil
		if keys then
			for j = 1, #COLOR_FIELDS do
				local piece = widget.spec[COLOR_FIELDS[j]]
				if piece and P.Colors:ReadsContext(keys, P.Colors:Program(piece, self.env.ctx)) then
					relevant = true
				end
			end
			local reads = widget.impl.contextKeys
			if type(reads) == 'function' then
				reads = reads(widget.spec)
			end
			for key in pairs(reads or EMPTY) do
				if keys[key] then
					relevant = true
				end
			end
		end
		if relevant and widget.impl.OnMessage then
			widget.impl.OnMessage(widget, message, ...)
		elseif relevant then
			widget.impl.Update(widget, src, message, ...)
		end
	end
	if actions then
		RunActions(self)
	end
	if begin then
		src:EndRead()
	end
end

---Start a live plate on a unit.
---@param unit string
---@param src Plates.LiveSource
function Plate:Bind(unit, src)
	self.unit = unit
	self.src = src
	self.env.src = src
	AttachActions(self)
	if self:EventMapsCurrent() then
		self:RegisterUnitEvents()
	else
		self:RebuildEvents()
	end
	self.root:Show()
	self:UpdateAll('FULL')
end

---Fill a preview plate from a sample (no events).
---@param src Plates.SampleSource
function Plate:BindSample(src)
	self.src = src
	self.env.src = src
	src:ReadFacts(self.facts)
	for state, on in pairs(src.sample and src.sample.states or {}) do
		self.states[state] = on
	end
	AttachActions(self)
	self.root:Show()
	self:UpdateAll('FULL')
	self:ApplyEmphasis(true)
end

---Stop events, reset every part and hide.
function Plate:Unbind()
	self.threatPending, self.threatUnit = nil, nil
	P.Scheduler.nextFrame[self.threatJobId] = nil
	self.registeredUnit, self.registeredMap = nil, nil
	if self.events then
		self.events:UnregisterAllEvents()
	end
	for _, widget in pairs(self.widgets) do
		widget.impl.Reset(widget)
	end
	if P.Actions then
		P.Actions:Clear(self)
	end
	self.unit = nil
	self.src = nil
	self.env.src = nil
	P.util.Wipe(self.states)
	-- States start off for the next unit: hide state-tied parts now, because SetState(state, false)
	-- does nothing for a state that is already off
	for i = 1, #self.active do
		local widget = self.active[i]
		if widget.spec.state and widget.frame then
			widget.frame:Hide()
		end
	end
	-- and so does the target growth and fade
	self:ApplyEmphasis(true)
	self.root:Hide()
end

---Change a runtime state. States change emphasis only, never the layout.
---@param state 'target'|'focus'|'mouseover'|'casting'
---@param on boolean
function Plate:SetState(state, on)
	on = on and true or false
	if (self.states[state] or false) == on then
		return
	end
	self.states[state] = on or nil
	for i = 1, #self.active do
		local widget = self.active[i]
		if widget.spec.state == state and widget.frame then
			if on then
				widget.frame:Show()
			else
				widget.frame:Hide()
			end
		end
		if widget.impl.OnState then
			widget.impl.OnState(widget, state, on)
		end
	end
	self:ApplyEmphasis(false)
	if self.actionStates then
		RunActions(self)
	end
end

---A state known only as a possibly-secret boolean (the S4 fallback when the target plate cannot
---be found by frame compare). State-tied parts are shown and faded in or out by the engine;
---OnStateSecret lets a part react the same way. Target growth and the fade of other plates stay
---off while a state is only known this way (they would have to read the answer).
---@param state 'target'|'focus'|'mouseover'
---@param boolSecret any
function Plate:SetStateSecret(state, boolSecret)
	self.states[state] = nil
	for i = 1, #self.active do
		local widget = self.active[i]
		if widget.spec.state == state and widget.frame then
			widget.frame:Show()
			-- The part's own alpha (ApplyCommon set it) when shown, so a faded part stays faded
			Secret.SetAlphaFromBoolean(widget.frame, boolSecret, widget.spec.alpha or 1, 0)
		end
		if widget.impl.OnStateSecret then
			widget.impl.OnStateSecret(widget, state, boolSecret)
		end
	end
	self:ApplyEmphasis(false)
	if self.actionStates then
		RunActions(self)
	end
end

local EASE_TIME = 0.15

---Target growth (whole pixels) and alpha from style.states, eased on the shared scheduler.
---@param instant boolean Skip the ease (first layout, previews)
function Plate:ApplyEmphasis(instant)
	local resolved = self.style
	if not resolved then
		return
	end
	local stateSpecs = resolved.states or EMPTY
	local states = self.states
	local ctx = self.env.ctx or P.Context
	local width, height = resolved.width, resolved.height
	-- Healer emphasis (Roles): enemy plates stay small and soft until they matter
	local quiet = P.Roles.Quiet(self)
	if quiet then
		width, height = P.Roles.QuietSize(width, height)
	end
	local grow = states.target and stateSpecs.target and stateSpecs.target.grow
	if grow then
		width, height = width + grow[1], height + grow[2]
	end
	-- Extra whole-pixel growth parts ask for (plate.grows[owner] = { w, h }, e.g. the threat size channel)
	for _, extra in pairs(self.grows or EMPTY) do
		width, height = width + extra[1], height + extra[2]
	end
	local alpha = 1
	if not self.isPreview and ctx.hasTarget and not states.target then
		alpha = stateSpecs.notTarget and stateSpecs.notTarget.alpha or 1
	elseif self.isPreview and not states.target and stateSpecs.notTarget and self.previewFade then
		alpha = stateSpecs.notTarget.alpha or 1
	end
	if states.casting and stateSpecs.casting and stateSpecs.casting.alpha then
		alpha = math.max(alpha, stateSpecs.casting.alpha)
	end
	if states.focus and stateSpecs.focus and stateSpecs.focus.alpha then
		alpha = math.max(alpha, stateSpecs.focus.alpha)
	end
	if quiet then
		alpha = math.min(alpha, P.Roles.QUIET.alpha)
	end

	local art = self.art
	local Scheduler = P.Scheduler
	if instant or not self.emW then
		Scheduler:StopEase(self.easeSizeId)
		Scheduler:StopEase(self.easeAlphaId)
		self.emW, self.emH, self.emA = width, height, alpha
		self.emToW, self.emToH, self.emToA = width, height, alpha
		art:SetSize(width, height)
		art:SetAlpha(alpha)
		return
	end
	-- Ease from the values we last applied. Size and alpha read back from a frame inside
	-- Blizzard's plate tree can be secret on 12.1, so they are never read. Nothing starts when
	-- the goal is the one already set (most plates on a target change).
	if width ~= self.emToW or height ~= self.emToH then
		self.emFromW, self.emFromH = self.emW, self.emH
		self.emToW, self.emToH = width, height
		Scheduler:Ease(self.easeSizeId, 0, 1, EASE_TIME, self.applySize)
	end
	if alpha ~= self.emToA then
		self.emToA = alpha
		Scheduler:Ease(self.easeAlphaId, self.emA or alpha, alpha, EASE_TIME, self.applyAlpha)
	end
end

---Run every part's Configure (aura filters and layout) now, or mark it for later while the game
---restricts changes. The Driver runs pending ones when the restriction lifts.
function Plate:Configure()
	if Secret.IsRestricted() then
		self.pendingConfigure = true
		return
	end
	self.pendingConfigure = nil
	if not self.style then
		return
	end
	local ctx = PointCtx(self)
	for i = 1, #self.active do
		local widget = self.active[i]
		if widget.impl.Configure then
			widget.impl.Configure(widget, widget.spec, ctx)
		end
	end
end

---Refresh after a settings change on a plate that keeps its style key (colors, aura settings).
---@param reasons table<string, boolean>
function Plate:Refresh(reasons)
	if reasons.colors then
		-- New color programs need new event maps; the same programs keep the maps and the unit
		-- event registrations (a context change that left the programs alone makes no tables)
		if not self:EventMapsCurrent() then
			self:RebuildEvents()
		end
		self:UpdateAll('COLORS')
	end
	if reasons.auras then
		self:Configure()
	end
	if not self.style then
		return
	end
	for i = 1, #self.active do
		local widget = self.active[i]
		local wanted = widget.impl.reasons
		if wanted then
			for reason in pairs(reasons) do
				if wanted[reason] and reason ~= 'look' and reason ~= 'size' then
					local ctx = PointCtx(self)
					widget.impl.Layout(widget, widget.spec, ctx)
					ctx:ApplyCommon(widget, widget.spec, i)
					break
				end
			end
		end
	end
end
