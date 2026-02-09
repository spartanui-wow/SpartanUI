local UF, L = SUI.UF, SUI.L
local timers = {}

---@param frame table
---@param DB table
local function Build(frame, DB)
	local unitName = frame.PName or frame.unit or frame:GetName()

	local function Flash(self)
		-- WoW 12.0.0: notInterruptible can be a secret value, use truthy check instead of == false
		if (self.Castbar.casting or self.Castbar.channeling) and not self.Castbar.notInterruptible and self:IsVisible() then
			local _, g, b = self.Castbar:GetStatusBarColor()
			if b ~= 0 and g ~= 0 then
				self.Castbar:SetStatusBarColor(1, 0, 0)
			elseif b == 0 and g == 0 then
				self.Castbar:SetStatusBarColor(1, 1, 0)
			else
				-- Reset to custom color if enabled, otherwise use default
				if DB.customColors and DB.customColors.useCustom then
					self.Castbar:SetStatusBarColor(unpack(DB.customColors.barColor))
				else
					self.Castbar:SetStatusBarColor(1, 1, 1)
				end
			end
			timers[unitName] = UF:ScheduleTimer(Flash, 0.1, self)
		end
	end
	local function PostCastStart(self, unit)
		-- WoW 12.0.0: notInterruptible can be a secret value, use truthy check instead of == false
		if not self.notInterruptible and DB.FlashOnInterruptible and UnitIsEnemy('player', unit) then
			self:SetStatusBarColor(0, 0, 0)
			timers[unitName] = UF:ScheduleTimer(Flash, DB.InterruptSpeed, self.__owner)
		else
			-- Use custom color if enabled, otherwise use default
			if DB.customColors and DB.customColors.useCustom then
				self:SetStatusBarColor(unpack(DB.customColors.barColor))
			else
				self:SetStatusBarColor(1, 0.7, 0)
			end
		end
	end
	local function PostCastStop(self)
		if timers[unitName] then
			UF:CancelTimer(timers[unitName])
		end
	end

	local cast = CreateFrame('StatusBar', nil, frame)
	cast:SetFrameStrata(DB.FrameStrata or frame:GetFrameStrata())
	cast:SetFrameLevel(DB.FrameLevel or 2)
	cast:SetStatusBarTexture(UF:FindStatusBarTexture(DB.texture))
	cast:SetSize(DB.width or frame:GetWidth(), DB.height or 20)
	cast:SetPoint('TOP', frame, 'TOP', 0, DB.offset or 0)

	local bg = cast:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(cast)
	bg:SetTexture(UF:FindStatusBarTexture(DB.texture))
	bg:SetVertexColor(unpack(DB.bg.color))
	cast.bg = bg

	-- Add spell text
	local Text = cast:CreateFontString()
	SUI.Font:Format(Text, DB.text['1'].size, 'UnitFrames')
	Text:SetPoint(DB.text['1'].position.anchor, cast, DB.text['1'].position.anchor, DB.text['1'].position.x, DB.text['1'].position.y)
	cast.Text = Text

	-- Add a timer
	local Time = cast:CreateFontString(nil, 'OVERLAY')
	SUI.Font:Format(Time, DB.text['2'].size, 'UnitFrames')
	Time:SetPoint(DB.text['2'].position.anchor, cast, DB.text['2'].position.anchor, DB.text['2'].position.x, DB.text['2'].position.y)
	cast.Time = Time

	-- Add Shield
	local Shield = cast:CreateTexture(nil, 'OVERLAY')
	Shield:SetSize(20, 20)
	Shield:SetPoint('CENTER', cast, 'RIGHT')
	Shield:SetTexture([[Interface\CastingBar\UI-CastingBar-Small-Shield]])
	cast.Shield = Shield

	-- Add spell icon
	local Icon = cast:CreateTexture(nil, 'OVERLAY')
	Icon:SetSize(DB.Icon.size, DB.Icon.size)
	Icon:SetPoint(DB.Icon.position.anchor, cast, DB.Icon.position.anchor, DB.Icon.position.x, DB.Icon.position.y)
	cast.Icon = Icon

	-- Add safezone
	local SafeZone = cast:CreateTexture(nil, 'OVERLAY')
	cast.SafeZone = SafeZone

	-- --Interupt Flash
	if not SUI.IsRetail then
		cast.PostCastStart = PostCastStart
		cast.PostCastInterruptible = PostCastStart
		cast.PostCastStop = PostCastStop
	end
	cast.TextElements = {
		['1'] = cast.Text,
		['2'] = cast.Time,
	}

	frame.Castbar = cast
end

