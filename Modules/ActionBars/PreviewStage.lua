---@type SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.ActionBars
local module = SUI:GetModule('ActionBars')
local Style = SUI.UI.Style

-- Action bar preview for the options window. Runs the real Bar:LayoutButtons on a stand-in
-- bar made of plain buttons, so the grid, size, spacing and growth match the live bar,
-- while nothing secure is touched.

local Stage = SUI.OptionsWindow and SUI.OptionsWindow.Stage
if not Stage or not module.BarPrototype then
	return
end

local MAX_BUTTONS = 12
local preview ---@type table|nil

---@param ctx SUI.OptionsWindow.StageContext
---@return table|nil bar, string|nil optionKey
local function GetBar(ctx)
	local optionKey = ctx.path[2]
	local id = optionKey and optionKey:match('^bar(%d+)$')
	local bar = id and module.bars['BT4Bar' .. id]
	if not bar or not bar.GetDB then
		return nil
	end
	local db = bar:GetDB()
	if not db or not db.enabled then
		return nil
	end
	return bar, optionKey
end

local function CreatePreviewBar(canvas)
	local frame = CreateFrame('Frame', nil, canvas)
	Mixin(frame, module.BarPrototype)
	frame.buttons = {}
	frame.cropIcons = true
	frame.key = 'SUI_ActionBarPreview'
	for i = 1, MAX_BUTTONS do
		local button = CreateFrame('Button', nil, frame)
		button:SetSize(36, 36)
		button.icon = button:CreateTexture(nil, 'ARTWORK')
		button.icon:SetAllPoints()
		button.border = Style:CreateBorder(button)
		button.border:SetColor(0, 0, 0, 1)
		button.hotkey = Style:CreateText(button, 10)
		button.hotkey:SetPoint('TOPRIGHT', -2, -2)
		frame.buttons[i] = button
	end
	return frame
end

---@type SUI.OptionsWindow.StageProvider
local provider = { path = { 'ActionBars' } }

function provider:GetHeight(ctx)
	local bar = GetBar(ctx)
	if not bar then
		return 0
	end
	local db = bar:GetDB()
	local _, height = module:CalculateBarSize(db, math.min(MAX_BUTTONS, db.buttons or MAX_BUTTONS))
	return math.max(70, math.min(140, height + 30))
end

function provider:Render(ctx)
	local bar, optionKey = GetBar(ctx)
	if not bar then
		self:Hide()
		return
	end
	preview = preview or CreatePreviewBar(ctx.canvas)
	preview:SetParent(ctx.canvas)
	preview:SetFrameLevel(ctx.canvas:GetFrameLevel() + 5)
	preview.GetDB = function()
		return bar:GetDB()
	end

	-- Show the player's real icons and key labels where the live bar has them
	for i, button in ipairs(preview.buttons) do
		local real = bar.buttons and bar.buttons[i]
		local texture = real and real.icon and real.icon.GetTexture and real.icon:GetTexture()
		button.icon:SetTexture(texture or 134400)
		local hotkey = real and real.HotKey and real.HotKey.GetText and real.HotKey:GetText()
		button.hotkey:SetText(hotkey or '')
	end

	local db = bar:GetDB()
	local count = math.min(MAX_BUTTONS, db.buttons or MAX_BUTTONS)
	preview:LayoutButtons(count)
	for i = 1, count do
		preview.buttons[i]:EnableMouse(false)
	end

	local width, height = module:CalculateBarSize(db, count)
	local canvasWidth, canvasHeight = ctx.canvas:GetSize()
	local scale = math.max(0.3, math.min(1.2, (canvasHeight - 16) / height, (canvasWidth - 24) / width))
	preview:SetScale(scale)
	preview:ClearAllPoints()
	preview:SetPoint('CENTER', ctx.canvas, 'CENTER', 0, 0)
	preview:SetFrameStrata(ctx.canvas:GetFrameStrata())
	preview:Show()

	ctx.Region(preview, { path = { 'ActionBars', optionKey }, label = bar.displayName or optionKey })
end

function provider:Hide()
	if preview then
		preview:Hide()
	end
end

Stage:Register(provider)
