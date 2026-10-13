-- @runtime lua51
-- Click and stacking areas you can see (Engine/Parts/Region.lua): the eye toggle draws both boxes
-- on every plate at the style's areas, real plates follow the Driver's click and stack frames (or
-- Blizzard's base plate when hit-test rebinding is off), one plate can be shown alone, a region
-- part draws its own box, and a hand-placed region part becomes the real click area.
local M, H = ...

if not H.ModuleExists() then
	describe('regions', function()
		pending('all', 'Modules/Nameplates/Load.xml does not exist yet')
	end)
	return
end

M.Login('NameplatesTestHost')
local P = H.FreshCore()
local Merge = P.Styles.Merge
local Registry = P.Styles.Registry
local Regions = P.Regions

local function Shown(region)
	return M.Get(region, 'shown') == true
end

local function Points(region)
	return M.Get(region, 'points') or {}
end

local function PreviewPlate(styleId)
	local plate = P.Plate.New(UIParent, true)
	plate:ApplyStyle(Merge:Resolve(styleId or 'clean', 'enemyNPC', 'medium'))
	plate:BindSample(P.Source.NewSample('casterTarget'))
	return plate
end

describe('regions: boxes', function()
	after_each(function()
		Regions:SetShowAll(false)
	end)

	it('draws nothing until asked', function()
		local plate = PreviewPlate()
		assert.is_nil(Regions.boxes[plate], 'no frames are made for plates that never show boxes')
		plate:Unbind()
	end)

	it('draws both areas on every plate while Show all parts is on', function()
		local plate = PreviewPlate()
		local fired
		P:On('REGION_BOXES_CHANGED', function(on)
			fired = on
		end, 'regionTest')
		Regions:SetShowAll(true)
		P:Off('REGION_BOXES_CHANGED', 'regionTest')
		assert.is_true(fired)
		local boxes = Regions.boxes[plate]
		assert.not_nil(boxes)
		local click = plate.style.regions.click
		assert.is_true(Shown(boxes.click))
		assert.is_true(Shown(boxes.stack))
		local points = Points(boxes.click)
		assert.equal(points[1][1], 'TOPLEFT')
		assert.equal(points[1][2], plate.art)
		assert.equal(points[1][3], 'CENTER')
		assert.equal(points[1][4], click.left)
		assert.equal(points[1][5], click.top)
		assert.equal(points[2][4], click.right)
		assert.equal(points[2][5], click.bottom)
		assert.equal(M.Get(boxes.click.label, 'text'), Regions.LABELS.click)
		Regions:SetShowAll(false)
		assert.is_false(Shown(boxes.click))
		assert.is_false(Shown(boxes.stack))
		plate:Unbind()
	end)

	it('draws boxes on plates laid out after the toggle', function()
		Regions:SetShowAll(true)
		local plate = PreviewPlate('mini')
		assert.is_true(Shown(Regions.boxes[plate].click))
		plate:Unbind()
	end)

	it('shows one plate alone, whatever the toggle says', function()
		local a, b = PreviewPlate(), PreviewPlate()
		Regions:ShowBoxes(a, true)
		assert.is_true(Shown(Regions.boxes[a].click))
		assert.is_nil(Regions.boxes[b])
		Regions:SetShowAll(true)
		Regions:ShowBoxes(a, false)
		assert.is_false(Shown(Regions.boxes[a].click))
		assert.is_true(Shown(Regions.boxes[b].click))
		Regions:ShowBoxes(a, nil)
		assert.is_true(Shown(Regions.boxes[a].click), 'nil goes back to the toggle')
		a:Unbind()
		b:Unbind()
	end)

	it('covers the real click and stacking frames on live plates', function()
		local plate = P.Plate.New(UIParent, false)
		plate.click = CreateFrame('Frame', nil, UIParent)
		plate.stack = CreateFrame('Frame', nil, UIParent)
		plate.base = CreateFrame('Frame', nil, UIParent)
		plate:ApplyStyle(Merge:Resolve('clean', 'enemyNPC', 'medium'))
		Regions:SetShowAll(true)
		local boxes = Regions.boxes[plate]
		assert.equal(M.Get(boxes.click, 'allPointsTo'), plate.click)
		assert.equal(M.Get(boxes.stack, 'allPointsTo'), plate.stack)
		P.Caps:Record('hitTest', false)
		Regions:Refresh(plate)
		assert.equal(M.Get(boxes.click, 'allPointsTo'), plate.base, 'Blizzard keeps the click area (S1)')
		P.Caps.recorded.hitTest = nil
	end)

	it('never takes the mouse', function()
		local plate = PreviewPlate()
		Regions:SetShowAll(true)
		assert.is_false(Regions.boxes[plate].click:IsMouseEnabled())
		assert.is_false(Regions.boxes[plate].stack:IsMouseEnabled())
		plate:Unbind()
	end)
end)

describe('regions: the part', function()
	local styleId = 'regionTest'
	Registry:RegisterBuiltin({
		id = styleId,
		name = 'Region test',
		version = 1,
		schema = 1,
		order = 900,
		internal = true,
		plate = { sizes = { small = { 100, 8 }, medium = { 120, 10 }, large = { 140, 12 } } },
		regions = { click = { auto = true, pad = { 2, 2, 2, 2 } }, stack = { auto = true, pad = { 2, 2, 2, 2 } } },
		parts = {
			health = { order = 10, kind = 'bar', source = 'health', fill = 'plate' },
			clickArea = { order = 90, kind = 'region', region = 'click', width = 160, height = 30, anchor = { 'CENTER', 'plate', 'CENTER', 10, 4 } },
			stackArea = { order = 91, kind = 'region', region = 'stack' },
		},
	})

	after_each(function()
		Regions:SetShowAll(false)
	end)

	it('passes the import checks', function()
		local _, report = P.Styles.Schema:ValidateStyle(Registry:Get(styleId))
		assert.equal(report.dropped + report.clamped + report.fixed, 0)
	end)

	it('makes a hand-placed region the real click area', function()
		local resolved = Merge:Resolve(styleId, 'enemyNPC', 'medium')
		assert.same(resolved.regions.click, { left = -70, right = 90, top = 19, bottom = -11 })
		-- the stacking area without a size keeps the worked-out area (the bar plus its pad)
		assert.same(resolved.regions.stack, { left = -62, right = 62, top = 7, bottom = -7 })
		local w, h = Merge.SizeForRect(resolved.regions.click)
		assert.equal(w, 180)
		assert.equal(h, 30)
	end)

	it('draws its own box only while boxes are shown, and the plate skips that area', function()
		local plate = PreviewPlate(styleId)
		local clickPart = plate:GetWidget('clickArea')
		local stackPart = plate:GetWidget('stackArea')
		assert.not_nil(clickPart)
		assert.is_false(Shown(clickPart.box))
		Regions:SetShowAll(true)
		assert.is_true(Shown(clickPart.box))
		assert.is_true(Shown(stackPart.box))
		assert.equal(M.Get(clickPart.frame, 'w'), 160)
		local boxes = Regions.boxes[plate]
		assert.is_false(Shown(boxes.click), 'the part draws the click box')
		assert.is_false(Shown(boxes.stack), 'the part draws the stacking box')
		local stackRect = plate.style.regions.stack
		local points = Points(stackPart.frame)
		assert.equal(points[1][4], stackRect.left)
		assert.equal(points[2][5], stackRect.bottom)
		Regions:SetShowAll(false)
		assert.is_false(Shown(clickPart.box))
		plate:Unbind()
	end)
end)

describe('regions: with the engine running', function()
	after_each(function()
		Regions:SetShowAll(false)
		if P.enabled then
			P:Disable()
		end
	end)

	it('draws real plates over the Driver click and stacking frames', function()
		P:Enable()
		local token, base = M.ShowPlate({ name = 'Gnoll', canAttack = true, reaction = 2 })
		local plate = P.API:GetPlate(base)
		if not (plate and plate.click and plate.stack) then
			M.HidePlate(token)
			skip('the Driver does not make click and stacking frames in this build')
		end
		Regions:SetShowAll(true)
		local boxes = Regions.boxes[plate]
		assert.not_nil(boxes)
		assert.is_true(Shown(boxes.click))
		local clickTarget = Regions.HitTestOff() and plate.base or plate.click
		assert.equal(M.Get(boxes.click, 'allPointsTo'), clickTarget)
		assert.equal(M.Get(boxes.stack, 'allPointsTo'), plate.stack)
		Regions:SetShowAll(false)
		assert.is_false(Shown(boxes.click))
		M.HidePlate(token)
	end)
end)
