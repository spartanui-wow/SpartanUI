local SUI, L, print = SUI, SUI.L, SUI.print
local module = SUI.Handlers.BarSystem ---@type SUI.Module.BarHandler
local BartenderMin = '4.15.0' -- Increased from 4.13.0 due to LibActionButton state bugs during spec changes
local MoveIt = SUI:GetModule('MoveIt') ---@type MoveIt
local Bartender4 = Bartender4
local scaleData
local BartenderChangesActive = false
------------------------------------------------------------
local BTProfileName = 'SpartanUI'
local SUIBT4Settings = {
	ActionBars = {
		actionbars = {
			{
				enabled = true,
				buttons = 12,
				rows = 1,
				padding = 3,
				position = { scale = 0.85 },
				skin = { Zoom = true },
			}, -- 1
			{
				enabled = true,
				buttons = 12,
				rows = 1,
				padding = 3,
				position = { scale = 0.85 },
				skin = { Zoom = true },
			}, -- 2
			{
				enabled = true,
				buttons = 12,
				rows = 1,
				padding = 3,
				position = { scale = 0.85 },
				skin = { Zoom = true },
			}, -- 3
			{
				enabled = true,
				buttons = 12,
				rows = 1,
				padding = 3,
				position = { scale = 0.85 },
				skin = { Zoom = true },
			}, -- 4
			{
				enabled = true,
				buttons = 12,
				rows = 3,
				padding = 4,
				position = { scale = 0.85 },
				skin = { Zoom = true },
			}, -- 5
			{
				enabled = true,
				buttons = 12,
				rows = 3,
				padding = 4,
				position = { scale = 0.85 },
				skin = { Zoom = true },
			}, -- 6
			{
				enabled = false,
				buttons = 12,
				rows = 1,
				padding = 3,
				position = { scale = 0.85 },
				skin = { Zoom = true },
			}, -- 7
			{
				enabled = false,
				buttons = 12,
				rows = 1,
				padding = 3,
				position = { scale = 0.85 },
				skin = { Zoom = true },
			}, -- 8
			{
				enabled = false,
				buttons = 12,
				rows = 1,
				padding = 3,
				position = { scale = 0.85 },
				skin = { Zoom = true },
			}, -- 9
			{
				enabled = false,
				buttons = 12,
				rows = 1,
				padding = 3,
				position = { scale = 0.85 },
				skin = { Zoom = true },
			}, -- 10
		},
	},
	BagBar = {
		enabled = true,
		padding = 0,
		onebag = false,
		keyring = true,
		position = { scale = 0.6 },
		skin = { Zoom = true },
	},
	MicroMenu = {
		enabled = true,
		padding = -7,
		position = { scale = 0.6 },
	},
	QueueStatus = {
		position = { scale = 0.58 },
	},
	PetBar = {
		enabled = true,
		position = { scale = 0.6 },
		skin = { Zoom = true },
	},
	StanceBar = {
		enabled = true,
		padding = 1,
		position = { scale = 0.6 },
		skin = { Zoom = true },
	},
	Vehicle = {
		enabled = false,
	},
	ExtraActionBar = {
		enabled = false,
	},
	ZoneAbilityBar = {
		enabled = false,
	},
	XPBar = {
		enabled = false,
	},
	RepBar = {
		enabled = false,
	},
	BlizzardArt = { enabled = false },
	StatusTrackingBar = { enabled = false },
	blizzardVehicle = true,
}

local FrameList = {
	'BT4Bar1',
	'BT4Bar2',
	'BT4Bar3',
	'BT4Bar4',
	'BT4Bar5',
	'BT4Bar6',
	'BT4Bar7',
	'BT4Bar8',
	'BT4Bar9',
	'BT4Bar10',
	'BT4BarBagBar',
	'BT4BarStanceBar',
	'BT4BarPetBar',
	'MultiCastActionBarFrame',
	'BT4BarMicroMenu',
	'BT4BarQueueStatus',
}
------------------------------------------------------------

-- Bartender4 Items

