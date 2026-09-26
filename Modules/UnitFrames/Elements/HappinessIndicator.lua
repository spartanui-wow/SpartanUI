local UF = SUI.UF

-- Forever only ships the namespaced version; older Classic clients have the global.
local GetPetHappiness = (C_PetInfo and C_PetInfo.GetPetHappiness) or _G.GetPetHappiness

---@param frame table
---@param DB table
local function Build(frame, DB)
	if not GetPetHappiness or select(2, UnitClass('player')) ~= 'HUNTER' or frame.unitOnCreate ~= 'pet' then
		return
	end
	local HappinessIndicator = frame:CreateTexture(nil, 'OVERLAY')
	HappinessIndicator.btn = CreateFrame('Frame', nil, frame)
	HappinessIndicator.Sizeable = true
	local function HIOnEnter(self)
		local happiness, damagePercentage, loyaltyRate = GetPetHappiness()
		if not happiness then
			return
		end

		GameTooltip:SetOwner(HappinessIndicator.btn, 'ANCHOR_RIGHT')
		GameTooltip:SetText(_G['PET_HAPPINESS' .. happiness])
		GameTooltip:AddLine(format(PET_DAMAGE_PERCENTAGE, damagePercentage), '', 1, 1, 1)
		local tooltipLoyalty = nil
		if loyaltyRate < 0 then
			tooltipLoyalty = _G['LOSING_LOYALTY']
		elseif loyaltyRate > 0 then
			tooltipLoyalty = _G['GAINING_LOYALTY']
		end
		if tooltipLoyalty then
			GameTooltip:AddLine(tooltipLoyalty, '', 1, 1, 1)
		end
		GameTooltip:Show()
	end
	local function HIOnLeave()
		GameTooltip:Hide()
	end
	HappinessIndicator.btn:SetAllPoints(HappinessIndicator)
	HappinessIndicator.btn:SetScript('OnEnter', HIOnEnter)
	HappinessIndicator.btn:SetScript('OnLeave', HIOnLeave)
	HappinessIndicator:Hide()
	HappinessIndicator.UpdateSUI = CreateFrame('Frame', nil, frame)
	HappinessIndicator.UpdateSUI:RegisterEvent('UNIT_HAPPINESS')
	HappinessIndicator.UpdateSUI:SetScript('OnEvent', function()
		frame:ElementUpdate('HappinessIndicator')
	end)
	HappinessIndicator.UpdateSUI:Hide()
	frame.HappinessIndicator = HappinessIndicator

	-- The mainline oUF names this element Happiness and reads the widget from there;
	-- oUF_Classic uses HappinessIndicator. Register it under both so either one drives it.
	if UF.IsModernOUF then
		frame.Happiness = HappinessIndicator
	end
end

---@param frame table
local function Update(frame)
	local element = frame.HappinessIndicator
	local DB = element and element.DB

	-- SpartanUI toggles elements by its own name, which the mainline oUF does not know.
	-- Skip it during the build: oUF enables every element itself once styling returns,
	-- and its element state for the frame does not exist before then.
	if UF.IsModernOUF and frame.Happiness and DB and frame.IsBuilt then
		if DB.enabled then
			frame:EnableElement('Happiness')
		else
			frame:DisableElement('Happiness')
		end
	end
end

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet) end

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = true,
	position = {
		anchor = 'LEFT',
		x = -10,
		y = -10,
	},
	config = {
		type = 'Indicator',
		DisplayName = 'Happiness',
	},
}

UF.Elements:Register('HappinessIndicator', Build, Update, Options, Settings)
