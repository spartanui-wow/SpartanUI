local SUI, L, Lib = SUI, SUI.L, SUI.Lib
---@class SUI.Handler.Profiles : SUI.Module
local module = SUI:NewModule('Handler.Profiles')
----------------------------------------------------------------------------------------------------

-- SpartanUI addon ID for LibAT ProfileManager
local SPARTANUI_ADDON_ID = 'spartanui'

-- Namespace blacklist
local namespaceblacklist = { 'LibDualSpec-1.0' }

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
	if LibAT and LibAT.ProfileManager then
		LibAT.ProfileManager:ShowImport(SPARTANUI_ADDON_ID)
	else
		SUI:Error('LibAT ProfileManager not available')
	end
end

---Open the LibAT ProfileManager in export mode for SpartanUI
function module:ExportUI()
	if LibAT and LibAT.ProfileManager then
		LibAT.ProfileManager:ShowExport(SPARTANUI_ADDON_ID)
	else
		SUI:Error('LibAT ProfileManager not available')
	end
end

function module:OnEnable()
	-- Register SpartanUI with LibAT ProfileManager
	if LibAT and LibAT.ProfileManager then
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
	else
		SUI:Error('LibAT ProfileManager not available - profile import/export disabled')
	end

	-- Register export blacklist patterns
	-- Paths are relative to namespace root: Namespace.profiles.ProfileName.key
	if LibAT and LibAT.ProfileManager then
		LibAT.ProfileManager:RegisterExportBlacklist({
			'Chatbox.profiles.*.chatLog.history', -- Chat log history (any profile)
			'StopTalking.profiles.*.history', -- Voice line history (any profile)
			'StopTalking.profiles.*.whitelist', -- Whitelisted voice lines (any profile)
		})
	end

	-- Register chat commands
	SUI:AddChatCommand('export', module.ExportUI, 'Export your settings')
	SUI:AddChatCommand('import', module.ImportUI, 'Import settings')
end
