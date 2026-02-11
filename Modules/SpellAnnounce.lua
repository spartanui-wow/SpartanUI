---@class SUI
local SUI = SUI
local module = SUI:NewModule('SpellAnnounce') ---@type SUI.Module
module.DisplayName = 'Spell announce'
module.description = 'Announce spells cast by players'

---@class SpellAnnounceDB
local DBDefaults = {
	AnnounceSets = {
		['**'] = {
			enabled = false,
			whoToAnnounce = 'self',
			announceLocation = 'auto',
			activeLocation = {
				always = false,
				inBG = false,
				inRaid = true,
				inParty = true,
				inArena = true,
				outdoors = false,
			},
			SpellList = {},
		},
		-- Interrupts = {
		-- 	enabled = true,
		-- 	text = 'Interrupted %t %spell',
		-- 	SpellList = {}
		-- },
		Taunts = {
			enabled = true,
			announceLocation = 'self',
			text = '%who taunted %what!',
			SpellList = {
				--Warrior
				355, --Taunt
				--Death Knight
				51399, --Death Grip for Blood (49576 is now just the pull effect)
				56222, --Dark Command
				--Paladin
				62124, --Hand of Reckoning
				--Druid
				6795, --Growl
				--Hunter
				20736, --Distracting Shot
				--Monk
				115546, --Provoke
				--Demon Hunter
				185245, --Torment
				--Paladin
				204079, --Final Stand
			},
		},
		Portals = {
			enabled = true,
			text = '%who is ripping a hole in space time to cast %spell!',
			SpellList = {},
		},
	},
}

local function SetupPage() end

local function Options()
	---@type AceConfig.OptionsTable
	local OptTable = {
		name = 'Spell announce',
		type = 'group',
		args = {},
	}

	SUI.Options:AddOptions(OptTable, 'SpellAnnounce', nil)
end

function module:OnInitialize()
	module.Database = SUI.SpartanUIDB:RegisterNamespace('SpellAnnounce', { profile = DBDefaults })
	module.DB = module.Database.profile

	-- Register profile change callbacks
	SUI.DBM:RegisterSequentialProfileRefresh(module)

	if SUI:IsModuleDisabled(module) then
		return
	end
end

function module:OnEnable()
	Options()
	if SUI:IsModuleDisabled(module) then
		return
	end
end

function module:OnDisable() end
