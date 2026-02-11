local SUI, L = SUI, SUI.L
---@class SUI.Module.EasyDelete : SUI.Module
local module = SUI:NewModule('EasyDelete')
module.DisplayName = 'Easy Delete'
module.description = 'Removes the need to type DELETE when destroying items'

local deleteDialogTypes = {
	['DELETE_ITEM'] = true,
	['DELETE_GOOD_ITEM'] = true,
	['DELETE_QUEST_ITEM'] = true,
	['DELETE_GOOD_QUEST_ITEM'] = true,
}

---@class SUI.Module.EasyDelete.DB
local DBDefaults = {}

local DB

function module:OnInitialize()
	module.Database = SUI.SpartanUIDB:RegisterNamespace('EasyDelete', { profile = DBDefaults })
	DB = module.Database.profile
	module.DB = DB

	-- Register profile change callbacks
	module.Database.RegisterCallback(module, 'OnProfileChanged', function()
		DB = module.Database.profile
		module.DB = DB
	end)
	module.Database.RegisterCallback(module, 'OnProfileCopied', function()
		DB = module.Database.profile
		module.DB = DB
	end)
	module.Database.RegisterCallback(module, 'OnProfileReset', function()
		DB = module.Database.profile
		module.DB = DB
	end)

	if SUI.logger then
		module.logger = SUI.logger:RegisterCategory('EasyDelete')
	end
end

function module:GetDB()
	return DB
end

---Ensures a FontString exists on the dialog to display the item link
---@param dialog Frame The StaticPopup dialog frame
---@return FontString
local function GetOrCreateItemLabel(dialog)
	if not dialog.suiItemLabel then
		dialog.suiItemLabel = dialog:CreateFontString(nil, 'ARTWORK', 'GameFontHighlight')
		dialog.suiItemLabel:SetPoint('CENTER', dialog.EditBox)
		dialog:HookScript('OnHide', function()
			if dialog.suiItemLabel then
				dialog.suiItemLabel:Hide()
			end
		end)
	end
	return dialog.suiItemLabel
end

function module:OnEnable()
	if SUI:IsModuleDisabled(module) then
		return
	end

	module:RegisterEvent('DELETE_ITEM_CONFIRM', 'OnDeleteConfirm')
	module:BuildOptions()
end

function module:OnDisable()
	module:UnregisterEvent('DELETE_ITEM_CONFIRM')
end

function module:OnDeleteConfirm()
	StaticPopup_ForEachShownDialog(function(dialog)
		if not deleteDialogTypes[dialog.which] then
			return
		end

		local editBox = dialog.EditBox
		if not editBox or not editBox:IsShown() then
			return
		end

		-- Skip the typing requirement
		editBox:Hide()
		local confirmBtn = dialog:GetButton1()
		if confirmBtn then
			confirmBtn:Enable()
		end

		-- Remove the 'Type "DELETE"...' instruction from the dialog text
		if dialog.Text then
			local fullText = dialog.Text:GetText()
			if fullText then
				local cleaned = fullText:gsub('\n\n.+$', '')
				dialog.Text:SetText(cleaned)
			end
		end

		-- Show the item link so the player knows what they are deleting
		local _, _, itemLink = GetCursorInfo()
		if itemLink then
			local label = GetOrCreateItemLabel(dialog)
			label:SetText(itemLink)
			label:Show()
		end
	end)
end
