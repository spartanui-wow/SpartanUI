-- Original work by Astromech
-- Rewritten based on Auras by wutname1
local _, ns = ...
local oUF = ns.oUF

local VISIBLE = 1
local HIDDEN = 0

local min, wipe, pairs, tinsert = min, wipe, pairs, tinsert
local CreateFrame = CreateFrame
local UnitIsUnit = UnitIsUnit

local function createAuraIcon(element, index)
	local button = CreateFrame('Button', element:GetName() .. 'Button' .. index, element)
	button:EnableMouse(false)
	button:Hide()

	local cd = CreateFrame('Cooldown', '$parentCooldown', button, 'CooldownFrameTemplate')
	cd:SetAllPoints()
	cd:SetReverse(true)
	cd:SetDrawBling(false)
	cd:SetDrawEdge(false)

	local icon = button:CreateTexture(nil, 'ARTWORK')
	icon:SetAllPoints()

	local countFrame = CreateFrame('Frame', nil, button)
	countFrame:SetAllPoints(button)
	countFrame:SetFrameLevel(cd:GetFrameLevel() + 1)

	local count = countFrame:CreateFontString(nil, 'OVERLAY', 'NumberFontNormal')
	count:SetPoint('BOTTOMRIGHT', countFrame, 'BOTTOMRIGHT', -1, 0)

	local overlay = button:CreateTexture(nil, 'OVERLAY')
	overlay:SetTexture([[Interface\Buttons\UI-Debuff-Overlays]])
	overlay:SetAllPoints()
	overlay:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)

	button.overlay = overlay
	button.icon = icon
	button.count = count
	button.cd = cd

	if element.PostCreateIcon then
		element:PostCreateIcon(button)
	end

	return button
end

local function customFilter(element, _, button, AuraData)
	local setting = element.watched[button.spellID]
	if not setting then
		return false
	end

	button.onlyShowMissing = setting.onlyShowMissing
	button.anyUnit = setting.anyUnit

	if setting.enabled and ((not setting.anyUnit and button.isPlayer) or (setting.anyUnit and button.castByPlayer)) then
		return not setting.onlyShowMissing
	end

	return false
end

local function getIcon(element, visible, offset)
	local position = visible + offset + 1
	local button = element[position]

	if not button then
		button = (element.CreateIcon or createAuraIcon)(element, position)

		tinsert(element, button)
		element.createdIcons = element.createdIcons + 1
	end

	return button, position
end

local function handleElements(element, unit, button, setting, icon, count, duration, expiration, isDebuff, debuffType, isStealable, modRate)
	if button.cd then
		if duration and duration > 0 then
			button.cd:SetCooldown(expiration - duration, duration, modRate)
			button.cd:Show()
		else
			button.cd:Hide()
		end
	end

	if button.stealable then
		if not isDebuff and isStealable and element.showStealableBuffs and not UnitIsUnit(unit, 'player') then
			button.stealable:Show()
		else
			button.stealable:Hide()
		end
	end

	if button.count then
		if count and count > 1 then
			button.count:SetText(count)
		else
			button.count:SetText()
		end
	end

	if button.overlay then
		if element.showType or (isDebuff and element.showDebuffType) or (not isDebuff and element.showBuffType) then
			local color = element.__owner.colors.debuff[debuffType] or element.__owner.colors.debuff.none

			button.overlay:SetVertexColor(color[1], color[2], color[3])
			button.overlay:Show()
		else
			button.overlay:Hide()
		end
	end

	if button.icon then
		button.icon:SetTexture(icon)
	end

	button.setting = setting

	if not setting.sizeOffset or setting.sizeOffset == 0 then
		button:SetSize(element.size, element.size)
	else
		button:SetSize(setting.sizeOffset + element.size, setting.sizeOffset + element.size)
	end

	button:Show()
	button:ClearAllPoints()
	button:SetPoint(setting.point, setting.xOffset, setting.yOffset)
end

local missing = {}
local function preOnlyMissing(element)
	wipe(missing)

	for spellID, setting in pairs(element.watched) do
		if setting.onlyShowMissing then
			missing[spellID] = setting
		end
	end
end

local function postOnlyMissing(element, unit, offset)
	local visible = 0
	for spellID, setting in pairs(missing) do
		local button, position = getIcon(element, visible, offset)

		button.spellID = spellID

		local icon = C_Spell.GetSpellTexture(spellID)
		handleElements(element, unit, button, setting, icon)

		if element.PostUpdateIcon then
			element:PostUpdateIcon(unit, button, nil, position)
		end

		visible = visible + 1
	end

	return visible
end

