local SUI, L, print = SUI, SUI.L, SUI.print
local module = SUI:NewModule('TauntWatcher') ---@type SUI.Module
module.DisplayName = L['Taunt watcher']
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
			announceLocation = 'SELF',
			text = '%who taunted %what!',
		},
	}
	module.Database = SUI.SpartanUIDB:RegisterNamespace('TauntWatcher', defaults)
	module.DB = module.Database.profile

	-- Register profile change callbacks
	SUI.DBM:RegisterSequentialProfileRefresh(module)

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

	local timeStamp, subEvent, _, _, srcName, _, _, _, dstName, _, _, spellID, spellName = (C_CombatLog and C_CombatLog.GetCurrentEventInfo or CombatLogGetCurrentEventInfo)()
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
