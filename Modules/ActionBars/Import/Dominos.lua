---@type SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.ActionBars
local module = SUI:GetModule('ActionBars')

local _, playerClass = UnitClass('player')
local _, playerRace = UnitRace('player')
local HAS_PETBATTLE = SUI.IsRetail or SUI.IsMOP or SUI.IsCata

---@type SUI.ActionBars.Importer
local importer = { id = 'Dominos', name = 'Dominos' }

----------------------------------------------------------------------------------------------------
-- Paging states
----------------------------------------------------------------------------------------------------

local MODIFIER_STATES = {
	{ 'selfcast', '[mod:SELFCAST]' },
	{ 'ctrlAltShift', '[mod:alt,mod:ctrl,mod:shift]' },
	{ 'ctrlAlt', '[mod:alt,mod:ctrl]' },
	{ 'altShift', '[mod:alt,mod:shift]' },
	{ 'ctrlShift', '[mod:ctrl,mod:shift]' },
	{ 'meta', '[mod:meta]' },
	{ 'alt', '[mod:alt]' },
	{ 'ctrl', '[mod:ctrl]' },
	{ 'shift', '[mod:shift]' },
}

local TARGET_STATES = {
	{ 'help', '[help]' },
	{ 'harm', '[harm]' },
	{ 'notarget', '[noexists]' },
}

---Class states that map to a fixed macro condition on this game version.
---@return table<string, string>
local function GetClassConditions()
	local conditions = {}
	local modern = SUI.IsRetail
	if playerClass == 'DRUID' then
		conditions.bear = '[bonusbar:3]'
		conditions.prowl = '[bonusbar:1,stealth]'
		conditions.cat = '[bonusbar:1]'
		if modern or SUI.IsMOP then
			conditions.moonkin = '[bonusbar:4]'
		end
	elseif playerClass == 'ROGUE' then
		if modern then
			conditions.shadowdance = '[bonusbar:1,form:2]'
		elseif SUI.IsWrath or SUI.IsCata then
			conditions.shadowdance = '[bonusbar:2]'
		end
		conditions.stealth = '[bonusbar:1]'
	elseif playerClass == 'EVOKER' then
		conditions.soar = '[bonusbar:1]'
	elseif playerClass == 'PRIEST' then
		if SUI.IsMOP then
			conditions.shadowform = '[bonusbar:1]'
		elseif not modern then
			conditions.shadowform = '[form:1]'
		end
	elseif playerClass == 'WARLOCK' and SUI.IsCata then
		conditions.metamorphosis = '[form:1]'
	end
	if modern then
		conditions.dragonriding = '[bonusbar:5]'
	end
	return conditions
end

-- Class states Dominos resolves from the form's spell at runtime
local FORM_SPELLS = {
	WARRIOR = { battle = { 2457, 386164 }, defensive = { 71, 386208 }, berserker = { 2458 } },
	DRUID = { moonkin = { 24858 }, tree = { 33891, 114282 }, travel = { 783 }, aquatic = { 1066 }, flight = { 33943, 40120 }, stag = { 210053 }, treant = { 114282 } },
	PRIEST = { shadowform = { 232698 } },
	MONK = { ox = { 115069 }, tiger = { 103985 }, serpent = { 115070 } },
	WARLOCK = { metamorphosis = { 103958 } },
}

---@param stateID string
---@return string|nil
local function ResolveFormCondition(stateID)
	local spells = FORM_SPELLS[playerClass] and FORM_SPELLS[playerClass][stateID]
	if not spells then
		return nil
	end
	for i = 1, GetNumShapeshiftForms() or 0 do
		local _, _, _, spellID = GetShapeshiftFormInfo(i)
		if not SUI.BlizzAPI.canaccessvalue(spellID) then
			return nil
		end
		for _, wanted in ipairs(spells) do
			if spellID == wanted then
				return ('[form:%d]'):format(i)
			end
		end
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- Data access
----------------------------------------------------------------------------------------------------

---@return table|nil
local function GetDominos()
	return LibStub('AceAddon-3.0'):GetAddon('Dominos', true)
end

function importer:IsAvailable()
	if not GetDominos() or type(_G.DominosDB) ~= 'table' then
		return false, L['Turn on Dominos and reload to import its settings. SpartanUI turns it off again when the import finishes.']
	end
	return true
end

