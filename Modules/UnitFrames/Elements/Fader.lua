local UF, L = SUI.UF, SUI.L
local canAccess = SUI.BlizzAPI.canaccessvalue

-- Evaluate whether the frame should be at full alpha based on active triggers
---@param frame table
---@param DB table
---@return boolean shouldShow true if any trigger wants the frame fully visible
local function EvaluateTriggers(frame, DB)
	local unit = frame.unit
	if not unit then
		return true
	end

	-- Combat trigger
	if DB.combat then
		local inCombat = UnitAffectingCombat(unit)
		local playerCombat = UnitAffectingCombat('player')
		if (canAccess(inCombat) and inCombat) or (canAccess(playerCombat) and playerCombat) then
			return true
		end
	end

	-- Unit has a target (player is targeting something)
	if DB.playerTarget then
		if unit == 'player' and UnitExists('target') then
			return true
		end
	end

	-- Unit is casting
	if DB.casting then
		if UnitCastingInfo(unit) or UnitChannelInfo(unit) then
			return true
		end
	end

	-- Health threshold - show when health drops below percentage
	if DB.health then
		local cur = UnitHealth(unit)
		local max = UnitHealthMax(unit)
		if cur and canAccess(cur) and max and canAccess(max) and max > 0 then
			local pct = cur / max
			if pct < (DB.healthThreshold or 1.0) then
				return true
			end
		end
	end

	-- Power threshold - show when power drops below percentage
	if DB.power then
		local cur = UnitPower(unit)
		local max = UnitPowerMax(unit)
		if cur and canAccess(cur) and max and canAccess(max) and max > 0 then
			local pct = cur / max
			if pct < (DB.powerThreshold or 0.5) then
				return true
			end
		end
	end

	-- Vehicle/dynamicflight
	if DB.vehicle then
		if UnitInVehicle(unit) then
			return true
		end
	end

	-- No triggers fired - frame should be faded
	return false
end

---@param frame table
---@param DB table
local function ApplyAlpha(frame, DB)
	local targetAlpha
	local shouldShow = EvaluateTriggers(frame, DB)

	-- Hover always overrides to maxAlpha
	if frame._faderHovered then
		if DB.hover then
			targetAlpha = DB.maxAlpha
		end
	end

	if not targetAlpha then
		targetAlpha = shouldShow and DB.maxAlpha or DB.minAlpha
	end

	-- Combine with range if range is active
	if frame.Range and frame._faderOutOfRange then
		local rangeAlpha = frame.Range.outsideAlpha or 0.3
		targetAlpha = math.min(targetAlpha, rangeAlpha)
	end

	-- Apply with smooth transition if enabled
	if DB.smooth and frame._faderAnim then
		local currentAlpha = frame:GetAlpha()
		if math.abs(currentAlpha - targetAlpha) > 0.01 then
			frame._faderAnim:SetFromAlpha(currentAlpha)
			frame._faderAnim:SetToAlpha(targetAlpha)
			frame._faderAnim:SetDuration(DB.smoothSpeed or 0.3)
			if frame._faderAnimGroup:IsPlaying() then
				frame._faderAnimGroup:Stop()
			end
			frame._faderAnimGroup:Play()
		end
	else
		frame:SetAlpha(targetAlpha)
	end

	frame._faderTargetAlpha = targetAlpha
end

-- OnUpdate throttle for periodic re-evaluation
local THROTTLE_INTERVAL = 0.2
local function OnUpdate(frame, elapsed)
	frame._faderElapsed = (frame._faderElapsed or 0) + elapsed
	if frame._faderElapsed < THROTTLE_INTERVAL then
		return
	end
	frame._faderElapsed = 0

	local DB = frame._faderDB
	if not DB or not DB.enabled then
		return
	end

	ApplyAlpha(frame, DB)
end

