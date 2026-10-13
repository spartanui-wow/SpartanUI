-- @runtime lua51
-- Painted nameplate plates (plan 5.3, 5.4, 5.5; Phase 10): each painted look (Atlas, Boughs,
-- Meridian) ships one plate picture cut from its unit frame plate by tools/painted/nameplates.py.
-- Its numbers in Themes/Painted.lua match the files, the style it builds passes the import check
-- untouched, the art part draws it as nine pieces whose corners keep their shape at every size
-- while the window stays on the health bar, the look offers it as a style of its own, and "Match
-- my look" draws it while that look is active.
local M, H = ...

if not (H.ModuleExists() and H.Exists(H.hostFile)) then
	describe('painted plates', function()
		pending('all', 'the nameplate module or its host does not exist yet')
	end)
	return
end

local ROOT = H.root
local LOOKS = { 'Atlas', 'Boughs', 'Meridian' }

local SUI, ns = H.LoadNameplatesLikeTheGame()
local P = ns.Plates
M.Login('SpartanUI')
M.Advance(1)

local Schema, Registry, Merge = P.Styles.Schema, P.Styles.Registry, P.Styles.Merge
local Highlight = P.Highlight

---The data half of Themes/Painted.lua, loaded the way the art tools load it (no SpartanUI).
local function LoadPaintedData()
	local chunk = assert(loadfile(ROOT .. 'Themes/Painted.lua'))
	local saved = rawget(_G, 'SUI')
	rawset(_G, 'SUI', nil)
	local ok, painted = pcall(chunk)
	rawset(_G, 'SUI', saved)
	assert(ok, painted)
	return painted
end

local Data = LoadPaintedData()

---Width, height, bit depth and color type from a PNG file's header.
local function PngHeader(path)
	local bytes = H.ReadFile(path)
	if not bytes or bytes:sub(1, 8) ~= '\137PNG\r\n\26\n' or bytes:sub(13, 16) ~= 'IHDR' then
		return nil
	end
	local function U32(at)
		local a, b, c, d = bytes:byte(at, at + 3)
		return ((a * 256 + b) * 256 + c) * 256 + d
	end
	return U32(17), U32(21), bytes:byte(25), bytes:byte(26)
end

local function PowerOfTwo(n)
	while n > 1 and n % 2 == 0 do
		n = n / 2
	end
	return n == 1
end

local function Root(look)
	return 'Interface\\AddOns\\SpartanUI\\Themes\\' .. look .. '\\Images\\'
end

local function Meta(look)
	return { root = Root(look), name = look, description = 'Painted ' .. look, accent = { 0.4, 0.6, 0.5 }, trim = { 0.6, 0.45, 0.3 }, frameLabel = 'Painted frame' }
end

local function Count(t)
	local n = 0
	for _ in pairs(t or {}) do
		n = n + 1
	end
	return n
end

describe('painted plates: pictures', function()
	it('has a plate for every painted look', function()
		for _, look in ipairs(LOOKS) do
			assert.not_nil(Data.NAMEPLATES[look], look)
		end
	end)

	it('carries the numbers of the last picture build (tools/painted/nameplates.py)', function()
		local built = assert(loadfile(ROOT .. 'tools/painted/out/nameplates.lua'))()
		assert.same(Data.NAMEPLATES, built)
	end)

	it('ships power-of-two RGBA files whose size and slices match the numbers in Painted.lua', function()
		for _, look in ipairs(LOOKS) do
			local art = Data.NAMEPLATES[look]
			local sl, out = art.slice, art.outset
			local w, h, depth, color = PngHeader(ROOT .. 'Themes/' .. look .. '/Images/Nameplate.png')
			assert.not_nil(w, look .. ' has Images/Nameplate.png')
			assert.equal(w, sl.file[1], look .. ' file width')
			assert.equal(h, sl.file[2], look .. ' file height')
			assert.is_true(PowerOfTwo(w) and PowerOfTwo(h), look .. ' is a power of two')
			assert.equal(depth, 8, look .. ' is 8 bits per channel')
			assert.equal(color, 6, look .. ' is RGBA')
			assert.is_true(sl.size[1] <= w and sl.size[2] <= h, look .. ' paints inside its file')
			assert.is_true(sl.left + sl.right < sl.size[1], look .. ' leaves a middle to stretch')
			assert.is_true(sl.top + sl.bottom < sl.size[2], look .. ' leaves a band to stretch')
			-- Every slice edge and the window land on whole drawn pixels
			for _, key in ipairs({ 'left', 'right', 'top', 'bottom' }) do
				local drawn = sl[key] * sl.scale
				assert.equal(drawn, math.floor(drawn), look .. ' ' .. key .. ' corner is whole pixels')
				assert.is_true(out[key] <= drawn, look .. ' ' .. key .. ' window edge sits inside its corner')
			end
			-- The corners fit around the smallest bar, so they are never cut
			assert.is_true((sl.top + sl.bottom) * sl.scale <= 8 + out.top + out.bottom, look .. ' fits a Small bar')
		end
	end)
end)

