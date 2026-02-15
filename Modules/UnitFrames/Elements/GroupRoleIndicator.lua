local UF = SUI.UF

-- Originally sourced from Blizzard_Deprecated/Deprecated_10_1_5.lua
local function GetTexCoordsForRoleSmallCircle(role)
	if role == 'TANK' then
		return 0, 19 / 64, 22 / 64, 41 / 64
	elseif role == 'HEALER' then
		return 20 / 64, 39 / 64, 1 / 64, 20 / 64
	elseif role == 'DAMAGER' then
		return 20 / 64, 39 / 64, 22 / 64, 41 / 64
	end
end

---@param frame table
local function Build(frame)
	local element = frame.raised:CreateTexture(nil, 'BORDER')
	element:SetTexture('Interface\\AddOns\\SpartanUI\\images\\icon_role.tga')
	element.Sizeable = true
	element:Hide()

	-- Override oUF's Update function to use custom SpartanUI texture instead of atlas
	element.Override = function(self, event)
		local parent = self.GroupRoleIndicator

		if parent.PreUpdate then
			parent:PreUpdate()
		end

		local role = UnitGroupRolesAssigned(self.unit)
		local customTexture = 'Interface\\AddOns\\SpartanUI\\images\\icon_role.tga'

		if role == 'TANK' or role == 'HEALER' or role == 'DAMAGER' then
			parent:SetTexture(customTexture)
			-- Set texture coordinates for the specific role icon
			parent:SetTexCoord(GetTexCoordsForRoleSmallCircle(role))
			parent:Show()
		else
			parent:Hide()
		end

		if parent.PostUpdate then
			return parent:PostUpdate(role)
		end
	end

	-- PostUpdate handles visibility based on user settings
	function element:PostUpdate(role)
		local DB = element.DB
		if DB.ShowTank and role == 'TANK' then
			self:Show()
		elseif DB.ShowHealer and role == 'HEALER' then
			self:Show()
		elseif DB.ShowDPS and role == 'DAMAGER' then
			self:Show()
		else
			self:Hide()
		end
	end

	frame.GroupRoleIndicator = element
end

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	local function OptUpdate(option, val)
		--Update memory
		UF.CurrentSettings[unitName].elements.GroupRoleIndicator[option] = val
		--Update the DB
		UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.GroupRoleIndicator[option] = val
		--Update the screen
		UF.Unit[unitName]:ElementUpdate('GroupRoleIndicator')
	end

	--local DB = UF.CurrentSettings[unitName].elements.Range.enabled
	OptionSet.args.visibility = {
		name = 'Role visibility',
		type = 'group',
		inline = true,
		get = function(info)
			return UF.CurrentSettings[unitName].elements.GroupRoleIndicator[info[#info]]
		end,
		set = function(info, val)
			OptUpdate(info[#info], val)
		end,
		args = {
			ShowTank = {
				name = 'Show tank',
				type = 'toggle',
			},
			ShowHealer = {
				name = 'Show healer',
				type = 'toggle',
			},
			ShowDPS = {
				name = 'Show DPS',
				type = 'toggle',
			},
		},
	}
end

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = true,
	size = 18,
	alpha = 0.75,
	ShowTank = true,
	ShowHealer = true,
	ShowDPS = true,
	position = {
		anchor = 'TOPRIGHT',
		x = 0,
		y = 10,
	},
	config = {
		type = 'Indicator',
		DisplayName = 'Group Role',
	},
}

UF.Elements:Register('GroupRoleIndicator', Build, nil, Options, Settings)
