local SUI, L, print = SUI, SUI.L, SUI.print
local module = SUI:NewModule('TauntWatcher') ---@type SUI.Module
module.Displayname = L['Taunt watcher']
module.description = 'Notify you or your party when others taunt'
----------------------------------------------------------------------------------------------------
-- Helper for spell links (retail vs classic API)
local GetSpellLinkCompat = C_Spell and GetSpellLinkCompat or GetSpellLink

local TauntsList = {
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
}
local lastTimeStamp, lastSpellID, lastspellName = 0, 0, ''
local function printFormattedString(who, target, sid, failed)
	local msg = module.DB.text
	local ChatChannel = module.DB.announceLocation

	msg = msg:gsub('%%what', target):gsub('%%who', who):gsub('%%spell', GetSpellLinkCompat(sid))
	if failed then
		msg = msg .. ' and it failed horribly.'
	end

	if ChatChannel == 'SELF' then
		SUI:Print(msg)
	else
		local inInstanceGroup = IsInGroup(2)
		local inInstanceRaid = IsInRaid(2)
		local inGroup = IsInGroup(1)
		local inRaid = IsInRaid(1)

		-- Handle group type and location
		if ChatChannel == 'RAID' and not inRaid then
			return
		elseif ChatChannel == 'PARTY' and not inGroup then
			return
		end

		-- Adjust ChatChannel for instance groups
		if inInstanceGroup then
			if ChatChannel == 'RAID' and inInstanceRaid then
				ChatChannel = 'INSTANCE_CHAT'
			elseif ChatChannel == 'PARTY' and not inInstanceRaid then
				ChatChannel = 'INSTANCE_CHAT'
			end
		else
			if inRaid and ChatChannel == 'INSTANCE_CHAT' then
				ChatChannel = 'RAID'
			elseif inGroup and ChatChannel == 'INSTANCE_CHAT' then
				ChatChannel = 'PARTY'
			end
		end

		-- Simplified SMART channel logic
		if module.DB.announceLocation == 'SMART' then
			if inInstanceRaid or inInstanceGroup then
				ChatChannel = 'INSTANCE_CHAT'
			elseif inRaid then
				ChatChannel = 'RAID'
			elseif inGroup then
				ChatChannel = 'PARTY'
			else
				SUI:Print(msg)
				return
			end
		end

		C_ChatInfo.SendChatMessage(msg, ChatChannel)
	end
end

function module:OnInitialize()
	local defaults = {
		profile = {
			active = {
				always = false,
				inBG = false,
				inRaid = true,
				inParty = true,
				inArena = true,
				outdoors = false,
			},
			failures = true,
			FirstLaunch = true,
			announceLocation = 'SELF',
			text = '%who taunted %what!',
		},
	}
	module.Database = SUI.SpartanUIDB:RegisterNamespace('TauntWatcher', defaults)
	module.DB = module.Database.profile

	-- Register profile change callbacks
	SUI.DBM:RegisterProfileCallbacks(module)

	-- Migrate old settings
	if SUI.DB.TauntWatcher then
		print('Taunt watcher DB Migration')
		module.DB = SUI:MergeData(module.DB, SUI.DB.TauntWatcher, true)
		SUI.DB.TauntWatcher = nil
	end
end

function module:COMBAT_LOG_EVENT_UNFILTERED()
	if SUI:IsModuleDisabled('TauntWatcher') or module.Override then
		return
	end

	local timeStamp, subEvent, _, _, srcName, _, _, _, dstName, _, _, spellID, spellName = CombatLogGetCurrentEventInfo()
	-- Check if we have been here before
	if
		(SUI.IsRetail and timeStamp == lastTimeStamp and spellID == lastSpellID)
		or (SUI.IsClassic and timeStamp == lastTimeStamp and spellName == lastspellName)
		or (SUI.IsClassic and type(spellName) ~= 'string')
	then
		return
	end

	-- Print the taunt
	if (SUI.IsRetail and SUI:IsInTable(TauntsList, spellID)) or (SUI.IsClassic and SUI:IsInTable(TauntsList, spellName)) then
		local continue = false
		local inInstance, instanceType = IsInInstance()
		if instanceType == 'arena' and module.DB.active.inArena then
			continue = true
		elseif inInstance and instanceType == 'party' and module.DB.active.inParty then
			continue = true
		elseif instanceType == 'pvp' and module.DB.active.inBG then
			continue = true
		elseif instanceType == 'raid' and module.DB.active.inRaid then
			continue = true
		elseif (instanceType == 'none' or (not inInstance and instanceType == 'party')) and module.DB.outdoors then
			continue = true
		end

		if not (continue or module.DB.active.alwayson) then
			return
		end

		if subEvent == 'SPELL_AURA_APPLIED' then
			printFormattedString(srcName, dstName, spellID)
		elseif subEvent == 'SPELL_MISSED' and module.DB.failures then
			printFormattedString(srcName, dstName, spellID, true)
		else
			return
		end
		-- Update last time and ID
		lastTimeStamp, lastSpellID = timeStamp, spellID
	end