---@param frame table
---@param DB table
local function Build(frame, DB)
	-- Create animation group for smooth transitions
	local animGroup = frame:CreateAnimationGroup()
	local anim = animGroup:CreateAnimation('Alpha')
	anim:SetFromAlpha(1)
	anim:SetToAlpha(1)
	anim:SetDuration(0.3)
	anim:SetSmoothing('IN_OUT')
	animGroup:SetScript('OnFinished', function()
		frame:SetAlpha(anim:GetToAlpha())
	end)

	frame._faderAnimGroup = animGroup
	frame._faderAnim = anim
	frame._faderDB = DB
	frame._faderElapsed = 0
	frame._faderOutOfRange = false
	frame._faderHovered = false

	-- Override Range element to integrate with fader
	if frame.Range then
		frame.Range.Override = function(self, event)
			local element = self.Range
			local unit = self.unit

			-- oUF's evalUnitAndUpdate runs a full element pass even when the
			-- frame has no unit yet, so this cannot assume one exists.
			if not unit then
				self._faderOutOfRange = false
				return
			end

			local inRange = true
			local connected = UnitIsConnected(unit)
			local inParty = UnitInParty(unit)
			local isEligible = false
			if canAccess(connected) and canAccess(inParty) then
				isEligible = connected and inParty
			end
			if isEligible then
				inRange = UnitInRange(unit)
			end
			if canAccess(inRange) then
				self._faderOutOfRange = not inRange
			else
				self._faderOutOfRange = false
			end

			local faderDB = self._faderDB
			if faderDB and faderDB.enabled then
				ApplyAlpha(self, faderDB)
			else
				-- Fader not active, apply range alpha normally
				if isEligible then
					if SUI.IsRetail then
						self:SetAlphaFromBoolean(inRange, element.insideAlpha, element.outsideAlpha)
					else
						if inRange then
							self:SetAlpha(element.insideAlpha)
						else
							self:SetAlpha(element.outsideAlpha)
						end
					end
				else
					self:SetAlpha(element.insideAlpha)
				end
			end

			if element.PostUpdate then
				return element:PostUpdate(self, inRange, isEligible)
			end
		end
	end

	-- Hover detection
	frame:HookScript('OnEnter', function(self)
		self._faderHovered = true
		local faderDB = self._faderDB
		if faderDB and faderDB.enabled and faderDB.hover then
			ApplyAlpha(self, faderDB)
		end
	end)
	frame:HookScript('OnLeave', function(self)
		self._faderHovered = false
		local faderDB = self._faderDB
		if faderDB and faderDB.enabled and faderDB.hover then
			ApplyAlpha(self, faderDB)
		end
	end)

	-- Register for combat events via OnUpdate throttle
	frame:HookScript('OnUpdate', OnUpdate)

	-- Set initial state
	if DB.enabled then
		ApplyAlpha(frame, DB)
	end
end

---@param frame table
---@param settings? table
local function Update(frame, settings)
	local DB = settings or (frame.Fader and frame.Fader.DB) or frame._faderDB
	if not DB then
		return
	end

	frame._faderDB = DB

	if DB.enabled then
		ApplyAlpha(frame, DB)
	else
		-- Disabled: reset to full alpha (range element handles its own alpha)
		if frame._faderAnimGroup and frame._faderAnimGroup:IsPlaying() then
			frame._faderAnimGroup:Stop()
		end
		frame:SetAlpha(1)
	end
end

