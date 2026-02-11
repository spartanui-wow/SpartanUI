local SUI, L, print = SUI, SUI.L, SUI.print
local module = SUI:NewModule('InterruptAnnouncer') ---@type SUI.Module
module.Displayname = L['Interrupt announcer']
----------------------------------------------------------------------------------------------------
local lastTime, lastSpellID = nil, nil

-- Helpers for API compatibility (retail vs classic)
local GetSpellLinkCompat = C_Spell and C_Spell.GetSpellLink or GetSpellLink
local SendChatMessageCompat = C_ChatInfo.SendChatMessage

local function printFormattedString(t, sid, spell, ss, ssid, inputstring)
	local msg = inputstring or module.DB.text
	local DBChannel = module.DB.announceLocation or 'SELF'
	local spelllink = GetSpellLinkCompat(sid)

	msg = msg:gsub('%%t', t):gsub('%%cl', CombatLog_String_SchoolString(ss)):gsub('%%spell', spelllink):gsub('%%sl', spelllink):gsub('%%myspell', GetSpellLinkCompat(ssid))
	if DBChannel ~= 'SELF' then
		if DBChannel == 'SMART' then
			if IsInGroup(2) then
				SendChatMessageCompat(msg, 'INSTANCE_CHAT')
				return
			elseif IsInRaid() then
				SendChatMessageCompat(msg, 'RAID')
				return
			elseif IsInGroup(1) then
				SendChatMessageCompat(msg, 'PARTY')
				return
			end
		else
			if DBChannel == 'RAID' or DBChannel == 'INSTANCE_CHAT' then
				if IsInGroup(2) then
					-- We are in a raid with instance chat
					SendChatMessageCompat(msg, 'INSTANCE_CHAT')
					return
				elseif IsInRaid() then
					-- We are in a manual Raid
					SendChatMessageCompat(msg, 'RAID')
					return
				end
			elseif DBChannel == 'PARTY' and IsInGroup(1) then
				SendChatMessageCompat(msg, 'PARTY')
				return
			end
		end
	end

	print(msg)
end

function module:OnInitialize()
	local defaults = {
		profile = {
			always = false,
			inBG = false,
			inRaid = true,
			inParty = true,
			selfInterrupt = true,
			inArena = true,
			outdoors = false,
			includePets = true,
			FirstLaunch = true,
			announceLocation = 'SMART',
			text = 'Interrupted %t %spell',
		},
	}
	module.Database = SUI.SpartanUIDB:RegisterNamespace('InterruptAnnouncer', defaults)
	module.DB = module.Database.profile

	-- Register profile change callbacks
	SUI.DBM:RegisterSequentialProfileRefresh(module)
end

local function COMBAT_LOG_EVENT_UNFILTERED()
	if SUI:IsModuleDisabled('InterruptAnnouncer') then
		return
	end

	local continue = false
	local inInstance, instanceType = IsInInstance()
	if instanceType == 'arena' and module.DB.inArena then
		continue = true
	elseif inInstance and instanceType == 'party' and module.DB.inParty then
		continue = true
	elseif instanceType == 'pvp' and module.DB.inBG then
		continue = true
	elseif instanceType == 'raid' and module.DB.inRaid then
		continue = true
	elseif (instanceType == 'none' or (not inInstance and instanceType == 'party')) and module.DB.outdoors then
		continue = true
	end

	local timeStamp, eventType, _, sourceGUID, _, _, _, destGUID, destName, _, _, sourceID, _, _, spellID, spellName, spellSchool = CombatLogGetCurrentEventInfo()

	-- Check if time and ID was same as last
	-- Note: This is to prevent flooding announcements on AoE taunts.
	if timeStamp == lastTime and spellID == lastSpellID then
		return
	end

	-- Update last time and ID
	lastTime, lastSpellID = timeStamp, spellID

	if (continue or module.DB.alwayson) and eventType == 'SPELL_INTERRUPT' and (sourceGUID == UnitGUID('player') or (sourceGUID == UnitGUID('pet') and module.DB.includePets)) then
		if destGUID == UnitGUID('player') and module.DB.selfInterrupt then
			printFormattedString(destName, spellID, spellName, spellSchool, sourceID, 'I have hurt myself in confustion while casting %spell and can no longer cast.')
		else
			printFormattedString(destName, spellID, spellName, spellSchool, sourceID)
		end
	end