end

function module:OnDisable()
	module:UnregisterAllEvents()
end

function module:OnEnable()
	module:Options()
	module:SetupWizard()

	module:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
end

function module:Options()
	SUI.opt.args['Modules'].args['TauntWatcher'] = {
		type = 'group',
		name = L['Taunt watcher'],
		get = function(info)
			return module.DB[info[#info]]
		end,
		set = function(info, val)
			module.DB[info[#info]] = val
		end,
		disabled = function()
			return SUI:IsModuleDisabled(module)
		end,
		args = {
			alwayson = {
				name = L['Always on'],
				type = 'toggle',
				width = 'full',
				order = 1,
				get = function(info)
					return module.DB.active.alwayson
				end,
				set = function(info, val)
					module.DB.active.alwayson = val
				end,
			},
			active = {
				name = L['Active'],
				type = 'group',
				inline = true,
				order = 100,
				get = function(info)
					return module.DB.active[info[#info]]
				end,
				set = function(info, val)
					module.DB.active[info[#info]] = val
				end,
				args = {
					inBG = {
						name = L['Battleground'],
						type = 'toggle',
						order = 1,
					},
					inRaid = {
						name = L['Raid'],
						type = 'toggle',
						order = 1,
					},
					inParty = {
						name = L['Party'],
						type = 'toggle',
						order = 1,
					},
					inArena = {
						name = L['Arena'],
						type = 'toggle',
						order = 1,
					},
					outdoors = {
						name = L['Outdoor'],
						type = 'toggle',
						order = 1,
					},
				},
			},
			failures = {
				name = L['Annnounce failed taunts'],
				type = 'toggle',
				width = 'full',
				order = 150,
			},
			announceLocation = {
				name = L['Announce location'],
				type = 'select',
				order = 200,
				values = {
					['INSTANCE_CHAT'] = 'Instance chat',
					['RAID'] = 'Raid',
					['PARTY'] = 'Party',
					['SMART'] = 'SMART',
					['SAY'] = 'Say',
					['SELF'] = 'No chat',
				},
			},
			TextInfo = {
				name = '',
				type = 'group',
				inline = true,
				order = 300,
				args = {
					a = {
						name = L['Text variables:'],
						type = 'description',
						order = 10,
						fontSize = 'large',
					},
					b = {
						name = '- %who - ' .. L['Player/Pet that taunted'],
						type = 'description',
						order = 11,
						fontSize = 'small',
					},
					b2 = {
						name = '- %what - ' .. L['Name of mob taunted'],
						type = 'description',
						order = 12,
						fontSize = 'small',
					},
					c = {
						name = '- %spell - ' .. L['Spell link of spell used to taunt'],
						type = 'description',
						order = 13,
						fontSize = 'small',
					},
					h = {
						name = '',
						type = 'description',
						order = 499,
						fontSize = 'medium',
					},
					text = {
						name = L['Announce text:'],
						type = 'input',
						order = 501,
						width = 'full',
						get = function(info)
							return module.DB.text
						end,
						set = function(info, value)
							module.DB.text = value
						end,
					},
				},
			},
		},
	}
end

function module:SetupWizard()
	-- Access LibAT from global namespace (not LibStub)
	local LibAT = _G.LibAT

	local PageData = {
		ID = 'TauntWatcher',
		name = L['Taunt watcher'],
		SubTitle = 'Taunt watcher',
		RequireDisplay = module.DB.FirstLaunch,
		Display = function()
			local SUI_Win = SUI.Setup.window.content

			--Container
			local TauntWatch = CreateFrame('Frame', nil)
			TauntWatch:SetParent(SUI_Win)
			TauntWatch:SetAllPoints(SUI_Win)

			if SUI:IsModuleDisabled('TauntWatcher') or module.Override then
				TauntWatch.lblDisabled = LibAT.UI.CreateLabel(TauntWatch, 'Disabled', 'GameFontNormalLarge')
				TauntWatch.lblDisabled:SetPoint('CENTER', TauntWatch)
			else
				local items = {
					{ text = L['Instance chat'], value = 'INSTANCE_CHAT' },
					{ text = L['Raid'], value = 'RAID' },
					{ text = L['Party'], value = 'PARTY' },
					{ text = L['Say'], value = 'SAY' },
					{ text = L['Smart'], value = 'SMART' },
					{ text = L['Self'], value = 'SELF' },
				}

				TauntWatch.announceLocation = LibAT.UI.CreateDropdown(TauntWatch, module.DB.announceLocation or L['Smart'], 190, 20)

				-- Create Labels
				TauntWatch.modEnabled = LibAT.UI.CreateCheckbox(TauntWatch, L['Module enabled'])
				TauntWatch.lblActive = LibAT.UI.CreateLabel(TauntWatch, L['Active when in'])
				TauntWatch.lblAnnouncelocation = LibAT.UI.CreateLabel(TauntWatch, L['Announce location'])

				-- Setup checkboxes
				TauntWatch.options = {}
				TauntWatch.options.alwayson = LibAT.UI.CreateCheckbox(TauntWatch, L['Always on'])

				TauntWatch.options.inBG = LibAT.UI.CreateCheckbox(TauntWatch, L['Battleground'])
				TauntWatch.options.inRaid = LibAT.UI.CreateCheckbox(TauntWatch, L['Raid'])
				TauntWatch.options.inParty = LibAT.UI.CreateCheckbox(TauntWatch, L['Party'])
				TauntWatch.options.inArena = LibAT.UI.CreateCheckbox(TauntWatch, L['Arena'])
				TauntWatch.options.outdoors = LibAT.UI.CreateCheckbox(TauntWatch, L['Outdoors'])

				-- Positioning - column layout with proper spacing
				local col1X, col2X, col3X = -200, -40, 120 -- X positions for columns
				local startY = -10 -- Starting Y position
				local rowHeight = 25 -- Height per row

				-- Module enabled at top
				TauntWatch.modEnabled:SetPoint('TOPLEFT', SUI_Win, 'TOP', -60, startY)

				-- Announce location label and dropdown
				TauntWatch.lblAnnouncelocation:SetPoint('TOPLEFT', SUI_Win, 'TOP', -180, startY - rowHeight)
				TauntWatch.announceLocation:SetPoint('LEFT', TauntWatch.lblAnnouncelocation, 'RIGHT', 5, 0)

				-- Active when in label
				TauntWatch.lblActive:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X, startY - (rowHeight * 2.5))

				-- Checkboxes in 3 columns below "Active when in"
				-- Row 1: Battleground, Arena, Outdoors
				TauntWatch.options.inBG:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X, startY - (rowHeight * 3.5))
				TauntWatch.options.inArena:SetPoint('TOPLEFT', SUI_Win, 'TOP', col2X, startY - (rowHeight * 3.5))
				TauntWatch.options.outdoors:SetPoint('TOPLEFT', SUI_Win, 'TOP', col3X, startY - (rowHeight * 3.5))

				-- Row 2: Raid, Party
				TauntWatch.options.inRaid:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X, startY - (rowHeight * 4.5))
				TauntWatch.options.inParty:SetPoint('TOPLEFT', SUI_Win, 'TOP', col2X, startY - (rowHeight * 4.5))

				-- Announce text section
				TauntWatch.lblAnnouncetext = LibAT.UI.CreateLabel(TauntWatch, L['Announce text:'])
				TauntWatch.lblvariable1 = LibAT.UI.CreateLabel(TauntWatch, '%who - ' .. L['Player/Pet that taunted'])
				TauntWatch.lblvariable2 = LibAT.UI.CreateLabel(TauntWatch, '%what - ' .. L['Name of mob taunted'])

				TauntWatch.tbAnnounceText = LibAT.UI.CreateEditBox(TauntWatch, 300, 24)
				TauntWatch.tbAnnounceText:SetText(module.DB.text or '')

				-- Position announce text section
				TauntWatch.lblAnnouncetext:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X, startY - (rowHeight * 6))
				TauntWatch.lblvariable1:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X + 15, startY - (rowHeight * 7))
				TauntWatch.lblvariable2:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X + 15, startY - (rowHeight * 7.8))

				if SUI.IsClassic then
					TauntWatch.tbAnnounceText:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X, startY - (rowHeight * 8.6))
				else
					TauntWatch.lblvariable3 = LibAT.UI.CreateLabel(TauntWatch, '%spell - ' .. L['Spell link of spell used to taunt'])
					TauntWatch.lblvariable3:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X + 15, startY - (rowHeight * 8.6))
					TauntWatch.tbAnnounceText:SetPoint('TOPLEFT', SUI_Win, 'TOP', col1X, startY - (rowHeight * 9.4))
				end

				-- Defaults
				TauntWatch.modEnabled:SetChecked(SUI:IsModuleEnabled('TauntWatcher'))
				for key, object in pairs(TauntWatch.options) do
					object:SetChecked(module.DB.active[key])
				end

				TauntWatch.modEnabled:HookScript('OnClick', function()
					for _, object in pairs(TauntWatch.options) do
						if TauntWatch.modEnabled:GetChecked() then
							SUI:EnableModule(module)
						else
							SUI:DisableModule(module)
						end
					end
				end)
			end

			SUI_Win.TauntWatch = TauntWatch
		end,
		Next = function()
			if SUI:IsModuleEnabled('TauntWatcher') and not module.Override then
				local window = SUI.Setup.window
				local TauntWatch = window.content.TauntWatch

				for key, object in pairs(TauntWatch.options) do
					module.DB[key] = object:GetChecked()
				end
				module.DB.text = TauntWatch.tbAnnounceText:GetText()
			end
			module.DB.FirstLaunch = false
		end,
		Skip = function()
			module.DB.FirstLaunch = false
		end,
	}
	SUI.Setup:AddPage(PageData)
end
