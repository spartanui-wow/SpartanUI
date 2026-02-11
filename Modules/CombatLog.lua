local SUI, L, print = SUI, SUI.L, SUI.print
local module = SUI:NewModule('CombatLog') ---@type SUI.Module
module.DisplayName = L['Combat logging']
module.description = 'Automatically runs /combatlog when in raids for log uploading to sites like Warcraftlogs'
----------------------------------------------------------------------------------------------------
local CombatLog_Watcher = CreateFrame('Frame')

function module:OnInitialize()
	local defaults = {
		profile = {
			alwayson = false,
			announce = true,
			raidmythic = true,
			raidheroic = true,
			raidnormal = true,
			raidlfr = false,
			raidlegacy = false,
			mythicplus = true,
			mythicdungeon = false,
			heroicdungeon = false,
			normaldungeon = false,
			loggingActive = false,
			FirstLaunch = true,
		},
	}
	module.Database = SUI.SpartanUIDB:RegisterNamespace('CombatLog', defaults)
	module.DB = module.Database.profile

	-- Register profile change callbacks
	SUI.DBM:RegisterProfileCallbacks(module)
end

local function setLogging(on, msg)
	if on then
		if GetCVar('advancedCombatLogging') ~= 1 then
			SetCVar('advancedCombatLogging', 1)
		end
		LoggingCombat(true)
		module.DB.loggingActive = true -- We have to track this ourself incase the player reloads the ui
	else
		LoggingCombat(false)
		module.DB.loggingActive = false
	end
	if module.DB.announce and msg then
		if msg == 'disabled' then
			SUI:Print('Combat logging disabled')
		else
			SUI:Print('Combat logging enabled - ' .. msg .. ' detected')
		end
	end
end

function module.ZONE_CHANGED_NEW_AREA()
	module:LogCheck('ZONE_CHANGED_NEW_AREA')
end

function module.CHALLENGE_MODE_START()
	module:LogCheck('CHALLENGE_MODE_START')
end

-- This is used to keep loggin turned on if the user /reloads
function module.PLAYER_ENTERING_WORLD()
	if module.DB.loggingActive then
		setLogging(true)
	else
		module:LogCheck('CHALLENGE_MODE_START')
		setLogging()
	end
end

function module:OnEnable()
	module:Options()
	module:FirstLaunch()

	CombatLog_Watcher:SetScript('OnEvent', function(_, event)
		if SUI:IsModuleDisabled('CombatLog') then
			return
		end

		if module[event] then
			module[event]()
		end
	end)

	if SUI.IsRetail then
		CombatLog_Watcher:RegisterEvent('CHALLENGE_MODE_START')
	end
	CombatLog_Watcher:RegisterEvent('ZONE_CHANGED_NEW_AREA')
	CombatLog_Watcher:RegisterEvent('PLAYER_ENTERING_WORLD')
	SUI:AddChatCommand('logging', function(arg)
		if (not arg) or (arg == 'start' and LoggingCombat()) or (arg == 'stop' and not LoggingCombat()) then
			if LoggingCombat() then
				SUI:Print('Currently logging combat')
			else
				SUI:Print('NOT Currently logging combat')
			end
		elseif arg == 'start' then
			setLogging(true, 'manual command')
		elseif arg == 'stop' then
			setLogging(false, 'disabled')
		end
	end, 'Toggles combat logging', nil, true)
end

function module:OnDisable()
	if SUI.IsRetail then
		CombatLog_Watcher:UnregisterEvent('CHALLENGE_MODE_START')
	end
	CombatLog_Watcher:UnregisterEvent('ZONE_CHANGED_NEW_AREA')
	CombatLog_Watcher:UnregisterEvent('PLAYER_ENTERING_WORLD')
end

function module:announce(msg) end

