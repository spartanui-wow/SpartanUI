---@diagnostic disable: missing-parameter
local _, ns = ...
local oUF = ns.oUF or oUF

-- Rare / Elite indicator as an oUF element
-- Supports two display modes:
-- Mode 'minimal': Solid colored overlay (default for most skins)
-- Mode 'dragon': Dragon texture wrapped around portrait (Classic style)
do
	local Update = function(self, event, unit)
		-- Both can be nil on a frame that has not been assigned a unit yet,
		-- which passes the inequality check below, so test for one first.
		if not unit or self.unit ~= unit then
			return
		end
		if not self.RareElite then
			return
		end
		local c = UnitClassification(unit)
		local element = self.RareElite
		local mode = element.mode or 'minimal'

		-- Determine classification
		local isEliteOrBoss = c == 'worldboss' or c == 'elite'
		local isRare = c == 'rare' or c == 'rareelite'

		if not isEliteOrBoss and not isRare then
			element:Hide()
			return
		end

		if mode == 'dragon' then
			-- DRAGON MODE (Classic style)
			-- Shows the dragon texture wrapped around portrait
			element:SetTexture('Interface\\AddOns\\SpartanUI\\Images\\elite_rare')
			-- Only set default texcoord if not already customized by theme callback
			if not element.texCoordSet then
				element:SetTexCoord(0, 1, 0, 1)
			end

			-- Apply texture coord modifiers if set
			if element.short == true then
				element:SetTexCoord(0, 1, 0, 0.7)
			elseif element.small == true then
				element:SetTexCoord(0, 1, 0, 0.4)
			end

			-- Gold for elite, silver for rare
			if isEliteOrBoss then
				element:SetVertexColor(1, 0.9, 0)
			else
				element:SetVertexColor(1, 1, 1)
			end

			element:SetAlpha(element.alpha or 1)
		else
			-- MINIMAL MODE (default)
			-- Shows a solid colored overlay without dragon texture
			element:SetTexture('Interface\\AddOns\\SpartanUI\\images\\textures\\Smoothv2')
			element:SetTexCoord(0, 1, 0, 1)

			-- Gold for elite, silver for rare
			if isEliteOrBoss then
				element:SetVertexColor(1, 0.8, 0)
			else
				element:SetVertexColor(0.8, 0.8, 0.8)
			end

			element:SetAlpha(element.alpha or 0.3)
		end

		element:Show()
	end

	local function ForceUpdate(element)
		return Update(element.__owner, 'ForceUpdate', element.__owner.unit)
	end

	local Enable = function(self)
		if self.RareElite then
			self.RareElite.__owner = self
			self.RareElite.ForceUpdate = ForceUpdate
			self.RareElite:Hide()
			return true
		end
	end

	local Disable = function(self)
		if self.RareElite then
			self.RareElite:Hide()
		end
	end

	oUF:AddElement('RareElite', Update, Enable, Disable)
end