describe('painted plates: style', function()
	it('passes the import check untouched for every look', function()
		for _, look in ipairs(LOOKS) do
			local style = Data.NameplateStyle(look, Meta(look))
			local cleaned, report, reason = Schema:ValidateStyle(style)
			assert.not_nil(cleaned, look .. ': ' .. tostring(reason))
			assert.equal(report.dropped, 0, look .. ' dropped ' .. table.concat(report.droppedKeys, ', '))
			assert.equal(report.clamped, 0, look .. ' clamped')
			assert.equal(report.fixed, 0, look .. ' fixed')
			assert.same(cleaned.parts.frame.slice, Data.NAMEPLATES[look].slice)
			assert.same(cleaned.parts.frame.outset, Data.NAMEPLATES[look].outset)
		end
	end)

	it('names no plate for a look without a picture', function()
		assert.is_nil(Data.NameplateStyle('War', Meta('War')))
	end)

	it('draws the frame under the bar and keeps the name, cast bar and icons clear of the paint', function()
		local art = Data.NAMEPLATES.Meridian
		local style = Data.NameplateStyle('Meridian', Meta('Meridian'))
		local parts = style.parts
		assert.is_true(parts.frame.order < parts.health.order, 'the frame draws under the health bar')
		assert.equal(parts.name.anchor[5], math.max(art.band.top, art.band.name) + 1)
		assert.equal(parts.cast.anchor[5], -(art.band.bottom + 2))
		assert.equal(parts.marker.anchor[4], -(art.outset.left + 4))
		assert.equal(parts.cc.anchor[4], art.outset.right + 4)
		assert.equal(parts.arrows.anchor[2], 'frame', 'target arrows wrap the whole frame')
		assert.equal(parts.threat.anchor[2], 'frame', 'the threat glow wraps the whole frame')
		assert.equal(style.tokens.plate, Root('Meridian') .. 'Nameplate.png')
	end)
end)

