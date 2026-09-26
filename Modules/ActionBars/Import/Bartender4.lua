---@type SUI
local SUI = SUI
local L = SUI.L
---@class SUI.Module.ActionBars
local module = SUI:GetModule('ActionBars')

local _, playerClass = UnitClass('player')
local HAS_PETBATTLE = SUI.IsRetail or SUI.IsMOP or SUI.IsCata

-- Bartender4 stance ids and the bonus bar each one switches to
local STANCE_BONUSBARS = {
	DRUID = { cat = 1, treeoflife = 2, bear = 3, moonkin = 4 },
	ROGUE = { stealth = 1, shadowdance = 2 },
	EVOKER = { soar = 1 },
	WARRIOR = { battle = 1, def = 2, berserker = 3 },
	PRIEST = { shadowform = 1 },
	MONK = { tiger = 1, ox = 2, serpent = 3 },
}

-- Bartender4 visibility flags and the macro condition each one hides the bar under
local VISIBILITY_CONDITIONS = {
	{ 'possess', '[possessbar]' },
	{ 'overridebar', '[overridebar]' },
	{ 'vehicleui', '[vehicleui]' },
	{ 'vehicle', '[@vehicle,exists]' },
	{ 'combat', '[combat]' },
	{ 'nocombat', '[nocombat]' },
	{ 'pet', '[pet]' },
	{ 'nopet', '[nopet]' },
	{ 'mounted', '[mounted]' },
}

---@type SUI.ActionBars.Importer
local importer = { id = 'Bartender4', name = 'Bartender4' }

function importer:IsAvailable()
	if not _G.Bartender4 or type(_G.Bartender4DB) ~= 'table' then
		return false, L['Turn on Bartender4 and reload to import its settings. SpartanUI turns it off again when the import finishes.']
	end
	return true
end