function importer:GetProfiles()
	local list = {}
	for name in pairs(_G.DominosDB.profiles or {}) do
		list[#list + 1] = name
	end
	table.sort(list)
	return list
end

function importer:GetCurrentProfile()
	local Dominos = GetDominos()
	return Dominos and Dominos.db and Dominos.db:GetCurrentProfile() or nil
end

---The Blizzard action page a Dominos bar index shows (slots 133-144 are skipped).
---@param index number
---@return number
local function DominosBarToPage(index)
	return index <= 11 and index or index + 1
end

---@param sets table
---@return string
local function ConvertShowStates(sets)
	local prefix = ''
	if HAS_PETBATTLE and not sets.showInPetBattleUI then
		prefix = '[petbattle] hide; '
	end
	local states = sets.showstates
	if type(states) ~= 'string' or states:gsub('%s', '') == '' then
		return prefix .. 'show'
	end
	-- Opacity values become show, 0 becomes hide
	states = states:gsub('%]%s*(%d+)', function(value)
		return tonumber(value) == 0 and '] hide' or '] show'
	end)
	if states:match('%]%s*$') then
		states = states .. ' show; hide'
	end
	-- Dominos hides the bar when no rule matches; say so explicitly
	local hasFallback = false
	for clause in states:gmatch('[^;]+') do
		if not clause:find('%[') and clause:gsub('%s', '') ~= '' then
			hasFallback = true
		end
	end
	if not hasFallback then
		states = states:gsub(';?%s*$', '') .. '; hide'
	end
	return prefix .. states
end

---Layout and fading shared by every Dominos frame.
---@param sets table
---@param buttonCount number
---@return table settings
---@return number scale
---@return SUI.ActionBars.ImportPosition position
local function ConvertFrame(sets, buttonCount)
	local alpha = tonumber(sets.alpha) or 1
	local fadeAlpha = tonumber(sets.fadeAlpha) or 1
	local scale = tonumber(sets.scale) or 1
	local settings = {
		enabled = not sets.hidden,
		buttonsPerRow = math.max(1, tonumber(sets.columns) or buttonCount),
		buttonSpacing = tonumber(sets.spacing) or 0,
		backdropSpacing = tonumber(sets.padW) or 0,
		point = (sets.isBottomToTop and 'BOTTOM' or 'TOP') .. (sets.isRightToLeft and 'RIGHT' or 'LEFT'),
		alpha = alpha,
		mouseover = fadeAlpha < 1,
		mouseoverAlpha = alpha * fadeAlpha,
		clickThrough = sets.clickThrough and true or false,
		frameStrata = sets.displayLayer,
		frameLevel = sets.displayLevel,
		visibility = ConvertShowStates(sets),
	}
	local point = sets.point or 'CENTER'
	local position = {
		point = point,
		anchor = UIParent,
		relativePoint = sets.relPoint or point,
		-- Dominos stores offsets in the frame's own scaled units
		x = (tonumber(sets.x) or 0) * scale,
		y = (tonumber(sets.y) or 0) * scale,
	}
	return settings, scale, position
end

---@param pages table
---@param barIndex number
---@param barCount number
---@return string rules
local function ConvertPages(pages, barIndex, barCount)
	local function target(offset)
		local index = ((barIndex + offset - 1) % barCount) + 1
		return DominosBarToPage(index)
	end
	local rules = ''
	local function add(condition, offset)
		if condition and tonumber(offset) then
			rules = rules .. ('%s %d; '):format(condition, target(offset))
		end
	end

	for _, pair in ipairs(MODIFIER_STATES) do
		add(pair[2], pages[pair[1]])
	end
	for n = 2, 6 do
		add(('[bar:%d]'):format(n), pages['page' .. n])
	end
	local classConditions = GetClassConditions()
	for stateID, offset in pairs(pages) do
		local condition = classConditions[stateID] or ResolveFormCondition(stateID)
		if condition then
			add(condition, offset)
		end
	end
	if playerRace == 'NightElf' then
		add('[stealth]', pages.shadowmeld)
	end
	for _, pair in ipairs(TARGET_STATES) do
		add(pair[2], pages[pair[1]])
	end
	return rules
end

---@param profile string
---@return SUI.ActionBars.ImportResult
function importer:Build(profile)
	local result = module:NewImportResult()
	local Dominos = GetDominos()
	local defaults = Dominos and Dominos.db and Dominos.db.defaults and Dominos.db.defaults.profile
	local data = module:MergeWithDefaults(defaults, _G.DominosDB.profiles[profile])
	local frames = type(data.frames) == 'table' and data.frames or {}

	local barCount = tonumber(data.ab and data.ab.count) or 14
	local barLength = math.floor(168 / barCount)
	if barLength ~= 12 then
		table.insert(result.notes, L['Dominos import: your bars use a custom button count, so actions may sit on different bars after importing.'])
	end

	local function flag(sets, key)
		if sets[key] ~= nil then
			return sets[key] and true or false
		end
		return data[key] ~= false
	end

	for index = 1, barCount do
		local sets = frames[index]
		local nativeID = DominosBarToPage(index)
		if type(sets) == 'table' and module.CurrentSettings.bars[nativeID] then
			local buttons = math.max(1, math.min(tonumber(sets.numButtons) or 12, 12))
			local settings, scale, position = ConvertFrame(sets, buttons)
			settings.buttons = buttons
			if sets.showEmptyButtons ~= nil then
				settings.showGrid = sets.showEmptyButtons and true or false
			else
				settings.showGrid = data.showEmptyButtons and true or false
			end
			settings.hotkeyText = flag(sets, 'showBindingText')
			settings.macroText = flag(sets, 'showMacroText')
			settings.countText = flag(sets, 'showCounts')
			settings.showEquipped = flag(sets, 'showEquippedItemBorders')
			if type(sets.flyoutDirection) == 'string' and sets.flyoutDirection ~= 'auto' then
				settings.flyoutDirection = sets.flyoutDirection
			else
				settings.flyoutDirection = 'AUTOMATIC'
			end
			local pages = type(sets.pages) == 'table' and sets.pages[playerClass]
			if type(pages) == 'table' and next(pages) then
				local rules = ConvertPages(pages, index, barCount)
				settings.pagingEnabled = true
				if rules ~= '' then
					settings.paging = { [playerClass] = rules }
				end
			end
			result.settings.bars[nativeID] = settings
			result.scales['BT4Bar' .. nativeID] = scale
			result.positions['BT4Bar' .. nativeID] = position
		elseif type(sets) == 'table' and not sets.hidden then
			table.insert(result.notes, (L['Dominos import: bar %d has no matching SpartanUI bar and was skipped.']):format(index))
		end
	end

	local function importFrame(frameID, key, settingsKey, buttonCount, extra)
		local sets = frames[frameID]
		if type(sets) ~= 'table' then
			return
		end
		local settings, scale, position = ConvertFrame(sets, buttonCount)
		for k, v in pairs(extra or {}) do
			settings[k] = v
		end
		result.settings[settingsKey] = settings
		result.scales[key] = scale
		result.positions[key] = position
	end

	importFrame('pet', 'BT4BarPetBar', 'pet', 10, { hotkeyText = frames.pet and frames.pet.showBindingText ~= false })
	importFrame('class', 'BT4BarStanceBar', 'stance', math.max(GetNumShapeshiftForms() or 0, 1))
	local microBar = module.bars.BT4BarMicroMenu
	importFrame('menu', 'BT4BarMicroMenu', 'micro', microBar and #microBar.buttons > 0 and #microBar.buttons or 12)
	local bags = frames.bags
	importFrame('bags', 'BT4BarBagBar', 'bags', bags and bags.oneBag and 1 or 5, {
		onlyBackpack = bags and bags.oneBag and true or false,
		showKeyring = bags and bags.keyRing and true or false,
	})

	-- Button behavior
	result.settings.rightClickSelfCast = data.ab and data.ab.rightClickUnit == 'player' or false
	if data.showTooltips == false then
		result.settings.tooltip = 'disabled'
	elseif data.showTooltipsCombat == false then
		result.settings.tooltip = 'nocombat'
	end

	-- Bars without a Blizzard binding used Dominos' own buttons
	if barLength == 12 then
		for _, page in ipairs({ 2, 7, 8, 9, 10 }) do
			for i = 1, 12 do
				local slot = (page - 1) * 12 + i
				result.bindings[('CLICK DominosActionButton%d:HOTKEY'):format(slot)] = ('CLICK %s:Keybind'):format(module:GetActionButtonName(page, i))
			end
		end
	end

	return result
end

function importer:DisableSource()
	C_AddOns.DisableAddOn('Dominos', UnitName('player'))
end

module:RegisterImporter(importer)
