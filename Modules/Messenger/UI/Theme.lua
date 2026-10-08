local _, ns = ...
local M = ns.Messenger

-- Visual tokens. Near-black translucent panes, flat and square, 1px hairlines. The only
-- saturated colors are the game's own chat colors, read live from the player's chat settings,
-- so every conversation wears the color of where its messages go.

---@class Messenger.Theme
local T = {}
M.Theme = T

local WHITE = 'Interface\\Buttons\\WHITE8X8'
T.WHITE = WHITE

T.color = {
	window = { 0.047, 0.051, 0.059 },
	list = { 0.066, 0.070, 0.082 },
	header = { 0.058, 0.062, 0.072 },
	hover = { 1, 1, 1, 0.045 },
	pressed = { 1, 1, 1, 0.08 },
	line = { 1, 1, 1, 0.08 },
	input = { 0, 0, 0, 0.35 },
	text = { 0.91, 0.90, 0.88 },
	muted = { 0.61, 0.61, 0.64 },
	-- Quietest readable text: about 5:1 on every pane, so times and hints stay legible over
	-- bright zones seen through the window
	faint = { 0.54, 0.54, 0.57 },
	popup = { 0.07, 0.075, 0.09, 0.98 },
	raised = { 1, 1, 1, 0.07 },
	selected = { 1, 1, 1, 0.1 },
	hoverSoft = { 1, 1, 1, 0.025 },
	edge = { 1, 1, 1, 0.12 },
	edgeStrong = { 1, 1, 1, 0.15 },
	focus = { 1, 1, 1, 0.35 },
	solid = { 1, 1, 1, 1 },
	pill = { 1, 1, 1, 0.92 },
	onLight = { 0.04, 0.04, 0.05 },
	danger = { 1, 0.45, 0.4 },
	mention = { 1, 0.72, 0.28, 0.1 },
	found = { 1, 1, 1, 0.1 },
	warn = { 1, 0.72, 0.28 },
	online = { 0.30, 0.82, 0.40 },
	away = { 1, 0.76, 0.25 },
	busy = { 0.92, 0.30, 0.30 },
	offline = { 0.40, 0.40, 0.42 },
}

-- Window surfaces a skin may recolor, with the look each one takes from the skin's colors
local SKINNED = {
	window = function(c)
		return c.surface[0], 1
	end,
	list = function(c)
		return c.surface[1]
	end,
	header = function(c)
		return c.bar or c.surface[1]
	end,
	popup = function(c)
		return c.surface[3], 0.98
	end,
	line = function(c)
		return c.trim, 0.35
	end,
	edge = function(c)
		return c.trim, 0.55
	end,
	edgeStrong = function(c)
		return c.trimHi or c.trim, 0.5
	end,
}

local DEFAULTS = {}
for key in pairs(SKINNED) do
	local color = T.color[key]
	DEFAULTS[key] = { color[1], color[2], color[3], color[4] }
end

local FALLBACK_KIND = {
	WHISPER = { 1, 0.5, 1 },
	BN_WHISPER = { 0, 1, 0.965 },
	GUILD = { 0.25, 1, 0.25 },
	OFFICER = { 0.25, 0.75, 0.25 },
	PARTY = { 0.667, 0.667, 1 },
	RAID = { 1, 0.498, 0 },
	INSTANCE_CHAT = { 1, 0.498, 0 },
	SAY = { 1, 1, 1 },
	YELL = { 1, 0.25, 0.25 },
	EMOTE = { 1, 0.5, 0.25 },
	CHANNEL = { 1, 0.75, 0.75 },
}

---The chat color for a conversation, as set in the player's chat options.
---@param convo MessengerConversation|nil
---@return number r, number g, number b
function T.KindColor(convo)
	if not convo then
		return unpack(T.color.muted)
	end
	local kind = M.KindByKey[convo.kind]
	local typeKey = kind and kind.colorType or 'SAY'
	if convo.kind == 'CHANNEL' and convo.target then
		local id = GetChannelName(convo.target)
		if id and id > 0 then
			typeKey = 'CHANNEL' .. id
		end
	end
	local info = ChatTypeInfo and ChatTypeInfo[typeKey]
	if info and info.r then
		return info.r, info.g, info.b
	end
	local fallback = FALLBACK_KIND[kind and kind.colorType or 'SAY'] or FALLBACK_KIND.SAY
	return fallback[1], fallback[2], fallback[3]
end

---@return number
function T.Alpha()
	return M.settings and M.settings.window.alpha or 0.94
end

----------------------------------------------------------------------------------------------------
-- Icons (Media/Icons.tga: 8 x 4 grid of 32px white glyphs, tinted with vertex color)
----------------------------------------------------------------------------------------------------

local ICONS = {
	close = 0,
	plus = 1,
	gear = 2,
	search = 3,
	pin = 4,
	popout = 5,
	dock = 6,
	more = 7,
	send = 8,
	chevron = 9,
	mute = 10,
	invite = 11,
	bubble = 12,
	info = 13,
	dot = 14,
	check = 15,
	sidebar = 16,
	bell = 17,
	bellOff = 18,
	at = 19,
}

