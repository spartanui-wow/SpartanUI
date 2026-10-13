local _, ns = ...
local P = ns.Plates
local Secret = P.Secret

-- Glows (5.5, 4): one shared glow implementation (P.GlowLib) and the 'glow' part for every source
-- except threat (Threat.lua). Owner: Phase 2 (pandemic on aura buttons in Phase 5).
--
-- P.GlowLib draws a glow around any region (the plate, another part, an aura button, a cast bar).
-- It is the only glow drawing code in the module: the threat glow, glow parts and the soft glow
-- target highlight use it, and the cast bar's important-cast glow and the aura rows' purge and
-- pandemic glows should too, so every glow looks and moves the same way.
--   glow = GlowLib.Create(parent)                  frames only (gate -> fade -> pulse -> pieces)
--   GlowLib.Layout(glow, region, opts, ctx)        opts = { look, size, art, blend, animate }
--   GlowLib.SetColor(glow, r, g, b, a)             plain colors (kept for pieces made later)
--   GlowLib.SetColorSecret(glow, rS, gS, bS, aS)   colors that may be secret (SetVertexColor only)
--   GlowLib.Show(glow) / GlowLib.Hide(glow, instant)
--   GlowLib.ShowWhenSecret(glow, conditionSecret)  shown when a possibly-secret boolean is true
--   GlowLib.Reset(glow)                            hide now, stop motion (unbind)
-- Frames: `gate` takes the secret answer (SetAlphaFromBoolean, never read back), `fade` eases in
-- and out on the shared scheduler (a plain alpha we track ourselves), `pulse` carries the look's
-- alpha animation (an AnimationGroup, so nothing runs an OnUpdate). Pieces are textures tinted with
-- SetVertexColor, the one tint call that takes secret colors.
--
-- Looks (GlowLib.LOOKS): soft (threat, soft highlight), important (casts), purge (buffs you can
-- remove), pandemic (refresh window). The art set paints one picture per look (Data/ArtAliases.lua
-- SLOTS.glow, LibSharedMedia type ArtAliases.MEDIA.glow); until it does, each look is drawn from
-- stepped rings of plain textures, so every look always draws.
--
-- The 'glow' part (kind 'glow', source ~= 'threat'):
--   importantCast  while a cast runs, shown through P.Secret.SetAlphaFromBoolean from
--                  src:IsImportantSecret(). On the Classic family the API answers but the spell
--                  data is unknown (S11): the glow simply shows for whatever the game flags.
--   purge          the unit has a buff you can remove: Lua scan with the removable row's own test
--                  (P.AuraRows.ROWS.removable.scan) where aura data is plain; previews use the
--                  sample's removable icons. Where secrets exist the game hides those details, so
--                  the glow stays off (logged once, GlowLib.Limit says why); the removable aura
--                  row marks those buffs instead.
--   pandemic       one of your debuffs is in its last 30% (refresh without losing time): plain
--                  scan plus one shared scheduler check; previews use sample timers. Where secrets
--                  exist: off (logged once); aura rows draw it per icon (Phase 5).
--   target         shown while the plate is your target (S4: from the secret answer).
-- The glow surrounds spec.anchor[2] (a part id) when set, else the whole plate.

---@class Plates.Glow
---@field gate table
---@field fade table
---@field pulse table
---@field pieces table[]
---@field count integer Pieces in use
---@field picture table Texture used when the art set has a picture for the look
---@field textures table[] Textures in use (for pixel snapping)
---@field anim? table AnimationGroup on pulse
---@field alphaAnim? table
---@field pulseSpec? table
---@field look table
---@field shown boolean We asked it to show (plain)
---@field built boolean Pieces match the last Layout request
---@field req? table The last Layout request (region, look, size, blend, path, slot, pixel)
---@field fadeAlpha number Last fade alpha we applied (never read back)
---@field key string Scheduler id prefix
---@field r number Last plain color (applied to pieces made later)
---@field g number
---@field b number
---@field a number

