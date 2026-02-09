local UF = SUI.UF

-- Helper for spell info (uses unified C_Spell API available in all current versions)
local function GetSpellInfoCompat(spellInput)
	return C_Spell.GetSpellInfo(spellInput)
end

-- Helper for spellbook check (retail vs classic API)
local function IsSpellInSpellBookCompat(spellID)
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		return C_SpellBook.IsSpellKnown(spellID)
	elseif C_SpellBook.IsSpellKnown then
		return C_SpellBook.IsSpellKnown(spellID)
	end
	return false
end

---@param frame table
---@param DB table
local function Build(frame, DB)
	local element = CreateFrame('Frame', '$parent_AuraWatch', frame)
	element:SetAllPoints(frame)
	element.DB = DB

	-- Initialize watched table from DB (required by oUF_AuraWatch)
	-- oUF_AuraWatch Enable function sets element.watched = element.watched or {}
	-- so we must set it before oUF enables the element
	element.watched = DB.watched or GetDefaultWatched()
	element.size = DB.size or 20

	element.PostUpdateIcon = function(_, unit, button, index, position, duration, expiration, debuffType, isStealable)
		if not button.spellID then
			return
		end
		local settings = button.setting
		if not settings then
			return
		end
		local SpellKnown = IsSpellInSpellBookCompat(button.spellID)
		if settings.onlyIfCastable and not SpellKnown then
			button:Hide()
		end
		if InCombatLockdown() and not settings.displayInCombat then
			button:Hide()
		end
	end
	frame.AuraWatch = element
end

---@param frame table
---@param data? table
local function Update(frame, data)
	local element = frame.AuraWatch
	if not element then
		return
	end
	local DB = data or element.DB
	if not DB then
		return
	end
	element.DB = DB
	element.size = DB.size or 20
	element.watched = DB.watched or element.watched or GetDefaultWatched()

	-- Force oUF to update
	if element.ForceUpdate then
		element:ForceUpdate()
	end
end

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
---@param DB? table
local function Options(unitName, OptionSet, DB)
	local L = SUI.L
	local ElementSettings = UF.CurrentSettings[unitName].elements.AuraWatch
	local UserSetting = UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.AuraWatch

	-- Remove Basic Filters (not used by AuraWatch)
	OptionSet.args.Filters = nil
	OptionSet.args.whitelist = nil
	OptionSet.args.blacklist = nil
	OptionSet.args.Layout = nil

	local buildSpellList

	-- Create a spell label entry
	local function createSpellLabel(spellID)
		return {
			type = 'description',
			width = 'double',
			fontSize = 'medium',
			order = spellID,
			name = function()
				local spellInfo = GetSpellInfoCompat(spellID)
				if spellInfo then
					return string.format('|T%s:14:14:0:0|t %s (#%i)', spellInfo.iconID or 'Interface\\Icons\\Inv_misc_questionmark', spellInfo.name or L['Unknown'], spellID)
				end
				return string.format('Unknown Spell (#%i)', spellID)
			end,
		}
	end

	-- Create a delete button for a spell
	local function createDeleteButton(spellID)
		return {
			type = 'execute',
			name = L['Delete'],
			width = 'half',
			order = spellID + 0.5,
			func = function()
				-- Remove from settings
				ElementSettings.watched[spellID] = nil
				if UserSetting.watched then
					UserSetting.watched[spellID] = nil
				end

				-- Rebuild list and update
				buildSpellList()
				UF.Unit[unitName]:ElementUpdate('AuraWatch')
			end,
		}
	end

	-- Build the spell list for the options UI
	buildSpellList = function()
		local spellsOpt = OptionSet.args.watched.args.spells.args
		table.wipe(spellsOpt)

		-- Add each watched spell (skip the '**' defaults key)
		for spellID, _ in pairs(ElementSettings.watched or {}) do
			if type(spellID) == 'number' then
				spellsOpt['label' .. spellID] = createSpellLabel(spellID)
				spellsOpt[tostring(spellID)] = createDeleteButton(spellID)
			end
		end
	end

	-- Add a new spell to watch
	local function addSpell(_, input)
		local spellId
		if type(input) == 'string' then
			-- Try to parse spell link
			if input:find('|Hspell:%d+') then
				spellId = tonumber(input:match('|Hspell:(%d+)'))
			elseif input:find('%[(.-)%]') then
				local spellInfo = GetSpellInfoCompat(input:match('%[(.-)%]'))
				spellId = spellInfo and spellInfo.spellID
			else
				-- Try as spell name or ID
				local numericId = tonumber(input)
				if numericId then
					spellId = numericId
				else
					local spellInfo = GetSpellInfoCompat(input)
					spellId = spellInfo and spellInfo.spellID
				end
			end

			if not spellId then
				SUI:Print(L['Invalid spell name or ID'])
				return
			end
		end

		-- Add to settings (uses '**' defaults)
		ElementSettings.watched[spellId] = {}
		if not UserSetting.watched then
			UserSetting.watched = {}
		end
		UserSetting.watched[spellId] = {}

		-- Update UI
		buildSpellList()
		UF.Unit[unitName]:ElementUpdate('AuraWatch')
	end

	OptionSet.args.watched = {
		name = L['Tracked Auras'],
		type = 'group',
		order = 4,
		args = {
			desc = {
				type = 'description',
				name = L['Track important buffs and debuffs on party/raid members. Auras are auto-populated based on your class. Add custom spells using spell name or ID below.'],
				order = 0.5,
			},
			create = {
				name = L['Add spell name or ID'],
				type = 'input',
				order = 1,
				width = 'full',
				set = addSpell,
			},
			spells = {
				order = 2,
				type = 'group',
				inline = true,
				name = L['Tracked Auras'],
				args = {},
			},
		},
	}

	-- Build initial spell list
	buildSpellList()
end

---@class SUI.UF.Unit.Settings.AuraWatch.Watched
---@field anyUnit? boolean
---@field onlyShowMissing? boolean
---@field onlyIfCastable? boolean
---@field displayInCombat? boolean
---@field point? string
---@field xOffset? number
---@field yOffset? number

---@class SUI.UF.Unit.Settings.AuraWatch : SUI.UF.Unit.Settings
---@field watched table<integer|string, SUI.UF.Unit.Settings.AuraWatch.Watched>
---@field size number

-- Get default watched spells (class-aware if AuraWatchSpells is loaded)
local function GetDefaultWatched()
	-- Use class-specific spells if the data file is loaded
	if UF.AuraWatchSpells and UF.AuraWatchSpells.GetDefaults then
		return UF.AuraWatchSpells:GetDefaults()
	end

	-- Fallback: empty watched list with onlyIfCastable = true
	-- This ensures users only see missing buffs they can actually cast
	return {
		['**'] = { onlyIfCastable = true, anyUnit = true, onlyShowMissing = true, point = 'CENTER', xOffset = 0, yOffset = 0, displayInCombat = false },
	}
end

---@class SUI.UF.Unit.Settings.AuraWatch
local Settings = {
	size = 20,
	watched = GetDefaultWatched(),
	config = {
		type = 'Auras',
	},
}

UF.Elements:Register('AuraWatch', Build, Update, Options, Settings)