function module:LogCheck(event)
	local _, type, difficulty, _, maxPlayers = GetInstanceInfo()
	if module.DB.alwayson then
		setLogging(true, 'Always on')
	elseif module.DB.raidmythic and type == 'raid' and difficulty == 16 then
		-- 16 - 20-player Mythic Raid Instance
		setLogging(true, 'Mythic Raid')
	elseif module.DB.raidheroic and type == 'raid' and difficulty == 15 then
		-- 15 - 10-30-player Heroic Raid Instance
		setLogging(true, 'Heroic Raid')
	elseif module.DB.raidnormal and type == 'raid' and difficulty == 14 then
		-- 14 - 10-30-player Normal Raid Instance
		setLogging(true, 'Normal Raid')
	elseif module.DB.raidlfr and type == 'raid' and difficulty == 17 then
		-- 17 - 10-30-player Raid Finder Instance
		setLogging(true, 'Raid Finder')
	elseif module.DB.normaldungeon and type == 'party' and difficulty == 1 and maxPlayers == 5 then
		-- 1 - 5-player Instance, filtering Garrison
		setLogging(true, 'Normal Dungeon')
	elseif module.DB.heroicdungeon and type == 'party' and difficulty == 2 and maxPlayers == 5 then
		-- 2 - 5-player Heroic Instance, filtering Garrison
		setLogging(true, 'Heroic Dungeon')
	elseif module.DB.mythicdungeon and type == 'party' and difficulty == 23 and maxPlayers == 5 then
		-- 23 - Mythic 5-player Instance, filtering Garrison
		setLogging(true, 'Mythic Dungeon')
	elseif module.DB.mythicplus and event == 'CHALLENGE_MODE_START' and type == 'party' and difficulty == 8 and maxPlayers == 5 then
		-- 8 - Mythic+ Mode Instance
		setLogging(true, 'Mythic+ Dungeon')
	elseif module.DB.raidlegacy and type == 'raid' and (difficulty == 3 or difficulty == 4 or difficulty == 5 or difficulty == 6 or difficulty == 7 or difficulty == 9) then
		-- 3-9 is legacy raid difficulties
		setLogging(true, 'Legacy Raid')
	else
		-- If we are curently logging announce we are disabling it.
		if module.DB.loggingActive and LoggingCombat() then
			setLogging(false, 'disabled')
		end
		-- Do this here to ensure DB is set to false
		module.DB.loggingActive = false
	end
end

