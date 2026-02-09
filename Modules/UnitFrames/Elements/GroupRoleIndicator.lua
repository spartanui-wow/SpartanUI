local UF = SUI.UF

---@param frame table
local function Build(frame)
	frame.GroupRoleIndicator = frame.raised:CreateTexture(nil, 'BORDER')
	frame.GroupRoleIndicator:SetTexture('Interface\\AddOns\\SpartanUI\\images\\icon_role.tga')
	frame.GroupRoleIndicator.Sizeable = true
	frame.GroupRoleIndicator:Hide()
	function frame.GroupRoleIndicator:PostUpdate(role)
		local DB = frame.GroupRoleIndicator.DB
		if DB.ShowTank and role == 'TANK' then
			self:Show()
		elseif DB.ShowHealer and role == 'HEALER' then
			self:Show()
		elseif DB.ShowDPS and role == 'DAMAGER' then
			self:Show()
		else
			-- if DB.ShowDPS and role == '' then
			self:Hide()
		end
	end
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
