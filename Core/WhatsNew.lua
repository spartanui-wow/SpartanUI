local SUI = SUI
local module = SUI:NewModule('Handler.WhatsNew') ---@type SUI.Module
-- DB or DBG - This allows us to change if the whats new should appear on every profile or once.
local db = 'DB'

function SUI:WhatsNew()
	local UI = LibAT.UI
	module.window = UI.CreateWindow({
		name = 'SUI_WhatsNew',
		title = "What's New",
		width = 650,
		height = 500,
		hidePortrait = true,
	})
	module.window:SetPoint('CENTER', 0, 0)
	module.window:SetFrameStrata('DIALOG')

	-- Custom logo
	local logo = module.window:CreateTexture(nil, 'ARTWORK')
	logo:SetTexture('Interface\\AddOns\\SpartanUI\\images\\setup\\SUISetup')
	logo:SetSize(256, 64)
	logo:SetPoint('TOP', module.window.Body, 'TOP', 0, 0)
	logo:SetAlpha(0.8)

	-- Setup the Top text fields
	local subtitle = UI.CreateLabel(module.window, "What's new", 'GameFontNormalLarge')
	subtitle:SetTextColor(0.29, 0.18, 0.96, 1)
	subtitle:SetJustifyH('CENTER')
	subtitle:SetPoint('TOP', logo, 'BOTTOM', 0, -10)
	subtitle:SetWidth(650)

	local desc1 = UI.CreateLabel(module.window, '', 'GameFontHighlight')
	desc1:SetPoint('TOP', subtitle, 'BOTTOM', 0, -5)
	desc1:SetTextColor(1, 1, 1, 0.8)
	desc1:SetWidth(610)
	desc1:SetJustifyH('CENTER')

	local desc2 = UI.CreateLabel(module.window, '', 'GameFontHighlight')
	desc2:SetPoint('TOP', desc1, 'BOTTOM', 0, -3)
	desc2:SetTextColor(1, 1, 1, 0.8)
	desc2:SetWidth(610)
	desc2:SetJustifyH('CENTER')

	-- Action buttons
	UI.CreateActionButtons(module.window, {
		{
			text = 'SKIP',
			width = 150,
			onClick = function()
				module.window:Hide()
			end,
		},
		{
			text = 'CONTINUE',
			width = 150,
			onClick = function()
				module.window:Hide()
			end,
		},
	})

	-- Store references for external updates
	module.window.SubTitle = subtitle
	module.window.Desc1 = desc1
	module.window.Desc2 = desc2

	-- Display first page
	module.window.closeBtn:Hide()
	module.window:Hide()
end

function module:OnInitialize() end