---@class Plates.GlowLib
local GlowLib = {}
P.GlowLib = GlowLib

GlowLib.WHITE = 'Interface\\Buttons\\WHITE8X8'
GlowLib.FADE_IN = 0.12
GlowLib.FADE_OUT = 0.2
---Share of a debuff's full time that counts as its refresh window.
GlowLib.PANDEMIC = 0.3

---How each look draws. rings: alpha per ring, inside first; edge: a crisp line right at the
---region's edge; corners: bright squares on the corners; pulse: alpha animation (to, duration).
GlowLib.LOOKS = {
	soft = { rings = { 0.5, 0.3, 0.16, 0.07 } },
	important = { rings = { 0.7, 0.42, 0.2 }, edge = 0.95, pulse = { to = 0.35, duration = 0.45 } },
	purge = { rings = { 0.55, 0.22 }, corners = 0.95, pulse = { to = 0.45, duration = 0.7 } },
	pandemic = { rings = { 0.3 }, edge = 1, pulse = { to = 0.3, duration = 0.8 } },
}
GlowLib.LOOK_ORDER = { 'soft', 'important', 'purge', 'pandemic' }

---The look each glow source uses when the part names none.
GlowLib.SOURCE_LOOKS = { threat = 'soft', importantCast = 'important', purge = 'purge', pandemic = 'pandemic', target = 'soft' }

---Colors for glows other parts draw (the cast bar's important-cast glow, the aura rows' purge and
---pandemic glows). Glow parts use spec.color.
GlowLib.SOURCE_COLORS = {
	importantCast = { 1, 0.55, 0.1, 1 },
	purge = { 0.3, 0.75, 1, 1 },
	pandemic = { 1, 0.85, 0.25, 1 },
}

local made = 0

---Build a glow's frames. Nothing shows until Show or ShowWhenSecret.
---@param parent table
---@return Plates.Glow
function GlowLib.Create(parent)
	made = made + 1
	local gate = CreateFrame('Frame', nil, parent)
	gate:SetAllPoints(parent)
	local fade = CreateFrame('Frame', nil, gate)
	fade:SetAllPoints(gate)
	local pulse = CreateFrame('Frame', nil, fade)
	pulse:SetAllPoints(fade)
	local picture = pulse:CreateTexture(nil, 'ARTWORK')
	picture:Hide()
	gate:Hide()
	fade:SetAlpha(0)
	local glow = {
		gate = gate,
		fade = fade,
		pulse = pulse,
		pieces = {},
		count = 0,
		picture = picture,
		textures = {},
		look = GlowLib.LOOKS.soft,
		shown = false,
		fadeAlpha = 0,
		key = 'glow' .. made,
		r = 1,
		g = 1,
		b = 1,
		a = 1,
	}
	-- Made once, so showing and hiding a glow makes no closures or strings
	glow.fadeId = glow.key .. 'f'
	glow.applyFade = function(value)
		glow.fadeAlpha = value
		fade:SetAlpha(value)
	end
	glow.hidden = function()
		gate:Hide()
		if glow.anim then
			glow.anim:Stop()
		end
	end
	return glow
end

local function Piece(glow, index)
	local piece = glow.pieces[index]
	if not piece then
		piece = glow.pulse:CreateTexture(nil, 'ARTWORK')
		piece:SetTexture(GlowLib.WHITE)
		piece:SetVertexColor(glow.r, glow.g, glow.b, glow.a)
		glow.pieces[index] = piece
	end
	piece:ClearAllPoints()
	piece:Show()
	return piece
end

