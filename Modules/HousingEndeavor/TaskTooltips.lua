---@class SUI
local SUI = SUI
local L = SUI.L

-- Only available in Retail
if not SUI.IsRetail then
	return
end

---@class SUI.Module.HousingEndeavor
local module = SUI.HousingEndeavor

-- Debug: Check if module loaded
if module and module.logger then
	module.logger.debug('TaskTooltips.lua loading, module exists: ' .. tostring(module ~= nil))
end

----------------------------------------------------------------------------------------------------
-- Task Tooltip Enhancement
----------------------------------------------------------------------------------------------------

local tooltipHooked = false
local lastLoggedScale = nil

---Calculate the contribution scale from activity log data
---Scale = actual_amount / progressContributionAmount
---@return number scale (0 if unable to calculate)
local function CalculateContributionScale()
	local info = module:GetInitiativeInfo()
	local activityLog = module:GetActivityLogInfo()

	if not info or not info.tasks or not activityLog or not activityLog.taskActivity then
		return 0
	end

	-- Build a map of taskID to progressContributionAmount
	local taskIDToDisplayXP = {}
	for _, task in ipairs(info.tasks) do
		if task.ID and task.progressContributionAmount then
			taskIDToDisplayXP[task.ID] = task.progressContributionAmount
		end
	end

	-- Find a recent activity entry where we can calculate scale
	-- (needs both amount > 0 and matching task with progressContributionAmount)
	for _, entry in ipairs(activityLog.taskActivity) do
		local displayXP = taskIDToDisplayXP[entry.taskID]
		if displayXP and displayXP > 0 and entry.amount and entry.amount > 0 then
			local scale = entry.amount / displayXP
			if module and module.logger and scale ~= lastLoggedScale then
				module.logger.debug(string.format('TaskTooltips: Calculated scale=%.6f from task %s (amount=%.2f, displayXP=%d)', scale, entry.taskName or 'unknown', entry.amount, displayXP))
				lastLoggedScale = scale
			end
			return scale
		end
	end

	return 0
end

---Build a lookup table of task names to XP amounts from API data
---@return table<string, number> map of taskName -> estimated actual contribution
local function GetTaskNameToXPMap()
	local map = {}
	local info = module:GetInitiativeInfo()
	if not info or not info.tasks then
		return map
	end

	-- Calculate the scale factor
	local scale = CalculateContributionScale()

	for _, task in ipairs(info.tasks) do
		if task.taskName and task.progressContributionAmount then
			if scale > 0 then
				-- Apply scale to get estimated actual contribution
				map[task.taskName] = task.progressContributionAmount * scale
			else
				-- No scale available, show raw value with indicator
				map[task.taskName] = task.progressContributionAmount
			end
		end
	end
	return map, scale
end

---Check if tooltip already has our contribution line
---@param tooltip GameTooltip
---@return boolean
local function HasContributionLine(tooltip)
	local tooltipName = tooltip:GetName()
	if not tooltipName then
		return false
	end

	for i = 1, tooltip:NumLines() do
		local line = _G[tooltipName .. 'TextLeft' .. i]
		if line then
			local text = line:GetText()
			-- Validate the value is accessible (not a secret value)
			if text and SUI.BlizzAPI.canaccessvalue(text) and type(text) == 'string' then
				if text:find('Endeavor Contribution') then
					return true
				end
			end
		end
	end
	return false
end

---Enhance tooltip with task XP if it contains a task name
---@param tooltip GameTooltip
local function EnhanceTaskTooltip(tooltip)
	if not module or not module.DB or not module.DB.taskTooltips or not module.DB.taskTooltips.enabled then
		return
	end

	if HasContributionLine(tooltip) then
		return
	end

	-- Get task name to XP mapping (with scale applied)
	local taskMap, scale = GetTaskNameToXPMap()
	if not next(taskMap) then
		return
	end

	local tooltipName = tooltip:GetName()
	if not tooltipName then
		return
	end

	-- Search tooltip lines for task name matches
	for i = 1, tooltip:NumLines() do
		local line = _G[tooltipName .. 'TextLeft' .. i]
		if line then
			local text = line:GetText()
			-- Validate the value is accessible (not a secret value)
			if text and SUI.BlizzAPI.canaccessvalue(text) and type(text) == 'string' then
				-- Check against task names
				for taskName, xpAmount in pairs(taskMap) do
					if text == taskName or text:find(taskName, 1, true) then
						tooltip:AddLine(' ')
						if scale and scale > 0 then
							-- Show estimated actual contribution
							tooltip:AddDoubleLine(L['Endeavor Contribution'] .. ':', string.format('~%.1f', xpAmount), 1, 0.82, 0, 1, 1, 1)
						else
							-- No scale available, show raw value with note
							tooltip:AddDoubleLine(L['Endeavor Contribution'] .. ':', string.format('%d (base)', xpAmount), 1, 0.82, 0, 0.7, 0.7, 0.7)
						end
						tooltip:Show()
						return
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Module Integration
----------------------------------------------------------------------------------------------------

---Initialize the task tooltip system
function module:InitTaskTooltips()
	if tooltipHooked then
		if self.logger then
			self.logger.debug('TaskTooltips: Already hooked, skipping')
		end
		return
	end

	if self.logger then
		self.logger.debug('TaskTooltips: InitTaskTooltips called')
	end

	-- Use TooltipDataProcessor if available (modern WoW)
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
		if self.logger then
			self.logger.debug('TaskTooltips: Using TooltipDataProcessor')
		end
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
			EnhanceTaskTooltip(tooltip)
		end)

		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, function(tooltip)
			EnhanceTaskTooltip(tooltip)
		end)
	end

	-- Also hook GameTooltip OnShow as fallback
	if self.logger then
		self.logger.debug('TaskTooltips: Hooking GameTooltip OnShow')
	end
	GameTooltip:HookScript('OnShow', function(tooltip)
		C_Timer.After(0.05, function()
			if tooltip:IsShown() then
				EnhanceTaskTooltip(tooltip)
			end
		end)
	end)

	tooltipHooked = true

	if self.logger then
		self.logger.info('Task tooltips initialized')
	end
end

-- Note: InitTaskTooltips is called from the main HousingEndeavor.lua OnEnable
