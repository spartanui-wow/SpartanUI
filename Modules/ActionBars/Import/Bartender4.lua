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

	-- Text elements share a wildcard default (font, flags, justify) that CopyDefaults drops
	local shared = defaults['**'] and defaults['**'].elements and defaults['**'].elements['**']
	if type(shared) == 'table' then
		config.elements = config.elements or {}
		for _, name in ipairs({ 'hotkey', 'count', 'macro' }) do
			config.elements[name] = SUI:MergeData(CopyDefaults(shared), config.elements[name], true)
		end
	end
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

-- Every class token, so a shared profile's page rules carry over for all of them
local ALL_CLASSES = {}
for token in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do
	ALL_CLASSES[#ALL_CLASSES + 1] = token
end

---Build page-swap rules for one class from Bartender4's state settings, in Bartender4's order.
---Vehicle paging is a separate SpartanUI setting and is not part of the rules.
---@param states table
---@param class string
---@return string rules Empty when the bar has no swaps for this class
local function ConvertStates(states, class)
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
	-- Shift+number pages come after modifiers and before forms, as in Bartender4
	if states.actionbar then
		for page = 2, 6 do
			rules = rules .. ('[bar:%d] %d; '):format(page, page)
		end
	end
	local stances = type(states.stance) == 'table' and states.stance[class]
	local map = STANCE_BONUSBARS[class]
	if type(stances) == 'table' and map then
		-- Prowl shares cat form's bonus bar and has to come first to ever match
		local prowl = tonumber(stances.prowl)
		if class == 'DRUID' and prowl and prowl > 0 then
			rules = rules .. ('[bonusbar:1,stealth:1] %d; '):format(prowl)
		end
		local ordered = {}
		for stanceID, bonusbar in pairs(map) do
			ordered[#ordered + 1] = { stanceID, bonusbar }
		end
		table.sort(ordered, function(a, b)
			return a[2] < b[2]
		end)
		for _, entry in ipairs(ordered) do
			local page = tonumber(stances[entry[1]])
			if page and page > 0 then
				rules = rules .. ('[bonusbar:%d] %d; '):format(entry[2], page)
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
		fadeOutDelay = config.fadeout and (tonumber(config.fadeoutdelay) or 0.2) or nil,
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

---@param a table
---@param b table|nil
---@return boolean
local function SameText(a, b)
	if not b then
		return false
	end
	for _, element in ipairs({ 'hotkey', 'count', 'macro' }) do
		local x, y = a[element] or {}, b[element] or {}
		for _, key in ipairs({ 'face', 'size', 'flags', 'anchor', 'x', 'y' }) do
			if x[key] ~= y[key] then
				return false
			end
		end
		local cx, cy = x.color, y.color
		if (cx == nil) ~= (cy == nil) or (cx and (cx[1] ~= cy[1] or cx[2] ~= cy[2] or cx[3] ~= cy[3])) then
			return false
		end
	end
	return true
end

---@param profile string
---@return SUI.ActionBars.ImportResult
function importer:Build(profile)
	local result = module:NewImportResult()
	local core = module:MergeWithDefaults(CopyDefaults(_G.Bartender4.db.defaults and _G.Bartender4.db.defaults.profile), _G.Bartender4DB.profiles[profile])

	-- While SpartanUI ran Bartender4 it placed and scaled every bar itself, whatever the
	-- profile was called, and those placements carry over through the shared mover names.
	-- Bartender4's own stored positions were never what was on screen.
	local barSystem = SUI.Handlers.BarSystem
	local spartanProfile = profile:find('^SpartanUI') ~= nil or (barSystem and barSystem.DB and barSystem.DB.BT4Initalized) or false

	local function addBar(key, settingsKey, settings, scale, position)
		if settingsKey then
			result.settings[settingsKey] = settings
		end
		if not spartanProfile then
			result.scales[key] = scale
			result.positions[key] = position
		end
	end

	local smartTargeting = false
	local sharedText
	for _, id in ipairs(module.ACTION_BAR_IDS) do
		local config = GetActionBarConfig(profile, id)
		local buttons = math.max(1, math.min(tonumber(config.buttons) or 12, 12))
		local settings, scale, position = ConvertBar(config, buttons, SUI.IsRetail)
		settings.buttons = buttons
		settings.showGrid = config.showgrid and true or false
		settings.flyoutDirection = config.flyoutDirection
		settings.hotkeyText = not config.hidehotkey
		settings.macroText = not config.hidemacrotext
		settings.showEquipped = not config.hideequipped
		settings.buttonOffset = math.max(0, math.min(tonumber(config.buttonOffset) or 0, 11))
		local states = type(config.states) == 'table' and config.states or {}
		settings.vehiclePaging = states.possess and true or false
		-- Shift+number pages are part of the converted rules, where Bartender4 checks them
		settings.manualPaging = false
		settings.pagingEnabled = states.enabled and true or false
		-- Bartender4's own stance pages replace SpartanUI's class defaults exactly
		settings.defaultClassPaging = false
		if states.enabled then
			local paging = {}
			for _, class in ipairs(ALL_CLASSES) do
				local rules = ConvertStates(states, class)
				if rules ~= '' then
					paging[class] = rules
				end
			end
			settings.paging = paging
		end
		if config.mouseover or config.autoassist then
			smartTargeting = true
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
			sharedText = text
		elseif not SameText(text, sharedText) then
			-- Bars whose fonts differ from bar 1 keep their own text style
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
		local settings, scale, position = ConvertBar(micro, module:CountMicroButtons(), false)
		-- Bartender4 steps micro buttons 32px apart (8px closer on modern clients) whatever
		-- their real width; SpartanUI spaces them from their real width
		local nativeWidth = CharacterMicroButton and CharacterMicroButton:GetWidth() or 32
		settings.buttonSpacing = math.floor(32 + (tonumber(micro.padding) or 1) + (SUI.IsRetail and -8 or 0) - nativeWidth + 0.5)
		settings.backdropSpacing = nil
		addBar('BT4BarMicroMenu', 'micro', settings, scale, position)
	end

	local bags = GetModuleData('BagBar', profile)
	if bags then
		local bagSettings = {
			onlyBackpack = bags.onebag and true or false,
			showReagentBag = not bags.onebag or bags.onebagreagents ~= false,
			showKeyring = bags.keyring ~= false,
		}
		local settings, scale, position = ConvertBar(bags, module:CountBagButtons(bagSettings), false)
		for k, v in pairs(bagSettings) do
			settings[k] = v
		end
		settings.backdropSpacing = nil
		addBar('BT4BarBagBar', 'bags', settings, scale, position)
	end

	-- Button behavior
	result.settings.tooltip = core.tooltip
	result.settings.lockButtons = core.buttonlock ~= false
	result.settings.outOfRangeColoring = core.outofrange
	result.settings.rightClickSelfCast = core.selfcastrightclick and true or false
	result.settings.checkSelfCast = core.selfcastmodifier ~= false
	result.settings.checkFocusCast = core.focuscastmodifier ~= false
	result.settings.spellCastVFX = core.spellCastVFX ~= false
	result.settings.hideBorder = GetActionBarConfig(profile, 1).hideborder and true or false
	if not spartanProfile and core.blizzardVehicle ~= nil then
		result.vehicleUI = core.blizzardVehicle and true or false
	end
	if type(core.colors) == 'table' then
		result.settings.colors = {
			range = module:ResolveColor(core.colors.range) or module.DBDefaults.colors.range,
			mana = module:ResolveColor(core.colors.mana) or module.DBDefaults.colors.mana,
			usable = module.DBDefaults.colors.usable,
			notUsable = module.DBDefaults.colors.notUsable,
		}
	end

	-- Every Bartender4 button has its own click binding, and players bind those directly
	for _, id in ipairs(module.ACTION_BAR_IDS) do
		for i = 1, 12 do
			local command = module:GetActionButtonBinding(id, i)
			local abs = (id - 1) * 12 + i
			result.bindings[('CLICK BT4Button%d:Keybind'):format(abs)] = command
			result.bindings[('CLICK BT4Button%d:LeftButton'):format(abs)] = command
		end
	end
	-- Pet and stance buttons are Blizzard's own in SpartanUI, bound through Blizzard's names
	for i = 1, 10 do
		result.bindings[('CLICK BT4PetButton%d:LeftButton'):format(i)] = ('BONUSACTIONBUTTON%d'):format(i)
		result.bindings[('CLICK BT4StanceButton%d:LeftButton'):format(i)] = ('SHAPESHIFTBUTTON%d'):format(i)
	end

	if smartTargeting then
		table.insert(result.notes, L["Bartender4 import: per-bar mouseover and auto-assist targeting are not carried over. Turn on the game's Mouseover Cast setting instead."])
	end

	if spartanProfile then
		table.insert(result.notes, L['Bartender4 import: this profile was set up by SpartanUI, so your current bar positions and sizes are kept.'])
	end
	return result
end

module:RegisterImporter(importer)
