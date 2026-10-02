---@class SUI
local SUI = SUI
local L = SUI.L
local module = SUI:NewModule('Handler.Modules') ---@type SUI.Module

---@param ModuleTable AceAddon
---@return string
function SUI:GetModuleName(ModuleTable)
	local name

	-- Remove SpartanUI_
	name = string.gsub(ModuleTable.name, 'SpartanUI_', '')

	return name
end

---@param moduleName AceAddon|string
---@return boolean
function SUI:IsModuleEnabled(moduleName)
	-- If we are passed a table, we need to get the name from it.
	if type(moduleName) == 'table' then
		if moduleName.Override or moduleName.override then
			return false
		end

		moduleName = SUI:GetModuleName(moduleName)
	else
		-- Fetch the Module
		local moduleObj = SUI:GetModule(moduleName, true)
		if not moduleObj then
			return false
		end
		-- See if the modules has been overridden
		if moduleObj and (moduleObj.Override or moduleObj.override) then
			return false
		end
	end

	if SUI.DB.DisabledModules and SUI.DB.DisabledModules[moduleName] then
		return false
	end

	return true
end

---@param moduleName AceAddon|string
---@return boolean
function SUI:IsModuleDisabled(moduleName)
	return not SUI:IsModuleEnabled(moduleName)
end

-- These override the default Ace3 calls so we can track the status
---@param input AceAddon|string
function SUI:DisableModule(input)
	local moduleToDisable
	if type(input) == 'table' then
		moduleToDisable = input
	else
		moduleToDisable = SUI:GetModule(input, true)
	end

	if moduleToDisable then
		SUI.DB.DisabledModules[SUI:GetModuleName(moduleToDisable)] = true
		return moduleToDisable:Disable()
	end
end

---@param input AceAddon|string
function SUI:EnableModule(input)
	local moduleToDisable
	if type(input) == 'table' then
		moduleToDisable = input
	else
		moduleToDisable = SUI:GetModule(input)
	end

	SUI.DB.DisabledModules[SUI:GetModuleName(moduleToDisable)] = nil
	return moduleToDisable:Enable()
end
