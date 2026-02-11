---@class SUI
local SUI = SUI

-- Retail-only module (requires C_Map waypoint APIs)
if not SUI.IsRetail then
	return
end

local module = SUI:NewModule('MiniTom') ---@type SUI.Module
module.DisplayName = 'MiniTom'
module.description = 'Enables /way command to set a waypoint on your map'
local HBD = LibStub('HereBeDragons-2.0')

---@class MiniTomDB
local DBDefaults = {}

---Get the MapID for a zone name
---@param zoneName string
function module:GetMapID(zoneName)
	local matches = {}

	---@diagnostic disable-next-line: undefined-field
	for mapID, mapInfo in pairs(HBD.mapData) do
		local lname = mapInfo.name:lower()
		local lzone = zoneName:lower()
		if lname:match(lzone) then
			return mapID -- table.insert(matches, {id = mapID, name = mapInfo.name})
		end
	end

	if #matches == 1 then
		return matches[1].id
	elseif #matches > 1 then
		SUI:Print('Multiple matches found for zone name')
		for i = 1, #matches do
			SUI:Print(matches[i].id)
			SUI:Print(matches[i].name)
		end
	else
		SUI:Print('No matches found for zone name')
	end
end

---Set a waypoint on the map
---@param mapID number
---@param x number
---@param y number
---@param desc? string
function module:SetPoint(mapID, x, y, desc)
	if C_Map.CanSetUserWaypointOnMap(mapID) then
		local mapPoint = UiMapPoint.CreateFromCoordinates(mapID, tonumber(x) / 100, tonumber(y) / 100, 0)
		if mapPoint then
			C_Map.SetUserWaypoint(mapPoint)
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
			SUI:Print('Waypoint set' .. (desc and ' for ' .. desc or ''))
		end
	else
		SUI:Print('Cannot set waypoint on this map')
	end
end

local function Options()
	---@type AceConfig.OptionsTable
	local OptTable = {
		name = 'MiniTom',
		type = 'group',
		disabled = function()
			return SUI:IsModuleDisabled(module)
		end,
		get = function(info)
			return module.DB[info[#info]]
		end,
		set = function(info, value)
			module.DB[info[#info]] = value
		end,
		args = {
			enabled = {
				name = 'Enabled',
				type = 'toggle',
				order = 1,
				width = 'full',
				get = function()
					return not SUI:IsModuleDisabled(module)
				end,
				set = function(value)
					SUI:DisableModule(not value)
				end,
			},
			desc1 = {
				name = 'This module enables a simple "Mini" version of the larger TomTom addon. It allows you to set waypoints using the /way command.',
				type = 'description',
				order = 2,
			},
			desc2 = {
				name = 'This module is not compatible with the full TomTom addon. If you have TomTom enabled, this module will be automatically disabled.',
				type = 'description',
				order = 3,
			},
			desc3 = {
				name = 'Example waypoint commands:',
				order = 4,
				type = 'input',
				width = 'full',
				get = function()
					return '/way 58 68'
				end,
				set = function() end,
			},
			desc4 = {
				name = '',
				type = 'input',
				order = 5,
				width = 'full',
				get = function()
					return '/way Waking Shore 58 68'
				end,
				set = function() end,
			},
			desc5 = {
				name = '',
				type = 'input',
				order = 6,
				width = 'full',
				get = function()
					return '/way Waking Shore 58 68 Tail Fragment'
				end,
				set = function() end,
			},
			desc6 = {
				name = '',
				type = 'input',
				order = 7,
				width = 'full',
				get = function()
					return '/way #2022 58 68 Tail Fragment'
				end,
				set = function() end,
			},
		},
	}

	SUI.Options:AddOptions(OptTable, 'MiniTom', nil)
end

function module:OnInitialize()
	module.Database = SUI.SpartanUIDB:RegisterNamespace('MiniTom', { profile = DBDefaults })
	---@type MiniTomDB
	module.DB = module.Database.profile

	-- Register profile change callbacks
	SUI.DBM:RegisterSequentialProfileRefresh(module)
	if SUI:IsAddonEnabled('TomTom') then
		module.override = true
	end
end

function module:OnEnable()
	Options()
	if SUI:IsModuleDisabled(module) then
		return
	end

	local function SetWaypoint(args)
		-- Remove any commas or periods from the numbers
		args = args:gsub('(%d)[%.,] (%d)', '%1 %2')
		local inputSections = {}
		-- Split the string
		for item in args:gmatch('%S+') do
			table.insert(inputSections, item)
		end

		-- Find the first number and use that to determine the end of the zone name
		local zoneEnd
		for i = 1, #inputSections do
			local token = inputSections[i]
			if tonumber(token) then
				zoneEnd = i - 1
				break
			end
		end

		local zone = table.concat(inputSections, ' ', 1, zoneEnd)
		local x, y, desc = select(zoneEnd + 1, unpack(inputSections))
		if desc then
			desc = table.concat(inputSections, ' ', zoneEnd + 3)
		end

		if inputSections[1] and not tonumber(inputSections[1]) then
			-- Find MapID
			local mapID
			if string.match(inputSections[1], '#') then
				mapID = tonumber(string.match(inputSections[1], '#(%d+)'))
			else
				mapID = module:GetMapID(zone)
			end

			if mapID then
				module:SetPoint(mapID, x, y, desc)
			else
				SUI:Print('Invalid zone name')
			end
		else
			local mapID = C_Map.GetBestMapForUnit('player')
			module:SetPoint(mapID, x, y, desc)
		end
	end

	SlashCmdList.MiniTom = SetWaypoint
	SLASH_MiniTom1 = '/way'
end

function module:OnDisable()
	SlashCmdList.MiniTom = nil
	SLASH_MiniTom1 = nil
end