---@param texture Texture
---@param name string
function T.SetIcon(texture, name)
	local index = ICONS[name] or 0
	local col = index % 8
	local row = math.floor(index / 8)
	texture:SetTexture(M.mediaPath .. 'Icons')
	texture:SetTexCoord(col / 8, (col + 1) / 8, row / 4, (row + 1) / 4)
end

---@return string path, number left, number right, number top, number bottom
function T.IconCoords(name)
	local index = ICONS[name] or 0
	local col = index % 8
	local row = math.floor(index / 8)
	return M.mediaPath .. 'Icons', col / 8, (col + 1) / 8, row / 4, (row + 1) / 4
end

----------------------------------------------------------------------------------------------------
-- Surfaces
----------------------------------------------------------------------------------------------------

-- Fills and lines drawn in a color a skin can change, so a new skin repaints them
local tokenKey = {}
for key in pairs(SKINNED) do
	tokenKey[T.color[key]] = key
end
local painted = setmetatable({}, { __mode = 'k' })

local function Track(tex, color)
	if tokenKey[color] then
		painted[tex] = color
	end
end

---@param parent Frame
---@param color table
---@param layer? string
---@param sublevel? number
---@return Texture
function T.Fill(parent, color, layer, sublevel)
	local tex = parent:CreateTexture(nil, layer or 'BACKGROUND', nil, sublevel)
	tex:SetTexture(WHITE)
	tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
	tex:SetAllPoints(parent)
	Track(tex, color)
	return tex
end

---One physical pixel in UI units.
---@return number
function T.Pixel()
	local _, height = GetPhysicalScreenSize()
	if not height or height == 0 then
		return 1
	end
	return 768 / height / UIParent:GetEffectiveScale()
end

---A 1px line. side is 'TOP', 'BOTTOM', 'LEFT' or 'RIGHT' of the parent.
---@param parent Frame
---@param side string
---@param color? table
---@return Texture
function T.Line(parent, side, color)
	color = color or T.color.line
	local tex = parent:CreateTexture(nil, 'BORDER')
	tex:SetTexture(WHITE)
	tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
	local px = T.Pixel()
	if side == 'TOP' or side == 'BOTTOM' then
		tex:SetPoint(side .. 'LEFT')
		tex:SetPoint(side .. 'RIGHT')
		tex:SetHeight(px)
	else
		tex:SetPoint('TOP' .. side)
		tex:SetPoint('BOTTOM' .. side)
		tex:SetWidth(px)
	end
	Track(tex, color)
	return tex
end

---1px border on all four sides.
---@param frame Frame
---@param color? table
function T.Border(frame, color)
	frame.borders = {
		T.Line(frame, 'TOP', color),
		T.Line(frame, 'BOTTOM', color),
		T.Line(frame, 'LEFT', color),
		T.Line(frame, 'RIGHT', color),
	}
end

----------------------------------------------------------------------------------------------------
-- Skins: Messenger's own look, or a window look from Lib's AddonTools (the same frames the host's
-- other windows use, without the crest or title plaque on top)
----------------------------------------------------------------------------------------------------

---@return table|nil
function T.Kit()
	return LibAT and LibAT.UI and LibAT.UI.Kit or nil
end

---The chosen skin: 'default' (Messenger's own), 'auto' (whatever the host's windows use) or a window look id.
---@return string
function T.SkinId()
	local id = M.settings and M.settings.window.skin or 'default'
	local Kit = T.Kit()
	if not Kit or (id ~= 'auto' and not Kit.registry[id]) then
		return 'default'
	end
	return id
end

