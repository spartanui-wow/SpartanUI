---@diagnostic disable: missing-parameter
local _, ns = ...
local oUF = ns.oUF or oUF

-- TargetIndicator as an oUF element
-- Displays visual indicator when unit is targeted
do
	local Update = function(self, event, unit)
		local element = self.TargetIndicator
		if not element then
			return
		end

		-- Get settings if available
		local DB = element.DB
		local enabled = not DB or DB.enabled

		-- Check states
		local isTarget = UnitIsUnit(self.unit or unit, 'target') and (not DB or DB.ShowTarget)
		local isFocus = UnitIsUnit(self.unit or unit, 'focus') and (not DB or DB.ShowFocus)
		local isMouseover = (self == GetMouseFocus() or (self.unit and UnitIsUnit(self.unit, 'mouseover'))) and (not DB or DB.ShowMouseover)

		-- Priority: target > focus > mouseover
		local shouldShow = (isTarget or isFocus or isMouseover) and enabled

		-- For nameplates, also check nameplate-specific logic
		if self:GetName() and self:GetName():match('NamePlates') then
			if UnitExists('target') and C_NamePlate.GetNamePlateForUnit('target') then
				-- Check if SpartanUI Nameplates module exists and has ShowTarget enabled
				local Nameplates = SUI and SUI.GetModule and SUI:GetModule('Nameplates')
				if Nameplates and Nameplates.DB and Nameplates.DB.ShowTarget then
					if self:GetName() ~= 'oUF_Spartan_NamePlates' .. C_NamePlate.GetNamePlateForUnit('target'):GetName() then
						isTarget = false
					end
				else
					isTarget = false
				end
			else
				isTarget = false
			end
		end

		-- Handle old structure (bg1/bg2) for backward compatibility
		if element.bg1 then
			if shouldShow then
				element.bg1:Show()
				element.bg2:Show()
			else
				element.bg1:Hide()
				element.bg2:Hide()
			end
			return
		end

		-- Handle new structure based on mode
		local mode = DB and DB.mode or 'texture'

		-- Determine color based on state priority
		local color = nil
		if isTarget and DB and DB.targetColor then
			color = DB.targetColor
		elseif isFocus and DB and DB.focusColor then
			color = DB.focusColor
		elseif isMouseover and DB and DB.mouseoverColor then
			color = DB.mouseoverColor
		end

		if mode == 'texture' or mode == 'both' then
			if element.textureObjects then
				for _, tex in pairs(element.textureObjects) do
					if shouldShow then
						if color then
							tex:SetVertexColor(unpack(color))
						end
						tex:Show()
					else
						tex:Hide()
					end
				end
			end
		end

		if mode == 'border' or mode == 'both' then
			if element.borderInstanceId and SUI and SUI.Handlers and SUI.Handlers.BackgroundBorder then
				if shouldShow and color then
					-- Update border color if available
					SUI.Handlers.BackgroundBorder:SetVisible(element.borderInstanceId, true)
					-- Note: Border color update would need BackgroundBorder API extension
				else
					SUI.Handlers.BackgroundBorder:SetVisible(element.borderInstanceId, shouldShow)
				end
			end
		end
	end

	local function ForceUpdate(element)
		return Update(element.__owner, 'ForceUpdate', element.__owner.unit)
	end

	local Enable = function(self)
		local element = self.TargetIndicator
		if element then
			element.__owner = self
			element.ForceUpdate = ForceUpdate
			self:RegisterEvent('PLAYER_TARGET_CHANGED', Update, true)
			self:RegisterEvent('PLAYER_FOCUS_CHANGED', Update, true)
			self:RegisterEvent('UPDATE_MOUSEOVER_UNIT', Update, true)

			-- Register mouseover script events
			if not element.mouseoverHooked then
				self:HookScript('OnEnter', function()
					Update(self, 'OnEnter')
				end)
				self:HookScript('OnLeave', function()
					Update(self, 'OnLeave')
				end)
				element.mouseoverHooked = true
			end

			return true
		end
	end

	local Disable = function(self)
		local icon = self.TargetIndicator
		if icon then
			self:UnregisterEvent('PLAYER_TARGET_CHANGED', Update)
			self:UnregisterEvent('PLAYER_FOCUS_CHANGED', Update)
			self:UnregisterEvent('UPDATE_MOUSEOVER_UNIT', Update)
			icon:Hide()
		end
	end

	oUF:AddElement('TargetIndicator', Update, Enable, Disable)
end