---@param frame table
---@param settings? table
local function Update(frame, settings)
	local element = frame.Castbar
	local DB = settings or element.DB ---@type SUI.UF.Elements.Settings.Castbar
	if not DB.enabled then
		element:Hide()
		return
	end

	-- latency
	if DB.latency then
		element.Shield:Show()
	else
		element.Shield:Hide()
	end

	-- spell name
	if DB.text['1'].enabled then
		element.Text:Show()
	else
		element.Text:Hide()
	end
	-- spell timer
	if DB.text['2'].enabled then
		element.Time:Show()
	else
		element.Time:Hide()
	end

	-- Basic Bar updates
	element:SetStatusBarTexture(UF:FindStatusBarTexture(DB.texture))
	element.bg:SetTexture(UF:FindStatusBarTexture(DB.texture))

	-- Set background color (class color or custom color)
	if DB.bg.useClassColor then
		local color = (_G.CUSTOM_CLASS_COLORS and _G.CUSTOM_CLASS_COLORS[select(2, UnitClass('player'))]) or _G.RAID_CLASS_COLORS[select(2, UnitClass('player'))]
		local alpha = DB.bg.classColorAlpha or 0.2
		if color then
			element.bg:SetVertexColor(color.r, color.g, color.b, alpha)
		else
			element.bg:SetVertexColor(1, 1, 1, alpha)
		end
	else
		element.bg:SetVertexColor(unpack(DB.bg.color or { 1, 1, 1, 0.2 }))
	end

	for i, key in pairs(DB.text) do
		if element.TextElements[i] then
			local TextElement = element.TextElements[i]
			TextElement:SetJustifyH(key.SetJustifyH)
			TextElement:SetJustifyV(key.SetJustifyV)
			TextElement:ClearAllPoints()
			TextElement:SetPoint(key.position.anchor, element, key.position.anchor, key.position.x, key.position.y)
			-- Don't apply tags to castbar TextElements as they are built-in elements (cast.Text, cast.Time)
			-- that already have their own functionality

			if key.enabled then
				TextElement:Show()
			else
				TextElement:Hide()
			end
		end
	end

	element:ClearAllPoints()
	element:SetSize(DB.width or frame:GetWidth(), DB.height or 20)
	element:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, DB.offset or 0)
	element:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, DB.offset or 0)

	-- Spell icon
	if DB.Icon.enabled then
		element.Icon:Show()
	else
		element.Icon:Hide()
	end
	element.Icon:ClearAllPoints()
	element.Icon:SetPoint(DB.Icon.position.anchor, element, DB.Icon.position.anchor, DB.Icon.position.x, DB.Icon.position.y)
	element.Icon:SetSize(DB.Icon.size, DB.Icon.size)

	if frame.unitOnCreate == 'player' then
		-- Helper function to hide a castbar frame
		local function HideCastbar(castFrame, frameName)
			if not castFrame then
				return
			end
			if SUI.logger then
				SUI.logger.debug('Hiding Blizzard castbar: ' .. (frameName or 'unknown'))
			end
			castFrame.showCastbar = false
			-- SetUnit doesn't exist in Classic
			if castFrame.SetUnit then
				castFrame:SetUnit(nil)
			end
			castFrame:UnregisterAllEvents()
			castFrame:Hide()
			castFrame:HookScript('OnShow', function(self)
				self:Hide()
				self.showCastbar = false
				if self.SetUnit then
					self:SetUnit(nil)
				end
			end)
		end

		-- EditModeManagerFrame.AccountSettings is Retail-only (10.0+)
		if EditModeManagerFrame and EditModeManagerFrame.AccountSettings then
			function EditModeManagerFrame.AccountSettings.SettingsContainer.CastBar:ShouldEnable()
				return false
			end
		end

		-- MOP Classic Edit Mode castbar handling
		-- MOP uses EditModeManagerFrame but may have different structure
		if SUI.IsMOP and EditModeManagerFrame then
			if SUI.logger then
				SUI.logger.debug('MOP Edit Mode detected, attempting to disable castbar')
			end
			-- Try to disable via EditMode settings if available
			if EditModeManagerFrame.GetSettingValue then
				-- Hook into the setting getter to always return disabled for castbar
				local origGetSettingValue = EditModeManagerFrame.GetSettingValue
				EditModeManagerFrame.GetSettingValue = function(self, setting, ...)
					if setting and tostring(setting):find('CastBar') then
						return false
					end
					return origGetSettingValue(self, setting, ...)
				end
			end
		end

		-- Retail/Modern frame names
		for _, k in ipairs({ 'PlayerCastingBarFrame', 'PetCastingBarFrame' }) do
			HideCastbar(_G[k], k)
		end

		-- Classic-specific castbar frames (Classic/TBC/Wrath/Cata/MOP)
		HideCastbar(_G['CastingBarFrame'], 'CastingBarFrame')

		-- MOP may also use these frame names
		HideCastbar(_G['PlayerCastBar'], 'PlayerCastBar')
		HideCastbar(_G['CastingBar'], 'CastingBar')
	end