---@param unitName string
---@param OptionSet AceConfig.OptionsTable
local function Options(unitName, OptionSet)
	local ElementSettings = UF.CurrentSettings[unitName].elements.Fader

	local function OptUpdate(option, val)
		UF.CurrentSettings[unitName].elements.Fader[option] = val
		UF.DB.UserSettings[UF:GetPresetForFrame(unitName)][unitName].elements.Fader[option] = val
		UF.Unit[unitName]:ElementUpdate('Fader')
	end

	OptionSet.args.general = {
		name = '',
		type = 'group',
		inline = true,
		order = 1,
		args = {
			minAlpha = {
				name = L['Minimum Alpha'],
				desc = L['How transparent the frame becomes when faded out'],
				type = 'range',
				order = 1,
				min = 0,
				max = 1,
				step = 0.05,
				get = function()
					return ElementSettings.minAlpha or 0.2
				end,
				set = function(_, val)
					OptUpdate('minAlpha', val)
				end,
			},
			maxAlpha = {
				name = L['Maximum Alpha'],
				desc = L['How visible the frame is when fully shown'],
				type = 'range',
				order = 2,
				min = 0.1,
				max = 1,
				step = 0.05,
				get = function()
					return ElementSettings.maxAlpha or 1
				end,
				set = function(_, val)
					OptUpdate('maxAlpha', val)
				end,
			},
			smooth = {
				name = L['Smooth Transitions'],
				desc = L['Animate alpha changes smoothly instead of instantly'],
				type = 'toggle',
				order = 3,
				get = function()
					return ElementSettings.smooth
				end,
				set = function(_, val)
					OptUpdate('smooth', val)
				end,
			},
			smoothSpeed = {
				name = L['Transition Speed'],
				desc = L['How fast the fade animation plays (seconds)'],
				type = 'range',
				order = 4,
				min = 0.1,
				max = 1.0,
				step = 0.05,
				hidden = function()
					return not ElementSettings.smooth
				end,
				get = function()
					return ElementSettings.smoothSpeed or 0.3
				end,
				set = function(_, val)
					OptUpdate('smoothSpeed', val)
				end,
			},
		},
	}

	OptionSet.args.triggers = {
		name = L['Show frame when...'],
		desc = L['The frame shows at full alpha when ANY of these conditions is true. Otherwise it fades to minimum alpha.'],
		type = 'group',
		inline = true,
		order = 10,
		args = {
			combat = {
				name = L['In combat'],
				desc = L['Show at full alpha when you or the unit are in combat'],
				type = 'toggle',
				order = 1,
				get = function()
					return ElementSettings.combat
				end,
				set = function(_, val)
					OptUpdate('combat', val)
				end,
			},
			hover = {
				name = L['Mouse hover'],
				desc = L['Show at full alpha when hovering over the frame'],
				type = 'toggle',
				order = 2,
				get = function()
					return ElementSettings.hover
				end,
				set = function(_, val)
					OptUpdate('hover', val)
				end,
			},
			playerTarget = {
				name = L['Has target'],
				desc = L['Show at full alpha when you have a target selected'],
				type = 'toggle',
				order = 3,
				get = function()
					return ElementSettings.playerTarget
				end,
				set = function(_, val)
					OptUpdate('playerTarget', val)
				end,
			},
			casting = {
				name = L['Casting'],
				desc = L['Show at full alpha when the unit is casting or channeling'],
				type = 'toggle',
				order = 4,
				get = function()
					return ElementSettings.casting
				end,
				set = function(_, val)
					OptUpdate('casting', val)
				end,
			},
			health = {
				name = L['Health below threshold'],
				desc = L['Show at full alpha when health drops below a percentage'],
				type = 'toggle',
				order = 5,
				get = function()
					return ElementSettings.health
				end,
				set = function(_, val)
					OptUpdate('health', val)
				end,
			},
			healthThreshold = {
				name = L['Health threshold'],
				desc = L['Show when health is below this percentage (1.0 = 100%)'],
				type = 'range',
				order = 6,
				min = 0.1,
				max = 1.0,
				step = 0.05,
				isPercent = true,
				hidden = function()
					return not ElementSettings.health
				end,
				get = function()
					return ElementSettings.healthThreshold or 1.0
				end,
				set = function(_, val)
					OptUpdate('healthThreshold', val)
				end,
			},
			power = {
				name = L['Power below threshold'],
				desc = L['Show at full alpha when power drops below a percentage'],
				type = 'toggle',
				order = 7,
				get = function()
					return ElementSettings.power
				end,
				set = function(_, val)
					OptUpdate('power', val)
				end,
			},
			powerThreshold = {
				name = L['Power threshold'],
				desc = L['Show when power is below this percentage (0.5 = 50%)'],
				type = 'range',
				order = 8,
				min = 0.1,
				max = 1.0,
				step = 0.05,
				isPercent = true,
				hidden = function()
					return not ElementSettings.power
				end,
				get = function()
					return ElementSettings.powerThreshold or 0.5
				end,
				set = function(_, val)
					OptUpdate('powerThreshold', val)
				end,
			},
			vehicle = {
				name = L['In vehicle'],
				desc = L['Show at full alpha when in a vehicle'],
				type = 'toggle',
				order = 9,
				get = function()
					return ElementSettings.vehicle
				end,
				set = function(_, val)
					OptUpdate('vehicle', val)
				end,
			},
		},
	}
end

---@type SUI.UF.Elements.Settings
local Settings = {
	enabled = false,
	minAlpha = 0.2,
	maxAlpha = 1,
	smooth = true,
	smoothSpeed = 0.3,
	combat = true,
	hover = true,
	playerTarget = false,
	casting = false,
	health = false,
	healthThreshold = 1.0,
	power = false,
	powerThreshold = 0.5,
	vehicle = false,
	config = {
		NoBulkUpdate = true,
	},
}
UF.Elements:Register('Fader', Build, Update, Options, Settings)
