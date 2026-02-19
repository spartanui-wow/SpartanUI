---@class SUI
local SUI = SUI
local L = SUI.L

-- Only available in Retail
if not SUI.IsRetail then
	return
end

---@class SUI.Module.HousingEndeavor
local module = SUI.HousingEndeavor

----------------------------------------------------------------------------------------------------
-- LibDataBroker Integration
----------------------------------------------------------------------------------------------------

local LDB = LibStub('LibDataBroker-1.1', true)
local dataObj = nil ---@type table|nil

---Create or update the LDB data object
local function CreateDataObject()
	if not LDB then
		if module.logger then
			module.logger.warning('LibDataBroker-1.1 not available')
		end
		return
	end

	if dataObj then
		return dataObj
	end

	dataObj = LDB:NewDataObject('SUI_HousingEndeavor', {
		type = 'data source',
		text = L['Housing Endeavor'],
		label = L['Housing Endeavor'],
		icon = 'Interface\\Icons\\INV_Misc_Chest_Beaker_01', -- Housing-related icon
		OnClick = function(_, button)
			if button == 'LeftButton' then
				-- Try to open Housing UI
				if C_AddOns.IsAddOnLoaded('Blizzard_HousingUI') then
					if HousingUI_Toggle then
						HousingUI_Toggle()
					elseif ToggleHousingUI then
						ToggleHousingUI()
					end
				else
					-- Fallback: Open SUI options
					SUI.Options:OpenOptions('HousingEndeavor')
				end
			elseif button == 'RightButton' then
				-- Open SUI options
				SUI.Options:OpenOptions('HousingEndeavor')
			end
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddLine('|cffffffffSpartan|cffe21f1fUI|r ' .. L['Housing Endeavor'])
			tooltip:AddLine(' ')

			local progress = module:GetCurrentProgress()
			if progress then
				-- Title
				tooltip:AddLine(progress.title, 1, 0.82, 0)
				tooltip:AddLine(' ')

				-- Current progress
				tooltip:AddDoubleLine(L['Current XP:'], string.format('%.1f', progress.currentXP), 1, 1, 1, 0.2, 1, 0.2)

				-- Milestones
				for i, threshold in ipairs(progress.milestones) do
					local completed = progress.currentXP >= threshold
					local isCurrent = not completed and i == progress.currentMilestone
					local icon, color
					if completed then
						icon = CreateAtlasMarkup('housing-dashboard-small-checkmark', 14, 14)
						color = { 0.2, 1, 0.2 }
					elseif isCurrent then
						icon = CreateAtlasMarkup('housing-dashboard-timertag-clock-icon', 14, 14)
						color = { 1, 1, 1 }
					else
						icon = CreateAtlasMarkup('housing-dashboard-timertag-clock-icon', 14, 14)
						color = { 0.5, 0.5, 0.5 }
					end
					tooltip:AddDoubleLine(icon .. ' ' .. L['Milestone'] .. ' ' .. i .. ':', string.format('%.0f XP', threshold), color[1], color[2], color[3], color[1], color[2], color[3])
				end

				tooltip:AddLine(' ')

				-- Progress to next milestone
				if progress.xpNeeded > 0 then
					tooltip:AddDoubleLine(L['XP to next:'], string.format('%.1f (%.1f%%)', progress.xpNeeded, progress.percentage), 1, 1, 1, 1, 0.82, 0)
					tooltip:AddDoubleLine(L['XP to final:'], string.format('%.1f', module:GetXPToFinal()), 1, 1, 1, 1, 0.82, 0)
				else
					tooltip:AddLine('|cff00ff00' .. L['All milestones completed!'] .. '|r')
				end
			else
				tooltip:AddLine(L['No data available'], 0.7, 0.7, 0.7)
				tooltip:AddLine(' ')
				tooltip:AddLine(L['Housing Initiative system may not be available.'], 0.7, 0.7, 0.7)
			end

			tooltip:AddLine(' ')
			tooltip:AddLine('|cff888888' .. L['Left-click: Open Housing UI'] .. '|r')
			tooltip:AddLine('|cff888888' .. L['Right-click: Open settings'] .. '|r')
		end,
	})

	return dataObj
end

---Update the LDB text display
---Exposed as module method so centralized OnMessage_UPDATED can call it
function module:UpdateDataBroker()
	if not dataObj then
		if module.logger then
			module.logger.debug('UpdateDataObject: no dataObj')
		end
		return
	end
	if not module.DB or not module.DB.dataBroker.enabled then
		if module.logger then
			module.logger.debug('UpdateDataObject: disabled')
		end
		dataObj.text = L['Disabled']
		return
	end

	local progress = module:GetCurrentProgress()
	if not progress then
		if module.logger then
			module.logger.debug('UpdateDataObject: no progress data')
		end
		dataObj.text = L['No data']
		return
	end

	-- Format text based on user preference
	local format = module.DB.dataBroker.format or 'short'
	local newText = module:FormatProgressText(format, progress)
	if module.logger then
		module.logger.debug('UpdateDataObject: setting text to "' .. newText .. '"')
	end
	dataObj.text = newText
end

----------------------------------------------------------------------------------------------------
-- Module Integration
----------------------------------------------------------------------------------------------------

---Initialize the DataBroker plugin
function module:InitDataBroker()
	CreateDataObject()
	module:UpdateDataBroker()
end

-- Note: InitDataBroker is called from the main HousingEndeavor.lua OnEnable
