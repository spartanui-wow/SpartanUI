local SUI, L = SUI, SUI.L
---@class SUI.Module.AFKEffects : SUI.Module
local module = SUI:NewModule('AFKEffects')
module.DisplayName = L['AFK Effects']
module.description = 'Spin the camera around your character and apply some effects when AFK'
----------------------------------------
local isAFK = false
local SpinCamRunning = false
local Container
---@class AFKEffectsDB
local defaults = {
	SpinCam = {
		enabled = true,
		speed = 8,
	},
	FilmEffects = {
		enabled = true,
		animationInterval = 0.2,
		effects = {
			['**'] = {
				enabled = false,
			},
			vignette = {},
			blur = {},
			crisp = {},
		},
	},
}

----- Film Effects ----
local EffectList = { 'vignette', 'blur', 'crisp' }
local function EffectLoop()
	if not module.DB.FilmEffects.effects.blur.enabled and not module.DB.FilmEffects.effects.crisp.enabled then
		return
	end

	local yOfs = math.random(0, 256)
	local xOfs = math.random(-128, 0)

	if module.DB.FilmEffects.effects.blur.enabled or module.DB.FilmEffects.effects.crisp.enabled then
		Container:SetPoint('TOPLEFT', UIParent, 'TOPLEFT', xOfs, yOfs)
	end
end

local function BuildFilmEffects()
	Container = CreateFrame('Frame', 'FilmEffects', WorldFrame)
	Container:SetPoint('TOPLEFT', UIParent, 'TOPLEFT', 0, 0)
	Container:SetPoint('BOTTOMRIGHT', UIParent, 'BOTTOMRIGHT', 0, 0)
	Container:SetFrameStrata('BACKGROUND')

	-- vignette
	Container.vignette = Container:CreateTexture('FE_Vignette', 'OVERLAY')
	Container.vignette:SetAllPoints(UIParent)
	Container.vignette:SetTexture('Interface\\AddOns\\SpartanUI\\images\\FilmEffects\\vignette')
	Container.vignette:SetBlendMode('MOD')
	Container.vignette:Hide()

	-- blur
	Container.blur = CreateFrame('Frame', 'FG_Crispy', Container)
	Container.blur.layer1 = Container.blur:CreateTexture('FG_Fuzzy', 'OVERLAY')
	Container.blur.layer2 = Container.blur:CreateTexture('FG_Fuggly', 'OVERLAY')
	Container.blur.layer1:SetTexture('Interface\\AddOns\\SpartanUI\\images\\FilmEffects\\25ASA_Add')
	Container.blur.layer2:SetTexture('Interface\\AddOns\\SpartanUI\\images\\FilmEffects\\25ASA_Mod')
	Container.blur.layer1:SetBlendMode('ADD')
	Container.blur.layer2:SetBlendMode('MOD')
	Container.blur.layer1:SetAlpha(0.2)
	Container.blur.layer2:SetAlpha(0.05)
	Container.blur.layer1:SetAllPoints(UIParent)
	Container.blur.layer2:SetAllPoints(UIParent)
	Container.blur:Hide()

	-- crisp
	-- local x, y = strmatch(({GetScreenResolutions()})[GetCurrentResolution()], "(%d+)x(%d+)")
	local i = 1
	local ix = 1
	local iy = 1
	local xLimit = math.floor((tonumber(Container:GetWidth())) / 512 + 1)
	local yLimit = math.floor((tonumber(Container:GetHeight())) / 512 + 1)
	local iLimit = xLimit * yLimit
	local intensity = 1
	Container.crisp = CreateFrame('Frame', 'FG_Crispy', Container)
	while i <= iLimit do
		local nameAdd = 'FG_' .. ix .. '_' .. iy .. '_Add'
		local nameMod = 'FG_' .. ix .. '_' .. iy .. '_Mod'
		Container.crisp[nameAdd] = Container.crisp:CreateTexture(nameAdd, 'OVERLAY')
		Container.crisp[nameMod] = Container.crisp:CreateTexture(nameMod, 'OVERLAY')

		Container.crisp[nameAdd]:SetTexture('Interface\\AddOns\\SpartanUI_FilmEffects\\media\\25ASA_Add')
		Container.crisp[nameMod]:SetTexture('Interface\\AddOns\\SpartanUI_FilmEffects\\media\\25ASA_Mod')

		Container.crisp[nameAdd]:SetSize(512, 512)
		Container.crisp[nameMod]:SetSize(512, 512)

		Container.crisp[nameAdd]:SetBlendMode('ADD')
		Container.crisp[nameMod]:SetBlendMode('MOD')
		Container.crisp[nameAdd]:SetAlpha(intensity * 0.45)
		Container.crisp[nameMod]:SetAlpha(intensity * 0.3)

		local father, anchor
		father = _G['FG_' .. (ix - 1) .. '_' .. iy .. '_Add'] or _G['FG_' .. ix .. '_' .. (iy - 1) .. '_Add'] or Container

		if _G['FG_' .. (ix - 1) .. '_' .. iy .. '_Add'] then
			anchor = 'TOPRIGHT'
		elseif _G['FG_' .. ix .. '_' .. (iy - 1) .. '_Add'] then
			anchor = 'BOTTOMLEFT'
		else
			anchor = 'TOPLEFT'
		end

		Container.crisp[nameAdd]:SetPoint('TOPLEFT', father, anchor, 0, 0)
		Container.crisp[nameMod]:SetPoint('TOPLEFT', Container.crisp[nameAdd], 'TOPLEFT', 0, 0)

		ix = ix + 1
		if ix > xLimit then
			ix = 1
			iy = iy + 1
		end
		i = i + 1
	end

	Container.crisp:Hide()
