local UF, L = SUI.UF, SUI.L

---@param frame table
---@param DB table
local function Build(frame, DB)
	local health = CreateFrame('StatusBar', nil, frame)
	health:SetFrameStrata(DB.FrameStrata or frame:GetFrameStrata())
	health:SetFrameLevel(DB.FrameLevel or 2)
	health:SetStatusBarTexture(UF:FindStatusBarTexture(DB.texture))
	health:SetSize(DB.width or frame:GetWidth(), DB.height or 20)

	local bg = health:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(health)
	bg:SetTexture(UF:FindStatusBarTexture(DB.texture))
	bg:SetVertexColor(unpack(DB.bg.color))
	health.bg = bg

	health:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, DB.offset or -1)
	health:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, DB.offset or -1)

	health.TextElements = {}
	for i, key in pairs(DB.text) do
		local NewString = health:CreateFontString(nil, 'OVERLAY')
		NewString:SetDrawLayer('OVERLAY', 7) -- Ensure text is above all bars
		SUI.Font:Format(NewString, key.size or 5, 'UnitFrames')
		NewString:SetJustifyH(key.SetJustifyH)
		NewString:SetJustifyV(key.SetJustifyV)
		NewString:SetPoint(key.position.anchor, health, key.position.anchor, key.position.x, key.position.y)
		frame:Tag(NewString, key.text)

		health.TextElements[i] = NewString
		if not key.enabled then
			health.TextElements[i]:Hide()
		end
	end

	frame.Health = health

	-- Cutaway Health: Ghost bar showing recently lost health
	local tempLoss = CreateFrame('StatusBar', nil, frame.Health)
	tempLoss:SetFrameLevel((DB.FrameLevel or 4) + 1) -- Above health bar
	tempLoss:SetStatusBarTexture(UF:FindStatusBarTexture(DB.texture))
	tempLoss:SetPoint('TOP', frame.Health, 'TOP')
	tempLoss:SetPoint('BOTTOM', frame.Health, 'BOTTOM')
	tempLoss:SetPoint('LEFT', frame.Health:GetStatusBarTexture(), 'LEFT')
	tempLoss:SetPoint('RIGHT', frame.Health:GetStatusBarTexture(), 'RIGHT')

	-- Color: dark red ghost
	tempLoss:SetStatusBarColor(0.5, 0, 0, 0.5)
	tempLoss:SetAlpha(0) -- Start invisible
	tempLoss:Hide()

	-- Create fade animation
	local fadeGroup = tempLoss:CreateAnimationGroup()
	local fadeAnim = fadeGroup:CreateAnimation('Alpha')
	fadeAnim:SetFromAlpha(0.5)
	fadeAnim:SetToAlpha(0)
	fadeAnim:SetDuration(0.75) -- 750ms fade
	fadeAnim:SetSmoothing('OUT')
	fadeGroup:SetScript('OnFinished', function()
		tempLoss:Hide()
		tempLoss:SetAlpha(0)
	end)

	tempLoss.fadeGroup = fadeGroup
	frame.Health.tempLoss = tempLoss

	-- PostUpdate callback for cutaway health effect
	frame.Health.PostUpdate = function(element, unit, cur, max)
		local DB = element.DB
		if not DB or not DB.cutaway or not DB.cutaway.enabled then
			return
		end

		local tempLoss = element.tempLoss
		if not tempLoss then
			return
		end

		-- Track previous health
		local prev = element.previousHealth or cur
		element.previousHealth = cur

		-- Check if health decreased (damage taken)
		if cur < prev and max > 0 then
			local damage = prev - cur

			-- Only show for significant damage (more than 1% of max health)
			if damage > (max * 0.01) then
				-- Stop any existing animation
				if tempLoss.fadeGroup:IsPlaying() then
					tempLoss.fadeGroup:Stop()
				end

				-- Set the ghost bar to show the lost health
				tempLoss:SetMinMaxValues(0, max)
				tempLoss:SetValue(prev) -- Show where health was before damage

				-- Apply custom color if configured
				if DB.cutaway.color then
					tempLoss:SetStatusBarColor(unpack(DB.cutaway.color))
				end

				-- Show and start fade animation
				tempLoss:Show()
				tempLoss:SetAlpha(0.5) -- Reset alpha
				tempLoss.fadeGroup:Play()
			end
		end
	end

	frame.Health.frequentUpdates = true
	frame.Health.colorDisconnected = DB.colorDisconnected or true
	frame.Health.colorTapping = DB.colorTapping or true
	frame.Health.colorReaction = DB.colorReaction or true
	frame.Health.colorSmooth = DB.colorSmooth or true
	frame.Health.colorClass = DB.colorClass or false

	frame.colors.smooth = { 1, 0, 0, 1, 1, 0, 0, 1, 0 }
	frame.Health.colorHealth = true

	frame.Health.DataTable = DB.text

	-- Incoming heals bar (combined heals from all sources)
	-- Note: Width is dynamically set by oUF's UpdateSize based on Health bar dimensions
	local healingAll = CreateFrame('StatusBar', nil, frame.Health)
	healingAll:SetFrameLevel((DB.FrameLevel or 2) + 2)
	healingAll:SetPoint('TOP', frame.Health, 'TOP')
	healingAll:SetPoint('BOTTOM', frame.Health, 'BOTTOM')
	healingAll:SetPoint('LEFT', frame.Health:GetStatusBarTexture(), 'RIGHT')
	healingAll:SetStatusBarTexture(UF:FindStatusBarTexture(DB.healPredictionTexture or 'Blizzard'))
	if DB.customColors and DB.customColors.useCustom and DB.customColors.healPredictionColor then
		healingAll:SetStatusBarColor(unpack(DB.customColors.healPredictionColor))
	else
		healingAll:SetStatusBarColor(0.0, 0.659, 0.608, 0.7) -- Blizzard's teal-green heal color
	end
	healingAll:SetWidth(200) -- Initial width, will be resized by oUF

	-- Damage absorb bar (shields like Power Word: Shield)
	local damageAbsorb = CreateFrame('StatusBar', nil, frame.Health)
	damageAbsorb:SetFrameLevel((DB.FrameLevel or 2) + 3)
	damageAbsorb:SetPoint('TOP', frame.Health, 'TOP')
	damageAbsorb:SetPoint('BOTTOM', frame.Health, 'BOTTOM')
	damageAbsorb:SetPoint('LEFT', healingAll:GetStatusBarTexture(), 'RIGHT')
	damageAbsorb:SetStatusBarTexture(UF:FindStatusBarTexture(DB.absorbTexture or 'Blizzard Shield'))
	if DB.customColors and DB.customColors.useCustom and DB.customColors.absorbColor then
		damageAbsorb:SetStatusBarColor(unpack(DB.customColors.absorbColor))
	else
		damageAbsorb:SetStatusBarColor(1, 1, 1, 0.8) -- White tint to show the shield texture
	end
	damageAbsorb:SetWidth(200) -- Initial width, will be resized by oUF

	-- Heal absorb bar (effects that absorb incoming healing, like Necrotic Strike)
	local healAbsorb = CreateFrame('StatusBar', nil, frame.Health)
	healAbsorb:SetFrameLevel((DB.FrameLevel or 2) + 3)
	healAbsorb:SetPoint('TOP', frame.Health, 'TOP')
	healAbsorb:SetPoint('BOTTOM', frame.Health, 'BOTTOM')
	healAbsorb:SetPoint('RIGHT', frame.Health:GetStatusBarTexture())
	healAbsorb:SetStatusBarTexture(UF:FindStatusBarTexture(DB.healAbsorbTexture or 'Blizzard Absorb'))
	if DB.customColors and DB.customColors.useCustom and DB.customColors.healAbsorbColor then
		healAbsorb:SetStatusBarColor(unpack(DB.customColors.healAbsorbColor))
	else
		healAbsorb:SetStatusBarColor(0.7, 0.0, 0.3, 0.8) -- Reddish-purple for heal absorbs
	end
	healAbsorb:SetReverseFill(true)
	healAbsorb:SetWidth(200) -- Initial width, will be resized by oUF

	-- Overflow indicator for damage absorbs (when absorb exceeds display area)
	-- Uses Blizzard's Shield-Overshield glow texture with ADD blend mode
	local overDamageAbsorbIndicator = frame.Health:CreateTexture(nil, 'ARTWORK', nil, 2)
	overDamageAbsorbIndicator:SetPoint('TOP', frame.Health, 'TOP')
	overDamageAbsorbIndicator:SetPoint('BOTTOM', frame.Health, 'BOTTOM')
	overDamageAbsorbIndicator:SetPoint('LEFT', frame.Health, 'RIGHT', -4, 0)
	overDamageAbsorbIndicator:SetWidth(8)
	overDamageAbsorbIndicator:SetTexture([[Interface\RaidFrame\Shield-Overshield]])
	overDamageAbsorbIndicator:SetBlendMode('ADD')

	-- Overflow indicator for heal absorbs
	-- Uses Blizzard's Absorb-Overabsorb glow texture with ADD blend mode
	local overHealAbsorbIndicator = frame.Health:CreateTexture(nil, 'ARTWORK', nil, 2)
	overHealAbsorbIndicator:SetPoint('TOP', frame.Health, 'TOP')
	overHealAbsorbIndicator:SetPoint('BOTTOM', frame.Health, 'BOTTOM')
	overHealAbsorbIndicator:SetPoint('RIGHT', frame.Health, 'LEFT', 4, 0)
	overHealAbsorbIndicator:SetWidth(8)
	overHealAbsorbIndicator:SetTexture([[Interface\RaidFrame\Absorb-Overabsorb]])
	overHealAbsorbIndicator:SetBlendMode('ADD')

	-- Build HealthPrediction table using Retail 12.0+ property names
	-- oUF_Classic handles translation to Classic APIs internally
	frame.HealthPrediction = {
		healingAll = healingAll, -- Combined incoming heals (player + others)
		damageAbsorb = damageAbsorb, -- Damage absorb shields
		healAbsorb = healAbsorb, -- Heal absorb effects
		overDamageAbsorbIndicator = overDamageAbsorbIndicator,
		overHealAbsorbIndicator = overHealAbsorbIndicator,
		incomingHealOverflow = 1.05,
	}
