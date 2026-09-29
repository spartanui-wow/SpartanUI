---@class SUI.UF
local UF = SUI.UF
local L = SUI.L

-- Unit frame preview for the options window: the frame being edited, drawn with sample data,
-- and each part clickable to jump to its settings.

local Stage = SUI.OptionsWindow and SUI.OptionsWindow.Stage
if not Stage then
	return
end

-- Large parts first: later parts get the higher click layer
local PARTS = {
	'FrameBackground',
	'Portrait',
	'Health',
	'Power',
	'Castbar',
	'Name',
	'ClassIcon',
	'RaidTargetIndicator',
	'LeaderIndicator',
	'RaidRoleIndicator',
	'RestingIndicator',
	'CombatIndicator',
	'ReadyCheckIndicator',
}
local AURA_PARTS = { 'BuffContainer', 'DebuffContainer', 'CustomAuras' }
local GAP = 8

---@param ctx SUI.OptionsWindow.StageContext
---@return string|nil
local function GetFrameName(ctx)
	local frameName = ctx.path[2]
	local settings = frameName and UF.CurrentSettings[frameName]
	if not settings or not settings.enabled or not UF.Unit:Get(frameName) then
		return nil
	end
	return frameName
end

---@type SUI.OptionsWindow.StageProvider
local provider = { path = { 'UnitFrames' } }

function provider:GetHeight(ctx)
	local frameName = GetFrameName(ctx)
	if not frameName then
		return 0
	end
	local height = UF:CalculateHeight(frameName) or 40
	local settings = UF.CurrentSettings[frameName]
	local count = UF.PreviewFrame:GetStageCount(frameName)
	if count > 1 and (settings.point == 'TOP' or settings.point == 'BOTTOM') then
		height = height * count + math.abs(settings.yOffset or 1) * (count - 1)
	end
	local elements = settings.elements or {}
	for _, auraElement in ipairs(AURA_PARTS) do
		local db = elements[auraElement]
		if db and db.enabled then
			local perRow = math.max(1, db.perRow or 8)
			local rows = math.min(2, math.ceil((db.number or perRow) / perRow))
			height = height + rows * ((db.size or 24) + (db.spacing or 2))
		end
	end
	return math.max(80, math.min(260, height * 1.2 + 24))
end

---Union of the preview frames and their sample aura rows, relative to the canvas center, in canvas units
---@return number left, number bottom, number right, number top
local function MeasureBounds(canvas, frames)
	local scale = canvas:GetEffectiveScale()
	local cx, cy = canvas:GetCenter()
	local left, bottom, right, top
	local function Add(region)
		local l, b, w, h = region:GetRect()
		if not l then
			return
		end
		local s = region:GetEffectiveScale() / scale
		l, b, w, h = l * s - cx, b * s - cy, w * s, h * s
		left = left and math.min(left, l) or l
		bottom = bottom and math.min(bottom, b) or b
		right = right and math.max(right, l + w) or l + w
		top = top and math.max(top, b + h) or b + h
	end
	for _, preview in ipairs(frames) do
		Add(preview)
		for _, part in ipairs(PARTS) do
			local element = preview[part]
			if element and element.IsShown and element:IsShown() and element.GetRect then
				Add(element)
			end
		end
		for _, auraElement in ipairs(AURA_PARTS) do
			local holder = preview['_sample' .. auraElement]
			if holder and holder:IsShown() then
				Add(holder)
			end
		end
	end
	return left or 0, bottom or 0, right or 1, top or 1
end

function provider:Render(ctx)
	local frameName = GetFrameName(ctx)
	if not frameName then
		self:Hide()
		return
	end
	local canvas = ctx.canvas
	local frames = UF.PreviewFrame:RenderStage(frameName, canvas)
	local settings = UF.CurrentSettings[frameName]
	local frameWidth = settings.width or 180
	local frameHeight = UF:CalculateHeight(frameName) or 40
	local offsets = {}

	-- Group frames stack the way the real group grows: TOP/BOTTOM in a column, LEFT/RIGHT in a row
	local point = settings.point
	local vertical = #frames > 1 and (point == 'TOP' or point == 'BOTTOM')
	local stepX = vertical and 0 or (frameWidth + (point and math.abs(settings.xOffset or 0) or GAP))
	local stepY = vertical and (frameHeight + math.abs(settings.yOffset or 1)) or 0
	local direction = (point == 'BOTTOM' or point == 'RIGHT') and -1 or 1

	-- Lay out at scale 1, measure everything that will be drawn, then scale and center it
	for i, preview in ipairs(frames) do
		local index = i - 1 - (#frames - 1) / 2
		offsets[i] = { index * stepX * direction, -index * stepY * direction }
		preview:SetScale(1)
		preview:ClearAllPoints()
		preview:SetPoint('CENTER', canvas, 'CENTER', offsets[i][1], offsets[i][2])
	end
	local left, bottom, right, top = MeasureBounds(canvas, frames)
	local canvasWidth, canvasHeight = canvas:GetSize()
	local scale = math.min(1, (canvasHeight - 16) / math.max(1, top - bottom), (canvasWidth - 24) / math.max(1, right - left))
	scale = math.max(0.3, scale)
	local shiftX, shiftY = (left + right) / 2, (bottom + top) / 2

	for i, preview in ipairs(frames) do
		preview:SetScale(scale)
		preview:ClearAllPoints()
		preview:SetPoint('CENTER', canvas, 'CENTER', offsets[i][1] - shiftX, offsets[i][2] - shiftY)

		for _, part in ipairs(PARTS) do
			local element = preview[part]
			local settings = UF.Elements:GetConfig(part)
			local optionType = settings and settings.config and settings.config.type
			if element and element:IsShown() and optionType then
				local displayName = settings.config.DisplayName and L[settings.config.DisplayName] or part
				ctx.Region(element, { path = { 'UnitFrames', frameName, optionType, part }, label = displayName })
			end
		end

		for _, auraElement in ipairs(AURA_PARTS) do
			local holder = preview['_sample' .. auraElement]
			if holder and holder:IsShown() then
				local settings = UF.Elements:GetConfig(auraElement)
				local displayName = settings and settings.config and settings.config.DisplayName or auraElement
				ctx.Region(holder, { path = { 'UnitFrames', frameName, 'Auras', auraElement }, label = displayName .. ' - ' .. L['sample icons'] })
			end
		end
	end
end

function provider:Hide()
	UF.PreviewFrame:HideStage()
end

Stage:Register(provider)