end

function module:OnEnable()
	module:Options()
	module:FirstLaunch()

	-- Defer event registration to next frame to avoid taint issues during addon init
	C_Timer.After(0, function()
		if module:IsEnabled() then
			module:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED', COMBAT_LOG_EVENT_UNFILTERED)
		end
	end)
end

function module:Options()
	SUI.opt.args['Modules'].args['InterruptAnnouncer'] = {
		type = 'group',
		name = L['Interrupt announcer'],
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
				order = 1,
			},
			active = {
				name = L['Active when in'],
				type = 'group',
				inline = true,
				order = 100,
				get = function(info)
					return module.DB[info[#info]]
				end,
				set = function(info, val)
					module.DB[info[#info]] = val
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
						name = L['Outdoors'],
						type = 'toggle',
						order = 1,
					},
				},
			},
			selfInterrupt = {
				name = L['Include self'],
				type = 'toggle',
				order = 1,
			},
			includePets = {
				name = L['Include pets'],
				type = 'toggle',
				order = 2,
			},
			announceLocation = {
				name = L['Announce location'],
				type = 'select',
				order = 200,
				values = {
					['INSTANCE_CHAT'] = L['Instance chat'],
					['PARTY'] = L['Party'],
					['RAID'] = L['Raid'],
					['SELF'] = L['Self'],
					['SMART'] = L['Smart'],
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
						name = '- %t - ' .. L['Target that was interrupted'],
						type = 'description',
						order = 11,
						fontSize = 'small',
					},
					c = {
						name = '- %spell - ' .. L['Spell link of spell interrupted'],
						type = 'description',
						order = 12,
						fontSize = 'small',
					},
					d = {
						name = '- %cl - ' .. L['Spell class'],
						type = 'description',
						order = 14,
						fontSize = 'small',
					},
					f = {
						name = '- %myspell - ' .. L['Spell you used to interrupt'],
						type = 'description',
						order = 15,
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

function module:FirstLaunch()
	-- Access LibAT from global namespace (not LibStub)
	local LibAT = _G.LibAT

	local PageData = {
		ID = 'InterruptAnnouncer',
		Name = L['Interrupt announcer'],
		SubTitle = L['Interrupt announcer'],
		RequireDisplay = module.DB.FirstLaunch,
		Display = function()
			local SUI_Win = SUI.Setup.window.content

			--Container
			local IAnnounce = CreateFrame('Frame', nil)
			IAnnounce:SetParent(SUI_Win)
			IAnnounce:SetAllPoints(SUI_Win)

			if SUI:IsModuleDisabled('InterruptAnnouncer') then
				IAnnounce.lblDisabled = LibAT.UI.CreateLabel(IAnnounce, 'Disabled', 'GameFontNormalLarge')
				IAnnounce.lblDisabled:SetPoint('CENTER', IAnnounce)
			else
				-- Setup checkboxes
				IAnnounce.options = {}
				IAnnounce.options.alwayson = LibAT.UI.CreateCheckbox(IAnnounce, L['Always on'])

				IAnnounce.options.inBG = LibAT.UI.CreateCheckbox(IAnnounce, L['Battleground'])
				IAnnounce.options.inRaid = LibAT.UI.CreateCheckbox(IAnnounce, L['Raid'])
				IAnnounce.options.inParty = LibAT.UI.CreateCheckbox(IAnnounce, L['Party'])
				IAnnounce.options.inArena = LibAT.UI.CreateCheckbox(IAnnounce, L['Arena'])
				IAnnounce.options.outdoors = LibAT.UI.CreateCheckbox(IAnnounce, L['Outdoors'])

				local items = {
					{ text = L['Instance chat'], value = 'INSTANCE_CHAT' },
					{ text = L['Raid'], value = 'RAID' },
					{ text = L['Party'], value = 'PARTY' },
					{ text = L['Smart'], value = 'SMART' },
					{ text = L['Self'], value = 'SELF' },
				}

				IAnnounce.announceLocation = LibAT.UI.CreateDropdown(IAnnounce, module.DB.announceLocation or L['Smart'], 190, 20)
				-- Note: Dropdown value change handling would need custom implementation

				-- Create Labels
				IAnnounce.modEnabled = LibAT.UI.CreateCheckbox(IAnnounce, L['Module enabled'])
				IAnnounce.lblActive = LibAT.UI.CreateLabel(IAnnounce, L['Active when in'])
				IAnnounce.lblAnnouncelocation = LibAT.UI.CreateLabel(IAnnounce, L['Announce location'])

				-- Positioning using SUI.UI helpers
				SUI.UI.GlueTop(IAnnounce.modEnabled, SUI_Win, 0, -10)
				SUI.UI.GlueBelow(IAnnounce.lblAnnouncelocation, IAnnounce.modEnabled, -100, -20)
				SUI.UI.GlueRight(IAnnounce.announceLocation, IAnnounce.lblAnnouncelocation, 5, 0)

				-- Active locations
				SUI.UI.GlueBelow(IAnnounce.lblActive, IAnnounce.lblAnnouncelocation, -80, -20)

				SUI.UI.GlueBelow(IAnnounce.options.inBG, IAnnounce.lblActive, 30, 0)
				SUI.UI.GlueRight(IAnnounce.options.inArena, IAnnounce.options.inBG, 0, 0)
				SUI.UI.GlueRight(IAnnounce.options.outdoors, IAnnounce.options.inArena, 0, 0)

				SUI.UI.GlueBelow(IAnnounce.options.inRaid, IAnnounce.options.inBG, 0, 0)
				SUI.UI.GlueRight(IAnnounce.options.inParty, IAnnounce.options.inRaid, 0, 0)

				-- text display
				IAnnounce.lblAnnouncetext = LibAT.UI.CreateLabel(IAnnounce, L['Announce text:'])
				IAnnounce.lblvariable1 = LibAT.UI.CreateLabel(IAnnounce, '%t - ' .. L['Target that was interrupted'])
				IAnnounce.lblvariable2 = LibAT.UI.CreateLabel(IAnnounce, '%spell - ' .. L['Spell link of spell interrupted'])
				IAnnounce.lblvariable3 = LibAT.UI.CreateLabel(IAnnounce, '%cl - ' .. L['Spell class'])
				IAnnounce.lblvariable4 = LibAT.UI.CreateLabel(IAnnounce, '%myspell - ' .. L['Spell you used to interrupt'])
				IAnnounce.tbAnnounceText = LibAT.UI.CreateEditBox(IAnnounce, 300, 24)
				IAnnounce.tbAnnounceText:SetText(module.DB.text or '')

				SUI.UI.GlueBelow(IAnnounce.lblAnnouncetext, IAnnounce.lblActive, 0, -80)
				SUI.UI.GlueBelow(IAnnounce.lblvariable1, IAnnounce.lblAnnouncetext, 15, -5, 'LEFT')
				SUI.UI.GlueBelow(IAnnounce.lblvariable2, IAnnounce.lblvariable1, 0, -5, 'LEFT')
				SUI.UI.GlueBelow(IAnnounce.lblvariable3, IAnnounce.lblvariable2, 0, -5, 'LEFT')
				SUI.UI.GlueBelow(IAnnounce.lblvariable4, IAnnounce.lblvariable3, 0, -5, 'LEFT')
				SUI.UI.GlueBelow(IAnnounce.tbAnnounceText, IAnnounce.lblvariable4, -15, -5, 'LEFT')

				-- Defaults
				IAnnounce.modEnabled:SetChecked(SUI:IsModuleEnabled('InterruptAnnouncer'))
				for key, object in pairs(IAnnounce.options) do
					object:SetChecked(module.DB[key])
				end

				IAnnounce.modEnabled:HookScript('OnClick', function()
					for _, object in pairs(IAnnounce.options) do
						if IAnnounce.modEnabled:GetChecked() then
							object:Enable()
						else
							object:Disable()
						end
					end
				end)
			end

			SUI_Win.IAnnounce = IAnnounce
		end,
		Next = function()
			if SUI:IsModuleEnabled('CombatLog') then
				local window = SUI.Setup.window
				local IAnnounce = window.content.IAnnounce
				if not IAnnounce.modEnabled:GetChecked() then
					SUI:DisableModule(module)
				end

				for key, object in pairs(IAnnounce.options) do
					module.DB[key] = object:GetChecked()
				end
				module.DB.text = IAnnounce.tbAnnounceText:GetText()
			end
			module.DB.FirstLaunch = false
		end,
		Skip = function()
			module.DB.FirstLaunch = false
		end,
	}
	SUI.Setup:AddPage(PageData)
end