end

---@param frame table
---@param settings? table
local function Update(frame, settings)
	local element = frame.Health
	local DB = settings or element.DB

	--Update Health items
	element.colorDisconnected = DB.colorDisconnected
	element.colorTapping = DB.colorTapping
	element.colorReaction = DB.colorReaction
	element.colorSmooth = DB.colorSmooth
	element.colorClass = DB.colorClass

	-- Handle custom coloring
	if DB.customColors and DB.customColors.useCustom then
		-- Disable automatic coloring when using custom colors
		element.colorDisconnected = false
		element.colorTapping = false
		element.colorReaction = false
		element.colorSmooth = false
		element.colorClass = false
		element.colorHealth = false
		-- Set custom color
		element:SetStatusBarColor(unpack(DB.customColors.barColor))
	else
		-- Enable automatic coloring
		element.colorHealth = true
	end

	-- Set reverse fill direction
	element:SetReverseFill(DB.reverseFill or false)

	-- Set smooth animation (Retail hardware smoothing)
	if SUI.IsRetail and DB.smoothAnimation then
		element.smoothing = Enum.StatusBarInterpolation.Linear
	else
		element.smoothing = nil -- Disable hardware smoothing if turned off or on Classic
	end

	element:SetStatusBarTexture(UF:FindStatusBarTexture(DB.texture))
	element.bg:SetTexture(UF:FindStatusBarTexture(DB.texture))

	-- Set background color (class color or custom color)
	if DB.bg.useClassColor then
		local unit = frame.unit or frame.unitOnCreate or 'player'
		local _, class = UnitClass(unit)
		local color = (_G.CUSTOM_CLASS_COLORS and _G.CUSTOM_CLASS_COLORS[class]) or _G.RAID_CLASS_COLORS[class]
		local alpha = DB.bg.classColorAlpha or 0.2
		if color then
			element.bg:SetVertexColor(color.r, color.g, color.b, alpha)
		else
			element.bg:SetVertexColor(1, 1, 1, alpha)
		end
	else
		element.bg:SetVertexColor(unpack(DB.bg.color or { 1, 1, 1, 0.2 }))
	end

	-- Update HealthPrediction bar textures and colors
	if frame.HealthPrediction then
		local healingAll = frame.HealthPrediction.healingAll
		local damageAbsorb = frame.HealthPrediction.damageAbsorb
		local healAbsorb = frame.HealthPrediction.healAbsorb

		if healingAll then
			healingAll:SetStatusBarTexture(UF:FindStatusBarTexture(DB.healPredictionTexture or 'Blizzard'))
			if DB.customColors and DB.customColors.useCustom and DB.customColors.healPredictionColor then
				healingAll:SetStatusBarColor(unpack(DB.customColors.healPredictionColor))
			else
				-- Blizzard default: teal-green heal prediction color
				healingAll:SetStatusBarColor(0.0, 0.659, 0.608, 0.7)
			end
		end
		if damageAbsorb then
			damageAbsorb:SetStatusBarTexture(UF:FindStatusBarTexture(DB.absorbTexture or 'Blizzard Shield'))
			if DB.customColors and DB.customColors.useCustom and DB.customColors.absorbColor then
				damageAbsorb:SetStatusBarColor(unpack(DB.customColors.absorbColor))
			else
				-- Blizzard default: white tint to show shield texture
				damageAbsorb:SetStatusBarColor(1, 1, 1, 0.8)
			end
		end
		if healAbsorb then
			healAbsorb:SetStatusBarTexture(UF:FindStatusBarTexture(DB.healAbsorbTexture or 'Blizzard Absorb'))
			if DB.customColors and DB.customColors.useCustom and DB.customColors.healAbsorbColor then
				healAbsorb:SetStatusBarColor(unpack(DB.customColors.healAbsorbColor))
			else
				-- Blizzard default: reddish-purple for heal absorbs
				healAbsorb:SetStatusBarColor(0.7, 0.0, 0.3, 0.8)
			end
		end
	end

	for i, key in pairs(DB.text) do
		if element.TextElements[i] then
			local TextElement = element.TextElements[i]
			TextElement:SetDrawLayer('OVERLAY', 7) -- Ensure text is above all bars
			TextElement:SetJustifyH(key.SetJustifyH)
			TextElement:SetJustifyV(key.SetJustifyV)
			TextElement:ClearAllPoints()
			TextElement:SetPoint(key.position.anchor, element, key.position.anchor, key.position.x, key.position.y)
			frame:Tag(TextElement, key.text)

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
end