end

---@param frameName string
---@param OptionSet AceConfig.OptionsTable
local function Options(frameName, OptionSet)
	OptionSet.args.general = {
		name = '',
		type = 'group',
		inline = true,
		args = {
			FlashOnInterruptible = {
				name = L['Flash on interruptible cast'],
				type = 'toggle',
				width = 'double',
				order = 10,
			},
			InterruptSpeed = {
				name = L['Interrupt flash speed'],
				type = 'range',
				width = 'double',
				min = 0.01,
				max = 1,
				step = 0.01,
				order = 11,
			},
			interruptable = {
				name = L['Show interrupt or spell steal'],
				type = 'toggle',
				width = 'double',
				order = 20,
			},
			latency = {
				name = L['Show latency'],
				type = 'toggle',
				order = 21,
			},
			Icon = {
				name = L['Spell icon'],
				type = 'group',
				inline = true,
				order = 100,
				get = function(info)
					return UF.CurrentSettings[frameName].elements.Castbar.Icon[info[#info]]
				end,
				set = function(info, val)
					--Update memory
					UF.CurrentSettings[frameName].elements.Castbar.Icon[info[#info]] = val
					--Update the DB
					UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements.Castbar.Icon[info[#info]] = val
					--Update the screen
					UF.Unit[frameName]:UpdateAll()
				end,
				args = {
					enabled = {
						name = L['Enable'],
						type = 'toggle',
						order = 1,
					},
					size = {
						name = L['Size'],
						type = 'range',
						min = 0,
						max = 100,
						step = 0.1,
						order = 5,
					},
					position = {
						name = L['Position'],
						type = 'group',
						order = 50,
						inline = true,
						get = function(info)
							return UF.CurrentSettings[frameName].elements.Castbar.Icon.position[info[#info]]
						end,
						set = function(info, val)
							--Update memory
							UF.CurrentSettings[frameName].elements.Castbar.Icon.position[info[#info]] = val
							--Update the DB
							UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements.Castbar.Icon.position[info[#info]] = val
							--Update Screen
							UF.Unit[frameName]:UpdateAll()
						end,
						args = {
							x = {
								name = L['X Axis'],
								type = 'range',
								order = 1,
								min = -100,
								max = 100,
								step = 1,
							},
							y = {
								name = L['Y Axis'],
								type = 'range',
								order = 2,
								min = -100,
								max = 100,
								step = 1,
							},
							anchor = {
								name = L['Anchor point'],
								type = 'select',
								order = 3,
								values = UF.Options.CONST.anchorPoints,
							},
						},
					},
				},
			},
		},
	}

	if frameName == 'player' or frameName == 'party' or frameName == 'raid' then
		OptionSet.args.general.args.interruptable.hidden = true
	end

	UF.Options:AddDynamicText(frameName, OptionSet, 'Castbar')
end

---@class SUI.UF.Elements.Settings.Castbar : SUI.UF.Elements.Settings
local Settings = {
	enabled = false,
	height = 10,
	width = false,
	FrameStrata = 'BACKGROUND',
	interruptable = true,
	FlashOnInterruptible = true,
	latency = false,
	InterruptSpeed = 0.1,
	bg = {
		enabled = true,
		color = { 1, 1, 1, 0.2 },
		useClassColor = false,
		classColorAlpha = 0.2,
	},
	customColors = {
		useCustom = false,
		barColor = { 1, 0.7, 0, 1 },
	},
	Icon = {
		enabled = true,
		size = 12,
		position = {
			anchor = 'LEFT',
			x = 0,
			y = 0,
		},
	},
	text = {
		['1'] = {
			enabled = true,
			text = '', -- Castbar Text element handles spell name automatically
			position = {
				anchor = 'CENTER',
				x = 0,
				y = 0,
			},
		},
		['2'] = {
			enabled = true,
			text = '', -- Castbar Time element handles timer automatically
			size = 8,
			position = {
				anchor = 'RIGHT',
				x = 0,
				y = 0,
			},
		},
	},
	position = {
		anchor = 'TOP',
	},
	config = {
		type = 'StatusBar',
	},
}
UF.Elements:Register('Castbar', Build, Update, Options, Settings)