---Every window look, sorted by name.
---@return { id: string, name: string }[]
function T.SkinList()
	local list = {}
	local Kit = T.Kit()
	if Kit then
		for id, config in pairs(Kit.registry) do
			list[#list + 1] = { id = id, name = config.name or id }
		end
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

local function Near(a, b)
	return math.abs((a or 1) - (b or 1)) < 0.01
end

local appliedSkin

---Recolors the window surfaces for a window look (nil for Messenger's own). Fills still showing
---the old color are repainted; ones a state has recolored (a chat-colored rule) are left alone.
---@param config? table
function T.ApplySkin(config)
	if config == appliedSkin then
		return
	end
	appliedSkin = config
	local old = {}
	for key, pick in pairs(SKINNED) do
		local token = T.color[key]
		old[key] = { token[1], token[2], token[3], token[4] }
		local source, alpha
		if config and config.colors then
			source, alpha = pick(config.colors)
		end
		if not source then
			source = DEFAULTS[key]
		end
		token[1], token[2], token[3] = source[1], source[2], source[3]
		token[4] = alpha or source[4]
	end
	for tex, token in pairs(painted) do
		local was = old[tokenKey[token]]
		local r, g, b, a = tex:GetVertexColor()
		if Near(r, was[1]) and Near(g, was[2]) and Near(b, was[3]) and Near(a, was[4]) then
			tex:SetVertexColor(token[1], token[2], token[3], token[4] or 1)
		end
	end
	M:Fire('SKIN_CHANGED')
end

----------------------------------------------------------------------------------------------------
-- Type
----------------------------------------------------------------------------------------------------

-- Body text uses the chat font so it matches the normal chat and covers the player's locale.
-- Names and titles use the game's standard UI face.
local ROLE = {
	body = { face = 'chat', offset = 0 },
	name = { face = 'ui', offset = -1 },
	title = { face = 'ui', offset = 0 },
	meta = { face = 'chat', offset = -2 },
	small = { face = 'ui', offset = -3 },
	initial = { face = 'ui', offset = -1 },
}

local fontStrings = setmetatable({}, { __mode = 'k' })

local function Face(kind)
	local fontObject = kind == 'chat' and ChatFontNormal or GameFontNormal
	local face = fontObject and fontObject:GetFont()
	return face or STANDARD_TEXT_FONT
end

---@return number
function T.BaseSize()
	return M.settings and M.settings.fontSize or 13
end

---Bar and row heights for the current text size, so larger text never clips.
---@return table { row, header, title, composer, search }
function T.Metrics()
	local s = T.BaseSize()
	return {
		row = math.max(46, math.floor((s - 1) * 1.3 + (s - 2) * 1.3 + 18)),
		slimRow = math.max(22, math.floor((s - 1) * 1.3 + 8)),
		iconRow = 36,
		header = math.max(46, math.floor((s + 1) * 1.3 + (s - 2) * 1.3 + 16)),
		title = math.max(32, math.floor(s * 1.3 + 16)),
		composer = math.max(36, math.floor(s * 1.3 + 18)),
		search = math.max(26, math.floor((s - 1) * 1.3 + 10)),
	}
end

---@param fs FontString
---@param role string
local function ApplyFont(fs, role)
	local spec = ROLE[role] or ROLE.body
	local size = math.max(8, T.BaseSize() + spec.offset + (fs.sizeBump or 0))
	fs:SetFont(Face(spec.face), size, '')
	fs:SetShadowColor(0, 0, 0, 0.85)
	fs:SetShadowOffset(1, -1)
end

---@param parent Frame
---@param role string body|name|title|meta|small|initial
---@param color? table
---@param layer? string
---@return FontString
function T.Text(parent, role, color, layer)
	local fs = parent:CreateFontString(nil, layer or 'OVERLAY')
	fontStrings[fs] = role
	ApplyFont(fs, role)
	color = color or T.color.text
	fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
	fs:SetJustifyH('LEFT')
	fs:SetWordWrap(false)
	return fs
end

---Makes one font string larger (or smaller) than its role, and re-applies it.
---@param fs FontString
---@param bump number
function T.Bump(fs, bump)
	fs.sizeBump = bump
	ApplyFont(fs, fontStrings[fs] or 'body')
end

---Re-applies fonts after the size setting changes.
function T.RefreshFonts()
	for fs, role in pairs(fontStrings) do
		ApplyFont(fs, role)
	end
	M:Fire('FONTS_CHANGED')
end

---@param fs FontString
---@param color table
function T.SetColor(fs, color)
	fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

----------------------------------------------------------------------------------------------------
-- Color helpers
----------------------------------------------------------------------------------------------------

---@return string hex 'ffrrggbb'
function T.Hex(r, g, b)
	return string.format('ff%02x%02x%02x', math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

---Name color for a class, falling back to the default text color.
---@param classFile string|nil
---@return number r, number g, number b
function T.NameColor(classFile)
	local r, g, b = M.Util.ClassColor(classFile)
	if r then
		return r, g, b
	end
	return T.color.text[1], T.color.text[2], T.color.text[3]
end

-- Other people's bubbles when they have no color
T.color.bubble = { 0.17, 0.17, 0.19 }

local function Linear(c)
	return c ^ 2.2
end

---The fill for a bubble of a chosen color: the color laid over the dark window, then darkened
---until light text (and the game's item and player link colors) stays easy to read on it.
---@param r number
---@param g number
---@param b number
---@return number r, number g, number b
function T.BubbleFill(r, g, b)
	local base = T.color.window
	local k = 0.55
	r, g, b = base[1] + (r - base[1]) * k, base[2] + (g - base[2]) * k, base[3] + (b - base[3]) * k
	local luminance = 0.2126 * Linear(r) + 0.7152 * Linear(g) + 0.0722 * Linear(b)
	local limit = 0.11
	if luminance > limit then
		local scale = (limit / luminance) ^ (1 / 2.2)
		r, g, b = r * scale, g * scale, b * scale
	end
	return r, g, b
end

---@param status string|nil
---@return table|nil
function T.StatusColor(status)
	return status and T.color[status] or nil
end
