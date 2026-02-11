local SUI, L = SUI, SUI.L
---@class SUI.Module.Convenience : SUI.Module
local module = SUI:NewModule('Convenience')
module.DisplayName = L['Convenience']
module.description = 'Auto-accept summons, resurrections, and other convenience features'
----------------------------------------------------------------------------------------------------

---@class SUI.Module.Convenience.DB
local DBDefaults = {
	autoAcceptSummon = false,
	autoAcceptResurrection = false,
	autoReleaseInPvP = false,
}

local DB

function module:OnInitialize()
	module.Database = SUI.SpartanUIDB:RegisterNamespace('Convenience', { profile = DBDefaults })
	DB = module.Database.profile
	module.DB = DB

	-- Register profile change callbacks
	module.Database.RegisterCallback(module, 'OnProfileChanged', function()
		DB = module.Database.profile
		module.DB = DB
	end)
	module.Database.RegisterCallback(module, 'OnProfileCopied', function()
		DB = module.Database.profile
		module.DB = DB
	end)
	module.Database.RegisterCallback(module, 'OnProfileReset', function()
		DB = module.Database.profile
		module.DB = DB
	end)

	module:SetupWizard()
end

function module:GetDB()
	return DB
end

function module:OnEnable()
	if SUI:IsModuleDisabled(module) then
		return
	end

	-- Register events
	module:RegisterEvent('CONFIRM_SUMMON', 'OnConfirmSummon')
	module:RegisterEvent('RESURRECT_REQUEST', 'OnResurrectRequest')
	module:RegisterEvent('PLAYER_DEAD', 'OnPlayerDead')

	-- Build options
	module:BuildOptions()
end

function module:OnDisable()
	module:UnregisterEvent('CONFIRM_SUMMON')
	module:UnregisterEvent('RESURRECT_REQUEST')
	module:UnregisterEvent('PLAYER_DEAD')
end

function module:OnConfirmSummon()
	if not DB.autoAcceptSummon then
		return
	end

	-- Don't auto-accept in combat
	if InCombatLockdown() then
		return
	end

	-- Get summon info
	local summonArea = C_SummonInfo.GetSummonConfirmAreaName()
	local summoner = C_SummonInfo.GetSummonConfirmSummoner()

	if summoner then
		SUI:Print(L['Auto-accepting summon from'] .. ' ' .. summoner .. (summonArea and (' to ' .. summonArea) or ''))
		C_SummonInfo.ConfirmSummon()
	end
end

function module:OnResurrectRequest(event, caster)
	if not DB.autoAcceptResurrection then
		return
	end

	-- Don't auto-accept in combat
	if InCombatLockdown() then
		return
	end

	if caster then
		SUI:Print(L['Auto-accepting resurrection from'] .. ' ' .. caster)
		AcceptResurrect()
		StaticPopup_Hide('RESURRECT_NO_TIMER')
		StaticPopup_Hide('RESURRECT_NO_SICKNESS')
		StaticPopup_Hide('RESURRECT')
	end
end

function module:OnPlayerDead()
	if not DB.autoReleaseInPvP then
		return
	end

	-- Check if we're in a PvP instance
	local inInstance, instanceType = IsInInstance()
	if inInstance and (instanceType == 'pvp' or instanceType == 'arena') then
		-- Release spirit
		C_Timer.After(0.5, function()
			if UnitIsDead('player') and not UnitIsGhost('player') then
				SUI:Print(L['Auto-releasing in PvP instance'])
				RepopMe()
			end
		end)
		return
	end

	-- Check for specific PvP zones (Wintergrasp, Ashran, etc.)
	local mapID = C_Map.GetBestMapForUnit('player')
	local pvpZones = {
		[123] = true, -- Wintergrasp
		[588] = true, -- Ashran
		[1280] = true, -- Korthia (for compatibility)
	}

	if mapID and pvpZones[mapID] then
		C_Timer.After(0.5, function()
			if UnitIsDead('player') and not UnitIsGhost('player') then
				SUI:Print(L['Auto-releasing in PvP zone'])
				RepopMe()
			end
		end)
	end
end
