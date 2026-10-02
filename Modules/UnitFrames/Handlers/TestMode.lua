---@class SUI.UF
local UF = SUI.UF
local L = SUI.L

local TestMode = {}
UF.TestMode = TestMode

local isGlobalActive = false

----------------------------------------------------------------------------------------------------
-- Mock data for varied preview appearance
----------------------------------------------------------------------------------------------------
local CLASS_LIST = { 'WARRIOR', 'PALADIN', 'HUNTER', 'ROGUE', 'PRIEST', 'DEATHKNIGHT', 'SHAMAN', 'MAGE', 'WARLOCK', 'MONK', 'DRUID', 'DEMONHUNTER', 'EVOKER' }

-- Map each class to its primary power token (used by oUF's colors.power[token])
local CLASS_POWER_TOKEN = {
	WARRIOR = 'RAGE',
	PALADIN = 'HOLY_POWER',
	HUNTER = 'FOCUS',
	ROGUE = 'ENERGY',
	PRIEST = 'MANA',
	DEATHKNIGHT = 'RUNIC_POWER',
	SHAMAN = 'MANA',
	MAGE = 'MANA',
	WARLOCK = 'SOUL_SHARDS',
	MONK = 'ENERGY',
	DRUID = 'MANA',
	DEMONHUNTER = 'FURY',
	EVOKER = 'MANA',
}

-- Mock spells for caster-type classes (name, duration, icon)
local MOCK_CASTS = {
	PRIEST = { name = 'Greater Heal', duration = 2.5, icon = 135915 },
	MAGE = { name = 'Fireball', duration = 2.0, icon = 135812 },
	WARLOCK = { name = 'Shadow Bolt', duration = 1.7, icon = 136197 },
	SHAMAN = { name = 'Lightning Bolt', duration = 1.5, icon = 136048 },
	DRUID = { name = 'Wrath', duration = 1.5, icon = 136006 },
	EVOKER = { name = 'Eternity Surge', duration = 2.5, icon = 4622468 },
	PALADIN = { name = 'Flash of Light', duration = 1.5, icon = 135907 },
}

local NAME_LIST = {
	'Arthas',
	'Jaina',
	'Thrall',
	'Sylvanas',
	'Tyrande',
	'Anduin',
	'Velen',
	'Illidan',
	'Malfurion',
	'Khadgar',
	'Genn',
	'Talanji',
	'Baine',
	"Lor'themar",
	'Alleria',
	'Turalyon',
	'Magni',
	'Mekkatorque',
	'Rokhan',
	'Calia',
	'Alexstrasza',
	'Nozdormu',
	'Wrathion',
	'Ebyssian',
	'Kalecgos',
	'Chromie',
	'Aggra',
	'Yrel',
	'Gazlowe',
	'Thalyssra',
	'Oculeth',
	'Valtrois',
	'Liadrin',
	'Sunwalker',
	'Aponi',
	'Hamuul',
	'Rehgar',
	'Saurfang',
	'Nazgrim',
	'Eitrigg',
}

-- Per-frame mock data, seeded by frame index for consistency
local mockDataCache = {}

---Generate deterministic mock data for a frame based on its index
---@param index number
---@return table mockData
local function GetMockData(index)
	if mockDataCache[index] then
		return mockDataCache[index]
	end

	local nameIdx = ((index * 7 + 3) % #NAME_LIST) + 1
	local classIdx = ((index * 11 + 5) % #CLASS_LIST) + 1
	local healthPct = 0.3 + ((index * 13 + 7) % 70) / 100
	local powerPct = 0.1 + ((index * 17 + 11) % 90) / 100

	local shieldPct = 0
	local healAbsorbPct = 0
	if index % 3 == 1 then
		shieldPct = 0.10 + ((index * 19 + 3) % 20) / 100
	end
	if index % 5 == 0 then
		healAbsorbPct = 0.10 + ((index * 23 + 7) % 20) / 100
	end

	local mockClass = CLASS_LIST[classIdx]
	mockDataCache[index] = {
		name = NAME_LIST[nameIdx],
		class = mockClass,
		healthPct = healthPct,
		powerPct = powerPct,
		powerToken = CLASS_POWER_TOKEN[mockClass] or 'MANA',
		shieldPct = shieldPct,
		healAbsorbPct = healAbsorbPct,
		mockCast = MOCK_CASTS[mockClass],
	}
	return mockDataCache[index]
end

-- Expose GetMockData for PreviewFrame.lua to use
TestMode.GetMockData = GetMockData

----------------------------------------------------------------------------------------------------
-- Public API (delegates to PreviewFrame)
----------------------------------------------------------------------------------------------------

---@return boolean
function TestMode:IsActive()
	return isGlobalActive
end

---@param frameName string
---@return boolean
function TestMode:IsFrameForced(frameName)
	return UF.PreviewFrame:IsShowing(frameName)
end

---Toggle test mode for a specific frame
---@param frameName string
function TestMode:Toggle(frameName)
	if InCombatLockdown() then
		SUI:Print(L['Cannot toggle test mode during combat'])
		return
	end

	if UF.PreviewFrame:IsShowing(frameName) then
		UF.PreviewFrame:Hide(frameName)
	else
		UF.PreviewFrame:Show(frameName)
	end
	isGlobalActive = UF.PreviewFrame:IsActive()
end

---Bring the active flag back in line with what is on screen
function TestMode:Sync()
	isGlobalActive = UF.PreviewFrame:IsActive()
end

---Enable test mode for all spawned frames
function TestMode:EnableAll()
	if InCombatLockdown() then
		SUI:Print(L['Cannot toggle test mode during combat'])
		return
	end

	UF.PreviewFrame:ShowAll()
	isGlobalActive = true
end

---Disable test mode for all forced frames
function TestMode:DisableAll()
	if InCombatLockdown() then
		SUI:Print(L['Cannot toggle test mode during combat'])
		return
	end

	UF.PreviewFrame:HideAll()
	isGlobalActive = false
end

----------------------------------------------------------------------------------------------------
-- Combat lockdown safety: auto-hide previews on combat entry
----------------------------------------------------------------------------------------------------

local combatWatcher = CreateFrame('Frame')
combatWatcher:RegisterEvent('PLAYER_REGEN_DISABLED')
combatWatcher:SetScript('OnEvent', function(_, event)
	if event == 'PLAYER_REGEN_DISABLED' then
		if isGlobalActive then
			UF.PreviewFrame:HideAll()
			isGlobalActive = false
			SUI:Print(L['Test mode disabled due to combat'])
		end
	end
end)