---A rectangular ring between `inner` and `outer` pixels outside the region. Top and bottom span
---the corners, left and right fill between them, so nothing overlaps.
local function Ring(glow, index, region, inner, outer, alpha)
	local top = Piece(glow, index)
	top:SetPoint('TOPLEFT', region, 'TOPLEFT', -outer, outer)
	top:SetPoint('BOTTOMRIGHT', region, 'TOPRIGHT', outer, inner)
	local bottom = Piece(glow, index + 1)
	bottom:SetPoint('TOPLEFT', region, 'BOTTOMLEFT', -outer, -inner)
	bottom:SetPoint('BOTTOMRIGHT', region, 'BOTTOMRIGHT', outer, -outer)
	local left = Piece(glow, index + 2)
	left:SetPoint('TOPLEFT', region, 'TOPLEFT', -outer, inner)
	left:SetPoint('BOTTOMRIGHT', region, 'BOTTOMLEFT', -inner, -inner)
	local right = Piece(glow, index + 3)
	right:SetPoint('TOPLEFT', region, 'TOPRIGHT', inner, inner)
	right:SetPoint('BOTTOMRIGHT', region, 'BOTTOMRIGHT', outer, -inner)
	top:SetAlpha(alpha)
	bottom:SetAlpha(alpha)
	left:SetAlpha(alpha)
	right:SetAlpha(alpha)
	return index + 4
end

local CORNERS = { 'TOPLEFT', 'TOPRIGHT', 'BOTTOMLEFT', 'BOTTOMRIGHT' }

local function Corners(glow, index, region, size, alpha)
	for _, corner in ipairs(CORNERS) do
		local piece = Piece(glow, index)
		piece:SetSize(size, size)
		-- Centered on the corner: half inside, half outside
		piece:SetPoint('CENTER', region, corner, 0, 0)
		piece:SetAlpha(alpha)
		index = index + 1
	end
	return index
end

---The art set's picture for a glow key, when it has one (LibSharedMedia first, then the slot's
---own file under the host's media path).
---@param key string|nil
---@param ctx? Plates.LayoutContext
---@return string|nil path
---@return table|nil slot
function GlowLib.Picture(key, ctx)
	if type(key) ~= 'string' then
		return nil, nil
	end
	local Art = P.Data.ArtAliases
	key = Art:Resolve(key)
	local slot = Art:Slot('glow', key)
	local path
	if ctx then
		path = ctx:Texture(key, Art.MEDIA.glow)
	else
		-- No plate layout (aura buttons, cast bars drawn elsewhere): ask the media library directly
		local media = P.services.media
		if media and media.IsValid and media:IsValid(Art.MEDIA.glow, key) then
			path = media:Fetch(Art.MEDIA.glow, key)
		end
	end
	if not path and slot and slot.file and P.host and P.host.mediaPath then
		path = P.host.mediaPath .. slot.file
	end
	return path, slot
end

local function SetupPulse(glow, look, animate)
	local pulse = look.pulse
	if animate == 'none' then
		pulse = nil
	elseif animate == 'pulse' and not pulse then
		pulse = GlowLib.LOOKS.important.pulse
	end
	glow.pulseSpec = pulse
	if not pulse then
		if glow.anim then
			glow.anim:Stop()
		end
		return
	end
	if not glow.anim and glow.pulse.CreateAnimationGroup then
		local group = glow.pulse:CreateAnimationGroup()
		local alpha = group:CreateAnimation('Alpha')
		if alpha.SetSmoothing then
			alpha:SetSmoothing('IN_OUT')
		end
		group:SetLooping('BOUNCE')
		glow.anim, glow.alphaAnim = group, alpha
	end
	if glow.alphaAnim then
		glow.alphaAnim:SetFromAlpha(1)
		glow.alphaAnim:SetToAlpha(pulse.to)
		glow.alphaAnim:SetDuration(pulse.duration)
	end
	if glow.shown and glow.anim and not glow.anim:IsPlaying() then
		glow.anim:Play()
	end
end

