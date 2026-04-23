local SUI, L, Lib = SUI, SUI.L, SUI.Lib
---@class SUI.Handler.Profiles : SUI.Module
local module = SUI:NewModule('Handler.Profiles')
----------------------------------------------------------------------------------------------------

-- SpartanUI addon ID for LibAT ProfileManager
local SPARTANUI_ADDON_ID = 'spartanui'

-- Namespace blacklist
local namespaceblacklist = { 'LibDualSpec-1.0' }

-- Required LibAT ProfileManager API surface. If any of these are missing,
-- the installed Libs-AddonTools is out of date and must be updated.
local REQUIRED_PROFILE_MANAGER_API = {
	'RegisterAddon',
	'RegisterComposite',
	'RegisterExportBlacklist',
	'ShowImport',
	'ShowExport',
}

---Check that LibAT ProfileManager is loaded and exposes the expected API.
---@return boolean compatible True if the installed ProfileManager matches the expected API
---@return string? reason Reason the API is unavailable (missing or outdated)
local function IsProfileManagerCompatible()
	if not (LibAT and LibAT.ProfileManager) then
		return false, 'missing'
	end
	for _, method in ipairs(REQUIRED_PROFILE_MANAGER_API) do
		if type(LibAT.ProfileManager[method]) ~= 'function' then
			return false, 'outdated'
		end
	end
	return true
end

---Show the appropriate error for an unavailable ProfileManager.
---@param reason string 'missing' or 'outdated'
local function ReportUnavailable(reason)
	if reason == 'outdated' then
		SUI:Error('Libs-AddonTools is out of date. Please update it to use profile import/export.')
	else
		SUI:Error('LibAT ProfileManager not available - profile import/export disabled')
	end
end

---Get list of all SpartanUI module namespaces for registration
---@return string[] namespaces List of namespace names
local function GetNamespaceList()
	local namespaces = {}

	if SpartanUIDB and SpartanUIDB.namespaces then
		for namespaceName, _ in pairs(SpartanUIDB.namespaces) do
			if not SUI:IsInTable(namespaceblacklist, namespaceName) then
				table.insert(namespaces, namespaceName)
			end
		end
	end

	-- Sort alphabetically for consistent display
	table.sort(namespaces)

	return namespaces
end

---Open the LibAT ProfileManager in import mode for SpartanUI
function module:ImportUI()
	local ok, reason = IsProfileManagerCompatible()
	if ok then
		LibAT.ProfileManager:ShowImport(SPARTANUI_ADDON_ID)
	else
		ReportUnavailable(reason)
	end
end

---Open the LibAT ProfileManager in export mode for SpartanUI
function module:ExportUI()
	local ok, reason = IsProfileManagerCompatible()
	if ok then
		LibAT.ProfileManager:ShowExport(SPARTANUI_ADDON_ID)
	else
		ReportUnavailable(reason)
	end
end

function module:OnEnable()
	local ok, reason = IsProfileManagerCompatible()
	if not ok then
		ReportUnavailable(reason)
		return
	end

	-- Register SpartanUI with LibAT ProfileManager
	local namespaces = GetNamespaceList()

	LibAT.ProfileManager:RegisterAddon({
		id = SPARTANUI_ADDON_ID,
		name = 'SpartanUI',
		db = SUI.SpartanUIDB,
		namespaces = namespaces,
		icon = 'Interface\\AddOns\\SpartanUI\\images\\Spartan-Helm',
	})

	-- Register composite bundle (full profile with action bars and UI positions)
	LibAT.ProfileManager:RegisterComposite({
		id = 'spartanui_full',
		displayName = 'SpartanUI (Full Profile)',
		description = 'Complete SUI setup including action bars and UI positions',
		primaryAddonId = SPARTANUI_ADDON_ID,

		-- Simple string IDs - ProfileManager's BuiltInSystems knows the rest
		components = {
			'bartender4', -- Built-in: knows addonId, displayName, availability
			'editmode', -- Built-in: knows it's Retail-only, has export/import logic
		},
	})

	-- Register export blacklist patterns
	-- Paths are relative to namespace root: Namespace.profiles.ProfileName.key
	LibAT.ProfileManager:RegisterExportBlacklist({
		'StopTalking.$global.history',
		'PreyTracker.$global',
	})

	-- Register chat commands
	SUI:AddChatCommand('export', module.ExportUI, 'Export your settings')
	SUI:AddChatCommand('import', module.ImportUI, 'Import settings')
end
