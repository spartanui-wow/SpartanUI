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
local ART_PARTS = { 'full', 'bg', 'top', 'bottom' }
local FOOTER_RESERVE = 28

-- Parts the player hid from the preview (this session only; the real frame is not touched)
local hidden = {} -- hidden[frameName][partName] = true

local function HiddenCount(frameName)
	local count = 0
	for _ in pairs(hidden[frameName] or {}) do
		count = count + 1
	end
	return count
end

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
local provider = { path = { 'UnitFrames' }, zoomable = true }

function provider:GetHeight(ctx)
	local frameName = GetFrameName(ctx)
	if not frameName then
		return 0
	end
	local settings = UF.CurrentSettings[frameName]
	local _, _, height = UF.Unit:GroupOffsets(frameName, UF.PreviewFrame:GetStageCount(frameName))
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
	local function Add(region, scaleSource)
		local l, b, w, h = region:GetRect()
		if not l then
			return
		end
		local s = (scaleSource or region):GetEffectiveScale() / scale
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
		local art = preview.SpartanArt
		if art and art:IsShown() then
			for _, pos in ipairs(ART_PARTS) do
				local texture = art[pos]
				if texture and texture:IsShown() then
					Add(texture, art)
				end
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
	local hiddenParts = hidden[frameName] or {}
	for _, preview in ipairs(frames) do
		for partName in pairs(hiddenParts) do
			local element = preview[partName]
			if element and element.Hide then
				element:Hide()
			end
			local holder = preview['_sample' .. partName]
			if holder then
				holder:Hide()
			end
		end
	end
	local reserve = HiddenCount(frameName) > 0 and FOOTER_RESERVE or 0
	-- Group frames sit the way the real group grows (growth direction, frames per column, offsets)
	local offsets = UF.Unit:GroupOffsets(frameName, #frames)

	-- Lay out at scale 1, measure everything that will be drawn, then scale and center it
	for i, preview in ipairs(frames) do
		preview:SetScale(1)
		preview:ClearAllPoints()
		preview:SetPoint('CENTER', canvas, 'CENTER', offsets[i][1], offsets[i][2])
	end
	local left, bottom, right, top = MeasureBounds(canvas, frames)
	local canvasWidth, canvasHeight = canvas:GetSize()
	local scale = math.min(1, (canvasHeight - 16 - reserve) / math.max(1, top - bottom), (canvasWidth - 24) / math.max(1, right - left))
	scale = math.max(0.3, scale)
	local shiftX, shiftY = (left + right) / 2, (bottom + top) / 2

	for i, preview in ipairs(frames) do
		preview:SetScale(scale)
		preview:ClearAllPoints()
		preview:SetPoint('CENTER', canvas, 'CENTER', offsets[i][1] - shiftX, offsets[i][2] - shiftY + reserve / 2)

		for _, part in ipairs(PARTS) do
			local element = preview[part]
			local settings = UF.Elements:GetConfig(part)
			local optionType = settings and settings.config and settings.config.type
			if element and element:IsShown() and optionType then
				local displayName = settings.config.DisplayName and L[settings.config.DisplayName] or part
				ctx.Region(element, {
					path = { 'UnitFrames', frameName, optionType, part },
					label = displayName,
					onShiftClick = function()
						hidden[frameName] = hidden[frameName] or {}
						hidden[frameName][part] = true
					end,
				})
			end
		end

		for _, auraElement in ipairs(AURA_PARTS) do
			local holder = preview['_sample' .. auraElement]
			if holder and holder:IsShown() then
				local settings = UF.Elements:GetConfig(auraElement)
				local displayName = settings and settings.config and settings.config.DisplayName or auraElement
				ctx.Region(holder, {
					path = { 'UnitFrames', frameName, 'Auras', auraElement },
					label = displayName .. ' - ' .. L['sample icons'],
					onShiftClick = function()
						hidden[frameName] = hidden[frameName] or {}
						hidden[frameName][auraElement] = true
					end,
				})
			end
		end
	end
end

function provider:Hide()
	UF.PreviewFrame:HideStage()
end

function provider:Footer(ctx)
	local frameName = GetFrameName(ctx)
	if not frameName or HiddenCount(frameName) == 0 then
		return nil
	end
	return {
		text = L['Show hidden parts'],
		tooltip = L['Parts you hid from this preview with Shift+click. Your frame settings are not changed.'],
		func = function()
			hidden[frameName] = nil
		end,
	}
end

function provider:Close()
	UF.PreviewFrame:HideAll()
	UF.TestMode:Sync()
end

function provider:Action(ctx)
	local frameName = GetFrameName(ctx)
	if not frameName then
		return nil
	end
	local showing = UF.TestMode:IsFrameForced(frameName)
	return {
		text = L['Preview in place'],
		tooltip = L['Show this frame on your screen with sample data. It hides when you close the options.'],
		active = showing,
		func = function()
			UF.TestMode:Toggle(frameName)
		end,
	}
end

Stage:Register(provider)
