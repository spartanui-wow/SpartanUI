local UF, L = SUI.UF, SUI.L
local timers = {}

---@param frame table
---@param DB table
local function Build(frame, DB)
	local unitName = frame.PName or frame.unit or frame:GetName()

	local flashColorOn = false
	local function Flash(self)
		local canAccess = SUI.BlizzAPI.canaccessvalue(self.Castbar.notInterruptible)
		local isInterruptible = canAccess and not self.Castbar.notInterruptible
		if isInterruptible and (self.Castbar.casting or self.Castbar.channeling) and self:IsVisible() then
			flashColorOn = not flashColorOn
			if flashColorOn then
				self.Castbar:SetStatusBarColor(1, 0, 0)
			else
				self.Castbar:SetStatusBarColor(1, 1, 0)
			end
			timers[unitName] = UF:ScheduleTimer(Flash, 0.1, self)
		end
	end

	-- Sync the non-interruptible overlay bar with the main castbar's timer
	local function SyncOverlay(castbar)
		local overlay = castbar.InterruptibleOverlay
		if not overlay then
			return
		end

		local duration = castbar:GetTimerDuration()
		if duration then
			overlay:SetTimerDuration(duration, castbar.smoothing)
		else
			local min, max = castbar:GetMinMaxValues()
			overlay:SetMinMaxValues(min, max)
			overlay:SetValue(castbar:GetValue())
		end
	end

	-- Frames where we show the interruptible overlay (enemy units)
	local isEnemyFrame = unitName == 'target' or unitName == 'focus' or unitName:match('^boss%d+$') or unitName:match('^arena%d+$')

	local overlayColorOn = false
	local function OverlayFlash(self)
		local castbar = self.Castbar
		if not castbar or not castbar.InterruptibleOverlay then
			return
		end
		if not (castbar.casting or castbar.channeling) or not self:IsVisible() then
			return
		end

		-- Toggle between interruptible color and transparent to create flash
		overlayColorOn = not overlayColorOn
		if overlayColorOn then
			castbar.InterruptibleOverlay:SetStatusBarColor(unpack(DB.interruptibleColor or { 0.7, 0, 0, 1 }))
		else
			castbar.InterruptibleOverlay:SetStatusBarColor(0, 0, 0, 0)
		end
		timers[unitName .. '_overlay'] = UF:ScheduleTimer(OverlayFlash, DB.InterruptSpeed or 0.1, self)
	end

	local function UpdateOverlay(self)
		if not self.InterruptibleOverlay or not SUI.IsRetail or not isEnemyFrame then
			return
		end

		-- Cancel previous overlay flash
		if timers[unitName .. '_overlay'] then
			UF:CancelTimer(timers[unitName .. '_overlay'])
			timers[unitName .. '_overlay'] = nil
		end

		-- Reset overlay to hidden and restore color
		self.InterruptibleOverlay:SetStatusBarColor(unpack(DB.interruptibleColor or { 0.7, 0, 0, 1 }))

		-- Alpha controlled by SetAlphaFromBoolean: notInterruptible=true -> alpha 0, false -> alpha 1
		-- This works even when notInterruptible is a secret boolean
		self.InterruptibleOverlay:SetAlphaFromBoolean(self.notInterruptible, 0, 1)
		SyncOverlay(self)

		-- Start the color flash on the overlay
		overlayColorOn = true
		timers[unitName .. '_overlay'] = UF:ScheduleTimer(OverlayFlash, DB.InterruptSpeed or 0.1, self.__owner)
	end

	local function PostCastStart(self, unit)
		UpdateOverlay(self)

		-- Interruptible flash on main bar color (only when we can confirm interruptible)
		local canAccess = SUI.BlizzAPI.canaccessvalue(self.notInterruptible)
		local isInterruptible = canAccess and not self.notInterruptible
		if isInterruptible and isEnemyFrame and DB.FlashOnInterruptible then
			self:SetStatusBarColor(0, 0, 0)
			timers[unitName] = UF:ScheduleTimer(Flash, DB.InterruptSpeed, self.__owner)
		else
			if DB.customColors and DB.customColors.useCustom then
				self:SetStatusBarColor(unpack(DB.customColors.barColor))
			else
				self:SetStatusBarColor(1, 0.7, 0)
			end
		end
	end
	local function PostCastInterruptible(self, unit)
		UpdateOverlay(self)
	end
	local function PostCastStop(self)
		if timers[unitName] then
			UF:CancelTimer(timers[unitName])
		end
		if timers[unitName .. '_overlay'] then
			UF:CancelTimer(timers[unitName .. '_overlay'])
		end
		-- Hide the overlay when cast ends
		if self.InterruptibleOverlay then
			self.InterruptibleOverlay:SetAlpha(0)
		end
	end

	local castLevel = DB.FrameLevel or 2

	local cast = CreateFrame('StatusBar', nil, frame)
	cast:SetFrameStrata(DB.FrameStrata or frame:GetFrameStrata())
	cast:SetFrameLevel(castLevel)
	cast:SetStatusBarTexture(UF:FindStatusBarTexture(DB.texture))
	cast:SetSize(DB.width or frame:GetWidth(), DB.height or 20)
	cast:SetPoint('TOP', frame, 'TOP', 0, DB.offset or 0)

	local bg = cast:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(cast)
	bg:SetTexture(UF:FindStatusBarTexture(DB.texture))
	bg:SetVertexColor(unpack(DB.bg.color))
	cast.bg = bg

	-- Interruptible overlay bar: sits above the main castbar
	-- Uses SetAlphaFromBoolean to show a different color when the cast CAN be interrupted
	if SUI.IsRetail then
		local overlay = CreateFrame('StatusBar', nil, cast)
		overlay:SetAllPoints(cast)
		overlay:SetFrameLevel(castLevel + 1)
		overlay:SetStatusBarTexture(UF:FindStatusBarTexture(DB.texture))
		overlay:SetStatusBarColor(unpack(DB.interruptibleColor or { 0.7, 0, 0, 1 }))
		overlay:SetAlpha(0)
		cast.InterruptibleOverlay = overlay
	end

	-- Top layer frame for text, shield, and icon so they render above the overlay bar
	local topLayer = CreateFrame('Frame', nil, cast)
	topLayer:SetAllPoints(cast)
	topLayer:SetFrameLevel(castLevel + 2)

	-- Add spell text
	local Text = topLayer:CreateFontString(nil, 'OVERLAY')
	SUI.Font:Format(Text, DB.text['1'].size, 'UnitFrames')
	Text:SetPoint(DB.text['1'].position.anchor, cast, DB.text['1'].position.anchor, DB.text['1'].position.x, DB.text['1'].position.y)
	cast.Text = Text

	-- Add a timer
	local Time = topLayer:CreateFontString(nil, 'OVERLAY')
	SUI.Font:Format(Time, DB.text['2'].size, 'UnitFrames')
	Time:SetPoint(DB.text['2'].position.anchor, cast, DB.text['2'].position.anchor, DB.text['2'].position.x, DB.text['2'].position.y)
	cast.Time = Time

	-- Shield frame sits above everything including threat borders
	local shieldLayer = CreateFrame('Frame', nil, cast)
	shieldLayer:SetAllPoints(cast)
	shieldLayer:SetFrameStrata('HIGH')
	shieldLayer:SetFrameLevel(castLevel + 50)

	-- Add Shield (interrupt protection icon)
	local Shield = shieldLayer:CreateTexture(nil, 'OVERLAY')
	Shield:SetSize(DB.Shield.size, DB.Shield.size * (17 / 15))
	if DB.Shield.attachToTimer then
		Shield:SetPoint('RIGHT', cast.Time, 'LEFT', DB.Shield.position.x, DB.Shield.position.y)
	else
		Shield:SetPoint(DB.Shield.position.anchor, cast, DB.Shield.position.anchor, DB.Shield.position.x, DB.Shield.position.y)
	end
	Shield:SetAtlas('UI-CastingBar-Shield')
	cast.Shield = Shield

	-- Add spell icon
	local Icon = topLayer:CreateTexture(nil, 'OVERLAY')
	Icon:SetSize(DB.Icon.size, DB.Icon.size)
	Icon:SetPoint(DB.Icon.position.anchor, cast, DB.Icon.position.anchor, DB.Icon.position.x, DB.Icon.position.y)
	cast.Icon = Icon

	-- Add safezone
	local SafeZone = cast:CreateTexture(nil, 'OVERLAY')
	cast.SafeZone = SafeZone

	-- Cast callbacks
	cast.PostCastStart = PostCastStart
	cast.PostCastInterruptible = PostCastInterruptible
	cast.PostCastStop = PostCastStop
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

	-- Interrupt protection shield (oUF controls visibility based on notInterruptible)
	if DB.interruptable then
		element.Shield:ClearAllPoints()
		element.Shield:SetSize(DB.Shield.size, DB.Shield.size * (17 / 15))
		if DB.Shield.attachToTimer then
			element.Shield:SetPoint('RIGHT', element.Time, 'LEFT', DB.Shield.position.x, DB.Shield.position.y)
		else
			element.Shield:SetPoint(DB.Shield.position.anchor, element, DB.Shield.position.anchor, DB.Shield.position.x, DB.Shield.position.y)
		end

		if SUI.IsRetail then
			-- Retail: oUF uses SetAlphaFromBoolean(notInterruptible, 1, 0)
			-- Widget must be Show()n for alpha changes to be visible
			element.Shield:Show()
			element.Shield:SetAlpha(0)
		else
			-- Classic: oUF uses SetShown(notInterruptible)
			-- Start hidden, oUF will Show() when cast is uninterruptible
			element.Shield:Hide()
		end
	else
		element.Shield:Hide()
	end

	-- Latency SafeZone (oUF populates during cast events for player unit)
	if element.SafeZone then
		if DB.latency then
			element.SafeZone:Show()
		else
			element.SafeZone:Hide()
		end
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

	-- Interruptible overlay bar
	if element.InterruptibleOverlay then
		element.InterruptibleOverlay:SetStatusBarTexture(UF:FindStatusBarTexture(DB.texture))
		element.InterruptibleOverlay:SetStatusBarColor(unpack(DB.interruptibleColor or { 0.7, 0, 0, 1 }))
	end

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

			if SUI.IsRetail then
				-- Retail 12.0+: Don't use SetUnit() - triggers forbidden table iteration
				-- SetUnit internally calls StopFinishAnims which iterates CastingBarTypeInfo
				-- with secret value keys, causing "forbidden table" errors
				castFrame:UnregisterAllEvents()
				castFrame:Hide()
				castFrame:HookScript('OnShow', function(self)
					self:Hide()
					self.showCastbar = false
				end)
			else
				-- Classic versions: SetUnit is safe and may be needed
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
			interruptibleColor = {
				name = L['Interruptible cast color'],
				desc = L['Color shown over the castbar when the spell can be interrupted'],
				type = 'color',
				hasAlpha = true,
				order = 22,
				get = function()
					return unpack(UF.CurrentSettings[frameName].elements.Castbar.interruptibleColor)
				end,
				set = function(_, r, g, b, a)
					local color = { r, g, b, a }
					UF.CurrentSettings[frameName].elements.Castbar.interruptibleColor = color
					UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements.Castbar.interruptibleColor = color
					UF.Unit[frameName]:UpdateAll()
				end,
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

	OptionSet.args.general.args.Shield = {
		name = L['Shield icon'],
		type = 'group',
		inline = true,
		order = 90,
		disabled = function()
			return not UF.CurrentSettings[frameName].elements.Castbar.interruptable
		end,
		get = function(info)
			return UF.CurrentSettings[frameName].elements.Castbar.Shield[info[#info]]
		end,
		set = function(info, val)
			UF.CurrentSettings[frameName].elements.Castbar.Shield[info[#info]] = val
			UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements.Castbar.Shield[info[#info]] = val
			UF.Unit[frameName]:UpdateAll()
		end,
		args = {
			attachToTimer = {
				name = L['Attach to timer text'],
				desc = L['Place the shield to the left of the cast timer. Keeps it inside the bar so artwork does not cover it.'],
				type = 'toggle',
				width = 'double',
				order = 1,
			},
			size = {
				name = L['Size'],
				type = 'range',
				min = 8,
				max = 40,
				step = 1,
				order = 5,
			},
			position = {
				name = L['Position'],
				type = 'group',
				order = 50,
				inline = true,
				get = function(info)
					return UF.CurrentSettings[frameName].elements.Castbar.Shield.position[info[#info]]
				end,
				set = function(info, val)
					UF.CurrentSettings[frameName].elements.Castbar.Shield.position[info[#info]] = val
					UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements.Castbar.Shield.position[info[#info]] = val
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
						desc = L['Only used when not attached to timer text'],
						type = 'select',
						order = 3,
						values = UF.Options.CONST.anchorPoints,
						disabled = function()
							return UF.CurrentSettings[frameName].elements.Castbar.Shield.attachToTimer
						end,
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
	interruptibleColor = { 0.7, 0, 0, 1 },
	Shield = {
		size = 19,
		attachToTimer = true,
		position = {
			anchor = 'RIGHT',
			x = -2,
			y = 0,
		},
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
