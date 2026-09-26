---@type SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.ActionBars
local module = SUI:GetModule('ActionBars')

local _, playerClass = UnitClass('player')

local UTILITY_MOVERS = {
	PetAB = 'BT4BarPetBar',
	ShiftAB = 'BT4BarStanceBar',
	MicrobarMover = 'BT4BarMicroMenu',
	BagsMover = 'BT4BarBagBar',
}

---@type SUI.ActionBars.Importer
local importer = { id = 'ElvUI', name = 'ElvUI' }

---@return table|nil E
---@return table|nil P
local function GetElvUI()
	local engine = _G.ElvUI
	if type(engine) ~= 'table' then
		return nil, nil
	end
	return engine[1], engine[4]
end

function importer:IsAvailable()
	local E = GetElvUI()
	if not E or type(_G.ElvDB) ~= 'table' or type(_G.ElvDB.profiles) ~= 'table' then
		return false, L['Turn on ElvUI and reload to import its settings. You can turn it off again afterwards.']
	end
	return true
end

function importer:GetProfiles()
	local list = {}
	for name in pairs(_G.ElvDB.profiles or {}) do
		list[#list + 1] = name
	end
	table.sort(list)
	return list
end

function importer:GetCurrentProfile()
	local E = GetElvUI()
	if E and E.data and E.data.GetCurrentProfile then
		return E.data:GetCurrentProfile()
	end
	return nil
end

---ElvUI settings for a profile, with ElvUI's defaults filled back in.
---@param profile string
---@return table data
---@return table|nil saved Raw saved table, used to spot legacy profiles
local function GetProfileData(profile)
	local E, P = GetElvUI()
	local saved = _G.ElvDB.profiles[profile]
	if E and E.db and importer:GetCurrentProfile() == profile then
		return E.db, saved
	end
	return module:MergeWithDefaults(P, saved), saved
end

---Font settings for one text element, read from an ElvUI bar.
local function ConvertText(src, prefix, offsetPrefix)
	local color = src['use' .. prefix:gsub('^%l', string.upper) .. 'Color'] and module:ResolveColor(src[prefix .. 'Color'])
	local x = src[offsetPrefix .. 'XOffset']
	local y = src[offsetPrefix .. 'YOffset']
	local text = {
		face = module:ResolveFontName(src[prefix .. 'Font']),
		size = src[prefix .. 'FontSize'],
		flags = module:ResolveFontFlags(src[prefix .. 'FontOutline']),
		anchor = src[prefix .. 'TextPosition'],
		x = x,
		y = y,
	}
	if color then
		text.color = color
	end
	return text
end

---Layout, fading and visibility shared by every ElvUI bar type.
---@param src table
---@return table
local function ConvertBarLayout(src)
	local backdrop = src.backdrop and true or false
	return {
		enabled = src.enabled and true or false,
		buttonsPerRow = src.buttonsPerRow,
		buttonSize = src.buttonSize or src.buttonsize,
		buttonHeight = src.buttonHeight,
		keepSizeRatio = src.keepSizeRatio ~= false,
		buttonSpacing = src.buttonSpacing or src.buttonspacing,
		backdrop = backdrop,
		-- Without a backdrop ElvUI draws the buttons edge to edge with the bar
		backdropSpacing = backdrop and ((src.backdropSpacing or 2) + 1) or 0,
		point = src.point,
		alpha = src.alpha,
		mouseover = src.mouseover and true or false,
		mouseoverAlpha = 0,
		inheritGlobalFade = src.inheritGlobalFade and true or false,
		clickThrough = src.clickThrough and true or false,
		frameStrata = src.frameStrata,
		frameLevel = src.frameLevel,
		visibility = type(src.visibility) == 'string' and src.visibility:gsub('[\n\r]', ' ') or nil,
	}
end

---@param profile string
---@return SUI.ActionBars.ImportResult
function importer:Build(profile)
	local result = module:NewImportResult()
	local data, saved = GetProfileData(profile)
	local _, P = GetElvUI()
	local ab = data.actionbar or {}
	local defaults = P and P.actionbar or {}
	local isCurrent = self:GetCurrentProfile() == profile
	local movers = {}
	for moverName, key in pairs(UTILITY_MOVERS) do
		movers[moverName] = key
	end

	-- Profiles from before ElvUI renumbered its bars still use the old order
	local swap = {}
	if not isCurrent and saved and saved.convertPages == nil and saved.actionbar then
		swap = { [2] = 6, [6] = 2, [3] = 5, [5] = 3 }
	end

	for _, id in ipairs(module.ACTION_BAR_IDS) do
		local sourceID = swap[id] or id
		local src = ab['bar' .. sourceID]
		if type(src) == 'table' then
			local bar = ConvertBarLayout(src)
			bar.buttons = src.buttons
			bar.showGrid = src.showGrid and true or false
			bar.flyoutDirection = src.flyoutDirection
			bar.hotkeyText = src.hotkeytext ~= false
			bar.macroText = src.macrotext and true or false
			bar.countText = src.counttext ~= false

			local paging = type(src.paging) == 'table' and src.paging[playerClass]
			local defaultPaging = defaults['bar' .. sourceID] and defaults['bar' .. sourceID].paging and defaults['bar' .. sourceID].paging[playerClass]
			if type(paging) == 'string' and paging:gsub('%s', '') ~= '' and paging ~= defaultPaging then
				bar.paging = { [playerClass] = paging }
				bar.pagingEnabled = true
			end
			result.settings.bars[id] = bar
			result.scales['BT4Bar' .. id] = 1
			movers['ElvAB_' .. sourceID] = 'BT4Bar' .. id
		end
	end

	-- Global button behavior
	result.settings.lockButtons = ab.lockActionBars ~= false
	result.settings.rightClickSelfCast = ab.rightClickSelfCast and true or false
	result.settings.outOfRangeColoring = ab.useRangeColorText and 'hotkey' or 'button'
	result.settings.colors = {
		range = module:ResolveColor(ab.noRangeColor) or module.DBDefaults.colors.range,
		mana = module:ResolveColor(ab.noPowerColor) or module.DBDefaults.colors.mana,
	}
	local fadeAlpha = tonumber(ab.globalFadeAlpha) or 0
	result.settings.globalFade = {
		enabled = fadeAlpha > 0,
		alpha = 1 - fadeAlpha,
	}

	-- ElvUI styles text per bar; bar 1's text becomes SpartanUI's shared style
	local bar1 = ab.bar1
	if type(bar1) == 'table' then
		result.settings.text = {
			hotkey = ConvertText(bar1, 'hotkey', 'hotkeyText'),
			count = ConvertText(bar1, 'count', bar1.countTextXOffset and 'countText' or 'countFont'),
			macro = ConvertText(bar1, 'macro', 'macroText'),
		}
	end

	if type(ab.barPet) == 'table' then
		local pet = ConvertBarLayout(ab.barPet)
		pet.hotkeyText = ab.barPet.hotkeytext ~= false
		result.settings.pet = pet
		result.scales.BT4BarPetBar = 1
	end
	if type(ab.stanceBar) == 'table' then
		local stance = ConvertBarLayout(ab.stanceBar)
		stance.hotkeyText = ab.stanceBar.hotkeytext ~= false
		result.settings.stance = stance
		result.scales.BT4BarStanceBar = 1
	end
	if type(ab.microbar) == 'table' then
		local micro = ConvertBarLayout(ab.microbar)
		-- ElvUI redraws the micro icons in its own shape; keep Blizzard's shape here
		micro.buttonSize, micro.buttonHeight, micro.keepSizeRatio = nil, nil, nil
		result.settings.micro = micro
		result.scales.BT4BarMicroMenu = 1
	end

	local bagBar = data.bags and data.bags.bagBar
	if type(bagBar) == 'table' then
		local E = GetElvUI()
		local enabled = E and E.private and E.private.bags and E.private.bags.bagBar
		result.settings.bags = {
			enabled = enabled and true or false,
			buttonSize = bagBar.size,
			buttonSpacing = bagBar.spacing,
			backdrop = bagBar.showBackdrop and true or false,
			backdropSpacing = bagBar.showBackdrop and bagBar.backdropSpacing or 0,
			mouseover = bagBar.mouseover and true or false,
			onlyBackpack = bagBar.justBackpack and true or false,
			reverse = bagBar.sortDirection == 'DESCENDING',
			buttonsPerRow = bagBar.growthDirection == 'VERTICAL' and 1 or 7,
			visibility = type(bagBar.visibility) == 'string' and bagBar.visibility:gsub('[\n\r]', ' ') or nil,
		}
		if not enabled then
			-- ElvUI's bag bar was off, so the Blizzard-style bag buttons stay where they were
			result.settings.bags = { enabled = true }
		else
			result.scales.BT4BarBagBar = 1
		end
	end

	-- Positions
	local savedMovers = type(data.movers) == 'table' and data.movers or {}
	local E = GetElvUI()
	local layouts = E and E.LayoutMoverPositions
	for moverName, key in pairs(movers) do
		local position
		local frame = isCurrent and _G[moverName]
		if frame and frame.GetLeft and frame:GetLeft() then
			local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
			position = { point = 'BOTTOMLEFT', anchor = UIParent, relativePoint = 'BOTTOMLEFT', x = frame:GetLeft() * ratio, y = frame:GetBottom() * ratio }
		else
			local stored = savedMovers[moverName]
			if not stored and layouts then
				stored = (data.layoutSet and layouts[data.layoutSet] and layouts[data.layoutSet][moverName]) or (layouts.ALL and layouts.ALL[moverName])
			end
			if type(stored) == 'string' then
				local point, anchorName, relativePoint, x, y = strsplit(stored:find('\031') and '\031' or ',', stored)
				position = {
					point = point,
					anchor = (anchorName and _G[anchorName]) or UIParent,
					relativePoint = relativePoint,
					x = tonumber(x) or 0,
					y = tonumber(y) or 0,
				}
			end
		end
		if position then
			result.positions[key] = position
		end
	end

	-- Bars without a Blizzard binding used ElvUI's own binding names
	for _, id in ipairs({ 2, 7, 8, 9, 10 }) do
		local sourceID = swap[id] or id
		for i = 1, 12 do
			result.bindings[('ELVUIBAR%dBUTTON%d'):format(sourceID, i)] = ('CLICK %s:Keybind'):format(module:GetActionButtonName(id, i))
		end
	end

	table.insert(result.notes, L['ElvUI import: button skins, cooldown text styling and backdrop size multipliers are not carried over.'])
	return result
end

---Turn ElvUI's action bars off so they do not sit on top of SpartanUI's.
function importer:DisableSource()
	local E = GetElvUI()
	if E and E.private then
		if E.private.actionbar then
			E.private.actionbar.enable = false
		end
		if E.private.bags then
			E.private.bags.bagBar = false
		end
	end
end

module:RegisterImporter(importer)