local function updateIcon(element, unit, index, offset, filter, isDebuff, visible)
	-- Validate unit token before calling GetAuraDataByIndex
	-- API does not accept player/pet names or invalid tokens
	local isValidUnit = unit and type(unit) == 'string' and (unit:match('^[a-z]+%d*$') or unit == 'player' or unit == 'pet' or unit == 'target' or unit == 'focus')

	if not isValidUnit then
		-- Invalid unit token (probably a player/pet name), skip this icon
		-- Debug: Log the invalid unit for investigation
		if SUI and SUI.logger then
			SUI.logger.warning('AuraWatch: Invalid unit token detected: ' .. tostring(unit))
		end
		return
	end

	local AuraData = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)

	if not AuraData then
		return
	end

	-- In Retail instanced content, aura data fields are "secret values" that cannot be
	-- read, compared, or tested as booleans. Use SUI.BlizzAPI wrappers for version safety.
	local BlizzAPI = SUI and SUI.BlizzAPI
	local isSecret = BlizzAPI and BlizzAPI.issecretvalue(AuraData.spellId) or false

	local button, position = getIcon(element, visible, offset)

	if isSecret then
		-- Secret values: only set safe defaults, skip filtering
		button.caster = nil
		button.filter = filter
		button.spellID = nil
		button.isDebuff = isDebuff
		button.castByPlayer = nil
		button.isPlayer = nil
		button:SetID(index)
		-- Cannot filter or match watched spells with secret data, skip this aura
		return HIDDEN
	end

	button.caster = AuraData.sourceUnit
	button.filter = filter
	button.spellID = AuraData.spellId
	button.isDebuff = isDebuff
	button.castByPlayer = AuraData.isFromPlayerOrPlayerPet
	button.isPlayer = AuraData.sourceUnit == 'player'

	button:SetID(index)

	local show = (element.CustomFilter or customFilter)(element, unit, button, AuraData)

	local setting = element.watched[AuraData.spellId]
	if setting and setting.onlyShowMissing then
		missing[AuraData.spellId] = nil
	end

	if show then
		handleElements(element, unit, button, setting, AuraData.icon, AuraData.charges or 1, AuraData.duration, AuraData.expirationTime, isDebuff, AuraData.isStealable, AuraData.timeMod)

		if element.PostUpdateIcon then
			element:PostUpdateIcon(unit, button, index, position, AuraData.duration, AuraData.expirationTime, AuraData.isStealable)
		end

		return VISIBLE
	else
		return HIDDEN
	end
end

local function filterIcons(element, unit, filter, limit, isDebuff, offset, dontHide)
	if not offset then
		offset = 0
	end

	local index, visible, hidden = 1, 0, 0
	while visible < limit do
		local result = updateIcon(element, unit, index, offset, filter, isDebuff, visible)
		if not result then
			break
		elseif result == VISIBLE then
			visible = visible + 1
		elseif result == HIDDEN then
			hidden = hidden + 1
		end

		index = index + 1
	end

	if not dontHide then
		for i = visible + offset + 1, #element do
			element[i]:Hide()
		end
	end

	return visible, hidden
end

local function UpdateAuras(self, event, unit, isFullUpdate, updatedAuras)
	-- Validate event unit token - allows update even if self.unit is invalid (player name)
	-- This handles the case where frames have invalid unit tokens but events provide correct ones
	local isValidEventUnit = unit and type(unit) == 'string' and (unit:match('^[a-z]+%d*$') or unit == 'player' or unit == 'pet' or unit == 'target' or unit == 'focus')

	if not unit then
		return
	end

	-- If event unit is valid, use it (even if self.unit doesn't match)
	-- If event unit is invalid, require exact match with self.unit
	if not isValidEventUnit and self.unit ~= unit then
		return
	end

	local element = self.AuraWatch
	if element then
		if element.PreUpdate then
			element:PreUpdate(unit)
		end

		preOnlyMissing(element)

		local numBuffs = element.numBuffs or 32
		local numDebuffs = element.numDebuffs or 16
		local numAuras = element.numTotal or (numBuffs + numDebuffs)

		local visibleBuffs, hiddenBuffs = filterIcons(element, unit, element.buffFilter or element.filter or 'HELPFUL', min(numBuffs, numAuras), nil, 0, true)
		local visibleDebuffs, hiddenDebuffs = filterIcons(element, unit, element.buffFilter or element.filter or 'HARMFUL', min(numDebuffs, numAuras - visibleBuffs), true, visibleBuffs)

		element.visibleDebuffs = visibleDebuffs
		element.visibleBuffs = visibleBuffs

		element.visibleAuras = visibleBuffs + visibleDebuffs

		local visibleMissing = postOnlyMissing(element, unit, element.visibleAuras)

		element.allAuras = visibleBuffs + visibleDebuffs + hiddenBuffs + hiddenDebuffs + visibleMissing

		if element.PostUpdate then
			element:PostUpdate(unit)
		end
	end
end

local function Update(self, event, unit)
	-- Validate event unit token - allows update even if self.unit is invalid (player name)
	local isValidEventUnit = unit and type(unit) == 'string' and (unit:match('^[a-z]+%d*$') or unit == 'player' or unit == 'pet' or unit == 'target' or unit == 'focus')

	-- If event unit is valid, use it (even if self.unit doesn't match)
	-- If event unit is invalid, require exact match with self.unit
	if not unit or (not isValidEventUnit and self.unit ~= unit) then
		return
	end

	UpdateAuras(self, event, unit)
end

local function ForceUpdate(element)
	return Update(element.__owner, 'ForceUpdate', element.__owner.unit)
end

local function SetNewTable(element, table)
	element.watched = table or {}
end

local function Enable(self)
	local element = self.AuraWatch
	if element then
		element.__owner = self
		element.SetNewTable = SetNewTable
		element.ForceUpdate = ForceUpdate

		element.watched = element.watched or {}
		element.createdIcons = element.createdIcons or 0
		element.anchoredIcons = 0
		element.size = 8

		self:RegisterEvent('UNIT_AURA', UpdateAuras)

		element:Show()

		return true
	end
end

local function Disable(self)
	if self.AuraWatch then
		self:UnregisterEvent('UNIT_AURA', UpdateAuras)

		if self.AuraWatch then
			self.AuraWatch:Hide()
		end
	end
end

oUF:AddElement('AuraWatch', Update, Enable, Disable)