function importer:GetProfiles()
	local list = {}
	for name in pairs(_G.Bartender4DB.profiles or {}) do
		list[#list + 1] = name
	end
	table.sort(list)
	return list
end

function importer:GetCurrentProfile()
	local db = _G.Bartender4 and _G.Bartender4.db
	return db and db:GetCurrentProfile() or nil
end

---Copy a defaults table without AceDB wildcard entries.
---@param source table|nil
---@return table
local function CopyDefaults(source)
	local copy = {}
	if type(source) ~= 'table' then
		return copy
	end
	for k, v in pairs(source) do
		if k ~= '*' and k ~= '**' then
			copy[k] = type(v) == 'table' and CopyDefaults(v) or v
		end
	end
	return copy
end

---A Bartender4 module's settings for a profile, with its defaults filled back in.
---@param moduleName string
---@param profile string
---@return table|nil merged
---@return table|nil saved
local function GetModuleData(moduleName, profile)
	local bt4Module = _G.Bartender4:GetModule(moduleName, true)
	local defaults = bt4Module and bt4Module.db and bt4Module.db.defaults and bt4Module.db.defaults.profile
	local ns = _G.Bartender4DB.namespaces and _G.Bartender4DB.namespaces[moduleName]
	local saved = ns and ns.profiles and ns.profiles[profile]
	if not bt4Module and not saved then
		return nil, nil
	end
	return module:MergeWithDefaults(CopyDefaults(defaults), saved), saved
end

---Settings for one action bar: wildcard defaults, then per-bar defaults, then saved values.
---@param profile string
---@param id number
---@return table config
---@return table|nil saved
local function GetActionBarConfig(profile, id)
	local bt4Module = _G.Bartender4:GetModule('ActionBars', true)
	local defaults = bt4Module and bt4Module.db and bt4Module.db.defaults and bt4Module.db.defaults.profile.actionbars or {}
	local ns = _G.Bartender4DB.namespaces and _G.Bartender4DB.namespaces.ActionBars
	local savedBars = ns and ns.profiles and ns.profiles[profile] and ns.profiles[profile].actionbars
	local saved = savedBars and savedBars[id]

	local config = CopyDefaults(defaults['**'])
	config = SUI:MergeData(config, CopyDefaults(defaults[id]), true)
	config = SUI:MergeData(config, saved, true)
	return config, saved
end

---@param visibility table|nil
---@return string
local function ConvertVisibility(visibility)
	visibility = visibility or {}
	local prefix = HAS_PETBATTLE and '[petbattle] hide; ' or ''
	if visibility.always then
		return 'hide'
	end
	if visibility.custom and type(visibility.customdata) == 'string' and visibility.customdata:gsub('%s', '') ~= '' then
		-- SpartanUI bars have no partial fade state; faded states just show
		local custom = visibility.customdata:gsub('fade:%d+', 'show'):gsub('fade', 'show')
		return prefix .. custom
	end
	local conditions = ''
	for _, pair in ipairs(VISIBILITY_CONDITIONS) do
		if visibility[pair[1]] then
			conditions = conditions .. pair[2]
		end
	end
	if type(visibility.stance) == 'table' then
		for index, hidden in pairs(visibility.stance) do
			if hidden and tonumber(index) then
				conditions = conditions .. ('[stance:%d]'):format(index)
			end
		end
	end
	if conditions ~= '' then
		return prefix .. conditions .. ' hide; show'
	end
	return prefix .. 'show'
end

---Build page-swap rules from Bartender4's state settings.
---@param states table|nil
---@param barID number
---@return string|nil rules Nil means use SpartanUI's default for this bar
local function ConvertStates(states, barID)
	if type(states) ~= 'table' or not states.enabled then
		return nil
	end
	if states.customEnabled and type(states.custom) == 'string' and states.custom:gsub('%s', '') ~= '' then
		return states.custom
	end

	local rules = ''
	for _, mod in ipairs({ 'ctrl', 'alt', 'shift' }) do
		local page = tonumber(states[mod])
		if page and page > 0 then
			rules = rules .. ('[mod:%s] %d; '):format(mod, page)
		end
	end
	if states.actionbar and barID ~= 1 then
		rules = rules .. '[bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6; '
	end
	local stances = type(states.stance) == 'table' and states.stance[playerClass]
	local map = STANCE_BONUSBARS[playerClass]
	if type(stances) == 'table' and map then
		local prowl = tonumber(stances.prowl)
		if playerClass == 'DRUID' and prowl and prowl > 0 then
			rules = rules .. ('[bonusbar:1,stealth:1] %d; '):format(prowl)
		end
		for stanceID, bonusbar in pairs(map) do
			local page = tonumber(stances[stanceID])
			if page and page > 0 then
				rules = rules .. ('[bonusbar:%d] %d; '):format(bonusbar, page)
			end
		end
	end
	local default = tonumber(states.default)
	if default and default > 0 then
		rules = rules .. default .. ';'
	end
	return rules
end

---Layout, fading and visibility shared by every Bartender4 bar type.
---@param config table
---@param buttonCount number
---@param migrateWoW10 boolean
---@return table settings
---@return number scale
---@return table|nil position
local function ConvertBar(config, buttonCount, migrateWoW10)
	local position = config.position or {}
	local growV = position.growVertical or 'DOWN'
	local growH = position.growHorizontal or 'RIGHT'
	local rows = math.max(1, tonumber(config.rows) or 1)
	local perRow = math.ceil(buttonCount / rows)
	local padding = tonumber(config.padding) or 2
	local scale = tonumber(position.scale) or 1

	-- Bartender4 shrank classic-sized layouts when Retail buttons grew to 45px
	if migrateWoW10 and not config.WoW10Layout and position.x then
		scale = scale * 0.8
		padding = padding / 0.8
	end

	local settings = {
		enabled = config.enabled ~= false,
		buttonsPerRow = perRow,
		buttonSpacing = padding,
		backdropSpacing = 4,
		point = (growV == 'UP' and 'BOTTOM' or 'TOP') .. (growH == 'LEFT' and 'RIGHT' or 'LEFT'),
		alpha = tonumber(config.alpha) or 1,
		mouseover = config.fadeout and true or false,
		mouseoverAlpha = tonumber(config.fadeoutalpha) or 0.1,
		clickThrough = config.clickthrough and true or false,
		zoom = config.skin and config.skin.Zoom and true or false,
		visibility = ConvertVisibility(config.visibility),
	}

	local placed
	if position.x and position.y then
		-- Bartender4 anchors a 1px frame at the corner the buttons grow from
		local corner = (growV == 'UP' and 'BOTTOM' or 'TOP') .. (growH == 'BOTH' and '' or (growH == 'LEFT' and 'RIGHT' or 'LEFT'))
		placed = {
			point = corner,
			anchor = UIParent,
			relativePoint = position.point or 'CENTER',
			x = tonumber(position.x) or 0,
			y = tonumber(position.y) or 0,
		}
	end
	return settings, scale, placed
end

---@param elements table|nil
---@param name string
---@return table|nil
local function ConvertText(elements, name)
	local element = type(elements) == 'table' and elements[name]
	if type(element) ~= 'table' then
		return nil
	end
	return {
		face = module:ResolveFontName(element.font),
		size = element.fontSize,
		flags = module:ResolveFontFlags(element.fontFlags),
		color = module:ResolveColor(element.fontColor),
		anchor = element.textAnchor,
		x = element.textOffsetX,
		y = element.textOffsetY,
	}
end

---@param profile string
---@return SUI.ActionBars.ImportResult
function importer:Build(profile)
	local result = module:NewImportResult()
	local core = module:MergeWithDefaults(CopyDefaults(_G.Bartender4.db.defaults and _G.Bartender4.db.defaults.profile), _G.Bartender4DB.profiles[profile])

	-- SpartanUI placed and scaled bars itself on its own Bartender4 profiles, and those
	-- placements already carry over. Only settings come from these profiles.
	local spartanProfile = profile:find('^SpartanUI') ~= nil

	local function addBar(key, settingsKey, settings, scale, position)
		if settingsKey then
			result.settings[settingsKey] = settings
		end
		if not spartanProfile then
			result.scales[key] = scale
			result.positions[key] = position
		end
	end

	for _, id in ipairs(module.ACTION_BAR_IDS) do
		local config, saved = GetActionBarConfig(profile, id)
		local buttons = math.max(1, math.min(tonumber(config.buttons) or 12, 12))
		local settings, scale, position = ConvertBar(config, buttons, SUI.IsRetail)
		settings.buttons = buttons
		settings.showGrid = config.showgrid and true or false
		settings.flyoutDirection = config.flyoutDirection
		settings.hotkeyText = not config.hidehotkey
		settings.macroText = not config.hidemacrotext
		settings.showEquipped = not config.hideequipped
		-- Untouched page settings keep SpartanUI's own defaults for the class
		if type(saved) == 'table' and type(saved.states) == 'table' then
			local paging = ConvertStates(config.states, id)
			settings.pagingEnabled = type(config.states) == 'table' and config.states.enabled and true or false
			if paging and paging ~= '' then
				settings.paging = { [playerClass] = paging }
			end
		end
		result.settings.bars[id] = settings
		addBar('BT4Bar' .. id, nil, nil, scale, position)

		local text = {
			hotkey = ConvertText(config.elements, 'hotkey'),
			count = ConvertText(config.elements, 'count'),
			macro = ConvertText(config.elements, 'macro'),
		}
		if id == 1 then
			result.settings.text = text
		elseif type(saved) == 'table' and type(saved.elements) == 'table' then
			-- Only bars whose fonts were changed in Bartender4 get their own text style
			settings.customText = true
			settings.text = text
		end
	end

	local pet = GetModuleData('PetBar', profile)
	if pet then
		local settings, scale, position = ConvertBar(pet, 10, false)
		settings.hotkeyText = not pet.hidehotkey
		addBar('BT4BarPetBar', 'pet', settings, scale, position)
	end

	local stance = GetModuleData('StanceBar', profile)
	if stance then
		local settings, scale, position = ConvertBar(stance, math.max(GetNumShapeshiftForms() or 0, 1), false)
		settings.hotkeyText = not stance.hidehotkey
		addBar('BT4BarStanceBar', 'stance', settings, scale, position)
	end

	local micro = GetModuleData('MicroMenu', profile)
	if micro then
		local microBar = module.bars.BT4BarMicroMenu
		local count = microBar and #microBar.buttons > 0 and #microBar.buttons or 12
		local settings, scale, position = ConvertBar(micro, count, false)
		addBar('BT4BarMicroMenu', 'micro', settings, scale, position)
	end

	local bags = GetModuleData('BagBar', profile)
	if bags then
		local settings, scale, position = ConvertBar(bags, bags.onebag and 1 or 5, false)
		settings.onlyBackpack = bags.onebag and true or false
		settings.showReagentBag = not bags.onebag or bags.onebagreagents ~= false
		settings.showKeyring = bags.keyring ~= false
		addBar('BT4BarBagBar', 'bags', settings, scale, position)
	end

	-- Button behavior
	result.settings.tooltip = core.tooltip
	result.settings.lockButtons = core.buttonlock ~= false
	result.settings.outOfRangeColoring = core.outofrange
	result.settings.rightClickSelfCast = core.selfcastrightclick and true or false
	if type(core.colors) == 'table' then
		result.settings.colors = {
			range = module:ResolveColor(core.colors.range) or module.DBDefaults.colors.range,
			mana = module:ResolveColor(core.colors.mana) or module.DBDefaults.colors.mana,
		}
	end

	-- Bars without a Blizzard binding used Bartender4's own buttons
	for _, id in ipairs({ 2, 7, 8, 9, 10 }) do
		for i = 1, 12 do
			result.bindings[('CLICK BT4Button%d:Keybind'):format((id - 1) * 12 + i)] = ('CLICK %s:Keybind'):format(module:GetActionButtonName(id, i))
		end
	end

	if spartanProfile then
		table.insert(result.notes, L['Bartender4 import: this profile was set up by SpartanUI, so your current bar positions and sizes are kept.'])
	end
	return result
end

module:RegisterImporter(importer)
