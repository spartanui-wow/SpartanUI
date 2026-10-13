-- Strict mock of the WoW client for the nameplate harness.
--
-- Everything the mock exposes comes from the flavor's data file (Tests/Nameplates/data/<flavor>.lua,
-- generated from Blizzard's API documentation by api_matrix.py):
--   * a global function, namespace function, widget method, event or Enum value exists only when
--     that client documents it (or Blizzard's own code uses it, for engine functions the docs
--     leave out). Anything else is nil, so calling it errors instead of quietly doing nothing.
--   * documented things the mock has no behavior for are generic stubs: they return nothing and
--     are counted in M.rec.unmodeled so suites can see what they leaned on.
--   * on clients with secrets, functions and methods marked SecretArguments = AllowedWhenUntainted
--     or NotAllowed raise an error when addon code hands them a secret, like the game does.
--
-- Globals expected before this file runs: HARNESS_ROOT (repo root, '/'-terminated) and FLAVOR.

local ROOT = HARNESS_ROOT
local FLAVOR = FLAVOR or 'retail'
local HARNESS = ROOT .. 'Tests/Nameplates/harness/'

local S = dofile(HARNESS .. 'secret.lua')
local D = dofile(ROOT .. 'Tests/Nameplates/data/' .. FLAVOR .. '.lua')
local FX = dofile(HARNESS .. 'framexml.lua')
local rawtype = S.rawtype
local rawtostring = S.rawtostring

local M = {
	flavor = FLAVOR,
	data = D,
	S = S,
	secrets = D.meta.secrets,
	errors = {},
	now = 1000,
	lockdown = false,
	loggedIn = false,
	extraEvents = {},
	templates = {},
	chat = {},
}

local FN = {} -- global function behaviors, by name
local NS = {} -- namespace function behaviors: NS.C_Name.Function
local W = {} -- widget method behaviors, by method name
local WT = {} -- behaviors for one type only: WT.Duration.Reset
M.FN, M.NS, M.W, M.WT = FN, NS, W, WT

----------------------------------------------------------------------------------------------------
-- Records: what addon code did, for suites to assert on
----------------------------------------------------------------------------------------------------

function M.ResetRecords()
	M.rec = {
		events = {}, -- { frame, event, kind, units, where }
		hooks = {}, -- { target, name, where }
		cvarWrites = {}, -- { name, value, old, via, where }
		globals = {}, -- { name, kind, where }
		tickers = {}, -- { timer, where }
		onUpdates = {}, -- { frame, where }
		blocked = {}, -- { label, where }
		unmodeled = {}, -- [label] = count
	}
end
M.ResetRecords()

---The first caller outside the harness, as "folder/file.lua:line".
function M.Caller(level)
	for l = level or 3, 60 do
		local info = debug.getinfo(l, 'Sl')
		if not info then
			break
		end
		local src = info.source or ''
		if info.currentline and info.currentline > 0 and not src:find('Tests/Nameplates/harness', 1, true) and not src:find('Tests\\Nameplates\\harness', 1, true) then
			src = src:gsub('^@', ''):gsub('\\', '/')
			return (src:match('([^/]+/[^/]+)$') or src) .. ':' .. info.currentline
		end
	end
	return '?'
end

----------------------------------------------------------------------------------------------------
-- Errors
----------------------------------------------------------------------------------------------------

local function traceback(e)
	return rawtostring(e) .. '\n' .. debug.traceback('', 2)
end

