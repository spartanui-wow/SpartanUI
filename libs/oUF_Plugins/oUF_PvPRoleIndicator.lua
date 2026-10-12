--[[
# Element: PVP Role Indicator

Handles the visibility and updating of an indicator based on the unit's raid assignment (main tank or main assist).

## Widget

PvPRoleIndicator - A `Texture` representing the unit's raid assignment.

## Notes

This element updates by changing the texture.

## Examples

    -- Position and size
    local PvPRoleIndicator = self:CreateTexture(nil, 'OVERLAY')
    PvPRoleIndicator:SetSize(16, 16)
    PvPRoleIndicator:SetPoint('TOPLEFT')

    -- Register it with oUF
    self.PvPRoleIndicator = PvPRoleIndicator
--]]

local _, ns = ...
local oUF = ns.oUF

-- Clients without secret values can read everything
local canaccessvalue = canaccessvalue or function()
	return true
end
local canaccesstable = canaccesstable or function()
	return true
end

local DEFAULT_TEXTURE = [[Interface\LFGFrame\UI-LFG-ICON-ROLES]]

local function Update(self, event)
	local element = self.PvPRoleIndicator

	--[[ Callback: PvPRoleIndicator:PreUpdate()
	Called before the element has been updated.

	* self - the PvPRoleIndicator element
	--]]
	if element.PreUpdate then element:PreUpdate() end

	-- Safety check: Ensure we have required API and data
	if not C_PvP or not C_PvP.GetScoreInfoByPlayerGuid then
		element:Hide()
		return
	end

	-- Need a readable unit GUID. It can be hidden on restricted maps, and the score lookup
	-- will not take a hidden one from addon code.
	local guid = self.unitGUID
	if not guid or not canaccessvalue(guid) or guid == '' then
		element:Hide()
		return
	end

	-- The score can be hidden during an active PvP match
	local info = C_PvP.GetScoreInfoByPlayerGuid(guid)
	if not info or not canaccessvalue(info) or not canaccesstable(info) then
		element:Hide()
		return
	end
	local role = info.roleAssigned
	if not role or not canaccessvalue(role) then
		element:Hide()
		return
	end
	if role == 2 and element.showTank then
		element:SetAtlas('UI-LFG-RoleIcon-Tank')
		element:Show()
	elseif role == 4 then
		element:SetAtlas('UI-LFG-RoleIcon-Healer')
		element:Show()
	else
		element:Hide()
	end
	-- element:Show()
	--[[ Callback: PvPRoleIndicator:PostUpdate(role)
	Called after the element has been updated.

	* self - the PvPRoleIndicator element
	* role - the unit's raid assignment (string?)['MAINTANK', 'MAINASSIST']
	--]]
	if element.PostUpdate then return element:PostUpdate() end
end

local function Path(self, ...)
	--[[ Override: PvPRoleIndicator.Override(self, event, ...)
	Used to completely override the internal update function.

	* self  - the parent object
	* event - the event triggering the update (string)
	* ...   - the arguments accompanying the event
	--]]
	return (self.PvPRoleIndicator.Override or Update)(self, ...)
end

local function ForceUpdate(element)
	return Path(element.__owner, 'ForceUpdate')
end

local function Enable(self)
	local element = self.PvPRoleIndicator
	if element then
		--Check for HHTD
		local HHTD, _ = C_AddOns.IsAddOnLoaded('HHTD')
		if not HHTD then
			element.__owner = self
			element.ForceUpdate = ForceUpdate

			self:RegisterEvent('GROUP_ROSTER_UPDATE', Path, true)
			self:RegisterEvent('UPDATE_BATTLEFIELD_SCORE', Path, true)

			return true
		end
	end
end

local function Disable(self)
	local element = self.PvPRoleIndicator
	if element then
		element:Hide()

		self:UnregisterEvent('GROUP_ROSTER_UPDATE', Path)
		self:UnregisterEvent('UPDATE_BATTLEFIELD_SCORE', Path)
	end
end

oUF:AddElement('PvPRoleIndicator', Path, Enable, Disable)