end

local function StartEffects()
	for i, v in ipairs(EffectList) do
		if module.DB.FilmEffects.effects[v].enabled then
			Container[v]:Show()
		end
	end

	if module.DB.FilmEffects.effects.blur.enabled or module.DB.FilmEffects.effects.crisp.enabled then
		module:ScheduleRepeatingTimer(EffectLoop, module.DB.FilmEffects.animationInterval)
	end
end

local function StopEffects()
	for i, v in ipairs(EffectList) do
		Container[v]:Hide()
	end
	module:CancelAllTimers()
end

----- Spin Cam ----
local function StopSpin()
	if not SpinCamRunning then
		return
	end

	MoveViewRightStop()
	SpinCamRunning = false
end

local function StartSpin()
	MoveViewRightStart(module.DB.SpinCam.speed / 100)
	SpinCamRunning = true
end

----- Core ----
local function AFKToggle()
	if SUI:IsModuleDisabled(module) or SpinCamRunning then
		StopSpin()
		StopEffects()
	else
		if module.DB.SpinCam.enabled then
			StartSpin()
		end

		if module.DB.FilmEffects.enabled then
			StartEffects()
		end
	end
end

local function Options()
	local optTable = {
		name = L['AFK Effects'],
		type = 'group',
		get = function(info)
			return module.DB[info[#info]]
		end,
		disabled = function()
			return SUI:IsModuleDisabled(module)
		end,
		args = {
			toggle = {
				name = L['Toggle Effects'],
				type = 'execute',
				order = 2,
				-- width = 'double',
				func = function(info, val)
					if not SpinCamRunning then
						DEFAULT_CHAT_FRAME:AddMessage('|cff33ff99SpinCam|r: ' .. L['Spinning, to stop type /spin again'])
					end
					AFKToggle()
				end,
			},
			SpinCam = {
				name = L['Spin cam'],
				type = 'group',
				inline = true,
				get = function(info)
					return module.DB.SpinCam[info[#info]]
				end,
				set = function(info, val)
					module.DB.SpinCam[info[#info]] = val
					if module.DB.SpinCam.enabled then
						StartSpin()
					else
						StopSpin()
					end
				end,
				args = {
					enabled = {
						name = L['Enabled'],
						type = 'toggle',
						order = 1,
						width = 'double',
					},
					speed = {
						name = L['Spin speed'],
						type = 'range',
						order = 3,
						width = 'full',
						min = 1,
						max = 100,
						step = 1,
					},
				},
			},
			FilmEffects = {
				name = L['Film effects'],
				type = 'group',
				inline = true,
				get = function(info)
					return module.DB.FilmEffects[info[#info]]
				end,
				set = function(info, val)
					module.DB.FilmEffects[info[#info]] = val
				end,
				args = {
					enable = {
						name = L['Enable Film Effects'],
						type = 'toggle',
						order = 1,
						width = 'full',
					},
					effects = {
						name = L['Effects'],
						type = 'group',
						inline = true,
						get = function(info)
							return module.DB.FilmEffects.effects[info[#info - 1]][info[#info]]
						end,
						set = function(info, val)
							module.DB.FilmEffects.effects[info[#info - 1]][info[#info]] = val
						end,
						args = {},
					},
				},
			},
		},
	}

	for k, v in ipairs(EffectList) do
		optTable.args.FilmEffects.args.effects.args[v] = {
			name = L[v],
			type = 'group',
			inline = true,
			args = {
				enabled = {
					name = L['Enabled'],
					type = 'toggle',
					order = 1,
					width = 'double',
				},
			},
		}
	end
	SUI.Options:AddOptions(optTable, 'AFKEffects')
end

function module:PLAYER_ENTERING_WORLD()
	if SUI:IsModuleDisabled(module) then
		module:UnregisterEvent('PLAYER_ENTERING_WORLD')
	end

	StopSpin()
end

-- Retail: Use PLAYER_FLAGS_CHANGED to avoid secret value issues
function module:PLAYER_FLAGS_CHANGED()
	if SUI:IsModuleDisabled(module) then
		module:UnregisterEvent('PLAYER_FLAGS_CHANGED')
		StopSpin()
		return
	end

	-- WoW 12.0.0: Use UnitIsAFK instead of chat messages to avoid secret value issues
	local playerIsAFK = UnitIsAFK('player')

	if playerIsAFK and not isAFK then
		-- Player just went AFK
		isAFK = true
		if module.DB.SpinCam.enabled then
			StartSpin()
		end
		if module.DB.FilmEffects.enabled then
			StartEffects()
		end
	elseif not playerIsAFK and isAFK then
		-- Player is no longer AFK
		isAFK = false
		StopSpin()
		StopEffects()
	end
end

function module:CHAT_MSG_SYSTEM(_, ...)
	if SUI:IsModuleDisabled(module) then
		module:UnregisterEvent('CHAT_MSG_SYSTEM')
		StopSpin()
		return
	end

	if module.DB.SpinCam.enabled and (... == format(MARKED_AFK_MESSAGE, DEFAULT_AFK_MESSAGE)) then
		StartSpin()
	elseif ... == CLEARED_AFK then
		StopSpin()
	end

	if module.DB.FilmEffects.enabled and (... == format(MARKED_AFK_MESSAGE, DEFAULT_AFK_MESSAGE)) then
		StartEffects()
	elseif ... == CLEARED_AFK then
		StopEffects()
	end
end

function module:OnInitialize()
	module.Database = SUI.SpartanUIDB:RegisterNamespace('AFKEffects', { profile = defaults })
	module.DB = module.Database.profile ---@type AFKEffectsDB

	-- Register profile change callbacks
	SUI.DBM:RegisterSequentialProfileRefresh(module)

	--If speed is less than 1 reset it
	if module.DB.SpinCam.speed < 1 then
		module.DB.SpinCam.speed = module.DB.SpinCam.speed * 100
	end
end

function module:OnEnable()
	Options()
	if SUI:IsModuleDisabled(module) then
		return
	end

	BuildFilmEffects()
	if SUI.IsRetail then
		module:RegisterEvent('PLAYER_FLAGS_CHANGED')
	else
		---@diagnostic disable-next-line: missing-parameter
		module:RegisterEvent('CHAT_MSG_SYSTEM')
	end
	---@diagnostic disable-next-line: missing-parameter
	module:RegisterEvent('PLAYER_ENTERING_WORLD')

	local ChatCommand = function()
		if not SpinCamRunning then
			DEFAULT_CHAT_FRAME:AddMessage('|cff33ff99SpinCam|r: ' .. L['Spinning, to stop type /spin again'])
		end
		AFKToggle()
	end
	SUI:AddChatCommand('spin', ChatCommand, 'Toggles the Spincam', nil, true)
end