-- Creates the SUI BT4 Profile
local function SetupProfile()
	--Exit if Bartender4 is not loaded
	if SUI:IsAddonDisabled('Bartender4') then
		return
	end

	-- Cannot modify secure frames during combat
	if InCombatLockdown() then
		if module.logger then
			module.logger.warning('Cannot setup Bartender4 profile during combat - deferring to PLAYER_REGEN_ENABLED')
		end
		module.profileSetupPending = true
		return
	end

	--Flag the SUI.DB that we are making changes
	BartenderChangesActive = true

	-- Set/Create our Profile
	Bartender4.db:SetProfile(BTProfileName)

	--Load the Profile Data
	for k, v in LibStub('AceAddon-3.0'):IterateModulesOfAddon(Bartender4) do -- for each module (BagBar, ActionBars, etc..)
		if SUIBT4Settings[k] and v.db.profile then
			v.db.profile = SUI:MergeData(v.db.profile, SUIBT4Settings[k], true)
		end
	end

	-- Update BT4 Configuration (deferred to avoid state initialization race)
	C_Timer.After(0.5, function()
		if not InCombatLockdown() then
			-- Wrap in pcall to catch Bartender4/LibActionButton state errors
			local success, err = pcall(function()
				Bartender4:UpdateModuleConfigs()
			end)
			if not success and module.logger then
				module.logger.error('Bartender4 UpdateModuleConfigs failed: ' .. tostring(err))
				module.logger.info('This is usually caused by outdated Bartender4 version or LibActionButton state bugs')
			end
		else
			-- Still in combat, try again after combat ends
			module.configUpdatePending = true
		end
	end)

	BartenderChangesActive = false
	module.profileSetupPending = false
end

local function Unlock()
	-- Move them!
	MoveIt:MoveIt(FrameList)
end

-- Returns True if the Inputed profileName is in BT4
local function ProfileCheck(profileName, Report)
	if not Bartender4 then
		return
	end

	local profiles, r = Bartender4.db:GetProfiles(), false
	for _, v in pairs(profiles) do
		if v == profileName then
			r = true
		end
	end
	if Report and (r ~= true) then
		print(profileName .. ' ' .. L['BTProfileNameCheckFail'])
	end
	return r
end

local function loadScales()
	scaleData = module.BarScale.BT4.default
	if SUI:IsModuleEnabled('Artwork') and module.BarScale.BT4[SUI.DB.Artwork.Style] then
		scaleData = SUI:MergeData(scaleData, module.BarScale.BT4[SUI.DB.Artwork.Style], true)
	end
	scaleData = SUI:MergeData(scaleData, module.DB.custom.scale.BT4, true)
end

local function RefreshConfig()
	local positionData = module.BarPosition.BT4.default
	-- If artwork is enabled load the art's position data if supplied
	if SUI:IsModuleEnabled('Artwork') and module.BarPosition.BT4[SUI.DB.Artwork.Style] then
		positionData = SUI:MergeData(module.BarPosition.BT4[SUI.DB.Artwork.Style], module.BarPosition.BT4.default)
	end
	loadScales()

	-- Position Bars
	for _, v in ipairs(FrameList) do
		if _G[v] and positionData[v] and type(positionData[v]) == 'string' and positionData[v] ~= '' then
			local f = _G[v]
			if f.scale then
				f:scale(SUI.DB.scale * (scaleData[v] * 1.08696), true)
			end

			if f.position then
				local point, anchor, secondaryPoint, x, y = strsplit(',', positionData[v])
				f:position(point, anchor, secondaryPoint, x, y, false, true)
			end
		end
	end
end

local function BTMover(BarName, DisplayName)
	if not BarName then
		return
	end
	local bar = _G[BarName]
	if bar then
		function bar:LoadPosition() end
		function bar:GetConfigScale()
			return scaleData[BarName]
		end

		function bar:SetConfigScale(scale)
			if scale then
				--Update DB
				module.DB.custom.scale.BT4[BarName] = scale
				-- update memory
				scaleData[BarName] = scale
				--Update screen
				bar:SetScale(scale)
			end
		end

		if scaleData[BarName] then
			bar:SetScale(scaleData[BarName])
		end
		MoveIt:CreateMover(bar, BarName, DisplayName, nil, 'Bartender4')
		MoveIt:UpdateMover(BarName, bar.overlay, true)
	end
end

local function AddMovers()
	local bt4ActionBars = Bartender4:GetModule('ActionBars')

	for _, i in ipairs(bt4ActionBars.LIST_ACTIONBARS) do
		local BarName = 'BT4Bar' .. i
		local bar = _G[BarName]
		if bar then
			local barLabel = bt4ActionBars:GetBarName(i)
			function bar:LoadPosition() end
			function bar:GetConfigScale()
				return scaleData[BarName]
			end

			function bar:SetConfigScale(scale)
				if scale then
					--Update DB
					module.DB.custom.scale.BT4[BarName] = scale
					-- update memory
					scaleData[BarName] = scale
					--Update screen
					bar:SetScale(scale)
				end
			end

			if scaleData[BarName] then
				bar:SetScale(scaleData[BarName])
			end
			MoveIt:CreateMover(bar, BarName, barLabel, nil, 'Bartender4')
			MoveIt:UpdateMover(BarName, bar.overlay, true)
		end
	end
	BTMover('BT4BarBagBar', 'Bag bar')
	BTMover('BT4BarStanceBar', 'Stance Bar')
	BTMover('BT4BarPetBar', 'Pet Bar')
	BTMover('BT4BarMicroMenu', 'Micro menu')
	if SUI.IsRetail and _G['BT4BarQueueStatus'] then
		BTMover('BT4BarQueueStatus', 'Queue Status')
	end

	if not SUI.IsRetail and select(2, UnitClass('player')) == 'SHAMAN' and _G['MultiCastActionBarFrame'] then
		BTMover('MultiCastActionBarFrame', 'Totem Bar')
	end
