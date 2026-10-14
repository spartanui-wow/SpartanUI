local SUI, L = SUI, SUI.L
local MoveIt = SUI.MoveIt

-- Lib's DataBar is a separate addon. When it is installed, SpartanUI styles its bars to match
-- the active theme and places the bars a theme has a spot for. DataBar keeps everything else
-- (plugins, order, tooltips, fading), and the player can take any bar back in DataBar's settings.
-- SpartanUI also adds two small bars: one under the minimap (on) and one above the chat window (off).

---@class SUI.Handler.DataBarHost : SUI.Module
local module = SUI:NewModule('Handler.DataBarHost')

local THEME_ID = 'spartanui'
local DEFAULT_WIDTH = 700
local DEFAULT_HEIGHT = 22

-- Small bars SpartanUI adds to Lib's DataBar. Each slot shows the first plugin on its list the player has.
local MINIMAP_BAR = 'sui_minimap'
local CHAT_BAR = 'sui_chat'
local MINI_HEIGHT = 20
local MINIMAP_PLUGINS = { "Lib's Social", "Lib's TimePlayed", "Lib's Clock" }
local CHAT_PLUGINS = { 'LibsMessenger', "Lib's Bags", "Lib's Clock" }

---@type table<string, Frame>
local holders = {}
---@type table<string, { position: string, width?: number, height?: number, strata?: string, label?: string, isAvailable?: fun(): boolean }>
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

---@param value number
---@return number
local function Round(value)
	return math.floor(value + 0.5)
end

---True when a frame's size and place can be read (not a combat-protected value on Retail)
---@param ... any
---@return boolean
local function Readable(...)
	for i = 1, select('#', ...) do
		local value = select(i, ...)
		if type(value) ~= 'number' or (canaccessvalue and not canaccessvalue(value)) then
			return false
		end
	end
	return true
end

---A frame's width in UIParent units, so a bar holder can match it whatever either is scaled to
---@param frame Frame|nil
---@param fallback number
---@return number
local function ScreenWidth(frame, fallback)
	local width = frame and frame:GetWidth()
	if not Readable(width) or width <= 0 then
		return fallback
	end
	return Round(width * frame:GetEffectiveScale() / UIParent:GetEffectiveScale())
end

---How far under the map the minimap bar sits: below the zone text and coordinates SpartanUI draws
---there (the minimap holder reaches down past them), or right under the map without them
---@return number y
local function MinimapBarOffset()
	local holder = _G.SUI_Minimap
	if not Minimap or not holder or not holder:IsShown() then
		return -2
	end
	local mapBottom, holderBottom = Minimap:GetBottom(), holder:GetBottom()
	if not Readable(mapBottom, holderBottom) then
		return -2
	end
	local uiScale = UIParent:GetEffectiveScale()
	local gap = mapBottom * Minimap:GetEffectiveScale() / uiScale - holderBottom * holder:GetEffectiveScale() / uiScale
	if gap > 0 and gap < 120 then
		return -Round(gap) - 2
	end
	return -2
end

---How far above the chat window the chat bar sits: over its tabs
---@return number y
local function ChatBarOffset()
	local chat, tab = _G.ChatFrame1, _G.ChatFrame1Tab
	local chatTop, tabTop = chat and chat:GetTop(), tab and tab:GetTop()
	if Readable(chatTop, tabTop) and tabTop > chatTop then
		local uiScale = UIParent:GetEffectiveScale()
		return Round(tabTop * tab:GetEffectiveScale() / uiScale - chatTop * chat:GetEffectiveScale() / uiScale) + 2
	end
	return 26
end

---@param barId string
---@return boolean
local function IsBarOn(barId)
	local api = LibsDataBar and LibsDataBar.API
	return api ~= nil and api.IsBarEnabled ~= nil and api:IsBarEnabled(barId)
end

---The small bars SpartanUI adds, as Lib's DataBar definitions. The attach spot is where the bar
---goes when the player takes it back from SpartanUI in DataBar's settings.
---@return table<string, table>
local function MiniBarDefinitions()
	local definitions = {}
	-- Minimap bar off for now (it was added for testing)
	--[[
	if Minimap then
		definitions[MINIMAP_BAR] = {
			name = L['Minimap bar'],
			kind = 'mini',
			enabled = true,
			slots = 2,
			plugins = MINIMAP_PLUGINS,
			attach = { frame = 'Minimap', side = 'below', y = MinimapBarOffset(), matchWidth = true, hideWithTarget = true },
			size = { height = MINI_HEIGHT },
			pluginDefaults = { mode = 'text', showLabel = false },
		}
	end
	--]]
	if _G.ChatFrame1 then
		definitions[CHAT_BAR] = {
			name = L['Chat bar'],
			kind = 'mini',
			enabled = false,
			slots = 3,
			plugins = CHAT_PLUGINS,
			attach = { frame = 'ChatFrame1', side = 'above', y = ChatBarOffset(), matchWidth = true },
			size = { height = MINI_HEIGHT },
			pluginDefaults = { mode = 'text', showLabel = false },
		}
	end
	return definitions
end

