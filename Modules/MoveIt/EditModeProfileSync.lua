---@class SUI
local SUI = SUI
---@class MoveIt
local MoveIt = SUI.MoveIt

---@class SUI.MoveIt.EditModeProfileSync
local EditModeProfileSync = {}
MoveIt.EditModeProfileSync = EditModeProfileSync

---Initialize EditMode profile sync feature (optional)
---Only active if MoveIt.DB.SyncEditModeProfile is enabled
function EditModeProfileSync:Initialize()
	-- Check if sync is enabled
	if not MoveIt.DB or not MoveIt.DB.SyncEditModeProfile then
		if MoveIt.logger then
			MoveIt.logger.debug('EditMode profile sync disabled (user setting)')
		end
		return
	end

	-- Check if we're on Retail (EditMode only exists in Retail)
	if not EditModeManagerFrame then
		if MoveIt.logger then
			MoveIt.logger.info('EditMode not available (Classic/TBC/Wrath) - profile sync unavailable')
		end
		return
	end

	-- Check if LibEditModeOverride is available
	local LibEMO = LibStub and LibStub('LibEditModeOverride-1.0', true)
	if not LibEMO then
		if MoveIt.logger then
			MoveIt.logger.warning('LibEditModeOverride not found - EditMode profile sync unavailable')
		end
		return
	end

	self.LibEMO = LibEMO

	if MoveIt.logger then
		MoveIt.logger.info('EditMode profile sync enabled')
	end
end

---Get character key for global DB tracking
---@return string charKey Character-realm key
local function GetCharacterKey()
	local name = UnitName('player')
	local realm = GetRealmName()
	return name .. '-' .. realm
end

---Get the current EditMode profile name for this character
---@return string|nil profileName The EditMode profile name, or nil if not set
function EditModeProfileSync:GetCurrentProfile()
	if not MoveIt.DBG or not MoveIt.DBG.CurrentProfiles then
		return nil
	end
	return MoveIt.DBG.CurrentProfiles[GetCharacterKey()]
end

---Set the current EditMode profile name for this character
---@param profileName string The EditMode profile name to track
function EditModeProfileSync:SetProfileForCharacter(profileName)
	if not MoveIt.DBG then
		return
	end
	if not MoveIt.DBG.CurrentProfiles then
		MoveIt.DBG.CurrentProfiles = {}
	end
	MoveIt.DBG.CurrentProfiles[GetCharacterKey()] = profileName

	if MoveIt.logger then
		MoveIt.logger.debug(('Tracking EditMode profile "%s" for this character'):format(profileName or 'nil'))
	end
end

---Switch to a specific EditMode profile by name
---@param profileName string The EditMode profile name to switch to
---@return boolean success True if profile switch was successful
function EditModeProfileSync:SwitchToProfile(profileName)
	if not self.LibEMO then
		if MoveIt.logger then
			MoveIt.logger.error('SwitchToProfile: LibEMO not available')
		end
		return false
	end

	if not profileName or profileName == '' then
		if MoveIt.logger then
			MoveIt.logger.error('SwitchToProfile: Invalid profile name')
		end
		return false
	end

	-- Load layouts if needed
	if not self.LibEMO:AreLayoutsLoaded() then
		self.LibEMO:LoadLayouts()
	end

	-- Check if the profile exists
	if not self.LibEMO:DoesLayoutExist(profileName) then
		if MoveIt.logger then
			MoveIt.logger.warning(('SwitchToProfile: Profile "%s" does not exist'):format(profileName))
		end
		return false
	end

	-- Switch to the profile
	if MoveIt.logger then
		MoveIt.logger.info(('Switching to EditMode profile "%s"'):format(profileName))
	end

	local success = pcall(function()
		self.LibEMO:SetActiveLayout(profileName)
	end)

	if not success then
		if MoveIt.logger then
			MoveIt.logger.error(('Failed to switch to EditMode profile "%s"'):format(profileName))
		end
		return false
	end

	-- Track the profile change
	self:SetProfileForCharacter(profileName)

	return true
end

---Handle SUI profile change event
---Automatically switches EditMode profile if sync is enabled
---@param event string Event name
---@param database table Database reference
---@param newProfile string The new SUI profile name
function EditModeProfileSync:OnSUIProfileChanged(event, database, newProfile)
	-- Check if sync is enabled
	if not MoveIt.DB or not MoveIt.DB.SyncEditModeProfile then
		return
	end

	if not self.LibEMO then
		return
	end

	if MoveIt.logger then
		MoveIt.logger.info(('SUI profile changed to "%s" - syncing EditMode profile'):format(newProfile))
	end

	-- Get the target EditMode profile name for this SUI profile
	-- By default, try to use a profile with the same name
	local targetProfile = self:GetCurrentProfile() or newProfile

	-- Switch to the profile if it exists
	if self.LibEMO:DoesLayoutExist(targetProfile) then
		self:SwitchToProfile(targetProfile)
	else
		if MoveIt.logger then
			MoveIt.logger.warning(('EditMode profile "%s" does not exist - sync skipped'):format(targetProfile))
		end
	end
end

---Get list of available EditMode profiles
---@return table profiles List of { name = string, type = number } tables
function EditModeProfileSync:GetAvailableProfiles()
	if not self.LibEMO then
		return {}
	end

	if not self.LibEMO:AreLayoutsLoaded() then
		self.LibEMO:LoadLayouts()
	end

	local profiles = {}
	local layouts = self.LibEMO:GetLayouts()

	if layouts then
		for _, layout in pairs(layouts) do
			if layout.layoutName then
				table.insert(profiles, {
					name = layout.layoutName,
					type = layout.layoutType or 0,
				})
			end
		end
	end

	-- Sort by name
	table.sort(profiles, function(a, b)
		return a.name < b.name
	end)

	return profiles
end
