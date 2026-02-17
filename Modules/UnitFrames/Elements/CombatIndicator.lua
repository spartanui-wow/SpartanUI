local UF = SUI.UF

---@param frame table
---@param DB table
local function Build(frame, DB)
	frame.CombatIndicator = frame.raised:CreateTexture(nil, 'ARTWORK')
	frame.CombatIndicator.Sizeable = true

	-- Glow texture behind the combat icon (twice the size, centered)
	local glow = frame.raised:CreateTexture(nil, 'ARTWORK', nil, -1)
	glow:SetAtlas('UI-HUD-UnitFrame-Player-CombatIcon-Glow')
	glow:SetPoint('CENTER', frame.CombatIndicator, 'CENTER')
	glow:SetSize(32, 32)
	glow:Hide()
	frame.CombatIndicator.glow = glow

	function frame.CombatIndicator:PostUpdate(inCombat)
		if DB and self.DB.enabled and inCombat then
			self:Show()
			if self.DB.glow ~= false then
				self.glow:SetSize(self:GetWidth() * 2, self:GetHeight() * 2)
				self.glow:Show()
			else
				self.glow:Hide()
			end
		else
			self:Hide()
			self.glow:Hide()
		end
	end
end

---@type SUI.UF.Elements.Settings
local Settings = {
	config = {
		type = 'Indicator',
		DisplayName = 'Combat',
	},
}

UF.Elements:Register('CombatIndicator', Build, nil, nil, Settings)
