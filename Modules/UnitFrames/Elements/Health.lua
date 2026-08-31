local UF, L = SUI.UF, SUI.L

---@param frame table
---@param DB table
local function Build(frame, DB)
	local health = CreateFrame('StatusBar', nil, frame)
	SUI.BlizzAPI.SetFrameStrataSafe(health, DB.FrameStrata, frame)
	health:SetFrameLevel(DB.FrameLevel or 2)
	health:SetStatusBarTexture(UF:FindStatusBarTexture(DB.texture))
	health:SetSize(DB.width or frame:GetWidth(), DB.height or 20)

	if DB.orientation == 'VERTICAL' then
		health:SetOrientation('VERTICAL')
	end

	local bg = health:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints(health)
	bg:SetTexture(UF:FindStatusBarTexture(DB.texture))
	bg:SetVertexColor(unpack(DB.bg.color))
	health.bg = bg

	if DB.orientation == 'VERTICAL' then
		health:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', DB.offset or 0, 0)
		health:SetPoint('TOPLEFT', frame, 'TOPLEFT', DB.offset or 0, 0)
	else
		health:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, DB.offset or -1)
		health:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, DB.offset or -1)
	end

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
		-- Guard against secret values from WoW 12.0 combat restriction predicates
		local canAccess = SUI.BlizzAPI.canaccessvalue
		if canAccess(cur) and canAccess(prev) and canAccess(max) and cur < prev and max > 0 then
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

	-- Default smooth gradient: red -> yellow -> green
	frame.colors.smooth = { 1, 0, 0, 1, 1, 0, 0, 1, 0 }
	frame.Health.colorHealth = true

	-- Custom gradient thresholds: apply custom colors based on health percentage
	if DB.gradient and DB.gradient.enabled then
		local gradDB = DB.gradient
		frame.Health.PostUpdateColor = function(element, unit, r, g, b)
			-- Only apply gradient when not using other color modes
			if element.colorClass or element.colorReaction or element.colorSmooth then
				return
			end

			local cur = UnitHealth(unit)
			local max = UnitHealthMax(unit)
			local canAccess = SUI.BlizzAPI.canaccessvalue
			if not (cur and canAccess(cur) and max and canAccess(max) and max > 0) then
				return
			end

			local pct = cur / max
			local color
			if pct <= (gradDB.lowThreshold or 0.35) then
				color = gradDB.lowColor or { 1, 0, 0, 1 }
			elseif pct <= (gradDB.midThreshold or 0.65) then
				color = gradDB.midColor or { 1, 1, 0, 1 }
			else
				color = gradDB.highColor or { 0, 1, 0, 1 }
			end
			element:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
		end
	end

	-- Missing health gradient background
	if DB.missingHealth and DB.missingHealth.enabled then
		local mhDB = DB.missingHealth
		-- Create gradient texture for missing health
		local missingGrad = health:CreateTexture(nil, 'BACKGROUND', nil, 1)
		missingGrad:SetAllPoints(health)
		missingGrad:SetTexture(UF:FindStatusBarTexture(DB.texture))
		local lowColor = mhDB.lowColor or { 0.5, 0, 0, 0.8 }
		local highColor = mhDB.highColor or { 0.1, 0.1, 0.1, 0.4 }
		missingGrad:SetGradient('HORIZONTAL', CreateColor(lowColor[1], lowColor[2], lowColor[3], lowColor[4] or 1), CreateColor(highColor[1], highColor[2], highColor[3], highColor[4] or 1))
		frame.Health.missingGrad = missingGrad
	end

	frame.Health.DataTable = DB.text

	-- Heal prediction source mode: ALL (combined), MINE (player only), SPLIT (separate bars)
	local healSource = DB.healPredictionSource or 'ALL'
	local healPredTexture = UF:FindStatusBarTexture(DB.healPredictionTexture or 'Blizzard')
	local healColor = (DB.customColors and DB.customColors.useCustom and DB.customColors.healPredictionColor) or { 0.0, 0.659, 0.608, 0.7 }
	local othersHealColor = (DB.customColors and DB.customColors.useCustom and DB.customColors.othersHealColor) or { 0.0, 0.431, 0.369, 0.5 }

	-- Combined heals bar (used in ALL mode)
	local healingAll = CreateFrame('StatusBar', nil, frame.Health)
	healingAll:SetFrameLevel((DB.FrameLevel or 2) + 2)
	healingAll:SetPoint('TOP', frame.Health, 'TOP')
	healingAll:SetPoint('BOTTOM', frame.Health, 'BOTTOM')
	healingAll:SetPoint('LEFT', frame.Health:GetStatusBarTexture(), 'RIGHT')
	healingAll:SetStatusBarTexture(healPredTexture)
	healingAll:SetStatusBarColor(unpack(healColor))
	healingAll:SetWidth(200)

	-- Player heals bar (used in MINE or SPLIT mode)
	local healingPlayer = CreateFrame('StatusBar', nil, frame.Health)
	healingPlayer:SetFrameLevel((DB.FrameLevel or 2) + 2)
	healingPlayer:SetPoint('TOP', frame.Health, 'TOP')
	healingPlayer:SetPoint('BOTTOM', frame.Health, 'BOTTOM')
	healingPlayer:SetPoint('LEFT', frame.Health:GetStatusBarTexture(), 'RIGHT')
	healingPlayer:SetStatusBarTexture(healPredTexture)
	healingPlayer:SetStatusBarColor(unpack(healColor))
	healingPlayer:SetWidth(200)

	-- Others' heals bar (used in SPLIT mode, anchored after player heals)
	local healingOther = CreateFrame('StatusBar', nil, frame.Health)
	healingOther:SetFrameLevel((DB.FrameLevel or 2) + 2)
	healingOther:SetPoint('TOP', frame.Health, 'TOP')
	healingOther:SetPoint('BOTTOM', frame.Health, 'BOTTOM')
	healingOther:SetPoint('LEFT', healingPlayer:GetStatusBarTexture(), 'RIGHT')
	healingOther:SetStatusBarTexture(healPredTexture)
	healingOther:SetStatusBarColor(unpack(othersHealColor))
	healingOther:SetWidth(200)

	-- Hide bars not used by the selected mode
	if healSource == 'ALL' then
		healingPlayer:Hide()
		healingOther:Hide()
	elseif healSource == 'MINE' then
		healingAll:Hide()
		healingOther:Hide()
	else -- SPLIT
		healingAll:Hide()
	end

	-- Determine which bar the absorb chain follows
	local lastHealBar = healingAll
	if healSource == 'MINE' then
		lastHealBar = healingPlayer
	elseif healSource == 'SPLIT' then
		lastHealBar = healingOther
	end

	-- Absorb display mode: ATTACHED (after heals), OVERLAY (on top of health bar)
	local absorbMode = DB.absorbDisplayMode or 'ATTACHED'

	-- Damage absorb bar (shields like Power Word: Shield)
	local damageAbsorb = CreateFrame('StatusBar', nil, frame.Health)
	damageAbsorb:SetFrameLevel((DB.FrameLevel or 2) + 3)
	damageAbsorb:SetPoint('TOP', frame.Health, 'TOP')
	damageAbsorb:SetPoint('BOTTOM', frame.Health, 'BOTTOM')
	if absorbMode == 'OVERLAY' then
		damageAbsorb:SetPoint('LEFT', frame.Health:GetStatusBarTexture(), 'RIGHT')
	else
		damageAbsorb:SetPoint('LEFT', lastHealBar:GetStatusBarTexture(), 'RIGHT')
	end
	damageAbsorb:SetStatusBarTexture(UF:FindStatusBarTexture(DB.absorbTexture or 'Blizzard Shield'))
	if DB.customColors and DB.customColors.useCustom and DB.customColors.absorbColor then
		damageAbsorb:SetStatusBarColor(unpack(DB.customColors.absorbColor))
	else
		damageAbsorb:SetStatusBarColor(1, 1, 1, 0.8)
	end
	damageAbsorb:SetWidth(200)

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
		healAbsorb:SetStatusBarColor(0.7, 0.0, 0.3, 0.8)
	end
	healAbsorb:SetReverseFill(true)
	healAbsorb:SetWidth(200)

	-- Overflow indicator for damage absorbs
	local overDamageAbsorbIndicator = frame.Health:CreateTexture(nil, 'ARTWORK', nil, 2)
	overDamageAbsorbIndicator:SetPoint('TOP', frame.Health, 'TOP')
	overDamageAbsorbIndicator:SetPoint('BOTTOM', frame.Health, 'BOTTOM')
	overDamageAbsorbIndicator:SetPoint('LEFT', frame.Health, 'RIGHT', -4, 0)
	overDamageAbsorbIndicator:SetWidth(8)
	overDamageAbsorbIndicator:SetTexture([[Interface\RaidFrame\Shield-Overshield]])
	overDamageAbsorbIndicator:SetBlendMode('ADD')

	-- Overflow indicator for heal absorbs
	local overHealAbsorbIndicator = frame.Health:CreateTexture(nil, 'ARTWORK', nil, 2)
	overHealAbsorbIndicator:SetPoint('TOP', frame.Health, 'TOP')
	overHealAbsorbIndicator:SetPoint('BOTTOM', frame.Health, 'BOTTOM')
	overHealAbsorbIndicator:SetPoint('RIGHT', frame.Health, 'LEFT', 4, 0)
	overHealAbsorbIndicator:SetWidth(8)
	overHealAbsorbIndicator:SetTexture([[Interface\RaidFrame\Absorb-Overabsorb]])
	overHealAbsorbIndicator:SetBlendMode('ADD')

	-- Overflow control
	local overflowAmount = DB.healPredictionOverflow or 1.05

	-- Only the bars used by the selected heal source are attached, so the
	-- element skips the rest.
	local activeHealingAll = (healSource == 'ALL') and healingAll or nil
	local activeHealingPlayer = (healSource ~= 'ALL') and healingPlayer or nil
	local activeHealingOther = (healSource == 'SPLIT') and healingOther or nil

	-- Retail: oUF 12.1 merged prediction into the Health element, so the
	-- sub-bars hang off Health itself using capitalised names.
	frame.Health.HealingAll = activeHealingAll
	frame.Health.HealingPlayer = activeHealingPlayer
	frame.Health.HealingOther = activeHealingOther
	frame.Health.DamageAbsorb = damageAbsorb
	frame.Health.HealAbsorb = healAbsorb
	frame.Health.OverDamageAbsorbIndicator = overDamageAbsorbIndicator
	frame.Health.OverHealAbsorbIndicator = overHealAbsorbIndicator
	frame.Health.incomingHealOverflow = overflowAmount

	-- Classic: oUF_Classic still ships the standalone HealthPrediction
	-- element, which reads a table of lowercase names off the frame.
	if not SUI.IsRetail then
		frame.HealthPrediction = {
			healingAll = activeHealingAll,
			healingPlayer = activeHealingPlayer,
			healingOther = activeHealingOther,
			damageAbsorb = damageAbsorb,
			healAbsorb = healAbsorb,
			overDamageAbsorbIndicator = overDamageAbsorbIndicator,
			overHealAbsorbIndicator = overHealAbsorbIndicator,
			incomingHealOverflow = overflowAmount,
		}
	end
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
		-- A secret class token cannot be used as a table key, but the engine
		-- can still look it up, so restricted units keep their class colour.
		local color = SUI.BlizzAPI.GetClassColor(class)
		local alpha = DB.bg.classColorAlpha or 0.2
		if color then
			element.bg:SetVertexColor(color.r, color.g, color.b, alpha)
		else
			element.bg:SetVertexColor(1, 1, 1, alpha)
		end
	else
		element.bg:SetVertexColor(unpack(DB.bg.color or { 1, 1, 1, 0.2 }))
	end

	-- Update prediction bar textures and colors.
	-- Retail hangs these off the Health element; Classic keeps them in a
	-- frame.HealthPrediction table. Both reference the same bar objects, so
	-- read from whichever this flavour populated.
	do
		local pred = frame.HealthPrediction
		local healingAll = element.HealingAll or (pred and pred.healingAll)
		local healingPlayer = element.HealingPlayer or (pred and pred.healingPlayer)
		local healingOther = element.HealingOther or (pred and pred.healingOther)
		local damageAbsorb = element.DamageAbsorb or (pred and pred.damageAbsorb)
		local healAbsorb = element.HealAbsorb or (pred and pred.healAbsorb)

		local healPredTexture = UF:FindStatusBarTexture(DB.healPredictionTexture or 'Blizzard')
		local healColor = (DB.customColors and DB.customColors.useCustom and DB.customColors.healPredictionColor) or { 0.0, 0.659, 0.608, 0.7 }
		local othersHealColor = (DB.customColors and DB.customColors.useCustom and DB.customColors.othersHealColor) or { 0.0, 0.431, 0.369, 0.5 }

		if healingAll then
			healingAll:SetStatusBarTexture(healPredTexture)
			healingAll:SetStatusBarColor(unpack(healColor))
		end
		if healingPlayer then
			healingPlayer:SetStatusBarTexture(healPredTexture)
			healingPlayer:SetStatusBarColor(unpack(healColor))
		end
		if healingOther then
			healingOther:SetStatusBarTexture(healPredTexture)
			healingOther:SetStatusBarColor(unpack(othersHealColor))
		end
		if damageAbsorb then
			damageAbsorb:SetStatusBarTexture(UF:FindStatusBarTexture(DB.absorbTexture or 'Blizzard Shield'))
			if DB.customColors and DB.customColors.useCustom and DB.customColors.absorbColor then
				damageAbsorb:SetStatusBarColor(unpack(DB.customColors.absorbColor))
			else
				damageAbsorb:SetStatusBarColor(1, 1, 1, 0.8)
			end
		end
		if healAbsorb then
			healAbsorb:SetStatusBarTexture(UF:FindStatusBarTexture(DB.healAbsorbTexture or 'Blizzard Absorb'))
			if DB.customColors and DB.customColors.useCustom and DB.customColors.healAbsorbColor then
				healAbsorb:SetStatusBarColor(unpack(DB.customColors.healAbsorbColor))
			else
				healAbsorb:SetStatusBarColor(0.7, 0.0, 0.3, 0.8)
			end
		end

		local overflow = DB.healPredictionOverflow or 1.05
		element.incomingHealOverflow = overflow
		if pred then
			pred.incomingHealOverflow = overflow
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

	if DB.orientation == 'VERTICAL' then
		element:SetOrientation('VERTICAL')
		element:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', DB.offset or 0, 0)
		element:SetPoint('TOPLEFT', frame, 'TOPLEFT', DB.offset or 0, 0)
	else
		element:SetOrientation('HORIZONTAL')
		element:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, DB.offset or 0)
		element:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, DB.offset or 0)
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
			orientation = {
				name = L['Bar orientation'],
				desc = L['Set the health bar to fill horizontally or vertically'],
				type = 'select',
				order = 0.5,
				values = {
					HORIZONTAL = L['Horizontal'],
					VERTICAL = L['Vertical'],
				},
			},
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
			healPrediction = {
				name = L['Heal prediction'],
				type = 'group',
				inline = true,
				order = 8,
				args = {
					healPredictionSource = {
						name = L['Heal source display'],
						desc = L['ALL shows combined heals. MINE shows only your heals. SPLIT shows your heals and others separately.'],
						type = 'select',
						order = 1,
						values = {
							ALL = L['All combined'],
							MINE = L['Mine only'],
							SPLIT = L['Split (mine + others)'],
						},
					},
					absorbDisplayMode = {
						name = L['Absorb display mode'],
						desc = L['ATTACHED shows absorbs after the heal prediction bar. OVERLAY shows absorbs starting from the end of the health bar.'],
						type = 'select',
						order = 2,
						values = {
							ATTACHED = L['Attached (after heals)'],
							OVERLAY = L['Overlay (on health bar)'],
						},
					},
					healPredictionOverflow = {
						name = L['Heal overflow amount'],
						desc = L['How far past the end of the health bar heal predictions can extend. 1.0 = no overflow, 1.2 = 20% past the end.'],
						type = 'range',
						order = 3,
						min = 1.0,
						max = 1.5,
						step = 0.05,
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

	-- Gradient health coloring options
	local ElementSettings = UF.CurrentSettings[frameName].elements.Health
	local function GradUpdate(path, val)
		ElementSettings.gradient = ElementSettings.gradient or {}
		ElementSettings.gradient[path] = val
		local userSettings = UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements.Health
		userSettings.gradient = userSettings.gradient or {}
		userSettings.gradient[path] = val
		UF.Unit[frameName]:ElementUpdate('Health')
	end

	OptionSet.args.gradient = {
		name = L['Gradient Health Colors'],
		desc = L['Color the health bar based on 3 health thresholds with custom colors. Overrides the Smooth color mode.'],
		type = 'group',
		order = 15,
		inline = true,
		args = {
			enabled = {
				name = L['Enable gradient coloring'],
				desc = L['Use custom colors at 3 health thresholds instead of the default smooth gradient'],
				type = 'toggle',
				order = 1,
				width = 'full',
				get = function()
					return ElementSettings.gradient and ElementSettings.gradient.enabled
				end,
				set = function(_, val)
					GradUpdate('enabled', val)
				end,
			},
			lowThreshold = {
				name = L['Low health threshold'],
				desc = L['Below this percentage, use the low health color'],
				type = 'range',
				order = 2,
				min = 0.05,
				max = 0.95,
				step = 0.05,
				isPercent = true,
				hidden = function()
					return not (ElementSettings.gradient and ElementSettings.gradient.enabled)
				end,
				get = function()
					return ElementSettings.gradient and ElementSettings.gradient.lowThreshold or 0.35
				end,
				set = function(_, val)
					GradUpdate('lowThreshold', val)
				end,
			},
			midThreshold = {
				name = L['Medium health threshold'],
				desc = L['Below this percentage, use the medium health color'],
				type = 'range',
				order = 3,
				min = 0.05,
				max = 0.95,
				step = 0.05,
				isPercent = true,
				hidden = function()
					return not (ElementSettings.gradient and ElementSettings.gradient.enabled)
				end,
				get = function()
					return ElementSettings.gradient and ElementSettings.gradient.midThreshold or 0.65
				end,
				set = function(_, val)
					GradUpdate('midThreshold', val)
				end,
			},
			lowColor = {
				name = L['Low health color'],
				type = 'color',
				order = 4,
				hasAlpha = true,
				hidden = function()
					return not (ElementSettings.gradient and ElementSettings.gradient.enabled)
				end,
				get = function()
					local c = ElementSettings.gradient and ElementSettings.gradient.lowColor or { 1, 0, 0, 1 }
					return c[1], c[2], c[3], c[4]
				end,
				set = function(_, r, g, b, a)
					GradUpdate('lowColor', { r, g, b, a })
				end,
			},
			midColor = {
				name = L['Medium health color'],
				type = 'color',
				order = 5,
				hasAlpha = true,
				hidden = function()
					return not (ElementSettings.gradient and ElementSettings.gradient.enabled)
				end,
				get = function()
					local c = ElementSettings.gradient and ElementSettings.gradient.midColor or { 1, 1, 0, 1 }
					return c[1], c[2], c[3], c[4]
				end,
				set = function(_, r, g, b, a)
					GradUpdate('midColor', { r, g, b, a })
				end,
			},
			highColor = {
				name = L['High health color'],
				type = 'color',
				order = 6,
				hasAlpha = true,
				hidden = function()
					return not (ElementSettings.gradient and ElementSettings.gradient.enabled)
				end,
				get = function()
					local c = ElementSettings.gradient and ElementSettings.gradient.highColor or { 0, 1, 0, 1 }
					return c[1], c[2], c[3], c[4]
				end,
				set = function(_, r, g, b, a)
					GradUpdate('highColor', { r, g, b, a })
				end,
			},
		},
	}

	-- Missing health gradient background options
	local function MissingUpdate(path, val)
		ElementSettings.missingHealth = ElementSettings.missingHealth or {}
		ElementSettings.missingHealth[path] = val
		local userSettings = UF.DB.UserSettings[UF:GetPresetForFrame(frameName)][frameName].elements.Health
		userSettings.missingHealth = userSettings.missingHealth or {}
		userSettings.missingHealth[path] = val
		UF.Unit[frameName]:ElementUpdate('Health')
	end

	OptionSet.args.missingHealth = {
		name = L['Missing Health Color'],
		desc = L['Color the background behind the health bar to show missing health with a gradient'],
		type = 'group',
		order = 16,
		inline = true,
		args = {
			enabled = {
				name = L['Enable missing health gradient'],
				desc = L['Show a gradient background color where health is missing'],
				type = 'toggle',
				order = 1,
				width = 'full',
				get = function()
					return ElementSettings.missingHealth and ElementSettings.missingHealth.enabled
				end,
				set = function(_, val)
					MissingUpdate('enabled', val)
				end,
			},
			lowColor = {
				name = L['Low health background'],
				desc = L['Background color when health is very low'],
				type = 'color',
				order = 2,
				hasAlpha = true,
				hidden = function()
					return not (ElementSettings.missingHealth and ElementSettings.missingHealth.enabled)
				end,
				get = function()
					local c = ElementSettings.missingHealth and ElementSettings.missingHealth.lowColor or { 0.5, 0, 0, 0.8 }
					return c[1], c[2], c[3], c[4]
				end,
				set = function(_, r, g, b, a)
					MissingUpdate('lowColor', { r, g, b, a })
				end,
			},
			highColor = {
				name = L['Full health background'],
				desc = L['Background color when health is nearly full'],
				type = 'color',
				order = 3,
				hasAlpha = true,
				hidden = function()
					return not (ElementSettings.missingHealth and ElementSettings.missingHealth.enabled)
				end,
				get = function()
					local c = ElementSettings.missingHealth and ElementSettings.missingHealth.highColor or { 0.1, 0.1, 0.1, 0.4 }
					return c[1], c[2], c[3], c[4]
				end,
				set = function(_, r, g, b, a)
					MissingUpdate('highColor', { r, g, b, a })
				end,
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
	orientation = 'HORIZONTAL',
	reverseFill = false,
	smoothAnimation = false,
	cutaway = {
		enabled = false,
		duration = 0.75,
		color = { 0.5, 0, 0, 0.5 }, -- Dark red ghost
	},
	texture = 'SpartanUI Default',
	healPredictionTexture = 'Blizzard', -- Incoming heals texture
	healPredictionSource = 'ALL', -- ALL, MINE, SPLIT
	healPredictionOverflow = 1.05,
	absorbTexture = 'Blizzard Shield', -- Damage absorb (shields) texture
	absorbDisplayMode = 'ATTACHED', -- ATTACHED, OVERLAY
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
	gradient = {
		enabled = false,
		lowThreshold = 0.35,
		midThreshold = 0.65,
		lowColor = { 1, 0, 0, 1 },
		midColor = { 1, 1, 0, 1 },
		highColor = { 0, 1, 0, 1 },
	},
	missingHealth = {
		enabled = false,
		lowColor = { 0.5, 0, 0, 0.8 },
		highColor = { 0.1, 0.1, 0.1, 0.4 },
	},
	customColors = {
		useCustom = false,
		barColor = { 0, 1, 0, 1 },
		healPredictionColor = { 0.0, 0.659, 0.608, 0.7 }, -- Blizzard's teal-green
		othersHealColor = { 0.0, 0.431, 0.369, 0.5 }, -- Dimmer teal for others' heals
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
