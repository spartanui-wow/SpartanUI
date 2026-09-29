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
local PARTS = { 'FrameBackground', 'Health', 'Power', 'Castbar', 'Name' }
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
	return math.max(80, math.min(180, height * 1.4 + 24))
end

function provider:Render(ctx)
	local frameName = GetFrameName(ctx)
	if not frameName then
		self:Hide()
		return
	end
	local canvas = ctx.canvas
	local frames = UF.PreviewFrame:RenderStage(frameName, canvas)
	local canvasWidth, canvasHeight = canvas:GetSize()
	local frameWidth = UF.CurrentSettings[frameName].width or 180
	local frameHeight = UF:CalculateHeight(frameName) or 40
	local totalWidth = #frames * frameWidth + (#frames - 1) * GAP
	local scale = math.min(1.5, (canvasHeight - 20) / frameHeight, (canvasWidth - 24) / totalWidth)
	scale = math.max(0.3, scale)
	-- SetPoint offsets are in the preview frame's own (scaled) units
	local startX = (canvasWidth / scale - totalWidth) / 2

	for i, preview in ipairs(frames) do
		preview:SetScale(scale)
		preview:ClearAllPoints()
		preview:SetPoint('LEFT', canvas, 'LEFT', startX + (i - 1) * (frameWidth + GAP), 0)

		for _, part in ipairs(PARTS) do
			local element = preview[part]
			local settings = UF.Elements:GetConfig(part)
			local optionType = settings and settings.config and settings.config.type
			if element and element:IsShown() and optionType then
				local displayName = settings.config.DisplayName and L[settings.config.DisplayName] or part
				ctx.Region(element, { path = { 'UnitFrames', frameName, optionType, part }, label = displayName })
			end
		end
	end
end

function provider:Hide()
	UF.PreviewFrame:HideStage()
end

Stage:Register(provider)