---Run a function the way the game runs a script: errors go to the error handler, not up the stack.
function M.Protect(fn, ...)
	local ok, err = xpcall(fn, traceback, ...)
	if not ok then
		M.errors[#M.errors + 1] = err
	end
	return ok
end

local errorHandler = function(err)
	M.errors[#M.errors + 1] = 'LUA ERROR: ' .. rawtostring(err) .. '\n' .. debug.traceback('', 2)
end

----------------------------------------------------------------------------------------------------
-- Spec strings from the data file: "<policy>|<unit arg>|<returns>|<flag,flag=...>"
----------------------------------------------------------------------------------------------------

local specCache = {}
local function parseSpec(spec)
	if not spec then
		return { policy = '', unit = 0, nret = 0, flags = {} }
	end
	local cached = specCache[spec]
	if cached then
		return cached
	end
	local policy, unit, nret, flagText = spec:match('^(%a?)|(%d+)|(%d+)|(.*)$')
	local flags = {}
	for flag in (flagText or ''):gmatch('[^,]+') do
		local key, value = flag:match('^([^=]+)=(.*)$')
		flags[key or flag] = value or true
	end
	cached = { policy = policy or '', unit = tonumber(unit) or 0, nret = tonumber(nret) or 0, flags = flags }
	specCache[spec] = cached
	return cached
end
M.ParseSpec = parseSpec

-- Functions whose whole job is to look at secrets
local SECRET_INSPECTORS = {
	canaccessvalue = true,
	canaccessallvalues = true,
	canaccesstable = true,
	issecretvalue = true,
	issecrettable = true,
	hasanysecretvalues = true,
	scrubsecretvalues = true,
	dumpobject = true,
}

----------------------------------------------------------------------------------------------------
-- Objects and per-object state (kept off the objects so pairs(frame) sees only addon fields)
----------------------------------------------------------------------------------------------------

local state = setmetatable({}, { __mode = 'k' })
local log = setmetatable({}, { __mode = 'k' })
M.allFrames = {}

function M.State(obj)
	return state[obj]
end
function M.Set(obj, key, value)
	state[obj][key] = value
end
function M.Get(obj, key)
	return state[obj] and state[obj][key]
end
function M.TypeOf(obj)
	return state[obj] and state[obj].type
end

---Record a call on an object (generic methods do this automatically).
function M.Log(obj, method, ...)
	local list = log[obj]
	if not list then
		list = {}
		log[obj] = list
	end
	list[#list + 1] = { method = method, n = select('#', ...), ... }
end

---Calls recorded on an object, optionally only one method's.
function M.Calls(obj, method)
	local out = {}
	for _, call in ipairs(log[obj] or {}) do
		if not method or call.method == method then
			out[#out + 1] = call
		end
	end
	return out
end

-- Widget type tree. apis are the generated ScriptObject documentation tables for each type.
local TYPES = {
	FrameScriptObject = { apis = { 'SimpleFrameScriptObjectAPI' } },
	Object = { parent = 'FrameScriptObject', apis = { 'SimpleObjectAPI' } },
	Region = { parent = 'Object', apis = { 'SimpleScriptRegionAPI', 'SimpleScriptRegionResizingAPI', 'SimpleAnimatableObjectAPI', 'SimpleRegionAPI' } },
	TextureBase = { parent = 'Region', apis = { 'SimpleTextureBaseAPI' } },
	Texture = { parent = 'TextureBase', apis = { 'SimpleTextureAPI' }, region = true },
	MaskTexture = { parent = 'TextureBase', apis = { 'SimpleMaskTextureAPI' }, region = true },
	Line = { parent = 'TextureBase', apis = { 'SimpleLineAPI' }, region = true },
	FontString = { parent = 'Region', apis = { 'SimpleFontStringAPI' }, region = true },
	Font = { parent = 'FrameScriptObject', apis = { 'SimpleFontAPI' } },
	Frame = { parent = 'Region', apis = { 'SimpleFrameAPI' }, frame = true },
	Button = { parent = 'Frame', apis = { 'SimpleButtonAPI' }, frame = true },
	CheckButton = { parent = 'Button', apis = { 'SimpleCheckboxAPI' }, frame = true },
	StatusBar = { parent = 'Frame', apis = { 'SimpleStatusBarAPI' }, frame = true },
	Cooldown = { parent = 'Frame', apis = { 'FrameAPICooldown' }, frame = true },
	Slider = { parent = 'Frame', apis = { 'SimpleSliderAPI' }, frame = true },
	EditBox = { parent = 'Frame', apis = { 'SimpleEditBoxAPI' }, frame = true },
	ScrollFrame = { parent = 'Frame', apis = { 'SimpleScrollFrameAPI' }, frame = true },
	MessageFrame = { parent = 'Frame', apis = { 'SimpleMessageFrameAPI' }, frame = true },
	SimpleHTML = { parent = 'Frame', apis = { 'SimpleHTMLAPI' }, frame = true },
	GameTooltip = { parent = 'Frame', apis = { 'FrameAPITooltip' }, frame = true },
	ColorSelect = { parent = 'Frame', apis = { 'SimpleColorSelectAPI' }, frame = true },
	Model = { parent = 'Frame', apis = { 'SimpleModelAPI' }, frame = true },
	PlayerModel = { parent = 'Model', apis = { 'FrameAPICharacterModelBase' }, frame = true },
	ModelScene = { parent = 'Frame', apis = { 'FrameAPIModelSceneFrame' }, frame = true },
	MovieFrame = { parent = 'Frame', apis = { 'SimpleMovieAPI' }, frame = true },
	NamePlate = { parent = 'Frame', apis = { 'FrameAPINamePlate' }, objectType = 'Frame', internal = true },
	AuraContainer = { parent = 'Frame', apis = {}, frame = true, auraContainer = true },
	AnimationGroup = { parent = 'Object', apis = { 'SimpleAnimGroupAPI' } },
	Animation = { parent = 'Object', apis = { 'SimpleAnimAPI' } },
	Alpha = { parent = 'Animation', apis = { 'SimpleAnimAlphaAPI' }, animation = true },
	Scale = { parent = 'Animation', apis = { 'SimpleAnimScaleAPI' }, animation = true },
	LineScale = { parent = 'Scale', apis = { 'SimpleAnimScaleLineAPI' }, animation = true },
	Translation = { parent = 'Animation', apis = { 'SimpleAnimTranslationAPI' }, animation = true },
	LineTranslation = { parent = 'Translation', apis = { 'SimpleAnimTranslationLineAPI' }, animation = true },
	Rotation = { parent = 'Animation', apis = { 'SimpleAnimRotationAPI' }, animation = true },
	Path = { parent = 'Animation', apis = { 'SimpleAnimPathAPI' }, animation = true },
	FlipBook = { parent = 'Animation', apis = { 'SimpleAnimFlipBookAPI' }, animation = true },
	TextureCoordTranslation = { parent = 'Animation', apis = { 'SimpleAnimTextureCoordTranslationAPI' }, animation = true },
	VertexColor = { parent = 'Animation', apis = { 'SimpleAnimVertexColorAPI' }, animation = true },
	ControlPoint = { parent = 'Object', apis = { 'SimpleControlPointAPI' } },
	-- Script objects that are not regions
	Curve = { apis = { 'LuaCurveObjectBaseAPI', 'LuaCurveObjectAPI' } },
	ColorCurve = { apis = { 'LuaCurveObjectBaseAPI', 'LuaColorCurveObjectAPI' } },
	Duration = { apis = { 'LuaDurationObjectAPI' } },
	DurationTextBinding = { apis = { 'DurationTextBindingObjectAPI' } },
	SecondsFormatter = { apis = { 'SecondsFormatterAPI' } },
	NumericFormatter = { apis = { 'NumericFormatterAPI' } },
	AbbreviatedNumberFormatter = { apis = { 'AbbreviatedNumberFormatterAPI' } },
	UnitHealPredictionCalculator = { apis = { 'UnitHealPredictionCalculatorAPI' } },
}
M.TYPES = TYPES

local function isA(typeName, wanted)
	while typeName do
		if typeName == wanted then
			return true
		end
		typeName = TYPES[typeName].parent
	end
	return false
end
M.IsA = isA

-- Types and methods that take secrets from addon code although their docs say AllowedWhenUntainted.
-- Duration and binding setters consume secrets in the engine (.context/patterns.md, 2026-06-17).
M.secretArgExempt = { Duration = true, DurationTextBinding = true }

local function wrapMethod(typeName, name, spec, impl)
	local p = parseSpec(spec)
	local label = typeName .. ':' .. name
	local guard = M.secrets and (p.policy == 'U' or p.policy == 'N') and not SECRET_INSPECTORS[name] and not M.secretArgExempt[typeName] and not M.secretArgExempt[label]
	local needHitTest = p.flags.RequiresCanChangeHitTestPoints
	return function(self, ...)
		local st = state[self]
		if not st then
			error(('%s called without a valid self (use ":" not ".")'):format(label), 2)
		end
		if guard and S.Any(...) then
			error(('%s: secret values are not allowed from addon code (SecretArguments = %s)'):format(label, p.policy == 'U' and 'AllowedWhenUntainted' or 'NotAllowed'), 2)
		end
		if needHitTest and not st.canHitTest then
			error(label .. ': only allowed while CanChangeHitTestPoints() is true (the tick a unit is added)', 2)
		end
		return impl(self, ...)
	end
end

local function genericMethod(typeName, name)
	local label = typeName .. ':' .. name
	return function(self, ...)
		M.Log(self, name, ...)
		M.rec.unmodeled[label] = (M.rec.unmodeled[label] or 0) + 1
	end
end

local classes = {}
local function buildClass(typeName)
	if classes[typeName] then
		return classes[typeName]
	end
	local info = TYPES[typeName]
	local specs = {}
	local chain = {}
	local t = typeName
	while t do
		table.insert(chain, 1, t)
		t = TYPES[t].parent
	end
	for _, tn in ipairs(chain) do
		for _, api in ipairs(TYPES[tn].apis) do
			for method, spec in pairs(D.scriptObjects[api] or {}) do
				specs[method] = spec
			end
		end
	end
	if info.auraContainer then
		for method in pairs(D.auraContainer or {}) do
			specs[method] = specs[method] or '|0|0|'
		end
	end
	local methods = {}
	local own = M.WT[typeName] or {}
	for method, spec in pairs(specs) do
		methods[method] = wrapMethod(typeName, method, spec, own[method] or W[method] or genericMethod(typeName, method))
	end
	local cls = { name = typeName, methods = methods, specs = specs, meta = { __index = methods } }
	classes[typeName] = cls
	return cls
end
M.Class = buildClass

---True when this flavor documents the method on that widget type.
function M.HasMethod(typeName, method)
	return buildClass(typeName).methods[method] ~= nil
end

---Create an object without recording it (for the mock's own frames and the engine's plates).
function M.NewObject(typeName, name, parent)
	if not TYPES[typeName] then
		error('unknown object type ' .. rawtostring(typeName), 2)
	end
	local obj = setmetatable({}, buildClass(typeName).meta)
	local st = {
		type = typeName,
		name = name,
		shown = true,
		alpha = 1,
		scale = 1,
		w = 0,
		h = 0,
		points = {},
		scripts = {},
		hooks = {},
		events = {},
		children = {},
		regions = {},
		attrs = {},
		level = 0,
		strata = 'MEDIUM',
	}
	state[obj] = st
	if parent then
		st.parent = parent
		local pst = state[parent]
		if pst then
			st.level = (pst.level or 0) + 1
			if TYPES[typeName].frame or TYPES[typeName].internal then
				pst.children[#pst.children + 1] = obj
			else
				pst.regions[#pst.regions + 1] = obj
			end
		end
	end
	if TYPES[typeName].frame or TYPES[typeName].internal then
		M.allFrames[#M.allFrames + 1] = obj
	end
	return obj
end

---Replace one method on one object (the mock's own frames only).
function M.Override(obj, method, fn)
	rawset(obj, method, fn)
end

function M.NewFont(name, size, flags)
	local font = M.NewObject('Font', name)
	state[font].font = { 'Fonts\\FRIZQT__.TTF', size or 12, flags or '' }
	return font
end

----------------------------------------------------------------------------------------------------
-- Scripts and visibility
----------------------------------------------------------------------------------------------------

local function runScript(obj, script, ...)
	local st = state[obj]
	local fn = st.scripts[script]
	if fn then
		M.Protect(fn, obj, ...)
	end
	for _, hook in ipairs(st.hooks[script] or {}) do
		M.Protect(hook, obj, ...)
	end
end
M.RunScript = runScript

local onUpdate = {}
local onUpdateOrder = {}

W.SetScript = function(self, script, fn)
	if fn ~= nil and rawtype(fn) ~= 'function' then
		error('SetScript: handler must be a function or nil', 2)
	end
	local st = state[self]
	st.scripts[script] = fn
	st.hooks[script] = nil
	if script == 'OnUpdate' then
		if fn then
			if not onUpdate[self] then
				onUpdateOrder[#onUpdateOrder + 1] = self
			end
			onUpdate[self] = true
			M.rec.onUpdates[#M.rec.onUpdates + 1] = { frame = self, where = M.Caller() }
		else
			onUpdate[self] = nil
		end
	end
end
W.GetScript = function(self, script)
	return state[self].scripts[script]
end
W.HookScript = function(self, script, fn)
	local st = state[self]
	st.hooks[script] = st.hooks[script] or {}
	table.insert(st.hooks[script], fn)
	if script == 'OnUpdate' then
		if not onUpdate[self] then
			onUpdateOrder[#onUpdateOrder + 1] = self
		end
		onUpdate[self] = true
		M.rec.onUpdates[#M.rec.onUpdates + 1] = { frame = self, where = M.Caller() }
	end
	return true
end
W.HasScript = function(self, script)
	return rawtype(script) == 'string' and script:match('^On%u') ~= nil
end

local function isVisible(obj)
	while obj do
		local st = state[obj]
		if not st or not st.shown then
			return false
		end
		obj = st.parent
	end
	return true
end
M.IsVisible = isVisible

W.Show = function(self)
	local st = state[self]
	if not st.shown then
		st.shown = true
		runScript(self, 'OnShow')
	end
end
W.Hide = function(self)
	local st = state[self]
	if st.shown then
		st.shown = false
		runScript(self, 'OnHide')
	end
end
W.SetShown = function(self, shown)
	if shown then
		W.Show(self)
	else
		W.Hide(self)
	end
end
W.IsShown = function(self)
	return state[self].shown
end
W.IsVisible = isVisible

----------------------------------------------------------------------------------------------------
-- Identity, parents, children
----------------------------------------------------------------------------------------------------

W.GetName = function(self)
	return state[self].name
end
W.GetDebugName = W.GetName
W.GetObjectType = function(self)
	local t = state[self].type
	return TYPES[t].objectType or t
end
W.IsObjectType = function(self, wanted)
	return isA(state[self].type, wanted)
end
W.IsForbidden = function(self)
	return state[self].forbidden or false
end
W.IsProtected = function(self)
	local p = state[self].protected and true or false
	return p, p
end
W.GetParent = function(self)
	return state[self].parent
end
W.SetParent = function(self, parent)
	if rawtype(parent) == 'string' then
		parent = _G[parent]
	end
	local st = state[self]
	local old = st.parent and state[st.parent]
	if old then
		for _, list in ipairs({ old.children, old.regions }) do
			for i = #list, 1, -1 do
				if list[i] == self then
					table.remove(list, i)
				end
			end
		end
	end
	st.parent = parent
	if parent and state[parent] then
		local pst = state[parent]
		if TYPES[st.type].frame or TYPES[st.type].internal then
			pst.children[#pst.children + 1] = self
		else
			pst.regions[#pst.regions + 1] = self
		end
	end
end
W.GetChildren = function(self)
	return unpack(state[self].children)
end
W.GetNumChildren = function(self)
	return #state[self].children
end
W.GetRegions = function(self)
	return unpack(state[self].regions)
end
W.GetNumRegions = function(self)
	return #state[self].regions
end
W.SetID = function(self, id)
	state[self].id = id
end
W.GetID = function(self)
	return state[self].id or 0
end
W.SetAttribute = function(self, key, value)
	state[self].attrs[key] = value
	runScript(self, 'OnAttributeChanged', key, value)
end
W.GetAttribute = function(self, key)
	return state[self].attrs[key]
end

----------------------------------------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------------------------------------

local VALID_POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }

W.SetPoint = function(self, point, relativeTo, relativePoint, x, y)
	if not VALID_POINTS[point] then
		error('SetPoint: invalid anchor point ' .. rawtostring(point), 2)
	end
	if rawtype(relativeTo) == 'number' then
		relativeTo, relativePoint, x, y = nil, point, relativeTo, relativePoint
	elseif rawtype(relativeTo) == 'string' then
		local found = _G[relativeTo]
		if not found then
			error('SetPoint: unknown frame ' .. relativeTo, 2)
		end
		relativeTo = found
	end
	if relativeTo == self then
		error('SetPoint: cannot anchor to itself', 2)
	end
	local st = state[self]
	local relative = relativeTo or st.parent
	for i = #st.points, 1, -1 do
		if st.points[i][1] == point then
			table.remove(st.points, i)
		end
	end
	st.points[#st.points + 1] = { point, relative, relativePoint or point, x or 0, y or 0 }
end
W.ClearAllPoints = function(self)
	state[self].points = {}
end
W.ClearPoint = function(self, point)
	local points = state[self].points
	for i = #points, 1, -1 do
		if points[i][1] == point then
			table.remove(points, i)
		end
	end
end
W.SetAllPoints = function(self, relativeTo)
	local st = state[self]
	relativeTo = relativeTo or st.parent
	st.points = { { 'TOPLEFT', relativeTo, 'TOPLEFT', 0, 0 }, { 'BOTTOMRIGHT', relativeTo, 'BOTTOMRIGHT', 0, 0 } }
	st.allPointsTo = relativeTo
end
W.GetNumPoints = function(self)
	return #state[self].points
end
W.GetPoint = function(self, index)
	local p = state[self].points[index or 1]
	if p then
		return p[1], p[2], p[3], p[4], p[5]
	end
end
W.GetPointByName = function(self, point)
	for _, p in ipairs(state[self].points) do
		if p[1] == point then
			return p[1], p[2], p[3], p[4], p[5]
		end
	end
end
W.SetSize = function(self, w, h)
	local st = state[self]
	st.w, st.h = w, h or w
	runScript(self, 'OnSizeChanged', st.w, st.h)
end
W.SetWidth = function(self, w)
	local st = state[self]
	st.w = w
	runScript(self, 'OnSizeChanged', st.w, st.h)
end
W.SetHeight = function(self, h)
	local st = state[self]
	st.h = h
	runScript(self, 'OnSizeChanged', st.w, st.h)
end
local function sizeOf(obj)
	local st = state[obj]
	if st.allPointsTo and state[st.allPointsTo] and st.w == 0 and st.h == 0 then
		return sizeOf(st.allPointsTo)
	end
	return st.w, st.h
end
W.GetWidth = function(self)
	return (sizeOf(self))
end
W.GetHeight = function(self)
	local _, h = sizeOf(self)
	return h
end
W.GetSize = function(self)
	return sizeOf(self)
end
W.GetRect = function(self)
	local w, h = sizeOf(self)
	return 0, 0, w, h
end
W.GetCenter = function(self)
	local w, h = sizeOf(self)
	return w / 2, h / 2
end
W.GetLeft = function()
	return 0
end
W.GetBottom = function()
	return 0
end
W.GetRight = function(self)
	return (sizeOf(self))
end
W.GetTop = function(self)
	local _, h = sizeOf(self)
	return h
end
W.SetScale = function(self, scale)
	if rawtype(scale) == 'number' and scale <= 0 then
		error('SetScale: scale must be above 0', 2)
	end
	state[self].scale = scale
end
W.GetScale = function(self)
	return state[self].scale
end
W.GetEffectiveScale = function(self)
	local scale, obj = 1, self
	while obj and state[obj] do
		scale = scale * (state[obj].scale or 1)
		obj = state[obj].parent
	end
	return scale
end
W.SetFrameLevel = function(self, level)
	state[self].level = level
end
W.GetFrameLevel = function(self)
	return state[self].level
end
W.SetFrameStrata = function(self, strata)
	state[self].strata = strata
end
W.GetFrameStrata = function(self)
	return state[self].strata
end
W.Raise = function(self)
	state[self].level = state[self].level + 1
end
W.Lower = function(self)
	state[self].level = math.max(0, state[self].level - 1)
end
W.SetDrawLayer = function(self, layer, sublevel)
	state[self].layer, state[self].sublevel = layer, sublevel
end
W.GetDrawLayer = function(self)
	return state[self].layer or 'ARTWORK', state[self].sublevel or 0
end

----------------------------------------------------------------------------------------------------
-- Alpha and color (the secret-aware sinks keep the revealed value for assertions)
----------------------------------------------------------------------------------------------------

W.SetAlpha = function(self, alpha)
	local st = state[self]
	st.alpha = S.Reveal(alpha)
	st.alphaSecret = S.IsSecret(alpha)
end
W.GetAlpha = function(self)
	local st = state[self]
	if st.alphaSecret then
		return S.Wrap(st.alpha)
	end
	return st.alpha
end
W.GetEffectiveAlpha = function(self)
	local alpha, obj = 1, self
	while obj and state[obj] do
		alpha = alpha * (state[obj].alpha or 1)
		obj = state[obj].parent
	end
	return alpha
end
W.SetAlphaFromBoolean = function(self, value, alphaIfTrue, alphaIfFalse)
	if rawtype(alphaIfTrue) ~= 'number' or rawtype(alphaIfFalse) ~= 'number' then
		error('SetAlphaFromBoolean: pass alphaIfTrue and alphaIfFalse explicitly', 2)
	end
	local st = state[self]
	st.alpha = S.Reveal(value) and alphaIfTrue or alphaIfFalse
	st.alphaSecret = S.IsSecret(value)
end
W.SetVertexColor = function(self, r, g, b, a)
	state[self].vertex = { S.Reveal(r), S.Reveal(g), S.Reveal(b), S.Reveal(a) or 1, secret = S.Any(r, g, b, a) }
end
W.GetVertexColor = function(self)
	local c = state[self].vertex or { 1, 1, 1, 1 }
	if c.secret then
		return S.Wrap(c[1]), S.Wrap(c[2]), S.Wrap(c[3]), S.Wrap(c[4])
	end
	return c[1], c[2], c[3], c[4]
end
local function colorParts(color)
	if rawtype(color) == 'table' and color.GetRGBA then
		return color:GetRGBA()
	end
	error('expected a color object', 3)
end
W.SetVertexColorFromBoolean = function(self, value, colorIfTrue, colorIfFalse)
	local r, g, b, a = colorParts(S.Reveal(value) and colorIfTrue or colorIfFalse)
	state[self].vertex = { S.Reveal(r), S.Reveal(g), S.Reveal(b), S.Reveal(a) or 1, secret = S.IsSecret(value) }
end
W.SetColorTexture = function(self, r, g, b, a)
	if not (S.IsSecret(r) or rawtype(r) == 'number') then
		error('SetColorTexture: color values must be numbers', 2)
	end
	local st = state[self]
	st.texture = nil
	st.colorTexture = { S.Reveal(r), S.Reveal(g), S.Reveal(b), S.Reveal(a) or 1 }
end

----------------------------------------------------------------------------------------------------
-- Textures, text and fonts
----------------------------------------------------------------------------------------------------

---A texture given as text must be a file path. A path that lost its backslashes
---('InterfaceButtonsWHITE8X8') draws nothing in game, with no error.
local function checkTexturePath(texture, method)
	if rawtype(texture) == 'string' and texture ~= '' and not texture:find('[\\/]') then
		error(method .. ': "' .. texture .. '" is not a file path', 3)
	end
end

W.SetTexture = function(self, texture)
	checkTexturePath(texture, 'SetTexture')
	state[self].texture = texture
	state[self].atlas = nil
	return true
end
W.GetTexture = function(self)
	return state[self].texture
end
W.GetTextureFilePath = W.GetTexture
W.SetAtlas = function(self, atlas)
	state[self].atlas = atlas
	state[self].texture = nil
	return true
end
W.GetAtlas = function(self)
	return state[self].atlas
end
W.SetTexCoord = function(self, ...)
	state[self].texCoord = { ... }
end
W.GetTexCoord = function(self)
	return unpack(state[self].texCoord or { 0, 0, 0, 1, 1, 0, 1, 1 })
end
W.SetDesaturated = function(self, value)
	state[self].desaturated = value
end
W.IsDesaturated = function(self)
	return state[self].desaturated or false
end
W.SetBlendMode = function(self, mode)
	state[self].blend = mode
end
W.GetBlendMode = function(self)
	return state[self].blend or 'BLEND'
end

local VALID_FONT_FLAGS = { OUTLINE = true, THICKOUTLINE = true, MONOCHROME = true, THICK = true, SLUG = true }
W.SetFont = function(self, face, height, flags)
	if rawtype(face) ~= 'string' or rawtype(height) ~= 'number' then
		error('SetFont: needs a font file and a number height', 2)
	end
	for flag in (flags or ''):gmatch('[^%s,]+') do
		if not VALID_FONT_FLAGS[flag] then
			error('SetFont: unknown flag "' .. flag .. '" (flags are uppercase: OUTLINE, THICKOUTLINE, MONOCHROME)', 2)
		end
	end
	state[self].font = { face, height, flags or '' }
	state[self].fontObject = nil
	return true
end
W.GetFont = function(self)
	local st = state[self]
	local f = st.font or (st.fontObject and state[st.fontObject] and state[st.fontObject].font) or { 'Fonts\\FRIZQT__.TTF', 12, '' }
	return f[1], f[2], f[3]
end
W.SetFontObject = function(self, font)
	if rawtype(font) == 'string' then
		font = _G[font]
	end
	if not (font and state[font]) then
		error('SetFontObject: not a font object', 2)
	end
	state[self].fontObject = font
	state[self].font = nil
end
W.GetFontObject = function(self)
	return state[self].fontObject
end
W.SetText = function(self, text)
	state[self].text = text
end
W.GetText = function(self)
	return state[self].text
end
W.SetFormattedText = function(self, fmt, ...)
	state[self].text = string.format(fmt, ...)
end
W.SetTextColor = function(self, r, g, b, a)
	state[self].textColor = { S.Reveal(r), S.Reveal(g), S.Reveal(b), S.Reveal(a) or 1, secret = S.Any(r, g, b, a) }
end
W.GetTextColor = function(self)
	local c = state[self].textColor or { 1, 1, 1, 1 }
	if c.secret then
		return S.Wrap(c[1]), S.Wrap(c[2]), S.Wrap(c[3]), S.Wrap(c[4])
	end
	return c[1], c[2], c[3], c[4]
end
W.SetJustifyH = function(self, value)
	state[self].justifyH = value
end
W.GetJustifyH = function(self)
	return state[self].justifyH or 'CENTER'
end
W.SetJustifyV = function(self, value)
	state[self].justifyV = value
end
W.GetJustifyV = function(self)
	return state[self].justifyV or 'MIDDLE'
end
W.SetShadowColor = function(self, ...)
	state[self].shadowColor = { ... }
end
W.SetShadowOffset = function(self, x, y)
	state[self].shadowOffset = { x, y }
end
W.GetUnboundedStringWidth = function(self)
	local text = state[self].text
	if S.IsSecret(text) then
		return S.Wrap(#rawtostring(S.Reveal(text)) * 6)
	end
	return #(rawtostring(text or ''):gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')) * 6
end
W.GetStringWidth = function(self)
	local full = W.GetUnboundedStringWidth(self)
	local w = state[self].w
	if not S.IsSecret(full) and w and w > 0 then
		return math.min(full, w)
	end
	return full
end
W.GetStringHeight = function(self)
	local _, size = W.GetFont(self)
	return size
end
W.SetWordWrap = function(self, value)
	state[self].wordWrap = value
end
W.SetMaxLines = function(self, value)
	state[self].maxLines = value
end

----------------------------------------------------------------------------------------------------
-- Creating regions and animations
----------------------------------------------------------------------------------------------------

local function namedChild(self, name)
	if rawtype(name) == 'string' and name:find('$parent', 1, true) then
		name = name:gsub('%$parent', state[self].name or '')
	end
	return name
end

local function recordGlobal(name, kind)
	if name then
		M.rec.globals[#M.rec.globals + 1] = { name = name, kind = kind, where = M.Caller(4) }
	end
end

local function applyTemplates(obj, template, level)
	if not template then
		return
	end
	for t in rawtostring(template):gmatch('[^,%s]+') do
		local apply = M.templates[t]
		if not apply then
			error(("Couldn't find inherited node '%s'"):format(t), level or 3)
		end
		apply(obj)
	end
	state[obj].template = template
end

local function newRegion(self, kind, name, layer, template, sublevel)
	name = namedChild(self, name)
	local region = M.NewObject(kind, name, self)
	state[region].layer, state[region].sublevel = layer, sublevel
	if name then
		_G[name] = region
		recordGlobal(name, kind)
	end
	if rawtype(template) == 'string' and M.templates[template] then
		applyTemplates(region, template, 4)
	end
	return region
end
W.CreateTexture = function(self, name, layer, template, sublevel)
	return newRegion(self, 'Texture', name, layer, template, sublevel)
end
W.CreateMaskTexture = function(self, name, layer, template, sublevel)
	return newRegion(self, 'MaskTexture', name, layer, template, sublevel)
end
W.CreateLine = function(self, name, layer, template, sublevel)
	return newRegion(self, 'Line', name, layer, template, sublevel)
end
W.CreateFontString = function(self, name, layer, template)
	local fs = newRegion(self, 'FontString', name, layer)
	if template then
		local font = rawtype(template) == 'string' and _G[template] or template
		if font and state[font] and state[font].type == 'Font' then
			state[fs].fontObject = font
		elseif rawtype(template) == 'string' and M.templates[template] then
			applyTemplates(fs, template, 3)
		else
			error(("CreateFontString: unknown font object or template '%s'"):format(rawtostring(template)), 2)
		end
	end
	return fs
end
W.CreateAnimationGroup = function(self, name, template)
	local group = M.NewObject('AnimationGroup', namedChild(self, name), self)
	state[group].animations = {}
	return group
end
W.CreateAnimation = function(self, kind, name)
	kind = kind or 'Animation'
	if not (TYPES[kind] and isA(kind, 'Animation')) then
		error('CreateAnimation: unknown animation type ' .. rawtostring(kind), 2)
	end
	local anim = M.NewObject(kind, name, self)
	table.insert(state[self].animations, anim)
	return anim
end
W.Play = function(self)
	state[self].playing = true
	runScript(self, 'OnPlay')
end
W.Stop = function(self)
	if state[self].playing then
		state[self].playing = false
		runScript(self, 'OnStop')
	end
end
W.Finish = function(self)
	state[self].playing = false
	runScript(self, 'OnFinished')
end
W.IsPlaying = function(self)
	return state[self].playing or false
end
W.SetLooping = function(self, value)
	state[self].looping = value
end
W.GetLooping = function(self)
	return state[self].looping or 'NONE'
end
W.SetDuration = function(self, seconds)
	state[self].duration = seconds
end
W.GetDuration = function(self)
	return state[self].duration or 0
end

----------------------------------------------------------------------------------------------------
-- Status bars and cooldowns
----------------------------------------------------------------------------------------------------

W.SetMinMaxValues = function(self, minValue, maxValue)
	local st = state[self]
	st.min, st.max = minValue, maxValue
end
W.GetMinMaxValues = function(self)
	local st = state[self]
	return st.min or 0, st.max or 1
end
W.SetValue = function(self, value)
	state[self].value = value
end
W.GetValue = function(self)
	return state[self].value or 0
end
W.SetStatusBarTexture = function(self, texture)
	checkTexturePath(texture, 'SetStatusBarTexture')
	local st = state[self]
	if rawtype(texture) == 'table' and state[texture] then
		st.barTexture = texture
	else
		st.barTexture = st.barTexture or M.NewObject('Texture', nil, self)
		state[st.barTexture].texture = texture
	end
	return true
end
W.GetStatusBarTexture = function(self)
	local st = state[self]
	st.barTexture = st.barTexture or M.NewObject('Texture', nil, self)
	return st.barTexture
end
W.SetStatusBarColor = function(self, r, g, b, a)
	local st = state[self]
	st.barColor = { S.Reveal(r), S.Reveal(g), S.Reveal(b), S.Reveal(a) or 1, secret = S.Any(r, g, b, a) }
	W.SetVertexColor(W.GetStatusBarTexture(self), r, g, b, a)
end
W.GetStatusBarColor = function(self)
	local c = state[self].barColor or { 1, 1, 1, 1 }
	if c.secret then
		return S.Wrap(c[1]), S.Wrap(c[2]), S.Wrap(c[3]), S.Wrap(c[4])
	end
	return c[1], c[2], c[3], c[4]
end
W.SetOrientation = function(self, value)
	state[self].orientation = value
end
W.GetOrientation = function(self)
	return state[self].orientation or 'HORIZONTAL'
end
W.SetReverseFill = function(self, value)
	state[self].reverseFill = value
end
W.GetReverseFill = function(self)
	return state[self].reverseFill or false
end
W.SetTimerDuration = function(self, duration, interpolation, direction)
	if duration ~= nil and not (rawtype(duration) == 'table' and state[duration] and state[duration].type == 'Duration') then
		error('SetTimerDuration: needs a duration object', 2)
	end
	state[self].timer = { duration = duration, interpolation = interpolation, direction = direction }
	M.Log(self, 'SetTimerDuration', duration, interpolation, direction)
end
W.SetCooldown = function(self, start, duration)
	state[self].cooldown = { start, duration }
	M.Log(self, 'SetCooldown', start, duration)
end
W.Clear = function(self)
	state[self].cooldown = nil
end

----------------------------------------------------------------------------------------------------
-- Mouse
----------------------------------------------------------------------------------------------------

W.EnableMouse = function(self, value)
	state[self].mouse = value and true or false
end
W.IsMouseEnabled = function(self)
	return state[self].mouse or false
end
W.SetMouseClickEnabled = function(self, value)
	state[self].mouseClick = value
end
W.SetMouseMotionEnabled = function(self, value)
	state[self].mouseMotion = value
end
W.IsMouseOver = function(self)
	local over = M.mouseFocus
	while over do
		if over == self then
			return true
		end
		over = state[over] and state[over].parent
	end
	return false
end

----------------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------------

local eventFrames = {}
local eventFrameSet = {}
M.eventFrames = eventFrames

local function knownEvent(event)
	return rawtype(event) == 'string' and (D.events[event] ~= nil or M.extraEvents[event] ~= nil)
end
M.KnownEvent = knownEvent

local function trackEventFrame(frame)
	if not eventFrameSet[frame] then
		eventFrameSet[frame] = true
		eventFrames[#eventFrames + 1] = frame
	end
end

W.RegisterEvent = function(self, event)
	if not knownEvent(event) then
		error(('Attempt to register unknown event "%s"'):format(rawtostring(event)), 2)
	end
	state[self].events[event] = true
	trackEventFrame(self)
	M.rec.events[#M.rec.events + 1] = { frame = self, event = event, kind = 'RegisterEvent', where = M.Caller() }
	return true
end
W.RegisterUnitEvent = function(self, event, unit1, unit2)
	if not knownEvent(event) then
		error(('Attempt to register unknown event "%s"'):format(rawtostring(event)), 2)
	end
	state[self].events[event] = { S.Reveal(unit1), S.Reveal(unit2) }
	trackEventFrame(self)
	M.rec.events[#M.rec.events + 1] = { frame = self, event = event, kind = 'RegisterUnitEvent', units = { unit1, unit2 }, where = M.Caller() }
	return true
end
W.RegisterAllEvents = function(self)
	state[self].allEvents = true
	trackEventFrame(self)
	M.rec.events[#M.rec.events + 1] = { frame = self, event = '*', kind = 'RegisterAllEvents', where = M.Caller() }
end
W.UnregisterEvent = function(self, event)
	state[self].events[event] = nil
end
W.UnregisterAllEvents = function(self)
	state[self].events = {}
	state[self].allEvents = nil
end
W.IsEventRegistered = function(self, event)
	local reg = state[self].events[event]
	if rawtype(reg) == 'table' then
		return true, reg[1], reg[2]
	end
	return reg ~= nil
end

---Events the frame is registered for right now.
function M.RegisteredEvents(frame)
	local out = {}
	for event in pairs(state[frame].events) do
		out[#out + 1] = event
	end
	table.sort(out)
	return out
end

---Fire a game event at every registered frame. Unit events honor RegisterUnitEvent filters.
function M.Fire(event, ...)
	if not knownEvent(event) then
		error('M.Fire: this flavor has no event ' .. rawtostring(event), 2)
	end
	local spec = D.events[event]
	local unitIndex = spec and tonumber(spec:match('^%d+|(%d+)|')) or 0
	local unit = unitIndex > 0 and S.Reveal((select(unitIndex, ...))) or nil
	local list = {}
	for i = 1, #eventFrames do
		list[i] = eventFrames[i]
	end
	for _, frame in ipairs(list) do
		local st = state[frame]
		local reg = st.events[event] or (st.allEvents and true)
		local pass = reg ~= nil
		if rawtype(reg) == 'table' then
			pass = unit ~= nil and (unit == reg[1] or unit == reg[2])
		end
		if pass then
			runScript(frame, 'OnEvent', event, ...)
		end
	end
end

---Fire only if this flavor knows the event (for mock-internal notifications).
function M.FireIfKnown(event, ...)
	if knownEvent(event) then
		M.Fire(event, ...)
	end
end

----------------------------------------------------------------------------------------------------
-- Time and timers
----------------------------------------------------------------------------------------------------

M.timers = {}
local function addTimer(delay, fn, iterations)
	local t = { at = M.now + (delay or 0), fn = fn, delay = delay or 0, left = iterations }
	M.timers[#M.timers + 1] = t
	t.Cancel = function()
		t.cancelled = true
	end
	t.IsCancelled = function()
		return t.cancelled or false
	end
	return t
end

---Move the clock forward, running timers and one OnUpdate pass every 50 ms, like a running game.
function M.Advance(seconds)
	local target = M.now + (seconds or 0)
	while true do
		local stepEnd = math.min(M.now + 0.05, target)
		while true do
			local nextTimer, index
			for i, t in ipairs(M.timers) do
				if not t.cancelled and t.at <= stepEnd and (not nextTimer or t.at < nextTimer.at) then
					nextTimer, index = t, i
				end
			end
			if not nextTimer then
				break
			end
			M.now = math.max(M.now, nextTimer.at)
			nextTimer.left = nextTimer.left - 1
			if nextTimer.left <= 0 then
				table.remove(M.timers, index)
			else
				nextTimer.at = M.now + math.max(nextTimer.delay, 0.01)
			end
			M.Protect(nextTimer.fn)
		end
		local elapsed = stepEnd - M.now
		M.now = stepEnd
		M.RunOnUpdate(elapsed > 0 and elapsed or 0.05)
		if M.now >= target then
			break
		end
	end
end

function M.RunOnUpdate(elapsed)
	local list = {}
	for _, frame in ipairs(onUpdateOrder) do
		if onUpdate[frame] then
			list[#list + 1] = frame
		end
	end
	for _, frame in ipairs(list) do
		if isVisible(frame) then
			runScript(frame, 'OnUpdate', elapsed or 0.016)
		end
	end
end

---Frames whose OnUpdate would run on the next frame (shown, with a script or hook).
function M.ActiveOnUpdates()
	local out = {}
	for _, frame in ipairs(onUpdateOrder) do
		if onUpdate[frame] and isVisible(frame) then
			out[#out + 1] = frame
		end
	end
	return out
end

---Repeating timers that are still running.
function M.ActiveTickers()
	local out = {}
	for _, t in ipairs(M.timers) do
		if not t.cancelled and t.left > 1 then
			out[#out + 1] = t
		end
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- Combat and login
----------------------------------------------------------------------------------------------------

---Start combat: PLAYER_REGEN_DISABLED fires before lockdown begins, as in the game.
function M.EnterCombat()
	M.inCombat = true
	M.FireIfKnown('PLAYER_REGEN_DISABLED')
	M.lockdown = true
end

---End combat: lockdown ends before PLAYER_REGEN_ENABLED fires.
function M.LeaveCombat()
	M.lockdown = false
	M.inCombat = false
	M.FireIfKnown('PLAYER_REGEN_ENABLED')
end

---Load-to-world sequence for one addon: ADDON_LOADED, PLAYER_LOGIN, PLAYER_ENTERING_WORLD.
function M.Login(addonName)
	M.FireIfKnown('ADDON_LOADED', addonName or 'SpartanUI', false)
	M.FireIfKnown('VARIABLES_LOADED')
	M.loggedIn = true
	M.FireIfKnown('PLAYER_LOGIN')
	M.FireIfKnown('PLAYER_ENTERING_WORLD', true, false)
end

----------------------------------------------------------------------------------------------------
-- CVars
----------------------------------------------------------------------------------------------------

M.cvars = {}
for name in pairs(D.cvars or {}) do
	M.cvars[name] = { value = '0', default = '0' }
end

---Add or change a CVar the client knows (value, default, secure, account, character, locked, readOnly).
function M.SetCVarState(name, opts)
	local c = M.cvars[name] or { value = '0', default = '0' }
	for k, v in pairs(opts or {}) do
		c[k] = v
	end
	if opts and opts.value ~= nil then
		c.value = rawtostring(opts.value)
	end
	if opts and opts.default ~= nil then
		c.default = rawtostring(opts.default)
	end
	M.cvars[name] = c
	return c
end

---Remove a CVar, as on a client that does not have it.
function M.RemoveCVar(name)
	M.cvars[name] = nil
end

local function cvarString(value)
	if rawtype(value) == 'boolean' then
		return value and '1' or '0'
	end
	return rawtostring(value)
end

local function writeCVar(name, value, via)
	local c = M.cvars[name]
	if not c then
		return false
	end
	if c.secure and M.lockdown then
		M.rec.blocked[#M.rec.blocked + 1] = { label = via .. '(' .. name .. ')', where = M.Caller(4) }
		return
	end
	if c.readOnly or c.locked then
		return false
	end
	M.rec.cvarWrites[#M.rec.cvarWrites + 1] = { name = name, value = value, old = c.value, via = via, where = M.Caller(4) }
	c.value = value
	M.FireIfKnown('CVAR_UPDATE', name, value)
	return true
end

-- Bitfield CVars are kept as a number with bit (index - 1) for each index (UNVERIFIED in game)
local function bitIsSet(value, index)
	local n = tonumber(value) or 0
	return math.floor(n / 2 ^ (index - 1)) % 2 == 1
end

NS.C_CVar = {
	GetCVar = function(name)
		local c = M.cvars[name]
		return c and c.value
	end,
	GetCVarBool = function(name)
		local c = M.cvars[name]
		if c then
			return c.value == '1'
		end
	end,
	GetCVarDefault = function(name)
		local c = M.cvars[name]
		return c and c.default
	end,
	GetCVarInfo = function(name)
		local c = M.cvars[name]
		if c then
			return c.value, c.default, c.account or false, c.character or false, c.locked or false, c.secure or false, c.readOnly or false
		end
	end,
	SetCVar = function(name, value)
		return writeCVar(name, cvarString(value), 'SetCVar')
	end,
	SetCVarToDefault = function(name)
		local c = M.cvars[name]
		if c then
			return writeCVar(name, c.default, 'SetCVarToDefault')
		end
		return false
	end,
	GetCVarBitfield = function(name, index)
		local c = M.cvars[name]
		if c then
			return bitIsSet(c.value, index)
		end
	end,
	SetCVarBitfield = function(name, index, value)
		local c = M.cvars[name]
		if not c then
			return false
		end
		local n = tonumber(c.value) or 0
		local set = bitIsSet(n, index)
		if value and not set then
			n = n + 2 ^ (index - 1)
		elseif not value and set then
			n = n - 2 ^ (index - 1)
		end
		return writeCVar(name, rawtostring(math.floor(n)), 'SetCVarBitfield')
	end,
	RegisterCVar = function(name, default)
		if not M.cvars[name] then
			M.cvars[name] = { value = cvarString(default or ''), default = cvarString(default or '') }
		end
	end,
}

----------------------------------------------------------------------------------------------------
-- Colors and backdrops (FrameXML mixins the models hand out)
----------------------------------------------------------------------------------------------------

M.ColorMixin = {}
local ColorMixin = M.ColorMixin
function ColorMixin:SetRGBA(r, g, b, a)
	self.r, self.g, self.b, self.a = r, g, b, a
end
function ColorMixin:SetRGB(r, g, b)
	self:SetRGBA(r, g, b, nil)
end
function ColorMixin:GetRGB()
	return self.r, self.g, self.b
end
function ColorMixin:GetRGBA()
	return self.r, self.g, self.b, self.a or 1
end
function ColorMixin:GetRGBAsBytes()
	return math.floor(self.r * 255 + 0.5), math.floor(self.g * 255 + 0.5), math.floor(self.b * 255 + 0.5)
end
function ColorMixin:GenerateHexColor()
	local r, g, b = self:GetRGBAsBytes()
	return ('ff%.2x%.2x%.2x'):format(r, g, b)
end
function ColorMixin:GenerateHexColorMarkup()
	return '|c' .. self:GenerateHexColor()
end
function ColorMixin:WrapTextInColorCode(text)
	return '|c' .. self:GenerateHexColor() .. text .. '|r'
end
function ColorMixin:IsEqualTo(other)
	return self.r == other.r and self.g == other.g and self.b == other.b and self.a == other.a
end

M.BackdropTemplateMixin = {
	SetBackdrop = function(self, info)
		state[self].backdrop = info
	end,
	GetBackdrop = function(self)
		return state[self].backdrop
	end,
	SetBackdropColor = function(self, r, g, b, a)
		state[self].backdropColor = { r, g, b, a }
	end,
	SetBackdropBorderColor = function(self, r, g, b, a)
		state[self].backdropBorderColor = { r, g, b, a }
	end,
	ApplyBackdrop = function() end,
	ClearBackdrop = function(self)
		state[self].backdrop = nil
	end,
}

---Read a literal Lua table Blizzard defines (see framexml.lua M.LiteralTable models).
function M.LiteralTable(name)
	local t = D.fxmlTables and D.fxmlTables[name]
	local out = {}
	for k, v in pairs(t or {}) do
		out[k] = v
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- Engine functions every client has (most are not in the generated documentation)
----------------------------------------------------------------------------------------------------

local CORE = {}
M.CORE = CORE

CORE.CreateFrame = function(frameType, name, parent, template, id)
	local info = TYPES[frameType]
	if not info or not info.frame or (info.auraContainer and not next(D.auraContainer or {})) then
		error(("CreateFrame: Unknown frame type '%s'"):format(rawtostring(frameType)), 2)
	end
	if rawtype(parent) == 'string' then
		parent = _G[parent]
	end
	if rawtype(name) == 'string' and parent and name:find('$parent', 1, true) then
		name = name:gsub('%$parent', state[parent] and state[parent].name or '')
	end
	local frame = M.NewObject(frameType, name, parent)
	if id then
		state[frame].id = id
	end
	if name then
		_G[name] = frame
		recordGlobal(name, frameType)
	end
	applyTemplates(frame, template, 3)
	runScript(frame, 'OnLoad')
	return frame
end
CORE.CreateFont = function(name)
	local font = M.NewObject('Font', name)
	if name then
		_G[name] = font
		recordGlobal(name, 'Font')
	end
	return font
end
CORE.hooksecurefunc = function(a, b, c)
	local tbl, name, fn
	if rawtype(a) == 'string' then
		tbl, name, fn = _G, a, b
	else
		tbl, name, fn = a, b, c
	end
	if rawtype(tbl) ~= 'table' or rawtype(name) ~= 'string' or rawtype(fn) ~= 'function' then
		error('Usage: hooksecurefunc([table,] "functionName", hookfunc)', 2)
	end
	local original = tbl[name]
	if rawtype(original) ~= 'function' then
		error(('hooksecurefunc(): %s is not a function'):format(name), 2)
	end
	M.rec.hooks[#M.rec.hooks + 1] = { target = tbl, name = name, where = M.Caller() }
	local function pack(...)
		return { n = select('#', ...), ... }
	end
	rawset(tbl, name, function(...)
		local results = pack(original(...))
		M.Protect(fn, ...)
		return unpack(results, 1, results.n)
	end)
end
CORE.issecure = function()
	return false
end
CORE.issecurevariable = function()
	return false, 'TestAddon'
end
CORE.securecall = function(fn, ...)
	if rawtype(fn) == 'string' then
		fn = _G[fn]
	end
	return fn(...)
end
CORE.securecallfunction = function(fn, ...)
	return fn(...)
end
CORE.forceinsecure = function() end
CORE.debugstack = function()
	return debug.traceback('', 2)
end
CORE.debugprofilestart = function() end
CORE.debugprofilestop = function()
	return os.clock() * 1000
end
CORE.geterrorhandler = function()
	return errorHandler
end
CORE.seterrorhandler = function(fn)
	errorHandler = fn
end
CORE.EnumerateFrames = function(after)
	local start = 1
	if after then
		for i, f in ipairs(M.allFrames) do
			if f == after then
				start = i + 1
				break
			end
		end
	end
	return M.allFrames[start]
end
CORE.GetFramesRegisteredForEvent = function(event)
	local out = {}
	for _, f in ipairs(eventFrames) do
		if state[f].events[event] then
			out[#out + 1] = f
		end
	end
	return unpack(out)
end
CORE.GetBuildInfo = function()
	return D.meta.version, D.meta.build, 'Oct 1 2026', D.meta.interface, 'Release x64', D.meta.interface
end
CORE.GetLocale = function()
	return 'enUS'
end
CORE.GetCurrentRegion = function()
	return 1
end
CORE.GetPhysicalScreenSize = function()
	return 1920, 1080
end
CORE.GetTime = function()
	return M.now
end
CORE.InCombatLockdown = function()
	return M.lockdown
end
CORE.IsLoggedIn = function()
	return M.loggedIn
end

FN.GetTime = CORE.GetTime
FN.InCombatLockdown = CORE.InCombatLockdown
FN.IsLoggedIn = CORE.IsLoggedIn
FN.GetServerTime = function()
	return os.time()
end
FN.GetFramerate = function()
	return 60
end
FN.CreateFontFamily = function(name, members)
	local font = M.NewObject('Font', name)
	state[font].members = members
	_G[name] = font
	recordGlobal(name, 'FontFamily')
	return font
end
FN.Mixin = FX.Mixin
FN.CreateFromMixins = function(...)
	return FX.Mixin({}, ...)
end
FN.canaccessvalue = function(v)
	return not S.IsSecret(v)
end
FN.canaccessallvalues = function(...)
	return not S.Any(...)
end
FN.canaccesssecrets = function()
	return false
end
FN.canaccesstable = function(t)
	return not S.IsSecret(t)
end
FN.issecretvalue = function(v)
	return S.IsSecret(v)
end
FN.hasanysecretvalues = function(...)
	return S.Any(...)
end
FN.issecrettable = function()
	return false
end
FN.scrubsecretvalues = function(...)
	local n = select('#', ...)
	local t = { ... }
	for i = 1, n do
		if S.IsSecret(t[i]) then
			t[i] = nil
		end
	end
	return unpack(t, 1, n)
end
FN.AbbreviateNumbers = function(value)
	local plain = S.Reveal(value)
	local text
	if rawtype(plain) ~= 'number' then
		text = rawtostring(plain)
	elseif plain >= 1e6 then
		text = ('%.1fM'):format(plain / 1e6)
	elseif plain >= 1e3 then
		text = ('%.1fK'):format(plain / 1e3)
	else
		text = rawtostring(math.floor(plain))
	end
	if S.IsSecret(value) then
		return S.Wrap(text)
	end
	return text
end
FN.BreakUpLargeNumbers = function(value)
	local plain = S.Reveal(value)
	local text = rawtostring(math.floor(tonumber(plain) or 0)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
	if S.IsSecret(value) then
		return S.Wrap(text)
	end
	return text
end
NS.C_Timer = {
	After = function(delay, fn)
		addTimer(delay, fn, 1)
	end,
	NewTimer = function(delay, fn)
		local t
		t = addTimer(delay, function()
			fn(t)
		end, 1)
		return t
	end,
	NewTicker = function(delay, fn, iterations)
		local t
		t = addTimer(delay, function()
			fn(t)
		end, iterations or math.huge)
		if not iterations or iterations > 1 then
			M.rec.tickers[#M.rec.tickers + 1] = { timer = t, where = M.Caller() }
		end
		return t
	end,
}

NS.C_XMLUtil = {
	GetTemplateInfo = function(name)
		if M.templates[name] then
			return { type = 'Frame', width = 0, height = 0, keyValues = {}, inherits = nil }
		end
	end,
}

NS.C_AddOns = {
	IsAddOnLoaded = function(name)
		return M.loadedAddons and M.loadedAddons[name] or false
	end,
	GetAddOnMetadata = function(_, field)
		if field == 'Version' then
			return 'test'
		end
	end,
}

----------------------------------------------------------------------------------------------------
-- Units, plates, secrets predicates (units.lua fills FN/NS/W with the world model)
----------------------------------------------------------------------------------------------------

local unitsChunk = assert(loadfile(HARNESS .. 'units.lua'))
unitsChunk(M, FN, NS, W, WT, S, state)

----------------------------------------------------------------------------------------------------
-- Install the globals for this flavor
----------------------------------------------------------------------------------------------------

M.fnLog = {}
local function genericFunction(label)
	return function(...)
		M.rec.unmodeled[label] = (M.rec.unmodeled[label] or 0) + 1
		local list = M.fnLog[label] or {}
		M.fnLog[label] = list
		list[#list + 1] = { n = select('#', ...), ... }
	end
end

---Calls made to a documented function the mock has no behavior for ("C_Name.Function" or "Name").
function M.FnCalls(label)
	return M.fnLog[label] or {}
end

local function wrapAllReturns(...)
	local n = select('#', ...)
	local t = { ... }
	for i = 1, n do
		local v = t[i]
		if rawtype(v) == 'table' and not state[v] then
			local copy = {}
			for k, fv in pairs(v) do
				copy[k] = (rawtype(fv) == 'table' or rawtype(fv) == 'function') and fv or S.Wrap(fv)
			end
			t[i] = copy
		elseif rawtype(v) ~= 'function' and not (rawtype(v) == 'table' and state[v]) then
			t[i] = S.Wrap(v)
		end
	end
	return unpack(t, 1, n)
end

-- Forced restricted mode on a Classic flavor borrows Retail's secret markers (its docs have none)
local retailSpecs
local function retailSpec(label)
	if not retailSpecs then
		local ok, data = pcall(dofile, ROOT .. 'Tests/Nameplates/data/retail.lua')
		retailSpecs = ok and data or { functions = {}, namespaces = {} }
	end
	local nsName, fnName = label:match('^([^.]+)%.(.+)$')
	if nsName then
		return retailSpecs.namespaces[nsName] and retailSpecs.namespaces[nsName][fnName]
	end
	return retailSpecs.functions[label]
end

local function wrapFunction(label, spec, impl)
	local p = parseSpec(spec)
	local guard = M.secrets and (p.policy == 'U' or p.policy == 'N') and not SECRET_INSPECTORS[label]
	local blocks = p.flags.HasRestrictions
	local categories = M.SecretCategories(p.flags)
	local borrowed
	return function(...)
		if guard and S.Any(...) then
			error(('%s: secret values are not allowed from addon code (SecretArguments = %s)'):format(label, p.policy == 'U' and 'AllowedWhenUntainted' or 'NotAllowed'), 2)
		end
		if blocks and M.lockdown then
			M.rec.blocked[#M.rec.blocked + 1] = { label = label, where = M.Caller() }
			M.FireIfKnown('ADDON_ACTION_BLOCKED', 'TestAddon', label)
			return
		end
		local cats, unitIndex, flags = categories, p.unit, p.flags
		if M.restrict.forced and not cats then
			if not borrowed then
				local rp = parseSpec(retailSpec(label))
				borrowed = { categories = M.SecretCategories(rp.flags) or false, unit = rp.unit, flags = rp.flags }
			end
			cats, unitIndex, flags = borrowed.categories or nil, borrowed.unit, borrowed.flags
		end
		if cats and unitIndex > 0 then
			local mode = M.SecretMode(cats, flags, (select(unitIndex, ...)))
			if mode == 'nothing' then
				return
			elseif mode == 'secret' then
				return wrapAllReturns(impl(...))
			end
		end
		return impl(...)
	end
end
M.WrapFunction = wrapFunction

-- Lua 5.1 standard library and WoW's Lua aliases are already in place (shims.lua)
for name, fn in pairs(CORE) do
	_G[name] = fn
end
-- Documented globals keep a Lua implementation that is already in place (shims.lua: wipe, strtrim, ...)
for name, spec in pairs(D.functions) do
	if not CORE[name] then
		local existing = rawget(_G, name)
		_G[name] = wrapFunction(name, spec, FN[name] or (rawtype(existing) == 'function' and existing) or genericFunction(name))
	end
end
for name in pairs(D.engine or {}) do
	if rawget(_G, name) == nil and not (D.fxml[name] and FX.models[name]) then
		_G[name] = wrapFunction(name, nil, FN[name] or genericFunction(name))
	end
end
-- Namespaces that are Lua libraries (Forever documents string, table and math) are added to, never replaced
for nsName, functions in pairs(D.namespaces) do
	local existing = rawget(_G, nsName)
	local ns = rawtype(existing) == 'table' and existing or {}
	local impls = NS[nsName] or {}
	for fnName, spec in pairs(functions) do
		local label = nsName .. '.' .. fnName
		local current = rawget(ns, fnName)
		if rawtype(current) == 'function' and not impls[fnName] then
			ns[fnName] = wrapFunction(label, spec, current)
		else
			ns[fnName] = wrapFunction(label, spec, impls[fnName] or genericFunction(label))
		end
	end
	_G[nsName] = ns
end
-- Lua-defined additions to documented namespaces
if C_Timer then
	C_Timer.NewTimer = C_Timer.NewTimer or NS.C_Timer.NewTimer
	C_Timer.NewTicker = C_Timer.NewTicker or NS.C_Timer.NewTicker
end

-- Engine constants and frames
Enum = {}
for name, values in pairs(D.enums) do
	local copy = {}
	for k, v in pairs(values) do
		copy[k] = v
	end
	Enum[name] = copy
end
-- Enums Blizzard's code uses but the docs leave out; values are placeholders (1..n)
for name, values in pairs(D.enumsUndocumented or {}) do
	if not Enum[name] then
		local copy = {}
		for k, v in pairs(values) do
			copy[k] = v
		end
		Enum[name] = copy
	end
end
Constants = {}
for name, values in pairs(D.constants or {}) do
	local copy = {}
	for k, v in pairs(values) do
		copy[k] = v
	end
	Constants[name] = copy
end
WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 2, 5
WOW_PROJECT_WRATH_CLASSIC, WOW_PROJECT_CATACLYSM_CLASSIC, WOW_PROJECT_MISTS_CLASSIC = 11, 14, 19
WOW_PROJECT_ID = D.meta.project
UIParent = M.NewObject('Frame', 'UIParent')
state[UIParent].w, state[UIParent].h = 1920, 1080
WorldFrame = M.NewObject('Frame', 'WorldFrame')
state[WorldFrame].w, state[WorldFrame].h = 1920, 1080
STANDARD_TEXT_FONT = 'Fonts\\FRIZQT__.TTF'
SlashCmdList = {}
hash_SlashCmdList = {}

-- FrameXML globals and templates this branch defines
for name, build in pairs(FX.models) do
	if D.fxml[name] and _G[name] == nil then
		_G[name] = build(M)
	end
end
for name, apply in pairs(FX.templates) do
	if D.templates and D.templates[name] then
		M.templates[name] = function(frame)
			apply(M, frame)
		end
	end
end

---Register a template the addon defines in its own XML (the loader does this).
function M.RegisterTemplate(name, apply)
	M.templates[name] = apply or function() end
end

-- Snapshot of _G after the mock is in place, so suites can list names addon code adds
M.baseGlobals = {}
for k in pairs(_G) do
	M.baseGlobals[k] = true
end

---Global names added since the given snapshot (or since the mock loaded).
function M.NewGlobals(snapshot)
	snapshot = snapshot or M.baseGlobals
	local out = {}
	for k in pairs(_G) do
		if not snapshot[k] then
			out[#out + 1] = k
		end
	end
	table.sort(out, function(a, b)
		return rawtostring(a) < rawtostring(b)
	end)
	return out
end

---Take a snapshot of the current global names.
function M.SnapshotGlobals()
	local snap = {}
	for k in pairs(_G) do
		snap[k] = true
	end
	return snap
end

return M