---@param frameName string
---@param OptionSet AceConfig.OptionsTable
local function Options(frameName, OptionSet)
	OptionSet.args.general = {
		name = '',
		type = 'group',
		inline = true,
		args = {
			reverseFill = {
				name = L['Reverse fill direction'],
				desc = L['Make the health bar fill right-to-left instead of left-to-right. Warning: This may be confusing for most players and is primarily used for specific UI aesthetics.'],
				type = 'toggle',
				order = 1,
			},
			smoothAnimation = {
				name = L['Smooth bar animation'],
				desc = L['Animate health changes smoothly instead of instantly. Uses hardware acceleration on Retail, addon smoothing on Classic.'],
				type = 'toggle',
				order = 2,
			},
			cutawayEnabled = {
				name = L['Cutaway health effect'],
				desc = L['Show a fading ghost bar when taking damage to visualize health loss'],
				type = 'toggle',
				order = 3,
				get = function()
					return UF.CurrentSettings[frameName].elements.Health.cutaway and UF.CurrentSettings[frameName].elements.Health.cutaway.enabled or false
				end,
				set = function(_, val)
					if not UF.CurrentSettings[frameName].elements.Health.cutaway then
						UF.CurrentSettings[frameName].elements.Health.cutaway = {}
					end
					UF.CurrentSettings[frameName].elements.Health.cutaway.enabled = val
					if not UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements.Health.cutaway then
						UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements.Health.cutaway = {}
					end
					UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements.Health.cutaway.enabled = val
					UF.Unit[frameName]:ElementUpdate('Health')
				end,
			},
			healthprediction = {
				name = L['Health prediction'],
				type = 'toggle',
				order = 5,
			},
			Dispel = {
				name = L['Dispel highlight'],
				type = 'toggle',
				order = 5,
			},
			textures = {
				name = L['Bar Textures'],
				type = 'group',
				inline = true,
				order = 6,
				args = {
					texture = {
						type = 'select',
						dialogControl = 'LSM30_Statusbar',
						order = 1,
						width = 'double',
						name = L['Health Bar Texture'],
						values = SUI.Lib.LSM:HashTable('statusbar'),
					},
					healPredictionTexture = {
						type = 'select',
						dialogControl = 'LSM30_Statusbar',
						order = 2,
						width = 'double',
						name = L['Heal Prediction Texture'],
						desc = L['Texture used for incoming heal prediction bars'],
						values = SUI.Lib.LSM:HashTable('statusbar'),
					},
					absorbTexture = {
						type = 'select',
						dialogControl = 'LSM30_Statusbar',
						order = 3,
						width = 'double',
						name = L['Damage Absorb Texture'],
						desc = L['Texture used for damage absorb bars (shields)'],
						values = SUI.Lib.LSM:HashTable('statusbar'),
					},
					healAbsorbTexture = {
						type = 'select',
						dialogControl = 'LSM30_Statusbar',
						order = 4,
						width = 'double',
						name = L['Heal Absorb Texture'],
						desc = L['Texture used for heal absorb bars'],
						values = SUI.Lib.LSM:HashTable('statusbar'),
					},
				},
			},
			coloring = {
				name = L['Color health bar by:'],
				desc = L['The below options are in order of wich they apply'],
				order = 10,
				inline = true,
				type = 'group',
				args = {
					colorTapping = {
						name = L['Tapped'],
						desc = "Color's the bar if the unit isn't tapped by the player",
						type = 'toggle',
						order = 1,
					},
					colorDisconnected = {
						name = L['Disconnected'],
						desc = L['Color the bar if the player is offline'],
						type = 'toggle',
						order = 2,
					},
					colorClass = {
						name = L['Class'],
						desc = L['Color the bar based on unit class'],
						type = 'toggle',
						order = 3,
					},
					colorReaction = {
						name = L['Reaction'],
						desc = "color the bar based on the player's reaction towards the player.",
						type = 'toggle',
						order = 4,
					},
					colorSmooth = {
						name = L['Smooth'],
						desc = "color the bar with a smooth gradient based on the player's current health percentage",
						type = 'toggle',
						order = 5,
					},
				},
			},
		},
	}

	-- Add additional heal prediction/absorb color options to the BarColors group
	if OptionSet.args.BarColors then
		OptionSet.args.BarColors.args.healPredictionColor = {
			name = L['Heal prediction color'],
			desc = L['Color for incoming heal prediction bars'],
			type = 'color',
			order = 3,
			hasAlpha = true,
			disabled = function()
				return not UF.CurrentSettings[frameName].elements.Health.customColors.useCustom
			end,
		}
		OptionSet.args.BarColors.args.absorbColor = {
			name = L['Damage absorb color'],
			desc = L['Color for damage absorb bars (shields)'],
			type = 'color',
			order = 4,
			hasAlpha = true,
			disabled = function()
				return not UF.CurrentSettings[frameName].elements.Health.customColors.useCustom
			end,
		}
		OptionSet.args.BarColors.args.healAbsorbColor = {
			name = L['Heal absorb color'],
			desc = L['Color for heal absorb bars'],
			type = 'color',
			order = 5,
			hasAlpha = true,
			disabled = function()
				return not UF.CurrentSettings[frameName].elements.Health.customColors.useCustom
			end,
		}
	end

	if not UF.Unit:isFriendly(frameName) then
		OptionSet.args.general.args.Dispel.hidden = true
	end

	UF.Options:AddDynamicText(frameName, OptionSet, 'Health')
