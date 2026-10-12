local _, ns = ...
local P = ns.Plates
local L = P.L

-- Preview scenes for the options side panel, gallery cards and setup cards (5.6). Owner: Phase 4a
-- (a plain version is enough for Phase 2 testers). Every plate in a scene is a real Plate built
-- with Plate.New(canvas, true) and filled with Plate:BindSample(Source.NewSample(id)), so previews
-- run the same parts as real plates. Preview plates stay insecure, never call Unit* and are never
-- anchored to real plates.
--
-- Scenes (by page, 5.6):
--   pull   Style and Sharing pages: P.Data.PULL in a slightly staggered column with faint labels
--   focus  Customize and Auras: one plate of the "Preview as" kind at fit scale, the selected
--          part outlined; two small 1x plates below (not target, faded; casting)
--   rows   Colors: one plate per row of the open color list, labeled with the row's sentence;
--          past 8 rows it fits to height down to 0.6, then "+N more"
--   kinds  Who and where: one plate per kind in its assigned style and Show mode; Hidden draws a
--          faint outline with the word Hidden
-- Size budget: a Medium Clean plate with marker, crowd control row, aura row, name and cast is
-- about 204 x 56; five with labels and gaps fit in about 390 px.
-- Context: preview plates never read P.Context. Each scene builds one with
-- Scenes.PreviewContext(fields) and passes it to Plate.New(canvas, true, ctx) (or
-- plate:SetContext for pooled plates), so the "pull" scene can show a tank's view in a group
-- (role, inGroup, tanks = { 'party1' } so a sample with tankedByOther shows "another tank is
-- holding it") whatever the player is doing. Colors caches one program set per context table.

---@class Plates.SceneDef
---@field id string
---@field samples? string[] Sample ids, top to bottom
---@field stagger? number Horizontal stagger in pixels
---@field gap? number Vertical gap
---@field labels? boolean

---@class Plates.Scenes
local Scenes = { pools = setmetatable({}, { __mode = 'k' }) }
P.Scenes = Scenes

Scenes.DEFS = {
	pull = { id = 'pull', samples = P.Data.PULL, stagger = 6, gap = 18, labels = true },
	focus = { id = 'focus', samples = { 'casterTarget' }, gap = 20, labels = false },
	rows = { id = 'rows', samples = {}, gap = 14, labels = true },
	kinds = { id = 'kinds', samples = { 'casterTarget', 'enemyPlayer', 'friendlyNPC', 'friendlyPlayer', 'minorGray' }, gap = 18, labels = true },
}

Scenes.LABEL_SAMPLE_ICONS = L['sample icons']

---A context for preview plates: the live context's place and level with the scene's own role,
---group and tanks on top. Keep the returned table (Colors caches programs per context table).
---@param fields? table role, inGroup, tanks, petTank, hasTarget, place, ...
---@return Plates.Context
function Scenes.PreviewContext(fields)
	local live = P.Context
	local ctx = {
		place = live.place or 'world',
		inCombat = false,
		resting = false,
		role = live.role or 'damage',
		inGroup = true,
		groupSize = 5,
		tanks = {},
		petTank = false,
		playerLevel = live.playerLevel or 1,
		hasTarget = true,
	}
	for k, v in pairs(fields or {}) do
		ctx[k] = v
	end
	return ctx
end

---@class Plates.SceneResult
---@field width number Bounds of everything drawn, for the provider's fit scale
---@field height number
---@field plates Plates.Plate[]

---Draw a scene on a canvas (preview plates are pooled per canvas).
---@param canvas table
---@param sceneId string
---@param opts? { styleId?: string, kind?: string, rows?: table[] }
---@return Plates.SceneResult
function Scenes:Render(canvas, sceneId, opts)
	return { width = 0, height = 0, plates = {} }
end

---Hide every preview plate drawn on a canvas.
---@param canvas table
function Scenes:Release(canvas)
	local pool = self.pools[canvas]
	if not pool then
		return
	end
	for _, plate in ipairs(pool) do
		plate:Unbind()
	end
end