end

local function OnInitialize()
	--Bartender4
	if not Bartender4 then
		return
	end
	--Update to the current profile
	SUI.DB.BT4Profile = Bartender4.db:GetCurrentProfile()
	Bartender4.db.RegisterCallback(SUI, 'OnProfileChanged', 'BT4RefreshConfig')
	Bartender4.db.RegisterCallback(SUI, 'OnProfileCopied', 'BT4RefreshConfig')
	Bartender4.db.RegisterCallback(SUI, 'OnProfileReset', 'BT4RefreshConfig')

	loadScales()
end

local function Options()
	local LDBIcon = LibStub('LibDBIcon-1.0')
	SUI.opt.args['General'].args['Bartender'] = {
		name = L['Bartender4'],
		type = 'group',
		order = 500,
		args = {
			MoveBars = {
				name = L['Move ActionBars'],
				type = 'execute',
				order = 1,
				func = function()
					Unlock()
				end,
			},
			ResetActionBars = {
				name = L['Reset ActionBars'],
				type = 'execute',
				order = 2,
				func = function()
					--Force Rebuild of primary bar profile
					SetupProfile()

					--Reset Scale
					module.DB.custom.scale.BT4 = {}

					--Reset Moved bars
					for _, v in ipairs(FrameList) do
						MoveIt:Reset(v)
					end

					--Force refresh
					RefreshConfig()
				end,
			},
			line1 = { name = '', type = 'header', order = 2.5 },
			LockButtons = {
				name = L['Lock Buttons'],
				type = 'toggle',
				order = 3,
				get = function(info)
					if Bartender4 then
						return Bartender4.db.profile.buttonlock
					else
						SUI.opt.args['Artwork'].args['Base'].args['LockButtons'].disabled = true
						return false
					end
				end,
				set = function(info, value)
					Bartender4.db.profile.buttonlock = value
					Bartender4.Bar:ForAll('ForAll', 'SetAttribute', 'buttonlock', value)
				end,
			},
			kb = {
				order = 4,
				type = 'execute',
				name = L['Key Bindings'],
				func = function()
					LibStub('LibKeyBound-1.0'):Toggle()
					AceConfigDialog:Close('Bartender4')
				end,
			},
			line2 = { name = '', type = 'header', order = 5.5 },
			VehicleUI = {
				name = L['Use Blizzard Vehicle UI'],
				type = 'toggle',
				order = 6,
				get = function(info)
					return SUI.DB.Artwork.VehicleUI
				end,
				set = function(info, val)
					if InCombatLockdown() then
						print(ERR_NOT_IN_COMBAT)
						return
					end
					SUI.DB.Artwork.VehicleUI = val
					--Make sure bartender knows to do it, or not...
					if Bartender4 then
						Bartender4.db.profile.blizzardVehicle = val
						Bartender4:UpdateBlizzardVehicle()
					end

					if SUI.DB.Artwork.VehicleUI then
						if SUI:GetModule('Style.' .. SUI.DB.Artwork.Style).SetupVehicleUI() ~= nil then
							SUI:GetModule('Style.' .. SUI.DB.Artwork.Style):SetupVehicleUI()
						end
					else
						if SUI:GetModule('Style.' .. SUI.DB.Artwork.Style).RemoveVehicleUI() ~= nil then
							SUI:GetModule('Style.' .. SUI.DB.Artwork.Style):RemoveVehicleUI()
						end
					end
				end,
			},
			minimapIcon = {
				order = 7,
				type = 'toggle',
				name = L['Minimap Icon'],
				get = function()
					return not Bartender4.db.profile.minimapIcon.hide
				end,
				set = function(info, value)
					Bartender4.db.profile.minimapIcon.hide = not value
					LDBIcon[value and 'Show' or 'Hide'](LDBIcon, 'Bartender4')
				end,
				disabled = function()
					return not LDBIcon
				end,
			},
		},
	}

	if Bartender4.options then
		for k, v in pairs(Bartender4.options.args.bars.args) do
			if v.args.position then
				v.args.position.hidden = true
			end
		end
	end

	-- Add to help screen
	SUI.opt.args.Help.args.SUIModuleHelp.args.ResetActionBars = SUI.opt.args.General.args.Bartender.args.ResetActionBars
end