end

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = true,
	height = 40,
	width = false,
	FrameLevel = 4,
	FrameStrata = 'BACKGROUND',
	reverseFill = false,
	smoothAnimation = false,
	cutaway = {
		enabled = false,
		duration = 0.75,
		color = { 0.5, 0, 0, 0.5 }, -- Dark red ghost
	},
	texture = 'SpartanUI Default',
	healPredictionTexture = 'Blizzard', -- Incoming heals texture
	absorbTexture = 'Blizzard Shield', -- Damage absorb (shields) texture
	healAbsorbTexture = 'Blizzard Absorb', -- Heal absorb texture
	colorReaction = true,
	colorSmooth = false,
	colorClass = true,
	colorTapping = true,
	colorDisconnected = true,
	bg = {
		enabled = true,
		color = { 1, 1, 1, 0.2 },
		useClassColor = false,
		classColorAlpha = 0.2,
	},
	customColors = {
		useCustom = false,
		barColor = { 0, 1, 0, 1 },
		healPredictionColor = { 0.0, 0.659, 0.608, 0.7 }, -- Blizzard's teal-green
		absorbColor = { 1, 1, 1, 0.8 }, -- White for shield texture visibility
		healAbsorbColor = { 0.7, 0.0, 0.3, 0.8 }, -- Reddish-purple
	},
	text = {
		['1'] = {
			enabled = true,
			text = '[SUIHealth(dynamic,displayDead)][ / $>SUIHealth(max,dynamic,hideDead)]',
			position = {
				anchor = 'CENTER',
				x = 0,
				y = 0,
			},
		},
		['2'] = {
			text = '[perhp]%',
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

UF.Elements:Register('Health', Build, Update, Options, Settings)
