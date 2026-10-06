local SUI, L = SUI, SUI.L
local MoveIt = SUI.MoveIt

-- Lib's DataBar is a separate addon. When it is installed, SpartanUI styles its bars to match
-- the active theme and places the bars a theme has a spot for. DataBar keeps everything else
-- (plugins, order, tooltips, fading), and the player can take any bar back in DataBar's settings.

---@class SUI.Handler.DataBarHost : SUI.Module
local module = SUI:NewModule('Handler.DataBarHost')

local THEME_ID = 'spartanui'
local DEFAULT_WIDTH = 700
local DEFAULT_HEIGHT = 22

---@type table<string, Frame>
local holders = {}
---@type table<string, { position: string, width?: number, height?: number, strata?: string }>
local slots = {}
---@type table<string, { width: number, height: number, strata?: string }>
local placements = {}
local refreshQueued = false

---@return table|nil
local function API()
	return LibsDataBar and LibsDataBar.API
end

---@param barId string
---@return string
local function MoverName(barId)
	return 'DataBar_' .. barId
end

---The `dataBars` block of the active theme
---@return table
local function ThemeSpec()
	local data = SUI.ThemeRegistry:GetData(SUI:GetActiveStyle())
	return (data and data.dataBars) or {}
end

---A theme `look` with SpartanUI's DataBar font and the accent filled in
---@param source table|nil
---@return table look
local function BuildLook(source)
	local look = SUI:CopyData({}, source or {})
	local r, g, b = SUI.UI.Style:GetAccent()
	look.font = look.font or {}
	look.font.face = SUI.Font:GetFont('DataBar')
	look.font.size = (look.font.size or 11) + (SUI.Font.DB and SUI.Font.DB.Modules.DataBar.Size or 0)
	look.font.shadow = true
	look.labelColor = look.labelColor or { r, g, b, 1 }
	look.highlight = look.highlight or { r, g, b, 0.22 }
	look.bar = look.bar or {}
	return look
end

---One DataBar look per painted strip, so a player can keep any strip whatever SpartanUI look they use
---@return table[] definitions
function module:BuildStripThemes()
	local list = {}
	for index, strip in ipairs(SUI.ThemeDataBars.list) do
		list[index] = {
			id = THEME_ID .. '-' .. strip.id,
			name = 'SpartanUI: ' .. strip.name,
			description = SUI.ThemeDataBars.Description(strip),
			order = 10 + index,
			base = 'default',
			look = BuildLook(SUI.ThemeDataBars.Look(strip.id)),
		}
	end
	return list
end

---Send the matching look and every strip look to DataBar
---@param api table
function module:UpdateThemes(api)
	api:UpdateTheme(self:BuildTheme())
	for _, definition in ipairs(self:BuildStripThemes()) do
		api:UpdateTheme(definition)
	end
end

---DataBar theme built from the active SpartanUI theme, font and accent
---@return table
function module:BuildTheme()
	local style = SUI:GetActiveStyle()
	local spec = ThemeSpec()
	local look = BuildLook(spec.look)
	-- Themes whose art color the player can change pass that color on to the bar edge
	if look.accent == 'Color.Art' then
		local art = SUI.ThemeRegistry:GetSetting(style, 'Color.Art')
		if art then
			look.bar.border = { show = true, color = { art[1], art[2], art[3], 1 } }
		end
	end
	look.accent = nil

	return {
		id = THEME_ID,
		name = 'SpartanUI',
		description = L['Matches your SpartanUI look and changes with it.'],
		order = 0,
		base = spec.base or 'default',
		look = look,
	}
end

---Holder frame the bar is anchored to. It carries the mover, so the player's moves are saved
---the same way as every other SpartanUI frame.
---@param barId string
---@return Frame
local function GetHolder(barId)
	local slot = slots[barId]
	local holder = holders[barId]
	if not holder then
		holder = CreateFrame('Frame', 'SUI_DataBarHolder_' .. barId, UIParent)
		holders[barId] = holder
	end
	holder:SetSize(slot.width or DEFAULT_WIDTH, slot.height or DEFAULT_HEIGHT)
	local point, anchor, relativePoint, x, y = strsplit(',', slot.position)
	x, y = tonumber(x) or 0, tonumber(y) or 0
	if MoveIt and MoveIt.MoverList[MoverName(barId)] then
		holder:position(point, anchor, relativePoint, x, y, false, true)
	else
		holder:ClearAllPoints()
		holder:SetPoint(point, anchor or 'UIParent', relativePoint or point, x, y)
		if MoveIt then
			MoveIt:CreateMover(holder, MoverName(barId), L["Lib's DataBar"] .. ' (' .. barId .. ')', nil, L['Info bars'])
		end
	end
	holder:Show()
	return holder