---Draw the pieces for the last Layout request (lazily, the first time the glow shows or takes a
---secret color, so hidden glows on many plates cost no textures).
---@param glow Plates.Glow
local function Build(glow)
	local req = glow.req
	glow.built = true
	P.util.Wipe(glow.textures)
	if not req then
		glow.count = 0
		return
	end
	local region, look, size, blend = req.region, req.look, req.size, req.blend
	local used = 0
	if req.path then
		local picture = glow.picture
		picture:SetTexture(req.path)
		picture:ClearAllPoints()
		local spread = size * 2
		picture:SetPoint('TOPLEFT', region, 'TOPLEFT', -spread, spread)
		picture:SetPoint('BOTTOMRIGHT', region, 'BOTTOMRIGHT', spread, -spread)
		local margins = req.slot and req.slot.margins
		if margins and picture.SetTextureSliceMargins then
			picture:SetTextureSliceMargins(margins[1], margins[2], margins[3], margins[4])
			if picture.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
				picture:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
			end
		end
		picture:SetBlendMode(blend)
		picture:SetVertexColor(glow.r, glow.g, glow.b, glow.a)
		picture:Show()
		glow.textures[1] = picture
	else
		glow.picture:Hide()
		local rings = look.rings
		local n = math.min(#rings, size)
		local step = size / n
		local index = 1
		if look.edge then
			index = Ring(glow, index, region, 0, req.pixel, look.edge)
		end
		for i = 1, n do
			local inner = math.floor((i - 1) * step + 0.5)
			local outer = math.floor(i * step + 0.5)
			if outer > inner then
				index = Ring(glow, index, region, inner, outer, rings[i])
			end
		end
		if look.corners then
			index = Corners(glow, index, region, math.max(2, math.floor(size * 0.75 + 0.5)), look.corners)
		end
		used = index - 1
		for i = 1, used do
			local piece = glow.pieces[i]
			piece:SetBlendMode(blend)
			piece:SetVertexColor(glow.r, glow.g, glow.b, glow.a)
			glow.textures[i] = piece
		end
	end
	for i = used + 1, #glow.pieces do
		glow.pieces[i]:Hide()
	end
	glow.count = used
end

---Set how a glow draws around a region. Call again whenever the look, size or region changes.
---Pieces are made the first time the glow shows (Build).
---@param glow Plates.Glow
---@param region table The region the glow surrounds
---@param opts table { look = 'soft'|'important'|'purge'|'pandemic', size = px, art = key, blend = 'BLEND'|'ADD', animate = 'none'|'pulse' }
---@param ctx? Plates.LayoutContext For art lookups and the pixel size
function GlowLib.Layout(glow, region, opts, ctx)
	opts = opts or {}
	local lookId = GlowLib.LOOKS[opts.look] and opts.look or 'soft'
	local look = GlowLib.LOOKS[lookId]
	local req = glow.req or {}
	glow.req = req
	glow.look = look
	req.region, req.look = region, look
	req.size = math.max(math.floor((opts.size or 4) + 0.5), 1)
	req.blend = opts.blend == 'ADD' and 'ADD' or 'BLEND'
	req.path, req.slot = GlowLib.Picture(opts.art or lookId, ctx)
	-- The layout context points at another plate later, so read the pixel size now
	req.pixel = look.edge and ctx and ctx:Pixel() or 1
	glow.built = false
	SetupPulse(glow, look, opts.animate)
	if glow.shown then
		Build(glow)
	else
		P.util.Wipe(glow.textures)
		glow.count = 0
		glow.picture:Hide()
		for i = 1, #glow.pieces do
			glow.pieces[i]:Hide()
		end
	end
end

---Tint with plain colors (kept, so pieces made later match).
---@param glow Plates.Glow
---@param r number
---@param g number
---@param b number
---@param a? number
function GlowLib.SetColor(glow, r, g, b, a)
	glow.r, glow.g, glow.b, glow.a = r, g, b, a or 1
	if glow.built then
		GlowLib.SetColorSecret(glow, r, g, b, a or 1)
	end
end

---Tint with colors that may be secret. Only SetVertexColor sees them and nothing is kept, so the
---owner sets the color again after every Layout.
---@param glow Plates.Glow
function GlowLib.SetColorSecret(glow, rSecret, gSecret, bSecret, aSecret)
	if not glow.built then
		Build(glow)
	end
	for i = 1, glow.count do
		glow.pieces[i]:SetVertexColor(rSecret, gSecret, bSecret, aSecret)
	end
	glow.picture:SetVertexColor(rSecret, gSecret, bSecret, aSecret)
end

local scratchOpts = {}

---The options table for one GlowLib.Layout call, filled in place (Layout reads it at once and
---keeps nothing), so laying a glow out makes no table.
---@return table opts
function GlowLib.Opts(look, size, art, blend, animate)
	local opts = scratchOpts
	opts.look, opts.size, opts.art, opts.blend, opts.animate = look, size, art, blend, animate
	return opts
end

local function FadeTo(glow, target, duration, done)
	P.Scheduler:Ease(glow.fadeId, glow.fadeAlpha or 0, target, duration, glow.applyFade, done)
end

local function StartPulse(glow)
	if glow.pulseSpec and glow.anim and not glow.anim:IsPlaying() then
		glow.anim:Play()
	end
end

---Show the glow (a plain decision).
---@param glow Plates.Glow
---@param instant? boolean Skip the fade in
function GlowLib.Show(glow, instant)
	if not glow.built then
		Build(glow)
	end
	glow.gate:Show()
	glow.gate:SetAlpha(1)
	if not glow.shown or instant then
		glow.shown = true
		FadeTo(glow, 1, instant and 0 or GlowLib.FADE_IN)
	end
	StartPulse(glow)
end

---Show the glow when a possibly-secret boolean is true. The answer only reaches the engine.
---@param glow Plates.Glow
---@param conditionSecret any
function GlowLib.ShowWhenSecret(glow, conditionSecret)
	if not glow.built then
		Build(glow)
	end
	glow.gate:Show()
	Secret.SetAlphaFromBoolean(glow.gate, conditionSecret, 1, 0)
	if not glow.shown then
		glow.shown = true
		FadeTo(glow, 1, GlowLib.FADE_IN)
	end
	StartPulse(glow)
end

---Hide the glow: a short fade, or at once.
---@param glow Plates.Glow
---@param instant? boolean
function GlowLib.Hide(glow, instant)
	if not glow.shown and not instant then
		return
	end
	glow.shown = false
	if instant or (glow.fadeAlpha or 0) <= 0 then
		P.Scheduler:StopEase(glow.fadeId)
		glow.fadeAlpha = 0
		glow.fade:SetAlpha(0)
		glow.hidden()
		return
	end
	FadeTo(glow, 0, GlowLib.FADE_OUT, glow.hidden)
end

---Whether we asked the glow to show (plain; a secret gate may still keep it invisible).
---@param glow Plates.Glow
---@return boolean
function GlowLib.IsShown(glow)
	return glow.shown
end

---Hide at once and stop all motion (unbind).
---@param glow Plates.Glow
function GlowLib.Reset(glow)
	GlowLib.Hide(glow, true)
end

---Why a glow source cannot show on this client, as a sentence for the player, or nil when it can.
---@param source string
---@return string|nil
function GlowLib.Limit(source)
	local hidden = P.Caps:Get('secrets')
	if source == 'purge' and hidden then
		return P.L['The game hides enemy buff details here, so this glow shows on the removable buffs row instead.']
	elseif source == 'pandemic' and hidden then
		return P.L['The game hides aura timers here, so this glow shows on your debuff icons instead.']
	elseif source == 'importantCast' and not P.Caps:Get('important') then
		return P.L['This game version cannot tell which casts are important.']
	elseif source == 'importantCast' and not P.Caps:Get('importantSeen') then
		-- S11: the question exists here, but no cast has been marked important yet this session
		return P.L['This game version may never mark a cast as important, so this may not show.']
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- The glow part
----------------------------------------------------------------------------------------------------

local CAST_EVENTS = {
	'UNIT_SPELLCAST_START',
	'UNIT_SPELLCAST_STOP',
	'UNIT_SPELLCAST_FAILED',
	'UNIT_SPELLCAST_INTERRUPTED',
	'UNIT_SPELLCAST_CHANNEL_START',
	'UNIT_SPELLCAST_CHANNEL_STOP',
	'UNIT_SPELLCAST_EMPOWER_START',
	'UNIT_SPELLCAST_EMPOWER_STOP',
}
local AURA_EVENTS = { 'UNIT_AURA' }
local NO_EVENTS = {}

local warned = {}

local function WarnOnce(source)
	if warned[source] then
		return
	end
	warned[source] = true
	P.log.info('The ' .. source .. ' glow is off on this client: ' .. tostring(GlowLib.Limit(source)))
end

local function Hostile(widget)
	local facts = widget.plate.facts
	return facts.canAttack == true or (type(facts.reaction) == 'number' and facts.reaction <= 3)
end

---Lua scan (plain aura data only): true as soon as test(aura, arg) is true. Tests are functions
---made once (no closure per scan).
local function AnyAura(src, filter, test, arg)
	for index = 1, 40 do
		local aura = src:AuraByIndexPlain(index, filter)
		if not aura then
			return false
		end
		if test(aura, arg) then
			return true
		end
	end
	return false
end

local NO_AURAS = {} -- read only

-- Reused env for the scan path's removable test (row settings: the player's always and never lists)
local purgeEnv = { settings = {}, tank = {}, tokenIDs = {}, hostile = true }