function module:Options()
	SUI.opt.args['Modules'].args['CombatLog'] = {
		type = 'group',
		name = L['Combat logging'],
		get = function(info)
			return module.DB[info[#info]]
		end,
		set = function(info, val)
			module.DB[info[#info]] = val
			module:LogCheck('force')
		end,
		disabled = function()
			return SUI:IsModuleDisabled(module)
		end,
		args = {
			alwayson = {
				name = L['Always on'],
				type = 'toggle',
				order = 1,
			},
			announce = {
				name = L['Announce logging in chat'],
				type = 'toggle',
				width = 'double',
				order = 5,
			},
			raid = {
				name = L['Raid settings'],
				type = 'group',
				inline = true,
				order = 10,
				width = 'full',
				get = function(info)
					return module.DB[info[#info]]
				end,
				set = function(info, val)
					module.DB[info[#info]] = val
					module:LogCheck('force')
				end,
				args = {
					raidlegacy = {
						name = L['Legacy raids'],
						type = 'toggle',
						order = 0,
					},
					raidlfr = {
						name = L['Looking for raid'],
						type = 'toggle',
						order = 2,
					},
					raidnormal = {
						name = L['Normal'],
						type = 'toggle',
						order = 4,
					},
					raidheroic = {
						name = L['Heroic'],
						type = 'toggle',
						order = 6,
					},
					raidmythic = {
						name = L['Mythic'],
						type = 'toggle',
						order = 8,
					},
				},
			},
			dungeons = {
				name = L['Dungeon settings'],
				type = 'group',
				inline = true,
				order = 20,
				width = 'full',
				get = function(info)
					return module.DB[info[#info]]
				end,
				set = function(info, val)
					module.DB[info[#info]] = val
					module:LogCheck('force')
				end,
				args = {
					normaldungeon = {
						name = L['Normal'],
						type = 'toggle',
						order = 0,
					},
					heroicdungeon = {
						name = L['Heroic'],
						type = 'toggle',
						order = 2,
					},
					mythicdungeon = {
						name = L['Mythic'],
						type = 'toggle',
						order = 4,
					},
					mythicplus = {
						name = L['Mythic+'],
						type = 'toggle',
						order = 6,
					},
				},
			},
		},
	}
end

function module:FirstLaunch()
	-- Access LibAT from global namespace (not LibStub)
	local LibAT = _G.LibAT

	local PageData = {
		ID = 'CombatLog',
		Name = L['Combat logging'],
		SubTitle = L['Combat logging'],
		Desc1 = L['Automatically turn on combat logging when entering a zone.'],
		Desc2 = L['Combat log will be Automatically enabled, for easy uploading to websites such as Warcraftlogs.'],
		RequireDisplay = module.DB.FirstLaunch,
		Display = function()
			local SUI_Win = SUI.Setup.window.content

			--Container
			local cLog = CreateFrame('Frame', nil)
			cLog:SetParent(SUI_Win)
			cLog:SetAllPoints(SUI_Win)

			if SUI:IsModuleDisabled('CombatLog') then
				cLog.lblDisabled = LibAT.UI.CreateLabel(cLog, 'Disabled', 'GameFontNormalLarge')
				cLog.lblDisabled:SetPoint('CENTER', cLog)
			else
				-- Setup checkboxes
				cLog.options = {}
				cLog.options.alwayson = LibAT.UI.CreateCheckbox(cLog, L['Always on'])
				cLog.options.announce = LibAT.UI.CreateCheckbox(cLog, L['Announce logging in chat'])
				cLog.modEnabled = LibAT.UI.CreateCheckbox(cLog, L['Module enabled'])

				-- Positioning - 2 column layout with proper spacing
				local col1X, col2X, col3X = -200, -20, 160 -- X positions for columns
				local startY = -10 -- Starting Y position
				local rowHeight = 25 -- Height per row

				-- Module enabled at top
				cLog.modEnabled:SetPoint('TOPLEFT', SUI_Win, 'TOP', -60, startY)

				-- Always on and announce in 2 columns
				cLog.options.alwayson:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X, startY - rowHeight)
				cLog.options.announce:SetPoint('TOPLEFT', SUI_Win, 'TOP', col2X, startY - rowHeight)

				if SUI.IsRetail then
					cLog.options.raidmythic = LibAT.UI.CreateCheckbox(cLog, L['Mythic'])
					cLog.options.raidheroic = LibAT.UI.CreateCheckbox(cLog, L['Heroic'])
					cLog.options.raidnormal = LibAT.UI.CreateCheckbox(cLog, L['Normal'])
					cLog.options.raidlfr = LibAT.UI.CreateCheckbox(cLog, L['Looking for raid'])
					cLog.options.raidlegacy = LibAT.UI.CreateCheckbox(cLog, L['Legacy raids'])

					cLog.options.mythicplus = LibAT.UI.CreateCheckbox(cLog, L['Mythic+'])
					cLog.options.mythicdungeon = LibAT.UI.CreateCheckbox(cLog, L['Mythic'])
					cLog.options.heroicdungeon = LibAT.UI.CreateCheckbox(cLog, L['Heroic'])
					cLog.options.normaldungeon = LibAT.UI.CreateCheckbox(cLog, L['Normal'])

					-- Create Labels
					cLog.lblRaid = LibAT.UI.CreateLabel(cLog, L['Raid settings'])
					cLog.lblDungeon = LibAT.UI.CreateLabel(cLog, L['Dungeon settings'])

					-- Raid Settings label and checkboxes in 3 columns
					cLog.lblRaid:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X, startY - (rowHeight * 2.5))
					cLog.options.raidmythic:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X, startY - (rowHeight * 3.5))
					cLog.options.raidheroic:SetPoint('TOPLEFT', SUI_Win, 'TOP', col2X, startY - (rowHeight * 3.5))
					cLog.options.raidnormal:SetPoint('TOPLEFT', SUI_Win, 'TOP', col3X, startY - (rowHeight * 3.5))

					cLog.options.raidlfr:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X, startY - (rowHeight * 4.5))
					cLog.options.raidlegacy:SetPoint('TOPLEFT', SUI_Win, 'TOP', col2X, startY - (rowHeight * 4.5))

					-- Dungeon Settings label and checkboxes in 3 columns
					cLog.lblDungeon:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X, startY - (rowHeight * 6))
					cLog.options.mythicplus:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X, startY - (rowHeight * 7))
					cLog.options.mythicdungeon:SetPoint('TOPLEFT', SUI_Win, 'TOP', col2X, startY - (rowHeight * 7))
					cLog.options.heroicdungeon:SetPoint('TOPLEFT', SUI_Win, 'TOP', col3X, startY - (rowHeight * 7))

					cLog.options.normaldungeon:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X, startY - (rowHeight * 8))
				end

				-- Defaults
				cLog.modEnabled:SetChecked(SUI:IsModuleEnabled('CombatLog'))
				for key, object in pairs(cLog.options) do
					object:SetChecked(module.DB[key])
				end

				cLog.modEnabled:HookScript('OnClick', function()
					for _, object in pairs(cLog.options) do
						if cLog.modEnabled:GetChecked() then
							object:Enable()
						else
							object:Disable()
						end
					end
				end)
			end

			SUI_Win.cLog = cLog
		end,
		Next = function()
			if SUI:IsModuleEnabled('CombatLog') then
				local window = SUI.Setup.window
				local cLog = window.content.cLog
				if not cLog.modEnabled:GetChecked() then
					SUI:DisableModule(module)
				end

				for key, object in pairs(cLog.options) do
					module.DB[key] = object:GetChecked()
				end
			end
			module.DB.FirstLaunch = false
		end,
		Skip = function()
			module.DB.FirstLaunch = false
		end,
	}
	SUI.Setup:AddPage(PageData)
end