---Holder spots for the small bars: attached to the map and the chat window, as wide as they are.
---The movers keep these spots as their default, so resetting a moved bar brings it back here.
---@return table<string, table>
local function MiniBarSlots()
	local list = {}
	local api = API()
	if not (api and api.DefineBar) then
		-- A Lib's DataBar from before small bars
		return list
	end
	--[[ Minimap bar off for now (it was added for testing)
	if Minimap then
		list[MINIMAP_BAR] = {
			position = 'TOP,Minimap,BOTTOM,0,' .. MinimapBarOffset(),
			width = ScreenWidth(Minimap, 180),
			height = MINI_HEIGHT,
			label = L['Minimap bar'],
			isAvailable = function()
				return IsBarOn(MINIMAP_BAR)
			end,
		}
	end
	--]]
	if _G.ChatFrame1 then
		list[CHAT_BAR] = {
			position = 'BOTTOMLEFT,ChatFrame1,TOPLEFT,0,' .. ChatBarOffset(),
			width = ScreenWidth(_G.ChatFrame1, 430),
			height = MINI_HEIGHT,
			label = L['Chat bar'],
			isAvailable = function()
				return IsBarOn(CHAT_BAR)
			end,
		}
	end
	return list
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
			MoveIt:CreateMover(holder, MoverName(barId), slot.label or (L["Lib's DataBar"] .. ' (' .. barId .. ')'), nil, L['Info bars'])
			local mover = MoveIt.MoverList[MoverName(barId)]
			if mover and slot.isAvailable then
				local isAvailable = slot.isAvailable
				mover.IsMoverAvailable = function()
					return isAvailable()
				end
				mover.optionsPath = { 'Modules', 'DataBars' }
			end
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
	for barId, slot in pairs(MiniBarSlots()) do
		slots[barId] = slot
		placements[barId] = { width = slot.width, height = slot.height }
		before[barId] = nil
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

---Bars SpartanUI wants Lib's DataBar to have
---@return table<string, table>
function host:GetBarDefinitions()
	return MiniBarDefinitions()
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
	self:RefreshPlacements()
end

---Place the bars again (the map or chat window moved, grew or shrank), without rebuilding the look
function module:RefreshPlacements()
	local api = API()
	if not api then
		return
	end
	if InCombatLockdown() then
		self.pendingPlacement = true
		return
	end
	RebuildSlots()
	api:RefreshHost()
end

---Place the bars again on the next frame; a resize fires many times while the player drags
function module:QueuePlacementRefresh()
	if self.placementQueued then
		return
	end
	self.placementQueued = true
	C_Timer.After(0, function()
		module.placementQueued = false
		module:RefreshPlacements()
	end)
end

---Follow the map and the chat window the small bars sit next to. Hooks only.
function module:WatchMiniBarTargets()
	local function Queue()
		module:QueuePlacementRefresh()
	end
	if Minimap and Minimap.HookScript then
		Minimap:HookScript('OnSizeChanged', Queue)
	end
	if _G.SUI_Minimap then
		-- The minimap mover scales the map through its holder
		hooksecurefunc(_G.SUI_Minimap, 'SetScale', Queue)
	end
	if _G.ChatFrame1 and _G.ChatFrame1.HookScript then
		_G.ChatFrame1:HookScript('OnSizeChanged', Queue)
	end
	self:RegisterEvent('PLAYER_ENTERING_WORLD', Queue)
end

---SpartanUI settings for the small bars: turn each one on or off
function module:BuildOptions()
	local api = API()
	if not (api and api.DefineBar and SUI.Options and SUI.opt and SUI.opt.args and SUI.opt.args.Modules) then
		return
	end
	local function BarToggle(barId, name, desc, order)
		return {
			type = 'toggle',
			name = name,
			desc = desc,
			width = 'full',
			order = order,
			get = function()
				return IsBarOn(barId)
			end,
			set = function(_, value)
				local api = API()
				if api then
					api:SetBarEnabled(barId, value)
				end
			end,
		}
	end
	SUI.Options:AddOptions({
		type = 'group',
		name = L['Info bars'],
		args = {
			intro = {
				type = 'description',
				name = L["Small bars from Lib's DataBar. Right-click one to choose what it shows."],
				fontSize = 'medium',
				order = 0,
			},
			-- Minimap bar off for now (it was added for testing)
			-- minimap = BarToggle(MINIMAP_BAR, L['Show a bar under the minimap'], L['Shows who is online in your guild and friends list, your time played, or the clock, depending on which addons you have.'], 1),
			chat = BarToggle(CHAT_BAR, L['Show a bar above the chat window'], L['Shows your messages, bag space and the clock, depending on which addons you have.'], 2),
			move = {
				type = 'execute',
				name = L['Move them'],
				desc = L['Opens move mode. Reset a bar there to put it back next to the minimap or chat window.'],
				order = 3,
				func = function()
					host:OpenMoveMode(IsBarOn(MINIMAP_BAR) and MINIMAP_BAR or CHAT_BAR)
				end,
			},
			more = {
				type = 'execute',
				name = L["More settings in Lib's DataBar"],
				order = 4,
				width = 'double',
				func = function()
					if LibsDataBar and LibsDataBar.OpenConfig then
						LibsDataBar:OpenConfig('bars', CHAT_BAR)
					end
				end,
			},
		},
	}, 'DataBars')
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
			module:RefreshPlacements()
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
	self:WatchMiniBarTargets()
	self:BuildOptions()
end