local function ScanRowAccepts(aura, accept)
	return accept(aura, purgeEnv) == true
end

local function ContainerRowAccepts(aura, row)
	return row.scan(aura, P.Context) == true
end

---The removable test the glow uses: the scan path's own row test (Engine/Parts/AurasScan.lua), so
---the glow and the row agree on what counts, else the container row's simpler test.
---@return function|nil test
---@return any arg
---@return string filter
local function PurgeTest()
	local scanRow = P.AuraScan and P.AuraScan.ROWS and P.AuraScan.ROWS.removable
	if scanRow and scanRow.Accept and P.AuraScan.RowSettings then
		P.AuraScan.RowSettings('removable', purgeEnv.settings)
		return ScanRowAccepts, scanRow.Accept, 'HELPFUL'
	end
	local rows = P.AuraRows and P.AuraRows.ROWS
	local row = rows and rows.removable
	if not row then
		return nil, nil, 'HELPFUL'
	end
	return ContainerRowAccepts, row, row.scanFilter or 'HELPFUL'
end

local function PurgeShown(widget, src)
	if not Hostile(widget) then
		return false
	end
	if src.isSample then
		local icons = src:SampleAuras('removable')
		return icons ~= nil and #icons > 0
	end
	local test, arg, filter = PurgeTest()
	if not test then
		return false
	end
	return AnyAura(src, filter, test, arg)