local function OnCombatEnd()
	-- Handle deferred profile setup
	if module.profileSetupPending then
		SetupProfile()
	end

	-- Handle deferred config update
	if module.configUpdatePending and not InCombatLockdown() then
		-- Wrap in pcall to catch Bartender4/LibActionButton state errors
		local success, err = pcall(function()
			Bartender4:UpdateModuleConfigs()
		end)
		if not success and module.logger then
			module.logger.error('Bartender4 UpdateModuleConfigs failed: ' .. tostring(err))
			module.logger.info('This is usually caused by outdated Bartender4 version or LibActionButton state bugs')
		end
		module.configUpdatePending = false
	end
end

local function OnEnable()
	if not Bartender4 then
		return
	end

	-- Register combat lockdown handler for deferred operations
	module:RegisterEvent('PLAYER_REGEN_ENABLED', OnCombatEnd)
	-- No Bartender/out of date Notification
	if SUI.Bartender4Version < BartenderMin then
		-- TODO: Convert this away from Static popup
		-- Minimum version warning.
		StaticPopupDialogs['BartenderVerWarning'] = {
			text = '|cff33ff99SpartanUI v'
				.. SUI.Version
				.. '|n|r|n|n'
				.. L['Warning']
				.. ': '
				.. L['Your bartender version may be out of date. We detected Version']
				.. ' '
				.. SUI.Bartender4Version
				.. '|n|nSpartanUI requires '
				.. BartenderMin
				.. ' or higher.',
			button1 = 'Ok',
			OnAccept = function()
				SUI.DBG.BartenderVerWarning = SUI.Version
			end,
			timeout = 0,
			whileDead = true,
			hideOnEscape = false,
		}
		StaticPopup_Show('BartenderVerWarning')
	end

	if not module.DB.BT4Initalized then
		module.DB.BT4Initalized = true
		--Force Rebuild of primary bar profile
		if Bartender4.db:GetCurrentProfile() ~= BTProfileName and ProfileCheck(BTProfileName) then
			Bartender4.db:SetProfile(BTProfileName)
		else
			SetupProfile()
		end
	end

	-- Build options
	Options()

	-- Position & scale Bars
	RefreshConfig()

	-- Movement System
	AddMovers()

	-- Eventually this will not be needed until then port this over.
	if SUI:IsAddonDisabled('Bartender4') and not SUI.DB.BT4Warned then
		local cnt = 1
		local BT4Warning = CreateFrame('Frame')
		BT4Warning:SetScript('OnEvent', function()
			if cnt <= 10 then
				SUI.UI.Dialog(L['Warning'], L['Bartender4 not detected! Please download and install Bartender4.'] .. ' Warning ' .. cnt .. ' of 10')
			else
				SUI.DB.BT4Warned = true
			end
			cnt = cnt + 1
		end)
		BT4Warning:RegisterEvent('PLAYER_LOGIN')
		BT4Warning:RegisterEvent('PLAYER_ENTERING_WORLD')
		BT4Warning:RegisterEvent('ZONE_CHANGED')
		BT4Warning:RegisterEvent('ZONE_CHANGED_INDOORS')
		BT4Warning:RegisterEvent('ZONE_CHANGED_NEW_AREA')
	end

	--Disable BT4 Movement system
	function Bartender4:Unlock()
		-- print('Bartender4 movement system overridden by SpartanUI. Please use "/sui move" going forward.')
		Unlock()
	end

	function Bartender4:Lock() end

	-- Do what Bartender isn't - Make the Bag buttons the same size
	do -- modify CharacterBag(0-3) Scale
		for i = 1, 4 do
			_G['CharacterBag' .. (i - 1) .. 'Slot']:SetScale(1.25)
		end
	end

	--Replace the BT4 Enable function so we know when new objects are created
	local BT4ActionBars = Bartender4:GetModule('ActionBars')
	function BT4ActionBars:EnableBar(id)
		id = tonumber(id)
		local bar = self.actionbars[id]
		local config = self.db.profile.actionbars[id]
		config.enabled = true
		if not bar then
			bar = self:Create(id, config)
			self.actionbars[id] = bar
		else
			bar.disabled = nil
			self:CreateBarOption(id)
			bar:ApplyConfig(config)
		end

		--SUI Stuff
		RefreshConfig()
		local MoveIt = SUI:GetModule('MoveIt') ---@type MoveIt
		MoveIt:CreateMover(bar, bar:GetName(), 'Bar ' .. id, nil, 'Bartender4')
		MoveIt:UpdateMover(bar:GetName(), bar.overlay, true)

		if not Bartender4.Locked then
			bar:Unlock()
		end
	end
end

function SUI:BT4RefreshConfig()
	if BartenderChangesActive or not SUI.DB.SetupDone then
		return
	end

	SUI:Print('Bartender4 Profile changed to: ' .. Bartender4.db:GetCurrentProfile())
end

module:AddBarSystem('Bartender4', OnInitialize, OnEnable, nil, Unlock, RefreshConfig)