describe('painted plates: drawing', function()
	local made = 0

	local function Plate(id, sizeKey, situation)
		made = made + 1
		local resolved = Merge:Resolve(id, situation or 'enemyNPC', sizeKey)
		local plate = P.Plate.New(UIParent, true)
		plate:ApplyStyle(resolved)
		return plate, resolved
	end

	local function Point(region, index)
		local point, relativeTo, relPoint, x, y = region:GetPoint(index)
		return { point, relativeTo, relPoint, x, y }
	end

	it('registers each look as a style and resolves its picture path at every size', function()
		for _, look in ipairs(LOOKS) do
			local style = Data.NameplateStyle(look, Meta(look))
			style.id = 'paintedTest' .. look
			local ok, reason = P.API:RegisterStyle(style)
			assert.is_true(ok, look .. ': ' .. tostring(reason))
			for _, size in ipairs({ 'small', 'medium', 'large' }) do
				local resolved = Merge:Resolve(style.id, 'enemyNPC', size)
				assert.equal(resolved.parts.frame.art, Root(look) .. 'Nameplate.png', look .. ' ' .. size)
			end
		end
	end)

	it('keeps every corner at its painted size while the plate grows and puts the window on the bar', function()
		for _, look in ipairs(LOOKS) do
			local art = Data.NAMEPLATES[look]
			local sl, out = art.slice, art.outset
			for _, size in ipairs({ 'small', 'medium', 'large' }) do
				local plate, resolved = Plate('paintedTest' .. look, size)
				local widget = plate:GetWidget('frame')
				assert.not_nil(widget and widget.pieces, look .. ' ' .. size .. ' is cut in nine')
				assert.is_false(widget.texture:IsShown(), 'the single picture steps aside')
				local holder = widget.frame
				local tl, br = Point(holder, 1), Point(holder, 2)
				assert.same({ tl[1], tl[3], tl[4], tl[5] }, { 'TOPLEFT', 'TOPLEFT', -out.left, out.top }, look .. ' window left and top')
				assert.same({ br[1], br[3], br[4], br[5] }, { 'BOTTOMRIGHT', 'BOTTOMRIGHT', out.right, -out.bottom }, look .. ' window right and bottom')
				assert.is_true(rawequal(tl[2], plate.art), 'the frame hangs from the plate, so it follows target growth')
				local health = resolved.parts.health
				assert.equal(health.fill, 'plate', 'the health bar fills the plate the window sits on')

				local L, R, T, B = sl.left * sl.scale, sl.right * sl.scale, sl.top * sl.scale, sl.bottom * sl.scale
				local corner = Point(widget.pieces.TL, 2)
				assert.same({ corner[1], corner[3], corner[4], corner[5] }, { 'BOTTOMRIGHT', 'TOPLEFT', L, -T }, look .. ' top left corner size')
				corner = Point(widget.pieces.BR, 1)
				assert.same({ corner[1], corner[3], corner[4], corner[5] }, { 'TOPLEFT', 'BOTTOMRIGHT', -R, B }, look .. ' bottom right corner size')
				-- Corners show their own texels; the middle shows the stretchable column
				local fw, fh = sl.file[1], sl.file[2]
				assert.same(M.Get(widget.pieces.TL, 'texCoord'), { 0, sl.left / fw, 0, sl.top / fh })
				assert.same(M.Get(widget.pieces.BR, 'texCoord'), { (sl.size[1] - sl.right) / fw, sl.size[1] / fw, (sl.size[2] - sl.bottom) / fh, sl.size[2] / fh })
				assert.same(M.Get(widget.pieces.C, 'texCoord'), { sl.left / fw, (sl.size[1] - sl.right) / fw, sl.top / fh, (sl.size[2] - sl.bottom) / fh })
				for i = 1, 9 do
					assert.matches(M.Get(widget.pieces[i], 'texture'), 'Nameplate%.png$')
					assert.is_true(widget.pieces[i]:IsShown(), look .. ' piece ' .. i .. ' shows')
				end
				assert.equal(#widget.textures, 9, 'pixel snapping reaches every piece')
			end
		end
	end)

	it('hides the frame with the bar on friendly players and hands its anchors on', function()
		local plate, resolved = Plate('paintedTestBoughs', 'medium', 'friendlyPlayer')
		assert.is_true(resolved.hidden.frame or resolved.parts.frame == nil, 'no frame without a bar')
		assert.not_equal(resolved.parts.threat.anchor[2], 'frame')
		local _ = plate
	end)
end)

describe('painted plates: slice geometry', function()
	local slice = { file = { 64, 64 }, size = { 64, 40 }, left = 28, right = 20, top = 14, bottom = 18, scale = 0.5 }

	it('draws corners at their painted size when there is room', function()
		local drawn, shown = Highlight.SliceGeometry(slice, 150, 20)
		assert.same(drawn, { left = 14, right = 10, top = 7, bottom = 9 })
		assert.same(shown, { left = 28, right = 20, top = 14, bottom = 18 })
	end)

	it('shows the outer part of each corner when the area is smaller than both', function()
		local drawn, shown = Highlight.SliceGeometry(slice, 12, 10)
		assert.equal(drawn.left + drawn.right, 12)
		assert.equal(drawn.top + drawn.bottom, 10)
		assert.equal(shown.left, drawn.left / slice.scale, 'texels follow the drawn size, never squashed')
		assert.equal(shown.bottom, drawn.bottom / slice.scale)
	end)

	it('keeps a plain picture on one texture and back again', function()
		local parts = {
			pic = { order = 1, kind = 'art', art = 'Interface\\AddOns\\NameplatesTestHost\\Media\\Pic.png', width = 40, height = 10 },
		}
		local resolved = Merge.ResolveRaw({ id = 'artTest', name = 'Art test', version = 1, schema = 1, plate = { sizes = { medium = { 132, 10 } } }, parts = parts }, nil, 'enemyNPC', 'medium', nil)
		resolved.key = 'artTest1'
		local plate = P.Plate.New(UIParent, true)
		plate:ApplyStyle(resolved)
		local widget = plate:GetWidget('pic')
		assert.is_true(widget.texture:IsShown())
		assert.is_nil(widget.pieces, 'no pieces made for a plain picture')
		parts.pic.slice = { file = { 64, 32 }, left = 8, right = 8, top = 4, bottom = 4, scale = 0.5 }
		resolved = Merge.ResolveRaw({ id = 'artTest', name = 'Art test', version = 1, schema = 1, plate = { sizes = { medium = { 132, 10 } } }, parts = parts }, nil, 'enemyNPC', 'medium', nil)
		resolved.key = 'artTest2'
		plate:ApplyStyle(resolved)
		assert.is_false(widget.texture:IsShown())
		assert.equal(Count(widget.pieces), 18, 'nine pieces, by index and by name')
		parts.pic.slice = nil
		resolved = Merge.ResolveRaw({ id = 'artTest', name = 'Art test', version = 1, schema = 1, plate = { sizes = { medium = { 132, 10 } } }, parts = parts }, nil, 'enemyNPC', 'medium', nil)
		resolved.key = 'artTest3'
		plate:ApplyStyle(resolved)
		assert.is_true(widget.texture:IsShown())
		for i = 1, 9 do
			assert.is_false(widget.pieces[i]:IsShown(), 'piece ' .. i .. ' steps aside')
		end
		assert.equal(#widget.textures, 1)
	end)
end)

describe('painted plates: SpartanUI looks', function()
	-- The whole of Themes/Painted.lua against the SpartanUI stand-in; the look modules are created
	-- after login and initialized by hand, so their artwork code never runs here
	local Painted
	local specs = {}

	local function LoadLooks()
		if Painted then
			return
		end
		H.LoadFile(ROOT .. 'Themes/Painted.lua', 'SpartanUI', {})
		Painted = SUI.ThemePainted
		local register = Painted.Register
		Painted.Register = function(spec)
			specs[spec.name] = spec
			return register(spec)
		end
		for _, look in ipairs(LOOKS) do
			H.LoadFile(ROOT .. 'Themes/' .. look .. '/Style.lua', 'SpartanUI', {})
		end
		Painted.Register = register
		for _, look in ipairs(LOOKS) do
			SUI:GetModule('Style.' .. look):OnInitialize()
		end
	end

	it('offers each look as a nameplate style of its own, named after the look', function()
		LoadLooks()
		for _, look in ipairs(LOOKS) do
			local style, source = Registry:Get('painted' .. look)
			assert.not_nil(style, look)
			assert.equal(source, 'host')
			assert.equal(style.name, specs[look].displayName)
			assert.is_nil(style.matchesHost, 'only Match my look follows the theme')
			assert.same(style.tokens.accent, { specs[look].accent[1], specs[look].accent[2], specs[look].accent[3], 1 }, 'in its own accent')
			assert.equal(style.parts.frame.art, '$plate')
		end
	end)

	it('draws the painted plate for Match my look while that look is active', function()
		LoadLooks()
		local spec = specs.Boughs
		H.sui.themes.Boughs = { nameplates = Painted.NameplateLook(spec, Root('Boughs')) }
		H.sui.activeStyle = 'Boughs'
		H.FireSUIEvent('ARTWORK_STYLE_CHANGED')
		M.Advance(0.2)
		assert.equal(Registry:ResolveId('host'), 'spartanui')
		local host = Registry:Get('spartanui')
		assert.not_nil(host.parts.frame, 'Match my look carries the frame')
		assert.is_true(host.matchesHost)
		assert.equal(host.tokens.accent, '$host', 'the accent follows the theme')
		local resolved = Merge:Resolve('host', 'enemyNPC', 'medium')
		assert.equal(resolved.parts.frame.art, Root('Boughs') .. 'Nameplate.png')
		assert.same(resolved.parts.frame.slice, Data.NAMEPLATES.Boughs.slice)
		H.sui.activeStyle = 'War'
		H.FireSUIEvent('ARTWORK_STYLE_CHANGED')
		M.Advance(0.2)
		assert.is_nil(Registry:Get('spartanui').parts.frame, 'another look takes its own plate')
	end)
end)