end

-- One pandemic check at a time: its results live here (no closure per scan)
local pandemic = { now = 0, inWindow = false, nextAt = nil }

local function PandemicCheck(remaining, duration)
	if type(duration) ~= 'number' or duration <= 0 or type(remaining) ~= 'number' then
		return
	end
	local share = GlowLib.PANDEMIC
	if remaining <= duration * share then
		if remaining > 0 then
			pandemic.inWindow = true
		end
	else
		local enter = pandemic.now + remaining - duration * share
		pandemic.nextAt = pandemic.nextAt and math.min(pandemic.nextAt, enter) or enter
	end
end

local function PandemicVisit(aura, ids)
	ids[#ids + 1] = aura.auraInstanceID
	if type(aura.expirationTime) == 'number' and aura.expirationTime > 0 then
		PandemicCheck(aura.expirationTime - pandemic.now, aura.duration)
	end
	return false
end

---Whether one of the player's debuffs is in its refresh window, and when the next one enters it.
---Keeps the instance ids of the player's debuffs on the widget (AuraRelevant reads them).
---@return boolean inWindow
---@return number|nil nextAt
local function PandemicState(widget, src, now)
	pandemic.now, pandemic.inWindow, pandemic.nextAt = now, false, nil
	if src.isSample then
		for _, aura in ipairs(src:SampleAuras('myDebuffs') or NO_AURAS) do
			PandemicCheck(aura.remaining, aura.duration)
		end
		return pandemic.inWindow, nil
	end
	local ids = widget.mineIDs
	if not ids then
		ids = {}
		widget.mineIDs = ids
	end
	P.util.Wipe(ids)
	AnyAura(src, 'HARMFUL|PLAYER', PandemicVisit, ids)
	return pandemic.inWindow, pandemic.nextAt
end

---True when one of `ids` (a payload list) is in `list`.
local function AnyListed(list, ids)
	if type(ids) ~= 'table' then
		return false
	end
	for i = 1, #ids do
		local id = ids[i]
		for j = 1, #list do
			if list[j] == id then
				return true
			end
		end
	end
	return false
end

---Can this UNIT_AURA change a purge or pandemic glow? These glows only run where aura data is
---plain (Classic family; previews get no events), so the payload can be read. The purge glow can
---only appear from an added removable buff and only go away on a removal; the pandemic glow
---follows the player's own debuffs (added ones, and changes to the ones it saw).
---@param widget table
---@param info table|nil updateInfo
---@return boolean
local function AuraRelevant(widget, info)
	if P.Caps:Get('secrets') then
		return false -- the glow is off here (Refresh hid it when the part was laid out)
	end
	if type(info) ~= 'table' or info.isFullUpdate then
		return true
	end
	local added = info.addedAuras
	if type(added) ~= 'table' then
		added = NO_AURAS
	end
	if widget.spec.source == 'purge' then
		if GlowLib.IsShown(widget.glow) then
			local removed = info.removedAuraInstanceIDs
			local updated = info.updatedAuraInstanceIDs
			return (type(removed) == 'table' and removed[1] ~= nil) or (type(updated) == 'table' and updated[1] ~= nil)
		end
		if not Hostile(widget) then
			return false
		end
		local test, arg = PurgeTest()
		local updated = info.updatedAuraInstanceIDs
		if type(updated) == 'table' then
			for i = 1, #updated do
				local aura = widget.plate.src:AuraByInstancePlain(updated[i])
				if test and aura and aura.isHelpful and test(aura, arg) then
					return true
				end
			end
		end
		for i = 1, #added do
			local aura = added[i]
			if test and type(aura) == 'table' and aura.isHelpful and test(aura, arg) then
				return true
			end
		end
		return false
	end
	local IsMine = P.AuraScan and P.AuraScan.IsMine
	for i = 1, #added do
		local aura = added[i]
		if type(aura) == 'table' and aura.isHarmful and (not IsMine or IsMine(aura)) then
			return true
		end
	end
	local ids = widget.mineIDs
	return ids ~= nil and (AnyListed(ids, info.updatedAuraInstanceIDs) or AnyListed(ids, info.removedAuraInstanceIDs))
end

-- Plates waiting for a debuff to enter its refresh window: one shared check, never an OnUpdate.
local waiting = setmetatable({}, { __mode = 'k' })
local due = {}
local Refresh

local function CheckWaiting(now)
	local any = false
	for widget, at in pairs(waiting) do
		any = true
		if now >= at then
			due[#due + 1] = widget
		end
	end
	for i = #due, 1, -1 do
		local widget = due[i]
		due[i] = nil
		waiting[widget] = nil
		if widget.active and widget.plate.src then
			Refresh(widget, widget.plate.src)
		end
	end
	if not any then
		P.Scheduler:Cancel('Glow.pandemic')
	end
end

local function Wait(widget, at)
	waiting[widget] = at
	if not P.Scheduler:IsRunning('Glow.pandemic') then
		P.Scheduler:Every('Glow.pandemic', 0.2, CheckWaiting)
	end
end

Refresh = function(widget, src)
	local glow = widget.glow
	local source = widget.spec.source
	if source == 'importantCast' then
		if src:CastKind() and (src.isSample or P.Caps:Get('important')) then
			GlowLib.ShowWhenSecret(glow, src:IsImportantSecret())
		else
			GlowLib.Hide(glow)
		end
	elseif source == 'purge' then
		if not src.isSample and P.Caps:Get('secrets') then
			WarnOnce(source)
			GlowLib.Hide(glow, true)
		elseif PurgeShown(widget, src) then
			GlowLib.Show(glow)
		else
			GlowLib.Hide(glow)
		end
	elseif source == 'pandemic' then
		waiting[widget] = nil
		if not src.isSample and P.Caps:Get('secrets') then
			WarnOnce(source)
			GlowLib.Hide(glow, true)
			return
		end
		local now = P.services.GetTime()
		local inWindow, nextAt = PandemicState(widget, src, now)
		if inWindow then
			GlowLib.Show(glow)
		else
			GlowLib.Hide(glow)
		end
		if nextAt then
			Wait(widget, nextAt)
		end
	elseif source == 'target' then
		if widget.plate.states.target then
			GlowLib.Show(glow)
		elseif not widget.targetUnknown then
			GlowLib.Hide(glow)
		end
	end
end

---The look a glow part draws: its art when that names a look, else the source's own look.
---@param spec table
---@return string
function GlowLib.LookFor(spec)
	if spec.art and GlowLib.LOOKS[spec.art] then
		return spec.art
	end
	return GlowLib.SOURCE_LOOKS[spec.source] or 'soft'
end

P.Parts:Register({
	id = 'glow',
	kinds = { 'glow' },
	match = function(spec)
		return spec.source ~= 'threat'
	end,
	events = function(spec)
		if spec.source == 'importantCast' then
			return CAST_EVENTS
		elseif spec.source == 'purge' or spec.source == 'pandemic' then
			return AURA_EVENTS
		end
		return NO_EVENTS
	end,
	Create = function(plate)
		local holder = CreateFrame('Frame', nil, plate.art)
		return { frame = holder, glow = GlowLib.Create(holder), textures = {} }
	end,
	Layout = function(widget, spec, ctx)
		local anchor = spec.anchor
		local region = ctx:Region(anchor and anchor[2] or 'plate')
		local x, y = anchor and anchor[4] or 0, anchor and anchor[5] or 0
		widget.frame:ClearAllPoints()
		widget.frame:SetPoint('TOPLEFT', region, 'TOPLEFT', x, y)
		widget.frame:SetPoint('BOTTOMRIGHT', region, 'BOTTOMRIGHT', x, y)
		GlowLib.Layout(widget.glow, widget.frame, GlowLib.Opts(GlowLib.LookFor(spec), spec.size, spec.art, spec.blend, spec.animate), ctx)
		widget.textures = widget.glow.textures
		GlowLib.SetColor(widget.glow, ctx:Color(spec.color or GlowLib.SOURCE_COLORS[spec.source]))
		if widget.plate.src then
			Refresh(widget, widget.plate.src)
		end
	end,
	Update = function(widget, src, event, _, info)
		-- Aura glows scan only when the change can matter to them
		if event == 'UNIT_AURA' and not AuraRelevant(widget, info) then
			return
		end
		Refresh(widget, src)
	end,
	OnState = function(widget, state)
		if state ~= 'target' or widget.spec.source ~= 'target' then
			return
		end
		widget.targetUnknown = nil
		if widget.plate.states.target then
			GlowLib.Show(widget.glow)
		else
			GlowLib.Hide(widget.glow)
		end
	end,
	OnStateSecret = function(widget, state, boolSecret)
		if state == 'target' and widget.spec.source == 'target' then
			widget.targetUnknown = true
			GlowLib.ShowWhenSecret(widget.glow, boolSecret)
		end
	end,
	Reset = function(widget)
		waiting[widget] = nil
		widget.targetUnknown = nil
		if widget.mineIDs then
			P.util.Wipe(widget.mineIDs)
		end
		GlowLib.Reset(widget.glow)
	end,
})