end

---@param barId string
local function ReleaseHolder(barId)
	if MoveIt then
		MoveIt:ReleaseMover(MoverName(barId))
	end
	if holders[barId] then
		holders[barId]:Hide()
	end
end

---Re-read which bars the active theme places
local function RebuildSlots()
	local before = {}
	for barId in pairs(slots) do
		before[barId] = true
	end
	wipe(slots)
	wipe(placements)

	local bars = ThemeSpec().bars
	if type(bars) == 'table' then
		for barId, slot in pairs(bars) do
			if type(slot) == 'table' and type(slot.position) == 'string' then
				slots[barId] = slot
				placements[barId] = { width = slot.width or DEFAULT_WIDTH, height = slot.height or DEFAULT_HEIGHT, strata = slot.strata }
				before[barId] = nil
			end
		end
	end

	-- A bar the new theme has no spot for goes back to DataBar's own placement
	for barId in pairs(before) do
		ReleaseHolder(barId)
	end
end

-- The host object DataBar calls into
local host = {}

function host:GetName()
	return 'SpartanUI'
end

---@param barId string
function host:GetBarPlacement(barId)
	return placements[barId]
end

---@param barId string
---@param frame Frame
function host:PlaceBar(barId, frame)
	if not slots[barId] then
		return
	end
	frame:SetAllPoints(GetHolder(barId))
end

---@param barId string
function host:OpenMoveMode(barId)
	if not MoveIt or not MoveIt.MoverMode or InCombatLockdown() then
		return
	end
	MoveIt.MoverMode:Enter()
	local mover = MoveIt.MoverList[MoverName(barId)]
	if mover then
		MoveIt.MoverMode:Select(mover)
	end
end

module.host = host

---Rebuild the look and placements after a theme, font or accent change (once per frame)
function module:QueueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	C_Timer.After(0, function()
		refreshQueued = false
		module:Refresh()
	end)
end

function module:Refresh()
	local api = API()
	if not api then
		return
	end
	self:UpdateThemes(api)
	if InCombatLockdown() then
		self.pendingPlacement = true
		return
	end
	RebuildSlots()
	api:RefreshHost()
end

function module:OnInitialize()
	SUI.DBM:SetupModule(self, { adopted = false })
	if not API() then
		return
	end
	-- Registered before DataBar starts, so a player who already uses this theme never sees another one first
	self:UpdateThemes(API())
end

function module:OnEnable()
	local api = API()
	if not api then
		return
	end

	-- A hidden string puts a "DataBar" entry on the font settings page
	local sample = UIParent:CreateFontString(nil, 'OVERLAY')
	sample:Hide()
	SUI.Font:Format(sample, 11, 'DataBar')
	hooksecurefunc(SUI.Font, 'Refresh', function()
		module:QueueRefresh()
	end)

	SUI.Event:RegisterEvent('ARTWORK_STYLE_CHANGED', function()
		module:QueueRefresh()
	end)
	SUI.UI.Style:OnAccentChanged(module, function()
		module:QueueRefresh()
	end)

	api:RegisterCallback('SpartanUI_DataBarHost', function(event, data)
		local barId = type(data) == 'table' and data.barId
		if (event == 'remove' or (event == 'host' and not data.hosted)) and barId then
			ReleaseHolder(barId)
		end
	end)

	self:RegisterEvent('PLAYER_REGEN_ENABLED', function()
		if module.pendingPlacement then
			module.pendingPlacement = false
			module:Refresh()
		end
	end)

	-- Use the SpartanUI look once, the first time both addons run together, unless the player
	-- already picked a DataBar look of their own
	if not self.DB.adopted then
		local current = api:GetThemeId()
		if not current or current == 'default' then
			api:SetThemeId(THEME_ID)
		end
		self.DB.adopted = true
	end

	self:UpdateThemes(api)
	RebuildSlots()
	api:SetHost(host)
end
