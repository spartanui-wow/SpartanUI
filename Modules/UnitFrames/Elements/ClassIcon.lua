local UF = SUI.UF
local L = SUI.L

---@param frame table
---@param DB table
local function Build(frame, DB)
	frame.ClassIcon = frame.raised:CreateTexture(nil, 'BORDER')
	frame.ClassIcon.Sizeable = true
	frame.ClassIcon.shadow = frame.raised:CreateTexture(nil, 'BACKGROUND')
	frame.ClassIcon.shadow:SetPoint('TOPLEFT', frame.ClassIcon, 'TOPLEFT', 2, -2)
	frame.ClassIcon.shadow:SetPoint('BOTTOMRIGHT', frame.ClassIcon, 'BOTTOMRIGHT', 2, -2)
	frame.ClassIcon.shadow:SetVertexColor(0, 0, 0, 0.9)

	function frame.ClassIcon:PostUpdate()
		if self.DB and self.DB.enabled then
			self:Show()
			self.shadow:Show()
		else
			self:Hide()
			self.shadow:Hide()
		end
	end
end

---@param frame table
---@param settings? table
local function Update(frame, settings)
	local element = frame.ClassIcon
	local DB = settings or element.DB
	local reaction = UnitReaction(frame.unit, 'player')
	if not reaction then
		return
	end

	if
		(
			(reaction <= 2 and DB.VisibleOn == 'hostile')
			or (reaction >= 3 and DB.VisibleOn == 'friendly')
			or (UnitPlayerControlled(frame.unit) and DB.VisibleOn == 'PlayerControlled')
			or DB.VisibleOn == 'all'
		) and DB.enabled
	then
		element:Show()
		element.shadow:Show()
		element:SetSize(DB.size, DB.size)
		element:SetPoint(DB.position.anchor, frame, DB.position.anchor, DB.position.x, DB.position.y)
	else
		element:Hide()
		element.shadow:Hide()
	end
end

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	local ElementSettings = UF.CurrentSettings[unitName].elements.ClassIcon
	local function OptUpdate(option, val)
		UF.CurrentSettings[unitName].elements.ClassIcon[option] = val
		UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.ClassIcon[option] = val
		UF.Unit[unitName]:ElementUpdate('ClassIcon')
	end

	OptionSet.args.VisibleOn = {
		name = L['Visibility'],
		desc = L['Set when the class icon should be visible'],
		type = 'select',
		order = 1,
		values = {
			all = L['Always'],
			hostile = L['Hostile Units'],
			friendly = L['Friendly Units'],
			PlayerControlled = L['Player Controlled Units'],
		},
		get = function()
			return ElementSettings.VisibleOn
		end,
		set = function(_, val)
			OptUpdate('VisibleOn', val)
		end,
	}

	OptionSet.args.shadow = {
		name = L['Show Shadow'],
		desc = L['Toggle the visibility of the icon shadow'],
		type = 'toggle',
		order = 3,
		get = function()
			return ElementSettings.shadow
		end,
		set = function(_, val)
			OptUpdate('shadow', val)
		end,
	}
end

---@type SUI.UF.Elements.Settings
local Settings = {
	VisibleOn = 'PlayerControlled',
	size = 20,
	position = {
		anchor = 'BOTTOMLEFT',
		x = -12,
		y = 0,
	},
	config = {
		type = 'Indicator',
		DisplayName = 'Class Icon',
	},
}

UF.Elements:Register('ClassIcon', Build, Update, Options, Settings)

do -- ClassIcon as an SUIUF module
	local function Update(self, event, unit)
		local icon = self.ClassIcon
		if icon then
			local _, class = UnitClass(self.unit)
			if not class then
				return
			end

			local path = 'Interface\\AddOns\\SpartanUI\\images\\flat_classicons\\' .. (string.lower(class)) .. '.blp'

			if class then
				-- local coords = ClassIconCoord[class or 'DEFAULT']
				-- icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
				icon:SetTexture(path)
				icon:Show()
				if icon.shadow then
					icon.shadow:SetTexture(path)
					icon.shadow:Show()
				end
			else
				icon:Hide()
				icon.shadow:Hide()
			end
			if icon.PostUpdate then
				return icon:PostUpdate()
			end
		end
	end

	local function ForceUpdate(element)
		return Update(element.__owner, 'ForceUpdate', element.__owner.unit)
	end

	local function Enable(self)
		local icon = self.ClassIcon
		if icon then
			icon.__owner = self
			icon.ForceUpdate = ForceUpdate
			self:RegisterEvent('PLAYER_TARGET_CHANGED', Update, true)
			self:RegisterEvent('UNIT_PET', Update, true)
			if icon.shadow == nil then
				icon.shadow = self:CreateTexture(nil, 'BACKGROUND')
				icon.shadow:SetSize(icon:GetSize())
				icon.shadow:SetPoint('CENTER', icon, 'CENTER', 2, -2)
				icon.shadow:SetVertexColor(0, 0, 0, 0.9)
			end
			return true
		end
	end

	local function Disable(self)
		local icon = self.ClassIcon
		if icon then
			self:UnregisterEvent('PLAYER_TARGET_CHANGED', Update)
			self:UnregisterEvent('UNIT_PET', Update)
			self.ClassIcon:Hide()
			self.ClassIcon.shadow:Hide()
		end
	end

	SUIUF:AddElement('ClassIcon', Update, Enable, Disable)
end
