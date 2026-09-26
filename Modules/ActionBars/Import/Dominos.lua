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
	{ 'alt', '[mod:alt]' },
	{ 'ctrl', '[mod:ctrl]' },
	{ 'shift', '[mod:shift]' },
	{ 'meta', '[mod:meta]' },
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
	elseif playerClass == 'WARLOCK' and (SUI.IsCata or SUI.IsWrath) then
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
-- Set while a profile is converted: Dominos hides its bars under Blizzard's vehicle bar
local usingOverrideUI = false

local function ConvertShowStates(sets, hideConditions)
	local prefix = hideConditions or ''
	if usingOverrideUI and not sets.showInOverrideUI then
		prefix = prefix .. '[overridebar] hide; '
	end
	if HAS_PETBATTLE and not sets.showInPetBattleUI then
		prefix = prefix .. '[petbattle] hide; '
	end
	local states = sets.showstates
	if type(states) ~= 'string' or states:gsub('%s', '') == '' then
		return prefix .. 'show'
	end
	-- Dominos appends show;hide to a rule set ending in a bare condition
	if states:match('%]%s*$') then
		states = states .. 'show;hide'
	end
	-- Each clause ends in show, hide or an opacity from 0 to 100; opacity 0 hides
	local clauses = {}
	for clause in states:gmatch('[^;]+') do
		local conditions, result = clause:match('^%s*(.-)%s*([%w]+)%s*$')
		if result then
			local value = tonumber(result)
			if value then
				result = value == 0 and 'hide' or 'show'
			end
			clauses[#clauses + 1] = (conditions ~= '' and (conditions .. ' ') or '') .. result
		end
	end
	-- With nothing matching, Dominos keeps the bar shown
	local last = clauses[#clauses]
	if not last or last:find('%[') then
		clauses[#clauses + 1] = 'show'
	end
	return prefix .. table.concat(clauses, '; ')
end

---Layout and fading shared by every Dominos frame.
---@param sets table
---@param buttonCount number
---@return table settings
---@return number scale
---@return SUI.ActionBars.ImportPosition position
local function ConvertFrame(sets, buttonCount, hideConditions)
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
		visibility = ConvertShowStates(sets, hideConditions),
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
-- Fallback order for class states when Dominos' own list is unavailable: stealthed and
-- combined states must come before the plain form they share a bonus bar with
local CLASS_STATE_ORDER = {
	'dragonriding',
	'bear',
	'prowl',
	'cat',
	'moonkin',
	'tree',
	'travel',
	'aquatic',
	'flight',
	'stag',
	'treant',
	'soar',
	'shadowform',
	'shadowdance',
	'stealth',
	'metamorphosis',
	'battle',
	'defensive',
	'berserker',
	'ox',
	'tiger',
	'serpent',
}

local STATE_PRECEDENCE = { 'modifier', 'page', 'class', 'race', 'target' }

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

	-- Dominos is loaded during an import, so its own state list gives the exact conditions
	-- and order it used for this character (forms resolved, per game version)
	local Dominos = GetDominos()
	local BarStates = Dominos and Dominos.BarStates
	if BarStates and BarStates.GetAll then
		for _, stateType in ipairs(STATE_PRECEDENCE) do
			for _, state in BarStates:GetAll(stateType) do
				local offset = pages[state.id]
				if offset then
					local condition = state.value
					if type(condition) == 'function' then
						condition = condition(state)
					end
					add(condition, offset)
				end
			end
		end
		return rules
	end

	for _, pair in ipairs(MODIFIER_STATES) do
		add(pair[2], pages[pair[1]])
	end
	for n = 2, 6 do
		add(('[bar:%d]'):format(n), pages['page' .. n])
	end
	local classConditions = GetClassConditions()
	for _, stateID in ipairs(CLASS_STATE_ORDER) do
		if pages[stateID] then
			add(classConditions[stateID] or ResolveFormCondition(stateID), pages[stateID])
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
	usingOverrideUI = data.useOverrideUI and true or false
	local frames = type(data.frames) == 'table' and data.frames or {}

	local barCount = tonumber(data.ab and data.ab.count) or 14
	local barLength = math.floor(168 / barCount)
	if barLength ~= 12 then
		table.insert(result.notes, L['Dominos import: your bars use a custom button count, so actions may sit on different bars after importing.'])
	end

	local isCurrent = self:GetCurrentProfile() == profile
	---Docked bars follow the bar they are stuck to, so their stored position can be stale.
	---While Dominos is running, its frames show where everything really is.
	local function LivePosition(frameID, position)
		local frame = isCurrent and _G['DominosFrame' .. frameID]
		if frame and frame.GetLeft and frame:GetLeft() then
			local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
			return { point = 'BOTTOMLEFT', anchor = UIParent, relativePoint = 'BOTTOMLEFT', x = frame:GetLeft() * ratio, y = frame:GetBottom() * ratio }
		end
		return position
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
			-- Dominos' page rules include its own Shift+number pages and replace the class
			-- defaults outright; bar 1 without any stored rules keeps SpartanUI's defaults
			local pages = type(sets.pages) == 'table' and sets.pages[playerClass]
			if type(pages) == 'table' then
				local rules = ConvertPages(pages, index, barCount)
				settings.pagingEnabled = rules ~= ''
				settings.manualPaging = false
				settings.defaultClassPaging = false
				if rules ~= '' then
					settings.paging = { [playerClass] = rules }
				end
			end
			settings.vehiclePaging = index == (tonumber(data.possessBar) or 1)
			result.settings.bars[nativeID] = settings
			result.scales['BT4Bar' .. nativeID] = scale
			result.positions['BT4Bar' .. nativeID] = LivePosition(index, position)
		elseif type(sets) == 'table' and not sets.hidden then
			table.insert(result.notes, (L['Dominos import: bar %d has no matching SpartanUI bar and was skipped.']):format(index))
		end
	end

	local function importFrame(frameID, key, settingsKey, buttonCount, extra, hideConditions)
		local sets = frames[frameID]
		if type(sets) ~= 'table' then
			return
		end
		local settings, scale, position = ConvertFrame(sets, buttonCount, hideConditions)
		for k, v in pairs(extra or {}) do
			settings[k] = v
		end
		result.settings[settingsKey] = settings
		result.scales[key] = scale
		result.positions[key] = LivePosition(frameID, position)
	end

	-- Dominos always adds its own pet condition on top of the player's rules
	local petHide = '[nopet][possessbar][overridebar] hide; '
	if SUI.IsRetail or SUI.IsMOP or SUI.IsCata or SUI.IsWrath or SUI.IsForever then
		petHide = '[nopet][possessbar][overridebar][vehicleui] hide; '
	elseif data.possessBar == 'pet' then
		-- Dominos shows mind control abilities on the pet bar here
		petHide = '[nopet,nobonusbar:5] hide; '
	end
	importFrame('pet', 'BT4BarPetBar', 'pet', 10, { hotkeyText = flag(frames.pet or {}, 'showBindingText') }, petHide)
	importFrame('class', 'BT4BarStanceBar', 'stance', math.max(GetNumShapeshiftForms() or 0, 1), { hotkeyText = flag(frames.class or {}, 'showBindingText') })
	importFrame('menu', 'BT4BarMicroMenu', 'micro', module:CountMicroButtons())
	local bags = frames.bags or {}
	local bagSettings = {
		onlyBackpack = bags.oneBag and true or false,
		-- Dominos' one-bag mode shows the backpack alone
		showReagentBag = not bags.oneBag,
		showKeyring = bags.keyRing and true or false,
	}
	importFrame('bags', 'BT4BarBagBar', 'bags', module:CountBagButtons(bagSettings), bagSettings)

	-- Dominos' override setting decides whether Blizzard's vehicle bar is used
	if data.useOverrideUI ~= nil then
		result.vehicleUI = data.useOverrideUI and true or false
	end
	if data.possessBar ~= nil and data.possessBar ~= 'pet' and tonumber(data.possessBar) ~= 1 then
		table.insert(result.notes, L['Dominos import: vehicle and possess actions now show on the bar you picked in Dominos only if it maps to a SpartanUI bar.'])
	end

	-- Button behavior
	result.settings.rightClickSelfCast = data.ab and data.ab.rightClickUnit == 'player' or false
	if data.showTooltips == false then
		result.settings.tooltip = 'disabled'
	elseif data.showTooltipsCombat == false then
		result.settings.tooltip = 'nocombat'
	end

	-- Bars without a Blizzard binding used Dominos' own buttons, and on some game versions
	-- so did Dominos' last three bars (SpartanUI bars 13-15)
	if barLength == 12 then
		local pages = { 2, 7, 8, 9, 10 }
		if module.CurrentSettings.bars[13] and _G.MultiBar5 then
			for page = 13, 15 do
				pages[#pages + 1] = page
			end
		end
		for _, page in ipairs(pages) do
			-- Dominos bars 12-14 hold pages 13-15, one slot block earlier
			local first = page > 12 and (page - 2) * 12 or (page - 1) * 12
			for i = 1, 12 do
				result.bindings[('CLICK DominosActionButton%d:HOTKEY'):format(first + i)] = module:GetActionButtonBinding(page, i)
			end
		end
	end

	return result
end

function importer:DisableSource()
	C_AddOns.DisableAddOn('Dominos', UnitName('player'))
end

module:RegisterImporter(importer)
