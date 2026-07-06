---@diagnostic disable: missing-parameter
local _, ns = ...
local oUF = ns.oUF or oUF

-- SUI_RaidGroup as an oUF element
-- Displays the raid subgroup number for the unit
do
	local Update = function(self, event, unit)
		local element = self.SUI_RaidGroup
		if not element then
			return
		end

		local raidIndex = IsInRaid() and UnitInRaid(self.unit)
		if raidIndex then
			local _, _, subgroup = GetRaidRosterInfo(raidIndex)
			element.Text:SetText(subgroup)
			element:Show()
			element.Text:Show()
		else
			element.Text:SetText('')
			element:Hide()
			element.Text:Hide()
		end
	end

	local Enable = function(self)
		if self.SUI_RaidGroup then
			self:RegisterEvent('GROUP_ROSTER_UPDATE', Update, true)
			return true
		end
	end

	local Disable = function(self)
		if self.SUI_RaidGroup then
			self:UnregisterEvent('GROUP_ROSTER_UPDATE', Update)
			self.SUI_RaidGroup:Hide()
			self.SUI_RaidGroup.Text:Hide()
		end
	end

	oUF:AddElement('SUI_RaidGroup', Update, Enable, Disable)
end
